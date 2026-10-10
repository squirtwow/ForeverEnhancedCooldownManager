-- Your buff or debuff time on the Cooldowns and Utility icons, as Blizzard's
-- own Cooldown Manager shows it: while the debuff a spell put on your target
-- (Shadow Word: Pain) or the buff it put on you is up, its icon shows the time
-- left, with a gold edge. Auras are secret in combat, so this uses Blizzard's
-- secure aura container, as the Buffs and Debuffs bars do: each icon gets one
-- slot for an aura on you and one for a debuff on your target, laid over it.
-- The container is only told which spell IDs to watch out of combat; a change
-- made in a fight waits for it to end. Nothing of Blizzard's is touched. Off
-- until a bar's "Show buff and debuff time" is ticked.
local _, ns = ...

local A = {}
ns.IconAuras = A

local Style = ns.Style
local EDGE = { 1, .82, 0 } -- the gold of an aura that's up
-- An aura on you, and your own debuff on your target.
local SIDES = { { key = "p", unit = "player", filter = "HELPFUL" }, { key = "t", unit = "target", filter = "HARMFUL" } }
-- Out of sight, for a slot whose spell isn't on the bar just now.
local AWAY = -10000

function A:Available()
    return CustomAuraContainerSlotDefaultOptions ~= nil
end

function A:On(bar)
    return bar and bar.kind == "cooldown" and bar.data and bar.data.showAuras == true and self:Available()
end

-- Sizes an overlay's numbers for its icon, and shows or hides the countdown.
local function Fit(parts, size, showTimer)
    parts.cooldown:SetCountdownFont(Style:Countdown(size))
    parts.cooldown:SetHideCountdownNumbers(not showTimer)
    parts.count:SetFontObject(Style:Count(size))
end

-- Runs once per slot, as the slot is added (and never later: Buffs.lua's
-- F.Add and F.Guard), before the client restricts it in combat. Everything
-- given to the slot is a descendant of its button.
local function Look(anchor)
    return function(button)
        button:SetAllPoints(anchor)
        button:EnableMouse(false)
        local edge = button:CreateTexture(nil, "BACKGROUND")
        edge:SetPoint("TOPLEFT", -1, 1)
        edge:SetPoint("BOTTOMRIGHT", 1, -1)
        edge:SetColorTexture(EDGE[1], EDGE[2], EDGE[3], 1)
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
        local top = CreateFrame("Frame", nil, button)
        top:SetAllPoints()
        top:SetFrameLevel(cooldown:GetFrameLevel() + 1)
        local count = top:CreateFontString(nil, "OVERLAY", "NumberFontNormal")
        count:SetPoint("BOTTOMRIGHT", -1, 1)
        button:SetApplicationCount(count)
        local parts = { cooldown = cooldown, count = count }
        Fit(parts, anchor.size or 36, anchor.showTimer ~= false)
        anchor.parts[#anchor.parts + 1] = parts
    end
end

-- The two containers, made the first time a bar needs them: never in a
-- fight, as the game needs the slots' looks before it restricts them.
local function Create(bar)
    if bar.auraContainers or InCombatLockdown() then return bar.auraContainers ~= nil end
    -- From now on the bar goes right out rather than hiding (Bars.lua B:Hold).
    ns.Bars:Hold(bar)
    local ok, err = pcall(function()
        local made = {}
        for _, side in ipairs(SIDES) do
            local container = CreateFrame("AuraContainer", nil, bar, "CustomAuraContainerTemplate")
            container:SetPoint("CENTER", bar, "CENTER")
            container:SetSize(1, 1)
            container:EnableMouse(false)
            -- Above the icons and their numbers, below the bar's mover.
            container:SetFrameLevel(bar:GetFrameLevel() + 6)
            container:SetEditModePreviewEnabled(false)
            container:SetUnit(side.unit)
            made[side.key] = container
        end
        bar.auraContainers, bar.auraAnchors, bar.auraApplied, bar.auraNames = made, {}, {}, {}
    end)
    if not ok and not A.lastError then
        A.lastError = tostring(err)
        print("|cffffd100" .. ns.TITLE .. ":|r buff and debuff times on the " .. ns.BAR_NAMES[bar.key]
            .. " bar couldn't start. Please report this: " .. A.lastError)
    end
    return bar.auraContainers ~= nil
end

-- One anchor per place on the bar, with a slot on each side over it.
local function Anchor(bar, i)
    local anchor = bar.auraAnchors[i]
    if anchor then return anchor end
    anchor = CreateFrame("Frame", nil, bar)
    anchor:EnableMouse(false)
    anchor:SetSize(1, 1)
    anchor:SetPoint("CENTER", UIParent, "BOTTOMLEFT", AWAY, AWAY)
    anchor.parts = {}
    bar.auraAnchors[i] = anchor
    for _, side in ipairs(SIDES) do
        local container = bar.auraContainers[side.key]
        local key = side.key .. i
        ns.BuffBar.Add(container, "AddAuraSlot", key, side.filter, { initializeFrame = ns.BuffBar.Guard(Look(anchor)) })
        container:SetAuraSlotEnabled(key, false)
    end
    return anchor
end

-- The spell IDs an icon's aura can have, as the container wants them ({ [id]
-- = true }), and sorted for comparing: every rank you know, and the buff's
-- own IDs where they differ (ns.Spells). A fixed rank's, its own ID's
-- (Vanish's stealth for Vanish at rank 1). Spells only: items, trinkets and
-- ammo put no aura of their own.
local function IDs(icon)
    if not icon or not icon:IsShown() then return nil end
    if icon.kind ~= "spell" and icon.kind ~= "rank" then return nil end
    local entry = ns.Spells:Find(icon.name)
    local set, sorted = {}, {}
    for _, id in ipairs(entry and entry.ids or ns.Spells:AuraIDs(icon.spellID)) do
        if type(id) == "number" and not set[id] then
            set[id] = true
            sorted[#sorted + 1] = id
        end
    end
    if #sorted == 0 then return nil end
    table.sort(sorted)
    return set, sorted
end

-- Each slot sits over the icon of the spell it was told about, found by name,
-- so icons moving in a fight (an item running out) never put a time on the
-- wrong spell. The addon's own frames only: fine in combat.
local function Place(bar, data)
    local size = ns.IconSize(data)
    for i, anchor in ipairs(bar.auraAnchors) do
        local name, target = bar.auraNames[i], nil
        if name then
            for j = 1, bar.count do
                local icon = bar.icons[j]
                if icon and icon.name == name and icon:IsShown() then target = icon break end
            end
        end
        anchor:ClearAllPoints()
        if target then
            anchor:SetAllPoints(target)
        else
            anchor:SetSize(1, 1)
            anchor:SetPoint("CENTER", UIParent, "BOTTOMLEFT", AWAY, AWAY)
        end
        if anchor.size ~= size or anchor.showTimer ~= data.showTimer then
            anchor.size, anchor.showTimer = size, data.showTimer
            for _, parts in ipairs(anchor.parts) do Fit(parts, size, data.showTimer) end
        end
    end
end

-- Tells the containers which spell goes in which place. Never in combat;
-- only what changed is sent.
function A:Apply(bar)
    if not (bar and bar.auraContainers) then return end
    if InCombatLockdown() then
        bar.auraPending = true
        return
    end
    bar.auraPending = nil
    local on = self:On(bar) and ns.Bars:Enabled()
    local wanted = on and bar.count or 0
    for i = 1, wanted do Anchor(bar, i) end
    for i, _ in ipairs(bar.auraAnchors) do
        local icon = i <= wanted and bar.icons[i] or nil
        local ids, sorted
        if icon then ids, sorted = IDs(icon) end
        local signature = ids and (icon.name .. ":" .. table.concat(sorted, ",")) or ""
        if bar.auraApplied[i] ~= signature then
            bar.auraApplied[i] = signature
            bar.auraNames[i] = ids and icon.name or nil
            for _, side in ipairs(SIDES) do
                local container, key = bar.auraContainers[side.key], side.key .. i
                if ids then
                    container:SetAuraSlotCandidateFilters(key, { includeSpellIDs = ids, isFromPlayerOrPlayerPet = true })
                    container:SetAuraSlotEnabled(key, true)
                else
                    container:SetAuraSlotEnabled(key, false)
                end
            end
        end
    end
    Place(bar, bar.data)
end

-- After a bar's icons are laid out (Bars.lua): made if needed, told what's
-- where, and placed over the icons.
function A:Layout(bar, data)
    if not bar or bar.kind ~= "cooldown" then return end
    if self:On(bar) and not Create(bar) then
        -- First ticked during a fight: made as it ends.
        bar.auraPending = true
        return
    end
    if not bar.auraContainers then return end
    self:Apply(bar)
    if InCombatLockdown() then Place(bar, data) end
end

-- A new target: the debuff side looks again at once, as the Debuffs bar does.
function A:UpdateTarget(bar)
    local containers = bar and bar.auraContainers
    if containers and self:On(bar) then containers.t:UpdateAllAuras() end
end

-- Anything held back during a fight.
function A:CombatEnded(bar)
    if bar and bar.auraPending then
        if self:On(bar) then Create(bar) end
        self:Apply(bar)
    end
end
