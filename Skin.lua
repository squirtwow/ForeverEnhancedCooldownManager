-- Classic look for Blizzard's Cooldown Manager: square 2004-style icons with a
-- thin dark edge, a square cooldown sweep, and Classic buff bars.
-- Visual only. Blizzard still decides what shows, when, and where (Edit Mode).
-- Cooldowns and auras are secret in combat, so nothing here reads them: each
-- item frame gets its textures, fonts and anchors set once, after Blizzard's
-- own setup, and no key is ever written on Blizzard's frames.
local _, ns = ...

local M = {}
ns.Skin = M

local SQUARE = "Interface\\Buttons\\WHITE8X8"
local BAR = "Interface\\TargetingFrame\\UI-StatusBar"
local OVERLAY_ATLAS = "UI-HUD-CoolDownManager-IconOverlay"
local EDGE = { 0, 0, 0, .9 }
local BAR_BG = { 0, 0, 0, .5 }
local BAR_COLOUR = { 1, .5, .25 } -- Blizzard's own buff-bar colour.
-- Buff icons get no timer font from Blizzard, so they use the 20pt default,
-- which fills the icon with "56m"; this is the next size down (16pt).
local BUFF_TIMER_FONT = "SystemFont_Shadow_Large_Outline"

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

local function Edge(owner, anchor)
    local edge = owner:CreateTexture(nil, "BACKGROUND", nil, -8)
    edge:SetColorTexture(EDGE[1], EDGE[2], EDGE[3], EDGE[4])
    edge:SetPoint("TOPLEFT", anchor, "TOPLEFT", -1, 1)
    edge:SetPoint("BOTTOMRIGHT", anchor, "BOTTOMRIGHT", 1, -1)
    return edge
end

-- The rounded mask and the modern frame art go, so the icon shows square with
-- its own bevelled edge, as icons did in 2004. Blizzard places icons 4 units
-- closer than the padding setting because the mask trims their edges; the
-- inset keeps a small gap between square icons at the default spacing.
local function SquareIcon(frame, icon, inset)
    for _, region in ipairs(Regions(frame)) do
        local kind = region:GetObjectType()
        if kind == "MaskTexture" then
            icon:RemoveMaskTexture(region)
        elseif kind == "Texture" and region:GetAtlas() == OVERLAY_ATLAS then
            region:SetAlpha(0)
        end
    end
    Inset(icon, frame, inset)
    Edge(frame, icon)
end

local function SquareSweep(cooldown, icon)
    if not cooldown then return end
    Inset(cooldown, icon, 0)
    cooldown:SetSwipeTexture(SQUARE)
end

local function Font(region, object)
    if region and object then region:SetFontObject(object) end
end

-- Item frames -------------------------------------------------------------------

-- Essential and Utility cooldowns, including trinkets and potions.
local function Cooldown(item, inset)
    SquareIcon(item, item.Icon, inset)
    SquareSweep(item.Cooldown, item.Icon)
    -- Out of range already tints the icon red, as in Classic; the modern
    -- shadow and the end-of-cooldown sparkle stay hidden.
    if item.OutOfRange then item.OutOfRange:SetAlpha(0) end
    if item.CooldownFlash then item.CooldownFlash:SetAlpha(0) end
end

-- Tracked buffs shown as icons.
local function Buff(item, inset)
    SquareIcon(item, item.Icon, inset)
    SquareSweep(item.Cooldown, item.Icon)
    if item.Cooldown and _G[BUFF_TIMER_FONT] then item.Cooldown:SetCountdownFont(BUFF_TIMER_FONT) end
end

-- Tracked buffs shown as bars.
local function Bar(item, inset)
    local iconFrame = item.Icon
    if iconFrame and iconFrame.Icon then SquareIcon(iconFrame, iconFrame.Icon, inset) end
    local bar = item.Bar
    if not bar then return end
    bar:SetStatusBarTexture(BAR)
    bar:SetStatusBarColor(BAR_COLOUR[1], BAR_COLOUR[2], BAR_COLOUR[3])
    if bar.BarBG then
        bar.BarBG:SetColorTexture(BAR_BG[1], BAR_BG[2], BAR_BG[3], BAR_BG[4])
        Inset(bar.BarBG, bar, 0)
    end
    Edge(bar, bar)
    if bar.Pip then bar.Pip:SetAlpha(0) end
    Font(bar.Name, GameFontHighlight)
    Font(bar.Duration, GameFontHighlightSmall)
end

M.VIEWERS = {
    { name = "EssentialCooldownViewer", skin = Cooldown, inset = 2 },
    { name = "UtilityCooldownViewer", skin = Cooldown, inset = 1.5 },
    { name = "BuffIconCooldownViewer", skin = Buff, inset = 1.5 },
    { name = "BuffBarCooldownViewer", skin = Bar, inset = 1 },
}

-- Setup -------------------------------------------------------------------------

-- Frames are pooled and reused, so each is styled once. A failure is reported
-- once per session instead of on every icon.
local function Skin(item, spec)
    if not item or skinned[item] then return end
    skinned[item] = true
    local ok, err = pcall(spec.skin, item, spec.inset)
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
