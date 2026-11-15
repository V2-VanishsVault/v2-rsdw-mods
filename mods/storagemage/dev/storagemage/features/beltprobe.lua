-- Developer, read only: what a click or drag on a Tool Belt item sets off, before Storage Mage does drag and drop
-- inside the Tool Belt itself (the game's own click-to-move switches to the Items page and drops nothing).
-- Switched on in the world with numpad *. Logs the left mouse button as the player controller sees it, and while the
-- inventory screen is open, every change of: the slot under the mouse, the page shown and the tabs checked, the
-- slots marked selected, and the drag API's current payload -> dumps/belt-drag.txt. Hooks nothing. One change, an
-- experiment: while a Tool Belt item is dragged, the page is switched back to the Tool Belt (keepBeltPage).
local M = {}

local INVUI = require("storagemage.inventoryui")
local L = require("storagemage.layout")

local ctx, O
local lines = {}

local function try(fn, ...)
    local ok, v = pcall(fn, ...)
    if ok then return v end
    return nil
end

local function out(fmt, ...)
    lines[#lines + 1] = os.date("%H:%M:%S ") .. string.format(fmt, ...)
    if #lines > 600 then table.remove(lines, 1) end
    ctx.fs.write(ctx.dir .. "dumps/belt-drag.txt", "# Storage Mage: Tool Belt clicks and drags\n" .. table.concat(lines, "\n") .. "\n")
end

-- The slot under the mouse: "<body> type <t> index <i> (absolute <a>)", or "none".
local function hovered(nav)
    local found = "none"
    try(function() O.get(nav, "InventoryBodies"):ForEach(function(_, e)
        local body = e:get()
        try(function() body.InventorySlots:ForEach(function(_, se)
            local s = se:get()
            if O.valid(s) and O.get(s, "bIsMousedOver") == true then
                local p = O.get(s, "SlotPayload")
                local t, i = O.get(p, "OwningInventoryType"), O.get(p, "InventoryIndex")
                found = string.format("%s type %s index %s (absolute %s)", O.name(body), tostring(t), tostring(i),
                    tostring(L.absoluteSlot(t, i)))
            end
        end) end)
    end) end)
    return found
end

local function screenState(nav)
    local switcher = O.get(nav, "InventorySwitcher")
    local page = try(function() return switcher:GetActiveWidgetIndex() end)
    local group = O.get(nav, "CategoryButtonGroup")
    local checked = {}
    try(function() O.get(group, "RadioButtons"):ForEach(function(i, e)
        local b = e:get()
        local on = try(function() return b:IsChecked() end) or try(function() return b:GetCheckedState() end)
        checked[#checked + 1] = string.format("%s=%s", tostring(O.get(b, "RadioValue") or i), tostring(on))
    end) end)
    -- (IsChecked/GetCheckedState read nil on these tabs, 2026-11-14; kept in case another call works)
    return string.format("page %s; tabs %s", tostring(page), table.concat(checked, " ")), page
end

-- Experiment (2026-11-14 run: a belt drag sets DragAndDropAPI.CurrentDragPayload to the belt slot, type 9, the
-- moment it starts, and the switcher jumps to page 0, Items, at the same moment): while a belt item is dragged,
-- the switcher is put back on the Tool Belt page, to see whether the game's own drop then lands on a belt slot.
M.BELT_PAGE = 4
local function keepBeltPage(n, dragType)
    if dragType ~= L.page("toolBelt").slotType then return end
    local switcher = O.get(n, "InventorySwitcher")
    local page = try(function() return switcher:GetActiveWidgetIndex() end)
    if page ~= nil and page ~= M.BELT_PAGE then
        local ok, err = pcall(function() switcher:SetActiveWidgetIndex(M.BELT_PAGE) end)
        out("PAGE BACK %s -> %d: %s", tostring(page), M.BELT_PAGE, ok and "ok" or tostring(err))
    end
end

local down = false
-- No hooks: hooking UserWidget:OnMouseButtonDown from Storage Mage while Frame Mage hooks it too crashed the game
-- (twice, 2026-11-14: right after the hook was registered). The button is polled instead.
-- Is the Tool Belt page showing in an open inventory window? (The inventory's UI API exists only once the inventory
-- has been opened; a page inside the closed window isn't visible.)
-- (onlyBelt false: any page showing, i.e. the window is open)
local function beltShown(nav, onlyBelt)
    if not O.valid(try(function() return FindFirstOf("InventoryUIAPI") end)) then return false end
    local shown = false
    local beltType = L.page("toolBelt").slotType
    try(function() O.get(nav, "InventoryBodies"):ForEach(function(_, e)
        local body = e:get()
        if O.valid(body) and (onlyBelt == false or O.get(body, "SlotType") == beltType)
            and try(function() return body:IsVisible() end) == true then
            shown = true
        end
    end) end)
    return shown
end

-- The inventory screen is looked up every 2 s, never per poll: FindAllOf/FindFirstOf 33 times a second crashed the
-- game on entering the world three times (2026-11-14), right as the game built the inventory bodies. Between
-- lookups only the cached widget is read.
local nav, open, api = nil, false, nil
local function refresh()
    local pick = INVUI.findNav()
    nav = pick and pick.w or nil
    local was = open
    open = nav ~= nil and O.valid(nav) and beltShown(nav, false)
    api = open and try(function() return FindFirstOf("InventoryUIAPI") end) or nil
    if open ~= was then out("window %s", open and "OPEN (probe watching)" or "closed") end
end

-- Slots whose bIsSelected is set (the game's click-to-move may mark the picked-up slot), as "type:index" list.
local function selected(n)
    local list = {}
    try(function() O.get(n, "InventoryBodies"):ForEach(function(_, e)
        local body = e:get()
        try(function() body.InventorySlots:ForEach(function(_, se)
            local s = se:get()
            if O.valid(s) and O.get(s, "bIsSelected") == true then
                local p = O.get(s, "SlotPayload")
                list[#list + 1] = tostring(O.get(p, "OwningInventoryType")) .. ":" .. tostring(O.get(p, "InventoryIndex"))
            end
        end) end)
    end) end)
    return #list > 0 and table.concat(list, ",") or "none"
end

local function dragPayload()
    local dd = api and O.valid(api) and O.get(api, "DragAndDropAPI")
    local p = dd and O.valid(dd) and O.get(dd, "CurrentDragPayload")
    if not (p and O.valid(p)) then return "none" end
    local t = O.get(p, "OwningInventoryType")
    return string.format("%s (type %s index %s)", O.name(p), tostring(t), tostring(O.get(p, "InventoryIndex"))), t
end

-- Clicks inside the game's menus may never reach the player controller (the first armed run, 2026-11-14, saw no
-- press at all), so besides the button every visible effect of a click is watched and logged when it changes.
local last = {}
local function tick()
    local isDown = ctx.keys.isDown("LeftMouseButton")
    if isDown ~= down then
        down = isDown
        out("button %s (window %s)", isDown and "PRESS" or "RELEASE", open and "open" or "closed")
    end
    if not (open and nav and O.valid(nav)) then last = {} return end
    local drag, dragType = dragPayload()
    keepBeltPage(nav, dragType)
    local now = { over = hovered(nav), screen = (screenState(nav)), sel = selected(nav), drag = drag }
    for _, k in ipairs({ "over", "screen", "sel", "drag" }) do
        if now[k] ~= last[k] then out("%-6s %s", k, now[k]) end
    end
    last = now
end

-- Even this probe, polling only, crashed the game on entering the world (four times, 2026-11-14; the world loads
-- fine without it). So nothing runs until it's switched on in the world: numpad * starts it (and stops it again).
M.KEY = "Multiply"
local armed, started = false, false

function M.init(c)
    ctx, O = c, c.objects
    c.keys.bind(M.KEY, "beltProbe", function()
        armed = not armed
        out("probe %s (numpad *)", armed and "ON" or "OFF")
        c.log.info("beltprobe: %s", armed and "on" or "off")
        pcall(c.toast.show, armed and "Belt probe on" or "Belt probe off")
        if armed and not started then
            started = true
            pcall(refresh)
            c.sched.every(2000, "beltprobe.find", function()
                if not armed then nav, open = nil, false return end
                if not pcall(refresh) then nav, open = nil, false end
            end)
            c.sched.every(50, "beltprobe", function() if armed then pcall(tick) end end)
        end
    end)
end

return M
