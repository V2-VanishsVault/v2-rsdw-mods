-- Pure naming rules for UI brush resources (unit-tested; no engine calls).
--
-- Art is keyed by these names: Art/<skin>/<name>.png replaces every brush showing that resource.
local M = {}

-- A MaterialInstanceDynamic is a per-widget runtime copy named MID_<parent>_<number>; the number changes every
-- session, so all copies of one effect share the base name. Textures keep their numbers: T_Panel_1 and
-- T_Panel_2 are different art.
function M.resourceKey(name, kind)
    if kind == "MaterialInstanceDynamic" then
        return (name:gsub("_%d+$", ""))
    end
    return name
end

-- Game assets live in packages under /Game/ (or a plugin); textures created at runtime (PNG imports by
-- Forgeframe or other mods, render targets) live in the transient package and aren't game art.
function M.isRuntime(fullName)
    return fullName:find("/Engine/Transient", 1, true) ~= nil
end

-- Groups for the artist's checklist: T_Icon_Health -> "Icon", MI_Menu_Underline -> "Menu".
function M.section(name)
    local s = name:match("^T_([^_%-]+)") or name:match("^MID_MI?_?UI_([^_]+)") or name:match("^MID_MI?_([^_]+)")
        or name:match("^MI_UI_([^_]+)") or name:match("^MI?_([^_]+)")
    return s and (s:sub(1, 1):upper() .. s:sub(2)) or "Other"
end

-- Pure: a readable name for a layout key, for the editor banner.
--   "WBP_HUD_RootWidget/HUD_Survival/WBP_SurvivalCore_Upkeep_Hydration" -> "Survival Core Upkeep Hydration"
--   "WBP_HUD/WBP_BuffEntry*" -> "Buff Entry"      "WBP_HUD/Image_12" -> "Image 12"
function M.pretty(key)
    local last = key:match("([^/]+)$") or key
    last = last:gsub("%*$", ""):gsub("_C$", "")
    -- common prefixes that say nothing to a player
    for _, p in ipairs({ "WBP_HUD_", "WBP_", "W_", "HUD_", "UI_", "BP_" }) do
        if last:sub(1, #p) == p and #last > #p then last = last:sub(#p + 1) break end
    end
    last = last:gsub("_", " ")
    last = last:gsub("(%l)(%u)", "%1 %2"):gsub("(%u)(%u%l)", "%1 %2"):gsub("(%a)(%d)", "%1 %2")
    last = last:gsub("%s+", " "):gsub("^%s+", ""):gsub("%s+$", "")
    return last ~= "" and last or key
end

function M.isMaterial(kind)
    return kind ~= nil and kind:find("Material", 1, true) ~= nil
end

return M
