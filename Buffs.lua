-- The Buffs bar: your own buffs and class procs, shown while they're on you.
-- Buffs are secret in combat, so the icons come from Blizzard's secure aura
-- container, the same way the portrait CC works in EraUI: each slot gets its
-- look once, before the game restricts it, and the addon only ever tells the
-- container which spell IDs belong in which slot, never in combat. Each slot
-- follows a plain holder frame of the addon's own, which sets its size and
-- place and can show the buff greyed while it's missing.
local _, ns = ...

local F = {}
ns.BuffBar = F

local SQUARE = "Interface\\Buttons\\WHITE8X8"
local TIMER_FONT = "SystemFont_Shadow_Large_Outline"

function F:Available()
    return CustomAuraContainerSlotDefaultOptions ~= nil
end

local function Edge(owner)
    local edge = owner:CreateTexture(nil, "BACKGROUND", nil, -7)
    edge:SetColorTexture(0, 0, 0, .9)
    edge:SetPoint("TOPLEFT", -1, 1)
    edge:SetPoint("BOTTOMRIGHT", 1, -1)
    return edge
end

-- Runs once per slot, before the client restricts the slot in combat.
-- Everything supplied to the slot must be a descendant of its button.
local function SlotLook(holder)
    return function(button)
        button:SetAllPoints(holder)
        button:EnableMouse(false)
        Edge(button)
        local icon = button:CreateTexture(nil, "ARTWORK")
        icon:SetAllPoints()
        button:SetIcon(icon)
        local cooldown = CreateFrame("Cooldown", nil, button, "CooldownFrameTemplate")
        cooldown:SetAllPoints()
        cooldown:SetSwipeTexture(SQUARE)
        cooldown:SetSwipeColor(0, 0, 0, .7)
        cooldown:SetReverse(true)
        cooldown:SetDrawEdge(false)
        cooldown:SetDrawBling(false)
        if _G[TIMER_FONT] then cooldown:SetCountdownFont(TIMER_FONT) end
        button:SetDurationCooldown(cooldown)
        -- Stack counts sit above the sweep.
        local top = CreateFrame("Frame", nil, button)
        top:SetAllPoints()
        top:SetFrameLevel(cooldown:GetFrameLevel() + 1)
        local count = top:CreateFontString(nil, "OVERLAY", "NumberFontNormal")
        count:SetPoint("BOTTOMRIGHT", -1, 1)
        button:SetApplicationCount(count)
    end
end

function F:Create(bar)
    bar.holders, bar.slotIDs, bar.applied = {}, {}, {}
    for i = 1, ns.BUFF_SLOTS do
        local holder = CreateFrame("Frame", nil, bar)
        holder:EnableMouse(false)
        holder.edge = Edge(holder)
        holder.icon = holder:CreateTexture(nil, "ARTWORK")
        holder.icon:SetAllPoints()
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
        container:SetAllPoints(bar)
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

-- Places the holders for the bar's buffs and works out each slot's spell IDs.
function F:Layout(bar, data)
    local size, spacing = data.size, data.spacing
    local count = 0
    for _, name in ipairs(data.spells) do
        local entry = ns.Spells:Find(name)
        if entry and entry.ids and #entry.ids > 0 and count < ns.BUFF_SLOTS then
            count = count + 1
            local holder = bar.holders[count]
            holder:SetSize(size, size)
            holder:ClearAllPoints()
            holder:SetPoint("LEFT", bar, "LEFT", (count - 1) * (size + spacing), 0)
            holder.icon:SetTexture(entry.icon)
            holder.icon:SetShown(data.showMissing)
            holder.edge:SetShown(data.showMissing)
            holder.label:SetWidth(size + spacing)
            holder.label:SetText(entry.name)
            holder.label:SetShown(data.showNames)
            holder:Show()
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

-- Tells the secure container which buffs go in which slot. Never in combat;
-- a change made then waits for the fight to end. Only changed slots are sent.
function F:Apply(bar)
    local container = bar.container
    if not container then return end
    if InCombatLockdown() then
        bar.pending = true
        return
    end
    bar.pending = nil
    local on = ns.Bars:Enabled()
    for i = 1, ns.BUFF_SLOTS do
        local ids = on and bar.slotIDs[i] or nil
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
end
