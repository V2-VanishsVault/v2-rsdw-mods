-- Demi-human theme: moonstone and wispy gold light (High Elf meets Dwarven). Colors are linear RGB (0..1).
-- Sizes are UI units (1920x1080 reference): the art in ui/ is made at twice these, so it stays sharp.
return {
    gold = { 0.86, 0.66, 0.26 },          -- highlights (the selected row in lists)
    ink = { 1.0, 0.84, 0.52 },            -- lettering on title bars, drag bars and buttons: gold light
    heading = { 0.95, 0.76, 0.40 },
    label = { 0.88, 0.88, 0.92 },
    dim = { 0.58, 0.60, 0.66 },
    panelColor = { 0.07, 0.08, 0.10, 0.94 },
    panelTile = 128,
    frameSize = 64,
    frameMargin = 0.453,                   -- 58 of the frame art's 128 pixels are corner
    panelPad = { 18, 16, 18, 16 },
    titleArt = "title_line.png",
    titleSize = { 128, 32 },
    titleMargin = { 0.25, 0.35 },
    keySize = 64,
    keyMargin = 0.32,
    flourishArt = "panel_flourish.png",   -- centered on a panel's top line
    flourishSize = { 64, 32 },
    flourishLine = 23,                     -- the art's row (UI units) that sits on the panel's top line
    checkArt = "check_mark.png",           -- the tick in a checkbox (drawn at checkSize)
    checkSize = { 32, 32 },
    checkBoxArt = { off = "check_box.png", offHover = "check_box_hover.png", on = "check_box_on.png",
        onHover = "check_box_on_hover.png" },  -- whole checkboxes: the box in the border treatment, with the tick
    tipArt = "tip_band.png",               -- tooltips: a band of dark glass edged top and bottom with light (9-slice)
    tipSize = { 128, 64 },
    tipMargin = { 0.22, 0.19 },            -- the fading ends and the lines stay fixed; the middle stretches
    tipLine = 3,                           -- the lines' distance in from the band's top and bottom (UI units)
    rimArt = { off = "button_rim.png", on = "button_rim_on.png" }, -- our button border alone, over a game button
    rimSize = 32,
    rimMargin = 0.34,
    fieldArt = "title_line.png",           -- text boxes: the same light border as title bars (titleSize / titleMargin)
}
