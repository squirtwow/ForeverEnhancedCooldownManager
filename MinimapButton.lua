-- The minimap button: click for the settings, right-click for What's new,
-- drag it round the minimap. A sibling of EraUI's: a dark circle in the
-- minimap's gold ring, with this addon's cooldown sweep. The General page
-- turns it off.
local _, ns = ...

local M = {}
ns.MinimapButton = M

local RING_GAP = 4 -- how far out from the minimap's edge it sits
local AFTER_DRAG = .2 -- a click this soon after a drag is the drag letting go
local atan2 = math.atan2 or math.atan

local button, dragAngle
local dropped = -math.huge

-- Round the minimap's edge at the saved angle: degrees anticlockwise from the
-- right, so 225 is the bottom left. While dragging, where the cursor is.
function M:Place()
    if not button then return end
    local angle = math.rad(dragAngle or ns.Get("minimapAngle"))
    local radius = Minimap:GetWidth() / 2 + RING_GAP
    button:ClearAllPoints()
    button:SetPoint("CENTER", Minimap, "CENTER", math.cos(angle) * radius, math.sin(angle) * radius)
end

local function Follow()
    local x, y = Minimap:GetCenter()
    if not x then return end
    local scale = Minimap:GetEffectiveScale()
    local cursorX, cursorY = GetCursorPosition()
    dragAngle = math.floor(math.deg(atan2(cursorY / scale - y, cursorX / scale - x)) + .5) % 360
    M:Place()
end

-- Saved once, where it was let go.
local function Drop(self)
    self:SetScript("OnUpdate", nil)
    self.isMoving = nil
    dropped = GetTime()
    local angle = dragAngle
    dragAngle = nil
    if angle then ns.Set("minimapAngle", angle) end
    M:Place()
end

function M:Apply()
    if not button then return end
    button:SetShown(ns.Get("minimap"))
    self:Place()
end

function M:Button()
    return button
end

function M:Start()
    if button or not Minimap then return end
    button = CreateFrame("Button", "FECMMinimapButton", Minimap)
    button:SetSize(32, 32)
    button:SetFrameStrata("MEDIUM")
    button:SetFrameLevel(Minimap:GetFrameLevel() + 8)
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
        GameTooltip:Hide()
        self.isMoving = true
        self:SetScript("OnUpdate", Follow)
    end)
    button:SetScript("OnDragStop", Drop)
    -- Hidden mid-drag: let go there, so it doesn't trail the cursor later.
    button:SetScript("OnHide", function(self)
        if self.isMoving then Drop(self) end
    end)
    button:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_LEFT")
        GameTooltip:SetText(ns.TITLE)
        GameTooltip:AddLine("Click: settings", 1, 1, 1)
        GameTooltip:AddLine("Right-click: What's new", 1, 1, 1)
        GameTooltip:AddLine("Drag: move it round the minimap", 1, 1, 1)
        GameTooltip:Show()
    end)
    button:SetScript("OnLeave", function() GameTooltip:Hide() end)
    -- The minimap can change size (EraUI's can): stay on its edge.
    Minimap:HookScript("OnSizeChanged", function() M:Place() end)
    self:Apply()
end
