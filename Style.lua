-- The look shared by Blizzard's restyled Cooldown Manager and the addon's own
-- bars: square icon art zoomed past its built-in bevel with no frame around
-- it, big bold countdown numbers, and flat bars in a colour of your choice.
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

local FONT = "Fonts\\FRIZQT__.TTF" -- the game's own font, as in the /ccm window
local THICK = 16 -- from this size up, a heavier outline
local made = {}

-- An outlined font of the given size, made once and shared. No drop shadow,
-- so the numbers stay crisp over bright icon art.
function S:Font(size)
    size = math.max(8, math.floor(size + .5))
    local name = "FECMFont" .. size
    if not made[size] then
        local font = CreateFont(name)
        font:SetFont(FONT, size, size >= THICK and "THICKOUTLINE" or "OUTLINE")
        font:SetShadowOffset(0, 0)
        font:SetTextColor(1, 1, 1)
        made[size] = font
    end
    return name
end

-- Countdown numbers about half the icon's height; stacks and counts smaller.
function S:Countdown(iconSize)
    return self:Font(math.max(11, iconSize * .5))
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

-- The pieces for one icon or bar, made on owner around region, all hidden.
-- inset: how far inside region the icon art's edge is.
function S:Decor(owner, region, inset)
    local decor = { region = region, inset = inset or 0, border = Ring(owner, "BORDER", -8, 1), shadow = {} }
    for i, alpha in ipairs(SHADOW) do decor.shadow[i] = Ring(owner, "BACKGROUND", -8, alpha) end
    return decor
end

-- Whether the border and the shadow go round each icon ("icon") or round
-- whole bars ("bar"), as chosen.
function S:DecorFor(scope)
    return ns.Get("iconBorder") == scope, ns.Get("iconShadow") == scope
end

-- Shows or hides the border and the shadow; the shadow starts outside the
-- border when both show.
function S:ShowDecor(decor, border, shadow)
    if not decor then return end
    local start = -decor.inset
    Place(decor.border, decor.region, start)
    Show(decor.border, border)
    for i, ring in ipairs(decor.shadow) do
        Place(ring, decor.region, start + (border and 1 or 0) + i - 1)
        Show(ring, shadow)
    end
end
