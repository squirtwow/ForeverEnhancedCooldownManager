-- Forever Enhanced Cooldown Manager: saved settings and their backup, the /ccm command,
-- Escape for the window and the entry in Options > AddOns. Each feature lives
-- in its own file and starts from here once the saved settings are loaded.
local ADDON, ns = ...

ns.TITLE = "Forever Enhanced Cooldown Manager"
ns.MEDIA = "Interface\\AddOns\\" .. ADDON .. "\\Media\\"

ns.DEFAULTS = {
    skin = true,
    useBars = false, -- the addon's own bars
    listItems = false, -- show trinkets and bag items in the /ccm spell list
    listRanks = false, -- show every rank you know as its own row
    accent = "orange", -- the /ccm window's accent colour
}
-- Choices a text setting may hold.
ns.ACCENT_KEYS = { "orange", "blue", "teal", "purple", "green" }
local CHOICES = { accent = {} }
for _, key in ipairs(ns.ACCENT_KEYS) do CHOICES.accent[key] = true end

function ns.Valid(key, value)
    local default = ns.DEFAULTS[key]
    if type(default) == "boolean" then return type(value) == "boolean" end
    if CHOICES[key] then return CHOICES[key][value] == true end
    return type(value) == type(default)
end
-- Settings that only take effect after a reload.
ns.RELOAD = {
    skin = true,
}

-- Bars: each bar lists spells by name, so the highest known rank is
-- always the one shown.
ns.BAR_KEYS = { "cd", "util", "buff" }
ns.BAR_NAMES = { cd = "Cooldowns", util = "Utility", buff = "Buffs" }
ns.BAR_LIMITS = { size = { 20, 64, 36 }, spacing = { 0, 20, 4 } } -- min, max, default
ns.BAR_MAX_SPELLS = 40
ns.BUFF_SLOTS = 16 -- the Buffs bar has one secure slot per buff

local db
ns.loaded = {}

function ns.Get(key)
    local value = db and db[key]
    if value == nil or not ns.Valid(key, value) then value = ns.DEFAULTS[key] end
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
    bar.showMissing = bar.showMissing == true
    bar.showNames = bar.showNames == true
    bar.showTimer = bar.showTimer ~= false -- countdown numbers, on unless turned off
    if not (Finite(bar.x) and Finite(bar.y) and math.abs(bar.x) < 4000 and math.abs(bar.y) < 4000) then
        bar.x, bar.y = nil, nil
    end
    return bar
end

-- Spells added by name or ID that aren't in your spellbook: name -> spell IDs.
function ns.CustomSpells()
    if not db then return {} end
    if type(db.custom) ~= "table" then db.custom = {} end
    for name, ids in pairs(db.custom) do
        local valid = type(name) == "string" and name ~= "" and type(ids) == "table" and #ids > 0
        for _, id in ipairs(valid and ids or {}) do
            if not Finite(id) then valid = false end
        end
        if not valid then db.custom[name] = nil end
    end
    return db.custom
end

function ns.AddCustom(name, ids)
    ns.CustomSpells()[name] = ids
end

-- Forgets added spells once they're on no bar.
function ns.PruneCustom()
    local custom = ns.CustomSpells()
    for name in pairs(custom) do
        local used = false
        for _, key in ipairs(ns.BAR_KEYS) do
            for _, spell in ipairs(ns.BarData(key).spells) do
                if spell == name then used = true end
            end
        end
        if not used then custom[name] = nil end
    end
end

-- Backup ------------------------------------------------------------------------
-- The Forever client can lose addon saved settings after a restart, so every
-- choice is also kept in game settings registered by the addon, and read back
-- at login for anything missing. Plain settings are stored as "key=1" pairs and
-- the bars as "cd.size=36;cd.spells=Moonfire|Bash" text split into chunks;
-- everything read back is checked, and nothing is ever run as code.
ns.BACKUP = "FECMBackup"
local BARS_BACKUP = ns.BACKUP .. "Bars"
-- The backup this addon kept under its first name, read once to carry a
-- setup over, with the two settings that were renamed.
local LEGACY = "ClassicCooldownManagerBackup"
local LEGACY_KEYS = { classicLook = "skin", classicBars = "useBars" }
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

local function ReadBackup(name)
    local values = {}
    local text = ReadCVar(name or ns.BACKUP)
    if not text then return values end
    for key, value in text:gmatch("(%w+)=(%w+)") do
        key = LEGACY_KEYS[key] or key
        local default = ns.DEFAULTS[key]
        if type(default) == "boolean" and (value == "0" or value == "1") then
            values[key] = value == "1"
        elseif type(default) == "string" and ns.Valid(key, value) then
            values[key] = value
        end
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
        parts[#parts + 1] = ("%s.size=%d;%s.spacing=%d;%s.hide=%d;%s.combat=%d;%s.missing=%d;%s.names=%d;%s.timer=%d;%s.spells=%s"):format(
            key, bar.size, key, bar.spacing, key, bar.hideReady and 1 or 0, key, bar.combatOnly and 1 or 0,
            key, bar.showMissing and 1 or 0, key, bar.showNames and 1 or 0, key, bar.showTimer and 1 or 0,
            key, table.concat(names, "|"))
        if bar.x and bar.y then parts[#parts + 1] = ("%s.x=%.1f;%s.y=%.1f"):format(key, bar.x, key, bar.y) end
    end
    local custom = {}
    for name, ids in pairs(ns.CustomSpells()) do
        if not name:find("[;=|~]") then custom[#custom + 1] = name .. "~" .. table.concat(ids, ",") end
    end
    table.sort(custom)
    if #custom > 0 then parts[#parts + 1] = "extra.custom=" .. table.concat(custom, "|") end
    return table.concat(parts, ";")
end

local function DecodeBars(text)
    local bars, custom = {}, nil
    for key, field, value in text:gmatch("(%a+)%.(%a+)=([^;]*)") do
        if key == "extra" and field == "custom" then
            custom = {}
            for name, list in value:gmatch("([^|~]+)~([%d,]+)") do
                local ids = {}
                for id in list:gmatch("%d+") do ids[#ids + 1] = tonumber(id) end
                if #name <= 60 and #ids > 0 then custom[name] = ids end
            end
        elseif ns.BAR_NAMES[key] then
            local bar = bars[key] or { spells = {} }
            bars[key] = bar
            if field == "size" or field == "spacing" then
                bar[field] = tonumber(value)
            elseif field == "hide" then
                bar.hideReady = value == "1"
            elseif field == "missing" then
                bar.showMissing = value == "1"
            elseif field == "names" then
                bar.showNames = value == "1"
            elseif field == "timer" then
                bar.showTimer = value == "1"
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
    return next(bars) and bars or nil, custom
end

local function ReadBarsBackup(prefix)
    prefix = prefix or BARS_BACKUP
    local count = tonumber(ReadCVar(prefix .. "0") or "")
    if not count or count < 1 or count > MAX_CHUNKS then return nil end
    local parts = {}
    for i = 1, count do
        parts[i] = ReadCVar(prefix .. i)
        if not parts[i] then return nil end
    end
    return DecodeBars(table.concat(parts))
end

local function WriteBackup()
    local flags = {}
    for key, default in pairs(ns.DEFAULTS) do
        if type(default) == "boolean" then
            flags[#flags + 1] = key .. "=" .. (ns.Get(key) and "1" or "0")
        elseif type(default) == "string" then
            flags[#flags + 1] = key .. "=" .. ns.Get(key)
        end
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

-- Escape closes the /ccm window. The key is borrowed only while the window is
-- up and handed back as a fight begins, since bindings cannot change in combat;
-- this keeps the addon out of the game's own Escape handling.
local escButton

function ns.EscUpdate()
    if not escButton or InCombatLockdown() then return end
    ClearOverrideBindings(escButton)
    if ns.window and ns.window:IsShown() then
        SetOverrideBindingClick(escButton, true, "ESCAPE", escButton:GetName())
    end
end

local function BuildEscape()
    escButton = CreateFrame("Button", "FECMEscButton", UIParent)
    escButton:SetScript("OnClick", function() if ns.window then ns.window:Hide() end end)
    escButton:RegisterEvent("PLAYER_REGEN_DISABLED")
    escButton:RegisterEvent("PLAYER_REGEN_ENABLED")
    escButton:SetScript("OnEvent", function(self, event)
        if event == "PLAYER_REGEN_DISABLED" then
            ClearOverrideBindings(self)
        else
            ns.EscUpdate()
        end
    end)
end

-- Options > AddOns ------------------------------------------------------------------

local function BuildOptionsEntry()
    if not (Settings and Settings.RegisterCanvasLayoutCategory and Settings.RegisterAddOnCategory) then return end
    local canvas = CreateFrame("Frame")
    local title = canvas:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    title:SetPoint("TOPLEFT", 16, -16)
    title:SetText(ns.TITLE)
    local about = canvas:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    about:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -10)
    about:SetWidth(560)
    about:SetJustifyH("LEFT")
    about:SetText("A charcoal look for Blizzard's Cooldown Manager, plus cooldown and buff bars of your own. Type /fecm, or click below, for the settings.")
    local open = CreateFrame("Button", nil, canvas, "UIPanelButtonTemplate")
    open:SetSize(160, 24)
    open:SetPoint("TOPLEFT", about, "BOTTOMLEFT", 0, -14)
    open:SetText("Open settings")
    open:SetScript("OnClick", function() if ns.ShowWindow then ns.ShowWindow() end end)
    local category = Settings.RegisterCanvasLayoutCategory(canvas, ns.TITLE)
    Settings.RegisterAddOnCategory(category)
end

-- Startup -------------------------------------------------------------------------

local loader = CreateFrame("Frame")
loader:RegisterEvent("ADDON_LOADED")
loader:SetScript("OnEvent", function(self, _, name)
    if name ~= ADDON then return end
    self:UnregisterEvent("ADDON_LOADED")
    ForeverEnhancedCooldownManagerDB = type(ForeverEnhancedCooldownManagerDB) == "table" and ForeverEnhancedCooldownManagerDB or {}
    db = ForeverEnhancedCooldownManagerDB
    -- Saved settings win; the backup only fills in what the client lost.
    -- A first login under the new name picks up the old backup instead.
    local fresh = next(db) == nil and ReadCVar(ns.BACKUP) == nil
    for key, value in pairs(ReadBackup(fresh and LEGACY or nil)) do
        if db[key] == nil then db[key] = value end
    end
    local bars, custom = ReadBarsBackup(fresh and LEGACY .. "Bars" or nil)
    if db.bars == nil then db.bars = bars end
    if db.custom == nil then db.custom = custom end
    for _, key in ipairs(ns.BAR_KEYS) do ns.BarData(key) end
    WriteBackup()
    for key in pairs(ns.RELOAD) do ns.loaded[key] = ns.Get(key) end

    SLASH_FECM1 = "/fecm"
    SLASH_FECM2 = "/ccm"
    SlashCmdList.FECM = function(msg)
        msg = type(msg) == "string" and msg or ""
        if ns.Probe and msg:match("^%s*check") then ns.Probe(msg) elseif ns.Toggle then ns.Toggle() end
    end
    BuildEscape()
    BuildOptionsEntry()

    if ns.loaded.skin and ns.Skin then ns.Skin:Start() end
    if ns.Bars then ns.Bars:Start() end
end)
