# Storage Mage

Bags, pickup routing, workbench access and a carry-weight slider for RuneScape: Dragonwilds (UE4SS Lua, UE 5.6).
A sibling of Frame Mage. Storage Mage owns the inventories (it runs on the server, and on clients) and draws its own
UI, such as the bag tabs, in the game's default look. Frame Mage is optional: when it's installed, its themes
restyle Storage Mage's UI too.

**Status:** scaffold. The mod loads and has one developer tool; bag logic is not built yet.
Design and the list of in-game tests: [docs/design.md](docs/design.md).

## Install (development)

```
powershell -ExecutionPolicy Bypass -File tools\deploy.ps1 -Link
```

`-Link` junctions `Mods\StorageMage\Scripts` to this repo, so edits load on the next game start. Without `-Link`
the scripts are copied (what players get). `config\`, `dumps\` and `saves\` in the game folder are never
overwritten. For a dedicated server, pass `-GameDir` with the server's folder.

## Install on a dedicated server (copied by hand)

```
powershell -ExecutionPolicy Bypass -File tools\deploy.ps1 -Package
```

This builds `dist\StorageMage.zip`. On the server, with UE4SS installed: stop the server, delete
`ue4ss\Mods\StorageMage\Scripts` and `Art` (so files removed from the mod don't linger), unzip into `ue4ss\Mods` and say
yes to replacing files, then start the server. The zip holds code and empty data folders only, so the server's
`config\` and `saves\` are kept. The zip is made by Windows PowerShell 5.1 and is meant for a Windows server.

## Keys

| Key | What |
|---|---|
| Numpad − (`keys.dumpInventory = "Subtract"`) | Developer: the player's inventories, pages, items and their tags → `Mods\StorageMage\dumps\inventory.txt`; every loaded item definition → `dumps\items.txt` |
| Numpad / (`keys.sortBags = "Divide"`) | Sort: everything on the Items page that belongs in a bag goes into it (the hotbar is never touched) |
| T (`keys.takeOut = "T"`) | With the inventory open: the bag item under the mouse goes to the Items page |
| Numpad + (`keys.hoverProbe = "Add"`) | Developer (feature `dragprobe`, off): the slot under the mouse → `dumps\drag.txt` |

Items that belong in a bag go into it when you pick them up, take them from a chest, or craft them
(`pickupRouting = true`). Only what you gained moves: an item you took out stays out until you sort.
Every move is logged in `dumps\moves.txt`. For now only the Tool Belt takes part.
## Bag pages

Storage Mage adds its seven bag pages (fixed layout: `storagemage/layout.lua`) to every player inventory by
patching the inventory's template at the main menu, so a save loads straight into them. For now the pages accept
nothing (no item carries their filter tags yet) and nothing shows them on screen. `dumps\pages.txt` reports the
patch and, each world, whether the live inventory has the pages. It refuses, and says why, if the Tool Belt or
RuneScape Bags mod is installed, or if the game's own pages aren't what it expects.

## Phase 2 test T1c (the template patch)

1. Quit the game. Back up `%LOCALAPPDATA%\RSDragonwilds\Saved\SaveGames` (copy the whole folder): this is the
   first build that changes the inventory's layout for every character.
2. Start the game and load your local world. Once you can move, open the inventory once and close it.
3. Wait 2 seconds, then quit. Send `dumps\pages.txt` and `dumps\t1.txt`.
4. If anything looks wrong (items missing, a crash), restore the backed-up folder with the game closed.

The T1 load timeline (`pagetest`, `dumps\t1.txt`) is off by default since T1 is done. The old T2/T3 and T6/T13
write tests were retired on 2026-11-11.

## Phase 2 test: tools survive a save and reload in the Tool Belt (T13 with real items)

The Tool Belt accepts tools (feature `tags`, report `dumps\tags.txt`); there's no tab yet, so the developer keys
move them in and out (`dumps\belt.txt`).
1. Quit the game. Back up `%LOCALAPPDATA%\RSDragonwilds\Saved\SaveGames`.
2. Start the game and load your local world. Wait about 10 seconds after you can move.
3. Press **Numpad /**: the tools on your Items page move into the Tool Belt (they disappear from view: there's
   no tab yet). `belt.txt` lists them and checks that your item count didn't change.
4. Quit to the main menu (that saves), load the world again, wait about 10 seconds.
5. `belt.txt`'s new "world loaded" entry should list the same tools on the Tool Belt. Press **Numpad *** to move
   them back to Items and check they're all there.
6. Quit. If anything is missing, restore the backup with the game closed.

**Passed 2026-11-13.**

## Phase 2: inventory screen dump (before the Tool Belt tab)

Feature `uidump` (developer, read only) writes `dumps\ui.txt` the first time the inventory screen is open: the
game's tab buttons, the tab group, the page switcher and the page bodies. Load a world, open the inventory
(Tab), wait 3 seconds, close it, and send `ui.txt`. **Done 2026-11-13.**

## Phase 2 test: the Tool Belt tab (first try)

Feature `belttab` adds a fifth tab, the Tool Belt (2 rows of 8), to the inventory screen. It only adds
widgets and never moves items, so no save backup is needed, but the game could crash while building it.
For now the tab shows the Items icon.
1. Put a tool or two in the Tool Belt with **Numpad /** first, so the page has something to show.
2. Open the inventory (Tab) and wait 3 seconds: the build runs while the screen is open.
3. Close and reopen it. Is there a fifth tab? Click it: does it show the Tool Belt with your tools? Do the
   other four tabs still work? Do Q / E (or whatever switches tabs) reach it?
4. Send `dumps\tab.txt` and `dumps\ui.txt`, and what you saw.
To turn it off: `features = { belttab = false }` in the game's `config\settings.lua`.
**Worked 2026-11-13** (with the Items icon). Now it has its own icon (`Art\default\T_SM_Tab_ToolBelt_*.png`,
made by `python -I tools\draw_tab_art.py`): open the inventory and check the fifth tab shows crossed tools over
a belt, dim when not selected and bright when selected. `tab.txt` reports where the art came from.

## Phase 2 probe: drag and drop (before moving items from the UI)

Feature `dragprobe` (developer, read only) lists the inventory screen's drag/drop/move functions
(`dumps\functions.txt`) and logs every call to them while you play (`dumps\drag.txt`). **Numpad +** logs
which slot is under the mouse.
1. Load your world. Put a tool in the Tool Belt (Numpad /). Open the inventory and wait 3 seconds.
2. Do each of these once, pausing a second between them:
   - open the Tool Belt tab and drag the tool to another Tool Belt slot;
   - drag the tool from the Tool Belt to the hotbar;
   - drag the tool out of the inventory window (to drop it), if the game allows it;
   - hover over an Items slot and press Numpad +; then over a Tool Belt slot and press Numpad +.
3. Close the inventory, quit, and send `functions.txt` and `drag.txt`, and say what happened on screen
   for each drag.

**Done 2026-11-13** (results in handoff.md).

## Phase 2 test: pickup routing, sorting and taking out (Tool Belt)

The developer keys Numpad / and Numpad * are gone; Numpad / is now the sort key.
1. Back up `%LOCALAPPDATA%\RSDragonwilds\Saved\SaveGames`. Load your local world; wait 10 seconds.
2. **Sort:** with some tools on the Items page (and some on the hotbar), press **Numpad /**. The Items-page
   tools go into the Tool Belt; the hotbar's stay. A message says how many moved.
3. **Take out:** open the inventory, Tool Belt tab, hover over a tool, press **T**. It goes to the Items
   page. Wait a few seconds: it must stay there (it wasn't picked up).
4. **Pickup:** drop a tool on the ground from the Items page (or the hotbar), then pick it up. Within a
   second it should move into the Tool Belt. Also try taking a tool from a chest.
5. **Torches** (if you have some): take a few out with T, then pick up one more torch: only the one you
   picked up goes into the Tool Belt.
6. **Full belt:** fill the Tool Belt's 16 slots, then sort or pick up another tool: it stays in Items and a
   message says the Tool Belt is full.
7. Quit and send `dumps\moves.txt`, plus what you saw. If anything is missing, restore the backup.

## Settings

`Mods\StorageMage\config\settings.lua` holds only what you change; `settings.defaults.lua` (rewritten every start)
lists every setting with its default.

## Tests

```
lua tests/run_tests.lua
```

Unit tests for the engine-independent code, plus a smoke test that loads `main.lua` against stubbed UE4SS globals.

## Layout

- `StorageMage/Scripts/main.lua`: entry point; loads `storagemage/features/*`.
- `StorageMage/Scripts/storagemage/core/`: log, sched, events, config, fs, serialize, keys (copied from Frame Mage,
  same behaviour) and objects (UObject helpers, net role).
- `tools/usmap_fields.py`: prints a class's fields or an enum's values from the game's `.usmap` type map.
