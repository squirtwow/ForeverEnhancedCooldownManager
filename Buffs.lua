-- The Buffs bar: your own buffs and class procs, shown while they're on you.
-- Buffs are secret in combat, so the icons come from Blizzard's secure aura
-- container, the same way the portrait CC works in EraUI: each icon gets its
-- look once, before the game restricts it, and the addon only ever tells the
-- container which spell IDs belong where, never in combat.
--
-- Two layouts:
-- * Packed (the default): one aura group per buff, in your order. Blizzard's
--   own layout places only the buffs that are up, side by side and centred on
--   the bar, so there are no gaps, even in combat. Groups size themselves, so
--   the icon size comes from scaling the container.
-- * Fixed, with "Show missing buffs greyed": one slot per buff, each following
--   a holder frame of the addon's own that keeps its place and shows the buff
--   greyed while it's missing.
local _, ns = ...

local F = {}
ns.BuffBar = F

local Style = ns.Style
local BASE = 36 -- packed icons are drawn at this size, then scaled

function F:Available()
    return CustomAuraContainerSlotDefaultOptions ~= nil
end

function F:Packed(data)
    return not data.showMissing
end

-- Sizes an icon's numbers for its size.
local function Fit(parts, size)
    parts.cooldown:SetCountdownFont(Style:Countdown(size))
    parts.count:SetFontObject(Style:Count(size))
end

-- Runs once per icon, before the client restricts it in combat. Everything
-- supplied to the icon must be a descendant of its button.
local function Look(button, size)
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
    Fit(parts, size)
    return parts
end

-- A slot's numbers take its holder's size; a later size change refits them.
local function SlotLook(holder)
    return function(button)
        button:SetAllPoints(holder)
        holder.slot = Look(button, holder.size or BASE)
    end
end

local function GroupLook(button)
    button:SetSize(BASE, BASE)
    Look(button, BASE)
end

function F:Create(bar)
    bar.holders, bar.slotIDs, bar.applied, bar.appliedGroups, bar.groups = {}, {}, {}, {}, 0
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
    local ok, err = pcall(function()
        local container = CreateFrame("AuraContainer", nil, bar, "CustomAuraContainerTemplate")
        -- One point only: packed groups resize the container around the buffs
        -- that are up, and it stays centred on the bar.
        container:SetPoint("CENTER", bar, "CENTER")
        container:SetSize(BASE, BASE)
        container:EnableMouse(false)
        container:SetFrameLevel(bar:GetFrameLevel() + 5)
        container:SetEditModePreviewEnabled(false)
        container:SetUnit("player")
        for i = 1, ns.BUFF_SLOTS do
            container:AddAuraSlot("b" .. i, "HELPFUL", { initializeFrame = SlotLook(bar.holders[i]) })
            container:SetAuraSlotEnabled("b" .. i, false)
        end
        bar.container = container
    end)
    if not ok and not F.lastError then
        F.lastError = tostring(err)
        print("|cffffd100" .. ns.TITLE .. ":|r the Buffs bar couldn't start. Please report this: " .. F.lastError)
    end
end

-- Places the holders for the bar's buffs and works out each one's spell IDs.
function F:Layout(bar, data)
    local size, spacing = data.size, data.spacing
    local fixed = not self:Packed(data)
    local count = 0
    for _, name in ipairs(data.spells) do
        local entry = ns.Spells:Find(name)
        if entry and entry.ids and #entry.ids > 0 and count < ns.BUFF_SLOTS then
            count = count + 1
            local holder = bar.holders[count]
            holder:SetSize(size, size)
            holder.size = size
            if holder.slot then Fit(holder.slot, size) end
            holder:ClearAllPoints()
            holder:SetPoint("LEFT", bar, "LEFT", (count - 1) * (size + spacing), 0)
            holder.icon:SetTexture(entry.icon)
            holder.label:SetWidth(size + spacing)
            holder.label:SetText(entry.name)
            holder.label:SetShown(data.showNames)
            holder:SetShown(fixed)
            local ids = {}
            for _, id in ipairs(entry.ids) do ids[id] = true end
            bar.slotIDs[count] = ids
        end
    end
    for i = count + 1, ns.BUFF_SLOTS do
        bar.holders[i]:Hide()
        bar.slotIDs[i] = nil
    end
    bar.count = count
    self:Apply(bar)
end

local function Signature(ids)
    if not ids then return "" end
    local keys = {}
    for id in pairs(ids) do keys[#keys + 1] = id end
    table.sort(keys)
    return table.concat(keys, ",")
end

-- Tells the secure container which buffs go where. Never in combat; a change
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
                container:SetAuraSlotCandidateFilters(key, { includeSpellIDs = ids })
                container:SetAuraSlotEnabled(key, true)
            else
                container:SetAuraSlotEnabled(key, false)
            end
        end
    end
    -- Groups are made as they're first needed; the game keeps them after that.
    local scale = packed and data.size / BASE or 1
    local spacing = data.spacing / scale
    if on and packed then
        for i = bar.groups + 1, bar.count do
            container:AddAuraGroup("g" .. i, "HELPFUL", { initializeFrame = GroupLook, maxFrameCount = 1,
                candidateFilters = { includeSpellIDs = bar.slotIDs[i] }, layout = { layoutIndex = i, groupSpacing = spacing } })
            bar.groups = i
            bar.appliedGroups[i] = Signature(bar.slotIDs[i]) .. "|" .. spacing
        end
    end
    for i = 1, bar.groups do
        local ids = on and packed and bar.slotIDs[i] or nil
        local signature = ids and (Signature(ids) .. "|" .. spacing) or ""
        if bar.appliedGroups[i] ~= signature then
            bar.appliedGroups[i] = signature
            local key = "g" .. i
            if ids then
                container:SetAuraGroupCandidateFilters(key, { includeSpellIDs = ids })
                container:SetAuraGroupLayout(key, { layoutIndex = i, groupSpacing = spacing })
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
