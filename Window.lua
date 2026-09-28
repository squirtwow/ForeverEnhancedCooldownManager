-- The /ccm window: one screen in three columns, Spellbook, Bars and Settings,
-- drawn in the flat Theme style. This file builds the frame, header, footer
-- and Settings column; BarsPanel.lua fills the Spellbook and Bars columns and
-- the "Add a spell" box.
local ADDON, ns = ...
local T = ns.Theme

local WIDTH, HEIGHT = 800, 520
local TOP, BOTTOM = 44, 30
local COLUMNS = { { 10, 330 }, { 348, 250 }, { 606, 184 } } -- x, width
local HINT = "Each spell shows once, at your highest rank."

local function Version()
    local get = C_AddOns and C_AddOns.GetAddOnMetadata or GetAddOnMetadata
    local version = get and get(ADDON, "Version")
    if not version or version:find("@", 1, true) then return "dev" end
    return "v" .. version
end

local function BuildSettings(window, panel)
    local B = ns.Bars
    T:Heading(panel, "Settings"):SetPoint("TOPLEFT", 8, -9)

    local bars = T:Check(panel, "Use Classic Bars", function(self)
        ns.Set("classicBars", self:GetChecked())
        B:Rebuild()
        window:Refresh()
    end)
    bars:SetPoint("TOPLEFT", 8, -28)
    window.useBars = bars

    local look = T:Check(panel, "Classic look for Blizzard's", function(self)
        ns.Set("classicLook", self:GetChecked())
        window:Refresh()
    end)
    look:SetPoint("TOPLEFT", 8, -50)
    window.look = look
    local lookDetail = T:Text(panel, "GameFontHighlightSmall", T.MUTED)
    lookDetail:SetPoint("TOPLEFT", 26, -67)
    lookDetail:SetWidth(150)
    lookDetail:SetText("Cooldown Manager. Needs a reload.")

    -- Shown when Blizzard's Cooldown Manager is switched off.
    local off = T:Text(panel, "GameFontHighlightSmall", { 1, .45, .3 })
    off:SetPoint("TOPLEFT", 8, -92)
    off:SetWidth(168)
    off:SetText("Blizzard's Cooldown Manager is off: Options > Gameplay > Advanced Options.")
    window.off = off

    local unlock = T:Button(panel, "Unlock bars to move", 168)
    unlock:SetPoint("TOPLEFT", 8, -126)
    unlock:SetScript("OnClick", function()
        if not B:Enabled() then
            window:Say("Tick Use Classic Bars first.")
        else
            B:SetUnlocked(not B:IsUnlocked())
        end
        window:Refresh()
    end)
    window.unlock = unlock
    local reset = T:Button(panel, "Reset positions", 168)
    reset:SetPoint("TOPLEFT", 8, -152)
    reset:SetScript("OnClick", function()
        B:ResetPositions()
        window:Say("Bars moved back above your action bar.")
        window:Refresh()
    end)

    T:Heading(panel, "Accent"):SetPoint("TOPLEFT", 8, -188)
    local swatches = {}
    local chosen = T:Text(panel, "GameFontHighlightSmall", T.MUTED)
    chosen:SetPoint("TOPLEFT", 8, -230)
    for i, key in ipairs(ns.ACCENT_KEYS) do
        local swatch = CreateFrame("Button", nil, panel, "BackdropTemplate")
        swatch:SetSize(20, 20)
        swatch:SetPoint("TOPLEFT", 8 + (i - 1) * 26, -204)
        local colour = T.ACCENTS[key].colour
        T:Flat(swatch, { colour[1], colour[2], colour[3], 1 }, T.CONTROL_BORDER)
        swatch.key = key
        swatch:SetScript("OnClick", function()
            ns.Set("accent", key)
            T:Repaint()
            window:Refresh()
        end)
        swatches[i] = swatch
    end
    window.swatches = swatches

    -- The reload a changed Classic look needs, at the foot of the column.
    local hint = T:Text(panel, "GameFontHighlightSmall", T.MUTED)
    hint:SetPoint("BOTTOMLEFT", 8, 38)
    hint:SetWidth(168)
    window.hint = hint
    local reload = T:Button(panel, "Reload UI", 168)
    reload:SetPoint("BOTTOMLEFT", 8, 10)
    -- Straight from the click, while the window is still shown.
    reload:SetScript("OnClick", function()
        if InCombatLockdown() then
            hint:SetText("Finish combat first, then reload.")
            return
        end
        ReloadUI()
    end)
    window.reload = reload

    function window:RefreshSettings()
        self.useBars:SetChecked(B:Enabled())
        self.look:SetChecked(ns.Get("classicLook"))
        self.off:SetShown(not ns.CooldownManagerOn())
        self.unlock:SetLabel(B:IsUnlocked() and "Lock bars" or "Unlock bars to move")
        local needsReload = ns.NeedsReload()
        self.reload:SetShown(needsReload)
        self.hint:SetText(needsReload and "Reload UI to apply your change." or "")
        local current = ns.Get("accent")
        for _, swatch in ipairs(self.swatches) do
            local border = swatch.key == current and { 1, 1, 1, 1 } or T.CONTROL_BORDER
            swatch:SetBackdropBorderColor(border[1], border[2], border[3], 1)
        end
        chosen:SetText(T.ACCENTS[current].name)
    end
end

local function BuildWindow()
    local window = CreateFrame("Frame", "ClassicCooldownManagerFrame", UIParent, "BackdropTemplate")
    window:SetSize(WIDTH, HEIGHT)
    window:SetPoint("CENTER", 0, 60)
    window:SetFrameStrata("FULLSCREEN_DIALOG")
    window:SetToplevel(true)
    window:SetClampedToScreen(true)
    window:EnableMouse(true)
    window:SetMovable(true)
    window:RegisterForDrag("LeftButton")
    window:SetScript("OnDragStart", window.StartMoving)
    window:SetScript("OnDragStop", window.StopMovingOrSizing)
    T:Flat(window, T.BG, { .22, .22, .22, 1 })
    window:Hide()

    -- Header: the icon on an accent square, and "Classic" in the accent.
    local logo = CreateFrame("Frame", nil, window, "BackdropTemplate")
    logo:SetSize(24, 24)
    logo:SetPoint("TOPLEFT", 12, -10)
    local icon = logo:CreateTexture(nil, "ARTWORK")
    icon:SetPoint("TOPLEFT", 2, -2)
    icon:SetPoint("BOTTOMRIGHT", -2, 2)
    icon:SetTexture("Interface\\Icons\\INV_Misc_PocketWatch_01")
    local title = T:Text(window, "GameFontNormalLarge")
    title:SetPoint("LEFT", logo, "RIGHT", 8, 0)
    T:Paint(function(accent)
        T:Flat(logo, { accent[1], accent[2], accent[3], 1 }, { accent[1], accent[2], accent[3], 1 })
        title:SetText("|cff" .. T:Hex(accent) .. "Classic|r Cooldown Manager")
    end)
    local close = T:Square(window, "X")
    close:SetSize(22, 22)
    close:SetPoint("TOPRIGHT", -10, -11)
    close:SetScript("OnClick", function() window:Hide() end)
    window.close = close

    local panels = {}
    for i, column in ipairs(COLUMNS) do
        local panel = T:Panel(window)
        panel:SetPoint("TOPLEFT", column[1], -TOP)
        panel:SetSize(column[2], HEIGHT - TOP - BOTTOM)
        panels[i] = panel
    end
    window.panels = panels

    -- Footer: the version, and messages from the window (or a tip).
    local version = T:Text(window, "GameFontHighlightSmall", T.MUTED)
    version:SetPoint("BOTTOMLEFT", 12, 10)
    version:SetText(Version() .. "   /ccm to open")
    local note = T:Text(window, "GameFontHighlightSmall", T.MUTED)
    note:SetPoint("BOTTOMRIGHT", -12, 10)
    note:SetJustifyH("RIGHT")
    note:SetWidth(520)
    window.note = note
    function window:Say(text)
        self.message = text
    end

    BuildSettings(window, panels[3])
    if ns.BuildBarsPanels then ns.BuildBarsPanels(window, panels[1], panels[2], panels[3]) end

    function window:Refresh()
        self:RefreshSettings()
        if self.RefreshBars then self:RefreshBars() end
        self.note:SetText(self.message or HINT)
        self.message = nil
    end

    window:SetScript("OnShow", function(self)
        self:Refresh()
        ns.EscUpdate()
    end)
    window:SetScript("OnHide", function()
        ns.EscUpdate()
        if ns.Bars then ns.Bars:SetUnlocked(false) end
    end)
    ns.window = window
    return window
end

function ns.ShowWindow()
    local window = ns.window or BuildWindow()
    window:Show()
    window:Raise()
end

function ns.Toggle()
    local window = ns.window or BuildWindow()
    window:SetShown(not window:IsShown())
end
