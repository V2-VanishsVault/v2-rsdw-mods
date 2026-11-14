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

- **Tests:** `lua tests/run_tests.lua` (919 pass on 2026-11-13). CI runs them for every push that changes this mod. In PowerShell, refresh PATH first so `lua` is found.
- **Static check:** `lua-language-server --check FrameMage/Scripts --checklevel=Warning`. About 119 problems is the
  baseline, mostly in the tests.
- **Deploy:** `tools/deploy.ps1 -Link`. It's already linked (the game's `ue4ss/Mods/FrameMage/Scripts` is a
  junction to this folder's `FrameMage/Scripts`, checked 2026-11-13), so script edits are live after a game restart.
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
- F4: Settings panel (in the editor)
- H: hidden-elements panel. A selected element that shows nothing is previewed as the game's own notice where it
  has one (`editor/preview.lua` NOTICES: the queue's collapsed entry, shown with example text and put back), else
  a plain stand-in at the size it last showed at (`editor/samples.lua`, saved in `config/sizes.lua`).
- Esc: closes the Settings panel, then the editor
- Ctrl+F9: widget and texture dumps
- Numpad +: API dump

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

## Not yet checked in game (do this first, with computer use)

Set the game to borderless windowed so screenshots aren't black.

1. **Vitals bars:**
   - Do the material-painted ends match the bars? If the log says "couldn't paint the bar ends", UV cropping failed.
   - Is there spacing with rings off and with shadows off?
   - Is the slimmer height (`heightScale` 0.68) still readable?
   - Do flat ends show with shaped bars off?
2. **Durability colours:** the log line "durability colours hold / are reset by the game" decides if a new approach is
   needed.
3. **Settings panel:** previous / CLOSE / next footer, arrows only when there's more, long text wrapping.
4. **Grid lines:** do they come back when "Show grid lines" is switched on again?
5. **Menu shortcuts:** can they be clicked and dragged with the key hints hidden (`bars.hideKeyHints`)?
6. **Interaction Prompt:** the chest / item tooltip is back on screen. It had been dragged off; the old layout is in
   `layouts/default.lua.bak`.

## Open items and plans

- **Survival vs buffs:** still one element. Needs a fresh Ctrl+F9 dump with buffs showing, then a split or our own
  replacement.
- **Hotbars:** `docs/hotbars-plan.md` covers 2 bars × 2 pages; the spell bar uses Numpad 0-9.
- **Bags:** handled in Storage Mage (`docs/bags-plan.md`).
- **Shared Settings panel** (replaces the earlier "Mod Menu replacement" idea; no Mod Menu, user 2026-11-13): one
  panel for all the user's mods, a tab per mod, a copy in every mod, the newest copy draws.
  - Request: `mods/storagemage/docs/settings-panel-handoff.md`.
  - Plan: `docs/settings-panel-plan.md`. The user approved its three recommendations (2026-11-13): no pictures
    without Frame Mage, Frame Mage's own settings through the shared channels, F4 as the open key. Ready to build.
  - Source: `shared/settingspanel/` at the repository's root (built into each mod's zip by `tools/build.sh`).
- **Storage Mage's tab art (F3):** its art list is in `mods/storagemage/docs/frame-mage-handoff.md` section 2
  (`T_SM_Tab_<Bag>_Normal/_Highlight`, 124x64). Themed copies go in `Art/themes/<theme>/storagemage/`.
- **Ideas:** `docs/ideas-from-other-mods.md` (from Relic Hunter UI and Rune UI; ideas only, see its licence note).
