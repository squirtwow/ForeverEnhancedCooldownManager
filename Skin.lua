-- A restyle of Blizzard's Cooldown Manager: square frameless icons with big
-- bold countdown numbers, and Tracked Bars in one of four designs (Glass,
-- Split, Outline, Block) and a colour of your choice, for all of them or bar
-- by bar, flat or faded (Colour fade).
-- Visual only. Blizzard still decides what shows, when, and where (Edit Mode).
-- Cooldowns and auras are secret in combat, so nothing here reads them: each
-- item frame gets its textures, fonts and anchors set once, after Blizzard's
-- own setup (and the swipe's colour after each refresh, once Icon details
-- changes it), and no key is ever written on Blizzard's frames.
local _, ns = ...

local M = {}
ns.Skin = M

local Style = ns.Style
local OVERLAY_ATLAS = "UI-HUD-CoolDownManager-IconOverlay"
local PIP_ATLAS = "UI-HUD-CoolDownManager-Bar-Pip" -- a Tracked Bar's spark
-- Tracked Bars are 30 tall with a 30 icon; the bar grows from 19 to sit level
-- with the icon's art, or for Block slims to 18, centred on it.
local BAR_HEIGHT = 26
local BLOCK_HEIGHT = 18
-- Blizzard places icons 4 units closer than the padding setting because its
-- mask trims their edges; trimming 2 from each side of the square art makes
-- the gap between icons match Edit Mode's Padding exactly.
local INSET = 2

local skinned = setmetatable({}, { __mode = "k" })
local bars = setmetatable({}, { __mode = "k" }) -- restyled bar items and the pieces added to them
local decors = setmetatable({}, { __mode = "k" }) -- each icon's border and shadow
local rows = {} -- each icon viewer's border and shadow, round the whole row
local keys = setmetatable({}, { __mode = "k" }) -- Essential/Utility item -> { frame, text, spec, lift, keyed }: the addon's own
local room = setmetatable({}, { __mode = "k" }) -- item -> { top, lift, spot } last applied to its count and countdown
-- Icon details: every Essential, Utility and buff icon -> its spec; those
-- whose refreshes are hooked, and those whose swipe or edge line the addon
-- has set (put back as Blizzard draws them once the details are back to
-- the defaults); and those with the addon's edge line on now (put back as
-- soon as Edge line goes off, even while the swipe stays changed).
local sweeps = setmetatable({}, { __mode = "k" })
local sweepHooks = setmetatable({}, { __mode = "k" })
local painted = setmetatable({}, { __mode = "k" })
local edged = setmetatable({}, { __mode = "k" })
M.decors, M.rows, M.keys = decors, rows, keys
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

-- A number from one of the item's own getters, such as the spell a bar or
-- icon shows, from Blizzard's settings for it rather than from the aura,
-- which can be secret in combat; nil if it can't be read.
local function Read(item, method)
    local get = item and item[method]
    if type(get) ~= "function" then return nil end
    local ok, value = pcall(get, item)
    if not ok or (issecretvalue and issecretvalue(value)) or type(value) ~= "number" then return nil end
    return value
end

local function SpellOf(item)
    return Read(item, "GetBaseSpellID")
end

-- Keybinds ------------------------------------------------------------------------
-- The key that casts each Essential and Utility icon's spell, from your action
-- bars (Keybinds.lua), in the addon's own text on its own frame over the
-- icon's art. Items are pooled and change spell, so the key follows each one;
-- the hooks only read what was worked out outside combat.

-- A level above the item's sweep and charge count; only levels are read.
local function Above(item)
    local level = item:GetFrameLevel()
    if item.Cooldown then level = math.max(level, item.Cooldown:GetFrameLevel()) end
    if item.ChargeCount then level = math.max(level, item.ChargeCount:GetFrameLevel()) end
    return level + 2
end

local function KeyFor(item)
    local binds = ns.Keybinds
    return binds and (binds:ForSpell(SpellOf(item)) or binds:ForSlot(Read(item, "GetEquipSlot"))) or nil
end

-- Blizzard's charge count goes top-right while the icon's own key shows along
-- the bottom, and the countdown moves clear of the key, or to the spot
-- picked in Icon details (a buff icon's too, which has no key). Both are
-- only touched when something must move, or be put back after: Blizzard's
-- own anchors are the count at BOTTOMRIGHT -2,2 of ChargeCount and the
-- countdown at the sweep's centre.
local function Room(item)
    local parts = keys[item]
    local keyed = parts and parts.keyed
    local top, lift, spot = Style:CountUp(keyed), parts and parts.lift or 0, ns.Get("countdownSpot")
    local was = room[item]
    if was then
        if was.top == top and was.lift == lift and was.spot == spot then return end
    elseif not top and lift == 0 and spot == "CENTER" then
        return
    end
    room[item] = { top = top, lift = lift, spot = spot }
    local cooldown, numbers = item.Cooldown, nil
    local get = cooldown and cooldown.GetCountdownFontString
    if type(get) == "function" then
        local ok, found = pcall(get, cooldown)
        if ok then numbers = found end
    end
    -- (A charge count only on an icon with a key: the Essential and Utility ones.)
    local box = parts and item.ChargeCount
    Style:KeyRoom(box and box.Current, box, 2, numbers, cooldown, lift, keyed)
end

-- A key showing up or going (a new spell, a binding changed) moves the count
-- with it. Nothing is looked up while keybinds are off, or with none (an
-- item handed out again before it has a spell), and nothing is set again
-- while the key stays the same: Blizzard hands its icons out again on every
-- relayout.
local function ShowKey(item, none)
    local parts = keys[item]
    local key = not none and ns.Get("keybinds") and KeyFor(item) or nil
    if parts.keyed ~= nil and parts.key == key then return end
    parts.key = key
    parts.keyed = Style:SetKey(parts.text, key)
    Room(item)
end

-- A failure is reported once per session, never thrown into Blizzard's code.
local function SafeShowKey(item, none)
    local ok, err = pcall(ShowKey, item, none)
    if not ok and not M.lastError then
        M.lastError = tostring(err)
        print("|cffffd100" .. ns.TITLE .. ":|r couldn't show a keybind on a cooldown icon. Please report this: " .. M.lastError)
    end
end

-- Sized to the icon's own size in Blizzard's template, as the countdown is.
local function KeyLook(item)
    local parts = keys[item]
    parts.frame:SetFrameLevel(Above(item))
    parts.lift = Style:KeyLook(parts.text, parts.frame, parts.spec.size - 2 * INSET, Style:CountdownSize(parts.spec.size))
    Room(item)
end

-- The key's own frame over the art, never taking the mouse. The acquire hook
-- runs before Blizzard gives a pooled item its spell, so the key is shown as
-- it gets one, and hidden as one is cleared (see Watch for pooled items
-- handed out again).
local function Keybind(item, spec)
    local art = spec.size - 2 * INSET
    local frame = CreateFrame("Frame", nil, item)
    frame:SetSize(art, art)
    frame:SetAllPoints(item.Icon)
    frame:EnableMouse(false)
    keys[item] = { frame = frame, text = Style:KeyText(frame), spec = spec }
    KeyLook(item)
    for _, method in ipairs({ "OnCooldownIDSet", "OnCooldownIDCleared" }) do
        if type(item[method]) == "function" then
            hooksecurefunc(item, method, function() SafeShowKey(item) end)
        end
    end
    ShowKey(item)
end

-- Icon details -------------------------------------------------------------------
-- The swipe's colour and see-through and the edge line picked on the Look
-- page, on Blizzard's Essential, Utility and buff icons, through the
-- cooldown's own setters only. Blizzard sets its swipe and edge again each
-- time it refreshes an icon, so once either differs from the defaults each
-- icon's refresh is post-hooked to set them after it; until then nothing is
-- hooked, set or read, and the icons stay exactly as Blizzard draws them.
-- Blizzard's gold swipe over a buff of the icon's spell that's up keeps its
-- own colour, so it still tells an aura from a cooldown. Nothing is read
-- that a fight keeps secret: only which of Blizzard's two swipe colours it
-- picked, and whether it draws its own edge line (for charges).

-- Whether the icon shows Blizzard's gold aura swipe now.
local function AuraSwipe(item)
    local constants = _G.CooldownViewerConstants
    local gold = type(constants) == "table" and constants.ITEM_AURA_COLOR or nil
    if gold == nil then return false end
    local shows = item.cooldownSwipeColor
    if issecretvalue and issecretvalue(shows) then return true end
    return rawequal(shows, gold)
end

-- The swipe and edge line as picked. back: put Blizzard's own back (the
-- defaults' swipe is Blizzard's own dark one; its edge line only for a
-- spell's charges coming back, in its own colour). Blizzard's own edge line
-- comes back too as soon as Edge line goes off, with the swipe still
-- changed: Blizzard never sets its colour, so a tint would stay on it.
local function Swipe(item, back)
    local cooldown = item.Cooldown
    if not cooldown then return end
    if not AuraSwipe(item) then
        local colour, alpha = Style:Swipe()
        cooldown:SetSwipeColor(colour[1], colour[2], colour[3], alpha)
    end
    if ns.Get("swipeEdge") == true then
        local tint = Style:EdgeColour(ns.ColourKey("edgeColour"))
        cooldown:SetDrawEdge(true)
        cooldown:SetEdgeColor(tint[1], tint[2], tint[3], 1)
        edged[item] = true
    elseif back or edged[item] then
        cooldown:SetDrawEdge(item.cooldownShowDrawEdge == true)
        cooldown:SetEdgeColor(1, 1, 1, 1)
        edged[item] = nil
    end
end

-- After each of Blizzard's refreshes of the icon, while the details differ
-- from the defaults. A failure is reported once, never thrown into
-- Blizzard's code.
local function AfterRefresh(item)
    if not Style:SwipeChanged() then return end
    local ok, err = pcall(Swipe, item)
    if not ok and not M.lastError then
        M.lastError = tostring(err)
        print("|cffffd100" .. ns.TITLE .. ":|r couldn't colour a cooldown icon's swipe. Please report this: " .. M.lastError)
    end
end

-- A cooldown icon's refresh and a buff icon's (CooldownViewer.lua's
-- RefreshSpellCooldownInfo and RefreshCooldownInfo), hooked once.
local function HookSwipe(item)
    if sweepHooks[item] then return end
    sweepHooks[item] = true
    for _, method in ipairs({ "RefreshSpellCooldownInfo", "RefreshCooldownInfo" }) do
        if type(item[method]) == "function" then
            hooksecurefunc(item, method, function() AfterRefresh(item) end)
        end
    end
end

-- The swipe on one icon as picked now: hooked and set while it differs
-- from the defaults; put back once, as they come back.
local function Sweep(item)
    if Style:SwipeChanged() then
        HookSwipe(item)
        Swipe(item)
        painted[item] = true
    elseif painted[item] then
        Swipe(item, true)
        painted[item] = nil
    end
end

-- All of it on one icon: the countdown's size and colour, its spot (clear
-- of a key in the middle), and the swipe.
local function Detail(item, spec)
    if item.Cooldown then item.Cooldown:SetCountdownFont(Style:Countdown(spec.size)) end
    if keys[item] then KeyLook(item) else Room(item) end
    Sweep(item)
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
    Keybind(item, spec)
    sweeps[item] = spec
    Sweep(item)
end

-- Tracked buffs shown as icons.
local function Buff(item, spec)
    SquareIcon(item, item.Icon)
    SquareSweep(item.Cooldown, item.Icon)
    Decorate(item, item.Icon)
    if item.Cooldown then item.Cooldown:SetCountdownFont(Style:Countdown(spec.size)) end
    Font(item.Applications and item.Applications.Applications, Style:Count(spec.size))
    Room(item)
    sweeps[item] = spec
    Sweep(item)
end

-- Tracked buffs shown as bars. Every piece any design uses is made once per
-- bar; Look shows the ones the chosen design needs and colours them, at the
-- start and whenever the choice changes.

local BLACK = { 0, 0, 0 }

local function Solid(texture, colour, alpha)
    texture:SetColorTexture(colour[1], colour[2], colour[3], alpha or 1)
end

-- The bar's fill in the texture chosen on the Look page, set only when it
-- changes: this runs whenever Blizzard gives a pooled bar a new spell. True
-- when it changed.
local function Fill(bar, parts)
    local texture = Style:BarTexture()
    if parts.texture == texture then return false end
    parts.texture = texture
    bar:SetStatusBarTexture(texture)
    return true
end

-- Block's slimmer bar and its text a size smaller, or back as they were; set
-- only when the design goes to or from Block.
local function Slim(bar, parts, block)
    if parts.slim == block then return end
    parts.slim = block
    bar:SetHeight(block and BLOCK_HEIGHT or BAR_HEIGHT)
    Font(bar.Name, Style:Font(block and 12 or 13))
    Font(bar.Duration, Style:Font(block and 13 or 15))
end

-- The bar in the design and colour chosen: its own colour when one is chosen
-- for its spell (at any rank), or the colour for all, flat or faded. As
-- Blizzard gives a pooled bar a spell (after every relayout), a bar with the
-- same spell, design, colour for all, darkness, edges and fade as last time
-- is left as it is; force (a Look page choice, which may be its own colour)
-- draws it again.
local function Look(item, parts, force)
    local bar, design, all, id = item.Bar, ns.Get("barStyle"), ns.ColourKey("barColour"), SpellOf(item)
    local dark, thick, fade = ns.Get("barDarkness"), ns.Get("thickEdges"), Style:Fades()
    local filled = Fill(bar, parts)
    if not (force or filled) and parts.drawn and parts.spell == id and parts.design == design and parts.all == all
        and parts.dark == dark and parts.thick == thick and parts.fade == fade then
        return
    end
    parts.drawn, parts.spell, parts.design, parts.all, parts.dark, parts.thick = true, id, design, all, dark, thick
    parts.fade = fade
    local colour = Style:BarColour(id and ns.BarColourFor(id) or all)
    local glass, split, outline = design == "glass", design == "split", design == "outline"
    Style:FillColour(bar, colour, outline and .45 or 1)
    if parts.track then parts.track:SetColorTexture(Style:TrackColour()) end
    -- A 1px edge round the bar and the icon: black, or the colour for Outline;
    -- with Thick edges, a second pixel inside each, and Block's warm line
    -- inside those.
    local edge = outline and colour or BLACK
    Solid(parts.edge, edge)
    Style:ShowInnerEdge(parts.inner, edge)
    Style:ShowBlockLine(parts.line)
    if parts.iconEdge then
        Solid(parts.iconEdge, edge)
        Style:ShowInnerEdge(parts.iconInner, edge)
        Style:ShowBlockLine(parts.iconLine)
    end
    Slim(bar, parts, design == "block")
    Style:ShowSheen(parts.sheen, glass)
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
        -- One line, cut short when too long, as Blizzard's own look does;
        -- without a height it would wrap and spill out of the bar.
        name:SetWordWrap(false)
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
        parts.iconInner = Style:InnerEdge(iconFrame, iconFrame.Icon)
        parts.iconLine = Style:BlockLine(iconFrame, iconFrame.Icon)
    end
    local bar = item.Bar
    if not bar then return end
    bar:SetHeight(BAR_HEIGHT)
    Fill(bar, parts)
    -- Blizzard's backing becomes the track (Look colours it).
    if bar.BarBG then
        parts.track = bar.BarBG
        Inset(bar.BarBG, bar, 0)
    end
    parts.edge = bar:CreateTexture(nil, "BACKGROUND", nil, -8)
    Inset(parts.edge, bar, -1)
    parts.inner = Style:InnerEdge(bar, bar)
    parts.line = Style:BlockLine(bar, bar)
    -- Glass: a soft shine across the top.
    local shine, height = bar:CreateTexture(nil, "OVERLAY", nil, -8), math.floor(BAR_HEIGHT * .45)
    shine:SetPoint("TOPLEFT", bar, "TOPLEFT", 0, 0)
    shine:SetPoint("TOPRIGHT", bar, "TOPRIGHT", 0, 0)
    shine:SetHeight(height)
    shine:SetColorTexture(1, 1, 1, .16)
    parts.sheen = Style:Sheen(bar, shine, height)
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
    parts.slim = false -- the height and fonts above; Look slims it for Block
    bars[item] = parts
    Look(item, parts, true)
end

-- A failure is reported once per session, never thrown into Blizzard's code.
local function Redraw(item, parts, force)
    local ok, err = pcall(Look, item, parts, force)
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

-- Redraws every restyled bar in the current design, colours and texture.
function M:ApplyBarLook()
    for item, parts in pairs(bars) do Redraw(item, parts, true) end
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

-- How many of a row's items have a cooldown in them, how many items it has,
-- and the last filled one. Blizzard always keeps at least two items and room
-- for them, so an empty row would get an empty box, and a row with one
-- cooldown a box with an empty slot in it.
local function Filled(viewer)
    local pool = viewer and viewer.itemFramePool
    if not (pool and pool.EnumerateActive) then return 0, 0 end
    local filled, active, last = 0, 0, nil
    for item in pool:EnumerateActive() do
        active = active + 1
        local id = item.cooldownID
        if (issecretvalue and issecretvalue(id)) or id ~= nil then
            filled, last = filled + 1, item
        end
    end
    return filled, active, last
end

-- The box goes round the whole row, or round the one icon's art when a row
-- has only one cooldown, and shows only while the row has any.
local function ShowRow(name)
    local decor = rows[name]
    if not decor then return end
    local border, shadow = Style:DecorFor("bar")
    local viewer = _G[name]
    local filled, active, last = Filled(viewer)
    if filled == 1 and active > 1 and last.Icon then
        decor.region, decor.inset = last.Icon, 0
    else
        decor.region, decor.inset = viewer, INSET
    end
    Style:ShowDecor(decor, border and filled > 0, shadow and filled > 0)
end

-- Borders and shadows as chosen, on every icon and round each cooldown row.
function M:ApplyDecor()
    local border, shadow = Style:DecorFor("icon")
    for _, decor in pairs(decors) do Style:ShowDecor(decor, border, shadow) end
    for name in pairs(rows) do ShowRow(name) end
end

-- Keybinds placed and sized as chosen on the Look page, on every Essential
-- and Utility icon.
function M:ApplyKeybinds()
    for item in pairs(keys) do
        local ok, err = pcall(KeyLook, item)
        if not ok and not M.lastError then
            M.lastError = tostring(err)
            print("|cffffd100" .. ns.TITLE .. ":|r couldn't place a keybind on a cooldown icon. Please report this: " .. M.lastError)
        end
        SafeShowKey(item)
    end
end

-- The keys again after a binding or page change; text only, so in combat too.
function M:ShowKeys()
    for item in pairs(keys) do SafeShowKey(item) end
end

-- Icon details picked on the Look page, on every Essential, Utility and
-- buff icon: cosmetic setters only, so in combat too.
function M:ApplyIconDetails()
    for item, spec in pairs(sweeps) do
        local ok, err = pcall(Detail, item, spec)
        if not ok and not M.lastError then
            M.lastError = tostring(err)
            print("|cffffd100" .. ns.TITLE .. ":|r couldn't restyle a cooldown icon's details. Please report this: " .. M.lastError)
        end
    end
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
    hooksecurefunc(viewer, "OnAcquireItemFrame", function(_, item)
        Skin(item, spec)
        -- Blizzard's pool empties an item it takes back without clearing its
        -- cooldown the usual way, so nothing else would hide the old key when
        -- the item comes back as one of Edit Mode's empty placeholders. Its
        -- old key goes here: it has no spell until Blizzard gives it one
        -- (OnCooldownIDSet), so there's nothing to look up yet.
        if keys[item] then SafeShowKey(item, true) end
    end)
    -- The row's icons sit INSET inside its edge, like each icon in its item.
    -- Checked whenever Blizzard lays the row out or refreshes its cooldowns:
    -- going between none, one and two cooldowns in Cooldown Settings keeps
    -- two items, so Blizzard only refreshes them and never lays the row out.
    -- Laying a shown row out refreshes it too, so it's checked twice; the
    -- second time sets nothing, as nothing changed (Style:ShowDecor).
    if spec.row then
        rows[spec.name] = Style:Decor(viewer, viewer, INSET)
        for _, method in ipairs({ "RefreshLayout", "RefreshData" }) do
            if type(viewer[method]) == "function" then
                hooksecurefunc(viewer, method, function() ShowRow(spec.name) end)
            end
        end
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

-- Whether an item has the addon's look on it. For the tests.
function M:IsSkinned(item)
    return skinned[item] == true
end
