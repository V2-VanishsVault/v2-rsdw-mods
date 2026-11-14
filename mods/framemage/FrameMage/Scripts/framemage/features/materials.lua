-- Materials: theme animated/shader UI effects by changing their parameters, keeping the animation.
--
-- Theme file: the theme's materials.lua (Art/themes/<theme>/, else Elven's) (format in core/theme.lua). Parameter names per effect are listed in
-- dumps/materials.txt after a Ctrl+F9 dump.
--
-- How it applies:
--   * MaterialInstanceDynamic brushes (the game's per-widget copies): parameters are set directly.
--   * MaterialInstanceConstant / Material brushes (shared assets): we never edit a shared asset; the brush gets
--     its own dynamic copy, and that copy is themed.
--   * force = true: the game often drives a parameter itself (fill amount, pulse color). Hooks on the
--     parameter setters re-apply the theme value right after the game's write. Only installed when needed.
-- Originals are captured before the first override, so removing an entry and reloading (Ctrl+F10) restores them.
-- Like art.lua, no widget or material handles are kept between ticks except our own created copies' names.
local M = {}

local theme = require("framemage.core.theme")
local names = require("framemage.core.names")

local ctx, W, log
local entries = {} -- normalized theme
local originals = {} -- effect key -> { scalars = {p = v}, vectors = {p = {R,G,B,A}}, textures = {p = pathName} }
local applied = {} -- effect key -> { ["s:Param"] = true, ["v:Param"] = true, ["t:Param"] = true }
local ownCopies = {} -- fullName of a dynamic copy we created -> { key =, parent = }
local hooksInstalled = false
local inSet = false

local function themePath()
    return ctx.themes.find("materials.lua") or (ctx.themes.dir() .. "materials.lua")
end

function M.loadTheme()
    local text = ctx.fs.read(themePath())
    if not text then entries = {} return 0 end
    local raw, err = ctx.serialize.parse(text, themePath())
    if not raw then
        log.error("materials.lua not loaded: %s", tostring(err))
        entries = {}
        return 0
    end
    local problems
    entries, problems = theme.normalize(raw)
    for _, p in ipairs(problems) do log.warn("materials.lua: %s", p) end
    local n = 0
    for _ in pairs(entries) do n = n + 1 end
    return n
end

-- Parameter discovery ---------------------------------------------------------------
-- Instances store overrides in three arrays; walking up the parent chain collects every parameter that some
-- instance sets. (Defaults that live only in the base material's graph aren't readable at runtime.)
local ARRAYS = {
    { prop = "ScalarParameterValues", kind = "scalars" },
    { prop = "VectorParameterValues", kind = "vectors" },
    { prop = "TextureParameterValues", kind = "textures" },
}

function M.describe(mi)
    local out = { scalars = {}, vectors = {}, textures = {} }
    local cur, depth = mi, 0
    while cur and W.valid(cur) and depth < 6 do
        for _, a in ipairs(ARRAYS) do
            pcall(function()
                cur[a.prop]:ForEach(function(_, el)
                    local v = el:get()
                    local pname = v.ParameterInfo.Name:ToString()
                    if out[a.kind][pname] == nil then -- nearest instance wins (that's what renders)
                        local val = v.ParameterValue
                        if a.kind == "scalars" then out.scalars[pname] = val
                        elseif a.kind == "vectors" then out.vectors[pname] = { val.R, val.G, val.B, val.A }
                        else out.textures[pname] = W.valid(val) and W.name(val) or "none" end
                    end
                end)
            end)
        end
        local ok, parent = pcall(function() return cur.Parent end)
        cur = ok and parent or nil
        depth = depth + 1
    end
    return out
end

-- Applying -------------------------------------------------------------------------------

local function captureOriginal(mid, key, kind, p)
    originals[key] = originals[key] or { scalars = {}, vectors = {}, textures = {} }
    local o = originals[key][kind]
    if o[p] ~= nil then return end
    pcall(function()
        if kind == "scalars" then o[p] = mid:K2_GetScalarParameterValue(FName(p))
        elseif kind == "vectors" then
            local c = mid:K2_GetVectorParameterValue(FName(p))
            o[p] = { R = c.R, G = c.G, B = c.B, A = c.A }
        else
            local t = mid:K2_GetTextureParameterValue(FName(p))
            o[p] = W.valid(t) and t:GetPathName() or false
        end
    end)
end

local function set(mid, kind, p, value)
    inSet = true
    local ok, err = pcall(function()
        if kind == "scalars" then mid:SetScalarParameterValue(FName(p), value)
        elseif kind == "vectors" then mid:SetVectorParameterValue(FName(p), value)
        else mid:SetTextureParameterValue(FName(p), value) end
    end)
    inSet = false
    if not ok then log.debug("set %s %s failed: %s", kind, p, tostring(err)) end
end

local function textureFor(file, worldContext)
    local art = ctx.features.art
    return art and art.loadTexture(file, worldContext)
end

-- Make `mid` match the theme entry for `key` (or the originals, for parameters no longer themed).
local function applyParams(mid, key, entry)
    local now = {}
    if entry then
        for p, v in pairs(entry.scalars) do captureOriginal(mid, key, "scalars", p); set(mid, "scalars", p, v); now["s:" .. p] = true end
        for p, v in pairs(entry.vectors) do captureOriginal(mid, key, "vectors", p); set(mid, "vectors", p, v); now["v:" .. p] = true end
        for p, file in pairs(entry.textures) do
            local tex = textureFor(file, mid)
            if tex then
                captureOriginal(mid, key, "textures", p); set(mid, "textures", p, tex); now["t:" .. p] = true
            else
                log.warn("materials.lua: %s.textures.%s: %s.png not found in the theme folder", key, p, file)
            end
        end
    end
    -- restore parameters that a previous theme set but this one doesn't
    local o = originals[key]
    for tag in pairs(applied[key] or {}) do
        if not now[tag] and o then
            local kind, p = tag:sub(1, 1), tag:sub(3)
            if kind == "s" and o.scalars[p] ~= nil then set(mid, "scalars", p, o.scalars[p])
            elseif kind == "v" and o.vectors[p] then set(mid, "vectors", p, o.vectors[p])
            elseif kind == "t" and o.textures[p] then
                local t = StaticFindObject(o.textures[p])
                if W.valid(t) then set(mid, "textures", p, t) end
            end
        end
    end
    -- remember every parameter ever themed for this effect, so copies themed before a reload still get
    -- restored when they're next seen (restoring an untouched copy to its original is harmless)
    local a = applied[key] or {}
    for tag in pairs(now) do a[tag] = true end
    applied[key] = next(a) and a or nil
end

-- Called by art.process for a material brush that has no PNG override.
-- kind = "image" | "border"; res = the brush's material; key/parent from names.resourceKey / rec.parent.
function M.apply(w, kind, res, cls, key, parent)
    local own = ownCopies[W.fullName(res)]
    if own then key, parent = own.key, own.parent end
    -- with the mod (or art) switched off, every effect gets its original values back
    local entry = (ctx.enabled and ctx.settings.art.enabled) and theme.lookup(entries, key, parent) or nil
    if cls == "MaterialInstanceDynamic" then
        if entry or applied[key] then applyParams(res, key, entry) end
        return
    end
    if not entry then return end
    -- shared asset: give this brush its own dynamic copy, then theme the copy
    local kml = StaticFindObject("/Script/Engine.Default__KismetMaterialLibrary")
    local ok, mid = pcall(function() return kml:CreateDynamicMaterialInstance(w, res, FName("None"), 0) end)
    if not (ok and W.valid(mid)) then
        ok, mid = pcall(function() return kml:CreateDynamicMaterialInstance(w, res) end)
    end
    if not (ok and W.valid(mid)) then log.warn("could not make a dynamic copy of %s", key) return end
    ownCopies[W.fullName(mid)] = { key = key, parent = W.name(res) }
    applyParams(mid, key, entry)
    ctx.features.art.guarded(function() w:SetBrushFromMaterial(mid) end)
end

function M.isOwnCopy(full) return ownCopies[full] ~= nil end

-- force: re-assert themed values after the game writes them ------------------------------------

local function installForceHooks()
    if hooksInstalled then return end
    hooksInstalled = true
    local hooks = {
        { "/Script/Engine.MaterialInstanceDynamic:SetScalarParameterValue", "scalars" },
        { "/Script/Engine.MaterialInstanceDynamic:SetVectorParameterValue", "vectors" },
        { "/Script/Engine.MaterialInstanceDynamic:SetTextureParameterValue", "textures" },
    }
    for _, h in ipairs(hooks) do
        local kind = h[2]
        local ok, err = pcall(RegisterHook, h[1], function() end, function(self, pname)
            if inSet then return end
            local okA, mid, p = pcall(function() return self:get(), pname:get():ToString() end)
            if not (okA and W.valid(mid)) then return end
            local full = W.fullName(mid)
            local own = ownCopies[full]
            local key, parent
            if own then key, parent = own.key, own.parent
            else
                key = names.resourceKey(W.name(mid), "MaterialInstanceDynamic")
                local okP, par = pcall(function() return mid.Parent end)
                parent = okP and W.valid(par) and W.name(par) or nil
            end
            if not ctx.enabled then return end
            local entry = theme.lookup(entries, key, parent)
            if not (entry and entry.force) then return end
            local v = entry[kind][p]
            if v == nil then return end
            if kind == "textures" then v = textureFor(v, mid) if not v then return end end
            set(mid, kind, p, v)
        end)
        if not ok then log.warn("could not hook %s: %s", h[1], tostring(err)) end
    end
    log.info("material force hooks installed")
end

function M.reload()
    local n = M.loadTheme()
    if theme.anyForce(entries) then installForceHooks() end
    return n
end

function M.init(c)
    ctx, W, log = c, c.widgets, c.log
    local n = M.reload()
    if n > 0 then log.info("material theme: %d effects from %s", n, themePath()) end
    -- own copies die with their widgets on a level change; their names may be reused by new objects
    c.events.on("worldchanged", function() ownCopies = {} end)
end

return M
