-- The tour: the basics a step at a time, like the game's own tips for new
-- characters. Each step opens the page it's about, outlines the part it
-- means in the accent, and explains it in a box beside it with Back, Next and
-- Skip tour. A Try it step can move on by itself once you've done what it
-- asks. The tour only opens pages and points: it never changes a setting,
-- and the outline takes no clicks. A first install opens the window with a
-- welcome that offers it; after that it's on the General page and /ccm tour.
-- Each step has the version it arrived in, and What's new offers a shorter
-- tour of just the steps an update added (Show me what's new). The ? in
-- the window's title bar walks through the page showing: every step about
-- it, from the tour, What's new and the page help (HELP), without leaving it.
local _, ns = ...
local T = ns.Theme

local Tour = {}
ns.Tour = Tour

local FLAT = "Interface\\Buttons\\WHITE8X8"
local BOX_WIDTH, PAD = 290, 10
local GAP = 14 -- between the part outlined and the box
local OUTLINE = 4 -- how far outside that part the outline sits
local CHECK_EVERY = .25 -- how often a Try it step looks to see if it's done
local TOUR_NOTE = "Take the tour any time from the General page, or with /ccm tour."
local NEWS_NOTE = "See it again any time from What's new, or with /ccm new."
local PAGE_NOTE = "Click ? any time to see it again."

local window, box, outline
local steps, index, started, welcome
local news -- the tour showing is What's new's
local here -- the page a page's walkthrough is about, while one shows
local since = 0

-- Which bars a step on a bar page is for, where it isn't all four: a tick
-- or choice only some bars' pages show.
local SPELL_BARS = { cd = true, util = true }
local AURA_BARS = { buff = true, debuff = true }

-- The bar page showing, or Cooldowns: what a bar page's step talks about.
local function ShownBar()
    local key = window and window.selected
    return ns.BAR_NAMES[key] and key or "cd"
end

local function Value(value, ...)
    if type(value) == "function" then return value(...) end
    return value
end

-- Spells on your four bars together: adding one counts wherever it goes.
local function SpellCount()
    local count = 0
    for _, key in ipairs(ns.BAR_KEYS) do count = count + #ns.BarData(key).spells end
    return count
end

-- The minimap button, while there's one to point at (EraUI can fade it).
local function MinimapButton()
    local button = ns.MinimapButton and ns.MinimapButton:Button()
    if button and button:IsVisible() and button:GetAlpha() > .5 then return button end
end

-- Whether the profile menu in the header is open.
local function ProfilesOpen(w)
    return w.profilePanel ~= nil and w.profilePanel:IsShown()
end

-- The end of the Look step, once the look is on or waiting for a reload.
local PICK = " Pick its design, colour, border and shadow here. Your own bars use them too."

-- Whether there's a Raid Timers page: its files only load after a full
-- restart. Asked before the window is made, for What's new's button.
local function RaidTimersPage()
    return ns.BuildRaidTimersPage ~= nil
end

-- The same for the Cooldown pulse page.
local function PulsePage()
    return ns.BuildPulsePage ~= nil
end

-- The addon whose own pulse runs instead, Forever Enhanced Cooldown Pulse,
-- while it does; else nil (Pulse.lua).
local function PulseElsewhere()
    return ns.Pulse and ns.Pulse.Elsewhere and ns.Pulse:Elsewhere() or nil
end

-- How many cooldowns are ticked to pulse, for its Try it.
local function PulsePicks()
    local count = 0
    for _ in pairs(ns.PulsePicks and ns.PulsePicks() or {}) do count = count + 1 end
    return count
end

-- The steps of the full tour, the basics. version: the version the step
-- arrived in. page: the page it opens (none keeps the one showing); a bar
-- page's step ("cd") is about any bar's page, or only those in bars. when:
-- whether it can show here, if it can't always. target: the part it
-- outlines, or the first and last of a row of them. side: where the box
-- goes, "right", "left", "below" or "above"; align "end" lines the box up
-- with the far end, where the side has one. A Try it step
-- moves on by itself when it has watch, a count that goes up once it's done,
-- unless already says it was done before the step began; without watch it
-- waits for Next, for a step with more to do after it.
local STEPS = {
    {
        version = "1.0.0",
        title = "The menu",
        text = function()
            -- The pages under More, as they're there.
            local more = {}
            if RaidTimersPage() then more[#more + 1] = "Raid Timers" end
            if ns.BuildPulsePage then more[#more + 1] = "Cooldown pulse" end
            return "Everything is in this list: your four bars at the top, then Look, Layout, Cast bar and General"
                .. (#more > 0 and (", and " .. table.concat(more, " and ") .. " under More.") or ".")
        end,
        target = function(w) return w.navFrame end,
        side = "right",
    },
    {
        version = "1.0.0",
        page = "general",
        title = "Switch your bars on",
        text = "Your own bars start off. Tick Use my bars to switch them on.",
        try = "Try it: tick it.",
        already = function() return ns.Bars:Enabled() end,
        alreadyText = "They're already on.",
        watch = function() return ns.Bars:Enabled() and 1 or 0 end,
        target = function(w) return w.useBars end,
        side = "below",
    },
    {
        version = "1.0.0",
        page = "cd",
        title = "Add spells",
        text = "Tick spells in this list, or drag them in from your spellbook. Utility, Buffs and Debuffs work the same way.",
        try = "Try it: add a spell.",
        watch = SpellCount,
        target = function(w) return w.pages.bar.listPanel end,
        side = "above",
    },
    {
        version = "1.0.0",
        page = "cd",
        title = "This bar's options",
        text = "Icon size, spacing, icons per row, and whether the bar shows out of combat. Each bar has its own.",
        target = function(w) return w.pages.bar.optionsArea end,
        side = "below",
    },
    {
        version = "1.0.0",
        page = "layout",
        title = "Layouts",
        text = "One click stacks your bars round your Personal Resource Display. Then change any row, or drag icons between rows.",
        target = function(w)
            local cards = w.pages.layout.cards
            return cards[1], cards[#cards]
        end,
        side = "below",
    },
    {
        version = "1.0.0",
        page = "look",
        title = "The look",
        text = function()
            if not ns.CooldownManagerOn() then
                return "Blizzard's Cooldown Manager is off, and its new look needs it. Turn on switches it on."
            end
            -- Only say it has the look when the look really started at login.
            if not ns.loaded.skin then
                if ns.Get("skin") then
                    return "Reload to apply, and Blizzard's Cooldown Manager gets the new look." .. PICK
                end
                return "Tick Apply this look to the Cooldown Manager, then reload, for its new look." .. PICK
            end
            if not ns.Get("skin") then
                return "Blizzard's Cooldown Manager goes back to its own look when you reload, as Apply this look is unticked."
                    .. " Your own bars still use the design, colour, border and shadow picked here."
            end
            return "Blizzard's Cooldown Manager already has the new look." .. PICK
        end,
        target = function(w)
            if ns.CooldownManagerOn() then return w.lookOptions end
            return w.turnOnManager
        end,
        side = "below",
    },
    {
        version = "1.0.0",
        page = "cast",
        -- The page's file only loads after a full restart. Asked before the
        -- window is made, for What's new's button.
        when = function() return ns.BuildCastBarPage ~= nil end,
        title = "Cast bar",
        text = "Tick the first for your own cast bar under your resource display, or leave it off if you use a cast bar addon."
            .. " The second adds a swing timer in the same spot.",
        -- Both ticks, so the box goes under the swing timer's, not over it.
        target = function(w) return w.pages.cast.ticks end,
        side = "below",
    },
    {
        version = "1.0.0",
        title = "Profiles",
        text = function()
            -- Share and Import: a new file, so only after a full restart.
            return "Each character has its own spell lists. Use one on several characters, even across classes, or on all of them."
                .. " Tank, Healer and Damage keep a profile for each role, and Switch with my talents can pick one for you."
                .. (ns.ProfileShare and " Share and Import trade profiles with other players as text." or "")
        end,
        -- Once the menu is open the box moves beside it, so it never covers it.
        target = function(w) return ProfilesOpen(w) and w.profilePanel or w.profileButton end,
        side = function(w) return ProfilesOpen(w) and "left" or "below" end,
        align = "end",
    },
    {
        version = "1.0.0",
        title = "That's the basics",
        text = function()
            return (MinimapButton() and "Open these settings any time with this button or /ccm."
                or "Open these settings any time from Options > AddOns, or with /ccm.")
                .. " What's new shows after each update, and this tour is on the General page."
        end,
        target = function(w) return MinimapButton() or w.versionText end,
        side = function() return MinimapButton() and "below" or "above" end,
        align = function() return MinimapButton() and "end" or nil end,
    },
}

-- Steps only What's new tours, for what an update added after the basics.
-- The same fields as above. Steps waiting for the next update's number are
-- ns.UNRELEASED; the release gives them that number.
local NEWS = {
    {
        version = "1.1.0",
        page = "look",
        when = function() return ns.Keybinds ~= nil end, -- a new file: only after a full restart
        title = "Keybinds on icons",
        text = "Your action bar keys on your Cooldowns and Utility icons, and on Blizzard's while Apply this look is ticked."
            .. " Pick where the key sits and how big it is.",
        -- No watch: the position and size only work once it's ticked, so the
        -- step stays for them until Next.
        try = "Try it: tick it.",
        already = function() return ns.Get("keybinds") end,
        alreadyText = "They're already on.",
        -- The tick, the position and the size; the box under the size, at its
        -- right, clear of all three.
        target = function(w) return w.keybinds, w.keySize end,
        side = "below",
        align = "end",
    },
    {
        version = "1.1.0",
        page = "layout",
        title = "Live preview",
        text = "Your icons here now have the border, shadow and keybinds from the Look page, as on your bars. Untick Live preview for plain icons.",
        target = function(w) return w.pages.layout.live end,
        -- Above it, over the drawing's foot: the tick is in its box's corner.
        side = "above",
    },
    {
        version = "1.1.0",
        page = "layout",
        title = "All bars",
        text = "Makes all your bars bigger or smaller together, each keeping its size next to the others. A bar's own Icon size still fine-tunes it.",
        target = function(w) return w.pages.layout.allBars end,
        side = "above",
    },
    {
        version = "1.2.0",
        page = "cd",
        title = "Healthstones and potions",
        text = "Healthstones, healing potions and mana potions: one icon each on a bar, for the best rank you carry."
            .. " They're with your items, or drag one in.",
        -- No watch: ticking it lists them, and the step stays so they can be seen.
        try = "Try it: tick Show items.",
        already = function() return ns.Get("listItems") end,
        alreadyText = "Your items are already listed.",
        bars = SPELL_BARS, -- the Buffs and Debuffs bars list no items
        target = function(w) return w.pages.bar.showItems end,
        -- Above the tick, clear of the list it fills.
        side = "above",
    },
    {
        version = "1.2.0",
        page = "cd",
        title = "Dim when ready",
        text = "Each bar's ready icons can now dim instead of hiding: the ones cooling down stand out, and every icon keeps its place.",
        -- No watch: the step stays so the bar can be seen dimming.
        try = "Try it: pick Dim.",
        -- The bar showing: Cooldowns, or Utility from its own page.
        already = function() return ns.BarData(ShownBar()).whenReady == "dim" end,
        alreadyText = function() return ns.BAR_NAMES[ShownBar()] .. " already dims its ready icons." end,
        bars = SPELL_BARS, -- the aura bars show missing ones greyed instead
        -- The label and its three choices as one part, the box under them.
        target = function(w) return w.pages.bar.options.whenReady.part end,
        side = "below",
    },
    {
        version = "1.2.0",
        page = "look",
        title = "Font and bar texture",
        text = "Pick the font for the numbers, keys and names on your icons, and the texture for your bars."
            .. " The preview at the top shows them.",
        -- No watch: the step stays so a few can be tried.
        try = "Try it: pick a font or a texture.",
        -- Both rows, the box under them at their right end, so the preview
        -- above stays in sight.
        target = function(w) return w.faces end,
        side = "below",
        align = "end",
    },
    {
        version = "1.2.0",
        page = "layout",
        title = "Grow arrows",
        text = "While your bars are unlocked, or in Edit Mode, an arrow on each shows which way it grows, and where a new row goes.",
        -- No watch: the arrows only show once the bars are unlocked, so the
        -- step stays until Next.
        try = "Try it: tick it, then Unlock bars.",
        already = function() return ns.Get("growArrows") end,
        alreadyText = "They're already on: Unlock bars to see them.",
        target = function(w) return w.pages.layout.growArrows end,
        -- Above it, clear of Unlock bars to the right.
        side = "above",
    },
    {
        version = "1.4.1",
        page = "raid",
        when = RaidTimersPage,
        title = "Raid Timers",
        text = "Your look on Blizzard's pull countdown, raid warnings, boss emotes and boss cast bars,"
            .. " in raids and dungeons. Each part is off until you tick it.",
        -- No watch: ticking one lights its preview, and the step stays so it
        -- can be seen.
        try = "Try it: tick one and watch the preview.",
        already = function() return ns.Get("pullTimer") or ns.Get("raidWarnings") or ns.Get("bossCasts") end,
        alreadyText = "Already on: the preview shows your look.",
        -- The preview and the ticks along its foot as one part; the box under
        -- its right end, over the raid warnings' choices, so the countdown's
        -- and the boss cast bars' ticks stay in sight.
        target = function(w) return w.pages.raid.top end,
        side = "below",
        align = "end",
    },
    {
        version = "1.4.1",
        page = "raid",
        when = RaidTimersPage,
        title = "Sizes",
        -- The boss cast bars have no size here: they keep Blizzard's.
        text = "Size the countdown, raid warnings and emotes once ticked, or all of them with All sizes."
            .. " Boss cast bars keep Blizzard's size.",
        -- All sizes, the last of them; the box under it, below the options,
        -- so each part's own sizes stay in sight.
        target = function(w)
            local sizes = w.pages.raid.sizes
            return sizes[#sizes]
        end,
        side = "below",
        align = "end",
    },
    {
        version = "1.4.1",
        page = "raid",
        when = RaidTimersPage,
        title = "Edit Mode",
        -- No Try it: Edit Mode opening closes the window and the tour with
        -- it, so this step is the last.
        text = "Boss cast bars only show in a boss fight. To see them now, click the Edit Mode button,"
            .. " then tick Boss Frames in Edit Mode.",
        -- The button; the box under it, clear of it and the boss cast bars'
        -- tick.
        target = function(w) return w.pages.raid.editMode end,
        side = "below",
    },
    {
        version = "1.5.0",
        page = "pulse",
        when = PulsePage,
        title = "Turn it on",
        -- With Forever Enhanced Cooldown Pulse's own pulse on, it runs
        -- there, and this tick is greyed out.
        text = function()
            local elsewhere = PulseElsewhere()
            if elsewhere then
                return "Cooldown pulse is on in " .. elsewhere .. ", so it runs there and this tick waits."
                    .. " Turn it off there to use this one."
            end
            return "Cooldown pulse, under More: a big icon in the middle of your screen the moment a cooldown is ready,"
                .. " in a fight too. Off until you tick it."
        end,
        try = "Try it: tick it.",
        already = function() return ns.Get("pulse") or PulseElsewhere() ~= nil end,
        alreadyText = function()
            return PulseElsewhere() and "Nothing to do here while it runs there." or "It's already on."
        end,
        watch = function() return ns.Get("pulse") and 1 or 0 end,
        -- The tick; the box under it, over the choices that follow.
        target = function(w) return w.pages.pulse.master end,
        side = "below",
    },
    {
        version = "1.5.0",
        page = "pulse",
        when = PulsePage,
        title = "Pick your cooldowns",
        text = "Every spell you know with a cooldown, and your trinkets and potions. Tick the ones to pulse,"
            .. " then pick Quick or Long for each.",
        -- No watch: once one is ticked, Quick or Long is still to pick.
        try = "Try it: tick one.",
        already = function() return PulsePicks() > 0 end,
        alreadyText = "You've ticked some already.",
        -- The list; the box above it, so its rows stay in sight.
        target = function(w) return w.pages.pulse.panel end,
        side = "above",
    },
    {
        version = "1.5.0",
        page = "pulse",
        when = PulsePage,
        title = "Quick and Long",
        text = "Each has its own size, time and sound. Pick one under Edit: Size, Shows for and Sound follow it,"
            .. " and Preview plays it.",
        -- No watch: Long picked, its own size, time and sound are to try.
        try = "Try it: pick Long, then Preview.",
        -- Edit and the three it picks for; the box beside them, over the
        -- look both styles share.
        target = function(w) return w.pages.pulse.styles end,
        side = "right",
    },
    {
        version = "1.5.0",
        page = "pulse",
        when = PulsePage,
        title = "Where it shows",
        text = "Move shows a box as big as the pulse: drag it where you want it, then click Done."
            .. " Reset puts it back in the middle.",
        -- No Try it: Move puts the window away while the box shows.
        target = function(w)
            local page = w.pages.pulse
            return page.move, page.reset
        end,
        side = "below",
    },
    {
        version = "1.5.0",
        page = "look",
        title = "Ready glow",
        text = "How a ready ability like Overpower, Riposte or Mongoose Bite lights up on your own bars:"
            .. " Blizzard's proc glow, or a plain gold edge.",
        -- No watch: the step stays so both can be seen.
        try = "Try it: pick Gold edge.",
        -- The label and its choices at the page's foot; the box above them,
        -- at their right end, inside the page.
        target = function(w) return w.readyGlow.part end,
        side = "above",
        align = "end",
    },
}

-- Steps only a page's own walkthrough shows (the ? in the title bar), for
-- pages with little in the tour or What's new: never in either. The same
-- fields, with no version.
local HELP = {
    {
        page = "cd",
        bars = AURA_BARS,
        title = "Missing ones greyed",
        text = function()
            if ShownBar() == "debuff" then
                return "Ticked, each debuff keeps its spot, greyed while it's missing from your target."
                    .. " Unticked, only the ones up show, in one row."
            end
            return "Ticked, each buff keeps its spot, greyed while it's missing from you. Unticked, only the ones up show, in one row."
        end,
        target = function(w) return w.pages.bar.options.showMissing end,
        side = "below",
    },
    {
        page = "cd",
        bars = AURA_BARS,
        title = "Join two into one",
        text = "With two on the bar, the + between them in the tray joins them into one icon, lit by whichever is up."
            .. " The - splits them again.",
        target = function(w) return w.pages.bar.tray end,
        side = "below",
    },
    {
        page = "cd",
        bars = AURA_BARS,
        title = "Your debuffs on you",
        text = function()
            if ShownBar() == "debuff" then
                return "Shows debuffs you put on yourself, like Weakened Soul or Recently Bandaged, at the end of this bar."
                    .. " Not with missing debuffs greyed."
            end
            return "Shows debuffs you put on yourself, like Weakened Soul or Recently Bandaged, after your buffs."
                .. " Not with missing buffs greyed."
        end,
        target = function(w) return w.pages.bar.options.showSelf end,
        side = "below",
    },
    {
        page = "cast",
        when = function() return ns.BuildCastBarPage ~= nil end,
        title = "Colours",
        text = "A colour for your cast bar and one for your swing timer. Click the chosen one again for Blizzard's gold, or silver.",
        -- Below: to the right, the box would cover the chosen colour's name.
        target = function(w) return w.pages.cast.colours end,
        side = "below",
    },
    {
        page = "cast",
        when = function() return ns.BuildCastBarPage ~= nil end,
        title = "Height and parts",
        text = "How tall both bars are, and whether the icon, the name and the time left show on them. The preview changes as you pick.",
        target = function(w) return w.pages.cast.parts end,
        side = "right",
    },
    {
        page = "general",
        title = "Minimap button",
        text = "Click it for these settings, right-click for What's new, and drag it round the minimap."
            .. " Untick to hide it: Options > AddOns and /ccm still open them.",
        target = function(w) return w.minimap end,
        side = "right",
    },
    {
        page = "general",
        title = "Help",
        text = "Take the tour shows you the basics again. Discord gives you the invite to copy, for help, bugs and ideas.",
        target = function(w) return w.tour, w.discord end,
        side = "below",
    },
}

-- Where the box goes against what it points at, and its arrow on the box's
-- edge: the box's point, the target's point, the offset, the arrow's point
-- on the box and its offset, and which way the arrow faces.
local PLACES = {
    right = { "TOPLEFT", "TOPRIGHT", GAP, 0, "RIGHT", "TOPLEFT", 0, -20, "left" },
    left = { "TOPRIGHT", "TOPLEFT", -GAP, 0, "LEFT", "TOPRIGHT", 0, -20, "right" },
    below = { "TOPLEFT", "BOTTOMLEFT", 0, -GAP, "BOTTOM", "TOPLEFT", 24, 0, "up" },
    above = { "BOTTOMLEFT", "TOPLEFT", 0, GAP, "TOP", "BOTTOMLEFT", 24, 0, "down" },
    belowEnd = { "TOPRIGHT", "BOTTOMRIGHT", 0, -GAP, "BOTTOM", "TOPRIGHT", -24, 0, "up" },
    aboveEnd = { "BOTTOMRIGHT", "TOPRIGHT", 0, GAP, "TOP", "BOTTOMRIGHT", -24, 0, "down" },
}
local ALIGNS = { ["end"] = "End" }

local function Strip(frame, layer)
    local strip = frame:CreateTexture(nil, layer)
    strip:SetTexture(FLAT)
    return strip
end

-- A ring of four strips, `width` thick, `out` pixels outside the frame's edge.
local function Ring(frame, width, out, layer)
    local top, bottom, left, right = Strip(frame, layer), Strip(frame, layer), Strip(frame, layer), Strip(frame, layer)
    top:SetPoint("TOPLEFT", -out, out)
    top:SetPoint("TOPRIGHT", out, out)
    top:SetHeight(width)
    bottom:SetPoint("BOTTOMLEFT", -out, -out)
    bottom:SetPoint("BOTTOMRIGHT", out, -out)
    bottom:SetHeight(width)
    left:SetPoint("TOPLEFT", -out, out)
    left:SetPoint("BOTTOMLEFT", -out, -out)
    left:SetWidth(width)
    right:SetPoint("TOPRIGHT", out, out)
    right:SetPoint("BOTTOMRIGHT", out, -out)
    right:SetWidth(width)
    return { top, bottom, left, right }
end

local function Build()
    window = ns.window
    -- The outline: the accent, with a soft edge, gently pulsing.
    outline = CreateFrame("Frame", nil, window)
    outline:SetFrameStrata("FULLSCREEN_DIALOG")
    outline:SetFrameLevel(window:GetFrameLevel() + 70)
    local line = Ring(outline, 2, 0, "OVERLAY")
    local soft = Ring(outline, 3, 3, "ARTWORK")
    T:Paint(function(accent)
        for _, strip in ipairs(line) do strip:SetVertexColor(accent[1], accent[2], accent[3], 1) end
        for _, strip in ipairs(soft) do strip:SetVertexColor(accent[1], accent[2], accent[3], .3) end
    end)
    local pulse = 0
    outline:SetScript("OnUpdate", function(self, elapsed)
        pulse = pulse + elapsed
        self:SetAlpha(.55 + .45 * (1 + math.sin(pulse * 4)) / 2)
    end)
    outline:Hide()

    box = CreateFrame("Frame", "FECMTour", window, "BackdropTemplate")
    box.outline = outline
    box:SetWidth(BOX_WIDTH)
    box:SetFrameStrata("FULLSCREEN_DIALOG")
    box:SetFrameLevel(window:GetFrameLevel() + 80)
    box:SetClampedToScreen(true)
    box:EnableMouse(true)
    T:Flat(box, T.BG, T.CONTROL_BORDER)
    box.title = T:Heading(box, "")
    box.title:SetPoint("TOPLEFT", PAD, -PAD)
    box.count = T:Text(box, "GameFontHighlightSmall", T.MUTED)
    box.count:SetPoint("TOPRIGHT", -PAD, -PAD)
    box.count:SetJustifyH("RIGHT")
    box.text = T:Text(box, "GameFontHighlightSmall")
    box.text:SetPoint("TOPLEFT", PAD, -(PAD + 16))
    box.text:SetWidth(BOX_WIDTH - 2 * PAD)
    box.arrow = box:CreateTexture(nil, "ARTWORK")
    box.arrow:SetTexture(ns.MEDIA .. "TourArrow.tga")
    local nextButton = T:Button(box, "Next", 64, 20)
    nextButton:SetPoint("BOTTOMRIGHT", -PAD, PAD)
    local back = T:Button(box, "Back", 64, 20)
    back:SetPoint("RIGHT", nextButton, "LEFT", -6, 0)
    local skip = T:Button(box, "Skip tour", 76, 20)
    skip:SetPoint("BOTTOMLEFT", PAD, PAD)
    T:Paint(function(accent)
        box:SetBackdropBorderColor(accent[1], accent[2], accent[3], 1)
        box.arrow:SetVertexColor(accent[1], accent[2], accent[3], 1)
        nextButton:SetBackdropBorderColor(accent[1], accent[2], accent[3], 1)
    end)
    nextButton:SetScript("OnClick", function()
        if welcome then Tour:Start() else Tour:Next() end
    end)
    back:SetScript("OnClick", function() Tour:Back() end)
    skip:SetScript("OnClick", function()
        local note = here and PAGE_NOTE or news and NEWS_NOTE or TOUR_NOTE
        Tour:Stop()
        window:Say(note)
        window:Refresh()
    end)
    box.next, box.back, box.skip = nextButton, back, skip
    -- A Try it step watches for what it asked for.
    box:SetScript("OnUpdate", function(_, elapsed)
        local step = steps and index and steps[index]
        if not (step and step.watch and started) then return end
        since = since + elapsed
        if since < CHECK_EVERY then return end
        since = 0
        if step.watch() > started then Tour:Next() end
    end)
    box:Hide()
    -- Closing the window ends the tour.
    window:HookScript("OnHide", function() Tour:Stop() end)
    -- Opening or closing the profile menu moves the box beside it, or back.
    if window.profilePanel then
        window.profilePanel:HookScript("OnShow", function() Tour:Repoint() end)
        window.profilePanel:HookScript("OnHide", function() Tour:Repoint() end)
    end
end

local function Ready()
    if not ns.ShowWindow then return false end
    ns.ShowWindow()
    if not box then Build() end
    return true
end

-- Sizes the box round its text: the title row, the text, then the buttons.
local function Fit()
    box:SetHeight(PAD + 16 + math.ceil(box.text:GetStringHeight() or 0) + 12 + 20 + PAD)
end

-- A bar page counts as any bar's page: the list and options are the same.
local function Same(a, b)
    return a == b or (ns.BAR_NAMES[a] ~= nil and ns.BAR_NAMES[b] ~= nil)
end

local function Point(step)
    local first, last = Value(step.target, window)
    last = last or first
    if not first then
        outline:Hide()
        box.arrow:Hide()
        box:ClearAllPoints()
        box:SetPoint("CENTER", window, "CENTER", 90, 30)
        return
    end
    outline:ClearAllPoints()
    outline:SetPoint("TOPLEFT", first, "TOPLEFT", -OUTLINE, OUTLINE)
    outline:SetPoint("BOTTOMRIGHT", last, "BOTTOMRIGHT", OUTLINE, -OUTLINE)
    outline:Show()
    local side = Value(step.side, window) or "below"
    local align = ALIGNS[Value(step.align, window)]
    local place = (align and PLACES[side .. align]) or PLACES[side] or PLACES.below
    local anchor = place[2]:find("RIGHT") and last or first
    box:ClearAllPoints()
    box:SetPoint(place[1], anchor, place[2], place[3], place[4])
    local arrow = box.arrow
    arrow:ClearAllPoints()
    arrow:SetPoint(place[5], box, place[6], place[7], place[8])
    if place[9] == "left" then
        arrow:SetSize(9, 16)
        arrow:SetTexCoord(1, 0, 0, 0, 1, 1, 0, 1)
    elseif place[9] == "right" then
        arrow:SetSize(9, 16)
        arrow:SetTexCoord(1, 1, 0, 1, 1, 0, 0, 0)
    else
        arrow:SetSize(16, 9)
        if place[9] == "up" then arrow:SetTexCoord(0, 1, 0, 1) else arrow:SetTexCoord(0, 1, 1, 0) end
    end
    arrow:Show()
end

local function Show(i)
    index, welcome = i, nil
    local step = steps[i]
    -- A page's walkthrough stays on its page (any bar's, for a bar page's
    -- steps), going back to it should another have been picked meanwhile.
    if here then
        if window.selected ~= here then window:Select(here) end
    elseif step.page then
        window:Select(step.page)
    end
    local text = Value(step.text, window)
    local already = step.already and step.already()
    if step.try then
        text = text .. "\n\n|cff" .. T:Hex(T:Accent()) .. (already and Value(step.alreadyText, window) or step.try) .. "|r"
    end
    box.title:SetText(step.title:upper())
    box.count:SetText(i .. " of " .. #steps)
    box.count:Show()
    box.text:SetText(text)
    box.back:SetShown(i > 1)
    box.next:SetWidth(64)
    box.next:SetLabel(i == #steps and "Done" or "Next")
    box.skip:SetLabel("Skip tour")
    started = step.watch and not already and step.watch() or nil
    since = 0
    Fit()
    Point(step)
    box:Show()
    box:Raise()
end

-- The tour from the start, over the window.
function Tour:Start()
    if not Ready() then return end
    steps, news, here = {}, nil, nil
    for _, step in ipairs(STEPS) do
        if not step.when or step.when(window) then steps[#steps + 1] = step end
    end
    Show(1)
end

-- The newest version a step that can show here arrived in, no newer than the
-- one running (for a copy straight from the source, the newest there is).
local function Latest(now)
    local compare, latest = ns.CompareVersions, nil
    for _, list in ipairs({ STEPS, NEWS }) do
        for _, step in ipairs(list) do
            if (compare(step.version, now) or 1) < 1 and (not step.when or step.when(window))
                and (not latest or compare(step.version, latest) == 1) then
                latest = step.version
            end
        end
    end
    return latest
end

-- The steps an update added, the full tour's then What's new's: newer than
-- the version seen before it and no newer than the one running, so versions
-- skipped come together. With no version seen (What's new opened by hand, or
-- none noted), the latest update's: the steps of the newest version that
-- added any that can show here, so an update that adds none, or whose steps
-- wait for a full restart, still offers the last ones. Only steps that can
-- show.
function Tour:News(seen)
    local now, compare = ns.Version(), ns.CompareVersions
    local byHand = not compare(seen, now)
    local latest = byHand and Latest(now)
    local list = {}
    if byHand and not latest then return list end
    for _, group in ipairs({ STEPS, NEWS }) do
        for _, step in ipairs(group) do
            local new
            if latest then
                new = compare(step.version, latest) == 0
            else
                new = compare(step.version, seen) == 1 and (compare(step.version, now) or 1) < 1
            end
            if new and (not step.when or step.when(window)) then list[#list + 1] = step end
        end
    end
    return list
end

-- What's new's tour: just those steps, over the window.
function Tour:StartNews(seen)
    local list = self:News(seen)
    if #list == 0 or not Ready() then return end
    steps, news, here = list, true, nil
    Show(1)
end

-- The steps about a page, for its walkthrough: the full tour's, then What's
-- new's, then the page help's, each where it can show and its part is
-- there to point at. Steps about no page (the menu, profiles) aren't any
-- page's. On a bar page, those for any bar's page, but not one only for
-- another kind of bar (bars), so the Buffs bar never points at a tick only
-- Cooldowns and Utility have. Asked once the window is made.
function Tour:Page(key)
    local list, bar = {}, ns.BAR_NAMES[key] ~= nil
    for _, group in ipairs({ STEPS, NEWS, HELP }) do
        for _, step in ipairs(group) do
            if step.page and Same(step.page, key) and not (bar and step.bars and not step.bars[key])
                and (not step.when or step.when(window)) then
                local part = window and Value(step.target, window)
                if part and part:IsShown() then list[#list + 1] = step end
            end
        end
    end
    return list
end

-- The ? in the title bar: a walkthrough of the page showing, over the
-- window, never leaving it. False, with nothing started, for a page with no
-- steps.
function Tour:StartPage(key)
    if not Ready() then return false end
    local list = self:Page(key)
    if #list == 0 then return false end
    steps, news, here = list, nil, key
    Show(1)
    return true
end

-- A first install: the window, and an offer of the tour.
function Tour:Welcome()
    if not Ready() then return end
    steps, index, started, welcome, news, here = nil, nil, nil, true, nil, nil
    box.title:SetText("WELCOME")
    box.count:Hide()
    box.text:SetText("New to " .. ns.TITLE .. "? A quick tour shows you the basics, a page at a time. It takes about a minute.")
    box.back:Hide()
    box.next:SetWidth(100)
    box.next:SetLabel("Take the tour")
    box.skip:SetLabel("Skip")
    Fit()
    Point({})
    box:Show()
    box:Raise()
end

function Tour:Next()
    if not (steps and index) then return end
    if index < #steps then return Show(index + 1) end
    local done = here and "That's this page. " .. PAGE_NOTE or news and "That's what's new. " .. NEWS_NOTE
        or "That's the tour. " .. TOUR_NOTE
    self:Stop()
    window:Say(done)
    window:Refresh()
end

function Tour:Back()
    if steps and index and index > 1 then Show(index - 1) end
end

function Tour:Stop()
    steps, index, started, welcome, news, here = nil, nil, nil, nil, nil, nil
    if box then
        box:Hide()
        outline:Hide()
    end
end

function Tour:Active()
    return box ~= nil and box:IsShown()
end

-- Called whenever the window changes page: the outline only shows on the page
-- the step is about. Next and Back always go back to it.
function Tour:Sync()
    local step = steps and index and steps[index]
    if not step or not box then return end
    -- A page's walkthrough: only its own page, not another bar's.
    local shown
    if here then shown = window.selected == here else shown = not step.page or Same(step.page, window.selected) end
    outline:SetShown(shown and Value(step.target, window) ~= nil)
    box.arrow:SetShown(shown)
end

-- Points the step showing at its part again, for a part that moved or
-- changed (the Profiles step, once the profile menu opens or closes).
function Tour:Repoint()
    local step = steps and index and steps[index]
    if not (step and box and box:IsShown()) then return end
    Point(step)
    self:Sync()
end
