-- Frame Mage: UI layout + art overhaul for RuneScape: Dragonwilds (UE4SS Lua).
--
-- Structure
--   framemage/core/*      shared services: log, fs, serialize, config, sched, events, keys, widgets
--   framemage/features/*  one module per feature; each exports init(ctx)
--
-- To add a feature: create framemage/features/<name>.lua exporting `init(ctx)`, then add its name to FEATURES.

local FEATURES = { "layout", "art", "materials", "grid", "editor", "inspector", "share", "celebrate", "replace",
    "modmenu" }

local function modDir()
    local src = (debug.getinfo(1, "S").source or ""):gsub("^@", "")
    local dir = src:gsub("[/\\]Scripts[/\\]main%.lua$", "")
    if dir == src or dir == "" then dir = "ue4ss/Mods/FrameMage" end
    return (dir:gsub("\\", "/")) .. "/"
end

local log = require("framemage.core.log")
local sched = require("framemage.core.sched")

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

-- Master switch (Mod Menu's "Frame Mage on"). Off: every change is handed back to the game live; on: re-applied.
-- Features opt in with setEnabled(on); hotkeys other than developer ones stop working while off.
ctx.enabled = ctx.settings.enabled ~= false
function ctx.setEnabled(on)
    on = on and true or false
    if on == ctx.enabled then return end
    ctx.enabled = on
    ctx.settings.enabled = on
    ctx.saveSettings()
    for _, name in ipairs(FEATURES) do
        local f = ctx.features[name]
        if f and f.setEnabled then
            local ok, err = pcall(f.setEnabled, on)
            if not ok then log.error("feature '%s' could not switch %s: %s", name, on and "on" or "off", tostring(err)) end
        end
    end
    log.info("Frame Mage %s", on and "on" or "off")
end

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
