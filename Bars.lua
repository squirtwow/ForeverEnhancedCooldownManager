-- The addon's own bars: rows of square frameless icons for the spells you
-- pick. Cooldowns are secret in combat, so each icon hands the game's
-- duration object straight to its sweep, greying and hide-when-ready without
-- ever reading it; only the open "usable" and range checks are read here.
-- The icons never take the mouse, so they can't get in the way in combat.
local _, ns = ...

local B = {}
ns.Bars = B

local Style = ns.Style
local DEFAULT_Y = { debuff = 278, buff = 234, cd = 190, util = 146 } -- just above the action bar
local RANGE_INTERVAL = .25
-- Blizzard's own Cooldown Manager tints.
local TINT = {
    ready = { 1, 1, 1 },
    mana = { .5, .5, 1 },
    unusable = { .4, .4, .4 },
    range = { .64, .15, .15 },
}
-- Abilities that only become usable after something happens in the fight.
local REACTIVE = {
    Overpower = true, Revenge = true, Execute = true, Riposte = true,
    Counterattack = true, ["Mongoose Bite"] = true,
}

local bars = {}
local unlocked, inCombat, editMode = false, false, false
local FADE = .3 -- a faded bar's opacity out of combat

local function Open(value)
    return not (issecretvalue and issecretvalue(value))
end

-- Hide when ready waits while the bars are being arranged (unlocked, or in
-- Edit Mode), so every icon on them can be seen.
local function HidesReady(data)
    return data.hideReady and not (unlocked or editMode)
end

-- Icons ---------------------------------------------------------------------------

local function NewIcon(bar)
    local icon = CreateFrame("Frame", nil, bar)
    icon:EnableMouse(false)
    -- A gold edge around the icon marks a reactive ability that is ready.
    icon.glow = icon:CreateTexture(nil, "BACKGROUND", nil, -8)
    icon.glow:SetColorTexture(1, .82, 0, 1)
    icon.glow:SetPoint("TOPLEFT", -2, 2)
    icon.glow:SetPoint("BOTTOMRIGHT", 2, -2)
    icon.glow:Hide()
    icon.texture = icon:CreateTexture(nil, "ARTWORK")
    icon.texture:SetAllPoints()
    Style:Zoom(icon.texture)
    icon.cooldown = CreateFrame("Cooldown", nil, icon, "CooldownFrameTemplate")
    icon.cooldown:SetAllPoints(icon.texture)
    icon.cooldown:SetSwipeTexture(Style.FLAT)
    icon.cooldown:SetSwipeColor(0, 0, 0, .7)
    icon.cooldown:SetDrawEdge(false)
    icon.cooldown:SetDrawBling(false)
    -- Events arrive when a cooldown starts, not when it ends; this catches the
    -- end, so the icon ungreys (or hides when ready) on time.
    icon.cooldown:SetScript("OnCooldownDone", function() B:RefreshAll() end)
    -- Item counts sit above the sweep.
    local top = CreateFrame("Frame", nil, icon)
    top:SetAllPoints()
    top:SetFrameLevel(icon.cooldown:GetFrameLevel() + 1)
    icon.count = top:CreateFontString(nil, "OVERLAY", "NumberFontNormal")
    icon.count:SetPoint("BOTTOMRIGHT", -1, 1)
    icon.label = icon:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    icon.label:SetPoint("TOP", icon, "BOTTOM", 0, -3)
    icon.label:SetWordWrap(false)
    icon.decor = Style:Decor(icon, icon)
    Style:ShowDecor(icon.decor, Style:DecorFor("icon"))
    return icon
end

-- Trinkets and bag items. Their cooldowns come back as plain numbers; if the
-- game ever hides them in combat, the icon simply keeps its last state.
local function RefreshItem(icon, data)
    local start, duration
    if icon.kind == "slot" then
        start, duration = GetInventoryItemCooldown("player", icon.slot)
    else
        start, duration = C_Item.GetItemCooldown(icon.itemID)
    end
    if Open(start) and Open(duration) and type(start) == "number" and type(duration) == "number" then
        local active = start > 0 and duration > 1.5
        if active then icon.cooldown:SetCooldown(start, duration) else icon.cooldown:Clear() end
        icon.texture:SetDesaturated(active)
        icon:SetAlpha(HidesReady(data) and not active and 0 or 1)
    end
    local count
    if icon.kind == "item" then
        count = C_Item.GetItemCount(icon.itemID, false, true)
        if Open(count) and type(count) == "number" then
            icon.count:SetText(count)
            if count == 0 then icon.texture:SetDesaturated(true) end
        end
    end
    local usable, noMana = C_Item.IsUsableItem(icon.itemID)
    local tint = TINT.ready
    if Open(usable) and usable == false then
        tint = Open(noMana) and noMana and TINT.mana or TINT.unusable
    end
    icon.texture:SetVertexColor(tint[1], tint[2], tint[3])
    icon.glow:Hide()
end

-- Your ammunition: how many you carry, greyed when you're out.
local function RefreshAmmo(icon)
    local texture = GetInventoryItemTexture("player", icon.slot)
    if texture then icon.texture:SetTexture(texture) end
    local count = GetInventoryItemID("player", icon.slot) and GetInventoryItemCount("player", icon.slot) or 0
    if Open(count) and type(count) == "number" then
        icon.count:SetText(count)
        icon.texture:SetDesaturated(count == 0)
    end
    icon.cooldown:Clear()
    icon:SetAlpha(1)
    icon.texture:SetVertexColor(TINT.ready[1], TINT.ready[2], TINT.ready[3])
    icon.glow:Hide()
end

local function RefreshIcon(icon, data, hasTarget)
    if icon.kind == "ammo" then return RefreshAmmo(icon) end
    if icon.kind == "item" or icon.kind == "slot" then return RefreshItem(icon, data) end
    local id = icon.spellID
    local duration = C_Spell.GetSpellCooldownDuration and C_Spell.GetSpellCooldownDuration(id, true)
    if duration then
        icon.cooldown:SetCooldownFromDurationObject(duration)
        -- Secret in combat: passed to the game as it is, never tested here.
        local active = duration:IsActive()
        icon.texture:SetDesaturated(active)
        if HidesReady(data) and icon.SetAlphaFromBoolean then icon:SetAlphaFromBoolean(active) else icon:SetAlpha(1) end
    else
        icon.cooldown:Clear()
        icon.texture:SetDesaturated(false)
        icon:SetAlpha(1)
    end
    local usable, noMana = C_Spell.IsSpellUsable(id)
    local inRange
    if hasTarget and C_Spell.IsSpellInRange then inRange = C_Spell.IsSpellInRange(id, "target") end
    local tint = TINT.ready
    if Open(inRange) and inRange == false then
        tint = TINT.range
    elseif Open(usable) and not usable then
        tint = Open(noMana) and noMana and TINT.mana or TINT.unusable
    end
    icon.texture:SetVertexColor(tint[1], tint[2], tint[3])
    icon.glow:SetShown(icon.reactive and Open(usable) and usable == true or false)
end

-- Bars ------------------------------------------------------------------------------

local NAMES = 14 -- room for spell names under a row of icons

-- Rows of up to perRow icons (or aura spots). Each row lines up by the bar's
-- grow choice: centred, from the right edge (growing left, first icon on the
-- right) or from the left edge; a new row goes below or above. Returns the
-- bar's size.
function B:Arrange(bar, frames, count, data)
    local size, spacing = data.size, data.spacing
    -- An empty bar keeps room for three icons so it can still be dragged.
    if count < 1 then return 3 * size + 2 * spacing, size end
    local across = math.max(1, math.min(data.perRow, count))
    local rows = math.ceil(count / across)
    local step = size + spacing + (data.showNames and NAMES or 0)
    local width = across * size + (across - 1) * spacing
    for i = 1, count do
        local row, column = math.floor((i - 1) / across), (i - 1) % across
        local inRow = math.min(across, count - row * across)
        local x
        if data.grow == "left" then
            x = width - size - column * (size + spacing)
        elseif data.grow == "right" then
            x = column * (size + spacing)
        else
            x = (width - (inRow * size + (inRow - 1) * spacing)) / 2 + column * (size + spacing)
        end
        local frame = frames[i]
        frame:ClearAllPoints()
        if data.wrap == "up" then
            frame:SetPoint("BOTTOMLEFT", bar, "BOTTOMLEFT", x, row * step)
        else
            frame:SetPoint("TOPLEFT", bar, "TOPLEFT", x, -row * step)
        end
    end
    return width, size + (rows - 1) * step
end

-- The point a bar is held by: the edge its rows grow away from, so icons
-- already there stay put as more are added.
local function Point(data)
    local side = data.grow == "left" and "RIGHT" or data.grow == "right" and "LEFT" or ""
    return (data.wrap == "up" and "BOTTOM" or "TOP") .. side, side
end

-- Where a point is, from the bar's centre.
local function Offset(point, width, height)
    local x = point:find("LEFT") and -width / 2 or point:find("RIGHT") and width / 2 or 0
    local y = point:find("TOP") and height / 2 or point:find("BOTTOM") and -height / 2 or 0
    return x, y
end

local function Round(n)
    return math.floor(n * 10 + .5) / 10
end

local function Place(bar)
    local data = bar.data
    local width, height = bar:GetWidth() or 0, bar:GetHeight() or 0
    local point, side = Point(data)
    bar:ClearAllPoints()
    if data.x and data.y then
        -- Kept for another point (from the centre, before rows existed):
        -- moved over to this one without the bar shifting.
        local from = data.point or "CENTER"
        if from ~= point then
            local fromX, fromY = Offset(from, width, height)
            local toX, toY = Offset(point, width, height)
            data.x, data.y, data.point = Round(data.x - fromX + toX), Round(data.y - fromY + toY), point
        end
        bar:SetPoint(point, UIParent, "CENTER", data.x, data.y)
    else
        -- Just above the action bar, growing up from there.
        local low = "BOTTOM" .. side
        bar:SetPoint(low, UIParent, "BOTTOM", (Offset(low, width, height)), DEFAULT_Y[bar.key] or 160)
    end
end

local function SavePosition(bar)
    local x, y = bar:GetCenter()
    local cx, cy = UIParent:GetCenter()
    if not (x and cx) then return end
    local point = Point(bar.data)
    local offsetX, offsetY = Offset(point, bar:GetWidth() or 0, bar:GetHeight() or 0)
    bar.data.x, bar.data.y, bar.data.point = Round(x - cx + offsetX), Round(y - cy + offsetY), point
    -- A bar moved by hand leaves the layout it was stacked in.
    if ns.Layout then ns.Layout:Moved() end
    Place(bar)
end

-- The Buffs and Debuffs bars hold Blizzard's secure aura slots, so they are
-- only ever shown, hidden, moved or resized outside combat.
local function Locked(bar)
    return bar.kind == "aura" and InCombatLockdown()
end

-- Lets go of a bar being dragged, where it is now.
local function Drop(bar)
    if not bar.dragging then return end
    bar.dragging = nil
    bar:StopMovingOrSizing()
    if bar.SetUserPlaced then bar:SetUserPlaced(false) end
    SavePosition(bar)
end

-- The border and shadow round a whole bar, when chosen, only go round icons
-- that stay put. Packed Buffs and Debuffs and a bar that hides when ready
-- come and go (like Blizzard's Tracked Buffs), so they'd leave an empty box
-- behind, as would the greyed Debuffs spots while there's no enemy.
local function BarDecor(bar)
    -- A layout waiting for the fight to end still has the old shape: keep the
    -- box as it is until then.
    if bar.pendingLayout then return end
    local border, shadow = Style:DecorFor("bar")
    local steady
    if bar.kind == "aura" then
        steady = not ns.BuffBar:Packed(bar.data) and bar.enemy ~= false
    else
        steady = not HidesReady(bar.data)
    end
    border, shadow = border and steady, shadow and steady
    local state = (border and "b" or "") .. (shadow and "s" or "")
    if bar.decorState == state then return end
    bar.decorState = state
    Style:ShowDecor(bar.decor, border, shadow)
end

-- Blizzard's packed Buffs and Debuffs icons can't be used by the addon while
-- auras are secret (in combat), so theirs change once the fight is over.
local function GroupDecor(bar)
    if not (bar.groupParts and bar.groupParts[1]) then
        bar.pendingDecor = nil
        return
    end
    if InCombatLockdown() then
        bar.pendingDecor = true
        return
    end
    bar.pendingDecor = nil
    local border, shadow = Style:DecorFor("icon")
    for _, parts in ipairs(bar.groupParts) do Style:ShowDecor(parts.decor, border, shadow) end
end

local function NewBar(key)
    local bar = CreateFrame("Frame", nil, UIParent)
    bar.key, bar.icons, bar.count = key, {}, 0
    bar.kind = ns.AURA_BARS[key] and "aura" or "cooldown"
    bar.data = ns.BarData(key)
    bar:SetFrameStrata("MEDIUM")
    bar:SetMovable(true)
    bar:SetClampedToScreen(true)
    bar:Hide()

    local mover = CreateFrame("Frame", nil, bar)
    mover:SetPoint("TOPLEFT", -4, 4)
    mover:SetPoint("BOTTOMRIGHT", 4, -4)
    mover:SetFrameLevel(bar:GetFrameLevel() + 20)
    mover:EnableMouse(true)
    mover:RegisterForDrag("LeftButton")
    mover.fill = mover:CreateTexture(nil, "BACKGROUND")
    mover.fill:SetAllPoints()
    mover.fill:SetColorTexture(.25, .55, 1, .45)
    -- The name sits inside the highlight, so it never covers another bar.
    mover.label = mover:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    mover.label:SetPoint("CENTER")
    mover.label:SetText(ns.BAR_NAMES[key])
    mover:SetScript("OnDragStart", function()
        if not Locked(bar) then
            bar.dragging = true
            bar:StartMoving()
        end
    end)
    mover:SetScript("OnDragStop", function() Drop(bar) end)
    -- A spell or item dragged from anywhere onto an unlocked bar joins it.
    mover:SetScript("OnReceiveDrag", function() B:Dropped(key) end)
    mover:SetScript("OnMouseUp", function() B:Dropped(key) end)
    mover:Hide()
    bar.mover = mover
    -- A border and shadow round the whole bar, when chosen.
    bar.decor = Style:Decor(bar, bar)
    BarDecor(bar)
    bars[key] = bar
    return bar
end

local function LayoutAuras(bar, data)
    if InCombatLockdown() then
        bar.pendingLayout = true
        return
    end
    bar.pendingLayout = nil
    if not bar.created then
        bar.created = true
        ns.BuffBar:Create(bar)
    end
    ns.BuffBar:Layout(bar, data)
    -- Fixed spots go in rows like icons; packed buffs are laid out by the
    -- game in one row.
    if ns.BuffBar:Packed(data) then
        local slots = bar.count > 0 and bar.count or 3
        bar:SetSize(slots * data.size + (slots - 1) * data.spacing, data.size)
    else
        bar:SetSize(B:Arrange(bar, bar.holders, bar.count, data))
    end
    Place(bar)
end

local function Layout(bar)
    local data = ns.BarData(bar.key)
    bar.data = data
    if bar.kind == "aura" then return LayoutAuras(bar, data) end
    local size, spacing = data.size, data.spacing
    local count = 0
    for _, name in ipairs(data.spells) do
        local entry = ns.Spells:Find(name)
        if entry and ns.Spells:ForMe(name, bar.key) then
            count = count + 1
            local icon = bar.icons[count] or NewIcon(bar)
            bar.icons[count] = icon
            icon:SetSize(size, size)
            icon.cooldown:SetCountdownFont(Style:Countdown(size))
            icon.cooldown:SetHideCountdownNumbers(not data.showTimer)
            icon.count:SetFontObject(Style:Count(size))
            icon.spellID, icon.name, icon.reactive = entry.spellID, name, REACTIVE[entry.baseName or entry.name] == true
            icon.kind, icon.itemID, icon.slot = entry.kind, entry.itemID, entry.slot
            icon.texture:SetTexture(entry.icon or (entry.spellID and C_Spell.GetSpellTexture(entry.spellID)))
            icon.count:SetText("")
            icon.label:SetWidth(size + spacing)
            icon.label:SetText((entry.name:gsub("^Trinket %d: ", ""):gsub("^Ammo: ", "")))
            icon.label:SetShown(data.showNames)
            icon:Show()
        end
    end
    for i = count + 1, #bar.icons do
        bar.icons[i]:Hide()
        bar.icons[i].spellID = nil
    end
    bar.count = count
    bar:SetSize(B:Arrange(bar, bar.icons, count, data))
    Place(bar)
end

-- Public ------------------------------------------------------------------------------

function B:Enabled()
    return ns.Get("useBars") == true
end

-- Borders and shadows as chosen on the Look page, round every icon or bar.
function B:ApplyDecor()
    local border, shadow = Style:DecorFor("icon")
    for _, bar in pairs(bars) do
        BarDecor(bar)
        for _, icon in ipairs(bar.icons or {}) do Style:ShowDecor(icon.decor, border, shadow) end
        ns.BuffBar:HolderDecor(bar)
        GroupDecor(bar)
    end
end

function B:Get(key)
    return bars[key]
end

function B:IsUnlocked()
    return unlocked
end

-- Bars come back in full in combat, with an enemy targeted, while unlocked
-- and while Edit Mode is open; otherwise each follows its out-of-combat
-- choice. A hidden answer about the target counts as an enemy.
local function Awake()
    if inCombat or unlocked or editMode then return true end
    local hostile = UnitExists("target") and UnitCanAttack("player", "target")
    if not Open(hostile) then return true end
    return hostile and true or false
end

function B:UpdateShown()
    local on = self:Enabled()
    if not on then unlocked = false end
    local awake = Awake()
    for _, key in ipairs(ns.BAR_KEYS) do
        local bar = bars[key]
        if bar then
            local mode = awake and "show" or bar.data.outOfCombat
            -- A bar taken out of your layout doesn't show at all.
            local out = ns.Layout ~= nil and ns.Layout:IsHidden(key)
            if bar.kind == "aura" then
                -- Shown whenever it has entries; hiding out of combat fades it
                -- right out instead, since the secure slots can't be hidden in
                -- a fight.
                local show = on and not out and (unlocked or bar.count > 0) or false
                if bar:IsShown() ~= show then
                    if InCombatLockdown() then bar.pendingShown = true else bar:SetShown(show) end
                end
                bar:SetAlpha(mode == "hide" and 0 or mode == "fade" and FADE or 1)
            else
                local show = on and not out and (unlocked or (bar.count > 0 and mode ~= "hide"))
                bar:SetShown(show and true or false)
                bar:SetAlpha(mode == "fade" and FADE or 1)
            end
            bar.mover:SetShown(on and unlocked)
            BarDecor(bar)
        end
    end
end

function B:SetUnlocked(value)
    unlocked = value and self:Enabled() or false
    self:UpdateShown()
    self:RefreshAll()
    -- Unlocked, empty bars show too, so a layout makes room for them.
    if ns.Layout then ns.Layout:Stack() end
end

function B:RefreshAll()
    if not (self.started and self:Enabled()) then return end
    local hasTarget = UnitExists("target") and true or false
    for _, key in ipairs(ns.BAR_KEYS) do
        local bar = bars[key]
        if bar and bar.kind == "cooldown" then
            for i = 1, bar.count do
                local ok, err = pcall(RefreshIcon, bar.icons[i], bar.data, hasTarget)
                if not ok and not self.lastError then
                    self.lastError = tostring(err)
                    print("|cffffd100" .. ns.TITLE .. ":|r a bar icon couldn't update. Please report this: " .. self.lastError)
                end
            end
        end
    end
end

function B:Rebuild()
    if not self.started then return end
    ns.Spells:Scan()
    for _, key in ipairs(ns.BAR_KEYS) do Layout(bars[key] or NewBar(key)) end
    self:UpdateShown()
    self:RefreshAll()
    if ns.Layout then ns.Layout:Stack() end
end

-- Setup changes. Each redraws the bars.

function B:Changed()
    ns.PruneCustom()
    self:Rebuild()
end

local SPELL_BARS = { "cd", "util" }

local function IndexOf(key, name)
    for i, spell in ipairs(ns.BarData(key).spells) do
        if spell == name then return i end
    end
end

-- The cooldown bar a spell is on, and its place there.
function B:Find(name)
    for _, key in ipairs(SPELL_BARS) do
        local index = IndexOf(key, name)
        if index then return key, index end
    end
end

-- Whether a spell is on the Buffs or Debuffs bar.
function B:HasAura(key, name)
    return IndexOf(key, name) ~= nil
end

-- Where an entry is on a bar, if it's there.
function B:Index(key, name)
    return IndexOf(key, name)
end

-- The entries on a bar that are for you, in order, and where each one is in
-- the list: a profile shared with another class keeps its spells too.
function B:Mine(key)
    local names, places = {}, {}
    for i, name in ipairs(ns.BarData(key).spells) do
        if ns.Spells:ForMe(name, key) then
            names[#names + 1], places[#places + 1] = name, i
        end
    end
    return names, places
end

function B:HasBuff(name)
    return self:HasAura("buff", name)
end

-- Joins -------------------------------------------------------------------------------
-- On the Buffs and Debuffs bars an entry can be joined to the one before it;
-- a run of joined entries shows as one icon. The first entry never joins.

function B:Joined(key, index)
    local spells = ns.BarData(key).spells
    return ns.AURA_BARS[key] ~= nil and index > 1 and spells[index] ~= nil and ns.Joins(key)[spells[index]] == true
end

local function Full(key)
    return ns.BAR_NAMES[key] .. " is full."
end

-- The bar's entries in order, with joined ones gathered into one group.
function B:Units(key)
    local units = {}
    for i, name in ipairs(ns.BarData(key).spells) do
        if self:Joined(key, i) and #units > 0 then
            table.insert(units[#units], name)
        else
            units[#units + 1] = { name }
        end
    end
    return units
end

-- How many of an aura bar's slots your entries take: one per icon, so a
-- joined group counts once, and another class's entries take none.
function B:SlotsUsed(key)
    local used = 0
    for _, unit in ipairs(self:Units(key)) do
        for _, name in ipairs(unit) do
            if ns.Spells:ForMe(name, key) then
                used = used + 1
                break
            end
        end
    end
    return used
end

-- Split off, an entry needs an icon of its own; not past the bar's slots.
function B:SetJoined(key, index, on)
    local spells = ns.BarData(key).spells
    if not ns.AURA_BARS[key] or index < 2 or not spells[index] then return false end
    local joins, name = ns.Joins(key), spells[index]
    local was, used = joins[name], self:SlotsUsed(key)
    joins[name] = on and true or nil
    local now = self:SlotsUsed(key)
    if now > used and now > ns.BUFF_SLOTS then
        joins[name] = was
        return false, Full(key)
    end
    self:Changed()
    return true
end

-- Takes an entry off a bar. When it heads a joined group, the next entry
-- becomes the head, so the rest stay together without joining the entry
-- before.
local function Take(key, index)
    local spells = ns.BarData(key).spells
    local name = spells[index]
    if not name then return end
    if ns.AURA_BARS[key] then
        local joins = ns.Joins(key)
        local after = spells[index + 1]
        if after and not joins[name] then joins[after] = nil end
        joins[name] = nil
    end
    table.remove(spells, index)
    return name
end

-- Puts a spell on the Cooldowns or Utility bar, or takes it off with no bar;
-- it sits on one of the two at a time. Returns false when the bar is full.
function B:Assign(name, key)
    local current, index = self:Find(name)
    if current == key then return true end
    if key and #ns.BarData(key).spells >= ns.BAR_MAX_SPELLS then return false end
    if current then Take(current, index) end
    if key then
        local spells = ns.BarData(key).spells
        spells[#spells + 1] = name
    end
    self:Changed()
    return true
end

-- The Buffs and Debuffs bars are tracked separately, so a spell can be on a
-- cooldown bar and an aura bar at once (a cooldown that also buffs you).
-- Returns false when the bar is full.
function B:SetAura(key, name, on)
    local index = IndexOf(key, name)
    if on and index or not on and not index then return true end
    local spells = ns.BarData(key).spells
    if on then
        -- The slots are for your own icons, one per joined group; the list
        -- has room for more.
        if self:SlotsUsed(key) >= ns.BUFF_SLOTS or #spells >= ns.BAR_MAX_SPELLS then return false end
        spells[#spells + 1] = name
    else
        Take(key, index)
    end
    self:Changed()
    return true
end

function B:SetBuff(name, on)
    return self:SetAura("buff", name, on)
end

local function Added(key, name)
    return "Added " .. name .. " to " .. ns.BAR_NAMES[key] .. "."
end

-- Whether an entry can show on a bar: true, or false and why not. Items put
-- no aura on anyone, a fixed rank adds nothing to an aura bar (it counts
-- every rank already), and procs are buffs on you with no cooldown of their
-- own. Anything not known here (another class's, say) may go anywhere.
function B:Fits(key, entry)
    if not entry then return true end
    local bar = ns.BAR_NAMES[key]
    if ns.AURA_BARS[key] and ns.Spells:IsItem(entry) then
        return false, "Items can't go on the " .. bar .. " bar."
    end
    if ns.AURA_BARS[key] and entry.kind == "rank" then
        return false, "Fixed ranks can't go on the " .. bar .. " bar, which counts every rank already."
    end
    if entry.kind == "proc" and key ~= "buff" then
        return false, "Procs only go on the Buffs bar."
    end
    return true
end

-- Puts a spell, by name or ID, on a bar: true and what happened, or false
-- and why not. Spells outside your spellbook are remembered by name. Also
-- gives the name it's kept under.
function B:Add(key, text)
    local found, ids = ns.Spells:Resolve(text)
    if not found then return false, ids end
    local entry = ns.Spells:Find(found)
    local fits, why = self:Fits(key, entry)
    if not fits then return false, why end
    if ids and not entry then ns.AddCustom(found, ids) end
    local ok
    if ns.AURA_BARS[key] then ok = self:SetAura(key, found, true) else ok = self:Assign(found, key) end
    ns.PruneCustom()
    if not ok then return false, Full(key) end
    return true, Added(key, entry and entry.name or found), found
end

-- The same, at a place in the bar's list (where the entry clicked is): the
-- entries from there on move along one.
function B:AddAt(key, text, spot)
    local ok, message, name = self:Add(key, text)
    local from = ok and IndexOf(key, name)
    if from and spot < from then self:MoveTo(key, from, spot) end
    return ok, message
end

-- An item with a cooldown: an equipped trinket follows its slot.
function B:AddItem(key, itemID)
    if ns.AURA_BARS[key] then return false, "Items can't go on the " .. ns.BAR_NAMES[key] .. " bar." end
    local item = "item:" .. itemID
    for _, slot in ipairs({ 13, 14 }) do
        if GetInventoryItemID("player", slot) == itemID then item = "slot:" .. slot end
    end
    local entry = ns.Spells:Find(item)
    if not entry then return false, "That item has no cooldown to show." end
    if not self:Assign(item, key) then return false, ns.BAR_NAMES[key] .. " is full." end
    return true, Added(key, entry.name)
end

-- What's on the cursor, dropped on a bar: a spell from any spellbook or an
-- action bar, or an item. Nil when the cursor holds nothing.
function B:AddFromCursor(key)
    local kind, first, _, spellID = GetCursorInfo()
    if not kind then return nil end
    local ok, message
    if kind == "spell" and type(spellID) == "number" then
        ok, message = self:Add(key, tostring(spellID))
    elseif kind == "item" and type(first) == "number" then
        ok, message = self:AddItem(key, first)
    else
        ok, message = false, "Only spells and items can go on a bar."
    end
    ClearCursor()
    return ok, message
end

-- A drop on one of the addon's own frames for a bar; says what happened in
-- the window. False when nothing was dropped.
function B:Dropped(key)
    local ok, message = self:AddFromCursor(key)
    if ok == nil then return false end
    if ns.window and ns.window:IsShown() then
        ns.window:Say(message)
        ns.window:Refresh()
    end
    return true
end

function B:Move(key, index, delta)
    self:MoveTo(key, index, index + delta)
end

-- Moves a spell to another place on its bar, as dragged in the window. A
-- moved entry leaves its joined group; dropped inside another group, it
-- joins that one rather than splitting it. On its own it needs an icon of
-- its own, so a full bar keeps it where it was.
function B:MoveTo(key, from, to)
    local spells = ns.BarData(key).spells
    if from == to or not spells[from] or not spells[to] then return end
    local aura = ns.AURA_BARS[key] ~= nil
    local joins, saved, used = aura and ns.Joins(key), {}, 0
    if joins then
        for entry, on in pairs(joins) do saved[entry] = on end
        used = self:SlotsUsed(key)
    end
    local name = Take(key, from)
    table.insert(spells, to, name)
    local after = spells[to + 1]
    if aura and to > 1 and after and joins[after] then joins[name] = true end
    local now = aura and self:SlotsUsed(key) or 0
    if now > used and now > ns.BUFF_SLOTS then
        table.remove(spells, to)
        table.insert(spells, from, name)
        for entry in pairs(joins) do joins[entry] = nil end
        for entry, on in pairs(saved) do joins[entry] = on end
        return false, Full(key)
    end
    self:Changed()
    return true
end

function B:Remove(key, index)
    if not Take(key, index) then return end
    self:Changed()
end

local function Named(name)
    local entry = ns.Spells:Find(name)
    return entry and entry.name or name
end

-- An entry dragged off a bar: true and what happened.
function B:TakeOff(key, name)
    local index = IndexOf(key, name)
    if not index then return false end
    self:Remove(key, index)
    return true, "Took " .. Named(name) .. " off " .. ns.BAR_NAMES[key] .. "."
end

-- An entry dragged from one bar onto another: true and what happened, or
-- false and why not.
function B:Transfer(from, to, name)
    if from == to or not IndexOf(from, name) then return false end
    local fits, why = self:Fits(to, ns.Spells:Find(name))
    if not fits then return false, why end
    local ok
    if ns.AURA_BARS[to] then ok = self:SetAura(to, name, true) else ok = self:Assign(name, to) end
    if not ok then return false, Full(to) end
    -- Between the two cooldown bars it's already moved; otherwise take it off.
    local index = IndexOf(from, name)
    if index then self:Remove(from, index) end
    return true, "Moved " .. Named(name) .. " to " .. ns.BAR_NAMES[to] .. "."
end

-- An option only changes how one bar looks, so only that bar is redrawn;
-- the size slider sends a change for every step it's dragged.
function B:SetOption(key, field, value)
    ns.BarData(key)[field] = value
    if not self.started then return end
    Layout(bars[key] or NewBar(key))
    self:UpdateShown()
    self:RefreshAll()
    -- A bar in a layout may now be taller or shorter.
    if ns.Layout then ns.Layout:Stack() end
end

-- Puts a bar's point at a spot, from the middle of the screen, for a layout.
-- The Buffs and Debuffs bars move once a fight is over.
function B:PlaceAt(key, point, x, y)
    local data = ns.BarData(key)
    data.x, data.y, data.point = Round(x), Round(y), point
    local bar = bars[key]
    if not bar then return end
    if Locked(bar) then
        bar.pendingLayout = true
        return
    end
    Place(bar)
end

-- Lays one bar out again after a layout changes which way it grows.
function B:Relayout(key)
    if not self.started then return end
    local bar = bars[key] or NewBar(key)
    Layout(bar)
end

-- Empties a bar.
-- Clears what you see on a bar; another class's entries in a shared profile
-- stay for the characters that use them.
function B:Clear(key)
    local _, places = self:Mine(key)
    for n = #places, 1, -1 do Take(key, places[n]) end
    self:Changed()
end

function B:ResetPositions()
    -- Back above the action bar, so no longer stacked in a layout.
    if ns.Layout then ns.Layout:TurnOff() end
    for _, key in ipairs(ns.BAR_KEYS) do
        local data = ns.BarData(key)
        data.x, data.y, data.point = nil, nil, nil
    end
    self:Changed()
end

function B:Start()
    if self.started then return end
    self.started = true
    inCombat = UnitAffectingCombat("player") and true or false
    local driver = CreateFrame("Frame")
    for _, event in ipairs({ "PLAYER_ENTERING_WORLD", "SPELLS_CHANGED", "SPELL_UPDATE_COOLDOWN",
        "SPELL_UPDATE_USABLE", "PLAYER_TARGET_CHANGED", "PLAYER_REGEN_DISABLED", "PLAYER_REGEN_ENABLED",
        "BAG_UPDATE_COOLDOWN", "BAG_UPDATE_DELAYED", "PLAYER_EQUIPMENT_CHANGED" }) do
        driver:RegisterEvent(event)
    end
    driver:SetScript("OnEvent", function(_, event)
        if event == "PLAYER_REGEN_DISABLED" then
            inCombat = true
            -- A Buffs or Debuffs bar still being dragged is let go where it
            -- is, just before the fight locks it in place.
            for key in pairs(ns.AURA_BARS) do
                if bars[key] then Drop(bars[key]) end
            end
            B:UpdateShown()
        elseif event == "PLAYER_REGEN_ENABLED" then
            inCombat = false
            -- Anything the aura bars had to wait for during the fight.
            for key in pairs(ns.AURA_BARS) do
                local bar = bars[key]
                if bar and bar.pendingLayout then
                    Layout(bar)
                elseif bar and bar.pending then
                    ns.BuffBar:Apply(bar)
                end
                if bar and bar.pendingDecor then GroupDecor(bar) end
                if bar then bar.pendingShown = nil end
            end
            B:UpdateShown()
        elseif event == "BAG_UPDATE_DELAYED" then
            -- Counts change often; the item list only matters while /ccm is open.
            if ns.window and ns.window:IsShown() then
                B:Rebuild()
                ns.window:Refresh()
            else
                B:RefreshAll()
            end
        elseif event == "SPELLS_CHANGED" or event == "PLAYER_ENTERING_WORLD" or event == "PLAYER_EQUIPMENT_CHANGED" then
            B:Rebuild()
            if ns.window and ns.window:IsShown() then ns.window:Refresh() end
        else
            if event == "PLAYER_TARGET_CHANGED" then
                ns.BuffBar:UpdateTarget(bars.debuff)
                B:UpdateShown()
            end
            B:RefreshAll()
        end
    end)
    -- Range changes as you move, with no event for it.
    local elapsedTotal = 0
    driver:SetScript("OnUpdate", function(_, elapsed)
        elapsedTotal = elapsedTotal + elapsed
        if elapsedTotal < RANGE_INTERVAL then return end
        elapsedTotal = 0
        if B:Enabled() and UnitExists("target") then B:RefreshAll() end
    end)
    self.driver = driver
    -- Bars come back in full while Edit Mode is open.
    local editor = EditModeManagerFrame
    if editor and editor.HookScript then
        editor:HookScript("OnShow", function() editMode = true; B:UpdateShown(); B:RefreshAll() end)
        -- The resource display may have moved: a layout follows it.
        editor:HookScript("OnHide", function()
            editMode = false
            B:UpdateShown()
            B:RefreshAll()
            if ns.Layout then ns.Layout:Stack() end
        end)
        editMode = editor:IsShown() and true or false
    end
    self:Rebuild()
end
