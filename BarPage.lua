-- A bar's page in the /ccm window: its icons in the order they show (drag
-- one onto another to swap them, x to take it off), its options, and a
-- searchable list of your spells with a tick box to put each on the bar.
local _, ns = ...
local T = ns.Theme

local ICON, GAP = 32, 12 -- icons in the tray; the gap fits the join button
-- The gap on the Cooldowns and Utility bars' trays, which have no join
-- buttons: a full bar (40) takes three rows there, so with their taller
-- options the spell list under them still shows two rows and more.
local TIGHT = 8
local ROW, HEADER_ROW = 22, 20 -- spell list rows
-- The options' height: the Buffs and Debuffs bars', two rows more on a
-- Debuffs bar counting ticks, and on the Cooldowns and Utility bars two rows
-- more for On cooldown's tick and Dimmed icons, then Show the global
-- cooldown's tick under them, which ends at its foot, so the spell list
-- under a full bar still shows two rows.
local OPTIONS, OPTIONS_TALL, OPTIONS_COOLDOWN = 134, 178, 189
local EMPTY = {
    cd = "Nothing here yet. Tick spells in the list below, or drag them here from your spellbook or bags.",
    util = "Nothing here yet. Tick spells in the list below, or drag them here from your spellbook or bags.",
    buff = "Nothing here yet. Tick spells that buff you, or your class procs, in the list below, or drag them here.",
    debuff = "Nothing here yet. Tick spells that put a debuff on your target in the list below, or drag them here.",
}

local function Full(key)
    return ns.BAR_NAMES[key] .. " is full."
end

-- The "Show your debuffs on you" tick on each aura bar's page (the Debuffs
-- one seen working in game 2026-10-08, so no experimental label).
local SELF_TICK = { buff = "Show your debuffs on you", debuff = "Show your debuffs on you" }
local SELF_LABEL = { buff = SELF_TICK.buff, debuff = SELF_TICK.debuff }

-- The Debuffs bar's tick count colour, in parent: a swatch that opens the
-- colours, Custom's kept beside them (tickCustom). For the bar showing
-- (state.bar).
local function TickColour(window, parent, state)
    local B = ns.Bars
    local function Data() return ns.BarData(state.bar) end
    local function Set(key, hex)
        Data().tickCustom = hex
        B:SetOption(state.bar, "tickColour", key)
        window:Refresh()
    end
    return ns.ColourChoice(window, parent, 20, {
        keys = ns.COUNT_COLOUR_KEYS,
        colourOf = function(key) return ns.COUNT_COLOURS[key] end,
        chosen = function() return Data().tickColour end,
        shown = function() return ns.CountColour(ns.CountColourKey(Data())) end,
        pick = function(key) Set(key, Data().tickCustom) end,
        note = function(key) return ns.COUNT_COLOUR_NAMES[key] .. " tick count." end,
        about = "The tick count's colour. Click for the colours.",
        custom = function() return Data().tickCustom end,
        setCustom = function(hex) Set(ns.CUSTOM, hex) end,
        restore = Set,
    })
end

-- A ticked aura's own ticks' hovers (Glow when missing, Only when missing,
-- Count ticks): the same on its row in the spell list and in its panel.
local function GlowNote(bar, name)
    local debuff = ns.BAR_KIND[bar] == "debuff" -- (Debuffs 2 too)
    -- (A buff ticked Only when missing has a spot of its own.)
    if name and not ns.Bars:MissingSpot(bar, name) then
        return debuff and "Tick Show missing debuffs greyed first: the glow shows on a missing debuff's greyed spot."
            or "Tick Show missing buffs greyed or Only when missing first: the glow shows on a missing buff's greyed spot."
    end
    if debuff then
        return "Its icon glows while it's missing from an enemy you target, like a Judgement that fell off."
    end
    return "Its icon glows while it's missing, so you see to recast it, like a Seal that fell off."
end

-- (bar: the Buffs bar whose page or panel it's on: Buffs 2 has its own.)
local function OnlyNote(bar)
    if ns.BarData(bar or "buff").onlyMissing then
        return "Not needed with Only show missing, which already shows every buff only while it's missing."
    end
    return "Shows this buff only while it's missing from you, so you see to recast it. The game hides your buffs"
        .. " from addons in a fight, so changes then show once it ends."
end

-- Glow while active, in a buff's own panel: what it does, or why it can't.
local function ActiveNote(bar, name)
    local B = ns.Bars
    if name and not B:ActiveUsable(bar, name) then
        if ns.BarData(bar).onlyMissing then
            return "Not with Only show missing: a buff has no icon while it's on you, so nothing to glow."
        end
        if not B:WarnUsable(bar, name) then
            return "Not for a buff shown Only when missing: it has no icon while it's on you, so nothing to glow."
        end
        return "Not for a weapon enchant: only a buff's icon can glow while it's up."
    end
    return "Its icon glows while the buff is on you, like a proc, so you can't miss it. Best for short procs."
end

local function TicksNote(bar, name, label)
    local B = ns.Bars
    local pace = name and B:TickPace(name) or 0
    local clash = name and B:TickClash(bar, name)
    local found = clash and ns.Spells:Find(clash)
    if clash then
        return "Can't count while it shares an icon with " .. (found and found.name or clash) .. ": the game can't tell the two apart."
    end
    return "Counts its ticks on its icon, every " .. pace .. (pace == 1 and " second" or " seconds")
        .. " for " .. (label or "it") .. ", starting again when you reapply it."
end

-- Settings per spell ---------------------------------------------------------------
-- (A player's idea: a font and size per icon.) Clicking an icon in a bar
-- page's tray opens its own panel over the window: its icon with a
-- countdown going round, at the bar's size, then its countdown's own font
-- and size, each the Look page's until picked (kept by entry in your
-- profile: Bars.lua B:SetSpellLook), and on the Buffs and Debuffs pages its
-- own ticks from the spell list, so they're there without scrolling to its
-- row. Like the Look page's panels its shade leaves the footer clear, so
-- each control still says what it does there. Made the first time it opens.
local PANEL = { width = 470, at = 96, row = 26, own = 84, tray = { 42, 64 } }
local PANEL_TIME = 75 -- the preview's cooldown, round and round: past a minute, then seconds
local PANEL_NOTE = "On every bar it's on, and on Blizzard's icon for it while the look is on the Cooldown Manager."
local PANEL_AURAS = " The Buffs and Debuffs bars change once you're out of combat."
local PANEL_OFF = " Show countdown numbers is off on this bar."
local UNTESTED = " (experimental)"

-- The preview's icon, in the middle of its tray, its cooldown starting
-- again as it ends while the panel shows.
local function PanelIcon(tray)
    local icon = CreateFrame("Frame", nil, tray)
    icon:SetSize(36, 36)
    icon:SetPoint("CENTER")
    icon.art = icon:CreateTexture(nil, "ARTWORK")
    icon.art:SetAllPoints()
    ns.Style:Zoom(icon.art)
    local cooldown = CreateFrame("Cooldown", nil, icon, "CooldownFrameTemplate")
    cooldown:SetAllPoints(icon.art)
    cooldown:SetSwipeTexture(ns.Style.FLAT)
    cooldown:SetDrawBling(false)
    cooldown:SetHideCountdownNumbers(false)
    cooldown:SetScript("OnCooldownDone", function(self)
        if tray:IsVisible() then self:SetCooldown(GetTime(), PANEL_TIME) end
    end)
    icon.cooldown = cooldown
    return icon
end

-- The preview in the spell's look, at its size on its bar (its own, where
-- its bar can show one; within the tray), drawn by the calls your bars'
-- icons use.
local function PaintPanelIcon(icon, bar, name)
    local S = ns.Style
    local shown = ns.IconSize(ns.BarData(bar))
    if ns.Bars:OwnSizeUsable(bar) then shown = ns.IconSizeFor(bar, name, shown) end
    local size = math.max(24, math.min(PANEL.tray[2] - 12, shown))
    icon:SetSize(size, size)
    icon.art:SetTexture(ns.Spells:Icon(name))
    icon.art:SetDesaturated(ns.Spells:Find(name) == nil)
    local cooldown = icon.cooldown
    S:CooldownLook(cooldown)
    cooldown:SetCountdownFont(S:Countdown(size, ns.SpellLook(name)))
    local get = cooldown.GetCountdownFontString
    local numbers = type(get) == "function" and get(cooldown) or nil
    if numbers then S:NumbersAt(numbers, cooldown, 0) end
end

-- The font row: the Look page's first (its name in that font), then each
-- font in its own face.
local function PanelFont(window, dialog, shade, Changed)
    local keys = { "look" }
    for _, key in ipairs(ns.FONT_KEYS) do keys[#keys + 1] = key end
    return ns.FontChoice(window, dialog, 260, {
        keys = keys,
        name = function(key) return key == "look" and "Look page" or ns.FONT_NAMES[key] end,
        face = function(key) return ns.Style:SampleFont(key == "look" and ns.Get("font") or key) end,
        note = function(key)
            if key == "look" then return "The Look page's font, now " .. ns.FONT_NAMES[ns.Get("font")] .. "." end
            return (ns.FONT_NOTES and ns.FONT_NOTES[key] or ns.FONT_NAMES[key]) .. ", just for this spell's countdown."
        end,
        pick = function(key)
            ns.Bars:SetSpellLook(shade.name, "font", key ~= "look" and key or nil)
            Changed()
        end,
        about = "This spell's countdown font: the Look page's, or one of its own. Click for the fonts." .. UNTESTED,
    })
end

-- The size row: Its own, then how big while it's ticked (a percent, as
-- Icon details' Size); unticked, the Look page's.
local function PanelSize(window, dialog, shade, Changed)
    local own = T:Check(dialog, "Its own", function(self)
        local value = self:GetChecked() and (shade.size.current or ns.Get("countdownSize")) or nil
        ns.Bars:SetSpellLook(shade.name, "size", value)
        Changed()
    end)
    window:Hint(own, "Gives this spell's countdown a size of its own, in place of Icon details' Size on the Look page."
        .. UNTESTED)
    local size = T:Slider(dialog, "", ns.COUNTDOWN_SIZE, 5, PANEL.width - 16 - PANEL.at - PANEL.own, function(value)
        if ns.SpellLook(shade.name) and ns.SpellLook(shade.name).size then
            ns.Bars:SetSpellLook(shade.name, "size", value)
            Changed()
        end
    end, 0)
    size.value:SetWidth(36)
    local set = size.Set
    function size:Set(value)
        set(self, value)
        self.value:SetText(value .. "%")
    end
    window:Hint(size, function()
        if not own:GetChecked() then return "Tick Its own first: until then it's Icon details' Size." end
        return "How big this spell's countdown is: 100% is about half the icon. In the middle it still moves clear of a"
            .. " keybind." .. UNTESTED
    end)
    return own, size
end

-- The icon's own size on this bar (a player's idea: more control over each
-- icon's size): Its own, then how big while it's ticked, a percent of the
-- bar's Icon size; unticked, the bar's. On a packed Buffs or Debuffs bar
-- both are greyed, saying why: the game draws those icons, all one size.
local function PackedNote(bar)
    local word = ns.AURA_BARS[bar] and ns.AURA_BARS[bar].word or "buff"
    return "This bar is packed: the game lays its icons out at one size. Tick Show missing " .. word
        .. "s greyed to give each its own spot, then its own size."
end

local function PanelIconSize(window, dialog, shade, Changed)
    local B = ns.Bars
    local own = T:Check(dialog, "Its own", function(self)
        B:SetOwnSize(shade.bar, shade.name, self:GetChecked() and (shade.iconSize.current or ns.ICON_SIZE[3]) or nil)
        Changed()
    end)
    window:Hint(own, function()
        if not B:OwnSizeUsable(shade.bar) then return PackedNote(shade.bar) end
        return "Gives this icon a size of its own on " .. ns.BAR_NAMES[shade.bar] .. ", in place of the bar's Icon size." .. UNTESTED
    end)
    local size = T:Slider(dialog, "", ns.ICON_SIZE, 5, PANEL.width - 16 - PANEL.at - PANEL.own, function(value)
        if ns.OwnSize(shade.bar, shade.name) then
            B:SetOwnSize(shade.bar, shade.name, value)
            Changed()
        end
    end, 0)
    size.value:SetWidth(36)
    local set = size.Set
    function size:Set(value)
        set(self, value)
        self.value:SetText(value .. "%")
    end
    window:Hint(size, function()
        if not B:OwnSizeUsable(shade.bar) then return PackedNote(shade.bar) end
        if not own:GetChecked() then return "Tick Its own first: until then it's the bar's Icon size." end
        return "How big this icon is: 100% is the bar's Icon size. The rest of the bar makes room for it." .. UNTESTED
    end)
    return own, size
end

-- Its own ticks from the spell list, each in a row of its own.
local function PanelTicks(window, dialog, shade, Changed)
    local B = ns.Bars
    local glow = T:Check(dialog, "Glow when missing", function(self)
        B:SetGlowMissing(shade.bar, shade.name, self:GetChecked())
        Changed()
    end)
    window:Hint(glow, function() return GlowNote(shade.bar, shade.name) end)
    local only = T:Check(dialog, "Only when missing", function(self)
        B:SetOnlyWhenMissing(shade.bar, shade.name, self:GetChecked())
        Changed()
    end)
    window:Hint(only, function() return OnlyNote(shade.bar) end)
    local ticks = T:Check(dialog, "Count ticks", function(self)
        B:SetCountTicks(shade.bar, shade.name, self:GetChecked())
        Changed()
    end)
    window:Hint(ticks, function() return TicksNote(shade.bar, shade.name, shade.label) end)
    -- Glow while active: only here, as the list row has no room for it
    -- (seen working in game, 8 Nov 2026, so not marked experimental).
    local active = T:Check(dialog, "Glow while active", function(self)
        B:SetGlowActive(shade.bar, shade.name, self:GetChecked())
        Changed()
    end)
    window:Hint(active, function() return ActiveNote(shade.bar, shade.name) end)
    return glow, only, ticks, active
end

-- Glow size, right under Glow while active and shown with it: how big the
-- glow is, a percent of its usual size. The profile's, for every buff that
-- glows, not this one's alone; greyed while this one's tick is off or greyed.
local function PanelGlowSize(window, dialog, shade, Changed)
    local B = ns.Bars
    local function Usable() return B:ActiveUsable(shade.bar, shade.name) and B:GlowsActive(shade.bar, shade.name) end
    local label = T:Text(dialog, "GameFontHighlight")
    label:SetText("Glow size")
    local size = T:Slider(dialog, "", ns.GLOW_ACTIVE_SIZE, 10, PANEL.width - 16 - PANEL.at, function(value)
        if Usable() then B:SetGlowActiveSize(value) end
        Changed() -- (greyed, it shows the kept size again)
    end, 0)
    size.value:SetWidth(36)
    local set = size.Set
    function size:Set(value)
        set(self, value)
        self.value:SetText(value .. "%")
    end
    window:Hint(size, function()
        if not B:ActiveUsable(shade.bar, shade.name) then return ActiveNote(shade.bar, shade.name) end
        if not B:GlowsActive(shade.bar, shade.name) then return "Tick Glow while active first: this sizes its glow." end
        return "How big the glow is round every buff that glows while it's up, not just this one: 100% is its usual size."
    end)
    return label, size, Usable
end

-- Warn at N seconds left (a player's idea: Siphon Life with 3 seconds left,
-- Demon Armor with 10 minutes left), on the Buffs and Debuffs pages: Off,
-- then each time offered, as pills (3s .. 10m).
local function WarnLength(seconds)
    if seconds >= 60 then
        local minutes = math.floor(seconds / 60)
        return ("%d %s"):format(minutes, minutes == 1 and "minute" or "minutes")
    end
    return ("%d %s"):format(seconds, seconds == 1 and "second" or "seconds")
end

local function WarnNote(bar, name, seconds)
    local buff = ns.BAR_KIND[bar] == "buff" -- (Buffs 2 too)
    if not ns.Bars:WarnUsable(bar, name) then
        if ns.BarData(bar).onlyMissing then
            return "Not with Only show missing: a buff has no icon while it's on you, so nothing to warn on."
        end
        return "Not for a buff shown Only when missing: it has no icon while it's on you, so nothing to warn on."
    end
    if seconds == 0 then return "No warning: its countdown stays as it is." end
    local text = "Its countdown turns red with " .. WarnLength(seconds) .. " left"
    -- A hand entry's spot is the addon's own: no red edge (that's an aura's).
    local entry = ns.Spells:Find(name)
    if entry and entry.hand then
        if buff and ns.BuffBar:Fixed(ns.BarData(bar)) then text = text .. ". Out of combat its icon glows too" end
    elseif ns.BuffBar:Fixed(ns.BarData(bar)) then
        text = text .. ", with a red edge round its icon" .. (buff and ". Out of combat its icon glows too" or "")
    else
        text = text .. ". Tick Show missing " .. (buff and "buffs" or "debuffs") .. " greyed for a red edge round its icon too"
    end
    return text .. "." .. UNTESTED
end

local function PanelWarn(window, dialog, shade)
    local items = { { key = 0, label = "Off" } }
    for _, seconds in ipairs(ns.WARN_SECONDS) do
        items[#items + 1] = { key = seconds, label = seconds >= 60 and ("%dm"):format(math.floor(seconds / 60)) or (seconds .. "s") }
    end
    local warn = T:Segmented(dialog, items, PANEL.width - 16 - PANEL.at, function(seconds)
        ns.Bars:SetWarnAt(shade.bar, shade.name, seconds)
        window:Refresh()
    end)
    for _, button in ipairs(warn.buttons) do
        window:Hint(button, function() return WarnNote(shade.bar, shade.name, button.key) end)
    end
    local label = T:Text(dialog, "GameFontHighlight")
    label:SetText("Warn at")
    return label, warn
end

-- Which of its own ticks the entry has on its bar: Glow when missing on the
-- Buffs and Debuffs bars, Only when missing and Glow while active on Buffs,
-- Count ticks on Debuffs for one that ticks. Each shown and set as its row
-- in the list is (Glow while active has no row there).
local function PaintTicks(shade, bar, name)
    local B = ns.Bars
    local aura, kind = ns.AURA_BARS[bar] ~= nil, ns.BAR_KIND[bar] -- (an extra bar goes by its kind)
    shade.glow:SetChecked(B:GlowsMissing(bar, name))
    shade.glow:SetUsable(B:MissingSpot(bar, name))
    shade.only:SetChecked(B:OnlyWhenMissing(bar, name))
    shade.only:SetUsable(not ns.BarData(bar).onlyMissing)
    shade.ticks:SetChecked(B:CountsTicks(bar, name))
    shade.ticks:SetUsable(shade.ticks:GetChecked() or not B:TickClash(bar, name))
    shade.active:SetChecked(B:GlowsActive(bar, name))
    shade.active:SetUsable(B:ActiveUsable(bar, name))
    return { aura and shade.glow or nil, kind == "buff" and shade.only or nil,
        kind == "debuff" and B:TickPace(name) ~= nil and shade.ticks or nil, kind == "buff" and shade.active or nil }
end

local function SpellPanel(window)
    local B = ns.Bars
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
    dialog:SetSize(PANEL.width, 300)
    dialog:SetPoint("CENTER", 0, -(ns.WINDOW_HEADER or 42) / 2)
    T:Flat(dialog, T.PANEL, T.CONTROL_BORDER)
    shade.dialog = dialog
    local title = T:Heading(dialog, "")
    title:SetPoint("TOPLEFT", 16, -16)
    local quiet = T:Text(dialog, "GameFontHighlightSmall", T.MUTED)
    quiet:SetPoint("LEFT", title, "RIGHT", 8, 0)
    shade.title, shade.quiet = title, quiet
    local tray = CreateFrame("Frame", nil, dialog, "BackdropTemplate")
    tray:SetPoint("TOPLEFT", 16, -PANEL.tray[1])
    tray:SetSize(PANEL.width - 32, PANEL.tray[2])
    T:Flat(tray, T.FIELD, T.BORDER)
    shade.tray, shade.preview = tray, PanelIcon(tray)
    local function Changed() window:Refresh() end

    -- The rows, each a label at the left and its choices from PANEL.at.
    local top = -(PANEL.tray[1] + PANEL.tray[2] + 14)
    local function At(region, x, row, down)
        region:ClearAllPoints()
        region:SetPoint("TOPLEFT", x, top - row * PANEL.row - (down or 0))
    end
    local fontLabel = T:Text(dialog, "GameFontHighlight")
    fontLabel:SetText("Font")
    At(fontLabel, 16, 0, 4)
    shade.font = PanelFont(window, dialog, shade, Changed)
    At(shade.font, PANEL.at, 0)
    local sizeLabel = T:Text(dialog, "GameFontHighlight")
    sizeLabel:SetText("Size")
    At(sizeLabel, 16, 1, 4)
    shade.own, shade.size = PanelSize(window, dialog, shade, Changed)
    At(shade.own, PANEL.at, 1, 2)
    At(shade.size, PANEL.at + PANEL.own, 1)
    -- The icon's own size on this bar, under its countdown's.
    local iconLabel = T:Text(dialog, "GameFontHighlight")
    iconLabel:SetText("Icon size")
    At(iconLabel, 16, 2, 4)
    shade.ownIcon, shade.iconSize = PanelIconSize(window, dialog, shade, Changed)
    At(shade.ownIcon, PANEL.at, 2, 2)
    At(shade.iconSize, PANEL.at + PANEL.own, 2)
    shade.glow, shade.only, shade.ticks, shade.active = PanelTicks(window, dialog, shade, Changed)
    shade.glowSizeLabel, shade.glowSize, shade.glowSizeUsable = PanelGlowSize(window, dialog, shade, Changed)
    shade.warnLabel, shade.warn = PanelWarn(window, dialog, shade)
    local note = T:Text(dialog, "GameFontHighlightSmall", T.MUTED)
    note:SetWidth(PANEL.width - 32)
    shade.note = note
    local done = T:Button(dialog, "Done", 90, 22)
    done:SetPoint("BOTTOMRIGHT", -16, 14)
    done:SetScript("OnClick", function() shade:Hide() end)
    window:Hint(done, "Close this panel. Every choice is kept as you make it.")
    local defaults = T:Button(dialog, "Defaults", 90, 22)
    defaults:SetPoint("RIGHT", done, "LEFT", -6, 0)
    defaults:SetScript("OnClick", function()
        B:ClearSpellLook(shade.name)
        B:SetOwnSize(shade.bar, shade.name, nil)
        Changed()
    end)
    window:Hint(defaults, "This spell's countdown back in the Look page's font and size, and its icon at the bar's size."
        .. " Its ticks stay as they are.")
    shade.done, shade.defaults = done, defaults
    window:HookScript("OnHide", function() shade:Hide() end)

    -- The choices as they are now: its own ticks in rows under the size,
    -- the note under them, and the panel as tall as they need. Gone with
    -- its entry (taken off the bar).
    function shade:Refresh()
        local bar, name = self.bar, self.name
        if not (bar and name and B:Index(bar, name)) then return self:Hide() end
        local entry = ns.Spells:Find(name)
        self.label = entry and entry.name or name
        title:SetText(((entry and (entry.shown or entry.name)) or name):upper())
        quiet:SetText("on " .. ns.BAR_NAMES[bar])
        local look = ns.SpellLook(name) or {}
        self.font:SetSelected(look.font or "look")
        self.own:SetChecked(look.size ~= nil)
        self.size:Set(look.size or ns.Get("countdownSize"))
        self.size:SetUsable(look.size ~= nil)
        -- Its icon's own size: kept on a packed bar, but greyed there.
        local ownSize, sizable = ns.OwnSize(bar, name), B:OwnSizeUsable(bar)
        self.ownIcon:SetChecked(ownSize ~= nil)
        self.ownIcon:SetUsable(sizable)
        self.iconSize:Set(ownSize or ns.ICON_SIZE[3])
        self.iconSize:SetUsable(sizable and ownSize ~= nil)
        local shown = PaintTicks(self, bar, name)
        local rows = 3
        -- Warn at, on the Buffs and Debuffs pages, under the size.
        local aura = ns.AURA_BARS[bar] ~= nil
        self.warnLabel:SetShown(aura)
        self.warn:SetShown(aura)
        if aura then
            At(self.warnLabel, 16, rows, 4)
            At(self.warn, PANEL.at, rows)
            self.warn:SetSelected(B:WarnAt(bar, name) or 0)
            self.warn:SetUsable(B:WarnUsable(bar, name))
            rows = rows + 1
        end
        for _, tick in ipairs({ self.glow, self.only, self.active, self.ticks }) do
            local on = tick == shown[1] or tick == shown[2] or tick == shown[3] or tick == shown[4]
            tick:SetShown(on)
            if on then
                At(tick, 16, rows, 2)
                rows = rows + 1
            end
            -- Glow size in the row under Glow while active, shown with it.
            if tick == self.active then
                self.glowSizeLabel:SetShown(on)
                self.glowSize:SetShown(on)
                if on then
                    At(self.glowSizeLabel, 16, rows, 4)
                    At(self.glowSize, PANEL.at, rows)
                    self.glowSize:Set(ns.GlowActiveSize())
                    self.glowSize:SetUsable(self.glowSizeUsable())
                    rows = rows + 1
                end
            end
        end
        note:SetText(PANEL_NOTE .. (aura and PANEL_AURAS or "") .. (ns.BarData(bar).showTimer and "" or PANEL_OFF))
        At(note, 16, rows, 4)
        local changed = look.font ~= nil or look.size ~= nil or ownSize ~= nil
        defaults:SetEnabled(changed)
        defaults:SetAlpha(changed and 1 or .45)
        dialog:SetHeight(math.ceil(-top + rows * PANEL.row + 4 + math.max(24, note:GetStringHeight() or 0) + 10 + 22 + 14))
        PaintPanelIcon(self.preview, bar, name)
    end
    -- Open for an entry on a bar: the preview's cooldown starts part way round.
    function shade:Open(bar, name)
        self.bar, self.name = bar, name
        self:Show()
        self.preview.cooldown:SetCooldown(GetTime() - 10, PANEL_TIME)
        self:Refresh()
    end
    return shade
end

function ns.BuildBarPage(window, page, width)
    local B = ns.Bars
    local state = { bar = "cd", search = "" }
    local inner = width - 32
    local perRow = math.floor((inner - 12 + GAP) / (ICON + GAP))
    local perRowTight = math.floor((inner - 12 + TIGHT) / (ICON + TIGHT)) -- the Cooldowns and Utility trays'

    -- Title row -------------------------------------------------------------------
    local title = T:Heading(page, "")
    title:SetPoint("TOPLEFT", 16, -16)
    -- On a second bar's page (Buffs 2), a "<" before the title goes back to
    -- its first bar; the title moves along after it (Refresh).
    local back = T:Square(page, "<")
    back:SetPoint("TOPLEFT", 14, -13)
    back:SetScript("OnClick", function() window:Select(ns.BAR_KIND[state.bar]) end)
    window:Hint(back, function() return "Back to " .. ns.BAR_NAMES[ns.BAR_KIND[state.bar]] .. "." end)
    back:Hide()
    page.back = back
    local count = T:Text(page, "GameFontHighlightSmall", T.MUTED)
    count:SetPoint("LEFT", title, "RIGHT", 10, 0)
    page.count = count
    -- While your bars are off, a way to turn them on right here.
    local off = T:Text(page, "GameFontHighlightSmall", T.WARN)
    off:SetPoint("LEFT", title, "RIGHT", 10, 0)
    off:SetText("Your bars are off.")
    local turnOn = T:Button(page, "Turn on", 70, 18)
    turnOn:SetPoint("LEFT", off, "RIGHT", 8, 0)
    turnOn:SetScript("OnClick", function()
        local message = ns.SetBars(true)
        if message then window:Say(message) end
        B:Rebuild()
        window:Refresh()
    end)
    window:Hint(turnOn, "Turn your bars on.")
    page.turnOn = turnOn
    -- A bar taken out of your layout says so, with a way to put it back.
    local out = T:Text(page, "GameFontHighlightSmall", T.WARN)
    out:SetPoint("LEFT", title, "RIGHT", 10, 0)
    out:SetText("Taken out of your layout.")
    local putBack = T:Button(page, "Put back", 70, 18)
    putBack:SetPoint("LEFT", out, "RIGHT", 8, 0)
    putBack:SetScript("OnClick", function()
        local _, message = ns.Layout:PutBack(state.bar)
        window:Say(message)
        window:Refresh()
    end)
    window:Hint(putBack, function() return "Put " .. ns.BAR_NAMES[state.bar] .. " back in your layout." end)
    page.putBack = putBack

    -- Clearing asks for a second click within a few seconds.
    local clear = T:Button(page, "", 130, 20)
    clear:SetPoint("TOPRIGHT", -16, -12)
    clear:SetScript("OnClick", function()
        local key = state.bar
        if state.armed == key then
            state.armed = nil
            B:Clear(key)
            window:Say(ns.BAR_NAMES[key] .. " cleared.")
        else
            state.armed = key
            C_Timer.After(4, function()
                if state.armed == key then
                    state.armed = nil
                    if window:IsShown() then window:Refresh() end
                end
            end)
        end
        window:Refresh()
    end)
    window:Hint(clear, function()
        local name = ns.BAR_NAMES[state.bar]
        -- Buffs or debuffs added before they were turned away, which show
        -- there for no one, go too (B:Leftovers): said only while there are any.
        local also, untested = "", ""
        if #B:Leftovers(state.bar) > 0 then
            also, untested = ", and buffs or debuffs added to it that can't show there", " (experimental)"
        end
        return state.armed == state.bar and ("Click again to take every icon off " .. name .. also .. "." .. untested)
            or ("Take every icon off " .. name .. also .. ". It asks for a second click." .. untested)
    end)
    page.clear = clear

    -- Extra bars (a player's idea: Curse of the Elements on a bar apart from
    -- three damage over time spells), left of Clear: on one of the four
    -- bars' pages, "+ Another bar" adds its kind's second bar (Core.lua), or
    -- once there, goes to its page; on that page, Remove bar (it asks
    -- first). The "<" before its title goes back, as does its kind's item
    -- in the list, lit there.
    local another = T:Button(page, "", 96, 20)
    another:SetScript("OnClick", function()
        local key = state.bar
        local extra = ns.EXTRA_OF[key]
        if not extra then
            return window:Ask("Remove " .. ns.BAR_NAMES[key] .. "?", "Its spells and their settings go from this profile. You can"
                .. " add it again on the " .. ns.BAR_NAMES[ns.BAR_KIND[key]] .. " page.", "Remove", function()
                local ok, message = B:RemoveBar(key)
                window:Say(message)
                if ok then window:Select(ns.BAR_KIND[key]) else window:Refresh() end
            end)
        end
        if ns.HasBar(extra) then return window:Select(extra) end
        local ok, added, message = B:AddBar(key)
        if not ok then
            window:Say(added)
            return window:Refresh()
        end
        window:Say(message)
        window:Select(added)
    end)
    window:Hint(another, function()
        local key = state.bar
        local extra = ns.EXTRA_OF[key]
        if not extra then
            return "Remove " .. ns.BAR_NAMES[key] .. " from this profile, with its spells. It asks first. "
                .. "The < before the title goes back to " .. ns.BAR_NAMES[ns.BAR_KIND[key]] .. ". (experimental)"
        end
        if ns.HasBar(extra) then return "The " .. ns.BAR_NAMES[extra] .. " page: your second " .. ns.BAR_NAMES[key] .. " bar." end
        local can, why = ns.CanAddBar(key)
        if not can then return why end
        return "Adds " .. ns.BAR_NAMES[extra] .. ": a second " .. ns.BAR_NAMES[key] .. " bar with its own spells, size, options"
            .. " and Layout row, say to keep one spell apart from the rest. (experimental)"
    end)
    page.another = another

    -- The tray: the bar's icons, left to right --------------------------------------
    local tray = CreateFrame("Frame", nil, page, "BackdropTemplate")
    tray:SetPoint("TOPLEFT", 16, -38)
    tray:SetSize(inner, 16 + ICON) -- a real size from the start, before the first refresh
    T:Flat(tray, T.PANEL, T.BORDER)
    -- A spell dragged from your spellbook (any spellbook) or an action bar,
    -- or an item, dropped here joins the bar.
    tray:EnableMouse(true)
    tray:SetScript("OnReceiveDrag", function() B:Dropped(state.bar) end)
    tray:SetScript("OnMouseUp", function() B:Dropped(state.bar) end)
    -- Held over the tray or its icons, the footer says what dropping does.
    local function Bar() return state.bar end
    tray.drop = Bar
    window:Hint(tray, "Drop a spell or item here from your spellbook, bags or action bars. Drag an icon onto another to swap them.")
    local empty = T:Text(tray, "GameFontHighlightSmall", T.MUTED)
    empty:SetPoint("LEFT", 12, 0)
    empty:SetWidth(inner - 24)
    page.tray, page.icons = tray, {}

    -- The icon being dragged follows the cursor.
    local ghost = CreateFrame("Frame", nil, page)
    ghost:SetSize(ICON, ICON)
    ghost:SetFrameLevel(page:GetFrameLevel() + 40)
    ghost.texture = ghost:CreateTexture(nil, "OVERLAY")
    ghost.texture:SetAllPoints()
    ghost.texture:SetAlpha(.8)
    ns.Style:Zoom(ghost.texture)
    ghost:Hide()
    page.ghost = ghost
    -- The icon it would swap with, outlined in the accent. Takes no mouse.
    local mark = CreateFrame("Frame", nil, tray, "BackdropTemplate")
    mark:SetFrameLevel(tray:GetFrameLevel() + 10)
    mark:EnableMouse(false)
    T:Flat(mark, { 0, 0, 0, 0 }, T.CONTROL_BORDER)
    T:Paint(function(accent) mark:SetBackdropBorderColor(accent[1], accent[2], accent[3], 1) end)
    mark:Hide()
    page.mark = mark

    -- Where a dragged icon lands: onto another icon swaps the two (the
    -- place and the icon), anywhere else in the tray puts it last; nil off
    -- the bar.
    local function DropTarget()
        for _, icon in ipairs(page.icons) do
            if icon:IsShown() and icon:IsMouseOver() then return icon.index, icon end
        end
        if tray:IsMouseOver() then return #ns.BarData(state.bar).spells end
    end

    -- While an icon is held: the one it would swap with outlined, the footer
    -- saying what letting go does, and the held icon greyed where letting go
    -- takes it off. Only when that changes.
    local said, marked
    local function Track()
        local from, held = state.drag, state.held
        if not (from and held) then
            said, marked = nil, nil
            mark:Hide()
            return window:DragNote(nil)
        end
        local to, onto = DropTarget()
        local swap = onto ~= nil and to ~= from
        local text
        if swap then
            text = "Let go to swap " .. held.name .. " and " .. onto.name .. "."
        elseif to == from then
            text = "Let go to leave " .. held.name .. " where it is."
        elseif to then
            text = "Let go to put " .. held.name .. " last."
        else
            text = "Let go to take " .. held.name .. " off " .. ns.BAR_NAMES[state.bar] .. "."
        end
        ghost.texture:SetDesaturated(to == nil)
        local around = swap and onto or nil
        if text == said and around == marked then return end
        said, marked = text, around
        mark:SetShown(around ~= nil)
        if around then
            mark:ClearAllPoints()
            mark:SetPoint("TOPLEFT", around, "TOPLEFT", -3, 3)
            mark:SetPoint("BOTTOMRIGHT", around, "BOTTOMRIGHT", 3, -3)
        end
        window:DragNote(text)
    end

    ghost:SetScript("OnUpdate", function(self)
        local x, y = GetCursorPosition()
        local scale = UIParent:GetEffectiveScale()
        self:ClearAllPoints()
        self:SetPoint("CENTER", UIParent, "BOTTOMLEFT", x / scale, y / scale)
        Track()
    end)
    -- The window closing mid-drag drops nothing: the icon's spot comes back,
    -- and no icon is left on the cursor for next time.
    page:HookScript("OnHide", function()
        state.drag, state.held = nil, nil
        ghost:Hide()
        Track()
        for _, icon in ipairs(page.icons) do icon:SetAlpha(1) end
    end)

    local function TrayIcon(i)
        local icon = page.icons[i]
        if icon then return icon end
        icon = CreateFrame("Button", nil, tray)
        icon:SetSize(ICON, ICON) -- placed on refresh: each bar's tray has its own gap
        icon.texture = icon:CreateTexture(nil, "ARTWORK")
        icon.texture:SetAllPoints()
        ns.Style:Zoom(icon.texture)
        local hover = icon:CreateTexture(nil, "HIGHLIGHT")
        hover:SetAllPoints()
        hover:SetColorTexture(1, 1, 1, .12)
        icon.remove = T:Square(icon, "x")
        icon.remove:SetSize(14, 14)
        icon.remove:SetPoint("CENTER", icon, "TOPRIGHT", -1, -1)
        icon.remove:SetScript("OnClick", function()
            B:Remove(state.bar, icon.index)
            window:Refresh()
        end)
        window:Hint(icon.remove, function() return "Take " .. (icon.name or "it") .. " off " .. ns.BAR_NAMES[state.bar] .. "." end)
        -- On the Buffs and Debuffs bars, the button in the gap before an icon
        -- joins it to the one before, or splits them again; a line under the
        -- pair shows they're joined.
        icon.link = T:Square(tray, "+")
        icon.link:SetSize(14, 14)
        icon.link:SetPoint("CENTER", icon, "LEFT", -GAP / 2, 0)
        icon.link:SetFrameLevel(icon:GetFrameLevel() + 3)
        icon.link:SetScript("OnClick", function()
            -- Split off, it needs an icon of its own: a full bar says so.
            local _, message = B:SetJoined(state.bar, icon.index, not B:Joined(state.bar, icon.index))
            if message then window:Say(message) end
            window:Refresh()
        end)
        window:Hint(icon.link, function()
            local spells = ns.BarData(state.bar).spells
            if B:Kindred(state.bar, spells[icon.index - 1], spells[icon.index]) then return B.FAMILY_TIED end
            return B:Joined(state.bar, icon.index) and "Split this from the one before."
                or "Join this to the one before: they'll show as one icon, lit by whichever is up."
        end)
        icon.bridge = tray:CreateTexture(nil, "ARTWORK")
        icon.bridge:SetHeight(3)
        icon.bridge:SetPoint("TOPLEFT", icon, "BOTTOMLEFT", -(ICON + GAP), -3)
        icon.bridge:SetPoint("TOPRIGHT", icon, "BOTTOMRIGHT", 0, -3)
        T:Paint(function(accent) T:Fill(icon.bridge, accent) end)
        icon:RegisterForDrag("LeftButton")
        icon:SetScript("OnDragStart", function(self)
            state.drag, state.held = self.index, self
            self:SetAlpha(0) -- picked up: its spot is empty until it lands
            ghost.texture:SetTexture(self.texture:GetTexture())
            ghost.texture:SetDesaturated(false)
            ghost:Show()
        end)
        icon:SetScript("OnDragStop", function(self)
            ghost:Hide()
            self:SetAlpha(1)
            local from = state.drag
            local to, onto = DropTarget()
            state.drag, state.held = nil, nil
            Track()
            if from and onto and to ~= from then
                -- Onto another icon: the two swap places.
                local _, message = B:Swap(state.bar, from, to)
                if message then window:Say(message) end
                window:Refresh()
            elseif from and to and to ~= from then
                local _, message = B:MoveTo(state.bar, from, to)
                if message then window:Say(message) end
                window:Refresh()
            elseif from and not to then
                -- Dragged off the bar: taken off it.
                local _, message = B:TakeOff(state.bar, ns.BarData(state.bar).spells[from])
                window:Say(message)
                window:Refresh()
            end
        end)
        -- A spell or item dropped on an icon, or clicked onto it, joins the
        -- bar, as on the tray round it; a click with nothing held opens the
        -- icon's own panel (below).
        icon:SetScript("OnReceiveDrag", function() B:Dropped(state.bar) end)
        -- Right-clicked in a joined icon (a player's idea): this one shows,
        -- faded, while none of them is up; a dot marks it.
        -- Clicked with nothing held (a player's idea, settings per spell): its
        -- own panel, for its countdown's font and size and its own ticks.
        icon:RegisterForClicks("LeftButtonUp", "RightButtonUp")
        icon:SetScript("OnClick", function(self, button)
            if button == "RightButton" then
                if B:PickMissing(state.bar, self.index) then window:Refresh() end
                return
            end
            if B:Holding() then
                B:Dropped(state.bar)
                return
            end
            local name = ns.BarData(state.bar).spells[self.index]
            if not name then return end
            window.spellPanel = window.spellPanel or SpellPanel(window)
            window.spellPanel:Open(state.bar, name)
            window:Refresh()
        end)
        icon.pick = icon:CreateTexture(nil, "OVERLAY")
        icon.pick:SetSize(6, 6)
        icon.pick:SetPoint("BOTTOMLEFT", 2, 2)
        T:Paint(function(accent) T:Fill(icon.pick, accent) end)
        icon.pick:Hide()
        icon.drop = Bar
        -- The footer names the icon under the mouse; its x says what it does.
        -- One added before the add box turned it away (Weakened Soul) says why it never shows.
        window:Hint(icon, function(self)
            if not self.name then return nil end
            if ns.Spells:SelfDebuffNote(self.spellName or self.name) then
                -- This page's own tick, or where to find one (one line: 93 letters at most).
                if SELF_TICK[ns.BAR_KIND[state.bar]] then
                    return self.name .. " can't show here. Tick \"" .. SELF_TICK[ns.BAR_KIND[state.bar]] .. "\" and drag it off the bar."
                end
                return self.name .. " can't show here. Drag it off, and tick \"" .. SELF_TICK.buff .. "\" on Buffs."
            end
            -- In a joined icon: right-click picks the one shown, faded, while none is up.
            if B:Joined(state.bar, self.index) or B:Joined(state.bar, self.index + 1) then
                return self.name .. ". Click: its own settings. Right-click: the one shown, faded, while none of its icon is up."
                    .. " Drag it onto another icon to swap them."
            end
            return self.name .. ". Click: its own settings. Drag it onto another icon to swap them, or off the bar to take it off."
        end)
        page.icons[i] = icon
        return icon
    end

    -- Options ------------------------------------------------------------------------
    -- Two columns: the sliders with how the icons show under them on the
    -- left, Out of combat, the ticks and which way rows grow on the right.
    -- The Cooldowns and Utility bars' pages are taller, for On cooldown's
    -- tick, how dim and Show the global cooldown (OPTIONS_COOLDOWN, set on
    -- refresh).
    local options = CreateFrame("Frame", nil, page)
    options:SetPoint("TOPLEFT", tray, "BOTTOMLEFT", 0, -12)
    options:SetSize(inner, OPTIONS_COOLDOWN)
    page.optionsArea = options
    -- Room before each slider's track for the longest label, Icons per row.
    local sliderLabel = 108
    local size = T:Slider(options, "Icon size", ns.BAR_LIMITS.size, 2, 280, function(value)
        B:SetOption(state.bar, "size", value)
        window:Refresh()
    end, sliderLabel)
    size:SetPoint("TOPLEFT", 0, -2)
    -- All bars (the Layout page) sizes every bar on top of this one: while it
    -- isn't 100, the note says what size this bar's icons are on screen.
    window:Hint(size, function()
        local scale = ns.Get("barScale")
        if scale == 100 then return "This bar's icon size. All bars on the Layout page sizes every bar together." end
        local shown = ns.IconSize(ns.BarData(state.bar))
        return "This bar's own size. All bars on the Layout page is at " .. scale .. ", so its icons show at "
            .. shown .. (shown <= ns.BAR_LIMITS.size[1] and ", the smallest they go." or ".")
    end)
    local spacing = T:Slider(options, "Spacing", ns.BAR_LIMITS.spacing, 1, 280, function(value)
        B:SetOption(state.bar, "spacing", value)
        window:Refresh()
    end, sliderLabel)
    spacing:SetPoint("TOPLEFT", 0, -30)
    window:Hint(spacing, "The room between this bar's icons.")
    -- More icons than fit across go on another row. (Not the tray's perRow.)
    local across = T:Slider(options, "Icons per row", ns.BAR_LIMITS.perRow, 1, 280, function(value)
        B:SetOption(state.bar, "perRow", value)
        window:Refresh()
    end, sliderLabel)
    across:SetPoint("TOPLEFT", 0, -58)
    window:Hint(across, "How many icons fit across before the next row starts.")
    page.size, page.spacing, page.across = size, spacing, across

    local function Option(label, field, y, note, x)
        local check = T:Check(options, label, function(self)
            B:SetOption(state.bar, field, self:GetChecked())
            window:Refresh()
        end)
        check:SetPoint("TOPLEFT", x or 320, y)
        window:Hint(check, note)
        return check
    end
    -- Buffs only show while they're on you, so their bar offers this instead
    -- of When ready (below), in the same spot under the sliders. Greyed while
    -- Only show missing (under it) is on, which it doesn't go with; its own
    -- choice is kept.
    -- (Each by the page's own bar, or for an extra bar its kind: Buffs 2 as Buffs.)
    local showMissing = Option("Show missing buffs greyed", "showMissing", -85, function()
        local kind = ns.BAR_KIND[state.bar]
        if kind == "buff" and ns.BarData(state.bar).onlyMissing then
            return "Not with Only show missing, which shows only the buffs you're missing."
        end
        if kind ~= "debuff" then return "Buffs missing from you show greyed in their spot, instead of hidden." end
        -- Debuffs: only with an enemy targeted, unless kept greyed (under it).
        if ns.BarData(state.bar).greyedNoTarget then
            return "Debuffs missing from your target show greyed in their spot, instead of hidden, with an enemy targeted or not."
        end
        return "Debuffs missing from your target show greyed in their spot while you have an enemy targeted, instead of hidden."
    end, 0)
    -- The Debuffs bar only, under that, in Only show missing's spot (a
    -- player's idea): its greyed spots kept with no enemy targeted. Greyed
    -- out while missing debuffs greyed is off, which it goes with; its own
    -- choice is kept.
    local keepGreyed = Option("Keep them greyed with no target", "greyedNoTarget", -107, function()
        if not ns.BarData(state.bar).showMissing then
            return "Tick Show missing debuffs greyed first: this keeps those greyed spots with no target."
        end
        return "Missing debuffs stay greyed in their spots with no enemy targeted, instead of hiding."
            .. " Out of combat Fade or Hide still applies. (experimental)"
    end, 0)
    -- The Buffs bar only: each buff only while it's not on you, under the
    -- sliders. Not on the Debuffs bar: your target's debuffs change in a
    -- fight, when the addon can't read them.
    local onlyMissing = Option("Only show missing", "onlyMissing", -107,
        "Shows a buff only while it's not on you. The game hides your buffs from addons in a fight, so changes then show"
            .. " once it ends.", 0)
    local showNames = Option("Show spell names", "showNames", -22, "Each spell's name under its icon.")
    local showTimer = Option("Show countdown numbers", "showTimer", -44, "The numbers counting down on this bar's icons.")
    -- The cooldown bars only: an icon shows the time left on the buff its
    -- spell put on you or its debuff on your target, as Blizzard's does.
    local showAuras = Option("Show buff and debuff time", "showAuras", -107,
        "While the buff a spell put on you, or its debuff on your target (like Shadow Word: Pain), is up,"
            .. " its icon shows the time left with a gold edge.")
    -- The cooldown bars only, under that: Swap with my form (a player's
    -- idea), a list of icons for each form you take, in the row On
    -- cooldown's tick makes on the left. Only for a character who knows a
    -- form (not a mage, hunter, warlock or paladin, nor a druid before Bear
    -- Form).
    -- Its words follow the class (ns.SwapWords): "Swap when in Stealth" on a
    -- rogue, "Swap with my stance" on a warrior.
    local swapForm = Option("Swap with my form", "swapForm", -129, function()
        local words = ns.SwapWords()
        if words.one then
            return words.one .. " gets its own icons on this bar, swapped as you go in and out of it."
        end
        return "Each " .. words.what .. " gets its own icons on this bar, swapped as you change."
    end)
    -- And with it ticked, under it, Editing: whose icons the tray and the
    -- bar show, to set up another form's without changing form. Your form's
    -- unless you pick one; leaving the page, closing the window or a fight
    -- goes back to it. The arrows step through Normal and the forms you know.
    local editing = CreateFrame("Frame", nil, options, "BackdropTemplate")
    editing:SetSize(156, 20)
    editing:SetPoint("TOPLEFT", 420, -151)
    T:Flat(editing, T.FIELD, T.CONTROL_BORDER)
    editing.label = T:Text(options, "GameFontHighlight")
    editing.label:SetPoint("TOPLEFT", 320, -155)
    editing.label:SetText("Editing")
    local function EditingNote()
        local words = ns.SwapWords()
        local follow = words.one or ("your " .. words.what)
        if InCombatLockdown() then return "Not in a fight: your bars follow " .. follow .. " until it ends." end
        if words.one then
            return "Pick " .. words.one .. " to set up its icons here without using it. Normal is for the rest of the time."
        end
        return "Pick a " .. words.what .. " to set up its icons here without changing " .. words.what
            .. ". Normal is for no " .. words.what .. "."
    end
    -- In a fight the arrows say why they do nothing (they aren't greyed:
    -- nothing would ungrey them as it ends).
    local function StepForm(by)
        if InCombatLockdown() then
            window:Say(EditingNote())
            return window:Refresh()
        end
        local choices, now, at = { 0 }, ns.ShownForm(state.bar), 1
        for _, known in ipairs(ns.KnownForms()) do choices[#choices + 1] = known.form end
        for i, form in ipairs(choices) do
            if form == now then at = i end
        end
        ns.SetEditingForm(choices[(at - 1 + by) % #choices + 1])
        B:FormChanged()
        window:Refresh()
    end
    editing.back = T:Square(editing, "<")
    editing.back:SetPoint("LEFT", 1, 0)
    editing.back:SetScript("OnClick", function() StepForm(-1) end)
    editing.next = T:Square(editing, ">")
    editing.next:SetPoint("RIGHT", -1, 0)
    editing.next:SetScript("OnClick", function() StepForm(1) end)
    -- The form's name between them, which says what the arrows do too.
    editing.show = CreateFrame("Button", nil, editing)
    editing.show:SetSize(156 - 2 * 18 - 8, 18)
    editing.show:SetPoint("CENTER")
    editing.name = T:Text(editing.show, "GameFontHighlightSmall")
    editing.name:SetPoint("CENTER")
    editing.name:SetJustifyH("CENTER")
    editing.show:EnableMouse(true)
    for _, part in ipairs({ editing.back, editing.show, editing.next }) do window:Hint(part, EditingNote) end
    -- A form picked there lets go as you leave the page or pick another
    -- bar: the bars follow your form again.
    local function FollowAgain()
        if ns.EditingForm() == nil then return end
        ns.SetEditingForm(nil)
        B:FormChanged()
    end
    page:HookScript("OnHide", FollowAgain)
    -- The Buffs and Debuffs bars, in the same spot, each its own (its label
    -- set on refresh: SELF_LABEL).
    local showSelf = Option(SELF_LABEL.buff, "selfDebuffs", -107, function()
        if ns.BAR_KIND[state.bar] == "debuff" then
            return "Debuffs you put on yourself, like Weakened Soul from your shield or Recently Bandaged, at the end of this bar."
                .. " Not with missing debuffs greyed."
        end
        return "Debuffs you put on yourself, like Weakened Soul from your shield or Recently Bandaged, after your buffs."
            .. " Not with missing buffs greyed or Only show missing."
    end)

    -- A label and joined buttons for a choice, with the footer explaining it:
    -- note is the same for every button, or one for each choice by its key.
    -- fit: each button as wide as its label needs.
    local function Pills(label, x, y, width, keys, names, field, note, fit)
        local text = T:Text(options, "GameFontHighlight")
        text:SetPoint("TOPLEFT", x, y - 4)
        text:SetText(label)
        local choices = { fit = fit }
        for _, key in ipairs(keys) do choices[#choices + 1] = { key = key, label = names[key] } end
        local pills
        pills = T:Segmented(options, choices, width, function(key)
            -- A layout decides which way its bars grow.
            if pills.held then
                window:Say("Your layout sets this. Change it on the Layout page.")
            else
                B:SetOption(state.bar, field, key)
            end
            window:Refresh()
        end)
        pills:SetPoint("TOPLEFT", x + 100, y)
        for _, button in ipairs(pills.buttons) do
            local own = type(note) == "table" and note[button.key] or note
            window:Hint(button, function()
                if pills.held then return "Your layout sets this. Change it on the Layout page." end
                if type(own) == "function" then return own() end
                return own
            end)
        end
        pills.label = text
        return pills
    end
    -- The same choice on both When ready and On cooldown: Hide leaves the bar
    -- with nothing showing, Dim every icon dimmed, so nothing stands out.
    -- Each one's note says so while the other is on it too.
    local function Both(other, choice)
        if ns.BarData(state.bar)[other] ~= choice then return "" end
        return choice == "hide" and " Both are on Hide, so this bar shows nothing." or " Both are on Dim, so every icon is dimmed."
    end
    -- When ready: each icon in full, dimmed or hidden while its spell is
    -- ready, under the sliders.
    local whenReady = Pills("When ready", 0, -85, 156, ns.WHEN_READY, ns.WHEN_READY_NAMES, "whenReady", {
        show = "Each icon shows in full while it's ready.",
        dim = function() return "Each icon dims while it's ready, so the ones cooling down stand out." .. Both("onCooldown", "dim") end,
        hide = function() return "Each icon hides while it's ready, so only the ones cooling down show." .. Both("onCooldown", "hide") end,
    })
    -- The label and its choices as one part, for the tour to outline: the
    -- label ends above the buttons, so a box hung from it sat too high.
    local readyPart = CreateFrame("Frame", nil, options)
    readyPart:SetPoint("TOPLEFT", 0, -85)
    readyPart:SetSize(100 + 156, 20)
    whenReady.part = readyPart
    -- On cooldown, under it: the other way round, each icon in full, dimmed
    -- or hidden while its spell cools down (a player's idea).
    local onCooldown = Pills("On cooldown", 0, -107, 156, ns.WHEN_READY, ns.WHEN_READY_NAMES, "onCooldown", {
        show = "Every icon shows in full while it cools down.",
        dim = function()
            return "Each icon dims while it cools down, so the ones ready stand out." .. Both("whenReady", "dim")
        end,
        hide = function()
            return "Each icon hides while it cools down, so only the ready ones show." .. Both("whenReady", "hide")
        end,
    })
    -- And under that, an icon you can't cast now (blue, grey or red: no
    -- mana, rage or energy, out of range, or not usable yet) dimmed too,
    -- never more than dimmed: one hidden stays hidden. Off unless ticked.
    local dimUnusable = Option("Dim when you can't cast it", "dimUnusable", -129,
        "Dims an icon while you can't cast it: not enough mana, rage or energy, out of range, or not usable yet.", 0)
    -- And under that, how much of a dimmed icon shows (each Dim and the
    -- tick), each bar its own, 40% as it always was. Greyed while nothing
    -- on the bar dims.
    local dimOpacity = T:Slider(options, "Dimmed icons", ns.BAR_LIMITS.dimOpacity, 5, 280, function(value)
        B:SetOption(state.bar, "dimOpacity", value)
    end, sliderLabel)
    dimOpacity:SetPoint("TOPLEFT", 0, -151)
    -- Its value as a share, "40%", with room for it up to the track.
    dimOpacity.value:SetWidth(36)
    local setDim = dimOpacity.Set
    function dimOpacity:Set(value)
        setDim(self, value)
        self.value:SetText(value .. "%")
    end
    local function Dims(data)
        return data.whenReady == "dim" or data.onCooldown == "dim" or data.dimUnusable == true
    end
    window:Hint(dimOpacity, function()
        if not Dims(ns.BarData(state.bar)) then
            return "Nothing on this bar dims yet. Pick Dim on When ready or On cooldown, or tick Dim when you can't cast it."
        end
        return "How much of a dimmed icon shows: lower is fainter. Used by Dim above and by Dim when you can't cast it."
    end)
    -- On cooldown, its tick and Dimmed icons as one part, for the page's walkthrough.
    local cooldownPart = CreateFrame("Frame", nil, options)
    cooldownPart:SetPoint("TOPLEFT", 0, -107)
    cooldownPart:SetSize(280, 151 - 107 + 20)
    onCooldown.part = cooldownPart
    -- And under that, the cooldown bars only: the global cooldown's swipe on
    -- the icons after each cast, each bar its own, off unless ticked.
    local showGCD = Option("Show the global cooldown (experimental)", "showGCD", -173,
        "After each cast, this bar's icons show the global cooldown's swipe, like your action bars."
            .. " An icon cooling down keeps showing its own cooldown.", 0)
    -- Out of combat: show, fade or hide. The footer explains when bars come back.
    local outOfCombat = Pills("Out of combat", 320, 0, 156, ns.OUT_OF_COMBAT, ns.OUT_OF_COMBAT_NAMES, "outOfCombat",
        "Out of combat. Bars come back in full in combat, with an enemy targeted, while unlocked, and in Edit Mode.")
    local grow = Pills("Grow", 320, -63, 156, ns.GROW, ns.GROW_NAMES, "grow",
        "Which way a row grows as icons come and go: from its centre, or from its right or left edge.")
    local wrap = Pills("New rows", 320, -85, 110, ns.WRAP, ns.WRAP_NAMES, "wrap",
        "Where the next row goes when there are more icons than fit across.")
    -- The Debuffs bar's tick count (Count ticks, a player's idea: where on
    -- the icon, from 1 like stacks or from 0, its size and colour), in two
    -- rows under the rest while any of the bar's debuffs counts.
    local AT_NOTE = "Where the tick count sits on each icon."
    local tickAt = Pills("Tick count", 0, -129, 500, ns.TICK_AT_KEYS, ns.TICK_AT_NAMES, "tickAt", {
        TOPLEFT = AT_NOTE, TOP = AT_NOTE, TOPRIGHT = AT_NOTE, BOTTOMLEFT = AT_NOTE, BOTTOM = AT_NOTE,
        BOTTOMRIGHT = AT_NOTE .. " Bottom right is where stacks show, so the two can overlap.",
        CENTER = AT_NOTE .. " The centre is the countdown's: untick Show countdown numbers to keep it clear.",
    }, true)
    local tickFrom = T:Check(options, "Start at 1", function(self)
        B:SetOption(state.bar, "tickFrom", self:GetChecked() and 1 or 0)
        window:Refresh()
    end)
    -- Under the spots, after the size and colours (the seven spots take the row).
    tickFrom:SetPoint("TOPLEFT", 398, -153)
    window:Hint(tickFrom, "1 as the debuff lands, 2 after its first tick, like stacks. Unticked, it counts the ticks so far, from 0.")
    -- And beside it, On the edge (a player's ask): the count centred on the
    -- icon's border at its spot, half outside, like durations on nameplates.
    local tickEdge = T:Check(options, "On the edge", function(self)
        B:SetOption(state.bar, "tickEdge", self:GetChecked())
        window:Refresh()
    end)
    tickEdge:SetPoint("TOPLEFT", 492, -153)
    window:Hint(tickEdge, "Centres the count on the icon's edge at its spot, half outside, so it covers less of the icon."
        .. " Not for the centre.")
    -- Its size, then its colour: one swatch that opens the colours, so the
    -- slider has the room the row of swatches had.
    local tickSize = T:Slider(options, "Size", ns.TICK_SIZE, 10, 260, function(value)
        B:SetOption(state.bar, "tickSize", value)
    end, 44)
    tickSize:SetPoint("TOPLEFT", 0, -151)
    -- Its value as a share, "100%", with room for it up to the track.
    tickSize.value:SetWidth(36)
    local setTickSize = tickSize.Set
    function tickSize:Set(value)
        setTickSize(self, value)
        self.value:SetText(value .. "%")
    end
    window:Hint(tickSize, "How big the tick count is: 100% follows the icon's size.")
    local tickColour = T:Text(options, "GameFontHighlight")
    tickColour:SetPoint("TOPLEFT", 276, -155)
    tickColour:SetText("Colour")
    local tickChoice = TickColour(window, options, state)
    tickChoice:SetPoint("TOPLEFT", 326, -151)
    -- Whether any of the page's Debuffs bar's debuffs (Debuffs 2's on its
    -- own page) counts its ticks now: one of yours (not another class's in a
    -- shared profile, whose tick you can't see).
    local function Counting()
        local key = state.bar
        local counts = ns.CountTicks(key)
        for _, name in ipairs(ns.BarData(key).spells) do
            if counts[name] and ns.Spells:ForMe(name, key) and B:TickPace(name) then return true end
        end
        return false
    end
    page.options = { whenReady = whenReady, onCooldown = onCooldown, dimUnusable = dimUnusable, dimOpacity = dimOpacity,
        showGCD = showGCD, showMissing = showMissing, keepGreyed = keepGreyed,
        onlyMissing = onlyMissing, showNames = showNames, showTimer = showTimer, showAuras = showAuras, swapForm = swapForm,
        editing = editing,
        showSelf = showSelf, outOfCombat = outOfCombat, grow = grow, wrap = wrap,
        tickAt = tickAt, tickFrom = tickFrom, tickEdge = tickEdge, tickSize = tickSize, tickColour = tickColour,
        tickChoice = tickChoice, tickSwatches = tickChoice.swatches }

    -- The spell list -------------------------------------------------------------------
    local listPanel = CreateFrame("Frame", nil, page, "BackdropTemplate")
    listPanel:SetPoint("TOPLEFT", options, "BOTTOMLEFT", 0, -10)
    listPanel:SetPoint("BOTTOMRIGHT", -16, 12)
    T:Box(listPanel)
    -- (Narrow enough for Ticked only beside Show items and Show all ranks.)
    local search = T:Input(listPanel, "Search by name or spell ID", 224)
    search:SetPoint("TOPLEFT", 8, -8)
    search:SetScript("OnTextChanged", function(self)
        state.search = (self:GetText() or ""):lower():match("^%s*(.-)%s*$")
        window:Refresh()
    end)
    -- With a debuff on you typed in it (Weakened Soul), hovering it keeps that tip.
    window:Hint(search, function()
        return ns.Spells:SelfDebuffMatch(state.search)
            or "Find a spell by name or ID. Three letters or more also finds spells outside your spellbook."
    end)
    page.search = search
    -- Trinkets and bag items only join the list when asked.
    local showItems = T:Check(listPanel, "Show items", function(self)
        ns.Set("listItems", self:GetChecked())
        window:Refresh()
    end)
    showItems:SetPoint("LEFT", search, "RIGHT", 14, 0)
    window:Hint(showItems, "Trinkets and bag items with a use, listed to put on the bar. Healthstones and potions are one icon each, whatever rank you carry.")
    -- Every rank you know as its own row, for casting a lower rank on purpose.
    local showRanks = T:Check(listPanel, "Show all ranks", function(self)
        ns.Set("listRanks", self:GetChecked())
        window:Refresh()
    end)
    showRanks:SetPoint("LEFT", showItems, "RIGHT", 14, 0)
    window:Hint(showRanks, "Every rank you know as its own row, for casting a lower rank on purpose.")
    -- Only the spells on this bar, so their own ticks are quick to reach (a
    -- player's idea): after the two ticks, or beside the search where an
    -- aura bar has neither (Refresh).
    local ticked = T:Check(listPanel, "Ticked only", function(self)
        ns.Set("listTicked", self:GetChecked())
        window:Refresh()
    end)
    ticked:SetPoint("LEFT", showRanks, "RIGHT", 14, 0)
    window:Hint(ticked, "Lists only the spells on this bar, with their own ticks. (experimental)")
    page.showItems, page.showRanks, page.ticked = showItems, showRanks, ticked
    -- How the list shows ranks, on a line of its own under the search: too
    -- long to fit beside it with the two ticks.
    local ranks = T:Text(listPanel, "GameFontHighlightSmall", T.MUTED)
    ranks:SetPoint("TOPLEFT", 10, -34)
    ranks:SetWidth(inner - 20)
    page.ranks = ranks

    local listWidth = inner - 30
    -- On this client a scroll area pinned while the page is still hidden is
    -- never placed, and draws nothing; one placed by a single corner and a
    -- size isn't either. So it's pinned by two corners, again a moment after
    -- the page shows, once everything around it has been laid out.
    local scroll = T:Scroll(listPanel, listWidth)
    local function Pin()
        scroll:ClearAllPoints()
        scroll:SetPoint("TOPLEFT", listPanel, "TOPLEFT", 8, -50)
        scroll:SetPoint("BOTTOMRIGHT", listPanel, "BOTTOMRIGHT", -16, 6)
        scroll:ScrollTo(scroll:GetVerticalScroll() or 0)
    end
    Pin()
    page:HookScript("OnShow", function() C_Timer.After(0, Pin) end)
    window:Hint(scroll.thumb, ns.SCROLL_NOTE)
    page.list, page.listPanel = scroll, listPanel
    local rows = {}
    page.rows = rows

    -- Adds a spell that isn't in your spellbook, by name or ID, to this bar.
    local function AddOther(text)
        local _, message = B:Add(state.bar, text)
        window:Say(message)
    end

    local function Ticked(row, checked)
        local bar = state.bar
        if row.other then
            if checked then AddOther(row.other) end
        else
            local ok
            if ns.AURA_BARS[bar] then
                ok = B:SetAura(bar, row.spell, checked)
            else
                ok = B:Assign(row.spell, checked and bar or nil)
            end
            if not ok then window:Say(Full(bar)) end
        end
        window:Refresh()
    end

    local function Row(i)
        local row = rows[i]
        if row then return row end
        row = CreateFrame("Frame", nil, scroll.content)
        row:SetSize(listWidth, ROW)
        row.check = T:Check(row, nil, function(self) Ticked(row, self:GetChecked()) end)
        row.check:SetPoint("LEFT", 4, 0)
        -- The whole row is the tick's, as a tick's label is elsewhere: its
        -- spell's icon, name and rank click it too, and say what it does.
        row.check:SetHitRectInsets(-4, -(listWidth - 20), -(ROW - 16) / 2, -(ROW - 16) / 2)
        -- What ticking or unticking this row does, for the spell it holds now.
        -- A healthstone or potion family says how it works as it's put on,
        -- and one you carry none of (an item too) that it shows once you do.
        window:Hint(row.check, function()
            local bar, name = ns.BAR_NAMES[state.bar], row.label or ""
            if row.other and row.pinned then return "Add " .. name .. " to " .. bar .. " as its own icon, for this spell ID only." end
            if row.other then return "Add " .. name .. " to " .. bar .. ", by name: it isn't in your spellbook." end
            if row.check:GetChecked() then return "Take " .. name .. " off " .. bar .. "." end
            local entry = row.spell and ns.Spells:Find(row.spell)
            local family = (entry and entry.kind == "family"
                and " One icon for the best one you carry, switching as your bags change." or "")
                .. (entry and entry.kind == "shards" and " It counts how many you carry." or "")
                .. (entry and entry.hand and " It lights while that hand has an oil, stone, poison or imbue on, and shows which."
                    .. UNTESTED or "")
                .. (row.spell and B:CarryNote(row.spell) or "")
            local on = not ns.AURA_BARS[state.bar] and row.spell and B:Find(row.spell)
            if on and on ~= state.bar then return "Move " .. name .. " here from " .. ns.BAR_NAMES[on] .. "." .. family end
            return "Put " .. name .. " on " .. bar .. "." .. family
        end)
        row.icon = row:CreateTexture(nil, "ARTWORK")
        row.icon:SetSize(16, 16)
        ns.Style:Zoom(row.icon)
        row.name = T:Text(row, "GameFontHighlight")
        row.name:SetPoint("LEFT", row.icon, "RIGHT", 6, 0)
        row.name:SetWordWrap(false)
        row.rank = T:Text(row, "GameFontHighlightSmall", T.MUTED)
        row.rank:SetPoint("LEFT", row.name, "RIGHT", 5, 0)
        -- Which other bar has the spell, right after its name and rank, so
        -- it can't be read as another row's.
        row.where = T:Text(row, "GameFontHighlightSmall", T.MUTED)
        row.where:SetPoint("LEFT", row.name, "RIGHT", 10, 0)
        row.header = T:Text(row, "GameFontHighlightSmall", T.MUTED)
        row.header:SetPoint("BOTTOMLEFT", 4, 3)
        -- On the Buffs and Debuffs pages, a ticked aura's own tick at the row's
        -- end (a player's idea): its icon glows while it's missing. Over the row's
        -- tick, whose click covers the whole row. A missing buff only shows
        -- (and glows) in its own spot, so it's greyed, saying why, until
        -- Show missing buffs greyed or Only show missing is ticked (the user:
        -- like Keep them greyed with no target); its own choice is kept.
        row.glow = T:Check(row, "Glow when missing", function(self)
            if row.spell then B:SetGlowMissing(state.bar, row.spell, self:GetChecked()) end
            window:Refresh()
        end)
        row.glow:SetWidth(18 + (row.glow.text:GetStringWidth() or 0))
        row.glow:SetPoint("RIGHT", -8, 0)
        row.glow:SetFrameLevel(row.check:GetFrameLevel() + 2)
        window:Hint(row.glow, function() return GlowNote(state.bar, row.spell) end)
        row.glow:Hide()
        -- On the Buffs page, a ticked buff's own Only when missing (a
        -- player's ask), just left of Glow when missing: its icon shows only
        -- while it's missing from you, in a spot of its own, as Only show
        -- missing does for every buff. Greyed, saying why, while Only show
        -- missing is on; its own choice is kept.
        row.only = T:Check(row, "Only when missing", function(self)
            if row.spell then B:SetOnlyWhenMissing(state.bar, row.spell, self:GetChecked()) end
            window:Refresh()
        end)
        row.only:SetWidth(18 + (row.only.text:GetStringWidth() or 0))
        row.only:SetPoint("RIGHT", -8, 0)
        row.only:SetFrameLevel(row.check:GetFrameLevel() + 2)
        window:Hint(row.only, function() return OnlyNote(state.bar) end)
        row.only:Hide()
        -- On the Debuffs page, a ticked debuff that ticks gets one there too
        -- (a player's idea: Bane of Agony's ticks): its icon counts them.
        row.ticks = T:Check(row, "Count ticks", function(self)
            if row.spell then B:SetCountTicks(state.bar, row.spell, self:GetChecked()) end
            window:Refresh()
        end)
        row.ticks:SetWidth(18 + (row.ticks.text:GetStringWidth() or 0))
        row.ticks:SetPoint("RIGHT", -8, 0)
        row.ticks:SetFrameLevel(row.check:GetFrameLevel() + 2)
        window:Hint(row.ticks, function() return TicksNote(state.bar, row.spell, row.label) end)
        row.ticks:Hide()
        rows[i] = row
        return row
    end

    -- Refresh ---------------------------------------------------------------------------
    local y, n

    local function Header(text)
        n = n + 1
        local row = Row(n)
        row:SetHeight(HEADER_ROW)
        row:SetPoint("TOPLEFT", 0, -y)
        row.header:SetText(text:upper())
        row.header:Show()
        row.spell, row.other, row.pinned = nil, nil, nil
        for _, part in ipairs({ row.check, row.icon, row.name, row.rank, row.where, row.glow, row.ticks, row.only }) do part:Hide() end
        row:Show()
        y = y + HEADER_ROW
    end

    local function Entry(icon, name, rankText, indent)
        n = n + 1
        local row = Row(n)
        row:SetHeight(ROW)
        row:SetPoint("TOPLEFT", 0, -y)
        row.header:Hide()
        row.icon:ClearAllPoints()
        row.icon:SetPoint("LEFT", indent and 44 or 26, 0)
        row.icon:SetTexture(icon or 134400)
        row.name:SetText(name)
        row.rank:SetText(rankText or "")
        row.where:SetText("")
        row.where:ClearAllPoints()
        row.where:SetPoint("LEFT", (rankText or "") ~= "" and row.rank or row.name, "RIGHT", 10, 0)
        for _, part in ipairs({ row.check, row.icon, row.name, row.rank, row.where }) do part:Show() end
        row.glow:Hide() -- a ticked buff's only (Spell)
        row.ticks:Hide() -- and a ticked debuff's
        row.only:Hide() -- and a ticked buff's
        row:Show()
        y = y + ROW
        return row
    end

    local function Spell(entry, indent, rankText)
        local row = Entry(entry.icon, indent and entry.rankText or entry.shown or entry.name, rankText, indent)
        row.spell, row.other, row.label, row.pinned = entry.key, nil, entry.name, nil
        if ns.AURA_BARS[state.bar] then
            local on = B:HasAura(state.bar, entry.key)
            row.check:SetChecked(on)
            -- Glow when missing, for a buff or debuff on the bar.
            row.glow:SetShown(on)
            row.glow:SetChecked(B:GlowsMissing(state.bar, entry.key))
            if on then row.glow:SetUsable(B:MissingSpot(state.bar, entry.key)) end
            -- Only when missing, on the Buffs page for a buff on the bar,
            -- just left of Glow when missing; greyed while Only show missing
            -- does it for every buff.
            local kind = ns.BAR_KIND[state.bar] -- (an extra bar goes by its kind)
            local only = kind == "buff" and on
            row.only:SetShown(only)
            row.only:SetChecked(B:OnlyWhenMissing(state.bar, entry.key))
            if only then
                row.only:SetUsable(not ns.BarData(state.bar).onlyMissing)
                row.only:ClearAllPoints()
                row.only:SetPoint("RIGHT", row.glow, "LEFT", -14, 0)
            end
            -- Count ticks, on the Debuffs page for a debuff on the bar that
            -- ticks, just left of Glow when missing; greyed while its icon
            -- can't count (its hint says why), unless it's ticked, so it can
            -- be unticked.
            local ticks = kind == "debuff" and on and B:TickPace(entry.key) ~= nil
            row.ticks:SetShown(ticks)
            row.ticks:SetChecked(B:CountsTicks(state.bar, entry.key))
            if ticks then
                row.ticks:SetUsable(row.ticks:GetChecked() or not B:TickClash(state.bar, entry.key))
                row.ticks:ClearAllPoints()
                row.ticks:SetPoint("RIGHT", row.glow, "LEFT", -14, 0)
            end
        else
            local on = B:Find(entry.key)
            row.check:SetChecked(on == state.bar)
            -- A spell sits on one cooldown bar at a time; ticking it here moves it.
            if on and on ~= state.bar then row.where:SetText("on " .. ns.BAR_NAMES[on]) end
        end
    end

    -- What this bar can hold: procs have no cooldown of their own and are
    -- buffs on you, items put no aura on anyone, and a fixed rank adds
    -- nothing to an aura bar, which already counts every rank. A warlock's
    -- stones only light on your weapon, so only on the Buffs bar.
    -- (With Ticked only, an item on the bar is listed with Show items off.)
    local function Fits(entry, onlyTicked)
        local item, kind = ns.Spells:IsItem(entry), ns.BAR_KIND[state.bar]
        if kind == "buff" then return not item and entry.kind ~= "rank" end
        if entry.kind == "enchant" then return false end
        if kind == "debuff" then return not item and entry.kind ~= "rank" and entry.kind ~= "proc" end
        if item then return ns.Get("listItems") or onlyTicked end
        return entry.kind ~= "proc"
    end

    -- Whether a spell is on this page's bar: its row's tick.
    local function OnBar(key)
        if ns.AURA_BARS[state.bar] then return B:HasAura(state.bar, key) == true end
        return B:Find(key) == state.bar
    end

    -- Ticked only: an entry and the lower ranks under it that are on the
    -- bar, or nil when neither is. Otherwise all of them.
    local function Listed(entry, lower, onlyTicked)
        if not onlyTicked then return lower end
        local ranks = {}
        for _, fixed in ipairs(lower) do
            if OnBar(fixed.key) then ranks[#ranks + 1] = fixed end
        end
        if OnBar(entry.key) or #ranks > 0 then return ranks end
        return nil
    end

    local function RefreshList()
        y, n = 0, 0
        local list = ns.Spells:Fresh()
        local text, listRanks = state.search, ns.Get("listRanks") and not ns.AURA_BARS[state.bar]
        local onlyTicked = ns.Get("listTicked") == true
        local id = tonumber(text)
        local line
        local known = {}
        for _, entry in ipairs(list) do
            -- Another character's spell added to a shared profile, or a
            -- passive with nothing to track here, stays off your list, as it
            -- stays off your bar (unticking it here would take it off
            -- theirs). Nor is it offered under Other spells, but for an ID
            -- that isn't passive given for a passive's name (the mage's
            -- Regeneration, where a troll's is saved). Known by name and by
            -- key: a spell pinned to one ID is known by both.
            if not ns.Spells:PassiveNote(entry.key, state.bar) then known[entry.name], known[entry.key] = true, true end
            -- On the Buffs page another class's spell added by name shows
            -- only while it's on this bar (a priest's Fortitude you track):
            -- not one another character added to another bar (a hunter's
            -- Call Pet in a shared profile).
            local elsewhere = ns.BAR_KIND[state.bar] == "buff" and entry.added and ns.Spells:AnotherClass(entry.key)
                and not B:HasAura(state.bar, entry.key)
            local lower = listRanks and entry.lower or {}
            local ranks = Fits(entry, onlyTicked) and not elsewhere and ns.Spells:ForMe(entry.key, state.bar)
                and (text == "" or entry.name:lower():find(text, 1, true) or (id and entry.spellID == id))
                and Listed(entry, lower, onlyTicked)
            if ranks then
                if text == "" and entry.line ~= line then
                    line = entry.line
                    Header(line or "")
                end
                Spell(entry, false, #lower > 0 and ("Highest (Rank " .. entry.rank .. ")") or entry.rankText)
                -- Lower ranks under the spell, each fixed to that rank.
                for _, fixed in ipairs(ranks) do Spell(fixed, true, "") end
            end
        end
        -- Searching also finds spells outside your spellbook, by name or ID.
        -- Not a passive this bar can't track (Underwater Breathing), which
        -- would only be turned away, nor one that wouldn't show here for you
        -- (another class's spell, a buff's ID on the Cooldowns page), which
        -- is turned away too. On the Buffs and Debuffs bars, an ID for
        -- another spell of a name already in your lists (the second
        -- Energized) is offered too: it goes on pinned to that ID. Not with
        -- Ticked only: none of them is on the bar.
        if not onlyTicked and (#text >= 3 or id) then
            local others = {}
            if id then
                local name = C_Spell.GetSpellName and C_Spell.GetSpellName(id)
                local pinned = type(name) == "string" and ns.Spells:Pin(id, state.bar)
                if type(name) == "string" and not known[pinned or name] and not ns.Spells:AddNote(text, state.bar)
                    and B:WouldShow(state.bar, text) then
                    local label = name .. " (ID " .. id .. ")"
                    others[1] = { name = pinned and label or name, label = label, lookup = text,
                        icon = C_Spell.GetSpellTexture(id), pinned = pinned or nil }
                end
            else
                -- Eight at most, from more names, as some may not show here.
                for _, found in ipairs(ns.Spells:Suggest(text, 24)) do
                    if #others < 8 and not known[found.name] and not ns.Spells:AddNote(found.name, state.bar)
                        and B:WouldShow(state.bar, found.name) then
                        others[#others + 1] = { name = found.name, label = found.name, lookup = found.name,
                            icon = found.icon or ((found.iconID or found.spellID) and C_Spell.GetSpellTexture(found.iconID or found.spellID)) }
                    end
                end
            end
            if #others > 0 then
                Header("Other spells")
                for _, other in ipairs(others) do
                    local row = Entry(other.icon, other.label, "")
                    row.spell, row.other, row.label, row.pinned = nil, other.lookup, other.name, other.pinned
                    row.check:SetChecked(false)
                end
            end
        end
        -- Typing a debuff on you (Weakened Soul): the footer says where it's
        -- shown, on every refresh, as a message lasts until the next one.
        local selfNote = ns.Spells:SelfDebuffMatch(text)
        if selfNote then window:Say(selfNote) end
        if n == 0 then
            Header(selfNote and "A debuff on you: see below" or text ~= "" and "No matches"
                or onlyTicked and "Nothing on this bar yet" or "Nothing to list")
        end
        for i = n + 1, #rows do rows[i]:Hide() end
        scroll.content:SetHeight(math.max(1, y))
        scroll:ScrollTo(scroll:GetVerticalScroll() or 0)
    end

    local function RefreshTray()
        local aura = ns.AURA_BARS[state.bar] ~= nil
        -- Your own entries: another class's, in a shared profile, stay hidden.
        local names, places = B:Mine(state.bar)
        -- Closer on the Cooldowns and Utility bars (TIGHT), with no join buttons.
        local cols, gap = aura and perRow or perRowTight, aura and GAP or TIGHT
        for n, key in ipairs(names) do
            local icon, i = TrayIcon(n), places[n]
            icon:ClearAllPoints()
            icon:SetPoint("TOPLEFT", 8 + ((n - 1) % cols) * (ICON + gap), -8 - math.floor((n - 1) / cols) * (ICON + gap))
            local entry = ns.Spells:Find(key)
            -- Named as in the list (two of one name read "Name (ID n)"); the
            -- self-debuff check below goes by the spell's own name.
            icon.index, icon.name, icon.spellName = i, entry and (entry.shown or entry.name) or key, entry and entry.name or key
            -- A spell you haven't learned yet shows greyed, in its own icon.
            icon.texture:SetTexture(ns.Spells:Icon(key))
            icon.texture:SetDesaturated(entry == nil)
            -- An entry joins the one just before it, so only to one you can see.
            local follows = aura and n > 1 and places[n - 1] == i - 1
            local joined = follows and B:Joined(state.bar, i)
            icon.link:SetShown(follows)
            icon.link:SetLabel(joined and "-" or "+")
            local colour = joined and T:Accent() or T.MUTED
            icon.link.label:SetTextColor(colour[1], colour[2], colour[3])
            -- An icon starting a new row has its partner at the end of the row above.
            icon.bridge:SetShown(joined and (n - 1) % cols ~= 0)
            icon.pick:SetShown(aura and B:Picked(state.bar, i) and (B:Joined(state.bar, i) or B:Joined(state.bar, i + 1)))
            icon:Show()
        end
        -- Icons not in use go, with their join button and line: those sit on
        -- the tray, so hiding the icon alone would leave them behind.
        for n = #names + 1, #page.icons do
            local icon = page.icons[n]
            icon:Hide()
            icon.link:Hide()
            icon.bridge:Hide()
        end
        local lines = math.max(1, math.ceil(#names / cols))
        local trayHeight = 16 + lines * ICON + (lines - 1) * gap
        tray:SetHeight(trayHeight)
        empty:SetShown(#names == 0)
        empty:SetText(EMPTY[ns.BAR_KIND[state.bar]])
    end

    local function Refresh(key)
        if key ~= state.bar then
            state.bar, state.armed = key, nil
            scroll:ScrollTo(0)
            FollowAgain()
        end
        -- A bar swapping with your form shows the form you're in now, even
        -- with your bars off (when nothing hears it change).
        if ns.Swaps(key) and ns.FollowForm() then B:FormChanged() end
        local data = ns.BarData(key)
        local spells = B:Mine(key)
        local name = ns.BAR_NAMES[key]
        title:SetText(name:upper())
        local second = ns.EXTRA_OF[key] == nil
        back:SetShown(second)
        title:ClearAllPoints()
        if second then title:SetPoint("LEFT", back, "RIGHT", 6, 0) else title:SetPoint("TOPLEFT", 16, -16) end
        local on = B:Enabled()
        local taken = on and ns.Layout ~= nil and ns.Layout:IsHidden(key)
        off:SetShown(not on)
        turnOn:SetShown(not on)
        out:SetShown(taken)
        putBack:SetShown(taken)
        count:SetShown(on and not taken)
        local aura = ns.AURA_BARS[key]
        local word = aura and aura.word or "icon"
        count:SetText(#spells == 0 and "Empty" or (#spells .. " " .. word .. (#spells == 1 and "" or "s")
            .. ", drag to reorder"))
        clear:SetLabel(state.armed == key and "Click again to clear" or ("Clear " .. name))
        -- Also while only buffs that show there for no one are left, so they
        -- can go (B:Leftovers).
        clear:SetShown(#spells > 0 or state.armed == key or #B:Leftovers(key) > 0)
        -- Extra bars: left of Clear (in its place while it's hidden), + Another
        -- bar once the bar has spells, greyed while one can't be added (it
        -- says why), or the way to the extra bar's page once it's there; on
        -- that page, Remove bar. (Where it shows, the ?'s note stays away:
        -- Window.lua.)
        local extra = ns.EXTRA_OF[key]
        another:SetShown(#spells > 0 or not extra or ns.HasBar(extra))
        another:SetLabel(not extra and "Remove bar" or ns.HasBar(extra) and (ns.BAR_NAMES[extra] .. " >") or "+ Another bar")
        another:SetAlpha((not extra or ns.HasBar(extra) or ns.CanAddBar(key)) and 1 or .45)
        another:ClearAllPoints()
        if clear:IsShown() then another:SetPoint("RIGHT", clear, "LEFT", -6, 0) else another:SetPoint("TOPRIGHT", -16, -12) end
        RefreshTray()
        size:Set(data.size)
        spacing:Set(data.spacing)
        across:Set(data.perRow)
        -- Packed buffs are laid out by the game in one row.
        local oneRow = aura ~= nil and ns.BuffBar:Packed(data)
        across:SetShown(not oneRow)
        wrap:SetShown(not oneRow)
        wrap.label:SetShown(not oneRow)
        local held = ns.Layout ~= nil and ns.Layout:Active()
        for _, pills in ipairs({ grow, wrap }) do
            pills.held = held
            pills:SetAlpha(held and .4 or 1)
            pills.label:SetAlpha(held and .4 or 1)
        end
        grow:SetSelected(data.grow)
        wrap:SetSelected(data.wrap)
        -- When ready, On cooldown, its tick, Dimmed icons and Show the global
        -- cooldown: the cooldown bars only, taller for them.
        for _, part in ipairs({ whenReady, whenReady.label, onCooldown, onCooldown.label, dimUnusable, dimOpacity, showGCD }) do
            part:SetShown(not aura)
        end
        -- The tick count's two rows, while a Debuffs bar counts any.
        local kind = ns.BAR_KIND[key] -- (an extra bar's options are its kind's)
        local counting = kind == "debuff" and Counting()
        for _, part in ipairs({ tickAt, tickAt.label, tickFrom, tickEdge, tickSize, tickColour, tickChoice }) do part:SetShown(counting) end
        tickChoice:Paint()
        tickAt:SetSelected(data.tickAt)
        tickFrom:SetChecked(data.tickFrom == 1)
        tickEdge:SetChecked(data.tickEdge == true)
        tickSize:Set(data.tickSize)
        options:SetHeight(not aura and OPTIONS_COOLDOWN or counting and OPTIONS_TALL or OPTIONS)
        onCooldown:SetSelected(data.onCooldown)
        dimUnusable:SetChecked(data.dimUnusable)
        dimOpacity:Set(data.dimOpacity)
        dimOpacity:SetUsable(Dims(data))
        showGCD:SetChecked(data.showGCD)
        showMissing:SetShown(aura ~= nil)
        showMissing.text:SetText("Show missing " .. word .. "s greyed")
        showMissing:SetWidth(18 + (showMissing.text:GetStringWidth() or 0)) -- the label is its click area
        onlyMissing:SetShown(kind == "buff")
        onlyMissing:SetChecked(data.onlyMissing)
        -- Packed buffs have no fixed spot to put a name under.
        showNames:SetShown(not aura or not ns.BuffBar:Packed(data))
        whenReady:SetSelected(data.whenReady)
        showMissing:SetChecked(data.showMissing)
        showMissing:SetUsable(not data.onlyMissing)
        -- The Debuffs bar's own, usable with missing debuffs greyed ticked.
        keepGreyed:SetShown(kind == "debuff")
        keepGreyed:SetChecked(data.greyedNoTarget)
        keepGreyed:SetUsable(data.showMissing)
        showNames:SetChecked(data.showNames)
        outOfCombat:SetSelected(data.outOfCombat)
        showTimer:SetChecked(data.showTimer)
        showAuras:SetShown(not aura)
        showAuras:SetChecked(data.showAuras)
        -- Swap with my form, for a character who knows a form (ticked in
        -- your profile); Editing with it ticked, naming whose icons show.
        -- (Not on an extra bar: Cooldowns and Utility only.)
        local forms, swaps = ns.CanSwap(key) and #ns.KnownForms() > 0, ns.Swaps(key)
        swapForm:SetShown(forms)
        swapForm:SetChecked(swaps)
        if forms then
            local label = ns.SwapWords().label
            if swapForm.text:GetText() ~= label then
                swapForm.text:SetText(label)
                swapForm:SetWidth(18 + (swapForm.text:GetStringWidth() or 0)) -- the label is its click area
            end
        end
        local picking = forms and swaps
        editing:SetShown(picking)
        editing.label:SetShown(picking)
        if picking then editing.name:SetText(ns.FormName(ns.ShownForm(key))) end
        showSelf:SetShown(aura ~= nil)
        showSelf:SetChecked(data.selfDebuffs)
        if aura then
            showSelf.text:SetText(SELF_LABEL[kind])
            showSelf:SetWidth(18 + (showSelf.text:GetStringWidth() or 0)) -- the label is its click area
        end
        showItems:SetShown(not aura)
        showRanks:SetShown(not aura)
        showItems:SetChecked(ns.Get("listItems"))
        showRanks:SetChecked(ns.Get("listRanks"))
        ticked:ClearAllPoints()
        ticked:SetPoint("LEFT", aura and search or showRanks, "RIGHT", 14, 0)
        ticked:SetChecked(ns.Get("listTicked"))
        -- An aura bar already counts every rank; Show all ranks lists the lower ones.
        ranks:SetText(aura and "Each spell shows once, and counts every rank."
            or ns.Get("listRanks") and "Each spell at your highest rank, with the lower ranks you know under it."
            or "Each spell shows once, at your highest rank.")
        RefreshList()
        -- A spell's own panel, while it's open for this bar (another bar's goes).
        local panel = window.spellPanel
        if panel and panel:IsShown() then
            if panel.bar == key then panel:Refresh() else panel:Hide() end
        end
    end

    -- A failure is reported once in chat instead of leaving the page half drawn.
    function page:Refresh(key)
        local ok, err = pcall(Refresh, key)
        page.listError = not ok and tostring(err) or nil
        if not ok and not page.reported then
            page.reported = true
            print("|cffffd100" .. ns.TITLE .. ":|r this page couldn't be drawn. Please report this: " .. page.listError)
        end
    end
end
