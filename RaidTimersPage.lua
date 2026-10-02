-- The Raid Timers page in the /fecm window, under More: Blizzard's pull and
-- start countdown, raid warnings and boss emotes, and the boss frames' cast
-- bars, each restyled once ticked. A live preview shows all three in your
-- choices, made from the addon's own frames (RaidTimers.lua), then each
-- part's switch and choices, and how to see them in the game.
local _, ns = ...
local T = ns.Theme

local SWATCH, SWATCH_GAP = 20, 6
local DIM = .35 -- a preview whose part is off
local COLUMN = 312 -- the raid warnings' column
local LABEL = 64 -- room for a row's label before its choices
local PULL_SECONDS = 12 -- the preview's countdown bar runs this long, then starts again
local CAST_SECONDS = 2.5 -- and its boss cast
local UNTESTED = " (Needs testing)"

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
    local pull = R:SamplePull(tray)
    pull:SetPoint("TOPLEFT", 12, -20)
    local warnings = R:SampleWarnings(tray)
    warnings:SetPoint("TOPLEFT", 226, -30)
    local boss = R:SampleBoss(tray)
    boss:SetPoint("TOPLEFT", 448, -36)
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
    options:SetPoint("TOPLEFT", tray, "BOTTOMLEFT", 0, -12)
    options:SetSize(inner, 176)
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
    local function Pills(keys, names, setting, width, x, y, note)
        local items = {}
        for _, key in ipairs(keys) do items[#items + 1] = { key = key, label = names[key] } end
        local pills = T:Segmented(options, items, width, function(key)
            ns.Set(setting, key)
            Changed()
        end)
        pills:SetPoint("TOPLEFT", x, y)
        for _, button in ipairs(pills.buttons) do window:Hint(button, note) end
        return pills
    end
    local function BarColour(key) return ns.Style:BarColour(key) end
    local function TextColour(key) return R:TextColour(key) end

    -- The pull and start countdown.
    local pullTick = Tick("Pull and start countdown" .. UNTESTED, "pullTimer", 0, -4,
        "Blizzard's countdown bar for a pull or a battleground's gates, in the Look page's design, texture and font, and its big numbers.")
    local pullColours = Colours("Colour", "pullColour", ns.BAR_COLOUR_KEYS, BarColour, 0, -28,
        "A colour for the countdown bar. Click it again for Blizzard's red.")
    Label("Numbers", 0, -56)
    local numbers = Pills(ns.NUMBER_KEYS, ns.NUMBER_NAMES, "pullNumbers", 200, LABEL, -56,
        "The big numbers for the last seconds: Blizzard's gold, white, or in the bar's colour.")

    -- The boss frames' cast bars.
    local bossTick = Tick("Boss cast bars" .. UNTESTED, "bossCasts", 0, -92,
        "The cast bars on Blizzard's boss frames, in the Look page's design, texture and font.")
    local bossColours = Colours("Colour", "bossColour", ns.BAR_COLOUR_KEYS, BarColour, 0, -116,
        "A colour for boss casts. Click it again for gold, green while channelling. Broken off is red, and casts you can't interrupt grey, when the game shows which.")
    local bossNote = T:Text(options, "GameFontHighlightSmall", T.MUTED)
    bossNote:SetPoint("TOPLEFT", 0, -144)
    bossNote:SetWidth(COLUMN - 16)
    page.bossNote = bossNote

    -- Raid warnings and boss emotes.
    local warningTick = Tick("Raid warnings and boss emotes" .. UNTESTED, "raidWarnings", COLUMN, -4,
        "The big text at the top of your screen: raid warnings and what bosses say and whisper. Blizzard still sizes, places and fades it.")
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
    page.pullTick, page.bossTick, page.warningTick, page.shadow = pullTick, bossTick, warningTick, shadow
    page.numbers, page.font, page.outline = numbers, font, outline
    page.pullColours, page.bossColours = pullColours, bossColours
    page.warningColours, page.emoteColours = warningColours, emoteColours

    -- How to see each one in the game.
    local help = T:Heading(page, "In the game")
    help:SetPoint("TOPLEFT", options, "BOTTOMLEFT", 0, -10)
    local lines = {
        "Pull timer: type /countdown 40 for the bar until 0:30, then the numbers. It's made for groups, so try it alone too. Battleground gates use it as well.",
        "Raid warnings: in a group, the leader or an assistant types /rw and a message. Boss emotes and casts need a boss.",
        "Boss cast bars: tick Boss Frames in Edit Mode to see them, empty.",
        "Blizzard's boss timeline and boss warnings aren't in WoW Forever yet. If Blizzard adds them, they'll get a switch here.",
    }
    local last = help
    page.help = {}
    for i, text in ipairs(lines) do
        local line = T:Text(page, "GameFontHighlightSmall", T.MUTED)
        line:SetPoint("TOPLEFT", last, "BOTTOMLEFT", 0, i == 1 and -6 or -4)
        line:SetWidth(inner)
        line:SetText(text)
        page.help[i] = line
        last = line
    end

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
