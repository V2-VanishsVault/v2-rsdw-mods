-- Developer, read only: groundwork for moving items into and out of bag pages from the inventory screen.
-- The first time the inventory screen is open (checked every 2 s):
--   1. lists the functions (with parameters) of the classes involved: the screen's InventoryUIAPI, its
--      DragAndDropAPI and InventoryController, the inventory component, and the slot widgets
--      -> dumps/functions.txt (the type map has fields only, not functions);
--   2. hooks the drag, drop, move, split and swap functions among them, and logs each call with its
--      parameters -> dumps/drag.txt (calls are rare: one per drag or click).
-- And a key (keys.hoverProbe, Numpad +): which slot the mouse is over, read from the slot widgets'
-- bIsMousedOver and SlotPayload (InventoryIndex, OwningInventoryType) -> dumps/drag.txt.
-- Changes nothing. Off once the moves are built.
local M = {}

local INVUI = require("storagemage.inventoryui")

local ctx, log, O

local function try(fn, ...)
    local ok, v = pcall(fn, ...)
    if ok then return v end
    return nil
end

-- Pure: should a function with this name be hooked? Unit-tested.
M.HOOK_WORDS = { "Drag", "Drop", "Move", "Split", "Swap", "Transfer" }
-- Queries can run every frame (hover, paint): never hook them.
M.SKIP_PREFIXES = { "Get", "Is", "Can", "Should", "Has", "K2_Get" }
function M.wanted(name)
    if name:find("Mouse", 1, true) then return false end
    for _, p in ipairs(M.SKIP_PREFIXES) do
        if name:sub(1, #p) == p then return false end
    end
    for _, w in ipairs(M.HOOK_WORDS) do
        if name:find(w, 1, true) then return true end
    end
    return false
end

local dragLines = {}
local function drag(fmt, ...)
    dragLines[#dragLines + 1] = os.date("%H:%M:%S ") .. string.format(fmt, ...)
    if #dragLines > 400 then table.remove(dragLines, 1) end
    ctx.fs.write(ctx.dir .. "dumps/drag.txt", "# Storage Mage drag-and-drop probe\n" .. table.concat(dragLines, "\n") .. "\n")
end

local function show(v)
    local t = type(v)
    if t == "number" or t == "boolean" or t == "string" or t == "nil" then return tostring(v) end
    local s = try(function() return v:ToString() end)
    if s then return '"' .. s .. '"' end
    if O.valid(v) then
        local extra = ""
        -- Drag payloads: the slot they came from.
        local idx = O.get(v, "InventoryIndex")
        if idx ~= nil then
            extra = string.format(" {index=%s type=%s amount=%s source=%s}", tostring(idx),
                tostring(O.get(v, "OwningInventoryType")), tostring(O.get(v, "Amount")),
                (function() local s2 = O.get(v, "SourceInventory"); return O.valid(s2) and O.name(s2) or "nil" end)())
        end
        local item = O.get(v, "ItemData")
        if O.valid(item) then extra = extra .. " item=" .. O.name(item) end
        return O.className(v) .. " " .. O.name(v) .. extra
    end
    return tostring(v)
end

-- Every class from cls up, stopping at the engine's base classes.
local STOP = { Object = true, UserWidget = true, ActorComponent = true, Widget = true, CommonUserWidget = true }
local function chain(cls)
    local out = {}
    while O.valid(cls) and #out < 8 do
        local n = O.name(cls)
        if STOP[n] then break end
        out[#out + 1] = cls
        cls = try(function() return cls:GetSuperStruct() end)
    end
    return out
end

local function params(fn)
    local ps = {}
    try(function() fn:ForEachProperty(function(p)
        local pn = try(function() return p:GetFName():ToString() end) or "?"
        local pc = try(function() return p:GetClass():GetFName():ToString() end) or "?"
        ps[#ps + 1] = pc:gsub("Property$", "") .. " " .. pn
    end) end)
    return table.concat(ps, ", ")
end

M.MAX_LOGGED = 20 -- calls logged per hooked function; after that, only a count every 100
local hooked = {}
local function hook(fn)
    local full = try(function() return fn:GetFullName() end)
    if not full then return false end
    local path = full:gsub("^Function ", "")
    if hooked[path] then return true end
    local name = path:match(":([^:]+)$") or path
    local ok = pcall(function()
        local calls = 0
        RegisterHook(path, function(self, ...)
            calls = calls + 1
            if calls > M.MAX_LOGGED then
                if calls % 100 == 0 then drag("%s: %d calls", name, calls) end
                return
            end
            local args = { ... }
            local parts = {}
            for i, a in ipairs(args) do
                parts[#parts + 1] = show(try(function() return a:get() end))
                if i >= 8 then break end
            end
            local who = try(function() return self:get() end)
            drag("%s on %s (%s)", name, O.valid(who) and O.name(who) or "?", table.concat(parts, ", "))
        end)
    end)
    hooked[path] = ok
    return ok
end

local function classesOf(nav)
    local list, seen = {}, {}
    local function add(label, o)
        local cls = o and (try(function() return o:GetClass() end))
        if not O.valid(cls) then return end
        for _, c in ipairs(chain(cls)) do
            local n = O.name(c)
            if not seen[n] then seen[n] = true; list[#list + 1] = { label = label, cls = c } end
        end
    end
    local api = try(function() return FindFirstOf("InventoryUIAPI") end)
    add("InventoryUIAPI", api)
    add("DragAndDropAPI", O.get(api, "DragAndDropAPI"))
    add("InventoryController", O.get(api, "InventoryController"))
    add("PagedInventoryComponent", O.get(api, "PagedInventoryComponent"))
    local items = O.get(nav, "InventoryBody_Items")
    local slot = items and try(function() return items.InventorySlots[1] end)
    add("item slot", slot)
    add("slot payload", O.get(slot, "SlotPayload"))
    add("page body", items)
    return list
end

local function probe(nav)
    local lines = { "# Storage Mage functions (" .. os.date("%Y-%m-%d %H:%M:%S") .. ")" }
    local hookedN, failed = 0, {}
    for _, e in ipairs(classesOf(nav)) do
        lines[#lines + 1] = string.format("%s: %s", e.label, try(function() return e.cls:GetFullName() end) or "?")
        try(function() e.cls:ForEachFunction(function(fn)
            local n = try(function() return fn:GetFName():ToString() end) or "?"
            local flags = try(function() return fn:GetFunctionFlags() end)
            local mark = ""
            if M.wanted(n) then
                if hook(fn) then hookedN = hookedN + 1; mark = "  [hooked]" else failed[#failed + 1] = n; mark = "  [hook FAILED]" end
            end
            lines[#lines + 1] = string.format("  %s(%s) flags=%s%s", n, params(fn), tostring(flags), mark)
        end) end)
    end
    lines[#lines + 1] = string.format("hooked %d functions%s", hookedN,
        #failed > 0 and (", failed: " .. table.concat(failed, ", ")) or "")
    ctx.fs.write(ctx.dir .. "dumps/functions.txt", table.concat(lines, "\n") .. "\n")
    drag("probe ready: %d hooks (see functions.txt). Drag items around now.", hookedN)
end

local done = false
local function check()
    if done then return end
    local pick = INVUI.findNav()
    if not pick then return end
    done = true
    local ok, err = pcall(probe, pick.w)
    if not ok then drag("probe failed: %s", tostring(err)) end
end

-- Which slot is under the mouse: every page body's slots, then the hotbar's (InventoryUIAPI.QuickActionSlots).
local function hovered()
    local pick = INVUI.findNav()
    if not pick then drag("hover: inventory not open") return end
    local found = {}
    local function scan(label, arr)
        if not arr then return end
        try(function() arr:ForEach(function(_, e)
            local s = e:get()
            if O.valid(s) and O.get(s, "bIsMousedOver") == true then
                local p = O.get(s, "SlotPayload")
                local item = O.get(s, "ContainedItem")
                found[#found + 1] = string.format("%s: %s index=%s type=%s item=%s", label, O.name(s),
                    tostring(O.get(p, "InventoryIndex")), tostring(O.get(p, "OwningInventoryType")), show(item))
            end
        end) end)
    end
    local bodies = O.get(pick.w, "InventoryBodies")
    try(function() bodies:ForEach(function(i, e)
        local b = e:get()
        scan("page " .. i .. " (SlotType " .. tostring(O.get(b, "SlotType")) .. ")", O.get(b, "InventorySlots"))
    end) end)
    local api = try(function() return FindFirstOf("InventoryUIAPI") end)
    scan("hotbar", O.get(api, "QuickActionSlots"))
    if #found == 0 then drag("hover: no slot under the mouse") end
    for _, l in ipairs(found) do drag("hover: %s", l) end
end

function M.init(c)
    ctx, log, O = c, c.log, c.objects
    ctx.sched.every(2000, "drag probe", check)
    ctx.keys.bind(ctx.settings.keys.hoverProbe, "hoverProbe", hovered)
end

return M
