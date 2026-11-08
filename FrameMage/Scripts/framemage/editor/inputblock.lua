-- Keeps the game's own key bindings (radial menus, inventory, emotes, attacks...) quiet while the editor is open.
--
-- The game uses Enhanced Input: actions come from input mapping contexts, highest priority first, and an action
-- that "consumes input" stops lower contexts from seeing the same key. So while editing, one context of ours sits
-- on top, mapping every keyboard, mouse and controller key to an action that does nothing and consumes it.
-- Frame Mage's own hotkeys are unaffected: they read raw key states from the player controller, not actions.
-- Escape is blocked too: it closes the editor (keys.closeEditor), and the block comes off ignoring keys still held,
-- so that same press doesn't open the pause menu.
local M = {}

local W = require("framemage.core.widgets")

local log
local applied -- { sub, context, action } while blocking

local KEYS = {}
do
    for c in ("ABCDEFGHIJKLMNOPQRSTUVWXYZ"):gmatch(".") do KEYS[#KEYS + 1] = c end
    for _, d in ipairs({ "Zero", "One", "Two", "Three", "Four", "Five", "Six", "Seven", "Eight", "Nine" }) do
        KEYS[#KEYS + 1] = d
        KEYS[#KEYS + 1] = "NumPad" .. d
    end
    for i = 1, 12 do KEYS[#KEYS + 1] = "F" .. i end
    for _, k in ipairs({
        "Escape", "SpaceBar", "Tab", "Enter", "BackSpace", "CapsLock", "LeftShift", "RightShift", "LeftControl", "RightControl",
        "LeftAlt", "RightAlt", "Tilde", "Hyphen", "Equals", "LeftBracket", "RightBracket", "Backslash", "Semicolon",
        "Apostrophe", "Comma", "Period", "Slash", "Insert", "Delete", "Home", "End", "PageUp", "PageDown",
        "Left", "Right", "Up", "Down", "Multiply", "Add", "Subtract", "Decimal", "Divide",
        "LeftMouseButton", "RightMouseButton", "MiddleMouseButton", "ThumbMouseButton", "ThumbMouseButton2",
        "MouseScrollUp", "MouseScrollDown", "MouseWheelAxis", "MouseX", "MouseY",
        "Gamepad_FaceButton_Bottom", "Gamepad_FaceButton_Right", "Gamepad_FaceButton_Left", "Gamepad_FaceButton_Top",
        "Gamepad_LeftShoulder", "Gamepad_RightShoulder", "Gamepad_LeftTrigger", "Gamepad_RightTrigger",
        "Gamepad_LeftTriggerAxis", "Gamepad_RightTriggerAxis",
        "Gamepad_DPad_Up", "Gamepad_DPad_Down", "Gamepad_DPad_Left", "Gamepad_DPad_Right",
        "Gamepad_Special_Left", "Gamepad_Special_Right", "Gamepad_LeftThumbstick", "Gamepad_RightThumbstick",
        "Gamepad_LeftX", "Gamepad_LeftY", "Gamepad_RightX", "Gamepad_RightY",
    }) do KEYS[#KEYS + 1] = k end
end
M.KEYS = KEYS

local function subsystem()
    local s = FindFirstOf("EnhancedInputLocalPlayerSubsystem")
    if W.valid(s) then return s end
    return nil
end

local function build()
    local outer = FindFirstOf("GameInstance")
    local action = StaticConstructObject(StaticFindObject("/Script/EnhancedInput.InputAction"), outer, FName("FM_EditorSwallow"))
    pcall(function() action.bConsumeInput = true end)
    pcall(function() action.ValueType = 0 end) -- Boolean
    local context = StaticConstructObject(StaticFindObject("/Script/EnhancedInput.InputMappingContext"), outer, FName("FM_EditorBlock"))
    local mapped = 0
    for _, k in ipairs(KEYS) do
        if pcall(function() context:MapKey(action, { KeyName = FName(k) }) end) then mapped = mapped + 1 end
    end
    return context, action, mapped
end

local function call(sub, fn, context, priority)
    -- removing: keys still held (the Escape that closed the editor) are ignored until released
    local opts = { bIgnoreAllPressedKeysUntilRelease = priority == nil, bForceImmediately = true, bNotifyUserSettings = false }
    local ok, err
    if priority then
        ok, err = pcall(function() sub[fn](sub, context, priority, opts) end)
        if not ok then ok, err = pcall(function() sub[fn](sub, context, priority) end) end
    else
        ok, err = pcall(function() sub[fn](sub, context, opts) end)
        if not ok then ok, err = pcall(function() sub[fn](sub, context) end) end
    end
    return ok, err
end

function M.block()
    if applied then return end
    local sub = subsystem()
    if not sub then log.warn("editor: Enhanced Input not found; game keys stay active") return end
    local ok, context, action, mapped = pcall(build)
    if not ok then log.warn("editor: could not build the key block: %s", tostring(context)) return end
    local okA, err = call(sub, "AddMappingContext", context, 1000000)
    if not okA then log.warn("editor: could not block game keys: %s", tostring(err)) return end
    applied = { sub = sub, context = context, action = action }
    log.info("editor: game keys blocked (%d keys)", mapped)
end

function M.unblock()
    local a = applied
    applied = nil
    if not a then return end
    if W.valid(a.sub) and W.valid(a.context) then
        local ok, err = call(a.sub, "RemoveMappingContext", a.context)
        if not ok then log.warn("editor: could not unblock game keys: %s", tostring(err)) end
    end
end

-- World changed: the subsystem and our objects may be gone; nothing to undo.
function M.forget() applied = nil end

function M.init(c) log = c.log end

return M
