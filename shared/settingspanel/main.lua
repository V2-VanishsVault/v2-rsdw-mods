-- The Settings panel's entry point. Every mod that ships a copy starts it once:
--
--   require("settingspanel.main").start{ mod = "StorageMage", dir = DIR }   -- dir: the mod's folder, ending in /
--
-- and takes part with settingspanel.client (its tab). Which copy draws is settled here:
--   - claim: at start-up a copy takes SettingsPanel.host if it's empty, an older version, or the same version from a
--     mod whose name sorts later (protocol.shouldClaim);
--   - settle: 3 s later, only the copy still holding it draws (builds the panel, polls its open key);
--   - heartbeat: the drawing copy bumps SettingsPanel.hostBeat every 2 s. If the beat stops for 6 s (its mod was
--     switched off), the others claim again.
local game = require("settingspanel.game")
local protocol = require("settingspanel.protocol")
local version = require("settingspanel.version")

local M = {}

local cfg
local drawing = false
local lastBeat, lastBeatChange
local beat = 0
local started = false

local function mine() return protocol.hostValue(version.PANEL_VERSION, cfg.mod) end

local function claim()
    local cur = game.get("SettingsPanel.host")
    if cur == mine() then return true end
    if protocol.shouldClaim(cur, version.PANEL_VERSION, cfg.mod) then
        game.set("SettingsPanel.host", mine())
        return true
    end
    return false
end

local function becomeHost()
    if drawing then return end
    drawing = true
    local panel = require("settingspanel.panel")
    panel.init(cfg)
    game.info("drawing the Settings panel (version %d, open key %s)", version.PANEL_VERSION, panel.openKey())
end

function M.isDrawing() return drawing end

local function tick()
    if not drawing then return end
    local panel = require("settingspanel.panel")
    local input = require("settingspanel.input")
    if not panel.isCapturing() and input.pressed(panel.openKey()) then panel.toggle() end
    panel.tick()
end

local function watch()
    local now = game.now()
    if drawing then
        -- still ours? (a newer copy that started late may have taken it)
        if game.get("SettingsPanel.host") ~= mine() then
            game.info("another copy draws the Settings panel now (%s)", tostring(game.get("SettingsPanel.host")))
            local panel = require("settingspanel.panel")
            panel.close()
            drawing = false
            return
        end
        beat = beat + 1
        game.set("SettingsPanel.hostBeat", beat)
        return
    end
    local b = game.get("SettingsPanel.hostBeat")
    if b ~= lastBeat then lastBeat, lastBeatChange = b, now end
    if protocol.stale(lastBeatChange, now) or game.get("SettingsPanel.host") == nil then
        -- the drawing copy is gone: take over (if several copies do at once, the last to write keeps it)
        game.set("SettingsPanel.host", mine())
        lastBeatChange = now
        game.later(1000, "settingspanel.reclaim", function()
            if game.get("SettingsPanel.host") == mine() then becomeHost() end
        end)
    end
end

function M.start(c)
    if started then return end
    started = true
    cfg = c
    game.setMod(c.mod)
    claim()
    lastBeatChange = game.now()
    game.later(3000, "settingspanel.settle", function()
        if game.get("SettingsPanel.host") == mine() then becomeHost() end
        game.every(protocol.BEAT_SECONDS * 1000, "settingspanel.watch", watch)
    end)
    game.every(16, "settingspanel.tick", tick) -- (every frame: a quick key tap lasts about one)
    -- RegisterHook on a world change isn't needed; the panel's widgets die with the world
    pcall(function()
        NotifyOnNewObject("/Script/Engine.PlayerController", function()
            if drawing then require("settingspanel.panel").forget() end
        end)
    end)
end

return M
