-- Developer: the API dump (Numpad +, keys.dumpApi). The game's functions for the classes a feature needs to drive,
-- from runtime reflection, written to dumps/api.txt. Not in releases: this file lives in dev/, which only a
-- development install has (tools\deploy.ps1 -Link). The class list is dev/framemage/data/api_classes.lua, made by
-- tools/gen_api_classes.py.
local M = {}

local ctx, W, log

-- API dump (Numpad +, keys.dumpApi) -----------------------------------------------------------------------------------
-- The game's functions for the classes a feature needs to drive (the hotbar, items, spells; and for Storage Mage:
-- crafting, workbenches, pickups, loot and carry weight), with their
-- parameters, from runtime reflection: the .usmap type map only has data fields. Written to dumps/api.txt.

-- Pure: should a class with this name be in the API dump? Unit-tested.
M.API_PATTERNS = { "QuickAccess", "Inventory", "Loadout", "Equipment", "Spellcasting", "SpellBook", "Spellbook",
    "SpellData", "SpellPayload", "Radial", "ItemSlot", "ItemData", "ItemStack", "HeldEquipment", "Hotbar",
    "PlayerCharacter", "DomPlayerController", "ActionBar",
    -- Storage Mage (bags): crafting and workbenches, pickups and loot, carry weight
    "Crafting", "Recipe", "Station", "Pickup", "Pickupable", "Loot", "CarryWeight", "ItemWeight", "WeightBar" }
function M.wantsApi(className)
    if className:match("^Default__") or className:match("^SKEL_") or className:match("^REINST_") then return false end
    for _, p in ipairs(M.API_PATTERNS) do
        if className:find(p, 1, true) then return true end
    end
    return false
end

-- Only the safest reflection calls: names, and each parameter's name and property type. (An earlier version also
-- asked parameters for their classes / structs / flags; one of those crashed the game natively, where pcall can't
-- help.) Each step is logged before it runs, so if the game ever does go down, the log shows where.
local function paramText(prop)
    local okN, name = pcall(function() return prop:GetFName():ToString() end)
    local okT, typ = pcall(function() return prop:GetClass():GetFName():ToString() end)
    return (okT and typ:gsub("Property$", "") or "?") .. " " .. (okN and name or "?")
end

local function functionLine(fn)
    local okN, name = pcall(function() return fn:GetFName():ToString() end)
    local params = {}
    pcall(function()
        fn:ForEachProperty(function(prop) params[#params + 1] = paramText(prop) end)
    end)
    return string.format("  %s(%s)", okN and name or "?", table.concat(params, ", "))
end

-- Pure: the script module a class path lives in ("/Script/Dominion.InventoryComponent" -> "Dominion"). Unit-tested.
function M.moduleOf(path)
    if type(path) ~= "string" then return nil end
    return path:match("/Script/([%w_]+)%.")
end

-- The classes come from data/api_classes.lua (made from the game's type map by tools/gen_api_classes.py): this
-- UE4SS build can't list classes in game, so each is looked up by name: by its script path (fast), or for
-- blueprint classes (..._C) from a live instance. Each step is logged before it runs.
function M.dumpApi()
    local t0 = os.clock()
    local okL, names = pcall(require, "framemage.data.api_classes")
    if not okL or type(names) ~= "table" then log.warn("API dump: no class list (%s)", tostring(names)) return end
    -- the game's own script module, learned from a class we know is there
    local modules, seenMod = {}, {}
    local function addModule(m) if m and not seenMod[m] then seenMod[m] = true; modules[#modules + 1] = m end end
    for _, probe in ipairs({ "InventoryComponent", "SpellcastingComponent", "PlayerController" }) do
        log.info("API dump: looking for a live %s", probe)
        local inst = FindFirstOf(probe)
        if W.valid(inst) then
            pcall(function() addModule(M.moduleOf(inst:GetClass():GetPathName())) end)
        end
    end
    for _, m in ipairs({ "Dominion", "DominionUI", "RSDragonwilds", "CommonUI", "CommonInput", "UMG", "Engine" }) do
        addModule(m)
    end
    log.info("API dump: modules %s; %d classes to look up", table.concat(modules, ", "), #names)

    local lines = { "# Frame Mage API dump " .. os.date("%Y-%m-%d %H:%M:%S"),
        "# Game classes Frame Mage and Storage Mage need (hotbar, items, spells, crafting, pickups, weight),",
        "# with their functions and each parameter's name and type. Modules searched: " .. table.concat(modules, ", "),
        "" }
    local nClasses, nFns, missing = 0, 0, {}
    for _, name in ipairs(names) do
        local cls
        for _, m in ipairs(modules) do
            local c = StaticFindObject("/Script/" .. m .. "." .. name)
            if W.valid(c) then cls = c break end
        end
        if not cls and name:match("_C$") then
            local inst = FindFirstOf(name)
            if W.valid(inst) then pcall(function() cls = inst:GetClass() end) end
        end
        if cls then
            local fns, err = {}, nil
            local ok, e = pcall(function()
                cls:ForEachFunction(function(fn) fns[#fns + 1] = functionLine(fn) end)
            end)
            if not ok then err = tostring(e) end
            if #fns > 0 or err then
                table.sort(fns)
                local okS, super = pcall(function() return cls:GetSuperStruct():GetFName():ToString() end)
                local okP, path = pcall(function() return cls:GetPathName() end)
                lines[#lines + 1] = string.format("%s : %s    (%s)%s", name, okS and super or "?", okP and path or "",
                    err and ("  [error: " .. err .. "]") or "")
                for _, f in ipairs(fns) do lines[#lines + 1] = f end
                lines[#lines + 1] = ""
                nClasses, nFns = nClasses + 1, nFns + #fns
            end
        else
            missing[#missing + 1] = name
        end
    end
    lines[#lines + 1] = "# Not found (structs, or not loaded right now): " .. table.concat(missing, ", ")
    ctx.fs.write(ctx.dir .. "dumps/api.txt", table.concat(lines, "\n"))
    log.info("API dump: %d classes, %d functions in %.1f s (%d not found) -> dumps/api.txt", nClasses, nFns,
        os.clock() - t0, #missing)
    local legend = require("framemage.editor.legend")
    if legend.flash then legend.flash(string.format("API dump: %d classes, %d functions", nClasses, nFns)) end
end

function M.init(c)
    ctx, W, log = c, c.widgets, c.log
    c.keys.bind(c.settings.keys.dumpApi, "dumpApi", function()
        local ok, err = pcall(M.dumpApi)
        if not ok then log.error("API dump failed: %s", tostring(err)) end
    end)
end

return M
