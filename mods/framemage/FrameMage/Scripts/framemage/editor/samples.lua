-- Samples: the real size of an element that shows nothing right now, for its stand-in while it's edited.
--
-- An element the game isn't showing (a notice between notices, a prompt with nothing to prompt) has almost no size,
-- so it's drawn as a stand-in box instead. That box should be the element's real size: so each element's size is
-- measured whenever the editor sees it showing something, kept by its key, and saved (config/sizes.lua), so it's
-- known in later sessions too. An element never yet seen showing gets the usual stand-in size.
local M = {}

local config -- core/config (load/save)
local path -- config/sizes.lua
local sizes = {} -- element key -> { w, h } (UI units)
local dirty = false

function M.init(ctx)
    config = require("framemage.core.config")
    path = ctx.dir .. "config/sizes.lua"
    local ok, data = pcall(config.load, path, {})
    sizes = (ok and type(data) == "table") and data or {}
end

-- Pure: is a measured box a real showing (not a collapsed sliver)? Unit-tested.
function M.isShowing(w, h) return w >= 16 and h >= 12 end

-- Remember an element's size (rect in UI units) while it shows something; changes of a unit or less are ignored.
function M.remember(key, rect)
    if not (key and rect) then return end
    local w, h = rect.right - rect.left, rect.bottom - rect.top
    if not M.isShowing(w, h) then return end
    local old = sizes[key]
    if old and math.abs(old[1] - w) <= 1 and math.abs(old[2] - h) <= 1 then return end
    sizes[key] = { math.floor(w + 0.5), math.floor(h + 0.5) }
    dirty = true
end

-- Save what was learned (the editor calls this when it closes).
function M.save()
    if not (dirty and config and path) then return end
    dirty = false
    config.save(path, sizes, "-- Frame Mage: each element's size the last time it showed something (UI units),\n" ..
        "-- so the layout editor can show elements that are empty at their real size. Safe to delete.\n")
end

-- The size to give an element showing nothing: its remembered size, else the default.
function M.sizeFor(key, defaultW, defaultH)
    local s = key and sizes[key]
    if s then return s[1], s[2], true end
    return defaultW, defaultH, false
end

-- Pure: the stand-in box at `at` (the element's place), w x h, kept on screen. Unit-tested.
function M.box(at, w, h, screenW, screenH)
    local left, top = at.left, at.top
    if screenW then left = math.max(0, math.min(left, screenW - w)) end
    if screenH then top = math.max(0, math.min(top, screenH - h)) end
    return { left = left, top = top, right = left + w, bottom = top + h }
end

-- (tests)
function M._set(t) sizes = t or {} end

return M
