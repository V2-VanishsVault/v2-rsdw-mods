-- Moving items into and out of bag pages (user's design, 2026-11-13; no manual moving into bags):
--   * pickup routing: when a player's total of a bag item rises (pickup, chest, crafting), the gained amount
--     moves from the Items page into its bag. Moves within the inventory don't change totals, so an item taken
--     out is never routed back. Runs where the inventories live: the host / dedicated server, for every player.
--   * sort hotkey (keys.sortBags): every Items-page item that belongs to an active bag goes into it, including
--     ones taken out earlier. The hotbar is never touched.
--   * take-out key (keys.takeOut, inventory open): the bag item under the mouse goes to the Items page.
-- Only bags in features/tags.lua ACTIVE take part (the Tool Belt for now).
--
-- Each operation is a job of single steps: snapshot the inventory, ask storagemage/routing.lua for the next move,
-- do it, check it on the next snapshot. Host / server: InventoryComponent:MoveItem. Joined client: the
-- InventoryController calls the game's own inventory screen uses (forwarded to the server), checked a moment
-- later. Native drag and drop can't be used (dragprobe, 2026-11-13: the UI calls it natively).
-- Report: dumps/moves.txt.
local M = {}

local L = require("storagemage.layout")
local F = require("storagemage.filters")
local R = require("storagemage.routing")
local TAGS = require("storagemage.features.tags")
local INVUI = require("storagemage.inventoryui")

local ctx, log, O

M.MAX_STEPS = 64
M.HOST_STEP_MS = 40
M.CLIENT_STEP_MS = 400
M.POLL_MS = 1000

local function try(fn, ...)
    local ok, v = pcall(fn, ...)
    if ok then return v end
    return nil
end

local report = {}
local function note(fmt, ...)
    report[#report + 1] = os.date("%H:%M:%S ") .. string.format(fmt, ...)
    log.info("moves: %s", report[#report])
    if #report > 400 then table.remove(report, 1) end
    ctx.fs.write(ctx.dir .. "dumps/moves.txt", "# Storage Mage bag moves\n" .. table.concat(report, "\n") .. "\n")
end

local BAG_NAMES = { toolBelt = "Tool Belt", herbs = "Herbs", gems = "Gems", ores = "Ores", seeds = "Seeds",
    fishing = "Fishing", runeEssence = "Rune Essence" }
local function bagName(bag) return BAG_NAMES[bag] or bag end

-- Active bags in layout order, their tags and slot ranges.
local function activeBags()
    local ranges = L.slotRanges()
    local list, set, bags = {}, {}, {}
    for _, p in ipairs(L.PAGES) do
        if TAGS.ACTIVE[p.bag] then
            list[#list + 1] = { bag = p.bag, tag = F.tagFor(p.bag) }
            set[p.bag] = true
            bags[p.bag] = { first = ranges[p.bag].first, last = ranges[p.bag].last }
        end
    end
    return list, set, bags
end

local function snapshot(inv)
    local list = activeBags()
    local _, total = L.slotRanges()
    local snap = {}
    for i = 0, total - 1 do
        local item = try(function() return inv:GetItemFromSlot(i) end)
        if O.valid(item) then
            local data = try(function() return item.ItemData end)
            local s = { key = O.valid(data) and O.name(data) or "?", count = try(function() return item.Count end) or 0,
                max = (data and try(function() return data.MaxStackSize end)) or 1 }
            for _, b in ipairs(list) do
                if data and TAGS.hasTag(data, b.tag) then s.bag = b.bag break end
            end
            snap[i] = s
        end
    end
    return snap, total
end

local function controllerOf(pc)
    local c = O.get(pc, "InventoryController")
    if O.valid(c) then return c end
    local pcName = try(function() return pc:GetFullName() end)
    for _, ic in ipairs(try(function() return FindAllOf("BP_Components_InventoryController_C") end) or {}) do
        local owner = O.valid(ic) and try(function() return ic:GetOwner() end)
        if owner and try(function() return owner:GetFullName() end) == pcName then return ic end
    end
    local api = try(function() return FindFirstOf("InventoryUIAPI") end)
    c = O.get(api, "InventoryController")
    return O.valid(c) and c or nil
end

-- Finds a player controller again by its full name (never keep handles across ticks).
local function controllerByName(name)
    local lp = O.localController()
    if lp and try(function() return lp:GetFullName() end) == name then return lp end
    for _, pc in ipairs(M.playerControllers()) do
        if try(function() return pc:GetFullName() end) == name then return pc end
    end
    return nil
end

-- Every player controller in the world (on a server: every player's). FindAllOf matches a class by name, so
-- the game's Blueprint class is asked for as well as the engine's.
function M.playerControllers()
    local out, seen = {}, {}
    for _, cls in ipairs({ "BP_PlayerController_C", "PlayerController" }) do
        for _, pc in ipairs(try(function() return FindAllOf(cls) end) or {}) do
            local n = O.valid(pc) and try(function() return pc:GetFullName() end)
            if n and not seen[n] and not n:find("Default__", 1, true) then seen[n] = true; out[#out + 1] = pc end
        end
    end
    return out
end

local function doMove(pc, inv, snap, m, viaServer)
    if not viaServer then
        return pcall(function() return inv:MoveItem(m.from, inv, m.to, pc, m.amount) end)
    end
    local ctrl = controllerOf(pc)
    if not ctrl then return false, "no InventoryController" end
    local src = snap[m.from]
    if not snap[m.to] and src and src.count == m.amount then
        return pcall(function() return ctrl:MoveItemBetweenInventories(inv, m.from, inv, m.to) end)
    end
    return pcall(function() return ctrl:SplitAndPutStack(inv, m.from, m.amount, inv, m.to) end)
end

-- Did move m (planned on `before`) happen, judging by `after`?
local function happened(before, after, m)
    local b, a, bt, at = before[m.from], after[m.from], before[m.to], after[m.to]
    if not b then return false end
    local srcOk = (a == nil and b.count == m.amount) or (a ~= nil and a.key == b.key and a.count == b.count - m.amount)
    local dstOk = at ~= nil and at.key == b.key and at.count == (bt and bt.count or 0) + m.amount
    return srcOk and dstOk
end

-- Jobs: one runs at a time per player; others wait in that player's queue.
local queues = {}
local function runNext(pcName)
    local q = queues[pcName]
    if not q or q.running or #q == 0 then return end
    local job = table.remove(q, 1)
    q.running = job
    local steps, last = 0, nil
    local function finish(reason)
        q.running = nil
        if job.done then pcall(job.done, reason, steps - (reason == "failed" and 1 or 0)) end
        runNext(pcName)
    end
    local function step()
        local pc = controllerByName(pcName)
        local inv = pc and O.get(pc, "InventoryComponent")
        if not O.valid(inv) then note("%s: player gone, stopped", job.label) return finish("gone") end
        local snap = snapshot(inv)
        if last then
            if not happened(last.snap, snap, last.move) then
                note("%s: move %d -> %d (x%d) did NOT happen; stopped", job.label, last.move.from, last.move.to,
                    last.move.amount)
                return finish("failed")
            end
            if job.moved then job.moved(last.move) end
        end
        if steps >= M.MAX_STEPS then note("%s: step limit reached", job.label) return finish("limit") end
        local m, reason = job.step(snap)
        if not m then return finish(reason) end
        local src = snap[m.from]
        local ok, ret = doMove(pc, inv, snap, m, job.viaServer)
        note("%s: %s x%d slot %d -> %d%s", job.label, src and src.key or "?", m.amount, m.from, m.to,
            ok and "" or ("  ERROR " .. tostring(ret)))
        if not ok then return finish("failed") end
        steps = steps + 1
        last = { snap = snap, move = m }
        ctx.sched.later(job.viaServer and M.CLIENT_STEP_MS or M.HOST_STEP_MS, "bag move", step)
    end
    step()
end

local function enqueue(pcName, job)
    queues[pcName] = queues[pcName] or {}
    table.insert(queues[pcName], job)
    runNext(pcName)
end

-- What this machine may do with the local player's inventory: "direct" (host / solo), "server" (a joined
-- client: ask the server), or nil (no player, or role unknown: don't touch inventories).
local function localMode()
    local role = O.netRole()
    if role == "host" then return "direct" end
    if role == "client" then return "server" end
    return nil
end

-- ---- sort hotkey ----------------------------------------------------------------------------------------------
local function sortBags()
    local mode = localMode()
    local pc = O.localController()
    if not (mode and pc) then return end
    local name = try(function() return pc:GetFullName() end)
    local _, active, bags = activeBags()
    local moved = 0
    note("sort: started (%s)", mode)
    enqueue(name, {
        label = "sort", viaServer = mode == "server",
        step = function(snap) return R.sortStep(snap, L.itemsRange(), bags, active) end,
        moved = function(m) moved = moved + 1 end,
        done = function(reason)
            local msg = moved > 0 and string.format("Sorted %d item stack%s into bags", moved, moved == 1 and "" or "s")
                or "Nothing to sort"
            if type(reason) == "table" and #reason > 0 then
                local names = {}
                for _, b in ipairs(reason) do names[#names + 1] = bagName(b) end
                msg = msg .. " (full: " .. table.concat(names, ", ") .. ")"
            elseif reason == "failed" then
                msg = msg .. " (a move failed: see dumps/moves.txt)"
            end
            note("sort: %s", msg)
            ctx.toast.show(msg)
        end,
    })
end

-- ---- take-out key ---------------------------------------------------------------------------------------------
-- The bag slot under the mouse, from the slot widgets' bIsMousedOver and SlotPayload (seen working 2026-11-13).
local function hoveredBagSlot(nav)
    local found
    try(function() O.get(nav, "InventoryBodies"):ForEach(function(_, e)
        if found then return end
        local body = e:get()
        if not L.bagOfSlotType(O.get(body, "SlotType")) then return end
        try(function() body.InventorySlots:ForEach(function(_, se)
            local s = se:get()
            if not found and O.valid(s) and O.get(s, "bIsMousedOver") == true then
                local p = O.get(s, "SlotPayload")
                found = L.absoluteSlot(O.get(p, "OwningInventoryType"), O.get(p, "InventoryIndex"))
            end
        end) end)
    end) end)
    return found
end

local function takeOut()
    local mode = localMode()
    local pc = O.localController()
    local pick = INVUI.findNav()
    if not (mode and pc and pick) then return end
    local slot = hoveredBagSlot(pick.w)
    if not slot then return end -- not over a bag slot: the key does nothing
    local name = try(function() return pc:GetFullName() end)
    local moved = 0
    enqueue(name, {
        label = "take out", viaServer = mode == "server",
        step = function(snap) return R.takeOutStep(snap, slot, L.itemsRange()) end,
        moved = function() moved = moved + 1 end,
        done = function(reason)
            if reason == "full" and moved == 0 then ctx.toast.show("Your backpack is full") end
            if reason == "failed" then ctx.toast.show("Couldn't take that out (see dumps/moves.txt)") end
        end,
    })
end

-- ---- pickup routing (where inventories live) ----------------------------------------------------------------
local players = {} -- pc full name -> { inv = inventory full name, base = totals of bag items, num = GetNumItems }

local function bagTotals(snap, total)
    local t = {}
    for i = 0, total - 1 do
        local s = snap[i]
        if s and s.bag then t[s.key] = (t[s.key] or 0) + s.count end
    end
    return t
end

local function pollPlayer(pc)
    local inv = O.get(pc, "InventoryComponent")
    if not O.valid(inv) or O.get(inv, "bHasLoadedFromSave") ~= true then return end
    local pcName = try(function() return pc:GetFullName() end)
    local invName = try(function() return inv:GetFullName() end)
    local num = try(function() return inv:GetNumItems() end)
    if not (pcName and invName and num) then return end
    local st = players[pcName]
    if not st or st.inv ~= invName then
        local snap, total = snapshot(inv)
        players[pcName] = { inv = invName, base = bagTotals(snap, total), num = num }
        return
    end
    if num == st.num then return end -- nothing gained or used: no scan
    st.num = num
    local snap, total = snapshot(inv)
    local now = bagTotals(snap, total)
    local gained = R.rises(st.base, now)
    st.base = now -- moves inside the inventory don't change totals, so this stays right while we route
    local bagOf = {}
    for i = 0, total - 1 do local s = snap[i]; if s and s.bag then bagOf[s.key] = s.bag end end
    local _, _, bags = activeBags()
    for key, amount in pairs(gained) do
        local bag = bagOf[key]
        if bag and bags[bag] then
            local left = amount
            note("pickup: %s +%d -> %s", key, amount, bagName(bag))
            enqueue(pcName, {
                label = "route " .. key,
                step = function(s) return R.routeStep(s, L.itemsRange(), bags[bag], key, left) end,
                moved = function(m) left = left - m.amount end,
                done = function(reason)
                    if reason == "full" then
                        note("pickup: %s: %s is full, %d left in the backpack", key, bagName(bag), left)
                        local lp = O.localController()
                        if lp and try(function() return lp:GetFullName() end) == pcName then
                            ctx.toast.show(bagName(bag) .. " is full")
                        end
                    end
                end,
            })
        end
    end
end

local function poll()
    local role = O.netRole()
    if role ~= "host" and role ~= "dedicated" then return end -- clients: the server routes for them
    for _, pc in ipairs(M.playerControllers()) do
        local ok, err = pcall(pollPlayer, pc)
        if not ok then log.warn("bag routing: %s", tostring(err)) end
    end
end

function M.init(c)
    ctx, log, O = c, c.log, c.objects
    ctx.keys.bind(ctx.settings.keys.sortBags, "sortBags", sortBags)
    -- No `when` gate: it runs every frame, and finding the inventory screen costs two object searches. The
    -- key looks for the screen only when pressed, and does nothing unless the mouse is over a bag slot.
    ctx.keys.bind(ctx.settings.keys.takeOut, "takeOut", takeOut)
    if ctx.settings.pickupRouting ~= false then ctx.sched.every(M.POLL_MS, "bag routing", poll) end
end

return M
