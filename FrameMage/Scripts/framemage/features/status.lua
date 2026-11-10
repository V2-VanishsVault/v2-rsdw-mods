-- Status effects (Cosiness, the weather, Encumbered, Sheltered...) as round gauges like the survival gauges. Each
-- game status row (WBP_HUD_StatusEffectListEntry: an icon and a thin bar) is read and shown as a gauge in an
-- overlay of ours, where the list sits: a timed effect (its bar shows, running down) in the survival gauges' own
-- ring (their background T_Upkeep and radial fill, MI_UI_ReverseRadialFill_Upkeep) in its bar's color, with the
-- theme's rim; an on / off effect (Sheltered) in the theme's icon ring, like the vitals' icons. Also: the theme's
-- rim round the game's own survival and buff gauges.
local M = {}

local ctx, W, log
local done = {} -- fullName of an entry -> { ring = {images}, mid, bar, icon }
local radial -- the survival gauges' radial fill material (the parent our fills are made from)

M.ENTRY = "WBP_HUD_StatusEffectListEntry_C"
local RADIAL = "MI_UI_ReverseRadialFill_Upkeep"

-- Pure: what a status entry shows: a ring (and its fill) when its bar shows, else its icon alone. Unit-tested.
function M.ringFill(barShown, fill)
    if not barShown then return nil end
    return math.max(0, math.min(1, fill or 0))
end

local function named(root, name)
    local found
    W.walk(root, function(x)
        if found then return false end
        local ok, n = pcall(W.name, x)
        if ok and n == name then found = x return false end
        return true
    end, 0, 8)
    return found
end

-- The survival gauges' radial fill material: from a gauge on screen, else found by name (once).
local function radialParent()
    if radial and W.valid(radial) then return radial end
    for _, g in pairs(FindAllOf("WBP_SegmentedRadialBar_C") or {}) do
        local img = W.valid(g) and named(g, "RadialImage")
        local ok, p = pcall(function() return img.Brush.ResourceObject.Parent end)
        if ok and W.valid(p) then radial = p return p end
    end
    for _, m in pairs(FindAllOf("MaterialInstanceConstant") or {}) do
        local ok, n = pcall(W.name, m)
        if ok and n == RADIAL then radial = m return m end
    end
    return nil
end

local function texture(name)
    local art = ctx.features.art
    return art and art.gameTexture and art.gameTexture(name) or nil
end

local function image(tree, name, tex, size)
    local img = StaticConstructObject(StaticFindObject("/Script/UMG.Image"), tree, FName(name))
    if tex then
        pcall(function() img:SetBrush({ ResourceObject = tex, ImageSize = { X = size, Y = size }, DrawAs = 3, Tiling = 0,
            TintColor = { SpecifiedColor = { R = 1, G = 1, B = 1, A = 1 }, ColorUseRule = 0 } }) end)
    end
    pcall(function() img:SetVisibility(3) end)
    return img
end

local made = 0

-- The theme's rim round every gauge (ui/gauge_rim.png): the survival gauges, the buffs and the status gauges.
local rims = {} -- fullName of the gauge -> { img, size }
local rimTheme -- the theme the rims were last drawn in

local function rimBrush(size, wc)
    local art = ctx.features.art
    local path = ctx.themes.find("ui/gauge_rim.png")
    local tex = art and path and art.loadFile(path, wc)
    if not tex then return nil end
    return { ResourceObject = tex, ImageSize = { X = size, Y = size }, DrawAs = 3, Tiling = 0,
        TintColor = { SpecifiedColor = { R = 1, G = 1, B = 1, A = 1 }, ColorUseRule = 0 } }
end

local function addRim(key, overlay, tree, wc, size, centered)
    if rims[key] or not (overlay and tree) then return rims[key] end
    made = made + 1
    local img = StaticConstructObject(StaticFindObject("/Script/UMG.Image"), tree, FName("FM_GaugeRim_" .. made))
    local b = rimBrush(size, wc)
    if b then ctx.features.art.guarded(function() img:SetBrush(b) end) end
    pcall(function() img:SetVisibility(3) end)
    local ok = pcall(function()
        local sl = overlay:AddChildToOverlay(img)
        sl:SetHorizontalAlignment(centered and 2 or 0)
        sl:SetVerticalAlignment(centered and 2 or 0)
    end)
    if not ok then return nil end
    rims[key] = { img = img, size = size, wc = wc }
    return rims[key]
end

-- The game's own gauges: the survival gauges' rings and the food / drink buffs' rings, each given the rim once.
local function rimGameGauges(S)
    for _, g in pairs(FindAllOf("WBP_SegmentedRadialBar_C") or {}) do
        if W.valid(g) and W.isInstance(g) then
            local full = W.fullName(g)
            if not rims[full] then addRim(full, named(g, "Overlay_0"), g.WidgetTree, g, S.gaugeRimSize or 68) end
        end
    end
    for _, cls in ipairs({ "WBP_HUD_FoodBuffListEntry_C", "WBP_HUD_DrinkBuffListEntry_C" }) do
        for _, e in pairs(FindAllOf(cls) or {}) do
            if W.valid(e) and W.isInstance(e) then
                local full = W.fullName(e)
                if not rims[full] then addRim(full, named(e, "Overlay_0"), e.WidgetTree, e, S.buffRimSize or 61) end
            end
        end
    end
end

-- How heavy the pack is: carried / limit, from the game's own weight bar (it can pass 1 when overloaded); nil until
-- the game has told us.
local weightRatio

-- Pure: the color for a load (carried / limit): green to half, yellow to 75%, orange to 90%, red to 100%, and
-- past that a red that pulses (t = seconds, for the pulse). Percent is rounded first. Unit-tested.
M.WEIGHT_BANDS = { -- { up to this percent, color }
    { 50, { 0.10, 0.70, 0.15 } },  -- green
    { 75, { 0.95, 0.80, 0.05 } },  -- yellow
    { 90, { 1.00, 0.40, 0.02 } },  -- orange
    { 100, { 0.85, 0.05, 0.04 } }, -- red
}
function M.weightColor(ratio, t)
    local pct = math.floor(math.max(0, ratio or 0) * 100 + 0.5)
    for _, b in ipairs(M.WEIGHT_BANDS) do
        if pct <= b[1] then local c = b[2] return { R = c[1], G = c[2], B = c[3], A = 1 } end
    end
    -- overloaded: red pulsing between full and dark, about once a second
    local k = 0.45 + 0.55 * (0.5 + 0.5 * math.sin((t or 0) * 2 * math.pi))
    return { R = 1.0 * k, G = 0.06 * k, B = 0.05 * k, A = 1 }
end

-- Pure: carried / limit from the weight bar's text ("286/475", "286.5 / 475"), or nil. Unit-tested.
function M.parseWeight(text)
    local a, b = tostring(text or ""):match("([%d%.,]+)%s*/%s*([%d%.,]+)")
    a = a and tonumber((a:gsub(",", ""))); b = b and tonumber((b:gsub(",", "")))
    if a and b and b > 0 then return a / b end
    return nil
end

-- The weight bar's text, read (the game keeps it current even with the inventory closed, once it has been made).
local function textRatio()
    for _, wb in pairs(FindAllOf("WBP_Inventory_WeightBar_C") or {}) do
        if W.valid(wb) and W.isInstance(wb) then
            local r
            local t = named(wb, "WeightText")
            if t then
                W.walk(t, function(x)
                    if r then return false end
                    local okT, s = pcall(function() return x:GetText():ToString() end)
                    if okT then r = M.parseWeight(s) end
                    return r == nil
                end, 0, 6)
            end
            if r then return r end
        end
    end
    return nil
end

-- The load now: the weight bar's text, else the game's last weight report, else the HUD gauge's own fill (which
-- stops at full).
local lastLoggedLoad
local function loadRatio(gaugeMid)
    local r = textRatio() or weightRatio
    if r then
        if not lastLoggedLoad or math.abs(r - lastLoggedLoad) > 0.05 then
            lastLoggedLoad = r
            log.info("status: load %.0f%%", r * 100)
        end
        return r
    end
    local ok, v = pcall(function() return gaugeMid:K2_GetScalarParameterValue(FName("FillBar")) end)
    return ok and type(v) == "number" and v or nil
end

-- The stone disc behind each shortcut's icon (the panels' stone, made round: <stone>_disc.png).
local stoneOn = {} -- fullName of the background image -> the disc file it has
local function stoneDisc(bgImg, size)
    local art = ctx.features.art
    local style = require("framemage.editor.style")
    local file = style.stoneFile(ctx.settings.stone):gsub("%.png$", "_disc.png")
    local path = ctx.themes.find("ui/" .. file) or ctx.themes.find("ui/panel_stone_disc.png")
    local full = W.fullName(bgImg)
    if not path or stoneOn[full] == path then return end
    local tex = art and art.loadFile(path, bgImg)
    if tex then
        art.guarded(function() bgImg:SetBrush({ ResourceObject = tex, ImageSize = { X = size, Y = size }, DrawAs = 3,
            Tiling = 0, TintColor = { SpecifiedColor = { R = 1, G = 1, B = 1, A = 1 }, ColorUseRule = 0 } }) end)
        stoneOn[full] = path
    end
end

-- The menu shortcuts (chat, map, spells, building, inventory with its encumbrance gauge): each circle the status
-- gauges' size, on the panels' stone, with the theme's rim round it; the inventory's load gauge colored by how
-- heavy the pack is.
local SHORTCUTS = { "WBP_InputLegend_Contextual_Entry_C", "WBP_InputLegend_Contextual_InventoryEntry_C" }
local function rimShortcuts(S)
    local size = S.menuShortcutSize or 0
    local entries = {}
    for _, cls in ipairs(SHORTCUTS) do
        for _, e in pairs(FindAllOf(cls) or {}) do entries[#entries + 1] = e end
    end
    for _, e in ipairs(entries) do
        if W.valid(e) and W.isInstance(e) then
            local full = W.fullName(e)
            local bg = named(e, "BackgroundImage")
            if bg then pcall(stoneDisc, bg, size > 0 and size or 64) end
            local gauge = named(e, "EncumbranceRadialImage")
            if gauge and S.weightColors ~= false then
                local okM, mid = pcall(function() return gauge.Brush.ResourceObject end)
                local r = okM and loadRatio(mid)
                if r then pcall(function() gauge:SetColorAndOpacity(M.weightColor(r, os.clock())) end) end
            end
            if size > 0 then
                local box = named(e, "SizeBox_115")
                if box then
                    pcall(function()
                        if box.WidthOverride ~= size or not box.bOverride_WidthOverride then box:SetWidthOverride(size) end
                        if box.HeightOverride ~= size or not box.bOverride_HeightOverride then box:SetHeightOverride(size) end
                    end)
                end
            end
            if not rims[full] then
                addRim(full, named(e, "Overlay_371"), e.WidgetTree, e, size > 0 and size or 64, true)
            end
        end
    end
end

-- The inventory's weight bar in the theme: its trough framed by the theme's rim (ui/weight_trough.png as the bar's
-- background, ui/weight_fill.png as its fill: clear over the rim, so the fill sits inside it) and its icon on the
-- theme's material (ui/weight_icon.png, the theme's own only: Demi-human keeps the game's icon).
local weightThemed = {} -- fullName of the weight bar -> theme it was styled in
local weightFrames = {} -- fullName of our frame round a weight bar -> { frame, icon (its row's icon, to follow) }
local gameWeightIcon -- the game's icon texture (to put back)
local loggedWeight
local function box(tex, w, h)
    return { ResourceObject = tex, ImageSize = { X = w, Y = h }, DrawAs = 1, Tiling = 0,
        Margin = { Left = 0.25, Top = 0.25, Right = 0.25, Bottom = 0.25 },
        TintColor = { SpecifiedColor = { R = 1, G = 1, B = 1, A = 1 }, ColorUseRule = 0 } }
end
local function themeWeightBar(wb, pb)
    local t = ctx.themes.current()
    local full = W.fullName(wb)
    if weightThemed[full] == t then return end
    weightThemed[full] = t
    local art = ctx.features.art
    if not art then return end
    -- the icon: the theme's own, else the game's
    local icon = named(wb, "WeightIcon")
    if icon then
        pcall(function() gameWeightIcon = gameWeightIcon or icon.Brush.ResourceObject end)
        local own = ctx.themes.dir(t) .. "ui/weight_icon.png"
        local tex = ctx.fs.exists(own) and art.loadFile(own, wb) or gameWeightIcon
        if tex then
            art.guarded(function()
                local sz = (tex == gameWeightIcon) and 40 or (ctx.settings.bars.weightIconSize or 28) -- (ours has no margin)
                icon:SetBrush({ ResourceObject = tex, ImageSize = { X = sz, Y = sz }, DrawAs = 3, Tiling = 0,
                    TintColor = { SpecifiedColor = { R = 1, G = 1, B = 1, A = 1 }, ColorUseRule = 0 } })
            end)
        end
    end
    -- the trough and fill: written into the bar's style (its Slate bar draws from that style every frame)
    local tp, fp = ctx.themes.find("ui/weight_trough.png"), ctx.themes.find("ui/weight_fill.png")
    local tt, ft = tp and art.loadFile(tp, wb), fp and art.loadFile(fp, wb)
    if not (tt and ft) then return end
    -- (the bar's own style can't be written from here: the trough goes behind it instead, in an overlay of ours
    -- that takes the bar's place in its row, the bar padded inside the rim)
    local ok, err = pcall(function()
        local holder = W.parent(pb)
        local frame
        if holder and W.name(holder):sub(1, 15) == "FM_WeightFrame_" then
            frame = holder
        else
            frame = M.wrapWeightBar(wb, pb)
        end
        local trough = frame and W.children(frame)[1] -- (the trough: the frame's first layer)
        if frame then weightFrames[W.fullName(frame)] = { frame = frame, icon = named(wb, "WeightIcon"), bar = pb } end
        if trough then trough:SetBrush(box(tt, 32, 16)) end
    end)
    if not loggedWeight then
        loggedWeight = true
        log.info("status: weight bar trough: %s", ok and "ok" or tostring(err))
    end
end

-- Put the weight bar inside an overlay of ours (same place, same slot settings), with the trough image behind it.
-- The row is rebuilt from the bar on: the bar and whatever follows it come out, the overlay goes in, and the rest go
-- back in order with their own settings.
function M.wrapWeightBar(wb, pb)
    local row = W.parent(pb)
    local tree = wb.WidgetTree
    if not (row and tree) then return nil end
    local kids = W.children(row)
    local at
    for i, k in ipairs(kids) do if W.fullName(k) == W.fullName(pb) then at = i end end
    if not at then return nil end
    local function slotOf(w)
        local s = w.Slot
        local out = {}
        pcall(function() out.size = { SizeRule = s.Size.SizeRule, Value = s.Size.Value } end)
        pcall(function() local p = s.Padding out.pad = { Left = p.Left, Top = p.Top, Right = p.Right, Bottom = p.Bottom } end)
        pcall(function() out.h = s.HorizontalAlignment end)
        pcall(function() out.v = s.VerticalAlignment end)
        return out
    end
    local function apply(sl, o)
        if o.size then pcall(function() sl:SetSize(o.size) end) end
        if o.pad then pcall(function() sl:SetPadding(o.pad) end) end
        if o.h then pcall(function() sl:SetHorizontalAlignment(o.h) end) end
        if o.v then pcall(function() sl:SetVerticalAlignment(o.v) end) end
    end
    local moved = {}
    for i = at, #kids do moved[#moved + 1] = { w = kids[i], slot = slotOf(kids[i]) } end
    for _, m in ipairs(moved) do row:RemoveChild(m.w) end
    -- (if anything below fails, everything goes back as it was: the bar must never go missing)
    local function putBack()
        for _, m in ipairs(moved) do
            pcall(function() local p = W.parent(m.w) if p then p:RemoveChild(m.w) end end)
            local okA, sl = pcall(function() return row:AddChild(m.w) end)
            if okA and sl then apply(sl, m.slot) end
        end
    end
    local okW, frame = pcall(function()
    made = made + 1
    local frame = StaticConstructObject(StaticFindObject("/Script/UMG.Overlay"), tree, FName("FM_WeightFrame_" .. made))
    local trough = StaticConstructObject(StaticFindObject("/Script/UMG.Image"), tree, FName("FM_WeightTrough_" .. made))
    pcall(function() trough:SetVisibility(3) end)
    local ts = frame:AddChildToOverlay(trough)
    ts:SetHorizontalAlignment(0); ts:SetVerticalAlignment(0) -- (fills the frame)
    local bs = frame:AddChildToOverlay(pb)
    bs:SetHorizontalAlignment(0); bs:SetVerticalAlignment(0)
    local rim = ctx.settings.bars.weightRim or 3
    bs:SetPadding({ Left = rim, Top = rim, Right = rim, Bottom = rim })
    for i, m in ipairs(moved) do
        local w = (i == 1) and frame or m.w
        local sl = row:AddChild(w)
        apply(sl, m.slot)
    end
    return frame
    end)
    if okW and frame then return frame end
    putBack()
    error(frame)
end

-- Pure: what our weight bar frame should do, given its row's icon (which the game shows and hides with the
-- inventory): { visible, opacity }. Unit-tested.
function M.followIcon(iconVisible, iconOpacity)
    return { visible = iconVisible == true, opacity = iconVisible and (tonumber(iconOpacity) or 1) or 0 }
end

-- Our frame (and the bar inside it) shows and fades exactly as the weight icon beside it does: the game hides the
-- row's pieces one by one when the inventory closes, and knows nothing of our frame.
local function syncWeightFrames()
    for full, f in pairs(weightFrames) do
        if not (W.valid(f.frame) and f.bar and W.valid(f.bar)) then
            weightFrames[full] = nil
        else
            -- the game hides the bar itself when the inventory closes (the icon beside it stays "visible"): the
            -- trough (the frame's first layer) follows the bar, the bar is left to the game
            local trough = W.children(f.frame)[1]
            local okV, vis = pcall(function() return f.bar:IsVisible() end)
            local okO, op = pcall(function() return f.bar:GetRenderOpacity() end)
            local want = M.followIcon(okV and vis, okO and op)
            if trough and W.valid(trough) then
                pcall(function()
                    local v = want.visible and 3 or 1 -- HitTestInvisible / Collapsed
                    if trough:GetVisibility() ~= v then trough:SetVisibility(v) end
                    if math.abs(trough:GetRenderOpacity() - want.opacity) > 0.01 then trough:SetRenderOpacity(want.opacity) end
                end)
            end
            -- (the frame itself always shown: it was hidden by the icon rule, and the bar inside goes with it)
            pcall(function() if f.frame:GetVisibility() ~= 4 then f.frame:SetVisibility(4) end end)
            pcall(function() if f.frame:GetRenderOpacity() < 1 then f.frame:SetRenderOpacity(1) end end)
        end
    end
end

-- ... and colored like the load gauge.
local function colorWeightBar(S)
    for _, wb in pairs(FindAllOf("WBP_Inventory_WeightBar_C") or {}) do
        if W.valid(wb) and W.isInstance(wb) and W.isVisible(wb) then
            local pb = named(wb, "WeightBar")
            if pb then pcall(themeWeightBar, wb, pb) end
            if pb and S.weightColors ~= false then
                pcall(function()
                    local r = textRatio() or weightRatio or pb.Percent
                    pb:SetFillColorAndOpacity(M.weightColor(r, os.clock()))
                end)
            end
        end
    end
end

-- A new theme: every rim, and every status icon's ring, redrawn in it.
local function retheme()
    local t = ctx.themes.current()
    if rimTheme == t then return end
    rimTheme = t
    local art = ctx.features.art
    local bpath = ctx.themes.find("ui/badge_ring.png")
    for _, rec in pairs(done) do
        for _, w in ipairs(rec.badge or {}) do
            local tex = art and bpath and W.valid(w) and art.loadFile(bpath, w)
            if tex then
                local size = 24 -- (drawn at the small base size; its render scale makes it the badge size)
                art.guarded(function() w:SetBrush({ ResourceObject = tex, ImageSize = { X = size, Y = size }, DrawAs = 3,
                    Tiling = 0, TintColor = { SpecifiedColor = { R = 1, G = 1, B = 1, A = 1 }, ColorUseRule = 0 } }) end)
            end
        end
    end
    for key, r in pairs(rims) do
        if W.valid(r.img) then
            local b = rimBrush(r.size, r.wc)
            if b then ctx.features.art.guarded(function() r.img:SetBrush(b) end) end
        else
            rims[key] = nil
        end
    end
end

-- A survival gauge's fill (its MID), whose settings - its fill texture above all - our fills copy.
local function survivalFill()
    for _, g in pairs(FindAllOf("WBP_SegmentedRadialBar_C") or {}) do
        local img = W.valid(g) and named(g, "RadialImage")
        local ok, m = pcall(function() return img.Brush.ResourceObject end)
        if ok and W.valid(m) then return m end
    end
end

-- Our status gauges ----------------------------------------------------------------------------------------------
-- Drawn in an overlay of our own, not inside the game's status rows: the status list lays its rows out short and
-- clips them, which squashed and cut off anything bigger drawn there. The game's rows stay, invisible, and are read
-- every tick: each one's icon, whether its bar shows (a timed effect) and its fill and color.

local overlay = require("framemage.core.overlay")
local measure = require("framemage.core.measure")
local WHITE = { SpecifiedColor = { R = 1, G = 1, B = 1, A = 1 }, ColorUseRule = 0 }

local host -- { uw, canvas, tree }
local pool = {} -- slot index -> { badge, ring, fill, mid, rim, icon (images), slots }
local hiddenRows = {} -- fullName -> a row's picture we made invisible
local movedRows = {} -- fullName -> a game row moved under its gauge (put back when the gauges are off)
local loggedFill

-- Pure: where the n-th gauge (1-based) goes: stacked down from the list's top-left, `size` apart plus `gap`.
-- Unit-tested.
function M.slotAt(listLeft, listTop, n, size, gap, up)
    local step = (n - 1) * (size + gap)
    return listLeft, up and listTop - step or listTop + step
end

-- Pure: each row's top, stacked from y0 with `gap` between, each heights[i] tall: down from y0, or (up) with the
-- first row's top at y0 and the rest above it. Unit-tested.
function M.stackTops(y0, heights, gap, up)
    local tops = {}
    if not up then
        local y = y0
        for i, h in ipairs(heights) do tops[i] = y; y = y + h + gap end
    else
        local bottom = y0 + (heights[1] or 0) -- the first row's bottom stays put; the rest climb above it
        for i, h in ipairs(heights) do
            tops[i] = bottom - h
            bottom = tops[i] - gap
        end
    end
    return tops
end

-- Pure: the game's rows stacked down its list from `top` (screen units), each sizes[i] = { w, h } in list units,
-- `scale` screen units per list unit: { { top, w, h } } in screen units. Unit-tested.
function M.rowTops(top, scale, sizes)
    local out, y = {}, top
    for i, s in ipairs(sizes) do
        out[i] = { top = y, w = s.w * scale, h = s.h * scale }
        y = y + s.h * scale
    end
    return out
end

-- Pure: the render translation (list units) that puts a row's middle - the row at listLeft / rowTop, w x h screen
-- units - on a gauge's center (cx, cy). Unit-tested.
function M.rowShift(cx, cy, listLeft, rowTop, w, h, scale)
    scale = (scale and scale > 0) and scale or 1
    return (cx - (listLeft + w / 2)) / scale, (cy - (rowTop + h / 2)) / scale
end

-- Pure: rows with a repeat of an earlier one's key left out (rows whose key is nil are all kept). Unit-tested.
function M.unique(rows, keyOf)
    local seen, out = {}, {}
    for _, r in ipairs(rows) do
        local k = keyOf(r)
        if k == nil or not seen[k] then
            if k ~= nil then seen[k] = true end
            out[#out + 1] = r
        end
    end
    return out
end

-- Pure: rect r grown to take in rect add (r may be nil). Unit-tested.
function M.grow(r, add)
    if not r then return { left = add.left, top = add.top, right = add.right, bottom = add.bottom } end
    return { left = math.min(r.left, add.left), top = math.min(r.top, add.top),
        right = math.max(r.right, add.right), bottom = math.max(r.bottom, add.bottom) }
end

-- Pure: the rows in the order chosen: "game" as listed, "timed" (ones that run out first) or "lasting" (on / off
-- ones first); the game's order kept within each kind. rows = { {timed = bool}, ... }. Unit-tested.
function M.ordered(rows, order)
    if order ~= "timed" and order ~= "lasting" then return rows end
    local first, second = {}, {}
    for _, r in ipairs(rows) do
        local isFirst = (r.timed == true) == (order == "timed")
        if isFirst then first[#first + 1] = r else second[#second + 1] = r end
    end
    for _, r in ipairs(second) do first[#first + 1] = r end
    return first
end

local function ensureHost()
    if host and W.valid(host.uw) then return true end
    local ok, h = pcall(overlay.host, "Status", 3) -- just above the game's HUD, under its menus
    if not ok then log.warn("status: no overlay: %s", tostring(h)) return false end
    host = h
    pool = {}
    pcall(function() host.uw:SetVisibility(3) end)
    return true
end

local function brushOf(tex, size)
    return { ResourceObject = tex, ImageSize = { X = size, Y = size }, DrawAs = 3, Tiling = 0, TintColor = WHITE }
end

local function place(img, x, y, size)
    pcall(function()
        img.Slot:SetPosition({ X = x, Y = y })
        img.Slot:SetSize({ X = size, Y = size })
    end)
end

local function newImage(name, z)
    made = made + 1
    local img = overlay.new("Image", host.tree, "FM_" .. name .. "_" .. made)
    local sl = host.canvas:AddChildToCanvas(img)
    sl:SetAutoSize(false)
    sl:SetZOrder(z)
    pcall(function() img:SetVisibility(3) end)
    return img
end

-- A survival gauge's fill texture (its InputTexture), which our fills need too.
local function fillTexture(src)
    local ok, t = pcall(function() return src:K2_GetTextureParameterValue(FName("InputTexture")) end)
    return ok and W.valid(t) and t or nil
end

local function slotN(n)
    local s = pool[n]
    if s and W.valid(s.icon) then return s end
    s = {
        badge = newImage("StatusBadge", 1),
        ring = newImage("StatusRing", 2),
        fill = newImage("StatusFill", 3),
        rim = newImage("StatusRim", 4),
        icon = newImage("StatusIcon", 5),
    }
    local bg = texture("T_Upkeep")
    if bg then pcall(function() s.ring:SetBrush(brushOf(bg, 64)) end) end
    -- the fill: a copy of a survival gauge's own fill (its texture and every setting come with it)
    local src = survivalFill()
    -- (made from the survival fill's own material, not from that live copy: a copy of a copy read back empty)
    local okPa, base = pcall(function() return src.Parent end)
    local parent = (okPa and W.valid(base) and base) or src or radialParent()
    if parent then
        local kml = StaticFindObject("/Script/Engine.Default__KismetMaterialLibrary")
        local ok, m = pcall(function() return kml:CreateDynamicMaterialInstance(host.uw, parent, FName("None"), 0) end)
        if ok and W.valid(m) then
            s.mid = m
            local tex = src and fillTexture(src)
            if tex then pcall(function() m:SetTextureParameterValue(FName("InputTexture"), tex) end) end
            pcall(function() s.fill:SetBrush(brushOf(m, 64)) end)
            -- (diagnostics, once: what the survival gauge's fill holds, and ours)
            if not loggedFill then
                loggedFill = true
                local function scalar(mm) local o, v = pcall(function() return mm:K2_GetScalarParameterValue(FName("FillBar")) end) return o and v end
                local okP, pn = pcall(function() return W.name(parent) end)
                log.info("status: fill made from %s (survival FillBar %s, texture %s); ours FillBar %s",
                    okP and pn or "?", tostring(src and scalar(src)), tostring(tex and W.name(tex)), tostring(scalar(m)))
            end
        end
    end
    s.themed = nil
    pool[n] = s
    return s
end

-- The theme's rim and icon ring on a slot (again after a theme change).
local function themeSlot(s, size, badgeSize)
    local t = ctx.themes.current()
    if s.themed == t then return end
    s.themed = t
    local art = ctx.features.art
    local rp, bp = ctx.themes.find("ui/gauge_rim.png"), ctx.themes.find("ui/badge_ring.png")
    local rt = art and rp and art.loadFile(rp, host.uw)
    local bt = art and bp and art.loadFile(bp, host.uw)
    if rt then art.guarded(function() s.rim:SetBrush(brushOf(rt, size)) end) end
    if bt then art.guarded(function() s.badge:SetBrush(brushOf(bt, badgeSize)) end) end
end

local function show(w, on) pcall(function() w:SetVisibility(on and 3 or 1) end) end

-- One game row read: { icon = texture, timed = bool, fill, color }.
local function readRow(row)
    local out = {}
    local icon = named(row, "ItemImage")
    pcall(function() out.icon = icon.Brush.ResourceObject end)
    local bar = named(row, "ProgressBarImage")
    pcall(function() out.timed = bar and W.valid(bar) and bar:GetVisibility() ~= 1 end)
    if out.timed then
        pcall(function()
            local m = bar.Brush.ResourceObject
            out.fill = m:K2_GetScalarParameterValue(FName("Fill"))
            local c = m:K2_GetVectorParameterValue(FName("Bar Color 1"))
            out.color = { R = c.R, G = c.G, B = c.B, A = 1 }
        end)
    end
    return out
end

local function tick()
    local S = ctx.settings.bars or {}
    if not ctx.enabled then return end
    if S.gaugeRims ~= false then
        pcall(rimGameGauges, S)
        pcall(rimShortcuts, S)
        pcall(colorWeightBar, S)

        pcall(retheme)
    end
    local want = S.statusGauges ~= false
    -- the list, and its rows in the order it shows them (the list makes its rows outside the widget tree, so
    -- they can't be measured: the gauges go where the list is)
    local rows, list, lv = {}, nil, nil
    for _, l in pairs(FindAllOf("WBP_HUD_EffectsDisplayLists_C") or {}) do
        if W.valid(l) and W.isInstance(l) then list = l break end
    end
    lv = list and named(list, "StatusEffectListView")
    -- the list's items, in its order, each with the row showing it (the list reuses rows: a row whose effect
    -- ended lingers among the displayed ones, which had drawn a stale second copy of another effect)
    local okI, items = pcall(function() return lv:GetListItems() end)
    if okI and items then
        local seen = {}
        for _, it in ipairs(items) do
            local okW, e = pcall(function() return lv:GetEntryWidgetFromItem(it) end)
            if okW and W.valid(e) and W.isVisible(e) then
                local full = W.fullName(e)
                if not seen[full] then seen[full] = true; rows[#rows + 1] = { w = e } end
            end
        end
    end
    if #rows == 0 then
        local okE, shown = pcall(function() return lv:GetDisplayedEntryWidgets() end)
        if okE and shown then
            for _, e in ipairs(shown) do
                local okC, cls = pcall(W.className, e)
                if W.valid(e) and okC and cls == M.ENTRY and W.isVisible(e) then rows[#rows + 1] = { w = e } end
            end
        end
    end
    if #rows == 0 then
        for _, e in pairs(FindAllOf(M.ENTRY) or {}) do
            if W.valid(e) and W.isInstance(e) and W.isVisible(e) then rows[#rows + 1] = { w = e } end
        end
    end
    local listShown = list and W.isVisible(list)
    if not want or #rows == 0 or not listShown then
        if host and W.valid(host.uw) then pcall(function() host.uw:SetVisibility(1) end) end
        if not want then
            for full, r in pairs(hiddenRows) do
                if W.valid(r) then pcall(function() r:SetRenderOpacity(1) end) end
                hiddenRows[full] = nil
            end
            for full, r in pairs(movedRows) do
                if W.valid(r) then pcall(function() r:SetRenderTranslation({ X = 0, Y = 0 }) end) end
                movedRows[full] = nil
            end
        end
        return
    end
    if not ensureHost() then return end
    pcall(function() host.uw:SetVisibility(3) end)
    local size = S.statusGaugeSize or 64
    local badgeSize = S.statusBadgeSize or size -- (on / off effects as big as the timed ones)
    local gap = S.statusGap or 4
    local lr = measure.rect(lv or list)
    if not lr then return end
    local x0, y0 = lr.left, lr.top
    for _, row in ipairs(rows) do row.d = readRow(row.w); row.timed = row.d.timed == true end
    -- where the game has each row (in its own order, stacked down the list): the rows stay invisible but still
    -- catch the mouse and show the effect's tooltip, so each is moved under its own gauge below
    local lay = measure.layoutRect(lv or list)
    if lv then pcall(function() if lv:GetClipping() ~= 0 then lv:SetClipping(0) end end) end -- (rows moved past it)
    local sc = (lay and lay.bottom - lay.top > 1) and (lr.bottom - lr.top) / (lay.bottom - lay.top) or 1
    local sizes = {}
    for i, row in ipairs(rows) do
        local okD, d = pcall(function() return row.w:GetDesiredSize() end)
        sizes[i] = { w = (okD and d and d.X and d.X > 0) and d.X or 24, h = (okD and d and d.Y and d.Y > 0) and d.Y or 24 }
    end
    for i, span in ipairs(M.rowTops(lr.top, sc, sizes)) do
        rows[i].natTop, rows[i].natH, rows[i].natW = span.top, span.h, span.w
    end
    rows = M.ordered(rows, S.statusOrder or "timed")
    local up = S.statusGrow == "up"
    -- each row as tall as what it shows (a gauge, or the smaller icon ring), stacked with the gap between
    -- one gauge per effect: the list reuses its rows, and a row left over from an ended effect can still show the
    -- picture of one that has its own row (two Sheltered)
    rows = M.unique(rows, function(row)
        local okN, n = pcall(function() return W.name(row.d.icon) end)
        return okN and n or nil
    end)
    local heights = {}
    for i, row in ipairs(rows) do heights[i] = row.timed and size or badgeSize end
    local bounds
    local tops = M.stackTops(y0, heights, gap, up)
    for n, row in ipairs(rows) do
        -- the game's row: its pictures invisible (it's still updated by the game, and read here); the row itself
        -- stays, so the editor still sees the list as an element with its title bar
        for _, part in ipairs({ "ItemImage", "Overlay_0" }) do
            local p = named(row.w, part)
            if p then
                pcall(function() if p:GetRenderOpacity() ~= 0 then p:SetRenderOpacity(0) end end)
                hiddenRows[W.fullName(p)] = p
            end
        end
        local d = row.d
        local s = slotN(n)
        themeSlot(s, size, badgeSize)
        local x = x0
        local cx, cy = x0 + size / 2, tops[n] + heights[n] / 2 -- (rings centered on the gauges' column)
        local y = cy - size / 2
        -- the game's row (invisible) moved under this gauge, so hovering the gauge shows this effect's tooltip
        if row.natTop then
            local tx, ty = M.rowShift(cx, cy, lr.left, row.natTop, row.natW, row.natH, sc)
            pcall(function() row.w:SetRenderTranslation({ X = tx, Y = ty }) end)
            movedRows[W.fullName(row.w)] = row.w
        end
        bounds = M.grow(bounds, { left = x, top = tops[n], right = x + size, bottom = tops[n] + heights[n] })
        place(s.ring, x, y, size)
        place(s.fill, x, y, size)
        place(s.rim, x, y, size)
        place(s.badge, cx - badgeSize / 2, cy - badgeSize / 2, badgeSize)
        -- the icon sized to what it sits in: a gauge's middle, or the inside of its icon ring
        local iconSize = row.timed and size * (S.statusIconScale or 0.55) or badgeSize * (S.statusBadgeIconScale or 0.6)
        place(s.icon, cx - iconSize / 2, cy - iconSize / 2, iconSize)
        if not d.icon then show(s.icon, false) end
        if d.icon and s.lastIcon ~= d.icon then
            s.lastIcon = d.icon
            pcall(function() s.icon:SetBrush(brushOf(d.icon, iconSize)) end)
        end
        local timed = d.timed == true
        show(s.ring, timed)
        show(s.fill, timed and s.mid ~= nil)
        show(s.rim, timed and S.gaugeRims ~= false)
        show(s.badge, not timed)
        show(s.icon, d.icon ~= nil)
        if timed and s.mid then
            local f = M.ringFill(true, d.fill)
            if s.lastFill ~= f then
                s.lastFill = f
                -- (the survival gauges' material fills in reverse: its FillBar is how much is used up)
                pcall(function() s.mid:SetScalarParameterValue(FName("FillBar"), 1 - f) end)
            end
            if d.color then pcall(function() s.fill:SetColorAndOpacity(d.color) end) end
            -- (diagnostics: once per effect shown in this slot)
            local okIN, iconName = pcall(function() return W.name(d.icon) end)
            iconName = okIN and iconName or "?"
            if s.loggedIcon ~= iconName then
                s.loggedIcon = iconName
                local okB, back = pcall(function() return s.mid:K2_GetScalarParameterValue(FName("FillBar")) end)
                local c = d.color or {}
                log.info("status: slot %d timed fill %s color %.2f,%.2f,%.2f; ours FillBar %s, fill shown %s",
                    n, tostring(d.fill), c.R or -1, c.G or -1, c.B or -1, tostring(okB and back), tostring(W.isVisible(s.fill)))
            end
        end
    end
    -- the editor frames the gauges where they're drawn (not the game's list, which grows the other way)
    if bounds then
        local units = require("framemage.editor.units")
        for _, w in ipairs({ list, lv }) do
            if w and W.valid(w) then pcall(units.setDrawn, W.fullName(w), bounds) end
        end
    end
    -- slots no longer needed: out of sight
    for n = #rows + 1, #pool do
        local s = pool[n]
        if s then for _, k in ipairs({ "badge", "ring", "fill", "rim", "icon" }) do show(s[k], false) end end
    end
end

function M.init(c)
    ctx, W, log = c, c.widgets, c.log
    c.events.on("worldchanged", function() done, radial, rims, rimTheme, host, pool, hiddenRows = {}, nil, {}, nil, nil, {}, {} end)
    -- art reloaded (Ctrl+F10) or a new theme: the rims and icon rings are drawn again from the fresh files
    local function again()
        rimTheme = nil
        for _, s in pairs(pool) do s.themed = nil end
    end
    c.events.on("stylechanged", again)
    c.events.on("stylechanged", function() stoneOn, weightThemed = {}, {} end)
    c.events.on("worldchanged", function() weightFrames, weightThemed, movedRows = {}, {}, {} end)
    -- the weight bar's trough follows the bar every frame: a slower check left it showing a moment after the game
    -- hid the bar (a flash as the inventory closed)
    c.sched.every(16, "status.weightTrough", function() pcall(syncWeightFrames) end)
    c.events.on("themechanged", function() weightThemed = {} end)
    local okH, errH = pcall(RegisterHook, "/Script/Dominion.WeightBarBase:UpdateInfo", function() end,
        function(_, carrying, limit)
            local okV, cw, lim = pcall(function() return carrying:get(), limit:get() end)
            if okV and type(cw) == "number" and type(lim) == "number" and lim > 0 then weightRatio = cw / lim end
        end)
    if not okH then log.info("status: no weight hook (%s); the load gauge uses its own fill", tostring(errH)) end
    c.events.on("themechanged", again)
    c.sched.every(150, "status.gauges", function()
        local ok, err = pcall(tick)
        if not ok then log.debug("status: %s", tostring(err)) end
    end)
end

return M
