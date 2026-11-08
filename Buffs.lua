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
-- * Only when missing (the Buffs bar, ticked buff by buff): those buffs alone
--   go that way, each in a fixed slot and holder of its own while it's
--   missing; the rest stay as they are, packed or greyed. On a packed bar
--   their spots lead the row and the game's packed icons follow (F:Spots).
local _, ns = ...

local F = {}
ns.BuffBar = F

local Style = ns.Style
local BASE = 36 -- packed icons are drawn at this size, then scaled

local function Open(value)
    return not (issecretvalue and issecretvalue(value))
end

-- What the container is told about a slot or group: its spell IDs, and on
-- the Debuffs bar, only a player's (the bar's "HARMFUL|PLAYER" filter then
-- keeps only yours: this flag alone lets any player's through).
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

-- Only when missing: whether any buff on the Buffs bar is ticked to show
-- only while it's missing (not with the bar's own Only show missing, which
-- already does it for all). From the saved picks, so it's known before the
-- bar is laid out.
function F:Flagged(key, data)
    if ns.BAR_KIND[key] ~= "buff" or data == nil or self:OnlyMissing(data) then return false end
    return next(ns.OnlyWhenMissing(key)) ~= nil
end

-- Whether the bar reads which of your buffs are on you: with Only show
-- missing, or any buff ticked Only when missing.
function F:Watches(key, data)
    return self:OnlyMissing(data) or self:Flagged(key, data)
end

-- Whether entry i shows only while it's missing: every entry with Only show
-- missing, else one ticked Only when missing (bar.only, F:Layout).
function F:Hides(bar, i)
    return self:OnlyMissing(bar.data) or bar.only ~= nil and bar.only[i] == true
end

-- Whether a buff on the bar as laid out is ticked Only when missing: a tick
-- on another character's buff in a shared profile isn't (it has no icon
-- here). Before the bar is first laid out, from the saved picks (F:Flagged).
function F:Ticked(bar, key, data)
    if bar and bar.only then return next(bar.only) ~= nil end
    return self:Flagged(key, data)
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

-- Sizes an icon's numbers for its size, and shows or hides the countdown,
-- in the spot picked in Icon details; look: its entry's own countdown font
-- and size (settings per spell), or nil for the Look page's.
local function Fit(parts, size, showTimer, look)
    parts.cooldown:SetCountdownFont(Style:Countdown(size, look))
    parts.cooldown:SetHideCountdownNumbers(not showTimer)
    parts.count:SetFontObject(Style:Count(size))
    Style:AuraNumbers(parts)
end

-- Icon details (the Look page) on the bar's icons as made: each packed
-- icon's and each fixed spot's, its numbers sized as laid out (in its
-- entry's own look). Only out of a fight (Bars.lua AuraDetails).
function F:Details(bar)
    local function Detail(parts, size, look)
        Style:CooldownLook(parts.cooldown)
        parts.cooldown:SetCountdownFont(Style:Countdown(size, look))
        Style:AuraNumbers(parts)
    end
    local looks = bar.looks or {}
    for _, parts in ipairs(bar.groupParts or {}) do Detail(parts, BASE, parts.index and looks[parts.index]) end
    for _, holder in ipairs(bar.holders or {}) do
        if holder.slot then Detail(holder.slot, holder.size or BASE, holder.look) end
        if holder.enchant then Detail(holder.enchant, holder.size or BASE, holder.look) end
    end
end

-- Settings per spell: a packed entry's icon in its entry's own look (or the
-- Look page's again), set only when that changes. Out of a fight (F:Layout).
local function GroupFont(parts, look)
    local key = Style:LookKey(look)
    if parts.lookKey == key then return end
    parts.lookKey = key
    parts.cooldown:SetCountdownFont(Style:Countdown(BASE, look))
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
    ["Mind Flay"] = 1,
    ["Moonfire"] = 3,
    ["Pounce Bleed"] = 3,
    ["Pyroblast"] = 3,
    ["Rake"] = 3,
    ["Rend"] = 3,
    ["Rip"] = 2,
    ["Rupture"] = 2,
    ["Savage Rend"] = 3,
    ["Scorpid Poison"] = 2,
    ["Serpent Sting"] = 3,
    ["Shadow Word: Pain"] = 3,
    ["Siphon Life"] = 3,
    ["Starshards"] = 1,
    ["Tendon Rip"] = 3,
    ["Viper Sting"] = 2,
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
    ["Frost Nova"] = { 8 },
    ["Frost Shock"] = { 8 },
    ["Frostbite"] = { 5 },
    ["Frostbolt"] = { 5, 6, 7, 8, 9 },
    ["Frostfire Bolt"] = { 9 },
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
    ["Lacerate"] = { 15, 21 },
    ["Lava Breath"] = { 10 },
    ["Long Daze"] = { 6 },
    ["Mind Control"] = { 60 },
    ["Mind Flay"] = { 3 },
    ["Mind Soothe"] = { 15 },
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
    ["Rake"] = { 9 },
    ["Rend"] = { 9, 12, 15, 18, 21 },
    ["Repentance"] = { 6 },
    ["Rip"] = { 12 },
    ["Riposte"] = { 6 },
    ["Rupture"] = { 6, 8, 10, 12, 14, 16 },
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
    ["Silence"] = { 5 },
    ["Siphon Life"] = { 30 },
    ["Soothe Animal"] = { 15 },
    ["Starshards"] = { 6 },
    ["Stormstrike"] = { 12 },
    ["Subjugate Demon"] = { 300 },
    ["Sunder Armor"] = { 30 },
    ["Tame Beast"] = { 20 },
    ["Taunt"] = { 3 },
    ["Tendon Rip"] = { 9 },
    ["Thunder Clap"] = { 10, 14, 18, 22, 26, 30 },
    ["Touch of Weakness"] = { 120, 600 },
    ["Turn Undead"] = { 10, 15, 20 },
    ["Vampiric Embrace"] = { 30 },
    ["Vindication"] = { 10 },
    ["Viper Sting"] = { 8 },
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

-- Glow while active ------------------------------------------------------------------
-- A ticked buff's icon glows while it's up, like a proc. The addon can't tell
-- in a fight whether a buff is up, and needn't: the glow is a frame inside
-- the game's own icon, made hidden with the icon, so it's only drawn while
-- the game shows that icon. The addon shows or hides it out of a fight only
-- (F:Actives). It has no scripts, so the container never runs the addon's
-- code as it shows and hides its icons. It's the Look page's gold edge and,
-- in the Proc glow style, a looping proc animation on the addon's own
-- texture too, handed to the game to play while the icon shows. The texture
-- starts see-through, so if the game won't take or play it, the edge shows alone.
-- Glow size (the profile's) makes both smaller or bigger: the loop's spread
-- past the icon, and the edge's width.
local ACTIVE_ATLAS = "UI-HUD-ActionBar-Proc-Loop-Flipbook"
local ACTIVE_SPREAD = 1.4 -- the loop spreads this far past the icon, as the game's proc glow does

-- The glow for a Buffs bar icon, hidden: { frame, strips (the edge's sides),
-- loop (nil when the game didn't take it) }, or nil if it can't be made.
local function ActiveGlow(button, top)
    local made, frame, strips = pcall(function()
        local edge, sides = ns.NewEdge(button)
        edge:SetFrameLevel(top:GetFrameLevel() + 1)
        return edge, sides
    end)
    if not made then return nil end
    local active = { frame = frame, strips = strips, width = ns.EDGE_WIDTH }
    local loop = CreateFrame("Frame", nil, frame)
    loop:SetPoint("CENTER")
    loop:SetSize(BASE * ACTIVE_SPREAD, BASE * ACTIVE_SPREAD)
    local taken = pcall(function()
        local art = loop:CreateTexture(nil, "ARTWORK")
        art:SetAllPoints()
        art:SetAtlas(ACTIVE_ATLAS)
        art:SetAlpha(0)
        -- As the game's own proc loop: seen while it plays, over and over.
        local spin = art:CreateAnimationGroup()
        spin:SetLooping("REPEAT")
        local seen = spin:CreateAnimation("Alpha")
        seen:SetFromAlpha(1)
        seen:SetToAlpha(1)
        seen:SetDuration(.001)
        seen:SetOrder(1)
        local flip = spin:CreateAnimation("FlipBook")
        flip:SetFlipBookRows(6)
        flip:SetFlipBookColumns(5)
        flip:SetFlipBookFrames(30)
        flip:SetDuration(1)
        flip:SetOrder(2)
        local hand = button.AddAuraShownAnimation
        if type(hand) ~= "function" then error("the game takes no animation") end
        hand(button, spin)
    end)
    if taken then active.loop = loop else loop:Hide() end
    return active
end

-- Runs once per icon, before the client restricts it in combat. Everything
-- supplied to the icon must be a descendant of its button. A packed icon
-- carries its own border and shadow; a fixed one's holder has them. A
-- Debuffs bar entry's icon can count ticks too (counts), and a Buffs bar
-- entry's can glow while it's up (active). look: its entry's own countdown
-- font and size (settings per spell), or nil.
local function Look(button, size, showTimer, decorate, counts, look, active)
    button:EnableMouse(false)
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
    -- Stack counts sit above the sweep.
    local top = CreateFrame("Frame", nil, button)
    top:SetAllPoints()
    top:SetFrameLevel(cooldown:GetFrameLevel() + 1)
    local count = top:CreateFontString(nil, "OVERLAY", "NumberFontNormal")
    count:SetPoint("BOTTOMRIGHT", -1, 1)
    button:SetApplicationCount(count)
    local parts = { cooldown = cooldown, count = count }
    if counts then parts.ticks = TickCount(button, top) end
    if active then parts.active = ActiveGlow(button, top) end
    if decorate then
        -- Made now: the container's icons only take art as they're made.
        parts.decor = Style:Decor(button, button, 0, true)
        Style:ShowDecor(parts.decor, Style:DecorFor("icon"))
    end
    Fit(parts, size, showTimer, look)
    parts.lookKey = Style:LookKey(look)
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
        holder.slot = Look(button, holder.size or BASE, holder.showTimer ~= false, false, ns.BAR_KIND[key] == "debuff", holder.look,
            ns.BAR_KIND[key] == "buff")
    end
end

-- A packed entry's group (index: its place) keeps its icons' tick counts or
-- glows and its entry's own look; the group of your debuffs on you has none.
local function GroupLook(bar, index)
    return function(button)
        button:SetSize(BASE, BASE)
        local parts = Look(button, BASE, bar.data.showTimer, true, ns.BAR_KIND[bar.key] == "debuff" and index ~= nil,
            index and bar.looks and bar.looks[index] or nil, ns.BAR_KIND[bar.key] == "buff" and index ~= nil)
        parts.index = index
        bar.groupParts[#bar.groupParts + 1] = parts
        if parts.ticks then
            bar.groupTicks[index] = bar.groupTicks[index] or {}
            table.insert(bar.groupTicks[index], parts.ticks)
        end
    end
end

-- Warn at N seconds left -------------------------------------------------------------
-- (A player's idea: Siphon Life warning with 3 seconds left on the target,
-- Demon Armor with 10 minutes left on you.) The addon can't read an aura's
-- time in a fight, so it hands the game rules it runs itself, set out of
-- combat (F:Warns):
-- * the entry's countdown turns red from N seconds left (its cooldown's
--   formatter, Style:WarnText), packed or in a fixed spot;
-- * round a fixed spot, a red edge from N seconds left: a second slot for the
--   entry (w1..w16, beside b1..b16) on the same spells, whose icon draws only
--   its time left, through a rule that writes the edge (a texture in its
--   text) under N and nothing from N. Slots are independent, so both take
--   the same aura, and the edge goes as it ends or is recast (the game
--   starts its time again). A packed bar's icons have no spot to ring.
-- * out of a fight, your own buff's spot glows from N seconds left (the
--   Look page's ready glow), from your buffs read then (F:LowTime).
local MARK = ns.MEDIA .. "LowEdge" -- a soft white square ring, tinted in its text
local MARK_SPREAD = 1.25 -- the ring's art is this much bigger than the icon it sits round
local MARK_COLOUR = "255:64:64"

-- Whether the game can draw the edge: its number rules and an icon's time left.
local function CanMark()
    local util, enum = C_StringUtil, Enum
    return type(util) == "table" and type(util.CreateNumericRuleFormatter) == "function" and type(enum) == "table"
        and type(enum.DurationTextBindingProperty) == "table" and enum.DurationTextBindingProperty.RemainingDuration ~= nil
end

-- The edge as text, size across.
local function Edge(size)
    return ("|T%s:%d:%d:0:0:64:64:0:64:0:64:%s|t"):format(MARK, size, size, MARK_COLOUR)
end

-- A w-slot's icon: over its entry's spot, never taking the mouse, drawing
-- only its time left (nothing until a rule is set) on a layer above the
-- b-slot's icon, its sweep and its counts. Made as the slot is added.
local function MarkLook(holder)
    return function(button)
        button:EnableMouse(false)
        button:SetAllPoints(holder)
        local ok, mark = pcall(function()
            local formatter = C_StringUtil.CreateNumericRuleFormatter()
            formatter:AddBreakpoint({ threshold = 0, format = "" })
            local frame = CreateFrame("Frame", nil, button)
            frame:SetAllPoints()
            frame:SetFrameLevel(button:GetFrameLevel() + 5)
            local text = frame:CreateFontString(nil, "OVERLAY", "NumberFontNormal")
            text:SetPoint("CENTER")
            button:SetDurationText(text, { textFormat = { formatString = "{}", components = {
                { property = Enum.DurationTextBindingProperty.RemainingDuration, formatter = formatter } } } })
            return { frame = frame, text = text, formatter = formatter, rule = "" }
        end)
        holder.mark = ok and mark or nil
        if not ok and not F.markError then F.markError = tostring(mark) end
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

-- Weapon enchants --------------------------------------------------------------------
-- (A player's report: a shaman's never lit.) Rockbiter Weapon, a rogue's
-- poisons and the like sit on the weapon, not on you, so the aura container
-- can't see them. The addon reads your two hands itself and draws the entry's
-- own spot: lit with its time left while it's on, greyed while it's missing,
-- and on a packed bar there only while it's on. Each spell's name with the
-- enchants its ranks put on a weapon, from build 70753's data (SpellEffect's
-- effect 360, and 54 for the last ID of a shaman's four and the later poisons).
-- A warlock's Firestone and Spellstone (every stone's), from build 70790's
-- (effect 360).
local ENCHANTS = {
    ["Rockbiter Weapon"] = { 29, 6, 1, 503, 1663, 683, 1664, 7568 },
    ["Flametongue Weapon"] = { 5, 4, 3, 523, 1665, 1666, 7567 },
    ["Frostbrand Weapon"] = { 2, 12, 524, 1667, 1668, 7566 },
    ["Windfury Weapon"] = { 283, 284, 525, 1669, 7569 },
    ["Sebacious Poison"] = { 7254 },
    ["Numbing Poison"] = { 7255 },
    ["Atrophic Poison"] = { 7256 },
    ["Occult Poison I"] = { 7542 },
    ["Occult Poison II"] = { 7651 },
    ["Firestone"] = { 1803, 1823, 1824, 1825 },
    ["Spellstone"] = { 8059, 8060, 8061 },
}
-- The poisons with a name per rank: any of them counts as the family. (The
-- spells that make Wound Poison II to IV and Crippling Poison II have a
-- numeral, 13228-13230 and 3421 in build 70790; what each puts on, and the
-- spell its item casts, go by the plain name.)
for name, ids in pairs({ ["Instant Poison"] = { 323, 324, 325, 623, 624, 625 }, ["Deadly Poison"] = { 7, 8, 626, 627, 2630 },
    ["Mind-numbing Poison"] = { 35, 23, 643 }, ["Wound Poison"] = { 703, 704, 705, 706 }, ["Crippling Poison"] = { 22, 603 } }) do
    for rank, numeral in ipairs({ "", " II", " III", " IV", " V", " VI" }) do
        if ids[rank] then ENCHANTS[name .. numeral] = ids end
    end
end
-- The imbues Forever's scrolls put on (Scroll of Imbue Flame...), from build
-- 70790's (effect 360): each one's spell and the enchant it puts on. The
-- scroll casts the spell, so no list of yours has it: its name is found here
-- (Spells.lua), and it's the Buffs bar's alone, like a warlock's stones. Not
-- the test imbue (8696) nor an NPC's Instant Toxin (42).
local IMBUES = {
    ["Imbue Accuracy"] = { 1302306, 8711 },
    ["Imbue Baleflame"] = { 1302219, 8706 },
    ["Imbue Balefrost"] = { 1302305, 8714 },
    ["Imbue Chillknife"] = { 1296225, 8698 },
    ["Imbue Flame"] = { 1302304, 8713 },
    ["Imbue Frost"] = { 1302283, 8709 },
    ["Imbue Greater Flame"] = { 1302311, 8716 },
    ["Imbue Greater Frost"] = { 1302312, 8717 },
    ["Imbue Iceknife"] = { 1302284, 8710 },
    ["Imbue Lesser Flame"] = { 1295720, 8700 },
    ["Imbue Manablade"] = { 1302308, 8715 },
    ["Imbue Precision"] = { 1302310, 8718 },
    ["Imbue Quickening"] = { 1302307, 8712 },
    ["Imbue Spark"] = { 1302227, 8707 },
    ["Imbue Striking"] = { 1302217, 8708 },
}
ns.IMBUE_SPELLS = {}
for name, imbue in pairs(IMBUES) do
    ns.IMBUE_SPELLS[name] = imbue[1]
    ENCHANTS[name] = { imbue[2] }
end
-- (The spell lists give these a section of their own: Spells.lua.)
ns.WEAPON_ENCHANTS = ENCHANTS

-- Main hand enchant and Off hand enchant (Spells.lua: entry.hand, the slot):
-- lit while anything at all is on that hand for a time (an oil, a stone, a
-- poison, an imbue), showing which: its name and icon here, or for one not
-- here the weapon's own icon (as the game's own buff button shows it) and
-- "Weapon enchant". A hand with no weapon in it (nothing there, a shield, a
-- held-in-off-hand item) has nothing missing: no glow, and no spot where
-- spots come and go. Every temporary weapon enchant a player can get, by its
-- enchant ID: the name and icon of the item that puts it on (a scroll by its
-- imbue's name), else the spell's. Printed by node Tools/MakeHandEnchants.mjs
-- from build 70790's data.
ns.HAND_ENCHANTS = {
    [1] = { "Rockbiter Weapon", 136086 },
    [2] = { "Frostbrand Weapon", 135847 },
    [3] = { "Flametongue Weapon", 135814 },
    [4] = { "Flametongue Weapon", 135814 },
    [5] = { "Flametongue Weapon", 135814 },
    [6] = { "Rockbiter Weapon", 136086 },
    [7] = { "Deadly Poison", 132290 },
    [8] = { "Deadly Poison II", 132290 },
    [12] = { "Frostbrand Weapon", 135847 },
    [13] = { "Coarse Sharpening Stone", 135249 },
    [14] = { "Heavy Sharpening Stone", 135250 },
    [19] = { "Rough Weightstone", 135255 },
    [20] = { "Coarse Weightstone", 135256 },
    [21] = { "Heavy Weightstone", 135257 },
    [22] = { "Crippling Poison", 132274 },
    [23] = { "Mind-numbing Poison II", 136066 },
    [25] = { "Shadow Oil", 134803 },
    [26] = { "Frost Oil", 134800 },
    [29] = { "Rockbiter Weapon", 136086 },
    [35] = { "Mind-numbing Poison", 136066 },
    [40] = { "Rough Sharpening Stone", 135248 },
    [263] = { "Shiny Bauble", 134335 },
    [264] = { "Nightcrawlers", 134324 },
    [265] = { "Bright Baubles", 134139 },
    [266] = { "Aquadynamic Fish Attractor", 133982 },
    [283] = { "Windfury Weapon", 136018 },
    [284] = { "Windfury Weapon", 136018 },
    [323] = { "Instant Poison", 132273 },
    [324] = { "Instant Poison II", 132273 },
    [325] = { "Instant Poison III", 132273 },
    [483] = { "Solid Sharpening Stone", 135251 },
    [484] = { "Solid Weightstone", 135258 },
    [503] = { "Rockbiter Weapon", 136086 },
    [523] = { "Flametongue Weapon", 135814 },
    [524] = { "Frostbrand Weapon", 135847 },
    [525] = { "Windfury Weapon", 136018 },
    [603] = { "Crippling Poison II", 132274 },
    [623] = { "Instant Poison IV", 132273 },
    [624] = { "Instant Poison V", 132273 },
    [625] = { "Instant Poison VI", 132273 },
    [626] = { "Deadly Poison III", 132290 },
    [627] = { "Deadly Poison IV", 132290 },
    [643] = { "Mind-numbing Poison III", 136066 },
    [683] = { "Rockbiter Weapon", 136086 },
    [703] = { "Wound Poison", 134197 },
    [704] = { "Wound Poison II", 134197 },
    [705] = { "Wound Poison III", 134197 },
    [706] = { "Wound Poison IV", 134197 },
    [1643] = { "Dense Sharpening Stone", 135252 },
    [1663] = { "Rockbiter Weapon", 136086 },
    [1664] = { "Rockbiter Weapon", 136086 },
    [1665] = { "Flametongue Weapon", 135814 },
    [1666] = { "Flametongue Weapon", 135814 },
    [1667] = { "Frostbrand Weapon", 135847 },
    [1668] = { "Frostbrand Weapon", 135847 },
    [1669] = { "Windfury Weapon", 136018 },
    [1703] = { "Dense Weightstone", 135259 },
    [1803] = { "Lesser Firestone", 134085 },
    [1823] = { "Firestone", 134085 },
    [1824] = { "Greater Firestone", 134085 },
    [1825] = { "Major Firestone", 134085 },
    [2506] = { "Elemental Sharpening Stone", 135228 },
    [2623] = { "Minor Wizard Oil", 134711 },
    [2624] = { "Minor Mana Oil", 134878 },
    [2625] = { "Lesser Mana Oil", 134879 },
    [2626] = { "Lesser Wizard Oil", 134725 },
    [2627] = { "Wizard Oil", 134726 },
    [2628] = { "Brilliant Wizard Oil", 134727 },
    [2629] = { "Brilliant Mana Oil", 134722 },
    [2630] = { "Deadly Poison V", 132290 },
    [2684] = { "Consecrated Sharpening Stone", 135249 },
    [2685] = { "Blessed Wizard Oil", 134806 },
    [7098] = { "Blackfathom Sharpening Stone", 134417 },
    [7254] = { "Sebacious Poison", 132108 },
    [7255] = { "Numbing Poison", 132098 },
    [7256] = { "Atrophic Poison", 132100 },
    [7542] = { "Occult Poison I", 135935 },
    [7566] = { "Frostbrand Weapon", 135847 },
    [7567] = { "Flametongue Weapon", 135814 },
    [7568] = { "Rockbiter Weapon", 136086 },
    [7569] = { "Windfury Weapon", 136018 },
    [7602] = { "Conductive Shield Coating", 134722 },
    [7644] = { "Magnificent Trollshine", 134876 },
    [7651] = { "Occult Poison II", 135935 },
    [8059] = { "Spellstone", 134131 },
    [8060] = { "Greater Spellstone", 134131 },
    [8061] = { "Major Spellstone", 134131 },
    [8698] = { "Imbue Chillknife", 4549168 },
    [8700] = { "Imbue Lesser Flame", 4549170 },
    [8706] = { "Imbue Baleflame", 4549170 },
    [8707] = { "Imbue Spark", 4549170 },
    [8708] = { "Imbue Striking", 4549172 },
    [8709] = { "Imbue Frost", 4549168 },
    [8710] = { "Imbue Iceknife", 4549168 },
    [8711] = { "Imbue Accuracy", 4549172 },
    [8712] = { "Imbue Quickening", 4549172 },
    [8713] = { "Imbue Flame", 4549170 },
    [8714] = { "Imbue Balefrost", 4549168 },
    [8715] = { "Imbue Manablade", 4549172 },
    [8716] = { "Imbue Greater Flame", 4549170 },
    [8717] = { "Imbue Greater Frost", 4549168 },
    [8718] = { "Imbue Precision", 4549172 },
}

-- Inventory slot: Enum.WeaponSlot.
local HANDS = { [16] = 0, [17] = 1 }
local PERMANENT = 1 -- Enum.ItemEnchantType.Permanent
-- What's on each hand as last read: false for nothing, else { id, ends (nil
-- with no timer), total }. One the game won't say about keeps what it was, so
-- in a fight the time left runs on from the last answer. And whether each
-- holds a weapon (Armed), kept the same way; never read counts as one.
local hands, armed = {}, {}

-- The game's three ways of asking, each giving the hand's enchant and its
-- seconds left, false for none, or nil when it won't say (a secret answer):
-- Prep's Hands.lua found Forever's imbues may show in one and not another.
local ENCHANT_SOURCES = {
    { function() return type(C_PaperDollInfo) == "table" and C_PaperDollInfo.GetTemporaryEnchantmentInfo end, function(api, slot)
        local info = api(slot)
        if not Open(info) then return nil end
        if info == nil then return false end
        local id, ms, timed = info.enchantID, info.remainingTimeMs, info.hasExpirationTime
        if not (Open(id) and Open(ms) and Open(timed)) or type(id) ~= "number" then return nil end
        return id, timed ~= false and type(ms) == "number" and ms / 1000 or nil
    end },
    { function() return type(C_Item) == "table" and C_Item.GetWeaponEnchantInfo end, function(api, slot)
        local list = api(HANDS[slot])
        if not Open(list) or type(list) ~= "table" then return nil end
        for _, each in pairs(list) do
            local has, kind = each.hasEnchant, each.enchantType
            if not (Open(has) and Open(kind)) then return nil end
            if has == true and kind ~= PERMANENT then
                local id, ms = each.enchantID, each.timeLeft
                if not (Open(id) and Open(ms)) or type(id) ~= "number" then return nil end
                return id, type(ms) == "number" and ms / 1000 or nil
            end
        end
        return false
    end },
    { function() return GetWeaponEnchantInfo end, function(api, slot)
        local values, at = { api() }, slot == 16 and 0 or 4
        local has, ms, id = values[at + 1], values[at + 2], values[at + 4]
        if not Open(has) then return nil end
        if not has then return false end
        if not (Open(ms) and Open(id)) or type(id) ~= "number" then return nil end
        return id, type(ms) == "number" and ms / 1000 or nil
    end },
}

-- A hand's enchant and seconds left from the first way that names one; false
-- only when one said none and none held back; nil when the game won't say.
local function ReadHand(slot)
    local none, held = false, false
    for _, source in ipairs(ENCHANT_SOURCES) do
        local api = source[1]()
        if api then
            local ok, id, left = pcall(source[2], api, slot)
            if ok and type(id) == "number" then return id, left end
            if ok and id == false then none = true else held = true end
        end
    end
    if none and not held then return false end
    return nil
end

-- Whether a hand holds a weapon, which something can go on: true or false,
-- or nil while the game won't say. Nothing there, a shield or a
-- held-in-off-hand item isn't one (a fishing pole is).
local function Armed(slot)
    if type(GetInventoryItemID) ~= "function" then return nil end
    local id = GetInventoryItemID("player", slot)
    if not Open(id) then return nil end
    if id == nil then return false end
    local info = C_Item and C_Item.GetItemInfoInstant
    if type(info) ~= "function" then return nil end
    local ok, _, _, _, _, _, class = pcall(info, id)
    if not (ok and Open(class)) or type(class) ~= "number" then return nil end
    return class == (Enum and Enum.ItemClass and Enum.ItemClass.Weapon or 2)
end

-- Whether a Buffs bar has an entry that's a weapon enchant.
function F:HasEnchants(bar)
    return bar ~= nil and bar.imbues ~= nil and next(bar.imbues) ~= nil
end

-- Reads both hands. (A timer read a moment later is the same one, not news.)
function F:ReadEnchants()
    local now = GetTime()
    for slot in pairs(HANDS) do
        local id, left = ReadHand(slot)
        if id == false then
            hands[slot] = false
        elseif id then
            local old, ends = hands[slot], left and now + left or nil
            if not old or old.id ~= id or (old.ends == nil) ~= (ends == nil) or (ends and math.abs(old.ends - ends) > 2) then
                hands[slot] = { id = id, ends = ends, total = left }
            end
        end
        local weapon = Armed(slot)
        if weapon ~= nil then armed[slot] = weapon end
    end
end

-- Whether one of these enchants is on a hand (any at all on a hand of its
-- own: ids.hands, a hand entry's), and when the soonest to end ends, how
-- long it had when read, which it is and on which hand. bare: an entry of
-- hands alone (ids.handsOnly) with no weapon in any of them, so nothing's
-- missing.
local function EnchantOn(ids)
    local now, on, ends, total, id, at = GetTime(), false, nil, nil, nil, nil
    local bare = ids.handsOnly == true
    for slot in pairs(HANDS) do
        local hand, own = hands[slot], ids.hands ~= nil and ids.hands[slot] == true
        if hand and (own or ids[hand.id]) and (not hand.ends or hand.ends > now) and (not on or (hand.ends and (not ends or hand.ends < ends))) then
            on, ends, total, id, at = true, hand.ends, hand.total, hand.id, slot
        end
        if own and armed[slot] ~= false then bare = false end
    end
    return on, ends, total, id, at, bare and not on
end

-- A hand entry's spot shows what's on that hand: the enchant's icon and
-- name, or its own while nothing is (as laid out: holder.restIcon and
-- restName). Each only set as it changes. The addon's own texture and text,
-- so fine in a fight.
local UNKNOWN_ICON = 134400 -- the question mark, if the weapon's own icon can't be had
local function Which(holder, id, slot)
    local icon, name = holder.restIcon, holder.restName
    if id then
        local known = ns.HAND_ENCHANTS[id]
        if known then
            name, icon = known[1], known[2]
        else
            -- (Its texture may be secret: only tested once Open says it isn't.)
            local texture
            if type(GetInventoryItemTexture) == "function" then texture = GetInventoryItemTexture("player", slot) end
            name, icon = "Weapon enchant", Open(texture) and texture or UNKNOWN_ICON
        end
    end
    if holder.whichIcon ~= icon then
        holder.whichIcon = icon
        holder.icon:SetTexture(icon)
    end
    if holder.whichName ~= name then
        holder.whichName = name
        holder.label:SetText(name)
    end
end

-- For /ccm debug: what a weapon enchant entry last read on your hands.
function F:EnchantReport(bar, i)
    local ids = bar and bar.imbues and bar.imbues[i]
    if not ids then return "" end
    local on, _, _, id, _, bare = EnchantOn(ids)
    return " | weapon enchant " .. (on and ("on, " .. tostring(id)) or bare and "none, no weapon" or "missing")
end

-- Seconds until an enchant on a hand runs out, or nil with none running.
function F:NextEnchantEnd()
    local now, soonest = GetTime(), nil
    for slot in pairs(HANDS) do
        local hand = hands[slot]
        if hand and hand.ends and hand.ends > now and (not soonest or hand.ends < soonest) then soonest = hand.ends end
    end
    return soonest and soonest - now or nil
end

-- A spot's own time left, as an aura's icon draws it. Made the first time it's wanted.
local function EnchantParts(holder)
    if holder.enchant then return holder.enchant end
    local cooldown = CreateFrame("Cooldown", nil, holder, "CooldownFrameTemplate")
    cooldown:SetAllPoints(holder.icon)
    cooldown:SetSwipeTexture(Style.FLAT)
    cooldown:SetReverse(true)
    Style:CooldownLook(cooldown)
    cooldown:SetDrawBling(false)
    local count = holder:CreateFontString(nil, "OVERLAY", "NumberFontNormal")
    count:SetPoint("BOTTOMRIGHT", -1, 1)
    holder.enchant = { cooldown = cooldown, count = count }
    return holder.enchant
end

-- Each weapon enchant's spot lit or greyed, with its time left; a spot that
-- was one and now holds something else goes back as it was. The addon's own
-- textures and cooldown, so fine in a fight.
function F:PaintEnchants(bar)
    if not (bar and bar.holders) then return end
    local packed = self:Packed(bar.data)
    for i = 1, ns.BUFF_SLOTS do
        local holder, ids = bar.holders[i], bar.imbues[i]
        if ids then
            local on, ends, total, id, slot, bare = EnchantOn(ids)
            holder.icon:SetDesaturated(not on)
            holder.icon:SetAlpha(on and 1 or .45)
            -- (Glow when missing: over it, unlike an aura's icon, so it goes;
            -- and never on a hand with no weapon, where nothing's missing.)
            if holder.glowHost then holder.glowHost:SetAlpha((on or bare) and 0 or 1) end
            holder.enchantLit = on
            if ids.hands then Which(holder, on and id, slot) end
            local parts = EnchantParts(holder)
            -- A packed bar's spot isn't scaled as its slot is, so its own size.
            Fit(parts, packed and ns.IconSize(bar.data) or holder.size or BASE, holder.showTimer ~= false, holder.look)
            -- Warn at, on a hand entry: its countdown red from its seconds
            -- left, as an aura's is. (Not yet on a named enchant's: parked.)
            Style:WarnText(parts.cooldown, ids.hands and bar.warns[i] or nil)
            if on and ends then
                parts.cooldown:SetCooldown(ends - total, total)
            else
                parts.cooldown:Clear()
            end
        elseif holder.enchantLit ~= nil then
            holder.enchantLit = nil
            holder.icon:SetDesaturated(true)
            holder.icon:SetAlpha(.45)
            if holder.glowHost then holder.glowHost:SetAlpha(1) end
            if holder.enchant then
                holder.enchant.cooldown:Clear()
                Style:WarnText(holder.enchant.cooldown, nil)
            end
        end
    end
end

function F:Create(bar)
    bar.holders, bar.slotIDs, bar.applied, bar.appliedGroups, bar.groups = {}, {}, {}, {}, 0
    bar.groupParts, bar.names, bar.up, bar.spots, bar.only, bar.imbues = {}, {}, {}, {}, {}, {}
    bar.tickPaces, bar.tickShows, bar.groupTicks, bar.looks, bar.bare = {}, {}, {}, {}, {}
    bar.warns, bar.appliedWarns, bar.actives = {}, {}, {}
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
    -- Warn at: each entry's edge slot, made now with the rest (never later),
    -- off until its entry warns. Where the game can't, none: the countdown
    -- still turns red. A slot the game turns down leaves the bar as it is.
    if not (ok and bar.container and CanMark()) then return end
    local made, why = pcall(function()
        for i = 1, ns.BUFF_SLOTS do
            F.Add(bar.container, "AddAuraSlot", "w" .. i, aura.filter, { initializeFrame = F.Guard(MarkLook(bar.holders[i])) })
            bar.container:SetAuraSlotEnabled("w" .. i, false)
        end
    end)
    bar.marks = made or nil
    if not made and not F.markError then F.markError = tostring(why) end
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
-- with Only show missing off and no buff ticked Only when missing, or your
-- bars off, and only the entries that show while missing are read.
-- bar.unread says the game didn't answer for one or more (your buffs still
-- secret as a fight ends, say), so the bars read again a moment later
-- (Bars.lua, Again).
function F:Check(bar)
    bar.unread = nil
    local watches = self:Watches(bar.key, bar.data) and ns.Bars:Enabled()
    local enchants = self:HasEnchants(bar)
    if not watches then
        bar.upBy = nil
        if not enchants then return false end
    end
    -- A packed bar with a weapon enchant centres its whole row (Lead), so it
    -- reads which of the game's packed icons are up too.
    local counting = enchants and self:Packed(bar.data) and ns.Bars:Enabled()
    local readable = (watches or counting) and Readable()
    local last, now, up, changed = bar.upBy or {}, {}, bar.up, false
    for i = 1, bar.count do
        local name, on = bar.names[i], nil
        -- (A weapon enchant is on your weapon, and answered from your hands;
        -- a hand with no weapon in it has nothing missing: bar.bare.)
        if bar.imbues[i] then
            local lit, _, _, _, _, bare = EnchantOn(bar.imbues[i])
            on = lit
            if (bar.bare[i] == true) ~= bare then changed = true end
            bar.bare[i] = bare or nil
        elseif counting or (watches and self:Hides(bar, i)) then
            if readable then on = OnYou(bar.slotIDs[i]) end
            if on == nil then on, bar.unread = last[name], true end
            now[name] = on
        end
        on = on == true
        if (up[i] == true) ~= on then changed = true end
        up[i] = on
    end
    for i = bar.count + 1, #up do up[i] = nil end
    bar.upBy = (watches or counting) and now or nil
    return changed
end

-- Whether entry i has a spot on the bar now: always with missing ones
-- greyed; with Only show missing, or ticked Only when missing, while it's
-- missing, and every one while the bars are arranged (unlocked, or in Edit
-- Mode), so the bar can be placed and sized with them all. A missing one's
-- slot stays on, so a buff cast in a fight draws over its greyed spot.
local function Spot(bar, i)
    if ns.Bars:Arranging() then return true end
    -- A hand with no weapon in it, shown only while missing: it isn't.
    if bar.bare and bar.bare[i] and F:Hides(bar, i) then return false end
    -- A weapon enchant on a packed bar shows as the packed icons do: while it's on.
    if bar.imbues[i] and F:Packed(bar.data) and not F:Hides(bar, i) then return bar.up[i] == true end
    return not (F:Hides(bar, i) and bar.up[i])
end

-- Whether entry i is shown in a fixed slot and spot: every entry unless
-- packed; on a packed bar, the ones ticked Only when missing and the weapon
-- enchants (the rest are the game's packed icons).
local function Own(bar, i, packed)
    return not packed or bar.only[i] == true or bar.imbues[i] ~= nil
end

-- A packed bar's spots (Only when missing) in one row, side by side: from
-- the edge it grows from, or centred as if alone, and the game's packed
-- icons just past them (bar.leadPoint, bar.leadX: the container's point and
-- how far along from the bar's, F:Apply). With none, the icons sit as
-- before: centred, or from that edge.
local function Lead(bar, spots)
    local data = bar.data
    local side = data.grow == "left" and "RIGHT" or data.grow == "right" and "LEFT" or "CENTER"
    local n = #spots
    bar.leadPoint, bar.leadX = side, 0
    if n == 0 then return end
    local size, spacing = ns.IconSize(data), data.spacing
    local step = size + spacing
    local slots = bar.count > 0 and bar.count or 3
    local width = slots * size + (slots - 1) * spacing
    local corner = data.wrap == "up" and "BOTTOMLEFT" or "TOPLEFT"
    local from
    if data.grow == "left" then
        from = width - n * step + spacing
        bar.leadPoint, bar.leadX = "RIGHT", -n * step
    elseif data.grow == "right" then
        from = 0
        bar.leadPoint, bar.leadX = "LEFT", n * step
    else
        -- With a weapon enchant, the packed icons up beside it count, so the
        -- whole row is centred (F:Check reads them; in a fight the row stays
        -- where it was and a buff gained then adds to the right, until it ends).
        local others = 0
        if F:HasEnchants(bar) then
            for i = 1, bar.count do
                if not Own(bar, i, true) and bar.up[i] then others = others + 1 end
            end
        end
        from = (width - ((n + others) * step - spacing)) / 2
        bar.leadPoint, bar.leadX = "LEFT", from + n * step
    end
    -- Growing left, the first one on the right, as fixed spots go.
    for k, holder in ipairs(spots) do
        local at = data.grow == "left" and (n - k) or (k - 1)
        holder:ClearAllPoints()
        holder:SetPoint(corner, bar, corner, from + at * step, 0)
    end
end

-- Shows the fixed spots that show and hides the rest (on a packed bar, all
-- but those ticked Only when missing), and lists those shown in your order
-- (bar.spots) for the bar to place side by side. Out of combat only, as
-- they carry the slots.
function F:Spots(bar)
    local packed, spots = self:Packed(bar.data), {}
    for i = 1, bar.count do
        local holder = bar.holders[i]
        local shown = Own(bar, i, packed) and Spot(bar, i)
        holder:SetShown(shown)
        if shown then spots[#spots + 1] = holder end
    end
    bar.spots = spots
    if packed then
        Lead(bar, spots)
    else
        bar.leadPoint, bar.leadX = nil, 0
    end
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
    local count, packed = 0, self:Packed(data)
    local picks, glows = ns.MissingPicks(bar.key), ns.GlowMissing(bar.key)
    local counts = ns.BAR_KIND[bar.key] == "debuff" and ns.CountTicks(bar.key) or {}
    -- Only when missing: the Buffs bar's, and not with Only show missing.
    local flags = self:Flagged(bar.key, data) and ns.OnlyWhenMissing(bar.key) or {}
    local warns = ns.WarnAt(bar.key)
    -- Glow while active: a Buffs bar's own.
    local actives = ns.BAR_KIND[bar.key] == "buff" and ns.GlowActive(bar.key) or {}
    -- A packed bar's slots sit in its container, scaled with the packed
    -- icons, so their numbers are sized as those icons' are.
    local fit = packed and BASE or size
    local weapons = ns.BAR_KIND[bar.key] == "buff"
    for _, group in ipairs(ns.Bars:Units(bar.key)) do
        local ids, entry, picked, glow, yours, only = {}, nil, nil, false, {}, false
        local active = false -- (any of yours in it ticked Glow while active)
        -- Weapon enchants: every one of yours in it is one (joined with a
        -- buff, it's the buff's as before: nothing tells them apart in a fight).
        -- A hand entry is any enchant on its hand (enchants.hands).
        local enchants, allEnchants, named = {}, weapons, false
        for _, name in ipairs(group) do
            local found = ns.Spells:Find(name)
            if found and found.ids and ns.Spells:ForMe(name, bar.key) then
                entry = entry or found
                if picks[name] and not picked then picked = found end -- the first picked, as B:Picked
                glow = glow or glows[name] == true
                only = only or flags[name] == true
                active = active or actives[name] == true
                yours[#yours + 1] = name
                for _, id in ipairs(found.ids) do ids[id] = true end
                local list = ENCHANTS[found.name]
                if found.hand and weapons then
                    enchants.hands = enchants.hands or {}
                    enchants.hands[found.hand] = true
                elseif list then
                    named = true
                    for _, id in ipairs(list) do enchants[id] = true end
                else
                    allEnchants = false
                end
            end
        end
        -- (Hands alone: one with no weapon in it has nothing missing.)
        if enchants.hands and not named then enchants.handsOnly = true end
        -- Its tick count: the counted debuffs' pace, and for a joined icon
        -- with others at another pace, the lengths it shows on (B:IconTicks).
        local pace, shows = ns.Bars:IconTicks(yours, counts)
        -- A joined icon shows its picked entry (on the bar's page), faded,
        -- while none is up; else its first of yours.
        entry = picked or entry
        -- (A hand entry has no spells of its own: its hand is what it watches.)
        if entry and (next(ids) or enchants.hands) and count < ns.BUFF_SLOTS then
            count = count + 1
            local holder = bar.holders[count]
            -- Its own size (settings per spell; a joined icon: the first of
            -- yours with one), on a bar whose spots are fixed: a packed bar's
            -- icons are the game's, all one size (its spots too: F:Spots).
            local own, sized = size, packed
            for _, name in ipairs(yours) do
                if not sized and ns.OwnSize(bar.key, name) then own, sized = ns.IconSizeFor(bar.key, name, size), true end
            end
            holder:SetSize(own, own)
            holder.ownSize = own ~= size and own or nil
            -- Its countdown in its entry's own look (settings per spell; a
            -- joined icon: the first of yours with one).
            local look = ns.SpellLookFor(yours)
            local fits = packed and fit or own
            holder.size, holder.showTimer, holder.look = fits, data.showTimer, look
            bar.looks[count] = look
            if holder.slot then Fit(holder.slot, fits, data.showTimer, look) end
            -- (What a hand entry shows while nothing is on it: F:PaintEnchants.)
            local text = #group > 1 and (entry.name .. " +" .. (#group - 1)) or entry.name
            holder.icon:SetTexture(entry.icon)
            holder.label:SetWidth(own + spacing)
            holder.label:SetText(text)
            holder.restIcon, holder.restName, holder.whichIcon, holder.whichName = entry.icon, text, entry.icon, text
            -- (A packed bar offers no names: its icons have no spot for one.)
            holder.label:SetShown(data.showNames and not packed)
            MissingGlow(holder, glow, own)
            bar.slotIDs[count] = ids
            bar.names[count] = table.concat(group, "+")
            bar.tickPaces[count], bar.tickShows[count] = pace, shows
            bar.only[count] = only or nil
            bar.imbues[count] = allEnchants and next(enchants) and enchants or nil
            bar.bare[count] = nil -- (read below: F:Check)
            -- Glow while active: not on an icon shown only while it's missing
            -- (none while it's up), nor a weapon enchant's own spot.
            bar.actives[count] = active and not (only or self:OnlyMissing(data) or bar.imbues[count]) or nil
            -- Warn at: the first of yours with one, unless it shows only
            -- while it's missing (it has no icon while it's up).
            local warn
            for _, name in ipairs(yours) do
                warn = warn or warns[name]
            end
            bar.warns[count] = not (only or self:OnlyMissing(data)) and warn or nil
        end
    end
    for i = count + 1, ns.BUFF_SLOTS do
        bar.holders[i]:Hide()
        MissingGlow(bar.holders[i], false)
        bar.slotIDs[i], bar.names[i], bar.tickPaces[i], bar.tickShows[i], bar.only[i] = nil, nil, nil, nil, nil
        bar.looks[i], bar.holders[i].look, bar.warns[i], bar.holders[i].ownSize = nil, nil, nil, nil
        bar.imbues[i], bar.bare[i], bar.actives[i] = nil, nil, nil
    end
    for _, parts in ipairs(bar.groupParts) do
        parts.cooldown:SetHideCountdownNumbers(not data.showTimer)
        if parts.index then GroupFont(parts, bar.looks[parts.index]) end
    end
    bar.count = count
    -- Which are on you, then the spots that show. (Packed icons line up
    -- from the bar's centre, or from the edge the bar grows away from, past
    -- any spots: F:Apply. Fixed spots are placed in rows by the bar.)
    if self:HasEnchants(bar) then self:ReadEnchants() end
    self:Check(bar)
    self:Spots(bar)
    self:Apply(bar)
    self:UpdateTarget(bar)
    self:LowTime(bar)
    self:PaintEnchants(bar)
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
        AddGroup(container, "self", "HARMFUL|PLAYER", { initializeFrame = F.Guard(GroupLook(bar)), maxFrameCount = SELF_MAX,
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
    -- (An extra bar you don't have now: everything off, your debuffs on you too.)
    local on = ns.Bars:Enabled() and ns.HasBar(bar.key)
    local packed = self:Packed(data)
    local scale = packed and ns.IconSize(data) / BASE or 1
    -- Packed icons line up from the bar's centre, or from the edge the bar
    -- grows away from; past the spots of any buffs ticked Only when missing
    -- (F:Spots), the offset in the container's own size, as it's scaled.
    local side = data.grow == "left" and "RIGHT" or data.grow == "right" and "LEFT" or "CENTER"
    local point, x = bar.leadPoint or side, bar.leadX or 0
    local where = x == 0 and point or (point .. "|" .. x .. "|" .. scale)
    if bar.containerSide ~= where then
        bar.containerSide = where
        container:ClearAllPoints()
        if x == 0 then container:SetPoint(point, bar, point) else container:SetPoint(point, bar, point, x / scale, 0) end
    end
    for i = 1, ns.BUFF_SLOTS do
        -- Fixed slots: every entry's, or on a packed bar those ticked Only
        -- when missing.
        local ids = on and Own(bar, i, packed) and bar.slotIDs[i] or nil
        -- Only show missing or Only when missing: a buff on you has no spot,
        -- and its slot is off. So is a hand entry's: it has no spells.
        if ids and (next(ids) == nil or not Spot(bar, i)) then ids = nil end
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
    -- Warn at: the edge slots, on the same spells as their entry's fixed
    -- spot, for a warned entry with a spot that stays (not on a packed bar,
    -- nor one shown only while it's missing).
    if bar.marks then
        for i = 1, ns.BUFF_SLOTS do
            local ids = on and not packed and bar.warns[i] and bar.holders[i].mark and not self:Hides(bar, i)
                and bar.slotIDs[i] or nil
            if ids and next(ids) == nil then ids = nil end
            local signature = Signature(ids)
            if bar.appliedWarns[i] ~= signature then
                bar.appliedWarns[i] = signature
                local key = "w" .. i
                if ids then
                    container:SetAuraSlotCandidateFilters(key, Filters(bar, ids))
                    container:SetAuraSlotEnabled(key, true)
                else
                    container:SetAuraSlotEnabled(key, false)
                end
            end
        end
    end
    -- Groups are made as they're first needed; the game keeps them after that.
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
        -- (Not one ticked Only when missing: its own slot shows it. Nor a
        -- weapon enchant: its own spot.)
        local ids = on and packed and bar.only[i] ~= true and not bar.imbues[i] and bar.slotIDs[i] or nil
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
    self:Warns(bar)
    self:Actives(bar)
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
    local colourKey = ns.CountColourKey(data) -- a named colour, or Custom's own
    local look = data.tickAt .. "|" .. tostring(data.tickEdge) .. "|" .. font .. "|" .. colourKey .. "|" .. Shows(shows)
    if ticks.look == look then return end
    local at = INSET[data.tickAt] or INSET.TOPLEFT
    local point = INSET[data.tickAt] and data.tickAt or "TOPLEFT"
    local colour = ns.CountColour(colourKey)
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

-- Warn at: each entry's countdown red from its seconds (its fixed slot's and
-- its packed group's icons), and its edge slot's rule: the edge, sized round
-- its spot, under its seconds and nothing from them; nothing at all while it
-- doesn't warn or has no spot. Out of combat only (F:Apply); each only sent
-- as it changes, and a rule the game turns down leaves no edge.
function F:Warns(bar)
    local packed = self:Packed(bar.data)
    for i = 1, ns.BUFF_SLOTS do
        local holder, warn = bar.holders[i], bar.warns[i]
        if holder.slot then Style:WarnText(holder.slot.cooldown, warn) end
        local mark = holder.mark
        if mark then
            local seconds = not packed and warn or nil
            local size = math.floor((holder.size or BASE) * MARK_SPREAD + .5)
            local rule = seconds and (seconds .. ":" .. size) or ""
            if mark.rule ~= rule then
                local ok = pcall(function()
                    mark.formatter:ClearBreakpoints()
                    if seconds then
                        mark.formatter:AddBreakpoint({ threshold = 0, format = Edge(size) })
                        mark.formatter:AddBreakpoint({ threshold = seconds, format = "" })
                    else
                        mark.formatter:AddBreakpoint({ threshold = 0, format = "" })
                    end
                end)
                mark.rule = ok and rule or nil -- (turned down: tried again as it next changes)
            end
        end
    end
    for _, parts in ipairs(bar.groupParts) do
        if parts.index then Style:WarnText(parts.cooldown, bar.warns[parts.index]) end
    end
end

-- Glow while active: each icon's glow shown for its entry or hidden (fixed
-- slot i and packed group i are entry i's: bar.actives, F:Layout), the loop
-- with it in the Proc glow style, sized round the icon (a packed icon is
-- drawn at BASE, then scaled), as big as Glow size says (spread: the loop's,
-- as a share of the icon; width: the edge's). Out of a fight only, as the
-- icons are the game's: one changed in a fight waits for it to end
-- (F:Apply). Each is only set as it changes.
local function Lit(active, on, size, looping, spread, width)
    if not active then return end
    if active.on ~= on then
        active.on = on
        active.frame:SetShown(on)
    end
    if active.strips and active.width ~= width then
        active.width = width
        ns.EdgeWidth(active.strips, width)
    end
    local loop = active.loop
    if not loop then return end
    if active.looping ~= looping then
        active.looping = looping
        loop:SetShown(looping)
    end
    local across = size * spread
    if active.spread ~= across then
        active.spread = across
        loop:SetSize(across, across)
    end
end

-- Glow size (a percent of the usual size): how far the loop spreads, as a
-- share of the icon (only its part past the icon grows or shrinks), and the
-- edge's width, never under 1. At 100% both as they always were.
local function ActiveSize(percent)
    return 1 + (ACTIVE_SPREAD - 1) * percent / 100, math.max(1, math.floor(ns.EDGE_WIDTH * percent / 100 + .5))
end

function F:Actives(bar)
    if not (bar and bar.holders and bar.actives) then return end
    if InCombatLockdown() then
        bar.pending = true
        return
    end
    local looping = ns.Get("readyGlow") ~= "edge"
    local spread, width = ActiveSize(ns.GlowActiveSize())
    for i = 1, ns.BUFF_SLOTS do
        local holder = bar.holders[i]
        if holder.slot then Lit(holder.slot.active, bar.actives[i] == true, holder.size or BASE, looping, spread, width) end
    end
    -- A packed icon's edge is scaled with its container: kept at least 1
    -- wide on screen, as a fixed slot's is, but never past the usual width.
    local packedWidth = math.max(width, math.min(ns.EDGE_WIDTH, 1 / (bar.appliedScale or 1)))
    for _, parts in ipairs(bar.groupParts) do
        Lit(parts.active, parts.index ~= nil and bar.actives[parts.index] == true, BASE, looping, spread, packedWidth)
    end
end

-- For /ccm debug: whether entry i glows while it's up, and whether the game
-- took the loop (else the edge alone).
function F:ActiveReport(bar, i)
    if not (bar and bar.actives and bar.actives[i]) then return "" end
    local made, looped = false, false
    local function See(active)
        if active then made, looped = true, looped or active.loop ~= nil end
    end
    local slot = bar.holders[i].slot
    See(slot and slot.active)
    for _, parts in ipairs(bar.groupParts) do
        if parts.index == i then See(parts.active) end
    end
    local how = not made and "no icon yet" or not looped and "edge only, the game took no loop"
        or ns.Get("readyGlow") == "edge" and "edge (Ready glow)" or "edge and loop"
    -- And its Glow size, when it isn't the usual one.
    local percent = ns.GlowActiveSize()
    return " | glow while active: " .. how .. (percent ~= ns.GLOW_ACTIVE_SIZE[3] and (", size " .. percent .. "%") or "")
end

-- Out of a fight, a warned buff's spot glows (the Look page's ready glow)
-- from its seconds left, over the game's icon and clear of its edge; the
-- glow on top of the bar's icons (the aura container sits 5 above the bar).
local function LowGlow(bar, holder, on)
    local host = holder.lowHost
    if not on then
        if host then ns.SetGlow(host, false) end
        return
    end
    if not host then
        host = CreateFrame("Frame", nil, holder)
        host:SetPoint("CENTER")
        host:EnableMouse(false)
        host.top, host.glows = host, {}
        holder.lowHost = host
    end
    host:SetFrameLevel(bar:GetFrameLevel() + 15)
    local size = holder.size or BASE
    host:SetSize(size, size)
    ns.UseGlow(host)
    ns.SetGlow(host, true)
end

-- Seconds left on an entry's buff on you, out of a fight: the soonest to
-- end of its spells that are on you and run out (one that doesn't run out
-- has no countdown to warn on). unknown: the game wouldn't say for one (a
-- secret answer, or its time kept secret).
local function TimeLeft(ids)
    local auras = C_UnitAuras
    local get = type(auras) == "table" and auras.GetPlayerAuraBySpellID
    if type(get) ~= "function" then return nil, false end
    local now, left, unknown = GetTime(), nil, false
    for id in pairs(ids or {}) do
        local ok, aura = pcall(get, id)
        if not ok or not Open(aura) then
            unknown = true
        elseif type(aura) == "table" then
            local ends = aura.expirationTime
            if not Open(ends) then
                unknown = true
            elseif type(ends) == "number" and ends > 0 then
                local this = ends - now
                if not left or this < left then left = this end
            end
        end
    end
    return left, unknown
end

-- Whether a Buffs bar (key: Buffs unless given, or Buffs 2) reads your
-- warned buffs' time left: with spots that stay (missing ones greyed), and
-- any buff warned.
function F:LowWatch(data, key)
    return data ~= nil and self:Fixed(data) and next(ns.WarnAt(key or "buff")) ~= nil
end

-- The low-time glows on the Buffs bar's warned spots, read out of a fight:
-- lit from the entry's seconds left until it's recast, ends or a fight
-- starts (fighting: all out, the game's red numbers and edge take over).
-- One with longer left sets one timer for the bar, for the soonest to cross
-- (bar.lowDue: when); a later read for another moment stands it down, one
-- for the same moment (your buffs changing often) leaves it be, so no
-- timers pile up. bar.lowUnread: the game didn't answer for one, so the
-- bars read again a moment later (Bars.lua, Again).
local LOW_LATE = .05 -- the timer's margin past the moment, so the read finds it under
function F:LowTime(bar, fighting)
    if not (bar and bar.holders and ns.BAR_KIND[bar.key] == "buff" and bar.warns) then return end
    local watch = not fighting and self:LowWatch(bar.data, bar.key) and ns.Bars:Enabled()
    local readable = watch and Readable()
    local soonest, unread = nil, false
    -- Whether left (seconds) is under warn's; else when it will be, the soonest kept.
    local function Under(left, warn)
        if left and left <= warn then return true end
        if left and (not soonest or left - warn < soonest) then soonest = left - warn end
        return false
    end
    for i = 1, ns.BUFF_SLOTS do
        local holder, warn, lit = bar.holders[i], bar.warns[i], false
        if watch and warn and i <= (bar.count or 0) and holder:IsShown() then
            local imbue = bar.imbues and bar.imbues[i]
            if imbue and imbue.hands then
                -- A hand entry's time left is your hands', read as they change.
                local on, ends = EnchantOn(imbue)
                lit = Under(on and ends and ends - GetTime() or nil, warn)
            elseif imbue then
                -- (A named weapon enchant has no aura to read: no glow, as before.)
                lit = false
            elseif readable then
                local left, unknown = TimeLeft(bar.slotIDs[i])
                if unknown then unread = true end
                lit = Under(left, warn)
            else
                unread = true
            end
        end
        LowGlow(bar, holder, lit)
    end
    bar.lowUnread = unread or nil
    local due = soonest and GetTime() + soonest + LOW_LATE or nil
    if due and bar.lowDue and math.abs(bar.lowDue - due) < .1 then return end
    bar.lowTimer, bar.lowDue = (bar.lowTimer or 0) + 1, due
    if due then
        local timer = bar.lowTimer
        C_Timer.After(soonest + LOW_LATE, function()
            if bar.lowTimer ~= timer then return end
            bar.lowDue = nil
            F:LowTime(bar)
        end)
    end
end

-- For /ccm debug: entry i's warning, if it has one.
function F:WarnReport(bar, i)
    local warn = bar and bar.warns and bar.warns[i]
    if not warn then return "" end
    local holder = bar.holders[i]
    local edge = not bar.marks and "none (the game can't)" or self:Packed(bar.data) and "none (packed)"
        or (bar.appliedWarns[i] or "") ~= "" and ("on, rule " .. tostring(holder.mark and holder.mark.rule)) or "off"
    local glow = holder.lowHost and holder.lowHost.glow
    return (" | warn at %ds: red numbers %s, edge %s, low glow %s"):format(warn,
        holder.slot and tostring(Style:Warned(holder.slot.cooldown) == warn) or "no icon yet", edge,
        ns.BAR_KIND[bar.key] ~= "buff" and "not on Debuffs" or tostring(glow ~= nil and glow:IsShown()))
end
