-- Pure helpers for material themes (unit-tested; no engine calls).
--
-- A theme file (Art/<skin>/materials.lua) maps an effect to parameter overrides:
--   return {
--       MI_Item_Selected = {                      -- effect key or its parent material (see dumps/materials.txt)
--           vectors  = { Color = "#4FA3FF" },     -- hex (#RGB[A] / #RRGGBB[AA]) is sRGB; {r,g,b,a} is linear
--           scalars  = { GlowStrength = 0.6 },
--           textures = { Mask = "selected_mask" },-- PNG in the skin folder (".png" optional)
--           force    = true,                      -- re-apply when the game sets these parameters itself
--       },
--   }
local M = {}

local function srgbToLinear(c)
    if c <= 0.04045 then return c / 12.92 end
    return ((c + 0.055) / 1.055) ^ 2.4
end

-- "#RGB", "#RRGGBB", "#RRGGBBAA" (sRGB) or { r, g, b [, a] } (linear) -> { R=, G=, B=, A= } linear, or nil, err
function M.parseColor(v)
    if type(v) == "table" then
        local r, g, b, a = v[1] or v.R or v.r, v[2] or v.G or v.g, v[3] or v.B or v.b, v[4] or v.A or v.a
        if type(r) ~= "number" or type(g) ~= "number" or type(b) ~= "number" then
            return nil, "color table needs 3 or 4 numbers"
        end
        return { R = r, G = g, B = b, A = type(a) == "number" and a or 1 }
    end
    if type(v) ~= "string" then return nil, "color must be \"#RRGGBB\" or { r, g, b, a }" end
    local hex = v:match("^#?(%x+)$")
    if not hex then return nil, "bad hex color " .. v end
    if #hex == 3 or #hex == 4 then hex = hex:gsub("(%x)", "%1%1") end
    if #hex ~= 6 and #hex ~= 8 then return nil, "hex color needs 3, 4, 6 or 8 digits: " .. v end
    local function byte(i) return tonumber(hex:sub(i, i + 1), 16) / 255 end
    return {
        R = srgbToLinear(byte(1)), G = srgbToLinear(byte(3)), B = srgbToLinear(byte(5)),
        A = #hex == 8 and byte(7) or 1, -- alpha is not gamma-encoded
    }
end

-- Validates a raw theme table. Returns normalized entries and a list of problems (bad entries are skipped,
-- never fatal: one typo must not disable the whole skin).
function M.normalize(raw)
    local out, problems = {}, {}
    if type(raw) ~= "table" then return out, { "theme file must return a table" } end
    for key, spec in pairs(raw) do
        if type(key) ~= "string" or type(spec) ~= "table" then
            problems[#problems + 1] = "entry " .. tostring(key) .. " ignored: must be name = { ... }"
        else
            local e = { scalars = {}, vectors = {}, textures = {}, force = spec.force == true }
            for p, v in pairs(spec.scalars or {}) do
                if type(v) == "number" then e.scalars[p] = v
                else problems[#problems + 1] = key .. ".scalars." .. tostring(p) .. " must be a number" end
            end
            for p, v in pairs(spec.vectors or {}) do
                local c, err = M.parseColor(v)
                if c then e.vectors[p] = c else problems[#problems + 1] = key .. ".vectors." .. tostring(p) .. ": " .. err end
            end
            for p, v in pairs(spec.textures or {}) do
                if type(v) == "string" and v ~= "" then e.textures[p] = (v:gsub("%.[Pp][Nn][Gg]$", ""))
                else problems[#problems + 1] = key .. ".textures." .. tostring(p) .. " must be a file name" end
            end
            out[key] = e
        end
    end
    return out, problems
end

-- The entry for an effect: its own key first, then the material it's a copy of.
function M.lookup(theme, key, parent)
    return theme[key] or (parent and theme[parent]) or nil
end

-- True when any entry asks for force (decides whether the parameter-setter hooks are worth installing).
function M.anyForce(theme)
    for _, e in pairs(theme) do if e.force then return true end end
    return false
end

return M
