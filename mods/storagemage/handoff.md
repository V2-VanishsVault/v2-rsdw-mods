# Storage Mage: hand-off (2026-11-08, updated 2026-11-13)

Read this first, then `docs/design.md` (the design, with every feature mapped to game functions and a list of
in-game tests T1–T21) and `README.md` (install, keys, tests, and the steps for each in-game test).

## What this is

A UE4SS Lua mod (UE 5.6) for RuneScape: Dragonwilds, one of a family by the same user. All of them live in the
`v2-rsdw-mods` monorepo (`C:\Developer\v2-rsdw-mods`); its `CLAUDE.md` has the rules for sessions working side by
side, and its root `README.md` covers building (`tools/build.sh`) and releasing (a tag `storagemage-v<version>`).

- **Storage Mage** (this folder, `mods/storagemage`): owns the bags, pickup routing, workbench access, saving and
  safe removal, and the carry-weight slider. It runs on the server (which owns inventories) and on clients.
- **Frame Mage** (`mods/framemage`): UI restyling with 5 themes (`elven`, formerly Demi-human and the fallback;
  `warrior`, `ranger`, `wizard`, `dwarven`). **Don't change Frame Mage, or `shared/settingspanel/`, from a
  Storage Mage session.** Its own session owns them.
- Map Mage, Spell Mage: later.

### What the bags are

Feature spec and the user's decisions: Frame Mage's `docs/bags-plan.md`. The bags are Tool Belt 16 (always
present; its top row is the Primary hotbar's page 2), Herbs 48, Gems 24, Ores 72, Seeds 64, Fishing 16, Rune
Essence 8. Crafted bags appear when carried.

- **Getting items in:** pickups go to the matching bag, or stay in the main inventory if the bag is full or
  missing. A sort key puts everything on the Items page away. **No manual moving into bags** (user, 2026-11-13);
  the hotbar is never sorted.
- **Getting items out:** a take-out key on the hovered bag slot (the game's drag and drop can't be reached from
  Lua). An item taken out is never routed straight back (see "Moving items" below).
- Workbenches see bag contents. The carry-weight slider runs 0–100%, default 50%.
- **Never lose items:** when bags are emptied (the mod is removed, a bag is lost), items go to the main inventory,
  then chests placed on the ground around the character, then loose items. Never deleted. This needs an "Empty
  bags (before uninstalling)" action in the shared Settings panel, plus game-kept storage if the API allows it.

### The UI, and Frame Mage

- **UI decision (2026-11-09):** Storage Mage adds every UI element it needs that the game lacks (bag tabs,
  messages, the Empty bags confirmation). Frame Mage only *styles* them through its themes. Without Frame Mage,
  Storage Mage ships its own art matching the default game look.
- Design: design.md "UI and styling". Build from game widgets and textures first, so Frame Mage's texture
  replacement themes them for free. New art goes in `StorageMage/Art/default/`, themed copies in
  `FrameMage/Art/themes/<theme>/storagemage/`. The active theme comes from the `FrameMage.theme` shared variable.
- **Themes switch at any time and hot-reload:** Storage Mage restyles its on-screen UI live when
  `FrameMage.themeRev` changes.
- `docs/frame-mage-handoff.md` is the stand-alone version for the Frame Mage session: keep it current when the
  contract, the Tool Belt's location or the art list changes. Frame Mage's answer is `docs/frame-mage-reply.md`:
  - F1, F2, F5: done.
  - F3 (themed copies of our tab art): our art list is in frame-mage-handoff.md section 2.
  - F4 (Plan A, Tool Belt at SlotType 9): received.
  - Its rules for us: brushes only through setters, tabs as `WBP_InventoryTabButton_C`, our widgets `SM_...`,
    leave `FM_...` alone.
- **Frame Mage no longer themes the inventory tabs** (user, 2026-11-13), so our tabs need nothing from it.
- The Tool Belt's top row as the Primary hotbar's page 2 **stays a Frame Mage feature** (user, 2026-11-09);
  without Frame Mage the Tool Belt is just a bag.

## Where things stand (2026-11-13)

- **Bag pages work** (Plan A): the inventory template is patched at the main menu with seven pages, slot types
  9–15, 424 slots. A save loads straight into them with nothing lost (T1c passed).
- **The Tool Belt works:** tools are tagged so it accepts them; they survive a save and reload; its tab shows
  in the inventory screen with our own icon ("Looks perfect!", user). Icons for all seven bags are drawn.
- **Pickup routing, the sort key and the take-out key are built, not yet run in game.** README "Phase 2 test:
  pickup routing, sorting and taking out" has the steps. For now only the Tool Belt takes part.
- **Tests:** `lua tests/run_tests.lua` from this folder: 272 pass (2026-11-14), including a smoke test that loads
  `main.lua` against stubbed UE4SS globals as a release install (no `dev/`). Run them after every change. CI runs them for every push that changes this mod.
- **Deployed locally with `-Link`:** the game's `Mods\StorageMage\Scripts` and `Art` are junctions to this
  folder's `StorageMage\Scripts` and `StorageMage\Art` (checked 2026-11-13), so edits load on the next game start.
  Run it once more after 2026-11-14 to link `dev\` too (`Mods\StorageMage\dev`).
- **Git:** part of the monorepo. Nothing of Storage Mage's work since the move is committed separately; commit only
  when the user asks, and only this mod's paths (`git add mods/storagemage listings/storagemage`).

### Code layout

- `StorageMage/Scripts/main.lua` loads `storagemage/features/*`:
  - `pages` (the template patch, `dumps/pages.txt`), `tags` (the Tool Belt's filter tag on tool definitions),
    `belttab` (the Tool Belt tab), `bagmoves` (routing, sorting, taking out; `dumps/moves.txt`).
- Developer tools are in `dev/` (2026-11-14), never in releases: `probe` (Numpad − dump), and, off by default,
  `pagetest` (T1 timeline), `uidump`, `dragprobe`, under `dev/storagemage/features/`, listed in `dev/features.lua`.
  `main.lua` starts them only when the folder is there. Shipping code never `require`s them: the inventory screen
  lookup is `storagemage/inventoryui.lua` and the item classes `storagemage/items.lua` (they used to live in `uidump`
  and `probe`, which is how switching `uidump` off broke the Tool Belt tab on 2026-11-13).
- `storagemage/`: `layout.lua` (the fixed page layout and slot maths), `filters.lua` (bag matching), `routing.lua`
  (the pure move planner), `art.lua` (tab art: theme copy, then Elven, then default), `defaults.lua` (settings and
  bag specs).
- `storagemage/core/`: log, sched, events, config, fs, serialize and keys (copied from Frame Mage, renamed),
  objects (UObject helpers and `netRole()`), toast (an on-screen message).
- `tools/deploy.ps1`: `-Link`, copy, `-ModsDir <path>`, `-Package` (builds `dist\StorageMage.zip` for the
  dedicated server). Release zips come from the monorepo's `tools/build.sh`.
- `tools/usmap_fields.py` prints class fields and enums from the type map; `tools/draw_tab_art.py` draws the tab
  icons (`tools/preview_tab_art.py` previews them).

## Next steps

1. ~~Run the pickup routing, sort and take-out test~~: passed, steps 2–6 (2026-11-13 and 11-14; README).
2. The user decides how items get out of bags beyond the take-out key (chests, dropping, trading; tools without
   Frame Mage's hotbar page 2).
3. The other six bags: tags and tabs like the Tool Belt's, then crafted bags appearing when carried (recipes not
   decided; Phase 4).
4. Workbench access, then the carry-weight slider (design.md, Phases).
5. **Settings:** built (2026-11-14): Storage Mage's tab in the shared Settings panel (`storagemage/panelclient.lua`:
   pickup routing, the two keys). Add the carry-weight slider and "Empty bags" there when they exist. Not yet
   checked in game.
6. **Dedicated server milestone:** UE4SS isn't on the server yet.

### Open for Frame Mage

- `Create` can't name widgets, so our tab and body can't be called `SM_…`. Frame Mage needs another way to tell
  them apart (for example a shared variable).

## The user's setup

- They play on their **own dedicated server on another machine**, which they update **by copying files by
  hand** (no network share). Use `tools\deploy.ps1 -Package`, then the README's server steps. UE4SS isn't on the
  server yet, and nothing has been installed there.
- **Develop and test in the user's local world** (server and client in one process), and test on the dedicated
  server at milestones.
- Give PowerShell commands with **full paths**: the user runs them from other folders (a relative
  `tools\deploy.ps1` failed for them).
- The user's Windows uses Ctrl+F11 for full screen. Frame Mage's API dump is **Numpad +**; Storage Mage's
  inventory dump is **Numpad −** (`keys.dumpInventory = "Subtract"`). Storage Mage's hover probe also uses
  Numpad +, but only while the `dragprobe` feature is on (off by default).
- **Rule (user, 2026-11-11): never use or require RuneSchema.** Bag items and unlocks must work without it
  (options in design.md 2.3).

## Key facts found (details in design.md, sections 1 and 4)

- The player's inventories are on `DominionPlayerController`: `InventoryComponent` (`BP_Components_Inventory_C`, a
  paged inventory), `LoadoutComponent`, `PersonalInventoryComponent` (personal chest) and `InventoryController`
  (the item-move and crafting RPCs).
- The main inventory has `InventoryPages` = {SlotType, NumSlots, AllowedItemFilter}: Items 32, Runes 32, Ammo 32,
  Quest 72, after 8 hotbar slots (`MaxSlotCount` 176). **Plan A** (chosen) makes each bag one more page.
- Per-tag weight multipliers already exist and are used by perks (`AddItemWeightMultiplier`): the slider will
  use them.
- Items carry only a `Category` tag, and categories are too coarse (herbs and rune essence share one; ores and
  gems share one), so bag filters = categories + specific item asset names. A category covers its child tags.
- UE4SS rules (learned in Frame Mage): no `RegisterKeyBind` (it crashes; keys are polled from the controller);
  never keep UObject handles across ticks (stale handles crash); structs with no script-visible fields
  (FGeometry, FPointerEvent) are empty in Lua; everything runs on the game thread inside pcall.
- **Lesson: no per-frame inventory reads or broad hooks in shipping code;** poll slowly and hook narrowly (see
  "Watch item" below).

## Data sources

- API dump (functions): `...\ue4ss\Mods\FrameMage\dumps\api.txt` (from Frame Mage's Numpad +).
- Type map (fields): `...\ue4ss\RSDragonwilds-5.6.1-254097+++dominion+hotfix-f6d5f942.usmap`; read it with
  `python -I tools/usmap_fields.py "<usmap>" ClassName "~substring"`.
- Inventory dumps: `...\ue4ss\Mods\StorageMage\dumps\inventory.txt` and `items.txt` (every loaded item
  definition by category; 1,545 on 2026-11-08).
- UE4SS log: `...\ue4ss\UE4SS.log`, lines tagged `[StorageMage]`.

## History (decisions and test results, oldest first)

### Bag contents (2026-11-08)

- The local-world dump says "host" (T19 settled for host and client; "dedicated" waits for UE4SS on the server).
- Fishing rods and nets go to the Tool Belt (the Fishing bag holds bait only); Coal counts as an ore.
- From items.txt the herb, gem and ore lists are filled in `defaults.lua`. The user decided the borderline items:
  Luminite → Ores; Shocking Plant Bulb, Poison Ichor → Herbs; Cursed Essence → Rune Essence; farming tools and
  torches → Tool Belt (raised to 16 slots), then "everything listed as a tool" (Anima Orb, Scarab Staff too), so
  the Tool Belt filter is the parent `Item.Equipment.Tool` + torches. **The bag item lists are complete.**

### Bag pages (2026-11-10 to 11-11)

- Feature `pagetest`: **T2 and T3 passed** (Plan A works while playing). **T1:** no tick between the inventory's
  creation and its save landing, so pages can't be added to the live inventory before load.
- **Prior art: Tool Belt 1.1.0 and RuneScape Bags 2.0.3 by Maxxfilth** (no licence, so learn, don't copy). They
  answer T1 (patch the inventory *template* at the main menu) and T13 (items in missing pages go to Items or the
  hotbar, or are deleted), and show how to make bag items (RuneSchema), filters (runtime tags), tabs, and
  dedicated-server moves. All in design.md "Prior art".
- **Layout (user):** slot types 9–15, past the game's enum (those mods reuse 7 = FishingBaits and 8 = None): Tool
  Belt 9/16 (slots 176–191), Herbs 10/48, Gems 11/24, Ores 12/72, Seeds 13/64, Fishing 14/16, Essence 15/8. Fixed
  in `storagemage/layout.lua`.
- **T1c passed (local world):** the save loaded into an inventory with all 11 pages and 424 slots, no items lost,
  the UI seeing the bag slots.
- **Watch item:** after T1c the first Tab press didn't open the inventory (new in that build, user). With the
  per-frame probe (`pagetest`) off and the pages on, the first Tab worked. Likely cause: the probe's per-frame
  inventory read, hooks on every inventory change and new-object watch. Not proven (that test also waited 10 s):
  if a first Tab ever misses again with the probe off, re-open this.

### Tool Belt (2026-11-11 to 11-13)

- Features `tags` (tool definitions get the Tool Belt tag before saves load; path cache
  `saves/bag-item-paths.txt`). **Passed in game (2026-11-13):** three steel tools went in, survived a save and
  reload on slots 176–178, and came back out with the item count unchanged.
- **The tab** (`belttab`): `dumps/ui.txt` showed 4 `WBP_InventoryTabButton_C` in `CategoryButtonGroup`
  (`WBP_DomRadioButtonGroup_C`, RadioValue 0–3), `InventorySwitcher` (a `CommonVisibilitySwitcher`), bodies
  `WBP_Inventory_InventoryBody_C`, slots `WBP_Inventory_ItemSlot_C`. Ours is made with
  `WidgetBlueprintLibrary:Create`, RadioValue 4, switcher child 4, group re-initialized. **Worked in game:** a
  fifth tab and page (2 rows of 8), the other tabs still work. Tab-cycling keys not tested.
- **The tab's icon:** tab icons are the `RadioCheckBox` style (`T_Icon_<Name>_Normal` / `_Highlight`, 62x32).
  Ours copies Runes' `CheckBoxStyleOverride`, swaps in our textures and assigns `WidgetStyle` (`SetWidgetStyle`
  isn't callable on this build; changing the style's `Padding` from Lua has no effect on screen). Our art is
  124x64, drawn with the tab's plate (soft falloff, no bottom border, brighter 2 px gold frame when selected) and
  each icon fitted by its own outline. Reworked over four in-game looks until the user said **"Looks perfect!"**.

### Moving items (2026-11-13)

- **Probe run** (`dragprobe`): the move API is `InventoryUIAPI:HandleInternalDragAndDrop`, `HandleDropItem`,
  `HandleInternalQuickTransfer`; `InventoryController:MoveItemBetweenInventories(Src, SrcSlot, Dst, DstSlot)`,
  `MoveItemBetweenInventoriesAnySlot`, `SplitAndPutStack`, `DropItemFromInventory` (with `Server_` RPCs);
  `InventoryComponent:MoveItem`, `AddItemToSlot`, `RemoveFromSlot`, `DropItem`. **None of the 40 hooks fired**
  during drags: the UI calls these natively, so Lua can't see or fix a drag. Hovering works (slot index within
  the page, and its type). Clicking a Tool Belt item starts the game's click-to-move, which then does nothing.
- **Rule (user): an item taken out must not be routed straight back.** Routing reacts only to a rise in the
  player's *total* count of a kind (pickups, chest withdrawals, crafting), never to an item appearing on the Items
  page. Only the gained amount is routed. The sort key is the explicit "put everything away" and does move
  taken-out items back (confirmed by the user).
- **Built:** `routing.lua` (pure planner: totals, rises, targets = stacks with room then empty slots; one move per
  step) and `bagmoves` (jobs of single steps: snapshot → plan → move → verify, one job at a time per player).
  Host: `InventoryComponent:MoveItem`; joined client: `InventoryController:MoveItemBetweenInventories` or
  `SplitAndPutStack`, 400 ms between steps. Pickup routing polls every 1 s on the host or dedicated server, scans
  only when `GetNumItems` changed. Keys: sort Numpad / (`sortBags`), take out T (`takeOut`).

### Settings panel (2026-11-13)

- **No Mod Menu** (user: not theirs to style or change, reached through the pause menu, disliked). All the user's
  mods share one Settings panel with a tab per mod; every mod ships a copy and the newest copy draws (Frame Mage
  not required). Our request: `docs/settings-panel-handoff.md`. Frame Mage's plan:
  `mods/framemage/docs/settings-panel-plan.md` (the source will be the monorepo's `shared/settingspanel/`).

### Deployment lost and restored (2026-11-11 to 11-13)

- A Vortex run (2026-11-11, 22:27–22:33) removed the game's `Mods\StorageMage` and `Mods\FrameMage` folders (with
  their dumps) and set both to `: 0` in mods.txt; the source was intact. It also left RuneSchema leftovers and
  brought back LazyStorageSolo, ModMenu, ConfigurableStacks and QuestLog. LazyStorageSolo's whole-inventory sort
  may move items in bag pages (T21).
- Redeployed 2026-11-13 (Frame Mage reinstalled by the user; RuneSchema off; LazyStorageSolo has no scripts left).
  Redeploy only with the user's OK.

## Shared notes

Other sessions in this family leave notes in
`C:\Users\chris\AppData\Roaming\Claude\side-session-notes\local_2e2bba35-1fab-468f-a5db-b4c039428d5a`
(on 2026-11-08 that folder did not exist on this machine). `storage-mage-handover.md` there is **out of date**
since the 2026-11-09 UI decision: Frame Mage no longer draws tabs or sends move requests.
