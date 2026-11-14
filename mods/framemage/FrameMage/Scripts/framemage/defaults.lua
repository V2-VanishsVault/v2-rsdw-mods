-- Default settings. Users edit Mods/FrameMage/config/settings.lua; missing keys fall back to these.
-- Key names are Unreal key names (F9, PageUp, Left, Equals, LeftBracket, LeftMouseButton ...); the older UE4SS
-- names (PAGE_UP, OEM_PLUS ...) also work. Modifiers: CTRL, SHIFT, ALT.
return {
    logLevel = "info", -- debug | info | warn | error

    -- Turn a feature off to isolate a problem (e.g. a crash). Removed/false features never load.
    -- the Settings panel: "shared" (the one every Mage mod shares, with a tab per mod) or "own" (Frame Mage's own)
    settingsPanel = "shared",

    -- every feature, so any can be switched off in settings.lua (one missing here was dropped as unknown on the next
    -- save); the developer features (dev/) too
    features = { layout = true, art = true, materials = true, grid = true, editor = true, share = true, ding = true,
        celebrate = true, replace = true, bars = true, survival = true, status = true, inventory = true,
        inspector = true, devkeys = true, apidump = true },

    -- Frame Mage's own widgets shown instead of the game's (features/replace.lua)
    replace = {
        levelUp = true, -- level-up popup -> fireworks celebration
    },

    -- the inventory window (features/inventory.lua); both take effect at the next start
    inventory = {
        tipGap = 6, -- a tooltip beside a window keeps this far clear of its frame (UI units)
        windowGap = 24, -- a station or chest window opens this far right of where the game puts it, clear of the inventory
        restyle = true, -- the inventory and chest windows in the chosen panel stone, a frame of gold light and the
                        -- top-line flourish; their checkboxes and text boxes in the same light border; tooltips
                        -- as a band of glass edged with light, a flourish on each edge
        separateHotbar = true, -- a HUD hotbar of its own (same slots as the window's top row), moved on its own
        equippedGlow = true, -- equipped / held items get a crafting table's animated gold border, not the orange square
    },

    -- the level-up fanfare: a short synthesized tune (features/ding.lua)
    ding = {
        enabled = true,
        volume = 0.7, -- 0..1
        delay = 0.1, -- seconds after the celebration starts (as the number lands)
        sound = "triumph", -- one of features/ding.lua's TUNES: triumph, ascend, quest, sparkle, heroic
        asset = "", -- optional: object path of a sound asset to play instead of the synth
    },

    celebrate = {
        centerY = 0.36, -- vertical position, fraction of the screen from the top
        duration = 3.4, -- seconds, including the fade-out
        outro = 0.45,
        zoomTime = 0.65,
        zoomFrom = 3.2, -- the number starts this many times larger
        numberSize = 120,
        titleSize = 34,
        labelSize = 26,
        iconSize = 56,
        glowSize = 420,
        sparkSize = 18,
        bursts = 5,
        perBurst = 30,
        burstTimes = { 0.12, 0.42, 0.72, 1.02, 1.38 },
        spreadMinX = 220, spreadMaxX = 520, -- burst centers, UI units from the middle
        spreadMinY = 60, spreadMaxY = 300,
        speedMin = 220, speedMax = 520,
        lifeMin = 1.1, lifeMax = 1.7,
        gravity = 240,
        drag = 1.3,
        flashSize = 200, -- bright bloom where each burst goes off
        flashTime = 0.35,
        palette = { { 1, 0.82, 0.36 }, { 1, 0.45, 0.25 }, { 0.55, 0.85, 1 }, { 1, 0.95, 0.8 }, { 0.85, 0.5, 1 } },
        frameMs = 33, -- 30 updates a second: smooth for sparks, half the cost of 60
    },

    profile = "default", -- layouts/<profile>.lua
    profiles = { "default", "combat", "minimal" },

    theme = "elven", -- elven, warrior, ranger, wizard or dwarven: Art/themes/<theme>/ (missing art comes from elven)
    stone = "theme", -- what fills the panels: theme (each theme's own), silk, forge, leather, oak, starfield, slate,
                     -- dragonscale, parchment, mists, embers, abyss or aurora

    layout = {
        reapplyMs = 200, -- how often moved elements are re-asserted (game animations can reset them)
    },

    bars = {
        style = "flat", -- the player's health / stamina / special bars: "flat" (the game's), "bevel" or "facet"
        badges = true, -- the game's bar icons on a dark disc with a gold ring
        ringSize = 38, -- the ring's size (UI units; the game's icons are 33)
        iconScale = 0.78, -- the icon's size on its ring
        ringGap = 2, -- (unused since rowPitch) space between neighboring rings
        rowPitch = 46, -- each bar's row height (UI units), with or without rings: rings 38 high sit 8 apart (keep
        -- it above ringSize + shadowOffsetY so neither the rings nor their shadows touch)
        taper = true, -- taller bars with a pointed right end
        sameHeight = true, -- every vital bar as tall as the tallest (the game makes the special bar slimmer)
        extraHeight = 6, -- how much taller than the game's bars (UI units), before heightScale
        heightScale = 0.68, -- then scaled: the bars sit a little slimmer than their icon rings
        outline = true, -- a fine gold edge round the shaped bars, matching the icon rings
        ringShadow = true, -- a soft shadow from each ring onto its bar
        -- another game icon on a ring (bar icon widget name -> game texture name): stamina shows the Agility skill
        iconOverrides = { StaminaIcon = "T_Icon_Tag_Skill_Agility" },
        statusGauges = true, -- timed status effects (Cosiness, the weather...) as round gauges like the survival gauges
        gaugeRims = true, -- the theme's rim round every gauge (survival, buffs, status effects)
        statusGaugeSize = 64, -- their ring's size (UI units)
        weightColors = true, -- the load gauge (inventory shortcut) and weight bar: green, yellow, orange, red, pulsing red past full
        weightIconSize = 28, -- the theme's weight icon beside the inventory weight bar (UI units)
        weightRim = 3, -- how far the weight bar sits inside its themed trough's rim (UI units)
        menuShortcutSize = 64, -- the menu shortcuts' circles (chat, map, spells, building, inventory): 0 = the game's size
        statusOrder = "timed", -- "game" (as listed), "timed" (ones that run out first) or "lasting" (on / off ones first)
        statusGrow = "down", -- "down" or "up": which way the column grows as effects appear (the first stays put)
        statusIconScale = 0.7,
        statusBadgeSize = 40, -- an effect without a timer (Sheltered): its icon in the theme's icon ring, this size
        statusBadgeIconScale = 0.6, -- their icon's size in the ring (inside it, not over it)
        statusGap = 4, -- space between status effects (UI units): as close as the vitals' icons
        percentFontSize = 10, -- their size (matching the health number)
        percentText = true,
        hideRateLabels = true, -- the game's rate labels beside the bars (STATS, HP/S, SPEC/S) never show -- the stamina and special bars show their fill as a percentage (the health bar has its value)
        survivalLayout = "row", -- "row": the game's; "stacked": water / food / exhaustion in a column beside the vitals
        survivalGap = 28, -- (stacked) space between the bars' points and the gauges
        survivalBuffGap = 14, -- (stacked) space between the gauges' values and the buffs
        survivalRingSize = 40, -- (stacked) each gauge's ring, a fixed size (UI units; Settings, Vitals: 24 to 96; bigger than the spacing of the bars, they spread apart)
        survivalMaxScale = 1, -- (stacked) the gauges never grow beyond their own size
        survivalTextScale = 1.35,
        survivalShrinkBuffs = false, -- (stacked) shrink the buffs to the gauges' ring size (their numbers get hard to read)
        textShadowOffset = 1.5, -- the drop shadow under the survival values and buff durations (UI units)
        textShadowOpacity = 0.85,
        hideKeyHints = false, -- hide the key hints (Block, Attack, Special Attack...)
        iconNudgeY = 1, -- the icons on the rings sit this much lower (UI units) to look centered
        durabilityColors = true, -- item durability bars: green (100%) -> yellow -> orange -> red (25%)
        shadowOffsetX = 4, shadowOffsetY = 3, -- where the shadow falls (UI units, right and down)
        shadowOpacity = 0.7,
        taperWidth = 16, -- length of the point (UI units)
        endWidth = 6, -- length of the flat end when shaped bars are off (UI units): its art is 16 px wide, its edge as thick as the bar's
        -- how the end (point or flat) gets its color, shown when the bar is full:
        --   "copy"  - the bar's own paint continued past its end: strips tipStripHeight UI units tall, each clipped
        --             to its piece of the shape and holding a full-size copy of the bar (a cropped copy drew black)
        --   "solid" - a plain shape in the material's main color * tipGain + tipLift
        tipPaint = "copy",
        tipStripHeight = 1,
        -- the point's color when full: the material's main color * tipGain + tipLift (the material draws brighter
        -- than its main color; raise these if the point looks darker than the bar)
        tipGain = 1.2,
        tipLift = 0.03,
    },

    art = {
        enabled = true,
        hookSetters = true, -- re-skin brushes the game changes at runtime (item icons, state swaps)
    },

    grid = {
        show = true, -- draw the grid while the editor is open
        snap = true, -- arrows snap element edges to grid lines (toggle in game with keys.toggleGrid)
        size = 16, -- cell size in UI units (1920x1080 reference)
        major = 4, -- brighter line every N cells; Shift+arrow jumps to these
        color = { 1, 0.85, 0.45 },
        minorAlpha = 0.08,
        majorAlpha = 0.22,
        centerColor = { 0.25, 0.85, 1 }, -- center axes: cyan, so the middle stands out from the gold grid
        centerAlpha = 0.75,
        centerThickness = 2,
        centerDot = 6, -- square at the center, in UI units
        centerAnimate = true, -- pulses travel from the center to each screen edge
        centerSegments = 24, -- per arm; more = smoother gradient
        centerWaves = 2, -- bright pulses visible on each arm at once
        centerSpeed = 0.6, -- pulses per second leaving the center
        centerFade = 0.7, -- how much dimmer the arms get toward the edges (0 = no gradient)
        centerMinLevel = 0.35, -- brightness between pulses
        centerPulseColor = { 1, 1, 1 }, -- pulses shift toward this color
        centerFrameMs = 33,
    },

    share = {
        importFile = "import", -- share/<name>.framemage.txt is what Import reads
    },

    inspector = {
        includeHidden = false, -- widgets.txt: also list collapsed/hidden branches (much longer)
    },

    editor = {
        step = 4,
        bigStep = 32,
        scaleStep = 0.05,
        fadeStep = 0.1,
        minScale = 0.2,
        maxScale = 4.0,

        lockInput = true, -- show the mouse cursor and pause game input while the editor is open

        -- selection frame (color is linear RGB; edges are thin, corner brackets heavier)
        frameColor = { 1, 1, 1 },
        frameEdgeAlpha = 0.6,
        frameEdge = 1,
        frameCorner = 3,
        frameCornerLength = 12,
        frameMinSize = 16, -- empty widgets get at least this big a frame so they can be seen
        frameMs = 33, -- how often the frame follows the selection

        -- preview of elements that have nothing to show right now
        ghostOpacity = 0.35, -- elements hidden by your layout show at this opacity while selected
        previewMaxText = 40, -- empty text fields that get a placeholder label

        -- title banner (ribbon below the compass): off; messages flash in the hotkey list's title bar instead
        showBanner = false,
        bannerHeight = 64, -- UI units
        bannerMinWidth = 220,
        bannerFontSize = 22,
        bannerGap = 10, -- below the compass
        bannerFallbackTop = 120, -- when the compass can't be measured

        -- hotkey legend (left edge of the screen while the editor is open)
        showLegend = true,
        legendKeySize = 26, -- keycap height in UI units
        legendKeyWidth = 44,
        buttonOrnamentSize = 9, -- the ornament at each end of a filled button (UI units)
        buttonOrnamentGap = 6, -- between an ornament and the button's text -- keycap width: wider than tall, like the game's own prompts (most names fit)
        legendCapPadX = 7, -- space either side of the key name inside a cap (a scrolling name stays inside the rim)
        legendMarqueeSpeed = 14, -- a name too wide for its cap scrolls at this speed (UI units / second)
        legendMarqueePause = 1.2, -- seconds it rests at each end
        legendCapFontSize = 9, -- small enough that the cap's rim reads as a rim, not as [ ]
        legendLabelSize = 13,
        legendHeadingSize = 13,
        legendSectionSize = 10,
        legendMargin = 24,
        legendDefaultTop = 200, -- where the list starts until you drag it
        legendX = -1, legendY = -1, -- where you dragged it (-1 = default); saved automatically
        legendCollapsed = false, -- saved automatically
        legendChevronSize = 14,
        legendSlideTime = 0.2, -- seconds to slide open / closed

        -- title bar: the gold drag handle above the selection
        titleColor = { 0.86, 0.66, 0.26 },
        titleFontSize = 12, -- (the same as the other elements' bars: picking one mustn't make it grow)
        titlePadX = 14,
        titlePadY = 5,
        titleGap = 3, -- between the bar and the frame
        titleMinTop = 6, -- closer to the top of the screen than this, the bar goes under the frame

        -- drag bars: a gold bar on every movable element while the editor is open, ready to grab
        showHandles = true,
        handleFontSize = 12,
        handlePadX = 10,
        handlePadY = 4,
        handleAlpha = 0.9,
        handleMinArea = 900, -- elements smaller than this (UI units squared, e.g. 30x30) get no bar
        handleMaxScreenShare = 0.5, -- containers bigger than this share of the screen get no bar (their parts do)
        handleMax = 60, -- most bars at once
        handlesMs = 400, -- how often the bars follow the HUD
        placeholderW = 220, placeholderH = 56, -- stand-in for a selected element with nothing showing, until it has
                                               -- been seen showing (then its own size: config/sizes.lua)
        rootsCacheSeconds = 2, -- the bars re-find the game's top-level panels this often (a full scan)

        -- hidden-elements panel (H): click a name to show that element
        hiddenWidth = 300,
        -- the Settings panel (F4)
        settingsWidth = 540,
        settingsX = false, settingsY = false, -- where it was last dragged to (false: top middle of the screen)
        settingsValueWidth = 200,
        settingsTipLines = 4, -- lines kept free for the hovered setting's explanation (a longer one makes the panel taller)
        hiddenRows = 14, -- names visible at once (the wheel scrolls)
        -- left out of that panel (by the name it shows): game pieces that aren't worth showing on their own
        hiddenSkip = { "Compass Marker", "Composite Variable Menu", "Canvas Panel" },
        -- elements never offered in the editor at all (by key): the HUD's own canvas holds the other elements
        listSkip = { "WBP_HUD_RootWidget/CanvasPanel" },
        -- elements never offered for picking or PgUp / PgDn, by title (and numbered copies: "Compass Marker 2")
        selectSkip = { "Compass Marker" },
        -- ... and by class or path (part of the name, any case): every reticle
        selectSkipClasses = { "Reticle" },
        -- ...and by class (any case, part of the name): reticles (never moved), durability bars (part of their
        -- item), and the inventory and chest windows' pieces (they stay as Frame Mage styles them)
        hiddenSkipClasses = { "Reticle", "DurabilityBar", "WBP_Inventory_", "WBP_Panel_Inventory",
            "WBP_WorldActorInventory" },

        -- the element list (PgUp / PgDn) and click-picking skip small building blocks whose class contains any of
        -- these (key-prompt icons, text wrappers, tooltips); click a bigger part or use Home / End to reach them
        ignoreClasses = { "InputIcon", "InputAction", "ActionWidget", "DomTextBlock", "TextBlock", "Tooltip",
            "SelectorArrow", "Keybind", "KeyHint", "InputLegend", "Spacer", "Divider", "Throbber", "LoadGuard" },
        listMinArea = 64, -- on-screen elements smaller than this (UI units squared) aren't listed
        splitGap = 36, -- parts of one widget further apart than this (UI units) become separate elements
        -- names shown for elements (the last part of their key -> what to call it)
        -- widgets always split into their parts (by class), when the parts sit too close to tell apart by distance
        forceSplit = {
            WBP_HUD_InputsLegend_C = true,      -- key hints | menu shortcuts
            WBP_InputLegend_World_C = true,
            WBP_SurvivalCore_Upkeep_C = true,   -- survival gauges | buffs
            WBP_Inventory_MainPanel_C = true,   -- only a wrapper round the inventory window: the window is the element
            WBP_HUD_RootWidget_C = true,        -- the whole HUD: its pieces are the elements, never one big group
        },
        renames = {
            GameInputs = "Key Hints",
            HorizontalBox_436 = "Menu Shortcuts",
            BackgroundPanel = "Inventory",
            WBP_Inventory_MainPanel = "Inventory",
            VitalsBarOverlay = "Vital Bars",
            WBP_SurvivalCore_Upkeep = "Survival",
            StatBarVerticalBox = "Vital Bars",
            QuickAccessBar = "Inventory Hotbar", -- the row inside the inventory window
            WBP_Inventory_QuickAccesBar = "Hotbar", -- the separate HUD hotbar (inventory.separateHotbar)
            ["WBP_HUD_PlayerVitalsBars/WBP_SurvivalCore_Upkeep/HorizontalBox_1"] = "Survival Gauges", -- (a whole key)
        },

        -- controller: the left stick moves the selection
        stickDeadzone = 0.2,
        stickSpeed = 700, -- UI units per second at full tilt

        -- click-to-pick
        pickMinArea = 4, -- ignore widgets smaller than this (UI units squared)
        pickMaxNodes = 6000, -- safety cap on widgets examined per click
        pickRepeatTolerance = 6, -- clicks this close count as "same spot" and step out to the parent
    },

    keys = {
        edit = "F9",
        closeEditor = "Escape", -- also closes the editor (saving); the pause menu stays shut for that press
        dump = "CTRL+F9",
        -- the same dumps 5 seconds later: Frame Mage's keys don't reach it while a game menu (the inventory...) is
        -- open, so press this, then open the menu
        dumpLater = "CTRL+SHIFT+F9",
        reloadArt = "CTRL+F10",
        -- developer: the game's functions for hotbars / items / spells / bags -> dumps/api.txt. Numpad +: Ctrl+F11 is
        -- taken by Windows (windowed / full screen), and Alt+F9 starts recording in NVIDIA's overlay
        dumpApi = "Add",
        previewCelebration = "CTRL+F8", -- developer: play the level-up celebration
        nextProfile = "F7",

        -- active only while the editor is open
        -- mouse (not rebindable): click selects (again: its parent), right-click selects the parent, drag the gold
        -- title bar to move
        next = "PageDown",
        prev = "PageUp",
        nextSibling = "CTRL+PageDown",
        prevSibling = "CTRL+PageUp",
        parent = "Home",
        child = "End",
        left = "Left",
        right = "Right",
        up = "Up",
        down = "Down",
        bigModifier = "SHIFT", -- hold with arrows for big steps
        scaleUp = "Equals",
        scaleDown = "Hyphen",
        fadeDown = "LeftBracket", -- [
        fadeUp = "RightBracket", -- ]
        hide = "Delete",
        reset = "BackSpace",
        toggleGrid = "Insert",
        showHidden = "H", -- add hidden elements to the PgUp / PgDn list (and back)
        legend = "F3", -- slide the hotkey list closed / open
        settings = "F4", -- the Settings panel: in normal play (on its own) and in the editor
        undo = "CTRL+Z", -- undo the last move (a drag, a group drag or a nudge)

        -- controller (Xbox names; the same buttons on other pads). Both sticks clicked opens / closes the editor.
        padEdit = "Gamepad_LeftThumbstick&Gamepad_RightThumbstick",
        padPrev = "Gamepad_LeftShoulder",
        padNext = "Gamepad_RightShoulder",
        padChild = "Gamepad_FaceButton_Bottom",
        padParent = "Gamepad_FaceButton_Right",
        padUp = "Gamepad_DPad_Up",
        padDown = "Gamepad_DPad_Down",
        padLeft = "Gamepad_DPad_Left",
        padRight = "Gamepad_DPad_Right",
        padScaleDown = "Gamepad_LeftTrigger",
        padScaleUp = "Gamepad_RightTrigger",
        padHide = "Gamepad_FaceButton_Left",
        padGrid = "Gamepad_FaceButton_Top",
        padReset = "Gamepad_RightThumbstick",
    },
}
