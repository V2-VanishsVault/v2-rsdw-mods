-- Dwarven theme (the forge): hammered bronze and dark iron, knotwork, a channel of molten amber. Colors are linear
-- RGB (0..1). Only what differs from Elven is here; everything else (sizes, the stones) comes from it. The art in
-- ui/ is made by tools/make_theme.py dwarven.
return {
    gold = { 0.92, 0.48, 0.10 },          -- highlights (the selected row in lists): forge amber
    ink = { 1.0, 0.78, 0.46 },            -- lettering on title bars, drag bars and buttons: firelight
    heading = { 1.0, 0.62, 0.24 },
    label = { 0.90, 0.86, 0.80 },
    dim = { 0.62, 0.57, 0.50 },
    panelColor = { 0.07, 0.05, 0.035, 0.94 },
    background = "panel_bg_forge.png",    -- the panels' background when it's the theme's own (settings: stone)
    selectedInk = { 0.08, 0.04, 0.01 },     -- lettering on a selected (grouped) title bar: dark on the bronze
    -- the level-up celebration: a molten number (two tones: fill and outline) on a pulsing amber glow, sparks to match
    celebrate = {
        number = { 1.00, 0.62, 0.14 }, outline = { 0.26, 0.08, 0.01 }, glow = { 1.00, 0.40, 0.04 },
        title = { 1.00, 0.92, 0.78 }, label = { 1.00, 0.72, 0.40 },
        sparks = { { 1, 0.55, 0.10 }, { 1, 0.80, 0.30 }, { 1, 0.95, 0.75 }, { 0.85, 0.25, 0.02 }, { 0.70, 0.45, 0.20 } },
    },
    -- the frame: painted (tools/painted_art.py over an exact template), 512px art drawn at 256 units; a thick band
    -- wrapping round each window from its edge out 20 units more (frameOutset), smaller plates over its corners,
    -- its sides tiled (frameDraw "border"). frameLine is where its inlay runs in game (0.78 units per art pixel)
    frameSize = 256,
    frameMargin = 0.1875,
    frameLine = 26.6,
    frameToEdge = true,
    frameOutset = 20,
    frameDraw = "border",
    panelPad = { 56, 52, 56, 52 },         -- Frame Mage's own panels: their contents clear the band and the plates
    framePadExtra = 30,                    -- (and panels with their own inset get this much more)
    flourishSize = { 128, 64 },            -- the crest at twice Elven's size, to match
    flourishLine = 46,
    tipFlourishScale = 0.5,                -- tooltips keep a small one
}
