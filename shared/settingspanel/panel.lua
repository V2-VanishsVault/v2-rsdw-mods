-- The Settings panel itself: one tab per mod taking part, that mod's own tabs under it, its settings in rows.
-- Only the drawing copy (main.lua: the host claim) ever builds it. Ported from Frame Mage's editor/settings.lua.
--
--   toggles flip with a click; choices and numbers step with the arrows either side of their value (the left
--   half steps back, the right half forward); a choice's value itself opens a list of every option; a key row
--   waits for the next key (Escape cancels); buttons do their thing (some ask "Sure?" first). The wheel and the
--   arrows at the bottom page through a long tab; the title bar drags the panel; Escape or the open key close it.
--
-- Every part is placed at a computed position on one canvas (layout below), so the panel always knows where its
-- buttons are without measuring the game's layout.
local game = require("settingspanel.game")
local input = require("settingspanel.input")
local protocol = require("settingspanel.protocol")
local serialize = require("settingspanel.serialize")
local look = require("settingspanel.look")

local M = {}

-- Sizes (UI units) --------------------------------------------------------------------------------------------------
M.SIZE = {
    width = 560, valueWidth = 250, titleH = 32, tabH = 32, rowH = 32, slots = 12, tipLines = 4, footH = 34,
    gap = 6, labelSize = 13, tabSize = 11, titleSize = 13, tipSize = 11, ornament = 9, ornamentGap = 6,
    resetW = 58, switchW = 46, switchH = 22, knob = 16,
}

-- Pure: where a switch's knob sits: at the right when on, the left when off.
function M.knobRect(sw, on, knob)
    local pad = (sw.bottom - sw.top - knob) / 2
    local left = on and (sw.right - pad - knob) or (sw.left + pad)
    return { left = left, top = sw.top + pad, right = left + knob, bottom = sw.top + pad + knob }
end

-- Pure: how many row slots a row takes (a long label or note wraps onto more lines).
function M.linesOf(row, labelWidth, size)
    local text = tostring(row.label or "")
    local kind = row.kind or protocol.kind(row)
    local width = labelWidth
    if kind == "text" then width = labelWidth + M.SIZE.valueWidth + 8 end
    local perLine = math.max(10, math.floor(width / (size * 0.55)))
    return math.max(1, math.min(3, math.ceil(#text / perLine)))
end

-- Pure: rows split into pages of at most `slots` slots, each { row, lines }.
function M.pages(rows, slots, linesOf)
    local pages, cur, used = {}, {}, 0
    for _, r in ipairs(rows) do
        local n = math.min(slots, linesOf(r))
        if used + n > slots and #cur > 0 then pages[#pages + 1] = cur; cur, used = {}, 0 end
        cur[#cur + 1] = { row = r, lines = n }
        used = used + n
    end
    if #cur > 0 or #pages == 0 then pages[#pages + 1] = cur end
    return pages
end

-- Pure: where everything goes, relative to the panel's top left. pad = { left, top, right, bottom }.
-- Returns { w, h, title, modTabs = {rect}, tabs = {rect}, rows = { top, left, right }, tip, prev, close, next }.
-- Pure: the room a tab's label needs (its text, the plate's ornaments and padding).
function M.need(label, size)
    -- (the game's font is wide: about 0.75 of its size per letter; then the ornaments and the plate's rims)
    return math.ceil(#tostring(label or "") * size * 0.75) + 2 * (M.SIZE.ornament + M.SIZE.ornamentGap) + 28
end

-- Pure: the panel's width: wide enough for the mods' tabs and each mod's own tabs in one row each, at least S.width.
-- modTitles: { "Frame Mage", ... }; tabLabels: { { "Look", "Vitals", ... }, ... } per mod.
function M.widthFor(S, pad, modTitles, tabLabels)
    local function row(labels, size)
        local sum = 0
        for _, l in ipairs(labels) do sum = sum + M.need(l, size) end
        return sum + 4 * math.max(0, #labels - 1)
    end
    local inner = row(modTitles, S.tabSize)
    for _, labels in ipairs(tabLabels) do inner = math.max(inner, row(labels, S.tabSize)) end
    return math.max(S.width, inner + pad[1] + pad[3])
end

-- Pure: buttons along a row from x0, `width` wide in all, each as wide as its label needs plus an equal share of
-- what's left: list of { left, right }.
function M.spread(x0, width, labels, size, gap)
    local needs, sum = {}, 0
    for i, l in ipairs(labels) do needs[i] = M.need(l, size); sum = sum + needs[i] end
    local spare = math.max(0, width - sum - gap * math.max(0, #labels - 1)) / math.max(1, #labels)
    local out, x = {}, x0
    for i = 1, #labels do
        local w = needs[i] + spare
        out[i] = { left = x, right = x + w }
        x = x + w + gap
    end
    return out
end

-- titleInset: the title moved down by this much (inside the game window's border, which runs round the top too).
function M.layout(S, pad, modCount, tabCount, width, titleInset)
    local r = function(l, t, w, h) return { left = l, top = t, right = l + w, bottom = t + h } end
    local w = width or S.width
    local inner = w - pad[1] - pad[3]
    local ti = titleInset or 0
    local y = ti + S.titleH + pad[2]
    local out = { w = w, title = r(0, ti, w, S.titleH), modTabs = {}, tabs = {} }
    if modCount > 1 then
        for i, c in ipairs(protocol.cells(inner, modCount, 4)) do out.modTabs[i] = r(pad[1] + c.x, y, c.w, S.tabH) end
        y = y + S.tabH + S.gap
    end
    for i, c in ipairs(protocol.cells(inner, math.max(1, tabCount), 4)) do out.tabs[i] = r(pad[1] + c.x, y, c.w, S.tabH) end
    y = y + S.tabH + S.gap + 2
    out.rows = { top = y, left = pad[1], right = w - pad[3] }
    y = y + S.slots * S.rowH + S.gap
    local tipH = math.ceil(S.tipSize * 1.5 * S.tipLines)
    out.tip = r(pad[1] + 6, y, inner - 12, tipH)
    y = y + tipH + S.gap
    local closeW = 110
    out.prev = r(pad[1], y, 100, S.footH)
    out.close = r(pad[1] + (inner - closeW) / 2, y, closeW, S.footH)
    out.next = r(w - pad[3] - 100, y, 100, S.footH)
    out.h = y + S.footH + pad[4]
    return out
end

-- Pure: a row's parts, for a row starting at slot `slot` taking `lines` slots.
function M.rowRects(L, S, slot, lines, kind)
    local top = L.rows.top + (slot - 1) * S.rowH
    local h = lines * S.rowH
    local row = { left = L.rows.left, top = top, right = L.rows.right, bottom = top + h }
    if kind == "text" then return { row = row, label = { left = row.left + 6, top = top, right = row.right - 6, bottom = top + h } } end
    local vr = row.right - 6
    local vl = vr - S.valueWidth
    local arrow = 16
    -- the value one row high, centered beside a label that wraps onto more lines
    local vt = top + (h - S.rowH) / 2
    local vb = vt + S.rowH
    return {
        row = row,
        label = { left = row.left + 6, top = top, right = vl - 8, bottom = top + h },
        value = { left = vl, top = vt + 1, right = vr, bottom = vb - 1 },
        back = { left = vl, top = vt, right = vl + arrow, bottom = vb },
        plate = { left = vl + arrow + 4, top = vt + 1, right = vr - arrow - 4, bottom = vb - 1 },
        fwd = { left = vr - arrow, top = vt, right = vr, bottom = vb },
        -- a key: an input field, and RESET after it
        field = { left = vl, top = vt + 3, right = vr - M.SIZE.resetW, bottom = vb - 3 },
        reset = { left = vr - M.SIZE.resetW + 6, top = vt + 3, right = vr, bottom = vb - 3 },
        -- on / off: a switch at the right, its state written before it
        switch = { left = vr - M.SIZE.switchW, top = vt + (S.rowH - M.SIZE.switchH) / 2, right = vr,
            bottom = vt + (S.rowH + M.SIZE.switchH) / 2 },
        state = { left = vl, top = vt, right = vr - M.SIZE.switchW - 8, bottom = vb },
    }
end

-- Runtime state -----------------------------------------------------------------------------------------------------

local cfg -- { dir, mod }: the mod this copy ships in
local host -- built widgets: { uw, canvas, full, catcher, parts..., L }
local isOpen = false
local mods = {} -- { name, schema, values, valuesRev, schemaRev }
local modIdx, tabId, page = 1, nil, 1
local drag, capturing, armed, drop
local pending = {} -- [mod][setting] = { id, value }
local nextId = math.floor(os.time() % 100000) * 10 -- (ids only need to grow; a fresh copy starts above old ones)
local ownInput = false -- the panel turned the cursor on (open on its own, not over Frame Mage's editor)
local prefs = { key = "F4" }
local pageRows = {} -- the rows on screen now: { row, rects }
local hookSeen, polledDown = false, false

M.PANEL_MOD = "~Panel" -- the panel's own tab (its open key)

-- Prefs -------------------------------------------------------------------------------------------------------------

local function prefsPath() return cfg.dir .. "config/settingspanel.lua" end

function M.loadPrefs()
    local fromShared = game.get("SettingsPanel.prefs")
    local t = type(fromShared) == "string" and serialize.parse(fromShared, "prefs") or nil
    if type(t) ~= "table" then
        local text = game.read(prefsPath())
        t = text and serialize.parse(text, "settingspanel.lua") or nil
    end
    if type(t) == "table" then for k, v in pairs(t) do prefs[k] = v end end
    if type(prefs.key) ~= "string" or prefs.key == "" then prefs.key = "F4" end
end

local function savePrefs()
    local text = serialize.dump(prefs)
    game.set("SettingsPanel.prefs", text)
    game.set("SettingsPanel.prefsRev", game.getNumber("SettingsPanel.prefsRev") + 1)
    game.write(prefsPath(), "-- The Settings panel's own: its open key, where it was dragged to, the last tab.\n" .. text)
end

function M.openKey() return prefs.key end

-- The mods' data ----------------------------------------------------------------------------------------------------

local function panelSchema()
    return protocol.clean({ protocol = 1, mod = M.PANEL_MOD, title = "Panel", order = 1000,
        tabs = { { id = "panel", label = "Panel" } },
        rows = {
            { tab = "panel", type = "key", setting = "key", label = "Open / close this panel", default = "F4",
                tooltip = "The key that opens this panel, for every mod. Escape closes it too." },
            { tab = "panel", type = "action", action = "center", label = "Put the panel back in the middle" },
        } })
end

-- Re-read the registry and every mod's schema and values (only what changed). true if anything did.
local function reload()
    local changed = false
    local names = protocol.split(game.get("SettingsPanel.registry"))
    local byName = {}
    for _, m in ipairs(mods) do byName[m.name] = m end
    local list = {}
    for _, name in ipairs(names) do
        local m = byName[name] or { name = name }
        local srev = game.getNumber("SettingsPanel." .. name .. ".schemaRev")
        if m.schemaRev ~= srev or not m.schema then
            local text = game.get("SettingsPanel." .. name .. ".schema")
            local raw = type(text) == "string" and serialize.parse(text, name .. " schema") or nil
            local s, notes = protocol.clean(raw)
            if s then
                m.schema = s
                for _, n in ipairs(notes or {}) do game.info("%s: %s", name, n) end
            end
            m.schemaRev = srev
            changed = true
        end
        local vrev = game.getNumber("SettingsPanel." .. name .. ".valuesRev")
        if m.valuesRev ~= vrev then
            local text = game.get("SettingsPanel." .. name .. ".values")
            local v = type(text) == "string" and serialize.parse(text, name .. " values") or nil
            m.values = type(v) == "table" and v or { values = {} }
            m.valuesRev = vrev
            changed = true
            -- a change of ours the mod refused: say why (and show its real value again)
            for setting, p in pairs(pending[name] or {}) do
                local why = protocol.refusal(p.id, m.values)
                if why then
                    pending[name][setting] = nil
                    if M.notify then M.notify(why) end
                end
            end
        end
        if m.schema then list[#list + 1] = m end
    end
    local panelMod = byName[M.PANEL_MOD] or { name = M.PANEL_MOD, schema = panelSchema() }
    panelMod.values = { values = { key = prefs.key } }
    list[#list + 1] = panelMod
    for i = 1, #list do list[i].order, list[i].title = list[i].schema.order, list[i].schema.title end
    protocol.sortMods(list)
    if #list ~= #mods then changed = true end
    mods = list
    return changed
end

local function current() return mods[modIdx] end

local function valueOf(m, row)
    if not row.setting then return nil end
    local p = pending[m.name] and pending[m.name][row.setting]
    if p and protocol.pending(p.id, m.values) then return p.value end
    return m.values and m.values.values and m.values.values[row.setting]
end

local function send(m, req)
    if m.name == M.PANEL_MOD then
        if req.set and req.set.setting == "key" then prefs.key = req.set.value; savePrefs() end
        if req.action == "center" then prefs.x, prefs.y = nil, nil; savePrefs(); M.place() end
        m.values = { values = { key = prefs.key } }
        return
    end
    game.set("SettingsPanel." .. m.name .. ".request", serialize.dump(req))
    game.set("SettingsPanel." .. m.name .. ".requestRev", game.getNumber("SettingsPanel." .. m.name .. ".requestRev") + 1)
end

-- A message in the explanation's place (a key that's taken, a change a mod refused), for a few seconds.
local notice -- { text, at }
M.NOTICE_SECONDS = 6
function M.notify(textOrNil)
    notice = textOrNil and { text = textOrNil, at = game.now() } or nil
end

local function setValue(m, row, value)
    nextId = nextId + 1
    pending[m.name] = pending[m.name] or {}
    pending[m.name][row.setting] = { id = nextId, value = value }
    send(m, protocol.request(nextId, row.setting, value))
end

-- A key for a key row: refused, with the reason shown, when another setting (in any mod) already uses it.
function M.trySetKey(m, row, spec)
    local taken = protocol.keyTakenBy(mods, m.name, row.setting, spec)
    if taken then
        M.notify(("%s is already used: %s. Pick another key, or change that one first."):format(spec, taken))
        return false
    end
    M.notify(nil)
    setValue(m, row, spec)
    return true
end

-- Widgets -----------------------------------------------------------------------------------------------------------

local function place(w, r, z)
    local slot = host.canvas:AddChildToCanvas(w)
    slot:SetAnchors({ Minimum = { X = 0, Y = 0 }, Maximum = { X = 0, Y = 0 } })
    slot:SetAutoSize(false)
    if r then
        slot:SetPosition({ X = r.left, Y = r.top })
        slot:SetSize({ X = r.right - r.left, Y = r.bottom - r.top })
    end
    if z then slot:SetZOrder(z) end
    return slot
end

local function move(slot, r, ox, oy)
    pcall(function()
        slot:SetPosition({ X = (ox or 0) + r.left, Y = (oy or 0) + r.top })
        slot:SetSize({ X = r.right - r.left, Y = r.bottom - r.top })
    end)
end

local n = 0
local function new(cls)
    n = n + 1
    return game.newObject(cls, host.tree, "SP_" .. cls .. "_" .. host.suffix .. "_" .. n)
end

local function text(str, size, color, wrap)
    local t = new("TextBlock")
    t:SetText(FText(str or ""))
    local f = game.gameFont()
    if f then pcall(function() t:SetFont({ FontObject = f.FontObject, TypefaceFontName = f.TypefaceFontName, Size = size }) end) end
    t:SetColorAndOpacity(look.slate(color))
    if wrap then pcall(function() t:SetAutoWrapText(true) end) end
    pcall(function() t:SetVisibility(3) end)
    return t
end

-- A cell: a transparent border holding `content`, aligned (h: 0 fill, 1 left, 2 center, 3 right; v center).
local function cell(content, h)
    local b = new("Border")
    pcall(function() b:SetBrushColor({ R = 0, G = 0, B = 0, A = 0 }) end)
    pcall(function() b:SetPadding({ Left = 0, Top = 0, Right = 0, Bottom = 0 }) end)
    pcall(function() b:SetHorizontalAlignment(h or 1) end)
    pcall(function() b:SetVerticalAlignment(2) end)
    b:SetContent(content)
    pcall(function() b:SetVisibility(3) end)
    return b
end

-- A button's plate: the theme's selected plate (or plain gold / dark), lit or not.
local function paintPlate(border, on, bare)
    local L = host.look
    pcall(function()
        if host.gameWindow and bare then
            border:SetBrushColor({ R = 0, G = 0, B = 0, A = 0 }) -- a tab on the game's window: text and underline only
        elseif host.gameWindow then
            border:SetBrushColor(on and look.color(L.gold) or look.color(L.button))
        elseif L.plain then
            border:SetBrushColor(look.color(on and L.gold or L.button))
        elseif host.plateTex then
            border:SetBrush(look.brush(host.plateTex, "box", L.titleSize[1], L.titleSize[2], { L.titleMargin[1], 0.5 }))
            border:SetBrushColor(on and { R = 1, G = 1, B = 1, A = 1 } or { R = 0.45, G = 0.45, B = 0.45, A = 1 })
        else
            border:SetBrushColor(look.color(on and L.gold or L.button))
        end
    end)
end

-- A button: plate, the theme's ornaments at each end, `content` between them.
local function button(content)
    local b = new("Border")
    pcall(function() b:SetPadding({ Left = 6, Top = 0, Right = 6, Bottom = 0 }) end)
    pcall(function() b:SetHorizontalAlignment(0) end)
    pcall(function() b:SetVerticalAlignment(2) end)
    local row = new("HorizontalBox")
    local function ornament(left)
        if not host.ornamentTex then return end
        local img = new("Image")
        pcall(function()
            img:SetBrush({ ResourceObject = host.ornamentTex, ImageSize = { X = M.SIZE.ornament, Y = M.SIZE.ornament },
                DrawAs = 3, Tiling = 0, TintColor = { SpecifiedColor = { R = 1, G = 1, B = 1, A = 1 }, ColorUseRule = 0 } })
        end)
        local sl = row:AddChildToHorizontalBox(img)
        sl:SetVerticalAlignment(2)
        local g = M.SIZE.ornamentGap
        sl:SetPadding(left and { Left = 0, Top = 0, Right = g, Bottom = 0 } or { Left = g, Top = 0, Right = 0, Bottom = 0 })
    end
    ornament(true)
    local cs = row:AddChildToHorizontalBox(content)
    cs:SetVerticalAlignment(2)
    cs:SetHorizontalAlignment(2)
    pcall(function() cs:SetSize({ SizeRule = 1, Value = 1 }) end)
    ornament(false)
    b:SetContent(row)
    pcall(function() b:SetVisibility(3) end)
    return b
end

local function show(w, on) pcall(function() w:SetVisibility(on and 3 or 1) end) end

local function maxTabs()
    local m = 1
    for _, mod in ipairs(mods) do m = math.max(m, #mod.schema.tabs) end
    return m
end

local function build()
    reload()
    local h = game.host("Settings", 19998)
    host = { uw = h.uw, tree = h.tree, canvas = h.canvas, suffix = h.suffix, full = h.full }
    pcall(function() h.canvas:SetVisibility(4) end) -- (the canvas itself never takes a click: the catcher does)
    local S = M.SIZE
    local L = look.current()
    host.look, host.lookRev = L, look.rev()
    host.plateTex = (not L.plain) and look.texture(L, "plateArt", h.canvas) or nil
    host.ornamentTex = (not L.plain) and look.texture(L, "ornamentArt", h.canvas) or nil
    local pad = L.panelPad or look.PLAIN.panelPad
    local titles, tabLabels = {}, {}
    for i, m in ipairs(mods) do
        titles[i] = m.schema.title
        local labels = {}
        for j, t in ipairs(m.schema.tabs) do labels[j] = t.label end
        tabLabels[i] = labels
    end
    local lay = M.layout(S, pad, #mods, maxTabs(), M.widthFor(S, pad, titles, tabLabels), L.game and L.titleInset or nil)
    -- the mods' tabs, each as wide as its title needs
    local inner = lay.w - pad[1] - pad[3]
    for i, x in ipairs(M.spread(pad[1], inner, titles, S.tabSize, 4)) do
        if lay.modTabs[i] then lay.modTabs[i].left, lay.modTabs[i].right = x.left, x.right end
    end
    host.L = lay
    local whole = { left = 0, top = 0, right = lay.w, bottom = lay.h }

    -- the click catcher: the panel's area (the whole screen while a list is open or the panel is on its own)
    local catcher = new("Image")
    catcher:SetColorAndOpacity({ R = 0, G = 0, B = 0, A = 0 })
    host.catcherSlot = place(catcher, whole, 0)
    catcher:SetVisibility(0)

    -- background: the game's own window (its look without Frame Mage), the theme's stone and frame, or dark glass
    -- with a thin gold edge
    host.bgSlots = {}
    local body = { left = 0, top = lay.title.bottom, right = lay.w, bottom = lay.h }
    local gameWindow
    if L.game then
        for _, cname in ipairs(L.window or {}) do
            local cls = game.classOf(cname)
            gameWindow = cls and game.createWidget(cls, h.uw)
            if gameWindow then
                -- its own size box would keep the inventory's size: ours instead
                pcall(function()
                    local root = gameWindow.WidgetTree.RootWidget
                    root:ClearWidthOverride()
                    root:ClearHeightOverride()
                end)
                pcall(function() gameWindow:SetVisibility(3) end)
                host.bgSlots[#host.bgSlots + 1] = { slot = place(gameWindow, whole, 1), r = whole }
                host.gameWindow = gameWindow
                break
            end
        end
        if not gameWindow then game.info("the game's window couldn't be copied: the plain look instead") end
        host.underline = game.imageResource(L.underline.image, L.underline.resource)
    end
    if gameWindow then
        -- (nothing more: the window is the background)
    elseif L.plain then
        local edge = new("Image")
        edge:SetColorAndOpacity(look.color(L.gold))
        host.bgSlots[#host.bgSlots + 1] = { slot = place(edge, body, 1), r = body }
        local e = L.edge or 2
        local inner = { left = e, top = body.top, right = lay.w - e, bottom = lay.h - e }
        local fill = new("Image")
        fill:SetColorAndOpacity(look.color(L.panelColor))
        host.bgSlots[#host.bgSlots + 1] = { slot = place(fill, inner, 2), r = inner }
        show(edge, true); show(fill, true)
    else
        local fill = new("Image")
        local stone = look.texture(L, "stoneArt", h.canvas)
        if stone then pcall(function() fill:SetBrush(look.brush(stone, "tile", L.stoneTile or 128, L.stoneTile or 128)) end)
        else fill:SetColorAndOpacity(look.color(L.panelColor)) end
        host.bgSlots[#host.bgSlots + 1] = { slot = place(fill, body, 1), r = body }
        show(fill, true)
        local frameTex = look.texture(L, "frameArt", h.canvas)
        if frameTex then
            local fr = new("Image")
            pcall(function() fr:SetBrush(look.brush(frameTex, L.frameDraw or "box", L.frameSize, L.frameSize, L.frameMargin)) end)
            host.bgSlots[#host.bgSlots + 1] = { slot = place(fr, body, 2), r = body }
            show(fr, true)
        end
    end

    -- title bar
    local title = new("Border")
    local titleTex = (not L.plain) and look.texture(L, "titleArt", h.canvas) or nil
    if gameWindow then
        pcall(function() title:SetBrushColor({ R = 0, G = 0, B = 0, A = 0 }) end)
    elseif titleTex then
        pcall(function() title:SetBrush(look.brush(titleTex, "box", L.titleSize[1], L.titleSize[2], { L.titleMargin[1], 0.5 })) end)
    else
        pcall(function() title:SetBrushColor(look.color(L.gold)) end)
    end
    pcall(function() title:SetHorizontalAlignment(2) end)
    pcall(function() title:SetVerticalAlignment(2) end)
    host.titleText = text("SETTINGS", S.titleSize, L.titleInk or L.ink)
    title:SetContent(host.titleText)
    show(title, true)
    host.titleSlot = place(title, lay.title, 3)
    if gameWindow and host.underline then
        local ul = new("Image")
        pcall(function()
            ul:SetBrush({ ResourceObject = host.underline, ImageSize = { X = 32, Y = 32 }, DrawAs = 3, Tiling = 0,
                TintColor = { SpecifiedColor = { R = 1, G = 1, B = 1, A = 1 }, ColorUseRule = 0 } })
        end)
        show(ul, true)
        local r = { left = lay.w * 0.3, top = lay.title.bottom - 3, right = lay.w * 0.7, bottom = lay.title.bottom + 1 }
        host.bgSlots[#host.bgSlots + 1] = { slot = place(ul, r, 3), r = r }
    end

    -- tabs: the mods, then the open mod's own
    local function tabButtons(count, rects)
        local list = {}
        for i = 1, count do
            local t = text("", S.tabSize, L.label)
            local b = button(t)
            list[i] = { border = b, text = t, slot = place(b, rects[i], 3), r = rects[i] }
            if host.gameWindow and host.underline then
                local ul = new("Image")
                pcall(function()
                    ul:SetBrush({ ResourceObject = host.underline, ImageSize = { X = 32, Y = 32 }, DrawAs = 3, Tiling = 0,
                        TintColor = { SpecifiedColor = { R = 1, G = 1, B = 1, A = 1 }, ColorUseRule = 0 } })
                end)
                list[i].underline = ul
                list[i].underlineSlot = place(ul, nil, 4)
                show(ul, false)
            end
        end
        return list
    end
    host.modTabs = tabButtons(#lay.modTabs, lay.modTabs)
    host.tabs = tabButtons(#lay.tabs, lay.tabs)

    -- row slots: each can show any row (re-placed on every paint)
    host.rows = {}
    for i = 1, S.slots do
        local label = text("", S.labelSize, L.label, true)
        local labelCell = cell(label, 0)
        local back = text("<", S.labelSize, L.heading)
        local fwd = text(">", S.labelSize, L.heading)
        local icon = new("Image")
        pcall(function() icon:SetVisibility(1) end)
        local value = text("", S.labelSize, L.ink)
        local line = new("HorizontalBox")
        local is = line:AddChildToHorizontalBox(icon)
        is:SetVerticalAlignment(2)
        is:SetPadding({ Left = 0, Top = 0, Right = 4, Bottom = 0 })
        local vs = line:AddChildToHorizontalBox(value)
        vs:SetVerticalAlignment(2)
        local plate = button(line)
        host.rows[i] = {
            label = label, labelSlot = place(labelCell, nil, 4), labelCell = labelCell,
            back = back, backCell = cell(back, 2), fwd = fwd, fwdCell = cell(fwd, 2),
            plate = plate, value = value, icon = icon,
        }
        local r = host.rows[i]
        r.backSlot = place(r.backCell, nil, 4)
        r.fwdSlot = place(r.fwdCell, nil, 4)
        r.plateSlot = place(plate, nil, 4)
        -- a key's input field: an edge, dark inside, the key's name at its left
        r.fieldEdge = new("Border")
        pcall(function() r.fieldEdge:SetPadding({ Left = 1, Top = 1, Right = 1, Bottom = 1 }) end)
        local inside = new("Border")
        pcall(function() inside:SetBrushColor({ R = 0, G = 0, B = 0, A = 0.6 }) end)
        pcall(function() inside:SetPadding({ Left = 8, Top = 0, Right = 8, Bottom = 0 }) end)
        pcall(function() inside:SetVerticalAlignment(2) end)
        r.fieldText = text("", S.labelSize, L.label)
        inside:SetContent(r.fieldText)
        pcall(function() inside:SetVisibility(3) end)
        r.fieldEdge:SetContent(inside)
        r.fieldSlot = place(r.fieldEdge, nil, 4)
        r.reset = text("RESET", S.tabSize, L.ink)
        r.resetCell = new("Border") -- a small button
        pcall(function() r.resetCell:SetHorizontalAlignment(2) end)
        pcall(function() r.resetCell:SetVerticalAlignment(2) end)
        r.resetCell:SetContent(r.reset)
        r.resetSlot = place(r.resetCell, nil, 4)
        -- an on / off switch: its track, its knob, and the state written before it
        r.track = new("Border") -- its edge: gold, on or off
        pcall(function() r.track:SetPadding({ Left = 2, Top = 2, Right = 2, Bottom = 2 }) end)
        r.trackFill = new("Border")
        pcall(function() r.trackFill:SetVisibility(3) end)
        r.track:SetContent(r.trackFill)
        r.trackSlot = place(r.track, nil, 4)
        r.knob = new("Border")
        r.knobSlot = place(r.knob, nil, 5)
        r.state = text("", S.labelSize, L.label)
        r.stateCell = cell(r.state, 3)
        r.stateSlot = place(r.stateCell, nil, 4)
        for _, w in ipairs({ r.fieldEdge, r.resetCell, r.track, r.knob, r.stateCell }) do show(w, false) end
    end

    host.tip = text("", S.tipSize, L.dim, true)
    host.tipSlot = place(cell(host.tip, 0), lay.tip, 4)
    host.prev = text("<  previous", S.tipSize + 1, L.heading)
    host.prevSlot = place(cell(host.prev, 1), lay.prev, 4)
    host.next = text("next  >", S.tipSize + 1, L.heading)
    host.nextSlot = place(cell(host.next, 3), lay.next, 4)
    local closeText = text("CLOSE", S.titleSize, L.ink)
    host.close = button(closeText)
    paintPlate(host.close, true)
    host.closeSlot = place(host.close, lay.close, 4)
    host.uw:SetVisibility(1)
end

-- Painting ----------------------------------------------------------------------------------------------------------

local function showIcon(img, row, value)
    local name = row.icons and row.icons[value]
    local tex = name and game.gameTexture(name)
    if tex then
        local sz = M.SIZE.labelSize + 5
        pcall(function()
            img:SetBrush({ ResourceObject = tex, ImageSize = { X = sz, Y = sz }, DrawAs = 3, Tiling = 0,
                TintColor = { SpecifiedColor = { R = 1, G = 1, B = 1, A = 1 }, ColorUseRule = 0 } })
            img:SetVisibility(3)
        end)
    else
        pcall(function() img:SetVisibility(1) end)
    end
end

local function labelWidth()
    local lay = host.L
    return (lay.rows.right - lay.rows.left) - M.SIZE.valueWidth - 20
end

local function tabRows()
    local m = current()
    if not m then return {} end
    return protocol.rowsOf(m.schema, tabId)
end

local function pagesNow()
    local lw = labelWidth()
    return M.pages(tabRows(), M.SIZE.slots, function(r) return M.linesOf(r, lw, M.SIZE.labelSize) end)
end

local function paint()
    if not (host and game.valid(host.uw)) then return end
    local L, S, lay = host.look, M.SIZE, host.L
    local ox, oy = host.x or 0, host.y or 0
    -- everything is placed relative to the panel's corner
    move(host.titleSlot, lay.title, ox, oy)
    for _, b in ipairs(host.bgSlots) do move(b.slot, b.r, ox, oy) end
    move(host.tipSlot, lay.tip, ox, oy)
    move(host.closeSlot, lay.close, ox, oy)
    move(host.prevSlot, lay.prev, ox, oy)
    move(host.nextSlot, lay.next, ox, oy)
    if drop then move(host.catcherSlot, { left = 0, top = 0, right = host.sw or 4000, bottom = host.sh or 3000 })
    elseif ownInput then move(host.catcherSlot, { left = 0, top = 0, right = host.sw or 4000, bottom = host.sh or 3000 })
    else move(host.catcherSlot, { left = 0, top = 0, right = lay.w, bottom = lay.h }, ox, oy) end

    local m = current()
    for i, t in ipairs(host.modTabs) do
        local mm = mods[i]
        move(t.slot, t.r, ox, oy)
        show(t.border, mm ~= nil)
        if mm then
            pcall(function() t.text:SetText(FText(mm.schema.title)) end)
            paintPlate(t.border, i == modIdx, true)
            pcall(function() t.text:SetColorAndOpacity(look.slate(i == modIdx and (host.gameWindow and L.heading or L.ink) or L.label)) end)
            if t.underline then
                move(t.underlineSlot, { left = t.r.left + 6, top = t.r.bottom - 4, right = t.r.right - 6, bottom = t.r.bottom }, ox, oy)
                show(t.underline, i == modIdx)
            end
        end
    end
    local tabs = m and m.schema.tabs or {}
    -- the open mod's tabs, each as wide as its label needs
    local labels = {}
    for i, tt in ipairs(tabs) do labels[i] = tt.label end
    local pad = L.panelPad or look.PLAIN.panelPad
    local xs = M.spread(pad[1], lay.w - pad[1] - pad[3], labels, S.tabSize, 4)
    for i, t in ipairs(host.tabs) do
        local tt = tabs[i]
        if xs[i] then t.r = { left = xs[i].left, right = xs[i].right, top = t.r.top, bottom = t.r.bottom } end
        move(t.slot, t.r, ox, oy)
        show(t.border, tt ~= nil and #tabs > 1)
        if tt then
            pcall(function() t.text:SetText(FText(tt.label)) end)
            paintPlate(t.border, tt.id == tabId, true)
            pcall(function() t.text:SetColorAndOpacity(look.slate(tt.id == tabId and (host.gameWindow and L.heading or L.ink) or L.label)) end)
            if t.underline then
                move(t.underlineSlot, { left = t.r.left + 6, top = t.r.bottom - 4, right = t.r.right - 6, bottom = t.r.bottom }, ox, oy)
                show(t.underline, tt.id == tabId)
            end
        end
    end
    pcall(function() host.titleText:SetText(FText(m and (m.schema.title:upper() .. "  SETTINGS") or "SETTINGS")) end)

    local pages = pagesNow()
    page = math.max(1, math.min(page, #pages))
    show(host.prev, page > 1)
    show(host.next, page < #pages)
    pageRows = {}
    local slot = 1
    for _, entry in ipairs(pages[page] or {}) do
        local row, r = entry.row, host.rows[#pageRows + 1]
        if not r then break end
        local rects = M.rowRects(lay, S, slot, entry.lines, row.kind)
        slot = slot + entry.lines
        pageRows[#pageRows + 1] = { row = row, rects = rects, widgets = r }
        move(r.labelSlot, rects.label, ox, oy)
        show(r.labelCell, true)
        pcall(function() r.label:SetText(FText(row.label)) end)
        local readOnly = protocol.readOnly(row, m.values)
        for _, w in ipairs({ r.fieldEdge, r.resetCell, r.track, r.knob, r.stateCell }) do show(w, false) end
        if row.kind == "text" then
            pcall(function() r.label:SetColorAndOpacity(look.slate(row.heading and L.heading or L.dim)) end)
            show(r.plate, false); show(r.backCell, false); show(r.fwdCell, false)
        elseif row.kind == "key" then
            -- an input field: lit while it waits for a key; RESET puts the mod's own default back
            pcall(function() r.label:SetColorAndOpacity(look.slate(readOnly and L.dim or L.label)) end)
            show(r.plate, false); show(r.backCell, false); show(r.fwdCell, false)
            local focused = capturing and capturing.row == row
            local v = valueOf(m, row)
            move(r.fieldSlot, rects.field, ox, oy)
            show(r.fieldEdge, true)
            pcall(function() r.fieldEdge:SetBrushColor(look.color(focused and L.gold or L.dim, focused and 1 or 0.8)) end)
            pcall(function() r.fieldText:SetText(FText(focused and "Press a key..." or tostring(v or ""))) end)
            pcall(function() r.fieldText:SetColorAndOpacity(look.slate(focused and L.dim or L.label)) end)
            local atDefault = row.default == nil or protocol.normKey(v) == protocol.normKey(row.default)
            move(r.resetSlot, rects.reset, ox, oy)
            show(r.resetCell, row.default ~= nil and not readOnly)
            pcall(function() r.resetCell:SetBrushColor(look.color(atDefault and L.button or L.gold)) end)
            pcall(function() r.reset:SetColorAndOpacity(look.slate(atDefault and L.dim or L.ink)) end)
        elseif row.kind == "bool" then
            -- a switch: the knob right and the track lit when on
            pcall(function() r.label:SetColorAndOpacity(look.slate(readOnly and L.dim or L.label)) end)
            show(r.plate, false); show(r.backCell, false); show(r.fwdCell, false)
            local on = valueOf(m, row) == true
            move(r.trackSlot, rects.switch, ox, oy)
            move(r.knobSlot, M.knobRect(rects.switch, on, S.knob), ox, oy)
            pcall(function() r.track:SetBrushColor(look.color(L.gold, readOnly and 0.5 or 1)) end)
            pcall(function() r.trackFill:SetBrushColor(look.color(on and L.gold or L.button, readOnly and 0.5 or 1)) end)
            pcall(function() r.knob:SetBrushColor(look.color(on and L.ink or L.label, readOnly and 0.5 or 1)) end)
            move(r.stateSlot, rects.state, ox, oy)
            pcall(function() r.state:SetText(FText((on and "On" or "Off") .. (row.applies == "restart" and "  *" or ""))) end)
            pcall(function() r.state:SetColorAndOpacity(look.slate(on and L.label or L.dim)) end)
            show(r.track, true); show(r.knob, true); show(r.stateCell, true)
        else
            pcall(function() r.label:SetColorAndOpacity(look.slate(readOnly and L.dim or L.label)) end)
            local stepped = (row.kind == "choice" or row.kind == "number" or row.kind == "slider") and not readOnly
            move(r.backSlot, rects.back, ox, oy); move(r.fwdSlot, rects.fwd, ox, oy)
            show(r.backCell, stepped); show(r.fwdCell, stepped)
            move(r.plateSlot, stepped and rects.plate or rects.value, ox, oy)
            show(r.plate, true)
            local v = valueOf(m, row)
            local shown
            if row.kind == "action" then
                shown = protocol.isArmed(armed, m.name .. ":" .. tostring(row.action), game.now()) and "Sure? Click again" or "Do it"
            else
                shown = protocol.display(row, v)
            end
            if row.applies == "restart" then shown = shown .. "  *" end
            pcall(function() r.value:SetText(FText(shown)) end)
            paintPlate(r.plate, not readOnly)
            pcall(function() r.value:SetColorAndOpacity(look.slate(readOnly and L.label or L.ink)) end)
            showIcon(r.icon, row, v)
        end
    end
    for i = #pageRows + 1, #host.rows do
        local r = host.rows[i]
        show(r.labelCell, false); show(r.plate, false); show(r.backCell, false); show(r.fwdCell, false)
        for _, w in ipairs({ r.fieldEdge, r.resetCell, r.track, r.knob, r.stateCell }) do show(w, false) end
    end
end

-- Pure: the explanation shown for a row (its tooltip; a restart note; a server note).
function M.tipFor(row, values)
    local parts = {}
    if row.tooltip then parts[#parts + 1] = row.tooltip end
    if row.applies == "restart" then parts[#parts + 1] = "* Takes effect after a restart." end
    if protocol.readOnly(row, values) then parts[#parts + 1] = "Set by the server you're playing on." end
    return table.concat(parts, " ")
end

-- Open, close, place ------------------------------------------------------------------------------------------------

function M.place()
    if not host then return end
    local sw, sh = game.screen(host.canvas)
    host.sw, host.sh = sw, sh
    if prefs.x and prefs.y then
        host.x, host.y = protocol.onScreen(prefs.x, prefs.y, sw, sh, host.L.w, host.L.h)
    else
        host.x = math.floor(((sw or 1920) - host.L.w) / 2)
        host.y = math.floor((sh or 1080) * 0.15)
    end
    paint()
end

local function publishBox()
    if not (host and host.x) then return end
    game.set("SettingsPanel.box", protocol.boxString({ left = host.x, top = host.y, right = host.x + host.L.w,
        bottom = host.y + host.L.h }))
end

local function selectMod(i)
    modIdx = math.max(1, math.min(i, #mods))
    local m = current()
    tabId = m and m.schema.tabs[1] and m.schema.tabs[1].id
    if m and prefs.tabs and prefs.tabs[m.name] then
        for _, t in ipairs(m.schema.tabs) do if t.id == prefs.tabs[m.name] then tabId = t.id end end
    end
    page = 1
end

local function closeDrop()
    if drop and drop.root and game.valid(drop.root) then pcall(function() drop.root:RemoveFromParent() end) end
    if drop then publishBox() end
    drop = nil
end

function M.isOpen() return isOpen end
function M.isCapturing() return capturing ~= nil end

function M.open()
    if isOpen then return true end
    -- rebuilt when the look changed (a theme switch in Frame Mage) or the mods did
    if host and (not game.valid(host.uw) or host.lookRev ~= look.rev()) then
        pcall(function() host.uw:RemoveFromParent() end)
        host = nil
    end
    local before = #mods
    reload()
    if host and #mods ~= before then pcall(function() host.uw:RemoveFromParent() end); host = nil end
    if not host then
        local ok, err = pcall(build)
        if not ok then game.warn("the panel could not be built: %s", tostring(err)); host = nil; return false end
    end
    -- the last mod and tab shown
    local want = prefs.mod
    modIdx = 1
    for i, m in ipairs(mods) do if m.name == want then modIdx = i end end
    selectMod(modIdx)
    -- over Frame Mage's editor the editor already has the cursor and the game paused; on its own the panel does it
    ownInput = game.getNumber("FrameMage.editorOpen") ~= 1
    if ownInput then game.setInputMode(true) end
    isOpen = true
    M.place()
    pcall(function() host.uw:SetVisibility(4) end) -- (4: its own canvas lets clicks through; the catcher takes them)
    game.set("SettingsPanel.open", 1)
    publishBox()
    return true
end

function M.close()
    if not isOpen then return end
    closeDrop()
    capturing = nil
    isOpen, drag = false, nil
    if host and game.valid(host.uw) then pcall(function() host.uw:SetVisibility(1) end) end
    -- give the cursor back unless Frame Mage's editor is open round the panel now
    if ownInput and game.getNumber("FrameMage.editorOpen") ~= 1 then game.setInputMode(false) end
    ownInput = false
    game.set("SettingsPanel.open", 0)
    game.set("SettingsPanel.closedAt", game.now())
end

function M.toggle() if isOpen then M.close() else M.open() end end

-- The drop-down list ------------------------------------------------------------------------------------------------

local function openDrop(m, row, rects)
    closeDrop()
    local L, S = host.look, M.SIZE
    local ox, oy = host.x, host.y
    local box = rects.plate
    local entryH = S.rowH
    local w = math.max(box.right - box.left, 120)
    local list = { left = ox + box.left, top = oy + box.bottom + 2 }
    list.right, list.bottom = list.left + w, list.top + entryH * #row.options + 6
    local root = new("CanvasPanel")
    local rs = host.canvas:AddChildToCanvas(root)
    rs:SetAnchors({ Minimum = { X = 0, Y = 0 }, Maximum = { X = 1, Y = 1 } })
    rs:SetOffsets({ Left = 0, Top = 0, Right = 0, Bottom = 0 })
    rs:SetZOrder(50)
    pcall(function() root:SetVisibility(3) end)
    local function at(widget, r)
        local sl = root:AddChildToCanvas(widget)
        sl:SetAnchors({ Minimum = { X = 0, Y = 0 }, Maximum = { X = 0, Y = 0 } })
        sl:SetAutoSize(false)
        sl:SetPosition({ X = r.left, Y = r.top })
        sl:SetSize({ X = r.right - r.left, Y = r.bottom - r.top })
    end
    local bg = new("Image")
    bg:SetColorAndOpacity(look.color(L.panelColor, 0.97))
    show(bg, true)
    at(bg, list)
    local entries = {}
    for i, value in ipairs(row.options) do
        local r = { left = list.left + 3, top = list.top + 3 + (i - 1) * entryH, right = list.right - 3,
            bottom = list.top + 3 + i * entryH }
        local line = new("HorizontalBox")
        local icon = new("Image")
        local is = line:AddChildToHorizontalBox(icon)
        is:SetVerticalAlignment(2)
        is:SetPadding({ Left = 0, Top = 0, Right = 4, Bottom = 0 })
        showIcon(icon, row, value)
        local t = text(protocol.display(row, value), S.labelSize, L.label)
        line:AddChildToHorizontalBox(t):SetVerticalAlignment(2)
        local b = new("Border")
        pcall(function() b:SetPadding({ Left = 8, Top = 0, Right = 8, Bottom = 0 }) end)
        pcall(function() b:SetVerticalAlignment(2) end)
        b:SetContent(line)
        pcall(function() b:SetBrushColor({ R = 0, G = 0, B = 0, A = 0 }) end)
        show(b, true)
        at(b, r)
        entries[i] = { border = b, text = t, value = value, r = r }
    end
    drop = { mod = m, row = row, root = root, entries = entries }
    -- (Frame Mage's editor leaves clicks on the list alone too: the box covers it while it's open)
    game.set("SettingsPanel.box", protocol.boxString({ left = math.min(host.x, list.left), top = host.y,
        right = math.max(host.x + host.L.w, list.right), bottom = math.max(host.y + host.L.h, list.bottom) }))
    paint() -- (the catcher grows to the whole screen: any click closes the list)
end

local function paintDrop(hovered)
    if not drop then return end
    local L = host.look
    local lit = hovered
    if not lit then
        local cur = valueOf(drop.mod, drop.row)
        for i, e in ipairs(drop.entries) do if e.value == cur then lit = i end end
    end
    if lit == drop.lit then return end
    drop.lit = lit
    for i, e in ipairs(drop.entries) do
        if i == lit then
            paintPlate(e.border, true)
            pcall(function() e.text:SetColorAndOpacity(look.slate(L.ink)) end)
        else
            pcall(function() e.border:SetBrushColor({ R = 0, G = 0, B = 0, A = 0 }) end)
            pcall(function() e.text:SetColorAndOpacity(look.slate(L.label)) end)
        end
    end
end

-- Clicks ------------------------------------------------------------------------------------------------------------

local function inPanel(r, x, y) return r and protocol.contains(r, x - host.x, y - host.y) end

local function activate(m, row, rects, x, y)
    if protocol.readOnly(row, m.values) then return end
    local kind = row.kind
    if kind == "choice" and inPanel(rects.plate, x, y) then openDrop(m, row, rects) return end
    if kind == "bool" then
        setValue(m, row, not valueOf(m, row))
    elseif kind == "choice" or kind == "number" or kind == "slider" then
        local v = rects.value
        local dir = (x - host.x < (v.left + v.right) / 2) and -1 or 1
        if kind == "choice" then setValue(m, row, protocol.cycle(row.options, valueOf(m, row), dir))
        else setValue(m, row, protocol.step(row, valueOf(m, row), dir)) end
    elseif kind == "key" then
        if row.default ~= nil and inPanel(rects.reset, x, y) then
            -- RESET: the mod's own key back, and the field let go
            capturing = nil
            if protocol.normKey(valueOf(m, row)) ~= protocol.normKey(row.default) then M.trySetKey(m, row, row.default) end
        elseif inPanel(rects.field, x, y) then
            capturing = { mod = m, row = row }
            input.startCapture()
            M.notify(nil)
        end
    elseif kind == "action" then
        local key = m.name .. ":" .. tostring(row.action)
        if row.confirm and not protocol.isArmed(armed, key, game.now()) then
            armed = { key = key, at = game.now() }
            game.later(protocol.CONFIRM_SECONDS * 1000 + 50, "settingspanel.disarm", function()
                if armed and not protocol.isArmed(armed, armed.key, game.now()) then armed = nil; paint() end
            end)
        else
            armed = nil
            nextId = nextId + 1
            send(m, protocol.actionRequest(nextId, row.action))
        end
    end
    paint()
end

function M.onDown(x, y)
    if not (isOpen and host) then return end
    if drop then
        for _, e in ipairs(drop.entries) do
            if protocol.contains(e.r, x, y) then
                local m, row = drop.mod, drop.row
                closeDrop()
                if e.value ~= valueOf(m, row) then setValue(m, row, e.value) end
                paint()
                return
            end
        end
        closeDrop(); paint()
        return
    end
    local lay = host.L
    if inPanel(lay.title, x, y) then drag = { x0 = x, y0 = y, px = host.x, py = host.y, moved = false } return end
    if capturing then return end
    if inPanel(lay.close, x, y) then M.close() return end
    local pages = pagesNow()
    if page > 1 and inPanel(lay.prev, x, y) then page = page - 1; paint() return end
    if page < #pages and inPanel(lay.next, x, y) then page = page + 1; paint() return end
    for i, t in ipairs(host.modTabs) do
        if mods[i] and inPanel(t.r, x, y) then
            selectMod(i)
            prefs.mod = mods[i].name
            savePrefs()
            paint()
            return
        end
    end
    local m = current()
    local tabs = m and m.schema.tabs or {}
    for i, t in ipairs(host.tabs) do
        if tabs[i] and #tabs > 1 and inPanel(t.r, x, y) then
            tabId, page = tabs[i].id, 1
            prefs.tabs = prefs.tabs or {}
            prefs.tabs[m.name] = tabId
            savePrefs()
            paint()
            return
        end
    end
    for _, pr in ipairs(pageRows) do
        if pr.row.kind ~= "text" and inPanel(pr.rects.row, x, y) then activate(m, pr.row, pr.rects, x, y) return end
    end
end

local function endDrag()
    local moved = drag and drag.moved
    drag = nil -- (first: whatever happens below, the drag is over)
    if moved then
        host.x, host.y = math.floor(host.x + 0.5), math.floor(host.y + 0.5)
        prefs.x, prefs.y = host.x, host.y
        savePrefs()
        publishBox()
        paint()
    end
end

-- Hooks: the game's own UserWidget mouse events, for our catcher (Frame Mage's editor gets clicks the same way).
local hooked = false
local function hookMouse()
    if hooked then return end
    hooked = true
    -- Only Frame Mage's copy hooks the game's mouse events while Frame Mage runs: Frame Mage's editor hooks the same
    -- UserWidget:OnMouseButtonDown, and one hook per function is the safer rule (a crash on 2026-11-14 was first
    -- blamed on a second mod hooking it; it turned out to be something else, but nothing is lost by not hooking
    -- twice). Any other copy then polls the mouse button instead (the fallback in M.tick).
    if cfg and cfg.mod ~= "FrameMage" and game.get("FrameMage.lookRev") ~= nil then
        game.info("Frame Mage is running: clicks are read by polling (no second hook on the game's mouse events)")
        return
    end
    local ok, err = pcall(RegisterHook, "/Script/UMG.UserWidget:OnMouseButtonDown", function(self)
        if not (isOpen and host) then return end
        local okS, full = pcall(function() return self:get():GetFullName() end)
        if not (okS and full == host.full) then return end
        hookSeen = true
        if input.isDown("RightMouseButton") then return end
        local x, y = game.mouse(host.canvas)
        if x then
            local okD, errD = pcall(M.onDown, x, y)
            if not okD then game.warn("click failed: %s", tostring(errD)) end
        end
    end)
    if not ok then game.warn("could not hook mouse clicks (%s); polling the button instead", tostring(err)) end
end

-- Every frame while open ------------------------------------------------------------------------------------------

local lastTip, lastReload, lastEditor = nil, 0, false

function M.tick()
    if not (isOpen and host and game.valid(host.uw)) then
        if isOpen then isOpen = false; game.set("SettingsPanel.open", 0) end
        return
    end
    -- Frame Mage's editor: the panel opened over it closes with it; opened on its own, it keeps the cursor when the
    -- editor (opened round it) closes again
    local editor = game.getNumber("FrameMage.editorOpen") == 1
    if not ownInput and not editor then M.close() return end
    if ownInput and lastEditor and not editor then game.setInputMode(true) end
    lastEditor = editor
    -- Frame Mage's look changed (a theme or background picked in this very panel): rebuilt in it, staying open
    if host.lookRev ~= look.rev() then
        M.close()
        pcall(function() host.uw:RemoveFromParent() end)
        host = nil
        M.open()
        return
    end
    local x, y = game.mouse(host.canvas)
    -- key capture
    if capturing then
        local spec, done = input.pollCapture()
        if done then
            local c = capturing
            capturing = nil
            -- a key that's taken: the field keeps waiting, and the reason shows
            if spec and not M.trySetKey(c.mod, c.row, spec) then capturing = c; input.startCapture() end
            paint()
        end
        return
    end
    if input.pressed("Escape") then
        if drop then closeDrop(); paint() else M.close() end
        return
    end
    -- the click fallback, until a hooked click has been seen
    -- (acted on only if no hooked click arrives for the same press: never twice)
    if not hookSeen then
        local down = input.isDown("LeftMouseButton")
        if down and not polledDown and x then
            local px, py = x, y
            game.later(150, "settingspanel.click", function() if not hookSeen and isOpen then M.onDown(px, py) end end)
        end
        polledDown = down
    end
    -- dragging the title bar
    if drag then
        if not input.isDown("LeftMouseButton") then endDrag()
        elseif x then
            local dx, dy = x - drag.x0, y - drag.y0
            if math.abs(dx) + math.abs(dy) > 3 then drag.moved = true end
            if drag.moved then
                host.x, host.y = protocol.onScreen(drag.px + dx, drag.py + dy, host.sw, host.sh, host.L.w, host.L.h)
                paint()
            end
        end
    end
    -- the wheel pages
    if x and protocol.contains({ left = host.x, top = host.y, right = host.x + host.L.w, bottom = host.y + host.L.h }, x, y) then
        local up, down = input.justPressed("MouseScrollUp"), input.justPressed("MouseScrollDown")
        if (up or down) and not drop then
            local n = #pagesNow()
            local p = math.max(1, math.min(n, page + (up and -1 or 1)))
            if p ~= page then page = p; paint() end
        end
    end
    -- the list: the entry under the pointer lit
    if drop and x then
        local hovered
        for i, e in ipairs(drop.entries) do if protocol.contains(e.r, x, y) then hovered = i break end end
        paintDrop(hovered)
    end
    -- the hovered row's explanation
    local tip = ""
    if notice and game.now() - notice.at > M.NOTICE_SECONDS then notice = nil end
    if notice then
        tip = notice.text
    elseif capturing then
        tip = "Press the key you want for \"" .. tostring(capturing.row.label) .. "\". Esc cancels."
    elseif x and not drop then
        local m = current()
        for _, pr in ipairs(pageRows) do
            if inPanel(pr.rects.row, x, y) then tip = M.tipFor(pr.row, m and m.values) break end
        end
    end
    if tip ~= lastTip then
        lastTip = tip
        pcall(function() host.tip:SetText(FText(tip)) end)
        pcall(function() host.tip:SetColorAndOpacity(look.slate(notice and host.look.heading or host.look.dim)) end)
    end
    -- the mods' values (a change made another way, or a request answered)
    local now = game.now()
    if now - lastReload > 0.25 then
        lastReload = now
        local before = #mods
        if reload() then
            if #mods ~= before then
                -- a mod joined or left: rebuilt with its tab
                M.close()
                if host then pcall(function() host.uw:RemoveFromParent() end) end
                host = nil
                M.open()
            else
                paint()
            end
        end
    end
end

-- Setup -------------------------------------------------------------------------------------------------------------

function M.forget()
    host, isOpen, drag, capturing, drop = nil, false, nil, nil, nil
    input.forget()
    game.forgetInput()
end

function M.init(c)
    cfg = c
    M.loadPrefs()
    hookMouse()
end

return M
