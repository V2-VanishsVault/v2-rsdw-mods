-- Drag and drop inside the Tool Belt page. The game starts its own drag on a belt item, but then switches the
-- screen to the Items page, and a drop back on a belt slot does nothing (both seen 2026-11-14, dev beltprobe).
-- The game's drag functions are called natively, so Lua hooks never see them; what Lua can read is the drag
-- API's CurrentDragPayload (set to the dragged slot the moment a drag starts, cleared on release) and each slot's
-- bIsMousedOver. So while a belt item is dragged: the page is put back on the Tool Belt, the belt slot under the
-- mouse is followed, and on release the item is moved there by bagmoves (moved, stacked or swapped).
--
-- Nothing runs until the Tool Belt tab is on screen, and then only a few seconds later: a developer probe that
-- polled from the start crashed the game on entering the world (four times, 2026-11-14).
local M = {}

local L = require("storagemage.layout")

local ctx, log, O
local function try(fn, ...)
    local ok, v = pcall(fn, ...)
    if ok then return v end
    return nil
end

M.START_DELAY_MS = 5000 -- after the Tool Belt tab is built
M.POLL_MS = 50          -- while watching: reading three properties (more only during a drag)
M.FIND_MS = 2000        -- the inventory UI API, looked up again

local nav, api, beltBody, beltIndex
local watching, started = false, false
local drag -- { from = absolute slot, over = absolute slot or nil }

local function findBelt(n)
    local beltType = L.page("toolBelt").slotType
    local body
    try(function() O.get(n, "InventoryBodies"):ForEach(function(_, e)
        local b = e:get()
        if not body and O.valid(b) and O.get(b, "SlotType") == beltType then body = b end
    end) end)
    if not body then return nil end
    local switcher = O.get(n, "InventorySwitcher")
    local index = try(function() return switcher:GetChildIndex(body) end)
    if type(index) ~= "number" or index < 0 then index = ctx.features.belttab and ctx.features.belttab.GAME_TABS or 4 end
    return body, index
end

-- The belt slot under the mouse (absolute), or nil.
local function overBelt()
    local found
    try(function() beltBody.InventorySlots:ForEach(function(_, se)
        if found then return end
        local s = se:get()
        if O.valid(s) and O.get(s, "bIsMousedOver") == true then
            local p = O.get(s, "SlotPayload")
            found = L.absoluteSlot(O.get(p, "OwningInventoryType"), O.get(p, "InventoryIndex"))
        end
    end) end)
    return found
end

local function keepBeltPage()
    local switcher = O.get(nav, "InventorySwitcher")
    local page = try(function() return switcher:GetActiveWidgetIndex() end)
    if page ~= nil and page ~= beltIndex then
        local ok, err = pcall(function() switcher:SetActiveWidgetIndex(beltIndex) end)
        if not ok then log.debug("beltdrag: page back failed: %s", tostring(err)) end
    end
end

-- The page switched back leaves the Items tab lit (2026-11-14), so on release the Tool Belt tab is clicked through
-- the tab group, by its radio value (an int: RuneScape Bags / Tool Belt 1.0.0 switch tabs the same way). Not during
-- the drag: a tab click might end it.
local function selectBeltTab()
    local group = O.get(nav, "CategoryButtonGroup")
    if not O.valid(group) then return end
    local ok, err = pcall(function() group:HandleClick(beltIndex) end)
    if not ok then log.info("beltdrag: tab click failed: %s", tostring(err)) end
end

local function payload()
    local dd = api and O.valid(api) and O.get(api, "DragAndDropAPI")
    local p = dd and O.valid(dd) and O.get(dd, "CurrentDragPayload")
    if not (p and O.valid(p)) then return nil end
    return L.absoluteSlot(O.get(p, "OwningInventoryType"), O.get(p, "InventoryIndex")), O.get(p, "OwningInventoryType")
end

local function poll()
    if not (watching and nav and O.valid(nav) and beltBody and O.valid(beltBody)) then drag = nil return end
    local from, slotType = payload()
    local fromBelt = from ~= nil and slotType == L.page("toolBelt").slotType
    if fromBelt then
        if not drag or drag.from ~= from then drag = { from = from } end
        keepBeltPage()
        drag.over = overBelt()
        return
    end
    if drag then -- released (or the drag turned into something else)
        local d = drag
        drag = nil
        selectBeltTab()
        if d.over and d.over ~= d.from then
            log.info("beltdrag: slot %d -> %d", d.from, d.over)
            ctx.features.bagmoves.dragMove(d.from, d.over)
        end
    end
end

local function stop()
    watching, nav, api, beltBody, drag = false, nil, nil, nil, nil
end

local function watch(n)
    if not O.valid(n) then return end
    local body, index = findBelt(n)
    if not body then log.info("beltdrag: no Tool Belt page on this screen") return end
    nav, beltBody, beltIndex = n, body, index
    api = try(function() return FindFirstOf("InventoryUIAPI") end)
    watching = true
    log.info("beltdrag: watching (Tool Belt page %d)", beltIndex)
    if started then return end
    started = true
    ctx.sched.every(M.FIND_MS, "belt drag find", function()
        if watching and not (api and O.valid(api)) then api = try(function() return FindFirstOf("InventoryUIAPI") end) end
    end)
    ctx.sched.every(M.POLL_MS, "belt drag", function()
        local ok, err = pcall(poll)
        if not ok then drag = nil; log.debug("beltdrag: %s", tostring(err)) end
    end)
end

function M.init(c)
    ctx, log, O = c, c.log, c.objects
    if not (ctx.features.bagmoves and ctx.features.bagmoves.dragMove) then -- (started before this one)
        log.info("beltdrag: needs bagmoves, which isn't running")
        return
    end
    ctx.events.on("belttab", function(n)
        stop()
        ctx.sched.later(M.START_DELAY_MS, "belt drag start", function() pcall(watch, n) end)
    end)
    ctx.events.on("worldchanged", stop)
end

return M
