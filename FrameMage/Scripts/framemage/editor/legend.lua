-- Hotkey legend shown while the editor is open: one row per player-facing hotkey, drawn the way the game
-- draws its own key prompts (WBP_DomInputIconWidget): the game's blank keycap texture with the key name in
-- the game's key font on top. Mouse buttons use Frame Mage's own mouse glyphs (Art/_ui, tools/make_icons.py).
-- Developer keys (dump, art reload) are left out. Rows follow live rebinding (rebuilt on the next open).
-- It has a gold title bar like the editor's own: drag it to move the list anywhere (remembered), click the chevron
-- (or F3) to slide the list closed into the bar and open again (remembered too).
local overlay = require("framemage.core.overlay")
local W = require("framemage.core.widgets")
local keys = require("framemage.core.keys")
local geometry = require("framemage.core.geometry")
local style = require("framemage.editor.style")

local M = {}

-- Pure parts (unit-tested) -------------------------------------------------------------------------

local LABELS = {
    PageUp = "PgUp", PageDown = "PgDn", Insert = "Ins", Delete = "Del", BackSpace = "Bksp",
    Equals = "+", Hyphen = "-", Add = "+", Subtract = "-", LeftBracket = "[", RightBracket = "]",
    SpaceBar = "Space", Escape = "Esc", Comma = ",", Period = ".", Slash = "/", Semicolon = ";",
    Apostrophe = "'", Backslash = "\\", Tilde = "~",
    Zero = "0", One = "1", Two = "2", Three = "3", Four = "4", Five = "5", Six = "6", Seven = "7", Eight = "8", Nine = "9",
    CONTROL = "Ctrl", SHIFT = "Shift", ALT = "Alt",
    -- controller (Xbox names, as Unreal uses them)
    Gamepad_FaceButton_Bottom = "A", Gamepad_FaceButton_Right = "B", Gamepad_FaceButton_Left = "X",
    Gamepad_FaceButton_Top = "Y", Gamepad_LeftShoulder = "LB", Gamepad_RightShoulder = "RB",
    Gamepad_LeftTrigger = "LT", Gamepad_RightTrigger = "RT", Gamepad_LeftThumbstick = "LS",
    Gamepad_RightThumbstick = "RS", Gamepad_DPad_Up = "Up", Gamepad_DPad_Down = "Down",
    Gamepad_DPad_Left = "Left", Gamepad_DPad_Right = "Right", Gamepad_Special_Left = "View",
    Gamepad_Special_Right = "Menu",
}
local MOUSE = { LeftMouseButton = "left", RightMouseButton = "right", MiddleMouseButton = "middle" }
local ARROWS = { Left = true, Right = true, Up = true, Down = true }

-- A key's cap: { text = "PgDn", wide = true } or { mouse = "left" }
function M.cap(name)
    if MOUSE[name] then return { mouse = MOUSE[name] } end
    local text = LABELS[name] or name
    return { text = text, wide = #text > 2 }
end

-- Caps for a spec, modifiers first: "CTRL+PageDown" -> { Ctrl, PgDn }; a chord "A&B" -> { A, B }
function M.caps(spec)
    local p = keys.parse(spec)
    if not p then return nil end
    local out = {}
    for _, m in ipairs(p.mods) do out[#out + 1] = M.cap(m) end
    for _, k in ipairs(p.chord or { p.key }) do out[#out + 1] = M.cap(k) end
    return out
end

-- Pure: shared modifiers shown once. { {Ctrl,PgUp}, {Ctrl,PgDn} } -> prefix {Ctrl}, alts { {PgUp}, {PgDn} }.
local function sameCap(x, y) return x.text == y.text and x.mouse == y.mouse end
function M.collapse(groups)
    if #groups < 2 then return {}, groups end
    local n = #groups[1]
    if n < 2 then return {}, groups end
    for _, g in ipairs(groups) do
        if #g ~= n then return {}, groups end
        for i = 1, n - 1 do
            if not sameCap(g[i], groups[1][i]) then return {}, groups end
        end
    end
    local prefix, alts = {}, {}
    for i = 1, n - 1 do prefix[i] = groups[1][i] end
    for i, g in ipairs(groups) do alts[i] = { g[n] } end
    return prefix, alts
end

-- The legend's entries from the current key specs. specFor(setting) -> spec string or nil.
-- Entry: { header = "Move" } or { prefix = {cap...}, alts = { {cap...}, ... } (shown with "/"), label = "..." }
-- device: "gamepad" lists the controller buttons; anything else the mouse and keyboard.
function M.rows(specFor, bigModifier, device)
    if device == "gamepad" then return M.padRows(specFor) end
    local rows = {}
    local function header(t) rows[#rows + 1] = { header = t } end
    local function fixed(label, ...) rows[#rows + 1] = { prefix = {}, alts = { { ... } }, label = label } end
    local function row(label, settings)
        local groups = {}
        for _, s in ipairs(settings) do
            local c = M.caps(specFor(s) or "")
            if c then groups[#groups + 1] = c end
        end
        if #groups == 0 then return end
        local prefix, alts = M.collapse(groups)
        rows[#rows + 1] = { prefix = prefix, alts = alts, label = label }
    end
    header("Select")
    fixed("Click  (again: the panel around it)", M.cap("LeftMouseButton"))
    fixed("The panel around it", M.cap("RightMouseButton"))
    row("Previous / next", { "prev", "next" })
    row("Neighboring part", { "prevSibling", "nextSibling" })
    row("Parent / child", { "parent", "child" })
    row("Hidden elements (click to show)", { "showHidden" })
    header("Move")
    fixed("Drag a title bar", M.cap("LeftMouseButton"))
    -- the four arrow keys collapse into one "Arrows" cap when they are the arrow keys
    local arrowSpecs, allArrows = {}, true
    for _, s in ipairs({ "left", "right", "up", "down" }) do
        local p = keys.parse(specFor(s) or "")
        arrowSpecs[#arrowSpecs + 1] = s
        if not (p and ARROWS[p.key] and #p.mods == 0) then allArrows = false end
    end
    if allArrows then
        local big = keys.parse(bigModifier or "")
        local mod = big and big.key or "SHIFT"
        local modName = LABELS[mod:upper()] or mod
        fixed("Nudge  (hold " .. modName .. ": further)", { text = "Arrows", wide = true })
    else
        row("Nudge", arrowSpecs)
    end
    header("Change")
    row("Smaller / bigger", { "scaleDown", "scaleUp" })
    row("More / less faded", { "fadeDown", "fadeUp" })
    row("Hide / show", { "hide" })
    row("Reset element", { "reset" })
    row("Undo a move", { "undo" })
    header("Editor")
    row("Grid on / off", { "toggleGrid" })
    row("Next layout", { "nextProfile" })
    row("Settings", { "settings" })
    row("Show / hide this list", { "legend" })
    row("Close editor", { "edit", "closeEditor" })
    return rows
end

-- Controller entries (shown after the pad was used).
function M.padRows(specFor)
    local rows = {}
    local function header(t) rows[#rows + 1] = { header = t } end
    local function fixed(label, cap) rows[#rows + 1] = { prefix = {}, alts = { { cap } }, label = label } end
    local function row(label, settings)
        local groups = {}
        for _, s in ipairs(settings) do
            local c = M.caps(specFor(s) or "")
            if c then groups[#groups + 1] = c end
        end
        if #groups == 0 then return end
        local prefix, alts = M.collapse(groups)
        rows[#rows + 1] = { prefix = prefix, alts = alts, label = label }
    end
    header("Select")
    row("Previous / next", { "padPrev", "padNext" })
    row("Child", { "padChild" })
    row("Parent", { "padParent" })
    header("Move")
    fixed("Move", { text = "L-stick", wide = true })
    fixed("Nudge  (snaps to the grid)", { text = "D-pad", wide = true })
    header("Change")
    row("Smaller / bigger", { "padScaleDown", "padScaleUp" })
    row("Hide / show", { "padHide" })
    row("Reset element", { "padReset" })
    header("Editor")
    row("Grid on / off", { "padGrid" })
    row("Close editor", { "padEdit" })
    return rows
end

-- Widget ---------------------------------------------------------------------------------------------

local host -- { uw, canvas, slot, root, plate, chev, clip, back, x, y, fullH }
local dirty = true
local ctx, S -- set on show
local collapsed = false
local anim -- { from, to, t0, current }
local drag -- { x0, y0, px, py, moved, onChevron }
local shown = false

local function findTexture(name)
    for _, t in pairs(FindAllOf("Texture2D") or {}) do
        local ok, n = pcall(function() return t:GetFName():ToString() end)
        if ok and n == name and W.valid(t) then return t end
    end
    return nil
end

-- The game's key font, copied (never edited in place) from a live key prompt.
local function gameKeyFont()
    for _, cls in ipairs({ "DomTextBlock", "CommonTextBlock", "TextBlock" }) do
        for _, t in pairs(FindAllOf(cls) or {}) do
            local ok, f = pcall(function()
                if t:GetFName():ToString() ~= "KeyText" then return nil end
                local font = t.Font
                return { FontObject = font.FontObject, TypefaceFontName = font.TypefaceFontName, Size = font.Size }
            end)
            if ok and f then return f end
        end
    end
    return nil
end

-- Exposed for the banner: the game's key font (copied), or nil.
function M.gameFont() return gameKeyFont() end

local function withSize(font, size)
    if not font then return nil end
    return { FontObject = font.FontObject, TypefaceFontName = font.TypefaceFontName, Size = size }
end

-- A keycap: the game's blank keycap drawn as a 9-slice box (fixed corners, stretchy middle) behind the key's
-- name, so a cap always fits its text: "F7" stays square, "Arrows" grows wide. Mouse buttons use our glyphs.
-- Key names too wide for their cap scroll inside it, like the game's own key prompts: { text, t0, overflow }.
local marquees = {}

-- Pure: the scroll offset of an overflowing key name at time t: rest, glide left until its end shows, rest,
-- glide back. overflow = how much wider the name is than its window. Unit-tested.
function M.marquee(t, overflow, speed, pause)
    if overflow <= 0 then return 0 end
    local travel = overflow / speed
    local p = t % (2 * (pause + travel))
    if p < pause then return 0 end
    p = p - pause
    if p < travel then return -overflow * M.ease(p / travel) end
    p = p - travel
    if p < pause then return -overflow end
    return -overflow * (1 - M.ease((p - pause) / travel))
end

local function makeCap(new, text, c, S, capTex, ownIcon)
    if c.mouse then
        local size = new("SizeBox")
        size:SetWidthOverride(math.floor(S.legendKeySize * 0.75))
        size:SetHeightOverride(S.legendKeySize)
        local img = new("Image")
        local tex = ownIcon("fm_mouse_" .. c.mouse .. ".png")
        if tex then img:SetBrushFromTexture(tex, false) end
        size:SetContent(img)
        return size
    end
    -- every key the same size: wider than tall, like the game's own prompts, so most names fit without scrolling
    local keyW = S.legendKeyWidth or S.legendKeySize
    local size = new("SizeBox")
    size:SetWidthOverride(keyW)
    size:SetHeightOverride(S.legendKeySize)
    local cap = new("Border")
    local boxed = false
    if capTex then
        boxed = pcall(function()
            cap:SetBrush({
                ResourceObject = capTex,
                ImageSize = { X = keyW, Y = S.legendKeySize },
                DrawAs = 1, -- Box: 9-slice
                Margin = { Left = 0.32, Top = 0.32, Right = 0.32, Bottom = 0.32 },
                TintColor = { SpecifiedColor = { R = 1, G = 1, B = 1, A = 1 }, ColorUseRule = 0 },
            })
        end)
        if not boxed then pcall(function() cap:SetBrushFromTexture(capTex) end) end
    end
    if not capTex then
        cap:SetBrushColor({ R = 0.12, G = 0.11, B = 0.10, A = 0.95 })
    end
    cap:SetPadding({ Left = S.legendCapPadX, Top = 1, Right = S.legendCapPadX, Bottom = 2 })
    cap:SetHorizontalAlignment(0) -- the window fills the cap; the text centers in it (or scrolls)
    cap:SetVerticalAlignment(2)
    -- the name sits in a clipped window; a long name scrolls in it (see M.tick)
    local window = new("SizeBox")
    window:SetWidthOverride(keyW - 2 * S.legendCapPadX)
    pcall(function() window.Clipping = 1 end)
    pcall(function() window:SetClipping(1) end)
    local t = text(c.text, S.legendCapFontSize, { R = 0.96, G = 0.93, B = 0.86, A = 1 })
    pcall(function() t:SetJustification(1) end) -- centered while it fits
    window:SetContent(t)
    cap:SetContent(window)
    size:SetContent(cap)
    marquees[#marquees + 1] = { text = t, t0 = os.clock() + #marquees * 0.15, overflow = nil }
    return size
end

local function build(ctx, S)
    marquees = {}
    local h = overlay.host("Legend", 19997)
    local art = ctx.features.art
    local function ownIcon(file) return art and art.loadFile(ctx.dir .. "Art/_ui/" .. file, h.uw) end
    -- keycaps: the theme's own, else the game's blank keycap, else our plain one
    -- (always the game's: the theme's own border isn't for keys)
    local capTex = findTexture("T_Keys-Special-Blank") or findTexture("T_Keys-Standard-Blank") or ownIcon("fm_keycap.png")
    local font = gameKeyFont()
    local n = 0
    local function new(cls)
        n = n + 1
        return overlay.new(cls, h.tree, "FM_Legend_" .. cls .. "_" .. h.suffix .. "_" .. n)
    end
    local function text(str, size, color)
        local t = new("TextBlock")
        t:SetText(FText(str))
        if font then pcall(function() t:SetFont(withSize(font, size)) end) end
        t:SetColorAndOpacity({ SpecifiedColor = color, ColorUseRule = 0 })
        return t
    end
    local GOLD, LABEL, SEP, INK = style.heading(), style.label(), style.dim(), style.ink()

    local root = new("VerticalBox")

    -- title bar: gold plate, black heading, chevron at the right (the drag handle and the collapse button)
    local plate = new("Border")
    style.titlePlate(plate, h.uw)
    plate:SetPadding({ Left = 14, Top = 6, Right = 12, Bottom = 6 })
    local bar = new("HorizontalBox")
    local titleText = text(M.TITLE, S.legendHeadingSize, INK)
    local hs0 = bar:AddChildToHorizontalBox(titleText)
    hs0:SetVerticalAlignment(2)
    local spacer = new("Spacer")
    local ss = bar:AddChildToHorizontalBox(spacer)
    pcall(function() ss:SetSize({ SizeRule = 1, Value = 1 }) end) -- fill: pushes the chevron to the right
    local chevBox = new("SizeBox")
    chevBox:SetWidthOverride(S.legendChevronSize)
    chevBox:SetHeightOverride(S.legendChevronSize)
    local chev = new("Image")
    local ct = ownIcon("fm_chevron.png")
    if ct then chev:SetBrushFromTexture(ct, false) end
    chev:SetColorAndOpacity(INK)
    pcall(function() chev:SetRenderTransformPivot({ X = 0.5, Y = 0.5 }) end)
    chevBox:SetContent(chev)
    local cs = bar:AddChildToHorizontalBox(chevBox)
    cs:SetVerticalAlignment(2)
    cs:SetPadding({ Left = 14, Top = 0, Right = 0, Bottom = 0 })
    plate:SetContent(bar)
    root:AddChildToVerticalBox(plate)

    -- body, inside a clipping box whose height animates for the slide
    local clip = new("SizeBox")
    -- clip to bounds (property and setter both: either may be all that takes on a given build), so the list is
    -- cut off at the box's edge as it shrinks instead of spilling out below
    pcall(function() clip.Clipping = 1 end)
    pcall(function() clip:SetClipping(1) end)
    local column = new("VerticalBox")
    local back = style.panel(new, column, h.uw) -- the theme's stone panel with its inlaid frame
    clip:SetContent(back)
    root:AddChildToVerticalBox(clip)

    -- two columns: keys right-aligned, descriptions left-aligned; the grid sizes each column to its widest entry
    local grid = new("GridPanel")
    column:AddChildToVerticalBox(grid)
    local row = 0
    for _, r in ipairs(M.rows(keys.specFor, ctx.settings.keys.bigModifier, keys.device)) do
        if r.header then
            local hs = grid:AddChildToGrid(text(r.header:upper(), S.legendSectionSize, GOLD), row, 0)
            pcall(function() hs:SetColumnSpan(2) end)
            hs:SetPadding({ Left = 0, Top = row == 0 and 4 or 10, Right = 0, Bottom = 2 })
        else
            local capsBox = new("HorizontalBox")
            local function add(widget, padL, padR)
                local s = capsBox:AddChildToHorizontalBox(widget)
                s:SetVerticalAlignment(2)
                s:SetPadding({ Left = padL or 0, Top = 0, Right = padR or 0, Bottom = 0 })
            end
            for i, c in ipairs(r.prefix) do
                if i > 1 then add(text("+", S.legendCapFontSize, SEP), 3, 3) end
                add(makeCap(new, text, c, S, capTex, ownIcon))
            end
            if #r.prefix > 0 then add(text("+", S.legendCapFontSize, SEP), 4, 4) end
            for gi, group in ipairs(r.alts) do
                if gi > 1 then add(text("/", S.legendCapFontSize, SEP), 4, 4) end
                for ci, c in ipairs(group) do
                    if ci > 1 then add(text("+", S.legendCapFontSize, SEP), 3, 3) end
                    add(makeCap(new, text, c, S, capTex, ownIcon))
                end
            end
            local ks = grid:AddChildToGrid(capsBox, row, 0)
            ks:SetHorizontalAlignment(3) -- right
            ks:SetVerticalAlignment(2)
            ks:SetPadding({ Left = 0, Top = 2, Right = 0, Bottom = 2 })
            local ls = grid:AddChildToGrid(text(r.label, S.legendLabelSize, LABEL), row, 1)
            ls:SetVerticalAlignment(2)
            ls:SetPadding({ Left = 12, Top = 2, Right = 0, Bottom = 2 })
        end
        row = row + 1
    end

    local slot = h.canvas:AddChildToCanvas(root)
    slot:SetAutoSize(true)
    slot:SetAnchors({ Minimum = { X = 0, Y = 0 }, Maximum = { X = 0, Y = 0 } })
    slot:SetAlignment({ X = 0, Y = 0 })
    local x = S.legendX >= 0 and S.legendX or S.legendMargin
    local y = S.legendY >= 0 and S.legendY or S.legendDefaultTop
    slot:SetPosition({ X = x, Y = y })
    host = { uw = h.uw, canvas = h.canvas, slot = slot, root = root, plate = plate, chev = chev, clip = clip, back = back,
        title = titleText,
        x = x, y = y }
    -- start in the remembered state, without animating
    collapsed = S.legendCollapsed == true
    anim = nil
    M.paint(collapsed and 1 or 0, true)
    dirty = false
end

-- Collapse / expand ---------------------------------------------------------------------------------------

-- Pure: smooth in-out ease (0..1).
function M.ease(t)
    t = math.max(0, math.min(1, t))
    return t * t * (3 - 2 * t)
end

-- Pure: the body's height and the chevron's angle at closedness c (0 = open, 1 = closed). Unit-tested.
function M.slide(c, fullHeight)
    return fullHeight * (1 - c), -90 * c, 1 - c
end

-- Draw the list at closedness c. `settled` = not animating (an open list then takes its natural height).
function M.paint(c, settled)
    if not (host and W.valid(host.uw)) then return end
    local full = host.fullH
    if not full or full <= 0 then
        -- lay the list out first: a list that starts closed has never been measured
        local ok, size = pcall(function()
            host.back:ForceLayoutPrepass()
            return host.back:GetDesiredSize()
        end)
        if ok and size and size.Y and size.Y > 0 then
            full = size.Y
            host.fullH = full
        else
            full = 400 -- a guess for this frame only; measured properly next time
        end
    end
    local h, angle, alpha = M.slide(c, full)
    pcall(function()
        if settled and c <= 0 then host.clip:ClearHeightOverride() else host.clip:SetHeightOverride(h) end
        host.back:SetRenderOpacity(alpha)
        host.chev:SetRenderTransformAngle(angle)
        -- fully closed: the body is gone, not just squeezed (nothing can show through even unclipped)
        host.clip:SetVisibility((settled and c >= 1) and 1 or 3)
    end)
end

function M.toggle()
    if not (host and W.valid(host.uw)) then return end
    -- measure the open height now (an open, settled list has its natural size)
    if not collapsed then
        local ok, size = pcall(function() return host.back:GetDesiredSize() end)
        if ok and size and size.Y and size.Y > 0 then host.fullH = size.Y end
    end
    local from = anim and anim.current or (collapsed and 1 or 0)
    collapsed = not collapsed
    anim = { from = from, to = collapsed and 1 or 0, t0 = os.clock(), current = from }
    if ctx then
        ctx.settings.editor.legendCollapsed = collapsed
        ctx.saveSettings()
    end
end

-- Every frame while the editor is open: run the slide.
-- Scroll the key names that don't fit (measured once, after the list has been laid out).
local function scrollNames()
    if not (S and host and shown) then return end
    local inner = (S.legendKeyWidth or S.legendKeySize) - 2 * S.legendCapPadX -- (the cap's width, inside its rim)
    local now = os.clock()
    for _, m in ipairs(marquees) do
        if m.overflow == nil then
            local ok, d = pcall(function()
                m.text:ForceLayoutPrepass()
                return m.text:GetDesiredSize()
            end)
            m.overflow = (ok and d and d.X and d.X > 0) and math.max(0, d.X - inner + 1) or 0
            if m.overflow > 0.5 then pcall(function() m.text:SetJustification(0) end) else m.overflow = 0 end
        end
        if m.overflow > 0 then
            local x = M.marquee(now - m.t0, m.overflow, S.legendMarqueeSpeed, S.legendMarqueePause)
            pcall(function() m.text:SetRenderTranslation({ X = x, Y = 0 }) end)
        end
    end
end

-- Short messages ("Layout saved", "Nothing to select there") show in the title bar for a moment, then it goes back
-- to its title. (They used to show in a banner under the compass, which got in the way of moving things.)
M.TITLE = "EDITOR CONTROLS"
local flashUntil

function M.flash(msg, seconds)
    if not (host and W.valid(host.uw) and host.title) then return end
    pcall(function() host.title:SetText(FText(msg)) end)
    flashUntil = os.clock() + (seconds or 2.2)
end

local function endFlash()
    if flashUntil and os.clock() >= flashUntil then
        flashUntil = nil
        if host and host.title then pcall(function() host.title:SetText(FText(M.TITLE)) end) end
    end
end

function M.tick()
    endFlash()
    scrollNames()
    if not anim then return end
    local t = (os.clock() - anim.t0) / (S and S.legendSlideTime or 0.2)
    local c = anim.from + (anim.to - anim.from) * M.ease(t)
    anim.current = c
    if t >= 1 then
        M.paint(anim.to, true)
        anim = nil
    else
        M.paint(c, false)
    end
end

-- Mouse (from the editor's catcher) ----------------------------------------------------------------------

local function grow(r, by)
    return { left = r.left - by, top = r.top - by, right = r.right + by, bottom = r.bottom + by }
end

-- A press: on the title bar starts a drag (a click without moving toggles, if on the chevron or while closed);
-- anywhere else on the open list is swallowed so it doesn't select the game widget underneath. true = handled.
function M.onDown(x, y)
    if not (host and W.valid(host.uw) and shown) then return false end
    local plate = geometry.rect(host.plate)
    if ctx then
        if plate then
            ctx.log.info("hotkey list bar at %.0f..%.0f, %.0f..%.0f", plate.left, plate.right, plate.top, plate.bottom)
        else
            ctx.log.warn("hotkey list bar: could not measure it")
        end
    end
    if plate and geometry.contains(plate, x, y) then
        local chev = geometry.rect(host.chev)
        drag = { x0 = x, y0 = y, px = host.x, py = host.y, moved = false,
            onChevron = chev ~= nil and geometry.contains(grow(chev, 8), x, y) }
        return true
    end
    if not collapsed then
        local body = geometry.rect(host.root)
        if body and geometry.contains(body, x, y) then return true end
    end
    return false
end

function M.onUp()
    if not drag then return false end
    local d = drag
    drag = nil
    if d.moved then
        if ctx then
            ctx.settings.editor.legendX = math.floor(host.x + 0.5)
            ctx.settings.editor.legendY = math.floor(host.y + 0.5)
            ctx.saveSettings()
        end
    elseif d.onChevron or collapsed then
        M.toggle()
    end
    return true
end

-- Pure: keep the list's title on screen. Unit-tested.
function M.clamp(x, y, screenW, screenH, keepW, keepH)
    return math.max(0, math.min(x, screenW - keepW)), math.max(0, math.min(y, screenH - keepH))
end

function M.dragTick(x, y)
    if not (drag and x and host and W.valid(host.uw)) then return end
    local dx, dy = x - drag.x0, y - drag.y0
    if math.abs(dx) + math.abs(dy) > 3 then drag.moved = true end
    if not drag.moved then return end
    local screen = geometry.rect(host.canvas)
    local sw = screen and (screen.right - screen.left) or 1920
    local sh = screen and (screen.bottom - screen.top) or 1080
    host.x, host.y = M.clamp(drag.px + dx, drag.py + dy, sw, sh, 80, 28)
    pcall(function() host.slot:SetPosition({ X = host.x, Y = host.y }) end)
end

function M.isDragging() return drag ~= nil end

function M.show(c, settings)
    ctx, S = c, settings
    if not S.showLegend then M.hide() return end
    if dirty and host and W.valid(host.uw) then
        pcall(function() host.uw:RemoveFromParent() end)
        host = nil
    end
    if not (host and W.valid(host.uw)) then
        local ok, err = pcall(build, ctx, S)
        if not ok then ctx.log.warn("hotkey legend unavailable: %s", tostring(err)); host = nil; return end
    end
    if host then pcall(function() host.uw:SetVisibility(3) end) end
    shown = host ~= nil
end

function M.hide()
    if host and W.valid(host.uw) then pcall(function() host.uw:SetVisibility(1) end) end
    shown = false
    drag = nil
end

-- Keys changed: rebuild on the next show.
function M.invalidate() dirty = true end
function M.forget() host = nil; dirty = true; shown = false; drag = nil; anim = nil; marquees = {} end

return M
