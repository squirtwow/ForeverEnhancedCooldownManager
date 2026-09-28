-- Charcoal look for Blizzard's Cooldown Manager: square frameless icons with
-- big bold countdown numbers, and flat charcoal Tracked Bars.
-- Visual only. Blizzard still decides what shows, when, and where (Edit Mode).
-- Cooldowns and auras are secret in combat, so nothing here reads them: each
-- item frame gets its textures, fonts and anchors set once, after Blizzard's
-- own setup, and no key is ever written on Blizzard's frames.
local _, ns = ...

local M = {}
ns.Skin = M

local Style = ns.Style
local OVERLAY_ATLAS = "UI-HUD-CoolDownManager-IconOverlay"
-- Tracked Bars are 30 tall with a 30 icon; the bar grows from 19 to sit level
-- with the icon's art.
local BAR_HEIGHT = 26
-- Blizzard places icons 4 units closer than the padding setting because its
-- mask trims their edges; trimming 2 from each side of the square art makes
-- the gap between icons match Edit Mode's Padding exactly.
local INSET = 2

local skinned = setmetatable({}, { __mode = "k" })
local hooked = {}

-- Region helpers --------------------------------------------------------------

local function Regions(frame)
    return { frame:GetRegions() }
end

local function Inset(region, anchor, inset)
    region:ClearAllPoints()
    region:SetPoint("TOPLEFT", anchor, "TOPLEFT", inset, -inset)
    region:SetPoint("BOTTOMRIGHT", anchor, "BOTTOMRIGHT", -inset, inset)
end

-- The rounded mask and the modern frame art go, and the icon art is zoomed
-- past its own bevel, with nothing drawn around it.
local function SquareIcon(frame, icon)
    for _, region in ipairs(Regions(frame)) do
        local kind = region:GetObjectType()
        if kind == "MaskTexture" then
            icon:RemoveMaskTexture(region)
        elseif kind == "Texture" and region:GetAtlas() == OVERLAY_ATLAS then
            region:SetAlpha(0)
        end
    end
    Inset(icon, frame, INSET)
    Style:Zoom(icon)
end

local function SquareSweep(cooldown, icon)
    if not cooldown then return end
    Inset(cooldown, icon, 0)
    cooldown:SetSwipeTexture(Style.FLAT)
end

local function Font(region, name)
    if region and name then region:SetFontObject(name) end
end

-- Item frames -------------------------------------------------------------------

-- Essential and Utility cooldowns, including trinkets and potions.
local function Cooldown(item, spec)
    SquareIcon(item, item.Icon)
    SquareSweep(item.Cooldown, item.Icon)
    if item.Cooldown then item.Cooldown:SetCountdownFont(Style:Countdown(spec.size)) end
    Font(item.ChargeCount and item.ChargeCount.Current, Style:Count(spec.size))
    -- Out of range still tints the icon red; the modern shadow and the
    -- end-of-cooldown sparkle stay hidden.
    if item.OutOfRange then item.OutOfRange:SetAlpha(0) end
    if item.CooldownFlash then item.CooldownFlash:SetAlpha(0) end
end

-- Tracked buffs shown as icons.
local function Buff(item, spec)
    SquareIcon(item, item.Icon)
    SquareSweep(item.Cooldown, item.Icon)
    if item.Cooldown then item.Cooldown:SetCountdownFont(Style:Countdown(spec.size)) end
    Font(item.Applications and item.Applications.Applications, Style:Count(spec.size))
end

-- Tracked buffs shown as bars.
local function Bar(item, spec)
    local iconFrame = item.Icon
    if iconFrame and iconFrame.Icon then
        SquareIcon(iconFrame, iconFrame.Icon)
        Font(iconFrame.Applications, Style:Count(spec.size))
    end
    local bar = item.Bar
    if not bar then return end
    bar:SetHeight(BAR_HEIGHT)
    bar:SetStatusBarTexture(Style.FLAT)
    bar:SetStatusBarColor(Style.FILL[1], Style.FILL[2], Style.FILL[3])
    if bar.BarBG then
        bar.BarBG:SetColorTexture(Style.TRACK[1], Style.TRACK[2], Style.TRACK[3], Style.TRACK[4])
        Inset(bar.BarBG, bar, 0)
    end
    if bar.Pip then bar.Pip:SetAlpha(0) end
    Font(bar.Name, Style:Font(13))
    Font(bar.Duration, Style:Font(15))
end

-- size is the item's own size in Blizzard's templates; Edit Mode's icon size
-- scales the whole viewer, fonts included.
M.VIEWERS = {
    { name = "EssentialCooldownViewer", skin = Cooldown, size = 50 },
    { name = "UtilityCooldownViewer", skin = Cooldown, size = 30 },
    { name = "BuffIconCooldownViewer", skin = Buff, size = 40 },
    { name = "BuffBarCooldownViewer", skin = Bar, size = 30 },
}

-- Setup -------------------------------------------------------------------------

-- Frames are pooled and reused, so each is styled once. A failure is reported
-- once per session instead of on every icon.
local function Skin(item, spec)
    if not item or skinned[item] then return end
    skinned[item] = true
    local ok, err = pcall(spec.skin, item, spec)
    if not ok and not M.lastError then
        M.lastError = tostring(err)
        print("|cffffd100" .. ns.TITLE .. ":|r couldn't restyle a cooldown icon. Please report this: " .. M.lastError)
    end
end

local function Watch(spec)
    if hooked[spec.name] then return true end
    local viewer = _G[spec.name]
    if not viewer or type(viewer.OnAcquireItemFrame) ~= "function" then return false end
    hooked[spec.name] = true
    hooksecurefunc(viewer, "OnAcquireItemFrame", function(_, item) Skin(item, spec) end)
    local pool = viewer.itemFramePool
    if pool and pool.EnumerateActive then
        for item in pool:EnumerateActive() do Skin(item, spec) end
    end
    return true
end

local function WatchAll()
    local all = true
    for _, spec in ipairs(M.VIEWERS) do
        all = Watch(spec) and all
    end
    return all
end

function M:Start()
    if self.started then return end
    self.started = true
    if WatchAll() then return end
    -- Blizzard's Cooldown Manager normally loads first; wait for it if not.
    local watcher = CreateFrame("Frame")
    watcher:RegisterEvent("ADDON_LOADED")
    watcher:SetScript("OnEvent", function(frame, _, name)
        if name ~= "Blizzard_CooldownViewer" then return end
        frame:UnregisterAllEvents()
        WatchAll()
    end)
end

function M:IsSkinned(item)
    return skinned[item] == true
end
