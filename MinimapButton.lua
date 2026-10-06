-- The minimap button: click for the settings, right-click for What's new,
-- drag it round the minimap. A sibling of EraUI's: a dark circle in the
-- minimap's gold ring, with this addon's cooldown sweep. The General page
-- turns it off, or sets it free-floating: dragged anywhere on the screen, and
-- showing even with the minimap hidden.
local _, ns = ...

local M = {}
ns.MinimapButton = M

-- Its tooltip is the addon's own (Theme.lua), never the game's: an addon
-- writing into the game's tooltip taints it, and in Forever it then breaks on
-- your hidden health every frame it shows a player (thousands of errors).
local TIP = "Click: settings\nRight-click: What's new\nDrag: move it round the minimap"
local TIP_FREE = "Click: settings\nRight-click: What's new\nDrag: move it anywhere"

local RING_GAP = 4 -- how far out from the minimap's edge it sits
local AFTER_DRAG = .2 -- a click this soon after a drag is the drag letting go
local atan2 = math.atan2 or math.atan

local button, dragAngle, dragX, dragY
local dropped = -math.huge

local function Limit(value)
    local limits = ns.MINIMAP_PLACE
    return math.max(limits[1], math.min(limits[2], math.floor(value + .5)))
end

-- Round the minimap's edge at the saved angle: degrees anticlockwise from the
-- right, so 225 is the bottom left. Free-floating, where it was dropped, from
-- the middle of the screen. While dragging, where the cursor is.
function M:Place()
    if not button then return end
    button:ClearAllPoints()
    if ns.Get("minimapFree") then
        button:SetPoint("CENTER", UIParent, "CENTER", dragX or ns.Get("minimapX"), dragY or ns.Get("minimapY"))
        return
    end
    local angle = math.rad(dragAngle or ns.Get("minimapAngle"))
    local radius = Minimap:GetWidth() / 2 + RING_GAP
    button:SetPoint("CENTER", Minimap, "CENTER", math.cos(angle) * radius, math.sin(angle) * radius)
end

local function Follow()
    local cursorX, cursorY = GetCursorPosition()
    if ns.Get("minimapFree") then
        local x, y = UIParent:GetCenter()
        if not x then return end
        local scale = UIParent:GetEffectiveScale()
        dragX, dragY = Limit(cursorX / scale - x), Limit(cursorY / scale - y)
    else
        local x, y = Minimap:GetCenter()
        if not x then return end
        local scale = Minimap:GetEffectiveScale()
        dragAngle = math.floor(math.deg(atan2(cursorY / scale - y, cursorX / scale - x)) + .5) % 360
    end
    M:Place()
end

-- Saved once, where it was let go.
local function Drop(self)
    self:SetScript("OnUpdate", nil)
    self.isMoving = nil
    dropped = GetTime()
    local angle, x, y = dragAngle, dragX, dragY
    dragAngle, dragX, dragY = nil, nil, nil
    if angle then ns.Set("minimapAngle", angle) end
    if x then
        ns.Set("minimapX", x)
        ns.Set("minimapY", y)
    end
    M:Place()
end

-- On the minimap, or on the screen itself while free-floating, so it shows
-- with the minimap hidden.
function M:Apply()
    if not button then return end
    local holder = ns.Get("minimapFree") and UIParent or Minimap
    button:SetParent(holder)
    button:SetFrameStrata("MEDIUM")
    button:SetFrameLevel(holder:GetFrameLevel() + 8)
    button:SetShown(ns.Get("minimap"))
    self:Place()
end

-- Free-floating on or off. Set free, it stays just where it is on the
-- minimap until it's dragged.
function M:SetFree(free)
    if free and button and not ns.Get("minimapFree") then
        local x, y = button:GetCenter()
        local midX, midY = UIParent:GetCenter()
        if x and y and midX and midY then
            local scale = button:GetEffectiveScale() / UIParent:GetEffectiveScale()
            ns.Set("minimapX", Limit(x * scale - midX))
            ns.Set("minimapY", Limit(y * scale - midY))
        end
    end
    ns.Set("minimapFree", free and true or false)
    self:Apply()
end

function M:Button()
    return button
end

function M:Start()
    if button or not Minimap then return end
    button = CreateFrame("Button", "FECMMinimapButton", Minimap)
    button:SetSize(32, 32)
    button:SetClampedToScreen(true)
    local back = button:CreateTexture(nil, "BACKGROUND")
    back:SetTexture("Interface\\CharacterFrame\\TempPortraitAlphaMask")
    back:SetSize(20, 20)
    back:SetPoint("CENTER")
    back:SetVertexColor(.067, .071, .082)
    local sweep = button:CreateTexture(nil, "ARTWORK")
    sweep:SetTexture(ns.MEDIA .. "MinimapIcon.tga")
    sweep:SetSize(14, 14)
    sweep:SetPoint("CENTER")
    local ring = button:CreateTexture(nil, "OVERLAY")
    ring:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")
    ring:SetSize(54, 54)
    ring:SetPoint("TOPLEFT")
    button:SetHighlightTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight", "ADD")
    button:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    button:RegisterForDrag("LeftButton")
    button:SetScript("OnClick", function(_, click)
        if GetTime() - dropped < AFTER_DRAG then return end
        if click == "RightButton" then
            if ns.ShowNotes then ns.ShowNotes() end
        else
            ns.Toggle()
        end
    end)
    -- isMoving tells minimap tidiers (EraUI's Clean minimap) not to fade it
    -- mid-drag, when the cursor can be well off the button.
    button:SetScript("OnDragStart", function(self)
        ns.Theme:HideTip(self)
        self.isMoving = true
        self:SetScript("OnUpdate", Follow)
    end)
    button:SetScript("OnDragStop", Drop)
    -- Hidden mid-drag: let go there, so it doesn't trail the cursor later.
    button:SetScript("OnHide", function(self)
        if self.isMoving then Drop(self) end
    end)
    button:SetScript("OnEnter", function(self)
        ns.Theme:ShowTip(self, ns.TITLE, ns.Get("minimapFree") and TIP_FREE or TIP, "below")
    end)
    button:SetScript("OnLeave", function(self) ns.Theme:HideTip(self) end)
    -- The minimap can change size (EraUI's can): stay on its edge.
    Minimap:HookScript("OnSizeChanged", function() M:Place() end)
    self:Apply()
end
