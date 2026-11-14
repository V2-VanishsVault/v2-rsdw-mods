-- The Settings panel's links to the game and to UE4SS: scheduling, shared variables, the player controller, the
-- screen and the mouse, the input mode while the panel is open. The panel shares no code with the mod it ships in,
-- so these are its own (small) copies of what Frame Mage and Storage Mage each have.
local M = {}

M.modName = "?"
local prefix = "[SettingsPanel]"

function M.setMod(name)
    M.modName = name
    prefix = "[" .. tostring(name) .. "] SettingsPanel"
end

local function emit(level, fmt, ...)
    local ok, msg = pcall(string.format, fmt, ...)
    print(string.format("%s %s: %s\n", prefix, level, ok and msg or tostring(fmt)))
end
function M.info(fmt, ...) emit("INFO", fmt, ...) end
function M.warn(fmt, ...) emit("WARN", fmt, ...) end

-- Scheduling: every callback on the game thread and inside pcall (errors logged once per name).
local failed = {}
function M.safe(name, fn)
    return function(...)
        local ok, err = pcall(fn, ...)
        if not ok and not failed[name] then
            failed[name] = true
            M.warn("%s failed: %s", name, tostring(err))
        end
    end
end
function M.every(ms, name, fn) LoopInGameThreadWithDelay(ms, M.safe(name, fn)) end
function M.later(ms, name, fn) ExecuteInGameThreadWithDelay(ms, M.safe(name, fn)) end
function M.now() return os.clock() end

-- Shared variables ------------------------------------------------------------------------------------------------
-- A long string that doesn't come back whole is split over numbered variables (<key>#1, <key>#2...), and <key>
-- holds "@chunks:<n>".
local CHUNK = 4000

local function rawSet(k, v) return pcall(function() ModRef:SetSharedVariable(k, v) end) end
local function rawGet(k)
    local ok, v = pcall(function() return ModRef:GetSharedVariable(k) end)
    if ok then return v end
    return nil
end

function M.get(k)
    local v = rawGet(k)
    if type(v) == "string" then
        local n = tonumber(v:match("^@chunks:(%d+)$"))
        if n then
            local parts = {}
            for i = 1, n do
                local p = rawGet(k .. "#" .. i)
                if type(p) ~= "string" then return nil end
                parts[i] = p
            end
            return table.concat(parts)
        end
    end
    return v
end

function M.set(k, v)
    if type(v) ~= "string" or #v <= CHUNK then return rawSet(k, v) end
    if rawSet(k, v) and rawGet(k) == v then return true end
    local n = math.ceil(#v / CHUNK)
    for i = 1, n do rawSet(k .. "#" .. i, v:sub((i - 1) * CHUNK + 1, i * CHUNK)) end
    return rawSet(k, "@chunks:" .. n)
end

function M.getNumber(k) return tonumber(M.get(k)) or 0 end

-- Objects -------------------------------------------------------------------------------------------------------

function M.valid(o)
    if o == nil then return false end
    local ok, v = pcall(function() return o:IsValid() end)
    return ok and v == true
end

function M.playerController()
    local ok, pc = pcall(function()
        local gs = StaticFindObject("/Script/Engine.Default__GameplayStatics")
        return gs:GetPlayerController(FindFirstOf("GameInstance"), 0)
    end)
    if ok and M.valid(pc) then return pc end
    pc = FindFirstOf("PlayerController")
    return M.valid(pc) and pc or nil
end

-- Screen and mouse (viewport units: what a full-screen canvas positions things in) ------------------------------

local WLL
local function wll()
    if not M.valid(WLL) then WLL = StaticFindObject("/Script/UMG.Default__WidgetLayoutLibrary") end
    return WLL
end

-- (cx: a world context; a widget of ours or the player controller)
function M.screen(cx)
    cx = cx or M.playerController()
    if not cx then return nil end
    local ok, w, h = pcall(function()
        local px, scale = wll():GetViewportSize(cx), wll():GetViewportScale(cx)
        if not (scale and scale > 0 and px and px.X and px.X > 0) then return nil end
        return px.X / scale, px.Y / scale
    end)
    if ok and w then return w, h end
    return nil
end

function M.mouse(cx)
    if not cx then return nil end
    local ok, p = pcall(function() return wll():GetMousePositionOnViewport(cx) end)
    if ok and p and type(p.X) == "number" then return p.X, p.Y end
    return nil
end

-- Widgets -------------------------------------------------------------------------------------------------------

local builds = 0
function M.newObject(cls, outer, name)
    return StaticConstructObject(StaticFindObject("/Script/UMG." .. cls), outer, FName(name))
end

-- A UserWidget with a CanvasPanel root, added to the viewport: { uw, tree, canvas, suffix, full }.
function M.host(name, zOrder)
    builds = builds + 1
    local suffix = M.modName .. "_" .. name .. builds
    local uw = M.newObject("UserWidget", FindFirstOf("GameInstance"), "SP_" .. suffix)
    local tree = M.newObject("WidgetTree", uw, "SP_Tree_" .. suffix)
    uw.WidgetTree = tree
    local canvas = M.newObject("CanvasPanel", tree, "SP_Canvas_" .. suffix)
    tree.RootWidget = canvas
    uw:AddToViewport(zOrder)
    return { uw = uw, tree = tree, canvas = canvas, suffix = suffix, full = uw:GetFullName() }
end

-- The game's own widgets ------------------------------------------------------------------------------------------

-- The class of a game widget, from a live one (nil when none exists yet: the inventory's is made with the HUD).
function M.classOf(className)
    local w = FindFirstOf(className)
    if not M.valid(w) then return nil end
    local ok, cls = pcall(function() return w:GetClass() end)
    if ok and M.valid(cls) then return cls end
    return nil
end

-- A new widget of a game class (CreateWidget), owned by the local player. nil if it couldn't be made.
function M.createWidget(cls, cx)
    local wbl = StaticFindObject("/Script/UMG.Default__WidgetBlueprintLibrary")
    local pc = M.playerController()
    local ok, w = pcall(function() return wbl:Create(cx, cls, pc) end)
    if ok and M.valid(w) then return w end
    return nil
end

-- The resource (texture or material) a live game Image named `name` shows, if it's `resource` (by name): e.g. the
-- inventory tabs' underline, MI_Menu_Underline. Looked up once.
local resources = {}
function M.imageResource(name, resource)
    local key = name .. "|" .. resource
    local r = resources[key]
    if r and M.valid(r) then return r end
    for _, img in pairs(FindAllOf("Image") or {}) do
        local ok, res = pcall(function()
            if img:GetFName():ToString() ~= name then return nil end
            local o = img.Brush.ResourceObject
            if o and o:GetFName():ToString() == resource then return o end
            return nil
        end)
        if ok and res and M.valid(res) then resources[key] = res return res end
    end
    return nil
end

-- The game's own font, copied from a live key prompt (nil before one exists).
local font
function M.gameFont()
    if font then return font end
    for _, cls in ipairs({ "DomTextBlock", "CommonTextBlock", "TextBlock" }) do
        for _, t in pairs(FindAllOf(cls) or {}) do
            local ok, f = pcall(function()
                if t:GetFName():ToString() ~= "KeyText" then return nil end
                local fo = t.Font
                return { FontObject = fo.FontObject, TypefaceFontName = fo.TypefaceFontName }
            end)
            if ok and f then font = f return f end
        end
    end
    return nil
end

-- A game texture by name (the choices' icons), looked up once.
local textures = {}
function M.gameTexture(name)
    local t = textures[name]
    if t and M.valid(t) then return t end
    for _, tex in pairs(FindAllOf("Texture2D") or {}) do
        local ok, n = pcall(function() return tex:GetFName():ToString() end)
        if ok and n == name and M.valid(tex) then textures[name] = tex return tex end
    end
    return nil
end

-- A PNG file as a texture (the look's pictures, read from Frame Mage's theme folder).
local KRL
function M.loadPng(path, cx)
    if not M.valid(KRL) then KRL = StaticFindObject("/Script/Engine.Default__KismetRenderingLibrary") end
    local ok, t = pcall(function() return KRL:ImportFileAsTexture2D(cx, path) end)
    if ok and M.valid(t) then return t end
    return nil
end

function M.exists(path)
    local f = io.open(path, "rb")
    if f then f:close() return true end
    return false
end

function M.read(path)
    local f = io.open(path, "rb")
    if not f then return nil end
    local s = f:read("a")
    f:close()
    return s
end

function M.write(path, text)
    local f = io.open(path, "wb")
    if not f then return false end
    f:write(text)
    f:close()
    return true
end

-- Input mode: the cursor shows and the character stops while the panel is open on its own -----------------------
-- (Game-and-UI, not UI-only: keys are read from the player controller.) The game's own key bindings are swallowed
-- with an Enhanced Input context of ours on top, mapping every key to an action that consumes it.

local BLOCK_KEYS = {}
do
    for c in ("ABCDEFGHIJKLMNOPQRSTUVWXYZ"):gmatch(".") do BLOCK_KEYS[#BLOCK_KEYS + 1] = c end
    for _, d in ipairs({ "Zero", "One", "Two", "Three", "Four", "Five", "Six", "Seven", "Eight", "Nine" }) do
        BLOCK_KEYS[#BLOCK_KEYS + 1] = d
        BLOCK_KEYS[#BLOCK_KEYS + 1] = "NumPad" .. d
    end
    for i = 1, 12 do BLOCK_KEYS[#BLOCK_KEYS + 1] = "F" .. i end
    for _, k in ipairs({ "Escape", "SpaceBar", "Tab", "Enter", "BackSpace", "LeftShift", "RightShift", "LeftControl",
        "RightControl", "LeftAlt", "RightAlt", "Tilde", "Hyphen", "Equals", "LeftBracket", "RightBracket", "Backslash",
        "Semicolon", "Apostrophe", "Comma", "Period", "Slash", "Insert", "Delete", "Home", "End", "PageUp", "PageDown",
        "Left", "Right", "Up", "Down", "Multiply", "Add", "Subtract", "Decimal", "Divide", "LeftMouseButton",
        "RightMouseButton", "MiddleMouseButton", "ThumbMouseButton", "ThumbMouseButton2", "MouseScrollUp",
        "MouseScrollDown", "MouseWheelAxis", "MouseX", "MouseY" }) do BLOCK_KEYS[#BLOCK_KEYS + 1] = k end
end

local block -- { sub, context } while blocking
local function subsystem()
    local s = FindFirstOf("EnhancedInputLocalPlayerSubsystem")
    return M.valid(s) and s or nil
end

local function setBlock(on)
    if on then
        if block then return end
        local sub = subsystem()
        if not sub then return end
        local ok, context = pcall(function()
            local outer = FindFirstOf("GameInstance")
            local action = StaticConstructObject(StaticFindObject("/Script/EnhancedInput.InputAction"), outer,
                FName("SP_Swallow_" .. M.modName))
            pcall(function() action.bConsumeInput = true end)
            local ctxObj = StaticConstructObject(StaticFindObject("/Script/EnhancedInput.InputMappingContext"), outer,
                FName("SP_Block_" .. M.modName))
            for _, k in ipairs(BLOCK_KEYS) do pcall(function() ctxObj:MapKey(action, { KeyName = FName(k) }) end) end
            return ctxObj
        end)
        if not ok then M.warn("could not build the key block: %s", tostring(context)) return end
        local opts = { bIgnoreAllPressedKeysUntilRelease = false, bForceImmediately = true, bNotifyUserSettings = false }
        local okA = pcall(function() sub:AddMappingContext(context, 1000001, opts) end)
        if not okA then okA = pcall(function() sub:AddMappingContext(context, 1000001) end) end
        if okA then block = { sub = sub, context = context } end
    else
        local b = block
        block = nil
        if not (b and M.valid(b.sub) and M.valid(b.context)) then return end
        -- keys still held (the Escape that closed the panel) are ignored until released
        local opts = { bIgnoreAllPressedKeysUntilRelease = true, bForceImmediately = true, bNotifyUserSettings = false }
        if not pcall(function() b.sub:RemoveMappingContext(b.context, opts) end) then
            pcall(function() b.sub:RemoveMappingContext(b.context) end)
        end
    end
end

function M.setInputMode(on)
    setBlock(on)
    local pc = M.playerController()
    if not pc then return end
    local wbl = StaticFindObject("/Script/UMG.Default__WidgetBlueprintLibrary")
    pcall(function() pc.bShowMouseCursor = on end)
    if on then
        if not pcall(function() wbl:SetInputMode_GameAndUIEx(pc, nil, 0, false, false) end) then
            pcall(function() wbl:SetInputMode_GameAndUIEx(pc, nil, 0, false) end)
        end
    else
        if not pcall(function() wbl:SetInputMode_GameOnly(pc, false) end) then
            pcall(function() wbl:SetInputMode_GameOnly(pc) end)
        end
    end
    pcall(function()
        local pawn = pc:K2_GetPawn()
        if M.valid(pawn) then
            if on then pawn:DisableInput(pc) else pawn:EnableInput(pc) end
        end
    end)
end

-- World changed: the input subsystem's context of ours is gone with it.
function M.forgetInput() block = nil end

return M
