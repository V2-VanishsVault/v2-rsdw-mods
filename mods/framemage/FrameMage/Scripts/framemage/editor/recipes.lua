-- Recipes: what a real entry of a game list looks like, learned while you play, for the editor's examples.
--
-- A list's entries show nothing until the game gives them data (a spell timer is only its name without its spell).
-- So whenever the game shows a real entry of a class the editor knows (a list's EntryWidgetClass, a notification
-- queue's NotificationWidgetClass), what each of its named parts shows is noted: its text, its picture (a texture,
-- or a material: a dynamic one is noted as the material it was made from), its visibility. Saved in
-- config/examples.lua, so it's known in later sessions too. editor/examples.lua applies a recipe to the entries it
-- makes, so they look like the real thing.
local W = require("framemage.core.widgets")

local M = {}

local ctx, log
local path -- config/examples.lua
M.isOurs = function() return false end -- set by editor/examples.lua: its own example entries aren't learned from
local recipes = {} -- entry class name -> { parts = { [part name] = { text, res, size, vis } }, seen = os.time() }
-- entry class names to look for: the HUD's lists the editor shows examples for, and any it meets
local watched = { WBP_SpellTimerEntry_C = true, WBP_ExperienceProgress_Item_C = true,
    WBP_FloatingExperience_Item_C = true }
local dirty = false

M.WATCH_MS = 3000 -- how often live entries are looked for (only of the classes known)
M.MAX_PARTS = 40

-- Pure: a recipe part from what a widget reports. Unit-tested.
function M.part(text, resPath, sizeX, sizeY, vis)
    local p = {}
    if type(text) == "string" and text ~= "" then p.text = text end
    if type(resPath) == "string" and resPath ~= "" then p.res = resPath end
    if type(sizeX) == "number" and type(sizeY) == "number" and sizeX > 0 and sizeY > 0 then p.size = { sizeX, sizeY } end
    if type(vis) == "number" then p.vis = vis end
    return p
end

-- Pure: does a recipe say anything? (a part with text or a picture)
function M.useful(recipe)
    for _, p in pairs(recipe and recipe.parts or {}) do if p.text or p.res then return true end end
    return false
end

-- A widget's picture as a loadable path: a texture or material asset; a dynamic material instance (made at run
-- time, in the transient package) as the material it was made from.
local function resourcePath(x)
    local ok, o = pcall(function() return x.Brush.ResourceObject end)
    if not (ok and W.valid(o)) then return nil end
    local okP, p = pcall(function() return o:GetPathName() end)
    if okP and type(p) == "string" and not p:find("/Engine/Transient", 1, true) then return p end
    local okA, parent = pcall(function() return o.Parent end)
    if okA and W.valid(parent) then
        local okQ, q = pcall(function() return parent:GetPathName() end)
        if okQ then return q end
    end
    return nil
end

local function imageSize(x)
    local ok, s = pcall(function() return x.Brush.ImageSize end)
    if ok and s then return s.X, s.Y end
    return nil
end

-- Note what a live entry shows.
function M.learn(entry)
    local okC, cls = pcall(W.className, entry)
    if not okC then return false end
    local parts, n = {}, 0
    W.walk(entry, function(x, depth)
        if n >= M.MAX_PARTS then return false end
        local okN, name = pcall(W.name, x)
        if not okN then return true end
        local okT, text = pcall(function() return x:GetText():ToString() end)
        local sx, sy = imageSize(x)
        local okV, vis = pcall(function() return x:GetVisibility() end)
        local p = M.part(okT and text or nil, resourcePath(x), sx, sy, okV and vis or nil)
        if depth > 0 and (p.text or p.res) then parts[name] = p; n = n + 1 end
        return true
    end, 0, 20)
    if not next(parts) then return false end
    local old = recipes[cls]
    recipes[cls] = { parts = parts, seen = os.time() }
    if not (old and M.useful(old)) then
        log.info("editor examples: learned what a real %s shows (%d parts)", cls, n)
    end
    dirty = true
    return true
end

function M.recipe(cls) return recipes[cls] end

-- Look for live entries of these classes from now on (the editor met their lists).
function M.watch(cls)
    if type(cls) == "string" and cls ~= "" then watched[cls] = true end
end

local loaded = {}
local function loadRes(p)
    local o = loaded[p]
    if o and W.valid(o) then return o end
    o = StaticFindObject(p)
    if not W.valid(o) and LoadAsset then pcall(function() o = LoadAsset(p) end) end
    if W.valid(o) then loaded[p] = o return o end
    return nil
end

-- Make a new entry look like the recipe: its parts' text and pictures, and the visibility they had.
function M.apply(entry, recipe)
    if not recipe then return 0 end
    local done = 0
    W.walk(entry, function(x, depth)
        if depth == 0 then return true end
        local okN, name = pcall(W.name, x)
        local p = okN and recipe.parts[name]
        if p then
            if p.text then pcall(function() x:SetText(FText(p.text)) end) end
            if p.res then
                local o = loadRes(p.res)
                if o then
                    pcall(function()
                        local b = x.Brush
                        x:SetBrush({ ResourceObject = o, ImageSize = { X = p.size and p.size[1] or b.ImageSize.X,
                            Y = p.size and p.size[2] or b.ImageSize.Y }, DrawAs = b.DrawAs, Tiling = b.Tiling,
                            Margin = b.Margin, TintColor = b.TintColor })
                    end)
                end
            end
            if p.vis and p.vis ~= 1 and p.vis ~= 2 then pcall(function() x:SetVisibility(p.vis) end) end
            done = done + 1
        end
        return true
    end, 0, 20)
    return done
end

local function scan()
    if not next(watched) then return end
    for cls in pairs(watched) do
        for _, e in pairs(FindAllOf(cls) or {}) do
            -- a real one the game is showing (ours live on our own overlay: their outer is never the game's)
            if W.valid(e) and W.isInstance(e) and W.isVisible(e) and not M.isOurs(e) then
                local okL, learned = pcall(M.learn, e)
                if okL and learned then break end
            end
        end
    end
    if dirty then
        dirty = false
        pcall(ctx.config.save, path, recipes,
            "-- What real entries of the game's lists show, learned while you play (Frame Mage's editor uses it for\n"
            .. "-- the examples it shows in empty lists). Rewritten as the game shows them; safe to delete.\n")
    end
end

function M.init(c)
    ctx, log = c, c.log
    path = c.dir .. "config/examples.lua"
    local ok, data = pcall(c.config.load, path, {})
    recipes = (ok and type(data) == "table") and data or {}
    for cls in pairs(recipes) do watched[cls] = true end
    c.sched.every(M.WATCH_MS, "editor.recipes", function()
        local okS, err = pcall(scan)
        if not okS then log.debug("editor examples: %s", tostring(err)) end
    end)
end

-- (tests)
function M._set(t) recipes = t or {} end

return M
