-- The /ccm window's look: flat charcoal panels, thin borders and one accent
-- colour, picked from a few set colours. Every piece
-- drawn in the accent registers a painter, so choosing a new accent repaints
-- the whole window at once.
local _, ns = ...

local T = {}
ns.Theme = T

local FLAT = "Interface\\Buttons\\WHITE8X8"

T.BG = { .106, .110, .122, .98 }
T.HEADER = { .125, .129, .145, 1 }
T.NAV = { .118, .122, .137, 1 }
T.PANEL = { .09, .094, .102, 1 }
T.BORDER = { .173, .180, .200, 1 }
T.ROW = { .08, .084, .092, 1 }
T.SELECTED = { .149, .157, .176, 1 }
T.CONTROL = { .15, .155, .17, 1 }
T.HOVER = { .20, .205, .225, 1 }
T.CONTROL_BORDER = { .20, .208, .227, 1 }
T.FIELD = { .075, .078, .086, 1 }
T.TEXT = { .84, .843, .851 }
T.MUTED = { .545, .553, .573 }
T.WARN = { 1, .45, .3 }

-- Soft washes of the accent, full on the right and fading out to the left:
-- how strong each is at its right-hand edge.
T.FADE = { page = .18, header = .30, selected = .36 }

T.ACCENTS = {
    orange = { name = "Orange", colour = { .88, .47, .16 } },
    blue = { name = "Blue", colour = { .24, .55, .88 } },
    teal = { name = "Teal", colour = { .17, .70, .64 } },
    purple = { name = "Purple", colour = { .69, .49, .94 } },
    green = { name = "Green", colour = { .38, .74, .30 } },
}

function T:Accent()
    local choice = T.ACCENTS[ns.Get("accent")] or T.ACCENTS.orange
    return choice.colour
end

-- Text on an accent fill: dark on light accents, white on dark ones.
function T:OnAccent(colour)
    colour = colour or self:Accent()
    local light = colour[1] * .299 + colour[2] * .587 + colour[3] * .114 > .5
    return light and { .07, .07, .07 } or { 1, 1, 1 }
end

function T:Hex(colour)
    local function Byte(v) return math.floor(math.max(0, math.min(1, v)) * 255 + .5) end
    return ("%02x%02x%02x"):format(Byte(colour[1]), Byte(colour[2]), Byte(colour[3]))
end

local painters = {}

-- Runs now and again whenever the accent changes.
function T:Paint(painter)
    painters[#painters + 1] = painter
    painter(self:Accent())
end

function T:Repaint()
    local accent = self:Accent()
    for _, painter in ipairs(painters) do painter(accent) end
end

-- Pieces -----------------------------------------------------------------------------

local function Colour(region, colour)
    region:SetColorTexture(colour[1], colour[2], colour[3], colour[4] or 1)
end

function T:Fill(region, colour)
    Colour(region, colour)
end

function T:Flat(frame, fill, border)
    frame:SetBackdrop({ bgFile = FLAT, edgeFile = FLAT, edgeSize = 1 })
    frame:SetBackdropColor(fill[1], fill[2], fill[3], fill[4] or 1)
    border = border or T.BORDER
    frame:SetBackdropBorderColor(border[1], border[2], border[3], border[4] or 1)
end

local function Gradient(texture, colour, strength)
    local r, g, b = colour[1], colour[2], colour[3]
    if CreateColor and texture.SetGradient then
        texture:SetGradient("HORIZONTAL", CreateColor(r, g, b, 0), CreateColor(r, g, b, strength))
    elseif texture.SetGradientAlpha then
        texture:SetGradientAlpha("HORIZONTAL", r, g, b, 0, r, g, b, strength)
    end
end

-- A wash of the accent over a frame's background, repainted with the accent.
function T:Fade(parent, strength)
    local fade = parent:CreateTexture(nil, "BORDER")
    fade:SetTexture(FLAT)
    self:Paint(function(accent) Gradient(fade, accent, strength) end)
    return fade
end

-- A page's main box (its list), outlined in the accent so it stands out.
function T:Box(frame)
    self:Flat(frame, T.PANEL, T.BORDER)
    self:Paint(function(accent) frame:SetBackdropBorderColor(accent[1], accent[2], accent[3], 1) end)
end

function T:Panel(parent)
    local panel = CreateFrame("Frame", nil, parent, "BackdropTemplate")
    self:Flat(panel, T.PANEL)
    return panel
end

-- A window's title bar: the addon's icon on an accent square, its name with
-- "Enhanced" in the accent, the accent washing in from the right, and an X.
function T:TitleBar(window, height)
    local header = CreateFrame("Frame", nil, window, "BackdropTemplate")
    header:SetPoint("TOPLEFT", 1, -1)
    header:SetPoint("TOPRIGHT", -1, -1)
    header:SetHeight(height)
    self:Flat(header, T.HEADER, T.HEADER)
    header.fade = self:Fade(header, T.FADE.header)
    header.fade:SetAllPoints()
    local logo = CreateFrame("Frame", nil, header, "BackdropTemplate")
    logo:SetSize(24, 24)
    logo:SetPoint("LEFT", 12, 0)
    local icon = logo:CreateTexture(nil, "ARTWORK")
    icon:SetPoint("TOPLEFT", 2, -2)
    icon:SetPoint("BOTTOMRIGHT", -2, 2)
    icon:SetTexture("Interface\\Icons\\INV_Misc_PocketWatch_01")
    local title = self:Text(header, "GameFontNormalLarge")
    title:SetPoint("LEFT", logo, "RIGHT", 8, 0)
    self:Paint(function(accent)
        self:Flat(logo, { accent[1], accent[2], accent[3], 1 }, { accent[1], accent[2], accent[3], 1 })
        title:SetText("Forever |cff" .. self:Hex(accent) .. "Enhanced|r Cooldown Manager")
    end)
    local close = self:Square(header, "X")
    close:SetSize(22, 22)
    close:SetPoint("RIGHT", -10, 0)
    close:SetScript("OnClick", function() window:Hide() end)
    header.close = close
    return header
end

function T:Text(parent, font, colour)
    local text = parent:CreateFontString(nil, "OVERLAY", font or "GameFontHighlight")
    text:SetJustifyH("LEFT")
    colour = colour or T.TEXT
    text:SetTextColor(colour[1], colour[2], colour[3])
    return text
end

-- Small capitals in the accent, over each part of the window.
function T:Heading(parent, label)
    local text = self:Text(parent, "GameFontNormalSmall")
    text:SetText(label:upper())
    self:Paint(function(accent) text:SetTextColor(accent[1], accent[2], accent[3]) end)
    return text
end

-- A square tick box that fills with the accent, with an optional label that
-- is part of the click area. Clicking flips it, then calls onClick.
function T:Check(parent, label, onClick)
    local check = CreateFrame("Button", nil, parent)
    local box = CreateFrame("Frame", nil, check, "BackdropTemplate")
    box:SetSize(12, 12)
    box:SetPoint("LEFT", label and 0 or 2, 0)
    self:Flat(box, T.FIELD, { .33, .33, .33, 1 })
    box:EnableMouse(false)
    local fill = box:CreateTexture(nil, "ARTWORK")
    fill:SetPoint("TOPLEFT", 2, -2)
    fill:SetPoint("BOTTOMRIGHT", -2, 2)
    fill:Hide()
    self:Paint(function(accent) Colour(fill, accent) end)
    check.box, check.fill = box, fill
    if label then
        check.text = self:Text(check, "GameFontHighlight")
        check.text:SetPoint("LEFT", box, "RIGHT", 6, 0)
        check.text:SetText(label)
        check:SetSize(18 + (check.text:GetStringWidth() or 0), 16)
    else
        check:SetSize(16, 16)
    end
    function check:SetChecked(value)
        self.checked = value and true or false
        self.fill:SetShown(self.checked)
    end
    function check:GetChecked()
        return self.checked == true
    end
    check:SetScript("OnClick", function(self)
        self:SetChecked(not self.checked)
        if onClick then onClick(self) end
    end)
    check:SetScript("OnEnter", function() box:SetBackdropBorderColor(.6, .6, .6, 1) end)
    check:SetScript("OnLeave", function() box:SetBackdropBorderColor(.33, .33, .33, 1) end)
    check:SetChecked(false)
    return check
end

-- A flat button with a lighter hover.
function T:Button(parent, label, width, height)
    local button = CreateFrame("Button", nil, parent, "BackdropTemplate")
    button:SetSize(width or 120, height or 22)
    self:Flat(button, T.CONTROL, T.CONTROL_BORDER)
    button.label = self:Text(button, "GameFontHighlightSmall")
    button.label:SetPoint("CENTER")
    button.label:SetJustifyH("CENTER")
    button.label:SetText(label)
    function button:SetLabel(text)
        self.label:SetText(text)
    end
    button:SetScript("OnEnter", function(self) self:SetBackdropColor(T.HOVER[1], T.HOVER[2], T.HOVER[3], 1) end)
    button:SetScript("OnLeave", function(self) self:SetBackdropColor(T.CONTROL[1], T.CONTROL[2], T.CONTROL[3], 1) end)
    return button
end

-- A small square button, for arrows, remove and plus or minus.
function T:Square(parent, label, accented)
    local button = self:Button(parent, label, 18, 18)
    button.label:SetFontObject("GameFontHighlight")
    if accented then
        self:Paint(function(accent) button.label:SetTextColor(accent[1], accent[2], accent[3]) end)
    end
    function button:SetUsable(usable)
        self:SetEnabled(usable)
        self:SetAlpha(usable and 1 or .35)
    end
    return button
end

-- Joined buttons; the chosen one fills with the accent.
function T:Segmented(parent, items, width, onSelect)
    local bar = CreateFrame("Frame", nil, parent, "BackdropTemplate")
    bar:SetSize(width, 20)
    self:Flat(bar, T.FIELD, T.CONTROL_BORDER)
    bar.buttons = {}
    local each = (width - 2) / #items
    for i, item in ipairs(items) do
        local button = CreateFrame("Button", nil, bar)
        button:SetSize(each, 18)
        button:SetPoint("LEFT", 1 + (i - 1) * each, 0)
        button.fill = button:CreateTexture(nil, "BACKGROUND")
        button.fill:SetAllPoints()
        button.label = self:Text(button, "GameFontHighlightSmall")
        button.label:SetPoint("CENTER")
        button.label:SetJustifyH("CENTER")
        button.label:SetText(item.label)
        button.key = item.key
        button:SetScript("OnClick", function() onSelect(item.key) end)
        bar.buttons[i] = button
    end
    function bar:SetSelected(key)
        self.selected = key
        local accent, on = T:Accent(), T:OnAccent()
        for _, button in ipairs(self.buttons) do
            local chosen = button.key == key
            button.fill:SetShown(chosen)
            Colour(button.fill, accent)
            local c = chosen and on or T.TEXT
            button.label:SetTextColor(c[1], c[2], c[3])
            -- The font's black drop shadow smears dark text on a light accent.
            button.label:SetShadowColor(0, 0, 0, chosen and on[1] < .5 and 0 or 1)
        end
    end
    self:Paint(function() if bar.selected then bar:SetSelected(bar.selected) end end)
    return bar
end

-- A flat text box with a grey placeholder while empty.
function T:Input(parent, placeholder, width)
    local input = CreateFrame("EditBox", nil, parent, "BackdropTemplate")
    input:SetSize(width or 160, 20)
    self:Flat(input, T.FIELD, T.CONTROL_BORDER)
    input:SetFontObject("GameFontHighlightSmall")
    input:SetTextInsets(6, 6, 0, 0)
    input:SetAutoFocus(false)
    input.placeholder = self:Text(input, "GameFontHighlightSmall", T.MUTED)
    input.placeholder:SetPoint("LEFT", 6, 0)
    input.placeholder:SetText(placeholder)
    input:SetScript("OnEscapePressed", input.ClearFocus)
    input:SetScript("OnEnterPressed", input.ClearFocus)
    input:SetScript("OnEditFocusGained", function(self) self.placeholder:Hide() end)
    input:SetScript("OnEditFocusLost", function(self) self.placeholder:SetShown((self:GetText() or "") == "") end)
    return input
end

-- A flat slider: the label, a thin track filled with the accent up to a
-- square thumb, and the value. Drag it, click the track, or use the wheel.
function T:Slider(parent, label, limits, step, width, onChange)
    local slider = CreateFrame("Frame", nil, parent)
    slider:SetSize(width, 20)
    slider.label = self:Text(slider, "GameFontHighlight")
    slider.label:SetPoint("LEFT")
    slider.label:SetText(label)
    slider.value = self:Text(slider, "GameFontHighlight")
    slider.value:SetPoint("RIGHT")
    slider.value:SetWidth(28)
    slider.value:SetJustifyH("RIGHT")
    local track = CreateFrame("Frame", nil, slider)
    track:SetPoint("LEFT", 100, 0)
    track:SetPoint("RIGHT", -40, 0)
    track:SetHeight(16)
    track:EnableMouse(true)
    local groove = track:CreateTexture(nil, "BACKGROUND")
    groove:SetPoint("LEFT")
    groove:SetPoint("RIGHT")
    groove:SetHeight(4)
    Colour(groove, T.CONTROL_BORDER)
    local fill = track:CreateTexture(nil, "ARTWORK")
    fill:SetPoint("LEFT")
    fill:SetHeight(4)
    self:Paint(function(accent) Colour(fill, accent) end)
    local thumb = track:CreateTexture(nil, "OVERLAY")
    thumb:SetSize(10, 10)
    Colour(thumb, T.TEXT)
    slider.track, slider.fill, slider.thumb = track, fill, thumb

    function slider:Set(value)
        self.current = value
        self.value:SetText(value)
        local length = track:GetWidth() or 0
        local share = (value - limits[1]) / (limits[2] - limits[1])
        fill:SetWidth(math.max(1, length * share))
        thumb:ClearAllPoints()
        thumb:SetPoint("CENTER", track, "LEFT", length * share, 0)
    end
    -- Snapped to the step and kept within the limits; only a new value is sent.
    function slider:Choose(value)
        value = limits[1] + math.floor((value - limits[1]) / step + .5) * step
        value = math.max(limits[1], math.min(limits[2], value))
        if value == self.current then return end
        self:Set(value)
        onChange(value)
    end
    local function FromCursor()
        local x = GetCursorPosition() / track:GetEffectiveScale()
        local length = math.max(1, track:GetWidth() or 1)
        slider:Choose(limits[1] + (x - (track:GetLeft() or 0)) / length * (limits[2] - limits[1]))
    end
    track:SetScript("OnMouseDown", function()
        FromCursor()
        track:SetScript("OnUpdate", FromCursor)
    end)
    track:SetScript("OnMouseUp", function() track:SetScript("OnUpdate", nil) end)
    -- The track's width is only known once it's drawn.
    track:SetScript("OnSizeChanged", function() if slider.current then slider:Set(slider.current) end end)
    slider:EnableMouseWheel(true)
    slider:SetScript("OnMouseWheel", function(self, delta) self:Choose((self.current or limits[1]) + delta * step) end)
    return slider
end

-- A list that scrolls with the mouse wheel, with a thin accent thumb that can
-- also be dragged.
function T:Scroll(parent, width)
    local scroll = CreateFrame("ScrollFrame", nil, parent)
    local content = CreateFrame("Frame", nil, scroll)
    content:SetSize(width, 1)
    scroll:SetScrollChild(content)
    scroll.content = content
    local thumb = CreateFrame("Frame", nil, parent)
    thumb:SetWidth(3)
    thumb:EnableMouse(true)
    thumb.texture = thumb:CreateTexture(nil, "ARTWORK")
    thumb.texture:SetAllPoints()
    self:Paint(function(accent) Colour(thumb.texture, accent) end)
    scroll.thumb = thumb

    -- Until the game has measured the list there's nothing to scroll; this
    -- keeps a short list from being scrolled out of view before then.
    local function Range()
        local view = scroll:GetHeight() or 0
        if view <= 0 then return 0 end
        return math.max(0, (content:GetHeight() or 0) - view)
    end
    function scroll:ScrollTo(offset)
        self:SetVerticalScroll(math.max(0, math.min(Range(), offset)))
        self:UpdateThumb()
    end
    function scroll:UpdateThumb()
        local view, range = self:GetHeight() or 0, Range()
        if range <= 0 or view <= 0 then
            thumb:Hide()
            return
        end
        local total = view + range
        local size = math.max(16, view * view / total)
        local offset = (view - size) * (self:GetVerticalScroll() or 0) / range
        thumb:SetHeight(size)
        thumb:ClearAllPoints()
        thumb:SetPoint("TOPLEFT", self, "TOPRIGHT", 4, -offset)
        thumb:Show()
    end
    -- Once the game measures the list, keep the position within its range.
    scroll:SetScript("OnSizeChanged", function(self) self:ScrollTo(self:GetVerticalScroll() or 0) end)
    scroll:EnableMouseWheel(true)
    scroll:SetScript("OnMouseWheel", function(self, delta) self:ScrollTo((self:GetVerticalScroll() or 0) - delta * 44) end)
    thumb:SetScript("OnMouseDown", function()
        local _, y = GetCursorPosition()
        thumb.drag = { y = y / scroll:GetEffectiveScale(), from = scroll:GetVerticalScroll() or 0 }
    end)
    thumb:SetScript("OnMouseUp", function() thumb.drag = nil end)
    thumb:SetScript("OnUpdate", function()
        local drag = thumb.drag
        if not drag then return end
        local _, y = GetCursorPosition()
        local view, range = scroll:GetHeight() or 1, Range()
        local track = math.max(1, view - thumb:GetHeight())
        scroll:ScrollTo(drag.from + (drag.y - y / scroll:GetEffectiveScale()) * range / track)
    end)
    thumb:Hide()
    return scroll
end
