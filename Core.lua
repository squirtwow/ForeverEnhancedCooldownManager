-- Classic Cooldown Manager: saved settings, the /ccm window and the entry in
-- Options > AddOns. Each feature lives in its own file and starts from here
-- once the saved settings are loaded.
local ADDON, ns = ...

ns.TITLE = "Classic Cooldown Manager"
ns.MEDIA = "Interface\\AddOns\\" .. ADDON .. "\\Media\\"

ns.DEFAULTS = {
    classicLook = true,
}
-- Settings that only take effect after a reload.
ns.RELOAD = {
    classicLook = true,
}

local db
ns.loaded = {}

function ns.Get(key)
    local value = db and db[key]
    if value == nil then value = ns.DEFAULTS[key] end
    return value
end

-- Backup ------------------------------------------------------------------------
-- The Forever client can lose addon saved settings after a restart, so every
-- choice is also kept in one game setting registered by the addon, and read
-- back at login for anything missing. Only on/off values are stored, as plain
-- "key=1" pairs; nothing read back is ever run as code.
ns.BACKUP = "ClassicCooldownManagerBackup"

local function ReadBackup()
    local values = {}
    if not (C_CVar and C_CVar.GetCVar) then return values end
    local ok, text = pcall(C_CVar.GetCVar, ns.BACKUP)
    if not ok or type(text) ~= "string" then return values end
    for key, flag in text:gmatch("(%w+)=([01])") do
        if type(ns.DEFAULTS[key]) == "boolean" then values[key] = flag == "1" end
    end
    return values
end

local function WriteBackup()
    if not (C_CVar and C_CVar.GetCVar and C_CVar.SetCVar and C_CVar.RegisterCVar) then return end
    local parts = {}
    for key, default in pairs(ns.DEFAULTS) do
        if type(default) == "boolean" then parts[#parts + 1] = key .. "=" .. (ns.Get(key) and "1" or "0") end
    end
    table.sort(parts)
    local ok, current = pcall(C_CVar.GetCVar, ns.BACKUP)
    if not ok or current == nil then pcall(C_CVar.RegisterCVar, ns.BACKUP, "") end
    pcall(C_CVar.SetCVar, ns.BACKUP, table.concat(parts, ";"))
end

function ns.Set(key, value)
    if not db then return end
    db[key] = value
    WriteBackup()
    if ns.window and ns.window:IsShown() then ns.window:Refresh() end
end

function ns.NeedsReload()
    for key in pairs(ns.RELOAD) do
        if ns.Get(key) ~= ns.loaded[key] then return true end
    end
    return false
end

function ns.CooldownManagerOn()
    if not (C_CVar and C_CVar.GetCVarBool) then return true end
    return C_CVar.GetCVarBool("cooldownViewerEnabled") ~= false
end

-- Settings window -----------------------------------------------------------------

local BORDER = ns.MEDIA .. "TooltipBorder.tga"
local FILL = { .016, .016, .02, .9 } -- The same dark fill as Classic tooltips.
local GREY = { .58, .62, .68 }

local function Text(parent, font, r, g, b)
    local text = parent:CreateFontString(nil, "OVERLAY", font)
    text:SetJustifyH("LEFT")
    if r then text:SetTextColor(r, g, b) end
    return text
end

-- The same plain X as the EraUI windows.
local function CloseX(parent, onClick)
    local close = CreateFrame("Button", nil, parent)
    close:SetSize(36, 36)
    close:SetPoint("TOPRIGHT", -6, -6)
    local label = close:CreateFontString(nil, "OVERLAY")
    local font, _, flags = GameFontHighlight:GetFont()
    label:SetFont(font, 20, flags or "")
    label:SetTextColor(GREY[1], GREY[2], GREY[3])
    label:SetPoint("CENTER")
    label:SetText("X")
    close:SetScript("OnClick", onClick)
    close:SetScript("OnEnter", function() label:SetTextColor(1, 1, 1) end)
    close:SetScript("OnLeave", function() label:SetTextColor(GREY[1], GREY[2], GREY[3]) end)
    close.label = label
    return close
end

-- Escape closes the window. The key is borrowed only while the window is up
-- and handed back as a fight begins, since bindings cannot change in combat;
-- this keeps the addon out of the game's own Escape handling.
local escButton

local function EscUpdate()
    if not escButton or InCombatLockdown() then return end
    ClearOverrideBindings(escButton)
    if ns.window and ns.window:IsShown() then
        SetOverrideBindingClick(escButton, true, "ESCAPE", escButton:GetName())
    end
end

local function BuildEscape()
    escButton = CreateFrame("Button", "ClassicCooldownManagerEscButton", UIParent)
    escButton:SetScript("OnClick", function() if ns.window then ns.window:Hide() end end)
    escButton:RegisterEvent("PLAYER_REGEN_DISABLED")
    escButton:RegisterEvent("PLAYER_REGEN_ENABLED")
    escButton:SetScript("OnEvent", function(self, event)
        if event == "PLAYER_REGEN_DISABLED" then
            ClearOverrideBindings(self)
        else
            EscUpdate()
        end
    end)
end

local function BuildWindow()
    local window = CreateFrame("Frame", "ClassicCooldownManagerFrame", UIParent, "BackdropTemplate")
    window:SetSize(460, 236)
    window:SetPoint("CENTER", 0, 80)
    window:SetFrameStrata("FULLSCREEN_DIALOG")
    window:SetToplevel(true)
    window:SetClampedToScreen(true)
    window:EnableMouse(true)
    window:SetMovable(true)
    window:RegisterForDrag("LeftButton")
    window:SetScript("OnDragStart", window.StartMoving)
    window:SetScript("OnDragStop", window.StopMovingOrSizing)
    window:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8X8", edgeFile = BORDER, edgeSize = 16,
        insets = { left = 3, right = 3, top = 3, bottom = 3 } })
    window:SetBackdropColor(FILL[1], FILL[2], FILL[3], FILL[4])
    window:SetBackdropBorderColor(1, 1, 1, 1)
    window:Hide()

    local title = Text(window, "GameFontNormalLarge")
    title:SetPoint("TOPLEFT", 20, -18)
    title:SetText(ns.TITLE)
    window.close = CloseX(window, function() window:Hide() end)

    local look = CreateFrame("CheckButton", nil, window, "UICheckButtonTemplate")
    look:SetPoint("TOPLEFT", 16, -52)
    look:SetScript("OnClick", function(self) ns.Set("classicLook", self:GetChecked() and true or false) end)
    local lookLabel = Text(window, "GameFontHighlight")
    lookLabel:SetPoint("LEFT", look, "RIGHT", 4, 1)
    lookLabel:SetText("Classic look")
    local lookDetail = Text(window, "GameFontHighlightSmall", .8, .8, .8)
    lookDetail:SetPoint("TOPLEFT", look, "BOTTOMLEFT", 30, 0)
    lookDetail:SetWidth(392)
    lookDetail:SetText("Square 2004-style icons, a Classic cooldown sweep and Classic buff bars for Blizzard's Cooldown Manager. Positions and sizes stay in Edit Mode.")
    window.look = look

    -- Shown when Blizzard's Cooldown Manager is switched off.
    local off = Text(window, "GameFontNormalSmall")
    off:SetPoint("TOPLEFT", lookDetail, "BOTTOMLEFT", -30, -16)
    off:SetWidth(422)
    off:SetText("Blizzard's Cooldown Manager is off. Turn it on in Options > Gameplay > Advanced Options > Enable Cooldown Manager.")
    window.off = off

    local hint = Text(window, "GameFontNormalSmall")
    hint:SetPoint("BOTTOMLEFT", 20, 22)
    hint:SetWidth(290)
    window.hint = hint

    local reload = CreateFrame("Button", nil, window, "UIPanelButtonTemplate")
    reload:SetSize(120, 24)
    reload:SetPoint("BOTTOMRIGHT", -16, 16)
    reload:SetText("Reload UI")
    -- Straight from the click, while the window is still shown.
    reload:SetScript("OnClick", function()
        if InCombatLockdown() then
            hint:SetText("Finish combat first, then reload.")
            return
        end
        ReloadUI()
    end)
    window.reload = reload

    function window:Refresh()
        self.look:SetChecked(ns.Get("classicLook") and true or false)
        self.off:SetShown(not ns.CooldownManagerOn())
        local needsReload = ns.NeedsReload()
        self.reload:SetShown(needsReload)
        self.hint:SetText(needsReload and "Reload UI to apply your change." or "")
    end

    window:SetScript("OnShow", function(self)
        self:Refresh()
        EscUpdate()
    end)
    window:SetScript("OnHide", EscUpdate)
    ns.window = window
    return window
end

function ns.Toggle()
    local window = ns.window or BuildWindow()
    window:SetShown(not window:IsShown())
end

-- Options > AddOns ------------------------------------------------------------------

local function BuildOptionsEntry()
    if not (Settings and Settings.RegisterCanvasLayoutCategory and Settings.RegisterAddOnCategory) then return end
    local canvas = CreateFrame("Frame")
    local title = Text(canvas, "GameFontNormalLarge")
    title:SetPoint("TOPLEFT", 16, -16)
    title:SetText(ns.TITLE)
    local about = Text(canvas, "GameFontHighlight")
    about:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -10)
    about:SetWidth(560)
    about:SetText("Classic 2004 look for Blizzard's Cooldown Manager. Type /ccm, or click below, for the settings.")
    local open = CreateFrame("Button", nil, canvas, "UIPanelButtonTemplate")
    open:SetSize(160, 24)
    open:SetPoint("TOPLEFT", about, "BOTTOMLEFT", 0, -14)
    open:SetText("Open settings")
    open:SetScript("OnClick", function()
        local window = ns.window or BuildWindow()
        window:Show()
        window:Raise()
    end)
    local category = Settings.RegisterCanvasLayoutCategory(canvas, ns.TITLE)
    Settings.RegisterAddOnCategory(category)
end

-- Startup -------------------------------------------------------------------------

local loader = CreateFrame("Frame")
loader:RegisterEvent("ADDON_LOADED")
loader:SetScript("OnEvent", function(self, _, name)
    if name ~= ADDON then return end
    self:UnregisterEvent("ADDON_LOADED")
    ClassicCooldownManagerDB = type(ClassicCooldownManagerDB) == "table" and ClassicCooldownManagerDB or {}
    db = ClassicCooldownManagerDB
    -- Saved settings win; the backup only fills in what the client lost.
    for key, value in pairs(ReadBackup()) do
        if db[key] == nil then db[key] = value end
    end
    WriteBackup()
    for key in pairs(ns.RELOAD) do ns.loaded[key] = ns.Get(key) end

    SLASH_CLASSICCOOLDOWNMANAGER1 = "/ccm"
    SlashCmdList.CLASSICCOOLDOWNMANAGER = function(msg)
        msg = type(msg) == "string" and msg or ""
        if ns.Probe and msg:match("^%s*check") then ns.Probe(msg) else ns.Toggle() end
    end
    BuildEscape()
    BuildOptionsEntry()

    if ns.loaded.classicLook and ns.Skin then ns.Skin:Start() end
end)
