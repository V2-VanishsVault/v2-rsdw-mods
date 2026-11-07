-- Default settings. Users edit Mods/Forgeframe/config/settings.lua; missing keys fall back to these.
-- Key names are UE4SS `Key` names (F9, PAGE_UP, LEFT_ARROW, OEM_PLUS ...). Modifiers: CTRL, SHIFT, ALT.
return {
    logLevel = "info", -- debug | info | warn | error

    -- Turn a feature off to isolate a problem (e.g. a crash). Removed/false features never load.
    features = { layout = true, art = true, materials = true, grid = true, editor = true, inspector = true },

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

        -- click-to-pick
        pickMinArea = 4, -- ignore widgets smaller than this (UI units squared)
        pickMaxNodes = 6000, -- safety cap on widgets examined per click
        pickRepeatTolerance = 6, -- clicks this close count as "same spot" and step out to the parent
    },

    keys = {
        edit = "F9",
        dump = "CTRL+F9",
        reloadArt = "CTRL+F10",
        nextProfile = "F7",

        -- active only while the editor is open
        pick = "LEFT_MOUSE_BUTTON", -- click to select; click again in the same spot to select its parent
        next = "PAGE_DOWN",
        prev = "PAGE_UP",
        nextSibling = "CTRL+PAGE_DOWN",
        prevSibling = "CTRL+PAGE_UP",
        parent = "HOME",
        child = "END",
        left = "LEFT_ARROW",
        right = "RIGHT_ARROW",
        up = "UP_ARROW",
        down = "DOWN_ARROW",
        bigModifier = "SHIFT", -- hold with arrows for big steps
        scaleUp = "OEM_PLUS",
        scaleDown = "OEM_MINUS",
        fadeDown = "OEM_FOUR", -- [
        fadeUp = "OEM_SIX", -- ]
        hide = "DEL",
        reset = "BACKSPACE",
        toggleGrid = "INS",
    },
}
