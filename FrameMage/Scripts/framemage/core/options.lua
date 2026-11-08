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
    { id = "share", label = "Layouts" },
}

-- Row types: toggle, choice (options + labels), number / slider (min, max, step), key, button (action), info.
M.SCHEMA = {
    -- Look
    { tab = "look", key = "Enabled", type = "toggle", label = "Frame Mage on", setting = "enabled",
        tooltip = "Off: every moved, faded or hidden element and all reskinned art go back to the game's own." },
    { tab = "look", key = "Theme", type = "choice", label = "Theme", setting = "theme",
        options = { "demihuman", "warrior", "ranger", "wizard" },
        labels = { demihuman = "Demi-human", warrior = "Warrior (soon)", ranger = "Ranger (soon)", wizard = "Wizard (soon)" },
        tooltip = "The look of reskinned game art and of Frame Mage's own panels." },
    { tab = "look", key = "Stone", type = "choice", label = "Panel stone", setting = "stone",
        options = { "moonstone", "slate", "marble" },
        labels = { moonstone = "Moonstone", slate = "Slate", marble = "Black marble" },
        tooltip = "The stone behind Frame Mage's own panels." },
    { tab = "look", key = "Profile", type = "choice", label = "Layout", setting = "profile",
        options = { "default", "combat", "minimal" },
        labels = { default = "Default", combat = "Combat", minimal = "Minimal" },
        tooltip = "Which saved layout is in use." },
    { tab = "look", key = "DurabilityColours", type = "toggle", label = "Colour durability bars",
        setting = "bars.durabilityColours", tooltip = "Green at full, then yellow, orange and red as items wear." },
    { tab = "look", key = "HideUpkeepDivider", type = "toggle", label = "Hide the survival / buffs divider",
        setting = "bars.hideUpkeepDivider" },
    { tab = "look", key = "HideKeyHints", type = "toggle", label = "Hide the key hints", setting = "bars.hideKeyHints",
        tooltip = "Hides Block / Attack / Special Attack... The menu shortcuts stay." },

    -- Vitals
    { tab = "vitals", key = "BarStyle", type = "choice", label = "Bar style", setting = "bars.style",
        options = { "flat", "bevel", "facet" },
        labels = { flat = "Flat", bevel = "Bevelled", facet = "Faceted" } },
    { tab = "vitals", key = "BarTaper", type = "toggle", label = "Shaped bars (pointed end)", setting = "bars.taper" },
    { tab = "vitals", key = "TipGain", type = "slider", label = "Point brightness", setting = "bars.tipGain",
        min = 0.5, max = 2.5, step = 0.05, percent = true,
        tooltip = "Match the full bar's point to the bar's colour." },
    { tab = "vitals", key = "BarOutline", type = "toggle", label = "Gold edge", setting = "bars.outline" },
    { tab = "vitals", key = "BarBadges", type = "toggle", label = "Icons on rings", setting = "bars.badges" },
    { tab = "vitals", key = "RingShadow", type = "toggle", label = "Ring shadows", setting = "bars.ringShadow" },

    -- Editor
    { tab = "editor", key = "GridSnap", type = "toggle", label = "Snap to grid", setting = "grid.snap" },
    { tab = "editor", key = "GridSize", type = "number", label = "Grid size", setting = "grid.size",
        min = 4, max = 64, step = 4, suffix = " px" },
    { tab = "editor", key = "GridLines", type = "toggle", label = "Show grid lines", setting = "grid.show" },
    { tab = "editor", key = "AxisAnimation", type = "toggle", label = "Animate the centre lines", setting = "grid.centreAnimate" },
    { tab = "editor", key = "Handles", type = "toggle", label = "Gold drag bars on everything", setting = "editor.showHandles" },
    { tab = "editor", key = "Legend", type = "toggle", label = "Show the hotkey list", setting = "editor.showLegend" },
    { tab = "editor", key = "PauseGame", type = "toggle", label = "Pause controls while editing", setting = "editor.lockInput" },

    -- Celebrations
    { tab = "fun", key = "LevelUpCelebration", type = "toggle", label = "Level-up celebration", setting = "replace.levelUp" },
    { tab = "fun", key = "Ding", type = "toggle", label = "DING! sound", setting = "ding.enabled" },
    { tab = "fun", key = "DingVolume", type = "slider", label = "DING! volume", setting = "ding.volume",
        min = 0, max = 1, step = 0.05, percent = true },
    { tab = "fun", type = "button", label = "Preview the celebration", action = "preview" },

    -- Keys
    { tab = "keys", key = "KeyEdit", type = "key", label = "Open / close the editor", setting = "keys.edit" },
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
    { tab = "keys", key = "KeyDumpApi", type = "key", label = "Developer: dump the game's API", setting = "keys.dumpApi" },

    -- Layouts
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
function M.rowsOf(tab)
    local out = {}
    for _, r in ipairs(M.SCHEMA) do if r.tab == tab then out[#out + 1] = r end end
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
    if row.key == "Enabled" then ctx.setEnabled(v) return true end   -- saves settings itself
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
end

return M
