-- Developer dump (Numpad -): the local player's inventories -> dumps/inventory.txt, and every loaded item
-- definition by category -> dumps/items.txt (for the bag item lists).
-- Read-only. It answers design tests T1-T3 and T5: the main inventory's class and pages (slot type, slot count),
-- slot counts, what JsonInventory holds, and each item's category and filter tags (for the bag tag table).
local M = {}

local ctx, log
local O

-- Pure (unit-tested) -------------------------------------------------------------------------------------

M.SLOT_TYPES = { [0] = "QuickAction", "InventoryItems", "InventoryRunes", "InventoryAmmunition",
    "InventoryQuestItems", "Loadout", "External", "FishingBaits", "None" }

function M.slotTypeName(n)
    if type(n) ~= "number" then return tostring(n) end
    return M.SLOT_TYPES[n] or ("#" .. n)
end

-- One line per item: "  [slot] count x name (asset)  category=...  tags=a,b"
-- The asset name (the ItemData object's name) is what bag filters list: it doesn't change with the language.
function M.itemLine(slot, count, name, category, tags, asset)
    local t = (tags and #tags > 0) and table.concat(tags, ",") or "-"
    return string.format("  [%d] %s x %s%s  category=%s  tags=%s", slot, tostring(count), tostring(name),
        asset and (" (" .. asset .. ")") or "", tostring(category or "-"), t)
end

-- Distinct categories with how many slots use each, sorted by name: for filling in the bag tag table.
function M.categorySummary(items)
    local n = {}
    for _, it in ipairs(items) do
        local c = it.category or "-"
        n[c] = (n[c] or 0) + 1
    end
    local keys = {}
    for k in pairs(n) do keys[#keys + 1] = k end
    table.sort(keys)
    local out = {}
    for _, k in ipairs(keys) do out[#out + 1] = string.format("  %s (%d)", k, n[k]) end
    return out
end

-- The item catalog (dumps/items.txt): every loaded item definition, grouped by category, so the bag item lists
-- can be filled in without carrying every item. entries = { { asset, name, category, weight, stack, class } }.
-- Duplicate assets (the same definition found through two class queries) are listed once.
function M.catalogLines(entries)
    local seen, byCat = {}, {}
    for _, e in ipairs(entries) do
        local a = e.asset or "?"
        if not seen[a] then
            seen[a] = true
            local c = e.category or "-"
            byCat[c] = byCat[c] or {}
            table.insert(byCat[c], e)
        end
    end
    local cats = {}
    for c in pairs(byCat) do cats[#cats + 1] = c end
    table.sort(cats)
    local out = {}
    for _, c in ipairs(cats) do
        local list = byCat[c]
        table.sort(list, function(x, y) return (x.asset or "") < (y.asset or "") end)
        out[#out + 1] = string.format("%s (%d)", c, #list)
        for _, e in ipairs(list) do
            out[#out + 1] = string.format("  %s  \"%s\"  weight=%s  stack=%s  class=%s", e.asset or "?",
                tostring(e.name or "?"), tostring(e.weight or "?"), tostring(e.stack or "?"), tostring(e.class or "?"))
        end
    end
    return out, #cats
end

-- Game reads (each wrapped: a missing field or function logs "?" instead of failing) ----------------------

local function try(fn, ...)
    local ok, v = pcall(fn, ...)
    if ok then return v end
    return nil
end

local function str(v)
    if v == nil then return nil end
    local s = try(function() return v:ToString() end)
    if s then return s end
    return tostring(v)
end

local function tagName(tag)
    return try(function() return tag.TagName:ToString() end)
end

local function tagList(container)
    local out = {}
    try(function()
        container.GameplayTags:ForEach(function(_, elem)
            local n = tagName(elem:get())
            if n then out[#out + 1] = n end
        end)
    end)
    return out
end

local function dumpInventory(lines, label, inv, items)
    if not O.valid(inv) then
        lines[#lines + 1] = label .. ": (none)"
        lines[#lines + 1] = ""
        return
    end
    lines[#lines + 1] = string.format("%s: %s  %s", label, O.className(inv), tostring(try(function() return inv:GetFullName() end)))
    lines[#lines + 1] = string.format("  MaxSlotCount=%s  NumberOfQuickActionSlots=%s  bHasLoadedFromSave=%s  items=%s  emptySlots=%s",
        tostring(O.get(inv, "MaxSlotCount")), tostring(O.get(inv, "NumberOfQuickActionSlots")),
        tostring(O.get(inv, "bHasLoadedFromSave")), tostring(try(function() return inv:GetNumItems() end)),
        tostring(try(function() return inv:GetNumEmptySlots() end)))
    local w = try(function() return inv:ComputeCurrentWeight() end)
    lines[#lines + 1] = "  weight=" .. tostring(w)
    try(function()
        inv.InventoryPages:ForEach(function(i, elem)
            local p = elem:get()
            lines[#lines + 1] = string.format("  page %d: SlotType=%s NumSlots=%s", i, M.slotTypeName(try(function() return p.SlotType end)),
                tostring(try(function() return p.NumSlots end)))
        end)
    end)
    try(function()
        inv.ItemWeightModifier:ForEach(function(i, elem)
            local m = elem:get()
            lines[#lines + 1] = string.format("  weight modifier %d: tag=%s x%s", i, tostring(tagName(m.WeightReductionTag)),
                tostring(try(function() return m.Multiplier end)))
        end)
    end)
    local json = str(O.get(inv, "JsonInventory"))
    lines[#lines + 1] = string.format("  JsonInventory: %d chars%s", json and #json or 0,
        (json and #json > 0) and (": " .. json:sub(1, 400)) or "")
    try(function()
        inv.ItemSlots:ForEach(function(i, elem)
            local item = elem:get()
            if O.valid(item) then
                local data = try(function() return item.ItemData end)
                local name = data and (str(try(function() return data:GetName() end)) or O.name(data)) or "?"
                local category = data and tagName(try(function() return data:GetCategory() end))
                local tags = data and tagList(try(function() return data:GetItemFilterTags() end)) or {}
                local asset = data and try(function() return O.name(data) end)
                lines[#lines + 1] = M.itemLine(i - 1, try(function() return item.Count end), name, category, tags, asset)
                items[#items + 1] = { category = category }
            end
        end)
    end)
    lines[#lines + 1] = ""
end

-- Every way of asking "is this the server?", raw, to settle design test T19.
function M.netChecks(pc)
    local ksl = StaticFindObject("/Script/Engine.Default__KismetSystemLibrary")
    local parts = {}
    local function add(label, fn)
        local ok, v = pcall(fn)
        parts[#parts + 1] = label .. "=" .. (ok and tostring(v) or "error")
    end
    add("pc:HasAuthority", function() return pc:HasAuthority() end)
    add("pc.Role", function() return pc.Role end)
    add("pc:IsLocalController", function() return pc:IsLocalController() end)
    add("ksl:IsServer(pc)", function() return ksl:IsServer(pc) end)
    add("ksl:IsDedicatedServer(pc)", function() return ksl:IsDedicatedServer(pc) end)
    add("ksl:IsStandalone(pc)", function() return ksl:IsStandalone(pc) end)
    add("GameModeBase", function() return O.valid(FindFirstOf("GameModeBase")) end)
    return table.concat(parts, "  ")
end

-- ItemData and its script subclasses (from the type map). FindAllOf should already return subclasses (Frame Mage
-- relies on that for UserWidget); querying them too covers the case where it doesn't, and catalogLines dedupes.
M.ITEM_DATA_CLASSES = { "ItemData", "BuffItemData", "BuildableItemData", "ConsumableItemData", "CraftableItemData",
    "DrinkItemData", "FoodItemData", "FuelItemData", "JournalItemData", "PotionItemData", "TrinketItemData",
    "WardstoneItemData", "WhetstoneItemData" }

-- Only definitions the game has loaded are found; the count goes in the file header so gaps are visible.
local function collectItemData()
    local entries = {}
    for _, cls in ipairs(M.ITEM_DATA_CLASSES) do
        for _, d in pairs(try(function() return FindAllOf(cls) end) or {}) do
            local asset = try(function() return O.name(d) end)
            -- Skip class default objects: they are templates, not items.
            if asset and not asset:find("^Default__") and O.valid(d) then
                entries[#entries + 1] = {
                    asset = asset,
                    name = str(try(function() return d.Name end)),
                    category = tagName(try(function() return d:GetCategory() end)),
                    weight = try(function() return d.Weight end),
                    stack = try(function() return d.MaxStackSize end),
                    class = try(function() return O.className(d) end),
                }
            end
        end
    end
    return entries
end

local function dumpCatalog()
    local entries = collectItemData()
    local body, ncat = M.catalogLines(entries)
    local seen, n = {}, 0
    for _, e in ipairs(entries) do if not seen[e.asset] then seen[e.asset] = true; n = n + 1 end end
    local lines = { "# Storage Mage item catalog " .. os.date("%Y-%m-%d %H:%M:%S"),
        string.format("# %d loaded item definitions in %d categories (definitions the game hasn't loaded are missing)", n, ncat), "" }
    for _, l in ipairs(body) do lines[#lines + 1] = l end
    local ok, err = ctx.fs.write(ctx.dir .. "dumps/items.txt", table.concat(lines, "\n") .. "\n")
    if not ok then log.error("item catalog failed: %s", tostring(err)) end
    return ok and n or nil
end

function M.dump()
    local pc = O.localController()
    if not pc then
        ctx.toast.show("no player yet - load a world, then press the key again")
        return
    end
    local lines = { "# Storage Mage inventory dump " .. os.date("%Y-%m-%d %H:%M:%S"),
        "# net role: " .. tostring(O.netRole()), "# net checks: " .. M.netChecks(pc), "" }
    local items = {}
    dumpInventory(lines, "InventoryComponent", O.get(pc, "InventoryComponent"), items)
    dumpInventory(lines, "LoadoutComponent", O.get(pc, "LoadoutComponent"), items)
    dumpInventory(lines, "PersonalInventoryComponent", O.get(pc, "PersonalInventoryComponent"), items)
    lines[#lines + 1] = "Categories:"
    for _, l in ipairs(M.categorySummary(items)) do lines[#lines + 1] = l end
    local path = ctx.dir .. "dumps/inventory.txt"
    local ok, err = ctx.fs.write(path, table.concat(lines, "\n") .. "\n")
    local nItems = dumpCatalog()
    if ok then
        ctx.toast.show(string.format("inventory dump written (%d stacks); item catalog: %s definitions", #items,
            nItems and tostring(nItems) or "failed"))
    else
        log.error("inventory dump failed: %s", tostring(err))
        ctx.toast.show("inventory dump failed - see UE4SS.log")
    end
end

function M.init(c)
    ctx, log, O = c, c.log, c.objects
    ctx.keys.bind(ctx.settings.keys.dumpInventory, "dumpInventory", M.dump)
end

return M
