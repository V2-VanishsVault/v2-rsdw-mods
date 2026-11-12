-- Inventory: the inventory window in Frame Mage's look, and the hotbar on its own.
--
-- The game builds the hotbar as the first row of the inventory window (WBP_Inventory_MainPanel > BackgroundPanel
-- (WBP_Panel_Inventory) > ... > VerticalBox_98 > QuickAccessBar, then the tabs, the bag, the equipment, the
-- weight bar); with the inventory closed every row but the hotbar collapses, which is the HUD's hotbar. So moving
-- the window moved the hotbar, and the window's frame was drawn round it.
--
-- Hotbar (inventory.separateHotbar): two of them, showing the same slots. The window keeps its own row (where items
-- are arranged), shown only while the inventory is open. The HUD gets a second copy of the game's own hotbar
-- widget, made for the same player and filled by the game (InitializeContent), on the HUD's canvas beside the
-- window: it starts where the row sits and is moved on its own (layout key WBP_Inventory_QuickAccesBar, shown as
-- "Hotbar"). It shows whenever the game shows its hotbar.
--
-- Window (inventory.restyle): the game's two art widgets are re-skinned in place, so they keep the game's layering
-- and its show / hide on open and close: BackgroundPanel (the image) gets the player's panel stone, tiled;
-- MagicBorder gets the theme's frame of gold light. The theme's flourish is added centered on the top line and
-- shown whenever the window's background is.
local style = require("framemage.editor.style")
local themes = require("framemage.core.themes")
local measure = require("framemage.core.measure")

local M = {}

local ctx, W, log
local made = 0
local flourishes = {} -- fullName of the flourish -> { img, bg } (bg: the game's background image it follows)
local windows = {} -- fullName of a restyled window -> { panel, bg, border, flourish }
local copies = {} -- fullName of a HUD hotbar we made -> true (so its own creation isn't copied again)
local pairsOf = {} -- fullName of the window's hotbar -> { row, grid, copy, bg }

local HOTBAR = "WBP_Inventory_QuickAccesBar_C"
local MAIN = "WBP_Inventory_MainPanel_C"
local PANEL = "WBP_Panel_Inventory_C"
local CHEST_PANEL = "WBP_Panel_WorldActorInventory_C"

-- Pure: where the hotbar goes on the HUD canvas so it lands where the game lays it out inside the window. The
-- hotbar's slot is anchored at the point the window's anchors start from (anchors.Minimum), with alignment 0.
-- Per axis, the window's top-left is: anchored at a point -> anchor + position - alignment * size; stretched
-- between two anchors -> anchor + its left / top offset (which is what the slot's position holds). Then the
-- hotbar's place inside the window (delta) is added. Unit-tested.
function M.hotbarPosition(pos, align, size, delta, anchors)
    local function axis(p, a, s, d, k)
        local stretched = anchors and anchors.Minimum[k] ~= anchors.Maximum[k]
        if stretched then return p + d end
        return p - a * s + d
    end
    return axis(pos.X, align.X, size.X, delta.X, "X"), axis(pos.Y, align.Y, size.Y, delta.Y, "Y")
end

-- Pure: the render pivot (0..1 of its own size) that makes a widget at `offset` from the hotbar scale about the
-- hotbar's own pivot point, so the two stay together when the hotbar is scaled. Unit-tested.
function M.followPivot(offset, size, hotbarSize, hotbarPivot)
    local function axis(o, s, hs, hp)
        if not (s and s > 0) then return 0.5 end
        return (hs * hp - o) / s
    end
    return { X = axis(offset.X, size.X, hotbarSize.X, hotbarPivot.X), Y = axis(offset.Y, size.Y, hotbarSize.Y, hotbarPivot.Y) }
end

local function child(root, name, cls)
    local found
    W.walk(root, function(w)
        if found then return false end
        local okN, n = pcall(W.name, w)
        local okC, c = pcall(W.className, w)
        if okN and okC and n == name and (not cls or c == cls) then found = w return false end
        return true
    end, 0, 12)
    return found
end

-- What shows exactly while a window is open. Its background image won't do for the inventory: on closing, the
-- game fades it out over about 1.5 s and it counts as visible all that time, while the rest of the window goes at
-- once. The inventory's tabs row (TabGroupOverlay) goes at once with it; other windows fall back to the background.
function M.openSignal(root, bg)
    return child(root, "TabGroupOverlay") or bg
end

local function ancestorOfClass(w, cls)
    local cur, guard = W.parent(w), 0
    while cur and guard < 20 do
        local ok, c = pcall(W.className, cur)
        if ok and c == cls then return cur end
        cur, guard = W.parent(cur), guard + 1
    end
    return nil
end

-- The windows ------------------------------------------------------------------------------------------------------

-- The game's window panels restyled, by class: the inventory, and a chest (or any storage) opened in the world.
-- Both draw their background with a BackgroundPanel image (the material MI_Menu_PanelBG_Shared).
--   inventory: the stone goes straight onto that image (once; the game leaves it alone), its MagicBorder image
--              gets the frame.
--   chest:     its background image is never touched: the chest puts its own material back each time it opens and
--              then works on it (fading it in), and swapping it for the stone mid-way crashed the game. Our stone
--              is a layer of its own over it instead, with the window's contents moved back on top (taken out and
--              put back in the same overlay, slot settings kept), and our frame added (it has no border image).
--   crafting:  the crafting stations' window (the game's generic panel, WBP_Panel_C, which other station menus may
--              share): built like the inventory's, but treated like a chest's (own stone layer: the safe way for a
--              panel class not yet seen in every menu; so a frame of ours on top too, its MagicBorder being under
--              the stone). Its title banner sits inside, below the top line, so it has the flourish too.
--   processing: a processing station's panel (the Grill, beside the inventory): like crafting, its contents in a
--              canvas inside the overlay; its station name is inside, so it has the flourish.
-- tabs = its tab buttons (the inventory's Items / Runes / Arrows / Quest, the Build menu's categories) get our
-- buttons' border over them;
--   building:  the Build menu: like processing (contents in a canvas, no border image of its own).
--   lore popup: the lore popup's panel: its background is a plain image, Image_48 (T_ToolTip_Bg); bg = that name.
--   chat:      the open chat (its background blur stays under our stone); content = the layer holding its
--              contents (no PanelContent), fields = text box borders by name (the send box's).
-- checks = its checkboxes are dressed (the chest's options row); flourish = false: none on its top line.
M.WINDOWS = {
    [PANEL] = { kind = "inventory", tabs = true },
    [CHEST_PANEL] = { kind = "chest", ownStone = true, checks = true },
    WBP_Panel_C = { kind = "crafting", ownStone = true },
    WBP_Panel_Processing_C = { kind = "processing", ownStone = true },
    WBP_Panel_Building_C = { kind = "building", ownStone = true, tabs = true },
    WBP_Panel_LorePopup_C = { kind = "lore popup", ownStone = true, bg = "Image_48" },
    -- (its contents reach its edges, where our inset frame's lines are: they're pulled in by contentPad)
    WBP_OpenedChat_C = { kind = "chat", ownStone = true, bg = "BackgroundImage", content = "VerticalBox_27",
        fields = { "MessageSendBorder" }, contentPad = { 12, 12, 12, 12 } },
}

-- The stone on the window: on our own layer if it has one, else on the game's background image; filling it.
local function stoneOn(rec)
    local stone = style.stoneBrush(rec.panel)
    if not stone then return false end
    local target = rec.stone or rec.bg
    style.setBrush(target, stone)
    pcall(function()
        target.Slot:SetHorizontalAlignment(0)
        target.Slot:SetVerticalAlignment(0)
    end)
    return true
end

-- The window's art in the current stone and theme (again whenever either changes): stone, frame, flourish, and its
-- checkboxes and text boxes.

-- The inset of the inventory's border (its slot padding in the game's layout), shared with windows whose border
-- is ours, so every window's frame sits the same distance in from its edge. nil until the inventory is restyled.
local framePad

local function padOf(slot)
    local ok, p = pcall(function() local q = slot.Padding return { Left = q.Left, Top = q.Top, Right = q.Right, Bottom = q.Bottom } end)
    return ok and p or nil
end

-- Our own frame (a chest's) inset like the inventory's; the flourish sitting on the frame's top line.
-- (a class theme's wide border runs to the window's edges instead - style.framePadding; set again on every theme
-- change)
local function placeFrame(rec)
    local st = themes.style()
    if (framePad or st.frameToEdge) and W.valid(rec.border) then
        local p = style.framePadding(framePad or { Left = 0, Top = 0, Right = 0, Bottom = 0 }, st)
        pcall(function() rec.border.Slot:SetPadding(p) end)
    end
    if rec.flourish and W.valid(rec.flourish) then
        local top = style.flourishTop(themes.style())
        local p = W.valid(rec.border) and padOf(rec.border.Slot)
        if p then top = top + p.Top end
        pcall(function() rec.flourish.Slot:SetPadding({ Left = 0, Top = top, Right = 0, Bottom = 0 }) end)
    end
end

local function skin(rec)
    stoneOn(rec)
    local frame = rec.border and style.frameBrush(rec.panel)
    if frame and style.setBrush(rec.border, frame) then
        -- the game's border sits centered at its own size; the frame has to reach the window's edges
        pcall(function()
            rec.border.Slot:SetHorizontalAlignment(0)
            rec.border.Slot:SetVerticalAlignment(0)
        end)
        if not rec.ownFrame and not framePad then
            framePad = padOf(rec.border.Slot)
            if framePad then
                log.info("inventory: window frames inset %.0f / %.0f / %.0f / %.0f (the inventory's)", framePad.Left,
                    framePad.Top, framePad.Right, framePad.Bottom)
            end
        end
    end
    if rec.flourish and W.valid(rec.flourish) then
        local spec = style.flourishBrush(rec.panel)
        if spec then style.setBrush(rec.flourish, spec) end
    end
    placeFrame(rec)
    for _, t in ipairs(rec.tabs or {}) do t.state = nil end -- tab rims: repainted in the new theme on the next sync
    -- checkboxes: our pictures (made in restyle) in the new theme
    local boxes, fields = 0, 0
    for _, ck in ipairs(rec.checks or {}) do
        if W.valid(ck.img) then
            ck.brushes = style.checkBrushes(rec.panel, ck.w, ck.h)
            ck.state = nil -- repaint on the next sync
            if ck.brushes then boxes = boxes + 1 end
        end
    end
    for _, b in ipairs(rec.fields or {}) do
        if W.valid(b) and style.field(b, rec.panel) then fields = fields + 1 end
    end
    return frame ~= nil, boxes, fields
end

-- A checkbox drawn our way: the game's CheckBox is made invisible (render opacity 0: it still takes clicks, focus
-- and plays its sounds) and our picture sits over it, following its state (syncWindows). The picture goes into
-- the row that holds the checkbox, straight after it, pulled back over it by its own width; so the checkbox has to
-- be the last thing in a horizontal row (it is, in the chest's options). Returns the record, or nil + why.
local function coverCheck(cb, worldContext)
    local dom = W.parent(cb) -- the game's checkbox widget (WBP_DOMCheckbox) whose root the CheckBox is
    local row = dom and W.parent(dom)
    local okR, rcls = pcall(W.className, row)
    if not (row and okR and rcls == "HorizontalBox") then return nil, "not in a horizontal row" end
    local okN, n = pcall(function() return row:GetChildrenCount() end)
    local okI, i = pcall(function() return row:GetChildIndex(dom) end)
    if not (okN and okI and i == n - 1) then return nil, "not the last in its row" end
    local w, h = 24, 24
    pcall(function()
        dom:ForceLayoutPrepass()
        local d = dom:GetDesiredSize()
        if d.X > 0 and d.Y > 0 then w, h = d.X, d.Y end
    end)
    local brushes = style.checkBrushes(worldContext, w, h)
    if not brushes then return nil, "no checkbox art in the theme" end
    local tree = W.owner(row) and W.owner(row).WidgetTree
    if not tree then return nil, "no widget tree" end
    made = made + 1
    local img = StaticConstructObject(StaticFindObject("/Script/UMG.Image"), tree, FName("FM_Check_" .. made))
    style.setBrush(img, brushes.off)
    pcall(function() img:SetVisibility(3) end) -- not hit-testable: clicks go to the real checkbox under it
    local s = row:AddChildToHorizontalBox(img)
    local pad = { Left = 0, Right = 0 }
    pcall(function() pad = dom.Slot.Padding end)
    s:SetPadding({ Left = -(w + (pad.Right or 0)), Top = 0, Right = pad.Right or 0, Bottom = 0 })
    s:SetVerticalAlignment(2) -- center, as the checkbox is
    pcall(function() cb:SetRenderOpacity(0) end)
    return { cb = cb, img = img, w = w, h = h, brushes = brushes }
end

-- Every 100 ms: each window's stone stays on (a chest puts its own back when it opens), and each covered
-- checkbox shows its state.
-- Tab buttons with our buttons' border: the inventory's (WBP_InventoryTabButton: Items, Runes, Arrows, Quest) and
-- the Build menu's categories (WBP_Building_NavigableTabButton). Neither can have its own pictures swapped (the
-- inventory's tile is a CheckBox's), so the border (nothing inside it) is laid over the tile, in the button's own
-- overlay, at the tile's size; brighter on the selected tab. Per kind: the tile it sits on and how to tell the
-- selected one.
local TABS = {
    -- (its picture is 62 x 32, but the tile it draws is a little narrower and a little taller - measured in game:
    -- the border is drawn 9 narrower and 1 taller, centered on the tile; 2 lower sat on the panel's separator)
    WBP_InventoryTabButton_C = { anchor = "RadioCheckBox", anchorClass = "CheckBox", selected = "checkbox",
        inset = { 9, -1 } },
    -- (the selected one shows the game's own animated gold border: ours steps aside for it)
    WBP_Building_NavigableTabButton_C = { anchor = "IconBg", selected = "SelectedImage", hideSelected = true },
}

-- Pure: padding with more added on each side (left, top, right, bottom); unchanged without any. Unit-tested.
function M.addPadding(p, extra)
    if not extra then return p end
    return { Left = p.Left + (extra[1] or 0), Top = p.Top + (extra[2] or 0), Right = p.Right + (extra[3] or 0),
        Bottom = p.Bottom + (extra[4] or 0) }
end

-- Pure: the slot padding that moves something centered in an overlay by `offset` (x, y units): padding on one
-- side shifts the center by half of it. Unit-tested.
function M.offsetPadding(offset)
    local dx, dy = offset[1] or 0, offset[2] or 0
    return { Left = math.max(0, 2 * dx), Top = math.max(0, 2 * dy), Right = math.max(0, -2 * dx),
        Bottom = math.max(0, -2 * dy) }
end

-- Pure: how our border shows on a tab: "hidden" (selected, where the game draws its own selection border),
-- "bright" (selected) or "plain". Unit-tested.
function M.tabLook(selected, hideSelected)
    if selected then return hideSelected and "hidden" or "bright" end
    return "plain"
end

-- Pure: a tile size made smaller by an inset (width, height); unchanged without one, never below 4. Unit-tested.
function M.insetSize(w, h, inset)
    if not (w and h) then return w, h end
    if not inset then return w, h end
    return math.max(4, w - inset[1]), math.max(4, h - inset[2])
end

-- The size of a tab's tile: a checkbox's picture, or an image's brush; else its laid-out size.
local function tileSize(anchor)
    local w, h
    pcall(function()
        local sz = anchor.WidgetStyle.UncheckedImage.ImageSize
        if sz.X > 0 and sz.Y > 0 then w, h = sz.X, sz.Y end
    end)
    if not w then
        pcall(function()
            local sz = anchor.Brush.ImageSize
            if sz.X > 0 and sz.Y > 0 then w, h = sz.X, sz.Y end
        end)
    end
    if not w then
        pcall(function()
            anchor:ForceLayoutPrepass()
            local d = anchor:GetDesiredSize()
            if d.X > 0 and d.Y > 0 then w, h = d.X, d.Y end
        end)
    end
    return w, h
end

local function rimTabs(panel)
    local out = {}
    W.walk(panel, function(w)
        local ok, cls = pcall(W.className, w)
        local kind = ok and TABS[cls]
        if not kind then return true end
        local anchor, tree = child(w, kind.anchor, kind.anchorClass), w.WidgetTree
        local overlay = anchor and W.parent(anchor)
        local okO, ocls = pcall(W.className, overlay)
        -- (a tab that already has our border is left alone: this runs again for tabs added later)
        local done = false
        for _, k in ipairs(overlay and W.children(overlay) or {}) do
            local okN, n = pcall(W.name, k)
            if okN and n:sub(1, 10) == "FM_TabRim_" then done = true end
        end
        if anchor and tree and okO and ocls == "Overlay" and not done then
            made = made + 1
            local img = StaticConstructObject(StaticFindObject("/Script/UMG.Image"), tree, FName("FM_TabRim_" .. made))
            pcall(function() img:SetVisibility(3) end)
            local w0, h0 = tileSize(anchor)
            local tw, th = M.insetSize(w0, h0, kind.inset)
            local s = overlay:AddChildToOverlay(img)
            s:SetHorizontalAlignment(2) -- centered on the tile, at its size
            s:SetVerticalAlignment(2)
            if kind.offset then s:SetPadding(M.offsetPadding(kind.offset)) end
            out[#out + 1] = { cb = anchor, img = img, w = tw, h = th, kind = kind,
                mark = kind.selected ~= "checkbox" and child(w, kind.selected) or nil }
        end
        return false
    end, 0, 30)
    return out
end

-- Is this tab the selected one?
local function tabSelected(t)
    if t.kind.selected == "checkbox" then
        local ok, v = pcall(function() return t.cb:IsChecked() end)
        return ok and v == true
    end
    local ok, v = pcall(function() return t.mark:IsVisible() end)
    return ok and v == true
end

local function checkedOf(cb)
    local ok, v = pcall(function() return cb:IsChecked() end)
    if ok and type(v) == "boolean" then return v end
    local okS, st = pcall(function() return cb:GetCheckedState() end)
    if okS and type(st) == "number" then return st == 1 end -- ECheckBoxState: 0 unchecked, 1 checked
    return nil
end

local warnedState = false
-- Every 100 ms: our own stone layer shows exactly when the game's background does, and each covered checkbox
-- shows its state.
local function syncWindows()
    for full, rec in pairs(windows) do
        if not (W.valid(rec.panel) and W.valid(rec.bg)) then
            windows[full] = nil
        else
            local okV, v = pcall(function() return rec.bg:IsVisible() end)
            local shown = okV and v == true
            if rec.stone and W.valid(rec.stone) then
                local want = shown and 3 or 1
                pcall(function() if rec.stone:GetVisibility() ~= want then rec.stone:SetVisibility(want) end end)
            end
            if shown and not rec.shown then
                -- just opened: the frame inset (if the inventory's is known by now), fresh checkbox pictures and
                -- tab rims
                placeFrame(rec)
                for _, ck in ipairs(rec.checks or {}) do ck.state = nil end
                for _, t in ipairs(rec.tabs or {}) do t.state = nil end
            end
            rec.shown = shown
            -- tab rims: brighter on the selected tab (fetched fresh, like the checkbox pictures)
            for _, t in ipairs(rec.tabs or {}) do
                if W.valid(t.cb) and W.valid(t.img) then
                    local on = tabSelected(t)
                    if on ~= t.state then
                        local look = M.tabLook(on, t.kind.hideSelected)
                        if look == "hidden" then
                            pcall(function() t.img:SetVisibility(1) end)
                            t.state = on
                        else
                            local br = style.rimBrush(rec.panel, look == "bright", t.w, t.h)
                            if br and style.setBrush(t.img, br) then
                                pcall(function() t.img:SetVisibility(3) end)
                                t.state = on
                            end
                        end
                    end
                end
            end
            for _, ck in ipairs(rec.checks or {}) do
                if W.valid(ck.cb) and W.valid(ck.img) and ck.brushes then
                    local checked = checkedOf(ck.cb)
                    if checked == nil and not warnedState then
                        warnedState = true
                        log.warn("inventory: couldn't read a checkbox's state; its picture may not follow it")
                    end
                    local okH, hovered = pcall(function() return ck.cb:IsHovered() end)
                    local want = style.checkState(checked == true, okH and hovered == true)
                    if want ~= ck.state then
                        -- the pictures are fetched afresh every time: a texture we load is only kept alive while
                        -- something shows it, so one held on to while hidden can be collected (and then draws as a
                        -- plain white square); the cache reloads a collected one
                        local br = style.checkBrushes(rec.panel, ck.w, ck.h)
                        if br and style.setBrush(ck.img, br[want]) then ck.state = want end
                    end
                end
            end
        end
    end
end

-- The window's checkboxes and the borders round its text boxes.
local function controlsOf(panel)
    local checks, fields = {}, {}
    W.walk(panel, function(w)
        local ok, cls = pcall(W.className, w)
        if not ok then return true end
        if cls == "CheckBox" then checks[#checks + 1] = w return false end
        if cls == "EditableText" or cls == "EditableTextBox" then
            local p = W.parent(w)
            local okP, pcls = pcall(W.className, p)
            if okP and pcls == "Border" then fields[#fields + 1] = p end
            return false
        end
        return true
    end, 0, 30)
    return checks, fields
end

local function restyle(panel, spec)
    local kind = spec.kind
    local bg = child(panel, spec.bg or "BackgroundPanel", "Image")
    if not bg then log.warn("inventory: the %s window's background image wasn't found; left as the game's", kind) return end
    local overlay = W.parent(bg)
    local tree = panel.WidgetTree
    local okC, ocls = pcall(W.className, overlay)
    if not (overlay and okC and ocls == "Overlay" and tree) then
        log.warn("inventory: the %s window isn't built as expected; left as the game's", kind)
        return
    end
    local function new(cls)
        made = made + 1
        return StaticConstructObject(StaticFindObject("/Script/UMG." .. cls), tree, FName("FM_Win" .. cls .. "_" .. made))
    end
    -- a window with a stone layer of ours gets a frame of ours on top too: its own border image (if any) is under
    -- that stone, so it's left alone, hidden by it
    local rec = { panel = panel, bg = bg, kind = kind,
        border = (not spec.ownStone) and child(panel, "MagicBorder", "Image") or nil }
    if spec.ownStone then
        -- our stone over the game's background (left untouched), then the window's contents moved back on top of
        -- it: taken out of this overlay and put back in it, with their slot settings kept
        local stone = new("Image")
        pcall(function() stone:SetVisibility(3) end)
        local ss = overlay:AddChildToOverlay(stone)
        ss:SetHorizontalAlignment(0)
        ss:SetVerticalAlignment(0)
        rec.stone = stone
        -- what holds the contents in this overlay: PanelContent itself (inventory, chest, crafting) or the panel
        -- it sits in (a processing station's canvas)
        local holder = child(panel, spec.content or "PanelContent")
        local ovFull = W.fullName(overlay)
        local guard = 0
        while holder and guard < 8 do
            local okP, pf = pcall(function() return W.fullName(W.parent(holder)) end)
            if not okP then holder = nil break end
            if pf == ovFull then break end
            holder, guard = W.parent(holder), guard + 1
        end
        if holder and guard < 8 then
            local okM, merr = pcall(function()
                local cs = holder.Slot
                local pad, h, v = cs.Padding, cs.HorizontalAlignment, cs.VerticalAlignment
                local keep = M.addPadding({ Left = pad.Left, Top = pad.Top, Right = pad.Right, Bottom = pad.Bottom },
                    spec.contentPad)
                holder:RemoveFromParent()
                local ns = overlay:AddChildToOverlay(holder)
                ns:SetPadding(keep)
                ns:SetHorizontalAlignment(h)
                ns:SetVerticalAlignment(v)
            end)
            if not okM then log.warn("inventory: the %s window's contents couldn't go over its stone: %s", kind, tostring(merr)) end
        else
            log.warn("inventory: the %s window's contents weren't found; its stone may cover them", kind)
        end
    end
    if not rec.border then
        -- no edge of its own: ours, stretched over the window (drawn over its contents, but it's only a hairline)
        local img = new("Image")
        pcall(function() img:SetVisibility(3) end)
        local s = overlay:AddChildToOverlay(img)
        s:SetHorizontalAlignment(0)
        s:SetVerticalAlignment(0)
        rec.border = img
        rec.ownFrame = true
    end
    local found
    found, rec.fields = controlsOf(panel)
    -- text boxes whose border isn't the text's own parent (the chat's send box), by name
    for _, name in ipairs(spec.fields or {}) do
        local b = child(panel, name)
        if b then rec.fields[#rec.fields + 1] = b end
    end
    rec.checks = {}
    rec.tabs = spec.tabs and rimTabs(panel) or nil
    if not spec.checks then found = {} end -- only the chest's options row has checkboxes to dress
    for _, cb in ipairs(found) do
        local ck, why = coverCheck(cb, panel)
        if ck then rec.checks[#rec.checks + 1] = ck
        else log.warn("inventory: a %s checkbox is left as the game's (%s)", kind, tostring(why)) end
    end
    windows[W.fullName(panel)] = rec
    local framed, boxes, fields = skin(rec)
    -- the flourish, centered on the top line (over the window's other layers: it mostly sits above the window)
    local img = spec.flourish ~= false and style.flourish(new, panel) or nil
    if img then
        local slot = overlay:AddChildToOverlay(img)
        slot:SetHorizontalAlignment(2) -- center
        slot:SetVerticalAlignment(1)   -- top
        slot:SetPadding({ Left = 0, Top = style.flourishTop(themes.style()), Right = 0, Bottom = 0 })
        flourishes[W.fullName(img)] = { img = img, bg = M.openSignal(panel, bg), art = bg }
        rec.flourish = img
    end
    placeFrame(rec)
    if rec.tabs then
        local t1 = rec.tabs[1]
        log.info("inventory: %d tab buttons given our border (%s)", #rec.tabs,
            t1 and t1.w and string.format("%.0f x %.0f", t1.w, t1.h) or "theme size")
    end
    log.info("inventory: %s window restyled (stone %s, %s, %s, %d checkboxes, %d text boxes)", kind,
        tostring(ctx.settings.stone), framed and "gold frame" or "game frame", img and "flourish" or "no flourish",
        boxes, fields)
end

-- Windows with no background of their own --------------------------------------------------------------------

-- Some station windows have no panel at all: the Enchanting window places its title banner and its contents
-- straight on a canvas over the world (WBP_Panel_Enchanting is a plain CanvasPanel). They get a window of ours on
-- that canvas: the stone behind everything (lowest ZOrder) and the frame and flourish over it (highest), round the
-- space its contents take up (from the layout, so it works while the window is hidden) plus a margin.
M.BARE = {
    WBP_Enchanting_MainPanel_C = { kind = "enchanting", canvas = "WBP_Panel_Enchanting", pad = 24 },
}

-- Pure: the box round `rects` (layout units) relative to `origin` (the canvas's own top-left), grown by `pad` on
-- every side: { x, y, w, h }; nil without rects. Unit-tested.
function M.paddedBounds(rects, origin, pad)
    local l, t, r, b
    for _, q in ipairs(rects) do
        l = l and math.min(l, q.left) or q.left
        t = t and math.min(t, q.top) or q.top
        r = r and math.max(r, q.right) or q.right
        b = b and math.max(b, q.bottom) or q.bottom
    end
    if not l then return nil end
    pad = pad or 0
    return { x = l - origin.left - pad, y = t - origin.top - pad, w = r - l + 2 * pad, h = b - t + 2 * pad }
end

local bareBox, flourishSpot
local bare = {} -- fullName of the window -> { panel, stone, frame, flourish }

-- The box (canvas units) round everything drawn inside the window's canvas, plus its margin. Every piece inside
-- is measured, not just the canvas's own children: the Enchanting body is a canvas whose own size doesn't cover
-- what it places (measuring only the children gave just the title banner). Our own layers are left out.
bareBox = function(canvas, spec)
    local lc = measure.layoutRect(canvas)
    if not lc then return nil end
    local rects = {}
    for _, c in ipairs(W.children(canvas)) do
        local okN, n = pcall(W.name, c)
        if not (okN and tostring(n):find("^FM_")) then
            W.walk(c, function(x)
                if not W.isVisible(x) then return false end
                local r = measure.layoutRect(x)
                if r and r.right > r.left and r.bottom > r.top then rects[#rects + 1] = r end
                return true
            end, 0, 12)
        end
    end
    return M.paddedBounds(rects, lc, spec.pad)
end

-- Pure: the frame's box round the stone's, grown by the theme's frameOutset (wide borders grow outward).
-- Unit-tested.
function M.frameBox(box, outset)
    local o = outset or 0
    return { x = box.x - o, y = box.y - o, w = box.w + 2 * o, h = box.h + 2 * o }
end

-- Where the flourish goes on the frame's top line (box = the stone's box): { x, y, w, h }.
flourishSpot = function(box)
    local st = themes.style()
    local size = st.flourishSize or { 64, 32 }
    local fb = M.frameBox(box, st.frameOutset)
    return { x = fb.x + (fb.w - size[1]) / 2, y = fb.y + style.flourishTop(st), w = size[1], h = size[2] }
end

-- Pure: has the window's box moved or changed size by more than a unit? Unit-tested.
function M.boxChanged(a, b)
    if not (a and b) then return a ~= b end
    return math.abs(a.x - b.x) > 1 or math.abs(a.y - b.y) > 1 or math.abs(a.w - b.w) > 1 or math.abs(a.h - b.h) > 1
end

-- While a bare window shows, keep our window round what it holds (it's laid out only once it's on screen).
local function syncBare()
    for full, rec in pairs(bare) do
        if not (W.valid(rec.panel) and W.valid(rec.canvas)) then
            bare[full] = nil
        elseif W.isVisible(rec.canvas) then
            local okB, box = pcall(bareBox, rec.canvas, rec.spec)
            if okB and box and box.w > 0 and M.boxChanged(rec.box, box) then
                rec.box = box
                pcall(function()
                    local fb = M.frameBox(box, themes.style().frameOutset)
                    for _, pair in ipairs({ { rec.stoneSlot, box }, { rec.frameSlot, fb } }) do
                        pair[1]:SetPosition({ X = pair[2].x, Y = pair[2].y })
                        pair[1]:SetSize({ X = pair[2].w, Y = pair[2].h })
                    end
                    if rec.flourishSlot then
                        local p = flourishSpot(box)
                        rec.flourishSlot:SetPosition({ X = p.x, Y = p.y })
                    end
                end)
                log.info("inventory: %s window refitted (%.0f x %.0f)", rec.kind, box.w, box.h)
            end
        end
    end
end

local function restyleBare(main, spec)
    local full = W.fullName(main)
    if bare[full] then return end
    local canvas = child(main, spec.canvas, "CanvasPanel")
    local tree = main.WidgetTree
    local lc = canvas and measure.layoutRect(canvas)
    if not (canvas and tree and lc) then
        log.warn("inventory: the %s window isn't built as expected; left as the game's", spec.kind)
        return
    end
    local box = bareBox(canvas, spec)
    if not box then log.warn("inventory: the %s window's contents couldn't be measured", spec.kind) return end
    local function place(img, x, y, w, h, z)
        pcall(function() img:SetVisibility(3) end)
        local s = canvas:AddChildToCanvas(img)
        s:SetAutoSize(false)
        s:SetPosition({ X = x, Y = y })
        s:SetSize({ X = w, Y = h })
        s:SetZOrder(z)
        return s
    end
    local function new(cls)
        made = made + 1
        return StaticConstructObject(StaticFindObject("/Script/UMG." .. cls), tree, FName("FM_Bare" .. cls .. "_" .. made))
    end
    local rec = { panel = main, kind = spec.kind, canvas = canvas, spec = spec, box = box }
    rec.stone, rec.frame = new("Image"), new("Image")
    rec.stoneSlot = place(rec.stone, box.x, box.y, box.w, box.h, -100)
    local fb = M.frameBox(box, themes.style().frameOutset)
    rec.frameSlot = place(rec.frame, fb.x, fb.y, fb.w, fb.h, 1000)
    local fl = style.flourish(new, main)
    if fl then
        local p = flourishSpot(box)
        rec.flourishSlot = place(fl, p.x, p.y, p.w, p.h, 1001)
        rec.flourish = fl
    end
    bare[full] = rec
    -- art (again on a stone or theme change)
    rec.skin = function()
        local stone = style.stoneBrush(main)
        if stone then style.setBrush(rec.stone, stone) end
        local frame = style.frameBrush(main)
        if frame then style.setBrush(rec.frame, frame) end
        local fb = rec.flourish and style.flourishBrush(main)
        if fb then style.setBrush(rec.flourish, fb) end
    end
    rec.skin()
    log.info("inventory: %s window given a window of ours (%.0f x %.0f, stone %s)", spec.kind, box.w, box.h,
        tostring(ctx.settings.stone))
end

-- Tooltips -----------------------------------------------------------------------------------------------------

-- The game's tooltip panel (WBP_Panel_Tooltip: the chest options' tips, and others built on it) as a band of dark
-- glass edged top and bottom with light, a flourish on each line (the bottom one upside down). Like a chest
-- window, its own art is never touched (PanelImage is a material the game made for it): it's made invisible
-- (opacity 0, kept so) and our band is a layer over it, with the tip's contents moved back on top.
M.TOOLTIP = "WBP_Panel_Tooltip_C"
local tips = {} -- fullName -> { panel, art, band, top, bottom }

-- The banner some tooltips show a time on (a status effect's: "06:46"), the game's beige T_Tooltip_Banner_Bg: on
-- the theme's own (ui/tip_banner.png) when it has one, its lettering light to read on it; the game's again when not.
M.BANNERS = { T_Tooltip_Banner_Bg = true }
local loggedTipArt = {}

local function brushTexOf(w)
    local ok, tex = pcall(function() return w.Brush.ResourceObject end)
    if not (ok and tex) then ok, tex = pcall(function() return w.Background.ResourceObject end) end
    if ok and tex and W.valid(tex) then
        local okN, n = pcall(W.name, tex)
        return tex, okN and n or nil
    end
    return nil, nil
end

local function findBanners(t)
    local owner = W.owner(t.panel)
    if not owner then return end
    t.banners = t.banners or {}
    local okC, ocls = pcall(W.className, owner)
    local seen = {}
    W.walk(owner, function(w)
        local okK, cls = pcall(W.className, w)
        if okK and (cls == "Image" or cls == "Border" or cls == "CommonLazyImage") then
            local tex, n = brushTexOf(w)
            if n then seen[#seen + 1] = W.name(w) .. "=" .. n end
            if n and M.BANNERS[n] and not t.banners[W.fullName(w)] then
                t.banners[W.fullName(w)] = { w = w, tex = tex, cls = cls }
            end
        end
        return true
    end)
    local key = okC and ocls or "?"
    if not loggedTipArt[key] then
        loggedTipArt[key] = true
        log.info("inventory: tooltip %s pictures: %s", key, table.concat(seen, ", "))
    end
end

local function themeBanners(t)
    local s = themes.style()
    local path = themes.find("ui/tip_banner.png")
    local art = path and ctx.features.art and ctx.features.art.loadFile(path, t.panel)
    for _, b in pairs(t.banners or {}) do
        if W.valid(b.w) then
            if art then
                local spec = style.brushSpec(art, "box", 128, 28, { 0.22, 0.3 })
                if b.cls == "Border" then style.setBrush(b.w, spec) else pcall(function() b.w:SetBrush(spec) end) end
            else
                pcall(function()
                    if b.cls == "Border" then b.w:SetBrushFromTexture(b.tex) else b.w:SetBrushFromTexture(b.tex, false) end
                end)
            end
            -- its lettering - inside it (a border), or beside it in a small overlay (never the whole tooltip's
            -- layout): light on the theme's banner, as it was on the game's
            local parent = b.cls == "Border" and b.w or W.parent(b.w)
            local okP, pcls = pcall(W.className, parent)
            if parent and okP and (pcls == "Overlay" or pcls == "Border" or pcls == "SizeBox") then
                W.walk(parent, function(x)
                    local ok, isText = pcall(function() return x.ColorAndOpacity ~= nil and x.SetText ~= nil end)
                    if ok and isText then
                        local full = W.fullName(x)
                        b.texts = b.texts or {}
                        if not b.texts[full] then
                            pcall(function()
                                local c = x.ColorAndOpacity.SpecifiedColor
                                b.texts[full] = { w = x, c = { R = c.R, G = c.G, B = c.B, A = c.A } }
                            end)
                        end
                        local rec = b.texts[full]
                        pcall(function()
                            x:SetColorAndOpacity({ SpecifiedColor = art and style.label() or (rec and rec.c), ColorUseRule = 0 })
                        end)
                    end
                    return true
                end)
            end
        end
    end
end

local function skinTip(t)
    local band = style.tipBrush(t.panel)
    if band then style.setBrush(t.band, band) end
    pcall(findBanners, t)
    pcall(themeBanners, t)
    -- (a theme with a big panel flourish draws it smaller on tooltips: tipFlourishScale)
    local scale = themes.style().tipFlourishScale or 1
    local pad = style.flourishPad(themes.style(), themes.style().tipLine or 3, scale)
    -- a theme may have tooltip crests of its own (tip_flourish.png; tip_flourish_bottom.png already the right way
    -- up for the bottom line, so drawn unflipped); else the usual crest, the bottom one flipped
    local bottomArt = themes.find("ui/tip_flourish_bottom.png") ~= nil
    for _, which in ipairs({ "top", "bottom" }) do
        local f = t[which]
        if f and W.valid(f) then
            local file = which == "top" and "tip_flourish.png" or (bottomArt and "tip_flourish_bottom.png" or "tip_flourish.png")
            local spec = style.flourishBrush(t.panel, scale, file)
            if spec then style.setBrush(f, spec) end
            if which == "bottom" then
                pcall(function() f:SetRenderScale({ X = 1, Y = bottomArt and 1 or -1 }) end)
            end
            pcall(function()
                if which == "top" then f.Slot:SetPadding({ Left = 0, Top = pad, Right = 0, Bottom = 0 })
                else f.Slot:SetPadding({ Left = 0, Top = 0, Right = 0, Bottom = pad }) end
            end)
        end
    end
end

local function restyleTip(panel)
    local full = W.fullName(panel)
    if tips[full] then return end
    local art = child(panel, "PanelImage", "Image")
    local content = child(panel, "PanelContent")
    local overlay = art and W.parent(art)
    local tree = panel.WidgetTree
    local okC, ocls = pcall(W.className, overlay)
    if not (art and content and overlay and okC and ocls == "Overlay" and tree) then return end
    local okP, same = pcall(function() return W.fullName(W.parent(content)) == W.fullName(overlay) end)
    if not (okP and same) then return end
    local function new(cls)
        made = made + 1
        return StaticConstructObject(StaticFindObject("/Script/UMG." .. cls), tree, FName("FM_Tip" .. cls .. "_" .. made))
    end
    local t = { panel = panel, art = art }
    t.band = new("Image")
    pcall(function() t.band:SetVisibility(3) end)
    local bs = overlay:AddChildToOverlay(t.band)
    bs:SetHorizontalAlignment(0)
    bs:SetVerticalAlignment(0)
    -- the tip's contents back on top of the band (out of this overlay and straight back in, slot settings kept)
    local cs = content.Slot
    local p, h, v = cs.Padding, cs.HorizontalAlignment, cs.VerticalAlignment
    local keep = { Left = p.Left, Top = p.Top, Right = p.Right, Bottom = p.Bottom }
    content:RemoveFromParent()
    local ns = overlay:AddChildToOverlay(content)
    ns:SetPadding(keep)
    ns:SetHorizontalAlignment(h)
    ns:SetVerticalAlignment(v)
    -- the flourishes: centered on the top line, and upside down on the bottom one
    for _, which in ipairs({ "top", "bottom" }) do
        local f = style.flourish(new, panel)
        if f then
            local fs = overlay:AddChildToOverlay(f)
            fs:SetHorizontalAlignment(2)
            fs:SetVerticalAlignment(which == "top" and 1 or 3)
            if which == "bottom" then pcall(function() f:SetRenderScale({ X = 1, Y = -1 }) end) end
            t[which] = f
        end
    end
    pcall(function() art:SetRenderOpacity(0) end)
    -- whose tooltip it is: an inventory window's item (moved clear of our frame) or the HUD's (left where it is)
    local okO, ocls = pcall(function() return W.className(W.owner(panel)) end)
    -- (the status effects' own tooltips sit by the HUD, never by a window: never moved)
    t.hud = okO and type(ocls) == "string" and ocls:find("HUD_", 1, true) ~= nil
    t.inventory = not t.hud
    if not M.loggedOwners then M.loggedOwners = {} end
    if okO and ocls and not M.loggedOwners[ocls] then
        M.loggedOwners[ocls] = true
        log.info("inventory: a tooltip of %s (%s)", tostring(ocls), t.hud and "the HUD's: left in place" or "moved clear of an open window's frame")
    end
    skinTip(t)
    tips[full] = t
end

-- Every 100 ms: a tip's own art stays invisible (should the game fade it back in).
-- Pure: how far to move an item tooltip to the right, clear of our frame: as far as the frame reaches past the
-- window's own edge (reach: from the frame's padding, outward), plus a gap; never more than `max`. The game places an
-- item's tooltip against the window's original edge (where it can't be measured from Lua - it's placed in the
-- viewport directly), and our frames reach further out. Unit-tested.
function M.tipShift(reach, gap, max)
    if not reach or reach <= 0 then return 0 end
    return math.min(max or 60, reach + (gap or 0))
end

-- How far our frames reach past their windows' right edges, for the windows open now (0 if none is). Open = its
-- background shows (the same signal the hotbar copy follows).
local function inventoryOpen()
    -- the weight bar shows only while an inventory is open (the game hides the bar itself when it closes; a
    -- window's own visibility says nothing - they're made at load and kept)
    for _, wb in pairs(FindAllOf("WBP_Inventory_WeightBar_C") or {}) do
        if W.valid(wb) and W.isInstance(wb) then
            local bar = child(wb, "WeightBar", "ProgressBar")
            local okV, vis = pcall(function() return bar:IsVisible() end)
            local okO, op = pcall(function() return bar:GetRenderOpacity() end)
            if okV and vis == true and (not okO or (op or 1) > 0.05) then return true end
        end
    end
    return false
end

local function frameReach()
    if not inventoryOpen() then return 0 end
    local reach = 0
    for _, rec in pairs(windows) do
        local okO, open = pcall(function() return rec.bg:IsVisible() end)
        -- (the item windows only: the chat and the lore popup don't put tooltips beside themselves)
        local itemWindow = rec.kind ~= "chat" and rec.kind ~= "lore popup"
        if itemWindow and okO and open == true and rec.border and W.valid(rec.border) then
            local p = padOf(rec.border.Slot)
            if p and p.Right < 0 then reach = math.max(reach, -p.Right) end
        end
    end
    return reach
end

-- The windows the game opens beside the inventory (a station, a chest): moved a little right, so our frames (which
-- reach past the windows' edges) don't meet. A window you've placed yourself in the editor is left as you put it.
local BESIDE = { chest = true, crafting = true, processing = true, building = true }

-- Pure: should this window get the gap? Unit-tested.
function M.wantsGap(kind, placedByYou) return BESIDE[kind] == true and not placedByYou end

local function spaceStations()
    local gap = (ctx.settings.inventory or {}).windowGap or 24
    local layout = ctx.features.layout
    for _, rec in pairs(windows) do
        if rec.panel and W.valid(rec.panel) then
            local okK, key = pcall(W.key, rec.panel)
            local placed = okK and layout and layout.entry and layout.entry(key) ~= nil
            -- (set every tick: the game may reset it as the window opens; a placed window is the layout's to move)
            if not placed and BESIDE[rec.kind] then
                pcall(function()
                    local t = rec.panel.RenderTransform.Translation
                    if math.abs(t.X - gap) > 0.5 then rec.panel:SetRenderTranslation({ X = gap, Y = t.Y }) end
                end)
            end
        end
    end
end

local loggedShift
local function syncTips()
    local I = ctx.settings.inventory or {}
    local reach
    for full, t in pairs(tips) do
        if not (W.valid(t.panel) and W.valid(t.art)) then
            tips[full] = nil
        else
            pcall(function() if t.art:GetRenderOpacity() ~= 0 then t.art:SetRenderOpacity(0) end end)
            -- an inventory item's tooltip: moved right, clear of our wider frame (the HUD's tooltips are left alone)
            local want = 0
            if not t.hud then
                reach = reach or frameReach()
                want = M.tipShift(reach, I.tipGap or 6, I.tipMaxShift or 60)
            end
            if math.abs(want - (t.nudge or 0)) > 0.5 then
                t.nudge = want
                pcall(function()
                    local y = t.panel.RenderTransform.Translation.Y
                    t.panel:SetRenderTranslation({ X = want, Y = y })
                end)
                if not loggedShift and want ~= 0 then
                    loggedShift = true
                    log.info("inventory: item tooltips moved %.0f right (the frame reaches %.0f past the window)", want, reach)
                end
            end
        end
    end
end

-- Equipped items -----------------------------------------------------------------------------------------------

-- An equipped or held item's slot (bag, the window's hotbar row, the HUD hotbar) shows the game's orange square
-- (EquippedImage, T_QuickAccess_Overlay). Instead it gets the animated gold border a crafting table gives its
-- selected recipe: that's the item icon's own material (MI_Item_Selected) with Selection Opacity 1 - the only
-- setting a selected crafting icon has that a plain one hasn't (dumps/selection.txt). The game still decides which
-- slots are equipped: its EquippedImage keeps its visibility (that's what we read) and is only made invisible
-- (render opacity 0). The effect is switched off again only on slots we switched on.
M.SLOT = "WBP_Inventory_ItemSlot_C"
local slots = {} -- fullName -> { slot, eq, icon, on }
local SELECTION = "Selection Opacity"

-- Pure: the selection effect a slot's icon should have: 1 while equipped, 0 when we'd switched it on and it no
-- longer is, nil = leave it to the game. Unit-tested.
function M.equippedEffect(equipped, ours)
    if equipped then return 1 end
    if ours then return 0 end
    return nil
end

local function watchSlot(slot)
    local full = W.fullName(slot)
    if slots[full] then return end
    local eq, icon = child(slot, "EquippedImage", "Image"), child(slot, "ItemImage", "Image")
    if eq and icon then slots[full] = { slot = slot, eq = eq, icon = icon } end
end

local function syncEquipped()
    for full, s in pairs(slots) do
        if not (W.valid(s.slot) and W.valid(s.eq) and W.valid(s.icon)) then
            slots[full] = nil
        else
            local okV, v = pcall(function() return s.eq:IsVisible() end)
            local equipped = okV and v == true
            if equipped then
                pcall(function() if s.eq:GetRenderOpacity() ~= 0 then s.eq:SetRenderOpacity(0) end end)
            end
            local want = M.equippedEffect(equipped, s.on)
            if want then
                pcall(function()
                    local mid = s.icon.Brush.ResourceObject
                    if W.valid(mid) and W.className(mid) == "MaterialInstanceDynamic" then
                        local name = FName(SELECTION)
                        local okG, cur = pcall(function() return mid:K2_GetScalarParameterValue(name) end)
                        if not (okG and cur == want) then mid:SetScalarParameterValue(name, want) end
                    end
                end)
                s.on = want == 1
            end
        end
    end
end

-- The hotbar ---------------------------------------------------------------------------------------------------

local function wbl() return StaticFindObject("/Script/UMG.Default__WidgetBlueprintLibrary") end

-- A second hotbar on the HUD for the window's hotbar `row`: the game's own widget class, made for the same player
-- and filled by the game, placed where the row is laid out (the window's anchor and position plus the row's place
-- inside the window).
local function makeCopy(row)
    if not W.valid(row) then return end
    local full = W.fullName(row)
    if pairsOf[full] then return end
    local main = ancestorOfClass(row, MAIN)
    local canvas = main and W.parent(main)
    local okC, ccls = pcall(W.className, canvas)
    if not (main and canvas and okC and ccls == "CanvasPanel") then
        log.warn("inventory: no separate hotbar (the window isn't on a canvas)")
        return
    end
    local ok, err = pcall(function()
        local ms = main.Slot
        local anchors, pos, align, z = ms:GetAnchors(), ms:GetPosition(), ms:GetAlignment(), ms:GetZOrder()
        local lm, lh = measure.layoutRect(main), measure.layoutRect(row)
        if not (lm and lh) then error("couldn't measure the window") end
        local a = { Minimum = { X = anchors.Minimum.X, Y = anchors.Minimum.Y },
            Maximum = { X = anchors.Maximum.X, Y = anchors.Maximum.Y } }
        local x, y = M.hotbarPosition({ X = pos.X, Y = pos.Y }, { X = align.X, Y = align.Y },
            { X = lm.right - lm.left, Y = lm.bottom - lm.top }, { X = lh.left - lm.left, Y = lh.top - lm.top }, a)
        local copy = wbl():Create(row, row:GetClass(), row:GetOwningPlayer())
        if not W.valid(copy) then error("the game wouldn't make another hotbar") end
        copies[W.fullName(copy)] = true
        local s = canvas:AddChildToCanvas(copy)
        -- anchored at the point the window's anchors start from, so both follow the screen the same way
        s:SetAnchors({ Minimum = { X = a.Minimum.X, Y = a.Minimum.Y }, Maximum = { X = a.Minimum.X, Y = a.Minimum.Y } })
        s:SetAlignment({ X = 0, Y = 0 })
        s:SetAutoSize(true)
        s:SetPosition({ X = x, Y = y })
        s:SetZOrder(z + 1)
        local okI, ierr = pcall(function() copy:InitializeContent() end)
        if not okI then log.warn("inventory: the HUD hotbar couldn't fill itself: %s", tostring(ierr)) end
        local pair = { row = row, grid = child(row, "SlotGridContainer"), copy = copy,
            bg = M.openSignal(main, child(main, "BackgroundPanel", "Image")),
            art = child(main, "BackgroundPanel", "Image") }
        -- the radial-menu prompt beside the hotbar belongs to the HUD hotbar. It stays where the game has it (moved
        -- out of its place, its key hint loses its input context and hides): the HUD hotbar starts exactly on the
        -- row, and the prompt sits beside the row, so giving the prompt the HUD hotbar's own offset and scale keeps
        -- it beside the HUD hotbar wherever that goes (syncHotbars)
        local prompt = child(main, "QuickAccessRadialPrompt")
        local lp = prompt and measure.layoutRect(prompt)
        if lp then
            pair.prompt = prompt
            pair.promptOffset = { X = lp.left - lh.left, Y = lp.top - lh.top }
            pair.promptSize = { X = lp.right - lp.left, Y = lp.bottom - lp.top }
            pair.hotbarSize = { X = lh.right - lh.left, Y = lh.bottom - lh.top }
        end
        pairsOf[full] = pair
        log.info("inventory: separate HUD hotbar at %.0f, %.0f%s", x, y, pair.prompt and " (with its radial prompt)" or "")
    end)
    if not ok then log.warn("inventory: no separate hotbar: %s", tostring(err)) end
end

-- Every 100 ms: the window's row shows only while the inventory is open (closed, the HUD hotbar takes its place;
-- Hidden keeps its space, so the window doesn't change shape); the HUD hotbar shows whenever the game shows its own.
-- Pure: the opacity a set of render opacities adds up to (each multiplies the next). Unit-tested.
function M.combinedOpacity(list)
    local o = 1
    for _, v in ipairs(list) do o = o * (tonumber(v) or 1) end
    return math.max(0, math.min(1, o))
end

-- How faded `signal` is by the game's own animation, as far as `target` isn't already: the render opacities of
-- signal and its parents, up to (not including) the first parent the target shares (whose fading the target gets
-- anyway). The inventory opens and closes with a fade the game doesn't give its hotbar row (in the game's design
-- that row is the always-on HUD hotbar) nor, of course, our flourish; they copy it from the tabs row.
local function fadeFor(signal, target)
    local shared, cur, guard = {}, W.parent(target), 0
    while cur and guard < 20 do
        local ok, f = pcall(W.fullName, cur)
        if ok then shared[f] = true end
        cur, guard = W.parent(cur), guard + 1
    end
    local list
    list, cur, guard = {}, signal, 0
    while cur and guard < 20 do
        local ok, f = pcall(W.fullName, cur)
        if not ok or shared[f] then break end
        local okO, o = pcall(function() return cur:GetRenderOpacity() end)
        if okO then list[#list + 1] = o end
        cur, guard = W.parent(cur), guard + 1
    end
    return M.combinedOpacity(list)
end

-- Pure: how a piece we keep in step with a window's animation is drawn: the lower opacity and the smaller scale of
-- the animated parts it follows (the tabs row: quick, and the one that fades on closing; the background image:
-- slower, the fade and zoom on opening - the game animates both, each on its own). Unit-tested.
function M.followAnimation(fades, scales)
    local o, sc = 1, 1
    for _, v in ipairs(fades) do o = math.min(o, tonumber(v) or 1) end
    for _, v in ipairs(scales) do sc = math.min(sc, tonumber(v) or 1) end
    return math.max(0, o), math.max(0.01, sc)
end

local function scaleOf(w)
    local ok, sc = pcall(function() return w.RenderTransform.Scale.X end)
    return ok and tonumber(sc) or 1
end

-- `target` drawn with the fade and zoom of `signal` (and of `art`, the window's background image, if given).
-- Pure: the render pivot (0..1 of `rect`) that puts a widget's zoom center on `point` (layout units, same space).
-- The game zooms the whole window about its own center; a piece zoomed about its own center ends up the right size
-- but in the wrong place mid-zoom - with this pivot it zooms as if it were part of the window. Unit-tested.
function M.pivotAt(point, rect)
    local w, h = rect.right - rect.left, rect.bottom - rect.top
    return { X = w > 0 and (point.X - rect.left) / w or 0.5, Y = h > 0 and (point.Y - rect.top) / h or 0.5 }
end

-- The point the window zooms about: its background image's own pivot, in layout units.
local function zoomCenter(art)
    local r = art and measure.layoutRect(art)
    if not r then return nil end
    local px, py = 0.5, 0.5
    pcall(function() local pv = art.RenderTransformPivot px, py = pv.X, pv.Y end)
    return { X = r.left + (r.right - r.left) * px, Y = r.top + (r.bottom - r.top) * py }
end

local function follow(target, signal, art)
    local fades, scales = { fadeFor(signal, target) }, { scaleOf(signal) }
    if art and W.valid(art) then fades[#fades + 1] = fadeFor(art, target); scales[#scales + 1] = scaleOf(art) end
    local o, sc = M.followAnimation(fades, scales)
    pcall(function() target:SetRenderOpacity(o) end)
    if sc < 0.999 then
        -- zooming: about the window's center (worked out only while it zooms)
        local c, r = zoomCenter(art and W.valid(art) and art or signal), measure.layoutRect(target)
        if c and r then pcall(function() target:SetRenderTransformPivot(M.pivotAt(c, r)) end) end
    end
    pcall(function() target:SetRenderScale({ X = sc, Y = sc }) end)
    return o
end

-- Every 33 ms (smooth enough for a fade): the window's hotbar row and the flourishes fade and zoom with their
-- window. (Copying the tabs row alone, the hotbar row was fully in at 0.2 s while the background was still zooming
-- in; a trace of the opening showed the game animating just those two, each on its own.)
local function syncFades()
    for _, f in pairs(flourishes) do
        if W.valid(f.img) and W.valid(f.bg) then pcall(follow, f.img, f.bg, f.art) end
    end
    for _, p in pairs(pairsOf) do
        if p.grid and W.valid(p.grid) and W.valid(p.bg) then
            local okF, fade = pcall(follow, p.grid, p.bg, p.art)
            if okF and fade < 0.99 and fade > 0.01 and not M.fadeSeen then
                M.fadeSeen = true
                log.info("inventory: copying the window's open / close animation (%.2f) to its hotbar row and flourish", fade)
            end
        end
    end
end

local function syncHotbars()
    for full, p in pairs(pairsOf) do
        if not (W.valid(p.row) and W.valid(p.copy)) then
            pairsOf[full] = nil
        else
            local okO, open = pcall(function() return p.bg:IsVisible() end)
            open = okO and open == true
            if p.grid and W.valid(p.grid) then
                local want = open and 4 or 2
                pcall(function() if p.grid:GetVisibility() ~= want then p.grid:SetVisibility(want) end end)
            end
            local okV, shown = pcall(function() return p.row:IsVisible() end)
            local want = (okV and shown) and 4 or 1
            pcall(function() if p.copy:GetVisibility() ~= want then p.copy:SetVisibility(want) end end)
            -- the radial prompt moves, scales and fades with the HUD hotbar (the game still decides when it shows)
            if p.prompt and W.valid(p.prompt) then
                pcall(function()
                    local t = p.copy.RenderTransform
                    local pv = p.copy.RenderTransformPivot
                    p.prompt:SetRenderTranslation({ X = t.Translation.X, Y = t.Translation.Y })
                    p.prompt:SetRenderScale({ X = t.Scale.X, Y = t.Scale.Y })
                    p.prompt:SetRenderTransformPivot(M.followPivot(p.promptOffset, p.promptSize, p.hotbarSize,
                        { X = pv.X, Y = pv.Y }))
                    p.prompt:SetRenderOpacity(p.copy:GetRenderOpacity())
                end)
            end
        end
    end
end

-- Are we in the game world, not the menus? The menus reuse the same panel and tooltip classes (the world list's
-- info box is the tooltip panel), and Frame Mage leaves the menus as the game made them. The test is the game's
-- HUD (its vital bars): only the game world has one. (Having a pawn isn't enough: the menu scene has one too.)
local function inGame()
    for _, h in pairs(FindAllOf("WBP_HUD_PlayerVitalsBars_C") or {}) do
        if W.valid(h) and W.isInstance(h) then return true end
    end
    return false
end
M.inGame = inGame

-- Run fn(w) once the game world is up: now, or a little later (a window made while the world loads, before the
-- character exists), giving up after a few tries (the menus).
local function whenInGame(w, label, fn, tries)
    tries = tries or 6
    if not W.valid(w) then return end
    if inGame() then return fn(w) end
    if tries <= 1 then return end
    ctx.sched.later(1000, label .. ".wait", function() whenInGame(w, label, fn, tries - 1) end)
end

function M.init(c)
    ctx, W, log = c, c.widgets, c.log
    local S = c.settings.inventory or {}
    -- the wrapper round the window (and, before, the radial prompt) isn't an element any more: whatever offset it
    -- was given moves onto the window, so the window stays where it is on screen
    local layout = c.features.layout
    if layout then pcall(layout.fold, "WBP_Inventory_MainPanel", "WBP_Inventory_MainPanel/BackgroundPanel") end
    c.events.on("userwidget", function(w)
        if not ctx.enabled then return end
        local ok, cls = pcall(W.className, w)
        if not ok then return end
        if M.WINDOWS[cls] and S.restyle ~= false then
            -- a moment later: its tree and theme art are ready by then
            c.sched.later(200, "inventory.restyle", function()
                whenInGame(w, "inventory.restyle", function()
                    local okR, err = pcall(restyle, w, M.WINDOWS[cls])
                    if not okR then log.warn("inventory: restyle failed: %s", tostring(err)) end
                end)
            end)
        elseif cls == M.SLOT and S.equippedGlow ~= false then
            -- a moment later: its parts are made by then
            c.sched.later(100, "inventory.slot", function() if W.valid(w) then pcall(watchSlot, w) end end)
        elseif M.BARE[cls] and S.restyle ~= false then
            c.sched.later(200, "inventory.bare", function()
                whenInGame(w, "inventory.bare", function()
                    local okB, err = pcall(restyleBare, w, M.BARE[cls])
                    if not okB then log.warn("inventory: restyle failed: %s", tostring(err)) end
                end)
            end)
        elseif TABS[cls] and S.restyle ~= false then
            -- a tab button made after its window was restyled (another mod's - Storage Mage's bag tabs - or the
            -- game's own, later): given our border like the others, once it's laid out
            c.sched.later(250, "inventory.lateTab", function()
                for _, rec in pairs(windows) do
                    if rec.tabs and W.valid(rec.panel) then
                        local okT, more = pcall(rimTabs, rec.panel)
                        if okT and more and #more > 0 then
                            for _, t in ipairs(more) do rec.tabs[#rec.tabs + 1] = t end
                            log.info("inventory: %d more tab buttons given our border", #more)
                        end
                    end
                end
            end)
        elseif cls == M.TOOLTIP and S.restyle ~= false and inGame() then
            -- made fresh on hover: restyled straight away, so the game's look never shows
            local okT, err = pcall(restyleTip, w)
            if not okT then log.warn("inventory: tooltip restyle failed: %s", tostring(err)) end
        elseif cls == HOTBAR and S.separateHotbar ~= false and not copies[W.fullName(w)] then
            -- after the HUD's first layout, so the window can be measured
            c.sched.later(500, "inventory.hotbar", function() makeCopy(w) end)
        end
    end)
    c.events.on("worldchanged", function() flourishes, copies, pairsOf, windows, tips, slots, bare = {}, {}, {}, {}, {}, {}, {} end)
    -- a new panel stone (Settings) or theme: the window follows straight away
    local function reskinAll()
        for full, rec in pairs(windows) do
            if W.valid(rec.panel) and W.valid(rec.bg) then
                local ok, err = pcall(skin, rec)
                if not ok then log.warn("inventory: restyle failed: %s", tostring(err)) end
            else
                windows[full] = nil
            end
        end
    end
    local function reskinBare()
        for full, rec in pairs(bare) do
            if W.valid(rec.panel) then pcall(rec.skin) else bare[full] = nil end
        end
    end
    c.events.on("stylechanged", reskinBare)
    c.events.on("themechanged", function() c.sched.later(50, "inventory.reskinBare", reskinBare) end)
    local function reskinTips()
        for _, t in pairs(tips) do if W.valid(t.panel) then pcall(skinTip, t) end end
    end
    c.events.on("stylechanged", reskinAll)
    c.events.on("stylechanged", function() c.sched.later(50, "inventory.reskinTips", reskinTips) end) -- (art reloaded)
    c.events.on("themechanged", function() c.sched.later(50, "inventory.reskinTips", reskinTips) end)
    c.events.on("themechanged", function() c.sched.later(50, "inventory.reskin", reskinAll) end)
    c.sched.every(33, "inventory.fade", syncFades)
    c.sched.every(100, "inventory.stationGap", function() pcall(spaceStations) end)
    c.sched.every(100, "inventory.sync", function()
        -- the flourish shows exactly when the window's background does (while the inventory is open)
        for full, f in pairs(flourishes) do
            if not (W.valid(f.img) and W.valid(f.bg)) then
                flourishes[full] = nil
            else
                local okV, v = pcall(function() return f.bg:IsVisible() end)
                local want = (okV and v) and 3 or 1
                pcall(function() if f.img:GetVisibility() ~= want then f.img:SetVisibility(want) end end)
            end
        end
        syncHotbars()
        syncWindows()
        syncTips()
        syncEquipped()
        syncBare()
    end)
end

return M
