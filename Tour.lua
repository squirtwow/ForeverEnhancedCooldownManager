-- The tour: the basics a step at a time, like the game's own tips for new
-- characters. Each step opens the page it's about, outlines the part it
-- means in the accent, and explains it in a box beside it with Back, Next and
-- Skip tour. A Try it step moves on by itself once you've done what it asks.
-- The tour only opens pages and points: it never changes a setting, and the
-- outline takes no clicks. A first install opens the window with a welcome
-- that offers it; after that it's on the General page and /ccm tour.
local _, ns = ...
local T = ns.Theme

local Tour = {}
ns.Tour = Tour

local FLAT = "Interface\\Buttons\\WHITE8X8"
local BOX_WIDTH, PAD = 290, 10
local GAP = 14 -- between the part outlined and the box
local OUTLINE = 4 -- how far outside that part the outline sits
local CHECK_EVERY = .25 -- how often a Try it step looks to see if it's done
local TOUR_NOTE = "Take the tour any time from the General page, or with /ccm tour."

local window, box, outline
local steps, index, started, welcome
local since = 0

local function Value(value, ...)
    if type(value) == "function" then return value(...) end
    return value
end

-- Spells on your four bars together: adding one counts wherever it goes.
local function SpellCount()
    local count = 0
    for _, key in ipairs(ns.BAR_KEYS) do count = count + #ns.BarData(key).spells end
    return count
end

-- The minimap button, while there's one to point at (EraUI can fade it).
local function MinimapButton()
    local button = ns.MinimapButton and ns.MinimapButton:Button()
    if button and button:IsVisible() and button:GetAlpha() > .5 then return button end
end

-- The steps. page: the page it opens (none keeps the one showing). target:
-- the part it outlines, or the first and last of a row of them. side: where
-- the box goes, "right", "below" or "above"; align "end" lines the box up
-- with the far end. A Try it step has watch, a count that goes up once it's
-- done, unless already says it was done before the step began.
local STEPS = {
    {
        title = "The menu",
        text = "Everything is in this list: your four bars at the top, then Look, Layout, Cast bar and General.",
        target = function(w) return w.navFrame end,
        side = "right",
    },
    {
        page = "general",
        title = "Switch your bars on",
        text = "Your own bars start off. Tick Use my bars to switch them on.",
        try = "Try it: tick it.",
        already = function() return ns.Bars:Enabled() end,
        alreadyText = "They're already on.",
        watch = function() return ns.Bars:Enabled() and 1 or 0 end,
        target = function(w) return w.useBars end,
        side = "below",
    },
    {
        page = "cd",
        title = "Add spells",
        text = "Tick spells in this list, or drag them in from your spellbook. Utility, Buffs and Debuffs work the same way.",
        try = "Try it: add a spell.",
        watch = SpellCount,
        target = function(w) return w.pages.bar.listPanel end,
        side = "above",
    },
    {
        page = "cd",
        title = "This bar's options",
        text = "Icon size, spacing, icons per row, and whether the bar shows out of combat. Each bar has its own.",
        target = function(w) return w.pages.bar.optionsArea end,
        side = "below",
    },
    {
        page = "layout",
        title = "Layouts",
        text = "One click stacks your bars round your Personal Resource Display. Then change any row, or drag icons between rows.",
        target = function(w)
            local cards = w.pages.layout.cards
            return cards[1], cards[#cards]
        end,
        side = "below",
    },
    {
        page = "look",
        title = "The look",
        text = function()
            if not ns.CooldownManagerOn() then
                return "Blizzard's Cooldown Manager is off, and its new look needs it. Turn on switches it on."
            end
            return "Blizzard's Cooldown Manager already has the new look. Pick its design, colour, border and shadow here. Your own bars use them too."
        end,
        target = function(w)
            if ns.CooldownManagerOn() then return w.lookOptions end
            return w.turnOnManager
        end,
        side = "below",
    },
    {
        page = "cast",
        when = function(w) return w.pages.cast ~= nil end,
        title = "Cast bar",
        text = "Tick this for your own cast bar under your resource display. Leave it off if you use a cast bar addon.",
        target = function(w) return w.pages.cast.shown end,
        side = "below",
    },
    {
        title = "Profiles",
        text = "Each character has its own spell lists. Share one between characters, even across classes, or use one on all of them.",
        target = function(w) return w.profileButton end,
        side = "below",
        align = "end",
    },
    {
        title = "That's the basics",
        text = function()
            return (MinimapButton() and "Open these settings any time with this button or /ccm."
                or "Open these settings any time with /ccm.")
                .. " What's new shows after each update, and this tour is on the General page."
        end,
        target = function(w) return MinimapButton() or w.versionText end,
        side = function() return MinimapButton() and "below" or "above" end,
        align = function() return MinimapButton() and "end" or nil end,
    },
}

-- Where the box goes against what it points at, and its arrow on the box's
-- edge: the box's point, the target's point, the offset, the arrow's point
-- on the box and its offset, and which way the arrow faces.
local PLACES = {
    right = { "TOPLEFT", "TOPRIGHT", GAP, 0, "RIGHT", "TOPLEFT", 0, -20, "left" },
    below = { "TOPLEFT", "BOTTOMLEFT", 0, -GAP, "BOTTOM", "TOPLEFT", 24, 0, "up" },
    above = { "BOTTOMLEFT", "TOPLEFT", 0, GAP, "TOP", "BOTTOMLEFT", 24, 0, "down" },
    belowEnd = { "TOPRIGHT", "BOTTOMRIGHT", 0, -GAP, "BOTTOM", "TOPRIGHT", -24, 0, "up" },
    aboveEnd = { "BOTTOMRIGHT", "TOPRIGHT", 0, GAP, "TOP", "BOTTOMRIGHT", -24, 0, "down" },
}

local function Strip(frame, layer)
    local strip = frame:CreateTexture(nil, layer)
    strip:SetTexture(FLAT)
    return strip
end

-- A ring of four strips, `width` thick, `out` pixels outside the frame's edge.
local function Ring(frame, width, out, layer)
    local top, bottom, left, right = Strip(frame, layer), Strip(frame, layer), Strip(frame, layer), Strip(frame, layer)
    top:SetPoint("TOPLEFT", -out, out)
    top:SetPoint("TOPRIGHT", out, out)
    top:SetHeight(width)
    bottom:SetPoint("BOTTOMLEFT", -out, -out)
    bottom:SetPoint("BOTTOMRIGHT", out, -out)
    bottom:SetHeight(width)
    left:SetPoint("TOPLEFT", -out, out)
    left:SetPoint("BOTTOMLEFT", -out, -out)
    left:SetWidth(width)
    right:SetPoint("TOPRIGHT", out, out)
    right:SetPoint("BOTTOMRIGHT", out, -out)
    right:SetWidth(width)
    return { top, bottom, left, right }
end

local function Build()
    window = ns.window
    -- The outline: the accent, with a soft edge, gently pulsing.
    outline = CreateFrame("Frame", nil, window)
    outline:SetFrameStrata("FULLSCREEN_DIALOG")
    outline:SetFrameLevel(window:GetFrameLevel() + 70)
    local line = Ring(outline, 2, 0, "OVERLAY")
    local soft = Ring(outline, 3, 3, "ARTWORK")
    T:Paint(function(accent)
        for _, strip in ipairs(line) do strip:SetVertexColor(accent[1], accent[2], accent[3], 1) end
        for _, strip in ipairs(soft) do strip:SetVertexColor(accent[1], accent[2], accent[3], .3) end
    end)
    local pulse = 0
    outline:SetScript("OnUpdate", function(self, elapsed)
        pulse = pulse + elapsed
        self:SetAlpha(.55 + .45 * (1 + math.sin(pulse * 4)) / 2)
    end)
    outline:Hide()

    box = CreateFrame("Frame", "FECMTour", window, "BackdropTemplate")
    box.outline = outline
    box:SetWidth(BOX_WIDTH)
    box:SetFrameStrata("FULLSCREEN_DIALOG")
    box:SetFrameLevel(window:GetFrameLevel() + 80)
    box:SetClampedToScreen(true)
    box:EnableMouse(true)
    T:Flat(box, T.BG, T.CONTROL_BORDER)
    box.title = T:Heading(box, "")
    box.title:SetPoint("TOPLEFT", PAD, -PAD)
    box.count = T:Text(box, "GameFontHighlightSmall", T.MUTED)
    box.count:SetPoint("TOPRIGHT", -PAD, -PAD)
    box.count:SetJustifyH("RIGHT")
    box.text = T:Text(box, "GameFontHighlightSmall")
    box.text:SetPoint("TOPLEFT", PAD, -(PAD + 16))
    box.text:SetWidth(BOX_WIDTH - 2 * PAD)
    box.arrow = box:CreateTexture(nil, "ARTWORK")
    box.arrow:SetTexture(ns.MEDIA .. "TourArrow.tga")
    local nextButton = T:Button(box, "Next", 64, 20)
    nextButton:SetPoint("BOTTOMRIGHT", -PAD, PAD)
    local back = T:Button(box, "Back", 64, 20)
    back:SetPoint("RIGHT", nextButton, "LEFT", -6, 0)
    local skip = T:Button(box, "Skip tour", 76, 20)
    skip:SetPoint("BOTTOMLEFT", PAD, PAD)
    T:Paint(function(accent)
        box:SetBackdropBorderColor(accent[1], accent[2], accent[3], 1)
        box.arrow:SetVertexColor(accent[1], accent[2], accent[3], 1)
        nextButton:SetBackdropBorderColor(accent[1], accent[2], accent[3], 1)
    end)
    nextButton:SetScript("OnClick", function()
        if welcome then Tour:Start() else Tour:Next() end
    end)
    back:SetScript("OnClick", function() Tour:Back() end)
    skip:SetScript("OnClick", function()
        Tour:Stop()
        window:Say(TOUR_NOTE)
        window:Refresh()
    end)
    box.next, box.back, box.skip = nextButton, back, skip
    -- A Try it step watches for what it asked for.
    box:SetScript("OnUpdate", function(_, elapsed)
        local step = steps and index and steps[index]
        if not (step and step.watch and started) then return end
        since = since + elapsed
        if since < CHECK_EVERY then return end
        since = 0
        if step.watch() > started then Tour:Next() end
    end)
    box:Hide()
    -- Closing the window ends the tour.
    window:HookScript("OnHide", function() Tour:Stop() end)
end

local function Ready()
    if not ns.ShowWindow then return false end
    ns.ShowWindow()
    if not box then Build() end
    return true
end

-- Sizes the box round its text: the title row, the text, then the buttons.
local function Fit()
    box:SetHeight(PAD + 16 + math.ceil(box.text:GetStringHeight() or 0) + 12 + 20 + PAD)
end

-- A bar page counts as any bar's page: the list and options are the same.
local function Same(a, b)
    return a == b or (ns.BAR_NAMES[a] ~= nil and ns.BAR_NAMES[b] ~= nil)
end

local function Point(step)
    local first, last = Value(step.target, window)
    last = last or first
    if not first then
        outline:Hide()
        box.arrow:Hide()
        box:ClearAllPoints()
        box:SetPoint("CENTER", window, "CENTER", 90, 30)
        return
    end
    outline:ClearAllPoints()
    outline:SetPoint("TOPLEFT", first, "TOPLEFT", -OUTLINE, OUTLINE)
    outline:SetPoint("BOTTOMRIGHT", last, "BOTTOMRIGHT", OUTLINE, -OUTLINE)
    outline:Show()
    local side = Value(step.side) or "below"
    local place = PLACES[Value(step.align) == "end" and side .. "End" or side] or PLACES.below
    local anchor = place[2]:find("RIGHT") and last or first
    box:ClearAllPoints()
    box:SetPoint(place[1], anchor, place[2], place[3], place[4])
    local arrow = box.arrow
    arrow:ClearAllPoints()
    arrow:SetPoint(place[5], box, place[6], place[7], place[8])
    if place[9] == "left" then
        arrow:SetSize(9, 16)
        arrow:SetTexCoord(1, 0, 0, 0, 1, 1, 0, 1)
    else
        arrow:SetSize(16, 9)
        if place[9] == "up" then arrow:SetTexCoord(0, 1, 0, 1) else arrow:SetTexCoord(0, 1, 1, 0) end
    end
    arrow:Show()
end

local function Show(i)
    index, welcome = i, nil
    local step = steps[i]
    if step.page then window:Select(step.page) end
    local text = Value(step.text)
    local already = step.already and step.already()
    if step.try then
        text = text .. "\n\n|cff" .. T:Hex(T:Accent()) .. (already and step.alreadyText or step.try) .. "|r"
    end
    box.title:SetText(step.title:upper())
    box.count:SetText(i .. " of " .. #steps)
    box.count:Show()
    box.text:SetText(text)
    box.back:SetShown(i > 1)
    box.next:SetWidth(64)
    box.next:SetLabel(i == #steps and "Done" or "Next")
    box.skip:SetLabel("Skip tour")
    started = step.watch and not already and step.watch() or nil
    since = 0
    Fit()
    Point(step)
    box:Show()
    box:Raise()
end

-- The tour from the start, over the window.
function Tour:Start()
    if not Ready() then return end
    steps = {}
    for _, step in ipairs(STEPS) do
        if not step.when or step.when(window) then steps[#steps + 1] = step end
    end
    Show(1)
end

-- A first install: the window, and an offer of the tour.
function Tour:Welcome()
    if not Ready() then return end
    steps, index, started, welcome = nil, nil, nil, true
    box.title:SetText("WELCOME")
    box.count:Hide()
    box.text:SetText("New to " .. ns.TITLE .. "? A quick tour shows you the basics, a page at a time. It takes about a minute.")
    box.back:Hide()
    box.next:SetWidth(100)
    box.next:SetLabel("Take the tour")
    box.skip:SetLabel("Skip")
    Fit()
    Point({})
    box:Show()
    box:Raise()
end

function Tour:Next()
    if not (steps and index) then return end
    if index < #steps then return Show(index + 1) end
    self:Stop()
    window:Say("That's the tour. " .. TOUR_NOTE)
    window:Refresh()
end

function Tour:Back()
    if steps and index and index > 1 then Show(index - 1) end
end

function Tour:Stop()
    steps, index, started, welcome = nil, nil, nil, nil
    if box then
        box:Hide()
        outline:Hide()
    end
end

function Tour:Active()
    return box ~= nil and box:IsShown()
end

-- Called whenever the window changes page: the outline only shows on the page
-- the step is about. Next and Back always go back to it.
function Tour:Sync()
    local step = steps and index and steps[index]
    if not step or not box then return end
    local here = not step.page or Same(step.page, window.selected)
    outline:SetShown(here and Value(step.target, window) ~= nil)
    box.arrow:SetShown(here)
end
