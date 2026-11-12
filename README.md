# Frame Mage

A UE4SS Lua mod for RuneScape: Dragonwilds, and the UI member of the Mage family (Map Mage, Storage Mage and
Spell Mage cover the rest). Move, scale, fade or hide **any** UI widget (HUD and menus) in an in-game editor, and
reskin UI art with your own PNGs, with no asset cooking. Frame Mage is about the UI only.

> Created using intellectual property belonging to Jagex Limited under the terms of Jagex's Fan Content Policy.
> This content is not endorsed by or affiliated with Jagex.

## Install

Requires the UE4SS **experimental** build (it needs `LoopInGameThreadWithDelay` / `NotifyOnNewObject`).

```
powershell -ExecutionPolicy Bypass -File tools\deploy.ps1
```

This copies `FrameMage/` into `...\Binaries\Win64\ue4ss\Mods\FrameMage` and enables it with `enabled.txt`.
Your `config/`, `layouts/`, `dumps/` and `Art/` in the game folder are never overwritten. Restart the game.

**Conflicts:** other mods that move HUD widgets (e.g. Rune UI) will fight over the same widgets; run one or the other.

## Troubleshooting

Look for `[FrameMage]` lines in `ue4ss/UE4SS.log`. To isolate a crash, set a feature to `false` under
`features = { ... }` in `config/settings.lua` and restart.

## Settings

Press **F4** while the editor is open (F9) for Frame Mage's own Settings panel, drawn in the theme: tabs for Look,
Vitals, Editor, Celebrations, Keys and Layouts. Click a toggle to flip it; click the left or right half of a value to
step it back or forward; click a key and press the new one to rebind it (Esc cancels). Everything is saved to
`config/settings.lua`, which you can also edit by hand (restart to apply). The rows come from `core/options.lua`.

## Celebrations (replacing the game's widgets)

Frame Mage can hide one of the game's widgets and show its own in its place. The first is the **level-up popup**:
instead of the game's circle, firework bursts go off around your new level, which zooms in on a golden glow under
the skill's name and icon. It says "Max level!" when you've maxed a skill, and the game's level-up sound still plays.
As the number lands, a **DING!** rings: a bell synthesized live with the game's Modular Synth (a strike at ~1.3 kHz
with a bell's 2.76x overtone and a 1.6 s ring-out). Volume and on/off are in Settings (Celebrations), and `ding.asset` can point at a
sound asset to play instead.
Turn it off in Settings (Celebrations), and press **Ctrl+F8** or the Preview button there to see it without leveling.

How it works: the game's popup is detected when it's created or given new data, its level and skill are read from
the game's own notification data (`NotificationSkillUpData.Level`, `SkillData.Name` / `MaxLevel`), and the popup is
set to *Hidden*, never removed, so the game's notification queue, timing and sound carry on as normal. The first
time a real one appears, its structure is written to `UE4SS.log`. More replacements can be added in
`features/replace.lua`.

## Sharing layouts

**Export** writes the current layout to `Mods/FrameMage/share/<layout>.framemage.txt`. To use someone else's, put
their file in `share/`, type its name under "File to import" and press **Import**. It replaces the current layout,
and the old one is kept as `layouts/<layout>.before-import.lua`. Imported files are read as data only, with every
value checked, so a shared file can't run code.

## Keys (all configurable in Settings > Keys or `config/settings.lua`)

While the editor is open, a list of these keys (drawn like the game's own key prompts) shows on the left of the
screen. Key names are Unreal's (`PageDown`, `LeftBracket`, `LeftMouseButton`); combos take `CTRL+` / `SHIFT+` / `ALT+`.

| Key | Action |
|---|---|
| F9 | Toggle the layout editor (shows the mouse cursor and pauses game input while open) |
| Left click | Select the widget under the cursor (small parts like key icons are skipped). Click the same spot again to select its parent, and so on outward |
| Drag the gold title bar | Move the selected widget; it snaps to the grid when you let go (if the grid is on) |
| Right click | Select the parent |
| PgDn / PgUp | Next / previous element on screen |
| H | Also list hidden elements (previewed when selected); press again to drop them |
| Ctrl + PgDn / PgUp | Next / previous sibling (other parts of the same panel) |
| Home / End | Select parent / first child (reach any widget in the tree) |
| Arrows | Move. With the grid on, jump to the next spot where an edge sits on a grid line |
| Shift + Arrows | Big move (grid on: next major line) |
| Ins | Toggle grid + snapping (off = free movement by `editor.step`) |
| `+` / `-` | Scale |
| `[` / `]` | Fade out / in |
| Del | Hide / unhide |
| Backspace | Reset element |
| F7 | Next layout profile |
| Ctrl+F9 | Dump on-screen widgets and texture names to `dumps/` |
| Ctrl+F10 | Reload art |
| Ctrl+F8 | Preview the level-up celebration |

### Controller

Click both sticks to open or close the editor. While it's open: **LB / RB** previous / next element, **A** child,
**B** parent, **left stick** move (it snaps to the grid when you let go), **D-pad** nudge, **LT / RT** scale,
**X** hide / show, **Y** grid on / off, **RS** (click) reset. The hotkey list switches to these buttons as soon as you
use the pad. Buttons are Xbox names; the same positions work on other pads.

## Themes

Frame Mage has four high-fantasy themes, picked in Settings (**Look > Theme**) or with `theme = "..."` in
`config/settings.lua`:

| Theme | Look | Status |
|---|---|---|
| `elven` (default, "Elven") | moonstone and wispy gold light: High Elf meets Dwarven | Frame Mage's own panels done; game art in progress |
| `warrior` | | coming soon (uses Elven's art meanwhile) |
| `ranger` | | coming soon |
| `wizard` | | coming soon |

A theme is a folder, `Art/themes/<theme>/`:

- **`<TextureName>.png`** replaces that game texture everywhere.
- **`materials.lua`** re-colors animated effects (see below).
- **`ui/`** holds Frame Mage's own panels, title bars and keycaps (`python tools/make_theme.py` makes Elven's).
- **`theme.lua`** sets colors and sizes for Frame Mage's own panels.

Anything a theme doesn't have comes from `elven`, so a new theme can start empty.

## Reskinning game art

1. In game, open the screens you want to reskin and press **Ctrl+F9** on each. `dumps/textures.txt` builds a
   list of every UI texture with its pixel size, the size it's drawn at, whether it's 9-sliced, and where it
   was first seen.
2. Save `Art/themes/<theme>/<TextureName>.png` at that size (or the same shape at 2x).
3. Press **Ctrl+F10**.

To find a texture's original image, browse the game paks with FModel using the `.usmap` in `ue4ss/`.

### Animated effects (materials)

Bars, rings, highlights and vignettes are *materials*, which are shaders. A PNG would flatten them, so theme
their parameters instead and the fills and animation keep working:

1. Press **Ctrl+F9** with the effect on screen. `dumps/materials.txt` lists every effect, its parameters and their
   current values, as ready-to-copy entries.
2. Copy `Art/themes/elven/materials.example.lua` to your theme's `materials.lua`, paste in the entries you want, and edit the values.
   Colors can be `"#RRGGBB"`, which is treated as sRGB like a color picker.
3. Press **Ctrl+F10**. Add `force = true` for parameters the game animates itself.

Shared material assets are never edited: a brush that uses one gets its own dynamic copy, and that copy is themed.
Remove an entry and reload to restore the original values.

## How it works

- **Identity.** Each element gets a stable key from its place in the widget tree, such as
  `WBP_HUD/SurvivalPanel`. Runtime list entries share one key (`WBP_HUD/WBP_BuffEntry*`), so editing one
  applies to all of them.
- **Layout.** Changes use the widget's *render transform* (translation, scale, opacity). These apply after
  layout, so moving an element never reflows its neighbors and works on any panel type. Layouts are saved
  per profile in `layouts/<profile>.lua` and re-applied every 200 ms in case game animations reset them.
- **Mouse.** While the editor is open, a transparent full-screen catcher of Frame Mage's own takes the clicks, and
  Unreal's own UserWidget mouse events are hooked on it. Reading the button from the player controller didn't work
  in game, because the game's UI framework (CommonUI) decides whether the game sees a click at all.
- **Selection.** A frame with corner brackets and a gold title bar (the drag handle) follows the selected widget. An element with nothing to show
  right now (boss bar, empty notification) is previewed while selected: shown with its designed default
  content, with placeholder labels in empty text fields. Everything is put back when you select something else.
- **Only what you change is enforced.** A moved element keeps the game's own fades and a faded one keeps its
  slide animations: only the properties you edited are re-applied.
- **Grid.** It's centered on the screen, with a 16-unit cell and a major line every 4 cells (`grid` in settings).
  Snapping measures the element's real on-screen rectangle (`GetCachedGeometry`), then moves it until its
  nearer edge reaches the next line, so left- and right-anchored elements both line up.
- **Art.** `Image`/`Border` brushes are matched by texture name, and the PNG is loaded with
  `KismetRenderingLibrary.ImportFileAsTexture2D`. Brushes are swapped when their widget appears and when
  the game calls a brush setter (hooked), so brushes that change at runtime are covered too.
- **Handle safety.** Features never keep widget handles for long. A handle to a freed widget can pass
  `IsValid` once its memory is reused, and reading it crashes the game. Handles are used in the tick they
  arrive in; the few kept for edited elements are dropped on every world change.
- **Threading.** All engine work runs on the game thread (`LoopInGameThreadWithDelay`). Hotkeys don't use
  `RegisterKeyBind`: its callbacks run Lua on UE4SS's input thread, which crashed this game under fast key
  presses. Instead the player controller's key state is polled every frame on the game thread
  (`core/keys.lua`), which also makes live rebinding possible.

## Layout of this repo

```
FrameMage/Scripts/main.lua               entry; FEATURES list
FrameMage/Scripts/framemage/core/       log, fs, serialize, config, sched, events, keys, widgets, overlay, names, theme, geometry
FrameMage/Scripts/framemage/features/   layout, art, materials, grid, editor, inspector, share, celebrate,
                                          replace, bars  (add new features here)
FrameMage/Scripts/framemage/editor/     frame, preview, picker, legend, banner (parts of the layout editor)
tests/run_tests.lua                       unit tests for the engine-independent code (lua tests/run_tests.lua)
.luarc.json                               Lua Language Server config (Lua 5.4 + UE4SS globals); static check:
                                          lua-language-server --check=. --checklevel=Warning
tools/deploy.ps1                          install into the game (-Link: live junctions for development)
tools/make_icons.py                       regenerate Frame Mage's own UI art (mouse glyphs, keycap, parchment ribbon)
```

### Adding a feature

Create `FrameMage/Scripts/framemage/features/<name>.lua` returning a table with `init(ctx)`, then add
`"<name>"` to `FEATURES` in `main.lua`. `ctx` provides `settings`, `log`, `sched`, `events`, `keys`,
`widgets`, `config`, `fs` and the other features (`ctx.features.layout`, and so on). Listen to
`events.on("userwidget", fn)` instead of scanning: a full `FindAllOf("UserWidget")`
walks 7–10k objects.
