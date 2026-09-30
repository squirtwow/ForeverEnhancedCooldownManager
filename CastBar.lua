-- Your own cast bar, under Blizzard's Personal Resource Display: a row of
-- your stack (Cooldowns, the display, the cast bar, then Utility and the
-- rest), in the Tracked Bars design and a colour of your choice, with the
-- spell's icon, name and time left. Blizzard's own cast bar is made
-- invisible while it's on, never moved, so Edit Mode still has it. Off (the
-- default) it takes no room and the rows close up, so another addon's cast
-- bar works as before. On, it keeps its room between casts, since the Buffs
-- and Debuffs bars under it can't move in a fight. Should the game ever keep
-- a cast's times secret, Blizzard's own bar shows that cast instead.
--
-- A swing timer can share the spot (also off by default): Auto Shot for
-- hunters, the main hand for everyone, from the game's PLAYER_SWING. A cast
-- takes the spot while it lasts, then the swing timer comes back. With only
-- the swing timer on, casts are left to Blizzard's own bar.
local _, ns = ...

local C = {}
ns.CastBar = C

local Style = ns.Style
local GOLD, GREEN, RED = { 1, .7, 0 }, { 0, .8, 0 }, { .85, .15, .1 } -- casting, channelling, broken off
local SILVER = { .66, .68, .72 } -- the swing timer's own colour
local HOLD, FADE = .4, .3 -- a finished or broken cast, or a swing run out, stays up this long, then fades
local PAD = 4 -- under the display: the gap Blizzard leaves between its own bars
local EDGE = 1 -- the bar's own edge, just outside it and its icon
local ALONE = { x = 0, y = -150, width = 200, height = 0, edge = 0 } -- with no display to go under
local MAIN_HAND, RANGED = 16, 18 -- equipment slots
local SWORD, BOW = "Interface\\Icons\\INV_Sword_04", "Interface\\Icons\\INV_Weapon_Bow_05"
local LONGEST = 60 -- seconds: a swing any longer isn't a real one

local row -- your cast bar, once made
local cast -- the cast on it now: { channel, id, start, finish }
local fading -- when the last cast ended, while it fades
local swing -- the swing timer's latest swing: { ranged, total, finish }
local swingEnd -- when the last swing ran out with no new one, while it fades
local drawn -- what the bar is drawn for: "cast", "channel", "broken", "swing" or nil

-- Secret values can be handed to the game, but never read.
local function Open(value)
    return not (issecretvalue and issecretvalue(value))
end

-- Blizzard's own cast bar -------------------------------------------------------------
-- Invisible while yours is on: its alpha is kept at 0, and the hold-and-fade
-- it plays on an interrupt (which would show it for a second) is stopped as
-- it starts. What Blizzard asks for meanwhile comes back when yours is off,
-- once its own bar is casting, so a finished cast never lingers.
local hidden, hooked, writing = false, false, false
local wanted = 1

local function Conceal(frame)
    if not hidden or writing then return end
    writing = true
    frame:SetAlpha(0)
    writing = false
end

local function Native(show)
    local frame = _G.PlayerCastingBarFrame
    if not frame or (show and not hidden) then return end
    if not hooked then
        hooked = true
        hooksecurefunc(frame, "SetAlpha", function(self, alpha)
            if writing or not hidden then return end
            wanted = alpha
            Conceal(self)
        end)
        frame:HookScript("OnShow", Conceal)
        -- Right after Blizzard starts it, before anything is drawn.
        if type(frame.PlayInterruptAnims) == "function" then
            hooksecurefunc(frame, "PlayInterruptAnims", function(self)
                local hold = self.HoldFadeOutAnim
                if hidden and type(hold) == "table" and hold.Stop then hold:Stop() end
                Conceal(self)
            end)
        end
    end
    if show then
        hidden = false
        writing = true
        frame:SetAlpha((frame.casting or frame.channeling) and wanted or 0)
        writing = false
    elseif not hidden then
        wanted = frame:GetAlpha()
        hidden = true
        Conceal(frame)
    end
end

-- The look -----------------------------------------------------------------------------

-- Your colour, or Blizzard's: gold while casting, green while channelling.
local function Colour(channel)
    local key = ns.Get("castColour")
    if key ~= "default" then return Style:BarColour(key) end
    return channel and GREEN or GOLD
end

-- The swing timer's colour: yours, or silver.
function C:SwingColour()
    local key = ns.Get("swingColour")
    if key ~= "default" then return Style:BarColour(key) end
    return SILVER
end

-- The spot's colour, as the Layout page draws it: the cast bar's, or the
-- swing timer's while only that's on.
function C:Colour()
    if not ns.Get("castBar") and ns.Get("swingTimer") then return self:SwingColour() end
    return Colour(false)
end

function C:Hunter()
    local _, class = UnitClass("player")
    return class == "HUNTER"
end

-- What a swing is called: Auto Shot for hunters, and the main hand.
function C:SwingName(ranged)
    if not ranged then return "Main hand" end
    return self:Hunter() and "Auto Shot" or "Ranged"
end

-- A bow or a sword, for the preview and when the weapon's own icon isn't to hand.
function C:SwingIcon(ranged)
    return ranged and BOW or SWORD
end

-- The weapon's own icon.
function C:WeaponIcon(ranged)
    local texture = GetInventoryItemTexture and GetInventoryItemTexture("player", ranged and RANGED or MAIN_HAND)
    if Open(texture) and texture then return texture end
    return self:SwingIcon(ranged)
end

-- A cast bar's parts, for yours and for the window's preview: the spell's
-- icon, then the bar with the spell's name and time left on it.
function C:Make(parent)
    local frame = CreateFrame("Frame", nil, parent)
    frame:SetSize(200, 18)
    frame.icon = frame:CreateTexture(nil, "ARTWORK")
    frame.icon:SetPoint("TOPLEFT")
    Style:Zoom(frame.icon)
    frame.iconEdge = frame:CreateTexture(nil, "BACKGROUND")
    frame.iconEdge:SetPoint("TOPLEFT", frame.icon, "TOPLEFT", -EDGE, EDGE)
    frame.iconEdge:SetPoint("BOTTOMRIGHT", frame.icon, "BOTTOMRIGHT", EDGE, -EDGE)
    frame.iconEdge:SetColorTexture(0, 0, 0, 1)
    local bar = CreateFrame("StatusBar", nil, frame)
    bar.fill = Style:BarTexture()
    bar:SetStatusBarTexture(bar.fill)
    bar:SetMinMaxValues(0, 1)
    bar:SetValue(0)
    local track = bar:CreateTexture(nil, "BACKGROUND")
    track:SetAllPoints()
    track:SetColorTexture(Style.TRACK[1], Style.TRACK[2], Style.TRACK[3], Style.TRACK[4])
    -- A 1px edge round the bar, and Glass's shine over its top half.
    bar.edge = bar:CreateTexture(nil, "BACKGROUND", nil, -8)
    bar.edge:SetPoint("TOPLEFT", -EDGE, EDGE)
    bar.edge:SetPoint("BOTTOMRIGHT", EDGE, -EDGE)
    bar.sheen = bar:CreateTexture(nil, "OVERLAY", nil, -8)
    bar.sheen:SetPoint("TOPLEFT")
    bar.sheen:SetPoint("BOTTOMRIGHT", bar, "RIGHT")
    bar.sheen:SetColorTexture(1, 1, 1, .16)
    bar.name = bar:CreateFontString(nil, "OVERLAY")
    bar.name:SetFontObject(Style:Font(10))
    bar.name:SetJustifyH("LEFT")
    bar.name:SetWordWrap(false)
    bar.time = bar:CreateFontString(nil, "OVERLAY")
    bar.time:SetFontObject(Style:Font(10))
    bar.time:SetJustifyH("RIGHT")
    bar.time:SetPoint("RIGHT", -4, 0)
    frame.bar = bar
    -- A soft shadow round the whole cast bar while shadows are on, and no
    -- extra border: its own 1px edges are one (Dress places the shadow).
    frame.decor = Style:Decor(frame, frame, -EDGE)
    return frame
end

-- Sizes and colours a cast bar from your choices: its height, the design,
-- the texture, the colour and which parts show.
local function Dress(frame, colour)
    local height = ns.Get("castHeight")
    local design = ns.Get("barStyle")
    local outline = design == "outline"
    local withIcon, withTime = ns.Get("castIcon"), ns.Get("castTime")
    local bar = frame.bar
    frame:SetHeight(height)
    frame.icon:SetSize(height, height)
    frame.icon:SetShown(withIcon)
    frame.iconEdge:SetShown(withIcon)
    bar:ClearAllPoints()
    bar:SetPoint("TOPLEFT", withIcon and height + 3 or 0, 0)
    bar:SetPoint("BOTTOMRIGHT")
    -- Dressed for every cast: the texture is only set again when it changes.
    local texture = Style:BarTexture()
    if bar.fill ~= texture then
        bar.fill = texture
        bar:SetStatusBarTexture(texture)
    end
    bar:SetStatusBarColor(colour[1], colour[2], colour[3], outline and .45 or 1)
    local edge = outline and colour or { 0, 0, 0 }
    bar.edge:SetColorTexture(edge[1], edge[2], edge[3], 1)
    bar.sheen:SetShown(design == "glass")
    local font = Style:Font(math.max(9, height * .55))
    bar.name:SetFontObject(font)
    bar.time:SetFontObject(font)
    bar.name:ClearAllPoints()
    bar.name:SetPoint("LEFT", 4, 0)
    bar.name:SetPoint("RIGHT", withTime and -40 or -4, 0)
    bar.name:SetShown(ns.Get("castName"))
    bar.time:SetShown(withTime)
    -- The shadow reaches as far out as your rows' does: it starts on the
    -- bar's edge, as theirs starts on their icons, or just past it while a
    -- border sits under their shadow and pushes it out.
    local shadow = ns.Get("iconShadow")
    frame.decor.inset = ns.Get("iconBorder") == shadow and -EDGE or 0
    Style:ShowDecor(frame.decor, false, shadow ~= "off")
end

-- A cast's colour: red once it's broken off.
function C:Look(frame, channel, broken)
    Dress(frame, broken and RED or Colour(channel))
end

function C:SwingLook(frame)
    Dress(frame, self:SwingColour())
end

-- Drawing ------------------------------------------------------------------------------
-- One bar, drawn for a cast or a swing. It only ticks while something shows
-- or fades.

local function DrawSwing()
    drawn = "swing"
    C:SwingLook(row)
    row.bar:SetMinMaxValues(0, swing.total)
    row.icon:SetTexture(C:WeaponIcon(swing.ranged))
    row.bar.name:SetText(C:SwingName(swing.ranged))
    row:SetAlpha(1)
end

-- The cast has left the spot: a swing still running takes it back, but one
-- that ran out meanwhile doesn't come back just to fade.
local function Handover(now)
    if swing and swing.finish <= now then swing = nil end
    swingEnd, drawn = nil, nil
end

local function Tick()
    local now = GetTime()
    if cast then
        local bar, left = row.bar, math.max(0, cast.finish - now)
        bar:SetValue(cast.channel and left or math.min(cast.total, now - cast.start))
        bar.time:SetFormattedText("%.1f", left)
        return
    end
    if fading then
        local gone = now - fading
        if gone < HOLD + FADE then
            if gone > HOLD then row:SetAlpha(1 - (gone - HOLD) / FADE) end
            return
        end
        fading = nil
        Handover(now)
    end
    if swing then
        if drawn ~= "swing" then DrawSwing() end
        local left = swing.finish - now
        if left > 0 then
            row.bar:SetValue(swing.total - left)
            row.bar.time:SetFormattedText("%.1f", left)
            return
        end
        -- Run out with no new swing yet: full and held, then it fades, so it
        -- never blinks out between shots.
        row.bar:SetValue(swing.total)
        row.bar.time:SetFormattedText("%.1f", 0)
        swing, swingEnd = nil, swing.finish
    end
    if swingEnd and drawn == "swing" then
        local gone = now - swingEnd
        if gone < HOLD + FADE then
            row:SetAlpha(gone > HOLD and 1 - (gone - HOLD) / FADE or 1)
            return
        end
    end
    -- Nothing left to show: no more work each frame.
    swingEnd, drawn = nil, nil
    row:SetAlpha(0)
    row:SetScript("OnUpdate", nil)
end

local function Wake()
    row:SetScript("OnUpdate", Tick)
    Tick()
end

-- No cast on the bar any more; a swing timer carries on.
local function DropCast()
    if not (cast or fading) then return end
    cast, fading = nil, nil
    Handover(GetTime())
    Wake()
end

local function DropSwing()
    swing, swingEnd = nil, nil
    if drawn == "swing" then
        drawn = nil
        Wake()
    end
end

-- Whatever's on the bar now, restyled after a choice changes.
local function Restyle()
    if drawn == "swing" then
        C:SwingLook(row)
    else
        C:Look(row, drawn == "channel", drawn == "broken")
    end
end

-- Casting ------------------------------------------------------------------------------

local function Begin(channel)
    local name, text, texture, startMS, endMS, id, _
    if channel then
        name, text, texture, startMS, endMS = UnitChannelInfo("player")
    else
        name, text, texture, startMS, endMS, _, id = UnitCastingInfo("player")
    end
    if Open(name) and not name then return end
    if not (Open(startMS) and Open(endMS) and Open(id)) then
        DropCast()
        Native(true)
        return
    end
    Native(false)
    local start, finish = startMS / 1000, endMS / 1000
    cast, fading = { channel = channel, id = id, start = start, finish = finish, total = math.max(.001, finish - start) }, nil
    drawn = channel and "channel" or "cast"
    C:Look(row, channel)
    row.bar:SetMinMaxValues(0, cast.total)
    row.icon:SetTexture(texture)
    row.bar.name:SetText(text)
    row:SetAlpha(1)
    row:SetScript("OnUpdate", Tick)
    Tick()
end

-- Finished: full, then it fades.
local function Done()
    if not cast.channel then row.bar:SetValue(cast.total) end
    cast, fading = nil, GetTime()
end

-- Interrupted or failed: full and red, saying so, then it fades.
local function Broken(text)
    local channel, total = cast.channel, cast.total
    cast, fading = nil, GetTime()
    drawn = "broken"
    C:Look(row, channel, true)
    row.bar:SetValue(total)
    row.bar.name:SetText(text)
    row.bar.time:SetText("")
end

local INTERRUPT_TEXT, FAIL_TEXT = INTERRUPTED or "Interrupted", FAILED or "Failed"

function C:Event(event, id, interruptedBy)
    if not row then return end
    -- A new world or weapon: the last swing is over.
    if event == "PLAYER_ENTERING_WORLD" or event == "WEAPON_SLOT_CHANGED" then DropSwing() end
    if event == "WEAPON_SLOT_CHANGED" or not ns.Get("castBar") then return end
    if event == "PLAYER_ENTERING_WORLD" then
        local channelling, casting = UnitChannelInfo("player"), UnitCastingInfo("player")
        if not Open(channelling) or channelling then
            Begin(true)
        elseif not Open(casting) or casting then
            Begin(false)
        else
            DropCast()
        end
    elseif event == "UNIT_SPELLCAST_START" or event == "UNIT_SPELLCAST_DELAYED" then
        Begin(false)
    elseif event == "UNIT_SPELLCAST_CHANNEL_START" or event == "UNIT_SPELLCAST_CHANNEL_UPDATE" then
        Begin(true)
    elseif not cast then
        return
    elseif event == "UNIT_SPELLCAST_STOP" then
        if not cast.channel and Open(id) and id == cast.id then Done() end
    elseif event == "UNIT_SPELLCAST_CHANNEL_STOP" then
        if cast.channel then
            if not Open(interruptedBy) or interruptedBy ~= nil then Broken(INTERRUPT_TEXT) else Done() end
        end
    elseif event == "UNIT_SPELLCAST_FAILED" or event == "UNIT_SPELLCAST_INTERRUPTED" then
        if not cast.channel and Open(id) and id == cast.id then
            Broken(event == "UNIT_SPELLCAST_FAILED" and FAIL_TEXT or INTERRUPT_TEXT)
        end
    end
end

-- Swinging -----------------------------------------------------------------------------

-- The game's PLAYER_SWING: the seconds until the next swing, and which hand
-- (0 main hand, 1 off hand, 2 ranged). The newest main hand or ranged swing
-- shows, filling until the next; the off hand doesn't. A swing the game keeps
-- secret is skipped, never guessed at.
function C:Swing(duration, kind)
    if not (row and ns.Get("swingTimer")) then return end
    if not (Open(duration) and Open(kind)) then return end
    if (kind ~= 0 and kind ~= 2) or type(duration) ~= "number" or not (duration > 0 and duration < LONGEST) then return end
    swing, swingEnd = { ranged = kind == 2, total = duration, finish = GetTime() + duration }, nil
    -- A cast keeps the spot until it's gone.
    if not (cast or fading) then DrawSwing() end
    Wake()
end

-- Auto-attack or Auto Shot switched off (the target died, you stopped, or
-- changed target): that swing isn't coming, so the bar stops where it is and
-- fades instead of filling on. The other kind of swing carries on.
function C:SwingStopped(ranged)
    if not (row and swing) or swing.ranged ~= ranged then return end
    swing = nil
    if drawn == "swing" then
        swingEnd = GetTime()
        row.bar.time:SetText("")
        Wake()
    end
end

-- Its place ----------------------------------------------------------------------------

-- How much room it takes under the display while the cast bar or the swing
-- timer is on.
function C:Room()
    if ns.Get("castBar") or ns.Get("swingTimer") then return ns.Get("castHeight") end
    return nil
end

-- Puts the bar under the display (and its combo points), as wide as it, and
-- gives back where the next row starts: under the bar, or under the display
-- while the bar is off. With the display switched off it sits where that was.
function C:Under(display)
    local bottom = display.y - display.height / 2
    local height = self:Room()
    if not height then return bottom end
    local pad = display.height > 0 and PAD or 0
    -- The bar's own edges, round its icon too, go on the restyle's, so the
    -- whole bar is exactly as wide as the display you see, at any Size and
    -- while it's switched off (its width still takes them in). Without the
    -- restyle they sit where its edges would, just outside the display's
    -- bars, like the combo points'.
    local width = display.width
    if (display.edge or 0) > 0 then width = width - 2 * EDGE end
    if row then
        row:ClearAllPoints()
        row:SetPoint("TOP", UIParent, "CENTER", display.x, bottom - pad)
        row:SetWidth(width >= 40 and width or ALONE.width)
    end
    return bottom - pad - height
end

-- Without a layout: under the display on its own, or where it would be.
function C:Place()
    self:Under(ns.Layout and ns.Layout:Display() or ALONE)
end

-- After a choice changes: shown or not (Blizzard's bar back while the cast
-- bar is off), restyled, and the rows moved to make room or close up.
function C:Apply()
    if not row then return end
    local casts, swings = ns.Get("castBar") == true, ns.Get("swingTimer") == true
    row:SetShown(casts or swings)
    if not casts then DropCast() end
    if not swings then DropSwing() end
    Native(not casts)
    Restyle()
    if ns.Layout then ns.Layout:Stack() else self:Place() end
end

function C:Start()
    if self.started then return end
    self.started = true
    row = self:Make(UIParent)
    row:SetAlpha(0)
    local events = CreateFrame("Frame")
    for _, event in ipairs({ "UNIT_SPELLCAST_START", "UNIT_SPELLCAST_STOP", "UNIT_SPELLCAST_FAILED",
        "UNIT_SPELLCAST_INTERRUPTED", "UNIT_SPELLCAST_DELAYED", "UNIT_SPELLCAST_CHANNEL_START",
        "UNIT_SPELLCAST_CHANNEL_UPDATE", "UNIT_SPELLCAST_CHANNEL_STOP" }) do
        events:RegisterUnitEvent(event, "player")
    end
    events:RegisterEvent("PLAYER_ENTERING_WORLD")
    -- Forever's own swing events; a client without them just has no swing timer.
    pcall(events.RegisterEvent, events, "PLAYER_SWING")
    pcall(events.RegisterEvent, events, "WEAPON_SLOT_CHANGED")
    -- Auto-attack and Auto Shot switching off.
    pcall(events.RegisterEvent, events, "PLAYER_LEAVE_COMBAT")
    pcall(events.RegisterEvent, events, "STOP_AUTOREPEAT_SPELL")
    events:SetScript("OnEvent", function(_, event, ...)
        if event == "PLAYER_SWING" then
            C:Swing(...)
        elseif event == "PLAYER_LEAVE_COMBAT" or event == "STOP_AUTOREPEAT_SPELL" then
            C:SwingStopped(event == "STOP_AUTOREPEAT_SPELL")
        else
            local _, id, _, interruptedBy = ...
            C:Event(event, id, interruptedBy)
        end
    end)
    self.row = row
    self:Apply()
end
