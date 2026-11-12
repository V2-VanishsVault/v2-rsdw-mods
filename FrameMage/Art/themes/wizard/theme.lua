-- Wizard theme (the magic class): black volcanic glass and arcane blue light - the window frame faceted
-- obsidian with a glowing blue channel and a laser-etched rune in each corner (Ansuz, Kenaz, Algiz, Dagaz). Colors are
-- linear RGB (0..1). Only what differs from Elven is here. The art in ui/ is made by tools/make_theme.py wizard.
return {
    gold = { 0.16, 0.52, 1.00 },          -- highlights (the selected row in lists): arcane blue
    ink = { 0.72, 0.88, 1.00 },           -- lettering on title bars, drag bars and buttons: pale blue light
    heading = { 0.45, 0.75, 1.00 },
    label = { 0.86, 0.88, 0.94 },
    dim = { 0.55, 0.58, 0.66 },
    panelColor = { 0.04, 0.045, 0.07, 0.94 },
    background = "panel_bg_starfield.png",    -- the panels' background when it's the theme's own (settings: stone)
    selectedInk = { 0.80, 0.92, 1.00 },     -- lettering on a selected (grouped) title bar: light on the glass
    -- the level-up celebration: a bright blue number (two tones: fill and outline) on a pulsing blue glow
    celebrate = {
        number = { 0.45, 0.80, 1.00 }, outline = { 0.02, 0.08, 0.30 }, glow = { 0.20, 0.55, 1.00 },
        title = { 0.88, 0.94, 1.00 }, label = { 0.62, 0.84, 1.00 },
        sparks = { { 0.40, 0.75, 1 }, { 0.75, 0.92, 1 }, { 0.20, 0.40, 1 }, { 0.95, 0.97, 1 }, { 0.55, 0.45, 1 } },
    },
    -- the frame: 512px art drawn at 256 units, its corners 96px (the rune plates in them 68px, the band turning
    -- behind), its edges tiled. The band is thicker than Warrior's - 48px of art, its channel 30px in - so it reaches
    -- further out (frameOutset 20). frameLine (where window crests sit) is where the channel is in game, measured: 23.5
    -- units (the frame draws at about 0.8 units per art pixel there, not the 0.5 its frameSize implies)
    frameSize = 256,
    frameMargin = 0.1875,
    frameLine = 23.5,
    frameToEdge = true,
    frameOutset = 20,
    frameDraw = "border",
    panelPad = { 56, 52, 56, 52 },           -- (Frame Mage's own panels: clear of the rune plates, which draw at about
                                             -- 0.8 units per art pixel - ~54 units from the frame's outer edge)
    framePadExtra = 30,
    flourishSize = { 128, 64 },
    flourishLine = 46,
    tipFlourishScale = 0.5,
}
