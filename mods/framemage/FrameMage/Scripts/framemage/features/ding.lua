-- Ding: a short level-up fanfare, played as the celebration's number lands.
--
-- Frame Mage's own sound, synthesized live (no audio file can be loaded at runtime the way PNGs can): Unreal's
-- Modular Synth (Synthesis plugin, shipped with the game) is attached to the player controller and played like a
-- keyboard, one scheduled note at a time.
--
-- settings.ding.sound picks one of TUNES: five original fanfares of about a second, each played on one of
-- VOICES. (A single bell strike, tried first, wasn't exciting enough.)
--
-- settings.ding.asset: optionally play a sound asset instead (a game sound, or your own cooked into a pak), by its
-- object path, e.g. "/Game/Audio/.../MSS_X.MSS_X". The game's own level-up sting still plays either way.
local M = {}

local ctx, W, log, D
local synth -- the ModularSynthComponent (dropped on world change: it dies with the player controller)
local tuned -- the tune and voice the synth is set up for

-- How the synth sounds. osc: the two oscillators' wave (0 sine, 1 saw, 2 triangle, 3 square); overtone /
-- overtoneGain: the second oscillator's pitch ratio and level. attackMs, decayMs, sustain, releaseMs: the volume
-- envelope. hitMs: how fast the brightness at each note's start dies (the mod envelope closes a low-pass filter);
-- cutoff: where the filter settles, as a multiple of the tune's lowest note. gainDb: level trim (saws are loud).
M.VOICES = {
    -- a small bell: an inharmonic overtone (2.76x) loud at the strike and gone a tenth of a second later
    bell = { osc = { 0, 0 }, overtone = 2.76, overtoneGain = 0.6, attackMs = 0.5, decayMs = 900, sustain = 0,
        releaseMs = 300, hitMs = 80, cutoff = 1.8, gainDb = 0, shimmer = true },
    -- bright synth brass: two slightly detuned saws, a quick swell, the filter opening on each note
    brass = { osc = { 1, 1 }, overtone = 2 ^ (8 / 1200), overtoneGain = 0.8, attackMs = 20, decayMs = 500,
        sustain = 0.55, releaseMs = 220, hitMs = 260, cutoff = 2.5, gainDb = -9, shimmer = true },
}

-- The fanfares. notes: { start (s), MIDI note, held for (s), velocity 1..127 }, in order. 72 = C5, 84 = C6, 96 = C7.
M.TUNES = {
    -- three pickups and a big major chord
    triumph = { voice = "brass", notes = {
        { 0.00, 79, 0.09, 96 }, { 0.12, 79, 0.09, 96 }, { 0.24, 79, 0.09, 96 },
        { 0.36, 84, 0.55, 110 }, { 0.36, 88, 0.55, 92 }, { 0.36, 91, 0.55, 92 } } },
    -- a sparkling arpeggio up an octave, then the chord rings
    ascend = { voice = "bell", notes = {
        { 0.00, 84, 0.3, 100 }, { 0.08, 88, 0.3, 100 }, { 0.16, 91, 0.3, 100 }, { 0.24, 96, 0.3, 110 },
        { 0.40, 88, 0.9, 90 }, { 0.40, 91, 0.9, 90 }, { 0.40, 96, 0.9, 105 } } },
    -- up the D major chord, a breath, then the chord an octave up
    quest = { voice = "brass", notes = {
        { 0.00, 74, 0.10, 92 }, { 0.10, 78, 0.10, 92 }, { 0.20, 81, 0.10, 96 }, { 0.30, 86, 0.18, 104 },
        { 0.56, 81, 0.6, 88 }, { 0.56, 86, 0.6, 100 }, { 0.56, 90, 0.6, 92 } } },
    -- a quick glittering run, then a high G chord
    sparkle = { voice = "bell", notes = {
        { 0.00, 86, 0.25, 90 }, { 0.06, 91, 0.25, 92 }, { 0.12, 95, 0.25, 96 }, { 0.18, 98, 0.25, 100 },
        { 0.32, 91, 0.9, 88 }, { 0.32, 95, 0.9, 88 }, { 0.32, 98, 0.9, 100 } } },
    -- a wide leap up, then the flat-seven chord resolving home (the "victory" cadence)
    heroic = { voice = "brass", notes = {
        { 0.00, 72, 0.16, 96 }, { 0.18, 79, 0.12, 96 }, { 0.32, 84, 0.12, 100 },
        { 0.50, 82, 0.12, 96 }, { 0.50, 86, 0.12, 92 },
        { 0.66, 84, 0.6, 110 }, { 0.66, 88, 0.6, 94 }, { 0.66, 91, 0.6, 94 } } },
}
M.ORDER = { "triumph", "ascend", "quest", "sparkle", "heroic" }
M.LABELS = { triumph = "Triumph", ascend = "Ascend", quest = "Quest", sparkle = "Sparkle", heroic = "Heroic" }
M.DEFAULT = "triumph"

-- Pure: the tune to play for a setting (an unknown name falls back to the default).
function M.tune(name)
    if M.TUNES[name] then return M.TUNES[name], name end
    return M.TUNES[M.DEFAULT], M.DEFAULT
end

-- Pure: the tune's lowest note.
function M.lowest(t)
    local lo = math.huge
    for _, n in ipairs(t.notes) do lo = math.min(lo, n[2]) end
    return lo
end

-- Pure: how long a tune lasts, in seconds (its last note's end plus the voice's release).
function M.length(t)
    local last = 0
    for _, n in ipairs(t.notes) do last = math.max(last, n[1] + n[3]) end
    return last + M.VOICES[t.voice].releaseMs / 1000
end

-- Pure: where the voice's filter settles for a tune, in Hz.
function M.restCutoff(t) return M.noteToHz(M.lowest(t)) * M.VOICES[t.voice].cutoff end

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
    if not ok then log.info("ding: %s failed: %s", fn, tostring(err)) end
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
    pcall(function() comp.VoiceCount = 16 end) -- chords ring over the notes before them
    call(comp, "SetEnablePolyphony", true)
    call(comp, "SetOscGain", 0, 1.0)
    -- each note's start: the mod envelope opens the low-pass filter wide, then closes it
    call(comp, "SetFilterType", 0) -- low pass
    call(comp, "SetFilterAlgorithm", 1) -- state variable
    call(comp, "SetFilterQ", 0.8)
    call(comp, "SetModEnvPatch", 2) -- to the filter's frequency
    call(comp, "SetModEnvDepth", 1.0)
    call(comp, "SetModEnvAttackTime", 0.5)
    call(comp, "SetModEnvSustainGain", 0.0)
    call(comp, "SetStereoDelayTime", 70)
    call(comp, "SetStereoDelayFeedback", 0.1)
    call(comp, "SetStereoDelayWetlevel", 0.18)
    call(comp, "SetGainDb", M.volumeToDb(D.volume))
    call(comp, "Start")
    tuned = nil
    log.info("ding: synth ready")
    return comp
end

local function playAsset(path)
    local snd = StaticFindObject(path)
    if not W.valid(snd) and LoadAsset then pcall(function() snd = LoadAsset(path) end) end
    if not W.valid(snd) then log.warn("ding: sound asset %s not found", path) return false end
    local gs = StaticFindObject("/Script/Engine.Default__GameplayStatics")
    return pcall(function() gs:PlaySound2D(FindFirstOf("GameInstance"), snd, D.volume, 1.0, 0.0, nil, nil, true) end)
end

-- Set the synth up for a tune's voice (only when it changed; the filter follows the tune's range).
local function setVoice(t, name)
    if tuned == name then return end
    local v = M.VOICES[t.voice]
    local semis, cents = M.ratioToSemitones(v.overtone)
    call(synth, "SetOscType", 0, v.osc[1])
    call(synth, "SetOscType", 1, v.osc[2])
    call(synth, "SetOscGain", 1, v.overtoneGain)
    call(synth, "SetOscSemitones", 1, semis)
    call(synth, "SetOscCents", 1, cents)
    call(synth, "SetAttackTime", v.attackMs)
    call(synth, "SetDecayTime", v.decayMs)
    call(synth, "SetSustainGain", v.sustain)
    call(synth, "SetReleaseTime", v.releaseMs)
    call(synth, "SetFilterFrequency", M.restCutoff(t))
    call(synth, "SetModEnvDecayTime", v.hitMs)
    call(synth, "SetModEnvReleaseTime", v.hitMs)
    call(synth, "SetStereoDelayIsEnabled", v.shimmer)
    tuned = name
    log.info("ding: %s on %s (%d notes, %.2f s)", name, t.voice, #t.notes, M.length(t))
end

-- force: play even with the fanfare switched off (picking a tune in Settings plays it).
function M.play(force)
    if not ctx.enabled then return end
    if not (D.enabled or force) then return end
    if D.asset and D.asset ~= "" and not force then
        if playAsset(D.asset) then return end
    end
    if not (synth and W.valid(synth)) then synth = makeSynth() end
    if not synth then return end
    local t, name = M.tune(D.sound)
    setVoice(t, name)
    call(synth, "SetGainDb", M.volumeToDb(D.volume) + M.VOICES[t.voice].gainDb)
    local s = synth
    for i, n in ipairs(t.notes) do
        local function strike()
            if W.valid(s) then call(s, "NoteOn", n[2], n[4], n[3]) end
        end
        if n[1] <= 0 then strike() else ctx.sched.later(math.floor(n[1] * 1000 + 0.5), "ding.note" .. i, strike) end
    end
end

-- the Settings panel's volume slider
function M.setVolume(v) D.volume = v end

function M.init(c)
    ctx, W, log, D = c, c.widgets, c.log, c.settings.ding
    c.events.on("worldchanged", function() synth, tuned = nil, nil end)
end

return M
