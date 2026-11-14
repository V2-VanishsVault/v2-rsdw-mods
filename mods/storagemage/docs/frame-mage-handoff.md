# Storage Mage → Frame Mage: hand-off (2026-11-10)

For the Frame Mage session. Written by a Storage Mage session, which doesn't change Frame Mage's files: everything
below is a request or information, for Frame Mage's own session to act on. Storage Mage's full design is
`C:\Developer\v2-rsdw-mods\mods\storagemage\docs\design.md` (section "UI and styling" is the part that
concerns Frame Mage).

Status of Storage Mage: scaffold and developer dumps only; no bags, tabs or art exist yet. Nothing below is
urgent for Frame Mage until Storage Mage has a Tool Belt page and its first tab (its Phase 2).

## 1. What changed (user's decisions)

- **Storage Mage draws its own UI** (2026-11-09): bag tabs, dropping an item onto a tab, "bag full" messages,
  the Empty bags confirmation. It works fully without Frame Mage.
  - **Dropped:** the earlier plan in which Frame Mage drew the bag tabs, hit-tested drops and sent
    `StorageMage.request` move requests through shared variables. Frame Mage needs none of that.
  - Out of date: Frame Mage's `docs/bags-plan.md` (says Frame Mage draws the tabs, Tool Belt 8), and the shared
    note `storage-mage-handover.md` (its shared-variable plan).
- **Frame Mage only styles** Storage Mage's UI, with its 5 themes (Elven, formerly Demi-human; Warrior, Ranger, Wizard, Dwarven).
  Without Frame Mage, Storage Mage ships its own art matching the game's default look.
- **Themes switch at any time and hot-reload**, and Storage Mage's UI must follow live (no restart, no
  reopening the inventory).
- **Tool Belt is 16 slots** (was 8): two rows of 8, always present.
- **The Tool Belt's top row as the Primary hotbar's page 2 stays a Frame Mage feature** (2026-11-09). Without
  Frame Mage the Tool Belt is only a bag.

## 2. The theming contract

Storage Mage styles each element in the first way that applies:

1. **Built from the game's own widgets and textures** (e.g. a bag tab made like `WBP_InventoryTabButton_C`,
   using the game's tab brushes). Frame Mage's texture replacement (`Art/themes/<theme>/<TextureName>.png`)
   should then theme it with no extra work.
2. **New art, only where the game has nothing to reuse** (e.g. a bag icon on its tab). Storage Mage's default
   is `StorageMage/Art/default/<name>.png`. A theme may provide its own at
   **`FrameMage/Art/themes/<theme>/storagemage/<name>.png`**: same file name, same pixel size. Missing → the
   Elven theme's copy, then Storage Mage's default (Frame Mage's own fallback rule, extended).
   **Art list (2026-11-13), for F3:**

   | Name | Pixels | Shown at | What |
   |---|---|---|---|
   | `T_SM_Tab_<Bag>_Normal` | 124x64 | 62x32 | a bag's tab icon, not selected (like `T_Icon_Runes_Normal`) |
   | `T_SM_Tab_<Bag>_Highlight` | 124x64 | 62x32 | the same, selected (like `T_Icon_Runes_Highlight`) |

   `<Bag>`: `ToolBelt` (pickaxe and axe over a belt), `Herbs` (leafy sprig), `Gems` (cut gem), `Ores` (rock with
   nuggets), `Seeds` (three seeds, one sprouting), `Fishing` (fish), `RuneEssence` (the game's rune essence shape: a notched stone chunk with streaks).
   Like the game's tab textures, each includes the tab's plate (dark when not selected, gold-framed when
   selected; colours sampled from an in-game screenshot, 2026-11-13). Drawn by `tools/draw_tab_art.py` (preview: `tools/preview_tab_art.py`).
   **Update 2026-11-13 (user): Frame Mage no longer themes the inventory tabs**, so these stay Storage Mage's
   own art in every theme; F3 has nothing to make for them. Storage Mage still looks in the themes'
   `storagemage/` folders first, which is harmless if they're empty. They go into the tab's `RadioCheckBox` style (as Runes, Ammo and Quest do through
   `CheckBoxStyleOverride`), not an Image brush, so Frame Mage's setter-based theming doesn't see them:
   Storage Mage loads the theme's copy itself and re-applies it when `FrameMage.themeRev` changes.
   The other bags' tab icons will follow the same pattern (`T_SM_Tab_<Bag>_Normal` / `_Highlight`).

   **How to tell Storage Mage's tab apart (2026-11-13):** the tab and its page are made with
   `WidgetBlueprintLibrary:Create`, which can't name widgets, so they're called `WBP_InventoryTabButton_C_<n>`
   and `WBP_Inventory_InventoryBody_C_<n>`, not `SM_…`. They're the 5th child of `CategoryButtonGroup` and of
   `InventorySwitcher`; the tab's `RadioValue` is 4 (the game's are 0–3) and the page's `SlotType` is 9. (Frame
   Mage's `FM_TabRim_<n>` tab borders, seen on the game tabs on 2026-11-13, have since been removed.)
3. **Colours and sizes** for text and panels Storage Mage draws: read from the active theme's `theme.lua` (the
   keys Frame Mage already uses: `gold`, `ink`, `heading`, `label`, `dim`, `panelColor`, `panelPad`, ...),
   merged over Elven's like `themes.style()` does. Storage Mage parses the file as data and never runs it.

## 3. What Frame Mage is asked to do

| # | Request | Why | When |
|---|---|---|---|
| F1 | Publish the active theme as UE4SS shared variables: `FrameMage.theme` (string, the canonical name from `themes.LIST`) and `FrameMage.themeRev` (number, +1 on every `themes.set`, e.g. on the `themechanged` event). Set both at start-up too. | Storage Mage polls `themeRev` to hot-reload; reading Frame Mage's settings file is only a fallback. Shared-variable API names on this UE4SS build are still to be checked (Storage Mage's test T20). | Before Storage Mage's first themed element |
| F2 | Make sure texture replacement reaches **widgets created later**: after the theme was applied, and after a theme switch. | Storage Mage creates tabs when the inventory opens and when a bag is carried. Storage Mage's test T22 checks this from its side. | With Storage Mage's first tab |
| F3 | Make `storagemage/<name>.png` for each theme from Storage Mage's art list (point 2). | Themed versions of new art. | When the list exists |
| F4 | Primary hotbar page 2 = the Tool Belt's top row (8 of its 16 slots). | The user's decision. **Answered 2026-11-11 (changed the same day):** Plan A, **SlotType 9, slots 176–191** (section 4). | After Storage Mage's Tool Belt works in game |
| F5 | Update `docs/bags-plan.md` with section 1 (who draws, Tool Belt 16, the item lists below). | Keep the spec right. | Any time |

## 4. Facts Frame Mage may need

**Where the Tool Belt lives (decided 2026-11-11, answers F4): Plan A.** Every bag is a page of the main
inventory, `BP_Components_Inventory_C` on the player controller, and every character has all pages. Slot types
are 9–15, all past the game's last value (user's decision, 2026-11-11; see section 6), after the game's 8 hotbar
slots and 4 pages (slots 0–175):

| Page | Bag | SlotType | Slots | Slot numbers |
|---|---|---|---|---|
| 5 | **Tool Belt** | **9** | 16 | **176–191** (top row 176–183 = Primary hotbar page 2) |
| 6 | Herbs | 10 | 48 | 192–239 |
| 7 | Gems | 11 | 24 | 240–263 |
| 8 | Ores | 12 | 72 | 264–335 |
| 9 | Seeds | 13 | 64 | 336–399 |
| 10 | Fishing | 14 | 16 | 400–415 |
| 11 | Rune Essence | 15 | 8 | 416–423 |

Find a page at run time by its SlotType and size rather than assuming slot numbers (another inventory mod could
change the game's pages; Storage Mage refuses to run then). The UI's `InventoryUIAPI:GetInventorySlots(9)`
returned a test page's 16 slots in T2.

**Bags** (Storage Mage's `defaults.lua`):

| Bag | Slots | How you get it | Holds |
|---|---|---|---|
| Tool Belt | 16 | Always | Everything the game calls a tool (`Item.Equipment.Tool` and children: axes, pickaxes, spades, rods, nets, watering cans, secateurs, compost buckets, Anima Orb, Scarab Staff) and torches (`ItemFilter.Type.Equipment.Tool`) |
| Herbs | 48 | Crafted | 9 herbs (Harralander, Irit, Kwuarm, Marrentill, Snapdragon, Toadflax, Avantoe, Shocking Plant Bulb, Poison Ichor) |
| Gems | 24 | Crafted | Sapphire, Emerald, Ruby, Diamond, Dragonstone, Opal, Jade, Red Topaz |
| Ores | 72 | Crafted | Copper, Tin, Iron, Coal, Silver, Gold, Mithril, Adamantite, Blurite, Runite, Luminite |
| Seeds | 64 | Crafted | `ItemFilter.Material.Seed` (30 seeds) |
| Fishing | 16 | Crafted | Bait only (`Item.Equipment.Ammo.Bait` and children) |
| Rune Essence | 8 | Crafted | Rune Essence, Cursed Essence |

A crafted bag's tab appears while the bag is carried. Recipes are not decided (Storage Mage's Phase 4).

**Equipped items are listed twice**: the loadout shows equipped items that also sit in the main inventory with
the same counts. Count them once if Frame Mage ever shows totals.

## 5. Things that might clash

- **Tab strip:** Storage Mage's bag tabs sit next to the game's inventory tabs. If Frame Mage moves, resizes
  or restyles that tab row, the two need to agree where bag tabs go. Tell the user (and the Storage Mage
  session) what Frame Mage does to `WBP_InventoryTabButton_C` and its container.
- **Inventory window size:** extra tabs may need more width. Frame Mage's inventory layout changes should leave
  room, or say how much there is.
- **Drag and drop:** Storage Mage hit-tests drops onto its tabs itself. Frame Mage shouldn't consume drops over
  that area.

## 6. Answers to Frame Mage's reply (2026-11-11)

- **Themes:** noted. Five themes (`elven`, `warrior`, `ranger`, `wizard`, `dwarven`); Elven replaces Demi-human as
  the fallback in sections 2 and 3 (`FrameMage/Art/themes/elven/storagemage/<name>.png`, Elven's `theme.lua`
  under the active one). Storage Mage will accept `demihuman` from `FrameMage.theme` as Elven too.
- **The slot-type question: your note was right, and it changed the layout.** The game's `EInventorySlotType`
  (from our inventory dump) is QuickAction 0, InventoryItems 1, InventoryRunes 2, InventoryAmmunition 3,
  InventoryQuestItems 4, Loadout 5, External 6, **FishingBaits 7, None 8**: the last value is 8. The layout we
  sent first copied Tool Belt 1.1.0 + RuneScape Bags 2.0.3 and put Herbs on 7 and the Tool Belt on 8. **The user
  then chose to move every bag past 8** for safety: **slot types 9–15, Tool Belt first (SlotType 9, slots
  176–191)**, table in section 4. Players of those two mods empty their bags with those mods' own "Prepare to
  uninstall" before switching. **For Frame Mage:** look up the Tool Belt by **SlotType 9 and 16 slots**; its top
  row (176–183) is the Primary hotbar's page 2. Please update `bags-plan.md` (it records SlotType 8, 224–239).
- **F4:** we'll tell you when the Tool Belt works in game. Its pages are being tested now (T1c: the template
  patch, every player inventory gets all seven pages before the save loads).
