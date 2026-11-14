-- How the panel looks. With Frame Mage installed it follows Frame Mage's theme: Frame Mage publishes everything the
-- panel needs as data (FrameMage.look: picture paths, slice sizes, colors; FrameMage.lookRev goes up on a change),
-- so no theme logic lives here. Without Frame Mage: the game's own look (the user, 2026-11-14): the panel sits on a
-- real copy of the inventory's window (WBP_Panel_Inventory_C: its stone, its double gold border), with the game's
-- underline under the chosen tab and the game's colors. If that window can't be made, the plain look below: dark
-- glass, a thin gold edge (no pictures).
local game = require("settingspanel.game")
local serialize = require("settingspanel.serialize")

local M = {}

-- Colors are { r, g, b[, a] }, LINEAR (what Unreal takes): a screen color c is about c ^ 2.2, so dark glass at 6 %
-- on screen is 0.005 here. (Picked as screen colors at first, the plain panel showed grey and pale cream.)
M.PLAIN = {
    plain = true,
    ink = { 0.007, 0.005, 0.002 },        -- lettering on a lit button (dark brown on gold)
    titleInk = { 0.007, 0.005, 0.002 },   -- the title, on its gold bar
    heading = { 0.911, 0.57, 0.119 },     -- arrows, paging (gold)
    label = { 0.848, 0.787, 0.674 },      -- ordinary text (warm white)
    dim = { 0.393, 0.355, 0.285 },        -- explanations, notes
    gold = { 0.692, 0.393, 0.064 },       -- the edge, the title bar, a lit button
    button = { 0.047, 0.033, 0.015, 0.97 }, -- an unlit button (dark bronze)
    panelColor = { 0.005, 0.005, 0.006, 0.92 }, -- dark glass
    edge = 2,                             -- the gold edge's width
    panelPad = { 16, 12, 16, 12 },
}

-- The game's look: the inventory window behind everything; text and lines in the game's colors (linear).
M.GAME = {
    plain = true, game = true,
    window = { "WBP_Panel_Inventory_C", "WBP_Panel_C" }, -- the game's window classes to copy, in order
    underline = { image = "SelectionImage", resource = "MI_Menu_Underline" }, -- the inventory tabs' underline
    ink = { 0.012, 0.010, 0.006 },
    titleInk = { 0.69, 0.48, 0.17 },       -- the title, in the window's gold
    heading = { 0.69, 0.48, 0.17 },        -- gold (the window's border)
    label = { 0.62, 0.59, 0.53 },          -- the game's light grey-beige (ARMOUR, counts)
    dim = { 0.30, 0.28, 0.24 },
    gold = { 0.69, 0.48, 0.17 },
    button = { 0.022, 0.019, 0.015, 0.85 }, -- an unlit button: the game's dark slots
    panelColor = { 0.010, 0.010, 0.010, 0.96 },
    edge = 2,
    panelPad = { 30, 18, 30, 24 },          -- inside the window's double border
    titleInset = 16,                        -- the title below the border's top lines
}

local cached, cachedRev

-- The look now: Frame Mage's if it publishes one, else plain. (Re-read only when FrameMage.lookRev changes.)
function M.current()
    local rev = game.get("FrameMage.lookRev")
    if rev == nil then cached, cachedRev = nil, nil return M.GAME end
    if cached and cachedRev == rev then return cached end
    local text = game.get("FrameMage.look")
    local t = type(text) == "string" and serialize.parse(text, "FrameMage.look") or nil
    if type(t) ~= "table" then return M.PLAIN end
    for k, v in pairs(M.PLAIN) do if t[k] == nil and k ~= "plain" then t[k] = v end end
    cached, cachedRev = t, rev
    return t
end

function M.rev() return game.get("FrameMage.lookRev") end

-- Pure: a color table as an FLinearColor.
function M.color(c, alpha)
    c = c or { 1, 1, 1 }
    return { R = c[1], G = c[2], B = c[3], A = alpha or c[4] or 1 }
end
function M.slate(c, alpha) return { SpecifiedColor = M.color(c, alpha), ColorUseRule = 0 } end

local WHITE = { SpecifiedColor = { R = 1, G = 1, B = 1, A = 1 }, ColorUseRule = 0 }

-- Pure: the brush for a texture: kind "box" (9-slice, edges stretched), "border" (9-slice, edges tiled, no
-- center) or "tile".
function M.brush(tex, kind, w, h, margin)
    if kind == "tile" then
        return { ResourceObject = tex, ImageSize = { X = w, Y = h }, DrawAs = 3, Tiling = 3, TintColor = WHITE }
    end
    local mh, mv = margin, margin
    if type(margin) == "table" then mh, mv = margin[1], margin[2] end
    return { ResourceObject = tex, ImageSize = { X = w, Y = h }, DrawAs = kind == "border" and 2 or 1, Tiling = 0,
        TintColor = WHITE, Margin = { Left = mh, Top = mv, Right = mh, Bottom = mv } }
end

-- Pictures load per world context and live only while shown: looked up again for each build.
function M.texture(look, field, cx)
    local path = look[field]
    if type(path) ~= "string" or path == "" or not game.exists(path) then return nil end
    return game.loadPng(path, cx)
end

return M
