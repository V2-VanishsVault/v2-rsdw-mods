-- Frame Mage's own panels in the active theme (core/themes.lua): stone panels with an inlaid frame, gold title
-- plates, themed keycaps. Every piece falls back to a flat colour when its art can't be loaded, so the editor
-- always works.
--
-- Panels are layered rather than one stretched picture: the stone is TILED (stays crisp at any size) and the
-- frame is drawn over it as a 9-slice box (corners fixed, edges stretched, centre transparent).
local themes = require("framemage.core.themes")

local M = {}

-- The stones players can pick for the panels (settings.stone), and their tile in the theme's ui/ folder.
M.STONES = { "moonstone", "slate", "marble" }
M.STONE_LABELS = { moonstone = "Moonstone", slate = "Slate", marble = "Black marble" }
local STONE_FILES = { moonstone = "panel_stone.png", slate = "panel_stone_slate.png", marble = "panel_stone_marble.png" }

-- Pure: the tile file for a stone name (unknown names get the theme's default stone). Unit-tested.
function M.stoneFile(name) return STONE_FILES[name] or "panel_stone.png" end

local ctx

function M.init(c) ctx = c end

local function load(file, worldContext)
    local art = ctx and ctx.features.art
    local path = themes.find("ui/" .. file)
    if not (art and path) then return nil end
    return art.loadFile(path, worldContext)
end

local WHITE = { SpecifiedColor = { R = 1, G = 1, B = 1, A = 1 }, ColorUseRule = 0 }

-- Pure: the brush table for a texture. kind = "box" (9-slice; margin = number or {h, v}) or "tile".
-- Unit-tested.
function M.brushSpec(tex, kind, w, h, margin)
    if kind == "tile" then
        return { ResourceObject = tex, ImageSize = { X = w, Y = h }, DrawAs = 3, Tiling = 3, TintColor = WHITE }
    end
    local mh, mv = margin, margin
    if type(margin) == "table" then mh, mv = margin[1], margin[2] end
    return { ResourceObject = tex, ImageSize = { X = w, Y = h }, DrawAs = 1, Tiling = 0, TintColor = WHITE,
        Margin = { Left = mh, Top = mv, Right = mh, Bottom = mv } }
end

local function setBrush(widget, spec)
    local art = ctx and ctx.features.art
    local function go() widget:SetBrush(spec) end
    if art then return art.guarded(go) end
    return pcall(go)
end

-- The theme's title bar behind `border`'s content (title bars, drag bars, buttons): Demi-human's is a hairline of
-- light round faint dark glass (theme.lua titleArt); older themes can use the solid gold plate. true if art was used.
function M.titlePlate(border, worldContext)
    local s = themes.style()
    local tex = load(s.titleArt or "title_plate.png", worldContext) or load("title_plate.png", worldContext)
    if tex and setBrush(border, M.brushSpec(tex, "box", s.titleSize[1], s.titleSize[2], s.titleMargin)) then
        return true
    end
    pcall(function() border:SetBrushColor(themes.color("gold")) end)
    return false
end

-- The game's font for text on plates: ink colour.
function M.ink() return themes.color("ink") end
function M.heading() return themes.color("heading") end
function M.label() return themes.color("label") end
function M.dim() return themes.color("dim") end

-- A stone panel around `content`: returns the outer widget to place. new(cls) makes a widget in your tree.
-- pad = { left, top, right, bottom } overrides the theme's inset.
function M.panel(new, content, worldContext, pad)
    local s = themes.style()
    pad = pad or s.panelPad
    local stack = new("Overlay")
    local stone = load(M.stoneFile(ctx and ctx.settings.stone), worldContext) or load("panel_stone.png", worldContext)
    local frame = load("panel_frame.png", worldContext)
    local fill = new("Image")
    local tiled = stone and setBrush(fill, M.brushSpec(stone, "tile", s.panelTile, s.panelTile))
    if not tiled then
        pcall(function()
            local c = s.panelColor
            fill:SetColorAndOpacity({ R = c[1], G = c[2], B = c[3], A = c[4] or 1 })
        end)
        if stone then pcall(function() fill:SetBrushFromTexture(stone, false) end) end
    end
    local function stretch(slot)
        slot:SetHorizontalAlignment(0)
        slot:SetVerticalAlignment(0)
    end
    stretch(stack:AddChildToOverlay(fill))
    if frame then
        local edge = new("Image")
        if setBrush(edge, M.brushSpec(frame, "box", s.frameSize, s.frameSize, s.frameMargin)) then
            stretch(stack:AddChildToOverlay(edge))
        end
    end
    local cs = stack:AddChildToOverlay(content)
    stretch(cs)
    cs:SetPadding({ Left = pad[1], Top = pad[2], Right = pad[3], Bottom = pad[4] })
    return stack
end

-- The themed keycap texture (or nil: the legend then uses the game's own keycap).
function M.keycap(worldContext) return load("keycap.png", worldContext) end

return M
