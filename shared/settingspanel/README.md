# Shared Settings panel

The one Settings panel every mod in this repository draws its settings in: a tab per mod, F4 to open it (plan:
`mods/framemage/docs/settings-panel-plan.md`). It is never built, tagged or released on its own:

- **Releases:** `tools/build.sh` copies this folder's `*.lua` files (not `tests/`) into each mod's
  `Scripts/settingspanel/`.
- **Development:** each mod's `tools/deploy.ps1 -Link` links this folder in as `<Game>/Scripts/settingspanel` (a
  junction inside the mod's own `Scripts/`, ignored by git); a copy install copies the `*.lua` files.
- **Tests:** `lua shared/settingspanel/tests/run_tests.lua` from the repository's root. Both mods' test runs include
  them too.

## How it works

Every UE4SS mod runs in its own Lua state, so mods share only plain values (UE4SS shared variables). Each mod ships
a copy of this folder; the newest copy draws the one panel, and every mod (the drawing one too) takes part as a
client:

| File | Holds |
|---|---|
| `main.lua` | `start{ mod, dir }`: the host claim (which copy draws), the heartbeat, the open key |
| `client.lua` | `register{ mod, title, tabs, rows, get, apply, action }`: a mod's tab; `changed()` republishes values |
| `panel.lua` | The drawing: tabs, rows, the drop-down list, key capture, dragging, paging |
| `protocol.lua` | Pure: the claim order, schemas, requests, values, display (unit-tested) |
| `look.lua` | Frame Mage's theme (published by Frame Mage as `FrameMage.look`), or a plain look without pictures |
| `input.lua` | Keys polled from the player controller (never `RegisterKeyBind`) |
| `game.lua` | Scheduling, shared variables, widgets, the screen and mouse, the input mode |
| `serialize.lua` | Data-only reading and writing |
| `version.lua` | `PANEL_VERSION` and a checksum of the files |

**Changing anything here:** raise `PANEL_VERSION` in `version.lua` and set `CHECKSUM` to what the tests print. Players
mix mods released at different times, and the highest version draws.

Shared variables: `SettingsPanel.host` / `hostBeat` (who draws), `SettingsPanel.registry` (the mods),
`SettingsPanel.<Mod>.schema` / `values` / `request` (+ `Rev` counters), `SettingsPanel.prefs` (the open key,
position, last tab; each copy also saves them in its mod's `config/settingspanel.lua`), and for Frame Mage's editor
`SettingsPanel.open`, `.box` and `.closedAt`. Frame Mage publishes `FrameMage.look` / `lookRev` and
`FrameMage.editorOpen`.

The Frame Mage session owns this folder.
