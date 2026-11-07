-- Runtime overlay widgets (no blueprint assets needed): a UserWidget with a CanvasPanel root, added to
-- the viewport at a chosen Z order. Used by the editor banner and the grid; reuse for future HUD features.
local M = {}

local builds = 0
local ours = {} -- fullName -> true for every overlay root we created

function M.new(cls, outer, name)
    return StaticConstructObject(StaticFindObject("/Script/UMG." .. cls), outer, FName(name))
end

-- Returns { uw, tree, canvas, suffix }. Names are unique per build: old objects may linger until GC.
function M.host(name, zOrder)
    builds = builds + 1
    local suffix = name .. builds
    local uw = M.new("UserWidget", FindFirstOf("GameInstance"), "FF_" .. suffix)
    local tree = M.new("WidgetTree", uw, "FF_Tree_" .. suffix)
    uw.WidgetTree = tree
    local canvas = M.new("CanvasPanel", tree, "FF_Canvas_" .. suffix)
    tree.RootWidget = canvas
    uw:AddToViewport(zOrder)
    ours[uw:GetFullName()] = true
    return { uw = uw, tree = tree, canvas = canvas, suffix = suffix }
end

function M.isOurs(w)
    local ok, full = pcall(function() return w:GetFullName() end)
    return ok and ours[full] == true
end

return M
