-- Progress-bar style: "flat" (the game's own), "bevel" (3D: a highlight rim, a glossy band and shading) or
-- "facet" (a hard bevel: top and bottom facets meeting in a ridge along the middle, mitred ends).
--
-- The player's bars (health, stamina, special attack) are animated materials, so a PNG can't replace them without
-- freezing their fill. Instead a thin overlay image of ours (the theme's ui/bar_bevel.png or bar_facet.png: white light and black
-- shade only, so it suits every color) is added into each bar's own Overlay, just above the bar image. The fill
-- and its effects keep working underneath. Switching to flat (or turning Frame Mage off) removes the overlays.
--
-- Rings: each bar's icon (stamina, health, special) is shown on a ring (ui/badge_ring.png: a dark disc with a
-- gold hairline), with a soft shadow, sitting OVER the start of its bar so the bar seems to grow out of it. The
-- game doesn't let scripts move widgets between panels (ReplaceChildAt isn't callable), so the game's icon stays
-- where it is, invisible and half a ring wide (the bar then starts under the ring's center), and the ring, its
-- shadow and a copy of the icon go into the bar's own container, drawn above the bar. Switching rings off removes
-- ours and brings the game's icon back.
--
-- Safety: handles are used only within the tick they're found in. Bars are found when their user widget is
-- announced, and re-found by scanning when the style changes.
local measure = require("framemage.core.measure")

local M = {}

local ctx, W, log
local styleBar -- style(barWidget, replace), defined further down
local made = 0

local OVERLAY_PREFIX = "FM_Bevel_"

-- Pure: is this one of the bar widgets we style? (WBP_HUD_Vitals_HealthBar_C, ..._StaminaBar_C, ...) Unit-tested.
function M.isBarClass(cls)
    return cls:match("^WBP_HUD_Vitals_.*Bar_C$") ~= nil
end

-- Pure: is this our overlay (by widget name)? Unit-tested.
function M.isOurs(name) return name:sub(1, #OVERLAY_PREFIX) == OVERLAY_PREFIX end

-- Pure: the overlay art for a style, or nil for flat / unknown styles. Unit-tested.
local ART = { bevel = "ui/bar_bevel.png", facet = "ui/bar_facet.png" }
function M.artFor(style) return ART[style] end

local function on() return ctx.enabled and M.artFor(ctx.settings.bars.style) ~= nil end

-- Pure: is this one of the bar icons that get a ring (by widget name)? Unit-tested.
local ICONS = { StaminaIcon = true, HealthImage = true, SpecialAttackImage = true }
function M.isIcon(name) return ICONS[name] == true end

local RING_BOX = "FM_RingBox_"
-- Pure: is this our ring box (by widget name)? Unit-tested.
function M.isRingBox(name) return name:sub(1, #RING_BOX) == RING_BOX end

local function badgesOn() return ctx.enabled and ctx.settings.bars.badges == true end
-- Our bar look (slimmer, dark track, gold edge, shading) is on whenever Frame Mage is; "Shaped bars" only adds the
-- pointed end. (Defined up here: the row spacing below uses it.)
local function lookOn() return ctx.enabled == true end

local function childIndex(panel, child)
    local ok, i = pcall(function() return panel:GetChildIndex(child) end)
    if ok and type(i) == "number" and i >= 0 then return i end
    return nil
end

local warnedWrap = false

-- The bar's own container: the Overlay that follows the icon in its row (it holds the bar and its value text).
local function barHolderAfter(row, icon)
    local idx = childIndex(row, icon)
    if not idx then return nil end
    for i, c in ipairs(W.children(row)) do
        if i - 1 > idx then
            local ok, cls = pcall(W.className, c)
            if ok and cls == "Overlay" then return c end
        end
    end
    return nil
end

local iconSizes = {} -- icon widget name -> its brush size
local holderPads = {} -- icon widget name -> its bar container's slot padding (to restore)

local function margin(m)
    return { Left = m.Left, Top = m.Top, Right = m.Right, Bottom = m.Bottom }
end

-- A game texture by name (the Agility icon for stamina, bars.iconOverrides), from the art feature, which remembers
-- where textures live between sessions.
local function gameTexture(name)
    local art = ctx.features.art
    return art and art.gameTexture and art.gameTexture(name) or nil
end

-- The game's icon, hidden for good but keeping its place: the game lines its three bars up through each icon's own
-- size and padding (they differ), so the icon stays in the layout, hidden (space kept) and scaled to nothing, so
-- when the game re-shows it (its animations do, many times a second) it still draws nothing.
local function hideGameIcon(icon)
    pcall(function() icon:SetVisibility(2) end) -- hidden: its space kept
    pcall(function() icon:SetRenderScale({ X = 0, Y = 0 }) end)
end

local function showGameIcon(icon)
    pcall(function() icon:SetRenderScale({ X = 1, Y = 1 }) end)
end

local ringIcons = {} -- game icon widget name -> { copy = our icon on the ring, override = texture name, done = bool }

local function ringBoxIn(holder)
    for _, c in ipairs(W.children(holder)) do
        local ok, n = pcall(W.name, c)
        if ok and M.isRingBox(n) then return c end
    end
    return nil
end

local function wrapIcon(icon)
    local okI, iconName = pcall(W.name, icon)
    local row = W.parent(icon)
    local holder = row and barHolderAfter(row, icon)
    if not (okI and holder) or ringBoxIn(holder) then return end
    local owner = W.owner(icon)
    local tree = owner and owner.WidgetTree
    local art = ctx.features.art
    local path = ctx.themes.find("ui/badge_ring.png")
    local tex = tree and art and path and art.loadFile(path, owner)
    if not tex then return end
    local B = ctx.settings.bars
    local size = B.ringSize
    -- the game's icon: invisible, and half a ring wide so the bar starts under the ring's center
    local okT, iconTex = pcall(function() return icon.Brush.ResourceObject end)
    if not iconSizes[iconName] then
        pcall(function()
            local sz = icon.Brush.ImageSize
            iconSizes[iconName] = { X = sz.X, Y = sz.Y }
        end)
    end
    local orig = iconSizes[iconName] or { X = 33, Y = 33 }
    -- the game's icon: hidden in place (the caps tick keeps it so, as the game re-shows it); the ring is centered on
    -- the start of the bar, its left half over the icon's old place
    hideGameIcon(icon)
    made = made + 1
    local box = StaticConstructObject(StaticFindObject("/Script/UMG.Overlay"), tree, FName(RING_BOX .. made))
    local function centered(w)
        local sl = box:AddChildToOverlay(w)
        sl:SetHorizontalAlignment(2)
        sl:SetVerticalAlignment(2)
        w:SetVisibility(3)
    end
    -- a soft shadow under the ring, falling right and down onto the bar
    local shadowPath = B.ringShadow and ctx.themes.find("ui/badge_shadow.png")
    local shadowTex = shadowPath and art.loadFile(shadowPath, owner)
    if shadowTex then
        local sh = StaticConstructObject(StaticFindObject("/Script/UMG.Image"), tree, FName("FM_RingShadow_" .. made))
        local ss = size * 160 / 112 -- the shadow art is 160 px to the ring's 112
        art.guarded(function()
            sh:SetBrush({ ResourceObject = shadowTex, ImageSize = { X = ss, Y = ss }, DrawAs = 3,
                TintColor = { SpecifiedColor = { R = 1, G = 1, B = 1, A = 1 }, ColorUseRule = 0 } })
        end)
        pcall(function() sh:SetDesiredSizeOverride({ X = ss, Y = ss }) end)
        centered(sh)
        pcall(function() sh:SetRenderTranslation({ X = B.shadowOffsetX, Y = B.shadowOffsetY }) end)
        pcall(function() sh:SetRenderOpacity(B.shadowOpacity) end)
    end
    local ring = StaticConstructObject(StaticFindObject("/Script/UMG.Image"), tree, FName("FM_Ring_" .. made))
    art.guarded(function()
        ring:SetBrush({ ResourceObject = tex, ImageSize = { X = size, Y = size }, DrawAs = 3,
            TintColor = { SpecifiedColor = { R = 1, G = 1, B = 1, A = 1 }, ColorUseRule = 0 } })
    end)
    pcall(function() ring:SetDesiredSizeOverride({ X = size, Y = size }) end)
    centered(ring)
    -- a copy of the game's icon on the ring (same texture and color, a little smaller), or another game icon
    -- chosen in bars.iconOverrides (stamina: the Agility skill's running figure)
    local override = B.iconOverrides and B.iconOverrides[iconName]
    local alt = override and gameTexture(override)
    if alt then iconTex, okT = alt, true end
    if okT and W.valid(iconTex) then
        local copy = StaticConstructObject(StaticFindObject("/Script/UMG.Image"), tree, FName("FM_RingIcon_" .. made))
        art.guarded(function() copy:SetBrushFromTexture(iconTex, false) end)
        -- the game's icon textures are a little taller than wide (52x56): keep their proportions, so the glyph
        -- isn't squashed upward, then nudge it to sit in the ring's center
        local h = orig.Y * B.iconScale
        local w = h
        pcall(function()
            local tx, ty = iconTex:Blueprint_GetSizeX(), iconTex:Blueprint_GetSizeY()
            if tx > 0 and ty > 0 then w = h * tx / ty end
        end)
        pcall(function() copy:SetDesiredSizeOverride({ X = w, Y = h }) end)
        -- (the nudge suits the game's own 52x56 icons; a substituted icon - square, its glyph centered - needs none)
        pcall(function() copy:SetRenderTranslation({ X = 0, Y = alt and 0 or B.iconNudgeY }) end)
        pcall(function()
            local c = icon.ColorAndOpacity
            copy:SetColorAndOpacity({ R = c.R, G = c.G, B = c.B, A = c.A })
        end)
        centered(copy)
        ringIcons[iconName] = { copy = copy, override = override, done = alt ~= nil }
    end
    local hs = holder:AddChildToOverlay(box) -- last in the bar's container: drawn above the bar
    hs:SetHorizontalAlignment(1)
    hs:SetVerticalAlignment(2)
    -- center the ring on the start of the bar: the box is as wide as its widest layer (the shadow), the ring sits
    -- in its middle
    local boxW = size
    if shadowTex then boxW = math.max(size, size * 160 / 112) end
    pcall(function() box:SetRenderTranslation({ X = -boxW / 2, Y = 0 }) end)
end

local function unwrapIcon(icon)
    local okI, iconName = pcall(W.name, icon)
    local row = W.parent(icon)
    local holder = row and barHolderAfter(row, icon)
    -- every ring of ours in the bar (more than one could be left from a rebuild: one left behind showed the stamina
    -- ring's Agility icon under the game's own once the rings were switched off)
    for _ = 1, 4 do
        local box = holder and ringBoxIn(holder)
        if not box then break end
        pcall(function() box:RemoveFromParent() end)
    end
    pcall(function() icon:SetRenderOpacity(1) end)
    if okI then
        showGameIcon(icon)
        ringIcons[iconName] = nil
    end
    pcall(function() icon:SetVisibility(4) end) -- back (self-hit-test-invisible, as the game has it)
    local hp = okI and holderPads[iconName]
    if holder and hp then pcall(function() holder.Slot:SetPadding(hp) end) end
end

local originalPad = {} -- bar widget name -> its slot padding before spacing was added
local extraTop = {} -- bar widget name -> a correction (UI units) so each row sits exactly rowPitch below the last
local loggedRow = {} -- bar widget name -> its row measurements have been logged

-- Pure: the padding above and below one bar so its row (padding + the bar's own height) is exactly `pitch` tall.
-- origTop / origBottom = the game's own padding, which the difference is shared on top of; the result can be
-- negative (the bar's own height includes the hidden game icon's box, which can be taller than the row we want).
-- Unit-tested.
function M.rowPadding(rowHeight, pitch, origTop, origBottom)
    origTop, origBottom = origTop or 0, origBottom or 0
    local extra = (pitch - rowHeight - origTop - origBottom) / 2
    return origTop + extra, origBottom + extra
end

local function space(barWidget)
    local okN, n = pcall(W.name, barWidget)
    local okS, slot = pcall(function() return barWidget.Slot end)
    if not (okN and okS and slot and W.valid(slot)) then return end
    pcall(function()
        if not originalPad[n] then
            local p = slot.Padding
            originalPad[n] = { Left = p.Left, Top = p.Top, Right = p.Right, Bottom = p.Bottom }
        end
        local o = originalPad[n]
        local top, bottom = o.Top, o.Bottom
        if lookOn() then -- the same spacing with or without rings, so the bars never close up
            local h = 0
            pcall(function()
                barWidget:ForceLayoutPrepass()
                h = barWidget:GetDesiredSize().Y
            end)
            -- every row the same height (bars.rowPitch), whether it has a ring, a ring with a shadow or neither
            if h > 0 then
                top, bottom = M.rowPadding(h, ctx.settings.bars.rowPitch, o.Top, o.Bottom)
                if not loggedRow[n] then
                    loggedRow[n] = true
                    log.info("bars: %s row: own height %.1f, game padding %.1f / %.1f -> %.1f / %.1f (pitch %d)",
                        n, h, o.Top, o.Bottom, top, bottom, ctx.settings.bars.rowPitch)
                end
            end
        end
        slot:SetPadding({ Left = o.Left, Top = top + (extraTop[n] or 0), Right = o.Right, Bottom = bottom })
    end)
end

-- Pure: the correction to add to the first row (of tops, in order) that isn't rowPitch below the one before it;
-- returns its index and the amount, or nil when every row is in place (within half a unit). One row at a time: a
-- row's correction moves every row below it too. Unit-tested.
function M.spacingFix(tops, pitch)
    for i = 2, #tops do
        local d = tops[1] + (i - 1) * pitch - tops[i]
        if math.abs(d) > 0.5 then return i, d end
    end
    return nil
end

local BAR_ORDER = { "WBP_HUD_Vitals_StaminaBar_C", "WBP_HUD_Vitals_HealthBar_C", "WBP_HUD_Vitals_SpecialChargeBar_C" }

-- The game's rows aren't all padded alike (the health and special rows sit closer than stamina and health), so
-- after spacing each bar, measure where the three actually are and correct the first one that's off.
local function evenRows()
    if not lookOn() then return end
    local bars, tops = {}, {}
    for _, cls in ipairs(BAR_ORDER) do
        for _, b in pairs(FindAllOf(cls) or {}) do
            if W.valid(b) and W.isInstance(b) and W.isVisible(b) then bars[#bars + 1] = b break end
        end
    end
    if #bars ~= 3 then return end
    for i, b in ipairs(bars) do
        local r = measure.layoutRect(b)
        if not r then return end
        tops[i] = r.top
    end
    local i, d = M.spacingFix(tops, ctx.settings.bars.rowPitch)
    if not i then return end
    local okN, n = pcall(W.name, bars[i])
    if not okN then return end
    extraTop[n] = (extraTop[n] or 0) + d
    space(bars[i])
    measure.invalidate()
    log.info("bars: %s row moved %.1f so the rows are evenly spaced", n, d)
end

local function applyBadges(barWidget, rebuild)
    W.walk(barWidget, function(w)
        local okN, n = pcall(W.name, w)
        if not (okN and M.isIcon(n)) then return true end
        if rebuild then unwrapIcon(w) end -- a settings change: rebuild the ring (shadow on / off, size)
        if badgesOn() then wrapIcon(w) else unwrapIcon(w) end
        return false
    end, 0, 16)
end

local function childNamed(panel, test)
    for _, c in ipairs(W.children(panel)) do
        local ok, n = pcall(W.name, c)
        if ok and test(n) then return c end
    end
    return nil
end

-- The bar images in one bar widget: the Images named ProgressBarImage (the material fill).
local function barImages(barWidget)
    local out = {}
    W.walk(barWidget, function(w)
        local okN, n = pcall(W.name, w)
        if okN and n == "ProgressBarImage" then out[#out + 1] = w return false end
        return true
    end, 0, 12)
    return out
end

-- Shape: slimmer bars with a pointed right end, in two parts that meet exactly:
--   the body: the bar's own box, ended short by the point's length; its frame draws our dark track, the game's fill
--   runs inside it, and (by style) a shading overlay and the gold edge are stretched over it;
--   the point: one fixed-size box of ours beside it holding the point's dark track, its color (shown when the bar
--   is full), its shading and its gold edges, each simply stretched to the box.
-- (9-slicing the point into one long image was tried first: the game sized the slices unpredictably.)

local function taperOn() return ctx.enabled and ctx.settings.bars.taper == true end

-- Pure: the shaped bar's height from the game's: a few units taller, then scaled. Unit-tested.
-- Pure: the game height a bar is sized from: its own, or (same = true) the tallest bar's seen so far. Unit-tested.
local tallest = 0
function M.rawHeight(own, tallestSeen, same)
    if not own or own <= 0 then return nil end
    if same then return math.max(own, tallestSeen or 0) end
    return own
end

function M.barHeight(gameHeight, extra, scale)
    return math.floor((gameHeight + (extra or 0)) * (scale or 1) + 0.5)
end

-- Pure: the shading art for a style: the body of a shaped bar, or a whole plain bar (nil for flat). Unit-tested.
local BODY = { bevel = "ui/bar_bevel_body.png", facet = "ui/bar_facet_body.png" }
function M.overlayArt(style, shaped)
    if shaped then return BODY[style] end
    return ART[style]
end

-- Pure: the point's shading for a style (nil for flat). Unit-tested.
local TIP = { bevel = "ui/bar_tip_bevel.png", facet = "ui/bar_tip_facet.png" }
function M.tipArt(style) return TIP[style] end

-- Pure: the art for a bar's end: the point (shaped) or a flat end. Unit-tested.
local END_SHADE = { bevel = "ui/bar_end_bevel.png", facet = "ui/bar_end_facet.png" }
function M.endArt(style, pointed)
    if pointed then
        return { track = "ui/bar_tip_track.png", cap = "ui/bar_cap.png", shade = TIP[style], outline = "ui/bar_tip_outline.png" }
    end
    return { track = "ui/bar_end_track.png", cap = "ui/bar_end_cap.png", shade = END_SHADE[style],
        outline = "ui/bar_end_outline.png" }
end

-- Pure: how long the end piece is (UI units). Unit-tested.
function M.endWidth(B, pointed)
    if pointed then return B.taperWidth end
    return B.endWidth or 3
end

local TIP_PREFIX, TIP_COLOR = "FM_Tip_", "FM_TipColor_"
-- Pure: is this our point box (by widget name)? Unit-tested.
function M.isTip(name) return name:sub(1, #TIP_PREFIX) == TIP_PREFIX end

-- Pure: is a bar full, from its value text's numbers? No numbers (the text hidden, as stamina's is when full)
-- counts as full. Unit-tested.
function M.isFull(cur, max)
    if cur == nil or max == nil then return true end
    return max > 0 and cur >= max
end

-- Pure: current and max from a bar's value text ("200 / 200", "4/100"), or nil. Unit-tested.
function M.parseValue(text)
    if type(text) ~= "string" then return nil end
    local cur, max = text:match("(%d+)%s*/%s*(%d+)")
    if not cur then return nil end
    return tonumber(cur), tonumber(max)
end

-- Pure: the point's color from the bar material's main color. The material draws brighter than its main color,
-- so the point is brightened to match: color * gain + lift, each channel at most 1. Unit-tested.
function M.tipColor(c, gain, lift)
    gain, lift = gain or 1, lift or 0
    local function ch(v) return math.min(1, v * gain + lift) end
    return { R = ch(c.R), G = ch(c.G), B = ch(c.B), A = c.A or 1 }
end

local FALLBACK_COLOR = { HealthBar = { R = 0.578, G = 0.016, B = 0.023, A = 1 },
    StaminaBar = { R = 0.70, G = 0.48, B = 0.02, A = 1 }, SpecialChargeBar = { R = 0.023, G = 0.153, B = 0.631, A = 1 } }

local shaped = {} -- bar widget name -> the game's values, to restore

local function ancestor(w, cls, limit)
    local cur = W.parent(w)
    for _ = 1, limit or 6 do
        if not cur then return nil end
        local ok, c = pcall(W.className, cur)
        if ok and c == cls then return cur end
        cur = W.parent(cur)
    end
    return nil
end

local function barColor(img, barName)
    local ok, c = pcall(function()
        local mid = img.Brush.ResourceObject
        local v = mid:GetVectorParameterValue(FName("Health Bar Main Color"))
        return { R = v.R, G = v.G, B = v.B, A = 1 }
    end)
    if ok and c and type(c.R) == "number" and (c.R + c.G + c.B) > 0.01 then return c end
    return FALLBACK_COLOR[barName] or { R = 0.5, G = 0.5, B = 0.5, A = 1 }
end

-- The pieces of one bar: its fill image, the container around it, its frame, its size box and the box's container.
local function parts(barWidget)
    local img = barImages(barWidget)[1]
    local fillPanel = img and W.parent(img)
    local okP, pcls = pcall(W.className, fillPanel)
    if not (img and okP and pcls == "Overlay") then return nil end
    local border = ancestor(img, "Border")
    local box = border and ancestor(border, "SizeBox", 2)
    local holder = box and W.parent(box)
    local okH, hcls = pcall(W.className, holder)
    if not (border and box and okH and hcls == "Overlay") then return nil end
    return img, fillPanel, border, box, holder
end

local function plainBrush(tex)
    return { ResourceObject = tex, ImageSize = { X = 32, Y = 32 }, DrawAs = 3, Tiling = 0,
        TintColor = { SpecifiedColor = { R = 1, G = 1, B = 1, A = 1 }, ColorUseRule = 0 } }
end

local function stretchedImage(tree, art, owner, file, name)
    local path = ctx.themes.find(file)
    local tex = path and art.loadFile(path, owner)
    if not tex then return nil end
    local img = StaticConstructObject(StaticFindObject("/Script/UMG.Image"), tree, FName(name))
    art.guarded(function() img:SetBrush(plainBrush(tex)) end)
    img:SetVisibility(3)
    return img
end

-- Pure: the strips that build a bar's end out of its material: { v0, v1, w } from top to bottom, v = the band of
-- the bar's height (0..1), w = the strip's length as a fraction of the end's. A point narrows evenly from full
-- length at its middle to nothing at its top and bottom; a flat end is one full strip. Unit-tested.
function M.tipStrips(n, pointed)
    if not pointed then return { { v0 = 0, v1 = 1, w = 1 } } end
    local out = {}
    for i = 0, n - 1 do
        local v0, v1 = i / n, (i + 1) / n
        local c = (v0 + v1) / 2
        out[#out + 1] = { v0 = v0, v1 = v1, w = 1 - math.abs(c - 0.5) * 2 }
    end
    return out
end

-- Pure: how much the bar's own paint is stretched (from its left edge, clipped at the body's end) so it and the
-- end's copy are one stripe of paint across body + end: the paint has a bright final column (its glow), and with
-- different stretches the body's glow showed as a line where the end began. Unit-tested.
function M.paintStretch(bodyWidth, length)
    if not (bodyWidth and bodyWidth > 0) then return 1 end
    return (bodyWidth + (length or 0)) / bodyWidth
end

-- The body's paint stretched over body + end and clipped at the body's end (scale 1: back to the game's own).
local function stretchPaint(img, fillPanel, rec, scale)
    if rec.clip == nil then pcall(function() rec.clip = fillPanel.Clipping end) end
    pcall(function() img:SetRenderTransformPivot({ X = 0, Y = 0.5 }) end)
    pcall(function() img:SetRenderScale({ X = scale, Y = 1 }) end)
    local clip = scale ~= 1 and 1 or (rec.clip or 0)
    pcall(function() fillPanel.Clipping = clip end)
    pcall(function() fillPanel:SetClipping(clip) end)
end

-- Pure: where the full-size copy of the bar sits inside one strip of the end (strip-local UI units): the copy
-- spans the body and the end (bodyWidth + length), so its left edge is bodyWidth left of the strip and its top is
-- the strip's band of the height above it. Unit-tested.
function M.copyPlacement(bodyWidth, length, height, v0)
    return { x = -bodyWidth, y = -height * v0, w = bodyWidth + length, h = height }
end

local warnedStrips = false
-- The end's color layer: a column of thin strips, each clipped to its own piece of the end's shape and holding a
-- copy of the bar's paint at the bar's full size, placed where the bar would continue. (Cropping the material to a
-- tiny image drew nothing in game; a full-size copy draws like the bar itself, and plain clipping cuts it.)
local function materialStrips(tree, mat, height, length, pointed, B, bodyWidth)
    if not (height and height > 0 and bodyWidth and bodyWidth > 0) then return nil end
    local ok, box = pcall(function()
        made = made + 1
        local col = StaticConstructObject(StaticFindObject("/Script/UMG.VerticalBox"), tree, FName(TIP_COLOR .. made))
        local n = math.max(4, math.floor(height / (B.tipStripHeight or 1) + 0.5))
        for i, s in ipairs(M.tipStrips(n, pointed)) do
            local sb = StaticConstructObject(StaticFindObject("/Script/UMG.SizeBox"), tree, FName("FM_TipStrip_" .. made .. "_" .. i))
            sb:SetHeightOverride(height * (s.v1 - s.v0))
            sb:SetWidthOverride(math.max(0, length * s.w))
            pcall(function() sb.Clipping = 1 end)
            pcall(function() sb:SetClipping(1) end) -- clip to bounds: only this strip's piece of the copy shows
            if s.w > 0 then
                local canvas = StaticConstructObject(StaticFindObject("/Script/UMG.CanvasPanel"), tree, FName("FM_TipCanvas_" .. made .. "_" .. i))
                local im = StaticConstructObject(StaticFindObject("/Script/UMG.Image"), tree, FName("FM_TipBand_" .. made .. "_" .. i))
                im:SetBrush({ ResourceObject = mat, ImageSize = { X = 32, Y = 32 }, DrawAs = 3, Tiling = 0,
                    TintColor = { SpecifiedColor = { R = 1, G = 1, B = 1, A = 1 }, ColorUseRule = 0 } })
                im:SetVisibility(3)
                local p = M.copyPlacement(bodyWidth, length, height, s.v0)
                local cs = canvas:AddChildToCanvas(im)
                cs:SetAutoSize(false)
                cs:SetPosition({ X = p.x, Y = p.y })
                cs:SetSize({ X = p.w, Y = p.h })
                canvas:SetVisibility(3)
                sb:SetContent(canvas)
            end
            local sl = col:AddChildToVerticalBox(sb)
            sl:SetHorizontalAlignment(1) -- left: the strip starts where the body ends
        end
        col:SetVisibility(1) -- shown once the bar is known to be full (as the matched color is)
        return col
    end)
    if ok then return box end
    if not warnedStrips then
        warnedStrips = true
        log.warn("bars: couldn't paint the bar ends from the material (%s); using a plain color", tostring(box))
    end
    return nil
end

local function shape(barWidget)
    local okN, barName = pcall(W.name, barWidget)
    local img, fillPanel, border, box, holder = parts(barWidget)
    if not (okN and img and fillPanel and border and box and holder) then return end
    local art = ctx.features.art
    local owner = W.owner(img)
    local tree = owner and owner.WidgetTree
    if not (art and tree) then return end
    local B = ctx.settings.bars
    local rec = shaped[barName]
    if not rec then
        rec = {}
        pcall(function() rec.height = box.bOverride_HeightOverride and box.HeightOverride or nil end)
        if not rec.height then pcall(function() rec.height = box:GetDesiredSize().Y end) end
        pcall(function() rec.pad = margin(border.Padding) end)
        pcall(function() rec.boxPad = margin(box.Slot.Padding) end)
        pcall(function() rec.valign = box.Slot.VerticalAlignment end)
        pcall(function() rec.halign = box.Slot.HorizontalAlignment end)
        pcall(function()
            local b = border.Background
            local t = b.TintColor.SpecifiedColor
            rec.brush = { ResourceObject = b.ResourceObject, ImageSize = { X = b.ImageSize.X, Y = b.ImageSize.Y },
                DrawAs = b.DrawAs, Tiling = b.Tiling, Margin = margin(b.Margin),
                TintColor = { SpecifiedColor = { R = t.R, G = t.G, B = t.B, A = t.A }, ColorUseRule = 0 } }
        end)
        shaped[barName] = rec
    end
    -- (every bar as tall as the tallest: the game makes the special bar slimmer than stamina and health)
    if rec.height and rec.height > 0 then tallest = math.max(tallest, rec.height) end
    local raw = M.rawHeight(rec.height, tallest, B.sameHeight ~= false)
    local height = raw and M.barHeight(raw, B.extraHeight, B.heightScale) or nil
    -- the body: its height, centered in its container, ended short by the point's length
    if height then pcall(function() box:SetHeightOverride(height) end) end
    pcall(function() box.Slot:SetVerticalAlignment(2) end)
    pcall(function() box.Slot:SetHorizontalAlignment(0) end) -- fill: the body always reaches the point
    local bp = rec.boxPad or { Left = 0, Top = 0, Right = 0, Bottom = 0 }
    local pointed = taperOn()
    pcall(function()
        box.Slot:SetPadding({ Left = bp.Left, Top = bp.Top, Right = bp.Right + M.endWidth(B, pointed), Bottom = bp.Bottom })
    end)
    -- the body's dark track (the frame's background), edge to edge with the fill
    local trackPath = ctx.themes.find("ui/bar_track_body.png")
    local track = trackPath and art.loadFile(trackPath, owner)
    if track then art.guarded(function() border:SetBrush(plainBrush(track)) end) end
    pcall(function() border:SetPadding({ Left = 0, Top = 0, Right = 0, Bottom = 0 }) end)
    -- the end, beside the body: the point, or (shaped bars off) a narrow flat end with a closing gold line
    if childNamed(holder, M.isTip) then return end
    local endArt = M.endArt(B.style, pointed)
    made = made + 1
    local tip = StaticConstructObject(StaticFindObject("/Script/UMG.SizeBox"), tree, FName(TIP_PREFIX .. made))
    tip:SetWidthOverride(M.endWidth(B, pointed))
    if height then tip:SetHeightOverride(height) end
    local stack = StaticConstructObject(StaticFindObject("/Script/UMG.Overlay"), tree, FName("FM_TipStack_" .. made))
    local function layer(w)
        if not w then return end
        local sl = stack:AddChildToOverlay(w)
        sl:SetHorizontalAlignment(0)
        sl:SetVerticalAlignment(0)
    end
    layer(stretchedImage(tree, art, owner, endArt.track, "FM_TipTrack_" .. made))
    -- the end's color: the bar's own paint continued past its end (clipped full-size copies), or a shape in the
    -- bar's main color; either shown once the bar is full
    local okM, mat = pcall(function() return img.Brush.ResourceObject end)
    local bodyWidth
    pcall(function()
        box:ForceLayoutPrepass()
        bodyWidth = box:GetDesiredSize().X
    end)
    if not rec.loggedWidth then
        rec.loggedWidth = true
        log.info("bars: %s body %.1f x %.1f, end %d (point color: %s)", barName, bodyWidth or -1, height or -1,
            M.endWidth(B, pointed), tostring(B.tipPaint))
    end
    local strips = okM and W.valid(mat) and B.tipPaint ~= "solid"
        and materialStrips(tree, mat, height, M.endWidth(B, pointed), pointed, B, bodyWidth)
    stretchPaint(img, fillPanel, rec, strips and M.paintStretch(bodyWidth, M.endWidth(B, pointed)) or 1)
    if strips then
        layer(strips)
    else
        local color = stretchedImage(tree, art, owner, endArt.cap, TIP_COLOR .. made)
        if color then
            color:SetColorAndOpacity(M.tipColor(barColor(img, barName), B.tipGain, B.tipLift))
            color:SetVisibility(1) -- shown once the bar is known to be full
            layer(color)
        end
    end
    if endArt.shade then layer(stretchedImage(tree, art, owner, endArt.shade, "FM_TipShade_" .. made)) end
    if B.outline then layer(stretchedImage(tree, art, owner, endArt.outline, "FM_TipEdge_" .. made)) end
    tip:SetContent(stack)
    local slot = holder:AddChildToOverlay(tip)
    slot:SetHorizontalAlignment(3) -- right: where the body ends short
    slot:SetVerticalAlignment(2)
    tip:SetVisibility(3)
end

local function addOverlay(img)
    local parent = W.parent(img)
    if not parent then return end
    local okC, cls = pcall(W.className, parent)
    if not (okC and cls == "Overlay") then return end
    if childNamed(parent, M.isOurs) then return end
    local owner = W.owner(img)
    local tree = owner and owner.WidgetTree
    local art = ctx.features.art
    if not (tree and art) then return end
    made = made + 1
    local over = stretchedImage(tree, art, owner, M.overlayArt(ctx.settings.bars.style, lookOn()), OVERLAY_PREFIX .. made)
    if not over then return end
    local slot = parent:AddChildToOverlay(over)
    slot:SetHorizontalAlignment(0)
    slot:SetVerticalAlignment(0)
end

local function removeOverlays(barWidget)
    for _, img in ipairs(barImages(barWidget)) do
        local parent = W.parent(img)
        local mine = parent and childNamed(parent, M.isOurs)
        if mine then pcall(function() mine:RemoveFromParent() end) end
    end
end

local OUTLINE_PREFIX = "FM_Outline_"
-- Pure: is this our gold edge (by widget name)? Unit-tested.
function M.isOutline(name) return name:sub(1, #OUTLINE_PREFIX) == OUTLINE_PREFIX end

-- The gold edge along the body (top and bottom; the ring covers the start, the point has its own).
local function addOutline(barWidget)
    local img, fillPanel = parts(barWidget)
    if not (img and fillPanel) or childNamed(fillPanel, M.isOutline) then return end
    local owner = W.owner(img)
    local tree = owner and owner.WidgetTree
    local art = ctx.features.art
    if not (tree and art) then return end
    made = made + 1
    local line = stretchedImage(tree, art, owner, "ui/bar_outline_body.png", OUTLINE_PREFIX .. made)
    if not line then return end
    local slot = fillPanel:AddChildToOverlay(line)
    slot:SetHorizontalAlignment(0)
    slot:SetVerticalAlignment(0)
    -- with the ring icons off nothing covers the start: close it with the flat end's gold line, mirrored
    if not badgesOn() then
        made = made + 1
        local edge = stretchedImage(tree, art, owner, M.endArt(ctx.settings.bars.style, false).outline,
            OUTLINE_PREFIX .. "Start_" .. made)
        if edge then
            local box = StaticConstructObject(StaticFindObject("/Script/UMG.SizeBox"), tree, FName(OUTLINE_PREFIX .. "StartBox_" .. made))
            box:SetWidthOverride(M.endWidth(ctx.settings.bars, false))
            box:SetContent(edge)
            pcall(function() edge:SetRenderScale({ X = -1, Y = 1 }) end)
            pcall(function() box:SetVisibility(3) end)
            local es = fillPanel:AddChildToOverlay(box)
            es:SetHorizontalAlignment(1) -- left
            es:SetVerticalAlignment(0)
        end
    end
end

local function removeOutline(barWidget)
    local img, fillPanel = parts(barWidget)
    if not (img and fillPanel) then return end
    -- the edge along the body and, with the ring icons off, the one closing its start
    for _ = 1, 3 do
        local line = childNamed(fillPanel, M.isOutline)
        if not line then break end
        pcall(function() line:RemoveFromParent() end)
    end
end

local function unshape(barWidget)
    local okN, barName = pcall(W.name, barWidget)
    local rec = okN and shaped[barName]
    local img, fillPanel, border, box, holder = parts(barWidget)
    if not (rec and img and fillPanel and border and box and holder) then return end
    local tip = childNamed(holder, M.isTip)
    if tip then pcall(function() tip:RemoveFromParent() end) end
    stretchPaint(img, fillPanel, rec, 1)
    removeOutline(barWidget)
    if rec.height then pcall(function() box:SetHeightOverride(rec.height) end) end
    if rec.valign then pcall(function() box.Slot:SetVerticalAlignment(rec.valign) end) end
    if rec.halign then pcall(function() box.Slot:SetHorizontalAlignment(rec.halign) end) end
    if rec.boxPad then pcall(function() box.Slot:SetPadding(rec.boxPad) end) end
    if rec.pad then pcall(function() border:SetPadding(rec.pad) end) end
    if rec.brush then
        local art = ctx.features.art
        local function go() border:SetBrush(rec.brush) end
        if art then art.guarded(go) else pcall(go) end
    end
end

-- The bar's value text ("200 / 200"): the first text in its tree that reads like one.
local function valueOf(barWidget)
    local cur, max
    W.walk(barWidget, function(w)
        if cur then return false end
        local ok, txt = pcall(function() return w:GetText():ToString() end)
        if ok then
            local c, m = M.parseValue(txt)
            if c then cur, max = c, m return false end
        end
        return true
    end, 0, 14)
    return cur, max
end

-- Percentages on the stamina and special bars (bars.percentText): the health bar shows its value ("200 / 200") but
-- the other two show nothing. Their fill is read from their material (the game's own "Fill from Avaliable", times
-- "Available health/stamina") and shown as a text over the bar like the health bar's, in its font.
local PERCENT_BARS = { WBP_HUD_Vitals_StaminaBar_C = true, WBP_HUD_Vitals_SpecialChargeBar_C = true }
local PERCENT_PREFIX = "FM_Percent_"
local healthFont -- (looked up each time a label is made) the health bar's value text: { font, color, shadowOffset, shadowColor, slot = {h, v, pad} }

-- Pure: the percentage shown for a fill (0..1) of the available part (0..1). Unit-tested.
function M.percentText(fill, available)
    local v = math.max(0, math.min(1, (fill or 0) * (available or 1)))
    return string.format("%d%%", math.floor(v * 100 + 0.5))
end

local function healthStyle()
    for _, hb in pairs(FindAllOf("WBP_HUD_Vitals_HealthBar_C") or {}) do
        if W.valid(hb) and W.isInstance(hb) then
            local vt
            W.walk(hb, function(w)
                if vt then return false end
                local ok, n = pcall(W.name, w)
                if ok and n == "ValueText" then vt = w return false end
                return true
            end, 0, 12)
            local tb
            if vt then
                W.walk(vt, function(w)
                    if tb then return false end
                    -- (the game's text widget wraps a text of its own class: any *TextBlock that isn't the wrapper)
                    local ok, c = pcall(W.className, w)
                    if ok and w ~= vt and c:find("TextBlock", 1, true) and not c:find("^WBP_") then tb = w return false end
                    return true
                end, 0, 6)
            end
            if tb then
                local f = {}
                pcall(function() f.font = tb.Font end)
                pcall(function() f.color = tb.ColorAndOpacity end)
                pcall(function() f.shadowOffset = tb.ShadowOffset end)
                pcall(function() f.shadowColor = tb.ShadowColorAndOpacity end)
                pcall(function()
                    local sl = vt.Slot
                    f.slot = { h = sl.HorizontalAlignment, v = sl.VerticalAlignment,
                        pad = { Left = sl.Padding.Left, Top = sl.Padding.Top, Right = sl.Padding.Right,
                            Bottom = sl.Padding.Bottom } }
                end)
                healthFont = f
                return f
            end
        end
    end
end

local function readScalar(mat, name)
    local ok, v = pcall(function() return mat:K2_GetScalarParameterValue(FName(name)) end)
    if ok and type(v) == "number" then return v end
    return nil
end

-- The game's rate labels beside each bar ("2 STATS", "HP/S", "SPEC/S", shown while a menu is open): never shown
-- (bars.hideRateLabels). They sit next to each bar in its row: StaminaRegenValue, HealthRegenValue,
-- SpecialChargeRegenValue (a background and a per-second value).
function M.isRateLabel(name) return type(name) == "string" and name:find("RegenValue$") ~= nil end

local function hideRateLabels()
    if not (ctx.enabled and ctx.settings.bars.hideRateLabels ~= false) then return end
    for _, cls in ipairs(BAR_ORDER) do
        for _, bar in pairs(FindAllOf(cls) or {}) do
            local row = W.valid(bar) and W.isInstance(bar) and W.parent(bar)
            if row then
                for _, c in ipairs(W.children(row)) do
                    local ok, n = pcall(W.name, c)
                    if ok and M.isRateLabel(n) then
                        pcall(function() if c:GetRenderOpacity() ~= 0 then c:SetRenderOpacity(0) end end)
                    end
                end
            end
        end
    end
end

local function percentLabels()
    local want = ctx.enabled and ctx.settings.bars.percentText ~= false
    for cls in pairs(PERCENT_BARS) do
        for _, bar in pairs(FindAllOf(cls) or {}) do
            if W.valid(bar) and W.isInstance(bar) then
                local img, _, _, _, holder = parts(bar)
                if holder then
                    local label = childNamed(holder, function(n) return n:sub(1, #PERCENT_PREFIX) == PERCENT_PREFIX end)
                    if not want then
                        if label then pcall(function() label:RemoveFromParent() end) end
                    else
                        if not label then
                            local hs = healthStyle() or {}
                            local owner = W.owner(holder)
                            local tree = owner and owner.WidgetTree
                            if tree then
                                made = made + 1
                                label = StaticConstructObject(StaticFindObject("/Script/UMG.TextBlock"), tree,
                                    FName(PERCENT_PREFIX .. made))
                                -- the game's font at a set size (the health number's own font can't always be read,
                                -- and the default is far too big)
                                local gf = require("framemage.editor.legend").gameFont()
                                local size = ctx.settings.bars.percentFontSize or 10
                                if gf then
                                    pcall(function() label:SetFont({ FontObject = gf.FontObject,
                                        TypefaceFontName = gf.TypefaceFontName, Size = size }) end)
                                elseif hs.font then
                                    pcall(function() label:SetFont(hs.font) end)
                                end
                                if hs.color then pcall(function() label:SetColorAndOpacity(hs.color) end) end
                                if hs.shadowOffset then pcall(function() label:SetShadowOffset(hs.shadowOffset) end) end
                                if hs.shadowColor then
                                    pcall(function() label:SetShadowColorAndOpacity(hs.shadowColor) end)
                                end
                                log.info("bars: percentage label on %s (%s)", tostring(W.name(bar)),
                                    gf and "the game's font" or (hs.font and "the health number's font" or "default font"))
                                pcall(function() label:SetJustification(1) end)
                                label:SetVisibility(3)
                                local sl = holder:AddChildToOverlay(label)
                                local p = hs.slot or {}
                                pcall(function() sl:SetHorizontalAlignment(p.h or 2) end)
                                pcall(function() sl:SetVerticalAlignment(p.v or 2) end)
                                if p.pad then pcall(function() sl:SetPadding(p.pad) end) end
                            end
                        end
                        if label and img then
                            local okM, mat = pcall(function() return img.Brush.ResourceObject end)
                            local fill = okM and readScalar(mat, "Fill from Avaliable")
                            if fill then
                                local t = M.percentText(fill, readScalar(mat, "Available health/stamina") or 1)
                                pcall(function() label:SetText(FText(t)) end)
                            end
                        end
                    end
                end
            end
        end
    end
end

-- Every few frames: keep the game's bar icons collapsed under the rings (the game re-shows them), and show each
-- point's color only when its bar is full.
local overrideWait = 0
local function updateCaps()
    if badgesOn() then
        for _, cls in ipairs({ "WBP_HUD_Vitals_HealthBar_C", "WBP_HUD_Vitals_StaminaBar_C", "WBP_HUD_Vitals_SpecialChargeBar_C" }) do
            for _, bar in pairs(FindAllOf(cls) or {}) do
                if W.valid(bar) and W.isInstance(bar) then
                    W.walk(bar, function(w)
                        local ok, n = pcall(W.name, w)
                        if ok and M.isIcon(n) then
                            local okV, v = pcall(function() return w:GetVisibility() end)
                            local okS, sx = pcall(function() return w.RenderTransform.Scale.X end)
                            if (okV and v ~= 2) or (okS and sx ~= 0) then hideGameIcon(w) end
                            return false
                        end
                        return true
                    end, 0, 6)
                end
            end
        end
    end
    -- an icon chosen in bars.iconOverrides that wasn't loaded when the ring was made (the Agility icon loads once the
    -- game has shown it, e.g. in the spell radial): swap it in when it turns up (looked for every few seconds)
    overrideWait = overrideWait - 1
    if overrideWait <= 0 then
        overrideWait = 25
        for _, r in pairs(ringIcons) do
            if r.override and not r.done and W.valid(r.copy) then
                local alt = gameTexture(r.override)
                if alt then
                    ctx.features.art.guarded(function() r.copy:SetBrushFromTexture(alt, false) end)
                    r.done = true
                    log.info("bars: stamina ring now shows %s", r.override)
                end
            end
        end
    end
    if not lookOn() then return end -- the end piece (point or flat) shows the color only when full
    for _, cls in ipairs({ "WBP_HUD_Vitals_HealthBar_C", "WBP_HUD_Vitals_StaminaBar_C", "WBP_HUD_Vitals_SpecialChargeBar_C" }) do
        for _, bar in pairs(FindAllOf(cls) or {}) do
            if W.valid(bar) and W.isInstance(bar) then
                local img, _, _, _, holder = parts(bar)
                local tip = holder and childNamed(holder, M.isTip)
                -- the game can give a bar a new material (after sleeping, a respawn...): the point's copies of the
                -- old one then draw dark, so the bar is styled again with the new one
                if tip and img and styleBar then
                    local okM, cur = pcall(function() return W.fullName(img.Brush.ResourceObject) end)
                    local band
                    W.walk(tip, function(w)
                        if band then return false end
                        local ok, n = pcall(W.name, w)
                        if ok and n:sub(1, 11) == "FM_TipBand_" then band = w return false end
                        return true
                    end, 0, 6)
                    local okB, old = pcall(function() return W.fullName(band.Brush.ResourceObject) end)
                    if band and okM and okB and cur ~= old then
                        log.info("bars: %s has a new material: its point is repainted", tostring(W.name(bar)))
                        styleBar(bar, true)
                        tip = nil
                    end
                end
                if tip then
                    -- no readable value counts as full: the stamina bar hides its text when it's full
                    local c, m = valueOf(bar)
                    local full = M.isFull(c, m)
                    W.walk(tip, function(w)
                        local ok, n = pcall(W.name, w)
                        if ok and n:sub(1, #TIP_COLOR) == TIP_COLOR then
                            pcall(function() w:SetVisibility(full and 3 or 1) end)
                            return false
                        end
                        return true
                    end, 0, 4)
                end
            end
        end
    end
end

local function style(barWidget, replace)
    pcall(applyBadges, barWidget, replace)
    if replace then
        pcall(removeOverlays, barWidget)
        pcall(removeOutline, barWidget)
        pcall(unshape, barWidget)
    end
    if lookOn() then
        local ok, err = pcall(shape, barWidget)
        if not ok then log.debug("bars: shape: %s", tostring(err)) end
    elseif not replace then
        pcall(unshape, barWidget)
    end
    if on() then
        for _, img in ipairs(barImages(barWidget)) do
            local ok, err = pcall(addOverlay, img)
            if not ok then log.debug("bars: %s", tostring(err)) end
        end
    else
        pcall(removeOverlays, barWidget)
    end
    if lookOn() and ctx.settings.bars.outline then
        if not replace then pcall(removeOutline, barWidget) end -- keep it the top layer of the body
        local ok, err = pcall(addOutline, barWidget)
        if not ok then log.debug("bars: outline: %s", tostring(err)) end
    else
        pcall(removeOutline, barWidget)
    end
    pcall(space, barWidget) -- last: measures the bar at its final height
end

-- HUD pieces that can be hidden by an option (their space kept, so nothing else shifts):
--   the line between the survival gauges and the buffs (then they read as separate elements in the editor too);
--   the key hints (Block, Attack, Special Attack...), for players who know their keys.
-- Pure: the hideable pieces: { widget class, piece name, setting }. Unit-tested via M.hideable.
M.HIDEABLE = {
    { cls = "WBP_InputLegend_World_C", name = "GameInputs", setting = "hideKeyHints" },
}
function M.hideable(cls)
    local out = {}
    for _, h in ipairs(M.HIDEABLE) do if h.cls == cls then out[#out + 1] = h end end
    return out
end
function M.isUpkeepClass(cls) return #M.hideable(cls) > 0 end

local function tidyUpkeep(uw)
    local okC, cls = pcall(W.className, uw)
    if not okC then return end
    for _, h in ipairs(M.hideable(cls)) do
        local hide = ctx.enabled and ctx.settings.bars[h.setting] == true
        W.walk(uw, function(w)
            local ok, n = pcall(W.name, w)
            if ok and n == h.name then
                pcall(function() w:SetVisibility(hide and 2 or 4) end) -- 2 Hidden (space kept) / 4 self-hit-test-invisible
                return false
            end
            return true
        end, 0, 12)
    end
end

-- Durability bars (under items): colored by how worn the item is, in bands: green above 75%, yellow above 50%,
-- orange above 25%, red at 25% and below. They're plain progress bars, so the fill color is simply set; the game's
-- own color is remembered and put back when the option is switched off.
M.DURABILITY_BANDS = { -- { above this fraction, color }, highest first
    { 0.75, { 0.10, 0.70, 0.15 } }, -- green: 76-100%
    { 0.50, { 0.95, 0.80, 0.05 } }, -- yellow: 51-75%
    { 0.25, { 1.00, 0.40, 0.02 } }, -- orange: 26-50%
    { -1, { 0.85, 0.05, 0.04 } },   -- red: 0-25%
}

-- Pure: the color for a durability fraction (0..1), as { R, G, B, A }. Percent is rounded first, so 75.4% is 75%
-- (yellow). Unit-tested.
function M.durabilityColor(p)
    local pct = math.floor(math.max(0, math.min(1, p or 0)) * 100 + 0.5) / 100
    for _, b in ipairs(M.DURABILITY_BANDS) do
        if pct > b[1] then local c = b[2] return { R = c[1], G = c[2], B = c[3], A = 1 } end
    end
    local c = M.DURABILITY_BANDS[#M.DURABILITY_BANDS][2]
    return { R = c[1], G = c[2], B = c[3], A = 1 }
end

local gameFill -- the game's own durability color (to restore)
local warnedDurability, durabilityChecked, lastSet = false, false, nil

local function durabilityBars(fn)
    for _, bar in pairs(FindAllOf("WBP_Inventory_DurabilityBar_C") or {}) do
        if W.valid(bar) and W.isInstance(bar) then
            W.walk(bar, function(w)
                local ok, cls = pcall(W.className, w)
                if ok and cls == "ProgressBar" then
                    local okF, err = pcall(fn, w)
                    if not okF and not warnedDurability then
                        warnedDurability = true
                        log.warn("bars: durability color failed: %s", tostring(err))
                    end
                    return false
                end
                return true
            end, 0, 6)
        end
    end
end

local durabilityWasOn = false
local function colorDurability()
    local onNow = ctx.enabled and ctx.settings.bars.durabilityColors == true
    if onNow then
        durabilityBars(function(pb)
            if not gameFill then
                local c = pb.FillColorAndOpacity
                gameFill = { R = c.R, G = c.G, B = c.B, A = c.A }
            end
            -- once: does the color we set last until the next pass, or does the game put its own back?
            if lastSet and not durabilityChecked then
                durabilityChecked = true
                local c = pb.FillColorAndOpacity
                local same = math.abs(c.R - lastSet.R) + math.abs(c.G - lastSet.G) + math.abs(c.B - lastSet.B) < 0.01
                log.info("bars: durability colors %s (bar at %d%%, %d bars)", same and "hold" or
                    "are reset by the game", math.floor(pb.Percent * 100 + 0.5), #(FindAllOf("WBP_Inventory_DurabilityBar_C") or {}))
            end
            local col = M.durabilityColor(pb.Percent)
            pb:SetFillColorAndOpacity(col)
            lastSet = col
        end)
    elseif durabilityWasOn and gameFill then
        durabilityBars(function(pb) pb:SetFillColorAndOpacity(gameFill) end)
    end
    durabilityWasOn = onNow
end

-- (ProgressBar.GetPercent is a C++-only getter in UE 5.x, so read the Percent property directly.)

-- Every bar on screen now (fresh handles from a scan): after a style change.
styleBar = function(b, r) return style(b, r) end

-- The box round the three bars as drawn, from each one's own container (its body and point): the stacked survival
-- gauges sit just right of the points, not of the bars' wider panel. { left, top, right, bottom } or nil.
function M.barsRect()
    local box
    for _, cls in ipairs(BAR_ORDER) do
        for _, b in pairs(FindAllOf(cls) or {}) do
            if W.valid(b) and W.isInstance(b) and W.isVisible(b) then
                local _, _, _, _, holder = parts(b)
                local r = measure.rect(holder or b)
                if r then
                    box = box and { left = math.min(box.left, r.left), top = math.min(box.top, r.top),
                        right = math.max(box.right, r.right), bottom = math.max(box.bottom, r.bottom) } or r
                end
                break
            end
        end
    end
    return box
end

-- Each bar's own container (body and point) where the game lays it out, before anyone's offsets on the bar itself:
-- moving a bar in the editor doesn't move these. { rect, ... } in bar order (stamina, health, special), or nil.
function M.barsNatural()
    local out = {}
    for _, cls in ipairs(BAR_ORDER) do
        for _, b in pairs(FindAllOf(cls) or {}) do
            if W.valid(b) and W.isInstance(b) and W.isVisible(b) then
                local _, _, _, _, holder = parts(b)
                local T = measure.transform(W.parent(b))
                local L = measure.layoutRect(holder or b)
                if T and L then out[#out + 1] = measure.apply(T, L) end
                break
            end
        end
    end
    return #out > 0 and out or nil
end

function M.refresh()
    local n = 0
    for _, uw in pairs(FindAllOf("UserWidget") or {}) do
        if W.valid(uw) and W.isInstance(uw) then
            local ok, cls = pcall(W.className, uw)
            if ok and M.isBarClass(cls) then style(uw, true); n = n + 1 end
            if ok and M.isUpkeepClass(cls) then pcall(tidyUpkeep, uw) end
        end
    end
    log.info("bars: %s style on %d bars", ctx.settings.bars.style, n)
end

function M.setStyle(s)
    ctx.settings.bars.style = s
    ctx.saveSettings()
    M.refresh()
end


function M.init(c)
    ctx, W, log = c, c.widgets, c.log
    c.events.on("userwidget", function(uw)
        if not (on() or badgesOn() or taperOn() or ctx.settings.bars.hideKeyHints) then return end
        local ok, cls = pcall(W.className, uw)
        if ok and M.isBarClass(cls) then style(uw) end
        if ok and M.isUpkeepClass(cls) then pcall(tidyUpkeep, uw) end
    end)
    c.events.on("themechanged", function() if on() then M.refresh() end end)
    c.sched.every(1000, "bars.durability", function()
        local ok, err = pcall(colorDurability)
        if not ok then log.debug("bars: durability: %s", tostring(err)) end
    end)
    c.sched.every(200, "bars.caps", function()
        local ok, err = pcall(updateCaps)
        if not ok then log.debug("bars: caps: %s", tostring(err)) end
        pcall(hideRateLabels)
        local okP, errP = pcall(percentLabels)
        if not okP then log.debug("bars: percent: %s", tostring(errP)) end
        local okR, errR = pcall(evenRows)
        if not okR then log.debug("bars: rows: %s", tostring(errR)) end
    end)
end

return M
