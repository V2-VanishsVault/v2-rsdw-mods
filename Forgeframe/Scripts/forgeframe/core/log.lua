-- Logging to UE4SS.log with a [Forgeframe] prefix and levels.
local M = {}

local LEVELS = { debug = 1, info = 2, warn = 3, error = 4 }
local current = LEVELS.info

function M.setLevel(name)
    current = LEVELS[name or "info"] or LEVELS.info
end

local function emit(level, fmt, ...)
    if LEVELS[level] < current then return end
    local ok, msg = pcall(string.format, fmt, ...)
    if not ok then msg = tostring(fmt) end
    print(string.format("[Forgeframe] %s: %s\n", level:upper(), msg))
end

function M.debug(fmt, ...) emit("debug", fmt, ...) end
function M.info(fmt, ...) emit("info", fmt, ...) end
function M.warn(fmt, ...) emit("warn", fmt, ...) end
function M.error(fmt, ...) emit("error", fmt, ...) end

return M
