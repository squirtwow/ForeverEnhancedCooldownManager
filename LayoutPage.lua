-- The Layout page in the /ccm window: one-click layouts for your bars, and
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
    -- Reset asks first: it puts the preset back as it was first set up.
    local reset = T:Button(page, "Reset", 70, 20)
    reset:SetPoint("RIGHT", toggle, "LEFT", -6, 0)
    reset:SetScript("OnClick", function()
        local base = L:Preset(ns.LayoutData().base) or L.PRESETS[1]
        window:Ask("Reset your layout?", "Back to " .. base.name
            .. " as first set up: every bar in, no room between rows or icons. Your spells and icon sizes stay.",
            "Reset", function() Done(L:Reset()) end)
    end)
    local undo = T:Button(page, "Undo", 70, 20)
    undo:SetPoint("RIGHT", reset, "LEFT", -6, 0)
    undo:SetScript("OnClick", function() Done(L:Undo()) end)
    page.status, page.turnOn, page.toggle, page.reset, page.undo = status, turnOn, toggle, reset, undo

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

    local DRAG = "Drag spells from your spellbook onto a row. Hover a row to change it."
    local drag = T:Text(box, "GameFontHighlightSmall", T.MUTED)
    drag:SetPoint("TOPLEFT", 12, -10)
    drag:SetText(DRAG)
    page.dragHint = drag

    -- Bars taken out of the layout, each with a button to put it back.
    local outLabel = T:Text(box, "GameFontHighlightSmall", T.MUTED)
    outLabel:SetPoint("BOTTOMLEFT", 12, 12)
    outLabel:SetText("Put back:")
    local outButtons = {}
    for _, key in ipairs(ns.BAR_KEYS) do
        local button = T:Button(box, "+ " .. ns.BAR_NAMES[key], 84, 18)
        button:SetPoint("BOTTOMLEFT", 80, 9)
        button:SetScript("OnClick", function() Done(L:PutBack(key)) end)
        button:HookScript("OnEnter", function() Note("Put " .. ns.BAR_NAMES[key] .. " back in your layout.") end)
        button:HookScript("OnLeave", Unnote)
        outButtons[key] = button
    end
    page.outButtons = outButtons

    -- Moving the bars by hand, and back to where they started.
    local home = T:Button(box, "Reset positions", 100, 18)
    home:SetPoint("BOTTOMRIGHT", -12, 9)
    home:SetScript("OnClick", function()
        B:ResetPositions()
        Done(true, "Bars moved back above your action bar. Line up stacks them again.")
    end)
    home:HookScript("OnEnter", function() Note("Puts your bars back above your action bar, out of the layout.") end)
    home:HookScript("OnLeave", Unnote)
    local unlock = T:Button(box, "Unlock bars", 90, 18)
    unlock:SetPoint("RIGHT", home, "LEFT", -6, 0)
    unlock:SetScript("OnClick", function()
        if not B:Enabled() then
            window:Say("Turn your bars on first.")
        else
            B:SetUnlocked(not B:IsUnlocked())
        end
        window:Refresh()
    end)
    unlock:HookScript("OnEnter", function()
        Note("Drag your bars anywhere on screen. Moving one stops the layout. Closing this window locks them again.")
    end)
    unlock:HookScript("OnLeave", Unnote)
    page.unlock, page.home = unlock, home
    -- Where the Taken out buttons wrap, clear of these two.
    local OUT_RIGHT = inner - 12 - 100 - 6 - 90 - 6

    -- Find a debuff: only your class's, then click the spot it goes in the
    -- Debuffs row.
    local placing -- the debuff picked, waiting for its spot
    local Pick
    local MAX_RESULTS = 8
    local search = T:Input(box, "Find a debuff to track", 200)
    search:SetPoint("TOPRIGHT", -12, -6)
    local cancel = T:Button(box, "Cancel", 70, 20)
    cancel:SetPoint("TOPRIGHT", -12, -6)
    cancel:SetScript("OnClick", function()
        placing = nil
        window:Refresh()
    end)
    local results = CreateFrame("Frame", nil, box, "BackdropTemplate")
    results:SetPoint("TOPRIGHT", search, "BOTTOMRIGHT", 0, -2)
    results:SetSize(200, 24)
    results:SetFrameLevel(box:GetFrameLevel() + 40)
    results:EnableMouse(true)
    T:Flat(results, T.PANEL, T.CONTROL_BORDER)
    results:Hide()
    local more = T:Text(results, "GameFontHighlightSmall", T.MUTED)
    local found = {}
    page.search, page.results, page.found, page.cancel = search, results, found, cancel

    -- Your class's debuffs matching the text, the ones you know first.
    local function Debuffs(text)
        local _, class = UnitClass("player")
        local known, other = {}, {}
        text = (text or ""):lower():match("^%s*(.-)%s*$")
        for _, name in ipairs(ns.DEBUFFS and ns.DEBUFFS[class] or {}) do
            if text == "" or name:lower():find(text, 1, true) then
                table.insert(ns.Spells:Find(name) and known or other, name)
            end
        end
        for _, name in ipairs(other) do known[#known + 1] = name end
        return known
    end
    local function Result(i)
        if found[i] then return found[i] end
        local row = CreateFrame("Button", nil, results)
        row:SetSize(196, 20)
        row:SetPoint("TOPLEFT", 2, -2 - (i - 1) * 20)
        local hover = row:CreateTexture(nil, "HIGHLIGHT")
        hover:SetAllPoints()
        hover:SetColorTexture(1, 1, 1, .06)
        row.icon = row:CreateTexture(nil, "ARTWORK")
        row.icon:SetSize(16, 16)
        row.icon:SetPoint("LEFT", 4, 0)
        ns.Style:Zoom(row.icon)
        row.name = T:Text(row, "GameFontHighlightSmall")
        row.name:SetPoint("LEFT", row.icon, "RIGHT", 6, 0)
        row:SetScript("OnClick", function(self) Pick(self.spell) end)
        found[i] = row
        return row
    end
    local function ShowResults()
        local list = Debuffs(search:GetText())
        local count = math.min(#list, MAX_RESULTS)
        for i = 1, count do
            local row, name = Result(i), list[i]
            local entry = ns.Spells:Find(name)
            row.spell = name
            row.icon:SetTexture(ns.Spells:Icon(name))
            row.name:SetText(name)
            -- Ones you haven't learned yet are greyed.
            local colour = entry and T.TEXT or T.MUTED
            row.name:SetTextColor(colour[1], colour[2], colour[3])
            row:Show()
        end
        for i = count + 1, #found do found[i]:Hide() end
        local extra = #list - count
        more:ClearAllPoints()
        more:SetPoint("TOPLEFT", 8, -5 - count * 20)
        more:SetText(#list == 0 and "No debuffs match." or ("Type to narrow down " .. extra .. " more."))
        more:SetShown(#list == 0 or extra > 0)
        results:SetHeight(4 + count * 20 + ((#list == 0 or extra > 0) and 18 or 0))
        results:Show()
    end
    search:HookScript("OnEditFocusGained", ShowResults)
    search:SetScript("OnTextChanged", function(_, typed)
        if typed then ShowResults() end
    end)
    search:HookScript("OnEditFocusLost", function()
        if not results:IsMouseOver() then results:Hide() end
    end)
    Pick = function(name)
        results:Hide()
        search:SetText("")
        search:ClearFocus()
        if L:IsHidden("debuff") then
            window:Say("Debuffs is out of your layout. Put it back first.")
        else
            placing = name
        end
        window:Refresh()
    end
    -- A spot picked for the debuff: in the Debuffs row only.
    local function Place(key, spot)
        if key ~= "debuff" then
            window:Say("Debuffs go in the Debuffs row.")
            return window:Refresh()
        end
        local name = placing
        placing = nil
        Done(B:AddAt("debuff", name, spot or #ns.BarData("debuff").spells + 1))
    end
    page:HookScript("OnHide", function()
        placing = nil
        results:Hide()
    end)

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
    page.ghost = ghost
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
        -- Dropped after the window closed (Escape, say): it stays where it was.
        if not (from and page:IsVisible()) then return end
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
    -- The window closing mid-drag drops nothing, and no icon is left on the
    -- cursor for next time.
    page:HookScript("OnHide", function()
        picked = nil
        ghost:Hide()
    end)

    local function Tile(row, i)
        local tile = row.tiles[i]
        if tile then return tile end
        tile = CreateFrame("Button", nil, row.strip)
        tile:SetSize(10, 10)
        tile.texture = tile:CreateTexture(nil, "ARTWORK")
        tile.texture:SetAllPoints()
        tile:RegisterForDrag("LeftButton")
        tile:SetScript("OnDragStart", function(self)
            -- Nothing is still held from a drag that never landed.
            picked = nil
            ghost:Hide()
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
        -- A spell from your spellbook dropped here joins the row's bar; a
        -- debuff found by the search goes in this spot.
        tile:SetScript("OnReceiveDrag", function() B:Dropped(row.key) end)
        tile:SetScript("OnClick", function(self)
            if placing then return Place(row.key, self.name and B:Index(row.key, self.name)) end
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
        -- Outlines the Debuffs row while a found debuff waits for its spot.
        row.target = CreateFrame("Frame", nil, row, "BackdropTemplate")
        row.target:SetPoint("TOPLEFT", row.strip, "TOPLEFT", -3, 3)
        row.target:SetPoint("BOTTOMRIGHT", row.strip, "BOTTOMRIGHT", 3, -3)
        T:Flat(row.target, { 0, 0, 0, 0 }, T.CONTROL_BORDER)
        T:Paint(function(accent) row.target:SetBackdropBorderColor(accent[1], accent[2], accent[3], 1) end)
        row.target:EnableMouse(false)
        row.target:Hide()
        local Button = Buttons(row, 106)
        row.fewer = Button(T:Square(row.buttons, "-", true), 0, function()
            Done(L:SetAcross(key, ns.BarData(key).perRow - 1))
        end)
        row.wider = Button(T:Square(row.buttons, "+", true), 22, function()
            Done(L:SetAcross(key, ns.BarData(key).perRow + 1))
        end)
        row.up = Button(Arrow(row.buttons, true), 44, function() Done(L:Swap(key, -1)) end)
        row.down = Button(Arrow(row.buttons, false), 66, function() Done(L:Swap(key, 1)) end)
        -- Taking a bar out asks first.
        row.out = Button(T:Square(row.buttons, "x", true), 88, function()
            window:Ask("Take " .. ns.BAR_NAMES[key] .. " out of your layout?",
                "It won't show until you put it back. Its spells stay.", "Take out",
                function() Done(L:TakeOut(key)) end)
        end)
        row:SetScript("OnEnter", function(self)
            ShowButtons(self)
            Note(HINT)
        end)
        row:SetScript("OnLeave", function(self)
            ShowButtons(self)
            Unnote()
        end)
        -- A spell dropped on a row joins that bar; a found debuff goes at the
        -- end of it; a click without either keeps the row's buttons up.
        row:SetScript("OnReceiveDrag", function(self) B:Dropped(self.key) end)
        row:SetScript("OnClick", function(self)
            if placing then return Place(self.key) end
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
    -- Your cast bar, drawn under the display while it's on.
    local castStrip = box:CreateTexture(nil, "ARTWORK")
    castStrip:Hide()
    page.castStrip = castStrip
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

    -- What's on a bar for you, in order: joined buff entries count once, and
    -- another class's (in a shared profile) not at all.
    local function Entries(key)
        if not ns.AURA_BARS[key] then return (B:Mine(key)) end
        local list = {}
        for _, unit in ipairs(B:Units(key)) do
            for _, name in ipairs(unit) do
                if ns.Spells:ForMe(name, key) then
                    list[#list + 1] = name
                    break
                end
            end
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
                -- A spell you haven't learned yet: its own icon, greyed.
                tile.texture:SetTexture(ns.Spells:Icon(name))
                tile.texture:SetDesaturated(ns.Spells:Find(name) == nil)
                ns.Style:Zoom(tile.texture)
            else
                tile.texture:SetDesaturated(false)
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
        -- Only the bars in the layout are drawn; taken-out ones get a button.
        local function In(key) return key and not layout.hidden[key] end
        local above, below, sides = {}, {}, {}
        for _, key in ipairs(layout.above) do if In(key) then above[#above + 1] = key end end
        for _, key in ipairs(layout.below) do if In(key) then below[#below + 1] = key end end
        for _, side in ipairs({ "left", "right" }) do if In(layout[side]) then sides[side] = layout[side] end end
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
        for _, list in ipairs({ above, below }) do
            for _, key in ipairs(list) do widest = math.max(widest, Real(key)) end
        end
        for _, key in pairs(sides) do middle = middle + layout.gap + Real(key) end
        local scale = math.min(SCALE, (boxWidth - 2 * EDGE) / math.max(1, widest, middle))
        local function Tile(key) return math.max(6, math.floor(ns.BarData(key).size * scale)) end
        local gap = math.floor(layout.gap * scale + .5)
        local displayWidth = math.floor(displayReal * scale)
        local shown = L:Display()
        local displayHeight = math.max(6, math.floor((shown and shown.height or 20) * scale + .5))
        local sideTile = 0
        for _, key in pairs(sides) do sideTile = math.max(sideTile, Tile(key)) end
        local lineHeight = math.max(displayHeight, sideTile)
        -- The cast bar hangs under the display; the rows below go under both.
        local castRoom = ns.CastBar and ns.CastBar:Room()
        local castHeight = castRoom and math.max(3, math.floor(castRoom * scale + .5)) or 0
        local castGap = castRoom and math.max(1, math.floor(4 * scale + .5)) or 0
        local lineBottom = math.max(lineHeight, (lineHeight + displayHeight) / 2 + castGap + castHeight)
        local total = lineBottom
        for _, list in ipairs({ above, below }) do
            for _, key in ipairs(list) do total = total + Tile(key) + gap end
        end
        for _, row in pairs(rows) do row:Hide() end
        local function Draws(row)
            row:Show()
            -- The Debuffs row, outlined while a found debuff waits for its spot.
            row.target:SetShown(placing ~= nil and row.key == "debuff")
            return row
        end
        local y = math.max(28, math.floor((boxHeight - total) / 2))
        for _, key in ipairs(above) do
            Stacked(Draws(Row(key)), y, Tile(key))
            y = y + Tile(key) + gap
        end
        display:ClearAllPoints()
        display:SetPoint("TOP", box, "TOP", 0, -(y + (lineHeight - displayHeight) / 2))
        display:SetSize(math.max(20, displayWidth), displayHeight)
        display.health:SetHeight(math.max(2, math.ceil(displayHeight * .6)))
        display.power:SetHeight(math.max(2, displayHeight - math.ceil(displayHeight * .6) - 1))
        -- Switched off, it's drawn faintly where it would be.
        display:SetAlpha(ns.PersonalDisplayOn() and 1 or .3)
        for side, key in pairs(sides) do Beside(Draws(Row(key)), side, y, Tile(key), lineHeight, displayWidth, gap) end
        castStrip:SetShown(castRoom ~= nil)
        if castRoom then
            castStrip:ClearAllPoints()
            castStrip:SetPoint("TOP", display, "BOTTOM", 0, -castGap)
            castStrip:SetSize(math.max(20, displayWidth), castHeight)
            T:Fill(castStrip, ns.CastBar:Colour())
        end
        y = y + lineBottom + gap
        for _, key in ipairs(below) do
            Stacked(Draws(Row(key)), y, Tile(key))
            y = y + Tile(key) + gap
        end
        local health, power = ns.Get("prdHealth"), ns.Get("prdPower")
        T:Fill(display.health, health ~= "default" and ns.Style:BarColour(health) or HEALTH)
        T:Fill(display.power, power ~= "default" and ns.Style:BarColour(power) or POWER)
        display.up:SetUsable(L:CanMoveDisplay(-1))
        display.down:SetUsable(L:CanMoveDisplay(1))
        for _, row in pairs(rows) do ShowButtons(row) end
        ShowButtons(display)
        -- Put back: a button for each bar taken out.
        local x, line, any = 80, 9, false
        for _, key in ipairs(ns.BAR_KEYS) do
            local button, out = outButtons[key], layout.hidden[key] == true
            button:SetShown(out)
            if out then
                if x + 84 > OUT_RIGHT then x, line = 80, line + 22 end
                button:ClearAllPoints()
                button:SetPoint("BOTTOMLEFT", box, "BOTTOMLEFT", x, line)
                x, any = x + 90, true
            end
        end
        outLabel:SetShown(any)
        -- While a found debuff waits for its spot, the box says so.
        drag:SetText(placing and ("Click a spot in the Debuffs row for " .. placing .. ".") or DRAG)
        search:SetShown(placing == nil)
        cancel:SetShown(placing ~= nil)
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
        elseif B:IsUnlocked() then
            text = "Unlocked: drag a bar on screen to move it."
        elseif active and not ns.PersonalDisplayOn() then
            text = "Your rows sit together where your resource display would be."
        elseif active then
            text = "Your bars follow your Personal Resource Display."
        elseif L.moved then
            text = "You moved a bar, so they're no longer stacked."
        elseif layout.preset or layout.base then -- picked once, even if edited since
            text = "Your bars stay where you put them."
        else
            text = "Pick a layout to stack your bars around your resource display."
        end
        status:SetText(text)
        status:SetTextColor(colour[1], colour[2], colour[3])
        turnOn:SetShown(barsOff)
        toggle:SetShown(on)
        toggle:SetLabel(active and "Turn off" or "Line up")
        unlock:SetLabel(B:IsUnlocked() and "Lock bars" or "Unlock bars")
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
