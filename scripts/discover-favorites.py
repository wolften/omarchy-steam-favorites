#!/usr/bin/env python3
"""Discover installed Steam games (prefer favorites) and print JSON to stdout."""

from __future__ import annotations

import json
import re
import sys
from pathlib import Path

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
                        "source": "config",
                    }
                )
    return games


def discover() -> dict:
    roots = steam_roots()
    if not roots:
        manual = load_manual_json()
        if manual:
            # Without Steam roots we cannot verify install — return empty with hint
            return {
                "ok": True,
                "error": None,
                "games": [],
                "note": "Steam not found; cannot verify installed games. Install Steam or fix paths.",
            }
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
        games.append({"appid": aid, "name": name, "source": "config"})
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
        games.append({"appid": aid, "name": name, "source": "favorite"})
        seen.add(aid)

    # Fallback: all installed real games (no uninstalled favorites)
    if not games:
        for appid, name in sorted(installed.items(), key=lambda kv: kv[1].lower()):
            aid = int(appid)
            if not is_game(aid, name):
                continue
            games.append({"appid": aid, "name": name, "source": "installed"})

    return {
        "ok": True,
        "error": None,
        "steamRoots": [str(r) for r in roots],
        "games": games,
        "note": (
            "Showing installed games (no favorites found in VDF)."
            if games and all(g.get("source") == "installed" for g in games)
            else None
        ),
    }


def main() -> int:
    result = discover()
    json.dump(result, sys.stdout, ensure_ascii=False)
    print()
    return 0 if result.get("ok") else 1


if __name__ == "__main__":
    raise SystemExit(main())
