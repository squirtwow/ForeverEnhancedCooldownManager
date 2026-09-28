-- Run the actual addon files against mock copies of Blizzard's cooldown viewer
-- frames, built from Blizzard_CooldownViewer's CooldownViewer.xml. Blizzard's
-- frames are sealed: writing any key on them, or calling anything that shows,
-- hides, scales or reads them, fails the test. The only size changes allowed
-- are a Tracked Bar's own status bar height, inside its unchanged item frame,
-- the height of the Personal Resource Display's extra mana bar, and the
-- display's width while a layout matches it to your rows (the widths its own
-- Bar Width setting changes).
local checks = 0
local function Equal(actual, expected, label)
    checks = checks + 1
    assert(actual == expected, label .. ": expected " .. tostring(expected) .. ", got " .. tostring(actual))
end

-- Mock objects ---------------------------------------------------------------------

local S = setmetatable({}, { __mode = "k" }) -- per-object mock state, never on the object
local FORBIDDEN = {
    Show = true, Hide = true, SetShown = true, SetScale = true, SetSize = true,
    SetParent = true, SetVertexColor = true, SetDesaturated = true,
    SetSwipeColor = true, SetDrawSwipe = true, IsShown = true, GetText = true,
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
function Proto:SetStatusBarColor(r, g, b, a) S[self].barColour = { r, g, b, a } end
function Proto:GetHeight() return S[self].height end
function Proto:GetStatusBarColor() local c = S[self].barColour or { 1, 1, 1, 1 }; return c[1], c[2], c[3], c[4] end
function Proto:SetAtlas(atlas) S[self].atlas = atlas end
function Proto:SetWidth(w)
    if S[self].blizzard and not S[self].resizable then error("resized a Blizzard frame", 2) end
    S[self].width = w
end
function Proto:SetFontObject(o) S[self].font = o end
function Proto:SetCountdownFont(o) S[self].countdownFont = o end
function Proto:SetTexCoord(...)
    S[self].coords = table.concat({ ... }, ",")
    S[self].zooms = (S[self].zooms or 0) + 1
end
function Proto:SetHeight(h)
    if S[self].blizzard and S[self].kind ~= "StatusBar" then error("resized a Blizzard frame", 2) end
    S[self].height = h
end
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
-- The spell Blizzard's settings give a Tracked Bar.
function Proto:GetBaseSpellID() return S[self].baseSpell end
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
    item.Applications.Applications = New("FontString", item.Applications)
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
    S[item.Bar.Pip].atlas = "UI-HUD-CoolDownManager-Bar-Pip"
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
        assert(_G.FECMFrame and S[_G.FECMFrame].shown, "window hidden before reload")
        reloads = reloads + 1
    end
    _G.C_CVar = {
        GetCVarBool = function(name) assert(name == "cooldownViewerEnabled"); return cvarOn end,
        GetCVar = function(name) return cvars[name] end,
        RegisterCVar = function(name, default) if cvars[name] == nil then cvars[name] = default end end,
        SetCVar = function(name, value) assert(cvars[name] ~= nil, "set before register"); cvars[name] = value end,
    }
    _G.UnitClass = function() return "Druid", "DRUID" end
    _G.RAID_CLASS_COLORS = { DRUID = { r = 1, g = .49, b = .04 } }
    _G.CreateFont = function(name)
        local font = New("Font")
        _G[name] = font
        return font
    end
    _G.ClearOverrideBindings = function(owner) assert(not combat, "binding change in combat"); bindings[owner] = nil end
    _G.SetOverrideBindingClick = function(owner, _, key, button) assert(not combat, "binding change in combat"); bindings[owner] = key .. ":" .. button end
    _G.SlashCmdList = {}
    _G.GameFontHighlight = { GetFont = function() return "font", 12, "" end, name = "GameFontHighlight" }
    _G.GameFontHighlightSmall = { name = "GameFontHighlightSmall" }
    _G.Settings = {
        RegisterCanvasLayoutCategory = function(canvas, title) return { canvas = canvas, title = title } end,
        RegisterAddOnCategory = function(cat) _G.registeredCategory = cat end,
    }
    _G.ForeverEnhancedCooldownManagerDB = nil
    _G.FECMFrame = nil
    _G.PersonalResourceDisplayFrame = nil
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
    _G.ForeverEnhancedCooldownManagerDB = saved
    assert(loadfile("Core.lua"))("ForeverEnhancedCooldownManager", ns)
    assert(loadfile("Style.lua"))("ForeverEnhancedCooldownManager", ns)
    assert(loadfile("Skin.lua"))("ForeverEnhancedCooldownManager", ns)
    assert(loadfile("Resource.lua"))("ForeverEnhancedCooldownManager", ns)
    Fire("ADDON_LOADED", "ForeverEnhancedCooldownManager")
    return ns
end

local function First(active) for item in pairs(active) do return item end end

local function Edges(frame)
    local found = {}
    for _, r in ipairs(S[frame].regions) do
        if S[r].layer == "BACKGROUND" and S[r].sublevel == -7 then table.insert(found, r) end
    end
    return found
end

local function InsetBy(region, anchor, inset)
    local p = S[region].points
    return #p == 2 and p[1][1] == "TOPLEFT" and p[1][2] == anchor and p[1][4] == inset and p[1][5] == -inset
        and p[2][1] == "BOTTOMRIGHT" and p[2][2] == anchor and p[2][4] == -inset and p[2][5] == inset
end

-- Charcoal look on existing and newly acquired cooldown icons --------------------------------

local ZOOM = "0.08,0.92,0.08,0.92"

Environment()
local v = Viewers(1)
local ns = Load(nil)
Equal(ns.Get("skin"), true, "charcoal look is on by default")
Equal(SlashCmdList.FECM ~= nil and SLASH_FECM1, "/fecm", "/fecm opens the settings")
Equal(SLASH_FECM2, "/ccm", "/ccm still works")
Equal(registeredCategory and registeredCategory.title, "Forever Enhanced Cooldown Manager", "listed under Options > AddOns")

local item = First(v.essentialActive)
Equal(ns.Skin:IsSkinned(item), true, "icons already on screen are restyled at load")
Equal(#S[item.Icon].masks, 0, "rounded mask removed")
Equal(InsetBy(item.Icon, item, 2), true, "essential icon inset 2, so the gap matches Edit Mode's padding")
Equal(S[item.Icon].coords, ZOOM, "icon art zoomed past its own bevel")
Equal(#Edges(item), 0, "no frame around the icon")
Equal(InsetBy(item.Cooldown, item.Icon, 0), true, "the sweep covers exactly the square icon")
Equal(S[item.Cooldown].swipe, "Interface\\Buttons\\WHITE8X8", "square cooldown sweep")
Equal(S[item.Cooldown].countdownFont, "FECMFont25", "big countdown, half the icon's height")
Equal(_G.FECMFont25 ~= nil, true, "the font exists for the game to use")
Equal(S[item.ChargeCount.Current].font, "FECMFont18", "bigger charge count")
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
Equal(S[fresh.Icon].zooms, 1, "a reused frame is not restyled twice")
Equal(acquired[fresh], 2, "Blizzard still handles every acquire")

local utility = CooldownItem()
v.utility:OnAcquireItemFrame(utility)
Equal(InsetBy(utility.Icon, utility, 2), true, "utility icon inset 2")
Equal(S[utility.Cooldown].countdownFont, "FECMFont15", "utility countdown sized for its smaller icons")
Equal(S[utility.ChargeCount.Current].font, "FECMFont12", "utility charges readable")

-- Tracked buffs as icons.
local buff = First(v.buffsActive)
Equal(#S[buff.Icon].masks, 0, "buff icon unmasked")
Equal(InsetBy(buff.Icon, buff, 2), true, "buff icon inset 2")
Equal(S[buff.Icon].coords, ZOOM, "buff icon zoomed")
Equal(#Edges(buff), 0, "no frame around buff icons")
Equal(S[buff.Cooldown].swipe, "Interface\\Buttons\\WHITE8X8", "buff duration sweep is square")
Equal(#S[buff.DebuffBorder].points, 0, "Blizzard's debuff border keeps its own anchors")
Equal(S[buff.Cooldown].countdownFont, "FECMFont20", "buff timers big and bold")
Equal(S[buff.Applications.Applications].font, "FECMFont14", "bigger stack count")

-- Tracked buffs as bars.
local bar = First(v.barsActive)
Equal(#S[bar.Icon.Icon].masks, 0, "bar icon unmasked")
Equal(InsetBy(bar.Icon.Icon, bar.Icon, 2), true, "bar icon inset 2")
Equal(S[bar.Icon.Icon].coords, ZOOM, "bar icon zoomed")
Equal(#Edges(bar.Icon), 0, "no frame around the bar icon")
Equal(S[bar.Icon.Applications].font, "FECMFont12", "bar stack count")
Equal(S[bar.Bar].height, 26, "bar as tall as the icon art")
Equal(S[bar].height, nil, "the item frame itself is never resized")
Equal(S[bar.Bar].barTexture, "Interface\\Buttons\\WHITE8X8", "flat bar")
local fill = S[bar.Bar].barColour
Equal(fill[1] == 1 and fill[2] == .5 and fill[3] == .25 and fill[4], 1, "Glass in Blizzard's orange by default")
Equal(S[bar.Bar.BarBG].color[1] == .08 and S[bar.Bar.BarBG].color[4], .85, "near-black track")
Equal(InsetBy(bar.Bar.BarBG, bar.Bar, 0), true, "track fits the bar")
Equal(#Edges(bar.Bar), 0, "no charcoal frame around the bar")
Equal(S[bar.Bar.Name].font, "FECMFont13", "bold name")
Equal(S[bar.Bar.Duration].font, "FECMFont15", "bigger time")
-- The pieces the skin added to the bar, found by their layer.
local function Piece(owner, layer, sublevel)
    for _, r in ipairs(S[owner].regions) do
        if S[r].layer == layer and S[r].sublevel == sublevel then return r end
    end
end
local barEdge, sheen, box = Piece(bar.Bar, "BACKGROUND", -8), Piece(bar.Bar, "OVERLAY", -8), Piece(bar.Bar, "OVERLAY", -7)
local iconEdge = Piece(bar.Icon, "BACKGROUND", -8)
Equal(InsetBy(barEdge, bar.Bar, -1) and S[barEdge].color[1] == 0 and S[barEdge].color[4], 1, "Glass: a 1px black edge round the bar")
Equal(InsetBy(iconEdge, bar.Icon.Icon, -1), true, "and round its icon")
Equal(S[sheen].shown, true, "a shine across the top")
Equal(S[box].shown, false, "no time box")
Equal(S[bar.Bar.Pip].alpha, 1, "and Blizzard's spark at the end of the fill")
Equal(S[bar.Bar.Duration].points[1][1], "RIGHT", "time on the right")
Equal(S[bar.Bar.Name].points[2][2], bar.Bar.Duration, "the name stops short of it")

ns.Set("barStyle", "split")
ns.Skin:ApplyBarLook()
Equal(S[sheen].shown == false and S[box].shown, true, "Split: a dark box instead of the shine")
local at = S[bar.Bar.Duration].points[1]
Equal(at[1] == "CENTER" and at[2], box, "the time centred in it")
Equal(S[bar.Bar.Name].points[2][2], box, "the name stops before it")
Equal(S[bar.Bar.Pip].alpha, 0, "no spark")

ns.Set("barStyle", "outline")
ns.Set("barColour", "blue")
ns.Skin:ApplyBarLook()
fill = S[bar.Bar].barColour
Equal(fill[3] == .88 and fill[4], .45, "Outline: a see-through fill")
Equal(S[barEdge].color[3] == .88 and S[iconEdge].color[3], .88, "inside an edge in the bar's colour, round the icon too")
local pip = S[bar.Bar.Pip]
Equal(pip.alpha == 0 and pip.color == nil and pip.width, nil, "no line where the fill ends; the spark is never redrawn or resized")

ns.Set("barStyle", "glass")
ns.Set("barColour", "class")
ns.Skin:ApplyBarLook()
Equal(S[bar.Bar.Pip].atlas == "UI-HUD-CoolDownManager-Bar-Pip" and S[bar.Bar.Pip].alpha, 1, "back to Glass, the spark returns")
fill = S[bar.Bar].barColour
Equal(fill[1] == 1 and fill[2] == .49 and fill[3], .04, "Class: your class colour")
Equal(S[barEdge].color[1], 0, "and the edge is black again")
ns.Set("barColour", "orange")
ns.Skin:ApplyBarLook()
Equal(#printed, 0, "no errors while switching")

-- Each bar can have a colour of its own, by the spell Blizzard gives it.
S[bar].baseSpell = 467 -- Thorns
local other = BarItem()
S[other].baseSpell = 1126 -- Mark of the Wild
v.bars:OnAcquireItemFrame(other)
v.barsActive[other] = true
rawset(other, "layoutIndex", 1) -- Blizzard's own order
rawset(bar, "layoutIndex", 2)
Equal(table.concat(ns.Skin:TrackedBars(), ","), "1126,467", "the window lists your Tracked Bars in Blizzard's order")
ns.SetBarColour(467, "purple")
ns.Skin:ApplyBarLook()
fill = S[bar.Bar].barColour
Equal(fill[1] == .6 and fill[2] == .43 and fill[3], .91, "Thorns in its own purple")
fill = S[other.Bar].barColour
Equal(fill[1] == 1 and fill[2] == .5 and fill[3], .25, "the others keep the colour for all")
ns.Set("barColour", "green")
ns.Skin:ApplyBarLook()
Equal(S[bar.Bar].barColour[3], .91, "a bar's own colour stays when the colour for all changes")
Equal(S[other.Bar].barColour[2], .74, "which the others follow")
-- Blizzard's bars are pooled and change spell; the colour follows at once.
S[other].baseSpell = 467
other:OnCooldownIDSet()
Equal(S[other.Bar].barColour[3], .91, "a bar given Thorns turns purple straight away")
local SECRET = {}
_G.issecretvalue = function(value) return value == SECRET end
S[other].baseSpell = SECRET
other:OnCooldownIDSet()
Equal(S[other.Bar].barColour[2], .74, "a spell that can't be read uses the colour for all")
_G.issecretvalue = nil
ns.SetBarColour(467, nil)
ns.Skin:ApplyBarLook()
Equal(ns.BarColours()[467] == nil and S[bar.Bar].barColour[2], .74, "and back to the colour for all")
ns.Set("barColour", "orange")
ns.Skin:ApplyBarLook()
v.barsActive[other] = nil

-- The window's preview: the addon's own bar, drawn by the same code.
local sample = ns.Skin:Sample(nil, 300)
Equal(S[sample].sealed, nil, "made from the addon's own frames")
Equal(S[sample.Bar].height, 26, "shaped like a Tracked Bar")
Equal(S[sample.Bar].barColour[2], .5, "in the colour for all bars")
ns.Set("barStyle", "split")
ns.Set("barColour", "blue")
ns.Skin:ApplyBarLook()
Equal(S[sample.Bar].barColour[3], .88, "following the colour")
Equal(S[Piece(sample.Bar, "OVERLAY", -7)].shown, true, "and the design")
Equal(S[sample.Bar.Pip].atlas, "UI-HUD-CoolDownManager-Bar-Pip", "with Blizzard's spark")
ns.Set("barStyle", "glass")
ns.Set("barColour", "orange")
ns.Skin:ApplyBarLook()
Equal(#printed, 0, "no errors with bars of their own colour")

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

-- Charcoal look off: nothing is hooked or restyled -----------------------------------

Environment()
v = Viewers(1)
ns = Load({ skin = false })
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
Equal(cvars.FECMBackup, "accent=orange;barColour=orange;barStyle=glass;listItems=0;listRanks=0;prdHealth=default;prdHideRepeat=1;prdMatch=1;prdPower=default;prdSkin=1;skin=1;useBars=0", "backup written at first login")
ns.Set("skin", false)
ns.Set("accent", "teal")
Equal(cvars.FECMBackup, "accent=teal;barColour=orange;barStyle=glass;listItems=0;listRanks=0;prdHealth=default;prdHideRepeat=1;prdMatch=1;prdPower=default;prdSkin=1;skin=0;useBars=0", "backup follows a change")

ns.SetBarColour(467, "blue")
ns.SetBarColour(1126, "class")

-- The client loses the saved settings on restart; the backup survives.
Environment(true)
v = Viewers(1)
ns = Load(nil)
Equal(ns.Get("skin"), false, "choice restored from the backup")
Equal(ForeverEnhancedCooldownManagerDB.skin, false, "and saved again")
Equal(ns.Skin.started, nil, "so the charcoal look stays off")
Equal(ns.Get("accent"), "teal", "accent restored too")
Equal(ns.BarColours()[467] == "blue" and ns.BarColours()[1126], "class", "and each bar's own colour")

-- Saved settings win over an older backup.
Environment(true)
Viewers(0)
ns = Load({ skin = true })
Equal(ns.Get("skin"), true, "saved settings win")
Equal(cvars.FECMBackup, "accent=teal;barColour=orange;barStyle=glass;listItems=0;listRanks=0;prdHealth=default;prdHideRepeat=1;prdMatch=1;prdPower=default;prdSkin=1;skin=1;useBars=0", "backup brought up to date")

-- Anything unexpected in the backup is ignored.
Environment()
cvars.FECMBackup = "skin=maybe;os=1;print(1);accent=pink"
Viewers(0)
ns = Load(nil)
Equal(ns.Get("skin"), true, "junk ignored; default used")
Equal(ForeverEnhancedCooldownManagerDB.os, nil, "unknown keys never copied")
Equal(ns.Get("accent"), "orange", "unknown accents ignored")
ForeverEnhancedCooldownManagerDB.accent = "pink"
Equal(ns.Get("accent"), "orange", "an invalid saved accent reads as the default")
ForeverEnhancedCooldownManagerDB.barColours = { [467] = "pink", [0] = "blue", foo = "green", [1126] = "green" }
local kept = 0
for _ in pairs(ns.BarColours()) do kept = kept + 1 end
Equal(kept == 1 and ns.BarColours()[1126], "green", "only real spells with a real colour are kept")
ns.SetBarColour("Thorns", "blue")
ns.SetBarColour(467, "pink")
Equal(ns.BarColours()[467], nil, "nothing else can be set")

-- The first login under the new name carries the old name's backup over.
Environment()
cvars.ClassicCooldownManagerBackup = "accent=teal;classicBars=1;classicLook=0;listItems=1"
cvars.ClassicCooldownManagerBackupBars0 = "1"
cvars.ClassicCooldownManagerBackupBars1 = "cd.size=40;cd.spells=Moonfire|Bash"
Viewers(0)
ns = Load(nil)
Equal(ns.Get("useBars"), true, "old Classic Bars switch carried over")
Equal(ns.Get("skin"), false, "old Classic look switch carried over")
Equal(ns.Get("accent"), "teal", "accent carried over")
Equal(table.concat(ns.BarData("cd").spells, ","), "Moonfire,Bash", "bars carried over")
Equal(ns.BarData("cd").size, 40, "with their size")
Equal(cvars.FECMBackup, "accent=teal;barColour=orange;barStyle=glass;listItems=1;listRanks=0;prdHealth=default;prdHideRepeat=1;prdMatch=1;prdPower=default;prdSkin=1;skin=0;useBars=1", "and saved under the new name")

-- After that, the new name's own settings and backup are used.
Environment(true)
cvars.ClassicCooldownManagerBackup = "classicBars=0"
Viewers(0)
ns = Load({ useBars = true })
Equal(ns.Get("useBars"), true, "the old backup is never read again")

-- Blizzard's Personal Resource Display ------------------------------------------------------

local function PRDBar(colour)
    local bar = New("StatusBar")
    local art = New("Texture", bar)
    S[art].atlas = "UI-HUD-CoolDownManager-Bar-BG"
    S[bar].barColour = colour
    return bar, art
end
local function PRD()
    local frame = New("Frame")
    local container = New("Frame", frame)
    frame.HealthBarsContainer = container
    local health, healthArt = PRDBar({ 0, 1, 0, 1 })
    container.healthBar = health
    frame.PowerBar = PRDBar({ 0, 0, 1, 1 })
    frame.AlternatePowerBar = PRDBar({ 0, 0, 1, 1 })
    frame.AlternatePowerBar.powerName = "MANA"
    frame.UpdatePowerBar = function() end
    frame.UpdateAlternatePowerBar = function() end
    -- Edit Mode's bar height, for both power bars.
    frame.SetPowerBarHeight = function(self, height)
        self.PowerBar:SetHeight(height)
        self.AlternatePowerBar:SetHeight(height)
    end
    S[frame.PowerBar].height, S[frame.AlternatePowerBar].height = 12, 12
    frame.ClassFrameContainer = New("Frame", frame)
    -- Edit Mode's Bar Width: these widths, and only these, may change.
    frame.defaultBarWidth, frame.barWidthPercent = 200, 100
    frame.UpdateBarWidth = function(self)
        local width = self.defaultBarWidth * self.barWidthPercent / 100
        for _, part in ipairs({ self, self.HealthBarsContainer, self.PowerBar, self.AlternatePowerBar, self.ClassFrameContainer }) do
            part:SetWidth(width)
        end
    end
    for _, part in ipairs({ frame, container, frame.PowerBar, frame.AlternatePowerBar, frame.ClassFrameContainer }) do
        S[part].resizable = true
    end
    for _, part in ipairs({ frame, health, frame.PowerBar, frame.AlternatePowerBar }) do Seal(part) end
    return frame, healthArt
end
local power = 0 -- the main bar's power: 0 mana, 3 energy
Environment()
Viewers(0)
_G.UnitPowerType = function() return power end
local prd, healthArt = PRD()
_G.PersonalResourceDisplayFrame = prd
ns = Load(nil)
local health = prd.HealthBarsContainer.healthBar
Equal(S[health].barTexture, "Interface\\Buttons\\WHITE8X8", "personal health bar made flat")
Equal(S[healthArt].color[1] == .08 and S[healthArt].color[4], .85, "its art swapped for the near-black track")
Equal(InsetBy(healthArt, health, 0), true, "fitted to the bar")
Equal(S[Piece(health, "BACKGROUND", -8)].color[1] == 0 and S[Piece(health, "OVERLAY", -8)].shown, true, "Glass: a black edge and a shine")
Equal(S[health].barColour[2] == 1 and S[health].barColour[1], 0, "Blizzard's green kept by default")
Equal(S[prd.AlternatePowerBar].alpha, 0, "the second mana bar hides while the main bar is mana")
power = 3
prd:UpdatePowerBar()
Equal(S[prd.AlternatePowerBar].alpha, 1, "and shows in cat form")
Equal(S[prd.AlternatePowerBar].height, 6, "half as tall there")
prd:SetPowerBarHeight(20)
Equal(S[prd.PowerBar].height == 20 and S[prd.AlternatePowerBar].height, 10, "still half after Edit Mode changes the bars")
power = 0
prd:UpdateAlternatePowerBar()
Equal(S[prd.AlternatePowerBar].alpha == 0 and S[prd.AlternatePowerBar].height, 20, "hidden again in caster form, at full height")
-- Blizzard recolours the power bar as your power changes; Default follows it.
prd.PowerBar:SetStatusBarColor(1, 1, 0)
Equal(S[prd.PowerBar].barColour[1] == 1 and S[prd.PowerBar].barColour[2], 1, "Blizzard's energy yellow kept")
ns.Set("prdPower", "purple")
ns.Resource:Apply()
Equal(S[prd.PowerBar].barColour[1] == .6 and S[prd.AlternatePowerBar].barColour[1], .6, "your own colour instead, on both power bars")
prd.PowerBar:SetStatusBarColor(0, 0, 1)
Equal(S[prd.PowerBar].barColour[1], .6, "and it stays when Blizzard recolours")
ns.Set("barStyle", "outline")
ns.Resource:Apply()
Equal(S[prd.PowerBar].barColour[4], .45, "Outline: a see-through fill")
Equal(S[Piece(prd.PowerBar, "BACKGROUND", -8)].color[1], .6, "inside an edge in its colour")
ns.Set("prdHideRepeat", false)
ns.Resource:Apply()
Equal(S[prd.AlternatePowerBar].alpha, 1, "the repeat bar can stay")
power = 3
prd:UpdatePowerBar()
Equal(S[prd.AlternatePowerBar].height, 20, "at full size in forms too")
power = 0
Equal(#printed, 0, "no errors")

-- Restyle off: Blizzard's bars untouched, but the repeat mana bar still hides.
Environment()
Viewers(0)
_G.UnitPowerType = function() return power end
prd = PRD()
_G.PersonalResourceDisplayFrame = prd
ns = Load({ prdSkin = false })
Equal(S[prd.PowerBar].barTexture, nil, "restyle off: Blizzard's own bars")
Equal(S[prd.AlternatePowerBar].alpha, 0, "the repeat bar still hides")

-- Blizzard loads the display once it's switched on.
Environment()
Viewers(0)
_G.UnitPowerType = function() return power end
ns = Load(nil)
prd = PRD()
_G.PersonalResourceDisplayFrame = prd
Fire("ADDON_LOADED", "Blizzard_PersonalResourceDisplay")
Equal(S[prd.PowerBar].barTexture, "Interface\\Buttons\\WHITE8X8", "restyled once Blizzard loads it")
Equal(#printed, 0, "no errors from the display")

-- A layout can make the display as wide as your widest row: only the widths
-- its own Bar Width setting changes, never in combat, and Blizzard's back after.
function Proto:GetEffectiveScale() return 1 end
Environment()
Viewers(0)
_G.UnitPowerType = function() return power end
_G.UIParent = New("Frame")
prd = PRD()
_G.PersonalResourceDisplayFrame = prd
ns = Load(nil)
local wanted
ns.Layout = {
    MatchWidth = function() return wanted end,
    Active = function() return wanted ~= nil end,
    Stack = function() ns.Resource:Match() end,
}
local function Widths()
    local list = {}
    for _, part in ipairs({ prd, prd.HealthBarsContainer, prd.PowerBar, prd.AlternatePowerBar, prd.ClassFrameContainer }) do
        list[#list + 1] = string.format("%g", S[part].width or 0)
    end
    return table.concat(list, ",")
end
wanted = 300
ns.Resource:Match()
Equal(Widths(), "300,300,300,300,300", "the display and its bars as wide as the rows")
prd:UpdateBarWidth()
Equal(Widths(), "300,300,300,300,300", "and again after Blizzard sets its own width")
combat = true
wanted = 340
ns.Resource:Match()
Equal(Widths() .. " " .. tostring(ns.Resource.pendingMatch), "300,300,300,300,300 true", "never in combat")
combat = false
ns.Resource:Match()
Equal(Widths(), "340,340,340,340,340", "done once it's over")
wanted = nil
ns.Resource:Match()
Equal(Widths(), "200,200,200,200,200", "Blizzard's own width back when it stops")
Equal(#printed, 0, "no errors while matching")

print = _G.print
io.write("Forever Enhanced Cooldown Manager checks passed: " .. checks .. " assertions.\n")
