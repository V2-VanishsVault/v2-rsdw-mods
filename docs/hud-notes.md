# HUD notes

Findings from play-testing the editor, kept for the art and replacement work.

## To replace with Frame Mage's own versions

| Element | Game widget | Notes |
|---|---|---|
| Background panel | `WBP_Inventory_MainPanel` / `BackgroundPanel` (`WBP_Panel_Inventory_C`) | The inventory screen's frame. On the HUD it wraps the hotbar and (at least) the party frame, so it's treated as a container, not moved as one piece. Its art is `MI_Menu_PanelBG_Shared` (a material). |

## How elements are grouped

The editor decides what moves as one piece in `FrameMage/Scripts/framemage/editor/units.lua`:

- **Compass:** the markers belong to `WBP_HUD_Compass` (it draws its own strip), so it moves as one.
- **Hotbar:** `QuickAccessBar` only wraps one list (`SlotGridContainer`, 8 slots), so it moves as one.
- **Key hints** (Block, Attack...) and **menu shortcuts** (chat, map, spellbook, build, inventory) are two lists
  inside `WBP_InputLegend_World`, which draws nothing itself, so each list is its own element:
  `GameInputs`, and the shortcut row `HorizontalBox_436`.
- **Upkeep:** `WBP_SurvivalCore_Upkeep` inside `WBP_HUD_PlayerVitalsBars`. When nothing in it is showing, selecting
  it shows a stand-in panel.
