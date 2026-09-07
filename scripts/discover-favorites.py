#!/usr/bin/env python3
"""Discover installed Steam games (prefer favorites) and print JSON to stdout.

Output games carry only: appid, name, cover, logo, icon.
No "installed"/source labels are emitted — the panel shows clean names.
Artwork is always a local ``file://`` URI (Steam librarycache or the plugin
cache filled by ``fetch-covers.py``). QML never loads remote URLs: CDN
fetching happens only here, behind connect/total timeouts, a hard byte
limit, and image format/dimension validation.
"""

from __future__ import annotations

import json
import os
import re
import sys
from pathlib import Path

try:
    # Bundled safe CDN fetcher (timeouts, byte cap, format/dimension
    # validation, atomic cache writes, bounded concurrency).
    sys.path.insert(0, str(Path(__file__).resolve().parent))
    import fetch_covers
except ImportError:  # offline / minimal environments: local art only
    fetch_covers = None  # type: ignore[assignment]

NON_GAME_NAME = re.compile(
    r"(?i)^(Proton(\b|[\s\-])|Steam Linux Runtime|Steamworks Common Redistributables|"
    r"Steamworks Shared|Steam Linux Runtime Soldier|Steam Linux Runtime Scout|"
    r"Steam Linux Runtime Sniper|Steam Linux Runtime Medic)"
)

# Known non-game / tool appids
NON_GAME_APPIDS = {
    228980,  # Steamworks Common Redistributables
    1391110,  # Steam Linux Runtime - Soldier
    1493710,  # Proton Experimental (sometimes listed)
    1628350,  # Steam Linux Runtime - Sniper
    1070560,  # Steam Linux Runtime
    2180100,  # Steam Linux Runtime 3.0 sniper variants tracked loosely
}

# Local artwork priority inside appcache/librarycache/<appid>/
COVER_FILENAMES = (
    "library_600x900.jpg",
    "library_capsule.jpg",
    "library_header.jpg",
    "header.jpg",
    "library_hero.jpg",
)
LOGO_FILENAMES = ("logo.png",)


def steam_roots() -> list[Path]:
    home = Path.home()
    candidates = [
        home / ".steam" / "steam",
        home / ".local" / "share" / "Steam",
        home / ".steam" / "root",
        home / ".var" / "app" / "com.valvesoftware.Steam" / "data" / "Steam",
    ]
    roots: list[Path] = []
    for path in candidates:
        if path.is_dir() and path not in roots:
            roots.append(path)
    return roots


def find_userdata(root: Path) -> list[Path]:
    userdata = root / "userdata"
    if not userdata.is_dir():
        return []
    return [p for p in userdata.iterdir() if p.is_dir() and p.name.isdigit()]


def parse_vdf_apps_with_favorite(text: str) -> set[str]:
    favorites: set[str] = set()
    for match in re.finditer(
        r'"(\d{2,})"\s*\{([^{}]*(?:\{[^{}]*\}[^{}]*)*)\}',
        text,
        flags=re.DOTALL,
    ):
        appid, body = match.group(1), match.group(2)
        if re.search(r'"favorite"\s*"', body, flags=re.IGNORECASE) or re.search(
            r'"\d+"\s*"favorite"', body, flags=re.IGNORECASE
        ):
            favorites.add(appid)
    for match in re.finditer(
        r'"(\d{2,})"\s*\{[^}]*?"tags"\s*\{[^}]*?favorite[^}]*?\}',
        text,
        flags=re.IGNORECASE | re.DOTALL,
    ):
        favorites.add(match.group(1))
    return favorites


def is_game(appid: int, name: str) -> bool:
    if appid in NON_GAME_APPIDS:
        return False
    if NON_GAME_NAME.search(name or ""):
        return False
    # Extra: any name containing these phrases
    lowered = (name or "").lower()
    if "steam linux runtime" in lowered:
        return False
    if lowered.startswith("proton "):
        return False
    if "steamworks common redistributables" in lowered:
        return False
    return True


def load_installed_apps(root: Path) -> dict[str, str]:
    """appid -> name for titles that have an appmanifest (i.e. installed)."""
    names: dict[str, str] = {}
    library_folders = root / "steamapps" / "libraryfolders.vdf"
    steamapps_dirs = [root / "steamapps"]
    if library_folders.is_file():
        text = library_folders.read_text(encoding="utf-8", errors="ignore")
        for match in re.finditer(r'"path"\s*"([^"]+)"', text):
            steamapps_dirs.append(Path(match.group(1)) / "steamapps")
    for steamapps in steamapps_dirs:
        if not steamapps.is_dir():
            continue
        for manifest in steamapps.glob("appmanifest_*.acf"):
            try:
                content = manifest.read_text(encoding="utf-8", errors="ignore")
            except OSError:
                continue
            appid_m = re.search(r'"appid"\s*"(\d+)"', content)
            name_m = re.search(r'"name"\s*"([^"]+)"', content)
            if appid_m and name_m:
                names[appid_m.group(1)] = name_m.group(1)
    return names


def load_manual_json() -> list[dict]:
    path = Path.home() / ".config" / "omarchy" / "steam-favorites.json"
    if not path.is_file():
        return []
    try:
        data = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError):
        return []
    games = []
    if isinstance(data, list):
        for item in data:
            if isinstance(item, dict) and item.get("appid"):
                games.append(
                    {
                        "appid": int(item["appid"]),
                        "name": str(item.get("name") or f"App {item['appid']}"),
                    }
                )
    return games


def plugin_cache_dir() -> Path:
    base = os.environ.get("XDG_CACHE_HOME") or str(Path.home() / ".cache")
    return (
        Path(base)
        / "omarchy"
        / "plugins"
        / "io.github.wolften.steam-favorites"
        / "covers"
    )


def cached_cover_uri(appid: str) -> str | None:
    """Return a validated cached-cover file:// URI, or None."""
    cache_dir = plugin_cache_dir()
    for suffix in (".jpg", ".png"):
        candidate = cache_dir / f"{appid}{suffix}"
        try:
            if not candidate.is_file():
                continue
            if candidate.stat().st_size <= 0:
                continue
            if fetch_covers is not None:
                try:
                    data = candidate.read_bytes()
                except OSError:
                    continue
                if fetch_covers.validate_image(data) is None:
                    try:
                        candidate.unlink()
                    except OSError:
                        pass
                    continue
            return candidate.as_uri()
        except OSError:
            continue
    return None


def find_artwork(appid: str, roots: list[Path]) -> dict[str, str | None]:
    """Locate local cover/logo/icon for an appid.

    Returns file:// URIs (or None) for keys cover, logo, icon.
    Searches <root>/appcache/librarycache/<appid>/ recursively because
    Steam stores full art inside hash-named subfolders.
    Falls back to the validated plugin CDN cache (never a remote URL).
    """
    cover: str | None = None
    logo: str | None = None
    icon: str | None = None
    for root in roots:
        base = root / "appcache" / "librarycache" / appid
        if not base.is_dir():
            continue
        # Direct hits first (fast path, e.g. RDR2 keeps files at top level).
        for name in COVER_FILENAMES:
            candidate = base / name
            if candidate.is_file() and cover is None:
                cover = candidate.as_uri()
                break
        for name in LOGO_FILENAMES:
            candidate = base / name
            if candidate.is_file() and logo is None:
                logo = candidate.as_uri()
                break
        if icon is None:
            for candidate in sorted(base.glob("*.jpg")):
                # Top-level small jpgs are the 32px client icons.
                if candidate.is_file():
                    icon = candidate.as_uri()
                    break
        if cover is not None and logo is not None and icon is not None:
            break
        # Deep search inside hash-named subfolders (Dota 2, Valheim, ...).
        try:
            files = [p for p in base.rglob("*") if p.is_file()]
        except OSError:
            continue
        by_name: dict[str, Path] = {}
        for path in files:
            by_name.setdefault(path.name, path)
        if cover is None:
            for name in COVER_FILENAMES:
                if name in by_name:
                    cover = by_name[name].as_uri()
                    break
        if logo is None and "logo.png" in by_name:
            logo = by_name["logo.png"].as_uri()
        if icon is None:
            # Prefer the smallest image as the client icon.
            images = [p for p in files if p.suffix.lower() in (".jpg", ".png")]
            if images:
                try:
                    smallest = min(images, key=lambda p: p.stat().st_size)
                    # Only treat it as icon when it is small (< 20KB ≈ 32px).
                    if smallest.stat().st_size < 20 * 1024:
                        icon = smallest.as_uri()
                except OSError:
                    pass
        if cover is not None and logo is not None and icon is not None:
            break
    if cover is None:
        # Validated plugin CDN cache (written by fetch-covers.py) — still a
        # local file:// URI, never a remote URL. Network fetching itself
        # happens in fetch-covers.py (invoked from Panel.qml), so discovery
        # stays fast and offline-safe.
        cover = cached_cover_uri(appid)
    return {"cover": cover, "logo": logo, "icon": icon}


def make_entry(appid: int, name: str, roots: list[Path]) -> dict:
    art = find_artwork(str(appid), roots)
    return {
        "appid": appid,
        "name": name,
        "cover": art["cover"],
        "logo": art["logo"],
        "icon": art["icon"],
    }


def discover() -> dict:
    roots = steam_roots()
    if not roots:
        return {
            "ok": False,
            "error": "Steam install not found",
            "games": [],
        }

    installed: dict[str, str] = {}
    favorite_ids: set[str] = set()
    for root in roots:
        installed.update(load_installed_apps(root))
        for user_dir in find_userdata(root):
            for rel in (
                Path("7") / "remote" / "sharedconfig.vdf",
                Path("config") / "localconfig.vdf",
            ):
                path = user_dir / rel
                if path.is_file():
                    try:
                        text = path.read_text(encoding="utf-8", errors="ignore")
                    except OSError:
                        continue
                    favorite_ids |= parse_vdf_apps_with_favorite(text)

    games: list[dict] = []
    seen: set[int] = set()

    # Manual config: only if installed + is a game
    for g in load_manual_json():
        aid = g["appid"]
        key = str(aid)
        if key not in installed:
            continue
        name = installed.get(key) or g["name"]
        if not is_game(aid, name):
            continue
        if aid in seen:
            continue
        games.append(make_entry(aid, name, roots))
        seen.add(aid)

    # Favorites that are installed games
    for appid in sorted(favorite_ids, key=lambda x: int(x)):
        if appid not in installed:
            continue
        aid = int(appid)
        name = installed[appid]
        if not is_game(aid, name):
            continue
        if aid in seen:
            continue
        games.append(make_entry(aid, name, roots))
        seen.add(aid)

    # Fallback: all installed real games
    if not games:
        for appid, name in installed.items():
            aid = int(appid)
            if not is_game(aid, name):
                continue
            if aid in seen:
                continue
            games.append(make_entry(aid, name, roots))
            seen.add(aid)

    # Clean grid ordering: alphabetical, no source/installed prefixes.
    games.sort(key=lambda g: str(g["name"]).lower())

    return {
        "ok": True,
        "error": None,
        "steamRoots": [str(r) for r in roots],
        "games": games,
        "note": None,
    }


def main() -> int:
    result = discover()
    json.dump(result, sys.stdout, ensure_ascii=False)
    print()
    return 0 if result.get("ok") else 1


if __name__ == "__main__":
    raise SystemExit(main())
