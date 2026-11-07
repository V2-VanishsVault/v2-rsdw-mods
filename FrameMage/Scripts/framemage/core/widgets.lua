-- UMG helpers: identity keys, tree walking, viewport roots, and new-widget tracking.
--
-- Element keys are stable across sessions and look like:
--   WBP_HUD                         a root widget (by class)
--   WBP_HUD/SurvivalPanel           a widget named SurvivalPanel inside WBP_HUD's tree
--   WBP_HUD/SurvivalPanel/Bar       nested user widgets chain their owners
--   WBP_HUD/WBP_BuffEntry*          runtime-created instances of a class (all share one key)
local log = require("framemage.core.log")
local sched = require("framemage.core.sched")
local events = require("framemage.core.events")

local M = {}

function M.valid(o)
    if o == nil then return false end
    local ok, v = pcall(function() return o:IsValid() end)
    return ok and v == true
end

function M.name(o)
    return o:GetFName():ToString()
end

function M.className(o)
    return o:GetClass():GetFName():ToString()
end

function M.fullName(o)
    return o:GetFullName()
end

-- Pure helpers (unit-tested) ------------------------------------------------

function M.stripClassSuffix(c)
    return (c:gsub("_C$", ""))
end

-- A runtime-made instance is named <Class>_<number>; collapse those so every instance shares a key.
-- Only blueprint classes (…_C) are created at runtime; native widgets named <Class>_<n> (Image_12) are
-- designer-placed with default names and must keep their own key.
function M.normaliseName(name, className)
    if className:match("_C$") and name:sub(1, #className) == className and name:sub(#className + 1):match("^_%d+$") then
        return M.stripClassSuffix(className) .. "*"
    end
    return name
end

-- Live game objects are in the transient package; templates/archetypes inside blueprint classes are not.
function M.isInstanceFullName(full)
    return full:find("/Engine/Transient", 1, true) ~= nil and full:find("Default__", 1, true) == nil
end

-- Object helpers -------------------------------------------------------------

local UserWidgetClass
local function userWidgetClass()
    if not M.valid(UserWidgetClass) then UserWidgetClass = StaticFindObject("/Script/UMG.UserWidget") end
    return UserWidgetClass
end

function M.isUserWidget(w)
    local cls = userWidgetClass()
    if not M.valid(cls) then return false end
    local ok, r = pcall(function() return w:IsA(cls) end)
    return ok and r == true
end

function M.isInstance(o)
    local ok, full = pcall(M.fullName, o)
    return ok and M.isInstanceFullName(full)
end

-- The UserWidget whose WidgetTree contains `w`, or nil for a root/runtime-created widget.
function M.owner(w)
    local ok, uw = pcall(function()
        local outer = w:GetOuter()
        if M.valid(outer) and M.className(outer) == "WidgetTree" then
            local o2 = outer:GetOuter()
            if M.valid(o2) then return o2 end
        end
        return nil
    end)
    return ok and uw or nil
end

function M.key(w)
    local parts = {}
    local cur, guard = w, 0
    while cur and guard < 16 do
        local cls = M.className(cur)
        local owner = M.owner(cur)
        if owner then
            table.insert(parts, 1, M.normaliseName(M.name(cur), cls))
        else
            table.insert(parts, 1, M.stripClassSuffix(cls))
        end
        cur, guard = owner, guard + 1
    end
    return table.concat(parts, "/")
end

function M.children(w)
    local out = {}
    if M.isUserWidget(w) then
        local ok, root = pcall(function() return w.WidgetTree.RootWidget end)
        if ok and M.valid(root) then out[1] = root end
        return out
    end
    local ok, count = pcall(function() return w:GetChildrenCount() end)
    if not ok or type(count) ~= "number" then return out end
    for i = 0, count - 1 do
        local okC, c = pcall(function() return w:GetChildAt(i) end)
        if okC and M.valid(c) then out[#out + 1] = c end
    end
    return out
end

function M.parent(w)
    local ok, p = pcall(function() return w:GetParent() end)
    if ok and M.valid(p) then return p end
    -- the tree root's parent is the owning user widget
    return M.owner(w)
end

-- Depth-first walk; fn(widget, depth) returning false skips that widget's children.
function M.walk(w, fn, depth, maxDepth)
    depth = depth or 0
    if depth > (maxDepth or 40) then return end
    if fn(w, depth) == false then return end
    for _, c in ipairs(M.children(w)) do M.walk(c, fn, depth + 1, maxDepth) end
end

function M.isVisible(w)
    local ok, v = pcall(function() return w:IsVisible() end)
    return ok and v == true
end

-- Top-level widgets currently on screen. Costs a full scan (tens of ms): call on demand only.
function M.viewportRoots()
    local roots = {}
    for _, w in pairs(FindAllOf("UserWidget") or {}) do
        if M.valid(w) and M.isInstance(w) then
            local ok, inVp = pcall(function() return w:IsInViewport() end)
            if ok and inVp then roots[#roots + 1] = w end
        end
    end
    return roots
end

-- Tracking -------------------------------------------------------------------
-- New user widgets are reported at construction, before their tree is filled in, so they are queued
-- and announced on the next game-thread tick. Image/Border creation is deliberately NOT subscribed:
-- there are tens of thousands, and features walk the trees of announced user widgets instead.
-- Handles are only used within the tick they are announced in; "worldchanged" tells features to drop
-- anything they kept, since a level change frees most widgets at once.

local pending = {}

function M.startTracking(ctx)
    local ok = pcall(NotifyOnNewObject, "/Script/UMG.UserWidget", function(obj) pending[#pending + 1] = obj end)
    if not ok then log.error("could not subscribe to new UserWidgets; changes apply only on rescan") end
    local okH = pcall(RegisterHook, "/Script/Engine.PlayerController:ClientRestart", function()
        sched.now("widgets.worldchanged", function() events.emit("worldchanged") end)
    end)
    if not okH then log.warn("could not hook ClientRestart; world changes are not detected") end
    sched.every(50, "widgets.drain", function()
        if #pending == 0 then return end
        local batch = pending
        pending = {}
        for _, w in ipairs(batch) do
            if M.valid(w) and M.isInstance(w) then events.emit("userwidget", w) end
        end
    end)
    -- Widgets that existed before the mod loaded: announce once.
    sched.later(500, "widgets.initialScan", function() M.rescan() end)
end

-- Re-announce every live user widget with fresh handles. Expensive (tens of ms): start, profile switch.
function M.rescan()
    local n = 0
    for _, w in pairs(FindAllOf("UserWidget") or {}) do
        if M.valid(w) and M.isInstance(w) then events.emit("userwidget", w); n = n + 1 end
    end
    log.debug("rescan announced %d user widgets", n)
end

return M
