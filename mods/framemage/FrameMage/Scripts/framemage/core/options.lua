-- Frame Mage's settings, as shown in its own Settings panel (the editor's F4; editor/settings.lua).
--
-- SCHEMA is the single list of what can be set: each row names its tab, how it's shown, and the path of the
-- setting in settings.lua it maps to. apply() changes a setting and tells the parts of Frame Mage that need to
-- know; action() runs a button. (This replaces the Mod Menu page, which used the same list.)
local M = {}

M.TABS = {
    { id = "look", label = "Look" },
    { id = "vitals", label = "Vitals" },
    { id = "editor", label = "Editor" },
    { id = "fun", label = "Celebrations" },
    { id = "keys", label = "Keys" },
    { id = "share", label = "Share" },
}

-- Row types: toggle, choice (options + labels), number / slider (min, max, step), key, button (action), info.
M.SCHEMA = {
    -- Look
    { tab = "look", key = "Theme", type = "choice", label = "Theme", setting = "theme",
        options = { "dwarven", "elven", "ranger", "warrior", "wizard" }, -- (alphabetical)
        labels = { elven = "Elven", warrior = "Warrior", ranger = "Ranger", wizard = "Wizard", dwarven = "Dwarven" },
        -- the game's own skill icons, before the name
        icons = { warrior = "T_Icon_Tag_Skill_Attack", wizard = "T_Icon_Tag_Skill_Magic", ranger = "T_Icon_Tag_Skill_Ranged",
            dwarven = "T_Icon_Tag_Skill_Mining", elven = "T_Icon_Tag_Skill_Herblore" },
        tooltip = "The look of reskinned game art and of Frame Mage's own panels." },
    { tab = "look", key = "Stone", type = "choice", label = "Panel background", setting = "stone",
        options = require("framemage.editor.style").STONES,
        labels = require("framemage.editor.style").STONE_LABELS,
        tooltip = "What fills Frame Mage's panels and the windows it restyles. Theme's own: each theme's painting." },
    { tab = "look", key = "Profile", type = "choice", label = "Layout", setting = "profile",
        options = { "default", "combat", "minimal" },
        labels = { default = "Default", combat = "Combat", minimal = "Minimal" },
        tooltip = "Which saved layout is in use." },
    { tab = "look", type = "button", label = "Reset this layout", action = "resetLayout", confirm = true,
        tooltip = "Puts every element back where the game has it. The old layout is kept in layouts/<layout>.before-reset.lua." },
    { tab = "look", key = "DurabilityColors", type = "toggle", label = "Color durability bars",
        setting = "bars.durabilityColors", tooltip = "Green at full, then yellow, orange and red as items wear." },
    { tab = "look", key = "HideKeyHints", type = "toggle", label = "Hide the key hints", setting = "bars.hideKeyHints",
        tooltip = "Hides Block / Attack / Special Attack... The menu shortcuts stay." },

    -- Vitals
    { tab = "vitals", key = "BarStyle", type = "choice", label = "Bar style", setting = "bars.style",
        options = { "flat", "bevel", "facet" },
        labels = { flat = "Flat", bevel = "Beveled", facet = "Faceted" } },
    { tab = "vitals", key = "BarTaper", type = "toggle", label = "Shaped bars (pointed end)", setting = "bars.taper" },
    { tab = "vitals", key = "BarOutline", type = "toggle", label = "Bar edge", setting = "bars.outline" },
    { tab = "vitals", key = "PercentText", type = "toggle", label = "Stamina / special as %", setting = "bars.percentText" },
    { tab = "vitals", key = "StatusGauges", type = "toggle", label = "Status effects as gauges", setting = "bars.statusGauges",
        tooltip = "Cosiness, Sheltered, the weather and the rest as round gauges like the buffs (takes effect as they next appear)." },
    { tab = "vitals", key = "WeightColors", type = "toggle", label = "Color the load gauge", setting = "bars.weightColors",
        tooltip = "The inventory shortcut's gauge and the inventory's weight bar: green to 50%, yellow to 75%, orange to 90%, red to full, pulsing red when overloaded." },
    { tab = "vitals", key = "StatusOrder", type = "choice", label = "Status effect order", setting = "bars.statusOrder",
        options = { "game", "timed", "lasting" }, labels = { game = "Game", timed = "Timed first", lasting = "Lasting first" },
        tooltip = "Game: the order the game lists them. Timed first: the ones that run out (Cosiness, overeating...) before the ones that last (Sheltered). Lasting first: the other way round." },
    { tab = "vitals", key = "StatusGrow", type = "choice", label = "Status effects grow", setting = "bars.statusGrow",
        options = { "down", "up" }, labels = { down = "Down", up = "Up" },
        tooltip = "Which way the column of status effects grows as more appear: the first one stays where you put it." },
    { tab = "vitals", key = "SurvivalLayout", type = "choice", label = "Survival gauges", setting = "bars.survivalLayout",
        options = { "row", "stacked" }, labels = { row = "Standard", stacked = "Stacked" },
        tooltip = "Stacked: water, food and exhaustion in a column beside the vital bars, each level with its bar, and the buffs in a row after them." },
    { tab = "vitals", key = "SurvivalSize", type = "number", label = "Survival gauge size", setting = "bars.survivalRingSize",
        min = 24, max = 96, step = 4, suffix = " px",
        tooltip = "How big the water, food and exhaustion gauges are when they're stacked. Bigger than the bars' spacing, they spread apart (move them anywhere in the editor)." },
    { tab = "vitals", key = "BarBadges", type = "toggle", label = "Icons on rings", setting = "bars.badges" },
    { tab = "vitals", key = "RingShadow", type = "toggle", label = "Ring shadows", setting = "bars.ringShadow" },

    -- Editor
    { tab = "editor", key = "GridSnap", type = "toggle", label = "Snap to grid", setting = "grid.snap" },
    { tab = "editor", key = "GridSize", type = "number", label = "Grid size", setting = "grid.size",
        min = 4, max = 64, step = 4, suffix = " px" },
    { tab = "editor", key = "GridLines", type = "toggle", label = "Show grid lines", setting = "grid.show" },
    { tab = "editor", key = "AxisAnimation", type = "toggle", label = "Animate the center lines", setting = "grid.centerAnimate" },
    { tab = "editor", key = "Handles", type = "toggle", label = "Drag bars on everything", setting = "editor.showHandles" },
    { tab = "editor", key = "Legend", type = "toggle", label = "Show the hotkey list", setting = "editor.showLegend" },
    { tab = "editor", key = "PauseGame", type = "toggle", label = "Pause controls while editing", setting = "editor.lockInput" },

    -- Celebrations
    { tab = "fun", key = "LevelUpCelebration", type = "toggle", label = "Level-up celebration", setting = "replace.levelUp" },
    { tab = "fun", key = "Ding", type = "toggle", label = "Level-up fanfare", setting = "ding.enabled" },
    { tab = "fun", key = "DingSound", type = "choice", label = "Fanfare", setting = "ding.sound",
        options = require("framemage.features.ding").ORDER, labels = require("framemage.features.ding").LABELS,
        tooltip = "The tune that plays as the number lands. Picking one plays it." },
    { tab = "fun", key = "DingVolume", type = "slider", label = "Fanfare volume", setting = "ding.volume",
        min = 0, max = 1, step = 0.05, percent = true },
    { tab = "fun", type = "button", label = "Preview the celebration", action = "preview" },

    -- Keys
    { tab = "keys", key = "KeyEdit", type = "key", label = "Open / close the editor", setting = "keys.edit" },
    { tab = "keys", key = "KeyUndo", type = "key", label = "Undo a move", setting = "keys.undo" },
    { tab = "keys", key = "KeySettings", type = "key", label = "Settings (this panel)", setting = "keys.settings" },
    { tab = "keys", key = "KeyCloseEditor", type = "key", label = "Close the editor (also)", setting = "keys.closeEditor" },
    { tab = "keys", key = "KeyLegend", type = "key", label = "Show / hide the hotkey list", setting = "keys.legend" },
    { tab = "keys", key = "KeyShowHidden", type = "key", label = "Hidden elements", setting = "keys.showHidden" },
    { tab = "keys", key = "KeyNextLayout", type = "key", label = "Next layout", setting = "keys.nextProfile" },
    { tab = "keys", key = "KeyNext", type = "key", label = "Next element", setting = "keys.next" },
    { tab = "keys", key = "KeyPrev", type = "key", label = "Previous element", setting = "keys.prev" },
    { tab = "keys", key = "KeyParent", type = "key", label = "Parent", setting = "keys.parent" },
    { tab = "keys", key = "KeyChild", type = "key", label = "Child", setting = "keys.child" },
    { tab = "keys", key = "KeyLeft", type = "key", label = "Move left", setting = "keys.left" },
    { tab = "keys", key = "KeyRight", type = "key", label = "Move right", setting = "keys.right" },
    { tab = "keys", key = "KeyUp", type = "key", label = "Move up", setting = "keys.up" },
    { tab = "keys", key = "KeyDown", type = "key", label = "Move down", setting = "keys.down" },
    { tab = "keys", key = "KeyScaleUp", type = "key", label = "Bigger", setting = "keys.scaleUp" },
    { tab = "keys", key = "KeyScaleDown", type = "key", label = "Smaller", setting = "keys.scaleDown" },
    { tab = "keys", key = "KeyFadeIn", type = "key", label = "Less faded", setting = "keys.fadeUp" },
    { tab = "keys", key = "KeyFadeOut", type = "key", label = "More faded", setting = "keys.fadeDown" },
    { tab = "keys", key = "KeyHide", type = "key", label = "Hide / show element", setting = "keys.hide" },
    { tab = "keys", key = "KeyReset", type = "key", label = "Reset element", setting = "keys.reset" },
    { tab = "keys", key = "KeyGrid", type = "key", label = "Grid on / off", setting = "keys.toggleGrid" },
    { tab = "keys", key = "KeyDumpApi", type = "key", label = "Developer: dump the game's API", setting = "keys.dumpApi",
        dev = true }, -- (only with the developer features: dev/)

    -- Share
    { tab = "share", type = "button", label = "Export this layout", action = "export",
        tooltip = "Writes it to Mods/FrameMage/share/<layout>.framemage.txt to send to someone." },
    { tab = "share", type = "button", label = "Import a layout", action = "import",
        tooltip = "Reads Mods/FrameMage/share/import.framemage.txt into the current layout." },
    { tab = "share", type = "info", label = "To import: save a layout you were sent as share/import.framemage.txt" },
}

-- Pure helpers (unit-tested) -----------------------------------------------------------------------------------

function M.getPath(t, path)
    for part in path:gmatch("[^.]+") do
        if type(t) ~= "table" then return nil end
        t = t[part]
    end
    return t
end

function M.setPath(t, path, v)
    local parts = {}
    for part in path:gmatch("[^.]+") do parts[#parts + 1] = part end
    for i = 1, #parts - 1 do
        t[parts[i]] = t[parts[i]] or {}
        t = t[parts[i]]
    end
    t[parts[#parts]] = v
end

-- The rows of one tab, in order.
-- Rows marked dev = true belong to developer features (dev/): shown only when those are installed (main.lua sets it).
M.showDev = false

function M.rowsOf(tab)
    local out = {}
    for _, r in ipairs(M.SCHEMA) do
        if r.tab == tab and (M.showDev or not r.dev) then out[#out + 1] = r end
    end
    return out
end

-- Pure: the next value of a choice (dir = 1 or -1, wrapping). Unit-tested.
function M.cycle(options, current, dir)
    local n = #options
    if n == 0 then return current end
    local i = 1
    for k, v in ipairs(options) do if v == current then i = k break end end
    return options[((i - 1 + (dir or 1)) % n) + 1]
end

-- Pure: a number stepped and kept in range (snapped to the step, no float drift). Unit-tested.
function M.step(row, current, dir)
    local v = (tonumber(current) or row.min or 0) + (dir or 1) * (row.step or 1)
    v = math.max(row.min or v, math.min(row.max or v, v))
    local s = row.step or 1
    return math.floor(v / s + 0.5) * s
end

-- Pure: how a row's value reads ("On", "Moonstone", "16 px", "75%"). Unit-tested.
function M.display(row, v)
    if row.type == "toggle" then return v and "On" or "Off" end
    if row.type == "choice" then return (row.labels and row.labels[v]) or tostring(v) end
    if row.type == "slider" and row.percent then return string.format("%d%%", math.floor((tonumber(v) or 0) * 100 + 0.5)) end
    if row.type == "number" or row.type == "slider" then
        local n = tonumber(v) or 0
        local s = (n == math.floor(n)) and string.format("%d", n) or string.format("%.2f", n)
        return s .. (row.suffix or "")
    end
    return tostring(v or "")
end

-- Runtime ----------------------------------------------------------------------------------------------------

-- Change one setting and tell whoever needs to know. Returns true if it changed.
function M.apply(ctx, row, v)
    if v == nil or not row.setting then return false end
    local cur = M.getPath(ctx.settings, row.setting)
    if v == cur then return false end
    local f = ctx.features
    if row.key == "Theme" then return ctx.themes.set(v) end            -- saves and restyles itself
    if row.key == "Profile" then
        if f.layout then f.layout.selectProfile(v) end
        return true
    end
    M.setPath(ctx.settings, row.setting, v)
    if row.type == "key" then
        ctx.keys.rebind(row.setting:match("^keys%.(.+)$"), v)
        if f.editor then f.editor.keysChanged() end
    elseif row.key == "Stone" then ctx.events.emit("stylechanged")
    elseif row.key == "GridSnap" and f.grid then f.grid.setSnap(v)
    elseif row.key == "GridSize" and f.grid then f.grid.setSize(v)
    elseif row.key == "GridLines" and f.grid then f.grid.setShowLines(v)
    elseif row.key == "Legend" and f.editor then f.editor.keysChanged()
    elseif row.key == "Handles" and f.editor then f.editor.handlesChanged()
    elseif row.key == "DingSound" and f.ding then f.ding.play(true)
    elseif row.setting:match("^bars%.") and f.bars then f.bars.refresh()
    end
    ctx.saveSettings()
    ctx.log.info("Settings: %s = %s", row.key or row.setting, tostring(v))
    return true
end

-- A button.
function M.action(ctx, name)
    local f = ctx.features
    if name == "export" and f.share then return f.share.export() end
    if name == "import" and f.share then return f.share.import() end
    if name == "preview" and f.celebrate then return f.celebrate.preview() end
    if name == "resetLayout" and f.layout then
        local n = f.layout.resetAll()
        if f.editor then f.editor.flash(("Layout reset: %d elements back to the game's own"):format(n)) end
        return n
    end
end

-- Pure: a button marked `confirm` runs only on a second click within CONFIRM_SECONDS of the first. armed =
-- { row, at } from the first click, or nil. Unit-tested.
M.CONFIRM_SECONDS = 4
function M.isArmed(armed, row, now)
    return armed ~= nil and armed.row == row and now - armed.at <= M.CONFIRM_SECONDS
end

return M
