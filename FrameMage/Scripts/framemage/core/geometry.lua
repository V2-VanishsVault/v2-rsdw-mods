-- Where widgets are on screen, in viewport UI units (the same units as a full-screen CanvasPanel slot and the
-- mouse position), measured from cached geometry, so it includes render transforms and parent offsets.
--
-- Needs a reference: a full-screen overlay canvas of ours that has been painted at least once
-- (setReference). Its geometry converts Slate's absolute (desktop pixel) space to viewport units.
local M = {}

local W = require("framemage.core.widgets")

local ref -- CanvasPanel
local SBL, WLL

local function libs()
    if not W.valid(SBL) then SBL = StaticFindObject("/Script/UMG.Default__SlateBlueprintLibrary") end
    if not W.valid(WLL) then WLL = StaticFindObject("/Script/UMG.Default__WidgetLayoutLibrary") end
end

function M.setReference(canvas) ref = canvas end
function M.hasReference() return ref ~= nil and W.valid(ref) end

-- { left, top, right, bottom, accScale } or nil. accScale = drawn units per local unit of `w`.
function M.rect(w)
    if not M.hasReference() then return nil end
    libs()
    local ok, r = pcall(function()
        local gg = ref:GetCachedGeometry()
        local o = SBL:LocalToAbsolute(gg, { X = 0, Y = 0 })
        local o1 = SBL:LocalToAbsolute(gg, { X = 1, Y = 1 })
        local sx, sy = o1.X - o.X, o1.Y - o.Y
        if not (sx > 0 and sy > 0) then return nil end
        local wg = w:GetCachedGeometry()
        local size = SBL:GetLocalSize(wg)
        local tl = SBL:LocalToAbsolute(wg, { X = 0, Y = 0 })
        local br = SBL:LocalToAbsolute(wg, { X = size.X, Y = size.Y })
        local unit = SBL:LocalToAbsolute(wg, { X = 1, Y = 0 })
        return {
            left = (tl.X - o.X) / sx, top = (tl.Y - o.Y) / sy,
            right = (br.X - o.X) / sx, bottom = (br.Y - o.Y) / sy,
            accScale = (unit.X - tl.X) / sx,
        }
    end)
    if ok then return r end
    return nil
end

-- Mouse position in the same viewport units, or nil.
function M.mouse()
    if not M.hasReference() then return nil end
    libs()
    local ok, p = pcall(function() return WLL:GetMousePositionOnViewport(ref) end)
    if ok and p and type(p.X) == "number" then return p.X, p.Y end
    return nil
end

-- Pure helpers ---------------------------------------------------------------------------

function M.contains(r, x, y)
    return x >= r.left and x <= r.right and y >= r.top and y <= r.bottom
end

function M.area(r)
    return math.max(0, r.right - r.left) * math.max(0, r.bottom - r.top)
end

-- Grow a rectangle around its centre to at least `min` units each way (empty widgets have no size).
function M.atLeast(r, min)
    local out = { left = r.left, top = r.top, right = r.right, bottom = r.bottom }
    if out.right - out.left < min then
        local c = (out.left + out.right) / 2
        out.left, out.right = c - min / 2, c + min / 2
    end
    if out.bottom - out.top < min then
        local c = (out.top + out.bottom) / 2
        out.top, out.bottom = c - min / 2, c + min / 2
    end
    return out
end

return M
