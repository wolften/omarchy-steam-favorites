#!/usr/bin/env python3
"""Safely fetch Steam CDN covers into the local plugin cache.

Security boundaries (the QML shell is unsandboxed, so this helper absorbs
all network risk instead of QML ``Image`` loaders):
  - allow-listed CDN host + path templates only (numeric appid interpolated)
  - connect timeout AND total per-file timeout
  - hard byte limit (header pre-check + chunked read cap)
  - magic-byte format validation (JPEG/PNG only) + parsed dimension limits
  - atomic writes (temp file in cache dir + os.replace) so QML never reads
    a partially written image
  - bounded concurrency (ThreadPoolExecutor, default 4 workers)

Usage:
    fetch-covers.py [--cache-dir DIR] [--max-workers N] APPID [APPID ...]

Prints a JSON object mapping each appid to a ``file://`` URI (or null when
no cover could be fetched) on stdout.

Also importable: ``from fetch_covers import fetch_cover, ensure_cached``.
"""

from __future__ import annotations

import argparse
import concurrent.futures
import json
import os
import re
import struct
import sys
import tempfile
import time
import urllib.request
from pathlib import Path

PLUGIN_ID = "io.github.wolften.steam-favorites"

CDN_HOST = "cdn.cloudflare.steamstatic.com"
CDN_TEMPLATES = (
    "https://cdn.cloudflare.steamstatic.com/steam/apps/{appid}/library_600x900.jpg",
    "https://cdn.cloudflare.steamstatic.com/steam/apps/{appid}/library_capsule.jpg",
    "https://cdn.cloudflare.steamstatic.com/steam/apps/{appid}/header.jpg",
)

CONNECT_TIMEOUT = 5.0  # seconds for TCP/TLS connect (per attempt)
TOTAL_TIMEOUT = 15.0  # seconds wall-clock per candidate file, all-in
MAX_BYTES = 4 * 1024 * 1024  # 4 MiB hard cap per image response
CHUNK = 64 * 1024
MAX_WORKERS = 4

# Decoded-dimension limits (defense in depth alongside QML sourceSize).
MIN_DIMENSION = 32
MAX_DIMENSION = 2048
MAX_PIXELS = 2048 * 2048

APPID_RE = re.compile(r"^\d{2,10}$")

JPEG_SOI = b"\xff\xd8"
PNG_MAGIC = b"\x89PNG\r\n\x1a\n"


def default_cache_dir() -> Path:
    base = os.environ.get("XDG_CACHE_HOME") or str(Path.home() / ".cache")
    return Path(base) / "omarchy" / "plugins" / PLUGIN_ID / "covers"


def _is_allowed_url(url: str, appid: str) -> bool:
    return url in [t.format(appid=appid) for t in CDN_TEMPLATES]


def parse_png_dimensions(data: bytes) -> tuple[int, int] | None:
    """Return (width, height) from a PNG header, or None if invalid."""
    if len(data) < 24 or data[:8] != PNG_MAGIC:
        return None
    # IHDR must be the first chunk: length(4) + type(4) + data(13).
    if data[12:16] != b"IHDR" or struct.unpack(">I", data[8:12])[0] != 13:
        return None
    width, height = struct.unpack(">II", data[16:24])
    return (width, height)


def parse_jpeg_dimensions(data: bytes) -> tuple[int, int] | None:
    """Return (width, height) from JPEG SOF markers, or None if invalid."""
    if len(data) < 4 or data[0:2] != JPEG_SOI:
        return None
    pos = 2
    end = len(data)
    # SOF markers that carry dimensions (baseline/extended/progressive etc.,
    # excluding DHT/DAC/DNL which share the 0xC4-0xCF range).
    sof = {
        0xC0, 0xC1, 0xC2, 0xC3, 0xC5, 0xC6, 0xC7,
        0xC9, 0xCA, 0xCB, 0xCD, 0xCE, 0xCF,
    }
    while pos + 4 <= end:
        if data[pos] != 0xFF:
            return None
        marker = data[pos + 1]
        # Standalone markers without length.
        if marker in (0xD8, 0xD9) or 0xD0 <= marker <= 0xD7 or marker == 0x01:
            pos += 2
            continue
        if pos + 4 > end:
            return None
        seg_len = struct.unpack(">H", data[pos + 2 : pos + 4])[0]
        if seg_len < 2 or pos + 2 + seg_len > end:
            return None
        if marker in sof:
            # SOF payload: precision(1) + height(2) + width(2) + ...
            if seg_len >= 7:
                height, width = struct.unpack(">HH", data[pos + 5 : pos + 9])
                return (width, height)
            return None
        if marker == 0xDA:  # SOS: dimensions must precede scan data
            return None
        pos += 2 + seg_len
    return None


def sniff_format(data: bytes) -> str | None:
    if data[:2] == JPEG_SOI:
        return "jpeg"
    if data[:8] == PNG_MAGIC:
        return "png"
    return None


def validate_image(data: bytes) -> tuple[int, int] | None:
    """Check magic + parse dimensions + enforce dimension bounds.

    Returns (width, height) when the image is acceptable, else None.
    """
    if not data:
        return None
    fmt = sniff_format(data)
    dims: tuple[int, int] | None = None
    if fmt == "jpeg":
        dims = parse_jpeg_dimensions(data)
    elif fmt == "png":
        dims = parse_png_dimensions(data)
    else:
        return None
    if dims is None:
        return None
    width, height = dims
    if not (
        MIN_DIMENSION <= width <= MAX_DIMENSION
        and MIN_DIMENSION <= height <= MAX_DIMENSION
    ):
        return None
    if width * height > MAX_PIXELS:
        return None
    return dims


def _download_candidate(url: str, appid: str) -> bytes | None:
    """Download one allow-listed URL with timeouts + byte cap. Returns None on any failure."""
    if not _is_allowed_url(url, appid):
        return None
    deadline = time.monotonic() + TOTAL_TIMEOUT
    request = urllib.request.Request(
        url,
        headers={"User-Agent": "omarchy-steam-favorites/1.0", "Accept": "image/jpeg,image/png"},
        method="GET",
    )
    try:
        remaining = max(0.1, deadline - time.monotonic())
        timeout = min(CONNECT_TIMEOUT, remaining)
        with urllib.request.urlopen(request, timeout=timeout) as response:
            status = getattr(response, "status", 200)
            if status != 200:
                return None
            content_type = (response.headers.get("Content-Type") or "").split(";")[0].strip().lower()
            if content_type not in ("image/jpeg", "image/pjpeg", "image/png", "application/octet-stream"):
                return None
            try:
                declared = response.headers.get("Content-Length")
                if declared is not None and int(declared) > MAX_BYTES:
                    return None
            except (ValueError, TypeError):
                return None
            buf = bytearray()
            while True:
                remaining = deadline - time.monotonic()
                if remaining <= 0:
                    return None  # total timeout
                chunk_timeout = min(CONNECT_TIMEOUT, remaining)
                # NOTE: http response reads honor the socket timeout set at
                # urlopen time; chunk_timeout only bounds our deadline math.
                _ = chunk_timeout
                chunk = response.read(min(CHUNK, MAX_BYTES + 1 - len(buf)))
                if not chunk:
                    break
                buf.extend(chunk)
                if len(buf) > MAX_BYTES:
                    return None  # hard byte limit
                if time.monotonic() > deadline:
                    return None
            if not buf:
                return None
            return bytes(buf)
    except Exception:
        return None


def _atomic_write(cache_dir: Path, appid: str, data: bytes, suffix: str) -> Path | None:
    """Write data atomically into cache_dir; returns final path or None."""
    try:
        cache_dir.mkdir(parents=True, exist_ok=True)
    except OSError:
        return None
    final = cache_dir / f"{appid}{suffix}"
    try:
        fd, tmp_name = tempfile.mkstemp(
            dir=str(cache_dir), prefix=f".{appid}-", suffix=".tmp"
        )
        try:
            with os.fdopen(fd, "wb") as handle:
                handle.write(data)
                handle.flush()
                os.fsync(handle.fileno())
            os.replace(tmp_name, final)
        except BaseException:
            try:
                os.unlink(tmp_name)
            except OSError:
                pass
            return None
        return final
    except OSError:
        return None


def fetch_cover(
    appid: str,
    cache_dir: Path | None = None,
    max_bytes: int = MAX_BYTES,
    total_timeout: float = TOTAL_TIMEOUT,
) -> Path | None:
    """Fetch one cover safely; returns cached file path or None.

    Reuses a valid cached file without network. Otherwise tries each CDN
    candidate in order and caches the first image that passes validation.
    """
    global MAX_BYTES, TOTAL_TIMEOUT
    old_max, old_total = MAX_BYTES, TOTAL_TIMEOUT
    MAX_BYTES, TOTAL_TIMEOUT = max_bytes, total_timeout
    try:
        return _fetch_cover(appid, cache_dir or default_cache_dir())
    finally:
        MAX_BYTES, TOTAL_TIMEOUT = old_max, old_total


def _fetch_cover(appid: str, cache_dir: Path) -> Path | None:
    if not APPID_RE.match(appid):
        return None
    # Reuse valid cache without touching the network.
    for suffix in (".jpg", ".png"):
        cached = cache_dir / f"{appid}{suffix}"
        try:
            if cached.is_file() and 0 < cached.stat().st_size <= MAX_BYTES:
                data = cached.read_bytes()
                if validate_image(data) is not None:
                    return cached
        except OSError:
            continue
        # Stale/invalid cache entry: remove so QML never loads it.
        try:
            if cached.is_file():
                cached.unlink()
        except OSError:
            pass
    for url in [t.format(appid=appid) for t in CDN_TEMPLATES]:
        data = _download_candidate(url, appid)
        if data is None:
            continue
        if validate_image(data) is None:
            continue
        suffix = ".png" if sniff_format(data) == "png" else ".jpg"
        written = _atomic_write(cache_dir, appid, data, suffix)
        if written is not None:
            return written
    return None


ensure_cached = fetch_cover


def fetch_many(
    appids: list[str], cache_dir: Path, max_workers: int = MAX_WORKERS
) -> dict[str, str | None]:
    """Fetch several covers with bounded concurrency. Returns appid -> file URI."""
    # De-duplicate while preserving order; cap workers to avoid thread storms
    # on very large libraries.
    seen: list[str] = []
    for raw in appids:
        appid = str(raw)
        if APPID_RE.match(appid) and appid not in seen:
            seen.append(appid)
    workers = max(1, min(max_workers, 8, len(seen) or 1))
    results: dict[str, str | None] = {appid: None for appid in seen}

    def _one(appid: str) -> tuple[str, str | None]:
        path = _fetch_cover(appid, cache_dir)
        return (appid, path.as_uri() if path is not None else None)

    with concurrent.futures.ThreadPoolExecutor(max_workers=workers) as pool:
        for appid, uri in pool.map(_one, seen):
            results[appid] = uri
    return results


def main(argv: list[str] | None = None) -> int:
    global MAX_BYTES
    parser = argparse.ArgumentParser(description="Fetch Steam covers into local cache")
    parser.add_argument("appids", nargs="*", help="Numeric Steam app IDs")
    parser.add_argument("--cache-dir", default=str(default_cache_dir()))
    parser.add_argument("--max-workers", type=int, default=MAX_WORKERS)
    parser.add_argument("--max-bytes", type=int, default=MAX_BYTES)
    args = parser.parse_args(argv)

    MAX_BYTES = args.max_bytes

    appids = [a for a in args.appids if APPID_RE.match(str(a))]
    if not appids:
        print(json.dumps({}))
        return 0
    cache_dir = Path(args.cache_dir)
    results = fetch_many([str(a) for a in appids], cache_dir, args.max_workers)
    json.dump(results, sys.stdout)
    print()
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
