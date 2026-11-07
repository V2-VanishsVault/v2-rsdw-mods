-- Tiny pub/sub so features can react to each other without hard dependencies.
-- Events in use:
--   started(ctx)                      widget tracking is live
--   userwidget(w)                     a new transient UserWidget is ready (one tick after creation)
--   worldchanged()                    level/pawn change: drop every stored widget handle
--   layoutchanged(key)                an element's layout entry changed
--   profilechanged(name)
local log = require("forgeframe.core.log")

local M = {}
local handlers = {}

function M.on(name, fn)
    handlers[name] = handlers[name] or {}
    table.insert(handlers[name], fn)
end

function M.emit(name, ...)
    local list = handlers[name]
    if not list then return end
    for _, fn in ipairs(list) do
        local ok, err = pcall(fn, ...)
        if not ok then log.error("event '%s' handler failed: %s", name, tostring(err)) end
    end
end

return M
