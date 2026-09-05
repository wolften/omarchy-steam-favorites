# Steam Favorites (Omarchy)

Bar widget that puts the Steam mark on the Omarchy bar and opens a two-column
grid of game covers. Click a cover to launch with `steam://rungameid/<id>`.

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
omarchy bar put io.github.wolften.steam-favorites --section right
```

## UI

- Bar slot uses the shared `BarIconButton` glyph canvas with a monochrome
  Steam mark that tints to the bar foreground (same optical slot as Dropbox,
  Tailscale, and the other brand icons).
- Dropdown is a two-column grid of portrait library covers (2:3), with the
  title over a bottom scrim. No "installed" prefixes.
- Artwork prefers the local Steam cache (`appcache/librarycache/<appid>`),
  then the public CDN (`library_600x900` → `library_capsule` → `header`).

## Usage

1. Left-click the Steam mark on the bar to open the panel.
2. Click a cover (or highlight with arrows and press Enter) to launch.
3. Middle-click the bar icon, or the ↻ control, to refresh.
4. Right-click the bar icon to open the Steam library.

## How games are discovered

`scripts/discover-favorites.py` (run by the panel) **only lists installed
games** (those with an `appmanifest_*.acf`). Tools are filtered out (Proton*,
Steam Linux Runtime*, Steamworks Common Redistributables, …). Each entry is
`appid`, `name`, `cover`, `logo`, and `icon`. The grid is alphabetical.

Order:

1. Manual list intersected with installed: `~/.config/omarchy/steam-favorites.json`
2. Favorites from VDF **that are also installed**
3. Fallback: all installed real games

Steam roots checked: `~/.steam/steam`, `~/.local/share/Steam`, Flatpak Steam data path.

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
