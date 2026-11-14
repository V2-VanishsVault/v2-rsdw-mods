-- Where widgets and the mouse are on screen, in viewport units: the units of a full-screen CanvasPanel slot,
-- which is what our overlays position things in (the screen's pixels divided by the game's UI scale; a
-- 5120x1440 screen at 1.33 is 3840x1080 units).
--
-- Widget rectangles are computed from layout data by core/measure.lua: Unreal's own answer (FGeometry) can't
-- be read from Lua. The reference set here is only a world context for the viewport queries (one of our
-- overlay canvases).
local M = {}

local W = require("framemage.core.widgets")
local measure = require("framemage.core.measure")

local ref -- a widget of ours (world context)
local WLL

local function lib()
    if not W.valid(WLL) then WLL = StaticFindObject("/Script/UMG.Default__WidgetLayoutLibrary") end
    return WLL
end

function M.setReference(canvas) ref = canvas end
function M.hasReference() return ref ~= nil and W.valid(ref) end

-- A world context for the viewport queries: our reference, or else the player controller. (Without one, the screen
-- size was unknown until the editor or Settings had been opened, and everything measured before then - the stacked
-- survival gauges at load - assumed a 1920-wide screen.)
local fallback
local function context()
    if M.hasReference() then return ref end
    if not (fallback and W.valid(fallback)) then fallback = FindFirstOf("PlayerController") end
    return fallback and W.valid(fallback) and fallback or nil
end

-- The screen's size in viewport units, or nil.
function M.screen()
    local cx = context()
    if not cx then return nil end
    local ok, w, h = pcall(function()
        local px = lib():GetViewportSize(cx)
        local scale = lib():GetViewportScale(cx)
        if not (scale and scale > 0 and px and px.X and px.X > 0) then return nil end
        return px.X / scale, px.Y / scale
    end)
    if ok and w then return w, h end
    return nil
end

measure.init(W, function() return M.screen() end)

-- { left, top, right, bottom, accScale } or nil. accScale = drawn units per local unit of `w`.
function M.rect(w)
    return measure.rect(w)
end

-- Layouts changed (a drag or an edit): forget this frame's measurements.
function M.invalidate() measure.invalidate() end

-- Mouse position in viewport units, or nil.
function M.mouse()
    if not M.hasReference() then return nil end
    local ok, p = pcall(function() return lib():GetMousePositionOnViewport(ref) end)
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

-- Grow a rectangle around its center to at least `min` units each way (empty widgets have no size).
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
