# Shared Settings panel: implementation plan

This plan answers Storage Mage's handoff, `StorageMage/docs/settings-panel-handoff.md` (2026-11-13). The user's
decisions from the handoff hold:

- **One panel for all of the user's mods**, with a tab for each installed mod.
- **Frame Mage isn't required.**
- **No Mod Menu.**
- **A copy of the panel ships in every mod**, and the newest copy draws.
- **Other authors' mods come later.**

## Where Frame Mage's panel stands today

The panel is `editor/settings.lua` (555 lines). Its rows are `core/options.lua` (222 lines): `SCHEMA` holds the rows
as data, and `apply` and `action` carry out a change. The data and the drawing are already apart; what holds the
panel to Frame Mage is what it borrows:

| Borrowed | From Frame Mage | The shared panel needs |
|---|---|---|
| Making widgets, the overlay host | `core/widgets`, `core/overlay` | Its own small copy (about 80 lines) |
| Hit-testing, screen size, the mouse | `core/geometry` | Its own copy (about 60 lines) |
| Clicks | the editor's catcher, `editor/mouse` (a hooked full-screen widget) | Its own catcher, open only while the panel is |
| Cursor and paused controls | `features/editor` `setEditInput`, `editor/inputblock` | Its own copy |
| Keys: the open key, key capture for key rows | `core/keys` (polls on the game thread) | A small poller of its own |
| Look: the frame, background, buttons, tooltips, the game font | `editor/style`, `core/themes`, `editor/legend` | Frame Mage's theme read from its files, or a plain look (step 4) |
| Settings, saving, effects of a change | `ctx.settings`, `options.apply` | Not moved: the owning mod does these (step 2) |

Storage Mage's `core` has no `widgets`, `geometry` or `overlay`, and its `keys` and `serialize` differ from Frame
Mage's. So the shared panel brings everything it uses and shares nothing with either mod's own code.

## The plan

### Step 1: a module with nothing of Frame Mage's

- **Where:** `shared/settingspanel/` at the repository's root is the only source (the monorepo's shared folder,
  owned by the Frame Mage session). It has no `require("framemage...")` or `require("storagemage...")`, and a test
  checks that. Each mod `require`s it as `settingspanel.*`.
- **Files:**

  | File | Holds |
  |---|---|
  | `panel.lua` | Drawing: tabs, rows, the dropdown, tooltips, dragging, scrolling, key capture |
  | `ui.lua` | Widgets, overlay, geometry, mouse catcher, input mode |
  | `input.lua` | Key polling and capture |
  | `look.lua` | The look: a theme or plain |
  | `serialize.lua` | Data-only reading and writing |
  | `protocol.lua` | Pure: schema checks, the host claim, requests and values |
  | `host.lua` | Which copy draws |
  | `client.lua` | What a mod calls to take part |

- **Drawing code:** it moves out of `editor/settings.lua` into `panel.lua`, close to as it is. The drawing has
  just been reworked (dropdown, icons, tooltips), so it is ported, not rewritten.
- **`PANEL_VERSION`:** in `settingspanel/version.lua`, raised on every change to the folder. A test fails if any
  file changed while the number stayed the same (it compares a checksum recorded next to the number).

### Step 2: every mod is a client, Frame Mage included

- **Answer to question 5:** Frame Mage's own settings go through the same channels. If Storage Mage's newer copy
  is drawing, Frame Mage's tab can only reach it through them anyway. One path, tested by both mods.
- **What a mod does:**

  ```lua
  local client = require("settingspanel.client")
  client.register{ mod = "FrameMage", title = "Frame Mage", schema = SCHEMA, values = function() ... end,
      apply = function(key, value) ... end, action = function(name) ... end }
  ```

- **What the client does:**
  - Publishes the schema and values.
  - Watches `requestRev` every 0.5 s (one number read).
  - Calls the mod's `apply` or `action`, then publishes the new values.
- **Frame Mage:** `options.apply` and `options.action` stay as they are and become its `apply` and `action`.
  `SCHEMA` becomes its schema.

### Step 3: the shared-variable channels

These are the handoff's names, accepted as written (question 4):

| Variable | Holds |
|---|---|
| `SettingsPanel.host`, `SettingsPanel.hostBeat` | Which copy draws, and its heartbeat |
| `SettingsPanel.registry` | The mods taking part |
| `SettingsPanel.<Mod>.schema`, `.values`, `.valuesRev` | Each mod's settings and their current values |
| `SettingsPanel.<Mod>.request`, `.requestRev` | Changes and button presses sent back to the mod |

Additions:

- **`SettingsPanel.prefs` + `prefsRev`:** the panel's own preferences: its open key, where it was dragged to, and
  the last tab. The drawing copy publishes them. Every copy saves them in its own mod's `config/settingspanel.lua`
  and offers its saved ones when it claims. So the open key and position survive a change of drawing copy.
- **`SettingsPanel.open` (0/1) and the panel's box:** published while the panel is open. Frame Mage's layout
  editor then leaves clicks inside the panel alone and pauses its own keys. This is how the panel opens over the
  editor whichever copy draws it.
- **A request carries an id,** and the owner echoes it back in `values` (`lastRequest`). The drawing copy shows a
  change as pending until it sees the echo, then shows the owner's real value. This covers a value the owner
  refused or clamped.
- **Schema data:**
  - Frame Mage's row types map onto the handoff's. Frame Mage's `toggle` is `bool`; `number` and `slider` are
    `int` and `float`; `button` is `action`; `info` is `text`; `choice` and `key` are the same.
  - Kept from Frame Mage's rows: `labels`, `icons` (game texture names), `suffix`, `percent`, `confirm`, `tooltip`.
  - From the handoff: `owner` and `serverOwned`; `applies` (`live` or `restart`, shown as "after a restart");
    sections with headings.
  - `protocol = 1`. A newer copy reads every older protocol; a row type it doesn't know is skipped, not an error.
- **Size:** a schema is a few KB, fine for a shared-variable string. The client checks that a value read back
  matches what it wrote. If a string comes back shorter, it splits it across numbered variables (`schema.1`,
  `schema.2`...). That's in from the start, and only used if needed.

### Step 4: which copy draws, and how it looks

- **Claim, settle and heartbeat:** as the handoff proposes. Each copy claims `SettingsPanel.host` at start-up if
  it's empty, an older version, or the same version from a mod whose name sorts later. After 3 s, only the holder
  draws. The holder bumps `hostBeat` every 2 s. If the beat stops for 6 s, the others claim again.
- **Pure logic, unit-tested:** the claim order, ties, a stale heartbeat, and a copy older than the one drawing.
- **The open key:** polled only by the drawing copy. The default stays F4 (question 2). Inside Frame Mage's
  editor, F4 opens the panel through `SettingsPanel.openRequest`, whichever copy draws.
- **Look (question 3):**
  - **With Frame Mage installed:** the drawing copy reads `FrameMage.theme`, loads that theme's `theme.lua` (data,
    through `serialize`) and its `ui/` pictures straight from Frame Mage's folder. It restyles when
    `FrameMage.themeRev` changes. This works the same from inside Storage Mage.
  - **Without Frame Mage:** a plain look, drawn without any pictures: dark glass, a thin gold edge, the game's
    font, the game's gold and white text. No art ships in each mod, and nothing can be missing.
  - **Icons:** game textures by name, as today. They're in the game, so every copy has them.

### Step 5: every mod's copy

Since the move into the monorepo there is one source and no copies in the repository:

- **Releases:** `tools/build.sh` already copies `shared/settingspanel/*.lua` into each mod's zip as
  `Scripts/settingspanel/`. (It copies only the folder's top level: keep the module flat, or extend the script.)
- **Development:** each mod's `tools/deploy.ps1 -Link` gets a step that links `shared/settingspanel/` in as
  `<Game>/Scripts/settingspanel/`. A mod's game `Scripts\` is already a junction into the repository, so that link
  sits inside `mods/<mod>/` and must be ignored by git there. Not done yet: neither deploy script does it today.
- **Tests:** each mod's `tests/run_tests.lua` adds `../../shared/?.lua` to `package.path`, so both suites run
  against the same source.
- **A check:** the `PANEL_VERSION` checksum test (step 1) still matters: players mix zips released at different
  times, and the claim in step 4 relies on the number going up with every change.
- **The handoff to Storage Mage:** the protocol, `client.register`, and an example schema for its section 8 (pickup
  routing, the two keys, the carry-weight slider, "Empty bags" with confirmation, a developer section). Storage
  Mage does its own side.

### Step 6: checks in game

1. Frame Mage alone: the panel opens with F4, in play and inside the editor. Every Frame Mage row still works:
   theme switch, dropdown, key capture, buttons with confirmation.
2. Storage Mage alone (Frame Mage disabled): the plain-look panel with Storage Mage's tab.
3. Both installed: one panel, two tabs, in Frame Mage's theme. Then Storage Mage's copy given a higher version: it
   draws, still in the theme. Then the drawing mod disabled: the other takes over within a few seconds.
4. A server-owned setting on a client joined to a dedicated server: shown grey with the server's value.

## Order and size

| Step | Work | Size |
|---|---|---|
| 1 | The module, ported from Frame Mage's panel | Large: about 1,200 lines moved or written |
| 2 | Client, Frame Mage as a client | Medium |
| 3 | Channels and schema checks, with tests | Medium |
| 4 | Host claim, plain look | Medium |
| 5 | Deploy link, test path, handoff to Storage Mage | Small |
| 6 | Checks in game | With the user |

Steps 1–4 land together: Frame Mage's panel must keep working at every commit. Until the move is done, the old
panel stays in place, and `features.settingsPanel = "shared"` switches to the new one so both can be compared.

## The user's decisions (2026-11-13)

All three as recommended, so the plan above stands as written and the work can start:

1. **Without Frame Mage, the panel is drawn without pictures:** dark glass, a thin gold edge, the game's font and
   text colors. No panel art ships in any mod.
2. **Frame Mage's own settings go through the shared channels,** like every other mod's.
3. **The open key stays F4,** set in the panel's own Keys rows and carried between copies by `SettingsPanel.prefs`.
