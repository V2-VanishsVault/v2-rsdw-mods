-- Developer test T1 (read-only, automatic): a timeline of when the main inventory loads its save ->
-- dumps/t1.txt. Hooks the candidate functions and polls the inventory every frame; with the pages feature on,
-- it also shows whether the inventory had the bag pages from its first appearance (pages=11, T1c).
-- The T2/T3 (Numpad *) and T6/T13 (Numpad /) write tests were retired on 2026-11-11: they added a slot type 9 page
-- that clashes with the fixed layout (storagemage/layout.lua). Their results are in design.md section 4.
local M = {}

local ctx, log, O

-- Pure (unit-tested) -------------------------------------------------------------------------------------

-- One line describing the main inventory's load state; equal lines = nothing changed.
function M.snapLine(s)
    if not s then return "no main inventory" end
    return string.format("loaded=%s pages=%s maxSlots=%s itemSlots=%s items=%s json=%s",
        tostring(s.loaded), tostring(s.pages), tostring(s.maxSlots), tostring(s.itemSlots), tostring(s.items),
        tostring(s.json))
end

-- Timeline entry: "+12.345s  <what>  <state>".
function M.timelineLine(ms, what, s)
    return string.format("+%.3fs  %-44s %s", ms / 1000, what, M.snapLine(s))
end

-- Game reads -----------------------------------------------------------------------------------------------

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

local function mainInventory()
    local pc = O.localController()
    local inv = pc and O.get(pc, "InventoryComponent")
    if O.valid(inv) then return inv end
    return nil
end

local function snapshot(inv)
    if not O.valid(inv) then return nil end
    local json = try(function() return inv.JsonInventory:ToString() end)
    return {
        loaded = O.get(inv, "bHasLoadedFromSave"),
        pages = arrayNum(try(function() return inv.InventoryPages end)),
        maxSlots = O.get(inv, "MaxSlotCount"),
        itemSlots = arrayNum(try(function() return inv.ItemSlots end)),
        items = try(function() return inv:GetNumItems() end),
        json = json and #json or nil,
    }
end

-- T1: load timeline ------------------------------------------------------------------------------------------

local t1 = { lines = {}, start = nil, last = nil, max = 400 }

-- os.clock() on Windows (MSVC) is wall time since the process started, not CPU time: right for a timeline.
local function nowMs() return math.floor(os.clock() * 1000) end

local function t1write()
    local text = "# Storage Mage T1: when the main inventory loads its save (" .. os.date("%Y-%m-%d %H:%M:%S") .. ")\n"
        .. "# Times are from Storage Mage's start. 'hook' lines name the function that fired (pre = before it ran,\n"
        .. "# post = after); 'poll' lines are changes seen by a per-frame poll; 'new player inventory' is the\n"
        .. "# component one tick after it was created.\n\n"
        .. table.concat(t1.lines, "\n") .. "\n"
    ctx.fs.write(ctx.dir .. "dumps/t1.txt", text)
end

local function t1record(what, s)
    if #t1.lines >= t1.max then return end
    t1.lines[#t1.lines + 1] = M.timelineLine(nowMs() - t1.start, what, s)
    if #t1.lines == t1.max then t1.lines[#t1.lines + 1] = "(timeline full: later changes not recorded)" end
    t1write()
end

-- Is this hooked object the local player's main inventory (not a chest's)?
local function isPlayerMain(obj)
    local name = try(function() return obj:GetFullName() end) or ""
    return name:find("PlayerController", 1, true) ~= nil and name:find("BP_Components_Inventory", 1, true) ~= nil
end

local HOOKS = {
    { fn = "/Script/Dominion.DominionPlayerController:OnInventoryLoadedFromSave" },
    { fn = "/Script/Dominion.InventoryComponent:OnRep_HasLoadedFromSave", filter = true },
    { fn = "/Script/Dominion.InventoryComponent:OnRep_ItemSlots", filter = true, limit = 5 },
}

local function hookAll()
    if RegisterHook == nil then
        t1.lines[#t1.lines + 1] = "RegisterHook is not available on this UE4SS build"
        return
    end
    for _, h in ipairs(HOOKS) do
        local count = 0
        local short = h.fn:match(":(.+)$") or h.fn
        local function cb(phase)
            return ctx.sched.safe("t1 hook " .. short, function(self)
                if h.filter and not isPlayerMain(try(function() return self:get() end)) then return end
                if phase == "pre" then count = count + 1 end
                if h.limit and count > h.limit then return end
                t1record("hook " .. phase .. " " .. short, snapshot(mainInventory()))
            end)
        end
        local ok, err = pcall(RegisterHook, h.fn, cb("pre"), cb("post"))
        t1.lines[#t1.lines + 1] = string.format("hook %s: %s", short, ok and "registered" or ("NOT registered: " .. tostring(err)))
    end
end

-- T1b: catch every new inventory component as it's made (NotifyOnNewObject on the base class also fires for
-- Blueprint subclasses, as Frame Mage's UserWidget subscription shows). Fields aren't set at construction, so
-- look one tick later, and only at the player's main inventory. Objects are queued, never kept past that tick.
local pendingNew = {}

local function watchNew()
    if NotifyOnNewObject == nil then return end
    local ok, err = pcall(NotifyOnNewObject, "/Script/Dominion.InventoryComponent", function(obj)
        pendingNew[#pendingNew + 1] = obj
        if #pendingNew == 1 then
            ctx.sched.now("t1 new inventory", function()
                local list = pendingNew
                pendingNew = {}
                for _, o in ipairs(list) do
                    if O.valid(o) and isPlayerMain(o) then t1record("new player inventory (+1 tick)", snapshot(o)) end
                end
            end)
        end
    end)
    t1.lines[#t1.lines + 1] = "new-object watch on InventoryComponent: " .. (ok and "on" or ("FAILED: " .. tostring(err)))
end

local function t1poll()
    local s = snapshot(mainInventory())
    local line = M.snapLine(s)
    if line ~= t1.last then
        t1.last = line
        t1record("poll", s)
    end
end

function M.init(c)
    ctx, log, O = c, c.log, c.objects
    t1.start = nowMs()
    hookAll()
    watchNew()
    t1write()
    -- Every frame: in the first run a world's inventory was already loaded at the 100 ms poll.
    ctx.sched.every(16, "t1 poll", t1poll)
end

return M
