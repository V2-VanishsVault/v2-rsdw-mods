# Bags: plan

Status: Storage Mage's design (`mods/storagemage/docs/design.md`); Frame Mage's part is styling. Updated
2026-11-13 from Storage Mage's hand-off (`mods/storagemage/docs/frame-mage-handoff.md`): the Tool Belt's place is
decided (Plan A), the Tool Belt and its tab work in game, and the art list for F3 is in.

**Decided:**
- **Bags live in Storage Mage**, a sibling mod (2026-11-07). It owns the bags, pickup routing, workbench access,
  saving and the carry-weight slider, and runs on a dedicated server too (the server owns the real inventories).
- **Storage Mage draws its own UI** (2026-11-09): the bag tabs, dropping an item onto a tab, "bag full" messages and
  the Empty bags confirmation. It works fully without Frame Mage, in the game's default look.
  - **Dropped:** the earlier plan in which Frame Mage drew the tabs, hit-tested drops and sent move requests through
    shared variables. Frame Mage does none of that.
- **Frame Mage only styles** Storage Mage's UI, in its themes (Elven, Warrior, Ranger, Wizard, Dwarven), and
  follows theme switches live (no restart, no reopening the inventory). The contract is
  [theming-for-mods.md](theming-for-mods.md).
- **The Tool Belt is 16 slots** (two rows of 8, always present).
- **The Tool Belt's top row as the Primary hotbar's page 2 stays a Frame Mage feature** (2026-11-09). Without
  Frame Mage the Tool Belt is only a bag.

## What players get

New tabs in the inventory, after the game's own (Items, Runes, Arrows, Quests):

| Bag | Slots | How you get it | Holds |
|---|---|---|---|
| Tool Belt | 16 | Always | Everything the game calls a tool (`Item.Equipment.Tool` and children: axes, pickaxes, spades, rods, nets, watering cans, secateurs, compost buckets, Anima Orb, Scarab Staff) and torches |
| Herbs | 48 | Crafted | 9 herbs (Harralander, Irit, Kwuarm, Marrentill, Snapdragon, Toadflax, Avantoe, Shocking Plant Bulb, Poison Ichor) |
| Gems | 24 | Crafted | Sapphire, Emerald, Ruby, Diamond, Dragonstone, Opal, Jade, Red Topaz |
| Ores | 72 | Crafted | Copper, Tin, Iron, Coal, Silver, Gold, Mithril, Adamantite, Blurite, Runite, Luminite |
| Seeds | 64 | Crafted | `ItemFilter.Material.Seed` (30 seeds) |
| Fishing | 16 | Crafted | Bait only (`Item.Equipment.Ammo.Bait` and children) |
| Rune Essence | 8 | Crafted | Rune Essence, Cursed Essence |

- A crafted bag's tab appears while the bag is carried. Recipes aren't decided (Storage Mage's Phase 4).
- Pickups go to the right bag; workbenches see bag contents. There's no dragging into bags (user, 2026-11-13: the
  game's drag and drop runs natively, out of Lua's reach): a sort key puts everything on the Items page away, and a
  take-out key moves the hovered bag item to Items. The hotbar is never sorted.
- Equipped items are listed twice (the loadout and the main inventory, same counts): count them once if Frame
  Mage ever shows totals.

## Frame Mage's part

| # | What | Status |
|---|---|---|
| F1 | Publish the theme as shared variables `FrameMage.theme` and `FrameMage.themeRev` (+1 on every change; set at start-up too) | Done (core/themes.lua `publish`). Whether this UE4SS build has `ModRef:SetSharedVariable` is checked by Storage Mage's test T20; if not, Frame Mage logs one warning. |
| F2 | Theming reaches widgets made later (after the theme was applied, after a switch) | Done: brushes are themed whenever a brush setter is called (hooks), every live brush is re-checked on a switch. (Inventory tab buttons get no Frame Mage border, so tabs added later need nothing.) Storage Mage must set brushes through the setters (see the guide). |
| F3 | `Art/themes/<theme>/storagemage/<name>.png` for each theme, from Storage Mage's art list | Ready to start: the list is in Storage Mage's `frame-mage-handoff.md` section 2 (`T_SM_Tab_<Bag>_Normal` / `_Highlight`, 124x64, drawn at 62x32; defaults in `StorageMage/Art/default/`) |
| F4 | Primary hotbar page 2 = the Tool Belt's top row (8 of its 16 slots) | Answered (Plan A: SlotType 9, top row slots 176-183). Storage Mage's Tool Belt works in game (2026-11-13: items survive a save, the tab shows), so this can be built with the hotbars (`hotbars-plan.md`, phase 4) |

**Where the bags live (decided 2026-11-11): Plan A.** Every bag is a page of the main inventory
(`BP_Components_Inventory_C` on the player controller), and every character has all pages, after the game's 8
hotbar slots and 4 pages (slots 0-175: Items 32, Runes 32, Ammunition 32, Quest Items 72). The game's
`EInventorySlotType` runs QuickAction 0, InventoryItems 1, InventoryRunes 2, InventoryAmmunition 3,
InventoryQuestItems 4, Loadout 5, External 6, FishingBaits 7, None 8; the bags take **9-15**, all past it (user's
decision: an earlier layout copying Tool Belt 1.1.0 + RuneScape Bags 2.0.3 used 7 and 8):

| Page | Bag | SlotType | Slots | Slot numbers |
|---|---|---|---|---|
| 5 | **Tool Belt** | **9** | 16 | **176-191** (top row 176-183 = the Primary hotbar's page 2) |
| 6 | Herbs | 10 | 48 | 192-239 |
| 7 | Gems | 11 | 24 | 240-263 |
| 8 | Ores | 12 | 72 | 264-335 |
| 9 | Seeds | 13 | 64 | 336-399 |
| 10 | Fishing | 14 | 16 | 400-415 |
| 11 | Rune Essence | 15 | 8 | 416-423 |

**For F4: find the Tool Belt at run time by its SlotType (9) and size (16)**, not by slot numbers: another inventory
mod could change the game's pages (Storage Mage refuses to run then). `InventoryUIAPI:GetInventorySlots(9)` returned
a test page's 16 slots in Storage Mage's test T2. Its top row is the page's first 8 slots.

## What Frame Mage does near Storage Mage's UI (for the two to agree)

- **The inventory's tab row:** Frame Mage doesn't move, resize or border the row or its tabs
  (`WBP_InventoryTabButton_C`): they keep the game's look, with only their textures themed by name, so Storage
  Mage's own tabs sit in the row as they are.
- **The inventory window's size:** unchanged. Frame Mage's frame is drawn outward, past the window's edges, by
  20 units (every theme); nothing inside moves. (Station and chest windows are moved 24 units right of
  where the game opens them, clear of the inventory: `inventory.windowGap`.)
- **Drag and drop:** Frame Mage takes the mouse only while its editor or Settings panel is open; in normal play it
  never consumes a drop.

## What the game already has (from the type map)

- **Per-category inventories.** The inventory screen has separate bodies for Items, Runes, Ammunition and Quest
  Items (`WBP_Inventory_InventoryBody_C` x 4 with tab buttons `WBP_InventoryTabButton_C`), and `InventoryBodyBase`
  has a `SlotType` (`EInventorySlotType`). New tabs can follow the same pattern.
- **Item filters.** `InventoryComponent.AllowedItemFilterQuery` (a gameplay-tag query) limits what an inventory
  accepts.
- **Weight modifiers.** `InventoryComponent.ItemWeightModifier`: the carry-weight slider can be one more modifier.
- **Linked inventories.** `LinkedInventoryComponent`: probably how workbenches reach more than one inventory.

## The hard parts (Storage Mage's)

- **Server authority:** bags and the weight slider need the mod on the server too, or work only in single-player
  and self-hosted worlds.
- **Saving**, and **never losing items on removal** (user's rule): an "Empty bags (before uninstalling)" action, and
  game-native storage if the API allows it.
- **Crafting the bags** needs new recipes.
