-- What's new: this version's notes, shown once after the addon updates (a
-- first install has nothing new to show), then any time from What's new in
-- /ccm or /ccm new. The releases before it follow underneath. Drawn in the
-- window's flat style. Show me what's new beside Got it tours the steps the
-- update added (Tour.lua), when it added any.
local _, ns = ...
local T = ns.Theme

-- Newest first, word for word as in CHANGELOG.txt (Tools/TestNotes.mjs checks).
-- Notes waiting for their version number are "Unreleased".
ns.NOTES = {
    {
        version = "1.5.4",
        sections = {
            { "Added", {
                "The Debuffs bar can show your debuffs on you, like Weakened Soul.",
                "Share your profile as text, or import one someone shared, from the Profile menu.",
            } },
            { "Fixed", {
                "A bar you're dragging stays on your mouse when your bags or spells change.",
            } },
        },
    },
    {
        version = "1.5.3",
        sections = {
            { "Fixed", {
                "Unticking Use my bars gives your resource display its own width back at once.",
                "A bar you're dragging is let go when the settings close mid-drag.",
                "What's new and the first-time welcome still show if you reload before they appear.",
            } },
            { "Improved", {
                "Lighter on your game, most of all with Use my bars off.",
                "Lighter in a fight: bars, cast bar, swing timer, keybinds and Cooldown pulse only redo what changed.",
            } },
            { "Changed", {
                "Your bars turn red out of range the moment the game says so.",
                "The settings, the tour and What's new point you to buttons rather than /ccm (it still works).",
                "Bars with buffs, debuffs or buff and debuff times fade right out instead of hiding (it looks the same).",
                "All bars, Show grow arrows, Dim when ready and Best you carry are no longer marked Needs testing.",
            } },
        },
    },
    {
        version = "1.5.2",
        sections = {
            { "Added", {
                "The minimap button can be free-floating: tick it on the General page, then drag it anywhere.",
            } },
            { "Changed", {
                "Escape now closes the settings during a fight too.",
                "The settings and What's new close along with the game's other windows, for example at a loading screen.",
                "The minimap button's tooltip now matches the addon's look.",
            } },
        },
    },
    {
        version = "1.5.1",
        sections = {
            { "Changed", {
                "If Forever Enhanced Cooldown Pulse is installed, only one of the two pulses runs at a time.",
            } },
        },
    },
    {
        version = "1.5.0",
        sections = {
            { "Added", {
                "Cooldown pulse, under More: a big icon pops up in the middle of your screen when a cooldown you tick is ready.",
                "Quick and Long pulse styles, each with its own size, time and sound, plus 15 sounds and a Master volume option.",
                "A \"?\" button on every page shows you how that page works.",
            } },
            { "Changed", {
                "Reactive abilities like Riposte now show the game's proc glow, or a gold edge if you prefer (Look page).",
                "Your bars glow whenever the game lights a spell up on your action bars.",
                "New logo, and the settings window is purple by default.",
                "Labels on the Layout page no longer run into each other.",
            } },
        },
    },
    {
        version = "1.4.4",
        sections = {
            { "Changed", {
                "The \"Show me what's new\" tooltip now matches the addon's look.",
                "Trying to add a debuff you put on yourself now points you to \"Show your debuffs on you\".",
            } },
        },
    },
    {
        version = "1.4.3",
        sections = {
            { "Added", {
                "Cooldowns and Utility bars can show a spell's buff or debuff time, like Shadow Word: Pain.",
                "Buffs bar can show your debuffs on you, like Weakened Soul.",
            } },
        },
    },
    {
        version = "1.4.2",
        sections = {
            { "Changed", {
                "Switching the Cooldown Manager or resource display from /ccm now asks for a reload.",
                "Smoother gear set swaps.",
                "Lighter icon updates in combat.",
                "New profiles are named with your surname.",
                "The tour points to Raid Timers under More.",
                "Pull countdown and Show me what's new are no longer marked Needs testing.",
            } },
            { "Fixed", {
                "Your rows close up when the resource display is Hidden in Edit Mode.",
                "Potions and healthstones move to the higher rank as soon as you level up.",
            } },
        },
    },
    {
        version = "1.4.1",
        sections = {
            { "Added", {
                "Raid Timers: size sliders for the countdown bar, its numbers, raid warnings and boss emotes, or all at once.",
                "Raid Timers: an Edit Mode button beside Boss cast bars.",
                "Show me what's new now tours the Raid Timers page.",
            } },
            { "Changed", {
                "Raid Timers: the \"In the game\" section is gone, for a tidier page.",
            } },
        },
    },
    {
        version = "1.4.0",
        sections = {
            { "Added", {
                "Raid Timers (under More): restyles the pull countdown, raid warnings, boss emotes and boss cast bars to match your bars. Each part stays off until you tick it.",
            } },
            { "Updated", {
                "Ready for the level 30 patch: the druid's Shifting Power and the warlock's Soul Harvest.",
            } },
            { "Fixed", {
                "Tracked Bar colours now stay at every rank of a spell.",
            } },
            { "Note", {
                "The level 30 patch merged spell ranks, so check Cooldown Settings for any ranked spells Blizzard moved.",
            } },
        },
    },
    {
        version = "1.3.0",
        sections = {
            { "Added", {
                "Swap icons: drop one icon onto another to swap them.",
                "The footer tells you what dropping a spell will do, or why it can't go there.",
                "/ccm reset asks before resetting your layout.",
                "Gold edge on Victory Rush, Hammer of Wrath and Divine Grace when they're ready.",
            } },
            { "Changed", {
                "Passive spells can't go on bars, but Reincarnation still can. Passives with their own buff, like Plainsrunning, can go on Buffs.",
                "Row arrows show how many icons fit across.",
                "Keybinds on icons is no longer marked Needs testing.",
            } },
            { "Fixed", {
                "Shared profiles no longer show another race's racials.",
                "No more empty box beside a short last row.",
            } },
        },
    },
    {
        version = "1.2.1",
        sections = {
            { "Fixed", {
                "Items and potions you don't carry no longer show on your bars; the bar closes up and they come back when you have one. Putting one on while you carry none says so.",
                "Ammo no longer shows for classes that never use it (a warlock sharing a hunter's profile). Hunters, warriors and rogues still see it greyed at 0 when out.",
            } },
        },
    },
    {
        version = "1.2.0",
        sections = {
            { "Added", {
                "Healthstones, Healing Potions and Mana Potions: one icon that shows the best one you carry and switches as your bags change. Tick it under Items, or drag any rank onto a bar.",
                "When ready: Show, Dim or Hide, for each bar.",
                "Font and bar texture choice on the Look page.",
                "Show grow arrows on the Layout page: while your bars are unlocked or in Edit Mode, arrows show which way each bar grows.",
            } },
            { "Fixed", {
                "Cast bar: its shadow no longer sticks out past the resource display and your rows, and it lines up with the display switched off or at other Edit Mode sizes.",
            } },
        },
    },
    {
        version = "1.1.0",
        sections = {
            { "Added", {
                "Keybinds on icons: the key that casts each spell or uses each item, from your action bars, on your Cooldowns and Utility bars and on Blizzard's Cooldown Manager icons. At the bottom, top left, top or top right, in the size you pick; the Look page's sample icons show it as you change it. Off by default, in /ccm > Look.",
                "All bars: one slider on the Layout page sizes all your bars together, keeping their sizes next to each other. Each bar's Icon size still fine-tunes it.",
                "Layout page: your icons show the border, shadow and keybinds from the Look page. Untick Live preview for plain icons.",
                "Drag items onto your bars: ammo of any kind from your bags or character panel becomes one icon that follows whatever ammo you have equipped, with its count. Trinkets, potions and your Hearthstone can be dragged in too.",
                "What's new: after an update, Show me what's new walks you through just the new features.",
                "Made with love by Squirt in the /ccm footer, in your window accent colour.",
            } },
            { "Changed", {
                "Every button and setting in /ccm explains itself in the footer when you hover it.",
                "Click a spell's name in a bar's list to tick it, like its tick box.",
                "\"Each spell shows once, at your highest rank\" is now on the bar pages, by the spell list.",
            } },
            { "Fixed", {
                "Swing timer: when your auto-attack or Auto Shot stops (the target died, or you stopped), the bar stops and fades instead of filling on.",
                "Layout page: a row's help stays up while you use its - + arrows and x, and the resource display's arrows can be reached by hovering.",
            } },
        },
    },
    {
        version = "1.0.0",
        sections = {
            { "Blizzard's Cooldown Manager", {
                "A new look: square icons with big, bold countdown numbers, and Tracked Bars in three designs (Glass, Split and Outline) and six colours. Any Tracked Bar can have a colour of its own. On by default, in /ccm > Look.",
                "Borders and shadows on the Look page: a thin border and a soft shadow, each round every icon or round whole bars, on Blizzard's Cooldown Manager icons and your own bars. Off until you pick them.",
                "Your Personal Resource Display's health and power bars get the same look, in Blizzard's colours or your own. The extra mana bar some specs get hides in caster form and is half size in forms.",
                "Combo points under your energy bar for rogues and druids in cat form, which Forever's display leaves out: five sharp segments as wide as the display, in your bar design and a colour of your own. Off until you tick it on the Look page.",
                "If Blizzard's Cooldown Manager or Personal Resource Display is off, /ccm tells you and can turn it on.",
            } },
            { "Your own bars", {
                "Cooldowns, Utility, Buffs and Debuffs bars, set up in /ccm by ticking spells or dragging them in from your spellbook. Each spell shows once, at your highest rank, and switches when you train a new one. Off until you tick Use my bars on the General page.",
                "Cooldown icons show the sweep and countdown in combat: grey while cooling down, red out of range, blue without enough mana, and a gold edge when a reactive ability like Overpower is ready.",
                "Buffs bar: your buffs and class procs (Clearcasting, Shadow Trance and more) with time left and stacks. Buffs from other players count at any rank, group versions too.",
                "Debuffs bar: your own debuffs on your target.",
                "Join entries on the Buffs and Debuffs bars to show one icon for whichever is up, for seals, auras, aspects or stings.",
                "Each bar has its own icon size, spacing and options: hide when ready, spell names, countdown numbers, and show, fade or hide out of combat. Unlock to drag bars anywhere.",
                "Icons per row: more icons than fit across go onto another row, and each bar grows from its centre or from either edge.",
                "Layout page: one click stacks your bars around your Personal Resource Display, as a pyramid, wide rows, sides and more, flush or with the room you choose between rows and icons. The display widens to your widest row, or hide it and the rows close up; your bars follow it as it moves or changes with your form.",
                "Change a layout row by row: how many icons fit across, which bar goes in which row, and where the display sits in the stack. Drag icons between rows, or off a row to remove them. Take a whole bar out, or Reset back to the preset.",
                "Find a debuff on the Layout page: only your class's debuffs are listed, and you pick the spot in the Debuffs row it goes in.",
                "Cast bar page: your own cast bar right under your Personal Resource Display, in your bar design and colour, with the spell's icon, name and time left, and a live preview. Blizzard's cast bar is hidden while it's on. Off by default; off, your rows close up so another addon's cast bar works as before.",
                "Swing timer on the Cast bar page: your main hand and ranged swings (Auto Shot for hunters), in the cast bar's spot under your Personal Resource Display, in your bar design and a colour of its own, with a live preview. A cast takes the spot while it lasts. Off by default.",
                "Trinkets, potions, your Hearthstone and ammo can go on a bar too. Search to add spells outside your spellbook by name or spell ID, or tick Show all ranks to use a lower rank.",
            } },
            { "Settings", {
                "The first time you log in with the addon, its settings open with a quick tour of the basics: each step opens the right page and points at what it's about, and some let you try it. Skip it, or take it again any time from the General page or with /ccm tour.",
                "A minimap button: click it for the settings, right-click for What's new, and drag it round the minimap. Turn it off on the General page.",
                "Found a bug or have an idea? The Discord button on the General page and in What's new gives you the invite, or type /ccm discord.",
                "Profiles: each character gets its own lists, and characters can share one, even across classes: each character only shows its own class's spells and racials. Use on all characters puts one profile on every character. Switch, copy, rename or delete them from the Profile menu.",
                "Pick the window's accent colour on the Look page, and find EraUI, my other addon, under More from Squirt on the General page.",
            } },
        },
    },
}

local WIDTH, HEADER = 520, 42
local TOP, FOOT = 82, 52 -- above and below the notes
local TEXT = WIDTH - 48 -- the notes' width, clear of the scroll thumb
local BULLET = 16 -- bullet text indent
local MAX_HEIGHT = 620
local HISTORY = 3 -- this version's notes and the two before

local N = {}
ns.Notes = N

-- This version's notes and the ones before, or the newest if this version has
-- none (a copy straight from the source).
local function Entries()
    local version, start = ns.Version(), 1
    for i, entry in ipairs(ns.NOTES) do
        if entry.version == version then
            start = i
            break
        end
    end
    local list = {}
    for i = start, math.min(#ns.NOTES, start + HISTORY - 1) do list[#list + 1] = ns.NOTES[i] end
    return list
end

local function Label(version)
    return version:match("^%d") and "Version " .. version or version
end

local window

local function Build()
    window = CreateFrame("Frame", "FECMNotes", UIParent, "BackdropTemplate")
    window:SetSize(WIDTH, 400)
    window:SetPoint("CENTER", 0, 40)
    window:SetFrameStrata("FULLSCREEN_DIALOG")
    window:SetToplevel(true)
    window:SetClampedToScreen(true)
    window:EnableMouse(true)
    window:SetMovable(true)
    window:RegisterForDrag("LeftButton")
    window:SetScript("OnDragStart", window.StartMoving)
    window:SetScript("OnDragStop", window.StopMovingOrSizing)
    T:Flat(window, T.BG, T.CONTROL_BORDER)
    T:Paint(function(accent) window:SetBackdropBorderColor(accent[1], accent[2], accent[3], 1) end)
    window:Hide()
    -- Set before anything hooks it: setting a script later drops hooks.
    window:SetScript("OnHide", function(self)
        self:StopMovingOrSizing() -- closed mid-drag, it never hears the mouse let go
    end)
    ns.CloseOnEscape(window)
    ns.notes = window

    local header = T:TitleBar(window, HEADER)
    window.close = header.close
    local fade = T:Fade(window, T.FADE.page)
    fade:SetPoint("TOPLEFT", 1, -(HEADER + 1))
    fade:SetPoint("BOTTOMRIGHT", -1, 1)

    local entries = Entries()
    local heading = T:Heading(window, "What's new")
    heading:SetPoint("TOPLEFT", 20, -(HEADER + 18))
    window.version = T:Text(window, "GameFontHighlightSmall", T.MUTED)
    window.version:SetPoint("LEFT", heading, "RIGHT", 10, 0)
    window.version:SetText(Label(entries[1].version))

    -- The notes scroll between the heading and the footer, pinned by two
    -- corners, again once shown (see the bar page).
    local scroll = T:Scroll(window, TEXT)
    local function Pin()
        scroll:ClearAllPoints()
        scroll:SetPoint("TOPLEFT", 20, -TOP)
        scroll:SetPoint("BOTTOMRIGHT", -28, FOOT)
        scroll:ScrollTo(scroll:GetVerticalScroll() or 0)
    end
    Pin()
    window:HookScript("OnShow", function() C_Timer.After(0, Pin) end)
    window.scroll = scroll
    local content = scroll.content

    -- Each row with the space above it; placed by Layout once the text has
    -- its width.
    local flow = {}
    window.flow = flow
    for index, entry in ipairs(entries) do
        local gap = 0
        if index > 1 then
            local rule = content:CreateTexture(nil, "ARTWORK")
            rule:SetHeight(1)
            T:Fill(rule, T.BORDER)
            flow[#flow + 1] = { rule = rule, gap = 22 }
            local older = T:Text(content, "GameFontHighlight", T.MUTED)
            older:SetWidth(TEXT)
            older:SetText(Label(entry.version))
            flow[#flow + 1] = { text = older, gap = 14 }
            gap = 12
        end
        for s, section in ipairs(entry.sections) do
            local title = T:Heading(content, section[1])
            title:SetWidth(TEXT)
            flow[#flow + 1] = { text = title, gap = s > 1 and 18 or gap }
            for i, item in ipairs(section[2]) do
                local text = T:Text(content, "GameFontHighlight")
                text:SetWidth(TEXT - BULLET)
                text:SetText(item)
                -- A small accent square level with the first line.
                local _, size = text:GetFont()
                local dot = content:CreateTexture(nil, "ARTWORK")
                dot:SetSize(4, 4)
                T:Paint(function(accent) T:Fill(dot, accent) end)
                flow[#flow + 1] = { text = text, indent = BULLET, dot = dot, gap = i == 1 and 8 or 6,
                    dotY = math.max(2, math.floor((size or 12) / 2) - 1) }
            end
        end
    end

    -- Rows top to bottom; the window grows to fit, up to the screen.
    function window:Layout()
        local y = 0
        for _, row in ipairs(flow) do
            y = y + row.gap
            local region = row.rule or row.text
            region:ClearAllPoints()
            region:SetPoint("TOPLEFT", row.indent or 0, -y)
            if row.dot then
                row.dot:ClearAllPoints()
                row.dot:SetPoint("TOPLEFT", 4, -(y + row.dotY))
            end
            if row.rule then
                region:SetPoint("TOPRIGHT", 0, -y)
                y = y + 1
            else
                y = y + math.max(1, row.text:GetStringHeight() or 12)
            end
        end
        content:SetHeight(math.max(1, y))
        local room = math.max(200, math.min(MAX_HEIGHT, (UIParent:GetHeight() or MAX_HEIGHT) - 40))
        self:SetHeight(math.max(200, math.min(room, TOP + y + FOOT + 12)))
        scroll:ScrollTo(scroll:GetVerticalScroll() or 0)
    end
    window:RegisterEvent("UI_SCALE_CHANGED")
    window:RegisterEvent("DISPLAY_SIZE_CHANGED")
    window:SetScript("OnEvent", function(self) if self:IsShown() then self:Layout() end end)

    -- Two short lines on the left: where to take a bug or an idea, and how to
    -- see this again. On the right Got it, then Show me what's new while
    -- there's a tour of it, then the Discord button.
    local ask = T:Text(window, "GameFontHighlightSmall")
    ask:SetPoint("BOTTOMLEFT", 20, 27)
    ask:SetText("Found a bug or have an idea?")
    local hint = T:Text(window, "GameFontHighlightSmall", T.MUTED)
    hint:SetPoint("BOTTOMLEFT", 20, 13)
    hint:SetText("See it again in the settings.")
    window.hint = hint
    local done = T:Button(window, "Got it", 100, 24)
    done:SetPoint("BOTTOMRIGHT", -16, 14)
    T:Paint(function(accent) done:SetBackdropBorderColor(accent[1], accent[2], accent[3], 1) end)
    done:SetScript("OnClick", function() window:Hide() end)
    window.done = done
    -- Closes this for the tour, which opens the settings. Its tooltip says
    -- what it does, as the label has no room to.
    local tour = T:Button(window, "Show me what's new", 120, 24)
    tour:SetPoint("RIGHT", done, "LEFT", -8, 0)
    tour:SetScript("OnClick", function()
        window:Hide()
        if ns.Tour then ns.Tour:StartNews(window.seen) end
    end)
    tour:HookScript("OnEnter", function(self)
        T:ShowTip(self, "Show me what's new", "A quick tour of what's new, a page at a time.")
    end)
    tour:HookScript("OnLeave", function() T:HideTip() end)
    window.tour = tour
    local discord = T:Button(window, "Discord", 80, 24)
    discord:SetPoint("RIGHT", done, "LEFT", -8, 0)
    discord:SetScript("OnClick", function() if ns.ShowDiscord then ns.ShowDiscord() end end)
    window.discord, window.ask = discord, ask
end

-- seen: after an update, the version whose notes were seen before it, so
-- the tour takes in every step since. Opened by hand, the tour offered is
-- the latest update's.
function ns.ShowNotes(seen)
    if #ns.NOTES == 0 then return end
    if not window then Build() end
    window.seen = type(seen) == "string" and seen or nil
    local tour = ns.Tour ~= nil and #ns.Tour:News(window.seen) > 0
    window.tour:SetShown(tour)
    window.discord:ClearAllPoints()
    window.discord:SetPoint("RIGHT", tour and window.tour or window.done, "LEFT", -8, 0)
    -- Raid Timers' secure Edit Mode button taken away first, or it would sit
    -- on top of this and take its clicks (RaidTimersPage.lua).
    if ns.EditModeAway then ns.EditModeAway() end
    window:Show()
    window:Raise()
    window:Layout()
    window.scroll:ScrollTo(0)
end

-- Once per version: a moment after the first login with it, and never in
-- combat. A first install has nothing new to show: the window opens instead,
-- with the offer of a tour. Each is marked seen only as it shows, so a
-- reload or logout before then (or during a fight) keeps it due.
function N:Start()
    local version, seen = ns.Version(), ns.NotesSeen()
    local welcome = ns.firstInstall or ns.WelcomeDue()
    if seen == version and not welcome then return end
    if not welcome and #ns.NOTES == 0 then
        ns.SetNotesSeen(version)
        return
    end
    local events = CreateFrame("Frame")
    local due, waiting = false, false
    local function ShowWhenFree()
        if not due or InCombatLockdown() then return end
        due = false
        events:UnregisterAllEvents()
        ns.SetNotesSeen(version)
        if not welcome then return ns.ShowNotes(seen) end
        ns.SetWelcomeDue(false)
        if ns.Tour then ns.Tour:Welcome() else ns.ShowWindow() end
    end
    events:RegisterEvent("PLAYER_ENTERING_WORLD")
    events:RegisterEvent("PLAYER_REGEN_ENABLED")
    events:SetScript("OnEvent", function(_, event)
        if event ~= "PLAYER_ENTERING_WORLD" then return ShowWhenFree() end
        if waiting then return end
        waiting = true
        C_Timer.After(2, function()
            due = true
            ShowWhenFree()
        end)
    end)
end
