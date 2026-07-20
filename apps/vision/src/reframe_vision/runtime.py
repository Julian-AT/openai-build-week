from __future__ import annotations

import importlib
from functools import lru_cache
from typing import Protocol, cast

from .contracts import TorchReadiness


class MPSBackend(Protocol):
    def is_available(self) -> bool: ...


class TorchBackends(Protocol):
    mps: MPSBackend


class TorchModule(Protocol):
    __version__: str
    backends: TorchBackends


@lru_cache(maxsize=1)
def probe_torch() -> TorchReadiness:
    try:
        torch = cast("TorchModule", importlib.import_module("torch"))
    except (ImportError, OSError):
        return TorchReadiness(installed=False, version=None, mps_available=False)
    return TorchReadiness(
        installed=True,
        version=torch.__version__,
        mps_available=torch.backends.mps.is_available(),
    )
