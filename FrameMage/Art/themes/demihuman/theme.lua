-- Demi-human theme: moonstone and wispy gold light (High Elf meets Dwarven). Colours are linear RGB (0..1).
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
}
