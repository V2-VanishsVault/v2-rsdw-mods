-- A short message at the top centre of the screen, so a key press visibly did something.
-- Built at runtime from UMG classes (no assets), the same way as Frame Mage's overlays. A new message replaces
-- the one showing. Client only: on a dedicated server there is no viewport, and show() just logs.
local log = require("storagemage.core.log")
local sched = require("storagemage.core.sched")
local O = require("storagemage.core.objects")

local M = {}

local builds, seq = 0, 0
local current -- the UserWidget showing now (checked with valid() before every use: it may be gone)

local function new(cls, outer, name)
    return StaticConstructObject(StaticFindObject("/Script/UMG." .. cls), outer, FName(name))
end

local function remove(uw)
    if O.valid(uw) then pcall(function() uw:RemoveFromParent() end) end
end

local function build(msg)
    builds = builds + 1
    local id = "SM_Toast" .. builds
    local uw = new("UserWidget", FindFirstOf("GameInstance"), id)
    local tree = new("WidgetTree", uw, id .. "_Tree")
    uw.WidgetTree = tree
    local canvas = new("CanvasPanel", tree, id .. "_Canvas")
    tree.RootWidget = canvas
    local border = new("Border", tree, id .. "_Box")
    border:SetBrushColor({ R = 0.06, G = 0.05, B = 0.04, A = 0.85 })
    border:SetPadding({ Left = 18, Top = 8, Right = 18, Bottom = 8 })
    local text = new("TextBlock", tree, id .. "_Text")
    text:SetText(FText(msg))
    text:SetColorAndOpacity({ SpecifiedColor = { R = 0.96, G = 0.86, B = 0.6, A = 1 }, ColorUseRule = 0 })
    border:SetContent(text)
    local slot = canvas:AddChildToCanvas(border)
    slot:SetAutoSize(true)
    slot:SetAnchors({ Minimum = { X = 0.5, Y = 0 }, Maximum = { X = 0.5, Y = 0 } })
    slot:SetAlignment({ X = 0.5, Y = 0 })
    slot:SetPosition({ X = 0, Y = 140 })
    uw:SetVisibility(3) -- HitTestInvisible: never takes clicks
    uw:AddToViewport(30000)
    return uw
end

-- show(msg [, ms]): also logged, so the message is in UE4SS.log even when the screen can't show it.
function M.show(msg, ms)
    log.info("%s", msg)
    seq = seq + 1
    local mine = seq
    remove(current)
    current = nil
    local ok, uw = pcall(build, "Storage Mage: " .. msg)
    if not ok then
        log.debug("toast: could not show (%s)", tostring(uw))
        return false
    end
    current = uw
    sched.later(ms or 3000, "toast.clear", function()
        if seq ~= mine then return end
        remove(current)
        current = nil
    end)
    return true
end

return M
