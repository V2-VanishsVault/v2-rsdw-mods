-- Data-only serialization for the Settings panel (a copy of Frame Mage's core/serialize: the panel shares no code with any mod).
-- Data files look like:  return { x = 1, ["WBP_HUD/Bar"] = { ... } }
local M = {}

local function fmtNumber(n)
    if math.type and math.type(n) == "integer" then return tostring(n) end
    if n ~= n or n == math.huge or n == -math.huge then return "0" end
    local s = string.format("%.4f", n):gsub("0+$", ""):gsub("%.$", "")
    if s == "-0" then s = "0" end
    return s
end

local function fmtKey(k)
    if type(k) == "string" and k:match("^[%a_][%w_]*$") then return k end
    if type(k) == "number" then return "[" .. fmtNumber(k) .. "]" end
    return "[" .. string.format("%q", tostring(k)) .. "]"
end

local function sortKeys(t)
    local keys = {}
    for k in pairs(t) do keys[#keys + 1] = k end
    table.sort(keys, function(a, b)
        local ta, tb = type(a), type(b)
        if ta ~= tb then return ta < tb end
        return a < b
    end)
    return keys
end

local function isArray(t)
    local n = #t
    for k in pairs(t) do
        if type(k) ~= "number" or k < 1 or k > n or k % 1 ~= 0 then return false end
    end
    return true
end

local function dump(v, indent, seen)
    local tv = type(v)
    if tv == "number" then return fmtNumber(v) end
    if tv == "string" then return string.format("%q", v) end
    if tv == "boolean" or tv == "nil" then return tostring(v) end
    if tv ~= "table" then return "nil" end
    if seen[v] then error("serialize: cycle detected") end
    seen[v] = true
    if next(v) == nil then seen[v] = nil return "{}" end
    local pad = string.rep("    ", indent + 1)
    local parts = {}
    if isArray(v) then
        for _, item in ipairs(v) do parts[#parts + 1] = pad .. dump(item, indent + 1, seen) end
    else
        for _, k in ipairs(sortKeys(v)) do
            parts[#parts + 1] = pad .. fmtKey(k) .. " = " .. dump(v[k], indent + 1, seen)
        end
    end
    seen[v] = nil
    return "{\n" .. table.concat(parts, ",\n") .. ",\n" .. string.rep("    ", indent) .. "}"
end

function M.dump(v)
    return "return " .. dump(v, 0, {}) .. "\n"
end

-- Loads a data file with an empty environment: no access to io/os/UE4SS.
function M.parse(text, chunkname)
    if not text then return nil, "no text" end
    local fn, err = load(text, chunkname or "data", "t", {})
    if not fn then return nil, err end
    local ok, result = pcall(fn)
    if not ok then return nil, result end
    if type(result) ~= "table" then return nil, "data file must return a table" end
    return result
end

return M
