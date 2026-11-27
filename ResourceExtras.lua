-- Two extras on the Personal Resource Display's bars, as restyled by
-- Resource.lua (a player's ideas, 28 Nov 2026), each off unless ticked on the
-- Look page:
--   Colour by amount: health from red when low through yellow to green when
--   full; power in its own colour, darker as it empties.
--   Queued swing cost: with Heroic Strike, Cleave, Maul or Raptor Strike
--   waiting for your next swing, what it will cost sits as a dark band at the
--   end of your power bar until the swing goes off.
-- Your health and power are hidden from addons, so nothing here ever reads,
-- compares or works out a sum with them. The game reads them itself: through
-- a colour curve, handing back a colour that goes straight onto the bar, and
-- as the most a status bar can hold, so the cost lands at the right spot.
-- Whether a spell waits for your swing and what it costs are open, even in a
-- fight (SpellDocumentation.lua). Visual only, on the addon's own pieces and
-- the bars' fill colour, as Resource.lua does.
local _, ns = ...

local X = {}
ns.ResourceExtras = X

local function Open(v) return not (issecretvalue and issecretvalue(v)) end
local function Number(v) return Open(v) and type(v) == "number" and v or nil end

---------------------------------------------------------------------------
-- Colour by amount
---------------------------------------------------------------------------

local LOW, MID, HEALTHY = { 1, .12, .12 }, { 1, .82, .1 }, { .15, .85, .2 }
-- Power keeps its own colour and darkens as it empties (Squirt, 28 Nov 2026:
-- red to yellow to its colour ran rage red to yellow to red, and barely moved
-- energy's yellow). EMPTY is how much of the colour is left at nothing.
local EMPTY = .3
local curves = {}

-- One curve per colour and kind, made once. Health: red, yellow at half,
-- then green. Power: its colour darkened at empty, then in full.
local function Curve(colour, dim)
    local r, g, b = Number(colour[1]), Number(colour[2]), Number(colour[3])
    if not (r and g and b) then return nil end
    local key = string.format("%s %.3f %.3f %.3f", dim and "dim" or "health", r, g, b)
    if curves[key] ~= nil then return curves[key] or nil end
    local make = C_CurveUtil and C_CurveUtil.CreateColorCurve
    local ok, curve = pcall(make)
    if not ok or not curve or type(CreateColor) ~= "function" then
        curves[key] = false
        return nil
    end
    if Enum and Enum.LuaCurveType then pcall(curve.SetType, curve, Enum.LuaCurveType.Linear) end
    if dim then
        curve:AddPoint(0, CreateColor(r * EMPTY, g * EMPTY, b * EMPTY))
    else
        curve:AddPoint(0, CreateColor(LOW[1], LOW[2], LOW[3]))
        curve:AddPoint(.5, CreateColor(MID[1], MID[2], MID[3]))
    end
    curve:AddPoint(1, CreateColor(r, g, b))
    curves[key] = curve
    return curve
end

-- The colour the game hands back goes onto the fill as it is: never opened.
local function Lay(texture, result)
    texture:SetVertexColor(result:GetRGB())
end

-- One restyled bar (Resource.lua's Look calls this after colouring it).
function X:Paint(bar, state)
    if not (bar and state and ns.Get("prdByAmount")) then return end
    local health = state.setting == "prdHealth"
    local curve = Curve(health and HEALTHY or state.colourNow or HEALTHY, not health)
    if not curve then return end
    local ok, result
    if health then
        ok, result = pcall(UnitHealthPercent, "player", true, curve)
    else
        ok, result = pcall(UnitPowerPercent, "player", state.powerType, false, curve)
    end
    if not ok or result == nil then return end
    local texture = bar.GetStatusBarTexture and bar:GetStatusBarTexture()
    if texture then pcall(Lay, texture, result) end
end

local function PaintAll()
    local restyled = ns.Resource and ns.Resource.restyled
    if not restyled then return end
    for bar, state in pairs(restyled) do X:Paint(bar, state) end
end

---------------------------------------------------------------------------
-- Queued swing cost
---------------------------------------------------------------------------

-- The next-swing spells, every rank (Ranks.lua), by their English names
-- only as keys into that list: what's checked is each rank's ID.
local SWINGS = { "Heroic Strike", "Cleave", "Maul", "Raptor Strike" }
local SHADE = { 0, 0, 0, .55 }

-- Every rank's ID of the next-swing spells, as a set.
local swingIDs
local function SwingIDs()
    if swingIDs then return swingIDs end
    swingIDs = {}
    for _, name in ipairs(SWINGS) do
        for _, id in ipairs(ns.RANKS and ns.RANKS[name] or {}) do swingIDs[id] = true end
    end
    return swingIDs
end

-- The action bar slots holding one of them (as a spell, or a macro that
-- casts one), found again whenever your bars change. The game marks a
-- waiting swing on its button (IsCurrentAction, seen in a fight 28 Nov 2026:
-- slot 109 while Heroic Strike waited) but not on the spell itself
-- (C_Spell.IsCurrentSpell answered false then).
local MAX_SLOT = 180
local slots, slotsDirty = {}, true
local function Call(api, ...)
    if type(api) ~= "function" then return nil end
    local ok, a, b = pcall(api, ...)
    if ok then return a, b end
    return nil
end
local function FindSlots()
    slotsDirty = false
    slots = {}
    local info = C_ActionBar and C_ActionBar.GetActionInfo or GetActionInfo
    local ids = SwingIDs()
    for slot = 1, MAX_SLOT do
        local kind, id = Call(info, slot)
        if Open(kind) and Open(id) then
            if kind == "macro" then id = Call(GetMacroSpell, id) end
            if Open(id) and type(id) == "number" and ids[id] then slots[#slots + 1] = { slot = slot, id = id } end
        end
    end
end

-- The spell waiting for your swing, by the ID of its rank, or nil.
local function Queued()
    if slotsDirty then FindSlots() end
    local current = C_ActionBar and C_ActionBar.IsCurrentAction or IsCurrentAction
    for _, held in ipairs(slots) do
        local on = Call(current, held.slot)
        if Open(on) and on == true then return held.id end
    end
    return nil
end

-- What it costs, in the bar's own power.
local function Cost(id)
    local ask = C_Spell and C_Spell.GetSpellPowerCost
    if type(ask) ~= "function" then return nil end
    local ok, costs = pcall(ask, id)
    if not ok or type(costs) ~= "table" then return nil end
    for _, entry in ipairs(costs) do
        local cost = type(entry) == "table" and Number(entry.cost)
        if cost and cost > 0 then return cost end
    end
    return nil
end

-- The band: a clip over the bar, and inside it a bar that fills leftwards
-- from where your power ends, as wide as the whole bar, holding as much as
-- your power can (the game's number, handed on as it is) with the cost in it.
local band
local function Band(bar)
    if band and band.owner == bar then return band end
    local clip = CreateFrame("Frame", nil, bar)
    clip:SetAllPoints(bar)
    clip:SetClipsChildren(true)
    clip:SetFrameLevel(bar:GetFrameLevel() + 3)
    local cost = CreateFrame("StatusBar", nil, clip)
    cost:SetStatusBarTexture("Interface\\Buttons\\WHITE8X8")
    cost:SetStatusBarColor(SHADE[1], SHADE[2], SHADE[3], SHADE[4])
    cost:SetReverseFill(true)
    local fill = bar:GetStatusBarTexture()
    cost:SetPoint("TOPRIGHT", fill, "TOPRIGHT", 0, 0)
    cost:SetPoint("BOTTOMRIGHT", fill, "BOTTOMRIGHT", 0, 0)
    -- Its own line where the cost begins, so it reads as a part held back.
    local edge = cost:CreateTexture(nil, "OVERLAY")
    edge:SetColorTexture(1, 1, 1, .7)
    edge:SetWidth(1)
    edge:SetPoint("TOP", cost:GetStatusBarTexture(), "TOPLEFT", 0, 0)
    edge:SetPoint("BOTTOM", cost:GetStatusBarTexture(), "BOTTOMLEFT", 0, 0)
    clip:Hide()
    band = { owner = bar, clip = clip, cost = cost }
    return band
end

local function Hide()
    if band then band.clip:Hide() end
end

local function ShowCost()
    local bar = X.main
    if not (bar and ns.Get("prdQueued") and bar:IsVisible()) then return Hide() end
    local id = Queued()
    local cost = id and Cost(id)
    if not cost then return Hide() end
    local width = Number(bar:GetWidth())
    if not width or width <= 0 then return Hide() end
    local b = Band(bar)
    b.cost:SetWidth(width)
    local ok = pcall(b.cost.SetMinMaxValues, b.cost, 0, UnitPowerMax("player"))
    if not ok then return Hide() end
    b.cost:SetValue(cost)
    b.clip:Show()
end

---------------------------------------------------------------------------
-- Driving it
---------------------------------------------------------------------------

local driver = CreateFrame("Frame")
local waited = 0
driver:SetScript("OnUpdate", function(_, elapsed)
    waited = waited + (Number(elapsed) or 0)
    if waited < .1 then return end
    waited = 0
    local ok = pcall(ShowCost)
    if not ok then Hide() end
end)
driver:SetScript("OnEvent", function(_, _, unit)
    if unit == nil or (Open(unit) and unit == "player") then PaintAll() end
end)
for _, event in ipairs({ "UNIT_HEALTH", "UNIT_MAXHEALTH", "UNIT_POWER_FREQUENT", "UNIT_MAXPOWER", "UNIT_DISPLAYPOWER",
    "PLAYER_ENTERING_WORLD" }) do
    pcall(driver.RegisterUnitEvent, driver, event, "player")
end
pcall(driver.RegisterEvent, driver, "PLAYER_ENTERING_WORLD")

-- Your bars changed: which slots hold a next-swing spell is found again.
local barsWatch = CreateFrame("Frame")
barsWatch:SetScript("OnEvent", function() slotsDirty = true end)
for _, event in ipairs({ "ACTIONBAR_SLOT_CHANGED", "UPDATE_BONUS_ACTIONBAR", "ACTIONBAR_PAGE_CHANGED", "SPELLS_CHANGED",
    "UPDATE_MACROS", "PLAYER_ENTERING_WORLD" }) do
    pcall(barsWatch.RegisterEvent, barsWatch, event)
end

-- A tick changed on the Look page: painted again now, the band hidden at once.
function X:Refresh()
    if ns.Resource and ns.Resource.Apply then pcall(ns.Resource.Apply, ns.Resource) end
    PaintAll()
    if not ns.Get("prdQueued") then Hide() end
end
