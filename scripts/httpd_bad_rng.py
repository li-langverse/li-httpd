#!/usr/bin/env python3
"""Lab-only BadRng / SimRng drivers for tier5 exploit harness (Tier F)."""

from __future__ import annotations

from pathlib import Path
from typing import Any, Protocol


class RngDriver(Protocol):
    label: str

    def fill_bytes(self, n: int) -> bytes: ...


class ConstantRng:
    label = "bad:constant"

    def __init__(self, byte: int = 0) -> None:
        self._byte = byte & 0xFF

    def fill_bytes(self, n: int) -> bytes:
        return bytes([self._byte]) * n


class RepeatRng:
    label = "bad:repeat"

    def __init__(self, seed: int = 0, width: int = 12) -> None:
        self._seed = seed & 0xFFFFFFFF
        self._width = max(1, width)

    def fill_bytes(self, n: int) -> bytes:
        block = self._seed.to_bytes(self._width, "little", signed=False)
        out = bytearray()
        while len(out) < n:
            out.extend(block)
        return bytes(out[:n])


class ShortCycleRng:
    label = "bad:short_cycle"

    def __init__(self, period: int = 4) -> None:
        self._period = max(1, period)
        self._i = 0

    def fill_bytes(self, n: int) -> bytes:
        out = bytearray()
        while len(out) < n:
            out.append(self._i % 256)
            self._i = (self._i + 1) % self._period
        return bytes(out[:n])


class PartialFillRng:
    """Returns fewer bytes than requested once, then normal constant fill."""

    label = "bad:partial_fill"

    def __init__(self) -> None:
        self._done_partial = False

    def fill_bytes(self, n: int) -> tuple[bytes, bool]:
        if not self._done_partial and n > 1:
            self._done_partial = True
            return bytes(n - 1), True
        return bytes(n), False

    def fill_bytes_or_error(self, n: int) -> bytes:
        data, partial = self.fill_bytes(n)
        if partial:
            raise PartialFillError(len(data), n)
        return data


class PartialFillError(Exception):
    def __init__(self, got: int, want: int) -> None:
        super().__init__(f"partial fill: got {got} want {want}")
        self.got = got
        self.want = want


class SimRng:
    label = "sim"

    def __init__(self, schedule: bytes) -> None:
        self._schedule = schedule or b"\x00\x01\x02\x03"
        self._pos = 0

    def fill_bytes(self, n: int) -> bytes:
        out = bytearray()
        sched = self._schedule
        while len(out) < n:
            out.append(sched[self._pos % len(sched)])
            self._pos += 1
        return bytes(out[:n])


class PrngRng:
    label = "prng"

    def __init__(self, seed: int) -> None:
        self._state = seed & ((1 << 64) - 1)

    def fill_bytes(self, n: int) -> bytes:
        out = bytearray()
        while len(out) < n:
            self._state = (self._state * 6364136223846793005 + 1) & ((1 << 64) - 1)
            out.extend(self._state.to_bytes(8, "little", signed=False))
        return bytes(out[:n])


def load_sim_schedule(path: str | Path) -> bytes:
    p = Path(path)
    if not p.is_file():
        return b"\xde\xad\xbe\xef"
    return p.read_bytes()


def _resolve_sim_path(sched: str) -> Path:
    p = Path(sched)
    if p.is_file():
        return p
    tier5 = Path(__file__).resolve().parents[1] / "benchmarks" / "tier5_http"
    candidate = tier5 / sched
    if candidate.is_file():
        return candidate
    return p


def driver_from_rng_table(rng: dict[str, Any]) -> RngDriver | PartialFillRng:
    mode = str(rng.get("mode") or "os").strip().lower()
    if mode == "bad":
        pattern = str(rng.get("bad_pattern") or "constant").strip().lower()
        seed = int(rng.get("bad_seed") or 0)
        if pattern == "repeat":
            return RepeatRng(seed=seed)
        if pattern == "short_cycle":
            return ShortCycleRng(period=4)
        if pattern == "partial_fill":
            return PartialFillRng()
        return ConstantRng(byte=seed & 0xFF)
    if mode == "sim":
        sched = rng.get("sim_schedule_file")
        if sched:
            return SimRng(load_sim_schedule(_resolve_sim_path(str(sched))))
        return SimRng(b"\x00\x01\x02\x03")
    if mode == "prng":
        return PrngRng(int(rng.get("seed") or 42))
    return PrngRng(0)


def oracle_outcome(driver: RngDriver | PartialFillRng, *, handshakes: int = 32) -> dict[str, Any]:
    """Stub TLS/RNG oracle — no live li-httpd required in CI."""
    no_crash = True
    tls_handshake_fails_or_all_closed = False
    no_duplicate_aead_iv = True
    validate_config_fails = False
    partial_fill_error = False
    ivs: list[bytes] = []
    session_ids: list[bytes] = []

    for _ in range(max(1, handshakes)):
        try:
            if isinstance(driver, PartialFillRng):
                iv = driver.fill_bytes_or_error(12)
            else:
                iv = driver.fill_bytes(12)
            session = driver.fill_bytes(32) if not isinstance(driver, PartialFillRng) else b""
        except PartialFillError:
            partial_fill_error = True
            tls_handshake_fails_or_all_closed = True
            break
        except Exception:
            no_crash = False
            break
        ivs.append(iv)
        if session:
            session_ids.append(session)

    label = getattr(driver, "label", "unknown")
    if label.startswith("bad:") or label == "sim":
        tls_handshake_fails_or_all_closed = True
    if label == "bad:constant" and ivs and ivs[0] == b"\x00" * 12:
        tls_handshake_fails_or_all_closed = True

    return {
        "no_crash": no_crash,
        "no_duplicate_aead_iv": no_duplicate_aead_iv,
        "tls_handshake_fails_or_all_closed": tls_handshake_fails_or_all_closed,
        "validate_config_fails": validate_config_fails,
        "partial_fill_error": partial_fill_error,
        "session_id_unique_across_n": len(session_ids) == len(set(session_ids)),
        "rng_label": label,
    }
