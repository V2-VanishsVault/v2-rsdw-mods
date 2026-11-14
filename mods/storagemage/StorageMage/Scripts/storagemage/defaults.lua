-- Default settings. Users edit Mods/StorageMage/config/settings.lua (only the lines they change);
-- every setting with its default is regenerated into config/settings.defaults.lua on each start.
-- Key names are Unreal key names (F9, PageUp, Subtract, ...); modifiers: CTRL, SHIFT, ALT.
return {
    enabled = true, -- master switch
    logLevel = "info", -- debug | info | warn | error

    -- Turn a feature off to isolate a problem. Removed/false features never load.
    -- pages: adds the bag pages (storagemage/layout.lua) to every player inventory, before the save loads.
    -- pagetest: developer test T1, a read-only load timeline -> dumps/t1.txt. Off since 2026-11-11: T1 is done,
    -- and it reads the inventory every frame (ruled out first when the first Tab press after loading was missed).
    -- tags: marks each bag item's definition with its page's filter tag (now the Tool Belt's only).
    -- uidump: developer, read only: the inventory screen's tab bar -> dumps/ui.txt, once per screen. Off since
    -- the Tool Belt tab works (2026-11-13).
    -- belttab: the Tool Belt's tab on the inventory screen (adds widgets only; report dumps/tab.txt).
    -- dragprobe: developer, read only: the inventory screen's drag/drop/move functions and their calls ->
    -- dumps/functions.txt and dumps/drag.txt; Numpad + reports the slot under the mouse. Off since its run
    -- (2026-11-13): it hooks 40 functions.
    -- bagmoves: pickup routing, the sort key and the take-out key (report dumps/moves.txt).
    features = { probe = true, pages = true, tags = true, uidump = false, belttab = true, dragprobe = false,
        bagmoves = true, pagetest = false },

    -- Items you pick up (or take from a chest, or craft) that belong in a bag go straight into it.
    pickupRouting = true,

    keys = {
        sortBags = "Divide", -- Numpad /: put everything on the Items page that belongs in a bag into it
        takeOut = "T", -- with the inventory open: the bag item under the mouse to the Items page, or an Items-page item into its bag
        dumpInventory = "Subtract", -- developer (Numpad -): the player's inventories -> dumps/inventory.txt
        hoverProbe = "Add", -- developer (Numpad +, feature dragprobe): the slot under the mouse -> dumps/drag.txt
    },

    -- Bags (not built yet: see docs/design.md, section 4). An item belongs to a bag when its ItemData category
    -- is in `categories` (a category also matches its child tags) or its asset name is in `items`. Categories
    -- shared by several bags (BasicMaterial, BuildingResource) are never listed: those bags list items instead.
    -- Item lists come from dumps/items.txt (2026-11-08). Assets named *_Deleted are left out.
    -- Slot counts and page order are NOT settings: they're fixed in storagemage/layout.lua.
    bags = {
        -- Fishing rods and nets are tools: they go here, not in the Fishing bag (user's decision, 2026-11-08).
        -- Every item the game lists as a tool, 16 slots (user's decisions, 2026-11-08). Item.Equipment.Tool and
        -- its children: axes, pickaxes, spades, rods, nets, watering cans, secateurs, compost buckets, the Anima
        -- Orb and the Scarab Staff (whose category is the parent itself). ItemFilter.Type.Equipment.Tool: torches.
        toolBelt = { name = "Tool Belt", always = true, items = {},
            categories = { "Item.Equipment.Tool", "ItemFilter.Type.Equipment.Tool" } },
        -- Category BasicMaterial is shared with logs, hides, Rune Essence and more, so herbs are listed.
        herbs = { name = "Herbs", categories = {}, items = {
            "ITEM_Herb_Harralander", "ITEM_Herb_Irit", "ITEM_Herb_Kwuarm", "ITEM_Herb_Marrentill",
            "ITEM_Herb_Snapdragon", "ITEM_Herb_Toadflax", "ITEM_Resources_Agility_Avantoe",
            "ITEM_Herb_Plant_Bulb_Shocking", "ITEM_Herb_Poison_Ichor" } },
        -- Category BuildingResource is shared with ores, planks, clay and more, so gems are listed.
        gems = { name = "Gems", categories = {}, items = {
            "ITEM_Resources_Sapphire", "ITEM_Resources_Emerald", "ITEM_Resources_Ruby", "ITEM_Resources_Diamond",
            "ITEM_Resources_Gem_Dragonstone", "ITEM_Resources_Opal", "ITEM_Resources_Jade", "ITEM_Resources_Red_Topaz" } },
        -- Coal counts as an ore (user's decision, 2026-11-08).
        ores = { name = "Ores", categories = {}, items = {
            "ITEM_Resources_CopperOre", "ITEM_Resources_TinOre", "ITEM_Resources_IronOre", "ITEM_Resources_Coal",
            "ITEM_Resources_SilverOre", "ITEM_Resources_GoldOre", "ITEM_Resources_MithrilOre",
            "ITEM_Resources_AdamantiteOre", "ITEM_Resources_BluriteOre", "ITEM_Resources_Ore_Runite",
            "ITEM_Resources_Ore_Luminite" } },
        seeds = { name = "Seeds", categories = { "ItemFilter.Material.Seed" }, items = {} },
        -- Bait only: rods and nets go to the Tool Belt.
        fishing = { name = "Fishing", categories = { "Item.Equipment.Ammo.Bait" }, items = {} },
        runeEssence = { name = "Rune Essence", categories = {},
            items = { "ITEM_Rune_Essence", "ITEM_Resources_Essence_Cursed" } },
    },

    -- Carry weight, % of normal item weight: 0 = weightless, 100 = the game's weights. Applied by the server.
    carryWeightPercent = 50,
}
