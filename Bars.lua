-- Classic Bars: the addon's own rows of square Classic icons for the spells
-- you pick. Cooldowns are secret in combat, so each icon hands the game's
-- duration object straight to its sweep, greying and hide-when-ready without
-- ever reading it; only the open "usable" and range checks are read here.
-- The icons never take the mouse, so they can't get in the way in combat.
local _, ns = ...

local B = {}
ns.Bars = B

local SQUARE = "Interface\\Buttons\\WHITE8X8"
local TIMER_FONT = "SystemFont_Shadow_Large_Outline"
local DEFAULT_Y = { buff = 234, cd = 190, util = 146 } -- just above the action bar
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
local unlocked, inCombat = false, false

local function Open(value)
    return not (issecretvalue and issecretvalue(value))
end

-- Icons ---------------------------------------------------------------------------

local function NewIcon(bar)
    local icon = CreateFrame("Frame", nil, bar)
    icon:EnableMouse(false)
    -- A gold edge outside the dark one marks a reactive ability that is ready.
    icon.glow = icon:CreateTexture(nil, "BACKGROUND", nil, -8)
    icon.glow:SetColorTexture(1, .82, 0, 1)
    icon.glow:SetPoint("TOPLEFT", -2, 2)
    icon.glow:SetPoint("BOTTOMRIGHT", 2, -2)
    icon.glow:Hide()
    icon.edge = icon:CreateTexture(nil, "BACKGROUND", nil, -7)
    icon.edge:SetColorTexture(0, 0, 0, .9)
    icon.edge:SetPoint("TOPLEFT", -1, 1)
    icon.edge:SetPoint("BOTTOMRIGHT", 1, -1)
    icon.texture = icon:CreateTexture(nil, "ARTWORK")
    icon.texture:SetAllPoints()
    icon.cooldown = CreateFrame("Cooldown", nil, icon, "CooldownFrameTemplate")
    icon.cooldown:SetAllPoints()
    icon.cooldown:SetSwipeTexture(SQUARE)
    icon.cooldown:SetSwipeColor(0, 0, 0, .7)
    icon.cooldown:SetDrawEdge(false)
    icon.cooldown:SetDrawBling(false)
    if _G[TIMER_FONT] then icon.cooldown:SetCountdownFont(TIMER_FONT) end
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
        icon:SetAlpha(data.hideReady and not active and 0 or 1)
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

local function RefreshIcon(icon, data, hasTarget)
    if icon.kind == "item" or icon.kind == "slot" then return RefreshItem(icon, data) end
    local id = icon.spellID
    local duration = C_Spell.GetSpellCooldownDuration and C_Spell.GetSpellCooldownDuration(id, true)
    if duration then
        icon.cooldown:SetCooldownFromDurationObject(duration)
        -- Secret in combat: passed to the game as it is, never tested here.
        local active = duration:IsActive()
        icon.texture:SetDesaturated(active)
        if data.hideReady and icon.SetAlphaFromBoolean then icon:SetAlphaFromBoolean(active) else icon:SetAlpha(1) end
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

local function Place(bar)
    local data = bar.data
    bar:ClearAllPoints()
    if data.x and data.y then
        bar:SetPoint("CENTER", UIParent, "CENTER", data.x, data.y)
    else
        bar:SetPoint("BOTTOM", UIParent, "BOTTOM", 0, DEFAULT_Y[bar.key] or 160)
    end
end

local function SavePosition(bar)
    local x, y = bar:GetCenter()
    local cx, cy = UIParent:GetCenter()
    if not (x and cx) then return end
    bar.data.x = math.floor((x - cx) * 10 + .5) / 10
    bar.data.y = math.floor((y - cy) * 10 + .5) / 10
    ns.SaveBars()
    Place(bar)
end

-- The Buffs bar holds Blizzard's secure buff slots, so it is only ever
-- shown, hidden, moved or resized outside combat.
local function Locked(bar)
    return bar.kind == "buff" and InCombatLockdown()
end

local function NewBar(key)
    local bar = CreateFrame("Frame", nil, UIParent)
    bar.key, bar.icons, bar.count = key, {}, 0
    bar.kind = key == "buff" and "buff" or "cooldown"
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
    mover:SetScript("OnDragStop", function()
        if not bar.dragging then return end
        bar.dragging = nil
        bar:StopMovingOrSizing()
        if bar.SetUserPlaced then bar:SetUserPlaced(false) end
        SavePosition(bar)
    end)
    mover:Hide()
    bar.mover = mover
    bars[key] = bar
    return bar
end

local function LayoutBuffs(bar, data)
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
    local size, spacing = data.size, data.spacing
    local slots = bar.count > 0 and bar.count or 3
    bar:SetSize(slots * size + (slots - 1) * spacing, size)
    Place(bar)
end

local function Layout(bar)
    local data = ns.BarData(bar.key)
    bar.data = data
    if bar.kind == "buff" then return LayoutBuffs(bar, data) end
    local size, spacing = data.size, data.spacing
    local count = 0
    for _, name in ipairs(data.spells) do
        local entry = ns.Spells:Find(name)
        if entry then
            count = count + 1
            local icon = bar.icons[count] or NewIcon(bar)
            bar.icons[count] = icon
            icon:SetSize(size, size)
            icon:ClearAllPoints()
            icon:SetPoint("LEFT", bar, "LEFT", (count - 1) * (size + spacing), 0)
            icon.spellID, icon.name, icon.reactive = entry.spellID, name, REACTIVE[name] == true
            icon.kind, icon.itemID, icon.slot = entry.kind, entry.itemID, entry.slot
            icon.texture:SetTexture(entry.icon or (entry.spellID and C_Spell.GetSpellTexture(entry.spellID)))
            icon.count:SetText("")
            icon.label:SetWidth(size + spacing)
            icon.label:SetText(entry.kind == "slot" and entry.name:gsub("^Trinket %d: ", "") or entry.name)
            icon.label:SetShown(data.showNames)
            icon:Show()
        end
    end
    for i = count + 1, #bar.icons do
        bar.icons[i]:Hide()
        bar.icons[i].spellID = nil
    end
    bar.count = count
    -- An empty bar keeps room for three icons so it can still be dragged.
    local slots = count > 0 and count or 3
    bar:SetSize(slots * size + (slots - 1) * spacing, size)
    Place(bar)
end

-- Public ------------------------------------------------------------------------------

function B:Enabled()
    return ns.Get("classicBars") == true
end

function B:Get(key)
    return bars[key]
end

function B:IsUnlocked()
    return unlocked
end

function B:UpdateShown()
    local on = self:Enabled()
    if not on then unlocked = false end
    for _, key in ipairs(ns.BAR_KEYS) do
        local bar = bars[key]
        if bar then
            if bar.kind == "buff" then
                -- Shown whenever it has buffs; "only in combat" fades it
                -- instead, since the secure slots can't be hidden in a fight.
                local show = on and (unlocked or bar.count > 0) or false
                if bar:IsShown() ~= show then
                    if InCombatLockdown() then bar.pendingShown = true else bar:SetShown(show) end
                end
                bar:SetAlpha((unlocked or not bar.data.combatOnly or inCombat) and 1 or 0)
            else
                local show = on and (unlocked or (bar.count > 0 and (not bar.data.combatOnly or inCombat)))
                bar:SetShown(show and true or false)
            end
            bar.mover:SetShown(on and unlocked)
        end
    end
end

function B:SetUnlocked(value)
    unlocked = value and self:Enabled() or false
    self:UpdateShown()
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
                    print("|cffffd100" .. ns.TITLE .. ":|r a Classic Bars icon couldn't update. Please report this: " .. self.lastError)
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
end

-- Setup changes. Each saves the backup and redraws the bars.

function B:Changed()
    ns.PruneCustom()
    ns.SaveBars()
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

function B:HasBuff(name)
    return IndexOf("buff", name) ~= nil
end

-- Puts a spell on the Cooldowns or Utility bar, or takes it off with no bar;
-- it sits on one of the two at a time. Returns false when the bar is full.
function B:Assign(name, key)
    local current, index = self:Find(name)
    if current == key then return true end
    if key and #ns.BarData(key).spells >= ns.BAR_MAX_SPELLS then return false end
    if current then table.remove(ns.BarData(current).spells, index) end
    if key then
        local spells = ns.BarData(key).spells
        spells[#spells + 1] = name
    end
    self:Changed()
    return true
end

-- Buffs are tracked separately, so a spell can be on a cooldown bar and the
-- Buffs bar at once (a cooldown that also buffs you). Returns false when full.
function B:SetBuff(name, on)
    local index = IndexOf("buff", name)
    if on and index or not on and not index then return true end
    local spells = ns.BarData("buff").spells
    if on then
        if #spells >= ns.BUFF_SLOTS then return false end
        spells[#spells + 1] = name
    else
        table.remove(spells, index)
    end
    self:Changed()
    return true
end

function B:Move(key, index, delta)
    local spells = ns.BarData(key).spells
    local target = index + delta
    if not spells[index] or target < 1 or target > #spells then return end
    spells[index], spells[target] = spells[target], spells[index]
    self:Changed()
end

function B:Remove(key, index)
    local spells = ns.BarData(key).spells
    if not spells[index] then return end
    table.remove(spells, index)
    self:Changed()
end

function B:SetOption(key, field, value)
    ns.BarData(key)[field] = value
    self:Changed()
end

function B:ResetPositions()
    for _, key in ipairs(ns.BAR_KEYS) do
        local data = ns.BarData(key)
        data.x, data.y = nil, nil
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
            B:UpdateShown()
        elseif event == "PLAYER_REGEN_ENABLED" then
            inCombat = false
            -- Anything the Buffs bar had to wait for during the fight.
            local buffs = bars.buff
            if buffs and buffs.pendingLayout then
                Layout(buffs)
            elseif buffs and buffs.pending then
                ns.BuffBar:Apply(buffs)
            end
            if buffs then buffs.pendingShown = nil end
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
    self:Rebuild()
end
