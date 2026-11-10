-- Warrior theme (the melee class): sharp, angular, forged - cut corners, every border polished steel with a red
-- inlay. Colors are linear RGB (0..1). Only what differs from Demi-human is here; everything else (sizes, the
-- stones) comes from it. The art in ui/ is made by tools/make_theme.py warrior, at Demi-human's sizes and margins.
return {
    gold = { 0.78, 0.12, 0.08 },          -- highlights (the selected row in lists): warrior red
    ink = { 1.0, 0.62, 0.50 },            -- lettering on title bars, drag bars and buttons: ember light
    heading = { 0.96, 0.40, 0.30 },
    label = { 0.88, 0.86, 0.86 },
    dim = { 0.60, 0.56, 0.56 },
    panelColor = { 0.08, 0.06, 0.06, 0.94 },
    selectedInk = { 0.06, 0.06, 0.07 },     -- lettering on a selected (grouped) title bar: dark on the steel
    -- the level-up celebration: a red number (two tones: fill and outline) on a pulsing red glow, sparks to match
    celebrate = {
        number = { 1.00, 0.24, 0.16 }, outline = { 0.28, 0.02, 0.02 }, glow = { 1.00, 0.16, 0.08 },
        title = { 1.00, 0.88, 0.85 }, label = { 1.00, 0.62, 0.55 },
        sparks = { { 1, 0.25, 0.15 }, { 1, 0.55, 0.20 }, { 0.92, 0.92, 0.96 }, { 0.75, 0.05, 0.05 }, { 1, 0.80, 0.60 } },
    },
    -- the wide border: 512px art drawn at 256 units, wrapping round each window - from its edge (frameToEdge) out
    -- 10 units more (frameOutset), so the band's inner edge sits about where Demi-human's line does and never
    -- covers a window's contents - its corners 48 units and its edges tiled, not stretched (frameDraw "border")
    frameSize = 256,
    frameMargin = 0.1875,
    frameLine = 9,
    frameToEdge = true,
    frameOutset = 10,
    frameDraw = "border",
    panelPad = { 40, 36, 40, 36 },         -- Frame Mage's own panels: their contents clear the band and corners
    framePadExtra = 26,                    -- (and panels with their own inset get this much more)
    flourishSize = { 128, 64 },            -- the flourish at twice Demi-human's size, to match
    flourishLine = 46,
    tipFlourishScale = 0.5,                -- tooltips keep a small one
}
