-- UObject helpers. Never keep a UObject across ticks: look it up again each time and check valid() first
-- (a stale handle crashes the game).
local M = {}

function M.valid(o)
    if o == nil then return false end
    local ok, v = pcall(function() return o:IsValid() end)
    return ok and v == true
end

function M.name(o) return o:GetFName():ToString() end
function M.className(o) return o:GetClass():GetFName():ToString() end

-- Reads o[field] without throwing; nil when it isn't there.
function M.get(o, field)
    local ok, v = pcall(function() return o[field] end)
    if ok then return v end
    return nil
end

-- The local player's controller (client / host), or nil (dedicated server, menus).
function M.localController()
    local ok, pc = pcall(function()
        local gs = StaticFindObject("/Script/Engine.Default__GameplayStatics")
        return gs:GetPlayerController(FindFirstOf("GameInstance"), 0)
    end)
    if ok and M.valid(pc) then return pc end
    return nil
end

-- Where this copy of the mod runs: "dedicated" (server without players), "host" (single-player / self-hosted:
-- server and client in one process), "client" (joined to someone else's server), or nil if no world yet.
-- Decided from the local player's controller: the server has authority over it, a remote client doesn't.
-- Seen "client" on a client joined to a dedicated server and "host" in a local world (both correct, 2026-11-08).
-- No local player but a game mode (server-only) means a dedicated server: not yet seen (needs UE4SS there).
-- Returns "unknown" when it can't tell; bag code must treat that as "don't change inventories". Design T19.
function M.netRole()
    local pc = M.localController()
    if pc then
        local ok, auth = pcall(function() return pc:HasAuthority() end)
        if not ok then return "unknown" end
        return auth and "host" or "client"
    end
    local ok, gm = pcall(function() return FindFirstOf("GameModeBase") end)
    if ok and M.valid(gm) then return "dedicated" end
    return "unknown"
end

return M
