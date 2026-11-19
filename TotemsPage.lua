-- The Totems page in the /ccm window, under More, for shamans only (a
-- player's idea): one tick to turn the bar on, a preview of it with your
-- choices, where it sits with Move and Reset, Red when out of range, its
-- size, spacing, rows, names, countdown numbers and out of combat choice,
-- and the order of the four elements. Totems.lua does the work.
local _, ns = ...
local T = ns.Theme

local LABEL = 108 -- room for a slider's label before its track: Icons per row, the longest
local SLIDER = 280 -- each slider's width, as on a bar's page
local COLUMN = 320 -- the right-hand column
local PILL_LABEL = 100 -- a choice's buttons start this far past its label
local PREVIEW_WIDTH, PREVIEW_HEIGHT = 380, 72 -- the preview's box
local PICKER, PICKER_STEP = 112, 120 -- each order picker's width, and from one to the next

-- A choice's buttons, from its keys and their names.
local function Choices(keys, names)
    local items = {}
    for _, key in ipairs(keys) do items[#items + 1] = { key = key, label = names[key] } end
    return items
end

-- Changed: saved, the bar as chosen, the page again.
local function Changed(window, key, value)
    ns.Set(key, value)
    ns.Totems:Apply()
    window:Refresh()
end

-- The preview, and where the bar sits with Move and Reset.
local function BuildTray(window, page, inner)
    local M = ns.Totems
    local tray = CreateFrame("Frame", nil, page, "BackdropTemplate")
    tray:SetPoint("TOPLEFT", 16, -38)
    tray:SetSize(inner, 104)
    T:Flat(tray, T.PANEL, T.BORDER)
    page.tray = tray
    local function Caption(text, x)
        local caption = T:Text(tray, "GameFontHighlightSmall", T.MUTED)
        caption:SetPoint("TOPLEFT", x, -8)
        caption:SetText(text)
    end
    Caption("PREVIEW", 12)
    Caption("WHERE IT SHOWS", 408)

    -- The bar as your choices make it, smaller to fit, never with the
    -- game's buff slots (Totems.lua NewPreview).
    local box = CreateFrame("Frame", nil, tray)
    box:SetPoint("TOPLEFT", 12, -24)
    box:SetSize(PREVIEW_WIDTH, PREVIEW_HEIGHT)
    box:SetClipsChildren(true)
    box:EnableMouse(true)
    window:Hint(box, function()
        if ns.Get("totemRange") then
            return "A preview with your choices: two totems down, one out of range, and an element with none."
        end
        return "A preview with your choices: three totems down and an element with none."
    end)
    local preview = M:NewPreview(box)
    preview:SetPoint("CENTER")
    page.previewBox, page.preview = box, preview

    local move = T:Button(tray, "Move", 80, 22)
    move:SetPoint("TOPLEFT", 408, -26)
    move:SetScript("OnClick", function()
        local ok, why = M:StartMove()
        if not ok then
            window:Say(why)
            window:Refresh()
        end
    end)
    window:Hint(move, "Hides this window and shows a box over the bar. Drag it where you want it, then click Done.")
    local reset = T:Button(tray, "Reset", 80, 22)
    reset:SetPoint("TOPLEFT", 496, -26)
    reset:SetScript("OnClick", function()
        M:ResetPlace()
        window:Say("The Totems bar is back where it started.")
        window:Refresh()
    end)
    window:Hint(reset, "Puts the Totems bar back where it started, left of your bars.")
    local where = T:Text(tray, "GameFontHighlightSmall", T.MUTED)
    where:SetPoint("TOPLEFT", 408, -56)
    where:SetWidth(inner - 420)
    page.move, page.reset, page.where = move, reset, where
end

-- The choices: on or off and Red when out of range, the sliders on the left,
-- names and countdown numbers under them, out of combat and rows on the right.
local function BuildOptions(window, page, inner)
    local M = ns.Totems
    local options = CreateFrame("Frame", nil, page)
    options:SetPoint("TOPLEFT", page.tray, "BOTTOMLEFT", 0, -10)
    options:SetSize(inner, 190)
    page.options = options

    local function Tick(label, key, x, y, note)
        local check = T:Check(options, label, function(self) Changed(window, key, self:GetChecked()) end)
        check:SetPoint("TOPLEFT", x, y)
        check.key = key
        window:Hint(check, note)
        return check
    end
    page.master = Tick("Show the Totems bar", "totemBar", 0, 0, "One spot for each element, greyed until you drop a totem,"
        .. " then that totem with its time left, in a fight too. It never takes the mouse.")
    -- Greyed while the game can't show it (Totems.lua CanRange).
    page.range = Tick("Red when out of range", "totemRange", COLUMN, 0, function()
        if not M:CanRange() then return "Your game can't show the range warning." end
        return "A totem that buffs you, like Strength of Earth or Mana Spring, turns red while you're out of its range."
            .. " Totems that don't buff you never do."
    end)

    page.sliders = {}
    local function Slider(label, key, limits, step, y, note)
        local slider = T:Slider(options, label, limits, step, SLIDER, function(value) Changed(window, key, value) end, LABEL)
        slider:SetPoint("TOPLEFT", 0, y)
        slider.key = key
        window:Hint(slider, note)
        page.sliders[#page.sliders + 1] = slider
        return slider
    end
    -- All bars (the Layout page) sizes them too: while it isn't 100, the
    -- note says what size they show at.
    page.size = Slider("Icon size", "totemSize", ns.BAR_LIMITS.size, 2, -26, function()
        local scale = ns.Get("barScale")
        if scale == 100 then return "How big the totems are. All bars on the Layout page sizes them too." end
        local shown = ns.IconSize({ size = ns.Get("totemSize") })
        return "Their own size. All bars on the Layout page is at " .. scale .. ", so they show at " .. shown
            .. (shown <= ns.BAR_LIMITS.size[1] and ", the smallest they go." or ".")
    end)
    local height = Slider("Icon height", "totemHeight", ns.BAR_LIMITS.heightPct, 5, -47,
        "How tall the icons are, as a share of their width. 100% is square.")
    -- Its value as a share, "100%", with room for it up to the track.
    height.value:SetWidth(36)
    local setHeight = height.Set
    function height:Set(value)
        setHeight(self, value)
        self.value:SetText(value .. "%")
    end
    page.height = height
    page.spacing = Slider("Spacing", "totemSpacing", ns.BAR_LIMITS.spacing, 1, -68, "The room between the totems.")
    page.across = Slider("Icons per row", "totemPerRow", ns.TOTEM_PER_ROW, 1, -89,
        "How many fit across before the next row starts: 4 is one row, 2 a square, 1 a column.")

    page.timer = Tick("Show countdown numbers", "totemTimer", 0, -113, "The time left on each totem, counting down.")
    page.names = Tick("Show totem names", "totemNames", 0, -135,
        "Each totem's name under its icon, or its element's while none is down.")

    -- A label, then its buttons PILL_LABEL along.
    local function Pills(label, key, keys, names, width, y, note)
        local text = T:Text(options, "GameFontHighlight")
        text:SetPoint("TOPLEFT", COLUMN, y - 4)
        text:SetText(label)
        local pills = T:Segmented(options, Choices(keys, names), width, function(picked) Changed(window, key, picked) end)
        pills:SetPoint("TOPLEFT", COLUMN + PILL_LABEL, y)
        pills.label, pills.key = text, key
        for _, button in ipairs(pills.buttons) do window:Hint(button, note) end
        return pills
    end
    page.outOfCombat = Pills("Out of combat", "totemOutOfCombat", ns.OUT_OF_COMBAT, ns.OUT_OF_COMBAT_NAMES, 156, -26, function()
        if ns.Get("oocIgnoreTarget") then
            return "Out of combat. The bar comes back in full in combat, while this page is open, while you move it, and in Edit Mode."
        end
        return "Out of combat. The bar comes back in full in combat, with an enemy targeted, while this page is open,"
            .. " while you move it, and in Edit Mode."
    end)
    page.grow = Pills("Grow", "totemGrow", ns.GROW, ns.GROW_NAMES, 156, -48,
        "Which way a row grows: from its centre, or from its right or left edge.")
    page.wrap = Pills("New rows", "totemWrap", ns.WRAP, ns.WRAP_NAMES, 110, -70,
        "Where the next row goes when there are more totems than fit across.")
end

-- The order: one picker for each spot, first to last, its element's name
-- between two arrows. An arrow steps that spot to the next element, which
-- swaps places with it (Totems.lua SetOrderAt).
local function BuildOrder(window, page)
    local M = ns.Totems
    local options = page.options
    local label = T:Text(options, "GameFontHighlight")
    label:SetPoint("TOPLEFT", 0, -165)
    label:SetText("Order")
    page.orderLabel, page.order = label, {}
    local note = "Which element goes in each spot, first to last. The arrows change it, swapping the two spots."
    local letters = { "e", "f", "w", "a" }
    for index = 1, 4 do
        local picker = CreateFrame("Frame", nil, options, "BackdropTemplate")
        picker:SetSize(PICKER, 20)
        picker:SetPoint("TOPLEFT", 100 + (index - 1) * PICKER_STEP, -161)
        T:Flat(picker, T.FIELD, T.CONTROL_BORDER)
        local function Step(by)
            local at = 1
            for i, letter in ipairs(letters) do
                if letter == picker.selected then at = i end
            end
            M:SetOrderAt(index, letters[(at - 1 + by) % #letters + 1])
            window:Refresh()
        end
        picker.back = T:Square(picker, "<")
        picker.back:SetPoint("LEFT", 1, 0)
        picker.back:SetScript("OnClick", function() Step(-1) end)
        picker.next = T:Square(picker, ">")
        picker.next:SetPoint("RIGHT", -1, 0)
        picker.next:SetScript("OnClick", function() Step(1) end)
        picker.name = T:Text(picker, "GameFontHighlightSmall")
        picker.name:SetPoint("CENTER")
        picker.name:SetJustifyH("CENTER")
        picker:EnableMouse(true)
        picker.label = label
        function picker:SetSelected(letter)
            self.selected = letter
            local element = M.ELEMENTS[letter]
            self.name:SetText(element and element.name or "")
        end
        picker.buttons = { picker.back, picker.next }
        window:Hint(picker, note)
        for _, button in ipairs(picker.buttons) do window:Hint(button, note) end
        page.order[index] = picker
    end
end

function ns.BuildTotemsPage(window, page, width)
    local M = ns.Totems
    local inner = width - 32
    local title = T:Heading(page, "Totems")
    title:SetPoint("TOPLEFT", 16, -16)
    local status = T:Text(page, "GameFontHighlightSmall", T.MUTED)
    status:SetPoint("LEFT", title, "RIGHT", 10, 0)
    page.title, page.status = title, status
    BuildTray(window, page, inner)
    BuildOptions(window, page, inner)
    BuildOrder(window, page)
    -- In full while the page is open (Totems.lua PageOpen).
    page:HookScript("OnShow", function() M:PageOpen(true) end)
    page:HookScript("OnHide", function() M:PageOpen(false) end)

    function page:Refresh()
        local on = ns.Get("totemBar") == true
        self.master:SetChecked(on)
        self.range:SetChecked(ns.Get("totemRange") == true)
        self.range:SetUsable(M:CanRange())
        self.timer:SetChecked(ns.Get("totemTimer") == true)
        self.names:SetChecked(ns.Get("totemNames") == true)
        for _, slider in ipairs(self.sliders) do slider:Set(ns.Get(slider.key)) end
        for _, pills in ipairs({ self.outOfCombat, self.grow, self.wrap }) do pills:SetSelected(ns.Get(pills.key)) end
        for index, letter in ipairs(M:Order()) do
            if self.order[index] then self.order[index]:SetSelected(letter) end
        end

        -- How many are down: out of a fight only (the game won't say in one).
        local said = "Off. Tick the box below to start."
        if on then
            local down = M:Down()
            if down == nil then
                said = "On."
            elseif down == 0 then
                said = "On. Drop a totem to see its time."
            elseif down == 1 then
                said = "On. 1 totem down."
            else
                said = "On. " .. down .. " totems down."
            end
        end
        self.status:SetText(said)
        local moved = ns.Get("totemX") ~= ns.DEFAULTS.totemX or ns.Get("totemY") ~= ns.DEFAULTS.totemY
        self.where:SetText(moved and "Where you dragged it." or "Left of your bars, where it starts.")

        -- The preview, drawn smaller to fit its box.
        local w, h = M:DrawPreview(self.preview)
        local scale = 1
        if type(w) == "number" and w > 0 then scale = math.min(scale, PREVIEW_WIDTH / w) end
        if type(h) == "number" and h > 0 then scale = math.min(scale, PREVIEW_HEIGHT / h) end
        self.preview:SetScale(scale)
    end
end
