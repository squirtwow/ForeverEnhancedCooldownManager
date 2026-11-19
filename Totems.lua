-- Totems bar (a player's idea): a shaman's four totems on a bar of their
-- own, one spot per element (Earth, Fire, Water, Air, in the order picked).
-- An element with no totem down shows its art greyed; a totem down shows its
-- icon with the time it has left, in a fight too. With Red when out of range
-- ticked, a totem that puts a buff on you turns red while that buff isn't on
-- you (you're out of its range); totems with no buff on you never do. Off
-- until it's ticked on its page under More in /ccm (TotemsPage.lua), and
-- only for shamans: for anyone else nothing is made or heard.
--
-- Totems are secret in a fight (every GetTotemInfo answer, in PvP out of one
-- too), so nothing here reads one then. The game hands each slot's time as a
-- duration object, given as it is to the spot's own Cooldown frame, and
-- whether it's running straight to the spot's layers (SetAlphaFromBoolean);
-- the icon goes straight to SetTexture. Which totem stands (for its name, and
-- whether it can turn red) is read out of a fight, or is the last totem of
-- that element you cast (your own casts' spell IDs are plain). No event
-- comes when a totem's time runs out: the spot's cooldown says so.
--
-- Buffs can't be read in a fight either, so the game draws the "buff is on
-- you" part, as the Buffs bar's greyed spots: under each spot's time lies a
-- red copy of the totem's art, and over it one slot of Blizzard's aura
-- container per element, told that element's totem buffs, drawing the buff's
-- icon (the totem's own) while it's on you. Out of range, the red shows
-- through. Containers are only made, told and switched out of a fight, and
-- from then on nothing they sit in is ever shown or hidden (Bars.lua B:Hold):
-- the bar goes by alpha alone. It never takes the mouse but for the box that
-- moves it. Nothing of Blizzard's is touched (its TotemFrame neither).
local _, ns = ...

local M = {}
ns.Totems = M

local Style = ns.Style

-- The four elements by their order letter: Blizzard's totem slot (1 fire, 2 earth, 3 water, 4 air),
-- the name shown, and the totem whose art stands for it while none is down.
local ELEMENTS = {
    e = { key = "earth", slot = 2, name = "Earth", art = 8071 },
    f = { key = "fire", slot = 1, name = "Fire", art = 3599 },
    w = { key = "water", slot = 3, name = "Water", art = 5675 },
    a = { key = "air", slot = 4, name = "Air", art = 8512 },
}
local LETTERS = { "e", "f", "w", "a" } -- Blizzard's own shaman order, and the default
-- Every totem on Forever by name: its element letter, and the buff it puts on you (every rank), if any.
-- Those with none are shown and timed but never turn red. Fire Nova and Tranquil Air aren't on Forever,
-- and Decoy is a rune (Forever has none).
local TOTEMS = {
    ["Strength of Earth Totem"] = { "e", { 8076, 8162, 8163, 10441, 25362 } },
    ["Stoneskin Totem"] = { "e", { 8072, 8156, 8157, 10403, 10404, 10405 } },
    ["Stoneclaw Totem"] = { "e" },
    ["Earthbind Totem"] = { "e" },
    ["Tremor Totem"] = { "e" },
    ["Flametongue Totem"] = { "f", { 8230, 8250, 10521, 15036 } },
    ["Frost Resistance Totem"] = { "f", { 8182, 10476, 10477 } },
    ["Searing Totem"] = { "f" },
    ["Magma Totem"] = { "f" },
    ["Healing Stream Totem"] = { "w", { 5672, 6371, 6372, 10460, 10461 } },
    ["Mana Spring Totem"] = { "w", { 5677, 10491, 10493, 10494 } },
    ["Mana Tide Totem"] = { "w", { 16191, 17355, 17360, 1325257 } },
    ["Fire Resistance Totem"] = { "w", { 8185, 10534, 10535 } },
    ["Poison Cleansing Totem"] = { "w" },
    ["Disease Cleansing Totem"] = { "w" },
    ["Windfury Totem"] = { "a", { 8515, 10609, 10612 } },
    ["Grace of Air Totem"] = { "a", { 8836, 10626, 25360 } },
    ["Nature Resistance Totem"] = { "a", { 10596, 10598, 10599 } },
    ["Windwall Totem"] = { "a", { 15108, 15109, 15110 } },
    ["Grounding Totem"] = { "a", { 8178 } },
    ["Sentry Totem"] = { "a" }, -- (its aura is the sight toggle on you, not a range buff)
}
local GRACE = 2.5 -- seconds a totem just down can't turn red, while its buff arrives
local FADE = .3 -- out of combat Fade, as your bars'
local RED = { .64, .15, .15 } -- Blizzard's out-of-range red, as on your bars
local AGAIN = .25 -- a cooldown done this soon after the spot was read is the game answering that read
-- The page's preview: a totem and its time for three elements (Water's turns
-- red with Red when out of range ticked); Air shows none.
local SAMPLES = { e = { "Strength of Earth Totem", 120 }, f = { "Searing Totem", 55 }, w = { "Mana Spring Totem", 300, true } }

M.ELEMENTS, M.TOTEMS, M.GRACE = ELEMENTS, TOTEMS, GRACE

-- Made at the start, from the game data: a totem by any rank's spell ID, by
-- name, each element's buff IDs ({ [id] = true }) and each totem's short name.
local BY_ID, BY_NAME, SHORT = {}, {}, {}
local ELEMENT_IDS = { e = {}, f = {}, w = {}, a = {} }

-- Everything else the bar keeps. spots: by letter; bySlot: game slot ->
-- letter; cast: game slot -> the totem of your last cast there; pending:
-- what waits for the fight to end; errors: each said once.
local state = { spots = {}, bySlot = {}, cast = {}, pending = {}, errors = {}, art = {} }
for letter, element in pairs(ELEMENTS) do state.bySlot[element.slot] = letter end

local function Open(value)
    return not (issecretvalue and issecretvalue(value))
end

-- A failure, said once per session each.
local FAILS = {
    update = "the Totems bar couldn't update. Please report this: ",
    range = "the Totems bar's range warning couldn't start. Please report this: ",
}
local function Fail(kind, err)
    if state.errors[kind] then return end
    state.errors[kind] = tostring(err)
    print("|cffffd100" .. ns.TITLE .. ":|r " .. FAILS[kind] .. state.errors[kind])
end

-- A spell's art, plain (it works for spells you don't know).
local function SpellArt(id)
    if not (id and C_Spell and C_Spell.GetSpellTexture) then return nil end
    local ok, file = pcall(C_Spell.GetSpellTexture, id)
    if ok and Open(file) then return file end
    return nil
end

-- A totem's art, by name.
local function Art(name)
    local ranks = ns.RANKS and ns.RANKS[name]
    return SpellArt(ranks and ranks[1])
end

-- An element's greyed art, read once.
local function ElementArt(letter)
    if state.art[letter] == nil then state.art[letter] = SpellArt(ELEMENTS[letter].art) or false end
    return state.art[letter] or nil
end

local function Lookups()
    if state.looked then return end
    state.looked = true
    for name, entry in pairs(TOTEMS) do
        BY_NAME[name] = name
        local ranks = ns.RANKS and ns.RANKS[name] or {}
        for _, id in ipairs(ranks) do BY_ID[id] = name end
        for _, id in ipairs(entry[2] or {}) do ELEMENT_IDS[entry[1]][id] = true end
        local spell = ranks[1] and C_Spell and C_Spell.GetSpellName and C_Spell.GetSpellName(ranks[1])
        if not (Open(spell) and type(spell) == "string" and spell ~= "") then spell = name end
        SHORT[name] = (spell:gsub(" Totem$", ""))
    end
end

-- Spots ------------------------------------------------------------------------------------
-- One per element: its greyed art (empty), and over it the totem down
-- (placed): its art, the red copy with the game's buff slot over it (warn),
-- then its time on top. Shown by alpha only. preview: the page's drawing of
-- one, never given a container.

local Again, Warn -- (below)

-- Its time ran out, or the game answered a read of it: read again, unless
-- it's that answer. A preview's sample starts again.
local function Done(spot)
    if spot.preview then
        if spot.sample then spot.cooldown:SetCooldown(GetTime(), spot.sample) end
        return
    end
    if spot.updating then return end
    local readAt = spot.readAt
    if readAt and GetTime() - readAt < AGAIN then
        -- Maybe its time truly ran out just after that read: read once more
        -- a moment on, unless read since (a read made so answers itself only).
        if spot.rechecked then return end
        C_Timer.After(AGAIN, function()
            if spot.readAt ~= readAt or not state.on then return end
            spot.checking = true
            Again(spot.letter)
        end)
        return
    end
    spot.doneAt = GetTime()
    Again(spot.letter)
end

local function NewSpot(parent, letter, preview)
    local spot = CreateFrame("Frame", nil, parent)
    spot:EnableMouse(false)
    local level = spot:GetFrameLevel()
    spot.letter, spot.preview, spot.serial, spot.graceUntil = letter, preview, 0, 0
    spot.decor = Style:Decor(spot, spot)

    local empty = CreateFrame("Frame", nil, spot)
    empty:SetAllPoints()
    empty:EnableMouse(false)
    empty:SetFrameLevel(level + 1)
    local emptyArt = empty:CreateTexture(nil, "ARTWORK")
    emptyArt:SetAllPoints()
    Style:Zoom(emptyArt)
    emptyArt:SetDesaturated(true)
    emptyArt:SetAlpha(.45)
    emptyArt:SetTexture(ElementArt(letter))
    -- (Placed under it now: Style:Shape only moves a name once the icon's drawn like Blizzard's.)
    local emptyLabel = empty:CreateFontString(nil, "OVERLAY", Style:NameFont())
    emptyLabel:SetPoint("TOP", empty, "BOTTOM", 0, -3)
    emptyLabel:SetWordWrap(false)
    emptyLabel:SetText(ELEMENTS[letter].name)
    spot.empty, spot.emptyArt, spot.emptyLabel = empty, emptyArt, emptyLabel
    spot.emptyKit = Style:ShapeKit(empty, emptyArt, {}, false, emptyLabel)

    local placed = CreateFrame("Frame", nil, spot)
    placed:SetAllPoints()
    placed:EnableMouse(false)
    placed:SetFrameLevel(level + 2)
    placed:SetAlpha(0)
    local art = placed:CreateTexture(nil, "ARTWORK")
    art:SetAllPoints()
    Style:Zoom(art)
    art:SetTexture(ElementArt(letter))
    local label = placed:CreateFontString(nil, "OVERLAY", Style:NameFont())
    label:SetPoint("TOP", placed, "BOTTOM", 0, -3)
    label:SetWordWrap(false)
    label:SetText(ELEMENTS[letter].name)
    spot.placed, spot.art, spot.label = placed, art, label

    local warn = CreateFrame("Frame", nil, placed)
    warn:SetAllPoints()
    warn:EnableMouse(false)
    warn:SetFrameLevel(level + 3)
    warn:SetAlpha(0)
    local red = warn:CreateTexture(nil, "ARTWORK")
    red:SetAllPoints()
    Style:Zoom(red)
    red:SetVertexColor(RED[1], RED[2], RED[3])
    red:SetTexture(ElementArt(letter))
    spot.warn, spot.red = warn, red
    spot.redKit = Style:ShapeKit(warn, red, {}, false)

    -- Above the game's buff slot (made later, at level + 4).
    local time = CreateFrame("Frame", nil, placed)
    time:SetAllPoints()
    time:EnableMouse(false)
    time:SetFrameLevel(level + 10)
    local cooldown = CreateFrame("Cooldown", nil, time, "CooldownFrameTemplate")
    cooldown:SetAllPoints(art)
    cooldown:SetSwipeTexture(Style.FLAT)
    Style:CooldownLook(cooldown)
    cooldown:SetDrawBling(false)
    cooldown:SetReverse(true)
    cooldown:SetScript("OnCooldownDone", function() Done(spot) end)
    spot.time, spot.cooldown = time, cooldown
    spot.kit = Style:ShapeKit(placed, art, { cooldown }, false, label)
    spot.parts = { cooldown = cooldown } -- (Style:AuraNumbers keeps the spot of its numbers here)
    return spot
end

-- A totem down (active true) or not, plain or secret: the placed layer over
-- the greyed one, or the greyed one alone.
local function Shown(spot, active)
    local placed, empty = spot.placed, spot.empty
    if placed.SetAlphaFromBoolean then
        placed:SetAlphaFromBoolean(active, 1, 0)
        empty:SetAlphaFromBoolean(active, 0, 1)
    elseif Open(active) then
        placed:SetAlpha(active and 1 or 0)
        empty:SetAlpha(active and 0 or 1)
    else
        placed:SetAlpha(1)
        empty:SetAlpha(0)
    end
end

-- One slot read: its time, whether a totem is down, its art, and which totem
-- stands (seen, or your last cast there in a fight).
local function Read(spot)
    local slot = ELEMENTS[spot.letter].slot
    spot.readAt, spot.rechecked, spot.checking = GetTime(), spot.checking, nil
    local active = false
    local ok, duration = pcall(GetTotemDuration, slot)
    if ok and Open(duration) and duration then
        spot.cooldown:SetCooldownFromDurationObject(duration)
        spot.timed = true
        local okA, answer = pcall(duration.IsActive, duration)
        if okA and (not Open(answer) or type(answer) == "boolean") then active = answer end
    elseif spot.timed then
        spot.timed = false
        spot.cooldown:Clear()
    end
    Shown(spot, active)

    local standing, source
    local okI, have, name, _, _, icon, _, spellID = pcall(GetTotemInfo, slot)
    if okI and Open(have) and Open(name) and Open(spellID) then
        if have then
            standing = type(spellID) == "number" and BY_ID[spellID] or nil
            if not standing and type(name) == "string" then standing = BY_NAME[(name:gsub("%s+[IVX]+$", ""))] end
            source = "seen"
        end
        state.cast[slot] = standing
    else
        standing = state.cast[slot]
        source = standing and "cast" or nil
    end
    -- The art: the game's icon as it is, secret or not; else the totem's own.
    local taken = false
    if okI and (not Open(icon) or icon ~= nil) then
        taken = pcall(spot.art.SetTexture, spot.art, icon)
        if taken then pcall(spot.red.SetTexture, spot.red, icon) end
    end
    if not taken and standing then
        local file = Art(standing)
        if file then
            spot.art:SetTexture(file)
            spot.red:SetTexture(file)
        end
    end
    spot.standing, spot.source = standing, source
    spot.label:SetText(standing and SHORT[standing] or ELEMENTS[spot.letter].name)
    Warn(spot)
end

local function Update(letter)
    local spot = state.spots[letter]
    if not spot then return end
    spot.updating = true
    local ok, err = pcall(Read, spot)
    spot.updating = false
    if not ok then Fail("update", err) end
end

local function UpdateAll()
    for _, letter in ipairs(LETTERS) do Update(letter) end
end

-- Read again on the next frame, once however many ask.
function Again(letter)
    local spot = state.spots[letter]
    if not spot or spot.queued then return end
    spot.queued = true
    C_Timer.After(0, function()
        spot.queued = nil
        if state.on then Update(letter) end
    end)
end

-- Red, or not: only with Red when out of range ticked and the game's slots
-- started, for a totem known to buff you, once its GRACE is over. Plain.
function Warn(spot)
    local standing = spot.standing
    local on = ns.Get("totemRange") == true and ns.Get("totemBar") == true and state.ranged == true and standing ~= nil
        and TOTEMS[standing] ~= nil and TOTEMS[standing][2] ~= nil and GetTime() >= spot.graceUntil
    spot.warn:SetAlpha(on and 1 or 0)
end

-- A totem just down (or the bar just started): not red until its buff has
-- had time to arrive. A newer start makes an older timer's end do nothing.
local function Grace(spot)
    local now = GetTime()
    spot.graceUntil, spot.droppedAt, spot.serial = now + GRACE, now, spot.serial + 1
    spot.warn:SetAlpha(0)
    local serial = spot.serial
    C_Timer.After(GRACE + .05, function()
        if spot.serial == serial then Warn(spot) end
    end)
end

-- Range warning -----------------------------------------------------------------------------

-- The game's slot over a spot's red, made as the slot is added (and never
-- later: Buffs.lua F.Add and F.Guard): exactly over it, taking no mouse,
-- drawing the buff's icon (its totem's own art) and nothing else.
local function Lit(spot)
    return function(button)
        button:SetAllPoints(spot.warn)
        button:EnableMouse(false)
        local icon = button:CreateTexture(nil, "ARTWORK")
        icon:SetAllPoints()
        Style:Zoom(icon)
        button:SetIcon(icon)
        spot.litKit = Style:ShapeKit(button, icon, {}, true)
        -- In the spot's look now (out of a fight, as the slot is added): nothing restyles till a choice changes.
        Style:Shape(spot.litKit, spot.kit.size, nil, spot.kit.ratio)
        spot.button = button
    end
end

-- The game's slots, one per element, made the first time Red when out of
-- range is wanted and switched on or off as it's ticked; never in a fight.
local function Range()
    if not state.made then return end
    local want = ns.Get("totemRange") == true and ns.Get("totemBar") == true
    if not (want or state.ranged) then return end
    if InCombatLockdown() then
        state.pending.range = true
        return
    end
    state.pending.range = nil
    if not state.ranged then
        if state.errors.range or not M:CanRange() then return end
        local ok, err = pcall(function()
            for _, letter in ipairs(LETTERS) do
                local spot = state.spots[letter]
                local container = CreateFrame("AuraContainer", nil, spot.warn, "CustomAuraContainerTemplate")
                state.holds = true -- (from now on nothing it sits in is shown or hidden: alpha only)
                container:SetPoint("CENTER", spot.warn)
                container:SetSize(1, 1)
                container:EnableMouse(false)
                container:SetFrameLevel(spot.warn:GetFrameLevel() + 1)
                container:SetEditModePreviewEnabled(false)
                container:SetUnit("player")
                ns.BuffBar.Add(container, "AddAuraSlot", "lit", "HELPFUL", { initializeFrame = ns.BuffBar.Guard(Lit(spot)) })
                container:SetAuraSlotCandidateFilters("lit", { includeSpellIDs = ELEMENT_IDS[letter] })
                container:SetAuraSlotEnabled("lit", false)
                spot.container, spot.litOn = container, false
            end
        end)
        if not ok then
            Fail("range", err)
            return
        end
        state.ranged = true
    end
    for _, letter in ipairs(LETTERS) do
        local spot = state.spots[letter]
        if spot.litOn ~= want then
            local ok, err = pcall(spot.container.SetAuraSlotEnabled, spot.container, "lit", want)
            if ok then spot.litOn = want else Fail("range", err) end
        end
    end
end

-- Whether the game can show the range warning: its aura containers there,
-- and none refused this session. For the tests and the Totems page
-- (TotemsPage.lua).
function M:CanRange()
    return CustomAuraContainerSlotDefaultOptions ~= nil and ns.BuffBar ~= nil and state.errors.range == nil
end

-- Layout ------------------------------------------------------------------------------------

local function Data()
    return { size = ns.Get("totemSize"), heightPct = ns.Get("totemHeight"), spacing = ns.Get("totemSpacing"),
        perRow = ns.Get("totemPerRow"), grow = ns.Get("totemGrow"), wrap = ns.Get("totemWrap"), showNames = ns.Get("totemNames") }
end

-- A spot's time in Icon details' look: square and reversed as the Buffs
-- bar's times, or drawn like Blizzard's with its gold swipe; its numbers
-- sized for the icon's shorter side.
local function Times(spot, face, timer)
    local cooldown = spot.cooldown
    Style:CooldownLook(cooldown)
    local rounded = spot.kit.rounded == true
    cooldown:SetReverse(not rounded)
    if rounded then
        local gold = Style.AURA_SWIPE
        cooldown:SetSwipeColor(gold[1], gold[2], gold[3], gold[4])
    end
    cooldown:SetCountdownFont(Style:Countdown(face))
    cooldown:SetHideCountdownNumbers(not timer)
    Style:AuraNumbers(spot.parts)
end

-- The spots in order on bar (the bar itself or the page's preview), at the
-- size and in the look chosen. The game's slots' looks out of a fight only.
-- Returns the bar's size.
local function Lay(bar, spots, data, fight)
    local size = ns.IconSize(data)
    local high, face, ratio = ns.IconHeight(data, size), ns.IconFace(data, size), ns.IconRatio(data, size)
    local list = {}
    for i, letter in ipairs(M:Order()) do
        list[i] = spots[letter]
        list[i]:SetSize(size, high)
    end
    local width, height = ns.Bars:Arrange(bar, list, #list, data)
    bar:SetSize(width, height)
    local font, timer = Style:NameFont(), ns.Get("totemTimer") == true
    local border, shadow = Style:DecorFor("icon", true)
    for _, spot in ipairs(list) do
        Style:Shape(spot.emptyKit, size, nil, ratio)
        Style:Shape(spot.kit, size, nil, ratio)
        Style:Shape(spot.redKit, size, nil, ratio)
        if spot.litKit and not fight then Style:Shape(spot.litKit, size, nil, ratio) end
        Times(spot, face, timer)
        for _, label in ipairs({ spot.label, spot.emptyLabel }) do
            label:SetFontObject(font)
            label:SetWidth(size + data.spacing)
            label:SetShown(data.showNames == true)
        end
        Style:ShowDecor(spot.decor, border, shadow)
    end
    border, shadow = Style:DecorFor("bar", true)
    local short = bar.short == true
    Style:ShowDecor(bar.decor, border, shadow)
    Style:ShowDecor(bar.tailDecor, border and short, shadow and short)
    return width, height
end

-- Empty regions for the border and shadow round a whole bar (Bars.lua NewBar).
local function Box(bar)
    bar.block = bar:CreateTexture(nil, "BACKGROUND")
    bar.block:SetAllPoints(bar)
    bar.tail = bar:CreateTexture(nil, "BACKGROUND")
    bar.tail:SetAllPoints(bar)
    bar.decor = Style:Decor(bar, bar.block)
    bar.tailDecor = Style:Decor(bar, bar.tail)
end

-- Its middle where it was put, from the middle of the screen. Never while
-- it's being dragged (the game's to move till it's let go).
local function Place()
    local bar = state.bar
    if not bar or state.dragging then return end
    bar:ClearAllPoints()
    bar:SetPoint("CENTER", UIParent, "CENTER", ns.Get("totemX"), ns.Get("totemY"))
end

-- Made once, the first time it's on: shown from then on, going by alpha.
local function Make()
    if state.made then return end
    local bar = CreateFrame("Frame", nil, UIParent)
    bar:SetFrameStrata("MEDIUM")
    bar:SetMovable(true)
    bar:SetClampedToScreen(true)
    bar:EnableMouse(false)
    bar:SetAlpha(0)
    Box(bar)
    state.bar = bar
    for _, letter in ipairs(LETTERS) do state.spots[letter] = NewSpot(bar, letter, false) end
    state.made = true
    M.bar = bar
end

-- Laid out again as chosen: out of a fight once it holds the game's slots
-- (a change in one waits for it to end).
function M:Restyle()
    if not state.made then return end
    if state.holds and InCombatLockdown() then
        state.pending.restyle = true
        return
    end
    state.pending.restyle = nil
    Lay(state.bar, state.spots, Data(), InCombatLockdown())
    Place()
end

-- The elements' letters in the order picked (a broken saved order is the
-- default's: ns.Get checks it).
function M:Order()
    local letters = {}
    for letter in tostring(ns.Get("totemOrder")):gmatch(".") do letters[#letters + 1] = letter end
    return letters
end

-- Puts an element in a spot (index, from the first), swapping it with the
-- one there. For the tests and the Totems page's order pickers (TotemsPage.lua).
function M:SetOrderAt(index, letter)
    local order = self:Order()
    if not (ELEMENTS[letter] and order[index]) then return end
    for i, have in ipairs(order) do
        if have == letter then
            order[i] = order[index]
            break
        end
    end
    order[index] = letter
    ns.Set("totemOrder", table.concat(order))
    self:Apply()
end

-- Showing -----------------------------------------------------------------------------------

-- In full in a fight, with an enemy targeted (a secret answer counts), while
-- its page is open, while it's moved, and while your bars are arranged
-- (unlocked or Edit Mode), as your bars. With Stay hidden with an enemy
-- targeted ticked (General page), the target doesn't bring it back.
local function Awake()
    if state.inCombat or InCombatLockdown() or state.pageOpen or state.moving or (ns.Bars ~= nil and ns.Bars:Arranging()) then
        return true
    end
    if ns.Get("oocIgnoreTarget") then return false end
    local hostile = UnitExists("target") and UnitCanAttack("player", "target")
    if not Open(hostile) then return true end
    return hostile and true or false
end

-- Its alpha: off, gone right out; else in full while awake, or as chosen
-- out of combat. Never shown or hidden.
function M:UpdateShown()
    local bar = state.bar
    if not bar then return end
    local alpha = 0
    if state.on and self:ForMe() then
        local mode = ns.Get("totemOutOfCombat")
        alpha = Awake() and 1 or mode == "fade" and FADE or mode == "hide" and 0 or 1
    end
    bar:SetAlpha(alpha)
end

-- Moving it ---------------------------------------------------------------------------------
-- The bar itself is dragged by a box over it (as your bars'): from its page
-- (Move, with Done and a note under it) or while your bars are unlocked.

-- Lets go of the bar mid-drag: its middle from the screen's is its new spot.
local function Drop()
    if not state.dragging then return end
    state.dragging = false
    local bar = state.bar
    bar:StopMovingOrSizing()
    if bar.SetUserPlaced then bar:SetUserPlaced(false) end
    local x, y = bar:GetCenter()
    local cx, cy = UIParent:GetCenter()
    if x and y and cx and cy then
        local limits = ns.TOTEM_PLACE
        ns.Set("totemX", math.max(limits[1], math.min(limits[2], math.floor(x - cx + .5))))
        ns.Set("totemY", math.max(limits[1], math.min(limits[2], math.floor(y - cy + .5))))
    end
    Place()
end

local function Mover()
    if state.mover then return state.mover end
    local T, bar = ns.Theme, state.bar
    local mover = CreateFrame("Frame", nil, bar)
    mover:SetPoint("TOPLEFT", -4, 4)
    mover:SetPoint("BOTTOMRIGHT", 4, -4)
    mover:SetFrameLevel(bar:GetFrameLevel() + 20)
    mover:EnableMouse(true)
    mover:RegisterForDrag("LeftButton")
    mover.fill = mover:CreateTexture(nil, "BACKGROUND")
    mover.fill:SetAllPoints()
    mover.fill:SetColorTexture(.25, .55, 1, .45)
    mover.label = mover:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    mover.label:SetPoint("CENTER")
    mover.label:SetText("Totems")
    mover.done = T:Button(mover, "Done", 80, 22)
    mover.done:SetPoint("TOP", mover, "BOTTOM", 0, -6)
    mover.done:SetScript("OnClick", function() M:StopMove(true) end)
    mover.note = T:Text(mover, "GameFontHighlightSmall")
    mover.note:SetPoint("TOP", mover.done, "BOTTOM", 0, -4)
    mover.note:SetJustifyH("CENTER")
    mover.note:SetText("Drag the bar, then click Done or right-click it.")
    mover:SetScript("OnDragStart", function()
        if state.holds and InCombatLockdown() then return end
        state.dragging = true
        bar:StartMoving()
    end)
    mover:SetScript("OnDragStop", Drop)
    -- Hidden mid-drag, it never hears the mouse let go: let go there.
    mover:SetScript("OnHide", Drop)
    -- Right-click finishes too, should Done be off the screen's edge.
    mover:SetScript("OnMouseUp", function(_, button)
        if button == "RightButton" and state.moving then M:StopMove(true) end
    end)
    mover:Hide()
    state.mover, M.mover = mover, mover
    return mover
end

-- The box over the bar: while it's moved from its page (with Done), or while
-- your bars are unlocked; never while the bar is off.
function M:ShowMover()
    local show = state.made == true and state.on == true and self:ForMe()
        and (state.moving == true or (ns.Bars ~= nil and ns.Bars:IsUnlocked() == true))
    local mover = state.mover
    if show and not mover then mover = Mover() end
    if not mover then return end
    mover.done:SetShown(state.moving == true)
    mover.note:SetShown(state.moving == true)
    mover:SetShown(show and true or false)
end

-- Its page shows (open true) or goes: in full meanwhile.
function M:PageOpen(open)
    state.pageOpen = open and true or false
    self:UpdateShown()
end

-- Shows the box with Done, out of a fight, with the /ccm window out of the
-- way: true, or false and why not.
function M:StartMove()
    if InCombatLockdown() then return false, "Finish the fight first, then move it." end
    if not (state.made and state.on) then return false, "Tick Show the Totems bar first." end
    state.moving = true
    self:ShowMover()
    if ns.window then ns.window:Hide() end
    self:UpdateShown()
    return true
end

-- Ends a move where the bar is; reopen brings the /ccm window back on the
-- Totems page.
function M:StopMove(reopen)
    Drop()
    state.moving = false
    self:ShowMover()
    self:UpdateShown()
    if reopen and ns.ShowWindow then
        ns.ShowWindow()
        if ns.window and ns.window.pages and ns.window.pages.totems then ns.window:Select("totems") end
    end
end

-- Back where it started, left of your bars.
function M:ResetPlace()
    ns.Set("totemX", ns.DEFAULTS.totemX)
    ns.Set("totemY", ns.DEFAULTS.totemY)
    if state.holds and InCombatLockdown() then
        state.pending.restyle = true
    else
        Place()
    end
end

-- Events ------------------------------------------------------------------------------------

local Begin -- (below)

local EVENTS = { "PLAYER_TOTEM_UPDATE", "PLAYER_ENTERING_WORLD", "PLAYER_REGEN_DISABLED", "PLAYER_REGEN_ENABLED",
    "PLAYER_TARGET_CHANGED" }

-- Your own cast of a totem (its spell ID is plain, in a fight too): the
-- totem that stands in its element now, while the game keeps the slot secret.
local function Cast(id)
    if not (Open(id) and type(id) == "number") then return end
    local name = BY_ID[id]
    if not name then return end
    local letter = TOTEMS[name][1]
    local spot = state.spots[letter]
    state.cast[ELEMENTS[letter].slot] = name
    if not spot then return end
    Grace(spot)
    Again(letter)
end

local function OnEvent(self, event, ...)
    if event == "PLAYER_LOGIN" then
        -- Your class unreadable as the addon started: asked once more now.
        self:UnregisterEvent("PLAYER_LOGIN")
        if M:ForMe() then Begin() end
    elseif event == "PLAYER_TOTEM_UPDATE" then
        local slot = ...
        local letter = Open(slot) and type(slot) == "number" and state.bySlot[slot] or nil
        local spot = letter and state.spots[letter]
        if not spot then return end
        spot.eventAt = GetTime()
        Grace(spot)
        Again(letter)
    elseif event == "UNIT_SPELLCAST_SUCCEEDED" then
        local unit, _, id = ...
        if Open(unit) and unit == "player" then Cast(id) end
    elseif event == "PLAYER_ENTERING_WORLD" then
        for _, letter in ipairs(LETTERS) do Grace(state.spots[letter]) end
        UpdateAll()
    elseif event == "PLAYER_REGEN_DISABLED" then
        state.inCombat = true
        -- A fight ends a move, where the bar is, with no window; or a drag
        -- while your bars are unlocked, where it is (still before lockdown).
        if state.moving then M:StopMove(false) else Drop() end
        M:UpdateShown()
    elseif event == "PLAYER_REGEN_ENABLED" then
        state.inCombat = false
        -- Turned off in the fight: only the game's slots switched off, then nothing heard.
        if not state.on then
            Range()
            self:UnregisterEvent("PLAYER_REGEN_ENABLED")
            return
        end
        if state.pending.restyle then M:Restyle() end
        if state.pending.range then Range() end
        -- What was guessed from your casts, read again now.
        UpdateAll()
        M:UpdateShown()
    elseif event == "PLAYER_TARGET_CHANGED" then
        M:UpdateShown()
    end
end

local function Driver()
    if not state.driver then
        state.driver = CreateFrame("Frame")
        state.driver:SetScript("OnEvent", OnEvent)
        M.driver = state.driver
    end
    return state.driver
end

-- Heard only while the bar is on.
local function Hear(on)
    if (state.hearing == true) == on then return end
    state.hearing = on
    if not on then
        if state.driver then state.driver:UnregisterAllEvents() end
        return
    end
    -- (Unheard while off: whether you're in a fight, as it is now.)
    state.inCombat = InCombatLockdown() and true or false
    local driver = Driver()
    for _, event in ipairs(EVENTS) do driver:RegisterEvent(event) end
    if not pcall(driver.RegisterUnitEvent, driver, "UNIT_SPELLCAST_SUCCEEDED", "player") then
        pcall(driver.RegisterEvent, driver, "UNIT_SPELLCAST_SUCCEEDED")
    end
end

-- Setup -------------------------------------------------------------------------------------

-- Whether you're a shaman: a plain answer is kept for the session; while
-- the game won't say, the one kept (none: no).
function M:ForMe()
    local ok, _, class = pcall(UnitClass, "player")
    if ok and Open(class) and type(class) == "string" and class ~= "" then state.class = class end
    return state.class == "SHAMAN"
end

function Begin()
    if state.begun then return end
    state.begun = true
    Lookups()
    M:Apply()
end

-- Once, as the addon starts (Core.lua). Not a shaman: nothing more.
function M:Start()
    if state.started then return end
    state.started = true
    if self:ForMe() then
        Begin()
    elseif state.class == nil then
        Driver():RegisterEvent("PLAYER_LOGIN")
    end
end

-- A choice changed (its page): on, everything as chosen; off, gone right out
-- and nothing heard, the game's slots switched off (once out of a fight).
function M:Apply()
    if not (state.begun and self:ForMe()) then return end
    local on = ns.Get("totemBar") == true
    state.on = on
    if on then
        Make()
        Hear(true)
        if not state.wasOn then
            for _, letter in ipairs(LETTERS) do Grace(state.spots[letter]) end
        end
        state.wasOn = true
        self:Restyle()
        -- The game's slots first, so a totem already down can turn red at once.
        Range()
        UpdateAll()
    else
        state.wasOn = false
        if state.moving then self:StopMove(false) end
        Hear(false)
        Range()
        -- Off in a fight: its end still heard, to switch the game's slots off then.
        if state.pending.range then Driver():RegisterEvent("PLAYER_REGEN_ENABLED") end
        for _, spot in pairs(state.spots) do Warn(spot) end
    end
    self:UpdateShown()
    self:ShowMover()
end

-- How many totems are down, out of a fight; nil in one (the game won't
-- say). For the tests and the Totems page's status line (TotemsPage.lua).
function M:Down()
    if InCombatLockdown() then return nil end
    local count = 0
    for slot = 1, 4 do
        local ok, have = pcall(GetTotemInfo, slot)
        if not (ok and Open(have)) then return nil end
        if have then count = count + 1 end
    end
    return count
end

-- The page's preview -------------------------------------------------------------------------
-- The same spots, never with the game's slots, drawn with your choices and
-- sample totems (SAMPLES): for the Totems page (TotemsPage.lua) and the tests.

-- For the tests and the Totems page (TotemsPage.lua): a preview bar on parent.
function M:NewPreview(parent)
    Lookups()
    local preview = CreateFrame("Frame", nil, parent)
    preview:EnableMouse(false)
    Box(preview)
    preview.spots = {}
    for _, letter in ipairs(LETTERS) do preview.spots[letter] = NewSpot(preview, letter, true) end
    return preview
end

-- For the tests and the Totems page (TotemsPage.lua): the preview drawn as
-- chosen now. Returns its size, for the page to fit it in its box.
function M:DrawPreview(preview)
    local width, height = Lay(preview, preview.spots, Data(), InCombatLockdown())
    local range = ns.Get("totemRange") == true
    for _, letter in ipairs(LETTERS) do
        local spot, sample = preview.spots[letter], SAMPLES[letter]
        if sample then
            local file = Art(sample[1])
            spot.art:SetTexture(file)
            spot.red:SetTexture(file)
            spot.label:SetText(SHORT[sample[1]])
            spot.placed:SetAlpha(1)
            spot.empty:SetAlpha(0)
            spot.warn:SetAlpha(sample[3] and range and 1 or 0)
            if spot.sample ~= sample[2] then
                spot.sample = sample[2]
                spot.cooldown:SetCooldown(GetTime(), sample[2])
            end
        else
            spot.placed:SetAlpha(0)
            spot.empty:SetAlpha(1)
        end
    end
    return width, height
end

-- /ccm debug: one line (never mentioned to players). say: anything the game
-- may keep secret.
function M:Report(add, say)
    local spots = {}
    for _, letter in ipairs(self:Order()) do
        local spot, slot = state.spots[letter], ELEMENTS[letter].slot
        local ok, have = pcall(GetTotemInfo, slot)
        spots[#spots + 1] = ("%s %s%s, now %s, red %s"):format(ELEMENTS[letter].name, tostring(spot and spot.standing or "none"),
            spot and spot.source and (" (" .. spot.source .. ")") or "", ok and say(have) or "refused",
            spot and tostring(spot.warn:GetAlpha()) or "-")
    end
    local pending = {}
    for key in pairs(state.pending) do pending[#pending + 1] = key end
    table.sort(pending)
    add(("Totems: shaman %s, on %s, range %s (slots %s%s), order %s, in a fight %s | %s | waiting %s%s"):format(
        tostring(self:ForMe()), tostring(ns.Get("totemBar")), tostring(ns.Get("totemRange")), tostring(state.ranged == true),
        state.errors.range and (", refused: " .. state.errors.range) or "", tostring(ns.Get("totemOrder")),
        tostring(InCombatLockdown()), table.concat(spots, "; "), #pending > 0 and table.concat(pending, ", ") or "none",
        state.errors.update and (" | update failed: " .. state.errors.update) or ""))
end
