-- Ranger theme (the ranged class): of the woods - rounded corners, every border grained wood with a green inlay,
-- leaves for ornament. Colors are linear RGB (0..1). Only what differs from Elven is here; everything else
-- (sizes, the stones) comes from it. The art in ui/ is made by tools/make_theme.py ranger, at Elven's sizes.
return {
    gold = { 0.22, 0.58, 0.18 },          -- highlights (the selected row in lists): ranger green
    ink = { 0.80, 1.0, 0.64 },            -- lettering on title bars, drag bars and buttons: leaf light
    heading = { 0.58, 0.88, 0.42 },
    label = { 0.90, 0.88, 0.82 },
    dim = { 0.60, 0.58, 0.50 },
    panelColor = { 0.07, 0.07, 0.05, 0.94 },
    background = "panel_bg_oak.png",    -- the panels' background when it's the theme's own (settings: stone)
    selectedInk = { 0.98, 0.93, 0.82 },     -- lettering on a selected (grouped) title bar: light on the oak
    -- the level-up celebration: a green number (two tones: fill and outline) on a pulsing green glow, sparks to match
    celebrate = {
        number = { 0.58, 0.94, 0.36 }, outline = { 0.04, 0.17, 0.04 }, glow = { 0.36, 0.88, 0.24 },
        title = { 0.92, 0.98, 0.84 }, label = { 0.76, 0.96, 0.60 },
        sparks = { { 0.58, 0.94, 0.36 }, { 0.96, 0.86, 0.42 }, { 0.30, 0.72, 0.26 }, { 0.92, 1, 0.82 }, { 0.78, 0.56, 0.30 } },
    },
    -- the frame: painted (tools/painted_art.py over an exact template), 512px art drawn at 256 units; a thick band
    -- (48px of art) wrapping round each window from its edge out 20 units more (frameOutset), smaller plates over its
    -- corners, its sides tiled (frameDraw "border"). frameLine is where its inlay runs in game: the painting puts it
    -- 24px in, and the frame draws at about 0.78 units per art pixel (measured for the Wizard)
    frameSize = 256,
    frameMargin = 0.1875,
    frameLine = 18.8,
    frameToEdge = true,
    frameOutset = 20,
    frameDraw = "border",
    panelPad = { 56, 52, 56, 52 },         -- Frame Mage's own panels: their contents clear the band and the plates
    framePadExtra = 30,                    -- (and panels with their own inset get this much more)
    flourishSize = { 128, 64 },            -- the flourish at twice Elven's size, to match
    flourishLine = 46,
    tipFlourishScale = 0.5,                -- tooltips keep a small one
}
