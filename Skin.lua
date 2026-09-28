-- A restyle of Blizzard's Cooldown Manager: square frameless icons with big
-- bold countdown numbers, and Tracked Bars in one of three designs (Glass,
-- Split, Outline) and a colour of your choice, for all of them or bar by bar.
-- Visual only. Blizzard still decides what shows, when, and where (Edit Mode).
-- Cooldowns and auras are secret in combat, so nothing here reads them: each
-- item frame gets its textures, fonts and anchors set once, after Blizzard's
-- own setup, and no key is ever written on Blizzard's frames.
local _, ns = ...

local M = {}
ns.Skin = M

local Style = ns.Style
local OVERLAY_ATLAS = "UI-HUD-CoolDownManager-IconOverlay"
local PIP_ATLAS = "UI-HUD-CoolDownManager-Bar-Pip" -- a Tracked Bar's spark
-- Tracked Bars are 30 tall with a 30 icon; the bar grows from 19 to sit level
-- with the icon's art.
local BAR_HEIGHT = 26
-- Blizzard places icons 4 units closer than the padding setting because its
-- mask trims their edges; trimming 2 from each side of the square art makes
-- the gap between icons match Edit Mode's Padding exactly.
local INSET = 2

local skinned = setmetatable({}, { __mode = "k" })
local bars = setmetatable({}, { __mode = "k" }) -- restyled bar items and the pieces added to them
local decors = setmetatable({}, { __mode = "k" }) -- each icon's border and shadow
local rows = {} -- each icon viewer's border and shadow, round the whole row
M.decors, M.rows = decors, rows
local hooked = {}
local SPLIT_BOX = 46 -- the Split design's time box

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

-- A border and shadow round the icon art, when chosen on the Look page.
local function Decorate(item, icon)
    local decor = Style:Decor(item, icon)
    decors[item] = decor
    Style:ShowDecor(decor, Style:DecorFor("icon"))
end

local function Font(region, name)
    if region and name then region:SetFontObject(name) end
end

-- Item frames -------------------------------------------------------------------

-- Essential and Utility cooldowns, including trinkets and potions.
local function Cooldown(item, spec)
    SquareIcon(item, item.Icon)
    SquareSweep(item.Cooldown, item.Icon)
    Decorate(item, item.Icon)
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
    Decorate(item, item.Icon)
    if item.Cooldown then item.Cooldown:SetCountdownFont(Style:Countdown(spec.size)) end
    Font(item.Applications and item.Applications.Applications, Style:Count(spec.size))
end

-- Tracked buffs shown as bars. Every piece any design uses is made once per
-- bar; Look shows the ones the chosen design needs and colours them, at the
-- start and whenever the choice changes.

-- The spell a bar shows, from Blizzard's settings for the bar rather than
-- from the aura, which can be secret in combat; nil if it can't be read.
local function SpellOf(item)
    local get = item and item.GetBaseSpellID
    if type(get) ~= "function" then return nil end
    local ok, id = pcall(get, item)
    if not ok or (issecretvalue and issecretvalue(id)) or type(id) ~= "number" then return nil end
    return id
end

-- A bar's own colour, when one is chosen for its spell, or the colour for all.
local function BarColour(item)
    local id = SpellOf(item)
    return Style:BarColour(id and ns.BarColours()[id] or ns.Get("barColour"))
end

local function Solid(texture, colour, alpha)
    texture:SetColorTexture(colour[1], colour[2], colour[3], alpha or 1)
end

local function Look(item, parts)
    local bar, design, colour = item.Bar, ns.Get("barStyle"), BarColour(item)
    local glass, split, outline = design == "glass", design == "split", design == "outline"
    bar:SetStatusBarColor(colour[1], colour[2], colour[3], outline and .45 or 1)
    -- A 1px edge round the bar and the icon: black, or the colour for Outline.
    local edge = outline and colour or { 0, 0, 0 }
    Solid(parts.edge, edge)
    if parts.iconEdge then Solid(parts.iconEdge, edge) end
    parts.sheen:SetShown(glass)
    parts.box:SetShown(split)
    parts.divider:SetShown(split)
    -- Only Glass keeps Blizzard's spark where the fill ends.
    if bar.Pip then bar.Pip:SetAlpha(glass and 1 or 0) end
    -- Time on the right, or centred in its own box for Split; the name
    -- stops short of it.
    local duration, name = bar.Duration, bar.Name
    if duration then
        duration:ClearAllPoints()
        if split then
            duration:SetPoint("CENTER", parts.box, "CENTER", 0, 0)
        else
            duration:SetPoint("RIGHT", bar, "RIGHT", -6, 0)
        end
    end
    if name then
        name:ClearAllPoints()
        name:SetPoint("LEFT", bar, "LEFT", 6, 0)
        if split then
            name:SetPoint("RIGHT", parts.box, "LEFT", -6, 0)
        elseif duration then
            name:SetPoint("RIGHT", duration, "LEFT", -6, 0)
        end
        name:SetJustifyH("LEFT")
    end
end

local function Bar(item, spec)
    local iconFrame = item.Icon
    local parts = {}
    if iconFrame and iconFrame.Icon then
        SquareIcon(iconFrame, iconFrame.Icon)
        Font(iconFrame.Applications, Style:Count(spec.size))
        parts.iconEdge = iconFrame:CreateTexture(nil, "BACKGROUND", nil, -8)
        Inset(parts.iconEdge, iconFrame.Icon, -1)
    end
    local bar = item.Bar
    if not bar then return end
    bar:SetHeight(BAR_HEIGHT)
    bar:SetStatusBarTexture(Style.FLAT)
    if bar.BarBG then
        bar.BarBG:SetColorTexture(Style.TRACK[1], Style.TRACK[2], Style.TRACK[3], Style.TRACK[4])
        Inset(bar.BarBG, bar, 0)
    end
    parts.edge = bar:CreateTexture(nil, "BACKGROUND", nil, -8)
    Inset(parts.edge, bar, -1)
    -- Glass: a soft shine across the top.
    parts.sheen = bar:CreateTexture(nil, "OVERLAY", nil, -8)
    parts.sheen:SetPoint("TOPLEFT", bar, "TOPLEFT", 0, 0)
    parts.sheen:SetPoint("TOPRIGHT", bar, "TOPRIGHT", 0, 0)
    parts.sheen:SetHeight(math.floor(BAR_HEIGHT * .45))
    parts.sheen:SetColorTexture(1, 1, 1, .16)
    -- Split: a dark box at the end for the time.
    parts.box = bar:CreateTexture(nil, "OVERLAY", nil, -7)
    parts.box:SetPoint("TOPRIGHT", bar, "TOPRIGHT", 0, 0)
    parts.box:SetPoint("BOTTOMRIGHT", bar, "BOTTOMRIGHT", 0, 0)
    parts.box:SetWidth(SPLIT_BOX)
    parts.box:SetColorTexture(.024, .027, .031, 1)
    parts.divider = bar:CreateTexture(nil, "OVERLAY", nil, -6)
    parts.divider:SetPoint("TOPRIGHT", parts.box, "TOPLEFT", 0, 0)
    parts.divider:SetPoint("BOTTOMRIGHT", parts.box, "BOTTOMLEFT", 0, 0)
    parts.divider:SetWidth(2)
    parts.divider:SetColorTexture(0, 0, 0, 1)
    Font(bar.Name, Style:Font(13))
    Font(bar.Duration, Style:Font(15))
    bars[item] = parts
    Look(item, parts)
end

-- A failure is reported once per session, never thrown into Blizzard's code.
local function Redraw(item, parts)
    local ok, err = pcall(Look, item, parts)
    if not ok and not M.lastError then
        M.lastError = tostring(err)
        print("|cffffd100" .. ns.TITLE .. ":|r couldn't restyle a Tracked Bar. Please report this: " .. M.lastError)
    end
end

-- Blizzard's bars are pooled and change spell, so each one's own colour
-- follows when it does.
local function TrackedBar(item, spec)
    Bar(item, spec)
    local parts = bars[item]
    if parts and type(item.OnCooldownIDSet) == "function" then
        hooksecurefunc(item, "OnCooldownIDSet", function() Redraw(item, parts) end)
    end
end

-- Redraws every restyled bar in the current design and colours.
function M:ApplyBarLook()
    for item, parts in pairs(bars) do Redraw(item, parts) end
end

-- The spells of Blizzard's Tracked Bars, in their order, for the window's
-- list of bars to colour. Read from its bars; nothing on them changes.
function M:TrackedBars()
    local viewer = _G.BuffBarCooldownViewer
    local pool = viewer and viewer.itemFramePool
    if not (pool and pool.EnumerateActive) then return {} end
    local found, seen = {}, {}
    for item in pool:EnumerateActive() do
        local id = SpellOf(item)
        if id and not seen[id] then
            seen[id] = true
            local order = item.layoutIndex
            if type(order) ~= "number" or (issecretvalue and issecretvalue(order)) then order = math.huge end
            found[#found + 1] = { id = id, order = order }
        end
    end
    table.sort(found, function(a, b)
        if a.order ~= b.order then return a.order < b.order end
        return a.id < b.id
    end)
    local ids = {}
    for i, entry in ipairs(found) do ids[i] = entry.id end
    return ids
end

-- A Tracked Bar for the /ccm window's preview, made from the addon's own
-- frames in the shape of Blizzard's so it shows exactly what each design does,
-- in the colour for all bars.
function M:Sample(parent, width)
    local item = CreateFrame("Frame", nil, parent)
    item:SetSize(width, 30)
    local iconFrame = CreateFrame("Frame", nil, item)
    iconFrame:SetSize(30, 30)
    iconFrame:SetPoint("LEFT", item, "LEFT", 0, 0)
    iconFrame.Icon = iconFrame:CreateTexture(nil, "ARTWORK")
    iconFrame.Icon:SetTexture("Interface\\Icons\\INV_Misc_PocketWatch_01")
    iconFrame.Applications = iconFrame:CreateFontString(nil, "OVERLAY") -- a stack count, as on Blizzard's bars
    item.Icon = iconFrame
    local bar = CreateFrame("StatusBar", nil, item)
    bar:SetPoint("LEFT", iconFrame, "RIGHT", 6, 0)
    bar:SetPoint("RIGHT", item, "RIGHT", 0, 0)
    bar:SetMinMaxValues(0, 1)
    bar:SetValue(.68)
    bar.BarBG = bar:CreateTexture(nil, "BACKGROUND")
    bar.Pip = bar:CreateTexture(nil, "OVERLAY")
    bar.Name = bar:CreateFontString(nil, "OVERLAY")
    bar.Duration = bar:CreateFontString(nil, "OVERLAY")
    item.Bar = bar
    Bar(item, { size = 30 })
    bar.Pip:SetAtlas(PIP_ATLAS, true)
    bar.Pip:SetPoint("CENTER", bar:GetStatusBarTexture() or bar, "RIGHT", 0, 0)
    bar.Name:SetText("Tracked bar")
    bar.Duration:SetText("8:42")
    return item
end

-- size is the item's own size in Blizzard's templates; Edit Mode's icon size
-- scales the whole viewer, fonts included. The cooldown rows can have a
-- border and shadow round the whole row; Tracked Buffs come and go, so they
-- only get them round each icon, and the Tracked Bars keep their own edges.
M.VIEWERS = {
    { name = "EssentialCooldownViewer", skin = Cooldown, size = 50, row = true },
    { name = "UtilityCooldownViewer", skin = Cooldown, size = 30, row = true },
    { name = "BuffIconCooldownViewer", skin = Buff, size = 40 },
    { name = "BuffBarCooldownViewer", skin = TrackedBar, size = 30 },
}

-- Whether a row has any icons: an item with a cooldown in it. An empty row
-- keeps two empty items and its size, so it would get an empty box.
local function Filled(viewer)
    local pool = viewer and viewer.itemFramePool
    if not (pool and pool.EnumerateActive) then return false end
    for item in pool:EnumerateActive() do
        local id = item.cooldownID
        if (issecretvalue and issecretvalue(id)) or id ~= nil then return true end
    end
    return false
end

local function ShowRow(name)
    local decor = rows[name]
    if not decor then return end
    local border, shadow = Style:DecorFor("bar")
    local filled = Filled(_G[name])
    Style:ShowDecor(decor, border and filled, shadow and filled)
end

-- Borders and shadows as chosen, on every icon and round each cooldown row.
function M:ApplyDecor()
    local border, shadow = Style:DecorFor("icon")
    for _, decor in pairs(decors) do Style:ShowDecor(decor, border, shadow) end
    for name in pairs(rows) do ShowRow(name) end
end

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
    -- The row's icons sit INSET inside its edge, like each icon in its item.
    -- Shown while the row has icons, checked whenever Blizzard lays it out.
    if spec.row then
        rows[spec.name] = Style:Decor(viewer, viewer, INSET)
        hooksecurefunc(viewer, "RefreshLayout", function() ShowRow(spec.name) end)
        ShowRow(spec.name)
    end
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
