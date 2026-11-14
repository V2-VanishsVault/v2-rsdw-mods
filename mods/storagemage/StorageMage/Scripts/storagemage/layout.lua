-- The bag pages added to the player's main inventory. FIXED: not a setting, and never to be changed once saves
-- use it. The game puts each saved item back in its saved slot number, so a changed size or order moves later
-- pages' items into the backpack (or deletes them if it's full). Only ever append new pages at the end.
--
-- Slot types 9-15, all past the game's last EInventorySlotType value (8 = None; 7 = FishingBaits), so the game
-- can never treat a bag page as one of its own kinds (user's decision, 2026-11-11). Deliberately NOT the layout of
-- Tool Belt 1.1.0 / RuneScape Bags 2.0.3 (which reuse 7 and 8): players of those mods empty their bags with those
-- mods' "Prepare to uninstall" before switching. Tool Belt first: every character has it, and Frame Mage's hotbar
-- page 2 reads its top row, so it gets the fixed address 176-191.
local M = {}

M.GAME_PAGES = { -- the game's own, for checking a live inventory: { slotType, slots }
    { slotType = 1, slots = 32 }, -- Items
    { slotType = 2, slots = 32 }, -- Runes
    { slotType = 3, slots = 32 }, -- Ammunition
    { slotType = 4, slots = 72 }, -- Quest Items
}
M.QUICK_ACTION_SLOTS = 8 -- the hotbar, before the pages
M.LAST_GAME_SLOT_TYPE = 8 -- EInventorySlotType's last value (None); every bag page must be above it

M.PAGES = { -- appended in this order, every character, whether or not they have the bag
    { bag = "toolBelt", slotType = 9, slots = 16 },
    { bag = "herbs", slotType = 10, slots = 48 },
    { bag = "gems", slotType = 11, slots = 24 },
    { bag = "ores", slotType = 12, slots = 72 },
    { bag = "seeds", slotType = 13, slots = 64 },
    { bag = "fishing", slotType = 14, slots = 16 },
    { bag = "runeEssence", slotType = 15, slots = 8 },
}

-- Pure: the first slot index of each page and the total slot count. Unit-tested.
function M.slotRanges()
    local first = M.QUICK_ACTION_SLOTS
    for _, p in ipairs(M.GAME_PAGES) do first = first + p.slots end
    local out = {}
    for _, p in ipairs(M.PAGES) do
        out[p.bag] = { first = first, last = first + p.slots - 1, slotType = p.slotType, slots = p.slots }
        first = first + p.slots
    end
    return out, first
end

-- Pure: the slot range of the game's Items page (the backpack): right after the hotbar.
function M.itemsRange()
    return { first = M.QUICK_ACTION_SLOTS, last = M.QUICK_ACTION_SLOTS + M.GAME_PAGES[1].slots - 1 }
end

-- Pure: the inventory slot for a slot widget's (slot type, index within its page), or nil. Slot type 0 is the
-- hotbar (QuickAction). Seen in game (2026-11-13): a Tool Belt slot reports type 9 and its index on the page.
function M.absoluteSlot(slotType, index)
    if type(slotType) ~= "number" or type(index) ~= "number" or index < 0 then return nil end
    if slotType == 0 then return index < M.QUICK_ACTION_SLOTS and index or nil end
    local first = M.QUICK_ACTION_SLOTS
    for _, p in ipairs(M.GAME_PAGES) do
        if p.slotType == slotType then return index < p.slots and first + index or nil end
        first = first + p.slots
    end
    for _, p in ipairs(M.PAGES) do
        if p.slotType == slotType then return index < p.slots and first + index or nil end
        first = first + p.slots
    end
    return nil
end

-- Pure: the bag whose page holds a slot type, or nil.
function M.bagOfSlotType(slotType)
    for _, p in ipairs(M.PAGES) do if p.slotType == slotType then return p.bag end end
    return nil
end

-- Pure: the page for a bag id, or nil.
function M.page(bag)
    for _, p in ipairs(M.PAGES) do if p.bag == bag then return p end end
    return nil
end

return M
