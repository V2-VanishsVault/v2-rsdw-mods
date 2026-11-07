-- In-game layout editor (F9).
--
-- Selecting:  click a widget (click the same spot again to step out to its parent panel, and so on),
--             or PgDn/PgUp through on-screen elements, Ctrl+PgDn/PgUp through siblings, Home/End for
--             parent / first child.
-- Editing:    arrows move (snap to the grid when it's on; Shift = big step), +/- scale, [ ] fade,
--             Del hide, Backspace reset, Ins grid on/off.
-- Showing:    a frame with corner brackets marks the selection; elements with nothing to show are
--             previewed (editor/preview.lua); the banner names the selection. While the editor is open the
--             mouse cursor is shown and game input is paused, so clicks select instead of attacking.
local M = {}

local overlay = require("forgeframe.core.overlay")
local names = require("forgeframe.core.names")
local geometry = require("forgeframe.core.geometry")
local frame = require("forgeframe.editor.frame")
local preview = require("forgeframe.editor.preview")
local picker = require("forgeframe.editor.picker")

local ctx, W, layout, log, S
local active = false
local list, index = {}, 0
local selected -- widget (handle kept only while the editor is open; dropped on world change)
local banner -- { uw, text }

-- Banner --------------------------------------------------------------------------------

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
        pcall(function() banner.uw:SetVisibility(msg == "" and 1 or 3) end) -- Collapsed / HitTestInvisible
    end
end

-- Pure: the banner line for a selection (unit-tested).
function M.bannerText(key, entry)
    if not key then return "Click a widget to select it" end
    return names.pretty(key) .. ((entry and entry.hidden) and "  (hidden)" or "")
end

local function refresh()
    if not active then return end
    if selected and W.valid(selected) then
        local key = W.key(selected)
        setBanner(M.bannerText(key, layout.entry(key)))
    else
        setBanner(M.bannerText(nil))
    end
end

-- Short on-screen message for other features (the UE4SS console is usually hidden).
local flashSeq = 0
function M.flash(msg)
    flashSeq = flashSeq + 1
    local mine = flashSeq
    setBanner(msg)
    ctx.sched.later(1800, "editor.flashClear", function()
        if flashSeq ~= mine then return end
        if active then refresh() else setBanner("") end
    end)
end

-- Input: cursor on, game input paused while editing ---------------------------------------

local function playerController()
    local ok, pc = pcall(function()
        local gs = StaticFindObject("/Script/Engine.Default__GameplayStatics")
        return gs:GetPlayerController(FindFirstOf("GameInstance"), 0)
    end)
    if ok and W.valid(pc) then return pc end
    pc = FindFirstOf("PlayerController")
    return W.valid(pc) and pc or nil
end

local function setEditInput(on)
    if not S.lockInput then return end
    local pc = playerController()
    if not pc then log.warn("editor: no player controller; game input not paused") return end
    local wbl = StaticFindObject("/Script/UMG.Default__WidgetBlueprintLibrary")
    pcall(function() pc.bShowMouseCursor = on end)
    local ok, err
    if on then
        ok, err = pcall(function() wbl:SetInputMode_UIOnlyEx(pc, nil, 0, false) end)
        if not ok then ok, err = pcall(function() wbl:SetInputMode_UIOnlyEx(pc, nil, 0) end) end
    else
        ok, err = pcall(function() wbl:SetInputMode_GameOnly(pc, false) end)
        if not ok then ok, err = pcall(function() wbl:SetInputMode_GameOnly(pc) end) end
    end
    if not ok then log.warn("editor: could not change input mode: %s", tostring(err)) end
end

-- Selection ---------------------------------------------------------------------------------

local function release()
    if selected and W.valid(selected) then
        preview.finish()
        layout.skipFull = nil
        pcall(layout.applyTo, selected, layout.entry(W.key(selected)))
    else
        preview.forget()
        layout.skipFull = nil
    end
end

local function startPreview()
    local e = layout.entry(W.key(selected))
    local ok, err = pcall(preview.begin, selected, (e and e.hidden) and S.ghostOpacity or nil, S.previewMaxText)
    if not ok then log.debug("preview failed: %s", tostring(err)) end
end

local function select(w)
    release()
    selected = w
    if w then
        layout.skipFull = W.fullName(w)
        startPreview()
        log.debug("selected %s", W.key(w))
    end
    refresh()
end

local function gameRoots()
    local roots = {}
    for _, root in ipairs(W.viewportRoots()) do
        -- skip our overlays and other mods' code-built ones: they're all class "UserWidget", share one
        -- layout key, and moving one would move every one of them
        if not overlay.isOurs(root) and W.className(root) ~= "UserWidget" then roots[#roots + 1] = root end
    end
    return roots
end

-- Every user widget in the on-screen trees, visible or not (hidden ones are previewed when selected),
-- one per layout key: list entries share a key, so one of them stands for all.
local function buildList()
    list = {}
    local seenKey = {}
    for _, root in ipairs(gameRoots()) do
        W.walk(root, function(w)
            if W.isUserWidget(w) or layout.entry(W.key(w)) then
                local key = W.key(w)
                if not seenKey[key] then
                    seenKey[key] = true
                    list[#list + 1] = w
                end
            end
            return true
        end)
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

local function sibling(dir)
    if not (selected and W.valid(selected)) then return end
    local parent = W.parent(selected)
    if not parent then return end
    local kids = W.children(parent)
    if #kids < 2 then return end
    local me = W.fullName(selected)
    for i, k in ipairs(kids) do
        if W.fullName(k) == me then
            select(kids[((i - 1 + dir) % #kids) + 1])
            return
        end
    end
end

local function go(toParent)
    if not (selected and W.valid(selected)) then return end
    local target = toParent and W.parent(selected) or W.children(selected)[1]
    if target and W.valid(target) then select(target) end
end

local function pickAtMouse()
    local x, y = geometry.mouse()
    if not x then log.debug("pick: no mouse position") return end
    local w, i, n = picker.pick(gameRoots(), x, y, S)
    if w then
        select(w)
        if n > 1 then log.debug("pick %d/%d at %.0f,%.0f", i, n, x, y) end
    end
end

-- Edits ----------------------------------------------------------------------------------------

local function edit(mutate)
    if not (selected and W.valid(selected)) then return end
    preview.finish()
    layout.edit(selected, mutate)
    startPreview() -- re-preview against the new entry (e.g. hidden <-> shown)
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
    local m = geometry.rect(selected)
    if m and m.right > m.left and m.bottom > m.top then
        local e = layout.entry(W.key(selected)) or {}
        local k = m.accScale / (e.scale or 1) -- drawn units per translation unit
        if not (k > 0.01) then k = 1 end
        local cx, cy = grid.centre()
        local ddx = dx ~= 0 and grid.snapDelta(m.left, m.right, dx, cell, cx) or 0
        local ddy = dy ~= 0 and grid.snapDelta(m.top, m.bottom, dy, cell, cy) or 0
        move(ddx / k, ddy / k)
    else
        -- no measurable size (empty widget): snap the offset itself
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

-- Mode ---------------------------------------------------------------------------------------------

local function open()
    active = true
    local ok, err = frame.open(S)
    if not ok then log.warn("editor frame unavailable: %s", tostring(err)) end
    local grid = ctx.features.grid
    if grid then grid.show() end
    setEditInput(true)
    picker.forget()
    selected, list, index = nil, {}, 0
    refresh()
    log.info("editor on")
end

local function close(save)
    release()
    selected, list = nil, {}
    frame.close()
    local grid = ctx.features.grid
    if grid then grid.hide() end
    setEditInput(false)
    if save then layout.save() end
    setBanner("")
    active = false
    log.info("editor off")
end

local function toggle()
    if active then close(true) else open() end
end

local function whenActive(fn)
    return function(...) if active then fn(...) end end
end

function M.isActive() return active end

function M.init(c)
    ctx, W, log = c, c.widgets, c.log
    layout = c.features.layout
    if not layout then error("editor needs the layout feature") end
    S = c.settings.editor
    local K = c.settings.keys

    c.keys.bind(K.edit, "edit", toggle)
    c.keys.bind(K.pick, "pick", whenActive(pickAtMouse))
    c.keys.bind(K.next, "next", whenActive(function() cycle(1) end))
    c.keys.bind(K.prev, "prev", whenActive(function() cycle(-1) end))
    c.keys.bind(K.nextSibling, "nextSibling", whenActive(function() sibling(1) end))
    c.keys.bind(K.prevSibling, "prevSibling", whenActive(function() sibling(-1) end))
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
        if grid then M.flash(grid.toggleSnap() and "Grid on" or "Grid off") end
    end))

    c.events.on("profilechanged", function() if active then select(nil); buildList() end end)
    c.events.on("worldchanged", function()
        -- every handle is stale now: drop them without touching anything
        preview.forget()
        frame.forget()
        picker.forget()
        layout.skipFull = nil
        list, index, selected, banner = {}, 0, nil, nil
        if active then
            active = false
            layout.save()
            setEditInput(false)
            log.info("editor closed: world changed")
        end
    end)

    -- Follow the selection: keep the preview applied and the frame on the widget as it moves/animates.
    c.sched.every(S.frameMs, "editor.frame", function()
        if not active then return end
        if selected and not W.valid(selected) then
            preview.forget()
            layout.skipFull = nil
            selected = nil
            refresh()
        end
        if selected then
            preview.tick()
            frame.place(geometry.rect(selected), S)
        else
            frame.place(nil, S)
        end
    end)
end

return M
