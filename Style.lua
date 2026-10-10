-- The look shared by Blizzard's restyled Cooldown Manager and the addon's own
-- bars: square icon art zoomed past its built-in bevel with no frame around
-- it, big bold countdown numbers, and bars in a colour of your choice. The
-- font and the bars' texture can be chosen too, on the Look page.
local _, ns = ...

local S = {}
ns.Style = S

S.FLAT = "Interface\\Buttons\\WHITE8X8"
-- Colours for Blizzard's Tracked Bars; "class" (not listed) is your class colour.
S.BAR_COLOURS = {
    orange = { 1, .5, .25 }, -- Blizzard's own
    charcoal = { .36, .38, .41 },
    blue = { .24, .55, .88 },
    green = { .38, .74, .30 },
    purple = { .6, .43, .91 },
}
-- A bar colour by its key; "class" is your class colour.
function S:BarColour(key)
    if key == "class" then
        local _, class = UnitClass("player")
        local colour = class and (C_ClassColor and C_ClassColor.GetClassColor and C_ClassColor.GetClassColor(class)
            or RAID_CLASS_COLORS and RAID_CLASS_COLORS[class])
        if colour then return { colour.r, colour.g, colour.b } end
    end
    return S.BAR_COLOURS[key] or S.BAR_COLOURS.orange
end
S.TRACK = { .08, .08, .09, .85 } -- behind a bar's fill
S.ZOOM = { .08, .92, .08, .92 } -- trims the icon art's own bevelled edge

-- The fills a bar can have, as chosen on the Look page: flat colour, or one
-- of the game's own bar textures, each tinted in the bar's colour.
S.BAR_TEXTURES = {
    flat = S.FLAT,
    classic = "Interface\\TargetingFrame\\UI-StatusBar", -- the unit frames' bars
    raid = "Interface\\RaidFrame\\Raid-Bar-Hp-Fill", -- the raid frames' health bars
    skills = "Interface\\PaperDollInfoFrame\\UI-Character-Skills-Bar", -- the character sheet's skill bars
}

function S:BarTexture()
    return S.BAR_TEXTURES[ns.Get("barTexture")] or S.FLAT
end

-- The fonts the numbers and text can be in: the game's own, so every player
-- has them. Friz Quadrata is the /ccm window's too.
S.FONTS = {
    friz = "Fonts\\FRIZQT__.TTF",
    arial = "Fonts\\ARIALN.TTF",
    morpheus = "Fonts\\MORPHEUS.ttf",
    skurri = "Fonts\\skurri.ttf",
}
local FONT = S.FONTS.friz
local THICK = 16 -- from this size up, a heavier outline
local made = {}

function S:FontFile()
    return S.FONTS[ns.Get("font")] or FONT
end

-- Puts a font in file at its size, or in Friz Quadrata should the game ever
-- refuse file, so the text never goes blank.
local function Face(font, file, size, flags)
    if file ~= FONT then
        local ok, done = pcall(font.SetFont, font, file, size, flags)
        if ok and done ~= false then return end
    end
    font:SetFont(FONT, size, flags)
end

local function Outline(size)
    return size >= THICK and "THICKOUTLINE" or "OUTLINE"
end

-- An outlined font of the given size, made once and shared. No drop shadow,
-- so the numbers stay crisp over bright icon art.
function S:Font(size)
    size = math.max(8, math.floor(size + .5))
    local name = "FECMFont" .. size
    if not made[size] then
        local font = CreateFont(name)
        Face(font, self:FontFile(), size, Outline(size))
        font:SetShadowOffset(0, 0)
        font:SetTextColor(1, 1, 1)
        made[size] = font
    end
    return name
end

-- A new font chosen: every font made so far takes it, and the text drawn in
-- them follows by itself: countdowns, counts and keys, your cast bar, and
-- Blizzard's restyled icons and Tracked Bars, with nothing set on them again.
function S:ApplyFont()
    local file = self:FontFile()
    for size, font in pairs(made) do Face(font, file, size, Outline(size)) end
end

-- Spell names under icons: the game's own small text, or a copy of it in the
-- font chosen, the same size and shadow.
local NAMES = "GameFontHighlightSmall"
local names

function S:NameFont()
    local file, small = self:FontFile(), _G[NAMES]
    if file == FONT or not (small and small.GetFont) then return NAMES end
    if not names then
        names = CreateFont("FECMNames")
        names:CopyFontObject(small)
    end
    local _, size, flags = small:GetFont()
    Face(names, file, size or 10, flags or "")
    return "FECMNames"
end

-- Each font's name in its own face, for the Look page to pick from.
local samples = {}

function S:SampleFont(key)
    local name = "FECMSample" .. key
    if not samples[key] then
        local font = CreateFont(name)
        Face(font, S.FONTS[key] or FONT, 11, "")
        font:SetShadowOffset(1, -1)
        samples[key] = font
    end
    return name
end

-- Countdown numbers about half the icon's height; stacks and counts smaller.
function S:CountdownSize(iconSize)
    return math.floor(math.max(11, iconSize * .5) + .5)
end

function S:Countdown(iconSize)
    return self:Font(self:CountdownSize(iconSize))
end

function S:Count(iconSize)
    return self:Font(math.max(12, iconSize * .36))
end

function S:Zoom(texture)
    texture:SetTexCoord(S.ZOOM[1], S.ZOOM[2], S.ZOOM[3], S.ZOOM[4])
end

-- Borders and shadows --------------------------------------------------------------
-- Around each icon or around a whole bar, as chosen on the Look page: a 1px
-- black border on the edge, and a soft shadow fading out past it. Both are
-- rings of plain colour, so they stay sharp at any size.
local SHADOW = { .55, .35, .18, .07 } -- the shadow's rings, from the inside out

-- A 1px black ring of four strips, hidden until placed and shown.
local function Ring(owner, layer, sublevel, alpha)
    local ring = {}
    for i = 1, 4 do
        ring[i] = owner:CreateTexture(nil, layer, nil, sublevel)
        ring[i]:SetColorTexture(0, 0, 0, alpha)
        ring[i]:Hide()
    end
    return ring
end

-- Puts a ring round region, `out` pixels outside its edge.
local function Place(ring, region, out)
    local top, bottom, left, right = ring[1], ring[2], ring[3], ring[4]
    top:ClearAllPoints()
    top:SetPoint("BOTTOMLEFT", region, "TOPLEFT", -(out + 1), out)
    top:SetPoint("BOTTOMRIGHT", region, "TOPRIGHT", out + 1, out)
    top:SetHeight(1)
    bottom:ClearAllPoints()
    bottom:SetPoint("TOPLEFT", region, "BOTTOMLEFT", -(out + 1), -out)
    bottom:SetPoint("TOPRIGHT", region, "BOTTOMRIGHT", out + 1, -out)
    bottom:SetHeight(1)
    left:ClearAllPoints()
    left:SetPoint("TOPRIGHT", region, "TOPLEFT", -out, out)
    left:SetPoint("BOTTOMRIGHT", region, "BOTTOMLEFT", -out, -out)
    left:SetWidth(1)
    right:ClearAllPoints()
    right:SetPoint("TOPLEFT", region, "TOPRIGHT", out, out)
    right:SetPoint("BOTTOMLEFT", region, "BOTTOMRIGHT", out, -out)
    right:SetWidth(1)
end

local function Show(ring, shown)
    for _, strip in ipairs(ring) do strip:SetShown(shown) end
end

-- The rings themselves, on the decor's owner, all hidden.
local function Rings(decor)
    local owner = decor.owner
    decor.border, decor.shadow = Ring(owner, "BORDER", -8, 1), {}
    for i, alpha in ipairs(SHADOW) do decor.shadow[i] = Ring(owner, "BACKGROUND", -8, alpha) end
    decor.borderShown, decor.shadowShown = false, false
end

-- The pieces for one icon or bar, on owner around region. inset: how far
-- inside region the icon art's edge is. Both are off unless chosen, so the
-- rings (20 textures) are only made the first time either is shown; now
-- makes them at once (an icon of Blizzard's aura container, which only
-- takes art as it's made).
function S:Decor(owner, region, inset, now)
    local decor = { owner = owner, region = region, inset = inset or 0 }
    if now then Rings(decor) end
    return decor
end

-- Whether the border and the shadow go round each icon ("icon") or round
-- whole bars ("bar"), as chosen.
function S:DecorFor(scope)
    return ns.Get("iconBorder") == scope, ns.Get("iconShadow") == scope
end

-- Shows or hides the border and the shadow; the shadow starts outside the
-- border when both show. Only what changed is set: the rings are placed
-- again when where they go changes (and not while both are off), and shown
-- or hidden when that changes. Blizzard's rows ask on every relayout, your
-- cast bar on every cast.
function S:ShowDecor(decor, border, shadow)
    if not decor then return end
    border, shadow = border and true or false, shadow and true or false
    if not decor.border then
        if not (border or shadow) then return end
        Rings(decor)
    end
    local region, inset = decor.region, decor.inset
    if (border or shadow) and (decor.placed ~= region or decor.placedInset ~= inset or decor.placedBorder ~= border) then
        decor.placed, decor.placedInset, decor.placedBorder = region, inset, border
        local start = -inset
        Place(decor.border, region, start)
        for i, ring in ipairs(decor.shadow) do Place(ring, region, start + (border and 1 or 0) + i - 1) end
    end
    if decor.borderShown ~= border then
        decor.borderShown = border
        Show(decor.border, border)
    end
    if decor.shadowShown ~= shadow then
        decor.shadowShown = shadow
        for _, ring in ipairs(decor.shadow) do Show(ring, shadow) end
    end
end

-- Darkness and thick edges ---------------------------------------------------------
-- Two choices on the Look page for your cast bar and swing timer, combo
-- points, the resource display and Blizzard's Tracked Bars: how dark the
-- empty part of each bar is, and a 2px edge instead of 1px. Both off by
-- default, so the bars look as they always have. The fill never changes.
local SHEEN = .16 -- Glass's shine

-- How far the empty part goes from today's track (0) to solid black (1).
function S:Darkness()
    return ns.Get("barDarkness") / 100
end

-- The track behind a bar's fill: S.TRACK, that far toward solid black.
function S:TrackColour()
    local dark, track = self:Darkness(), S.TRACK
    local keep = 1 - dark
    return track[1] * keep, track[2] * keep, track[3] * keep, track[4] + (1 - track[4]) * dark
end

-- Glass's shine on a bar: `over`, the bar's own shine texture across its top
-- half (or a strip `height` tall along its top), and while the bars are
-- darkened `rest` too, so the shine splits where the fill ends: `over` stops
-- there, and `rest` covers the empty part, fading as the darkness grows, so a
-- dark bar's empty part stays dark. Nothing else goes over the empty part,
-- so Blizzard's heal prediction on the health bar still shows. Unsplit,
-- `over` runs the whole bar as the shine always has.
local function Span(sheen, fill)
    local bar, height, over, rest = sheen.bar, sheen.height, sheen.over, sheen.rest
    local stop = fill or bar
    over:ClearAllPoints()
    over:SetPoint("TOPLEFT", bar, "TOPLEFT", 0, 0)
    if height then
        over:SetPoint("TOPRIGHT", stop, "TOPRIGHT", 0, 0)
    else
        over:SetPoint("BOTTOMRIGHT", stop, "RIGHT", 0, 0)
    end
    if not fill then return end
    rest:ClearAllPoints()
    rest:SetPoint("TOPLEFT", fill, "TOPRIGHT", 0, 0)
    if height then
        rest:SetPoint("TOPRIGHT", bar, "TOPRIGHT", 0, 0)
    else
        rest:SetPoint("BOTTOMRIGHT", bar, "RIGHT", 0, 0)
    end
end

-- The shine on bar, from its own texture `over`, placed as it always was.
-- The empty part's is only made the first time the bars are darkened, so
-- nothing more is made while darkness stays at 0.
function S:Sheen(bar, over, height)
    return { bar = bar, over = over, height = height }
end

-- Shows the shine for Glass (glass true), split where the fill ends while
-- the bars are darkened. It's anchored again only when that changes or the
-- fill does (a new texture can bring a new one), and the empty part's shine
-- set only when the darkness changes. A bar that can't say where its fill
-- is keeps the whole shine.
function S:ShowSheen(sheen, glass)
    local dark = self:Darkness()
    local fill = glass and dark > 0 and sheen.bar:GetStatusBarTexture() or nil
    if fill ~= sheen.fill then
        sheen.fill = fill
        if fill and not sheen.rest then
            sheen.rest = sheen.bar:CreateTexture(nil, "OVERLAY", nil, -8)
            if sheen.height then sheen.rest:SetHeight(sheen.height) end
        end
        Span(sheen, fill)
    end
    sheen.over:SetShown(glass)
    if sheen.rest then sheen.rest:SetShown(fill ~= nil) end
    if not fill then return end
    local alpha = SHEEN * (1 - dark)
    if sheen.alpha ~= alpha then
        sheen.alpha = alpha
        sheen.rest:SetColorTexture(1, 1, 1, alpha)
    end
end

-- Thick edges: a second pixel just inside region's 1px edge (a bar's, or an
-- icon's beside one), so every size and gap stays as it is. Over the fill,
-- the art, Glass's shine and Split's box, under any text. Its four strips
-- are only made the first time it shows, as the borders' rings are.
function S:InnerEdge(owner, region)
    return { owner = owner, region = region, r = 0, g = 0, b = 0, shown = false }
end

-- Shown while Thick edges is on (and shown isn't false: its icon is
-- hidden), in colour like the edge it thickens. Only what changed is set.
function S:ShowInnerEdge(ring, colour, shown)
    local thick = shown ~= false and ns.Get("thickEdges") == true
    if thick and not ring[1] then
        for i, strip in ipairs(Ring(ring.owner, "OVERLAY", -5, 1)) do ring[i] = strip end
        Place(ring, ring.region, -1)
    end
    if thick and (ring.r ~= colour[1] or ring.g ~= colour[2] or ring.b ~= colour[3]) then
        ring.r, ring.g, ring.b = colour[1], colour[2], colour[3]
        for _, strip in ipairs(ring) do strip:SetColorTexture(colour[1], colour[2], colour[3], 1) end
    end
    if ring.shown ~= thick then
        ring.shown = thick
        Show(ring, thick)
    end
end

-- Keybinds -------------------------------------------------------------------------
-- The key that casts an icon's spell, in one corner or along one edge of its
-- art, sized with the icon. Your bars, Blizzard's icons and the Look page's
-- preview all draw it here, so they always match.
local KEY_SHARE = .3 -- automatic size: this share of the icon art's size (36 -> 11, below the count's 13)
local KEY_MIN = 8 -- smallest readable text; also S:Font's floor
local KEY_GLYPH = .75 -- how tall numbers and capitals draw, as a share of the font size
local KEY_EDGE = 2 -- from the icon art's edge
local KEY_GAP = 1 -- between the key and the countdown's numbers
S.KEY_COLOUR = { .9, .9, .9 } -- near white, just under the countdown's pure white
local KEY_POINTS = { -- point on the art, x/y offset direction (times KEY_EDGE), justification
    BOTTOM = { "BOTTOM", 0, 1, "CENTER" }, TOP = { "TOP", 0, -1, "CENTER" },
    TOPLEFT = { "TOPLEFT", 1, -1, "LEFT" }, TOPRIGHT = { "TOPRIGHT", -1, -1, "RIGHT" },
}

-- The key's automatic size on an icon: a share of its art, times the size chosen.
local function Wanted(art, scale)
    return math.floor(art * KEY_SHARE * scale / 100 + .5)
end

-- Size for an icon's key, and how far its countdown moves to stay clear (+ up for a
-- bottom key, - down for a top one). art: the icon art's size; countdown: its font size.
function S:KeyFit(art, countdown, position, scale)
    local half = KEY_GLYPH * countdown / 2
    local room = art / 2 - half -- edge to the countdown's numbers
    local most = math.floor((art - 2 * half - KEY_EDGE - KEY_GAP - 1) / KEY_GLYPH) -- countdown moved as far as it may go
    local size = Wanted(art, scale)
    size = math.max(KEY_MIN, math.min(size, most))
    local need = KEY_EDGE + KEY_GLYPH * size + KEY_GAP - room
    local lift = need > 0 and math.ceil(need) or 0
    if position ~= "BOTTOM" then lift = -lift end
    return size, lift
end

-- Whether a key reads on an icon this small, whatever size is chosen: the icon is
-- at least as big as the smallest your bars can have, where KeyFit still fits it
-- inside the art and clear of the countdown. The Layout page's small drawing of
-- your bars leaves it off on smaller tiles, rather than draw a smudge; on the rest
-- the size chosen only resizes it, as on your bars.
function S:KeyReadable(art)
    return art >= ns.BAR_LIMITS.size[1]
end

-- The addon's own text for a key, on parent (a frame above the icon's sweep), hidden until it has one.
function S:KeyText(parent)
    local text = parent:CreateFontString(nil, "OVERLAY")
    text:SetFontObject(self:Font(KEY_MIN))
    text:SetTextColor(S.KEY_COLOUR[1], S.KEY_COLOUR[2], S.KEY_COLOUR[3])
    text:SetWordWrap(false)
    text:SetJustifyH("CENTER")
    text:SetWidth(20)
    text:SetPoint("BOTTOM", parent, "BOTTOM", 0, KEY_EDGE)
    text:Hide()
    return text -- no height: a FontString shorter than its font draws nothing
end

-- Places and sizes it as chosen; returns the countdown's lift (0 with keybinds off).
function S:KeyLook(text, region, art, countdown)
    local position = ns.Get("keybindPosition")
    local size, lift = self:KeyFit(art, countdown, position, ns.Get("keybindSize"))
    local at = KEY_POINTS[position] or KEY_POINTS.BOTTOM
    text:SetFontObject(self:Font(size))
    text:SetTextColor(S.KEY_COLOUR[1], S.KEY_COLOUR[2], S.KEY_COLOUR[3])
    -- One line as wide as the art: a long key is cut short, as Blizzard's own are.
    text:SetWidth(math.max(1, art - 2 * KEY_EDGE))
    text:SetJustifyH(at[4])
    text:ClearAllPoints()
    text:SetPoint(at[1], region, at[1], at[2] * KEY_EDGE, at[3] * KEY_EDGE)
    return ns.Get("keybinds") and lift or 0
end

-- The key, or nothing (no key, or keybinds off). Text only: safe in combat.
-- Returns whether it shows, for where the icon's count goes.
function S:SetKey(text, key)
    local shown = ns.Get("keybinds") and key ~= nil or false
    text:SetText(key or "")
    text:SetShown(shown)
    return shown
end

-- Whether an icon's count goes top-right: only while its own key shows along the bottom.
function S:CountUp(keyed)
    return keyed == true and ns.Get("keybinds") == true and ns.Get("keybindPosition") == "BOTTOM"
end

-- Room for the key: the count goes top-right while the icon's key shows along the bottom (keyed),
-- bottom-right otherwise, as on an icon with no key; the countdown's numbers move by lift.
-- box/inset: where the count sits; around: what the numbers centre on.
function S:KeyRoom(count, box, inset, numbers, around, lift, keyed)
    if count and box then
        count:ClearAllPoints()
        if self:CountUp(keyed) then
            count:SetPoint("TOPRIGHT", box, "TOPRIGHT", -inset, -inset)
        else
            count:SetPoint("BOTTOMRIGHT", box, "BOTTOMRIGHT", -inset, inset)
        end
    end
    if numbers and around then
        numbers:ClearAllPoints()
        numbers:SetPoint("CENTER", around, "CENTER", 0, lift)
    end
end
