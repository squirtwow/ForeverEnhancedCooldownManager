-- The Cast bar page in the /ccm window: your own cast bar under the Personal
-- Resource Display, and a swing timer that can share its spot, shown in a
-- live preview in the Look page's design, and their choices: each on or off,
-- their colours, the height, and whether the icon, name and time left show.
local _, ns = ...
local T = ns.Theme

local SWATCH, SWATCH_GAP = 20, 6
local SAMPLE = { name = "Hearthstone", icon = "Interface\\Icons\\INV_Misc_Rune_01", total = 3 }
-- The batch preview: a few crafts of a long batch, counting down.
local BATCH_SAMPLE = { name = "Roasted Boar Meat", icon = "Interface\\Icons\\INV_Misc_Food_14", total = 3, count = 133, from = 4 }
local SWING_SAMPLE = 2.8 -- seconds between the preview's swings
-- The tick marks preview: a channel of five ticks, draining, with a mark
-- where each of the first four lands (the last is at its end).
local TICK_SAMPLE = { name = "Drain Life", icon = "Interface\\Icons\\Spell_Shadow_LifeDrain02", total = 5 }
local TICK_AT = { .8, .6, .4, .2 }
local SAMPLE_LAG = .18 -- seconds: the preview's latency
local DIM = .35 -- a preview bar whose tick is off

function ns.BuildCastBarPage(window, page, width)
    local C = ns.CastBar
    local inner = width - 32
    local function Changed()
        C:Apply()
        window:Refresh()
    end

    local title = T:Heading(page, "Cast bar")
    title:SetPoint("TOPLEFT", 16, -16)
    local status = T:Text(page, "GameFontHighlightSmall", T.MUTED)
    status:SetPoint("LEFT", title, "RIGHT", 10, 0)
    page.status = status

    -- The preview: a cast bar like yours, filling over and over, and a swing
    -- timer under it. Each grows away from the middle as the height changes.
    local tray = CreateFrame("Frame", nil, page, "BackdropTemplate")
    tray:SetPoint("TOPLEFT", 16, -38)
    tray:SetSize(inner, 120)
    T:Flat(tray, T.PANEL, T.BORDER)
    local sample = C:Make(tray)
    sample:SetPoint("BOTTOMLEFT", tray, "LEFT", 12, 17)
    sample:SetWidth(300)
    sample.icon:SetTexture(SAMPLE.icon)
    sample.bar.name:SetText(SAMPLE.name)
    sample.bar:SetMinMaxValues(0, SAMPLE.total)
    local elapsed = 0
    sample:SetScript("OnUpdate", function(_, delta)
        elapsed = (elapsed + delta) % SAMPLE.total
        sample.bar:SetValue(elapsed)
        C:Time(sample.bar.time, SAMPLE.total - elapsed, SAMPLE.total)
    end)
    -- Its latency zone, while that's on, as wide as the bar lets it be.
    local function SampleLag()
        C:Lag(sample, SAMPLE_LAG / SAMPLE.total, math.floor(SAMPLE_LAG * 1000 + .5), false)
    end
    sample.bar:SetScript("OnSizeChanged", SampleLag)
    page.sample = sample
    local swingSample = C:Make(tray)
    swingSample:SetPoint("TOPLEFT", tray, "LEFT", 12, 11)
    swingSample:SetWidth(300)
    swingSample.bar:SetMinMaxValues(0, SWING_SAMPLE)
    local swung = 0
    swingSample:SetScript("OnUpdate", function(_, delta)
        swung = (swung + delta) % SWING_SAMPLE
        swingSample.bar:SetValue(swung)
        C:Time(swingSample.bar.time, SWING_SAMPLE - swung, SWING_SAMPLE)
    end)
    page.swingSample = swingSample
    local batchSample = C:Make(tray)
    batchSample:SetPoint("TOPLEFT", swingSample, "BOTTOMLEFT", 0, -6)
    batchSample:SetWidth(300)
    batchSample.icon:SetTexture(BATCH_SAMPLE.icon)
    batchSample.bar:SetMinMaxValues(0, BATCH_SAMPLE.total)
    local crafted = 0
    batchSample:SetScript("OnUpdate", function(_, delta)
        crafted = (crafted + delta) % (BATCH_SAMPLE.total * 5)
        local index = BATCH_SAMPLE.from + math.floor(crafted / BATCH_SAMPLE.total)
        local into = crafted % BATCH_SAMPLE.total
        batchSample.bar:SetValue(into)
        batchSample.bar.name:SetFormattedText("%s %d / %d", BATCH_SAMPLE.name, index, BATCH_SAMPLE.count)
        local left = math.floor((BATCH_SAMPLE.total - into) + (BATCH_SAMPLE.count - index) * BATCH_SAMPLE.total + .5)
        batchSample.bar.time:SetFormattedText("%d:%02d left", math.floor(left / 60), left % 60)
    end)
    page.batchSample = batchSample
    local tickSample = C:Make(tray)
    tickSample:SetWidth(300)
    tickSample.icon:SetTexture(TICK_SAMPLE.icon)
    tickSample.bar.name:SetText(TICK_SAMPLE.name)
    tickSample.bar:SetMinMaxValues(0, TICK_SAMPLE.total)
    local drained = 0
    tickSample:SetScript("OnUpdate", function(_, delta)
        drained = (drained + delta) % TICK_SAMPLE.total
        tickSample.bar:SetValue(TICK_SAMPLE.total - drained)
        C:Time(tickSample.bar.time, TICK_SAMPLE.total - drained, TICK_SAMPLE.total)
    end)
    tickSample.bar:SetScript("OnSizeChanged", function(bar) C:Marks(bar, TICK_AT) end)
    page.tickSample = tickSample
    local previewNote = T:Text(tray, "GameFontHighlightSmall", T.MUTED)
    previewNote:SetPoint("RIGHT", -12, 0)
    previewNote:SetJustifyH("RIGHT")
    previewNote:SetText("Preview. Changes show straight away.")

    local options = CreateFrame("Frame", nil, page)
    options:SetPoint("TOPLEFT", tray, "BOTTOMLEFT", 0, -12)
    options:SetSize(inner, 280)
    page.options = options
    local function Tick(label, key, y, note)
        local check = T:Check(options, label, function(self)
            ns.Set(key, self:GetChecked())
            Changed()
        end)
        check:SetPoint("TOPLEFT", 0, y)
        window:Hint(check, note)
        return check
    end
    local shown = Tick("Show my cast bar under the resource display", "castBar", -4,
        "On, Blizzard's own cast bar is hidden. Off, another addon's cast bar works as before, and with the swing timer off too your rows close up.")
    local swings = Tick("Swing timer in this spot", "swingTimer", -26,
        "Main hand and ranged swings: Auto Shot for hunters, Ranged for other classes. A cast takes the spot while it lasts. "
        .. "Forever's own swing timers and EraUI's are separate: turn those off if you don't want two.")
    -- Both ticks as one part, for the tour to outline and put its box under.
    local ticks = CreateFrame("Frame", nil, options)
    ticks:SetPoint("TOPLEFT", shown, "TOPLEFT")
    ticks:SetPoint("BOTTOMLEFT", swings, "BOTTOMLEFT")
    ticks:SetWidth(math.max(shown:GetWidth(), swings:GetWidth()))
    page.ticks = ticks

    -- A row of colours for one of them: click the chosen one again for its own.
    local function Colours(caption, key, y, note)
        local label = T:Text(options, "GameFontHighlight")
        label:SetPoint("TOPLEFT", 0, y - 4)
        label:SetText(caption)
        local swatches = {}
        for i, colour in ipairs(ns.BAR_COLOUR_KEYS) do
            local swatch = ns.Swatch(options, SWATCH, function()
                ns.Set(key, ns.Get(key) ~= colour and colour or "default")
                Changed()
            end)
            swatch:SetPoint("TOPLEFT", 100 + (i - 1) * (SWATCH + SWATCH_GAP), y)
            swatch.key = colour
            if colour == "class" then ns.ClassIcon(swatch) end
            window:Hint(swatch, note)
            swatches[i] = swatch
        end
        local chosen = T:Text(options, "GameFontHighlightSmall", T.MUTED)
        chosen:SetPoint("TOPLEFT", 100 + #ns.BAR_COLOUR_KEYS * (SWATCH + SWATCH_GAP) + 2, y - 4)
        return swatches, chosen
    end
    local swatches, chosen = Colours("Cast colour", "castColour", -54,
        "A colour for your cast bar. Click it again for Blizzard's gold, green while channelling.")
    local swingSwatches, swingChosen = Colours("Swing colour", "swingColour", -82,
        "A colour for your swing timer. Click it again for silver.")
    page.swatches, page.chosen = swatches, chosen
    page.swingSwatches, page.swingChosen = swingSwatches, swingChosen
    -- Both rows of colours, their labels and swatches, as one part for the
    -- page's walkthrough (the ? in the title bar) to outline.
    local colours = CreateFrame("Frame", nil, options)
    colours:SetPoint("TOPLEFT", 0, -54)
    colours:SetSize(100 + #ns.BAR_COLOUR_KEYS * (SWATCH + SWATCH_GAP) - SWATCH_GAP, 48)
    page.colours = colours

    local height = T:Slider(options, "Height", ns.CAST_HEIGHT, 1, 280, function(value)
        ns.Set("castHeight", value)
        Changed()
    end)
    height:SetPoint("TOPLEFT", 0, -114)
    window:Hint(height, "How tall your cast bar and swing timer are.")
    page.height = height

    local icon = Tick("Icon", "castIcon", -146, "The spell's icon at the left end, or your weapon's for the swing timer.")
    local name = Tick("Name", "castName", -168, "The spell's name on the bar, or Main hand, Auto Shot or Ranged for the swing timer.")
    local timer = Tick("Time left", "castTime", -190, "Seconds left, at the right end.")
    -- The right-hand column: crafting beside the height, then the tick marks
    -- and, while they're on, their colour, style and width under them.
    local RIGHT = 300
    local batch = Tick("Crafting: time left for the batch", "castBatch", -114,
        "With Create All or a number of crafts, the bar shows which one you're on, like 4 / 133, and the time left for them all. (experimental)")
    batch:ClearAllPoints()
    batch:SetPoint("TOPLEFT", RIGHT, -114)
    local marks = Tick("Tick marks on channelled spells", "castTicks", -146,
        "Marks on the bar where each tick of a channelled spell lands, like Drain Life, Mind Flay or Arcane Missiles.")
    marks:ClearAllPoints()
    marks:SetPoint("TOPLEFT", RIGHT, -146)
    page.shown, page.swing, page.icon, page.name, page.timer, page.batch = shown, swings, icon, name, timer, batch
    page.marks = marks
    local tickParts = {}
    local tickColourLabel = T:Text(options, "GameFontHighlight")
    tickColourLabel:SetPoint("TOPLEFT", RIGHT, -172)
    tickColourLabel:SetText("Colour")
    tickParts[#tickParts + 1] = tickColourLabel
    local tickSwatches = {}
    for i, key in ipairs(ns.TICK_COLOUR_KEYS) do
        local swatch = ns.Swatch(options, SWATCH, function()
            ns.Set("castTickColour", key)
            Changed()
        end)
        swatch:SetPoint("TOPLEFT", RIGHT + 52 + (i - 1) * (SWATCH + SWATCH_GAP), -168)
        swatch.key = key
        if key == "class" then ns.ClassIcon(swatch) end
        window:Hint(swatch, (key == "white" and "White" or key == "black" and "Black" or ns.BAR_COLOUR_NAMES[key])
            .. " tick marks.")
        tickSwatches[i] = swatch
        tickParts[#tickParts + 1] = swatch
    end
    local styleLabel = T:Text(options, "GameFontHighlight")
    styleLabel:SetPoint("TOPLEFT", RIGHT, -194)
    styleLabel:SetText("Style")
    tickParts[#tickParts + 1] = styleLabel
    local styles = {}
    for _, key in ipairs(ns.TICK_STYLE_KEYS) do styles[#styles + 1] = { key = key, label = ns.TICK_STYLE_NAMES[key] } end
    local tickStyle = T:Segmented(options, styles, 120, function(key)
        ns.Set("castTickStyle", key)
        Changed()
    end)
    tickStyle:SetPoint("TOPLEFT", RIGHT + 52, -190)
    for _, button in ipairs(tickStyle.buttons) do
        window:Hint(button, "Notches: short marks at the bar's top and bottom edges. Lines: right across the bar.")
    end
    tickParts[#tickParts + 1] = tickStyle
    local tickWidth = T:Slider(options, "Width", ns.CAST_TICK_WIDTH, 1, inner - RIGHT - 184, function(value)
        ns.Set("castTickWidth", value)
        Changed()
    end, 44)
    tickWidth:SetPoint("TOPLEFT", RIGHT + 184, -190)
    window:Hint(tickWidth, "How wide each tick mark is, in screen pixels.")
    tickParts[#tickParts + 1] = tickWidth
    page.tickSwatches, page.tickStyle, page.tickWidth = tickSwatches, tickStyle, tickWidth
    -- Latency, under the tick marks (and their choices while they show):
    -- the tick and Show ms beside it, then, while it's on, its colour.
    local latency = Tick("Latency on the bar", "castLatency", -178,
        "Your latency as a zone at the end of each cast, the start of a channel: once the bar reaches it, the cast is"
        .. " done on the server, so you can start the next.")
    local latencyMs = Tick("Show ms", "castLatencyText", -178, "How long the zone is, in ms, at the right end of the bar.")
    local latencyLabel = T:Text(options, "GameFontHighlight")
    latencyLabel:SetText("Colour")
    local latencySwatches = {}
    for i, key in ipairs(ns.LATENCY_COLOUR_KEYS) do
        local swatch = ns.Swatch(options, SWATCH, function()
            ns.Set("castLatencyColour", key)
            Changed()
        end)
        swatch.key = key
        if key == "class" then ns.ClassIcon(swatch) end
        window:Hint(swatch, key == "paler" and "A paler shade of your cast bar's own colour for the latency zone."
            or ((key == "red" and "Red" or key == "white" and "White" or key == "black" and "Black"
            or ns.BAR_COLOUR_NAMES[key]) .. " latency zone, in your bar's texture."))
        latencySwatches[i] = swatch
    end
    page.latency, page.latencyMs, page.latencySwatches = latency, latencyMs, latencySwatches
    -- Where they go: under the tick marks, or under their choices.
    local function PlaceLatency(ticking)
        local y = ticking and -222 or -178
        latency:ClearAllPoints()
        latency:SetPoint("TOPLEFT", RIGHT, y)
        latencyMs:ClearAllPoints()
        latencyMs:SetPoint("TOPLEFT", RIGHT + 170, y)
        latencyLabel:ClearAllPoints()
        latencyLabel:SetPoint("TOPLEFT", RIGHT, y - 26)
        for i, swatch in ipairs(latencySwatches) do
            swatch:ClearAllPoints()
            swatch:SetPoint("TOPLEFT", RIGHT + 52 + (i - 1) * (SWATCH + SWATCH_GAP), y - 22)
        end
    end
    -- The time: seconds left, or left / the whole cast, beside Time left.
    local timeFormat = T:Segmented(options, { { key = "left", label = "1.5" }, { key = "total", label = "1.5 / 3.0" } }, 180,
        function(key)
            ns.Set("castTimeFormat", key)
            Changed()
        end)
    timeFormat:SetPoint("TOPLEFT", 100, -190)
    for _, button in ipairs(timeFormat.buttons) do
        window:Hint(button, "The time on the bar: seconds left, or seconds left / the whole cast.")
    end
    page.timeFormat = timeFormat
    -- The height and the three ticks under it as one part, for the walkthrough.
    local parts = CreateFrame("Frame", nil, options)
    parts:SetPoint("TOPLEFT", 0, -114)
    parts:SetSize(280, 190 + 20 - 114)
    page.parts = parts

    -- Under the left-hand column, clear of the right's.
    local about = T:Text(options, "GameFontHighlightSmall", T.MUTED)
    about:SetPoint("TOPLEFT", 0, -222)
    about:SetWidth(280)
    about:SetText("It sits right under your resource display, and in a layout the rows go under it. "
        .. "It keeps its room between casts, since the Buffs and Debuffs bars can't move in a fight.")
    page.about = about

    local function Paint(list, label, key, default)
        local colour = ns.Get(key)
        for _, swatch in ipairs(list) do
            ns.PaintSwatch(swatch, ns.Style:BarColour(swatch.key), swatch.key == colour)
        end
        label:SetText(colour == "default" and default or ns.BAR_COLOUR_NAMES[colour])
    end

    function page:Refresh()
        local casts, swinging = ns.Get("castBar"), ns.Get("swingTimer")
        if casts and swinging then
            status:SetText("Cast bar and swing timer under your resource display. Blizzard's cast bar is hidden.")
        elseif casts then
            status:SetText("Under your Personal Resource Display. Blizzard's cast bar is hidden.")
        elseif swinging then
            status:SetText("Swing timer under your resource display. Casts show on Blizzard's cast bar.")
        else
            status:SetText("Off. Your rows close up, and other cast bar addons work as before.")
        end
        shown:SetChecked(casts)
        swings:SetChecked(swinging)
        icon:SetChecked(ns.Get("castIcon"))
        name:SetChecked(ns.Get("castName"))
        timer:SetChecked(ns.Get("castTime"))
        batch:SetChecked(ns.Get("castBatch"))
        marks:SetChecked(ns.Get("castTicks"))
        height:Set(ns.Get("castHeight"))
        Paint(swatches, chosen, "castColour", "Blizzard's gold")
        Paint(swingSwatches, swingChosen, "swingColour", "Silver")
        C:Look(sample, false)
        C:Look(batchSample, false)
        C:SwingLook(swingSample)
        -- Auto Shot for hunters, the main hand for everyone else.
        local ranged = C:Hunter()
        swingSample.icon:SetTexture(C:SwingIcon(ranged))
        swingSample.bar.name:SetText(C:SwingName(ranged))
        -- Each preview bar dims while its tick is off.
        sample:SetAlpha(casts and 1 or DIM)
        swingSample:SetAlpha(swinging and 1 or DIM)
        -- The tick marks' choices and preview only while they're on.
        local ticking = ns.Get("castTicks") and true or false
        for _, piece in ipairs(tickParts) do piece:SetShown(ticking) end
        local tickColour = ns.Get("castTickColour")
        for _, swatch in ipairs(tickSwatches) do
            ns.PaintSwatch(swatch, C:MarkColour(swatch.key), swatch.key == tickColour)
        end
        tickStyle:SetSelected(ns.Get("castTickStyle"))
        tickWidth:Set(ns.Get("castTickWidth"))
        -- Latency: Show ms and the colours only while it's on.
        local lagging = ns.Get("castLatency") and true or false
        latency:SetChecked(lagging)
        latencyMs:SetChecked(ns.Get("castLatencyText"))
        latencyMs:SetShown(lagging)
        latencyLabel:SetShown(lagging)
        local lagColour = ns.Get("castLatencyColour")
        for _, swatch in ipairs(latencySwatches) do
            swatch:SetShown(lagging)
            ns.PaintSwatch(swatch, C:LagColour(swatch.key), swatch.key == lagColour)
        end
        PlaceLatency(ticking)
        timeFormat:SetSelected(ns.Get("castTimeFormat"))
        SampleLag()
        C:Look(tickSample, true)
        tickSample:SetAlpha(casts and 1 or DIM)
        C:Marks(tickSample.bar, TICK_AT)
        -- The batch and tick previews only while their ticks are on, under
        -- the swing timer: the tray grows for them, and the rows stay in its
        -- middle (for two, at any height).
        local batching = ns.Get("castBatch") and true or false
        batchSample:SetShown(batching)
        tickSample:SetShown(ticking)
        local extras = (batching and 1 or 0) + (ticking and 1 or 0)
        tray:SetHeight(extras == 2 and 156 or extras == 1 and 120 or 92)
        local shift = extras == 2 and ns.Get("castHeight") + 6 or extras == 1 and 14 or 0
        sample:ClearAllPoints()
        sample:SetPoint("BOTTOMLEFT", tray, "LEFT", 12, 3 + shift)
        swingSample:ClearAllPoints()
        swingSample:SetPoint("TOPLEFT", tray, "LEFT", 12, -3 + shift)
        tickSample:ClearAllPoints()
        tickSample:SetPoint("TOPLEFT", batching and batchSample or swingSample, "BOTTOMLEFT", 0, -6)
    end
end
