-- Storage Mage's own art (design.md "UI and styling"): which file to use for a name, and loading it as a texture.
-- Order: the active Frame Mage theme's copy (FrameMage/Art/themes/<theme>/storagemage/<name>.png), then Elven's
-- copy, then Storage Mage's default (StorageMage/Art/default/<name>.png). Without Frame Mage, only the default.
-- The theme comes from Frame Mage's shared variables FrameMage.theme / FrameMage.themeRev (plain values).
-- Textures are loaded fresh by the caller each time they're applied: never keep a UObject across ticks.
local M = {}

M.FALLBACK_THEME = "elven"

-- Pure: the Frame Mage folder next to ours ("<Mods>/StorageMage/" -> "<Mods>/FrameMage/").
function M.frameMageDir(dir)
    local base = dir:gsub("[/\\]+$", "")
    local parent = base:match("^(.*)[/\\][^/\\]+$")
    return (parent or ".") .. "/FrameMage/"
end

-- Pure: the files to try for `name`, best first. theme may be nil (Frame Mage installed but not saying).
function M.candidates(dir, name, frameMage, theme)
    local out = {}
    if frameMage then
        local fm = M.frameMageDir(dir) .. "Art/themes/"
        if theme and theme ~= "" and theme ~= M.FALLBACK_THEME then
            out[#out + 1] = fm .. theme .. "/storagemage/" .. name .. ".png"
        end
        out[#out + 1] = fm .. M.FALLBACK_THEME .. "/storagemage/" .. name .. ".png"
    end
    out[#out + 1] = dir .. "Art/default/" .. name .. ".png"
    return out
end

local function shared(key)
    local ok, v = pcall(function() return ModRef:GetSharedVariable(key) end)
    if ok then return v end
    return nil
end

-- Frame Mage counts as installed when its folder has enabled.txt or its scripts.
function M.frameMageInstalled(ctx)
    local fm = M.frameMageDir(ctx.dir)
    return ctx.fs.exists(fm .. "enabled.txt") or ctx.fs.exists(fm .. "Scripts/main.lua")
end

-- Current theme name and revision (nil, nil when Frame Mage isn't publishing them).
function M.theme()
    local t, r = shared("FrameMage.theme"), shared("FrameMage.themeRev")
    return type(t) == "string" and t or nil, type(r) == "number" and r or nil
end

-- The file to use for `name`, or nil if even the default is missing.
function M.path(ctx, name)
    local fm = M.frameMageInstalled(ctx)
    local theme = fm and M.theme() or nil
    for _, p in ipairs(M.candidates(ctx.dir, name, fm, theme)) do
        if ctx.fs.exists(p) then return p end
    end
    return nil
end

-- Loads a PNG as a (transient) Texture2D. worldContext: any live object in the world (the controller).
function M.load(path, worldContext)
    local ok, tex = pcall(function()
        local lib = StaticFindObject("/Script/Engine.Default__KismetRenderingLibrary")
        return lib:ImportFileAsTexture2D(worldContext, (path:gsub("/", "\\")))
    end)
    if ok then return tex end
    return nil, tex
end

return M
