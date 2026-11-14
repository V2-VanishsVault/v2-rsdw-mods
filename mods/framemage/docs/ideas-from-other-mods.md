# Ideas from Relic Hunter UI and Rune UI

Surveyed 2026-11-13 (Relic Hunter UI 1.2.1, Rune UI 1.17.1). Both are UE4SS Lua UI mods for Dragonwilds.

- **Rune UI's licence** forbids putting any part of it, code or pictures, into another mod without the author's
  permission. Treat what follows as ideas only, and write them in Frame Mage's own way.
- **Relic Hunter UI** uses RuneSchema only for its bag data (stacks of 99, an old compass item). None of its UI code
  needs RuneSchema, and none of the ideas below do.
- **Out of scope:** map, bags, spells and action bars belong to the sister mods.

## Worth adding (Frame Mage's scope)

| Idea | Seen in | What it is | Size |
|---|---|---|---|
| HUD fade rules | both | Fade the HUD when idle or out of combat, and bring each part back for its own reason: health below max, a new chat message, a quest change, ammo or a tool swap, a survival need turning orange. Debuffs never fade. | M |
| Hide the whole HUD on a key | RHUI | One key toggles the whole HUD, for screenshots. | S |
| Combat text restyle | Rune UI | Damage numbers bigger, with outline and shadow; crits gold with a "pop"; status words recolored. Styling the shared text styles reaches every number at once. | M |
| Damage numbers and enemy bars on/off | both | Separate toggles, applied as opacity because the game drives their visibility. | S |
| Enemy and boss bar restyle | Rune UI | The theme's colors on enemy bars, set once on the shared template so every new bar has them. | M |
| Crosshair rules and theme color | Rune UI | Show the crosshair always, only when aiming or holding a tool, or never. The reticle and lock-on take the theme's color. | S–M |
| Notice restyle | Rune UI | Pick-ups, quests, banners and the upkeep warning in the theme's look. | L |
| Quest tracker restyle | Rune UI | No dark band; a heading-colored name and underline. | S |
| Readable letters | Rune UI | White text with a shadow on prompts and the Build and repair panels, keeping warning colors. | M |
| Death screen restyle | Rune UI | A larger, themed "You Died". | S–M |
| Themed mouse pointer | Rune UI | `SetHardwareCursor` with the theme's pointer art. | S |
| Menu hover sound | RHUI | Frame Mage's own buttons play the game's hover sound. | S |
| Party panel | Rune UI | Co-op friends' names and health bars. | M |
| Stamina and health numbers | Rune UI | Numbers on the vitals bars. Check what Frame Mage's bars show now. | S |
| Keyboard editing | Rune UI | Select elements with PgUp/PgDn, arrows to move with a step size, +/- to scale, , . for opacity. | M |
| First-run hint | Rune UI | The game's own tutorial tip says "Press F9 to edit your HUD" once. | S |
| Per-character layouts | RHUI | Layouts chosen by character as well as by name. | S–M |
| Your own colors | RHUI | Generate theme art in colors the player picks. | L |
| Settings icon | Our own | A gear icon on the HUD that can be moved like any other element in Frame Mage's editor. Clicking it opens the Settings panel. | M |

## Techniques to adopt

- **Esc guard (RHUI):** re-check the input mapping context every second and re-add it if the game dropped it. Close
  the pause menu if it opened anyway. A watchdog releases Esc if the mod stops ticking. Frame Mage's `inputblock`
  has the basic block but none of these three.
- **Garbage collection (Rune UI):** run small collection steps at the end of each tick, skipping when the tick was
  already slow, to avoid 20–40 ms hitches. Avoid creating tables in key handlers, which run on the UE4SS thread.
- **Unique widget names (Rune UI):** creating a widget with a live widget's name replaced it in place and crashed
  the game. Every name should be unique per run.
- **Textures kept alive (RHUI):** re-check cached textures every second and hold them in a hidden "vault" widget so
  garbage collection can't free them.
- **Only write on change (both):** compare before every `Set*`.

## Already done from this survey

The layout editor previews notices with the game's own entry, and gives an empty element's stand-in the size it
last showed at (`editor/preview.lua`, `editor/samples.lua`).
