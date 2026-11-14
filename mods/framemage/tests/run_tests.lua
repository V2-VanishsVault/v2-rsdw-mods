-- Unit tests for the engine-independent parts. Run from the repo root with Lua 5.4:
--   lua tests/run_tests.lua
-- dev/ holds the developer features (the API dump): not in releases, tested here too.
-- ../../shared/ holds the Settings panel every mod ships (as Scripts/settingspanel): tested here too.
package.path = "FrameMage/Scripts/?.lua;dev/?.lua;../../shared/?.lua;" .. package.path
print = print -- log.lua writes through print

local failures, passes = 0, 0
local function check(name, cond, detail)
    if cond then passes = passes + 1 else
        failures = failures + 1
        io.stderr:write("FAIL " .. name .. (detail and (": " .. tostring(detail)) or "") .. "\n")
    end
end
local function eq(name, a, b) check(name, a == b, string.format("got %s, want %s", tostring(a), tostring(b))) end

-- serialize ---------------------------------------------------------------------
local S = require("framemage.core.serialize")
local data = {
    elements = {
        ["WBP_HUD/Bar"] = { x = 12, y = -3.5, scale = 1.25, hidden = true },
        ["WBP_HUD/WBP_Buff*"] = { opacity = 0.3 },
    },
    profiles = { "default", "combat" },
    weird = { ['q"uote\n'] = 1 },
}
local text = S.dump(data)
local back, err = S.parse(text, "t")
check("roundtrip parses", back ~= nil, err)
eq("roundtrip x", back.elements["WBP_HUD/Bar"].x, 12)
eq("roundtrip float y", back.elements["WBP_HUD/Bar"].y, -3.5)
eq("roundtrip bool", back.elements["WBP_HUD/Bar"].hidden, true)
eq("roundtrip opacity", back.elements["WBP_HUD/WBP_Buff*"].opacity, 0.3)
eq("roundtrip array", back.profiles[2], "combat")
eq("roundtrip escaped key", back.weird['q"uote\n'], 1)
eq("deterministic", S.dump(back), text)
eq("float formatting", S.dump({ a = 0.1 + 0.2 }):match("a = ([%d%.]+)"), "0.3")
check("sandboxed: no os", S.parse("return { x = os.time() }") == nil)
check("rejects non-table", S.parse("return 5") == nil)
check("rejects syntax error", S.parse("return {") == nil)

-- config.merge -----------------------------------------------------------------
local C = require("framemage.core.config")
local m = C.merge({ keys = { edit = "F9", dump = "CTRL+F9" }, list = { "a", "b" }, n = 1 },
    { keys = { edit = "F8" }, list = { "z" } })
eq("merge override", m.keys.edit, "F8")
eq("merge keeps default", m.keys.dump, "CTRL+F9")
eq("merge array replaces", #m.list, 1)
eq("merge scalar default", m.n, 1)

-- config.diff ----------------------------------------------------------------------
local defs = { grid = { size = 16, color = { 1, 0.85, 0.45 } }, keys = { edit = "F9" }, logLevel = "info" }
local d, unknown = C.diff(defs, { grid = { size = 16, color = { 1, 0.85, 0.45 }, sweepMs = 250 },
    keys = { edit = "F8" }, logLevel = "info", stray = 1 })
eq("diff keeps change", d.keys.edit, "F8")
check("diff drops equal scalar", d.logLevel == nil)
check("diff drops equal subtable", d.grid == nil)
eq("diff reports unknown", table.concat(unknown, ","):find("grid.sweepMs", 1, true) ~= nil, true)
eq("diff reports unknown top", #unknown, 2)
d = C.diff(defs, { grid = { size = 16, color = { 0, 1, 1 } } })
eq("diff array replaced whole", d.grid.color[1], 0)
check("diff of defaults is empty", next((C.diff(defs, C.deepCopy(defs)))) == nil)

-- keys.parse --------------------------------------------------------------------
local K = require("framemage.core.keys")
local p = K.parse("ctrl+shift+F9")
eq("parse key", p.key, "F9")
eq("parse mods", table.concat(p.mods, ","), "CONTROL,SHIFT")
eq("parse plain", #K.parse("PAGE_DOWN").mods, 0)
check("parse bad modifier", K.parse("HYPER+F1") == nil)
check("parse empty", K.parse("") == nil)
check("parse none", K.parse("none") == nil)
eq("UE4SS name -> Unreal", K.parse("PAGE_DOWN").key, "PageDown")
eq("Unreal name kept", K.parse("LeftBracket").key, "LeftBracket")
eq("OEM_FOUR is [", K.unrealName("OEM_FOUR"), "LeftBracket")
eq("mouse name", K.unrealName("LEFT_MOUSE_BUTTON"), "LeftMouseButton")
eq("digit", K.unrealName("7"), "Seven")
eq("letter", K.unrealName("g"), "G")
eq("ctrl + unreal", K.parse("ctrl+PageDown").key, "PageDown")
check("plain needs no modifiers", K.modsMatch({}, { CONTROL = false, SHIFT = false, ALT = false }))
check("plain refuses ctrl held", not K.modsMatch({}, { CONTROL = true }))
check("ctrl combo matches", K.modsMatch({ "CONTROL" }, { CONTROL = true, SHIFT = false }))
check("ctrl combo refuses extra shift", not K.modsMatch({ "CONTROL" }, { CONTROL = true, SHIFT = true }))

-- widgets pure helpers ---------------------------------------------------------
local W = require("framemage.core.widgets")
eq("strip _C", W.stripClassSuffix("WBP_HUD_C"), "WBP_HUD")
eq("normalize instance", W.normaliseName("WBP_BuffEntry_C_2147482", "WBP_BuffEntry_C"), "WBP_BuffEntry*")
eq("keep designer name", W.normaliseName("HealthBar", "WBP_Bar_C"), "HealthBar")
eq("keep numbered designer name", W.normaliseName("Image_12", "Image"), "Image_12")
check("transient is instance", W.isInstanceFullName("WBP_HUD_C /Engine/Transient.GameEngine_0:BP_GI_C_0.WBP_HUD_C_0"))
check("template is not", not W.isInstanceFullName("WBP_Bar_C /Game/UI/WBP_HUD.WBP_HUD_C:WidgetTree.Bar"))
check("CDO is not", not W.isInstanceFullName("WBP_HUD_C /Engine/Transient.Default__WBP_HUD_C"))

-- layout.resolve -----------------------------------------------------------------
local L = require("framemage.features.layout")
local t = L.resolve(nil)
check("no entry touches nothing", t.translate == nil and t.scale == nil and t.opacity == nil)
t = L.resolve({ x = 5 })
check("move only leaves opacity to the game", t.opacity == nil and t.scale == nil)
eq("move only x", t.translate[1], 5); eq("move only y defaults 0", t.translate[2], 0)
t = L.resolve({ x = 5, y = 6, scale = 2, opacity = 0.5 })
eq("scale", t.scale, 2); eq("opacity absolute", t.opacity, 0.5)
eq("hidden", L.resolve({ hidden = true, opacity = 1 }).opacity, 0)
eq("clamped", L.resolve({ opacity = 3 }).opacity, 1)
local r = L.released({ x = 4, opacity = 0.5 }, { x = 8 })
check("released opacity only", r.opacity and not r.translate and not r.scale)
r = L.released({ x = 4, scale = 2 }, nil)
check("released all on reset", r.translate and r.scale and not r.opacity)
r = L.released({ hidden = true }, { opacity = 0.4 })
check("hidden -> faded keeps opacity owned", not r.opacity)

-- names.pretty ----------------------------------------------------------------------
local N0 = require("framemage.core.names")
eq("pretty nested", N0.pretty("WBP_HUD_RootWidget/HUD_Survival/WBP_SurvivalCore_Upkeep_Hydration"), "Survival Core Upkeep Hydration")
eq("pretty instance", N0.pretty("WBP_HUD/WBP_BuffEntry*"), "Buff Entry")
eq("pretty acronym", N0.pretty("WBP_HUD/HPBarText"), "HP Bar Text")
eq("pretty digits", N0.pretty("WBP_HUD/XPProgress2"), "XP Progress 2")
eq("pretty root", N0.pretty("WBP_HUD_QuestList"), "Quest List")

-- editor pure parts ------------------------------------------------------------------
local E = require("framemage.features.editor")
eq("banner name only", E.bannerText("WBP_HUD/WBP_QuestTracker", nil), "Quest Tracker")
eq("banner hidden", E.bannerText("WBP_HUD/Compass", { hidden = true }), "Compass  (hidden)")
eq("banner nothing", E.bannerText(nil), "Drag a title bar to move it, or click anything to select it")

-- drag bars on every element
do
    local HS = { handleMinArea = 900, handleMaxScreenShare = 0.5 }
    local screen = 1920 * 1080
    check("handle: normal panel", E.wantsHandle(200 * 80, screen, false, HS))
    check("handle: tiny piece", not E.wantsHandle(20 * 20, screen, false, HS))
    check("handle: full-screen container", not E.wantsHandle(screen, screen, false, HS))
    check("handle: building block", not E.wantsHandle(200 * 80, screen, true, HS))

    local H = require("framemage.editor.handles")
    local s = { gap = 3, minTop = 6, corner = 3, screenW = 1920, screenH = 1080 }
    local function item(l, t, r, b) return { rect = { left = l, top = t, right = r, bottom = b }, w = 100, h = 20 } end
    -- room above: the bar sits above the element's top-left
    local bars = H.layout({ item(500, 300, 800, 400) }, s)
    eq("bar above x", bars[1].left, 497)
    eq("bar above y", bars[1].top, 300 - 3 - 3 - 20)
    -- at the top of the screen: below instead
    bars = H.layout({ item(500, 10, 800, 100) }, s)
    eq("bar below at top", bars[1].top, 100 + 3 + 3)
    -- two elements at the same spot: the second bar moves below its element
    bars = H.layout({ item(500, 300, 800, 400), item(510, 300, 700, 380) }, s)
    check("second bar placed", bars[2] ~= false)
    check("bars never overlap", not H.overlaps(bars[1], bars[2]))
    -- no room anywhere: left out
    local crowd = {}
    for i = 1, 5 do crowd[i] = item(500, 300, 800, 330) end
    bars = H.layout(crowd, s)
    local n, clash = 0, false
    for i = 1, 5 do
        if bars[i] then
            n = n + 1
            for j = 1, i - 1 do if bars[j] and H.overlaps(bars[i], bars[j]) then clash = true end end
        end
    end
    check("crowded: some bars left out", n < 5 and n >= 1)
    check("crowded: none overlap", not clash)
    -- kept on screen at the right edge
    bars = H.layout({ item(1900, 300, 1920, 400) }, s)
    eq("bar kept on screen", bars[1].right, 1920)
end

-- layout measurement (FGeometry can't be read from Lua, so positions are computed from layout data)
do
    local MS = require("framemage.core.measure")
    local P = MS.makeRect(0, 0, 1920, 1080)
    local function near(name, a, b) check(name, math.abs(a - b) < 1e-6, string.format("got %s, want %s", tostring(a), tostring(b))) end
    -- canvas: anchored top-right, aligned by its right edge, auto-sized
    local ld = { Offsets = { Left = -20, Top = 30, Right = 0, Bottom = 0 },
        Anchors = { Minimum = { X = 1, Y = 0 }, Maximum = { X = 1, Y = 0 } }, Alignment = { X = 1, Y = 0 } }
    local r = MS.canvas(P, ld, true, 200, 50)
    near("canvas top-right left", r.left, 1920 - 20 - 200)
    near("canvas top-right top", r.top, 30)
    near("canvas top-right right", r.right, 1900)
    -- canvas: fixed size from offsets (not auto), centered
    ld = { Offsets = { Left = 0, Top = 0, Right = 300, Bottom = 100 },
        Anchors = { Minimum = { X = 0.5, Y = 0.5 }, Maximum = { X = 0.5, Y = 0.5 } }, Alignment = { X = 0.5, Y = 0.5 } }
    r = MS.canvas(P, ld, false, 10, 10)
    near("canvas centered left", r.left, 960 - 150)
    near("canvas centered bottom", r.bottom, 540 + 50)
    -- canvas: stretched across the bottom with margins
    ld = { Offsets = { Left = 10, Top = -80, Right = 10, Bottom = 60 },
        Anchors = { Minimum = { X = 0, Y = 1 }, Maximum = { X = 1, Y = 1 } }, Alignment = { X = 0, Y = 0 } }
    r = MS.canvas(P, ld, false, 0, 0)
    near("canvas stretched left", r.left, 10)
    near("canvas stretched right", r.right, 1910)
    near("canvas stretched top", r.top, 1000)
    -- overlay-style alignment with padding
    r = MS.aligned(P, { Left = 5, Top = 5, Right = 5, Bottom = 5 }, 3, 3, 100, 40)
    near("aligned bottom-right", r.right, 1915)
    near("aligned bottom-right top", r.top, 1075 - 40)
    r = MS.aligned(P, nil, 0, 0, 100, 40)
    near("aligned fill", r.right, 1920)
    -- vertical box: two auto rows then a fill row
    local pad0 = { Left = 0, Top = 0, Right = 0, Bottom = 0 }
    local items = {
        { dw = 100, dh = 20, pad = pad0, h = 1, v = 0, fill = false, value = 1 },
        { collapsed = true, dw = 100, dh = 999, pad = pad0, h = 1, v = 0, fill = false, value = 1 },
        { dw = 50, dh = 30, pad = { Left = 0, Top = 4, Right = 0, Bottom = 0 }, h = 1, v = 0, fill = false, value = 1 },
        { dw = 10, dh = 10, pad = pad0, h = 0, v = 0, fill = true, value = 1 },
    }
    local box = MS.makeRect(100, 200, 300, 400)
    r = MS.box(box, items, 3, true)
    near("vbox third top (collapsed one takes no space)", r.top, 200 + 20 + 4)
    near("vbox third left aligned", r.right, 150)
    r = MS.box(box, items, 4, true)
    near("vbox fill takes the rest", r.bottom, 600)
    near("vbox fill top", r.top, 254)
    -- horizontal box
    r = MS.box(box, { { dw = 40, dh = 10, pad = pad0, h = 0, v = 2, fill = false, value = 1 },
        { dw = 60, dh = 10, pad = pad0, h = 0, v = 2, fill = false, value = 1 } }, 2, false)
    near("hbox second left", r.left, 140)
    near("hbox centered vertically", r.top, 200 + 195)
    -- uniform grid
    r = MS.uniformGrid(MS.makeRect(0, 0, 300, 200), { { row = 0, col = 0, h = 0, v = 0, dw = 1, dh = 1 },
        { row = 1, col = 2, h = 0, v = 0, dw = 1, dh = 1 } }, 2)
    near("uniform grid cell left", r.left, 200)
    near("uniform grid cell top", r.top, 100)
    -- render transform: translation and scale about the center, composed with a parent's
    local L = MS.makeRect(100, 100, 200, 100)
    local T = MS.renderAffine(L, { Translation = { X = 30, Y = -10 }, Scale = { X = 2, Y = 2 } }, { X = 0.5, Y = 0.5 })
    r = MS.apply(T, L)
    near("transform left", r.left, 0 + 30)
    near("transform top", r.top, 50 - 10)
    near("transform scale", r.accScale, 2)
    local parentT = MS.renderAffine(MS.makeRect(0, 0, 1920, 1080), { Translation = { X = 5, Y = 0 }, Scale = { X = 1, Y = 1 } }, nil)
    r = MS.apply(MS.compose(parentT, T), L)
    near("parent translation carries", r.left, 35)
end

-- themes
do
    local TH = require("framemage.core.themes")
    local o = TH.searchOrder("wizard")
    eq("theme search: own first", o[1], "wizard"); eq("theme search: then elven", o[2], "elven")
    eq("theme search: elven alone", #TH.searchOrder("elven"), 1)
    eq("old theme name still works", TH.canonical("general"), "elven")
    check("old theme name is known", TH.known("general"))
    check("theme known", TH.known("ranger")); check("theme unknown", not TH.known("nonsense"))
    check("Dwarven is a theme", TH.known("dwarven"))
    eq("Default (dropped) loads as Elven", TH.canonical("default"), "elven")
    eq("Demi-human is now Elven", TH.canonical("demihuman"), "elven")
    do  -- the Settings picker offers every theme, in the same order
        local row
        for _, r in ipairs(require("framemage.core.options").SCHEMA) do if r.setting == "theme" then row = r end end
        eq("Settings offers every theme", table.concat(row.options, ","), table.concat(TH.LIST, ","))
        for _, name in ipairs(TH.LIST) do check("Settings names theme " .. name, row.labels[name] == TH.LABELS[name]) end
    end
    local m = TH.merge({ gold = { 1, 0, 0 }, panelPad = { 1, 2, 3, 4 }, nested = { a = 1, b = 2 } },
        { gold = { 0, 1, 0 }, nested = { b = 3 } })
    eq("merge replaces color arrays", m.gold[2], 1); eq("merge keeps untouched", m.panelPad[4], 4)
    eq("merge deep keeps", m.nested.a, 1); eq("merge deep overrides", m.nested.b, 3)
    eq("builtin has every color", type(TH.BUILTIN.ink), "table")
    local ST = require("framemage.editor.style")
    local b = ST.brushSpec("tex", "box", 128, 32, { 0.2, 0.3 })
    eq("box brush draws as box", b.DrawAs, 1); eq("box brush h margin", b.Margin.Left, 0.2); eq("box brush v margin", b.Margin.Top, 0.3)
    local t = ST.brushSpec("tex", "tile", 128, 128)
    eq("tile brush draws as image", t.DrawAs, 3); eq("tile brush tiles both ways", t.Tiling, 3)
    eq("box brush single margin", ST.brushSpec("tex", "box", 64, 64, 0.25).Margin.Bottom, 0.25)
    eq("border brush: edges tiled (Slate's Border draw)", ST.brushSpec("tex", "border", 256, 256, 0.19).DrawAs, 2)
    eq("box brush: stretched", ST.brushSpec("tex", "box", 256, 256, 0.19).DrawAs, 1)
    eq("background: slate is a painting now", ST.stoneFile("slate"), "panel_bg_slate.png")
    eq("background: a removed one (moonstone) is the theme's own", ST.stoneFile("moonstone", { background = "x.png" }), "x.png")
    eq("background: unknown, and no theme background: slate", ST.stoneFile("granite"), "panel_bg_slate.png")
    eq("background: none: slate", ST.stoneFile(nil), "panel_bg_slate.png")
    eq("background: a painting's tile", ST.stoneFile("forge"), "panel_bg_forge.png")
    eq("background: the theme's own", ST.stoneFile("theme", { background = "panel_bg_silk.png" }), "panel_bg_silk.png")
    eq("background: a theme without one gets slate", ST.stoneFile("theme", {}), "panel_bg_slate.png")
    eq("background: a painting is drawn twice a stone's size", ST.stoneTile("panel_bg_oak.png", 128), 256)
    eq("background: anything else at a stone's size", ST.stoneTile("panel_stone.png", 128), 128)
end

-- texture dump details
do
    local A = require("framemage.features.art")
    eq("size text", A.sizeText(255.6, 64), "256x64"); eq("size text bad", A.sizeText(0, 4), nil)
    local I = require("framemage.features.inspector")
    local line = I.textureLine(false, "T_Bar_Bg", { count = 3, size = "256x32", drawn = "128x16", drawAs = "box", where = "WBP_HUD/Bars" })
    check("texture line has size", line:find("size=256x32", 1, true) ~= nil, line)
    check("texture line has drawn", line:find("drawn=128x16", 1, true) ~= nil, line)
    check("texture line marks 9-slice", line:find("  box", 1, true) ~= nil, line)
    check("texture line has where", line:find("where=WBP_HUD/Bars", 1, true) ~= nil, line)
    check("plain image not marked", not I.textureLine(true, "X", { count = 1, drawAs = "image" }):find("image", 1, true))
end

-- what counts as one movable element
do
    local U = require("framemage.editor.units")
    eq("draws itself: one unit (compass + markers)", U.verdict({ visuals = 3, lists = { 1 }, children = { 1 } }), "unit")
    eq("wraps one list: one unit (hotbar)", U.verdict({ visuals = 0, lists = { 1 }, children = {} }), "unit")
    eq("several lists: container (key hints + shortcuts)", U.verdict({ visuals = 0, lists = { 1, 2 }, children = {} }), "container")
    eq("wraps sub-elements: container (inventory frame)", U.verdict({ visuals = 0, lists = {}, children = { 1 } }), "container")
    eq("list plus sub-element: container", U.verdict({ visuals = 0, lists = { 1 }, children = { 1 } }), "container")
    eq("nothing showing: empty", U.verdict({ visuals = 0, lists = {}, children = {} }), "empty")
    local SA = 1920 * 1080
    check("empty element at the top-left corner: not offered (place unknown)",
        not U.emptyPlaceable({ left = 0, top = 0, right = 300, bottom = 80 }, SA, 0.5))
    check("empty element covering the screen: not offered", not U.emptyPlaceable({ left = 5, top = 5, right = 1915, bottom = 1075 }, SA, 0.5))
    check("empty element with a real place: offered", U.emptyPlaceable({ left = 800, top = 600, right = 1100, bottom = 680 }, SA, 0.5))
    check("no rect: not offered", not U.emptyPlaceable(nil, SA, 0.5))
    local si = U.standIn({ left = 50, top = 60 }, { left = 50, top = 60, right = 350, bottom = 560 }, 200, 80, SA)
    check("stand-in: an empty element's own tall box", si.right == 350 and si.bottom == 560)
    local sj = U.standIn({ left = 50, top = 60 }, { left = 50, top = 60, right = 60, bottom = 70 }, 200, 80, SA)
    check("stand-in: at least the usual size", sj.right == 250 and sj.bottom == 140)
    -- previews of elements showing nothing
    local SM = require("framemage.editor.samples")
    check("a collapsed sliver isn't a showing", not SM.isShowing(220, 4))
    check("a real box is a showing", SM.isShowing(360, 130))
    SM._set({ ["HUD.Pickups"] = { 360, 130 } })
    local w1, h1, k1 = SM.sizeFor("HUD.Pickups", 220, 56)
    check("stand-in: the size it last showed at", w1 == 360 and h1 == 130 and k1)
    local w2, h2, k2 = SM.sizeFor("HUD.Never", 220, 56)
    check("stand-in: never seen, the usual size", w2 == 220 and h2 == 56 and not k2)
    SM._set({})
    local bx = SM.box({ left = 1800, top = 1000 }, 360, 130, 1920, 1080)
    check("stand-in kept on screen", bx.right == 1920 and bx.bottom == 1080 and bx.left == 1560)
    local PV = require("framemage.editor.preview")
    local pg = PV.pageIndexes({ "LevelUpNotificationItem", "AchievementNotificationItem", "NewSkillNotificationItem" },
        { "AchievementNotificationItem", "FishCaughtNotificationItem", "NewSkillNotificationItem" })
    check("notice pages: the ones it has, in order", #pg == 2 and pg[1] == 1 and pg[2] == 2)
    check("notice entries known", PV.NOTICES.WBP_ItemPickups_Item_C ~= nil)
    check("no level-up page (the celebration replaces it)",
        not table.concat(PV.NOTICES.WBP_PrimaryNotificationQueue_Item_C.pages, ","):find("LevelUpNotificationItem", 1, true))
    check("Compass Marker never offered", U.skipSelect("Compass Marker", { "Compass Marker" }))
    check("numbered Compass Markers never offered", U.skipSelect("compass marker 3", { "Compass Marker" }))
    check("other elements offered", not U.skipSelect("Compass", { "Compass Marker" }))
    check("designer name kept", U.meaningfulName("GameInputs"))
    check("designer name kept 2", U.meaningfulName("SlotGridContainer"))
    check("default name dropped", not U.meaningfulName("HorizontalBox_436"))
    check("default name dropped 2", not U.meaningfulName("Overlay_1"))
    check("bare class name dropped", not U.meaningfulName("VerticalBox"))
    check("instance name dropped", not U.meaningfulName("WBP_Slot_C_2147445737"))
    check("list view recognized", U.isListView("ListView"))
    check("common list view recognized", U.isListView("CommonListView"))
    check("tile view recognized", U.isListView("CommonTileView"))
    check("plain box is not a list view", not U.isListView("VerticalBox"))
    do -- vitals rows: the rings (and their drop shadows) never touch the ring below
        local b = require("framemage.defaults").bars
        check("vitals rings keep a gap", b.rowPitch - b.ringSize - b.shadowOffsetY >= 4,
            ("rowPitch %d, ringSize %d"):format(b.rowPitch, b.ringSize))
    end
    check("common switcher recognized", U.isSwitcher("CommonAnimatedSwitcher"))
    check("widget switcher recognized", U.isSwitcher("WidgetSwitcher"))
    check("overlay is not a switcher", not U.isSwitcher("Overlay"))
    -- the world key legend: key hints (a grid under a size box) and menu shortcuts (a row), side by side
    local hints = { "Overlay_0", "VerticalBox_57", "SizeBox_0", "GameInputs" }
    local shortcuts = { "Overlay_0", "VerticalBox_57", "HorizontalBox_436" }
    local gb = U.groupByBranch({ hints, shortcuts })
    eq("hints and shortcuts: two groups", #gb, 2)
    eq("hints alone", gb[1][1], 1); eq("shortcuts alone", gb[2][1], 2)
    local one = U.groupByBranch({ shortcuts })
    eq("one piece (hints hidden): one group", #one, 1)
    local three = U.groupByBranch({ { "A", "B", "X" }, { "A", "B", "Y", "Z" }, { "A", "B", "X", "Q" } })
    eq("grouped by branch below shared node", #three, 2)
    eq("same branch together", #three[1], 2)
    local nested = U.groupByBranch({ { "A", "B" }, { "A", "B", "C" } })
    eq("a piece that is the shared node stands alone", #nested, 2)
    eq("no pieces: no groups", #U.groupByBranch({}), 0)
    check("vitals frame is minor: split", U.ownIsMinor(1200, 30000, 4))
    check("compass strip is major: whole", not U.ownIsMinor(18000, 8000, 5))
    check("one child: never split here", not U.ownIsMinor(10, 30000, 1))
    local function R(l, t, r, b) return { left = l, top = t, right = r, bottom = b } end
    -- survival circles far left, the bars and their shadow together in the middle
    local cl = U.cluster({ R(30, 480, 130, 530), R(900, 480, 1080, 520), R(895, 470, 1090, 530), R(950, 440, 1010, 470) }, 48)
    eq("far-apart parts: two groups", #cl, 2)
    eq("left group alone", #cl[1], 1)
    eq("middle group together", #cl[2], 3)
    eq("touching parts: one group", #U.cluster({ R(0, 0, 100, 20), R(0, 30, 100, 50), R(110, 0, 200, 50) }, 48), 1)
end

-- element names that tell elements apart
do
    local N = require("framemage.core.names")
    local t = N.titles({
        "WBP_HUD_Notifications/PlayerUpkeeps/NotificationQueueWidget",
        "WBP_HUD_Notifications/ItemPickups/NotificationQueueWidget",
        "WBP_HUD_Compass",
        "WBP_Hotbar/Slot",
        "WBP_Spellbar/Slot",
    })
    eq("generic name gives way to parent", t[1], "Player Upkeeps")
    eq("generic name gives way to parent 2", t[2], "Item Pickups")
    eq("plain name kept", t[3], "Compass")
    eq("clashing names get parent in front", t[4], "Hotbar - Slot")
    eq("clashing names get parent in front 2", t[5], "Spellbar - Slot")
end

-- progress-bar style
do
    local B = require("framemage.features.bars")
    eq("bars: the special bar as tall as the tallest", B.rawHeight(15, 21, true), 21)
    eq("bars: a bar keeps its own height when they needn't match", B.rawHeight(15, 21, false), 15)
    eq("bars: no height yet", B.rawHeight(0, 21, true), nil)
    check("health bar class", B.isBarClass("WBP_HUD_Vitals_HealthBar_C"))
    check("stamina bar class", B.isBarClass("WBP_HUD_Vitals_StaminaBar_C"))
    check("other widget not a bar", not B.isBarClass("WBP_HUD_PlayerVitalsBars_C"))
    check("enemy bar left alone", not B.isBarClass("WBP_AI_Healthbar_C"))
    check("our overlay recognized", B.isOurs("FM_Bevel_3"))
    check("game widget not ours", not B.isOurs("ProgressBarImage"))
    eq("bevel art", B.artFor("bevel"), "ui/bar_bevel.png")
    eq("facet art", B.artFor("facet"), "ui/bar_facet.png")
    eq("flat has no overlay", B.artFor("flat"), nil)
    check("ring: stamina icon", B.isIcon("StaminaIcon"))
    check("ring: health icon", B.isIcon("HealthImage"))
    check("ring: special icon", B.isIcon("SpecialAttackImage"))
    check("ring: other images untouched", not B.isIcon("ProgressBarImage"))
    check("ring box recognized", B.isRingBox("FM_RingBox_4"))
    check("game panel not a ring box", not B.isRingBox("HorizontalBox_0"))
    local top, bottom = B.rowPadding(38, 46, 0, 0)
    eq("short bar: padded up to the pitch (top)", top, 4); eq("short bar: padded (bottom)", bottom, 4)
    top, bottom = B.rowPadding(56, 46, 0, 0)
    eq("tall bar: pulled in to the pitch", top, -5); eq("tall bar: pulled in (bottom)", bottom, -5)
    top, bottom = B.rowPadding(40, 46, 2, 4)
    eq("game padding kept, difference shared (top)", top, 2); eq("difference shared (bottom)", bottom, 4)
    eq("row is exactly the pitch", 40 + top + bottom, 46)
    local c, m = B.parseValue("200 / 200")
    eq("value: current", c, 200); eq("value: max", m, 200)
    c, m = B.parseValue("4/100")
    eq("value: no spaces", c, 4); eq("value: no spaces max", m, 100)
    eq("value: not a value", B.parseValue("Health"), nil)
    check("full: equal", B.isFull(100, 100))
    check("not full: less", not B.isFull(45, 100))
    check("full: no text (stamina hides it when full)", B.isFull(nil, nil))
    check("point box recognized", B.isTip("FM_Tip_2"))
    eq("point shading: facet", B.tipArt("facet"), "ui/bar_tip_facet.png")
    eq("point shading: flat has none", B.tipArt("flat"), nil)
    check("outline recognized", B.isOutline("FM_Outline_7"))
    check("upkeep widget: nothing of it hidden any more", not B.isUpkeepClass("WBP_SurvivalCore_Upkeep_C"))
    eq("upkeep: the divider always shows (not hideable)", #B.hideable("WBP_SurvivalCore_Upkeep_C"), 0)
    eq("input legend: the key hints are hideable", B.hideable("WBP_InputLegend_World_C")[1].name, "GameInputs")
    eq("other widgets: nothing hideable", #B.hideable("WBP_HUD_Compass_C"), 0)
    local g = B.durabilityColor(1)
    check("durability: green at 100%", g.G > g.R and g.G > 0.5)
    local y = B.durabilityColor(0.75)
    check("durability: yellow at 75%", y.R > 0.9 and y.G > 0.7)
    local o = B.durabilityColor(0.5)
    check("durability: orange at 50%", o.R > 0.9 and o.G > 0.3 and o.G < 0.5)
    local r = B.durabilityColor(0.1)
    check("durability: red at 25% and below", r.R > 0.8 and r.G < 0.1)
    eq("durability: 76% is green", B.durabilityColor(0.76).G, g.G)
    eq("durability: 51% is yellow", B.durabilityColor(0.51).G, y.G)
    eq("durability: 26% is orange", B.durabilityColor(0.26).G, o.G)
    eq("durability: 25% is red", B.durabilityColor(0.25).G, r.G)
    eq("durability: 0% is red", B.durabilityColor(0).G, r.G)
    check("game image not an outline", not B.isOutline("ProgressBarImage"))
    eq("bar height: taller then 75%", B.barHeight(26, 6, 0.75), 24)
    eq("bar height: no scale", B.barHeight(26, 6, nil), 32)
    eq("shaped facet body", B.overlayArt("facet", true), "ui/bar_facet_body.png")
    eq("shaped bevel body", B.overlayArt("bevel", true), "ui/bar_bevel_body.png")
    eq("plain facet art", B.overlayArt("facet", false), "ui/bar_facet.png")
    eq("flat has no overlay, tapered or not", B.overlayArt("flat", true), nil)
    eq("pointed end art", B.endArt("facet", true).outline, "ui/bar_tip_outline.png")
    eq("flat end art", B.endArt("facet", false).outline, "ui/bar_end_outline.png")
    eq("flat end shading", B.endArt("bevel", false).shade, "ui/bar_end_bevel.png")
    eq("flat style end: no shading", B.endArt("flat", false).shade, nil)
    eq("point length", B.endWidth({ taperWidth = 16, endWidth = 3 }, true), 16)
    local st = B.tipStrips(4, true)
    eq("tip strips: count", #st, 4)
    check("tip strips: top strip short", math.abs(st[1].w - 0.25) < 1e-9)
    check("tip strips: middle strips long", math.abs(st[2].w - 0.75) < 1e-9)
    check("tip strips: symmetric", math.abs(st[4].w - st[1].w) < 1e-9)
    eq("tip strips: bands cover the height", st[4].v1, 1)
    eq("flat end: one full strip", B.tipStrips(9, false)[1].w, 1)
    -- the end's paint: a full-size copy of the bar placed so it continues past the body's end
    local p = B.copyPlacement(400, 16, 25, 0)
    eq("copy starts at the body's left edge", p.x, -400); eq("copy spans body and end", p.w, 416)
    eq("top strip: copy not shifted", p.y, 0); eq("copy is the bar's height", p.h, 25)
    eq("middle strip: copy shifted up by its band", B.copyPlacement(400, 16, 25, 0.5).y, -12.5)
    -- the body's paint stretched the same way, so body and end are one stripe (no line at the join)
    eq("paint stretched over body + end", B.paintStretch(300, 16), 316 / 300)
    eq("no body width: no stretch", B.paintStretch(nil, 16), 1)
    local s = B.paintStretch(300, 16)
    check("join: body's last column = copy's first column",
        math.abs(300 / (300 * s) - 300 / B.copyPlacement(300, 16, 27, 0).w) < 1e-9)
    do -- the Settings panel opens where it was last put, kept on screen
        local St = require("framemage.editor.settings")
        check("settings: four lines of help kept free (11 pt: 66 units)", St.tipHeight(11, 4) == 66)
        eq("settings: the panel widens to fit its tabs", St.panelWidth(540, 611.2), 612)
        eq("settings: never narrower than its set width", St.panelWidth(540, 300), 540)
        local th = { "dwarven", "elven", "ranger", "warrior", "wizard" }
        eq("drop-down: the current value lit", St.dropLit(th, "ranger", nil), 3)
        eq("drop-down: the hovered entry lit instead", St.dropLit(th, "ranger", 5), 5)
        eq("drop-down: nothing lit for an unknown value", St.dropLit(th, "nonsense", nil), nil)
        local x, y = St.onScreen(1200, 300, 1920, 1080)
        eq("saved position kept", x, 1200); eq("saved y kept", y, 300)
        x, y = St.onScreen(3000, 2000, 1920, 1080)
        eq("off the right: pulled back", x, 1840); eq("off the bottom: pulled back", y, 1052)
        x, y = St.onScreen(-50, -10, 1920, 1080)
        eq("off the left: pulled back", x, 0); eq("off the top: pulled back", y, 0)
        local d = require("framemage.defaults").editor
        check("no saved position by default", d.settingsX == false and d.settingsY == false)
    end
    eq("flat end length", B.endWidth({ taperWidth = 16, endWidth = 3 }, false), 3)
end

-- progress-bar style
do
    local B = require("framemage.features.bars")
    check("health bar class", B.isBarClass("WBP_HUD_Vitals_HealthBar_C"))
    check("stamina bar class", B.isBarClass("WBP_HUD_Vitals_StaminaBar_C"))
    check("other widget not a bar", not B.isBarClass("WBP_HUD_PlayerVitalsBars_C"))
    check("enemy bar left alone", not B.isBarClass("WBP_AI_Healthbar_C"))
    check("our overlay recognized", B.isOurs("FM_Bevel_3"))
    check("game widget not ours", not B.isOurs("ProgressBarImage"))
end

-- API dump filter (a developer feature: dev/framemage/features/apidump.lua)
do
    local I = require("framemage.features.apidump")
    check("api: hotbar class", I.wantsApi("QuickAccessBarBase"))
    check("api: spell component", I.wantsApi("SpellcastingComponent"))
    check("api: inventory component", I.wantsApi("InventoryComponent"))
    check("api: unrelated class skipped", not I.wantsApi("WBP_HUD_Compass_C"))
    check("api: workbench", I.wantsApi("CraftingStationComponent"))
    check("api: recipes", I.wantsApi("RecipeSubsystem"))
    check("api: loot", I.wantsApi("LootDropComponent"))
    check("api: carry weight", I.wantsApi("MaxCarryWeightAttribute"))
    eq("api: module from a class path", I.moduleOf("/Script/Dominion.InventoryComponent"), "Dominion")
    eq("api: no module in a game path", I.moduleOf("/Game/UI/WBP_Thing.WBP_Thing_C"), nil)
    local okL, list = pcall(require, "framemage.data.api_classes")
    check("api: class list loads", okL and type(list) == "table" and #list > 100)
    check("api: class default object skipped", not I.wantsApi("Default__InventoryComponent"))
end

-- Developer features stay out of releases: dev/features.lua lists them, each loads from dev/, and no shipping file
-- (FrameMage/Scripts) names a module that only dev/ has.
do
    local okL, names = pcall(dofile, "dev/features.lua")
    check("dev/features.lua lists the developer features", okL and type(names) == "table" and #names > 0, tostring(names))
    for _, name in ipairs(okL and names or {}) do
        local okM, m = pcall(require, "framemage.features." .. name)
        check("developer feature " .. name .. " loads", okM and type(m) == "table" and type(m.init) == "function", tostring(m))
    end
    local function lines(cmd)
        local out, h = {}, io.popen(cmd)
        if h then for l in h:lines() do out[#out + 1] = l end h:close() end
        return out
    end
    local devModules = {}
    for _, f in ipairs(lines("git ls-files --cached --others --exclude-standard dev")) do
        local mod = f:match("^dev/(framemage/.+)%.lua$")
        if mod then devModules[#devModules + 1] = mod:gsub("/", ".") end
    end
    check("dev modules found", #devModules > 0)
    local shipped = lines("git ls-files --cached --others --exclude-standard FrameMage/Scripts")
    check("shipping files found", #shipped > 0)
    for _, f in ipairs(shipped) do
        if f:match("%.lua$") then
            local h = io.open(f, "rb")
            local text = h and h:read("a") or ""
            if h then h:close() end
            for _, mod in ipairs(devModules) do
                check(f .. " doesn't need developer module " .. mod, not text:find('"' .. mod .. '"', 1, true))
            end
        end
    end
    -- the Settings panel's developer rows show only with dev/ installed
    local Opt = require("framemage.core.options")
    local function hasDumpApi()
        for _, r in ipairs(Opt.rowsOf("keys")) do if r.key == "KeyDumpApi" then return true end end
        return false
    end
    Opt.showDev = false
    check("release: no developer key row", not hasDumpApi())
    Opt.showDev = true
    check("development: developer key row shown", hasDumpApi())
    Opt.showDev = false
end

-- hidden-elements panel
do
    local HP = require("framemage.editor.hidden")
    eq("hidden offset clamps low", HP.clampOffset(-3, 40, 14), 0)
    eq("hidden offset clamps high", HP.clampOffset(99, 40, 14), 26)
    eq("hidden offset short list", HP.clampOffset(5, 6, 14), 0)
    local t = HP.uniqueTitles({ "Quest Tracker", "Map", "Quest Tracker", "Quest Tracker" })
    eq("unique 1", t[1], "Quest Tracker")
    eq("unique 2", t[3], "Quest Tracker (2)")
    eq("unique 3", t[4], "Quest Tracker (3)")
    eq("unique other", t[2], "Map")
    eq("range text", HP.rangeText(14, 40, 14), "15-28 of 40")
    eq("range text end", HP.rangeText(26, 40, 14), "27-40 of 40")
    eq("range text empty", HP.rangeText(0, 0, 14), "Nothing hidden right now")
end

local Geo = require("framemage.core.geometry")
local rr = { left = 10, top = 10, right = 10, bottom = 30 }
local g = Geo.atLeast(rr, 16)
eq("atLeast widens empty", g.right - g.left, 16); eq("atLeast centered", g.left, 2); eq("atLeast keeps tall", g.bottom - g.top, 20)
check("contains", Geo.contains({ left = 0, top = 0, right = 10, bottom = 10 }, 5, 10))
check("not contains", not Geo.contains({ left = 0, top = 0, right = 10, bottom = 10 }, 11, 5))
eq("area", Geo.area({ left = 0, top = 0, right = 4, bottom = 5 }), 20)

local F = require("framemage.editor.frame")
local edges, corners = F.pieces({ left = 100, top = 50, right = 200, bottom = 90 }, 1, 3, 12)
eq("4 edges", #edges, 4); eq("8 corner bars", #corners, 8)
eq("top edge above", edges[1][2], 49); eq("top edge width", edges[1][3], 100)
eq("left edge spans corners", edges[3][4], 42)
eq("corner bracket outside", corners[1][1], 97); eq("corner length", corners[1][3], 12)
eq("top-right bracket ends at edge+corner", corners[3][1] + corners[3][3], 203)
local _, tiny = F.pieces({ left = 0, top = 0, right = 4, bottom = 4 }, 1, 3, 12)
eq("brackets shrink on tiny widgets", tiny[1][3], 5)

local P = require("framemage.editor.picker")
local ordered = P.order({ { area = 500, depth = 1, id = "panel" }, { area = 20, depth = 3, id = "icon" },
    { area = 20, depth = 5, id = "deep" }, { area = 9000, depth = 0, id = "root" } })
eq("pick smallest first", ordered[1].id, "deep"); eq("then same-size shallower", ordered[2].id, "icon")
eq("then panel", ordered[3].id, "panel"); eq("root last", ordered[4].id, "root")
check("same spot", P.sameSpot({ x = 10, y = 10 }, { x = 14, y = 7 }, 6))
check("different spot", not P.sameSpot({ x = 10, y = 10 }, { x = 30, y = 10 }, 6))

-- grid.snapDelta -------------------------------------------------------------------
local G = require("framemage.features.grid")
eq("snap right from aligned left", G.snapDelta(0, 50, 1, 16, 0), 14) -- right edge 50 -> 64 beats left 0 -> 16
eq("snap right, left edge nearer", G.snapDelta(5, 100, 1, 16, 0), 11) -- 5 -> 16
eq("snap left to line", G.snapDelta(5, 100, -1, 16, 0), -4) -- 100 -> 96 beats 5 -> 0
eq("aligned moves a full cell", G.snapDelta(16, 32, 1, 16, 0), 16)
eq("aligned moves a full cell left", G.snapDelta(16, 32, -1, 16, 0), -16)
eq("near-aligned skips sliver", G.snapDelta(15.9, 40, 1, 16, 0), 8) -- 40 -> 48 (15.9 -> 32 is 16.1)
eq("origin offset", G.snapDelta(960, 1000, 1, 16, 960), 8) -- 1000 -> 1008 (lines at 960 + 16k)
eq("negative coords", G.snapDelta(-10, -2, -1, 16, 0), -6) -- -10 -> -16
eq("roundTo", G.roundTo(23, 16), 16)
eq("roundTo up", G.roundTo(25, 16), 32)

-- names ------------------------------------------------------------------------------
local N = require("framemage.core.names")
eq("MID long suffix", N.resourceKey("MID_MI_Item_Selected_2147443523", "MaterialInstanceDynamic"), "MID_MI_Item_Selected")
eq("MID short suffix", N.resourceKey("MID_M_UMG_Background_982", "MaterialInstanceDynamic"), "MID_M_UMG_Background")
eq("texture keeps number", N.resourceKey("T_Craft_InfoBackground_1", "Texture2D"), "T_Craft_InfoBackground_1")
eq("MIC keeps name", N.resourceKey("MI_VFX_UI_Laser_01", "MaterialInstanceConstant"), "MI_VFX_UI_Laser_01")
check("runtime texture", N.isRuntime("Texture2D /Engine/Transient.Texture2D_12"))
check("game texture", not N.isRuntime("Texture2D /Game/UI/Icons/T_Icon_Health.T_Icon_Health"))
eq("section T_", N.section("T_Icon_Health"), "Icon")
eq("section MID", N.section("MID_MI_Item_Selected"), "Item")
eq("section MID UI", N.section("MID_MI_UI_RadialFill_SpellTimer"), "RadialFill")
eq("section MI", N.section("MI_Menu_Underline"), "Menu")
eq("section other", N.section("icon-circle"), "Other")
check("material kind", N.isMaterial("MaterialInstanceDynamic") and not N.isMaterial("Texture2D"))

-- inspector migration + checklist --------------------------------------------------
local I = require("framemage.features.inspector")
local v2 = I.migrate({
    MID_MI_Item_Selected_1 = { kind = "MaterialInstanceDynamic", count = 1 },
    MID_MI_Item_Selected_2 = { kind = "MaterialInstanceDynamic", count = 1 },
    Texture2D_44 = { kind = "Texture2D", count = 3 },
    T_Icon_Health = { kind = "Texture2D", count = 9 },
})
eq("migrate version", v2.version, 2)
eq("migrate merges copies", v2.entries.MID_MI_Item_Selected.count, 2)
check("migrate drops runtime", v2.entries.Texture2D_44 == nil)
eq("migrate idempotent", I.migrate(v2), v2)
local lines, tN, mN = I.checklist(v2.entries, function(n) return n == "T_Icon_Health" end, "Art/default/")
eq("checklist texture count", tN, 1)
eq("checklist material count", mN, 1)
local text = table.concat(lines, "\n")
check("checklist marks done", text:find("%[x%] T_Icon_Health") ~= nil, text)
check("checklist shows done tally", text:find("TEXTURES  1 done / 1", 1, true) ~= nil, text)

-- theme ----------------------------------------------------------------------------------
local T = require("framemage.core.theme")
local function near(name, a, b) check(name, math.abs(a - b) < 1e-3, string.format("got %s, want %s", a, b)) end
local c = T.parseColor("#FFFFFF")
near("hex white R", c.R, 1); near("hex white A", c.A, 1)
c = T.parseColor("#808080")
near("hex gray is linearized", c.R, 0.2159) -- sRGB 128 -> linear 0.2159
c = T.parseColor("#F00C")
near("short hex red", c.R, 1); near("short hex no green", c.G, 0)
check("3-digit hex has no alpha", T.parseColor("#F00").A == 1)
c = T.parseColor("#00000080")
near("hex alpha stays linear", c.A, 128 / 255)
c = T.parseColor({ 0.5, 0.25, 0 })
near("table is linear as-is", c.R, 0.5); near("table default alpha", c.A, 1)
check("bad hex rejected", T.parseColor("#12345") == nil)
do -- the Elven material theme loads cleanly (no flat override of the animated selection border)
    local mt, probs = T.normalize(dofile("FrameMage/Art/themes/elven/materials.lua"))
    eq("theme materials.lua has no problems", #probs, 0)
    check("no flat color on the item selection border", T.lookup(mt, "MID_MI_Item_Selected", "MI_Item_Selected") == nil)
end
do -- the selection-border dump
    local Ins = require("framemage.features.inspector")
    check("selection border shows", Ins.showsSelection({ scalars = { ["Selection Opacity"] = 1 } }))
    check("masterwork border counts", Ins.showsSelection({ scalars = { ["MW HBorder Opacity"] = 0.5 } }))
    check("plain icon", not Ins.showsSelection({ scalars = { ["Selection Opacity"] = 0 } }))
    local pl = Ins.paramLines({ scalars = { b = 2, a = 1 }, vectors = { c = { 1, 0.5, 0, 1 } } })
    eq("param lines: sorted, scalars first", pl[1]:match("%S+%s+(%S+)"), "a")
    eq("param lines: all listed", #pl, 3)
end
check("bad type rejected", T.parseColor(5) == nil)
local norm, problems = T.normalize({
    MI_Item_Selected = { vectors = { Color = "#4FA3FF" }, scalars = { Glow = 0.5, Bad = "x" },
        textures = { Mask = "mask.PNG" }, force = true },
    [3] = { },
    Broken = "nope",
})
check("normalize keeps good entry", norm.MI_Item_Selected ~= nil)
eq("normalize scalar", norm.MI_Item_Selected.scalars.Glow, 0.5)
check("normalize drops bad scalar", norm.MI_Item_Selected.scalars.Bad == nil)
eq("normalize strips .png", norm.MI_Item_Selected.textures.Mask, "mask")
eq("normalize force", norm.MI_Item_Selected.force, true)
eq("normalize reports problems", #problems, 3)
eq("lookup by key", T.lookup(norm, "MI_Item_Selected", nil), norm.MI_Item_Selected)
eq("lookup by parent", T.lookup(norm, "MID_MI_Item_Selected", "MI_Item_Selected"), norm.MI_Item_Selected)
check("lookup miss", T.lookup(norm, "X", "Y") == nil)
check("anyForce", T.anyForce(norm))

-- material sheet --------------------------------------------------------------------------
local sheet = table.concat(I.materialSheet({
    MID_MI_Item_Selected = { kind = "MaterialInstanceDynamic", count = 5, parent = "MI_Item_Selected",
        params = { scalars = { Glow = 0.5 }, vectors = { Color = { 1, 0.5, 0, 1 } }, textures = { Mask = "T_Mask" } } },
    MI_Empty = { kind = "MaterialInstanceConstant", count = 1 },
    T_Icon = { kind = "Texture2D", count = 9 },
}), "\n")
check("sheet lists effect", sheet:find("MID_MI_Item_Selected = {", 1, true) ~= nil, sheet)
check("sheet lists vector", sheet:find("Color = { 1, 0.5, 0, 1 },", 1, true) ~= nil, sheet)
check("sheet notes empty", sheet:find("no parameters read yet", 1, true) ~= nil)
check("sheet skips textures", sheet:find("T_Icon", 1, true) == nil)
-- the starter block must itself be a valid theme file
local block = sheet:match("(MID_MI_Item_Selected = {.-\n},)")
local parsed = S.parse("return {\n" .. block .. "\n}")
check("sheet block parses as theme", parsed and parsed.MID_MI_Item_Selected.scalars.Glow == 0.5, block)

-- legend -------------------------------------------------------------------------------------
local Lg = require("framemage.editor.legend")
eq("cap PgDn", Lg.cap("PageDown").text, "PgDn"); check("cap PgDn wide", Lg.cap("PageDown").wide)
eq("cap bracket", Lg.cap("LeftBracket").text, "["); check("cap bracket narrow", not Lg.cap("LeftBracket").wide)
eq("cap mouse", Lg.cap("LeftMouseButton").mouse, "left")
local cc = Lg.caps("CTRL+PageDown")
eq("caps modifier first", cc[1].text, "Ctrl"); eq("caps key second", cc[2].text, "PgDn")
local defaultsT = require("framemage.defaults")
local rows = Lg.rows(function(s) return defaultsT.keys[s] end, defaultsT.keys.bigModifier)
local function find(list, label)
    for _, r in ipairs(list) do if r.label == label then return r end end
end
local labels, headers = {}, {}
for _, r in ipairs(rows) do
    if r.header then headers[#headers + 1] = r.header else labels[#labels + 1] = r.label end
end
local joined = table.concat(labels, "|")
eq("legend sections", table.concat(headers, ","), "Select,Move,Change,Editor")
eq("legend starts with a heading", rows[1].header, "Select")
eq("legend select row is mouse", rows[2].alts[1][1].mouse, "left")
check("legend excludes dump", not joined:find("Dump", 1, true))
local nudgeRow = find(rows, "Nudge  (hold Shift: further)")
check("arrows merged into one row", nudgeRow ~= nil, joined)
eq("arrows cap", nudgeRow.alts[1][1].text, "Arrows")
local sib = find(rows, "Neighboring part")
eq("shared Ctrl shown once", #sib.prefix, 1); eq("shared prefix is Ctrl", sib.prefix[1].text, "Ctrl")
eq("then PgUp / PgDn", sib.alts[1][1].text, "PgUp"); eq("alt 2", sib.alts[2][1].text, "PgDn")
local pn = find(rows, "Previous / next")
eq("no prefix without modifiers", #pn.prefix, 0)
local pre, alt = Lg.collapse({ { { text = "Ctrl" }, { text = "A" } }, { { text = "Shift" }, { text = "B" } } })
eq("different modifiers not merged", #pre, 0); eq("kept as two groups", #alt, 2)
local rebound = Lg.rows(function(s) if s == "left" then return "A" end return defaultsT.keys[s] end, "SHIFT")
local nudgeKeys = find(rebound, "Nudge")
check("rebound arrows listed per key", nudgeKeys ~= nil and nudgeKeys.alts[1][1].text == "A")

-- legend: slide, ease, clamp ------------------------------------------------------------------------
local hOpen, aOpen, oOpen = Lg.slide(0, 300)
eq("open: full height", hOpen, 300); eq("open: chevron down", aOpen, 0); eq("open: opaque", oOpen, 1)
local hShut, aShut = Lg.slide(1, 300)
local _, _, oShut = Lg.slide(1, 300)
eq("closed: no height", hShut, 0); eq("closed: chevron sideways", aShut, -90); eq("closed: faded out", oShut, 0)
near("half way", (Lg.slide(0.5, 300)), 150)
eq("ease start", Lg.ease(0), 0); eq("ease end", Lg.ease(1), 1); near("ease middle", Lg.ease(0.5), 0.5)
check("ease is gentle at the start", Lg.ease(0.1) < 0.1)
eq("marquee: a name that fits stays put", Lg.marquee(3, 0, 14, 1.2), 0)
eq("marquee: rests at the start", Lg.marquee(0.5, 10, 10, 1), 0)
near("marquee: reaches the end", Lg.marquee(2.0, 10, 10, 1), -10)
near("marquee: rests at the end", Lg.marquee(2.5, 10, 10, 1), -10)
near("marquee: glides back", Lg.marquee(4.0, 10, 10, 1), 0)
check("marquee: half way while gliding", math.abs(Lg.marquee(1.5, 10, 10, 1) + 5) < 0.01)
near("marquee: repeats", Lg.marquee(4.5, 10, 10, 1), Lg.marquee(0.5, 10, 10, 1))
local cx1, cy1 = Lg.clamp(-50, 2000, 1920, 1080, 80, 28)
eq("clamp left", cx1, 0); eq("clamp bottom keeps title", cy1, 1052)
local cx2 = Lg.clamp(1900, 10, 1920, 1080, 80, 28)
eq("clamp right keeps title", cx2, 1840)
check("legend lists its own toggle", find(rows, "Show / hide this list") ~= nil)

-- banner ------------------------------------------------------------------------------------------
local Bn = require("framemage.editor.banner")
local bs = { bannerGap = 10, bannerFallbackTop = 120 }
eq("banner below compass", Bn.topFor(84, bs), 94)
eq("banner fallback without compass", Bn.topFor(nil, bs), 120)
eq("banner ignores absurd compass", Bn.topFor(900, bs), 120)

-- editor: element filter, drag, stick, title bar ------------------------------------------------------
local Ed = require("framemage.features.editor")
local ignore = defaultsT.editor.ignoreClasses
check("input icon is an atom", Ed.isAtom("WBP_DomInputIconWidget_C", ignore))
check("text wrapper is an atom", Ed.isAtom("WBP_DomTextBlock_C", ignore))
check("tooltip is an atom", Ed.isAtom("WBP_Inventory_Tooltip_C", ignore))
check("compass is not an atom", not Ed.isAtom("WBP_HUD_Compass_C", ignore))
check("hidden panel skips Compass Marker", Ed.skipHidden("Compass Marker", defaultsT.editor.hiddenSkip))
check("hidden panel skips Composite Variable Menu (any case)", Ed.skipHidden("composite variable menu", defaultsT.editor.hiddenSkip))
check("hidden panel keeps the rest", not Ed.skipHidden("Lore Popup Main Panel", defaultsT.editor.hiddenSkip))
do
    local E = defaultsT.editor
    check("hidden panel skips reticles", Ed.skipHidden("Additive Reticle Hunter Sense", E.hiddenSkip, "WBP_AdditiveReticle_HuntersSense_C", E.hiddenSkipClasses))
    check("hidden panel skips durability bars", Ed.skipHidden("Durability Bar", E.hiddenSkip, "WBP_Inventory_DurabilityBar_C", E.hiddenSkipClasses))
    check("hidden panel skips inventory pieces", Ed.skipHidden("Equipment Bar", E.hiddenSkip, "WBP_Inventory_EquipmentBar_C", E.hiddenSkipClasses)
        and Ed.skipHidden("Weight Bar", E.hiddenSkip, "WBP_Inventory_WeightBar_C", E.hiddenSkipClasses))
    check("hidden panel keeps other classes", not Ed.skipHidden("Lore Popup Main Panel", E.hiddenSkip, "WBP_Panel_LorePopup_C", E.hiddenSkipClasses))
end
check("build bar is not an atom", not Ed.isAtom("WBP_Building_Hotbar_C", ignore))
check("key entry is an atom", Ed.isAtom("WBP_InputLegend_Contextual_Entry_C", ignore, defaultsT.editor.forceSplit))
check("world legend (key hints + menu shortcuts) is not an atom",
    not Ed.isAtom("WBP_InputLegend_World_C", ignore, defaultsT.editor.forceSplit))
check("every forced split class survives the ignore list", (function()
    for cls in pairs(defaultsT.editor.forceSplit) do
        if Ed.isAtom(cls, ignore, defaultsT.editor.forceSplit) then return false end
    end
    return true
end)())
eq("snap nearest left edge", Ed.snapNearest(18, 60, 16, 0), -2)   -- 18 -> 16
eq("snap nearest right edge", Ed.snapNearest(5, 47, 16, 0), 1)     -- 47 -> 48 beats 5 -> 0
do -- an element dragged off screen is pulled back so 48 units of it show
    local fx, fy = Ed.keepVisible({ left = 3900, top = 700, right = 4100, bottom = 760 }, 1920, 1080, 48)
    eq("keep visible: pulled back from the right", fx, 1872 - 3900)
    eq("keep visible: on-screen axis untouched", fy, 0)
    local gx, gy = Ed.keepVisible({ left = -300, top = -90, right = -10, bottom = -40 }, 1920, 1080, 48)
    eq("keep visible: pulled back from the left", gx, 58)
    eq("keep visible: pulled down from the top", gy, 88)
    local hx = Ed.keepVisible({ left = 100, top = 0, right = 300, bottom = 10 }, 1920, 1080, 48)
    eq("keep visible: on screen stays", hx, 0)
end
eq("snap nearest with origin", Ed.snapNearest(963, 1000, 16, 960), -3)
eq("stick deadzone", Ed.stickMove(0.15, 0.2, 700, 0.016), 0)
near("stick full tilt", Ed.stickMove(1, 0.2, 700, 0.1), 70)
check("stick left is negative", Ed.stickMove(-1, 0.2, 700, 0.1) < 0)
check("stick gentle is slow", Ed.stickMove(0.4, 0.2, 700, 0.1) < 5)
do -- inventory: the hotbar on its own, the window in our look
    local Inv = require("framemage.features.inventory")
    -- window anchored top-left at (40, 60), alignment 0: the hotbar sits 18 in and 16 down inside it
    local x, y = Inv.hotbarPosition({ X = 40, Y = 60 }, { X = 0, Y = 0 }, { X = 600, Y = 420 }, { X = 18, Y = 16 })
    eq("hotbar x: window left + its place inside", x, 58); eq("hotbar y", y, 76)
    -- window centered on its anchor (alignment 0.5): its top-left is half its size up and left of the position
    x, y = Inv.hotbarPosition({ X = 0, Y = 0 }, { X = 0.5, Y = 0.5 }, { X = 600, Y = 400 }, { X = 18, Y = 16 })
    eq("centered window: hotbar x", x, -282); eq("centered window: hotbar y", y, -184)
    -- window stretched between anchors (as the game's is): its top-left is the anchor + its left / top offset,
    -- whatever its alignment
    local stretch = { Minimum = { X = 0, Y = 0 }, Maximum = { X = 1, Y = 1 } }
    x, y = Inv.hotbarPosition({ X = 40, Y = 60 }, { X = 0.5, Y = 0.5 }, { X = 600, Y = 420 }, { X = 18, Y = 16 }, stretch)
    eq("stretched window: hotbar x", x, 58); eq("stretched window: hotbar y", y, 76)
    local wide = { Minimum = { X = 0, Y = 0.5 }, Maximum = { X = 1, Y = 0.5 } } -- stretched across, a point down
    x, y = Inv.hotbarPosition({ X = 40, Y = 60 }, { X = 0, Y = 0.5 }, { X = 600, Y = 400 }, { X = 18, Y = 16 }, wide)
    eq("mixed: stretched x", x, 58); eq("mixed: point y uses alignment", y, -124)
    -- the radial prompt, 10 right of a 400x50 hotbar, scales about the hotbar's center
    local pv = Inv.followPivot({ X = 410, Y = 5 }, { X = 40, Y = 40 }, { X = 400, Y = 50 }, { X = 0.5, Y = 0.5 })
    eq("prompt pivot x: hotbar center is 210 left of it", pv.X, -5.25); eq("prompt pivot y", pv.Y, 0.5)
    local L = require("framemage.features.layout")
    local f = L.foldEntry({ x = 3356.5, y = 828 }, { x = -3356, y = -854 })
    eq("fold: offsets add (x)", f.x, 0.5); eq("fold: offsets add (y)", f.y, -26)
    eq("fold: offsets canceling leave no entry", L.foldEntry({ x = 5 }, { x = -5 }), nil)
    eq("fold: scale carries over", L.foldEntry({ scale = 1.2 }, { x = 3 }).scale, 1.2)
    eq("fold: target's own scale wins", L.foldEntry({ scale = 1.2 }, { scale = 0.8 }).scale, 0.8)
    local Sty = require("framemage.editor.style")
    local pm = Sty.plateMargin({ 0.25, 0.35 })
    check("plates: no squashable band down the sides (end ornaments in the corners)", pm[1] == 0.25 and pm[2] == 0.5)
    -- Elven: frame drawn 64, its hairline 3.5 in; the flourish's line is 23 down its 32
    eq("flourish sits on the frame's top line", Sty.flourishTop({ frameSize = 64, flourishLine = 23 }), -19.5)
    local d = require("framemage.defaults").inventory
    check("inventory restyle on by default", d.restyle == true)
    eq("inventory window restyled", Inv.WINDOWS.WBP_Panel_Inventory_C.kind, "inventory")
    eq("chest window restyled", Inv.WINDOWS.WBP_Panel_WorldActorInventory_C.kind, "chest")
    check("inventory tab buttons keep the game's look (Storage Mage adds tabs there)", not Inv.WINDOWS.WBP_Panel_Inventory_C.tabs)
    check("Build menu tabs still get our border", Inv.WINDOWS.WBP_Panel_Building_C.tabs == true)
    eq("tab: plain border", Inv.tabLook(false, false), "plain")
    eq("inventory tab selected: brighter border", Inv.tabLook(true, false), "bright")
    eq("Build tab selected: ours hidden for the game's animated one", Inv.tabLook(true, true), "hidden")
    eq("Build tab not selected: our border", Inv.tabLook(false, true), "plain")
    local iw, ih = Inv.insetSize(62, 32, { 9, -1 })
    eq("tab border inset to the visible tile (w)", iw, 53); eq("tab border a little taller (h)", ih, 33)
    local op = Inv.offsetPadding({ 0, 2 })
    eq("2 lower: 4 padding on top", op.Top, 4); eq("nothing below", op.Bottom, 0); eq("not sideways", op.Left, 0)
    op = Inv.offsetPadding({ -3, -1 })
    eq("left: padding on the right", op.Right, 6); eq("up: padding below", op.Bottom, 2)
    iw, ih = Inv.insetSize(40, 40, nil)
    eq("no inset: tile size kept", iw, 40); eq("no inset (h)", ih, 40)
    iw = Inv.insetSize(5, 5, { 6, 3 })
    eq("inset never collapses the border", iw, 4)
    -- a window with no background: ours round its contents (title 100..500 x 40..90, body 80..520 x 100..400)
    local bx = Inv.paddedBounds({ { left = 100, top = 40, right = 500, bottom = 90 },
        { left = 80, top = 100, right = 520, bottom = 400 } }, { left = 50, top = 20 }, 24)
    eq("bare window box x", bx.x, 6); eq("bare window box y", bx.y, -4)
    eq("bare window box w", bx.w, 488); eq("bare window box h", bx.h, 408)
    eq("nothing to measure: no box", Inv.paddedBounds({}, { left = 0, top = 0 }, 24), nil)
    check("bare box: same box isn't a change", not Inv.boxChanged({ x = 0, y = 0, w = 100, h = 50 }, { x = 0.5, y = 0, w = 100, h = 50.5 }))
    check("bare box: grown box is a change", Inv.boxChanged({ x = 0, y = 0, w = 685, h = 103 }, { x = 0, y = 0, w = 685, h = 600 }))
    check("bare box: first box is a change", Inv.boxChanged(nil, { x = 0, y = 0, w = 1, h = 1 }))
    check("Enchanting gets a window of ours", Inv.BARE.WBP_Enchanting_MainPanel_C ~= nil)
    local ch = Inv.WINDOWS.WBP_OpenedChat_C
    check("open chat restyled, its background never touched", ch ~= nil and ch.ownStone == true and ch.bg == "BackgroundImage")
    check("open chat: its contents named (no PanelContent)", ch ~= nil and ch.content == "VerticalBox_27")
    check("open chat: the send box gets the light border", ch ~= nil and ch.fields and ch.fields[1] == "MessageSendBorder")
    check("open chat: contents pulled in from the frame", ch ~= nil and ch.contentPad and ch.contentPad[4] >= 10)
    check("open chat: the send box clears the corner plates",
        ch ~= nil and ch.contentPad and ch.contentPad[1] >= 30 and ch.contentPad[3] >= 30)
    local ap = Inv.addPadding({ Left = 2, Top = 0, Right = 0, Bottom = 4 }, { 12, 12, 12, 12 })
    eq("padding added (left)", ap.Left, 14); eq("padding added (bottom)", ap.Bottom, 16)
    eq("no extra: padding kept", Inv.addPadding({ Left = 2, Top = 0, Right = 0, Bottom = 4 }, nil).Left, 2)
    local lp = Inv.WINDOWS.WBP_Panel_LorePopup_C
    check("lore popup restyled, its own background layer named", lp ~= nil and lp.ownStone == true and lp.bg == "Image_48")
    local bp = Inv.WINDOWS.WBP_Panel_Building_C
    check("Build panel restyled, its background never touched", bp ~= nil and bp.kind == "building" and bp.ownStone == true)
    check("Build panel's category tabs get our border", bp ~= nil and bp.tabs == true)
    local thm = dofile("FrameMage/Art/themes/elven/theme.lua")
    check("theme button rim art", thm.rimArt and io.open("FrameMage/Art/themes/elven/ui/" .. thm.rimArt.off) ~= nil
        and io.open("FrameMage/Art/themes/elven/ui/" .. thm.rimArt.on) ~= nil)
    check("inventory: stone on the game's own background", not Inv.WINDOWS.WBP_Panel_Inventory_C.ownStone)
    check("chest: its background never touched (own stone layer)", Inv.WINDOWS.WBP_Panel_WorldActorInventory_C.ownStone == true)
    local cr = Inv.WINDOWS.WBP_Panel_C
    check("crafting window restyled, its background never touched", cr ~= nil and cr.kind == "crafting" and cr.ownStone == true)
    check("crafting has the flourish (its title banner is inside, below the top line)", cr ~= nil and cr.flourish ~= false)
    local pr = Inv.WINDOWS.WBP_Panel_Processing_C
    check("processing station panel restyled, its background never touched", pr ~= nil and pr.ownStone == true)
    check("processing station panel has the flourish", pr ~= nil and pr.flourish ~= false)
    check("only the chest's checkboxes are dressed", Inv.WINDOWS.WBP_Panel_WorldActorInventory_C.checks == true and not cr.checks)
    local St2 = require("framemage.editor.style")
    -- tooltip flourishes: line row 23 of 32 onto lines 3 in from the edge; flipped, the same padding at the bottom
    eq("tip flourish padding", St2.flourishPad({ flourishLine = 23 }, 3), -20)
    eq("tip flourish padding, drawn at half size", St2.flourishPad({ flourishLine = 46 }, 3, 0.5), -20)
    eq("frame line: Elven's hairline", St2.frameLine({ frameSize = 64 }), 3.5)
    eq("frame line: a wide frame's own", St2.frameLine({ frameSize = 128, frameLine = 9 }), 9)
    eq("wide frame's flourish sits on its center line", St2.flourishTop({ frameSize = 128, frameLine = 9, flourishLine = 46 }), -37)
    local inset = { Left = 7, Top = 8, Right = 6, Bottom = 8 }
    eq("frame inset kept", St2.framePadding(inset, {}).Top, 8)
    eq("panel padding: the theme's", St2.panelPadding(nil, { panelPad = { 16, 14, 16, 14 } })[1], 16)
    eq("panel padding: a panel's own, plus room for a wide border", St2.panelPadding({ 12, 10, 12, 10 }, { framePadExtra = 18 })[2], 28)
    eq("panel padding: a panel's own, unchanged by Elven", St2.panelPadding({ 12, 10, 12, 10 }, {})[3], 12)
    eq("wide frame runs to the window's edge", St2.framePadding(inset, { frameToEdge = true }).Left, 0)
    eq("frame pushed further out", St2.framePadding(inset, { frameToEdge = true, frameOutset = 3 }).Right, -3)
    local fbx = Inv.frameBox({ x = 10, y = 20, w = 100, h = 50 }, 4)
    check("bare window frame grown outward", fbx.x == 6 and fbx.y == 16 and fbx.w == 108 and fbx.h == 58)
    for _, theme in ipairs({ "warrior", "ranger", "wizard" }) do
        local t = dofile("FrameMage/Art/themes/" .. theme .. "/theme.lua")
        check(theme .. ": wide frame round the window, edges tiled", t.frameToEdge == true and t.frameOutset == 20 and t.frameSize == 256 and t.frameDraw == "border")
        check(theme .. ": small flourish on tooltips", t.tipFlourishScale == 0.5)
    end
    eq("tooltip panel restyled", Inv.TOOLTIP, "WBP_Panel_Tooltip_C")
    check("theme tooltip band art", io.open("FrameMage/Art/themes/elven/ui/"
        .. dofile("FrameMage/Art/themes/elven/theme.lua").tipArt) ~= nil)
    eq("checkbox: off", St2.checkState(false, false), "off"); eq("checkbox: off, hovered", St2.checkState(false, true), "offHover")
    eq("checkbox: on", St2.checkState(true, false), "on"); eq("checkbox: on, hovered", St2.checkState(true, true), "onHover")
    local th = dofile("FrameMage/Art/themes/elven/theme.lua")
    for _, k in ipairs({ "off", "offHover", "on", "onHover" }) do
        local f = th.checkBoxArt and th.checkBoxArt[k]
        check("theme checkbox art " .. k, f ~= nil and io.open("FrameMage/Art/themes/elven/ui/" .. f) ~= nil)
    end
    check("theme flourish art", io.open("FrameMage/Art/themes/elven/ui/" .. th.flourishArt) ~= nil)
    do -- class themes: their own theme.lua (Warrior red, Ranger green) and their own art under Elven's names
        local wt = dofile("FrameMage/Art/themes/warrior/theme.lua")
        check("warrior theme: red highlight", wt.gold[1] > 0.5 and wt.gold[2] < 0.3)
        local rt = dofile("FrameMage/Art/themes/ranger/theme.lua")
        check("ranger theme: green highlight", rt.gold[2] > 0.4 and rt.gold[1] < 0.4)
        for _, theme in ipairs({ "warrior", "ranger" }) do
            for _, f in ipairs({ "panel_frame.png", "panel_flourish.png", "title_line.png", "tip_band.png", "button_rim.png",
                "button_rim_on.png", "check_box.png", "check_box_on.png", "check_mark.png", "keycap.png" }) do
                check(theme .. " art " .. f, io.open("FrameMage/Art/themes/" .. theme .. "/ui/" .. f) ~= nil)
            end
        end
    end
    check("hotbar separate by default", d.separateHotbar == true)
    check("equipped glow on by default", d.equippedGlow == true)
    eq("equipped: the crafting selection effect on", Inv.equippedEffect(true, false), 1)
    eq("still equipped: kept on", Inv.equippedEffect(true, true), 1)
    eq("no longer equipped: ours switched off", Inv.equippedEffect(false, true), 0)
    eq("never ours: left to the game", Inv.equippedEffect(false, false), nil)
    eq("item slots watched", Inv.SLOT, "WBP_Inventory_ItemSlot_C")
    eq("fade: opacities multiply", Inv.combinedOpacity({ 0.5, 0.5 }), 0.25)
    eq("fade: nothing fading", Inv.combinedOpacity({}), 1)
    eq("fade: never above full", Inv.combinedOpacity({ 2 }), 1)
    -- opening: the tabs are in (1.0) while the background still fades and zooms (0.4, 0.97): follow the background
    local o, sc = Inv.followAnimation({ 1.0, 0.4 }, { 1.0, 0.97 })
    eq("follow: the lower fade", o, 0.4); eq("follow: the smaller zoom", sc, 0.97)
    -- a 600x400 window centered at (300, 200); the hotbar row at its top (20..580, 10..70)
    local pv = Inv.pivotAt({ X = 300, Y = 200 }, { left = 20, top = 10, right = 580, bottom = 70 })
    eq("zoom pivot x: the window's center", pv.X, 0.5); eq("zoom pivot y: far below the row", pv.Y, 190 / 60)
    o, sc = Inv.followAnimation({}, {})
    eq("follow: nothing animating", o, 1); eq("follow: full size", sc, 1)
end
local Fr = require("framemage.editor.frame")
local fs = { frameCorner = 3, titleGap = 3, titleMinTop = 6 }
local bx, by = Fr.barPosition({ left = 100, top = 200, right = 300, bottom = 260 }, 26, fs)
eq("bar left edge", bx, 97); eq("bar above the frame", by, 168)
local _, by2 = Fr.barPosition({ left = 100, top = 10, right = 300, bottom = 60 }, 26, fs)
eq("bar below when no room above", by2, 66)
local Kc = require("framemage.core.keys")
local chord = Kc.parse("Gamepad_LeftThumbstick&Gamepad_RightThumbstick")
eq("chord keys", #chord.chord, 2); eq("chord second", chord.chord[2], "Gamepad_RightThumbstick")
check("gamepad key", Kc.isGamepad("Gamepad_FaceButton_Bottom") and not Kc.isGamepad("PageDown"))
local Lg2 = require("framemage.editor.legend")
local padRows = Lg2.rows(function(s) return defaultsT.keys[s] end, "SHIFT", "gamepad")
eq("pad legend heading", padRows[1].header, "Select")
eq("pad legend first keys", padRows[2].alts[1][1].text, "LB")
local closeRow = padRows[#padRows]
eq("pad close is both sticks", #closeRow.alts[1], 2); eq("pad close cap", closeRow.alts[1][1].text, "LS")
local kbRows = Lg2.rows(function(s) return defaultsT.keys[s] end, "SHIFT", "keyboard")
local dragRow
for _, r in ipairs(kbRows) do if r.label == "Drag a title bar" then dragRow = r end end
check("mouse drag row", dragRow ~= nil and dragRow.alts[1][1].mouse == "left")
local P2 = require("framemage.editor.picker")
local kept = P2.withoutAtoms({ { cls = "WBP_DomInputIconWidget_C" }, { cls = "WBP_Building_Hotbar_C" } },
    function(c) return Ed.isAtom(c, ignore) end)
eq("picker drops atoms", #kept, 1)
eq("picker keeps atoms when alone", #P2.withoutAtoms({ { cls = "WBP_DomInputIconWidget_C" } },
    function(c) return Ed.isAtom(c, ignore) end), 1)

-- grid axes ------------------------------------------------------------------------------------
local Gr = require("framemage.features.grid")
local segs = Gr.axisSegments(960, 540, 1920, 1080, 4, 2)
eq("4 arms x 4 segments", #segs, 16)
eq("right arm starts at center", segs[1].x, 960); eq("right arm segment length", segs[1].w, 240)
eq("left arm ends at center", segs[5].x + segs[5].w, 960); eq("left arm first seg nearest center", segs[5].x, 720)
eq("down arm", segs[9].y, 540); eq("up arm first seg ends at center", segs[13].y + segs[13].h, 540)
local gs = { centerFade = 0.7, centerWaves = 2, centerMinLevel = 0.35 }
local l0 = Gr.axisLevel(0, 0, gs)
near("pulse at center at phase 0", l0, 1)
local lEdge = Gr.axisLevel(1, 0, gs)
near("edge dimmer (gradient)", lEdge, 0.3)
check("pulse moves outward", Gr.axisLevel(0.25, 0.5, gs) > Gr.axisLevel(0.25, 0, gs))

-- share ------------------------------------------------------------------------------------------
local Sh = require("framemage.features.share")
local exported = Sh.encode("combat", { ["WBP_HUD/Compass"] = { x = 12, y = -4, hidden = true } }, "2026-11-07")
check("export has header", exported:find("Frame Mage layout: combat (1 elements)", 1, true) ~= nil)
local imported, ierr = Sh.decode(exported)
check("roundtrip import", imported ~= nil, ierr)
eq("import x", imported.elements["WBP_HUD/Compass"].x, 12)
eq("import profile name", imported.profile, "combat")
local bad, _, dropped = Sh.decode([[return { framemage = "layout", format = 1, elements = {
    ok = { x = 5, scale = 99, opacity = -1, hidden = "yes", evil = "x" }, [5] = { x = 1 } } }]])
eq("import keeps valid field", bad.elements.ok.x, 5)
check("import drops out-of-range scale", bad.elements.ok.scale == nil)
check("import drops bad opacity", bad.elements.ok.opacity == nil)
check("import drops non-bool hidden", bad.elements.ok.hidden == nil)
check("import drops unknown field", bad.elements.ok.evil == nil)
eq("import reports drops", #dropped, 5)
check("import rejects code", Sh.decode('return { framemage = "layout", format = 1, elements = os.exit() }') == nil)
check("import rejects other files", Sh.decode("return { hello = 1 }") == nil)
check("import rejects newer format", Sh.decode('return { framemage = "layout", format = 2, elements = {} }') == nil)
eq("import name adds suffix", Sh.importFileName(" my layout "), "my layout.framemage.txt")
eq("import name keeps .txt", Sh.importFileName("friend.txt"), "friend.txt")
check("import name refuses folders", Sh.importFileName("../config/settings") == nil)
check("import name refuses drive", Sh.importFileName("C:evil") == nil)

-- celebrate ----------------------------------------------------------------------------------------
local Ce = require("framemage.features.celebrate")
do
    local war = Ce.colors({ number = { 1, 0.24, 0.16 }, glow = { 1, 0.16, 0.08 } }, { { 1, 1, 1 } })
    check("celebration: a theme's own number and glow", war.number[2] == 0.24 and war.glow[2] == 0.16)
    check("celebration: what a theme leaves out is gold", war.title == Ce.GOLD.title and war.outline == Ce.GOLD.outline)
    check("celebration: sparks from the settings' palette unless the theme has its own", war.sparks[1][1] == 1)
    local gold = Ce.colors(nil, { { 0, 0, 0 } })
    check("celebration: no theme colors is all gold", gold.number == Ce.GOLD.number and gold.sparks[1][1] == 0)
    local themeFile = io.open("FrameMage/Art/themes/warrior/theme.lua"):read("*a")
    check("celebration: the Warrior theme has red celebration colors", themeFile:find("celebrate = {", 1, true) ~= nil)
end
local cs = defaultsT.celebrate
local r1, r2 = Ce.rng(42), Ce.rng(42)
eq("rng deterministic", r1(), r2())
local rr3 = Ce.rng(5)
local inRange = true
for _ = 1, 200 do local v = rr3(10, 20); if v < 10 or v > 20 then inRange = false end end
check("rng range", inRange)
near("back starts at 0", Ce.easeOutBack(0), 0); near("back ends at 1", Ce.easeOutBack(1), 1)
local peak = 0
for i = 0, 100 do peak = math.max(peak, Ce.easeOutBack(i / 100)) end
check("back overshoots a little", peak > 1.02 and peak < 1.1, peak)
local minScale = 99
for i = 0, 100 do minScale = math.min(minScale, Ce.timeline(i / 100 * cs.zoomTime, cs).numberScale) end
check("number never shrinks below 85%", minScale > 0.85, minScale)
local plan = Ce.plan(cs, Ce.rng(7))
eq("plan particle count", #plan, cs.bursts * cs.perBurst)
eq("first burst crowns the number", plan[1].x0, 0)
check("bursts staggered", plan[#plan].t0 > plan[1].t0)
local p0 = { t0 = 0, life = 1.2, x0 = 0, y0 = 0, vx = 100, vy = 0 }
check("particle hidden before start", Ce.particleAt({ t0 = 1, life = 1, x0 = 0, y0 = 0, vx = 0, vy = 0 }, 0.5, 260, 1.6) == nil)
local x1, y1, f1 = Ce.particleAt(p0, 0.5, 260, 1.6)
check("particle moves out", x1 > 0)
check("gravity pulls down", y1 > 0)
check("particle fades", f1 < 1 and f1 > 0)
local xa = Ce.particleAt(p0, 0.5, 0, 1.6)
local xb = Ce.particleAt(p0, 1.0, 0, 1.6)
check("drag slows it", (xb - xa) < xa)
check("particle gone after life", Ce.particleAt(p0, 1.3, 260, 1.6) == nil)
local tl0 = Ce.timeline(0, cs)
near("number starts large", tl0.numberScale, cs.zoomFrom)
local tl1 = Ce.timeline(cs.zoomTime + 0.1, cs)
near("number settles", tl1.numberScale, 1)
near("fully visible mid-way", Ce.timeline(1.5, cs).all, 1)
check("fading at the end", Ce.timeline(cs.duration - 0.1, cs).all < 0.5)
check("done after duration", Ce.timeline(cs.duration + 0.01, cs).done)

-- key polling watchdog ------------------------------------------------------------------------------------
do
    local K = require("framemage.core.keys")
    check("keys: never polled is stalled", K.stalled(nil, 10))
    check("keys: polled just now is fine", not K.stalled(9.99, 10))
    check("keys: no poll for 4 s is stalled", K.stalled(6, 10))
end

-- ding --------------------------------------------------------------------------------------------
local Dg = require("framemage.features.ding")
local semis, cents = Dg.ratioToSemitones(2.76)
eq("bell overtone semitones", semis, 17)
check("bell overtone cents", math.abs(cents - 57.5) < 0.5, cents)
local s2, c2 = Dg.ratioToSemitones(2)
eq("octave is 12 semitones", s2, 12); near("octave has no cents", c2, 0)
near("full volume is 0 dB", Dg.volumeToDb(1), 0)
near("half volume is -6 dB", Dg.volumeToDb(0.5), -6.0206)
eq("silent floor", Dg.volumeToDb(0), -60)
near("A4 is 440 Hz", Dg.noteToHz(69), 440)
eq("default fanfare exists", select(2, Dg.tune(defaultsT.ding.sound)), defaultsT.ding.sound)
eq("unknown fanfare falls back", select(2, Dg.tune("nope")), Dg.DEFAULT)
eq("five fanfares", #Dg.ORDER, 5)
do
    local seen = 0
    for _ in pairs(Dg.TUNES) do seen = seen + 1 end
    eq("every fanfare is in the list", seen, #Dg.ORDER)
end
for _, name in ipairs(Dg.ORDER) do
    local t = Dg.TUNES[name]
    check("fanfare listed and labeled: " .. name, t ~= nil and Dg.LABELS[name] ~= nil)
    check("fanfare voice exists: " .. name, Dg.VOICES[t.voice] ~= nil)
    check("fanfare is short (0.8 to 1.6 s): " .. name, Dg.length(t) >= 0.8 and Dg.length(t) <= 1.6, Dg.length(t))
    local ordered, inRange, maxAtOnce = true, true, 0
    for i, n in ipairs(t.notes) do
        if i > 1 and n[1] < t.notes[i - 1][1] then ordered = false end
        if n[2] < 60 or n[2] > 100 or n[4] < 1 or n[4] > 127 or n[3] <= 0 then inRange = false end
        local sounding = 0 -- notes still held or releasing when this one starts
        for _, m in ipairs(t.notes) do
            if m[1] <= n[1] and m[1] + m[3] + Dg.VOICES[t.voice].releaseMs / 1000 > n[1] then sounding = sounding + 1 end
        end
        maxAtOnce = math.max(maxAtOnce, sounding)
    end
    check("fanfare notes in time order: " .. name, ordered)
    check("fanfare notes, lengths and velocities in range: " .. name, inRange)
    check("fanfare fits the synth's 16 voices: " .. name, maxAtOnce <= 16, maxAtOnce)
    check("fanfare filter rests above its lowest note: " .. name, Dg.restCutoff(t) > Dg.noteToHz(Dg.lowest(t)))
end
eq("lowest note", Dg.lowest({ notes = { { 0, 80, 1, 1 }, { 0.1, 72, 1, 1 } } }), 72)

-- replace -------------------------------------------------------------------------------------------
local Rp = require("framemage.features.replace")
local li = Rp.levelInfo(12, "Woodcutting", 50, nil)
eq("levelInfo level", li.level, 12); eq("levelInfo skill", li.skill, "Woodcutting"); eq("levelInfo max", li.maxLevel, 50)
eq("levelInfo from text", Rp.levelInfo(nil, nil, nil, "Level 37").level, 37)
check("levelInfo needs a level", Rp.levelInfo(nil, "x", 5, "no digits") == nil)
eq("levelInfo empty skill", Rp.levelInfo(3, "", nil, nil).skill, nil)
eq("level-up replacement registered", Rp.REPLACEMENTS[1].class, "WBP_LevelUpNotification_C")

-- settings panel rows ----------------------------------------------------------------------------------
do
    local O = require("framemage.core.options")
    local defaultsT = require("framemage.defaults")
    local seen = {}
    for _, row in ipairs(O.SCHEMA) do
        if row.setting then
            check("settings row has a default: " .. row.setting, O.getPath(defaultsT, row.setting) ~= nil)
        end
        if row.key then
            check("settings row key unique: " .. row.key, not seen[row.key])
            seen[row.key] = true
        end
        local tabOk = false
        for _, t in ipairs(O.TABS) do if t.id == row.tab then tabOk = true end end
        check("settings row in a known tab: " .. (row.key or row.label), tabOk)
    end
    -- layout reset: on the Look tab beside the Layout choice, and it asks before it wipes
    local reset
    for _, row in ipairs(O.SCHEMA) do if row.action == "resetLayout" then reset = row end end
    check("reset layout button on the Look tab", reset ~= nil and reset.tab == "look")
    check("Look tab still fits one page", #O.rowsOf("look") <= 12)
    check("reset layout asks first", reset ~= nil and reset.confirm == true)
    check("no switch to turn the mod off in game", (function()
        for _, row in ipairs(O.SCHEMA) do if row.setting == "enabled" then return false end end
        return true
    end)())
    check("no point color / brightness rows", (function()
        for _, row in ipairs(O.SCHEMA) do
            if row.setting == "bars.tipPaint" or row.setting == "bars.tipGain" then return false end
        end
        return true
    end)())
    check("first click: not armed", not O.isArmed(nil, reset, 10))
    check("second click in time: armed", O.isArmed({ row = reset, at = 10 }, reset, 12))
    check("too late: not armed", not O.isArmed({ row = reset, at = 10 }, reset, 10 + O.CONFIRM_SECONDS + 0.1))
    check("another button: not armed", not O.isArmed({ row = reset, at = 10 }, { action = "export" }, 11))
    eq("cycle forward", O.cycle({ "a", "b", "c" }, "b", 1), "c")
    eq("cycle wraps", O.cycle({ "a", "b", "c" }, "c", 1), "a")
    eq("cycle back wraps", O.cycle({ "a", "b", "c" }, "a", -1), "c")
    eq("step up", O.step({ min = 4, max = 64, step = 4 }, 16, 1), 20)
    eq("step clamps", O.step({ min = 4, max = 64, step = 4 }, 64, 1), 64)
    near("step no drift", O.step({ min = 0, max = 1, step = 0.05 }, 0.7, 1), 0.75)
    eq("display toggle", O.display({ type = "toggle" }, true), "On")
    eq("display choice", O.display({ type = "choice", labels = { slate = "Slate" } }, "slate"), "Slate")
    eq("display percent", O.display({ type = "slider", percent = true }, 0.75), "75%")
    eq("display px", O.display({ type = "number", suffix = " px" }, 16), "16 px")
    local t = {}
    O.setPath(t, "bars.style", "facet")
    eq("set / get path", O.getPath(t, "bars.style"), "facet")
end

-- the point's color, brightened to match the material
do
    local Bt = require("framemage.features.bars")
    local c = Bt.tipColor({ R = 0.5, G = 0.9, B = 0.0, A = 1 }, 1.35, 0.08)
    near("tip color scaled", c.R, 0.755)
    eq("tip color capped at 1", c.G, 1)
    near("tip color lifted", c.B, 0.08)
    eq("tip color plain", Bt.tipColor({ R = 0.2, G = 0.2, B = 0.2 }).R, 0.2)
end

-- key capture spec
do
    local K2 = require("framemage.core.keys")
    eq("capture spec plain", K2.specOf({}, "F9"), "F9")
    eq("capture spec with ctrl", K2.specOf({ CONTROL = true }, "F9"), "CTRL+F9")
    eq("capture spec order", K2.specOf({ SHIFT = true, CONTROL = true }, "A"), "CTRL+SHIFT+A")
    check("captured spec parses", K2.parse("CTRL+F9") ~= nil)
end

do -- vitals: even rows, percentages
    local Bv = require("framemage.features.bars")
    eq("rows in place: nothing to fix", Bv.spacingFix({ 0, 46, 92 }, 46), nil)
    local i, d = Bv.spacingFix({ 0, 46, 88 }, 46)
    check("rows: the third row pushed down 4", i == 3 and math.abs(d - 4) < 1e-6)
    local i2, d2 = Bv.spacingFix({ 0, 44, 88 }, 46)
    check("rows: the first wrong row first", i2 == 2 and math.abs(d2 - 2) < 1e-6)
    check("rate labels recognized", Bv.isRateLabel("HealthRegenValue") and Bv.isRateLabel("SpecialChargeRegenValue")
        and not Bv.isRateLabel("ValueText"))
    eq("percent: full", Bv.percentText(1, 1), "100%")
    eq("percent: rounded", Bv.percentText(0.666, 1), "67%")
    eq("percent: of what's available", Bv.percentText(0.5, 0.8), "40%")
end

do -- status effects as gauges
    local St = require("framemage.features.status")
    eq("status: an on / off effect has no ring", St.ringFill(false, 0), nil)
    eq("status: a bar's fill shows as the ring", St.ringFill(true, 0.4), 0.4)
    eq("status: clamped", St.ringFill(true, 1.7), 1)
    local sx, sy = St.slotAt(10, 100, 3, 64, 6)
    check("status: gauges stacked down from the list's top-left", sx == 10 and sy == 240)
    local function band(r) local c = St.weightColor(r, 0) return string.format("%.2f,%.2f", c.R, c.G) end
    eq("load: half full is green", band(0.50), "0.10,0.70")
    eq("load: 51% is yellow", band(0.51), "0.95,0.80")
    eq("load: 75% still yellow", band(0.75), "0.95,0.80")
    eq("load: 76% is orange", band(0.76), "1.00,0.40")
    eq("load: 91% is red", band(0.91), "0.85,0.05")
    eq("load: full is red", band(1.0), "0.85,0.05")
    eq("load from text", St.parseWeight("286/475"), 286 / 475)
    eq("load from text with spaces and decimals", St.parseWeight("500.5 / 475"), 500.5 / 475)
    eq("load from text with commas", St.parseWeight("1,200/1,000"), 1.2)
    eq("no load from other text", St.parseWeight("Weight"), nil)
    local p1, p2 = St.weightColor(1.2, 0.25), St.weightColor(1.2, 0.75)
    check("load: overloaded pulses (bright, then dark)", p1.R > 0.9 and p2.R < 0.5 and p1.G < 0.1)
    local u = St.unique({ { k = "a" }, { k = "b" }, { k = "a" }, { k = nil }, { k = nil } }, function(r) return r.k end)
    eq("status: a repeated effect shown once (unknown ones all kept)", #u, 4)
    local g = St.grow(St.grow(nil, { left = 10, top = 50, right = 74, bottom = 114 }), { left = 22, top = 6, right = 62, bottom = 46 })
    check("status: the gauges' bounds take in every gauge", g.left == 10 and g.top == 6 and g.right == 74 and g.bottom == 114)
    local rt = St.rowTops(200, 2, { { w = 100, h = 20 }, { w = 100, h = 30 } })
    check("status: the game's rows stacked down its list", rt[1].top == 200 and rt[2].top == 240 and rt[2].h == 60 and rt[1].w == 200)
    local sx2, sy2 = St.rowShift(150, 300, 100, 200, 200, 40, 2)
    check("status: a row's shift puts its middle on the gauge (in list units)", sx2 == -25 and sy2 == 40)
    local tops = St.stackTops(100, { 64, 40, 40 }, 4, false)
    check("status: rows stacked by their own height", tops[1] == 100 and tops[2] == 168 and tops[3] == 212)
    eq("list edge: top stays", St.stableEdge({ top = 100, bottom = 200, n = 2 }, { top = 100, bottom = 150, n = 1 }), "top")
    eq("list edge: bottom stays", St.stableEdge({ top = 100, bottom = 200, n = 2 }, { top = 150, bottom = 200, n = 1 }), "bottom")
    eq("list edge: same count tells nothing", St.stableEdge({ top = 100, bottom = 200, n = 2 }, { top = 150, bottom = 200, n = 2 }), nil)
    eq("anchor: a bottom-pinned list's last row top", St.anchorY("bottom", 100, 200, 50), 150)
    eq("anchor: two rows or one, the same place", St.anchorY("bottom", 150, 200, 50), 150)
    eq("anchor: a top-pinned list's top", St.anchorY("top", 100, 200, 50), 100)
    local utops = St.stackTops(100, { 64, 40 }, 4, true)
    check("status: growing up, the first stays and the next sits above it", utops[1] == 100 and utops[2] == 56)
    local _, uy = St.slotAt(10, 100, 3, 64, 6, true)
    eq("status: growing up, the third sits two steps above the first", uy, -40)
    local rows = { { id = "shelter", timed = false }, { id = "cosy", timed = true }, { id = "full", timed = true } }
    local function ids(t) local o = {} for _, r in ipairs(t) do o[#o + 1] = r.id end return table.concat(o, ",") end
    eq("status: timed first", ids(St.ordered(rows, "timed")), "cosy,full,shelter")
    eq("status: lasting first", ids(St.ordered(rows, "lasting")), "shelter,cosy,full")
    eq("status: game order", ids(St.ordered(rows, "game")), "shelter,cosy,full")
end

do -- survival gauges stacked beside the vitals
    local Sv = require("framemage.features.survival")
    local pos, sc = Sv.stack({ left = 0, top = 100, right = 300, bottom = 238 }, 68, 92, 3, 10, 1)
    check("stacked: the gauges share the bars' height", math.abs(sc - 46 / 92) < 1e-6)
    check("stacked: a column just right of the bars", pos[1].x == 310 and pos[3].x == 310)
    check("stacked: each centered in its share", math.abs(pos[1].y - 100) < 1e-6 and math.abs(pos[2].y - 146) < 1e-6)
    local _, big = Sv.stack({ left = 0, top = 0, right = 10, bottom = 900 }, 68, 92, 3, 10, 1)
    eq("stacked: never larger than the game draws them", big, 1)
    local col = Sv.column({ { left = 0, top = 100, right = 300, bottom = 146 }, { left = 0, top = 146, right = 310, bottom = 192 } }, 40, 28)
    check("stacked: a column past the furthest bar", col[1].x == 338 and col[2].x == 338)
    check("stacked: each ring centered on its bar", col[1].y == 103 and col[2].y == 149)
    local bars3 = { { left = 0, top = 100, right = 300, bottom = 146 }, { left = 0, top = 146, right = 300, bottom = 192 },
        { left = 0, top = 192, right = 300, bottom = 238 } }
    local big3 = Sv.column(bars3, 80, 28, 4)
    eq("big rings: spread to their size", big3[2].y - big3[1].y, 84)
    check("big rings: the middle one still on the middle bar", math.abs(big3[2].y + 40 - 169) < 1e-6)
    eq("small rings: level with their bars", Sv.column(bars3, 40, 28, 4)[2].y - Sv.column(bars3, 40, 28, 4)[1].y, 46)
    local tx, ty = Sv.translation(50, 60, 150, 20, 2)
    check("stacked: translation in the widget's own units", tx == 50 and ty == -20)
    eq("Survival gauges choice offered", (function()
        local O = require("framemage.core.options")
        for _, r in ipairs(O.SCHEMA) do if r.key == "SurvivalLayout" then return r.setting end end
    end)(), "bars.survivalLayout")
end

do
    local m = C.americanize({ bars = { durabilityColours = true }, grid = { centreAlpha = 0.4, size = 8 } })
    check("old British setting names read under the American ones", m.bars.durabilityColors == true
        and m.grid.centerAlpha == 0.4 and m.grid.size == 8 and m.bars.durabilityColours == nil)
end
do
    local R = require("framemage.core.reload")
    eq("reload: our names get the run's suffix", R.runName("FM_GaugeRim_3", "ab12"), "FM_GaugeRim_3_rab12")
    eq("reload: the game's names are left alone", R.runName("WeightBar", "ab12"), "WeightBar")
    check("reload: ours by prefix", R.isOurs("FM_WeightFrame_2_rab12") and not R.isOurs("Overlay_371"))
end
do
    local Inv = require("framemage.features.inventory")
    eq("item tooltip moves past the frame's reach plus a gap", Inv.tipShift(20, 6, 60), 26)
    eq("no frame reach: no move", Inv.tipShift(0, 6, 60), 0)
    check("a station window gets the gap", Inv.wantsGap("processing", false) and Inv.wantsGap("chest", false))
    check("not the inventory, nor a window you placed", not Inv.wantsGap("inventory", false) and not Inv.wantsGap("crafting", true))
    eq("never more than the most it may move", Inv.tipShift(200, 6, 60), 60)
end
do
    local Th = require("framemage.core.themes")
    local v = Th.sharedValues("wizard", 3)
    check("themes: other mods get the theme and its revision", v["FrameMage.theme"] == "wizard" and v["FrameMage.themeRev"] == 3)
end
-- every feature main.lua starts can be switched off in settings.lua (it has a default) ----------------------------
do
    local src = io.open("FrameMage/Scripts/main.lua"):read("a")
    local list = src:match("local FEATURES = (%b{})")
    local defaultsT = require("framemage.defaults")
    for name in list:gmatch('"([%w_]+)"') do
        check("feature has a default switch: " .. name, defaultsT.features[name] ~= nil)
    end
    local devList = dofile("dev/features.lua")
    for _, name in ipairs(devList) do
        check("developer feature has a default switch: " .. name, defaultsT.features[name] ~= nil)
    end
end

-- example entries in empty lists (editor/examples.lua) ------------------------------------------------------------
do
    local Ex = require("framemage.editor.examples")
    local col = Ex.place(10, 20, 100, 30, 2, true, 4)
    eq("examples: a column", col[2].top, 54)
    eq("examples: same left", col[2].left, 10)
    local row = Ex.place(10, 20, 100, 30, 2, false, 4)
    eq("examples: a row", row[2].left, 114)
    local u = Ex.union(col)
    check("examples: the box round them", u.top == 20 and u.bottom == 84 and u.right == 110)
    eq("examples: none, no box", Ex.union({}), nil)
    local Rc = require("framemage.editor.recipes")
    local p = Rc.part("Fireball", "/Game/UI/T_Fire.T_Fire", 32, 32, 3)
    check("recipe part: text, picture, size, visibility", p.text == "Fireball" and p.res and p.size[1] == 32 and p.vis == 3)
    eq("recipe part: empty text left out", Rc.part("", nil, 0, 0, nil).text, nil)
    check("a recipe with text or a picture is useful", Rc.useful({ parts = { A = { text = "x" } } }))
    check("an empty recipe isn't", not Rc.useful({ parts = { A = { vis = 3 } } }))
end

-- the shared Settings panel --------------------------------------------------------------------------------
do
    local Ps = require("framemage.core.panelshared")
    local O = require("framemage.core.options")
    local P = require("settingspanel.protocol")
    local rows = Ps.rows(O.SCHEMA, false)
    local clean, notes = P.clean({ protocol = 1, mod = "FrameMage", title = "Frame Mage", tabs = O.TABS, rows = rows })
    check("Frame Mage's rows make a clean schema", clean ~= nil and #notes == 0, notes and notes[1])
    eq("every Frame Mage row kept", #clean.rows, #rows)
    local hasOpenKey, hasDev = false, false
    for _, r in ipairs(rows) do
        if r.setting == "keys.settings" then hasOpenKey = true end
        if r.dev then hasDev = true end
    end
    check("the panel's own open key isn't a Frame Mage row", not hasOpenKey)
    check("developer rows only with dev/", not hasDev)
    local withDev = Ps.rows(O.SCHEMA, true)
    check("developer rows with dev/", #withDev > #rows)
    local look = Ps.lookData({ titleArt = "title_line.png", titleSize = { 128, 32 }, ink = { 1, 1, 1 }, selectedInk = { 0, 0, 0 } },
        function(rel) if rel == "ui/plate_ornament.png" then return nil end return "/T/" .. rel end, "panel_bg_silk.png", 256, "elven")
    eq("look: the title art", look.titleArt, "/T/ui/title_line.png")
    eq("look: no ornament art", look.ornamentArt, nil)
    eq("look: lit lettering is the selected ink", look.ink[1], 0)
    eq("look: the title in the theme's ink", look.titleInk[1], 1)
    check("a click on the panel's box", Ps.inBox("10,20,300,400", 100, 100))
    check("a click beside it", not Ps.inBox("10,20,300,400", 5, 100))
    check("no box: nothing on it", not Ps.inBox(nil, 5, 5))
    -- every shipping file can find the panel: Frame Mage's code requires it only through core/panelshared
    local sp, sf = dofile("../../shared/settingspanel/tests/run_tests.lua")
    passes, failures = passes + sp, failures + sf
end

print(string.format("%d passed, %d failed", passes, failures))
os.exit(failures == 0 and 0 or 1)
