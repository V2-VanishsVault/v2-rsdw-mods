-- Click-to-pick: every visible widget under a point, smallest first. Clicking the same spot again steps to
-- the next larger widget (child -> panel -> whole HUD), so nested parts can be grabbed independently.
local W = require("framemage.core.widgets")
local geometry = require("framemage.core.geometry")

local M = {}

local last -- { x, y, list = { widget... }, index }

-- Pure: order candidates for picking. Smallest area first; ties go to the deeper widget. Unit-tested.
function M.order(cands)
    table.sort(cands, function(a, b)
        if math.abs(a.area - b.area) > 1e-3 then return a.area < b.area end
        return a.depth > b.depth
    end)
    return cands
end

-- Pure: is this click a repeat of the last one (same spot)?
function M.sameSpot(a, b, tolerance)
    return a and b and math.abs(a.x - b.x) <= tolerance and math.abs(a.y - b.y) <= tolerance
end

local function collect(roots, x, y, minArea, maxNodes)
    local cands, seen, nodes = {}, {}, 0
    for _, root in ipairs(roots) do
        W.walk(root, function(w, depth)
            nodes = nodes + 1
            if nodes > maxNodes then return false end
            if not W.isVisible(w) then return false end
            local r = geometry.rect(w)
            if r and geometry.contains(r, x, y) then
                local area = geometry.area(r)
                local full = W.fullName(w)
                if area >= minArea and not seen[full] then
                    seen[full] = true
                    cands[#cands + 1] = { w = w, area = area, depth = depth }
                end
            end
            return true -- children can be drawn outside their parent (moved elements), so always descend
        end)
    end
    return M.order(cands)
end

-- Returns the widget to select for a click at (x, y), or nil. `roots` are the game's on-screen roots.
function M.pick(roots, x, y, settings)
    local here = { x = x, y = y }
    if last and M.sameSpot(last, here, settings.pickRepeatTolerance) and #last.list > 0 then
        -- step outward through the same stack; skip widgets that have since gone away
        for _ = 1, #last.list do
            last.index = last.index % #last.list + 1
            local w = last.list[last.index]
            if W.valid(w) then return w, last.index, #last.list end
        end
    end
    local cands = collect(roots, x, y, settings.pickMinArea, settings.pickMaxNodes)
    local list = {}
    for i, c in ipairs(cands) do list[i] = c.w end
    last = { x = x, y = y, list = list, index = 1 }
    if #list == 0 then return nil, 0, 0 end
    return list[1], 1, #list
end

function M.forget() last = nil end

return M
