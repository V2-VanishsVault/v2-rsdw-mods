-- Tests for the shared Settings panel (pure parts, and the client and host against stand-in shared variables).
-- Run on their own (lua shared/settingspanel/tests/run_tests.lua from the repository's root) or from a mod's
-- tests, which dofile this with package.path already pointing at shared/. Returns passed, failed.
local here = (debug.getinfo(1, "S").source:gsub("^@", ""):gsub("\\", "/"):match("^(.*)/tests/[^/]+$")) or "shared/settingspanel"
local sharedDir = here:match("^(.*)/settingspanel$") or "shared"
package.path = sharedDir .. "/?.lua;" .. package.path

local pass, fail = 0, 0
local function check(name, cond, extra)
    if cond then pass = pass + 1 else fail = fail + 1; io.stdout:write("FAIL settingspanel: " .. name .. (extra ~= nil and (": " .. tostring(extra)) or ""), "\n") end
end
local function eq(name, a, b) check(name, a == b, tostring(a) .. " ~= " .. tostring(b)) end

-- stand-ins for UE4SS: shared variables in a table, scheduled callbacks collected
local vars = {}
ModRef = { SetSharedVariable = function(_, k, v) vars[k] = v end, GetSharedVariable = function(_, k) return vars[k] end }
local loops, laters = {}, {}
LoopInGameThreadWithDelay = function(ms, fn) loops[#loops + 1] = fn end
ExecuteInGameThreadWithDelay = function(ms, fn) laters[#laters + 1] = fn end
local realPrint = print
local quiet = true
print = function(...) if not quiet then realPrint(...) end end

local P = require("settingspanel.protocol")
local serialize = require("settingspanel.serialize")

-- files: nothing of any mod's own code ----------------------------------------------------------------------------
local FILES = { "client", "game", "input", "look", "main", "panel", "protocol", "serialize", "version" }
local function read(name)
    local f = io.open(here .. "/" .. name .. ".lua", "rb")
    if not f then return nil end
    local s = f:read("a"); f:close()
    return (s:gsub("\r\n", "\n"))
end
local all = {}
for _, name in ipairs(FILES) do
    local text = read(name)
    check("file exists: " .. name, text ~= nil)
    if text then
        check("no mod's code required: " .. name, not text:find('require%("framemage') and not text:find('require%("storagemage'))
        check("loads: " .. name, load(text, name) ~= nil)
        if name ~= "version" then all[#all + 1] = text end
    end
end
local sum = P.checksum(table.concat(all, "\n"))
local version = require("settingspanel.version")
if version.CHECKSUM ~= sum then
    realPrint(("settingspanel: the panel's files changed: raise PANEL_VERSION in version.lua (now %d) and set CHECKSUM = %q")
        :format(version.PANEL_VERSION, sum))
end
check("version.lua's CHECKSUM matches the files (raise PANEL_VERSION when they change)", version.CHECKSUM == sum)

-- host claim ------------------------------------------------------------------------------------------------------
check("claim an empty host", P.shouldClaim(nil, 1, "StorageMage"))
check("claim a garbled host", P.shouldClaim("x", 1, "StorageMage"))
check("newer copy claims", P.shouldClaim("1|FrameMage", 2, "StorageMage"))
check("older copy doesn't", not P.shouldClaim("2|FrameMage", 1, "StorageMage"))
check("same version: the first name keeps it", not P.shouldClaim("1|FrameMage", 1, "StorageMage"))
check("same version: the first name takes it", P.shouldClaim("1|StorageMage", 1, "FrameMage"))
check("a mod re-claims its own", P.shouldClaim("1|FrameMage", 1, "FrameMage"))
check("stale: never seen", P.stale(nil, 10))
check("stale after 6 s", P.stale(3, 10))
check("fresh beat", not P.stale(8, 10))
eq("host value", P.hostValue(3, "FrameMage"), "3|FrameMage")

-- registry ---------------------------------------------------------------------------------------------------------
eq("registry: first", P.addTo(nil, "StorageMage"), "StorageMage")
eq("registry: sorted, once", P.addTo("StorageMage,FrameMage", "FrameMage"), "FrameMage,StorageMage")
eq("registry: added", P.addTo("StorageMage", "FrameMage"), "FrameMage,StorageMage")

-- schema -----------------------------------------------------------------------------------------------------------
do
    local s, notes = P.clean({ protocol = 1, mod = "X", title = "X Mod",
        tabs = { { id = "a", label = "A" }, { id = "a", label = "dup" } },
        rows = { { tab = "a", type = "toggle", setting = "on", label = "On" },
            { tab = "zz", type = "bool", setting = "lost" },
            { tab = "a", type = "hologram", setting = "future" },
            { type = "button", action = "go", label = "Go" } } })
    check("schema cleaned", s ~= nil)
    eq("duplicate tab dropped", #s.tabs, 1)
    eq("unknown kind skipped", #s.rows, 3)
    eq("noted", #notes, 1)
    eq("old names mapped: toggle", s.rows[1].kind, "bool")
    eq("old names mapped: button", s.rows[3].kind, "action")
    eq("a row on an unknown tab goes to the first", s.rows[2].tab, "a")
    check("no protocol: refused", P.clean({ rows = {} }) == nil)
    local one = P.clean({ protocol = 1, title = "Solo", rows = { { type = "bool", setting = "x" } } })
    eq("no tabs: one made from the title", one.tabs[1].label, "Solo")
end

-- values, requests -------------------------------------------------------------------------------------------------
check("pending until echoed", P.pending(5, { lastRequest = 4 }))
check("answered", not P.pending(5, { lastRequest = 5 }))
check("nothing sent", not P.pending(nil, {}))
check("server-owned shows read-only on a client", P.readOnly({ owner = "server" }, { serverOwned = true }))
check("server-owned is editable on the server", not P.readOnly({ owner = "server" }, { serverOwned = false }))
eq("cycle wraps", P.cycle({ "a", "b", "c" }, "c", 1), "a")
eq("cycle back", P.cycle({ "a", "b", "c" }, "a", -1), "c")
eq("step clamps", P.step({ min = 0, max = 10, step = 4 }, 8, 1), 10)
eq("step: no float drift", P.step({ min = 0, max = 1, step = 0.05 }, 0.7, 1), 0.75)
eq("display: bool", P.display({ type = "bool" }, true), "On")
eq("display: percent", P.display({ type = "slider", percent = true }, 0.5), "50%")
eq("display: suffix", P.display({ type = "number", suffix = " px" }, 16), "16 px")
eq("display: label", P.display({ type = "choice", labels = { a = "Alpha" } }, "a"), "Alpha")
check("armed within 4 s", P.isArmed({ key = "k", at = 1 }, "k", 4))
check("disarmed after", not P.isArmed({ key = "k", at = 1 }, "k", 6))
local box = P.parseBox(P.boxString({ left = 10, top = 20, right = 300, bottom = 400 }))
eq("box round trip", box.right, 300)
eq("a box at a fractional position (after a drag) is written whole", P.boxString({ left = 10.4, top = 20.6, right = 300, bottom = 400.5 }), "10,21,300,401")
check("box contains", P.contains(box, 100, 100) and not P.contains(box, 5, 100))
local ox, oy = P.onScreen(1643, 780, 1920, 1080, 600, 650)
eq("a panel dragged low comes back on screen", oy, 430)
eq("and stays where it was sideways if it fits", ox, 1320)
local tx, ty = P.onScreen(-50, -9, 1920, 1080, 600, 650)
check("never off the top or left", tx == 0 and ty == 0)
local cells = P.cells(100, 4, 4)
eq("cells: four", #cells, 4)
check("cells fill the width", math.abs(cells[4].x + cells[4].w - 100) < 0.001)

-- a key going down: held now and not before, or a tap between two looks ---------------------------------------
do
    local I = require("settingspanel.input")
    check("pressed since the last look", I.wentDown(true, false, false))
    check("still held: not again", not I.wentDown(true, true, false))
    check("a tap between two looks", I.wentDown(false, false, true))
    check("nothing", not I.wentDown(false, false, false))
end

-- keys: taken, refused ---------------------------------------------------------------------------------------------
do
    local mods = {
        { name = "FrameMage", schema = P.clean({ protocol = 1, title = "Frame Mage",
            rows = { { type = "key", setting = "keys.edit", label = "Open the editor" },
                { type = "key", setting = "keys.undo", label = "Undo" } } }),
          values = { values = { ["keys.edit"] = "F9", ["keys.undo"] = "CTRL+Z" } } },
        { name = "StorageMage", schema = P.clean({ protocol = 1, title = "Storage Mage",
            rows = { { type = "key", setting = "keys.takeOut", label = "Take out" } } }),
          values = { values = { ["keys.takeOut"] = "T" } } },
    }
    eq("a key another mod uses is taken", P.keyTakenBy(mods, "StorageMage", "keys.takeOut", "f9"), "Frame Mage: Open the editor")
    eq("with modifiers, spelled differently", P.keyTakenBy(mods, "StorageMage", "keys.takeOut", "ctrl + z"), "Frame Mage: Undo")
    eq("the row's own key is free", P.keyTakenBy(mods, "StorageMage", "keys.takeOut", "T"), nil)
    eq("a free key", P.keyTakenBy(mods, "StorageMage", "keys.takeOut", "Y"), nil)
    eq("refusal for our request", P.refusal(7, { refused = { id = 7, reason = "No." } }), "No.")
    eq("someone else's refusal", P.refusal(8, { refused = { id = 7, reason = "No." } }), nil)
end

-- panel layout (pure) ----------------------------------------------------------------------------------------------
do
    -- panel.lua needs the game only at run time; its pure functions load without it
    local Pn = require("settingspanel.panel")
    local S = Pn.SIZE
    local L = Pn.layout(S, { 16, 12, 16, 12 }, 3, 6)
    eq("three mod tabs", #L.modTabs, 3)
    eq("six tabs", #L.tabs, 6)
    check("tabs under the mod tabs", L.tabs[1].top > L.modTabs[1].bottom)
    check("rows under the tabs", L.rows.top > L.tabs[1].bottom)
    check("tip under the rows", L.tip.top >= L.rows.top + S.slots * S.rowH)
    check("close in the middle", math.abs((L.close.left + L.close.right) / 2 - S.width / 2) < 1)
    check("panel holds the footer", L.h >= L.close.bottom)
    local inset = Pn.layout(S, { 16, 12, 16, 12 }, 3, 6, nil, 16)
    eq("the title moved inside a border", inset.title.top, 16)
    eq("and everything under it with it", inset.tabs[1].top - L.tabs[1].top, 16)
    local one = Pn.layout(S, { 16, 12, 16, 12 }, 1, 1)
    eq("one mod: no mod tabs", #one.modTabs, 0)
    local rr = Pn.rowRects(L, S, 2, 1, "bool")
    eq("row 2 starts one row down", rr.row.top, L.rows.top + S.rowH)
    check("value right of the label", rr.value.left > rr.label.right)
    check("arrows either side of the plate", rr.back.right <= rr.plate.left and rr.fwd.left >= rr.plate.right)
    local pages = Pn.pages({ 1, 2, 3, 4, 5 }, 4, function(r) return r == 3 and 2 or 1 end)
    eq("pages: two", #pages, 2)
    eq("pages: a tall row moves to the next page", #pages[1], 3)
    eq("pages: empty tab still has a page", #Pn.pages({}, 4, function() return 1 end), 1)
    eq("a short label is one line", Pn.linesOf({ type = "bool", label = "Snap to grid" }, 300, 13), 1)
    check("a long note wraps", Pn.linesOf({ type = "info", label = string.rep("word ", 40) }, 300, 13) > 1)
    check("tip: restart note", Pn.tipFor({ applies = "restart", tooltip = "T." }, {}):find("restart") ~= nil)
    local sw = { left = 100, top = 10, right = 146, bottom = 32 }
    check("switch on: knob at the right", Pn.knobRect(sw, true, 16).right <= 146 and Pn.knobRect(sw, true, 16).left > 120)
    check("switch off: knob at the left", Pn.knobRect(sw, false, 16).left >= 100 and Pn.knobRect(sw, false, 16).right < 126)
    local kr = Pn.rowRects(L, S, 1, 1, "key")
    check("a key's field, then RESET", kr.field.right <= kr.reset.left and kr.reset.right <= L.rows.right)
    local br = Pn.rowRects(L, S, 1, 1, "bool")
    check("a switch at the right, its state before it", br.state.right < br.switch.left)
    local fm = { "Look", "Vitals", "Editor", "Celebrations", "Keys", "Share" }
    local wide = Pn.widthFor(S, { 56, 52, 56, 52 }, { "Frame Mage", "Storage Mage", "Panel" }, { fm, { "Bags" } })
    check("the panel widens for a wide frame and six tabs", wide > S.width, wide)
    eq("narrow tabs: the panel keeps its width", Pn.widthFor(S, { 16, 12, 16, 12 }, { "A", "B" }, { { "X" } }), S.width)
    local xs = Pn.spread(10, wide - 112, fm, S.tabSize, 4)
    check("a long label gets more room", (xs[4].right - xs[4].left) > (xs[5].right - xs[5].left))
    check("every label fits its tab", (xs[4].right - xs[4].left) >= Pn.need("Celebrations", S.tabSize))
    check("tabs end inside the panel", xs[6].right <= 10 + wide - 112 + 0.001)
end

-- client against stand-in shared variables -----------------------------------------------------------------------
do
    local client = require("settingspanel.client")
    local store = { a = true, n = 3 }
    local applied, ran = {}, {}
    client.register({ mod = "TestMod", title = "Test", order = 5,
        tabs = { { id = "t", label = "T" } },
        rows = { { tab = "t", type = "bool", setting = "a", label = "A" }, { tab = "t", type = "number", setting = "n", label = "N" },
            { tab = "t", type = "action", action = "go", label = "Go" } },
        get = function(k) return store[k] end,
        apply = function(k, v) store[k] = v; applied[#applied + 1] = k end,
        action = function(name) ran[#ran + 1] = name end })
    check("registered", (vars["SettingsPanel.registry"] or ""):find("TestMod") ~= nil)
    local schema = serialize.parse(vars["SettingsPanel.TestMod.schema"])
    eq("schema published", schema and #schema.rows, 3)
    local values = serialize.parse(vars["SettingsPanel.TestMod.values"])
    eq("values published", values.values.n, 3)
    -- the panel sends a change
    vars["SettingsPanel.TestMod.request"] = serialize.dump(P.request(41, "n", 7))
    vars["SettingsPanel.TestMod.requestRev"] = 1
    for _, f in ipairs(loops) do f() end
    eq("change applied", store.n, 7)
    values = serialize.parse(vars["SettingsPanel.TestMod.values"])
    eq("new value published", values.values.n, 7)
    eq("request echoed", values.lastRequest, 41)
    check("no longer pending", not P.pending(41, values))
    vars["SettingsPanel.TestMod.request"] = serialize.dump(P.actionRequest(42, "go"))
    vars["SettingsPanel.TestMod.requestRev"] = 2
    for _, f in ipairs(loops) do f() end
    eq("action run", ran[1], "go")
    for _, f in ipairs(loops) do f() end
    eq("a request runs once", #ran, 1)
    -- a change the mod refuses comes back with its reason
    local client2 = require("settingspanel.client")
    local refusing = { mod = "TestMod", rows = {}, get = function() end,
        apply = function() return false, "Nope: taken." end }
    eq("refused: the id", client2.handle(refusing, P.request(50, "a", 1)), 50)
    eq("refused: the reason kept", client2.refused and client2.refused.reason, "Nope: taken.")
end

-- long strings over shared variables --------------------------------------------------------------------------------
do
    local game = require("settingspanel.game")
    local real = ModRef.SetSharedVariable
    ModRef.SetSharedVariable = function(_, k, v) vars[k] = (type(v) == "string" and #v > 5000) and v:sub(1, 5000) or v end
    local long = string.rep("abcdefghij", 1200)
    game.set("Big", long)
    eq("a long string comes back whole", game.get("Big"), long)
    check("split into pieces", tostring(vars["Big"]):match("^@chunks:") ~= nil)
    ModRef.SetSharedVariable = real
end

print = realPrint
-- (run on its own: report and exit; dofile'd from a mod's tests: just return the counts)
if arg and arg[0] and arg[0]:gsub("\\", "/"):find("settingspanel/tests/run_tests%.lua$") then
    print(("settingspanel: %d passed, %d failed"):format(pass, fail))
    if fail > 0 then os.exit(1) end
end
return pass, fail
