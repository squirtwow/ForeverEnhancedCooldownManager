-- What's new: this version's notes, shown once after the addon updates (a
-- first install has nothing new to show), then any time from What's new in
-- /fecm or /fecm new. The releases before it follow underneath. Drawn in the
-- window's flat style.
local _, ns = ...
local T = ns.Theme

-- Newest first, word for word as in CHANGELOG.txt (Tools/TestNotes.mjs checks).
-- Notes waiting for their version number are "Unreleased".
ns.NOTES = {
    {
        version = "Unreleased",
        sections = {
            { "Blizzard's Cooldown Manager", {
                "A new look: square icons with big, bold countdown numbers, and Tracked Bars in three designs (Glass, Split and Outline) and six colours. Any Tracked Bar can have a colour of its own. On by default, in /fecm > Look.",
                "Your Personal Resource Display's health and power bars get the same look, in Blizzard's colours or your own. The extra mana bar some specs get hides in caster form and is half size in forms.",
                "If Blizzard's Cooldown Manager or Personal Resource Display is off, /fecm tells you and can turn it on.",
            } },
            { "Your own bars", {
                "Cooldowns, Utility, Buffs and Debuffs bars, set up in /fecm by ticking spells or dragging them in from your spellbook. Each spell shows once, at your highest rank, and switches when you train a new one. Off until you tick Use my bars on the General page.",
                "Cooldown icons show the sweep and countdown in combat: grey while cooling down, red out of range, blue without enough mana, and a gold edge when a reactive ability like Overpower is ready.",
                "Buffs bar: your buffs and class procs (Clearcasting, Shadow Trance and more) with time left and stacks. Buffs from other players count at any rank, group versions too.",
                "Debuffs bar: your own debuffs on your target.",
                "Join entries on the Buffs and Debuffs bars to show one icon for whichever is up, for seals, auras, aspects or stings.",
                "Each bar has its own icon size, spacing and options: hide when ready, spell names, countdown numbers, and show, fade or hide out of combat. Unlock to drag bars anywhere.",
                "Icons per row: more icons than fit across go onto another row, and each bar grows from its centre or from either edge.",
                "Layout page: one click stacks your bars around your Personal Resource Display, as a pyramid, wide rows, sides and more, flush or with the room you choose between rows and icons. The display widens to your widest row, or hide it and the rows close up; your bars follow it as it moves or changes with your form.",
                "Change a layout row by row: how many icons fit across, which bar goes in which row, and where the display sits in the stack. Drag icons between rows, or off a row to remove them.",
                "Trinkets, potions, your Hearthstone and ammo can go on a bar too. Search to add spells outside your spellbook by name or spell ID, or tick Show all ranks to use a lower rank.",
            } },
            { "Settings", {
                "Profiles: each character gets its own lists, and characters can share one. Switch, copy, rename or delete them from the Profile menu.",
                "Your settings are also backed up in the game's own settings, so they come back if the game loses them, and you're told when that happens.",
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
    -- Set before anything hooks them: setting a script later drops hooks.
    window:SetScript("OnShow", function() ns.EscUpdate() end)
    window:SetScript("OnHide", function() ns.EscUpdate() end)
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

    local hint = T:Text(window, "GameFontHighlightSmall", T.MUTED)
    hint:SetPoint("BOTTOMLEFT", 20, 21)
    hint:SetText("/fecm new shows this again.")
    local done = T:Button(window, "Got it", 100, 24)
    done:SetPoint("BOTTOMRIGHT", -16, 14)
    T:Paint(function(accent) done:SetBackdropBorderColor(accent[1], accent[2], accent[3], 1) end)
    done:SetScript("OnClick", function() window:Hide() end)
    window.done = done
end

function ns.ShowNotes()
    if #ns.NOTES == 0 then return end
    if not window then Build() end
    window:Show()
    window:Raise()
    window:Layout()
    window.scroll:ScrollTo(0)
end

-- Once per version: a moment after the first login with it, and never in
-- combat. A first install only notes the version.
function N:Start()
    local version = ns.Version()
    if ns.NotesSeen() == version then return end
    ns.SetNotesSeen(version)
    if ns.firstInstall or #ns.NOTES == 0 then return end
    local events = CreateFrame("Frame")
    local due, waiting = false, false
    local function ShowWhenFree()
        if not due or InCombatLockdown() then return end
        due = false
        events:UnregisterAllEvents()
        ns.ShowNotes()
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
