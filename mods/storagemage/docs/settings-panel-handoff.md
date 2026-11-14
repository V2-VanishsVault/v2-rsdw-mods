# Shared settings panel: handoff to the Frame Mage session

From the Storage Mage session, 2026-11-13. Frame Mage owns this work: the panel is Frame Mage's, and the
Storage Mage session doesn't change Frame Mage's files. Everything below about protocol details is a
proposal for the Frame Mage session to settle; the user's decisions are marked as such.

## 1. What the user decided (2026-11-13)

- **All of the user's mods use Frame Mage's settings panel** (the one that already covers Frame Mage's own
  settings), with a tab per installed mod.
- **Players must not have to install Frame Mage** to get the panel for Storage Mage (or any other of the
  user's mods).
- **No Mod Menu.** The user doesn't own it (so can't style or change it), doesn't want settings reached
  through the pause menu, and doesn't like how it looks or works. Storage Mage's design had planned Mod
  Menu for its carry-weight slider and its "Empty bags" action; those move to this panel.
- **Approach chosen:** the same panel code is shipped inside every one of the user's mods; at run time the
  newest copy draws the one panel and the others only publish their settings (section 3). A separate
  "Settings Panel" mod was considered and rejected because players would have to install it.
- **Other authors' mods:** later. The data protocol (section 4) is what would make that possible; keep it
  versioned, and document it for others only once it has settled.

## 2. Constraints that shape the design

- **Every UE4SS Lua mod runs in its own Lua state.** One mod can't call another's Lua functions or share
  Lua tables. Mods exchange only **plain values through UE4SS shared variables** (`ModRef:SetSharedVariable`
  / `GetSharedVariable`: strings, numbers, booleans; never UObjects) and **files**. Frame Mage already
  publishes `FrameMage.theme` / `FrameMage.themeRev` this way, and Storage Mage reads them (seen working
  in game, 2026-11-13: theme `elven`, rev 1).
- So **the panel is data-driven**: each mod describes its settings as data, the drawing copy renders them,
  and changes go back to the owning mod as data. The owning mod validates, applies and saves its own
  settings; the panel never writes another mod's files.
- Never keep a UObject across ticks; no `RegisterKeyBind` (keys are polled on the game thread); no
  per-frame scans or broad hooks (both mods' rules).
- Separate Lua states also mean no module-name clashes: each mod can `require` its copy of the panel
  under the same name.

## 3. One panel, many copies: which copy draws it

Proposal:
- Each copy has a `PANEL_VERSION` (a number, raised on every change to the panel code) and the mod's name.
- **Claim:** at start-up each copy reads `SettingsPanel.host` (`"<version>|<ModName>"`). If it's empty, or
  its version is lower, or equal with a name that sorts after its own, the copy writes its own. Mods start
  one after another on the game thread, so read-then-write is safe at start-up.
- **Settle:** a copy starts drawing (registers the panel key, builds its widgets lazily) only if it still
  holds `SettingsPanel.host` a few seconds after start-up. All others stay passive.
- **Liveness:** the host bumps `SettingsPanel.hostBeat` every few seconds. If the beat stops (the host mod
  was disabled or reloaded with UE4SS's mod reloading), the passive copies run the claim again.
- A copy that loses the claim never draws, even if it is newer than the panel version that was running
  when a world loaded: no two panels, ever.

## 4. The data protocol (proposal; `protocol = 1`)

Registry:
- `SettingsPanel.registry`: the names of the participating mods, `"FrameMage,StorageMage"`. Each mod adds
  its name at start-up (read, append if missing, write).

Per mod (`<Mod>` is the mod's folder name):
- `SettingsPanel.<Mod>.schema`: the mod's settings description, a string in a data-only format the panel
  parses and never runs (Frame Mage and Storage Mage share `core/serialize`, which already reads
  `return { ... }` data safely). Includes `protocol`, the tab title, sections and settings.
- `SettingsPanel.<Mod>.values` + `SettingsPanel.<Mod>.valuesRev`: the current values, serialized, published
  by the mod at start-up and whenever they change (including edits made by hand in `settings.lua`).
- `SettingsPanel.<Mod>.request` + `SettingsPanel.<Mod>.requestRev`: written by the drawing copy when the
  player changes a setting or presses an action button: `{ set = { key = value } }` or
  `{ action = "emptyBags" }`. The owning mod polls `requestRev` (about every 0.5 s, only a number read),
  applies the request, saves its own `settings.lua`, and publishes new values.

Setting types the schema needs (from Frame Mage's and Storage Mage's settings):
- `bool`; `int` / `float` with `min`, `max`, `step` (slider); `choice` (list of values with labels);
  `key` (a hotkey, the same spec strings both mods' `core/keys` parse); `action` (a button, with an
  optional confirmation text); `text` (read-only info line).
- Per setting: `key` (dot path into the settings table, e.g. `keys.sortBags`), `label`, `help`, `default`,
  `applies` (`"live"` or `"restart"`), and `owner` (`"local"` or `"server"`: see below).
- Per tab: `title`, optional `icon` (art name; see section 6), sections with headings.

Multiplayer: some of Storage Mage's settings belong to the server (pickup routing, the carry-weight
slider: the server applies them to every player). On a client joined to a dedicated server they show
read-only with the server's value, if the mod publishes it; the panel greys out `owner = "server"`
settings when the mod says so in its `values` (`serverOwned = true`).

## 5. Opening the panel

- **Not through the pause menu** (user). Its own hotkey, set in the panel itself and in the drawing mod's
  settings. Frame Mage's current panel key would be the natural default.
- Possibly also a small button on the inventory screen later (Storage Mage could provide one). Not needed
  for the first version.

## 6. Look

- With Frame Mage installed: Frame Mage's themes, hot-reloading on a theme switch as today.
- Without Frame Mage (a copy inside Storage Mage is drawing): the game's default look, with its own art
  shipped in each mod (same rule as Storage Mage's tab art: default art in the mod, themed copies only
  through Frame Mage). The drawing copy needs its art available whichever mod it lives in: either each
  mod ships the panel's default art, or the panel draws without textures when Frame Mage is absent.
  Frame Mage's call.

## 7. Keeping the copies the same

- One source of truth for the panel code, in the Frame Mage project (e.g. a `settingspanel/` module folder
  that doesn't depend on the rest of Frame Mage).
- Each other mod's deploy script copies it in (Storage Mage's `tools/deploy.ps1` already copies and links
  `Scripts\` and `Art\`; it would add the panel folder). No hand edits to the copies.
- Players with mods released at different times get different panel versions; the claim in section 3 makes
  the newest one draw. The newest copy must still render older `protocol` schemas.

## 8. What Storage Mage will put in its tab

Current and planned settings (Storage Mage's `defaults.lua`):
- Pickup routing on/off (`pickupRouting`; server-owned).
- Keys: sort into bags (`keys.sortBags`, Numpad /), take out (`keys.takeOut`, T).
- Carry-weight slider, 0–100 %, default 50 % (planned; server-owned).
- "Empty bags (before uninstalling)" action with a confirmation (planned).
- Developer section (feature switches, probe keys), hidden unless a developer setting is on.

Storage Mage will publish its schema and handle requests once Frame Mage has settled the protocol. Until
then its settings stay in `Mods\StorageMage\config\settings.lua`.

## 9. Questions for the Frame Mage session

1. Does Frame Mage's current panel split cleanly into a module with no other Frame Mage dependencies
   (widgets, theme lookup, input)? What has to come along?
2. Which panel key does it use today, and should the shared panel keep it?
3. How does Frame Mage's panel draw without Frame Mage's theme files (the copy inside Storage Mage)?
4. Any objection to the shared-variable names and the request/values channels above? Shared variable
   strings have no stated size limit in UE4SS's docs; Storage Mage's schema will be a few KB.
5. When the user wants it: should Frame Mage's own settings move to the same protocol (so it's just one
   more registered mod), or keep a private path?
