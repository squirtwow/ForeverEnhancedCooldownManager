-- Run the actual addon files against mock copies of Blizzard's cooldown viewer
-- frames, built from Blizzard_CooldownViewer's CooldownViewer.xml. Blizzard's
-- frames are sealed: writing any key on them, or calling anything that shows,
-- hides, scales or reads them, fails the test. The only size changes allowed
-- are a Tracked Bar's own status bar height, inside its unchanged item frame,
-- the height of the Personal Resource Display's extra mana bar, and the
-- display's width while a layout matches it to your rows (the widths its own
-- Bar Width setting changes). The one read allowed is whether the display's
-- bars show, to put the addon's combo points under the lowest.
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
    SetTexture = true, SetFrameLevel = true,
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
                if S[obj].blizzard and FORBIDDEN[key] and not (key == "IsShown" and S[obj].readable) then
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
function Proto:SetMinMaxValues(low, high) S[self].range = low .. "-" .. high end
function Proto:SetValue(value) S[self].value = value end
function Proto:GetHeight() return S[self].height end
function Proto:GetStatusBarColor() local c = S[self].barColour or { 1, 1, 1, 1 }; return c[1], c[2], c[3], c[4] end
function Proto:SetAtlas(atlas) S[self].atlas = atlas end
function Proto:SetWidth(w)
    if S[self].blizzard and not S[self].resizable then error("resized a Blizzard frame", 2) end
    S[self].width = w
end
function Proto:SetFontObject(o) S[self].font = o end
function Proto:SetWordWrap(v) S[self].wordWrap = v end
function Proto:SetCountdownFont(o) S[self].countdownFont = o end
-- The addon's own fonts: the face each one is set in.
function Proto:SetFont(file, size, flags) S[self].face = file .. " " .. size .. " " .. flags end
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
function Proto:HookScript(key, fn)
    local old = S[self].scripts[key]
    S[self].scripts[key] = function(...) if old then old(...) end fn(...) end
end
function Proto:RegisterEvent(e) S[self].events[e] = true end
function Proto:RegisterUnitEvent(e, unit) S[self].events[e] = unit end
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

-- Keybinds: levels are read on Blizzard's frames and only set on the addon's
-- own (SetFrameLevel is forbidden on Blizzard's).
function Proto:GetFrameLevel() return S[self].level or 1 end
function Proto:SetFrameLevel(level) S[self].level = level end
function Proto:EnableMouse(v) S[self].mouse = v end
function Proto:SetJustifyH(h) S[self].justify = h end
-- The trinket slot Blizzard's settings give a cooldown icon.
function Proto:GetEquipSlot() return S[self].equipSlot end
-- A cooldown's countdown numbers, Blizzard's own when the cooldown is.
function Proto:GetCountdownFontString()
    local s = S[self]
    if not s.numbers then
        s.numbers = New("FontString", self, s.blizzard)
        if s.sealed then Seal(s.numbers) end
    end
    return s.numbers
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
-- Blizzard's own refreshes, run by the test as the game would. The addon may
-- only post-hook them, never call them itself.
local blizzardCalling = false
local function Blizzard(viewer, method)
    blizzardCalling = true
    viewer[method](viewer)
    blizzardCalling = false
end
local function Viewer(name, make, preexisting)
    local viewer = New("Frame")
    local active = {}
    for i = 1, preexisting do active[make()] = true end
    viewer.itemFramePool = { EnumerateActive = function() return pairs(active) end }
    viewer.OnAcquireItemFrame = function(self, item) acquired[item] = (acquired[item] or 0) + 1 end
    viewer.make = make
    viewer.RefreshLayout = function() assert(blizzardCalling, "called RefreshLayout on a Blizzard viewer") end
    viewer.RefreshData = function() assert(blizzardCalling, "called RefreshData on a Blizzard viewer") end
    Seal(viewer)
    S[viewer.itemFramePool] = nil
    return viewer, active
end

-- Game environment ------------------------------------------------------------------

local frames, printed, reloads, combat, cvarOn
local bindings
local cvars = {} -- the game's own settings (the addon keeps none of its own there)

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
    _G.wipe = function(t) for k in pairs(t) do t[k] = nil end return t end
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
    assert(loadfile("Keybinds.lua"))("ForeverEnhancedCooldownManager", ns)
    assert(loadfile("Resource.lua"))("ForeverEnhancedCooldownManager", ns)
    assert(loadfile("CastBar.lua"))("ForeverEnhancedCooldownManager", ns)
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
Equal(SlashCmdList.FECM ~= nil and SLASH_FECM1, "/ccm", "/ccm opens the settings")
Equal(SLASH_FECM2, "/fecm", "/fecm still works")
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
Equal(S[bar.Bar.Name].wordWrap, false, "a long name stays on one line, cut short, as in Blizzard's look")

ns.Set("barStyle", "split")
ns.Skin:ApplyBarLook()
Equal(S[sheen].shown == false and S[box].shown, true, "Split: a dark box instead of the shine")
local at = S[bar.Bar.Duration].points[1]
Equal(at[1] == "CENTER" and at[2], box, "the time centred in it")
Equal(S[bar.Bar.Name].points[2][2], box, "the name stops before it")
Equal(S[bar.Bar.Name].wordWrap, false, "still on one line")
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

-- The bar texture picked on the Look page, a cosmetic setter on Blizzard's
-- bars, only set again when it changes; and the font picked, which the
-- addon's own fonts take, so Blizzard's countdowns and bar text change with
-- nothing set on Blizzard's frames again.
local RAID, FLAT = "Interface\\RaidFrame\\Raid-Bar-Hp-Fill", "Interface\\Buttons\\WHITE8X8"
local textures = 0
local SetTexture = Proto.SetStatusBarTexture
function Proto:SetStatusBarTexture(t)
    textures = textures + 1
    SetTexture(self, t)
end
ns.Set("barTexture", "raid")
ns.Skin:ApplyBarLook()
Equal(S[bar.Bar].barTexture, RAID, "the texture picked, on Blizzard's Tracked Bars")
local before = textures
ns.Skin:ApplyBarLook()
bar:OnCooldownIDSet()
Equal(textures, before, "not set again while it stays the same, even as Blizzard gives the bar a new spell")
ns.Set("barTexture", "flat")
ns.Skin:ApplyBarLook()
Equal(S[bar.Bar].barTexture, FLAT, "flat again")
Proto.SetStatusBarTexture = SetTexture
Equal(S[_G.FECMFont25].face .. " | " .. S[_G.FECMFont13].face, "Fonts\\FRIZQT__.TTF 25 THICKOUTLINE | Fonts\\FRIZQT__.TTF 13 OUTLINE",
    "Friz Quadrata to start with")
ns.Set("font", "skurri")
ns.Style:ApplyFont()
Equal(S[_G.FECMFont25].face .. " | " .. S[_G.FECMFont13].face .. " | " .. S[item.Cooldown].countdownFont .. " " .. S[bar.Bar.Name].font,
    "Fonts\\skurri.ttf 25 THICKOUTLINE | Fonts\\skurri.ttf 13 OUTLINE | FECMFont25 FECMFont13",
    "a new font: Blizzard's countdowns and bar text keep their fonts, which take it")
ns.Set("font", "friz")
ns.Style:ApplyFont()
Equal(S[_G.FECMFont25].face, "Fonts\\FRIZQT__.TTF 25 THICKOUTLINE", "and back")

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
    Equal(keys, 4, "viewer holds only its pool and its own acquire, layout and refresh functions, hooked")
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

-- Saved settings -------------------------------------------------------------------------
-- Kept in the addon's saved settings only; nothing goes into the game's own.

Environment()
Viewers(0)
ns = Load(nil)
ns.Set("skin", false)
ns.Set("accent", "teal")
ns.SetBarColour(467, "blue")
ns.SetBarColour(1126, "class")
Equal(next(cvars), nil, "no game settings written")

-- A reload keeps them.
local saved = ForeverEnhancedCooldownManagerDB
Environment(true)
v = Viewers(1)
ns = Load(saved)
Equal(ns.Get("skin"), false, "the choice kept over a reload")
Equal(ns.Skin.started, nil, "so the charcoal look stays off")
Equal(ns.Get("accent"), "teal", "accent kept too")
Equal(ns.BarColours()[467] == "blue" and ns.BarColours()[1126], "class", "and each bar's own colour")

-- A lost settings file starts afresh: game settings an earlier build kept
-- are never read, under either name.
Environment()
cvars.FECMBackup = "skin=0;accent=teal"
cvars.ClassicCooldownManagerBackup = "accent=teal;classicBars=1;classicLook=0;listItems=1"
cvars.ClassicCooldownManagerBackupBars0 = "1"
cvars.ClassicCooldownManagerBackupBars1 = "cd.size=40;cd.spells=Moonfire|Bash"
Viewers(0)
ns = Load(nil)
Equal(tostring(ns.firstInstall) .. " " .. tostring(ns.Get("skin")) .. " " .. tostring(ns.Get("useBars")) .. " " .. ns.Get("accent"),
    "true true false orange", "defaults, as a first install")
Equal(#ns.BarData("cd").spells .. " " .. ns.BarData("cd").size, "0 36", "with empty bars")
Equal(#printed, 0, "and nothing to say")

-- Anything unexpected in the saved settings is ignored.
ForeverEnhancedCooldownManagerDB.accent = "pink"
Equal(ns.Get("accent"), "orange", "an invalid saved accent reads as the default")
ForeverEnhancedCooldownManagerDB.barColours = { [467] = "pink", [0] = "blue", foo = "green", [1126] = "green" }
local kept = 0
for _ in pairs(ns.BarColours()) do kept = kept + 1 end
Equal(kept == 1 and ns.BarColours()[1126], "green", "only real spells with a real colour are kept")
ns.SetBarColour("Thorns", "blue")
ns.SetBarColour(467, "pink")
Equal(ns.BarColours()[467], nil, "nothing else can be set")

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
    for _, part in ipairs({ container, frame.PowerBar, frame.AlternatePowerBar }) do S[part].readable = true end
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
Equal(ns.Resource:ExtraHidden(), true, "a layout leaves no room for it then")
power = 3
prd:UpdatePowerBar()
Equal(S[prd.AlternatePowerBar].alpha, 1, "and shows in cat form")
Equal(ns.Resource:ExtraHidden(), false, "where it takes its room")
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
-- The bar texture picked on the Look page, and still only set when it changes
-- as Blizzard recolours the bars.
ns.Set("barTexture", "skills")
ns.Resource:Apply()
local SKILLS = "Interface\\PaperDollInfoFrame\\UI-Character-Skills-Bar"
Equal(S[health].barTexture .. " " .. S[prd.PowerBar].barTexture .. " " .. S[prd.AlternatePowerBar].barTexture,
    SKILLS .. " " .. SKILLS .. " " .. SKILLS, "the texture picked, on the display's bars")
local fills = 0
local SetFill = Proto.SetStatusBarTexture
function Proto:SetStatusBarTexture(t)
    fills = fills + 1
    SetFill(self, t)
end
prd.PowerBar:SetStatusBarColor(0, 0, 1)
ns.Resource:Apply()
Equal(fills .. " " .. S[prd.PowerBar].barTexture, "0 " .. SKILLS, "not set again while it stays the same")
Proto.SetStatusBarTexture = SetFill
ns.Set("barTexture", "flat")
ns.Resource:Apply()
Equal(S[health].barTexture, "Interface\\Buttons\\WHITE8X8", "flat again")
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

-- Combo points under the display: the addon's own, since Forever's display
-- has none. Off by default.
Environment()
Viewers(0)
power = 3
_G.UnitPowerType = function() return power end
local points = 2
_G.UnitPower = function(unit, kind) assert(unit == "player" and kind == 4, "your combo points"); return points end
prd = PRD()
_G.PersonalResourceDisplayFrame = prd
ns = Load(nil)
Equal(ns.Resource:ComboRow(), nil, "off unless you tick it")
ns.Set("prdCombo", true)
ns.Resource:Apply()
local row = ns.Resource:ComboRow()
Equal(row ~= nil and S[row].shown, true, "ticked, a druid in cat form gets them")
local top = S[row].points[1]
Equal(top[1] .. " " .. tostring(top[2] == prd.AlternatePowerBar) .. " " .. top[3] .. " " .. top[5], "TOPLEFT true BOTTOMLEFT -4",
    "under the lowest bar, Blizzard's padding apart")
Equal(S[row].points[2][1] .. " " .. S[row].points[2][3] .. " " .. S[row].height, "TOPRIGHT BOTTOMRIGHT 12",
    "as wide as the display, whatever its width, and as tall as the power bar")
local segments = S[row].children
local ranges, values = {}, {}
for i, bar in ipairs(segments) do ranges[i], values[i] = S[bar].range, tostring(S[bar].value) end
Equal(#segments .. " " .. table.concat(ranges, ","), "5 0-1,1-2,2-3,3-4,4-5", "five segments, one point each")
Equal(table.concat(values, ","), "2,2,2,2,2", "each handed the count as it is: the game fills the first two")
Equal(S[segments[1]].barTexture .. " " .. S[segments[1]].barColour[1], "Interface\\Buttons\\WHITE8X8 0.87", "flat, in red to start with")
points = 4
Fire("UNIT_POWER_FREQUENT", "player")
Equal(S[segments[5]].value, 4, "they follow your points")
ns.Set("prdComboColour", "blue")
ns.Set("barStyle", "outline")
ns.Resource:Apply()
Equal(S[segments[1]].barColour[1] == ns.Style:BarColour("blue")[1] and S[segments[1]].barColour[4], .45,
    "your colour, in the design you picked")
ns.Set("barTexture", "classic")
ns.Resource:Apply()
Equal(S[segments[1]].barTexture .. " " .. S[segments[5]].barTexture, "Interface\\TargetingFrame\\UI-StatusBar Interface\\TargetingFrame\\UI-StatusBar",
    "and the texture you picked")
ns.Set("barTexture", "flat")
ns.Resource:Apply()
-- Caster form: gone, and back in cat form.
power = 0
Fire("UPDATE_SHAPESHIFT_FORM")
Equal(tostring(ns.Resource:ComboRow()) .. " " .. tostring(S[row].shown), "nil false", "gone out of cat form")
power = 3
Fire("UPDATE_SHAPESHIFT_FORM")
Equal(S[row].shown, true, "back in cat form")
-- A rogue has no extra mana bar: straight under the energy bar.
S[prd.AlternatePowerBar].shown = false
prd:UpdatePowerBar()
Equal(S[row].points[1][2] == prd.PowerBar, true, "under the energy bar when it's the lowest")
Equal(#printed, 0, "no errors from the combo points")

-- Your cast bar: Blizzard's own is only made invisible while yours is on,
-- never moved, hidden or written on, and gets its alpha back after.
Environment()
Viewers(0)
_G.UnitCastingInfo = function() return nil end
_G.UnitChannelInfo = function() return nil end
_G.GetTime = function() return 0 end
local castingBar = New("StatusBar")
S[castingBar].alpha = 1
-- The hold-and-fade Blizzard plays on an interrupt, as an animation group.
local hold = New("AnimationGroup")
castingBar.HoldFadeOutAnim = hold
castingBar.PlayInterruptAnims = function(self) self.HoldFadeOutAnim:Play() end
Seal(castingBar)
_G.PlayerCastingBarFrame = castingBar
ns = Load({ castBar = true })
Equal(S[castingBar].alpha, 0, "Blizzard's cast bar invisible while yours is on")
castingBar:SetAlpha(1)
Equal(S[castingBar].alpha, 0, "and still, when Blizzard shows it for a cast")
castingBar:PlayInterruptAnims()
Equal(S[hold].calls.Play .. " " .. S[hold].calls.Stop .. " " .. S[castingBar].alpha, "1 1 0",
    "its interrupt hold-and-fade is stopped as Blizzard starts it, so it can't show it")
ns.Set("castBar", false)
ns.CastBar:Apply()
Equal(S[castingBar].alpha, 0, "yours off between casts: Blizzard's stays out of sight until it casts")
castingBar:SetAlpha(1)
Equal(S[castingBar].alpha, 1, "then shows as normal")
castingBar:PlayInterruptAnims()
Equal(S[hold].calls.Play .. " " .. S[hold].calls.Stop, "2 1", "and its interrupt plays as normal")
Equal(#printed, 0, "no errors from the cast bar")
_G.PlayerCastingBarFrame = nil

-- Borders and shadows on Blizzard's icons: the addon's own textures, round
-- each icon's art or round each icon row, nothing written on Blizzard's frames.
Environment()
v = Viewers(1)
ns = Load({ iconBorder = "icon", iconShadow = "bar" })
item = First(v.essentialActive)
local decor, row = ns.Skin.decors[item], ns.Skin.rows.EssentialCooldownViewer
local utilityRow = ns.Skin.rows.UtilityCooldownViewer
Equal(tostring(S[row.shadow[1][1]].shown) .. " " .. tostring(S[utilityRow.shadow[1][1]].shown), "false false",
    "no box round an empty row")
rawset(item, "cooldownID", 7)
ns.Skin:ApplyDecor()
Equal(tostring(S[decor.border[1]].shown) .. " " .. tostring(S[decor.shadow[1][1]].shown), "true false", "a border round each icon")
local buffIcon = First(v.buffsActive)
Equal(tostring(S[ns.Skin.decors[buffIcon].border[1]].shown), "true", "tracked buff icons too")
Equal(tostring(S[row.border[1]].shown) .. " " .. tostring(S[row.shadow[1][1]].shown), "false true", "a shadow round the whole row")
local edge = S[decor.border[1]].points[1]
Equal(edge[1] .. " " .. tostring(edge[2] == item.Icon) .. " " .. edge[4] .. " " .. edge[5], "BOTTOMLEFT true -1 0",
    "the border right on the icon art's edge")
local rowEdge = S[row.shadow[1][1]].points[1]
Equal(rowEdge[4] .. " " .. rowEdge[5], "1 -2", "the row's shadow from its icons' edge, inside Blizzard's frame")
Equal(tostring(ns.Skin.rows.BuffBarCooldownViewer) .. " " .. tostring(ns.Skin.rows.BuffIconCooldownViewer), "nil nil",
    "the Tracked Bars keep their own edges, and Tracked Buffs (which come and go) only get them per icon")
rawset(item, "cooldownID", nil)
Blizzard(v.essential, "RefreshLayout")
Equal(tostring(S[row.shadow[1][1]].shown), "false", "emptied, its row loses the box when Blizzard lays it out")
rawset(item, "cooldownID", 7)
Blizzard(v.essential, "RefreshLayout")
-- Cooldown Settings going between none, one and two cooldowns only refreshes
-- the row in place (Blizzard keeps two items): the box follows at once.
ns.Set("iconBorder", "bar")
ns.Skin:ApplyDecor()
rawset(item, "cooldownID", nil)
Blizzard(v.essential, "RefreshData")
Equal(tostring(S[row.border[1]].shown) .. " " .. tostring(S[row.shadow[1][1]].shown), "false false",
    "emptied in Cooldown Settings, the box goes with no relayout")
rawset(item, "cooldownID", 7)
Blizzard(v.essential, "RefreshData")
Equal(tostring(S[row.border[1]].shown) .. " " .. tostring(S[row.shadow[1][1]].shown), "true true", "and comes back when one is added")
-- One cooldown and Blizzard's empty second item: the box goes round the one
-- icon, not the empty slot.
local spare = CooldownItem()
v.essential:OnAcquireItemFrame(spare)
v.essentialActive[spare] = true
Blizzard(v.essential, "RefreshData")
local top = S[row.border[1]].points[1]
Equal(tostring(top[2] == item.Icon) .. " " .. top[4] .. " " .. top[5], "true -1 0", "one cooldown: the border round its icon art")
Equal(tostring(S[row.shadow[1][1]].points[1][2] == item.Icon) .. " " .. tostring(S[row.shadow[1][1]].shown), "true true", "and the shadow")
-- A cooldown the game keeps secret still counts as one.
_G.issecretvalue = function(value) return value == SECRET end
rawset(spare, "cooldownID", SECRET)
Blizzard(v.essential, "RefreshLayout")
top = S[row.border[1]].points[1]
Equal(tostring(top[2] == v.essential) .. " " .. top[4] .. " " .. top[5], "true 1 -2", "two cooldowns, one secret: round the whole row again")
_G.issecretvalue = nil
rawset(spare, "cooldownID", nil)
v.essentialActive[spare] = nil
ns.Set("iconBorder", "icon")
ns.Set("iconShadow", "icon")
ns.Skin:ApplyDecor()
local first = S[decor.shadow[1][1]]
Equal(tostring(first.shown) .. " " .. first.points[1][4] .. " " .. tostring(S[row.shadow[1][1]].shown), "true -2 false",
    "shadow round each icon now, starting outside its border")
ns.Set("iconBorder", "off")
ns.Set("iconShadow", "off")
ns.Skin:ApplyDecor()
Equal(tostring(S[decor.border[1]].shown) .. " " .. tostring(S[decor.shadow[1][1]].shown), "false false", "and off again")
Equal(#printed, 0, "no errors from borders and shadows")

-- Keybinds on Blizzard's Essential and Utility icons: the addon's own text on
-- its own frame, Blizzard's charge count and countdown only moved while a key
-- needs them moved, and nothing written on Blizzard's frames.
do
    local slots, keyOf = {}, {}
    -- The game as Keybinds.lua reads it: your action bars, bindings, spell
    -- names and trinket.
    local function Game()
        _G.C_Timer = { After = function(_, fn) fn() end }
        _G.GetActionInfo = function(slot) local a = slots[slot]; if a then return a[1], a[2], a[3] end end
        _G.GetBindingKey = function(binding) return keyOf[binding] end
        _G.C_Spell = { GetSpellName = function(id) return ({ [8921] = "Moonfire", [8924] = "Moonfire", [5176] = "Wrath" })[id] end }
        _G.GetInventoryItemID = function(_, slot) if slot == 13 then return 5079 end end
        _G.issecretvalue = function(value) return value == SECRET end
    end
    local function At(region, anchor)
        local p = S[region].points[1]
        return p[1] .. " " .. tostring(p[2] == anchor) .. " " .. p[3] .. " " .. p[4] .. " " .. p[5]
    end

    Environment()
    local views = Viewers(1)
    Game()
    local essential, utility = First(views.essentialActive), First(views.utilityActive)
    S[essential.Cooldown].level, S[essential.ChargeCount].level, S[essential].baseSpell = 3, 4, 8924
    S[utility].equipSlot = 13
    slots[1], keyOf.ACTIONBUTTON1 = { "spell", 8921 }, "SHIFT-1"
    slots[2], keyOf.ACTIONBUTTON2 = { "item", 5079 }, "2"
    local kns = Load({ keybinds = true })
    kns.Keybinds:Update()
    local parts, small = kns.Skin.keys[essential], kns.Skin.keys[utility]
    local text, frame = parts.text, parts.frame
    Equal(S[text].text .. " " .. tostring(S[text].shown), "S1 true", "Blizzard's icon shows the key that casts its spell, whichever rank")
    Equal(tostring(S[frame].parent == essential) .. " " .. tostring(S[frame].sealed) .. " " .. S[frame].level .. " " .. tostring(S[frame].mouse),
        "true nil 6 false", "on the addon's own frame, above Blizzard's sweep and count, never taking the mouse")
    Equal(S[text].parent == frame, true, "in the addon's own text")
    Equal(At(text, frame) .. " " .. S[text].font .. " " .. S[text].width, "BOTTOM true BOTTOM 0 2 FECMFont14 42",
        "along the bottom of the art, sized to the icon")
    Equal(At(essential.ChargeCount.Current, essential.ChargeCount) .. " | " .. At(S[essential.Cooldown].numbers, essential.Cooldown),
        "TOPRIGHT true TOPRIGHT -2 -2 | CENTER true CENTER 0 0", "the charge count goes top right; the countdown has room")
    Equal(S[small.text].text .. " " .. S[small.text].font .. " " .. At(S[utility.Cooldown].numbers, utility.Cooldown),
        "2 FECMFont8 CENTER true CENTER 0 2", "a trinket's key on a Utility icon, its countdown moved up clear of it")

    local function Count(item) return At(item.ChargeCount.Current, item.ChargeCount) end

    -- Pooled items change spell: the key follows, and the count with it.
    S[essential].baseSpell = 5176
    essential:OnCooldownIDSet()
    Equal(tostring(S[text].shown) .. " " .. Count(essential), "false BOTTOMRIGHT true BOTTOMRIGHT -2 2",
        "given a spell with no key: none, and its charge count back where Blizzard puts it")
    S[essential].baseSpell = 8924
    essential:OnCooldownIDSet()
    Equal(S[text].text .. " " .. tostring(S[text].shown) .. " " .. Count(essential), "S1 true TOPRIGHT true TOPRIGHT -2 -2",
        "given one with a key: shown at once, the count up clear of it")
    -- Blizzard's pool takes it back and empties it without OnCooldownIDCleared
    -- (ResetCooldownData), then hands it out again as an Edit Mode placeholder:
    -- ClearCooldownID fires nothing on an item already empty.
    S[essential].baseSpell = nil
    views.essential:OnAcquireItemFrame(essential)
    Equal(tostring(S[text].shown) .. " " .. #printed, "false 0", "handed out again as an empty placeholder: the old key goes")
    S[essential].baseSpell = 8924
    essential:OnCooldownIDSet()
    Equal(S[text].text .. " " .. tostring(S[text].shown), "S1 true", "and comes back when Blizzard gives it a spell")
    S[utility].equipSlot = nil
    views.utility:OnAcquireItemFrame(utility)
    Equal(tostring(S[small.text].shown) .. " " .. Count(utility), "false BOTTOMRIGHT true BOTTOMRIGHT -2 2",
        "a trinket's Utility icon handed out again empty: no key either, its count at the bottom")
    S[utility].equipSlot = 13
    utility:OnCooldownIDSet()
    Equal(S[small.text].text .. " " .. tostring(S[small.text].shown) .. " " .. Count(utility), "2 true TOPRIGHT true TOPRIGHT -2 -2",
        "and back with its trinket, its count up")
    S[essential].baseSpell = nil
    essential:OnCooldownIDCleared()
    Equal(tostring(S[text].shown), "false", "cleared, as for Edit Mode's placeholders: gone")

    -- A spell kept secret in a fight: nothing until it's over.
    combat = true
    S[essential].baseSpell = SECRET
    essential:OnCooldownIDSet()
    Equal(tostring(S[text].shown) .. " " .. #printed .. " " .. Count(essential), "false 0 BOTTOMRIGHT true BOTTOMRIGHT -2 2",
        "a secret spell in a fight: no key, no error, the count at the bottom")
    combat = false
    S[essential].baseSpell = 8924
    Fire("PLAYER_REGEN_ENABLED")
    Equal(S[text].text .. " " .. tostring(S[text].shown), "S1 true", "its key once the fight is over")

    -- A key changed in a fight is read once it's over.
    combat = true
    keyOf.ACTIONBUTTON1 = "3"
    Fire("UPDATE_BINDINGS")
    Equal(S[text].text .. " " .. tostring(kns.Keybinds.pending), "S1 true", "a key changed in a fight waits")
    combat = false
    Fire("PLAYER_REGEN_ENABLED")
    Equal(S[text].text, "3", "and shows once it's over")
    -- Unbound and bound again: Blizzard's count follows the key at once.
    keyOf.ACTIONBUTTON1 = nil
    Fire("UPDATE_BINDINGS")
    Equal(tostring(S[text].shown) .. " " .. Count(essential), "false BOTTOMRIGHT true BOTTOMRIGHT -2 2",
        "a key unbound: Blizzard's count back down")
    keyOf.ACTIONBUTTON1 = "3"
    Fire("UPDATE_BINDINGS")
    Equal(S[text].text .. " " .. Count(essential), "3 TOPRIGHT true TOPRIGHT -2 -2", "bound again: up")

    -- Top right: Blizzard's count goes back where it puts it.
    kns.Set("keybindPosition", "TOPRIGHT")
    kns.Skin:ApplyKeybinds()
    Equal(At(text, frame) .. " " .. S[text].justify, "TOPRIGHT true TOPRIGHT -2 -2 RIGHT", "top right")
    Equal(At(essential.ChargeCount.Current, essential.ChargeCount) .. " | " .. At(S[utility.Cooldown].numbers, utility.Cooldown),
        "BOTTOMRIGHT true BOTTOMRIGHT -2 2 | CENTER true CENTER 0 -2", "the count back where Blizzard puts it; a small icon's countdown moved down")

    -- Off: no keys, and Blizzard's count and countdown back home.
    kns.Set("keybinds", false)
    kns.Keybinds:Update()
    kns.Skin:ApplyKeybinds()
    Equal(tostring(S[text].shown) .. " " .. tostring(S[small.text].shown), "false false", "off: no keys")
    Equal(At(utility.ChargeCount.Current, utility.ChargeCount) .. " | " .. At(S[essential.Cooldown].numbers, essential.Cooldown)
        .. " | " .. At(S[utility.Cooldown].numbers, utility.Cooldown),
        "BOTTOMRIGHT true BOTTOMRIGHT -2 2 | CENTER true CENTER 0 0 | CENTER true CENTER 0 0", "and Blizzard's count and countdown back home")

    -- Only cooldown icons get keys, and nothing is written on Blizzard's frames.
    Equal(tostring(kns.Skin.keys[First(views.buffsActive)]) .. " " .. tostring(kns.Skin.keys[First(views.barsActive)]), "nil nil",
        "Tracked Buffs and Tracked Bars get none")
    local held = 0
    for _ in pairs(essential) do held = held + 1 end
    Equal(held, 7, "Blizzard's icon holds only its own parts and the two hooks")
    for _, viewer in ipairs({ views.essential, views.utility, views.buffs, views.bars }) do
        local count = 0
        for name in pairs(viewer) do if name ~= "make" then count = count + 1 end end
        Equal(count, 4, "each viewer still holds only its own four")
    end
    Equal(#printed, 0, "no errors from keybinds")

    -- Off from login: Blizzard's count and countdown are never touched.
    Environment()
    views = Viewers(1)
    Game()
    kns = Load(nil)
    essential = First(views.essentialActive)
    Equal(#S[essential.ChargeCount.Current].points .. " " .. tostring(S[essential.Cooldown].numbers) .. " "
        .. tostring(S[kns.Skin.keys[essential].text].shown), "0 nil false", "off from login: nothing moved, no key")

    -- Without the look, Blizzard's icons get no keys, and nothing breaks.
    Environment()
    Viewers(1)
    Game()
    kns = Load({ skin = false, keybinds = true })
    local ok = pcall(kns.Keybinds.Update, kns.Keybinds)
    Equal(tostring(next(kns.Skin.keys)) .. " " .. tostring(ok) .. " " .. #printed, "nil true 0", "the look off: no keys on Blizzard's icons, no errors")
    _G.issecretvalue = nil
end

print = _G.print
io.write("Forever Enhanced Cooldown Manager checks passed: " .. checks .. " assertions.\n")
