-- Share: export the current layout to a text file and import someone else's.
--
--   Export -> Mods/FrameMage/share/<profile>.framemage.txt
--   Import <- Mods/FrameMage/share/<name>.framemage.txt (name from Mod Menu's "Import file", default "import")
--             replaces the current profile; the old one is kept as layouts/<profile>.before-import.lua
--
-- Shared files come from other people, so import is strict: it loads the file as data only (no code can run),
-- keeps only known fields, and checks every value's type and range. Anything else is dropped and reported.
local M = {}

local serialize = require("framemage.core.serialize")

local ctx, log

local LIMITS = { maxBytes = 1024 * 1024, maxElements = 5000, maxKey = 400, maxOffset = 10000,
    minScale = 0.05, maxScale = 10 }

local function finite(v) return type(v) == "number" and v == v and v ~= math.huge and v ~= -math.huge end

-- Pure: the shareable text for a profile. Unit-tested.
function M.encode(profileName, elements, when)
    local n = 0
    for _ in pairs(elements or {}) do n = n + 1 end
    local header = string.format(
        "-- Frame Mage layout: %s (%d elements), exported %s\n"
            .. "-- To use it: put this file in Mods/FrameMage/share/ and import it from Mod Menu (Frame Mage > Share).\n",
        profileName, n, when or "")
    return header .. serialize.dump({ framemage = "layout", format = 1, profile = profileName, elements = elements or {} })
end

-- Pure: validated layout data from shared text, or nil, reason. Also returns a list of dropped things.
function M.decode(text)
    if type(text) ~= "string" then return nil, "no file" end
    if #text > LIMITS.maxBytes then return nil, "file is too large to be a layout" end
    local data, err = serialize.parse(text, "shared layout")
    if not data then return nil, "not a readable layout file (" .. tostring(err) .. ")" end
    if data.framemage ~= "layout" then return nil, "not a Frame Mage layout file" end
    if data.format ~= 1 then return nil, "made by a newer Frame Mage (format " .. tostring(data.format) .. ")" end
    if type(data.elements) ~= "table" then return nil, "the file has no elements" end
    local out, dropped, n = {}, {}, 0
    for key, e in pairs(data.elements) do
        n = n + 1
        if n > LIMITS.maxElements then dropped[#dropped + 1] = "elements past " .. LIMITS.maxElements break end
        if type(key) ~= "string" or #key == 0 or #key > LIMITS.maxKey or type(e) ~= "table" then
            dropped[#dropped + 1] = "entry " .. tostring(key):sub(1, 40)
        else
            local c = {}
            for field, v in pairs(e) do
                local ok = false
                if (field == "x" or field == "y") and finite(v) and math.abs(v) <= LIMITS.maxOffset then ok = true
                elseif field == "scale" and finite(v) and v >= LIMITS.minScale and v <= LIMITS.maxScale then ok = true
                elseif field == "opacity" and finite(v) and v >= 0 and v <= 1 then ok = true
                elseif field == "hidden" and v == true then ok = true end
                if ok then c[field] = v else dropped[#dropped + 1] = key .. "." .. tostring(field) end
            end
            if next(c) then out[key] = c end
        end
    end
    return { profile = type(data.profile) == "string" and data.profile or "?", elements = out }, nil, dropped
end

-- Pure: the file name for an import name typed by a player ("my layout" -> "my layout.framemage.txt").
-- Path separators and ".." are refused so a name can't reach outside the share folder.
function M.importFileName(name)
    if type(name) ~= "string" then return nil end
    name = name:gsub("^%s+", ""):gsub("%s+$", "")
    if name == "" or name:find("[/\\:]") or name:find("%.%.") then return nil end
    if name:lower():match("%.txt$") then return name end
    return name .. ".framemage.txt"
end

local function shareDir() return ctx.dir .. "share/" end

local function flash(msg)
    log.info("%s", msg)
    local editor = ctx.features.editor
    if editor then editor.flash(msg) end
end

function M.export()
    local layout = ctx.features.layout
    if not layout then return end
    if layout.save then layout.save() end
    local name = ctx.settings.profile
    local path = shareDir() .. name .. ".framemage.txt"
    local ok, err = ctx.fs.write(path, M.encode(name, layout.profileData().elements, os.date("%Y-%m-%d %H:%M")))
    if ok then flash("Layout exported: share/" .. name .. ".framemage.txt")
    else log.error("export failed: %s", tostring(err)); flash("Layout export failed (see UE4SS.log)") end
end

function M.import(name)
    local layout = ctx.features.layout
    if not layout then return end
    local file = M.importFileName(name or ctx.settings.share.importFile)
    if not file then flash("Import: type a file name (no folders) in Mod Menu first") return end
    local text = ctx.fs.read(shareDir() .. file)
    if not text then flash("Import: share/" .. file .. " not found") return end
    local data, err, dropped = M.decode(text)
    if not data then flash("Import failed: " .. err) return end
    for _, d in ipairs(dropped or {}) do log.warn("import %s: dropped %s", file, d) end
    layout.replaceProfile(data)
    local n = 0
    for _ in pairs(data.elements) do n = n + 1 end
    flash(string.format("Imported '%s' into layout '%s' (%d elements%s)", data.profile, ctx.settings.profile, n,
        (dropped and #dropped > 0) and (", " .. #dropped .. " invalid values dropped") or ""))
end

function M.init(c)
    ctx, log = c, c.log
end

return M
