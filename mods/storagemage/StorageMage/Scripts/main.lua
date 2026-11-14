-- Storage Mage: bags, pickup routing, workbench access and carry weight for RuneScape: Dragonwilds (UE4SS Lua).
-- Runs on the server (owns the inventories) and on clients (reads them and draws Storage Mage's own UI;
-- Frame Mage, if installed, only restyles it).
-- Design: docs/design.md.
--
-- Structure
--   storagemage/core/*      shared services: log, fs, serialize, config, sched, events, keys, objects, toast
--   storagemage/features/*  one module per feature; each exports init(ctx)
--   dev/                    developer features (dumps, probes), next to Scripts/ in a development install only:
--                           dev/features.lua lists them. Release zips don't have it, and nothing here needs it.

local FEATURES = { "pages", "tags", "belttab", "bagmoves" }

local function modDir()
    local src = (debug.getinfo(1, "S").source or ""):gsub("^@", "")
    local dir = src:gsub("[/\\]Scripts[/\\]main%.lua$", "")
    if dir == src or dir == "" then dir = "ue4ss/Mods/StorageMage" end
    return (dir:gsub("\\", "/")) .. "/"
end

local log = require("storagemage.core.log")
local sched = require("storagemage.core.sched")

local DIR = modDir()
log.info("Storage Mage starting from %s", DIR)

if not sched.available() then
    log.error("this UE4SS build lacks LoopInGameThreadWithDelay / ExecuteInGameThreadWithDelay / NotifyOnNewObject. "
        .. "Install the latest UE4SS experimental build. Storage Mage is not running.")
    return
end

local config = require("storagemage.core.config")
local defaults = require("storagemage.defaults")

local ctx = {
    dir = DIR,
    version = 1,
    log = log,
    sched = sched,
    fs = require("storagemage.core.fs"),
    serialize = require("storagemage.core.serialize"),
    config = config,
    events = require("storagemage.core.events"),
    keys = require("storagemage.core.keys"),
    objects = require("storagemage.core.objects"),
    toast = require("storagemage.core.toast"),
    features = {},
}
ctx.settingsPath = DIR .. "config/settings.lua"
ctx.settings = config.load(ctx.settingsPath, defaults)

-- settings.lua holds only what the user changed, so improved defaults reach them on update.
function ctx.saveSettings()
    local overrides, unknown = config.diff(defaults, ctx.settings)
    for _, k in ipairs(unknown) do log.warn("settings.lua: unknown setting '%s' ignored", k) end
    config.save(ctx.settingsPath, overrides,
        "-- Your Storage Mage settings: only what differs from the defaults. Every setting, with its default,\n"
        .. "-- is in settings.defaults.lua; copy a line here and change it. Restart the game to apply.\n")
end
config.save(DIR .. "config/settings.defaults.lua", defaults,
    "-- Generated on every start: all Storage Mage settings at their defaults. Don't edit this file;\n"
    .. "-- put changes in settings.lua (only the lines you change).\n")
ctx.saveSettings()
log.setLevel(ctx.settings.logLevel)

ctx.enabled = ctx.settings.enabled ~= false
if not ctx.enabled then
    log.info("Storage Mage is switched off in settings")
    return
end

local function start(name, kind)
    if ctx.settings.features[name] == false then
        log.info("%s '%s' disabled in settings", kind, name)
        return
    end
    local ok, mod = pcall(require, "storagemage.features." .. name)
    if ok then
        local okInit, err = pcall(mod.init, ctx)
        if okInit then
            ctx.features[name] = mod
            log.info("%s '%s' ready", kind, name)
        else
            log.error("%s '%s' failed to start: %s", kind, name, tostring(err))
        end
    else
        log.error("%s '%s' failed to load: %s", kind, name, tostring(mod))
    end
end

for _, name in ipairs(FEATURES) do start(name, "feature") end

-- Developer features: only in a development install (the dev folder linked in by tools\deploy.ps1 -Link).
local devList = io.open(DIR .. "dev/features.lua", "r")
if devList then
    devList:close()
    package.path = DIR .. "dev/?.lua;" .. package.path
    local okL, names = pcall(dofile, DIR .. "dev/features.lua")
    if okL and type(names) == "table" then
        ctx.dev = true
        for _, name in ipairs(names) do start(name, "developer feature") end
    else
        log.error("dev/features.lua couldn't be read: %s", tostring(names))
    end
end

-- Storage Mage's tab in the Settings panel every Mage mod shares (Scripts/settingspanel; F4 opens it).
require("storagemage.panelclient").start(ctx)

-- Hotkeys are polled on the game thread (see core/keys.lua for why not RegisterKeyBind). A dedicated server
-- has no local player, so polling finds no controller and costs almost nothing.
ctx.keys.start(ctx)

sched.later(1500, "start", function()
    log.info("Storage Mage running (%s)", tostring(ctx.objects.netRole()))
    ctx.events.emit("started", ctx)
end)
