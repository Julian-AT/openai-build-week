from __future__ import annotations

import asyncio
import json
import secrets
from dataclasses import dataclass
from typing import TYPE_CHECKING, cast

from fastapi import FastAPI, Request, Security
from fastapi.exceptions import RequestValidationError
from fastapi.responses import JSONResponse
from fastapi.security import HTTPAuthorizationCredentials, HTTPBearer

if TYPE_CHECKING:
    from collections.abc import Awaitable, Callable

    from starlette.responses import Response
    from starlette.types import ASGIApp, Message, Receive, Scope, Send

from .contracts import HealthResponse, InferenceJob, InferenceJobResponse, WorkerReadiness
from .providers import InferenceProvider, ProviderUnavailableError
from .scheduler import SingleInferenceLane

MAX_TOKEN_BYTES = 512
MAX_CONFIGURED_BODY_BYTES = 10_000_000
MAX_DEADLINE_SECONDS = 120


@dataclass(frozen=True, slots=True)
class InferenceAppOptions:
    token: str
    provider: InferenceProvider
    maximum_body_bytes: int = 3_500_000
    deadline_seconds: float = 30.0


class WorkerProtocolError(Exception):
    def __init__(self, status_code: int, code: str) -> None:
        super().__init__(code)
        self.status_code = status_code
        self.code = code


class BodyTooLargeError(Exception):
    pass


class BodyLimitMiddleware:
    def __init__(self, app: ASGIApp, maximum_bytes: int) -> None:
        self.app = app
        self.maximum_bytes = maximum_bytes

    async def __call__(self, scope: Scope, receive: Receive, send: Send) -> None:
        if scope["type"] != "http":
            await self.app(scope, receive, send)
            return
        raw_headers = cast("list[tuple[bytes, bytes]]", scope["headers"])
        headers = {key.lower(): value for key, value in raw_headers}
        declared = headers.get(b"content-length")
        if declared is not None:
            try:
                if int(declared) > self.maximum_bytes or int(declared) < 0:
                    await send_json_error(send, 413, "payload_too_large")
                    return
            except ValueError:
                await send_json_error(send, 400, "invalid_request")
                return

        received = 0
        response_started = False

        async def bounded_receive() -> Message:
            nonlocal received
            message = await receive()
            if message["type"] == "http.request":
                body = cast("bytes", message.get("body", b""))
                received += len(body)
                if received > self.maximum_bytes:
                    raise BodyTooLargeError
            return message

        async def tracked_send(message: Message) -> None:
            nonlocal response_started
            if message["type"] == "http.response.start":
                response_started = True
            await send(message)

        try:
            await self.app(scope, bounded_receive, tracked_send)
        except BodyTooLargeError:
            if not response_started:
                await send_json_error(send, 413, "payload_too_large")


async def send_json_error(send: Send, status: int, code: str) -> None:
    body = json.dumps({"error": code}, separators=(",", ":")).encode("utf-8")
    await send(
        {
            "type": "http.response.start",
            "status": status,
            "headers": [
                (b"content-type", b"application/json"),
                (b"content-length", str(len(body)).encode("ascii")),
                (b"cache-control", b"no-store"),
                (b"x-content-type-options", b"nosniff"),
            ],
        }
    )
    await send({"type": "http.response.body", "body": body})


def create_inference_app(options: InferenceAppOptions) -> FastAPI:
    if not options.token or len(options.token.encode("utf-8")) > MAX_TOKEN_BYTES:
        raise ValueError("invalid inference token")
    if options.maximum_body_bytes < 1 or options.maximum_body_bytes > MAX_CONFIGURED_BODY_BYTES:
        raise ValueError("invalid maximum body bytes")
    if options.deadline_seconds <= 0 or options.deadline_seconds > MAX_DEADLINE_SECONDS:
        raise ValueError("invalid inference deadline")

    app = FastAPI(docs_url=None, redoc_url=None, openapi_url=None)
    app.add_middleware(BodyLimitMiddleware, maximum_bytes=options.maximum_body_bytes)
    bearer = HTTPBearer(auto_error=False)
    lane = SingleInferenceLane()

    def require_bearer(credentials: HTTPAuthorizationCredentials | None) -> None:
        if (
            credentials is None
            or credentials.scheme != "Bearer"
            or not secrets.compare_digest(credentials.credentials, options.token)
        ):
            raise WorkerProtocolError(401, "unauthorized")

    async def authorize(
        credentials: HTTPAuthorizationCredentials | None = Security(bearer),
    ) -> None:
        require_bearer(credentials)

    async def authorize_json(
        request: Request,
        credentials: HTTPAuthorizationCredentials | None = Security(bearer),
    ) -> None:
        require_bearer(credentials)
        content_type = request.headers.get("content-type", "").split(";", maxsplit=1)[0]
        if content_type.strip().lower() != "application/json":
            raise WorkerProtocolError(415, "unsupported_media_type")

    @app.exception_handler(WorkerProtocolError)
    async def handle_protocol_error(_request: Request, error: WorkerProtocolError) -> JSONResponse:
        return JSONResponse({"error": error.code}, status_code=error.status_code)

    @app.exception_handler(RequestValidationError)
    async def handle_validation_error(
        _request: Request, _error: RequestValidationError
    ) -> JSONResponse:
        return JSONResponse({"error": "invalid_request"}, status_code=400)

    @app.middleware("http")
    async def security_headers(
        request: Request,
        call_next: Callable[[Request], Awaitable[Response]],
    ) -> Response:
        if request.url.query:
            response = JSONResponse({"error": "not_found"}, status_code=404)
        else:
            response = await call_next(request)
        response.headers["cache-control"] = "no-store"
        response.headers["x-content-type-options"] = "nosniff"
        response.headers["referrer-policy"] = "no-referrer"
        return response

    @app.get("/healthz", response_model=HealthResponse)
    async def health() -> HealthResponse:
        return HealthResponse()

    @app.get("/readyz", response_model=WorkerReadiness, dependencies=[Security(authorize)])
    async def readiness() -> WorkerReadiness:
        return await options.provider.readiness()

    @app.post(
        "/v1/jobs",
        response_model=InferenceJobResponse,
        dependencies=[Security(authorize_json)],
    )
    async def run_job(job: InferenceJob) -> InferenceJobResponse:
        if not await lane.try_acquire():
            raise WorkerProtocolError(429, "worker_busy")
        try:
            try:
                async with asyncio.timeout(options.deadline_seconds):
                    return await options.provider.run(job)
            except TimeoutError as error:
                raise WorkerProtocolError(504, "worker_timeout") from error
            except ProviderUnavailableError as error:
                raise WorkerProtocolError(503, "provider_unavailable") from error
        finally:
            await lane.release()

    return app
