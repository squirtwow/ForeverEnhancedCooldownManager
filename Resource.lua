-- Blizzard's Personal Resource Display (Options > Combat), restyled like the
-- Tracked Bars: its health and power bars in the same design, each in
-- Blizzard's colour or one of yours. Some specs get a second mana bar under
-- the main one: it's hidden while the main bar is mana too, so it never just
-- repeats it, and half as tall in bear, cat and other forms. While a layout
-- stacks your bars around it, it can be as wide as your widest row. Combo
-- points, which Forever's display leaves out, can go under it, and your
-- health and power as text on its bars.
-- Visual only. Blizzard still decides what shows and where: only colours,
-- textures, sizes and the addon's own pieces change, and no key is ever
-- written on Blizzard's frames.
local _, ns = ...

local R = {}
ns.Resource = R

local Style = ns.Style
local BG_ATLAS = "UI-HUD-CoolDownManager-Bar-BG" -- the art behind each bar
local MANA = Enum and Enum.PowerType and Enum.PowerType.Mana or 0

local bars = setmetatable({}, { __mode = "k" }) -- restyled bars and what's added to them
local painting = setmetatable({}, { __mode = "k" }) -- a colour the addon is setting itself

-- Something went wrong restyling the display: you're told once.
local function Fault(err)
    if R.lastError then return end
    R.lastError = tostring(err)
    print("|cffffd100" .. ns.TITLE .. ":|r couldn't restyle the Personal Resource Display. Please report this: " .. R.lastError)
end

-- fn as a post-hook for Blizzard's display, with anything going wrong
-- reported once and never handed back: Blizzard calls these in the middle of
-- its own work (UpdatePowerBar sets the bar's colour before it notes your
-- power type and sets up the rest), which must always carry on.
local function Safely(fn)
    return function(...)
        local ok, err = pcall(fn, ...)
        if not ok then Fault(err) end
    end
end

local function Solid(texture, colour, alpha)
    texture:SetColorTexture(colour[1], colour[2], colour[3], alpha or 1)
end

local function Inset(region, anchor, inset)
    region:ClearAllPoints()
    region:SetPoint("TOPLEFT", anchor, "TOPLEFT", inset, -inset)
    region:SetPoint("BOTTOMRIGHT", anchor, "BOTTOMRIGHT", -inset, inset)
end

-- The colour you picked for the bar, or nil on Blizzard's (state.blizzard,
-- the one Blizzard gave it).
local function Own(state)
    local key = ns.Get(state.setting)
    if key ~= "default" then return Style:BarColour(key) end
end

-- One of Blizzard's own parts by its key, if it's there.
local function Part(frame, key)
    local part = frame and frame[key]
    if type(part) == "table" then return part end
end

-- Blizzard's own textures beside a bar's fill, which take its texture too:
-- heals on the way on the health bar, and what a cast will cost at the end
-- of the power bar. Blizzard only colours, places and sizes them, and never
-- sets their texture or alpha again. Its shield stripes and glows stay as
-- they are: the stripes are what mark a shield.
local HEAL_PIECES = { "myHealPrediction", "otherHealPrediction" }
local COST_PIECES = { "ManaCostPredictionBar" }

local function Pieces(bar, keys)
    local list = {}
    for _, key in ipairs(keys or {}) do
        local piece = Part(bar, key)
        if piece and piece:GetObjectType() == "Texture" then list[#list + 1] = piece end
    end
    return list
end

-- The flash of power just spent, over the end of the power bar: Blizzard
-- tints it like the bar each time it sets the bar up, so it's tinted again
-- after that, in the bar's colour (Blizzard's own, unless you picked one).
local function Spent(bar)
    local flash = Part(Part(bar, "FeedbackFrame"), "BarTexture")
    if flash and flash:GetObjectType() == "Texture" then return flash end
end

local function Flash(state, colour, outline)
    if state.flash then state.flash:SetVertexColor(colour[1], colour[2], colour[3], outline and .45 or 1) end
end

-- What a cast will cost, at the end of the power bar.
local function CostPiece(bar)
    local cost = Part(bar, COST_PIECES[1])
    if cost and cost:GetObjectType() == "Texture" then return cost end
end

-- Blizzard draws what a cast will cost lighter than its bar: on this display
-- its mana bar is 0.1, 0.25, 1 and the cost 0, 0.447, 1
-- (Blizzard_PersonalResourceDisplay .lua:97 and .xml:96, build 70425), as
-- light to the eye as the bar taken 22.5% of the way to white. A colour of
-- yours is taken the same way.
local COST_LIGHTER = .225

-- How light a colour looks to the eye (relative luminance: 0 black, 1 white).
local function Linear(c)
    if c <= .04045 then return c / 12.92 end
    return ((c + .055) / 1.055) ^ 2.4
end

local function Luminance(r, g, b)
    return .2126 * Linear(r) + .7152 * Linear(g) + .0722 * Linear(b)
end

-- How far the lighter shade must stand out from the bar (contrast ratio, the
-- lighter's luminance + .05 over the bar's + .05). Blizzard's own cost blue
-- stands out 1.51 from its bar; the step does 1.22 to 1.67 on the palette and
-- 1.13 (hunter green) or more on the class colours, but 1.02 on the rogue's
-- pale yellow and nothing at all on a priest's white, which has no lighter
-- shade. Below 1.1 (any grey lighter than .829, say) the cost goes the same
-- step darker instead, 22.5% of the way to black: 1.7 on those two, and 1.58
-- or more on any colour the lighter shade fails.
local COST_STANDOUT = 1.1

-- What a cast will cost on your colour: the lighter shade, or the darker one
-- when the lighter wouldn't stand out from the bar.
local function CostShade(colour)
    local t, r, g, b = COST_LIGHTER, colour[1], colour[2], colour[3]
    local lr, lg, lb = r + (1 - r) * t, g + (1 - g) * t, b + (1 - b) * t
    if (Luminance(lr, lg, lb) + .05) / (Luminance(r, g, b) + .05) >= COST_STANDOUT then return lr, lg, lb end
    return r * (1 - t), g * (1 - t), b * (1 - t)
end

-- Blizzard's own colour for what a cast will cost, picked as Blizzard picks
-- it for your power (UpdatePowerBar in Blizzard_PersonalResourceDisplay.lua):
-- the power's own, or mana's when it has none (or no name, as Blizzard then
-- looks nothing up).
local function BlizzardCost()
    local kind, token, altR = UnitPowerType("player")
    local list, info = type(PowerBarColor) == "table" and PowerBarColor or {}, nil
    if not (issecretvalue and (issecretvalue(kind) or issecretvalue(token) or issecretvalue(altR))) and token then
        info = list[token]
        if not info and not altR and kind then info = list[kind] end
    end
    local colour = type(info) == "table" and info.predictionColor or POWERBAR_PREDICTION_COLOR_MANA
    if type(colour) == "table" and colour.GetRGBA then return colour end
end

-- What a cast will cost in a lighter shade of the colour you picked for the
-- bar (a darker one on white or a colour nearly as light: CostShade), set
-- again after each time Blizzard sets its own (as your power type changes).
-- The tint itself is solid: for Outline the piece's own alpha makes it
-- see-through like the fill. On Blizzard's colours it keeps Blizzard's, put
-- back only if yours was on it.
local function CostTint(state, own)
    local cost = state.cost
    if not cost then return end
    if own then
        local r, g, b = CostShade(own)
        cost:SetVertexColor(r, g, b, 1)
        state.tinted = true
    elseif state.tinted then
        state.tinted = nil
        local colour = BlizzardCost()
        if colour then cost:SetVertexColor(colour:GetRGBA()) end
    end
end

-- The bar's fill in the texture chosen on the Look page, and Blizzard's
-- pieces beside it, set only when it changes: Look also runs each time
-- Blizzard recolours the bar.
local function Fill(bar, state)
    local texture = Style:BarTexture()
    if state.texture == texture then return end
    state.texture = texture
    bar:SetStatusBarTexture(texture)
    for _, piece in ipairs(state.pieces) do piece:SetTexture(texture) end
    if state.flash then state.flash:SetTexture(texture) end
end

-- The track's darkness chosen on the Look page, set only when it changes.
local function Track(state)
    local dark = Style:Darkness()
    if state.dark == dark then return end
    state.dark = dark
    for _, track in ipairs(state.tracks) do track:SetColorTexture(Style:TrackColour()) end
end

local function Look(bar, state)
    local design, own = ns.Get("barStyle"), Own(state)
    local colour, outline = own or state.blizzard, design == "outline"
    Fill(bar, state)
    Track(state)
    Style:ShowSheen(state.sheen, design == "glass")
    painting[bar] = true
    bar:SetStatusBarColor(colour[1], colour[2], colour[3], outline and .45 or 1)
    painting[bar] = nil
    -- A 1px edge round the bar: black, or the bar's colour for Outline; with
    -- Thick edges, a second pixel inside it.
    local edge = outline and colour or { 0, 0, 0 }
    Solid(state.edge, edge)
    Style:ShowInnerEdge(state.inner, edge)
    -- Blizzard's pieces beside the fill as see-through as it for Outline
    -- (set only when that changes), the spent flash in the bar's colour, and
    -- what a cast will cost in a lighter shade of yours (darker on white).
    local alpha = outline and .45 or 1
    if state.alpha ~= alpha then
        state.alpha = alpha
        for _, piece in ipairs(state.pieces) do piece:SetAlpha(alpha) end
    end
    Flash(state, colour, outline)
    CostTint(state, own)
end

-- Look, with anything going wrong reported once, and the bar never left
-- marked as one the addon is colouring should it stop half-way.
local function TryLook(bar, state)
    local ok, err = pcall(Look, bar, state)
    painting[bar] = nil
    if not ok then Fault(err) end
end

-- pieces: the keys of Blizzard's textures beside the bar's fill; main: the
-- main power bar, with the spent flash and what a cast will cost.
local function Restyle(bar, setting, pieces, main)
    if not bar or bars[bar] then return end
    -- Blizzard's pieces start at full alpha, so nothing is set on them until Outline.
    local state = { setting = setting, tracks = {}, pieces = Pieces(bar, pieces), alpha = 1,
        flash = main and Spent(bar) or nil, cost = main and CostPiece(bar) or nil }
    Fill(bar, state)
    -- Blizzard's art behind the bar becomes its track (Track colours it).
    for _, region in ipairs({ bar:GetRegions() }) do
        if region:GetObjectType() == "Texture" and region:GetAtlas() == BG_ATLAS then
            state.tracks[#state.tracks + 1] = region
            Inset(region, bar, 0)
        end
    end
    state.edge = bar:CreateTexture(nil, "BACKGROUND", nil, -8)
    Inset(state.edge, bar, -1)
    state.inner = Style:InnerEdge(bar, bar)
    -- Glass: a soft shine over the top half.
    local shine = bar:CreateTexture(nil, "OVERLAY", nil, -8)
    shine:SetPoint("TOPLEFT", bar, "TOPLEFT", 0, 0)
    shine:SetPoint("BOTTOMRIGHT", bar, "RIGHT", 0, 0)
    shine:SetColorTexture(1, 1, 1, .16)
    state.sheen = Style:Sheen(bar, shine)
    local r, g, b = bar:GetStatusBarColor()
    state.blizzard = { r or 1, g or 1, b or 1 }
    bars[bar] = state
    -- Blizzard sets the colour as your power changes; keep its colour for
    -- Default, and your own or the design's on top. Run through TryLook:
    -- UpdatePowerBar sets it first, and the rest of its work must still run.
    hooksecurefunc(bar, "SetStatusBarColor", function(self, red, green, blue)
        if painting[self] then return end
        state.blizzard = { red, green, blue }
        TryLook(self, state)
    end)
    Look(bar, state)
end

-- Whether the extra mana bar is hidden right now: a layout leaves no room for it.
local extraHidden = false

function R:ExtraHidden()
    return extraHidden
end

-- The display's bars changed which are showing (a form change, say): a
-- layout closes up or makes room.
local function Restack()
    if ns.Layout then ns.Layout:Stack() end
end

-- The extra mana bar: hidden while your main bar is mana too, and half as
-- tall in forms, so your mana is still there but out of the way. A power
-- type the game won't say keeps it as it was.
local function ExtraMana(frame)
    local extra = frame and frame.AlternatePowerBar
    if not extra or extra.powerName ~= "MANA" then return end
    local kind = UnitPowerType("player")
    if issecretvalue and issecretvalue(kind) then return end
    local tidy, caster = ns.Get("prdHideRepeat"), kind == MANA
    extra:SetAlpha(tidy and caster and 0 or 1)
    local full = frame.PowerBar and frame.PowerBar:GetHeight()
    if type(full) == "number" and full > 0 then
        extra:SetHeight(tidy and not caster and math.max(2, math.floor(full / 2 + .5)) or full)
    end
    local hidden = tidy and caster or false
    if hidden ~= extraHidden then
        extraHidden = hidden
        Restack()
    end
end

-- Combo points ---------------------------------------------------------------------
-- Blizzard left combo points out of Forever's display (until 70291, below), so
-- the addon draws its own under the display's lowest bar: five segments as wide as the display, in
-- the Tracked Bars design and texture and a colour of your choice. Flat by
-- default, so they stay sharp at any size, and they stretch or shrink with the
-- display.
-- Rogues, and druids in cat form. The count can be secret in combat, so each
-- segment is a bar from i - 1 to i handed the count as it is: the game fills
-- it, and the addon never reads the number.
local COMBO = Enum and Enum.PowerType and Enum.PowerType.ComboPoints or 4
local ENERGY = Enum and Enum.PowerType and Enum.PowerType.Energy or 3
local COMBO_MAX = 5
local COMBO_GAP = 3 -- between segments, clear of each one's 1px edge
local COMBO_RED = { .87, .2, .13 } -- the colour they start in
local combo -- the row, made once the display is there
local comboShown = false

local function ComboColour()
    local key = ns.Get("prdComboColour")
    if key ~= "default" then return Style:BarColour(key) end
    return COMBO_RED
end

-- One of the addon's own bars on the display (a combo segment, the energy
-- bar): its track, edges and shine, coloured by OwnLook.
local function MakeOwn(parent, texture)
    local bar = CreateFrame("StatusBar", nil, parent)
    bar:SetStatusBarTexture(texture)
    -- Its track, coloured by OwnLook with the darkness chosen.
    bar.background = bar:CreateTexture(nil, "BACKGROUND")
    bar.background:SetAllPoints()
    bar.edge = bar:CreateTexture(nil, "BACKGROUND", nil, -8)
    Inset(bar.edge, bar, -1)
    bar.inner = Style:InnerEdge(bar, bar)
    local shine = bar:CreateTexture(nil, "OVERLAY", nil, -8)
    shine:SetPoint("TOPLEFT", bar, "TOPLEFT", 0, 0)
    shine:SetPoint("BOTTOMRIGHT", bar, "RIGHT", 0, 0)
    shine:SetColorTexture(1, 1, 1, .16)
    bar.sheen = Style:Sheen(bar, shine)
    return bar
end

-- The design chosen, in this colour; the texture only when it changes
-- (retexture), as for the display's own bars.
local function OwnLook(bar, colour, texture, retexture)
    local design = ns.Get("barStyle")
    local outline = design == "outline"
    local edge = outline and colour or { 0, 0, 0 }
    if retexture then bar:SetStatusBarTexture(texture) end
    bar:SetStatusBarColor(colour[1], colour[2], colour[3], outline and .45 or 1)
    bar.background:SetColorTexture(Style:TrackColour())
    Solid(bar.edge, edge)
    Style:ShowInnerEdge(bar.inner, edge)
    Style:ShowSheen(bar.sheen, design == "glass")
end

local function ComboLook()
    if not combo then return end
    local colour, texture = ComboColour(), Style:BarTexture()
    local retexture = combo.texture ~= texture
    combo.texture = texture
    for _, bar in ipairs(combo.segments) do OwnLook(bar, colour, texture, retexture) end
end

-- The segments share the row's width, whatever it is now.
local function ComboLayout()
    local width = combo:GetWidth()
    if not (type(width) == "number" and width > 0) then return end
    local each = (width - (COMBO_MAX - 1) * COMBO_GAP) / COMBO_MAX
    for i, bar in ipairs(combo.segments) do
        local x = (i - 1) * (each + COMBO_GAP)
        bar:ClearAllPoints()
        bar:SetPoint("TOPLEFT", combo, "TOPLEFT", x, 0)
        bar:SetPoint("BOTTOMLEFT", combo, "BOTTOMLEFT", x, 0)
        bar:SetWidth(each)
    end
end

local function MakeCombo(frame)
    combo = CreateFrame("Frame", nil, frame)
    combo:SetSize(1, 1)
    combo:Hide()
    combo.segments = {}
    combo.texture = Style:BarTexture()
    for i = 1, COMBO_MAX do
        local bar = MakeOwn(combo, combo.texture)
        bar:SetMinMaxValues(i - 1, i)
        bar:SetValue(0)
        combo.segments[i] = bar
    end
    combo:SetScript("OnSizeChanged", ComboLayout)
    ComboLook()
end

-- Rogues always, druids while their power is energy (cat form). A power type
-- the game won't say keeps things as they were.
local function ComboWanted()
    if not ns.Get("prdCombo") then return false end
    local _, class = UnitClass("player")
    if class == "ROGUE" then return true end
    if class ~= "DRUID" then return false end
    local power = UnitPowerType("player")
    if issecretvalue and issecretvalue(power) then return comboShown end
    return power == ENERGY
end

-- A row under the lowest bar that shows, Blizzard's own padding apart, as
-- tall as the power bar (or half, as the extra mana bar is in forms).
local function Underneath(row, frame, half)
    local below = frame.PowerBar
    local extra = frame.AlternatePowerBar
    if extra and extra:IsShown() and not extraHidden then below = extra end
    if not (below and below:IsShown()) then below = frame.HealthBarsContainer or frame end
    local padding = type(frame.GetBarPadding) == "function" and frame:GetBarPadding() or 4
    row:ClearAllPoints()
    row:SetPoint("TOPLEFT", below, "BOTTOMLEFT", 0, -padding)
    row:SetPoint("TOPRIGHT", below, "BOTTOMRIGHT", 0, -padding)
    local height = frame.PowerBar and frame.PowerBar:GetHeight()
    height = type(height) == "number" and height > 0 and height or 8
    row:SetHeight(half and math.max(2, math.floor(height / 2 + .5)) or height)
end

-- Your points now, handed straight to the segments.
local function ComboPoints()
    if not (combo and combo:IsShown()) then return end
    local points = UnitPower("player", COMBO)
    for _, bar in ipairs(combo.segments) do bar:SetValue(points) end
end

-- Since Forever 1.60.1 (70291) the display draws the game's own combo points
-- too, for rogues and druids, under the bars (its ClassFrameContainer). While
-- ours show, the game's are made see-through, so there's one set: only their
-- alpha, as with the extra mana bar above (nothing shown, hidden, moved or
-- set on them), and back to full when ours go. Edit Mode's own Hide Class
-- Resources still works as before.
local classMuted = false
local function MuteClassFrame(frame, mute)
    local container = frame and frame.ClassFrameContainer
    if not container or mute == classMuted then return end
    classMuted = mute
    container:SetAlpha(mute and 0 or 1)
end

-- What the row listens for (made for rogues and druids): nothing while combo
-- points are off; while they're on, what can show or hide them (your power
-- type, form, a loading screen); and while they show, your points and target
-- too. Changed only when that changes.
local comboEvents -- the listener, once made
local comboHearing -- "off", "on" or "shown": what it listens for now
local COMBO_UNIT_EVENTS = { "UNIT_MAXPOWER", "UNIT_DISPLAYPOWER" }
local COMBO_EVENTS = { "UPDATE_SHAPESHIFT_FORM", "PLAYER_ENTERING_WORLD" }

local function ComboListen()
    if not comboEvents then return end
    local want = not ns.Get("prdCombo") and "off" or comboShown and "shown" or "on"
    if want == comboHearing then return end
    comboHearing = want
    comboEvents:UnregisterAllEvents()
    if want == "off" then return end
    for _, event in ipairs(COMBO_UNIT_EVENTS) do comboEvents:RegisterUnitEvent(event, "player") end
    for _, event in ipairs(COMBO_EVENTS) do comboEvents:RegisterEvent(event) end
    if want == "shown" then
        comboEvents:RegisterUnitEvent("UNIT_POWER_FREQUENT", "player")
        comboEvents:RegisterEvent("PLAYER_TARGET_CHANGED")
    end
end

-- Shows or hides the row and puts it in place; a layout makes room for it.
local function ComboUpdate()
    local frame = _G.PersonalResourceDisplayFrame
    if not (frame and combo) then return end
    local want = ComboWanted()
    if want then Underneath(combo, frame) end
    MuteClassFrame(frame, want)
    combo:SetShown(want)
    ComboPoints()
    local changed = want ~= comboShown
    comboShown = want
    ComboListen()
    if changed then Restack() end
end

-- Energy out of cat form ---------------------------------------------------------
-- For druids who want their energy in sight in their other forms: one bar in
-- the combo points' spot (free outside cat form), half as tall as the power
-- bar like the extra mana bar in forms, in the Tracked Bars design
-- and texture and the game's energy colour. In cat form energy is the
-- display's main bar, so this one hides. The game fills it: your energy goes
-- to it as it is, never read.
local ENERGY_YELLOW = { 1, 1, 0 }
local energy -- the bar, made for druids once the display is there
local energyShown = false
local energyEvents -- its listener
local energyHearing -- "off", "on" or "shown", as for combo points

local function EnergyLook()
    if not energy then return end
    local info = type(PowerBarColor) == "table" and PowerBarColor.ENERGY
    local colour = type(info) == "table" and type(info.r) == "number" and { info.r, info.g, info.b } or ENERGY_YELLOW
    local texture = Style:BarTexture()
    local retexture = energy.texture ~= texture
    energy.texture = texture
    OwnLook(energy, colour, texture, retexture)
end

local function MakeEnergy(frame)
    energy = MakeOwn(frame, Style:BarTexture())
    energy.texture = Style:BarTexture()
    energy:SetMinMaxValues(0, 100)
    energy:SetValue(0)
    energy:Hide()
    EnergyLook()
end

-- While it's ticked and your power isn't energy. A power type the game won't
-- say keeps things as they were.
local function EnergyWanted()
    if not ns.Get("prdEnergy") then return false end
    local power = UnitPowerType("player")
    if issecretvalue and issecretvalue(power) then return energyShown end
    return power ~= ENERGY
end

local function EnergyFill()
    if not (energy and energy:IsShown()) then return end
    energy:SetMinMaxValues(0, UnitPowerMax("player", ENERGY))
    energy:SetValue(UnitPower("player", ENERGY))
end

-- Nothing while it's off; while it's on, your form and power type; while it
-- shows, your energy too.
local function EnergyListen()
    if not energyEvents then return end
    local want = not ns.Get("prdEnergy") and "off" or energyShown and "shown" or "on"
    if want == energyHearing then return end
    energyHearing = want
    energyEvents:UnregisterAllEvents()
    if want == "off" then return end
    energyEvents:RegisterUnitEvent("UNIT_DISPLAYPOWER", "player")
    for _, event in ipairs(COMBO_EVENTS) do energyEvents:RegisterEvent(event) end
    if want == "shown" then
        energyEvents:RegisterUnitEvent("UNIT_POWER_FREQUENT", "player")
        energyEvents:RegisterUnitEvent("UNIT_MAXPOWER", "player")
    end
end

local function EnergyUpdate()
    local frame = _G.PersonalResourceDisplayFrame
    if not (frame and energy) then return end
    local want = EnergyWanted()
    if want then Underneath(energy, frame, true) end
    energy:SetShown(want)
    EnergyFill()
    local changed = want ~= energyShown
    energyShown = want
    EnergyListen()
    if changed then Restack() end
end

-- The row under the display while it shows (combo points or energy, never
-- both), so a layout counts it as part of the display.
function R:ComboRow()
    return comboShown and combo or energyShown and energy or nil
end

-- Text on the display's bars -------------------------------------------------------
-- Your health and power as text on the display's health bar and main power
-- bar, as set up from the Look page: in the middle, or a pair at the left
-- and right ends, each your value now, it and the most it can be, or a
-- percent. Off by default. The text is the addon's own, on frames of its own
-- over Blizzard's bars that take no mouse, so it hides and fades with them.
-- Forever keeps your health and power secret, in and out of combat, so the
-- game's numbers go straight into its own text calls: never read, compared,
-- added up or joined. While it shows on a bar, Blizzard's own text there
-- (Edit Mode's Show Bar Text) goes see-through: only its alpha, and back to
-- full when ours goes.
local SPOTS = { "centre", "left", "right" }
local TEXT_KINDS = { "health", "power" }
local TEXT_KEYS = {
    health = { at = "prdHealthAt", centre = "prdHealthCentre", left = "prdHealthLeft", right = "prdHealthRight" },
    power = { at = "prdPowerAt", centre = "prdPowerCentre", left = "prdPowerLeft", right = "prdPowerRight" },
}
local TEXT_EVENTS = {
    health = { "UNIT_HEALTH", "UNIT_MAXHEALTH" },
    power = { "UNIT_POWER_FREQUENT", "UNIT_MAXPOWER", "UNIT_DISPLAYPOWER" },
}
-- And after each loading screen, as Blizzard's own display does: your
-- numbers can settle then without an event of their own.
local TEXT_REFRESH = "PLAYER_ENTERING_WORLD"
local BLIZZARD_TEXT = { "TextString", "LeftText", "RightText" }
local TEXT_INSET, TEXT_GAP = 4, 2 -- from the bar's ends, and either side of its middle for a pair
local holders = {} -- each bar's text, by kind, made the first time it's ticked
R.textHolders = holders -- for the tests
local textOn = false

-- Plain numbers for the Set up panel's preview (Window.lua).
local SAMPLES = {
    health = { Current = function() return 4321 end, Max = function() return 5120 end, Percent = function() return 84.4 end },
    power = { Current = function() return 1876 end, Max = function() return 2400 end, Percent = function() return 78.2 end },
}

-- Your power type, plain, or nil for the game's own choice of your current one.
local function PowerType()
    local kind = UnitPowerType("player")
    if issecretvalue and issecretvalue(kind) then return nil end
    return kind
end

-- The game's numbers for your bars, handed on as they come. A percent goes
-- through the game's own 0 to 100 curve; on a build without the curve or the
-- call (checked as the text is made), percent spots stay blank.
local function GameSource(kind)
    local curve = CurveConstants and CurveConstants.ScaleTo100 or nil
    if kind == "health" then
        return {
            Current = function() return UnitHealth("player") end,
            Max = function() return UnitHealthMax("player") end,
            Percent = curve and UnitHealthPercent and function() return UnitHealthPercent("player", false, curve) end or nil,
        }
    end
    return {
        Current = function() return UnitPower("player", PowerType()) end,
        Max = function() return UnitPowerMax("player", PowerType()) end,
        Percent = curve and UnitPowerPercent and function() return UnitPowerPercent("player", PowerType(), false, curve) end or nil,
    }
end

-- A number as the game writes it: 4,321, or 4.3K. Should a build lack the
-- call, the number goes on as it is.
local function Number(value)
    if AbbreviateNumbers and ns.Get("prdTextNumbers") == "short" then return AbbreviateNumbers(value) end
    if BreakUpLargeNumbers then return BreakUpLargeNumbers(value) end
    return value
end

-- One spot's text: the value now, it and the most it can be, a percent, or nothing.
local function Put(text, format, source)
    if format == "value" then
        text:SetFormattedText("%s", Number(source.Current()))
    elseif format == "both" then
        text:SetFormattedText("%s / %s", Number(source.Current()), Number(source.Max()))
    elseif format == "percent" and source.Percent then
        text:SetFormattedText("%.0f%%", source.Percent())
    else
        text:SetText("")
    end
end

-- The text's font: the Look page's at the size chosen, or one of the game's own.
local function TextFont()
    local size, key = ns.Get("prdTextSize"), ns.Get("prdTextFont")
    if key == "look" then return Style:Font(size) end
    return Style:FontIn(key, size)
end

-- A bar's three spots for text, on frame (the addon's own): the middle, and
-- a left and right pair, each half the bar, so a long pair is cut short
-- rather than run into each other. Each has its font before any text.
function R:TextSlots(frame)
    local slots = { font = TextFont() }
    for _, spot in ipairs(SPOTS) do
        local text = frame:CreateFontString(nil, "OVERLAY")
        text:SetFontObject(slots.font)
        text:SetWordWrap(false)
        slots[spot] = text
    end
    slots.centre:SetJustifyH("CENTER")
    slots.centre:SetPoint("LEFT", frame, "LEFT", TEXT_INSET, 0)
    slots.centre:SetPoint("RIGHT", frame, "RIGHT", -TEXT_INSET, 0)
    slots.left:SetJustifyH("LEFT")
    slots.left:SetPoint("LEFT", frame, "LEFT", TEXT_INSET, 0)
    slots.left:SetPoint("RIGHT", frame, "CENTER", -TEXT_GAP, 0)
    slots.right:SetJustifyH("RIGHT")
    slots.right:SetPoint("LEFT", frame, "CENTER", TEXT_GAP, 0)
    slots.right:SetPoint("RIGHT", frame, "RIGHT", -TEXT_INSET, 0)
    slots.formats = { centre = "none", left = "none", right = "none" }
    return slots
end

-- The font and size chosen, set only when they change.
local function Dress(slots)
    local font = TextFont()
    if slots.font == font then return end
    slots.font = font
    for _, spot in ipairs(SPOTS) do slots[spot]:SetFontObject(font) end
end

-- What each spot shows on kind's bar as chosen ("none" where it isn't
-- used), and a spot no longer used emptied.
local function Arrange(slots, kind)
    local keys, formats = TEXT_KEYS[kind], {}
    local at = ns.Get(keys.at)
    formats.centre = at == "centre" and ns.Get(keys.centre) or "none"
    formats.left = at == "sides" and ns.Get(keys.left) or "none"
    formats.right = at == "sides" and ns.Get(keys.right) or "none"
    for _, spot in ipairs(SPOTS) do
        if formats[spot] == "none" and slots.formats[spot] ~= "none" then slots[spot]:SetText("") end
    end
    slots.formats = formats
    slots.any = formats.centre ~= "none" or formats.left ~= "none" or formats.right ~= "none"
end

-- The spots in use, from source.
local function Write(slots, source)
    local formats = slots.formats
    for _, spot in ipairs(SPOTS) do
        local format = formats[spot]
        if format ~= "none" then Put(slots[spot], format, source) end
    end
end

-- The Set up panel's preview (Window.lua): kind's text from plain numbers,
-- through the same code as your bars, so the two always match.
function R:WriteSample(slots, kind)
    Dress(slots)
    Arrange(slots, kind)
    Write(slots, SAMPLES[kind])
end

-- Blizzard's own text on the bar see-through while ours shows there, and
-- back to full after: only its alpha, set only when that changes.
local function MuteBlizzard(holder, mute)
    if holder.muted == mute then return end
    holder.muted = mute
    for _, key in ipairs(BLIZZARD_TEXT) do
        local text = Part(holder.bar, key)
        if text then text:SetAlpha(mute and 0 or 1) end
    end
end

-- Something went wrong with the text: you're told once.
local function TextFault(err)
    if R.textError then return end
    R.textError = tostring(err)
    print("|cffffd100" .. ns.TITLE .. ":|r couldn't show text on the Personal Resource Display. Please report this: " .. R.textError)
end

-- Should the game refuse a number (a build that keeps one some other way),
-- the bar's text goes blank, stops listening and is put away, and
-- Blizzard's own text there comes back.
local function Broken(holder, err)
    holder.broken = true
    holder:UnregisterAllEvents()
    for _, spot in ipairs(SPOTS) do holder.slots[spot]:SetText("") end
    MuteBlizzard(holder, false)
    holder:Hide()
    TextFault(err)
end

-- Your numbers now, while the bar is in sight; one coming back into sight
-- is brought up to date as it shows.
local function Update(holder)
    if not holder:IsVisible() then return end
    local ok, err = pcall(Write, holder.slots, holder.source)
    if not ok then Broken(holder, err) end
end

-- The power bar's events: a change to a power other than the one on the bar
-- (a druid's mana ticking in cat form, say) is left alone, as Blizzard's own
-- display does. Only when both names are plain words that differ: anything
-- else, or no name, still writes.
local POWER_CHANGES = { UNIT_POWER_FREQUENT = true, UNIT_MAXPOWER = true }

local function Plain(word)
    return type(word) == "string" and not (issecretvalue and issecretvalue(word))
end

local function PowerEvent(holder, event, _, token)
    if POWER_CHANGES[event] and Plain(token) then
        local _, current = UnitPowerType("player")
        if Plain(current) and current ~= token then return end
    end
    Update(holder)
end

-- The bars the text goes on: the display's health bar and main power bar.
local function TextBar(frame, kind)
    if kind == "health" then return Part(Part(frame, "HealthBarsContainer"), "healthBar") end
    return Part(frame, "PowerBar")
end

-- level, or part's frame level if that's higher.
local function Above(level, part)
    local over = part and part:GetFrameLevel()
    if type(over) == "number" and over > level then return over end
    return level
end

-- Above everything Blizzard draws on the bar: the health bar's lost max
-- health (its own bar at level 100), and the power bar's full-power pulse
-- (a frame a level above the bar, with its spike and glow frames a level
-- above that), yet under Edit Mode's highlight.
local function TextLevel(frame, bar, kind)
    local level = bar:GetFrameLevel()
    if kind == "health" then return Above(level, Part(Part(frame, "HealthBarsContainer"), "TempMaxHealthLoss")) + 1 end
    local pulse = Part(bar, "FullPowerFrame")
    return Above(Above(Above(level + 1, pulse), Part(pulse, "SpikeFrame")), Part(pulse, "PulseFrame")) + 1
end

local function MakeHolder(frame, kind)
    local bar = TextBar(frame, kind)
    if not bar then return nil end
    local holder = CreateFrame("Frame", nil, bar)
    holder:SetAllPoints(bar)
    holder:SetFrameLevel(TextLevel(frame, bar, kind))
    holder:EnableMouse(false)
    holder:Hide()
    holder.bar, holder.kind, holder.source, holder.muted = bar, kind, GameSource(kind), false
    holder.slots = R:TextSlots(holder)
    holder:SetScript("OnEvent", kind == "power" and PowerEvent or Update)
    holder:SetScript("OnShow", Update)
    return holder
end

-- Shows, updates or puts away the text as chosen. Nothing is made until
-- it's first ticked, and while it's off nothing listens.
local function ApplyText()
    local frame = _G.PersonalResourceDisplayFrame
    local on = ns.Get("prdText") == true
    if not (frame and (on or textOn)) then return end
    textOn = on
    for _, kind in ipairs(TEXT_KINDS) do
        if on and not holders[kind] then holders[kind] = MakeHolder(frame, kind) end
        local holder = holders[kind]
        if holder then
            local slots = holder.slots
            Dress(slots)
            Arrange(slots, kind)
            local show = on and slots.any and not holder.broken
            holder:UnregisterAllEvents()
            if show then
                for _, event in ipairs(TEXT_EVENTS[kind]) do holder:RegisterUnitEvent(event, "player") end
                holder:RegisterEvent(TEXT_REFRESH)
            end
            MuteBlizzard(holder, show)
            local was = holder:IsShown()
            holder:SetShown(show)
            if show and was then Update(holder) end
        end
    end
end

-- The same, with anything going wrong reported once, as the text's own faults are.
local function TryText()
    local ok, err = pcall(ApplyText)
    if not ok then TextFault(err) end
end

-- The width the display was given to match your rows, while it's matching.
local matched

-- As wide as your widest row while a layout holds your bars (and the choice
-- is on): the same widths Blizzard's own Bar Width setting changes, set
-- after Blizzard sets its own. Otherwise its width is Blizzard's again.
-- Never in combat; it waits for the fight to end.
function R:Match()
    local frame = _G.PersonalResourceDisplayFrame
    if not frame then return end
    if InCombatLockdown() then
        self.pendingMatch = true
        return
    end
    self.pendingMatch = nil
    local want = ns.Layout and ns.Layout:MatchWidth()
    local width
    if want then
        local own = frame:GetEffectiveScale()
        if not (type(own) == "number" and own > 0) then return end
        width = want * UIParent:GetEffectiveScale() / own
    elseif matched then
        local base, percent = frame.defaultBarWidth, frame.barWidthPercent
        if type(base) == "number" and type(percent) == "number" then width = base * percent / 100 end
    end
    if not width then return end
    matched = want and width or nil
    for _, part in ipairs({ frame, frame.HealthBarsContainer, frame.PowerBar, frame.AlternatePowerBar, frame.ClassFrameContainer }) do
        if part then part:SetWidth(width) end
    end
end

-- Blizzard has just set its own width (Edit Mode): a layout puts the match
-- back, and moves anything beside the display.
local function Rematch()
    matched = nil
    if ns.Layout and ns.Layout:Active() then
        ns.Layout:Stack()
    elseif ns.CastBar then
        ns.CastBar:Place()
    end
end

local function Hook()
    local frame = _G.PersonalResourceDisplayFrame
    if not frame then return false end
    if ns.loaded.prdSkin then
        local health = frame.HealthBarsContainer and frame.HealthBarsContainer.healthBar or frame.healthbar
        Restyle(health, "prdHealth", HEAL_PIECES)
        Restyle(frame.PowerBar, "prdPower", COST_PIECES, true)
        Restyle(frame.AlternatePowerBar, "prdPower")
    end
    -- Combo points, for the classes that have them. The listener hears
    -- nothing until they're ticked (ComboListen, from ComboUpdate). Any
    -- power's change counts, not only combo points', as for the game's own.
    local _, class = UnitClass("player")
    if class == "ROGUE" or class == "DRUID" then
        MakeCombo(frame)
        comboEvents = CreateFrame("Frame")
        comboEvents:SetScript("OnEvent", function(_, event)
            if event == "UNIT_POWER_FREQUENT" or event == "PLAYER_TARGET_CHANGED" then ComboPoints() else ComboUpdate() end
        end)
    end
    -- Energy in other forms, for druids: silent too until ticked.
    if class == "DRUID" then
        MakeEnergy(frame)
        energyEvents = CreateFrame("Frame")
        energyEvents:SetScript("OnEvent", function(_, event)
            if event == "UNIT_POWER_FREQUENT" or event == "UNIT_MAXPOWER" then EnergyFill() else EnergyUpdate() end
        end)
    end
    -- Your power changing, and Edit Mode setting the bars' height, padding
    -- and which show.
    local function Changed(self)
        ExtraMana(self)
        ComboUpdate()
        EnergyUpdate()
        -- Blizzard has just tinted the spent flash again, setting the power
        -- bar up, and what a cast will cost if your power type changed.
        local power = Part(self, "PowerBar")
        local state = power and bars[power]
        if state then
            local own = Own(state)
            Flash(state, own or state.blizzard, ns.Get("barStyle") == "outline")
            CostTint(state, own)
        end
    end
    -- Hooked through Safely: anything going wrong is reported once, never
    -- handed back to Blizzard's call (Edit Mode's setters carry on after).
    local hooked = Safely(Changed)
    for _, method in ipairs({ "UpdatePowerBar", "UpdateAlternatePowerBar", "SetPowerBarHeight", "SetBarPadding",
        "SetHidePower", "SetHideAltPower" }) do
        if type(frame[method]) == "function" then hooksecurefunc(frame, method, hooked) end
    end
    if type(frame.UpdateBarWidth) == "function" then hooksecurefunc(frame, "UpdateBarWidth", Safely(Rematch)) end
    Changed(frame)
    TryText()
    return true
end

-- Whether the display is there to restyle: Blizzard loads it once it's on.
function R:Shown()
    return _G.PersonalResourceDisplayFrame ~= nil
end

-- Redraws the bars after a choice changes.
function R:Apply()
    for bar, state in pairs(bars) do TryLook(bar, state) end
    ExtraMana(_G.PersonalResourceDisplayFrame)
    ComboLook()
    ComboUpdate()
    EnergyLook()
    EnergyUpdate()
    TryText()
end

function R:Start()
    if self.started then return end
    self.started = true
    local ok, found = pcall(Hook)
    if ok and found then return end
    if not ok then
        Fault(found)
        return
    end
    -- Blizzard loads the display when it's switched on; wait for it.
    local watcher = CreateFrame("Frame")
    watcher:RegisterEvent("ADDON_LOADED")
    watcher:SetScript("OnEvent", function(frame, _, name)
        if name ~= "Blizzard_PersonalResourceDisplay" then return end
        frame:UnregisterAllEvents()
        local fine, err = pcall(Hook)
        if not fine then Fault(err) end
    end)
end
