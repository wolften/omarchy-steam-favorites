# Steam Favorites (Omarchy Quattro)

Bar widget that lists Steam favorites (or installed games / a manual JSON list) and launches them with `steam://rungameid/<id>`.

Plugin id: `io.github.wolften.steam-favorites`

## Install

```sh
omarchy plugin add https://github.com/wolften/omarchy-steam-favorites.git --enable
```

Or manually:

```sh
git clone https://github.com/wolften/omarchy-steam-favorites.git \
  ~/.config/omarchy/plugins/io.github.wolften.steam-favorites
omarchy plugin validate ~/.config/omarchy/plugins/io.github.wolften.steam-favorites
omarchy plugin enable io.github.wolften.steam-favorites
omarchy-shell shell rescanPlugins
```

Place on the bar if needed:

```sh
omarchy bar put io.github.wolften.steam-favorites --section left
```

## UI

Panel shows a **2-column grid** with Steam CDN covers (`library_600x900`, falling back to `capsule_231x87`) and titles clipped with ellipsis. Covers are public CDN URLs by appid — no Steam Web API scraping.

## Usage

1. Click **Steam** on the bar to open the panel.
2. Click a game to launch via `steam://rungameid/<appid>` (Steam must be installed).
3. Use **↻** to refresh the list.

## How games are discovered

`scripts/discover-favorites.py` (run by the panel) **only lists installed games** (those with an `appmanifest_*.acf`). Non-games are filtered out (Proton*, Steam Linux Runtime*, Steamworks Common Redistributables, …).

Order:

1. Manual list intersected with installed: `~/.config/omarchy/steam-favorites.json`
2. Favorites from VDF **that are also installed**
3. Fallback: all installed real games

Steam roots checked: `~/.steam/steam`, `~/.local/share/Steam`, Flatpak Steam data path.

The bar uses a monochrome Steam glyph (`assets/steam-glyph.png`) tinted to the bar foreground.

### Manual JSON (recommended if favorites do not sync locally)

```json
[
  { "appid": 570, "name": "Dota 2" },
  { "appid": 730, "name": "Counter-Strike 2" }
]
```

Copy from `example-steam-favorites.json` in this repo.

## Validate

```sh
omarchy plugin validate ~/.config/omarchy/plugins/io.github.wolften.steam-favorites
```

## Remove

```sh
omarchy plugin remove io.github.wolften.steam-favorites
```

## Notes

- Requires `python3` on PATH for discovery.
- Modern Steam may not keep favorites in local VDF; use the JSON file if the panel only shows installed games.
- Plugins run unsandboxed inside `omarchy-shell` — review the code before enabling.

## Review

Opened for @Revisador against Quattro develop guide.
