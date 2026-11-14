# Frame Mage: session handoff (2026-11-08, updated 2026-11-13)

Paste this into a new session opened in `C:\Developer\v2-rsdw-mods\mods\framemage`.

## What this is

Frame Mage is a UI-only UE4SS Lua mod for RuneScape: Dragonwilds (UE 5.6). It lets you move, scale, fade and hide
HUD elements in an editor, reskins the HUD with themes, and restyles the vitals bars. It's one of a "Mage" family:
- Frame Mage (UI)
- Storage Mage (bags and inventory, server-side): `C:\Developer\v2-rsdw-mods\mods\storagemage`, its own session
- Map Mage, Spell Mage (later)

Both live in the `v2-rsdw-mods` monorepo (`C:\Developer\v2-rsdw-mods`). Its `CLAUDE.md` has the rules for sessions
working side by side; the root `README.md` covers building (`tools/build.sh`) and releasing (a tag
`framemage-v<version>`). `shared/settingspanel/` (the shared Settings panel, not written yet) belongs to this
session.

## Working rules

- **Tests:** `lua tests/run_tests.lua` (1104 pass on 2026-11-14). CI runs them for every push that changes this mod. In PowerShell, refresh PATH first so `lua` is found.
- **Static check:** `lua-language-server --check FrameMage/Scripts --checklevel=Warning`. About 119 problems is the
  baseline, mostly in the tests.
- **Deploy:** `tools/deploy.ps1 -Link`. It's already linked (the game's `ue4ss/Mods/FrameMage/Scripts` is a
  junction to this folder's `FrameMage/Scripts`, checked 2026-11-13), so script edits are live after a game restart.
  Run it once more after 2026-11-14 to link `dev/` too (`Mods/FrameMage/dev`).
- **Developer features live in `dev/`** (2026-11-14): `inspector` (Ctrl+F9 dumps), `devkeys` (Ctrl+F10 art reload,
  Ctrl+F8 celebration preview), `apidump` (Numpad +, with `framemage/data/api_classes.lua`), listed in
  `dev/features.lua`. Releases don't contain `dev/`, and the banner outside the editor shows only with it
  (`ctx.dev`); Settings rows marked `dev = true` likewise. Shipping code must never `require` a `dev/` module (the
  tests check it).
- **Game files:** `C:\Program Files (x86)\Steam\steamapps\common\RSDragonwilds\RSDragonwilds\Binaries\Win64\ue4ss\`
  - log: `UE4SS.log`
  - dumps: `Mods/FrameMage/dumps/` (`widgets.txt`, `textures.txt`, `materials.txt`, `api.txt`)
  - user settings: `Mods/FrameMage/config/settings.lua`
  - layouts: `Mods/FrameMage/layouts/`
- **Commits:** commit only when asked, and only this mod's paths (`git add mods/framemage listings/framemage`).
  The last Frame Mage commit is `a509174` (the move into the monorepo). End commit messages with
  `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`.
- **Python edits:** write patch scripts to a scratchpad file or a quoted heredoc. Bash heredocs with mixed quotes
  broke before.
- **Pillow:** installed (`tools/make_badges.py`, `tools/make_bar_ends.py` use it).

## Keys

- F9: editor
- F3: hotkey list
- F4: the shared Settings panel (in play or in the editor; its own key, set on its Panel tab)
- H: hidden-elements panel. A selected element that shows nothing is previewed as the game's own notice where it
  has one (`editor/preview.lua` NOTICES: the queue's collapsed entry, shown with example text and put back), else
  a plain stand-in at the size it last showed at (`editor/samples.lua`, saved in `config/sizes.lua`).
- Esc: closes the Settings panel, then the editor
- Development install only (`dev/`): Ctrl+F9 widget and texture dumps, Ctrl+F10 art reload, Ctrl+F8 celebration
  preview, Numpad + API dump
- 2026-11-14: for one whole session no hotkey worked and the log said nothing; the next start they worked. The
  poll loop now logs its first run ("keys: polling"), the player controller it reads ("keys: reading keys from"),
  each press ("keys: edit pressed (F9)"), and a watchdog starts the loop again if it stops ("keys: polling
  stopped"). If keys die again, that warning (or its absence) says whether the loop or the input was at fault.

## Key technical facts

- **Geometry:** UE4SS can't read FGeometry or FPointerEvent. Widget rects are computed in `core/measure.lua`; the
  mouse position comes from `GetMousePositionOnViewport`, buttons from player-controller key state.
- **Replacing widgets:** `ReplaceChildAt` isn't callable. Collapse the game widget, then add ours with
  `AddChildToOverlay`.
- **Class lookup:** classes can't be enumerated. The API dump uses `data/api_classes.lua`, generated from the
  `.usmap` by `tools/gen_api_classes.py`.
- **Editor elements:** the "units" model is in `editor/units.lua`.
  - Click-picking ranks visible elements before empty placeholders, smallest first; clicking again steps through.
  - Drags are kept 48 units on screen.
- **Themes:** `Art/themes/<theme>/` with fallback to `elven`. Theme ids: dwarven, elven (aliases "general",
  "demihuman", "default"), ranger, warrior, wizard.
- **Panel backgrounds** (setting `stone`): "theme" (each theme's own: `background` in its theme.lua) and paintings
  (silk, forge, leather, oak, starfield, slate, dragonscale, parchment, mists, embers, abyss, aurora:
  `tools/make_backgrounds.py` from `tools/backgrounds_src/`, drawn at 256 units). Removed names (moonstone, marble,
  tapestry, glacier) load as the theme's own.
- **Settings panel:** `editor/settings.lua`, with rows defined in `core/options.lua`. Mod Menu support was removed.

## Vitals bars (`features/bars.lua`), current design

- **Game icons:** each stays in the layout, hidden and scaled to 0. The game aligns the three bars through each
  icon's size and padding, so collapsing an icon shifted the special bar.
- **Rings:** our rings (dark disc, gold ring, shadow) sit centred on the bar start.
- **Stamina icon:** shows the Agility icon (`T_Icon_Tag_Skill_Agility`). Its path is learned the first time the game
  shows it and saved to `config/texture-paths.lua`; the ring swaps live.
- **Body:** our dark track, game fill, style shading (flat / bevel / facet), gold edge. The `bars.*` settings
  control it.
- **Row height:** fixed at `bars.rowPitch` (54) whatever the ring and shadow settings.
- **Ends:** a point (`bars.taper`) or a 3-unit flat end. The end's colour is the bar's own material, in 1-unit strips
  cropped by brush UV region (`materialStrips`). The fallback is the tinted cap (`bars.tipFromMaterial = false`).
- **Durability bars:** colour bands: red to 25%, orange to 50%, yellow to 75%, green above.

## Checked in game (2026-11-14, with computer use)

Passed:
- **Vitals bars:** the pointed ends are painted in each bar's own color (no "couldn't paint the bar ends" in the
  log); spacing stays even with ring shadows off and with icons on rings off; the slimmer height is readable; flat
  ends show with shaped bars off.
- **Settings panel:** page 1 has CLOSE + "next", the last page "previous" + CLOSE, tabs that fit have neither; long
  text wraps (Share tab). Paging by `ROWS - 1` repeats one row across pages on purpose.
- **Grid lines** go away and come back with "Show grid lines".
- **Menu shortcuts** can be selected and dragged with the key hints hidden; Ctrl+Z puts them back.
- **Interaction Prompt** is on screen (the "Collect" prompt over a dropped item).
- **Empty elements** (today's previews): Experience Progress shows the new plain stand-in with its name.

Found:
1. **Durability colors need a new approach:** the log says "durability colors are reset by the game" (239 bars).
2. **The notice queue's stand-in** (Achievement Level Up Skill Unlock) is narrower than its name: it shows
   "Achievement Level", with a clipped second line under it. The game's own notice with example text
   (`editor/preview.lua` NOTICES) didn't show for it.
3. **Editor clicks near the top right** (over Item Pickups, x ≈ 3940 of 4040 UI units, y ≈ 450-520) never reached
   the editor (no "editor click" in the log), while clicks lower on the same side did. Probably a game widget there
   takes the click first (the Item Pickups column is the likeliest). The user says it isn't the Mini Map mod
   (on for several restarts by 2026-11-14). PgDn still reaches those elements.
   - **Mini Map** (a C++ mod, `Mods/MiniMap/dlls/main.dll`, installed with Vortex) draws a map at the top right.
     The user plans a similar widget in Map Mage, so it isn't being fixed; if it's enabled again, check that its
     widget doesn't catch editor clicks there too.
4. In automation, keys and clicks held for under about 0.1 s are sometimes missed (the game polls); people won't
   notice.

## Open items and plans

- **Survival vs buffs:** staying one element (the user, 2026-11-14: no split needed). The stacked gauges' size is a
  setting now (Settings, Vitals: "Survival gauge size", `bars.survivalRingSize`, 24 to 96; rings bigger than the spacing of the bars spread apart, centered on them).
- **Hotbars:** `docs/hotbars-plan.md` covers 2 bars × 2 pages; the spell bar uses Numpad 0-9.
- **Bags:** handled in Storage Mage (`docs/bags-plan.md`).
- **Shared Settings panel** (replaces the earlier "Mod Menu replacement" idea; no Mod Menu, user 2026-11-13): one
  panel for all the user's mods, a tab per mod, a copy in every mod, the newest copy draws.
  - Request: `mods/storagemage/docs/settings-panel-handoff.md`.
  - Plan: `docs/settings-panel-plan.md`. The user approved its three recommendations (2026-11-13): no pictures
    without Frame Mage, Frame Mage's own settings through the shared channels, F4 as the open key.
  - **Built 2026-11-14** (steps 1–5): `shared/settingspanel/` (98 tests), Frame Mage as a client
    (`core/panelshared.lua`: its rows, `FrameMage.look`, `FrameMage.editorOpen`; the editor's keys wait while the
    panel is open), Storage Mage as a client. `settingsPanel = "own"` brings back `editor/settings.lua`. Next: the
    in-game checks (plan, step 6).
  - Source: `shared/settingspanel/` at the repository's root (built into each mod's zip by `tools/build.sh`).
- **Storage Mage's tab art (F3):** its art list is in `mods/storagemage/docs/frame-mage-handoff.md` section 2
  (`T_SM_Tab_<Bag>_Normal/_Highlight`, 124x64). Themed copies go in `Art/themes/<theme>/storagemage/`.
- **Ideas:** `docs/ideas-from-other-mods.md` (from Relic Hunter UI and Rune UI; ideas only, see its licence note).
