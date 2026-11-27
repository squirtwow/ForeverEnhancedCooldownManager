-- DoTs (More in /ccm): the damage over time spells you have running on your
-- target, with the damage they still have to deal marked on its health bar.
-- DotsBand.lua draws the band, the bright line and the skull; DotsPage.lua is
-- the page. This file is the work: which spells are DoTs, each one's figure
-- out of its own description, the running list, our own clock, and the
-- reconcile against the real auras out of a fight.
--
-- Why a clock of our own. On this client the combat log is shut to addons
-- (C_CombatLog.IsCombatLogRestricted() is true, CombatLogGetCurrentEventInfo
-- is gone, and registering for COMBAT_LOG_EVENT_UNFILTERED is itself a
-- blocked action), and in a fight every aura read comes back nil, on the
-- target and on you, with any filter. So nothing here may wait on an aura or
-- a tick event in a fight: the list hears your own casts and counts down
-- itself, the icons' swipe comes from the game's own secure aura container,
-- and the real auras are only ever read out of a fight, to put our list
-- straight again.
--
-- Where the figures come from. C_Spell.GetSpellDescription(id) hands back the
-- spell's own text with the server's numbers already in it, so a +46 spell
-- damage robe changes Corruption's text from "40 Shadow damage over 12 sec"
-- to "76" on the same character and rank. There is no coefficient table of
-- ours, and nothing here works a figure out from your gear.
--
-- What is in so far: the settings, the page, the nav row, the list of what
-- you have running, and each spell's damage figure. One row per spell: its
-- icon with the game's own countdown swipe on it, its name, the seconds left
-- and the damage still to come. The icon and the swipe are the container's,
-- since that is the only countdown the game allows in a fight; the row's own
-- bar, its seconds and its figure are ours, off the clock below. The figure
-- is each spell's own text read for its total and its time, divided into
-- ticks and counted down on our clock (D:Figure, D:Band). The band on the
-- health bar comes after it, and it takes its number from D:Band.
local _, ns = ...

local D = {}
ns.Dots = D

local Style = ns.Style

-- Out of sight, for a spell's icon with no row of its own just now
-- (IconAuras.lua parks its anchors the same way).
local AWAY = -10000
-- How many rows the list ever holds, and how many of your spells ever get a
-- slot of their own in the secure container. Both are made once, out of a
-- fight, and never after.
local MAX_ROWS, MAX_SLOTS = 12, 12
-- Amber as it runs out: this many seconds left or fewer.
local AMBER_AT = 3
local AMBER = { 1, .72, .2 }
local FADE = .3 -- out of combat Fade, as your bars'
-- A spell whose length the addon could not work out at all is dropped after
-- this long, so nothing sits in the list for ever.
local UNKNOWN_LASTS = 30
-- A row's bar: this many icons wide, and never narrower than BAR_LEAST, so
-- the name and the numbers have room at every icon size.
local BAR_WIDE, BAR_LEAST = 5, 120
local ICON_GAP = 4 -- between a row's icon and its bar
local TEXT_INSET = 3 -- the name and the numbers in from the bar's edges
local STEP = .05 -- how often the rows are drawn again, in seconds
-- How many indices the reconcile ever asks for, and how many times a read
-- the game refused is tried again (never polled: Buffs.lua does the same).
-- MOST_TRIES covers a spell's own text as well as an aura: a client that
-- holds either back is asked a few times and then left alone.
local MOST_AURAS, MOST_TRIES = 40, 3
-- How long a spell you have just cast is left in the list even where the
-- game's own aura read has not named it yet. The aura does not always answer
-- in the same moment as the cast, and out of a fight that read is taken as
-- the whole truth, so without this the row was thrown away the instant it was
-- made (27 Nov 2026). Short enough that a spell which really missed is gone
-- on the next read.
local CAST_GRACE = 1.5
-- How many spell IDs one pass over your own spells ever reads a description
-- for, so a class with many ranks of many damage over time spells cannot
-- turn one gear change into an unbounded run of asks.
local MOST_WARM = 150
-- How long the re-read after a change is held for, so a gear set changing
-- every slot at once is read again once rather than nineteen times.
local SETTLE = .5

local function Open(value)
    return not (issecretvalue and issecretvalue(value))
end

-- The colour the band draws in, by the spell's school, for Default. The
-- school of a spell you have running comes with the figure (its description
-- names it), so this is the table those names land in.
D.SCHOOLS = {
    shadow = { .58, .35, .85 },
    fire = { 1, .45, .16 },
    frost = { .35, .7, 1 },
    nature = { .35, .85, .4 },
    arcane = { .85, .5, 1 },
    holy = { 1, .92, .5 },
    physical = { .85, .8, .7 },
}
-- Default for the band with nothing running yet, and for a spell whose
-- description names no school: the physical one, which reads as plain damage.
-- The page's Default swatch shows this same colour, so the swatch and the band
-- never disagree.
D.NO_SCHOOL = "physical"
-- The bright line's own two, which are not bar colours: ns.Style:BarColour
-- answers orange for a key it does not know, so white and black are kept
-- here, as the cast bar's tick marks keep theirs (CastBar.lua MarkColour).
local PLAIN = { white = { 1, 1, 1 }, black = { 0, 0, 0 } }

-- The ones a hit sets off rather than a cast of yours. They are listed and
-- timed, and never counted in the band: their size comes from the hit that
-- caused them, and the game tells addons nothing at all about hits. Each one
-- with its reason, and the next step adds to this as it works the figures
-- out:
--   Deep Wound     a share of your weapon's own damage, per hit
--   Ignite         a share of the fire crit that set it off
--   Thunderfury    the weapon's own proc
-- (Only one of them can be listed at all today: ns.TICK_PERIODS holds Deep
-- Wound and not the other two, and nothing is listed that is not in there.
-- They are named here all the same, so a spell that joins that table is
-- never costed by mistake.)
D.PROCS = {
    ["Deep Wound"] = true,
    ["Ignite"] = true,
    ["Thunderfury"] = true,
}

-- Everything the list keeps: the rows and the spells' icon anchors, made once
-- out of a fight; what is running on your target now, in the order it
-- started, and the same by name; the length each spell's real aura last
-- showed, which is better than anything the addon can work out; and what is
-- waiting for a fight to end. (D.state is for the tests, as the Totems bar
-- hands out its own pieces.)
local state = {
    rows = {},
    anchors = {},
    slotKeys = {},
    list = {},
    by = {},
    -- And what anyone else has running on your target, where that is ticked
    -- (the second band behind yours): the same shape, keyed by the spell and
    -- the caster the game named, since two players' own Corruption are two
    -- spells. Read out of a fight only, as every real aura is.
    theirs = {},
    theirsBy = {},
    lasts = {},
    pending = {},
    errors = {},
    tries = 0,
    -- Casts of yours the game would not name (a spell ID it held back), for
    -- /ccm debug: see Cast, below.
    sealed = 0,
    -- Each spell ID's own text read into a figure (readings[id] is the
    -- reading, or false where the game's text named no figure in it), the
    -- asks the game refused per ID, and how many asks have been made at all.
    -- The debug report says all three.
    readings = {},
    asks = {},
    reads = 0,
}
D.state = state

local ticker

-- Whether the DoTs part runs at all.
function D:On()
    return ns.Get("dots") == true
end

-- And whether the list of running spells draws: the master tick and its own.
function D:Listed()
    return ns.Get("dots") == true and ns.Get("dotList") == true
end

-- Whether this game has the secure aura container the icons' swipe comes
-- from (Buffs.lua and IconAuras.lua ask the same way). Without it the list
-- still works: each row shows the spell's own picture and our clock.
function D:Available()
    return CustomAuraContainerSlotDefaultOptions ~= nil
end

-- The colour one of the page's two colour settings stands for now, as a bar
-- colour is given (ns.Style:BarColour): its named choice, Custom's own
-- colour, white or black for the line, or for the band's Default the school's
-- (the physical one until a spell with a school of its own is running). The
-- page's swatches read the same way, so a swatch and what it draws never
-- disagree (DotsPage.lua Named).
function D:Colour(setting, key)
    key = key or ns.ColourKey(setting)
    if key == "default" then return D.SCHOOLS[self.school or D.NO_SCHOOL] end
    if PLAIN[key] then return PLAIN[key] end
    return ns.Style:BarColour(key)
end

-- Each spell's own text ----------------------------------------------------------------
-- Where every figure comes from, and the one place any of them is read. On
-- this client C_Spell.GetSpellDescription(id) hands back the spell's own
-- description with the server's numbers already worked into it: a +46 spell
-- damage robe turns Corruption's "40 Shadow damage over 12 sec" into "76" on
-- the same character and the same rank (measured in game on 26 Nov 2026,
-- build 1.60.1.71139). C_TooltipInfo.GetSpellByID answers the same text and
-- is the fallback for a client that holds the description back.
--
-- So there is no coefficient table of ours, and nothing here works a figure
-- out from your gear. Where the text names no figure the spell has none at
-- all: it is listed and timed with its damage column empty and it adds
-- nothing to the band. Nothing anywhere makes a number up.
--
-- Read out of a fight only, and kept per spell ID, since each rank has its
-- own numbers. A fight uses what was read before it (Warm, below, reads them
-- all as the part goes on and again after anything that changes them), since
-- in a fight your own stat functions are sealed and nothing here may wait on
-- a read.

-- A number as the game writes one in a spell's text. Only a separator
-- between a digit and a group of exactly three is taken out, so a client
-- that writes 40,5 for forty and a half is never read as four hundred and
-- five: it is read as no figure at all, which is the honest answer.
local function Amount(text)
    if type(text) ~= "string" then return nil end
    local plain = text
    for _ = 1, 4 do plain = plain:gsub("(%d),(%d%d%d)", "%1%2") end
    local value = tonumber(plain)
    if type(value) ~= "number" or value ~= value or value <= 0 or value >= math.huge then return nil end
    return value
end

-- How the game writes a length of time, in seconds.
local UNITS = { sec = 1, secs = 1, second = 1, seconds = 1, min = 60, mins = 60, minute = 60, minutes = 60 }

local function Span(text, unit)
    local value = Amount(text)
    local scale = type(unit) == "string" and UNITS[unit:lower()] or nil
    if not (value and scale) then return nil end
    return value * scale
end

-- The per tick shape read into a total: what each tick deals, times how many
-- ticks the whole time holds.
local function Whole(amount, each, eachUnit, time, unit)
    local value, period, span = Amount(amount), Span(each, eachUnit), Span(time, unit)
    if not (value and period and span and period > 0) then return nil end
    local ticks = math.floor(span / period + .5)
    if ticks < 1 then return nil end
    return value * ticks, span
end

-- A spell whose own text says it does not deal its damage evenly over its
-- time. Bane of Agony: "This damage is dealt slowly at first, and builds up
-- as the Bane reaches its full duration." Nothing in the text says how steep
-- that is, so the figure stays the total's share of the time left, and the
-- page says in plain words that the figure is a total rather than an even
-- spread (DotsPage.lua, under the colours).
local RAMPS = { "slowly at first", "builds up", "ramps up", "grows over time", "increases over time" }

-- A spell's text read into a figure: the damage it deals over time, how long
-- it deals it over, the school it names and whether it says it ramps.
-- Nothing is worked out here that the text does not say, and a text with no
-- figure in it answers nothing at all.
--
-- The shapes, from what the game really answered (26 Nov 2026):
--   Corruption     "Corrupts the target, causing 40 Shadow damage over 12 sec."
--   Corruption     "... causing 76 Shadow damage over 12 sec."  (+46 spell damage)
--   Bane of Agony  "... 72 Shadow damage over 24 sec. This damage is dealt
--                   slowly at first, and builds up as the Bane reaches its
--                   full duration."
--   Rend           "Wounds the target causing them to bleed for 15 damage over 9 sec."
--   Immolate       "Burns the enemy for 11 Fire damage and then an
--                   additional 15 Fire damage over 15 sec."
--   Serpent Sting  "Stings the target, causing 20 Nature damage over 15 sec."
--
-- Immolate is why only a figure the text says is dealt OVER a time is taken:
-- its 11 lands with the cast and is already dealt by the time anything here
-- looks, so counting it would mark damage on the health bar that is never
-- coming. Its own wording leaves that 11 out by itself, since the text never
-- says "11 Fire damage over" anything.
--
-- And why several figures in one text are kept apart rather than one of them
-- taken. A finishing move writes a line per combo point:
--   Rupture  "1 point: 68 damage over 8 secs ... 5 points: 378 damage over
--             16 secs"  (ns.DEBUFF_LASTS holds its six lengths for that
--             reason, and Rip's and Garrote's read the same way)
-- Nothing in that text says which line this cast was, so no one figure is
-- claimed: every pair is handed over instead (reading.pairs) and the one
-- whose own time is the length the real aura showed is the one costed
-- (D:Figure). Taking the last would cost a one point Rupture as the five
-- point one, which is five times the damage that is coming.

-- One of the figures a text named, kept once: what it deals, over how long,
-- and the school it named.
local function Note(found, total, over, school)
    for _, pair in ipairs(found) do
        if pair.total == total and pair.lasts == over then return end
    end
    found[#found + 1] = { total = total, lasts = over, school = school }
end

local function Parse(text)
    if type(text) ~= "string" or text == "" then return nil end
    local found = {}
    -- With a school named, which is every one of the six above but Rend's.
    for amount, word, time, unit in text:gmatch("(%d[%d,%.]*)%s+(%a+)%s+damage%s+over%s+(%d[%d,%.]*)%s*(%a+)") do
        local value, seconds = Amount(amount), Span(time, unit)
        if value and seconds then
            Note(found, value, seconds, D.SCHOOLS[word:lower()] and word:lower() or nil)
        end
    end
    -- With none, which is Rend's shape.
    if #found == 0 then
        for amount, time, unit in text:gmatch("(%d[%d,%.]*)%s+damage%s+over%s+(%d[%d,%.]*)%s*(%a+)") do
            local value, seconds = Amount(amount), Span(time, unit)
            if value and seconds then Note(found, value, seconds, nil) end
        end
    end
    -- The same thing said the other way round: what one tick deals and how
    -- long it keeps ticking. None of the six says it this way, so it is only
    -- ever tried once nothing above has matched.
    if #found == 0 then
        for amount, word, each, eachUnit, time, unit in text:gmatch(
            "(%d[%d,%.]*)%s+(%a+)%s+damage%s+every%s+(%d[%d,%.]*)%s*(%a+)%s+for%s+(%d[%d,%.]*)%s*(%a+)") do
            local value, seconds = Whole(amount, each, eachUnit, time, unit)
            if value and seconds then
                Note(found, value, seconds, D.SCHOOLS[word:lower()] and word:lower() or nil)
            end
        end
    end
    if #found == 0 then
        for amount, each, eachUnit, time, unit in text:gmatch(
            "(%d[%d,%.]*)%s+damage%s+every%s+(%d[%d,%.]*)%s*(%a+)%s+for%s+(%d[%d,%.]*)%s*(%a+)") do
            local value, seconds = Whole(amount, each, eachUnit, time, unit)
            if value and seconds then Note(found, value, seconds, nil) end
        end
    end
    if #found == 0 then return nil end
    local lower, ramps = text:lower(), false
    for _, phrase in ipairs(RAMPS) do
        if lower:find(phrase, 1, true) then ramps = true end
    end
    local last = found[#found]
    local reading = { school = last.school, ramps = ramps or nil, text = text }
    if #found == 1 then
        reading.total, reading.lasts = last.total, last.lasts
    else
        -- Several of them, and the text does not say which one this cast was.
        reading.pairs = found
    end
    return reading
end

-- For the tests and for anything that wants to read a text without the
-- game being asked anything at all.
function D:Parse(text)
    return Parse(text)
end

-- Whether a spell's text may be asked for now: out of a fight only, behind
-- the same first two checks the aura reconcile uses (Readable, below). In a
-- fight what was read before it stands.
local function Askable()
    if InCombatLockdown() or state.inCombat then return false end
    local fighting = UnitAffectingCombat and UnitAffectingCombat("player")
    if not Open(fighting) or fighting then return false end
    return true
end

-- The description itself. Hands back the text, and whether the game refused
-- the ask: an error or a text it held back is refused and asked again later,
-- while a spell the game simply has no text for is answered and never asked
-- again.
local function Described(id)
    local spell = C_Spell
    local ask = type(spell) == "table" and spell.GetSpellDescription
    if type(ask) ~= "function" then return nil, false end
    state.reads = state.reads + 1
    local ok, text = pcall(ask, id)
    if not ok then return nil, true end
    if text == nil then return nil, false end
    if not Open(text) then return nil, true end
    if type(text) ~= "string" or text == "" then return nil, false end
    return text, false
end

-- The tooltip reader's lines for the same spell, newest first, for a client
-- that holds the description back. Four lines were measured (name, mana
-- cost, cast time, then the description), but nothing here counts on the
-- description's place: every line is handed back and the first that reads as
-- a figure is the one taken. The whole walk is inside one pcall, since a
-- table the game holds back cannot be looked through at all.
local function TipLines(id)
    local out, held = {}, false
    local tip = C_TooltipInfo
    local get = type(tip) == "table" and tip.GetSpellByID
    if type(get) ~= "function" then return out, false end
    state.reads = state.reads + 1
    local ok = pcall(function()
        local info = get(id)
        if info == nil then return end
        if not (type(info) == "table" and Open(info)) then
            held = true
            return
        end
        local lines = info.lines
        if lines == nil then return end
        if not (type(lines) == "table" and Open(lines)) then
            held = true
            return
        end
        for i = #lines, 1, -1 do
            local line = lines[i]
            if type(line) == "table" and Open(line) then
                local text = line.leftText
                if not Open(text) then
                    held = true
                elseif type(text) == "string" and text ~= "" then
                    out[#out + 1] = text
                end
            end
        end
    end)
    if not ok then return out, true end
    return out, held
end

-- One spell ID read: its reading, false where the game answered and named no
-- figure, or nothing at all where the game refused, which is tried again.
local function Read(id)
    local refused = false
    local text, held = Described(id)
    if held then refused = true end
    if text then
        local reading = Parse(text)
        if reading then return reading end
    end
    local lines, heldLines = TipLines(id)
    if heldLines then refused = true end
    for _, line in ipairs(lines) do
        local reading = Parse(line)
        if reading then return reading end
    end
    if refused then return nil end
    return false
end

-- A spell ID's reading, read the first time it is wanted and kept after
-- that. Nothing is asked for in a fight: a figure not already read simply
-- has none until the fight ends (state.pending.figures).
local function Figures(id)
    if not (Open(id) and type(id) == "number") then return nil end
    local kept = state.readings[id]
    if kept ~= nil then return kept or nil end
    if not Askable() then
        state.pending.figures = true
        return nil
    end
    if (state.asks[id] or 0) >= MOST_TRIES then return nil end
    local reading = Read(id)
    if reading == nil then
        state.asks[id] = (state.asks[id] or 0) + 1
        return nil
    end
    state.readings[id] = reading
    return reading or nil
end

-- Which spells are DoTs ---------------------------------------------------------------
-- ns.TICK_PERIODS (Buffs.lua) is every debuff of yours that ticks, with how
-- often, from the game's own data; ns.DEBUFF_LASTS beside it is how long each
-- one lasts. Both are keyed by the name Forever uses (Curse of Agony is Bane
-- of Agony here), and ns.Spells:ByName looks a name up in either the way the
-- rest of the addon does, renames included. Nothing new is invented here and
-- neither table is edited: a spell missing from them is regenerated with
-- node Tools/MakeTickPeriods.mjs.

local byID -- every rank's spell ID to its name, made the first time one is asked for

-- The name of the spell an ID belongs to: our own tables first (so the name
-- matches the keys the rest of the file looks things up by), then the game's
-- own answer for an ID no table of ours knows.
local function NameOf(id)
    if not (Open(id) and type(id) == "number") then return nil end
    if not byID then
        byID = {}
        for name, ids in pairs(ns.RANKS or {}) do
            for _, rank in ipairs(ids) do
                if byID[rank] == nil then byID[rank] = name end
            end
        end
    end
    if byID[id] then return byID[id] end
    local spell = C_Spell
    local ask = type(spell) == "table" and spell.GetSpellName
    if type(ask) ~= "function" then return nil end
    local ok, name = pcall(ask, id)
    if ok and Open(name) and type(name) == "string" and name ~= "" then return name end
    return nil
end

-- Whether a spell of that name is a damage over time spell at all: it ticks
-- on your target (ns.TICK_PERIODS).
function D:IsDot(name)
    if type(name) ~= "string" or name == "" then return false end
    return ns.Spells:ByName(ns.TICK_PERIODS, name) ~= nil
end

-- Whether a hit sets it off rather than a cast of yours (D.PROCS).
function D:IsProc(name)
    return type(name) == "string" and D.PROCS[name] == true
end

-- Whether a spell of that name belongs in the list: a DoT, listed unless you
-- unticked it, and one a hit sets off only with List the ones a hit sets off.
function D:Wanted(name)
    if not self:IsDot(name) then return false end
    if self:IsProc(name) and ns.Get("dotProcs") ~= true then return false end
    return ns.DotListed(name)
end

-- How long a cast of that spell runs for, in seconds, or nothing where the
-- addon cannot tell. In order: the length its own aura last showed (read out
-- of a fight, and the only figure that is certainly right), then the length
-- that rank's own text gives ("over 12 sec", which the game wrote for the
-- exact rank cast), then the one length ns.DEBUFF_LASTS gives it, then the
-- length its rank asks for where the ranks and the lengths line up one for
-- one, and last the longest it has, since the rank most players cast is
-- their highest. A finisher that a combo point lengthens is only right once
-- its own aura has been seen, so one is marked a guess until then
-- (entry.guessed), and the page says so rather than pretending.
function D:Lasts(name, id)
    local seen = state.lasts[name]
    if type(seen) == "number" and seen > 0 then return seen, false end
    local reading = Figures(id)
    if reading and type(reading.lasts) == "number" and reading.lasts > 0 then return reading.lasts, false end
    -- Several figures in the one text, each with a time of its own (a
    -- finishing move's, one line per combo point): nothing in it says which
    -- line this cast was, so the longest is taken and marked a guess until
    -- the real aura hands the length over, as an unmatched rank is.
    if reading and reading.pairs then
        local most = 0
        for _, pair in ipairs(reading.pairs) do
            if pair.lasts > most then most = pair.lasts end
        end
        if most > 0 then return most, true end
    end
    local lengths = ns.Spells:ByName(ns.DEBUFF_LASTS, name)
    if type(lengths) ~= "table" or #lengths == 0 then return nil, true end
    if #lengths == 1 then return lengths[1], false end
    local ranks = ns.RANKS and ns.RANKS[name]
    if type(ranks) == "table" and #ranks == #lengths and Open(id) and type(id) == "number" then
        for i, rank in ipairs(ranks) do
            if rank == id then return lengths[i], false end
        end
    end
    return lengths[#lengths], true
end

-- The running list ---------------------------------------------------------------------

-- The spell's picture: its own entry in your spellbook if it has one, else
-- the game's answer for the ID that put it there.
local function Picture(name, id)
    local entry = ns.Spells:Find(name)
    if entry and entry.icon then return entry.icon end
    local spell = C_Spell
    local ask = type(spell) == "table" and spell.GetSpellTexture
    if type(ask) ~= "function" or not (Open(id) and type(id) == "number") then return nil end
    local ok, texture = pcall(ask, id)
    if ok and Open(texture) then return texture end
    return nil
end

-- Whether you have a target at all. A secret answer counts as yes, so a cast
-- is never thrown away over one.
local function Targeted()
    local ok, there = pcall(UnitExists, "target")
    if not ok then return true end
    if not Open(there) then return true end
    return there and true or false
end

-- And whether it is already dead. Death takes every debuff on it with it, so
-- what our clock still holds for a corpse has gone: the list comes off it
-- rather than counting damage down on something nothing is dealing it to.
-- An answer the game holds back counts as alive, since nothing here may look
-- behind one (DotsBand.lua asks the same way for the band).
local function Dead()
    local ok, dead = pcall(UnitIsDeadOrGhost, "target")
    if not ok or not Open(dead) then return false end
    return dead and true or false
end

-- Puts a spell into the list, or starts it again where it is already there
-- (a DoT cast again replaces what was left of it). start and lasts are
-- plain numbers of ours; a figure is never kept here, since it is worked out
-- from the time left each time the rows are drawn.
local function Running(name, id, now, lasts, guessed, stacks)
    local entry = state.by[name]
    if not entry then
        entry = { name = name }
        state.by[name] = entry
        state.list[#state.list + 1] = entry
    end
    entry.id, entry.start, entry.lasts, entry.guessed = id or entry.id, now, lasts, guessed and true or nil
    entry.stacks = stacks or entry.stacks
    entry.proc = D:IsProc(name) or nil
    entry.icon = Picture(name, entry.id)
    return entry
end

-- Takes a spell out of the list.
local function Gone(name)
    if not state.by[name] then return false end
    state.by[name] = nil
    for i = #state.list, 1, -1 do
        if state.list[i].name == name then table.remove(state.list, i) end
    end
    return true
end

-- The whole list goes: no target, a target that died, or a target you
-- swapped for another one. What was on the old target is forgotten rather
-- than guessed at: in a fight the game will not say what is on the new one,
-- and only your own casts are ever on our clock.
local function Clear()
    if #state.list == 0 and #state.theirs == 0 then return false end
    wipe(state.list)
    wipe(state.by)
    -- Everyone else's goes with it, for the same reason: what was on the old
    -- target says nothing about the new one, and in a fight the game will not
    -- say what is on it.
    wipe(state.theirs)
    wipe(state.theirsBy)
    return true
end

-- How long a spell has left, by our clock, or nothing where its length was
-- never worked out.
local function Left(entry, now)
    if type(entry.lasts) ~= "number" then return nil end
    return entry.start + entry.lasts - now
end

-- Everything that has run out goes. A spell with no length at all is held
-- for UNKNOWN_LASTS and then dropped, so the list can never keep something
-- that ended long ago.
local function Prune(now)
    local went = false
    for i = #state.list, 1, -1 do
        local entry = state.list[i]
        local left = Left(entry, now)
        local over = left ~= nil and left <= 0 or (left == nil and now - entry.start >= UNKNOWN_LASTS)
        if over then
            state.by[entry.name] = nil
            table.remove(state.list, i)
            went = true
        end
    end
    return went
end

-- Other players' spells -----------------------------------------------------------------
-- What anyone else has running on your target, for the second band behind your
-- own (DotsBand.lua draws it). Off until it is ticked.
--
-- Where they come from, and what that costs. A real aura names its own caster
-- (sourceUnit, which the probe proved open out of a fight), so everyone's
-- damage over time spells on your target can be read and told apart from
-- yours. Out of a fight only: in one the game answers nothing at all for any
-- aura, so what was read before it is counted down on our clock and anything
-- cast during it is not seen until it ends. Only your own casts are ever heard
-- as they happen. The page says both in plain words.
--
-- And what their figures are. Each spell's own description is the only reading
-- the game gives us, and it writes that text for this character: it says
-- nothing about their gear, their talents or which rank they cast. So their
-- figure is the spell's own, never theirs, and the page says so. Nothing a hit
-- set off is costed, theirs no more than yours.

-- The band behind yours is the only thing theirs is ever drawn as, so the
-- band's own tick is part of this: with the band off nothing of theirs is
-- read, counted or said on the page, and the wider aura filter below is never
-- asked for. (The page greys the tick while the band is off for the same
-- reason, and the setting is kept either way.)
local function Others()
    return ns.Get("dots") == true and ns.Get("dotBand") == true and ns.Get("dotOthers") == true
end

-- One of theirs, by the spell and the caster the game named.
local function TheirKey(name, source)
    return name .. "|" .. (source or "?")
end

-- Whether a debuff the game named is one of your own casts. Asked only where
-- everyone's were asked for: with the PLAYER filter every answer is yours by
-- definition. The caster the game named settles it, and a caster it held back
-- counts as yours only where that spell is on our own clock already, so a
-- sealed caster can never make a second band out of your own spell.
local function Yours(taken)
    if taken.source == "player" then return true end
    return taken.source == nil and state.by[taken.name] ~= nil
end

-- One of theirs put into the list, or started again where it is already there.
local function TheirRunning(taken, key)
    local entry = state.theirsBy[key]
    if not entry then
        entry = { name = taken.name, key = key, source = taken.source }
        state.theirsBy[key] = entry
        state.theirs[#state.theirs + 1] = entry
    end
    entry.id, entry.start, entry.lasts, entry.stacks = taken.id, taken.start, taken.lasts, taken.stacks
    entry.proc, entry.theirs = D:IsProc(taken.name) or nil, true
    return entry
end

local function TheirsClear()
    if #state.theirs == 0 then return false end
    wipe(state.theirs)
    wipe(state.theirsBy)
    return true
end

-- The damage everyone else's spells still have to deal, added up, and how many
-- of them are running. Nothing of theirs is ever drawn but the band, so this
-- is the only clock they have: one that has run out is dropped as this walks
-- rather than on a tick of its own.
function D:Theirs()
    if not Others() then return nil, 0 end
    local now = GetTime()
    for i = #state.theirs, 1, -1 do
        local entry = state.theirs[i]
        local left = Left(entry, now)
        if (left ~= nil and left <= 0) or (left == nil and now - entry.start >= UNKNOWN_LASTS) then
            state.theirsBy[entry.key] = nil
            table.remove(state.theirs, i)
        end
    end
    local total, count = nil, 0
    for _, entry in ipairs(state.theirs) do
        count = count + 1
        local figure = self:Figure(entry)
        if type(figure) == "number" and figure > 0 then total = (total or 0) + figure end
    end
    return total, count
end

-- What is running of theirs, for the tests and the debug report.
function D:TheirRows()
    local now, out = GetTime(), {}
    for i, entry in ipairs(state.theirs) do
        out[i] = { name = entry.name, id = entry.id, source = entry.source, left = Left(entry, now),
            lasts = entry.lasts, stacks = entry.stacks, proc = entry.proc, figure = self:Figure(entry) }
    end
    return out
end

-- The damage figure --------------------------------------------------------------------

-- How many times a spell of that length ticks, and how often: the length out
-- of its own text, with ns.TICK_PERIODS' period for it (Buffs.lua's table,
-- from the game's own data). A length that is not a whole number of ticks is
-- rounded to the nearest, since the game deals whole ticks.
function D:Ticks(name, over)
    local period = ns.Spells:ByName(ns.TICK_PERIODS, name)
    if not (type(period) == "number" and period > 0) then return nil, nil end
    if not (type(over) == "number" and over > 0) then return nil, period end
    local ticks = math.floor(over / period + .5)
    if ticks < 1 then ticks = 1 end
    return ticks, period
end

-- The damage a spell you have running still has to deal, and the school it
-- deals it in. Its own text gives the total and the time, ns.TICK_PERIODS
-- gives how often it ticks, and our own clock gives how much of its time is
-- left: the figure is the ticks still to come times what each one deals.
--
-- Everything that wants a figure asks through this one function: each row's
-- damage column, the page's status line (D:Running), the debug report and
-- the band (D:Band). Four things it will not do:
--   * a spell a hit set off is never costed, whatever its text says. Its
--     size comes from the hit, and the game tells addons nothing about hits.
--   * a spell whose text named no figure has none: nothing is guessed from
--     its rank, its school or anything else.
--   * a spell with no clock of ours has none either, since there is then no
--     saying how much of its time is left.
--   * a figure is never raised above the text's own total. A talent or a
--     combo point can make the aura last longer than the text says, which
--     deals more ticks than the text counted, but how much more is not in
--     the text, so the ticks still to come are capped at the ticks the text
--     paid for.
--   * a text that named several figures, one line per combo point, is costed
--     at the line whose own time is the length the real aura showed, and not
--     at all until that length is certain. Nothing picks one of the lines.
-- A spell that stacks deals its text's figure once per stack, and the count
-- is only ever readable out of a fight, so it is the last one seen.

-- How near two lengths have to be to read as the same one: the lines of a
-- finishing move's text are whole seconds apart, so this only has to forgive
-- the game writing 8 where our clock holds 8.0.
local SAME = .5

-- Which of a reading's figures a spell you have running is costed at: the one
-- it named, or, where it named several, the line whose own time is the length
-- the real aura showed. While that length is still a guess there is no saying
-- which line this cast was, so there is no figure at all.
local function Costed(reading, entry)
    if not reading.pairs then return reading.total, reading.lasts end
    if entry.guessed or type(entry.lasts) ~= "number" then return nil, nil end
    for _, pair in ipairs(reading.pairs) do
        if math.abs(pair.lasts - entry.lasts) < SAME then return pair.total, pair.lasts end
    end
    return nil, nil
end

function D:Figure(entry)
    if type(entry) ~= "table" then return nil, nil end
    if entry.proc then return nil, nil end
    local reading = Figures(entry.id)
    if not reading then return nil, nil end
    local left = Left(entry, GetTime())
    if type(left) ~= "number" then return nil, reading.school end
    if left < 0 then left = 0 end
    local total, over = Costed(reading, entry)
    if total == nil then return nil, reading.school end
    if type(entry.stacks) == "number" and entry.stacks > 1 then total = total * entry.stacks end
    local ticks, period = self:Ticks(entry.name, over)
    local coming
    if ticks and period then
        -- One tick lands every period, so a part of a period still to run is
        -- a tick that has not landed yet.
        local toCome = math.ceil(left / period)
        if toCome > ticks then toCome = ticks end
        if toCome < 0 then toCome = 0 end
        coming = total / ticks * toCome
    elseif type(over) == "number" and over > 0 then
        -- No period for it at all (nothing in the list should be in that
        -- state, since a spell is only listed when ns.TICK_PERIODS holds
        -- it): the share of its time that is left, which is the same
        -- arithmetic without the whole-tick rounding.
        coming = total * math.min(1, left / over)
    end
    if coming == nil then return nil, reading.school end
    return math.floor(coming + .5), reading.school
end

-- The band's own figure: the damage every spell on our clock still has to
-- deal, added up, with the school to draw it in. The school is the one the
-- biggest share of that damage is dealt in, so a band that is mostly
-- Corruption draws in shadow. Nothing a hit set off is in either figure.
function D:Band()
    local total, school, most = nil, nil, 0
    for _, entry in ipairs(state.list) do
        local figure, kind = self:Figure(entry)
        if type(figure) == "number" and figure > 0 then
            total = (total or 0) + figure
            if figure > most then most, school = figure, kind end
        end
    end
    self.school = school
    return total, school
end

-- What the page's status line says: how many spells are running, and the
-- damage they still have to deal. With no figure for any of them the damage
-- is nothing at all, and the page leaves that part of the line out rather
-- than saying nought.
function D:Running()
    local damage = self:Band()
    return #state.list, damage
end

-- The spells a player can take out of the list one by one (the DoTs page's
-- Choose spells panel): your own damage over time spells, by name, with the
-- picture each row shows and whether it is ticked. Anything running now that
-- is not in your spellbook (one a hit set off, say) is listed under it, so a
-- spell you can see in the list is always one you can untick.
function D:Pickable()
    local out, seen = {}, {}
    for _, entry in ipairs(ns.Spells:Fresh()) do
        if entry.kind == "spell" and self:IsDot(entry.name) and not seen[entry.name] then
            seen[entry.name] = true
            out[#out + 1] = { name = entry.name, icon = entry.icon, listed = ns.DotListed(entry.name),
                proc = self:IsProc(entry.name) or nil }
        end
    end
    for _, entry in ipairs(state.list) do
        if not seen[entry.name] then
            seen[entry.name] = true
            out[#out + 1] = { name = entry.name, icon = entry.icon, listed = ns.DotListed(entry.name),
                proc = entry.proc, running = true }
        end
    end
    for name in pairs(ns.DotsLeftOut()) do
        if not seen[name] then
            seen[name] = true
            out[#out + 1] = { name = name, icon = Picture(name), listed = false }
        end
    end
    table.sort(out, function(a, b) return a.name < b.name end)
    return out
end

-- A spell ticked or unticked in that panel: it goes into the list or out of
-- it at once.
function D:Pick(name, listed)
    ns.SetDotListed(name, listed)
    if not listed then Gone(name) end
    self:Apply()
end

-- What is running now, for the tests, the page and the debug report: each
-- spell's name, the seconds it has left, its figure and what its own text
-- said, in the order they started. (The band takes one number, D:Band, not
-- this.)
function D:Rows()
    local now = GetTime()
    local out = {}
    for i, entry in ipairs(state.list) do
        local reading = entry.id and state.readings[entry.id] or nil
        -- The figure the row is costed at, which for a text that named
        -- several is the line its own length picked (Costed), and how many
        -- lines there were, so the report says which it took and out of what.
        local total, over = nil, nil
        if reading then total, over = Costed(reading, entry) end
        out[i] = { name = entry.name, id = entry.id, left = Left(entry, now), lasts = entry.lasts,
            guessed = entry.guessed, proc = entry.proc, stacks = entry.stacks, from = entry.from,
            figure = self:Figure(entry), total = total, over = over,
            several = reading and reading.pairs and #reading.pairs or nil,
            school = reading and reading.school or nil,
            ramps = reading and reading.ramps or nil }
    end
    return out
end

-- The icons' swipe: the secure aura container --------------------------------------------
-- The only countdown the game allows in a fight is its own, so each of your
-- damage over time spells gets one slot in a container of ours, told which
-- spell to watch out of a fight, with its icon laid over an anchor frame of
-- ours. Our clock then only has to move the anchor to the row the spell sits
-- in, which it may do in a fight, since the anchor is ours. Nothing is ever
-- written onto the container or one of its buttons, nothing of its own is
-- shown or hidden, and no slot is added or told anything in a fight.

-- Runs once per slot, as the slot is added and never after (ns.BuffBar.Add
-- and ns.BuffBar.Guard, Buffs.lua: the container never runs our code while
-- it updates). Everything handed over is a child of its own button.
local function Look(anchor)
    return function(button)
        button:SetAllPoints(anchor)
        button:EnableMouse(false)
        local icon = button:CreateTexture(nil, "ARTWORK")
        icon:SetAllPoints()
        Style:Zoom(icon)
        button:SetIcon(icon)
        local cooldown = CreateFrame("Cooldown", nil, button, "CooldownFrameTemplate")
        cooldown:SetAllPoints(icon)
        cooldown:SetSwipeTexture(Style.FLAT)
        cooldown:SetReverse(true)
        Style:CooldownLook(cooldown)
        cooldown:SetDrawBling(false)
        -- The swipe is the game's and the numbers are ours: the row says the
        -- seconds left beside the name, so the icon would only say the same
        -- thing twice.
        cooldown:SetHideCountdownNumbers(true)
        button:SetDurationCooldown(cooldown)
        local top = CreateFrame("Frame", nil, button)
        top:SetAllPoints()
        top:SetFrameLevel(cooldown:GetFrameLevel() + 1)
        local count = top:CreateFontString(nil, "OVERLAY", "NumberFontNormal")
        count:SetPoint("BOTTOMRIGHT", -1, 1)
        count:SetFontObject(Style:Count(anchor.size or 28))
        button:SetApplicationCount(count)
        anchor.parts = { cooldown = cooldown, count = count, icon = icon }
    end
end

-- The container, made the first time the list is on, out of a fight only:
-- the game needs a slot's look before it shuts the container to us.
local function Container()
    if state.container or not D:Available() or InCombatLockdown() then return state.container end
    local ok, err = pcall(function()
        local box = CreateFrame("AuraContainer", nil, state.frame, "CustomAuraContainerTemplate")
        box:SetPoint("CENTER", state.frame, "CENTER")
        box:SetSize(1, 1)
        box:EnableMouse(false)
        box:SetFrameLevel(state.frame:GetFrameLevel() + 6)
        box:SetEditModePreviewEnabled(false)
        box:SetUnit("target")
        state.container = box
    end)
    if not ok and not state.errors.container then state.errors.container = tostring(err) end
    return state.container
end

-- Your own damage over time spells, by name, in a settled order, from your
-- spellbook: the ones that get a slot of their own. Read out of a fight only
-- (it reads the spellbook), and never while the list is off.
local function Mine()
    local names = {}
    for _, entry in ipairs(ns.Spells:Fresh()) do
        if entry.kind == "spell" and D:IsDot(entry.name) and #names < MAX_SLOTS then
            names[#names + 1] = entry.name
        end
    end
    table.sort(names)
    return names
end

-- The spell IDs a slot watches out for, as the container wants them
-- ({ [id] = true }), and the same sorted, for telling whether anything
-- changed: every rank of that spell.
local function IDs(name)
    local entry = ns.Spells:Find(name)
    local set, sorted = {}, {}
    for _, id in ipairs(entry and entry.ids or ns.RANKS and ns.RANKS[name] or {}) do
        if type(id) == "number" and not set[id] then
            set[id] = true
            sorted[#sorted + 1] = id
        end
    end
    if #sorted == 0 then return nil end
    table.sort(sorted)
    return set, sorted
end

-- One anchor per spell, with one slot of the container laid over it. Made
-- out of a fight only; a spell learned in one waits for it to end.
local function Slots()
    if not ns.BuffBar then return end
    -- Switched on in a fight: nothing is made or told anything until it
    -- ends (PLAYER_REGEN_ENABLED comes back here then).
    if InCombatLockdown() then
        state.pending.slots = true
        return
    end
    state.pending.slots = nil
    local box = Container()
    if not box then return end
    local names = Mine()
    local signature = table.concat(names, "|")
    if state.slotsFor == signature then return end
    state.slotsFor = signature
    -- Every word said to the container inside one pcall, as the Buffs bars say
    -- theirs (Buffs.lua): a client that turns a slot down says so by erroring,
    -- and an error let out of here would stop the rest of the addon starting,
    -- since Core.lua starts the band, the layout, the minimap button and the
    -- notes after this. Without the slots the list still works: each row shows
    -- the spell's own picture and our own clock, with no swipe over it.
    local ok, err = pcall(function()
        -- A spell learned since changes which slot watches what, so the whole
        -- map from a spell to its anchor is made again here.
        wipe(state.anchors)
        for i, name in ipairs(names) do
            local key = "d" .. i
            local anchor = state.slotKeys[key]
            if not anchor then
                anchor = CreateFrame("Frame", nil, state.frame)
                anchor:EnableMouse(false)
                anchor:SetSize(ns.Get("dotSize"), ns.Get("dotSize"))
                anchor:SetPoint("CENTER", UIParent, "BOTTOMLEFT", AWAY, AWAY)
                anchor.size = ns.Get("dotSize")
                state.slotKeys[key] = anchor
                ns.BuffBar.Add(box, "AddAuraSlot", key, "HARMFUL|PLAYER",
                    { initializeFrame = ns.BuffBar.Guard(Look(anchor)) })
                box:SetAuraSlotEnabled(key, false)
            end
            anchor.spell = name
            state.anchors[name] = anchor
            local ids = IDs(name)
            if ids then
                box:SetAuraSlotCandidateFilters(key, { includeSpellIDs = ids, isFromPlayerOrPlayerPet = true })
                box:SetAuraSlotEnabled(key, true)
            else
                box:SetAuraSlotEnabled(key, false)
            end
        end
        -- A slot no spell of yours needs any more watches nothing and its
        -- anchor goes out of sight.
        for key, anchor in pairs(state.slotKeys) do
            local wanted = false
            for _, name in ipairs(names) do
                if name == anchor.spell then wanted = true end
            end
            if not wanted then
                box:SetAuraSlotEnabled(key, false)
                if anchor.spell then state.anchors[anchor.spell] = nil end
                anchor.spell = nil
                anchor:ClearAllPoints()
                anchor:SetPoint("CENTER", UIParent, "BOTTOMLEFT", AWAY, AWAY)
            end
        end
    end)
    if not ok and not state.errors.slots then state.errors.slots = tostring(err) end
end

-- Reading every figure at once ----------------------------------------------------------
-- In a fight a spell's text is never asked for, so every figure a fight
-- needs has to have been read before it started. This reads them all: each
-- rank of each of your own damage over time spells, since each rank has its
-- own numbers and your cast names the rank. Out of a fight only, bounded
-- (MOST_WARM), and nothing is read twice.

local function Warm()
    if not D:On() then return end
    if not Askable() then
        state.pending.figures = true
        return
    end
    state.pending.figures = nil
    local asked = 0
    -- Your own spells once per change, since the page calls D:Apply on every
    -- tick and every step of a slider and this would otherwise walk your
    -- whole spellbook each time. Stale clears the flag, and a spell learned
    -- comes through Stale too (SPELLS_CHANGED). A pass cut short by
    -- MOST_WARM, or one that found no spellbook to read yet, is not counted
    -- as done, so it is made again rather than leaving figures unread.
    if not state.warmed then
        local names, done = Mine(), true
        for _, name in ipairs(names) do
            local _, sorted = IDs(name)
            for _, id in ipairs(sorted or {}) do
                if asked >= MOST_WARM then done = false end
                if done and state.readings[id] == nil then
                    asked = asked + 1
                    Figures(id)
                end
            end
        end
        state.warmed = (#names > 0 and done) or nil
    end
    -- And anything running now that is not in your spellbook, so its row has
    -- a figure too where it is not one a hit set off.
    for _, entry in ipairs(state.list) do
        if asked >= MOST_WARM then return end
        if entry.id and state.readings[entry.id] == nil then
            asked = asked + 1
            Figures(entry.id)
        end
    end
end

-- Every figure read again from scratch: your gear, your talents or your
-- level changed, so the server's own numbers in every spell's text have
-- changed with them. Several of those events land together (a gear set
-- changes every slot), so the re-read is held for a moment and done once.
--
-- In a fight nothing is thrown away: the figures already read are better
-- than none at all and stand until it ends, exactly as a refused aura read
-- leaves the last one standing.
local function Stale()
    if not D:On() then return end
    if not Askable() then
        state.pending.stale = true
        return
    end
    state.pending.stale = nil
    state.warmed = nil
    wipe(state.readings)
    wipe(state.asks)
    if state.restale then return end
    state.restale = true
    C_Timer.After(SETTLE, function()
        state.restale = nil
        Warm()
    end)
end

-- The rows ------------------------------------------------------------------------------
-- One row per spell: its icon, then a bar of ours with the name at its left
-- and the seconds left and the damage still to come at its right. The bar,
-- the seconds and the figure are our clock's; the icon and the swipe over it
-- are the container's, where the game has one.

local function NewRow(i)
    local row = state.rows[i]
    if row then return row end
    row = CreateFrame("Frame", nil, state.frame)
    row:EnableMouse(false)
    -- The spell's own picture, for a row with no slot over it: one a hit set
    -- off, or a game with no container at all.
    row.icon = row:CreateTexture(nil, "ARTWORK")
    Style:Zoom(row.icon)
    row.bar = CreateFrame("StatusBar", nil, row)
    row.bar:EnableMouse(false)
    row.bar:SetStatusBarTexture(Style:BarTexture())
    row.bar:SetMinMaxValues(0, 1)
    row.bar:SetValue(0)
    row.back = row.bar:CreateTexture(nil, "BACKGROUND")
    row.back:SetAllPoints()
    row.back:SetColorTexture(0, 0, 0, .55)
    row.name = row.bar:CreateFontString(nil, "OVERLAY")
    row.name:SetJustifyH("LEFT")
    row.name:SetWordWrap(false)
    row.time = row.bar:CreateFontString(nil, "OVERLAY")
    row.time:SetJustifyH("RIGHT")
    row.damage = row.bar:CreateFontString(nil, "OVERLAY")
    row.damage:SetJustifyH("RIGHT")
    row:Hide()
    state.rows[i] = row
    return row
end

-- The list made, the first time it is on: the frame it all hangs off, its
-- rows and the container's slots.
local function Make()
    if state.made then return end
    local frame = CreateFrame("Frame", nil, UIParent)
    frame:SetFrameStrata("MEDIUM")
    frame:EnableMouse(false)
    frame:SetSize(1, 1)
    frame:SetAlpha(0)
    state.frame = frame
    D.frame = frame
    for i = 1, MAX_ROWS do NewRow(i) end
    state.made = true
    Slots()
end

-- Where the list sits: its middle where it was put, from the middle of the
-- screen, and which way it grows from there (Grow: from its centre, or from
-- its right or left edge).
local function Place()
    local frame = state.frame
    if not frame then return end
    local grow = ns.Get("dotGrow")
    local point = grow == "left" and "RIGHT" or grow == "right" and "LEFT" or "CENTER"
    frame:ClearAllPoints()
    frame:SetPoint(point, UIParent, "CENTER", ns.Get("dotX"), ns.Get("dotY"))
end

-- Every row sized, placed and filled in as chosen. Called when the list
-- changes and when a choice on the page does, in a fight as well as out of
-- one: every frame here is ours.
local function Lay()
    if not state.made then return end
    local size, high = ns.Get("dotSize"), ns.Get("dotRowHeight")
    local gap, down = ns.Get("dotSpacing"), ns.Get("dotWrap") ~= "up"
    local perColumn = ns.Get("dotPerRow")
    local wide = math.max(BAR_LEAST, size * BAR_WIDE)
    local rowWide, rowHigh = size + ICON_GAP + wide, math.max(size, high)
    -- With List the spells unticked nothing shows, while the clock behind it
    -- keeps running for the band.
    local shown = D:Listed() and math.min(#state.list, MAX_ROWS) or 0
    local names, numbers = Style:NameFont(), Style:Font(math.max(10, high * .62))
    local rows = math.min(shown, perColumn)
    local columns = shown > 0 and math.ceil(shown / perColumn) or 0
    state.frame:SetSize(math.max(1, columns * rowWide + math.max(0, columns - 1) * gap),
        math.max(1, rows * rowHigh + math.max(0, rows - 1) * gap))
    local timer, figures = ns.Get("dotTimer") == true, ns.Get("dotNumbers") == true
    for i, row in ipairs(state.rows) do
        local entry = i <= shown and state.list[i] or nil
        if not entry then
            row:Hide()
        else
            local column, place = math.ceil(i / perColumn) - 1, (i - 1) % perColumn
            row:SetSize(rowWide, rowHigh)
            row:ClearAllPoints()
            row:SetPoint(down and "TOPLEFT" or "BOTTOMLEFT", state.frame, down and "TOPLEFT" or "BOTTOMLEFT",
                column * (rowWide + gap), down and -place * (rowHigh + gap) or place * (rowHigh + gap))
            row.icon:SetSize(size, size)
            row.icon:ClearAllPoints()
            row.icon:SetPoint("LEFT")
            row.bar:SetSize(wide, high)
            row.bar:ClearAllPoints()
            row.bar:SetPoint("RIGHT")
            row.bar:SetStatusBarTexture(Style:BarTexture())
            row.name:ClearAllPoints()
            row.name:SetPoint("LEFT", TEXT_INSET, 0)
            row.name:SetFontObject(names)
            row.time:ClearAllPoints()
            row.time:SetPoint("RIGHT", -TEXT_INSET, 0)
            row.time:SetFontObject(numbers)
            row.damage:ClearAllPoints()
            -- Left of the seconds, or at the bar's own right edge where the
            -- seconds are not shown: a hidden font string still takes up its
            -- own width, so anchoring to it either way would leave a gap
            -- where the countdown would have been.
            if timer then
                row.damage:SetPoint("RIGHT", row.time, "LEFT", -6, 0)
            else
                row.damage:SetPoint("RIGHT", -TEXT_INSET, 0)
            end
            row.damage:SetFontObject(numbers)
            row.name:SetWidth(math.max(20, wide * .5))
            row.name:SetText(entry.name)
            row.time:SetShown(timer)
            row.damage:SetShown(figures)
            -- The icon is the container's where that spell has a slot: its
            -- anchor comes here and our own picture stays out of the way.
            -- Where it has none (one a hit set off, or a game without the
            -- container) the row shows the picture itself, with no swipe.
            local anchor = state.anchors[entry.name]
            if anchor then
                anchor.size = size
                anchor:SetSize(size, size)
                anchor:ClearAllPoints()
                anchor:SetPoint("CENTER", row.icon, "CENTER")
                if anchor.parts then anchor.parts.count:SetFontObject(Style:Count(size)) end
                row.icon:SetTexture(nil)
            else
                row.icon:SetTexture(entry.icon or 134400)
            end
            row:Show()
        end
    end
    -- An anchor whose spell is not in the list goes out of sight.
    for name, anchor in pairs(state.anchors) do
        local listed = false
        for i = 1, shown do
            if state.list[i].name == name then listed = true end
        end
        if not listed then
            anchor:ClearAllPoints()
            anchor:SetPoint("CENTER", UIParent, "BOTTOMLEFT", AWAY, AWAY)
        end
    end
    Place()
end

-- The seconds left as a row writes them: a whole second above ten, a tenth
-- under it, so the last few seconds read as they run out. (Every number on a
-- row is a plain one of ours, off our own clock, so it is written with
-- SetText; a secret of the game's would have to go to SetFormattedText
-- instead, and none ever reaches here.)
local function Seconds(row, left)
    if left == nil then
        row.time:SetText("")
    elseif left >= 10 then
        row.time:SetText(("%d"):format(left))
    else
        row.time:SetText(("%.1f"):format(left))
    end
end

-- Each row drawn again off our clock: its bar's share of the time left, its
-- seconds, its figure, and amber as it runs out.
local function Draw(now)
    -- The figures first, which is also what settles the school the band and
    -- these bars draw in (D:Band sets D.school).
    D:Band()
    -- The band's own colour, and with Spell's school picked, each row in its
    -- own spell's. The school was being read once for the whole list, so one
    -- fire spell in it turned every shadow row orange: Corruption alone drew
    -- purple and went amber the moment Immolate was cast beside it (seen in
    -- game 27 Nov 2026). A colour chosen by hand still paints every row the
    -- same, which is what picking one means.
    local key = ns.ColourKey("dotBandColour")
    local colour = D:Colour("dotBandColour", key)
    local amber = ns.Get("dotAmber") == true
    for i, row in ipairs(state.rows) do
        local entry = row:IsShown() and state.list[i] or nil
        if entry then
            local left = Left(entry, now)
            local going = amber and left ~= nil and left <= AMBER_AT
            local own = key == "default" and D.SCHOOLS[entry.school or D.NO_SCHOOL] or colour
            local shade = going and AMBER or own
            row.bar:SetMinMaxValues(0, entry.lasts or 1)
            row.bar:SetValue(left or entry.lasts or 1)
            row.bar:SetStatusBarColor(shade[1], shade[2], shade[3])
            row.name:SetTextColor(1, 1, 1)
            row.time:SetTextColor(going and AMBER[1] or 1, going and AMBER[2] or 1, going and AMBER[3] or 1)
            Seconds(row, left)
            local figure = D:Figure(entry)
            row.damage:SetText(type(figure) == "number" and ("%d"):format(figure) or "")
        end
    end
end

-- Drawing ------------------------------------------------------------------------------
-- One OnUpdate for the whole list, running only while something is in it and
-- stopped the moment nothing is (Fill.lua does the same). Nothing here ever
-- asks the game anything: it is our own clock all the way.

local waited = 0

local function Stop()
    if ticker then ticker:SetScript("OnUpdate", nil) end
end

local function Run(_, elapsed)
    waited = waited + (elapsed or 0)
    if waited < STEP then return end
    waited = 0
    local now = GetTime()
    -- A target that died took its debuffs with it, so the whole list goes
    -- rather than running on over a corpse. The target frame does not change
    -- when your target dies, so no event says so and this is the one place
    -- that would notice (the band reads the same answer every pass).
    if Dead() then
        if Clear() then Lay() end
        Stop()
        D:UpdateShown()
        return
    end
    if Prune(now) then Lay() end
    if #state.list == 0 then
        Stop()
        D:UpdateShown()
        return
    end
    Draw(now)
end

local function Going()
    if not state.made or #state.list == 0 or not D:On() then return Stop() end
    if not ticker then
        ticker = CreateFrame("Frame")
        D.ticker = ticker
    end
    if not ticker:GetScript("OnUpdate") then
        waited = STEP
        ticker:SetScript("OnUpdate", Run)
    end
end

-- For the tests: whether the OnUpdate runs now, and how many rows it draws.
function D:Drawing()
    return ticker ~= nil and ticker:GetScript("OnUpdate") ~= nil, #state.list
end

-- Showing ------------------------------------------------------------------------------

-- In full in a fight, with an enemy targeted (a secret answer counts), and
-- while its page is open, as the Totems bar is. With Stay hidden with an
-- enemy targeted ticked (General page), a target does not bring it back.
local function Awake()
    if state.inCombat or InCombatLockdown() or state.pageOpen then return true end
    if ns.Get("oocIgnoreTarget") then return false end
    local ok, hostile = pcall(UnitCanAttack, "player", "target")
    if not ok then return true end
    if not Open(hostile) then return true end
    return (hostile and Targeted()) and true or false
end

-- The list's alpha: off or empty, gone right out; else in full while awake,
-- or as chosen out of combat. Never shown or hidden.
function D:UpdateShown()
    -- The band on the target's health bar marks the same list on the same
    -- clock, so it is told whenever the list is: a cast landing, a spell
    -- running out, a new target, a fight starting or ending (DotsBand.lua's
    -- Follow, which does nothing at all while the band is unticked).
    if ns.DotsBand then ns.DotsBand:Follow() end
    local frame = state.frame
    if not frame then return end
    local alpha = 0
    if self:Listed() and #state.list > 0 then
        local mode = ns.Get("dotOutOfCombat")
        alpha = Awake() and 1 or mode == "fade" and FADE or mode == "hide" and 0 or 1
    end
    frame:SetAlpha(alpha)
end

-- Reading the real auras, out of a fight only -------------------------------------------
-- In a fight the game answers nil for every aura index, on every unit, with
-- any filter, so the reconcile only ever runs out of one, behind the same
-- three checks the Buffs bars use. What it finds is the truth: a spell it
-- does not find has gone, and one it does find hands over the length our
-- clock then goes by for the rest of the session.

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

-- One aura of the game's read into plain numbers of ours, or nothing where
-- any part of it is held back. Every field is checked before it is used, and
-- nothing is ever worked out from a secret.
local function Taken(aura, now)
    if not (type(aura) == "table" and Open(aura)) then return nil end
    local id, name = aura.spellId, aura.name
    if not (Open(id) and type(id) == "number") then return nil end
    if not (Open(name) and type(name) == "string" and name ~= "") then name = NameOf(id) end
    if type(name) ~= "string" or name == "" then return nil end
    local lasts, ends, stacks = aura.duration, aura.expirationTime, aura.applications
    if not (Open(lasts) and type(lasts) == "number" and lasts > 0) then lasts = nil end
    if not (Open(ends) and type(ends) == "number" and ends > 0) then ends = nil end
    if not (Open(stacks) and type(stacks) == "number" and stacks > 0) then stacks = nil end
    -- Who cast it, which is how everyone else's are told from yours. A caster
    -- the game holds back is no caster at all here: nothing is guessed from it.
    local source = aura.sourceUnit
    if not (Open(source) and type(source) == "string" and source ~= "") then source = nil end
    local start = lasts and ends and (ends - lasts) or now
    return { id = id, name = name, lasts = lasts, start = start, stacks = stacks, source = source }
end

local Again

-- The list put straight against the real auras: every damage over time
-- debuff of yours on your target, with its real length and time left. An ask
-- the game refuses leaves the list standing and is tried again a moment
-- later, a few times at most and never polled.
local function Reconcile()
    if not (state.made and D:On()) then return false end
    if not Readable() then return false end
    local auras = C_UnitAuras
    local get = type(auras) == "table" and auras.GetAuraDataByIndex
    if type(get) ~= "function" then return false end
    if not Targeted() then
        local went = Clear()
        if went then Lay() end
        return went
    end
    -- Everyone's harmful auras where other players' spells are wanted, and
    -- only your own where they are not. Either way the answer is the whole
    -- truth out of a fight, so what the game does not name has gone.
    local now, found, refused = GetTime(), {}, false
    local theirs = Others() and {} or nil
    local filter = theirs and "HARMFUL" or "HARMFUL|PLAYER"
    local ok = pcall(function()
        for i = 1, MOST_AURAS do
            local aura = get("target", i, filter)
            if aura == nil then return end
            local taken = Taken(aura, now)
            if not taken then
                refused = true
            elseif D:Wanted(taken.name) then
                if theirs == nil or Yours(taken) then
                    found[#found + 1] = taken
                else
                    theirs[#theirs + 1] = taken
                end
            end
        end
    end)
    if not ok then
        state.unread = true
        Again()
        return false
    end
    state.unread = refused or nil
    local changed = false
    local keep = {}
    for _, taken in ipairs(found) do
        keep[taken.name] = true
        if taken.lasts then state.lasts[taken.name] = taken.lasts end
        local entry = state.by[taken.name]
        if not entry then changed = true end
        entry = Running(taken.name, taken.id, taken.start, taken.lasts, false, taken.stacks)
        entry.from = "aura"
    end
    -- Out of a fight the game's answer is the whole truth, so anything it
    -- did not name has gone. Not where it held something back: then the list
    -- stands as it was and is read again.
    if not refused then
        local now = GetTime()
        for i = #state.list, 1, -1 do
            local entry = state.list[i]
            -- A spell you have only just cast is left alone, even where the
            -- game has not named it yet. The aura does not always answer in
            -- the same moment as the cast, and reading the list as the whole
            -- truth right then threw the row away: tab to something, cast
            -- Corruption, and nothing showed (Squirt, 27 Nov 2026). The
            -- grace is short, so a spell that truly missed or was resisted
            -- still goes on the next read.
            local justCast = entry.from == "cast" and type(now) == "number" and type(entry.start) == "number"
                and (now - entry.start) < CAST_GRACE
            if not keep[entry.name] and not justCast then
                state.by[entry.name] = nil
                table.remove(state.list, i)
                changed = true
            end
        end
    end
    -- And everyone else's, the same way, where they are wanted. They have no
    -- row of their own, so nothing is laid out again for them: the band reads
    -- them through D:Theirs on its own next pass.
    if theirs then
        local keepTheirs = {}
        for _, taken in ipairs(theirs) do
            local key = TheirKey(taken.name, taken.source)
            keepTheirs[key] = true
            TheirRunning(taken, key)
        end
        if not refused then
            for i = #state.theirs, 1, -1 do
                local entry = state.theirs[i]
                if not keepTheirs[entry.key] then
                    state.theirsBy[entry.key] = nil
                    table.remove(state.theirs, i)
                end
            end
        end
    else
        TheirsClear()
    end
    if refused then
        Again()
    else
        state.tries = 0
    end
    if changed then Lay() end
    Going()
    D:UpdateShown()
    return changed
end

-- An answer the game refused, tried again a moment later: a few times at
-- most, then left alone until something else happens.
Again = function()
    if state.waiting or state.tries >= MOST_TRIES then return end
    state.tries = state.tries + 1
    state.waiting = true
    C_Timer.After(.2, function()
        state.waiting = nil
        Reconcile()
    end)
end

-- Your own casts ------------------------------------------------------------------------

-- A cast of yours that landed: a damage over time spell starts, or starts
-- again, on our clock. This one event is the whole of what the list stands on
-- in a fight, since no aura can be read in one.
--
-- Where the game holds the spell ID back, that cast is not listed at all.
-- Nothing here may guess which spell it was, and in a fight there is no
-- second way to ask, so it is counted instead and /ccm debug says so
-- (state.sealed), rather than leaving a row that never appeared with no
-- reason given. How often the game does that is not proven: the probe did
-- not measure this event, and the addon has had a secret spell ID out of it
-- elsewhere (a Buffs bar's own reading of a buff sound), so it is handled
-- rather than assumed away.
local function Cast(id)
    if not (Open(id) and type(id) == "number") then
        state.sealed = state.sealed + 1
        return false
    end
    local name = NameOf(id)
    if not name or not D:Wanted(name) then return false end
    if not Targeted() then return false end
    local lasts, guessed = D:Lasts(name, id)
    local entry = Running(name, id, GetTime(), lasts, guessed)
    entry.from = "cast"
    Lay()
    -- Painted here, not left to the next tick. Laying a row out gives it its
    -- name and shows it, but its seconds, its bar and its figure all come
    -- from the draw, so a row cast and not drawn is on screen and blank:
    -- Squirt read that as the row not appearing at all until he cast
    -- something else (27 Nov 2026).
    Draw(GetTime())
    Going()
    D:UpdateShown()
    return true
end

-- Events -------------------------------------------------------------------------------

local EVENTS = { "PLAYER_TARGET_CHANGED", "PLAYER_REGEN_DISABLED", "PLAYER_REGEN_ENABLED", "PLAYER_ENTERING_WORLD" }

-- The server works its own numbers into each spell's text, so every figure
-- changes with your gear, your weapon's enchant, your talents and your
-- level. Each of these is registered through pcall, since a client without
-- one of them errors on the ask rather than answering, and none of them is
-- heard while the part is off.
local FIGURE_EVENTS = {
    PLAYER_EQUIPMENT_CHANGED = true, WEAPON_ENCHANT_CHANGED = true, SPELLS_CHANGED = true,
    PLAYER_LEVEL_UP = true, PLAYER_LEVEL_CHANGED = true, PLAYER_TALENT_UPDATE = true,
    TRAIT_CONFIG_UPDATED = true, ACTIVE_TALENT_GROUP_CHANGED = true,
}

local function OnEvent(self, event, unit, _, id)
    if event == "UNIT_SPELLCAST_SUCCEEDED" then
        if Open(unit) and unit == "player" then Cast(id) end
    elseif FIGURE_EVENTS[event] then
        Stale()
    elseif event == "UNIT_AURA" then
        -- Out of a fight only, and the gate above settles that: in one the
        -- game answers nothing anyway.
        Reconcile()
    elseif event == "PLAYER_TARGET_CHANGED" then
        if Clear() then Lay() end
        state.tries = 0
        Reconcile()
        Going()
        D:UpdateShown()
    elseif event == "PLAYER_REGEN_DISABLED" then
        state.inCombat = true
        D:UpdateShown()
    elseif event == "PLAYER_REGEN_ENABLED" then
        state.inCombat = false
        if state.pending.slots then Slots() end
        state.tries = 0
        Reconcile()
        -- Anything the fight would not let us read, read now: a change that
        -- landed during it, then any figure that was wanted and missing.
        if state.pending.stale then
            Stale()
        elseif state.pending.figures then
            Warm()
        end
        D:UpdateShown()
    elseif event == "PLAYER_ENTERING_WORLD" then
        -- A loading screen: what was on our clock was on the last world's
        -- target, and in a fight the game will not say what is on this one,
        -- so the list goes rather than counting down on nothing. The band
        -- blanks itself for the same reason (DotsBand.lua).
        if Clear() then Lay() end
        state.tries = 0
        Reconcile()
        Warm()
        D:UpdateShown()
    end
end

local function Driver()
    if not state.driver then
        state.driver = CreateFrame("Frame")
        state.driver:SetScript("OnEvent", OnEvent)
        D.driver = state.driver
    end
    return state.driver
end

-- Heard only while the list is on. The combat log is never registered for at
-- all: on this client that is a blocked action and puts a warning box on the
-- player's screen.
local function Hear(on)
    if (state.hearing == true) == on then return end
    state.hearing = on
    if not on then
        if state.driver then state.driver:UnregisterAllEvents() end
        return
    end
    state.inCombat = InCombatLockdown() and true or false
    local driver = Driver()
    for _, event in ipairs(EVENTS) do driver:RegisterEvent(event) end
    for event in pairs(FIGURE_EVENTS) do pcall(driver.RegisterEvent, driver, event) end
    if not pcall(driver.RegisterUnitEvent, driver, "UNIT_SPELLCAST_SUCCEEDED", "player") then
        pcall(driver.RegisterEvent, driver, "UNIT_SPELLCAST_SUCCEEDED")
    end
    if not pcall(driver.RegisterUnitEvent, driver, "UNIT_AURA", "target") then
        pcall(driver.RegisterEvent, driver, "UNIT_AURA")
    end
end

-- In full while its page is open, as the Totems bar is (DotsPage.lua hooks
-- the page's OnShow and OnHide).
function D:PageOpen(open)
    self.pageOpen = open == true
    state.pageOpen = open == true
    self:UpdateShown()
end

-- Every choice on the page again: the list follows, and the band. The page
-- calls this after each change, so this is the one way in.
function D:Apply()
    -- The master tick makes it and starts the clock, since the band needs
    -- the clock whether the list of rows shows or not; List the spells only
    -- says whether the rows are drawn (Lay).
    if self:On() then
        Make()
        Hear(true)
        Slots()
        -- Every figure read while there is no fight on, so a fight has them
        -- already: in one the game is never asked for a spell's text.
        Warm()
        Lay()
        Going()
        if #state.list == 0 then Reconcile() end
    else
        Hear(false)
        if Clear() then Lay() end
        Stop()
        -- Nothing is heard while it is off, so a gear or talent change that
        -- happens then is never heard either. The readings go with it rather
        -- than being trusted again when it is ticked back on.
        state.warmed = nil
        wipe(state.readings)
        wipe(state.asks)
    end
    self:UpdateShown()
    if ns.DotsBand then ns.DotsBand:Apply() end
end

function D:Start()
    if self.started then return end
    self.started = true
    -- Nothing is registered unless the part is on: Hear does that, as
    -- Fill.lua's Listen does, so nothing is heard and nothing is made while
    -- the page is unticked.
    self:Apply()
end

-- /ccm debug (Debug.lua): what the page cannot show.
function D:Report(add)
    local running, damage = self:Running()
    local rows = {}
    for _, row in ipairs(self:Rows()) do
        rows[#rows + 1] = ("%s %s/%s (%s)%s%s%s"):format(row.name, row.left and ("%.1f"):format(row.left) or "-",
            row.lasts and ("%.1f"):format(row.lasts) or "-", tostring(row.from or "?"),
            row.guessed and " guessed" or "", row.proc and " proc" or "",
            row.figure and (" " .. row.figure) or " no figure")
    end
    local pending = {}
    for key in pairs(state.pending) do pending[#pending + 1] = key end
    table.sort(pending)
    -- The figures, which is the one part a player cannot see the workings of:
    -- what each running spell's own text said, and what came out of it.
    local figures, kept, blank = {}, 0, 0
    for _, reading in pairs(state.readings) do
        if reading then kept = kept + 1 else blank = blank + 1 end
    end
    for _, row in ipairs(self:Rows()) do
        local ticks = row.total and select(1, self:Ticks(row.name, row.over)) or nil
        figures[#figures + 1] = ("%s %s over %s in %s ticks%s%s%s%s"):format(row.name,
            row.total and ("%g"):format(row.total) or "no figure", row.over and ("%g"):format(row.over) or "-",
            ticks and tostring(ticks) or "-", row.school and (" " .. row.school) or "",
            row.several and (" of " .. row.several .. " in its text") or "",
            row.ramps and " ramps" or "", row.stacks and (" x" .. row.stacks) or "")
    end
    add(("DoTs: on %s, band %s (%s, %s%%), line %s (%s), skull %s, list %s, others %s, nameplates %s, procs %s, page open %s, running %s (%s)"):format(
        tostring(ns.Get("dots")), tostring(ns.Get("dotBand")), tostring(ns.ColourKey("dotBandColour")),
        tostring(ns.Get("dotBandStrength")), tostring(ns.Get("dotLine")), tostring(ns.ColourKey("dotLineColour")),
        tostring(ns.Get("dotSkull")), tostring(ns.Get("dotList")), tostring(ns.Get("dotOthers")),
        tostring(ns.Get("dotNameplates")), tostring(ns.Get("dotProcs")), tostring(self.pageOpen == true),
        tostring(running), damage and (damage .. " to come") or "no figures yet"))
    add(("DoTs figures: asks %s, spells with a figure %s, texts with none %s | %s"):format(
        tostring(state.reads), tostring(kept), tostring(blank),
        #figures > 0 and table.concat(figures, "; ") or "nothing running"))
    -- Everyone else's, where they are wanted: what was read and who the game
    -- said cast it. Their figures are each spell's own text as this character
    -- reads it, never their gear's, which is the one thing the page cannot
    -- show the workings of either.
    local theirs, theirRunning = self:Theirs()
    local told = {}
    for _, row in ipairs(self:TheirRows()) do
        told[#told + 1] = ("%s from %s %s/%s%s"):format(row.name, tostring(row.source or "unnamed"),
            row.left and ("%.1f"):format(row.left) or "-", row.lasts and ("%.1f"):format(row.lasts) or "-",
            row.figure and (" " .. row.figure) or (row.proc and " proc" or " no figure"))
    end
    add(("DoTs others: %s, running %s, to come %s | %s"):format(
        Others() and "on" or ns.Get("dotOthers") == true and "on, band off" or "off", tostring(theirRunning),
        tostring(theirs or "nothing"), #told > 0 and table.concat(told, "; ") or "nothing of theirs"))
    add(("DoTs list: made %s, container %s%s, slots %s, rows %s, unread %s, casts unnamed %s, waiting %s | %s"):format(
        tostring(state.made == true), tostring(state.container ~= nil),
        state.errors and state.errors.container and (" (refused: " .. state.errors.container .. ")") or "",
        tostring(state.slotsFor or "none")
            .. (state.errors and state.errors.slots and (" (refused: " .. state.errors.slots .. ")") or ""),
        tostring(#state.list), tostring(state.unread == true),
        tostring(state.sealed), #pending > 0 and table.concat(pending, ", ") or "none",
        #rows > 0 and table.concat(rows, "; ") or "nothing running"))
end
