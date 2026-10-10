-- A bar's page in the /ccm window: its icons in the order they show (drag
-- one onto another to swap them, x to take it off), its options, and a
-- searchable list of your spells with a tick box to put each on the bar.
local _, ns = ...
local T = ns.Theme

local ICON, GAP = 32, 12 -- icons in the tray; the gap fits the join button
local ROW, HEADER_ROW = 22, 20 -- spell list rows
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
-- one seen working in game 2026-10-08, so no Needs testing label).
local SELF_TICK = { buff = "Show your debuffs on you", debuff = "Show your debuffs on you" }
local SELF_LABEL = { buff = SELF_TICK.buff, debuff = SELF_TICK.debuff }

function ns.BuildBarPage(window, page, width)
    local B = ns.Bars
    local state = { bar = "cd", search = "" }
    local inner = width - 32
    local perRow = math.floor((inner - 12 + GAP) / (ICON + GAP))

    -- Title row -------------------------------------------------------------------
    local title = T:Heading(page, "")
    title:SetPoint("TOPLEFT", 16, -16)
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
        ns.Set("useBars", true)
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
        return state.armed == state.bar and ("Click again to take every icon off " .. name .. ".")
            or ("Take every icon off " .. name .. ". It asks for a second click.")
    end)
    page.clear = clear

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
        icon:SetSize(ICON, ICON)
        icon:SetPoint("TOPLEFT", 8 + ((i - 1) % perRow) * (ICON + GAP), -8 - math.floor((i - 1) / perRow) * (ICON + GAP))
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
        -- bar, as on the tray round it; a click with nothing held does nothing.
        icon:SetScript("OnReceiveDrag", function() B:Dropped(state.bar) end)
        icon:SetScript("OnClick", function() B:Dropped(state.bar) end)
        icon.drop = Bar
        -- The footer names the icon under the mouse; its x says what it does.
        -- One added before the add box turned it away (Weakened Soul) says why it never shows.
        window:Hint(icon, function(self)
            if not self.name then return nil end
            if ns.Spells:SelfDebuffNote(self.name) then
                -- This page's own tick, or where to find one (one line: 93 letters at most).
                if SELF_TICK[state.bar] then
                    return self.name .. " can't show here. Tick \"" .. SELF_TICK[state.bar] .. "\" and drag it off the bar."
                end
                return self.name .. " can't show here. Drag it off, and tick \"" .. SELF_TICK.buff .. "\" on Buffs."
            end
            return self.name .. ". Drag it onto another icon to swap them, or off the bar to take it off."
        end)
        page.icons[i] = icon
        return icon
    end

    -- Options ------------------------------------------------------------------------
    local options = CreateFrame("Frame", nil, page)
    options:SetPoint("TOPLEFT", tray, "BOTTOMLEFT", 0, -12)
    options:SetSize(inner, 134)
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

    local function Option(label, field, y, note)
        local check = T:Check(options, label, function(self)
            B:SetOption(state.bar, field, self:GetChecked())
            window:Refresh()
        end)
        check:SetPoint("TOPLEFT", 320, y)
        window:Hint(check, note)
        return check
    end
    -- Buffs only show while they're on you, so their bar offers this instead
    -- of When ready (below), in the same spot.
    local showMissing = Option("Show missing buffs greyed", "showMissing", 0, function()
        return (state.bar == "debuff" and "Debuffs missing from your target" or "Buffs missing from you")
            .. " show greyed in their spot, instead of hidden."
    end)
    local showNames = Option("Show spell names", "showNames", -22, "Each spell's name under its icon.")
    local showTimer = Option("Show countdown numbers", "showTimer", -44, "The numbers counting down on this bar's icons.")
    -- The cooldown bars only: an icon shows the time left on the buff its
    -- spell put on you or its debuff on your target, as Blizzard's does.
    local showAuras = Option("Show buff and debuff time", "showAuras", -107,
        "While the buff a spell put on you, or its debuff on your target (like Shadow Word: Pain), is up,"
            .. " its icon shows the time left with a gold edge.")
    -- The Buffs and Debuffs bars, in the same spot, each its own (its label
    -- set on refresh: SELF_LABEL).
    local showSelf = Option(SELF_LABEL.buff, "selfDebuffs", -107, function()
        if state.bar == "debuff" then
            return "Debuffs you put on yourself, like Weakened Soul from your shield or Recently Bandaged, at the end of this bar."
                .. " Not with missing debuffs greyed."
        end
        return "Debuffs you put on yourself, like Weakened Soul from your shield or Recently Bandaged, after your buffs."
            .. " Not with missing buffs greyed."
    end)

    -- A label and joined buttons for a choice, with the footer explaining it:
    -- note is the same for every button, or one for each choice by its key.
    local function Pills(label, x, y, width, keys, names, field, note)
        local text = T:Text(options, "GameFontHighlight")
        text:SetPoint("TOPLEFT", x, y - 4)
        text:SetText(label)
        local choices = {}
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
            window:Hint(button, function() return pills.held and "Your layout sets this. Change it on the Layout page." or own end)
        end
        pills.label = text
        return pills
    end
    -- When ready: each icon in full, dimmed or hidden while its spell is
    -- ready. Dim is new, so its note says it needs testing.
    local whenReady = Pills("When ready", 320, 0, 156, ns.WHEN_READY, ns.WHEN_READY_NAMES, "whenReady", {
        show = "Every icon shows in full, ready or cooling down.",
        dim = "Each icon dims while it's ready, so the ones cooling down stand out.",
        hide = "Each icon hides while it's ready, so only the ones cooling down show.",
    })
    -- The label and its choices as one part, for the tour to outline: the
    -- label ends above the buttons, so a box hung from it sat too high.
    local readyPart = CreateFrame("Frame", nil, options)
    readyPart:SetPoint("TOPLEFT", 320, 0)
    readyPart:SetSize(100 + 156, 20)
    whenReady.part = readyPart
    -- Out of combat: show, fade or hide. The footer explains when bars come back.
    local outOfCombat = Pills("Out of combat", 0, -85, 156, ns.OUT_OF_COMBAT, ns.OUT_OF_COMBAT_NAMES, "outOfCombat",
        "Out of combat. Bars come back in full in combat, with an enemy targeted, while unlocked, and in Edit Mode.")
    local grow = Pills("Grow", 320, -63, 156, ns.GROW, ns.GROW_NAMES, "grow",
        "Which way a row grows as icons come and go: from its centre, or from its right or left edge.")
    local wrap = Pills("New rows", 320, -85, 110, ns.WRAP, ns.WRAP_NAMES, "wrap",
        "Where the next row goes when there are more icons than fit across.")
    page.options = { whenReady = whenReady, showMissing = showMissing, showNames = showNames,
        showTimer = showTimer, showAuras = showAuras, showSelf = showSelf, outOfCombat = outOfCombat, grow = grow, wrap = wrap }

    -- The spell list -------------------------------------------------------------------
    local listPanel = CreateFrame("Frame", nil, page, "BackdropTemplate")
    listPanel:SetPoint("TOPLEFT", options, "BOTTOMLEFT", 0, -10)
    listPanel:SetPoint("BOTTOMRIGHT", -16, 12)
    T:Box(listPanel)
    local search = T:Input(listPanel, "Search spells, or type a name or spell ID", 280)
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
    page.showItems, page.showRanks = showItems, showRanks
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
        for _, part in ipairs({ row.check, row.icon, row.name, row.rank, row.where }) do part:Hide() end
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
        row:Show()
        y = y + ROW
        return row
    end

    local function Spell(entry, indent, rankText)
        local row = Entry(entry.icon, indent and entry.rankText or entry.name, rankText, indent)
        row.spell, row.other, row.label, row.pinned = entry.key, nil, entry.name, nil
        if ns.AURA_BARS[state.bar] then
            row.check:SetChecked(B:HasAura(state.bar, entry.key))
        else
            local on = B:Find(entry.key)
            row.check:SetChecked(on == state.bar)
            -- A spell sits on one cooldown bar at a time; ticking it here moves it.
            if on and on ~= state.bar then row.where:SetText("on " .. ns.BAR_NAMES[on]) end
        end
    end

    -- What this bar can hold: procs have no cooldown of their own and are
    -- buffs on you, items put no aura on anyone, and a fixed rank adds
    -- nothing to an aura bar, which already counts every rank.
    local function Fits(entry)
        local item = ns.Spells:IsItem(entry)
        if state.bar == "buff" then return not item and entry.kind ~= "rank" end
        if state.bar == "debuff" then return not item and entry.kind ~= "rank" and entry.kind ~= "proc" end
        if item then return ns.Get("listItems") end
        return entry.kind ~= "proc"
    end

    local function RefreshList()
        y, n = 0, 0
        local list = ns.Spells:Fresh()
        local text, listRanks = state.search, ns.Get("listRanks") and not ns.AURA_BARS[state.bar]
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
            if Fits(entry) and ns.Spells:ForMe(entry.key, state.bar)
                and (text == "" or entry.name:lower():find(text, 1, true) or (id and entry.spellID == id)) then
                if text == "" and entry.line ~= line then
                    line = entry.line
                    Header(line or "")
                end
                local lower = listRanks and entry.lower or {}
                Spell(entry, false, #lower > 0 and ("Highest (Rank " .. entry.rank .. ")") or entry.rankText)
                -- Lower ranks under the spell, each fixed to that rank.
                for _, fixed in ipairs(lower) do Spell(fixed, true, "") end
            end
        end
        -- Searching also finds spells outside your spellbook, by name or ID.
        -- Not a passive this bar can't track (Underwater Breathing), which
        -- would only be turned away. On the Buffs and Debuffs bars, an ID
        -- for another spell of a name already in your lists (the second
        -- Energized) is offered too: it goes on pinned to that ID.
        if #text >= 3 or id then
            local others = {}
            if id then
                local name = C_Spell.GetSpellName and C_Spell.GetSpellName(id)
                local pinned = type(name) == "string" and ns.Spells:Pin(id, state.bar)
                if type(name) == "string" and not known[pinned or name] and not ns.Spells:AddNote(text, state.bar) then
                    local label = name .. " (ID " .. id .. ")"
                    others[1] = { name = pinned and label or name, label = label, lookup = text,
                        icon = C_Spell.GetSpellTexture(id), pinned = pinned or nil }
                end
            else
                for _, found in ipairs(ns.Spells:Suggest(text, 8)) do
                    if not known[found.name] and not ns.Spells:AddNote(found.name, state.bar) then
                        others[#others + 1] = { name = found.name, label = found.name, lookup = found.name,
                            icon = found.icon or (found.spellID and C_Spell.GetSpellTexture(found.spellID)) }
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
        if n == 0 then Header(selfNote and "A debuff on you: see below" or text == "" and "Nothing to list" or "No matches") end
        for i = n + 1, #rows do rows[i]:Hide() end
        scroll.content:SetHeight(math.max(1, y))
        scroll:ScrollTo(scroll:GetVerticalScroll() or 0)
    end

    local function RefreshTray()
        local aura = ns.AURA_BARS[state.bar] ~= nil
        -- Your own entries: another class's, in a shared profile, stay hidden.
        local names, places = B:Mine(state.bar)
        for n, key in ipairs(names) do
            local icon, i = TrayIcon(n), places[n]
            local entry = ns.Spells:Find(key)
            icon.index, icon.name = i, entry and entry.name or key
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
            icon.bridge:SetShown(joined and (n - 1) % perRow ~= 0)
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
        local lines = math.max(1, math.ceil(#names / perRow))
        local trayHeight = 16 + lines * ICON + (lines - 1) * GAP
        tray:SetHeight(trayHeight)
        empty:SetShown(#names == 0)
        empty:SetText(EMPTY[state.bar])
    end

    local function Refresh(key)
        if key ~= state.bar then
            state.bar, state.armed = key, nil
            scroll:ScrollTo(0)
        end
        local data = ns.BarData(key)
        local spells = B:Mine(key)
        local name = ns.BAR_NAMES[key]
        title:SetText(name:upper())
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
        clear:SetShown(#spells > 0 or state.armed == key)
        RefreshTray()
        size:Set(data.size)
        spacing:Set(data.spacing)
        across:Set(data.perRow)
        -- Packed buffs are laid out by the game in one row.
        local oneRow = aura ~= nil and not data.showMissing
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
        whenReady:SetShown(not aura)
        whenReady.label:SetShown(not aura)
        showMissing:SetShown(aura ~= nil)
        showMissing.text:SetText("Show missing " .. word .. "s greyed")
        -- Packed buffs have no fixed spot to put a name under.
        showNames:SetShown(not aura or data.showMissing)
        whenReady:SetSelected(data.whenReady)
        showMissing:SetChecked(data.showMissing)
        showNames:SetChecked(data.showNames)
        outOfCombat:SetSelected(data.outOfCombat)
        showTimer:SetChecked(data.showTimer)
        showAuras:SetShown(not aura)
        showAuras:SetChecked(data.showAuras)
        showSelf:SetShown(aura ~= nil)
        showSelf:SetChecked(data.selfDebuffs)
        if aura then
            showSelf.text:SetText(SELF_LABEL[state.bar])
            showSelf:SetWidth(18 + (showSelf.text:GetStringWidth() or 0)) -- the label is its click area
        end
        showItems:SetShown(not aura)
        showRanks:SetShown(not aura)
        showItems:SetChecked(ns.Get("listItems"))
        showRanks:SetChecked(ns.Get("listRanks"))
        -- An aura bar already counts every rank; Show all ranks lists the lower ones.
        ranks:SetText(aura and "Each spell shows once, and counts every rank."
            or ns.Get("listRanks") and "Each spell at your highest rank, with the lower ranks you know under it."
            or "Each spell shows once, at your highest rank.")
        RefreshList()
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
