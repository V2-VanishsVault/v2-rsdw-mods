-- Developer, read only: the inventory screen's tab bar, as built by the game, once per inventory screen.
-- Groundwork for the Tool Belt tab (what the game's own tab buttons, the button group, the switcher and the
-- bodies look like live). Changes nothing. Checks every 2 s for the screen (one FindFirstOf), and writes
-- dumps/ui.txt the first time each screen is seen.
local M = {}

local ctx, log
-- Loaded here, not in init: belttab and bagmoves call M.findNav() even when this feature is switched off (its init
-- never runs then). Leaving it to init broke the Tool Belt tab and the take-out key on 2026-11-13.
local O = require("storagemage.core.objects")

local function try(fn, ...)
    local ok, v = pcall(fn, ...)
    if ok then return v end
    return nil
end

local lines = {}
local function add(fmt, ...) lines[#lines + 1] = string.format(fmt, ...) end

local function str(v)
    if v == nil then return "nil" end
    local t = type(v)
    if t == "string" or t == "number" or t == "boolean" then return tostring(v) end
    local s = try(function() return v:ToString() end)
    if s then return '"' .. s .. '"' end
    if O.valid(v) then return O.className(v) .. " " .. O.name(v) end
    return tostring(v)
end

local function num(arr) return try(function() return arr:GetArrayNum() end) or try(function() return #arr end) end

local function nameOf(w) return O.valid(w) and (O.name(w) .. " (" .. O.className(w) .. ")") or "nil" end

local function brushOf(img)
    if not O.valid(img) then return "no image" end
    local res = try(function() return img.Brush.ResourceObject end)
    local size = try(function() return img.Brush.ImageSize end)
    return string.format("%s res=%s size=%sx%s vis=%s", nameOf(img), O.valid(res) and O.name(res) or "none",
        tostring(size and try(function() return size.X end)), tostring(size and try(function() return size.Y end)),
        tostring(try(function() return img:GetVisibility() end)))
end

local function button(label, b)
    if not O.valid(b) then add("  %s: nil", label) return end
    add("  %s: %s", label, nameOf(b))
    add("    RadioValue=%s ButtonLabel=%s vis=%s parent=%s", str(O.get(b, "RadioValue")), str(O.get(b, "ButtonLabel")),
        tostring(try(function() return b:GetVisibility() end)), nameOf(try(function() return b:GetParent() end)))
    add("    ButtonIcon: %s", brushOf(O.get(b, "ButtonIcon")))
    add("    LabelImage: %s", brushOf(O.get(b, "LabelImage")))
    add("    SelectionImage: %s", brushOf(O.get(b, "SelectionImage")))
    add("    bHideRadio=%s bShowIndentWhenSelected=%s", str(O.get(b, "bHideRadio")),
        str(O.get(b, "bShowIndentWhenSelected")))
    -- Where the tab's icon lives: the radio check box's style (override or the check box's own), or an Image
    -- somewhere in the button's tree.
    add("    bOverrideCheckBoxStyle=%s", str(O.get(b, "bOverrideCheckBoxStyle")))
    local function style(label, st)
        if not st then add("    %s: none", label) return end
        for _, k in ipairs({ "UncheckedImage", "UncheckedHoveredImage", "CheckedImage", "CheckedHoveredImage" }) do
            local res = try(function() return st[k].ResourceObject end)
            local sz = try(function() return st[k].ImageSize end)
            add("    %s.%s: res=%s size=%sx%s", label, k, O.valid(res) and (O.className(res) .. " " .. O.name(res))
                or "none", tostring(sz and try(function() return sz.X end)), tostring(sz and try(function() return sz.Y end)))
        end
    end
    style("CheckBoxStyleOverride", O.get(b, "CheckBoxStyleOverride"))
    local cb = O.get(b, "RadioCheckBox")
    add("    RadioCheckBox: %s", nameOf(cb))
    if O.valid(cb) then style("RadioCheckBox.WidgetStyle", O.get(cb, "WidgetStyle")) end
    local tree = O.get(b, "WidgetTree")
    local function walk(w, depth)
        if not O.valid(w) or depth > 8 then return end
        local extra = ""
        if O.className(w) == "Image" or O.className(w):find("Image", 1, true) then extra = "  " .. brushOf(w) end
        add("    %s%s%s", string.rep("  ", depth), nameOf(w), extra)
        for i = 0, (try(function() return w:GetChildrenCount() end) or 0) - 1 do
            walk(try(function() return w:GetChildAt(i) end), depth + 1)
        end
        local content = try(function() return w:GetContent() end)
        if O.valid(content) and not try(function() return w:GetChildrenCount() end) then walk(content, depth + 1) end
    end
    add("    tree:")
    walk(tree and O.get(tree, "RootWidget"), 1)
end

local function dump(nav)
    lines = {}
    add("# Storage Mage inventory screen (%s)", os.date("%Y-%m-%d %H:%M:%S"))
    add("nav: %s", try(function() return nav:GetFullName() end) or "?")
    add("PagedInventoryComponent: %s", nameOf(O.get(nav, "PagedInventoryComponent")))
    add("tab buttons by field:")
    for _, f in ipairs({ "Button_Items", "Button_Runes", "Button_Ammunition", "Button_QuestItems" }) do
        button(f, O.get(nav, f))
    end
    local grp = O.get(nav, "CategoryButtonGroup")
    add("CategoryButtonGroup: %s name=%s selectOnHover=%s", nameOf(grp), str(O.get(grp, "RadioButtonGroupName")),
        str(O.get(grp, "bSelectOnHover")))
    local rb = O.get(grp, "RadioButtons")
    add("  RadioButtons: %s", tostring(rb and num(rb)))
    if rb then
        try(function() rb:ForEach(function(i, e)
            local w = e:get()
            add("    [%d] %s RadioValue=%s", i, nameOf(w), str(O.get(w, "RadioValue")))
        end) end)
    end
    add("  group children: %s", tostring(try(function() return grp:GetChildrenCount() end)))
    for i = 0, (try(function() return grp:GetChildrenCount() end) or 0) - 1 do
        add("    child %d: %s", i, nameOf(try(function() return grp:GetChildAt(i) end)))
    end
    local sw = O.get(nav, "InventorySwitcher")
    add("InventorySwitcher: %s widgets=%s active=%s", nameOf(sw), tostring(try(function() return sw:GetNumWidgets() end)),
        tostring(try(function() return sw:GetActiveWidgetIndex() end)))
    for i = 0, (try(function() return sw:GetChildrenCount() end) or 0) - 1 do
        local w = try(function() return sw:GetChildAt(i) end)
        add("    child %d: %s vis=%s", i, nameOf(w), tostring(w and try(function() return w:GetVisibility() end)))
    end
    local bodies = O.get(nav, "InventoryBodies")
    add("InventoryBodies: %s", tostring(bodies and num(bodies)))
    if bodies then
        try(function() bodies:ForEach(function(i, e)
            local b = e:get()
            local slots = O.get(b, "InventorySlots")
            local first = slots and try(function() return slots[1] end)
            add("    [%d] %s SlotType=%s RowCount=%s slots=%s firstSlot=%s grid=%s slotRef=%s", i, nameOf(b),
                str(O.get(b, "SlotType")), str(O.get(b, "RowCount")), tostring(slots and num(slots)),
                nameOf(first), nameOf(O.get(b, "SlotGridContainer")), str(O.get(b, "InventorySlotWidgetRef")))
            if O.valid(first) then add("        first slot InventoryPanel=%s", nameOf(O.get(first, "InventoryPanel"))) end
        end) end)
    end
    for _, f in ipairs({ "TabBackground", "ScrollBox_0", "LeftBG", "TabGroupOverlay" }) do
        local w = O.get(nav, f)
        add("%s: %s parent=%s", f, nameOf(w), nameOf(w and try(function() return w:GetParent() end)))
    end
    local cdo = try(function() return StaticFindObject(
        "/Game/UI/Inventory/WBP_Inventory_InventoryBody.Default__WBP_Inventory_InventoryBody_C") end)
    if not O.valid(cdo) then
        cdo = try(function() return FindFirstOf("WBP_Inventory_InventoryBody_C"):GetClass():GetCDO() end)
    end
    add("body class default: %s SlotType=%s RowCount=%s", cdo and (try(function() return cdo:GetFullName() end) or "?")
        or "not found", str(O.get(cdo, "SlotType")), str(O.get(cdo, "RowCount")))
    local tabCdo = try(function() return FindFirstOf("WBP_InventoryTabButton_C"):GetClass():GetFullName() end)
    add("tab button class: %s", tostring(tabCdo))
    local bodyCls = try(function() return FindFirstOf("WBP_Inventory_InventoryBody_C"):GetClass():GetFullName() end)
    add("body class: %s", tostring(bodyCls))
    ctx.fs.write(ctx.dir .. "dumps/ui.txt", table.concat(lines, "\n") .. "\n")
    log.info("uidump: wrote dumps/ui.txt (%d lines)", #lines)
end

-- FindFirstOf can return a template copy (a widget blueprint's own tree, a class default) that is never on
-- screen, so look at every copy: dump the first one that's in the viewport (or visible), and log once what the
-- candidates looked like while the inventory screen's API exists (the inventory was opened).
local seen, reported
local CLASSES = { "WBP_Inventory_VerticalNavigation_C", "InventoryMainPanelContent" }
-- The inventory screen's navigation widget that's on display (nil when the inventory is closed), plus every
-- candidate looked at. Also used by belttab. Never keep the result past this tick.
function M.findNav()
    local cands = {}
    for _, cls in ipairs(CLASSES) do
        local all = try(function() return FindAllOf(cls) end)
        for _, w in ipairs(all or {}) do
            if O.valid(w) then
                local id = try(function() return w:GetFullName() end) or "?"
                if not id:find("Default__", 1, true) then
                    local root = try(function() return w:GetOuter():GetOuter() end)
                    cands[#cands + 1] = { w = w, id = id, cls = cls,
                        vis = try(function() return w:IsVisible() end),
                        port = try(function() return w:IsInViewport() end),
                        rootPort = root and try(function() return root:IsInViewport() end) }
                end
            end
        end
    end
    local pick
    for _, c in ipairs(cands) do if c.vis == true and (c.port == true or c.rootPort == true) then pick = c break end end
    if not pick then for _, c in ipairs(cands) do if c.vis == true then pick = c break end end end
    return pick, cands
end

local function check()
    local pick, cands = M.findNav()
    local opened = O.valid(try(function() return FindFirstOf("InventoryUIAPI") end))
    if opened and not reported then
        reported = true
        log.info("uidump: %d candidates (%s)", #cands, pick and ("picked " .. pick.id) or "none on screen")
        for _, c in ipairs(cands) do
            log.info("uidump:   %s [%s] visible=%s inViewport=%s outerInViewport=%s", c.id, c.cls, tostring(c.vis),
                tostring(c.port), tostring(c.rootPort))
        end
    end
    if not pick then return end
    -- Dump again when the tab count changes (the Tool Belt tab added after the first dump).
    local key = pick.id .. "#" .. tostring(try(function() return pick.w.CategoryButtonGroup.RadioButtons:GetArrayNum() end))
    if key == seen then return end
    seen = key
    local ok, err = pcall(dump, pick.w)
    if not ok then log.warn("uidump failed: %s", tostring(err)) end
end

function M.init(c)
    ctx, log = c, c.log
    ctx.sched.every(2000, "ui dump", check)
end

return M
