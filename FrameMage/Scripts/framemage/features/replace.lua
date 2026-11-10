-- Replace: swap one of the game's UI widgets for Frame Mage's own.
--
-- A replacement names a game widget class and a handler. When the game shows that widget, the handler reads what
-- it was going to display, Frame Mage shows its own version, and the game's widget is kept invisible for as long as
-- it lives. The game's widget is hidden, never removed: its owner (e.g. the notification queue) still drives its
-- timing, sound and clean-up exactly as before, so nothing downstream notices.
--
-- Showing is detected two ways, because the game may create a fresh widget per notification or reuse one:
-- a new instance (userwidget event) and, for instances already seen, a change of their NotificationData.
-- Handles to the few watched widgets are dropped on every world change (see core/widgets.lua on stale handles).
--
-- Replacements now: level-up popup -> features/celebrate.lua. Add more in REPLACEMENTS below.
local M = {}

local ctx, W, log
local watched = {} -- fullName -> { w, spec, lastData, hiding }
local firstSeen = {} -- class -> true once its structure has been written to the log

-- Pure: the level-up info from values read off the game's data (unit-tested).
--   level: NotificationSkillUpData.Level; skill: SkillData.Name; maxLevel: SkillData.MaxLevel
--   levelText: fallback, the popup's LevelTextBlock text
function M.levelInfo(level, skill, maxLevel, levelText)
    local lv = tonumber(level)
    if not lv and type(levelText) == "string" then lv = tonumber(levelText:match("(%d+)")) end
    if not lv then return nil end
    return { level = math.floor(lv), skill = (skill ~= "" and skill) or nil, maxLevel = tonumber(maxLevel) }
end

local function read(fn)
    local ok, v = pcall(fn)
    if ok then return v end
    return nil
end

-- Level-up popup (WBP_LevelUpNotification_C : LevelUpNotificationItem : NotificationItem).
-- NotificationData is a NotificationSkillUpData { Skill = SkillData, Level = int }; SkillData has Name (Text),
-- MaxLevel (int). The popup's SkillIconImage already shows the skill's icon, which the celebration reuses.
local function levelUp(w, data)
    local skill = read(function() return data.Skill end)
    local info = M.levelInfo(
        read(function() return data.Level end),
        W.valid(skill) and read(function() return skill.Name:ToString() end) or nil,
        W.valid(skill) and read(function() return skill.MaxLevel end) or nil,
        read(function() return w.LevelTextBlock:GetText():ToString() end))
    if not info then return false end
    info.icon = read(function()
        local res = w.SkillIconImage.Brush.ResourceObject
        if W.valid(res) and W.className(res) == "Texture2D" then return res end
        return nil
    end)
    local celebrate = ctx.features.celebrate
    if not celebrate then return false end
    celebrate.play(info)
    log.info("level-up: %s %d", info.skill or "?", info.level)
    return true
end

M.REPLACEMENTS = {
    { class = "WBP_LevelUpNotification_C", setting = "levelUp", handler = levelUp,
        -- a reused popup may get the same data object with a new level: the level is part of "new"
        signature = function(data) return tostring(read(function() return data.Level end)) end },
}

-- First time a replaced widget shows, write its structure to the log (names, classes, visibility, data fields),
-- so the replacement can be checked against the real thing.
local function logStructure(w, data, spec)
    if firstSeen[spec.class] then return end
    firstSeen[spec.class] = true
    local lines = { "replace: first " .. spec.class .. " seen; structure:" }
    W.walk(w, function(child, depth)
        local vis = read(function() return child:GetVisibility() end)
        lines[#lines + 1] = string.format("  %s%s [%s] vis=%s", string.rep("  ", depth), W.name(child), W.className(child), tostring(vis))
        return depth < 6
    end)
    lines[#lines + 1] = "  data: " .. tostring(read(function() return W.className(data) end))
    for _, f in ipairs({ "Level", "Tag" }) do
        lines[#lines + 1] = string.format("    %s = %s", f, tostring(read(function() return data[f] end)))
    end
    local skill = read(function() return data.Skill end)
    if W.valid(skill) then
        lines[#lines + 1] = string.format("    Skill = %s (%s) Name=%s MaxLevel=%s", W.name(skill), W.className(skill),
            tostring(read(function() return skill.Name:ToString() end)), tostring(read(function() return skill.MaxLevel end)))
    end
    for _, l in ipairs(lines) do log.info("%s", l) end
end

local function hide(rec)
    -- Hidden keeps its layout space and lets its animations, sound and timers run; it just isn't drawn
    pcall(function() if rec.w:GetVisibility() ~= 2 then rec.w:SetVisibility(2) end end)
end

local function unhide(rec)
    pcall(function() rec.w:SetVisibility(4) end) -- SelfHitTestInvisible, as notifications normally are
    rec.hiding = false
end

local function on(spec)
    return ctx.enabled and ctx.settings.replace[spec.setting] ~= false
end

local function check(rec)
    local data = read(function() return rec.w.NotificationData end)
    if not W.valid(data) then return end
    local full = W.fullName(data)
    if rec.spec.signature then full = full .. "#" .. tostring(rec.spec.signature(data)) end
    if full == rec.lastData then return end
    rec.lastData = full
    if not on(rec.spec) then return end
    pcall(logStructure, rec.w, data, rec.spec)
    local ok, handled = pcall(rec.spec.handler, rec.w, data)
    if ok and handled then
        rec.hiding = true
        hide(rec)
    elseif not ok then
        log.warn("replace %s failed: %s (the game's own widget is shown)", rec.spec.class, tostring(handled))
    end
end

local byClass = {}

function M.init(c)
    ctx, W, log = c, c.widgets, c.log
    for _, spec in ipairs(M.REPLACEMENTS) do byClass[spec.class] = spec end

    c.events.on("userwidget", function(w)
        local ok, cls = pcall(W.className, w)
        local spec = ok and byClass[cls]
        if not spec then return end
        local full = W.fullName(w)
        if not watched[full] then
            watched[full] = { w = w, spec = spec }
            check(watched[full])
        end
    end)
    c.events.on("worldchanged", function() watched = {} end)

    -- every frame: keep replaced widgets hidden (their own animations may show them) and notice new data
    c.sched.every(16, "replace.watch", function()
        for full, rec in pairs(watched) do
            if not W.valid(rec.w) then
                watched[full] = nil
            else
                check(rec)
                if rec.hiding then
                    if on(rec.spec) then hide(rec) else unhide(rec) end
                end
            end
        end
    end)
end

return M
