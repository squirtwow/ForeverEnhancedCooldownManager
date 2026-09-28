-- A bar's page in the /fecm window: its icons in the order they show (drag
-- one onto another to move it, x to take it off), its options, and a
-- searchable list of your spells with a tick box to put each on the bar.
local _, ns = ...
local T = ns.Theme

local ICON, GAP = 32, 12 -- icons in the tray; the gap fits the join button
local ROW, HEADER_ROW = 22, 20 -- spell list rows
local EMPTY = {
    cd = "Nothing here yet. Tick spells in the list below to add them.",
    util = "Nothing here yet. Tick spells in the list below to add them.",
    buff = "Nothing here yet. Tick spells that buff you, or your class procs, in the list below.",
    debuff = "Nothing here yet. Tick spells that put a debuff on your target in the list below.",
}

local function Full(key)
    return ns.BAR_NAMES[key] .. " is full."
end

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
    page.turnOn = turnOn

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
    page.clear = clear

    -- The tray: the bar's icons, left to right --------------------------------------
    local tray = CreateFrame("Frame", nil, page, "BackdropTemplate")
    tray:SetPoint("TOPLEFT", 16, -38)
    tray:SetSize(inner, 16 + ICON) -- a real size from the start, before the first refresh
    T:Flat(tray, T.PANEL, T.BORDER)
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
    ghost:SetScript("OnUpdate", function(self)
        local x, y = GetCursorPosition()
        local scale = UIParent:GetEffectiveScale()
        self:ClearAllPoints()
        self:SetPoint("CENTER", UIParent, "BOTTOMLEFT", x / scale, y / scale)
    end)

    -- Where a dragged icon lands: on another icon takes its place, anywhere
    -- else in the tray goes to the end.
    local function DropTarget()
        for i, icon in ipairs(page.icons) do
            if icon:IsShown() and icon:IsMouseOver() then return i end
        end
        if tray:IsMouseOver() then return #ns.BarData(state.bar).spells end
    end

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
        -- On the Buffs and Debuffs bars, the button in the gap before an icon
        -- joins it to the one before, or splits them again; a line under the
        -- pair shows they're joined.
        icon.link = T:Square(tray, "+")
        icon.link:SetSize(14, 14)
        icon.link:SetPoint("CENTER", icon, "LEFT", -GAP / 2, 0)
        icon.link:SetFrameLevel(icon:GetFrameLevel() + 3)
        icon.link:SetScript("OnClick", function()
            B:SetJoined(state.bar, icon.index, not B:Joined(state.bar, icon.index))
            window:Refresh()
        end)
        icon.link:SetScript("OnEnter", function()
            window.note:SetText(B:Joined(state.bar, icon.index) and "Split this from the one before."
                or "Join this to the one before: they'll show as one icon, lit by whichever is up.")
        end)
        icon.link:SetScript("OnLeave", function() window.note:SetText(window.lastNote or "") end)
        icon.bridge = tray:CreateTexture(nil, "ARTWORK")
        icon.bridge:SetHeight(3)
        icon.bridge:SetPoint("TOPLEFT", icon, "BOTTOMLEFT", -(ICON + GAP), -3)
        icon.bridge:SetPoint("TOPRIGHT", icon, "BOTTOMRIGHT", 0, -3)
        T:Paint(function(accent) T:Fill(icon.bridge, accent) end)
        icon:RegisterForDrag("LeftButton")
        icon:SetScript("OnDragStart", function(self)
            state.drag = self.index
            self:SetAlpha(.3)
            ghost.texture:SetTexture(self.texture:GetTexture())
            ghost:Show()
        end)
        icon:SetScript("OnDragStop", function(self)
            ghost:Hide()
            self:SetAlpha(1)
            local from, to = state.drag, DropTarget()
            state.drag = nil
            if from and to and to ~= from then
                B:MoveTo(state.bar, from, to)
                window:Refresh()
            end
        end)
        -- The footer names the icon under the mouse.
        icon:SetScript("OnEnter", function(self) window.note:SetText(self.name or "") end)
        icon:SetScript("OnLeave", function() window.note:SetText(window.lastNote or "") end)
        page.icons[i] = icon
        return icon
    end

    -- Options ------------------------------------------------------------------------
    local options = CreateFrame("Frame", nil, page)
    options:SetPoint("TOPLEFT", tray, "BOTTOMLEFT", 0, -12)
    options:SetSize(inner, 90)
    local size = T:Slider(options, "Icon size", ns.BAR_LIMITS.size, 2, 280, function(value)
        B:SetOption(state.bar, "size", value)
        window:Refresh()
    end)
    size:SetPoint("TOPLEFT", 0, -2)
    local spacing = T:Slider(options, "Spacing", ns.BAR_LIMITS.spacing, 1, 280, function(value)
        B:SetOption(state.bar, "spacing", value)
        window:Refresh()
    end)
    spacing:SetPoint("TOPLEFT", 0, -30)
    page.size, page.spacing = size, spacing

    local function Option(label, field, y)
        local check = T:Check(options, label, function(self)
            B:SetOption(state.bar, field, self:GetChecked())
            window:Refresh()
        end)
        check:SetPoint("TOPLEFT", 320, y)
        return check
    end
    local hideReady = Option("Hide when ready", "hideReady", 0)
    -- Buffs only show while they're on you, so their bar offers this instead.
    local showMissing = Option("Show missing buffs greyed", "showMissing", 0)
    local showNames = Option("Show spell names", "showNames", -22)
    local showTimer = Option("Show countdown numbers", "showTimer", -44)

    -- Out of combat: show, fade or hide. The footer explains when bars come back.
    local oocLabel = T:Text(options, "GameFontHighlight")
    oocLabel:SetPoint("TOPLEFT", 0, -63)
    oocLabel:SetText("Out of combat")
    local choices = {}
    for _, mode in ipairs(ns.OUT_OF_COMBAT) do choices[#choices + 1] = { key = mode, label = ns.OUT_OF_COMBAT_NAMES[mode] } end
    local outOfCombat = T:Segmented(options, choices, 156, function(mode)
        B:SetOption(state.bar, "outOfCombat", mode)
        window:Refresh()
    end)
    outOfCombat:SetPoint("TOPLEFT", 100, -59)
    for _, button in ipairs(outOfCombat.buttons) do
        button:SetScript("OnEnter", function()
            window.note:SetText("Out of combat. Bars come back in full in combat, with an enemy targeted, while unlocked, and in Edit Mode.")
        end)
        button:SetScript("OnLeave", function() window.note:SetText(window.lastNote or "") end)
    end
    page.options = { hideReady = hideReady, showMissing = showMissing, showNames = showNames,
        showTimer = showTimer, outOfCombat = outOfCombat }

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
    page.search = search
    -- Trinkets and bag items only join the list when asked.
    local showItems = T:Check(listPanel, "Show items", function(self)
        ns.Set("listItems", self:GetChecked())
        window:Refresh()
    end)
    showItems:SetPoint("LEFT", search, "RIGHT", 14, 0)
    -- Every rank you know as its own row, for casting a lower rank on purpose.
    local showRanks = T:Check(listPanel, "Show all ranks", function(self)
        ns.Set("listRanks", self:GetChecked())
        window:Refresh()
    end)
    showRanks:SetPoint("LEFT", showItems, "RIGHT", 14, 0)
    page.showItems, page.showRanks = showItems, showRanks

    local listWidth = inner - 30
    -- On this client a scroll area pinned while the page is still hidden is
    -- never placed, and draws nothing; one placed by a single corner and a
    -- size isn't either. So it's pinned by two corners, again a moment after
    -- the page shows, once everything around it has been laid out.
    local scroll = T:Scroll(listPanel, listWidth)
    local function Pin()
        scroll:ClearAllPoints()
        scroll:SetPoint("TOPLEFT", listPanel, "TOPLEFT", 8, -36)
        scroll:SetPoint("BOTTOMRIGHT", listPanel, "BOTTOMRIGHT", -16, 6)
        scroll:ScrollTo(scroll:GetVerticalScroll() or 0)
    end
    Pin()
    page:HookScript("OnShow", function() C_Timer.After(0, Pin) end)
    page.list, page.listPanel = scroll, listPanel
    local rows = {}
    page.rows = rows

    -- Adds a spell that isn't in your spellbook, by name or ID, to this bar.
    local function AddOther(text)
        local bar = state.bar
        local found, ids = ns.Spells:Resolve(text)
        if not found then
            window:Say(ids)
            return
        end
        local entry = ns.Spells:Find(found)
        if ns.AURA_BARS[bar] and entry and ns.Spells:IsItem(entry) then
            window:Say("Items can't go on the " .. ns.BAR_NAMES[bar] .. " bar.")
            return
        end
        if ids and not entry then ns.AddCustom(found, ids) end
        local ok
        if ns.AURA_BARS[bar] then ok = B:SetAura(bar, found, true) else ok = B:Assign(found, bar) end
        ns.PruneCustom()
        window:Say(ok and ("Added " .. (entry and entry.name or found) .. " to " .. ns.BAR_NAMES[bar] .. ".") or Full(bar))
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
        row.icon = row:CreateTexture(nil, "ARTWORK")
        row.icon:SetSize(16, 16)
        ns.Style:Zoom(row.icon)
        row.name = T:Text(row, "GameFontHighlight")
        row.name:SetPoint("LEFT", row.icon, "RIGHT", 6, 0)
        row.name:SetWordWrap(false)
        row.rank = T:Text(row, "GameFontHighlightSmall", T.MUTED)
        row.rank:SetPoint("LEFT", row.name, "RIGHT", 5, 0)
        row.where = T:Text(row, "GameFontHighlightSmall", T.MUTED)
        row.where:SetPoint("RIGHT", -8, 0)
        row.where:SetJustifyH("RIGHT")
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
        row.spell, row.other = nil, nil
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
        for _, part in ipairs({ row.check, row.icon, row.name, row.rank, row.where }) do part:Show() end
        row:Show()
        y = y + ROW
        return row
    end

    local function Spell(entry, indent, rankText)
        local row = Entry(entry.icon, indent and entry.rankText or entry.name, rankText, indent)
        row.spell, row.other = entry.key, nil
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
        local list = ns.Spells:List()
        if #list == 0 then list = ns.Spells:Scan() end
        local text, listRanks = state.search, ns.Get("listRanks") and not ns.AURA_BARS[state.bar]
        local id = tonumber(text)
        local line
        local known = {}
        for _, entry in ipairs(list) do
            known[entry.name] = true
            if Fits(entry) and (text == "" or entry.name:lower():find(text, 1, true) or (id and entry.spellID == id)) then
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
        if #text >= 3 or id then
            local others = {}
            if id then
                local name = C_Spell.GetSpellName and C_Spell.GetSpellName(id)
                if type(name) == "string" and not known[name] then
                    others[1] = { name = name, label = name .. " (ID " .. id .. ")", lookup = text,
                        icon = C_Spell.GetSpellTexture(id) }
                end
            else
                for _, found in ipairs(ns.Spells:Suggest(text, 8)) do
                    if not known[found.name] then
                        others[#others + 1] = { name = found.name, label = found.name, lookup = found.name,
                            icon = found.icon or (found.spellID and C_Spell.GetSpellTexture(found.spellID)) }
                    end
                end
            end
            if #others > 0 then
                Header("Other spells")
                for _, other in ipairs(others) do
                    local row = Entry(other.icon, other.label, "")
                    row.spell, row.other = nil, other.lookup
                    row.check:SetChecked(false)
                end
            end
        end
        if n == 0 then Header(text == "" and "Nothing to list" or "No matches") end
        for i = n + 1, #rows do rows[i]:Hide() end
        scroll.content:SetHeight(math.max(1, y))
        scroll:ScrollTo(scroll:GetVerticalScroll() or 0)
    end

    local function RefreshTray()
        local spells = ns.BarData(state.bar).spells
        local aura = ns.AURA_BARS[state.bar] ~= nil
        for i, key in ipairs(spells) do
            local icon = TrayIcon(i)
            local entry = ns.Spells:Find(key)
            icon.index, icon.name = i, entry and entry.name or key
            icon.texture:SetTexture(entry and entry.icon or 134400) -- question mark until learned
            icon.texture:SetDesaturated(entry == nil)
            local joined = aura and B:Joined(state.bar, i)
            icon.link:SetShown(aura and i > 1)
            icon.link:SetLabel(joined and "-" or "+")
            local colour = joined and T:Accent() or T.MUTED
            icon.link.label:SetTextColor(colour[1], colour[2], colour[3])
            -- An icon starting a new row has its partner at the end of the row above.
            icon.bridge:SetShown(joined and (i - 1) % perRow ~= 0)
            icon:Show()
        end
        for i = #spells + 1, #page.icons do page.icons[i]:Hide() end
        local lines = math.max(1, math.ceil(#spells / perRow))
        local trayHeight = 16 + lines * ICON + (lines - 1) * GAP
        tray:SetHeight(trayHeight)
        empty:SetShown(#spells == 0)
        empty:SetText(EMPTY[state.bar])
    end

    local function Refresh(key)
        if key ~= state.bar then
            state.bar, state.armed = key, nil
            scroll:ScrollTo(0)
        end
        local data = ns.BarData(key)
        local spells = data.spells
        local name = ns.BAR_NAMES[key]
        title:SetText(name:upper())
        local on = B:Enabled()
        off:SetShown(not on)
        turnOn:SetShown(not on)
        count:SetShown(on)
        local aura = ns.AURA_BARS[key]
        local word = aura and aura.word or "icon"
        count:SetText(#spells == 0 and "Empty" or (#spells .. " " .. word .. (#spells == 1 and "" or "s")
            .. ", drag to reorder"))
        clear:SetLabel(state.armed == key and "Click again to clear" or ("Clear " .. name))
        clear:SetShown(#spells > 0 or state.armed == key)
        RefreshTray()
        size:Set(data.size)
        spacing:Set(data.spacing)
        hideReady:SetShown(not aura)
        showMissing:SetShown(aura ~= nil)
        showMissing.text:SetText("Show missing " .. word .. "s greyed")
        -- Packed buffs have no fixed spot to put a name under.
        showNames:SetShown(not aura or data.showMissing)
        hideReady:SetChecked(data.hideReady)
        showMissing:SetChecked(data.showMissing)
        showNames:SetChecked(data.showNames)
        outOfCombat:SetSelected(data.outOfCombat)
        showTimer:SetChecked(data.showTimer)
        showItems:SetShown(not aura)
        showRanks:SetShown(not aura)
        showItems:SetChecked(ns.Get("listItems"))
        showRanks:SetChecked(ns.Get("listRanks"))
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
