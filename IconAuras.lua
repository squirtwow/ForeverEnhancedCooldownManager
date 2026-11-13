-- Your buff or debuff time on the Cooldowns and Utility icons, as Blizzard's
-- own Cooldown Manager shows it: while the debuff a spell put on your target
-- (Shadow Word: Pain) or the buff it put on you is up, its icon shows the time
-- left, with a gold edge. Auras are secret in combat, so this uses Blizzard's
-- secure aura container, as the Buffs and Debuffs bars do: each icon gets one
-- slot for an aura on you and one for a debuff on your target, laid over it.
-- The container is only told which spell IDs to watch out of combat; a change
-- made in a fight waits for it to end. Nothing of Blizzard's is touched. Off
-- until a bar's "Show buff and debuff time" is ticked. The same way, a
-- spell's icon can glow for a proc the game doesn't light (Glow for more
-- procs, below).
local _, ns = ...

local A = {}
ns.IconAuras = A

local Style = ns.Style
local EDGE = { 1, .82, 0 } -- the gold of an aura that's up
-- An aura on you, and your own debuff on your target ("PLAYER": yours, not
-- another player's same debuff).
local SIDES = { { key = "p", unit = "player", filter = "HELPFUL" }, { key = "t", unit = "target", filter = "HARMFUL|PLAYER" } }
-- Out of sight, for a slot whose spell isn't on the bar just now.
local AWAY = -10000

function A:Available()
    return CustomAuraContainerSlotDefaultOptions ~= nil
end

function A:On(bar)
    return bar and bar.kind == "cooldown" and bar.data and bar.data.showAuras == true and self:Available()
end

-- Sizes an overlay's numbers for its icon, and shows or hides the
-- countdown, in the spot picked in Icon details; look: its spell's own
-- countdown font and size (settings per spell), or nil for the Look page's.
local function Fit(parts, size, showTimer, look)
    parts.cooldown:SetCountdownFont(Style:Countdown(size, look))
    parts.cooldown:SetHideCountdownNumbers(not showTimer)
    parts.count:SetFontObject(Style:Count(size))
    Style:AuraNumbers(parts)
end

-- An overlay square with its gold edge, as always, or drawn like the icon
-- under it in Blizzard's look (Icon details' Icons): rounded in its frame,
-- with Blizzard's own gold swipe over a buff or debuff that's up, running
-- as its cooldown items' do, and no edge. Only what changed is set; after
-- the swipe's colour is set again (recolour: Style:CooldownLook), the gold
-- goes back over it. Out of a fight only.
local function Draw(parts, size, recolour)
    Style:Shape(parts.shape, size)
    local rounded = parts.shape.rounded
    if parts.gold ~= rounded then
        parts.gold = rounded
        parts.edge:SetShown(not rounded)
        parts.cooldown:SetReverse(not rounded)
        recolour = true
    end
    if rounded and recolour then
        local gold = Style.AURA_SWIPE
        parts.cooldown:SetSwipeColor(gold[1], gold[2], gold[3], gold[4])
    end
end

-- Icon details (the Look page) on every overlay made: square or like
-- Blizzard's, the swipe, the edge line and the countdown, sized for its icon
-- (in its spell's own look). Only out of a fight (Bars.lua AuraDetails).
function A:Details(bar)
    for _, anchor in ipairs(bar and bar.auraAnchors or {}) do
        for _, parts in ipairs(anchor.parts) do
            Style:CooldownLook(parts.cooldown)
            Draw(parts, anchor.size or 36, true)
            parts.cooldown:SetCountdownFont(Style:Countdown(anchor.size or 36, anchor.look))
            Style:AuraNumbers(parts)
        end
    end
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
        cooldown:SetReverse(true)
        Style:CooldownLook(cooldown) -- the swipe and edge line picked in Icon details
        cooldown:SetDrawBling(false)
        button:SetDurationCooldown(cooldown)
        local top = CreateFrame("Frame", nil, button)
        top:SetAllPoints()
        top:SetFrameLevel(cooldown:GetFrameLevel() + 1)
        local count = top:CreateFontString(nil, "OVERLAY", "NumberFontNormal")
        count:SetPoint("BOTTOMRIGHT", -1, 1)
        button:SetApplicationCount(count)
        -- Made square with its edge, reversed (gold false); Blizzard's look's
        -- pieces made now, as the container's icons only take art as they're made.
        local parts = { cooldown = cooldown, count = count, edge = edge, gold = false,
            shape = Style:ShapeKit(button, icon, { cooldown }, true) }
        Fit(parts, anchor.size or 36, anchor.showTimer ~= false, anchor.look)
        Draw(parts, anchor.size or 36)
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
-- wrong spell. The addon's own frames only: fine in combat. Its numbers
-- take the spell's own look (settings per spell) out of a fight only: in
-- one, a look changed then waits for it to end (A:CombatEnded).
local function Place(bar, data)
    local base, fight = ns.IconSize(data), InCombatLockdown()
    for i, anchor in ipairs(bar.auraAnchors) do
        local name, target = bar.auraNames[i], nil
        if name then
            for j = 1, bar.count do
                local icon = bar.icons[j]
                if icon and icon.name == name and icon:IsShown() then target = icon break end
            end
        end
        -- Its numbers sized for the icon it sits over: that icon's own size
        -- (settings per spell), else the bar's.
        local size = target and target.size or base
        anchor:ClearAllPoints()
        if target then
            anchor:SetAllPoints(target)
        else
            anchor:SetSize(1, 1)
            anchor:SetPoint("CENTER", UIParent, "BOTTOMLEFT", AWAY, AWAY)
        end
        local look = anchor.look
        if not fight then look = ns.SpellLook(name) end
        if fight and Style:LookKey(ns.SpellLook(name)) ~= Style:LookKey(look) then bar.auraPending = true end
        if anchor.size ~= size or anchor.showTimer ~= data.showTimer or Style:LookKey(anchor.look) ~= Style:LookKey(look) then
            anchor.size, anchor.showTimer, anchor.look = size, data.showTimer, look
            for _, parts in ipairs(anchor.parts) do Fit(parts, size, data.showTimer, look) end
        end
        -- Square or like Blizzard's at its icon's size, out of a fight: a
        -- size changed in one waits for it to end.
        for _, parts in ipairs(anchor.parts) do
            if not fight then
                Draw(parts, size)
            elseif parts.shape.size ~= size then
                bar.auraPending = true
            end
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

-- Glow for more procs -----------------------------------------------------------------
-- (A player's report: Nightfall never lit Shadow Bolt.) A spell's icon glows
-- when the game lights it on your action bars (Bars.lua); for some procs
-- that empower one spell, Forever lights nothing. With a cooldown bar's
-- "Glow for more procs" ticked, that spell's icon glows while the proc's
-- buff is on you, in a fight too. Your buffs are secret in a fight, so the
-- game does it: one more secure aura container on the bar, for your buffs,
-- with a slot for each such icon, told out of a fight which proc to watch.
-- A slot's icon is only a glow laid over the spell's icon, made as Glow
-- while active's is (Buffs.lua ActiveGlow), hidden inside the game's icon,
-- so it's drawn only while the game shows that icon: in the Look page's
-- Ready glow style, the game's proc loop on the addon's own texture, handed
-- to the game to play while the icon shows, or the gold edge (Gold edge, or
-- a game that won't take the loop). Nothing of the buff's own is given to
-- the slot: no picture, no time. No burst: the game's own hands over to its
-- loop from a script, which a container's icon can't run; the loop is the
-- same art, as big. Off until ticked; nothing is made for a bar with none
-- of these spells on it.
--
-- Each spell a proc empowers with no light from the game (every rank:
-- ns.RANKS), and that proc's buff IDs. Checked in build 70888's data (the
-- proc's SpellEffect class mask against SpellClassOptions): Shadow Trance
-- (17941, from Nightfall, and the warlocks' T2 set), "Your next Shadow Bolt
-- becomes an instant cast spell", touches every Shadow Bolt rank and
-- nothing else.
A.PROC_LIGHTS = {
    { spell = "Shadow Bolt", procs = { 17941 } }, -- Shadow Trance
}
local GLOW_SPREAD = 1.4 -- the loop round its icon, as the game's proc glow (Bars.lua)
local litBy -- each spell ID's PROC_LIGHTS line, made the first time it's asked

-- The proc line that lights a spell ID, if any.
local function LitBy(id)
    if not litBy then
        litBy = {}
        for _, light in ipairs(A.PROC_LIGHTS) do
            for _, rank in ipairs(ns.RANKS and ns.RANKS[light.spell] or {}) do litBy[rank] = light end
        end
    end
    return type(id) == "number" and litBy[id] or nil
end

-- Whether a bar's icons glow for more procs: a cooldown bar, ticked, on a
-- game with the containers.
function A:GlowsOn(bar)
    return bar ~= nil and bar.kind == "cooldown" and bar.data ~= nil and bar.data.glowProcs == true and self:Available()
end

-- The icons that glow for a proc now, in order, each name once: its name
-- and the proc's buff IDs. Spells only (a fixed rank's too): items put no
-- proc of their own.
local function Wanted(bar)
    local wanted, seen = {}, {}
    if not (A:GlowsOn(bar) and ns.Bars:Enabled()) then return wanted end
    for i = 1, bar.count or 0 do
        local icon = bar.icons[i]
        local light = icon and icon:IsShown() and (icon.kind == "spell" or icon.kind == "rank") and LitBy(icon.spellID)
        if light and not seen[icon.name] then
            seen[icon.name] = true
            wanted[#wanted + 1] = { name = icon.name, procs = light.procs }
        end
    end
    return wanted
end

-- The bar's glow container, made the first time one of its icons glows for
-- a proc, never in a fight: for your buffs, over the buff and debuff times'
-- containers (6 above the bar) and below the bar's mover, taking no mouse,
-- with no stand-in auras in Edit Mode. From then on the bar goes right out
-- rather than hiding (Bars.lua B:Hold).
local function GlowContainer(bar)
    if bar.procGlow then return bar.procGlow end
    ns.Bars:Hold(bar)
    local container = CreateFrame("AuraContainer", nil, bar, "CustomAuraContainerTemplate")
    container:SetPoint("CENTER", bar, "CENTER")
    container:SetSize(1, 1)
    container:EnableMouse(false)
    container:SetFrameLevel(bar:GetFrameLevel() + 7)
    container:SetEditModePreviewEnabled(false)
    container:SetUnit("player")
    bar.procGlow = { container = container, slots = {}, applied = {} }
    return bar.procGlow
end

-- A glow slot's icon, made as the slot is added (and never later: Buffs.lua
-- F.Add and F.Guard): over its anchor, taking no mouse, holding only the
-- glow, hidden until Light shows it.
local function GlowLook(slot)
    return function(button)
        button:EnableMouse(false)
        button:SetAllPoints(slot.anchor)
        slot.active = ns.BuffBar.ActiveGlow(button, button)
    end
end

-- Glow slot i ("g1", "g2" ...), made the first time it's wanted: its anchor
-- (the addon's own frame, out of sight until placed), then the slot,
-- switched off until it's told its proc.
local function GlowSlot(bar, glow, i)
    if glow.slots[i] then return glow.slots[i] end
    local slot = { key = "g" .. i }
    local anchor = CreateFrame("Frame", nil, bar)
    anchor:EnableMouse(false)
    anchor:SetSize(1, 1)
    anchor:SetPoint("CENTER", UIParent, "BOTTOMLEFT", AWAY, AWAY)
    slot.anchor = anchor
    glow.slots[i] = slot
    ns.BuffBar.Add(glow.container, "AddAuraSlot", slot.key, "HELPFUL", { initializeFrame = ns.BuffBar.Guard(GlowLook(slot)) })
    glow.container:SetAuraSlotEnabled(slot.key, false)
    return slot
end

-- Whether a slot's glow is the loop (Proc glow, with the loop taken) rather
-- than the gold edge.
local function Looping(active, proc)
    return proc and active.loop ~= nil
end

-- A slot's glow shown, in the Ready glow style picked, the loop round its
-- icon's size. Only what changed is set. Out of a fight only, as the icons
-- are the game's.
local function Light(active, size, proc)
    if not active.on then
        active.on = true
        active.frame:Show()
    end
    local looping = Looping(active, proc)
    if active.looping ~= looping then
        active.looping = looping
        for _, strip in ipairs(active.strips) do strip:SetShown(not looping) end
        if active.loop then active.loop:SetShown(looping) end
    end
    local across = size * GLOW_SPREAD
    if active.loop and active.spread ~= across then
        active.spread = across
        active.loop:SetSize(across, across)
    end
end

-- Whether Light would change anything on a slot's glow.
local function Stale(active, size, proc)
    return not active.on or active.looping ~= Looping(active, proc) or active.loop ~= nil and active.spread ~= size * GLOW_SPREAD
end

-- Each glow slot over the icon of the spell it was told about, found by
-- name, so icons moving in a fight never put a glow on the wrong spell (the
-- addon's own frames only: fine in a fight). Its glow's look out of one
-- only: a change in a fight waits for it to end.
local function PlaceGlows(bar)
    local glow = bar.procGlow
    if not glow then return end
    local fight, proc = InCombatLockdown(), ns.Get("readyGlow") ~= "edge"
    local base = ns.IconSize(bar.data)
    for _, slot in ipairs(glow.slots) do
        local target
        for j = 1, slot.name and bar.count or 0 do
            local icon = bar.icons[j]
            if icon and icon.name == slot.name and icon:IsShown() then
                target = icon
                break
            end
        end
        local anchor = slot.anchor
        anchor:ClearAllPoints()
        if target then
            anchor:SetAllPoints(target)
        else
            anchor:SetSize(1, 1)
            anchor:SetPoint("CENTER", UIParent, "BOTTOMLEFT", AWAY, AWAY)
        end
        local active, size = slot.active, target and target.size or base
        if active and fight then
            if Stale(active, size, proc) then bar.glowPending = true end
        elseif active then
            Light(active, size, proc)
        end
    end
end

-- Tells the bar's glow container which proc goes with which icon, making
-- what's needed. Never in a fight: then it waits for it to end, the glows
-- only placed. Only what changed is sent. A failure is reported once, and
-- glows for more procs stop for the session.
function A:ApplyGlows(bar)
    if not (bar and bar.kind == "cooldown") then return end
    if InCombatLockdown() then
        bar.glowPending = true
        return PlaceGlows(bar)
    end
    bar.glowPending = nil
    if A.glowError then return end
    local wanted = Wanted(bar)
    if not bar.procGlow and #wanted == 0 then return end
    local ok, err = pcall(function()
        local glow = GlowContainer(bar)
        for i = 1, #wanted do GlowSlot(bar, glow, i) end
        for i, slot in ipairs(glow.slots) do
            local want = wanted[i]
            local signature = want and (want.name .. ":" .. table.concat(want.procs, ",")) or ""
            if glow.applied[i] ~= signature then
                glow.applied[i] = signature
                slot.name = want and want.name or nil
                if want then
                    local ids = {}
                    for _, id in ipairs(want.procs) do ids[id] = true end
                    glow.container:SetAuraSlotCandidateFilters(slot.key, { includeSpellIDs = ids })
                    glow.container:SetAuraSlotEnabled(slot.key, true)
                else
                    glow.container:SetAuraSlotEnabled(slot.key, false)
                end
            end
        end
    end)
    if not ok then
        A.glowError = tostring(err)
        print("|cffffd100" .. ns.TITLE .. ":|r glows for more procs couldn't start. Please report this: " .. A.glowError)
        return
    end
    PlaceGlows(bar)
end

-- For /ccm debug: a cooldown bar's glow for more procs, while ticked: each
-- spell it watches and its proc's buff IDs, and how it glows, or why not.
function A:GlowReport(bar)
    if not (bar and bar.kind == "cooldown" and bar.data and bar.data.glowProcs == true) then return nil end
    local glow, told = bar.procGlow, {}
    for i, slot in ipairs(glow and glow.slots or {}) do
        if slot.name then told[#told + 1] = glow.applied[i] end
    end
    local how
    if not self:Available() then
        how = "none (the game can't)"
    elseif A.glowError then
        how = "couldn't start: " .. A.glowError
    elseif #told == 0 then
        how = "no spell on this bar has one"
    else
        local active = glow.slots[1].active
        how = table.concat(told, ", ") .. ", " .. (not active and "no icon yet" or not active.loop and "edge only, the game took no loop"
            or ns.Get("readyGlow") == "edge" and "edge (Ready glow)" or "loop")
    end
    return "  glow for more procs: " .. how .. (bar.glowPending and ", waiting for the fight to end" or "")
end

-- After a bar's icons are laid out (Bars.lua): made if needed, told what's
-- where, and placed over the icons. Its glows for more procs first.
function A:Layout(bar, data)
    if not bar or bar.kind ~= "cooldown" then return end
    self:ApplyGlows(bar)
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
    if bar and bar.glowPending then self:ApplyGlows(bar) end
    if bar and bar.auraPending then
        if self:On(bar) then Create(bar) end
        self:Apply(bar)
    end
end
