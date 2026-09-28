-- Run the actual addon files against mock copies of Blizzard's cooldown viewer
-- frames, built from Blizzard_CooldownViewer's CooldownViewer.xml. Blizzard's
-- frames are sealed: writing any key on them, or calling anything that shows,
-- hides, scales or reads them, fails the test.
local checks = 0
local function Equal(actual, expected, label)
    checks = checks + 1
    assert(actual == expected, label .. ": expected " .. tostring(expected) .. ", got " .. tostring(actual))
end

-- Mock objects ---------------------------------------------------------------------

local S = setmetatable({}, { __mode = "k" }) -- per-object mock state, never on the object
local FORBIDDEN = {
    Show = true, Hide = true, SetShown = true, SetScale = true, SetSize = true, SetWidth = true,
    SetHeight = true, SetParent = true, SetVertexColor = true, SetDesaturated = true,
    SetSwipeColor = true, SetDrawSwipe = true, SetTexCoord = true, IsShown = true, GetText = true,
    GetValue = true, GetCooldownTimes = true, GetSpellID = true, GetAuraData = true,
    GetAuraDataCached = true, RefreshLayout = true, RefreshData = true, Layout = true,
    SetTexture = true,
}

local Proto = {}
local New

local function Fallback(name)
    return function(self)
        local s = S[self]
        if s.blizzard and FORBIDDEN[name] then error("called " .. name .. " on a Blizzard frame", 2) end
        s.calls[name] = (s.calls[name] or 0) + 1
    end
end

New = function(kind, parent, blizzard)
    local obj = {}
    S[obj] = { kind = kind, parent = parent, points = {}, alpha = 1, regions = {}, children = {},
        masks = {}, shown = true, calls = {}, scripts = {}, events = {}, blizzard = blizzard }
    setmetatable(obj, {
        __index = function(_, key)
            local method = Proto[key]
            if method then
                if S[obj].blizzard and FORBIDDEN[key] then
                    return function() error("called " .. key .. " on a Blizzard frame", 2) end
                end
                return method
            end
            if type(key) == "string" and key:match("^[A-Z]") then return Fallback(key) end
        end,
        __newindex = function(t, key, value)
            if S[t].sealed then error("wrote key '" .. tostring(key) .. "' on a Blizzard frame", 2) end
            rawset(t, key, value)
        end,
    })
    if parent and S[parent] then
        local list = (kind == "Texture" or kind == "MaskTexture" or kind == "FontString") and "regions" or "children"
        table.insert(S[parent][list], obj)
    end
    return obj
end

function Proto:GetObjectType() return S[self].kind end
function Proto:GetRegions() return table.unpack(S[self].regions) end
function Proto:GetName() return S[self].name end
function Proto:CreateTexture(_, layer, _, sublevel)
    local t = New("Texture", self)
    S[t].layer, S[t].sublevel = layer, sublevel
    return t
end
function Proto:CreateFontString() return New("FontString", self) end
function Proto:ClearAllPoints() S[self].points = {} end
function Proto:SetPoint(point, rel, relPoint, x, y) table.insert(S[self].points, { point, rel, relPoint, x, y }) end
function Proto:SetAllPoints(rel) S[self].points = { { "ALL", rel } } end
function Proto:SetAlpha(a) S[self].alpha = a end
function Proto:GetAtlas() return S[self].atlas end
function Proto:RemoveMaskTexture(mask)
    local masks = S[self].masks
    for i = #masks, 1, -1 do if masks[i] == mask then table.remove(masks, i) end end
end
function Proto:SetColorTexture(r, g, b, a) S[self].color = { r, g, b, a } end
function Proto:SetSwipeTexture(t) S[self].swipe = t end
function Proto:SetStatusBarTexture(t) S[self].barTexture = t end
function Proto:SetStatusBarColor(r, g, b) S[self].barColour = { r, g, b } end
function Proto:SetFontObject(o) S[self].font = o end
function Proto:SetCountdownFont(o) S[self].countdownFont = o end
-- Only the addon's own frames use these.
function Proto:Show() local s = S[self]; if not s.shown then s.shown = true; if s.scripts.OnShow then s.scripts.OnShow(self) end end end
function Proto:Hide() local s = S[self]; if s.shown then s.shown = false; if s.scripts.OnHide then s.scripts.OnHide(self) end end end
function Proto:SetShown(v) if v then self:Show() else self:Hide() end end
function Proto:IsShown() return S[self].shown end
function Proto:SetScript(key, fn) S[self].scripts[key] = fn end
function Proto:RegisterEvent(e) S[self].events[e] = true end
function Proto:UnregisterEvent(e) S[self].events[e] = nil end
function Proto:UnregisterAllEvents() S[self].events = {} end
function Proto:SetText(t) S[self].text = t end
function Proto:GetText() return S[self].text end
function Proto:SetChecked(v) S[self].checked = v end
function Proto:GetChecked() return S[self].checked end
function Proto:GetFont() return "font", 12, "" end
function Proto:GetStringWidth() return 40 end
function Proto:Click() S[self].scripts.OnClick(self) end

local function Seal(obj)
    S[obj].sealed, S[obj].blizzard = true, true
    for _, r in ipairs(S[obj].regions) do Seal(r) end
    for _, c in ipairs(S[obj].children) do Seal(c) end
end

-- Blizzard's item templates -----------------------------------------------------------

local function IconParts(frame)
    frame.Icon = New("Texture", frame)
    local mask = New("MaskTexture", frame)
    S[frame.Icon].masks = { mask }
    local overlay = New("Texture", frame)
    S[overlay].atlas = "UI-HUD-CoolDownManager-IconOverlay"
    return overlay, mask
end

local function CooldownItem()
    local item = New("Frame")
    local overlay = IconParts(item)
    item.OutOfRange = New("Texture", item)
    S[item.OutOfRange].atlas = "UI-CooldownManager-OORshadow"
    item.Cooldown = New("Cooldown", item)
    item.ChargeCount = New("Frame", item)
    item.ChargeCount.Current = New("FontString", item.ChargeCount)
    item.CooldownFlash = New("Frame", item)
    Seal(item)
    return item, overlay
end

local function BuffItem()
    local item = New("Frame")
    local overlay = IconParts(item)
    item.Cooldown = New("Cooldown", item)
    item.DebuffBorder = New("Frame", item)
    item.Applications = New("Frame", item)
    Seal(item)
    return item, overlay
end

local function BarItem()
    local item = New("Frame")
    item.Icon = New("Frame", item)
    local overlay = IconParts(item.Icon)
    item.Icon.Applications = New("FontString", item.Icon)
    item.DebuffBorder = New("Frame", item)
    item.Bar = New("StatusBar", item)
    item.Bar.BarBG = New("Texture", item.Bar)
    item.Bar.Pip = New("Texture", item.Bar)
    item.Bar.Name = New("FontString", item.Bar)
    item.Bar.Duration = New("FontString", item.Bar)
    Seal(item)
    return item, overlay
end

local acquired = {}
local function Viewer(name, make, preexisting)
    local viewer = New("Frame")
    local active = {}
    for i = 1, preexisting do active[make()] = true end
    viewer.itemFramePool = { EnumerateActive = function() return pairs(active) end }
    viewer.OnAcquireItemFrame = function(self, item) acquired[item] = (acquired[item] or 0) + 1 end
    viewer.make = make
    Seal(viewer)
    S[viewer.itemFramePool] = nil
    return viewer, active
end

-- Game environment ------------------------------------------------------------------

local frames, printed, reloads, combat, cvarOn
local bindings
local cvars = {} -- addon-registered game settings survive a restart

local function Fire(event, ...)
    for _, frame in ipairs(frames) do
        if S[frame].events[event] and S[frame].scripts.OnEvent then S[frame].scripts.OnEvent(frame, event, ...) end
    end
end

local function Environment(keepCVars)
    frames, printed, reloads, combat, cvarOn = {}, {}, 0, false, true
    if not keepCVars then cvars = {} end
    bindings = {}
    acquired = {}
    _G.CreateFrame = function(_, name, parent)
        local f = New("Frame", parent)
        S[f].name = name
        S[f].shown = true
        table.insert(frames, f)
        if name then _G[name] = f end
        return f
    end
    _G.hooksecurefunc = function(t, key, hook)
        local original = t[key]
        rawset(t, key, function(...) original(...); hook(...) end)
    end
    _G.print = function(msg) table.insert(printed, msg) end
    _G.InCombatLockdown = function() return combat end
    _G.ReloadUI = function()
        assert(not combat, "blocked ReloadUI in combat")
        assert(_G.ClassicCooldownManagerFrame and S[_G.ClassicCooldownManagerFrame].shown, "window hidden before reload")
        reloads = reloads + 1
    end
    _G.C_CVar = {
        GetCVarBool = function(name) assert(name == "cooldownViewerEnabled"); return cvarOn end,
        GetCVar = function(name) return cvars[name] end,
        RegisterCVar = function(name, default) if cvars[name] == nil then cvars[name] = default end end,
        SetCVar = function(name, value) assert(cvars[name] ~= nil, "set before register"); cvars[name] = value end,
    }
    _G.SystemFont_Shadow_Large_Outline = {}
    _G.ClearOverrideBindings = function(owner) assert(not combat, "binding change in combat"); bindings[owner] = nil end
    _G.SetOverrideBindingClick = function(owner, _, key, button) assert(not combat, "binding change in combat"); bindings[owner] = key .. ":" .. button end
    _G.SlashCmdList = {}
    _G.GameFontHighlight = { GetFont = function() return "font", 12, "" end, name = "GameFontHighlight" }
    _G.GameFontHighlightSmall = { name = "GameFontHighlightSmall" }
    _G.Settings = {
        RegisterCanvasLayoutCategory = function(canvas, title) return { canvas = canvas, title = title } end,
        RegisterAddOnCategory = function(cat) _G.registeredCategory = cat end,
    }
    _G.ClassicCooldownManagerDB = nil
    _G.ClassicCooldownManagerFrame = nil
    for _, name in ipairs({ "EssentialCooldownViewer", "UtilityCooldownViewer", "BuffIconCooldownViewer", "BuffBarCooldownViewer" }) do
        _G[name] = nil
    end
end

local function Viewers(pre)
    local v = {}
    v.essential, v.essentialActive = Viewer("EssentialCooldownViewer", CooldownItem, pre)
    v.utility, v.utilityActive = Viewer("UtilityCooldownViewer", CooldownItem, pre)
    v.buffs, v.buffsActive = Viewer("BuffIconCooldownViewer", BuffItem, pre)
    v.bars, v.barsActive = Viewer("BuffBarCooldownViewer", BarItem, pre)
    _G.EssentialCooldownViewer, _G.UtilityCooldownViewer = v.essential, v.utility
    _G.BuffIconCooldownViewer, _G.BuffBarCooldownViewer = v.buffs, v.bars
    return v
end

local function Load(saved)
    local ns = {}
    _G.ClassicCooldownManagerDB = saved
    assert(loadfile("Core.lua"))("ClassicCooldownManager", ns)
    assert(loadfile("Skin.lua"))("ClassicCooldownManager", ns)
    Fire("ADDON_LOADED", "ClassicCooldownManager")
    return ns
end

local function First(active) for item in pairs(active) do return item end end

local function Edges(frame)
    local found = {}
    for _, r in ipairs(S[frame].regions) do
        if S[r].layer == "BACKGROUND" and S[r].sublevel == -8 then table.insert(found, r) end
    end
    return found
end

local function InsetBy(region, anchor, inset)
    local p = S[region].points
    return #p == 2 and p[1][1] == "TOPLEFT" and p[1][2] == anchor and p[1][4] == inset and p[1][5] == -inset
        and p[2][1] == "BOTTOMRIGHT" and p[2][2] == anchor and p[2][4] == -inset and p[2][5] == inset
end

-- Classic look on existing and newly acquired cooldown icons ---------------------------------

Environment()
local v = Viewers(1)
local ns = Load(nil)
Equal(ns.Get("classicLook"), true, "Classic look is on by default")
Equal(SlashCmdList.CLASSICCOOLDOWNMANAGER ~= nil and SLASH_CLASSICCOOLDOWNMANAGER1, "/ccm", "/ccm opens the settings")
Equal(registeredCategory and registeredCategory.title, "Classic Cooldown Manager", "listed under Options > AddOns")

local item = First(v.essentialActive)
Equal(ns.Skin:IsSkinned(item), true, "icons already on screen are restyled at load")
Equal(#S[item.Icon].masks, 0, "rounded mask removed")
Equal(InsetBy(item.Icon, item, 2), true, "essential icon inset 2 so default spacing keeps a gap")
local edges = Edges(item)
Equal(#edges, 1, "one dark edge behind the icon")
Equal(S[edges[1]].color[1] == 0 and S[edges[1]].color[4], .9, "the edge is near-black")
Equal(InsetBy(edges[1], item.Icon, -1), true, "the edge sits one unit around the icon")
Equal(InsetBy(item.Cooldown, item.Icon, 0), true, "the sweep covers exactly the square icon")
Equal(S[item.Cooldown].swipe, "Interface\\Buttons\\WHITE8X8", "square cooldown sweep")
Equal(S[item.OutOfRange].alpha, 0, "modern range shadow hidden; the red icon tint remains")
Equal(S[item.CooldownFlash].alpha, 0, "modern end-of-cooldown sparkle hidden")
local overlayHidden = false
for _, r in ipairs(S[item].regions) do
    if S[r].atlas == "UI-HUD-CoolDownManager-IconOverlay" then overlayHidden = S[r].alpha == 0 end
end
Equal(overlayHidden, true, "modern icon frame art hidden")

local fresh = CooldownItem()
v.essential:OnAcquireItemFrame(fresh)
Equal(acquired[fresh], 1, "Blizzard's own OnAcquireItemFrame still runs first")
Equal(ns.Skin:IsSkinned(fresh), true, "newly acquired icons are restyled")
v.essential:OnAcquireItemFrame(fresh)
Equal(#Edges(fresh), 1, "a reused frame is not restyled twice")
Equal(acquired[fresh], 2, "Blizzard still handles every acquire")

local utility = CooldownItem()
v.utility:OnAcquireItemFrame(utility)
Equal(InsetBy(utility.Icon, utility, 1.5), true, "utility icon inset 1.5")

-- Tracked buffs as icons.
local buff = First(v.buffsActive)
Equal(#S[buff.Icon].masks, 0, "buff icon unmasked")
Equal(InsetBy(buff.Icon, buff, 1.5), true, "buff icon inset 1.5")
Equal(S[buff.Cooldown].swipe, "Interface\\Buttons\\WHITE8X8", "buff duration sweep is square")
Equal(#S[buff.DebuffBorder].points, 0, "Blizzard's debuff border keeps its own anchors")
Equal(S[buff.Cooldown].countdownFont, "SystemFont_Shadow_Large_Outline", "buff timers one size smaller")
Equal(S[item.Cooldown].countdownFont, nil, "essential timers keep Blizzard's font")
Equal(S[utility.Cooldown].countdownFont, nil, "utility timers keep Blizzard's font")

-- Tracked buffs as bars.
local bar = First(v.barsActive)
Equal(#S[bar.Icon.Icon].masks, 0, "bar icon unmasked")
Equal(InsetBy(bar.Icon.Icon, bar.Icon, 1), true, "bar icon inset 1")
Equal(#Edges(bar.Icon), 1, "bar icon has a dark edge")
Equal(S[bar.Bar].barTexture, "Interface\\TargetingFrame\\UI-StatusBar", "Classic bar texture")
Equal(S[bar.Bar].barColour[1] == 1 and S[bar.Bar].barColour[2] == .5 and S[bar.Bar].barColour[3], .25, "Blizzard's orange kept")
Equal(S[bar.Bar.BarBG].color[4], .5, "dark bar background")
Equal(InsetBy(bar.Bar.BarBG, bar.Bar, 0), true, "background fits the bar")
Equal(#Edges(bar.Bar), 1, "bar has a dark edge")
Equal(S[bar.Bar.Pip].alpha, 0, "modern spark hidden")
Equal(S[bar.Bar.Name].font, GameFontHighlight, "Classic name font")
Equal(S[bar.Bar.Duration].font, GameFontHighlightSmall, "Classic duration font")
Equal(next(S[bar.Icon.Applications].calls) == nil and S[bar.Icon.Applications].font == nil, true, "stack count untouched")

-- Only hooksecurefunc touched Blizzard's viewers.
for _, viewer in ipairs({ v.essential, v.utility, v.buffs, v.bars }) do
    local keys = 0
    for key in pairs(viewer) do if key ~= "make" then keys = keys + 1 end end
    Equal(keys, 2, "viewer holds only its pool and the hooked acquire function")
end
Equal(#printed, 0, "no errors reported")

-- A failure is reported once, never thrown into Blizzard's code --------------------------

local broken = New("Frame")
Seal(broken)
v.essential:OnAcquireItemFrame(broken)
Equal(#printed, 1, "a restyle failure is reported")
Equal(printed[1]:find("Please report this", 1, true) ~= nil, true, "with a clear message")
local broken2 = New("Frame")
Seal(broken2)
v.utility:OnAcquireItemFrame(broken2)
Equal(#printed, 1, "reported only once per session")

-- Classic look off: nothing is hooked or restyled -----------------------------------

Environment()
v = Viewers(1)
ns = Load({ classicLook = false })
Equal(ns.Skin.started, nil, "skin not started when off")
Equal(ns.Skin:IsSkinned(First(v.essentialActive)), false, "icons keep Blizzard's look")
Equal(rawget(v.essential, "OnAcquireItemFrame") == v.essential.OnAcquireItemFrame, true, "no hook installed")
local plain = CooldownItem()
v.essential:OnAcquireItemFrame(plain)
Equal(#S[plain.Icon].masks, 1, "new icons keep the rounded mask")

-- Blizzard's Cooldown Manager loading after the addon -------------------------------------

Environment()
ns = Load(nil)
Equal(ns.Skin.started, true, "skin waiting")
v = Viewers(1)
Fire("ADDON_LOADED", "Blizzard_Something")
Equal(ns.Skin:IsSkinned(First(v.essentialActive)), false, "ignores other addons")
Fire("ADDON_LOADED", "Blizzard_CooldownViewer")
Equal(ns.Skin:IsSkinned(First(v.essentialActive)), true, "restyles once Blizzard's viewers load")
Equal(ns.Skin:IsSkinned(First(v.barsActive)), true, "bars too")

-- Settings backup -----------------------------------------------------------------------

Environment()
Viewers(0)
ns = Load(nil)
Equal(cvars.ClassicCooldownManagerBackup, "accent=orange;classicBars=0;classicLook=1;listItems=0;listRanks=0", "backup written at first login")
ns.Set("classicLook", false)
ns.Set("accent", "teal")
Equal(cvars.ClassicCooldownManagerBackup, "accent=teal;classicBars=0;classicLook=0;listItems=0;listRanks=0", "backup follows a change")

-- The client loses the saved settings on restart; the backup survives.
Environment(true)
v = Viewers(1)
ns = Load(nil)
Equal(ns.Get("classicLook"), false, "choice restored from the backup")
Equal(ClassicCooldownManagerDB.classicLook, false, "and saved again")
Equal(ns.Skin.started, nil, "so the Classic look stays off")
Equal(ns.Get("accent"), "teal", "accent restored too")

-- Saved settings win over an older backup.
Environment(true)
Viewers(0)
ns = Load({ classicLook = true })
Equal(ns.Get("classicLook"), true, "saved settings win")
Equal(cvars.ClassicCooldownManagerBackup, "accent=teal;classicBars=0;classicLook=1;listItems=0;listRanks=0", "backup brought up to date")

-- Anything unexpected in the backup is ignored.
Environment()
cvars.ClassicCooldownManagerBackup = "classicLook=maybe;os=1;print(1);accent=pink"
Viewers(0)
ns = Load(nil)
Equal(ns.Get("classicLook"), true, "junk ignored; default used")
Equal(ClassicCooldownManagerDB.os, nil, "unknown keys never copied")
Equal(ns.Get("accent"), "orange", "unknown accents ignored")
ClassicCooldownManagerDB.accent = "pink"
Equal(ns.Get("accent"), "orange", "an invalid saved accent reads as the default")

print = _G.print
io.write("Classic Cooldown Manager checks passed: " .. checks .. " assertions.\n")
