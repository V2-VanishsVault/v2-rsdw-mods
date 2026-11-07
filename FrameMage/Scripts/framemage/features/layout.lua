-- Layout: per-element offset, scale, opacity and hiding, stored per profile.
--
-- Uses the widget's render transform, which is applied after layout: moving an element never
-- reflows its neighbours, and it works for any widget regardless of its slot/panel type.
-- Profile file: layouts/<profile>.lua  ->  return { elements = { [key] = { x=, y=, scale=, opacity=, hidden= } } }
local M = {}

local ctx, W, log
local profile -- { elements = {...} }
local live = {} -- fullName -> { w = widget, key = key }
local original = {} -- fullName -> original render opacity
local ownerPrefixes = {} -- "WBP_HUD" -> true when any key nests under it
local dirtyAt -- os.clock() of last unsaved change

local function profilePath(name)
    return ctx.dir .. "layouts/" .. name .. ".lua"
end

local function rebuildPrefixes()
    ownerPrefixes = {}
    for key in pairs(profile.elements) do
        local prefix = key
        while true do
            prefix = prefix:match("^(.*)/[^/]+$")
            if not prefix then break end
            ownerPrefixes[prefix] = true
        end
    end
end

function M.entry(key) return profile.elements[key] end
function M.profileName() return ctx.settings.profile end

-- Only what the user changed is enforced: an element that was only moved keeps the game's own opacity
-- (fades, flashes), and one that was only faded keeps the game's own slide animations.

-- Pure: what applyTo sets for an entry (nil = leave that property to the game). Unit-tested.
function M.resolve(entry)
    entry = entry or {}
    local t = {}
    if entry.x or entry.y then t.translate = { entry.x or 0, entry.y or 0 } end
    if entry.scale then t.scale = entry.scale end
    if entry.hidden then t.opacity = 0
    elseif entry.opacity then t.opacity = math.max(0, math.min(1, entry.opacity)) end
    return t
end

-- Pure: which properties go back to the game's values when an entry changes from `before` to `after`.
function M.released(before, after)
    local b, a = M.resolve(before), M.resolve(after)
    return { translate = b.translate ~= nil and a.translate == nil, scale = b.scale ~= nil and a.scale == nil,
        opacity = b.opacity ~= nil and a.opacity == nil }
end

local function captureOpacity(w, full)
    if original[full] == nil then
        local ok, v = pcall(function() return w:GetRenderOpacity() end)
        original[full] = (ok and type(v) == "number") and v or 1
    end
end

function M.applyTo(w, entry)
    local t = M.resolve(entry)
    if t.translate then w:SetRenderTranslation({ X = t.translate[1], Y = t.translate[2] }) end
    if t.scale then w:SetRenderScale({ X = t.scale, Y = t.scale }) end
    if t.opacity then
        captureOpacity(w, W.fullName(w)) -- before our first write, so a reset can give it back
        w:SetRenderOpacity(t.opacity)
    end
end

-- Hand properties back to the game (once, when the user removes a change).
function M.release(w, before, after)
    local r = M.released(before, after)
    if r.translate then w:SetRenderTranslation({ X = 0, Y = 0 }) end
    if r.scale then w:SetRenderScale({ X = 1, Y = 1 }) end
    if r.opacity then
        local full = W.fullName(w)
        w:SetRenderOpacity(original[full] or 1)
        original[full] = nil
    end
end

local function track(w, key)
    local full = W.fullName(w)
    live[full] = { w = w, key = key }
    M.applyTo(w, profile.elements[key])
end

-- A user widget appeared: apply its own entry, and look inside it for nested entries.
local function onUserWidget(uw)
    if not ctx.enabled then return end
    if next(profile.elements) == nil then return end -- nothing edited: skip the key work entirely
    local key = W.key(uw)
    if profile.elements[key] then track(uw, key) end
    if ownerPrefixes[key] then
        W.walk(uw, function(child, depth)
            if depth == 0 then return true end
            if W.isUserWidget(child) then return false end -- nested user widgets get their own event
            local k = W.key(child)
            if profile.elements[k] then track(child, k) end
            return true
        end)
    end
end

-- Editor API -----------------------------------------------------------------

function M.edit(w, mutate)
    local key = W.key(w)
    local before = ctx.config.deepCopy(profile.elements[key] or {})
    local e = ctx.config.deepCopy(before)
    mutate(e)
    -- drop no-op values so moved-and-moved-back elements don't leave entries behind
    if e.x and math.abs(e.x) < 1e-3 then e.x = nil end
    if e.y and math.abs(e.y) < 1e-3 then e.y = nil end
    if next(e) == nil then e = nil end
    profile.elements[key] = e
    rebuildPrefixes()
    local full = W.fullName(w)
    M.release(w, before, e)
    if e then track(w, key) else live[full] = nil end
    -- other live instances that share the key (list entries) follow
    for f, rec in pairs(live) do
        if f ~= full and rec.key == key and W.valid(rec.w) then
            M.release(rec.w, before, e)
            M.applyTo(rec.w, e)
        end
    end
    dirtyAt = os.clock()
    ctx.events.emit("layoutchanged", key)
    return key, e
end

function M.save()
    ctx.config.save(profilePath(ctx.settings.profile), profile)
    dirtyAt = nil
end

function M.loadProfile(name)
    -- restore everything to the game's own values before switching
    for full, rec in pairs(live) do
        if W.valid(rec.w) then pcall(M.release, rec.w, profile.elements[rec.key], nil) end
        live[full] = nil
    end
    ctx.settings.profile = name
    profile = ctx.config.load(profilePath(name), { elements = {} })
    profile.elements = profile.elements or {}
    rebuildPrefixes()
    ctx.saveSettings()
    log.info("layout profile '%s' (%d elements)", name, (function() local n = 0 for _ in pairs(profile.elements) do n = n + 1 end return n end)())
    ctx.events.emit("profilechanged", name)
end

local function releaseAll()
    for full, rec in pairs(live) do
        if W.valid(rec.w) then pcall(M.release, rec.w, profile.elements[rec.key], nil) end
        live[full] = nil
    end
end

-- Master switch: off hands every edited widget back to the game; on finds and re-applies them.
function M.setEnabled(on)
    if on then W.rescan() else releaseAll() end
end

-- Switch to a named profile (Mod Menu's profile choice).
function M.selectProfile(name)
    if name == ctx.settings.profile then return end
    if dirtyAt then M.save() end
    M.loadProfile(name)
    if ctx.enabled then W.rescan() end
end

-- The current profile's data (for export) and replacing it (import). Replace keeps a backup file.
function M.profileData() return ctx.config.deepCopy(profile) end
function M.replaceProfile(data)
    local name = ctx.settings.profile
    ctx.config.save(ctx.dir .. "layouts/" .. name .. ".before-import.lua", profile)
    releaseAll()
    profile = { elements = ctx.config.deepCopy(data.elements or {}) }
    rebuildPrefixes()
    M.save()
    if ctx.enabled then W.rescan() end
    ctx.events.emit("profilechanged", name)
end

function M.nextProfile()
    if dirtyAt then M.save() end
    local list, cur = ctx.settings.profiles, ctx.settings.profile
    local idx = 1
    for i, n in ipairs(list) do if n == cur then idx = i end end
    M.loadProfile(list[(idx % #list) + 1])
    W.rescan()
    local editor = ctx.features.editor
    if editor then editor.flash("Frame Mage layout: " .. ctx.settings.profile) end
end

-- Feature entry --------------------------------------------------------------

function M.init(c)
    ctx, W, log = c, c.widgets, c.log
    M.loadProfile(ctx.settings.profile)

    ctx.events.on("userwidget", onUserWidget)
    -- a level change frees most widgets: forget handles, re-find them as they are recreated
    ctx.events.on("worldchanged", function()
        live, original = {}, {}
        M.skipFull = nil
    end)

    -- Re-assert transforms: UMG animations may write render opacity/transform every frame.
    ctx.sched.every(ctx.settings.layout.reapplyMs, "layout.reapply", function()
        if not ctx.enabled then return end
        for full, rec in pairs(live) do
            if W.valid(rec.w) then
                -- the editor owns the selected widget while it previews it
                if full ~= M.skipFull then M.applyTo(rec.w, profile.elements[rec.key]) end
            else
                live[full] = nil
                original[full] = nil
            end
        end
        if dirtyAt and os.clock() - dirtyAt > 1.0 then M.save() end
    end)

    ctx.keys.bind(ctx.settings.keys.nextProfile, "nextProfile", M.nextProfile, nil,
        { when = function() return ctx.enabled end })
end

return M
