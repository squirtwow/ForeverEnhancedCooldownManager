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

local FONT = "Fonts\\FRIZQT__.TTF" -- the game's own font, as in the /fecm window
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
