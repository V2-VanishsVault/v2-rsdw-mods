-- The survival gauges' second layout (bars.survivalLayout = "stacked"): water, food and exhaustion in a column
-- just to the right of the vital bars, scaled so the three share the bars' height, and the buffs that follow them
-- in the survival row moved, in their own order, to the right of that column.
--
-- The game lays the gauges out in a HorizontalBox (WBP_SurvivalCore_Upkeep/HorizontalBox_1: each gauge with its
-- warning effect's box before it, then the buffs). Nothing is reparented: each piece gets a render transform (the
-- same mechanism as the layout editor's offsets), worked out from where the game put it and where the bars are.
-- "row" puts every piece back.
local measure = require("framemage.core.measure")

local M = {}

local ctx, W, log
local touched = {} -- fullName -> widget: everything we've transformed (put back when switching to "row")
local hiddenBg = {} -- fullName -> widget: the text background strip, hidden while stacked
local lastSig -- the last placement logged

M.UPKEEP = "WBP_SurvivalCore_Upkeep_C"
M.GAUGE = "WBP_SurvivalCore_Upkeep_RadialBase_C"
M.VITALS = "WBP_HUD_PlayerVitalsBars_C"

-- Pure: where each of n gauges goes (screen units) beside the vitals' box V: a column `gap` to its right, the
-- gauges (gw x gh each) scaled to share V's height (never above maxScale), each centered in its share.
-- { { x, y }, ... }, scale. Unit-tested.
function M.stack(V, gw, gh, n, gap, maxScale)
    local cell = (V.bottom - V.top) / n
    local s = math.min(maxScale or 1, cell / gh)
    local out = {}
    for i = 1, n do
        out[i] = { x = V.right + gap, y = V.top + (i - 1) * cell + (cell - gh * s) / 2 }
    end
    return out, s
end

-- Pure: where each gauge's ring (ringH tall on screen) goes beside the bars' rows (their rects, in order): a
-- column `gap` to the right of the furthest bar, each ring centered on its own bar. { { x, y }, ... }. Unit-tested.
function M.column(rows, ringH, gap)
    local right = rows[1].right
    for _, r in ipairs(rows) do right = math.max(right, r.right) end
    local out = {}
    for i, r in ipairs(rows) do
        out[i] = { x = right + gap, y = (r.top + r.bottom) / 2 - ringH / 2 }
    end
    return out
end

-- Pure: the render translation (the widget's own units, its parent drawing at scale ps) that moves a widget
-- naturally at (nx, ny) on screen to (x, y), its pivot at its top-left so a scale doesn't move that corner.
-- Unit-tested.
function M.translation(nx, ny, x, y, ps)
    ps = (ps and ps ~= 0) and ps or 1
    return (x - nx) / ps, (y - ny) / ps
end

local function set(w, tx, ty, s)
    pcall(function()
        w:SetRenderTransformPivot({ X = 0, Y = 0 })
        w:SetRenderTranslation({ X = tx, Y = ty })
        w:SetRenderScale({ X = s, Y = s })
    end)
    touched[W.fullName(w)] = w
end

-- A soft drop shadow under every text block in `root`, so white numbers stay readable on a bright floor or sky
-- (each block's own shadow kept, to put back).
local shadowed = {} -- fullName -> { w, offset, color }
local function shadowText(root, S)
    W.walk(root, function(x)
        local ok, isText = pcall(function() return x.ShadowOffset ~= nil and x.SetShadowOffset ~= nil end)
        if ok and isText then
            local full = W.fullName(x)
            if not shadowed[full] then
                local rec = { w = x }
                pcall(function()
                    rec.offset = { X = x.ShadowOffset.X, Y = x.ShadowOffset.Y }
                    local c = x.ShadowColorAndOpacity
                    rec.color = { R = c.R, G = c.G, B = c.B, A = c.A }
                end)
                shadowed[full] = rec
                local d = S.textShadowOffset or 1.5
                pcall(function()
                    x:SetShadowOffset({ X = d, Y = d })
                    x:SetShadowColorAndOpacity({ R = 0, G = 0, B = 0, A = S.textShadowOpacity or 0.85 })
                end)
            end
        end
        return true
    end)
end

local function restore()
    for full, rec in pairs(shadowed) do
        if W.valid(rec.w) and rec.offset then
            pcall(function()
                rec.w:SetShadowOffset(rec.offset)
                if rec.color then rec.w:SetShadowColorAndOpacity(rec.color) end
            end)
        end
        shadowed[full] = nil
    end
    for full, w in pairs(touched) do
        if W.valid(w) then
            pcall(function()
                w:SetRenderTranslation({ X = 0, Y = 0 })
                w:SetRenderScale({ X = 1, Y = 1 })
                w:SetRenderTransformPivot({ X = 0.5, Y = 0.5 })
            end)
        end
        touched[full] = nil
    end
    for full, w in pairs(hiddenBg) do
        if W.valid(w) then pcall(function() w:SetRenderOpacity(1) end) end
        hiddenBg[full] = nil
    end
end

local function named(root, name)
    local found
    W.walk(root, function(x)
        if found then return false end
        local ok, n = pcall(W.name, x)
        if ok and n == name then found = x return false end
        return true
    end)
    return found
end

local function classOf(w)
    local ok, c = pcall(W.className, w)
    return ok and c or ""
end

-- One survival widget, stacked beside the vitals bars.
local function stackOne(up, vitals, S)
    local row = named(up, "HorizontalBox_1")
    local bars = named(vitals, "StatBarVerticalBox") -- the three bars themselves (not the effect icons above them)
    if not (row and bars) then return false end
    local feature = ctx.features.bars
    local V = (feature and feature.barsRect and feature.barsRect()) or measure.rect(bars)
    local T = measure.transform(row)
    if not (V and T) then return false end
    -- the Survival element's own offset (moved in the editor) moves the whole stack: beside the bars is only where
    -- it starts. The offset = where the row is drawn minus where it would be without the element's own transforms.
    local base = measure.transform(W.parent(up))
    local Lrow = measure.layoutRect(row)
    local drawn = measure.rect(row)
    local plain = base and Lrow and measure.apply(base, Lrow)
    local ox, oy = 0, 0
    if drawn and plain then ox, oy = drawn.left - plain.left, drawn.top - plain.top end
    local kids = W.children(row)
    local gauges, last = {}, 0
    for i, k in ipairs(kids) do
        if classOf(k) == M.GAUGE and #gauges < 3 then gauges[#gauges + 1] = { w = k, i = i }; last = i end
    end
    if #gauges == 0 then return false end
    local function natural(w)
        local L = measure.layoutRect(w)
        return L and measure.apply(T, L)
    end
    local g1 = natural(gauges[1].w)
    if not g1 then return false end
    local gw = g1.right - g1.left
    -- each gauge is its ring with its value under it: in the column the ring alone shares the bars' height and the
    -- value moves beside it, so the rings are as big as they can be and the values stay readable
    local ring = named(gauges[1].w, "SegmentedRadialBar")
    local rr = ring and natural(ring)
    local gh = rr and (rr.bottom - rr.top) or (g1.bottom - g1.top)
    if gw <= 0 or gh <= 0 then return false end
    -- a fixed size (bars.survivalRingSize units for each ring), each gauge level with its bar's own row where the
    -- game lays the bars out: neither the bars' sizes nor moving a bar changes the column (move the Survival element
    -- to move it)
    local rows = feature and feature.barsNatural and feature.barsNatural()
    local s = (S.survivalRingSize or 40) / gh
    local targets
    if rows and #rows >= #gauges then
        targets = M.column(rows, gh * s, S.survivalGap or 28)
    else
        targets = M.stack(V, gw, gh, #gauges, S.survivalGap or 28, S.survivalMaxScale or 1)
    end
    local k = S.survivalTextScale or 1.35 -- the values' size on screen (1 = the game's)
    local textW = 0
    local ps = T.sx
    local sig = string.format("%.0f %.0f %.0f %.0f %.2f", V.left, V.top, V.right, V.bottom, s)
    if lastSig ~= sig then
        lastSig = sig
        log.info("survival: stacked beside the bars (%.0f,%.0f - %.0f,%.0f): gauges %.0fx%.0f at %.0f,%.0f, scale %.2f",
            V.left, V.top, V.right, V.bottom, gw, gh, targets[1].x, targets[1].y, s)
    end
    for _, t in ipairs(targets) do t.x, t.y = t.x + ox, t.y + oy end
    for n, g in ipairs(gauges) do
        local r = natural(g.w)
        if r then
            local t = targets[n]
            local gx, gy = M.translation(r.left, r.top, t.x, t.y, ps) -- (both values: not as a middle argument)
            set(g.w, gx, gy, s)
            -- its value: beside the ring, centered on it, at its own size (k), not shrunk with the gauge
            local val = named(g.w, "SizeBox_1")
            if val then shadowText(val, S) end -- (readable on a bright background)
            local vl, gl = val and measure.layoutRect(val), measure.layoutRect(g.w)
            if vl and gl then
                local th = vl.bottom - vl.top
                local tx = (gh / ps) + 6 - (vl.left - gl.left)         -- the gauge's own units (its ring is gh / ps)
                local ty = (gh / ps - th * k / s) / 2 - (vl.top - gl.top)
                set(val, tx, ty, k / s)
                textW = math.max(textW, (vl.right - vl.left) * ps * k)
            end
            -- its warning effect (the box just before it) goes with it, at the same scale
            local fx = kids[g.i - 1]
            if fx and classOf(fx) ~= M.GAUGE then
                local fr = natural(fx)
                if fr then
                    local tx, ty = M.translation(fr.left, fr.top, t.x + (fr.left - r.left) * s, t.y + (fr.top - r.top) * s, ps)
                    set(fx, tx, ty, s)
                end
            end
        end
    end
    -- the buffs: everything after the last gauge (the divider, the buff lists), as a group to the right of the
    -- column and its values, their rings the size of the gauges' rings, keeping their spacing, centered on the bars
    -- (at their own size: shrunk to the gauges' rings, their durations were too small to read, and scaling those back
    -- up pushed them out of the list, which clips its rows. survivalShrinkBuffs = true shrinks them as before.)
    local bs = S.survivalShrinkBuffs and math.min(1, s * gh / (S.survivalBuffRing or 61 * ps)) or 1
    local startX = targets[1].x + (gh + 6 * ps) * s + textW + (S.survivalBuffGap or 14)
    local midY = ((rows and rows[2]) and (rows[2].top + rows[2].bottom) / 2 or (V.top + V.bottom) / 2) + oy
    local first
    for i = last + 1, #kids do
        local r = natural(kids[i])
        if r and r.right > r.left then
            first = first or r
            local x = startX + (r.left - first.left) * bs
            local y = midY - (r.bottom - r.top) * bs / 2
            local bx, by = M.translation(r.left, r.top, x, y, ps)
            set(kids[i], bx, by, bs)
        end
    end
    -- the buffs' durations: the game's own, at their own size under each ring - only their dim backing taken away and
    -- a drop shadow added (like the survival values)
    for _, cls in ipairs({ "WBP_HUD_FoodBuffListEntry_C", "WBP_HUD_DrinkBuffListEntry_C" }) do
        for _, e in pairs(FindAllOf(cls) or {}) do
            local t = W.valid(e) and W.isInstance(e) and named(e, "Overlay_1")
            if t then
                pcall(function() if t:GetRenderOpacity() ~= 1 then t:SetRenderOpacity(1) end end)
                local back = named(t, "TextBackground")
                if back then
                    pcall(function() if back:GetRenderOpacity() ~= 0 then back:SetRenderOpacity(0) end end)
                    hiddenBg[W.fullName(back)] = back
                end
                shadowText(t, S)
            end
        end
    end
    -- the strip behind the values (sized for the row) doesn't fit the column
    local bg = named(up, "TextBackground")
    if bg then
        pcall(function() bg:SetRenderOpacity(0) end)
        hiddenBg[W.fullName(bg)] = bg
    end
    return true
end

local function tick()
    local S = ctx.settings.bars or {}
    if not (ctx.enabled and S.survivalLayout == "stacked") then
        if next(touched) or next(hiddenBg) then restore() end
        return
    end
    local vitals
    for _, v in pairs(FindAllOf(M.VITALS) or {}) do
        if W.valid(v) and W.isInstance(v) and W.isVisible(v) then vitals = v break end
    end
    if not vitals then return end
    for _, up in pairs(FindAllOf(M.UPKEEP) or {}) do
        if W.valid(up) and W.isInstance(up) then
            local ok, err = pcall(stackOne, up, vitals, S)
            if not ok then log.debug("survival: %s", tostring(err)) end
        end
    end
end

function M.init(c)
    ctx, W, log = c, c.widgets, c.log
    c.events.on("worldchanged", function() touched, hiddenBg = {}, {} end)
    -- often enough to follow the bars (they move when edited, and buffs come and go)
    c.sched.every(150, "survival.stack", function()
        local ok, err = pcall(tick)
        if not ok then log.debug("survival: %s", tostring(err)) end
    end)
end

return M
