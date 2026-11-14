# Theming other mods with Frame Mage

How a mod (Storage Mage, and the mods that follow) gets styled by Frame Mage's themes while still working on its
own. Frame Mage never needs to know the other mod's code: the mod follows the four rules below, and Frame Mage's
themes reach it.

**The principle:** a mod draws its own UI and ships its own default art (matching the game's look), so it works
without Frame Mage. When Frame Mage is installed, the same UI takes the active theme's look, and follows a theme
switch live: no restart, no reopening a window.

## 1. Know the theme: shared variables

Frame Mage publishes the active theme through UE4SS shared variables, at start-up and on every switch:

| Variable | Value |
|---|---|
| `FrameMage.theme` | The theme's canonical name: `elven`, `warrior`, `ranger`, `wizard` or `dwarven` |
| `FrameMage.themeRev` | A number that goes up by 1 on every switch |

Poll `FrameMage.themeRev` (a few times a second is plenty) and restyle when it changes. Missing (Frame Mage not
installed, or not started yet): use your default look. As a fallback only, the theme is also the `theme` line of
`FrameMage/config/settings.lua`.

(On this UE4SS build, check that `ModRef:GetSharedVariable` exists: Storage Mage's test T20. If Frame Mage can't
publish, it logs "could not publish the theme to other mods".)

## 2. Build from the game's own widgets and textures where possible

Frame Mage themes the game's textures by name: `Art/themes/<theme>/<TextureName>.png` replaces that texture
everywhere it's used. A widget built from the game's own pieces and textures (a tab made like
`WBP_InventoryTabButton_C`, using the game's tab brushes) is themed with no extra work.

**Set every brush through a setter** - `SetBrush`, `SetBrushFromTexture`, `SetBrushResourceObject`,
`SetBrushFromMaterial` (Image and Border). Frame Mage themes a brush when a setter is called, whenever that is: so
widgets made long after the theme was applied, or after a switch, are themed too. A brush written straight into a
widget's properties (`img.Brush = ...`) is never seen.

Frame Mage also recognizes some game widget classes and dresses them (the Build menu's category tabs get its button
border). Inventory tab buttons (`WBP_InventoryTabButton_C`) are left in the game's look, so tabs another mod adds to
that row need nothing from Frame Mage.

## 3. New art: a theme folder per mod

Where the game has nothing to reuse (a bag icon on a tab), the mod ships its own default art at
`<YourMod>/Art/default/<name>.png`. A theme may provide its own version at:

```
FrameMage/Art/themes/<theme>/<yourmod>/<name>.png
```

(lower-case mod folder name; same file name and pixel size as the default). Look up in this order:

1. the active theme: `FrameMage/Art/themes/<theme>/<yourmod>/<name>.png`
2. Elven: `FrameMage/Art/themes/elven/<yourmod>/<name>.png`
3. your own default: `<YourMod>/Art/default/<name>.png`

That's the rule Frame Mage uses for its own files, extended to yours. Publish your list of names and sizes (a
table in your docs) so Frame Mage can make each theme's set.

## 4. Colors and sizes: the theme's `theme.lua`

For text and panels your mod draws, read the active theme's `FrameMage/Art/themes/<theme>/theme.lua`, merged over
Elven's (`elven/theme.lua`), merged over the built-in values below - the same as Frame Mage's
`themes.style()`. Parse it as data; don't run it. Colors are linear RGB(A), 0..1.

| Key | Meaning | Built-in |
|---|---|---|
| `gold` | Highlights (a selected row; title bars without art) | 0.86, 0.66, 0.26 |
| `ink` | Text on title bars and buttons | 0.03, 0.02, 0.01 |
| `heading` | Section headings on panels | 0.95, 0.74, 0.32 |
| `label` | Ordinary text on panels | 0.90, 0.87, 0.80 |
| `dim` | Quiet text, separators | 0.62, 0.59, 0.53 |
| `selectedInk` | Text on a filled (selected) button | per theme |
| `panelColor` | Panel fill without panel art | 0.03, 0.03, 0.04, 0.88 |
| `panelPad` | A panel's content inset: left, top, right, bottom (units) | 16, 14, 16, 14 |

Each theme sets more (frame sizes, the tooltip band, the level-up celebration's colors under `celebrate`): see the
theme files; the keys are commented there.

## The themes

| Theme | Look | Accent |
|---|---|---|
| Elven | Antique silver in frilly openwork filigree | Glowing moonstone channel |
| Warrior | Polished steel, cut corners, rivets | Red inlay |
| Ranger | Planed oak, rounded corners, ivy | Green inlay |
| Wizard | Faceted black obsidian, a laser-etched rune in each corner | Glowing blue channel |
| Dwarven | Hammered bronze and iron knotwork, studs | Molten amber channel |

## Things to agree on per mod

Where a mod's UI meets Frame Mage's changes (a shared tab row, a window Frame Mage frames or moves, the mouse),
write it down in both mods' docs. For the inventory, see [bags-plan.md](bags-plan.md), "What Frame Mage does near
Storage Mage's UI".
