-- Selection frame: a thin outline around the selected widget with heavier L-shaped corner brackets, and a gold
-- title bar (black text, padded) naming it, which is the handle you click and drag to move the widget.
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

-- Pure: where the title bar goes for frame rect r: above the top-left corner, or below the frame when there
-- isn't room above (the top of the screen). Returns x, y. Unit-tested.
function M.barPosition(r, barHeight, s)
    local x = r.left - s.frameCorner
    local above = r.top - s.frameCorner - s.titleGap - barHeight
    if above >= s.titleMinTop then return x, above end
    return x, r.bottom + s.frameCorner + s.titleGap
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
    -- title bar: gold plate, black lettering in the game's font
    local plate = overlay.new("Border", h.tree, "FM_TitleBar_" .. h.suffix)
    require("framemage.editor.style").titlePlate(plate, h.uw)
    plate:SetPadding({ Left = settings.titlePadX, Top = settings.titlePadY, Right = settings.titlePadX, Bottom = settings.titlePadY })
    local label = overlay.new("TextBlock", h.tree, "FM_TitleText_" .. h.suffix)
    local font = require("framemage.editor.legend").gameFont()
    if font then
        pcall(function() label:SetFont({ FontObject = font.FontObject, TypefaceFontName = font.TypefaceFontName, Size = settings.titleFontSize }) end)
    end
    label:SetColorAndOpacity({ SpecifiedColor = require("framemage.editor.style").ink(), ColorUseRule = 0 })
    plate:SetContent(label)
    local barSlot = h.canvas:AddChildToCanvas(plate)
    barSlot:SetAutoSize(true)
    imgs[#imgs + 1] = plate
    -- stand-in for an element with nothing showing (an empty list, a bar at zero): a faint stone panel saying
    -- what goes there, so it can still be seen, placed and moved
    local style = require("framemage.editor.style")
    local n = 0
    local function new(cls)
        n = n + 1
        return overlay.new(cls, h.tree, "FM_Placeholder_" .. cls .. "_" .. h.suffix .. "_" .. n)
    end
    local phText = new("TextBlock")
    if font then
        pcall(function() phText:SetFont({ FontObject = font.FontObject, TypefaceFontName = font.TypefaceFontName, Size = 13 }) end)
    end
    phText:SetColorAndOpacity({ SpecifiedColor = style.label(), ColorUseRule = 0 })
    local phBox = new("SizeBox")
    pcall(function() phBox:SetClipping(1) end)
    phBox:SetContent(phText)
    -- (plain dark glass, no window frame: the theme's frame art squeezed into a small box showed a crushed copy
    -- of the whole frame; the selection's own corners already outline it)
    local ph = new("Border")
    local pc = require("framemage.core.themes").style().panelColor or { 0.03, 0.03, 0.04, 0.94 }
    pcall(function()
        ph:SetBrushColor({ R = pc[1], G = pc[2], B = pc[3], A = 0.7 })
        ph:SetPadding({ Left = 12, Top = 10, Right = 12, Bottom = 10 })
        ph:SetHorizontalAlignment(2)
        ph:SetVerticalAlignment(2)
    end)
    ph:SetContent(phBox)
    pcall(function() phText:SetJustification(1) end)
    local phSlot = h.canvas:AddChildToCanvas(ph)
    phSlot:SetAutoSize(false)
    ph:SetVisibility(1)
    -- the canvas must fill the screen to serve as the geometry reference
    host = { uw = h.uw, canvas = h.canvas, edges = edges, corners = corners, imgs = imgs,
        bar = plate, barSlot = barSlot, barText = label, title = nil, ph = ph, phSlot = phSlot, phText = phText }
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

-- Draw the frame around rect r (viewport units) with `title` on its bar, or hide the pieces when r is nil.
-- empty = the element shows nothing right now: a stand-in panel fills r.
function M.place(r, settings, title, empty)
    if not (host and W.valid(host.uw)) then return end
    pcall(function()
        if r and empty then
            host.phSlot:SetPosition({ X = r.left, Y = r.top })
            host.phSlot:SetSize({ X = r.right - r.left, Y = r.bottom - r.top })
            if host.phTitle ~= title then
                host.phTitle = title
                host.phText:SetText(FText((title or "This element") .. " appears here when the game shows it"))
                pcall(function() host.phText:SetAutoWrapText(true) end)
            end
            host.ph:SetVisibility(3)
        else
            host.ph:SetVisibility(1)
        end
    end)
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
    if title and title ~= host.title then
        host.title = title
        pcall(function() host.barText:SetText(FText(title)) end)
    end
    local barRect = geometry.rect(host.bar)
    local barH = (barRect and barRect.bottom > barRect.top) and (barRect.bottom - barRect.top) or settings.titleFontSize + 2 * settings.titlePadY + 6
    local bx, by = M.barPosition(r, barH, settings)
    pcall(function() host.barSlot:SetPosition({ X = bx, Y = by }) end)
    showPieces(true)
end

-- The title bar's on-screen rectangle (for hit-testing the drag handle), or nil.
function M.barRect()
    if not (host and W.valid(host.bar) and framesShown) then return nil end
    return geometry.rect(host.bar)
end

-- Theme changed: drop the overlay; the next open builds it in the new style.
function M.restyle()
    if host and W.valid(host.uw) then pcall(function() host.uw:RemoveFromParent() end) end
    host = nil
    framesShown = true
end

function M.forget()
    host = nil
    framesShown = true
    geometry.setReference(nil)
end

function M.isOurs(w) return overlay.isOurs(w) end

return M
