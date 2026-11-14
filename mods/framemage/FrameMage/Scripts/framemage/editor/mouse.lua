-- Mouse input for the editor, independent of the game's input routing.
--
-- Reading LeftMouseButton from the player controller didn't work in game: with a cursor shown, a click lands on
-- the UI first and the game's UI framework (CommonUI) decides whether the game ever sees it. So while the editor is
-- open, a transparent full-screen "catcher" of ours sits over the HUD (under Frame Mage's own overlays, which
-- don't take clicks) and Unreal's own UserWidget mouse events are hooked: every click and release lands on the
-- catcher, whatever the game's input mode. It also keeps clicks off the game's buttons while you edit.
-- Fallback: if the hooks never fire on this build, the button is read from the player controller as before.
local overlay = require("framemage.core.overlay")
local W = require("framemage.core.widgets")
local geometry = require("framemage.core.geometry")
local keys = require("framemage.core.keys")

local M = {}

local ctx, log
local catcher -- { uw, full }
local handlers -- { down = fn(x, y, button), up = fn(x, y, button) }
local active = false
local hookSeen = false -- a hooked event arrived this session: ignore the polling fallback
local polledDown = false

local function build()
    local h = overlay.host("Catcher", 18990)
    local img = overlay.new("Image", h.tree, "FM_Catcher_" .. h.suffix)
    img:SetColorAndOpacity({ R = 0, G = 0, B = 0, A = 0 }) -- invisible, but still hit-tested (hit-testing is geometric)
    local slot = h.canvas:AddChildToCanvas(img)
    slot:SetAnchors({ Minimum = { X = 0, Y = 0 }, Maximum = { X = 1, Y = 1 } })
    slot:SetOffsets({ Left = 0, Top = 0, Right = 0, Bottom = 0 })
    img:SetVisibility(0) -- Visible: takes clicks
    h.uw:SetVisibility(1)
    catcher = { uw = h.uw, full = h.uw:GetFullName(), canvas = h.canvas }
end

-- Which button: the hooked pointer event can't be read from Lua (FPointerEvent has no script-visible fields), so
-- the button is read from the player controller's key state at that moment, defaulting to the left button.
local downButton -- the button of the press in progress (its release reports the same one)
local function currentButton()
    if keys.isDown("RightMouseButton") then return "RightMouseButton" end
    if keys.isDown("MiddleMouseButton") then return "MiddleMouseButton" end
    return "LeftMouseButton"
end

local function emit(kind, button)
    local x, y = geometry.mouse()
    if not x then log.warn("editor mouse %s: no position (no world context)", kind) return end
    if kind == "down" then log.info("editor click %s at %.0f, %.0f", button, x, y) end
    keys.noteMouse()
    local fn = handlers and handlers[kind]
    if fn then
        local ok, err = pcall(fn, x, y, button)
        if not ok then log.warn("editor mouse %s failed: %s", kind, tostring(err)) end
    end
end

-- One hook per event, registered once; each returns immediately unless the editor is open and the event is ours.
local function hook(fnPath, kind)
    local ok, err = pcall(RegisterHook, fnPath, function(self)
        if not (active and catcher) then return end
        local okS, full = pcall(function() return self:get():GetFullName() end)
        if not (okS and full == catcher.full) then return end
        hookSeen = true
        if kind == "down" then downButton = currentButton() end
        emit(kind, downButton or "LeftMouseButton")
    end)
    if not ok then log.warn("editor: could not hook %s (%s); using the fallback", fnPath, tostring(err)) end
    return ok
end

function M.open()
    if not (catcher and W.valid(catcher.uw)) then
        local ok, err = pcall(build)
        if not ok then log.warn("editor mouse catcher unavailable: %s", tostring(err)); catcher = nil end
    end
    if catcher then pcall(function() catcher.uw:SetVisibility(0) end) end
    -- the mouse position needs a world context: the editor's frame gives one while the editor is open; with the
    -- Settings panel open on its own, the catcher's canvas is it
    if catcher and not geometry.hasReference() then geometry.setReference(catcher.canvas) end
    active = true
    polledDown = false
end

function M.close()
    active = false
    if catcher and W.valid(catcher.uw) then pcall(function() catcher.uw:SetVisibility(1) end) end
end

-- Fallback, every editor frame: the player controller's view of the left button (only until a hook has fired).
function M.tick()
    if not active then return end
    -- the wheel: polled (scrolling over a widget that ignores it reaches the player controller)
    if handlers and handlers.wheel then
        local up, down = keys.justPressed("MouseScrollUp"), keys.justPressed("MouseScrollDown")
        if up or down then
            local x, y = geometry.mouse()
            if x then pcall(handlers.wheel, x, y, up and 1 or -1) end
        end
    end
    if hookSeen then return end
    local down = keys.isDown and keys.isDown("LeftMouseButton")
    if down and not polledDown then emit("down", "LeftMouseButton")
    elseif not down and polledDown then emit("up", "LeftMouseButton") end
    polledDown = down
end

function M.isOurs(w) return overlay.isOurs(w) end
function M.forget() catcher = nil; active = false end

function M.init(c, h)
    ctx, log, handlers = c, c.log, h
    hook("/Script/UMG.UserWidget:OnMouseButtonDown", "down")
    hook("/Script/UMG.UserWidget:OnMouseButtonUp", "up")
end

return M
