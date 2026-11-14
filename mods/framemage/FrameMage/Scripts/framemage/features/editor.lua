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

local overlay = require("framemage.core.overlay")
local names = require("framemage.core.names")
local geometry = require("framemage.core.geometry")
local frame = require("framemage.editor.frame")
local preview = require("framemage.editor.preview")
local samples = require("framemage.editor.samples")
local picker = require("framemage.editor.picker")
local legend = require("framemage.editor.legend")
local banner = require("framemage.editor.banner")
local mouse = require("framemage.editor.mouse")
local handles = require("framemage.editor.handles")
local hidden = require("framemage.editor.hidden")
local inputblock = require("framemage.editor.inputblock")
local settingsPanel = require("framemage.editor.settings")
local units = require("framemage.editor.units")

local ctx, W, layout, log, S
local active = false
local list, index = {}, 0
local legendDevice = 0
local refreshHandles -- the drag bars (defined below)
local selected -- widget (handle kept only while the editor is open; dropped on world change)

-- Banner (editor/banner.lua: the ribbon below the compass) -------------------------------------------

-- The banner is off by default (it got in the way of moving things): short messages flash in the hotkey list's
-- title bar instead.
local function setBanner(msg) if S and S.showBanner then banner.set(msg) end end

-- Pure: the banner line for a selection (unit-tested).
function M.bannerText(key, entry)
    if not key then return "Drag a title bar to move it, or click anything to select it" end
    return names.pretty(key) .. ((entry and entry.hidden) and "  (hidden)" or "")
end

local titleFor -- the selection's display name (defined with the units below)

local function refresh()
    if not active then return end
    if selected and W.valid(selected) then
        local key = W.key(selected)
        local entry = layout.entry(key)
        setBanner(titleFor(selected) .. ((entry and entry.hidden) and "  (hidden)" or ""))
    elseif hidden.isOpen() then
        setBanner("Click a hidden element in the list to show it")
    else
        setBanner(M.bannerText(nil))
    end
end

-- Short on-screen message for other features (the UE4SS console is usually hidden).
local flashSeq = 0
function M.flash(msg)
    flashSeq = flashSeq + 1
    local mine = flashSeq
    if not active then
        -- outside the editor (an art reload, a delayed dump, Settings on its own) the banner is the only thing on
        -- screen to say it: shown in a development install only (dev/, ctx.dev), like the developer keys. The log
        -- always has it.
        log.info("%s", tostring(msg))
        if not ctx.dev then return end
        pcall(banner.set, msg)
        ctx.sched.later(2500, "editor.flashClear", function()
            if flashSeq == mine and not active then pcall(banner.set, "") end
        end)
        return
    end
    if not S.showBanner then legend.flash(msg) return end
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
    -- the game's own key bindings (radial menus, inventory...) are swallowed while editing
    if on then inputblock.block() else inputblock.unblock() end
    local pc = playerController()
    if not pc then log.warn("editor: no player controller; game input not paused") return end
    -- Game-and-UI mode (not UI-only): the player controller must keep seeing keys and clicks, because
    -- hotkeys are read from it (core/keys.lua). The character's own input is switched off instead, which
    -- stops camera look, movement and attacks while the editor is open.
    local wbl = StaticFindObject("/Script/UMG.Default__WidgetBlueprintLibrary")
    pcall(function() pc.bShowMouseCursor = on end)
    local ok, err
    if on then
        ok, err = pcall(function() wbl:SetInputMode_GameAndUIEx(pc, nil, 0, false, false) end)
        if not ok then ok, err = pcall(function() wbl:SetInputMode_GameAndUIEx(pc, nil, 0, false) end) end
    else
        ok, err = pcall(function() wbl:SetInputMode_GameOnly(pc, false) end)
        if not ok then ok, err = pcall(function() wbl:SetInputMode_GameOnly(pc) end) end
    end
    if not ok then log.warn("editor: could not change input mode: %s", tostring(err)) end
    local okP, pawn = pcall(function() return pc:K2_GetPawn() end)
    if okP and W.valid(pawn) then
        local okI, ierr = pcall(function()
            if on then pawn:DisableInput(pc) else pawn:EnableInput(pc) end
        end)
        if not okI then log.warn("editor: could not %s character input: %s", on and "pause" or "resume", tostring(ierr)) end
    end
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

local selectingFromPanel = false
local function select(w)
    if not selectingFromPanel then hidden.clearCurrent() end
    release()
    selected = w
    if w then
        layout.skipFull = W.fullName(w)
        startPreview()
        log.debug("selected %s", W.key(w))
    end
    refresh()
    refreshHandles() -- the selection's bar moves to its frame (and a deselected element gets its own back)
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

-- Pure: is this widget class a small building block (a key-prompt icon, a text wrapper, a tooltip) rather than
-- an element a player would move on its own? Matched against editor.ignoreClasses. Classes in `keep`
-- (editor.forceSplit: holders of separate pieces) never are, even when a pattern matches ("InputLegend" is meant for
-- the key entries, not the legend that holds the key hints and the menu shortcuts). Unit-tested.
function M.isAtom(className, patterns, keep)
    if keep and keep[className] then return false end
    for _, p in ipairs(patterns or {}) do
        if className:find(p, 1, true) then return true end
    end
    return false
end

local currentUnits -- defined below

-- The elements PgUp/PgDn step through: the movable units on screen (editor/units.lua), top to bottom, left to
-- right. Hidden ones are in the hidden-elements panel (H).
local function buildList()
    list = {}
    local us = currentUnits(true)
    table.sort(us, function(a, b)
        if math.abs(a.rect.top - b.rect.top) > 8 then return a.rect.top < b.rect.top end
        return a.rect.left < b.rect.left
    end)
    for _, u in ipairs(us) do list[#list + 1] = u.widget end
    index = 0
end

-- Pure: should this element get its own drag bar? Big enough to grab, not a full-screen container, not a small
-- building block. Unit-tested.
function M.wantsHandle(area, screenArea, isAtom, s)
    if isAtom then return false end
    if area < s.handleMinArea then return false end
    return area <= screenArea * s.handleMaxScreenShare
end

-- The outermost movable elements on screen, for the drag bars: { {widget, rect, title} }. A panel that gets a
-- bar isn't searched further (its pieces don't get their own); full-screen containers are searched through.
-- Finding the game's top-level widgets is a full object scan: the bars reuse the result for a couple of seconds.
local rootsCache, rootsAt = nil, -1
local function cachedRoots()
    local now = os.clock()
    if not rootsCache or now - rootsAt > S.rootsCacheSeconds then rootsCache, rootsAt = gameRoots(), now end
    return rootsCache
end

-- The movable units on screen (cached briefly: collecting walks every visible widget tree).
local unitsCache, unitsAt = {}, -1
local unitsTimed = false
currentUnits = function(force)
    local now = os.clock()
    if not force and now - unitsAt < S.handlesMs / 1000 * 0.9 then return unitsCache end
    local sw, sh = geometry.screen()
    if not sw then return unitsCache end
    local roots = cachedRoots()
    for _, r in ipairs(roots) do
        if not W.valid(r) then rootsCache = nil; roots = cachedRoots() break end
    end
    local t0 = os.clock()
    local ok, res = pcall(units.collect, roots, sw, sh)
    if ok then
        unitsCache = res
        -- each element's size while it shows something: an empty one's stand-in is drawn at it later
        for _, u in ipairs(res) do if not u.empty then samples.remember(u.key, u.rect) end end
    else
        log.debug("units: %s", tostring(res))
    end
    unitsAt = now
    if not unitsTimed then
        unitsTimed = true
        log.info("editor: %d movable elements on screen (found in %.0f ms)", #unitsCache, (os.clock() - t0) * 1000)
    end
    return unitsCache
end

local function unitOf(w)
    return w and units.containing(unitsCache, w) or nil
end

titleFor = function(w)
    local u = unitOf(w)
    if u then return u.title end
    local okK, key = pcall(W.key, w)
    return okK and names.pretty(key) or "?"
end

refreshHandles = function()
    if not (active and S.showHandles) then handles.hide() return end
    local sw, sh = geometry.screen()
    if not sw then return end
    local ok, err = pcall(function()
        local targets = {}
        local selFull = selected and W.valid(selected) and W.fullName(selected)
        for _, u in ipairs(currentUnits()) do
            local okF, full = pcall(W.fullName, u.widget)
            local big = u.empty or M.wantsHandle(u.area, sw * sh, false, S)
            if okF and full ~= selFull and big then targets[#targets + 1] = u end
        end
        -- bigger elements claim their bar's spot first
        table.sort(targets, function(a, b) return a.area > b.area end)
        handles.show(targets, sw, sh)
    end)
    if not ok then log.debug("drag bars: %s", tostring(err)) end
end

-- Everything that isn't showing: the outermost movable element of each hidden branch, plus anything you hid
-- yourself. { {widget, title} }, sorted by name.
-- Pure: is a hidden game piece left out of the panel? By the title it shows (editor.hiddenSkip, whole name) or
-- its class (editor.hiddenSkipClasses, part of the name); any case. Unit-tested.
M.skipHidden = units.skipHidden

local function hiddenTargets()
    local out, seen = {}, {}
    -- yours = you hid it yourself: always listed, so it can be shown again
    local function add(w, yours)
        local k = W.key(w)
        if seen[k] then return end
        seen[k] = true
        local title = names.pretty(k)
        local okC, cls = pcall(W.className, w)
        if yours or not M.skipHidden(title, S.hiddenSkip, okC and cls, S.hiddenSkipClasses) then out[#out + 1] = { widget = w, title = title } end
    end
    for _, root in ipairs(gameRoots()) do
        W.walk(root, function(w)
            if W.isVisible(w) then
                local e = layout.entry(W.key(w))
                if e and e.hidden then add(w, true) return false end
                return true
            end
            W.walk(w, function(x)
                if W.isUserWidget(x) and not M.isAtom(W.className(x), S.ignoreClasses, S.forceSplit) then add(x) return false end
                return true
            end)
            return false
        end)
    end
    table.sort(out, function(a, b) return a.title:lower() < b.title:lower() end)
    return out
end

local function toggleHiddenPanel()
    if hidden.isOpen() then
        hidden.close()
        select(nil)
    else
        local list = hiddenTargets()
        if hidden.open(list) then
            log.info("hidden-elements panel: %d elements", #list)
            refresh()
        end
    end
end

-- From the panel: show this one (the previous one goes back to hidden), or nil = hide it again.
local function pickHidden(w)
    selectingFromPanel = true
    select(w)
    selectingFromPanel = false
end

local function saveHidden()
    hidden.close()
    select(nil)
    layout.save()
    M.flash("Layout saved")
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

-- Click: the smallest unit under the pointer; clicking the same spot again steps out to the next bigger one.
local lastPick -- { x, y, i, n }
local function pickAt(x, y)
    local hits = {}
    for _, u in ipairs(currentUnits()) do
        if W.valid(u.widget) and geometry.contains(u.rect, x, y) then hits[#hits + 1] = u end
    end
    -- what you can see first (smallest first), then empty elements' placeholders (an empty Interaction Prompt
    -- must not catch clicks meant for the menu shortcuts it sits over); click again to step through them
    table.sort(hits, function(a, b)
        if (a.empty or false) ~= (b.empty or false) then return not a.empty end
        return a.area < b.area
    end)
    if #hits == 0 then lastPick = nil; M.flash("Nothing to select there") return end
    local i = 1
    local tol = S.pickRepeatTolerance
    if lastPick and lastPick.n == #hits and math.abs(lastPick.x - x) <= tol and math.abs(lastPick.y - y) <= tol then
        i = lastPick.i % #hits + 1
    end
    lastPick = { x = x, y = y, i = i, n = #hits }
    select(hits[i].widget)
    log.debug("pick %d/%d at %.0f,%.0f: %s", i, #hits, x, y, hits[i].title)
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

-- Undo (Ctrl+Z): each step is the elements one move changed and where they were before it - a drag (a group drag
-- is one step) or a nudge. { { { w, x, y }, ... }, ... }, newest last; kept to editor.undoSteps.
local undoStack = {}
local function remember(items)
    if #items == 0 then return end
    undoStack[#undoStack + 1] = items
    while #undoStack > (S.undoSteps or 50) do table.remove(undoStack, 1) end
end
local function placeOf(w)
    local e = layout.entry(W.key(w)) or {}
    return { w = w, x = e.x, y = e.y }
end

local function move(dx, dy)
    if selected and W.valid(selected) then remember({ placeOf(selected) }) end
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
        local cx, cy = grid.center()
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

-- Dragging (mouse on the title bar, or the controller's left stick) ----------------------------------------

-- Pure: offset to move an edge pair [a, b] so the NEAREST edge sits on the nearest grid line (for drops).
function M.snapNearest(a, b, cell, origin)
    origin = origin or 0
    local best
    for _, e in ipairs({ a, b }) do
        local d = origin + math.floor((e - origin) / cell + 0.5) * cell - e
        if not best or math.abs(d) < math.abs(best) then best = d end
    end
    return best
end

-- Pure: stick deflection -> movement this frame. Deadzone removed, then squared for fine control near the
-- center and speed at full tilt. Unit-tested.
function M.stickMove(v, deadzone, speed, dt)
    local a = math.abs(v)
    if a <= deadzone then return 0 end
    local t = (a - deadzone) / (1 - deadzone)
    return (v < 0 and -1 or 1) * t * t * speed * dt
end

local drag -- { ex, ey, nx, ny, k, x0, y0, moved, source = "mouse"|"stick" }

-- The group: elements Ctrl+clicked by their title bars, dragged together (each by the same distance on screen).
-- { fullName -> widget }. Emptied when a group drag ends.
local group = {}
local function inGroup(w) return w and W.valid(w) and group[W.fullName(w)] ~= nil end
local function groupSize() local n = 0 for _ in pairs(group) do n = n + 1 end return n end
local function ctrlHeld()
    return ctx.keys.isDown and (ctx.keys.isDown("LeftControl") or ctx.keys.isDown("RightControl"))
end
local function toggleGroup(w)
    local full = W.fullName(w)
    if group[full] then group[full] = nil else group[full] = w end
    log.info("editor: %s %s the group (%d in it)", tostring(titleFor(w)), group[full] and "added to" or "taken out of",
        groupSize())
    refreshHandles() -- (the grouped bars turn gold: no message, which would widen the key list)
end

-- Ctrl+Z: the last move undone - every element it changed back where it was.
local function undo()
    local step = table.remove(undoStack)
    if not step then M.flash("Nothing to undo") return end
    for _, it in ipairs(step) do
        if W.valid(it.w) then
            local function back(e) e.x = it.x; e.y = it.y end
            if it.w == selected then edit(back) else pcall(layout.edit, it.w, back) end
        end
    end
    unitsAt = -1
    refresh()
    refreshHandles()
end
M.undo = undo

-- Each group member's start, for a group drag: its offset and how many screen units a unit of offset is.
local function groupStart()
    local out = {}
    for _, w in pairs(group) do
        if W.valid(w) then
            local e = layout.entry(W.key(w)) or {}
            local m = geometry.rect(w)
            local k = (m and m.accScale or 1) / (e.scale or 1)
            if not (k > 0.01) then k = 1 end
            out[#out + 1] = { w = w, ex = e.x or 0, ey = e.y or 0, k = k }
        end
    end
    return out
end

local function beginDrag(source, x0, y0)
    if not (selected and W.valid(selected)) then return end
    local e = layout.entry(W.key(selected)) or {}
    local m = geometry.rect(selected)
    local k = (m and m.accScale or 1) / (e.scale or 1) -- drawn units per translation unit
    if not (k > 0.01) then k = 1 end
    drag = { ex = e.x or 0, ey = e.y or 0, nx = e.x or 0, ny = e.y or 0, k = k, x0 = x0, y0 = y0, moved = false,
        source = source }
    if source == "mouse" and groupSize() > 0 and inGroup(selected) then
        drag.group = groupStart()
        -- the layout re-applies saved offsets to the elements it tracks: not to the group while it's dragged
        layout.skipSet = {}
        for full in pairs(group) do layout.skipSet[full] = true end
    end
    -- while it's held, the other elements' bars step aside: they'd cover what you're lining it up with (they come
    -- back on release - onMouseUp refreshes them)
    if source == "mouse" then handles.hide() end
end

local function endDrag()
    local d = drag
    drag = nil
    unitsAt = -1 -- something moved: the next bar refresh measures afresh
    if d and d.group then
        layout.skipSet = nil
        -- a group drag: every member saved where it was dropped, and the group let go
        if d.moved and d.last then
            local before = {}
            for _, m in ipairs(d.group) do
                if W.valid(m.w) then before[#before + 1] = { w = m.w, x = m.ex ~= 0 and m.ex or nil, y = m.ey ~= 0 and m.ey or nil } end
            end
            remember(before)
            for _, m in ipairs(d.group) do
                if W.valid(m.w) then
                    local nx, ny = m.ex + d.last.dx / m.k, m.ey + d.last.dy / m.k
                    if m.w == selected then
                        edit(function(e) e.x = nx; e.y = ny end)
                    else
                        pcall(layout.edit, m.w, function(e) e.x = nx; e.y = ny end)
                    end
                end
            end
        end
        group = {}
        refreshHandles()
        return
    end
    if not (d and d.moved and selected and W.valid(selected)) then return end
    local nx, ny = d.nx, d.ny
    local grid = ctx.features.grid
    if grid and grid.snapping() then
        local r = geometry.rect(selected)
        if r and r.right > r.left then
            local cx, cy = grid.center()
            local cell = grid.cell(false)
            nx = nx + M.snapNearest(r.left, r.right, cell, cx) / d.k
            ny = ny + M.snapNearest(r.top, r.bottom, cell, cy) / d.k
        end
    end
    -- never saved fully off screen (it couldn't be seen to be dragged back): at least `keepOnScreen` units of it stay
    local r = geometry.rect(selected)
    local sw, sh = geometry.screen()
    if r and sw and sh then
        local fx, fy = M.keepVisible(r, sw, sh, S.keepOnScreen or 48)
        nx, ny = nx + fx / d.k, ny + fy / d.k
    end
    remember({ { w = selected, x = d.ex ~= 0 and d.ex or nil, y = d.ey ~= 0 and d.ey or nil } })
    edit(function(e) e.x = nx; e.y = ny end)
end

-- Pure: how far to move a rect so at least `keep` units of it (or all of it, if smaller) stay on a sw x sh screen.
-- Unit-tested.
function M.keepVisible(r, sw, sh, keep)
    local function axis(lo, hi, size)
        local need = math.min(keep, hi - lo)
        if hi < need then return need - hi end
        if lo > size - need then return (size - need) - lo end
        return 0
    end
    return axis(r.left, r.right, sw), axis(r.top, r.bottom, sh)
end

local function dragTo(nx, ny)
    drag.nx, drag.ny = nx, ny
    pcall(function() selected:SetRenderTranslation({ X = nx, Y = ny }) end) -- live; saved on release
end


local solo = false -- the Settings panel open on its own (F4 in normal play), without the editor

local function onMouseDown(x, y, button)
    -- a click on the shared Settings panel is the panel's (its copy may live in another mod: the click reaches the
    -- editor's catcher too)
    if require("framemage.core.panelshared").contains(x, y) then return end
    if solo then
        if button == "LeftMouseButton" then settingsPanel.onDown(x, y) end
        return
    end
    if button == "LeftMouseButton" and legend.onDown(x, y) then return end -- the hotkey list's own title bar / body
    if button == "LeftMouseButton" and settingsPanel.onDown(x, y) then return end -- the Settings panel (on top)
    if button == "LeftMouseButton" and hidden.onDown(x, y) then return end -- the hidden-elements panel
    if button == "RightMouseButton" then go(true) return end -- right-click: the panel around it
    if button ~= "LeftMouseButton" then return end
    local bar = frame.barRect()
    local onFrame = selected and bar and geometry.contains(bar, x, y)
    local w = (not onFrame) and handles.at(x, y) or nil
    -- Ctrl+click on a title bar: in or out of the group (no drag)
    if (onFrame or w) and ctrlHeld() then
        toggleGroup(onFrame and selected or w)
        return
    end
    if onFrame then
        beginDrag("mouse", x, y)
        return
    end
    -- any element's own gold bar: select it and start dragging in one go (with the group, if it's in it)
    if w then
        if groupSize() > 0 and not inGroup(w) then group = {} end -- a bar outside the group: the group's let go
        select(w)
        beginDrag("mouse", x, y)
        return
    end
    pickAt(x, y)
end

local function onMouseUp(_, _, button)
    if solo then
        if button == "LeftMouseButton" then settingsPanel.onUp() end
        return
    end
    if button == "LeftMouseButton" and legend.onUp() then return end
    if button == "LeftMouseButton" and settingsPanel.onUp() then return end
    if button == "LeftMouseButton" and hidden.onUp() then return end
    if button == "LeftMouseButton" and drag and drag.source == "mouse" then
        endDrag()
        refreshHandles()
    end
end

local lastDragTick = os.clock()
local function dragTick()
    local now = os.clock()
    local dt = math.min(now - lastDragTick, 0.1)
    lastDragTick = now
    if solo then
        mouse.tick()
        settingsPanel.tick()
        if settingsPanel.isDragging() then settingsPanel.dragTick(geometry.mouse()) end
        return
    end
    if not active then return end
    mouse.tick()
    legend.tick()
    settingsPanel.tick()
    if settingsPanel.isDragging() then settingsPanel.dragTick(geometry.mouse()) return end
    if legend.isDragging() then legend.dragTick(geometry.mouse()) return end
    if hidden.isDragging() then hidden.dragTick(geometry.mouse()) return end
    if not (selected and W.valid(selected)) then drag = nil return end
    if drag and drag.source == "mouse" then
        local x, y = geometry.mouse()
        if x then
            local dx, dy = x - drag.x0, y - drag.y0
            if math.abs(dx) + math.abs(dy) > 2 then drag.moved = true end
            if drag.moved and drag.group then
                drag.last = { dx = dx, dy = dy }
                for _, m in ipairs(drag.group) do
                    if W.valid(m.w) then
                        pcall(function() m.w:SetRenderTranslation({ X = m.ex + dx / m.k, Y = m.ey + dy / m.k }) end)
                    end
                end
            elseif drag.moved then dragTo(drag.ex + dx / drag.k, drag.ey + dy / drag.k) end
        end
        return
    end
    -- controller: the left stick moves the selection smoothly; letting go drops it (snapping if the grid is on)
    local lx = M.stickMove(ctx.keys.analog("Gamepad_LeftX"), S.stickDeadzone, S.stickSpeed, dt)
    local ly = M.stickMove(ctx.keys.analog("Gamepad_LeftY"), S.stickDeadzone, S.stickSpeed, dt)
    if lx ~= 0 or ly ~= 0 then
        ctx.keys.noteGamepad()
        if not drag then beginDrag("stick", 0, 0) end
        if drag then
            drag.moved = true
            dragTo(drag.nx + lx / drag.k, drag.ny - ly / drag.k) -- stick up is positive, screen up is negative
        end
    elseif drag and drag.source == "stick" then
        endDrag()
    end
end

-- Mode ---------------------------------------------------------------------------------------------

local function open()
    active = true
    local ok, err = frame.open(S)
    if not ok then log.warn("editor frame unavailable: %s", tostring(err)) end
    local grid = ctx.features.grid
    if grid then grid.show() end
    legend.show(ctx, S)
    setEditInput(true)
    mouse.open()
    picker.forget()
    drag = nil
    selected, list, index = nil, {}, 0
    unitsAt, unitsTimed, lastPick = -1, false, nil
    refresh()
    -- the overlay canvas needs one paint before anything can be measured: bars appear a moment after opening
    ctx.sched.later(120, "editor.handlesFirst", refreshHandles)
    require("framemage.core.panelshared").setEditorOpen(true)
    log.info("editor on")
end

local function close(save)
    if drag then endDrag() end
    release()
    selected, list = nil, {}
    mouse.close()
    handles.hide()
    hidden.close()
    settingsPanel.close()
    frame.close()
    local grid = ctx.features.grid
    if grid then grid.hide() end
    legend.hide()
    setEditInput(false)
    if save then layout.save() end
    samples.save()
    setBanner("")
    active = false
    require("framemage.core.panelshared").setEditorOpen(false)
    log.info("editor off")
end

-- The Settings panel on its own, in normal play: the mouse cursor shows and the game's input pauses while it's
-- open (as in the editor), and nothing else of the editor appears.
local function openSolo()
    if active or solo then return end
    solo = true
    setEditInput(true)
    mouse.open()
    if not settingsPanel.open() then
        log.warn("settings: the panel could not be shown")
    end
    log.info("settings on (outside the editor)")
end

-- (fromPanel: the panel closed itself, from its Close button)
local function closeSolo(fromPanel)
    if not solo then return end
    solo = false
    if not fromPanel then settingsPanel.close() end
    mouse.close()
    setEditInput(false)
    log.info("settings off")
end

-- F4: the Settings panel - inside the editor it opens over it; in normal play, on its own
local function toggleSettings()
    if active then settingsPanel.toggle()
    elseif solo then closeSolo()
    else openSolo() end
end

local function toggle()
    if solo then
        -- F9 with Settings open on its own: the editor opens round it, Settings staying open
        closeSolo()
        open()
        settingsPanel.open()
        return
    end
    if active then close(true) else open() end
end

function M.isActive() return active end

-- Is the Settings panel open on its own (outside the editor)?
function M.isSettingsOpen() return solo end

-- Close (saving the layout), e.g. when the whole mod is switched off.
function M.close() if active then close(true) end end

-- Hotkeys changed (the Settings panel): the legend is rebuilt the next time it is shown.
function M.handlesChanged() refreshHandles() end

function M.keysChanged()
    legend.invalidate()
    if active then legend.show(ctx, S) end
end

function M.init(c)
    ctx, W, log = c, c.widgets, c.log
    layout = c.features.layout
    if not layout then error("editor needs the layout feature") end
    S = c.settings.editor
    banner.init(c, S)
    handles.init(c, S)
    handles.setMarked(function(w) return inGroup(w) end)
    samples.init(c)
    preview.init(c)
    units.init(W, geometry, names, S, function(cls) return M.isAtom(cls, S.ignoreClasses, S.forceSplit) end)
    inputblock.init(c)
    hidden.init(c, S, pickHidden, saveHidden)
    settingsPanel.init(c, S, function()
        if solo then closeSolo(true) else refresh() end
    end)
    mouse.init(c, { down = onMouseDown, up = onMouseUp, wheel = function(x, y, d)
        if require("framemage.core.panelshared").panelBusy() then return end -- (the shared panel pages with it)
        if not settingsPanel.onWheel(x, y, d) then hidden.onWheel(x, y, d) end
    end })
    local K = c.settings.keys

    -- (the shared Settings panel open over the editor: the editor's keys wait, so typing a key into the panel
    -- doesn't also move an element)
    local shared = require("framemage.core.panelshared")
    local function isActive() return active and not shared.panelBusy() end
    -- editor-only key: not even polled while the editor is closed
    local function ed(setting, fn, extraMods, repeats, name)
        c.keys.bind(K[setting], name or setting, fn, extraMods, { setting = setting, when = isActive, repeats = repeats })
    end

    c.keys.bind(K.edit, "edit", toggle, nil, { when = function() return c.enabled end })
    c.keys.bind(K.padEdit, "padEdit", toggle, nil, { when = function() return c.enabled end })
    ed("next", function() cycle(1) end)
    ed("prev", function() cycle(-1) end)
    ed("nextSibling", function() sibling(1) end)
    ed("prevSibling", function() sibling(-1) end)
    ed("parent", function() go(true) end)
    ed("child", function() go(false) end)

    local dirs = { left = { -1, 0 }, right = { 1, 0 }, up = { 0, -1 }, down = { 0, 1 } }
    for name, d in pairs(dirs) do
        ed(name, function() nudge(d[1], d[2], false) end, nil, true)
        ed(name, function() nudge(d[1], d[2], true) end, { K.bigModifier }, true, name .. "Big")
    end
    ed("scaleUp", function() scaleBy(S.scaleStep) end, nil, true)
    ed("scaleDown", function() scaleBy(-S.scaleStep) end, nil, true)
    ed("fadeUp", function() fade(S.fadeStep) end, nil, true)
    ed("fadeDown", function() fade(-S.fadeStep) end, nil, true)
    ed("hide", toggleHide)
    ed("reset", reset)
    ed("legend", function() legend.toggle() end)
    -- Escape: closes the Settings panel first, if it's open; then the editor
    ed("closeEditor", function()
        if settingsPanel.isOpen() then settingsPanel.close() else close(true) end
    end)
    -- F4 works in normal play too (the panel on its own); Escape closes it there. (The shared panel polls its own
    -- open key, in whichever mod's copy draws it.)
    if not shared.enabled() then
        c.keys.bind(K.settings, "settings", toggleSettings, nil, { setting = "settings", when = function() return c.enabled end })
        c.keys.bind(K.closeEditor, "closeSettings", function() closeSolo() end, nil,
            { setting = "closeEditor", when = function() return solo end })
    end
    ed("showHidden", toggleHiddenPanel)
    ed("undo", function() undo() end)

    -- controller (Xbox names; the same buttons on other pads)
    ed("padNext", function() cycle(1) end)
    ed("padPrev", function() cycle(-1) end)
    ed("padChild", function() go(false) end)
    ed("padParent", function() go(true) end)
    ed("padUp", function() nudge(0, -1, false) end, nil, true)
    ed("padDown", function() nudge(0, 1, false) end, nil, true)
    ed("padLeft", function() nudge(-1, 0, false) end, nil, true)
    ed("padRight", function() nudge(1, 0, false) end, nil, true)
    ed("padScaleUp", function() scaleBy(S.scaleStep) end, nil, true)
    ed("padScaleDown", function() scaleBy(-S.scaleStep) end, nil, true)
    ed("padHide", toggleHide)
    ed("padReset", reset)
    local function toggleGrid()
        local grid = c.features.grid
        if not grid then return end
        local on = grid.toggleSnap()
        c.settings.grid.snap = on
        c.saveSettings()
        settingsPanel.refresh()
        M.flash(on and "Grid on" or "Grid off")
    end
    ed("toggleGrid", toggleGrid)
    ed("padGrid", toggleGrid)

    -- theme changed: rebuild Frame Mage's own panels in the new style (reopening the editor if it's open)
    local function restyle()
        local wasOpen = active
        -- the Settings panel (and the hidden-elements panel) come back too: a stone picked in Settings shouldn't
        -- close Settings (it reopens on the same tab, where it was)
        local settingsWasOpen = settingsPanel.isOpen()
        local hiddenWasOpen = hidden.isOpen()
        if solo then
            -- Settings open on its own: rebuilt in the new style, staying open
            settingsPanel.restyle()
            settingsPanel.open()
            return
        end
        if wasOpen then close(true) end
        legend.invalidate()
        hidden.restyle()
        settingsPanel.restyle()
        handles.restyle()
        frame.restyle()
        if wasOpen then
            open()
            if settingsWasOpen then settingsPanel.open() end
            if hiddenWasOpen then toggleHiddenPanel() end
        end
    end
    c.events.on("themechanged", restyle)
    c.events.on("stylechanged", restyle) -- e.g. the panel stone: only Frame Mage's own panels change
    c.events.on("profilechanged", function() if active then select(nil); buildList() end end)
    c.events.on("worldchanged", function()
        -- every handle is stale now: drop them without touching anything
        preview.forget()
        frame.forget()
        legend.forget()
        picker.forget()
        mouse.forget()
        handles.forget()
        unitsCache, unitsAt, lastPick = {}, -1, nil
        units.forgetContent()
        hidden.forget()
        settingsPanel.forget()
        inputblock.unblock() -- the player's input subsystem outlives a level change: take our block off it
        rootsCache = nil
        drag = nil
        layout.skipFull = nil
        list, index, selected = {}, 0, nil
        undoStack = {}
        banner.forget()
        if active then
            active = false
            layout.save()
            setEditInput(false)
            log.info("editor closed: world changed")
        end
        if solo then
            solo = false
            setEditInput(false)
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
            local u = unitOf(selected)
            local sw, sh = geometry.screen()
            local r = u and sw and units.contentRect(selected) or geometry.rect(selected)
            local empty = u and u.empty
            -- a notice the preview shows (the game's own entry, at its real size): framed as it is
            local shownNotice = empty and preview.noticeRect(geometry.rect)
            if shownNotice then
                r, empty = shownNotice, false
            elseif empty then
                -- nothing showing: a stand-in where the element will appear, at the size it last showed at;
                -- never seen showing: its own box when the game gives it room to grow into (Item Pickups: a
                -- tall column), else a stand-in of the usual size
                local at = r or u.rect
                local w, h, known = samples.sizeFor(u.key, S.placeholderW, S.placeholderH)
                if known then
                    r = samples.box(at, w, h, sw, sh)
                else
                    r = units.standIn(at, geometry.rect(selected), w, h, sw and sw * sh or 1920 * 1080)
                end
            end
            frame.place(r, S, titleFor(selected), empty)
        else
            frame.place(nil, S)
        end
        -- the hotkey list follows the device in use (keyboard and mouse, or controller)
        if ctx.keys.deviceChanges ~= legendDevice then
            legendDevice = ctx.keys.deviceChanges
            legend.invalidate()
            legend.show(ctx, S)
        end
    end)
    -- dragging and the controller stick need every frame to feel direct
    c.sched.every(16, "editor.drag", dragTick)
    -- the drag bars follow the HUD as panels open, close and move (not while you're dragging one)
    c.sched.every(S.handlesMs, "editor.handles", function()
        if active and not drag then refreshHandles() end
    end)
end

return M
