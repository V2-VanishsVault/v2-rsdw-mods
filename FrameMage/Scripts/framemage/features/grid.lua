-- Grid: an on-screen grid shown while the editor is open, and the maths for snapping to it.
--
-- The grid is centered on the screen (the center cross is drawn brighter), with a brighter line every
-- `major` cells. Snapping works on what is actually drawn: the selected widget's on-screen rectangle is
-- measured from its cached geometry, and a move goes to the nearest position in that direction where
-- either of its edges sits on a grid line. Left/right-anchored elements both line up naturally.
local M = {}

local ctx, W, log, overlay, G
local host -- { uw, canvas, w, h, axis }
local visible = false
local snapOn = true

-- Pure snapping maths (unit-tested) --------------------------------------------

-- Distance (in drawn units, signed) to move an edge pair [a, b] in direction dir (+1/-1) so that the
-- nearer edge lands on the next grid line beyond where it is now. Lines are at origin + k * cell.
local EPS = 0.25
function M.snapDelta(a, b, dir, cell, origin)
    origin = origin or 0
    local best
    for _, e in ipairs({ a, b }) do
        local t
        if dir > 0 then
            t = origin + (math.floor((e - origin + EPS) / cell) + 1) * cell
        else
            t = origin + (math.ceil((e - origin - EPS) / cell) - 1) * cell
        end
        local d = t - e
        if not best or math.abs(d) < math.abs(best) then best = d end
    end
    return best
end

-- Round an offset to the grid (fallback when geometry can't be measured).
function M.roundTo(v, cell)
    return math.floor(v / cell + 0.5) * cell
end

-- Overlay -------------------------------------------------------------------------

local function viewportSize()
    local ok, w, h = pcall(function()
        local wll = StaticFindObject("/Script/UMG.Default__WidgetLayoutLibrary")
        local pc = FindFirstOf("PlayerController")
        local size = wll:GetViewportSize(pc)
        local scale = wll:GetViewportScale(pc)
        return size.X / scale, size.Y / scale
    end)
    if ok and type(w) == "number" and w > 100 and h > 100 then return w, h end
    return 1920, 1080
end

local function line(tree, canvas, name, vertical, pos, thickness, alpha, color)
    local img = overlay.new("Image", tree, name)
    color = color or G.color
    img:SetColorAndOpacity({ R = color[1], G = color[2], B = color[3], A = alpha })
    local slot = canvas:AddChildToCanvas(img)
    if vertical then
        slot:SetAnchors({ Minimum = { X = 0, Y = 0 }, Maximum = { X = 0, Y = 1 } })
        slot:SetOffsets({ Left = pos - thickness / 2, Top = 0, Right = thickness, Bottom = 0 })
    else
        slot:SetAnchors({ Minimum = { X = 0, Y = 0 }, Maximum = { X = 1, Y = 0 } })
        slot:SetOffsets({ Left = 0, Top = pos - thickness / 2, Right = 0, Bottom = thickness })
    end
end

local function build()
    local w, h = viewportSize()
    -- over the game's HUD but under all of the editor's own layers (handles 19996, hotkey list and hidden-elements
    -- panel 19997, selection frame and Settings 19998, banner 20000), so it never draws across a panel
    local hst = overlay.host("Grid", 19995)
    local cell, major = G.size, G.major
    local cx, cy = w / 2, h / 2
    local n = 0
    local function lines(vertical, center, extent)
        local k = math.ceil(center / cell)
        for i = -k, k do
            local pos = center + i * cell
            if i ~= 0 and pos >= 0 and pos <= extent then -- center axes are drawn last, below
                local alpha = (i % major == 0) and G.majorAlpha or G.minorAlpha
                n = n + 1
                line(hst.tree, hst.canvas, "FM_GridLine_" .. hst.suffix .. "_" .. n, vertical, pos, 1, alpha)
            end
        end
    end
    lines(true, cx, w)
    lines(false, cy, h)
    -- center axes: own color, added last so they draw on top of every crossing grid line. Four arms of short
    -- segments (center -> each edge) so they can carry a gradient and traveling pulses (animateAxes).
    local axis = {}
    for i, s in ipairs(M.axisSegments(cx, cy, w, h, G.centerSegments, G.centerThickness)) do
        local img = overlay.new("Image", hst.tree, "FM_GridAxis_" .. hst.suffix .. "_" .. i)
        local slot = hst.canvas:AddChildToCanvas(img)
        slot:SetPosition({ X = s.x, Y = s.y })
        slot:SetSize({ X = s.w, Y = s.h })
        axis[#axis + 1] = { img = img, t = s.t, last = -1 }
    end
    local dot = overlay.new("Image", hst.tree, "FM_GridDot_" .. hst.suffix)
    local cc = G.centerColor or G.color
    dot:SetColorAndOpacity({ R = cc[1], G = cc[2], B = cc[3], A = 1 })
    local ds = hst.canvas:AddChildToCanvas(dot)
    ds:SetPosition({ X = cx - G.centerDot / 2, Y = cy - G.centerDot / 2 })
    ds:SetSize({ X = G.centerDot, Y = G.centerDot })
    n = n + #axis + 1
    hst.uw:SetVisibility(1) -- collapsed until shown
    host = { uw = hst.uw, canvas = hst.canvas, w = w, h = h, axis = axis }
    M.paintAxes(0)
    log.debug("grid built: %dx%d, %d lines, cell %d", w, h, n, cell)
end

-- Animated center axes ------------------------------------------------------------------------------

-- Pure: the 4 arms (right, left, down, up) cut into n segments each, from the center out to the screen edge.
-- t = how far along the arm the segment's middle is (0 center .. 1 edge). Unit-tested.
function M.axisSegments(cx, cy, w, h, n, thick)
    local out = {}
    local arms = {
        { dx = 1, dy = 0, len = w - cx }, { dx = -1, dy = 0, len = cx },
        { dx = 0, dy = 1, len = h - cy }, { dx = 0, dy = -1, len = cy },
    }
    for _, a in ipairs(arms) do
        local seg = a.len / n
        for i = 0, n - 1 do
            local from, to = i * seg, (i + 1) * seg
            local t = (i + 0.5) / n
            if a.dy == 0 then
                local x = a.dx > 0 and (cx + from) or (cx - to)
                out[#out + 1] = { x = x, y = cy - thick / 2, w = seg, h = thick, t = t }
            else
                local y = a.dy > 0 and (cy + from) or (cy - to)
                out[#out + 1] = { x = cx - thick / 2, y = y, w = thick, h = seg, t = t }
            end
        end
    end
    return out
end

-- Pure: brightness 0..1 at position t for animation phase (in pulses traveled). A gradient that fades
-- toward the edge, with `waves` bright pulses per arm moving outward as phase grows. Unit-tested.
function M.axisLevel(t, phase, g)
    local base = 1 - g.centerFade * t
    local wave = 0.5 + 0.5 * math.cos(2 * math.pi * (t * g.centerWaves - phase))
    local pulse = wave ^ 4 -- narrow bright bands
    return math.max(0, math.min(1, base * (g.centerMinLevel + (1 - g.centerMinLevel) * pulse))), pulse
end

function M.paintAxes(phase)
    if not (host and host.axis) then return end
    local cc, hi = G.centerColor or G.color, G.centerPulseColor or { 1, 1, 1 }
    for _, s in ipairs(host.axis) do
        local level, pulse = M.axisLevel(s.t, phase, G)
        local a = G.centerAlpha * level
        if math.abs(a - s.last) > 0.01 then
            s.last = a
            local k = pulse * 0.5 -- pulses shift toward the highlight color
            pcall(function()
                s.img:SetColorAndOpacity({ R = cc[1] + (hi[1] - cc[1]) * k, G = cc[2] + (hi[2] - cc[2]) * k,
                    B = cc[3] + (hi[3] - cc[3]) * k, A = a })
            end)
        end
    end
end

function M.show()
    if not G.show then return end
    local w, h = viewportSize()
    if not (host and W.valid(host.uw)) or math.abs(w - host.w) > 1 or math.abs(h - host.h) > 1 then
        if host and W.valid(host.uw) then pcall(function() host.uw:RemoveFromParent() end) end
        local ok, err = pcall(build)
        if not ok then log.warn("grid unavailable: %s", tostring(err)); host = nil; return end
    end
    -- (lines show whether or not snapping is on: they have their own toggle, grid.show)
    pcall(function() host.uw:SetVisibility(3) end) -- HitTestInvisible
    visible = true
end

function M.hide()
    if host and W.valid(host.uw) then pcall(function() host.uw:SetVisibility(1) end) end
    visible = false
end

-- Setters (the Settings panel) ------------------------------------------------------------------------------------
function M.setSnap(on)
    snapOn = on and true or false
end
function M.setShowLines(on)
    G.show = on and true or false
    if not G.show then
        M.hide()
    else
        local ed = ctx.features.editor
        if ed and ed.isActive and ed.isActive() then M.show() end -- back on while editing: show them now
    end
end

-- Snap size changed (the Settings panel): rebuild the lines at the new spacing next time it's shown.
function M.setSize(size)
    G.size = size
    if host and W.valid(host.uw) then pcall(function() host.uw:RemoveFromParent() end) end
    host = nil
    if visible then M.show() end
end

function M.isOverlay(w) return overlay.isOurs(w) end
function M.snapping() return snapOn end
function M.cell(big) return big and G.size * G.major or G.size end

function M.toggleSnap()
    snapOn = not snapOn
    return snapOn
end

-- On-screen rectangle of `w` (see core/geometry; the editor frame provides the reference canvas).
function M.measure(w)
    return require("framemage.core.geometry").rect(w)
end

function M.center()
    return (host and host.w or 1920) / 2, (host and host.h or 1080) / 2
end

function M.init(c)
    ctx, W, log = c, c.widgets, c.log
    overlay = require("framemage.core.overlay")
    G = c.settings.grid
    snapOn = G.snap ~= false
    c.events.on("worldchanged", function() host = nil; visible = false end)
    -- animate the center axes while the grid is on screen (costs nothing while it isn't)
    local phase, last = 0, os.clock()
    c.sched.every(G.centerFrameMs, "grid.axes", function()
        local now = os.clock()
        local dt = math.min(now - last, 0.25)
        last = now
        if not (visible and G.centerAnimate and host and W.valid(host.uw)) then return end
        phase = (phase + dt * G.centerSpeed) % 1
        M.paintAxes(phase)
    end)
end

return M
