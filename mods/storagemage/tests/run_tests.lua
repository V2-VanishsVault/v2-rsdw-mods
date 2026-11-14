-- Unit tests for the engine-independent parts, plus a smoke test that loads main.lua with stubbed UE4SS
-- globals. Run from the repo root with Lua 5.4:
--   lua tests/run_tests.lua
package.path = "StorageMage/Scripts/?.lua;" .. package.path

local failures, passes = 0, 0
local function check(name, cond, detail)
    if cond then passes = passes + 1 else
        failures = failures + 1
        io.stderr:write("FAIL " .. name .. (detail and (": " .. tostring(detail)) or "") .. "\n")
    end
end
local function eq(name, a, b) check(name, a == b, string.format("got %s, want %s", tostring(a), tostring(b))) end
-- serialize ---------------------------------------------------------------------
local S = require("storagemage.core.serialize")
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
local C = require("storagemage.core.config")
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
local K = require("storagemage.core.keys")
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

-- objects (no engine: everything must fail soft) ---------------------------------------
local O = require("storagemage.core.objects")
check("valid(nil) is false", O.valid(nil) == false)
check("valid(junk) is false", O.valid({}) == false)
eq("get on a table", O.get({ a = 1 }, "a"), 1)
eq("get missing field", O.get(setmetatable({}, { __index = function() error("no field") end }), "x"), nil)

-- toast and net role with no engine: must fail soft (no viewport, no controller)
local T = require("storagemage.core.toast")
check("toast without an engine returns false", T.show("test") == false)
eq("net role without a player", O.netRole(), "unknown")

-- probe pure helpers ---------------------------------------------------------------------
local P = require("storagemage.features.probe")
eq("slot type 0", P.slotTypeName(0), "QuickAction")
eq("slot type 2", P.slotTypeName(2), "InventoryRunes")
eq("unknown slot type (a bag)", P.slotTypeName(12), "#12")
eq("item line", P.itemLine(3, 5, "Copper ore", "Item.Resource.Ore", { "A", "B" }),
    "  [3] 5 x Copper ore  category=Item.Resource.Ore  tags=A,B")
eq("item line no tags", P.itemLine(0, 1, "Axe", nil, {}), "  [0] 1 x Axe  category=-  tags=-")
eq("item line with asset", P.itemLine(27, 19, "Iron Ore", "Item.BuildingResource", {}, "ItemData_IronOre"),
    "  [27] 19 x Iron Ore (ItemData_IronOre)  category=Item.BuildingResource  tags=-")
local sum = P.categorySummary({ { category = "B" }, { category = "A" }, { category = "B" }, {} })
eq("summary sorted", sum[1], "  - (1)"); eq("summary counts", sum[3], "  B (2)")
do
    local cat, ncat = P.catalogLines({
        { asset = "ITEM_Ore_Iron", name = "Iron Ore", category = "Item.BuildingResource", weight = 1, stack = 50, class = "ItemData" },
        { asset = "ITEM_Gem_Jade", name = "Jade", category = "Item.BuildingResource", weight = 0.5, stack = 50, class = "ItemData" },
        { asset = "ITEM_Ore_Iron", name = "Iron Ore", category = "Item.BuildingResource", class = "ItemData" }, -- duplicate
        { asset = "ITEM_Seed_Wheat", name = "Wheat Seeds", category = "ItemFilter.Material.Seed" },
        { asset = "ITEM_Odd" },
    })
    eq("catalog category count", ncat, 3)
    eq("catalog uncategorised first", cat[1], "- (1)")
    eq("catalog dedupes and counts", cat[3], "Item.BuildingResource (2)")
    eq("catalog sorts assets in a category", cat[4], '  ITEM_Gem_Jade  "Jade"  weight=0.5  stack=50  class=ItemData')
    eq("catalog missing fields show ?", cat[7], '  ITEM_Seed_Wheat  "Wheat Seeds"  weight=?  stack=?  class=?')
    eq("catalog line count", #cat, 7)
end

-- defaults: the bag spec ---------------------------------------------------------------------
local D = require("storagemage.defaults")
-- layout: fixed, slot types 9-15, past the game's enum (user's decision, 2026-11-11) -------------------------
local L = require("storagemage.layout")
local want = { { "toolBelt", 9, 16 }, { "herbs", 10, 48 }, { "gems", 11, 24 }, { "ores", 12, 72 },
    { "seeds", 13, 64 }, { "fishing", 14, 16 }, { "runeEssence", 15, 8 } }
for _, p in ipairs(L.PAGES) do
    check("slot type " .. p.slotType .. " is past the game's enum", p.slotType > L.LAST_GAME_SLOT_TYPE)
end
eq("layout page count", #L.PAGES, #want)
for i, w in ipairs(want) do
    local p = L.PAGES[i] or {}
    eq("layout page " .. i .. " bag", p.bag, w[1])
    eq("layout page " .. i .. " slot type", p.slotType, w[2])
    eq("layout page " .. i .. " slots", p.slots, w[3])
    check("layout page " .. i .. " has a bag spec", D.bags[w[1]] ~= nil)
    check("bag " .. w[1] .. " has no slot setting", D.bags[w[1]] and D.bags[w[1]].slots == nil)
end
local ranges, total = L.slotRanges()
eq("tool belt starts after the game's 176", ranges.toolBelt.first, 176)
eq("tool belt last slot", ranges.toolBelt.last, 191)
eq("herbs first slot", ranges.herbs.first, 192)
eq("rune essence last slot", ranges.runeEssence.last, 423)
eq("total slots", total, 424)
eq("page lookup", L.page("gems").slotType, 11)
eq("page lookup missing", L.page("nope"), nil)
eq("tool belt always present", D.bags.toolBelt.always, true)
eq("carry weight default 50%", D.carryWeightPercent, 50)
do -- bag filters: every bag can match something; no item is claimed by two bags; no deleted assets
    local owner, clash = {}, nil
    for id, b in pairs(D.bags) do
        check("bag " .. id .. " has a filter", #(b.categories or {}) + #(b.items or {}) > 0)
        for _, a in ipairs(b.items or {}) do
            if owner[a] then clash = a .. " in " .. owner[a] .. " and " .. id end
            owner[a] = id
            check("no deleted asset " .. a, not a:find("_Deleted$"))
        end
    end
    eq("no item in two bags", clash, nil)
    check("coal is an ore", owner["ITEM_Resources_Coal"] == "ores")
    local tb = table.concat(D.bags.toolBelt.categories, ",")
    check("tool belt takes every tool (parent category)", tb:find("Item.Equipment.Tool", 1, true) == 1)
    check("tool belt takes torches", tb:find("ItemFilter.Type.Equipment.Tool", 1, true) ~= nil)
end
check("defaults round-trip through serialize", S.parse(S.dump(D)) ~= nil)
eq("retired probe keys are gone", (D.keys.pageTest or D.keys.moveTest), nil)

-- pagetest (T1 timeline) pure helpers ---------------------------------------------------------------------
local PT = require("storagemage.features.pagetest")
eq("snap line", PT.snapLine({ loaded = true, pages = 4, maxSlots = 176, itemSlots = 176, items = 10, json = 0 }),
    "loaded=true pages=4 maxSlots=176 itemSlots=176 items=10 json=0")
eq("snap line, no inventory", PT.snapLine(nil), "no main inventory")
check("timeline line has seconds", PT.timelineLine(1234, "poll", nil):find("^%+1%.234s  poll") ~= nil,
    PT.timelineLine(1234, "poll", nil))

-- pages (T1c: the template patch) pure helpers -------------------------------------------------------------
local PG = require("storagemage.features.pages")
local game = { { slotType = 1, numSlots = 32 }, { slotType = 2, numSlots = 32 }, { slotType = 3, numSlots = 32 },
    { slotType = 4, numSlots = 72 } }
local function withLayout(k) -- the game's pages + the first k of ours
    local t = { game[1], game[2], game[3], game[4] }
    for i = 1, k do t[#t + 1] = { slotType = L.PAGES[i].slotType, numSlots = L.PAGES[i].slots } end
    return t
end
eq("plan: game pages -> patch from 1", PG.plan(game).action .. ":" .. PG.plan(game).from, "patch:1")
eq("plan: 3 of ours -> patch from 4", PG.plan(withLayout(3)).from, 4)
eq("plan: whole layout -> done", PG.plan(withLayout(#L.PAGES)).action, "done")
local extra = withLayout(#L.PAGES); extra[#extra + 1] = { slotType = 16, numSlots = 8 }
eq("plan: a page beyond ours -> refuse", PG.plan(extra).action, "refuse")
local other = withLayout(0); other[5] = { slotType = 7, numSlots = 48 } -- RuneScape Bags' Herbs page
eq("plan: RuneScape Bags' 5th page -> refuse", PG.plan(other).action, "refuse")
local wrongSize = withLayout(0); wrongSize[5] = { slotType = 9, numSlots = 8 } -- our type, a different size
eq("plan: our slot type with the wrong size -> refuse", PG.plan(wrongSize).action, "refuse")
local bigItems = withLayout(0); bigItems[1] = { slotType = 1, numSlots = 64 } -- an inventory-size mod
eq("plan: changed game page -> refuse", PG.plan(bigItems).action, "refuse")
eq("plan: nil -> refuse", PG.plan(nil).action, "refuse")
eq("need slots, game only", PG.needSlots(game), 176)
eq("need slots, whole layout", PG.needSlots(withLayout(#L.PAGES)), 424)
-- filters: which bag an item belongs to -------------------------------------------------------------------
local FL = require("storagemage.filters")
local ord = {}
for _, p in ipairs(L.PAGES) do ord[#ord + 1] = p.bag end
eq("under: child tag", FL.under("Item.Equipment.Tool.Hatchet", "Item.Equipment.Tool"), true)
eq("under: same tag", FL.under("Item.Equipment.Tool", "Item.Equipment.Tool"), true)
eq("under: prefix but not a child", FL.under("Item.Equipment.ToolBox", "Item.Equipment.Tool"), false)
eq("under: nil", FL.under(nil, "Item.Equipment.Tool"), false)
eq("bagFor: pickaxe -> tool belt", FL.bagFor("Item.Equipment.Tool.Pickaxe", "ITEM_Pickaxe_Steel", D.bags, ord), "toolBelt")
eq("bagFor: Scarab Staff (parent category) -> tool belt", FL.bagFor("Item.Equipment.Tool", "ITEM_ScarabStaff", D.bags, ord), "toolBelt")
eq("bagFor: torch -> tool belt", FL.bagFor("ItemFilter.Type.Equipment.Tool", "ITEM_Torch", D.bags, ord), "toolBelt")
eq("bagFor: rod -> tool belt, not fishing", FL.bagFor("Item.Equipment.Tool.Fishing.Rod", "ITEM_FishingRod_Willow", D.bags, ord), "toolBelt")
eq("bagFor: bait -> fishing", FL.bagFor("Item.Equipment.Ammo.Bait.Shrimp", "ITEM_FishBait_Shrimp", D.bags, ord), "fishing")
eq("bagFor: coal -> ores (item list)", FL.bagFor("Item.BuildingResource", "ITEM_Resources_Coal", D.bags, ord), "ores")
eq("bagFor: herb -> herbs", FL.bagFor("ItemFilter.Material.BasicMaterial", "ITEM_Herb_Irit", D.bags, ord), "herbs")
eq("bagFor: ash logs -> none", FL.bagFor("ItemFilter.Material.BasicMaterial", "ITEM_Resources_Wood_Ash", D.bags, ord), nil)
eq("bagFor: a sword -> none", FL.bagFor("Item.Equipment.Weapon.1H.Sword", "ITEM_Sword", D.bags, ord), nil)
eq("bagFor: only active bags", FL.bagFor("Item.BuildingResource", "ITEM_Resources_Coal", D.bags, ord, { toolBelt = true }), nil)
eq("bagFor: active tool belt", FL.bagFor("Item.Equipment.Tool.Shovel", "ITEM_Spade", D.bags, ord, { toolBelt = true }), "toolBelt")
eq("path from full name", FL.pathFromFullName("ItemData /Game/Gameplay/Items/Tools/ITEM_Pickaxe_Steel.ITEM_Pickaxe_Steel"),
    "/Game/Gameplay/Items/Tools/ITEM_Pickaxe_Steel.ITEM_Pickaxe_Steel")
eq("path from bad name", FL.pathFromFullName("nonsense"), nil)
do
    local text = FL.formatPaths({ ["/Game/B.B"] = "toolBelt", ["/Game/A.A"] = "toolBelt" })
    local back = FL.parsePaths(text)
    eq("paths round-trip A", back["/Game/A.A"], "toolBelt")
    eq("paths round-trip B", back["/Game/B.B"], "toolBelt")
    check("paths file sorted", text:find("/Game/A.A", 1, true) < text:find("/Game/B.B", 1, true))
    eq("paths parse ignores junk", next(FL.parsePaths("# comment\nnot a line\n")), nil)
end

-- layout: slot helpers
eq("items range", L.itemsRange().first .. "-" .. L.itemsRange().last, "8-39")
eq("absolute: hotbar 3", L.absoluteSlot(0, 3), 3)
eq("absolute: items 3 (shield, seen in game)", L.absoluteSlot(1, 3), 11)
eq("absolute: runes 0", L.absoluteSlot(2, 0), 40)
eq("absolute: quest 71", L.absoluteSlot(4, 71), 175)
eq("absolute: tool belt 2 (spade, seen in game)", L.absoluteSlot(9, 2), 178)
eq("absolute: rune essence 7", L.absoluteSlot(15, 7), 423)
eq("absolute: index past the page", L.absoluteSlot(9, 16), nil)
eq("absolute: unknown type", L.absoluteSlot(8, 0), nil)
eq("absolute: not a number", L.absoluteSlot(nil, 0), nil)
eq("bag of slot type 9", L.bagOfSlotType(9), "toolBelt")
eq("bag of slot type 1", L.bagOfSlotType(1), nil)

-- routing: move planning
local R = require("storagemage.routing")
do
    local items, belt = { first = 8, last = 11 }, { first = 176, last = 179 }
    local axe = function(n) return { key = "Axe", count = n or 1, max = 1, bag = "toolBelt" } end
    local torch = function(n) return { key = "Torch", count = n, max = 10, bag = "toolBelt" } end
    local bread = { key = "Bread", count = 3, max = 20 }

    -- totals and rises
    local snap = { [0] = axe(), [9] = torch(4), [177] = torch(5), [10] = bread }
    local t = R.totals(snap, 0, 423)
    eq("totals torch", t.Torch, 9); eq("totals axe", t.Axe, 1)
    local up = R.rises({ Torch = 9, Axe = 1 }, { Torch = 12, Axe = 1, Gem = 2 })
    eq("rise torch", up.Torch, 3); eq("rise new kind", up.Gem, 2); eq("no rise axe", up.Axe, nil)
    eq("no rise when used", next(R.rises({ Torch = 9 }, { Torch = 4 })), nil)

    -- target: stack with room first, then empty slots
    local tg, room = R.target({ [176] = torch(8) }, belt, "Torch", 10, 5)
    eq("target tops up stack", tg.to .. ":" .. tg.amount, "176:2"); eq("target total room", room, 5)
    tg = R.target({ [176] = torch(10) }, belt, "Torch", 10, 3)
    eq("target skips full stack", tg.to, 177)
    tg = R.target({ [176] = axe(), [177] = axe(), [178] = axe(), [179] = axe() }, belt, "Axe", 1, 1)
    eq("target none when full", tg, nil)

    -- sort: Items-page bag items only, hotbar untouched
    local m, full = R.sortStep({ [0] = axe(), [9] = axe(), [10] = bread }, items, { toolBelt = belt }, { toolBelt = true })
    eq("sort moves Items axe", m.from .. ">" .. m.to .. "x" .. m.amount, "9>176x1")
    m = R.sortStep({ [0] = axe(), [10] = bread }, items, { toolBelt = belt }, { toolBelt = true })
    eq("sort leaves hotbar", m, nil)
    m, full = R.sortStep({ [9] = axe(), [176] = axe(), [177] = axe(), [178] = axe(), [179] = axe() }, items,
        { toolBelt = belt }, { toolBelt = true })
    eq("sort: bag full", m, nil); eq("sort reports full bag", full[1], "toolBelt")
    m = R.sortStep({ [9] = axe() }, items, { toolBelt = belt }, {})
    eq("sort skips inactive bags", m, nil)

    -- routing: only the gained amount, from the last Items stack
    m = R.routeStep({ [8] = torch(6), [176] = torch(2) }, items, belt, "Torch", 1)
    eq("route moves just the gain", m.from .. ">" .. m.to .. "x" .. m.amount, "8>176x1")
    m = R.routeStep({ [8] = torch(2), [11] = torch(3) }, items, belt, "Torch", 4)
    eq("route takes the last stack first", m.from .. "x" .. m.amount, "11x3")
    local _, why = R.routeStep({ [0] = torch(3) }, items, belt, "Torch", 3)
    eq("route: gain went to the hotbar", why, "none")
    _, why = R.routeStep({ [8] = axe(), [176] = axe(), [177] = axe(), [178] = axe(), [179] = axe() }, items, belt, "Axe", 1)
    eq("route: bag full", why, "full")

    -- take out: to the Items page, stacking first
    m = R.takeOutStep({ [176] = torch(4), [9] = torch(9) }, 176, items)
    eq("take out tops up an Items stack", m.from .. ">" .. m.to .. "x" .. m.amount, "176>9x1")
    m = R.takeOutStep({ [176] = axe() }, 176, items)
    eq("take out to first empty", m.to, 8)
    _, why = R.takeOutStep({}, 176, items)
    eq("take out: empty slot", why, "empty")
    _, why = R.takeOutStep({ [176] = axe(), [8] = bread, [9] = bread, [10] = bread, [11] = bread }, 176, items)
    eq("take out: backpack full", why, "full")
end

-- art: which file to use
local ART = require("storagemage.art")
do
    local dir = "C:/G/ue4ss/Mods/StorageMage/"
    eq("frame mage dir", ART.frameMageDir(dir), "C:/G/ue4ss/Mods/FrameMage/")
    local c = ART.candidates(dir, "T_SM_X", false, "warrior")
    eq("no frame mage: default only", #c, 1); eq("default path", c[1], dir .. "Art/default/T_SM_X.png")
    c = ART.candidates(dir, "T_SM_X", true, "warrior")
    eq("theme first", c[1], "C:/G/ue4ss/Mods/FrameMage/Art/themes/warrior/storagemage/T_SM_X.png")
    eq("then elven", c[2], "C:/G/ue4ss/Mods/FrameMage/Art/themes/elven/storagemage/T_SM_X.png")
    eq("then default", c[3], dir .. "Art/default/T_SM_X.png")
    eq("elven theme not listed twice", #ART.candidates(dir, "T_SM_X", true, "elven"), 2)
    eq("unknown theme: elven then default", #ART.candidates(dir, "T_SM_X", true, nil), 2)
end
do
    local f = io.open("StorageMage/Art/default/T_SM_Tab_ToolBelt_Normal.png", "rb")
    local g = io.open("StorageMage/Art/default/T_SM_Tab_ToolBelt_Highlight.png", "rb")
    eq("tool belt tab art shipped", f ~= nil and g ~= nil, true)
    if f then f:close() end
    if g then g:close() end
end

-- dragprobe: which functions get hooked
local DP = require("storagemage.features.dragprobe")
eq("hook drag handler", DP.wanted("HandleInternalDragAndDrop"), true)
eq("hook move", DP.wanted("MoveItemBetweenInventories"), true)
eq("hook split", DP.wanted("SplitAndPutStack"), true)
eq("skip queries", DP.wanted("CanDropItem"), false)
eq("skip getters", DP.wanted("GetDragPayload"), false)
eq("skip mouse", DP.wanted("OnMouseMove"), false)
eq("skip unrelated", DP.wanted("RefreshSlots"), false)

-- belttab: rows for a page (8 slots wide, like the game's bodies)
local BT = require("storagemage.features.belttab")
eq("tab rows tool belt", BT.rows(16), 2); eq("tab rows items", BT.rows(32), 4); eq("tab rows ores", BT.rows(72), 9)
eq("tab rows essence", BT.rows(8), 1); eq("tab value after game tabs", BT.GAME_TABS, 4)
do
    local all = true
    for _, p in ipairs(L.PAGES) do if p.slots % BT.SLOTS_PER_ROW ~= 0 then all = false end end
    eq("every bag fills whole rows", all, true)
end

eq("tag for tool belt", PG.tagFor("toolBelt"), "ItemFilter.StorageMage.ToolBelt")
eq("tag for rune essence", PG.tagFor("runeEssence"), "ItemFilter.StorageMage.RuneEssence")
do
    local seen, dup = {}, nil
    for _, p in ipairs(L.PAGES) do
        local t = PG.tagFor(p.bag)
        if seen[t] then dup = t end
        seen[t] = true
    end
    eq("page tags are unique", dup, nil)
end

-- main.lua smoke test: loads with stubbed UE4SS, starts every feature, writes its settings ---------------
do
    -- main.lua finds its folder from its own path: run it as the repo's StorageMage/Scripts/main.lua, so it
    -- writes into StorageMage/config/ (git-ignored; the game uses its own config folder). Files the test
    -- creates are removed again; a settings.lua that was already there is left alone.
    local dir = "StorageMage"
    local function exists(p) local f = io.open(p, "rb"); if f then f:close() return true end return false end
    local hadSettings = exists(dir .. "/config/settings.lua")
    local hadDefaults = exists(dir .. "/config/settings.defaults.lua")
    local hadT1 = exists(dir .. "/dumps/t1.txt")
    local hadTags = exists(dir .. "/dumps/tags.txt")
    local scheduled, logged = {}, {}
    local stubs = {
        LoopInGameThreadWithDelay = function(_, fn) scheduled[#scheduled + 1] = fn end,
        ExecuteInGameThreadWithDelay = function(_, fn) scheduled[#scheduled + 1] = fn end,
        ExecuteInGameThread = function(fn) scheduled[#scheduled + 1] = fn end,
        NotifyOnNewObject = function() end,
        StaticFindObject = function() return nil end,
        FindFirstOf = function() return nil end,
        FName = function(s) return s end,
    }
    for k, v in pairs(stubs) do _G[k] = v end
    local realPrint = print
    _G.print = function(s) logged[#logged + 1] = s end
    local ok, err = pcall(dofile, dir .. "/Scripts/main.lua")
    for _, fn in ipairs(scheduled) do pcall(fn) end -- one round of game-thread callbacks
    _G.print = realPrint
    for k in pairs(stubs) do _G[k] = nil end
    check("main.lua runs", ok, err)
    local joined = table.concat(logged, "")
    check("feature probe ready", joined:find("feature 'probe' ready", 1, true) ~= nil, joined)
    check("feature pagetest off by default", joined:find("feature 'pagetest' disabled in settings", 1, true) ~= nil, joined)
    check("feature pages ready", joined:find("feature 'pages' ready", 1, true) ~= nil, joined)
    check("no T1 timeline while pagetest is off", hadT1 or not exists(dir .. "/dumps/t1.txt"))
    if not hadT1 then os.remove(dir .. "/dumps/t1.txt") end
    check("feature tags ready", joined:find("feature 'tags' ready", 1, true) ~= nil, joined)
    check("feature uidump off by default", joined:find("feature 'uidump' disabled in settings", 1, true) ~= nil, joined)
    check("feature belttab ready", joined:find("feature 'belttab' ready", 1, true) ~= nil, joined)
    check("feature dragprobe off by default", joined:find("feature 'dragprobe' disabled in settings", 1, true) ~= nil, joined)
    check("feature bagmoves ready", joined:find("feature 'bagmoves' ready", 1, true) ~= nil, joined)
    if not hadTags then os.remove(dir .. "/dumps/tags.txt") end
    check("started callback ran", joined:find("Storage Mage running", 1, true) ~= nil, joined)
    check("no errors logged", joined:find("ERROR", 1, true) == nil, joined)
    check("settings.defaults.lua written", exists(dir .. "/config/settings.defaults.lua"))
    if not hadSettings then
        local f = io.open(dir .. "/config/settings.lua", "rb")
        local text = f and f:read("a")
        if f then f:close() end
        local parsed = text and S.parse(text)
        check("fresh settings.lua holds no overrides", parsed ~= nil and next(parsed) == nil, text)
        os.remove(dir .. "/config/settings.lua")
    end
    if not hadDefaults then os.remove(dir .. "/config/settings.defaults.lua") end
end

print(string.format("%d passed, %d failed", passes, failures))
os.exit(failures == 0 and 0 or 1)
