-- Gold title bars on every movable element while the editor is open, so you can grab one and drag straight away,
-- without selecting it first. The selected element's bar is drawn by editor/frame.lua instead (with its frame).
--
-- Which elements get a bar: the OUTERMOST elements on screen (a panel gets one, the pieces inside it don't, so
-- the screen doesn't drown in bars), skipping full-screen containers and tiny pieces. Bars that would sit on top of
-- each other are moved below their element, or inside its top edge, and left out if there's still no room; those
-- elements can still be clicked, or reached with PgUp / PgDn and Home / End.
local overlay = require("framemage.core.overlay")
local W = require("framemage.core.widgets")
local style = require("framemage.editor.style")

local M = {}

local host -- { uw, canvas, tree, suffix, plates = { {plate, slot, text, title} } }
local placed = {} -- { {widget, rect = {left, top, right, bottom}} } (bars on screen now)
local log, S

-- Pure ---------------------------------------------------------------------------------------------------

local function overlaps(a, b)
    return a.left < b.right and b.left < a.right and a.top < b.bottom and b.top < a.bottom
end
M.overlaps = overlaps

-- Pure: where each element's bar goes. items = { {rect = element rect, w = bar width, h = bar height}, ... } in
-- priority order. Tries above the element's top-left, then below its bottom, then just inside its top edge; a
-- bar that would overlap one already placed (or leave the screen) is skipped. Returns, per item, the bar's rect
-- or false. s = { gap, minTop, screenW, screenH, corner }. Unit-tested.
function M.layout(items, s)
    local out, taken = {}, {}
    for i, it in ipairs(items) do
        local r, x = it.rect, it.rect.left - (s.corner or 0)
        local tries = {
            r.top - (s.corner or 0) - s.gap - it.h,  -- above
            r.bottom + (s.corner or 0) + s.gap,      -- below
            r.top + 2,                               -- inside the top edge
        }
        x = math.max(0, math.min(x, s.screenW - it.w))
        out[i] = false
        for _, y in ipairs(tries) do
            local bar = { left = x, top = y, right = x + it.w, bottom = y + it.h }
            local onScreen = y >= s.minTop and bar.bottom <= s.screenH
            local free = onScreen
            if free then
                for _, t in ipairs(taken) do
                    if overlaps(bar, t) then free = false break end
                end
            end
            if free then
                out[i] = bar
                taken[#taken + 1] = bar
                break
            end
        end
    end
    return out
end

-- Pure: estimated bar size for a title (used until the real size can be measured).
function M.estimate(title, fontSize, padX, padY)
    return #title * fontSize * 0.56 + 2 * padX, fontSize * 1.35 + 2 * padY
end

-- Widgets ------------------------------------------------------------------------------------------------

local function ensure()
    if host and W.valid(host.uw) then return true end
    local ok, err = pcall(function()
        local h = overlay.host("Handles", 19996) -- under the hotkey list and the selection frame
        host = { uw = h.uw, canvas = h.canvas, tree = h.tree, suffix = h.suffix, plates = {} }
    end)
    if not ok then log.warn("drag bars unavailable: %s", tostring(err)); host = nil end
    return ok
end

local function plateAt(i)
    local p = host.plates[i]
    if p then return p end
    local plate = overlay.new("Border", host.tree, "FM_Handle_" .. host.suffix .. "_" .. i)
    style.titlePlate(plate, host.uw)
    pcall(function() plate:SetRenderOpacity(S.handleAlpha) end)
    plate:SetPadding({ Left = S.handlePadX, Top = S.handlePadY, Right = S.handlePadX, Bottom = S.handlePadY })
    local text = overlay.new("TextBlock", host.tree, "FM_HandleText_" .. host.suffix .. "_" .. i)
    local font = require("framemage.editor.legend").gameFont()
    if font then
        pcall(function() text:SetFont({ FontObject = font.FontObject, TypefaceFontName = font.TypefaceFontName, Size = S.handleFontSize }) end)
    end
    text:SetColorAndOpacity({ SpecifiedColor = style.ink(), ColorUseRule = 0 })
    plate:SetContent(text)
    local slot = host.canvas:AddChildToCanvas(plate)
    slot:SetAutoSize(true)
    p = { plate = plate, slot = slot, text = text, title = nil }
    host.plates[i] = p
    return p
end

-- The bar's real size for a title: set the text, lay it out, read its desired size (falls back to an estimate).
local sizes = {} -- title -> { w, h }
local function sizeOf(p, title)
    if p.title ~= title then
        p.title = title
        pcall(function() p.text:SetText(FText(title)) end)
    end
    local known = sizes[title]
    if known then return known[1], known[2] end
    local ok, d = pcall(function()
        p.plate:ForceLayoutPrepass()
        return p.plate:GetDesiredSize()
    end)
    if ok and d and d.X and d.X > 1 and d.Y > 1 then
        sizes[title] = { d.X, d.Y }
        return d.X, d.Y
    end
    return M.estimate(title, S.handleFontSize, S.handlePadX, S.handlePadY)
end

-- Show bars for targets = { {widget, rect, title}, ... } (priority order). screen = { w, h }.
function M.show(targets, screenW, screenH)
    if not ensure() then return end
    local items = {}
    for i, t in ipairs(targets) do
        local p = plateAt(i)
        local w, h = sizeOf(p, t.title)
        items[i] = { rect = t.rect, w = w, h = h }
    end
    local bars = M.layout(items, { gap = S.titleGap, minTop = S.titleMinTop, corner = S.frameCorner,
        screenW = screenW, screenH = screenH })
    placed = {}
    for i, p in ipairs(host.plates) do
        local bar = bars[i]
        pcall(function()
            if bar then
                p.slot:SetPosition({ X = bar.left, Y = bar.top })
                p.plate:SetVisibility(3)
            else
                p.plate:SetVisibility(1)
            end
        end)
        if bar then placed[#placed + 1] = { widget = targets[i].widget, rect = bar } end
    end
    pcall(function() host.uw:SetVisibility(3) end)
end

function M.hide()
    placed = {}
    if host and W.valid(host.uw) then pcall(function() host.uw:SetVisibility(1) end) end
end

-- The element whose bar is under (x, y), or nil. Bars never overlap, so there is at most one.
function M.at(x, y)
    for _, b in ipairs(placed) do
        local r = b.rect
        if x >= r.left and x <= r.right and y >= r.top and y <= r.bottom and W.valid(b.widget) then
            return b.widget
        end
    end
    return nil
end

function M.count() return #placed end

-- World changed: every handle is stale.
function M.forget() host = nil; placed = {}; sizes = {} end

-- Theme changed: rebuild the bars in the new style on the next refresh.
function M.restyle()
    if host and W.valid(host.uw) then pcall(function() host.uw:RemoveFromParent() end) end
    M.forget()
end

function M.init(c, settings) log, S = c.log, settings end

return M
