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

-- Pure: the transform a given entry produces (unit-tested).
function M.resolve(entry, originalOpacity)
    entry = entry or {}
    local base = originalOpacity or 1
    local opacity = entry.hidden and 0 or base * (entry.opacity or 1)
    return {
        x = entry.x or 0,
        y = entry.y or 0,
        scale = entry.scale or 1,
        opacity = math.max(0, math.min(1, opacity)),
    }
end

local function originalOpacity(w, full)
    if original[full] == nil then
        local ok, v = pcall(function() return w:GetRenderOpacity() end)
        original[full] = (ok and type(v) == "number") and v or 1
    end
    return original[full]
end

-- Apply `entry` (or identity when nil) to one widget. opacityMul lets the editor blink the selection.
function M.applyTo(w, entry, opacityMul)
    local full = W.fullName(w)
    local t = M.resolve(entry, originalOpacity(w, full))
    w:SetRenderTranslation({ X = t.x, Y = t.y })
    w:SetRenderScale({ X = t.scale, Y = t.scale })
    w:SetRenderOpacity(t.opacity * (opacityMul or 1))
end

local function track(w, key)
    local full = W.fullName(w)
    live[full] = { w = w, key = key }
    M.applyTo(w, profile.elements[key])
end

-- A user widget appeared: apply its own entry, and look inside it for nested entries.
local function onUserWidget(uw)
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
    local e = profile.elements[key] or {}
    mutate(e)
    -- drop no-op values so moved-and-moved-back elements don't leave entries behind
    if e.x and math.abs(e.x) < 1e-3 then e.x = nil end
    if e.y and math.abs(e.y) < 1e-3 then e.y = nil end
    if next(e) == nil then e = nil end
    profile.elements[key] = e
    rebuildPrefixes()
    if e then track(w, key) else M.applyTo(w, nil); live[W.fullName(w)] = nil end
    -- other live instances that share the key (list entries) follow
    for _, rec in pairs(live) do
        if rec.key == key and W.valid(rec.w) then M.applyTo(rec.w, e) end
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
        if W.valid(rec.w) then pcall(M.applyTo, rec.w, nil) end
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

function M.nextProfile()
    if dirtyAt then M.save() end
    local list, cur = ctx.settings.profiles, ctx.settings.profile
    local idx = 1
    for i, n in ipairs(list) do if n == cur then idx = i end end
    M.loadProfile(list[(idx % #list) + 1])
    W.rescan()
    local editor = ctx.features.editor
    if editor then editor.flash("Forgeframe layout: " .. ctx.settings.profile) end
end

-- Feature entry --------------------------------------------------------------

function M.init(c)
    ctx, W, log = c, c.widgets, c.log
    M.loadProfile(ctx.settings.profile)

    ctx.events.on("userwidget", onUserWidget)
    -- a level change frees most widgets: forget handles, re-find them as they are recreated
    ctx.events.on("worldchanged", function()
        live, original = {}, {}
        M.blinkFull = nil
    end)

    -- Re-assert transforms: UMG animations may write render opacity/transform every frame.
    ctx.sched.every(ctx.settings.layout.reapplyMs, "layout.reapply", function()
        for full, rec in pairs(live) do
            if W.valid(rec.w) then
                -- the editor owns the selected widget's opacity while it blinks
                if full ~= M.blinkFull then M.applyTo(rec.w, profile.elements[rec.key]) end
            else
                live[full] = nil
                original[full] = nil
            end
        end
        if dirtyAt and os.clock() - dirtyAt > 1.0 then M.save() end
    end)

    ctx.keys.bind(ctx.settings.keys.nextProfile, "nextProfile", M.nextProfile)
end

return M
