-- The Buffs and Debuffs bars: your buffs and class procs while they're on
-- you, and your own debuffs on your target. Auras are secret in combat, so
-- the icons come from Blizzard's secure aura container, the same way the
-- portrait CC works in EraUI: each icon gets its look once, before the game
-- restricts it, and the addon only ever tells the container which spell IDs
-- belong where, never in combat. Entries joined together (seals, auras,
-- aspects, stings) share one icon that lights for whichever is up.
--
-- Two layouts:
-- * Packed (the default): one aura group per entry, in your order. Blizzard's
--   own layout places only the ones that are up, side by side and centred on
--   the bar, so there are no gaps, even in combat. Groups size themselves, so
--   the icon size comes from scaling the container.
-- * Fixed, with "Show missing ... greyed": one slot per entry, each following
--   a holder frame of the addon's own that keeps its place and shows the
--   entry greyed while it's missing.
local _, ns = ...

local F = {}
ns.BuffBar = F

local Style = ns.Style
local BASE = 36 -- packed icons are drawn at this size, then scaled

local function Open(value)
    return not (issecretvalue and issecretvalue(value))
end

-- What the container is told about a slot or group: its spell IDs, and on
-- the Debuffs bar, only auras you cast.
local function Filters(bar, ids)
    return { includeSpellIDs = ids, isFromPlayerOrPlayerPet = ns.AURA_BARS[bar.key].mine or nil }
end

function F:Available()
    return CustomAuraContainerSlotDefaultOptions ~= nil
end

function F:Packed(data)
    return not data.showMissing
end

-- Sizes an icon's numbers for its size, and shows or hides the countdown.
local function Fit(parts, size, showTimer)
    parts.cooldown:SetCountdownFont(Style:Countdown(size))
    parts.cooldown:SetHideCountdownNumbers(not showTimer)
    parts.count:SetFontObject(Style:Count(size))
end

-- Runs once per icon, before the client restricts it in combat. Everything
-- supplied to the icon must be a descendant of its button.
local function Look(button, size, showTimer)
    button:EnableMouse(false)
    local icon = button:CreateTexture(nil, "ARTWORK")
    icon:SetAllPoints()
    Style:Zoom(icon)
    button:SetIcon(icon)
    local cooldown = CreateFrame("Cooldown", nil, button, "CooldownFrameTemplate")
    cooldown:SetAllPoints(icon)
    cooldown:SetSwipeTexture(Style.FLAT)
    cooldown:SetSwipeColor(0, 0, 0, .7)
    cooldown:SetReverse(true)
    cooldown:SetDrawEdge(false)
    cooldown:SetDrawBling(false)
    button:SetDurationCooldown(cooldown)
    -- Stack counts sit above the sweep.
    local top = CreateFrame("Frame", nil, button)
    top:SetAllPoints()
    top:SetFrameLevel(cooldown:GetFrameLevel() + 1)
    local count = top:CreateFontString(nil, "OVERLAY", "NumberFontNormal")
    count:SetPoint("BOTTOMRIGHT", -1, 1)
    button:SetApplicationCount(count)
    local parts = { cooldown = cooldown, count = count }
    Fit(parts, size, showTimer)
    return parts
end

-- A slot's numbers take its holder's size; a later size change refits them.
local function SlotLook(holder)
    return function(button)
        button:SetAllPoints(holder)
        holder.slot = Look(button, holder.size or BASE, holder.showTimer ~= false)
    end
end

local function GroupLook(bar)
    return function(button)
        button:SetSize(BASE, BASE)
        bar.groupParts[#bar.groupParts + 1] = Look(button, BASE, bar.data.showTimer)
    end
end

function F:Create(bar)
    bar.holders, bar.slotIDs, bar.applied, bar.appliedGroups, bar.groups = {}, {}, {}, {}, 0
    bar.groupParts = {}
    for i = 1, ns.BUFF_SLOTS do
        local holder = CreateFrame("Frame", nil, bar)
        holder:EnableMouse(false)
        holder.icon = holder:CreateTexture(nil, "ARTWORK")
        holder.icon:SetAllPoints()
        Style:Zoom(holder.icon)
        holder.icon:SetDesaturated(true)
        holder.icon:SetAlpha(.45)
        holder.label = holder:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        holder.label:SetPoint("TOP", holder, "BOTTOM", 0, -3)
        holder.label:SetWordWrap(false)
        holder:Hide()
        bar.holders[i] = holder
    end
    if not self:Available() then return end
    local aura = ns.AURA_BARS[bar.key]
    local ok, err = pcall(function()
        local container = CreateFrame("AuraContainer", nil, bar, "CustomAuraContainerTemplate")
        -- One point only: packed groups resize the container around the
        -- entries that are up, and it stays on that point (the bar's centre,
        -- or the edge the bar grows from; see F:Layout).
        container:SetPoint("CENTER", bar, "CENTER")
        container:SetSize(BASE, BASE)
        container:EnableMouse(false)
        container:SetFrameLevel(bar:GetFrameLevel() + 5)
        container:SetEditModePreviewEnabled(false)
        container:SetUnit(aura.unit)
        for i = 1, ns.BUFF_SLOTS do
            container:AddAuraSlot("b" .. i, aura.filter, { initializeFrame = SlotLook(bar.holders[i]) })
            container:SetAuraSlotEnabled("b" .. i, false)
        end
        bar.container = container
    end)
    if not ok and not F.lastError then
        F.lastError = tostring(err)
        print("|cffffd100" .. ns.TITLE .. ":|r the " .. ns.BAR_NAMES[bar.key] .. " bar couldn't start. Please report this: " .. F.lastError)
    end
end

-- The Debuffs bar's greyed spots only show while you have a target you can
-- attack, and its icons follow a new target at once. Only the addon's own
-- textures change here, so this is fine in combat, as is the refresh, which
-- Blizzard's target frame does the same way.
function F:UpdateTarget(bar)
    if not (bar and bar.holders and ns.AURA_BARS[bar.key].unit == "target") then return end
    local hostile = UnitExists("target") and UnitCanAttack("player", "target")
    if not Open(hostile) then hostile = true end
    for _, holder in ipairs(bar.holders) do holder.icon:SetAlpha(hostile and .45 or 0) end
    if bar.container then bar.container:UpdateAllAuras() end
end

-- Places the holders for the bar's entries and works out each one's spell
-- IDs; joined entries count as one, with every linked spell's IDs.
function F:Layout(bar, data)
    local size, spacing = data.size, data.spacing
    local fixed = not self:Packed(data)
    local count = 0
    for _, group in ipairs(ns.Bars:Units(bar.key)) do
        local ids, entry = {}, nil
        for _, name in ipairs(group) do
            local found = ns.Spells:Find(name)
            if found and found.ids then
                entry = entry or found
                for _, id in ipairs(found.ids) do ids[id] = true end
            end
        end
        if entry and next(ids) and count < ns.BUFF_SLOTS then
            count = count + 1
            local holder = bar.holders[count]
            holder:SetSize(size, size)
            holder.size, holder.showTimer = size, data.showTimer
            if holder.slot then Fit(holder.slot, size, data.showTimer) end
            holder.icon:SetTexture(entry.icon)
            holder.label:SetWidth(size + spacing)
            holder.label:SetText(#group > 1 and (entry.name .. " +" .. (#group - 1)) or entry.name)
            holder.label:SetShown(data.showNames)
            holder:SetShown(fixed)
            bar.slotIDs[count] = ids
        end
    end
    for i = count + 1, ns.BUFF_SLOTS do
        bar.holders[i]:Hide()
        bar.slotIDs[i] = nil
    end
    for _, parts in ipairs(bar.groupParts) do parts.cooldown:SetHideCountdownNumbers(not data.showTimer) end
    bar.count = count
    -- Packed icons line up from the bar's centre, or from the edge the bar
    -- grows away from. (Fixed spots are placed in rows by the bar.)
    local side = data.grow == "left" and "RIGHT" or data.grow == "right" and "LEFT" or "CENTER"
    if bar.container and bar.containerSide ~= side then
        bar.containerSide = side
        bar.container:ClearAllPoints()
        bar.container:SetPoint(side, bar, side)
    end
    self:Apply(bar)
    self:UpdateTarget(bar)
end

local function Signature(ids)
    if not ids then return "" end
    local keys = {}
    for id in pairs(ids) do keys[#keys + 1] = id end
    table.sort(keys)
    return table.concat(keys, ",")
end

-- Tells the secure container which entries go where. Never in combat; a change
-- made then waits for the fight to end. Only what changed is sent.
function F:Apply(bar)
    local container = bar.container
    if not container then return end
    if InCombatLockdown() then
        bar.pending = true
        return
    end
    bar.pending = nil
    local data = bar.data
    local on = ns.Bars:Enabled()
    local packed = self:Packed(data)
    for i = 1, ns.BUFF_SLOTS do
        local ids = on and not packed and bar.slotIDs[i] or nil
        local signature = Signature(ids)
        if bar.applied[i] ~= signature then
            bar.applied[i] = signature
            local key = "b" .. i
            if ids then
                container:SetAuraSlotCandidateFilters(key, Filters(bar, ids))
                container:SetAuraSlotEnabled(key, true)
            else
                container:SetAuraSlotEnabled(key, false)
            end
        end
    end
    -- Groups are made as they're first needed; the game keeps them after that.
    local scale = packed and data.size / BASE or 1
    local spacing = data.spacing / scale
    -- Growing left, the first entry sits at the right, as fixed spots do.
    local function Index(i)
        return data.grow == "left" and ns.BUFF_SLOTS + 1 - i or i
    end
    if on and packed then
        for i = bar.groups + 1, bar.count do
            container:AddAuraGroup("g" .. i, ns.AURA_BARS[bar.key].filter, { initializeFrame = GroupLook(bar), maxFrameCount = 1,
                candidateFilters = Filters(bar, bar.slotIDs[i]), layout = { layoutIndex = Index(i), groupSpacing = spacing } })
            bar.groups = i
            bar.appliedGroups[i] = Signature(bar.slotIDs[i]) .. "|" .. spacing .. "|" .. Index(i)
        end
    end
    for i = 1, bar.groups do
        local ids = on and packed and bar.slotIDs[i] or nil
        local signature = ids and (Signature(ids) .. "|" .. spacing .. "|" .. Index(i)) or ""
        if bar.appliedGroups[i] ~= signature then
            bar.appliedGroups[i] = signature
            local key = "g" .. i
            if ids then
                container:SetAuraGroupCandidateFilters(key, Filters(bar, ids))
                container:SetAuraGroupLayout(key, { layoutIndex = Index(i), groupSpacing = spacing })
                container:SetAuraGroupEnabled(key, true)
            else
                container:SetAuraGroupEnabled(key, false)
            end
        end
    end
    if bar.appliedScale ~= scale then
        bar.appliedScale = scale
        container:SetScale(scale)
    end
end
