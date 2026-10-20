-- The Buffs and Debuffs bars: your buffs and class procs while they're on
-- you, and your own debuffs on your target; either can also show the debuffs
-- you put on yourself (F:ApplySelf). Auras are secret in combat, so
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
-- * Only show missing (the Buffs bar, F:Check): the fixed slots and holders,
--   but only for the buffs that aren't on you, side by side. Which are on you
--   is read out of combat only (the game keeps your buffs secret in a fight),
--   so in a fight the bar stays as it was: a buff cast then draws over its
--   greyed spot in its slot as usual, and one that drops shows once it's over.
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

-- Only show missing: the Buffs bar's own (ns.BarData keeps it off on the
-- Debuffs bar).
function F:OnlyMissing(data)
    return data ~= nil and data.onlyMissing == true
end

function F:Packed(data)
    return not (data.showMissing or self:OnlyMissing(data))
end

-- Every entry keeping a spot of its own, greyed while missing: with missing
-- ones greyed, and not with Only show missing, whose spots come and go.
function F:Fixed(data)
    return data.showMissing == true and not self:OnlyMissing(data)
end

-- Keep them greyed with no target (the Debuffs bar's own, a player's idea):
-- with missing debuffs greyed, their spots stay with no enemy targeted
-- (ns.BarData keeps it off on the Buffs bar).
function F:KeepGreyed(data)
    return data ~= nil and data.greyedNoTarget == true and self:Fixed(data)
end

-- Sizes an icon's numbers for its size, and shows or hides the countdown.
local function Fit(parts, size, showTimer)
    parts.cooldown:SetCountdownFont(Style:Countdown(size))
    parts.cooldown:SetHideCountdownNumbers(not showTimer)
    parts.count:SetFontObject(Style:Count(size))
end

-- Count ticks (a player's idea: how many times Bane of Agony has ticked),
-- ticked per debuff on the Debuffs page: how often each debuff of yours
-- ticks on a target, in seconds, from the game's data (printed by
-- node Tools/MakeTickPeriods.mjs).
ns.TICK_PERIODS = {
    ["Arcane Missiles"] = 1,
    ["Bane of Agony"] = 2,
    ["Black Arrow"] = 2,
    ["Corruption"] = 3,
    ["Curse of Idiocy"] = 3,
    ["Devouring Plague"] = 3,
    ["Drain Life"] = 1,
    ["Drain Mana"] = 1,
    ["Drain Soul"] = 3,
    ["Entangling Roots"] = 3,
    ["Fireball"] = 2,
    ["Flame Shock"] = 3,
    ["Frostfire Bolt"] = 3,
    ["Garrote"] = 3,
    ["Holy Fire"] = 2,
    ["Immolate"] = 3,
    ["Immolation Trap"] = 3,
    ["Insect Swarm"] = 2,
    ["Lacerate"] = 3,
    ["Living Bomb"] = 3,
    ["Living Flame"] = 1,
    ["Mind Flay"] = 1,
    ["Mind Sear"] = 1,
    ["Moonfire"] = 3,
    ["Pounce Bleed"] = 3,
    ["Pyroblast"] = 3,
    ["Rake"] = 3,
    ["Rend"] = 3,
    ["Rip"] = 2,
    ["Rupture"] = 2,
    ["Saber Slash"] = 2,
    ["Savage Rend"] = 3,
    ["Scorpid Poison"] = 2,
    ["Serpent Sting"] = 3,
    ["Shadow Word: Pain"] = 3,
    ["Shadowflame"] = 2,
    ["Siphon Life"] = 3,
    ["Starshards"] = 1,
    ["Sunfire"] = 3,
    ["Tendon Rip"] = 3,
    ["Vampiric Touch"] = 3,
    ["Viper Sting"] = 2,
    ["Void Plague"] = 3,
    ["Web"] = 1,
    ["Wrack"] = 1,
}

-- And how long each debuff of yours lasts, in seconds (each length its ranks
-- have, and each a combo point more makes: Rupture), from the same data: a joined icon holding debuffs that tick at
-- different paces counts only while a counted one is up, told apart by its
-- length (Bane of Agony 24, Bane of Doom 60; B:IconTicks).
ns.DEBUFF_LASTS = {
    ["Arcane Missiles"] = { 3, 4, 5 },
    ["Bane of Agony"] = { 24 },
    ["Bane of Doom"] = { 60 },
    ["Bane of Havoc"] = { 300 },
    ["Banish"] = { 20, 30 },
    ["Bash"] = { 2, 3, 4 },
    ["Black Arrow"] = { 30 },
    ["Blast Wave"] = { 6 },
    ["Blind"] = { 10 },
    ["Challenging Roar"] = { 6 },
    ["Challenging Shout"] = { 6 },
    ["Chastise"] = { 2 },
    ["Cheap Shot"] = { 4 },
    ["Chilled"] = { 1.5 },
    ["Chimera Shot - Scorpid"] = { 10 },
    ["Concussion Blow"] = { 5 },
    ["Concussive Shot"] = { 4 },
    ["Cone of Cold"] = { 6 },
    ["Confounding Flash"] = { 3 },
    ["Corruption"] = { 12, 15, 18 },
    ["Counterattack"] = { 5 },
    ["Curse of Exhaustion"] = { 12 },
    ["Curse of Idiocy"] = { 120 },
    ["Curse of Recklessness"] = { 120 },
    ["Curse of Tongues"] = { 30 },
    ["Curse of Weakness"] = { 120 },
    ["Curse of the Elements"] = { 300 },
    ["Death Coil"] = { 3 },
    ["Demonic Howl"] = { 6 },
    ["Demoralizing Roar"] = { 30 },
    ["Demoralizing Screech"] = { 30 },
    ["Demoralizing Shout"] = { 45 },
    ["Devouring Plague"] = { 24 },
    ["Disarm"] = { 10 },
    ["Dismember"] = { 6 },
    ["Distract"] = { 10 },
    ["Drain Life"] = { 5, 15 },
    ["Drain Mana"] = { 5 },
    ["Drain Soul"] = { 15 },
    ["Dust Cloud"] = { 30 },
    ["Entangling Roots"] = { 12, 15, 18, 21, 24, 27 },
    ["Expose Armor"] = { 30 },
    ["Faerie Fire"] = { 40 },
    ["Fear"] = { 10, 15, 20 },
    ["Fire Vulnerability"] = { 30 },
    ["Fireball"] = { 4, 6, 8 },
    ["Flame Shock"] = { 12 },
    ["Frost Blast"] = { 9 },
    ["Frost Nova"] = { 8 },
    ["Frost Shock"] = { 8 },
    ["Frostbite"] = { 5 },
    ["Frostbolt"] = { 5, 6, 7, 8, 9 },
    ["Frostfire Bolt"] = { 9 },
    ["Frozen Orb"] = { 5, 16 },
    ["Garrote"] = { 18 },
    ["Gouge"] = { 4 },
    ["Growl"] = { 3 },
    ["Hammer of Justice"] = { 3, 4, 5, 6 },
    ["Hamstring"] = { 15 },
    ["Harass"] = { 10, 20, 30 },
    ["Hemorrhage"] = { 15 },
    ["Hex of Weakness"] = { 120 },
    ["Hibernate"] = { 20, 30, 40 },
    ["Holy Fire"] = { 10 },
    ["Howl of Terror"] = { 10, 15 },
    ["Hunter's Mark"] = { 120 },
    ["Immolate"] = { 15 },
    ["Immolation Trap"] = { 15, 60 },
    ["Impact"] = { 2 },
    ["Insect Swarm"] = { 12 },
    ["Intimidating Shout"] = { 8 },
    ["Judgement of Justice"] = { 10 },
    ["Judgement of Light"] = { 40 },
    ["Judgement of Wisdom"] = { 40 },
    ["Judgement of the Crusader"] = { 40 },
    ["Kidney Shot"] = { 1, 2, 3, 4, 5, 6 },
    ["Lacerate"] = { 15 },
    ["Lava Breath"] = { 10 },
    ["Living Bomb"] = { 12 },
    ["Living Flame"] = { 2, 10 },
    ["Long Daze"] = { 6 },
    ["Menace"] = { 3 },
    ["Mind Control"] = { 60 },
    ["Mind Flay"] = { 3 },
    ["Mind Sear"] = { 6 },
    ["Mind Soothe"] = { 15 },
    ["Mind Spike"] = { 10 },
    ["Mine!"] = { 3 },
    ["Mocking Blow"] = { 6 },
    ["Moonfire"] = { 9, 12 },
    ["Mortal Strike"] = { 10 },
    ["Piercing Howl"] = { 6 },
    ["Pinch"] = { 9 },
    ["Polymorph"] = { 20, 30, 40, 50 },
    ["Polymorph: Cow"] = { 50 },
    ["Pounce"] = { 2 },
    ["Pounce Bleed"] = { 18 },
    ["Psychic Scream"] = { 8 },
    ["Pyroblast"] = { 12 },
    ["Pyroclasm"] = { 3 },
    ["Quick Draw"] = { 6 },
    ["Rake"] = { 9 },
    ["Rend"] = { 9, 12, 15, 18, 21 },
    ["Repentance"] = { 6 },
    ["Rip"] = { 12 },
    ["Riposte"] = { 6 },
    ["Rupture"] = { 6, 8, 10, 12, 14, 16 },
    ["Saber Slash"] = { 12 },
    ["Sap"] = { 25, 35, 45 },
    ["Savage Rend"] = { 18 },
    ["Scare Beast"] = { 10, 15, 20 },
    ["Scatter Shot"] = { 4 },
    ["Scorpid Poison"] = { 10 },
    ["Scorpid Sting"] = { 20 },
    ["Serpent Sting"] = { 12, 15 },
    ["Shackle Undead"] = { 30, 40, 50 },
    ["Shadow Word: Pain"] = { 18 },
    ["Shadowburn"] = { 8 },
    ["Shadowflame"] = { 8, 15 },
    ["Shockwave"] = { 4 },
    ["Silence"] = { 5 },
    ["Siphon Life"] = { 30 },
    ["Soothe Animal"] = { 15 },
    ["Spellfrost Bolt"] = { 9 },
    ["Starshards"] = { 6 },
    ["Stormstrike"] = { 12 },
    ["Subjugate Demon"] = { 300 },
    ["Sunder Armor"] = { 30 },
    ["Sunfire"] = { 12 },
    ["Tame Beast"] = { 20 },
    ["Taunt"] = { 3 },
    ["Tendon Rip"] = { 9 },
    ["Thunder Clap"] = { 10, 14, 18, 22, 26, 30 },
    ["Touch of Weakness"] = { 120, 600 },
    ["Turn Undead"] = { 10, 15, 20 },
    ["Vampiric Embrace"] = { 30 },
    ["Vampiric Touch"] = { 15 },
    ["Vindication"] = { 10 },
    ["Viper Sting"] = { 8 },
    ["Void Plague"] = { 18 },
    ["Web"] = { 4 },
    ["Wing Clip"] = { 10 },
    ["Wrack"] = { 6 },
}

-- A tick count's rule: the aura's time so far over its pace, rounded down
-- (from 0), or up (from 1, like stacks: 1 as it lands, 2 after the first
-- tick). From 1, the time is taken as at least a moment, so it never reads
-- 0 as it lands.
local function Ticking(seconds, from)
    local rounding = Enum.NumericRuleFormatRounding
    if from == 1 then
        return { threshold = 0, min = .01, format = "%d", components = { { div = seconds, step = 1, rounding = rounding.Up } } }
    end
    return { threshold = 0, format = "%d", components = { { div = seconds, step = 1, rounding = rounding.Down } } }
end

-- A colour curve for a count's colour by how long its aura lasts (TotalDuration),
-- where the game has them: its colour while shown, see-through for a joined
-- icon's other debuffs (F:Ticks). Nil where it can't.
local function TickCurve()
    local util = C_CurveUtil
    if type(util) ~= "table" or type(util.CreateColorCurve) ~= "function" or type(CreateColor) ~= "function" then return nil end
    local ok, curve = pcall(function()
        local curve = util.CreateColorCurve()
        curve:AddPoint(0, CreateColor(1, 1, 1, 1))
        return curve
    end)
    return ok and curve or nil
end

-- A Debuffs bar icon's tick count. The addon can't read an aura's time in a
-- fight (nor the combat log), so the game draws it: the aura's time so far,
-- through a rule the addon sets out of combat (F:Ticks), which starts again
-- as the debuff is put back on, coloured by a curve on how long the aura
-- lasts where the game has them (ticks.curve). Hidden until its entry counts;
-- where it sits, its size and colour are the bar's (F:Ticks). Nil when the
-- game can't. A curve the game turns down leaves the count without one.
local function TickCount(button, top)
    local util, enum = C_StringUtil, Enum
    if not (type(util) == "table" and type(util.CreateNumericRuleFormatter) == "function" and type(enum) == "table"
        and enum.DurationTextBindingProperty and enum.NumericRuleFormatRounding) then return nil end
    local ok, ticks = pcall(function()
        local formatter = util.CreateNumericRuleFormatter()
        formatter:AddBreakpoint(Ticking(2, 0))
        local frame = CreateFrame("Frame", nil, top)
        frame:SetAllPoints()
        frame:Hide()
        local text = frame:CreateFontString(nil, "OVERLAY", "NumberFontNormal")
        text:SetPoint("TOPLEFT", 1, -1)
        local format = { formatString = "{}", components = {
            { property = enum.DurationTextBindingProperty.ElapsedDuration, formatter = formatter } } }
        local curve = enum.DurationTextBindingProperty.TotalDuration and TickCurve()
        if curve and not pcall(button.SetDurationText, button, text, { textFormat = format,
            textColor = { curve = curve, property = enum.DurationTextBindingProperty.TotalDuration } }) then
            curve = nil
        end
        -- Whether the game took them: joined icons count only where it does (B:IconTicks).
        if curve then F.curves = true elseif F.curves == nil then F.curves = false end
        if not curve then button:SetDurationText(text, { textFormat = format }) end
        return { frame = frame, text = text, formatter = formatter, rule = "2:0", curve = curve }
    end)
    return ok and ticks or nil
end

-- Runs once per icon, before the client restricts it in combat. Everything
-- supplied to the icon must be a descendant of its button. A packed icon
-- carries its own border and shadow; a fixed one's holder has them. A
-- Debuffs bar entry's icon can count ticks too (counts).
local function Look(button, size, showTimer, decorate, counts)
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
    if counts then parts.ticks = TickCount(button, top) end
    if decorate then
        -- Made now: the container's icons only take art as they're made.
        parts.decor = Style:Decor(button, button, 0, true)
        Style:ShowDecor(parts.decor, Style:DecorFor("icon"))
    end
    Fit(parts, size, showTimer)
    return parts
end

-- Blizzard runs a slot's or group's look (initializeFrame) on every icon it
-- makes for it, and makes them as the addon adds the slot or group: one for a
-- slot, a batch of ten for a group (Blizzard_CustomAuraContainer.lua). It
-- would only make more in the middle of its own update, for a group showing
-- more auras than it has icons. So a group never shows more than were made
-- (AddGroup), and a look does nothing unless the addon is adding right then:
-- the container never runs the addon's code while it updates. IconAuras.lua
-- adds its slots the same way.
local adding = false

-- Adds a slot or group ("AddAuraSlot" or "AddAuraGroup"), its look allowed
-- for just this call.
function F.Add(container, method, ...)
    adding = true
    local ok, result = pcall(container[method], container, ...)
    adding = false
    if not ok then error(result, 0) end
    return result
end

-- A look that only works while the addon is adding its slot or group.
function F.Guard(look)
    return function(button)
        if adding then look(button) end
    end
end

-- A slot's numbers take its holder's size; a later size change refits them.
local function SlotLook(holder, key)
    return function(button)
        button:SetAllPoints(holder)
        holder.slot = Look(button, holder.size or BASE, holder.showTimer ~= false, false, key == "debuff")
    end
end

-- A packed entry's group (index: its place) keeps its icons' tick counts;
-- the group of your debuffs on you has none.
local function GroupLook(bar, index)
    return function(button)
        button:SetSize(BASE, BASE)
        local parts = Look(button, BASE, bar.data.showTimer, true, bar.key == "debuff" and index ~= nil)
        bar.groupParts[#bar.groupParts + 1] = parts
        if parts.ticks then
            bar.groupTicks[index] = bar.groupTicks[index] or {}
            table.insert(bar.groupTicks[index], parts.ticks)
        end
    end
end

-- A group, never showing more icons than Blizzard made as it was added.
local function AddGroup(container, key, filter, options)
    F.Add(container, "AddAuraGroup", key, filter, options)
    local made = container:GetAuraGroupFrameCount(key)
    if Open(made) and type(made) == "number" and made < options.maxFrameCount then
        container:SetAuraGroupMaxFrameCount(key, made)
    end
end

function F:Create(bar)
    bar.holders, bar.slotIDs, bar.applied, bar.appliedGroups, bar.groups = {}, {}, {}, {}, 0
    bar.groupParts, bar.names, bar.up, bar.spots = {}, {}, {}, {}
    bar.tickPaces, bar.tickShows, bar.groupTicks = {}, {}, {}
    for i = 1, ns.BUFF_SLOTS do
        local holder = CreateFrame("Frame", nil, bar)
        holder:EnableMouse(false)
        holder.icon = holder:CreateTexture(nil, "ARTWORK")
        holder.icon:SetAllPoints()
        Style:Zoom(holder.icon)
        holder.icon:SetDesaturated(true)
        holder.icon:SetAlpha(.45)
        holder.label = holder:CreateFontString(nil, "OVERLAY", Style:NameFont())
        holder.label:SetPoint("TOP", holder, "BOTTOM", 0, -3)
        holder.label:SetWordWrap(false)
        holder.decor = Style:Decor(holder, holder)
        Style:ShowDecor(holder.decor, Style:DecorFor("icon"))
        holder:Hide()
        bar.holders[i] = holder
    end
    if not self:Available() then return end
    -- From now on the bar goes right out rather than hiding (Bars.lua B:Hold).
    ns.Bars:Hold(bar)
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
            F.Add(container, "AddAuraSlot", "b" .. i, aura.filter, { initializeFrame = F.Guard(SlotLook(bar.holders[i], bar.key)) })
            container:SetAuraSlotEnabled("b" .. i, false)
        end
        bar.container = container
    end)
    if not ok and not F.lastError then
        F.lastError = tostring(err)
        print("|cffffd100" .. ns.TITLE .. ":|r the " .. ns.BAR_NAMES[bar.key] .. " bar couldn't start. Please report this: " .. F.lastError)
    end
end

-- The border and shadow round each fixed spot, when chosen. They go with
-- the Debuffs bar's greyed spots while there's no enemy, so no empty boxes
-- are left behind. Only changed when something about them has.
function F:HolderDecor(bar)
    if not (bar and bar.holders) then return end
    local border, shadow = Style:DecorFor("icon")
    local shown = bar.enemy ~= false
    border, shadow = border and shown, shadow and shown
    local state = (border and "b" or "") .. (shadow and "s" or "")
    if bar.holderDecor == state then return end
    bar.holderDecor = state
    for _, holder in ipairs(bar.holders) do Style:ShowDecor(holder.decor, border, shadow) end
end

-- The Debuffs bar's Glow when missing: only on a living enemy you target
-- (not with nothing targeted, a friend or a corpse, kept greyed or not).
-- A secret answer counts as yes. Only FECM's own frames change, so any time
-- (your target dying: UNIT_FLAGS, Bars.lua).
function F:TargetGlow(bar)
    if not (bar and bar.holders) then return end
    local living = UnitExists("target") and UnitCanAttack("player", "target")
    if not Open(living) then living = true end
    if living and UnitIsDeadOrGhost then
        local dead = UnitIsDeadOrGhost("target")
        if Open(dead) and dead then living = false end
    end
    for _, holder in ipairs(bar.holders) do
        if holder.glowHost then holder.glowHost:SetAlpha(living and 1 or 0) end
    end
end

-- The Debuffs bar's greyed spots only show while you have a target you can
-- attack, or always with Keep them greyed with no target, and its icons
-- follow a new target at once. Only the addon's own textures change here,
-- so this is fine in combat, as is the refresh, which Blizzard's target
-- frame does the same way. (bar.enemy: whether the spots show, which their
-- rings and the whole-bar box follow.)
function F:UpdateTarget(bar)
    if not (bar and bar.holders and ns.AURA_BARS[bar.key].unit == "target") then return end
    local hostile = UnitExists("target") and UnitCanAttack("player", "target")
    if not Open(hostile) then hostile = true end
    -- Kept greyed: no target, a friendly or a dead one leave them up too.
    if self:KeepGreyed(bar.data) then hostile = true end
    bar.enemy = hostile and true or false
    for _, holder in ipairs(bar.holders) do holder.icon:SetAlpha(bar.enemy and .45 or 0) end
    self:TargetGlow(bar)
    self:HolderDecor(bar)
    if bar.container then bar.container:UpdateAllAuras() end
end

-- Only show missing ------------------------------------------------------------------
-- Which of the Buffs bar's entries are on you, read out of combat only:
-- after the bar is laid out (login, a change of yours, a spell learned), as
-- your buffs change (UNIT_AURA, at most once a frame, Bars.lua) and as a
-- fight ends. Never polled: a read the game wouldn't answer is tried again
-- a moment later a few times at most, and as its restrictions change. In a
-- fight the game keeps your buffs secret (asked then, it finds none even
-- with them up), so nothing is read.

-- Whether the game lets the addon see your buffs now: out of combat, while
-- it doesn't say they're kept secret (a raid encounter, say).
local function Readable()
    if InCombatLockdown() then return false end
    local fighting = UnitAffectingCombat and UnitAffectingCombat("player")
    if not Open(fighting) or fighting then return false end
    local secrets = C_Secrets
    local ask = type(secrets) == "table" and secrets.ShouldAurasBeSecret
    if type(ask) == "function" then
        local ok, secret = pcall(ask)
        if not (ok and Open(secret) and secret == false) then return false end
    end
    return true
end

-- Whether any of an entry's spells is on you: true, false, or nil when the
-- game won't say (a secret or unreadable answer). Only asks whether one is
-- there, never what's in it. The IDs are the ones its slot is given: every
-- rank, and every linked spell's for joined entries.
local function OnYou(ids)
    local auras = C_UnitAuras
    local get = type(auras) == "table" and auras.GetPlayerAuraBySpellID
    if type(get) ~= "function" then return nil end
    local unknown = false
    for id in pairs(ids) do
        local ok, aura = pcall(get, id)
        if not ok or not Open(aura) then
            unknown = true
        elseif aura ~= nil then
            return true
        end
    end
    if unknown then return nil end
    return false
end

-- Reads which entries are on you (bar.up, by place). One the game won't say
-- about keeps what it was last (by its names: bar.upBy), and one never read
-- counts as missing, so it shows. True when any changed. Nothing is read
-- with Only show missing off, or your bars. bar.unread says the game didn't
-- answer for one or more (your buffs still secret as a fight ends, say), so
-- the bars read again a moment later (Bars.lua, Again).
function F:Check(bar)
    bar.unread = nil
    if not (self:OnlyMissing(bar.data) and ns.Bars:Enabled()) then
        bar.upBy = nil
        return false
    end
    local readable = Readable()
    local last, now, up, changed = bar.upBy or {}, {}, bar.up, false
    for i = 1, bar.count do
        local name, on = bar.names[i], nil
        if readable then on = OnYou(bar.slotIDs[i]) end
        if on == nil then on, bar.unread = last[name], true end
        now[name] = on
        on = on == true
        if (up[i] == true) ~= on then changed = true end
        up[i] = on
    end
    for i = bar.count + 1, #up do up[i] = nil end
    bar.upBy = now
    return changed
end

-- Whether entry i has a spot on the bar now: always with missing ones
-- greyed; with Only show missing, while it's missing, and every one while
-- the bars are arranged (unlocked, or in Edit Mode), so the bar can be
-- placed and sized with them all. A missing one's slot stays on, so a buff
-- cast in a fight draws over its greyed spot.
local function Spot(bar, i)
    return not (F:OnlyMissing(bar.data) and bar.up[i]) or ns.Bars:Arranging()
end

-- Shows the fixed spots that show and hides the rest (all of them while
-- packed), and lists those shown in your order (bar.spots) for the bar to
-- place side by side. Out of combat only, as they carry the slots.
function F:Spots(bar)
    local fixed, spots = not self:Packed(bar.data), {}
    for i = 1, bar.count do
        local holder = bar.holders[i]
        local shown = fixed and Spot(bar, i)
        holder:SetShown(shown)
        if shown then spots[#spots + 1] = holder end
    end
    bar.spots = spots
    return spots
end

-- Glow when missing (a player's idea: a Seal that fell off): the glow picked
-- on the Look page on a buff's greyed spot, kept inside it (clipped) and
-- under the game's icon. The addon can't tell in a fight whether the buff is
-- up, and needn't: while it's on you the game's icon covers the glow. Made
-- the first time it's wanted.
local function MissingGlow(holder, on, size)
    local host = holder.glowHost
    if not on then
        if host then ns.SetGlow(host, false) end
        return
    end
    if not host then
        host = CreateFrame("Frame", nil, holder)
        host:SetPoint("CENTER")
        host:SetClipsChildren(true)
        host.top, host.glows = host, {}
        holder.glowHost = host
    end
    host:SetSize(size, size)
    ns.UseGlow(host)
    ns.SetGlow(host, true)
end

-- Places the holders for the bar's entries and works out each one's spell
-- IDs; joined entries count as one, with every linked spell's IDs.
function F:Layout(bar, data)
    local size, spacing = ns.IconSize(data), data.spacing
    local count = 0
    local picks, glows = ns.MissingPicks(bar.key), ns.GlowMissing(bar.key)
    local counts = bar.key == "debuff" and ns.CountTicks(bar.key) or {}
    for _, group in ipairs(ns.Bars:Units(bar.key)) do
        local ids, entry, picked, glow, yours = {}, nil, nil, false, {}
        for _, name in ipairs(group) do
            local found = ns.Spells:Find(name)
            if found and found.ids and ns.Spells:ForMe(name, bar.key) then
                entry = entry or found
                if picks[name] and not picked then picked = found end -- the first picked, as B:Picked
                glow = glow or glows[name] == true
                yours[#yours + 1] = name
                for _, id in ipairs(found.ids) do ids[id] = true end
            end
        end
        -- Its tick count: the counted debuffs' pace, and for a joined icon
        -- with others at another pace, the lengths it shows on (B:IconTicks).
        local pace, shows = ns.Bars:IconTicks(yours, counts)
        -- A joined icon shows its picked entry (on the bar's page), faded,
        -- while none is up; else its first of yours.
        entry = picked or entry
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
            MissingGlow(holder, glow, size)
            bar.slotIDs[count] = ids
            bar.names[count] = table.concat(group, "+")
            bar.tickPaces[count], bar.tickShows[count] = pace, shows
        end
    end
    for i = count + 1, ns.BUFF_SLOTS do
        bar.holders[i]:Hide()
        MissingGlow(bar.holders[i], false)
        bar.slotIDs[i], bar.names[i], bar.tickPaces[i], bar.tickShows[i] = nil, nil, nil, nil
    end
    for _, parts in ipairs(bar.groupParts) do parts.cooldown:SetHideCountdownNumbers(not data.showTimer) end
    bar.count = count
    -- Which are on you, then the spots that show.
    self:Check(bar)
    self:Spots(bar)
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

-- Debuffs you put on yourself (Weakened Soul from your own shield, Recently
-- Bandaged), when ticked, on the Buffs bar, the Debuffs bar or both. The game
-- won't let an addon pick out a debuff on you by spell ID, only by who cast
-- it, so this is one group for all of yours. Packed only: fixed spots belong
-- to entries. Up to four, well under the ten Blizzard makes for a group.
-- * The Buffs bar's container watches you, so the group goes in it, after
--   your buffs (before them when the bar grows left).
-- * The Debuffs bar's watches your target, and a container watches one unit,
--   so that bar gets a second container of its own for them, watching you
--   (SelfContainer). The game sizes a container itself and nothing may hang
--   off one, so it's anchored to the bar: just past the bar's end the way it
--   grows, or in the bar's own spot while the bar has no entries (SelfSpot).
local SELF_MAX = 4
function F:SelfOn(bar)
    return bar ~= nil and ns.AURA_BARS[bar.key] ~= nil and bar.data ~= nil and bar.data.selfDebuffs == true
        and self:Packed(bar.data)
end

-- The Debuffs bar's container for your debuffs on you, made the first time
-- they're ticked with your bars on, as the Buffs bar's group is: never in a
-- fight (F:Apply waits for it to end), on a bar already holding its own
-- container (F:Create), so the bar is never shown or hidden after and the
-- container is made in sight. Made once; if the game turns it down, that's
-- said once and not tried again.
local function SelfContainer(bar)
    if bar.selfContainer or bar.selfFailed then return bar.selfContainer end
    ns.Bars:Hold(bar)
    local ok, err = pcall(function()
        local container = CreateFrame("AuraContainer", nil, bar, "CustomAuraContainerTemplate")
        container:SetPoint("CENTER", bar, "CENTER")
        container:SetSize(BASE, BASE)
        container:EnableMouse(false)
        container:SetFrameLevel(bar:GetFrameLevel() + 5)
        container:SetEditModePreviewEnabled(false)
        container:SetUnit("player")
        bar.selfContainer = container
    end)
    if not ok then
        bar.selfFailed = true
        if not F.lastError then
            F.lastError = tostring(err)
            print("|cffffd100" .. ns.TITLE .. ":|r your debuffs on you on the " .. ns.BAR_NAMES[bar.key]
                .. " bar couldn't start. Please report this: " .. F.lastError)
        end
    end
    return bar.selfContainer
end

-- Where that container sits on the bar: its point, the bar's point, and how
-- far out (in the container's own size, as it's scaled with the icons). Past
-- the end the bar grows to, the bar's spacing from it: the right end, or the
-- left when it grows left. With no entries, where they'd start instead.
local function SelfSpot(bar, spacing)
    local grow = bar.data.grow
    if bar.count == 0 then
        local side = grow == "left" and "RIGHT" or grow == "right" and "LEFT" or "CENTER"
        return side, side, 0
    end
    if grow == "left" then return "RIGHT", "LEFT", -spacing end
    return "LEFT", "RIGHT", spacing
end

function F:ApplySelf(bar, packed, spacing, scale)
    local own = ns.AURA_BARS[bar.key].unit == "player"
    local on = packed and bar.data.selfDebuffs == true
    -- After the last entry, or before the first when the bar grows left (on
    -- the Debuffs bar the group is alone in its container, so it's moot).
    local layout = { layoutIndex = bar.data.grow == "left" and 0 or ns.BUFF_SLOTS + 1, groupSpacing = spacing }
    local signature, point, to, x = "", nil, nil, nil
    if on then
        signature = layout.layoutIndex .. "|" .. spacing
        if not own then
            point, to, x = SelfSpot(bar, spacing)
            signature = signature .. "|" .. point .. "|" .. to .. "|" .. x .. "|" .. scale
        end
    end
    if bar.appliedSelf == signature then return end
    -- On the Debuffs bar, nothing is made until they're first wanted.
    local container
    if own then
        container = bar.container
    elseif on or bar.selfGroup then
        container = SelfContainer(bar)
    end
    if not container then return end
    bar.appliedSelf = signature
    if point then
        container:ClearAllPoints()
        container:SetPoint(point, bar, to, x, 0)
        container:SetScale(scale)
    end
    if on and not bar.selfGroup then
        AddGroup(container, "self", "HARMFUL", { initializeFrame = F.Guard(GroupLook(bar)), maxFrameCount = SELF_MAX,
            candidateFilters = { isFromPlayerOrPlayerPet = true }, layout = layout })
        bar.selfGroup = true
    elseif bar.selfGroup then
        if on then container:SetAuraGroupLayout("self", layout) end
        container:SetAuraGroupEnabled("self", on)
    end
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
        -- Only show missing: a buff on you has no spot, and its slot is off.
        if ids and not Spot(bar, i) then ids = nil end
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
    local scale = packed and ns.IconSize(data) / BASE or 1
    local spacing = data.spacing / scale
    -- Growing left, the first entry sits at the right, as fixed spots do.
    local function Index(i)
        return data.grow == "left" and ns.BUFF_SLOTS + 1 - i or i
    end
    if on and packed then
        for i = bar.groups + 1, bar.count do
            AddGroup(container, "g" .. i, ns.AURA_BARS[bar.key].filter, { initializeFrame = F.Guard(GroupLook(bar, i)), maxFrameCount = 1,
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
    self:ApplySelf(bar, on and packed, spacing, scale)
    if bar.appliedScale ~= scale then
        bar.appliedScale = scale
        container:SetScale(scale)
    end
    self:Ticks(bar)
end

-- Count ticks: each Debuffs bar icon's count set going at its entry's pace,
-- from 0 or 1, or hidden, and placed, sized and coloured as the Debuffs page
-- says. Fixed slot i and packed group i are entry i's (a packed icon is
-- drawn at BASE, then scaled). Out of combat only (F:Apply), as the icons
-- are the game's; each is only sent as it changes, and a rule the game
-- turns down leaves the count hidden. Tucked a pixel into its corner, or
-- On the edge (a player's ask): centred on the border there, half outside.
local INSET = { TOPLEFT = { 1, -1, "LEFT" }, TOP = { 0, -1, "CENTER" }, TOPRIGHT = { -1, -1, "RIGHT" },
    BOTTOMLEFT = { 1, 1, "LEFT" }, BOTTOM = { 0, 1, "CENTER" }, BOTTOMRIGHT = { -1, 1, "RIGHT" }, CENTER = { 0, 0, "CENTER" } }

-- The count's colour by how long its aura lasts: its colour throughout, or
-- for a joined icon (shows: its debuffs' lengths in order, each counted or
-- not; B:IconTicks) see-through for the others, stepping half way between.
local function Paint(curve, colour, shows)
    curve:ClearPoints()
    local function Add(x, on) curve:AddPoint(x, CreateColor(colour[1], colour[2], colour[3], on and 1 or 0)) end
    if not shows then
        Add(0, true)
        Add(100000, true)
        return
    end
    Add(0, shows[1][2])
    for i = 1, #shows - 1 do
        local a, b = shows[i], shows[i + 1]
        if a[2] ~= b[2] then
            local half = (a[1] + b[1]) / 2
            Add(half - .01, a[2])
            Add(half + .01, b[2])
        end
    end
    Add(100000, shows[#shows][2])
end

local function Shows(shows)
    if not shows then return "" end
    local parts = {}
    for i, show in ipairs(shows) do parts[i] = show[1] .. (show[2] and "+" or "-") end
    return table.concat(parts, ",")
end

local function SetCount(ticks, seconds, shows, data, size)
    -- Telling a joined icon's debuffs apart needs the game's colour curve.
    if shows and not ticks.curve then seconds = nil end
    if seconds then
        local rule = seconds .. ":" .. data.tickFrom
        if ticks.rule ~= rule then
            local ok = pcall(function()
                ticks.formatter:ClearBreakpoints()
                ticks.formatter:AddBreakpoint(Ticking(seconds, data.tickFrom))
            end)
            ticks.rule = ok and rule or nil
            if not ok then seconds = nil end
        end
    end
    ticks.frame:SetShown(seconds ~= nil)
    if not seconds then return end
    local font = Style:Ticks(size, data.tickSize)
    local look = data.tickAt .. "|" .. tostring(data.tickEdge) .. "|" .. font .. "|" .. data.tickColour .. "|" .. Shows(shows)
    if ticks.look == look then return end
    local at = INSET[data.tickAt] or INSET.TOPLEFT
    local point = INSET[data.tickAt] and data.tickAt or "TOPLEFT"
    local colour = ns.COUNT_COLOURS[data.tickColour] or ns.COUNT_COLOURS.white
    if ticks.curve and not pcall(Paint, ticks.curve, colour, shows) then
        -- Turned down: a joined icon can't tell its debuffs apart, so no count.
        ticks.look = nil
        if shows then return ticks.frame:Hide() end
    else
        ticks.look = look
    end
    local text = ticks.text
    text:SetFontObject(font)
    text:SetTextColor(colour[1], colour[2], colour[3])
    text:ClearAllPoints()
    if data.tickEdge and point ~= "CENTER" then
        text:SetPoint("CENTER", ticks.frame, point, 0, 0)
        text:SetJustifyH("CENTER")
    else
        text:SetPoint(point, at[1], at[2])
        text:SetJustifyH(at[3])
    end
end

function F:Ticks(bar)
    local data = bar.data
    for i = 1, ns.BUFF_SLOTS do
        local seconds, shows, holder = bar.tickPaces[i], bar.tickShows[i], bar.holders[i]
        if holder.slot and holder.slot.ticks then SetCount(holder.slot.ticks, seconds, shows, data, holder.size or BASE) end
        for _, ticks in ipairs(bar.groupTicks[i] or {}) do SetCount(ticks, seconds, shows, data, BASE) end
    end
end
