-- Minimal file helpers. Directories ship with the mod (no os.execute: it flashes a console window).
local M = {}

function M.exists(path)
    local f = io.open(path, "rb")
    if f then f:close() return true end
    return false
end

function M.read(path)
    local f = io.open(path, "rb")
    if not f then return nil end
    local text = f:read("a")
    f:close()
    return text
end

-- Write via a temp file so a crash mid-write never leaves a half-written config.
function M.write(path, text)
    local tmp = path .. ".tmp"
    local f, err = io.open(tmp, "wb")
    if not f then return false, err end
    f:write(text)
    f:close()
    os.remove(path)
    local ok, rerr = os.rename(tmp, path)
    if not ok then return false, rerr end
    return true
end

return M
