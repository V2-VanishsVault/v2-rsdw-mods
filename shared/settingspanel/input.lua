-- Keys for the Settings panel, read on the game thread from the player controller (never RegisterKeyBind: its
-- callbacks run on another thread and crashed the game). Only the drawing copy polls.
--
-- Specs are the same strings the mods use: "F4", "CTRL+F9", "SHIFT+Left", "PageDown", "Add".
local game = require("settingspanel.game")

local M = {}

-- UE4SS / Windows-style names -> Unreal FKey names
local UNREAL = {
    PAGE_UP = "PageUp", PAGE_DOWN = "PageDown", HOME = "Home", END = "End",
    INS = "Insert", INSERT = "Insert", DEL = "Delete", DELETE = "Delete", BACKSPACE = "BackSpace",
    LEFT_ARROW = "Left", RIGHT_ARROW = "Right", UP_ARROW = "Up", DOWN_ARROW = "Down",
    OEM_PLUS = "Equals", OEM_MINUS = "Hyphen", OEM_FOUR = "LeftBracket", OEM_SIX = "RightBracket",
    OEM_COMMA = "Comma", OEM_PERIOD = "Period", OEM_ONE = "Semicolon", OEM_TWO = "Slash", OEM_THREE = "Tilde",
    OEM_FIVE = "Backslash", OEM_SEVEN = "Apostrophe",
    SPACE = "SpaceBar", RETURN = "Enter", ENTER = "Enter", ESCAPE = "Escape", TAB = "Tab",
    ADD = "Add", SUBTRACT = "Subtract", MULTIPLY = "Multiply", DIVIDE = "Divide",
    ["0"] = "Zero", ["1"] = "One", ["2"] = "Two", ["3"] = "Three", ["4"] = "Four",
    ["5"] = "Five", ["6"] = "Six", ["7"] = "Seven", ["8"] = "Eight", ["9"] = "Nine",
}
local MODS = { CTRL = "CONTROL", CONTROL = "CONTROL", SHIFT = "SHIFT", ALT = "ALT" }
local MOD_KEYS = { CONTROL = { "LeftControl", "RightControl" }, SHIFT = { "LeftShift", "RightShift" },
    ALT = { "LeftAlt", "RightAlt" } }

-- Pure: a key name in either style -> the Unreal name.
function M.unrealName(name)
    if type(name) ~= "string" or name == "" then return nil end
    local up = name:upper()
    if UNREAL[up] then return UNREAL[up] end
    if up:match("^F%d%d?$") or up:match("^%u$") then return up end
    return name
end

-- Pure: "CTRL+F4" -> { key = "F4", mods = { "CONTROL" } }, or nil.
function M.parse(spec)
    if type(spec) ~= "string" or spec == "" or spec:lower() == "none" then return nil end
    local parts = {}
    for p in spec:gmatch("[^+%s]+") do parts[#parts + 1] = p end
    if #parts == 0 then return nil end
    local key = M.unrealName(table.remove(parts))
    local mods = {}
    for _, m in ipairs(parts) do
        local mm = MODS[m:upper()]
        if not mm then return nil end
        mods[#mods + 1] = mm
    end
    return { key = key, mods = mods }
end

-- Pure: do the held modifiers match exactly?
function M.modsMatch(mods, held)
    local want = {}
    for _, m in ipairs(mods) do want[m] = true end
    for m in pairs(MOD_KEYS) do
        if (held[m] == true) ~= (want[m] == true) then return false end
    end
    return true
end

-- Pure: a spec from held modifiers and a key ("CTRL+SHIFT+F9").
function M.specOf(held, key)
    local parts = {}
    for _, m in ipairs({ "CONTROL", "SHIFT", "ALT" }) do
        if held[m] then parts[#parts + 1] = (m == "CONTROL") and "CTRL" or m end
    end
    parts[#parts + 1] = key
    return table.concat(parts, "+")
end

-- The keys a capture listens for.
M.CAPTURE_KEYS = {}
do
    for c in ("ABCDEFGHIJKLMNOPQRSTUVWXYZ"):gmatch(".") do M.CAPTURE_KEYS[#M.CAPTURE_KEYS + 1] = c end
    for _, d in ipairs({ "Zero", "One", "Two", "Three", "Four", "Five", "Six", "Seven", "Eight", "Nine" }) do
        M.CAPTURE_KEYS[#M.CAPTURE_KEYS + 1] = d
        M.CAPTURE_KEYS[#M.CAPTURE_KEYS + 1] = "NumPad" .. d
    end
    for i = 1, 12 do M.CAPTURE_KEYS[#M.CAPTURE_KEYS + 1] = "F" .. i end
    for _, k in ipairs({ "SpaceBar", "Tab", "Enter", "BackSpace", "Insert", "Delete", "Home", "End", "PageUp",
        "PageDown", "Left", "Right", "Up", "Down", "Hyphen", "Equals", "LeftBracket", "RightBracket", "Semicolon",
        "Apostrophe", "Comma", "Period", "Slash", "Backslash", "Tilde", "Add", "Subtract", "Multiply", "Divide",
        "Decimal" }) do M.CAPTURE_KEYS[#M.CAPTURE_KEYS + 1] = k end
end

-- Runtime --------------------------------------------------------------------------------------------------------

local pc, pcAt = nil, -10
local fkeys = {}
local function fkey(name)
    local k = fkeys[name]
    if not k then k = { KeyName = FName(name) }; fkeys[name] = k end
    return k
end

local function controller()
    if pc and game.valid(pc) then return pc end
    pc = nil
    if game.now() - pcAt < 1 then return nil end
    pcAt = game.now()
    pc = game.playerController()
    return pc
end

function M.forget() pc = nil; pcAt = -10 end

function M.isDown(name)
    local p = controller()
    if not p then return false end
    local ok, d = pcall(function() return p:IsInputKeyDown(fkey(name)) end)
    return ok and d == true
end

function M.justPressed(name)
    local p = controller()
    if not p then return false end
    local ok, d = pcall(function() return p:WasInputKeyJustPressed(fkey(name)) end)
    return ok and d == true
end

local function held()
    local h = {}
    for m, names in pairs(MOD_KEYS) do h[m] = M.isDown(names[1]) or M.isDown(names[2]) end
    return h
end

-- Edge detection for a spec: true once per press.
local wasDown = {}
local quiet -- a key just captured: it fires nothing until it's let go (it may be the panel's new open key)
function M.pressed(spec)
    local p = M.parse(spec)
    if not p then return false end
    local down = M.isDown(p.key)
    if quiet == p.key then
        if down then wasDown[spec] = true return false end
        quiet = nil
    end
    local edge = down and not wasDown[spec]
    if not down and not wasDown[spec] and M.justPressed(p.key) then edge = true end -- a tap within one frame
    wasDown[spec] = down
    return edge and M.modsMatch(p.mods, held())
end

-- Pure: did a key go down? (held now and not at the last look, or reported as just pressed: a tap between two looks)
function M.wentDown(nowDown, wasDownBefore, justPressed)
    return (nowDown and not wasDownBefore) or justPressed == true
end

-- Key capture: the next key pressed (with modifiers) as a spec; Escape gives nil (cancel). Returns spec, done.
-- Every key's held state is watched while capturing: "just pressed" alone is only true for the one frame of the
-- press, and a quick tap between two looks was missed (the user had to press T several times).
local capHeld = {}
function M.startCapture()
    capHeld = {}
    for _, k in ipairs(M.CAPTURE_KEYS) do capHeld[k] = M.isDown(k) end -- (keys already held don't count)
    capHeld.Escape = M.isDown("Escape")
end

local function went(k)
    local down = M.isDown(k)
    local was = capHeld[k]
    capHeld[k] = down
    return M.wentDown(down, was, (not down and not was) and M.justPressed(k) or false)
end

function M.pollCapture()
    if went("Escape") then
        for s in pairs(wasDown) do wasDown[s] = true end
        return nil, true
    end
    for _, k in ipairs(M.CAPTURE_KEYS) do
        if went(k) then
            -- the key just pressed is still down: none of the panel's own keys fire from this press
            for s in pairs(wasDown) do wasDown[s] = true end
            quiet = k
            return M.specOf(held(), k), true
        end
    end
    return nil, false
end

return M
