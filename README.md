# Forgeframe

A UE4SS Lua mod for RuneScape: Dragonwilds. Move, scale, fade or hide **any** UI widget (HUD and menus), and
reskin UI art with your own PNGs, with no asset cooking. It's built as a small core plus feature modules so more
features can be added over time.

> Created using intellectual property belonging to Jagex Limited under the terms of Jagex's Fan Content Policy.
> This content is not endorsed by or affiliated with Jagex.

## Install

Requires the UE4SS **experimental** build (it needs `LoopInGameThreadWithDelay` / `NotifyOnNewObject`).

```
powershell -ExecutionPolicy Bypass -File tools\deploy.ps1
```

This copies `Forgeframe/` into `...\Binaries\Win64\ue4ss\Mods\Forgeframe` and enables it with `enabled.txt`.
Your `config/`, `layouts/`, `dumps/` and `Art/` in the game folder are never overwritten. Restart the game.

**Conflicts:** other mods that move HUD widgets (e.g. Rune UI) will fight over the same widgets; run one or the other.

## Troubleshooting

Look for `[Forgeframe]` lines in `ue4ss/UE4SS.log`. To isolate a crash, set a feature to `false` under
`features = { ... }` in `config/settings.lua` and restart.

## Keys (all configurable in `config/settings.lua`)

| Key | Action |
|---|---|
| F9 | Toggle the layout editor (shows the mouse cursor and pauses game input while open) |
| Left click | Select the widget under the cursor. Click the same spot again to select its parent, and so on outward |
| PgDn / PgUp | Next / previous element, including ones that are currently empty or hidden |
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

## Reskinning

1. In game, open the screens you want to reskin and press **Ctrl+F9** on each. `dumps/textures.txt` builds a
   list of every UI texture name.
2. Save `Art/<skin>/<TextureName>.png` (match the size shown in `dumps/widgets.txt`).
3. Press **Ctrl+F10**. Switch skins with `skin = "..."` in `config/settings.lua`.

To find a texture's original image, browse the game paks with FModel using the `.usmap` in `ue4ss/`.

### Animated effects (materials)

Bars, rings, highlights and vignettes are *materials*, which are shaders. A PNG would flatten them, so theme
their parameters instead and the fills and animation keep working:

1. Press **Ctrl+F9** with the effect on screen. `dumps/materials.txt` lists every effect, its parameters and their
   current values, as ready-to-copy entries.
2. Copy `Art/<skin>/materials.example.lua` to `materials.lua`, paste in the entries you want, and edit the values.
   Colours can be `"#RRGGBB"`, which is treated as sRGB like a colour picker.
3. Press **Ctrl+F10**. Add `force = true` for parameters the game animates itself.

Shared material assets are never edited: a brush that uses one gets its own dynamic copy, and that copy is themed.
Remove an entry and reload to restore the original values.

## How it works

- **Identity.** Each element gets a stable key from its place in the widget tree, such as
  `WBP_HUD/SurvivalPanel`. Runtime list entries share one key (`WBP_HUD/WBP_BuffEntry*`), so editing one
  applies to all of them.
- **Layout.** Changes use the widget's *render transform* (translation, scale, opacity). These apply after
  layout, so moving an element never reflows its neighbours and works on any panel type. Layouts are saved
  per profile in `layouts/<profile>.lua` and re-applied every 200 ms in case game animations reset them.
- **Selection.** A frame with corner brackets follows the selected widget. An element with nothing to show
  right now (boss bar, empty notification) is previewed while selected: shown with its designed default
  content, with placeholder labels in empty text fields. Everything is put back when you select something else.
- **Only what you change is enforced.** A moved element keeps the game's own fades and a faded one keeps its
  slide animations: only the properties you edited are re-applied.
- **Grid.** It's centred on the screen, with a 16-unit cell and a major line every 4 cells (`grid` in settings).
  Snapping measures the element's real on-screen rectangle (`GetCachedGeometry`), then moves it until its
  nearer edge reaches the next line, so left- and right-anchored elements both line up.
- **Art.** `Image`/`Border` brushes are matched by texture name, and the PNG is loaded with
  `KismetRenderingLibrary.ImportFileAsTexture2D`. Brushes are swapped when their widget appears and when
  the game calls a brush setter (hooked), so brushes that change at runtime are covered too.
- **Handle safety.** Features never keep widget handles for long. A handle to a freed widget can pass
  `IsValid` once its memory is reused, and reading it crashes the game. Handles are used in the tick they
  arrive in; the few kept for edited elements are dropped on every world change.
- **Threading.** All engine work runs on the game thread (`LoopInGameThreadWithDelay`). UE4SS keybind
  callbacks are moved onto it, because Lua running on UE4SS's own thread can crash the game.

## Layout of this repo

```
Forgeframe/Scripts/main.lua               entry; FEATURES list
Forgeframe/Scripts/forgeframe/core/       log, fs, serialize, config, sched, events, keys, widgets, overlay, names, theme, geometry
Forgeframe/Scripts/forgeframe/features/   layout, art, materials, grid, editor, inspector  (add new features here)
Forgeframe/Scripts/forgeframe/editor/     frame, preview, picker (parts of the layout editor)
tests/run_tests.lua                       unit tests for the engine-independent code (lua tests/run_tests.lua)
.luarc.json                               Lua Language Server config (Lua 5.4 + UE4SS globals); static check:
                                          lua-language-server --check=. --checklevel=Warning
tools/deploy.ps1                          install into the game
```

### Adding a feature

Create `Forgeframe/Scripts/forgeframe/features/<name>.lua` returning a table with `init(ctx)`, then add
`"<name>"` to `FEATURES` in `main.lua`. `ctx` provides `settings`, `log`, `sched`, `events`, `keys`,
`widgets`, `config`, `fs` and the other features (`ctx.features.layout`, and so on). Listen to
`events.on("userwidget", fn)` / `("brushwidget", fn)` instead of scanning: a full `FindAllOf("UserWidget")`
walks 7–10k objects.
