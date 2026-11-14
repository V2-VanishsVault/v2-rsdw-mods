-- The Settings panel's data protocol: pure functions, no game calls (unit-tested by every mod's tests).
--
-- Every mod that takes part describes its settings as data (a schema), publishes it and its current values through
-- UE4SS shared variables, and gets changes back as requests. One copy of the panel draws for all of them; which copy
-- is decided by the host claim below. Shared variables (all strings or numbers):
--
--   SettingsPanel.host       "<version>|<Mod>": the copy that draws      SettingsPanel.hostBeat   bumped every 2 s
--   SettingsPanel.registry   "FrameMage,StorageMage": the mods taking part
--   SettingsPanel.<Mod>.schema, .values, .valuesRev                  the mod's settings and their current values
--   SettingsPanel.<Mod>.request, .requestRev                         changes and button presses sent to the mod
--   SettingsPanel.prefs, .prefsRev                                   the panel's own: open key, position, last tab
--   SettingsPanel.open (0/1), SettingsPanel.box "l,t,r,b", SettingsPanel.closedAt   for Frame Mage's editor
local M = {}

M.PROTOCOL = 1

-- Row kinds. A schema may use Frame Mage's older names; they map onto these. A kind the panel doesn't know is
-- skipped (a newer mod's row shown by an older panel), never an error.
M.KIND = {
    bool = "bool", toggle = "bool",
    number = "number", int = "number", float = "number",
    slider = "slider",
    choice = "choice",
    key = "key",
    action = "action", button = "action",
    text = "text", info = "text",
}

function M.kind(row) return row and M.KIND[row.type] end

-- Host claim ---------------------------------------------------------------------------------------------------

function M.hostValue(version, mod) return tostring(version) .. "|" .. tostring(mod) end

function M.parseHost(s)
    if type(s) ~= "string" then return nil end
    local v, mod = s:match("^(%d+)|(.+)$")
    if not v then return nil end
    return tonumber(v), mod
end

-- Should this copy (version, mod) take the host from `current`? An empty or unreadable host, an older version, or
-- the same version from a mod whose name sorts later. (The newest copy draws; ties go to the first name.)
function M.shouldClaim(current, version, mod)
    local cv, cmod = M.parseHost(current)
    if not cv then return true end
    if cmod == mod then return cv <= version end
    if cv ~= version then return cv < version end
    return mod < cmod
end

-- Has the host's heartbeat stopped? (lastChange: when the beat was last seen to change; nil = never seen)
M.BEAT_SECONDS, M.STALE_SECONDS = 2, 6
function M.stale(lastChange, now, timeout)
    return lastChange == nil or now - lastChange > (timeout or M.STALE_SECONDS)
end

-- Registry -----------------------------------------------------------------------------------------------------

function M.split(list)
    local out = {}
    for name in tostring(list or ""):gmatch("[^,]+") do out[#out + 1] = name end
    return out
end

-- The list with `mod` in it (once), sorted, as a string.
function M.addTo(list, mod)
    local names, seen = {}, {}
    for _, n in ipairs(M.split(list)) do if not seen[n] then seen[n] = true; names[#names + 1] = n end end
    if not seen[mod] then names[#names + 1] = mod end
    table.sort(names)
    return table.concat(names, ",")
end

-- Schema -------------------------------------------------------------------------------------------------------

-- A schema as a mod publishes it:
--   { protocol = 1, mod = "StorageMage", title = "Storage Mage", order = 20,
--     tabs = { { id = "bags", label = "Bags" }, ... },        -- (one tab: the mod's sections all on it)
--     rows = { { tab = "bags", type = "bool", setting = "pickupRouting", label = "...", tooltip = "...",
--                applies = "restart", owner = "server" }, ... } }
-- Row fields: type (see KIND), label, setting (the mod's own name for it, often a dot path), tooltip; choice:
-- options + labels (+ icons: game texture names); number / slider: min, max, step, suffix, percent; action: action
-- (its name) + confirm; heading = true makes a section heading (a text row drawn as one).
-- Pure: a schema made safe to draw: unknown kinds dropped, rows without a tab put on the first, and what was dropped
-- noted. Returns schema (a new table) and a list of notes, or nil and a reason.
function M.clean(s)
    if type(s) ~= "table" then return nil, "not a table" end
    if type(s.protocol) ~= "number" then return nil, "no protocol" end
    local tabs, ids = {}, {}
    for _, t in ipairs(type(s.tabs) == "table" and s.tabs or {}) do
        if type(t) == "table" and type(t.id) == "string" and not ids[t.id] then
            ids[t.id] = true
            tabs[#tabs + 1] = { id = t.id, label = tostring(t.label or t.id) }
        end
    end
    if #tabs == 0 then tabs[1] = { id = "main", label = tostring(s.title or s.mod or "Settings") }; ids.main = true end
    local rows, notes = {}, {}
    for i, r in ipairs(type(s.rows) == "table" and s.rows or {}) do
        local kind = type(r) == "table" and M.kind(r)
        if not kind then
            notes[#notes + 1] = ("row %d: unknown type %s, skipped"):format(i, type(r) == "table" and tostring(r.type) or "?")
        else
            local c = {}
            for k, v in pairs(r) do c[k] = v end
            c.kind = kind
            if not ids[c.tab] then c.tab = tabs[1].id end
            c.label = tostring(c.label or c.setting or c.action or "")
            if kind == "choice" and type(c.options) ~= "table" then c.options = {} end
            rows[#rows + 1] = c
        end
    end
    return { protocol = s.protocol, mod = s.mod, title = tostring(s.title or s.mod or "?"), order = tonumber(s.order) or 50,
        tabs = tabs, rows = rows }, notes
end

-- The rows of one tab, in order.
function M.rowsOf(schema, tab)
    local out = {}
    for _, r in ipairs(schema and schema.rows or {}) do if r.tab == tab then out[#out + 1] = r end end
    return out
end

-- Mods in the order their tabs show: by `order`, then title.
function M.sortMods(list)
    table.sort(list, function(a, b)
        if (a.order or 50) ~= (b.order or 50) then return (a.order or 50) < (b.order or 50) end
        return tostring(a.title) < tostring(b.title)
    end)
    return list
end

-- Values and requests --------------------------------------------------------------------------------------------

-- What a mod publishes: { values = { [setting] = value }, lastRequest = id, serverOwned = bool }.
-- What the panel sends:  { id = n, set = { setting = "x", value = v } } or { id = n, action = "name" }.
function M.request(id, setting, value) return { id = id, set = { setting = setting, value = value } } end
function M.actionRequest(id, name) return { id = id, action = name } end

-- Is a change the panel sent still waiting for the mod (not echoed back in lastRequest yet)?
function M.pending(sentId, values)
    return sentId ~= nil and (type(values) ~= "table" or (tonumber(values.lastRequest) or 0) < sentId)
end

-- A change the mod refused, for a request the panel sent: the reason, or nil.
-- (values.refused = { id = <request id>, reason = "..." }, published by the client)
function M.refusal(sentId, values)
    local r = type(values) == "table" and values.refused
    if sentId and type(r) == "table" and tonumber(r.id) == sentId then return tostring(r.reason or "Not accepted") end
    return nil
end

-- Is a row read-only right now? (a server-owned setting on a client joined to a server)
function M.readOnly(row, values)
    return row.owner == "server" and type(values) == "table" and values.serverOwned == true
end

-- Keys ------------------------------------------------------------------------------------------------------------

-- Pure: a key spec in one spelling, for comparing ("ctrl + f4" and "CTRL+F4" are the same key).
function M.normKey(spec)
    if type(spec) ~= "string" then return nil end
    local s = spec:upper():gsub("%s", ""):gsub("CONTROL%+", "CTRL+")
    if s == "" or s == "NONE" then return nil end
    return s
end

-- Pure: who else uses `spec`? Every key row of every mod (and the panel's own open key) is checked, except the row
-- being set. mods: { { name, schema, values } }. Returns "Mod title: row label", or nil when the key is free.
function M.keyTakenBy(mods, mod, setting, spec)
    local want = M.normKey(spec)
    if not want then return nil end
    for _, m in ipairs(mods) do
        local values = m.values and m.values.values or {}
        for _, r in ipairs(m.schema and m.schema.rows or {}) do
            local kind = r.kind or M.kind(r)
            if kind == "key" and r.setting and not (m.name == mod and r.setting == setting)
                and M.normKey(values[r.setting]) == want then
                return tostring(m.schema.title) .. ": " .. tostring(r.label)
            end
        end
    end
    return nil
end

-- Showing and stepping values -------------------------------------------------------------------------------------

-- The next value of a choice (dir = 1 or -1, wrapping).
function M.cycle(options, current, dir)
    local n = #options
    if n == 0 then return current end
    local i = 1
    for k, v in ipairs(options) do if v == current then i = k break end end
    return options[((i - 1 + (dir or 1)) % n) + 1]
end

-- A number stepped and kept in range (snapped to the step, no float drift).
function M.step(row, current, dir)
    local s = row.step or 1
    local v = (tonumber(current) or row.min or 0) + (dir or 1) * s
    v = math.floor(v / s + 0.5) * s
    v = math.max(row.min or v, math.min(row.max or v, v))
    if s == math.floor(s) and v == math.floor(v) then v = math.floor(v) end
    return v
end

-- How a row's value reads ("On", "Elven", "16 px", "75%").
function M.display(row, v)
    local kind = row.kind or M.kind(row)
    if kind == "bool" then return v and "On" or "Off" end
    if kind == "choice" then return (row.labels and row.labels[v]) or tostring(v) end
    if kind == "slider" and row.percent then return string.format("%d%%", math.floor((tonumber(v) or 0) * 100 + 0.5)) end
    if kind == "number" or kind == "slider" then
        local n = tonumber(v) or 0
        local s = (n == math.floor(n)) and string.format("%d", n) or string.format("%.2f", n)
        return s .. (row.suffix or "")
    end
    if v == nil then return "" end
    return tostring(v)
end

-- A confirm button runs only on a second click within CONFIRM_SECONDS of the first. armed = { key, at } or nil.
M.CONFIRM_SECONDS = 4
function M.isArmed(armed, key, now)
    return armed ~= nil and armed.key == key and now - armed.at <= M.CONFIRM_SECONDS
end

-- Layout ---------------------------------------------------------------------------------------------------------

-- A position that keeps a w x h panel on screen (where it fits; else its top left corner, so the title bar can
-- always be grabbed).
function M.onScreen(x, y, sw, sh, w, h)
    sw, sh = sw or 1920, sh or 1080
    return math.max(0, math.min(x, sw - (w or 80))), math.max(0, math.min(y, sh - (h or 28)))
end

-- Cells of equal width across `width` for `n` buttons with `gap` between them: list of { x, w }.
function M.cells(width, n, gap)
    local out = {}
    if n <= 0 then return out end
    local w = (width - gap * (n - 1)) / n
    for i = 1, n do out[i] = { x = (i - 1) * (w + gap), w = w } end
    return out
end

-- The box "l,t,r,b" as a string, and back.
function M.boxString(r)
    local f = function(v) return math.floor((tonumber(v) or 0) + 0.5) end
    return string.format("%d,%d,%d,%d", f(r.left), f(r.top), f(r.right), f(r.bottom))
end
function M.parseBox(s)
    local l, t, r, b = tostring(s or ""):match("^(%-?%d+),(%-?%d+),(%-?%d+),(%-?%d+)$")
    if not l then return nil end
    return { left = tonumber(l), top = tonumber(t), right = tonumber(r), bottom = tonumber(b) }
end
function M.contains(r, x, y) return r ~= nil and x >= r.left and x <= r.right and y >= r.top and y <= r.bottom end

-- A cheap checksum of text (FNV-1a, 32 bits), for the version check: a file changed, the version must go up.
function M.checksum(text)
    local h = 2166136261
    for i = 1, #text do
        h = h ~ text:byte(i)
        h = (h * 16777619) % 4294967296
    end
    return string.format("%08x", h)
end

return M
