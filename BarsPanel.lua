-- The Spellbook and Bars columns of the /ccm window, and its "Add a spell"
-- box: your spells ticked onto a bar on the left, the chosen bar's order and
-- options in the middle.
local _, ns = ...
local T = ns.Theme

local ROW, HEADER = 22, 20
local SPELL_LIST = 308 -- spellbook list width
local BAR_LIST = 228 -- bar list width
-- Tick centres across a spellbook row, and the column labels above them.
local TICKS = { cd = 236, util = 266, buff = 296 }
local EMPTY = {
    cd = "Tick CD on spells to add them to this bar.",
    util = "Tick Util on spells to add them to this bar.",
    buff = "Tick Buff on spells that put a buff on you, or on your class procs near the bottom of the list.",
}

local function Stepper(parent, label, limits, step, onChange)
    local stepper = CreateFrame("Frame", nil, parent)
    stepper:SetSize(234, 20)
    local text = T:Text(stepper, "GameFontHighlight")
    text:SetPoint("LEFT")
    text:SetText(label)
    local plus = T:Square(stepper, "+", true)
    plus:SetPoint("RIGHT")
    local value = T:Text(stepper, "GameFontHighlight")
    value:SetPoint("RIGHT", plus, "LEFT", -4, 0)
    value:SetWidth(28)
    value:SetJustifyH("CENTER")
    local minus = T:Square(stepper, "-", true)
    minus:SetPoint("RIGHT", value, "LEFT", -4, 0)
    minus:SetScript("OnClick", function() onChange(math.max(limits[1], stepper.current - step)) end)
    plus:SetScript("OnClick", function() onChange(math.min(limits[2], stepper.current + step)) end)
    function stepper:Set(number)
        self.current = number
        value:SetText(number)
    end
    return stepper
end

function ns.BuildBarsPanels(window, spellPanel, barsPanel, settingsPanel)
    local B = ns.Bars
    local state = { bar = "cd", search = "" }
    local spellRows, barRows = {}, {}

    -- Spellbook ------------------------------------------------------------------
    T:Heading(spellPanel, "Spellbook"):SetPoint("TOPLEFT", 8, -9)
    local search = T:Input(spellPanel, "Search spells", 206)
    search:SetPoint("TOPLEFT", 8, -26)
    search:SetScript("OnTextChanged", function(self)
        state.search = (self:GetText() or ""):lower()
        window:RefreshBars()
    end)
    -- Trinkets and bag items only join the list when asked; items already on a
    -- bar stay there either way.
    local showItems = T:Check(spellPanel, "Show items", function(self)
        ns.Set("listItems", self:GetChecked())
        window:Refresh()
    end)
    showItems:SetPoint("LEFT", search, "RIGHT", 10, 0)
    -- Every rank you know as its own row, for casting a lower rank on purpose.
    local showRanks = T:Check(spellPanel, "Show all ranks", function(self)
        ns.Set("listRanks", self:GetChecked())
        window:Refresh()
    end)
    showRanks:SetPoint("TOPLEFT", 8, -49)
    for key, x in pairs(TICKS) do
        local label = T:Text(spellPanel, "GameFontHighlightSmall", T.MUTED)
        label:SetPoint("CENTER", spellPanel, "TOPLEFT", 8 + x, -56)
        label:SetText(key:upper())
    end

    local spellScroll = T:Scroll(spellPanel, SPELL_LIST)
    spellScroll:SetPoint("TOPLEFT", 8, -66)
    spellScroll:SetPoint("BOTTOMRIGHT", -14, 8)

    local function SpellRow(i)
        local row = spellRows[i]
        if row then return row end
        row = CreateFrame("Frame", nil, spellScroll.content)
        row:SetSize(SPELL_LIST, ROW)
        row.icon = row:CreateTexture(nil, "ARTWORK")
        row.icon:SetSize(16, 16)
        row.icon:SetPoint("LEFT", 2, 0)
        row.name = T:Text(row, "GameFontHighlight")
        row.name:SetPoint("LEFT", row.icon, "RIGHT", 6, 0)
        row.name:SetWordWrap(false)
        row.rank = T:Text(row, "GameFontHighlightSmall", T.MUTED)
        row.rank:SetPoint("LEFT", row.name, "RIGHT", 5, 0)
        row.header = T:Text(row, "GameFontHighlightSmall", T.MUTED)
        row.header:SetPoint("BOTTOMLEFT", 2, 3)
        local function Tick(key)
            return function(self)
                local ok
                if key == "buff" then
                    ok = B:SetBuff(row.spell, self:GetChecked())
                else
                    ok = B:Assign(row.spell, self:GetChecked() and key or nil)
                end
                if not ok then window:Say(ns.BAR_NAMES[key] .. " is full.") end
                window:Refresh()
            end
        end
        for key, x in pairs(TICKS) do
            local check = T:Check(row, nil, Tick(key))
            check:SetPoint("CENTER", row, "LEFT", x, 0)
            row[key] = check
        end
        spellRows[i] = row
        return row
    end

    -- Bars -----------------------------------------------------------------------
    T:Heading(barsPanel, "Bars"):SetPoint("TOPLEFT", 8, -9)
    local items = {}
    for _, key in ipairs(ns.BAR_KEYS) do items[#items + 1] = { key = key, label = ns.BAR_NAMES[key] } end
    local segments = T:Segmented(barsPanel, items, 234, function(key)
        state.bar = key
        state.armed = nil
        window:Refresh()
    end)
    segments:SetPoint("TOPLEFT", 8, -26)
    local count = T:Text(barsPanel, "GameFontHighlightSmall", T.MUTED)
    count:SetPoint("TOPLEFT", 8, -52)

    local barScroll = T:Scroll(barsPanel, BAR_LIST)
    barScroll:SetPoint("TOPLEFT", 8, -66)
    barScroll:SetPoint("BOTTOMRIGHT", -14, 176)
    local empty = T:Text(barsPanel, "GameFontHighlightSmall", T.MUTED)
    empty:SetPoint("TOPLEFT", 10, -70)
    empty:SetWidth(222)

    local function BarRow(i)
        local row = barRows[i]
        if row then return row end
        row = CreateFrame("Frame", nil, barScroll.content)
        row:SetSize(BAR_LIST, ROW)
        row.fill = row:CreateTexture(nil, "BACKGROUND")
        row.fill:SetPoint("TOPLEFT", 0, -1)
        row.fill:SetPoint("BOTTOMRIGHT", 0, 1)
        row.fill:SetColorTexture(T.ROW[1], T.ROW[2], T.ROW[3], 1)
        row.icon = row:CreateTexture(nil, "ARTWORK")
        row.icon:SetSize(16, 16)
        row.icon:SetPoint("LEFT", 3, 0)
        row.name = T:Text(row, "GameFontHighlight")
        row.name:SetPoint("LEFT", row.icon, "RIGHT", 6, 0)
        row.name:SetWidth(132)
        row.name:SetWordWrap(false)
        row.remove = T:Square(row, "x")
        row.remove:SetPoint("RIGHT", -2, 0)
        row.remove:SetScript("OnClick", function() B:Remove(state.bar, row.index); window:Refresh() end)
        row.down = T:Square(row, "v", true)
        row.down:SetPoint("RIGHT", row.remove, "LEFT", -2, 0)
        row.down:SetScript("OnClick", function() B:Move(state.bar, row.index, 1); window:Refresh() end)
        row.up = T:Square(row, "^", true)
        row.up:SetPoint("RIGHT", row.down, "LEFT", -2, 0)
        row.up:SetScript("OnClick", function() B:Move(state.bar, row.index, -1); window:Refresh() end)
        barRows[i] = row
        return row
    end

    local size = Stepper(barsPanel, "Icon size", ns.BAR_LIMITS.size, 2, function(value)
        B:SetOption(state.bar, "size", value)
        window:Refresh()
    end)
    size:SetPoint("BOTTOMLEFT", 8, 146)
    local spacing = Stepper(barsPanel, "Spacing", ns.BAR_LIMITS.spacing, 1, function(value)
        B:SetOption(state.bar, "spacing", value)
        window:Refresh()
    end)
    spacing:SetPoint("BOTTOMLEFT", 8, 122)
    local function Option(label, field, y)
        local check = T:Check(barsPanel, label, function(self)
            B:SetOption(state.bar, field, self:GetChecked())
            window:Refresh()
        end)
        check:SetPoint("BOTTOMLEFT", 8, y)
        return check
    end
    local hideReady = Option("Hide when ready", "hideReady", 98)
    -- Buffs only show while they're on you, so their bar offers this instead.
    local showMissing = Option("Show missing buffs greyed", "showMissing", 98)
    local showNames = Option("Show spell names", "showNames", 76)
    local combatOnly = Option("Only in combat", "combatOnly", 54)

    -- Clearing asks for a second click within a few seconds.
    local clear = T:Button(barsPanel, "", 234)
    clear:SetPoint("BOTTOMLEFT", 8, 10)
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
    window.clear = clear

    -- Add a spell ------------------------------------------------------------------
    T:Heading(settingsPanel, "Add a spell"):SetPoint("TOPLEFT", 8, -258)
    local add = T:Input(settingsPanel, "Name or spell ID", 168)
    add:SetPoint("TOPLEFT", 8, -276)
    window.add, window.addButtons = add, {}

    -- Matches appear above the box as you type, best nearest the box; click one
    -- (or press Enter for the best) to fill in its exact name.
    local SUGGESTIONS = 8
    local suggest = CreateFrame("Frame", nil, settingsPanel, "BackdropTemplate")
    suggest:SetPoint("BOTTOMRIGHT", add, "TOPRIGHT", 0, 3)
    suggest:SetSize(250, 8)
    suggest:SetFrameLevel(settingsPanel:GetFrameLevel() + 50)
    T:Flat(suggest, { .05, .05, .05, .98 }, T.CONTROL_BORDER)
    suggest:EnableMouse(true)
    suggest:Hide()
    suggest.rows = {}
    for i = 1, SUGGESTIONS do
        local row = CreateFrame("Button", nil, suggest)
        row:SetSize(242, 20)
        row:SetPoint("BOTTOMLEFT", 4, 4 + (i - 1) * 20)
        row.icon = row:CreateTexture(nil, "ARTWORK")
        row.icon:SetSize(16, 16)
        row.icon:SetPoint("LEFT", 2, 0)
        row.text = T:Text(row, "GameFontHighlight")
        row.text:SetPoint("LEFT", row.icon, "RIGHT", 6, 0)
        row.text:SetWidth(214)
        row.text:SetWordWrap(false)
        local glow = row:CreateTexture(nil, "HIGHLIGHT")
        glow:SetAllPoints()
        glow:SetColorTexture(1, 1, 1, .1)
        row:SetScript("OnClick", function(self)
            add:SetText(self.name)
            suggest:Hide()
            add:ClearFocus()
        end)
        suggest.rows[i] = row
    end
    add.suggest = suggest
    local function Suggest(text)
        local found = ns.Spells:Suggest(text, SUGGESTIONS)
        for i, row in ipairs(suggest.rows) do
            local item = found[i]
            row.name = item and item.name
            if item then
                row.icon:SetTexture(item.icon or (item.spellID and C_Spell.GetSpellTexture(item.spellID)) or 134400)
                row.text:SetText(item.name)
            end
            row:SetShown(item ~= nil)
        end
        suggest:SetHeight(#found * 20 + 8)
        suggest:SetShown(#found > 0)
    end
    add:SetScript("OnTextChanged", function(self, typed)
        if typed then Suggest(self:GetText()) end
    end)
    add:SetScript("OnEnterPressed", function(self)
        local first = suggest:IsShown() and suggest.rows[1].name
        if first then self:SetText(first) end
        suggest:Hide()
        self:ClearFocus()
    end)
    add:SetScript("OnEscapePressed", function(self)
        suggest:Hide()
        self:ClearFocus()
    end)
    window:HookScript("OnHide", function() suggest:Hide() end)

    local function AddTyped(key)
        suggest:Hide()
        local found, ids = ns.Spells:Resolve(add:GetText())
        if not found then
            window:Say(ids)
            return window:Refresh()
        end
        local entry = ns.Spells:Find(found)
        if key == "buff" and entry and (entry.kind == "item" or entry.kind == "slot") then
            window:Say("Items can't go on the Buffs bar.")
            return window:Refresh()
        end
        if ids and not entry then ns.AddCustom(found, ids) end
        local ok
        if key == "buff" then ok = B:SetBuff(found, true) else ok = B:Assign(found, key) end
        ns.PruneCustom()
        local name = entry and entry.name or found
        if ok then
            add:SetText("")
            add:ClearFocus()
            add.placeholder:Show()
            window:Say("Added " .. name .. " to " .. ns.BAR_NAMES[key] .. ".")
        else
            window:Say(ns.BAR_NAMES[key] .. " is full.")
        end
        window:Refresh()
    end
    for i, key in ipairs(ns.BAR_KEYS) do
        local label = key == "cd" and "+ CD" or key == "util" and "+ Util" or "+ Buff"
        local button = T:Button(settingsPanel, label, 52)
        button:SetPoint("TOPLEFT", 8 + (i - 1) * 58, -302)
        button:SetScript("OnClick", function() AddTyped(key) end)
        window.addButtons[key] = button
    end

    -- Refresh --------------------------------------------------------------------
    local function FillRow(row, entry, y, indent, rankText)
        local item = entry.kind == "item" or entry.kind == "slot"
        row:SetHeight(ROW)
        row:SetPoint("TOPLEFT", 0, -y)
        row.spell = entry.key
        row.header:Hide()
        row.icon:ClearAllPoints()
        row.icon:SetPoint("LEFT", indent and 22 or 2, 0)
        row.icon:SetTexture(entry.icon)
        row.name:SetText(indent and entry.rankText or entry.name)
        row.rank:SetText(rankText or "")
        local on = B:Find(entry.key)
        row.cd:SetChecked(on == "cd")
        row.util:SetChecked(on == "util")
        row.buff:SetChecked(B:HasBuff(entry.key))
        for _, part in ipairs({ row.icon, row.name, row.rank }) do part:Show() end
        -- Procs have no cooldown of their own, items no buff, and a fixed rank
        -- adds nothing on the Buffs bar, which already counts every rank.
        row.cd:SetShown(entry.kind ~= "proc")
        row.util:SetShown(entry.kind ~= "proc")
        row.buff:SetShown(not item and entry.kind ~= "rank")
        row:Show()
    end

    local function RefreshSpells()
        local list = ns.Spells:List()
        if #list == 0 then list = ns.Spells:Scan() end
        local listItems, listRanks = ns.Get("listItems"), ns.Get("listRanks")
        local y, n, line = 0, 0, nil
        for _, entry in ipairs(list) do
            local item = entry.kind == "item" or entry.kind == "slot"
            if (listItems or not item) and (state.search == "" or entry.name:lower():find(state.search, 1, true)) then
                if entry.line ~= line and state.search == "" then
                    line = entry.line
                    n = n + 1
                    local header = SpellRow(n)
                    header:SetHeight(HEADER)
                    header:SetPoint("TOPLEFT", 0, -y)
                    header.header:SetText((line or ""):upper())
                    header.header:Show()
                    header.spell = nil
                    for _, part in ipairs({ header.icon, header.name, header.rank, header.cd, header.util, header.buff }) do part:Hide() end
                    header:Show()
                    y = y + HEADER
                end
                local lower = listRanks and entry.lower or {}
                n = n + 1
                FillRow(SpellRow(n), entry, y, false, #lower > 0 and ("Highest (Rank " .. entry.rank .. ")") or entry.rankText)
                y = y + ROW
                -- Lower ranks under the spell, each fixed to that rank.
                for _, fixed in ipairs(lower) do
                    n = n + 1
                    FillRow(SpellRow(n), fixed, y, true, "")
                    y = y + ROW
                end
            end
        end
        for i = n + 1, #spellRows do spellRows[i]:Hide() end
        spellScroll.content:SetHeight(math.max(1, y))
        spellScroll:ScrollTo(spellScroll:GetVerticalScroll() or 0)
    end

    local function RefreshBar()
        segments:SetSelected(state.bar)
        local data = ns.BarData(state.bar)
        local spells = data.spells
        for i, key in ipairs(spells) do
            local row = BarRow(i)
            row.index = i
            row:SetPoint("TOPLEFT", 0, -(i - 1) * (ROW + 2))
            local entry = ns.Spells:Find(key)
            row.icon:SetTexture(entry and entry.icon or 134400) -- question mark until learned
            row.name:SetText(entry and entry.name or key)
            local c = entry and T.TEXT or T.MUTED
            row.name:SetTextColor(c[1], c[2], c[3])
            row.up:SetUsable(i > 1)
            row.down:SetUsable(i < #spells)
            row:Show()
        end
        for i = #spells + 1, #barRows do barRows[i]:Hide() end
        barScroll.content:SetHeight(math.max(1, #spells * (ROW + 2)))
        barScroll:ScrollTo(barScroll:GetVerticalScroll() or 0)
        local word = state.bar == "buff" and "buff" or "icon"
        count:SetText(#spells == 0 and "Empty" or (#spells .. " " .. word .. (#spells == 1 and "" or "s") .. ", left to right"))
        empty:SetShown(#spells == 0)
        empty:SetText(EMPTY[state.bar])
        size:Set(data.size)
        spacing:Set(data.spacing)
        local buffs = state.bar == "buff"
        hideReady:SetShown(not buffs)
        showMissing:SetShown(buffs)
        -- Packed buffs have no fixed spot to put a name under.
        showNames:SetShown(not buffs or data.showMissing)
        hideReady:SetChecked(data.hideReady)
        showMissing:SetChecked(data.showMissing)
        showNames:SetChecked(data.showNames)
        combatOnly:SetChecked(data.combatOnly)
        clear:SetLabel(state.armed == state.bar and "Click again to clear" or ("Clear " .. ns.BAR_NAMES[state.bar]))
    end

    function window:RefreshBars()
        showItems:SetChecked(ns.Get("listItems"))
        showRanks:SetChecked(ns.Get("listRanks"))
        RefreshSpells()
        RefreshBar()
    end
end
