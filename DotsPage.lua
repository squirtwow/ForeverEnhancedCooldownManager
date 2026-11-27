-- The DoTs page in the /ccm window, under More: one tick to turn it on, then
-- what it marks on your target's health bar, the list of the spells you have
-- running, how strong the band's colour is, how the list is laid out, and a
-- colour for the band and for the bright line at its edge. Dots.lua does the
-- work and DotsBand.lua draws the band.
--
-- Everything but the first tick is greyed while the part is off, and a
-- control only the band draws, or only the list, is greyed while that one is
-- unticked, so a tick a player can turn on and off while it does nothing at
-- all is never reachable.
local _, ns = ...
local T = ns.Theme

-- Room for a label before its control: Out of combat is the longest one here,
-- about 91 at seven units a letter, and a slider's thumb sits 5 over its
-- track's start. The same 108 the Totems page gives its own labels, so the
-- sliders on the two pages line up.
local LABEL = 108
local COLUMN = 312 -- the right-hand column (inner is 606)
local PILLS = 150 -- a choice's buttons, as wide as a slider's track
local WRAP_PILLS = 110 -- Below and Above, two short names
local SWATCH = 20 -- a colour row's swatch
local COLOUR_NAME = 96 -- room for the name of the colour in use, beside its swatch
-- Choose spells, in a panel over the window as the Icon details and spell
-- panels are (Window.lua IconPanel, BarPage.lua SpellPanel): there is no
-- room on the page for one tick per spell, and a panel has as much as the
-- list needs.
local PANEL_WIDE, PANEL_HIGH, PANEL_ROW = 420, 320, 22

-- A colour's name as this page writes it: a bar colour's own name, else the
-- key with its first letter up (White and Black, which are not bar colours).
local function Named(key)
    return ns.BAR_COLOUR_NAMES[key] or (key:gsub("^%l", string.upper))
end

-- A choice's buttons, from its keys and their names.
local function Choices(keys, names)
    local items = {}
    for _, key in ipairs(keys) do items[#items + 1] = { key = key, label = names[key] } end
    return items
end

-- Choose spells: one tick per damage over time spell of yours, so a spell you
-- never want in the list can be left out of it. In a panel over the window,
-- as the Icon details panel is, since the page has no room for a list of its
-- own. What is unticked is kept in this character's profile
-- (ns.DotsLeftOut), never in a shared string.
local function SpellsPanel(window)
    local D = ns.Dots
    local shade = CreateFrame("Frame", nil, window)
    shade:SetPoint("TOPLEFT")
    shade:SetPoint("BOTTOMRIGHT", 0, ns.WINDOW_FOOTER or 28)
    -- Over the profile menu (60), under the tour (70) and Are you sure? (80).
    shade:SetFrameLevel(window:GetFrameLevel() + 64)
    shade:EnableMouse(true) -- nothing behind it can be clicked meanwhile
    local dim = shade:CreateTexture(nil, "BACKGROUND")
    dim:SetAllPoints()
    dim:SetColorTexture(0, 0, 0, .45)
    shade:Hide()
    local dialog = CreateFrame("Frame", nil, shade, "BackdropTemplate")
    dialog:SetSize(PANEL_WIDE, PANEL_HIGH)
    dialog:SetPoint("CENTER", 0, -(ns.WINDOW_HEADER or 42) / 2)
    T:Flat(dialog, T.PANEL, T.CONTROL_BORDER)
    shade.dialog = dialog
    local title = T:Heading(dialog, "Which spells")
    title:SetPoint("TOPLEFT", 16, -16)
    local quiet = T:Text(dialog, "GameFontHighlightSmall", T.MUTED)
    quiet:SetPoint("LEFT", title, "RIGHT", 8, 0)
    quiet:SetText("untick one you never want listed")
    local panel = CreateFrame("Frame", nil, dialog, "BackdropTemplate")
    panel:SetPoint("TOPLEFT", 16, -44)
    panel:SetPoint("BOTTOMRIGHT", -16, 48)
    T:Flat(panel, T.FIELD, T.BORDER)
    local empty = T:Text(panel, "GameFontHighlightSmall", T.MUTED)
    empty:SetPoint("TOPLEFT", 12, -12)
    empty:SetWidth(PANEL_WIDE - 56)
    empty:SetWordWrap(true)
    local listWide = PANEL_WIDE - 62
    local scroll = T:Scroll(panel, listWide)
    -- Pinned by two corners, and again once it shows: a scroll frame laid out
    -- under a frame with no size of its own never draws (the bar page does
    -- the same).
    local function Pin()
        scroll:ClearAllPoints()
        scroll:SetPoint("TOPLEFT", panel, "TOPLEFT", 8, -6)
        scroll:SetPoint("BOTTOMRIGHT", panel, "BOTTOMRIGHT", -16, 6)
        scroll:ScrollTo(scroll:GetVerticalScroll() or 0)
    end
    Pin()
    shade:HookScript("OnShow", function() C_Timer.After(0, Pin) end)
    window:Hint(scroll.thumb, ns.SCROLL_NOTE)
    shade.list, shade.empty, shade.rows = scroll, empty, {}

    local function Row(i)
        local row = shade.rows[i]
        if row then return row end
        row = CreateFrame("Frame", nil, scroll.content)
        row:SetSize(listWide, PANEL_ROW)
        row.check = T:Check(row, nil, function(self)
            D:Pick(row.spell, self:GetChecked() and true or false)
            window:Refresh()
        end)
        row.check:SetPoint("LEFT", 4, 0)
        -- The whole row clicks its tick, as on the bar pages.
        row.check:SetHitRectInsets(-4, -(listWide - 24), -(PANEL_ROW - 16) / 2, -(PANEL_ROW - 16) / 2)
        window:Hint(row.check, function()
            local name = row.spell or "it"
            if row.check:GetChecked() then return "Untick to leave " .. name .. " out of the list." end
            return "Tick to list " .. name .. " again."
        end)
        row.icon = row:CreateTexture(nil, "ARTWORK")
        row.icon:SetSize(16, 16)
        row.icon:SetPoint("LEFT", 26, 0)
        ns.Style:Zoom(row.icon)
        row.name = T:Text(row, "GameFontHighlight")
        row.name:SetPoint("LEFT", row.icon, "RIGHT", 6, 0)
        row.name:SetWidth(listWide - 130)
        row.name:SetWordWrap(false)
        row.note = T:Text(row, "GameFontHighlightSmall", T.MUTED)
        row.note:SetPoint("RIGHT", -8, 0)
        row.note:SetJustifyH("RIGHT")
        shade.rows[i] = row
        return row
    end

    local done = T:Button(dialog, "Done", 90, 22)
    done:SetPoint("BOTTOMRIGHT", -16, 14)
    done:SetScript("OnClick", function() shade:Hide() end)
    window:Hint(done, "Close this panel. Every tick is kept as you make it.")
    local all = T:Button(dialog, "All of them", 110, 22)
    all:SetPoint("RIGHT", done, "LEFT", -6, 0)
    all:SetScript("OnClick", function()
        for name in pairs(ns.DotsLeftOut()) do ns.SetDotListed(name, true) end
        D:Apply()
        window:Refresh()
    end)
    window:Hint(all, "Lists every one of your damage over time spells again.")
    shade.done, shade.all = done, all

    function shade:Refresh()
        local spells, y = D:Pickable(), 0
        for i, spell in ipairs(spells) do
            local row = Row(i)
            row:ClearAllPoints()
            row:SetPoint("TOPLEFT", 0, -y)
            row.spell = spell.name
            row.icon:SetTexture(spell.icon or 134400)
            row.name:SetText(spell.name)
            row.note:SetText(spell.running and "running now" or spell.proc and "set off by a hit" or "")
            row.check:SetChecked(spell.listed)
            row:Show()
            y = y + PANEL_ROW
        end
        for i = #spells + 1, #self.rows do self.rows[i]:Hide() end
        self.empty:SetText(#spells == 0 and "None of your spells is a damage over time spell yet. New ones show here as you"
            .. " learn them." or "")
        self.empty:SetShown(#spells == 0)
        -- Greyed and unclickable with nothing left out, as a square button
        -- is, and it still says what it is for on hover.
        local count = 0
        for _ in pairs(ns.DotsLeftOut()) do count = count + 1 end
        self.all.usable = count > 0
        self.all:SetEnabled(count > 0)
        self.all:SetMotionScriptsWhileDisabled(true)
        self.all:SetAlpha(count > 0 and 1 or .35)
        scroll.content:SetHeight(math.max(1, y))
        scroll:ScrollTo(scroll:GetVerticalScroll() or 0)
    end

    function shade:Open()
        self:Show()
        self:Refresh()
    end
    return shade
end

-- The ticks on the left, the sliders and the choices on the right, and the
-- two lines that say plainly what the figures are and what they leave out.
local function BuildOptions(window, page, inner)
    local D = ns.Dots
    local function Changed()
        D:Apply()
        window:Refresh()
    end
    local options = CreateFrame("Frame", nil, page)
    options:SetPoint("TOPLEFT", 16, -44)
    options:SetSize(inner, 250)
    page.options = options

    local function Tick(label, key, x, y, note)
        local check = T:Check(options, label, function(self)
            ns.Set(key, self:GetChecked())
            Changed()
        end)
        check:SetPoint("TOPLEFT", x, y)
        check.key = key
        window:Hint(check, note)
        return check
    end
    local function Slider(label, key, limits, step, y, note, percent)
        local slider = T:Slider(options, label, limits, step, inner - COLUMN, function(value)
            ns.Set(key, value)
            Changed()
        end, LABEL)
        slider:SetPoint("TOPLEFT", COLUMN, y)
        slider.key = key
        if percent then
            local set = slider.Set
            function slider:Set(value)
                set(self, value)
                self.value:SetText(value .. "%")
            end
            slider.value:SetWidth(36)
        end
        window:Hint(slider, note)
        return slider
    end
    -- A label in the right-hand column, then its buttons LABEL along.
    local function Pills(label, key, keys, names, width, y, note)
        local text = T:Text(options, "GameFontHighlight")
        text:SetPoint("TOPLEFT", COLUMN, y - 4)
        text:SetText(label)
        local pills = T:Segmented(options, Choices(keys, names), width, function(picked)
            ns.Set(key, picked)
            Changed()
        end)
        pills:SetPoint("TOPLEFT", COLUMN + LABEL, y)
        pills.label, pills.key = text, key
        for _, button in ipairs(pills.buttons) do window:Hint(button, note) end
        return pills
    end

    page.master = Tick("Show my damage over time spells", "dots", 0, 0,
        "The spells you have running on your target, with the damage they still have to deal. Your casts are timed by the"
        .. " addon, so it works in a fight, when the game stops telling addons about auras.")
    page.band = Tick("Mark the damage on the health bar", "dotBand", 0, -26,
        "A band on your target's health bar, from the right end of its health leftwards: the damage your spells still"
        .. " have to deal.")
    page.line = Tick("Bright line at the band's edge", "dotLine", 0, -48,
        "A bright line where your own band ends, so you can see where your spells leave your target's health.")
    page.skull = Tick("Skull when it is enough", "dotSkull", 0, -70,
        "A skull on your target's portrait once the band covers the rest of its health.")
    page.list = Tick("List the spells", "dotList", 0, -92,
        "One row for each spell you have running: its icon with the game's own countdown on it, its name, the seconds left"
        .. " and the damage still to come.")
    page.numbers = Tick("Show the damage left", "dotNumbers", 0, -114,
        "The damage each spell still has to deal, on its own row.")
    page.timer = Tick("Show countdown numbers", "dotTimer", 0, -136,
        "The seconds each spell has left, on its own row, counting down.")
    page.procs = Tick("List the ones a hit sets off", "dotProcs", 0, -158,
        "Spells like Deep Wound that come from a hit rather than a cast. They are listed and timed, but their damage is"
        .. " not counted, because the game does not tell addons how big the hit was.")
    page.others = Tick("Mark other players' spells too", "dotOthers", 0, -180,
        "Damage over time spells anyone else has running on your target, hatched behind your own band, so the band"
        .. " shows everything coming. They are read between fights, and their figures come from each spell's own"
        .. " description.")
    page.nameplates = Tick("Mark it on nameplates too", "dotNameplates", 0, -202,
        "The same band on your target's own nameplate, not just on your target frame. Only your target's plate is"
        .. " marked, since the addon only knows what you have running on it.")
    page.amber = Tick("Amber as it runs out", "dotAmber", 0, -224,
        "A spell with a few seconds left turns amber in the list, so you can see it is about to drop off.")

    page.strength = Slider("Strength", "dotBandStrength", ns.DOT_STRENGTH, 5, 0,
        "How strong the band's colour is over your target's health bar.", true)
    page.size = Slider("Icon size", "dotSize", ns.BAR_LIMITS.size, 2, -26, "How big the icons in the list are.")
    page.rowHeight = Slider("Row height", "dotRowHeight", ns.DOT_ROW, 1, -52,
        "How tall each spell's own bar is, beside its icon.")
    page.spacing = Slider("Spacing", "dotSpacing", ns.BAR_LIMITS.spacing, 1, -78, "The room between the rows.")
    page.across = Slider("Per column", "dotPerRow", ns.DOT_PER_ROW, 1, -104,
        "How many rows there are before the list starts another column beside them.")
    page.grow = Pills("Grow", "dotGrow", ns.GROW, ns.GROW_NAMES, PILLS, -132,
        "Which way the list grows: from its centre, or from its right or left edge.")
    page.wrap = Pills("New rows", "dotWrap", ns.WRAP, ns.WRAP_NAMES, WRAP_PILLS, -154,
        "Where the next row goes: under the one before it, or over it.")
    -- Its note follows Stay hidden with an enemy targeted (General page): with
    -- that ticked a target does not bring the list back, so the note must not
    -- say it does (Dots.lua Awake reads the same setting, and the Totems
    -- bar's own note is written the same way).
    page.outOfCombat = Pills("Out of combat", "dotOutOfCombat", ns.OUT_OF_COMBAT, ns.OUT_OF_COMBAT_NAMES, PILLS, -176,
        function()
            if ns.Get("oocIgnoreTarget") then
                return "Out of combat. It comes back in full in combat, and while this page is open."
            end
            return "Out of combat. It comes back in full in combat, with an enemy targeted, and while this page is open."
        end)
end

-- The two things a player has to be told in plain words, not hidden in a
-- hover: where the figures come from, and what the band leaves out. Right
-- across the page under the colours, where there is room for them to read as
-- sentences rather than a narrow column.
local function BuildNotes(page, inner)
    local function Said(at, text)
        local said = T:Text(page, "GameFontHighlightSmall", T.MUTED)
        said:SetPoint("TOPLEFT", page.colours, "BOTTOMLEFT", 0, at)
        said:SetWidth(inner)
        said:SetWordWrap(true)
        said:SetText(text)
        return said
    end
    page.saidBand = Said(-10, "The figures come from each spell's own description, so they already include your gear. Some"
        .. " spells deal their damage unevenly over their time, and the figure is their total.")
    page.saidProcs = Said(-44, "Spells a hit sets off are listed and timed, but not counted in the band. The game does not"
        .. " tell addons how big the hit was.")
    page.saidOthers = Said(-78, "Other players' spells are read between fights, so one cast during a fight is marked when"
        .. " that fight ends. Their figures are the spell's own description, which says nothing about their gear.")
end

-- One colour for the band and one for the bright line, each with Custom and
-- the way back to what it started as.
local function BuildColours(window, page, inner)
    local D = ns.Dots
    local function Changed()
        D:Apply()
        window:Refresh()
    end
    local heading = T:Heading(page, "Colours")
    heading:SetPoint("TOPLEFT", page.options, "BOTTOMLEFT", 0, -10)
    page.heading = heading
    local colours = CreateFrame("Frame", nil, page)
    colours:SetPoint("TOPLEFT", heading, "BOTTOMLEFT", 0, -8)
    colours:SetSize(inner, 28)
    page.colours = colours
    page.rows = {}
    local rows = {
        { setting = "dotBandColour", name = "Band", keys = ns.DOT_BAND_COLOUR_KEYS,
            -- It is the list's colour as well: each row's own bar is drawn in
            -- it too (Dots.lua Draw), so the hover says both.
            about = "The colour of the band on your target's health bar, and of each row's own bar in the list."
                .. " Click for the colours.",
            default = "Spell's school" },
        { setting = "dotLineColour", name = "Line", keys = ns.TICK_COLOUR_KEYS,
            about = "The colour of the line at the band's left edge. Click for the colours.",
            default = "White" },
    }
    for i, row in ipairs(rows) do
        local x = (i - 1) * COLUMN
        local label = T:Text(colours, "GameFontHighlight")
        label:SetPoint("TOPLEFT", x, -4)
        label:SetText(row.name)
        local lower = row.name:lower()
        local choice = ns.ColourChoice(window, colours, SWATCH, ns.SettingChoice(row.setting, {
            keys = row.keys,
            colourOf = function(key) return D:Colour(row.setting, key) end,
            shown = function() return D:Colour(row.setting) end,
            pick = function(key)
                ns.Set(row.setting, ns.Get(row.setting) ~= key and key or ns.DEFAULTS[row.setting])
                Changed()
            end,
            note = function(key)
                if key == "default" then return "The school of the spell that put it there, for the " .. lower .. "." end
                return Named(key) .. " for the " .. lower .. "."
            end,
            about = row.about,
        }, Changed))
        choice:SetPoint("TOPLEFT", x + LABEL, 0)
        local chosen = T:Text(colours, "GameFontHighlightSmall", T.MUTED)
        chosen:SetPoint("TOPLEFT", x + LABEL + SWATCH + 20, -4)
        chosen:SetWidth(COLOUR_NAME)
        page.rows[i] = { setting = row.setting, choice = choice, chosen = chosen, default = row.default }
    end
end

function ns.BuildDotsPage(window, page, width)
    local D = ns.Dots
    local inner = width - 32
    local title = T:Heading(page, "DoTs")
    title:SetPoint("TOPLEFT", 16, -16)
    local status = T:Text(page, "GameFontHighlightSmall", T.MUTED)
    status:SetPoint("LEFT", title, "RIGHT", 10, 0)
    page.title, page.status = title, status
    -- Choose spells, in a panel over the window: one tick per spell, for the
    -- ones you never want marked or listed (a spell unticked there comes off
    -- our clock altogether, so it leaves the band as well as the rows).
    local choose = T:Button(page, "Choose spells", 120, 20)
    choose:SetPoint("TOPRIGHT", -16, -12)
    choose:SetScript("OnClick", function()
        window.dotsPanel = window.dotsPanel or SpellsPanel(window)
        window.dotsPanel:Open()
    end)
    window:Hint(choose, "One tick for each of your damage over time spells. Untick one you never want marked or listed.")
    page.choose = choose
    BuildOptions(window, page, inner)
    BuildColours(window, page, inner)
    BuildNotes(page, inner)
    -- In full while the page is open, as the Totems bar is (Dots.lua PageOpen).
    page:HookScript("OnShow", function() D:PageOpen(true) end)
    page:HookScript("OnHide", function() D:PageOpen(false) end)

    function page:Refresh()
        local on = D:On()
        self.master:SetChecked(on)
        for _, name in ipairs({ "band", "line", "skull", "list", "numbers", "timer", "procs", "others", "nameplates",
            "amber" }) do
            self[name]:SetChecked(ns.Get(self[name].key) == true)
        end
        for _, name in ipairs({ "strength", "size", "rowHeight", "spacing", "across" }) do
            self[name]:Set(ns.Get(self[name].key))
        end
        for _, name in ipairs({ "grow", "wrap", "outOfCombat" }) do
            self[name]:SetSelected(ns.Get(self[name].key))
        end
        -- Everything is greyed while the part is off. Then the band's line,
        -- its skull, its strength and the line's own colour follow the band's
        -- tick, and the list's own choices follow List the spells.
        local band = on and ns.Get("dotBand") == true
        local list = on and ns.Get("dotList") == true
        self.band:SetUsable(on)
        -- Other players' spells are a band of their own behind yours, so they
        -- follow the band's tick rather than the master's.
        self.others:SetUsable(band)
        -- The ones a hit sets off are listed and timed and never counted in
        -- the band, so this tick only ever changes the list: it follows List
        -- the spells, as the rest of the list's own choices do.
        self.procs:SetUsable(list)
        self.nameplates:SetUsable(band)
        self.line:SetUsable(band)
        self.skull:SetUsable(band)
        self.strength:SetUsable(band)
        self.list:SetUsable(on)
        self.numbers:SetUsable(list)
        self.timer:SetUsable(list)
        self.amber:SetUsable(list)
        self.size:SetUsable(list)
        self.rowHeight:SetUsable(list)
        self.spacing:SetUsable(list)
        self.across:SetUsable(list)
        self.grow:SetUsable(list)
        self.wrap:SetUsable(list)
        self.outOfCombat:SetUsable(on)
        -- Choose spells follows the master tick, not the list: a spell
        -- unticked there is left out of the band as well as the rows (it is
        -- taken off our clock altogether, Dots.lua D:Wanted), so it still
        -- does something with the band on and the rows off. Greyed and
        -- unclickable only while the whole part is off, as a tick is, and it
        -- still says what it is for on hover.
        self.choose.usable = on
        self.choose:SetEnabled(on)
        self.choose:SetMotionScriptsWhileDisabled(true)
        self.choose:SetAlpha(on and 1 or .35)
        for _, row in ipairs(self.rows) do
            local key = ns.Get(row.setting)
            row.chosen:SetText(key == ns.CUSTOM and ns.CUSTOM_NAME
                or key == ns.DEFAULTS[row.setting] and row.default or Named(key))
            row.choice:Paint()
            -- The band's colour is the list's too (each row's own bar is
            -- drawn in it, Dots.lua Draw), so it follows the band or the
            -- list, whichever is on. The line's follows the band alone, since
            -- the line only ever sits on the band's own edge. Greyed and
            -- unclickable while it does nothing, as a tick is, and it still
            -- says what it is for on hover.
            local lit = band
            if row.setting == "dotBandColour" then lit = band or list end
            row.choice:SetEnabled(lit)
            row.choice:SetMotionScriptsWhileDisabled(true)
            row.choice:SetAlpha(lit and 1 or .35)
        end

        local said = "Off. Tick the box below to start."
        local host = ns.DotsBand
        if on and band and host and host.Missing and host:Missing() then
            -- The band could not read this client's target frame, so it has
            -- nothing to sit on. Said plainly, since the rest still works and
            -- a quiet nothing would read as a bug (/ccm debug says why). Not
            -- said while it is only waiting for a fight to end.
            said = "On, but your target frame could not be found, so the band has nothing to sit on. The list still works."
        elseif on then
            local running, damage = D:Running()
            local spells = running == 1 and "spell" or "spells"
            -- What anyone else has running, where that is ticked: said on the
            -- end of the line, so the figures are never mixed up with yours.
            local theirs = select(1, D:Theirs())
            local also = theirs and (" %d of other players' to come."):format(theirs) or ""
            if running == 0 then
                said = "On. Cast a damage over time spell to see it." .. also
            elseif damage then
                said = ("On. %d %s running, %d damage to come."):format(running, spells, damage) .. also
            else
                -- No figure for any of them: the line says how many are
                -- running and leaves the damage out rather than saying nought.
                said = ("On. %d %s running."):format(running, spells) .. also
            end
        end
        self.status:SetText(said)
        -- The panel over the window follows too, while it is open.
        local panel = window.dotsPanel
        if panel and panel:IsShown() then panel:Refresh() end
    end
end
