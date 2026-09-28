-- The /ccm window's look: flat dark panels, thin borders and one accent
-- colour, picked from a few set colours. Every piece
-- drawn in the accent registers a painter, so choosing a new accent repaints
-- the whole window at once.
local _, ns = ...

local T = {}
ns.Theme = T

local FLAT = "Interface\\Buttons\\WHITE8X8"

T.BG = { .07, .07, .07, .97 }
T.PANEL = { .10, .10, .10, 1 }
T.BORDER = { .18, .18, .18, 1 }
T.ROW = { .08, .08, .08, 1 }
T.CONTROL = { .14, .14, .14, 1 }
T.HOVER = { .20, .20, .20, 1 }
T.CONTROL_BORDER = { .24, .24, .24, 1 }
T.FIELD = { .055, .055, .055, 1 }
T.TEXT = { .9, .9, .9 }
T.MUTED = { .55, .55, .55 }

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

function T:Flat(frame, fill, border)
    frame:SetBackdrop({ bgFile = FLAT, edgeFile = FLAT, edgeSize = 1 })
    frame:SetBackdropColor(fill[1], fill[2], fill[3], fill[4] or 1)
    border = border or T.BORDER
    frame:SetBackdropBorderColor(border[1], border[2], border[3], border[4] or 1)
end

function T:Panel(parent)
    local panel = CreateFrame("Frame", nil, parent, "BackdropTemplate")
    self:Flat(panel, T.PANEL)
    return panel
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

    local function Range()
        return math.max(0, (content:GetHeight() or 0) - (scroll:GetHeight() or 0))
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
