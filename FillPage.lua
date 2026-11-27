-- The Resource fill page in the /ccm window, under More: one tick to turn it
-- on, another for your action bars, a live preview of the look you pick at
-- four levels (the last one filling up over and over), the look itself and
-- how much it moves, how strong the fill and the darkening are, the small
-- ticks that change what shows, and one colour for each power with a way
-- back to the game's own. Fill.lua does the work, FillBars.lua the action
-- bars.
local _, ns = ...
local T = ns.Theme

-- Room for a label before its control (a slider's track, or a choice's
-- buttons). As on the Cooldown pulse's page, a label runs about seven units
-- a letter: the longest here, Movement, needs about 60, and the slider's
-- thumb sits 5 over the track's start.
local LABEL = 96
local COLUMN = 312 -- the right-hand column
local PILLS = 160 -- the left column's choices: as wide as its sliders' tracks
-- The five looks need more room than three, and still stop short of the
-- ticks in the right-hand column; each name takes the share its length asks
-- for (the choices' own fit).
local LOOK_PILLS = 200
local SWATCH = 20 -- a colour row's swatch
local SAMPLE = 44 -- the preview's icons
local SAMPLE_GAP = 72 -- and how far apart they sit
local SAMPLES = { .2, .45, .7 } -- the levels the first three show
local RISE = 3.2 -- the last one fills up in this many seconds, over and over
local COLOUR_NAME = 96 -- room for the name of the colour in use, beside its swatch

-- What each look does, in the preview's own words.
local SAYS = {
    liquid = "A wave rolling across the surface, the spell showing through the fill, and bubbles rising.",
    flat = "One clean block of colour. Nothing moves.",
    frost = "Ice standing still at the surface, with a few sparkles in it.",
    ember = "A burning line along the surface, flickering, with sparks lifting off it.",
    arcane = "A slow glow, with motes drifting about inside it.",
}

-- A choice's buttons, from its keys and their names; fit gives each name the
-- share its length asks for, for a row whose names differ in length.
local function Choices(keys, names, fit)
    local items = { fit = fit or nil }
    for _, key in ipairs(keys) do items[#items + 1] = { key = key, label = names[key] } end
    return items
end

-- The preview: four icons in the look you picked, the first three at set
-- levels and the last filling up over and over, so a change shows at once.
local function BuildTray(window, page, inner)
    local F = ns.Fill
    local tray = CreateFrame("Frame", nil, page, "BackdropTemplate")
    tray:SetPoint("TOPLEFT", 16, -38)
    tray:SetSize(inner, 104)
    T:Flat(tray, T.PANEL, T.BORDER)
    page.tray = tray
    local caption = T:Text(tray, "GameFontHighlightSmall", T.MUTED)
    caption:SetPoint("TOPLEFT", 12, -8)
    caption:SetText("ON YOUR ICONS")
    local says = T:Text(tray, "GameFontHighlightSmall", T.MUTED)
    says:SetPoint("TOPLEFT", 332, -8)
    says:SetWidth(inner - 344)
    says:SetWordWrap(true)
    page.says = says
    page.samples = {}
    for i = 1, #SAMPLES + 1 do
        local sample = F:Sample(tray, SAMPLE)
        sample:SetPoint("TOPLEFT", 12 + (i - 1) * SAMPLE_GAP, -28)
        -- The icon under the fill: the spell's art, as on your bars.
        local art = sample:CreateTexture(nil, "BACKGROUND")
        art:SetAllPoints()
        art:SetTexture(136170)
        ns.Style:Zoom(art)
        local under = T:Text(tray, "GameFontHighlightSmall", T.MUTED)
        under:SetPoint("TOP", sample, "BOTTOM", 0, -4)
        under:SetWidth(SAMPLE_GAP)
        under:SetJustifyH("CENTER")
        under:SetText(i <= #SAMPLES and (math.floor(SAMPLES[i] * 100 + .5) .. "%") or "filling")
        page.samples[i] = sample
    end
    -- All four drawn from one clock, as the look you picked makes them.
    local clock = 0
    tray:SetScript("OnUpdate", function(_, elapsed)
        clock = clock + (elapsed or 0)
        for i, sample in ipairs(page.samples) do
            F:Draw(sample.fill, SAMPLES[i] or (clock % RISE) / RISE, clock)
        end
    end)
end

-- The choices: on or off, then the look and the fill on the left, and the
-- ticks that change what shows on the right.
local function BuildOptions(window, page, inner)
    local F = ns.Fill
    local function Changed()
        F:Apply()
        window:Refresh()
    end
    local options = CreateFrame("Frame", nil, page)
    options:SetPoint("TOPLEFT", page.tray, "BOTTOMLEFT", 0, -22)
    options:SetSize(inner, 140)
    page.options = options
    local master = T:Check(options, "Fill an icon I can't pay for", function(self)
        ns.Set("fill", self:GetChecked())
        Changed()
    end)
    master:SetPoint("TOPLEFT", 0, 0)
    window:Hint(master, "A spell you can't pay for goes dark and fills up from the bottom with the mana, rage or energy it"
        .. " needs, as that power comes back. It flashes once when you can pay for it. Your own bars' icons, in a fight too.")
    page.master = master
    -- The same fill on your action bars, in its own tick beside it.
    local bars = T:Check(options, "Fill my action bars too", function(self)
        ns.Set("fillBars", self:GetChecked())
        Changed()
    end)
    bars:SetPoint("TOPLEFT", COLUMN, 0)
    window:Hint(bars, "The same fill on your action bars' buttons, so a spell you can't pay for there goes dark and fills up"
        .. " too. Blizzard's bars and the common bar addons. The keybind, the count and the cooldown stay on top of it.")
    page.bars = bars

    -- A label, then its buttons LABEL along.
    local function Pills(label, keys, names, width, setting, x, y, note, fit)
        local text = T:Text(options, "GameFontHighlight")
        text:SetPoint("TOPLEFT", x, y - 4)
        text:SetText(label)
        local pills = T:Segmented(options, Choices(keys, names, fit), width, function(key)
            ns.Set(setting, key)
            Changed()
        end)
        pills:SetPoint("TOPLEFT", x + LABEL, y)
        pills.label = text
        for _, button in ipairs(pills.buttons) do window:Hint(button, note) end
        return pills
    end
    local function Slider(label, key, limits, step, x, y, note)
        local slider = T:Slider(options, label, limits, step, x == 0 and COLUMN - 16 or inner - COLUMN, function(value)
            ns.Set(key, value)
            Changed()
        end, LABEL)
        slider:SetPoint("TOPLEFT", x, y)
        slider.key = key
        local set = slider.Set
        function slider:Set(value)
            set(self, value)
            self.value:SetText(value .. "%")
        end
        slider.value:SetWidth(36)
        window:Hint(slider, note)
        return slider
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

    page.look = Pills("Look", ns.FILL_STYLE_KEYS, ns.FILL_STYLE_NAMES, LOOK_PILLS, "fillStyle", 0, -26,
        "How the fill is drawn: Liquid, Flat, Frost, Ember or Arcane. The preview above plays the one you pick.", true)
    page.move = Pills("Movement", ns.FILL_MOVE_KEYS, ns.FILL_MOVE_NAMES, PILLS, "fillMove", 0, -52,
        "How fast it moves and how far the surface rolls. Flat sits still whichever you pick.")
    page.strength = Slider("Strength", "fillStrength", ns.FILL_STRENGTH, 5, 0, -78,
        "How strong the fill's colour is over the spell's own picture. The picture shows through it at any setting.")
    page.darkness = Slider("Darkness", "fillDarkness", ns.FILL_DARKNESS, 5, 0, -104, function()
        if ns.Get("fillDim") ~= true then return "Tick Darken the spell first, then how dark it goes is set here." end
        return "How dark the part you can't pay for yet goes, above the fill. 0 leaves the picture as it is."
    end)

    page.bubbles = Tick("Bubbles", "fillBubbles", COLUMN, -26,
        "Small bubbles rising through the fill. Frost sparkles instead, Ember throws sparks and Arcane drifts motes.")
    page.flash = Tick("Flash when I can pay", "fillFlash", COLUMN, -48,
        "One quick flash on the icon the moment you can pay for the spell, as the fill goes.")
    page.line = Tick("Bright line on the surface", "fillLine", COLUMN, -70,
        "A bright glow along the surface of the fill, so the level stands out. Ember's flickers.")
    page.dim = Tick("Darken the spell", "fillDim", COLUMN, -92,
        "The part of the spell's picture above the fill darkens while you can't pay for it. Untick it to leave the"
        .. " picture alone and show the fill alone.")
    page.cost = Tick("Show what it costs", "fillCost", COLUMN, -114,
        "What the spell costs, in the corner of its icon, while you can't pay for it.")
end

-- One colour for each power, with the way back to the game's own.
local function BuildColours(window, page, inner)
    local F = ns.Fill
    local function Changed()
        F:Apply()
        window:Refresh()
    end
    local heading = T:Heading(page, "Colours")
    heading:SetPoint("TOPLEFT", page.options, "BOTTOMLEFT", 0, -6)
    -- The heading stands on its own: the rows name their own power and each
    -- one says "Game's own" beside it until a colour is picked, so a line of
    -- words after Colours only said again what the rows already show.
    page.heading = heading
    local colours = CreateFrame("Frame", nil, page)
    colours:SetPoint("TOPLEFT", heading, "BOTTOMLEFT", 0, -8)
    colours:SetSize(inner, 60)
    page.colours = colours
    page.rows = {}
    for i, power in ipairs(ns.FILL_POWERS) do
        local x, y = ((i - 1) % 2) * COLUMN, math.floor((i - 1) / 2) * -28
        local label = T:Text(colours, "GameFontHighlight")
        label:SetPoint("TOPLEFT", x, y - 4)
        label:SetText(power.name)
        local lower = power.name:lower()
        local choice = ns.ColourChoice(window, colours, SWATCH, ns.SettingChoice(power.setting, {
            keys = ns.FILL_COLOUR_KEYS,
            colourOf = function(key)
                if key == "default" then return F:Own(power) end
                return ns.Style:BarColour(key)
            end,
            shown = function() return F:Colour(power) end,
            pick = function(key)
                ns.Set(power.setting, ns.Get(power.setting) ~= key and key or "default")
                Changed()
            end,
            note = function(key)
                if key == "default" then return "The game's own colour for " .. lower .. "." end
                return (ns.BAR_COLOUR_NAMES[key] or key) .. " for " .. lower .. "."
            end,
            about = "The colour " .. lower .. " fills in. Click for the colours.",
        }, Changed))
        choice:SetPoint("TOPLEFT", x + LABEL, y)
        local chosen = T:Text(colours, "GameFontHighlightSmall", T.MUTED)
        chosen:SetPoint("TOPLEFT", x + LABEL + SWATCH + 20, y - 4)
        chosen:SetWidth(COLOUR_NAME)
        page.rows[i] = { power = power, choice = choice, chosen = chosen }
    end
    -- Under the four rows, at the right, clear of their names.
    local reset = T:Button(page, "Game's colours", 130, 22)
    reset:SetPoint("TOPRIGHT", page.colours, "BOTTOMRIGHT", -16, -6)
    reset:SetScript("OnClick", function()
        ns.SetMany(function()
            for _, power in ipairs(ns.FILL_POWERS) do ns.Set(power.setting, "default") end
        end)
        Changed()
        window:Say("Every power fills in the game's own colour again.")
    end)
    window:Hint(reset, "Puts all four colours back to the game's own.")
    page.reset = reset
end

function ns.BuildFillPage(window, page, width)
    local inner = width - 32
    local title = T:Heading(page, "Resource fill")
    title:SetPoint("TOPLEFT", 16, -16)
    local status = T:Text(page, "GameFontHighlightSmall", T.MUTED)
    status:SetPoint("LEFT", title, "RIGHT", 10, 0)
    page.title, page.status = title, status
    BuildTray(window, page, inner)
    BuildOptions(window, page, inner)
    BuildColours(window, page, inner)

    function page:Refresh()
        local on = ns.Get("fill")
        self.master:SetChecked(on)
        self.bars:SetChecked(ns.Get("fillBars"))
        self.look:SetSelected(ns.Get("fillStyle"))
        self.move:SetSelected(ns.Get("fillMove"))
        self.strength:Set(ns.Get("fillStrength"))
        self.darkness:Set(ns.Get("fillDarkness"))
        self.bubbles:SetChecked(ns.Get("fillBubbles"))
        self.flash:SetChecked(ns.Get("fillFlash"))
        self.line:SetChecked(ns.Get("fillLine"))
        self.dim:SetChecked(ns.Get("fillDim"))
        self.cost:SetChecked(ns.Get("fillCost"))
        -- Flat has no surface and nothing moving, so bubbles, how much it
        -- moves and the bright line along the surface have nothing to do on
        -- it; the rest work on every look.
        local look = ns.Get("fillStyle")
        self.bubbles:SetUsable(look ~= "flat")
        self.move:SetUsable(look ~= "flat")
        self.line:SetUsable(look ~= "flat")
        -- Darkness only means anything while the spell is darkened at all.
        -- With that tick off the darkening is nothing whatever the slider
        -- says, and a slider that moves and does nothing reads as a broken
        -- one: Squirt moved it between 20 and 80 and rightly called it dead
        -- (27 Nov 2026). Greyed, the tick above it is the answer.
        self.darkness:SetUsable(ns.Get("fillDim") == true)
        self.says:SetText(SAYS[look] or SAYS.liquid)
        for _, row in ipairs(self.rows) do
            local key = ns.Get(row.power.setting)
            row.chosen:SetText(key == ns.CUSTOM and ns.CUSTOM_NAME or key == "default" and "Game's own"
                or ns.BAR_COLOUR_NAMES[key] or key)
            row.choice:Paint()
        end
        local said = "Off. Tick the box below to start."
        if on then
            -- Where it draws: your own bars' icons, your action bars, or
            -- both. With your bars off (the General page's Use my bars) and
            -- your action bars unticked it has nothing to draw on at all.
            local own = not (ns.Bars and not ns.Bars:Enabled())
            local onBars = ns.Get("fillBars") == true
            local where = own and (onBars and "on your bars' icons and your action bars." or "on your bars' icons.")
                or "on your action bars."
            said = ns.FILL_STYLE_NAMES[look] .. ", " .. (ns.FILL_MOVE_NAMES[ns.Get("fillMove")] or ""):lower() .. ", " .. where
            if look == "flat" then said = "Flat, " .. where end
            if not own and not onBars then
                said = "On, but your bars are off: turn Use my bars on, on the General page."
            end
        end
        self.status:SetText(said)
        -- (The preview draws itself from its own clock, whether the fill is
        -- on or off, so a change shows the moment it's made.)
    end
end
