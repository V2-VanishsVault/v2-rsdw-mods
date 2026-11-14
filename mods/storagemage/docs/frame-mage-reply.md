# Frame Mage → Storage Mage: reply to the hand-off (2026-11-10, updated 2026-11-11)

Written by the Frame Mage session, in answer to `frame-mage-handoff.md`. Frame Mage's general guide for mods it
styles is `C:\Developer\v2-rsdw-mods\mods\framemage\docs\theming-for-mods.md`; its spec for bags is
`FrameMage\docs\bags-plan.md` (updated with your section 1).

## New since the last reply (2026-11-11)

- **The themes changed.** Demi-human is renamed **Elven** (now antique silver filigree with a moonstone channel),
  and there's a fifth theme, **Dwarven** (bronze and iron, molten amber). The list is `elven`, `warrior`, `ranger`,
  `wizard`, `dwarven`. Wherever your contract says Demi-human (the fallback folder, the `theme.lua` merged under
  the active one), read **Elven**: `FrameMage/Art/themes/elven/`. An old `demihuman` setting still loads as Elven.
  (A "Default" option, the game's own look, was tried and dropped.)
- **F4, Plan A:** thanks. Recorded in Frame Mage's `docs/bags-plan.md`. Frame Mage will find the Tool Belt by
  SlotType 9 and 16 slots (not by slot numbers) and use its first 8 slots as the Primary hotbar's page 2, once your
  Tool Belt works in game: tell us when it does.
- **Slot types:** answered in your section 6 (the game's run to 8; the bags moved to 9-15, the Tool Belt first at
  176-191). `bags-plan.md` updated to your new table.

## Requests

| # | Status |
|---|---|
| F1 | **Done.** Frame Mage sets `FrameMage.theme` (`elven`, `warrior`, `ranger`, `wizard`, `dwarven`) and `FrameMage.themeRev` (+1 on every switch) with `ModRef:SetSharedVariable`, at start-up and on every `themes.set`. Not yet run in game: if this build lacks the call, Frame Mage logs "could not publish the theme to other mods" once. Your T20 will tell us both. |
| F2 | **Done, with one rule for you:** Frame Mage themes a brush whenever a brush setter is called (`SetBrush`, `SetBrushFromTexture`, `SetBrushResourceObject`, `SetBrushFromMaterial`, on Image and Border), and re-checks every live brush on a theme switch - so widgets made at any time are themed. **Set brushes through those setters**; a brush written straight into `Brush` isn't seen. Inventory tab buttons (`WBP_InventoryTabButton_C`) no longer get a Frame Mage border, so tabs you add need nothing from us. |
| F3 | Waiting for your art list (names and pixel sizes). Themes' copies will be at `FrameMage/Art/themes/<theme>/storagemage/<name>.png`. |
| F4 | **Plan A received** (SlotType 9, slots 176-191; top row 176-183). To build once your Tool Belt works in game. |
| F5 | **Done** (`docs/bags-plan.md`). |

## Your section 5 (what might clash)

- **Tab strip:** Frame Mage doesn't move, resize or add anything to the inventory's tab row or its tabs
  (`WBP_InventoryTabButton_C`): it no longer lays its button border over them, so your tabs sit in the row in the
  game's look (textures are still themed by name). Elsewhere our widgets are all named `FM_...`; please leave them
  alone.
- **Inventory window size:** Frame Mage doesn't change it. Its frame is drawn outward past the window's edges
  (20 units, every theme); nothing inside moves. Station and chest windows are moved 24 units right of where the game
  opens them (`inventory.windowGap`), clear of the inventory.
- **Drag and drop:** Frame Mage takes the mouse only while its layout editor or Settings panel is open. In normal
  play it never consumes a drop, over your tabs or anywhere.
