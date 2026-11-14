-- The inventory screen as the game builds it: finding the widget that's on display. Used by the Tool Belt tab
-- (belttab) and the take-out key (bagmoves); the developer dumps use it too.
local M = {}

local O = require("storagemage.core.objects")

local function try(fn, ...)
    local ok, v = pcall(fn, ...)
    if ok then return v end
    return nil
end

-- The classes the inventory screen's navigation widget can be found as (it holds the tab group, the page
-- switcher and the page bodies).
M.NAV_CLASSES = { "WBP_Inventory_VerticalNavigation_C", "InventoryMainPanelContent" }

-- The inventory screen's navigation widget that's on display (nil when the inventory is closed), plus every
-- candidate looked at. FindAllOf can return template copies (a widget blueprint's own tree, a class default) that
-- are never on screen, so the one picked is visible and in the viewport (or at least visible). Never keep the
-- result past this tick.
function M.findNav()
    local cands = {}
    for _, cls in ipairs(M.NAV_CLASSES) do
        local all = try(function() return FindAllOf(cls) end)
        for _, w in ipairs(all or {}) do
            if O.valid(w) then
                local id = try(function() return w:GetFullName() end) or "?"
                if not id:find("Default__", 1, true) then
                    local root = try(function() return w:GetOuter():GetOuter() end)
                    cands[#cands + 1] = { w = w, id = id, cls = cls,
                        vis = try(function() return w:IsVisible() end),
                        port = try(function() return w:IsInViewport() end),
                        rootPort = root and try(function() return root:IsInViewport() end) }
                end
            end
        end
    end
    local pick
    for _, c in ipairs(cands) do if c.vis == true and (c.port == true or c.rootPort == true) then pick = c break end end
    if not pick then for _, c in ipairs(cands) do if c.vis == true then pick = c break end end end
    return pick, cands
end

return M
