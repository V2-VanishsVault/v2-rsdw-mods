-- Grid: an on-screen grid shown while the editor is open, and the maths for snapping to it.
--
-- The grid is centred on the screen (the centre cross is drawn brighter), with a brighter line every
-- `major` cells. Snapping works on what is actually drawn: the selected widget's on-screen rectangle is
-- measured from its cached geometry, and a move goes to the nearest position in that direction where
-- either of its edges sits on a grid line. Left/right-anchored elements both line up naturally.
local M = {}

local ctx, W, log, overlay, G
local host -- { uw, canvas, w, h }
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
    local hst = overlay.host("Grid", 19999) -- just under the editor banner
    local cell, major = G.size, G.major
    local cx, cy = w / 2, h / 2
    local n = 0
    local function lines(vertical, centre, extent)
        local k = math.ceil(centre / cell)
        for i = -k, k do
            local pos = centre + i * cell
            if i ~= 0 and pos >= 0 and pos <= extent then -- centre axes are drawn last, below
                local alpha = (i % major == 0) and G.majorAlpha or G.minorAlpha
                n = n + 1
                line(hst.tree, hst.canvas, "FF_GridLine_" .. hst.suffix .. "_" .. n, vertical, pos, 1, alpha)
            end
        end
    end
    lines(true, cx, w)
    lines(false, cy, h)
    -- centre axes: own colour, thicker, added last so they draw on top of every crossing grid line
    local cc = G.centreColor or G.color
    line(hst.tree, hst.canvas, "FF_GridAxisV_" .. hst.suffix, true, cx, G.centreThickness, G.centreAlpha, cc)
    line(hst.tree, hst.canvas, "FF_GridAxisH_" .. hst.suffix, false, cy, G.centreThickness, G.centreAlpha, cc)
    n = n + 2
    hst.uw:SetVisibility(1) -- collapsed until shown
    host = { uw = hst.uw, canvas = hst.canvas, w = w, h = h }
    log.debug("grid built: %dx%d, %d lines, cell %d", w, h, n, cell)
end

function M.show()
    if not G.show then return end
    local w, h = viewportSize()
    if not (host and W.valid(host.uw)) or math.abs(w - host.w) > 1 or math.abs(h - host.h) > 1 then
        if host and W.valid(host.uw) then pcall(function() host.uw:RemoveFromParent() end) end
        local ok, err = pcall(build)
        if not ok then log.warn("grid unavailable: %s", tostring(err)); host = nil; return end
    end
    pcall(function() host.uw:SetVisibility(snapOn and 3 or 1) end) -- HitTestInvisible / Collapsed
end

function M.hide()
    if host and W.valid(host.uw) then pcall(function() host.uw:SetVisibility(1) end) end
end

function M.isOverlay(w) return overlay.isOurs(w) end
function M.snapping() return snapOn end
function M.cell(big) return big and G.size * G.major or G.size end

function M.toggleSnap()
    snapOn = not snapOn
    M.show()
    return snapOn
end

-- On-screen rectangle of `w` (see core/geometry; the editor frame provides the reference canvas).
function M.measure(w)
    return require("forgeframe.core.geometry").rect(w)
end

function M.centre()
    return (host and host.w or 1920) / 2, (host and host.h or 1080) / 2
end

function M.init(c)
    ctx, W, log = c, c.widgets, c.log
    overlay = require("forgeframe.core.overlay")
    G = c.settings.grid
    snapOn = G.snap ~= false
    c.events.on("worldchanged", function() host = nil end)
end

return M
