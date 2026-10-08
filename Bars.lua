-- The addon's own bars: rows of square frameless icons for the spells you
-- pick. Cooldowns are secret in combat, so each icon hands the game's
-- duration object straight to its sweep, greying and dim or hide when ready
-- without ever reading it; only the open "usable" and range checks are read
-- here.
-- The icons never take the mouse, so they can't get in the way in combat.
local _, ns = ...

local B = {}
ns.Bars = B

local Style = ns.Style
local DEFAULT_Y = { debuff = 278, buff = 234, cd = 190, util = 146 } -- just above the action bar
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
local DIM = .4 -- a ready icon's opacity on a bar that dims them
local READY_ALPHA = { show = 1, dim = DIM, hide = 0 }

local function Open(value)
    return not (issecretvalue and issecretvalue(value))
end

-- How a ready icon shows: "show", "dim" or "hide". Dimming and hiding wait
-- while the bars are being arranged (unlocked, or in Edit Mode), so every
-- icon on them can be seen in full.
local function WhenReady(data)
    if unlocked or editMode then return "show" end
    return data.whenReady
end

local function HidesReady(data)
    return WhenReady(data) == "hide"
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

-- Reads again which of the items on your cooldown bars you carry none of.
-- Anything the game won't say keeps what was known. True when any changed.
local function Recount()
    if InCombatLockdown() then return false end
    local now, changed = {}, false
    for _, key in ipairs(ns.BAR_KEYS) do
        if not ns.AURA_BARS[key] then
            for _, name in ipairs(ns.BarData(key).spells) do
                local have = ns.Spells:Carries(ns.Spells:Find(name))
                if have == nil then now[name] = absent[name] else now[name] = not have or nil end
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

local function NewEdge(top)
    local glow = CreateFrame("Frame", nil, top)
    glow:SetAllPoints()
    for _, side in ipairs(GLOW_SIDES) do
        local strip = glow:CreateTexture(nil, "BORDER")
        strip:SetColorTexture(1, .82, 0, 1)
        strip:SetPoint(side[1])
        strip:SetPoint(side[2])
        if side[3] then strip:SetHeight(GLOW) else strip:SetWidth(GLOW) end
    end
    glow:Hide()
    return glow
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

local function NewIcon(bar)
    local icon = CreateFrame("Frame", nil, bar)
    icon:EnableMouse(false)
    icon.texture = icon:CreateTexture(nil, "ARTWORK")
    icon.texture:SetAllPoints()
    Style:Zoom(icon.texture)
    icon.cooldown = CreateFrame("Cooldown", nil, icon, "CooldownFrameTemplate")
    icon.cooldown:SetAllPoints(icon.texture)
    icon.cooldown:SetSwipeTexture(Style.FLAT)
    icon.cooldown:SetSwipeColor(0, 0, 0, .7)
    icon.cooldown:SetDrawEdge(false)
    icon.cooldown:SetDrawBling(false)
    -- Events arrive when a cooldown starts, not when it ends; this catches the
    -- end, so the icon ungreys (or dims or hides when ready) on time.
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
    Style:ShowDecor(icon.decor, Style:DecorFor("icon"))
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
-- red (out of range). Only set when it changes.
local function Tint(icon, tint)
    if icon.tint == tint then return end
    icon.tint = tint
    icon.texture:SetVertexColor(tint[1], tint[2], tint[3])
end

-- The icon's opacity when it's a plain number, only set when it changes.
-- Dim or Hide when ready hands the game a secret answer instead (Fade), and
-- the next plain one is set again after it.
local function Alpha(icon, alpha)
    if icon.alpha == alpha then return end
    icon.alpha = alpha
    icon:SetAlpha(alpha)
end

local function Fade(icon, active, dim)
    icon.alpha = nil
    if dim then icon:SetAlphaFromBoolean(active, 1, DIM) else icon:SetAlphaFromBoolean(active) end
end

-- Trinkets and bag items. Their cooldowns come back as plain numbers; if the
-- game ever hides them in combat, the icon simply keeps its last state.
local function RefreshItem(icon, data, follows)
    if follows and icon.kind == "family" then Follow(icon) end
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
        Alpha(icon, active and 1 or READY_ALPHA[WhenReady(data)])
    end
    local count
    if icon.kind == "item" or icon.kind == "family" then
        count = C_Item.GetItemCount(icon.itemID, false, true)
        if Open(count) and type(count) == "number" then
            icon.count:SetText(count)
            if count == 0 then icon.texture:SetDesaturated(true) end
        end
    end
    local usable, noMana = C_Item.IsUsableItem(icon.itemID)
    local tint = TINT.ready
    if Open(usable) and usable == false then
        tint = Open(noMana) and noMana and TINT.mana or TINT.unusable
    end
    Tint(icon, tint)
    SetGlow(icon, false)
end

-- Your ammunition: how many you carry, greyed when you're out.
local function RefreshAmmo(icon)
    local texture = GetInventoryItemTexture("player", icon.slot)
    if texture then icon.texture:SetTexture(texture) end
    local count = GetInventoryItemID("player", icon.slot) and GetInventoryItemCount("player", icon.slot) or 0
    if Open(count) and type(count) == "number" then
        icon.count:SetText(count)
        icon.texture:SetDesaturated(count == 0)
    end
    icon.cooldown:Clear()
    Alpha(icon, 1)
    Tint(icon, TINT.ready)
    SetGlow(icon, false)
end

-- Whether an icon shows an item (or your ammunition) rather than a spell.
local ITEM_KINDS = { item = true, slot = true, family = true, ammo = true }

-- A spell's cooldown: on the sweep, grey while it cools down, and in full,
-- dimmed or hidden while it's ready. Redone as cooldowns start or end.
local function SpellCooldown(icon, data)
    local id = icon.spellID
    local duration = C_Spell.GetSpellCooldownDuration and C_Spell.GetSpellCooldownDuration(id, true)
    if duration then
        icon.cooldown:SetCooldownFromDurationObject(duration)
        -- Secret in combat: passed to the game as it is, never tested here.
        local active = duration:IsActive()
        icon.texture:SetDesaturated(active)
        -- In full while it cools down; dimmed or hidden while it's ready.
        local ready = WhenReady(data)
        if ready == "show" or not icon.SetAlphaFromBoolean then
            Alpha(icon, 1)
        else
            Fade(icon, active, ready == "dim")
        end
    else
        icon.cooldown:Clear()
        icon.texture:SetDesaturated(false)
        Alpha(icon, 1)
    end
end

-- A spell's colour and glow: whether it can be used, has the mana, reaches
-- your target, and is lit by the game. Redone as the game says one of these
-- changed (usable, in or out of range, a glow, a new target).
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
end

-- One icon: all of it, or just its cooldown ("cooldown") or its colour and
-- glow ("state"). Items and ammo are few, so read in full either way.
local function RefreshIcon(icon, data, hasTarget, follows, part)
    if icon.kind == "ammo" then return RefreshAmmo(icon) end
    if ITEM_KINDS[icon.kind] then return RefreshItem(icon, data, follows) end
    if part ~= "state" then SpellCooldown(icon, data) end
    if part ~= "cooldown" then SpellState(icon, hasTarget) end
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

-- Rows of up to perRow icons (or aura spots). Each row lines up by the bar's
-- grow choice: centred, from the right edge (growing left, first icon on the
-- right) or from the left edge; a new row goes below or above. Icons are at
-- their size on screen (ns.IconSize). Returns the bar's size.
function B:Arrange(bar, frames, count, data)
    local size, spacing = ns.IconSize(data), data.spacing
    -- An empty bar keeps room for three icons so it can still be dragged.
    if count < 1 then
        Whole(bar)
        return 3 * size + 2 * spacing, size
    end
    local across = math.max(1, math.min(data.perRow, count))
    local rows = math.ceil(count / across)
    local step = size + spacing + (data.showNames and NAMES or 0)
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
    Outline(bar, frames, count, across, rows, size, step, data)
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

local function SavePosition(bar)
    local x, y = bar:GetCenter()
    local cx, cy = UIParent:GetCenter()
    if not (x and cx) then return end
    local point = Point(bar.data)
    local offsetX, offsetY = Offset(point, bar:GetWidth() or 0, bar:GetHeight() or 0)
    bar.data.x, bar.data.y, bar.data.point = Round(x - cx + offsetX), Round(y - cy + offsetY), point
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
end

-- The border and shadow round a whole bar, when chosen, only go round icons
-- that stay put. Packed Buffs and Debuffs and a bar that hides when ready
-- come and go (like Blizzard's Tracked Buffs), so they'd leave an empty box
-- behind, as would the greyed Debuffs spots while there's no enemy. A bar
-- that dims its ready icons keeps them in place, and its box.
local function Steady(key, data)
    if ns.AURA_BARS[key] then return not ns.BuffBar:Packed(data) end
    return not HidesReady(data)
end

local function BarDecor(bar)
    -- A layout waiting for the fight to end still has the old shape: keep the
    -- box as it is until then.
    if bar.pendingLayout then return end
    local border, shadow = Style:DecorFor("bar")
    local steady = Steady(bar.key, bar.data) and bar.enemy ~= false
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
    local border, shadow = Style:DecorFor("icon")
    for _, parts in ipairs(bar.groupParts) do Style:ShowDecor(parts.decor, border, shadow) end
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
    -- Fixed spots go in rows like icons; packed buffs are laid out by the
    -- game in one row.
    if ns.BuffBar:Packed(data) then
        local slots, size = bar.count > 0 and bar.count or 3, ns.IconSize(data)
        bar:SetSize(slots * size + (slots - 1) * data.spacing, size)
        Whole(bar)
    else
        bar:SetSize(B:Arrange(bar, bar.holders, bar.count, data))
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

local function Room(icon)
    Style:KeyRoom(icon.count, icon, 1, Numbers(icon.cooldown), icon.cooldown, icon.lift or 0, icon.keyed)
end

local function KeyLook(icon, size)
    icon.lift = Style:KeyLook(icon.key, icon, size, Style:CountdownSize(size))
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
    if bar.kind == "aura" then return LayoutAuras(bar, data) end
    -- Families laid out from the list follow what you carry at the next refresh.
    follow = true
    local size, spacing = ns.IconSize(data), data.spacing
    local count, on = 0, B:Enabled()
    for _, name in ipairs(data.spells) do
        local entry = ns.Spells:Find(name)
        if entry and ns.Spells:ForMe(name, bar.key) and not Absent(name) then
            count = count + 1
            local icon = bar.icons[count] or NewIcon(bar)
            bar.icons[count] = icon
            icon:SetSize(size, size)
            icon.cooldown:SetCountdownFont(Style:Countdown(size))
            icon.cooldown:SetHideCountdownNumbers(not data.showTimer)
            icon.count:SetFontObject(Style:Count(size))
            icon.spellID, icon.name, icon.reactive = entry.spellID, name, REACTIVE[entry.baseName or entry.name] == true
            icon.kind, icon.itemID, icon.slot, icon.current = entry.kind, entry.itemID, entry.slot, entry.current
            WatchRange(icon, on and not ITEM_KINDS[entry.kind] and entry.spellID or nil)
            KeyLook(icon, size)
            ShowKey(icon)
            icon.texture:SetTexture(entry.icon or (entry.spellID and C_Spell.GetSpellTexture(entry.spellID)))
            icon.count:SetText("")
            icon.label:SetWidth(size + spacing)
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

-- Public ------------------------------------------------------------------------------

function B:Enabled()
    return ns.Get("useBars") == true
end

-- One Buffs or Debuffs bar entry for the report: its name and the spell IDs
-- its icon shows. These bars keep their entries in holders, not icons.
local function ReportEntry(bar, i, say)
    local holder, ids = bar.holders and bar.holders[i], {}
    for id in pairs(bar.slotIDs and bar.slotIDs[i] or {}) do ids[#ids + 1] = id end
    table.sort(ids)
    return ("  %d. %s | spells %s"):format(i, say(holder and holder.label:GetText()), table.concat(ids, ","))
end

-- For /ccm debug (Debug.lua): each of your bars and the icons on it as they
-- are now: what each is, whether it's reactive, the game's usable answer,
-- and its glow; on the Buffs and Debuffs bars, each entry's spells. say
-- turns a secret answer into "secret".
function B:Report(add, say)
    add("Use my bars: " .. tostring(self:Enabled()))
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
                    add(("  %d. %s | %s %s | reactive %s | usable %s, no mana %s | glow %s (%s%s) | size %s | range watched %s"):format(i,
                        say(icon.name), say(icon.kind), say(icon.spellID or icon.itemID), tostring(icon.reactive), say(usable), say(noMana),
                        tostring(glow:IsShown()), glow.proc and "proc" or "edge", loop, say(icon:GetWidth()), tostring(icon.ranged == true)))
                end
            end
        end
    end
end

-- The border and shadow round a whole bar as set up, for the Layout page's
-- drawing: as chosen on the Look page, round a bar whose icons stay put.
function B:BarDecorFor(key)
    local border, shadow = Style:DecorFor("bar")
    local steady = Steady(key, ns.BarData(key))
    return border and steady, shadow and steady
end

-- Borders and shadows as chosen on the Look page, round every icon or bar.
function B:ApplyDecor()
    local border, shadow = Style:DecorFor("icon")
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

-- Keybinds placed and sized as chosen on the Look page.
function B:ApplyKeybinds()
    EachKey(function(icon, bar)
        KeyLook(icon, ns.IconSize(bar.data))
        ShowKey(icon)
    end)
end

-- The keys again after a binding or page change; text only, so in combat too.
function B:ShowKeys()
    EachKey(ShowKey)
end

function B:Get(key)
    return bars[key]
end

function B:IsUnlocked()
    return unlocked
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
    for _, key in ipairs(ns.BAR_KEYS) do
        local bar = bars[key]
        if bar then
            local mode = awake and "show" or bar.data.outOfCombat
            -- A bar taken out of your layout doesn't show at all.
            local out = ns.Layout ~= nil and ns.Layout:IsHidden(key)
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
    -- Items you carry none of show while unlocked, so they can be placed.
    if self.started and was ~= unlocked then Relay() end
    self:UpdateShown()
    self:RefreshAll()
    -- Unlocked, empty bars show too, so a layout makes room for them.
    if ns.Layout then ns.Layout:Stack() end
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

-- Lays the bars out again with your spells and items as they are now. Off,
-- bars made earlier are laid out with nothing watched and hidden, and none
-- are made.
local function Rebuild()
    Listen()
    if B:Enabled() or next(bars) then
        ns.Spells:Fresh()
        Recount()
        for _, key in ipairs(ns.BAR_KEYS) do
            local bar = bars[key] or NewBar(key)
            Layout(bar)
            -- A Look page change made in a fight while the bars were off:
            -- the driver didn't hear that fight end, so it's done now.
            if bar.pendingDecor then GroupDecor(bar) end
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

local SPELL_BARS = { "cd", "util" }

local function IndexOf(key, name)
    for i, spell in ipairs(ns.BarData(key).spells) do
        if spell == name then return i end
    end
end

-- The cooldown bar a spell is on, and its place there.
function B:Find(name)
    for _, key in ipairs(SPELL_BARS) do
        local index = IndexOf(key, name)
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

function B:Joined(key, index)
    local spells = ns.BarData(key).spells
    return ns.AURA_BARS[key] ~= nil and index > 1 and spells[index] ~= nil and ns.Joins(key)[spells[index]] == true
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
    if OnBar(key, name) then return true end
    if #ns.BarData(key).spells >= ns.BAR_MAX_SPELLS then return false end
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

-- Puts a spell on the Cooldowns or Utility bar, or takes it off with no bar;
-- it sits on one of the two at a time. Returns false when the bar is full.
function B:Assign(name, key)
    local current, index = self:Find(name)
    if current == key then return true end
    if key and not Space(key, name) then return false end
    if current then Take(current, index) end
    if key then
        local spells = ns.BarData(key).spells
        spells[#spells + 1] = name
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
        spells[#spells + 1] = name
    else
        Take(key, index)
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
    if entry.kind == "proc" and key ~= "buff" then
        return false, "Procs only go on the Buffs bar."
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
-- what dropping it does.
local function Vet(key, text)
    -- A debuff on you (Weakened Soul): no bar shows it by name, the Buffs
    -- or Debuffs bar's tick does.
    local selfNote = ns.Spells:SelfDebuffNote(text)
    if selfNote then return false, selfNote end
    local found, ids, given = ns.Spells:Resolve(text)
    if not found then return false, ids end
    local entry = ns.Spells:Find(found)
    local fits, why = B:Fits(key, entry, given ~= nil)
    if not fits then return false, why end
    local passive = ns.Spells:AddNote(text, key)
    if passive then return false, passive end
    if not Space(key, found) then return false, Full(key) end
    local plan = { name = found, shown = entry and entry.name or found }
    if ids and not entry then
        plan.remember = ids
    elseif given and entry and entry.added then
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
    plan.there = plan.remember == nil and OnBar(key, found)
    return true, plan
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
-- character) is remembered with it, so the mage's goes on by its ID.
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
    return true, said .. self:CarryNote(found), found
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

-- What B:AddItem would do, changing nothing, as B:CanAdd does for spells.
function B:CanAddItem(key, itemID)
    local ok, plan = VetItem(key, itemID)
    if not ok then return false, plan end
    return true, Preview(key, plan)
end

-- An item with a cooldown: an equipped trinket follows its slot. Ammunition
-- of any kind is your ammo, which counts whatever ammo you have equipped (a
-- class that never uses ammo is told so), and any rank of a healthstone or
-- potion is its family, which shows the best one you carry.
function B:AddItem(key, itemID)
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
    if not Take(key, index) then return end
    self:Changed()
end

local function Named(name)
    local entry = ns.Spells:Find(name)
    return entry and entry.name or name
end

-- An entry dragged off a bar: true and what happened.
function B:TakeOff(key, name)
    local index = IndexOf(key, name)
    if not index then return false end
    self:Remove(key, index)
    return true, "Took " .. Named(name) .. " off " .. ns.BAR_NAMES[key] .. "."
end

-- Why an entry can't go on a bar where it wouldn't show for you: a buff added
-- by name that another class casts on you shows on the Buffs bar only, and
-- anywhere else it would be hidden with no icon left to drag it back.
local function Unshown(name, key)
    return Named(name) .. " can't show on the " .. ns.BAR_NAMES[key] .. " bar for you."
end

-- An entry dragged from one bar onto another: true and what happened, or
-- false and why not.
function B:Transfer(from, to, name)
    if from == to or not IndexOf(from, name) then return false end
    local fits, why = self:Fits(to, ns.Spells:Find(name))
    if not fits then return false, why end
    if not ns.Spells:ForMe(name, to) then return false, Unshown(name, to) end
    local ok
    if ns.AURA_BARS[to] then ok = self:SetAura(to, name, true) else ok = self:Assign(name, to) end
    if not ok then return false, Full(to) end
    -- Between the two cooldown bars it's already moved; otherwise take it off.
    local index = IndexOf(from, name)
    if index then self:Remove(from, index) end
    return true, "Moved " .. Named(name) .. " to " .. ns.BAR_NAMES[to] .. "."
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
    for _, move in ipairs(moves) do
        local fits, why = self:Fits(move[2], ns.Spells:Find(move[1]))
        if not fits then return false, why end
        if not ns.Spells:ForMe(move[1], move[2]) then return false, Unshown(move[1], move[2]) end
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
    ns.BarData(from).spells[a], ns.BarData(to).spells[b] = other, name
    -- Neither is joined to anything, and nor is either in its new place.
    for _, key in ipairs({ from, to }) do
        if ns.AURA_BARS[key] then
            local joins = ns.Joins(key)
            joins[name], joins[other] = nil, nil
        end
    end
    self:Changed()
    return true, Swapped(name, other)
end

-- An option only changes how one bar looks, so only that bar is redrawn;
-- the size slider sends a change for every step it's dragged.
function B:SetOption(key, field, value)
    ns.BarData(key)[field] = value
    if not self.started then return end
    -- None are made while off: that waits for them to be turned on.
    if bars[key] or self:Enabled() then Layout(bars[key] or NewBar(key)) end
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

-- Empties a bar.
-- Clears what you see on a bar; another class's entries in a shared profile
-- stay for the characters that use them.
function B:Clear(key)
    local _, places = self:Mine(key)
    for n = #places, 1, -1 do Take(key, places[n]) end
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

local function OnEvent(_, event, arg)
    if event == "PLAYER_REGEN_DISABLED" then
        inCombat = true
        -- A Buffs or Debuffs bar still being dragged is let go where it
        -- is, just before the fight locks it in place.
        for key in pairs(ns.AURA_BARS) do
            if bars[key] then Drop(bars[key]) end
        end
        B:UpdateShown()
    elseif event == "PLAYER_REGEN_ENABLED" then
        inCombat = false
        -- Anything the aura bars had to wait for during the fight.
        for key in pairs(ns.AURA_BARS) do
            local bar = bars[key]
            if bar and bar.pendingLayout then
                Layout(bar)
            elseif bar and bar.pending then
                ns.BuffBar:Apply(bar)
            end
            if bar and bar.pendingDecor then GroupDecor(bar) end
            if bar then bar.pendingShown = nil end
        end
        -- And the buff and debuff times on the cooldown icons.
        for _, key in ipairs(ns.BAR_KEYS) do
            if bars[key] then ns.IconAuras:CombatEnded(bars[key]) end
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
        -- Turned off during the fight: done now, so the driver rests.
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
    elseif event == "SPELL_UPDATE_COOLDOWN" or event == "BAG_UPDATE_COOLDOWN" then
        -- A cooldown started (or the global cooldown, with every cast).
        cooling = true
    else
        if event == "PLAYER_TARGET_CHANGED" then
            ns.BuffBar:UpdateTarget(bars.debuff)
            ns.IconAuras:UpdateTarget(bars.cd)
            ns.IconAuras:UpdateTarget(bars.util)
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
    if not (dirty or cooling or tinting) then return end
    local part
    if not dirty and not (cooling and tinting) then part = cooling and "cooldown" or "state" end
    dirty, cooling, tinting = false, false, false
    if B.started and B:Enabled() then Each(part) end
end

-- The driver listens while your bars are on, made the first time they are.
-- Turned off in a fight, it still hears the fight end, when the Buffs and
-- Debuffs bars can hide.
Listen = function()
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
        driver:SetScript("OnUpdate", Tick)
    else
        driver:UnregisterAllEvents()
        driver:SetScript("OnUpdate", nil)
    end
end

function B:Start()
    if self.started then return end
    self.started = true
    local watch = CreateFrame("Frame")
    for _, event in ipairs({ "PLAYER_ENTERING_WORLD", "SPELLS_CHANGED", "PLAYER_EQUIPMENT_CHANGED", "BAG_UPDATE_DELAYED" }) do
        watch:RegisterEvent(event)
    end
    watch:SetScript("OnEvent", Listing)
    self.watch = watch
    -- Bars come back in full while Edit Mode is open.
    local editor = EditModeManagerFrame
    if editor and editor.HookScript then
        editor:HookScript("OnShow", function()
            editMode = true
            -- Items you carry none of show, to be placed, and a layout makes room.
            local any = next(absent) ~= nil
            if any then Relay() end
            B:UpdateShown()
            B:RefreshAll()
            if any and ns.Layout then ns.Layout:Stack() end
        end)
        -- The resource display may have moved: a layout follows it.
        editor:HookScript("OnHide", function()
            editMode = false
            if next(absent) then Relay() end
            B:UpdateShown()
            B:RefreshAll()
            if ns.Layout then ns.Layout:Stack() end
        end)
        editMode = editor:IsShown() and true or false
    end
    Rebuild()
end
