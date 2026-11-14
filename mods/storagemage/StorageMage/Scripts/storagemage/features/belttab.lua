-- The Tool Belt tab on the inventory screen (Phase 2, first try). Client side: it only adds widgets, it never
-- touches an inventory. Once per inventory screen (checked every 2 s while the inventory is open):
--   1. a page body like the game's own (WBP_Inventory_InventoryBody_C), set to the Tool Belt's slot type and
--      2 rows of 8, added to the screen's page switcher and its InventoryBodies list;
--   2. a tab button like the game's own (WBP_InventoryTabButton_C), RadioValue = its page's index in the
--      switcher (4: after Items, Runes, Ammo, Quest), added to the tab group, and the group re-initialized so it
--      knows the new button (Initialize appends, so its list is emptied first).
-- The icon is the Items tab's for now (art comes later; Frame Mage restyles it when installed).
-- Every step is checked and reported to dumps/tab.txt; a failed step stops the build for that screen.
-- What the game's screen looks like: dumps/ui.txt (feature uidump), 2026-11-13.
local M = {}

local L = require("storagemage.layout")
local INVUI = require("storagemage.inventoryui")
local ART = require("storagemage.art")

M.ICON = "T_SM_Tab_ToolBelt" -- + _Normal / _Highlight: Art/default/, or a Frame Mage theme's storagemage/ folder
M.BODY_CLASS = "/Game/UI/Inventory/WBP_Inventory_InventoryBody.WBP_Inventory_InventoryBody_C"
M.BODY_CDO = "/Game/UI/Inventory/WBP_Inventory_InventoryBody.Default__WBP_Inventory_InventoryBody_C"
M.TAB_CLASS = "/Game/UI/Inventory/WBP_InventoryTabButton.WBP_InventoryTabButton_C"
M.GAME_TABS = 4 -- Items, Runes, Ammo, Quest: RadioValue 0..3 and switcher children 0..3
M.SLOTS_PER_ROW = 8

local ctx, log, O

local function try(fn, ...)
    local ok, v = pcall(fn, ...)
    if ok then return v end
    return nil
end

-- Pure: rows for a page of n slots (the game's bodies are 8 wide). Unit-tested.
function M.rows(n) return math.ceil(n / M.SLOTS_PER_ROW) end

local report = {}
local function note(fmt, ...)
    report[#report + 1] = string.format(fmt, ...)
    log.info("tab: %s", report[#report])
    if #report > 300 then table.remove(report, 1) end
    ctx.fs.write(ctx.dir .. "dumps/tab.txt", "# Storage Mage Tool Belt tab (" .. os.date("%Y-%m-%d %H:%M:%S") .. ")\n"
        .. table.concat(report, "\n") .. "\n")
end

local function num(arr) return arr and try(function() return arr:GetArrayNum() end) end

local function findValue(group, value)
    local found
    local rb = O.get(group, "RadioButtons")
    if rb then
        try(function() rb:ForEach(function(_, e)
            local w = e:get()
            if O.valid(w) and O.get(w, "RadioValue") == value then found = w end
        end) end)
    end
    return found
end

-- Runs a step; returns its result, or nil and notes the failure. `check` (optional) validates the result.
local function step(label, fn, check)
    local ok, v = pcall(fn)
    local good = ok and (check == nil or check(v))
    note("  %s: %s%s", label, good and "ok" or "FAILED", ok and "" or ("  " .. tostring(v)))
    if good then return v == nil and true or v end
    return nil
end

local function resName(o) return O.valid(o) and O.name(o) or "none" end

local function marginText(m)
    if not m then return "?" end
    return string.format("%s/%s/%s/%s", tostring(m.Left), tostring(m.Top), tostring(m.Right), tostring(m.Bottom))
end

-- Copies a widget's slot layout (padding, size rule, alignment) onto another widget's slot in the same panel,
-- through the slot's setters, and notes both before and after. Unit-tested with stand-in slots.
function M.copySlotLayout(from, to, noteFn)
    local a, b = from and try(function() return from.Slot end), to and try(function() return to.Slot end)
    if not (a and b) then noteFn("  tab spacing: no slot to copy (%s -> %s)", tostring(a ~= nil), tostring(b ~= nil)) return false end
    local pad = try(function() return a.Padding end)
    noteFn("  tab spacing: game tab padding %s, ours %s", marginText(pad), marginText(try(function() return b.Padding end)))
    local copied = {}
    if pad and try(function()
        b:SetPadding({ Left = pad.Left, Top = pad.Top, Right = pad.Right, Bottom = pad.Bottom })
        return true
    end) then copied[#copied + 1] = "padding" end
    local size = try(function() return a.Size end)
    if size and try(function() b:SetSize({ SizeRule = size.SizeRule, Value = size.Value }) return true end) then
        copied[#copied + 1] = "size"
    end
    local h, v = try(function() return a.HorizontalAlignment end), try(function() return a.VerticalAlignment end)
    if h and try(function() b:SetHorizontalAlignment(h) return true end) then copied[#copied + 1] = "h-align" end
    if v and try(function() b:SetVerticalAlignment(v) return true end) then copied[#copied + 1] = "v-align" end
    noteFn("  tab spacing: copied %s; ours now %s", #copied > 0 and table.concat(copied, ", ") or "nothing",
        marginText(try(function() return b.Padding end)))
    return #copied > 0
end

-- The tab's icon: a tab icon is its RadioCheckBox's style (T_Icon_<Name>_Normal when unselected, _Highlight when
-- selected, shown at 62x32). Runes, Ammo and Quest set it through CheckBoxStyleOverride (Items uses the check
-- box's own style), so: copy Runes' override (sizes, margins, sounds), put our two textures in its four brushes,
-- and push it to the check box, which took its style when the button was built. Also used on a theme change.
local appliedRev
function M.applyIcon(nav, tab)
    local base = O.get(nav, "Button_Runes")
    local pc = O.localController()
    local theme, rev = ART.theme()
    local nPath, hPath = ART.path(ctx, M.ICON .. "_Normal"), ART.path(ctx, M.ICON .. "_Highlight")
    note("  icon (theme %s, rev %s): %s | %s", tostring(theme), tostring(rev), tostring(nPath), tostring(hPath))
    if not (O.valid(base) and nPath and hPath and pc) then
        note("  icon: FAILED (Runes tab %s, art %s/%s): keeps the default icon", tostring(O.valid(base)),
            tostring(nPath ~= nil), tostring(hPath ~= nil))
        return false
    end
    local texN, errN = ART.load(nPath, pc)
    local texH, errH = ART.load(hPath, pc)
    if not (O.valid(texN) and O.valid(texH)) then
        note("  icon: textures FAILED to load (%s / %s)", tostring(errN or texN), tostring(errH or texH))
        return false
    end
    note("    textures %dx%d", try(function() return texN:Blueprint_GetSizeX() end) or -1,
        try(function() return texN:Blueprint_GetSizeY() end) or -1)
    local ok = step("icon in the tab's style override", function()
        tab.bOverrideCheckBoxStyle = true
        tab.CheckBoxStyleOverride = base.CheckBoxStyleOverride
        local st = tab.CheckBoxStyleOverride
        st.UncheckedImage.ResourceObject = texN
        st.UncheckedHoveredImage.ResourceObject = texN
        st.CheckedImage.ResourceObject = texH
        st.CheckedHoveredImage.ResourceObject = texH
    end, function()
        return O.get(tab, "bOverrideCheckBoxStyle") == true
            and resName(try(function() return tab.CheckBoxStyleOverride.CheckedImage.ResourceObject end)) == resName(texH)
    end)
    if not ok then
        note("    override reads back: unchecked=%s checked=%s", resName(try(function()
            return tab.CheckBoxStyleOverride.UncheckedImage.ResourceObject end)), resName(try(function()
            return tab.CheckBoxStyleOverride.CheckedImage.ResourceObject end)))
        return false
    end
    local cb = O.get(tab, "RadioCheckBox")
    local pushed = step("icon pushed to the check box (SetWidgetStyle)", function()
        cb:SetWidgetStyle(tab.CheckBoxStyleOverride)
    end, function()
        return resName(try(function() return cb.WidgetStyle.CheckedImage.ResourceObject end)) == resName(texH)
    end)
    if not pushed then
        pushed = step("icon pushed to the check box (WidgetStyle)", function()
            cb.WidgetStyle = tab.CheckBoxStyleOverride
        end, function()
            return resName(try(function() return cb.WidgetStyle.CheckedImage.ResourceObject end)) == resName(texH)
        end)
    end
    if pushed then appliedRev = rev or false end
    return pushed
end

-- Frame Mage theme switch (themeRev changed) while the screen is open: re-apply the icon to our tab, found again
-- by its RadioValue (widgets made with Create can't be named SM_...).
local function themeCheck(nav)
    if appliedRev == nil then return end
    local _, rev = ART.theme()
    if (rev or false) == appliedRev then return end
    local tab = findValue(O.get(nav, "CategoryButtonGroup"), M.GAME_TABS)
    if not O.valid(tab) then return end
    note("theme changed (rev %s -> %s): re-applying the icon", tostring(appliedRev), tostring(rev))
    M.applyIcon(nav, tab)
end

local function build(nav)
    local page = L.page("toolBelt")
    local value = M.GAME_TABS -- first page after the game's
    local group = O.get(nav, "CategoryButtonGroup")
    local switcher = O.get(nav, "InventorySwitcher")
    local bodies = O.get(nav, "InventoryBodies")
    if not (O.valid(group) and O.valid(switcher) and bodies) then
        note("screen not as expected (group %s, switcher %s, bodies %s): no tab", tostring(O.valid(group)),
            tostring(O.valid(switcher)), tostring(bodies ~= nil))
        return false
    end
    if findValue(group, value) then return true end -- already built on this screen
    local tabs = num(O.get(group, "RadioButtons"))
    local pagesNow = try(function() return switcher:GetChildrenCount() end)
    note("inventory screen %s: %s tabs, %s pages", try(function() return nav:GetFullName() end) or "?",
        tostring(tabs), tostring(pagesNow))
    if tabs ~= M.GAME_TABS or pagesNow ~= M.GAME_TABS then
        note("  expected %d tabs and %d pages (another mod's tabs?): no Tool Belt tab", M.GAME_TABS, M.GAME_TABS)
        return false
    end
    local pc = O.localController()
    local wbl = try(function() return StaticFindObject("/Script/UMG.Default__WidgetBlueprintLibrary") end)
    local bodyCls = try(function() return StaticFindObject(M.BODY_CLASS) end)
    local tabCls = try(function() return StaticFindObject(M.TAB_CLASS) end)
    local cdo = try(function() return StaticFindObject(M.BODY_CDO) end)
    if not (pc and O.valid(wbl) and O.valid(bodyCls) and O.valid(tabCls)) then
        note("  missing: controller %s, widget library %s, body class %s, tab class %s", tostring(pc ~= nil),
            tostring(O.valid(wbl)), tostring(O.valid(bodyCls)), tostring(O.valid(tabCls)))
        return false
    end
    local itemsBody = O.get(nav, "InventoryBody_Items")
    local itemsTab = O.get(nav, "Button_Items")

    -- 1. The page body. Create builds the class default's page first; keep that the 32-slot Items page (a large
    -- page there crashed other mods' Create), then set ours and rebuild its slots.
    local cdoType = O.get(cdo, "SlotType")
    if O.valid(cdo) and cdoType ~= 1 then
        step("body class default back to Items (was " .. tostring(cdoType) .. ")", function() cdo.SlotType = 1 end)
    end
    local body = step("create page body", function() return wbl:Create(pc, bodyCls, pc) end, O.valid)
    if not body then return false end
    if itemsBody then
        step("body API from Items", function() body.InventoryAPI = itemsBody.InventoryAPI end)
    end
    if not step("body SlotType " .. page.slotType .. ", " .. M.rows(page.slots) .. " rows", function()
        body.SlotType = page.slotType
        body.RowCount = M.rows(page.slots)
    end, function() return O.get(body, "SlotType") == page.slotType end) then return false end
    step("clear the default slots", function()
        local grid = O.get(body, "SlotGridContainer")
        if O.valid(grid) then grid:ClearChildren() end
        body.InventorySlots:Empty()
    end)
    if not step("build Tool Belt slots", function() body:InitializeContent() end,
        function() return num(O.get(body, "InventorySlots")) == page.slots end) then
        note("    slots now %s (want %d)", tostring(num(O.get(body, "InventorySlots"))), page.slots)
        return false
    end
    -- New slots don't know the screen they're on: empty ones would show stale tooltips.
    local panel = itemsBody and try(function() return itemsBody.InventorySlots[1].InventoryPanel end)
    if O.valid(panel) then
        step("slots' InventoryPanel", function()
            body.InventorySlots:ForEach(function(_, e) local s = e:get(); if O.valid(s) then s.InventoryPanel = panel end end)
        end)
    end
    if not step("add page to the switcher", function() switcher:AddChild(body) end,
        function() return try(function() return switcher:GetChildrenCount() end) == M.GAME_TABS + 1 end) then
        return false
    end
    step("add page to InventoryBodies", function() bodies[num(bodies) + 1] = body end,
        function() return num(bodies) == M.GAME_TABS + 1 end)

    -- 2. The tab button.
    local tab = step("create tab button", function() return wbl:Create(pc, tabCls, pc) end, O.valid)
    if not tab then return false end
    step("tab RadioValue " .. value, function() tab.RadioValue = value end,
        function() return O.get(tab, "RadioValue") == value end)
    M.applyIcon(nav, tab)
    if not step("add tab to the group", function() group:AddChild(tab) end,
        function() return try(function() return group:GetChildrenCount() end) == M.GAME_TABS + 1 end) then
        return false
    end
    -- AddChild gives our tab a fresh slot; the game's tabs have their spacing in theirs (ours sat further from the
    -- Quest tab than the game's tabs sit from each other, 2026-11-14). Copy the last game tab's slot layout.
    local lastGameTab = O.get(nav, "Button_QuestItems") or itemsTab
    M.copySlotLayout(lastGameTab, tab, note)
    step("re-initialize the group", function()
        group.RadioButtons:Empty()
        group:Initialize()
    end, function() return num(O.get(group, "RadioButtons")) == M.GAME_TABS + 1 end)
    note("  RadioButtons now %s; Tool Belt tab built", tostring(num(O.get(group, "RadioButtons"))))
    return true
end

-- Developer, once per screen: each tab's laid-out size and its check box's picture size and padding, to find why
-- our tab sits further along the row than the game's tabs sit from each other (2026-11-14).
local function vec(v) return v and string.format("%.1fx%.1f", v.X or -1, v.Y or -1) or "?" end
local function measureTabs(nav)
    local group = O.get(nav, "CategoryButtonGroup")
    local n = try(function() return group:GetChildrenCount() end) or 0
    note("tab sizes (row %s, slot class %s):", O.valid(group) and O.className(group) or "?",
        try(function() return O.className(group:GetChildAt(0).Slot) end) or "?")
    for i = 0, n - 1 do
        local t = try(function() return group:GetChildAt(i) end)
        if O.valid(t) then
            local cb = O.get(t, "RadioCheckBox")
            local st = try(function() return cb.WidgetStyle end)
            note("  %d %s: desired %s; check box desired %s, picture %s, padding %s; slot size rule %s",
                i, O.name(t), vec(try(function() return t:GetDesiredSize() end)),
                vec(try(function() return cb:GetDesiredSize() end)),
                vec(try(function() return st.UncheckedImage.ImageSize end)),
                marginText(try(function() return st.Padding end)),
                tostring(try(function() return t.Slot.Size.SizeRule end)))
        end
    end
end

local doneFor, measured = {}, {}
local function check()
    local pick = INVUI.findNav()
    if not pick then return end
    local id = pick.id
    if doneFor[id] ~= nil then
        if doneFor[id] then
            pcall(themeCheck, pick.w)
            if not measured[id] then measured[id] = true; pcall(measureTabs, pick.w) end
        end
        return
    end
    local ok, res = pcall(build, pick.w)
    if not ok then note("build error: %s", tostring(res)) end
    doneFor[id] = ok and res or false -- one try per screen: a failed build isn't repeated every 2 s
end

function M.init(c)
    ctx, log, O = c, c.log, c.objects
    ctx.sched.every(2000, "tool belt tab", check)
end

return M
