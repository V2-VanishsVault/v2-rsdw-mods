-- Keybinds from config strings like "F9", "CTRL+F9", "SHIFT+LEFT_ARROW".
-- UE4SS calls keybind callbacks off the game thread, so every handler is hopped onto it.
local log = require("forgeframe.core.log")
local sched = require("forgeframe.core.sched")

local M = {}

local MODS = { CTRL = "CONTROL", CONTROL = "CONTROL", SHIFT = "SHIFT", ALT = "ALT" }

-- Pure: "CTRL+SHIFT+F9" -> { key = "F9", mods = { "CONTROL", "SHIFT" } }
function M.parse(spec)
    if type(spec) ~= "string" or spec == "" then return nil, "empty key" end
    local parts = {}
    for p in spec:upper():gmatch("[^+%s]+") do parts[#parts + 1] = p end
    if #parts == 0 then return nil, "empty key" end
    local key = table.remove(parts)
    local mods = {}
    for _, m in ipairs(parts) do
        if not MODS[m] then return nil, "unknown modifier " .. m end
        mods[#mods + 1] = MODS[m]
    end
    return { key = key, mods = mods }
end

-- bind(spec, name, fn [, extraMods]) -- extraMods lets one config key also bind a SHIFT variant
function M.bind(spec, name, fn, extraMods)
    local parsed, err = M.parse(spec)
    if not parsed then
        log.warn("keybind '%s' = %q ignored: %s", name, tostring(spec), err)
        return false
    end
    local keyCode = Key and Key[parsed.key]
    if not keyCode then
        log.warn("keybind '%s': %q is not a UE4SS key name", name, parsed.key)
        return false
    end
    local modList = {}
    for _, m in ipairs(parsed.mods) do modList[#modList + 1] = m end
    for _, m in ipairs(extraMods or {}) do modList[#modList + 1] = MODS[m] or m end
    local modCodes = {}
    for _, m in ipairs(modList) do
        if not (ModifierKey and ModifierKey[m]) then
            log.warn("keybind '%s': modifier %s unavailable", name, m)
            return false
        end
        modCodes[#modCodes + 1] = ModifierKey[m]
    end
    local handler = function() sched.now("key:" .. name, fn) end
    if #modCodes > 0 then
        RegisterKeyBind(keyCode, modCodes, handler)
    else
        RegisterKeyBind(keyCode, handler)
    end
    return true
end

return M
