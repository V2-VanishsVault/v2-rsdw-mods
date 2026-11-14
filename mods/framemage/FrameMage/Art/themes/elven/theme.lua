-- Elven theme: antique silver filigree and moonstone. Colors are linear RGB (0..1).
-- Sizes are UI units (1920x1080 reference): the art in ui/ is made at twice these, so it stays sharp.
return {
    gold = { 0.40, 0.76, 0.78 },          -- highlights (the selected row in lists): moonstone
    ink = { 0.86, 0.97, 1.0 },            -- lettering on title bars, drag bars and buttons: moonlight
    heading = { 0.72, 0.92, 0.94 },
    label = { 0.88, 0.88, 0.92 },
    dim = { 0.58, 0.60, 0.66 },
    panelColor = { 0.07, 0.08, 0.10, 0.94 },
    background = "panel_bg_silk.png",    -- the panels' background when it's the theme's own (settings: stone)
    panelTile = 128,
    titleArt = "title_line.png",
    titleSize = { 128, 32 },
    titleMargin = { 0.25, 0.35 },
    keySize = 64,
    keyMargin = 0.32,
    flourishArt = "panel_flourish.png",   -- centered on a panel's top line
    checkArt = "check_mark.png",           -- the tick in a checkbox (drawn at checkSize)
    checkSize = { 32, 32 },
    checkBoxArt = { off = "check_box.png", offHover = "check_box_hover.png", on = "check_box_on.png",
        onHover = "check_box_on_hover.png" },  -- whole checkboxes: the box in the border treatment, with the tick
    tipArt = "tip_band.png",               -- tooltips: a band of dark glass edged top and bottom with light (9-slice)
    tipSize = { 128, 64 },
    tipMargin = { 0.22, 0.19 },            -- the fading ends and the lines stay fixed; the middle stretches
    tipLine = 6,                           -- the lines' distance in from the band's top and bottom (UI units: the game
                                           -- sizes the band's slices by its art's own pixels, and the lines are 6px in)
    rimArt = { off = "button_rim.png", on = "button_rim_on.png" }, -- our button border alone, over a game button
    rimSize = 32,
    rimMargin = 0.34,
    fieldArt = "title_line.png",           -- text boxes: the same light border as title bars (titleSize / titleMargin)
    -- the frame: painted (tools/painted_art.py over an exact template), 512px art drawn at 256 units; a thick band
    -- wrapping round each window from its edge out 20 units more (frameOutset), smaller plates over its corners,
    -- its sides tiled (frameDraw "border"). frameLine is where its inlay runs in game (0.78 units per art pixel)
    frameSize = 256,
    frameMargin = 0.1875,
    frameLine = 21.1,
    frameToEdge = true,
    frameOutset = 20,
    frameDraw = "border",
    panelPad = { 56, 52, 56, 52 },         -- Frame Mage's own panels: their contents clear the band and the plates
    framePadExtra = 30,                    -- (and panels with their own inset get this much more)
    flourishSize = { 128, 64 },            -- the crest
    flourishLine = 46,
    tipFlourishScale = 0.5,                -- tooltips keep a small one
    selectedInk = { 0.04, 0.05, 0.07 },    -- lettering on a selected (grouped) title bar: dark on the silver
    -- the level-up celebration: a silver number (two tones: fill and outline) on a pulsing moonstone glow
    celebrate = {
        number = { 0.90, 0.94, 1.00 }, outline = { 0.06, 0.10, 0.14 }, glow = { 0.46, 0.96, 0.94 },
        title = { 0.96, 1.00, 0.98 }, label = { 0.72, 0.94, 0.94 },
        sparks = { { 0.86, 0.90, 0.96 }, { 0.62, 1, 0.96 }, { 1, 1, 1 }, { 0.40, 0.80, 0.82 }, { 0.70, 0.74, 0.80 } },
    },
}
