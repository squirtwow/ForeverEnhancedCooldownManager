-- Your buff or debuff time on the Cooldowns and Utility icons, as Blizzard's
-- own Cooldown Manager shows it: while the debuff a spell put on your target
-- (Shadow Word: Pain) or the buff it put on you is up, its icon shows the time
-- left, with a gold edge. Auras are secret in combat, so this uses Blizzard's
-- secure aura container, as the Buffs and Debuffs bars do: each icon gets one
-- slot for an aura on you and one for a debuff on your target, laid over it.
-- The container is only told which spell IDs to watch out of combat; a change
-- made in a fight waits for it to end. Nothing of Blizzard's is touched. Off
-- until a bar's "Show buff and debuff time" is ticked, and one icon can be
-- left out of it (Cooldown only in its own panel: that icon shows its
-- cooldown while the rest of the bar shows their times). With it, a spell's
-- icon can count its debuff's ticks too (Count ticks, below). The same way,
-- a spell's icon can glow for a proc the game doesn't light (Glow for more
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

-- (Not on a bar set to Show only when I can't afford it, a player's idea:
-- these slots sit on the bar, not in the icon, so they'd show over icons
-- the game keeps hidden. Their choice is kept.)
function A:On(bar)
    return bar and bar.kind == "cooldown" and bar.data and bar.data.showAuras == true and not bar.data.onlyShort
        and self:Available()
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
-- goes back over it. Out of a fight only. ratio: its icon's height over its
-- width (Icon height), the art cropped to it.
local function Draw(parts, size, recolour, ratio)
    Style:Shape(parts.shape, size, nil, ratio)
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
            Draw(parts, anchor.size or 36, true, anchor.ratio)
            parts.cooldown:SetCountdownFont(Style:Countdown(anchor.face or anchor.size or 36, anchor.look))
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
        Fit(parts, anchor.face or anchor.size or 36, anchor.showTimer ~= false, anchor.look)
        Draw(parts, anchor.size or 36, nil, anchor.ratio)
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
-- None for an icon ticked Cooldown only in its own panel (Squirt, 25 Nov
-- 2026: Stormstrike's icon showed its debuff's 12 seconds over its 8 second
-- cooldown), so both its slots stay off and it shows its plain cooldown
-- while the rest of the bar still shows their times (A:Apply). Its count of
-- the debuff's ticks goes with them (Counted, below), as that count shows
-- only while the time does.
local function IDs(bar, icon)
    if not icon or not icon:IsShown() then return nil end
    if icon.kind ~= "spell" and icon.kind ~= "rank" then return nil end
    if ns.CooldownOnly(bar.key, icon.name) then return nil end
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

-- Count ticks -------------------------------------------------------------------------
-- (Squirt, 14 Nov 2026, in the Shaman preset review: Flame Shock's ticks on
-- its Cooldowns icon, as the preset hides the Debuffs bar.) A spell on a
-- Cooldowns or Utility bar (an extra one too) ticked Count ticks in its own
-- panel counts its debuff's ticks on its icon while the icon shows that
-- debuff's time on your target. The debuff's time is secret in a fight, so
-- the game counts, as on the Debuffs bar (Buffs.lua TickCount): one more
-- slot on the bar's debuff container for each such icon (k1, k2 ...), told
-- the same spells as the icon's debuff time, so it shows just while that
-- does. Its icon holds only the count: the debuff's time so far over its
-- pace, through a rule set out of a fight. Where it sits, its size and
-- colour are the bar's own tick count settings (its page). Nothing is made
-- for a bar with none ticked, and none is told a spell while Show buff and
-- debuff time is off.
local TARGET = SIDES[2] -- (the debuff side)

-- The icons counting now, in order, each name once: its name, its pace and
-- its debuff's spell IDs (as IDs gives them, and joined for comparing).
local function Counted(bar)
    local counted, seen, B = {}, {}, ns.Bars
    for i = 1, bar.count or 0 do
        local icon = bar.icons[i]
        local pace = icon and not seen[icon.name] and B:CountsTicks(bar.key, icon.name) and B:TickPace(icon.name)
        local ids, sorted
        -- (None for an icon ticked Cooldown only: IDs gives it no spells, so
        -- it gets no count slot either.)
        if pace then ids, sorted = IDs(bar, icon) end
        if ids then
            seen[icon.name] = true
            counted[#counted + 1] = { name = icon.name, pace = pace, ids = ids, sorted = table.concat(sorted, ",") }
        end
    end
    return counted
end

-- A count slot's icon, made as the slot is added (and never later: Buffs.lua
-- F.Add and F.Guard): over its anchor, taking no mouse, holding only the
-- count, on a layer above the debuff time's icon, its sweep and its numbers.
local function TickLook(slot)
    return function(button)
        button:EnableMouse(false)
        button:SetAllPoints(slot.anchor)
        local top = CreateFrame("Frame", nil, button)
        top:SetAllPoints()
        top:SetFrameLevel(button:GetFrameLevel() + 5)
        slot.ticks = ns.BuffBar.TickCount(button, top)
    end
end

-- Count slot i ("k1", "k2" ...), made the first time it's wanted: its anchor
-- (the addon's own frame, out of sight until placed), then the slot,
-- switched off until it's told its spell.
local function TickSlot(bar, i)
    if bar.tickSlots[i] then return bar.tickSlots[i] end
    local slot = { key = "k" .. i }
    local anchor = CreateFrame("Frame", nil, bar)
    anchor:EnableMouse(false)
    anchor:SetSize(1, 1)
    anchor:SetPoint("CENTER", UIParent, "BOTTOMLEFT", AWAY, AWAY)
    slot.anchor = anchor
    bar.tickSlots[i] = slot
    local container = bar.auraContainers[TARGET.key]
    ns.BuffBar.Add(container, "AddAuraSlot", slot.key, TARGET.filter, { initializeFrame = ns.BuffBar.Guard(TickLook(slot)) })
    container:SetAuraSlotEnabled(slot.key, false)
    return slot
end

-- Tells the count slots which spell each counts (on: the bar shows buff and
-- debuff times), making what's needed. Never in a fight (A:Apply); only
-- what changed is sent.
local function ApplyTicks(bar, on)
    local counted = on and Counted(bar) or {}
    if not bar.tickSlots and #counted == 0 then return end
    bar.tickSlots, bar.tickApplied = bar.tickSlots or {}, bar.tickApplied or {}
    for i = 1, #counted do TickSlot(bar, i) end
    local container = bar.auraContainers[TARGET.key]
    for i, slot in ipairs(bar.tickSlots) do
        local want = counted[i]
        local signature = want and (want.name .. ":" .. want.sorted) or ""
        if bar.tickApplied[i] ~= signature then
            bar.tickApplied[i] = signature
            if want then
                container:SetAuraSlotCandidateFilters(slot.key, { includeSpellIDs = want.ids, isFromPlayerOrPlayerPet = true })
                container:SetAuraSlotEnabled(slot.key, true)
            else
                container:SetAuraSlotEnabled(slot.key, false)
            end
        end
        slot.name, slot.pace = want and want.name or nil, want and want.pace or nil
    end
end

-- Each count slot over the icon of the spell it was told about, found by
-- name, as the debuff times are (the addon's own frames: fine in a fight).
-- Its count set going at its pace and drawn as the bar's page says out of
-- a fight only, as the icons are the game's: one changed in a fight waits
-- for it to end.
local function PlaceTicks(bar, data)
    if not bar.tickSlots then return end
    local fight, base = InCombatLockdown(), ns.IconSize(data)
    for _, slot in ipairs(bar.tickSlots) do
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
        -- Its numbers sized for the icon it sits over (its own size, else the
        -- bar's; by its shorter side, Icon height).
        local pace, size = target and slot.pace or nil, ns.IconFace(data, target and target.size or base)
        local drawn = pace and (pace .. ":" .. size) or ""
        if slot.ticks and fight then
            if slot.drawn ~= drawn then bar.auraPending = true end
        elseif slot.ticks then
            ns.BuffBar.SetCount(slot.ticks, pace, nil, data, size)
            slot.drawn = drawn
        end
    end
end

-- For /ccm debug: an icon's Count ticks, while ticked: its pace and its
-- count's slot, or why it has none.
function A:TickReport(bar, name)
    local B = ns.Bars
    if not (bar and B:CountsTicks(bar.key, name)) then return "" end
    local how = bar.data and bar.data.onlyShort and "off with Show only when I can't afford it"
        or not self:On(bar) and "Show buff and debuff time is off"
        or ns.CooldownOnly(bar.key, name) and "off with Cooldown only" or "no slot yet"
    for _, slot in ipairs(self:On(bar) and bar.tickSlots or {}) do
        if slot.name == name then
            how = slot.ticks and ("slot " .. slot.key .. ", rule " .. tostring(slot.ticks.rule)) or "the game can't draw it"
        end
    end
    return " | counts ticks every " .. tostring(B:TickPace(name)) .. " s: " .. how .. (bar.auraPending and ", waiting for the fight to end" or "")
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
        -- (Icon height: its art cropped to the icon's shape, its numbers by
        -- the icon's shorter side.)
        local size = target and target.size or base
        local face, ratio = ns.IconFace(data, size), ns.IconRatio(data, size)
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
        if anchor.size ~= size or anchor.face ~= face or anchor.showTimer ~= data.showTimer
            or Style:LookKey(anchor.look) ~= Style:LookKey(look) then
            anchor.size, anchor.face, anchor.showTimer, anchor.look = size, face, data.showTimer, look
            for _, parts in ipairs(anchor.parts) do Fit(parts, face, data.showTimer, look) end
        end
        anchor.ratio = ratio
        -- Square or like Blizzard's at its icon's size, out of a fight: a
        -- size changed in one waits for it to end.
        for _, parts in ipairs(anchor.parts) do
            if not fight then
                Draw(parts, size, nil, ratio)
            elseif parts.shape.size ~= size or (parts.shape.ratio or 1) ~= ratio then
                bar.auraPending = true
            end
        end
    end
    -- And the counts of the icons counting their ticks.
    PlaceTicks(bar, data)
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
        if icon then ids, sorted = IDs(bar, icon) end
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
    -- And which spell each count slot counts (Count ticks).
    ApplyTicks(bar, on)
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
-- game with the containers. Not with Show only when I can't afford it (A:On).
function A:GlowsOn(bar)
    return bar ~= nil and bar.kind == "cooldown" and bar.data ~= nil and bar.data.glowProcs == true and not bar.data.onlyShort
        and self:Available()
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
-- icon's size (size across, high tall: Icon height). Only what changed is
-- set. Out of a fight only, as the icons are the game's.
local function Light(active, size, high, proc)
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
    local across, tall = size * GLOW_SPREAD, high * GLOW_SPREAD
    if active.loop and (active.spread ~= across or active.spreadTall ~= tall) then
        active.spread, active.spreadTall = across, tall
        active.loop:SetSize(across, tall)
    end
end

-- Whether Light would change anything on a slot's glow.
local function Stale(active, size, high, proc)
    return not active.on or active.looping ~= Looping(active, proc)
        or active.loop ~= nil and (active.spread ~= size * GLOW_SPREAD or active.spreadTall ~= high * GLOW_SPREAD)
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
        local high = ns.IconHeight(bar.data, size)
        if active and fight then
            if Stale(active, size, high, proc) then bar.glowPending = true end
        elseif active then
            Light(active, size, high, proc)
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
    elseif bar.data.onlyShort then
        how = "off with Show only when I can't afford it"
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

-- Totem time ---------------------------------------------------------------------------
-- (A player's idea: a 5 minute totem's time on its icon, as Blizzard's own
-- Cooldown Manager shows it; only a totem with a cooldown showed a number.)
-- With Totem time ticked (Icon details), a totem's icon on a Cooldowns or
-- Utility bar (an extra one too) shows the time its totem has left while
-- it stands, with the gold edge of a buff's time. The game hands each totem
-- slot's time as a duration object (GetTotemDuration, fine in a fight).
-- Which totem stands in a slot is read from GetTotemInfo, or, while the
-- game keeps that secret, it's the last totem of that element you cast;
-- a slot with none then shows nothing, as its time isn't running. The
-- addon's own frames only, laid over the icon: nothing of Blizzard's is
-- touched. Off until ticked: then nothing is made or heard.
local TOTEM_SLOTS = {} -- a totem's name -> its slot (1 fire, 2 earth, 3 water, 4 air)
for slot, names in ipairs({
    { "Searing Totem", "Fire Nova Totem", "Magma Totem", "Flametongue Totem", "Frost Resistance Totem" },
    { "Earthbind Totem", "Stoneclaw Totem", "Stoneskin Totem", "Strength of Earth Totem", "Tremor Totem" },
    { "Healing Stream Totem", "Mana Spring Totem", "Mana Tide Totem", "Poison Cleansing Totem", "Disease Cleansing Totem",
        "Fire Resistance Totem" },
    { "Grounding Totem", "Nature Resistance Totem", "Windfury Totem", "Grace of Air Totem", "Windwall Totem",
        "Tranquil Air Totem", "Sentry Totem" },
}) do
    for _, name in ipairs(names) do TOTEM_SLOTS[name] = slot end
end
local TOTEM_COUNT = 4
-- cast: by slot, the last totem of that element you cast; hearing: the
-- events listened for; events: their frame, made the first time.
local totems = { cast = {}, hearing = false }

local function Open(value)
    return not (issecretvalue and issecretvalue(value))
end

-- The totem standing in a slot now, by its spell's name, or nil.
local function Standing(slot)
    if type(GetTotemInfo) ~= "function" then return nil end
    local ok, have, name, _, duration, _, _, spellID = pcall(GetTotemInfo, slot)
    if not ok then return nil end
    if not (Open(have) and Open(name) and Open(spellID) and Open(duration)) then return totems.cast[slot] end
    if not have or type(name) ~= "string" or name == "" then return nil end
    if type(duration) == "number" and duration <= 0 then return nil end
    local spell = type(spellID) == "number" and spellID > 0 and C_Spell and C_Spell.GetSpellName
        and C_Spell.GetSpellName(spellID) or nil
    if type(spell) == "string" and Open(spell) and spell ~= "" then return spell end
    -- The totem's own name, its rank (IV) left off.
    return (name:gsub("%s+[IVX]+$", ""))
end

-- Which slot each standing totem is in, by name.
local function StandingTotems()
    local standing = {}
    for slot = 1, TOTEM_COUNT do
        local name = Standing(slot)
        if name then standing[name] = slot end
    end
    return standing
end

-- An icon's totem time, made the first time it's wanted: over the icon, in
-- the same look as a buff's time over it (Look, above), taking no mouse.
local function TotemParts(icon)
    local parts = icon.totemParts
    if parts then return parts end
    local frame = CreateFrame("Frame", nil, icon)
    frame:SetAllPoints(icon)
    frame:SetFrameLevel(icon:GetFrameLevel() + 4)
    frame:EnableMouse(false)
    local edge = frame:CreateTexture(nil, "BACKGROUND")
    edge:SetPoint("TOPLEFT", -1, 1)
    edge:SetPoint("BOTTOMRIGHT", 1, -1)
    edge:SetColorTexture(EDGE[1], EDGE[2], EDGE[3], 1)
    local art = frame:CreateTexture(nil, "ARTWORK")
    art:SetAllPoints()
    Style:Zoom(art)
    local cooldown = CreateFrame("Cooldown", nil, frame, "CooldownFrameTemplate")
    cooldown:SetAllPoints(art)
    cooldown:SetSwipeTexture(Style.FLAT)
    cooldown:SetReverse(true)
    cooldown:SetDrawBling(false)
    Style:CooldownLook(cooldown)
    -- Its time run out: gone until the next totem.
    cooldown:SetScript("OnCooldownDone", function() frame:Hide() end)
    frame:Hide()
    parts = { frame = frame, art = art, cooldown = cooldown, edge = edge, gold = false,
        shape = Style:ShapeKit(frame, art, { cooldown }) }
    icon.totemParts = parts
    return parts
end

-- The time left on slot's totem over icon, drawn for its size and its
-- spell's look. A duration that isn't running (the game keeping the slot
-- secret and no totem there) shows nothing.
local function ShowTotem(icon, data, slot)
    local ok, duration = false, nil
    if type(GetTotemDuration) == "function" then ok, duration = pcall(GetTotemDuration, slot) end
    if not (ok and duration) then
        if icon.totemParts then icon.totemParts.frame:Hide() end
        return
    end
    local parts = TotemParts(icon)
    local size = icon.size or ns.IconSize(data)
    Style:CooldownLook(parts.cooldown)
    Draw(parts, size, true, ns.IconRatio(data, size))
    parts.cooldown:SetCountdownFont(Style:Countdown(icon.face or size, icon.look))
    parts.cooldown:SetHideCountdownNumbers(data.showTimer == false)
    Style:AuraNumbers(parts)
    local art = icon.spellID and C_Spell.GetSpellTexture(icon.spellID)
    if art then parts.art:SetTexture(art) end
    parts.cooldown:SetCooldownFromDurationObject(duration)
    if parts.frame.SetAlphaFromBoolean and duration.IsActive then
        -- Secret in a fight: handed to the game as it is.
        parts.frame:SetAlphaFromBoolean(duration:IsActive(), 1, 0)
    end
    parts.frame:Show()
end

-- One cooldown bar's totem icons: each with its totem's time while it
-- stands, the rest without. standing: from StandingTotems, or nil for none.
-- None for an icon ticked Cooldown only: a totem's time is laid over its
-- icon in the same spot and the same gold edge as a buff's, so leaving it
-- there would show a totem's whole minute in place of the cooldown the tick
-- asks for. By the entry's own name, its rank and all, as the tick is kept
-- (the name stripped of its rank is only for which totem stands).
local function TotemBar(bar, standing)
    if not (bar and bar.kind == "cooldown" and bar.icons) then return end
    for i, icon in ipairs(bar.icons) do
        local slot = standing and i <= (bar.count or 0) and icon.spellID and icon.name
            and not ns.CooldownOnly(bar.key, icon.name)
            and standing[(icon.name:gsub("@.*$", ""))]
        if slot then
            ShowTotem(icon, bar.data or ns.BarData(bar.key), slot)
        elseif icon.totemParts then
            icon.totemParts.frame:Hide()
        end
    end
end

local function TotemsOn()
    return ns.Get("totemTime") == true and ns.Bars ~= nil and ns.Bars:Enabled()
end

-- Every cooldown bar's totem icons again.
function A:Totems()
    local standing = TotemsOn() and StandingTotems() or nil
    for _, key in ipairs(ns.BAR_KEYS) do TotemBar(ns.Bars and ns.Bars:Get(key), standing) end
end

-- Your totems heard (each slot's changes, and your casts for which totem
-- went down) only while Totem time is ticked.
local function HearTotems(on)
    if totems.hearing == on then return end
    totems.hearing = on
    local events = totems.events
    if not events then
        if not on then return end
        events = CreateFrame("Frame")
        events:SetScript("OnEvent", function(_, event, ...)
            if event == "UNIT_SPELLCAST_SUCCEEDED" then
                -- (The unit, the cast's GUID, then its spell ID.)
                local id = select(3, ...)
                if not (Open(id) and type(id) == "number") then return end
                local name = C_Spell.GetSpellName and C_Spell.GetSpellName(id)
                local slot = type(name) == "string" and Open(name) and TOTEM_SLOTS[name]
                if not slot then return end
                totems.cast[slot] = name
            end
            A:Totems()
        end)
        totems.events = events
    end
    if on then
        pcall(events.RegisterEvent, events, "PLAYER_TOTEM_UPDATE")
        pcall(events.RegisterEvent, events, "PLAYER_ENTERING_WORLD")
        pcall(events.RegisterUnitEvent, events, "UNIT_SPELLCAST_SUCCEEDED", "player")
    else
        events:UnregisterAllEvents()
    end
end

-- Totem time ticked or unticked (Icon details): heard or not, and every
-- totem icon shown or cleared at once.
function A:ApplyTotems()
    HearTotems(TotemsOn())
    self:Totems()
end

-- For the tests: the totem standing in each slot, as read now.
function A:TotemReport()
    local list = {}
    for slot = 1, TOTEM_COUNT do list[slot] = tostring(Standing(slot)) end
    return table.concat(list, ", ")
end

-- After a bar's icons are laid out (Bars.lua): made if needed, told what's
-- where, and placed over the icons. Its glows for more procs first.
function A:Layout(bar, data)
    if not bar or bar.kind ~= "cooldown" then return end
    -- Totem time over the icons where they are now (nothing while unticked
    -- and none was shown).
    local on = TotemsOn()
    HearTotems(on)
    TotemBar(bar, on and StandingTotems() or nil)
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
