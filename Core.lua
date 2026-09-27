-- Classic Cooldown Manager: saved settings, the /ccm window and the entry in
-- Options > AddOns. Each feature lives in its own file and starts from here
-- once the saved settings are loaded.
local ADDON, ns = ...

ns.TITLE = "Classic Cooldown Manager"
ns.MEDIA = "Interface\\AddOns\\" .. ADDON .. "\\Media\\"

ns.DEFAULTS = {
    classicLook = true,
    classicBars = false,
}
-- Settings that only take effect after a reload.
ns.RELOAD = {
    classicLook = true,
}

-- Classic Bars: each bar lists spells by name, so the highest known rank is
-- always the one shown.
ns.BAR_KEYS = { "cd", "util" }
ns.BAR_NAMES = { cd = "Cooldowns", util = "Utility" }
ns.BAR_LIMITS = { size = { 20, 64, 36 }, spacing = { 0, 20, 4 } } -- min, max, default
ns.BAR_MAX_SPELLS = 40

local db
ns.loaded = {}

function ns.Get(key)
    local value = db and db[key]
    if value == nil then value = ns.DEFAULTS[key] end
    return value
end

local function Finite(n)
    return type(n) == "number" and n == n and n > -math.huge and n < math.huge
end

local function Limit(value, limits)
    if not Finite(value) then return limits[3] end
    return math.max(limits[1], math.min(limits[2], math.floor(value + .5)))
end

-- A bar's saved data, repaired in place if anything is missing or invalid.
function ns.BarData(key)
    if not db or not ns.BAR_NAMES[key] then return nil end
    if type(db.bars) ~= "table" then db.bars = {} end
    local bar = db.bars[key]
    if type(bar) ~= "table" then
        bar = {}
        db.bars[key] = bar
    end
    if type(bar.spells) ~= "table" then bar.spells = {} end
    local spells = bar.spells
    for i = #spells, 1, -1 do
        if type(spells[i]) ~= "string" or spells[i] == "" then table.remove(spells, i) end
    end
    for i = #spells, ns.BAR_MAX_SPELLS + 1, -1 do spells[i] = nil end
    bar.size = Limit(bar.size, ns.BAR_LIMITS.size)
    bar.spacing = Limit(bar.spacing, ns.BAR_LIMITS.spacing)
    bar.hideReady = bar.hideReady == true
    bar.combatOnly = bar.combatOnly == true
    if not (Finite(bar.x) and Finite(bar.y) and math.abs(bar.x) < 4000 and math.abs(bar.y) < 4000) then
        bar.x, bar.y = nil, nil
    end
    return bar
end

-- Backup ------------------------------------------------------------------------
-- The Forever client can lose addon saved settings after a restart, so every
-- choice is also kept in game settings registered by the addon, and read back
-- at login for anything missing. On/off values are stored as "key=1" pairs and
-- the bars as "cd.size=36;cd.spells=Moonfire|Bash" text split into chunks;
-- everything read back is checked, and nothing is ever run as code.
ns.BACKUP = "ClassicCooldownManagerBackup"
local BARS_BACKUP = ns.BACKUP .. "Bars"
local CHUNK, MAX_CHUNKS = 900, 16

local function ReadCVar(name)
    if not (C_CVar and C_CVar.GetCVar) then return nil end
    local ok, value = pcall(C_CVar.GetCVar, name)
    if ok and type(value) == "string" then return value end
end

local function WriteCVar(name, value)
    if not (C_CVar and C_CVar.SetCVar and C_CVar.RegisterCVar) then return end
    if ReadCVar(name) == nil then pcall(C_CVar.RegisterCVar, name, "") end
    pcall(C_CVar.SetCVar, name, value)
end

local function ReadBackup()
    local values = {}
    local text = ReadCVar(ns.BACKUP)
    if not text then return values end
    for key, flag in text:gmatch("(%w+)=([01])") do
        if type(ns.DEFAULTS[key]) == "boolean" then values[key] = flag == "1" end
    end
    return values
end

local function EncodeBars()
    local parts = {}
    for _, key in ipairs(ns.BAR_KEYS) do
        local bar = ns.BarData(key)
        local names = {}
        for _, name in ipairs(bar.spells) do
            if not name:find("[;=|]") then names[#names + 1] = name end
        end
        parts[#parts + 1] = ("%s.size=%d;%s.spacing=%d;%s.hide=%d;%s.combat=%d;%s.spells=%s"):format(
            key, bar.size, key, bar.spacing, key, bar.hideReady and 1 or 0,
            key, bar.combatOnly and 1 or 0, key, table.concat(names, "|"))
        if bar.x and bar.y then parts[#parts + 1] = ("%s.x=%.1f;%s.y=%.1f"):format(key, bar.x, key, bar.y) end
    end
    return table.concat(parts, ";")
end

local function DecodeBars(text)
    local bars = {}
    for key, field, value in text:gmatch("(%a+)%.(%a+)=([^;]*)") do
        if ns.BAR_NAMES[key] then
            local bar = bars[key] or { spells = {} }
            bars[key] = bar
            if field == "size" or field == "spacing" then
                bar[field] = tonumber(value)
            elseif field == "hide" then
                bar.hideReady = value == "1"
            elseif field == "combat" then
                bar.combatOnly = value == "1"
            elseif field == "x" or field == "y" then
                bar[field] = tonumber(value)
            elseif field == "spells" then
                for name in value:gmatch("[^|]+") do
                    if #name <= 60 and #bar.spells < ns.BAR_MAX_SPELLS then bar.spells[#bar.spells + 1] = name end
                end
            end
        end
    end
    return next(bars) and bars or nil
end

local function ReadBarsBackup()
    local count = tonumber(ReadCVar(BARS_BACKUP .. "0") or "")
    if not count or count < 1 or count > MAX_CHUNKS then return nil end
    local parts = {}
    for i = 1, count do
        parts[i] = ReadCVar(BARS_BACKUP .. i)
        if not parts[i] then return nil end
    end
    return DecodeBars(table.concat(parts))
end

local function WriteBackup()
    local flags = {}
    for key, default in pairs(ns.DEFAULTS) do
        if type(default) == "boolean" then flags[#flags + 1] = key .. "=" .. (ns.Get(key) and "1" or "0") end
    end
    table.sort(flags)
    WriteCVar(ns.BACKUP, table.concat(flags, ";"))
    if not db then return end
    local text = EncodeBars()
    local count = math.min(MAX_CHUNKS, math.ceil(#text / CHUNK))
    for i = 1, count do WriteCVar(BARS_BACKUP .. i, text:sub((i - 1) * CHUNK + 1, i * CHUNK)) end
    WriteCVar(BARS_BACKUP .. "0", tostring(count))
end

function ns.Set(key, value)
    if not db then return end
    db[key] = value
    WriteBackup()
    if ns.window and ns.window:IsShown() then ns.window:Refresh() end
end

-- Called after any change to a bar's data.
function ns.SaveBars()
    WriteBackup()
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

-- Shared window pieces ---------------------------------------------------------------

local BORDER = ns.MEDIA .. "TooltipBorder.tga"
local FILL = { .016, .016, .02, .9 } -- The same dark fill as Classic tooltips.
local GREY = { .58, .62, .68 }
local GOLD = { 1, .82, 0 }

local UI = {}
ns.UI = UI
UI.GREY, UI.GOLD = GREY, GOLD

function UI.Text(parent, font, r, g, b)
    local text = parent:CreateFontString(nil, "OVERLAY", font)
    text:SetJustifyH("LEFT")
    if r then text:SetTextColor(r, g, b) end
    return text
end

-- A plain text tab: gold with an underline when selected, grey otherwise.
function UI.Tab(parent, label, onClick)
    local tab = CreateFrame("Button", nil, parent)
    tab.label = UI.Text(tab, "GameFontNormal")
    tab.label:SetPoint("CENTER", 0, 1)
    tab.label:SetText(label)
    tab:SetSize(tab.label:GetStringWidth() + 20, 24)
    tab.line = tab:CreateTexture(nil, "ARTWORK")
    tab.line:SetColorTexture(GOLD[1], GOLD[2], GOLD[3], .9)
    tab.line:SetPoint("BOTTOMLEFT", 6, 0)
    tab.line:SetPoint("BOTTOMRIGHT", -6, 0)
    tab.line:SetHeight(2)
    function tab:SetSelected(selected)
        self.selected = selected
        self.line:SetShown(selected)
        local c = selected and GOLD or GREY
        self.label:SetTextColor(c[1], c[2], c[3])
    end
    tab:SetScript("OnClick", onClick)
    tab:SetScript("OnEnter", function(self) if not self.selected then self.label:SetTextColor(1, 1, 1) end end)
    tab:SetScript("OnLeave", function(self) self:SetSelected(self.selected) end)
    tab:SetSelected(false)
    return tab
end

-- A dark inset box for grouping controls.
function UI.Box(parent)
    local box = CreateFrame("Frame", nil, parent, "BackdropTemplate")
    box:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8X8", edgeFile = "Interface\\Buttons\\WHITE8X8", edgeSize = 1 })
    box:SetBackdropColor(0, 0, 0, .3)
    box:SetBackdropBorderColor(1, 1, 1, .12)
    return box
end

-- The same plain X as the EraUI windows.
function UI.CloseX(parent, onClick, size)
    local close = CreateFrame("Button", nil, parent)
    close:SetSize(size or 36, size or 36)
    local label = close:CreateFontString(nil, "OVERLAY")
    local font, _, flags = GameFontHighlight:GetFont()
    label:SetFont(font, size and math.floor(size * .6) or 20, flags or "")
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

-- Settings window -----------------------------------------------------------------

local PAGE_SIZE = { look = { 470, 280 }, bars = { 720, 540 } }

local function BuildLookPage(window, page)
    local look = CreateFrame("CheckButton", nil, page, "UICheckButtonTemplate")
    look:SetPoint("TOPLEFT", 16, -4)
    look:SetScript("OnClick", function(self) ns.Set("classicLook", self:GetChecked() and true or false) end)
    local lookLabel = UI.Text(page, "GameFontHighlight")
    lookLabel:SetPoint("LEFT", look, "RIGHT", 4, 1)
    lookLabel:SetText("Classic look")
    local lookDetail = UI.Text(page, "GameFontHighlightSmall", .8, .8, .8)
    lookDetail:SetPoint("TOPLEFT", look, "BOTTOMLEFT", 30, 0)
    lookDetail:SetWidth(392)
    lookDetail:SetText("Square 2004-style icons, a Classic cooldown sweep and Classic buff bars for Blizzard's Cooldown Manager. Positions and sizes stay in Edit Mode.")
    window.look = look

    -- Shown when Blizzard's Cooldown Manager is switched off.
    local off = UI.Text(page, "GameFontNormalSmall")
    off:SetPoint("TOPLEFT", lookDetail, "BOTTOMLEFT", -30, -16)
    off:SetWidth(422)
    off:SetText("Blizzard's Cooldown Manager is off. Turn it on in Options > Gameplay > Advanced Options > Enable Cooldown Manager.")
    window.off = off

    local hint = UI.Text(page, "GameFontNormalSmall")
    hint:SetPoint("BOTTOMLEFT", 20, 22)
    hint:SetWidth(290)
    window.hint = hint

    local reload = CreateFrame("Button", nil, page, "UIPanelButtonTemplate")
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
end

local function BuildWindow()
    local window = CreateFrame("Frame", "ClassicCooldownManagerFrame", UIParent, "BackdropTemplate")
    window:SetSize(PAGE_SIZE.look[1], PAGE_SIZE.look[2])
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

    local title = UI.Text(window, "GameFontNormalLarge")
    title:SetPoint("TOPLEFT", 20, -18)
    title:SetText(ns.TITLE)
    window.close = UI.CloseX(window, function() window:Hide() end)
    window.close:SetPoint("TOPRIGHT", -6, -6)

    window.pages, window.tabs = {}, {}
    local order = { { "look", "Classic look" }, { "bars", "Classic Bars" } }
    local previous
    for _, entry in ipairs(order) do
        local key = entry[1]
        local page = CreateFrame("Frame", nil, window)
        page:SetPoint("TOPLEFT", 0, -76)
        page:SetPoint("BOTTOMRIGHT")
        page:Hide()
        window.pages[key] = page
        local tab = UI.Tab(window, entry[2], function() window:ShowPage(key) end)
        if previous then tab:SetPoint("LEFT", previous, "RIGHT", 4, 0) else tab:SetPoint("TOPLEFT", 14, -42) end
        previous = tab
        window.tabs[key] = tab
    end
    BuildLookPage(window, window.pages.look)
    if ns.BuildBarsPage then ns.BuildBarsPage(window, window.pages.bars) end

    function window:ShowPage(key)
        self.page = key
        for name, page in pairs(self.pages) do
            page:SetShown(name == key)
            self.tabs[name]:SetSelected(name == key)
        end
        self:SetSize(PAGE_SIZE[key][1], PAGE_SIZE[key][2])
        self:Refresh()
    end

    function window:Refresh()
        self.look:SetChecked(ns.Get("classicLook") and true or false)
        self.off:SetShown(not ns.CooldownManagerOn())
        local needsReload = ns.NeedsReload()
        self.reload:SetShown(needsReload)
        self.hint:SetText(needsReload and "Reload UI to apply your change." or "")
        if self.page == "bars" and self.RefreshBars then self:RefreshBars() end
    end

    window:SetScript("OnShow", function(self)
        self:ShowPage(self.page or "look")
        EscUpdate()
    end)
    window:SetScript("OnHide", function()
        EscUpdate()
        if ns.Bars then ns.Bars:SetUnlocked(false) end
    end)
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
    local title = UI.Text(canvas, "GameFontNormalLarge")
    title:SetPoint("TOPLEFT", 16, -16)
    title:SetText(ns.TITLE)
    local about = UI.Text(canvas, "GameFontHighlight")
    about:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -10)
    about:SetWidth(560)
    about:SetText("Classic 2004 look for Blizzard's Cooldown Manager, plus Classic Bars of your own. Type /ccm, or click below, for the settings.")
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
    if db.bars == nil then db.bars = ReadBarsBackup() end
    for _, key in ipairs(ns.BAR_KEYS) do ns.BarData(key) end
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
    if ns.Bars then ns.Bars:Start() end
end)
