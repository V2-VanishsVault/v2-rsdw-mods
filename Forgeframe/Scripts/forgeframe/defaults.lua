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
        blinkMs = 300,
    },

    keys = {
        edit = "F9",
        dump = "CTRL+F9",
        reloadArt = "CTRL+F10",
        nextProfile = "F7",

        -- active only while the editor is open
        next = "PAGE_DOWN",
        prev = "PAGE_UP",
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
