-- Bag pages (design 2.1, Plan A; test T1c). Adds Storage Mage's fixed page layout (storagemage/layout.lua) to the
-- player inventory's TEMPLATE, the controller Blueprint's default sub-object, before any player exists. Every
-- inventory the game spawns afterwards already has the pages, so a save loads straight into them (there is no
-- tick between a live inventory's creation and its save landing: T1 run 2). Runs on the server, the host and
-- clients alike: every side must have the same layout.
--
-- Technique learned from Tool Belt 1.1.0 / RuneScape Bags 2.0.3 (Maxxfilth; no licence, so our own code):
-- grow the page array with an empty element first, then copy the Runes page into it, then set its fields.
--
-- Filters: each page's query is the Runes page's copy with its one tag renamed to "ItemFilter.StorageMage.<Bag>".
-- No item carries those tags yet (pickup routing comes later), so for now the pages accept nothing and nothing
-- can land in them by accident.
--
-- Report: dumps/pages.txt (what was patched, and each world's live inventory check).
local M = {}

local L = require("storagemage.layout")
local F = require("storagemage.filters")

local ctx, log, O

M.TEMPLATE = "/Game/Gameplay/Character/Player/BP_PlayerController.BP_PlayerController_C:BP_Components_Inventory_GEN_VARIABLE"
M.CONFLICTS = { "ToolBelt", "RuneScapeBags" } -- mods that add pages of their own to the same inventory

-- Pure (unit-tested) -------------------------------------------------------------------------------------

-- The filter tag of a bag page: toolBelt -> ItemFilter.StorageMage.ToolBelt (one definition, in filters.lua).
M.tagFor = F.tagFor

-- What to do with an inventory's pages ({ {slotType, numSlots}, ... }):
--   { action = "patch", from = <first layout index to add> }   the game's pages, plus 0 or more of ours in order
--   { action = "done" }                                        exactly the game's pages + our whole layout
--   { action = "refuse", reason = "..." }                      anything else (another mod, a changed game)
function M.plan(pages)
    if type(pages) ~= "table" then return { action = "refuse", reason = "no pages" } end
    for i, g in ipairs(L.GAME_PAGES) do
        local p = pages[i]
        if not p or p.slotType ~= g.slotType or p.numSlots ~= g.slots then
            return { action = "refuse", reason = string.format("the game's page %d isn't SlotType %d / %d slots", i,
                g.slotType, g.slots) }
        end
    end
    local n = #L.GAME_PAGES
    for i = n + 1, #pages do
        local want, p = L.PAGES[i - n], pages[i]
        if not want then return { action = "refuse", reason = "more pages than Storage Mage's layout (another inventory mod?)" } end
        if p.slotType ~= want.slotType or p.numSlots ~= want.slots then
            return { action = "refuse", reason = string.format("page %d is SlotType %s / %s slots, not %s's %d / %d "
                .. "(another inventory mod?)", i, tostring(p.slotType), tostring(p.numSlots), want.bag, want.slotType,
                want.slots) }
        end
    end
    if #pages == n + #L.PAGES then return { action = "done" } end
    return { action = "patch", from = #pages - n + 1 }
end

-- The slot count the pages need: hotbar + every page.
function M.needSlots(pages)
    local total = L.QUICK_ACTION_SLOTS
    for _, p in ipairs(pages) do total = total + (p.numSlots or 0) end
    return total
end

-- Game side ------------------------------------------------------------------------------------------------

local function try(fn, ...)
    local ok, v = pcall(fn, ...)
    if ok then return v end
    return nil
end

local function arrayNum(arr)
    if arr == nil then return nil end
    local n = try(function() return arr:GetArrayNum() end)
    if n == nil then n = try(function() return #arr end) end
    return n
end

local function readPages(inv)
    local out = {}
    local ok = pcall(function()
        inv.InventoryPages:ForEach(function(_, elem)
            local p = elem:get()
            out[#out + 1] = { slotType = try(function() return p.SlotType end),
                numSlots = try(function() return p.NumSlots end),
                tag = try(function() return p.AllowedItemFilter.TagDictionary[1].TagName:ToString() end) }
        end)
    end)
    if not ok then return nil end
    return out
end

local report = {}
local function note(fmt, ...)
    local line = string.format(fmt, ...)
    report[#report + 1] = line
    log.info("pages: %s", line)
    ctx.fs.write(ctx.dir .. "dumps/pages.txt", "# Storage Mage bag pages (" .. os.date("%Y-%m-%d %H:%M:%S") .. ")\n"
        .. table.concat(report, "\n") .. "\n")
end

local state = { patched = false, refused = nil, conflict = nil }

-- Another page-adding mod installed (its Lua folder present)? Both would patch the same template.
local function conflictingMod()
    for _, name in ipairs(M.CONFLICTS) do
        if ctx.fs.exists(ctx.dir .. "../" .. name .. "/Scripts/main.lua") then return name end
    end
    return nil
end

-- Add one layout page at array index i. Returns true, or false + why (the page is then left with 0 slots).
local function addPage(t, i, spec)
    local pages = t.InventoryPages
    local okGrow, err = pcall(function() pages[i] = { NumSlots = 0 } end)
    if not okGrow or arrayNum(t.InventoryPages) ~= i then
        return false, "could not grow the page array: " .. tostring(err)
    end
    local ok, e = pcall(function()
        t.InventoryPages[i] = t.InventoryPages[2] -- the Runes page: a one-tag query to rename
        local p = t.InventoryPages[i]
        p.SlotType = spec.slotType
        p.NumSlots = spec.slots
        p.AllowedItemFilter.TagDictionary[1].TagName = FName(M.tagFor(spec.bag))
    end)
    local got = readPages(t)
    local p = got and got[i]
    if ok and p and p.slotType == spec.slotType and p.numSlots == spec.slots and p.tag == M.tagFor(spec.bag) then
        return true
    end
    pcall(function() t.InventoryPages[i].NumSlots = 0 end) -- never leave a second Runes page behind
    return false, ok and string.format("read back SlotType=%s NumSlots=%s tag=%s", tostring(p and p.slotType),
        tostring(p and p.numSlots), tostring(p and p.tag)) or tostring(e)
end

local function setMaxSlots(t, need)
    local have = O.get(t, "MaxSlotCount")
    if have and have >= need then return true end
    pcall(function() t.MaxSlotCount = need end)
    if O.get(t, "MaxSlotCount") ~= need then pcall(function() t:SetPropertyValue("MaxSlotCount", need) end) end
    return O.get(t, "MaxSlotCount") == need
end

-- Patch the template once. Returns "done", "notyet" (template not loaded), or "refused".
function M.patchTemplate(why)
    if state.patched then return "done" end
    if state.refused then return "refused" end
    local other = conflictingMod()
    if other then
        state.refused = other .. " is installed"
        note("NOT patched: the %s mod is installed and adds its own pages to the same inventory. Remove it (empty its "
            .. "bags first) or remove Storage Mage.", other)
        return "refused"
    end
    local t = try(function() return StaticFindObject(M.TEMPLATE) end)
    if not O.valid(t) then return "notyet" end

    local pages = readPages(t)
    local plan = M.plan(pages)
    if plan.action == "refuse" then
        state.refused = plan.reason
        note("NOT patched (%s): %s", why, plan.reason)
        return "refused"
    end
    if plan.action == "patch" then
        local base = #L.GAME_PAGES
        for k = plan.from, #L.PAGES do
            local spec = L.PAGES[k]
            local ok, err = addPage(t, base + k, spec)
            if not ok then
                state.refused = "page " .. spec.bag .. " failed"
                note("FAILED adding page %d (%s, SlotType %d): %s. Later pages not added.", base + k, spec.bag,
                    spec.slotType, tostring(err))
                return "refused"
            end
        end
    end
    local need = M.needSlots(readPages(t) or {})
    if not setMaxSlots(t, need) then
        state.refused = "MaxSlotCount"
        note("FAILED: template MaxSlotCount is %s, need %d", tostring(O.get(t, "MaxSlotCount")), need)
        return "refused"
    end
    state.patched = true
    note("template patched (%s): %d pages, MaxSlotCount %s", why, arrayNum(t.InventoryPages) or -1,
        tostring(O.get(t, "MaxSlotCount")))
    return "done"
end

-- Each world: does the live inventory have the layout? (T1c's answer.)
local checkedFor, uiCheckedFor = nil, nil
local function checkLive()
    if not state.patched then return end
    local pc = O.localController()
    local inv = pc and O.get(pc, "InventoryComponent")
    if not O.valid(inv) or O.get(inv, "bHasLoadedFromSave") ~= true then return end
    local id = try(function() return inv:GetFullName() end)
    if id == checkedFor then
        -- The inventory screen's API only exists once the inventory has been opened: report it then.
        if uiCheckedFor ~= id then
            local api = try(function() return FindFirstOf("InventoryUIAPI") end)
            if O.valid(api) then
                uiCheckedFor = id
                local tbType = L.page("toolBelt").slotType
                note("  inventory opened: UI Tool Belt slots=%s, UI Ores slots=%s", tostring(arrayNum(try(function()
                    return api:GetInventorySlots(tbType) end))), tostring(arrayNum(try(function()
                    return api:GetInventorySlots(L.page("ores").slotType) end))))
            end
        end
        return
    end
    checkedFor = id
    local pages = readPages(inv) or {}
    local ranges, total = L.slotRanges()
    local tb = ranges.toolBelt
    note("live inventory (%s): plan=%s pages=%d MaxSlotCount=%s ItemSlots=%s items=%s", tostring(O.netRole()),
        M.plan(pages).action, #pages, tostring(O.get(inv, "MaxSlotCount")),
        tostring(arrayNum(try(function() return inv.ItemSlots end))), tostring(try(function() return inv:GetNumItems() end)))
    note("  want %d slots; IsValidSlotIndex(%d)=%s (%d)=%s; Tool Belt free slots=%s (want %d)", total,
        total - 1, tostring(try(function() return inv:IsValidSlotIndex(total - 1) end)), total,
        tostring(try(function() return inv:IsValidSlotIndex(total) end)),
        tostring(try(function() return inv:GetFreeSlotCountFromSlotType(tb.slotType) end)), tb.slots)
    for i, p in ipairs(pages) do
        if i > #L.GAME_PAGES then
            note("  page %d: SlotType=%s NumSlots=%s tag=%s", i, tostring(p.slotType), tostring(p.numSlots), tostring(p.tag))
        end
    end
end

function M.init(c)
    ctx, log, O = c, c.log, c.objects
    local function attempt(why) return function() M.patchTemplate(why) end end
    pcall(M.patchTemplate, "script load")
    if RegisterInitGameStatePostHook then
        pcall(RegisterInitGameStatePostHook, ctx.sched.safe("pages init-game-state", attempt("InitGameState")))
    end
    if RegisterLoadMapPostHook then
        pcall(RegisterLoadMapPostHook, ctx.sched.safe("pages load-map", attempt("LoadMap")))
    end
    -- Until patched (the template's Blueprint loads after the mod), retry each second; then check each world.
    ctx.sched.every(1000, "pages tick", function()
        if not state.patched and not state.refused then M.patchTemplate("retry") end
        checkLive()
    end)
end

return M
