# Storage Mage: hand-off (2026-11-08)

Read this first, then `docs/design.md` (the design, with every feature mapped to game functions and a list of
in-game tests T1–T21) and `README.md` (install, keys, tests).

## What this is
A UE4SS Lua mod (UE 5.6) for RuneScape: Dragonwilds, one of a family by the same user:
- **Frame Mage** (`C:\Developer\v2-rsdw-mods\mods\framemage`): UI restyling with 5 themes (`elven` — formerly
  Demi-human, the fallback — `warrior`, `ranger`, `wizard`, `dwarven`). **Don't change Frame Mage from a Storage Mage session.** Its own session owns it.
- **UI decision (2026-11-09):** Storage Mage adds every UI element it needs that the game lacks (bag tabs,
  drop-onto-tab, messages, Empty bags confirmation). Frame Mage only *styles* them through its themes. Without
  Frame Mage, Storage Mage ships its own art matching the default game look. Design: design.md "UI and styling"
  (build from game widgets/textures first, so Frame Mage's texture replacement themes them for free; new art in
  `StorageMage/Art/default/`, themed copies in `FrameMage/Art/themes/<theme>/storagemage/`; active theme from a
  `FrameMage.theme` shared variable). That section lists what the Frame Mage session needs to do; the stand-alone version for that session is
  `docs/frame-mage-handoff.md` (2026-11-10): keep it current when the contract, Tool Belt location or art list
  changes. **Frame Mage replied** (`docs/frame-mage-reply.md`): F1, F2, F5 done (not yet run in game); F3 waits
  for our art list (names + pixel sizes), F4 for our Plan A/B choice (Tool Belt slot type or component + first
  slot index). Its rules for us are in design.md "UI and styling": brushes only through setters, tabs as
  `WBP_InventoryTabButton_C`, our widgets `SM_...`, leave `FM_...` alone.
  The Tool Belt's top row as the Primary hotbar's page 2 **stays a Frame Mage feature** (user, 2026-11-09);
  without Frame Mage the Tool Belt is just a bag.
  **Themes switch at any time and hot-reload**: Storage Mage must restyle its on-screen UI live when
  `FrameMage.themeRev` changes (design.md "UI and styling").
- **Storage Mage** (this folder): owns the bags, pickup routing, workbench access, saving and safe removal, and
  the carry-weight slider. It runs on the server (which owns inventories) and on clients.
- Map Mage, Spell Mage: later.

Feature spec and the user's decisions: Frame Mage's `docs/bags-plan.md`. The bags are Tool Belt 16 (always
present; its top row is the Primary hotbar's page 2; raised from 8 on 2026-11-08, and Frame Mage's
bags-plan.md still says 8: the user should tell the Frame Mage session), Herbs 48, Gems 24, Ores 72, Seeds 64, Fishing 16,
Rune Essence 8. Crafted bags appear when carried. Pickups go to the matching bag, or to the main inventory if
the bag is full or missing. Workbenches see bag contents. Drag an item onto a tab to move it: the same bag does
nothing, and a full bag refuses with a message. The carry-weight slider runs 0–100%, default 50%.
**Never lose items**: when bags are emptied (the mod is removed, a bag is lost), items go to the main inventory,
then chests placed on the ground around the character, then loose items. Never deleted. This needs an "Empty bags
(before uninstalling)" Mod Menu action, plus game-kept storage if the API allows it.

## Where things stand
- **Scaffold done, no bag logic yet.** It loads in game and has been seen working: the log shows
  "Storage Mage running", and the Numpad − dump writes a file and shows an on-screen message.
- **Deployed locally with `-Link`**: `...\RSDragonwilds\Binaries\Win64\ue4ss\Mods\StorageMage\Scripts` is a
  junction to this repo's `StorageMage\Scripts`, so edits load on the next game start.
- **Tests:** `lua tests/run_tests.lua` from this folder. 70 pass, including a smoke test that loads `main.lua`
  against stubbed UE4SS globals. Run them after every change.
- **Not a git repository, nothing committed.** Commit only if the user asks.
- Code layout: `StorageMage/Scripts/main.lua`, which loads `storagemage/features/*` (only `probe` so far).
  `storagemage/core/`: log, sched, events, config, fs, serialize and keys (copied from Frame Mage, renamed),
  objects (UObject helpers and `netRole()`), toast (an on-screen message). `defaults.lua` has the bag specs.
  `tools/deploy.ps1` handles `-Link`, copy, `-ModsDir <path>` and `-Package` (builds `dist\StorageMage.zip`).
  `tools/usmap_fields.py` prints class fields and enums from the type map.

## The user's setup
- They play on their **own dedicated server on another machine**, which they update **by copying files by
  hand** (no network share). Use `tools\deploy.ps1 -Package`, then the README's server steps. UE4SS isn't on the
  server yet, and nothing has been installed there.
- **Develop and test in the user's local world** (server and client in one process), and test on the dedicated
  server at milestones.
- Give PowerShell commands with **full paths**: the user runs them from other folders (a relative
  `tools\deploy.ps1` failed for them).
- The user's Windows uses Ctrl+F11 for full screen. Frame Mage's API dump is **Numpad +**; Storage Mage's
  inventory dump is **Numpad −** (`keys.dumpInventory = "Subtract"`).

## Key facts found (details in design.md, sections 1 and 4)
- The player's inventories are on `DominionPlayerController`: `InventoryComponent` (`BP_Components_Inventory_C`, a
  paged inventory), `LoadoutComponent`, `PersonalInventoryComponent` (personal chest) and `InventoryController`
  (the item-move and crafting RPCs).
- The main inventory has `InventoryPages` = {SlotType, NumSlots, AllowedItemFilter}: Items 32, Runes 32, Ammo 32,
  Quest 72, after 8 hotbar slots (`MaxSlotCount` 176). **Plan A** makes each bag one more page (slot types 9–15).
  **Plan B** gives each bag its own InventoryComponent. Plan A is preferred and needs tests T2/T3.
- Per-tag weight multipliers already exist and are used by perks (`AddItemWeightMultiplier`): the slider will
  use them.
- Items carry only a `Category` tag, and categories are too coarse (herbs and rune essence share one; ores and
  gems share one), so bag filters = categories + specific item asset names.
- Prior art: the installed mods **LazyStorageSolo** and **LinkedStorageStations** already hook or call many of
  the needed functions from Lua (see design.md, "Prior art"). Read them before guessing at an API.
- UE4SS rules (learned in Frame Mage): no `RegisterKeyBind` (it crashes; keys are polled from the controller);
  never keep UObject handles across ticks (stale handles crash); structs with no script-visible fields
  (FGeometry, FPointerEvent) are empty in Lua; everything runs on the game thread inside pcall.

## Data sources
- API dump (functions): `...\ue4ss\Mods\FrameMage\dumps\api.txt` (from Frame Mage's Numpad +).
- Type map (fields): `...\ue4ss\RSDragonwilds-5.6.1-254097+++dominion+hotfix-f6d5f942.usmap`; read it with
  `python -I tools/usmap_fields.py "<usmap>" ClassName "~substring"`.
- Inventory dumps: `...\ue4ss\Mods\StorageMage\dumps\inventory.txt`. The two so far were both taken on the
  dedicated server's **client** (net role "client", correct).
- UE4SS log: `...\ue4ss\UE4SS.log`, lines tagged `[StorageMage]`.

## Next steps
1. **Done 2026-11-08:** the local-world dump says "host" (T19 settled for host and client; "dedicated" waits for
   UE4SS on the server). It had too few bag items for the lists, so Numpad − now also writes
   `dumps/items.txt` (every loaded item definition by category; 76 tests pass). **Ask the user to restart the
   game, load the world and press Numpad − again**, then fill `defaults.lua` `bags.<id>.items` from items.txt.
   If items.txt is short (definitions not loaded), open a workbench first or fall back to the pak file list.
2. **Decided 2026-11-08:** fishing rods and nets go to the Tool Belt (the Fishing bag holds bait only), and Coal
   counts as an ore. Recorded in `defaults.lua` (bags now have `categories` + `items`; the herb, gem and ore
   item lists are TODO until items.txt arrives) and in design.md section 4.
   **items.txt arrived** (1,545 definitions): herb, gem and ore lists are filled in `defaults.lua`; 111 tests
   pass. The user then decided the borderline items: Luminite → Ores; Shocking Plant Bulb, Poison Ichor →
   Herbs; Cursed Essence → Rune Essence; farming tools and torches → Tool Belt, now 16 slots; then "everything listed as a tool" (Anima Orb,
   Scarab Staff too), so the Tool Belt filter is the parent `Item.Equipment.Tool` + torches. Bag matching must
   treat a category as covering its child tags. All in
   `defaults.lua`; 124 tests pass. **The bag item lists are complete.**
3. **Started 2026-11-10:** feature `pagetest` (T1 timeline to `dumps/t1.txt` automatically; Numpad * runs
   T2/T3 to `dumps/pagetest.txt`, host only, changes the inventory: README "Phase 2 tests" has the save backup
   steps). 132 tests pass. **Run 1 (2026-11-11): T2 and T3 passed** (Plan A works while playing); T1 needs a
   second run with the improved probe (catches new inventory components, polls every frame, appends
   pagetest.txt). Results in design.md section 4. **Run 2: T1 answered** — no tick between the inventory's
   creation and its save landing, so pages can't be added on the live inventory before load.
   **Prior art read (2026-11-11): Tool Belt 1.1.0 and RuneScape Bags 2.0.3 by Maxxfilth** (user's Downloads;
   no licence, so learn, don't copy). They answer T1 (patch the inventory *template* at the main menu) and T13
   (items in missing pages go to Items or the hotbar, or are deleted), and show how to make bag items (RuneSchema),
   filters (runtime tags), tabs, and dedicated-server moves (Tool Belt 1.1.0). All in design.md "Prior art".
   The Numpad / rune test was **not run** and isn't needed. **Layout decided (user, 2026-11-11): slot types 9–15, past the game's enum** (first matched those mods, then
   dropped because they reuse 7 = FishingBaits and 8 = None) — Tool Belt 9/16 (slots 176–191), Herbs 10/48,
   Gems 11/24, Ores 12/72, Seeds 13/64, Fishing 14/16, Essence 15/8, 424 slots; fixed in `storagemage/layout.lua`
   (slot counts removed from settings); 180 tests pass. Frame Mage's F4 answered in frame-mage-handoff.md. **T1c built (2026-11-11):** feature `pages` patches the
   inventory template with the layout (pages accept nothing yet); report `dumps/pages.txt`. The Numpad * and /
   probes are retired (`pagetest` now only writes the T1 timeline). README "Phase 2 test T1c" has the steps.
   **T1c PASSED (2026-11-11, local world, layout 9–15):** the save loaded into an inventory with all 11 pages
   and 424 slots, with no items lost and the UI seeing the bag slots (details in design.md section 4). Next in
   Phase 2: tag the tools (`ItemFilter.StorageMage.ToolBelt` on their ItemData at the main menu) so the Tool
   Belt accepts them, then the Tool Belt tab, then moving items in and out; and later the dedicated-server
   milestone test.
   **Watch item (T1c run, 2026-11-11):** the first Tab press after loading didn't open the inventory; the second
   did. The log shows no errors; the world-start burst of several mods (and Storage Mage's one 7 ms read-only check)
   was at 22:13:38, and the inventory window first appeared at 22:13:40.4. **The user says it's new** (never
   before this build). Step 1: the per-frame T1 probe (`pagetest`) is now off by default (180 tests pass).
   A/B test: (A) pages on, probe off — load, wait ~10 s, press Tab once; (B) only if A still misses: add
   `features = { pages = false }` to the game's `config/settings.lua` and repeat. Pages off is safe while no
   item is in a bag page (none can be yet). **Result A (2026-11-11): the first Tab opened the inventory** with
   the probe off and the pages on, so the bag pages are cleared. Likely cause: the probe (a per-frame inventory read,
   hooks on every inventory change, and a new-object watch on all InventoryComponents). Not proven, because test A also
   waited 10 s: if a first Tab ever misses again with the probe off, re-open this. **Lesson: no per-frame
   inventory reads or broad hooks in shipping code**; poll slowly and hook narrowly.
   **Tool Belt step 1 built (2026-11-11):** `filters.lua`, features `tags` (tool definitions get the Tool Belt
   tag before saves load; path cache `saves/bag-item-paths.txt`) and `beltdev` (Numpad / in, Numpad * out, host
   only; `dumps/belt.txt`). 208 tests pass. **PASSED in game (2026-11-13):** three steel tools went into the
   Tool Belt, survived a save and reload on slots 176–178, and came back out with the item count unchanged
   (design.md section 4). Redeployed 2026-11-13 (Frame Mage reinstalled by the user; RuneSchema off;
   LazyStorageSolo has no scripts left). Next: the Tool Belt tab. **Step 1 (2026-11-13):** feature `uidump`
   (read only) writes the live inventory screen's tab bar to `dumps/ui.txt` (fields from the usmap:
   `InventoryMainPanelContent` has `CategoryButtonGroup`, `InventorySwitcher`, `InventoryBodies`; tab buttons are
   `DomRadioButton` with `RadioValue`, `ButtonIcon`; bodies have `SlotType`, `RowCount`, `InventorySlots`).
   209 tests pass. **ui.txt received (2026-11-13):** 4 `WBP_InventoryTabButton_C` in `CategoryButtonGroup`
   (`WBP_DomRadioButtonGroup_C`, children and RadioButtons in order, RadioValue 0–3); `InventorySwitcher` is a
   `CommonVisibilitySwitcher`; bodies `WBP_Inventory_InventoryBody_C` (Items SlotType 1 RowCount 4, Quest 4/9),
   slots `WBP_Inventory_ItemSlot_C` with `InventoryPanel` = the main panel; body class default SlotType 1;
   `ButtonIcon`/`LabelImage` empty, so the tab icon is elsewhere (dump now records the check box style and
   button tree). **Step 2 built:** feature `belttab` (body + tab button via `WidgetBlueprintLibrary:Create`,
   RadioValue 4, switcher child 4, group re-initialized; icon copied from Items for now; `dumps/tab.txt`).
   216 tests pass. **WORKED in game (2026-11-13):** every step ok (`tab.txt`); fifth tab and page (SlotType 9,
   2 rows, 16 slots) appear, clicking it shows the Tool Belt, the other tabs still work. Its icon is the Items
   backpack: tab icons are the `RadioCheckBox` style (`T_Icon_<Name>_Normal` / `_Highlight`, 62x32); Items uses
   the check box's own style (`bOverrideCheckBoxStyle=false`), the other three set `CheckBoxStyleOverride`, so
   ours needs its own override. Frame Mage adds an `FM_TabRim_<n>` Image to each game tab, not (yet) to ours.
   Tab-cycling keys not tested (user doesn't know them). **Step 3 (2026-11-13): own icon** (user chose our own
   art over a game icon): `StorageMage/Art/default/T_SM_Tab_ToolBelt_Normal/_Highlight.png` (124x64, drawn by
   `tools/draw_tab_art.py`), `storagemage/art.lua` (theme copy → Elven → default; `ImportFileAsTexture2D`;
   reads `FrameMage.theme`/`themeRev`), belttab copies Runes' `CheckBoxStyleOverride`, swaps in our textures
   and pushes it to the check box (`SetWidgetStyle`, else `WidgetStyle`); re-applies on a themeRev change.
   deploy.ps1 now links/copies `Art\` too. Art list sent to Frame Mage in frame-mage-handoff.md section 2.
   225 tests pass; not run in game. **Frame Mage no longer themes the inventory tabs** (user, 2026-11-13).
   **Icons for every bag drawn (2026-11-13):** `T_SM_Tab_<Bag>_Normal/_Highlight` for Herbs, Gems, Ores, Seeds,
   Fishing, RuneEssence too (`tools/draw_tab_art.py`, preview `tools/preview_tab_art.py`); user approved, with
   Rune Essence redrawn in the game item's shape (wiki picture). **In game (2026-11-13): our Tool Belt icon
   showed**, so the art loading and the style override work; but the game's tab textures include the tab's
   plate (the background), so ours looked bare. Redrawn with plates and the game's icon colours, sampled
   from the user's screenshot. Second in-game look: plate too big and icons too high and large; plate now
   94x60 of 124x64 touching the bottom, icons scaled 0.8 and moved down (`PLATE_*`, `ICON_*` in the script),
   measured against the user's screenshot. **Third look:** size right, the underline moves to our tab when
   selected (game handles it), but the plate sits 1-2 screen px above the game's; belttab now moves the image
   down through the check box style's `Padding`. **Fourth look:** the padding was set but had no effect on
   screen (the check box doesn't re-lay itself out when its style is replaced from Lua), so it's removed. `SetWidgetStyle` isn't
   callable on this build; assigning `WidgetStyle` works. Measured again: the plate edges matched the game's;
   it was the Tool Belt icon that sat ~3 screen px high (its drawing's centre is higher than the others').
   Now `draw_tab_art.py` fits every icon by its own outline (`ICON_MAX_H` 35, `ICON_MAX_W` 44,
   `ICON_CENTRE_Y` 36 of 64), which puts all seven icons' centres where the game's are. **User's close-up:**
   the game's plates fade out at their edges (soft dark falloff, frame line inset ~2 px, inside darker
   towards the frame); ours had a hard edge with the frame on the outermost pixel. Plate now drawn per pixel
   with `FALLOFF` 3.5 and `INNER_SHADE` 7; normal plate lightened; `ICON_MAX_W` 40. The game's plates also
   have **no bottom border** (they run into the tab row's line, user), so ours now fade and frame on the
   sides and top only; the selected plate's gold frame is brighter and 2 px. **User: "Looks perfect!"
   (2026-11-13).** The Tool Belt tab is done visually. Next (Phase 2): moving items in and out of the Tool
   Belt from the UI (drag out of a bag page, a key or drop to move in), then dedicated-server moves through
   InventoryController. **Started 2026-11-13:** from the usmap, slot widgets (`InventorySlotBase`) have
   `bIsMousedOver` and `SlotPayload` (`InventorySlotDragPayload`: `InventoryIndex`, `OwningInventoryType`,
   `SourceInventory`; split payload adds `Amount`); `InventoryUIAPI` holds `DragAndDropAPI`,
   `InventoryController`, `QuickActionSlots`, `InventorySlots`. Feature `dragprobe` (read only) dumps their
   functions to `dumps/functions.txt`, hooks the drag/drop/move/split/swap ones (not Get/Is/Can/Should/Has
   or Mouse; 20 logged calls each) to `dumps/drag.txt`, and Numpad + logs the hovered slot. 233 tests pass;
   waiting for the user's run (README "Phase 2 probe: drag and drop").
   **Decided (user, 2026-11-13): no manual moving into bags.** Items go in automatically: pickup routing (an
   item that lands in Items moves to its bag; stays in Items if the bag is full) plus a "sort into bags"
   hotkey for everything on the Items page. **The hotbar is never sorted.** On a dedicated server the server
   routes pickups itself; the hotkey asks the server through the UI's own move calls. Still needed: a way
   out of bags (chests, dropping, trading; tools without Frame Mage's hotbar page 2): a "take out" key on
   the hovered slot and/or fixing drag-out; the user decides after the probe run.
   **Probe run (2026-11-13):** `functions.txt` has the move API: `InventoryUIAPI` `HandleInternalDragAndDrop
   (FromSlotNum, FromSlotType, ToSlotNum, ToSlotType)`, `HandleDropItem`, `HandleInternalQuickTransfer`, split
   variants; `InventoryController` `MoveItemBetweenInventories(Src, SrcSlot, Dst, DstSlot)`,
   `MoveItemBetweenInventoriesAnySlot`, `SplitAndPutStack`, `DropItemFromInventory`, with `Server_` RPCs;
   `InventoryComponent` `MoveItem`, `AddItemToSlot`, `RemoveFromSlot`, `DropItem`. **None of the 40 hooks
   fired** during the drags: the UI calls these natively (not through ProcessEvent), so Lua hooks can't see
   or fix the drag. **Hover works:** Numpad + read `index=3 type=1` (shield, Items) and `index=2 type=9`
   (spade, Tool Belt); the index is within the page. **Clicking a Tool Belt item** starts the game's
   click-to-move, jumps to the first tab, and the click on a target does nothing (the item stays in the
   Tool Belt). So a native drag-out isn't reachable; recommended way out: a "take out" key on the hovered
   slot. Dim tab: its frame line was invisible in game; now olive, 2 px, on a darker inside.
   **Rule (user, 2026-11-13): an item taken out must not be routed straight back.** Design: pickup routing
   reacts only to a rise in the player's *total* count of a kind (pickups, chest withdrawals, crafting
   results), never to an item merely appearing on the Items page. A take-out (or any move within the
   inventory) leaves the total unchanged, so routing ignores it. Only the newly gained amount is routed
   (split off the Items stack if it merged with items taken out earlier). The sort hotkey is the explicit
   "put everything away" and does move taken-out items back (**confirmed by the user**).
   **Built 2026-11-13:** `storagemage/routing.lua` (pure planner: totals, rises, target = stacks with room
   then empty slots, `sortStep`, `routeStep`, `takeOutStep`; one move per call) and feature `bagmoves`:
   jobs of single steps (snapshot → plan → move → verify on the next snapshot), one job at a time per
   player. Host: `InventoryComponent:MoveItem`; joined client: `InventoryController:MoveItemBetweenInventories`
   (whole stack to an empty slot) or `SplitAndPutStack`, 400 ms between steps. Pickup routing polls every
   1 s on the host / dedicated server for every player controller, scans only when `GetNumItems` changed,
   and routes only rises in a bag item's total. Keys: sort Numpad / (`sortBags`), take out T (`takeOut`;
   no `when` gate, it looks for the screen only when pressed). `layout.lua` gained `itemsRange`,
   `absoluteSlot`, `bagOfSlotType`. `beltdev` removed; `uidump` and `dragprobe` off by default.
   263 tests pass; not run in game (README "Phase 2 test: pickup routing, sorting and taking out").
   Unknown until run: whether `MoveItem` onto a same-kind stack merges (each move is verified; a mismatch
   stops the job and is logged).
   **Settings panel (user, 2026-11-13): no Mod Menu** (not the user's to style or change, reached through
   the pause menu, disliked). All the user's mods share Frame Mage's settings panel with a tab per mod;
   every mod ships a copy and the newest copy draws it (Frame Mage not required). Handoff to the Frame Mage
   session: `docs/settings-panel-handoff.md` (election, shared-variable data protocol, what Storage Mage's
   tab holds, open questions). design.md's Mod Menu mentions now point to the panel. Storage Mage
   publishes its schema once Frame Mage settles the protocol; until then `config\settings.lua`. **Open for Frame Mage:** `Create` can't name widgets, so the tab and body
   can't be called `SM_…`; we need another way for Frame Mage to tell them apart (e.g. a shared variable).
   **Deployment lost (found 2026-11-11 ~22:35):** a Vortex run (22:27–22:33) removed the game's
   `Mods\StorageMage` and `Mods\FrameMage` folders (with their dumps) and set both to `: 0` in mods.txt. Both repos
   are intact (they were only linked). It also left RuneSchema (`RuneSchema : 1`, an empty folder) and brought back
   **LazyStorageSolo with its scripts** (its whole-inventory sort may move items in bag pages: T21), plus ModMenu,
   ConfigurableStacks and QuestLog. Redeploy with `tools\deploy.ps1 -Link` only with the user's OK. **Rule (user, 2026-11-11): never use or require
   RuneSchema**; bag items/unlocks must work without it (options in design.md 2.3). On 2026-11-11 only
   leftovers of RuneSchema remained (an empty `Mods\RuneSchema\mods` folder, `RuneSchema : 1` in mods.txt, a
   Vortex load-order entry); no RuneSchema items were in the user's save or character files. Next: the template-patch test (T1c), and the user's
   choice on matching their page layout. LazyStorageSolo's scripts are no longer installed (only its
   .ini files), so its hooks can't be read. Phase 2 (Tool Belt): run tests T1–T3 (when the save loads, a page with slot type 9, writing `InventoryPages`
   from Lua), then T6 and T13 (bag items after the mod is removed), and choose Plan A or Plan B.
4. Then pickup routing and workbench access, then crafted bags, then the weight slider (design.md, Phases).

## Shared notes
Other sessions in this family leave notes in
`C:\Users\chris\AppData\Roaming\Claude\side-session-notes\local_2e2bba35-1fab-468f-a5db-b4c039428d5a`
(on 2026-11-08 that folder, and `side-session-notes` itself, did not exist on this machine).
(`storage-mage-handover.md` there covers the shared-variable plan for Frame Mage: **out of date** since the
2026-11-09 UI decision; Frame Mage no longer draws tabs or sends move requests).
