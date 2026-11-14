-- Hotkeys, read on the game thread.
--
-- Why not RegisterKeyBind: its callbacks run Lua on UE4SS's input thread while the game thread runs the same
-- Lua state, and fast key presses crashed Dragonwilds that way (Mod Menu's author traced it, 2026-11-04).
-- Instead the player controller's key state is polled every frame on the game thread (IsInputKeyDown, plus
-- WasInputKeyJustPressed for taps shorter than a frame), and a binding fires on the press edge.
--
-- Specs are config strings: "F9", "CTRL+F9", "SHIFT+Left", "LeftMouseButton". Key names may be Unreal
-- names (PageDown, LeftBracket, LeftMouseButton: what Mod Menu's key picker saves) or the older UE4SS names
-- (PAGE_DOWN, OEM_FOUR, LEFT_MOUSE_BUTTON); both work. Modifiers must match exactly: plain PageDown does not
-- fire while Ctrl is held, so Ctrl+PageDown can have its own action.
-- Bindings can be changed at runtime (rebind), which is what the Settings panel's Keys tab uses.
local log = require("framemage.core.log")

local M = {}

local MODS = { CTRL = "CONTROL", CONTROL = "CONTROL", SHIFT = "SHIFT", ALT = "ALT" }
local MOD_KEYS = {
    CONTROL = { "LeftControl", "RightControl" },
    SHIFT = { "LeftShift", "RightShift" },
    ALT = { "LeftAlt", "RightAlt" },
}

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
    LEFT_MOUSE_BUTTON = "LeftMouseButton", RIGHT_MOUSE_BUTTON = "RightMouseButton",
    MIDDLE_MOUSE_BUTTON = "MiddleMouseButton", XBUTTON_ONE = "ThumbMouseButton", XBUTTON_TWO = "ThumbMouseButton2",
    ["0"] = "Zero", ["1"] = "One", ["2"] = "Two", ["3"] = "Three", ["4"] = "Four",
    ["5"] = "Five", ["6"] = "Six", ["7"] = "Seven", ["8"] = "Eight", ["9"] = "Nine",
}

-- Pure: a key name in either style -> the Unreal FKey name.
function M.unrealName(name)
    if type(name) ~= "string" or name == "" then return nil end
    local up = name:upper()
    if UNREAL[up] then return UNREAL[up] end
    if up:match("^F%d%d?$") or up:match("^%u$") then return up end
    return name -- assume it already is an Unreal name (FNames are case-insensitive)
end

-- Pure: "CTRL+SHIFT+F9" -> { key = "F9", mods = { "CONTROL", "SHIFT" } }
-- A chord of keys held together uses "&": "Gamepad_LeftThumbstick&Gamepad_RightThumbstick" (both sticks
-- clicked) -> { key = first, chord = { all keys } }.
function M.parse(spec)
    if type(spec) ~= "string" or spec == "" or spec:lower() == "none" then return nil, "no key" end
    local parts = {}
    for p in spec:gmatch("[^+%s]+") do parts[#parts + 1] = p end
    if #parts == 0 then return nil, "no key" end
    local last = table.remove(parts)
    local chord
    if last:find("&", 1, true) then
        chord = {}
        for k in last:gmatch("[^&]+") do chord[#chord + 1] = M.unrealName(k) end
        if #chord == 0 then return nil, "no key" end
    end
    local key = chord and chord[1] or M.unrealName(last)
    local mods = {}
    for _, m in ipairs(parts) do
        local mm = MODS[m:upper()]
        if not mm then return nil, "unknown modifier " .. m end
        mods[#mods + 1] = mm
    end
    return { key = key, mods = mods, chord = chord }
end

-- Pure: is this an Unreal gamepad key (for device tracking and the legend)?
function M.isGamepad(name) return type(name) == "string" and name:sub(1, 7) == "Gamepad" end

-- Pure: does a binding with `mods` match the modifier state `held` ({CONTROL=bool, SHIFT=bool, ALT=bool})?
function M.modsMatch(mods, held)
    local want = { CONTROL = false, SHIFT = false, ALT = false }
    for _, m in ipairs(mods) do want[m] = true end
    for m, w in pairs(want) do
        if (held[m] == true) ~= w then return false end
    end
    return true
end

-- Registry --------------------------------------------------------------------------------

local bindings = {} -- list of { name, setting, spec, parsed, extraMods, fn, when, repeats, down, nextRepeat }
local REPEAT_DELAY, REPEAT_EVERY = 0.35, 0.07

local function compile(b)
    local parsed, err = M.parse(b.spec)
    if not parsed then
        b.parsed = nil
        if b.spec and b.spec ~= "" and b.spec:lower() ~= "none" then
            log.warn("hotkey '%s' = %q ignored: %s", b.name, tostring(b.spec), err)
        end
        return
    end
    for _, m in ipairs(b.extraMods or {}) do parsed.mods[#parsed.mods + 1] = MODS[m:upper()] or m end
    b.parsed = parsed
end

-- bind(spec, name, fn [, extraMods [, opts]])
--   extraMods: e.g. { "SHIFT" } to bind a Shift variant of the same setting
--   opts.setting: settings.keys entry this follows on rebind (default: name)
--   opts.when:    predicate; the key isn't even polled while it returns false (keeps idle cost low)
--   opts.repeats: fire again while held (after a short delay), for nudging
function M.bind(spec, name, fn, extraMods, opts)
    opts = opts or {}
    local b = { name = name, setting = opts.setting or name, spec = spec, extraMods = extraMods, fn = fn,
        when = opts.when, repeats = opts.repeats, down = false }
    compile(b)
    bindings[#bindings + 1] = b
    return b.parsed ~= nil
end

-- Change every binding that follows settings.keys[setting] to a new spec (takes effect immediately).
function M.rebind(setting, spec)
    local n = 0
    for _, b in ipairs(bindings) do
        if b.setting == setting then b.spec = spec; b.down = false; compile(b); n = n + 1 end
    end
    return n
end

-- The current spec for a setting (for the hotkey legend).
function M.specFor(setting)
    for _, b in ipairs(bindings) do
        if b.setting == setting and not b.extraMods then return b.spec end
    end
    return nil
end

-- Polling -----------------------------------------------------------------------------------

local pc, pcRetryAt = nil, 0
local fkeys = {} -- Unreal name -> FKey struct table (built once per name)

local function fkey(name)
    local k = fkeys[name]
    if not k then k = { KeyName = FName(name) }; fkeys[name] = k end
    return k
end

local function controller(W)
    if pc and W.valid(pc) then return pc end
    pc = nil
    if os.clock() < pcRetryAt then return nil end
    pcRetryAt = os.clock() + 1
    local ok, p = pcall(function()
        local gs = StaticFindObject("/Script/Engine.Default__GameplayStatics")
        return gs:GetPlayerController(FindFirstOf("GameInstance"), 0)
    end)
    if ok and W.valid(p) then pc = p return pc end
    p = FindFirstOf("PlayerController")
    if W.valid(p) then pc = p end
    return pc
end

function M.forgetController() pc = nil; pcRetryAt = 0 end

-- Last input device a binding fired from ("keyboard" or "gamepad"); the legend switches its glyphs on it.
M.device = "keyboard"
M.deviceChanges = 0
local function noteDevice(key)
    local d = M.isGamepad(key) and "gamepad" or "keyboard"
    if d ~= M.device then M.device = d; M.deviceChanges = M.deviceChanges + 1 end
end
function M.noteMouse() if M.device ~= "keyboard" then M.device = "keyboard"; M.deviceChanges = M.deviceChanges + 1 end end

function M.noteGamepad() if M.device ~= "gamepad" then M.device = "gamepad"; M.deviceChanges = M.deviceChanges + 1 end end

-- Is a key held right now (one-off read, outside the bindings)?
function M.isDown(name)
    if not pc then return false end
    local ok, d = pcall(function() return pc:IsInputKeyDown(fkey(M.unrealName(name))) end)
    return ok and d == true
end

-- Did a key go down since the last frame (e.g. MouseScrollUp, which is never "held")?
function M.justPressed(name)
    if not pc then return false end
    local ok, d = pcall(function() return pc:WasInputKeyJustPressed(fkey(M.unrealName(name))) end)
    return ok and d == true
end

-- Analog value of an axis key (Gamepad_LeftX, Gamepad_LeftY, Gamepad_LeftTriggerAxis ...), or 0.
function M.analog(name)
    if not pc then return 0 end
    local ok, v = pcall(function() return pc:GetInputAnalogKeyState(fkey(name)) end)
    if ok and type(v) == "number" then return v end
    return 0
end

-- Key capture (the Settings panel's rebinding): the next real key press, with Ctrl / Shift / Alt if held, is handed
-- to the callback as a spec ("CTRL+F9"); Escape cancels (nil). While capturing, no binding fires, and afterwards
-- the key just pressed doesn't also fire its old action.
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
        "Decimal", "Gamepad_FaceButton_Bottom", "Gamepad_FaceButton_Right", "Gamepad_FaceButton_Left",
        "Gamepad_FaceButton_Top", "Gamepad_LeftShoulder", "Gamepad_RightShoulder", "Gamepad_LeftTrigger",
        "Gamepad_RightTrigger", "Gamepad_DPad_Up", "Gamepad_DPad_Down", "Gamepad_DPad_Left", "Gamepad_DPad_Right",
        "Gamepad_Special_Left", "Gamepad_Special_Right", "Gamepad_LeftThumbstick", "Gamepad_RightThumbstick" }) do
        M.CAPTURE_KEYS[#M.CAPTURE_KEYS + 1] = k
    end
end
local captureCb

function M.capture(cb) captureCb = cb end
function M.cancelCapture() captureCb = nil end
function M.capturing() return captureCb ~= nil end

-- Pure: a spec from held modifiers and a key ("CTRL+SHIFT+F9"). Unit-tested.
function M.specOf(held, key)
    local parts = {}
    for _, m in ipairs({ "CONTROL", "SHIFT", "ALT" }) do
        if held[m] then parts[#parts + 1] = (m == "CONTROL") and "CTRL" or m end
    end
    parts[#parts + 1] = key
    return table.concat(parts, "+")
end

local function tick(W, sched)
    local p = controller(W)
    if not p then return end
    local cache = {}
    local function isDown(name)
        local v = cache[name]
        if v ~= nil then return v end
        local ok, d = pcall(function() return p:IsInputKeyDown(fkey(name)) end)
        v = ok and d == true
        cache[name] = v
        return v
    end
    local function justPressed(name)
        local ok, d = pcall(function() return p:WasInputKeyJustPressed(fkey(name)) end)
        return ok and d == true
    end
    if captureCb then
        local spec, done
        if justPressed("Escape") then done = true
        else
            for _, k in ipairs(M.CAPTURE_KEYS) do
                if justPressed(k) then
                    local mods = {}
                    for m, names in pairs(MOD_KEYS) do mods[m] = isDown(names[1]) or isDown(names[2]) end
                    spec, done = M.specOf(mods, k), true
                    break
                end
            end
        end
        if done then
            local cb = captureCb
            captureCb = nil
            -- the key just pressed is still down: don't let it fire its old action on release of the capture
            for _, b in ipairs(bindings) do
                if b.parsed then b.down = isDown(b.parsed.key) end
            end
            sched.safe("key:capture", function() cb(spec) end)()
        end
        return
    end
    local held
    local now = os.clock()
    for _, b in ipairs(bindings) do
        local parsed = b.parsed
        if parsed and (not b.when or b.when()) then
            if not held then
                held = {}
                for m, names in pairs(MOD_KEYS) do held[m] = isDown(names[1]) or isDown(names[2]) end
            end
            local down
            if parsed.chord then
                down = true
                for _, k in ipairs(parsed.chord) do if not isDown(k) then down = false break end end
            else
                down = isDown(parsed.key)
            end
            local pressed = down and not b.down
            if not parsed.chord and not down and not b.down and justPressed(parsed.key) then
                pressed = true -- a tap within one frame
            end
            if pressed and M.modsMatch(parsed.mods, held) then
                noteDevice(parsed.key)
                b.nextRepeat = now + REPEAT_DELAY
                sched.safe("key:" .. b.name, b.fn)()
            elseif down and b.down and b.repeats and b.nextRepeat and now >= b.nextRepeat
                and M.modsMatch(parsed.mods, held) then
                b.nextRepeat = now + REPEAT_EVERY
                sched.safe("key:" .. b.name, b.fn)()
            end
            b.down = down
        else
            b.down = false
        end
    end
end

function M.start(ctx)
    ctx.sched.every(16, "keys.poll", function() tick(ctx.widgets, ctx.sched) end)
    ctx.events.on("worldchanged", M.forgetController)
end

return M
