-- Game-thread scheduling. Every callback runs on the game thread and inside pcall:
-- Lua running on UE4SS's own thread at the same time as the game thread can crash the game.
local log = require("storagemage.core.log")

local M = {}

function M.available()
    return LoopInGameThreadWithDelay ~= nil and ExecuteInGameThreadWithDelay ~= nil
        and ExecuteInGameThread ~= nil and NotifyOnNewObject ~= nil
end

local failed = {}
function M.safe(name, fn)
    return function(...)
        local ok, err = pcall(fn, ...)
        if not ok and not failed[name] then
            failed[name] = true -- log once per callback name, not every tick
            log.error("%s failed: %s", name, tostring(err))
        end
    end
end

function M.every(ms, name, fn)
    LoopInGameThreadWithDelay(ms, M.safe(name, fn))
end

function M.later(ms, name, fn)
    ExecuteInGameThreadWithDelay(ms, M.safe(name, fn))
end

function M.now(name, fn)
    ExecuteInGameThread(M.safe(name, fn))
end

return M
