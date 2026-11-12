-- Frame Mage's own panels in the active theme (core/themes.lua): stone panels with an inlaid frame, gold title
-- plates, themed keycaps. Every piece falls back to a flat color when its art can't be loaded, so the editor
-- always works.
--
-- Panels are layered rather than one stretched picture: the stone is TILED (stays crisp at any size) and the
-- frame is drawn over it as a 9-slice box (corners fixed, edges stretched, center transparent).
local themes = require("framemage.core.themes")

local M = {}

-- The backgrounds players can pick for the panels (settings.stone): the theme's own (its theme.lua `background`),
-- then paintings (tools/make_backgrounds.py), each panel_bg_<name>.png in the theme's ui/ folder (Elven's has them all).
M.STONES = { "theme", "silk", "forge", "leather", "oak", "starfield", "slate", "dragonscale", "parchment", "mists",
    "embers", "abyss", "aurora" }
M.STONE_LABELS = { theme = "Theme's own", silk = "Moonlit silk", forge = "Forge iron", leather = "Battle leather",
    oak = "Weathered oak", starfield = "Starfield", slate = "Slate", dragonscale = "Dragon scale",
    parchment = "Old parchment", mists = "Dark mists", embers = "Ember ash", abyss = "Abyss", aurora = "Aurora" }
-- Used when nothing else is found (a theme with no `background` of its own, a picture missing)
M.FALLBACK = "panel_bg_slate.png"

-- Pure: the tile file for a background name; "theme" = the theme's own (`background` in its style); a painting's is
-- panel_bg_<name>.png; anything else (a background since removed: moonstone, marble, tapestry, glacier) the theme's
-- own too. Unit-tested.
function M.stoneFile(name, st)
    for _, n in ipairs(M.STONES) do
        if n == name and n ~= "theme" then return "panel_bg_" .. name .. ".png" end
    end
    return (st and st.background) or M.FALLBACK
end

-- Pure: the drawn size of a background's tile (UI units): a painting's twice a stone's (its 512 px picture shows its
-- detail at the stones' sharpness, and repeats less often). Unit-tested.
function M.stoneTile(file, panelTile)
    if file and file:sub(1, 9) == "panel_bg_" then return panelTile * 2 end
    return panelTile
end

local ctx

function M.init(c) ctx = c end

local function load(file, worldContext)
    local art = ctx and ctx.features.art
    local path = themes.find("ui/" .. file)
    if not (art and path) then return nil end
    return art.loadFile(path, worldContext)
end

-- The chosen background's tile (falling back to slate) and its drawn size.
local function backgroundTile(worldContext)
    local s = themes.style()
    local file = M.stoneFile(ctx and ctx.settings.stone, s)
    local tex = load(file, worldContext)
    if not tex then file = M.FALLBACK; tex = load(file, worldContext) end
    return tex, M.stoneTile(file, s.panelTile)
end

local WHITE = { SpecifiedColor = { R = 1, G = 1, B = 1, A = 1 }, ColorUseRule = 0 }

-- Pure: the brush table for a texture. kind = "box" (9-slice; margin = number or {h, v}), "border" (9-slice with
-- tiled edges and no center) or "tile".
-- Unit-tested.
function M.brushSpec(tex, kind, w, h, margin)
    if kind == "tile" then
        return { ResourceObject = tex, ImageSize = { X = w, Y = h }, DrawAs = 3, Tiling = 3, TintColor = WHITE }
    end
    local mh, mv = margin, margin
    if type(margin) == "table" then mh, mv = margin[1], margin[2] end
    -- "border": the corners fixed and the edges TILED along their length (the center isn't drawn), so a frame's
    -- detail - wood grain, brushed steel - repeats at its own size instead of being stretched; "box" stretches them
    return { ResourceObject = tex, ImageSize = { X = w, Y = h }, DrawAs = kind == "border" and 2 or 1, Tiling = 0,
        TintColor = WHITE,
        Margin = { Left = mh, Top = mv, Right = mh, Bottom = mv } }
end

local function setBrush(widget, spec)
    local art = ctx and ctx.features.art
    local function go() widget:SetBrush(spec) end
    if art then return art.guarded(go) end
    return pcall(go)
end

-- The theme's title bar behind `border`'s content (title bars, drag bars, buttons): Elven's is a hairline of
-- light round faint dark glass (theme.lua titleArt); older themes can use the solid gold plate. true if art was used.
function M.titlePlate(border, worldContext)
    local s = themes.style()
    local tex = load(s.titleArt or "title_plate.png", worldContext) or load("title_plate.png", worldContext)
    -- (sliced with no stretchy band down the sides: the ornaments at each end sit half way down, and on a button
    -- shorter than the plate that band was squashed to nothing and took them with it)
    local m = s.titleMargin or { 0.25, 0.35 }
    if tex and setBrush(border, M.brushSpec(tex, "box", s.titleSize[1], s.titleSize[2], { m[1], 0.5 })) then
        return true
    end
    pcall(function() border:SetBrushColor(themes.color("gold")) end)
    return false
end

-- A solid gold plate behind `border` (a title bar in the editor's group); true if art was used.
-- Pure: a plate's slice margins: the title bars' sideways, and half its height top and bottom (no middle band to
-- squash: the end ornaments sit in the corners). Unit-tested.
function M.plateMargin(titleMargin)
    local m = titleMargin or { 0.25, 0.35 }
    return { m[1], 0.5 }
end

function M.goldPlate(border, worldContext)
    -- the theme's plate for a selected title bar (ui/plate_selected.png: Elven gold, Warrior polished steel,
    -- Ranger oak), sliced like the title bars; a gold color if there's no art
    local s = themes.style()
    local tex = load("plate_selected.png", worldContext) or load("title_plate.png", worldContext)
    pcall(function() border:SetBrushColor({ R = 1, G = 1, B = 1, A = 1 }) end)
    -- sliced with no stretchy band down the sides: the ornaments at each end (Elven's diamonds, Warrior's
    -- rivets, Ranger's pegs) sit half way down, and on a button shorter than the plate that band was squeezed to
    -- nothing and took them with it
    local m = M.plateMargin(s.titleMargin)
    if tex and setBrush(border, M.brushSpec(tex, "box", s.titleSize[1], s.titleSize[2], m)) then
        return true
    end
    pcall(function() border:SetBrushColor(themes.color("gold")) end)
    return false
end

-- A text button (Settings' Close, value buttons, tabs): filled with the theme's material, like a selected title bar.
M.buttonPlate = function(border, worldContext) return M.goldPlate(border, worldContext) end

-- A filled button's inside: the theme's ornament (ui/plate_ornament.png: a diamond, a rivet, a brass peg) at each
-- end with `content` between them, so the ornaments sit beside the text, never under it, and are always drawn at
-- their own size (baked into the plate, they were stretched with every button's shape). new(cls) makes a widget.
function M.buttonContent(new, content, worldContext)
    local S = ctx and ctx.settings.editor or {}
    local size, gap = S.buttonOrnamentSize or 9, S.buttonOrnamentGap or 6
    local tex = load("plate_ornament.png", worldContext)
    if not tex then return content end
    local row = new("HorizontalBox")
    local function ornament(left)
        local img = new("Image")
        pcall(function()
            img:SetBrush({ ResourceObject = tex, ImageSize = { X = size, Y = size }, DrawAs = 3, Tiling = 0,
                TintColor = WHITE })
        end)
        local sl = row:AddChildToHorizontalBox(img)
        sl:SetVerticalAlignment(2)
        sl:SetPadding(left and { Left = 0, Top = 0, Right = gap, Bottom = 0 } or { Left = gap, Top = 0, Right = 0, Bottom = 0 })
    end
    ornament(true)
    local cs = row:AddChildToHorizontalBox(content)
    cs:SetVerticalAlignment(2)
    cs:SetHorizontalAlignment(2)
    pcall(function() cs:SetSize({ SizeRule = 1, Value = 1 }) end) -- (the content takes the room between them)
    ornament(false)
    return row
end

-- Lettering on a selected title bar (the theme's selectedInk: dark on gold and steel, light on oak).
function M.selectedInk()
    local c = themes.style().selectedInk or { 0.06, 0.04, 0.02 }
    return { R = c[1], G = c[2], B = c[3], A = 1 }
end

-- The game's font for text on plates: ink color.
function M.ink() return themes.color("ink") end
function M.heading() return themes.color("heading") end
function M.label() return themes.color("label") end
function M.dim() return themes.color("dim") end
-- The theme's highlight color, a little brightened (a grouped title bar in the editor).
function M.highlight()
    local c = themes.color("gold")
    return { R = math.min(1, c.R * 1.6 + 0.2), G = math.min(1, c.G * 1.6 + 0.2), B = math.min(1, c.B * 1.6 + 0.2), A = 1 }
end

-- Pure: a panel's content inset: the theme's panelPad, or the caller's own plus the theme's framePadExtra (room
-- for a class theme's wide border and corner pieces). Unit-tested.
function M.panelPadding(pad, s)
    if not pad then return s.panelPad end
    local e = s.framePadExtra or 0
    return { pad[1] + e, pad[2] + e, pad[3] + e, pad[4] + e }
end

-- A stone panel around `content`: returns the outer widget to place. new(cls) makes a widget in your tree.
-- pad = { left, top, right, bottom } overrides the theme's inset.
function M.panel(new, content, worldContext, pad)
    local s = themes.style()
    pad = M.panelPadding(pad, s)
    local stack = new("Overlay")
    local stone, tile = backgroundTile(worldContext)
    local frame = load("panel_frame.png", worldContext)
    local fill = new("Image")
    local tiled = stone and setBrush(fill, M.brushSpec(stone, "tile", tile, tile))
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
        if setBrush(edge, M.brushSpec(frame, s.frameDraw or "box", s.frameSize, s.frameSize, s.frameMargin)) then
            stretch(stack:AddChildToOverlay(edge))
        end
    end
    local cs = stack:AddChildToOverlay(content)
    stretch(cs)
    cs:SetPadding({ Left = pad[1], Top = pad[2], Right = pad[3], Bottom = pad[4] })
    return stack
end

-- Pure: the top padding that puts the flourish's line row (flourishLine, UI units from its top) on a frame's top
-- hairline, which sits `inset` units into the frame art. Unit-tested.
function M.flourishTop(s)
    return M.frameLine(s) - (s.flourishLine or 23)
end

-- Pure: how far in from the frame art's edge its line runs (UI units): the theme's frameLine, or Elven's
-- hairline 7 of its 128 pixels in. Unit-tested.
function M.frameLine(s)
    return s.frameLine or (s.frameSize or 64) * 7 / 128
end

-- Pure: a window frame's slot padding (p = the usual inset, the inventory border's). A theme with frameToEdge
-- (the class themes' wide borders) runs its frame right to the window's edges, using the inset's space for the
-- band rather than covering the window's contents; frameOutset (units) pushes it further out. Unit-tested.
function M.framePadding(p, s)
    s = s or {}
    if s.frameToEdge then p = { Left = 0, Top = 0, Right = 0, Bottom = 0 } end
    local o = s.frameOutset or 0
    return { Left = p.Left - o, Top = p.Top - o, Right = p.Right - o, Bottom = p.Bottom - o }
end

-- The theme's ornament for a panel's top line, as an Image drawn at its own size (nil if the theme has none).
-- Place it centered at the top of the panel with M.flourishTop as its top padding.
-- The flourish as a brush, drawn at its own size; nil if the theme has none.
function M.flourishBrush(worldContext, scale, file)
    local s = themes.style()
    -- (`file`: a flourish of the theme's own for one use - the tooltips' - else its usual one)
    local tex = file and load(file, worldContext)
    tex = tex or (s.flourishArt and load(s.flourishArt, worldContext))
    if not tex then return nil end
    local size = s.flourishSize or { 64, 32 }
    scale = scale or 1
    return { ResourceObject = tex, ImageSize = { X = size[1] * scale, Y = size[2] * scale }, DrawAs = 3, Tiling = 0,
        TintColor = WHITE }
end

function M.flourish(new, worldContext)
    local spec = M.flourishBrush(worldContext)
    if not spec then return nil end
    local img = new("Image")
    if not setBrush(img, spec) then return nil end
    pcall(function() img:SetVisibility(3) end)
    return img
end

-- The panel stone as a brush (tiled), in the player's chosen stone; nil without art.
function M.stoneBrush(worldContext)
    local stone, tile = backgroundTile(worldContext)
    return stone and M.brushSpec(stone, "tile", tile, tile) or nil
end

-- The panel frame (gold light) as a 9-slice brush; nil without art.
function M.frameBrush(worldContext)
    local s = themes.style()
    local frame = load("panel_frame.png", worldContext)
    return frame and M.brushSpec(frame, s.frameDraw or "box", s.frameSize, s.frameSize, s.frameMargin) or nil
end

-- Set a brush the way the art feature expects (so it isn't swapped back); true if it took.
M.setBrush = setBrush

-- A text box (the Border round an EditableText) in the light border of the title bars. true if art was used.
function M.field(border, worldContext)
    local s = themes.style()
    local tex = load(s.fieldArt or s.titleArt or "title_line.png", worldContext)
    if not tex then return false end
    return setBrush(border, M.brushSpec(tex, "box", s.titleSize[1], s.titleSize[2], s.titleMargin)) == true
end

-- The tooltip band (dark glass edged top and bottom with light) as a 9-slice brush; nil without art.
function M.tipBrush(worldContext)
    local s = themes.style()
    local tex = s.tipArt and load(s.tipArt, worldContext)
    if not tex then return nil end
    local size = s.tipSize or { 128, 64 }
    return M.brushSpec(tex, "box", size[1], size[2], s.tipMargin or { 0.22, 0.19 })
end

-- Pure: the padding (top for the top flourish, bottom for the flipped one) that puts a flourish's line on a line
-- `inset` units in from the edge. Flipped upside down, the art's line row is the same distance from the bottom as
-- it was from the top, so the same padding works at both edges. Unit-tested.
function M.flourishPad(s, inset, scale)
    return (inset or 0) - (s.flourishLine or 23) * (scale or 1)
end

-- Our buttons' border on its own (nothing inside), as a 9-slice brush: `on` = the brighter, selected one. nil
-- without art. (Fetched fresh each time it's needed: a loaded texture lives only while something shows it.)
-- w, h = the size to draw it at (the game button's own tile; default the theme's rimSize).
function M.rimBrush(worldContext, on, w, h)
    local s = themes.style()
    local art = s.rimArt
    local tex = art and load(on and art.on or art.off, worldContext)
    if not tex then return nil end
    local size = s.rimSize or 32
    return M.brushSpec(tex, "box", w or size, h or w or size, s.rimMargin or 0.34)
end

-- Pure: which of a checkbox's four pictures to show. Unit-tested.
function M.checkState(checked, hovered)
    if checked then return hovered and "onHover" or "on" end
    return hovered and "offHover" or "off"
end

-- The theme's checkbox pictures as brushes of the given size: { off, offHover, on, onHover }; nil without art.
-- (The game's CheckBox can't be given new pictures from Lua - SetWidgetStyle isn't callable and writing its style
-- in place keeps the old textures - so these are drawn over it, see features/inventory.lua.)
function M.checkBrushes(worldContext, w, h)
    local art = themes.style().checkBoxArt
    if not art then return nil end
    local out = {}
    for k, f in pairs(art) do
        local tex = load(f, worldContext)
        if tex then out[k] = { ResourceObject = tex, ImageSize = { X = w, Y = h }, DrawAs = 3, Tiling = 0, TintColor = WHITE } end
    end
    if not (out.off and out.on) then return nil end
    out.offHover, out.onHover = out.offHover or out.off, out.onHover or out.on
    return out
end

-- The themed keycap texture (or nil: the legend then uses the game's own keycap).
function M.keycap(worldContext) return load("keycap.png", worldContext) end

return M
