-- Frame Mage: UI layout + art overhaul for RuneScape: Dragonwilds (UE4SS Lua).
--
-- Structure
--   framemage/core/*      shared services: log, fs, serialize, config, sched, events, keys, widgets
--   framemage/features/*  one module per feature; each exports init(ctx)
--
-- To add a feature: create framemage/features/<name>.lua exporting `init(ctx)`, then add its name to FEATURES.

local FEATURES = { "layout", "art", "materials", "grid", "editor", "inspector", "share", "ding", "celebrate", "replace",
    "bars", "survival", "status", "inventory" }

local function modDir()
    local src = (debug.getinfo(1, "S").source or ""):gsub("^@", "")
    local dir = src:gsub("[/\\]Scripts[/\\]main%.lua$", "")
    if dir == src or dir == "" then dir = "ue4ss/Mods/FrameMage" end
    return (dir:gsub("\\", "/")) .. "/"
end

local log = require("framemage.core.log")
local sched = require("framemage.core.sched")
-- safe to reload in a running game (UE4SS Ctrl+R): this run's objects get their own names (see core/reload.lua)
local reload = require("framemage.core.reload")
reload.install()

local DIR = modDir()
log.info("Frame Mage starting from %s", DIR)

if not sched.available() then
    log.error("this UE4SS build lacks LoopInGameThreadWithDelay / ExecuteInGameThreadWithDelay / NotifyOnNewObject. "
        .. "Install the latest UE4SS experimental build. Frame Mage is not running.")
    return
end

local config = require("framemage.core.config")
local defaults = require("framemage.defaults")

local ctx = {
    dir = DIR,
    log = log,
    sched = sched,
    fs = require("framemage.core.fs"),
    serialize = require("framemage.core.serialize"),
    config = config,
    events = require("framemage.core.events"),
    keys = require("framemage.core.keys"),
    widgets = require("framemage.core.widgets"),
    features = {},
}
ctx.settingsPath = DIR .. "config/settings.lua"
ctx.settings = config.load(ctx.settingsPath, defaults)

-- settings.lua holds only what the user changed, so improved defaults reach them on update.
-- settings.defaults.lua is regenerated every start as a reference of every setting.
function ctx.saveSettings()
    local overrides, unknown = config.diff(defaults, ctx.settings)
    for _, k in ipairs(unknown) do log.warn("settings.lua: unknown setting '%s' ignored", k) end
    config.save(ctx.settingsPath, overrides,
        "-- Your Frame Mage settings: only what differs from the defaults. Every setting, with its default,\n"
        .. "-- is in settings.defaults.lua; copy a line here and change it. Restart the game to apply.\n")
end
config.save(DIR .. "config/settings.defaults.lua", defaults,
    "-- Generated on every start: all Frame Mage settings at their defaults. Don't edit this file;\n"
    .. "-- put changes in settings.lua (only the lines you change).\n")
ctx.saveSettings()
log.setLevel(ctx.settings.logLevel)

-- themes (Art/themes/<name>/): game-art replacements and the look of Frame Mage's own panels
ctx.themes = require("framemage.core.themes")
ctx.themes.init(ctx)
require("framemage.editor.style").init(ctx)

-- Frame Mage is always on while loaded: turning it off is done the usual way (UE4SS's mods.txt or a mod manager).
-- An in-game switch had no way back once its panel went away with everything else. A saved `enabled = false`
-- from that switch is ignored.
ctx.enabled = true

-- anything a previous run (before a reload) left on the game's screens goes first: on the game thread, before any
-- feature's first tick (they'd see the leftovers as their own work already done)
sched.now("reload.cleanup", function()
    local okC, errC = pcall(reload.cleanup, ctx.widgets, log)
    if not okC then log.warn("reload cleanup failed: %s", tostring(errC)) end
end)

for _, name in ipairs(FEATURES) do
  if ctx.settings.features[name] == false then
    log.info("feature '%s' disabled in settings", name)
  else
    local ok, mod = pcall(require, "framemage.features." .. name)
    if ok then
        local okInit, err = pcall(mod.init, ctx)
        if okInit then
            ctx.features[name] = mod
            log.info("feature '%s' ready", name)
        else
            log.error("feature '%s' failed to start: %s", name, tostring(err))
        end
    else
        log.error("feature '%s' failed to load: %s", name, tostring(mod))
    end
  end
end

-- Hotkeys are polled on the game thread (see core/keys.lua for why not RegisterKeyBind).
ctx.keys.start(ctx)

-- Widget creation reports drive everything; they must be registered after the engine is up.
sched.later(1500, "start", function()
    ctx.widgets.startTracking(ctx)
    ctx.events.emit("started", ctx)
end)
