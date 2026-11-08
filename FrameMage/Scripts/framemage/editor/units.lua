-- What counts as one movable element ("unit") on screen. The gold bars, click-to-select and PgUp / PgDn all use
-- this, so what you can click always matches what has a bar.
--
-- The game builds its HUD from user widgets inside user widgets, and the right thing to move isn't always the
-- outermost or the innermost. A game user widget is sorted by what's in its own tree:
--   draws something of its own (images, text)   -> one unit: everything inside moves with it
--                                                   (the compass and its markers) - unless what it draws is
--                                                   small next to the sub-elements it holds (the vitals
--                                                   bars' frame around the health bars and the upkeep
--                                                   circles): then it's a container, and they split apart
--   only wraps ONE list of entries               -> one unit (the hotbar and its 8 slots)
--   holds several lists / sub-elements, draws nothing itself
--                                                -> a container: each list and sub-element is its own unit
--                                                   (key hints and menu shortcuts; the inventory's frame
--                                                   around the hotbar)
--   nothing showing at all                       -> an empty unit (selected, it shows example content)
-- A list is a box / grid panel holding two or more user widgets (its entries); entries are never units.
-- Small building blocks (key icons, text wrappers: editor.ignoreClasses) belong to whoever contains them.
local M = {}

local W, geometry, names, S
local isAtomClass

-- Panels whose child user widgets are list entries.
M.LIST_PANELS = { VerticalBox = true, HorizontalBox = true, UniformGridPanel = true, GridPanel = true,
    WrapBox = true, ScrollBox = true, StackBox = true, DynamicEntryBox = true }

-- Widgets that draw something themselves.
M.VISUALS = { Image = true, CommonLazyImage = true, TextBlock = true, RichTextBlock = true, CommonTextBlock = true,
    ProgressBar = true, Throbber = true, CircularThrobber = true, EditableTextBox = true, Slider = true,
    NiagaraSystemWidget = false } -- effects come and go: not "content"

-- Pure: is this a list view (entries made at runtime, not in the widget tree)? Unit-tested.
function M.isListView(cls)
    return cls:find("ListView", 1, true) ~= nil or cls:find("TileView", 1, true) ~= nil
        or cls:find("TreeView", 1, true) ~= nil
end

-- Pure: group rectangles that sit close together (within `gap` of each other, directly or through others).
-- Returns a list of clusters, each a list of indices into rects. Unit-tested.
function M.cluster(rects, gap)
    local parent = {}
    for i = 1, #rects do parent[i] = i end
    local function find(i)
        while parent[i] ~= i do parent[i] = parent[parent[i]]; i = parent[i] end
        return i
    end
    local h = gap / 2
    for i = 1, #rects do
        for j = i + 1, #rects do
            local a, b = rects[i], rects[j]
            if a.left - h < b.right + h and b.left - h < a.right + h and a.top - h < b.bottom + h and b.top - h < a.bottom + h then
                parent[find(i)] = find(j)
            end
        end
    end
    local groups, order = {}, {}
    for i = 1, #rects do
        local r = find(i)
        if not groups[r] then groups[r] = {}; order[#order + 1] = r end
        table.insert(groups[r], i)
    end
    local out = {}
    for _, r in ipairs(order) do out[#out + 1] = groups[r] end
    return out
end

-- Pure: should a widget that draws something itself still be split into its sub-elements? Yes when its own
-- drawing covers less than half the area its sub-elements do. Unit-tested.
function M.ownIsMinor(ownArea, childArea, childCount)
    return childCount >= 2 and ownArea < 0.5 * childArea
end

-- Pure: the verdict for a scanned user widget. Unit-tested.
function M.verdict(scan)
    if scan.visuals > 0 then return "unit" end
    local lists, kids = #scan.lists, #scan.children
    if lists == 1 and kids == 0 then return "unit" end
    if lists == 0 and kids == 0 then return "empty" end
    return "container"
end

-- Pure: is this a designer's own name ("GameInputs") rather than a default one ("HorizontalBox_436")? Unit-tested.
local DEFAULT_NAMES = { Overlay = true, CanvasPanel = true, SizeBox = true, Border = true, ScaleBox = true }
function M.meaningfulName(name)
    if name:match("^%a+_%d+$") or name:match("_C_%d+$") then return false end -- HorizontalBox_436, X_C_2147...
    if M.LIST_PANELS[name] or DEFAULT_NAMES[name] then return false end
    return true
end

-- Pure: paths (lists of ids, outermost first) grouped by the branch they take below the deepest node they all
-- share; a path that ends at that node is its own group. Returns lists of indices. Unit-tested.
function M.groupByBranch(paths)
    if #paths == 0 then return {} end
    local shared = 0
    while true do
        local id = paths[1][shared + 1]
        if id == nil then break end
        local same = true
        for i = 2, #paths do
            if paths[i][shared + 1] ~= id then same = false break end
        end
        if not same then break end
        shared = shared + 1
    end
    local groups, order = {}, {}
    for i, p in ipairs(paths) do
        local k = p[shared + 1] or ""
        if not groups[k] then groups[k] = {}; order[#order + 1] = k end
        table.insert(groups[k], i)
    end
    local out = {}
    for _, k in ipairs(order) do out[#out + 1] = groups[k] end
    return out
end

-- Pure: is this a widget switcher (only its active child shows; the others keep their visibility)? Unit-tested.
function M.isSwitcher(cls) return cls:find("Switcher", 1, true) ~= nil end

local function classOf(w)
    local ok, c = pcall(W.className, w)
    return ok and c or ""
end

-- A switcher's showing child, or nil if it can't be told (then all its children are looked at).
local function activeChild(sw)
    local ok, a = pcall(function() return sw:GetActiveWidget() end)
    if ok and a and W.valid(a) then return a end
    local okI, i = pcall(function() return sw:GetActiveWidgetIndex() end)
    if okI and type(i) == "number" then return W.children(sw)[i + 1] end
    return nil
end

-- Look through one user widget's own tree (not into nested user widgets, which are reported as children).
function M.scan(uw)
    local out = { visuals = 0, lists = {}, children = {}, own = {}, listViews = {} }
    local node
    node = function(w)
        if not W.isVisible(w) then return false end
        local cls = classOf(w)
        if M.isSwitcher(cls) then
            -- the inactive pages (the build, craft, inventory... key legends) aren't on screen
            local a = activeChild(w)
            if a then W.walk(a, node, 0, 30) return false end
        end
        if W.isUserWidget(w) then
            if isAtomClass(cls) then
                out.visuals = out.visuals + 1
                if #out.own < 40 then out.own[#out.own + 1] = w end
            else out.children[#out.children + 1] = w end
            return false
        end
        if M.isListView(cls) then
            -- its entries are made at runtime and aren't in the tree: the list view itself is the content
            out.listViews[#out.listViews + 1] = w
            local okN, n = pcall(function() return w:GetNumItems() end)
            if okN and type(n) == "number" and n > 0 then out.visuals = out.visuals + 1 end
            return false
        end
        if M.LIST_PANELS[cls] then
            local entries = 0
            for _, c in ipairs(W.children(w)) do
                if W.isUserWidget(c) and not isAtomClass(classOf(c)) then entries = entries + 1 end
            end
            if entries >= 2 then
                out.lists[#out.lists + 1] = w
                return false
            end
        end
        if M.VISUALS[cls] then
            out.visuals = out.visuals + 1
            if #out.own < 40 then out.own[#out.own + 1] = w end
        end
        return true
    end
    for _, root in ipairs(W.children(uw)) do W.walk(root, node, 0, 30) end
    return out
end

local function union(a, b)
    if not a then return b end
    if not b then return a end
    return { left = math.min(a.left, b.left), top = math.min(a.top, b.top),
        right = math.max(a.right, b.right), bottom = math.max(a.bottom, b.bottom), accScale = a.accScale }
end

-- Where a widget's content actually is: the union of what it draws (images, text, small building blocks), so
-- a compass laid out on a full-screen canvas, or a strip inside a big empty box, is cropped to what you see.
-- Measuring every piece is costly, so the result is kept for a couple of seconds as fractions of the widget's
-- own box: it follows drags and scaling straight away. nil = nothing showing.
local contentCache = {} -- key -> { at, f = {x0, y0, x1, y1} } | { at, abs = rect } | { at, none = true }
M.CONTENT_SECONDS = 2.0

local function leafUnion(w)
    local out, n = nil, 0
    W.walk(w, function(x)
        n = n + 1
        if n > 600 or not W.isVisible(x) then return false end
        local cls = classOf(x)
        if M.VISUALS[cls] or M.isListView(cls) or (x ~= w and W.isUserWidget(x) and isAtomClass(cls)) then
            local r = geometry.rect(x)
            if r and geometry.area(r) >= 1 then out = union(out, r) end
            return false
        end
        return true
    end, 0, 40)
    return out
end

function M.contentRect(w)
    local r = geometry.rect(w)
    if not r then return nil end
    local okK, key = pcall(W.key, w)
    key = okK and key or tostring(w)
    local now = os.clock()
    local c = contentCache[key]
    local wdt, hgt = r.right - r.left, r.bottom - r.top
    if not c or now - c.at > M.CONTENT_SECONDS then
        local u = leafUnion(w)
        if not u then c = { at = now, none = true }
        elseif wdt > 0.5 and hgt > 0.5 then
            c = { at = now, f = { (u.left - r.left) / wdt, (u.top - r.top) / hgt,
                (u.right - r.left) / wdt, (u.bottom - r.top) / hgt } }
        else c = { at = now, abs = u } end
        contentCache[key] = c
    end
    if c.none then return nil end
    if c.abs then return c.abs end
    return { left = r.left + c.f[1] * wdt, top = r.top + c.f[2] * hgt, right = r.left + c.f[3] * wdt,
        bottom = r.top + c.f[4] * hgt, accScale = r.accScale }
end

-- Something changed shape (world change, a reset): measure content afresh.
function M.forgetContent() contentCache = {} end

local function listTitle(panel)
    local okN, name = pcall(W.name, panel)
    if okN and M.meaningfulName(name) then return names.pretty(name) end
    for _, c in ipairs(W.children(panel)) do
        if W.isUserWidget(c) then
            local cls = classOf(c):gsub("_C$", ""):gsub("^WBP_", "")
            return names.pretty(cls) .. " list"
        end
    end
    return "List"
end

-- Every unit on screen: { widget, title, rect (content), empty = bool, list = bool }.
function M.collect(roots, screenW, screenH)
    local out = {}
    local screenArea = screenW * screenH
    local seen = {}
    local function add(w, title, empty, isList, anchor, nameKey)
        local okK, key = pcall(W.key, w)
        key = okK and key or tostring(w)
        if seen[key] or #out >= S.handleMax then return end
        seen[key] = true
        local r = M.contentRect(w)
        -- nothing showing: place it where its content will appear (an empty list view), else its own box
        if not r and empty then r = (anchor and geometry.rect(anchor)) or geometry.rect(w) end
        if not r then return end
        if r.right < 0 or r.bottom < 0 or r.left > screenW or r.top > screenH then return end
        out[#out + 1] = { widget = w, title = title, key = key, rect = r, empty = empty or false,
            list = isList or false, area = geometry.area(r), nameKey = nameKey }
    end
    -- The deepest widget that contains all of `ws` (within uw), or uw itself.
    local function commonParent(uw, ws)
        local okU, uwFull = pcall(W.fullName, uw)
        local paths = {}
        for i, w in ipairs(ws) do
            local chain, cur, guard = {}, w, 0
            while cur and guard < 40 do
                local okF, full = pcall(W.fullName, cur)
                if not okF then break end
                table.insert(chain, 1, { w = cur, full = full })
                if okU and full == uwFull then break end
                cur, guard = W.parent(cur), guard + 1
            end
            paths[i] = chain
        end
        local best = uw
        for depth = 1, 40 do
            local first = paths[1][depth]
            if not first then break end
            for i = 2, #paths do
                local p = paths[i][depth]
                if not p or p.full ~= first.full then return best end
            end
            best = first.w
        end
        return best
    end

    local visit

    -- One element per group top: a game user widget is looked at in turn; anything else becomes an element, named
    -- after its nearest parent with a real name ("VitalsBarOverlay" -> "Vital Bars" via editor.renames), since a
    -- group's nearest common parent often has a default name ("Overlay_0").
    local function emit(uw, tops, depth)
        local okUF, uwFull = pcall(W.fullName, uw)
        for _, top in ipairs(tops) do
            if W.isUserWidget(top) and not isAtomClass(classOf(top)) then
                visit(top, depth + 1)
            else
                -- (stopping below uw: a piece split out of uw isn't named after uw itself; with no real name on the
                -- way it keeps its key, "HorizontalBox_436" -> "Menu Shortcuts" via editor.renames)
                local nameKey, cur, guard = nil, top, 0
                while cur and guard < 12 do
                    local okF, f = pcall(W.fullName, cur)
                    if okF and okUF and f == uwFull then break end
                    local okN, nm = pcall(W.name, cur)
                    if okN and M.meaningfulName(nm) then nameKey = nm break end
                    cur, guard = W.parent(cur), guard + 1
                end
                local okK, key = pcall(W.key, top)
                add(top, names.pretty(nameKey or (okK and key) or "?"), false, false, nil, nameKey or false)
            end
        end
    end

    -- The widgets from w up to (not including) uw, outermost first; nil if uw isn't above it.
    local function pathBelow(uw, w)
        local okU, uwFull = pcall(W.fullName, uw)
        if not okU then return nil end
        local chain, cur, guard = {}, w, 0
        while cur and guard < 40 do
            local okF, full = pcall(W.fullName, cur)
            if not okF then return nil end
            if full == uwFull then return chain end
            table.insert(chain, 1, { w = cur, full = full, cls = classOf(cur) })
            cur, guard = W.parent(cur), guard + 1
        end
        return nil
    end

    -- A widget forced to split (editor.forceSplit) whose pieces are all small building blocks (the world key legend:
    -- its key hints and its menu shortcuts are rows of key entries, side by side). Each building block belongs to
    -- its nearest row / grid; the rows are grouped by the branch they sit on, so pieces split however close they
    -- are. One piece showing (the key hints hidden) is still singled out. Returns true if it split.
    local function splitByStructure(uw, scan, depth)
        local pieces, seen = {}, {}
        for _, o in ipairs(scan.own) do
            local r = geometry.rect(o)
            local chain = r and geometry.area(r) >= 1 and pathBelow(uw, o)
            if chain and #chain > 0 then
                local cut = #chain
                for i = #chain, 1, -1 do
                    if M.LIST_PANELS[chain[i].cls] then cut = i break end
                end
                local piece = chain[cut]
                if not seen[piece.full] then
                    seen[piece.full] = true
                    local ids = {}
                    for i = 1, cut do ids[i] = chain[i].full end
                    pieces[#pieces + 1] = { w = piece.w, ids = ids }
                end
            end
        end
        if #pieces == 0 then return false end
        local paths = {}
        for i, p in ipairs(pieces) do paths[i] = p.ids end
        local tops = {}
        for _, g in ipairs(M.groupByBranch(paths)) do
            local ws = {}
            for _, i in ipairs(g) do ws[#ws + 1] = pieces[i].w end
            tops[#tops + 1] = (#ws == 1) and ws[1] or commonParent(uw, ws)
        end
        emit(uw, tops, depth)
        return true
    end

    -- A widget whose parts sit in separate groups on screen (the survival circles far left, the vital bars in the
    -- middle) becomes one element per group: each group's nearest common parent. Returns true if it split.
    local function splitByDistance(uw, scan, depth)
        local parts = {}
        local function part(w, r) if r and geometry.area(r) >= 1 then parts[#parts + 1] = { w = w, r = r } end end
        for _, o in ipairs(scan.own) do part(o, geometry.rect(o)) end
        -- a sub-element that is itself just a holder of separate parts (the input legend inside its frame, holding
        -- the key hints and the menu shortcuts) contributes those parts, so they can split apart too
        local function addChild(c, d)
            local cs = d < 3 and M.scan(c)
            local inner = cs and (#cs.lists + #cs.children + #cs.listViews)
            if cs and cs.visuals == 0 and inner and inner >= 2 then
                for _, l in ipairs(cs.lists) do part(l, geometry.rect(l)) end
                for _, l in ipairs(cs.listViews) do part(l, geometry.rect(l)) end
                for _, cc in ipairs(cs.children) do addChild(cc, d + 1) end
            else
                part(c, M.contentRect(c))
            end
        end
        for _, c in ipairs(scan.children) do addChild(c, 0) end
        for _, l in ipairs(scan.lists) do part(l, geometry.rect(l)) end
        for _, l in ipairs(scan.listViews) do part(l, geometry.rect(l)) end
        if #parts < 2 then return false end
        local rects = {}
        for i, p in ipairs(parts) do rects[i] = p.r end
        local groups = M.cluster(rects, S.splitGap)
        if #groups < 2 then return false end
        local okUF, uwFull = pcall(W.fullName, uw)
        local tops = {}
        for _, g in ipairs(groups) do
            local ws = {}
            for _, i in ipairs(g) do ws[#ws + 1] = parts[i].w end
            local top = (#ws == 1) and ws[1] or commonParent(uw, ws)
            local okT, topFull = pcall(W.fullName, top)
            if not okT or (okUF and topFull == uwFull) then return false end -- can't separate them: keep whole
            tops[#tops + 1] = top
        end
        emit(uw, tops, depth)
        return true
    end

    visit = function(uw, depth)
        if depth > 12 or not W.isVisible(uw) then return end
        local scan = M.scan(uw)
        local v = M.verdict(scan)
        -- widgets known to be holders of separate pieces (editor.forceSplit, by class), whatever their spacing: their
        -- sub-elements and lists, or (when every piece is a small building block) their rows of those
        if S.forceSplit and S.forceSplit[classOf(uw)] then
            if #scan.children + #scan.lists + #scan.listViews > 0 then v = "container"
            elseif splitByStructure(uw, scan, depth) then return end
        end
        if v ~= "container" then
            local r = M.contentRect(uw)
            if r and geometry.area(r) > screenArea * S.handleMaxScreenShare then v = "container" end
        end
        if v == "unit" and splitByDistance(uw, scan, depth) then return end
        if v == "unit" and #scan.children >= 2 then
            -- draws a little itself but mostly holds sub-elements (a frame around them): split it up
            local ownArea, childArea = 0, 0
            for _, o in ipairs(scan.own) do
                local r = geometry.rect(o)
                if r then ownArea = ownArea + geometry.area(r) end
            end
            for _, c in ipairs(scan.children) do
                local r = M.contentRect(c)
                if r then childArea = childArea + geometry.area(r) end
            end
            if M.ownIsMinor(ownArea, childArea, #scan.children) then v = "container" end
        end
        if v == "unit" or v == "empty" then
            local okK, key = pcall(W.key, uw)
            add(uw, names.pretty(okK and key or "?"), v == "empty", false, scan.listViews[1])
            return
        end
        for _, list in ipairs(scan.lists) do add(list, listTitle(list), false, true) end
        for _, child in ipairs(scan.children) do visit(child, depth + 1) end
    end
    for _, root in ipairs(roots) do
        if W.valid(root) then visit(root, 0) end
    end
    -- names that tell elements apart: "Player Upkeeps", not five "Notification Queue Widget"s
    local idx, keys = {}, {}
    for i, u in ipairs(out) do
        if not u.list and u.nameKey == nil then idx[#idx + 1] = i; keys[#keys + 1] = u.key end
    end
    for j, t in ipairs(names.titles(keys)) do out[idx[j]].title = t end
    -- the player's own names for elements (editor.renames: last part of the key -> title)
    for _, u in ipairs(out) do
        local last = u.nameKey or (u.key or ""):match("([^/]+)$")
        local bare = last and last:gsub("%*$", ""):gsub("_C$", "")
        if bare and S.renames and S.renames[bare] then u.title = S.renames[bare] end
    end
    return out
end

-- The unit that contains widget w (from a collection), smallest first; or nil.
function M.containing(units, w)
    local okF, full = pcall(W.fullName, w)
    if not okF then return nil end
    for _, u in ipairs(units) do
        local okU, uf = pcall(W.fullName, u.widget)
        if okU and uf == full then return u end
    end
    return nil
end

function M.init(widgets, geo, nm, settings, isAtom)
    W, geometry, names, S, isAtomClass = widgets, geo, nm, settings, isAtom
end

return M
