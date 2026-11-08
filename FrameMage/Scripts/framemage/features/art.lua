-- Art: replace any Image/Border brush texture with a PNG from the theme, Art/themes/<theme>/<TextureName>.png
-- (falling back to the Demi-human theme's; see core/themes.lua).
-- Material brushes (animated effects) without a PNG are handed to the materials feature, which themes their
-- parameters instead (the theme's materials.lua).
--
-- The game's texture name is the key, so one file reskins that texture everywhere it is used.
-- PNGs load at runtime (KismetRenderingLibrary.ImportFileAsTexture2D): no cooking, edit and press
-- the reload key. Run the inspector dump to get the list of texture names on screen.
--
-- Safety rule: this feature never keeps widget handles between ticks. A stored handle to a widget the
-- engine has since freed can pass IsValid when the memory is reused, and reading it crashes the game.
-- Brushes are processed when their user widget appears (fresh handle) and when the game calls a brush
-- setter (hook, fresh `self`); a reload re-announces live widgets with fresh handles.
local M = {}

local ctx, W, log
local KRL
local texCache = {} -- textureName -> UTexture2D (our own imports, kept alive by the brushes using them)
local missing = {} -- textureName -> true (no PNG for it)
local ours = {} -- fullName of an imported texture -> original texture's path name (for restore)
local inHook = false
local names = require("framemage.core.names")
M.seen = {} -- resource key -> { kind = "Texture2D", count = n, parent = "MI_..." } (used by the inspector)

-- Art applies only while the mod is on (master switch) and art itself is enabled in settings.
local function artOn() return ctx.enabled and ctx.settings.art.enabled end

local ImageClass, BorderClass
local function classes()
    if not W.valid(ImageClass) then ImageClass = StaticFindObject("/Script/UMG.Image") end
    if not W.valid(BorderClass) then BorderClass = StaticFindObject("/Script/UMG.Border") end
end

local function isA(w, cls)
    if not W.valid(cls) then return false end
    local ok, r = pcall(function() return w:IsA(cls) end)
    return ok and r == true
end


local function resourceOf(w, kind)
    local ok, res = pcall(function()
        local b = (kind == "image") and w.Brush or w.Background
        return b and b.ResourceObject
    end)
    if ok and W.valid(res) then return res end
    return nil
end

function M.loadTexture(name, worldContext)
    local tex = texCache[name]
    if tex and W.valid(tex) then return tex end
    if missing[name] then return nil end
    local path = ctx.themes.find(name .. ".png")
    if not path then missing[name] = true return nil end
    if not W.valid(KRL) then KRL = StaticFindObject("/Script/Engine.Default__KismetRenderingLibrary") end
    local ok, t = pcall(function() return KRL:ImportFileAsTexture2D(worldContext, path) end)
    if not (ok and W.valid(t)) then
        log.warn("could not load %s (%s)", path, tostring(t))
        missing[name] = true
        return nil
    end
    texCache[name] = t
    log.debug("loaded %s", path)
    return t
end

-- Load any PNG by full path (Frame Mage's own UI icons). Cached by path; nil if missing or unreadable.
local fileCache = {}
function M.loadFile(path, worldContext)
    local tex = fileCache[path]
    if tex and W.valid(tex) then return tex end
    if not ctx.fs.exists(path) then return nil end
    if not W.valid(KRL) then KRL = StaticFindObject("/Script/Engine.Default__KismetRenderingLibrary") end
    local ok, t = pcall(function() return KRL:ImportFileAsTexture2D(worldContext, path) end)
    if not (ok and W.valid(t)) then log.warn("could not load %s", path) return nil end
    fileCache[path] = t
    ours[W.fullName(t)] = { name = path } -- never treated as game art
    return t
end

-- Run a brush change of our own without the setter hooks reacting to it.
function M.guarded(fn)
    inHook = true
    local ok, err = pcall(fn)
    inHook = false
    if not ok then log.debug("guarded brush change failed: %s", tostring(err)) end
    return ok
end

local function setTexture(w, tex)
    inHook = true -- our own setter call must not re-enter the hook
    local ok, err = pcall(function() w:SetBrushFromTexture(tex, false) end) -- false = keep designed size
    inHook = false
    if not ok then log.debug("SetBrushFromTexture failed: %s", tostring(err)) end
    return ok
end

-- Process one brush widget (fresh handle only). kind = "image" | "border"
local function process(w, kind)
    local res = resourceOf(w, kind)
    if not res then return end
    local resFull = W.fullName(res)
    if ours[resFull] then return end -- already ours
    local okC, cls = pcall(W.className, res)
    cls = okC and cls or "?"
    local mats = ctx.features.materials
    if mats and mats.isOwnCopy(resFull) then
        mats.apply(w, kind, res, cls, nil, nil) -- applies or restores, depending on the switch
        return
    end
    -- runtime textures are other mods' PNG imports or render targets, not game art: leave them alone
    -- (material instances are runtime copies by design and are keyed by their base name instead)
    if not names.isMaterial(cls) and names.isRuntime(resFull) then return end
    local name = names.resourceKey(W.name(res), cls)
    local rec = M.seen[name]
    if not rec then
        rec = { kind = cls, count = 0 }
        if cls == "MaterialInstanceDynamic" then
            local okP, parent = pcall(function() return res.Parent end)
            if okP and W.valid(parent) then rec.parent = W.name(parent) end
        end
        if names.isMaterial(cls) and mats then
            local okD, params = pcall(mats.describe, res) -- parameter names for dumps/materials.txt
            if okD then rec.params = params end
        end
        -- what a replacement needs (dumps/textures.txt): the texture's pixel size, the size and way the
        -- game draws it (plain image, 9-slice box/border) and where it was first seen
        pcall(function()
            if cls == "Texture2D" then rec.size = M.sizeText(res:Blueprint_GetSizeX(), res:Blueprint_GetSizeY()) end
        end)
        pcall(function()
            local b = (kind == "image") and w.Brush or w.Background
            rec.drawn = M.sizeText(b.ImageSize.X, b.ImageSize.Y)
            rec.drawAs = M.DRAW_AS[b.DrawAs]
        end)
        pcall(function() rec.where = W.key(w) end)
        M.seen[name] = rec
    end
    -- where the texture lives (a texture first seen in an earlier session, restored from the dump, is still
    -- learned here)
    if cls == "Texture2D" and not M.knowsPath(name) then pcall(function() M.rememberPath(name, res:GetPathName()) end) end
    rec.count = rec.count + 1
    local tex = artOn() and M.loadTexture(name, w)
    if not tex and names.isMaterial(cls) then
        local mats = ctx.features.materials
        if mats then mats.apply(w, kind, res, cls, name, rec.parent) end
        return
    end
    if tex and setTexture(w, tex) then
        local okP, path = pcall(function() return res:GetPathName() end)
        ours[W.fullName(tex)] = { name = name, path = okP and path or nil }
    end
end

M.DRAW_AS = { [0] = "none", [1] = "box", [2] = "border", [3] = "image", [4] = "rounded" }

-- Pure: "256x64" from two sizes (rounded), or nil. Unit-tested.
function M.sizeText(w, h)
    if type(w) ~= "number" or type(h) ~= "number" or w <= 0 or h <= 0 then return nil end
    return string.format("%dx%d", math.floor(w + 0.5), math.floor(h + 0.5))
end

local function processAny(w)
    classes()
    if isA(w, ImageClass) then process(w, "image")
    elseif isA(w, BorderClass) then process(w, "border") end
end

-- New user widget: walk its own tree (nested user widgets get their own event).
local function onUserWidget(uw)
    if not artOn() then return end
    W.walk(uw, function(child, depth)
        if depth > 0 and W.isUserWidget(child) then return false end
        processAny(child)
        return true
    end)
end

-- Restore helper for reload: put the original texture back on a widget showing a stale import.
local function refresh(w, kind)
    local res = resourceOf(w, kind)
    if not res then return end
    local info = ours[W.fullName(res)]
    if not info then process(w, kind) return end
    local tex = artOn() and M.loadTexture(info.name, w)
    if tex then
        if W.fullName(tex) ~= W.fullName(res) then
            setTexture(w, tex)
            ours[W.fullName(tex)] = info
        end
    elseif info.path then
        local orig = StaticFindObject(info.path)
        if W.valid(orig) then setTexture(w, orig) end
    end
end

function M.reload()
    texCache, missing = {}, {}
    local mats = ctx.features.materials
    local themed = mats and mats.reload() or 0
    classes()
    local n = 0
    for _, spec in ipairs({ { "Image", "image" }, { "Border", "border" } }) do
        for _, w in pairs(FindAllOf(spec[1]) or {}) do
            if W.valid(w) and W.isInstance(w) then refresh(w, spec[2]); n = n + 1 end
        end
    end
    log.info("art reloaded: theme '%s' (%d brushes checked, %d material themes)", ctx.themes.current(), n, themed)
    local editor = ctx.features.editor
    if editor then
        editor.flash(string.format("Art reloaded: %s theme", ctx.themes.LABELS[ctx.themes.current()] or ctx.themes.current()))
    end
end

local function hookSetters()
    local setters = {
        { "/Script/UMG.Image:SetBrush", "image" },
        { "/Script/UMG.Image:SetBrushFromTexture", "image" },
        { "/Script/UMG.Image:SetBrushResourceObject", "image" },
        { "/Script/UMG.Border:SetBrush", "border" },
        { "/Script/UMG.Border:SetBrushFromTexture", "border" },
        { "/Script/UMG.Image:SetBrushFromMaterial", "image" },
        { "/Script/UMG.Border:SetBrushFromMaterial", "border" },
    }
    for _, s in ipairs(setters) do
        local kind = s[2]
        local ok, err = pcall(RegisterHook, s[1], function() end, function(self)
            if inHook or not artOn() then return end
            local okS, w = pcall(function() return self:get() end)
            if okS and W.valid(w) and W.isInstance(w) then
                local okP, perr = pcall(process, w, kind)
                if not okP then log.debug("art hook: %s", tostring(perr)) end
            end
        end)
        if not ok then log.warn("could not hook %s: %s", s[1], tostring(err)) end
    end
end

-- Master switch: reload re-points every swapped brush (PNG when on, the game's original when off) and lets
-- materials re-apply or restore their parameters.
function M.setEnabled() M.reload() end

-- Where game textures live (name -> object path), learned as they're seen and kept in config/texture-paths.lua, so
-- a feature can load a texture by name even before the game has shown it (e.g. the Agility icon on the stamina ring).
local knownPaths, pathsDirty = {}, false
local function pathsFile() return ctx.dir .. "config/texture-paths.lua" end

function M.knowsPath(name) return knownPaths[name] ~= nil end

function M.rememberPath(name, path)
    if type(path) ~= "string" or path == "" or knownPaths[name] == path then return end
    knownPaths[name] = path
    pathsDirty = true
    if name:find("Agility", 1, true) then log.info("art: found %s at %s", name, path) end
end

-- A game texture by name: loaded if the game has it, else loaded from its remembered path; nil if unknown.
function M.gameTexture(name)
    local path = knownPaths[name]
    if not path then
        for _, t in pairs(FindAllOf("Texture2D") or {}) do
            local ok, n = pcall(function() return t:GetFName():ToString() end)
            if ok and n == name and W.valid(t) then
                pcall(function() M.rememberPath(name, t:GetPathName()) end)
                return t
            end
        end
        return nil
    end
    local t = StaticFindObject(path)
    if W.valid(t) then return t end
    if LoadAsset then
        local ok, loaded = pcall(LoadAsset, path)
        if ok and W.valid(loaded) then return loaded end
    end
    return nil
end

local function loadPaths()
    local text = ctx.fs.read(pathsFile())
    if not text then return end
    local t = ctx.serialize.parse(text, pathsFile())
    if type(t) == "table" then
        for k, v in pairs(t) do if type(v) == "string" then knownPaths[k] = v end end
    end
end

local function savePaths()
    if not pathsDirty then return end
    pathsDirty = false
    ctx.config.save(pathsFile(), knownPaths,
        "-- Where game textures live (learned automatically as Frame Mage sees them). Safe to delete.\n")
end

function M.init(c)
    ctx, W, log = c, c.widgets, c.log
    c.events.on("userwidget", onUserWidget)
    c.events.on("worldchanged", function() texCache, fileCache = {}, {} end) -- imports may be collected with their widgets
    pcall(loadPaths)
    c.sched.every(10000, "art.paths", function()
        local ok, err = pcall(savePaths)
        if not ok then log.warn("art: could not save texture paths: %s", tostring(err)) end
    end)
    c.events.on("themechanged", function() fileCache = {}; M.reload() end)
    if c.settings.art.hookSetters then hookSetters() end
    c.keys.bind(c.settings.keys.reloadArt, "reloadArt", M.reload)
end

return M
