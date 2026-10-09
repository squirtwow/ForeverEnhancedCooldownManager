-- Blizzard's Personal Resource Display (Options > Combat), restyled like the
-- Tracked Bars: its health and power bars in the same design, each in
-- Blizzard's colour or one of yours. Some specs get a second mana bar under
-- the main one: it's hidden while the main bar is mana too, so it never just
-- repeats it, and half as tall in bear, cat and other forms. While a layout
-- stacks your bars around it, it can be as wide as your widest row. Combo
-- points, which Forever's display leaves out, can go under it.
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

local function Solid(texture, colour, alpha)
    texture:SetColorTexture(colour[1], colour[2], colour[3], alpha or 1)
end

local function Inset(region, anchor, inset)
    region:ClearAllPoints()
    region:SetPoint("TOPLEFT", anchor, "TOPLEFT", inset, -inset)
    region:SetPoint("BOTTOMRIGHT", anchor, "BOTTOMRIGHT", -inset, inset)
end

-- Your colour for the bar, or the one Blizzard gave it.
local function Colour(state)
    local key = ns.Get(state.setting)
    if key ~= "default" then return Style:BarColour(key) end
    return state.blizzard
end

-- The bar's fill in the texture chosen on the Look page, set only when it
-- changes: Look also runs each time Blizzard recolours the bar.
local function Fill(bar, state)
    local texture = Style:BarTexture()
    if state.texture == texture then return end
    state.texture = texture
    bar:SetStatusBarTexture(texture)
end

local function Look(bar, state)
    local design, colour = ns.Get("barStyle"), Colour(state)
    local outline = design == "outline"
    Fill(bar, state)
    state.sheen:SetShown(design == "glass")
    painting[bar] = true
    bar:SetStatusBarColor(colour[1], colour[2], colour[3], outline and .45 or 1)
    painting[bar] = nil
    -- A 1px edge round the bar: black, or the bar's colour for Outline.
    Solid(state.edge, outline and colour or { 0, 0, 0 })
end

local function Restyle(bar, setting)
    if not bar or bars[bar] then return end
    local state = { setting = setting }
    Fill(bar, state)
    for _, region in ipairs({ bar:GetRegions() }) do
        if region:GetObjectType() == "Texture" and region:GetAtlas() == BG_ATLAS then
            Solid(region, Style.TRACK, Style.TRACK[4])
            Inset(region, bar, 0)
        end
    end
    state.edge = bar:CreateTexture(nil, "BACKGROUND", nil, -8)
    Inset(state.edge, bar, -1)
    -- Glass: a soft shine over the top half.
    state.sheen = bar:CreateTexture(nil, "OVERLAY", nil, -8)
    state.sheen:SetPoint("TOPLEFT", bar, "TOPLEFT", 0, 0)
    state.sheen:SetPoint("BOTTOMRIGHT", bar, "RIGHT", 0, 0)
    state.sheen:SetColorTexture(1, 1, 1, .16)
    local r, g, b = bar:GetStatusBarColor()
    state.blizzard = { r or 1, g or 1, b or 1 }
    bars[bar] = state
    -- Blizzard sets the colour as your power changes; keep its colour for
    -- Default, and your own or the design's on top.
    hooksecurefunc(bar, "SetStatusBarColor", function(self, red, green, blue)
        if painting[self] then return end
        state.blizzard = { red, green, blue }
        Look(self, state)
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
-- tall in forms, so your mana is still there but out of the way.
local function ExtraMana(frame)
    local extra = frame and frame.AlternatePowerBar
    if not extra or extra.powerName ~= "MANA" then return end
    local tidy, caster = ns.Get("prdHideRepeat"), UnitPowerType("player") == MANA
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

local function ComboLook()
    if not combo then return end
    local design, colour, texture = ns.Get("barStyle"), ComboColour(), Style:BarTexture()
    local outline = design == "outline"
    -- The texture only when it changes, as for the display's own bars.
    local retexture = combo.texture ~= texture
    combo.texture = texture
    for _, bar in ipairs(combo.segments) do
        if retexture then bar:SetStatusBarTexture(texture) end
        bar:SetStatusBarColor(colour[1], colour[2], colour[3], outline and .45 or 1)
        Solid(bar.edge, outline and colour or { 0, 0, 0 })
        bar.sheen:SetShown(design == "glass")
    end
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
        local bar = CreateFrame("StatusBar", nil, combo)
        bar:SetStatusBarTexture(combo.texture)
        bar:SetMinMaxValues(i - 1, i)
        bar:SetValue(0)
        local track = bar:CreateTexture(nil, "BACKGROUND")
        track:SetAllPoints()
        Solid(track, Style.TRACK, Style.TRACK[4])
        bar.edge = bar:CreateTexture(nil, "BACKGROUND", nil, -8)
        Inset(bar.edge, bar, -1)
        bar.sheen = bar:CreateTexture(nil, "OVERLAY", nil, -8)
        bar.sheen:SetPoint("TOPLEFT", bar, "TOPLEFT", 0, 0)
        bar.sheen:SetPoint("BOTTOMRIGHT", bar, "RIGHT", 0, 0)
        bar.sheen:SetColorTexture(1, 1, 1, .16)
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

-- Under the lowest bar that shows, Blizzard's own padding apart, as tall as
-- the power bar.
local function ComboPlace(frame)
    local below = frame.PowerBar
    local extra = frame.AlternatePowerBar
    if extra and extra:IsShown() and not extraHidden then below = extra end
    if not (below and below:IsShown()) then below = frame.HealthBarsContainer or frame end
    local padding = type(frame.GetBarPadding) == "function" and frame:GetBarPadding() or 4
    combo:ClearAllPoints()
    combo:SetPoint("TOPLEFT", below, "BOTTOMLEFT", 0, -padding)
    combo:SetPoint("TOPRIGHT", below, "BOTTOMRIGHT", 0, -padding)
    local height = frame.PowerBar and frame.PowerBar:GetHeight()
    combo:SetHeight(type(height) == "number" and height > 0 and height or 8)
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

-- Shows or hides the row and puts it in place; a layout makes room for it.
local function ComboUpdate()
    local frame = _G.PersonalResourceDisplayFrame
    if not (frame and combo) then return end
    local want = ComboWanted()
    if want then ComboPlace(frame) end
    MuteClassFrame(frame, want)
    combo:SetShown(want)
    ComboPoints()
    if want ~= comboShown then
        comboShown = want
        Restack()
    end
end

-- The row while it shows, so a layout counts it as part of the display.
function R:ComboRow()
    return comboShown and combo or nil
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
        Restyle(health, "prdHealth")
        Restyle(frame.PowerBar, "prdPower")
        Restyle(frame.AlternatePowerBar, "prdPower")
    end
    -- Combo points, for the classes that have them.
    local _, class = UnitClass("player")
    if class == "ROGUE" or class == "DRUID" then
        MakeCombo(frame)
        local events = CreateFrame("Frame")
        for _, event in ipairs({ "UNIT_POWER_FREQUENT", "UNIT_MAXPOWER", "UNIT_DISPLAYPOWER" }) do
            events:RegisterUnitEvent(event, "player")
        end
        for _, event in ipairs({ "PLAYER_TARGET_CHANGED", "UPDATE_SHAPESHIFT_FORM", "PLAYER_ENTERING_WORLD" }) do
            events:RegisterEvent(event)
        end
        events:SetScript("OnEvent", function(_, event)
            if event == "UNIT_POWER_FREQUENT" or event == "PLAYER_TARGET_CHANGED" then ComboPoints() else ComboUpdate() end
        end)
    end
    -- Your power changing, and Edit Mode setting the bars' height, padding
    -- and which show.
    local function Changed(self)
        ExtraMana(self)
        ComboUpdate()
    end
    for _, method in ipairs({ "UpdatePowerBar", "UpdateAlternatePowerBar", "SetPowerBarHeight", "SetBarPadding",
        "SetHidePower", "SetHideAltPower" }) do
        if type(frame[method]) == "function" then hooksecurefunc(frame, method, Changed) end
    end
    if type(frame.UpdateBarWidth) == "function" then hooksecurefunc(frame, "UpdateBarWidth", Rematch) end
    Changed(frame)
    return true
end

-- Whether the display is there to restyle: Blizzard loads it once it's on.
function R:Shown()
    return _G.PersonalResourceDisplayFrame ~= nil
end

-- Redraws the bars after a choice changes.
function R:Apply()
    for bar, state in pairs(bars) do
        local ok, err = pcall(Look, bar, state)
        if not ok and not R.lastError then
            R.lastError = tostring(err)
            print("|cffffd100" .. ns.TITLE .. ":|r couldn't restyle the Personal Resource Display. Please report this: " .. R.lastError)
        end
    end
    ExtraMana(_G.PersonalResourceDisplayFrame)
    ComboLook()
    ComboUpdate()
end

function R:Start()
    if self.started then return end
    self.started = true
    local ok, found = pcall(Hook)
    if ok and found then return end
    if not ok then
        R.lastError = tostring(found)
        print("|cffffd100" .. ns.TITLE .. ":|r couldn't restyle the Personal Resource Display. Please report this: " .. R.lastError)
        return
    end
    -- Blizzard loads the display when it's switched on; wait for it.
    local watcher = CreateFrame("Frame")
    watcher:RegisterEvent("ADDON_LOADED")
    watcher:SetScript("OnEvent", function(frame, _, name)
        if name ~= "Blizzard_PersonalResourceDisplay" then return end
        frame:UnregisterAllEvents()
        local fine, err = pcall(Hook)
        if not fine then
            R.lastError = tostring(err)
            print("|cffffd100" .. ns.TITLE .. ":|r couldn't restyle the Personal Resource Display. Please report this: " .. R.lastError)
        end
    end)
end
