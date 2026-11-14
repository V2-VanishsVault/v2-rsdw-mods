-- Storage Mage: bags, pickup routing, workbench access and carry weight for RuneScape: Dragonwilds (UE4SS Lua).
-- Runs on the server (owns the inventories) and on clients (reads them and draws Storage Mage's own UI;
-- Frame Mage, if installed, only restyles it).
-- Design: docs/design.md. Bag logic is not built yet; this is the scaffold.
--
-- Structure
--   storagemage/core/*      shared services: log, fs, serialize, config, sched, events, keys, objects, toast
--   storagemage/features/*  one module per feature; each exports init(ctx)

local FEATURES = { "probe", "pages", "tags", "uidump", "belttab", "dragprobe", "bagmoves", "pagetest" }

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

for _, name in ipairs(FEATURES) do
    if ctx.settings.features[name] == false then
        log.info("feature '%s' disabled in settings", name)
    else
        local ok, mod = pcall(require, "storagemage.features." .. name)
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

-- Hotkeys are polled on the game thread (see core/keys.lua for why not RegisterKeyBind). A dedicated server
-- has no local player, so polling finds no controller and costs almost nothing.
ctx.keys.start(ctx)

sched.later(1500, "start", function()
    log.info("Storage Mage running (%s)", tostring(ctx.objects.netRole()))
    ctx.events.emit("started", ctx)
end)
