-- The look shared by Blizzard's restyled Cooldown Manager and the addon's own
-- bars: square icon art zoomed past its built-in bevel with no frame around
-- it, big bold countdown numbers, and flat charcoal bars.
local _, ns = ...

local S = {}
ns.Style = S

S.FLAT = "Interface\\Buttons\\WHITE8X8"
S.FILL = { .36, .38, .41 } -- a bar's fill
S.TRACK = { .08, .08, .09, .85 } -- behind a bar's fill
S.ZOOM = { .08, .92, .08, .92 } -- trims the icon art's own bevelled edge

local FONT = "Fonts\\ARIALN.TTF"
local made = {}

-- A bold outlined font of the given size, made once and shared.
function S:Font(size)
    size = math.max(8, math.floor(size + .5))
    local name = "FECMFont" .. size
    if not made[size] then
        local font = CreateFont(name)
        font:SetFont(FONT, size, "OUTLINE")
        font:SetShadowOffset(1, -1)
        font:SetShadowColor(0, 0, 0, 1)
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
