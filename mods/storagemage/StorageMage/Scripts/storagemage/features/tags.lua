-- Bag filter tags on item definitions (design 2.1). A bag page only accepts items whose ItemData carries the
-- page's tag (ItemFilter.StorageMage.<Bag>, see filters.lua), and when a save loads, the game puts an item back
-- in its bag slot ONLY if the page accepts it (otherwise it goes to Items or the hotbar, or is deleted if they're
-- full). So every bag item's definition must be tagged BEFORE the save is read, at the main menu.
--
-- Not every definition is loaded that early, so each pass remembers the path of every bag item it tags
-- (saves/bag-item-paths.txt), and at the main menu those definitions are loaded (LoadAsset) and tagged first.
-- Tags live only in memory (nothing is written to the save); every start re-applies them, on the server and on
-- each client alike.
--
-- Passes: script load, InitGameState (the main menu, before any save), LoadMap, then every 30 s (definitions
-- loaded later in play). Report: dumps/tags.txt.
local M = {}

local F = require("storagemage.filters")
local L = require("storagemage.layout")
local PROBE = require("storagemage.features.probe") -- for its list of ItemData classes

local ctx, log, O

-- Bags whose items get tagged now. Only the Tool Belt (always present) until the other bags have tabs and a way
-- to unlock them: a tagged herb could otherwise land in an invisible Herbs page when the Items page is full.
M.ACTIVE = { toolBelt = true }

local function try(fn, ...)
    local ok, v = pcall(fn, ...)
    if ok then return v end
    return nil
end

local function order()
    local o = {}
    for _, p in ipairs(L.PAGES) do o[#o + 1] = p.bag end
    return o
end

-- Does this ItemData's filter container hold `tag`?
function M.hasTag(data, tag)
    local found = false
    pcall(function()
        data.ItemFilterTags.GameplayTags:ForEach(function(_, elem)
            if try(function() return elem:get().TagName:ToString() end) == tag then found = true end
        end)
    end)
    return found
end

local function addTag(data, tag)
    if M.hasTag(data, tag) then return "had" end
    local ok, err = pcall(function()
        local arr = data.ItemFilterTags.GameplayTags
        local n = arr:GetArrayNum()
        arr[n + 1] = { TagName = FName(tag) }
    end)
    if ok and M.hasTag(data, tag) then return "added" end
    return "failed", err
end

local report, paths, dirty = {}, {}, false
local cacheFile

local function note(fmt, ...)
    report[#report + 1] = string.format(fmt, ...)
    log.info("tags: %s", report[#report])
    if #report > 200 then table.remove(report, 1) end
    ctx.fs.write(ctx.dir .. "dumps/tags.txt", "# Storage Mage bag filter tags (" .. os.date("%Y-%m-%d %H:%M:%S") .. ")\n"
        .. table.concat(report, "\n") .. "\n")
end

-- Load the remembered definitions that aren't in memory yet.
local function loadRemembered()
    local loaded, failed, present = 0, 0, 0
    for path in pairs(paths) do
        if O.valid(try(function() return StaticFindObject(path) end)) then
            present = present + 1
        elseif LoadAsset and pcall(LoadAsset, path) and O.valid(try(function() return StaticFindObject(path) end)) then
            loaded = loaded + 1
        else
            failed = failed + 1
        end
    end
    return loaded, failed, present
end

-- One tagging pass over every loaded ItemData.
function M.pass(why)
    local loaded, failed, present = 0, 0, 0
    if why == "InitGameState" or why == "script load" then loaded, failed, present = loadRemembered() end
    local bags, ord, seen = ctx.settings.bags, order(), {}
    local counts = { matched = 0, added = 0, failed = 0 }
    for _, cls in ipairs(PROBE.ITEM_DATA_CLASSES) do
        for _, d in pairs(try(function() return FindAllOf(cls) end) or {}) do
            local asset = try(function() return O.name(d) end)
            if asset and not seen[asset] and not asset:find("^Default__") and O.valid(d) then
                seen[asset] = true
                local cat = try(function() return d:GetCategory().TagName:ToString() end)
                local bag = F.bagFor(cat, asset, bags, ord, M.ACTIVE)
                if bag then
                    counts.matched = counts.matched + 1
                    local r = addTag(d, F.tagFor(bag))
                    if r == "added" then counts.added = counts.added + 1 end
                    if r == "failed" then counts.failed = counts.failed + 1 end
                    local path = F.pathFromFullName(try(function() return d:GetFullName() end))
                    if path and paths[path] ~= bag then paths[path] = bag; dirty = true end
                end
            end
        end
    end
    if dirty then
        dirty = false
        ctx.fs.write(cacheFile, F.formatPaths(paths))
    end
    if counts.added > 0 or counts.failed > 0 or loaded > 0 or failed > 0 or why ~= "every 30 s" then
        note("%s: %d definitions seen, %d bag items (%d newly tagged, %d failed); remembered: %d already loaded, "
            .. "%d loaded now, %d not loadable", why, M.countKeys(seen), counts.matched, counts.added, counts.failed,
            present, loaded, failed)
    end
    return counts
end

function M.countKeys(t)
    local n = 0
    for _ in pairs(t) do n = n + 1 end
    return n
end

function M.init(c)
    ctx, log, O = c, c.log, c.objects
    cacheFile = ctx.dir .. "saves/bag-item-paths.txt"
    paths = F.parsePaths(ctx.fs.read(cacheFile))
    pcall(M.pass, "script load")
    if RegisterInitGameStatePostHook then
        pcall(RegisterInitGameStatePostHook, ctx.sched.safe("tags init-game-state", function() M.pass("InitGameState") end))
    end
    if RegisterLoadMapPostHook then
        pcall(RegisterLoadMapPostHook, ctx.sched.safe("tags load-map", function() M.pass("LoadMap") end))
    end
    ctx.sched.every(30000, "tags every 30 s", function() M.pass("every 30 s") end)
end

return M
