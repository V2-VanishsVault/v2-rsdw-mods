-- Where a widget is on screen, worked out from its layout data, in viewport units (the units of a full-screen
-- CanvasPanel and of the viewport mouse position).
--
-- Why not ask Unreal? Its answer is an FGeometry, and FGeometry has no script-visible fields: through UE4SS it
-- arrives as an empty table, and handing that back to SlateBlueprintLibrary measures nothing. So the layout is
-- recomputed here from what IS visible to scripts: each slot's anchors / offsets / alignment / padding / size
-- rules, each widget's desired size (from the last layout pass), and render transforms (translation and scale;
-- rotation and shear are ignored). It's the same arithmetic Slate does for the common panels (canvas, overlay,
-- vertical / horizontal box, border, size box, grids, wrap box); anything unusual is treated as filling its parent.
local M = {}

-- Pure layout -------------------------------------------------------------------------------------------------
-- Rects are { left, top, right, bottom }. Alignment enums: 0 Fill, 1 Left/Top, 2 Center, 3 Right/Bottom.

local function rect(l, t, w, h) return { left = l, top = t, right = l + w, bottom = t + h } end
M.makeRect = rect

local function width(r) return r.right - r.left end
local function height(r) return r.bottom - r.top end

local function align1(start, avail, size, a)
    if a == 0 then return start, avail end
    if a == 2 then return start + (avail - size) / 2, size end
    if a == 3 then return start + avail - size, size end
    return start, size
end

-- A slot with padding and alignment inside parent rect P (overlay, border, size box, button, switcher...).
function M.aligned(P, pad, h, v, dw, dh)
    pad = pad or { Left = 0, Top = 0, Right = 0, Bottom = 0 }
    local ax, aw = P.left + pad.Left, width(P) - pad.Left - pad.Right
    local ay, ah = P.top + pad.Top, height(P) - pad.Top - pad.Bottom
    local x, w = align1(ax, aw, dw, h or 0)
    local y, hh = align1(ay, ah, dh, v or 0)
    return rect(x, y, w, hh)
end

-- A canvas panel slot. ld = { Offsets = margin, Anchors = { Minimum = {X,Y}, Maximum = {X,Y} }, Alignment = {X,Y} }
function M.canvas(P, ld, autoSize, dw, dh)
    local W, H = width(P), height(P)
    local o, a, al = ld.Offsets, ld.Anchors, ld.Alignment
    local function axis(min, max, off1, off2, alignment, desired, size, origin)
        if max ~= min then -- stretched between anchors
            local s = origin + min * size + off1
            return s, origin + max * size - off2 - s
        end
        local w = autoSize and desired or off2
        return origin + min * size + off1 - alignment * w, w
    end
    local x, w = axis(a.Minimum.X, a.Maximum.X, o.Left, o.Right, al.X, dw, W, P.left)
    local y, h = axis(a.Minimum.Y, a.Maximum.Y, o.Top, o.Bottom, al.Y, dh, H, P.top)
    return rect(x, y, w, h)
end

-- A vertical (vertical = true) or horizontal box. items[i] = { collapsed, fill (bool), value, pad, h, v, dw, dh }
function M.box(P, items, index, vertical)
    local main = vertical and height(P) or width(P)
    local used, fillTotal = 0, 0
    for _, it in ipairs(items) do
        if not it.collapsed then
            local p = it.pad
            used = used + (vertical and (p.Top + p.Bottom) or (p.Left + p.Right))
            if it.fill then fillTotal = fillTotal + (it.value > 0 and it.value or 1)
            else used = used + (vertical and it.dh or it.dw) end
        end
    end
    local free = math.max(0, main - used)
    local pos = vertical and P.top or P.left
    for i, it in ipairs(items) do
        if not it.collapsed then
            local p = it.pad
            local lead = vertical and p.Top or p.Left
            local trail = vertical and p.Bottom or p.Right
            local size
            if it.fill then size = free * (it.value > 0 and it.value or 1) / math.max(fillTotal, 1e-6)
            else size = vertical and it.dh or it.dw end
            if i == index then
                if vertical then
                    local x, w = align1(P.left + p.Left, width(P) - p.Left - p.Right, it.dw, it.h)
                    local y, h = align1(pos + lead, size, it.dh, it.fill and 0 or it.v)
                    return rect(x, y, w, h)
                else
                    local y, h = align1(P.top + p.Top, height(P) - p.Top - p.Bottom, it.dh, it.v)
                    local x, w = align1(pos + lead, size, it.dw, it.fill and 0 or it.h)
                    return rect(x, y, w, h)
                end
            end
            pos = pos + lead + size + trail
        elseif i == index then
            return vertical and rect(P.left, pos, 0, 0) or rect(pos, P.top, 0, 0)
        end
    end
    return P
end

-- A uniform grid: equal cells. items[i] = { row, col, h, v, dw, dh }
function M.uniformGrid(P, items, index)
    local rows, cols = 1, 1
    for _, it in ipairs(items) do rows = math.max(rows, it.row + 1); cols = math.max(cols, it.col + 1) end
    local it = items[index]
    local cw, ch = width(P) / cols, height(P) / rows
    return M.aligned(rect(P.left + it.col * cw, P.top + it.row * ch, cw, ch), nil, it.h, it.v, it.dw, it.dh)
end

-- A grid: each column as wide as its widest piece, each row as tall as its tallest. items[i] adds pad, nudge.
function M.grid(P, items, index)
    local colW, rowH = {}, {}
    for _, it in ipairs(items) do
        if not it.collapsed then
            colW[it.col] = math.max(colW[it.col] or 0, it.dw + it.pad.Left + it.pad.Right)
            rowH[it.row] = math.max(rowH[it.row] or 0, it.dh + it.pad.Top + it.pad.Bottom)
        end
    end
    local it = items[index]
    local x, y = P.left, P.top
    for c = 0, it.col - 1 do x = x + (colW[c] or 0) end
    for r = 0, it.row - 1 do y = y + (rowH[r] or 0) end
    local cell = rect(x + (it.nudge and it.nudge.X or 0), y + (it.nudge and it.nudge.Y or 0), colW[it.col] or it.dw, rowH[it.row] or it.dh)
    return M.aligned(cell, it.pad, it.h, it.v, it.dw, it.dh)
end

-- A wrap box: left to right, wrapping at the parent's width. items[i] = { collapsed, pad, dw, dh }
function M.wrap(P, items, index)
    local x, y, lineH = P.left, P.top, 0
    for i, it in ipairs(items) do
        if not it.collapsed then
            local w = it.dw + it.pad.Left + it.pad.Right
            local h = it.dh + it.pad.Top + it.pad.Bottom
            if x > P.left and x + w > P.right then x, y, lineH = P.left, y + lineH, 0 end
            if i == index then return rect(x + it.pad.Left, y + it.pad.Top, it.dw, it.dh) end
            x, lineH = x + w, math.max(lineH, h)
        end
    end
    return rect(P.left, P.top, items[index].dw, items[index].dh)
end

-- Affine (axis-aligned scale + offset): screen = s * p + b.
M.IDENTITY = { sx = 1, sy = 1, bx = 0, by = 0 }

function M.compose(A, B) -- A after B
    return { sx = A.sx * B.sx, sy = A.sy * B.sy, bx = A.sx * B.bx + A.bx, by = A.sy * B.by + A.by }
end

-- A widget's render transform (translation, scale about its pivot) for layout rect L.
function M.renderAffine(L, t, pivot)
    if not t then return M.IDENTITY end
    local sx, sy = t.Scale and t.Scale.X or 1, t.Scale and t.Scale.Y or 1
    local tx, ty = t.Translation and t.Translation.X or 0, t.Translation and t.Translation.Y or 0
    local px, py = pivot and pivot.X or 0.5, pivot and pivot.Y or 0.5
    local cx, cy = L.left + px * width(L), L.top + py * height(L)
    return { sx = sx, sy = sy, bx = cx - sx * cx + tx, by = cy - sy * cy + ty }
end

function M.apply(T, r)
    local x1, x2 = T.sx * r.left + T.bx, T.sx * r.right + T.bx
    local y1, y2 = T.sy * r.top + T.by, T.sy * r.bottom + T.by
    return { left = math.min(x1, x2), top = math.min(y1, y2), right = math.max(x1, x2), bottom = math.max(y1, y2),
        accScale = T.sx }
end

-- Live widgets ------------------------------------------------------------------------------------------------

local W -- core.widgets (set in init)
local viewport -- function() -> width, height in viewport units

local memo, memoAt = {}, -1
local MEMO_LIFE = 0.03 -- one pass (a frame or so): layouts don't change within it

local function idOf(o)
    local ok, a = pcall(function() return o:GetAddress() end)
    if ok and a then return a end
    local okF, f = pcall(function() return o:GetFullName() end)
    return okF and f or tostring(o)
end

local function vec(v, dx, dy)
    local ok, x, y = pcall(function() return v.X, v.Y end)
    if ok and type(x) == "number" then return { X = x, Y = y } end
    return { X = dx, Y = dy }
end

local function margin(m)
    local ok, r = pcall(function() return { Left = m.Left, Top = m.Top, Right = m.Right, Bottom = m.Bottom } end)
    if ok and type(r.Left) == "number" then return r end
    return { Left = 0, Top = 0, Right = 0, Bottom = 0 }
end

local function field(o, name)
    local ok, v = pcall(function() return o[name] end)
    if ok then return v end
    return nil
end

local function desired(w)
    local ok, d = pcall(function() return w:GetDesiredSize() end)
    if ok and d then
        local v = vec(d, 0, 0)
        return v.X, v.Y
    end
    return 0, 0
end

local function collapsedW(w)
    local v = field(w, "Visibility")
    return v == 1
end

local function slotOf(w)
    local s = field(w, "Slot")
    if s and W.valid(s) then return s end
    return nil
end

local function siblings(parent)
    local out = {}
    local ok, n = pcall(function() return parent:GetChildrenCount() end)
    if not ok or type(n) ~= "number" then return out end
    for i = 0, n - 1 do
        local okC, c = pcall(function() return parent:GetChildAt(i) end)
        if okC and W.valid(c) then out[#out + 1] = c end
    end
    return out
end

local function hv(slot)
    local h = field(slot, "HorizontalAlignment")
    if type(h) ~= "number" then h = field(slot, "HAlign") end
    local v = field(slot, "VerticalAlignment")
    if type(v) ~= "number" then v = field(slot, "VAlign") end
    return type(h) == "number" and h or 0, type(v) == "number" and v or 0
end

local function itemFor(c)
    local s = slotOf(c)
    local dw, dh = desired(c)
    local it = { collapsed = collapsedW(c), dw = dw, dh = dh, pad = { Left = 0, Top = 0, Right = 0, Bottom = 0 },
        h = 0, v = 0, fill = false, value = 1, row = 0, col = 0 }
    if s then
        local p = field(s, "Padding")
        if p then it.pad = margin(p) end
        it.h, it.v = hv(s)
        local size = field(s, "Size")
        if size then
            local okS, rule, val = pcall(function() return size.SizeRule, size.Value end)
            if okS then it.fill = rule == 1; it.value = type(val) == "number" and val or 1 end
        end
        local r, cIdx = field(s, "Row"), field(s, "Column")
        if type(r) == "number" then it.row = r end
        if type(cIdx) == "number" then it.col = cIdx end
        local nudge = field(s, "Nudge")
        if nudge then it.nudge = vec(nudge, 0, 0) end
    end
    return it
end

-- Child c's layout rect inside parent's layout rect P (same coordinate frame).
local function layoutIn(parent, c, P)
    local s = slotOf(c)
    if not s then return P end -- a user widget's root widget fills it
    local okC, cls = pcall(function() return W.className(s) end)
    cls = okC and cls or ""
    local dw, dh = desired(c)
    if cls == "CanvasPanelSlot" then
        local ok, ld = pcall(function()
            local l = s.LayoutData
            return {
                Offsets = margin(l.Offsets),
                Anchors = { Minimum = vec(l.Anchors.Minimum, 0, 0), Maximum = vec(l.Anchors.Maximum, 0, 0) },
                Alignment = vec(l.Alignment, 0, 0),
            }
        end)
        if not ok then return P end
        return M.canvas(P, ld, field(s, "bAutoSize") == true, dw, dh)
    end
    local vertical
    if cls == "VerticalBoxSlot" then vertical = true
    elseif cls == "HorizontalBoxSlot" then vertical = false
    elseif cls == "StackBoxSlot" or cls == "ScrollBoxSlot" then
        local o = field(parent, "Orientation")
        vertical = o ~= 0 -- EOrientation: 0 horizontal, 1 vertical
    end
    if vertical ~= nil or cls == "UniformGridSlot" or cls == "GridSlot" or cls == "WrapBoxSlot" then
        local sib, items, index = siblings(parent), {}, nil
        local me = idOf(c)
        for i, x in ipairs(sib) do
            items[i] = itemFor(x)
            if not index and idOf(x) == me then index = i end
        end
        if not index then return P end
        if vertical ~= nil then return M.box(P, items, index, vertical) end
        if cls == "UniformGridSlot" then return M.uniformGrid(P, items, index) end
        if cls == "GridSlot" then return M.grid(P, items, index) end
        return M.wrap(P, items, index)
    end
    -- overlay, border, size box, button, scale box, safe zone, switcher, named slot ...: padding + alignment
    local p = field(s, "Padding")
    local h, v = hv(s)
    return M.aligned(P, p and margin(p) or nil, h, v, dw, dh)
end

-- { L = layout rect, T = affine to the screen (including the widget's own render transform) }
local function frameOf(w, depth)
    local id = idOf(w)
    local hit = memo[id]
    if hit then return hit end
    local parent = W.parent(w)
    local L, PT
    if not parent or depth > 40 then
        local vw, vh = viewport()
        L, PT = rect(0, 0, vw or 1920, vh or 1080), M.IDENTITY
    else
        local pf = frameOf(parent, depth + 1)
        L, PT = layoutIn(parent, w, pf.L), pf.T
    end
    local rt = field(w, "RenderTransform")
    local t
    if rt then
        local ok, v = pcall(function() return { Translation = vec(rt.Translation, 0, 0), Scale = vec(rt.Scale, 1, 1) } end)
        if ok then t = v end
    end
    local pivot = field(w, "RenderTransformPivot")
    local f = { L = L, T = M.compose(PT, M.renderAffine(L, t, pivot and vec(pivot, 0.5, 0.5) or nil)) }
    memo[id] = f
    return f
end

-- { left, top, right, bottom, accScale } in viewport units, or nil.
function M.rect(w)
    if not (W and w and W.valid(w)) then return nil end
    local now = os.clock()
    if now - memoAt > MEMO_LIFE then memo, memoAt = {}, now end
    local ok, f = pcall(frameOf, w, 0)
    if not ok or not f then return nil end
    return M.apply(f.T, f.L)
end

-- The widget's layout box ({ left, top, right, bottom }) before any render transforms (anyone's offsets, scales),
-- in its root's layout space; or nil. Two widgets with no scaling panel between them can be compared directly.
function M.layoutRect(w)
    if not (W and w and W.valid(w)) then return nil end
    local now = os.clock()
    if now - memoAt > MEMO_LIFE then memo, memoAt = {}, now end
    local ok, f = pcall(frameOf, w, 0)
    if not ok or not f then return nil end
    return f.L
end

-- The affine that takes a widget's layout box to the screen (its parents' layouts and render transforms and its own):
-- { sx, sy, bx, by }, or nil. A child's natural place on screen (before its own render transform) is its parent's
-- transform applied to the child's layoutRect.
function M.transform(w)
    if not (W and w and W.valid(w)) then return nil end
    local now = os.clock()
    if now - memoAt > MEMO_LIFE then memo, memoAt = {}, now end
    local ok, f = pcall(frameOf, w, 0)
    if not ok or not f then return nil end
    return f.T
end

-- Something moved (a drag, an edit): measure afresh.
function M.invalidate() memo, memoAt = {}, -1 end

function M.init(widgets, viewportFn) W, viewport = widgets, viewportFn end

return M
