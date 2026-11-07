-- Selection frame: a thin outline around the selected widget with heavier L-shaped corner brackets.
-- Its full-screen canvas doubles as the geometry reference (core/geometry) while the editor is open.
local overlay = require("framemage.core.overlay")
local W = require("framemage.core.widgets")
local geometry = require("framemage.core.geometry")

local M = {}

local host -- { uw, canvas, edges = {slot...}, corners = {slot...} }

-- Pure: rectangles (x, y, w, h) for the 4 edges and 8 corner bars around rect r. Unit-tested.
function M.pieces(r, edge, corner, len)
    local x, y = r.left, r.top
    local w, h = r.right - r.left, r.bottom - r.top
    len = math.min(len, w / 2 + corner, h / 2 + corner) -- short brackets on tiny widgets
    local o = corner -- brackets sit just outside the outline
    local edges = {
        { x, y - edge, w, edge },          -- top
        { x, y + h, w, edge },             -- bottom
        { x - edge, y - edge, edge, h + 2 * edge }, -- left
        { x + w, y - edge, edge, h + 2 * edge },    -- right
    }
    local corners = {
        { x - o, y - o, len, corner }, { x - o, y - o, corner, len },                 -- top-left
        { x + w + o - len, y - o, len, corner }, { x + w, y - o, corner, len },       -- top-right
        { x - o, y + h, len, corner }, { x - o, y + h + o - len, corner, len },       -- bottom-left
        { x + w + o - len, y + h, len, corner }, { x + w, y + h + o - len, corner, len }, -- bottom-right
    }
    return edges, corners
end

local function bar(h, name, color)
    local img = overlay.new("Image", h.tree, name)
    img:SetColorAndOpacity(color)
    local slot = h.canvas:AddChildToCanvas(img)
    slot:SetAutoSize(false)
    return slot, img
end

local function build(settings)
    local h = overlay.host("Frame", 19998) -- under the banner, over the grid
    local c = settings.frameColor
    local edgeColor = { R = c[1], G = c[2], B = c[3], A = settings.frameEdgeAlpha }
    local cornerColor = { R = c[1], G = c[2], B = c[3], A = 1 }
    local edges, corners, imgs = {}, {}, {}
    for i = 1, 4 do edges[i], imgs[#imgs + 1] = bar(h, "FM_FrameEdge_" .. h.suffix .. "_" .. i, edgeColor) end
    for i = 1, 8 do corners[i], imgs[#imgs + 1] = bar(h, "FM_FrameCorner_" .. h.suffix .. "_" .. i, cornerColor) end
    -- the canvas must fill the screen to serve as the geometry reference
    host = { uw = h.uw, canvas = h.canvas, edges = edges, corners = corners, imgs = imgs }
    geometry.setReference(h.canvas)
end

function M.ensure(settings)
    if host and W.valid(host.uw) then return true end
    local ok, err = pcall(build, settings)
    if not ok then host = nil; return false, err end
    return true
end

local function setVisible(v)
    if host and W.valid(host.uw) then pcall(function() host.uw:SetVisibility(v and 3 or 1) end) end
end

local framesShown = true
local function showPieces(show)
    if framesShown == show or not host then return end
    framesShown = show
    for _, img in ipairs(host.imgs) do
        pcall(function() img:SetVisibility(show and 3 or 1) end)
    end
end

-- Show the editor overlay (canvas visible so geometry works) with no frame drawn yet.
function M.open(settings)
    local ok, err = M.ensure(settings)
    if ok then setVisible(true); showPieces(false) end
    return ok, err
end

function M.close()
    setVisible(false)
end

-- Draw the frame around rect r (viewport units), or hide the pieces when r is nil.
function M.place(r, settings)
    if not (host and W.valid(host.uw)) then return end
    if not r then showPieces(false) return end
    r = geometry.atLeast(r, settings.frameMinSize)
    local edges, corners = M.pieces(r, settings.frameEdge, settings.frameCorner, settings.frameCornerLength)
    local function put(slot, p)
        slot:SetPosition({ X = p[1], Y = p[2] })
        slot:SetSize({ X = math.max(p[3], 0), Y = math.max(p[4], 0) })
    end
    pcall(function()
        for i, p in ipairs(edges) do put(host.edges[i], p) end
        for i, p in ipairs(corners) do put(host.corners[i], p) end
    end)
    showPieces(true)
end

function M.forget()
    host = nil
    framesShown = true
    geometry.setReference(nil)
end

function M.isOurs(w) return overlay.isOurs(w) end

return M
