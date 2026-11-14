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
    -- list entries: a ListView makes its rows itself, outside its own widget tree, so the walk above never reaches
    -- them (status effects, buffs, spell timers...); each visible one is dumped on its own
    local entries = 0
    for _, e in pairs(FindAllOf("UserWidget") or {}) do
        local okC, cls = pcall(W.className, e)
        if okC and cls:find("ListEntry", 1, true) and W.valid(e) and W.isInstance(e) and W.isVisible(e) then
            entries = entries + 1
            lines[#lines + 1] = "# list entry " .. cls
            W.walk(e, function(w, depth)
                local okV, vis = pcall(function() return w:GetVisibility() end)
                local parts = { string.rep("  ", depth) .. W.name(w), "[" .. W.className(w) .. "]",
                    "vis=" .. (okV and (VIS[vis] or tostring(vis)) or "?") }
                local bi = brushInfo(w)
                if bi then parts[#parts + 1] = bi end
                lines[#lines + 1] = table.concat(parts, " ")
                return true
            end)
            lines[#lines + 1] = ""
        end
    end
    lines[4] = string.format("# %d game roots and %d list entries; skipped %d mod overlays and %d hidden branches",
        roots, entries, skippedRoots, skippedBranches)
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
    lines[#lines + 1] = "# loses fills and animation; theme these with color/material changes instead."
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

-- Item icons showing a selection border -------------------------------------------------------------------------
-- Every item icon is drawn with one material (MI_Item_Selected) that also draws its border: the equipped / held
-- border in the inventory, the animated selection on a crafting table. dumps/selection.txt lists, per dump (added
-- to the end, so dumps from different screens sit side by side), each icon on screen whose border shows, where it
-- is, and all its material settings, plus one plain icon to compare with.

-- Pure: does an item icon with these material settings show a selection border? Unit-tested.
function M.showsSelection(params)
    local s = params and params.scalars or {}
    return (tonumber(s["Selection Opacity"]) or 0) > 0 or (tonumber(s["MW HBorder Opacity"]) or 0) > 0
end

-- Pure: the lines for one icon's settings (sorted, so two dumps can be compared line by line). Unit-tested.
function M.paramLines(params)
    local out = {}
    for _, kind in ipairs({ "scalars", "vectors", "textures" }) do
        local keys = {}
        for k in pairs(params[kind] or {}) do keys[#keys + 1] = k end
        table.sort(keys)
        for _, k in ipairs(keys) do
            local v = params[kind][k]
            if type(v) == "table" then
                v = string.format("{ %.3f, %.3f, %.3f, %.3f }", v[1] or 0, v[2] or 0, v[3] or 0, v[4] or 0)
            elseif type(v) == "number" then v = string.format("%.4g", v) end
            out[#out + 1] = string.format("    %-8s %-40s %s", kind:sub(1, 6), k, tostring(v))
        end
    end
    return out
end

local function dumpSelection()
    local mats = ctx.features.materials
    if not mats then return 0 end
    local lines = { "", "== " .. os.date("%Y-%m-%d %H:%M:%S") .. " ==" }
    local n, plain = 0, false
    for _, img in pairs(FindAllOf("Image") or {}) do
        if W.valid(img) and W.isVisible(img) then
            local ok, res = pcall(function() return img.Brush.ResourceObject end)
            local okP, parent = pcall(function() return res.Parent end)
            if ok and okP and W.valid(res) and W.valid(parent) and W.name(parent) == "MI_Item_Selected" then
                local okD, params = pcall(mats.describe, res)
                if okD then
                    local sel = M.showsSelection(params)
                    if sel or not plain then
                        if not sel then plain = true end
                        local okK, key = pcall(W.key, img)
                        lines[#lines + 1] = string.format("%s  %s", sel and "SELECTED" or "plain   ", okK and key or "?")
                        for _, l in ipairs(M.paramLines(params)) do lines[#lines + 1] = l end
                        if sel then n = n + 1 end
                    end
                end
            end
        end
    end
    local path = ctx.dir .. "dumps/selection.txt"
    ctx.fs.write(path, (ctx.fs.read(path) or "") .. table.concat(lines, "\n") .. "\n")
    return n
end

function M.dump()
    local roots, lines = dumpWidgets()
    local tN, mN = dumpTextures()
    local okS, sN = pcall(dumpSelection)
    if okS then log.info("dump: %d item icons with a selection border -> dumps/selection.txt", sN)
    else log.warn("dump: selection borders not listed: %s", tostring(sN)) end
    log.info("dump: %d game roots, %d widget lines, %d textures + %d material effects -> %sdumps/",
        roots, lines, tN, mN, ctx.dir)
    local editor = ctx.features.editor
    if editor then
        editor.flash(string.format("Frame Mage: dumped %d widget lines; %d textures, %d effects", lines, tN, mN))
    end
end

function M.init(c)
    ctx, W, log = c, c.widgets, c.log
    c.keys.bind(c.settings.keys.dump, "dump", M.dump)
    c.keys.bind(c.settings.keys.dumpLater, "dumpLater", function()
        log.info("dump in 5 seconds: open the menu to capture now")
        local editor = c.features.editor
        if editor then editor.flash("Dumping in 5 seconds...") end
        c.sched.later(5000, "inspector.dumpLater", function()
            local ok, err = pcall(M.dump)
            if not ok then log.error("delayed dump failed: %s", tostring(err)) end
            if editor then editor.flash(ok and "Dumped: see dumps/ in the mod folder" or "Dump failed: see the log") end
        end)
    end)
end

return M
