from __future__ import annotations

import asyncio


class SingleInferenceLane:
    def __init__(self) -> None:
        self._state_lock = asyncio.Lock()
        self._occupied = False

    async def try_acquire(self) -> bool:
        async with self._state_lock:
            if self._occupied:
                return False
            self._occupied = True
            return True

    async def release(self) -> None:
        async with self._state_lock:
            if not self._occupied:
                raise RuntimeError("inference lane is not occupied")
            self._occupied = False
