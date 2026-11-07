-- Forgeframe: UI layout + art overhaul for RuneScape: Dragonwilds (UE4SS Lua).
--
-- Structure
--   forgeframe/core/*      shared services: log, fs, serialize, config, sched, events, keys, widgets
--   forgeframe/features/*  one module per feature; each exports init(ctx)
--
-- To add a feature: create forgeframe/features/<name>.lua exporting `init(ctx)`, then add its name to FEATURES.

local FEATURES = { "layout", "art", "materials", "grid", "editor", "inspector" }

local function modDir()
    local src = (debug.getinfo(1, "S").source or ""):gsub("^@", "")
    local dir = src:gsub("[/\\]Scripts[/\\]main%.lua$", "")
    if dir == src or dir == "" then dir = "ue4ss/Mods/Forgeframe" end
    return (dir:gsub("\\", "/")) .. "/"
end

local log = require("forgeframe.core.log")
local sched = require("forgeframe.core.sched")

local DIR = modDir()
log.info("Forgeframe starting from %s", DIR)

if not sched.available() then
    log.error("this UE4SS build lacks LoopInGameThreadWithDelay / ExecuteInGameThreadWithDelay / NotifyOnNewObject. "
        .. "Install the latest UE4SS experimental build. Forgeframe is not running.")
    return
end

local config = require("forgeframe.core.config")
local defaults = require("forgeframe.defaults")

local ctx = {
    dir = DIR,
    log = log,
    sched = sched,
    fs = require("forgeframe.core.fs"),
    serialize = require("forgeframe.core.serialize"),
    config = config,
    events = require("forgeframe.core.events"),
    keys = require("forgeframe.core.keys"),
    widgets = require("forgeframe.core.widgets"),
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
        "-- Your Forgeframe settings: only what differs from the defaults. Every setting, with its default,\n"
        .. "-- is in settings.defaults.lua; copy a line here and change it. Restart the game to apply.\n")
end
config.save(DIR .. "config/settings.defaults.lua", defaults,
    "-- Generated on every start: all Forgeframe settings at their defaults. Don't edit this file;\n"
    .. "-- put changes in settings.lua (only the lines you change).\n")
ctx.saveSettings()
log.setLevel(ctx.settings.logLevel)

for _, name in ipairs(FEATURES) do
  if ctx.settings.features[name] == false then
    log.info("feature '%s' disabled in settings", name)
  else
    local ok, mod = pcall(require, "forgeframe.features." .. name)
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

-- Widget creation reports drive everything; they must be registered after the engine is up.
sched.later(1500, "start", function()
    ctx.widgets.startTracking(ctx)
    ctx.events.emit("started", ctx)
end)
