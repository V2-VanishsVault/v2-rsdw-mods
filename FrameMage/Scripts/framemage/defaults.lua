-- Default settings. Users edit Mods/FrameMage/config/settings.lua; missing keys fall back to these.
-- Key names are Unreal key names (F9, PageUp, Left, Equals, LeftBracket, LeftMouseButton ...); the older UE4SS
-- names (PAGE_UP, OEM_PLUS ...) also work. Modifiers: CTRL, SHIFT, ALT.
return {
    enabled = true, -- master switch (also in Mod Menu); off hands everything back to the game
    logLevel = "info", -- debug | info | warn | error

    -- Turn a feature off to isolate a problem (e.g. a crash). Removed/false features never load.
    features = { layout = true, art = true, materials = true, grid = true, editor = true, inspector = true,
        share = true, celebrate = true, replace = true, modmenu = true },

    -- Frame Mage's own widgets shown instead of the game's (features/replace.lua)
    replace = {
        levelUp = true, -- level-up popup -> fireworks celebration
    },

    celebrate = {
        centreY = 0.36, -- vertical position, fraction of the screen from the top
        duration = 3.4, -- seconds, including the fade-out
        outro = 0.45,
        zoomTime = 0.65,
        zoomFrom = 3.2, -- the number starts this many times larger
        numberSize = 120,
        titleSize = 34,
        labelSize = 26,
        iconSize = 56,
        glowSize = 420,
        sparkSize = 18,
        bursts = 5,
        perBurst = 30,
        burstTimes = { 0.12, 0.42, 0.72, 1.02, 1.38 },
        spreadMinX = 220, spreadMaxX = 520, -- burst centres, UI units from the middle
        spreadMinY = 60, spreadMaxY = 300,
        speedMin = 220, speedMax = 520,
        lifeMin = 1.1, lifeMax = 1.7,
        gravity = 240,
        drag = 1.3,
        flashSize = 200, -- bright bloom where each burst goes off
        flashTime = 0.35,
        palette = { { 1, 0.82, 0.36 }, { 1, 0.45, 0.25 }, { 0.55, 0.85, 1 }, { 1, 0.95, 0.8 }, { 0.85, 0.5, 1 } },
        frameMs = 33, -- 30 updates a second: smooth for sparks, half the cost of 60
    },

    profile = "default", -- layouts/<profile>.lua
    profiles = { "default", "combat", "minimal" },

    skin = "default", -- Art/<skin>/<TextureName>.png

    layout = {
        reapplyMs = 200, -- how often moved elements are re-asserted (game animations can reset them)
    },

    art = {
        enabled = true,
        hookSetters = true, -- re-skin brushes the game changes at runtime (item icons, state swaps)
    },

    grid = {
        show = true, -- draw the grid while the editor is open
        snap = true, -- arrows snap element edges to grid lines (toggle in game with keys.toggleGrid)
        size = 16, -- cell size in UI units (1920x1080 reference)
        major = 4, -- brighter line every N cells; Shift+arrow jumps to these
        color = { 1, 0.85, 0.45 },
        minorAlpha = 0.08,
        majorAlpha = 0.22,
        centreColor = { 0.25, 0.85, 1 }, -- centre axes: cyan, so the middle stands out from the gold grid
        centreAlpha = 0.75,
        centreThickness = 2,
        centreDot = 6, -- square at the centre, in UI units
        centreAnimate = true, -- pulses travel from the centre to each screen edge
        centreSegments = 24, -- per arm; more = smoother gradient
        centreWaves = 2, -- bright pulses visible on each arm at once
        centreSpeed = 0.6, -- pulses per second leaving the centre
        centreFade = 0.7, -- how much dimmer the arms get toward the edges (0 = no gradient)
        centreMinLevel = 0.35, -- brightness between pulses
        centrePulseColor = { 1, 1, 1 }, -- pulses shift toward this colour
        centreFrameMs = 33,
    },

    share = {
        importFile = "import", -- share/<name>.framemage.txt is what Import reads (Mod Menu sets this)
    },

    inspector = {
        includeHidden = false, -- widgets.txt: also list collapsed/hidden branches (much longer)
    },

    editor = {
        step = 4,
        bigStep = 32,
        scaleStep = 0.05,
        fadeStep = 0.1,
        minScale = 0.2,
        maxScale = 4.0,

        lockInput = true, -- show the mouse cursor and pause game input while the editor is open

        -- selection frame (colour is linear RGB; edges are thin, corner brackets heavier)
        frameColor = { 1, 1, 1 },
        frameEdgeAlpha = 0.6,
        frameEdge = 1,
        frameCorner = 3,
        frameCornerLength = 12,
        frameMinSize = 16, -- empty widgets get at least this big a frame so they can be seen
        frameMs = 33, -- how often the frame follows the selection

        -- preview of elements that have nothing to show right now
        ghostOpacity = 0.35, -- elements hidden by your layout show at this opacity while selected
        previewMaxText = 40, -- empty text fields that get a placeholder label

        -- title banner (ribbon below the compass)
        bannerHeight = 64, -- UI units
        bannerMinWidth = 220,
        bannerFontSize = 22,
        bannerGap = 10, -- below the compass
        bannerFallbackTop = 120, -- when the compass can't be measured

        -- hotkey legend (left edge of the screen while the editor is open)
        showLegend = true,
        legendKeySize = 28, -- keycap height in UI units
        legendKeyColumn = 120, -- width reserved for the keys column
        legendMargin = 24,

        -- click-to-pick
        pickMinArea = 4, -- ignore widgets smaller than this (UI units squared)
        pickMaxNodes = 6000, -- safety cap on widgets examined per click
        pickRepeatTolerance = 6, -- clicks this close count as "same spot" and step out to the parent
    },

    keys = {
        edit = "F9",
        dump = "CTRL+F9",
        reloadArt = "CTRL+F10",
        previewCelebration = "CTRL+F8", -- developer: play the level-up celebration
        nextProfile = "F7",

        -- active only while the editor is open
        pick = "LeftMouseButton", -- click to select; click again in the same spot to select its parent
        next = "PageDown",
        prev = "PageUp",
        nextSibling = "CTRL+PageDown",
        prevSibling = "CTRL+PageUp",
        parent = "Home",
        child = "End",
        left = "Left",
        right = "Right",
        up = "Up",
        down = "Down",
        bigModifier = "SHIFT", -- hold with arrows for big steps
        scaleUp = "Equals",
        scaleDown = "Hyphen",
        fadeDown = "LeftBracket", -- [
        fadeUp = "RightBracket", -- ]
        hide = "Delete",
        reset = "BackSpace",
        toggleGrid = "Insert",
    },
}
