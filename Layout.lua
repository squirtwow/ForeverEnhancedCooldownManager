-- Layouts: your own bars stacked in rows around Blizzard's Personal Resource
-- Display, above it, below it or beside it, flush against it and each other
-- unless you ask for room. One click sets up a preset; on the Layout page
-- each row's width can change, bars can swap rows (the rows keep their
-- shape) and the display can move up or down the stack. The addon only reads
-- where the display is (Edit Mode places it) and, if asked, widens its bars
-- to your widest row (Resource.lua). A bar dragged by hand leaves the layout.
local _, ns = ...

local L = {}
ns.Layout = L

local NAMES = 14 -- room for spell names under a row
local FALLBACK_Y = -150 -- where the stack goes with no display: under the middle
-- What a layout changes on a bar, and Undo puts back. Not icon sizes: a
-- layout never changes them, so ones you set after it stay.
local FIELDS = { "x", "y", "point", "spacing", "perRow", "grow", "wrap" }

-- Each row: the bar, above or below the display (top to bottom) or beside
-- it, and how many icons fit across. Your icon sizes stay as you set them.
L.PRESETS = {
    { key = "pyramid", name = "Pyramid", about = "6, 5, 4 and 3 across.", rows = {
        { bar = "cd", place = "above", across = 6 },
        { bar = "util", place = "below", across = 5 },
        { bar = "buff", place = "below", across = 4 },
        { bar = "debuff", place = "below", across = 3 } } },
    { key = "wide", name = "Wide", about = "12, 7, 5 and 4 across.", rows = {
        { bar = "cd", place = "above", across = 12 },
        { bar = "util", place = "below", across = 7 },
        { bar = "buff", place = "below", across = 5 },
        { bar = "debuff", place = "below", across = 4 } } },
    { key = "stack", name = "Centre stack", about = "Buffs on top, then cooldowns; utility and debuffs underneath.", rows = {
        { bar = "buff", place = "above", across = 4 },
        { bar = "cd", place = "above", across = 6 },
        { bar = "util", place = "below", across = 5 },
        { bar = "debuff", place = "below", across = 4 } } },
    { key = "even", name = "Even", about = "8 across on every row.", rows = {
        { bar = "cd", place = "above", across = 8 },
        { bar = "util", place = "below", across = 8 },
        { bar = "buff", place = "below", across = 8 },
        { bar = "debuff", place = "below", across = 8 } } },
    { key = "sides", name = "Sides", about = "Buffs left of the display, debuffs right.", rows = {
        { bar = "cd", place = "above", across = 8 },
        { bar = "buff", place = "left", across = 4 },
        { bar = "debuff", place = "right", across = 4 },
        { bar = "util", place = "below", across = 6 } } },
    { key = "twin", name = "Twin rows", about = "Two rows of 10 above the display.", rows = {
        { bar = "util", place = "above", across = 10 },
        { bar = "cd", place = "above", across = 10 },
        { bar = "buff", place = "below", across = 6 },
        { bar = "debuff", place = "below", across = 6 } } },
    { key = "funnel", name = "Funnel", about = "Everything above the display, widest nearest: 3, 4, 5 and 6.", rows = {
        { bar = "debuff", place = "above", across = 3 },
        { bar = "buff", place = "above", across = 4 },
        { bar = "util", place = "above", across = 5 },
        { bar = "cd", place = "above", across = 6 } } },
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
-- around it again, and hiding (switched off in Options, say) closes the rows
-- up. Post-hooks on Blizzard's frame, set once.
local watching
local function Watch(frame)
    if watching or not frame.HookScript then return end
    watching = true
    frame:HookScript("OnShow", function() L:Stack() end)
    frame:HookScript("OnHide", function() L:Stack() end)
end

-- The display's bars you can see now: health, power, the extra mana bar
-- unless it's tucked away, and the addon's combo points while they show
-- (Forever's display has none of its own). Not the frame around them, which
-- keeps a minimum height.
local function Bars(frame)
    local list = {}
    -- Edit Mode's Hide Health Bar hides the container, not the bar in it.
    local health = frame.HealthBarsContainer
    if health and health:IsShown() then list[#list + 1] = health.healthBar or health end
    list[#list + 1] = frame.PowerBar
    if not (ns.Resource and ns.Resource:ExtraHidden()) then list[#list + 1] = frame.AlternatePowerBar end
    list[#list + 1] = ns.Resource and ns.Resource:ComboRow()
    return list
end

-- The display's middle and size, from the middle of the screen, in the bars'
-- own units, edges included, so rows sit flush against it; edge is how far
-- the restyle's edges reach past its bars. While the game can't say (it's
-- hidden until combat, say), where it was last seen. Switched off, it takes
-- no room, so the rows close up where it was. Nil when it's never been there.
function L:Display()
    local frame = _G.PersonalResourceDisplayFrame
    local layout = ns.LayoutData()
    local display
    if frame then
        Watch(frame)
        local screen = UIParent:GetEffectiveScale()
        local left, right, bottom, top, edge
        for _, region in ipairs(Bars(frame)) do
            local shown = region and region.GetRect and region:IsShown()
            local ok, x, y, width, height
            if shown then ok, x, y, width, height = pcall(region.GetRect, region) end
            if ok and x and y and width and height and width > 0 and height > 0 then
                local scale = region:GetEffectiveScale() / screen
                x, y, width, height = x * scale, y * scale, width * scale, height * scale
                left, right = math.min(left or x, x), math.max(right or x + width, x + width)
                bottom, top = math.min(bottom or y, y), math.max(top or y + height, y + height)
                -- The restyle draws a 1px edge round each bar, in the
                -- display's own size (Edit Mode's Size), not the screen's.
                if ns.loaded.prdSkin then edge = math.max(edge or 0, scale) end
            end
        end
        if left then
            edge = edge or 0
            local cx, cy = UIParent:GetCenter()
            display = { x = (left + right) / 2 - cx, y = (bottom + top) / 2 - cy,
                width = right - left + 2 * edge, height = top - bottom + 2 * edge, edge = edge }
            if layout then layout.display = display end
        end
    end
    local seen = layout and layout.display
    if not display and type(seen) == "table" and type(seen.x) == "number" and type(seen.y) == "number"
        and type(seen.width) == "number" and type(seen.height) == "number" then
        display = seen
        -- Seen before its edge was kept: measured with the restyle's 1px.
        if type(display.edge) ~= "number" then display.edge = ns.loaded.prdSkin and 1 or 0 end
    end
    if display and not ns.PersonalDisplayOn() then
        return { x = display.x, y = display.y, width = display.width, height = 0, edge = display.edge, off = true }
    end
    return display
end

-- Whether a bar is taken out of the layout: it keeps its row and spells, but
-- doesn't show.
function L:IsHidden(key)
    local layout = ns.LayoutData()
    return layout ~= nil and layout.hidden[key] == true
end

-- The bars in a place (above or below the display) that are in the layout.
local function Placed(layout, place)
    local keys = {}
    for _, key in ipairs(layout[place]) do
        if not layout.hidden[key] then keys[#keys + 1] = key end
    end
    return keys
end

-- Your widest row above or below the display, with every tile filled.
function L:WidestRow()
    local layout, widest = ns.LayoutData(), 0
    for _, place in ipairs({ "above", "below" }) do
        for _, key in ipairs(Placed(layout, place)) do
            local data = ns.BarData(key)
            widest = math.max(widest, data.perRow * ns.IconSize(data) + (data.perRow - 1) * data.spacing)
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
-- your cast bar under it while that's on, rows below from the nearest
-- downwards, and the ones beside it level with its middle, touching unless
-- you've asked for space between them. A bar with nothing on it takes no
-- room, unless the bars are unlocked. The Buffs and Debuffs bars catch up
-- after a fight. Without a layout, only the cast bar is put under the display.
function L:Stack()
    if not self:Active() then
        if ns.CastBar then ns.CastBar:Place() end
        return false
    end
    if InCombatLockdown() then self.pending = true end
    local layout, B = ns.LayoutData(), ns.Bars
    local gap = layout.gap
    if ns.Resource then ns.Resource:Match() end
    local display = self:Display()
    self.found = display ~= nil
    display = display or { x = 0, y = FALLBACK_Y, width = self:MatchWidth() or 0, height = 0, edge = 0 }
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
    local y = display.y + display.height / 2 + gap
    local above = Placed(layout, "above")
    for i = #above, 1, -1 do
        local key = above[i]
        local data = Grow(key, "centre", "up")
        -- Names hang under the icons, so the bar sits above them.
        B:PlaceAt(key, "BOTTOM", display.x, y + (data.showNames and NAMES or 0))
        local room = Room(key, data)
        if room then y = y + room + gap end
    end
    local bottom = display.y - display.height / 2
    if ns.CastBar then bottom = ns.CastBar:Under(display) end
    y = bottom - gap
    for _, key in ipairs(Placed(layout, "below")) do
        local data = Grow(key, "centre", "down")
        B:PlaceAt(key, "TOP", display.x, y)
        local room = Room(key, data)
        if room then y = y - room - gap end
    end
    for _, side in ipairs({ "left", "right" }) do
        local key = layout[side]
        if key and not layout.hidden[key] then
            local data = Grow(key, side, "down")
            local x = side == "left" and display.x - display.width / 2 - gap or display.x + display.width / 2 + gap
            B:PlaceAt(key, side == "left" and "TOPRIGHT" or "TOPLEFT", x, display.y + ns.IconSize(data) / 2)
        end
    end
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
    local hidden = {}
    for key in pairs(layout.hidden) do hidden[key] = true end
    copy.layout = { on = layout.on, preset = layout.preset, base = layout.base, above = Copy(layout.above),
        below = Copy(layout.below), left = layout.left, right = layout.right, gap = layout.gap,
        spacing = layout.spacing, hidden = hidden }
    return copy
end

-- Sets your bars up as a preset: each bar's place and how many icons fit
-- across, with the layout's icon spacing. Your spells and icon sizes stay
-- as they are.
function L:Apply(key)
    local preset = PRESET[key]
    if not preset then return false, "There's no layout called that." end
    if InCombatLockdown() then return false, "Finish combat first." end
    self.undo, self.moved = Snapshot(), nil
    local layout = ns.LayoutData()
    layout.above, layout.below, layout.left, layout.right = {}, {}, nil, nil
    for _, row in ipairs(preset.rows) do
        local data = ns.BarData(row.bar)
        data.perRow, data.spacing = row.across, layout.spacing
        if row.place == "left" or row.place == "right" then
            layout[row.place] = row.bar
        else
            table.insert(layout[row.place], row.bar)
        end
    end
    layout.on, layout.preset, layout.base = true, key, key
    ns.LayoutData()
    if not ns.Bars:Enabled() then ns.Set("useBars", true) end
    ns.Bars:Rebuild()
    return true, preset.name .. " is set up. Tick spells for each bar, then size them to taste."
end

-- Puts back what the last preset or Reset changed.
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
    for field, value in pairs(copy.layout) do layout[field] = value end
    -- These can be empty, which the copy leaves out.
    layout.left, layout.right, layout.base = copy.layout.left, copy.layout.right, copy.layout.base
    layout.preset = copy.layout.preset
    if ns.Get("useBars") ~= copy.useBars then ns.Set("useBars", copy.useBars) end
    ns.Bars:Rebuild()
    if ns.Resource then ns.Resource:Match() end
    return true, "Put back as it was."
end

-- The layout as its preset was first set up: every bar back in, no room
-- between rows or icons. Your spells and icon sizes stay; Undo puts it back.
function L:Reset()
    if InCombatLockdown() then return false, "Finish combat first." end
    local layout = ns.LayoutData()
    local undo = Snapshot()
    layout.gap, layout.spacing, layout.hidden = 0, 0, {}
    local ok, message = self:Apply(layout.base or L.PRESETS[1].key)
    self.undo = undo
    if ok then message = PRESET[ns.LayoutData().base].name .. " is back as it was first set up." end
    return ok, message
end

-- Takes a bar out of the layout: its row closes up and it doesn't show, but
-- it keeps its spells and place for when it's put back.
function L:TakeOut(key)
    if InCombatLockdown() then return false, "Finish combat first." end
    local layout = ns.LayoutData()
    layout.hidden[key] = true
    ns.Bars:Rebuild()
    return true, ns.BAR_NAMES[key] .. " is out of your layout. Put it back any time."
end

function L:PutBack(key)
    if InCombatLockdown() then return false, "Finish combat first." end
    ns.LayoutData().hidden[key] = nil
    ns.Bars:Rebuild()
    return true, ns.BAR_NAMES[key] .. " is back in your layout."
end

-- A change on the Layout page stacks the bars again, as your own layout.
local function Edited()
    local layout = ns.LayoutData()
    layout.on, layout.preset = true, nil
    L.moved = nil
    return layout
end

-- The space between rows, and between the rows and the display.
function L:SetGap(gap)
    if InCombatLockdown() then return false, "Finish combat first." end
    ns.LayoutData().gap = gap
    ns.LayoutData()
    self:Stack()
    return true
end

-- The space between the icons in every row of the layout.
function L:SetSpacing(spacing)
    if InCombatLockdown() then return false, "Finish combat first." end
    local layout = ns.LayoutData()
    layout.spacing = spacing
    layout = ns.LayoutData()
    for _, key in ipairs(ns.BAR_KEYS) do ns.BarData(key).spacing = layout.spacing end
    ns.Bars:Rebuild()
    return true
end

-- How many icons fit across a row.
function L:SetAcross(key, across)
    if InCombatLockdown() then return false, "Finish combat first." end
    local limits = ns.BAR_LIMITS.perRow
    Edited()
    ns.Bars:SetOption(key, "perRow", math.max(limits[1], math.min(limits[2], across)))
    return true
end

-- The rows in the layout, top to bottom: those above the display, the ones
-- beside it, then those below.
function L:Rows()
    local layout, rows = ns.LayoutData(), {}
    for _, key in ipairs(Placed(layout, "above")) do rows[#rows + 1] = key end
    for _, side in ipairs({ "left", "right" }) do
        if layout[side] and not layout.hidden[layout[side]] then rows[#rows + 1] = layout[side] end
    end
    for _, key in ipairs(Placed(layout, "below")) do rows[#rows + 1] = key end
    return rows
end

local function IndexOf(list, value)
    for i, item in ipairs(list) do
        if item == value then return i end
    end
end

function L:CanSwap(key, delta)
    local rows = self:Rows()
    local at = IndexOf(rows, key)
    return at ~= nil and rows[at + delta] ~= nil
end

-- What swapping two bars' rows does to how many fit across each: rows keep
-- their width, so each bar takes the other's. Said before the swap (ahead)
-- or after it; nothing when they're the same.
function L:Widths(key, other, ahead)
    local mine, theirs = ns.BarData(key).perRow, ns.BarData(other).perRow
    if mine == theirs then return "" end
    if ahead then mine, theirs = theirs, mine end
    return " Rows keep their width, so " .. ns.BAR_NAMES[key] .. (ahead and " would be " or " is now ") .. mine
        .. " across and " .. ns.BAR_NAMES[other] .. " " .. theirs .. "."
end

-- Swaps a bar with the row above or below it. The rows keep how many fit
-- across, so a preset's shape stays with the bars in a new order; each bar
-- keeps its own icon size. True, and what changed.
function L:Swap(key, delta)
    if InCombatLockdown() then return false, "Finish combat first." end
    if not self:CanSwap(key, delta) then return false end
    local layout = Edited()
    local rows = self:Rows()
    local other = rows[IndexOf(rows, key) + delta]
    local function Trade(value)
        if value == key then return other elseif value == other then return key end
        return value
    end
    for _, place in ipairs({ "above", "below" }) do
        for i, value in ipairs(layout[place]) do layout[place][i] = Trade(value) end
    end
    layout.left, layout.right = Trade(layout.left), Trade(layout.right)
    local a, b = ns.BarData(key), ns.BarData(other)
    a.perRow, b.perRow = b.perRow, a.perRow
    ns.Bars:Rebuild()
    return true, ns.BAR_NAMES[key] .. " and " .. ns.BAR_NAMES[other] .. " swapped rows." .. self:Widths(key, other)
end

function L:CanMoveDisplay(delta)
    return #Placed(ns.LayoutData(), delta < 0 and "above" or "below") > 0
end

-- Moves the display up or down past one row, which changes sides of it
-- (taken-out rows on the way go with it).
function L:MoveDisplay(delta)
    if InCombatLockdown() then return false, "Finish combat first." end
    if not self:CanMoveDisplay(delta) then return false end
    local layout = Edited()
    local moved
    repeat
        if delta < 0 then
            moved = table.remove(layout.above)
            table.insert(layout.below, 1, moved)
        else
            moved = table.remove(layout.below, 1)
            table.insert(layout.above, moved)
        end
    until not layout.hidden[moved]
    self:Stack()
    return true
end

-- Your bars stay where they are, and the display gets Blizzard's width back.
function L:TurnOff()
    local layout = ns.LayoutData()
    if not (layout and layout.on) then return end
    layout.on = false
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
        "UI_SCALE_CHANGED", "DISPLAY_SIZE_CHANGED", "CVAR_UPDATE" }) do
        events:RegisterEvent(event)
    end
    events:SetScript("OnEvent", function(_, event, name)
        if event == "PLAYER_REGEN_ENABLED" then
            if ns.Resource and ns.Resource.pendingMatch then ns.Resource:Match() end
            if L.pending then
                L.pending = nil
                L:Stack()
            end
        elseif event == "CVAR_UPDATE" then
            -- The display switched on or off in Options: the rows make room
            -- or close up.
            if type(name) == "string" and not (issecretvalue and issecretvalue(name))
                and name:lower() == "nameplateshowself" then
                L:Stack()
            end
        elseif event ~= "ADDON_LOADED" or name == "Blizzard_PersonalResourceDisplay" then
            -- Edit Mode puts the display in place as the world loads, as
            -- it's switched on, and again when the screen changes size.
            C_Timer.After(1, function() L:Stack() end)
        end
    end)
end
