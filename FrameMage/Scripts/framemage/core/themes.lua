-- UI themes: Demi-human (the default: High Elf meets Dwarven), Warrior, Ranger, Wizard. (core/theme.lua is something else: the parser for
-- material theme files.)
--
-- A theme is a folder, Art/themes/<name>/:
--   <TextureName>.png   replaces that game texture everywhere (see dumps/textures.txt for names and sizes)
--   materials.lua       re-colors animated (material) effects
--   ui/*.png            Frame Mage's own panels, title bars and keycaps
--   theme.lua           colors and sizes for Frame Mage's own panels (data only)
-- Anything a theme doesn't have comes from Demi-human, so a new theme can start empty and fill in over time.
local M = {}

M.LIST = { "demihuman", "warrior", "ranger", "wizard" }
M.LABELS = { demihuman = "Demi-human", warrior = "Warrior", ranger = "Ranger", wizard = "Wizard" }
M.DEFAULT = "demihuman"
-- Old names that still work (settings saved before a rename).
M.ALIASES = { general = "demihuman" }

-- Pure: a theme name with old names mapped to current ones. Unit-tested.
function M.canonical(name)
    if type(name) ~= "string" then return name end
    return M.ALIASES[name] or name
end

-- Built-in style: used when no theme.lua can be read at all (keeps the editor usable without art files).
M.BUILTIN = {
    gold = { 0.86, 0.66, 0.26 },      -- title bars when there's no title-bar art
    ink = { 0.03, 0.02, 0.01 },       -- text on title bars and buttons
    heading = { 0.95, 0.74, 0.32 },   -- section headings on panels
    label = { 0.90, 0.87, 0.80 },     -- ordinary text on panels
    dim = { 0.62, 0.59, 0.53 },       -- separators (+ and /)
    panelColor = { 0.03, 0.03, 0.04, 0.88 }, -- panel fill when there's no panel art
    panelTile = 128,                  -- drawn size of one tile of the panel's stone (UI units)
    frameSize = 64,                   -- drawn size of the frame art (its corners are frameMargin of this)
    frameMargin = 0.25,
    panelPad = { 16, 14, 16, 14 },    -- content inset from the panel's edge: left, top, right, bottom
    titleSize = { 128, 32 },          -- drawn size the title-bar art is sliced against
    titleMargin = { 0.2, 0.3 },       -- horizontal, vertical slice margins
    keySize = 64,
    keyMargin = 0.32,
}

local ctx
local styleCache

function M.init(c) ctx = c end

local function known(name)
    name = M.canonical(name)
    for _, n in ipairs(M.LIST) do if n == name then return true end end
    return false
end
M.known = known

function M.current()
    local t = ctx and M.canonical(ctx.settings.theme)
    if type(t) == "string" and known(t) then return t end
    return M.DEFAULT
end

function M.dir(name) return ctx.dir .. "Art/themes/" .. (name or M.current()) .. "/" end

-- Pure: where to look for a file, in order (the theme, then Demi-human). Unit-tested.
function M.searchOrder(name)
    if name == M.DEFAULT then return { M.DEFAULT } end
    return { name, M.DEFAULT }
end

-- The first theme folder holding `rel` (e.g. "ui/panel_frame.png", "T_Bar_Bg.png"), or nil.
function M.find(rel)
    for _, name in ipairs(M.searchOrder(M.current())) do
        local p = M.dir(name) .. rel
        if ctx.fs.exists(p) then return p end
    end
    return nil
end

-- Has this theme been made yet (does it have its own theme.lua)?
function M.isMade(name) return ctx.fs.exists(M.dir(name) .. "theme.lua") end

-- Pure: deep merge (b over a) for style tables; arrays (colors, paddings) are replaced whole. Unit-tested.
function M.merge(a, b)
    local out = {}
    for k, v in pairs(a or {}) do out[k] = v end
    for k, v in pairs(b or {}) do
        if type(v) == "table" and type(out[k]) == "table" and #v == 0 and next(v) ~= nil then
            out[k] = M.merge(out[k], v)
        else
            out[k] = v
        end
    end
    return out
end

local function readStyle(name)
    local path = M.dir(name) .. "theme.lua"
    local text = ctx.fs.read(path)
    if not text then return nil end
    local t, err = ctx.serialize.parse(text, path)
    if not t then ctx.log.warn("%s not loaded: %s", path, tostring(err)) return nil end
    return t
end

-- The active style: built-in, then Demi-human's theme.lua, then the theme's own.
function M.style()
    if styleCache then return styleCache end
    local s = M.merge(M.BUILTIN, readStyle(M.DEFAULT))
    local cur = M.current()
    if cur ~= M.DEFAULT then s = M.merge(s, readStyle(cur)) end
    styleCache = s
    return s
end

-- A color from the style as an FLinearColor table.
function M.color(key, alpha)
    local c = M.style()[key] or M.BUILTIN[key] or { 1, 1, 1 }
    return { R = c[1], G = c[2], B = c[3], A = alpha or c[4] or 1 }
end

-- Switch theme: saved, art reloaded, Frame Mage's own panels rebuilt. Returns false for an unknown name.
function M.set(name)
    name = M.canonical(name)
    if not known(name) then return false end
    ctx.settings.theme = name
    styleCache = nil
    ctx.saveSettings()
    ctx.events.emit("themechanged", name)
    local made = name == M.DEFAULT or M.isMade(name)
    ctx.log.info("theme: %s%s", M.LABELS[name], made and "" or " (not made yet: Demi-human's art is used)")
    local editor = ctx.features and ctx.features.editor
    if editor and not made then editor.flash(M.LABELS[name] .. " theme is coming soon: showing Demi-human") end
    return true
end

function M.forget() styleCache = nil end

return M
