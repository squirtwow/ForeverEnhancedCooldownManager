-- Blizzard's Personal Resource Display (Options > Combat), restyled like the
-- Tracked Bars: its health and power bars in the same design, each in
-- Blizzard's colour or one of yours. Some specs get a second mana bar under
-- the main one: it's hidden while the main bar is mana too, so it never just
-- repeats it, and half as tall in bear, cat and other forms. While a layout
-- stacks your bars around it, it can be as wide as your widest row.
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

local function Look(bar, state)
    local design, colour = ns.Get("barStyle"), Colour(state)
    local outline = design == "outline"
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
    bar:SetStatusBarTexture(Style.FLAT)
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
    if ns.Layout and ns.Layout:Active() then ns.Layout:Stack() end
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
    -- Your power changing, and Edit Mode setting the bars' height.
    for _, method in ipairs({ "UpdatePowerBar", "UpdateAlternatePowerBar", "SetPowerBarHeight" }) do
        if type(frame[method]) == "function" then hooksecurefunc(frame, method, ExtraMana) end
    end
    if type(frame.UpdateBarWidth) == "function" then hooksecurefunc(frame, "UpdateBarWidth", Rematch) end
    -- Combo points come and go with cat form (the holder keeps its height).
    local class = frame.classFrame
    if class and class.HookScript then
        class:HookScript("OnShow", Restack)
        class:HookScript("OnHide", Restack)
    end
    ExtraMana(frame)
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
