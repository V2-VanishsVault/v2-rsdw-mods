-- Preview: make the selected element visible while it's being edited, even when the game currently has
-- nothing to show in it (a boss bar with no boss, an empty notification, a faded-out prompt).
--
--   * the element and every ancestor that is Collapsed/Hidden is shown (hit-test invisible, so it can't
--     swallow clicks)
--   * near-zero render opacity on that chain is raised to full (hidden-by-layout elements show as a ghost)
--   * empty text blocks inside it get a placeholder label, so its text areas have size and can be seen
--   What the element shows otherwise is the designer's default content: images and text set in the widget
--   blueprint remain until the game replaces them at runtime.
--   * a notice: the game keeps one entry widget per notice queue for the whole world, collapsed between notices but
--     still holding its last notice (or the designer's example). Inside the element, the first collapsed entry of
--     each kind is shown, at its own size, with an example text where its text is empty (M.NOTICES). An entry the
--     game is using (not collapsed) is never touched, and one the game takes while it's shown is let go: nothing
--     of ours is written to it again or put back.
-- Every change is recorded and undone by finish(); tick() re-applies them if the game hides things again.
local W = require("framemage.core.widgets")
local names = require("framemage.core.names")
local examples = require("framemage.editor.examples") -- real entries in empty lists (spell timers, effects...)

local M = {}

local COLLAPSED, SHOWN = 1, 3 -- ESlateVisibility (3: shown, not hit-testable)
local PAGE_SECONDS = 2 -- a notice with several kinds of page shows each in turn

-- The game's notice entries (class -> how to show one):
--   pages: children of its WidgetSwitcher root, shown in turn (the ones it has); examples: text widget name ->
--   example text, written only where the text is empty; quiet: parts collapsed while it shows (a tip's key line);
--   opaque: its own color rests fully transparent; centered: it rests slid aside (render translation).
-- (The level-up page is left out: Frame Mage's celebration replaces it.)
M.NOTICES = {
    WBP_PlayerUpkeepNotification_Item_C = {},
    WBP_ExperienceProgress_Item_C = {},
    WBP_FloatingExperience_Item_C = {},
    WBP_QuestAndUnlocks_Item_C = {},
    WBP_EnvAndPlayerStatus_Item_C = { opaque = true },
    WBP_TutorialNotifications_Item_C = { quiet = { "InputEntryWidget" },
        examples = { TitleTextBlock = "Tutorial tip", BodyTextBlock = "The game's tips show here." } },
    WBP_ItemPickups_Item_C = { centered = true, examples = { ItemText = "Bronze Pickaxe", ItemCountText = "x1" } },
    WBP_PrimaryNotificationQueue_Item_C = { pages = { "AchievementNotificationItem", "NewSkillNotificationItem",
        "MilestoneMaterialNotificationItem", "FishCaughtNotificationItem", "ArenaNotificationItem",
        "LevelUpVendorNotificationItem", "FinalBossExtractionPointUnlockNotificationItem",
        "FinalBossDefeatedNotificationItem" } },
}

local records = {} -- { w, kind = "vis"|"opacity"|"text"|"page"|"color"|"move", old, new, entry }
local entries = {} -- notice entries shown: { w, pages = { index... }, at, switcher, nextAt }
local TextBlockClass

local function rec(w, kind, old, new, entry)
    records[#records + 1] = { w = w, kind = kind, old = old, new = new, entry = entry }
end

local function set(r, value)
    pcall(function()
        if r.kind == "vis" then r.w:SetVisibility(value)
        elseif r.kind == "opacity" then r.w:SetRenderOpacity(value)
        elseif r.kind == "page" then r.w:SetActiveWidgetIndex(value)
        elseif r.kind == "color" then r.w:SetColorAndOpacity(value)
        elseif r.kind == "move" then r.w:SetRenderTranslation(value)
        else r.w:SetText(FText(value)) end
    end)
end

-- Pure: the indexes of the wanted pages among a switcher's children (names in order), in the order wanted; the
-- ones it hasn't are left out. Unit-tested.
function M.pageIndexes(childNames, wanted)
    local at, out = {}, {}
    for i, n in ipairs(childNames) do at[n] = i - 1 end
    for _, n in ipairs(wanted) do if at[n] then out[#out + 1] = at[n] end end
    return out
end

local function field(w, name)
    local ok, v = pcall(function() return w[name] end)
    return ok and W.valid(v) and v or nil
end

-- Show one collapsed notice entry (recording what it had).
local function showEntry(item, how)
    local e = { w = item }
    local okV, vis = pcall(function() return item:GetVisibility() end)
    local okO, op = pcall(function() return item:GetRenderOpacity() end)
    if not (okV and okO) then return end
    rec(item, "vis", vis, SHOWN, e)
    rec(item, "opacity", op, 1, e)
    if how.pages then
        local sw = item.WidgetTree and item.WidgetTree.RootWidget
        if W.valid(sw) then
            local kids = {}
            for _, c in ipairs(W.children(sw)) do kids[#kids + 1] = W.name(c) end
            local pages = M.pageIndexes(kids, how.pages)
            local okI, index = pcall(function() return sw:GetActiveWidgetIndex() end)
            if #pages > 0 and okI then
                e.switcher, e.pages, e.at, e.nextAt = sw, pages, 1, os.clock() + PAGE_SECONDS
                rec(sw, "page", index, pages[1], e)
                e.pageRecord = records[#records]
            end
        end
    end
    for name, text in pairs(how.examples or {}) do
        local t = field(item, name)
        local ok, cur = pcall(function() return t:GetText():ToString() end)
        if t and ok and cur == "" then rec(t, "text", "", text, e) end
    end
    for _, name in ipairs(how.quiet or {}) do
        local p = field(item, name)
        local ok, v = pcall(function() return p:GetVisibility() end)
        if p and ok then rec(p, "vis", v, COLLAPSED, e) end
    end
    if how.opaque then
        local ok, c = pcall(function() local x = item.ColorAndOpacity return { R = x.R, G = x.G, B = x.B, A = x.A } end)
        if ok then rec(item, "color", c, { R = c.R, G = c.G, B = c.B, A = 1 }, e) end
    end
    if how.centered then
        local ok, t = pcall(function() local x = item.RenderTransform.Translation return { X = x.X, Y = x.Y } end)
        if ok then rec(item, "move", t, { X = 0, Y = 0 }, e) end
    end
    entries[#entries + 1] = e
end

-- The first collapsed entry of each kind of notice inside `w` (or `w` itself) is shown.
local function showNotices(w)
    local done = {}
    W.walk(w, function(x)
        local cls = W.className(x)
        local how = cls and M.NOTICES[cls]
        if not how then return true end
        if not done[cls] then
            local ok, vis = pcall(function() return x:GetVisibility() end)
            if ok and vis == COLLAPSED then
                done[cls] = true
                pcall(showEntry, x, how)
            end
        end
        return false
    end, 0, 14)
end

-- Has the game taken this shown entry for a real notice (its visibility no longer ours)?
local function taken(e)
    if e.gone then return true end
    local ok, vis = pcall(function() return e.w:GetVisibility() end)
    if W.valid(e.w) and ok and vis == SHOWN then return false end
    e.gone = true
    return true
end

local function isTextBlock(w)
    if not W.valid(TextBlockClass) then TextBlockClass = StaticFindObject("/Script/UMG.TextBlock") end
    if not W.valid(TextBlockClass) then return false end
    local ok, r = pcall(function() return w:IsA(TextBlockClass) end)
    return ok and r == true
end

-- ghostOpacity: when set (element hidden by the layout), the element itself shows at this opacity.
function M.begin(w, ghostOpacity, maxTextBlocks)
    M.finish()
    -- visibility + opacity along the chain from the element up to its root
    local cur, depth = w, 0
    while cur and W.valid(cur) and depth < 40 do
        local okV, vis = pcall(function() return cur:GetVisibility() end)
        if okV and (vis == 1 or vis == 2) then rec(cur, "vis", vis, 3) end
        local okO, op = pcall(function() return cur:GetRenderOpacity() end)
        if depth == 0 and ghostOpacity then
            if okO then rec(cur, "opacity", op, ghostOpacity) end
        elseif okO and type(op) == "number" and op < 0.05 then
            rec(cur, "opacity", op, 1)
        end
        cur = W.parent(cur)
        depth = depth + 1
    end
    -- the game's notice entries inside it (before the placeholder text: their example texts come first)
    showNotices(w)
    local given = {} -- text blocks that already have an example
    for _, r in ipairs(records) do if r.kind == "text" then given[W.fullName(r.w)] = true end end
    -- placeholder text in empty text blocks inside the element
    local budget = maxTextBlocks or 40
    W.walk(w, function(child)
        if budget <= 0 then return false end
        if isTextBlock(child) then
            local ok, text = pcall(function() return child:GetText():ToString() end)
            if ok and text == "" and not given[W.fullName(child)] then
                rec(child, "text", "", names.pretty(W.name(child)))
                budget = budget - 1
            end
            return false
        end
        return true
    end, 0, 25)
    for _, r in ipairs(records) do set(r, r.new) end
    -- empty lists inside it: example entries of their own class, where they sit
    local okR, at = pcall(require("framemage.core.geometry").rect, w)
    pcall(examples.show, w, okR and at or nil)
end

-- The box round the notice entries and example entries shown (viewport units, via geometry.rect), or nil when none
-- shows.
function M.noticeRect(rectOf)
    local box = examples.rect()
    for _, e in ipairs(entries) do
        local q = not taken(e) and rectOf(e.w)
        if q and q.right > q.left and q.bottom > q.top then
            box = box and { left = math.min(box.left, q.left), top = math.min(box.top, q.top),
                right = math.max(box.right, q.right), bottom = math.max(box.bottom, q.bottom) } or q
        end
    end
    return box
end

-- Re-apply (the game may collapse or fade the element again while it's selected).
function M.tick()
    local now = os.clock()
    for _, e in ipairs(entries) do
        -- a notice with several kinds of page: the next one
        if not taken(e) and e.pages and #e.pages > 1 and now >= e.nextAt then
            e.at, e.nextAt = e.at % #e.pages + 1, now + PAGE_SECONDS
            e.pageRecord.new = e.pages[e.at]
            set(e.pageRecord, e.pageRecord.new)
        end
    end
    for _, r in ipairs(records) do
        if r.entry and taken(r.entry) then
            -- (the game is using it for a real notice: left alone)
        elseif W.valid(r.w) then
            local ok, cur = pcall(function()
                if r.kind == "vis" then return r.w:GetVisibility()
                elseif r.kind == "opacity" then return r.w:GetRenderOpacity() end
                return nil -- text is only set once: the game may legitimately fill it in meanwhile
            end)
            if ok and cur ~= nil and math.abs(cur - r.new) > 1e-3 then set(r, r.new) end
        end
    end
end

-- Undo everything, newest first. Text is only restored if it still shows our placeholder.
function M.finish()
    for i = #records, 1, -1 do
        local r = records[i]
        if r.entry and taken(r.entry) then
            -- (the game took it for a real notice: left as the game has it)
        elseif W.valid(r.w) then
            if r.kind == "text" then
                local ok, text = pcall(function() return r.w:GetText():ToString() end)
                if ok and text == r.new then set(r, r.old) end
            else
                set(r, r.old)
            end
        end
    end
    records = {}
    entries = {}
    examples.clear()
end

-- Forget handles without touching anything (the world changed; the widgets are gone).
function M.forget() records = {}; entries = {}; examples.forget() end

function M.active() return #records > 0 end

function M.init(c) examples.init(c) end

return M
