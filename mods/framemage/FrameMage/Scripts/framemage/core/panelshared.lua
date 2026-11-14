-- Frame Mage and the Settings panel every Mage mod shares (shared/settingspanel, shipped as Scripts/settingspanel).
--
-- Frame Mage is one of the panel's clients, like every other mod: its rows (core/options.lua SCHEMA) are published as
-- its tab, and changes come back through options.apply / options.action. It also publishes its look (FrameMage.look:
-- the theme's picture paths, slice sizes and colors), so whichever mod's copy draws the panel draws it in the theme,
-- and FrameMage.editorOpen, so the panel leaves the cursor alone over the editor.
--
-- settings.settingsPanel = "own" goes back to Frame Mage's own panel (editor/settings.lua), for comparison.
local options = require("framemage.core.options")

local M = {}

local ctx, client
local lookRev = 0

function M.enabled() return ctx ~= nil and client ~= nil end

local function set(k, v) pcall(function() ModRef:SetSharedVariable(k, v) end) end
local function get(k)
    local ok, v = pcall(function() return ModRef:GetSharedVariable(k) end)
    return ok and v or nil
end

-- Pure: Frame Mage's rows as the panel's schema rows (the panel's own open key isn't one of them: it lives in the
-- panel, for every mod), each with its default (a key row's RESET puts it back). Unit-tested.
function M.rows(schema, showDev, defaults)
    local out = {}
    for _, r in ipairs(schema) do
        if r.key ~= "KeySettings" and (showDev or not r.dev) then
            local c = {}
            for k, v in pairs(r) do c[k] = v end
            c.rowKey = r.key -- (options.apply's own name for the row)
            c.key = nil
            if defaults and r.setting then c.default = options.getPath(defaults, r.setting) end
            out[#out + 1] = c
        end
    end
    return out
end

local function rowFor(setting)
    for _, r in ipairs(options.SCHEMA) do if r.setting == setting then return r end end
    return nil
end

-- The look, published for the panel ---------------------------------------------------------------------------------

-- Pure-ish: the look table from the theme's style (s) and a find(rel) that returns a file's full path or nil.
function M.lookData(s, find, stoneFile, stoneTile, theme)
    local function c(k) return s[k] end
    local title = s.titleArt or "title_plate.png"
    return {
        theme = theme,
        titleArt = find("ui/" .. title) or find("ui/title_plate.png"),
        plateArt = find("ui/plate_selected.png") or find("ui/title_plate.png"),
        ornamentArt = find("ui/plate_ornament.png"),
        frameArt = find("ui/panel_frame.png"),
        stoneArt = stoneFile and find("ui/" .. stoneFile) or nil,
        stoneTile = stoneTile,
        titleSize = s.titleSize, titleMargin = s.titleMargin,
        frameSize = s.frameSize, frameMargin = s.frameMargin, frameDraw = s.frameDraw,
        panelPad = s.panelPad, panelColor = c("panelColor"),
        ink = s.selectedInk or { 0.06, 0.04, 0.02 }, -- lettering on a lit plate
        titleInk = c("ink"), heading = c("heading"), label = c("label"), dim = c("dim"), gold = c("gold"),
        button = { 0.12, 0.12, 0.14, 0.95 },
    }
end

function M.publishLook()
    if not ctx then return end
    local themes = ctx.themes
    local style = require("framemage.editor.style")
    local ok, data = pcall(function()
        local s = themes.style()
        local file = style.stoneFile(ctx.settings.stone, s)
        if not themes.find("ui/" .. file) then file = style.FALLBACK end
        return M.lookData(s, themes.find, file, style.stoneTile(file, s.panelTile), themes.current())
    end)
    if not ok then ctx.log.warn("settings panel: look not published: %s", tostring(data)) return end
    lookRev = lookRev + 1
    set("FrameMage.look", ctx.serialize.dump(data))
    set("FrameMage.lookRev", lookRev)
end

-- The editor ------------------------------------------------------------------------------------------------------

function M.setEditorOpen(on) set("FrameMage.editorOpen", on and 1 or 0) end

-- Is the shared panel open (or did it close a moment ago: the Escape that closed it mustn't close the editor too)?
-- Read at most every 0.1 s (the editor's keys ask every frame).
local cachedAt, cached = -1, false
function M.panelBusy()
    if not client then return false end
    local now = os.clock()
    if now - cachedAt < 0.1 then return cached end
    cachedAt = now
    local open = tonumber(get("SettingsPanel.open")) == 1
    local closedAt = tonumber(get("SettingsPanel.closedAt"))
    cached = open or (closedAt ~= nil and now - closedAt < 0.3)
    return cached
end

-- Pure: is (x, y) inside a box string "l,t,r,b"? Unit-tested.
function M.inBox(box, x, y)
    local l, t, r, b = tostring(box or ""):match("^(%-?%d+),(%-?%d+),(%-?%d+),(%-?%d+)$")
    if not l then return false end
    return x >= tonumber(l) and x <= tonumber(r) and y >= tonumber(t) and y <= tonumber(b)
end

-- Is the shared panel open with (x, y) on it?
function M.contains(x, y)
    if not client or tonumber(get("SettingsPanel.open")) ~= 1 then return false end
    return M.inBox(get("SettingsPanel.box"), x, y)
end

-- Setup ------------------------------------------------------------------------------------------------------------

function M.changed() if client then pcall(client.changed) end end

-- The rows changed (the developer rows appear with dev/).
function M.refreshRows()
    if client then pcall(client.setRows, options.TABS, M.rows(options.SCHEMA, options.showDev, require("framemage.defaults"))) end
end

function M.start(c)
    ctx = c
    local ok, err = pcall(function()
        require("settingspanel.main").start({ mod = "FrameMage", dir = c.dir })
        client = require("settingspanel.client")
        client.register({
            mod = "FrameMage", title = "Frame Mage", order = 10,
            tabs = options.TABS,
            rows = M.rows(options.SCHEMA, options.showDev, require("framemage.defaults")),
            get = function(setting) return options.getPath(c.settings, setting) end,
            apply = function(setting, value)
                local row = rowFor(setting)
                if not row then return false, "Frame Mage has no setting " .. tostring(setting) end
                if row.type == "key" and not c.keys.parse(value) then
                    return false, tostring(value) .. " isn't a key Frame Mage can use."
                end
                options.apply(c, row, value)
                return true
            end,
            action = function(name) options.action(c, name) end,
        })
    end)
    if not ok then
        client = nil
        c.log.warn("the shared Settings panel couldn't start (%s): using Frame Mage's own", tostring(err))
        return false
    end
    M.publishLook()
    M.setEditorOpen(false)
    c.events.on("themechanged", function() M.publishLook(); M.changed() end)
    c.events.on("stylechanged", function() M.publishLook(); M.changed() end)
    c.events.on("profilechanged", M.changed)
    -- every save: the panel shows the new values (a hotkey, the next-layout key, a theme switch)
    local save = c.saveSettings
    c.saveSettings = function(...)
        save(...)
        M.changed()
    end
    return true
end

return M
