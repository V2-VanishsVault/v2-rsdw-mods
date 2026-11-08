-- The hidden-elements panel (H in the editor): every part of the HUD that isn't showing right now (closed
-- panels, things the game only shows in certain situations, things you hid), as a list you click through.
--
-- Click a name: that element is shown (previewed) and selected, so you can drag its bar, nudge, scale or fade it.
-- Click another: the first goes back to hidden and the new one shows. Click the shown one again: hidden again.
-- SAVE closes the panel and saves the layout. The mouse wheel (over the list) or the arrows scroll it. The gold
-- title bar drags the panel out of the way.
--
-- The editor owns selecting and previewing (editor.select); this module only draws the list and reports clicks.
local overlay = require("framemage.core.overlay")
local W = require("framemage.core.widgets")
local geometry = require("framemage.core.geometry")
local style = require("framemage.editor.style")
local themes = require("framemage.core.themes")

local M = {}

local ctx, S, log
local host -- { uw, canvas, slot, root, plate, rows = { {border, text} }, count, save, up, down, x, y }
local entries = {} -- { {widget, title} }
local offset = 0 -- first entry shown
local current -- index into entries of the element being shown, or nil
local drag -- { x0, y0, px, py, moved }
local onPick, onSave -- callbacks from the editor
local open = false

-- Pure -----------------------------------------------------------------------------------------------------

-- Pure: keep the scroll offset within the list. Unit-tested.
function M.clampOffset(offsetIn, count, rows)
    return math.max(0, math.min(offsetIn, math.max(0, count - rows)))
end

-- Pure: names made unique, in order: a second "Quest Tracker" becomes "Quest Tracker (2)". Unit-tested.
function M.uniqueTitles(titles)
    local seen, out = {}, {}
    for i, t in ipairs(titles) do
        seen[t] = (seen[t] or 0) + 1
        out[i] = seen[t] > 1 and (t .. " (" .. seen[t] .. ")") or t
    end
    return out
end

-- Pure: the footer's "1-14 of 87". Unit-tested.
function M.rangeText(offsetIn, count, rows)
    if count == 0 then return "Nothing hidden right now" end
    return string.format("%d-%d of %d", offsetIn + 1, math.min(offsetIn + rows, count), count)
end

-- Widgets --------------------------------------------------------------------------------------------------


local GOLD_TEXT, LABEL, INK -- theme colours, read at build

local function build()
    GOLD_TEXT, LABEL, INK = style.heading(), style.label(), style.ink()
    local h = overlay.host("Hidden", 19997)
    local font = require("framemage.editor.legend").gameFont()
    local art = ctx.features.art
    local n = 0
    local function new(cls)
        n = n + 1
        return overlay.new(cls, h.tree, "FM_Hidden_" .. cls .. "_" .. h.suffix .. "_" .. n)
    end
    local function text(str, size, color)
        local t = new("TextBlock")
        t:SetText(FText(str))
        if font then
            pcall(function() t:SetFont({ FontObject = font.FontObject, TypefaceFontName = font.TypefaceFontName, Size = size }) end)
        end
        t:SetColorAndOpacity({ SpecifiedColor = color, ColorUseRule = 0 })
        return t
    end
    local GOLD = themes.color("gold")

    local width = new("SizeBox")
    width:SetWidthOverride(S.hiddenWidth)
    local root = new("VerticalBox")
    width:SetContent(root)

    -- title bar
    local plate = new("Border")
    style.titlePlate(plate, h.uw)
    plate:SetPadding({ Left = 14, Top = 6, Right = 14, Bottom = 6 })
    plate:SetContent(text("HIDDEN ELEMENTS", S.legendHeadingSize, INK))
    root:AddChildToVerticalBox(plate)

    -- body: a fixed number of rows (the list scrolls through them)
    local column = new("VerticalBox")
    local back = style.panel(new, column, h.uw)
    root:AddChildToVerticalBox(back)

    local hint = text("Click one to show it", S.legendSectionSize, GOLD_TEXT)
    local hs = column:AddChildToVerticalBox(hint)
    hs:SetPadding({ Left = 6, Top = 0, Right = 0, Bottom = 4 })

    local rows = {}
    for i = 1, S.hiddenRows do
        local b = new("Border")
        b:SetBrushColor({ R = 0, G = 0, B = 0, A = 0 })
        b:SetPadding({ Left = 6, Top = 2, Right = 6, Bottom = 2 })
        local clip = new("SizeBox")
        pcall(function() clip:SetClipping(1) end) -- long names are cut, not wrapped
        local t = text("", S.legendLabelSize, LABEL)
        clip:SetContent(t)
        b:SetContent(clip)
        column:AddChildToVerticalBox(b)
        rows[i] = { border = b, text = t }
    end

    -- footer: scroll arrows, the range, SAVE
    local footer = new("HorizontalBox")
    local fs = column:AddChildToVerticalBox(footer)
    fs:SetPadding({ Left = 0, Top = 8, Right = 0, Bottom = 0 })
    local function arrow(up)
        local box = new("SizeBox")
        box:SetWidthOverride(22)
        box:SetHeightOverride(22)
        local b = new("Border")
        b:SetBrushColor({ R = 0.16, G = 0.15, B = 0.13, A = 1 })
        b:SetPadding({ Left = 4, Top = 4, Right = 4, Bottom = 4 })
        local img = new("Image")
        local tex = art and art.loadFile(ctx.dir .. "Art/_ui/fm_chevron.png", h.uw)
        if tex then img:SetBrushFromTexture(tex, false) end
        img:SetColorAndOpacity(GOLD)
        pcall(function() img:SetRenderTransformPivot({ X = 0.5, Y = 0.5 }) end)
        if up then pcall(function() img:SetRenderTransformAngle(180) end) end
        b:SetContent(img)
        box:SetContent(b)
        local s = footer:AddChildToHorizontalBox(box)
        s:SetVerticalAlignment(2)
        s:SetPadding({ Left = 2, Top = 0, Right = 2, Bottom = 0 })
        return b
    end
    local up = arrow(true)
    local down = arrow(false)
    local count = text("", S.legendSectionSize, LABEL)
    local cs = footer:AddChildToHorizontalBox(count)
    cs:SetVerticalAlignment(2)
    cs:SetPadding({ Left = 8, Top = 0, Right = 8, Bottom = 0 })
    pcall(function() cs:SetSize({ SizeRule = 1, Value = 1 }) end) -- fill: pushes SAVE to the right
    local save = new("Border")
    style.titlePlate(save, h.uw)
    save:SetPadding({ Left = 16, Top = 5, Right = 16, Bottom = 5 })
    save:SetContent(text("SAVE", S.legendHeadingSize, INK))
    local ss = footer:AddChildToHorizontalBox(save)
    ss:SetVerticalAlignment(2)

    local slot = h.canvas:AddChildToCanvas(width)
    slot:SetAutoSize(true)
    slot:SetAnchors({ Minimum = { X = 0, Y = 0 }, Maximum = { X = 0, Y = 0 } })
    slot:SetAlignment({ X = 0, Y = 0 })
    host = { uw = h.uw, canvas = h.canvas, slot = slot, root = width, plate = plate, rows = rows, count = count,
        save = save, up = up, down = down, back = back }
end

-- Fill the rows from entries + offset, highlighting the one being shown.
local function paint()
    if not (host and W.valid(host.uw)) then return end
    local tc = themes.style().gold
    for i, row in ipairs(host.rows) do
        local e = entries[offset + i]
        pcall(function()
            if e then
                row.text:SetText(FText(e.title))
                row.border:SetVisibility(3)
                local on = (offset + i) == current
                row.border:SetBrushColor(on and { R = tc[1], G = tc[2], B = tc[3], A = 0.9 } or { R = 0, G = 0, B = 0, A = 0 })
                row.text:SetColorAndOpacity({ SpecifiedColor = on and INK or LABEL, ColorUseRule = 0 })
            else
                row.border:SetVisibility(2) -- keeps its space so the panel doesn't change size
            end
        end)
    end
    pcall(function() host.count:SetText(FText(M.rangeText(offset, #entries, S.hiddenRows))) end)
end

local function place()
    if not host.x then
        local sw = geometry.screen() or 1920
        host.x = sw - S.hiddenWidth - S.legendMargin
        host.y = S.legendDefaultTop
    end
    pcall(function() host.slot:SetPosition({ X = host.x, Y = host.y }) end)
end

-- Open with entries = { {widget, title} } (titles made unique here).
function M.open(list)
    if not (host and W.valid(host.uw)) then
        local ok, err = pcall(build)
        if not ok then log.warn("hidden-elements panel unavailable: %s", tostring(err)); host = nil; return false end
    end
    local titles = {}
    for i, e in ipairs(list) do titles[i] = e.title end
    titles = M.uniqueTitles(titles)
    entries = {}
    for i, e in ipairs(list) do entries[i] = { widget = e.widget, title = titles[i] } end
    offset, current, drag = 0, nil, nil
    place()
    paint()
    pcall(function() host.uw:SetVisibility(3) end)
    open = true
    return true
end

function M.close()
    open = false
    drag = nil
    current = nil
    if host and W.valid(host.uw) then pcall(function() host.uw:SetVisibility(1) end) end
end

function M.isOpen() return open end

-- The editor deselected (or selected something else): drop the highlight.
function M.clearCurrent()
    if current then current = nil; paint() end
end

function M.scroll(rowsBy)
    if not open then return end
    local o = M.clampOffset(offset + rowsBy, #entries, S.hiddenRows)
    if o ~= offset then offset = o; paint() end
end

local function inside(w, x, y)
    local r = w and geometry.rect(w)
    return r ~= nil and geometry.contains(r, x, y)
end

-- A press: true = the panel took it.
function M.onDown(x, y)
    if not (open and host and W.valid(host.uw)) then return false end
    if inside(host.plate, x, y) then
        drag = { x0 = x, y0 = y, px = host.x, py = host.y, moved = false }
        return true
    end
    if not inside(host.root, x, y) then return false end
    if inside(host.save, x, y) then
        if onSave then onSave() end
        return true
    end
    if inside(host.up, x, y) then M.scroll(-S.hiddenRows + 1) return true end
    if inside(host.down, x, y) then M.scroll(S.hiddenRows - 1) return true end
    for i, row in ipairs(host.rows) do
        local idx = offset + i
        if entries[idx] and inside(row.border, x, y) then
            if current == idx then
                current = nil
                paint()
                if onPick then onPick(nil) end -- clicked the shown one again: hide it
            else
                current = idx
                paint()
                if W.valid(entries[idx].widget) then
                    if onPick then onPick(entries[idx].widget) end
                else
                    log.debug("hidden panel: %s is gone", entries[idx].title)
                end
            end
            return true
        end
    end
    return true -- anywhere else on the panel: swallowed
end

function M.onUp()
    if not drag then return false end
    drag = nil
    return true
end

function M.isDragging() return drag ~= nil end

function M.dragTick(x, y)
    if not (drag and x and host and W.valid(host.uw)) then return end
    local dx, dy = x - drag.x0, y - drag.y0
    if math.abs(dx) + math.abs(dy) > 3 then drag.moved = true end
    if not drag.moved then return end
    local sw, sh = geometry.screen()
    host.x = math.max(0, math.min(drag.px + dx, (sw or 1920) - 80))
    host.y = math.max(0, math.min(drag.py + dy, (sh or 1080) - 28))
    pcall(function() host.slot:SetPosition({ X = host.x, Y = host.y }) end)
end

-- The wheel over the panel scrolls it. true = taken.
function M.onWheel(x, y, delta)
    if not (open and host and inside(host.root, x, y)) then return false end
    M.scroll(delta > 0 and -3 or 3)
    return true
end

function M.forget() host = nil; entries = {}; open = false; drag = nil; current = nil end

-- Theme changed: drop the panel; the next open builds it in the new style.
function M.restyle()
    if host and W.valid(host.uw) then pcall(function() host.uw:RemoveFromParent() end) end
    M.forget()
end

function M.init(c, settings, pick, save)
    ctx, S, log = c, settings, c.log
    onPick, onSave = pick, save
end

return M
