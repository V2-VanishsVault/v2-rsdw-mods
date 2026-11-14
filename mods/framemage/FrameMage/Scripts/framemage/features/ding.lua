-- Ding: the classic "DING!" when you level up, played as the celebration's number lands.
--
-- Frame Mage's own sound, synthesized live (no audio file can be loaded at runtime the way PNGs can): Unreal's
-- Modular Synth (Synthesis plugin, shipped with the game) is attached to the player controller and played like a
-- keyboard. A struck bell = a sharp attack, a long exponential ring-out, and an inharmonic overtone at ~2.76x the
-- fundamental (that ratio is what makes it a bell, not a beep), plus a little stereo delay for shimmer.
--
-- settings.ding.asset: optionally play a sound asset instead (a game sound, or your own cooked into a pak), by its
-- object path, e.g. "/Game/Audio/.../MSS_X.MSS_X". The game's own level-up sting still plays either way.
local M = {}

local ctx, W, log, D
local synth -- the ModularSynthComponent (dropped on world change: it dies with the player controller)

-- Pure (unit-tested) -------------------------------------------------------------------------------------

-- A frequency ratio as semitones + cents (what the synth's oscillator tuning takes).
function M.ratioToSemitones(ratio)
    local total = 12 * math.log(ratio, 2)
    local semis = math.floor(total)
    return semis, (total - semis) * 100
end

-- Linear volume 0..1 -> decibels (the synth's gain), with a floor for silence.
function M.volumeToDb(v)
    if v <= 0.001 then return -60 end
    return 20 * math.log(v, 10)
end

-- MIDI note -> frequency, for the log line.
function M.noteToHz(note) return 440 * 2 ^ ((note - 69) / 12) end

-- Runtime --------------------------------------------------------------------------------------------------

local function call(obj, fn, ...)
    local args = table.pack(...)
    local ok, err = pcall(function() return obj[fn](obj, table.unpack(args, 1, args.n)) end)
    if not ok then log.debug("ding: %s failed: %s", fn, tostring(err)) end
    return ok
end

local function playerController()
    local ok, pc = pcall(function()
        local gs = StaticFindObject("/Script/Engine.Default__GameplayStatics")
        return gs:GetPlayerController(FindFirstOf("GameInstance"), 0)
    end)
    if ok and W.valid(pc) then return pc end
    return nil
end

local function makeSynth()
    local pc = playerController()
    if not pc then return nil end
    local cls = StaticFindObject("/Script/Synthesis.ModularSynthComponent")
    if not W.valid(cls) then log.warn("ding: the game has no Modular Synth; set ding.asset to use a sound asset") return nil end
    local identity = { Rotation = { X = 0, Y = 0, Z = 0, W = 1 }, Translation = { X = 0, Y = 0, Z = 0 },
        Scale3D = { X = 1, Y = 1, Z = 1 } }
    local ok, comp = pcall(function() return pc:AddComponentByClass(cls, false, identity, false) end)
    if not (ok and W.valid(comp)) then log.warn("ding: could not create the synth (%s)", tostring(comp)) return nil end
    -- a UI sound: not placed in the world, not affected by game pause or distance
    pcall(function() comp.bAllowSpatialization = false end)
    pcall(function() comp.bIsUISound = true end)
    local semis, cents = M.ratioToSemitones(D.overtoneRatio)
    call(comp, "SetEnablePolyphony", true)
    call(comp, "SetOscType", 0, 0) -- sine
    call(comp, "SetOscType", 1, 0) -- sine
    call(comp, "SetOscGain", 0, 1.0)
    call(comp, "SetOscGain", 1, D.overtoneGain)
    call(comp, "SetOscSemitones", 1, semis)
    call(comp, "SetOscCents", 1, cents)
    call(comp, "SetAttackTime", D.attackMs)
    call(comp, "SetDecayTime", D.decayMs)
    call(comp, "SetSustainGain", 0.0)
    call(comp, "SetReleaseTime", D.releaseMs)
    call(comp, "SetFilterFrequency", 12000)
    call(comp, "SetStereoDelayIsEnabled", D.shimmer)
    call(comp, "SetStereoDelayTime", 110)
    call(comp, "SetStereoDelayFeedback", 0.25)
    call(comp, "SetStereoDelayWetlevel", 0.22)
    call(comp, "SetGainDb", M.volumeToDb(D.volume))
    call(comp, "Start")
    log.info("ding: synth ready (%.0f Hz bell, overtone x%.2f)", M.noteToHz(D.note), D.overtoneRatio)
    return comp
end

local function playAsset(path)
    local snd = StaticFindObject(path)
    if not W.valid(snd) and LoadAsset then pcall(function() snd = LoadAsset(path) end) end
    if not W.valid(snd) then log.warn("ding: sound asset %s not found", path) return false end
    local gs = StaticFindObject("/Script/Engine.Default__GameplayStatics")
    return pcall(function() gs:PlaySound2D(FindFirstOf("GameInstance"), snd, D.volume, 1.0, 0.0, nil, nil, true) end)
end

function M.play()
    if not (ctx.enabled and D.enabled) then return end
    if D.asset and D.asset ~= "" then
        if playAsset(D.asset) then return end
    end
    if not (synth and W.valid(synth)) then synth = makeSynth() end
    if not synth then return end
    call(synth, "SetGainDb", M.volumeToDb(D.volume))
    call(synth, "NoteOn", D.note, 110, D.holdSeconds)
end

-- the Settings panel's volume slider
function M.setVolume(v) D.volume = v end

function M.init(c)
    ctx, W, log, D = c, c.widgets, c.log, c.settings.ding
    c.events.on("worldchanged", function() synth = nil end)
end

return M
