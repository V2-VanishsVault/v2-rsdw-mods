-- Mod Menu support: Esc > MODS > Frame Mage.
--
-- Mod Menu (Maxxfilth) draws a settings page for every mod that ships a modmenu.json next to its enabled.txt,
-- saves the player's choices into the file that json names, and publishes changes as UE4SS shared variables:
--   ModMenu.Frame Mage.<Key>   current value     ModMenu.Frame Mage.rev     +1 on every change
--   ModMenu.Frame Mage.action  "<action>#<n>" when a button is clicked
--   ModMenu.request.set        (written by us) "<id>#<n>|Key=value" keeps the page in step with hotkey changes
--
-- SCHEMA below is the single source of truth: tools/gen_modmenu.lua writes FrameMage/modmenu.json from it
-- with defaults taken from defaults.lua, and a test fails if the committed json is out of date.
-- Frame Mage works the same without Mod Menu installed.
local M = {}

M.ID = "FrameMage"
M.CONFIG_FILE = "modmenu-settings.txt"

-- Each row: Mod Menu field + `setting` (path in Frame Mage settings) the value maps to.
M.SCHEMA = {
    { type = "header", label = "Frame Mage" },
    { key = "Enabled", type = "toggle", label = "Frame Mage on", setting = "enabled",
        tooltip = "Off: every moved, faded or hidden element and all reskinned art go back to the game's own, live. On: your layout and skin come back." },
    { key = "Profile", type = "choice", label = "Layout", setting = "profile", options = { "default", "combat", "minimal" },
        valueLabels = { default = "Default", combat = "Combat", minimal = "Minimal" },
        tooltip = "Which saved layout is in use. The next-layout key cycles them too." },

    { type = "header", label = "Layout editor" },
    { key = "GridSnap", type = "toggle", label = "Snap to grid", setting = "grid.snap",
        tooltip = "Arrows move an element until one of its edges sits on the next grid line. Off: free movement in small steps." },
    { key = "GridSize", type = "number", label = "Grid size", setting = "grid.size", min = 4, max = 64, step = 4, suffix = " px",
        tooltip = "Distance between grid lines, in UI units (1920x1080 screen)." },
    { key = "GridLines", type = "toggle", label = "Show grid lines", setting = "grid.show",
        tooltip = "Off: snapping still works, the lines just aren't drawn." },
    { key = "AxisAnimation", type = "toggle", label = "Animate the centre lines", setting = "grid.centreAnimate",
        tooltip = "Pulses run from the centre of the screen to each edge along the cyan centre lines." },
    { key = "Legend", type = "toggle", label = "Show the hotkey list", setting = "editor.showLegend",
        tooltip = "The list of editor keys on the left of the screen while the editor is open." },
    { key = "PauseGame", type = "toggle", label = "Pause controls while editing", setting = "editor.lockInput",
        tooltip = "Shows the mouse pointer and stops the camera, movement and attacks while the editor is open, so a click selects instead of swinging." },

    { type = "header", label = "Celebrations" },
    { key = "LevelUpCelebration", type = "toggle", label = "Level-up celebration", setting = "replace.levelUp",
        tooltip = "Fireworks and your new level zooming in, instead of the game's level-up circle. The game's level-up sound still plays." },
    { type = "button", label = "PREVIEW", action = "preview",
        tooltip = "Plays the level-up celebration now (close this menu to see it)." },

    { type = "header", label = "Hotkeys" },
    { key = "KeyEdit", type = "key", label = "Open / close the editor", setting = "keys.edit" },
    { key = "KeyNextLayout", type = "key", label = "Next layout", setting = "keys.nextProfile" },
    { key = "KeyPick", type = "key", label = "Select (editor)", setting = "keys.pick",
        tooltip = "Click again on the same spot to select the panel around it." },
    { key = "KeyNext", type = "key", label = "Next element (editor)", setting = "keys.next" },
    { key = "KeyPrev", type = "key", label = "Previous element (editor)", setting = "keys.prev" },
    { key = "KeyParent", type = "key", label = "Parent (editor)", setting = "keys.parent" },
    { key = "KeyChild", type = "key", label = "Child (editor)", setting = "keys.child" },
    { key = "KeyLeft", type = "key", label = "Move left (editor)", setting = "keys.left" },
    { key = "KeyRight", type = "key", label = "Move right (editor)", setting = "keys.right" },
    { key = "KeyUp", type = "key", label = "Move up (editor)", setting = "keys.up" },
    { key = "KeyDown", type = "key", label = "Move down (editor)", setting = "keys.down" },
    { key = "KeyScaleUp", type = "key", label = "Bigger (editor)", setting = "keys.scaleUp" },
    { key = "KeyScaleDown", type = "key", label = "Smaller (editor)", setting = "keys.scaleDown" },
    { key = "KeyFadeIn", type = "key", label = "Less faded (editor)", setting = "keys.fadeUp" },
    { key = "KeyFadeOut", type = "key", label = "More faded (editor)", setting = "keys.fadeDown" },
    { key = "KeyHide", type = "key", label = "Hide / show (editor)", setting = "keys.hide" },
    { key = "KeyReset", type = "key", label = "Reset element (editor)", setting = "keys.reset" },
    { key = "KeyGrid", type = "key", label = "Grid on / off (editor)", setting = "keys.toggleGrid" },

    { type = "header", label = "Share layouts" },
    { key = "ImportFile", type = "text", label = "File to import", setting = "share.importFile", maxLength = 60,
        tooltip = "Name of a file in Mods/FrameMage/share/ (without .framemage.txt). Import replaces the current layout; the old one is kept as layouts/<name>.before-import.lua." },
    { type = "button", label = "EXPORT LAYOUT", action = "export",
        tooltip = "Writes the current layout to Mods/FrameMage/share/<layout>.framemage.txt to send to someone." },
    { type = "button", label = "IMPORT LAYOUT", action = "import",
        tooltip = "Reads Mods/FrameMage/share/<File to import>.framemage.txt into the current layout." },
}

-- Pure helpers (unit-tested) -------------------------------------------------------------------------

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

-- "Key = value  # comment" lines -> { Key = "value" } (strings; the schema gives the types)
function M.parseConfig(text)
    local out = {}
    for line in (text or ""):gmatch("[^\r\n]+") do
        local k, v = line:match("^%s*([%w_]+)%s*=%s*(.-)%s*$")
        if k then out[k] = (v:gsub("%s+[#;].*$", "")) end
    end
    return out
end

-- Coerce a value from the config file or a shared variable to the type of the default. nil if unusable.
function M.coerce(v, default)
    if v == nil then return nil end
    if type(default) == "boolean" then
        if type(v) == "boolean" then return v end
        local s = tostring(v):lower()
        if s == "true" then return true elseif s == "false" then return false end
        return nil
    elseif type(default) == "number" then
        return tonumber(v)
    end
    return tostring(v)
end

-- Minimal JSON writer with stable key order (for tools/gen_modmenu.lua).
local function jstr(s)
    return '"' .. tostring(s):gsub('[%c"\\]', function(c)
        local map = { ['"'] = '\\"', ["\\"] = "\\\\", ["\n"] = "\\n", ["\r"] = "\\r", ["\t"] = "\\t" }
        return map[c] or string.format("\\u%04x", c:byte())
    end) .. '"'
end
local function jval(v, indent)
    local pad, pad2 = string.rep("  ", indent), string.rep("  ", indent + 1)
    if type(v) == "table" then
        if v.__order then
            local parts = {}
            for _, k in ipairs(v.__order) do
                if v[k] ~= nil then parts[#parts + 1] = pad2 .. jstr(k) .. ": " .. jval(v[k], indent + 1) end
            end
            return "{\n" .. table.concat(parts, ",\n") .. "\n" .. pad .. "}"
        elseif #v > 0 then
            local parts = {}
            for _, x in ipairs(v) do parts[#parts + 1] = pad2 .. jval(x, indent + 1) end
            return "[\n" .. table.concat(parts, ",\n") .. "\n" .. pad .. "]"
        else
            local keys = {}
            for k in pairs(v) do keys[#keys + 1] = k end
            table.sort(keys)
            local parts = {}
            for _, k in ipairs(keys) do parts[#parts + 1] = pad2 .. jstr(k) .. ": " .. jval(v[k], indent + 1) end
            if #parts == 0 then return "{}" end
            return "{\n" .. table.concat(parts, ",\n") .. "\n" .. pad .. "}"
        end
    elseif type(v) == "string" then return jstr(v)
    elseif type(v) == "number" then
        if math.type and math.type(v) == "integer" then return tostring(v) end
        return (string.format("%.4f", v):gsub("0+$", ""):gsub("%.$", ""))
    end
    return tostring(v)
end

-- The modmenu.json document for `defaults` (pure).
function M.toJson(defaults, version)
    local rows = {}
    local ORDER = { "key", "type", "label", "options", "valueLabels", "min", "max", "step", "suffix", "maxLength",
        "keyNames", "action", "default", "tooltip" }
    for _, r in ipairs(M.SCHEMA) do
        local row = { __order = ORDER } ---@type table<string, any>
        for _, f in ipairs(ORDER) do row[f] = r[f] end
        if r.setting then row.default = M.getPath(defaults, r.setting) end
        if r.type == "key" then row.keyNames = "unreal" end
        rows[#rows + 1] = row
    end
    local doc = {
        __order = { "schema", "id", "name", "author", "version", "description", "runsOn", "config", "settings" },
        schema = 1, id = M.ID, name = "Frame Mage", author = "Chris Van Cleve", version = version or "0.1.0",
        description = "Move, scale, fade or hide any part of the UI with an in-game editor (F9), and reskin it with your own art.",
        runsOn = "yours", config = { file = M.CONFIG_FILE }, settings = rows,
    }
    return jval(doc, 0) .. "\n"
end

-- Runtime -----------------------------------------------------------------------------------------------

local ctx, log
local rows = {} -- key -> schema row
local lastRev, lastAction
local requestN = 0

local function shared(name)
    local ok, v = pcall(function() return ModRef:GetSharedVariable(name) end)
    if ok then return v end
    return nil
end

-- Apply one Mod Menu value to Frame Mage (only if it differs).
local function apply(row, raw)
    local default = M.getPath(require("framemage.defaults"), row.setting)
    local v = M.coerce(raw, default)
    if v == nil then return end
    if row.type == "key" and v == "" then return end
    local cur = M.getPath(ctx.settings, row.setting)
    if v == cur then return end
    if row.key == "Enabled" then ctx.setEnabled(v) return end -- saves settings itself
    if row.key == "Profile" then
        local layout = ctx.features.layout
        if layout then layout.selectProfile(v) end
        return
    end
    M.setPath(ctx.settings, row.setting, v)
    local f = ctx.features
    if row.type == "key" then
        ctx.keys.rebind(row.setting:match("^keys%.(.+)$"), v)
        if f.editor then f.editor.keysChanged() end
    elseif row.key == "GridSnap" and f.grid then f.grid.setSnap(v)
    elseif row.key == "GridSize" and f.grid then f.grid.setSize(v)
    elseif row.key == "GridLines" and f.grid then f.grid.setShowLines(v)
    elseif row.key == "Legend" and f.editor then f.editor.keysChanged()
    end
    ctx.saveSettings()
    log.info("Mod Menu: %s = %s", row.key, tostring(v))
end

local function readConfigFile()
    local text = ctx.fs.read(ctx.dir .. M.CONFIG_FILE)
    if not text then return end
    for k, v in pairs(M.parseConfig(text)) do
        if rows[k] then apply(rows[k], v) end
    end
end

local function poll()
    local rev = shared("ModMenu." .. M.ID .. ".rev")
    if type(rev) == "number" and rev ~= lastRev then
        lastRev = rev
        for key, row in pairs(rows) do
            local v = shared("ModMenu." .. M.ID .. "." .. key)
            if v ~= nil then apply(row, v) end
        end
    end
    local action = shared("ModMenu." .. M.ID .. ".action")
    if action ~= nil and action ~= lastAction then
        lastAction = action
        local name = tostring(action):match("^([%w_]+)#")
        local share = ctx.features.share
        if share and name == "export" then share.export()
        elseif share and name == "import" then share.import()
        elseif name == "preview" and ctx.features.celebrate then ctx.features.celebrate.preview() end
    end
end

-- Tell Mod Menu about a value Frame Mage changed itself (hotkey), so its page and file stay in step.
function M.push(key, value)
    if not rows[key] then return end
    requestN = requestN + 1
    pcall(function()
        ModRef:SetSharedVariable("ModMenu.request.set", string.format("%s#%d|%s=%s", M.ID, requestN, key, tostring(value)))
    end)
end

function M.init(c)
    ctx, log = c, c.log
    for _, r in ipairs(M.SCHEMA) do if r.key then rows[r.key] = r end end
    readConfigFile()
    -- don't replay a button click from before this session
    lastAction = shared("ModMenu." .. M.ID .. ".action")
    lastRev = nil
    c.sched.every(500, "modmenu.poll", poll)
    c.events.on("profilechanged", function(name) M.push("Profile", name) end)
    local version = shared("ModMenu.version")
    log.info("Mod Menu %s", version and ("found (" .. tostring(version) .. ")") or "not installed; settings.lua only")
end

return M
