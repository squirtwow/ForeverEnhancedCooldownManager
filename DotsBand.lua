-- The DoTs band: the damage your spells still have to deal, marked on your
-- target's health bar from the right end of its health leftwards, with a
-- bright line at the band's left edge and a skull on the portrait once the
-- band covers the rest of the health. Dots.lua does the work; this file
-- draws it.
--
-- Every line in the addon that touches a frame of Blizzard's for the DoTs
-- part lives here and nowhere else, so that rule can be read in one file.
-- What that rule is: nothing of Blizzard's is ever set. No SetPoint,
-- SetAllPoints, ClearAllPoints, Show, Hide, SetShown, SetAlpha, SetScale,
-- SetParent, SetFrameLevel, SetFrameStrata, SetAttribute or SetClipsChildren
-- on one, and no key written onto one. Reads are fine (GetWidth,
-- GetStatusBarTexture, GetFrameLevel), and a frame or texture of ours
-- parented to one is ours to set: that is how the band attaches.
--
-- How it attaches (measured in game on 26 Nov 2026, build 1.60.1.71139):
-- the target frame's health bar is 126 x 20 and that width is an open number,
-- while its fill texture's width is secret in a fight. A clipping frame of
-- ours pinned to the health bar's four corners holds one StatusBar of ours,
-- as wide as the health bar, its right edge pinned to the health fill's right
-- edge, SetReverseFill(true), its range 0 to the sealed max health and its
-- value the plain damage figure. The game does that division; nothing here
-- ever reads the health. The band reaches left past the bar when the health
-- is low, which is what the clipping frame is for.
--
--   TargetFrame (Blizzard's, level 500, strata LOW)   reads only
--     health bar (Blizzard's, level 502, 126 x 20)    reads only
--       clip    our Frame, the health bar's four corners, SetClipsChildren
--         back  our StatusBar, hatched and paler: everyone else's damage,
--               its right edge on the band's own fill's left edge, so it
--               carries on from where your own band ends
--         band  our StatusBar, the health bar's width, right edge on the
--               health fill's right edge, reverse filling
--           line  our Texture, on the band's own fill texture's left edge
--     holder  our Frame, the skull's group, nothing of it seen but the skull
--       reach  our StatusBar, never seen: the skull's own geometry
--       gate  our Frame, SetClipsChildren, slid by reach's own fill
--         skull  our Texture, the portrait's own rect
--
-- Why the skull takes two frames of its own. On this client your target's
-- health is a secret in a fight and out of one, so "the band covers the rest
-- of the health" is a comparison nothing here may make: a secret cannot be
-- subtracted from, compared with or divided by anything. The game itself can
-- do it, though, the same way it works out the band. One StatusBar of ours,
-- never seen, takes the health your target has now as its range and the
-- damage still to come as its value, so its own fill is full at the moment
-- the damage reaches the health and not before. The bar is SHARP times as
-- wide as the health bar and pinned so that a full fill stands just past the
-- portrait's far edge: a clipping frame of ours rides that fill's edge and
-- the skull inside it is revealed as the edge crosses the portrait. Nothing
-- at all until the damage is within about a fortieth of the health, and the
-- whole skull from the moment it passes it. Nothing here ever learns the
-- health, the band's width or how much of the skull is showing.
--
-- And the same band on your target's nameplate, for anyone who reads their
-- target off that rather than the target frame. A plate is the game's, and
-- the game hands the same plate to another unit as the first goes out of
-- sight, so nothing of ours is ever built on one: one set of layers is made
-- with the rest, out of a fight, and moved onto whichever plate is your
-- target's. It comes off again as that plate goes.
local _, ns = ...

local B = {}
ns.DotsBand = B

local Style = ns.Style
local FLAT = Style.FLAT
local SKULL = ns.MEDIA .. "Skull.tga" -- ours, written by Tools/GenerateSkull.mjs
local HATCH = ns.MEDIA .. "Hatch.tga" -- the same, by Tools/GenerateHatch.mjs

local LINE_WIDE = 2 -- the bright line at the band's left edge, in pixels
local SKULL_INSET = 2 -- how far in from the portrait's edges the skull is drawn
local SKULL_OVER = 2 -- and how far past its far edge a full fill stands
-- The skull's own colour: bone, not the band's, so it reads on any portrait
-- and whatever colour the band is set to.
local BONE = { 1, .96, .9 }
-- Other players' band, behind yours: this much of the band's own strength and
-- this far towards white, so the same damage marked by someone else reads as
-- the quieter of the two. Hatched as well (Media/Hatch.tga), so the two are
-- never one band with a lighter end.
local THEIRS_SHARE, THEIRS_PALE = .65, .35
-- How sharply the skull comes in: the bar the skull's own geometry is worked
-- out on is this many times as wide as the health bar, so the portrait's
-- width of it is crossed by about a fortieth of the health your target has
-- left (58 and 2 of 20 x 126, as measured in game). One, and the skull would
-- wipe in over nearly half of that health.
local SHARP = 20
-- How far back the sliding clip reaches, which only has to be further than
-- SHARP ever slides it (SHARP x a health bar that is nowhere near 200 wide),
-- so the skull stays in full once the damage is well past the health.
local REACH = 4000
local FADE = .3 -- out of combat Fade, as the list's and your bars'
local STEP = .05 -- how often the band is drawn again, in seconds
-- The band's own frame level, over the health bar it sits on, and the
-- skull's, over the target frame's own art. The band was one level up and
-- that was not enough: a unit frame addon laying its own art over the bar
-- hid the band completely while the skull, six up, still showed (seen in
-- game 27 Nov 2026, EraUI's own target frame doing it, which is how it was
-- found). Six for both, so anything dressing the frame is cleared. The band
-- is clipped to the health bar, so it can never reach past it however high
-- it sits, and it is see-through, so the game's own health numbers still
-- read through it.
local OVER_BAR, OVER_FRAME = 6, 6
-- A level is not enough on its own. A unit frame addon dressing the target
-- frame laid its own art over the bar and hid the band completely, at one
-- level up and still at six (seen in game 27 Nov 2026, EraUI's own target
-- frame doing it). A strata beats every level under it, so the band takes
-- the one above its bar's and stops the guessing. It is clipped to the
-- health bar, so however high it sits it can never draw past it, and it is
-- see-through, so the game's own health numbers still read underneath.
local STRATA = { BACKGROUND = "LOW", LOW = "MEDIUM", MEDIUM = "HIGH", HIGH = "DIALOG" }

-- The strata to put our own frame in so it draws over everything dressing
-- the bar. Nothing of Blizzard's is set: this is read from theirs and set on
-- ours. Nil when the game will not say, and the level alone has to do.
local function Above(bar)
    local now = bar.GetFrameStrata and select(1, pcall(bar.GetFrameStrata, bar))
        and ({ pcall(bar.GetFrameStrata, bar) })[2] or nil
    return type(now) == "string" and STRATA[now] or nil
end

local function Open(value)
    return not (issecretvalue and issecretvalue(value))
end

-- Everything the band keeps: Blizzard's frame and the parts of it this reads,
-- the layers of ours on it and on your target's nameplate, what the game last
-- said the target's health was, and what is waiting for a fight to end.
-- (B.state is for the tests, as Dots.lua hands out its own.)
local state = {
    pending = {},
    errors = {},
}
B.state = state

local ticker, waited = nil, 0

-- Whether the band draws at all: the page's master tick and its own.
local function Wanted()
    return ns.Get("dots") == true and ns.Get("dotBand") == true
end

-- Reading the game ---------------------------------------------------------------------
-- Every answer the game may hold back goes through one of these first, as
-- Fill.lua's own reads do. A secret is kept exactly as it came and is only
-- ever handed straight back to the game; one it answers plainly has to be a
-- number to be any use.

local function Read(fn, unit)
    if type(fn) ~= "function" then return nil end
    local ok, value = pcall(fn, unit)
    if not ok or value == nil then return nil end
    if Open(value) and type(value) ~= "number" then return nil end
    return value
end

-- A plain number the game gives openly: a width, a frame level. A secret one
-- is no use here, since both are only ever used as numbers of ours.
local function Number(fn, obj)
    if type(fn) ~= "function" then return nil end
    local ok, value = pcall(fn, obj)
    if not ok or not Open(value) or type(value) ~= "number" then return nil end
    return value
end

-- Whether you have a target at all (Dots.lua asks the same way).
local function Targeted()
    local ok, there = pcall(UnitExists, "target")
    if not ok then return true end
    if not Open(there) then return true end
    return there and true or false
end

-- And whether it is already dead, so the band comes off a corpse rather than
-- marking damage that will never land. An answer the game holds back counts
-- as alive, since the band itself is right either way.
local function Dead()
    local ok, dead = pcall(UnitIsDeadOrGhost, "target")
    if not ok or not Open(dead) then return false end
    return dead and true or false
end

-- Finding Blizzard's target frame ------------------------------------------------------
-- Only ever read, and only looked for out of a fight. The health bar's key
-- differs between frame generations, so each shape is tried and the one this
-- frame really has is taken (Resource.lua reads its display's the same way).
-- A frame that has none of them is not an error: the band has nothing to sit
-- on, the page and the debug report say so, and the list still works.

local function Part(frame, key)
    local part = frame and frame[key]
    if type(part) == "table" then return part end
end

local function Host()
    local frame = _G.TargetFrame
    if type(frame) ~= "table" then return nil, "no target frame" end
    if type(frame.CreateTexture) ~= "function" or type(frame.GetFrameLevel) ~= "function" then
        return nil, "the target frame is not a frame"
    end
    local bar = Part(Part(frame, "HealthBarsContainer"), "healthBar") or Part(frame, "healthbar")
        or Part(frame, "healthBar")
    if not bar then return nil, "no health bar on the target frame" end
    if type(bar.GetStatusBarTexture) ~= "function" then return nil, "the health bar is not a status bar" end
    local fill = bar:GetStatusBarTexture()
    if type(fill) ~= "table" then return nil, "the health bar has no fill of its own" end
    -- The portrait is the skull's only; a frame without one keeps the band
    -- and the line and goes without the skull.
    local portrait = Part(frame, "portrait") or Part(frame, "Portrait")
    return frame, nil, bar, fill, portrait
end

-- A health bar on a frame of the game's, whatever shape it is in. The names
-- Blizzard's own frames use are tried first; where the frame has none of them,
-- the first status bar among its own children is taken, which is what a plate
-- another addon has restyled rather than replaced still has. Read only:
-- nothing here is ever set on what it finds, and a frame with no bar in it at
-- all answers nothing rather than erroring.
-- Whether a bar is one a player can actually see. An addon that draws its own
-- bars hides the game's by setting it to no opacity rather than by hiding the
-- frame, so a bar can be "shown" and still be invisible: EraUI's target frame
-- was found that way on 27 Nov 2026, reading "shown true, alpha 0". A bar like
-- that is the wrong one to measure a band against, because the one the player
-- is looking at is somewhere else and may not even be the same shape. Read
-- only. A game that will not answer counts as visible, so nothing is skipped
-- on a client that simply says less.
local function Visible(bar)
    if type(bar) ~= "table" then return false end
    -- IsVisible, not IsShown. IsShown only asks whether this frame's own flag
    -- is set, so a bar whose whole unit frame has been hidden still answers
    -- true with full opacity: that is how a nameplate addon puts the game's
    -- plate away before drawing its own, and asking IsShown finds the wrong
    -- bar every time (27 Nov 2026, Plater). IsVisible takes the parents into
    -- account, which is the question actually being asked here.
    local ask = type(bar.IsVisible) == "function" and "IsVisible"
        or type(bar.IsShown) == "function" and "IsShown" or nil
    if ask then
        local ok, shown = pcall(bar[ask], bar)
        if ok and Open(shown) and shown == false then return false end
    end
    if type(bar.GetAlpha) == "function" then
        local ok, alpha = pcall(bar.GetAlpha, bar)
        if ok and Open(alpha) and type(alpha) == "number" and alpha <= 0 then return false end
    end
    return true
end

-- A status bar off a frame by name, going one step further where the name
-- holds a widget rather than a bar: a nameplate addon keeps a frame called
-- healthBar whose actual bar is statusBar inside it, so stopping at the name
-- finds a frame that is not a bar at all and gives up (read out of its
-- source, 27 Nov 2026). Read only.
local function BarIn(frame)
    for _, key in ipairs({ "healthBar", "healthbar", "statusBar" }) do
        local part = Part(frame, key)
        if part then
            if type(part.GetStatusBarTexture) == "function" then return part end
            local deeper = Part(part, "statusBar") or Part(part, "healthBar")
            if deeper and type(deeper.GetStatusBarTexture) == "function" then return deeper end
        end
    end
end

local function BarOn(frame)
    if type(frame) ~= "table" then return nil end
    -- statusBar as well as the game's own names: a nameplate addon calls its
    -- health bar that, and makes an absorb bar of the same kind just before
    -- it, so taking the first bar found would mark the absorb one instead
    -- (read out of its source, 27 Nov 2026). Asking for the key by name
    -- settles which is which without caring what order they were made in.
    local named = Part(Part(frame, "HealthBarsContainer"), "healthBar") or BarIn(frame)
    local hidden, hiddenFill -- the game's own bar, kept in case nothing else turns up
    if named and type(named.GetStatusBarTexture) == "function" then
        local fill = named:GetStatusBarTexture()
        if type(fill) == "table" then
            if Visible(named) then return named, fill, true end
            hidden, hiddenFill = named, fill
        end
    end
    if type(frame.GetChildren) ~= "function" then return hidden, hiddenFill, false end
    -- The whole walk inside one pcall: what the game hands back here is its
    -- own frames, and a client that will not list them says so by erroring
    -- rather than by answering.
    local ok, kids = pcall(function() return { frame:GetChildren() } end)
    if not ok then return hidden, hiddenFill, false end
    -- Two levels down, not one. An addon that builds its own plate puts a
    -- frame of its own on the game's and the health bar inside that, so the
    -- bar a player is looking at is a grandchild and one level finds only the
    -- game's hidden one (27 Nov 2026, Plater). Two is as deep as this goes:
    -- any further and it is walking somebody's whole interface looking for
    -- something that is not theirs to find.
    local deeper = {}
    for _, kid in ipairs(kids) do
        if type(kid) == "table" and type(kid.GetStatusBarTexture) == "function" then
            local fill = kid:GetStatusBarTexture()
            if type(fill) == "table" then
                if Visible(kid) then return kid, fill, true end
                if not hidden then hidden, hiddenFill = kid, fill end
            end
        end
        if type(kid) == "table" and type(kid.GetChildren) == "function" then deeper[#deeper + 1] = kid end
    end
    for _, kid in ipairs(deeper) do
        -- The child's own named bar first, for the same reason as above: the
        -- plate's display frame holds both an absorb bar and the health one,
        -- and only the name tells them apart.
        local own = BarIn(kid)
        if own and type(own.GetStatusBarTexture) == "function" then
            local fill = own:GetStatusBarTexture()
            if type(fill) == "table" then
                if Visible(own) then return own, fill, true end
                if not hidden then hidden, hiddenFill = own, fill end
            end
        end
        local ok2, grandkids = pcall(function() return { kid:GetChildren() } end)
        if ok2 then
            for _, grandkid in ipairs(grandkids) do
                if type(grandkid) == "table" and type(grandkid.GetStatusBarTexture) == "function" then
                    local fill = grandkid:GetStatusBarTexture()
                    if type(fill) == "table" then
                        if Visible(grandkid) then return grandkid, fill, true end
                        if not hidden then hidden, hiddenFill = grandkid, fill end
                    end
                end
            end
        end
    end
    -- Nothing visible anywhere: the game's own bar, so a plate that is simply
    -- faded out this moment still gets its band when it comes back. The third
    -- answer says whether what came back is one a player can see, so a caller
    -- with somewhere else to look knows to look there first.
    return hidden, hiddenFill, false
end

-- And your target's own nameplate, the same way: asked for whenever the game
-- says the plates have changed, since which plate belongs to your target is
-- the game's to say and never ours to remember. Only your target's is ever
-- marked: the clock knows what you have running on your target and on
-- nothing else. A client with no nameplates, or a plate in a shape this
-- cannot read, is not an error: the tick simply has nothing to mark.
local function Plate()
    local plates = C_NamePlate
    local ask = type(plates) == "table" and plates.GetNamePlateForUnit
    if type(ask) ~= "function" then return nil, "this client has no nameplates to ask about" end
    local ok, plate = pcall(ask, "target")
    if not ok or type(plate) ~= "table" then return nil, "your target has no nameplate up" end
    -- The game's own shape first, which is a unit frame on the plate with the
    -- health bar in that, then the plate itself for a plate that was built
    -- again rather than restyled. A bar that is there but not one a player can
    -- see is not good enough to stop at: a nameplate addon hides the game's
    -- unit frame whole and draws its own on the plate beside it, so the game's
    -- bar is still found, still answers, and is the wrong one. Only a bar
    -- nobody can see anywhere is settled for (27 Nov 2026, Plater).
    -- Every place a bar could be, in turn, and the first one a player can
    -- actually see wins. Not "UnitFrame or unitFrame": the game's own is
    -- there even when an addon has hidden it, so an `or` never reaches the
    -- addon's and the band lands on the hidden one every time (27 Nov 2026,
    -- Plater). A bar nobody can see is only settled for when no look finds
    -- one that is visible.
    local bar, fill
    -- Built by hand, not as a list literal: a plate with no unit frame on it
    -- gives nil for the first two, and ipairs over a table with a hole in it
    -- stops dead at the hole and looks at nothing.
    local places = {}
    for _, where in ipairs({ "UnitFrame", "unitFrame" }) do
        local found = Part(plate, where)
        if found then places[#places + 1] = found end
    end
    places[#places + 1] = plate
    -- Some nameplate addons do not put their frame inside the plate at all.
    -- They keep it elsewhere and name it after the plate, so walking down
    -- from the plate finds only the game's hidden one however deep it goes
    -- (27 Nov 2026: the plate's own tree held no status bar anywhere, while
    -- a frame called NamePlate2PlaterUnitFrame existed beside it). The
    -- plate's name plus a suffix finds those, and costs one table lookup.
    -- Read out of its own source on 27 Nov 2026 rather than guessed at: it
    -- builds a frame named after the plate plus PlaterUnitFrame, and a real
    -- status bar inside that named the same plus HealthBar. The bar itself is
    -- tried first, because going at it directly skips every question about
    -- where its frame is parented.
    local named = type(plate.GetName) == "function" and ({ pcall(plate.GetName, plate) })[2] or nil
    if type(named) == "string" then
        for _, full in ipairs({ named .. "PlaterUnitFrameHealthBar" }) do
            local found = _G[full]
            if type(found) == "table" and type(found.GetStatusBarTexture) == "function" and Visible(found) then
                local fillOf = found:GetStatusBarTexture()
                if type(fillOf) == "table" then return plate, nil, found, fillOf end
            end
        end
        for _, suffix in ipairs({ "PlaterUnitFrame", "UnitFrame", "Health" }) do
            local found = _G[named .. suffix]
            if type(found) == "table" then places[#places + 1] = found end
        end
    end
    for _, where in ipairs(places) do
        local found, foundFill, seen = BarOn(where)
        if found and seen then
            bar, fill = found, foundFill
            break
        end
        if found and not bar then bar, fill = found, foundFill end
    end
    if not bar then return nil, "no health bar this can read on your target's nameplate" end
    return plate, nil, bar, fill
end

-- Building it, once --------------------------------------------------------------------
-- Every frame and texture is made here, out of a fight, and never again: a
-- fight never builds anything (Fill.lua states the same rule). Each layer is
-- anchored to the edge that is the measurement, never to a number worked out
-- from where that edge is, so nothing has to be moved as the health moves.
-- The only thing ever anchored again is a set of layers put on a different
-- frame underneath (Point, PointSkull), which is a nameplate the game has
-- handed to another unit.

-- How wide the band is, which is the one number a health bar gives openly.
-- The skull's own bar takes SHARP times it, since that is what makes the
-- skull come in sharply.
local function Shape(parts)
    local bar = parts.bar
    local wide = bar and Number(bar.GetWidth, bar)
    if not wide or wide <= 0 then return end
    if wide ~= parts.wide then
        parts.wide = wide
        parts.band:SetWidth(wide)
        parts.back:SetWidth(wide)
    end
    -- The skull's bar is kept on its own, since it may be made after the band
    -- has already taken its width (the frame has a portrait and the bar does
    -- not) and nothing else would set it then.
    local reach = wide * SHARP
    if parts.reach and parts.reachWide ~= reach then
        parts.reachWide = reach
        parts.reach:SetWidth(reach)
    end
end

local function Band(parent)
    local parts = {}
    local clip = CreateFrame("Frame", nil, parent)
    clip:EnableMouse(false)
    clip:SetClipsChildren(true)
    clip:SetAlpha(0)
    -- Everyone else's spells, behind yours and made first so it is under it.
    -- Its own value is their damage alone and it is pointed at the edge your
    -- own band reaches (Point), so the two sit side by side rather than one
    -- over the other. Out of sight until there is some of theirs to mark.
    local back = CreateFrame("StatusBar", nil, clip)
    back:EnableMouse(false)
    back:SetStatusBarTexture(HATCH)
    back:SetReverseFill(true)
    back:SetMinMaxValues(0, 1)
    back:SetValue(0)
    back:SetWidth(1)
    back:SetAlpha(0)
    local band = CreateFrame("StatusBar", nil, clip)
    band:EnableMouse(false)
    band:SetStatusBarTexture(FLAT)
    band:SetReverseFill(true)
    band:SetMinMaxValues(0, 1)
    band:SetValue(0)
    band:SetWidth(1)
    -- The bright line on the band's own fill texture's left edge, which is
    -- where your own spells leave the target's health. (Other players' band
    -- carries on from that same edge, so the line reads as the join between
    -- what you are dealing and what they are.)
    local mark = band:GetStatusBarTexture()
    local line = band:CreateTexture(nil, "OVERLAY")
    line:SetTexture(FLAT)
    line:SetPoint("TOPLEFT", mark, "TOPLEFT", 0, 0)
    line:SetPoint("BOTTOMLEFT", mark, "BOTTOMLEFT", 0, 0)
    line:SetWidth(LINE_WIDE)
    line:Hide()
    parts.clip, parts.band, parts.mark, parts.line, parts.back = clip, band, mark, line, back
    return parts
end

-- Our layers put on a health bar: the clip over the whole of it, and the band
-- as wide as the bar with its right edge on the bar's own fill. So the game
-- lays the band from where the health ends back towards where it started, and
-- the share it reaches is the share the damage is of the target's full
-- health. Everything set here is set on ours; the bar is only ever read and
-- never written to, and a frame of ours as the argument of our own SetParent
-- or SetPoint is ours.
--
-- Done again only where the frame underneath can change, which is a
-- nameplate: the target frame's band is pointed at it once and never moved.
-- The band kept above the bar it sits on, checked every tick rather than set
-- once. A nameplate addon builds its plate and then raises its own frames
-- afterwards, so a level read at the moment the plate was adopted is stale
-- within a frame or two: ours sat at 7 while the bar it was marking had
-- climbed to 5011, which put the band underneath the very bar it was drawn
-- on (27 Nov 2026, Plater). Only written when it has actually drifted, so
-- the usual case costs one read and nothing else.
local function Raise(parts)
    if not (parts and parts.bar and parts.clip) then return end
    local level = Number(parts.bar.GetFrameLevel, parts.bar)
    if not level then return end
    local want = level + OVER_BAR
    if Number(parts.clip.GetFrameLevel, parts.clip) == want then return end
    pcall(parts.clip.SetFrameLevel, parts.clip, want)
    local inside = Number(parts.clip.GetFrameLevel, parts.clip)
    if not inside then return end
    pcall(parts.back.SetFrameLevel, parts.back, inside)
    pcall(parts.band.SetFrameLevel, parts.band, inside + 1)
end

local function Point(parts, bar, fill)
    -- The fill texture is checked as well as the bar, not just the bar. A
    -- unit frame addon restyling the target frame gives its health bar a new
    -- status bar texture, which throws the old texture object away: the bar
    -- is the same frame, so pointing only on the bar left the band pinned to
    -- a texture nothing draws any more. It reported itself found, sized and
    -- drawing while nothing was on screen, and no amount of frame level or
    -- strata helped, because it was not a layering fault at all (seen in
    -- game 27 Nov 2026 against EraUI's own unit frame look).
    if parts.bar == bar and parts.fill == fill then return end
    parts.bar, parts.fill, parts.wide = bar, fill, nil
    local clip = parts.clip
    -- Hung off the bar's parent, not the bar. A unit frame addon that draws
    -- its own bars hides the game's by setting it to no opacity at all
    -- rather than hiding the frame, and a child of it inherits that, so the
    -- band was invisible however high it sat: proven in game on 27 Nov 2026,
    -- where the report read "shown true, alpha 0" on the bar it had taken.
    -- The anchors below still go to the bar and its fill, so where the band
    -- sits is unchanged; only what it hangs from has moved, and it still
    -- goes when the frame goes. Nothing of theirs is set either way.
    -- Only when the bar itself is hidden. A visible bar is hung off directly,
    -- the plain way that works on the game's own plates and on a skin: a
    -- nameplate is drawn through the game's own path, and pulling our frame
    -- out of it by parent and strata stops it drawing at all even though
    -- every number says it should (27 Nov 2026, Plater, whose bar is visible
    -- at full opacity and needed none of this).
    local seen = Visible(bar)
    local host = not seen and type(bar.GetParent) == "function" and ({ pcall(bar.GetParent, bar) })[2] or nil
    clip:SetParent(type(host) == "table" and host or bar)
    clip:ClearAllPoints()
    clip:SetPoint("TOPLEFT", bar, "TOPLEFT", 0, 0)
    clip:SetPoint("BOTTOMRIGHT", bar, "BOTTOMRIGHT", 0, 0)
    Raise(parts)
    -- The same: a strata of its own only where the band had to climb out of
    -- a hidden bar. A visible bar keeps its own, so a nameplate's band stays
    -- in the strata the game draws its plates in.
    local strata = not seen and Above(bar) or nil
    if strata then clip:SetFrameStrata(strata) end
    local band, back = parts.band, parts.back
    band:ClearAllPoints()
    band:SetPoint("TOP", clip, "TOP", 0, 0)
    band:SetPoint("BOTTOM", clip, "BOTTOM", 0, 0)
    band:SetPoint("RIGHT", fill, "RIGHT", 0, 0)
    -- Everyone else's carries on from where your own band ends, so the two
    -- never lie over one another: its right edge is your band's own fill
    -- texture's left edge, which is the edge your damage reaches, exactly as
    -- the bright line is anchored. Where your own band covers the whole bar
    -- theirs is pushed off the left of the clip, which is right: the health is
    -- marked already.
    back:ClearAllPoints()
    back:SetPoint("TOP", clip, "TOP", 0, 0)
    back:SetPoint("BOTTOM", clip, "BOTTOM", 0, 0)
    back:SetPoint("RIGHT", parts.mark, "LEFT", 0, 0)
    -- And your own band over theirs inside the clip. Set again with the level
    -- rather than once where they are made, since the clip's own level follows
    -- whichever health bar it was last put on.
    local inside = Number(clip.GetFrameLevel, clip)
    if inside then
        back:SetFrameLevel(inside)
        band:SetFrameLevel(inside + 1)
    end
    Shape(parts)
end

-- The skull's own group, which is only made where the frame has a portrait
-- to put it on. The bar in it is never seen: it is there for the game to do
-- the one sum nothing here may do (see the top of this file).
local function Skull(parts, frame)
    local holder = CreateFrame("Frame", nil, frame)
    holder:EnableMouse(false)
    holder:SetAlpha(0)
    -- The damage still to come, against the health your target has now: the
    -- range is that health and the value is the damage, so the game fills
    -- this bar right to its end at the moment the one reaches the other.
    local reach = CreateFrame("StatusBar", nil, holder)
    reach:EnableMouse(false)
    reach:SetStatusBarTexture(FLAT)
    reach:SetAlpha(0)
    reach:SetHeight(1)
    reach:SetWidth(1)
    reach:SetMinMaxValues(0, 1)
    reach:SetValue(0)
    -- The clip that rides that fill's edge. It reaches a long way back, so
    -- once the damage is well past the health it lies right across the
    -- portrait and stays there.
    local gate = CreateFrame("Frame", nil, holder)
    gate:EnableMouse(false)
    gate:SetClipsChildren(true)
    gate:SetWidth(REACH)
    -- The skull itself, which the gate lets through rather than squashing or
    -- stretching, so it reads the same however much of it is showing.
    local skull = gate:CreateTexture(nil, "OVERLAY")
    skull:SetTexture(SKULL)
    skull:SetVertexColor(BONE[1], BONE[2], BONE[3])
    skull:Hide()
    parts.holder, parts.reach, parts.gate, parts.skull = holder, reach, gate, skull
end

-- The skull's group put on a portrait: the group over the portrait itself,
-- the bar's right edge a little past the portrait's far edge (so a full fill
-- clears the whole portrait and a fill a portrait's width short of full
-- clears none of it), the gate riding that fill's right edge, and the skull
-- on the portrait's own rect. Done again only if the frame underneath is
-- swapped for another one, which is why nothing of it is anchored where it
-- is made.
local function PointSkull(parts, frame, portrait)
    if parts.portrait == portrait then return end
    parts.portrait = portrait
    local holder, reach, gate, skull = parts.holder, parts.reach, parts.gate, parts.skull
    holder:SetParent(frame)
    holder:ClearAllPoints()
    holder:SetPoint("TOPLEFT", portrait, "TOPLEFT", 0, 0)
    holder:SetPoint("BOTTOMRIGHT", portrait, "BOTTOMRIGHT", 0, 0)
    local level = Number(frame.GetFrameLevel, frame)
    if level then holder:SetFrameLevel(level + OVER_FRAME) end
    reach:ClearAllPoints()
    reach:SetPoint("RIGHT", portrait, "RIGHT", SKULL_OVER, 0)
    gate:ClearAllPoints()
    gate:SetPoint("TOP", portrait, "TOP", 0, 0)
    gate:SetPoint("BOTTOM", portrait, "BOTTOM", 0, 0)
    gate:SetPoint("RIGHT", reach:GetStatusBarTexture(), "RIGHT", 0, 0)
    skull:ClearAllPoints()
    skull:SetPoint("TOPLEFT", portrait, "TOPLEFT", SKULL_INSET, -SKULL_INSET)
    skull:SetPoint("BOTTOMRIGHT", portrait, "BOTTOMRIGHT", -SKULL_INSET, SKULL_INSET)
end

-- Drawing it ---------------------------------------------------------------------------

-- The target's health as the game hands it over, kept exactly as it came. The
-- band's range is the full health and the skull's bar's range is the health it
-- has left, so both are kept. Neither is ever read, counted or compared: each
-- goes straight back to the game (Hand, below). An answer the game refuses
-- leaves the last one standing.
local function Health()
    local most = Read(UnitHealthMax, "target")
    local now = Read(UnitHealth, "target")
    if most ~= nil then state.most = most end
    if now ~= nil then state.now = now end
    return state.most ~= nil
end

-- The range and the value handed over, which is the whole of how far the band
-- reaches: the range is the target's sealed full health and the value is the
-- plain damage still to come, the other way round from the Resource fill's
-- gauges. The game works the share out and lays its own fill texture there.
-- damage is your own spells', theirs is everyone else's, and total is both
-- together. Your own band takes yours, the band behind it takes theirs (it
-- starts where yours ends, so each one is its own owner's damage), and the
-- skull takes the two together: the skull is about whether your target lives,
-- and it does not care who the damage came from.
local function Hand(parts, damage, theirs, total)
    if state.most == nil then return false end
    parts.band:SetMinMaxValues(0, state.most)
    parts.band:SetValue(damage or 0)
    parts.back:SetMinMaxValues(0, state.most)
    parts.back:SetValue(theirs or 0)
    -- And the skull's own bar, which is the damage against the health your
    -- target has left rather than the health it started with. A health the
    -- game would not give leaves the last one standing.
    if parts.reach and state.now ~= nil then
        parts.reach:SetMinMaxValues(0, state.now)
        parts.reach:SetValue(total or damage or 0)
    end
    return true
end

-- The band's colour and the line's, each as its own choice says, with the
-- strength slider as the band's own opacity over the health bar. The band's
-- Default is the school of whichever spell has the most damage still to come
-- (Dots.lua's D:Band hands it over), so a band that is mostly Corruption
-- draws in shadow. Only ever set again when something has changed, so
-- nothing is made frame by frame for it.
local function Paint(parts, school)
    local D = ns.Dots
    if not D then return end
    local bandKey, lineKey = ns.ColourKey("dotBandColour"), ns.ColourKey("dotLineColour")
    local strength = ns.Get("dotBandStrength")
    if parts.bandKey == bandKey and parts.lineKey == lineKey and parts.strength == strength
        and parts.school == school then return end
    parts.bandKey, parts.lineKey, parts.strength, parts.school = bandKey, lineKey, strength, school
    local colour, edge = D:Colour("dotBandColour", bandKey), D:Colour("dotLineColour", lineKey)
    if type(colour) ~= "table" or type(edge) ~= "table" then return end
    parts.band:SetStatusBarColor(colour[1], colour[2], colour[3], strength / 100)
    parts.line:SetVertexColor(edge[1], edge[2], edge[3])
    -- Everyone else's in the same colour, paler and at a share of the
    -- strength, so it reads as the quieter of the two bands.
    parts.back:SetStatusBarColor(colour[1] + (1 - colour[1]) * THEIRS_PALE,
        colour[2] + (1 - colour[2]) * THEIRS_PALE, colour[3] + (1 - colour[3]) * THEIRS_PALE,
        strength / 100 * THEIRS_SHARE)
end

-- In full in a fight, with an enemy targeted (a secret answer counts), and
-- while the DoTs page is open, as the list and the Totems bar are.
local function Awake()
    if state.inCombat or InCombatLockdown() or (ns.Dots and ns.Dots.pageOpen) then return true end
    if ns.Get("oocIgnoreTarget") then return false end
    local ok, hostile = pcall(UnitCanAttack, "player", "target")
    if not ok then return true end
    if not Open(hostile) then return true end
    return (hostile and Targeted()) and true or false
end

-- One set of layers lit or put out: the band by its own alpha, the line and
-- the skull by their ticks as well.
local function Lit(parts, alpha)
    if not parts then return end
    parts.clip:SetAlpha(alpha)
    parts.line:SetShown(alpha > 0 and ns.Get("dotLine") == true)
    -- Everyone else's band only where it is ticked and there is some of theirs
    -- to mark. Its own colour carries the strength, so this is on or off.
    parts.back:SetAlpha(alpha > 0 and ns.Get("dotOthers") == true
        and type(state.theirs) == "number" and state.theirs > 0 and 1 or 0)
    if not parts.holder then return end
    local skull = alpha > 0 and ns.Get("dotSkull") == true
    parts.holder:SetAlpha(skull and alpha or 0)
    parts.skull:SetShown(skull)
end

-- The band's alpha: nothing to mark, no target or a dead one, gone right out;
-- else in full while awake, or as chosen out of combat. Never shown or
-- hidden, and nothing of Blizzard's is touched either way. The line and the
-- skull are ours, so those are shown and hidden as their own ticks say.
function B:UpdateShown()
    local alpha = 0
    -- Anything at all to mark, yours or anyone else's: a target with only
    -- other players' spells on it is still marked, where that is ticked.
    local marked = Wanted() and type(state.total) == "number" and state.total > 0
    if marked and Targeted() and not Dead() then
        local mode = ns.Get("dotOutOfCombat")
        alpha = Awake() and 1 or mode == "fade" and FADE or mode == "hide" and 0 or 1
    end
    Lit(state.parts, alpha)
    -- The nameplate's goes out with its plate, whatever the band itself is
    -- doing on the target frame.
    Lit(state.plateParts, state.plateOn and alpha or 0)
end

-- One pass: what the damage still to come is now (our own clock's number,
-- never the game's), handed over with the colours and the alpha that go with
-- it. Answers whether anything is left to mark, which is what stops the clock.
local function Draw()
    -- Kept above whatever the bars have done to themselves since. A nameplate
    -- addon raises its own frames after the plate is up, so this is the only
    -- place that can keep the band on top of them.
    Raise(state.parts)
    Raise(state.plateParts)
    local damage, school = nil, nil
    if ns.Dots then damage, school = ns.Dots:Band() end
    -- And everyone else's, for the band behind yours. Dots.lua answers nothing
    -- at all while that is unticked, so nothing of theirs is read or drawn.
    local theirs = nil
    if ns.Dots and ns.Dots.Theirs then theirs = ns.Dots:Theirs() end
    local total = (damage or 0) + (theirs or 0)
    state.damage, state.school, state.theirs = damage, school, theirs
    state.total = total > 0 and total or nil
    -- Each set of layers in turn, and nothing made here: the pass runs every
    -- STEP while there is damage to mark.
    local drawn = false
    local parts = state.parts
    if parts then
        Shape(parts)
        Paint(parts, school)
        Hand(parts, damage, theirs, total)
        drawn = true
    end
    parts = state.plateParts
    if parts then
        Shape(parts)
        Paint(parts, school)
        Hand(parts, damage, theirs, total)
        drawn = true
    end
    B:UpdateShown()
    return drawn and total > 0
end

local function Stop()
    if ticker then ticker:SetScript("OnUpdate", nil) end
end

-- One OnUpdate for the band, running only while there is damage to mark and
-- stopped the moment there is none (Fill.lua and the list do the same).
-- Nothing in it asks the game anything: the damage is our own clock's and the
-- health only changes when the game says it has.
local function Run(_, elapsed)
    waited = waited + (elapsed or 0)
    if waited < STEP then return end
    waited = 0
    if not Draw() then Stop() end
end

-- Started only where there is something to mark and somewhere to mark it, so
-- a band with nothing running never runs a frame of its own at all.
local function Going()
    if not (state.parts or state.plateParts) or not Wanted() then return Stop() end
    if not (type(state.total) == "number" and state.total > 0) then return Stop() end
    if not ticker then
        ticker = CreateFrame("Frame")
        B.ticker = ticker
    end
    if not ticker:GetScript("OnUpdate") then
        waited = STEP
        ticker:SetScript("OnUpdate", Run)
    end
end

-- For the tests: whether the OnUpdate runs now.
function B:Drawing()
    return ticker ~= nil and ticker:GetScript("OnUpdate") ~= nil
end

-- Attaching and letting go --------------------------------------------------------------

-- Everything of ours out of sight, with nothing of Blizzard's touched: what
-- the band does when it is switched off, when there is no target, and at a
-- loading screen.
local function Dark(parts)
    if not parts then return end
    parts.clip:SetAlpha(0)
    parts.line:Hide()
    parts.back:SetAlpha(0)
    if parts.holder then parts.holder:SetAlpha(0) end
    if parts.skull then parts.skull:Hide() end
end

local function Blank()
    state.damage, state.school, state.theirs, state.total = nil, nil, nil, nil
    Dark(state.parts)
    Dark(state.plateParts)
end

-- The layers made on Blizzard's frame, once, out of a fight. A fight waits:
-- what the game is showing now is left exactly as it is and the band goes up
-- when the fight ends. A frame the addon cannot read is not an error either:
-- state.errors.host says why, for the page and the debug report.
local function Attach()
    if not Wanted() then return false end
    -- Blizzard's frame is only ever looked for out of a fight, and never
    -- built on during one: what is up stays up, and what is not waits.
    if InCombatLockdown() then
        if not state.parts then state.pending.attach = true end
        return state.parts ~= nil
    end
    local frame, why, bar, fill, portrait = Host()
    if not frame then
        state.errors.host = why
        -- This set only: a target frame this cannot read says nothing about
        -- the band on your target's nameplate.
        Dark(state.parts)
        return false
    end
    state.errors.host = nil
    state.pending.attach = nil
    if state.parts and state.bar == bar then return true end
    -- A target frame that was swapped for another one has the same layers
    -- moved onto its health bar; nothing is ever unmade, exactly as nothing
    -- is ever made in a fight.
    local parts = state.parts
    if parts then
        Dark(parts)
    else
        parts = Band(bar)
        state.parts = parts
        B.parts = parts
    end
    Point(parts, bar, fill)
    if portrait then
        if not parts.holder then Skull(parts, frame) end
        PointSkull(parts, frame, portrait)
    end
    state.frame, state.bar, state.fill, state.portrait = frame, bar, fill, portrait
    Health()
    return true
end

-- And the same layers on your target's nameplate, where that is ticked. Made
-- out of a fight with everything else, and moved rather than remade: the
-- plates themselves come and go in the middle of a fight, and the game gives
-- the same plate to the next unit, so one set of ours follows whichever plate
-- is your target's and goes out as that plate does.
local function Plated()
    if not (Wanted() and ns.Get("dotNameplates") == true) then
        state.plateOn = false
        state.pending.plate = nil
        Dark(state.plateParts)
        return false
    end
    local parts = state.plateParts
    if not parts then
        if InCombatLockdown() then
            state.pending.plate = true
            return false
        end
        parts = Band(UIParent)
        state.plateParts = parts
        B.plateParts = parts
    end
    state.pending.plate = nil
    local plate, why, bar, fill = Plate()
    if not plate then
        state.errors.plate = why
        state.plateOn = false
        Dark(parts)
        return false
    end
    state.errors.plate = nil
    state.plateOn = true
    state.plate = plate
    Point(parts, bar, fill)
    return true
end

-- Whether the band found something to sit on, for the page and the report.
function B:Found()
    return state.parts ~= nil and state.errors.host == nil
end

-- And why not, where the answer is that this client's target frame could not
-- be read at all: the page says that in plain words. Nothing while the band
-- is only waiting for a fight to end, since there is nothing wrong then.
function B:Missing()
    return state.errors.host
end

-- For the tests: the layers as they are now.
function B:Parts()
    return state.parts
end

-- For the tests: and the set of them on your target's nameplate.
function B:PlateParts()
    return state.plateParts
end

-- Events -------------------------------------------------------------------------------
-- Heard only while the band is on. The combat log is never registered for at
-- all: on this client that is a blocked action and puts a warning box on the
-- player's screen.

local EVENTS = { "PLAYER_TARGET_CHANGED", "PLAYER_REGEN_DISABLED", "PLAYER_REGEN_ENABLED", "PLAYER_ENTERING_WORLD" }
-- The target's health, which the band's own range (its full health) and the
-- skull's bar (the health it has left) both take as the game has it. Through
-- pcall, since which of these a client has is not proven, and as unit events
-- for your target alone where the game allows it. A client that answers
-- neither leaves both on the health it last heard about, and how far the band
-- reaches never depends on the number either way.
local HEALTH_EVENTS = { "UNIT_HEALTH", "UNIT_MAXHEALTH" }
-- The plates, which come and go in the middle of a fight. Which one is your
-- target's is asked of the game on each of these rather than worked out from
-- the unit the event names, since that is the game's answer to give.
local PLATE_EVENTS = { "NAME_PLATE_UNIT_ADDED", "NAME_PLATE_UNIT_REMOVED" }

local function OnEvent(_, event)
    if not Wanted() then return end
    if event == "PLAYER_ENTERING_WORLD" then
        -- A loading screen: Blizzard's frames may be new ones, and nothing of
        -- ours is left showing over whatever is there now.
        Blank()
        Attach()
        Plated()
        Health()
        Draw()
        Going()
    elseif event == "PLAYER_TARGET_CHANGED" then
        -- A new target has its own health and its own plate, and the list it
        -- had on it (if any) is Dots.lua's to clear. Nothing is left behind.
        Blank()
        Attach()
        Plated()
        Health()
        Draw()
        Going()
    elseif event == "PLAYER_REGEN_DISABLED" then
        state.inCombat = true
        B:UpdateShown()
    elseif event == "PLAYER_REGEN_ENABLED" then
        state.inCombat = false
        -- Anything the fight would not let us build is built now.
        if state.pending.attach then Attach() end
        if state.pending.plate then Plated() end
        Health()
        Draw()
        Going()
    elseif event == "NAME_PLATE_UNIT_ADDED" or event == "NAME_PLATE_UNIT_REMOVED" then
        -- A plate came up or went away: ours follows whichever one is your
        -- target's now, or goes out if that is none.
        Plated()
        Draw()
        Going()
    else
        -- The target's health changed. The band's own range is its max health
        -- and the skull's is the health it has left, so both sets take the new
        -- answer; how far the band reaches never depends on either number.
        if Health() then
            if state.parts then Hand(state.parts, state.damage, state.theirs, state.total) end
            if state.plateParts then Hand(state.plateParts, state.damage, state.theirs, state.total) end
        end
    end
end

local function Driver()
    if not state.driver then
        state.driver = CreateFrame("Frame")
        state.driver:SetScript("OnEvent", OnEvent)
        B.driver = state.driver
    end
    return state.driver
end

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
    for _, event in ipairs(HEALTH_EVENTS) do
        if not pcall(driver.RegisterUnitEvent, driver, event, "target") then
            pcall(driver.RegisterEvent, driver, event)
        end
    end
    -- Through pcall as well: which of these a client has is not proven, and a
    -- client without them simply never marks a plate.
    for _, event in ipairs(PLATE_EVENTS) do pcall(driver.RegisterEvent, driver, event) end
end

-- The list changed, or the clock moved it on (Dots.lua calls this as it draws
-- its own rows): the band follows the same number, and its own clock starts
-- or stops with it.
function B:Follow()
    if not Wanted() then return end
    if not state.parts then Attach() end
    if not state.plateOn then Plated() end
    Draw()
    Going()
end

-- Every choice on the page again, which is the one way in: Dots.lua's D:Apply
-- calls this after each change.
function B:Apply()
    self.wanted = Wanted()
    if not self.wanted then
        Hear(false)
        Stop()
        Blank()
        return
    end
    Hear(true)
    Attach()
    Plated()
    Health()
    Draw()
    Going()
end

function B:Start()
    if self.started then return end
    self.started = true
    -- Nothing is registered and nothing is built unless the band is on, as
    -- Fill.lua's own Listen does it, so nothing of this runs while the page
    -- is unticked.
    self:Apply()
end

-- /ccm debug (Debug.lua): what the page cannot show about the band itself.
-- Never announced to players.
function B:Report(add)
    local parts = state.parts
    -- Which bar it actually took and whether that bar is the one on screen.
    -- Added 27 Nov 2026: the band reported itself found, sized and drawing
    -- while nothing showed, and without this there was no way to tell a bar
    -- that is hidden, or the wrong one of two, from a layering fault. It goes
    -- after the line above, which the suite reads as the first one.
    local function Host(which, parts)
        if not (parts and parts.bar) then return end
        local bar, fill = parts.bar, parts.fill
        local function Say(fn, host)
            if type(host) ~= "table" or type(host[fn]) ~= "function" then return "none" end
            local ok, got = pcall(host[fn], host)
            if not ok then return "refused" end
            if not Open(got) then return "secret" end
            return tostring(got)
        end
        add(("DoTs %s bar: name %s, shown %s (really visible %s), width %s, alpha %s, level %s, strata %s"
            .. " | its fill: still the bar's own %s, shown %s, width %s"):format(which,
            Say("GetName", bar), Say("IsShown", bar), Say("IsVisible", bar),
            Say("GetWidth", bar), Say("GetAlpha", bar),
            Say("GetFrameLevel", bar), Say("GetFrameStrata", bar),
            tostring(type(bar.GetStatusBarTexture) == "function"
                and ({ pcall(bar.GetStatusBarTexture, bar) })[2] == fill),
            Say("IsShown", fill), Say("GetWidth", fill)))
        -- And our own clip and band on it. Without this there is no telling a
        -- band that is drawing somewhere wrong from one that is not drawing.
        add(("DoTs %s ours: clip shown %s (really visible %s), alpha %s, level %s, strata %s, width %s, parent %s"
            .. " | band shown %s, alpha %s, width %s, value set %s"):format(which,
            Say("IsShown", parts.clip), Say("IsVisible", parts.clip), Say("GetAlpha", parts.clip),
            Say("GetFrameLevel", parts.clip), Say("GetFrameStrata", parts.clip), Say("GetWidth", parts.clip),
            Say("GetName", parts.clip and type(parts.clip.GetParent) == "function"
                and ({ pcall(parts.clip.GetParent, parts.clip) })[2] or nil),
            Say("IsShown", parts.band), Say("GetAlpha", parts.band), Say("GetWidth", parts.band),
            tostring(parts.wide)))
    end
    local pending = {}
    for key in pairs(state.pending) do pending[#pending + 1] = key end
    table.sort(pending)
    add(("DoTs band: wanted %s, on the target frame %s%s, skull %s, width %s, marking %s%s, drawing %s, health %s,"
        .. " nameplate %s%s, waiting %s"):format(
        tostring(Wanted()), tostring(self:Found()),
        state.errors.host and (" (" .. state.errors.host .. ")") or "",
        tostring(parts ~= nil and parts.skull ~= nil), tostring(parts and parts.wide or "none"),
        type(state.damage) == "number" and (state.damage .. " damage" .. (state.school and (" " .. state.school) or ""))
            or "nothing",
        type(state.theirs) == "number" and (" and " .. state.theirs .. " of theirs") or "",
        tostring(self:Drawing()),
        state.most ~= nil and (state.now ~= nil and "read" or "max only") or "none",
        ns.Get("dotNameplates") == true and tostring(state.plateOn == true) or "off",
        state.errors.plate and (" (" .. state.errors.plate .. ")") or "",
        #pending > 0 and table.concat(pending, ", ") or "none"))
    Host("band", parts)
    Host("plate", state.plateParts)
    -- The target's nameplate as it really is, two levels down, so a plate
    -- built by an addon can be read instead of guessed at. Every frame with
    -- a status bar texture is marked, with whether a player can see it.
    local plates = C_NamePlate
    local ok, plate = pcall(type(plates) == "table" and plates.GetNamePlateForUnit or function() end, "target")
    if ok and type(plate) == "table" then
        local seen, out = 0, {}
        local function Look(frame, path)
            if seen > 24 or type(frame) ~= "table" then return end
            local kids = ({ pcall(function() return { frame:GetChildren() } end) })[2]
            if type(kids) ~= "table" then return end
            for i, kid in ipairs(kids) do
                if seen > 24 then return end
                seen = seen + 1
                local isBar = type(kid) == "table" and type(kid.GetStatusBarTexture) == "function"
                local showing = type(kid) == "table" and type(kid.IsVisible) == "function"
                    and ({ pcall(kid.IsVisible, kid) })[2]
                local name = type(kid) == "table" and type(kid.GetName) == "function"
                    and ({ pcall(kid.GetName, kid) })[2] or nil
                out[#out + 1] = ("%s%d%s%s%s"):format(path, i, isBar and " BAR" or "",
                    showing == true and " seen" or " unseen", type(name) == "string" and (" " .. name) or "")
                if path == "" then Look(kid, i .. ".") end
            end
        end
        Look(plate, "")
        add("DoTs plate tree: " .. (#out > 0 and table.concat(out, " | ") or "nothing under it"))
        local pname = type(plate.GetName) == "function" and ({ pcall(plate.GetName, plate) })[2] or nil
        local function Global(suffix)
            if type(pname) ~= "string" then return "no plate name" end
            local got = _G[pname .. suffix]
            if type(got) ~= "table" then return "not there" end
            local isBar = type(got.GetStatusBarTexture) == "function"
            local showing = type(got.IsVisible) == "function" and ({ pcall(got.IsVisible, got) })[2]
            return ("there, bar %s, visible %s"):format(tostring(isBar), tostring(showing))
        end
        add(("DoTs plate names: plate %s | <plate>PlaterUnitFrame: %s | <plate>PlaterUnitFrameHealthBar: %s"):format(
            tostring(pname), Global("PlaterUnitFrame"), Global("PlaterUnitFrameHealthBar")))
    end
end
