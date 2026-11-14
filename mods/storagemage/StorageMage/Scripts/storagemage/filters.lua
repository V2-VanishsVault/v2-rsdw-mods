-- Which bag an item belongs to, and each bag page's filter tag. Pure: no game calls, unit-tested.
--
-- A bag page's filter (set by features/pages.lua) asks for one gameplay tag, ItemFilter.StorageMage.<Bag>.
-- features/tags.lua adds that tag to the ItemFilterTags of every item definition (ItemData) belonging to the
-- bag, so the game lets those items into the page, including when it puts saved items back on load.
local M = {}

M.TAG_PREFIX = "ItemFilter.StorageMage."

-- toolBelt -> ItemFilter.StorageMage.ToolBelt
function M.tagFor(bag)
    return M.TAG_PREFIX .. bag:sub(1, 1):upper() .. bag:sub(2)
end

-- Does tag `t` equal `parent` or sit under it? ("Item.Equipment.Tool.Hatchet" is under "Item.Equipment.Tool".)
function M.under(t, parent)
    if type(t) ~= "string" or type(parent) ~= "string" then return false end
    return t == parent or t:sub(1, #parent + 1) == parent .. "."
end

-- The bag an item belongs to, or nil. `bags` is settings.bags ({ id = { categories, items } }); `active` limits
-- it to the bags currently switched on ({ id = true }), or all when nil. Item lists win over categories, and bags
-- are checked in a fixed order (layout order) so the answer never depends on table order.
function M.bagFor(category, asset, bags, order, active)
    for _, id in ipairs(order) do
        local b = bags[id]
        if b and (active == nil or active[id]) then
            for _, a in ipairs(b.items or {}) do if a == asset then return id end end
        end
    end
    for _, id in ipairs(order) do
        local b = bags[id]
        if b and (active == nil or active[id]) then
            for _, c in ipairs(b.categories or {}) do if M.under(category, c) then return id end end
        end
    end
    return nil
end

-- "ItemData /Game/Gameplay/Items/X/ITEM_Y.ITEM_Y" (GetFullName) -> "/Game/Gameplay/Items/X/ITEM_Y.ITEM_Y"
function M.pathFromFullName(full)
    if type(full) ~= "string" then return nil end
    local p = full:match("^%S+%s+(/%S+)$")
    return p
end

-- The remembered item paths file: one "<bag> <path>" per line, '#' comments. Returns { path = bag }.
function M.parsePaths(text)
    local out = {}
    for line in (text or ""):gmatch("[^\r\n]+") do
        local bag, path = line:match("^(%w+)%s+(/%S+)$")
        if bag then out[path] = bag end
    end
    return out
end

function M.formatPaths(paths)
    local keys = {}
    for p in pairs(paths) do keys[#keys + 1] = p end
    table.sort(keys)
    local lines = { "# Storage Mage: bag item definitions seen in play, loaded at the main menu so their filter tags",
        "# are in place before a save is read. Rebuilt automatically; safe to delete." }
    for _, p in ipairs(keys) do lines[#lines + 1] = paths[p] .. " " .. p end
    return table.concat(lines, "\n") .. "\n"
end

return M
