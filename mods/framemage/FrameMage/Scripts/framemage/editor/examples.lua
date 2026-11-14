-- Examples: real entries in an empty list, while it's being edited.
--
-- Many of the game's HUD elements are lists the game fills as things happen (spell timers, status effects, unlocks).
-- With nothing in them they have no size and nothing to see, so the editor drew a plain stand-in box. A list knows
-- its own entry class, though (ListView / DynamicEntryBox: EntryWidgetClass), even when it's empty: so for each
-- empty list inside the selected element, a couple of real entries of that class are made (CreateWidget) and shown
-- where the list sits, with example text where theirs is empty. They are Frame Mage's own widgets on an overlay of
-- ours: the game's list and its data are never touched. clear() removes them.
local W = require("framemage.core.widgets")
local overlay = require("framemage.core.overlay")
local geometry = require("framemage.core.geometry")
local names = require("framemage.core.names")
local recipes = require("framemage.editor.recipes") -- what real entries show, learned while you play

local M = {}

M.COUNT = 2 -- example entries per empty list
M.MAX_LISTS = 3
-- Example text by entry class (text widget name -> text), where the entry's own is empty; the rest of an empty
-- text gets its widget's name, made readable.
M.TEXT = {}

local log
local host -- the overlay: { uw, canvas, tree, suffix }
local shown = {} -- { w, r } per example entry (r: where it's drawn, viewport units)
local ours = {} -- full names of the entries we made
recipes.isOurs = function(e)
    local ok, full = pcall(function() return e:GetFullName() end)
    return ok and ours[full] == true
end

-- Pure: where n entries of size (ew x eh) go from (x, y), down a column (vertical) or along a row, `gap` apart.
-- { { left, top, right, bottom }, ... }. Unit-tested.
function M.place(x, y, ew, eh, n, vertical, gap)
    local out = {}
    for i = 1, n do
        local dx = vertical and 0 or (i - 1) * (ew + gap)
        local dy = vertical and (i - 1) * (eh + gap) or 0
        out[i] = { left = x + dx, top = y + dy, right = x + dx + ew, bottom = y + dy + eh }
    end
    return out
end

-- Pure: the box round several rects, or nil.
function M.union(rects)
    local box
    for _, q in ipairs(rects) do
        box = box and { left = math.min(box.left, q.left), top = math.min(box.top, q.top),
            right = math.max(box.right, q.right), bottom = math.max(box.bottom, q.bottom) }
            or { left = q.left, top = q.top, right = q.right, bottom = q.bottom }
    end
    return box
end

local LIST_CLASSES = { ListView = true, TileView = true, TreeView = true, DynamicEntryBox = true }

local function isEmptyList(x)
    local cls = W.className(x)
    if not (cls and (LIST_CLASSES[cls] or cls:match("ListView") or cls:match("EntryBox"))) then return false end
    local ok, n = pcall(function() return x:GetNumItems() end)
    if ok and type(n) == "number" then return n == 0 end
    local okE, entries = pcall(function() return x:GetAllEntries() end)
    if okE and type(entries) == "table" then return #entries == 0 end
    return false
end

-- The game's notification queues (NotificationQueue: Experience Progress, Floating Experience...) name their entry
-- class too. One with no entry made yet (nothing shown this session) gets examples; one with pooled entries is the
-- preview's to show (preview.lua NOTICES: the game's own entry, revealed).
local function arrayLen(a)
    if a == nil then return nil end
    local ok, n = pcall(function() return a:GetArrayNum() end)
    if ok and type(n) == "number" then return n end
    local okL, m = pcall(function() return #a end)
    if okL and type(m) == "number" then return m end
    return nil
end

local function emptyQueue(x)
    local ok, cls = pcall(function() return x.NotificationWidgetClass end)
    if not (ok and W.valid(cls)) then return false end
    local okP, pool = pcall(function() return x.NotificationWidgetsPool end)
    local okD, disp = pcall(function() return x.NotificationWidgetsOnDisplay end)
    local np = okP and arrayLen(pool) or nil
    local nd = okD and arrayLen(disp) or nil
    return (np or 0) == 0 and (nd or 0) == 0
end

local function entryClass(x)
    local ok, cls = pcall(function() return x.EntryWidgetClass end)
    if ok and W.valid(cls) then return cls end
    local okN, ncls = pcall(function() return x.NotificationWidgetClass end)
    if okN and W.valid(ncls) then return ncls end
    return nil
end

local function vertical(x)
    local ok, o = pcall(function() return x.Orientation end)
    if ok and type(o) == "number" then return o == 1 end
    return true
end

local function ensureHost()
    if host and W.valid(host.uw) then return host end
    host = overlay.host("Examples", 18985) -- under the editor's frame and catcher
    pcall(function() host.uw:SetVisibility(3) end)
    return host
end

-- An entry made without the game's data often rests hidden or transparent (the game shows it when it fills it):
-- every hidden part shown, every near-invisible part made opaque. Returns a short report for the log.
local function reveal(entry)
    local shownN, opaqueN, parts = 0, 0, {}
    W.walk(entry, function(x)
        local okV, vis = pcall(function() return x:GetVisibility() end)
        if okV and (vis == 1 or vis == 2) then
            pcall(function() x:SetVisibility(3) end)
            shownN = shownN + 1
        end
        local okO, op = pcall(function() return x:GetRenderOpacity() end)
        if okO and type(op) == "number" and op < 0.05 then
            pcall(function() x:SetRenderOpacity(1) end)
            opaqueN = opaqueN + 1
        end
        if #parts < 12 then
            local okR, res = pcall(function() return x.Brush.ResourceObject:GetFName():ToString() end)
            parts[#parts + 1] = W.name(x) .. "[" .. tostring(W.className(x)) .. (okR and res and (" " .. res) or "") .. "]"
        end
        return true
    end, 0, 20)
    return ("%d shown, %d made opaque; %s"):format(shownN, opaqueN, table.concat(parts, ", "))
end

local function fillText(entry, cls)
    local given = M.TEXT[cls] or {}
    W.walk(entry, function(child)
        local ok, text = pcall(function() return child:GetText():ToString() end)
        if ok and text == "" then
            local n = W.name(child)
            pcall(function() child:SetText(FText(given[n] or names.pretty(n))) end)
            return false
        end
        return true
    end, 0, 20)
end

-- Show examples in every empty list inside `w`; `at` = where the element sits (viewport units), used when a list
-- has no size of its own yet. true if any were made.
function M.show(w, at)
    M.clear()
    local lists = {}
    -- (the element itself may be the list or queue: Experience Progress is a notification queue)
    if (isEmptyList(w) or emptyQueue(w)) and entryClass(w) then lists[1] = w end
    W.walk(w, function(x)
        if #lists >= M.MAX_LISTS then return false end
        if (isEmptyList(x) or emptyQueue(x)) and entryClass(x) then lists[#lists + 1] = x return false end
        return true
    end, 0, 25)
    if #lists == 0 then return false end
    local h = ensureHost()
    local wbl = StaticFindObject("/Script/UMG.Default__WidgetBlueprintLibrary")
    local pc = FindFirstOf("PlayerController")
    for _, list in ipairs(lists) do
        local cls = entryClass(list)
        local lr = geometry.rect(list)
        local x0 = (lr and lr.right > lr.left) and lr.left or (at and at.left) or 100
        local y0 = (lr and lr.bottom > lr.top) and lr.top or (at and at.top) or 100
        local made = {}
        for i = 1, M.COUNT do
            local ok, e = pcall(function() return wbl:Create(h.uw, cls, pc) end)
            if ok and W.valid(e) then
                made[#made + 1] = e
                pcall(function() ours[e:GetFullName()] = true end)
            end
        end
        local slots, ew, eh, report = {}, nil, nil, ""
        if #made > 0 then
            report = ""
            local okC0, cls0 = pcall(W.className, made[1])
            local recipe = okC0 and recipes.recipe(cls0) or nil
            if okC0 then recipes.watch(cls0) end
            for _, e in ipairs(made) do
                local okR, rep2 = pcall(reveal, e)
                if okR and report == "" then report = rep2 end
                -- what a real one showed (learned while playing), then example text where it's still empty
                local okA, n = pcall(recipes.apply, e, recipe)
                if okA and n > 0 and report ~= "" then report = report .. ("; %d parts from a real one"):format(n) end
                pcall(fillText, e, okC0 and cls0 or "") -- (before measuring: example text gives an entry its size)
            end
            -- on screen first (a widget not yet in the viewport has no size to measure), then measured
            for i, e in ipairs(made) do
                pcall(function() e:SetVisibility(3) end)
                local okS, slot = pcall(function() return h.canvas:AddChildToCanvas(e) end)
                if okS and slot then
                    pcall(function()
                        slot:SetAnchors({ Minimum = { X = 0, Y = 0 }, Maximum = { X = 0, Y = 0 } })
                        slot:SetAutoSize(true)
                        slot:SetPosition({ X = x0, Y = y0 })
                    end)
                    slots[i] = slot
                end
            end
            pcall(function()
                made[1]:ForceLayoutPrepass()
                local d = made[1]:GetDesiredSize()
                if d.X > 1 and d.Y > 1 then ew, eh = d.X, d.Y end
            end)
            if not ew then
                -- nothing to draw without the game's data (a spell timer is only its name until the game fills it):
                -- no examples; the stand-in at the element's real size is better than an empty one
                if log then log.info("editor: example %s in %s has no size of its own: stand-in instead (%s)",
                    tostring(W.className(made[1])), W.name(list), report) end
                for _, e in ipairs(made) do pcall(function() e:RemoveFromParent() end) end
                made = {}
            end
        end
        if #made > 0 then
            local spots = M.place(x0, y0, ew, eh, #made, vertical(list), 4)
            local okC, clsName = pcall(W.className, made[1])
            for i, e in ipairs(made) do
                local slot = slots[i]
                if slot then pcall(function() slot:SetPosition({ X = spots[i].left, Y = spots[i].top }) end) end
                shown[#shown + 1] = { w = e, r = spots[i] }
            end
            if log then
                log.info("editor: %d example %s in %s, %.0f x %.0f: %s", #made, okC and clsName or "entries", W.name(list),
                    ew, eh, report)
            end
        end
    end
    return #shown > 0
end

-- The box round the examples shown (viewport units), or nil.
function M.rect()
    local rects = {}
    for _, s in ipairs(shown) do if W.valid(s.w) then rects[#rects + 1] = s.r end end
    return M.union(rects)
end

function M.clear()
    for _, s in ipairs(shown) do
        if W.valid(s.w) then pcall(function() s.w:RemoveFromParent() end) end
    end
    shown = {}
end

-- The world changed: our widgets went with it.
function M.forget() shown = {}; host = nil end

function M.init(c)
    log = c.log
    recipes.init(c)
end

return M
