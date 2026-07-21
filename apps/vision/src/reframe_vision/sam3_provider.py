# The official SAM builder is an external dynamic SDK boundary; its runtime
# signature and subprocess provenance are validated immediately before use.
# ruff: noqa: A002, PLR0913, S603, S607, TRY301
# pyright: reportAny=false, reportAttributeAccessIssue=false, reportUnknownArgumentType=false, reportUnknownMemberType=false, reportUnknownVariableType=false, reportUnnecessaryCast=false
from __future__ import annotations

import asyncio
import base64
import hashlib
import importlib
import os
import re
import subprocess
import sys
from dataclasses import dataclass
from pathlib import Path
from typing import Literal, Protocol, cast

import numpy as np
from numpy.typing import NDArray

from .contracts import (
    ImageInput,
    InferenceJob,
    InferenceJobResponse,
    MaskResult,
    ProviderIdentity,
    SegmentationJob,
    TaskReadiness,
    TorchReadiness,
    WorkerReadiness,
)
from .providers import InferenceProvider, ProviderUnavailableError
from .runtime import probe_torch
from .target_track import TargetMaskObservation, TargetSeedBinding, TargetTrack, TargetTrackStore

SAM_CHECKPOINT_REPOSITORY = "facebook/sam3.1"
SAM_CHECKPOINT_FILENAME = "sam3.1_multiplex.pt"
SAM_PROVIDER_ID = "sam3_1"
SESSION_ID_PATTERN = re.compile(r"^[A-Za-z0-9._-]{1,128}$")
MAX_TRACK_SESSIONS = 8
MAX_PROVIDER_REVISION_LENGTH = 128
SAM_MULTIPLEX_COUNT = 16
MASK_DIMENSIONS = 2
MASK_OUTPUT_DIMENSIONS = 3
TARGET_OBJECT_INDEX = 1


class _Predictor(Protocol):
    def handle_request(self, request: dict[str, object]) -> dict[str, object]: ...


class _TorchCuda(Protocol):
    def is_available(self) -> bool: ...


class _TorchVersion(Protocol):
    cuda: str | None


class _TorchRuntime(Protocol):
    __version__: str
    version: _TorchVersion
    cuda: _TorchCuda


class _SAMBuilder(Protocol):
    def build_sam3_multiplex_video_predictor(
        self,
        *,
        checkpoint_path: str,
        max_num_objects: int,
        multiplex_count: int,
        use_fa3: bool,
        compile: bool,
        async_loading_frames: bool,
    ) -> _Predictor: ...


@dataclass(frozen=True, slots=True)
class SAMPrompt:
    kind: Literal["point", "box"]
    x: int
    y: int
    width: int | None = None
    height: int | None = None
    label: Literal["foreground", "background"] | None = None


@dataclass(frozen=True, slots=True)
class SAMPrediction:
    mask: NDArray[np.bool_]
    confidence: float


class SAMEngine(Protocol):
    def start_session(self, session_id: str, image: ImageInput, frame_index: int) -> None: ...

    def segment(
        self,
        session_id: str,
        frame_index: int,
        image: ImageInput,
        prompt: SAMPrompt,
    ) -> SAMPrediction: ...

    def close_session(self, session_id: str) -> None: ...


@dataclass(slots=True)
class _SAMSession:
    target_id: str
    last_frame_index: int


class SAMProvider:
    """Authenticated, single-target SAM boundary; scene identity stays outside."""

    def __init__(
        self,
        engine: SAMEngine,
        *,
        provider_revision: str,
        torch: TorchReadiness | None = None,
    ) -> None:
        if not provider_revision or len(provider_revision) > MAX_PROVIDER_REVISION_LENGTH:
            raise ValueError("invalid SAM provider revision")
        self.identity = ProviderIdentity(
            provider_id=SAM_PROVIDER_ID,
            provider_revision=provider_revision,
            evidence_class="measured",
        )
        self._engine = engine
        self._torch = torch or probe_torch()
        self._tracks = TargetTrackStore()
        self._sessions: dict[str, _SAMSession] = {}
        self._lock = asyncio.Lock()

    async def readiness(self) -> WorkerReadiness:
        return WorkerReadiness(
            status="ready",
            provider=self.identity,
            tasks=TaskReadiness(segment=True, metric_depth=False, reconstruct=False),
            torch=self._torch,
        )

    async def run(self, job: InferenceJob) -> InferenceJobResponse:
        if not isinstance(job, SegmentationJob):
            raise ProviderUnavailableError
        if job.session_id is None or job.target_id is None or job.frame_index is None:
            raise ProviderUnavailableError
        session_id = _require_session_id(job.session_id)
        async with self._lock:
            session = self._sessions.get(session_id)
            if session is None:
                if len(self._sessions) >= MAX_TRACK_SESSIONS:
                    raise ProviderUnavailableError
                seed = _seed_from_job(job)
                self._tracks.begin(seed, target_id=job.target_id)
                self._engine.start_session(session_id, job.image, job.frame_index)
                session = _SAMSession(target_id=job.target_id, last_frame_index=job.frame_index - 1)
                self._sessions[session_id] = session
            if session.target_id != job.target_id:
                raise ProviderUnavailableError
            if job.frame_index <= session.last_frame_index:
                raise ProviderUnavailableError
            prediction = await asyncio.to_thread(
                self._engine.segment,
                session_id,
                job.frame_index,
                job.image,
                _prompt_from_job(job),
            )
            counts, foreground, digest = encode_binary_rle(prediction.mask)
            observation = TargetMaskObservation(
                session_id=session_id,
                target_id=session.target_id,
                frame_id=job.frame_index,
                encoded_width=job.image.width,
                encoded_height=job.image.height,
                counts=counts,
                confidence=prediction.confidence,
                sha256=digest,
                provider_id=self.identity.provider_id,
                provider_revision=self.identity.provider_revision,
            )
            self._tracks.record(observation)
            session.last_frame_index = job.frame_index
        return InferenceJobResponse(
            request_id=job.request_id,
            task="segment",
            provider=self.identity,
            result=MaskResult(
                kind="mask",
                width=job.image.width,
                height=job.image.height,
                encoding="binary_rle",
                counts=counts,
                foreground_pixels=foreground,
                sha256=digest,
            ),
        )

    def track(self, session_id: str) -> TargetTrack | None:
        return self._tracks.current(session_id)

    async def close_session(self, session_id: str) -> None:
        async with self._lock:
            self._engine.close_session(session_id)
            self._sessions.pop(session_id, None)


class UnavailableSAMProvider:
    def __init__(self, provider_revision: str = "unavailable") -> None:
        self.identity = ProviderIdentity(
            provider_id=SAM_PROVIDER_ID,
            provider_revision=provider_revision,
            evidence_class="unmeasured",
        )

    async def readiness(self) -> WorkerReadiness:
        return WorkerReadiness(
            status="degraded",
            provider=self.identity,
            tasks=TaskReadiness(segment=False, metric_depth=False, reconstruct=False),
            torch=probe_torch(),
        )

    async def run(self, job: InferenceJob) -> InferenceJobResponse:
        del job
        raise ProviderUnavailableError


def encode_binary_rle(mask: NDArray[np.bool_]) -> tuple[tuple[int, ...], int, str]:
    values = np.asarray(mask, dtype=np.bool_)
    if values.ndim != MASK_DIMENSIONS or values.shape[0] < 1 or values.shape[1] < 1:
        raise ValueError("SAM mask must be a non-empty matrix")
    flat = values.reshape(-1, order="C")
    counts: list[int] = []
    current = False
    run = 0
    for value in flat:
        if bool(value) == current:
            run += 1
        else:
            counts.append(run)
            current = bool(value)
            run = 1
    counts.append(run)
    raw = np.where(flat, np.uint8(1), np.uint8(0)).tobytes()
    return tuple(counts), int(np.count_nonzero(flat)), hashlib.sha256(raw).hexdigest()


def _seed_from_job(job: SegmentationJob) -> TargetSeedBinding:
    prompt = job.prompt
    if prompt.kind == "point":
        pixel_x, pixel_y = prompt.x, prompt.y
    else:
        pixel_x = prompt.x + prompt.width // 2
        pixel_y = prompt.y + prompt.height // 2
    return TargetSeedBinding(
        session_id=_require_session_id(cast("str", job.session_id)),
        frame_id=cast("int", job.frame_index),
        encoded_width=job.image.width,
        encoded_height=job.image.height,
        pixel_x=pixel_x,
        pixel_y=pixel_y,
    )


def _prompt_from_job(job: SegmentationJob) -> SAMPrompt:
    prompt = job.prompt
    if prompt.kind == "point":
        return SAMPrompt(kind="point", x=prompt.x, y=prompt.y, label=prompt.label)
    return SAMPrompt(
        kind="box",
        x=prompt.x,
        y=prompt.y,
        width=prompt.width,
        height=prompt.height,
    )


def _require_session_id(value: str) -> str:
    if not SESSION_ID_PATTERN.fullmatch(value):
        raise ProviderUnavailableError
    return value


class SAM3PredictorEngine:
    """Thin adapter around Meta's external SAM3.1 multiplex predictor."""

    def __init__(self, predictor: _Predictor, data_root: Path) -> None:
        self._predictor = predictor
        self._data_root = data_root
        self._sessions: set[str] = set()

    def start_session(self, session_id: str, image: ImageInput, frame_index: int) -> None:
        session_dir = self._session_dir(session_id)
        session_dir.mkdir(parents=True, exist_ok=True)
        (session_dir / f"{frame_index:08d}.jpg").write_bytes(_decode_image(image))
        self._predictor.handle_request(
            {
                "type": "start_session",
                "resource_path": str(session_dir),
                "session_id": session_id,
                "offload_video_to_cpu": True,
                "offload_state_to_cpu": True,
            }
        )
        self._sessions.add(session_id)

    def segment(
        self,
        session_id: str,
        frame_index: int,
        image: ImageInput,
        prompt: SAMPrompt,
    ) -> SAMPrediction:
        if session_id not in self._sessions:
            raise ProviderUnavailableError
        session_dir = self._session_dir(session_id)
        frame_path = session_dir / f"{frame_index:08d}.jpg"
        if not frame_path.exists():
            frame_path.write_bytes(_decode_image(image))
        torch = cast("_TorchRuntime", importlib.import_module("torch"))

        request: dict[str, object] = {
            "type": "add_prompt",
            "session_id": session_id,
            "frame_index": frame_index,
            "obj_id": 1,
            "rel_coordinates": True,
        }
        if prompt.kind == "point":
            request["points"] = torch.tensor(
                [[prompt.x / image.width, prompt.y / image.height]], dtype=torch.float32
            )
            request["point_labels"] = torch.tensor(
                [1 if prompt.label == "foreground" else 0], dtype=torch.int32
            )
        else:
            if prompt.width is None or prompt.height is None:
                raise ProviderUnavailableError
            request["bounding_boxes"] = torch.tensor(
                [
                    [
                        prompt.x / image.width,
                        prompt.y / image.height,
                        prompt.width / image.width,
                        prompt.height / image.height,
                    ]
                ],
                dtype=torch.float32,
            )
            request["bounding_box_labels"] = torch.tensor([1], dtype=torch.int32)
        autocast = getattr(torch, "autocast", None)
        bfloat16 = getattr(torch, "bfloat16", None)
        if autocast is None or bfloat16 is None:
            # Lightweight test doubles do not expose CUDA autocast.
            response = self._predictor.handle_request(request)
        else:
            # The gateway invokes provider work on a bounded worker thread.
            # SAM's predictor creates its BF16 context on the construction
            # thread, so re-enter it here to keep matmul dtypes consistent.
            with autocast(device_type="cuda", dtype=bfloat16):
                response = self._predictor.handle_request(request)
        outputs = cast("dict[str, object]", response.get("outputs", {}))
        object_ids = np.asarray(cast("object", outputs.get("out_obj_ids", [])))
        masks = np.asarray(cast("object", outputs.get("out_binary_masks", [])))
        probabilities = np.asarray(cast("object", outputs.get("out_probs", [])), dtype=np.float32)
        matching = np.flatnonzero(object_ids == TARGET_OBJECT_INDEX)
        if masks.ndim != MASK_OUTPUT_DIMENSIONS:
            raise ProviderUnavailableError
        if matching.size:
            index = int(matching[0])
        elif object_ids.size == 1 and masks.shape[0] == 1:
            # Some SAM3.1 predictor builds normalize a single prompt to object
            # id zero. A sole output is safe to bind to this server-owned
            # target; multiple unbound objects fail closed.
            index = 0
        else:
            raise ProviderUnavailableError
        confidence = float(probabilities[index]) if index < len(probabilities) else 0.0
        return SAMPrediction(mask=np.asarray(masks[index], dtype=np.bool_), confidence=confidence)

    def close_session(self, session_id: str) -> None:
        if session_id in self._sessions:
            self._predictor.handle_request({"type": "close_session", "session_id": session_id})
            self._sessions.remove(session_id)

    def _session_dir(self, session_id: str) -> Path:
        _require_session_id(session_id)
        return self._data_root / "sessions" / session_id


def load_sam3_engine(
    source_dir: Path,
    checkpoint_path: Path,
    data_root: Path,
    *,
    source_revision: str,
    checkpoint_bytes: int,
    checkpoint_sha256: str,
) -> SAM3PredictorEngine:
    _verify_source(source_dir, source_revision)
    _verify_file(checkpoint_path, checkpoint_bytes, checkpoint_sha256)
    try:
        torch = cast("_TorchRuntime", importlib.import_module("torch"))
        version = tuple(int(part) for part in torch.__version__.split("+")[0].split(".")[:2])
        cuda_version = tuple(int(part) for part in str(torch.version.cuda or "0.0").split(".")[:2])
        if version < (2, 7) or cuda_version < (12, 6) or not torch.cuda.is_available():
            raise RuntimeError("SAM requires torch>=2.7, CUDA>=12.6, and a CUDA device")
        if str(source_dir) not in sys.path:
            sys.path.insert(0, str(source_dir))
        builder = cast("_SAMBuilder", importlib.import_module("sam3.model_builder"))
        predictor = builder.build_sam3_multiplex_video_predictor(
            checkpoint_path=str(checkpoint_path),
            max_num_objects=1,
            multiplex_count=SAM_MULTIPLEX_COUNT,
            use_fa3=False,
            compile=False,
            async_loading_frames=False,
        )
    except (ImportError, OSError, RuntimeError, ValueError) as error:
        raise RuntimeError("SAM runtime initialization failed") from error
    return SAM3PredictorEngine(predictor, data_root)


def create_sam_provider_from_environment() -> InferenceProvider:
    revision = os.environ.get("REFRAME_SAM_PROVIDER_REVISION", "unavailable")
    try:
        source_dir = Path(os.environ["REFRAME_SAM_SOURCE_DIR"]).expanduser().resolve()
        checkpoint_path = Path(os.environ["REFRAME_SAM_CHECKPOINT_PATH"]).expanduser().resolve()
        data_root = Path(os.environ["REFRAME_SAM_DATA_DIR"]).expanduser().resolve()
        engine = load_sam3_engine(
            source_dir,
            checkpoint_path,
            data_root,
            source_revision=os.environ["REFRAME_SAM_SOURCE_REVISION"],
            checkpoint_bytes=int(os.environ["REFRAME_SAM_CHECKPOINT_BYTES"]),
            checkpoint_sha256=os.environ["REFRAME_SAM_CHECKPOINT_SHA256"],
        )
    except (KeyError, OSError, RuntimeError, ValueError) as error:
        del error
        return UnavailableSAMProvider(revision)
    return SAMProvider(engine, provider_revision=revision)


def _verify_source(source_dir: Path, expected_revision: str) -> None:
    if not source_dir.is_dir() or not expected_revision:
        raise RuntimeError("SAM source directory is unavailable")
    try:
        actual = subprocess.run(
            ["git", "-C", str(source_dir), "rev-parse", "HEAD"],
            check=True,
            capture_output=True,
            text=True,
        ).stdout.strip()
    except (OSError, subprocess.SubprocessError) as error:
        raise RuntimeError("SAM source revision cannot be verified") from error
    if actual != expected_revision:
        raise RuntimeError("SAM source revision mismatch")


def _verify_file(path: Path, expected_bytes: int, expected_sha256: str) -> None:
    if expected_bytes < 1 or not re.fullmatch(r"[0-9a-f]{64}", expected_sha256):
        raise ValueError("invalid SAM checkpoint manifest")
    if not path.is_file() or path.stat().st_size != expected_bytes:
        raise RuntimeError("SAM checkpoint size mismatch")
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(chunk)
    if digest.hexdigest() != expected_sha256:
        raise RuntimeError("SAM checkpoint digest mismatch")


def _decode_image(image: ImageInput) -> bytes:
    return base64.b64decode(image.data_base64, validate=True)
