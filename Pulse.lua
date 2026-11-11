-- Cooldown pulse: the moment one of your cooldowns comes back, its icon
-- pulses in the middle of your screen: big and a little see-through, in
-- fast, a short hold, then out, growing as it goes. Several at once take
-- turns, and only a few wait, so it never floods. Off until it's ticked on
-- its page under More in /ccm (PulsePage.lua). Each cooldown pulses in one
-- of two styles, Quick or Long, each with its own size, time and sound.
--
-- Cooldowns are secret in a fight, so nothing here reads one. Each spell
-- watched has a Cooldown frame of its own that's never drawn, handed the
-- game's duration object just as your bars' icons are (Bars.lua), and the
-- game itself says when it's done (OnCooldownDone): that's the pulse. The
-- global cooldown is left out by asking for the duration without it, and
-- passed over when the game says it's all there is (isOnGCD). An
-- item's cooldown comes as plain numbers, as on your bars: one no longer
-- than the global cooldown is left out, and if the game ever hides them in
-- a fight the watcher keeps what it had. Which of your spells have a
-- cooldown comes from the game data (each spell's base cooldown,
-- ns.COOLDOWNS in Ranks.lua), never from the game in a fight; only the ones
-- you ticked are watched. A cooldown on hold (one that
-- only starts once its effect is used up, like Presence of Mind) isn't
-- counted until it starts: the game says so plainly, and Blizzard's buttons
-- ask the same (ActionButton.lua). Potions share one cooldown: one pulse;
-- trinkets each pulse for their own.
--
-- No pulse for a while after logging in, a reload or a loading screen, nor
-- for a cooldown that never ran: only one the game counted down says it's
-- done. Nor for an item you carry none of now. The pulse is the addon's own plain frame: it never takes the mouse,
-- and shows in a fight like anything that isn't secure. Nothing of
-- Blizzard's is touched.
--
-- Procs can pulse too, the moment one lands (Procs, below): the game plays
-- those itself, in its own aura container, as your Buffs bar shows your
-- buffs, so they take no turns with the cooldowns and play no sound.
--
-- Forever Enhanced Cooldown Pulse is this same pulse as an addon of its
-- own: with both installed, only one of them pulses, so a cooldown never
-- pops up twice. Whichever pulse is on keeps it; the other's on/off tick
-- greys out, its hover note saying where the pulse runs and how to swap.
-- With both saved as on, this one wins. No popups, and no reload: a change
-- in one greys or frees the other at once (the link, below).
local ADDON, ns = ...

local P = {}
ns.Pulse = P

-- The link with Forever Enhanced Cooldown Pulse: one small table in the
-- game's global space, ForeverPulseLink, made by whichever addon loads
-- first. Each addon registers itself in it by its folder name: its title, a
-- rank (the higher wins when both are on), a function saying whether its
-- own tick is on, and one to call when the other's changes. Its functions
-- come from the newest version of this code loaded, so an older copy in the
-- other addon never holds back a newer one. The same code as that addon's
-- Link.lua (Tools/TestRules.mjs checks the two match).
local LINK_VERSION = 1
local LINK_RANK = 2 -- this addon's; Forever Enhanced Cooldown Pulse's is 1
local link = _G.ForeverPulseLink
if type(link) ~= "table" then
    link = {}
    _G.ForeverPulseLink = link
end
if type(link.owners) ~= "table" then link.owners = {} end
if type(link.version) ~= "number" or link.version < LINK_VERSION then
    link.version = LINK_VERSION

    -- An addon joins (or joins again) under its folder name, and the others
    -- hear of it.
    function link:Register(key, owner)
        if type(key) ~= "string" or type(owner) ~= "table" then return end
        self.owners[key] = owner
        self:Notify(key)
    end

    -- Every other addon hears that something changed. A call that fails is
    -- passed over, so one addon's error never stops the other; one that
    -- calls back in while this runs is ignored, so it can't go round.
    function link:Notify(from)
        if self.notifying then return end
        self.notifying = true
        for key, owner in pairs(self.owners) do
            if key ~= from and type(owner) == "table" and type(owner.Refresh) == "function" then pcall(owner.Refresh) end
        end
        self.notifying = nil
    end

    -- The addon that pulses now: of those whose tick is on, the highest
    -- rank (then the first by name). Its key and entry, or nil for none.
    function link:Runner()
        local bestKey, best, bestRank
        for key, owner in pairs(self.owners) do
            if type(key) == "string" and type(owner) == "table" and type(owner.IsOn) == "function" then
                local ok, on = pcall(owner.IsOn)
                local rank = tonumber(owner.rank) or 0
                if ok and on == true and (not best or rank > bestRank or (rank == bestRank and key < bestKey)) then
                    bestKey, best, bestRank = key, owner, rank
                end
            end
        end
        return bestKey, best
    end
end

-- The addon whose pulse runs now, by folder name, and its title; nil when
-- neither pulse is on. Asked safely, whichever copy of the link's code won.
local function Runner()
    local ok, key, owner = pcall(link.Runner, link)
    if not ok or type(key) ~= "string" then return nil end
    return key, type(owner) == "table" and type(owner.name) == "string" and owner.name or key
end

-- The title of the other addon while the pulse runs there, else nil.
function P:Elsewhere()
    local key, name = Runner()
    if key and key ~= ADDON then return name end
    return nil
end

-- The on/off tick's hover note while it's greyed out, else nil.
function P:Note()
    local name = self:Elsewhere()
    if name then return "Cooldown pulse is on in " .. name .. ". Turn it off there to use this one." end
    return nil
end

-- This addon's tick changed (ns.Set): the other hears of it.
function P:Notify()
    pcall(link.Notify, link, ADDON)
end

local Style = ns.Style
local FLAT = "Interface\\Buttons\\WHITE8X8"
-- The previews' icon until you have a cooldown to show: a pocket watch.
P.SAMPLE = "Interface\\Icons\\INV_Misc_PocketWatch_01"
-- Sounds from Blizzard's own Cooldown Manager alerts, so every player has
-- them (CooldownViewerSoundAlertData.lua): from its Instruments, Devices,
-- Impacts and two older sets. Its newer "Short" set (Bell Strike, 353392)
-- played nothing in Forever.
P.SOUNDS = {
    chime = 316447, -- Chime Ascending
    bell = 316493, -- Bell Ring
    trill = 316712, -- Bell Trill
    shimmerBell = 316779, -- Shimmer Bell
    magicChimes = 316736, -- Magic Chimes
    shimmer = 316778, -- Magic Shimmer
    zippy = 316737, -- Zippy Magic
    synth = 316460, -- Synth High
    pipe = 316501, -- Pitch Pipe Note
    brass = 316722, -- Brass
    warhorn = 316723, -- Warhorn
    fanfare = 316769, -- Fanfare
    gold = 316770, -- Gold
    jackpot = 316717, -- Jackpot Bell
    anvil = 316528, -- Anvil Strike
}
P.QUIET = 2 -- seconds after logging in, a reload or a loading screen with no pulses
P.AGAIN = 3 -- the same cooldown done again this soon is the same one, told twice
P.WAITING = 3 -- pulses waiting their turn at most; any more are let go
local ITEM_GCD = 1.5 -- an item's cooldown this short is only the global cooldown
local FADE_IN, HOLD = .15, .3 -- shares of a pulse's time: in, then held; out for the rest
local SHADOW = { .55, .35, .18, .07 } -- the soft shadow's rings, from the inside out, as on your bars
local TRINKETS = { 13, 14 }
local ITEM_BARS = { "cd", "util" }

local function Open(value)
    return not (issecretvalue and issecretvalue(value))
end

-- A failure is reported once per session.
local function Report(err)
    if P.lastError then return end
    P.lastError = tostring(err)
    print("|cffffd100" .. ns.TITLE .. ":|r the cooldown pulse couldn't follow a cooldown. Please report this: " .. P.lastError)
end

-- Whether the pulse runs: ticked on, and not running in Forever Enhanced
-- Cooldown Pulse instead (with both on, this one runs).
function P:On()
    if ns.Get("pulse") ~= true then return false end
    local key = Runner()
    return key == nil or key == ADDON
end

-- The two styles, and the settings of each one's own. The rest of the look
-- (see-through, grows to, border, shadow) and the spot are shared.
P.STYLES = {
    quick = { size = "pulseSize", time = "pulseTime", sound = "pulseSound" },
    long = { size = "pulseLongSize", time = "pulseLongTime", sound = "pulseLongSound" },
}
-- The style the page shows the settings of, which its previews, Preview and
-- the box to move it use too. Quick each session.
P.editing = "quick"

local function Keys(style)
    return P.STYLES[style] or P.STYLES.quick
end

-- A cooldown's style, by its key: Long if it's been switched, else Quick.
function P:StyleOf(key)
    return ns.PulseStyles()[key] == "long" and "long" or "quick"
end

function P:Size(style)
    return ns.Get(Keys(style).size)
end

function P:Seconds(style)
    return ns.Get(Keys(style).time) / 10
end

function P:Sound(style)
    return ns.Get(Keys(style).sound)
end

-- The look --------------------------------------------------------------------------------
-- An icon with a dark border and a soft shadow round it, each a ring of
-- plain colour as on your bars, made thicker as the icon gets bigger.

local function Ring(owner, layer)
    local ring = {}
    for i = 1, 4 do
        ring[i] = owner:CreateTexture(nil, layer, nil, -8)
        ring[i]:SetColorTexture(0, 0, 0, 1)
        ring[i]:Hide()
    end
    return ring
end

-- Puts a ring `out` past region's edge, `width` thick, at this darkness.
local function Place(ring, region, out, width, alpha, shown)
    local top, bottom, left, right = ring[1], ring[2], ring[3], ring[4]
    local far = out + width
    top:ClearAllPoints()
    top:SetPoint("BOTTOMLEFT", region, "TOPLEFT", -far, out)
    top:SetPoint("BOTTOMRIGHT", region, "TOPRIGHT", far, out)
    top:SetHeight(width)
    bottom:ClearAllPoints()
    bottom:SetPoint("TOPLEFT", region, "BOTTOMLEFT", -far, -out)
    bottom:SetPoint("TOPRIGHT", region, "BOTTOMRIGHT", far, -out)
    bottom:SetHeight(width)
    left:ClearAllPoints()
    left:SetPoint("TOPRIGHT", region, "TOPLEFT", -out, out)
    left:SetPoint("BOTTOMRIGHT", region, "BOTTOMLEFT", -out, -out)
    left:SetWidth(width)
    right:ClearAllPoints()
    right:SetPoint("TOPLEFT", region, "TOPRIGHT", out, out)
    right:SetPoint("BOTTOMLEFT", region, "BOTTOMRIGHT", out, -out)
    right:SetWidth(width)
    for _, strip in ipairs(ring) do
        strip:SetColorTexture(0, 0, 0, alpha)
        strip:SetShown(shown)
    end
end

-- The icon, for the pulse and the page's previews. Takes no mouse.
function P:NewArt(parent)
    local art = CreateFrame("Frame", nil, parent)
    art:EnableMouse(false)
    art.texture = art:CreateTexture(nil, "ARTWORK")
    art.texture:SetAllPoints()
    Style:Zoom(art.texture)
    art.border = Ring(art, "BORDER")
    art.shadow = {}
    for i = 1, #SHADOW do art.shadow[i] = Ring(art, "BACKGROUND") end
    return art
end

-- How thick the border is on an icon this big (0 for none), and each of the
-- shadow's four rings: at the default size a thin border is 2, a thick one
-- 5, and the shadow 20 deep, so it looks the same at any size.
function P:Edges(size)
    local border = ns.Get("pulseBorder")
    local width = 0
    if border == "thick" then
        width = math.max(2, math.floor(size / 64 + .5))
    elseif border == "thin" then
        width = math.max(1, math.floor(size / 160 + .5))
    end
    return width, math.max(1, math.floor(size / 64 + .5))
end

-- The border and shadow as chosen, for an icon this big.
function P:Dress(art, size)
    local border, ring = self:Edges(size)
    Place(art.border, art, 0, math.max(1, border), 1, border > 0)
    local shadow = ns.Get("pulseShadow")
    for i, alpha in ipairs(SHADOW) do
        Place(art.shadow[i], art, border + (i - 1) * ring, ring, alpha, shadow)
    end
end

-- At its fullest: what isn't see-through. 80% is a tenth (the user's pick,
-- once the far end), then it fades on to 4% at 90%.
function P:Opacity()
    local see = ns.Get("pulseSeeThrough")
    if see <= 80 then return 1 - see * .01125 end
    return .1 - (see - 80) * .006
end

-- A pulse part way through (0 to 1): its share of full opacity, and its
-- size as a share of the size chosen. It fades in fast, holds, then fades
-- out, growing all the while, quickly at first.
function P:Shape(progress)
    progress = math.max(0, math.min(1, progress))
    local fade
    if progress < FADE_IN then
        fade = progress / FADE_IN
    elseif progress < FADE_IN + HOLD then
        fade = 1
    else
        fade = (1 - progress) / (1 - FADE_IN - HOLD)
    end
    local eased = 1 - (1 - progress) * (1 - progress)
    return fade, 1 + (ns.Get("pulseGrow") / 100 - 1) * eased
end

-- The pulse --------------------------------------------------------------------------------

local pulse -- the frame, made the first time one shows
local queue, showing, elapsed = {}, nil, 0

local function Frame()
    if pulse then return pulse end
    pulse = CreateFrame("Frame", "FECMPulse", UIParent)
    pulse:SetFrameStrata("HIGH")
    pulse:EnableMouse(false)
    pulse:Hide()
    pulse.art = P:NewArt(pulse)
    pulse.art:SetPoint("CENTER")
    -- Hidden with the interface (Alt+Z, a cinematic) it stops: what showed
    -- and waited is let go, not played late once the interface is back.
    pulse:SetScript("OnHide", function(self)
        wipe(queue)
        showing = nil
        self:Hide()
    end)
    pulse:SetScript("OnUpdate", function(_, dt)
        elapsed = elapsed + (dt or 0)
        local total = P:Seconds(showing and showing.style)
        if elapsed >= total then return P:Next() end
        P:Draw(elapsed / total)
    end)
    P.frame = pulse
    return pulse
end

-- The proc pulses (Procs, below): the game's aura container, its slots (each
-- with the addon's own frame it sits on, and the look made for it), what
-- each slot was last told, whether a change waits for a fight to end, a
-- failure to start, and the hush (Hush, below): when it ends, how many
-- there were, and the game refusing one.
local procs = { slots = {}, applied = {}, hushUntil = 0, hushes = 0 }

-- Each proc's frame in the pulse's spot. The addon's own frames: fine in a
-- fight, and the game's icons on them follow.
local function PlaceProcs()
    for _, slot in ipairs(procs.slots) do
        slot.holder:ClearAllPoints()
        slot.holder:SetPoint("CENTER", UIParent, "CENTER", ns.Get("pulseX"), ns.Get("pulseY"))
    end
end

-- Where it sits and how big: from the middle of the screen, as moved, at
-- the size of the style showing. The proc pulses sit there too.
function P:Place()
    PlaceProcs()
    if not pulse then return end
    local size = self:Size(showing and showing.style)
    pulse:SetSize(size, size)
    pulse:ClearAllPoints()
    pulse:SetPoint("CENTER", UIParent, "CENTER", ns.Get("pulseX"), ns.Get("pulseY"))
end

function P:Draw(progress)
    local fade, grow = self:Shape(progress)
    local size = self:Size(showing and showing.style) * grow
    pulse:SetAlpha(fade * self:Opacity())
    pulse.art:SetSize(size, size)
end

-- With Sound Effects, or at your Master volume if ticked: the game's own
-- volumes either way, never changed here.
function P:PlaySound(key)
    local kit = self.SOUNDS[key]
    if kit and PlaySound then pcall(PlaySound, kit, ns.Get("pulseMaster") and "Master" or "SFX") end
end

-- The next one waiting, or none: the frame hides.
function P:Next()
    showing = table.remove(queue, 1)
    if not showing then
        if pulse then pulse:Hide() end
        return
    end
    local frame = Frame()
    -- A preview shows over the /ccm window; a pulse in play under it and
    -- the game's dialogs.
    frame:SetFrameStrata(showing.preview and "TOOLTIP" or "HIGH")
    self:Place()
    frame.art.texture:SetTexture(showing.icon or self.SAMPLE)
    self:Dress(frame.art, self:Size(showing.style))
    elapsed = 0
    self:Draw(0)
    frame:Show()
    self:PlaySound(self:Sound(showing.style))
end

-- One more pulse, in a style (Quick unless "long"): shown now, or after the
-- ones before it. Not if it's showing or waiting already, or enough are
-- waiting. True when it's queued.
function P:Queue(icon, key, preview, style)
    if showing and showing.key == key then return false end
    for _, waiting in ipairs(queue) do
        if waiting.key == key then return false end
    end
    if #queue >= self.WAITING then return false end
    queue[#queue + 1] = { icon = icon, key = key, preview = preview, style = style == "long" and "long" or "quick" }
    if not showing then self:Next() end
    return true
end

-- What's showing and waiting, for the tests: the key showing, how many
-- wait, and the style showing.
function P:Showing()
    return showing and showing.key, #queue, showing and showing.style
end

-- Watching ---------------------------------------------------------------------------------

local holder -- the watchers' frame: shown, never drawn, takes no mouse
local watchers, spare = {}, {} -- by key; and frames let go, for the next one
local quietUntil = 0

local function Holder()
    if holder then return holder end
    -- Of its own, not UIParent's: the watchers keep time with the
    -- interface hidden (Alt+Z) too. One unit square, at the screen's corner.
    holder = CreateFrame("Frame", nil, nil)
    holder:SetSize(1, 1)
    holder:SetPoint("BOTTOMLEFT", 0, 0)
    holder:EnableMouse(false)
    holder:Show()
    P.holder = holder
    return holder
end

-- A spell's watcher that showed and finished within a global cooldown only
-- counted the global cooldown (or nothing at all): every watched spell's own
-- is longer (P:Spells), so that's no pulse. The game shows a watcher as a
-- cooldown starts (below), so a spell sitting ready that's handed a global
-- cooldown in a fight anyway shows, finishes and is passed over here.
local SHORT = 1.75
local function Started(cooldown)
    cooldown.started = GetTime()
end

-- Shooting a wand, each shot can hand a spell sitting ready a short wait of
-- its own (up to the wand's speed, past SHORT), one after the next, and the
-- spell would pulse as the wand's "cooldown" ends. So while a wand shoots,
-- and for its slowest shot after it stops, spells aren't handed anything new:
-- one already counting carries on and still pulses, and every one is fed
-- again once the shooting's over, so one started meanwhile is counted then.
-- Only a wand: a hunter's Auto Shot runs all fight, among real cooldowns.
P.WAND_TAIL = 2.6 -- seconds: the slowest wand's shot (2.4 in the game data), and a little lag
local RANGED_SLOT, WEAPON, WAND = 18, 2, 19 -- the slot; the item class and subclass
local wanding, wandUntil = false, 0

local function WandWorn()
    local id = GetInventoryItemID("player", RANGED_SLOT)
    if not (Open(id) and id and C_Item and C_Item.GetItemInfoInstant) then return false end
    local _, _, _, _, _, class, subclass = C_Item.GetItemInfoInstant(id)
    return Open(class) and Open(subclass) and class == WEAPON and subclass == WAND
end

function P:Wanding()
    return wanding or GetTime() < wandUntil
end

local function Done(cooldown)
    local watch = cooldown.watch
    if watch and watch.spellID and cooldown.started and GetTime() - cooldown.started <= SHORT then return end
    P:Done(watch)
end

-- A Cooldown frame that only keeps time: no sweep, edge, flash or numbers.
-- Blizzard's own template, as your bars' icons use: the game shows it as a
-- cooldown starts and hides it as it ends, on a frame that stays shown, so
-- it's never left waiting on a hidden one.
local function Watcher()
    local cooldown = table.remove(spare)
    if cooldown then return cooldown end
    cooldown = CreateFrame("Cooldown", nil, Holder(), "CooldownFrameTemplate")
    cooldown:SetAllPoints()
    cooldown:EnableMouse(false)
    cooldown:SetDrawSwipe(false)
    cooldown:SetDrawEdge(false)
    cooldown:SetDrawBling(false)
    cooldown:SetHideCountdownNumbers(true)
    cooldown:SetScript("OnCooldownDone", Done)
    cooldown:SetScript("OnShow", Started)
    return cooldown
end

-- A spell's base cooldown in seconds, from the game data, or 0. One the data
-- doesn't cover (a profession's, or a later build's) is asked of the game,
-- if it has a way and answers plainly.
local covered
function P:BaseCooldown(spellID)
    if type(spellID) ~= "number" then return 0 end
    local seconds = ns.COOLDOWNS and ns.COOLDOWNS[spellID]
    if seconds then return seconds end
    if not covered then
        covered = {}
        for _, ids in pairs(ns.RANKS or {}) do
            for _, id in ipairs(ids) do covered[id] = true end
        end
    end
    local api = _G.GetSpellBaseCooldown
    if covered[spellID] or not api then return 0 end
    local ok, ms = pcall(api, spellID)
    if ok and Open(ms) and type(ms) == "number" and ms > 0 then return ms / 1000 end
    return 0
end

-- Every spell you know with a cooldown of its own (longer than the global
-- cooldown, like Power Word: Shield's 4 seconds), by name: your
-- spellbook's, at your highest rank, not ones added to a bar by name. New
-- ones join as you learn them. Each is on once you tick it.
function P:Spells()
    local list = ns.Spells:Fresh()
    local found, picks = {}, ns.PulsePicks()
    for _, entry in ipairs(list) do
        if entry.kind == "spell" and not entry.added and entry.spellID then
            local base = self:BaseCooldown(entry.spellID)
            if base > ITEM_GCD then
                found[#found + 1] = { key = entry.key, name = entry.name, icon = entry.icon, spellID = entry.spellID, base = base,
                    on = picks[entry.key] == true }
            end
        end
    end
    table.sort(found, function(a, b) return a.name < b.name end)
    return found
end

-- Whether an item has a use (a trinket that only gives stats has none):
-- unknown counts as one.
local function HasUse(itemID)
    if not (C_Item and C_Item.GetItemSpell) then return true end
    local spell = C_Item.GetItemSpell(itemID)
    return not Open(spell) or spell ~= nil
end

-- Your two trinkets with a use, your healthstones and potions (each the
-- best one you carry), then items with a use in your bags or on your
-- Cooldowns or Utility bar: no need to put one on a bar to pulse it (the
-- user). Each is on once you tick it. carried says whether you carry any of
-- a healthstone or potion family now (nil for the rest, or while the game
-- won't say), as Forever Enhanced Cooldown Pulse's list does.
function P:Items()
    local found, seen, picks, onBar = {}, {}, ns.PulsePicks(), {}
    -- On any of a bar's lists: each form's too (Swap with my form).
    for _, bar in ipairs(ITEM_BARS) do
        for _, spells in ipairs(ns.BarLists(bar)) do
            for _, key in ipairs(spells) do onBar[key] = true end
        end
    end
    local function Take(entry)
        if not (entry and entry.itemID) or seen[entry.key] then return end
        if entry.kind ~= "slot" and entry.kind ~= "item" and entry.kind ~= "family" then return end
        if entry.kind == "slot" and not HasUse(entry.itemID) then return end
        local wanted = onBar[entry.key] or picks[entry.key]
        -- Not an and/or: that would turn false (none carried) into nil.
        local carried
        if entry.kind == "family" then carried = ns.Spells:Carries(entry) end
        -- A healthstone or potion you carry none of shows only if it's wanted.
        if entry.kind == "family" and not wanted and carried == false then return end
        -- A potion or healthstone in your bags is its family's row already
        -- (Healing Potions for a Minor Healing Potion), unless it's wanted on
        -- its own: on a bar by itself, or ticked.
        local family = entry.kind == "item" and ns.Spells:Family(entry.itemID)
        if family and seen[family.key] and not wanted then return end
        seen[entry.key] = true
        found[#found + 1] = { key = entry.key, name = entry.name, icon = entry.icon, itemID = entry.itemID,
            slot = entry.kind == "slot" and entry.slot or nil, bar = onBar[entry.key] == true, carried = carried,
            on = picks[entry.key] == true }
    end
    for _, slot in ipairs(TRINKETS) do Take(ns.Spells:Find("slot:" .. slot)) end
    local list = ns.Spells:Fresh()
    -- Families first, so a potion in your bags always finds its family's
    -- row: one only on a bar comes last (Mana Potions for a warrior).
    for _, entry in ipairs(list) do
        if entry.kind == "family" then Take(entry) end
    end
    for _, entry in ipairs(list) do Take(entry) end
    return found
end

-- A ticked bag item back in your bags after you ran out of it: your bags
-- are read again (the bars only read them while /ccm is open).
local function PickBack()
    if not (P:On() and ns.Get("pulseItems")) then return false end
    for key in pairs(ns.PulsePicks()) do
        local id = tonumber(key:match("^item:(%d+)$"))
        if id and not ns.Spells:Find(key) then
            local count = C_Item.GetItemCount(id, false, true)
            if Open(count) and type(count) == "number" and count > 0 then return true end
        end
    end
    return false
end

-- Everything that pulses now: the spells ticked, then the items ticked.
function P:Watched()
    local watched = {}
    for _, list in ipairs({ self:Spells(), ns.Get("pulseItems") and self:Items() or {} }) do
        for _, entry in ipairs(list) do
            if entry.on then watched[#watched + 1] = entry end
        end
    end
    return watched
end

-- A watcher's cooldown cleared: one on hold, or only the global cooldown.
-- The game can answer a Clear with OnCooldownDone, and that's no cooldown
-- coming back, so the watcher is let go of meanwhile (a cooldown that ends
-- by itself still says so as it ends). From Forever Enhanced Cooldown Pulse.
local function Clear(watch)
    local cooldown = watch.cooldown
    cooldown.watch = nil
    cooldown:Clear()
    cooldown.watch = watch
end

local function Feed(watch)
    local cooldown = watch.cooldown
    if watch.spellID then
        if P:Wanding() then return end
        -- On hold, it hasn't started: nothing to count yet. Never secret
        -- (SpellSharedDocumentation.lua), so it's asked plainly.
        local info = C_Spell.GetSpellCooldown and C_Spell.GetSpellCooldown(watch.spellID)
        if type(info) == "table" and Open(info.isEnabled) and info.isEnabled == false then
            Clear(watch)
            return
        end
        -- Only the global cooldown: nothing of its own to count, so the
        -- watcher keeps what it had, as Blizzard's own cooldown viewer and
        -- broadcaster pass these over. Asked for without it (below), the game
        -- can still hand it over in a fight, and a spell sitting ready would
        -- pulse after every global cooldown. Never secret either. One of its
        -- own ending under a global cooldown still says so as it ends.
        if type(info) == "table" and Open(info.isOnGCD) and info.isOnGCD == true then return end
        -- Without the global cooldown. Secret in a fight: handed on as it is.
        local duration = C_Spell.GetSpellCooldownDuration and C_Spell.GetSpellCooldownDuration(watch.spellID, true)
        if duration then cooldown:SetCooldownFromDurationObject(duration) else Clear(watch) end
        return
    end
    local start, length, enable
    if watch.slot then
        start, length, enable = GetInventoryItemCooldown("player", watch.slot)
    else
        start, length, enable = C_Item.GetItemCooldown(watch.itemID)
    end
    if not (Open(start) and Open(length) and Open(enable) and type(start) == "number" and type(length) == "number") then return end
    -- Not enabled (0 or false) is on hold, as Blizzard's own read it (Cooldown.lua).
    if start > 0 and length > ITEM_GCD and enable and enable ~= 0 then
        cooldown:SetCooldown(start, length)
        -- Bag items sharing a cooldown (every potion) share this, so they
        -- pulse once. Kept once cleared, so it still names this one when
        -- it's done. Not a trinket: two used at once (or one and a potion)
        -- run their own cooldowns, each with its own pulse.
        if not watch.slot then watch.shared = start .. ":" .. length end
    else
        Clear(watch)
    end
end

-- Every watcher handed its cooldown as it stands now.
function P:Feed()
    for _, watch in pairs(watchers) do
        local ok, err = pcall(Feed, watch)
        if not ok then Report(err) end
    end
end

-- Watchers for what pulses now (none while it's off): kept for what still
-- does, so a cooldown counting down carries on, let go for the rest, then
-- every one fed. Then the procs ticked (P:ApplyProcs).
local built -- the read of your spells and items the watchers were last made from

function P:Rebuild()
    local want = {}
    built = nil
    if self:On() then
        for _, entry in ipairs(self:Watched()) do want[entry.key] = entry end
        built = ns.Spells:Reads()
    end
    for key, watch in pairs(watchers) do
        if not want[key] then
            -- Let go first, so whatever its frame says from now on is ignored.
            watch.cooldown.watch = nil
            watch.cooldown:Clear()
            spare[#spare + 1] = watch.cooldown
            watchers[key] = nil
        end
    end
    for key, entry in pairs(want) do
        local watch = watchers[key]
        if not watch then
            watch = { cooldown = Watcher() }
            watch.cooldown.watch = watch
            watchers[key] = watch
        end
        watch.key, watch.icon = key, entry.icon
        watch.spellID, watch.itemID, watch.slot = entry.spellID, entry.itemID, entry.slot
    end
    self:Feed()
    self:ApplyProcs()
end

-- Your bags changed and nothing else: what's watched stays the same unless
-- the list of your spells and items was read again since (or waits to be),
-- so only the items are looked at again (a healthstone or potion family
-- moves on to the one you carry, its icon with it), then every watcher fed.
-- Your spells wait for your spellbook to change, or a tick. A family is
-- moved on here, as Forever Enhanced Cooldown Pulse's pulse does, not left
-- to your bars: with them off, or the family on none of them, nothing else
-- would.
function P:Restock()
    if built == nil or ns.Spells:Changed(built) then return self:Rebuild() end
    for key, watch in pairs(watchers) do
        if watch.itemID and not watch.slot then
            local entry = ns.Spells:Find(key)
            if entry then
                if entry.family then ns.Spells:Pick(entry) end
                watch.icon, watch.itemID = entry.icon, entry.itemID
            end
        end
    end
    self:Feed()
end

-- How many cooldowns are watched now, and each one's watcher by key, for the tests.
function P:Watchers()
    local count = 0
    for _ in pairs(watchers) do count = count + 1 end
    return count, watchers
end

-- Whether an item is worn in a trinket slot that's watched itself: a
-- trinket put on a bar from your bags before you wore it is still that
-- item on the bar, and the slot's pulse is its pulse.
local function SlotWatched(itemID)
    for _, slot in ipairs(TRINKETS) do
        local worn = GetInventoryItemID("player", slot)
        if Open(worn) and worn == itemID and watchers["slot:" .. slot] then return true end
    end
    return false
end

-- The game says a watched cooldown is done: it pulses in its style, unless
-- it's off, the interface is hidden, it's just after a login, reload or
-- loading screen, this one was only just told, or it's an item you carry
-- none of now (your bars hide it too; unknown still pulses), or a trinket
-- whose slot pulses for it. A bag item no longer listed (the list read
-- again since its watcher was made, say as your bars were laid out again
-- after a change to one) is asked about by its own ID, as Forever Enhanced
-- Cooldown Pulse's is. Items sharing a cooldown pulse once: the second
-- finds the first showing.
function P:Done(watch)
    if not (watch and self:On()) then return end
    local now = GetTime()
    if now < quietUntil then return end
    if watch.last and now - watch.last < self.AGAIN then return end
    watch.last = now
    if UIParent and not UIParent:IsVisible() then return end
    if watch.itemID and not watch.slot
        and ns.Spells:Carries(ns.Spells:Find(watch.key) or { kind = "item", itemID = watch.itemID }) == false then
        return
    end
    if watch.itemID and not watch.slot and SlotWatched(watch.itemID) then return end
    self:Queue(watch.icon, watch.shared and ("cd:" .. watch.shared) or watch.key, nil, self:StyleOf(watch.key))
end

-- An icon to show: the first cooldown you have that pulses, or the watch.
function P:SampleIcon()
    local watched = self:Watched()
    return watched[1] and watched[1].icon or self.SAMPLE
end

-- A pulse now in the style the page shows, with your choices, whether it's on or not.
-- One of the other style showing makes way for it; one waiting plays this one.
function P:Preview()
    local style = self.editing == "long" and "long" or "quick"
    if showing and showing.preview and showing.style ~= style then
        table.insert(queue, 1, { icon = self:SampleIcon(), key = "preview", preview = true, style = style })
        self:Next()
        return true
    end
    for _, waiting in ipairs(queue) do
        if waiting.preview then waiting.style = style end
    end
    return self:Queue(self:SampleIcon(), "preview", true, style)
end

-- Procs ------------------------------------------------------------------------------------
-- A pulse the moment a proc's buff lands. Your buffs are secret in a fight
-- and the addon never reads one, so the game does the work: Blizzard's
-- secure aura container, as your Buffs bar uses (Buffs.lua),
-- is told out of a fight which buffs go in which slot, one slot per proc
-- ticked. Each slot's icon is the pulse's own look, see-through, with one
-- animation handed to the game, which plays it as the icon comes into sight
-- (Blizzard_CustomAuraButton.lua ApplyVisibility): in fast, a hold, then
-- out, growing as it goes, as the pulse does. So it pulses as the proc lands
-- while it isn't up; refreshed, stacking or replaced while up, it doesn't
-- pulse again. One already up would pulse again whenever the container
-- looks at all your buffs afresh, so those moments are hushed (Hush, below).
-- Used up before the pulse ends, its icon goes and the pulse with it. No
-- sound and no turns with the cooldowns: the addon never hears one land.
-- The look is made only as a slot is added (Buffs.lua F.Add and F.Guard),
-- nothing of the addon's runs as the game plays it (no scripts), and
-- nothing is written on the game's icons or container; of the container
-- only its see-through changes (Hush). A change made in a fight waits for
-- it to end. Off until "Procs too" is ticked.

-- Each class's procs, each a list of its buff's IDs (the first is its key,
-- name and icon): your Buffs bar's (Spells.lua S.PROCS), and every buff a
-- talent of the class puts on you (Ranks.lua PASSIVE_BUFFS) that the game
-- data (build 70888: SpellEffect, SpellMisc, SpellDuration) makes an aura on
-- yourself (effect 6, target 1) lasting 1 to 60 seconds. Left out: Divine
-- Aegis and Inspiration (on whoever you heal), Frenzy (your pet's), Spirit
-- of Redemption, Furor, and anything that lasts. Run that check again with
-- each build. The same as Forever Enhanced Cooldown Pulse's, line for line
-- (Tools/TestRules.mjs checks the two match).
P.PROCS = {
    DRUID = { { 16870 }, { 16886 }, { 408255 } }, -- Clearcasting, Nature's Grace, Eclipse
    HUNTER = { { 6150 }, { 415407 }, { 1242512 }, { 1242688 }, { 1310726 } }, -- Quick Shots, Rapid Killing, Rapid Recuperation, Resourcefulness, Expose Prey
    MAGE = { { 12536 }, { 400589, 1326083 }, { 400625 }, { 400670 } }, -- Clearcasting, Missile Barrage, Heating Up, Fingers of Frost
    PALADIN = { { 20050 }, { 20128 }, { 53672, 437063 }, { 20272 }, { 1311033 }, { 1328551 }, { 440668 } }, -- Vengeance, Redoubt, Infusion of Light, Illumination, Iron Creed, Shieldsworn, Vindication
    PRIEST = { { 15271 }, { 1326168 }, { 27813 } }, -- Spirit Tap, Dark Inspiration, Blessed Recovery
    ROGUE = { { 14143 }, { 1329282 }, { 1310703 } }, -- Remorseless, Quick Getaway, Venom
    SHAMAN = { { 16246 }, { 16257 }, { 408505 }, { 30165 }, { 1238931 }, { 415144 } }, -- Clearcasting, Flurry, Maelstrom Weapon, Elemental Devastation, Improved Stormstrike, Mental Dexterity
    WARLOCK = { { 17941 }, { 440873 }, { 1242853 } }, -- Shadow Trance, Decimation, Soul Harvest
    WARRIOR = { { 12966 }, { 12880 }, { 16488 }, { 1323969 } }, -- Flurry, Enrage, Blood Craze, Gore Drinker
}
-- Each side of a ring (Ring: top, bottom, left, right): the way from a
-- strip's own middle to the icon's.
local SIDES = { { 0, -1 }, { 0, 1 }, { 1, 0 }, { -1, 0 } }

-- Whether the game has the containers proc pulses need.
function P:CanProcs()
    return CustomAuraContainerSlotDefaultOptions ~= nil
end

-- Whether proc pulses run: ticked on, with the pulse on and running here.
function P:ProcsOn()
    return ns.Get("pulseProcs") == true and self:On() and self:CanProcs()
end

-- Your class's procs, by name: each one's key ("proc:" and its first buff
-- ID, the same in every language, and never a spell's name), name, icon,
-- buff IDs, whether it's ticked and its style. One the game has no name for
-- is left out.
function P:Procs()
    local _, class = UnitClass("player")
    local found, picks = {}, ns.PulsePicks()
    if not (Open(class) and type(class) == "string") then return found end
    for _, ids in ipairs(self.PROCS[class] or {}) do
        local name = C_Spell.GetSpellName and C_Spell.GetSpellName(ids[1])
        local icon = C_Spell.GetSpellTexture and C_Spell.GetSpellTexture(ids[1])
        if Open(name) and type(name) == "string" and name ~= "" then
            local key = "proc:" .. ids[1]
            found[#found + 1] = { key = key, name = name, icon = Open(icon) and icon or nil, ids = ids, on = picks[key] == true,
                style = self:StyleOf(key) }
        end
    end
    table.sort(found, function(a, b) return a.name < b.name end)
    return found
end

-- What a proc's pulse looks like in a style, with your choices, to tell
-- whether a slot needs tuning again.
local function Look(style)
    return table.concat({ P:Size(style), P:Seconds(style), P:Opacity(), ns.Get("pulseGrow"), tostring(ns.Get("pulseBorder")),
        tostring(ns.Get("pulseShadow")) }, " ")
end

-- A slot's pulse in a style, with your choices: its border and shadow as
-- chosen, then each texture's fades (in, held, out, as P:Shape) and its
-- grow, from the icon's middle, so the rings grow with it. Never its
-- textures' alpha: the game's once handed over.
local function Tune(slot, style)
    local size, total = P:Size(style), P:Seconds(style)
    local opacity, grow = P:Opacity(), ns.Get("pulseGrow") / 100
    local border, ring = P:Edges(size)
    P:Dress(slot.art, size)
    for _, part in ipairs(slot.parts) do
        local fadeIn, hold, out, scale = part[1], part[2], part[3], part[4]
        fadeIn:SetFromAlpha(0)
        fadeIn:SetToAlpha(opacity)
        fadeIn:SetStartDelay(0)
        fadeIn:SetDuration(FADE_IN * total)
        hold:SetFromAlpha(opacity)
        hold:SetToAlpha(opacity)
        hold:SetStartDelay(FADE_IN * total)
        hold:SetDuration(HOLD * total)
        out:SetFromAlpha(opacity)
        out:SetToAlpha(0)
        out:SetStartDelay((FADE_IN + HOLD) * total)
        out:SetDuration((1 - FADE_IN - HOLD) * total)
        -- A strip's middle is this far out from the icon's (P:Dress: the
        -- border's ring at the edge, each of the shadow's past it).
        local reach, side = 0, SIDES[part.side] or { 0, 0 }
        if part.ring == 0 then
            reach = size / 2 + math.max(1, border) / 2
        elseif part.ring then
            reach = size / 2 + border + (part.ring - 1) * ring + ring / 2
        end
        scale:SetScaleFrom(1, 1)
        scale:SetScaleTo(grow, grow)
        scale:SetStartDelay(0)
        scale:SetDuration(total)
        scale:SetOrigin("CENTER", side[1] * reach, side[2] * reach)
    end
    slot.look = Look(style)
end

-- A slot's look, made as the game adds the slot (and never later: F.Guard):
-- on its frame, taking no mouse, the pulse's icon with its border and
-- shadow, every texture see-through, and one animation group handed to the
-- game. What's made is kept in slot, nothing written on the game's icon.
local function ProcLook(slot)
    return function(button)
        button:EnableMouse(false)
        button:SetAllPoints(slot.holder)
        local art = P:NewArt(button)
        art:SetAllPoints(button)
        button:SetIcon(art.texture)
        local group = art:CreateAnimationGroup()
        slot.button, slot.art, slot.group, slot.parts = button, art, group, {}
        -- Each texture fades in, holds and out, and grows: plain animations
        -- side by side, no scripts.
        local function Part(texture, side, ring)
            texture:SetAlpha(0)
            local part = { texture = texture, side = side, ring = ring }
            for i, kind in ipairs({ "Alpha", "Alpha", "Alpha", "Scale" }) do
                local animation = group:CreateAnimation(kind)
                animation:SetTarget(texture)
                animation:SetOrder(1)
                part[i] = animation
            end
            part[4]:SetSmoothing("OUT")
            slot.parts[#slot.parts + 1] = part
        end
        Part(art.texture)
        for side, strip in ipairs(art.border) do Part(strip, side, 0) end
        for i, shadow in ipairs(art.shadow) do
            for side, strip in ipairs(shadow) do Part(strip, side, i) end
        end
        Tune(slot, slot.style)
        -- If the game won't take it, the icon stays see-through: nothing shows.
        local ok, err = pcall(button.AddAuraShownAnimation, button, group)
        slot.taken, slot.error = ok, not ok and tostring(err) or nil
    end
end

-- Hushed: the container looks at all your buffs afresh, hiding every icon
-- showing and showing it again (UpdateAllAuras, Blizzard_CustomAuraContainer.lua
-- and Blizzard_ManagedAuraContainer.lua), as a fight starts or ends, on a
-- stun, fear or mount, and as your PvP flag changes (UNIT_FLAGS and
-- UNIT_FACTION, which it hears for you once told buff IDs:
-- Blizzard_AuraContainerUtil.lua AppendCandidateFilterUnitEvents), after a
-- loading screen, with the interface back after Alt+Z, and as its slots
-- are made or changed (after logging in or a reload too). Each time, a proc
-- already up would pulse again, and nothing tells that from one landing. So
-- from each of those the container is see-through for as long as a pulse
-- lasts (the longest style of the procs on), after a loading screen or a
-- change to the slots for the cooldown pulse's quiet (P.QUIET) too. The
-- cost: a proc landing then shows only the end of its pulse, or nothing.
-- Only the container's see-through changes, never its icons. If the game
-- refuses it, the replays show as before, and /ccm debug says so.
local HUSH_PAD = .25 -- a moment more: the game replays it on its next frame

-- How long the longest pulse of the procs on lasts (Quick's with none on).
local function Longest()
    local longest = 0
    for i, slot in ipairs(procs.slots) do
        if procs.applied[i] ~= nil and procs.applied[i] ~= "" then longest = math.max(longest, P:Seconds(slot.style)) end
    end
    return longest > 0 and longest or P:Seconds("quick")
end

-- The container see-through (0) or not (1); a refusal kept for /ccm debug.
local function Fade(alpha)
    local ok, err = pcall(procs.container.SetAlpha, procs.container, alpha)
    if not ok then procs.hushError = procs.hushError or tostring(err) end
end

-- The hush over once its time is up, or looked at again then.
local function Unhush()
    local left = procs.hushUntil - GetTime()
    if left > 0 then
        C_Timer.After(left, Unhush)
        return
    end
    procs.timing = nil
    Fade(1)
end

-- Hushed from now, for as long as a pulse lasts and extra seconds more.
local function Hush(extra)
    if not procs.container then return end
    procs.hushUntil = math.max(procs.hushUntil, GetTime() + extra + Longest() + HUSH_PAD)
    procs.hushes = procs.hushes + 1
    Fade(0)
    if not procs.timing then
        procs.timing = true
        C_Timer.After(procs.hushUntil - GetTime(), Unhush)
    end
end

-- What hushes it, heard on a frame of the addon's own in the interface:
-- your flags and faction, a loading screen, and the interface coming back
-- (shown with it, the frame hears OnShow). Never a hook on the game's frames.
local function Watch()
    local watch = CreateFrame("Frame", nil, UIParent)
    watch:SetSize(1, 1)
    watch:SetPoint("BOTTOMLEFT")
    watch:RegisterUnitEvent("UNIT_FLAGS", "player")
    watch:RegisterUnitEvent("UNIT_FACTION", "player")
    watch:RegisterEvent("PLAYER_ENTERING_WORLD")
    watch:SetScript("OnEvent", function(_, event, unit)
        if event == "PLAYER_ENTERING_WORLD" then
            Hush(P.QUIET)
        elseif unit == "player" then
            Hush(0)
        end
    end)
    watch:SetScript("OnShow", function() Hush(0) end)
    P.procWatch = watch
end

-- The container, made once, never in a fight: the player's, high up, taking
-- no mouse, with no stand-in auras in Edit Mode (they'd pulse). Then what
-- hushes it (Watch).
local function Container()
    if procs.container then return procs.container end
    local container = CreateFrame("AuraContainer", nil, UIParent, "CustomAuraContainerTemplate")
    container:SetPoint("CENTER")
    container:SetSize(1, 1)
    container:EnableMouse(false)
    container:SetFrameStrata("HIGH")
    container:SetEditModePreviewEnabled(false)
    container:SetUnit("player")
    procs.container = container
    Watch()
    return container
end

-- Slot i ("p1", "p2" ...), made the first time it's wanted: its frame, then
-- the slot, switched off until it's told its proc.
local function Slot(i, style)
    if procs.slots[i] then return procs.slots[i] end
    local slot = { name = "p" .. i, style = style }
    slot.holder = CreateFrame("Frame", nil, UIParent)
    slot.holder:EnableMouse(false)
    slot.holder:SetSize(P:Size(style), P:Size(style))
    ns.BuffBar.Add(procs.container, "AddAuraSlot", slot.name, "HELPFUL", { initializeFrame = ns.BuffBar.Guard(ProcLook(slot)) })
    procs.container:SetAuraSlotEnabled(slot.name, false)
    procs.slots[i] = slot
    return slot
end

-- Each slot told its proc (the ones wanted, in order) or switched off, only
-- when that changed; each sized and tuned for its proc's style. Anything
-- told, the game looks at all your buffs afresh: hushed (Hush).
local function Assign(wanted)
    Container()
    for i, entry in ipairs(wanted) do Slot(i, entry.style) end
    local told = false
    for i, slot in ipairs(procs.slots) do
        local entry = wanted[i]
        if entry then
            slot.style = entry.style
            slot.holder:SetSize(P:Size(entry.style), P:Size(entry.style))
            -- The game may not let a handed animation change: then a
            -- reload, which makes the slots again, brings the change.
            if slot.art and slot.look ~= Look(entry.style) then
                local tuned, why = pcall(Tune, slot, entry.style)
                if not tuned then slot.retuneError = tostring(why) end
            end
        end
        local signature = entry and (entry.key .. ":" .. table.concat(entry.ids, ",")) or ""
        if procs.applied[i] ~= signature then
            procs.applied[i], told = signature, true
            if entry then
                local ids = {}
                for _, id in ipairs(entry.ids) do ids[id] = true end
                procs.container:SetAuraSlotCandidateFilters(slot.name, { includeSpellIDs = ids })
                procs.container:SetAuraSlotEnabled(slot.name, true)
            else
                procs.container:SetAuraSlotEnabled(slot.name, false)
            end
        end
    end
    if told then Hush(P.QUIET) end
    PlaceProcs()
end

-- The procs ticked, told to the game (none while proc pulses are off, or
-- the pulse runs in Forever Enhanced Cooldown Pulse). Never in a fight: then
-- it waits for it to end. Nothing is made until a proc is ticked; a failure
-- is reported once, and proc pulses stop for the session.
function P:ApplyProcs()
    if InCombatLockdown() then
        procs.pending = true
        return
    end
    procs.pending = nil
    if procs.error then return end
    local wanted = {}
    if self:ProcsOn() then
        for _, entry in ipairs(self:Procs()) do
            if entry.on then wanted[#wanted + 1] = entry end
        end
    end
    if not procs.container and #wanted == 0 then return end
    local ok, err = pcall(Assign, wanted)
    if not ok then
        procs.error = tostring(err)
        print("|cffffd100" .. ns.TITLE .. ":|r proc pulses couldn't start. Please report this: " .. procs.error)
    end
end

-- One line for /ccm debug: the procs ticked, whether proc pulses run and
-- the game can show them, the slots made and switched on, how many the
-- game took the pulse for, a retune it refused, a change waiting for a
-- fight to end, how many times it was hushed and whether the game refused
-- that, whether the game keeps each ticked proc secret (C_Secrets: whether
-- a sound could ever follow one), and any failure.
function P:ProcReport(Add)
    local ticked, secret = 0, {}
    local ask = C_Secrets and C_Secrets.ShouldSpellAuraBeSecret
    for _, entry in ipairs(self:Procs()) do
        if entry.on then
            ticked = ticked + 1
            local ok, value = false, nil
            if ask then ok, value = pcall(ask, entry.ids[1]) end
            local said = "?"
            if ok and Open(value) and type(value) == "boolean" then said = tostring(value) end
            secret[#secret + 1] = entry.name .. " " .. said
        end
    end
    local on, taken, refused, failed = 0, 0, nil, procs.error
    for i, slot in ipairs(procs.slots) do
        if procs.applied[i] and procs.applied[i] ~= "" then on = on + 1 end
        if slot.taken then taken = taken + 1 end
        refused = refused or slot.retuneError
        failed = failed or slot.error
    end
    Add(("Proc pulse: ticked %d, on %s, game can %s | slots made %d, on %d, taken %d/%d, retune refused %s | pending %s"
        .. " | hushed %d, hush refused %s | secret: %s | error %s"):format(ticked, tostring(self:ProcsOn()), tostring(self:CanProcs()),
        #procs.slots, on, taken, #procs.slots, refused or "no", tostring(procs.pending == true), procs.hushes, procs.hushError or "no",
        #secret > 0 and table.concat(secret, ", ") or "none", failed or "none"))
end

-- Moving it -------------------------------------------------------------------------------
-- A box the pulse's size, to drag where you want it. The /ccm window steps
-- aside meanwhile; Done (or a right-click) brings it back. A fight ends the
-- move, where it is, so the box never sits in the way in one.

local mover

-- Lets go of the box mid-drag, where it is now, as your bars do: hidden, it
-- would never hear the mouse let go. Kept out of the game's own layout.
local function Drop(frame)
    if not frame.dragging then return end
    frame.dragging = nil
    frame:StopMovingOrSizing()
    if frame.SetUserPlaced then frame:SetUserPlaced(false) end
    P:Moved(frame)
end

local function Mover()
    if mover then return mover end
    local T = ns.Theme
    mover = CreateFrame("Frame", "FECMPulseMover", UIParent, "BackdropTemplate")
    mover:SetFrameStrata("DIALOG")
    mover:SetClampedToScreen(true)
    mover:SetMovable(true)
    mover:EnableMouse(true)
    mover:RegisterForDrag("LeftButton")
    T:Flat(mover, { 0, 0, 0, .35 }, T.CONTROL_BORDER)
    T:Paint(function(accent) mover:SetBackdropBorderColor(accent[1], accent[2], accent[3], 1) end)
    mover.icon = mover:CreateTexture(nil, "ARTWORK")
    mover.icon:SetPoint("TOPLEFT", 1, -1)
    mover.icon:SetPoint("BOTTOMRIGHT", -1, 1)
    mover.icon:SetAlpha(.3)
    Style:Zoom(mover.icon)
    -- Above and below the box, so they fit at any size.
    mover.title = T:Heading(mover, "Cooldown pulse")
    mover.title:SetPoint("BOTTOM", mover, "TOP", 0, 6)
    mover.title:SetJustifyH("CENTER")
    mover.done = T:Button(mover, "Done", 80, 22)
    mover.done:SetPoint("TOP", mover, "BOTTOM", 0, -6)
    mover.done:SetScript("OnClick", function() P:StopMove(true) end)
    mover.note = T:Text(mover, "GameFontHighlightSmall")
    mover.note:SetPoint("TOP", mover.done, "BOTTOM", 0, -4)
    mover.note:SetJustifyH("CENTER")
    mover.note:SetText("Drag the box, then click Done or right-click it.")
    mover:SetScript("OnDragStart", function(self)
        self.dragging = true
        self:StartMoving()
    end)
    -- Right-click finishes too, should Done be off the screen's edge.
    mover:SetScript("OnMouseUp", function(_, button)
        if button == "RightButton" then P:StopMove(true) end
    end)
    mover:SetScript("OnDragStop", Drop)
    mover:Hide()
    P.mover = mover
    return mover
end

-- As big as the style the page shows; both styles share the spot.
local function PlaceMover()
    local size = P:Size(P.editing)
    mover:SetSize(size, size)
    mover:ClearAllPoints()
    mover:SetPoint("CENTER", UIParent, "CENTER", ns.Get("pulseX"), ns.Get("pulseY"))
end

local function Within(value)
    local limits = ns.PULSE_PLACE
    return math.max(limits[1], math.min(limits[2], math.floor(value + .5)))
end

-- Let go: the box's middle from the screen's is the pulse's new spot.
function P:Moved(frame)
    local x, y = frame:GetCenter()
    local cx, cy = UIParent:GetCenter()
    if not (x and y and cx and cy) then return end
    ns.Set("pulseX", Within(x - cx))
    ns.Set("pulseY", Within(y - cy))
    PlaceMover()
    self:Place()
end

-- Shows the box, out of a fight: true, or false and why not.
function P:StartMove()
    if InCombatLockdown() then return false, "Finish the fight first, then move it." end
    Mover()
    PlaceMover()
    mover.icon:SetTexture(self:SampleIcon())
    mover:Show()
    if ns.window then ns.window:Hide() end
    return true
end

-- Hides the box; reopen brings the /ccm window back on this page.
function P:StopMove(reopen)
    if mover then
        Drop(mover)
        mover:Hide()
    end
    if reopen and ns.ShowWindow then
        ns.ShowWindow()
        if ns.window then ns.window:Select("pulse") end
    end
end

function P:Moving()
    return mover ~= nil and mover:IsShown()
end

-- Back to the middle of the screen.
function P:ResetPlace()
    ns.Set("pulseX", 0)
    ns.Set("pulseY", 0)
    if self:Moving() then PlaceMover() end
    self:Place()
end

-- Setup -----------------------------------------------------------------------------------

-- A choice changed on the page: what's watched (the procs too, P:Rebuild),
-- and where and how big the pulse is.
function P:Apply()
    self:Rebuild()
    self:Place()
    if self:Moving() then PlaceMover() end
end

local driver
local work = {}

-- Done once on the next frame, however many events asked. Your spellbook,
-- gear or level changed, or a ticked bag item is back: the list of your
-- spells and items is noted as changed as the event comes, and read again
-- once, by whatever wants it first (the pulse while it's on, your bars, the
-- /ccm window), not by each. The window shows what's new. Only your bags
-- changed: only the items are looked at again (P:Restock).
local function Work(self)
    self:SetScript("OnUpdate", nil)
    local scan, rebuild, bags, feed = work.scan, work.rebuild, work.bags, work.feed
    work.scan, work.rebuild, work.bags, work.feed = nil, nil, nil, nil
    if rebuild then
        P:Rebuild()
    elseif bags then
        P:Restock()
    elseif feed then
        P:Feed()
    end
    if scan and ns.window ~= nil and ns.window:IsShown() then ns.window:Refresh() end
end

local function Soon(what)
    work[what] = true
    driver:SetScript("OnUpdate", Work)
end

-- A new spell learned, a new level or trinket, or a ticked bag item back:
-- the list of your spells and items is read again before the pulse looks
-- (ns.Spells:Stale, then read once by whatever wants it first).
local REBUILD = { SPELLS_CHANGED = true }
local FEED = { SPELL_UPDATE_COOLDOWN = true, BAG_UPDATE_COOLDOWN = true }
local SCAN = { PLAYER_EQUIPMENT_CHANGED = true, PLAYER_LEVEL_UP = true, PLAYER_LEVEL_CHANGED = true }

local function OnEvent(_, event)
    if event == "PLAYER_ENTERING_WORLD" then
        quietUntil = GetTime() + P.QUIET
        wanding, wandUntil = false, 0
        Soon("rebuild")
    elseif event == "PLAYER_REGEN_DISABLED" then
        if P:Moving() then P:StopMove(false) end
    elseif event == "PLAYER_REGEN_ENABLED" then
        -- A change to the procs made in the fight, told to the game now.
        if procs.pending then P:ApplyProcs() end
    elseif event == "START_AUTOREPEAT_SPELL" then
        wanding = WandWorn()
    elseif event == "STOP_AUTOREPEAT_SPELL" then
        if wanding then
            wanding, wandUntil = false, GetTime() + P.WAND_TAIL
            C_Timer.After(P.WAND_TAIL + .1, function() Soon("feed") end)
        end
    elseif event == "BAG_UPDATE_DELAYED" then
        if PickBack() then
            ns.Spells:Stale()
            Soon("scan")
            Soon("rebuild")
        else
            Soon("bags")
        end
    elseif SCAN[event] then
        ns.Spells:Stale()
        Soon("scan")
        Soon("rebuild")
    elseif REBUILD[event] then
        if event == "SPELLS_CHANGED" then ns.Spells:Stale() end
        Soon("rebuild")
    elseif FEED[event] and next(watchers) then
        Soon("feed")
    end
end

function P:Start()
    if self.started then return end
    self.started = true
    driver = CreateFrame("Frame")
    for _, event in ipairs({ "PLAYER_ENTERING_WORLD", "SPELLS_CHANGED", "SPELL_UPDATE_COOLDOWN", "BAG_UPDATE_COOLDOWN",
        "BAG_UPDATE_DELAYED", "PLAYER_EQUIPMENT_CHANGED", "PLAYER_LEVEL_UP", "PLAYER_LEVEL_CHANGED", "PLAYER_REGEN_DISABLED",
        "PLAYER_REGEN_ENABLED", "START_AUTOREPEAT_SPELL", "STOP_AUTOREPEAT_SPELL" }) do
        driver:RegisterEvent(event)
    end
    driver:SetScript("OnEvent", OnEvent)
    self.driver = driver
    quietUntil = GetTime() + self.QUIET
    Soon("rebuild")
    -- On the link: Forever Enhanced Cooldown Pulse hears this addon joined,
    -- and whenever its tick changes; this one hears of that one's the same
    -- way, so the pulse starts or stops here and the tick greys or frees.
    pcall(link.Register, link, ADDON, {
        name = ns.TITLE,
        rank = LINK_RANK,
        IsOn = function() return ns.Get("pulse") == true end,
        Refresh = function()
            if P.started then P:Apply() end
            if ns.window and ns.window:IsShown() then ns.window:Refresh() end
        end,
    })
end
