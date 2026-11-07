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
-- Bindings can be changed at runtime (rebind), which is what Mod Menu's hotkey page uses.
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
function M.parse(spec)
    if type(spec) ~= "string" or spec == "" or spec:lower() == "none" then return nil, "no key" end
    local parts = {}
    for p in spec:gmatch("[^+%s]+") do parts[#parts + 1] = p end
    if #parts == 0 then return nil, "no key" end
    local key = M.unrealName(table.remove(parts))
    local mods = {}
    for _, m in ipairs(parts) do
        local mm = MODS[m:upper()]
        if not mm then return nil, "unknown modifier " .. m end
        mods[#mods + 1] = mm
    end
    return { key = key, mods = mods }
end

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
    local held
    local now = os.clock()
    for _, b in ipairs(bindings) do
        local parsed = b.parsed
        if parsed and (not b.when or b.when()) then
            if not held then
                held = {}
                for m, names in pairs(MOD_KEYS) do held[m] = isDown(names[1]) or isDown(names[2]) end
            end
            local down = isDown(parsed.key)
            local pressed = down and not b.down
            if not down and not b.down and justPressed(parsed.key) then pressed = true end -- a tap within one frame
            if pressed and M.modsMatch(parsed.mods, held) then
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
