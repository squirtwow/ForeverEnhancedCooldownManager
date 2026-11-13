-- The addon's own bars: rows of square frameless icons for the spells you
-- pick. Cooldowns are secret in combat, so each icon hands the game's
-- duration object straight to its sweep, greying and its dim or hide (when
-- ready, or on cooldown) without ever reading it; only the open "usable" and
-- range checks are read here.
-- The icons never take the mouse, so they can't get in the way in combat.
local _, ns = ...

local B = {}
ns.Bars = B

local Style = ns.Style
-- Just above the action bar, an extra bar (Extra bars, Core.lua) higher up.
local DEFAULT_Y = { debuff = 278, buff = 234, cd = 190, util = 146, debuff2 = 322, buff2 = 366, util2 = 410, cd2 = 454,
    debuff3 = 498, buff3 = 542, util3 = 586, cd3 = 630 }
-- Blizzard's own Cooldown Manager tints.
local TINT = {
    ready = { 1, 1, 1 },
    mana = { .5, .5, 1 },
    unusable = { .4, .4, .4 },
    range = { .64, .15, .15 },
}
-- Abilities that only become usable after something happens in the fight
-- (Overpower after a dodge, Execute on a wounded target, Victory Rush after
-- a kill), by name, from the game data (Ranks.lua).
local REACTIVE = ns.REACTIVE or {}

local bars = {}
local unlocked, inCombat, editMode = false, false, false
-- Icons wanting a refresh: done once on the next frame, however many events
-- (a cast brings several) or cooldowns ending asked for it. Only what the
-- game said changed: everything (dirty), the cooldowns (cooling), or the
-- colour and glow (tinting: usable, in range, lit by the game).
local dirty, cooling, tinting = false, false, false
local FADE = .3 -- a faded bar's opacity out of combat
-- A dimmed icon's opacity in percent (When ready, On cooldown, or one you
-- can't cast), unless its bar says otherwise: each bar has its own.
local DIM = ns.BAR_LIMITS.dimOpacity[3]
local SHOWN = { show = 1, hide = 0 } -- each choice's opacity, and Dim the bar's own

local function Open(value)
    return not (issecretvalue and issecretvalue(value))
end

-- An icon's opacity while its spell cools down and while it's ready: in
-- full (1), dimmed (the bar's Dimmed icons, 40% unless chosen) or hidden
-- (0), as its bar's On cooldown and When ready say. On a bar that dims what
-- you can't cast, one you can't cast now (blue, grey or red) is never more
-- than dimmed; a hidden one stays hidden. Dimming and hiding wait while the
-- bars are being arranged (unlocked, or in Edit Mode), so every icon on
-- them can be seen in full.
local function Alphas(data, cantCast)
    if unlocked or editMode then return 1, 1 end
    local dim = (type(data.dimOpacity) == "number" and data.dimOpacity or DIM) / 100
    local cooling = data.onCooldown == "dim" and dim or SHOWN[data.onCooldown] or 1
    local ready = data.whenReady == "dim" and dim or SHOWN[data.whenReady] or 1
    if cantCast and data.dimUnusable then return math.min(cooling, dim), math.min(ready, dim) end
    return cooling, ready
end

-- Whether a bar hides its icons while ready or while cooling down, so they
-- come and go.
local function Hides(data)
    local cooling, ready = Alphas(data, false)
    return cooling == 0 or ready == 0
end

-- Bag items, healthstones and potions you carry none of, by their key on the
-- bar: left off your bars, which close up, so a profile shared with another
-- character doesn't show that one's potions. Read outside a fight only, so
-- icons never jump about in one (a potion used up then stays greyed at 0
-- until it's over). They show while the bars are arranged, to be placed.
local absent = {}

local function Absent(name)
    return absent[name] == true and not (unlocked or editMode)
end

-- Reads again which of the items on your cooldown bars you carry none of
-- (on any of their lists: each form's too, Swap with my form). Anything the
-- game won't say keeps what was known. True when any changed.
local function Recount()
    if InCombatLockdown() then return false end
    local now, changed = {}, false
    for _, key in ipairs(ns.BAR_KEYS) do
        if not ns.AURA_BARS[key] then
            for _, spells in ipairs(ns.BarLists(key)) do
                for _, name in ipairs(spells) do
                    local have = ns.Spells:Carries(ns.Spells:Find(name))
                    if have == nil then now[name] = absent[name] else now[name] = not have or nil end
                end
            end
        end
    end
    for name in pairs(absent) do
        if now[name] ~= absent[name] then changed = true end
    end
    for name in pairs(now) do
        if now[name] ~= absent[name] then changed = true end
    end
    absent = now
    return changed
end

-- Icons ---------------------------------------------------------------------------

-- A reactive ability that is ready glows with Blizzard's own proc glow, as
-- on its action bars (ActionButtonSpellAlerts.xml): a burst, then a loop,
-- spreading this far past the icon, as Blizzard sizes it. It sits over the
-- icon, so the icons beside it and the Look page's border and shadow never
-- hide it: an edge drawn behind the icon showed only its top (a player's
-- Riposte). Or, picked on the Look page (Ready glow), a plain gold edge just
-- inside the icon, GLOW wide: the edge is also what both show without the
-- template.
local GLOW_SPREAD = 1.4
local GLOW = 2
-- The edge's four sides: the corners each runs between, and whether it runs across.
local GLOW_SIDES = { { "TOPLEFT", "TOPRIGHT", true }, { "BOTTOMLEFT", "BOTTOMRIGHT", true },
    { "TOPLEFT", "BOTTOMLEFT" }, { "TOPRIGHT", "BOTTOMRIGHT" } }

-- The edge's frame, and its four sides in GLOW_SIDES' order.
local function NewEdge(top)
    local glow = CreateFrame("Frame", nil, top)
    glow:SetAllPoints()
    local strips = {}
    for i, side in ipairs(GLOW_SIDES) do
        local strip = glow:CreateTexture(nil, "BORDER")
        strip:SetColorTexture(1, .82, 0, 1)
        strip:SetPoint(side[1])
        strip:SetPoint(side[2])
        if side[3] then strip:SetHeight(GLOW) else strip:SetWidth(GLOW) end
        strips[i] = strip
    end
    glow:Hide()
    return glow, strips
end

-- An edge's sides made width wide in place of GLOW (Glow while active's
-- Glow size, Buffs.lua).
local function EdgeWidth(strips, width)
    for i, side in ipairs(GLOW_SIDES) do
        if side[3] then strips[i]:SetHeight(width) else strips[i]:SetWidth(width) end
    end
end

-- Blizzard's proc glow, or nil if the game can't make it.
local function NewProc(icon, top)
    local made, glow = pcall(CreateFrame, "Frame", nil, top, "ActionButtonSpellAlertTemplate")
    if not (made and glow and type(glow.ProcStartAnim) == "table" and type(glow.ProcLoop) == "table") then
        if made and glow and glow.Hide then glow:Hide() end
        return nil
    end
    glow:SetPoint("CENTER", icon, "CENTER")
    glow.proc = true
    -- Forever's template never stops the loop as it hides (its second
    -- OnHide runs its OnShow method), so SetGlow stops it as it goes out.
    -- Shown again with its bar while lit, this plays it.
    glow:HookScript("OnShow", function(self)
        if self.looping then self.ProcLoop:Play() end
    end)
    glow:Hide()
    return glow
end

-- Lights an icon's glow, with the burst only as it comes on, or puts it out.
-- Whether the game has lit a spell up on your action bars just now: a proc,
-- whatever it is (the user: "copy the game's own glow"). Asked as its own
-- action buttons ask (ActionButton.lua); a hidden answer never counts.
local function Overlayed(spellID)
    local overlay = C_SpellActivationOverlay
    if not (spellID and overlay and overlay.IsSpellOverlayed) then return false end
    local lit = overlay.IsSpellOverlayed(spellID)
    return Open(lit) and lit == true
end

local function SetGlow(icon, on)
    local glow = icon.glow
    if not on then
        glow.looping = nil
        -- Out already: its burst and loop were stopped as it went out.
        if not glow:IsShown() then return end
        if glow.proc then
            glow.ProcStartAnim:Stop()
            glow.ProcLoop:Stop()
        end
        glow:Hide()
        return
    end
    if glow.proc then
        local width, height = icon:GetSize()
        glow:SetSize(width * GLOW_SPREAD, height * GLOW_SPREAD)
    end
    if glow:IsShown() then return end
    glow:Show()
    if glow.proc then
        glow.ProcStartAnim:Play() -- the loop follows it (Blizzard's OnLoad)
        glow.looping = true
    end
end

-- The icon's glow in the style picked on the Look page, each style made the
-- first time it's wanted and kept. Proc glow falls back to the edge for good
-- if the game can't make it. A glow lit as the style changes goes out (its
-- burst and loop stopped) and the new one comes on lit, burst and all.
local function UseGlow(icon)
    local glows, style = icon.glows, ns.Get("readyGlow") == "edge" and "edge" or "proc"
    local glow = glows[style]
    if not glow then
        if style == "proc" then glow = NewProc(icon, icon.top) end
        if not glow then
            glows.edge = glows.edge or NewEdge(icon.top)
            glow = glows.edge
        end
        glows[style] = glow
    end
    local old = icon.glow
    if old == glow then return end
    local lit = old ~= nil and old:IsShown()
    if old then SetGlow(icon, false) end
    icon.glow = glow
    if lit then SetGlow(icon, true) end
end
-- Shared with the Buffs bar's missing buffs (Buffs.lua), on any frame with a
-- top for the glow and a glows table. The gold edge too, for its buffs that
-- glow while they're up, and how wide its sides are.
ns.UseGlow, ns.SetGlow, ns.NewEdge, ns.EdgeWidth, ns.EDGE_WIDTH = UseGlow, SetGlow, NewEdge, EdgeWidth, GLOW

local function NewIcon(bar)
    local icon = CreateFrame("Frame", nil, bar)
    icon:EnableMouse(false)
    icon.texture = icon:CreateTexture(nil, "ARTWORK")
    icon.texture:SetAllPoints()
    Style:Zoom(icon.texture)
    icon.cooldown = CreateFrame("Cooldown", nil, icon, "CooldownFrameTemplate")
    icon.cooldown:SetAllPoints(icon.texture)
    icon.cooldown:SetSwipeTexture(Style.FLAT)
    Style:CooldownLook(icon.cooldown) -- the swipe and edge line picked in Icon details
    icon.cooldown:SetDrawBling(false)
    -- Events arrive when a cooldown starts, not when it ends; this catches the
    -- end, so the icon ungreys (and dims, hides or shows again, as chosen) on time.
    icon.cooldown:SetScript("OnCooldownDone", function() cooling = true end)
    -- Item counts and the keybind sit above the sweep.
    local top = CreateFrame("Frame", nil, icon)
    top:SetAllPoints()
    top:SetFrameLevel(icon.cooldown:GetFrameLevel() + 1)
    icon.top = top
    icon.glows = {}
    UseGlow(icon)
    icon.count = top:CreateFontString(nil, "OVERLAY", "NumberFontNormal")
    icon.count:SetPoint("BOTTOMRIGHT", -1, 1)
    icon.key = Style:KeyText(top)
    icon.label = icon:CreateFontString(nil, "OVERLAY", Style:NameFont())
    icon.label:SetPoint("TOP", icon, "BOTTOM", 0, -3)
    icon.label:SetWordWrap(false)
    icon.decor = Style:Decor(icon, icon)
    Style:ShowDecor(icon.decor, Style:DecorFor("icon", true))
    -- Square, or drawn like Blizzard's (Icon details' Icons) as it's laid
    -- out, its name then under Blizzard's frame.
    icon.shape = Style:ShapeKit(icon, icon.texture, { icon.cooldown }, false, icon.label)
    return icon
end

local ShowKey -- with the keybinds, below

-- The name under an icon: a trinket or ammo by the item itself, and a
-- healthstone or potion family by the one you carry (its own name when
-- you're out).
local function Label(entry)
    return ((entry.current or entry.name):gsub("^Trinket %d: ", ""):gsub("^Ammo: ", ""))
end

-- A healthstone or potion family moves on to the best one you carry as your
-- bags change, which only refreshes the bars: its picture, name and key
-- follow it. Looked for at the next refresh after your bags change, the bars
-- are laid out, you level, a fight ends or the game learns an item's name,
-- not on every refresh (several a second).
local follow = true
local function Follow(icon)
    local entry = ns.Spells:Find(icon.name)
    if not entry then return end
    ns.Spells:Pick(entry)
    if icon.itemID == entry.itemID and icon.current == entry.current then return end
    icon.itemID, icon.current = entry.itemID, entry.current
    icon.texture:SetTexture(entry.icon)
    icon.label:SetText(Label(entry))
    ShowKey(icon)
end

-- The icon's colour: white, blue (low on mana), grey (can't be used now) or
-- red (out of range), with Blizzard's shadow out of range on an icon drawn
-- like Blizzard's. Only set when it changes.
local function Tint(icon, tint)
    if icon.tint == tint then return end
    icon.tint = tint
    icon.texture:SetVertexColor(tint[1], tint[2], tint[3])
    Style:Far(icon.shape, tint == TINT.range)
end

-- The icon's opacity when it's a plain number, only set when it changes.
-- One that differs while cooling down and while ready (When ready, On
-- cooldown) hands the game a secret answer instead (Fade), and the next
-- plain one is set again after it.
local function Alpha(icon, alpha)
    if icon.alpha == alpha then return end
    icon.alpha = alpha
    icon:SetAlpha(alpha)
end

-- The game picks: cooling while active, ready while not.
local function Fade(icon, active, cooling, ready)
    icon.alpha = nil
    icon:SetAlphaFromBoolean(active, cooling, ready)
end

-- Trinkets and bag items. Their cooldowns come back as plain numbers; if the
-- game ever hides them in combat, the icon simply keeps its last state.
-- Whether one can be used now is read first: on a bar that dims what you
-- can't use, it goes into the opacity too.
local function RefreshItem(icon, data, follows)
    if follows and icon.kind == "family" then Follow(icon) end
    local usable, noMana = C_Item.IsUsableItem(icon.itemID)
    local tint = TINT.ready
    if Open(usable) and usable == false then
        tint = Open(noMana) and noMana and TINT.mana or TINT.unusable
    end
    Tint(icon, tint)
    icon.cantCast = tint ~= TINT.ready
    SetGlow(icon, false)
    local start, duration
    if icon.kind == "slot" then
        start, duration = GetInventoryItemCooldown("player", icon.slot)
    else
        start, duration = C_Item.GetItemCooldown(icon.itemID)
    end
    if Open(start) and Open(duration) and type(start) == "number" and type(duration) == "number" then
        local active = start > 0 and duration > 1.5
        if active then icon.cooldown:SetCooldown(start, duration) else icon.cooldown:Clear() end
        icon.texture:SetDesaturated(active)
        local cooling, ready = Alphas(data, icon.cantCast)
        Alpha(icon, active and cooling or ready)
    end
    local count
    if icon.kind == "item" or icon.kind == "family" then
        count = C_Item.GetItemCount(icon.itemID, false, true)
        if Open(count) and type(count) == "number" then
            icon.count:SetText(count)
            if count == 0 then icon.texture:SetDesaturated(true) end
        end
    end
end

-- An icon that only counts what you carry (your ammo, your Soul Shards):
-- the count, greyed at 0, never cooling down.
local function Counted(icon, count)
    if Open(count) and type(count) == "number" then
        icon.count:SetText(count)
        icon.texture:SetDesaturated(count == 0)
    end
    icon.cooldown:Clear()
    Alpha(icon, 1)
    Tint(icon, TINT.ready)
    -- Never "can't cast". Icons are reused by place, so this clears what a
    -- spell or item there before left for the debug report.
    icon.cantCast = false
    SetGlow(icon, false)
end

-- Your ammunition: how many you carry, greyed when you're out.
local function RefreshAmmo(icon)
    local texture = GetInventoryItemTexture("player", icon.slot)
    if texture then icon.texture:SetTexture(texture) end
    Counted(icon, GetInventoryItemID("player", icon.slot) and GetInventoryItemCount("player", icon.slot) or 0)
end

-- Your Soul Shards in your bags (not the bank).
local function RefreshShards(icon)
    Counted(icon, C_Item.GetItemCount(icon.itemID, false, false))
end

-- Whether an icon shows an item (your ammunition, your Soul Shards) rather
-- than a spell.
local ITEM_KINDS = { item = true, slot = true, family = true, ammo = true, shards = true }

-- Show reagent count (ticked in a spell's own panel): how many times your
-- reagents let you cast it, in the spot an item's count goes. The game can
-- keep the number secret in a fight: the last one shown then stays.
local function ReagentCount(icon)
    if not (icon.look and icon.look.reagents and icon.spellID) or not C_Spell.GetSpellCastCount then return end
    local ok, count = pcall(C_Spell.GetSpellCastCount, icon.spellID)
    if ok and Open(count) and type(count) == "number" then icon.count:SetText(count) end
end

-- Show the global cooldown (each cooldown bar's tick, off unless ticked):
-- a second sweep on a spell's icon, made the first time it's wanted, with
-- no numbers and no flash. It's fed the spell's cooldown with the global
-- cooldown counted (the game's own duration object, never read here), and
-- is see-through while the spell's own cooldown runs (active: whether it
-- does, secret in a fight, handed to the game as it is), so it only ever
-- shows on an icon that isn't cooling down: a longer cooldown of its own
-- keeps showing as before. A spell the global cooldown doesn't touch shows
-- none, as the game says. Nothing waits for it to end: it simply stops.
local function Global(icon, active)
    local gcd = icon.gcd
    if not gcd then
        gcd = CreateFrame("Cooldown", nil, icon, "CooldownFrameTemplate")
        gcd:SetAllPoints(icon.texture)
        Style:Sweep(icon.shape, gcd) -- the icon's own swipe art, square or Blizzard's
        Style:CooldownLook(gcd) -- the same swipe as the icon's own (Icon details)
        gcd:SetDrawBling(false)
        gcd:SetHideCountdownNumbers(true)
        icon.gcd = gcd
    end
    icon.gcdShown = true
    local duration = C_Spell.GetSpellCooldownDuration and C_Spell.GetSpellCooldownDuration(icon.spellID, false)
    if not duration then return gcd:Clear() end
    gcd:SetCooldownFromDurationObject(duration)
    if gcd.SetAlphaFromBoolean then
        gcd:SetAlphaFromBoolean(active, 0, 1)
    else
        -- (A client without it: shown only while the answer can be read.)
        gcd:SetAlpha(Open(active) and not active and 1 or 0)
    end
end

-- The global cooldown's sweep off an icon: the tick unticked, or its spot
-- now holding an item. Once, not on every refresh after.
local function NoGlobal(icon)
    icon.gcdShown = nil
    icon.gcd:Clear()
end

-- A spell's cooldown: on the sweep, grey while it cools down, and in full,
-- dimmed or hidden while it cools down and while it's ready, as chosen.
-- Redone as cooldowns start or end. The global cooldown is left out (as for
-- the grey), so a cast never dims or hides the rest for a moment; a spell
-- with charges cools down, as the game says, only with none left. With
-- Show the global cooldown ticked, it's on a sweep of its own (Global).
local function SpellCooldown(icon, data)
    local id = icon.spellID
    local duration = C_Spell.GetSpellCooldownDuration and C_Spell.GetSpellCooldownDuration(id, true)
    local active = false
    if duration then
        icon.cooldown:SetCooldownFromDurationObject(duration)
        -- Secret in combat: passed to the game as it is, never tested here.
        active = duration:IsActive()
        icon.texture:SetDesaturated(active)
        -- The same either way is set as it is; otherwise the game picks.
        local cooling, ready = Alphas(data, icon.cantCast)
        if cooling == ready then
            Alpha(icon, ready)
        elseif icon.SetAlphaFromBoolean then
            Fade(icon, active, cooling, ready)
        else
            Alpha(icon, 1)
        end
    else
        icon.cooldown:Clear()
        icon.texture:SetDesaturated(false)
        Alpha(icon, 1)
    end
    if data.showGCD then
        Global(icon, active)
    elseif icon.gcdShown then
        NoGlobal(icon)
    end
end

-- A spell's colour and glow: whether it can be used, has the mana, reaches
-- your target, and is lit by the game. Redone as the game says one of these
-- changed (usable, in or out of range, a glow, a new target). These answers
-- are open in a fight (only the cooldown is secret); one the game hides
-- counts as castable. True when whether you can cast it changed: the icon is
-- tinted (blue, grey or red) now and wasn't, or the other way round.
local function SpellState(icon, hasTarget)
    local id = icon.spellID
    local usable, noMana = C_Spell.IsSpellUsable(id)
    local inRange
    if hasTarget and C_Spell.IsSpellInRange then inRange = C_Spell.IsSpellInRange(id, "target") end
    local tint = TINT.ready
    if Open(inRange) and inRange == false then
        tint = TINT.range
    elseif Open(usable) and not usable then
        tint = Open(noMana) and noMana and TINT.mana or TINT.unusable
    end
    Tint(icon, tint)
    -- Lit when the game lights it on your action bars, or, for a reactive
    -- ability the game doesn't light (Overpower after a dodge), once usable.
    SetGlow(icon, Overlayed(id) or (icon.reactive and Open(usable) and usable == true) or false)
    local cantCast = tint ~= TINT.ready
    if icon.cantCast == cantCast then return false end
    icon.cantCast = cantCast
    return true
end

-- One icon: all of it, or just its cooldown ("cooldown") or its colour and
-- glow ("state"). Items and ammo are few, so read in full either way. The
-- colour goes first: on a bar that dims what you can't cast, a change there
-- sets the icon's opacity again, with its cooldown.
local function RefreshIcon(icon, data, hasTarget, follows, part)
    if icon.kind == "ammo" then return RefreshAmmo(icon) end
    if icon.kind == "shards" then return RefreshShards(icon) end
    if ITEM_KINDS[icon.kind] then return RefreshItem(icon, data, follows) end
    local changed = part ~= "cooldown" and SpellState(icon, hasTarget)
    if part ~= "state" or (changed and data.dimUnusable) then SpellCooldown(icon, data) end
    ReagentCount(icon)
end

-- Range: the game says when a spell on your bars goes in or out of range of
-- your target (SPELL_RANGE_CHECK_UPDATE) once asked to watch it, as for
-- Blizzard's own Cooldown Manager, so nothing has to ask again and again as
-- you move. Each spell icon asks for its own spell while the bars are on,
-- and lets it go as it changes spell or the bars go off: one ask and one
-- let-go per icon, as Blizzard's action buttons do for theirs.
local function WatchRange(icon, id)
    if icon.watching == id then return end
    local enable = C_Spell.EnableSpellRangeCheck
    if icon.ranged then pcall(enable, icon.watching, false) end
    icon.watching, icon.ranged = id, false
    if not (id and enable) then return end
    -- A spell with no range (one on yourself) has nothing to watch.
    local has = C_Spell.SpellHasRange and C_Spell.SpellHasRange(id)
    if not Open(has) or has ~= false then icon.ranged = pcall(enable, id, true) end
end

-- Bars ------------------------------------------------------------------------------

local NAMES = 14 -- room for spell names under a row of icons

-- What the border and shadow round a whole bar (when chosen) go round: the
-- icons, never empty room. bar.block is round the full rows; a last row short
-- of them (5 icons, 4 across) gets bar.tail round its own icons, so the room
-- beside them isn't boxed in. Both are empty regions the rings follow.
local function Whole(bar)
    if not bar.block then return end
    bar.block:ClearAllPoints()
    bar.block:SetAllPoints(bar)
    bar.short = false
end

local function Outline(bar, frames, count, across, rows, size, step, data)
    local last = count - (rows - 1) * across -- icons in the last row
    if not bar.block or rows < 2 or last >= across then return Whole(bar) end
    local block, tail = bar.block, bar.tail
    local tall = (rows - 2) * step + size -- from the first row to the last full one
    block:ClearAllPoints()
    if data.wrap == "up" then
        block:SetPoint("BOTTOMLEFT", bar, "BOTTOMLEFT", 0, 0)
        block:SetPoint("TOPRIGHT", bar, "BOTTOMRIGHT", 0, tall)
    else
        block:SetPoint("TOPLEFT", bar, "TOPLEFT", 0, 0)
        block:SetPoint("BOTTOMRIGHT", bar, "TOPRIGHT", 0, -tall)
    end
    -- Growing left, the row's first icon is on its right.
    local left, right = frames[count - last + 1], frames[count]
    if data.grow == "left" then left, right = right, left end
    tail:ClearAllPoints()
    tail:SetPoint("TOPLEFT", left, "TOPLEFT", 0, 0)
    tail:SetPoint("BOTTOMRIGHT", right, "BOTTOMRIGHT", 0, 0)
    bar.short = true
end

-- Icons with sizes of their own (settings per spell, frame.ownSize: a
-- player's idea), in rows of up to perRow as below: each row as wide as its
-- icons and as tall as its biggest, each icon centred in its row's height,
-- the rows lined up by the bar's grow choice. The bar is at least as big as
-- its rows would be at its own size, and as room would keep it. No box round
-- a short last row: its icons aren't one size.
local function Sized(bar, frames, count, data, room, size, spacing)
    local across = math.max(1, math.min(data.perRow, room))
    local lines, under = math.ceil(room / across), spacing + (data.showNames and NAMES or 0)
    local named = data.showNames -- (and under Blizzard's frame, by the row's biggest icon: Style:NameDrop)
    local widths, heights, widest = {}, {}, across * size + (across - 1) * spacing
    for line = 1, lines do
        local first, last = (line - 1) * across + 1, math.min(line * across, count)
        local width, height = 0, size -- a row kept only for room is at the bar's size
        if first <= last then height = 0 end
        for i = first, last do
            local own = frames[i].ownSize or size
            width, height = width + own + (i > first and spacing or 0), math.max(height, own)
        end
        widths[line], heights[line] = width, height
        widest = math.max(widest, width)
    end
    local y = 0
    for line = 1, lines do
        local first, last = (line - 1) * across + 1, math.min(line * across, count)
        local x = data.grow == "left" and widest or data.grow == "right" and 0 or (widest - widths[line]) / 2
        for i = first, last do
            local frame = frames[i]
            local own = frame.ownSize or size
            local inset = (heights[line] - own) / 2
            if data.grow == "left" then x = x - own end
            frame:ClearAllPoints()
            if data.wrap == "up" then
                frame:SetPoint("BOTTOMLEFT", bar, "BOTTOMLEFT", x, y + inset)
            else
                frame:SetPoint("TOPLEFT", bar, "TOPLEFT", x, -(y + inset))
            end
            x = data.grow == "left" and x - spacing or x + own + spacing
        end
        y = y + heights[line] + (line < lines and under + (named and Style:NameDrop(heights[line]) or 0) or 0)
    end
    Whole(bar)
    return widest, y
end

-- Rows of up to perRow icons (or aura spots). Each row lines up by the bar's
-- grow choice: centred, from the right edge (growing left, first icon on the
-- right) or from the left edge; a new row goes below or above. Icons are at
-- their size on screen (ns.IconSize), or one of their own (Sized). Returns
-- the bar's size. With room, the bar keeps its size for that many (the Buffs
-- bar's Only show missing: the spots showing are fewer than its entries),
-- and the ones there line up in it.
function B:Arrange(bar, frames, count, data, room)
    local size, spacing = ns.IconSize(data), data.spacing
    room = math.max(room or count, count)
    -- An empty bar keeps room for three icons so it can still be dragged.
    if room < 1 then
        Whole(bar)
        return 3 * size + 2 * spacing, size
    end
    for i = 1, count do
        if frames[i].ownSize then return Sized(bar, frames, count, data, room, size, spacing) end
    end
    local across = math.max(1, math.min(data.perRow, room))
    local rows = math.ceil(room / across)
    -- (Names under icons drawn like Blizzard's go under its frame: Style:NameDrop.)
    local step = size + spacing + (data.showNames and NAMES + Style:NameDrop(size) or 0)
    local width = across * size + (across - 1) * spacing
    for i = 1, count do
        local row, column = math.floor((i - 1) / across), (i - 1) % across
        local inRow = math.min(across, count - row * across)
        local x
        if data.grow == "left" then
            x = width - size - column * (size + spacing)
        elseif data.grow == "right" then
            x = column * (size + spacing)
        else
            x = (width - (inRow * size + (inRow - 1) * spacing)) / 2 + column * (size + spacing)
        end
        local frame = frames[i]
        frame:ClearAllPoints()
        if data.wrap == "up" then
            frame:SetPoint("BOTTOMLEFT", bar, "BOTTOMLEFT", x, row * step)
        else
            frame:SetPoint("TOPLEFT", bar, "TOPLEFT", x, -row * step)
        end
    end
    -- (Spots that come and go have no box round them: Steady.)
    if count < room then Whole(bar) else Outline(bar, frames, count, across, rows, size, step, data) end
    return width, size + (rows - 1) * step
end

-- The point a bar is held by: the edge its rows grow away from, so icons
-- already there stay put as more are added.
local function Point(data)
    local side = data.grow == "left" and "RIGHT" or data.grow == "right" and "LEFT" or ""
    return (data.wrap == "up" and "BOTTOM" or "TOP") .. side, side
end

-- Where a point is, from the bar's centre.
local function Offset(point, width, height)
    local x = point:find("LEFT") and -width / 2 or point:find("RIGHT") and width / 2 or 0
    local y = point:find("TOP") and height / 2 or point:find("BOTTOM") and -height / 2 or 0
    return x, y
end

local function Round(n)
    return math.floor(n * 10 + .5) / 10
end

local function Place(bar)
    -- A bar being dragged is the game's to move till it's let go (Drop,
    -- which places it then): anchored now (a bag or spell change laying the
    -- bars out again), it would jump back to its old spot, off the cursor.
    if bar.dragging then return end
    local data = bar.data
    local width, height = bar:GetWidth() or 0, bar:GetHeight() or 0
    local point, side = Point(data)
    bar:ClearAllPoints()
    if data.x and data.y then
        -- Kept for another point (from the centre, before rows existed):
        -- moved over to this one without the bar shifting.
        local from = data.point or "CENTER"
        if from ~= point then
            local fromX, fromY = Offset(from, width, height)
            local toX, toY = Offset(point, width, height)
            data.x, data.y, data.point = Round(data.x - fromX + toX), Round(data.y - fromY + toY), point
        end
        bar:SetPoint(point, UIParent, "CENTER", data.x, data.y)
    else
        -- Just above the action bar, growing up from there. All bars spreads
        -- the spots over Utility's (or closes them up) with the bars, so they
        -- never overlap where they didn't at 100.
        local low, y = "BOTTOM" .. side, DEFAULT_Y[bar.key]
        if y then
            y = math.floor(DEFAULT_Y.util + (y - DEFAULT_Y.util) * ns.Get("barScale") / 100 + .5)
        end
        bar:SetPoint(low, UIParent, "BOTTOM", (Offset(low, width, height)), y or 160)
    end
end

-- Where a bar is on screen now: the point it's held by (Point), from the
-- middle of the screen. Nil before it has a place.
local function Where(bar)
    local x, y = bar:GetCenter()
    local cx, cy = UIParent:GetCenter()
    if not (x and cx) then return nil end
    local offsetX, offsetY = Offset(Point(bar.data), bar:GetWidth() or 0, bar:GetHeight() or 0)
    return Round(x - cx + offsetX), Round(y - cy + offsetY)
end

local function SavePosition(bar)
    local x, y = Where(bar)
    if not x then return end
    bar.data.x, bar.data.y, bar.data.point = x, y, (Point(bar.data))
    -- A bar moved by hand leaves the layout it was stacked in.
    if ns.Layout then ns.Layout:Moved() end
    Place(bar)
end

-- The Buffs and Debuffs bars hold Blizzard's secure aura slots, so they are
-- only ever shown, hidden, moved or resized outside combat.
local function Locked(bar)
    return bar.kind == "aura" and InCombatLockdown()
end

-- A bar holding Blizzard's aura containers (B:Hold) is never shown or hidden
-- again: it goes right out instead (gone), which looks the same. Whether a
-- bar is there as you see it, and putting it there or taking it away.
local function Showing(bar)
    return bar:IsShown() and not bar.gone
end

local function SetShowing(bar, show)
    if bar.holds then bar.gone = not show else bar:SetShown(show) end
end

-- Lets go of a bar being dragged, where it is now.
local function Drop(bar)
    if not bar.dragging then return end
    bar.dragging = nil
    bar:StopMovingOrSizing()
    if bar.SetUserPlaced then bar:SetUserPlaced(false) end
    SavePosition(bar)
    -- The Layout page's numbers (and what it says) show where it went.
    if ns.window and ns.window:IsShown() then ns.window:Refresh() end
end

-- The border and shadow round a whole bar, when chosen, only go round icons
-- that stay put. Packed Buffs and Debuffs, Only show missing (or Only when
-- missing on any buff) and a bar that hides when ready or on cooldown come
-- and go (like Blizzard's Tracked Buffs), so they'd leave an empty box
-- behind, as would the greyed Debuffs spots while there's no enemy (unless
-- kept greyed with no target: then bar.enemy stays true). A bar that dims
-- its icons keeps them in place, and its box. (bar: the bar as laid out,
-- when it has been: a tick on another character's buff in a shared profile
-- moves nothing here.)
local function Steady(key, data, bar)
    if ns.AURA_BARS[key] then return ns.BuffBar:Fixed(data) and not ns.BuffBar:Ticked(bar, key, data) end
    return not Hides(data)
end

local function BarDecor(bar)
    -- A layout waiting for the fight to end still has the old shape: keep the
    -- box as it is until then.
    if bar.pendingLayout then return end
    local border, shadow = Style:DecorFor("bar", true)
    local steady = Steady(bar.key, bar.data, bar) and bar.enemy ~= false
    border, shadow = border and steady, shadow and steady
    -- A short last row gets its own, round just its icons (Outline).
    local short = bar.short == true
    local state = (border and "b" or "") .. (shadow and "s" or "") .. (short and "t" or "")
    if bar.decorState == state then return end
    bar.decorState = state
    Style:ShowDecor(bar.decor, border, shadow)
    Style:ShowDecor(bar.tailDecor, border and short, shadow and short)
end

-- Blizzard's packed Buffs and Debuffs icons can't be used by the addon while
-- auras are secret (in combat), so theirs change once the fight is over.
local function GroupDecor(bar)
    if not (bar.groupParts and bar.groupParts[1]) then
        bar.pendingDecor = nil
        return
    end
    if InCombatLockdown() then
        bar.pendingDecor = true
        return
    end
    bar.pendingDecor = nil
    local border, shadow = Style:DecorFor("icon", true)
    for _, parts in ipairs(bar.groupParts) do Style:ShowDecor(parts.decor, border, shadow) end
end

-- Icon details on an aura bar's icons, or on the buff and debuff times over
-- a cooldown bar's icons: the game's aura containers' own icons, changed
-- only out of a fight, as their borders are. One made in a fight waits for
-- it to end.
local function AuraDetails(bar)
    if InCombatLockdown() then
        bar.pendingDetails = true
        return
    end
    bar.pendingDetails = nil
    if bar.kind == "aura" then ns.BuffBar:Details(bar) else ns.IconAuras:Details(bar) end
end

-- Grow arrows -----------------------------------------------------------------------
-- While you arrange your bars (unlocked, or in Edit Mode), small arrows in the
-- accent on each bar show which way it grows as icons come and go: out both
-- ways from its centre, or away from the edge it's held by, and the way a new
-- row goes. Each sits on the bar's edge with its tip just outside, over the
-- icons and the mover, and never takes the mouse. Off unless the Layout
-- page's Show grow arrows is ticked.

local ARROW = ns.MEDIA .. "TourArrow.tga" -- the tour's arrow: a triangle pointing up
local ARROW_WIDE, ARROW_LONG = 12, 7 -- across its base, and from its base to its tip
local ARROW_OUT = 3 -- how far its tip reaches past the bar's edge, inside the mover's

-- The art turned to face a way.
local function Turn(texture, way)
    if way == "left" then
        texture:SetTexCoord(1, 0, 0, 0, 1, 1, 0, 1)
    elseif way == "right" then
        texture:SetTexCoord(1, 1, 0, 1, 1, 0, 0, 0)
    elseif way == "up" then
        texture:SetTexCoord(0, 1, 0, 1)
    else
        texture:SetTexCoord(0, 1, 1, 0)
    end
end

-- An arrow facing a way, with a dark edge so it reads over any icon: the
-- same art in black, a little bigger, underneath it.
local function NewArrow(arrows, way)
    local across = way == "left" or way == "right"
    local width, height = across and ARROW_LONG or ARROW_WIDE, across and ARROW_WIDE or ARROW_LONG
    local edge = arrows:CreateTexture(nil, "ARTWORK", nil, 0)
    edge:SetTexture(ARROW)
    edge:SetSize(width + 2, height + 2)
    edge:SetVertexColor(0, 0, 0, .8)
    local arrow = arrows:CreateTexture(nil, "ARTWORK", nil, 1)
    arrow:SetTexture(ARROW)
    arrow:SetSize(width, height)
    edge:SetPoint("CENTER", arrow, "CENTER")
    Turn(arrow, way)
    Turn(edge, way)
    arrow.edge = edge
    return arrow
end

local function ShowArrow(arrow, shown)
    arrow:SetShown(shown)
    arrow.edge:SetShown(shown)
end

-- A bar's arrows: one at each side edge, and one for new rows. They sit in a
-- frame of their own, above the mover, so they show in Edit Mode too.
local function NewArrows(bar)
    local arrows = CreateFrame("Frame", nil, bar)
    arrows:SetAllPoints()
    arrows:SetFrameLevel(bar:GetFrameLevel() + 22)
    arrows:EnableMouse(false)
    arrows.left, arrows.right, arrows.row = NewArrow(arrows, "left"), NewArrow(arrows, "right"), NewArrow(arrows, "down")
    arrows.left:SetPoint("LEFT", bar, "LEFT", -ARROW_OUT, 0)
    arrows.right:SetPoint("RIGHT", bar, "RIGHT", ARROW_OUT, 0)
    for _, arrow in ipairs({ arrows.left, arrows.right, arrows.row }) do ShowArrow(arrow, false) end -- until pointed (below)
    ns.Theme:Paint(function(accent)
        for _, arrow in ipairs({ arrows.left, arrows.right, arrows.row }) do
            arrow:SetVertexColor(accent[1], accent[2], accent[3], 1)
        end
    end)
    arrows:Hide()
    return arrows
end

-- A bar's arrows shown while the bars are being arranged, if asked for and
-- the bar is there (not gone), and pointed the way it grows now. A Buffs or
-- Debuffs bar waiting for the fight to end still has its old shape, so its
-- arrows wait with it. Packed buffs stay in one row: no new rows to point to.
local function Arrows(bar)
    local arrows = bar.arrows
    arrows:SetShown((unlocked or editMode) and not bar.gone and ns.Get("growArrows") and B:Enabled() or false)
    if bar.pendingLayout then return end
    local data = bar.data
    local rows = not (bar.kind == "aura" and ns.BuffBar:Packed(data))
    local up = data.wrap == "up"
    local state = data.grow .. " " .. (rows and data.wrap or "none")
    if arrows.state == state then return end
    arrows.state = state
    ShowArrow(arrows.left, data.grow ~= "right")
    ShowArrow(arrows.right, data.grow ~= "left")
    ShowArrow(arrows.row, rows)
    Turn(arrows.row, up and "up" or "down")
    Turn(arrows.row.edge, up and "up" or "down")
    local point = up and "TOP" or "BOTTOM"
    arrows.row:ClearAllPoints()
    arrows.row:SetPoint(point, bar, point, 0, up and ARROW_OUT or -ARROW_OUT)
end

local function NewBar(key)
    local bar = CreateFrame("Frame", nil, UIParent)
    bar.key, bar.icons, bar.count = key, {}, 0
    bar.kind = ns.AURA_BARS[key] and "aura" or "cooldown"
    bar.data = ns.BarData(key)
    bar:SetFrameStrata("MEDIUM")
    bar:SetMovable(true)
    bar:SetClampedToScreen(true)
    -- Never takes the mouse itself, there or gone: only its mover does.
    bar:EnableMouse(false)
    bar:Hide()

    local mover = CreateFrame("Frame", nil, bar)
    mover:SetPoint("TOPLEFT", -4, 4)
    mover:SetPoint("BOTTOMRIGHT", 4, -4)
    mover:SetFrameLevel(bar:GetFrameLevel() + 20)
    mover:EnableMouse(true)
    mover:RegisterForDrag("LeftButton")
    mover.fill = mover:CreateTexture(nil, "BACKGROUND")
    mover.fill:SetAllPoints()
    mover.fill:SetColorTexture(.25, .55, 1, .45)
    -- The name sits inside the highlight, so it never covers another bar.
    mover.label = mover:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    mover.label:SetPoint("CENTER")
    mover.label:SetText(ns.BAR_NAMES[key])
    mover:SetScript("OnDragStart", function()
        if not Locked(bar) then
            bar.dragging = true
            -- The Layout page's numbers follow the bar you last dragged.
            B.moving = key
            bar:StartMoving()
        end
    end)
    mover:SetScript("OnDragStop", function() Drop(bar) end)
    -- Hidden mid-drag, it never hears the mouse let go: let go there, so the
    -- bar doesn't follow the cursor and its spot is kept. Locking the bars
    -- (/ccm closed by Escape, a loading screen, death) lets go first anyway
    -- (B:SetUnlocked); this catches any other way it hides.
    mover:SetScript("OnHide", function() Drop(bar) end)
    -- A spell or item dragged from anywhere onto an unlocked bar joins it.
    mover:SetScript("OnReceiveDrag", function() B:Dropped(key) end)
    mover:SetScript("OnMouseUp", function() B:Dropped(key) end)
    -- Held over it, the window's footer says what dropping it here does.
    mover.drop = key
    mover:SetScript("OnEnter", function(self)
        if ns.window and ns.window:IsShown() then ns.window:Note(self) end
    end)
    mover:SetScript("OnLeave", function(self)
        if ns.window then ns.window:Unnote(self) end
    end)
    mover:Hide()
    bar.mover = mover
    bar.arrows = NewArrows(bar)
    -- A border and shadow round the whole bar, when chosen: round its full
    -- rows, and round a short last row's icons (Outline). Empty regions,
    -- with no art, that the rings follow.
    bar.block = bar:CreateTexture(nil, "BACKGROUND")
    bar.block:SetAllPoints(bar)
    bar.tail = bar:CreateTexture(nil, "BACKGROUND")
    bar.tail:SetAllPoints(bar)
    bar.decor = Style:Decor(bar, bar.block)
    bar.tailDecor = Style:Decor(bar, bar.tail)
    BarDecor(bar)
    bars[key] = bar
    return bar
end

-- Your buffs read again a moment later when the game wouldn't answer
-- (Only show missing; with the driver, below).
local Again

local function LayoutAuras(bar, data)
    if InCombatLockdown() then
        bar.pendingLayout = true
        return
    end
    bar.pendingLayout = nil
    if not bar.created then
        bar.created = true
        ns.BuffBar:Create(bar)
    end
    ns.BuffBar:Layout(bar, data)
    if ns.BuffBar:HasEnchants(bar) then B:EnchantClock() end
    if ns.BuffBar:Watches(bar.key, data) or bar.lowUnread then Again(bar) end
    -- Fixed spots go in rows like icons; packed buffs are laid out by the
    -- game in one row (after the spots of buffs ticked Only when missing,
    -- placed by Buffs.lua). With Only show missing the spots showing close
    -- up, in a bar kept the size of all of them.
    if ns.BuffBar:Packed(data) then
        local slots, size = bar.count > 0 and bar.count or 3, ns.IconSize(data)
        bar:SetSize(slots * size + (slots - 1) * data.spacing, size)
        Whole(bar)
    else
        bar:SetSize(B:Arrange(bar, bar.spots, #bar.spots, data, bar.count))
    end
    BarDecor(bar)
    Place(bar)
    Arrows(bar)
end

-- Keybinds: the key that casts each icon's spell (Keybinds.lua), placed and
-- sized as chosen on the Look page, with the countdown moved clear, and the
-- count too on an icon that shows a key.
local function Numbers(cooldown)
    local get = cooldown.GetCountdownFontString
    return type(get) == "function" and get(cooldown) or nil
end

-- (The count 2 in from the corner on an icon drawn like Blizzard's, as on its own.)
local function Room(icon)
    Style:KeyRoom(icon.count, icon, icon.shape.rounded and 2 or 1, Numbers(icon.cooldown), icon.cooldown, icon.lift or 0, icon.keyed)
end

-- (Clear of the icon's countdown at its own size: settings per spell.)
local function KeyLook(icon, size)
    icon.lift = Style:KeyLook(icon.key, icon, size, Style:CountdownSize(size, icon.look and icon.look.size))
    Room(icon)
end

-- The key that casts a bar entry, by name: your bars and the Layout page's
-- drawing of them find it the same way.
function B:KeyFor(name)
    local keys = ns.Keybinds
    return keys and name and keys:ForEntry(ns.Spells:Find(name)) or nil
end

-- A key showing up or going moves the count with it: the addon's own
-- frames only, so in combat too. Nothing is looked up while keybinds are
-- off, and nothing is set again while the key stays the same (a form
-- change asks every icon again).
ShowKey = function(icon)
    local key = ns.Get("keybinds") and B:KeyFor(icon.name) or nil
    if icon.keyed ~= nil and icon.keyText == key then return end
    icon.keyText = key
    icon.keyed = Style:SetKey(icon.key, key)
    Room(icon)
end

local function Layout(bar)
    local data = ns.BarData(bar.key)
    bar.data = data
    bar.namesRounded = Style:Rounded() -- (its names' room as laid out: B:ApplyIconDetails)
    if bar.kind == "aura" then return LayoutAuras(bar, data) end
    -- Families laid out from the list follow what you carry at the next refresh.
    follow = true
    local size, spacing = ns.IconSize(data), data.spacing
    local count, on = 0, B:Enabled()
    -- The list it's laid out from: with Swap with my form, your form's, so a
    -- change of form (or of the list the bar's page sets up) lays it out
    -- again only when that list isn't this one (B:FormChanged).
    local spells = data.spells
    bar.list = spells
    for _, name in ipairs(spells) do
        local entry = ns.Spells:Find(name)
        -- (A hand's weapon enchant or a trinket's buff has no spell: the
        -- Buffs bar's alone, B:Fits.)
        if entry and not entry.hand and not entry.trinket and ns.Spells:ForMe(name, bar.key) and not Absent(name) then
            count = count + 1
            local icon = bar.icons[count] or NewIcon(bar)
            bar.icons[count] = icon
            -- At its own size on this bar, if it has one (settings per spell),
            -- with everything on it sized for that.
            local own = ns.IconSizeFor(bar.key, name, size)
            icon.size, icon.ownSize = own, own ~= size and own or nil
            icon:SetSize(own, own)
            Style:Shape(icon.shape, own)
            -- Its countdown in the spell's own font and size, if it has them
            -- (settings per spell), else the Look page's.
            icon.look = ns.SpellLook(name)
            icon.cooldown:SetCountdownFont(Style:Countdown(own, icon.look))
            icon.cooldown:SetHideCountdownNumbers(not data.showTimer)
            icon.count:SetFontObject(Style:Count(own))
            icon.spellID, icon.name, icon.reactive = entry.spellID, name, REACTIVE[entry.baseName or entry.name] == true
            icon.kind, icon.itemID, icon.slot, icon.current = entry.kind, entry.itemID, entry.slot, entry.current
            -- A spot that showed a spell's global cooldown and now holds an item.
            if icon.gcdShown and ITEM_KINDS[entry.kind] then NoGlobal(icon) end
            WatchRange(icon, on and not ITEM_KINDS[entry.kind] and entry.spellID or nil)
            KeyLook(icon, own)
            ShowKey(icon)
            icon.texture:SetTexture(entry.icon or (entry.spellID and C_Spell.GetSpellTexture(entry.spellID)))
            icon.count:SetText("")
            icon.label:SetWidth(own + spacing)
            icon.label:SetText(Label(entry))
            icon.label:SetShown(data.showNames)
            icon:Show()
        end
    end
    for i = count + 1, #bar.icons do
        bar.icons[i]:Hide()
        bar.icons[i].spellID = nil
        WatchRange(bar.icons[i], nil)
    end
    bar.count = count
    bar:SetSize(B:Arrange(bar, bar.icons, count, data))
    -- Buff and debuff times over the icons, when ticked (IconAuras.lua).
    ns.IconAuras:Layout(bar, data)
    BarDecor(bar)
    Place(bar)
    Arrows(bar)
end

-- The Cooldowns and Utility bars laid out again, when the items left off
-- them change: the addon's own frames only, so safe in a fight too.
local function Relay()
    for _, key in ipairs(ns.BAR_KEYS) do
        local bar = bars[key]
        if bar and bar.kind == "cooldown" then Layout(bar) end
    end
end

-- The Buffs bar with Only show missing (or buffs ticked Only when missing):
-- your buffs read again and, when one came or went (or with all, as the
-- bars are arranged or put back), its spots shown or hidden, its slots
-- switched to match and the spots showing closed up, in the room it keeps
-- for all of them: the bar itself keeps its size and place. (A packed bar's
-- spots are placed with its slots, Buffs.lua.) Out of combat only: in a
-- fight it all waits for the end, as every change to that bar does. Buffs
-- the game wouldn't answer for are read again a moment later (Again).
local function Missing(bar, all)
    if not (bar and bar.holders and B:Enabled() and (ns.BuffBar:Watches(bar.key, bar.data) or ns.BuffBar:HasEnchants(bar))) then return end
    if inCombat or InCombatLockdown() then
        bar.pendingLayout = true
        return
    end
    if bar.pendingLayout then return Layout(bar) end
    local changed = ns.BuffBar:Check(bar)
    Again(bar)
    if not changed and not all then return end
    local spots = ns.BuffBar:Spots(bar)
    ns.BuffBar:Apply(bar)
    if not ns.BuffBar:Packed(bar.data) then B:Arrange(bar, spots, #spots, bar.data, bar.count) end
end

-- Your weapon enchants (Buffs.lua), read as one goes on or off, as a fight
-- ends and as one runs out (B:EnchantClock): each Buffs bar's spots for them
-- lit or greyed at once, in a fight too (the addon's own frames), and any that
-- come and go with them follow as your buffs do (Missing, out of combat).
function B:EnchantsChanged()
    local any = false
    for _, key in ipairs(ns.BAR_KEYS) do
        local bar = ns.BAR_KIND[key] == "buff" and bars[key]
        if bar and ns.BuffBar:HasEnchants(bar) then
            if not any then ns.BuffBar:ReadEnchants() end
            any = true
            ns.BuffBar:PaintEnchants(bar)
            Missing(bar)
            -- (Warn at: a warned one's low-time glow, out of a fight.)
            ns.BuffBar:LowTime(bar, inCombat)
        end
    end
    if any then self:EnchantClock() end
end

-- Looks again just as the soonest enchant runs out: no polling. A newer clock
-- replaces this one.
function B:EnchantClock()
    self:HearAuras()
    local left = ns.BuffBar:NextEnchantEnd()
    local clock = (self.enchantClock or 0) + 1
    self.enchantClock = clock
    if not left then return end
    C_Timer.After(left + .1, function()
        if clock == B.enchantClock then B:EnchantsChanged() end
    end)
end

-- The same for each Buffs bar you have (Buffs 2 too), with all.
local function MissingAll()
    for _, key in ipairs(ns.BAR_KEYS) do
        if ns.BAR_KIND[key] == "buff" then Missing(bars[key], true) end
    end
end

-- Public ------------------------------------------------------------------------------

function B:Enabled()
    return ns.Get("useBars") == true
end

-- One Buffs or Debuffs bar entry for the report: its name and the spell IDs
-- its icon shows. These bars keep their entries in holders, not icons. With
-- Only show missing, or ticked Only when missing, whether it was last read
-- as on you.
local function ReportEntry(bar, i, say)
    local holder, ids = bar.holders and bar.holders[i], {}
    for id in pairs(bar.slotIDs and bar.slotIDs[i] or {}) do ids[#ids + 1] = id end
    table.sort(ids)
    local only = ""
    if ns.BuffBar:Hides(bar, i) then
        only = (ns.BuffBar:OnlyMissing(bar.data) and "" or " | only when missing")
            .. " | on you " .. tostring(bar.up ~= nil and bar.up[i] == true)
    end
    return ("  %d. %s | spells %s%s%s%s%s%s"):format(i, say(holder and holder.label:GetText()), table.concat(ids, ","), only,
        ns.BuffBar:WarnReport(bar, i), ns.BuffBar:EnchantReport(bar, i), ns.BuffBar:ActiveReport(bar, i), ns.BuffBar:TrinketReport(bar, i))
end

-- For /ccm debug (Debug.lua): each of your bars and the icons on it as they
-- are now: what each is, whether it's reactive, the game's usable answer,
-- its glow and whether it was last read as one you can't cast; on the Buffs
-- and Debuffs bars, each entry's spells. Under a cooldown bar's icons, how
-- they show when ready and on cooldown (a player asking why theirs are
-- faded); under the Debuffs bar's, its greyed spots. say turns a secret
-- answer into "secret".
function B:Report(add, say)
    add("Use my bars: " .. tostring(self:Enabled()))
    -- Extra bars in your profile (Core.lua), and icons with sizes of their own.
    local extras, sizes = {}, {}
    for _, key in ipairs(ns.BAR_KEYS) do
        if not ns.EXTRAS_OF[key] then extras[#extras + 1] = key end
        local names = {}
        for name, percent in pairs(type(ns.ProfileLists().iconSize) == "table" and ns.ProfileLists().iconSize[key] or {}) do
            names[#names + 1] = say(name) .. " " .. tostring(percent) .. "%"
        end
        table.sort(names)
        if #names > 0 then sizes[#sizes + 1] = key .. ": " .. table.concat(names, ", ") end
    end
    add(("Extra bars: %s | icon sizes: %s"):format(#extras > 0 and table.concat(extras, ", ") or "none",
        #sizes > 0 and table.concat(sizes, "; ") or "none"))
    for _, key in ipairs(ns.BAR_KEYS) do
        local bar = bars[key]
        if bar then
            local aura = bar.kind == "aura"
            add(("%s bar: shown %s%s, %d %s"):format(key, tostring(Showing(bar)), bar.holds and " (holds aura containers)" or "",
                bar.count or 0, aura and "entries" or "icons"))
            for i = 1, bar.count or 0 do
                if aura then
                    add(ReportEntry(bar, i, say))
                else
                    local icon, usable, noMana = bar.icons[i], nil, nil
                    if icon.spellID and C_Spell.IsSpellUsable then usable, noMana = C_Spell.IsSpellUsable(icon.spellID) end
                    local glow = icon.glow
                    local loop = glow.proc and (", loop " .. tostring(glow.ProcLoop:IsPlaying())) or ""
                    add(("  %d. %s | %s %s | reactive %s | usable %s, no mana %s | glow %s (%s%s) | size %s | range watched %s"
                        .. " | can't cast %s"):format(i, say(icon.name), say(icon.kind), say(icon.spellID or icon.itemID),
                        tostring(icon.reactive), say(usable), say(noMana), tostring(glow:IsShown()), glow.proc and "proc" or "edge", loop,
                        say(icon:GetWidth()), tostring(icon.ranged == true), tostring(icon.cantCast == true)))
                end
            end
            if not aura then
                local data = bar.data
                -- Swap with my form: the game's answers now, and whose list
                -- the bar shows (one picked on its page says so).
                if ns.Swaps(key) then
                    add(("  swap with my form: form %s, stealthed %s, showing %s%s"):format(
                        say(GetShapeshiftFormID and GetShapeshiftFormID()), say(IsStealthed and IsStealthed()),
                        ns.FormName(ns.ShownForm(key)), ns.ShownForm(key) ~= ns.FormNow() and " (picked on its page)" or ""))
                end
                add(("  when ready %s, on cooldown %s, dim when you can't cast it %s, dimmed icons %s%%%s"):format(
                    tostring(data.whenReady), tostring(data.onCooldown), tostring(data.dimUnusable), tostring(data.dimOpacity),
                    data.showGCD and ", global cooldown shown" or ""))
                -- Glow for more procs, while ticked: what it watches, or why not.
                local glows = ns.IconAuras:GlowReport(bar)
                if glows then add(glows) end
            elseif ns.BAR_KIND[key] == "debuff" then
                -- Its greyed spots: ticked, kept with no target, and up now
                -- (a player asking why they go without one).
                local data = bar.data
                add(("  missing greyed %s, keep greyed with no target %s, out of combat %s, greyed spots up %s"):format(
                    tostring(data.showMissing), tostring(data.greyedNoTarget), tostring(data.outOfCombat), tostring(bar.enemy)))
            end
        end
    end
end

-- The border and shadow round a whole bar as set up, for the Layout page's
-- drawing: as chosen on the Look page, round a bar whose icons stay put.
function B:BarDecorFor(key)
    local border, shadow = Style:DecorFor("bar", true)
    local steady = Steady(key, ns.BarData(key), bars[key])
    return border and steady, shadow and steady
end

-- Borders and shadows as chosen on the Look page, round every icon or bar
-- (none while your icons are drawn like Blizzard's).
function B:ApplyDecor()
    local border, shadow = Style:DecorFor("icon", true)
    for _, bar in pairs(bars) do
        BarDecor(bar)
        for _, icon in ipairs(bar.icons or {}) do Style:ShowDecor(icon.decor, border, shadow) end
        ns.BuffBar:HolderDecor(bar)
        GroupDecor(bar)
    end
end

-- The ready glow picked on the Look page, on every icon at once, those not
-- in use too: the addon's own frames only, so in a fight too.
function B:ApplyGlow()
    for _, bar in pairs(bars) do
        for _, icon in ipairs(bar.icons or {}) do UseGlow(icon) end
        -- And the Buffs bar's missing buffs that glow, in the new style.
        for _, holder in ipairs(bar.holders or {}) do
            if holder.glowHost then UseGlow(holder.glowHost) end
        end
        -- And its buffs that glow while they're up (once out of a fight).
        if bar.holders then ns.BuffBar:Actives(bar) end
        -- And a cooldown bar's glows for more procs (once out of a fight).
        if bar.procGlow then ns.IconAuras:ApplyGlows(bar) end
    end
end

-- Keybinds go on the Cooldowns and Utility icons only: the Buffs and Debuffs
-- bars show auras, not casts. Each icon in use goes through fn; a failure is
-- reported once, as for RefreshAll.
local function EachKey(fn)
    for _, bar in pairs(bars) do
        if bar.kind == "cooldown" then
            for i = 1, bar.count do
                local ok, err = pcall(fn, bar.icons[i], bar)
                if not ok and not B.lastError then
                    B.lastError = tostring(err)
                    print("|cffffd100" .. ns.TITLE .. ":|r a bar icon's keybind couldn't update. Please report this: " .. B.lastError)
                end
            end
        end
    end
end

-- The font chosen on the Look page, for the spell names under the icons
-- (the numbers and keys follow their own fonts by themselves).
function B:ApplyFont()
    local font = Style:NameFont()
    for _, bar in pairs(bars) do
        for _, icon in ipairs(bar.icons or {}) do icon.label:SetFontObject(font) end
        for _, holder in ipairs(bar.holders or {}) do holder.label:SetFontObject(font) end
    end
end

-- Keybinds placed and sized as chosen on the Look page (each icon at the
-- size it's laid out at: its own, settings per spell).
function B:ApplyKeybinds()
    EachKey(function(icon, bar)
        KeyLook(icon, icon.size or ns.IconSize(bar.data))
        ShowKey(icon)
    end)
end

-- The keys again after a binding or page change; text only, so in combat too.
function B:ShowKeys()
    EachKey(ShowKey)
end

-- Icon details picked on the Look page, on every icon, those not in use
-- too: the icons square or drawn like Blizzard's, the swipe and edge line,
-- and the countdown's size, colour and spot (still clear of a key in the
-- middle). The addon's own icons at once, in a fight too; the aura
-- containers' as AuraDetails allows. Then the borders and shadows, which
-- skip icons drawn like Blizzard's.
function B:ApplyIconDetails()
    for _, bar in pairs(bars) do
        local size = bar.data and ns.IconSize(bar.data)
        for _, icon in ipairs(bar.icons or {}) do
            local own = icon.size or size
            Style:Shape(icon.shape, own)
            Style:CooldownLook(icon.cooldown)
            if icon.gcd then Style:CooldownLook(icon.gcd) end -- its global cooldown's sweep too, once made
            if own then
                icon.cooldown:SetCountdownFont(Style:Countdown(own, icon.look))
                KeyLook(icon, own)
            end
        end
        AuraDetails(bar)
    end
    -- A bar with names laid out again when the icons' style changes: under
    -- icons drawn like Blizzard's they go under its frame, with more room
    -- under each row. A layout stacked again for that room too.
    local rounded, named = Style:Rounded(), false
    for _, bar in pairs(bars) do
        if bar.data and bar.data.showNames and bar.namesRounded ~= rounded then
            Layout(bar)
            named = true
        end
    end
    if named and ns.Layout then ns.Layout:Stack() end
    self:ApplyDecor()
end

function B:Get(key)
    return bars[key]
end

function B:IsUnlocked()
    return unlocked
end

-- Whether the bars are being arranged: unlocked, or in Edit Mode. Every
-- icon shows in full then, to be placed and sized.
function B:Arranging()
    return unlocked or editMode
end

-- Bars come back in full in combat, with an enemy targeted, while unlocked
-- and while Edit Mode is open; otherwise each follows its out-of-combat
-- choice. A hidden answer about the target counts as an enemy.
local function Awake()
    if inCombat or unlocked or editMode then return true end
    local hostile = UnitExists("target") and UnitCanAttack("player", "target")
    if not Open(hostile) then return true end
    return hostile and true or false
end

-- Bars holding Blizzard's aura containers: the Buffs and Debuffs bars, and
-- Cooldowns or Utility with Show buff and debuff time. A container's own
-- OnShow and OnHide run inside whatever code shows or hides a frame it sits
-- in, so once a bar holds one the addon never shows or hides it again: it
-- stays shown and goes right out instead (gone): fully see-through, with its
-- mover and grow arrows hidden, so nothing on it can be seen, hovered or
-- clicked, as when it was hidden. Everything that places or stacks the bars
-- goes by the same choices either way. Called just before a bar's first
-- container is made (Buffs.lua, IconAuras.lua), never in a fight: a hidden
-- bar is shown now, gone, while it holds nothing yet, so the container is
-- made in sight and signs up for its events as its unit is set. Bars that
-- never hold one are shown and hidden as before.
function B:Hold(bar)
    if bar.holds then return end
    bar.holds = true
    if bar:IsShown() then return end
    bar.gone = true
    bar:SetAlpha(0)
    bar.mover:Hide()
    bar.arrows:Hide()
    bar:Show()
end

function B:UpdateShown()
    local on = self:Enabled()
    if not on then unlocked = false end
    local awake = Awake()
    -- Every bar made: an extra bar you don't have now (removed, or another
    -- profile's) is laid out empty (Rebuild) and goes, as one taken out does.
    for _, key in ipairs(ns.ALL_BAR_KEYS) do
        local bar = bars[key]
        if bar then
            local mode = awake and "show" or bar.data.outOfCombat
            -- A bar taken out of your layout doesn't show at all.
            local out = ns.Layout ~= nil and ns.Layout:IsHidden(key) or not ns.HasBar(key)
            if bar.kind == "aura" then
                -- Shown whenever it has entries (or your debuffs on you
                -- ticked), never in a fight; hiding out of combat fades it
                -- right out instead.
                local has = bar.count > 0 or ns.BuffBar:SelfOn(bar)
                local show = on and not out and (unlocked or has) or false
                if Showing(bar) ~= show then
                    if InCombatLockdown() then bar.pendingShown = true else SetShowing(bar, show) end
                end
                bar:SetAlpha(bar.gone and 0 or mode == "hide" and 0 or mode == "fade" and FADE or 1)
            else
                local show = on and not out and (unlocked or (bar.count > 0 and mode ~= "hide"))
                SetShowing(bar, show and true or false)
                bar:SetAlpha(bar.gone and 0 or mode == "fade" and FADE or 1)
            end
            bar.mover:SetShown(on and unlocked and not bar.gone)
            Arrows(bar)
            BarDecor(bar)
        end
    end
end

-- The grow arrows switched on or off on the Layout page.
function B:ApplyArrows()
    for _, bar in pairs(bars) do Arrows(bar) end
end

-- Whether an entry is left off your bars because you carry none of it (it
-- still shows on the window's drawings of them). For the tests.
function B:Absent(name)
    return absent[name] == true
end

-- Said as an item or potion family goes on a bar while you carry none of it,
-- so it isn't taken for broken: it's left off till you do. Nothing while the
-- game won't say.
function B:CarryNote(name)
    return ns.Spells:Carries(ns.Spells:Find(name)) == false and " You carry none, so it shows once you do." or ""
end

function B:SetUnlocked(value)
    local was = unlocked
    unlocked = value and self:Enabled() or false
    -- A bar still being dragged as they lock is let go where it is first,
    -- before the bars are laid out again (that puts each in its spot).
    if not unlocked then
        for _, bar in pairs(bars) do Drop(bar) end
    end
    -- Items you carry none of show while unlocked, so they can be placed,
    -- and so do buffs on you with Only show missing.
    if self.started and was ~= unlocked then
        Relay()
        MissingAll()
    end
    self:UpdateShown()
    self:RefreshAll()
    -- Unlocked, empty bars show too, so a layout makes room for them.
    if ns.Layout then ns.Layout:Stack() end
    -- A cast bar set free drags with them.
    if ns.CastBar then ns.CastBar:ShowMover() end
end

-- Every icon on the Cooldowns and Utility bars: in full, or one part of each
-- (RefreshIcon). A failure is reported once.
local function Each(part)
    local hasTarget = UnitExists("target") and true or false
    local follows = follow
    follow = false
    for _, key in ipairs(ns.BAR_KEYS) do
        local bar = bars[key]
        if bar and bar.kind == "cooldown" then
            for i = 1, bar.count do
                local ok, err = pcall(RefreshIcon, bar.icons[i], bar.data, hasTarget, follows, part)
                if not ok and not B.lastError then
                    B.lastError = tostring(err)
                    print("|cffffd100" .. ns.TITLE .. ":|r a bar icon couldn't update. Please report this: " .. B.lastError)
                end
            end
        end
    end
end

function B:RefreshAll()
    if not (self.started and self:Enabled()) then return end
    dirty, cooling, tinting = false, false, false
    Each(nil)
end

-- With Use my bars off (the default) the bars are never made: no bars, icons,
-- aura containers or event driver, and your spells and bags aren't read for
-- them. They're made the first time the bars are turned on, and kept (hidden)
-- if they're turned off again.
local Listen -- the driver's events, with the driver below
local HearAuras -- and whether it hears your buffs change (Only show missing)
local HearForms -- and your form (Swap with my form)

-- Lays the bars out again with your spells and items as they are now (and
-- the form you're in, for a bar swapping with it). Off, bars made earlier
-- are laid out with nothing watched and hidden, and none are made.
local function Rebuild()
    Listen()
    -- A spell on both cooldown bars in a form (in a profile switched to, or
    -- one made from a string) stays on Cooldowns.
    ns.KeepApart()
    ns.FollowForm()
    if B:Enabled() or next(bars) then
        ns.Spells:Fresh()
        Recount()
        for _, key in ipairs(ns.BAR_KEYS) do
            local bar = bars[key] or NewBar(key)
            Layout(bar)
            -- A Look page change made in a fight while the bars were off:
            -- the driver didn't hear that fight end, so it's done now.
            if bar.pendingDecor then GroupDecor(bar) end
            if bar.pendingDetails then AuraDetails(bar) end
            bar.retired = nil
        end
        -- An extra bar you don't have now (removed, or another profile's):
        -- frames can't be thrown away, so it's laid out once with nothing on
        -- it (its aura slots and range checks off) and goes (UpdateShown).
        for _, key in ipairs(ns.ALL_BAR_KEYS) do
            local bar = bars[key]
            if bar and not ns.HasBar(key) and not bar.retired then
                Layout(bar)
                bar.retired = not bar.pendingLayout or nil
            end
        end
    end
    B:UpdateShown()
    B:RefreshAll()
    if ns.Layout then ns.Layout:Stack() end
end

-- After a change of yours (a bar's entries, a profile, the bars turned on or
-- off, a layout): your spells and items are read again when next wanted.
function B:Rebuild()
    if not self.started then return end
    ns.Spells:Stale()
    Rebuild()
end

-- Setup changes. Each redraws the bars.

function B:Changed()
    ns.PruneCustom()
    self:Rebuild()
end

-- The cooldown bars a spell can be on, Cooldowns' first (a spell on both
-- shows there), then Utility, then the extra ones in Core.lua's order
-- (Cooldowns 2, Utility 2, Cooldowns 3, Utility 3), as ns.KeepApart keeps them.
local SPELL_BARS = { "cd", "util" }
for _, key in ipairs(ns.EXTRA_BAR_KEYS) do
    if not ns.AURA_BARS[key] then SPELL_BARS[#SPELL_BARS + 1] = key end
end

local function IndexOf(key, name)
    for i, spell in ipairs(ns.BarData(key).spells) do
        if spell == name then return i end
    end
end

-- The cooldown bar a spell is on, and its place there.
function B:Find(name)
    for _, key in ipairs(SPELL_BARS) do
        local index = ns.HasBar(key) and IndexOf(key, name)
        if index then return key, index end
    end
end

-- Whether a spell is on the Buffs or Debuffs bar.
function B:HasAura(key, name)
    return IndexOf(key, name) ~= nil
end

-- Where an entry is on a bar, if it's there.
function B:Index(key, name)
    return IndexOf(key, name)
end

-- The entries on a bar that are for you, in order, and where each one is in
-- the list: a profile shared with another class keeps its spells too.
function B:Mine(key)
    local names, places = {}, {}
    for i, name in ipairs(ns.BarData(key).spells) do
        if ns.Spells:ForMe(name, key) then
            names[#names + 1], places[#places + 1] = name, i
        end
    end
    return names, places
end

-- Joins -------------------------------------------------------------------------------
-- On the Buffs and Debuffs bars an entry can be joined to the one before it;
-- a run of joined entries shows as one icon. The first entry never joins.

-- One at a time: only one of a warlock's Curses, one Bane, one of a hunter's
-- Stings or one of a paladin's Judgements can be yours on a target, and only
-- one Seal, Aura or Aspect on you (each spell says so). With an aura bar's
-- families option (a player's idea, on by default) one beside another of its
-- family on that bar is joined to it as if by hand, and one added there goes
-- beside its family. Nothing in the lists changes, so the option can be
-- unticked at any time. The names are the spells', at any rank or ID; the
-- one-at-a-time rule is the server's, so the list is ours (from Forever's
-- spell texts; Judgements only the ones that leave a debuff).
B.FAMILIES = {
    { key = "banes", name = "Banes", bar = "debuff", spells = { "Bane of Agony", "Bane of Doom", "Bane of Havoc" } },
    { key = "curses", name = "Curses", bar = "debuff", spells = { "Curse of Weakness", "Curse of Recklessness",
        "Curse of Tongues", "Curse of the Elements", "Curse of Exhaustion", "Curse of Idiocy" } },
    { key = "stings", name = "Stings", bar = "debuff", spells = { "Serpent Sting", "Viper Sting", "Scorpid Sting" } },
    { key = "judgements", name = "Judgements", bar = "debuff", spells = { "Judgement of the Crusader", "Judgement of Light",
        "Judgement of Wisdom", "Judgement of Justice", "Judgement of Martyrdom" } },
    { key = "seals", name = "Seals", bar = "buff", spells = { "Seal of Righteousness", "Seal of the Crusader", "Seal of Light",
        "Seal of Wisdom", "Seal of Justice", "Seal of Command", "Seal of Fury", "Seal of Martyrdom" } },
    { key = "auras", name = "Auras", bar = "buff", spells = { "Devotion Aura", "Retribution Aura", "Concentration Aura",
        "Shadow Resistance Aura", "Frost Resistance Aura", "Fire Resistance Aura", "Sanctity Aura" } },
    { key = "aspects", name = "Aspects", bar = "buff", spells = { "Aspect of the Hawk", "Aspect of the Monkey",
        "Aspect of the Cheetah", "Aspect of the Pack", "Aspect of the Beast", "Aspect of the Wild", "Aspect of the Viper",
        "Aspect of the Falcon" } },
}
B.FAMILY_OF = {}
for _, family in ipairs(B.FAMILIES) do
    for _, name in ipairs(family.spells) do B.FAMILY_OF[name] = family end
end

-- An entry's family by its spell's name ("Name", "Name@rank", "Name#ID"); nil for none.
function B:Family(name)
    return type(name) == "string" and B.FAMILY_OF[name:match("^[^@#]+")] or nil
end

-- An entry's family that this bar keeps as one icon now: its own bar's, with
-- the option ticked; nil otherwise.
function B:FamilyHere(key, name)
    if not (ns.AURA_BARS[key] and ns.Get("groupFamilies")) then return nil end
    local family = self:Family(name)
    return family and family.bar == ns.BAR_KIND[key] and family or nil
end

-- Group one-at-a-time spells (the General page) ticked or unticked: unticked
-- splits each family into its own icons, so not past a bar's slots (false
-- and why). True when done.
function B:SetFamilies(on)
    on = on == true
    if ns.Get("groupFamilies") == on then return true end
    ns.Set("groupFamilies", on)
    if not on then
        for _, key in ipairs(ns.BAR_KEYS) do
            if ns.AURA_BARS[key] and self:SlotsUsed(key) > ns.BUFF_SLOTS then
                ns.Set("groupFamilies", true)
                return false, ns.BAR_NAMES[key] .. " has no room to split them: take a spell or two off it first."
            end
        end
    end
    self:Changed()
    return true
end

-- Whether two entries are one family this bar keeps as one icon now.
function B:Kindred(key, a, b)
    local family = self:FamilyHere(key, a)
    return family ~= nil and family == self:Family(b)
end

function B:Joined(key, index)
    local spells = ns.BarData(key).spells
    if not (ns.AURA_BARS[key] ~= nil and index > 1 and spells[index] ~= nil) then return false end
    return ns.Joins(key)[spells[index]] == true or self:Kindred(key, spells[index - 1], spells[index])
end

local function Full(key)
    return ns.BAR_NAMES[key] .. " is full."
end

-- Whether an entry is on a bar already: on the Cooldowns or Utility bar, the
-- one of the two it sits on.
local function OnBar(key, name)
    if ns.AURA_BARS[key] then return IndexOf(key, name) ~= nil end
    return B:Find(name) == key
end

-- Whether a bar has room for an entry, or has it already. An aura bar's
-- slots are for your own icons, one per joined group; its list has room for
-- more. B:Assign and B:SetAura go by it, and so do the checks before a drop.
local function Space(key, name)
    if OnBar(key, name) or IndexOf(key, name) then return true end
    if #ns.BarData(key).spells >= ns.BAR_MAX_SPELLS then return false end
    -- One that goes beside its family on the Debuffs bar shares its icon.
    if B:Beside(key, name) then return true end
    return not ns.AURA_BARS[key] or B:SlotsUsed(key) < ns.BUFF_SLOTS
end

-- The bar's entries in order, with joined ones gathered into one group.
function B:Units(key)
    local units = {}
    for i, name in ipairs(ns.BarData(key).spells) do
        if self:Joined(key, i) and #units > 0 then
            table.insert(units[#units], name)
        else
            units[#units + 1] = { name }
        end
    end
    return units
end

-- How many of an aura bar's slots your entries take: one per icon, so a
-- joined group counts once, and another class's entries take none.
function B:SlotsUsed(key)
    local used = 0
    for _, unit in ipairs(self:Units(key)) do
        for _, name in ipairs(unit) do
            if ns.Spells:ForMe(name, key) then
                used = used + 1
                break
            end
        end
    end
    return used
end

-- Split off, an entry needs an icon of its own; not past the bar's slots.
function B:SetJoined(key, index, on)
    local spells = ns.BarData(key).spells
    if not ns.AURA_BARS[key] or index < 2 or not spells[index] then return false end
    -- A Curse, Bane or Sting beside its family stays one icon with it.
    if not on and self:Kindred(key, spells[index - 1], spells[index]) then return false, B.FAMILY_TIED end
    local joins, name = ns.Joins(key), spells[index]
    local was, used = joins[name], self:SlotsUsed(key)
    joins[name] = on and true or nil
    local now = self:SlotsUsed(key)
    if now > used and now > ns.BUFF_SLOTS then
        joins[name] = was
        return false, Full(key)
    end
    self:Changed()
    return true
end

-- Takes an entry off a bar. When it heads a joined group, the next entry
-- becomes the head, so the rest stay together without joining the entry
-- before.
local function Take(key, index)
    local spells = ns.BarData(key).spells
    local name = spells[index]
    if not name then return end
    if ns.AURA_BARS[key] then
        local joins = ns.Joins(key)
        local after = spells[index + 1]
        if after and not joins[name] then joins[after] = nil end
        joins[name] = nil
    end
    table.remove(spells, index)
    return name
end

-- An aura bar's entry gone from its list (not just moved along it): its own
-- choices go with it (the icon shown faded, Glow when missing, Count ticks,
-- Only when missing, Glow while active, Warn at, Dim until Warn at), so
-- putting it back starts afresh, as after a reload (Core.lua Lists). Any
-- bar's: its own countdown look too (settings per spell), once none of your
-- lists has it.
local function Forget(key, name)
    if name then
        ns.ForgetSpellLook(name)
        -- And its icon's own size on this bar, once none of its lists has it.
        ns.ForgetOwnSize(key, name)
    end
    if not (ns.AURA_BARS[key] and name) then return name end
    ns.MissingPicks(key)[name], ns.GlowMissing(key)[name], ns.CountTicks(key)[name] = nil, nil, nil
    if ns.BAR_KIND[key] == "buff" then ns.OnlyWhenMissing(key)[name], ns.GlowActive(key)[name], ns.HandOthers(key)[name] = nil, nil, nil end
    ns.SetWarnAt(key, name, nil)
    ns.DimUntilWarn(key)[name] = nil
    return name
end

-- Takes an entry off the other cooldown bar's lists that show beside this
-- bar's list now (ns.BesideLists): with Swap with my form the two bars'
-- lists can differ by form, and a spell sits on one of the two in each.
-- An extra cooldown bar (Cooldowns 2 or 3, Utility 2 or 3) never swaps: a spell on it
-- is on no other cooldown bar's list, in any form, and one put on another
-- comes off it.
local function Apart(key, name)
    local lists = ns.BesideLists(key, ns.ShownForm(key))
    for _, other in ipairs(SPELL_BARS) do
        if other ~= key and ns.HasBar(other) and (not ns.CanSwap(other) or not ns.CanSwap(key)) then
            for _, list in ipairs(ns.BarLists(other)) do lists[#lists + 1] = list end
        end
    end
    for _, list in ipairs(lists) do
        for i = #list, 1, -1 do
            if list[i] == name then table.remove(list, i) end
        end
    end
end

-- Puts a spell on the Cooldowns or Utility bar, or takes it off with no bar;
-- it sits on one of the two at a time, in every form. Never twice on a list.
-- Returns false when the bar is full.
function B:Assign(name, key)
    local current, index = self:Find(name)
    if current == key then return true end
    if key and not Space(key, name) then return false end
    if current then
        Take(current, index)
        ns.ForgetOwnSize(current, name)
    end
    if not key then ns.ForgetSpellLook(name) end
    if key then
        if not IndexOf(key, name) then
            local spells = ns.BarData(key).spells
            spells[#spells + 1] = name
        end
        Apart(key, name)
    end
    self:Changed()
    return true
end

-- The Buffs and Debuffs bars are tracked separately, so a spell can be on a
-- cooldown bar and an aura bar at once (a cooldown that also buffs you).
-- Returns false when the bar is full.
function B:SetAura(key, name, on)
    local index = IndexOf(key, name)
    if on and index or not on and not index then return true end
    local spells = ns.BarData(key).spells
    if on then
        if not Space(key, name) then return false end
        -- A Curse, Bane or Sting goes beside its family on the Debuffs bar
        -- (the families option), joining its icon; anything else at the end.
        table.insert(spells, self:Beside(key, name) or #spells + 1, name)
    else
        Forget(key, Take(key, index))
    end
    self:Changed()
    return true
end

local function Added(key, name)
    return "Added " .. name .. " to " .. ns.BAR_NAMES[key] .. "."
end

-- Said of an entry dropped on a bar it's on already, which changes nothing.
local function Already(key, name)
    return (name:gsub("^%l", string.upper)) .. " is already on " .. ns.BAR_NAMES[key] .. "."
end

local function Named(name)
    local entry = ns.Spells:Find(name)
    return entry and entry.name or name
end

-- Why an entry can't go on a bar where it wouldn't show for you: a buff added
-- by name that another class casts on you shows on the Buffs bar only, and
-- anywhere else it would be hidden with no icon left to drag it back. The
-- same for a spell added there: another class's, or a buff's ID on the
-- Cooldowns or Utility bar, which no one ever learns.
local function Unshown(name, key)
    return Named(name) .. " can't show on the " .. ns.BAR_NAMES[key] .. " bar for you."
end

-- Said as your pet's ability goes on a cooldown bar (added, moved or
-- swapped there) while no pet that knows it is out (Spells.lua S:PetAway):
-- it's on the bar, hidden till one is, so it isn't taken for broken. Of one
-- of two swapped (by), by its name.
local function PetNote(name, key, by)
    if not ns.Spells:PetAway(name, key) then return "" end
    return " " .. (by and Named(name) or "It") .. " shows while a pet that knows it is out."
end

-- What a drop would do, said while it's held over the bar: put the entry on
-- it, move it there from the other cooldown bar, or nothing, as it's there.
local function Preview(key, plan)
    if plan.there then return Already(key, plan.shown) end
    local from = not ns.AURA_BARS[key] and B:Find(plan.name)
    if from and from ~= key then
        return "Drop to move " .. plan.shown .. " from " .. ns.BAR_NAMES[from] .. " to " .. ns.BAR_NAMES[key] .. "."
    end
    return "Drop to add " .. plan.shown .. " to " .. ns.BAR_NAMES[key] .. "."
end

-- Whether an entry can show on a bar: true, or false and why not. Items put
-- no aura on anyone, a fixed rank adds nothing to an aura bar (it counts
-- every rank already), procs are buffs on you with no cooldown of their
-- own, and a passive has nothing to track (but for a buff or debuff of its
-- own, on that bar). Anything not known here (another class's, say) may go
-- anywhere. With byID, an ID was dragged or typed for it, which B:Add judges
-- on its own for being passive.
function B:Fits(key, entry, byID)
    if not entry then return true end
    local bar = ns.BAR_NAMES[key]
    if ns.AURA_BARS[key] and ns.Spells:IsItem(entry) then
        return false, "Items can't go on the " .. bar .. " bar."
    end
    if ns.AURA_BARS[key] and entry.kind == "rank" then
        return false, "Fixed ranks can't go on the " .. bar .. " bar, which counts every rank already."
    end
    if entry.kind == "proc" and ns.BAR_KIND[key] ~= "buff" then
        return false, "Procs only go on the Buffs bar."
    end
    -- (A warlock's Firestone or Spellstone, or a scroll's imbue once added: Spells.lua.)
    if entry.kind == "enchant" and ns.BAR_KIND[key] ~= "buff" then
        return false, entry.name .. " only goes on the Buffs bar, where it lights while it's on your weapon."
    end
    -- (Trinket 1 or Trinket 2: the buff your trinket's use puts on you, Spells.lua.)
    if entry.kind == "trinket" and ns.BAR_KIND[key] ~= "buff" then
        return false, entry.name .. " only goes on the Buffs bar, where it lights while your trinket's buff is on you."
    end
    local passive = not byID and ns.Spells:PassiveNote(entry.key, key)
    if passive then return false, passive end
    return true
end

-- B:Add's checks, which change nothing: false and why not, or true and the
-- plan: the name it's kept under and shown by, the IDs to remember it by
-- (and what was remembered before, when the ID given joins those), and
-- whether it's on the bar already with nothing new. B:Add and B:CanAdd both
-- go by it, so what the footer says while a spell is held over a bar is
-- what dropping it does. On the Buffs or Debuffs bar, an ID for another
-- spell of a name in your lists is kept pinned to that ID (Spells.lua
-- S:Pin): an entry of its own, with nothing remembered, and the entry of
-- its name left watching what it did. One that could never show for you
-- once on (another class's spell, a buff's ID on the Cooldowns bar) is
-- turned away, as a drag from another bar is: once on, it would be hidden,
-- with nothing in the window to take it off. Then the third answer is
-- true. One you or your pet don't know yet (a talent not taken) goes on,
-- shown once you do.
local function Vet(key, text)
    -- A debuff on you (Weakened Soul): no bar shows it by name, the Buffs
    -- or Debuffs bar's tick does.
    local selfNote = ns.Spells:SelfDebuffNote(text)
    if selfNote then return false, selfNote end
    -- (With the bar: your pet's ability added before by none of the pet's
    -- IDs, Spell Lock by its silence, goes on a cooldown bar by the pet's
    -- spell, given as if typed.)
    local found, ids, given = ns.Spells:Resolve(text, key)
    if not found then return false, ids end
    local pinned = given and ns.Spells:Pin(given, key)
    local shown = pinned and ns.Spells:PinName(found, given)
    if pinned then found, ids = pinned, nil end
    local entry = ns.Spells:Find(found)
    local fits, why = B:Fits(key, entry, given ~= nil)
    if not fits then return false, why end
    -- A scroll's imbue not added yet (Imbue Flame): the Buffs bar's alone, as
    -- once added (B:Fits), and not offered on the other bars' pages.
    if not entry and ns.IMBUE_SPELLS and ns.IMBUE_SPELLS[found] and ns.BAR_KIND[key] ~= "buff" then
        return false, found .. " only goes on the Buffs bar, where it lights while it's on your weapon.", true
    end
    local passive = ns.Spells:AddNote(text, key)
    if passive then return false, passive end
    local plan = { name = found, shown = entry and entry.name or shown or found }
    if ids and not entry then
        plan.remember = ids
    elseif given and entry and entry.added and not pinned then
        local merged, known = {}, false
        for i, id in ipairs(entry.added) do
            merged[i] = id
            known = known or id == given
        end
        if not known then
            merged[#merged + 1] = given
            plan.remember, plan.before = merged, entry.added
        end
    end
    -- Judged as it will be: by what it's remembered by, a new pinned one
    -- by its ID, one added before by what it was.
    local remember = plan.remember or (pinned and not entry and { given }) or (entry and entry.added) or nil
    if not ns.Spells:ForMe(found, key, remember) then return false, Unshown(plan.shown, key), true end
    if not Space(key, found) then return false, Full(key) end
    plan.there = plan.remember == nil and OnBar(key, found)
    return true, plan
end

-- Whether a spell, by name or ID, could show on a bar for you once added
-- (now, or once you or your pet know it): what the bar's page offers under
-- Other spells (BarPage.lua), so nothing it offers vanishes for good once
-- ticked. Turned away for anything else (the bar full, say), it's still
-- offered, and ticking it says why.
function B:WouldShow(key, text)
    local ok, _, hidden = Vet(key, text)
    return ok or not hidden
end

-- What B:Add would do, changing nothing: true and what (said while a spell
-- is held over the bar), or false and why not, in B:Add's own words.
function B:CanAdd(key, text)
    local ok, plan = Vet(key, text)
    if not ok then return false, plan end
    return true, Preview(key, plan)
end

-- Puts a spell, by name or ID, on a bar: true and what happened, or false
-- and why not. Spells outside your spellbook are remembered by name. Also
-- gives the name it's kept under. A passive is turned away as dragged or
-- typed, by its own ID: the troll's Regeneration isn't the mage's. An ID
-- given for a name already added (the troll's Regeneration, saved by another
-- character) is remembered with it, so the mage's goes on by its ID; on the
-- Buffs or Debuffs bar, one its entry doesn't watch goes on pinned instead,
-- as an icon of its own (the second Energized).
function B:Add(key, text)
    local ok, plan = Vet(key, text)
    if not ok then return false, plan end
    local found = plan.name
    if plan.remember then ns.AddCustom(found, plan.remember) end
    local done
    if ns.AURA_BARS[key] then done = self:SetAura(key, found, true) else done = self:Assign(found, key) end
    -- Already on this bar, it shows now with the ID it was given; a full bar
    -- leaves what was remembered as it was.
    if plan.before then
        if done then self:Changed() else ns.AddCustom(found, plan.before) end
    end
    ns.PruneCustom()
    if not done then return false, Full(key) end
    local said = plan.there and Already(key, plan.shown) or Added(key, plan.shown)
    -- Your pet's ability with no pet that knows it out (Spells.lua
    -- S:PetAway): on the bar, hidden till one is, so it isn't taken for broken.
    return true, said .. PetNote(found, key) .. self:CarryNote(found), found
end

-- The same, at a place in the bar's list (where the entry clicked is): the
-- entries from there on move along one.
function B:AddAt(key, text, spot)
    local ok, message, name = self:Add(key, text)
    local from = ok and IndexOf(key, name)
    if from and spot < from then self:MoveTo(key, from, spot) end
    return ok, message
end

-- B:AddItem's checks, which change nothing, the same way: the plan has the
-- entry's key and name, what's said once it's on (extra), whether a note
-- about carrying none goes with that, and whether it's on the bar already.
local function VetItem(key, itemID)
    if ns.AURA_BARS[key] then return false, "Items can't go on the " .. ns.BAR_NAMES[key] .. " bar." end
    local plan
    if ns.Spells:IsAmmo(itemID) then
        if not ns.Spells:UsesAmmo() then return false, "Your class doesn't use ammo." end
        plan = { name = "ammo", shown = "your ammo", extra = " It counts whatever ammo you have equipped." }
    elseif itemID == ns.Spells.SOUL_SHARD then
        if not ns.Spells:UsesShards() then return false, "Only warlocks use Soul Shards." end
        plan = { name = "shards", shown = "your Soul Shards", extra = " It counts how many you carry." }
    else
        local family = ns.Spells:Family(itemID)
        if family then
            plan = { name = family.key, shown = family.name, extra = " It shows the best one you carry.", carry = true }
        else
            local item = "item:" .. itemID
            for _, slot in ipairs({ 13, 14 }) do
                if GetInventoryItemID("player", slot) == itemID then item = "slot:" .. slot end
            end
            local entry = ns.Spells:Find(item)
            if not entry then return false, "That item has no cooldown to show." end
            plan = { name = item, shown = entry.name, extra = "", carry = true }
        end
    end
    if not Space(key, plan.name) then return false, Full(key) end
    plan.there = OnBar(key, plan.name)
    return true, plan
end

-- An item that puts a weapon enchant on (a poison, a Firestone, a Scroll of
-- Imbue Flame) can't go on the Buffs bar, but what it puts on can: the
-- spell it casts, by its name where your lists have it (a rogue's Instant
-- Poison, a warlock's Firestone), else by its ID (a scroll's imbue, found by
-- its name: Spells.lua). Any rank of it on the bar already is what it is
-- told it is (Instant Poison VI there, for an Instant Poison V), as that one
-- lights for every rank's (Buffs.lua). With none on, and no entry of the
-- spell's own name in your lists, the highest rank of it they do have
-- (Crippling Poison II, for an item that casts Crippling Poison). Nil for
-- any other item or bar, or while the game won't say.
local RANK_NUMERALS = { II = 2, III = 3, IV = 4, V = 5, VI = 6 }
local function EnchantSpell(key, itemID)
    local api = C_Item and C_Item.GetItemSpell
    if ns.BAR_KIND[key] ~= "buff" or not api then return nil end
    local ok, name, spellID = pcall(api, itemID)
    if not (ok and Open(name) and type(name) == "string") then return nil end
    local enchants = ns.WEAPON_ENCHANTS
    local family = enchants and enchants[name]
    if not family then return nil end
    local data = ns.BarData(key)
    for _, onBar in ipairs(data and data.spells or {}) do
        if rawequal(enchants[onBar], family) then return onBar end
    end
    if ns.Spells:Find(name) then return name end
    local best, top = nil, 0
    for _, entry in ipairs(ns.Spells:Fresh()) do
        if rawequal(enchants[entry.name], family) then
            local rank = RANK_NUMERALS[entry.name:match(" (%u+)$") or ""] or 1
            if rank > top then best, top = entry.key, rank end
        end
    end
    if best then return best end
    if not (Open(spellID) and type(spellID) == "number") then return name end
    return tostring(spellID)
end

-- What B:AddItem would do, changing nothing, as B:CanAdd does for spells.
-- An item that puts a weapon enchant on is what it puts on (EnchantSpell).
function B:CanAddItem(key, itemID)
    local spell = EnchantSpell(key, itemID)
    if spell then return self:CanAdd(key, spell) end
    local ok, plan = VetItem(key, itemID)
    if not ok then return false, plan end
    return true, Preview(key, plan)
end

-- An item with a cooldown: an equipped trinket follows its slot. Ammunition
-- of any kind is your ammo, which counts whatever ammo you have equipped (a
-- class that never uses ammo is told so), and any rank of a healthstone or
-- potion is its family, which shows the best one you carry. On the Buffs
-- bar, a poison, stone or scroll puts on what it casts (EnchantSpell).
function B:AddItem(key, itemID)
    local spell = EnchantSpell(key, itemID)
    if spell then return self:Add(key, spell) end
    local ok, plan = VetItem(key, itemID)
    if not ok then return false, plan end
    if not self:Assign(plan.name, key) then return false, Full(key) end
    local carry = plan.carry and self:CarryNote(plan.name) or ""
    if plan.there then return true, Already(key, plan.shown) .. carry end
    return true, Added(key, plan.shown) .. plan.extra .. carry
end

local ONLY = "Only spells and items can go on a bar."

-- What the cursor holds, read so a hidden value is never taken for anything:
-- "spell" or "item" and its ID, "other" for anything else or what the game
-- won't say, or nil when it holds nothing.
local function Held()
    local kind, first, _, spellID = GetCursorInfo()
    if Open(kind) and kind == nil then return nil end
    if Open(kind) and kind == "spell" and Open(spellID) and type(spellID) == "number" then return "spell", spellID end
    if Open(kind) and kind == "item" and Open(first) and type(first) == "number" then return "item", first end
    return "other"
end

-- The same as one value ("spell:81"), to tell whether the cursor still holds
-- what it did; nil when it holds nothing.
function B:Holding()
    local kind, id = Held()
    if not kind then return nil end
    return id and (kind .. ":" .. id) or kind
end

-- What dropping what the cursor holds on a bar would do, changing nothing:
-- true and what, or false and why not, as B:AddFromCursor would say. Nil
-- when it holds nothing.
function B:CursorNote(key)
    local kind, id = Held()
    if not kind then return nil end
    if kind == "spell" then return self:CanAdd(key, tostring(id)) end
    if kind == "item" then return self:CanAddItem(key, id) end
    return false, ONLY
end

-- What's on the cursor, dropped on a bar: a spell from any spellbook or an
-- action bar, or an item from your bags or character panel. Nil when the
-- cursor holds nothing. Only what joins the bar is let go of; anything
-- turned away stays on the cursor.
function B:AddFromCursor(key)
    local kind, id = Held()
    if not kind then return nil end
    local ok, message
    if kind == "spell" then
        ok, message = self:Add(key, tostring(id))
    elseif kind == "item" then
        ok, message = self:AddItem(key, id)
    else
        ok, message = false, ONLY
    end
    if ok then ClearCursor() end
    return ok, message
end

-- A drop on one of the addon's own frames for a bar; says what happened in
-- the window. Turned away, it's still held, and why stays in the footer
-- until it isn't (not after, as a message would). False when nothing was
-- dropped.
function B:Dropped(key)
    local ok, message = self:AddFromCursor(key)
    if ok == nil then return false end
    if ns.window and ns.window:IsShown() then
        if ok then ns.window:Say(message) else ns.window:Refused(message) end
        ns.window:Refresh()
    end
    return true
end

function B:Move(key, index, delta)
    self:MoveTo(key, index, index + delta)
end

-- Moves a spell to another place on its bar, as dragged in the window. A
-- moved entry leaves its joined group; dropped inside another group, it
-- joins that one rather than splitting it. On its own it needs an icon of
-- its own, so a full bar keeps it where it was.
function B:MoveTo(key, from, to)
    local spells = ns.BarData(key).spells
    if from == to or not spells[from] or not spells[to] then return end
    local aura = ns.AURA_BARS[key] ~= nil
    local joins, saved, used = aura and ns.Joins(key), {}, 0
    if joins then
        for entry, on in pairs(joins) do saved[entry] = on end
        used = self:SlotsUsed(key)
    end
    local name = Take(key, from)
    table.insert(spells, to, name)
    local after = spells[to + 1]
    if aura and to > 1 and after and joins[after] then joins[name] = true end
    local now = aura and self:SlotsUsed(key) or 0
    if now > used and now > ns.BUFF_SLOTS then
        table.remove(spells, to)
        table.insert(spells, from, name)
        for entry in pairs(joins) do joins[entry] = nil end
        for entry, on in pairs(saved) do joins[entry] = on end
        return false, Full(key)
    end
    self:Changed()
    return true
end

function B:Remove(key, index)
    if not Forget(key, Take(key, index)) then return end
    self:Changed()
end

-- An entry dragged off a bar: true and what happened. Named before it goes:
-- one in no other list (a spell pinned to one ID) leaves your list with it.
function B:TakeOff(key, name)
    local index = IndexOf(key, name)
    if not index then return false end
    local shown = Named(name)
    self:Remove(key, index)
    return true, "Took " .. shown .. " off " .. ns.BAR_NAMES[key] .. "."
end

-- Whether an entry dragged from another bar can go on this one (B:Transfer,
-- B:CanTrade): true, or false and why not. Your class's pet ability going
-- onto a cooldown bar (Spells.lua S:PetMove: a hunter's Growl or Scorpid
-- Poison, a warlock's Seduction or Spell Lock) is judged as adding it there
-- by name is (Vet), by the IDs it goes on with, so it moves whichever pet
-- is out, or none, and stays hidden there till a pet that knows it is out;
-- then also the IDs to remember it by, when the pet's own spell joins them
-- (Spell Lock put on the Debuffs bar by its silence: it goes by the
-- felhunter's spell there). Anything else as before. (Squirt, 2026-11-13,
-- "Yea": the move was turned away, "can't show on the ... bar for you".)
local function Movable(name, to)
    local remember, joined = ns.Spells:PetMove(name, to)
    local fits, why = B:Fits(to, ns.Spells:Find(name), joined)
    if not fits then return false, why end
    if not ns.Spells:ForMe(name, to, remember) then return false, Unshown(name, to) end
    return true, joined and remember or nil
end

-- An entry dragged from one bar onto another: true and what happened, or
-- false and why not.
function B:Transfer(from, to, name)
    if from == to or not IndexOf(from, name) then return false end
    local fits, remember = Movable(name, to)
    if not fits then return false, remember end
    -- Your pet's ability takes its pet's own spell with it (Movable); a full
    -- bar leaves what was remembered as it was.
    local before = remember and ns.CustomSpells()[name]
    if remember then ns.AddCustom(name, remember) end
    local ok
    if ns.AURA_BARS[to] then ok = self:SetAura(to, name, true) else ok = self:Assign(name, to) end
    if not ok then
        if remember then ns.AddCustom(name, before) end
        return false, Full(to)
    end
    -- Between the two cooldown bars it's already moved; otherwise take it off.
    local index = IndexOf(from, name)
    if index then self:Remove(from, index) end
    return true, "Moved " .. Named(name) .. " to " .. ns.BAR_NAMES[to] .. "." .. PetNote(name, to)
end

local function Swapped(name, other)
    return "Swapped " .. Named(name) .. " and " .. Named(other) .. "."
end

-- Two entries on a bar trade places, as dragged one onto the other on the
-- bar's page. On the Buffs and Debuffs bars each place keeps whether it's
-- joined to the one before, so the icons stay as they were with the two
-- entries in each other's: a full bar needs no more room. True and what
-- happened.
function B:Swap(key, a, b)
    local spells = ns.BarData(key).spells
    local name, other = spells[a], spells[b]
    if a == b or not (name and other) then return false end
    if ns.AURA_BARS[key] then
        local joins = ns.Joins(key)
        joins[name], joins[other] = joins[other], joins[name]
    end
    spells[a], spells[b] = other, name
    self:Changed()
    return true, Swapped(name, other)
end

-- The places in a bar's list of the icon holding the entry at index: a
-- joined group on the Buffs and Debuffs bars, otherwise just that entry.
local function Group(key, index)
    local first, last = index, index
    while B:Joined(key, first) do first = first - 1 end
    while B:Joined(key, last + 1) do last = last + 1 end
    return first, last
end

-- Why the icon holding the entry at index can't leave its bar: it's a joined
-- group. One joined only to entries hidden for you (another character's, in
-- a shared profile) looks like any other icon, so that says so. Nil when it's
-- on its own.
local function Tied(key, index)
    local first, last = Group(key, index)
    if first == last then return nil end
    local spells, yours = ns.BarData(key).spells, 0
    for i = first, last do
        if ns.Spells:ForMe(spells[i], key) then yours = yours + 1 end
    end
    if yours > 1 then return "Joined icons only swap on their own bar." end
    return Named(spells[index]) .. " is joined to another character's spell, so it only swaps on " .. ns.BAR_NAMES[key] .. "."
end

-- One at a time (above, by Joins): said when the join button would split a
-- spell from its family.
B.FAMILY_TIED = "One family's spells side by side stay one icon while Group one-at-a-time spells (General page) is ticked."

-- Where on an aura bar one of a family added now goes (a Curse on the
-- Debuffs bar, a Seal on the Buffs bar): just after its family's last icon,
-- so it joins it (the families option). Nil when it has no family there, or
-- the option is off.
function B:Beside(key, name)
    local family, spells = self:FamilyHere(key, name), ns.BarData(key).spells
    if not family then return nil end
    for i = #spells, 1, -1 do
        if spells[i] ~= name and self:Family(spells[i]) == family then
            local _, last = Group(key, i)
            return last + 1
        end
    end
    return nil
end

-- Which entry of a joined icon shows, faded, while none of them is up (a
-- player's idea): the one picked, or else the first of yours. Picking it
-- again unpicks it.
function B:PickMissing(key, index)
    local spells = ns.BarData(key).spells
    if not (ns.AURA_BARS[key] and spells[index]) then return false end
    local first, last = Group(key, index)
    if first == last then return false end
    local picks, name = ns.MissingPicks(key), spells[index]
    local was = self:Picked(key, index)
    for i = first, last do picks[spells[i]] = nil end
    picks[name] = not was or nil
    self:Changed()
    return true
end

-- Glow when missing (a player's idea: a Seal that fell off): a buff on the
-- Buffs bar whose icon glows while it's missing, so you see to recast it,
-- or a debuff of yours on the Debuffs bar while it's missing from your
-- target (the same player: Judgement of the Crusader fallen off a mob).
function B:SetGlowMissing(key, name, on)
    if not ns.AURA_BARS[key] or not IndexOf(key, name) then return false end
    ns.GlowMissing(key)[name] = on and true or nil
    self:Changed()
    return true
end

function B:GlowsMissing(key, name)
    return ns.AURA_BARS[key] ~= nil and ns.GlowMissing(key)[name] == true
end

-- Only when missing (asked for by a player): one buff on the Buffs bar shown
-- only while it's missing from you, in a spot of its own, as Only show
-- missing does for every buff (Buffs.lua). Not on the Debuffs bar: your
-- target's debuffs change in a fight, when the addon can't read them.
function B:SetOnlyWhenMissing(key, name, on)
    if ns.BAR_KIND[key] ~= "buff" or not IndexOf(key, name) then return false end
    ns.OnlyWhenMissing(key)[name] = on and true or nil
    self:Changed()
    return true
end

function B:OnlyWhenMissing(key, name)
    return ns.BAR_KIND[key] == "buff" and ns.OnlyWhenMissing(key)[name] == true
end

-- Whether a buff's icon has a greyed spot while it's missing (for Glow when
-- missing): with missing ones greyed or Only show missing, or with it or a
-- buff of yours joined to it ticked Only when missing (another character's,
-- in a shared profile, gives the icon no spot here: Buffs.lua F:Layout).
function B:MissingSpot(key, name)
    local data = ns.BarData(key)
    if not ns.BuffBar:Packed(data) then return true end
    local index = IndexOf(key, name)
    if ns.BAR_KIND[key] ~= "buff" or not index then return false end
    local first, last = Group(key, index)
    for i = first, last do
        local spell = data.spells[i]
        if self:OnlyWhenMissing(key, spell) and ns.Spells:ForMe(spell, key) then return true end
    end
    return false
end

-- Count ticks (a player's idea: Bane of Agony's ticks): a debuff on the
-- Debuffs bar whose icon counts its ticks so far, at its own pace (in
-- seconds, from the game's data: ns.TICK_PERIODS, Buffs.lua). Only debuffs
-- that tick; a trap kept under its old name too.
function B:TickPace(name)
    if type(name) ~= "string" or type(ns.TICK_PERIODS) ~= "table" then return nil end
    return ns.Spells:ByName(ns.TICK_PERIODS, name:match("^[^@#]+"))
end

function B:SetCountTicks(key, name, on)
    if ns.BAR_KIND[key] ~= "debuff" or not IndexOf(key, name) or not self:TickPace(name) then return false end
    ns.CountTicks(key)[name] = on and true or nil
    self:Changed()
    return true
end

function B:CountsTicks(key, name)
    return ns.BAR_KIND[key] == "debuff" and ns.CountTicks(key)[name] == true
end

-- Warn at N seconds left (a player's idea: Siphon Life with 3 seconds left
-- on the target, Demon Armor with 10 minutes left on you): an entry on the
-- Buffs or Debuffs bar whose icon warns as its time runs low (seconds; nil
-- or 0 for none). The game draws it, as the addon can't read an aura's time
-- in a fight (Buffs.lua F:Warns): its countdown turns red, a red edge shows
-- round a fixed spot, and out of a fight your own buff's spot glows. The
-- icons change once out of a fight. False for an entry not on that bar.
function B:SetWarnAt(key, name, seconds)
    if seconds == 0 then seconds = nil end
    if not ns.AURA_BARS[key] or not IndexOf(key, name) or (seconds ~= nil and not ns.WarnValue(seconds)) then return false end
    if ns.SetWarnAt(key, name, seconds) then self:Changed() end
    return true
end

function B:WarnAt(key, name)
    if not ns.AURA_BARS[key] then return nil end
    return ns.WarnAt(key)[name]
end

-- Whether an entry's warning can show: not on the Buffs bar with Only show
-- missing, nor for a buff ticked Only when missing or joined to one (it has
-- no icon while it's up).
function B:WarnUsable(key, name)
    if not ns.AURA_BARS[key] then return false end
    if ns.BAR_KIND[key] ~= "buff" then return true end
    if ns.BarData(key).onlyMissing then return false end
    local index = IndexOf(key, name)
    if not index then return false end
    local first, last = Group(key, index)
    for i = first, last do
        if self:OnlyWhenMissing(key, ns.BarData(key).spells[i]) then return false end
    end
    return true
end

-- Glow while active: a buff on a Buffs bar (Buffs 2 too) whose icon glows
-- while it's up, like a proc, so it's hard to miss. The glow sits inside the
-- game's own icon for it, so it shows with that icon, in a fight too
-- (Buffs.lua F:Actives); a change shows once out of a fight.
function B:SetGlowActive(key, name, on)
    if ns.BAR_KIND[key] ~= "buff" or not IndexOf(key, name) then return false end
    ns.GlowActive(key)[name] = on and true or nil
    self:Changed()
    return true
end

function B:GlowsActive(key, name)
    return ns.BAR_KIND[key] == "buff" and ns.GlowActive(key)[name] == true
end

-- Others only: a Main hand or Off hand enchant on a Buffs bar that isn't lit
-- by an enchant with an entry of its own on that bar (a player's report: on
-- Forever a Spellstone and an oil sit on one weapon, and the stone hid the
-- missing oil). False for anything but a hand entry on a Buffs bar.
function B:SetHandOthers(key, name, on)
    local entry = ns.Spells:Find(name)
    if ns.BAR_KIND[key] ~= "buff" or not IndexOf(key, name) or not (entry and entry.hand) then return false end
    ns.HandOthers(key)[name] = on and true or nil
    self:Changed()
    return true
end

function B:HandOthers(key, name)
    return ns.BAR_KIND[key] == "buff" and ns.HandOthers(key)[name] == true
end

-- Dim until Warn at (a player's idea: Moonfire's icon ticking down for all
-- 12 seconds when only its end matters): an entry on a Buffs or Debuffs bar
-- whose icon stays dark while it's up, its countdown and sweep hidden, until
-- its Warn at time is left; then it lights up as usual, its countdown red.
-- Missing, it shows greyed as before. The addon can't read an aura's time in
-- a fight, so the game draws it: the edge's slot covers the icon with its
-- own art darkened, from the same rule as the edge (Buffs.lua F:Warns). Not
-- hidden outright: the greyed spot under it would then look missing. The
-- icons change once out of a fight. False for an entry not on that bar.
function B:SetDimUntilWarn(key, name, on)
    if not ns.AURA_BARS[key] or not IndexOf(key, name) then return false end
    ns.DimUntilWarn(key)[name] = on and true or nil
    self:Changed()
    return true
end

function B:DimsUntilWarn(key, name)
    return ns.AURA_BARS[key] ~= nil and ns.DimUntilWarn(key)[name] == true
end

-- Whether its icon has a Warn at time: its own or one joined to it's (the
-- icon warns at the first of yours with one, Buffs.lua F:Layout).
function B:IconWarns(key, name)
    local index = ns.AURA_BARS[key] and IndexOf(key, name)
    if not index then return false end
    local first, last = Group(key, index)
    local warns, spells = ns.WarnAt(key), ns.BarData(key).spells
    for i = first, last do
        if warns[spells[i]] then return true end
    end
    return false
end

-- Whether it can show: as Warn at, only with an icon while it's up; with
-- missing ones greyed (only a spot of its own has the edge's slot); not on a
-- weapon enchant's spot (the addon's own, not the game's); and with a Warn
-- at time to light up from.
function B:DimUsable(key, name)
    if not ns.AURA_BARS[key] or not self:WarnUsable(key, name) then return false end
    if ns.BAR_KIND[key] == "buff" and not self:ActiveUsable(key, name) then return false end
    return ns.BuffBar:Fixed(ns.BarData(key)) and self:IconWarns(key, name)
end

-- Glow size: how big those glows are on every Buffs bar, a percent of their
-- usual size (the profile's, not a spell's). The glows lit now change at
-- once, or once a fight ends (Buffs.lua F:Actives).
function B:SetGlowActiveSize(percent)
    ns.SetGlowActiveSize(percent)
    for _, bar in pairs(bars) do
        if bar.holders then ns.BuffBar:Actives(bar) end
    end
end

-- Whether it can show: as Warn at, only with an icon while the buff is up
-- (not with Only show missing, nor Only when missing), and not on an icon of
-- weapon enchants alone, whose spot is the addon's own, not the game's.
-- Judged as Buffs.lua F:Layout does, by your own in the icon; with none of
-- yours in it (another character's), by them all.
function B:ActiveUsable(key, name)
    if ns.BAR_KIND[key] ~= "buff" or not self:WarnUsable(key, name) then return false end
    local data = ns.BarData(key)
    local first, last = Group(key, IndexOf(key, name))
    local yours, all = nil, false
    for i = first, last do
        local spell = data.spells[i]
        local found = ns.Spells:Find(spell)
        local buff = not (found and (found.hand or ns.WEAPON_ENCHANTS[found.name]))
        all = all or buff
        if found and found.ids and ns.Spells:ForMe(spell, key) then yours = yours or buff end
    end
    if yours == nil then return all end
    return yours
end

-- Settings per spell (a player's idea: a font and size per icon): an
-- entry's own countdown font and size (field "font" or "size"; nil for the
-- Look page's again), set in the panel its tray icon opens on a bar's page.
-- Your bars' icons change at once, in a fight too; the Buffs and Debuffs
-- bars' and the buff and debuff times over your icons (the game's aura
-- containers' icons) once out of a fight; Blizzard's icons for its spell
-- at once (a cosmetic setter). True when it changed.
function B:SetSpellLook(name, field, value)
    if not ns.SetSpellLook(name, field, value) then return false end
    self:ApplySpellLooks()
    return true
end

-- Both back to the Look page's (the panel's Defaults). True when it changed.
function B:ClearSpellLook(name)
    local font = ns.SetSpellLook(name, "font", nil)
    local size = ns.SetSpellLook(name, "size", nil)
    if not (font or size) then return false end
    self:ApplySpellLooks()
    return true
end

-- Whether an entry on a Cooldowns or Utility bar is a spell that uses a
-- reagent (Vanish, Blind): the game says, or it can be cast a number of times.
function B:UsesReagent(key, name)
    local kind, entry = ns.BAR_KIND[key], ns.Spells:Find(name)
    if (kind ~= "cd" and kind ~= "util") or not entry or not entry.spellID or ITEM_KINDS[entry.kind] then return false end
    local says = C_Spell.IsConsumableSpell
    if says then
        local ok, consumable = pcall(says, entry.spellID)
        if ok and Open(consumable) and consumable == true then return true end
    end
    local count = C_Spell.GetSpellCastCount
    if not count then return false end
    local ok, casts = pcall(count, entry.spellID)
    return ok and Open(casts) and type(casts) == "number" and casts > 0
end

-- Show reagent count for an entry: true when it changed.
function B:SetShowsReagents(name, on)
    return self:SetSpellLook(name, "reagents", on and true or nil)
end

function B:ShowsReagents(name)
    local look = ns.SpellLook(name)
    return look ~= nil and look.reagents == true
end

-- Every bar made laid out again with the looks as they are now (each
-- slider step sends one, so nothing is read again), and Blizzard's icons.
function B:ApplySpellLooks()
    if self.started then
        for _, key in ipairs(ns.BAR_KEYS) do
            if bars[key] then Layout(bars[key]) end
        end
        self:UpdateShown()
        self:RefreshAll()
    end
    if ns.Skin and ns.Skin.started then ns.Skin:ApplySpellLooks() end
end

-- An icon's own size on a bar (settings per spell; a player's idea: more
-- control over each icon's size): a percent of the bar's icon size, or nil
-- for the bar's again, set in the panel its tray icon opens. Your Cooldowns
-- and Utility icons change at once, in a fight too (the addon's own frames);
-- a Buffs or Debuffs bar's fixed spots once out of a fight. A packed one's
-- icons are the game's, all one size: kept, but used once its spots are
-- fixed (B:OwnSizeUsable). True when it changed.
function B:SetOwnSize(key, name, percent)
    if not ns.SetOwnSize(key, name, percent) then return false end
    if self.started and bars[key] then
        Layout(bars[key])
        self:UpdateShown()
        self:RefreshAll()
        if ns.Layout then ns.Layout:Stack() end
    end
    return true
end

-- Whether a bar's icons can each have a size of their own now: always on
-- the Cooldowns and Utility bars, and on a Buffs or Debuffs bar while its
-- spots are fixed (missing ones greyed, or Only show missing).
function B:OwnSizeUsable(key)
    return not ns.AURA_BARS[key] or not ns.BuffBar:Packed(ns.BarData(key))
end

-- Extra bars (Core.lua): a kind's second bar added to your profile and made,
-- empty: true, its key and what happened; or false and why not. Out of a
-- fight only.
function B:AddBar(kind)
    local ok, key = ns.AddBar(kind)
    if not ok then return false, key end
    self:Changed()
    return true, key, ns.BAR_NAMES[key] .. " added. Tick spells for it in the list below."
end

-- An extra bar taken out of your profile, with its spells: its frame laid
-- out empty and gone (Rebuild). True and what happened, or false and why not.
function B:RemoveBar(key)
    local ok, why = ns.RemoveBar(key)
    if not ok then return false, why end
    if self.moving == key then self.moving = "cd" end
    self:Changed()
    return true, ns.BAR_NAMES[key] .. " removed, with its spells."
end

-- How long a debuff lasts, each length its ranks have (seconds; Buffs.lua's
-- ns.DEBUFF_LASTS), or nil when not known.
local function Lasts(name)
    if type(name) ~= "string" or type(ns.DEBUFF_LASTS) ~= "table" then return nil end
    return ns.Spells:ByName(ns.DEBUFF_LASTS, name:match("^[^@#]+"))
end

-- How an icon counts ticks, given its debuffs of yours (names) and which
-- are ticked to count (counts): the pace, and, when others share the icon at
-- another pace or none (a player's case: Bane of Doom beside Agony), which
-- lengths it shows on, as a list of { seconds, shown } by length. The game
-- shows whichever debuff is up and the addon can't tell which in a fight,
-- but the count's colour can follow how long the aura lasts (Agony 24 s,
-- Doom 60 s), so the others' counts go see-through (Buffs.lua Paint). No
-- pace when it can't count, with the debuff in the way: none counted, the
-- counted at different paces, or another as long as a counted one, of a
-- length not known, or the game without colour curves.
function B:IconTicks(names, counts)
    local pace, counted
    for _, name in ipairs(names) do
        local own = counts[name] and self:TickPace(name)
        if own then
            -- Two counted at different paces: each is in the other's way.
            if pace and own ~= pace then return nil, nil, name, counted end
            pace, counted = own, counted or name
        end
    end
    if not pace then return nil end
    local others = {}
    for _, name in ipairs(names) do
        if self:TickPace(name) ~= pace then others[#others + 1] = name end
    end
    if #others == 0 then return pace end
    -- Only where the game took the counts' colour curves (Buffs.lua TickCount).
    if not (ns.BuffBar and ns.BuffBar.curves) then return nil, nil, others[1] end
    local shown, length, owner = {}, {}, {}
    for _, name in ipairs(names) do
        local lasts = Lasts(name)
        local on = self:TickPace(name) == pace
        if not lasts then return nil, nil, on and others[1] or name end
        for _, seconds in ipairs(lasts) do
            -- As long as one on the other side: the one in the way is the other.
            if length[seconds] ~= nil and length[seconds] ~= on then return nil, nil, on and owner[seconds] or name end
            if length[seconds] == nil then
                length[seconds], owner[seconds] = on, name
                shown[#shown + 1] = seconds
            end
        end
    end
    table.sort(shown)
    local shows = {}
    for i, seconds in ipairs(shown) do shows[i] = { seconds, length[seconds] } end
    return pace, shows
end

-- Another of yours in a debuff's icon that keeps it from counting its
-- ticks, were it ticked (B:IconTicks), or nil.
function B:TickClash(key, name)
    local index = IndexOf(key, name)
    if not (index and ns.AURA_BARS[key]) then return nil end
    local spells, names, counts = ns.BarData(key).spells, {}, {}
    local first, last = Group(key, index)
    for i = first, last do
        local found = ns.Spells:Find(spells[i])
        if found and found.ids and ns.Spells:ForMe(spells[i], key) then names[#names + 1] = spells[i] end
    end
    for k, v in pairs(ns.CountTicks(key)) do counts[k] = v end
    counts[name] = true
    local pace, _, blocker, other = self:IconTicks(names, counts)
    if pace then return nil end
    -- Counted at another pace than one already counted: that one's in the way.
    if blocker == name then blocker = other end
    if blocker == name then return nil end
    return blocker
end

-- Whether the entry at index is the one its icon shows while none is up:
-- picked, and the first picked in its icon (two can meet there after a move).
function B:Picked(key, index)
    local spells = ns.BarData(key).spells
    if not (ns.AURA_BARS[key] and spells[index]) then return false end
    local picks = ns.MissingPicks(key)
    if picks[spells[index]] ~= true then return false end
    local first = Group(key, index)
    for i = first, index - 1 do
        if picks[spells[i]] == true then return false end
    end
    return true
end

-- Whether two icons can trade places (B:Trade): true, or false and why not.
-- Changes nothing, so the Layout page can say so while one is held over the
-- other. On one bar any two icons can. Between two bars each entry goes in
-- the other's place on the other's bar: only what that bar can show (and
-- shows for you), not onto a bar it's already on (or both cooldown bars),
-- and a joined group stays on its own bar.
function B:CanTrade(from, name, to, other)
    local a, b = IndexOf(from, name), IndexOf(to, other)
    if not (a and b) or from == to and a == b then return false end
    if from == to then return (Group(from, a)) ~= (Group(from, b)) end
    local moves = { { name, to, from }, { other, from, to } } -- entry, the bar it goes to, the bar it leaves
    -- (Your pet's ability onto a cooldown bar: as it's added there, Movable.)
    for _, move in ipairs(moves) do
        local fits, why = Movable(move[1], move[2])
        if not fits then return false, why end
    end
    for _, spot in ipairs({ { from, a }, { to, b } }) do
        local why = Tied(spot[1], spot[2])
        if why then return false, why end
    end
    for _, move in ipairs(moves) do
        local entry, onto, leaving = move[1], move[2], move[3]
        local already = IndexOf(onto, entry) and onto
        if not already and not ns.AURA_BARS[onto] then
            local current = self:Find(entry)
            if current ~= leaving then already = current end
        end
        if already then return false, Named(entry) .. " is already on " .. ns.BAR_NAMES[already] .. "." end
    end
    return true
end

-- Two icons trade places, as dragged one onto the other on the Layout page
-- (B:CanTrade says which can). On one bar a joined group moves whole; between
-- two bars each entry takes the other's place. True and what happened, or
-- false and why not.
function B:Trade(from, name, to, other)
    local can, why = self:CanTrade(from, name, to, other)
    if not can then return false, why end
    local a, b = IndexOf(from, name), IndexOf(to, other)
    if from == to then
        local a1, a2 = Group(from, a)
        local b1, b2 = Group(from, b)
        if b1 < a1 then a1, a2, b1, b2 = b1, b2, a1, a2 end
        -- The first group, the entries between, the second: swapped round.
        -- Each group's first entry leads it again, so the joins stay as they are.
        local spells, order = ns.BarData(from).spells, {}
        for _, run in ipairs({ { 1, a1 - 1 }, { b1, b2 }, { a2 + 1, b1 - 1 }, { a1, a2 }, { b2 + 1, #spells } }) do
            for i = run[1], run[2] do order[#order + 1] = spells[i] end
        end
        for i, entry in ipairs(order) do spells[i] = entry end
        self:Changed()
        return true, Swapped(name, other)
    end
    -- Your pet's ability going onto a cooldown bar takes its pet's own
    -- spell with it (Movable), as a move there does.
    local _, keeps = Movable(name, to)
    local _, gives = Movable(other, from)
    ns.BarData(from).spells[a], ns.BarData(to).spells[b] = other, name
    if keeps then ns.AddCustom(name, keeps) end
    if gives then ns.AddCustom(other, gives) end
    -- Neither is joined to anything, and nor is either in its new place.
    -- Between the two cooldown bars each leaves the other's lists in the
    -- forms its new place shows in (B:Assign).
    for _, key in ipairs({ from, to }) do
        if ns.AURA_BARS[key] then
            local joins = ns.Joins(key)
            joins[name], joins[other] = nil, nil
        end
    end
    if not (ns.AURA_BARS[from] or ns.AURA_BARS[to]) then
        Apart(to, name)
        Apart(from, other)
    end
    self:Changed()
    return true, Swapped(name, other) .. PetNote(name, to, true) .. PetNote(other, from, true)
end

-- An option only changes how one bar looks, so only that bar is redrawn;
-- the size slider sends a change for every step it's dragged.
function B:SetOption(key, field, value)
    -- Swap with my form is the profile's, beside the lists it swaps between.
    if field == "swapForm" then ns.SetSwaps(key, value) else ns.BarData(key)[field] = value end
    -- Swap with my form ticked or unticked: the lists that show beside each
    -- other from now on keep a spell off both cooldown bars. Ticked, this
    -- bar's form lists kept from before give way to the other bar's;
    -- unticked, its normal list (now in every form) keeps what's on it. Any
    -- change there lays every bar out again.
    local apart = field == "swapForm" and ns.KeepApart(value and (key == "cd" and "util" or "cd") or key)
    if not self.started then return end
    if apart then return self:Rebuild() end
    -- Swap with my form ticked: the form you're in now, read before the bar
    -- shows its list.
    ns.FollowForm()
    -- None are made while off: that waits for them to be turned on.
    if bars[key] or self:Enabled() then Layout(bars[key] or NewBar(key)) end
    -- Only show missing ticked or unticked: your buffs changing are heard or
    -- not; and the same for your form, with Swap with my form.
    HearAuras()
    HearForms()
    self:UpdateShown()
    self:RefreshAll()
    -- A bar in a layout may now be taller or shorter.
    if ns.Layout then ns.Layout:Stack() end
end

-- The size for all your bars together (the Layout page's All bars), as a
-- share of each bar's own: every bar is laid out again, as when one bar's
-- size changes, and a layout stacked again. Sent for every step the slider
-- is dragged. In a fight the Buffs and Debuffs bars catch up once it's over.
function B:SetScale(percent)
    local limits = ns.BAR_SCALE
    ns.Set("barScale", math.max(limits[1], math.min(limits[2], math.floor(percent + .5))))
    if not self.started then return end
    if self:Enabled() or next(bars) then
        for _, key in ipairs(ns.BAR_KEYS) do Layout(bars[key] or NewBar(key)) end
    end
    self:UpdateShown()
    self:RefreshAll()
    if ns.Layout then ns.Layout:Stack() end
end

-- Puts a bar's point at a spot, from the middle of the screen, for a layout.
-- The Buffs and Debuffs bars move once a fight is over.
function B:PlaceAt(key, point, x, y)
    local data = ns.BarData(key)
    data.x, data.y, data.point = Round(x), Round(y), point
    local bar = bars[key]
    if not bar then return end
    if Locked(bar) then
        bar.pendingLayout = true
        return
    end
    Place(bar)
end

-- Lays one bar out again after a layout changes which way it grows.
function B:Relayout(key)
    if not (self.started and (bars[key] or self:Enabled())) then return end
    Layout(bars[key] or NewBar(key))
end

-- Swap with my form: each Cooldowns or Utility bar whose list changed (your
-- form, or the one its page sets up) laid out again with the new one, at
-- once and in a fight too: the addon's own icons only, as for an item
-- running out (Relay). Its spot, size and every other setting stay. True
-- when any bar was.
function B:FormChanged()
    if not self.started then return false end
    local changed = false
    for _, key in ipairs(ns.BAR_KEYS) do
        local bar = bars[key]
        if bar and bar.kind == "cooldown" and ns.ActiveList(key) ~= bar.list then
            Layout(bar)
            changed = true
        end
    end
    if not changed then return false end
    self:UpdateShown()
    self:RefreshAll()
    if ns.Layout then ns.Layout:Stack() end
    return true
end

-- The entries on a bar that show there for no one (Spells.lua S:Leftover:
-- a buff's ID ticked on the Cooldowns bar before that was turned away).
function B:Leftovers(key)
    local names = {}
    for _, name in ipairs(ns.BarData(key).spells) do
        if ns.Spells:Leftover(name, key) then names[#names + 1] = name end
    end
    return names
end

-- The entries on a cooldown bar that are your pet's abilities, hidden till
-- a pet that knows them is out (Spells.lua S:PetAway): its page lists them,
-- and Clear takes them.
function B:Waiting(key)
    local names = {}
    for _, name in ipairs(ns.BarData(key).spells) do
        if ns.Spells:PetAway(name, key) then names[#names + 1] = name end
    end
    return names
end

-- Empties a bar.
-- Clears what you see on a bar (its page lists your pet's abilities hidden
-- till their pet is out too), and what shows there for no one; another
-- class's entries in a shared profile stay for the characters that use them.
function B:Clear(key)
    local places = {}
    for i, name in ipairs(ns.BarData(key).spells) do
        if ns.Spells:ForMe(name, key) or ns.Spells:Leftover(name, key) or ns.Spells:PetAway(name, key) then
            places[#places + 1] = i
        end
    end
    for n = #places, 1, -1 do Forget(key, Take(key, places[n])) end
    self:Changed()
end

function B:ResetPositions()
    -- Back above the action bar, so no longer stacked in a layout.
    if ns.Layout then ns.Layout:TurnOff() end
    for _, key in ipairs(ns.BAR_KEYS) do
        local data = ns.BarData(key)
        data.x, data.y, data.point = nil, nil, nil
    end
    self:Changed()
end

-- Moving a bar by numbers (the Layout page, a player's idea): where it is,
-- as the point it's held by from the middle of the screen, typed in or
-- nudged a pixel at a time. Your own bars only, out of a fight; like a drag,
-- it takes the bar out of the layout it was stacked in. Blizzard's Cooldown
-- Manager is moved in Edit Mode. B.moving: the bar the page moves, the one
-- last dragged on screen or picked there.
B.moving = "cd"

-- A bar's place now, nil before it has one. One kept for another point (a
-- layout's, or from before rows) is worked out for this one, as Place
-- would, without moving anything (in a fight too).
function B:BarPlace(key)
    local bar = bars[key]
    if not (bar and bar.data) then return nil end
    local data = bar.data
    if not (data.x and data.y) then return Where(bar) end
    local point, from = Point(data), data.point or "CENTER"
    if from == point then return data.x, data.y end
    local width, height = bar:GetWidth() or 0, bar:GetHeight() or 0
    local fromX, fromY = Offset(from, width, height)
    local toX, toY = Offset(point, width, height)
    return Round(data.x - fromX + toX), Round(data.y - fromY + toY)
end

-- Puts a bar at x, y (the whole bar kept on the screen, as a drag keeps it,
-- so the numbers say where it really is). False and why when it can't.
function B:MoveBar(key, x, y)
    if InCombatLockdown() then return false, "Finish combat first, then move your bars." end
    local bar = bars[key]
    if not (bar and self:Enabled()) then return false, "Turn your bars on first." end
    if type(x) ~= "number" or type(y) ~= "number" or x ~= x or y ~= y then return false, "Type a number." end
    if bar.dragging then return false, "Let go of the bar first." end
    local wide, tall = UIParent:GetWidth() or 0, UIParent:GetHeight() or 0
    if wide > 0 and tall > 0 then
        -- x, y is the point the bar is held by (a corner, or an edge's
        -- middle): the bar's middle is kept far enough in for all of it.
        local width, height = bar:GetWidth() or 0, bar:GetHeight() or 0
        local offsetX, offsetY = Offset(Point(bar.data), width, height)
        local roomX, roomY = math.max(0, (wide - width) / 2), math.max(0, (tall - height) / 2)
        x = math.max(-roomX, math.min(roomX, x - offsetX)) + offsetX
        y = math.max(-roomY, math.min(roomY, y - offsetY)) + offsetY
    end
    local data = bar.data
    data.x, data.y, data.point = Round(x), Round(y), (Point(data))
    if ns.Layout then ns.Layout:Moved() end
    Place(bar)
    return true
end

-- Moves a bar by dx, dy pixels, from its place to the nearest whole pixel.
function B:NudgeBar(key, dx, dy)
    local x, y = self:BarPlace(key)
    if not x then return false, self:Enabled() and "Show the bar first: it has no place yet." or "Turn your bars on first." end
    return self:MoveBar(key, math.floor(x + .5) + dx, math.floor(y + .5) + dy)
end

-- Your spellbook, gear and bags changing ------------------------------------------------
-- Each change only notes that the list of your spells and items wants
-- reading again. The bars (when on) and an open /ccm window are redrawn once
-- on the next frame, however many changes came at once (several
-- SPELLS_CHANGED as you shift form, a gear set's every slot, a loading
-- screen). With your bars off and /ccm closed, that's all.
local rebuildWanted = false
local function RebuildNow()
    if not rebuildWanted then return end
    rebuildWanted = false
    Rebuild()
    if ns.window and ns.window:IsShown() then ns.window:Refresh() end
end
local function RebuildSoon()
    rebuildWanted = true
    C_Timer.After(0, RebuildNow)
end

-- With /ccm open its spell list shows what's in your bags: redrawn a moment
-- after the last bag change (looting, a potion, ammo on a dummy), not on
-- every one.
local BAG_WAIT = .2
local bagChanges = 0
local function BagsChanged()
    ns.Spells:Stale()
    bagChanges = bagChanges + 1
    local mine = bagChanges
    C_Timer.After(BAG_WAIT, function()
        if mine ~= bagChanges then return end
        Rebuild()
        if ns.window and ns.window:IsShown() then ns.window:Refresh() end
    end)
end

local function Listing(_, event)
    local open = ns.window ~= nil and ns.window:IsShown()
    if event == "BAG_UPDATE_DELAYED" then
        if open then BagsChanged() end
    else
        ns.Spells:Stale()
        if open or B:Enabled() then RebuildSoon() end
    end
end

-- The driver: everything your bars follow while they're on. Made the first
-- time they're on; while they're off it hears nothing.
local driver
local listening = false
local DRIVER_EVENTS = { "SPELL_UPDATE_COOLDOWN", "SPELL_UPDATE_USABLE", "PLAYER_TARGET_CHANGED", "PLAYER_REGEN_DISABLED",
    "PLAYER_REGEN_ENABLED", "BAG_UPDATE_COOLDOWN", "BAG_UPDATE_DELAYED", "PLAYER_LEVEL_UP", "PLAYER_LEVEL_CHANGED",
    "GET_ITEM_INFO_RECEIVED", "SPELL_ACTIVATION_OVERLAY_GLOW_SHOW", "SPELL_ACTIVATION_OVERLAY_GLOW_HIDE" }
-- Your buffs changed (UNIT_AURA), out of combat with Only show missing on:
-- read once on the next frame, however many came at once.
local checking = false
-- Heard with UNIT_AURA: the game's restrictions changing, or an encounter
-- ending, after which buffs it kept secret may be read (each event the game
-- lacks is left out).
local LIFTED = { "ADDON_RESTRICTION_STATE_CHANGED", "ENCOUNTER_END" }
-- Reads again since the game last answered in full, or since a fight ended
-- or its restrictions changed (Again), and whether one is on its way.
local tries, waiting = 0, false
-- Your form, stance or stealth changing, heard only while a bar swaps with
-- your form (each event the game lacks is left out): the bars follow on the
-- next frame, however many came at once.
local FORM_EVENTS = { UPDATE_SHAPESHIFT_FORM = true, UPDATE_SHAPESHIFT_FORMS = true, UPDATE_STEALTH = true }
local shifting = false

-- Whether a Buffs bar's last read (Buffs, or Buffs 2: Extra bars) left some
-- of your buffs unanswered (Again, below).
local function Unread()
    for _, key in ipairs(ns.BAR_KEYS) do
        local bar = ns.BAR_KIND[key] == "buff" and bars[key]
        if bar and (bar.unread or bar.lowUnread) then return true end
    end
    return false
end

local function OnEvent(_, event, arg)
    if event == "UNIT_AURA" then
        checking = true
    elseif event == "UNIT_INVENTORY_CHANGED" or event == "WEAPON_ENCHANT_CHANGED" then
        -- A weapon enchant on or off, read on the next frame however many came.
        B.enchanting = true
    elseif event == "UNIT_FLAGS" then
        -- Your target died (or came back): a Debuffs bar's Glow when
        -- missing goes out on a corpse. FECM's own frames only.
        for _, key in ipairs(ns.BAR_KEYS) do
            if ns.BAR_KIND[key] == "debuff" then ns.BuffBar:TargetGlow(bars[key]) end
        end
    elseif FORM_EVENTS[event] then
        shifting = true
    elseif event == "ADDON_RESTRICTION_STATE_CHANGED" or event == "ENCOUNTER_END" then
        -- Buffs the game wouldn't answer for may be readable now: read on
        -- the next frame (not as the event comes, when the game may not
        -- have caught up yet), and again a few times if still not.
        if Unread() then tries, checking = 0, true end
    elseif event == "PLAYER_REGEN_DISABLED" then
        inCombat = true
        -- Nothing on a Buffs bar changes in a fight: your buffs aren't heard.
        HearAuras()
        for _, key in ipairs(ns.BAR_KEYS) do
            -- A buff's low-time glow (Warn at) goes out: in a fight its time
            -- is secret, and the game's red numbers and edge take over.
            if ns.BAR_KIND[key] == "buff" then ns.BuffBar:LowTime(bars[key], true) end
            -- A Buffs or Debuffs bar still being dragged is let go where it
            -- is, just before the fight locks it in place.
            if ns.AURA_BARS[key] and bars[key] then Drop(bars[key]) end
        end
        -- Another form's list picked on the bar's page (Swap with my form)
        -- lets go: in a fight your bars follow your form.
        if ns.EditingForm() ~= nil then
            ns.SetEditingForm(nil)
            B:FormChanged()
            if ns.window and ns.window:IsShown() then ns.window:Refresh() end
        end
        B:UpdateShown()
    elseif event == "PLAYER_REGEN_ENABLED" then
        inCombat = false
        -- Your trinkets, read now if a list was read in the fight (they
        -- aren't then): a Buffs bar waiting for the fight's end lays out
        -- with them below.
        if ns.Spells:TrinketsHeld() then ns.Spells:Stale() end
        -- A weapon enchant the game wouldn't say about in the fight.
        B:EnchantsChanged()
        -- Anything the aura bars had to wait for during the fight, and the
        -- buffs that came or went in it (Only show missing: read again a
        -- few times if the game doesn't answer yet).
        tries = 0
        for _, key in ipairs(ns.ALL_BAR_KEYS) do
            local bar = ns.AURA_BARS[key] and bars[key]
            if bar and bar.pendingLayout then
                Layout(bar)
                -- (An extra bar you don't have now, emptied at last.)
                if not ns.HasBar(key) then bar.retired = not bar.pendingLayout or nil end
            elseif bar then
                Missing(bar)
                if bar.pending then ns.BuffBar:Apply(bar) end
            end
            if bar and bar.pendingDecor then GroupDecor(bar) end
            if bar then bar.pendingShown = nil end
        end
        -- Your buffs' time left read again (Warn at: the low-time glow),
        -- and again a moment later if the game doesn't answer yet.
        for _, key in ipairs(ns.BAR_KEYS) do
            if ns.BAR_KIND[key] == "buff" and bars[key] then
                ns.BuffBar:LowTime(bars[key])
                Again(bars[key])
            end
        end
        -- And the buff and debuff times on the cooldown icons. Then Icon
        -- details changed in the fight, on the aura containers' icons.
        for _, key in ipairs(ns.BAR_KEYS) do
            if bars[key] then ns.IconAuras:CombatEnded(bars[key]) end
            if bars[key] and bars[key].pendingDetails then AuraDetails(bars[key]) end
        end
        -- Items used up or picked up in the fight come off or go on now,
        -- and families move on to the best one you carry.
        follow = true
        local recounted = Recount()
        if recounted then Relay() end
        B:UpdateShown()
        if recounted then
            B:RefreshAll()
            if ns.Layout then ns.Layout:Stack() end
        else
            dirty = true
        end
        -- Your form read again on the next frame (Swap with my form): one
        -- the game kept secret in the fight shows now.
        shifting = true
        -- Turned off during the fight: done now, so the driver rests. Your
        -- buffs changing are heard again (Only show missing).
        Listen()
    elseif event == "BAG_UPDATE_DELAYED" then
        follow = true
        if ns.window and ns.window:IsShown() then
            -- Counts now; the bars and the window are laid out again a
            -- moment after the last bag change (BagsChanged).
            dirty = true
        elseif Recount() then
            -- Out of an item, or carrying one again: the bars close up
            -- or make room for it.
            Relay()
            B:UpdateShown()
            B:RefreshAll()
            if ns.Layout then ns.Layout:Stack() end
        else
            B:RefreshAll()
        end
    elseif event == "PLAYER_LEVEL_UP" or event == "PLAYER_LEVEL_CHANGED" or event == "GET_ITEM_INFO_RECEIVED" then
        -- A potion you can use now, or the name of one the game has just
        -- loaded. Your level may still read the old one as PLAYER_LEVEL_UP
        -- fires, so PLAYER_LEVEL_CHANGED (with the new one) looks again.
        if event ~= "GET_ITEM_INFO_RECEIVED" or ns.Spells:Family(arg) then follow, dirty = true, true end
        -- A trinket worn whose use the game hadn't loaded: its buff read now
        -- (a Buffs bar lays out again; in a fight, once it ends).
        if event == "GET_ITEM_INFO_RECEIVED" and ns.Spells:TrinketWaiting(arg) then
            ns.Spells:Stale()
            RebuildSoon()
        end
    elseif event == "SPELL_UPDATE_COOLDOWN" or event == "BAG_UPDATE_COOLDOWN" then
        -- A cooldown started (or the global cooldown, with every cast).
        cooling = true
    else
        if event == "PLAYER_TARGET_CHANGED" then
            -- Each Debuffs bar, and the buff and debuff times on each
            -- cooldown bar's icons.
            for _, key in ipairs(ns.BAR_KEYS) do
                local bar = bars[key]
                if ns.BAR_KIND[key] == "debuff" then
                    ns.BuffBar:UpdateTarget(bar)
                elseif not ns.AURA_BARS[key] then
                    ns.IconAuras:UpdateTarget(bar)
                end
            end
            B:UpdateShown()
        end
        -- Usable, in or out of range, lit or put out by the game, or a new
        -- target to be in range of: colours and glows.
        tinting = true
    end
end

-- Refreshes asked for since the last frame, done here once: in full, or
-- just the part that changed. Nothing is asked of the game while nothing
-- changes; range has its own event (WatchRange).
local function Tick()
    if B.enchanting then
        B.enchanting = false
        B:EnchantsChanged()
    end
    if checking then
        checking = false
        for _, key in ipairs(ns.BAR_KEYS) do
            local bar = ns.BAR_KIND[key] == "buff" and bars[key]
            if bar then
                Missing(bar)
                -- And how long your warned buffs have left (Warn at: the low-time glow).
                ns.BuffBar:LowTime(bar, inCombat)
                Again(bar)
            end
        end
    end
    -- Your form changed: read once, and each bar swapping with it shows that
    -- form's list (B:FormChanged), when it's another; so does /ccm, open.
    if shifting then
        shifting = false
        if ns.FollowForm() and B:FormChanged() and ns.window and ns.window:IsShown() then ns.window:Refresh() end
    end
    if not (dirty or cooling or tinting) then return end
    local part
    if not dirty and not (cooling and tinting) then part = cooling and "cooldown" or "state" end
    dirty, cooling, tinting = false, false, false
    if B.started and B:Enabled() then Each(part) end
end

-- Your buffs coming and going (UNIT_AURA for you) are heard only while the
-- Buffs bar shows only missing ones (all, or those ticked Only when
-- missing), or a buff in a spot of its own warns as it runs low (Warn at),
-- your bars are on and you're out of a fight. In one the bar stays as it
-- is (your buffs are secret then), so nothing is heard; they're read again
-- as it ends.
local hearing = false
HearAuras = function()
    -- (Any Buffs bar: Buffs 2 too, once added.)
    local any = false
    for _, key in ipairs(ns.BAR_KEYS) do
        if ns.BAR_KIND[key] == "buff" then
            local data = ns.BarData(key)
            any = any or ns.BuffBar:Watches(key, data) or ns.BuffBar:LowWatch(data, key) or ns.BuffBar:HasEnchants(bars[key])
        end
    end
    local want = listening and not inCombat and any or false
    if want == hearing then return end
    hearing = want
    if want then
        driver:RegisterUnitEvent("UNIT_AURA", "player")
        for _, event in ipairs(LIFTED) do pcall(driver.RegisterEvent, driver, event) end
    else
        driver:UnregisterEvent("UNIT_AURA")
        for _, event in ipairs(LIFTED) do pcall(driver.UnregisterEvent, driver, event) end
        checking = false
    end
end
-- (For B:EnchantClock, above, as a bar first has a weapon enchant.)
function B:HearAuras()
    HearAuras()
end

-- Your form changing is heard only while your bars are on and a bar swaps
-- with your form: in a fight too, as that's when you change form most.
local forming = false
HearForms = function()
    local want = listening and ns.AnySwaps() or false
    if want == forming then return end
    forming = want
    for event in pairs(FORM_EVENTS) do
        if want then pcall(driver.RegisterEvent, driver, event) else pcall(driver.UnregisterEvent, driver, event) end
    end
    if not want then shifting = false end
end

-- The Buffs bar's last read (Missing, its layout, or the time left on warned
-- buffs: bar.lowUnread, Buffs.lua F:LowTime) left some of your buffs
-- unanswered: the game still keeps them secret as a fight ends, say, or out
-- of one in an encounter. Read again half a second later, four times at
-- most, and only while your buffs are heard (out of a fight, the setting
-- on); a read answered in full, a fight ending or the game's restrictions
-- changing start the count again. Never more than that: no polling.
local AGAIN, TRIES = .5, 4
-- (With Buffs 2 too, any Buffs bar unanswered counts, so one bar answered in
-- full never starts the count again while the other still isn't.)
Again = function()
    if not Unread() then
        tries = 0
        return
    end
    if waiting or tries >= TRIES then return end
    tries, waiting = tries + 1, true
    C_Timer.After(AGAIN, function()
        waiting = false
        if hearing and Unread() then checking = true end
    end)
end

-- The driver listens while your bars are on, made the first time they are.
-- Turned off in a fight, it still hears the fight end, when the Buffs and
-- Debuffs bars can hide.
local function Switch()
    local on = B:Enabled()
    if on == listening or not on and InCombatLockdown() then return end
    if on and not driver then
        driver = CreateFrame("Frame")
        driver:SetScript("OnEvent", OnEvent)
        B.driver = driver
    end
    if not driver then return end
    listening = on
    if on then
        inCombat = UnitAffectingCombat("player") and true or false
        for _, event in ipairs(DRIVER_EVENTS) do driver:RegisterEvent(event) end
        -- A client without range events still checks range on a new target
        -- and as spells become usable or not.
        pcall(driver.RegisterEvent, driver, "SPELL_RANGE_CHECK_UPDATE")
        -- Your target dying or coming back (the Debuffs bar's glow).
        pcall(driver.RegisterUnitEvent, driver, "UNIT_FLAGS", "target")
        -- A weapon enchant going on or off (each event the game lacks is left out).
        pcall(driver.RegisterUnitEvent, driver, "UNIT_INVENTORY_CHANGED", "player")
        pcall(driver.RegisterEvent, driver, "WEAPON_ENCHANT_CHANGED")
        driver:SetScript("OnUpdate", Tick)
    else
        driver:UnregisterAllEvents()
        driver:SetScript("OnUpdate", nil)
        hearing, checking, forming, shifting = false, false, false, false
    end
end

Listen = function()
    Switch()
    HearAuras()
    HearForms()
end

function B:Start()
    if self.started then return end
    self.started = true
    local watch = CreateFrame("Frame")
    for _, event in ipairs({ "PLAYER_ENTERING_WORLD", "SPELLS_CHANGED", "PLAYER_EQUIPMENT_CHANGED", "BAG_UPDATE_DELAYED" }) do
        watch:RegisterEvent(event)
    end
    -- Your pet summoned, dismissed, stabled, swapped or dead: a hunter's pet
    -- abilities and a warlock's demon's spells show only while the pet out
    -- knows them (Spells.lua PetSpells). Blizzard's pet frame and pet bar
    -- go by UNIT_PET too, and its spellbook redraws a pet's spells on
    -- SPELLS_CHANGED (above).
    watch:RegisterUnitEvent("UNIT_PET", "player")
    watch:SetScript("OnEvent", Listing)
    self.watch = watch
    -- Bars come back in full while Edit Mode is open.
    local editor = EditModeManagerFrame
    if editor and editor.HookScript then
        editor:HookScript("OnShow", function()
            editMode = true
            -- Items you carry none of show, to be placed, and a layout makes
            -- room; buffs on you with Only show missing show too.
            local any = next(absent) ~= nil
            if any then Relay() end
            MissingAll()
            B:UpdateShown()
            B:RefreshAll()
            if any and ns.Layout then ns.Layout:Stack() end
        end)
        -- The resource display may have moved: a layout follows it.
        editor:HookScript("OnHide", function()
            editMode = false
            if next(absent) then Relay() end
            MissingAll()
            B:UpdateShown()
            B:RefreshAll()
            if ns.Layout then ns.Layout:Stack() end
        end)
        editMode = editor:IsShown() and true or false
    end
    Rebuild()
end
