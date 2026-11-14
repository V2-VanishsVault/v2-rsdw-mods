-- Reloading in a running game (UE4SS's Ctrl+R): Frame Mage starts afresh, but what the last run added to the
-- game's screens is still there. Two things make that safe:
--   * every object we name "FM_..." gets this run's own suffix (one place: StaticConstructObject is wrapped), so a
--     new object never takes the name of a leftover in the same outer - the engine fails hard on that
--   * at start, every leftover is taken away: our overlays leave the viewport, our widgets in the game's own
--     trees are removed, and a holder of ours that wraps a game widget (the weight bar's frame) is unwrapped, the
--     game's widget put back in its place
-- The game widgets we restyled (brushes, opacity) are simply restyled again by the new run.
local M = {}

M.RUN = nil -- this run's suffix

-- Pure: an object name with this run's suffix, if it's one of ours (FM_...). Unit-tested.
function M.runName(name, run)
    if type(name) ~= "string" or name:sub(1, 3) ~= "FM_" or not run then return name end
    return name .. "_r" .. run
end

-- Pure: is this the name of one of our objects? Unit-tested.
function M.isOurs(name) return type(name) == "string" and name:sub(1, 3) == "FM_" end

function M.install()
    if M.RUN then return end
    math.randomseed(os.time() + math.floor(os.clock() * 1000))
    M.RUN = string.format("%x%x", os.time() % 0x100000, math.random(0, 0xfff))
    local raw = StaticConstructObject
    if not raw then return end
    StaticConstructObject = function(cls, outer, name, ...)
        local ok, s = pcall(function() return name:ToString() end)
        if ok and M.isOurs(s) then name = FName(M.runName(s, M.RUN)) end
        return raw(cls, outer, name, ...)
    end
end

local CLASSES = { "UserWidget", "Image", "Border", "Overlay", "SizeBox", "HorizontalBox", "VerticalBox", "TextBlock",
    "CanvasPanel", "ScaleBox", "Spacer" }

-- Slot settings worth carrying over when a widget moves to another slot.
local function slotOf(w)
    local out = {}
    local s
    pcall(function() s = w.Slot end)
    if not s then return out end
    pcall(function() out.size = { SizeRule = s.Size.SizeRule, Value = s.Size.Value } end)
    pcall(function() local p = s.Padding out.pad = { Left = p.Left, Top = p.Top, Right = p.Right, Bottom = p.Bottom } end)
    pcall(function() out.h = s.HorizontalAlignment end)
    pcall(function() out.v = s.VerticalAlignment end)
    return out
end

local function apply(sl, o)
    if not sl then return end
    if o.size then pcall(function() sl:SetSize(o.size) end) end
    if o.pad then pcall(function() sl:SetPadding(o.pad) end) end
    if o.h then pcall(function() sl:SetHorizontalAlignment(o.h) end) end
    if o.v then pcall(function() sl:SetVerticalAlignment(o.v) end) end
end

-- A holder of ours around game widgets: the game's widgets go back where the holder was (with its slot settings),
-- the widgets after it back after them, and the holder away.
local function unwrap(W, holder, parent, gameKids)
    local kids = W.children(parent)
    local at
    local hf = W.fullName(holder)
    for i, k in ipairs(kids) do if W.fullName(k) == hf then at = i end end
    if not at then return false end
    local holderSlot = slotOf(holder)
    local after = {}
    for i = at + 1, #kids do after[#after + 1] = { w = kids[i], slot = slotOf(kids[i]) } end
    for _, a in ipairs(after) do pcall(function() parent:RemoveChild(a.w) end) end
    pcall(function() parent:RemoveChild(holder) end)
    for _, g in ipairs(gameKids) do
        pcall(function() holder:RemoveChild(g) end)
        local ok, sl = pcall(function() return parent:AddChild(g) end)
        if ok then apply(sl, holderSlot) end
    end
    for _, a in ipairs(after) do
        local ok, sl = pcall(function() return parent:AddChild(a.w) end)
        if ok then apply(sl, a.slot) end
    end
    return true
end

-- Take away everything a previous run left behind. Returns how many overlays and widgets went.
function M.cleanup(W, log)
    local overlays, widgets, unwrapped = 0, 0, 0
    local function named(o)
        local ok, n = pcall(W.name, o)
        return ok and n or nil
    end
    for _, cls in ipairs(CLASSES) do
        for _, w in pairs(FindAllOf(cls) or {}) do
            local n = W.valid(w) and named(w)
            -- (this run's own objects carry its suffix: never touched)
            if n and M.isOurs(n) and not (M.RUN and n:find("_r" .. M.RUN, 1, true)) then
                if cls == "UserWidget" then
                    -- an overlay of ours: out of the viewport
                    if pcall(function() w:RemoveFromParent() end) then overlays = overlays + 1 end
                else
                    local parent = W.parent(w)
                    local pn = parent and named(parent)
                    -- only the outermost of ours in a game tree (what's inside goes with it)
                    if parent and pn and not M.isOurs(pn) then
                        local game = {}
                        for _, k in ipairs(W.children(w) or {}) do
                            local kn = named(k)
                            if kn and not M.isOurs(kn) then game[#game + 1] = k end
                        end
                        if #game > 0 then
                            if unwrap(W, w, parent, game) then unwrapped = unwrapped + 1 end
                        elseif pcall(function() w:RemoveFromParent() end) then
                            widgets = widgets + 1
                        end
                    end
                end
            end
        end
    end
    if overlays + widgets + unwrapped > 0 then
        log.info("reload: took away %d overlays and %d widgets left by the last run; put %d game widgets back",
            overlays, widgets, unwrapped)
    end
    return overlays, widgets, unwrapped
end

return M
