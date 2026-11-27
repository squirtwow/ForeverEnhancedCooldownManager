-- Resource fill: a spell you can't pay for right now goes dark and fills up
-- from the bottom with your mana, rage or energy as it comes back, so
-- one look tells you how close you are to affording it. The moment you can
-- pay, it flashes once and goes bright. Off until it's ticked on its page
-- under More in /ccm (FillPage.lua). Your own bars' icons; your action bars
-- too with their own tick on that page (FillBars.lua, which draws every fill
-- through the code here).
--
-- It reads as liquid in the icon rather than a bar in it: the filled part is
-- a wash of the power's colour thin enough that the spell's own picture still
-- shows through it, only the part above the level is darkened, and the
-- surface between the two is one soft wave with a glowing crest. The wave is
-- a texture of our own (Media/Wave.tga, written by Tools/GenerateWave.mjs):
-- an above band, a below band and a crest glow, all off the same curve, drawn
-- three times over and scrolled by moving their texture coordinates.
--
-- Five looks, every one drawn here out of that one texture and plain colour,
-- no game art: Liquid (the wave rolling across, darker at the bottom and
-- brighter near the surface, small bubbles rising), Flat (one clean block of
-- colour, nothing moving and no wave at all), Frost (the same wave standing
-- still, with a few sparkles), Ember (a shorter wave with a flickering crest
-- and sparks lifting off it) and Arcane (a shorter wave with a slow glow and
-- motes drifting inside).
--
-- What a spell costs comes from the game (C_Spell.GetSpellPowerCost), asked
-- once a spell and asked again when your form changes, since a druid's
-- spells cost what the form casting them costs. A spell that costs nothing
-- gets no fill, nor does one whose cost is something this doesn't fill with
-- (health, combo points). Whether you can pay comes from the game as it does
-- for the blue tint this replaces (Bars.lua's SpellState, the second answer
-- of C_Spell.IsSpellUsable); while the game holds that answer back, the fill
-- stays as it was.
--
-- How far up the fill stands is the game's own sum, never ours. Your power is
-- a secret on this client, in a fight and out of one, and a secret number
-- can't be divided by what a spell costs or compared with it: the game stops
-- both. So every fill keeps gauges of its own (status bars, never seen),
-- whose range is what the spell costs, an open number from the game, and
-- whose value is your power exactly as the game hands it over. The game works
-- out how far up each gauge's own fill texture reaches, and everything is
-- drawn from where that texture ends: the wash reaches its top edge, the
-- wave's band stands on that edge with the darkening above it, and each
-- bubble rides a gauge of its own, as tall a share of the fill as that bubble
-- has risen through it. Nothing in this file ever learns the number, and a
-- power the game hands over plainly goes the same way.
--
-- Your power is asked for only when the game says it changed
-- (UNIT_POWER_FREQUENT, UNIT_MAXPOWER, UNIT_DISPLAYPOWER), never frame by
-- frame, and an answer the game refuses leaves the last one standing.
-- One OnUpdate draws the waves for every icon at once, about thirty times a
-- second, and only while a fill that moves is in sight: Flat at rest never
-- runs it, nor does one on bars that are hidden.
-- Every texture, gauge and animation is made with the icon that holds it
-- (Bars.lua's NewIcon), never later and never by itself, so a fill is never
-- the reason anything is built in a fight: an icon that does turn up mid-fight
-- (an item picked up then, on a Cooldowns or Utility bar) brings its own with
-- it, as all its other layers do. On one of your action bars' buttons nothing
-- is ever made during a fight at all, since those are Blizzard's own frames
-- (FillBars.lua).
local _, ns = ...

local F = {}
ns.Fill = F

local Style = ns.Style
local FLAT = "Interface\\Buttons\\WHITE8X8"

-- This file's colour for each power, where the game has none of its own
-- (PowerBarColor, which Blizzard's bars read first).
local OWN = { mana = { .19, .48, .98 }, rage = { .89, .18, .16 }, energy = { 1, .86, .21 } }
-- How fast the waves run and how far the surface rolls, by Movement.
local MOVE = { calm = { speed = .4, roll = .7 }, normal = { speed = .8, roll = 1 }, lively = { speed = 1.4, roll = 1.35 } }
-- The looks that move by themselves: Flat sits still.
local MOVES = { liquid = true, flat = false, frost = true, ember = true, arcane = true }
-- The surface, drawn from one texture of our own (Tools/GenerateWave.mjs):
-- four bands of 64 rows in a 256 by 256 picture, every one off the same
-- curve, so the light above it, the colour below it and the glow on it line
-- up exactly. It was twelve rectangles, which read as a staircase on an icon
-- this small: rectangles can't make a soft curve at all.
local WAVE = ns.MEDIA .. "Wave.tga"
-- Each band's own quarter of the texture, its top edge then its foot, pulled
-- in by one row at each end. A quarter is exactly 0, .25, .5 and .75, so a
-- band read right up to its edge is filtered against the band next to it and
-- takes some of it. The band under the curve sits next to the glow's, whose
-- first rows fade to nothing on purpose, so its bottom edge faded out and the
-- fill stopped short of the surface in a hard straight line instead of the
-- colour running up to the wave (Squirt saw it, 27 Nov 2026). One row of 64
-- costs nothing and no band can reach its neighbour.
local INSET = 1 / 256 -- one row of the 256 the picture is tall
local ABOVE_TOP, ABOVE_FOOT = 0 + INSET, .25 - INSET
local BELOW_TOP, BELOW_FOOT = .25 + INSET, .5 - INSET
local CREST_TOP, CREST_FOOT = .5 + INSET, .75 - INSET
-- How much of the texture's width shows across one icon. It holds two full
-- waves, and a bit over one wave on an icon is what reads as liquid: two
-- start to look like a zigzag at forty pixels across.
local SPAN_X = 1.25 / 2
local SCROLL = .16 -- how far across the texture the band travels a second
local FROZEN = .12 -- Frost's own place in the wave, which it holds
-- How tall the band stands on the icon, as a share of it, and how much
-- shorter Ember's and Arcane's quieter wave is.
local BAND, QUIET = .30, .6
-- The wash over the filled part at full Fill strength. It goes no higher than
-- this, so the spell's own picture always shows through the fill.
local WASH = .5
local FLECKS = 5 -- the bubbles, sparkles, sparks or motes in it
local SPOTS = { .14, .33, .52, .7, .86 } -- where each one sits across the icon
local RATES = { .55, .85, .4, .66, .95 } -- and how fast it rises or twinkles
-- And their sizes, each a share of the one size they all used to be: mixed
-- sizes read as bubbles, one size reads as a row of dots.
local SIZES = { 1.35, .85, 1.1, .75, .95 }
local STEP = 1 / 30 -- the shared OnUpdate does its work this often at most
local FLASH = .35 -- how long the flash as it becomes payable lasts, in seconds
local DISC = "Interface\\CharacterFrame\\TempPortraitAlphaMask" -- a round white disc

-- Every fill the shared OnUpdate draws now, how many there are, and the
-- frame it runs on with its clock.
local live, living = {}, 0
local ticker, clock, waited = nil, 0, 0
local fills = {} -- each fill made, so a change on the page reaches them all
local have = {} -- what you have of each power as the game hands it over, asked only as the game says it changed
local costs = {} -- what each spell costs, asked once (Ask, below)
-- Each power by the game's power type, for a cost's own type.
local byKind = {}
for _, power in ipairs(ns.FILL_POWERS) do byKind[power.kind] = power end

local function Open(value)
    return not (issecretvalue and issecretvalue(value))
end

-- Whether the fill runs at all.
function F:On()
    return ns.Get("fill") == true
end

-- The look picked.
local function Look()
    local key = ns.Get("fillStyle")
    return MOVES[key] ~= nil and key or "liquid"
end

-- Your power of one kind, exactly as the game hands it over, or nothing where
-- it refuses to answer at all: asked through pcall, kept as it comes, and
-- never read. A secret answer is taken as it is, since it is only ever handed
-- straight back to the game (Hand, below); one the game does answer plainly
-- has to be a number to be any use.
local function Read(kind)
    local ok, value = pcall(UnitPower, "player", kind)
    if not ok or value == nil then return nil end
    if Open(value) and type(value) ~= "number" then return nil end
    return value
end

-- Every power asked for again; one the game answers is kept, one it refuses
-- leaves the last answer standing.
local function Powers()
    for _, power in ipairs(ns.FILL_POWERS) do
        local value = Read(power.kind)
        if value ~= nil then have[power.kind] = value end
    end
end

-- The first cost in the game's list this fills with: its amount and its
-- power. Kept apart so the whole read sits inside one pcall, since a list
-- the game holds back can't be looked through at all. Every field is read
-- open first, the power type included: a secret number answers type() with
-- "number" exactly as a plain one does, so a type check on its own lets one
-- through, and a power type the game kept to itself would be looked up as a
-- key here.
local function Pick(list)
    if type(list) ~= "table" then return nil end
    for _, entry in ipairs(list) do
        local kind = Open(entry) and type(entry) == "table" and entry.type or nil
        local power = Open(kind) and type(kind) == "number" and byKind[kind] or nil
        local amount = power and entry.cost or nil
        if power and Open(amount) and type(amount) == "number" and amount > 0 then return amount, power end
    end
    return nil
end

-- What the game says a spell costs: the amount, its power, and whether the
-- game answered at all. No question in this game, a refusal, a list it keeps
-- to itself and an answer that isn't a list are all no answer; a list with
-- nothing this fills with in it is an answer of none, which is what a free
-- spell gives.
local function Ask(spellID)
    local get = C_Spell and C_Spell.GetSpellPowerCost
    if type(get) ~= "function" then return nil end
    local ok, list = pcall(get, spellID)
    if not ok or not Open(list) or type(list) ~= "table" then return nil end
    local read, amount, power = pcall(Pick, list)
    if not read then return nil end
    return amount, power, true
end

-- A spell's cost, asked once and kept until your form changes. Only an
-- answer is kept: a read the game refused is asked again the next time that
-- spell comes up, instead of leaving it unable to fill until your form
-- changes (the game can be short of a spell's data for a moment at a
-- loading screen, when your action bars are first read).
local function Cost(spellID)
    if type(spellID) ~= "number" then return nil end
    local kept = costs[spellID]
    if kept ~= nil then
        if kept == false then return nil end
        return kept.amount, kept.power
    end
    local amount, power, answered = Ask(spellID)
    if amount then
        costs[spellID] = { amount = amount, power = power }
    elseif answered then
        costs[spellID] = false
    end
    return amount, power
end

-- What a spell costs and the power it costs, for a fill about to be shown:
-- nothing where the spell is free, costs something this doesn't fill with, or
-- the game has never once said what you have of that power.
local function Payable(spellID)
    local amount, power = Cost(spellID)
    if not amount or have[power.kind] == nil then return nil end
    return amount, power
end

-- One fill's gauges at a cost and a value: the range the game measures
-- against, which is what the spell costs, and the value it measures, which is
-- your power as it came. The value may be a secret, so nothing here reads,
-- tests or counts it; the game works out how far up each gauge stands, the
-- bubbles' gauges each at their own share of the fill (Flecks, below).
local function Hand(parts, amount, value)
    if value == nil then return end -- the game answered nothing at all: left as it was
    local gauges = parts.gauges
    for i = 1, #gauges do
        gauges[i]:SetMinMaxValues(0, amount)
        gauges[i]:SetValue(value)
    end
end

-- The game's own colour for one power, as Blizzard's bars read it, and this
-- file's where the game has none (its page's Default swatch too). Each power
-- keeps one table for it, so asking again makes no garbage and a fill can
-- tell the colour hasn't changed.
local owned = {}
function F:Own(power)
    local kept = owned[power.key]
    if not kept then
        kept = {}
        owned[power.key] = kept
    end
    local info = type(PowerBarColor) == "table" and PowerBarColor[power.token] or nil
    local own = type(info) == "table" and type(info.r) == "number" and info or nil
    if own then
        kept[1], kept[2], kept[3] = own.r, own.g, own.b
    else
        own = OWN[power.key] or OWN.mana
        kept[1], kept[2], kept[3] = own[1], own[2], own[3]
    end
    return kept
end

-- The colour one power fills in: the one you picked for it, or the game's own
-- while it's left at Default.
function F:Colour(power)
    local key = ns.ColourKey(power.setting)
    if type(key) == "string" and key ~= "default" then return Style:BarColour(key) end
    return self:Own(power)
end

-- The look ---------------------------------------------------------------------------------

-- A gradient up a texture. It is drawn over the texture's own colour, never
-- instead of it (a texture draws as what it holds times the colour given for
-- its corners, which is why the game's own gradients are laid on plain white:
-- Window.lua's rainbow), so the wash is only ever shaded in greys. A colour
-- here would be the power's colour twice over, and the fill would come out
-- far darker than the swatch on its page says.
local function Shade(texture, from, to)
    if CreateColor and texture.SetGradient then
        texture:SetGradient("VERTICAL", CreateColor(from[1], from[2], from[3], from[4] or 1),
            CreateColor(to[1], to[2], to[3], to[4] or 1))
    end
end
-- The wash's own shade, down its height: white at the top, where it meets the
-- wave's filled side, so those two are the same colour exactly and no join
-- shows at the level, and darker at the foot, so the fill reads as depth.
-- Flat is one clean block, so it takes white at both ends. A game without
-- gradients leaves the wash the flat colour, which is the same at the join.
local DEPTH, LIT = { 1, 1, 1 }, { 1, 1, 1 }
local FOOT, GLOW = .55, .3 -- how dark the foot goes, and how far Arcane lifts it

-- A colour part of the way to black (0) or white (1), for the shades the
-- looks are drawn in. Written into one of a few tables kept for them, so the
-- waves leave nothing behind for the game to tidy up as they run; slot keeps
-- one apart from another where more than one is wanted at once.
local shades = { {}, {}, {} }
local function Mix(slot, colour, towards, share)
    local shade = shades[slot]
    shade[1] = colour[1] + (towards - colour[1]) * share
    shade[2] = colour[2] + (towards - colour[2]) * share
    shade[3] = colour[3] + (towards - colour[3]) * share
    return shade
end

-- Nothing of the fill shows: every layer of it, the darkening and what it
-- costs. The flash is left alone, since it fades out after the fill has gone.
local function Blank(parts)
    for i = 1, #parts.layers do parts.layers[i]:Hide() end
end

-- One fill's gauge: a status bar of its own, never seen (it is see-through,
-- and only the game's own measure of it is ever used), standing on the bottom
-- of what the fill sits on and growing upwards. Its own fill texture is where
-- everything else is drawn from.
local function Gauge(parts, holder)
    local gauge = CreateFrame("StatusBar", nil, holder)
    gauge:EnableMouse(false)
    gauge:SetOrientation("VERTICAL")
    gauge:SetStatusBarTexture(FLAT)
    gauge:SetAlpha(0)
    gauge:SetPoint("BOTTOMLEFT", holder, "BOTTOMLEFT", 0, 0)
    gauge:SetSize(1, 1)
    gauge:SetMinMaxValues(0, 1)
    gauge:SetValue(0)
    parts.gauges[#parts.gauges + 1] = gauge
    return gauge, gauge:GetStatusBarTexture()
end

-- One fill's layers and gauges, made once with the icon that holds them and
-- never again (and never at all on a button of your action bars in a fight). A frame of the addon's own goes over the icon either way,
-- so showing or hiding the bar reaches the fill (Wake and Sleep, below) and
-- the gauges have somewhere to stand; nothing shows until the fill is on and
-- you're short, and the flash fades out on its own after the fill has gone.
-- drop lowers every layer inside ARTWORK by that much: 0 on your bars' own
-- icons, where the layers go on that frame and the fill sits over the icon
-- and its swipe, and lower on one of your action bars' buttons
-- (FillBars.lua), where the layers go on the button itself, under its own
-- cooldown swipe (a frame of ours at the button's level draws over that
-- swipe, a texture on the button under it: seen in game, 26 Nov 2026), and
-- the lowest sublevels keep them under the button's own art and border too.
local function Build(owner, level, flash, drop, art)
    drop = drop or 0
    local onButton = drop ~= 0
    -- What the fill is bounded by. On a button of your action bars that is the
    -- button's own picture, not the button: the frame is bigger than its art,
    -- so filling the frame spills the wash and the wave over the border and
    -- into the gap between slots (Squirt saw it, 27 Nov 2026). The textures
    -- are still made on the button itself, which is what keeps them under its
    -- swipe, keybind and count. No picture to read: the button, as before.
    local bounds = art or owner
    -- What it costs and the flash sit over the fill: over everything on an
    -- icon of ours, and still under the keybind and count on a button of
    -- your action bars.
    local top = onButton and "ARTWORK" or "OVERLAY"
    local parts = { owner = owner, flecks = {}, gauges = {}, fleckMarks = {}, width = 1, height = 1 }
    local holder = CreateFrame("Frame", nil, owner)
    holder:EnableMouse(false)
    holder:SetAllPoints(bounds)
    if level then holder:SetFrameLevel(level) end
    parts.holder = holder
    -- The one the fill itself is drawn from, then one for each bubble.
    parts.gauge, parts.mark = Gauge(parts, holder)
    for i = 1, FLECKS do
        local _, mark = Gauge(parts, holder)
        parts.fleckMarks[i] = mark
    end
    local canvas = onButton and owner or holder
    -- The spell you can't pay for, darkened. Flat has no surface to darken
    -- down to, so it darkens the whole icon as it always did; every look with
    -- a wave darkens from the icon's top down to the top of the wave's band,
    -- and the band's own above side carries it the rest of the way to the
    -- level.
    parts.dark = canvas:CreateTexture(nil, "ARTWORK", nil, drop - 3)
    parts.dark:SetTexture(FLAT)
    parts.dark:SetAllPoints(bounds)
    parts.darkTop = canvas:CreateTexture(nil, "ARTWORK", nil, drop - 3)
    parts.darkTop:SetTexture(FLAT)
    -- The filled part: a wash of the power's colour, thin enough that the
    -- spell's own picture still shows through it. Added to the picture rather
    -- than laid over it (27 Nov 2026): over a dark spell a half see-through
    -- blue came out muddy, and the only ways to brighten a laid-over wash are
    -- to make it more opaque or to pale the colour, which cost the picture or
    -- make the fill disagree with its own swatch. Adding lights the picture
    -- up in the power's own colour instead, so the art stays every bit as
    -- readable ("i just wanna be able to still see the icon") and the swatch
    -- on the page stays true. The wave's filled side is added the same way,
    -- or the two would not match where they meet.
    parts.wash = canvas:CreateTexture(nil, "ARTWORK", nil, drop - 2)
    parts.wash:SetTexture(FLAT)
    parts.wash:SetBlendMode("ADD")
    -- The surface: the one wave texture three times over, each showing a band
    -- of its own. Dark above the curve, the power's colour below it, and the
    -- glowing crest over both, so the three read as one surface.
    parts.above = canvas:CreateTexture(nil, "ARTWORK", nil, drop - 1)
    parts.below = canvas:CreateTexture(nil, "ARTWORK", nil, drop)
    parts.below:SetBlendMode("ADD") -- as the wash is, so the two meet in the same colour
    -- Round bubbles, not squares: the game's own white disc, tinted each
    -- frame with SetVertexColor rather than painted over with a flat colour.
    for i = 1, FLECKS do
        parts.flecks[i] = canvas:CreateTexture(nil, "ARTWORK", nil, drop + 1)
        parts.flecks[i]:SetTexture(DISC)
    end
    parts.crest = canvas:CreateTexture(nil, "ARTWORK", nil, drop + 2)
    parts.ribbon = { parts.above, parts.below, parts.crest }
    -- REPEAT across, so a band's texture coordinates can run on past the
    -- texture's right edge and come round again as it scrolls, with no seam;
    -- CLAMP down it, since each band keeps to its own quarter.
    for i = 1, #parts.ribbon do parts.ribbon[i]:SetTexture(WAVE, "REPEAT", "CLAMP") end
    parts.cost = canvas:CreateFontString(nil, top, "NumberFontNormalSmall")
    if onButton then parts.cost:SetDrawLayer(top, drop + 3) end
    parts.cost:SetPoint("BOTTOMLEFT", bounds, "BOTTOMLEFT", 2, 2)
    -- Nothing is ever moved again: every layer is anchored once, here. The
    -- game puts the gauge's own fill texture's top edge where the level is,
    -- so the wave's band stands on that edge and rises above it, the
    -- darkening runs from the icon's top down to the band's top, and the wash
    -- runs from the level down to the bottom. None of it is worked out from
    -- how far up the level is, because that edge is the level. A game whose
    -- status bars have no texture of their own to measure from can't be drawn
    -- on at all, and the fill never shows (F:Set).
    if parts.mark then
        for i = 1, #parts.ribbon do
            parts.ribbon[i]:SetPoint("BOTTOMLEFT", parts.mark, "TOPLEFT", 0, 0)
            parts.ribbon[i]:SetPoint("BOTTOMRIGHT", parts.mark, "TOPRIGHT", 0, 0)
        end
        parts.darkTop:SetPoint("TOPLEFT", holder, "TOPLEFT", 0, 0)
        parts.darkTop:SetPoint("TOPRIGHT", holder, "TOPRIGHT", 0, 0)
        parts.darkTop:SetPoint("BOTTOMLEFT", parts.above, "TOPLEFT", 0, 0)
        parts.darkTop:SetPoint("BOTTOMRIGHT", parts.above, "TOPRIGHT", 0, 0)
        parts.wash:SetPoint("TOPLEFT", parts.mark, "TOPLEFT", 0, 0)
        parts.wash:SetPoint("TOPRIGHT", parts.mark, "TOPRIGHT", 0, 0)
        parts.wash:SetPoint("BOTTOMLEFT", holder, "BOTTOMLEFT", 0, 0)
        parts.wash:SetPoint("BOTTOMRIGHT", holder, "BOTTOMRIGHT", 0, 0)
    end
    -- Every layer the fill is drawn in, so the whole of it goes in one go
    -- (nothing is hidden with the frame it sits on any more: on a button of
    -- your action bars the layers are the button's own).
    parts.layers = { parts.wash, parts.darkTop, parts.above, parts.below, parts.crest, parts.dark, parts.cost }
    for i = 1, FLECKS do parts.layers[#parts.layers + 1] = parts.flecks[i] end
    Blank(parts)
    -- The flash as you become able to pay, on an icon only. The page's
    -- preview never flashes, so it gets none of this.
    if flash then
        parts.flash = canvas:CreateTexture(nil, top, nil, onButton and drop + 4 or nil)
        parts.flash:SetTexture(FLAT)
        parts.flash:SetAllPoints(bounds)
        parts.flash:Hide()
        -- The game fades it out by itself, so nothing is drawn frame by frame
        -- for it.
        local group = parts.flash:CreateAnimationGroup()
        local fade = group:CreateAnimation("Alpha")
        fade:SetDuration(FLASH)
        fade:SetFromAlpha(1)
        fade:SetToAlpha(0)
        group:SetScript("OnFinished", function() parts.flash:Hide() end)
        parts.fade = group
    end
    return parts
end

-- How tall the wave's band stands on this icon, how much room that leaves
-- the fill under it, and how big the pieces drawn out of its own size are.
-- The gauge stops short of the top by the whole band, so a crest on a full
-- fill reaches the icon's top edge and never goes over it.
local function Sizes(parts)
    local w, h = parts.width, parts.height
    local quiet = parts.look == "ember" or parts.look == "arcane"
    -- About a third of the icon is what makes it read as liquid in a cup: at
    -- a ninth the surface was four pixels on a 40 pixel icon and the eye took
    -- it for a straight edge. Movement says how far the surface rolls, and
    -- Ember and Arcane wear the same wave shorter.
    local band = h * BAND * (MOVE[parts.move] or MOVE.normal).roll
    band = math.max(quiet and 6 or 10, math.floor(band * (quiet and QUIET or 1) + .5))
    parts.ribbonH = math.max(1, math.min(math.floor(h / 2), band))
    -- Flat has no wave, so it fills the whole icon as it always did.
    parts.span = parts.look == "flat" and h or math.max(1, h - parts.ribbonH)
    -- Bubbles at a sixteenth of the icon were two pixels across and vanished.
    parts.fleckSize = math.max(2, math.floor(w / 9 + .5))
    parts.gauge:SetSize(w, parts.span)
    for i = 2, #parts.gauges do parts.gauges[i]:SetWidth(w) end
    for i = 1, #parts.ribbon do parts.ribbon[i]:SetHeight(parts.ribbonH) end
end

-- Everything on the page a fill is drawn by, read once a change and kept on
-- it: the look, how much it moves, how strong the fill is, how dark the rest
-- goes, and the ticks that only change what shows. The look and the movement
-- set how far the surface rolls, so the gauges are sized again with them.
local function Dress(parts)
    parts.look = Look()
    parts.move = MOVE[ns.Get("fillMove")] and ns.Get("fillMove") or "normal"
    parts.strength = ns.Get("fillStrength") / 100
    parts.darkness = ns.Get("fillDarkness") / 100
    parts.bubbles = ns.Get("fillBubbles") == true
    parts.lit = ns.Get("fillLine") == true
    parts.dim = ns.Get("fillDim") == true
    parts.showCost = ns.Get("fillCost") == true
    Sizes(parts)
end

-- How big the icon under it is, so every piece is worked out from its own
-- size and nothing ever reaches past it.
local function Fit(parts, width, height)
    parts.width, parts.height = math.max(1, width or 1), math.max(1, height or 1)
    Sizes(parts)
end

-- The surface at a moment in time. The three bands are the same picture read
-- at three heights, so sliding all of them along by the same amount keeps the
-- light above the curve, the colour below it and the glow on it one surface;
-- two offsets would tear it apart at the join. Nothing here knows how far up
-- the level is: the band is anchored to it and only its texture moves, and
-- how far along that is is made of time alone.
local function Ribbon(parts, off, colour, wash, dark, crest)
    local last = off + SPAN_X
    parts.above:SetTexCoord(off, last, ABOVE_TOP, ABOVE_FOOT)
    parts.below:SetTexCoord(off, last, BELOW_TOP, BELOW_FOOT)
    parts.crest:SetTexCoord(off, last, CREST_TOP, CREST_FOOT)
    -- The same black as the darkening above it and the same colour as the
    -- wash below it, so neither join shows; the crest is white and bright.
    -- Every band is white in the picture, with its shape in the alpha alone,
    -- so the tint is all it takes.
    parts.above:SetVertexColor(0, 0, 0)
    parts.above:SetAlpha(dark)
    parts.above:SetShown(dark > 0)
    parts.below:SetVertexColor(colour[1], colour[2], colour[3])
    parts.below:SetAlpha(wash)
    parts.below:Show()
    parts.crest:SetVertexColor(1, 1, 1)
    parts.crest:SetAlpha(crest)
    parts.crest:SetShown(parts.lit and crest > 0)
end

-- The bubbles, sparkles, sparks or motes: bubbles rise through the fill to
-- the surface, sparkles twinkle in it, sparks lift off above it, and motes
-- drift about inside. None on Flat, and none with Bubbles unticked.
-- Each one stands on a gauge of its own, as tall a share of the fill as the
-- one the fill itself is drawn from: the game puts that gauge's own fill
-- texture at that share of the level, so a bubble follows the level without
-- anything here knowing it, and can never rise out of the fill. A spark
-- lifting off is the share under it falling away as it climbs, with the rest
-- of its climb a plain height above that share.
local function Flecks(parts, now, colour)
    local w, h = parts.width, parts.height
    local look = parts.look
    local show = parts.bubbles and look ~= "flat"
    for i = 1, FLECKS do
        local fleck = parts.flecks[i]
        if not show then
            fleck:Hide()
        else
            -- Mixed sizes, around the one size they all used to be.
            local size = math.max(2, math.floor(parts.fleckSize * SIZES[i] + .5))
            local step = (now * RATES[i] + i * .37) % 1
            local x, share, lift, alpha = SPOTS[i] * (w - size), step, 0, .75 * (1 - step * .6)
            if look == "ember" then
                share, lift, alpha = 1 - step, step * math.max(0, h - size), 1 - step
            elseif look == "frost" then
                share, alpha = SPOTS[i], .35 + .5 * (1 + math.sin(now * 3 + i)) / 2
            elseif look == "arcane" then
                share = .2 + .6 * (1 + math.sin(now * 1.2 + i * 2)) / 2
                x = x + math.sin(now * .8 + i) * w / 10
                alpha = .5 + .35 * (1 + math.sin(now * 1.7 + i)) / 2
            end
            -- Brighter than they were, so a bubble reads against the fill it
            -- rises through. The disc is tinted, never painted over: a flat
            -- colour would throw the round shape away and leave a square.
            local tint = Mix(3, colour, 1, look == "ember" and .7 or .55)
            parts.gauges[i + 1]:SetHeight(math.max(1, parts.span * share))
            fleck:ClearAllPoints()
            fleck:SetPoint("BOTTOMLEFT", parts.fleckMarks[i], "TOPLEFT", math.max(0, math.min(w - size, x)), lift)
            fleck:SetSize(size, size)
            fleck:SetVertexColor(tint[1], tint[2], tint[3], math.min(1, alpha + .2) * parts.strength)
            fleck:Show()
        end
    end
end

-- Draws one fill at a moment in time. Where the level is, and so how tall the
-- wash is and where the wave's band stands, is the game's own measure of the
-- gauge: nothing here is worked out from it.
local function Paint(parts, now)
    local colour = parts.colour or OWN.mana
    local look, strength = parts.look, parts.strength
    now = now * (MOVE[parts.move] or MOVE.normal).speed
    -- The filled part: the power's colour at Fill strength, held thin enough
    -- that the spell's own picture shows through it at every setting. Darker
    -- at the bottom, brighter near the surface; Arcane's whole fill glows
    -- slowly, and Flat is one clean block of it. With none of that power at
    -- all the game leaves it nothing to draw, so only the darkening shows.
    local wash = WASH * strength
    -- Arcane's slow glow, on the whole fill's opacity rather than on a shade
    -- down its foot (27 Nov 2026). The wash and the wave's own filled side
    -- are handed this one number, so they breathe together and the join
    -- between them stays invisible however far it has lifted.
    if look == "arcane" then wash = wash * (1 - GLOW * (1 + math.sin(now * .9)) / 2) end
    local dark = parts.dim and parts.darkness or 0
    -- How much of it shows is the layer's own opacity, not the colour's: a
    -- gradient is laid over that same texture (Shade, above) and carries an
    -- opacity of its own at each end, and whether that one is what the game
    -- draws with has never been seen here. On its own alpha it can't be: the
    -- opacity of the layer is always the last word, so the spell's picture
    -- shows through whatever the gradient does, and the wave's own filled
    -- side (which is tinted and set the same way) matches it exactly.
    parts.wash:SetColorTexture(colour[1], colour[2], colour[3], 1)
    parts.wash:SetAlpha(wash)
    -- How dark the foot of the wash goes, in plain grey over that colour
    -- (Shade, above): nothing for Flat, which is one clean block, and
    -- Arcane's slow glow lifting the depths and letting them fall again. The
    -- top is always white, so the wash meets the wave's own filled side in
    -- exactly the same colour. Set again only when it changes.
    -- No depth shade for now (27 Nov 2026): Squirt saw a hard straight line
    -- where the wash meets the wave's filled side, which made the wave read
    -- as a decoration floating over the real level instead of being the
    -- surface itself. Both carry the same colour and the same opacity, and
    -- the gradient is the only thing that differs between them, so it comes
    -- off until the join is seen to be clean. Put FOOT back (and Arcane's
    -- breathing glow with it) once that is known.
    local foot = 1
    if parts.footAt ~= foot then
        parts.footAt = foot
        DEPTH[1], DEPTH[2], DEPTH[3] = foot, foot, foot
        Shade(parts.wash, DEPTH, LIT)
    end
    parts.wash:Show()
    -- The darkening, set again only when it changes.
    if parts.darkAt ~= dark then
        parts.darkAt = dark
        parts.dark:SetColorTexture(0, 0, 0, dark)
        parts.darkTop:SetColorTexture(0, 0, 0, dark)
    end
    if look == "flat" then
        -- No surface at all: one block of colour, over the whole icon
        -- darkened, exactly as Flat always was.
        parts.dark:SetShown(dark > 0)
        parts.darkTop:Hide()
        for i = 1, #parts.ribbon do parts.ribbon[i]:Hide() end
    else
        parts.dark:Hide()
        parts.darkTop:SetShown(dark > 0)
        -- Frost holds its own place in the wave, so the ice stands still; the
        -- rest roll along with the shared clock, wrapped round the texture's
        -- own width so the offset never grows without bound.
        local off = look == "frost" and FROZEN or (now * SCROLL) % 1
        -- Ember's crest burns unevenly, Arcane's glows slowly, and the rest
        -- are steady.
        local flicker = look == "ember" and (.55 + .45 * (1 + math.sin(now * 7.3)) / 2) or 1
        local pulse = look == "arcane" and (.75 + .25 * (1 + math.sin(now * 1.1)) / 2) or 1
        Ribbon(parts, off, colour, wash, dark, math.min(1, strength + .25) * flicker * pulse)
    end
    Flecks(parts, now, colour)
end

-- Working ----------------------------------------------------------------------------------

local Wake, Sleep, Listen

local function Stop()
    if ticker then ticker:SetScript("OnUpdate", nil) end
end

-- Whether a fill needs the shared OnUpdate: one in sight, in a look that
-- moves. How far up it stands is the game's own and can't be read here, so
-- one sitting empty or full keeps its waves rolling; Flat still never runs.
local function Wants(parts)
    if not (parts.on and parts.holder:IsVisible()) then return false end
    return MOVES[parts.look] == true
end

local function Run(_, elapsed)
    clock = clock + (elapsed or 0)
    waited = waited + (elapsed or 0)
    if waited < STEP then return end
    waited = 0
    for parts in pairs(live) do
        Paint(parts, clock + parts.seed)
        if not Wants(parts) then Sleep(parts) end
    end
    if living == 0 then Stop() end
end

-- The one frame every fill's waves are drawn on, made the first time one
-- needs it.
local function Going()
    if not ticker then ticker = CreateFrame("Frame") end
    F.ticker = ticker
    if not ticker:GetScript("OnUpdate") then
        waited = STEP -- so the first frame draws and a new fill never sits still
        ticker:SetScript("OnUpdate", Run)
    end
end

Wake = function(parts)
    -- One that doesn't need drawing any more (Flat, or one out of sight)
    -- leaves at once, so the OnUpdate stops with the last of them.
    if not Wants(parts) then return Sleep(parts) end
    if not live[parts] then
        live[parts] = true
        living = living + 1
    end
    Going()
end

Sleep = function(parts)
    if not live[parts] then return end
    live[parts] = nil
    living = living - 1
    if living == 0 then Stop() end
end

-- The fill goes: nothing of it shows, and it leaves the shared OnUpdate. The
-- flash is left to fade out on its own.
local function Clear(parts)
    parts.on, parts.amount = false, nil
    Sleep(parts)
    Blank(parts)
end

-- Shown: the gauges take what the spell costs and what you have of the power
-- it costs, that power's colour goes on it, the spell is darkened under it,
-- and what it costs shows if that's ticked.
local function Fill(parts, amount, power)
    local first = not parts.on
    -- Nothing new to draw: the game says the same as last time, so the
    -- shared OnUpdate is left to its waves and nothing else is set, your
    -- power included (it is handed over as the game says it changed, by
    -- Levels below). A change on the page clears the power first, so that
    -- always draws again.
    local same = not first and parts.amount == amount and parts.power == power
    parts.on, parts.amount = true, amount
    if same then return Wake(parts) end
    if parts.power ~= power then
        parts.power = power
        parts.colour = F:Colour(power)
    end
    Hand(parts, amount, have[power.kind])
    parts.cost:SetText(amount)
    parts.cost:SetShown(parts.showCost)
    Paint(parts, clock + parts.seed)
    Wake(parts)
end

-- You can pay for it now: the fill goes, with one flash as it does. No flash
-- for an icon out of sight, nor for one that wasn't filling.
local function Paid(parts)
    local was = parts.on
    Clear(parts)
    if not (was and parts.flash and ns.Get("fillFlash") == true and parts.owner:IsVisible()) then return end
    parts.flash:SetColorTexture(1, 1, 1, .45)
    parts.flash:SetAlpha(1)
    parts.flash:Show()
    parts.fade:Stop()
    parts.fade:Play()
end

-- On your bars -----------------------------------------------------------------------------

-- One fill's layers over a frame, with everything they are drawn by: their
-- own moment in time, what the page says, and the size of what they sit on.
-- Both surfaces come through here: your bars' icons (F:Build, below) and
-- your action bars' buttons (FillBars.lua), so there is one lot of drawing
-- code for the two. level is the frame level the layers sit at, drop how far
-- they go down inside ARTWORK (Build, above).
function F:Attach(owner, level, width, height, drop, art)
    local parts = Build(owner, level, true, drop, art)
    parts.seed = #fills * .37 -- so every fill's waves don't roll in step
    parts.holder:SetScript("OnShow", function() Wake(parts) end)
    parts.holder:SetScript("OnHide", function() Sleep(parts) end)
    Dress(parts)
    Fit(parts, width, height)
    fills[#fills + 1] = parts
    return parts
end

-- One icon's layers, made with the icon (Bars.lua's NewIcon): over its art
-- and its cooldown swipe. Nothing of Blizzard's is touched.
function F:Build(icon)
    if icon.fill then return icon.fill end
    local cooldown = icon.cooldown
    icon.fill = self:Attach(icon, cooldown and (cooldown:GetFrameLevel() or 1) + 1 or nil, icon:GetWidth(), icon:GetHeight())
    return icon.fill
end

-- The size of what a fill sits on, where that can change under it (a button
-- of your action bars).
function F:Size(parts, width, height)
    if parts then Fit(parts, width, height) end
end

-- A fill with nothing to show any more (an empty spot, a spell that costs
-- nothing now): nothing is left on what it sits on.
function F:Drop(parts)
    if parts then Clear(parts) end
end

-- Whether a spell costs something this fills with, asked once a spell
-- (FillBars.lua: a free spell on your action bars never takes a fill).
function F:Costed(spellID)
    return (Cost(spellID)) ~= nil
end

-- A bar laid out (Bars.lua's Layout): each icon's fill sized to it, and set
-- up again where it shows another spell now. The spots left over go dark.
function F:Layout(bar, data)
    for i, icon in ipairs(bar.icons) do
        local parts = icon.fill
        if parts and i <= (bar.count or 0) then
            local own = icon.ownSize or icon.size or (data and ns.IconSize(data)) or parts.width
            Fit(parts, own, icon:GetHeight())
            Dress(parts)
            parts.cost:SetFontObject(Style:Count(icon.face or own))
            if parts.spell ~= icon.spellID then
                parts.spell = icon.spellID
                Clear(parts)
            end
        elseif parts then
            parts.spell = nil
            Clear(parts)
        end
    end
end

-- One fill at what the game says now: short, whether you're short of the
-- power that spell costs, and answered, whether the game said at all. True
-- while the fill shows. Your action bars' buttons come straight here
-- (FillBars.lua); your bars' icons through F:Icon, below.
function F:Set(parts, spellID, short, answered)
    if not parts then return false end
    if not self:On() then
        if parts.on then Clear(parts) end
        return false
    end
    parts.spell = spellID
    -- The game is holding the answer back: the fill stays as it was.
    if not answered then return parts.on == true end
    if not short then
        Paid(parts)
        return false
    end
    -- Nothing to fill, or no status bar to measure it on at all.
    local amount, power = Payable(spellID)
    if not amount or not parts.mark then
        Clear(parts)
        return false
    end
    Fill(parts, amount, power)
    return true
end

-- One icon's state, from the game's own answers (Bars.lua's SpellState).
-- True while the fill shows, which is when the icon keeps its own colours
-- instead of turning blue.
function F:Icon(icon, short, answered)
    return self:Set(icon.fill, icon.spellID, short, answered)
end

-- Your power changed, or your form did: every fill showing hands the game
-- what you have now, and the game moves its own gauges. Nothing is asked for
-- while the fill is off. Your action bars' fills are in this list too, and
-- then ask the game again whether you can pay for what they hold
-- (FillBars.lua's Levels), which takes a fill away as your power reaches what
-- a spell costs and brings it back as you fall short.
local function Levels()
    if not F:On() then return end
    Powers()
    for _, parts in ipairs(fills) do
        if parts.on and parts.amount and parts.power then Hand(parts, parts.amount, have[parts.power.kind]) end
    end
    if ns.FillBars then ns.FillBars:Levels() end
end

-- The page ---------------------------------------------------------------------------------

-- A fill of its own for the page's preview: a frame with the same layers on
-- it, drawn by the page (F:Draw), so none of the real fill's work starts
-- while the fill is off.
function F:Sample(parent, size)
    local sample = CreateFrame("Frame", nil, parent)
    sample:EnableMouse(false)
    sample:SetSize(size, size)
    local parts = Build(sample)
    parts.seed = 0
    Dress(parts)
    Fit(parts, size, size)
    parts.on = true
    parts.holder:Show()
    sample.fill = parts
    return sample
end

-- The preview's own fill at a level, from the page's own clock, in one
-- power's colour (mana unless given). The level here is one the page made up,
-- a plain number of its own, so its gauges measure it against one whole.
function F:Draw(parts, level, now, power)
    if not parts.mark then return end
    Dress(parts)
    parts.colour = self:Colour(power or ns.FILL_POWERS[1])
    Hand(parts, 1, math.max(0, math.min(1, level)))
    Paint(parts, now)
end

-- Setup ------------------------------------------------------------------------------------

-- A choice changed on its page: every fill is dressed and drawn again, and
-- any that shouldn't show goes. Costs are left alone, since only a change of
-- form changes those. Turned off, nothing is left on an icon.
function F:Apply()
    local on = self:On()
    for _, parts in ipairs(fills) do
        Dress(parts)
        if not on or not parts.on then
            Clear(parts)
        else
            parts.power, parts.colour = nil, nil
            local amount, power = Payable(parts.spell)
            if not amount then Clear(parts) else Fill(parts, amount, power) end
        end
    end
    Listen()
    -- Your bars read the game's answers again, so a fill comes or goes at
    -- once instead of waiting for the next thing the game says (the icons
    -- are the addon's own, so this is safe in a fight too).
    if ns.Bars then ns.Bars:RefreshAll() end
    -- And your action bars, where that's ticked (FillBars.lua).
    if ns.FillBars then ns.FillBars:Apply() end
end

local driver
local hearing = false
-- Your power, your biggest and the power your form uses: heard only while
-- the fill is on.
local POWER_EVENTS = { "UNIT_POWER_FREQUENT", "UNIT_MAXPOWER", "UNIT_DISPLAYPOWER" }

-- Your form changed, so what your spells cost may have changed too: every
-- cost is asked again, and the levels follow.
local function Formed()
    costs = {}
    Levels()
end

local function OnEvent(_, event)
    if event == "UNIT_DISPLAYPOWER" then Formed() else Levels() end
end

Listen = function()
    local want = F:On() and driver ~= nil
    if want == hearing then return end
    hearing = want
    if want then
        for _, event in ipairs(POWER_EVENTS) do pcall(driver.RegisterUnitEvent, driver, event, "player") end
        Powers()
    else
        driver:UnregisterAllEvents()
    end
end

function F:Start()
    if self.started then return end
    self.started = true
    driver = CreateFrame("Frame")
    driver:SetScript("OnEvent", OnEvent)
    self.driver = driver
    Listen()
end

-- For the tests: whether the shared OnUpdate runs now, and how many fills it
-- draws.
function F:Running()
    return ticker ~= nil and ticker:GetScript("OnUpdate") ~= nil, living
end
