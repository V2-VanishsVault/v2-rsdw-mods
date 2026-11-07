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

function M.isMaterial(kind)
    return kind ~= nil and kind:find("Material", 1, true) ~= nil
end

return M
