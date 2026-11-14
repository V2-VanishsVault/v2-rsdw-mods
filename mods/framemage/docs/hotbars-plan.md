# Custom hotbars: plan

Status: design. The game functions to call are confirmed from `dumps/api.txt` (Numpad + in game) before building.

## Scope

Four hotbars in total, as two bars with two pages each:

| Bar | Page 1 | Page 2 | Slots | Keys (defaults, rebindable) |
|---|---|---|---|---|
| Primary | Actions (the game's hotbar row) | Tools (the Tool Belt bag's top row) | 8 | 1-8 |
| Spells | Spells A | Spells B | 10 | Numpad 0-9 |

Switching pages: Shift + mouse wheel over a bar, a page key per bar (default ` for Primary, Numpad . for Spells),
or the arrows on the bar. Each bar shows which page it's on. Keys always act on the page you're looking at.

## What the game gives us (from the type map)

- **The hotbar is the first row of the inventory.** `InventoryComponent.ItemSlots` holds every slot; the first
  `NumberOfQuickActionSlots` (8) are the hotbar. The HUD shows them through `QuickAccessBarBase`
  (`WBP_Inventory_MainPanel` / `QuickAccessBar`), inside the inventory screen's frame.
- **Keys 1-8 are Enhanced Input actions.** `QuickAccessBarBase.QuickAccessSlotInputActions` (one per slot) in
  `QuickAccessInputMappingContext`. Using slot N is the game's own action, so it works with the server.
- **Spells live on `SpellcastingComponent`.** `SelectedSpells` holds `NumSpellRadials` x `NumSpellSlotsPerRadial`
  spells (the Q radial's pages and slices). Each radial slice knows its `SpellSlotNum`. The radial already has an
  "assign" mode (`AssignInfoTextBlock`, `AssignableAnim`), used by the spellbook screen's drag and drop.

## The design

### Primary bar (8 slots, keys 1-8)

- Our own standalone hotbar widget in the theme, movable like any element. The game's hotbar row is hidden on
  the HUD (the inventory screen still shows its top row).
- **Page 1, Actions** mirrors the game's hotbar row; keys 1-8 stay the game's own actions.
- **Page 2, Tools** is the top row of the Tool Belt bag (see [bags-plan.md](bags-plan.md)). Turning to it swaps
  those 8 items with the hotbar row using the game's own item-move function (server-safe), so keys 1-8 use what
  the visible page shows. Without bags, page 2 uses 8 reserved inventory slots instead.

### Spell bar (10 slots, Numpad 0-9)

- Spells only. Casting a slot calls the game's spell-cast function for that spell (from the API dump), as if
  picked from the Q radial.
- **Assigning:** open the Q radial, hover a spell, hold Shift and press a spell-bar key: the hovered spell goes
  into that slot (on the page showing) without casting. The hovered slice's `SpellSlotNum` gives the spell.
- Spells not learned, or cooling down, show greyed out with the game's cooldown.

## Phases

1. **API dump** (tool done): Numpad + in game, then confirm the move, use and cast functions.
2. **Primary bar, page 1**: our bar mirroring the game's, the game's row hidden on the HUD, theme art.
3. **Spell bar**: cast from a slot, assign from the radial, numpad keys, Mod Menu bindings.
4. **Pages**: page switching for both bars; Primary page 2 via the Tool Belt (or reserved slots).

Each phase is tested in game before the next, single-player first, then on a dedicated server.
