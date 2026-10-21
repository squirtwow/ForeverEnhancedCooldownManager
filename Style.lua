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
-- A bar colour by its key; "class" is your class colour, and a Custom
-- colour's "#rrggbb" (ns.ColourKey) itself.
function S:BarColour(key)
    if key == "class" then
        local _, class = UnitClass("player")
        local colour = class and (C_ClassColor and C_ClassColor.GetClassColor and C_ClassColor.GetClassColor(class)
            or RAID_CLASS_COLORS and RAID_CLASS_COLORS[class])
        if colour then return { colour.r, colour.g, colour.b } end
    end
    return S.BAR_COLOURS[key] or ns.HexColour(key) or S.BAR_COLOURS.orange
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
-- has them. Friz Quadrata is the /ccm window's too. Game font is the one the
-- rest of the game is in, for its language: Friz Quadrata in English, a
-- Chinese, Korean or Cyrillic one where the others can't write the names.
S.FONTS = {
    friz = "Fonts\\FRIZQT__.TTF",
    arial = "Fonts\\ARIALN.TTF",
    morpheus = "Fonts\\MORPHEUS.ttf",
    skurri = "Fonts\\skurri.ttf",
}
local FONT = S.FONTS.friz
S.FONTS.game = type(STANDARD_TEXT_FONT) == "string" and STANDARD_TEXT_FONT ~= "" and STANDARD_TEXT_FONT or FONT
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

-- The same, but always in the face key (one of S.FONTS) whatever the Look
-- page's font, for text with a font of its own: the resource display's
-- health and power text. Made once and shared; a new Look page font leaves
-- them be.
local own = {}

function S:FontIn(key, size)
    local file = S.FONTS[key]
    if not file then return self:Font(size) end
    size = math.max(8, math.floor(size + .5))
    local name = "FECMFont" .. key .. size
    if not own[name] then
        local font = CreateFont(name)
        Face(font, file, size, Outline(size))
        font:SetShadowOffset(0, 0)
        font:SetTextColor(1, 1, 1)
        own[name] = font
    end
    return name
end

-- A countdown in a colour of its own (Icon details): a font for each size,
-- made once and shared, so counts and keys in that size keep theirs.
local numbers = {}

-- A new font chosen: every font made so far takes it, and the text drawn in
-- them follows by itself: countdowns, counts and keys, your cast bar, and
-- Blizzard's restyled icons and Tracked Bars, with nothing set on them again.
function S:ApplyFont()
    local file = self:FontFile()
    for size, font in pairs(made) do Face(font, file, size, Outline(size)) end
    for size, font in pairs(numbers) do Face(font, file, size, Outline(size)) end
end

-- Spell names under icons: the game's own small text (in Friz Quadrata or
-- Game font), or a copy of it in the font chosen, the same size and shadow.
local NAMES = "GameFontHighlightSmall"
local names

function S:NameFont()
    local file, small = self:FontFile(), _G[NAMES]
    if file == FONT or ns.Get("font") == "game" or not (small and small.GetFont) then return NAMES end
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

-- Countdown numbers about half the icon's height, times the size picked in
-- Icon details; stacks and counts smaller.
function S:CountdownSize(iconSize)
    local size, percent = math.max(11, iconSize * .5), ns.Get("countdownSize")
    if percent ~= 100 then size = size * percent / 100 end
    return math.floor(size + .5)
end

-- The countdown's font: the shared one for its size while the numbers are
-- white, as they always were; in another colour (Icon details), that
-- size's own font in that colour.
function S:Countdown(iconSize)
    local size, key = self:CountdownSize(iconSize), ns.ColourKey("countdownColour")
    if key == "white" then return self:Font(size) end
    size = math.max(8, size)
    local name = "FECMCountdown" .. size
    local font = numbers[size]
    if not font then
        font = CreateFont(name)
        Face(font, self:FontFile(), size, Outline(size))
        font:SetShadowOffset(0, 0)
        numbers[size] = font
    end
    if font.colourKey ~= key then
        font.colourKey = key
        local colour = ns.CountColour(key)
        font:SetTextColor(colour[1], colour[2], colour[3])
    end
    return name
end

function S:Count(iconSize)
    return self:Font(math.max(12, iconSize * .36))
end

-- A Debuffs bar icon's tick count (Buffs.lua): smaller, so in its corner it
-- stays clear of the countdown, times the size picked for it (percent).
function S:Ticks(iconSize, percent)
    return self:Font(iconSize * .28 * (percent or 100) / 100)
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

-- The track behind a bar's fill: S.TRACK (Block's warmer one while Block is
-- the design), that far toward solid black.
function S:TrackColour()
    local dark, track = self:Darkness(), self:Block() and S.BLOCK_TRACK or S.TRACK
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

-- Block ----------------------------------------------------------------------------
-- The fourth Design on the Look page, beside Glass, Split and Outline: each
-- bar in its colour with no shine, in a 1px black edge with a thin warm
-- line just inside it, on a warmer dark track, and Blizzard's Tracked Bars
-- slimmer (Skin.lua). The icons beside the bars (the Tracked Bars', your
-- cast bar's) get the same warm line. The line sits over the fill and under
-- any text, one pixel in, or two with Thick edges (inside that second black
-- pixel). Its four strips are only made the first time Block shows.
S.BLOCK_TRACK = { .11, .085, .075, .92 } -- Block's track: a warm near-black
local BLOCK_LINE = { 1, .84, .59, .35 } -- its line: a soft warm cream

function S:Block()
    return ns.Get("barStyle") == "block"
end

-- thin: on a bar that never takes Thick edges (Raid Timers'), always one pixel in.
function S:BlockLine(owner, region, thin)
    return { owner = owner, region = region, thin = thin, shown = false }
end

-- Shown while Block is the design (and shown isn't false: its icon is
-- hidden), placed again only when Thick edges changes. Only what changed is set.
function S:ShowBlockLine(line, shown)
    local on = shown ~= false and self:Block()
    if on then
        if not line[1] then
            for i = 1, 4 do
                local strip = line.owner:CreateTexture(nil, "OVERLAY", nil, -6)
                strip:SetColorTexture(BLOCK_LINE[1], BLOCK_LINE[2], BLOCK_LINE[3], BLOCK_LINE[4])
                strip:Hide()
                line[i] = strip
            end
        end
        local inset = not line.thin and ns.Get("thickEdges") == true and -2 or -1
        if line.inset ~= inset then
            line.inset = inset
            Place(line, line.region, inset)
        end
    end
    if line.shown ~= on then
        line.shown = on
        Show(line, on)
    end
end

-- Colour fade ----------------------------------------------------------------------
-- A tick on the Look page that works with any design: each bar's fill fades
-- left to right from a deeper shade of its colour into a lighter one. The
-- named colours each have a pair of their own (Orange, Purple and Blue as
-- Forever Enhanced XP Bar's fills); any other colour (your class's, a
-- Custom one, Blizzard's own on the resource display, the cast bar's gold)
-- is taken a step deeper and a step lighter. Only colours go in, never a
-- bar's values. A vertex colour wipes a gradient in the game, so it's put on
-- again each time the bar's colour is (S:FillColour). A colour the game
-- keeps secret stays flat, and should the game refuse a gradient (an error,
-- kept quietly for /ccm debug), every bar stays flat for the session.
local FADE_DEEP, FADE_LIGHT = .8, .4 -- any other colour: this much of it, and this far to white
local FADES = { -- deeper, then lighter
    [S.BAR_COLOURS.orange] = { { .94, .51, .12 }, { 1, .75, .24 } },
    [S.BAR_COLOURS.purple] = { { .42, .42, .97 }, { .77, .43, .97 } },
    [S.BAR_COLOURS.blue] = { { .23, .5, .94 }, { .5, .77, 1 } },
    [S.BAR_COLOURS.green] = { { .18, .62, .29 }, { .48, .88, .54 } },
    [S.BAR_COLOURS.charcoal] = { { .23, .24, .27 }, { .48, .5, .55 } },
}
local fadeRefused = false

-- Whether bars fade now: ticked, and the game hasn't refused one.
function S:Fades()
    return ns.Get("colourFade") == true and not fadeRefused
end

-- colour's two ends: the deeper one (left), then the lighter one.
function S:FadeEnds(colour)
    local pair = FADES[colour]
    if pair then return pair[1], pair[2] end
    local r, g, b = colour[1], colour[2], colour[3]
    return { r * FADE_DEEP, g * FADE_DEEP, b * FADE_DEEP },
        { r + (1 - r) * FADE_LIGHT, g + (1 - g) * FADE_LIGHT, b + (1 - b) * FADE_LIGHT }
end

local function Gradient(texture, from, to, alpha)
    texture:SetGradient("HORIZONTAL", CreateColor(from[1], from[2], from[3], alpha), CreateColor(to[1], to[2], to[3], alpha))
end

-- A status bar's fill in colour, alpha as see-through as it is (Outline's
-- .45), flat, then faded over that while Colour fade is ticked. True when
-- it's faded. The flat colour goes on first, so it's what shows wherever a
-- fade doesn't.
function S:FillColour(bar, colour, alpha)
    alpha = alpha or 1
    bar:SetStatusBarColor(colour[1], colour[2], colour[3], alpha)
    if not self:Fades() or type(CreateColor) ~= "function" then return false end
    if issecretvalue and (issecretvalue(colour[1]) or issecretvalue(colour[2]) or issecretvalue(colour[3])) then return false end
    local fill = bar:GetStatusBarTexture()
    if not fill then return false end
    local from, to = self:FadeEnds(colour)
    local ok, err = pcall(Gradient, fill, from, to, alpha)
    if ok then return true end
    fadeRefused = true
    S.fadeError = tostring(err)
    bar:SetStatusBarColor(colour[1], colour[2], colour[3], alpha)
    return false
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
-- box/inset: where the count sits; around: what the numbers sit on (S:NumbersAt).
function S:KeyRoom(count, box, inset, numbers, around, lift, keyed)
    if count and box then
        count:ClearAllPoints()
        if self:CountUp(keyed) then
            count:SetPoint("TOPRIGHT", box, "TOPRIGHT", -inset, -inset)
        else
            count:SetPoint("BOTTOMRIGHT", box, "BOTTOMRIGHT", -inset, inset)
        end
    end
    if numbers and around then self:NumbersAt(numbers, around, lift) end
end

-- Icon details ---------------------------------------------------------------------
-- The Look page's Icon details: the cooldown swipe's colour and how much of
-- the icon shows through it, the countdown numbers' size, colour and spot,
-- and a line along the swipe's edge. At the defaults the icons look as they
-- always have: a 70% black swipe, white numbers half the icon's height in
-- its middle, and no edge line on your bars (Blizzard's keep their own).
S.SWIPE_COLOURS = { black = { 0, 0, 0 }, white = { 1, 1, 1 } }
local UNTINTED = { 1, 1, 1 } -- the game's own edge line
local SPOT_EDGE = 1 -- a countdown in a corner or along an edge: this far in from the art's edge
local SPOTS = { -- x and y offset directions (times SPOT_EDGE), from the spot's own point on the icon
    TOPLEFT = { 1, -1 }, TOP = { 0, -1 }, TOPRIGHT = { -1, -1 },
    BOTTOMLEFT = { 1, 1 }, BOTTOM = { 0, 1 }, BOTTOMRIGHT = { -1, 1 },
}

-- A swipe colour by its key: black, white, a bar colour or Custom's "#rrggbb".
function S:SwipeColour(key)
    return S.SWIPE_COLOURS[key] or self:BarColour(key)
end

-- The swipe as picked: its colour, and how much of it shows (1 solid).
function S:Swipe()
    return self:SwipeColour(ns.ColourKey("swipeColour")), (100 - ns.Get("swipeSeeThrough")) / 100
end

-- The edge line's tint by its key: none for the game's own line, else a bar
-- colour or Custom's "#rrggbb".
function S:EdgeColour(key)
    if key == "game" then return UNTINTED end
    return self:BarColour(key)
end

-- Whether the swipe or its edge line differ from the defaults: until they
-- do, Blizzard's icons are left exactly as Blizzard draws them.
function S:SwipeChanged()
    return ns.Get("swipeColour") ~= ns.DEFAULTS.swipeColour or ns.Get("swipeSeeThrough") ~= ns.DEFAULTS.swipeSeeThrough
        or ns.Get("swipeEdge") == true
end

-- One of the addon's own cooldowns (your bars' icons, their buff and debuff
-- times, the Buffs and Debuffs bars' icons, the panel's preview) in the
-- swipe and edge line picked. At the defaults these are the calls each was
-- always made with: a 70% black swipe and no edge line.
function S:CooldownLook(cooldown)
    local colour, alpha = self:Swipe()
    cooldown:SetSwipeColor(colour[1], colour[2], colour[3], alpha)
    local edge = ns.Get("swipeEdge") == true
    cooldown:SetDrawEdge(edge)
    if edge then
        local tint = self:EdgeColour(ns.ColourKey("edgeColour"))
        cooldown:SetEdgeColor(tint[1], tint[2], tint[3], 1)
    end
end

-- The countdown's numbers in the spot picked: in the middle (moved up or
-- down by lift, clear of a key), or in a corner or along an edge, just in
-- from it. around: the art they sit on (its cooldown).
function S:NumbersAt(numbers, around, lift)
    local spot = ns.Get("countdownSpot")
    local at = SPOTS[spot]
    numbers:ClearAllPoints()
    if at then
        numbers:SetPoint(spot, around, spot, at[1] * SPOT_EDGE, at[2] * SPOT_EDGE)
    else
        numbers:SetPoint("CENTER", around, "CENTER", 0, lift or 0)
    end
end

-- An aura icon's countdown (the Buffs and Debuffs bars', and the buff and
-- debuff times over your cooldown icons: the game's aura containers' own
-- icons) in the spot picked. Left where the game puts it, the middle, until
-- a spot is picked; after that, set again only when the spot changes.
-- parts: the icon's { cooldown }, which keeps the spot set last.
function S:AuraNumbers(parts)
    local spot = ns.Get("countdownSpot")
    if parts.spot == spot or (parts.spot == nil and spot == "CENTER") then return end
    local get = parts.cooldown.GetCountdownFontString
    local found = type(get) == "function" and get(parts.cooldown) or nil
    if not found then return end
    parts.spot = spot
    self:NumbersAt(found, parts.cooldown, 0)
end

-- Every icon again after a change in Icon details: your bars' and Blizzard's.
function S:ApplyDetails()
    if ns.Bars and ns.Bars.started then ns.Bars:ApplyIconDetails() end
    if ns.Skin and ns.Skin.started then ns.Skin:ApplyIconDetails() end
end
