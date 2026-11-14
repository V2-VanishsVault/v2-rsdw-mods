-- Load/save data files, merged over defaults.
local fs = require("storagemage.core.fs")
local serialize = require("storagemage.core.serialize")
local log = require("storagemage.core.log")

local M = {}

function M.deepCopy(v)
    if type(v) ~= "table" then return v end
    local out = {}
    for k, x in pairs(v) do out[k] = M.deepCopy(x) end
    return out
end

-- Values from `over` win; tables merge recursively; arrays in `over` replace wholesale.
function M.merge(base, over)
    local out = M.deepCopy(base)
    if type(over) ~= "table" then return out end
    for k, v in pairs(over) do
        if type(v) == "table" and type(out[k]) == "table" and #v == 0 and next(v) ~= nil then
            out[k] = M.merge(out[k], v)
        else
            out[k] = M.deepCopy(v)
        end
    end
    return out
end

function M.load(path, defaults)
    local text = fs.read(path)
    if not text then return M.deepCopy(defaults or {}) end
    local data, err = serialize.parse(text, path)
    if not data then
        log.error("could not read %s (%s); using defaults. Your file was kept as %s.bad", path, tostring(err), path)
        fs.write(path .. ".bad", text)
        return M.deepCopy(defaults or {})
    end
    return M.merge(defaults or {}, data)
end

-- Pure: the parts of `current` that differ from `defaults` (what a user actually changed).
-- Arrays compare as a whole. Keys that don't exist in defaults are returned in `unknown` (typos, retired
-- settings) and left out of the result.
function M.diff(defaults, current, prefix, unknown)
    unknown = unknown or {}
    local out = {}
    for k, v in pairs(current or {}) do
        local d = defaults[k]
        local path = (prefix and (prefix .. ".") or "") .. tostring(k)
        if d == nil then
            unknown[#unknown + 1] = path
        elseif type(v) == "table" and type(d) == "table" and not (#v > 0 or #d > 0) then
            local sub = M.diff(d, v, path, unknown)
            if next(sub) then out[k] = sub end
        elseif not M.equal(v, d) then
            out[k] = M.deepCopy(v)
        end
    end
    return out, unknown
end

function M.equal(a, b)
    if type(a) ~= type(b) then return false end
    if type(a) ~= "table" then return a == b end
    for k, v in pairs(a) do if not M.equal(v, b[k]) then return false end end
    for k in pairs(b) do if a[k] == nil then return false end end
    return true
end

function M.save(path, data, header)
    local ok, err = fs.write(path, (header or "") .. serialize.dump(data))
    if not ok then log.error("could not save %s: %s", path, tostring(err)) end
    return ok
end

return M
