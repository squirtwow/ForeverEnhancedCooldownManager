-- The Raid Timers page in the /fecm window, under More: Blizzard's pull and
-- start countdown, raid warnings and boss emotes, and the boss frames' cast
-- bars, each restyled once ticked. A live preview shows all three in your
-- choices and sizes, made from the addon's own frames (RaidTimers.lua), then
-- each part's switch, choices and sizes, and a button for Edit Mode.
local _, ns = ...
local T = ns.Theme

local SWATCH, SWATCH_GAP = 20, 6
local DIM = .35 -- a preview whose part is off, or a control that doesn't apply
local COLUMN = 312 -- the raid warnings' column
local LABEL = 64 -- room for a row's label before its choices
local SIZE_LABEL = 84 -- and before a size slider's track
local SIZE_STEP = 5
local PULL_SECONDS = 12 -- the preview's countdown bar runs this long, then starts again
local CAST_SECONDS = 2.5 -- and its boss cast
local UNTESTED = " (Needs testing)"
local IN_A_FIGHT = "Edit Mode can't open in a fight. Try again once it's over."
local AGAIN = "Click Edit Mode again to open it, or type /editmode."

-- Edit Mode -----------------------------------------------------------------------------
-- Opened by the game's own /editmode, from your click on a secure button:
-- addon code never opens it. A secure button can't be touched in a fight,
-- and neither can a window holding one, so it's never in this window: it's
-- UIParent's, laid over the page's Edit Mode button only while the mouse is
-- on it out of a fight (and again as a fight ends with the mouse still
-- there), and taken away when the mouse leaves, the page closes, What's new
-- opens, or a fight starts (the game says so just before it locks secure
-- frames). In a fight the page's button greys and says why. Once Edit Mode
-- is open this window closes, as Edit Mode opens under it.
-- It sits a strata above the window, not in the window's own: the window
-- comes to the front of its strata whenever it's clicked (it's toplevel) or
-- raised, which would put the page's button back over anything else in
-- that strata, and the page's button would take the click.
local ABOVE = "TOOLTIP" -- the one strata above the window's FULLSCREEN_DIALOG
local secure -- the secure button, made the first time the mouse comes over the page's
local fighting = false -- from the start of a fight to its end

local function InFight()
    return fighting or (InCombatLockdown and InCombatLockdown()) == true
end

-- Taken away: hidden and anchored to nothing, so nothing holds the window.
local function Away()
    if not secure or InCombatLockdown() then return end
    secure:Hide()
    secure:ClearAllPoints()
end
-- What's new opens over the window, right over the page's button, often from
-- the keyboard (/fecm new) with the mouse resting on it, so the secure one
-- hears no OnLeave: taken away as it opens (Notes.lua), or being a strata
-- above, it would sit on What's new and take its clicks. If What's new
-- doesn't cover the button, the game's next OnEnter puts it back.
ns.EditModeAway = Away

local function EditModeButton(window, button)
    local function Lit(on)
        local c = on and T.HOVER or T.CONTROL
        button:SetBackdropColor(c[1], c[2], c[3], 1)
    end
    local function Secure()
        if secure then return secure end
        secure = CreateFrame("Button", "FECMEditModeButton", UIParent, "SecureActionButtonTemplate")
        secure:Hide()
        secure:EnableMouse(true) -- said outright, not left to the template
        -- The game runs the macro on the press or on the release, as its
        -- Action Button Use Key Down setting says: both are registered.
        secure:RegisterForClicks("AnyUp", "AnyDown")
        secure:SetAttribute("type", "macro")
        secure:SetAttribute("macrotext", "/editmode")
        -- Over the page's button: its hover look and note, as if it were the
        -- one under the mouse. A message the page's button just said (clicked
        -- itself) stays up: the mouse hasn't moved onto anything new.
        secure:SetScript("OnEnter", function()
            Lit(true)
            local saying = window.saying
            window:Note(button)
            if saying then
                window.saying = saying
                window:ShowNote()
            end
        end)
        secure:SetScript("OnLeave", function()
            Lit(false)
            window:Unnote(button)
            Away()
        end)
        -- After the game's own click: once Edit Mode shows (the game opens it
        -- under this window), this window closes, so its Boss Frames tick
        -- can be reached. Only read whether it shows, never touched.
        secure:HookScript("PostClick", function()
            local editor = _G.EditModeManagerFrame
            if not InCombatLockdown() and editor and editor:IsShown() then window:Hide() end
        end)
        return secure
    end
    -- The secure one over the whole of the page's button, a strata above the
    -- window (see ABOVE); out of a fight only. The page's button's own
    -- OnLeave, sent as the secure one takes the mouse, leaves it there.
    local function Place()
        if InFight() then return end
        local over = Secure()
        over:SetFrameStrata(ABOVE)
        over:ClearAllPoints()
        over:SetAllPoints(button)
        over:Show()
    end
    -- The mouse on the page's button.
    button:HookScript("OnEnter", Place)
    -- The page switched or the window closed, even with the mouse still there.
    button:HookScript("OnHide", Away)
    -- Clicked itself: in a fight, or the press reached the page's button
    -- before the secure one was under the mouse. Out of a fight the secure
    -- one goes straight back over it, so the next click opens Edit Mode.
    button:SetScript("OnClick", function()
        if InFight() then
            window:Say(IN_A_FIGHT)
        else
            Place()
            window:Say(AGAIN)
        end
        window:Refresh()
    end)
    local watch = CreateFrame("Frame")
    watch:RegisterEvent("PLAYER_REGEN_DISABLED")
    watch:RegisterEvent("PLAYER_REGEN_ENABLED")
    watch:SetScript("OnEvent", function(_, event)
        fighting = event == "PLAYER_REGEN_DISABLED"
        if fighting then
            Away()
        elseif button:IsVisible() and button:IsMouseMotionFocus() then
            -- The fight over with the mouse still on the button: the game
            -- sends no new OnEnter for it, so the secure one goes back now.
            -- Only if the button is what the mouse is on: IsMouseOver is
            -- only where the mouse is, true under What's new or the "Are you
            -- sure?" shade too, and the secure one would go over those.
            Place()
        end
        -- Only while this page shows: its button greys or brightens, and an
        -- Edit Mode message in the footer is no longer true. A refresh
        -- clears the footer's message, so another page's stays.
        if button:IsVisible() then window:Refresh() end
    end)
    button.watch = watch
end

-- The page ------------------------------------------------------------------------------

function ns.BuildRaidTimersPage(window, page, width)
    local R = ns.RaidTimers
    local inner = width - 32
    local function Changed()
        R:Apply()
        window:Refresh()
    end

    local title = T:Heading(page, "Raid Timers")
    title:SetPoint("TOPLEFT", 16, -16)
    local status = T:Text(page, "GameFontHighlightSmall", T.MUTED)
    status:SetPoint("LEFT", title, "RIGHT", 10, 0)
    page.status = status

    -- The preview: a countdown, two raid warning lines and a boss cast bar.
    local tray = CreateFrame("Frame", nil, page, "BackdropTemplate")
    tray:SetPoint("TOPLEFT", 16, -38)
    tray:SetSize(inner, 112)
    T:Flat(tray, T.PANEL, T.BORDER)
    page.tray = tray
    local function Caption(text, x)
        local caption = T:Text(tray, "GameFontHighlightSmall", T.MUTED)
        caption:SetPoint("TOPLEFT", x, -8)
        caption:SetText(text)
        return caption
    end
    Caption("PULL TIMER", 12)
    Caption("RAID WARNINGS", 236)
    Caption("BOSS CAST BAR", 462)
    -- Each preview in a box of its own, so a big size is cut at its edge
    -- instead of running over the next one.
    local function Box(x, boxWidth)
        local box = CreateFrame("Frame", nil, tray)
        box:SetPoint("TOPLEFT", x, -20)
        box:SetSize(boxWidth, 88)
        box:SetClipsChildren(true)
        return box
    end
    page.boxes = { pull = Box(8, 216), warnings = Box(226, 218), boss = Box(446, inner - 452) }
    local pull = R:SamplePull(page.boxes.pull)
    pull:SetPoint("TOPLEFT", 4, 0)
    local warnings = R:SampleWarnings(page.boxes.warnings)
    warnings:SetPoint("TOPLEFT", 0, -10)
    local boss = R:SampleBoss(page.boxes.boss)
    boss:SetPoint("TOPLEFT", 2, -16)
    page.pull, page.warnings, page.boss = pull, warnings, boss
    -- The countdown's bar runs down from 0:42 to 0:31 over and over, its big
    -- number counts 5 to 1, and the boss cast fills again and again.
    local clock = 0
    tray:SetScript("OnUpdate", function(_, elapsed)
        clock = clock + elapsed
        local left = PULL_SECONDS - clock % PULL_SECONDS
        pull.bar:SetValue(left / PULL_SECONDS)
        pull.bar.timeText:SetFormattedText("0:%02d", 30 + math.ceil(left))
        R:SampleNumber(pull, 5 - math.floor(clock % 5))
        boss.bar:SetValue(clock % CAST_SECONDS / CAST_SECONDS)
    end)

    local options = CreateFrame("Frame", nil, page)
    options:SetPoint("TOPLEFT", tray, "BOTTOMLEFT", 0, -10)
    options:SetSize(inner, 228)
    page.options = options
    local function Label(text, x, y)
        local label = T:Text(options, "GameFontHighlight")
        label:SetPoint("TOPLEFT", x, y - 4)
        label:SetText(text)
        return label
    end
    local function Tick(label, key, x, y, note)
        local check = T:Check(options, label, function(self)
            ns.Set(key, self:GetChecked())
            Changed()
        end)
        check:SetPoint("TOPLEFT", x, y)
        window:Hint(check, note)
        return check
    end
    -- A row of colour swatches for one setting: click the chosen one again
    -- for its own (Blizzard's, or gold). colourOf gives each swatch's colour.
    local function Colours(caption, key, keys, colourOf, x, y, note)
        Label(caption, x, y)
        local swatches = {}
        for i, colour in ipairs(keys) do
            local swatch = ns.Swatch(options, SWATCH, function()
                ns.Set(key, ns.Get(key) ~= colour and colour or "default")
                Changed()
            end)
            swatch:SetPoint("TOPLEFT", x + LABEL + (i - 1) * (SWATCH + SWATCH_GAP), y)
            swatch.key = colour
            if colour == "class" then ns.ClassIcon(swatch) end
            window:Hint(swatch, note)
            swatches[i] = swatch
        end
        local chosen = T:Text(options, "GameFontHighlightSmall", T.MUTED)
        chosen:SetPoint("TOPLEFT", x + LABEL + #keys * (SWATCH + SWATCH_GAP) + 2, y - 4)
        return { swatches = swatches, chosen = chosen, key = key, colourOf = colourOf }
    end
    local function Pills(keys, names, setting, pillsWidth, x, y, note)
        local items = {}
        for _, key in ipairs(keys) do items[#items + 1] = { key = key, label = names[key] } end
        local pills = T:Segmented(options, items, pillsWidth, function(key)
            ns.Set(setting, key)
            Changed()
        end)
        pills:SetPoint("TOPLEFT", x, y)
        for _, button in ipairs(pills.buttons) do window:Hint(button, note) end
        return pills
    end
    -- A size, in percent of Blizzard's: greyed while its part is off (on says
    -- whether it is), and its note says why.
    local function Size(label, key, limits, x, y, on, note, off)
        local slider = T:Slider(options, label, limits, SIZE_STEP, x == 0 and COLUMN - 16 or inner - COLUMN, function(value)
            ns.Set(key, value)
            Changed()
        end, SIZE_LABEL)
        slider:SetPoint("TOPLEFT", x, y)
        slider.key, slider.on = key, on
        window:Hint(slider, function() return on() and note or off end)
        return slider
    end
    local function BarColour(key) return ns.Style:BarColour(key) end
    local function TextColour(key) return R:TextColour(key) end
    local function Pulling() return ns.Get("pullTimer") end
    local function Warning() return ns.Get("raidWarnings") end
    local function Either() return Pulling() or Warning() end

    -- The pull and start countdown.
    local pullTick = Tick("Pull and start countdown" .. UNTESTED, "pullTimer", 0, -4,
        "Blizzard's countdown bar for a pull or a battleground's gates, in the Look page's design, texture and font, and its big numbers.")
    local pullColours = Colours("Colour", "pullColour", ns.BAR_COLOUR_KEYS, BarColour, 0, -28,
        "A colour for the countdown bar. Click it again for Blizzard's red.")
    Label("Numbers", 0, -56)
    local numbers = Pills(ns.NUMBER_KEYS, ns.NUMBER_NAMES, "pullNumbers", 200, LABEL, -56,
        "The big numbers for the last seconds: Blizzard's gold, white, or in the bar's colour.")
    local PULL_OFF = "Tick Pull and start countdown first."
    local barSize = Size("Bar size", "pullBarSize", ns.RAID_SIZE, 0, -84, Pulling,
        "How big the countdown bar is: 100 is Blizzard's size. It grows from its top middle. Two countdowns at once"
            .. " overlap above about 180, All sizes included.", PULL_OFF)
    local numberSize = Size("Number size", "pullNumberSize", ns.RAID_SIZE, 0, -106, Pulling,
        "How big the countdown's big numbers are: 100 is Blizzard's size. They grow round their middle.", PULL_OFF)

    -- The boss frames' cast bars, and Edit Mode beside them to see them.
    local bossTick = Tick("Boss cast bars" .. UNTESTED, "bossCasts", 0, -134,
        "The cast bars on Blizzard's boss frames, in the Look page's design, texture and font.")
    local editMode = T:Button(options, "Edit Mode", 76, 18)
    editMode:SetPoint("LEFT", bossTick, "RIGHT", 10, 0)
    window:Hint(editMode, function()
        return InFight() and IN_A_FIGHT
            or "Opens Edit Mode, as /editmode does, and closes this window. Tick Boss Frames there to see the boss cast bars, empty."
    end)
    EditModeButton(window, editMode)
    local bossColours = Colours("Colour", "bossColour", ns.BAR_COLOUR_KEYS, BarColour, 0, -158,
        "A colour for boss casts. Click it again for gold, green while channelling. Broken off is red, and casts you can't interrupt grey, when the game shows which.")
    local bossNote = T:Text(options, "GameFontHighlightSmall", T.MUTED)
    bossNote:SetPoint("TOPLEFT", 0, -186)
    bossNote:SetWidth(COLUMN - 16)
    page.bossNote, page.editMode = bossNote, editMode

    -- Raid warnings and boss emotes.
    local warningTick = Tick("Raid warnings and boss emotes" .. UNTESTED, "raidWarnings", COLUMN, -4,
        "The big text at the top of your screen: raid warnings and what bosses say and whisper. Blizzard still places and fades it.")
    -- Each font by its first name, in its own face.
    Label("Font", COLUMN, -28)
    local fontNames = {}
    for _, key in ipairs(ns.FONT_KEYS) do fontNames[key] = ns.FONT_NAMES[key]:match("^%S+") end
    local font = Pills(ns.FONT_KEYS, fontNames, "warningFont", inner - COLUMN - LABEL, COLUMN + LABEL, -28,
        "The font for raid warnings and boss emotes.")
    for _, button in ipairs(font.buttons) do button.label:SetFontObject(ns.Style:SampleFont(button.key)) end
    Label("Outline", COLUMN, -56)
    local outline = Pills(ns.OUTLINE_KEYS, ns.OUTLINE_NAMES, "warningOutline", 150, COLUMN + LABEL, -56,
        "A dark outline round each letter, thin or thick, so the text reads over anything.")
    local shadow = Tick("Shadow", "warningShadow", COLUMN + LABEL + 162, -58,
        "A soft drop shadow under the text, as Blizzard's has.")
    local warningColours = Colours("Warnings", "warningColour", ns.TEXT_COLOUR_KEYS, TextColour, COLUMN, -84,
        "A colour for raid warnings. Click it again for Blizzard's.")
    local emoteColours = Colours("Emotes", "emoteColour", ns.TEXT_COLOUR_KEYS, TextColour, COLUMN, -112,
        "A colour for what bosses say and whisper to you. Click it again for Blizzard's.")
    local WARNING_OFF = "Tick Raid warnings and boss emotes first."
    local warningSize = Size("Warning size", "warningSize", ns.RAID_SIZE, COLUMN, -140, Warning,
        "How big raid warnings are: 100 is Blizzard's size. Each still grows a little as it arrives, as Blizzard's do."
            .. " When big, long ones wrap onto more lines than Blizzard's usual 5.",
        WARNING_OFF)
    local emoteSize = Size("Emote size", "emoteSize", ns.RAID_SIZE, COLUMN, -162, Warning,
        "How big what bosses say and whisper is: 100 is Blizzard's size. When big, long ones wrap onto more lines"
            .. " than Blizzard's usual 5.", WARNING_OFF)
    -- All of them together.
    local allSizes = Size("All sizes", "raidSize", ns.RAID_SIZE_ALL, COLUMN, -188, Either,
        "Bar, Number, Warning and Emote size together, each kept in proportion: 100 leaves them as set."
            .. " The boss cast bars keep Blizzard's size; the boss frames have their own Frame Size in Edit Mode.",
        "Tick the countdown or the raid warnings first. The boss cast bars keep Blizzard's size.")
    page.pullTick, page.bossTick, page.warningTick, page.shadow = pullTick, bossTick, warningTick, shadow
    page.numbers, page.font, page.outline = numbers, font, outline
    page.pullColours, page.bossColours = pullColours, bossColours
    page.warningColours, page.emoteColours = warningColours, emoteColours
    page.sizes = { barSize, numberSize, warningSize, emoteSize, allSizes }
    -- The preview and the row of ticks along its foot (4 down, 16 high) as
    -- one part, for the tour to outline and put its box under. No mouse.
    page.top = CreateFrame("Frame", nil, page)
    page.top:SetPoint("TOPLEFT", tray, "TOPLEFT")
    page.top:SetPoint("BOTTOMRIGHT", options, "TOPRIGHT", 0, -20)

    local function Paint(row, default)
        local chosen = ns.Get(row.key)
        for _, swatch in ipairs(row.swatches) do
            ns.PaintSwatch(swatch, row.colourOf(swatch.key), swatch.key == chosen)
        end
        local names = row.colourOf == TextColour and ns.TEXT_COLOUR_NAMES or ns.BAR_COLOUR_NAMES
        row.chosen:SetText(chosen == "default" and default or names[chosen])
    end

    function page:Refresh()
        local pulling, warning, casting = ns.Get("pullTimer"), ns.Get("raidWarnings"), ns.Get("bossCasts")
        local owner = R:BossOwner()
        local on = (pulling and 1 or 0) + (warning and 1 or 0) + ((casting and not owner) and 1 or 0)
        status:SetText(on == 0 and "Blizzard's countdown, raid warnings and boss casts, in your look. Tick one to start."
            or "Your look on " .. on .. " of 3. The previews show your choices.")
        pullTick:SetChecked(pulling)
        warningTick:SetChecked(warning)
        bossTick:SetChecked(casting)
        shadow:SetChecked(ns.Get("warningShadow"))
        numbers:SetSelected(ns.Get("pullNumbers"))
        font:SetSelected(ns.Get("warningFont"))
        outline:SetSelected(ns.Get("warningOutline"))
        Paint(pullColours, "Blizzard's red")
        Paint(bossColours, "Gold")
        Paint(warningColours, "Blizzard's")
        Paint(emoteColours, "Blizzard's")
        for _, slider in ipairs(page.sizes) do
            slider:Set(ns.Get(slider.key))
            slider:SetUsable(slider.on() and true or false)
        end
        -- Edit Mode can't open in a fight: the button greys meanwhile.
        local fight = InFight()
        editMode.usable = not fight
        editMode:SetAlpha(fight and DIM or 1)
        -- EraUI's Classic cast bars style the boss cast bars too. A current
        -- EraUI steps back while this is on, and the note says so; an older
        -- one keeps them while its Cast Bars are on, and this part waits.
        if owner then
            bossNote:SetText(owner .. "'s Cast Bars style these while they're on (/era, Casting). This waits until they're off, or for a newer EraUI.")
            bossNote:SetTextColor(T.WARN[1], T.WARN[2], T.WARN[3])
        elseif R:SharedBy("EraUI") then
            bossNote:SetText("While this is on, they take your look instead of EraUI's. In a fight the game keeps each cast secret, so the bar keeps one colour.")
            bossNote:SetTextColor(T.MUTED[1], T.MUTED[2], T.MUTED[3])
        else
            bossNote:SetText("In a boss fight the game keeps each cast secret, so the bar keeps one colour. Blizzard's shield still marks casts you can't interrupt.")
            bossNote:SetTextColor(T.MUTED[1], T.MUTED[2], T.MUTED[3])
        end
        -- The same code as Blizzard's frames get; each dims while its part is off.
        R:SampleLook(pull)
        R:SampleLook(warnings)
        R:SampleLook(boss)
        pull:SetAlpha(pulling and 1 or DIM)
        warnings:SetAlpha(warning and 1 or DIM)
        boss:SetAlpha((casting and not owner) and 1 or DIM)
    end
end
