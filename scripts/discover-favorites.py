#!/usr/bin/env python3
"""Discover Steam favorites / installed games and print JSON to stdout."""

from __future__ import annotations

import json
import os
import re
import sys
from pathlib import Path


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
    """Best-effort: find appid blocks that contain a favorite tag."""
    favorites: set[str] = set()
    # Match apps/<appid> ... tags ... "favorite"
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
    # Also catch tags { "0" "favorite" } near appid keys more loosely
    for match in re.finditer(
        r'"(\d{2,})"\s*\{[^}]*?"tags"\s*\{[^}]*?favorite[^}]*?\}',
        text,
        flags=re.IGNORECASE | re.DOTALL,
    ):
        favorites.add(match.group(1))
    return favorites


def load_app_names(root: Path) -> dict[str, str]:
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
    manual = load_manual_json()
    roots = steam_roots()
    if not roots and not manual:
        return {
            "ok": False,
            "error": "Steam install not found and no ~/.config/omarchy/steam-favorites.json",
            "games": [],
        }

    favorite_ids: set[str] = set()
    names: dict[str, str] = {}
    for root in roots:
        names.update(load_app_names(root))
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

    for g in manual:
        if g["appid"] not in seen:
            games.append(g)
            seen.add(g["appid"])

    for appid in sorted(favorite_ids, key=lambda x: int(x)):
        aid = int(appid)
        if aid in seen:
            continue
        games.append(
            {
                "appid": aid,
                "name": names.get(appid, f"App {appid}"),
                "source": "favorite",
            }
        )
        seen.add(aid)

    # Fallback: installed library (not true favorites) if nothing else
    if not games and names:
        for appid, name in sorted(names.items(), key=lambda kv: kv[1].lower()):
            games.append(
                {
                    "appid": int(appid),
                    "name": name,
                    "source": "installed",
                }
            )

    return {
        "ok": True,
        "error": None,
        "steamRoots": [str(r) for r in roots],
        "games": games,
        "note": (
            "Listed installed library (favorites not found in VDF). "
            "Optional: ~/.config/omarchy/steam-favorites.json"
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
