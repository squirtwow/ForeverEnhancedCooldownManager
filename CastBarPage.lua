-- The Cast bar page in the /ccm window: your own cast bar under the Personal
-- Resource Display, and a swing timer that can share its spot, shown in a
-- live preview in the Look page's design, and their choices: each on or off,
-- their colours, the height, and whether the icon, name and time left show.
local _, ns = ...
local T = ns.Theme

local SWATCH, SWATCH_GAP = 20, 6
local SAMPLE = { name = "Hearthstone", icon = "Interface\\Icons\\INV_Misc_Rune_01", total = 3 }
local SWING_SAMPLE = 2.8 -- seconds between the preview's swings
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
    tray:SetSize(inner, 92)
    T:Flat(tray, T.PANEL, T.BORDER)
    local sample = C:Make(tray)
    sample:SetPoint("BOTTOMLEFT", tray, "LEFT", 12, 3)
    sample:SetWidth(300)
    sample.icon:SetTexture(SAMPLE.icon)
    sample.bar.name:SetText(SAMPLE.name)
    sample.bar:SetMinMaxValues(0, SAMPLE.total)
    local elapsed = 0
    sample:SetScript("OnUpdate", function(_, delta)
        elapsed = (elapsed + delta) % SAMPLE.total
        sample.bar:SetValue(elapsed)
        sample.bar.time:SetFormattedText("%.1f", SAMPLE.total - elapsed)
    end)
    page.sample = sample
    local swingSample = C:Make(tray)
    swingSample:SetPoint("TOPLEFT", tray, "LEFT", 12, -3)
    swingSample:SetWidth(300)
    swingSample.bar:SetMinMaxValues(0, SWING_SAMPLE)
    local swung = 0
    swingSample:SetScript("OnUpdate", function(_, delta)
        swung = (swung + delta) % SWING_SAMPLE
        swingSample.bar:SetValue(swung)
        swingSample.bar.time:SetFormattedText("%.1f", SWING_SAMPLE - swung)
    end)
    page.swingSample = swingSample
    local previewNote = T:Text(tray, "GameFontHighlightSmall", T.MUTED)
    previewNote:SetPoint("RIGHT", -12, 0)
    previewNote:SetJustifyH("RIGHT")
    previewNote:SetText("Preview. Changes show straight away.")

    local options = CreateFrame("Frame", nil, page)
    options:SetPoint("TOPLEFT", tray, "BOTTOMLEFT", 0, -12)
    options:SetSize(inner, 250)
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
    page.shown, page.swing, page.icon, page.name, page.timer = shown, swings, icon, name, timer
    -- The height and the three ticks under it as one part, for the walkthrough.
    local parts = CreateFrame("Frame", nil, options)
    parts:SetPoint("TOPLEFT", 0, -114)
    parts:SetSize(280, 190 + 16 - 114)
    page.parts = parts

    local about = T:Text(options, "GameFontHighlightSmall", T.MUTED)
    about:SetPoint("TOPLEFT", 0, -222)
    about:SetWidth(inner)
    about:SetText("It sits right under your Personal Resource Display, and in a layout the rows go under it. "
        .. "It keeps its room between casts and swings, since the Buffs and Debuffs bars can't move in a fight.")
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
        height:Set(ns.Get("castHeight"))
        Paint(swatches, chosen, "castColour", "Blizzard's gold")
        Paint(swingSwatches, swingChosen, "swingColour", "Silver")
        C:Look(sample, false)
        C:SwingLook(swingSample)
        -- Auto Shot for hunters, the main hand for everyone else.
        local ranged = C:Hunter()
        swingSample.icon:SetTexture(C:SwingIcon(ranged))
        swingSample.bar.name:SetText(C:SwingName(ranged))
        -- Each preview bar dims while its tick is off.
        sample:SetAlpha(casts and 1 or DIM)
        swingSample:SetAlpha(swinging and 1 or DIM)
    end
end
