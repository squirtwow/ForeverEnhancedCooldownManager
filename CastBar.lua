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

-- fn as a hook on Blizzard's cast bar: anything going wrong is reported once
-- and never handed back, so Blizzard's own cast bar code carries on.
local function Safely(fn)
    return function(...)
        local ok, err = pcall(fn, ...)
        if not ok and not C.lastError then
            C.lastError = tostring(err)
            print("|cffffd100" .. ns.TITLE .. ":|r couldn't hide Blizzard's cast bar. Please report this: " .. C.lastError)
        end
    end
end

local function Native(show)
    local frame = _G.PlayerCastingBarFrame
    if not frame or (show and not hidden) then return end
    if not hooked then
        hooked = true
        hooksecurefunc(frame, "SetAlpha", Safely(function(self, alpha)
            if writing or not hidden then return end
            wanted = alpha
            Conceal(self)
        end))
        frame:HookScript("OnShow", Safely(Conceal))
        -- Right after Blizzard starts it, before anything is drawn.
        if type(frame.PlayInterruptAnims) == "function" then
            hooksecurefunc(frame, "PlayInterruptAnims", Safely(function(self)
                local hold = self.HoldFadeOutAnim
                if hidden and type(hold) == "table" and hold.Stop then hold:Stop() end
                Conceal(self)
            end))
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
    -- Thick edges: a second black pixel just inside the icon's edge.
    frame.iconInner = Style:InnerEdge(frame, frame.icon)
    local bar = CreateFrame("StatusBar", nil, frame)
    bar.fill = Style:BarTexture()
    bar:SetStatusBarTexture(bar.fill)
    bar:SetMinMaxValues(0, 1)
    bar:SetValue(0)
    -- The track behind the fill. (Not .track: the tests' layout checks take a
    -- frame's .track for a slider's, and the Cast bar page shows this one.)
    bar.background = bar:CreateTexture(nil, "BACKGROUND")
    bar.background:SetAllPoints()
    bar.background:SetColorTexture(Style:TrackColour())
    -- A 1px edge round the bar (and with Thick edges a second pixel inside
    -- it), and Glass's shine over its top half.
    bar.edge = bar:CreateTexture(nil, "BACKGROUND", nil, -8)
    bar.edge:SetPoint("TOPLEFT", -EDGE, EDGE)
    bar.edge:SetPoint("BOTTOMRIGHT", EDGE, -EDGE)
    bar.inner = Style:InnerEdge(bar, bar)
    local shine = bar:CreateTexture(nil, "OVERLAY", nil, -8)
    shine:SetPoint("TOPLEFT")
    shine:SetPoint("BOTTOMRIGHT", bar, "RIGHT")
    shine:SetColorTexture(1, 1, 1, .16)
    bar.sheen = Style:Sheen(bar, shine)
    bar.name = bar:CreateFontString(nil, "OVERLAY")
    bar.name:SetFontObject(Style:Font(10))
    bar.name:SetJustifyH("LEFT")
    bar.name:SetWordWrap(false)
    bar.time = bar:CreateFontString(nil, "OVERLAY")
    bar.time:SetFontObject(Style:Font(10))
    bar.time:SetJustifyH("RIGHT")
    bar.time:SetPoint("RIGHT", -4, 0)
    -- Your latency: a zone at the end of a cast (the start of a channel, as
    -- it drains), drawn like the fill (its texture, under Glass's shine),
    -- and how long it is at the right end.
    bar.lag = bar:CreateTexture(nil, "ARTWORK", nil, 7)
    bar.lag:Hide()
    bar.ms = bar:CreateFontString(nil, "OVERLAY")
    bar.ms:SetFontObject(Style:Font(8))
    bar.ms:SetJustifyH("RIGHT")
    bar.ms:SetPoint("RIGHT", -4, 0)
    bar.ms:Hide()
    frame.bar = bar
    -- A soft shadow round the whole cast bar while shadows are on, and no
    -- extra border: its own 1px edges are one (Dress places the shadow).
    frame.decor = Style:Decor(frame, frame, -EDGE)
    -- The choices it was last sized for, and the colour it was last given.
    frame.fit, frame.paint = {}, {}
    return frame
end

local BLACK = { 0, 0, 0 }

-- Sizes a cast bar from your choices: its height, the design, the texture,
-- the darkness and edges, which parts show and its shadow. A cast or a swing
-- starts every second or two, so it's only done again when one of these has
-- changed since. True when it was done.
local function Fit(frame)
    local height, design, texture = ns.Get("castHeight"), ns.Get("barStyle"), Style:BarTexture()
    local withIcon, withTime, withName = ns.Get("castIcon"), ns.Get("castTime"), ns.Get("castName")
    local shadow, border = ns.Get("iconShadow"), ns.Get("iconBorder")
    local dark, thick = ns.Get("barDarkness"), ns.Get("thickEdges")
    local whole, ms = ns.Get("castTimeFormat") == "total", ns.Get("castLatency") and ns.Get("castLatencyText")
    local fit = frame.fit
    if fit.height == height and fit.design == design and fit.texture == texture and fit.icon == withIcon
        and fit.time == withTime and fit.name == withName and fit.shadow == shadow and fit.border == border
        and fit.dark == dark and fit.thick == thick and fit.whole == whole and fit.ms == ms then
        return false
    end
    fit.height, fit.design, fit.texture, fit.icon, fit.time = height, design, texture, withIcon, withTime
    fit.name, fit.shadow, fit.border, fit.dark, fit.thick = withName, shadow, border, dark, thick
    fit.whole, fit.ms = whole, ms
    local bar = frame.bar
    frame:SetHeight(height)
    frame.icon:SetSize(height, height)
    frame.icon:SetShown(withIcon)
    frame.iconEdge:SetShown(withIcon)
    Style:ShowInnerEdge(frame.iconInner, BLACK, withIcon)
    bar:ClearAllPoints()
    bar:SetPoint("TOPLEFT", withIcon and height + 3 or 0, 0)
    bar:SetPoint("BOTTOMRIGHT")
    -- The texture is only set again when it changes.
    if bar.fill ~= texture then
        bar.fill = texture
        bar:SetStatusBarTexture(texture)
    end
    bar.background:SetColorTexture(Style:TrackColour())
    Style:ShowSheen(bar.sheen, design == "glass")
    local font = Style:Font(math.max(9, height * .55))
    bar.name:SetFontObject(font)
    bar.time:SetFontObject(font)
    -- The ms at the right end, smaller, and the time just left of it: the
    -- name keeps clear of both.
    bar.ms:SetFontObject(Style:Font(math.max(8, height * .4)))
    bar.time:ClearAllPoints()
    if ms then bar.time:SetPoint("RIGHT", bar.ms, "LEFT", -4, 0) else bar.time:SetPoint("RIGHT", -4, 0) end
    local room = (withTime and (whole and 70 or 40) or 4) + (ms and 34 or 0)
    bar.name:ClearAllPoints()
    bar.name:SetPoint("LEFT", 4, 0)
    bar.name:SetPoint("RIGHT", -room, 0)
    bar.name:SetShown(withName)
    bar.time:SetShown(withTime)
    -- The shadow reaches as far out as your rows' does: it starts on the
    -- bar's edge, as theirs starts on their icons, or just past it while a
    -- border sits under their shadow and pushes it out.
    frame.decor.inset = border == shadow and -EDGE or 0
    Style:ShowDecor(frame.decor, false, shadow ~= "off")
    return true
end

-- Sizes and colours a cast bar from your choices. The colour goes with the
-- cast (gold, green, red, or yours), so it's set whenever it changes, and
-- again after a new fit.
local function Dress(frame, colour)
    local fitted = Fit(frame)
    local r, g, b = colour[1], colour[2], colour[3]
    local paint = frame.paint
    if not fitted and paint.r == r and paint.g == g and paint.b == b then return end
    paint.r, paint.g, paint.b = r, g, b
    local outline = frame.fit.design == "outline"
    local bar = frame.bar
    bar:SetStatusBarColor(r, g, b, outline and .45 or 1)
    local edge = outline and colour or BLACK
    bar.edge:SetColorTexture(edge[1], edge[2], edge[3], 1)
    Style:ShowInnerEdge(bar.inner, edge)
end

-- A cast's colour: red once it's broken off.
function C:Look(frame, channel, broken)
    Dress(frame, broken and RED or Colour(channel))
end

function C:SwingLook(frame)
    Dress(frame, self:SwingColour())
end

-- The time on a bar: seconds left, or left / the whole cast, as chosen.
function C:Time(text, left, total)
    if ns.Get("castTimeFormat") == "total" then
        text:SetFormattedText("%.1f / %.1f", left, total)
    else
        text:SetFormattedText("%.1f", left)
    end
end

-- The latency zone's colour, nearly solid like the fill, in the same red as
-- a broken cast.
local LAG_COLOURS = { red = { RED[1], RED[2], RED[3], .85 }, white = { 1, 1, 1, .7 }, black = { 0, 0, 0, .7 } }

local PALER = .5 -- Paler: this much of the way from the cast bar's colour to white

function C:LagColour(key, channel)
    key = key or ns.Get("castLatencyColour")
    if LAG_COLOURS[key] then return LAG_COLOURS[key] end
    if key == "paler" then
        local own = Colour(channel)
        return { own[1] + (1 - own[1]) * PALER, own[2] + (1 - own[2]) * PALER, own[3] + (1 - own[3]) * PALER, .85 }
    end
    local colour = Style:BarColour(key)
    return { colour[1], colour[2], colour[3], .85 }
end

-- The latency zone on a cast bar, while it's on: this share of the bar, at
-- the right end of a cast or the left of a channel (where each ends), and
-- its ms at the right end if that's ticked. Nil hides it.
function C:Lag(frame, share, ms, channel)
    local bar = frame.bar
    local width = bar:GetWidth()
    if not (share and ns.Get("castLatency") and type(width) == "number" and width > 0) then
        bar.lag:Hide()
        bar.ms:Hide()
        return
    end
    local colour = self:LagColour(nil, channel)
    local side = channel and "LEFT" or "RIGHT"
    -- The bar's own texture, set only when it changes; Outline's see-through
    -- fill gets a see-through zone.
    local texture = Style:BarTexture()
    if bar.lag.texture ~= texture then
        bar.lag.texture = texture
        bar.lag:SetTexture(texture)
    end
    bar.lag:SetVertexColor(colour[1], colour[2], colour[3], ns.Get("barStyle") == "outline" and .45 or colour[4])
    bar.lag:ClearAllPoints()
    bar.lag:SetPoint("TOP" .. side)
    bar.lag:SetPoint("BOTTOM" .. side)
    bar.lag:SetWidth(math.max(1, math.min(1, share) * width))
    bar.lag:Show()
    bar.ms:SetFormattedText("%dms", ms)
    bar.ms:SetShown(ns.Get("castLatencyText") == true)
end

-- Drawing ------------------------------------------------------------------------------
-- One bar, drawn for a cast or a swing. It only ticks while something shows
-- or fades.

local function DrawSwing()
    drawn = "swing"
    C:Lag(row, nil)
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

-- A batch of crafts (Create All or a number): the game says how many casts
-- are left after this one. Each tradeskill cast asks again; a count that
-- doesn't go down starts a new batch. Nil for anything else.
local batch
local function Batch(tradeSkill)
    local api = C_TradeSkillUI and C_TradeSkillUI.GetRemainingRecasts
    if not (ns.Get("castBatch") and api and Open(tradeSkill) and tradeSkill) then batch = nil return nil end
    local ok, left = pcall(api)
    if not ok or not Open(left) or type(left) ~= "number" or left < 0 then batch = nil return nil end
    if not batch or left >= batch.last then
        if left == 0 then batch = nil return nil end
        batch = { total = left + 1 }
    end
    batch.last = left
    local this = { index = batch.total - left, total = batch.total, left = left }
    if left == 0 then batch = nil end
    return this
end

-- Minutes and seconds for the whole batch.
local function Clock(seconds)
    seconds = math.floor(seconds + .5)
    return ("%d:%02d left"):format(math.floor(seconds / 60), seconds % 60)
end

-- Tick marks ---------------------------------------------------------------------------
-- Where each tick of a channelled spell lands, as thin marks across the bar
-- (Cast bar page, off by default). How many times a spell ticks comes from
-- Forever's own spell data: its duration over its period, by spell ID, so each
-- rank has its own (made by Tools/MakeChannelTicks.mjs). The ticks are spread
-- evenly over the channel as it started, so haste is counted, and keep their
-- moments when a hit pushes the channel back: the ones past its new end go.
-- Each is a pair of short light notches, one down from the bar's top edge and
-- one up from its bottom, so they read as ticks rather than splitting the bar
-- into blocks like the combo points.
local CHANNEL_TICKS = {
    [5143] = 3, [5144] = 4, [5145] = 5, [8416] = 5, [8417] = 5, [10211] = 5, [10212] = 5, [25345] = 5, -- Arcane Missiles
    [10] = 8, [6141] = 8, [8427] = 8, [10185] = 8, [10186] = 8, [10187] = 8, -- Blizzard
    [17767] = 5, [17850] = 5, [17851] = 5, [17852] = 5, [17853] = 5, [17854] = 5, -- Consume Shadows
    [689] = 5, [699] = 5, [709] = 5, [7651] = 5, [11699] = 5, [11700] = 5, -- Drain Life
    [5138] = 5, [6226] = 5, [11703] = 5, [11704] = 5, -- Drain Mana
    [1120] = 5, [8288] = 5, [8289] = 5, [11675] = 5, -- Drain Soul
    [12051] = 8, -- Evocation
    [746] = 6, [1159] = 6, [3267] = 7, [3268] = 7, [7926] = 8, [7927] = 8, [10838] = 8, [10839] = 8, [18608] = 8, [18610] = 8, [23567] = 8, [23568] = 8, [23569] = 8, [23696] = 8, [24412] = 8, [24413] = 8, [24414] = 8, [30020] = 10, [470345] = 8, [1290863] = 8, [1290865] = 8, [1290867] = 8, -- First Aid
    [755] = 10, [3698] = 10, [3699] = 10, [3700] = 10, [11693] = 10, [11694] = 10, [11695] = 10, -- Health Funnel
    [1949] = 15, [11683] = 15, [11684] = 15, -- Hellfire
    [16914] = 10, [17401] = 10, [17402] = 10, -- Hurricane
    [136] = 5, [3111] = 5, [3661] = 5, [3662] = 5, [13542] = 5, [13543] = 5, [13544] = 5, -- Mend Pet
    [15407] = 3, [17311] = 3, [17312] = 3, [17313] = 3, [17314] = 3, [18807] = 3, -- Mind Flay
    [5740] = 4, [6219] = 4, [11677] = 4, [11678] = 4, -- Rain of Fire
    [10797] = 6, [19296] = 6, [19299] = 6, [19302] = 6, [19303] = 6, [19304] = 6, [19305] = 6, -- Starshards
    [740] = 5, [8918] = 5, [9862] = 5, [9863] = 5, -- Tranquility
    [1510] = 6, [14294] = 6, [14295] = 6, -- Volley
    [1316697] = 6, -- Wrack
}
local MARK_COLOURS = { white = { 1, 1, 1, .8 }, black = { 0, 0, 0, .85 } }
local NOTCH = .35 -- each notch's share of the bar's height
local NONE = {}

-- White, black or a bar colour, as chosen on the Cast bar page.
function C:MarkColour(key)
    key = key or ns.Get("castTickColour")
    if MARK_COLOURS[key] then return MARK_COLOURS[key] end
    local colour = Style:BarColour(key)
    return { colour[1], colour[2], colour[3], 1 }
end

local function Notch(bar)
    return bar:CreateTexture(nil, "OVERLAY", nil, -6)
end

-- One screen pixel in the bar's own units. A notch a whole number of them
-- wide, its edges on whole pixels too (C:Marks), is drawn crisp and the same
-- width wherever it lands; otherwise one comes out a pixel wider or
-- narrower, or blurred over the next, here and there.
local function Pixel(frame)
    local _, high = GetPhysicalScreenSize and GetPhysicalScreenSize()
    local scale = type(frame.GetEffectiveScale) == "function" and frame:GetEffectiveScale()
    if not (type(high) == "number" and high > 0 and type(scale) == "number" and scale > 0) then return 1 end
    return 768 / high / scale
end

-- Marks on a cast bar's bar at these fractions of its width from the left,
-- in the colour, style and width chosen; any it had past those hide. For
-- your cast bar and the Cast bar page's preview alike.
function C:Marks(bar, at)
    local marks = bar.marks or {}
    bar.marks = marks
    local width, height, shown = bar:GetWidth(), bar:GetHeight(), 0
    if type(width) == "number" and width > 0 then
        local px = Pixel(bar)
        local wide = ns.Get("castTickWidth") * px
        local lines = ns.Get("castTickStyle") == "lines"
        local tall = math.max(2, math.floor((type(height) == "number" and height or 0) * NOTCH / px + .5)) * px
        local colour = self:MarkColour()
        -- Where the bar starts on the screen, so each tick's edge can go on a
        -- whole pixel whatever your UI scale and the bar's place. Drawn a
        -- tenth of a pixel inside each edge: exactly on them, the game's
        -- rounding can tip an edge either way and make a tick a pixel wider
        -- (seen at UI scale 0.65 on 1440p).
        local left = bar.GetLeft and bar:GetLeft()
        local drawn = wide - .2 * px
        for _, share in ipairs(at) do
            local x = share * width
            if type(left) == "number" then
                x = math.floor((left + x - wide / 2) / px + .5) * px + wide / 2 - left
            end
            if x > wide and x < width - wide then
                shown = shown + 1
                local mark = marks[shown]
                if not mark then
                    mark = { top = Notch(bar), bottom = Notch(bar) }
                    marks[shown] = mark
                end
                local top, bottom = mark.top, mark.bottom
                top:SetColorTexture(colour[1], colour[2], colour[3], colour[4])
                top:SetWidth(drawn)
                top:ClearAllPoints()
                top:SetPoint("TOP", bar, "TOPLEFT", x, 0)
                top:Show()
                -- Lines: the top one right down the bar, and no bottom one.
                if lines then
                    top:SetPoint("BOTTOM", bar, "BOTTOMLEFT", x, 0)
                    bottom:Hide()
                else
                    top:SetHeight(tall)
                    bottom:SetColorTexture(colour[1], colour[2], colour[3], colour[4])
                    bottom:SetWidth(drawn)
                    bottom:SetHeight(tall)
                    bottom:ClearAllPoints()
                    bottom:SetPoint("BOTTOM", bar, "BOTTOMLEFT", x, 0)
                    bottom:Show()
                end
            end
        end
    end
    for i = shown + 1, #marks do
        marks[i].top:Hide()
        marks[i].bottom:Hide()
    end
end

local function HideMarks()
    C:Marks(row.bar, NONE)
end

-- Your latency -------------------------------------------------------------------------
-- From pressing a spell (UNIT_SPELLCAST_SENT) to the game starting it, when
-- the game waits for the server: what the zone at its end shows. Otherwise
-- (Forever usually starts a cast as you press it, after a loading screen, or
-- one pressed too long before) the game's own figure, your world latency.
local sent -- when you last pressed a spell
local LAG_LONGEST = 2 -- seconds: a press any longer before its cast isn't its own
local LAG_SHORTEST = .01 -- seconds: any less and the cast started without waiting for the server

local function NetLag()
    if not GetNetStats then return nil end
    local _, _, home, world = GetNetStats()
    local ms = world or home
    if not (Open(ms) and type(ms) == "number" and ms > 0) then return nil end
    return ms / 1000
end

local function ShowLag()
    local lag = cast and cast.lag
    if not lag then return C:Lag(row, nil) end
    C:Lag(row, lag / cast.total, math.floor(lag * 1000 + .5), cast.channel)
end

-- The bar is the time left (full to empty), so the tick k periods in sits as
-- far along as the time left at that moment.
local function PlaceMarks()
    if not (cast and cast.ticks) then return HideMarks() end
    local at = {}
    for k = 1, cast.ticks - 1 do
        at[k] = (cast.finish - (cast.tickStart + k * cast.period)) / cast.total
    end
    C:Marks(row.bar, at)
end

local function Tick()
    local now = GetTime()
    if cast then
        local bar, left = row.bar, math.max(0, cast.finish - now)
        bar:SetValue(cast.channel and left or math.min(cast.total, now - cast.start))
        if cast.batch then
            bar.time:SetText(Clock(left + cast.batch.left * cast.total))
        else
            C:Time(bar.time, left, cast.total)
        end
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
            C:Time(row.bar.time, left, swing.total)
            return
        end
        -- Run out with no new swing yet: full and held, then it fades, so it
        -- never blinks out between shots.
        row.bar:SetValue(swing.total)
        C:Time(row.bar.time, 0, swing.total)
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
    HideMarks()
    C:Lag(row, nil)
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

local function Begin(channel, fresh)
    local previous = cast
    local keep = cast and not cast.channel and not channel and cast.batch
    local name, text, texture, startMS, endMS, id, tradeSkill, spell, _
    if channel then
        name, text, texture, startMS, endMS, _, _, spell = UnitChannelInfo("player")
    else
        name, text, texture, startMS, endMS, tradeSkill, id = UnitCastingInfo("player")
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
    -- A delay keeps the batch's count; only a new cast asks the game again.
    if not channel then
        if fresh then cast.batch = Batch(tradeSkill) else cast.batch = keep or nil end
        if not Open(text) then cast.batch = nil end
    end
    -- A channel's ticks: a pushback (not fresh) keeps the moments its start gave.
    if channel and ns.Get("castTicks") and Open(spell) and CHANNEL_TICKS[spell] then
        local ticks = CHANNEL_TICKS[spell]
        local same = not fresh and previous and previous.channel and previous.spell == spell and previous.ticks
        cast.spell, cast.ticks = spell, ticks
        cast.tickStart = same and previous.tickStart or start
        cast.period = same and previous.period or cast.total / ticks
    end
    drawn = channel and "channel" or "cast"
    C:Look(row, channel)
    row.bar:SetMinMaxValues(0, cast.total)
    row.icon:SetTexture(texture)
    if cast.batch then
        row.bar.name:SetFormattedText("%s %d / %d", text, cast.batch.index, cast.batch.total)
    elseif channel then
        -- A channel's own name: the game's text for one is just "Channeling".
        row.bar.name:SetText(name)
    else
        row.bar.name:SetText(text)
    end
    PlaceMarks()
    -- Its latency, while that's on: timed from your press as it starts; a
    -- delay or pushback keeps what it had.
    local waited = fresh and sent and GetTime() - sent
    if fresh then sent = nil end
    if not ns.Get("castLatency") then
        cast.lag = nil
    elseif fresh then
        -- Forever starts a cast on your screen as you press it, so the time
        -- between is often nothing: then the game's own figure.
        cast.lag = waited and waited >= LAG_SHORTEST and waited < LAG_LONGEST and waited or NetLag()
    elseif previous and previous.channel == channel and previous.lag then
        cast.lag = previous.lag
    else
        cast.lag = NetLag()
    end
    ShowLag()
    row:SetAlpha(1)
    row:SetScript("OnUpdate", Tick)
    Tick()
end

-- Finished: full, then it fades.
local function Done()
    if not cast.channel then row.bar:SetValue(cast.total) end
    cast, fading = nil, GetTime()
    HideMarks()
end

-- Interrupted or failed: full and red, saying so, then it fades.
local function Broken(text)
    local channel, total = cast.channel, cast.total
    cast, fading = nil, GetTime()
    HideMarks()
    C:Lag(row, nil)
    drawn = "broken"
    C:Look(row, channel, true)
    row.bar:SetValue(total)
    row.bar.name:SetText(text)
    row.bar.time:SetText("")
end

local INTERRUPT_TEXT, FAIL_TEXT = INTERRUPTED or "Interrupted", FAILED or "Failed"

function C:Event(event, id, interruptedBy)
    if not row then return end
    -- You pressed a spell: its latency is timed from now.
    if event == "UNIT_SPELLCAST_SENT" then
        sent = GetTime()
        return
    end
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
        Begin(false, event == "UNIT_SPELLCAST_START")
    elseif event == "UNIT_SPELLCAST_CHANNEL_START" or event == "UNIT_SPELLCAST_CHANNEL_UPDATE" then
        Begin(true, event == "UNIT_SPELLCAST_CHANNEL_START")
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
    -- A channel's marks, and the latency zone, as just chosen.
    if cast and cast.ticks then PlaceMarks() end
    ShowLag()
end

function C:Start()
    if self.started then return end
    self.started = true
    row = self:Make(UIParent)
    row:SetAlpha(0)
    -- A channel's tick marks and the latency zone move with the bar's width
    -- (a layout, the display's size).
    row.bar:SetScript("OnSizeChanged", function()
        if not cast then return end
        if cast.ticks then PlaceMarks() end
        ShowLag()
    end)
    local events = CreateFrame("Frame")
    for _, event in ipairs({ "UNIT_SPELLCAST_SENT", "UNIT_SPELLCAST_START", "UNIT_SPELLCAST_STOP", "UNIT_SPELLCAST_FAILED",
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
