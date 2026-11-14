-- Preview: make the selected element visible while it's being edited, even when the game currently has
-- nothing to show in it (a boss bar with no boss, an empty notification, a faded-out prompt).
--
--   * the element and every ancestor that is Collapsed/Hidden is shown (hit-test invisible, so it can't
--     swallow clicks)
--   * near-zero render opacity on that chain is raised to full (hidden-by-layout elements show as a ghost)
--   * empty text blocks inside it get a placeholder label, so its text areas have size and can be seen
--   What the element shows otherwise is the designer's default content: images and text set in the widget
--   blueprint remain until the game replaces them at runtime.
-- Every change is recorded and undone by finish(); tick() re-applies them if the game hides things again.
local W = require("framemage.core.widgets")
local names = require("framemage.core.names")

local M = {}

local records = {} -- { w, kind = "vis"|"opacity"|"text", old, new }
local TextBlockClass

local function rec(w, kind, old, new)
    records[#records + 1] = { w = w, kind = kind, old = old, new = new }
end

local function set(r, value)
    pcall(function()
        if r.kind == "vis" then r.w:SetVisibility(value)
        elseif r.kind == "opacity" then r.w:SetRenderOpacity(value)
        else r.w:SetText(FText(value)) end
    end)
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
    -- placeholder text in empty text blocks inside the element
    local budget = maxTextBlocks or 40
    W.walk(w, function(child)
        if budget <= 0 then return false end
        if isTextBlock(child) then
            local ok, text = pcall(function() return child:GetText():ToString() end)
            if ok and text == "" then
                rec(child, "text", "", names.pretty(W.name(child)))
                budget = budget - 1
            end
            return false
        end
        return true
    end, 0, 25)
    for _, r in ipairs(records) do set(r, r.new) end
end

-- Re-apply (the game may collapse or fade the element again while it's selected).
function M.tick()
    for _, r in ipairs(records) do
        if W.valid(r.w) then
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
        if W.valid(r.w) then
            if r.kind == "text" then
                local ok, text = pcall(function() return r.w:GetText():ToString() end)
                if ok and text == r.new then set(r, r.old) end
            else
                set(r, r.old)
            end
        end
    end
    records = {}
end

-- Forget handles without touching anything (the world changed; the widgets are gone).
function M.forget() records = {} end

function M.active() return #records > 0 end

return M
