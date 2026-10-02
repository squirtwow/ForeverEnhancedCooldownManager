-- Raid Timers: Blizzard's own raid and dungeon timers, restyled to match your
-- bars. Each part has its own switch, off by default:
--   * the pull and start countdown (/countdown, the raid window's Countdown
--     button, a battleground's gates): its bar in the Look page's design,
--     texture and font, and its big numbers gold, white or in the bar's colour;
--   * raid warnings and boss emotes: their font, outline, shadow and colour;
--   * the boss frames' cast bars: the Look page's design in a colour of your
--     choice. EraUI's Classic cast bars style these too: an EraUI that shares
--     them (through the public API at the end of this file) steps back while
--     this part is on; an older one keeps them while its Cast Bars are on and
--     this part waits. Either way the two never style one bar.
-- Looks only. Blizzard still decides what shows, when and where. Its frames
-- get cosmetic setters from hooks that run after its own code, and the
-- addon's own pieces drawn on them. No key is written on them, and nothing
-- is shown, hidden or moved. Blizzard's art that your look replaces is made
-- see-through (alpha 0), as is a boss bar's fill while Edit Mode shows it
-- with no cast, and the countdown's time is moved only into Split's box, and
-- put back after. Sizes: the countdown (its bar and big numbers, never
-- protected) is the one thing of Blizzard's ever scaled; raid warnings and
-- boss emotes take theirs as text, the height Blizzard draws them at times
-- yours. The boss frames and their cast bars keep Blizzard's size. At 100%
-- nothing is sized, and each size is put back exactly when its part goes
-- off or back to 100%. Nothing that can be secret in a fight (the
-- countdown's time, a message's text, a boss's cast) is read.
-- Blizzard's boss timeline and boss warnings aren't in WoW Forever; if they
-- arrive they get a part of their own here.
local _, ns = ...

local R = {}
ns.RaidTimers = R

local Style = ns.Style
local WHITE = { 1, 1, 1 }
R.RED = { 1, 0, 0 } -- Blizzard's countdown bar
R.GOLD, R.GREEN = { 1, .7, 0 }, { 0, .8, 0 } -- a boss casting, channelling (as your own cast bar)
R.LOCKED, R.BROKEN = { .5, .5, .5 }, { .85, .15, .1 } -- a cast that can't be interrupted, one broken off
-- Colours for the text of raid warnings and boss emotes; "class" is your class colour.
R.TEXT_COLOURS = {
    white = { 1, 1, 1 },
    gold = { 1, .82, 0 },
    orange = { 1, .5, .25 },
    red = { 1, .25, .2 },
    purple = { .72, .52, 1 },
}
R.OUTLINES = { none = "", outline = "OUTLINE", thick = "THICKOUTLINE" }

-- Blizzard's own art and fonts, for its look back and for the previews.
local PLAIN_FILL = "Interface\\TargetingFrame\\UI-StatusBar"
local OLD_BORDER = "Interface\\CastingBar\\UI-CastingBar-Border"
local NUMBERS = "Interface\\Timer\\BigTimerNumbers" -- 4 digits across, 256x170 each, on a 1024x512 sheet
local PULL_FONT, WARNING_FONT, BOSS_FONT = "GameFontHighlight", "GameFontNormalHuge", "SystemFont_Shadow_Small"
local PULL_SIZE = 12 -- the countdown's time, as big as Blizzard's
local WARNING_SIZE = 20 -- a raid warning at rest; Blizzard grows it to 30 and back as it arrives
local BOSS_SIZE = 10 -- a boss cast's spell name
local SPLIT_BOX = 40 -- the Split design's time box on the countdown bar
local PULL_NUMBER_Y = 49 -- the preview's big number: its middle, this far under the top (8 under the bar at 100%)
local BOSSES = 5
local DIGITS = { "digit1", "digit2", "glow1", "glow2" } -- the countdown's big numbers and their glow

local pulls = setmetatable({}, { __mode = "k" }) -- Blizzard's countdown frames restyled, and the pieces added
local scaled = setmetatable({}, { __mode = "k" }) -- countdown pieces (and previews) at a scale of yours: that scale
local warnings = setmetatable({}, { __mode = "k" }) -- raid warning lines restyled: true, or "tinted" while in your colour
local given = setmetatable({}, { __mode = "k" }) -- the colour Blizzard gave each of those lines for its message
local heights = setmetatable({}, { __mode = "k" }) -- those lines drawn at a size of yours: that size
local bouncing = setmetatable({}, { __mode = "k" }) -- those lines Blizzard was growing or shrinking last frame
local bosses = setmetatable({}, { __mode = "k" }) -- boss cast bars restyled, and the pieces added
local samples = setmetatable({}, { __mode = "k" }) -- the window's previews, and their pieces
local hooked = { bars = {} }
R.pulls, R.warnings, R.bosses = pulls, warnings, bosses

-- A failure is reported once per session, never thrown into Blizzard's code.
local function Safe(what, fn, ...)
    local ok, err = pcall(fn, ...)
    if not ok and not R.lastError then
        R.lastError = tostring(err)
        print("|cffffd100" .. ns.TITLE .. ":|r couldn't restyle " .. what .. ". Please report this: " .. R.lastError)
    end
end

local function Secret(value)
    return issecretvalue ~= nil and issecretvalue(value) == true
end

-- A plain number of Blizzard's, never a secret one.
local function Number(value)
    return not Secret(value) and type(value) == "number"
end

-- Fits region to anchor, out pixels past its edge all round.
local function Around(region, anchor, out)
    region:ClearAllPoints()
    region:SetPoint("TOPLEFT", anchor, "TOPLEFT", -out, out)
    region:SetPoint("BOTTOMRIGHT", anchor, "BOTTOMRIGHT", out, -out)
end

local function Solid(texture, colour, alpha)
    texture:SetColorTexture(colour[1], colour[2], colour[3], alpha or 1)
end

-- Puts text in a font file, or in Friz Quadrata should the game refuse it.
local function Face(region, file, size, flags)
    if file ~= Style.FONTS.friz then
        local ok, done = pcall(region.SetFont, region, file, size, flags)
        if ok and done ~= false then return end
    end
    region:SetFont(Style.FONTS.friz, size, flags)
end

-- The pieces every design uses, made once on a bar: a 1px edge and the dark
-- track under its fill, Glass's shine, and Split's box at the end.
local function Pieces(bar, box)
    local parts = {}
    parts.edge = bar:CreateTexture(nil, "BACKGROUND", nil, -8)
    Around(parts.edge, bar, 1)
    parts.track = bar:CreateTexture(nil, "BACKGROUND", nil, -7)
    Around(parts.track, bar, 0)
    Solid(parts.track, Style.TRACK, Style.TRACK[4])
    parts.sheen = bar:CreateTexture(nil, "OVERLAY", nil, -8)
    parts.sheen:SetPoint("TOPLEFT", bar, "TOPLEFT", 0, 0)
    parts.sheen:SetPoint("BOTTOMRIGHT", bar, "RIGHT", 0, 0)
    parts.sheen:SetColorTexture(1, 1, 1, .16)
    if box then
        parts.box = bar:CreateTexture(nil, "OVERLAY", nil, -7)
        parts.box:SetPoint("TOPRIGHT", bar, "TOPRIGHT", 0, 0)
        parts.box:SetPoint("BOTTOMRIGHT", bar, "BOTTOMRIGHT", 0, 0)
        parts.box:SetWidth(box)
        parts.box:SetColorTexture(.024, .027, .031, 1)
        parts.divider = bar:CreateTexture(nil, "OVERLAY", nil, -6)
        parts.divider:SetPoint("TOPRIGHT", parts.box, "TOPLEFT", 0, 0)
        parts.divider:SetPoint("BOTTOMRIGHT", parts.box, "BOTTOMLEFT", 0, 0)
        parts.divider:SetWidth(2)
        parts.divider:SetColorTexture(0, 0, 0, 1)
    end
    return parts
end

local function ShowPieces(parts, shown, design)
    parts.edge:SetShown(shown)
    parts.track:SetShown(shown)
    parts.sheen:SetShown(shown and design == "glass")
    if parts.box then
        parts.box:SetShown(shown and design == "split")
        parts.divider:SetShown(shown and design == "split")
    end
end

-- The fill's texture, set only when it changes.
local function Fill(bar, parts, texture)
    if parts.texture == texture then return end
    parts.texture = texture
    bar:SetStatusBarTexture(texture)
end

-- Your bar design on a bar: the texture and colour, see-through inside an
-- edge in its colour for Outline, a black edge otherwise.
local function Design(bar, parts, colour)
    local design = ns.Get("barStyle")
    local outline = design == "outline"
    Fill(bar, parts, Style:BarTexture())
    bar:SetStatusBarColor(colour[1], colour[2], colour[3], outline and .45 or 1)
    Solid(parts.edge, outline and colour or { 0, 0, 0 })
    ShowPieces(parts, true, design)
    return design
end

-- Sizes ---------------------------------------------------------------------------------

-- A part's size times Size (all of them), as a scale: 1 is Blizzard's own.
function R:Scale(key)
    return ns.Get(key) * ns.Get("raidSize") / 10000
end

-- Whether a frame can't be scaled now: one the game protects, in a fight.
-- The countdown's never are; should that change, the size waits.
local function Locked(region)
    if not (InCombatLockdown and InCombatLockdown()) then return false end
    if type(region.IsProtected) ~= "function" then return true end
    local ok, protected = pcall(region.IsProtected, region)
    return not ok or Secret(protected) or protected ~= false
end

-- A countdown piece at a scale: set only off 1, and 1 put back after (Blizzard
-- never scales them, so 1 is its own). Nothing is called while it's already so.
local function Resize(region, scale)
    if not region or (scaled[region] or 1) == scale or Locked(region) then return end
    region:SetScale(scale)
    scaled[region] = scale ~= 1 and scale or nil
end

-- Colours ------------------------------------------------------------------------------

-- The countdown bar's colour: yours, or Blizzard's red.
function R:PullColour()
    local key = ns.Get("pullColour")
    if key ~= "default" then return Style:BarColour(key) end
    return R.RED
end

-- A text colour by its key; "class" is your class colour.
function R:TextColour(key)
    if key == "class" then return Style:BarColour("class") end
    return R.TEXT_COLOURS[key] or WHITE
end

-- A boss cast's colour by what kind it is, when the game lets that be seen:
-- red once broken off, grey when it can't be interrupted, else yours, or
-- gold (green channelling). A cast the game keeps secret takes yours, or gold;
-- Blizzard's shield still marks one that can't be interrupted.
function R:BossColour(kind)
    if kind == "broken" then return R.BROKEN end
    if kind == "locked" then return R.LOCKED end
    local key = ns.Get("bossColour")
    if key ~= "default" then return Style:BarColour(key) end
    return kind == "channel" and R.GREEN or R.GOLD
end

-- Pull and start countdown ------------------------------------------------------------
-- Blizzard's StartTimerBar: a 195x13 red bar with the old cast bar border and
-- its time ("0:42") while there's more than half a minute to go (10 seconds
-- for a battleground's gates), then big gold numbers that pop in each second.
-- Each frame is made on demand and reused; the restyle goes on after
-- Blizzard has set it up for each new countdown.

-- Blizzard's own black backing (the one texture under the fill) and its old
-- border (named after the bar), found once.
local function PullParts(timer, border, backing)
    local bar = timer.bar
    if not border then
        local name = bar:GetName()
        border = type(name) == "string" and _G[name .. "Border"] or nil
    end
    if not backing then
        local fill = bar:GetStatusBarTexture()
        for _, region in ipairs({ bar:GetRegions() }) do
            if region ~= fill and region:GetObjectType() == "Texture" and region:GetDrawLayer() == "BACKGROUND" then
                backing = region
            end
        end
    end
    local parts = Pieces(bar, SPLIT_BOX)
    parts.border, parts.backing = border, backing
    return parts
end

-- The big numbers and their glow: Blizzard's gold, or made grey and tinted
-- white or in the bar's colour.
local function Numbers(timer, how, colour)
    local tint = how == "bar" and colour or WHITE
    for _, key in ipairs(DIGITS) do
        local digit = timer[key]
        if digit then
            digit:SetDesaturated(how ~= "gold")
            digit:SetVertexColor(tint[1], tint[2], tint[3])
        end
    end
end

-- The time on the bar: in your font, as big as Blizzard's; centred, or in
-- Split's box. Its anchor is only touched for Split, and put back after.
local function PullText(bar, parts, design)
    local text = bar.timeText
    if not text then return end
    text:SetFontObject(Style:Font(PULL_SIZE))
    if design == "split" then
        text:ClearAllPoints()
        text:SetPoint("CENTER", parts.box, "CENTER", 0, 0)
        parts.moved = true
    elseif parts.moved then
        text:ClearAllPoints()
        text:SetPoint("CENTER", bar, "CENTER", 0, 0)
        parts.moved = nil
    end
end

local function PullLook(timer, parts, on)
    local bar = timer.bar
    if not on then
        -- Blizzard's own look: its fill, backing, border, font and gold numbers.
        Fill(bar, parts, PLAIN_FILL)
        bar:SetStatusBarColor(R.RED[1], R.RED[2], R.RED[3], 1)
        if parts.border then parts.border:SetAlpha(1) end
        if parts.backing then parts.backing:SetAlpha(1) end
        ShowPieces(parts, false)
        if bar.timeText then
            bar.timeText:SetFontObject(PULL_FONT)
            if parts.moved then
                bar.timeText:ClearAllPoints()
                bar.timeText:SetPoint("CENTER", bar, "CENTER", 0, 0)
                parts.moved = nil
            end
        end
        Numbers(timer, "gold")
        return
    end
    local colour = R:PullColour()
    local design = Design(bar, parts, colour)
    if parts.border then parts.border:SetAlpha(0) end
    if parts.backing then parts.backing:SetAlpha(0) end
    PullText(bar, parts, design)
    Numbers(timer, ns.Get("pullNumbers"), colour)
end

-- Its sizes, the one exception to never scaling Blizzard's frames (approved
-- for the countdown only): a scale on the bar and on each big digit, 1 when
-- off. Blizzard never scales them and never reads their size: the bar hangs
-- from the top of its timer frame, so it grows from its top centre, and the
-- digits are laid out from widths Blizzard keeps itself, round the frame's
-- centre (from 30 seconds) or the screen's (the last 10), so the numbers grow
-- round their centre. The glow is pinned to its digit's corners and follows.
local function PullSize(timer, on)
    Resize(timer.bar, on and R:Scale("pullBarSize") or 1)
    local numbers = on and R:Scale("pullNumberSize") or 1
    Resize(timer.digit1, numbers)
    Resize(timer.digit2, numbers)
end

-- Every countdown frame Blizzard has made, restyled (made the first time).
local function RestylePulls()
    local tracker = _G.TimerTracker
    local list = tracker and tracker.timerList
    if type(list) ~= "table" then return end
    local on = ns.Get("pullTimer")
    for _, timer in ipairs(list) do
        if type(timer) == "table" and timer.bar then
            if on and not pulls[timer] then pulls[timer] = PullParts(timer) end
            if pulls[timer] then
                PullLook(timer, pulls[timer], on)
                PullSize(timer, on)
            end
        end
    end
end

function R:ApplyPull()
    if ns.Get("pullTimer") and not hooked.pull and type(_G.TimerTracker_StartTimerOfType) == "function" then
        hooked.pull = true
        -- Runs after Blizzard sets each countdown up (or makes its frame), so the
        -- numbers it sets again for every countdown take the tint each time.
        hooksecurefunc("TimerTracker_StartTimerOfType", function() Safe("the pull countdown", RestylePulls) end)
    end
    Safe("the pull countdown", RestylePulls)
end

-- Raid warnings and boss emotes --------------------------------------------------------
-- Blizzard's RaidWarningFrame shows both, top centre, each a pooled line of
-- text. After it adds a message, every line showing is dressed: the font,
-- outline and shadow, and a colour when one is chosen, for raid warnings and
-- boss emotes apart. The colour Blizzard gave each message is kept, to put
-- back on lines still showing when its colour is chosen again or the part is
-- switched off. Their text is never read, and their place and fading stay
-- Blizzard's. Their size is text too: Blizzard draws each line 20 high,
-- growing a new one to 30 and back over its first moments, so the font alone
-- can't size it; with a size of yours each line is drawn at Blizzard's
-- height times yours, set again each time Blizzard sets it.

local function EmoteType()
    local util = _G.RaidWarningUtil
    local types = util and util.MessageType
    return types and types.BossEmote or 2
end

-- { r, g, b } from one of Blizzard's colours, when it can be read.
local function RGB(info)
    if type(info) ~= "table" then return nil end
    local r, g, b = info.r, info.g, info.b
    if Secret(r) or Secret(g) or Secret(b) then return nil end
    if type(r) ~= "number" or type(g) ~= "number" or type(b) ~= "number" then return nil end
    return { r, g, b }
end

-- The colour Blizzard gave a line: the one it added the message in, or else
-- its usual one for raid warnings or boss emotes.
local function GivenColour(line, emote)
    if given[line] then return given[line] end
    local info = _G.ChatTypeInfo
    return type(info) == "table" and RGB(info[emote and "RAID_BOSS_EMOTE" or "RAID_WARNING"]) or nil
end

-- Your font, outline and shadow on a line, in its kind's size, and your
-- colour for its kind. With Blizzard's colour chosen, plain goes back on it
-- (when given). Says whether the line is now in a colour of yours, and its size.
local function DressWarning(line, emote, plain)
    local scale = R:Scale(emote and "emoteSize" or "warningSize")
    Face(line, Style.FONTS[ns.Get("warningFont")] or Style.FONTS.friz, math.floor(WARNING_SIZE * scale + .5),
        R.OUTLINES[ns.Get("warningOutline")] or "OUTLINE")
    if ns.Get("warningShadow") then
        line:SetShadowOffset(1, -1)
        line:SetShadowColor(0, 0, 0, 1)
    else
        line:SetShadowOffset(0, 0)
    end
    local key = ns.Get(emote and "emoteColour" or "warningColour")
    local colour = key ~= "default" and R:TextColour(key) or plain
    if colour then line:SetTextColor(colour[1], colour[2], colour[3], 1) end
    return key ~= "default", scale
end

-- Whether a line is a boss emote or whisper: the kind Blizzard gave it.
local function IsEmote(line)
    local kind = line.messageType
    return not Secret(kind) and kind == EmoteType()
end

-- The height Blizzard draws a line at now: each new message grows from 20 to
-- 30 and back over its first moments (FadingFrame_UpdateTextScaling, every
-- frame), then stays at 20. Worked out from the timings Blizzard keeps on
-- the line, read only, as it works them out; nil when they can't be read.
local function DrawnHeight(line)
    local low, high = line.textScalingMinHeight, line.textScalingMaxHeight
    local up, down, now = line.textScalingUpTime, line.textScalingDownTime, line.textScalingTime
    if not Number(low) then return nil end
    if now == nil then return low end
    if not (Number(now) and Number(high) and Number(up) and Number(down)) or up <= 0 then return nil end
    if now <= up then return math.floor(low + (high - low) * now / up) end
    if now <= down then return math.floor(high - (high - low) * (now - up) / (down - up)) end
    return low
end

-- A line in your size: Blizzard's height for it now, times yours. Nothing at
-- 100% on a line never sized; Blizzard's height back on one that was.
local function Height(line, scale)
    if scale == 1 and not heights[line] then return end
    local height = DrawnHeight(line)
    if not height then return end
    line:SetTextHeight(height * scale)
    heights[line] = scale ~= 1 and scale or nil
end

-- After Blizzard grows or shrinks a line, and once more as it stops: the
-- same height in your size. Lines at rest are left alone.
local function Bounced(line)
    if not warnings[line] or not ns.Get("raidWarnings") then return end
    local now = line.textScalingTime
    if Secret(now) then return end
    local was = bouncing[line]
    bouncing[line] = now ~= nil or nil
    if now ~= nil or was then Height(line, R:Scale(IsEmote(line) and "emoteSize" or "warningSize")) end
end

-- Blizzard's own font and shadow back, from its font for these lines, and
-- its colour on a line that was in yours.
local function PlainWarning(line, tinted)
    local font = _G[WARNING_FONT]
    local file, size, flags = Style.FONTS.friz, WARNING_SIZE, ""
    if font and font.GetFont then
        local f, s, fl = font:GetFont()
        file, size, flags = f or file, s or size, fl or flags
    end
    line:SetFont(file, size, flags)
    local x, y = 1, -1
    if font and font.GetShadowOffset then x, y = font:GetShadowOffset() end
    line:SetShadowOffset(x or 1, y or -1)
    line:SetShadowColor(0, 0, 0, 1)
    local colour = tinted and GivenColour(line, IsEmote(line))
    if colour then line:SetTextColor(colour[1], colour[2], colour[3], 1) end
    Height(line, 1)
end

-- After Blizzard adds a message (frame and its colour), or a choice changes.
local function RestyleWarnings(frame, colorInfo)
    frame = frame or _G.RaidWarningFrame
    local pool = frame and frame.fontStringPool
    if not (pool and pool.EnumerateActive) then return end
    if not ns.Get("raidWarnings") then return end
    -- The line just added is the newest: its colour is kept.
    local newest = colorInfo and frame.messageCounter
    if type(newest) ~= "number" then newest = nil end
    for line in pool:EnumerateActive() do
        if newest and line.messageOrder == newest then given[line] = RGB(colorInfo) end
        local emote = IsEmote(line)
        local tinted, scale = DressWarning(line, emote, warnings[line] == "tinted" and GivenColour(line, emote) or nil)
        warnings[line] = tinted and "tinted" or true
        Height(line, scale)
    end
end

function R:ApplyWarnings()
    local frame = _G.RaidWarningFrame
    if ns.Get("raidWarnings") then
        if not hooked.warnings and frame and type(frame.AddMessage) == "function" then
            hooked.warnings = true
            hooksecurefunc(frame, "AddMessage", function(added, _, colorInfo)
                Safe("a raid warning", RestyleWarnings, added, colorInfo)
            end)
        end
        -- Only once a text size isn't 100%: Blizzard growing and shrinking each line.
        local sized = self:Scale("warningSize") ~= 1 or self:Scale("emoteSize") ~= 1
        if sized and not hooked.fading and type(_G.FadingFrame_UpdateTextScaling) == "function" then
            hooked.fading = true
            hooksecurefunc("FadingFrame_UpdateTextScaling", function(line) Safe("a raid warning", Bounced, line) end)
        end
        Safe("a raid warning", RestyleWarnings)
        return
    end
    -- Off: every line dressed so far goes back to Blizzard's font, colour and
    -- height, shown or not, as the pool hands lines out again as they are.
    for line, state in pairs(warnings) do
        Safe("a raid warning", PlainWarning, line, state == "tinted")
        warnings[line], given[line], bouncing[line] = nil, nil, nil
    end
end

-- Boss cast bars -------------------------------------------------------------------------
-- Blizzard's Boss1-5 spell bars (120x10, the spell's name under them). Its
-- modern frame, backing and name box go; your design, a dark track and the
-- edge come in, the name in your font, the icon zoomed past its bevel. The
-- fill is set again after Blizzard picks it for each cast. Blizzard's shield
-- (a cast that can't be interrupted) and finish flash stay. In Edit Mode
-- (Boss Frames ticked) the bars show empty in your design: see Idle.

-- EraUI's Classic cast bars style these too, and the two must never style one
-- bar. A current EraUI shares them: it says so through the public API at the
-- end of this file, steps back while this part styles them, and hears each
-- time they change hands, so this part's switch decides. An older EraUI keeps
-- them while its Cast Bars are on (its default, read from its own settings as
-- it reads them, and assumed when they can't be read); this part waits.
local sharing = {} -- addons that step back from the boss bars while this part styles them, and what to tell each

function R:BossOwner()
    if sharing.EraUI then return nil end
    local loaded = C_AddOns and C_AddOns.IsAddOnLoaded and C_AddOns.IsAddOnLoaded("EraUI")
    if not loaded then return nil end
    local era = _G.EraUI
    if type(era) ~= "table" or type(era.GetSetting) ~= "function" then return "EraUI" end
    local ok, enabled = pcall(era.GetSetting, era, "enabled")
    if ok and not enabled then return nil end
    local read, castBars = pcall(era.GetSetting, era, "castBars")
    if read and castBars == false then return nil end
    return "EraUI"
end

-- Whether an addon shares the boss bars (and so steps back while this is on).
function R:SharedBy(addon)
    return sharing[addon] ~= nil
end

-- Whether this part styles the boss bars: ticked, and not left to EraUI.
function R:StylesBoss()
    return ns.Get("bossCasts") == true and not self:BossOwner()
end

-- Each addon that shares the bars hears when that changes; its trouble is its own.
local function Tell()
    for _, heard in pairs(sharing) do pcall(heard) end
end

-- What kind of cast Blizzard just drew, from the fill it picked; nil when
-- the game keeps it secret.
local function Kind(bar)
    local fill = bar:GetStatusBarTexture()
    local atlas = fill and fill.GetAtlas and fill:GetAtlas()
    if Secret(atlas) or type(atlas) ~= "string" then return nil end
    atlas = atlas:lower()
    if atlas:find("interrupted", 1, true) then return "broken" end
    if atlas:find("uninterrupt", 1, true) then return "locked" end
    if atlas:find("channel", 1, true) then return "channel" end
    return "cast"
end

local function BossParts(bar)
    local parts = Pieces(bar)
    if bar.Icon then
        Style:Zoom(bar.Icon)
        parts.zoomed = true
    end
    return parts
end

local function BossLook(bar, parts, on)
    local design = ns.Get("barStyle")
    for _, key in ipairs({ "Border", "Background", "TextBorder" }) do
        if bar[key] then bar[key]:SetAlpha(on and 0 or 1) end
    end
    -- Only Glass keeps Blizzard's spark where the fill ends.
    if bar.Spark then bar.Spark:SetAlpha((not on or design == "glass") and 1 or 0) end
    if bar.Text then bar.Text:SetFontObject(on and Style:Font(BOSS_SIZE) or BOSS_FONT) end
    if bar.Icon then
        if on and not parts.zoomed then
            Style:Zoom(bar.Icon)
            parts.zoomed = true
        elseif not on and parts.zoomed then
            bar.Icon:SetTexCoord(0, 1, 0, 1)
            parts.zoomed = nil
        end
    end
    if on then
        Design(bar, parts, R:BossColour(parts.kind))
    else
        -- The fill goes back to Blizzard's as it picks one for the next cast.
        parts.texture = nil
        ShowPieces(parts, false)
    end
end

-- Edit Mode's Boss Frames shows the bars as Blizzard left them: full (after
-- the last cast, or with none at all), with no name or icon, so the fill
-- hides the track and only a coloured line shows. While Edit Mode shows a
-- bar that isn't casting, its fill is made see-through, so the bar shows
-- empty in your design; every cast shows it again. Only Edit Mode's switch
-- and whether the bar is casting are read, as Blizzard sets them.
local function Idle(bar)
    local box = _G.BossTargetFrameContainer
    local editing = box and box.isInEditMode
    local casting, channeling = bar.casting, bar.channeling
    if Secret(editing) or Secret(casting) or Secret(channeling) then return false end
    return editing == true and not casting and not channeling
end

local function FillShown(bar, shown)
    local fill = bar:GetStatusBarTexture()
    if fill then fill:SetAlpha(shown and 1 or 0) end
end

-- After Blizzard picks a cast's fill: yours, in the colour for its kind,
-- and the rest of the look again, should the Look page have changed. The
-- fill shows for a cast (Blizzard picks it before it marks the bar casting,
-- and fills it as a cast ends while still marked); a full fill on a bar with
-- no cast (as on a loading screen) stays see-through in Edit Mode.
local function BossFilled(bar, isFull)
    local parts = bosses[bar]
    if not (parts and R.bossOn) then return end
    parts.kind = Kind(bar)
    parts.texture = nil -- Blizzard just set its own
    BossLook(bar, parts, true)
    local full = not Secret(isFull) and isFull == true
    FillShown(bar, not (full and Idle(bar)))
end

-- After Blizzard shows or hides the boss frames: Boss Frames ticked or
-- unticked in Edit Mode, Edit Mode closed, a boss arriving.
local function BossFramesShown()
    if not R.bossOn then return end
    for bar in pairs(bosses) do FillShown(bar, not Idle(bar)) end
end

function R:BossBars()
    local list = {}
    for i = 1, BOSSES do
        local bar = _G["Boss" .. i .. "TargetFrameSpellBar"]
        if not bar then
            local frame = _G["Boss" .. i .. "TargetFrame"]
            bar = frame and frame.spellbar
        end
        if bar then list[#list + 1] = bar end
    end
    return list
end

function R:ApplyBoss()
    local on = self:StylesBoss()
    -- Not this part's, and nothing of it on them: left alone (EraUI's, or Blizzard's).
    if not on and not self.bossOn then return end
    -- Taking the bars: the addons that share them hear first, so their look
    -- is put away before this one goes on.
    if on and not self.bossOn then
        self.bossOn = true
        Tell()
    end
    local box = _G.BossTargetFrameContainer
    if on and not hooked.box and box and type(box.UpdateShownState) == "function" then
        hooked.box = true
        hooksecurefunc(box, "UpdateShownState", function() Safe("a boss cast bar", BossFramesShown) end)
    end
    for _, bar in ipairs(self:BossBars()) do
        if on and not hooked.bars[bar] and type(bar.UpdateBarFillTexture) == "function" then
            hooked.bars[bar] = true
            hooksecurefunc(bar, "UpdateBarFillTexture", function(self, isFull)
                Safe("a boss cast bar", BossFilled, self, isFull)
            end)
        end
        if on and not bosses[bar] then bosses[bar] = BossParts(bar) end
        if bosses[bar] then
            Safe("a boss cast bar", BossLook, bar, bosses[bar], on)
            -- Off, Blizzard's fill as it was; on, see-through while Edit Mode shows the bar idle.
            Safe("a boss cast bar", FillShown, bar, not (on and Idle(bar)))
        end
    end
    -- Giving them back: Blizzard's look is back on first, then they hear.
    if not on and self.bossOn then
        self.bossOn = false
        Tell()
    end
end

-- The window's previews ---------------------------------------------------------------
-- The addon's own frames in the shape of Blizzard's, in its art, dressed by
-- the same code, so they show exactly what each part does. Nothing here
-- runs Blizzard's own timers, messages or casts.

-- A countdown: the bar with its time, and one big number.
function R:SamplePull(parent)
    local timer = CreateFrame("Frame", nil, parent)
    timer:SetSize(206, 70)
    local bar = CreateFrame("StatusBar", nil, timer)
    bar:SetSize(195, 13)
    bar:SetPoint("TOP", timer, "TOP", 0, -12)
    bar:SetStatusBarTexture(PLAIN_FILL)
    bar:SetStatusBarColor(R.RED[1], R.RED[2], R.RED[3])
    bar:SetMinMaxValues(0, 1)
    bar:SetValue(.6)
    local backing = bar:CreateTexture(nil, "BACKGROUND")
    backing:SetAllPoints()
    backing:SetColorTexture(0, 0, 0, .5)
    local border = bar:CreateTexture(nil, "OVERLAY")
    border:SetTexture(OLD_BORDER)
    border:SetSize(256, 64)
    border:SetPoint("TOP", bar, "TOP", 0, 25)
    bar.timeText = bar:CreateFontString(nil, "OVERLAY", PULL_FONT)
    bar.timeText:SetPoint("CENTER", bar, "CENTER", 0, 0)
    bar.timeText:SetText("0:42")
    timer.bar = bar
    -- The big number centred on a spot of its own under the bar, as the game
    -- centres its numbers on the timer: it grows round its middle, and the
    -- bar's size never moves it. Drawn over the bar, so a big bar never
    -- hides it (in the game the bar has faded by the time they show).
    local spot = CreateFrame("Frame", nil, timer)
    spot:SetSize(1, 1)
    spot:SetPoint("CENTER", timer, "TOP", 0, -PULL_NUMBER_Y)
    spot:SetFrameLevel(bar:GetFrameLevel() + 1)
    timer.spot = spot
    timer.digit1 = spot:CreateTexture(nil, "OVERLAY")
    timer.digit1:SetTexture(NUMBERS)
    timer.digit1:SetSize(48, 32)
    timer.digit1:SetPoint("CENTER", spot, "CENTER", 0, 0)
    self:SampleNumber(timer, 5)
    samples[timer] = PullParts(timer, border, backing)
    self:SampleLook(timer)
    return timer
end

-- Shows the number n (0 to 9) on a preview countdown, from Blizzard's sheet.
function R:SampleNumber(timer, n)
    local w, h = 256 / 1024, 170 / 512
    local left, top = (n % 4) * w, math.floor(n / 4) * h
    timer.digit1:SetTexCoord(left, left + w, top, top + h)
end

-- Two lines like Blizzard's: a raid warning and a boss emote, each in
-- Blizzard's colour for it, the second under the first as Blizzard stacks
-- them, so each shows its size.
function R:SampleWarnings(parent)
    local frame = CreateFrame("Frame", nil, parent)
    frame:SetSize(210, 60)
    local info = _G.ChatTypeInfo or {}
    local lines = {}
    for i, sample in ipairs({
        { text = "Raid warning", colour = info.RAID_WARNING or { r = 1, g = .282, b = 0 } },
        { text = "Boss emote", colour = info.RAID_BOSS_EMOTE or { r = 1, g = .867, b = 0 }, emote = true },
    }) do
        local line = frame:CreateFontString(nil, "ARTWORK", WARNING_FONT)
        if i == 1 then
            line:SetPoint("TOP", frame, "TOP", 0, 0)
        else
            line:SetPoint("TOP", lines[i - 1], "BOTTOM", 0, -10)
        end
        line:SetWidth(210)
        line:SetJustifyH("CENTER")
        line:SetText(sample.text)
        line.blizzard = { sample.colour.r, sample.colour.g, sample.colour.b }
        line.emote = sample.emote
        lines[i] = line
    end
    frame.lines = lines
    samples[frame] = true
    self:SampleLook(frame)
    return frame
end

-- A boss cast bar: the modern art Blizzard gives it, then the name under it.
function R:SampleBoss(parent)
    local frame = CreateFrame("Frame", nil, parent)
    frame:SetSize(146, 34)
    local bar = CreateFrame("StatusBar", nil, frame)
    bar:SetSize(120, 10)
    bar:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -2, -4)
    bar:SetMinMaxValues(0, 1)
    bar:SetValue(.5)
    bar.TextBorder = bar:CreateTexture(nil, "BACKGROUND")
    bar.TextBorder:SetAtlas("ui-castingbar-textbox")
    bar.TextBorder:SetPoint("TOPLEFT", bar, "TOPLEFT", 0, 0)
    bar.TextBorder:SetPoint("BOTTOMRIGHT", bar, "BOTTOMRIGHT", 0, -12)
    bar.Background = bar:CreateTexture(nil, "BACKGROUND")
    bar.Background:SetAtlas("ui-castingbar-background")
    bar.Background:SetAllPoints()
    bar.Icon = bar:CreateTexture(nil, "ARTWORK")
    bar.Icon:SetSize(20, 20)
    bar.Icon:SetPoint("RIGHT", bar, "LEFT", -2, -5)
    bar.Icon:SetTexture("Interface\\Icons\\Spell_Frost_FrostBolt02")
    bar.Border = bar:CreateTexture(nil, "OVERLAY")
    bar.Border:SetAtlas("ui-castingbar-frame")
    bar.Border:SetPoint("TOPLEFT", bar, "TOPLEFT", -1, 2)
    bar.Border:SetPoint("BOTTOMRIGHT", bar, "BOTTOMRIGHT", 1, -2)
    bar.Spark = bar:CreateTexture(nil, "OVERLAY")
    bar.Spark:SetAtlas("ui-castingbar-pip")
    bar.Spark:SetSize(6, 16)
    bar.Text = bar:CreateFontString(nil, "OVERLAY", BOSS_FONT)
    bar.Text:SetPoint("TOPLEFT", bar, "TOPLEFT", 0, -8)
    bar.Text:SetPoint("TOPRIGHT", bar, "TOPRIGHT", 0, -8)
    bar.Text:SetHeight(16)
    bar.Text:SetText("Frostbolt Volley")
    frame.bar = bar
    samples[frame] = BossParts(bar)
    samples[frame].kind = "cast"
    self:SampleLook(frame)
    return frame
end

-- A preview in your current choices: always restyled, so you can see it
-- before ticking it on.
function R:SampleLook(sample)
    local parts = samples[sample]
    if not parts then return end
    if sample.lines then
        for _, line in ipairs(sample.lines) do DressWarning(line, line.emote, line.blizzard) end
    elseif sample.digit1 then
        PullLook(sample, parts, true)
        PullSize(sample, true)
    else
        BossLook(sample.bar, parts, true)
        -- The spark where the fill ends, as Blizzard's does.
        local bar = sample.bar
        if bar.Spark then
            bar.Spark:ClearAllPoints()
            bar.Spark:SetPoint("CENTER", bar:GetStatusBarTexture() or bar, "RIGHT", 0, 0)
        end
    end
end

-- Setup ------------------------------------------------------------------------------

-- After a choice changes: each part on, restyled, or Blizzard's own look back.
function R:Apply()
    self:ApplyPull()
    self:ApplyWarnings()
    self:ApplyBoss()
end

function R:Start()
    if self.started then return end
    self.started = true
    -- Once every addon has loaded, so EraUI's choice is known; and again
    -- should Blizzard load its raid warnings late.
    local watcher = CreateFrame("Frame")
    watcher:RegisterEvent("PLAYER_LOGIN")
    watcher:RegisterEvent("ADDON_LOADED")
    watcher:SetScript("OnEvent", function(_, event, name)
        if event == "PLAYER_LOGIN" then
            self.ready = true
            self:Apply()
        elseif self.ready and name == "Blizzard_RaidWarning" then
            self:ApplyWarnings()
        end
    end)
    if IsLoggedIn and IsLoggedIn() then
        self.ready = true
        self:Apply()
    end
end

-- The public API ------------------------------------------------------------------------
-- For other addons, read-only: whether this addon styles Blizzard's boss cast
-- bars, and a way for an addon that styles them too to step back while it
-- does (EraUI's Classic cast bars use it).
--   ForeverEnhancedCooldownManagerAPI.version                1
--   ForeverEnhancedCooldownManagerAPI.StylesBossCastBars()   true while this addon styles the
--       boss cast bars (the Raid Timers page's part is on, and they're its to style), else false
--   ForeverEnhancedCooldownManagerAPI.ShareBossCastBars(addon, callback)
--       addon (its folder name) steps back from the boss cast bars while
--       StylesBossCastBars() is true; callback() runs after each change of
--       that answer: when taking them, before this addon's look goes on;
--       when handing them back, after Blizzard's look is back. Returns true
--       once registered. The first callback under a name holds it: another
--       under the same name is refused (false), the same one again is fine.
local api = { version = 1 }

-- What this addon does now, not what it's about to: the answer only changes
-- inside ApplyBoss, just before the callbacks.
function api.StylesBossCastBars()
    return R.bossOn == true
end

function api.ShareBossCastBars(addon, callback)
    if type(addon) ~= "string" or addon == "" or type(callback) ~= "function" then return false end
    -- Taken already: nobody else can speak for that addon or cut it off.
    if sharing[addon] ~= nil then return sharing[addon] == callback end
    sharing[addon] = callback
    -- After login the bars may change hands at once (EraUI's waited for it till now).
    if R.ready then Safe("a boss cast bar", R.ApplyBoss, R) end
    return true
end

ForeverEnhancedCooldownManagerAPI = setmetatable({}, {
    __index = api,
    __newindex = function() error("ForeverEnhancedCooldownManagerAPI is read-only", 2) end,
    __metatable = false,
})
