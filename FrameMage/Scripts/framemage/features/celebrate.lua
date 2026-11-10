-- Celebrate: Frame Mage's level-up moment, shown instead of the game's level-up popup (see features/replace.lua).
--
--   fireworks  bursts of sparks that fly out, fall under gravity and fade, tinted per burst
--   number     the new level zooms in from large, lands with a slight overshoot, on a soft golden glow
--   text       the skill's name above, "Level up!" (or "Max level!") below, the game's own skill icon on top
-- Everything is a runtime overlay (no game assets changed); art is Frame Mage's own (Art/_ui/fm_spark.png,
-- fm_glow.png from tools/make_icons.py). Several level-ups in a row play one after another.
-- The game's level-up sound still plays: only the popup's visuals are replaced. A "DING!" (features/ding.lua) plays
-- on top as the number lands.
local overlay = require("framemage.core.overlay")
local W = require("framemage.core.widgets")

local M = {}

-- Pure parts (unit-tested) ---------------------------------------------------------------------------

-- Small deterministic RNG (so a preview looks the same each time, and tests can check positions).
function M.rng(seed)
    local s = (seed or 1) % 2147483647
    if s <= 0 then s = s + 2147483646 end
    return function(a, b)
        s = (s * 16807) % 2147483647
        local u = (s - 1) / 2147483646
        if a then return a + (b - a) * u end
        return u
    end
end

-- "Back" ease-out: one small overshoot (about 6%), then settles at 1. (An elastic ease overshoots ~35%, which on
-- a 3x zoom shrank the number to a quarter of its size before it bounced back.)
function M.easeOutBack(t, c1)
    t = math.max(0, math.min(1, t))
    c1 = c1 or 1.2
    local c3 = c1 + 1
    return 1 + c3 * (t - 1) ^ 3 + c1 * (t - 1) ^ 2
end

function M.easeOutCubic(t)
    t = math.max(0, math.min(1, t))
    return 1 - (1 - t) ^ 3
end

-- Bursts and their particles. Returns a list of particles:
--   { burst = i, t0 = start time, life, x0, y0, vx, vy, color = {r,g,b} }  (positions relative to center)
function M.plan(o, random)
    local parts = {}
    for b = 1, o.bursts do
        local t0 = o.burstTimes[b] or (0.15 + (b - 1) * 0.3)
        local side = (b % 2 == 0) and 1 or -1
        local bx = side * random(o.spreadMinX, o.spreadMaxX)
        local by = -random(o.spreadMinY, o.spreadMaxY)
        if b == 1 then bx, by = 0, -o.spreadMaxY * 0.6 end -- the first burst crowns the number
        local color = o.palette[(b - 1) % #o.palette + 1]
        for _ = 1, o.perBurst do
            local ang = random(0, 2 * math.pi)
            local speed = random(o.speedMin, o.speedMax)
            parts[#parts + 1] = { burst = b, t0 = t0, life = random(o.lifeMin, o.lifeMax), x0 = bx, y0 = by,
                vx = math.cos(ang) * speed, vy = math.sin(ang) * speed, color = color }
        end
    end
    return parts
end

-- Burst flash: bright at the moment a burst goes off, gone after `dur` seconds (0..1).
function M.flashAt(t, t0, dur)
    local a = t - t0
    if a < 0 or a > dur then return 0 end
    return (1 - a / dur) ^ 2
end

-- Where a particle is at time t, and how visible (0..1). Drag slows it; gravity pulls it down.
function M.particleAt(p, t, gravity, drag)
    local a = t - p.t0
    if a < 0 or a > p.life then return nil end
    -- closed form of v' = -drag*v (+ gravity on y)
    local k = (1 - math.exp(-drag * a)) / drag
    local x = p.x0 + p.vx * k
    local y = p.y0 + p.vy * k + gravity * (a - k) / drag
    local fade = (1 - a / p.life) ^ 1.5
    return x, y, fade
end

-- Timeline: 0..intro the number zooms; hold; outro fades everything. Returns per-element values at time t.
function M.timeline(t, o)
    local out = {}
    local zoom = M.easeOutBack(t / o.zoomTime)
    out.numberScale = o.zoomFrom + (1 - o.zoomFrom) * zoom
    out.numberOpacity = M.easeOutCubic(t / 0.2)
    out.textOpacity = M.easeOutCubic((t - 0.35) / 0.3)
    out.textLift = (1 - M.easeOutCubic((t - 0.35) / 0.4)) * 14
    out.glowOpacity = M.easeOutCubic(t / 0.35) * (0.75 + 0.25 * math.sin(t * 5))
    out.glowScale = 0.6 + 0.4 * M.easeOutCubic(t / 0.5)
    local fadeOut = 1 - M.easeOutCubic((t - (o.duration - o.outro)) / o.outro)
    if t < o.duration - o.outro then fadeOut = 1 end
    out.all = math.max(0, fadeOut)
    out.rise = (1 - out.all) * 24
    out.done = t >= o.duration
    return out
end

-- The celebration's colors in the active theme (its `celebrate` table), each missing one Demi-human's gold.
-- Colors are { r, g, b }. Pure. Unit-tested.
M.GOLD = {
    number = { 1, 0.82, 0.36 }, outline = { 0.22, 0.1, 0.02 }, glow = { 1, 0.72, 0.28 },
    title = { 0.98, 0.92, 0.76 }, label = { 1, 0.9, 0.66 },
}
function M.colors(themed, palette)
    local out = {}
    for k, v in pairs(M.GOLD) do out[k] = (themed and themed[k]) or v end
    out.sparks = (themed and themed.sparks) or palette
    return out
end

-- Runtime -------------------------------------------------------------------------------------------------

local ctx, log, C
local ui -- built overlay
local queue, playing = {}, nil

-- The game's font on a text block at `size`, with an outline `outline` thick in `rgb` (none if the font won't).
function M.setFont(t, font, size, outline, rgb)
    if not font then return end
    local f = { FontObject = font.FontObject, TypefaceFontName = font.TypefaceFontName, Size = size }
    if outline then
        f.OutlineSettings = { OutlineSize = outline, OutlineColor = { R = rgb[1], G = rgb[2], B = rgb[3], A = 1 } }
    end
    if not pcall(function() t:SetFont(f) end) then
        f.OutlineSettings = nil
        pcall(function() t:SetFont(f) end)
    end
end

local function build()
    local h = overlay.host("Celebrate", 19000)
    local art = ctx.features.art
    local function tex(file) return art and art.loadFile(ctx.dir .. "Art/_ui/" .. file, h.uw) end
    local n = 0
    local function new(cls)
        n = n + 1
        return overlay.new(cls, h.tree, "FM_Cel_" .. cls .. "_" .. h.suffix .. "_" .. n)
    end
    local function place(widget, x, y, w, hh, autosize)
        local s = h.canvas:AddChildToCanvas(widget)
        s:SetAnchors({ Minimum = { X = 0.5, Y = C.centerY }, Maximum = { X = 0.5, Y = C.centerY } })
        s:SetAlignment({ X = 0.5, Y = 0.5 })
        s:SetPosition({ X = x, Y = y })
        if autosize then s:SetAutoSize(true) else s:SetSize({ X = w, Y = hh }) end
        return s
    end
    local font = require("framemage.editor.legend").gameFont() -- the game's own font, so it looks native
    local function text(size, color, outline)
        local t = new("TextBlock")
        M.setFont(t, font, size, outline, M.GOLD.outline)
        t:SetColorAndOpacity({ SpecifiedColor = color, ColorUseRule = 0 })
        pcall(function() t:SetJustification(1) end) -- center
        pcall(function() t:SetShadowOffset({ X = 2, Y = 2 }) end)
        pcall(function() t:SetShadowColorAndOpacity({ R = 0, G = 0, B = 0, A = 0.6 }) end)
        return t
    end

    local glow = new("Image")
    local gt = tex("fm_glow.png")
    if gt then glow:SetBrushFromTexture(gt, false) end
    glow:SetColorAndOpacity({ R = 1, G = 0.72, B = 0.28, A = 1 })
    place(glow, 0, 0, C.glowSize, C.glowSize)

    -- sparks (a fixed pool, reused by every celebration)
    local st = tex("fm_spark.png")
    local sparks = {}
    for i = 1, C.bursts * C.perBurst do
        local img = new("Image")
        if st then img:SetBrushFromTexture(st, false) end
        img:SetRenderOpacity(0)
        place(img, 0, 0, C.sparkSize, C.sparkSize)
        sparks[i] = img
    end

    -- one flash per burst, under the sparks
    local flashes = {}
    for i = 1, C.bursts do
        local img = new("Image")
        if gt then img:SetBrushFromTexture(gt, false) end
        img:SetRenderOpacity(0)
        place(img, 0, 0, C.flashSize, C.flashSize)
        flashes[i] = img
    end

    local icon = new("Image")
    place(icon, 0, -C.numberSize * 1.45, C.iconSize, C.iconSize)
    local skill = text(C.titleSize, { R = 0.98, G = 0.92, B = 0.76, A = 1 })
    place(skill, 0, -C.numberSize * 0.95, 0, 0, true)
    local number = text(C.numberSize, { R = 1, G = 0.82, B = 0.36, A = 1 }, 4)
    place(number, 0, 0, 0, 0, true)
    pcall(function() number:SetRenderTransformPivot({ X = 0.5, Y = 0.5 }) end)
    local label = text(C.labelSize, { R = 1, G = 0.9, B = 0.66, A = 1 })
    place(label, 0, C.numberSize * 0.8, 0, 0, true)

    h.uw:SetVisibility(1)
    ui = { font = font, uw = h.uw, glow = glow, sparks = sparks, flashes = flashes, icon = icon, skill = skill, number = number, label = label }
end

local function setText(w, s) pcall(function() w:SetText(FText(s)) end) end

local function start(info)
    if not (ui and W.valid(ui.uw)) then
        local ok, err = pcall(build)
        if not ok then log.warn("celebration unavailable: %s", tostring(err)); ui = nil; return false end
    end
    setText(ui.number, tostring(info.level or "?"))
    setText(ui.skill, (info.skill or ""):upper())
    local maxed = info.maxLevel and info.level and info.level >= info.maxLevel
    setText(ui.label, maxed and "Max level!" or "Level up!")
    if info.icon and W.valid(info.icon) then
        pcall(function() ui.icon:SetBrushFromTexture(info.icon, false) end)
        pcall(function() ui.icon:SetVisibility(3) end)
    else
        pcall(function() ui.icon:SetVisibility(1) end)
    end
    -- the theme's colors: the number (fill and outline), the glow, the words, the sparks
    local col = M.colors(ctx.themes.style().celebrate, C.palette)
    local function rgb(c) return { R = c[1], G = c[2], B = c[3], A = 1 } end
    pcall(function() ui.number:SetColorAndOpacity({ SpecifiedColor = rgb(col.number), ColorUseRule = 0 }) end)
    M.setFont(ui.number, ui.font, C.numberSize, 4, col.outline)
    pcall(function() ui.skill:SetColorAndOpacity({ SpecifiedColor = rgb(col.title), ColorUseRule = 0 }) end)
    pcall(function() ui.label:SetColorAndOpacity({ SpecifiedColor = rgb(col.label), ColorUseRule = 0 }) end)
    pcall(function() ui.glow:SetColorAndOpacity(rgb(col.glow)) end)
    local plan = setmetatable({ palette = col.sparks }, { __index = C })
    local parts = M.plan(plan, M.rng(info.seed or os.time()))
    -- tint each spark once; only position and opacity change per frame
    for i, img in ipairs(ui.sparks) do
        local p = parts[i]
        if p then
            pcall(function() img:SetColorAndOpacity({ R = p.color[1], G = p.color[2], B = p.color[3], A = 1 }) end)
        end
    end
    -- place and tint each burst's flash at its burst center
    local bursts = {}
    for _, p in ipairs(parts) do bursts[p.burst] = bursts[p.burst] or p end
    for i, img in ipairs(ui.flashes) do
        local p = bursts[i]
        if p then
            pcall(function()
                img:SetRenderTranslation({ X = p.x0, Y = p.y0 })
                img:SetColorAndOpacity({ R = p.color[1], G = p.color[2], B = p.color[3], A = 1 })
            end)
        end
    end
    pcall(function() ui.uw:SetVisibility(3) end)
    playing = { t0 = os.clock(), parts = parts, bursts = bursts }
    -- DING! as the number lands (features/ding.lua)
    local ding = ctx.features.ding
    if ding then ctx.sched.later(math.floor(ctx.settings.ding.delay * 1000), "celebrate.ding", ding.play) end
    return true
end

local function frame()
    if not playing then
        if #queue > 0 then start(table.remove(queue, 1)) end
        return
    end
    if not (ui and W.valid(ui.uw)) then playing = nil return end
    local t = os.clock() - playing.t0
    local tl = M.timeline(t, C)
    pcall(function()
        ui.number:SetRenderScale({ X = tl.numberScale, Y = tl.numberScale })
        ui.number:SetRenderOpacity(tl.numberOpacity * tl.all)
        ui.number:SetRenderTranslation({ X = 0, Y = -tl.rise })
        ui.glow:SetRenderOpacity(tl.glowOpacity * tl.all)
        ui.glow:SetRenderScale({ X = tl.glowScale, Y = tl.glowScale })
        for _, w in ipairs({ ui.skill, ui.label, ui.icon }) do
            w:SetRenderOpacity(tl.textOpacity * tl.all)
            w:SetRenderTranslation({ X = 0, Y = tl.textLift - tl.rise })
        end
    end)
    for i, img in ipairs(ui.flashes) do
        local b = playing.bursts[i]
        local f = b and M.flashAt(t, b.t0, C.flashTime) or 0
        pcall(function() img:SetRenderOpacity(f * tl.all) end)
    end
    for i, img in ipairs(ui.sparks) do
        local p = playing.parts[i]
        local x, y, fade
        if p then x, y, fade = M.particleAt(p, t, C.gravity, C.drag) end
        pcall(function()
            if x then
                img:SetRenderTranslation({ X = x, Y = y })
                img:SetRenderOpacity(fade * tl.all)
            else
                img:SetRenderOpacity(0)
            end
        end)
    end
    if tl.done then
        pcall(function() ui.uw:SetVisibility(1) end)
        playing = nil
    end
end

-- Queue a celebration: { level, skill, maxLevel, icon (Texture2D or nil), seed }
function M.play(info)
    queue[#queue + 1] = info
    if #queue > 5 then table.remove(queue, 1) end -- never fall far behind
end

-- Developer preview (no level-up needed).
function M.preview()
    M.play({ level = math.random(2, 49), skill = "Woodcutting", maxLevel = 50, seed = 7 })
end

function M.init(c)
    ctx, log, C = c, c.log, c.settings.celebrate
    c.sched.every(C.frameMs, "celebrate.frame", frame)
    c.events.on("worldchanged", function() ui = nil; playing = nil end)
    c.keys.bind(c.settings.keys.previewCelebration, "previewCelebration", M.preview)
end

return M
