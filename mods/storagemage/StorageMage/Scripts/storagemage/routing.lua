-- Pure planning for bag moves (no UE4SS calls; unit-tested). A snapshot is a table indexed by slot number:
-- snap[i] = { key = <item kind, e.g. its ItemData name>, count = n, max = <stack size>, bag = <bag id or nil> }
-- or nil for an empty slot. A range is { first = a, last = b }. A move is { from = i, to = j, amount = n }.
--
-- Every planner returns ONE move (the next one) or nil plus a reason: the caller does it, takes a fresh
-- snapshot and asks again. That keeps each step right even when a move doesn't do what was expected, and
-- works the same for a joined client, whose moves land on the server a moment later.
local M = {}

-- Total count of each kind over the slots first..last.
function M.totals(snap, first, last)
    local t = {}
    for i = first, last do
        local s = snap[i]
        if s and s.key then t[s.key] = (t[s.key] or 0) + (s.count or 0) end
    end
    return t
end

-- Kinds whose total rose: { key = increase }.
function M.rises(before, after)
    local out = {}
    for k, n in pairs(after) do
        local d = n - (before[k] or 0)
        if d > 0 then out[k] = d end
    end
    return out
end

-- Where `amount` of `key` can go within `range`: stacks of the same kind with room first (in slot order), then
-- empty slots. Returns the first target { to, amount } and how much of `amount` all the targets together can
-- take. `skip` is a slot never to use (the source).
function M.target(snap, range, key, max, amount, skip)
    max = (max and max > 0) and max or 1
    local first, room = nil, 0
    for i = range.first, range.last do
        local s = snap[i]
        if i ~= skip and s and s.key == key and (s.count or 0) < max then
            local fits = math.min(max - s.count, amount - room)
            if fits > 0 then
                first = first or { to = i, amount = fits }
                room = room + fits
                if room >= amount then return first, room end
            end
        end
    end
    for i = range.first, range.last do
        if i ~= skip and not snap[i] then
            local fits = math.min(max, amount - room)
            first = first or { to = i, amount = fits }
            room = room + fits
            if room >= amount then return first, room end
        end
    end
    return first, room
end

local function moveFrom(snap, from, amount, range)
    local s = snap[from]
    local t = M.target(snap, range, s.key, s.max, amount, from)
    if not t then return nil end
    return { from = from, to = t.to, amount = math.min(t.amount, amount) }
end

-- The sort hotkey: the next Items-page item that belongs to an active bag, into that bag. Hotbar never touched.
-- active: { bag = true }; bags: { bag = range }. Returns move, or nil and a list of bags that were full.
function M.sortStep(snap, items, bags, active)
    local full, fullSeen = {}, {}
    for i = items.first, items.last do
        local s = snap[i]
        if s and s.bag and active[s.bag] and bags[s.bag] then
            local m = moveFrom(snap, i, s.count, bags[s.bag])
            if m then return m end
            if not fullSeen[s.bag] then fullSeen[s.bag] = true; full[#full + 1] = s.bag end
        end
    end
    return nil, full
end

-- Pickup routing: move `amount` of `key` (newly gained) from the Items page into its bag. Takes from the last
-- Items stack of that kind first. Returns move, or nil and "none" (nothing of it on the Items page: it went to
-- the hotbar or straight into the bag) or "full".
function M.routeStep(snap, items, bagRange, key, amount)
    if amount <= 0 then return nil, "done" end
    for i = items.last, items.first, -1 do
        local s = snap[i]
        if s and s.key == key then
            local m = moveFrom(snap, i, math.min(s.count, amount), bagRange)
            if m then return m end
            return nil, "full"
        end
    end
    return nil, "none"
end

-- The take-out key: everything in bag slot `from` to the Items page. Returns move, or nil and "empty" / "full".
function M.takeOutStep(snap, from, items)
    local s = snap[from]
    if not s then return nil, "empty" end
    local m = moveFrom(snap, from, s.count, items)
    if m then return m end
    return nil, "full"
end

return M
