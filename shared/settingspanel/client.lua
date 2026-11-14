-- What a mod calls to have its settings in the shared Settings panel. Every mod is a client, Frame Mage included:
-- whichever copy of the panel draws, it reaches each mod's settings only through these shared variables.
--
--   local client = require("settingspanel.client")
--   client.register{
--       mod = "StorageMage", title = "Storage Mage", order = 20,
--       tabs = { { id = "bags", label = "Bags" } },
--       rows = { { tab = "bags", type = "bool", setting = "pickupRouting", label = "Route pickups into bags" } },
--       get = function(setting) return value end,           -- the current value of a row's setting
--       apply = function(setting, value) end,                -- change it (validate, save, take effect); return
--                                                            -- false, "why" to refuse (the panel shows why)
--       action = function(name) end,                         -- a button
--       serverOwned = function() return false end,           -- optional: server settings are read-only here
--   }
--   client.changed()            -- a setting changed some other way: publish the values again
--   client.setRows(tabs, rows)  -- the rows themselves changed
local game = require("settingspanel.game")
local serialize = require("settingspanel.serialize")
local protocol = require("settingspanel.protocol")

local M = {}

local spec -- what register was given
local lastRev = 0
local lastRequest = 0
local valuesRev = 0

local function key(suffix) return "SettingsPanel." .. spec.mod .. "." .. suffix end

local function publishSchema()
    local schema = { protocol = protocol.PROTOCOL, mod = spec.mod, title = spec.title, order = spec.order,
        tabs = spec.tabs, rows = spec.rows }
    local ok, text = pcall(serialize.dump, schema)
    if not ok then game.warn("schema not published: %s", tostring(text)) return end
    game.set(key("schema"), text)
    game.set(key("schemaRev"), (game.getNumber(key("schemaRev")) or 0) + 1)
end

-- Pure: the values a schema's rows show, read with get(setting).
function M.collect(rows, get)
    local values = {}
    for _, r in ipairs(rows or {}) do
        if r.setting then
            local ok, v = pcall(get, r.setting)
            if ok then values[r.setting] = v end
        end
    end
    return values
end

function M.changed()
    if not spec then return end
    local data = { values = M.collect(spec.rows, spec.get), lastRequest = lastRequest, refused = M.refused,
        serverOwned = spec.serverOwned and spec.serverOwned() == true or nil }
    local ok, text = pcall(serialize.dump, data)
    if not ok then game.warn("values not published: %s", tostring(text)) return end
    game.set(key("values"), text)
    valuesRev = math.max(valuesRev, game.getNumber(key("valuesRev"))) + 1
    game.set(key("valuesRev"), valuesRev)
end

function M.setRows(tabs, rows)
    if not spec then return end
    spec.tabs, spec.rows = tabs or spec.tabs, rows or spec.rows
    publishSchema()
    M.changed()
end

-- Pure: carry out one request against a client spec. Returns the request's id.
function M.handle(s, req)
    if type(req) ~= "table" then return nil end
    if type(req.set) == "table" and req.set.setting ~= nil then
        local ok, accepted, reason = pcall(s.apply, req.set.setting, req.set.value)
        if not ok then
            game.warn("%s = %s failed: %s", tostring(req.set.setting), tostring(req.set.value), tostring(accepted))
            M.refused = { id = tonumber(req.id), reason = "That didn't work (see the log)." }
        elseif accepted == false then
            M.refused = { id = tonumber(req.id), reason = tostring(reason or "Not accepted") }
        end
    elseif req.action ~= nil and s.action then
        local ok, err = pcall(s.action, req.action)
        if not ok then game.warn("%s failed: %s", tostring(req.action), tostring(err)) end
    end
    return tonumber(req.id)
end

local function poll()
    local rev = game.getNumber(key("requestRev"))
    if rev == lastRev then return end
    lastRev = rev
    local text = game.get(key("request"))
    local req = type(text) == "string" and serialize.parse(text, "request") or nil
    local id = M.handle(spec, req)
    if id then lastRequest = math.max(lastRequest, id) end
    M.changed()
end

function M.register(s)
    assert(type(s) == "table" and type(s.mod) == "string", "settingspanel.client.register: mod name needed")
    spec = s
    game.setMod(s.mod)
    lastRev = game.getNumber(key("requestRev")) -- (a request left from before a reload isn't run again)
    game.set("SettingsPanel.registry", protocol.addTo(game.get("SettingsPanel.registry"), s.mod))
    publishSchema()
    M.changed()
    game.every(500, "settingspanel.client", poll)
end

return M
