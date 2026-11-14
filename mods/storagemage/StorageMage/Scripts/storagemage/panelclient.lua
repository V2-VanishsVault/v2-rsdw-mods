-- Storage Mage's tab in the Settings panel every Mage mod shares (shared/settingspanel in the repository, shipped
-- as Scripts/settingspanel). Storage Mage is a client like every other mod: it publishes its rows and values, and
-- applies the changes that come back. Whichever mod's copy of the panel is newest draws it (in Frame Mage's theme
-- when Frame Mage is installed, plain otherwise).
local M = {}

M.TABS = { { id = "bags", label = "Bags" } }

-- The rows. (Planned with the bags themselves: the carry-weight slider, "Empty bags" before uninstalling.)
M.ROWS = {
    { tab = "bags", type = "bool", setting = "pickupRouting", label = "Pickups go into bags",
        tooltip = "Items you pick up, take from a chest or craft go straight into the bag they belong in.",
        applies = "restart", owner = "server" },
    { tab = "bags", type = "key", setting = "keys.sortBags", label = "Sort into bags",
        tooltip = "Everything on the Items page that belongs in a bag goes into it (the hotbar is never touched)." },
    { tab = "bags", type = "key", setting = "keys.takeOut", label = "Transfer",
        tooltip = "With the inventory open: the bag item under the mouse goes to the Items page, and an Items-page item under the mouse goes back into its bag." },
}

-- Pure: a dot path into a table.
function M.getPath(t, path)
    for part in path:gmatch("[^.]+") do
        if type(t) ~= "table" then return nil end
        t = t[part]
    end
    return t
end

function M.setPath(t, path, v)
    local parts = {}
    for part in path:gmatch("[^.]+") do parts[#parts + 1] = part end
    for i = 1, #parts - 1 do
        t[parts[i]] = t[parts[i]] or {}
        t = t[parts[i]]
    end
    t[parts[#parts]] = v
end

-- Pure: is `value` acceptable for `setting`? (keys must parse; the switch must be a boolean)
function M.valid(setting, value, parseKey)
    if setting == "pickupRouting" then return type(value) == "boolean" end
    if setting:match("^keys%.") then return type(value) == "string" and parseKey(value) ~= nil end
    return false
end

-- Change a setting: checked, saved, and live where it can be (keys rebind at once; routing on the next start).
-- Returns false and the reason when it's refused (the panel shows the reason).
function M.apply(ctx, setting, value)
    if not M.valid(setting, value, ctx.keys.parse) then
        ctx.log.warn("settings panel: %s = %s refused", tostring(setting), tostring(value))
        if setting:match("^keys%.") then return false, tostring(value) .. " isn't a key Storage Mage can use." end
        return false, "Storage Mage can't use that value."
    end
    M.setPath(ctx.settings, setting, value)
    local keyName = setting:match("^keys%.(.+)$")
    if keyName then ctx.keys.rebind(keyName, value) end
    ctx.saveSettings()
    ctx.log.info("settings panel: %s = %s", setting, tostring(value))
    return true
end

-- Pure: the rows with their defaults (a key row's RESET puts it back).
function M.rowsWithDefaults(defaults)
    local out = {}
    for i, r in ipairs(M.ROWS) do
        local c = {}
        for k, v in pairs(r) do c[k] = v end
        if r.setting then c.default = M.getPath(defaults, r.setting) end
        out[i] = c
    end
    return out
end

function M.start(ctx)
    local ok, err = pcall(function()
        require("settingspanel.main").start({ mod = "StorageMage", dir = ctx.dir })
        local client = require("settingspanel.client")
        client.register({
            mod = "StorageMage", title = "Storage Mage", order = 20,
            tabs = M.TABS, rows = M.rowsWithDefaults(require("storagemage.defaults")),
            get = function(setting) return M.getPath(ctx.settings, setting) end,
            apply = function(setting, value) return M.apply(ctx, setting, value) end,
            -- on a client joined to someone else's world, the server's own settings decide
            serverOwned = function() return ctx.objects.netRole() == "client" end,
        })
        M.client = client
    end)
    if not ok then ctx.log.warn("the shared Settings panel couldn't start: %s", tostring(err)) end
    return ok
end

return M
