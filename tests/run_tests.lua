-- Unit tests for the engine-independent parts. Run from the repo root with Lua 5.4:
--   lua tests/run_tests.lua
package.path = "Forgeframe/Scripts/?.lua;" .. package.path
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
local S = require("forgeframe.core.serialize")
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
local C = require("forgeframe.core.config")
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
local K = require("forgeframe.core.keys")
local p = K.parse("ctrl+shift+F9")
eq("parse key", p.key, "F9")
eq("parse mods", table.concat(p.mods, ","), "CONTROL,SHIFT")
eq("parse plain", #K.parse("PAGE_DOWN").mods, 0)
check("parse bad modifier", K.parse("HYPER+F1") == nil)
check("parse empty", K.parse("") == nil)

-- widgets pure helpers ---------------------------------------------------------
local W = require("forgeframe.core.widgets")
eq("strip _C", W.stripClassSuffix("WBP_HUD_C"), "WBP_HUD")
eq("normalise instance", W.normaliseName("WBP_BuffEntry_C_2147482", "WBP_BuffEntry_C"), "WBP_BuffEntry*")
eq("keep designer name", W.normaliseName("HealthBar", "WBP_Bar_C"), "HealthBar")
eq("keep numbered designer name", W.normaliseName("Image_12", "Image"), "Image_12")
check("transient is instance", W.isInstanceFullName("WBP_HUD_C /Engine/Transient.GameEngine_0:BP_GI_C_0.WBP_HUD_C_0"))
check("template is not", not W.isInstanceFullName("WBP_Bar_C /Game/UI/WBP_HUD.WBP_HUD_C:WidgetTree.Bar"))
check("CDO is not", not W.isInstanceFullName("WBP_HUD_C /Engine/Transient.Default__WBP_HUD_C"))

-- layout.resolve -----------------------------------------------------------------
local L = require("forgeframe.features.layout")
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
local N0 = require("forgeframe.core.names")
eq("pretty nested", N0.pretty("WBP_HUD_RootWidget/HUD_Survival/WBP_SurvivalCore_Upkeep_Hydration"), "Survival Core Upkeep Hydration")
eq("pretty instance", N0.pretty("WBP_HUD/WBP_BuffEntry*"), "Buff Entry")
eq("pretty acronym", N0.pretty("WBP_HUD/HPBarText"), "HP Bar Text")
eq("pretty digits", N0.pretty("WBP_HUD/XPProgress2"), "XP Progress 2")
eq("pretty root", N0.pretty("WBP_HUD_QuestList"), "Quest List")

-- editor pure parts ------------------------------------------------------------------
local E = require("forgeframe.features.editor")
eq("banner name only", E.bannerText("WBP_HUD/WBP_QuestTracker", nil), "Quest Tracker")
eq("banner hidden", E.bannerText("WBP_HUD/Compass", { hidden = true }), "Compass  (hidden)")
eq("banner nothing", E.bannerText(nil), "Click a widget to select it")

local Geo = require("forgeframe.core.geometry")
local rr = { left = 10, top = 10, right = 10, bottom = 30 }
local g = Geo.atLeast(rr, 16)
eq("atLeast widens empty", g.right - g.left, 16); eq("atLeast centred", g.left, 2); eq("atLeast keeps tall", g.bottom - g.top, 20)
check("contains", Geo.contains({ left = 0, top = 0, right = 10, bottom = 10 }, 5, 10))
check("not contains", not Geo.contains({ left = 0, top = 0, right = 10, bottom = 10 }, 11, 5))
eq("area", Geo.area({ left = 0, top = 0, right = 4, bottom = 5 }), 20)

local F = require("forgeframe.editor.frame")
local edges, corners = F.pieces({ left = 100, top = 50, right = 200, bottom = 90 }, 1, 3, 12)
eq("4 edges", #edges, 4); eq("8 corner bars", #corners, 8)
eq("top edge above", edges[1][2], 49); eq("top edge width", edges[1][3], 100)
eq("left edge spans corners", edges[3][4], 42)
eq("corner bracket outside", corners[1][1], 97); eq("corner length", corners[1][3], 12)
eq("top-right bracket ends at edge+corner", corners[3][1] + corners[3][3], 203)
local _, tiny = F.pieces({ left = 0, top = 0, right = 4, bottom = 4 }, 1, 3, 12)
eq("brackets shrink on tiny widgets", tiny[1][3], 5)

local P = require("forgeframe.editor.picker")
local ordered = P.order({ { area = 500, depth = 1, id = "panel" }, { area = 20, depth = 3, id = "icon" },
    { area = 20, depth = 5, id = "deep" }, { area = 9000, depth = 0, id = "root" } })
eq("pick smallest first", ordered[1].id, "deep"); eq("then same-size shallower", ordered[2].id, "icon")
eq("then panel", ordered[3].id, "panel"); eq("root last", ordered[4].id, "root")
check("same spot", P.sameSpot({ x = 10, y = 10 }, { x = 14, y = 7 }, 6))
check("different spot", not P.sameSpot({ x = 10, y = 10 }, { x = 30, y = 10 }, 6))

-- grid.snapDelta -------------------------------------------------------------------
local G = require("forgeframe.features.grid")
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
local N = require("forgeframe.core.names")
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
local I = require("forgeframe.features.inspector")
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
local T = require("forgeframe.core.theme")
local function near(name, a, b) check(name, math.abs(a - b) < 1e-3, string.format("got %s, want %s", a, b)) end
local c = T.parseColor("#FFFFFF")
near("hex white R", c.R, 1); near("hex white A", c.A, 1)
c = T.parseColor("#808080")
near("hex grey is linearised", c.R, 0.2159) -- sRGB 128 -> linear 0.2159
c = T.parseColor("#F00C")
near("short hex red", c.R, 1); near("short hex no green", c.G, 0)
check("3-digit hex has no alpha", T.parseColor("#F00").A == 1)
c = T.parseColor("#00000080")
near("hex alpha stays linear", c.A, 128 / 255)
c = T.parseColor({ 0.5, 0.25, 0 })
near("table is linear as-is", c.R, 0.5); near("table default alpha", c.A, 1)
check("bad hex rejected", T.parseColor("#12345") == nil)
check("bad type rejected", T.parseColor(5) == nil)
local norm, problems = T.normalise({
    MI_Item_Selected = { vectors = { Color = "#4FA3FF" }, scalars = { Glow = 0.5, Bad = "x" },
        textures = { Mask = "mask.PNG" }, force = true },
    [3] = { },
    Broken = "nope",
})
check("normalise keeps good entry", norm.MI_Item_Selected ~= nil)
eq("normalise scalar", norm.MI_Item_Selected.scalars.Glow, 0.5)
check("normalise drops bad scalar", norm.MI_Item_Selected.scalars.Bad == nil)
eq("normalise strips .png", norm.MI_Item_Selected.textures.Mask, "mask")
eq("normalise force", norm.MI_Item_Selected.force, true)
eq("normalise reports problems", #problems, 3)
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

print(string.format("%d passed, %d failed", passes, failures))
os.exit(failures == 0 and 0 or 1)
