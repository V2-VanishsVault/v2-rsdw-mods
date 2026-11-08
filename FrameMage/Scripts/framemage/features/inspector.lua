-- Inspector: Ctrl+F9 writes what is on screen right now.
--   dumps/widgets.txt    the game's on-screen widget trees: layout key, class, visibility, brush
--                        (mod overlays and hidden/collapsed branches are left out; see settings.inspector)
--   dumps/textures.txt   the artist's checklist: every UI texture and material effect seen so far, grouped
--                        and sorted by use. The name is the PNG file name to put in Art/<skin>/.
--   dumps/materials.txt  every material effect with its parameters and current values, plus a starter
--                        Art/<skin>/materials.lua entry to copy (theme effects without losing animation)
--   dumps/textures.lua   the same data, merged across dumps and sessions
-- Open each screen you want to cover and press the key again; the checklist keeps growing.
local M = {}

local ctx, W, log
local names = require("framemage.core.names")
local overlay = require("framemage.core.overlay")

local VIS = { [0] = "Visible", "Collapsed", "Hidden", "HitTestInvisible", "SelfHitTestInvisible" }

local function brushInfo(w)
    local ok, info = pcall(function()
        local b = w.Brush
        if not b then b = w.Background end
        if not b then return nil end
        local res = b.ResourceObject
        if not W.valid(res) then return nil end
        local size = b.ImageSize
        local cls = W.className(res)
        return string.format("tex=%s (%s) %dx%d", names.resourceKey(W.name(res), cls), cls,
            math.floor(size.X + 0.5), math.floor(size.Y + 0.5))
    end)
    return ok and info or nil
end

-- Roots worth dumping: the game's own widgets. Frame Mage's overlays and other mods' code-built overlays
-- (plain UserWidget class, no blueprint) are skipped.
local function gameRoot(root)
    if overlay.isOurs(root) then return false end
    local ok, cls = pcall(W.className, root)
    return ok and cls ~= "UserWidget"
end

local function dumpWidgets()
    local includeHidden = ctx.settings.inspector.includeHidden
    local lines = { "# Frame Mage widget dump " .. os.date("%Y-%m-%d %H:%M:%S"),
        "# indent = depth | name [class] key=<layout key> vis=<visibility> [brush]",
        includeHidden and "# hidden/collapsed branches included"
            or "# hidden/collapsed branches omitted (settings: inspector.includeHidden = true to include)", "" }
    local roots, skippedRoots, skippedBranches = 0, 0, 0
    for _, root in ipairs(W.viewportRoots()) do
        if gameRoot(root) then
            roots = roots + 1
            W.walk(root, function(w, depth)
                local okV, vis = pcall(function() return w:GetVisibility() end)
                if not includeHidden and okV and (vis == 1 or vis == 2) and depth > 0 then
                    skippedBranches = skippedBranches + 1
                    return false
                end
                local parts = {
                    string.rep("  ", depth) .. W.name(w),
                    "[" .. W.className(w) .. "]",
                    "key=" .. W.key(w),
                    "vis=" .. (okV and (VIS[vis] or tostring(vis)) or "?"),
                }
                local bi = brushInfo(w)
                if bi then parts[#parts + 1] = bi end
                lines[#lines + 1] = table.concat(parts, " ")
                return true
            end)
            lines[#lines + 1] = ""
        else
            skippedRoots = skippedRoots + 1
        end
    end
    lines[4] = string.format("# %d game roots; skipped %d mod overlays and %d hidden branches",
        roots, skippedRoots, skippedBranches)
    lines[5] = ""
    ctx.fs.write(ctx.dir .. "dumps/widgets.txt", table.concat(lines, "\n"))
    return roots, #lines
end

-- Version-1 data used raw names: one entry per runtime material copy and other mods' textures.
local function migrate(data)
    if data.version == 2 then return data end
    local entries = {}
    for name, rec in pairs(data) do
        if type(rec) == "table" and not name:match("^Texture2D_%d+$") then
            local key = names.resourceKey(name, rec.kind)
            local cur = entries[key]
            if cur then cur.count = (cur.count or 0) + (rec.count or 0)
            else entries[key] = { kind = rec.kind, count = rec.count or 0 } end
        end
    end
    return { version = 2, entries = entries }
end

-- Pure: one texture's checklist line. Unit-tested.
function M.textureLine(done, name, rec)
    local parts = { string.format("[%s] %-56s uses=%d", done and "x" or " ", name, rec.count or 0) }
    if rec.size then parts[#parts + 1] = "size=" .. rec.size end
    if rec.drawn then parts[#parts + 1] = "drawn=" .. rec.drawn end
    if rec.drawAs and rec.drawAs ~= "image" then parts[#parts + 1] = rec.drawAs end
    if rec.where then parts[#parts + 1] = "where=" .. rec.where end
    return table.concat(parts, "  ")
end

-- Pure: checklist lines from entries (exposed for tests).
function M.checklist(entries, hasPng, skinDir)
    local groups = { textures = {}, materials = {} }
    for name, rec in pairs(entries) do
        local bucket = names.isMaterial(rec.kind) and groups.materials or groups.textures
        local sec = names.section(name)
        local g = bucket[sec]
        if not g then g = { name = sec, uses = 0, items = {} }; bucket[sec] = g end
        g.uses = g.uses + (rec.count or 0)
        g.items[#g.items + 1] = { name = name, rec = rec }
    end
    -- single-item groups would fragment the list: fold them into one "Misc" group
    for _, bucket in pairs(groups) do
        local misc
        for sec, g in pairs(bucket) do
            if #g.items == 1 and sec ~= "Misc" then
                misc = misc or bucket.Misc or { name = "Misc", uses = 0, items = {} }
                misc.uses = misc.uses + g.uses
                misc.items[#misc.items + 1] = g.items[1]
                bucket[sec] = nil
            end
        end
        if misc then bucket.Misc = misc end
    end
    local function sorted(bucket)
        local list = {}
        for _, g in pairs(bucket) do
            table.sort(g.items, function(a, b)
                local ua, ub = a.rec.count or 0, b.rec.count or 0
                if ua ~= ub then return ua > ub end
                return a.name < b.name
            end)
            list[#list + 1] = g
        end
        table.sort(list, function(a, b)
            if a.uses ~= b.uses then return a.uses > b.uses end
            return a.name < b.name
        end)
        return list
    end
    local function count(bucket)
        local n, done = 0, 0
        for _, g in pairs(bucket) do
            for _, it in ipairs(g.items) do
                n = n + 1
                if hasPng(it.name) then done = done + 1 end
            end
        end
        return n, done
    end

    local tN, tDone = count(groups.textures)
    local mN, mDone = count(groups.materials)
    local lines = {
        "# Frame Mage art checklist " .. os.date("%Y-%m-%d %H:%M:%S"),
        "# Save <name>.png in " .. skinDir .. " to replace it everywhere; Ctrl+F10 reloads.",
        "# [x] = PNG exists. uses = how often the game drew it while Frame Mage watched (higher = more visible).",
        "",
        string.format("## TEXTURES  %d done / %d", tDone, tN),
        "# Plain images: a PNG replaces them exactly. size = the texture's pixels (make yours the same, or the",
        "# same shape at 2x); drawn = the size the game shows it at; box/border = 9-sliced (corners stay fixed,",
        "# edges stretch); where = the first element seen using it.",
        "",
    }
    for _, g in ipairs(sorted(groups.textures)) do
        lines[#lines + 1] = string.format("### %s  (%d, uses %d)", g.name, #g.items, g.uses)
        for _, it in ipairs(g.items) do
            lines[#lines + 1] = M.textureLine(hasPng(it.name), it.name, it.rec)
        end
        lines[#lines + 1] = ""
    end
    lines[#lines + 1] = string.format("## MATERIAL EFFECTS  %d done / %d", mDone, mN)
    lines[#lines + 1] = "# Shader-driven (bars, rings, highlights, vignettes). A PNG turns them into a flat image and"
    lines[#lines + 1] = "# loses fills and animation; theme these with colour/material changes instead."
    lines[#lines + 1] = ""
    for _, g in ipairs(sorted(groups.materials)) do
        lines[#lines + 1] = string.format("### %s  (%d, uses %d)", g.name, #g.items, g.uses)
        for _, it in ipairs(g.items) do
            local note = it.rec.parent and (" copy of " .. it.rec.parent) or ""
            lines[#lines + 1] = string.format("[%s] %-56s uses=%d  %s%s", hasPng(it.name) and "x" or " ",
                it.name, it.rec.count or 0, it.rec.kind or "?", note)
        end
        lines[#lines + 1] = ""
    end
    return lines, tN, mN
end

local function dumpTextures()
    local dataPath = ctx.dir .. "dumps/textures.lua"
    local data = migrate(ctx.config.load(dataPath, {}))
    local art = ctx.features.art
    for name, rec in pairs(art and art.seen or {}) do
        local cur = data.entries[name] or { kind = rec.kind, count = 0 }
        cur.count = math.max(cur.count or 0, rec.count)
        cur.parent = cur.parent or rec.parent
        cur.params = rec.params or cur.params
        cur.size = rec.size or cur.size
        cur.drawn = rec.drawn or cur.drawn
        cur.drawAs = rec.drawAs or cur.drawAs
        cur.where = cur.where or rec.where
        data.entries[name] = cur
    end
    ctx.config.save(dataPath, data)

    local skinDir = ctx.themes.dir()
    local lines, tN, mN = M.checklist(data.entries, function(n) return ctx.themes.find(n .. ".png") ~= nil end,
        skinDir)
    ctx.fs.write(ctx.dir .. "dumps/textures.txt", table.concat(lines, "\n"))
    ctx.fs.write(ctx.dir .. "dumps/materials.txt", table.concat(M.materialSheet(data.entries), "\n"))
    return tN, mN
end

M.migrate = migrate

local function fmtNum(v)
    if type(v) ~= "number" then return "0" end
    return (string.format("%.3f", v):gsub("0+$", ""):gsub("%.$", ""))
end

local function luaKey(k)
    if k:match("^[%a_][%w_]*$") then return k end
    return "[" .. string.format("%q", k) .. "]"
end

-- Pure: the parameter sheet for material effects (exposed for tests).
function M.materialSheet(entries)
    local list = {}
    for name, rec in pairs(entries) do
        if names.isMaterial(rec.kind) then list[#list + 1] = { name = name, rec = rec } end
    end
    table.sort(list, function(a, b)
        local ua, ub = a.rec.count or 0, b.rec.count or 0
        if ua ~= ub then return ua > ub end
        return a.name < b.name
    end)
    local lines = {
        "-- Frame Mage material effects " .. os.date("%Y-%m-%d %H:%M:%S"),
        "-- Theme these in Art/<skin>/materials.lua (Ctrl+F10 reloads). Each block is a starter entry: copy it",
        "-- inside `return { ... }`, keep only the parameters you want to change, and edit the values.",
        "-- Key by the effect name, or by its 'copy of' material to cover every effect built from it.",
        "-- Vector values below are linear; hex strings (\"#4FA3FF\") in your file are treated as sRGB.",
        "-- Parameters the game animates itself (fills, pulses) need force = true to stick.",
        "",
    }
    for _, it in ipairs(list) do
        local r, p = it.rec, it.rec.params
        lines[#lines + 1] = string.format("-- %s  (%s%s, uses %d)", it.name, r.kind or "?",
            r.parent and (", copy of " .. r.parent) or "", r.count or 0)
        local empty = not p or (next(p.scalars or {}) == nil and next(p.vectors or {}) == nil
            and next(p.textures or {}) == nil)
        if empty then
            lines[#lines + 1] = "--   (no parameters read yet: dump again while it is on screen; some effects have none)"
        else
            lines[#lines + 1] = luaKey(it.name) .. " = {"
            local function block(kind, fmt)
                local keys = {}
                for k in pairs(p[kind] or {}) do keys[#keys + 1] = k end
                if #keys == 0 then return end
                table.sort(keys)
                lines[#lines + 1] = "    " .. kind .. " = {"
                for _, k in ipairs(keys) do
                    lines[#lines + 1] = "        " .. luaKey(k) .. " = " .. fmt(p[kind][k]) .. ","
                end
                lines[#lines + 1] = "    },"
            end
            block("scalars", fmtNum)
            block("vectors", function(c)
                return string.format("{ %s, %s, %s, %s }", fmtNum(c[1]), fmtNum(c[2]), fmtNum(c[3]), fmtNum(c[4]))
            end)
            block("textures", function(t) return string.format("%q, -- now: %s", "my_" .. tostring(t), tostring(t)) end)
            lines[#lines + 1] = "},"
        end
        lines[#lines + 1] = ""
    end
    return lines
end

function M.dump()
    local roots, lines = dumpWidgets()
    local tN, mN = dumpTextures()
    log.info("dump: %d game roots, %d widget lines, %d textures + %d material effects -> %sdumps/",
        roots, lines, tN, mN, ctx.dir)
    local editor = ctx.features.editor
    if editor then
        editor.flash(string.format("Frame Mage: dumped %d widget lines; %d textures, %d effects", lines, tN, mN))
    end
end

-- API dump (Numpad +, keys.dumpApi) -----------------------------------------------------------------------------------
-- The game's functions for the classes a feature needs to drive (the hotbar, items, spells; and for Storage Mage:
-- crafting, workbenches, pickups, loot and carry weight), with their
-- parameters, from runtime reflection: the .usmap type map only has data fields. Written to dumps/api.txt.

-- Pure: should a class with this name be in the API dump? Unit-tested.
M.API_PATTERNS = { "QuickAccess", "Inventory", "Loadout", "Equipment", "Spellcasting", "SpellBook", "Spellbook",
    "SpellData", "SpellPayload", "Radial", "ItemSlot", "ItemData", "ItemStack", "HeldEquipment", "Hotbar",
    "PlayerCharacter", "DomPlayerController", "ActionBar",
    -- Storage Mage (bags): crafting and workbenches, pickups and loot, carry weight
    "Crafting", "Recipe", "Station", "Pickup", "Pickupable", "Loot", "CarryWeight", "ItemWeight", "WeightBar" }
function M.wantsApi(className)
    if className:match("^Default__") or className:match("^SKEL_") or className:match("^REINST_") then return false end
    for _, p in ipairs(M.API_PATTERNS) do
        if className:find(p, 1, true) then return true end
    end
    return false
end

-- Only the safest reflection calls: names, and each parameter's name and property type. (An earlier version also
-- asked parameters for their classes / structs / flags; one of those crashed the game natively, where pcall can't
-- help.) Each step is logged before it runs, so if the game ever does go down, the log shows where.
local function paramText(prop)
    local okN, name = pcall(function() return prop:GetFName():ToString() end)
    local okT, typ = pcall(function() return prop:GetClass():GetFName():ToString() end)
    return (okT and typ:gsub("Property$", "") or "?") .. " " .. (okN and name or "?")
end

local function functionLine(fn)
    local okN, name = pcall(function() return fn:GetFName():ToString() end)
    local params = {}
    pcall(function()
        fn:ForEachProperty(function(prop) params[#params + 1] = paramText(prop) end)
    end)
    return string.format("  %s(%s)", okN and name or "?", table.concat(params, ", "))
end

-- Pure: the script module a class path lives in ("/Script/Dominion.InventoryComponent" -> "Dominion"). Unit-tested.
function M.moduleOf(path)
    if type(path) ~= "string" then return nil end
    return path:match("/Script/([%w_]+)%.")
end

-- The classes come from data/api_classes.lua (made from the game's type map by tools/gen_api_classes.py): this
-- UE4SS build can't list classes in game, so each is looked up by name: by its script path (fast), or for
-- blueprint classes (..._C) from a live instance. Each step is logged before it runs.
function M.dumpApi()
    local t0 = os.clock()
    local okL, names = pcall(require, "framemage.data.api_classes")
    if not okL or type(names) ~= "table" then log.warn("API dump: no class list (%s)", tostring(names)) return end
    -- the game's own script module, learned from a class we know is there
    local modules, seenMod = {}, {}
    local function addModule(m) if m and not seenMod[m] then seenMod[m] = true; modules[#modules + 1] = m end end
    for _, probe in ipairs({ "InventoryComponent", "SpellcastingComponent", "PlayerController" }) do
        log.info("API dump: looking for a live %s", probe)
        local inst = FindFirstOf(probe)
        if W.valid(inst) then
            pcall(function() addModule(M.moduleOf(inst:GetClass():GetPathName())) end)
        end
    end
    for _, m in ipairs({ "Dominion", "DominionUI", "RSDragonwilds", "CommonUI", "CommonInput", "UMG", "Engine" }) do
        addModule(m)
    end
    log.info("API dump: modules %s; %d classes to look up", table.concat(modules, ", "), #names)

    local lines = { "# Frame Mage API dump " .. os.date("%Y-%m-%d %H:%M:%S"),
        "# Game classes Frame Mage and Storage Mage need (hotbar, items, spells, crafting, pickups, weight),",
        "# with their functions and each parameter's name and type. Modules searched: " .. table.concat(modules, ", "),
        "" }
    local nClasses, nFns, missing = 0, 0, {}
    for _, name in ipairs(names) do
        local cls
        for _, m in ipairs(modules) do
            local c = StaticFindObject("/Script/" .. m .. "." .. name)
            if W.valid(c) then cls = c break end
        end
        if not cls and name:match("_C$") then
            local inst = FindFirstOf(name)
            if W.valid(inst) then pcall(function() cls = inst:GetClass() end) end
        end
        if cls then
            local fns, err = {}, nil
            local ok, e = pcall(function()
                cls:ForEachFunction(function(fn) fns[#fns + 1] = functionLine(fn) end)
            end)
            if not ok then err = tostring(e) end
            if #fns > 0 or err then
                table.sort(fns)
                local okS, super = pcall(function() return cls:GetSuperStruct():GetFName():ToString() end)
                local okP, path = pcall(function() return cls:GetPathName() end)
                lines[#lines + 1] = string.format("%s : %s    (%s)%s", name, okS and super or "?", okP and path or "",
                    err and ("  [error: " .. err .. "]") or "")
                for _, f in ipairs(fns) do lines[#lines + 1] = f end
                lines[#lines + 1] = ""
                nClasses, nFns = nClasses + 1, nFns + #fns
            end
        else
            missing[#missing + 1] = name
        end
    end
    lines[#lines + 1] = "# Not found (structs, or not loaded right now): " .. table.concat(missing, ", ")
    ctx.fs.write(ctx.dir .. "dumps/api.txt", table.concat(lines, "\n"))
    log.info("API dump: %d classes, %d functions in %.1f s (%d not found) -> dumps/api.txt", nClasses, nFns,
        os.clock() - t0, #missing)
    local legend = require("framemage.editor.legend")
    if legend.flash then legend.flash(string.format("API dump: %d classes, %d functions", nClasses, nFns)) end
end

function M.init(c)
    ctx, W, log = c, c.widgets, c.log
    c.keys.bind(c.settings.keys.dump, "dump", M.dump)
    c.keys.bind(c.settings.keys.dumpApi, "dumpApi", function()
        local ok, err = pcall(M.dumpApi)
        if not ok then log.error("API dump failed: %s", tostring(err)) end
    end)
end

return M
