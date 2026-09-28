-- The Layout page in the /fecm window: one-click layouts for your bars, and
-- the stack they make around Blizzard's Personal Resource Display, drawn to
-- scale with your own icons in it. Drag a spell from your spellbook onto a
-- row to add it; hover a row for - and + (how many icons fit across) and the
-- arrows (up or down the stack, past the display).
local _, ns = ...
local T = ns.Theme

local CARD_W, CARD_H, CARD_GAP = 80, 66, 6
local TILE_GAP = 2
local EDGE = 118 -- room beside a row for its name and buttons
local SCALE = .7 -- the drawing's largest scale
local HEALTH, POWER = { .1, .8, .1 }, { 0, .5, 1 } -- Blizzard's own colours
local HINT = "- and + change how many fit across; the arrows swap rows. Drag an icon to another row, or off to remove it."

-- A small square button with an arrow on it, in the accent.
local function Arrow(parent, up)
    local button = T:Square(parent, "")
    local art = button:CreateTexture(nil, "ARTWORK")
    art:SetSize(12, 12)
    art:SetPoint("CENTER")
    art:SetTexture(ns.MEDIA .. (up and "UI-ScrollBar-ScrollUpButton-Up" or "UI-ScrollBar-ScrollDownButton-Up"))
    art:SetTexCoord(.25, .75, .25, .75)
    art:SetDesaturated(true)
    T:Paint(function(accent) art:SetVertexColor(accent[1], accent[2], accent[3]) end)
    button.art = art
    return button
end

-- A preset in miniature: its rows as tiny tiles around the display.
local function Thumbnail(card, preset)
    local tile, gap = 3, 1
    local above, below, sides, widest = {}, {}, {}, 0
    for _, row in ipairs(preset.rows) do
        if row.place == "above" then
            above[#above + 1] = row.across
        elseif row.place == "below" then
            below[#below + 1] = row.across
        else
            sides[row.place] = row.across
        end
        if row.place == "above" or row.place == "below" then widest = math.max(widest, row.across) end
    end
    local function Width(across) return across * (tile + gap) - gap end
    local lines = #above + #below
    local y = -(8 + math.floor((40 - (lines * (tile + 2) + 5)) / 2))
    local function Tiles(across, left)
        for i = 1, across do
            local square = card:CreateTexture(nil, "ARTWORK")
            square:SetSize(tile, tile)
            square:SetPoint("TOPLEFT", card, "TOP", left + (i - 1) * (tile + gap), y)
            square:SetColorTexture(T.TEXT[1], T.TEXT[2], T.TEXT[3], .55)
        end
    end
    for _, across in ipairs(above) do
        Tiles(across, -Width(across) / 2)
        y = y - tile - 2
    end
    local display = card:CreateTexture(nil, "ARTWORK")
    display:SetSize(Width(widest), 3)
    display:SetPoint("TOP", card, "TOP", 0, y)
    T:Paint(function(accent) T:Fill(display, accent) end)
    if sides.left then Tiles(sides.left, -Width(widest) / 2 - 2 - Width(sides.left)) end
    if sides.right then Tiles(sides.right, Width(widest) / 2 + 2) end
    y = y - 5
    for _, across in ipairs(below) do
        Tiles(across, -Width(across) / 2)
        y = y - tile - 2
    end
end

function ns.BuildLayoutPage(window, page, width, height)
    local L, B = ns.Layout, ns.Bars
    local inner = width - 32
    local selected -- the row whose buttons stay up after a click
    local function Note(text) window.note:SetText(text) end
    local function Unnote() window.note:SetText(window.lastNote or "") end
    local function Done(_, message)
        if message then window:Say(message) end
        window:Refresh()
    end

    -- Title row: how things stand, with Undo and a way to stop or start.
    local title = T:Heading(page, "Layout")
    title:SetPoint("TOPLEFT", 16, -16)
    local status = T:Text(page, "GameFontHighlightSmall", T.MUTED)
    status:SetPoint("LEFT", title, "RIGHT", 10, 0)
    local turnOn = T:Button(page, "Turn on", 70, 18)
    turnOn:SetPoint("LEFT", status, "RIGHT", 8, 0)
    turnOn:SetScript("OnClick", function()
        ns.Set("useBars", true)
        B:Rebuild()
        window:Refresh()
    end)
    local toggle = T:Button(page, "", 90, 20)
    toggle:SetPoint("TOPRIGHT", -16, -12)
    toggle:SetScript("OnClick", function()
        if L:Active() then
            L:TurnOff()
            Done(true, "Your bars stay where they are now.")
        else
            Done(L:LineUp())
        end
    end)
    local undo = T:Button(page, "Undo", 70, 20)
    undo:SetPoint("RIGHT", toggle, "LEFT", -6, 0)
    undo:SetScript("OnClick", function() Done(L:Undo()) end)
    page.status, page.turnOn, page.toggle, page.undo = status, turnOn, toggle, undo

    -- The presets, each drawn in miniature.
    local cards = {}
    for i, preset in ipairs(L.PRESETS) do
        local card = CreateFrame("Button", nil, page, "BackdropTemplate")
        card:SetSize(CARD_W, CARD_H)
        card:SetPoint("TOPLEFT", 16 + (i - 1) * (CARD_W + CARD_GAP), -38)
        T:Flat(card, T.PANEL, T.BORDER)
        local hover = card:CreateTexture(nil, "HIGHLIGHT")
        hover:SetAllPoints()
        hover:SetColorTexture(1, 1, 1, .05)
        Thumbnail(card, preset)
        card.label = T:Text(card, "GameFontHighlightSmall")
        card.label:SetPoint("BOTTOM", 0, 7)
        card.label:SetJustifyH("CENTER")
        card.label:SetText(preset.name)
        card.key = preset.key
        card:SetScript("OnClick", function() Done(L:Apply(preset.key)) end)
        card:SetScript("OnEnter", function() Note(preset.name .. ": " .. preset.about) end)
        card:SetScript("OnLeave", Unnote)
        cards[i] = card
    end
    page.cards = cards

    -- The stack, drawn to scale with your own icons.
    local top = 38 + CARD_H + 12
    local box = CreateFrame("Frame", nil, page, "BackdropTemplate")
    box:SetPoint("TOPLEFT", 16, -top)
    box:SetPoint("BOTTOMRIGHT", -16, 64)
    T:Box(box)
    page.box = box
    local boxWidth, boxHeight = inner - 16, height - top - 64

    local drag = T:Text(box, "GameFontHighlightSmall", T.MUTED)
    drag:SetPoint("TOPLEFT", 12, -10)
    drag:SetText("Drag spells from your spellbook onto a row. Hover a row to change it.")
    page.dragHint = drag

    local rows = {}
    page.rows = rows
    local display -- the resource display, drawn between the rows
    local function Hovered(row)
        return row:IsMouseOver() or row.buttons:IsMouseOver() or selected == row.key
    end
    -- The buttons show while the row is hovered or chosen; beside the display
    -- they take the place of the row's name.
    local function ShowButtons(row)
        local on = Hovered(row)
        row.hover:SetShown(on)
        row.buttons:SetShown(on)
        if row.name then
            local named = not (on and row.place ~= "stack")
            row.name:SetShown(named)
            row.across:SetShown(named)
        end
    end
    local function Buttons(owner, width)
        owner.buttons = CreateFrame("Frame", nil, owner)
        owner.buttons:SetSize(width, 18)
        return function(button, x, onClick)
            button:SetPoint("LEFT", x, 0)
            button:SetScript("OnClick", function()
                selected = owner.key
                onClick()
            end)
            button:HookScript("OnEnter", function() ShowButtons(owner) end)
            button:HookScript("OnLeave", function() ShowButtons(owner) end)
            return button
        end
    end

    -- An icon being dragged follows the cursor: onto another row it moves
    -- there, anywhere else it comes off its bar.
    local ghost = CreateFrame("Frame", nil, page)
    ghost:SetSize(24, 24)
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
    local picked -- { from = bar, name = entry } while an icon is dragged
    local function DropPicked()
        ghost:Hide()
        local from = picked
        picked = nil
        if not from then return end
        local target
        for key, row in pairs(rows) do
            if row:IsShown() and row:IsMouseOver() then target = key end
        end
        if target == from.bar then return window:Refresh() end
        if target then
            Done(B:Transfer(from.bar, target, from.name))
        else
            Done(B:TakeOff(from.bar, from.name))
        end
    end

    local function Tile(row, i)
        local tile = row.tiles[i]
        if tile then return tile end
        tile = CreateFrame("Button", nil, row.strip)
        tile:SetSize(10, 10)
        tile.texture = tile:CreateTexture(nil, "ARTWORK")
        tile.texture:SetAllPoints()
        tile:RegisterForDrag("LeftButton")
        tile:SetScript("OnDragStart", function(self)
            if not self.name then return end
            picked = { bar = row.key, name = self.name }
            ghost.texture:SetTexture(self.texture:GetTexture())
            ghost:Show()
            -- Picked up: its spot is empty until it lands somewhere.
            T:Fill(self.texture, T.CONTROL_BORDER)
        end)
        tile:SetScript("OnDragStop", function()
            DropPicked()
        end)
        -- A spell from your spellbook dropped here joins the row's bar.
        tile:SetScript("OnReceiveDrag", function() B:Dropped(row.key) end)
        tile:SetScript("OnClick", function()
            if B:Dropped(row.key) then return end
            selected = row.key
            window:Refresh()
        end)
        tile:SetScript("OnEnter", function(self)
            ShowButtons(row)
            local entry = self.name and ns.Spells:Find(self.name)
            Note(entry and (entry.name .. ". Drag it to another row, or off to remove it.") or HINT)
        end)
        tile:SetScript("OnLeave", function()
            ShowButtons(row)
            Unnote()
        end)
        row.tiles[i] = tile
        return tile
    end

    local function Row(key)
        if rows[key] then return rows[key] end
        local row = CreateFrame("Button", nil, box)
        row:SetSize(boxWidth, 20) -- sized again on every refresh
        row.key = key
        row.hover = row:CreateTexture(nil, "BACKGROUND")
        row.hover:SetAllPoints()
        row.hover:SetColorTexture(1, 1, 1, .05)
        row.strip = CreateFrame("Frame", nil, row)
        row.strip:SetSize(10, 10)
        row.strip:EnableMouse(false)
        row.tiles = {}
        row.name = T:Text(row, "GameFontHighlightSmall")
        row.name:SetText(ns.BAR_NAMES[key])
        row.across = T:Text(row, "GameFontHighlightSmall", T.MUTED)
        row.more = T:Text(row, "GameFontHighlightSmall", T.MUTED)
        local Button = Buttons(row, 84)
        row.fewer = Button(T:Square(row.buttons, "-", true), 0, function()
            Done(L:SetAcross(key, ns.BarData(key).perRow - 1))
        end)
        row.wider = Button(T:Square(row.buttons, "+", true), 22, function()
            Done(L:SetAcross(key, ns.BarData(key).perRow + 1))
        end)
        row.up = Button(Arrow(row.buttons, true), 44, function() Done(L:Swap(key, -1)) end)
        row.down = Button(Arrow(row.buttons, false), 66, function() Done(L:Swap(key, 1)) end)
        row:SetScript("OnEnter", function(self)
            ShowButtons(self)
            Note(HINT)
        end)
        row:SetScript("OnLeave", function(self)
            ShowButtons(self)
            Unnote()
        end)
        -- A spell dropped on a row joins that bar; a click without one
        -- keeps the row's buttons up.
        row:SetScript("OnReceiveDrag", function(self) B:Dropped(self.key) end)
        row:SetScript("OnClick", function(self)
            if B:Dropped(self.key) then return end
            selected = self.key
            window:Refresh()
        end)
        rows[key] = row
        return row
    end

    -- The display, with arrows to move it up or down the stack.
    display = CreateFrame("Button", nil, box)
    display:SetSize(100, 14)
    display.key = "display"
    display.hover = display:CreateTexture(nil, "BACKGROUND")
    display.hover:SetPoint("TOPLEFT", -3, 3)
    display.hover:SetPoint("BOTTOMRIGHT", 3, -3)
    display.hover:SetColorTexture(1, 1, 1, .05)
    display.health = display:CreateTexture(nil, "ARTWORK")
    display.health:SetPoint("TOPLEFT")
    display.health:SetPoint("TOPRIGHT")
    display.health:SetHeight(8)
    display.power = display:CreateTexture(nil, "ARTWORK")
    display.power:SetPoint("BOTTOMLEFT")
    display.power:SetPoint("BOTTOMRIGHT")
    display.power:SetHeight(5)
    local Button = Buttons(display, 40)
    display.buttons:SetPoint("LEFT", display, "RIGHT", 8, 0)
    display.up = Button(Arrow(display.buttons, true), 0, function() Done(L:MoveDisplay(-1)) end)
    display.down = Button(Arrow(display.buttons, false), 22, function() Done(L:MoveDisplay(1)) end)
    local DISPLAY_NOTE = "Your Personal Resource Display. The arrows move it up or down the stack; move it on screen in Edit Mode."
    display:SetScript("OnEnter", function(self)
        ShowButtons(self)
        Note(DISPLAY_NOTE)
    end)
    display:SetScript("OnLeave", function(self)
        ShowButtons(self)
        Unnote()
    end)
    display:SetScript("OnClick", function(self)
        selected = self.key
        window:Refresh()
    end)
    page.display = display

    -- What's on a bar, in order: joined buff entries count once.
    local function Entries(key)
        local list = {}
        if ns.AURA_BARS[key] then
            for _, unit in ipairs(B:Units(key)) do list[#list + 1] = unit[1] end
        else
            for _, name in ipairs(ns.BarData(key).spells) do list[#list + 1] = name end
        end
        return list
    end

    -- A row's tiles: your icons, then empty spots up to how many fit across.
    local function Fill(row, size, fromRight)
        local data, entries = ns.BarData(row.key), Entries(row.key)
        for i = 1, data.perRow do
            local tile = Tile(row, i)
            tile:SetSize(size, size)
            tile:ClearAllPoints()
            local offset = (i - 1) * (size + TILE_GAP)
            if fromRight then
                tile:SetPoint("TOPRIGHT", row.strip, "TOPRIGHT", -offset, 0)
            else
                tile:SetPoint("TOPLEFT", row.strip, "TOPLEFT", offset, 0)
            end
            local name = entries[i]
            tile.name = name
            if name then
                local entry = ns.Spells:Find(name)
                tile.texture:SetTexture(entry and entry.icon or 134400) -- question mark until learned
                ns.Style:Zoom(tile.texture)
            else
                T:Fill(tile.texture, T.CONTROL_BORDER)
            end
            tile:Show()
        end
        for i = data.perRow + 1, #row.tiles do row.tiles[i]:Hide() end
        row.strip:SetSize(data.perRow * size + (data.perRow - 1) * TILE_GAP, size)
        row.more:SetText(#entries > data.perRow and ("+" .. (#entries - data.perRow)) or "")
        row.across:SetText(data.perRow .. " across")
        row.fewer:SetUsable(data.perRow > ns.BAR_LIMITS.perRow[1])
        row.wider:SetUsable(data.perRow < ns.BAR_LIMITS.perRow[2])
        row.up:SetUsable(L:CanSwap(row.key, -1))
        row.down:SetUsable(L:CanSwap(row.key, 1))
    end

    -- A row across the middle, its name on the left and buttons on the right.
    local function Stacked(row, y, tile)
        row.place = "stack"
        row:ClearAllPoints()
        row:SetPoint("TOPLEFT", box, "TOPLEFT", 8, -y)
        row:SetSize(boxWidth, tile)
        row.strip:ClearAllPoints()
        row.strip:SetPoint("CENTER")
        row.name:ClearAllPoints()
        row.name:SetPoint("LEFT", 10, 0)
        row.across:ClearAllPoints()
        row.across:SetPoint("LEFT", row.name, "RIGHT", 5, 0)
        row.buttons:ClearAllPoints()
        row.buttons:SetPoint("RIGHT", -8, 0)
        row.more:ClearAllPoints()
        row.more:SetPoint("LEFT", row.strip, "RIGHT", 6, 0)
        Fill(row, tile, false)
    end

    -- A row beside the display: tiles against it, name and buttons outside.
    local function Beside(row, side, y, tile, lineHeight, displayWidth, gap)
        row.place = side
        local rowWidth = (boxWidth - displayWidth) / 2 - gap
        row:ClearAllPoints()
        row:SetSize(rowWidth, lineHeight)
        row.strip:ClearAllPoints()
        row.name:ClearAllPoints()
        row.across:ClearAllPoints()
        row.buttons:ClearAllPoints()
        row.more:ClearAllPoints()
        if side == "left" then
            row:SetPoint("TOPLEFT", box, "TOPLEFT", 8, -y)
            row.strip:SetPoint("RIGHT")
            row.name:SetPoint("LEFT", 10, 0)
            row.across:SetPoint("LEFT", row.name, "RIGHT", 5, 0)
            row.buttons:SetPoint("LEFT", 8, 0)
            row.more:SetPoint("RIGHT", row.strip, "LEFT", -6, 0)
        else
            row:SetPoint("TOPRIGHT", box, "TOPRIGHT", -8, -y)
            row.strip:SetPoint("LEFT")
            row.across:SetPoint("RIGHT", -10, 0)
            row.name:SetPoint("RIGHT", row.across, "LEFT", -5, 0)
            row.buttons:SetPoint("RIGHT", -8, 0)
            row.more:SetPoint("LEFT", row.strip, "RIGHT", 6, 0)
        end
        Fill(row, tile, side == "left")
    end

    local function Draw()
        local layout = ns.LayoutData()
        local function Real(key)
            local data = ns.BarData(key)
            return data.perRow * data.size + (data.perRow - 1) * data.spacing
        end
        -- The display: as wide as the widest row when it's to match,
        -- otherwise as it is now.
        local displayReal = ns.Get("prdMatch") and L:WidestRow()
        if not displayReal then
            local shown = L:Display()
            displayReal = shown and shown.width or 200
        end
        -- One scale for everything, so the rows keep their proportions and
        -- sit together as they will on screen, with your row spacing.
        local widest, middle = displayReal, displayReal
        for _, place in ipairs({ "above", "below" }) do
            for _, key in ipairs(layout[place]) do widest = math.max(widest, Real(key)) end
        end
        for _, side in ipairs({ "left", "right" }) do
            if layout[side] then middle = middle + layout.gap + Real(layout[side]) end
        end
        local scale = math.min(SCALE, (boxWidth - 2 * EDGE) / math.max(1, widest, middle))
        local function Tile(key) return math.max(6, math.floor(ns.BarData(key).size * scale)) end
        local gap = math.floor(layout.gap * scale + .5)
        local displayWidth = math.floor(displayReal * scale)
        local shown = L:Display()
        local displayHeight = math.max(6, math.floor((shown and shown.height or 20) * scale + .5))
        local sideTile = 0
        for _, side in ipairs({ "left", "right" }) do
            if layout[side] then sideTile = math.max(sideTile, Tile(layout[side])) end
        end
        local lineHeight = math.max(displayHeight, sideTile)
        local total = lineHeight
        for _, place in ipairs({ "above", "below" }) do
            for _, key in ipairs(layout[place]) do total = total + Tile(key) + gap end
        end
        local y = math.max(28, math.floor((boxHeight - total) / 2))
        for _, key in ipairs(layout.above) do
            Stacked(Row(key), y, Tile(key))
            y = y + Tile(key) + gap
        end
        display:ClearAllPoints()
        display:SetPoint("TOP", box, "TOP", 0, -(y + (lineHeight - displayHeight) / 2))
        display:SetSize(math.max(20, displayWidth), displayHeight)
        display.health:SetHeight(math.max(2, math.ceil(displayHeight * .6)))
        display.power:SetHeight(math.max(2, displayHeight - math.ceil(displayHeight * .6) - 1))
        for _, side in ipairs({ "left", "right" }) do
            if layout[side] then Beside(Row(layout[side]), side, y, Tile(layout[side]), lineHeight, displayWidth, gap) end
        end
        y = y + lineHeight + gap
        for _, key in ipairs(layout.below) do
            Stacked(Row(key), y, Tile(key))
            y = y + Tile(key) + gap
        end
        local health, power = ns.Get("prdHealth"), ns.Get("prdPower")
        T:Fill(display.health, health ~= "default" and ns.Style:BarColour(health) or HEALTH)
        T:Fill(display.power, power ~= "default" and ns.Style:BarColour(power) or POWER)
        display.up:SetUsable(L:CanMoveDisplay(-1))
        display.down:SetUsable(L:CanMoveDisplay(1))
        for _, row in pairs(rows) do ShowButtons(row) end
        ShowButtons(display)
    end

    -- Below the box: the display, and the space between rows and icons.
    local function Tick(label, y, note, onClick)
        local check = T:Check(page, label, onClick)
        check:SetPoint("BOTTOMLEFT", 16, y)
        check:HookScript("OnEnter", function() Note(note) end)
        check:HookScript("OnLeave", Unnote)
        return check
    end
    local shown = Tick("Show the Personal Resource Display", 36,
        "Blizzard's display, as in Options > Combat. Off, your rows close up where it was.", function(self)
            local on, why
            if self:GetChecked() then on, why = ns.TurnOn("nameplateShowSelf") else on, why = ns.TurnOff("nameplateShowSelf") end
            if not on then window:Say(why or "It couldn't be changed here: Options > Combat > Personal Resource Display.") end
            L:Stack()
            window:Refresh()
        end)
    page.shown = shown
    local match = Tick("Match the resource display to my rows", 14,
        "While your bars are stacked, the display is as wide as your widest row. Off, it keeps Blizzard's Bar Width from Edit Mode.",
        function(self)
            ns.Set("prdMatch", self:GetChecked())
            if L:Active() then L:Stack() elseif ns.Resource then ns.Resource:Match() end
            window:Refresh()
        end)
    page.match = match
    -- Rows and icons touch unless you give them room.
    local function Spacing(label, limits, y, set)
        local slider = T:Slider(page, label, limits, 1, 250, function(value)
            local _, message = set(value)
            if message then window:Say(message) end
            window:Refresh()
        end)
        slider:SetPoint("BOTTOMRIGHT", -16, y)
        return slider
    end
    local spacing = Spacing("Row spacing", ns.ROW_GAP, 34, function(value) return L:SetGap(value) end)
    local iconSpacing = Spacing("Icon spacing", ns.ICON_GAP, 12, function(value) return L:SetSpacing(value) end)
    page.spacing, page.iconSpacing = spacing, iconSpacing

    local function Refresh()
        local layout, active, on = ns.LayoutData(), L:Active(), B:Enabled()
        local text, colour, barsOff = nil, T.MUTED, false
        if not on then
            text, colour, barsOff = "Your bars are off.", T.WARN, true
        elseif active and not ns.PersonalDisplayOn() then
            text = "Your rows sit together where your resource display would be."
        elseif active then
            text = "Your bars follow your Personal Resource Display."
        elseif L.moved then
            text = "You moved a bar, so they're no longer stacked."
        elseif layout.preset then
            text = "Your bars stay where you put them."
        else
            text = "Pick a layout to stack your bars around your resource display."
        end
        status:SetText(text)
        status:SetTextColor(colour[1], colour[2], colour[3])
        turnOn:SetShown(barsOff)
        toggle:SetShown(on)
        toggle:SetLabel(active and "Turn off" or "Line up")
        undo:SetShown(L.undo ~= nil)
        for _, card in ipairs(cards) do
            local border = active and layout.preset == card.key and T:Accent() or T.BORDER
            card:SetBackdropBorderColor(border[1], border[2], border[3], 1)
        end
        match:SetChecked(ns.Get("prdMatch"))
        shown:SetChecked(ns.PersonalDisplayOn())
        spacing:Set(layout.gap)
        iconSpacing:Set(layout.spacing)
        Draw()
    end

    -- A failure is reported once in chat instead of leaving the page half drawn.
    function page:Refresh()
        local ok, err = pcall(Refresh)
        page.drawError = not ok and tostring(err) or nil
        if not ok and not page.reported then
            page.reported = true
            print("|cffffd100" .. ns.TITLE .. ":|r the Layout page couldn't be drawn. Please report this: " .. page.drawError)
        end
    end
end
