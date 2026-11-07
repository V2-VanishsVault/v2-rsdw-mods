-- In-game layout editor.
--   F9 toggles. PgDn/PgUp cycle on-screen elements, Home/End go to parent / first child (so any widget
--   in any tree can be reached), arrows move (Shift = big step), +/- scale, [ ] fade, Del hide, Backspace reset,
--   Ins toggles the grid. With the grid on, arrows jump to the next position where an edge of the
--   element sits on a grid line (Shift: major lines).
-- The selection blinks and a banner at the top of the screen names it.
local M = {}

local ctx, W, layout, log, S
local active = false
local list, index = {}, 0
local selected -- widget
local blinkOn = false
local banner -- { uw, text }

-- Banner overlay --------------------------------------------------------------

local overlay = require("forgeframe.core.overlay")

local function buildBanner()
    local h = overlay.host("Banner", 20000)
    local border = overlay.new("Border", h.tree, "FF_Back_" .. h.suffix)
    border:SetBrushColor({ R = 0.02, G = 0.02, B = 0.03, A = 0.78 })
    border:SetPadding({ Left = 14, Top = 6, Right = 14, Bottom = 6 })
    local text = overlay.new("TextBlock", h.tree, "FF_Text_" .. h.suffix)
    text:SetColorAndOpacity({ SpecifiedColor = { R = 1, G = 0.82, B = 0.4, A = 1 }, ColorUseRule = 0 })
    border:SetContent(text)
    local slot = h.canvas:AddChildToCanvas(border)
    slot:SetAutoSize(true)
    slot:SetAnchors({ Minimum = { X = 0.5, Y = 0 }, Maximum = { X = 0.5, Y = 0 } })
    slot:SetAlignment({ X = 0.5, Y = 0 })
    slot:SetPosition({ X = 0, Y = 24 })
    banner = { uw = h.uw, text = text }
end

local function setBanner(msg)
    if not (banner and W.valid(banner.uw) and W.valid(banner.text)) then
        local ok, err = pcall(buildBanner)
        if not ok then log.warn("editor banner unavailable: %s", tostring(err)); banner = nil end
    end
    if banner then
        pcall(function() banner.text:SetText(FText(msg)) end)
        pcall(function() banner.uw:SetVisibility(msg == "" and 1 or 4) end) -- Collapsed / SelfHitTestInvisible
    end
end

-- Selection -------------------------------------------------------------------

local function fmt(n) return string.format("%g", math.floor(n * 100 + 0.5) / 100) end

local function describe()
    if not (selected and W.valid(selected)) then
        return string.format("FORGEFRAME EDIT [%s]  - nothing selected (PgDn)", layout.profileName())
    end
    local key = W.key(selected)
    local e = layout.entry(key) or {}
    local grid = ctx.features.grid
    local snap = (grid and grid.snapping()) and ("  SNAP " .. grid.cell(false)) or "  free"
    return string.format("FORGEFRAME EDIT [%s]  %d/%d  %s   x %s  y %s  scale %s  opacity %s%s%s",
        layout.profileName(), index, #list, key, fmt(e.x or 0), fmt(e.y or 0), fmt(e.scale or 1),
        fmt(e.opacity or 1), e.hidden and "  HIDDEN" or "", snap)
end

local function refresh() setBanner(describe()) end

local function unblink()
    if selected and W.valid(selected) then
        layout.blinkFull = nil
        pcall(layout.applyTo, selected, layout.entry(W.key(selected)))
    end
end

local function select(w)
    unblink()
    selected = w
    if w then
        layout.blinkFull = W.fullName(w)
        log.debug("selected %s", W.key(w))
    end
    refresh()
end

-- Every visible user widget on screen, plus anything that already has a layout entry.
local function buildList()
    list = {}
    local seen = {}
    for _, root in ipairs(W.viewportRoots()) do
        -- skip our overlays and other mods' code-built ones: they're all class "UserWidget", share one
        -- layout key, and moving one would move every one of them
        if not overlay.isOurs(root) and W.className(root) ~= "UserWidget" then
            W.walk(root, function(w)
                if not W.isVisible(w) then return false end
                local full = W.fullName(w)
                if not seen[full] and (W.isUserWidget(w) or layout.entry(W.key(w))) then
                    seen[full] = true
                    list[#list + 1] = w
                end
                return true
            end)
        end
    end
    index = 0
end

local function cycle(dir)
    if #list == 0 then buildList() end
    if #list == 0 then refresh() return end
    for _ = 1, #list do
        index = ((index - 1 + dir) % #list) + 1
        if W.valid(list[index]) then select(list[index]) return end
    end
    buildList()
    refresh()
end

local function go(toParent)
    if not (selected and W.valid(selected)) then return end
    local target
    if toParent then
        target = W.parent(selected)
    else
        target = W.children(selected)[1]
    end
    if target and W.valid(target) then select(target) end
end

-- Edits -----------------------------------------------------------------------

local function edit(mutate)
    if not (selected and W.valid(selected)) then return end
    layout.edit(selected, mutate)
    refresh()
end

local function clamp(v, lo, hi) return math.max(lo, math.min(hi, v)) end

local function move(dx, dy)
    edit(function(e) e.x = (e.x or 0) + dx; e.y = (e.y or 0) + dy end)
end

-- dx, dy in {-1, 0, 1}. Snaps to the grid when it is on, otherwise moves by the configured step.
local function nudge(dx, dy, big)
    if not (selected and W.valid(selected)) then return end
    local grid = ctx.features.grid
    if not (grid and grid.snapping()) then
        local step = big and S.bigStep or S.step
        move(dx * step, dy * step)
        return
    end
    local cell = grid.cell(big)
    local m = grid.measure(selected)
    if m then
        local e = layout.entry(W.key(selected)) or {}
        local k = m.accScale / (e.scale or 1) -- drawn units per translation unit
        if not (k > 0.01) then k = 1 end
        local cx, cy = grid.centre()
        local ddx = dx ~= 0 and grid.snapDelta(m.left, m.right, dx, cell, cx) or 0
        local ddy = dy ~= 0 and grid.snapDelta(m.top, m.bottom, dy, cell, cy) or 0
        move(ddx / k, ddy / k)
    else
        -- geometry unavailable: snap the offset itself
        edit(function(e)
            e.x = grid.roundTo((e.x or 0) + dx * cell, cell)
            e.y = grid.roundTo((e.y or 0) + dy * cell, cell)
        end)
    end
end

local function scaleBy(d)
    edit(function(e)
        e.scale = clamp((e.scale or 1) + d, S.minScale, S.maxScale)
        if math.abs(e.scale - 1) < 1e-6 then e.scale = nil end
    end)
end

local function fade(d)
    edit(function(e)
        e.opacity = clamp((e.opacity or 1) + d, 0.1, 1)
        if math.abs(e.opacity - 1) < 1e-6 then e.opacity = nil end
    end)
end

local function toggleHide()
    edit(function(e) if e.hidden then e.hidden = nil else e.hidden = true end end)
end

local function reset()
    edit(function(e) for k in pairs(e) do e[k] = nil end end)
end

-- Mode ------------------------------------------------------------------------

local function toggle()
    active = not active
    local grid = ctx.features.grid
    if active then
        if grid then grid.show() end
        buildList()
        log.info("editor on: %d on-screen elements", #list)
        cycle(1)
    else
        if grid then grid.hide() end
        unblink()
        selected = nil
        layout.save()
        setBanner("")
        log.info("editor off; layout saved")
    end
end

local function whenActive(fn)
    return function(...) if active then fn(...) end end
end

function M.isActive() return active end

-- Short on-screen message for other features (the UE4SS console is usually hidden).
local flashSeq = 0
function M.flash(msg)
    flashSeq = flashSeq + 1
    local mine = flashSeq
    setBanner(msg)
    ctx.sched.later(2500, "editor.flashClear", function()
        if flashSeq ~= mine then return end
        if active then refresh() else setBanner("") end
    end)
end

function M.init(c)
    ctx, W, log = c, c.widgets, c.log
    layout = c.features.layout
    if not layout then error("editor needs the layout feature") end
    S = c.settings.editor
    local K = c.settings.keys

    c.keys.bind(K.edit, "edit", toggle)
    c.keys.bind(K.next, "next", whenActive(function() cycle(1) end))
    c.keys.bind(K.prev, "prev", whenActive(function() cycle(-1) end))
    c.keys.bind(K.parent, "parent", whenActive(function() go(true) end))
    c.keys.bind(K.child, "child", whenActive(function() go(false) end))

    local dirs = { left = { -1, 0 }, right = { 1, 0 }, up = { 0, -1 }, down = { 0, 1 } }
    for name, d in pairs(dirs) do
        c.keys.bind(K[name], name, whenActive(function() nudge(d[1], d[2], false) end))
        c.keys.bind(K[name], name .. "Big", whenActive(function() nudge(d[1], d[2], true) end), { K.bigModifier })
    end
    c.keys.bind(K.scaleUp, "scaleUp", whenActive(function() scaleBy(S.scaleStep) end))
    c.keys.bind(K.scaleDown, "scaleDown", whenActive(function() scaleBy(-S.scaleStep) end))
    c.keys.bind(K.fadeUp, "fadeUp", whenActive(function() fade(S.fadeStep) end))
    c.keys.bind(K.fadeDown, "fadeDown", whenActive(function() fade(-S.fadeStep) end))
    c.keys.bind(K.hide, "hide", whenActive(toggleHide))
    c.keys.bind(K.reset, "reset", whenActive(reset))
    c.keys.bind(K.toggleGrid, "toggleGrid", whenActive(function()
        local grid = c.features.grid
        if grid then grid.toggleSnap(); refresh() end
    end))

    c.events.on("profilechanged", function() if active then buildList(); select(nil) end end)
    c.events.on("worldchanged", function()
        list, index, selected, banner = {}, 0, nil, nil
        if active then active = false; layout.save(); log.info("editor closed: world changed") end
    end)

    c.sched.every(S.blinkMs, "editor.blink", function()
        if not (active and selected) then return end
        if not W.valid(selected) then select(nil) return end
        blinkOn = not blinkOn
        local e = layout.entry(W.key(selected))
        if e and e.hidden then
            -- show hidden elements as a faint ghost so they can still be found and unhidden
            local ghost = {}
            for k, v in pairs(e) do ghost[k] = v end
            ghost.hidden = nil
            layout.applyTo(selected, ghost, blinkOn and 0.15 or 0.35)
        else
            layout.applyTo(selected, e, blinkOn and 0.25 or 1)
        end
    end)
end

return M
