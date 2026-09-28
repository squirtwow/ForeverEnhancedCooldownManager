-- Your own cast bar, under Blizzard's Personal Resource Display: a row of
-- your stack (Cooldowns, the display, the cast bar, then Utility and the
-- rest), in the Tracked Bars design and a colour of your choice, with the
-- spell's icon, name and time left. Blizzard's own cast bar is made
-- invisible while it's on, never moved, so Edit Mode still has it. Off (the
-- default) it takes no room and the rows close up, so another addon's cast
-- bar works as before. On, it keeps its room between casts, since the Buffs
-- and Debuffs bars under it can't move in a fight. Should the game ever keep
-- a cast's times secret, Blizzard's own bar shows that cast instead.
local _, ns = ...

local C = {}
ns.CastBar = C

local Style = ns.Style
local GOLD, GREEN, RED = { 1, .7, 0 }, { 0, .8, 0 }, { .85, .15, .1 } -- casting, channelling, broken off
local HOLD, FADE = .4, .3 -- a finished or broken cast stays up this long, then fades
local PAD = 4 -- under the display: the gap Blizzard leaves between its own bars
local ALONE = { x = 0, y = -150, width = 200, height = 0 } -- with no display to go under

local row -- your cast bar, once made
local cast -- the cast on it now: { channel, id, start, finish }
local fading -- when the last cast ended, while it fades

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

function C:Colour()
    return Colour(false)
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
    frame.iconEdge:SetPoint("TOPLEFT", frame.icon, "TOPLEFT", -1, 1)
    frame.iconEdge:SetPoint("BOTTOMRIGHT", frame.icon, "BOTTOMRIGHT", 1, -1)
    frame.iconEdge:SetColorTexture(0, 0, 0, 1)
    local bar = CreateFrame("StatusBar", nil, frame)
    bar:SetStatusBarTexture(Style.FLAT)
    bar:SetMinMaxValues(0, 1)
    bar:SetValue(0)
    local track = bar:CreateTexture(nil, "BACKGROUND")
    track:SetAllPoints()
    track:SetColorTexture(Style.TRACK[1], Style.TRACK[2], Style.TRACK[3], Style.TRACK[4])
    -- A 1px edge round the bar, and Glass's shine over its top half.
    bar.edge = bar:CreateTexture(nil, "BACKGROUND", nil, -8)
    bar.edge:SetPoint("TOPLEFT", -1, 1)
    bar.edge:SetPoint("BOTTOMRIGHT", 1, -1)
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
    -- A soft shadow round the whole cast bar while shadows are on, outside
    -- its own 1px edges (so no extra border).
    frame.decor = Style:Decor(frame, frame, -1)
    return frame
end

-- Sizes and colours a cast bar from your choices: its height, the design,
-- the colour (red once a cast is broken off) and which parts show.
function C:Look(frame, channel, broken)
    local height = ns.Get("castHeight")
    local design, colour = ns.Get("barStyle"), broken and RED or Colour(channel)
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
    Style:ShowDecor(frame.decor, false, ns.Get("iconShadow") ~= "off")
end

-- Casting ------------------------------------------------------------------------------

local function Tick()
    local now = GetTime()
    if cast then
        local bar, left = row.bar, math.max(0, cast.finish - now)
        bar:SetValue(cast.channel and left or math.min(cast.total, now - cast.start))
        bar.time:SetFormattedText("%.1f", left)
    elseif fading then
        local gone = now - fading
        if gone >= HOLD + FADE then
            fading = nil
            row:SetAlpha(0)
            row:SetScript("OnUpdate", nil)
        elseif gone > HOLD then
            row:SetAlpha(1 - (gone - HOLD) / FADE)
        end
    end
end

local function Clear()
    cast, fading = nil, nil
    row:SetAlpha(0)
    row:SetScript("OnUpdate", nil)
end

local function Begin(channel)
    local name, text, texture, startMS, endMS, id, _
    if channel then
        name, text, texture, startMS, endMS = UnitChannelInfo("player")
    else
        name, text, texture, startMS, endMS, _, id = UnitCastingInfo("player")
    end
    if Open(name) and not name then return end
    if not (Open(startMS) and Open(endMS) and Open(id)) then
        Clear()
        Native(true)
        return
    end
    Native(false)
    local start, finish = startMS / 1000, endMS / 1000
    cast, fading = { channel = channel, id = id, start = start, finish = finish, total = math.max(.001, finish - start) }, nil
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
    C:Look(row, channel, true)
    row.bar:SetValue(total)
    row.bar.name:SetText(text)
    row.bar.time:SetText("")
end

local INTERRUPT_TEXT, FAIL_TEXT = INTERRUPTED or "Interrupted", FAILED or "Failed"

function C:Event(event, id, interruptedBy)
    if not (row and ns.Get("castBar")) then return end
    if event == "PLAYER_ENTERING_WORLD" then
        local channelling, casting = UnitChannelInfo("player"), UnitCastingInfo("player")
        if not Open(channelling) or channelling then
            Begin(true)
        elseif not Open(casting) or casting then
            Begin(false)
        else
            Clear()
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

-- Its place ----------------------------------------------------------------------------

-- How much room it takes under the display while it's on.
function C:Room()
    return ns.Get("castBar") and ns.Get("castHeight") or nil
end

-- Puts the bar under the display (and its combo points), as wide as it, and
-- gives back where the next row starts: under the bar, or under the display
-- while the bar is off. With the display switched off it sits where that was.
function C:Under(display)
    local bottom = display.y - display.height / 2
    local height = self:Room()
    if not height then return bottom end
    local pad = display.height > 0 and PAD or 0
    -- The restyle's 1px edges stick out past the display and this bar alike.
    local edge = display.height > 0 and ns.loaded.prdSkin and 1 or 0
    local width = display.width - 2 * edge
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

-- After a choice changes: shown or not (Blizzard's bar back while it's off),
-- restyled, and the rows moved to make room or close up.
function C:Apply()
    if not row then return end
    local on = ns.Get("castBar") == true
    row:SetShown(on)
    if not on then Clear() end
    Native(not on)
    self:Look(row, cast and cast.channel)
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
    events:SetScript("OnEvent", function(_, event, _, id, _, interruptedBy) C:Event(event, id, interruptedBy) end)
    self.row = row
    self:Apply()
end
