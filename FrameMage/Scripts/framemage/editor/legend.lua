-- Hotkey legend shown while the editor is open: one row per player-facing hotkey, drawn the way the game
-- draws its own key prompts (WBP_DomInputIconWidget): the game's blank keycap texture with the key name in
-- the game's key font on top. Mouse buttons use Frame Mage's own mouse glyphs (Art/_ui, tools/make_icons.py).
-- Developer keys (dump, art reload) are left out. Rows follow live rebinding (rebuilt on the next open).
local overlay = require("framemage.core.overlay")
local W = require("framemage.core.widgets")
local keys = require("framemage.core.keys")

local M = {}

-- Pure parts (unit-tested) -------------------------------------------------------------------------

local LABELS = {
    PageUp = "PgUp", PageDown = "PgDn", Insert = "Ins", Delete = "Del", BackSpace = "Bksp",
    Equals = "+", Hyphen = "-", Add = "+", Subtract = "-", LeftBracket = "[", RightBracket = "]",
    SpaceBar = "Space", Escape = "Esc", Comma = ",", Period = ".", Slash = "/", Semicolon = ";",
    Apostrophe = "'", Backslash = "\\", Tilde = "~",
    Zero = "0", One = "1", Two = "2", Three = "3", Four = "4", Five = "5", Six = "6", Seven = "7", Eight = "8", Nine = "9",
    CONTROL = "Ctrl", SHIFT = "Shift", ALT = "Alt",
}
local MOUSE = { LeftMouseButton = "left", RightMouseButton = "right", MiddleMouseButton = "middle" }
local ARROWS = { Left = true, Right = true, Up = true, Down = true }

-- A key's cap: { text = "PgDn", wide = true } or { mouse = "left" }
function M.cap(name)
    if MOUSE[name] then return { mouse = MOUSE[name] } end
    local text = LABELS[name] or name
    return { text = text, wide = #text > 2 }
end

-- Caps for a spec, modifiers first: "CTRL+PageDown" -> { Ctrl, PgDn }
function M.caps(spec)
    local p = keys.parse(spec)
    if not p then return nil end
    local out = {}
    for _, m in ipairs(p.mods) do out[#out + 1] = M.cap(m) end
    out[#out + 1] = M.cap(p.key)
    return out
end

-- The legend rows from the current key specs. specFor(setting) -> spec string or nil.
-- Each row: { groups = { {cap...}, ... } (alternatives, shown with "/"), label = "..." }
function M.rows(specFor, bigModifier)
    local rows = {}
    local function row(label, settings)
        local groups = {}
        for _, s in ipairs(settings) do
            local c = M.caps(specFor(s) or "")
            if c then groups[#groups + 1] = c end
        end
        if #groups > 0 then rows[#rows + 1] = { groups = groups, label = label } end
    end
    row("Select  (again: parent)", { "pick" })
    row("Previous / next", { "prev", "next" })
    row("Parts of the same panel", { "prevSibling", "nextSibling" })
    row("Parent / child", { "parent", "child" })
    -- the four arrow keys collapse into one "Arrows" cap when they are the arrow keys
    local arrowSpecs, allArrows = {}, true
    for _, s in ipairs({ "left", "right", "up", "down" }) do
        local p = keys.parse(specFor(s) or "")
        arrowSpecs[#arrowSpecs + 1] = s
        if not (p and ARROWS[p.key] and #p.mods == 0) then allArrows = false end
    end
    if allArrows then
        rows[#rows + 1] = { groups = { { { text = "Arrows", wide = true } } }, label = "Move" }
        local big = keys.parse(bigModifier or "")
        local mod = big and big.key or "SHIFT"
        rows[#rows + 1] = { groups = { { M.cap(LABELS[mod:upper()] and mod:upper() or mod), { text = "Arrows", wide = true } } },
            label = "Move further" }
    else
        row("Move", arrowSpecs)
    end
    row("Scale", { "scaleDown", "scaleUp" })
    row("Fade", { "fadeDown", "fadeUp" })
    row("Hide / show", { "hide" })
    row("Reset element", { "reset" })
    row("Grid on / off", { "toggleGrid" })
    row("Next layout", { "nextProfile" })
    row("Close editor", { "edit" })
    return rows
end

-- Widget ---------------------------------------------------------------------------------------------

local host -- { uw, built = true }
local dirty = true

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

local function build(ctx, S)
    local h = overlay.host("Legend", 19997)
    local art = ctx.features.art
    local function ownIcon(file) return art and art.loadFile(ctx.dir .. "Art/_ui/" .. file, h.uw) end
    local capStd = findTexture("T_Keys-Standard-Blank") or ownIcon("fm_keycap.png")
    local capWide = findTexture("T_Keys-Special-Blank") or capStd
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
    local CAP_TEXT = { R = 0.95, G = 0.92, B = 0.85, A = 1 }
    local LABEL = { R = 0.86, G = 0.83, B = 0.76, A = 1 }
    local SEP = { R = 0.6, G = 0.58, B = 0.52, A = 1 }

    local function capWidget(c)
        local size = new("SizeBox")
        if c.mouse then
            size:SetWidthOverride(S.legendKeySize * 0.75)
            size:SetHeightOverride(S.legendKeySize)
            local img = new("Image")
            local tex = ownIcon("fm_mouse_" .. c.mouse .. ".png")
            if tex then img:SetBrushFromTexture(tex, false) end
            size:SetContent(img)
            return size
        end
        local width = c.wide and math.max(S.legendKeySize * 1.6, 10 + #c.text * S.legendKeySize * 0.36) or S.legendKeySize
        size:SetWidthOverride(width)
        size:SetHeightOverride(S.legendKeySize)
        local ov = new("Overlay")
        local img = new("Image")
        local tex = c.wide and capWide or capStd
        if tex then img:SetBrushFromTexture(tex, false) end
        ov:AddChildToOverlay(img) -- fills
        local t = text(c.text, math.floor(S.legendKeySize * 0.45), CAP_TEXT)
        local ts = ov:AddChildToOverlay(t)
        ts:SetHorizontalAlignment(2) -- center
        ts:SetVerticalAlignment(2)
        size:SetContent(ov)
        return size
    end

    local back = new("Border")
    back:SetBrushColor({ R = 0.02, G = 0.02, B = 0.03, A = 0.72 })
    back:SetPadding({ Left = 12, Top = 10, Right = 14, Bottom = 10 })
    local list = new("VerticalBox")
    back:SetContent(list)

    for _, r in ipairs(M.rows(keys.specFor, ctx.settings.keys.bigModifier)) do
        local line = new("HorizontalBox")
        local capsBox = new("HorizontalBox")
        for gi, group in ipairs(r.groups) do
            if gi > 1 then
                local s = capsBox:AddChildToHorizontalBox(text("/", math.floor(S.legendKeySize * 0.45), SEP))
                s:SetPadding({ Left = 4, Top = 0, Right = 4, Bottom = 0 })
                s:SetVerticalAlignment(2)
            end
            for ci, c in ipairs(group) do
                if ci > 1 then
                    local s = capsBox:AddChildToHorizontalBox(text("+", math.floor(S.legendKeySize * 0.45), SEP))
                    s:SetPadding({ Left = 3, Top = 0, Right = 3, Bottom = 0 })
                    s:SetVerticalAlignment(2)
                end
                local s = capsBox:AddChildToHorizontalBox(capWidget(c))
                s:SetVerticalAlignment(2)
            end
        end
        local capsSize = new("SizeBox")
        capsSize:SetMinDesiredWidth(S.legendKeyColumn)
        capsSize:SetContent(capsBox)
        local cs = line:AddChildToHorizontalBox(capsSize)
        cs:SetVerticalAlignment(2)
        local ls = line:AddChildToHorizontalBox(text(r.label, math.floor(S.legendKeySize * 0.5), LABEL))
        ls:SetVerticalAlignment(2)
        ls:SetPadding({ Left = 10, Top = 0, Right = 0, Bottom = 0 })
        local rs = list:AddChildToVerticalBox(line)
        rs:SetPadding({ Left = 0, Top = 3, Right = 0, Bottom = 3 })
    end

    local slot = h.canvas:AddChildToCanvas(back)
    slot:SetAutoSize(true)
    slot:SetAnchors({ Minimum = { X = 0, Y = 0.5 }, Maximum = { X = 0, Y = 0.5 } })
    slot:SetAlignment({ X = 0, Y = 0.5 })
    slot:SetPosition({ X = S.legendMargin, Y = 0 })
    host = { uw = h.uw }
    dirty = false
end

function M.show(ctx, S)
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
end

function M.hide()
    if host and W.valid(host.uw) then pcall(function() host.uw:SetVisibility(1) end) end
end

-- Keys changed: rebuild on the next show.
function M.invalidate() dirty = true end
function M.forget() host = nil; dirty = true end

return M
