# Storage Mage: bags design

Status: design, not built. Feature spec and decisions: Frame Mage `docs/bags-plan.md`.
Sources: Frame Mage's API dump (`ue4ss/Mods/FrameMage/dumps/api.txt`, 2026-11-07 23:45: function names and
parameter types only) and the game's type map (`RSDragonwilds-5.6.1-254097+++dominion+hotfix-f6d5f942.usmap`: data
fields). Reproduce the field lists with `python -I tools/usmap_fields.py <usmap> InventoryComponent ...`.

How certain each line is:
- **[dump]**: the function or field exists, as named (from the dump or the type map). What it *does* is inferred
  from its name and parameters.
- **[guess]**: a reasonable inference that has not been seen working in game.
- **[test Tn]**: must be checked in game before building on it; the tests are listed at the end.

Where code runs: **S** = server (dedicated server, or the host in single-player / self-hosted, where server and
client are the same process), **C** = the owning client (UI), **S+C** = both. On a dedicated server Storage Mage
must be installed on the server *and* on each client that wants bag tabs (Frame Mage is optional: it only
restyles them); with it only on clients, bags are off and
the mod says so (see "Server presence").

---

## 1. What the game already gives us

### Where a player's items live
`DominionPlayerController` [dump] holds the player's inventory components, so they exist on the server and the
owning client (other clients don't see someone else's controller):

| Field on `DominionPlayerController` | Class | What it is |
|---|---|---|
| `InventoryComponent` | `PagedInventoryWithLogComponent` [guess: the dump's `InventoryUIAPI.PagedInventoryComponent` points at it] | The main inventory: Items, Runes, Ammunition, Quest Items tabs |
| `LoadoutComponent` | `LoadoutComponent : InventoryWithLogComponent` | Worn and held equipment |
| `PersonalInventoryComponent` | `PersonalInventoryComponent : InventoryWithLogComponent` | The personal chest (perk) |
| `InventoryController` | `InventoryController` | Server RPCs for every item move, craft, drop, split |

The character (`DominionPlayerCharacter`) holds `ItemMagnet`, `PlayerEncumbranceComponent` and the attributes
component, not the inventories.

### The main inventory is already "pages with filters"
`PagedInventoryWithLogComponent.InventoryPages : Array<InventoryPage>` [dump], and `InventoryPage` is
`{ SlotType: EInventorySlotType, NumSlots: Int, AllowedItemFilter: GameplayTagQuery }` [dump].
`EInventorySlotType` = QuickAction 0, InventoryItems 1, InventoryRunes 2, InventoryAmmunition 3,
InventoryQuestItems 4, Loadout 5, External 6, FishingBaits 7, None 8 [dump].
The UI asks for a tab's slots by type: `InventoryUIAPI:GetInventorySlots(SlotType)`, and
`PagedInventoryWithLogComponent:GetFreeSlotCountFromSlotType(SlotType)` [dump].

So the game's own Runes / Ammunition tabs **are** "an inventory section with a tag filter". This is the
cheapest route to bags (see 2.1).

### Inventory functions we'll use (all on `InventoryComponent`, [dump])
`AddItem`, `AddItemByData(ItemData, Count, DurabilityPercentage, GameplayTags)`, `AddItemByDataToSlot`,
`CanAddItem`, `CanAddItemByData`, `GetSpaceAvailableForItemByData`, `IsItemAllowed`, `GetItemFromSlot`,
`GetItemSlots`, `GetAllItems`, `GetNumEmptySlots`, `MoveItem(SlotIndex, TargetInventory, TargetSlotIndex,
Instigator, Amount)`, `MoveAllItems(TargetInventory)`, `RemoveFromSlot`, `DropItem(SlotIndex, Transform,
Instigator, DropSpeed, LaunchDirection, AmountOverride, bMagnetize)`, `DropItemByData`, `ComputeCurrentWeight`,
`AddItemWeightMultiplier(WeightReductionTag, Multiplier) -> handle`, `RemoveItemWeightMultiplier(handle)`.
Fields: `ItemSlots : Array<Item>`, `MaxSlotCount`, `NumberOfQuickActionSlots`, `AllowedItemFilterQuery`,
`ItemWeightModifier : Array<{HandleId, WeightReductionTag, Multiplier}>`, `JsonInventory : Str`,
`bHasLoadedFromSave`, `bAllowAdds`, `bAllowRemoves`.

Server RPCs on `InventoryController` [dump] (what the UI calls; the client sends, the server runs):
`Server_MoveItemBetweenInventories(Source, SourceSlot, Target, TargetSlot)`,
`MoveItemBetweenInventoriesAnySlot(Source, SourceSlot, Target)` (no `Server_` twin in the dump: [test T6]),
`Server_CraftRecipe(Station, Recipe, Count, BonusCount, XPMul, BonusXPMul, Inventories)`,
`Server_DropItemFromInventory`, `Server_SplitAndPutStack`.

Items: `Item { Count, Durability, GameplayTags, Guid, ItemDataPersistenceId: Str, ItemData, ... }` and
`ItemData { Category: GameplayTag, ItemFilterTags: GameplayTagContainer, Weight, WeightReductionTag,
MaxStackSize, ... }` with `GetCategory()`, `GetItemFilterTags()`, `GetRawWeight()`,
`GetRelativeWeight(InventoryClass)`, `GetWeightReductionTag()` [dump].

### Prior art in installed mods (evidence, not our own test)
Two installed mods already use these from Lua, which is good evidence they work on this build:
- **LazyStorageSolo** hooks (`RegisterHook`): `/Script/Dominion.DominionPlayerController:OnInventoryLoadedFromSave`
  (the moment the save lands in the inventory: T1), `/Script/Dominion.InventoryComponent:OnRep_ItemSlots`
  (client: slots arrived), `/Script/Dominion.LocalPlayerInventoryAudioManager:ProcessInventoryLogEvent` (every
  inventory log event, which it uses for pickups), the `InventoryController:Server_*` RPCs (MoveItemBetweenInventories,
  SplitAndPutStack, MoveAllItemsBetweenInventories, CraftRecipe, ...), `PlayerInteractionManager:Server_RequestInteraction`,
  and the Blueprint `BP_PlayerController_C:OnInventoryChanged_BrokenItemFTUE` (fires on inventory change).
  It calls `InventoryComponent:MoveItem` / `RemoveFromSlot` directly on the host.
- **LinkedStorageStations** moves items with `InventoryController:SplitAndPutStack(src, srcSlot, amount, dst, dstSlot)`,
  the UI's own call: run on a client it is forwarded to the server, and its author reports a standard dedicated
  server accepts it. It finds chests with `LinkedInventoryComponent:IsLinkable`.
- **Tool Belt 1.1.0 and RuneScape Bags 2.0.3** (author Maxxfilth; downloads in the user's Downloads folder; read
  2026-11-11, read only; **no licence stated, so learn from the approach, don't copy code**). They already
  do most of what Storage Mage plans, as extra pages of the main inventory (Plan A). The Bags mod works for a
  host or solo game only. Tool Belt 1.1.0 says it supports dedicated servers, with the mod on the server and
  every client. What they established (their own in-game probes, quoted in their code comments):
  - **Pages before the save loads: patch the inventory *template*.** At script load, `RegisterInitGameStatePostHook`
    and `RegisterLoadMapPostHook`, they append pages to the controller Blueprint's default sub-object
    `/Game/Gameplay/Character/Player/BP_PlayerController.BP_PlayerController_C:BP_Components_Inventory_GEN_VARIABLE`
    and raise its `MaxSlotCount` (`SetPropertyValue`). Every inventory spawned afterwards already has the pages,
    so the save loads straight into them. This works without a local player, so a dedicated server patches too.
    This replaces our T1 route (no tick exists between creation and load, as our T1 run 2 showed).
  - **Adding a page safely:** grow the array first with `p[n+1] = { NumSlots = 0 }`, then deep-copy the Runes page
    `p[n+1] = p[2]`, then set `SlotType`, `NumSlots` and the filter's `TagDictionary[1].TagName`. Copying in one
    step read freed memory and sometimes crashed at start (their 1.0.7 / 2.0.2 fixes). A page that can't be set up
    is reset to 0 slots, and every later page is turned off.
  - **Filters: one runtime tag per bag.** A gameplay tag such as `ItemFilter.RuneScapeBags.Gem` is appended at
    the main menu, before a save is read, to each matching `ItemData.ItemFilterTags.GameplayTags`. The page's query
    is the Runes copy with its one tag renamed. A second tag means editing `QueryTokenStream` bytes. Not tagging
    a kind before load made those items fall out of their tab (Bags 2.0.3 fix).
  - **On load, an item goes back to its saved slot only if that slot's page accepts it.** Otherwise the game
    moves it to the Items page or the hotbar, and **deletes it if both are full**. A save without the pages
    deletes what was in them. **This answers T13**, so our Numpad / rune test isn't needed. Rules that follow:
    pages are always added for every character, whether or not they own the bag, so the slot count never
    changes. Pages are only ever appended, never reordered or resized, so saved slot numbers never move.
  - **Bag items via RuneSchema** (**not for Storage Mage: the user won't have RuneSchema**, see 2.3): JSON clones an existing item
    (`ITEM_Resources_SteelLimbs`) with its own `PersistenceID`, name, icon, stack size and weight, plus a small pak.
    Recipes are added by JSON to `DT_CraftingStationsDataTable` row `CraftingTable` (and to the vendor table).
    Runtime path `/Game/RuneSchema/<mod>/Items/<InternalName>`. Without the add-on, newer RuneSchema deletes the
    items from characters; older versions won't load a character that held one.
  - **Unlock once:** carrying a bag once unlocks its tab for good. It's stored as a hidden marker recipe
    (`ProgressComponent:UnlockRecipes` / `IsRecipeUnlocked`, saved by the game) plus a fallback file.
  - **Tabs:** `WidgetBlueprintLibrary:Create(pc, WBP_Inventory_InventoryBody_C / WBP_InventoryTabButton_C, pc)`
    into the `WBP_Inventory_VerticalNavigation_C`'s `InventorySwitcher`, `InventoryBodies` and
    `CategoryButtonGroup`. Its `RadioButtons:Empty()` then `Initialize()` (Initialize appends). On the body, set
    `SlotType` and `RowCount`, then `InventorySlots:Empty()` then `InitializeContent()`.
    - **Crash guard:** `Create` builds slots for the class default's SlotType and crashes on pages over about 32
      slots, so they temporarily set the CDO `Default__WBP_Inventory_InventoryBody_C.SlotType` to a small page.
    - Copy each new slot's `InventoryPanel` from an Items slot, or empty slots show stale tooltips.
    - Set tab icons before adding the button. Collapse tabs until unlocked.
  - **Drag and drop:** dragging *out of* an extra page does nothing natively. They hook
    `InventoryUIAPI:HandleInternalDragAndDrop` and `HandleDragAndDropToExternal`, queue the request, and finish
    it with `MoveItem` on the next tick. They found **no way to drop between tabs** (one tab shows at a time), so
    moving *into* a bag uses a key (T) on a hovered slot. `IsHovered()` works on slot widgets.
    `GetCachedGeometry` reads 0x0 from Lua, and mouse clicks never reach Lua.
  - **Pickups:** a 1 s poll of `GetNumItemsByData` per kind. A rise while the inventory is closed counts as a
    pickup and is moved with `MoveItem` (existing stacks first). It has a per-kind cap, and the rest stays in
    Items with a message. Stations count bag pages natively (a jewelry recipe used opals from a bag page), and
    death gravestones keep the extra slots.
  - **Weight:** one `AddItemWeightMultiplier(tag, percent/100)` per weight tag, setting a runtime
    `WeightReductionTag` where the game left it None. They remove leftovers carrying their own tags once per
    world, so nothing is halved twice.
  - **Safety:** a per-character ledger file (keyed by the character GUID from `Saved\SaveCharacters\<name>.json`,
    with `SaveCount` to tell save points apart) and a one-time "Restore lost bag items". "Prepare to uninstall"
    empties the bags to Items, then the nearest chest, then calls `PersistenceSubsystem:SaveGame(false)` after
    checking its signature.
  - **Dedicated server (Tool Belt 1.1.0):** the server only patches the template and tags. A joined client moves
    items with `InventoryController:MoveItemBetweenInventories` and `SplitAndPutStack`, which the game forwards to
    the server, and confirms by watching the source slot. There's no handshake: both sides must patch the same
    layout. The Bags mod is host-only because every move is a direct component call gated by `HasAuthority`, and
    pickups only run for the local player.
  - **Their layout** (slot types and sizes, pages appended after the game's 4):
    7 Herbs 48, 8 Tool Belt 16, 9 Seeds 64, 10 Gems 24, 11 Fishing 16, 12 Essence 8, 13 Ores 72 (424 slots).
    Same bags and sizes as Storage Mage's, but 7 and 8 reuse the game's `FishingBaits` and `None`. Storage
    Mage deliberately does **not** match it (user, 2026-11-11, see 2.1). Both mods refuse to run if pages 5+
    differ from what they expect, so Storage Mage must not run alongside them and detects them.
- **Conflicts to watch:** both mods touch the same inventories. LazyStorageSolo's sort/fill could reorder bag
  pages in Plan A (its sort runs on the whole main inventory) [test T21]; LinkedStorageStations widens which
  chests stations use, which doesn't touch bags.

---

## 2. Feature by feature

### 2.1 A new inventory per bag, with a tag filter — **S+C**

**Plan A (preferred): extra pages in the player's main inventory.** For each bag the player has, the server adds an
`InventoryPage { SlotType = <bag's type>, NumSlots = <from layout.lua>, AllowedItemFilter = <bag's tag query> }`
to `InventoryComponent.InventoryPages`, and raises `MaxSlotCount` to match.
- Why it's the best fit: replication (`OnRep_ItemSlots`), saving (`JsonInventory`), weight (`ComputeCurrentWeight`),
  crafting (the main inventory is already passed to crafting) and drag-and-drop all already work for pages, so
  most features below come for free.
- Bag slot types and order (**user's decision, 2026-11-11: slot types 9–15, all past the game's last enum
  value** — `EInventorySlotType` ends at FishingBaits 7, None 8 — so the game can never treat a bag page as one
  of its own kinds). Earlier the same day the layout matched Tool Belt 1.1.0 + RuneScape Bags 2.0.3 (Herbs 7,
  Tool Belt 8, ...); that was dropped because it reuses 7 and 8. Players of those mods empty their bags with those
  mods' "Prepare to uninstall" before switching. Pages appended after the game's four, in this order, for every
  character whether or not they have the bag (Tool Belt first: everyone has it, and Frame Mage's hotbar page 2
  reads its top row):

  | Page | Bag | SlotType | Slots | Slot numbers |
  |---|---|---|---|---|
  | 5 | Tool Belt | 9 | 16 | 176–191 |
  | 6 | Herbs | 10 | 48 | 192–239 |
  | 7 | Gems | 11 | 24 | 240–263 |
  | 8 | Ores | 12 | 72 | 264–335 |
  | 9 | Seeds | 13 | 64 | 336–399 |
  | 10 | Fishing | 14 | 16 | 400–415 |
  | 11 | Rune Essence | 15 | 8 | 416–423 |

  `MaxSlotCount` 424. Fixed in `storagemage/layout.lua` (not a setting). Never resize or reorder: only append.
  Code finds pages by SlotType **and** size. T2 confirmed the game accepts a slot type past its enum (9) in a page.
- Timing: pages must be in place **before** the save is loaded into the component, or saved bag items won't
  have slots to land in. Hook points: `DominionPlayerController:OnInventoryLoadedFromSave` (pre-hook = before the
  save lands, if it runs that way; see prior art), `InventoryComponent:OnRep_HasLoadedFromSave` (client),
  `bHasLoadedFromSave` (server). [test T1]: when the save is applied, and whether adding pages after
  load (then reloading) is needed.
- Writing `InventoryPages` (an array of structs with a `GameplayTagQuery` inside) from Lua: [test T3]. Building a
  `GameplayTagQuery` from Lua is the riskiest part (it's a token stream, not plain fields). Workaround: copy an
  existing page's query (Runes page) as a template, or leave `AllowedItemFilter` empty and enforce the filter in
  Storage Mage (refuse moves of the wrong category, see 2.8).

**Plan B (fallback): one `InventoryComponent` per bag on the controller.** The server creates it with
`StaticConstructObject(InventoryComponent class, controller)` and registers it, with `MaxSlotCount = N`,
`AllowedItemFilterQuery = <query>`.
- Costs: replication to the owning client of a component made at runtime is not guaranteed on UE 5.6 (registered
  sub-object lists are C++ only) [test T4]; the game won't save it, so Storage Mage saves it (2.6); weight,
  crafting and pickups don't see it without extra work.

Tag filters per bag (by `ItemData.Category` / `ItemFilterTags`): the exact gameplay tags are not in the type map
(tags are data). [test T5]: Storage Mage's developer dump (Numpad −) lists every item's category and filter tags;
the bag→tag table is filled in from that and lives in `defaults.lua` (`bags.<name>.tags`).

### 2.2 Tool Belt always present — **S** (creates it), **C** (shows the tab)
Plan A: the Tool Belt page (16 slots since 2026-11-08) is added for every player, whether or not they carry anything.
Its top row is the Primary hotbar's page 2: that link is Frame Mage's (the hotbar reads the Tool Belt's slots;
hotbar paging is a Frame Mage feature, so without Frame Mage there is no page 2 and the Tool Belt is only a
bag). Confirmed by the user (2026-11-09): this stays a Frame Mage feature. Filter: tools (axe, pickaxe, fishing rod, ... by category tag) [test T5].

### 2.3 Crafted bags appear when carried — **S** decides, **C** shows
**User's rule (2026-11-11): Storage Mage must never use or require RuneSchema** (the user removes it whenever it
turns up). So the RuneScape Bags way of making bag items (RuneSchema JSON clones with their own persistence id
and a pak) is out. The bag item must come from what the game and Lua alone allow. Options, to choose in Phase 4:
- **No new item; a craft action unlocks the tab.** At a Crafting Table, Storage Mage takes the materials itself
  (`RemoveItemByData`, after checking the counts) and records the unlock on the server, in its own file keyed by
  the character's GUID. Nothing new goes into the save, so nothing breaks if the mod is removed. The tab
  shows once unlocked ("unlock once" fits this naturally).
- **An existing game item stands in for each bag** (one the player can get but rarely uses): it saves like any
  item, but it looks and is named like that item unless we rename it in the UI.
- **A runtime-made `ItemData`** (T7): no persistence id the save can find, so it would vanish or break loading.
  Avoid.
- A bag is an item. The cheapest item to "be" a bag is one the game already has but which does nothing in the
  inventory; making brand-new `ItemData` assets needs pak/asset work and is out of scope for Lua.
  [guess] Options, in order: (1) an existing unused/rare item renamed in the UI; (2) a new `ItemData` duplicated at
  runtime from an existing one (`StaticConstructObject` with a template) — it then has no persistence id the save
  can find, so it **must not** be the only record of the bag [test T7].
- Recipes: `RecipeData { ItemsConsumed, ItemsCreated, ... }` and `CraftingStationComponent.ValidRecipes`,
  `CraftingStationDataTableRow.LabeledRecipes` [dump]. Bag recipes (materials, station) are **not decided**:
  the user wants them based on a station/recipe dump in Phase 4 (a 2026-11-09 draft needs significant changes).
  Adding a recipe = appending a `RecipeData` (runtime-made)
  to a station's `ValidRecipes` on the server and client. [test T8]. Crafting is Phase 4; until then bags are
  granted from the settings panel (developer) for testing.
- "Carried" = the bag item is in the main inventory or loadout. The server checks on inventory change (2.4's
  hook) and adds/removes the bag's page. Removing a page that still holds items first runs **emptying** (2.6).

### 2.4 Pickup routing — **S**
Goal: an ore goes into the Ores bag; if the bag is full or not carried, into the main inventory.
- **Plan A gets this partly free** [test T9]: when a page has a filter, `AddItem` probably picks the first page
  that accepts the item. If bag pages come before the Items page in `InventoryPages`, ores land in the Ores page
  with no code. Check order rules with T9.
- **Otherwise, the sweep**: after the main inventory changes on the server, move newly added items whose tags
  match a carried bag: `InventoryComponent:MoveItem(slot, target, -1?, nil, count)` (Plan B) or a slot-to-slot
  move within the same component (Plan A). Trigger: `RegisterHook` on a function the game binds to
  `OnInventoryChanged`, which dynamic delegates call through ProcessEvent, so UE4SS sees it:
  `BP_PlayerController_C:OnInventoryChanged_BrokenItemFTUE` (LazyStorageSolo uses it),
  `LoadoutComponent:OnReceiveInventoryChanged(Inventory, Added, Removed, Changed)` or
  `LinkedInventorySubsystem:LinkedInventoryChanged(...)` [dump; test T10: which of these fire on the server for
  the player's main inventory]. Fallback: a 250 ms server poll of `GetNumItems` per player.
- Weak spot of the sweep: if the main inventory is **full**, the pickup is refused before we can move it. Fix:
  a pre-hook on the world item's pickup. Candidates: `PlayerInteractionManager:Server_RequestInteraction` (server;
  hooked by LazyStorageSolo, so it fires), `MagneticComponent_GrantItem` (the magnet's grant),
  `RuntimeSpawnedWorldItem.InteractionComponent`, `WorldItem.ItemData` [dump]; their functions are not in the dump
  yet [test T11: add `MagneticComponent`, `WorldItem` to the API dump patterns]. Plan A has no weak spot here.
- Native C++ calls between game classes do **not** go through ProcessEvent, so hooking
  `InventoryComponent:AddItem` itself is not expected to fire for pickups [guess, consistent with UE4SS].

### 2.5 Workbench access — **S** (Plan A: free; Plan B: S+C)
- The client's crafting UI gathers inventories with `CraftingFunctionLibrary:GetLinkedInventories(World,
  BuildingPieceLocation, InDefaultInventories, OutAvailableInventories)` and the cache
  `LinkedInventorySubsystem.LinkedInventoryCache.DefaultInventories` [dump], then sends them in
  `InventoryController:Server_CraftRecipe(..., Inventories)` [dump]. Checks use
  `CraftingFunctionLibrary:CanCraftRecipe / GetMaxAmountCraftableOfRecipe / HasRequiredConsumedItemsForRecipe
  (..., Inventories, ...)` [dump].
- **Plan A:** bag pages are inside the main inventory, which is already a default inventory → crafting sees bag
  contents with no code [test T12].
- **Plan B:** add each bag component to the inventories list. Two places, both [test T12]: on the client, append
  to `LinkedInventoryCache.DefaultInventories` (weak object array) and call
  `CraftingFunctionLibrary:ResetLinkedInventoryCache` if the cache is rebuilt; on the server, a pre-hook on
  `InventoryController:Server_CraftRecipe` that appends the player's bag components to `Inventories` (RPCs run
  through ProcessEvent, so the hook fires; writing to a TArray parameter from Lua is the open question).
  Processing stations (smelter, etc.: `ProcessingStationComponent`) take items by drag, which 2.8 covers.

### 2.6 Saving, and never losing items when the mod is removed — **S**
User's rule: bag contents go back to the main inventory; what doesn't fit is dropped in chests on the ground
around the character, or as loose items if no chest can be placed. Never deleted.

**Plan A saving:** the game saves the main inventory including bag pages (`JsonInventory`) [test T1].
**Removal without the mod running** is then the open risk: on load, the game rebuilds `InventoryPages` from its
defaults (no bag pages) and must decide what to do with items in slots past the last page. [test T13, the most
important test]: put items in a bag page, save, quit, remove the mod, load. Possible outcomes:
1. items still appear (overflow kept or folded into Items) → safe, nothing more needed;
2. items vanish from view but stay in the saved JSON → safe as long as reinstalling restores them; the
   "Empty bags" action is then strongly advised before removal (the settings panel says so);
3. items are deleted on load → Plan A needs the Empty-bags step **every** time the game saves, which isn't
   workable; switch storage to Plan B + "game-kept storage" below.

**Plan B saving:** Storage Mage writes each player's bag contents to
`StorageMage/saves/<world>/<character guid>.lua` on the server (on change, debounced, written via temp file like
Frame Mage's `fs.write`): per slot, `ItemDataPersistenceId`, `Count`, `Durability`, `GameplayTags`. Loading uses
`AddItemByDataToSlot(ItemData, slot, count, durability%, tags)`; mapping a persistence id back to an `ItemData`
asset is [test T14]. Character id: `DomCharacterGuid` (seen in `GravestoneData.OwningCharGuid`,
`WorldItem.GuidOfPlayerCharacterThatDroppedItem`) [dump]; how to read it for a controller is [test T14].
If the mod is removed, the file stays: reinstalling brings the bags back. Items are not in the game meanwhile,
which is why "Empty bags" exists.

**Game-kept storage (works even if the mod is deleted without warning)** [guess, test T15]: keep a **mirror** of
bag contents somewhere the game itself saves for that character, so a mod-less load still has them. Candidates,
best first:
1. Plan A outcome 1 above (nothing extra needed).
2. The personal chest: `DominionPlayerController.PersonalInventoryComponent` [dump] is saved by the game per
   player. Not usable as a mirror (items would exist twice); usable as the **landing place** in emptying, before
   ground chests.
3. A gravestone: `GravestoneSubsystem` / `Gravestone` / `GravestoneData { Location, OwningCharGuid, ... }` [dump] —
   the game's own saved, per-character item container left in the world. If the server can spawn one holding items
   (as on death), it is the best "chest on the ground" for emptying. [test T16].

**"Empty bags (before uninstalling)" — settings panel action, S (requested from C):**
for each bag page/component, for each item:
1. `MoveItem` into the main inventory (fills existing stacks first: `FillStacks`, then `MoveAllItems`);
2. what's left → the personal chest if the player has it (`PersonalInventoryComponent`, `CanAddItem`);
3. what's left → containers placed on the ground around the character: a gravestone if T16 works, otherwise a
   world chest actor with an inventory (`WorldChest { InventoryComponent, ... }` [dump]; spawning one that the game
   saves is [test T17]); as many as needed, placed in a ring around the player;
4. what's left → loose items: `InventoryComponent:DropItem(slot, transform, instigator, speed, dir, count,
   bMagnetize=false)` [dump] in a ring around the player. Loose world items can expire
   (`WorldItem.bCanExpire`) [dump]: the message tells the player to pick them up.
The same routine runs when a bag stops being carried with items still in it (2.3). It is idempotent: running it
twice does nothing the second time, and it logs every item it moves.

### 2.7 Carry-weight slider, 0–100 %, default 50 % — **S** (applies), **C** (option UI in the shared settings panel)
- The game already has per-tag weight multipliers: `InventoryComponent:AddItemWeightMultiplier(WeightReductionTag,
  Multiplier) -> ItemWeightModifierHandle` and `RemoveItemWeightMultiplier(handle)`, stored in
  `ItemWeightModifier` and replicated (`OnRep_ItemWeightModifier`) [dump]. Each `ItemData` has a
  `WeightReductionTag` [dump]. Perks such as the Lumber Backpack (`GE_Woodcutting_LumberBackpack_WeightReduction_C`)
  likely use exactly this.
- Plan: on the server, for each player's main inventory (and bag components in Plan B), add one multiplier =
  slider/100 per distinct `WeightReductionTag` found across items, and replace them when the slider changes.
  [test T18]: whether an empty tag matches every item (one call would do), and whether multipliers stack
  multiplicatively with perks (they should; we don't touch the perk's handle).
- Result is visible in `PlayerEncumbranceComponent.CurrentCarryWeight` and the weight bar
  (`WeightBarBase:UpdateInfo(CarryingWeight, WeightLimit)`) [dump].
- Fallback: scale `ItemData.Weight` on every loaded item asset on the server [guess; global, affects everyone,
  and must be re-applied for assets loaded later].
- Multiplayer: one server-wide value set by the host (server's settings file); a client's slider only applies in
  single-player / self-hosted. The settings panel shows it read-only on clients of a dedicated server.

### 2.8 Drag-to-tab moves — **C** (Storage Mage UI) → **S** (Storage Mage moves)
- Storage Mage draws the bag tabs (next to the game's `WBP_InventoryTabButton_C` tabs) and detects a drop onto
  one. See "UI and styling" for who draws and who styles. Dragged item: `InventorySlotDragPayload {
  InventoryIndex, OwningInventoryType, SourceInventory }` and `DragPayload.DraggedItem` [dump]. Pointer/geometry
  structs are empty in Lua, so the tab under the cursor comes from Storage Mage's own hit-testing (Frame Mage
  has working hit-testing code to copy, as the core modules were), not from `FPointerEvent`.
- Storage Mage (C) checks first, for instant feedback: same bag → do nothing; bag full
  (`GetFreeSlotCountFromSlotType` / `GetNumEmptySlots`) or item not allowed (`IsItemAllowed`) → refuse, with a
  message. Then it asks the server to move through the game's own request, so no custom networking is needed:
  `InventoryController:SplitAndPutStack(src, srcSlot, count, dst, dstSlot)` (the non-`Server_` call the UI
  uses; run on a client the game forwards it to the server, as LinkedStorageStations does), or
  `MoveItemBetweenInventories(src, srcSlot, dst, dstSlot)`.
  - Plan A (same component): `src = dst = main inventory`, `dstSlot` = first free slot of the bag page
    [test T6: same source and target allowed].
  - Plan B: `src = main`, `dst = bag component`.
  The server re-checks (the game's own validation, plus Storage Mage on the server if a hook is needed).

---

## 3. Cross-cutting

### Server presence
- Storage Mage detects whether it runs on the server (`KismetSystemLibrary:IsDedicatedServer`, or a server-side
  heartbeat in a replicated field) [test T19]. A client joined to a server without Storage Mage turns bags
  off, shows "Bags need Storage Mage on the server", and never changes inventory data.
- Never assume the client can create inventories, pages or items: all writes happen on the server; the client
  only reads and sends the game's own move RPCs.

### UI and styling (C) — user's decision, 2026-11-09
**Settings (user, 2026-11-13): no Mod Menu.** All the user's mods share Frame Mage's settings panel, with a tab per mod; every mod ships a copy of the panel and the newest copy draws it, so Frame Mage isn't required. It isn't reached through the pause menu. Design and protocol: `docs/settings-panel-handoff.md` (Frame Mage's work). Until it exists, settings live in `config\settings.lua`.

**Storage Mage adds every UI element it needs that the game doesn't have**: bag tabs, drop-onto-tab handling,
"bag full" messages, the Empty bags confirmation, and its tab in the shared settings panel. It works fully
**without Frame Mage**. **Frame Mage only styles** those elements with its 5 themes (`elven`, `warrior`,
`ranger`, `wizard`, `dwarven`; Elven was called Demi-human until 2026-11-11, and is the fallback theme). Without Frame Mage, Storage Mage's own artwork matches the game's default look.

How each element gets its look, in order of preference:
1. **Built from the game's own widgets and textures** (e.g. a bag tab made like `WBP_InventoryTabButton_C`, with
   the game's tab brushes). It matches the default game by construction. Frame Mage themes replace game textures
   by name everywhere (`Art/themes/<theme>/<TextureName>.png`), so these elements follow the theme with no
   extra work on either side [test T22: the replacement reaches widgets Storage Mage creates after Frame Mage
   applied the theme].
2. **New art only where the game has nothing to reuse** (e.g. one icon per bag on its tab). Storage Mage ships it
   in `StorageMage/Art/default/<name>.png`, drawn to match the game's default theme. Each file name is a stable
   contract. A Frame Mage theme may provide its own version at
   `FrameMage/Art/themes/<theme>/storagemage/<name>.png`. Storage Mage uses the theme's file when Frame Mage is
   installed and the file exists, then Elven's copy (`FrameMage/Art/themes/elven/storagemage/`), then its own default (Frame Mage's rule,
   extended: anything missing comes from Elven). Same file name and pixel size as the default. Making the themed versions is Frame Mage's work.
3. **Colours and sizes** for text and panels Storage Mage draws: read from the active theme's `theme.lua`
   (Frame Mage's keys `gold`, `ink`, `heading`, `label`, `dim`, `panelColor`, ...; data only, parsed as data,
   never run), falling back to Storage Mage's built-in defaults that match the game.

Finding the active theme: Frame Mage publishes it as a shared variable `FrameMage.theme` (theme name) +
`FrameMage.themeRev` (number, bumped on change), which Storage Mage polls and then reloads its art.
**The theme can be changed at any time and hot-reloads** (user, 2026-11-09), so Storage Mage must restyle its
UI that is already on screen, with no restart and no reopening of the inventory: on a rev change, drop cached
textures, styles and colours, then re-apply art and colours to every Storage Mage widget that exists (found
again by name each time, never through handles kept across ticks). Widgets created later use the new theme
from the start. Elements built from game textures (point 1) follow Frame Mage's own hot reload [test T22]. Fallback if
the variable isn't there: read the `theme` setting from Frame Mage's settings file. Frame Mage absent (no
`Mods/FrameMage` folder or not enabled) → the default art, no polling.

UE4SS shared variables (`ModRef:SetSharedVariable / GetSharedVariable`) hold plain values only, never UObjects.
Their API names on this UE4SS build are [test T20].

**Frame Mage's reply (`docs/frame-mage-reply.md`, 2026-11-10)** settles these rules for Storage Mage's UI code:
- **Set every brush through a setter** (`SetBrush`, `SetBrushFromTexture`, `SetBrushResourceObject`,
  `SetBrushFromMaterial`, on Image and Border). Frame Mage themes brushes when a setter is called and re-checks
  live brushes on a switch; a brush written straight into `Brush` is never themed.
- **Make bag tabs real `WBP_InventoryTabButton_C` widgets** where possible: Frame Mage adds its button border to
  those automatically, including ones added after the window opened (an Image in the button's overlay, the
  one holding `RadioCheckBox`).
- **Leave widgets named `FM_...` alone**, and name ours `SM_...`, so neither mod mistakes the other's. Hit-testing
  and widget searches must skip `FM_` widgets (e.g. the border inside our tab buttons).
- **Name our own textures uniquely** (`T_SM_...`) so Frame Mage's replace-by-texture-name never matches them by
  accident; our themed art comes only from the `storagemage/` folders. [check when the art exists]
- Frame Mage doesn't move or resize the inventory's tab row, its tabs, or the inventory window; its frame is
  drawn outside the window's edges. It moves station and chest windows 24 units right. In normal play it never
  consumes the mouse or a drop.
- Both F1 (shared variables) and F2 (theming late widgets) are written but **not yet run in game**: T20 and T22
  still decide them. If publishing fails, Frame Mage logs "could not publish the theme to other mods".

**Needs the Frame Mage session** (this session doesn't change Frame Mage; status from the reply: F1, F2, F5 done,
F3 and F4 wait for Storage Mage): publish `FrameMage.theme` and
`FrameMage.themeRev`; make `storagemage/*.png` for its themes once Storage Mage's art list exists; make sure its
texture replacement also reaches widgets created later (T22); update `bags-plan.md` (Storage Mage draws the
bag tabs; Tool Belt is 16 slots). The earlier plan, where Frame Mage drew the tabs and sent move requests to
Storage Mage through shared variables, is dropped.

### UE4SS rules carried over from Frame Mage
- No `RegisterKeyBind`: keys are polled on the game thread (`core/keys.lua`).
- Every callback runs on the game thread inside `pcall` (`core/sched.lua`).
- Never keep a UObject handle across ticks: look up the controller and its components each time, and check
  `IsValid` (stale handles crash).
- Structs with no script-visible fields (`FGeometry`, `FPointerEvent`) are empty in Lua.

---

## 4. Findings from the inventory dumps (2026-11-08)
- **Confirmed:** the main inventory is `BP_Components_Inventory_C` on `BP_PlayerController_C`, with 4 pages:
  Items 32, Runes 32, Ammunition 32, Quest Items 72. `MaxSlotCount = 176` = 8 hotbar slots + 168 page slots, and
  slot indexes run through the pages in order (Items 8-39, runes from 40, ammo from 72, quest from 104), so
  hotbar slots come first. A new page would add to the end.
- **Confirmed:** per-tag weight multipliers are live and already used by perks:
  `ItemFilter.WeightReduction.StoneBlock x0.5`, `.Stone x0.75`, `.Ore x0.75`, `.Fish x0.75`. The slider (2.7)
  adds its own handles next to these.
- `JsonInventory` is empty while playing: it is probably filled only when saving (T1 still open).
- Every item's `ItemFilterTags` came back empty; only `Category` is set. **Categories are too coarse for most
  bags**, so a bag's filter is a list of categories **plus** a list of specific items (by `ItemData` asset name,
  which the dump now prints; display names change with the language). From the second dump:

  | Bag | Category | Shared with (so list items instead) |
  |---|---|---|
  | Tool Belt | `Item.Equipment.Tool.Hatchet`, `.Pickaxe`, `.Shovel`, `.Fishing.Rod`, `.Fishing.Net` | — (category is enough) |
  | Seeds | `ItemFilter.Material.Seed` (Wheat Seeds, Oak Tree Seed, Redberry Seeds) | — (category is enough) |
  | Fishing | `Item.Equipment.Ammo.Bait.*` only | **decided:** rods and nets always go to the Tool Belt |
  | Herbs | `ItemFilter.Material.BasicMaterial` (Harralander, Kwuarm, Marrentill, Snapdragon, Toadflax) | Rune Essence, Vault Core → list the herbs |
  | Rune Essence | `ItemFilter.Material.BasicMaterial` | herbs, Vault Core → list `ITEM_Rune_Essence` |
  | Ores | `Item.BuildingResource` (Iron Ore, Blurite Ore, Coal) | gems → list the ores; **decided:** Coal counts as an ore |
  | Gems | `Item.BuildingResource` (Sapphire, Opal, Jade) | ores → list the gems |

  The item lists come from the next dump (asset names) and live in `defaults.lua` (`bags.<id>.items`).
- `GetNumItems` counts items (21,904), not slots.
- Both dumps were taken on a client joined to the user's dedicated server, and both said net role "client":
  correct. So everything above (pages, slot counts, weight modifiers, categories) is what the **client** sees
  through replication, which is good news for the UI side.
- **Local-world dump (third):** net role **"host"** — `HasAuthority=true  Role=3  IsLocalController=true
  IsServer=true  IsDedicatedServer=false  IsStandalone=true  GameModeBase=true`. So `netRole()` is right for host
  and client; the "dedicated" branch is still unseen until UE4SS is on the server (T19 partly settled).
  Pages, slot counts and weight modifiers match the client's view. That inventory held almost none of the bag
  items (no herbs, ores, gems or seeds), so the Numpad − dump now also writes `dumps/items.txt`: every loaded
  `ItemData` (and subclass) with asset name, display name, category, weight and stack size, grouped by category.
  Asset names seen so far: `ITEM_Rune_Essence`, `ITEM_Resources_VaultCore`, `ITEM_FishingRod_Willow`,
  `ITEM_FishingNet_FineNet`, `ITEM_FishBait_{Feather,FeatheredLure,Shrimp,Spooky}`, `ITEM_Logging_Axe_Steel`,
  `ITEM_Pickaxe_Steel`, `ITEM_Spade_T5_Steel`. Naming is `ITEM_<Group>_<Name>`, not `ItemData_…`.
- **Item catalog (items.txt, 2026-11-08):** 1,545 loaded definitions in 93 categories, taken in the local
  world. The item lists for herbs, gems and ores are filled in `defaults.lua` from it. Findings:
  - The seed category `ItemFilter.Material.Seed` holds 30 seeds; the only other "seed" is a quest item.
  - Bait has 8 subcategories under `Item.Equipment.Ammo.Bait` (Fishing Bait, Anchovy, Lobster/Monkfish, ...).
  - Ores and gems are all `Item.BuildingResource`, as are planks, clay, limbs, Ascension cores and more.
  - Herbs are `ItemFilter.Material.BasicMaterial` with asset names `ITEM_Herb_*`, except Avantoe
    (`ITEM_Resources_Agility_Avantoe`).
  - Some assets are named `*_Deleted` (an Emerald, a Runite Ore): left out.
  - **Decided by the user (2026-11-08):** Luminite is an ore; Shocking Plant Bulb and Poison Ichor are herbs;
    Cursed Essence goes with Rune Essence; farming tools (watering cans, secateurs, compost buckets) and the 6
    torches (`ItemFilter.Type.Equipment.Tool`) go in the Tool Belt, which grows to **16 slots** (two rows of 8;
    the top row is still the Primary hotbar's page 2). Rule: **everything the game lists as a tool** goes in
    the Tool Belt, including the Anima Orb and the Scarab Staff, so its filter is the parent category
    `Item.Equipment.Tool` (which bag matching must treat as covering its child tags) plus the torches'.
- **T2 and T3 passed (local world, 2026-11-11; `pagetest` feature, Numpad *):** a 5th page `{ SlotType = 9,
  NumSlots = 16 }` was written into `InventoryPages` from Lua, the Runes page's `GameplayTagQuery` copied into it
  (1 tag, 5 tokens, same as Runes), `MaxSlotCount` 176 → 192, and `ItemSlots` grew to 192. The game accepts it:
  `IsValidSlotIndex` true for 176–191 and false for 192, `GetFreeSlotCountFromSlotType(9)` = 16, and the UI's
  `InventoryUIAPI:GetInventorySlots(9)` returns 16 slots (Runes still 32). Item count unchanged (22,034). **Plan A
  works for adding a page while playing.** Not known: which write method worked (way 1 or 2), and whether
  `ItemSlots` grew by itself (the first report was overwritten by the re-check; the probe now appends).
- **T1, first run (2026-11-11):** `JsonInventory` stays empty all session. The save landed in a
  `loaded=false` inventory (1 item) about 6 s after it appeared, signalled by `OnRep_ItemSlots` then
  `OnRep_HasLoadedFromSave` (both fire on the host, filtered to the player's main inventory). Then the main
  inventory disappeared (+85 s) and a new one was found already loaded; `OnInventoryLoadedFromSave` fired
  after that, and its **pre-hook already saw the loaded items**, so it can't be used to add pages before
  loading. Open: what happened at +53 s and +85 s (a menu or preview controller, then the world?), and whether the
  world's inventory has a `loaded=false` moment at all.
- **T1, second run (2026-11-11, per-frame poll + `NotifyOnNewObject`):** loading straight into the world, the
  first visible state of the player's main inventory is already loaded (22,034 items). `OnInventoryLoadedFromSave`
  fired at +25.6 s with the items already in place; the queued "one tick after creation" look ran at +26.9 s and
  also saw it loaded; the per-frame poll didn't run from +25.6 to +26.9 s (the game thread was busy loading). The
  +3.9 s "new player inventory" with 0 item slots is the class's template (archetype), not a real inventory.
  **Conclusion: there is no game-thread tick between the inventory's creation and its save landing, so Storage
  Mage can't add pages before the load with scheduled code.** Untried: writing `InventoryPages` synchronously
  inside the `NotifyOnNewObject` callback (at construction, before the archetype's values may be copied in:
  risky), or a pre-hook on a Blueprint event that runs before the load.
  **So T13 decides Plan A:** what the game does with a saved item in slot 176+ when the reloaded inventory has
  176 slots. If it re-places the item in a free slot, Storage Mage re-adds pages after load and moves bag items
  back (from its own record of what was in each bag). If it deletes it, bag items must leave the bag slots
  before every save, or Plan A needs the construction-time write.
- T6/T13 probe (Numpad /): moves one Air Rune into slot 176 of the test page (its filter is the Runes copy),
  then the user saves (quits to the menu), reloads and counts Air Runes with Numpad −. **Not run: T13 is
  answered by Maxxfilth's probes** (see "Prior art": items in missing pages go to Items or the hotbar, or are
  deleted if both are full). **The next test is the template patch (T1c)**: patch
  `BP_Components_Inventory_GEN_VARIABLE` at the main menu and confirm a world loads with the pages in place.
- **T1c built (2026-11-11): feature `pages`** (`features/pages.lua`). It patches the template at script load,
  in `RegisterInitGameStatePostHook` and `RegisterLoadMapPostHook`, and retries each second until the
  Blueprint is loaded. It appends the seven layout pages, each made by growing the array, copying Runes, then
  setting SlotType, NumSlots and the tag `ItemFilter.StorageMage.<Bag>`. It raises the template's
  `MaxSlotCount` to 424, and verifies each page by reading it back. It refuses when Tool Belt or RuneScape
  Bags is installed, or when the game's pages or any extra page differ from the expected layout
  (`pages.plan`, unit-tested). No item carries the new tags yet, so the pages accept nothing. Report:
  `dumps/pages.txt` (the patch, then each world's live inventory, then the UI's view once the inventory is
  opened). The retired Numpad * / Numpad / probes are gone.
- **T1c PASSED (local world, 2026-11-11 22:13, layout 9–15):** the template was patched on the first
  `RegisterInitGameStatePostHook` (about 2 s after start), giving 11 pages and `MaxSlotCount` 424. The archetype
  seen at +3.3 s already had `pages=11 maxSlots=424`. The save loaded straight into the patched inventory: 11
  pages, `MaxSlotCount` = `ItemSlots` = 424, every bag page with the right SlotType, NumSlots and tag. Items
  were unchanged (22,034). `IsValidSlotIndex(423)` was true and `(424)` false. Tool Belt free slots were 16. Once
  the inventory was opened, the UI's `GetInventorySlots` gave 16 for type 9 and 72 for type 12. There were no
  errors in UE4SS.log. **Plan A's storage works in a local world.** Still to see: a dedicated server
  (milestone), and items actually in the pages surviving a save and reload (once items can get in).
- **Tool Belt, step 1 built (2026-11-11):**
  - `filters.lua` (pure, unit-tested) decides which bag an item belongs to. Item lists win over categories, and
    categories match their child tags. It also holds `tagFor`, and the format of the path cache.
  - Feature `tags` adds `ItemFilter.StorageMage.<Bag>` to each matching `ItemData.ItemFilterTags.GameplayTags`
    (in memory only). It runs at script load, `InitGameState` (the main menu, before any save), `LoadMap`, and
    every 30 s.
  - Each tagged definition's path goes into `saves/bag-item-paths.txt`. At the main menu, those definitions are
    loaded with `LoadAsset` and tagged before the save is read.
  - Only the Tool Belt is active for now, so items can't land in invisible bag pages.
  - Feature `beltdev` (host / solo, developer keys Numpad / and *) moves tools between Items and the Tool Belt
    with `MoveItem`. Each move is checked by reading both slots back and comparing the item count. It also
    reports the belt's contents once per world. Report: `dumps/belt.txt`.
  - **PASSED in game (2026-11-13, local world):** three steel tools (axe, pickaxe, spade) were moved into the
    Tool Belt, the world was saved and reloaded, and they loaded on slots 176–178. Numpad * moved all three back
    to Items 8–10, with the item count unchanged (22,345). At script load `LoadAsset` loaded none of the 47
    remembered paths; at the first `InitGameState` (main menu) all 47 were already loaded and tagged, before the
    save. So the tagging runs early enough. **Plan A works with real items in a bag page.**
  - The next step is the Tool Belt tab.
- Plan A's last open point, saved items in a bag slot (176+) surviving a save and reload, was answered on
  2026-11-13 (above). Still to see: a dedicated server.
- The loadout lists equipped items that also appear in the main inventory with the same counts (arrows, runes,
  mace, shield): it references them rather than holding separate stacks. Bag code must not count both.

## 5. Tests to run in game (in order)

| # | What | Why |
|---|---|---|
| T1 | When the main inventory loads its save (`bHasLoadedFromSave` / `OnRep_HasLoadedFromSave`), and what `JsonInventory` holds | Saving, timing of page creation |
| T2 | A page with an unknown `SlotType` (9+): accepted? `GetInventorySlots(9)` works? | Plan A at all |
| T3 | Writing `InventoryPages` / `MaxSlotCount` from Lua; copying a `GameplayTagQuery` | Plan A filters |
| T4 | A runtime-made `InventoryComponent` on the controller replicates to the owning client | Plan B |
| T5 | Item categories / filter tags (Storage Mage's Numpad − dump) | Bag tag table |
| T6 | `Server_MoveItemBetweenInventories` with the same inventory as source and target | Drag-to-tab, Plan A |
| T7 | A runtime-duplicated `ItemData` survives save/load | Bag items |
| T8 | A runtime `RecipeData` appended to `CraftingStationComponent.ValidRecipes` shows and crafts | Crafting bags |
| T9 | Which page `AddItem` picks when several accept an item | Free pickup routing |
| T10 | Which of `LoadoutComponent:OnReceiveInventoryChanged` / `LinkedInventorySubsystem:LinkedInventoryChanged` fire on the server | Sweep trigger |
| T11 | Functions of `MagneticComponent_GrantItem`, `WorldItem` (extend the dump) | Pickup pre-hook |
| T12 | Crafting counts items in bag pages (Plan A) / in added inventories (Plan B) | Workbench access |
| T13 | **Bag items after the mod is removed and the save reloaded** | Never losing items |
| T14 | Persistence id → `ItemData`; a controller's character GUID | Plan B saving |
| T15 | Any game-saved place a mirror could live | Removal safety |
| T16 | Spawning a gravestone holding items | Emptying overflow |
| T17 | Spawning a world chest the game saves | Emptying overflow |
| T18 | `AddItemWeightMultiplier` with an empty tag; stacking with perks | Weight slider |
| T19 | Detecting server / dedicated server / Storage Mage on the server | Server presence |
| T20 | Shared-variable functions on this UE4SS build | Frame Mage theme link |
| T23 | (Dropped 2026-11-11: the layout no longer reuses slot types 7 and 8.) | — |
| T22 | Frame Mage's texture replacement reaches widgets Storage Mage creates later (and after a theme switch) | Theming built-from-game elements |
| T21 | LazyStorageSolo's sort / fill with bag pages present | Conflicts |

## 6. Phases
1. Scaffold + developer dump (done: this folder; Numpad − writes `dumps/inventory.txt` for T1–T3, T5).
2. Tool Belt: Plan A page (or Plan B), drag-to-tab, saving, Empty bags, safe removal (T1–T6, T13).
3. Pickup routing and workbench access (T9–T12).
4. Crafted bags and recipes (T7, T8).
5. Carry-weight slider (T18).
