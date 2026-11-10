-- The Settings panel (F4 while the editor is open): every Frame Mage setting, in tabs, drawn in the theme.
-- (It replaces the Mod Menu page; the rows come from core/options.lua.)
--
--   toggles flip with a click; choices and numbers step with the arrows either side of their value (click the
--   left half for back, the right half for forward); a key row waits for the next key press (Escape cancels);
--   buttons do their thing. The wheel scrolls a long tab; the gold title bar drags the panel.
local overlay = require("framemage.core.overlay")
local W = require("framemage.core.widgets")
local geometry = require("framemage.core.geometry")
local options = require("framemage.core.options")
local style = require("framemage.editor.style")
local themes = require("framemage.core.themes")

local M = {}

local ctx, S, log
local host -- { uw, slot, root, plate, tabs = { {border, text, id} }, rows = { {border, label, value, back, fwd} }, close, up, down, tip, x, y }
local tab = "look"
local offset = 0
local open = false
local drag
local capturing -- the row waiting for a key
local armed -- { row, at }: a confirm button clicked once, waiting for the second click
local onClose

local ROWS = 12

local function setting(row) return row.setting and options.getPath(ctx.settings, row.setting) end

local function build()
    local h = overlay.host("Settings", 19998)
    local font = require("framemage.editor.legend").gameFont()
    local n = 0
    local function new(cls)
        n = n + 1
        return overlay.new(cls, h.tree, "FM_Settings_" .. cls .. "_" .. h.suffix .. "_" .. n)
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
    local INK, LABEL, HEAD, DIM = style.ink(), style.label(), style.heading(), style.dim()

    local width = new("SizeBox")
    width:SetWidthOverride(S.settingsWidth)
    local root = new("VerticalBox")
    width:SetContent(root)

    -- title bar
    local plate = new("Border")
    style.titlePlate(plate, h.uw)
    plate:SetPadding({ Left = 14, Top = 6, Right = 14, Bottom = 6 })
    plate:SetContent(text("FRAME MAGE SETTINGS", S.legendHeadingSize, INK))
    root:AddChildToVerticalBox(plate)

    local column = new("VerticalBox")
    root:AddChildToVerticalBox(style.panel(new, column, h.uw))

    -- tabs
    local tabRow = new("HorizontalBox")
    local tabs = {}
    -- each tab a button in the theme's button border (the rim drawn over the game's buttons), dark glass inside;
    -- the selected one's rim brighter and its glass tinted with the theme's highlight (see paint)
    for _, t in ipairs(options.TABS) do
        local b = new("Border")                     -- the rim
        b:SetPadding({ Left = 3, Top = 3, Right = 3, Bottom = 3 })
        local fill = new("Border")                  -- the glass inside it
        fill:SetPadding({ Left = 5, Top = 2, Right = 5, Bottom = 2 })
        local label = text(t.label, S.legendSectionSize + 1, LABEL)
        fill:SetContent(style.buttonContent(new, label, h.uw))
        b:SetContent(fill)
        local sl = tabRow:AddChildToHorizontalBox(b)
        sl:SetPadding({ Left = 0, Top = 0, Right = 4, Bottom = 0 })
        tabs[#tabs + 1] = { border = b, fill = fill, text = label, id = t.id }
    end
    local ts = column:AddChildToVerticalBox(tabRow)
    ts:SetPadding({ Left = 0, Top = 0, Right = 0, Bottom = 8 })

    -- rows: a label, and the value with arrows either side
    local rows = {}
    for _ = 1, ROWS do
        local b = new("Border")
        b:SetBrushColor({ R = 0, G = 0, B = 0, A = 0 })
        b:SetPadding({ Left = 6, Top = 3, Right = 6, Bottom = 3 })
        local line = new("HorizontalBox")
        local label = text("", S.legendLabelSize, LABEL)
        pcall(function() label:SetAutoWrapText(true) end) -- long labels and notes wrap inside the panel
        local ls = line:AddChildToHorizontalBox(label)
        ls:SetVerticalAlignment(2)
        pcall(function() ls:SetSize({ SizeRule = 1, Value = 1 }) end)
        local valueBox = new("SizeBox")
        valueBox:SetWidthOverride(S.settingsValueWidth)
        local valueRow = new("HorizontalBox")
        local back = text("<", S.legendLabelSize, HEAD)
        local value = text("", S.legendLabelSize, style.selectedInk())
        local fwd = text(">", S.legendLabelSize, HEAD)
        local valuePlate = new("Border")
        style.buttonPlate(valuePlate, h.uw) -- a button: filled with the theme's material
        -- (its inside fills the button, so the ornaments sit at its ends, 8 units in from the border; the value is
        -- centered between them)
        valuePlate:SetPadding({ Left = 8, Top = 1, Right = 8, Bottom = 1 })
        valuePlate:SetHorizontalAlignment(0)
        -- an icon before the value where the choice has one (the themes: the game's combat-style icons)
        local valueLine = new("HorizontalBox")
        local icon = new("Image")
        pcall(function() icon:SetVisibility(1) end)
        local is = valueLine:AddChildToHorizontalBox(icon)
        is:SetVerticalAlignment(2)
        is:SetPadding({ Left = 0, Top = 0, Right = 4, Bottom = 0 })
        local vls = valueLine:AddChildToHorizontalBox(value); vls:SetVerticalAlignment(2)
        valuePlate:SetContent(style.buttonContent(new, valueLine, h.uw))
        local s1 = valueRow:AddChildToHorizontalBox(back); s1:SetVerticalAlignment(2)
        s1:SetPadding({ Left = 0, Top = 0, Right = 6, Bottom = 0 })
        local s2 = valueRow:AddChildToHorizontalBox(valuePlate); s2:SetVerticalAlignment(2)
        pcall(function() s2:SetSize({ SizeRule = 1, Value = 1 }) end)
        local s3 = valueRow:AddChildToHorizontalBox(fwd); s3:SetVerticalAlignment(2)
        s3:SetPadding({ Left = 6, Top = 0, Right = 0, Bottom = 0 })
        valueBox:SetContent(valueRow)
        local vs = line:AddChildToHorizontalBox(valueBox)
        vs:SetVerticalAlignment(2)
        b:SetContent(line)
        column:AddChildToVerticalBox(b)
        rows[#rows + 1] = { border = b, label = label, value = value, icon = icon, plate = valuePlate, back = back, fwd = fwd,
            box = valueBox }
    end

    -- the hovered row's explanation
    local tip = text("", S.legendSectionSize + 1, DIM)
    pcall(function() tip:SetAutoWrapText(true) end)
    local tipBox = new("SizeBox")
    -- room for four lines kept free (the panel doesn't jump as you hover), and a longer tip makes the panel taller
    -- instead of running over the CLOSE row (a fixed height had let a three-line tip spill out of it)
    tipBox:SetMinDesiredHeight(M.tipHeight(S.legendSectionSize + 1, S.settingsTipLines or 4))
    tipBox:SetContent(tip)
    local tps = column:AddChildToVerticalBox(tipBox)
    tps:SetPadding({ Left = 6, Top = 6, Right = 6, Bottom = 4 })

    -- footer: scroll arrows, CLOSE
    local footer = new("HorizontalBox")
    local up = text("<  previous", S.legendSectionSize + 1, HEAD)
    local down = text("next  >", S.legendSectionSize + 1, HEAD)
    -- previous on the left, CLOSE in the middle, next on the right (each arrow shown only when there's more that way)
    local function gap()
        local sps = footer:AddChildToHorizontalBox(new("Spacer"))
        pcall(function() sps:SetSize({ SizeRule = 1, Value = 1 }) end)
    end
    local u1 = footer:AddChildToHorizontalBox(up); u1:SetVerticalAlignment(2)
    gap()
    local close = new("Border")
    style.buttonPlate(close, h.uw)
    close:SetPadding({ Left = 8, Top = 5, Right = 8, Bottom = 5 })
    pcall(function() close:SetHorizontalAlignment(0) end)
    close:SetContent(style.buttonContent(new, text("CLOSE", S.legendHeadingSize, style.selectedInk()), h.uw))
    local cs = footer:AddChildToHorizontalBox(close); cs:SetVerticalAlignment(2)
    gap()
    local u2 = footer:AddChildToHorizontalBox(down); u2:SetVerticalAlignment(2)
    local fs = column:AddChildToVerticalBox(footer)
    fs:SetPadding({ Left = 0, Top = 4, Right = 0, Bottom = 0 })

    local slot = h.canvas:AddChildToCanvas(width)
    slot:SetAutoSize(true)
    slot:SetAnchors({ Minimum = { X = 0, Y = 0 }, Maximum = { X = 0, Y = 0 } })
    -- the panel as wide as its tabs need (the buttons grew ornaments), never narrower than settingsWidth: measured
    -- now, while the labels and the explanation are still empty, so long wrapping text can't widen it
    local panelW = S.settingsWidth
    pcall(function()
        root:ForceLayoutPrepass()
        panelW = M.panelWidth(S.settingsWidth, root:GetDesiredSize().X)
    end)
    pcall(function() width:SetWidthOverride(panelW) end)
    host = { width = panelW, uw = h.uw, canvas = h.canvas, slot = slot, root = width, plate = plate, tabs = tabs, rows = rows,
        close = close, up = up, down = down, tip = tip }
end

local function tabRows() return options.rowsOf(tab) end

-- Fill the rows from the current tab and settings.
local function paint()
    if not (host and W.valid(host.uw)) then return end
    local tc = themes.style().gold
    for _, t in ipairs(host.tabs) do
        pcall(function()
            local on = t.id == tab
            -- a button filled with the theme's material (fetched fresh: a loaded texture lives only while something
            -- shows it); the selected tab bright with the plate's lettering, the others dimmed with light lettering
            style.buttonPlate(t.border, host.uw)
            t.border:SetBrushColor(on and { R = 1, G = 1, B = 1, A = 1 } or { R = 0.45, G = 0.45, B = 0.45, A = 1 })
            t.fill:SetBrushColor({ R = 0, G = 0, B = 0, A = 0 })
            t.text:SetColorAndOpacity({ SpecifiedColor = on and style.selectedInk() or style.label(), ColorUseRule = 0 })
        end)
    end
    local list = tabRows()
    pcall(function() host.up:SetVisibility(offset > 0 and 3 or 2) end) -- 2 hidden: keeps its space
    pcall(function() host.down:SetVisibility(offset + ROWS < #list and 3 or 2) end)
    for i, r in ipairs(host.rows) do
        local row = list[offset + i]
        pcall(function()
            if not row then r.border:SetVisibility(2) return end
            r.border:SetVisibility(3)
            r.label:SetText(FText(row.label))
            local kind = row.type
            local stepped = kind == "choice" or kind == "number" or kind == "slider"
            r.back:SetVisibility(stepped and 3 or 2)
            r.fwd:SetVisibility(stepped and 3 or 2)
            if kind == "info" then
                r.box:SetVisibility(1)
                r.label:SetColorAndOpacity({ SpecifiedColor = style.dim(), ColorUseRule = 0 })
                return
            end
            r.label:SetColorAndOpacity({ SpecifiedColor = style.label(), ColorUseRule = 0 })
            r.box:SetVisibility(3)
            local shown
            if kind == "button" then
                shown = options.isArmed(armed, row, os.clock()) and "Sure? Click again" or "Do it"
            elseif kind == "key" then
                shown = (capturing == row) and "Press a key (Esc: cancel)" or tostring(setting(row) or "")
            else shown = options.display(row, setting(row)) end
            r.value:SetText(FText(shown))
            -- the value's icon (a theme's combat style), if it has one
            local iconName = row.icons and row.icons[setting(row)]
            local art = ctx.features.art
            local tex = iconName and art and art.gameTexture and art.gameTexture(iconName)
            if tex then
                local sz = S.legendLabelSize + 5
                pcall(function()
                    r.icon:SetBrush({ ResourceObject = tex, ImageSize = { X = sz, Y = sz }, DrawAs = 3, Tiling = 0,
                        TintColor = { SpecifiedColor = { R = 1, G = 1, B = 1, A = 1 }, ColorUseRule = 0 } })
                    r.icon:SetVisibility(3)
                end)
            else
                pcall(function() r.icon:SetVisibility(1) end)
            end
        end)
    end
end

-- Pure: the panel's width: what its contents need (rounded up), at least `min`. Unit-tested.
function M.panelWidth(min, need)
    return math.max(min, math.ceil(tonumber(need) or 0))
end

-- Pure: the room (UI units) the hovered row's explanation keeps free: `lines` lines of text at font size `size`
-- (a line is about 1.5 x the font size, with its spacing). Unit-tested.
function M.tipHeight(size, lines)
    return math.ceil(size * 1.5 * lines)
end

-- Pure: a panel position kept on screen, so its title bar can always be grabbed (the same limits as a drag).
-- Unit-tested.
function M.onScreen(x, y, sw, sh)
    return math.max(0, math.min(x, (sw or 1920) - 80)), math.max(0, math.min(y, (sh or 1080) - 28))
end

-- Where the panel opens: where it was last dragged to (editor.settingsX / settingsY, saved), else top middle.
local function place()
    if not host.x then
        local sw, sh = geometry.screen()
        if S.settingsX and S.settingsY then
            host.x, host.y = M.onScreen(S.settingsX, S.settingsY, sw, sh)
        else
            host.x = math.floor(((sw or 1920) - (host.width or S.settingsWidth)) / 2)
            host.y = math.floor((sh or 1080) * 0.18)
        end
    end
    pcall(function() host.slot:SetPosition({ X = host.x, Y = host.y }) end)
end

function M.open()
    if not (host and W.valid(host.uw)) then
        local ok, err = pcall(build)
        if not ok then log.warn("settings panel unavailable: %s", tostring(err)); host = nil; return false end
    end
    offset, drag = 0, nil
    place()
    paint()
    pcall(function() host.uw:SetVisibility(3) end)
    open = true
    return true
end

function M.close()
    if capturing then ctx.keys.cancelCapture(); capturing = nil end
    open = false
    drag = nil
    if host and W.valid(host.uw) then pcall(function() host.uw:SetVisibility(1) end) end
end

function M.toggle()
    if open then M.close() else M.open() end
    return open
end

function M.isOpen() return open end

local function inside(w, x, y)
    local r = w and geometry.rect(w)
    return r ~= nil and geometry.contains(r, x, y)
end

function M.scroll(by)
    local n = #tabRows()
    local o = math.max(0, math.min(offset + by, math.max(0, n - ROWS)))
    if o ~= offset then offset = o; paint() end
end

local function startCapture(row)
    capturing = row
    paint()
    ctx.keys.capture(function(spec)
        capturing = nil
        if spec then options.apply(ctx, row, spec) end
        paint()
    end)
end

local function activate(row, x, r)
    local kind = row.type
    if kind == "toggle" then
        options.apply(ctx, row, not setting(row))
    elseif kind == "choice" or kind == "number" or kind == "slider" then
        local box = geometry.rect(r.box)
        local dir = (box and x < (box.left + box.right) / 2) and -1 or 1
        if kind == "choice" then options.apply(ctx, row, options.cycle(row.options, setting(row), dir))
        else options.apply(ctx, row, options.step(row, setting(row), dir)) end
    elseif kind == "key" then
        startCapture(row)
        return
    elseif kind == "button" then
        if row.confirm and not options.isArmed(armed, row, os.clock()) then
            -- first click only asks; the label goes back to "Do it" when the time runs out
            armed = { row = row, at = os.clock() }
            paint()
            ctx.sched.later(options.CONFIRM_SECONDS * 1000 + 50, "settings.disarm", function()
                if armed and not options.isArmed(armed, armed.row, os.clock()) then armed = nil; paint() end
            end)
            return
        end
        armed = nil
        local ok, err = pcall(options.action, ctx, row.action)
        if not ok then log.warn("settings: %s failed: %s", tostring(row.action), tostring(err)) end
    end
    paint()
end

-- A press: true = the panel took it.
function M.onDown(x, y)
    if not (open and host and W.valid(host.uw)) then return false end
    if inside(host.plate, x, y) then
        drag = { x0 = x, y0 = y, px = host.x, py = host.y, moved = false }
        return true
    end
    if not inside(host.root, x, y) then return false end
    if capturing then return true end -- waiting for a key: clicks don't change anything
    if inside(host.close, x, y) then M.close(); if onClose then onClose() end return true end
    if offset > 0 and inside(host.up, x, y) then M.scroll(-(ROWS - 1)) return true end
    if offset + ROWS < #tabRows() and inside(host.down, x, y) then M.scroll(ROWS - 1) return true end
    for _, t in ipairs(host.tabs) do
        if inside(t.border, x, y) then
            tab, offset = t.id, 0
            paint()
            return true
        end
    end
    local list = tabRows()
    for i, r in ipairs(host.rows) do
        local row = list[offset + i]
        if row and inside(r.border, x, y) then
            activate(row, x, r)
            return true
        end
    end
    return true
end

function M.onUp()
    if not drag then return false end
    if drag.moved and host and host.x then
        -- remember where it was put, for the next time it opens (this session or the next)
        S.settingsX, S.settingsY = math.floor(host.x + 0.5), math.floor(host.y + 0.5)
        ctx.saveSettings()
    end
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
    host.x, host.y = M.onScreen(drag.px + dx, drag.py + dy, sw, sh)
    pcall(function() host.slot:SetPosition({ X = host.x, Y = host.y }) end)
end

function M.onWheel(x, y, delta)
    if not (open and host and inside(host.root, x, y)) then return false end
    M.scroll(delta > 0 and -2 or 2)
    return true
end

-- Every editor frame: the explanation of the row under the pointer.
local lastTip
function M.tick()
    if not (open and host and W.valid(host.uw)) then return end
    local x, y = geometry.mouse()
    local tipText = ""
    if x then
        local list = tabRows()
        for i, r in ipairs(host.rows) do
            local row = list[offset + i]
            if row and inside(r.border, x, y) then tipText = row.tooltip or "" break end
        end
    end
    if tipText ~= lastTip then
        lastTip = tipText
        pcall(function() host.tip:SetText(FText(tipText)) end)
    end
end

-- Settings changed elsewhere (a hotkey, the next-layout key): show the new values.
function M.refresh() if open then paint() end end

function M.forget() host = nil; open = false; drag = nil; capturing = nil end

function M.restyle()
    if host and W.valid(host.uw) then pcall(function() host.uw:RemoveFromParent() end) end
    M.forget()
end

function M.init(c, settings, closed)
    ctx, S, log, onClose = c, settings, c.log, closed
end

return M
