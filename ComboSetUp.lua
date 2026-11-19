-- The combo points' height and spot (a player's idea): a small pop-up from
-- the Look page's Set up, beside the Combo points tick. Height: as tall as
-- the power bar until you move it, or 3 to 30. Spot: under the display's
-- lowest bar, as before, or over its health bar; the cast bar, swing timer
-- and your rows move so nothing overlaps (Resource.lua, Layout.lua). It
-- works with the tick off too: the settings wait for when it's on. A window
-- pop-up (ns.PagePopup): one at a time, gone on Escape, a click elsewhere,
-- another page or the window closing.
local _, ns = ...
local T = ns.Theme

local WIDTH, HEIGHT = 230, 86

function ns.ComboSetUp(window)
    local popup = ns.PagePopup(window, WIDTH, HEIGHT)
    local function Apply()
        if ns.Resource then ns.Resource:Apply() end
    end
    local title = T:Heading(popup, "Combo points")
    title:SetPoint("TOPLEFT", 10, -10)
    local reset = T:Button(popup, "Reset", 54, 18)
    reset:SetPoint("TOPRIGHT", -8, -6)
    local height = T:Slider(popup, "Height", { ns.COMBO_HEIGHT_LOW, ns.COMBO_HEIGHT[2] }, 1, WIDTH - 20, function(value)
        ns.Set("prdComboHeight", value)
        Apply()
    end, 56)
    height:SetPoint("TOPLEFT", 10, -32)
    local spotLabel = T:Text(popup, "GameFontHighlight")
    spotLabel:SetPoint("TOPLEFT", 10, -62)
    spotLabel:SetText("Spot")
    local spot = T:Segmented(popup, { { key = "below", label = "Below" }, { key = "above", label = "Above" } }, 120, function(key)
        ns.Set("prdComboAt", key)
        popup:Refresh()
        Apply()
    end)
    spot:SetPoint("TOPLEFT", 60, -58)
    reset:SetScript("OnClick", function()
        ns.Set("prdComboHeight", 0)
        ns.Set("prdComboAt", "below")
        Apply()
        popup:Refresh()
    end)
    window:Hint(popup, "The combo points' height and spot. Escape or a click elsewhere closes this.")
    window:Hint(reset, "As tall as your power bar again, under the display.")
    window:Hint(height, "How tall the combo points are. Until you move this, they're as tall as your power bar.")
    window:Hint(spot.buttons[1], "Under the display's lowest bar, as before.")
    window:Hint(spot.buttons[2], "Over the display's health bar. Rows above, and your cast bar when it's set above too, go over them.")
    popup.title, popup.reset, popup.height, popup.spotLabel, popup.spot = title, reset, height, spotLabel, spot

    -- The height in use (the power bar's, while yours is 0), kept within the
    -- slider's ends, and the spot picked.
    function popup:Refresh()
        local now = ns.Resource and ns.Resource:ComboHeight() or ns.COMBO_HEIGHT_LOW
        now = math.max(ns.COMBO_HEIGHT_LOW, math.min(ns.COMBO_HEIGHT[2], math.floor(now + .5)))
        height:Set(now)
        spot:SetSelected(ns.Get("prdComboAt"))
    end
    -- Under the button that opened it; clicked again, it closes.
    function popup:Toggle(owner)
        if self:IsOpen() then return self:Close() end
        self:ClearAllPoints()
        self:SetPoint("TOPLEFT", owner, "BOTTOMLEFT", 0, -4)
        self:Open(owner)
        self:Refresh()
    end
    return popup
end
