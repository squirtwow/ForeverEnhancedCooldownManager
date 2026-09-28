-- Layouts: your own bars stacked in rows around Blizzard's Personal Resource
-- Display, above it, below it or beside it. One click sets up a preset; each
-- row's width and place can then be changed on the Layout page. The addon
-- only reads where the display is (Edit Mode places it) and, if asked,
-- widens its bars to your widest row (Resource.lua). A bar dragged by hand
-- leaves the layout.
local _, ns = ...

local L = {}
ns.Layout = L

local GAP = 6 -- between the rows, and between the rows and the display
local NAMES = 14 -- room for spell names under a row
local FALLBACK_Y = -150 -- where the stack goes with no display: under the middle
-- The display's parts, all counted whether or not they're up right now, so
-- the stack doesn't shift as forms change.
local PARTS = { "HealthBarsContainer", "PowerBar", "AlternatePowerBar", "ClassFrameContainer" }
-- What a layout changes on a bar, and Undo puts back.
local FIELDS = { "x", "y", "point", "size", "spacing", "perRow", "grow", "wrap" }

-- Each row: the bar, above or below the display (top to bottom) or beside
-- it, how many icons fit across and their size.
L.PRESETS = {
    { key = "pyramid", name = "Pyramid", about = "6, 5, 4 and 3 across.", rows = {
        { bar = "cd", place = "above", across = 6, size = 42 },
        { bar = "util", place = "below", across = 5, size = 38 },
        { bar = "buff", place = "below", across = 4, size = 34 },
        { bar = "debuff", place = "below", across = 3, size = 30 } } },
    { key = "wide", name = "Wide", about = "12, 7, 5 and 4 across.", rows = {
        { bar = "cd", place = "above", across = 12, size = 36 },
        { bar = "util", place = "below", across = 7, size = 34 },
        { bar = "buff", place = "below", across = 5, size = 30 },
        { bar = "debuff", place = "below", across = 4, size = 28 } } },
    { key = "stack", name = "Centre stack", about = "Buffs on top, then cooldowns; utility and debuffs underneath.", rows = {
        { bar = "buff", place = "above", across = 4, size = 30 },
        { bar = "cd", place = "above", across = 6, size = 42 },
        { bar = "util", place = "below", across = 5, size = 36 },
        { bar = "debuff", place = "below", across = 4, size = 30 } } },
    { key = "compact", name = "Compact", spacing = 2, about = "Smaller icons, 8 across, close together.", rows = {
        { bar = "cd", place = "above", across = 8, size = 32 },
        { bar = "util", place = "below", across = 8, size = 28 },
        { bar = "buff", place = "below", across = 8, size = 26 },
        { bar = "debuff", place = "below", across = 8, size = 26 } } },
    { key = "sides", name = "Sides", about = "Buffs left of the display, debuffs right.", rows = {
        { bar = "cd", place = "above", across = 8, size = 38 },
        { bar = "buff", place = "left", across = 4, size = 32 },
        { bar = "debuff", place = "right", across = 4, size = 32 },
        { bar = "util", place = "below", across = 6, size = 34 } } },
    { key = "twin", name = "Twin rows", about = "Two rows of 10 above the display.", rows = {
        { bar = "util", place = "above", across = 10, size = 34 },
        { bar = "cd", place = "above", across = 10, size = 34 },
        { bar = "buff", place = "below", across = 6, size = 28 },
        { bar = "debuff", place = "below", across = 6, size = 28 } } },
    { key = "funnel", name = "Funnel", about = "Everything above the display, widest nearest: 3, 4, 5 and 6.", rows = {
        { bar = "debuff", place = "above", across = 3, size = 28 },
        { bar = "buff", place = "above", across = 4, size = 32 },
        { bar = "util", place = "above", across = 5, size = 36 },
        { bar = "cd", place = "above", across = 6, size = 42 } } },
}
local PRESET = {}
for _, preset in ipairs(L.PRESETS) do PRESET[preset.key] = preset end

function L:Preset(key)
    return PRESET[key]
end

local function Copy(list)
    local copy = {}
    for i, value in ipairs(list) do copy[i] = value end
    return copy
end

-- Whether a layout holds your bars now.
function L:Active()
    local layout = ns.LayoutData()
    return layout ~= nil and layout.on and ns.Bars:Enabled() or false
end

-- The display showing (say it's set to show only in combat) stacks the bars
-- around it again. A post-hook on Blizzard's frame, set once.
local watching
local function Watch(frame)
    if watching or not frame.HookScript then return end
    watching = true
    frame:HookScript("OnShow", function() L:Stack() end)
end

-- The display's middle and size, from the middle of the screen, in the bars'
-- own units. While the game can't say (it's hidden until combat, say), where
-- it was last seen. Nil when it's never been there.
function L:Display()
    local frame = _G.PersonalResourceDisplayFrame
    local layout = ns.LayoutData()
    if frame then
        Watch(frame)
        local screen = UIParent:GetEffectiveScale()
        local left, right, bottom, top
        local function Add(region)
            if not (region and region.GetRect) then return end
            local ok, x, y, width, height = pcall(region.GetRect, region)
            if not (ok and x and y and width and height) or width <= 0 or height <= 0 then return end
            local scale = region:GetEffectiveScale() / screen
            x, y, width, height = x * scale, y * scale, width * scale, height * scale
            left, right = math.min(left or x, x), math.max(right or x + width, x + width)
            bottom, top = math.min(bottom or y, y), math.max(top or y + height, y + height)
        end
        Add(frame)
        for _, name in ipairs(PARTS) do Add(frame[name]) end
        if left then
            local cx, cy = UIParent:GetCenter()
            local display = { x = (left + right) / 2 - cx, y = (bottom + top) / 2 - cy, width = right - left, height = top - bottom }
            if layout then layout.display = display end
            return display
        end
    end
    local seen = layout and layout.display
    if type(seen) == "table" and type(seen.x) == "number" and type(seen.y) == "number"
        and type(seen.width) == "number" and type(seen.height) == "number" then
        return seen
    end
end

-- Your widest row above or below the display, with every tile filled.
function L:WidestRow()
    local layout, widest = ns.LayoutData(), 0
    for _, place in ipairs({ "above", "below" }) do
        for _, key in ipairs(layout[place]) do
            local data = ns.BarData(key)
            widest = math.max(widest, data.perRow * data.size + (data.perRow - 1) * data.spacing)
        end
    end
    return widest > 0 and widest or nil
end

-- How wide the display should be, or nil while it keeps Blizzard's width.
function L:MatchWidth()
    if not (self:Active() and ns.Get("prdMatch")) then return nil end
    return self:WidestRow()
end

-- Puts the bars in place: rows above the display from the nearest upwards,
-- rows below from the nearest downwards, and the ones beside it level with
-- its middle. A bar with nothing on it takes no room, unless the bars are
-- unlocked. The Buffs and Debuffs bars catch up after a fight.
function L:Stack()
    if not self:Active() then return false end
    if InCombatLockdown() then self.pending = true end
    local layout, B = ns.LayoutData(), ns.Bars
    if ns.Resource then ns.Resource:Match() end
    local display = self:Display()
    self.found = display ~= nil
    display = display or { x = 0, y = FALLBACK_Y, width = self:MatchWidth() or 0, height = 0 }
    -- Each bar grows away from the display; laid out again if that changed.
    local function Grow(key, grow, wrap)
        local data = ns.BarData(key)
        if data.grow ~= grow or data.wrap ~= wrap then
            data.grow, data.wrap = grow, wrap
            B:Relayout(key)
        end
        return data
    end
    local function Room(key, data)
        local bar = B:Get(key)
        if not (bar and (bar.count > 0 or B:IsUnlocked())) then return nil end
        return bar:GetHeight() + (data.showNames and NAMES or 0)
    end
    local y = display.y + display.height / 2 + GAP
    for i = #layout.above, 1, -1 do
        local key = layout.above[i]
        local data = Grow(key, "centre", "up")
        -- Names hang under the icons, so the bar sits above them.
        B:PlaceAt(key, "BOTTOM", display.x, y + (data.showNames and NAMES or 0))
        local room = Room(key, data)
        if room then y = y + room + GAP end
    end
    y = display.y - display.height / 2 - GAP
    for _, key in ipairs(layout.below) do
        local data = Grow(key, "centre", "down")
        B:PlaceAt(key, "TOP", display.x, y)
        local room = Room(key, data)
        if room then y = y - room - GAP end
    end
    for _, side in ipairs({ "left", "right" }) do
        local key = layout[side]
        if key then
            local data = Grow(key, side, "down")
            local x = side == "left" and display.x - display.width / 2 - GAP or display.x + display.width / 2 + GAP
            B:PlaceAt(key, side == "left" and "TOPRIGHT" or "TOPLEFT", x, display.y + data.size / 2)
        end
    end
    ns.SaveBars()
    return true
end

-- Everything a layout changes, for Undo.
local function Snapshot()
    local copy = { bars = {}, useBars = ns.Get("useBars") }
    for _, key in ipairs(ns.BAR_KEYS) do
        local data, saved = ns.BarData(key), {}
        for _, field in ipairs(FIELDS) do saved[field] = data[field] end
        copy.bars[key] = saved
    end
    local layout = ns.LayoutData()
    copy.layout = { on = layout.on, preset = layout.preset, above = Copy(layout.above),
        below = Copy(layout.below), left = layout.left, right = layout.right }
    return copy
end

-- Sets your bars up as a preset: each bar's place, how many icons fit
-- across and their size. Your spells stay as they are.
function L:Apply(key)
    local preset = PRESET[key]
    if not preset then return false, "There's no layout called that." end
    if InCombatLockdown() then return false, "Finish combat first." end
    self.undo, self.moved = Snapshot(), nil
    local layout = ns.LayoutData()
    layout.above, layout.below, layout.left, layout.right = {}, {}, nil, nil
    for _, row in ipairs(preset.rows) do
        local data = ns.BarData(row.bar)
        data.perRow, data.size, data.spacing = row.across, row.size, preset.spacing or 4
        if row.place == "left" or row.place == "right" then
            layout[row.place] = row.bar
        else
            table.insert(layout[row.place], row.bar)
        end
    end
    layout.on, layout.preset = true, key
    ns.LayoutData()
    if not ns.Bars:Enabled() then ns.Set("useBars", true) end
    ns.Bars:Rebuild()
    return true, preset.name .. " is set up. Tick spells for each bar, then size them to taste."
end

-- Puts back what the last preset changed.
function L:Undo()
    local copy = self.undo
    if not copy then return false end
    if InCombatLockdown() then return false, "Finish combat first." end
    self.undo = nil
    for key, saved in pairs(copy.bars) do
        local data = ns.BarData(key)
        for _, field in ipairs(FIELDS) do data[field] = saved[field] end
    end
    local layout = ns.LayoutData()
    layout.on, layout.preset = copy.layout.on, copy.layout.preset
    layout.above, layout.below = copy.layout.above, copy.layout.below
    layout.left, layout.right = copy.layout.left, copy.layout.right
    if ns.Get("useBars") ~= copy.useBars then ns.Set("useBars", copy.useBars) end
    ns.Bars:Rebuild()
    if ns.Resource then ns.Resource:Match() end
    return true, "Put back as it was."
end

-- A change on the Layout page stacks the bars again, as your own layout.
local function Edited()
    local layout = ns.LayoutData()
    layout.on, layout.preset = true, nil
    L.moved = nil
    return layout
end

-- How many icons fit across a row.
function L:SetAcross(key, across)
    if InCombatLockdown() then return false, "Finish combat first." end
    local limits = ns.BAR_LIMITS.perRow
    Edited()
    ns.Bars:SetOption(key, "perRow", math.max(limits[1], math.min(limits[2], across)))
    return true
end

-- The rows top to bottom, with false for the display: the bars beside it
-- aren't in it.
function L:Order()
    local layout, order = ns.LayoutData(), {}
    for _, key in ipairs(layout.above) do order[#order + 1] = key end
    order[#order + 1] = false
    for _, key in ipairs(layout.below) do order[#order + 1] = key end
    return order
end

local function IndexOf(list, value)
    for i, item in ipairs(list) do
        if item == value then return i end
    end
end

-- Whether a row can move that way: past the display it changes sides of it,
-- and a row beside the display can go just above or below it.
function L:CanMove(key, delta)
    local layout = ns.LayoutData()
    if layout.left == key or layout.right == key then return true end
    local order = self:Order()
    local at = IndexOf(order, key)
    return at ~= nil and order[at + delta] ~= nil
end

function L:Move(key, delta)
    if InCombatLockdown() then return false, "Finish combat first." end
    if not self:CanMove(key, delta) then return false end
    local layout = Edited()
    local order = self:Order()
    if layout.left == key or layout.right == key then
        if layout.left == key then layout.left = nil else layout.right = nil end
        local display = IndexOf(order, false)
        table.insert(order, delta < 0 and display or display + 1, key)
    else
        local at = IndexOf(order, key)
        order[at], order[at + delta] = order[at + delta], order[at]
    end
    local below = false
    layout.above, layout.below = {}, {}
    for _, item in ipairs(order) do
        if item == false then below = true else table.insert(below and layout.below or layout.above, item) end
    end
    self:Stack()
    return true
end

-- Your bars stay where they are, and the display gets Blizzard's width back.
function L:TurnOff()
    local layout = ns.LayoutData()
    if not (layout and layout.on) then return end
    layout.on = false
    ns.SaveBars()
    if ns.Resource then ns.Resource:Match() end
end

-- A bar dragged by hand.
function L:Moved()
    if not self:Active() then return end
    self:TurnOff()
    self.moved = true
end

-- Stacks the bars again in the layout they were last in.
function L:LineUp()
    if InCombatLockdown() then return false, "Finish combat first." end
    ns.LayoutData().on = true
    self.moved = nil
    if not ns.Bars:Enabled() then ns.Set("useBars", true) end
    ns.Bars:Rebuild()
    return true, "Your bars are stacked again."
end

function L:Start()
    if self.started then return end
    self.started = true
    local events = CreateFrame("Frame")
    for _, event in ipairs({ "PLAYER_ENTERING_WORLD", "PLAYER_REGEN_ENABLED", "ADDON_LOADED",
        "UI_SCALE_CHANGED", "DISPLAY_SIZE_CHANGED" }) do
        events:RegisterEvent(event)
    end
    events:SetScript("OnEvent", function(_, event, name)
        if event == "PLAYER_REGEN_ENABLED" then
            if ns.Resource and ns.Resource.pendingMatch then ns.Resource:Match() end
            if L.pending then
                L.pending = nil
                L:Stack()
            end
        elseif event ~= "ADDON_LOADED" or name == "Blizzard_PersonalResourceDisplay" then
            -- Edit Mode puts the display in place as the world loads, as
            -- it's switched on, and again when the screen changes size.
            C_Timer.After(1, function() L:Stack() end)
        end
    end)
end
