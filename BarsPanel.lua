-- The Classic Bars page of the /ccm window: your spells on the left, ticked
-- onto a bar, and the chosen bar's order and options on the right.
local _, ns = ...
local UI = ns.UI

local ROW, HEADER = 24, 20
local LIST_WIDTH = 338
local BAR_LIST_WIDTH = 270

local function Scroll(parent, width)
    local scroll = CreateFrame("ScrollFrame", nil, parent, "UIPanelScrollFrameTemplate")
    scroll:EnableMouseWheel(true)
    scroll:SetScript("OnMouseWheel", function(self, delta)
        self:SetVerticalScroll(math.max(0, math.min(self:GetVerticalScrollRange(), self:GetVerticalScroll() - delta * ROW * 2)))
    end)
    local content = CreateFrame("Frame", nil, scroll)
    content:SetSize(width, 1)
    scroll:SetScrollChild(content)
    scroll.content = content
    return scroll
end

local function Check(parent)
    local check = CreateFrame("CheckButton", nil, parent, "UICheckButtonTemplate")
    check:SetSize(24, 24)
    return check
end

local function Labelled(parent, label)
    local check = Check(parent)
    check.text = UI.Text(parent, "GameFontHighlight")
    check.text:SetPoint("LEFT", check, "RIGHT", 2, 1)
    check.text:SetText(label)
    return check
end

local function SmallButton(parent, label, width)
    local button = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
    button:SetSize(width or 22, 22)
    button:SetText(label)
    return button
end

-- The Classic scroll arrows (the client only ships modern stand-ins), cropped
-- to the arrow itself.
local function ArrowButton(parent, direction)
    local button = CreateFrame("Button", nil, parent)
    button:SetSize(16, 16)
    local base = ns.MEDIA .. "UI-ScrollBar-Scroll" .. direction .. "Button-"
    button:SetNormalTexture(base .. "Up")
    button:SetPushedTexture(base .. "Down")
    button:SetDisabledTexture(base .. "Disabled")
    button:SetHighlightTexture(base .. "Highlight", "ADD")
    for _, texture in ipairs({ button:GetNormalTexture(), button:GetPushedTexture(),
        button:GetDisabledTexture(), button:GetHighlightTexture() }) do
        texture:SetTexCoord(.25, .75, .25, .75)
    end
    return button
end

-- Steps a number up or down within the bar limits.
local function Stepper(parent, label, limits, step, onChange)
    local stepper = CreateFrame("Frame", nil, parent)
    stepper:SetSize(250, 24)
    local text = UI.Text(stepper, "GameFontHighlight")
    text:SetPoint("LEFT")
    text:SetText(label)
    local minus = SmallButton(stepper, "-")
    minus:SetPoint("LEFT", 110, 0)
    local value = UI.Text(stepper, "GameFontHighlight")
    value:SetPoint("LEFT", minus, "RIGHT", 4, 0)
    value:SetWidth(34)
    value:SetJustifyH("CENTER")
    local plus = SmallButton(stepper, "+")
    plus:SetPoint("LEFT", value, "RIGHT", 4, 0)
    minus:SetScript("OnClick", function() onChange(math.max(limits[1], stepper.current - step)) end)
    plus:SetScript("OnClick", function() onChange(math.min(limits[2], stepper.current + step)) end)
    function stepper:Set(number)
        self.current = number
        value:SetText(number)
    end
    stepper.minus, stepper.plus, stepper.value = minus, plus, value
    return stepper
end

function ns.BuildBarsPage(window, page)
    local B = ns.Bars
    local state = { bar = "cd", search = "" }
    local spellRows, barRows = {}, {}

    -- Top row --------------------------------------------------------------------
    local use = Labelled(page, "Use Classic Bars")
    use:SetPoint("TOPLEFT", 16, -2)
    use:SetScript("OnClick", function(self)
        ns.Set("classicBars", self:GetChecked() and true or false)
        B:Rebuild()
        window:RefreshBars()
    end)

    local reset = SmallButton(page, "Reset positions", 124)
    reset:SetPoint("TOPRIGHT", -18, -2)
    reset:SetScript("OnClick", function() B:ResetPositions() end)
    local unlock = SmallButton(page, "Unlock bars to move", 160)
    unlock:SetPoint("RIGHT", reset, "LEFT", -8, 0)
    unlock:SetScript("OnClick", function()
        if not B:Enabled() then
            state.note = "Tick Use Classic Bars first."
        else
            B:SetUnlocked(not B:IsUnlocked())
        end
        window:RefreshBars()
    end)

    local note = UI.Text(page, "GameFontHighlightSmall", .8, .8, .8)
    note:SetPoint("TOPLEFT", 20, -32)
    note:SetWidth(680)

    -- Your spells ----------------------------------------------------------------
    local left = UI.Box(page)
    left:SetPoint("TOPLEFT", 16, -54)
    left:SetSize(372, 392)
    local spellsTitle = UI.Text(left, "GameFontNormal")
    spellsTitle:SetPoint("TOPLEFT", 10, -9)
    spellsTitle:SetText("Your spells")
    -- Column labels line up with the row ticks (buff 330, util 296, cd 262).
    for x, label in pairs({ [262] = "CD", [296] = "Util", [330] = "Buff" }) do
        local text = UI.Text(left, "GameFontNormalSmall", UI.GREY[1], UI.GREY[2], UI.GREY[3])
        text:SetPoint("CENTER", left, "TOPLEFT", x, -16)
        text:SetText(label)
    end

    local search = CreateFrame("EditBox", nil, left, "InputBoxTemplate")
    search:SetSize(190, 20)
    search:SetPoint("TOPLEFT", 16, -30)
    search:SetAutoFocus(false)
    local hint = UI.Text(search, "GameFontDisable")
    hint:SetPoint("LEFT", 2, 0)
    hint:SetText("Search spells")
    search:SetScript("OnEscapePressed", search.ClearFocus)
    search:SetScript("OnEnterPressed", search.ClearFocus)
    search:SetScript("OnEditFocusGained", function() hint:Hide() end)
    search:SetScript("OnEditFocusLost", function(self) hint:SetShown(self:GetText() == "") end)
    search:SetScript("OnTextChanged", function(self)
        state.search = (self:GetText() or ""):lower()
        window:RefreshBars()
    end)

    local spellScroll = Scroll(left, LIST_WIDTH)
    spellScroll:SetPoint("TOPLEFT", 6, -56)
    spellScroll:SetPoint("BOTTOMRIGHT", -28, 6)

    local function SpellRow(i)
        local row = spellRows[i]
        if row then return row end
        row = CreateFrame("Frame", nil, spellScroll.content)
        row:SetSize(LIST_WIDTH, ROW)
        row.icon = row:CreateTexture(nil, "ARTWORK")
        row.icon:SetSize(20, 20)
        row.icon:SetPoint("LEFT", 4, 0)
        row.name = UI.Text(row, "GameFontHighlight")
        row.name:SetPoint("LEFT", row.icon, "RIGHT", 6, 0)
        row.rank = UI.Text(row, "GameFontHighlightSmall", UI.GREY[1], UI.GREY[2], UI.GREY[3])
        row.rank:SetPoint("LEFT", row.name, "RIGHT", 6, 0)
        row.header = UI.Text(row, "GameFontNormalSmall", UI.GREY[1], UI.GREY[2], UI.GREY[3])
        row.header:SetPoint("BOTTOMLEFT", 4, 3)
        row.buff = Check(row)
        row.buff:SetPoint("RIGHT", -2, 0)
        row.util = Check(row)
        row.util:SetPoint("RIGHT", row.buff, "LEFT", -10, 0)
        row.cd = Check(row)
        row.cd:SetPoint("RIGHT", row.util, "LEFT", -10, 0)
        row.buff:SetScript("OnClick", function(self)
            if not B:SetBuff(row.spell, self:GetChecked() and true or false) then
                state.note = ns.BAR_NAMES.buff .. " is full."
            end
            window:RefreshBars()
        end)
        local function Tick(self, key)
            if not B:Assign(row.spell, self:GetChecked() and key or nil) then
                state.note = ns.BAR_NAMES[key] .. " is full."
            end
            window:RefreshBars()
        end
        row.cd:SetScript("OnClick", function(self) Tick(self, "cd") end)
        row.util:SetScript("OnClick", function(self) Tick(self, "util") end)
        spellRows[i] = row
        return row
    end

    -- The chosen bar -------------------------------------------------------------
    local right = UI.Box(page)
    right:SetPoint("TOPLEFT", left, "TOPRIGHT", 12, 0)
    right:SetSize(304, 392)
    local barTabs = {}
    local previous
    for _, key in ipairs(ns.BAR_KEYS) do
        local tab = UI.Tab(right, ns.BAR_NAMES[key], function()
            state.bar = key
            window:RefreshBars()
        end)
        if previous then tab:SetPoint("LEFT", previous, "RIGHT", 4, 0) else tab:SetPoint("TOPLEFT", 6, -4) end
        previous = tab
        barTabs[key] = tab
    end

    local barScroll = Scroll(right, BAR_LIST_WIDTH)
    barScroll:SetPoint("TOPLEFT", 6, -34)
    barScroll:SetPoint("BOTTOMRIGHT", -28, 150)
    local empty = UI.Text(right, "GameFontHighlightSmall", UI.GREY[1], UI.GREY[2], UI.GREY[3])
    empty:SetPoint("TOPLEFT", 14, -44)
    empty:SetWidth(270)
    local EMPTY = {
        cd = "Tick CD on spells to add them to this bar.",
        util = "Tick Util on spells to add them to this bar.",
        buff = "Tick Buff on spells that put a buff on you, or on your class procs at the bottom of the list.",
    }

    local function BarRow(i)
        local row = barRows[i]
        if row then return row end
        row = CreateFrame("Frame", nil, barScroll.content)
        row:SetSize(BAR_LIST_WIDTH, ROW)
        row.icon = row:CreateTexture(nil, "ARTWORK")
        row.icon:SetSize(20, 20)
        row.icon:SetPoint("LEFT", 4, 0)
        row.name = UI.Text(row, "GameFontHighlight")
        row.name:SetPoint("LEFT", row.icon, "RIGHT", 6, 0)
        row.name:SetWidth(170)
        row.remove = UI.CloseX(row, function() B:Remove(state.bar, row.index); window:RefreshBars() end, 20)
        row.remove:SetPoint("RIGHT", -2, 0)
        row.down = ArrowButton(row, "Down")
        row.down:SetPoint("RIGHT", row.remove, "LEFT", -4, 0)
        row.down:SetScript("OnClick", function() B:Move(state.bar, row.index, 1); window:RefreshBars() end)
        row.up = ArrowButton(row, "Up")
        row.up:SetPoint("RIGHT", row.down, "LEFT", -2, 0)
        row.up:SetScript("OnClick", function() B:Move(state.bar, row.index, -1); window:RefreshBars() end)
        barRows[i] = row
        return row
    end

    local size = Stepper(right, "Icon size", ns.BAR_LIMITS.size, 2, function(value)
        B:SetOption(state.bar, "size", value)
        window:RefreshBars()
    end)
    size:SetPoint("BOTTOMLEFT", 12, 112)
    local spacing = Stepper(right, "Spacing", ns.BAR_LIMITS.spacing, 1, function(value)
        B:SetOption(state.bar, "spacing", value)
        window:RefreshBars()
    end)
    spacing:SetPoint("BOTTOMLEFT", 12, 84)
    local hideReady = Labelled(right, "Hide when ready")
    hideReady:SetPoint("BOTTOMLEFT", 8, 44)
    hideReady:SetScript("OnClick", function(self)
        B:SetOption(state.bar, "hideReady", self:GetChecked() and true or false)
        window:RefreshBars()
    end)
    -- Buffs only show while they're on you, so their bar offers this instead.
    local showMissing = Labelled(right, "Show missing buffs greyed")
    showMissing:SetPoint("BOTTOMLEFT", 8, 44)
    showMissing:SetScript("OnClick", function(self)
        B:SetOption(state.bar, "showMissing", self:GetChecked() and true or false)
        window:RefreshBars()
    end)
    local combatOnly = Labelled(right, "Only in combat")
    combatOnly:SetPoint("BOTTOMLEFT", 8, 16)
    combatOnly:SetScript("OnClick", function(self)
        B:SetOption(state.bar, "combatOnly", self:GetChecked() and true or false)
        window:RefreshBars()
    end)

    -- Refresh --------------------------------------------------------------------
    local function RefreshSpells()
        local list = ns.Spells:List()
        if #list == 0 then list = ns.Spells:Scan() end
        local y, count, line = 0, 0, nil
        for _, entry in ipairs(list) do
            if state.search == "" or entry.name:lower():find(state.search, 1, true) then
                if entry.line ~= line and state.search == "" then
                    line = entry.line
                    count = count + 1
                    local header = SpellRow(count)
                    header:SetHeight(HEADER)
                    header:SetPoint("TOPLEFT", 0, -y)
                    header.header:SetText(line)
                    header.header:Show()
                    for _, part in ipairs({ header.icon, header.name, header.rank, header.cd, header.util, header.buff }) do part:Hide() end
                    header:Show()
                    y = y + HEADER
                end
                count = count + 1
                local row = SpellRow(count)
                row:SetHeight(ROW)
                row:SetPoint("TOPLEFT", 0, -y)
                row.spell = entry.name
                row.header:Hide()
                row.icon:SetTexture(entry.icon)
                row.name:SetText(entry.name)
                row.rank:SetText(entry.rankText or "")
                local on = B:Find(entry.name)
                row.cd:SetChecked(on == "cd")
                row.util:SetChecked(on == "util")
                row.buff:SetChecked(B:HasBuff(entry.name))
                for _, part in ipairs({ row.icon, row.name, row.rank, row.buff }) do part:Show() end
                -- Procs have no cooldown of their own, only a buff.
                row.cd:SetShown(not entry.proc)
                row.util:SetShown(not entry.proc)
                row:Show()
                y = y + ROW
            end
        end
        for i = count + 1, #spellRows do spellRows[i]:Hide() end
        spellScroll.content:SetHeight(math.max(1, y))
    end

    local function RefreshBar()
        for key, tab in pairs(barTabs) do tab:SetSelected(key == state.bar) end
        local data = ns.BarData(state.bar)
        for i, name in ipairs(data.spells) do
            local row = BarRow(i)
            row.index = i
            row:SetPoint("TOPLEFT", 0, -(i - 1) * ROW)
            local entry = ns.Spells:Find(name)
            row.icon:SetTexture(entry and entry.icon or 134400) -- question mark until learned
            row.name:SetText(name)
            local c = entry and 1 or .5
            row.name:SetTextColor(c, c, c)
            row.up:SetEnabled(i > 1)
            row.down:SetEnabled(i < #data.spells)
            row:Show()
        end
        for i = #data.spells + 1, #barRows do barRows[i]:Hide() end
        barScroll.content:SetHeight(math.max(1, #data.spells * ROW))
        empty:SetShown(#data.spells == 0)
        empty:SetText(EMPTY[state.bar])
        size:Set(data.size)
        spacing:Set(data.spacing)
        local buffs = state.bar == "buff"
        hideReady:SetShown(not buffs)
        hideReady.text:SetShown(not buffs)
        showMissing:SetShown(buffs)
        showMissing.text:SetShown(buffs)
        hideReady:SetChecked(data.hideReady)
        showMissing:SetChecked(data.showMissing)
        combatOnly:SetChecked(data.combatOnly)
    end

    function window:RefreshBars()
        local on = B:Enabled()
        use:SetChecked(on)
        unlock:SetText(B:IsUnlocked() and "Lock bars" or "Unlock bars to move")
        note:SetText(state.note or "Tick CD or Util for cooldowns, and Buff for buffs on you. Each spell shows once, at your highest rank.")
        state.note = nil
        RefreshSpells()
        RefreshBar()
    end
end
