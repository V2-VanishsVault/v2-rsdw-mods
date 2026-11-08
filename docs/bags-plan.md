# Bags: plan

Status: design, waiting on the API dump.

**Decided (2026-11-07):**
- **Bags live in Storage Mage**, a sibling mod. Storage Mage owns the bags, pickup routing, workbench access,
  saving and the carry-weight slider. Frame Mage stays UI-only and draws the bag tabs and drag-to-tab moves,
  talking to Storage Mage through shared variables (like Mod Menu does).
- **The mod runs on the server too.** The player can install UE4SS on their dedicated server, so Storage Mage
  runs on both sides: the server owns the real inventories, and clients show them.

## What players get

New tabs in the inventory, after the game's own (Items, Runes, Arrows, Quests):

| Bag | Slots | How you get it |
|---|---|---|
| Tool Belt | 8 | Everyone has it (its top row is the Primary hotbar's page 2) |
| Herbs | 48 | Crafted |
| Gems | 24 | Crafted |
| Ores | 72 | Crafted |
| Seeds | 64 | Crafted |
| Fishing | 16 | Crafted |
| Rune Essence | 8 | Crafted |

- A bag's tab appears once the bag is crafted and carried.
- **Pickups go to the right bag automatically** (an ore into the Ores bag), falling back to the main inventory
  when the bag is full or not carried.
- **Workbenches see bag contents** when crafting, like the main inventory.
- **Moving items:** drag an item onto a tab to move it into that bag (smooth, no extra key). Dropping onto the
  tab of the bag it's already in does nothing; a full bag refuses, with a message.
- **Carry weight slider** in options: 0% (everything weightless) to 100% (normal weights), default 50%.

## What the game already has (from the type map)

- **Per-category inventories.** The inventory screen already has separate bodies for Items, Runes, Ammunition and
  Quest Items (`WBP_Inventory_InventoryBody_C` x 4 with tab buttons `WBP_InventoryTabButton_C`), and
  `InventoryBodyBase` has a `SlotType` (`EInventorySlotType`). New tabs can follow the same pattern.
- **Item filters.** `InventoryComponent.AllowedItemFilterQuery` (a gameplay-tag query) limits what an inventory
  accepts: a bag can be an inventory that only accepts its category's tags.
- **Weight modifiers.** `InventoryComponent.ItemWeightModifier` (an array of modifiers): the carry-weight slider can
  likely be one more modifier rather than a rewrite.
- **Linked inventories.** `LinkedInventoryComponent` exists; it's probably how workbenches reach more than one
  inventory, and the way to make bags visible to them.

## The hard parts

- **Server authority.** On a dedicated server, inventories, pickups and weight are decided by the server. A
  client-only mod can draw tabs, but can't make the server put items in a bag or weigh them differently. Bags and
  the weight slider need the mod on the server as well (UE4SS on the dedicated server), or work only in
  single-player and self-hosted worlds.
- **Saving.** Bag contents must save with the character (`InventoryComponent.JsonInventory` suggests inventories
  serialise to JSON), and must survive the mod being removed without losing items.
- **Never lose items on removal** (user's rule): bag contents go back into the main inventory; whatever doesn't
  fit is **dropped in chests placed on the ground around the character** (as many as needed), or as loose items
  if no chest can be placed. Never deleted. Because a removed mod can't run code, this needs both:
  - an **"Empty bags (before uninstalling)"** action in Mod Menu that does the unpacking while the mod is still
    there, and the same unpacking whenever a bag is lost (dropped, destroyed);
  - storage that the game itself keeps without the mod, if the API allows it (bag contents held in a game-native
    container), so even an uninstall without that step loses nothing. To confirm from the API dump.
- **Crafting the bags** needs new recipes, which means adding data the game's crafting reads (to be found in
  the API dump).

## Phases (once decided)

1. API dump (Numpad +), and confirm: inventory move / add functions, crafting's inventory lookup, weight.
2. Tool Belt tab: a new tab and inventory, drag-to-tab moves, saving, and safe removal.
3. Pickup routing and workbench access.
4. The crafted bags and their recipes.
5. Carry-weight slider.
