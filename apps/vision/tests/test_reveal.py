import asyncio
import base64
import hashlib

import httpx
import pytest
from pydantic import TypeAdapter

from reframe_vision import (
    DisabledRevealFillProvider,
    HttpRevealFillProvider,
    RevealFillRequest,
    RevealFillUnavailableError,
    RevealMetrics,
    assess_reveal,
)


def test_automated_reveal_readiness_accepts_a_safe_bundle() -> None:
    result = assess_reveal(
        RevealMetrics(
            coverage_p10=0.97,
            coverage_median=0.99,
            largest_uncovered_component_fraction=0.005,
            observed_fraction_outside_hole=0.9,
            foreground_overwrite_fraction=0.0,
            seam_severity="minor",
            severe_surface_order_artifact=False,
        )
    )

    assert result.decision == "ready"
    assert result.rejection_codes == ()


def test_automated_reveal_readiness_reports_every_failed_safety_gate() -> None:
    result = assess_reveal(
        RevealMetrics(
            coverage_p10=0.90,
            coverage_median=0.95,
            largest_uncovered_component_fraction=0.02,
            observed_fraction_outside_hole=0.70,
            foreground_overwrite_fraction=0.001,
            seam_severity="severe",
            severe_surface_order_artifact=True,
        )
    )

    assert result.decision == "rejected"
    assert result.rejection_codes == (
        "coverage_p10",
        "coverage_median",
        "uncovered_component",
        "observed_fraction",
        "foreground_overwrite",
        "seam",
        "surface_order",
    )


def test_disabled_fill_provider_fails_closed_without_modifying_input() -> None:
    request = RevealFillRequest(
        color_png=b"\x89PNG\r\n\x1a\ncolor",
        binary_mask_png=b"\x89PNG\r\n\x1a\nmask",
    )

    with pytest.raises(RevealFillUnavailableError):
        asyncio.run(DisabledRevealFillProvider().fill(request))


def test_http_fill_provider_binds_inputs_output_and_checkpoint() -> None:
    async def run() -> None:
        output = b"\x89PNG\r\n\x1a\nfilled"
        seen: list[dict[str, object]] = []
        payload_adapter: TypeAdapter[dict[str, object]] = TypeAdapter(dict[str, object])

        async def handler(request: httpx.Request) -> httpx.Response:
            seen.append(payload_adapter.validate_json(request.content))
            return httpx.Response(
                200,
                json={
                    "protocol_version": "1.0.0",
                    "provider_id": "lama",
                    "provider_revision": "official-pytorch-r1",
                    "checkpoint_sha256": "a" * 64,
                    "output_png_base64": base64.b64encode(output).decode("ascii"),
                    "output_sha256": hashlib.sha256(output).hexdigest(),
                },
            )

        async with httpx.AsyncClient(transport=httpx.MockTransport(handler)) as client:
            provider = HttpRevealFillProvider(
                "http://reveal-lama:8080",
                provider_revision="official-pytorch-r1",
                checkpoint_sha256="a" * 64,
                client=client,
            )
            result = await provider.fill(
                RevealFillRequest(
                    color_png=b"\x89PNG\r\n\x1a\ncolor",
                    binary_mask_png=b"\x89PNG\r\n\x1a\nmask",
                )
            )

        assert result.output_png == output
        assert result.provider_id == "lama"
        assert result.checkpoint_sha256 == "a" * 64
        assert seen[0]["color_sha256"] == hashlib.sha256(b"\x89PNG\r\n\x1a\ncolor").hexdigest()
        assert seen[0]["binary_mask_sha256"] == hashlib.sha256(b"\x89PNG\r\n\x1a\nmask").hexdigest()

    asyncio.run(run())


def test_http_fill_provider_rejects_unbound_or_malformed_output() -> None:
    async def run() -> None:
        output = b"\x89PNG\r\n\x1a\nfilled"

        async def handler(_request: httpx.Request) -> httpx.Response:
            return httpx.Response(
                200,
                json={
                    "protocol_version": "1.0.0",
                    "provider_id": "lama",
                    "provider_revision": "unexpected",
                    "checkpoint_sha256": "a" * 64,
                    "output_png_base64": base64.b64encode(output).decode("ascii"),
                    "output_sha256": hashlib.sha256(output).hexdigest(),
                },
            )

        async with httpx.AsyncClient(transport=httpx.MockTransport(handler)) as client:
            provider = HttpRevealFillProvider(
                "http://reveal-lama:8080",
                provider_revision="official-pytorch-r1",
                checkpoint_sha256="a" * 64,
                client=client,
            )
            with pytest.raises(RevealFillUnavailableError):
                await provider.fill(
                    RevealFillRequest(
                        color_png=b"\x89PNG\r\n\x1a\ncolor",
                        binary_mask_png=b"\x89PNG\r\n\x1a\nmask",
                    )
                )

    asyncio.run(run())
