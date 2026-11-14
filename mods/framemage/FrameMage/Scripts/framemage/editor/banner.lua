-- The editor's title banner: a parchment ribbon (aged, burnt-edged band; swallowtail ends folded behind)
-- naming the selected element. It sits just below the game's compass (measured live, so it follows the
-- compass if that has been moved), and unfurls briefly whenever its text changes.
-- Art: Art/_ui/fm_ribbon_{left,mid,right}.png from tools/make_icons.py (Frame Mage's own).
local overlay = require("framemage.core.overlay")
local W = require("framemage.core.widgets")
local geometry = require("framemage.core.geometry")
local legend = require("framemage.editor.legend")

local M = {}

-- art geometry (pixels in the generated PNGs; see tools/make_icons.py)
local ART = { height = 80, endWidth = 76, bandTop = 4, bandBottom = 58 }

local ctx, S
local b -- { uw, slot, box, text }
local text = ""
local animSeq = 0

-- Pure: where the banner's top goes. compassBottom = lowest edge of the compass (viewport units) or nil.
function M.topFor(compassBottom, settings)
    if compassBottom and compassBottom > 0 and compassBottom < 600 then
        return compassBottom + settings.bannerGap
    end
    return settings.bannerFallbackTop
end

-- The compass's lowest visible edge, ignoring full-screen containers.
local function compassBottom()
    local compass = FindFirstOf("WBP_HUD_Compass_C")
    if not (W.valid(compass) and W.isVisible(compass)) then return nil end
    local root = geometry.rect(compass)
    if not root then return nil end
    local screenW = root.right - root.left
    local bottom
    W.walk(compass, function(w, depth)
        if depth > 0 and not W.isVisible(w) then return false end
        local r = geometry.rect(w)
        if r and depth > 0 and (r.right - r.left) < screenW * 0.8 and r.bottom > r.top and r.top < 400 then
            if not bottom or r.bottom > bottom then bottom = r.bottom end
        end
        return true
    end, 0, 8)
    return bottom
end

local function build()
    local h = overlay.host("Banner", 20000)
    local art = ctx.features.art
    local function tex(file) return art and art.loadFile(ctx.dir .. "Art/_ui/" .. file, h.uw) end
    local k = S.bannerHeight / ART.height
    local n = 0
    local function new(cls)
        n = n + 1
        return overlay.new(cls, h.tree, "FM_Banner_" .. cls .. "_" .. h.suffix .. "_" .. n)
    end
    local function piece(file, width)
        local size = new("SizeBox")
        size:SetWidthOverride(width)
        size:SetHeightOverride(S.bannerHeight)
        local img = new("Image")
        local t = tex(file)
        if t then img:SetBrushFromTexture(t, false) end
        size:SetContent(img)
        return size
    end

    local box = new("HorizontalBox")
    box:AddChildToHorizontalBox(piece("fm_ribbon_left.png", ART.endWidth * k))

    -- center: stretched band with the name on it, centered on the band (not the whole image)
    local midSize = new("SizeBox")
    midSize:SetMinDesiredWidth(S.bannerMinWidth)
    midSize:SetHeightOverride(S.bannerHeight)
    local ov = new("Overlay")
    local midImg = new("Image")
    local mt = tex("fm_ribbon_mid.png")
    if mt then midImg:SetBrushFromTexture(mt, false) end
    local ms = ov:AddChildToOverlay(midImg)
    ms:SetHorizontalAlignment(0) -- fill
    ms:SetVerticalAlignment(0)
    local label = new("TextBlock")
    local font = legend.gameFont()
    if font then
        pcall(function()
            label:SetFont({ FontObject = font.FontObject, TypefaceFontName = font.TypefaceFontName, Size = S.bannerFontSize })
        end)
    end
    -- iron-gall ink on parchment, with a faint light edge as if pressed into the page
    label:SetColorAndOpacity({ SpecifiedColor = { R = 0.16, G = 0.08, B = 0.03, A = 1 }, ColorUseRule = 0 })
    pcall(function() label:SetShadowOffset({ X = 1, Y = 1 }) end)
    pcall(function() label:SetShadowColorAndOpacity({ R = 1, G = 0.95, B = 0.8, A = 0.35 }) end)
    local ls = ov:AddChildToOverlay(label)
    ls:SetHorizontalAlignment(2)
    ls:SetVerticalAlignment(2)
    -- shift the text up so it is centered on the band, which is the upper part of the art
    local bandCenter = (ART.bandTop + ART.bandBottom) / 2
    local lift = (ART.height / 2 - bandCenter) * 2 * k
    ls:SetPadding({ Left = 18 * k, Top = 0, Right = 18 * k, Bottom = lift })
    midSize:SetContent(ov)
    box:AddChildToHorizontalBox(midSize)

    box:AddChildToHorizontalBox(piece("fm_ribbon_right.png", ART.endWidth * k))

    local slot = h.canvas:AddChildToCanvas(box)
    slot:SetAutoSize(true)
    slot:SetAnchors({ Minimum = { X = 0.5, Y = 0 }, Maximum = { X = 0.5, Y = 0 } })
    slot:SetAlignment({ X = 0.5, Y = 0 })
    slot:SetPosition({ X = 0, Y = S.bannerFallbackTop })
    pcall(function() box:SetRenderTransformPivot({ X = 0.5, Y = 0.5 }) end)
    b = { uw = h.uw, slot = slot, box = box, text = label }
end

-- Unfurl: widen from 80% and fade in over ~150 ms (eased), on the game thread.
local function animateIn()
    animSeq = animSeq + 1
    local mine, steps = animSeq, 6
    local function frame(i)
        if mine ~= animSeq or not (b and W.valid(b.box)) then return end
        local t = i / steps
        local e = 1 - (1 - t) ^ 3
        pcall(function()
            b.box:SetRenderScale({ X = 0.8 + 0.2 * e, Y = 0.94 + 0.06 * e })
            b.box:SetRenderOpacity(0.25 + 0.75 * e)
        end)
    end
    frame(0)
    for i = 1, steps do ctx.sched.later(i * 25, "banner.anim", function() frame(i) end) end
end

function M.set(msg)
    if not (b and W.valid(b.uw) and W.valid(b.text)) then
        local ok, err = pcall(build)
        if not ok then ctx.log.warn("editor banner unavailable: %s", tostring(err)); b = nil; return end
    end
    if msg == "" then
        text = ""
        pcall(function() b.uw:SetVisibility(1) end)
        return
    end
    local changed = msg ~= text
    text = msg
    pcall(function() b.text:SetText(FText(msg)) end)
    pcall(function() b.slot:SetPosition({ X = 0, Y = M.topFor(compassBottom(), S) }) end)
    pcall(function() b.uw:SetVisibility(3) end)
    if changed then animateIn() end
end

function M.forget() b = nil; text = "" end

function M.init(c, settings) ctx, S = c, settings end

return M
