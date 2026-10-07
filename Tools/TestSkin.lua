-- Run the actual addon files against mock copies of Blizzard's cooldown viewer
-- frames, built from Blizzard_CooldownViewer's CooldownViewer.xml. Blizzard's
-- frames are sealed: writing any key on them or a viewer's item pool (even
-- one already there), calling anything that shows, hides, scales or reads them, setting their
-- scripts, events, mouse or strata, moving or fading a whole icon or viewer,
-- or calling any of Blizzard's own methods, fails the test. The only size changes allowed
-- are a Tracked Bar's own status bar height, inside its unchanged item frame,
-- the height of the Personal Resource Display's extra mana bar, and the
-- display's width while a layout matches it to your rows (the widths its own
-- Bar Width setting changes). The one read allowed is whether the display's
-- bars show, to put the addon's combo points under the lowest. Raid Timers
-- follow the same rules on Blizzard's countdown (TimerTracker), raid warnings
-- (RaidWarningFrame) and boss cast bars: only the cosmetic setters each part
-- allows, never their text, nothing that shows or hides them, and never the
-- private boss emote anchor or the deadly debuff frame. Only the art the look
-- replaces may be made see-through (and a boss bar's fill while Edit Mode
-- shows it with no cast), and only the countdown's time may be moved (into
-- Split's box, and back). Sizes: the one approved exception to never scaling
-- Blizzard's frames is the countdown, its bar and its two big digits (never
-- the timer frame, the glow or the logo); raid warning lines may only have
-- their text height set, as Blizzard's times yours. Nothing is scaled or
-- sized at 100%, and the boss frames and their cast bars never are.
local checks = 0
-- Also fails on a secret the addon misused since the last check (below),
-- even one its own pcall kept quiet, and on a widget method Forever lacks
-- that the addon looked for.
local function Equal(actual, expected, label)
    checks = checks + 1
    if SecretMisuse[1] then error(label .. ": the addon misused a secret before this check: " .. SecretMisuse[1], 2) end
    if WidgetMisses[1] then error(label .. ": the addon looked for a method Forever lacks before this check: " .. WidgetMisses[1], 2) end
    assert(rawequal(actual, expected) or actual == expected, label .. ": expected " .. tostring(expected) .. ", got " .. tostring(actual))
end

-- Secrets, as the game keeps them in a fight (the same as Tools/TestBars.lua's
-- mock game): when the addon's own code compares one, does sums with it,
-- indexes, calls, measures or iterates it, joins it into text or turns it
-- into text, it errors, and is noted (SecretMisuse) so a pcall can't hide
-- it; type() says "number", so only an issecretvalue check gets past one.
-- The mock and the tests are the game's own code here, so they may look.
do
    local rawtype, kinds = type, setmetatable({}, { __mode = "k" })
    local function Addon()
        for level = 3, 40 do
            local info = debug.getinfo(level, "Sl")
            if not info then return nil end
            if info.what ~= "C" and info.what ~= "J" then
                local source = info.source or ""
                if source:sub(1, 1) == "@" and not source:find("Tools", 1, true) then
                    return source:sub(2) .. ":" .. tostring(info.currentline)
                end
                return nil
            end
        end
    end
    local function Boom(verb, plain)
        return function(a, b)
            local at = Addon()
            if not at then return plain(a, b) end
            local message = "attempt to " .. verb .. " a secret " .. (kinds[a] or kinds[b]) .. " value"
            SecretMisuse[#SecretMisuse + 1] = at .. ": " .. message
            error(message, 2)
        end
    end
    local META = { __metatable = false,
        __index = Boom("index", function() return nil end), __newindex = Boom("index", function() end),
        __call = Boom("call", function() error("the tests called a secret") end),
        __eq = Boom("compare", rawequal), __lt = Boom("compare", function() return false end),
        __le = Boom("compare", function() return false end),
        __concat = Boom("concatenate", function() return "secret" end), __len = Boom("get the length of", function() return 0 end),
        __tostring = Boom("turn into text", function() return "secret" end),
        __pairs = Boom("iterate", function() return next, {}, nil end) }
    for _, op in ipairs({ "add", "sub", "mul", "div", "mod", "pow", "unm", "idiv", "band", "bor", "bxor", "shl", "shr", "bnot" }) do
        META["__" .. op] = Boom("perform arithmetic on", function(a, b) return kinds[a] and a or b end)
    end
    SECRETS = {}
    for _, kind in ipairs({ "number", "boolean", "string" }) do
        SECRETS[kind] = setmetatable({}, META)
        kinds[SECRETS[kind]] = kind
    end
    SecretMisuse = {}
    _G.type = function(v)
        if rawtype(v) == "table" and kinds[v] then return kinds[v] end
        return rawtype(v)
    end
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
    -- A bar's values and a line's text: Blizzard's, and secret in a fight.
    SetValue = true, SetMinMaxValues = true, SetText = true, ClearText = true, SetTextHeight = true,
    SetMaxLines = true, GetNumLines = true, GetStringWidth = true, GetStringHeight = true,
    -- Every other way to size one, besides SetScale, SetSize, SetWidth and SetHeight.
    SetTextScale = true, SetFontHeight = true, SetIgnoreParentScale = true,
    -- Its scripts, events, mouse, strata and secure attributes: Blizzard's own.
    SetScript = true, EnableMouse = true, SetFrameStrata = true, RegisterEvent = true, RegisterUnitEvent = true,
    UnregisterEvent = true, UnregisterAllEvents = true, SetAttribute = true,
}
-- True while Blizzard's own code runs in the test: it may do what the addon may not.
local blizzardCalling = false

-- Like the game (and Tools/TestBars.lua's mock): each kind of widget has
-- only the methods Forever gives it, and its template's
-- (Tools/WidgetMethods.lua). On the addon's own frames any other capitalised
-- name is nil, and one an addon file looks for is noted in WidgetMisses (its
-- file and line), so a call to a method Forever lacks fails the next check.
-- Blizzard's frames also have Lua methods of their own, which the seal above
-- keeps to them; on those, only a widget method of another kind (a status
-- bar's on a plain frame, say) is a miss.
local WidgetHas
do
    local list = dofile("Tools/WidgetMethods.lua")
    local function Into(set, names) for name in names:gmatch("%S+") do set[name] = true end return set end
    local kinds, templates, any = {}, {}, {}
    for kind, apis in pairs(list.kinds) do
        kinds[kind] = {}
        for api in apis:gmatch("%S+") do
            Into(kinds[kind], assert(list.apis[api], api))
            Into(any, list.apis[api])
        end
    end
    for name, names in pairs(list.templates) do templates[name] = Into({}, names) end
    WidgetMisses = {}
    -- The first Lua code up the stack past WidgetHas and the widget's
    -- __index, if it's an addon file's: its file and line. Skin.lua's Read
    -- looks for Blizzard's item getters on purpose, and does without them on
    -- the window's sample Tracked Bar.
    local LOOKS = { ["Skin.lua GetBaseSpellID"] = true, ["Skin.lua GetEquipSlot"] = true }
    local function Addon(key)
        for level = 4, 40 do
            local info = debug.getinfo(level, "Sl")
            if not info then return nil end
            if info.what ~= "C" and info.what ~= "J" then
                local source = info.source or ""
                if source:sub(1, 1) == "@" and not source:find("Tools", 1, true)
                    and not LOOKS[source:sub(2) .. " " .. key] then
                    return source:sub(2) .. ":" .. tostring(info.currentline)
                end
                return nil
            end
        end
    end
    function WidgetHas(s, key)
        local own = assert(kinds[s.kind], "the mock game has no " .. tostring(s.kind) .. " widgets")
        if own[key] or (s.blizzard and (blizzardCalling or not any[key])) then return true end
        for name in (s.frameTemplate or ""):gmatch("[^,%s]+") do
            if assert(templates[name], "the mock game has no " .. name)[key] then return true end
        end
        local at = Addon(key)
        if at then WidgetMisses[#WidgetMisses + 1] = at .. ": Forever has no " .. s.kind .. ":" .. key end
        return false
    end
end

-- Blizzard's own code writing a key on its frames (this test, as the game):
-- kept with a sealed frame's fields, off the frame itself, so a write by the
-- addon always reaches the seal, even over a key that's there already.
local rawset0, rawget0 = rawset, rawget
local function rawset(t, key, value)
    local s = S[t]
    if s and s.fields then s.fields[key] = value else rawset0(t, key, value) end
    return t
end
local function rawget(t, key)
    local s = S[t]
    if s and s.fields then return s.fields[key] end
    return rawget0(t, key)
end

local Proto = {}
local New

-- A method no mock models. On a sealed Blizzard frame only its own code may
-- call one, or the addon where a part allows it: any other (a Blizzard
-- mixin's, say) would run Blizzard's code from the addon's in the game.
local function Fallback(name)
    return function(self)
        local s = S[self]
        if s.sealed and not blizzardCalling and not (s.allow and s.allow[name]) then
            error("called " .. name .. ", which a Blizzard frame keeps to itself", 2)
        end
        if s.blizzard and FORBIDDEN[name] and not blizzardCalling then error("called " .. name .. " on a Blizzard frame", 2) end
        s.calls[name] = (s.calls[name] or 0) + 1
    end
end

New = function(kind, parent, blizzard)
    local obj = {}
    S[obj] = { kind = kind, parent = parent, points = {}, alpha = 1, regions = {}, children = {},
        masks = {}, shown = true, calls = {}, scripts = {}, events = {}, blizzard = blizzard }
    setmetatable(obj, {
        __index = function(_, key)
            local s = S[obj]
            -- A sealed frame's own keys, as they were on the frame.
            local fields = s.fields
            if fields and fields[key] ~= nil then return fields[key] end
            if type(key) == "string" and key:match("^[A-Z]") and not WidgetHas(s, key) then return nil end
            -- On Blizzard's frames: nothing forbidden unless the part allows it
            -- (allow), and nothing a part keeps to itself (deny; ALL for all).
            if s.blizzard and not blizzardCalling and type(key) == "string" and key:match("^[A-Z]") then
                local blocked = FORBIDDEN[key] and not (s.allow and s.allow[key]) and not (key == "IsShown" and s.readable)
                if blocked or (s.deny and (s.deny[key] or s.deny.ALL)) then
                    return function() error("called " .. key .. " on a Blizzard frame", 2) end
                end
            end
            local method = Proto[key]
            if method then return method end
            if type(key) == "string" and key:match("^[A-Z]") then return Fallback(key) end
        end,
        __newindex = function(t, key, value)
            if S[t].sealed then error("wrote key '" .. tostring(key) .. "' on a Blizzard frame", 2) end
            rawset0(t, key, value)
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
function Proto:GetAlpha() return S[self].alpha end
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
-- Raid Timers: what the restyle sets on Blizzard's countdown, raid warnings
-- and boss cast bars, where each part allows it.
function Proto:GetDrawLayer() return S[self].layer end
function Proto:GetStatusBarTexture() return S[self].fill end
function Proto:SetVertexColor(r, g, b) S[self].tint = { r, g, b } end
function Proto:SetDesaturated(v) S[self].desaturated = v end
function Proto:SetTextColor(r, g, b) S[self].textColour = { r, g, b } end
function Proto:SetShadowOffset(x, y) S[self].shadowOffset = x .. "," .. y end
function Proto:SetShadowColor(r, g, b, a) S[self].shadowColour = { r, g, b, a } end
function Proto:GetStringWidth() return 40 end
function Proto:Click() S[self].scripts.OnClick(self) end
-- Sizes, where a part allows them: each call the addon makes is counted.
local sizeCalls = 0
function Proto:SetScale(scale)
    if not blizzardCalling then sizeCalls = sizeCalls + 1 end
    S[self].scale = scale
end
function Proto:SetTextHeight(height)
    if not blizzardCalling then sizeCalls = sizeCalls + 1 end
    S[self].textHeight = height
end
-- Whether the game protects it (none of these are, unless a test says so).
function Proto:IsProtected() return S[self].protected == true, false end

-- Every frame sealed so far: nothing may ever be left on one (see the end).
local sealed = setmetatable({}, { __mode = "k" })
local function Seal(obj)
    local s = S[obj]
    s.sealed, s.blizzard = true, true
    sealed[obj] = true
    -- Its keys move off the frame, so writing any of them again reaches the seal.
    if not s.fields then
        local fields = {}
        for key, value in next, obj do fields[key] = value end
        for key in next, fields do rawset0(obj, key, nil) end
        s.fields = fields
    end
    for _, r in ipairs(s.regions) do Seal(r) end
    for _, c in ipairs(s.children) do Seal(c) end
end
-- What a cooldown item, buff icon, Tracked Bar or viewer keeps to itself, as
-- a whole: its place and its alpha (its parts allow what the look needs).
local function KeepsPlace(obj)
    S[obj].deny = { SetPoint = true, ClearAllPoints = true, SetAllPoints = true, SetAlpha = true }
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
    KeepsPlace(item)
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
    KeepsPlace(item)
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
    KeepsPlace(item)
    return item, overlay
end

local acquired = {}
-- Blizzard's own refreshes, run by the test as the game would. The addon may
-- only post-hook them, never call them itself.
local function Blizzard(viewer, method, ...)
    blizzardCalling = true
    viewer[method](viewer, ...)
    blizzardCalling = false
end
local function Viewer(name, make, preexisting)
    local viewer = New("Frame")
    local active = {}
    for i = 1, preexisting do active[make()] = true end
    -- Blizzard's pool: read, never written.
    viewer.itemFramePool = setmetatable({}, {
        __index = { EnumerateActive = function() return pairs(active) end },
        __newindex = function(_, key) error("wrote key " .. tostring(key) .. " on a Blizzard pool", 2) end,
    })
    viewer.OnAcquireItemFrame = function(self, item)
        assert(blizzardCalling, "called OnAcquireItemFrame on a Blizzard viewer")
        acquired[item] = (acquired[item] or 0) + 1
    end
    viewer.make = make
    -- Like Blizzard's (CooldownViewer.lua RefreshLayout): a shown viewer
    -- refreshes its items (RefreshData) as it lays them out; a hidden one
    -- waits to be shown, which lays it out again.
    viewer.RefreshLayout = function(self)
        assert(blizzardCalling, "called RefreshLayout on a Blizzard viewer")
        if S[self].shown then self:RefreshData() end
    end
    viewer.RefreshData = function() assert(blizzardCalling, "called RefreshData on a Blizzard viewer") end
    Seal(viewer)
    KeepsPlace(viewer)
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
    _G.CreateFrame = function(kind, name, parent, template)
        local f = New(kind, parent)
        S[f].frameTemplate = template
        S[f].name = name
        S[f].shown = true
        table.insert(frames, f)
        if name then _G[name] = f end
        return f
    end
    -- A global function by its name, or a table's; the hook is the addon's own
    -- code, so it runs under the addon's rules even inside Blizzard's call.
    _G.hooksecurefunc = function(t, key, hook)
        if type(t) == "string" then t, key, hook = _G, t, key end
        local original = t[key]
        rawset(t, key, function(...)
            original(...)
            local was = blizzardCalling
            blizzardCalling = false
            hook(...)
            blizzardCalling = was
        end)
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
    -- Key bindings are never changed from addon code (Tools/TestBars.lua):
    -- a call is kept and stops the test.
    for _, name in ipairs({ "SetBinding", "SetBindingClick", "SetOverrideBinding", "SetOverrideBindingClick",
        "ClearOverrideBinding", "ClearOverrideBindings", "SaveBindings", "LoadBindings" }) do
        _G[name] = function() bindings[#bindings + 1] = name; error(name .. " called from addon code") end
    end
    _G.UISpecialFrames = {}
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
    assert(loadfile("RaidTimers.lua"))("ForeverEnhancedCooldownManager", ns)
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
Blizzard(v.essential, "OnAcquireItemFrame", fresh)
Equal(acquired[fresh], 1, "Blizzard's own OnAcquireItemFrame still runs first")
Equal(ns.Skin:IsSkinned(fresh), true, "newly acquired icons are restyled")
Blizzard(v.essential, "OnAcquireItemFrame", fresh)
Equal(S[fresh.Icon].zooms, 1, "a reused frame is not restyled twice")
Equal(acquired[fresh], 2, "Blizzard still handles every acquire")

local utility = CooldownItem()
Blizzard(v.utility, "OnAcquireItemFrame", utility)
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
Blizzard(bar, "OnCooldownIDSet")
Equal(textures, before, "not set again while it stays the same, even as Blizzard gives the bar a new spell")
ns.Set("barTexture", "flat")
ns.Skin:ApplyBarLook()
Equal(S[bar.Bar].barTexture, FLAT, "flat again")
Proto.SetStatusBarTexture = SetTexture
-- Blizzard gives its bars their spells again after every relayout: a bar
-- with the same spell, design and colour as last time is left as it is.
do
    local colours, SetColour = 0, Proto.SetStatusBarColor
    function Proto:SetStatusBarColor(...)
        colours = colours + 1
        SetColour(self, ...)
    end
    Blizzard(bar, "OnCooldownIDSet")
    Equal(colours, 0, "given the same spell again, in the same design and colour: nothing set again")
    ns.Set("barColour", "blue")
    Blizzard(bar, "OnCooldownIDSet")
    Equal(colours .. " " .. S[bar.Bar].barColour[3], "1 0.88", "the colour for all changed meanwhile: drawn again in it")
    ns.Set("barColour", "orange")
    ns.Skin:ApplyBarLook()
    Equal(colours, 2, "a Look page choice always draws every bar again")
    Proto.SetStatusBarColor = SetColour
end
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
Blizzard(v.bars, "OnAcquireItemFrame", other)
v.barsActive[other] = true
rawset(other, "layoutIndex", 1) -- Blizzard's own order
rawset(bar, "layoutIndex", 2)
Equal(table.concat(ns.Skin:TrackedBars(), ","), "1126,467", "the window lists your Tracked Bars in Blizzard's order")
-- An order the game keeps secret is never compared: that bar goes last.
_G.issecretvalue = function(value) return rawequal(value, SECRETS.number) end
rawset(other, "layoutIndex", SECRETS.number)
Equal(table.concat(ns.Skin:TrackedBars(), ","), "467,1126", "an order the game keeps secret: never compared, that bar listed last")
rawset(other, "layoutIndex", 1)
_G.issecretvalue = nil
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
Blizzard(other, "OnCooldownIDSet")
Equal(S[other.Bar].barColour[3], .91, "a bar given Thorns turns purple straight away")
local SECRET = SECRETS.number -- an ID, a height: secret numbers
_G.issecretvalue = function(value) return rawequal(value, SECRET) end
S[other].baseSpell = SECRET
Blizzard(other, "OnCooldownIDSet")
Equal(S[other.Bar].barColour[2], .74, "a spell that can't be read uses the colour for all")
-- (Its spell taken off before the game stops calling it secret: a secret left
-- there would read as a plain number then.)
S[other].baseSpell = nil
_G.issecretvalue = nil
ns.SetBarColour(467, nil)
ns.Skin:ApplyBarLook()
Equal(ns.BarColours()[467] == nil and S[bar.Bar].barColour[2], .74, "and back to the colour for all")
ns.Set("barColour", "orange")
ns.Skin:ApplyBarLook()
-- Since build 70170 Blizzard shows every rank of a spell on one bar, under
-- one of its ranks (Thorns 467 at any rank), so a colour goes with the spell,
-- by the ranks in Ranks.lua: the highest rank that has one (before the patch,
-- learning a rank dropped the colour, so that's the latest pick).
do
    assert(loadfile("Ranks.lua"))("ForeverEnhancedCooldownManager", ns)
    local colours = ForeverEnhancedCooldownManagerDB
    S[other].baseSpell = 1126
    Blizzard(other, "OnCooldownIDSet")
    colours.barColours = { [782] = "blue" } -- picked while Blizzard showed Thorns rank 2
    ns.Skin:ApplyBarLook()
    Equal(S[bar.Bar].barColour[3] .. " " .. S[other.Bar].barColour[3], "0.88 0.25",
        "a colour saved on Thorns rank 2 colours the bar Blizzard gives rank 1, not Mark of the Wild's")
    Equal(ns.BarColourFor(467) .. " " .. ns.BarColourFor(9910) .. " " .. tostring(ns.BarColourFor(1126))
        .. " " .. tostring(ns.BarColourFor(16870)), "blue blue nil nil", "any rank of Thorns finds it; no other spell does")
    S[other].baseSpell = 9910
    Blizzard(other, "OnCooldownIDSet")
    Equal(S[other.Bar].barColour[3], .88, "and a bar given another rank of Thorns turns blue straight away")
    colours.barColours = { [782] = "blue", [9910] = "purple" }
    Equal(ns.BarColourFor(467) .. " " .. ns.BarColourFor(9910), "purple purple", "with colours at several ranks, the highest rank's")
    colours.barColours = { [467] = "green", [9910] = "purple" }
    ns.Skin:ApplyBarLook()
    Equal(ns.BarColourFor(467) .. " " .. ns.BarColourFor(782) .. " " .. S[bar.Bar].barColour[3], "purple purple 0.91",
        "even over the bar's own ID: rank 1's colour is the older pick")
    colours.barColours = { [467] = "green" }
    Equal(ns.BarColourFor(467) .. " " .. ns.BarColourFor(9910), "green green", "and the bar's own ID when it's the only one")
    colours.barColours = { [782] = "blue", [9910] = "purple", [1126] = "green", [16870] = "charcoal" }
    ns.SetBarColour(467, "class")
    local stored = {}
    for id, key in pairs(ns.BarColours()) do stored[#stored + 1] = id .. "=" .. key end
    table.sort(stored)
    Equal(table.concat(stored, " "), "1126=green 16870=charcoal 467=class",
        "a new colour goes under the bar's ID, and the spell's other ranks lose theirs")
    colours.barColours = { [782] = "blue", [1126] = "green" }
    ns.SetBarColour(9910, nil)
    ns.Skin:ApplyBarLook()
    Equal(tostring(next(ns.BarColours(), nil)) .. " " .. S[bar.Bar].barColour[3], "1126 0.25",
        "going back to the colour for all clears every rank")
    ns.SetBarColour(16870, "blue")
    Equal(ns.BarColours()[16870] .. " " .. ns.BarColours()[1126] .. " " .. ns.BarColourFor(16870), "blue green blue",
        "a spell with no ranks listed keeps its own ID, and finds it there")
    colours.barColours = {}
    ns.RANKS = nil
    Equal(tostring(ns.BarColourFor(467)), "nil", "and nothing breaks without the rank list")
end
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

-- Only hooksecurefunc touched Blizzard's viewers (their keys are kept with
-- the seal, so nothing at all is on the frame itself).
for _, viewer in ipairs({ v.essential, v.utility, v.buffs, v.bars }) do
    local keys = 0
    for key in pairs(S[viewer].fields) do if key ~= "make" then keys = keys + 1 end end
    Equal(keys .. " " .. tostring(next(viewer)), "4 nil",
        "viewer holds only its pool and its own acquire, layout and refresh functions, hooked")
end
Equal(#printed, 0, "no errors reported")

-- A failure is reported once, never thrown into Blizzard's code --------------------------

local broken = New("Frame")
Seal(broken)
Blizzard(v.essential, "OnAcquireItemFrame", broken)
Equal(#printed, 1, "a restyle failure is reported")
Equal(printed[1]:find("Please report this", 1, true) ~= nil, true, "with a clear message")
local broken2 = New("Frame")
Seal(broken2)
Blizzard(v.utility, "OnAcquireItemFrame", broken2)
Equal(#printed, 1, "reported only once per session")

-- Charcoal look off: nothing is hooked or restyled -----------------------------------

Environment()
v = Viewers(1)
ns = Load({ skin = false })
Equal(ns.Skin.started, nil, "skin not started when off")
Equal(ns.Skin:IsSkinned(First(v.essentialActive)), false, "icons keep Blizzard's look")
Equal(rawget(v.essential, "OnAcquireItemFrame") == v.essential.OnAcquireItemFrame, true, "no hook installed")
local plain = CooldownItem()
Blizzard(v.essential, "OnAcquireItemFrame", plain)
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
    "true true false purple", "defaults, as a first install")
Equal(#ns.BarData("cd").spells .. " " .. ns.BarData("cd").size, "0 36", "with empty bars")
Equal(#printed, 0, "and nothing to say")

-- Anything unexpected in the saved settings is ignored.
ForeverEnhancedCooldownManagerDB.accent = "pink"
Equal(ns.Get("accent"), "purple", "an invalid saved accent reads as the default")
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
    -- The room Blizzard leaves between its bars: a getter the addon may read.
    frame.GetBarPadding = function() return 4 end
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
Equal(tostring(row.border) .. " " .. tostring(row.shadow) .. " " .. tostring(utilityRow.border), "nil nil nil",
    "no box round an empty row: its rings aren't even made until one shows")
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
Blizzard(v.essential, "OnAcquireItemFrame", spare)
v.essentialActive[spare] = true
Blizzard(v.essential, "RefreshData")
local top = S[row.border[1]].points[1]
Equal(tostring(top[2] == item.Icon) .. " " .. top[4] .. " " .. top[5], "true -1 0", "one cooldown: the border round its icon art")
Equal(tostring(S[row.shadow[1][1]].points[1][2] == item.Icon) .. " " .. tostring(S[row.shadow[1][1]].shown), "true true", "and the shadow")
-- A cooldown the game keeps secret still counts as one.
_G.issecretvalue = function(value) return rawequal(value, SECRET) end
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

-- Border and shadow off (the default): their rings (20 textures an icon)
-- are never made on Blizzard's icons or rows, until one is chosen.
Environment()
v = Viewers(1)
ns = Load({})
item = First(v.essentialActive)
rawset(item, "cooldownID", 7)
Blizzard(v.essential, "RefreshLayout")
decor, row = ns.Skin.decors[item], ns.Skin.rows.EssentialCooldownViewer
Equal(tostring(decor ~= nil) .. " " .. tostring(decor.border) .. " " .. tostring(decor.shadow) .. " " .. tostring(row.border),
    "true nil nil nil", "off: no rings made round Blizzard's icons or rows")
ns.Set("iconBorder", "icon")
ns.Skin:ApplyDecor()
Equal(tostring(S[decor.border[1]].shown) .. " " .. tostring(S[decor.shadow[1][1]].shown) .. " " .. tostring(row.border),
    "true false nil", "chosen: made then, round each icon only")
Equal(#printed, 0, "no errors from rings made late")

-- Blizzard lays its rows out again and again (a full aura update on you or
-- your target): a box round the row is only placed, shown or hidden when
-- something about it changed, never again for the same.
do
    ns.Set("iconBorder", "bar")
    ns.Set("iconShadow", "bar")
    ns.Skin:ApplyDecor()
    local strips = {}
    for _, strip in ipairs(row.border) do strips[strip] = true end
    for _, ring in ipairs(row.shadow) do
        for _, strip in ipairs(ring) do strips[strip] = true end
    end
    -- Calls on the box's strips while fn runs.
    local function Touched(fn)
        local count, saved = 0, {}
        for name, method in pairs(Proto) do
            saved[name] = method
            Proto[name] = function(self, ...)
                if strips[self] then count = count + 1 end
                return method(self, ...)
            end
        end
        fn()
        for name, method in pairs(saved) do Proto[name] = method end
        return count
    end
    Equal(tostring(S[row.border[1]].shown) .. " " .. tostring(S[row.shadow[1][1]].shown), "true true", "a border and shadow round the row")
    local laid = Touched(function() Blizzard(v.essential, "RefreshLayout") end)
    local refreshed = Touched(function() Blizzard(v.essential, "RefreshData") end)
    Equal(laid .. " " .. refreshed, "0 0", "laid out or refreshed again, nothing changed: none of its 20 strips touched (was each placed and shown, twice)")
    rawset(item, "cooldownID", nil)
    Blizzard(v.essential, "RefreshLayout")
    Equal(tostring(S[row.border[1]].shown) .. " " .. tostring(S[row.shadow[1][1]].shown), "false false", "emptied: the box goes")
    local hidden = Touched(function() Blizzard(v.essential, "RefreshLayout") end)
    Equal(hidden, 0, "and while it's gone, nothing touched either")
    rawset(item, "cooldownID", 7)
    Blizzard(v.essential, "RefreshData")
    Equal(tostring(S[row.border[1]].shown) .. " " .. tostring(S[row.shadow[1][1]].shown), "true true", "a cooldown back: so is the box")
    Equal(#printed, 0, "no errors from rows laid out again")
end

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
        _G.issecretvalue = function(value) return rawequal(value, SECRET) end
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
    Blizzard(essential, "OnCooldownIDSet")
    Equal(tostring(S[text].shown) .. " " .. Count(essential), "false BOTTOMRIGHT true BOTTOMRIGHT -2 2",
        "given a spell with no key: none, and its charge count back where Blizzard puts it")
    S[essential].baseSpell = 8924
    Blizzard(essential, "OnCooldownIDSet")
    Equal(S[text].text .. " " .. tostring(S[text].shown) .. " " .. Count(essential), "S1 true TOPRIGHT true TOPRIGHT -2 -2",
        "given one with a key: shown at once, the count up clear of it")
    -- Blizzard's pool takes it back and empties it without OnCooldownIDCleared
    -- (ResetCooldownData), then hands it out again as an Edit Mode placeholder:
    -- ClearCooldownID fires nothing on an item already empty.
    S[essential].baseSpell = nil
    Blizzard(views.essential, "OnAcquireItemFrame", essential)
    Equal(tostring(S[text].shown) .. " " .. #printed, "false 0", "handed out again as an empty placeholder: the old key goes")
    S[essential].baseSpell = 8924
    Blizzard(essential, "OnCooldownIDSet")
    Equal(S[text].text .. " " .. tostring(S[text].shown), "S1 true", "and comes back when Blizzard gives it a spell")
    -- Handed out again it has no spell yet (Blizzard emptied it): nothing
    -- is looked up for it then, only once it gets its spell.
    do
        local reads, GetBase = 0, Proto.GetBaseSpellID
        function Proto:GetBaseSpellID()
            if self == essential then reads = reads + 1 end
            return GetBase(self)
        end
        S[essential].baseSpell = nil
        Blizzard(views.essential, "OnAcquireItemFrame", essential)
        Equal(tostring(S[text].shown) .. " " .. reads, "false 0", "handed out again: the old key goes, nothing looked up")
        S[essential].baseSpell = 8924
        Blizzard(essential, "OnCooldownIDSet")
        Equal(S[text].text .. " " .. tostring(S[text].shown) .. " " .. reads, "S1 true 1", "looked up once as it gets its spell")
        Proto.GetBaseSpellID = GetBase
        -- The keys again with none changed (a form change that moves no key
        -- here): nothing set again.
        local sets, SetText = 0, Proto.SetText
        function Proto:SetText(value)
            if self == text then sets = sets + 1 end
            return SetText(self, value)
        end
        kns.Skin:ShowKeys()
        Proto.SetText = SetText
        Equal(sets .. " " .. S[text].text, "0 S1", "the keys again with none changed: nothing set again")
    end
    S[utility].equipSlot = nil
    Blizzard(views.utility, "OnAcquireItemFrame", utility)
    Equal(tostring(S[small.text].shown) .. " " .. Count(utility), "false BOTTOMRIGHT true BOTTOMRIGHT -2 2",
        "a trinket's Utility icon handed out again empty: no key either, its count at the bottom")
    S[utility].equipSlot = 13
    Blizzard(utility, "OnCooldownIDSet")
    Equal(S[small.text].text .. " " .. tostring(S[small.text].shown) .. " " .. Count(utility), "2 true TOPRIGHT true TOPRIGHT -2 -2",
        "and back with its trinket, its count up")
    S[essential].baseSpell = nil
    Blizzard(essential, "OnCooldownIDCleared")
    Equal(tostring(S[text].shown), "false", "cleared, as for Edit Mode's placeholders: gone")

    -- A spell kept secret in a fight: nothing until it's over.
    combat = true
    S[essential].baseSpell = SECRET
    Blizzard(essential, "OnCooldownIDSet")
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
    for _ in pairs(S[essential].fields) do held = held + 1 end
    Equal(held .. " " .. tostring(next(essential)), "7 nil", "Blizzard's icon holds only its own parts and the two hooks")
    for _, viewer in ipairs({ views.essential, views.utility, views.buffs, views.bars }) do
        local count = 0
        for name in pairs(S[viewer].fields) do if name ~= "make" then count = count + 1 end end
        Equal(count .. " " .. tostring(next(viewer)), "4 nil", "each viewer still holds only its own four")
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
    -- Off, nothing is looked up as Blizzard hands its icons out and gives them spells.
    do
        local reads, GetBase = 0, Proto.GetBaseSpellID
        function Proto:GetBaseSpellID()
            if self == essential then reads = reads + 1 end
            return GetBase(self)
        end
        Blizzard(views.essential, "OnAcquireItemFrame", essential)
        S[essential].baseSpell = 8924
        Blizzard(essential, "OnCooldownIDSet")
        Proto.GetBaseSpellID = GetBase
        Equal(reads .. " " .. tostring(S[kns.Skin.keys[essential].text].shown), "0 false", "off: no key looked up for Blizzard's icons")
    end

    -- Without the look, Blizzard's icons get no keys, and nothing breaks.
    Environment()
    Viewers(1)
    Game()
    kns = Load({ skin = false, keybinds = true })
    local ok = pcall(kns.Keybinds.Update, kns.Keybinds)
    Equal(tostring(next(kns.Skin.keys)) .. " " .. tostring(ok) .. " " .. #printed, "nil true 0", "the look off: no keys on Blizzard's icons, no errors")
    _G.issecretvalue = nil
end

-- Raid Timers on Blizzard's own frames ---------------------------------------------------
-- Its countdown frames, raid warning lines and boss cast bars, sealed like the
-- viewers: each part allows only the cosmetic setters the restyle uses, and
-- Blizzard's own functions here fail if the addon calls them.
do
    local DIGIT_KEYS = { "digit1", "digit2", "glow1", "glow2" }
    local FLAT, PLAIN = "Interface\\Buttons\\WHITE8X8", "Interface\\TargetingFrame\\UI-StatusBar"
    -- What a part keeps to itself: its place, size and alpha, and whatever else is named.
    local function Keep(obj, extra, alpha)
        local deny = { SetPoint = true, ClearAllPoints = true, SetAllPoints = true, SetAlpha = not alpha,
            SetWidth = true, SetHeight = true }
        for key in pairs(extra or {}) do deny[key] = true end
        S[obj].deny = deny
    end
    local function Untouchable(obj) S[obj].deny = { ALL = true } end

    -- Blizzard's StartTimerBar: the frame, its bar (named, its border named
    -- after it), the black backing, the time, the numbers and the logo.
    local function StartTimerBar(index)
        local timer = New("Frame")
        S[timer].name = "TimerTrackerTimer" .. index
        local bar = New("StatusBar", timer)
        S[bar].name = "TimerTrackerTimer" .. index .. "StatusBar"
        local backing = New("Texture", bar)
        S[backing].layer = "BACKGROUND"
        -- The fill, listed with the bar's regions after it: never taken for the backing.
        local fill = New("Texture", bar)
        S[fill].layer = "BACKGROUND"
        S[bar].fill = fill
        local border = New("Texture", bar)
        S[border].layer = "OVERLAY"
        _G[S[bar].name .. "Border"] = border
        rawset(bar, "timeText", New("FontString", bar))
        S[bar.timeText].points = { { "CENTER", nil, nil, 0, 0 } }
        rawset(timer, "bar", bar)
        for _, key in ipairs(DIGIT_KEYS) do rawset(timer, key, New("Texture", timer)) end
        rawset(timer, "GoTexture", New("Texture", timer))
        Seal(timer)
        Keep(timer)
        Keep(bar)
        -- The approved exception: the bar and the two big digits may be scaled.
        S[bar].allow = { SetScale = true }
        Keep(backing, nil, true)
        Keep(border, nil, true)
        for _, key in ipairs(DIGIT_KEYS) do
            Keep(timer[key])
            S[timer[key]].allow = { SetVertexColor = true, SetDesaturated = true, SetScale = key:match("^digit") ~= nil }
        end
        Untouchable(fill)
        Untouchable(timer.GoTexture)
        return timer, backing, border
    end

    local tracker, made
    local function Tracker()
        tracker = New("Frame")
        rawset(tracker, "timerList", {})
        Seal(tracker)
        Untouchable(tracker)
        _G.TimerTracker = tracker
        made = {}
        -- Blizzard's: reuses a free frame or makes the next, and sets the
        -- numbers' art again each time.
        _G.TimerTracker_StartTimerOfType = function(self, timerType, timeSeconds)
            assert(blizzardCalling, "called Blizzard's TimerTracker_StartTimerOfType")
            local timer
            for _, each in ipairs(self.timerList) do
                if each.isFree then timer = each end
            end
            if not timer then
                local backing, border
                timer, backing, border = StartTimerBar(#self.timerList + 1)
                made[timer] = { backing = backing, border = border }
                table.insert(self.timerList, timer)
            end
            rawset(timer, "isFree", false)
            rawset(timer, "time", timeSeconds)
            rawset(timer, "type", timerType)
            for _, key in ipairs(DIGIT_KEYS) do timer[key]:SetTexture("Interface\\Timer\\BigTimerNumbers") end
        end
    end
    local function Countdown(seconds)
        blizzardCalling = true
        TimerTracker_StartTimerOfType(tracker, 3, seconds, seconds)
        blizzardCalling = false
    end
    local function Free(timer)
        blizzardCalling = true
        rawset(timer, "isFree", true)
        blizzardCalling = false
    end

    -- Blizzard's RaidWarningFrame: its pool of lines (their text secret), and
    -- the private boss emote anchor and deadly debuff frame under them.
    local frame, pool, lines
    local function Warnings()
        frame = New("Frame")
        lines = {}
        local active = {}
        pool = setmetatable({}, { __newindex = function() error("wrote on Blizzard's pool", 2) end })
        rawset(pool, "EnumerateActive", function() return pairs(active) end)
        rawset(pool, "Release", function(_, line)
            assert(blizzardCalling)
            active[line] = nil
            rawset(line, "textScalingTime", nil) -- FadingFrame_StopTextScaling
        end)
        rawset(pool, "Acquire", function()
            assert(blizzardCalling, "acquired from Blizzard's pool")
            for _, line in ipairs(lines) do
                if not active[line] then
                    active[line] = true
                    return line
                end
            end
            local line = New("FontString", frame)
            Seal(line)
            Keep(line, { SetFontObject = true, SetJustifyH = true })
            -- Only its text height, for your sizes.
            S[line].allow = { SetTextHeight = true }
            -- Blizzard's FadingFrame_InitSlot: 20 high, growing to 30 and back over 0.4 s.
            rawset(line, "textScalingMinHeight", 20)
            rawset(line, "textScalingMaxHeight", 30)
            rawset(line, "textScalingUpTime", .2)
            rawset(line, "textScalingDownTime", .4)
            lines[#lines + 1] = line
            active[line] = true
            return line
        end)
        rawset(frame, "fontStringPool", pool)
        rawset(frame, "AddMessage", function(self, text, info, _, messageType)
            assert(blizzardCalling, "called Blizzard's AddMessage")
            local line = self.fontStringPool:Acquire()
            line:SetText(text)
            line:SetTextColor(info.r, info.g, info.b, 1)
            line:SetTextHeight(20)
            rawset(line, "messageType", messageType or 1)
            -- Each message's place in the order, the newest the frame's count.
            rawset(self, "messageCounter", (rawget(self, "messageCounter") or 0) + 1)
            rawset(line, "messageOrder", self.messageCounter)
            rawset(line, "textScalingTime", 0) -- FadingFrame_StartTextScaling
        end)
        -- Blizzard's, run each frame for every line showing: grows a new
        -- line from 20 to 30 and back, then leaves it at 20.
        _G.FadingFrame_UpdateTextScaling = function(line, elapsed)
            assert(blizzardCalling, "called Blizzard's FadingFrame_UpdateTextScaling")
            local now = rawget(line, "textScalingTime")
            if not now then return end
            now = now + elapsed
            local low, high, up, down = line.textScalingMinHeight, line.textScalingMaxHeight, line.textScalingUpTime,
                line.textScalingDownTime
            if now <= up then
                rawset(line, "textScalingTime", now)
                line:SetTextHeight(math.floor(low + (high - low) * now / up))
            elseif now <= down then
                rawset(line, "textScalingTime", now)
                line:SetTextHeight(math.floor(high - (high - low) * (now - up) / (down - up)))
            else
                line:SetTextHeight(low)
                rawset(line, "textScalingTime", nil)
            end
        end
        Seal(frame)
        Keep(frame, { Show = true, Hide = true })
        _G.RaidWarningFrame = frame
        _G.RaidWarningUtil = { MessageType = { RaidWarning = 1, BossEmote = 2, BGSystem = 3 } }
        _G.GameFontNormalHuge = { GetFont = function() return "Fonts\\FRIZQT__.TTF", 20, "" end,
            GetShadowOffset = function() return 1, -1 end }
        local anchor, deadly = New("Frame"), New("Frame")
        Seal(anchor)
        Seal(deadly)
        Untouchable(anchor)
        Untouchable(deadly)
        _G.PrivateRaidBossEmoteFrameAnchor, _G.DeadlyDebuffFrame = anchor, deadly
    end
    local WARNING, EMOTE = { r = 1, g = .282, b = 0 }, { r = 1, g = .867, b = 0 }
    local function Say(info, messageType)
        blizzardCalling = true
        frame:AddMessage(SECRET, info, nil, messageType)
        blizzardCalling = false
    end
    local function Release(line)
        blizzardCalling = true
        pool:Release(line)
        blizzardCalling = false
    end
    -- One frame of Blizzard's RaidWarningFrame OnUpdate: each line showing grows or shrinks.
    local function Frames(elapsed)
        blizzardCalling = true
        for line in pool:EnumerateActive() do FadingFrame_UpdateTextScaling(line, elapsed) end
        blizzardCalling = false
    end

    -- Blizzard's Boss1-5 frames, each with its spell bar: the fill it picks
    -- for each cast, its art, and the shield and finish flash it keeps. Their
    -- container shows them; Edit Mode's Boss Frames tick sets its
    -- isInEditMode and calls its UpdateShownState, as does closing Edit Mode.
    local bars, box
    local function Bosses()
        bars = {}
        box = New("Frame")
        rawset(box, "isInEditMode", false)
        rawset(box, "UpdateShownState", function()
            assert(blizzardCalling, "called Blizzard's BossTargetFrameContainer:UpdateShownState")
        end)
        Seal(box)
        Untouchable(box)
        _G.BossTargetFrameContainer = box
        for i = 1, 5 do
            local boss = New("Button")
            S[boss].name = "Boss" .. i .. "TargetFrame"
            local bar = New("StatusBar", boss)
            S[bar].name = "Boss" .. i .. "TargetFrameSpellBar"
            for _, key in ipairs({ "TextBorder", "Background", "BorderShield", "Icon", "Border", "Spark", "Flash" }) do
                rawset(bar, key, New("Texture", bar))
            end
            rawset(bar, "Text", New("FontString", bar))
            local fill = New("Texture", bar)
            S[bar].fill = fill
            -- Blizzard's: UpdateBarFillTexture(isFull), the atlas from the cast's type.
            rawset(bar, "UpdateBarFillTexture", function(self, isFull)
                assert(blizzardCalling, "called Blizzard's UpdateBarFillTexture")
                assert(type(isFull) == "boolean", "Blizzard passes isFull")
                local atlas = S[self].pick
                S[self].barTexture = atlas
                S[S[self].fill].atlas = atlas
            end)
            rawset(boss, "spellbar", bar)
            Seal(boss)
            Untouchable(boss)
            Keep(bar)
            for _, key in ipairs({ "TextBorder", "Background", "Border", "Spark" }) do Keep(bar[key], nil, true) end
            Keep(bar.Icon)
            Keep(bar.Text)
            Untouchable(bar.BorderShield)
            Untouchable(bar.Flash)
            -- The fill: only its alpha may change, never its place or size.
            Keep(fill, nil, true)
            _G["Boss" .. i .. "TargetFrame"], _G["Boss" .. i .. "TargetFrameSpellBar"] = boss, bar
            bars[i] = bar
        end
    end
    -- Blizzard picks a bar's fill: atlas for the cast's type, full as a cast
    -- ends or with no cast at all (its first PLAYER_ENTERING_WORLD, a loading screen).
    local function Cast(bar, atlas, full)
        S[bar].pick = atlas
        blizzardCalling = true
        bar:UpdateBarFillTexture(full == true)
        blizzardCalling = false
    end
    -- Blizzard marks a bar casting or channelling (after it picks the fill), or neither.
    local function Casting(bar, casting, channeling)
        rawset(bar, "casting", casting)
        rawset(bar, "channeling", channeling)
    end
    -- Edit Mode's Boss Frames ticked (true) or unticked, or Edit Mode closed (false).
    local function EditMode(on)
        rawset(box, "isInEditMode", on)
        blizzardCalling = true
        box:UpdateShownState()
        blizzardCalling = false
    end
    local function Alpha(bar) return S[S[bar].fill].alpha end
    local function Colour(bar)
        local c = S[bar].barColour
        return string.format("%g,%g,%g,%g", c[1], c[2], c[3], c[4])
    end

    local SECRET_ATLAS = "ui-castingbar-interrupted-secret"
    local function Game(era)
        _G.C_AddOns = { IsAddOnLoaded = function(name) return era ~= nil and name == "EraUI" end }
        _G.EraUI = era
        -- A secret can be a string too: one that would read as broken off.
        _G.issecretvalue = function(value) return rawequal(value, SECRET) or value == SECRET_ATLAS end
    end
    -- The keys a frame holds: a sealed one's kept with its seal, and any left
    -- on the frame itself.
    local function Keys(t)
        local count = 0
        for _ in pairs(t) do count = count + 1 end
        for _ in pairs(S[t] and S[t].fields or {}) do count = count + 1 end
        return count
    end

    -- Off, as for everyone at first: nothing hooked, nothing touched.
    Environment()
    Viewers(0)
    Tracker()
    Warnings()
    Bosses()
    Game(nil)
    local plainStart = TimerTracker_StartTimerOfType
    local plainSay, plainFill = frame.AddMessage, bars[1].UpdateBarFillTexture
    local plainShown = box.UpdateShownState
    ns = Load(nil)
    Fire("PLAYER_LOGIN")
    Equal(tostring(TimerTracker_StartTimerOfType == plainStart) .. " " .. tostring(frame.AddMessage == plainSay)
        .. " " .. tostring(bars[1].UpdateBarFillTexture == plainFill) .. " " .. tostring(box.UpdateShownState == plainShown),
        "true true true true", "off: no hooks on the countdown, the raid warnings, the boss bars or their container")
    Countdown(10)
    local timer = tracker.timerList[1]
    Say(WARNING)
    Equal(tostring(S[timer.bar].barTexture) .. " " .. tostring(S[lines[1]].face) .. " " .. tostring(S[bars[1].Border].alpha),
        "nil nil 1", "and Blizzard's look stays as it is")
    EditMode(true)
    Equal(Alpha(bars[1]) .. " " .. Alpha(bars[5]), "1 1", "off, Boss Frames in Edit Mode: Blizzard's fill left as it is")
    EditMode(false)

    -- All three on.
    Environment()
    Viewers(0)
    Tracker()
    Warnings()
    Bosses()
    Game(nil)
    plainSay = frame.AddMessage
    local plainFading = FadingFrame_UpdateTextScaling
    sizeCalls = 0
    ns = Load({ pullTimer = true, raidWarnings = true, bossCasts = true })
    Equal(tostring(frame.AddMessage == plainSay) .. " " .. tostring(S[bars[1].Border].alpha), "true 1",
        "nothing hooked or touched before login")
    Fire("PLAYER_LOGIN")

    -- The countdown, after Blizzard sets it up.
    Countdown(40)
    timer = tracker.timerList[1]
    local bar = timer.bar
    Equal(S[bar].barTexture .. " " .. Colour(bar), FLAT .. " 1,0,0,1", "the countdown bar in your texture, Blizzard's red")
    Equal(S[made[timer].border].alpha .. " " .. S[made[timer].backing].alpha, "0 0", "its old border and backing see-through")
    Equal(S[bar.timeText].font, "FECMFont12", "its time in your font, as big as Blizzard's")
    Equal(tostring(S[timer.digit1].desaturated) .. " " .. table.concat(S[timer.glow2].tint, ","), "false 1,1,1",
        "the big numbers and their glow in Blizzard's gold")
    local edge
    for _, r in ipairs(S[bar].regions) do
        if S[r].layer == "BACKGROUND" and S[r].sublevel == -8 then edge = r end
    end
    Equal(edge ~= nil and S[edge].sealed == nil and S[edge].color[1] == 0, true, "a black edge of the addon's own round the bar")
    -- Blizzard sets the numbers' art again for each countdown: the tint goes on again after.
    ns.Set("pullNumbers", "bar")
    ns.Set("pullColour", "blue")
    Free(timer)
    Countdown(10)
    Equal(#tracker.timerList .. " " .. tostring(S[timer.digit2].desaturated) .. " " .. table.concat(S[timer.digit2].tint, ","),
        "1 true 0.24,0.55,0.88", "the same frame again: numbers in the bar's blue, after Blizzard set them up")
    Equal(Colour(bar), "0.24,0.55,0.88,1", "and the bar blue")
    ns.Set("barStyle", "split")
    ns.RaidTimers:Apply()
    local at = S[bar.timeText].points[1]
    Equal(at[1] .. " " .. tostring(S[at[2]].sealed) .. " " .. tostring(S[at[2]].sublevel), "CENTER nil -7",
        "Split: the time in the addon's own box")
    ns.Set("barStyle", "glass")
    ns.RaidTimers:Apply()
    at = S[bar.timeText].points[1]
    Equal(at[1] .. " " .. tostring(at[2] == bar), "CENTER true", "Glass: centred on the bar again, as Blizzard has it")
    -- A second countdown at once (a battleground's gates): its own frame.
    Countdown(60)
    Equal(#tracker.timerList .. " " .. S[tracker.timerList[2].bar].barTexture, "2 " .. FLAT, "a second frame, restyled too")

    -- Raid warnings and boss emotes: each line showing, after Blizzard adds one.
    Say(WARNING)
    local first = lines[1]
    Equal(S[first].face .. " | " .. S[first].shadowOffset, "Fonts\\FRIZQT__.TTF 20 OUTLINE | 1,-1",
        "a raid warning in your font, outlined, with a shadow")
    Equal(table.concat(S[first].textColour, ","), "1,0.282,0", "in Blizzard's colour for it")
    Say(EMOTE, 2)
    local second = lines[2]
    ns.Set("emoteColour", "purple")
    ns.Set("warningFont", "skurri")
    ns.Set("warningOutline", "thick")
    ns.Set("warningShadow", false)
    ns.RaidTimers:Apply()
    Equal(S[second].face .. " | " .. S[second].shadowOffset .. " | " .. table.concat(S[second].textColour, ","),
        "Fonts\\skurri.ttf 20 THICKOUTLINE | 0,0 | 0.72,0.52,1", "the lines showing change at once: the boss emote purple")
    Equal(table.concat(S[first].textColour, ","), "1,0.282,0", "the raid warning keeps Blizzard's colour")
    -- Lines are pooled: one handed out again is dressed again.
    Release(first)
    ns.Set("warningColour", "white")
    Say(WARNING)
    Equal(S[first].face .. " " .. table.concat(S[first].textColour, ","), "Fonts\\skurri.ttf 20 THICKOUTLINE 1,1,1",
        "a line handed out again: dressed, in your white")
    -- Blizzard's colour chosen again: back on the lines showing at once, each
    -- in the colour Blizzard gave its message.
    ns.Set("warningColour", "default")
    ns.Set("emoteColour", "default")
    ns.RaidTimers:Apply()
    Equal(table.concat(S[first].textColour, ",") .. " | " .. table.concat(S[second].textColour, ","), "1,0.282,0 | 1,0.867,0",
        "Blizzard's colours chosen again: back on the lines showing")
    ns.Set("warningColour", "white")
    ns.Set("emoteColour", "purple")
    ns.RaidTimers:Apply()

    -- Boss cast bars: dressed at login, and the fill after Blizzard picks one.
    local boss = bars[1]
    Equal(S[boss.Border].alpha .. " " .. S[boss.Background].alpha .. " " .. S[boss.TextBorder].alpha .. " " .. S[boss.Spark].alpha,
        "0 0 0 1", "a boss bar's modern frame, backing and name box go; Glass keeps the spark")
    Equal(S[boss.Text].font .. " " .. S[boss.Icon].coords, "FECMFont10 0.08,0.92,0.08,0.92", "the name in your font, the icon zoomed")
    Equal(S[bars[5].Border].alpha, 0, "all five boss bars")
    Cast(boss, "ui-castingbar-filling-standard")
    Equal(S[boss].barTexture .. " " .. Colour(boss), FLAT .. " 1,0.7,0,1", "a cast: your texture, gold")
    Cast(boss, "ui-castingbar-filling-channel")
    Equal(Colour(boss), "0,0.8,0,1", "channelling: green")
    Cast(boss, "ui-castingbar-uninterruptable")
    Equal(Colour(boss), "0.5,0.5,0.5,1", "can't be interrupted: grey")
    Cast(boss, "ui-castingbar-interrupted")
    Equal(Colour(boss), "0.85,0.15,0.1,1", "broken off: red")
    Cast(boss, SECRET)
    Equal(Colour(boss), "1,0.7,0,1", "kept secret: gold, nothing read")
    Cast(boss, SECRET_ATLAS)
    Equal(Colour(boss), "1,0.7,0,1", "a secret that is a string: still gold, never read")
    ns.Set("bossColour", "purple")
    ns.Set("barStyle", "outline")
    Cast(boss, "ui-castingbar-filling-channel")
    Equal(Colour(boss) .. " " .. S[boss.Spark].alpha, "0.6,0.43,0.91,0.45 0", "your purple, see-through for Outline, no spark")
    ns.Set("barStyle", "glass")
    Equal(#printed, 0, "no errors from the raid timers")
    -- Every size at 100%, as for everyone at first: nothing of Blizzard's is
    -- scaled or sized, and Blizzard's growing text isn't even hooked.
    Say(WARNING)
    Frames(.1)
    local midway = S[lines[3] or first].textHeight
    Frames(.5)
    Equal(sizeCalls .. " " .. midway .. " " .. S[first].textHeight .. " " .. tostring(FadingFrame_UpdateTextScaling == plainFading)
        .. " " .. tostring(S[bar].scale) .. " " .. tostring(S[timer.digit1].scale), "0 25 20 true nil nil",
        "sizes at 100%: Blizzard's heights as it sets them, nothing scaled, its text growing left unhooked")

    -- Only hooks were added to Blizzard's frames.
    Equal(Keys(frame) .. " " .. Keys(bars[1]) .. " " .. Keys(tracker) .. " " .. Keys(timer), "3 9 1 9",
        "Blizzard's frames hold only their own parts and the addon's hooks")

    -- Off again, from Split (the time moved, the spark gone), with the raid
    -- warnings in your colours and without a shadow: Blizzard's own look back.
    -- The addon's own pieces on a bar that are showing.
    local function Pieces(region)
        local count = 0
        for _, r in ipairs(S[region].regions) do
            if not S[r].sealed and S[r].shown then count = count + 1 end
        end
        return count
    end
    ns.Set("barStyle", "split")
    ns.RaidTimers:Apply()
    Equal(Pieces(bar) .. " " .. Pieces(boss) .. " " .. S[boss.Spark].alpha .. " " .. tostring(S[bar.timeText].points[1][2] == bar),
        "4 2 0 false", "Split before: the edge, track and box on the countdown, the edge and track on the boss bar, no spark")
    ns.Set("pullTimer", false)
    ns.Set("raidWarnings", false)
    ns.Set("bossCasts", false)
    ns.RaidTimers:Apply()
    ns.Set("barStyle", "glass")
    Equal(S[bar].barTexture .. " " .. Colour(bar) .. " " .. S[made[timer].border].alpha .. " " .. S[made[timer].backing].alpha
        .. " " .. S[bar.timeText].font, PLAIN .. " 1,0,0,1 1 1 GameFontHighlight", "the countdown bar, border, backing and time as Blizzard's")
    at = S[bar.timeText].points[1]
    Equal(#S[bar.timeText].points .. " " .. at[1] .. " " .. tostring(at[2] == bar) .. " " .. at[3] .. " " .. at[4] .. "," .. at[5],
        "1 CENTER true CENTER 0,0", "its time centred on the bar again, out of Split's box")
    Equal(Pieces(bar) .. " " .. Pieces(tracker.timerList[2].bar), "0 0", "none of the addon's pieces left on the countdown bars")
    Equal(tostring(S[timer.digit1].desaturated) .. " " .. table.concat(S[timer.digit1].tint, ","), "false 1,1,1", "the numbers gold")
    Equal(S[first].face .. "|" .. S[second].face, "Fonts\\FRIZQT__.TTF 20 |Fonts\\FRIZQT__.TTF 20 ",
        "every line dressed so far back in Blizzard's font")
    Equal(S[first].shadowOffset .. " " .. S[second].shadowOffset, "1,-1 1,-1", "and its shadow")
    Equal(table.concat(S[first].textColour, ",") .. " | " .. table.concat(S[second].textColour, ","), "1,0.282,0 | 1,0.867,0",
        "and the colour Blizzard gave each message, on the lines still showing")
    Equal(S[boss.Border].alpha .. " " .. S[boss.Text].font .. " " .. S[boss.Icon].coords, "1 SystemFont_Shadow_Small 0,1,0,1",
        "the boss bar's own art, font and icon back")
    Equal(S[boss.Background].alpha .. " " .. S[boss.TextBorder].alpha .. " " .. S[boss.Spark].alpha .. " " .. Pieces(boss),
        "1 1 1 0", "its backing, name box and spark too, none of the addon's pieces left")
    Free(timer)
    Countdown(5)
    Release(lines[3] or first)
    Say(WARNING)
    Cast(boss, "ui-castingbar-filling-standard")
    Equal(S[bar].barTexture .. " " .. S[boss].barTexture .. " " .. S[lines[3] or first].face, PLAIN .. " ui-castingbar-filling-standard "
        .. "Fonts\\FRIZQT__.TTF 20 ", "and nothing restyled any more as Blizzard carries on")
    Equal(#printed, 0, "no errors switching off")

    -- Sizes. The countdown's bar and big digits take a scale (the approved
    -- exception, the countdown only); raid warning lines take Blizzard's text
    -- height times yours, as Blizzard grows each new one and after; each part's
    -- size times Size (all of them).
    Environment()
    Viewers(0)
    Tracker()
    Warnings()
    Bosses()
    Game(nil)
    sizeCalls = 0
    ns = Load({ pullTimer = true, raidWarnings = true, bossCasts = true, pullBarSize = 150, pullNumberSize = 200,
        warningSize = 150, emoteSize = 50 })
    Fire("PLAYER_LOGIN")
    Countdown(40)
    timer = tracker.timerList[1]
    bar = timer.bar
    -- A number as the game prints it (2, not 2.0), or nil.
    local function G(value) return value and string.format("%g", value) or "nil" end
    local function Scales(each)
        return G(S[each.bar].scale) .. " " .. G(S[each.digit1].scale) .. " " .. G(S[each.digit2].scale)
    end
    Equal(Scales(timer), "1.5 2 2", "the countdown bar at 150%, its big digits at 200%")
    Equal(tostring(S[timer].scale) .. " " .. tostring(S[timer.glow1].scale) .. " " .. tostring(S[timer.GoTexture].scale) .. " "
        .. tostring(S[tracker].scale), "nil nil nil nil", "never the timer frame, the glow (pinned to its digit) or the logo")
    Countdown(60)
    Equal(Scales(tracker.timerList[2]), "1.5 2 2", "a second countdown frame too")
    -- The same frame again: Blizzard never scales it, so nothing is set again.
    local calls = sizeCalls
    Free(timer)
    Countdown(10)
    Equal((sizeCalls - calls) .. " " .. Scales(timer), "0 1.5 2 2", "the frame reused: still sized, nothing set again")
    -- Size, all of them together.
    ns.Set("raidSize", 120)
    ns.RaidTimers:Apply()
    Equal(Scales(timer) .. " | " .. Scales(tracker.timerList[2]), "1.8 2.4 2.4 | 1.8 2.4 2.4", "Size at 120%: each times 1.2")
    -- In a fight, a piece the game protected would wait (none of the countdown's are).
    S[bar].protected, combat = true, true
    ns.Set("raidSize", 100)
    ns.RaidTimers:Apply()
    Equal(Scales(timer), "1.8 2 2", "in a fight a protected piece waits; the rest change")
    S[bar].protected, combat = nil, false
    ns.RaidTimers:Apply()
    Equal(Scales(timer), "1.5 2 2", "and takes its size once it can")

    -- Raid warnings in their sizes: the font, and Blizzard's height times yours.
    Say(WARNING)
    Say(EMOTE, 2)
    local warning, emote = lines[1], lines[2]
    Equal(S[warning].face .. " " .. G(S[warning].textHeight) .. " | " .. S[emote].face .. " " .. G(S[emote].textHeight),
        "Fonts\\FRIZQT__.TTF 30 OUTLINE 30 | Fonts\\FRIZQT__.TTF 10 OUTLINE 10", "a raid warning at 150%, a boss emote at 50%")
    Frames(.1)
    Equal(G(S[warning].textHeight) .. " " .. G(S[emote].textHeight), "37.5 12.5", "as Blizzard grows them (25 high): 37.5 and 12.5")
    Frames(.2)
    Equal(G(S[warning].textHeight) .. " " .. G(S[emote].textHeight), "37.5 12.5", "and shrinks them back (25 again)")
    Frames(.2)
    Equal(G(S[warning].textHeight) .. " " .. G(S[emote].textHeight), "30 10", "at rest (20): 30 and 10")
    calls = sizeCalls
    Frames(.1)
    Frames(.1)
    Equal(sizeCalls - calls, 0, "lines at rest are left alone, frame after frame")
    -- A line handed out again: Blizzard sets 20 for its new message, then yours.
    Release(warning)
    Say(EMOTE, 2)
    Equal(S[warning].face .. " " .. G(S[warning].textHeight), "Fonts\\FRIZQT__.TTF 10 OUTLINE 10", "a line handed out again, now an emote: 50%")
    ns.Set("emoteSize", 100)
    ns.RaidTimers:Apply()
    Equal(G(S[warning].textHeight) .. " " .. G(S[emote].textHeight) .. " " .. S[emote].face, "20 20 Fonts\\FRIZQT__.TTF 20 OUTLINE",
        "back to 100%: Blizzard's height on the lines showing, at once")
    calls = sizeCalls
    Frames(.1)
    Frames(.5)
    Equal((sizeCalls - calls) .. " " .. G(S[warning].textHeight), "0 20", "and Blizzard's own heights from then on")
    -- A height that can't be read (a secret) is never set.
    Say(WARNING)
    local third = lines[3]
    rawset(third, "textScalingMinHeight", SECRET)
    calls = sizeCalls
    ns.RaidTimers:Apply()
    Equal(sizeCalls - calls, 0, "Blizzard's heights unreadable: none of yours set")
    rawset(third, "textScalingMinHeight", 20)

    -- Off, mid-growth: Blizzard's height and scale back on everything at once.
    ns.Set("emoteSize", 50)
    ns.Set("raidSize", 150)
    ns.RaidTimers:Apply()
    Say(WARNING)
    Frames(.1)
    local growing = lines[#lines]
    Equal(G(S[growing].textHeight) .. " " .. Scales(timer), "56.25 2.25 3 3", "Size at 150%: a raid warning 225% as it grows")
    ns.Set("pullTimer", false)
    ns.Set("raidWarnings", false)
    ns.RaidTimers:Apply()
    Equal(Scales(timer) .. " | " .. Scales(tracker.timerList[2]), "1 1 1 | 1 1 1", "off: the countdown back to Blizzard's scale")
    Equal(G(S[growing].textHeight) .. " " .. G(S[warning].textHeight) .. " " .. S[growing].face, "25 20 Fonts\\FRIZQT__.TTF 20 ",
        "the lines at Blizzard's height for now (25 still growing, 20 at rest), in its font")
    calls = sizeCalls
    Frames(.1)
    Frames(.5)
    Free(timer)
    Countdown(10)
    Say(WARNING)
    Frames(.1)
    Equal((sizeCalls - calls) .. " " .. Scales(timer), "0 1 1 1", "then nothing sized as Blizzard carries on")
    -- Everything else stays refused: scaling the timer frame, the glow, the
    -- logo, the tracker, a raid warning line or its frame, a boss frame or bar.
    local refused = 0
    for _, each in ipairs({ tracker, timer, timer.glow1, timer.glow2, timer.GoTexture, warning, frame, bars[1],
        Boss1TargetFrame, bars[2].Icon }) do
        if not pcall(function() each:SetScale(2) end) then refused = refused + 1 end
    end
    Equal(refused .. " " .. tostring(pcall(function() bar:SetTextHeight(20) end)) .. " "
        .. tostring(pcall(function() bars[1].Text:SetTextHeight(20) end)), "10 false false",
        "scaling anything else of Blizzard's, or sizing other text, is refused")
    -- Nor any other way to size them: text scale, font height, ignoring the parent's scale.
    refused = 0
    for _, try in ipairs({
        function() bar.timeText:SetTextScale(2) end, function() warning:SetTextScale(2) end,
        function() warning:SetFontHeight(30) end, function() timer:SetIgnoreParentScale(true) end,
        function() bar:SetIgnoreParentScale(true) end, function() timer.digit1:SetIgnoreParentScale(true) end,
    }) do
        if not pcall(try) then refused = refused + 1 end
    end
    Equal(refused, 6, "no text scale, font height or ignored parent scale on Blizzard's countdown or raid warnings")
    -- Ticked again with sizes kept: the boss bars still Blizzard's size.
    ns.Set("pullTimer", true)
    ns.Set("raidWarnings", true)
    ns.RaidTimers:Apply()
    Cast(bars[1], "ui-castingbar-filling-standard")
    Equal(Scales(timer) .. " " .. tostring(S[bars[1]].scale) .. " " .. tostring(S[Boss1TargetFrame].scale), "2.25 3 3 nil nil",
        "on again: the countdown sized again, the boss bars and frames never")
    Equal(#printed, 0, "no errors with sizes")

    -- Only Emote size changed (Warning size and All sizes at 100): Blizzard's
    -- growing text is hooked all the same, so a boss emote keeps your size
    -- as Blizzard grows it and once it rests; raid warnings stay Blizzard's.
    do
        Environment()
        Viewers(0)
        Tracker()
        Warnings()
        Bosses()
        Game(nil)
        local plainGrowth = FadingFrame_UpdateTextScaling
        sizeCalls = 0
        ns = Load({ raidWarnings = true, emoteSize = 150 })
        Fire("PLAYER_LOGIN")
        Say(EMOTE, 2)
        Say(WARNING)
        local emoteLine, warningLine = lines[1], lines[2]
        Frames(.1)
        local growing = G(S[emoteLine].textHeight) .. " " .. G(S[warningLine].textHeight)
        Frames(.5)
        Equal(tostring(FadingFrame_UpdateTextScaling ~= plainGrowth) .. " " .. growing .. " | " .. G(S[emoteLine].textHeight) .. " "
            .. G(S[warningLine].textHeight), "true 37.5 25 | 30 20",
            "only Emote size changed: growth hooked, the emote at 150% as it grows and at rest, the raid warning Blizzard's")
        Equal(#printed, 0, "no errors with only Emote size changed")
    end

    -- A size changed after login, as the page's slider does: Blizzard's growing
    -- text hooked then, and the next warning keeps your size as it grows and
    -- rests. Other text Blizzard grows (loss of control) is never sized.
    do
        Environment()
        Viewers(0)
        Tracker()
        Warnings()
        Bosses()
        Game(nil)
        local plainGrowth = FadingFrame_UpdateTextScaling
        ns = Load({ raidWarnings = true })
        Fire("PLAYER_LOGIN")
        ns.Set("warningSize", 150)
        ns.RaidTimers:Apply()
        Say(WARNING)
        Frames(.1)
        local mid = string.format("%g", S[lines[1]].textHeight)
        Frames(.5)
        Equal(tostring(FadingFrame_UpdateTextScaling ~= plainGrowth) .. " " .. mid .. " " .. string.format("%g", S[lines[1]].textHeight),
            "true 37.5 30", "Warning size changed after login: growth hooked, 150% as it grows and at rest")
        local other = New("FontString")
        Seal(other)
        rawset(other, "textScalingMinHeight", 20)
        rawset(other, "textScalingMaxHeight", 30)
        rawset(other, "textScalingUpTime", .2)
        rawset(other, "textScalingDownTime", .4)
        rawset(other, "textScalingTime", 0)
        blizzardCalling = true
        FadingFrame_UpdateTextScaling(other, .1)
        blizzardCalling = false
        Equal(string.format("%g", S[other].textHeight) .. " " .. #printed, "25 0", "Blizzard's other growing text left alone")
    end

    -- Edit Mode's Boss Frames shows the boss bars as Blizzard left them: full
    -- (each bar's first PLAYER_ENTERING_WORLD fills it with no cast), with no
    -- name or icon. A full fill hides the track, so the addon's look showed
    -- only a coloured line. There the bars show empty in your design: the fill
    -- see-through while a bar isn't casting, shown again for every cast.
    Environment()
    Viewers(0)
    Tracker()
    Warnings()
    Bosses()
    Game(nil)
    for _, each in ipairs(bars) do Cast(each, "ui-castingbar-full-standard", true) end
    ns = Load({ bossCasts = true })
    Fire("PLAYER_LOGIN")
    boss = bars[1]
    Equal(Alpha(boss) .. " " .. S[boss].barTexture .. " " .. Pieces(boss), "1 " .. FLAT .. " 3",
        "outside Edit Mode: the fill as it is, in your texture, with the edge, track and shine")
    EditMode(true)
    Equal(Alpha(boss) .. " " .. Alpha(bars[5]) .. " " .. Pieces(boss) .. " " .. S[boss.Border].alpha, "0 0 3 0",
        "Boss Frames ticked: all five empty, the edge, track and shine showing, Blizzard's frame gone")
    -- A boss cast while it shows: Blizzard picks the fill before it marks the bar casting.
    Cast(boss, "ui-castingbar-filling-standard")
    Casting(boss, true)
    Equal(Alpha(boss) .. " " .. Colour(boss) .. " " .. Alpha(bars[2]), "1 1,0.7,0,1 0",
        "a boss cast in Edit Mode: its fill shows, gold; the other bars stay empty")
    -- Blizzard fills it as the cast ends, still marked casting, then clears the mark.
    Cast(boss, "ui-castingbar-full-standard", true)
    Equal(Alpha(boss), 1, "the cast ending: its fill still shows")
    Casting(boss, nil)
    EditMode(true)
    Equal(Alpha(boss), 0, "Boss Frames ticked again after it: empty again")
    -- A channel is marked channelling, not casting.
    Cast(boss, "ui-castingbar-filling-channel")
    Casting(boss, nil, true)
    EditMode(true)
    Equal(Alpha(boss) .. " " .. Colour(boss), "1 0,0.8,0,1", "a channel while Boss Frames is ticked again: shown, green")
    Casting(boss, nil, nil)
    -- A full fill with no cast (a loading screen) while Edit Mode shows them: still empty.
    Cast(boss, "ui-castingbar-full-standard", true)
    Equal(Alpha(boss), 0, "Blizzard's full fill with no cast in Edit Mode: still empty")
    -- Edit Mode closed: every fill shows again, for the next cast.
    EditMode(false)
    Equal(Alpha(boss) .. " " .. Alpha(bars[5]), "1 1", "Edit Mode closed: every fill shows again")
    Cast(boss, "ui-castingbar-full-standard", true)
    Equal(Alpha(boss), 1, "and a full fill outside Edit Mode shows")
    -- Unticked while Edit Mode shows them: Blizzard's own full bar back at
    -- once, and left alone after.
    EditMode(true)
    ns.Set("bossCasts", false)
    ns.RaidTimers:Apply()
    Equal(Alpha(boss) .. " " .. Alpha(bars[5]) .. " " .. S[boss.Border].alpha .. " " .. Pieces(boss), "1 1 1 0",
        "switched off in Edit Mode: Blizzard's fill and frame back, none of the addon's pieces")
    EditMode(true)
    Cast(boss, "ui-castingbar-full-standard", true)
    Equal(Alpha(boss), 1, "and left alone after, as Edit Mode refreshes and Blizzard fills it")
    -- Ticked while Edit Mode shows them: empty at once.
    ns.Set("bossCasts", true)
    ns.RaidTimers:Apply()
    Equal(Alpha(boss) .. " " .. Alpha(bars[5]) .. " " .. Pieces(boss), "0 0 3", "switched on in Edit Mode: empty at once")
    -- The window's preview is the addon's own bar: Edit Mode never empties it.
    local preview = ns.RaidTimers:SampleBoss(nil)
    S[preview.bar].fill = New("Texture", preview.bar)
    ns.RaidTimers:SampleLook(preview)
    Equal(S[S[preview.bar].fill].alpha, 1, "the page's preview keeps its fill in Edit Mode")
    EditMode(false)
    Equal(#printed, 0, "no errors in Edit Mode")

    -- EraUI's Classic cast bars style the boss bars while they're on: the
    -- boss bars are left to it, never hooked or touched.
    Environment()
    Viewers(0)
    Tracker()
    Warnings()
    Bosses()
    Game({ GetSetting = function(_, key) if key == "castBars" or key == "enabled" then return true end end })
    plainFill, plainShown = bars[1].UpdateBarFillTexture, box.UpdateShownState
    ns = Load({ bossCasts = true })
    Fire("PLAYER_LOGIN")
    Equal(tostring(bars[1].UpdateBarFillTexture == plainFill) .. " " .. tostring(S[bars[1].Border].alpha) .. " "
        .. tostring(ns.RaidTimers:BossOwner()), "true 1 EraUI", "EraUI's Cast Bars on: the boss bars are EraUI's")
    Cast(bars[1], "ui-castingbar-filling-standard")
    Equal(S[bars[1]].barTexture, "ui-castingbar-filling-standard", "Blizzard's fill, left as it is")
    EditMode(true)
    Equal(tostring(box.UpdateShownState == plainShown) .. " " .. Alpha(bars[1]), "true 1",
        "EraUI's, Boss Frames in Edit Mode: their container never hooked, the fill left as it is")
    EditMode(false)
    -- Off in EraUI: the addon styles them.
    Environment()
    Viewers(0)
    Tracker()
    Warnings()
    Bosses()
    local eraCastBars = false
    Game({ GetSetting = function(_, key)
        if key == "enabled" then return true end
        if key == "castBars" then return eraCastBars end
    end })
    ns = Load({ bossCasts = true })
    Fire("PLAYER_LOGIN")
    Equal(tostring(ns.RaidTimers:BossOwner()) .. " " .. S[bars[1].Border].alpha, "nil 0", "EraUI's Cast Bars off: the addon's look")
    -- EraUI taking them back later, with the hooks in: handed back at once,
    -- and Blizzard's next fill left to EraUI.
    eraCastBars = true
    ns.RaidTimers:Apply()
    Cast(bars[1], "ui-castingbar-filling-channel")
    Equal(tostring(ns.RaidTimers:BossOwner()) .. " " .. S[bars[1].Border].alpha .. " " .. S[bars[1]].barTexture,
        "EraUI 1 ui-castingbar-filling-channel", "EraUI's again later: handed back, the next cast left as it is")
    -- EraUI switched off as a whole: its skins don't run, so the addon's.
    Environment()
    Viewers(0)
    Tracker()
    Warnings()
    Bosses()
    Game({ GetSetting = function(_, key) return key ~= "enabled" end })
    ns = Load({ bossCasts = true })
    Fire("PLAYER_LOGIN")
    Equal(tostring(ns.RaidTimers:BossOwner()) .. " " .. S[bars[1].Border].alpha, "nil 0", "EraUI switched off: the addon's look")
    -- An EraUI whose settings can't be read: left to it, so the two never both style them.
    Environment()
    Viewers(0)
    Tracker()
    Warnings()
    Bosses()
    Game({})
    ns = Load({ bossCasts = true })
    Fire("PLAYER_LOGIN")
    Equal(tostring(ns.RaidTimers:BossOwner()) .. " " .. S[bars[1].Border].alpha, "EraUI 1", "EraUI that can't say: left to EraUI")

    -- A current EraUI shares the boss bars: at its login it says so through
    -- the public API, and steps back while this part styles them, so the
    -- switch decides even with its Cast Bars on. It hears each change of
    -- hands: taking, before this look goes on; handing back, after
    -- Blizzard's is back. first: its login runs before the addon's.
    local era
    local function SharingEraUI(first)
        era = { heard = {} }
        era.GetSetting = function(_, key) if key == "castBars" or key == "enabled" then return true end end
        Game(era)
        local function Login()
            local watch = CreateFrame("Frame")
            watch:RegisterEvent("PLAYER_LOGIN")
            watch:SetScript("OnEvent", function()
                era.callback = function()
                    local boss = bars[1]
                    table.insert(era.heard, tostring(ForeverEnhancedCooldownManagerAPI.StylesBossCastBars()) .. " "
                        .. S[boss.Border].alpha .. " " .. S[boss.TextBorder].alpha .. " " .. tostring(S[boss.Text].font))
                end
                era.shared = ForeverEnhancedCooldownManagerAPI.ShareBossCastBars("EraUI", era.callback)
            end)
        end
        return Login
    end
    local API = function() return ForeverEnhancedCooldownManagerAPI end
    -- Its login first, the switch on: the addon's look once it logs in.
    Environment()
    Viewers(0)
    Tracker()
    Warnings()
    Bosses()
    SharingEraUI(true)()
    plainFill = bars[1].UpdateBarFillTexture
    ns = Load({ bossCasts = true })
    Equal(tostring(API().StylesBossCastBars()) .. " " .. S[bars[1].Border].alpha, "false 1", "before login: not styling, nothing touched")
    Fire("PLAYER_LOGIN")
    Equal(tostring(era.shared) .. " " .. tostring(ns.RaidTimers:BossOwner()) .. " " .. tostring(ns.RaidTimers:SharedBy("EraUI")),
        "true nil true", "a sharing EraUI, its Cast Bars on: the bars are the switch's to decide")
    Equal(#era.heard .. " " .. tostring(era.heard[1]), "1 true 1 1 nil",
        "it heard once, told the addon styles them, before this look went on")
    Equal(tostring(API().StylesBossCastBars()) .. " " .. S[bars[1].Border].alpha .. " " .. S[bars[5].TextBorder].alpha
        .. " " .. S[bars[1].Text].font .. " " .. tostring(bars[1].UpdateBarFillTexture ~= plainFill),
        "true 0 0 FECMFont10 true", "then the addon's look, on all five, the fill hooked")
    Cast(bars[1], "ui-castingbar-filling-channel")
    Equal(Colour(bars[1]), "0,0.8,0,1", "a boss channel in the addon's green, EraUI's Cast Bars on")
    -- Unticked: Blizzard's look back first, then EraUI hears, and gets them.
    ns.Set("bossCasts", false)
    ns.RaidTimers:Apply()
    Equal(#era.heard .. " " .. tostring(era.heard[2]), "2 false 1 1 SystemFont_Shadow_Small",
        "unticked: EraUI heard after Blizzard's look was back")
    Equal(tostring(API().StylesBossCastBars()), "false", "and the API says so")
    -- Then they're EraUI's: the addon leaves them alone, whatever changes.
    S[bars[1].TextBorder].alpha, S[bars[1].Border].alpha = 0, .5
    ns.Set("barStyle", "split")
    ns.RaidTimers:Apply()
    ns.Set("barStyle", "glass")
    ns.RaidTimers:Apply()
    Cast(bars[1], "ui-castingbar-filling-standard")
    Equal(S[bars[1].TextBorder].alpha .. " " .. S[bars[1].Border].alpha .. " " .. S[bars[1]].barTexture .. " " .. #era.heard,
        "0 0.5 ui-castingbar-filling-standard 2", "EraUI's again: never touched by the addon, as choices change and bosses cast")
    -- Ticked again: EraUI hears first again.
    ns.Set("bossCasts", true)
    ns.RaidTimers:Apply()
    Equal(#era.heard .. " " .. tostring(era.heard[3]) .. " " .. S[bars[1].Border].alpha, "3 true 0.5 0 SystemFont_Shadow_Small 0",
        "ticked again: EraUI heard first, then the addon's look")
    ns.RaidTimers:Apply()
    Equal(#era.heard, 3, "a choice changed while it's on: no change of hands, nothing heard")
    Equal(#printed, 0, "no errors handing over")

    -- Its login after the addon's: the addon waits for EraUI's Cast Bars at
    -- first, then takes the bars as EraUI shares them.
    Environment()
    Viewers(0)
    Tracker()
    Warnings()
    Bosses()
    local login = SharingEraUI(false)
    ns = Load({ bossCasts = true })
    login()
    Fire("PLAYER_LOGIN")
    Equal(#era.heard .. " " .. tostring(era.heard[1]) .. " " .. S[bars[1].Border].alpha .. " " .. tostring(API().StylesBossCastBars()),
        "1 true 1 1 nil 0 true", "EraUI's login second: heard as the addon took them, then the addon's look")

    -- Switch off with a sharing EraUI: nothing heard, nothing hooked or touched.
    Environment()
    Viewers(0)
    Tracker()
    Warnings()
    Bosses()
    SharingEraUI(true)()
    plainFill = bars[1].UpdateBarFillTexture
    ns = Load({ bossCasts = false })
    Fire("PLAYER_LOGIN")
    Equal(#era.heard .. " " .. S[bars[1].Border].alpha .. " " .. tostring(bars[1].UpdateBarFillTexture == plainFill) .. " "
        .. tostring(API().StylesBossCastBars()), "0 1 true false", "switch off: EraUI keeps them, nothing hooked, nothing heard")

    -- Every EraUI with the switch on and off: who styles the boss bars.
    for _, case in ipairs({
        { "no EraUI", nil, true, "true 0" }, { "no EraUI", nil, false, "false 1" },
        { "an older EraUI, Cast Bars on", "on", true, "false 1" }, { "an older EraUI, Cast Bars on", "on", false, "false 1" },
        { "EraUI's Cast Bars off", "off", true, "true 0" }, { "EraUI's Cast Bars off", "off", false, "false 1" },
        { "a sharing EraUI", "sharing", true, "true 0" }, { "a sharing EraUI", "sharing", false, "false 1" },
    }) do
        Environment()
        Viewers(0)
        Tracker()
        Warnings()
        Bosses()
        if case[2] == "sharing" then
            SharingEraUI(true)()
        elseif case[2] then
            Game({ GetSetting = function(_, key) if key == "enabled" then return true end if key == "castBars" then return case[2] == "on" end end })
        else
            Game(nil)
        end
        ns = Load({ bossCasts = case[3] })
        Equal(API().StylesBossCastBars(), false, case[1] .. ", switch " .. (case[3] and "on" or "off") .. ": before login, not yet")
        Fire("PLAYER_LOGIN")
        Equal(tostring(API().StylesBossCastBars()) .. " " .. S[bars[3].Border].alpha, case[4],
            case[1] .. ", switch " .. (case[3] and "on" or "off"))
    end

    -- The API is read-only, checks what it's given, and a listener's error stays its own.
    Equal(API().version .. " " .. tostring(getmetatable(API())), "1 false", "version 1, its metatable hidden")
    Equal(pcall(function() API().StylesBossCastBars = function() return true end end), false, "can't be written")
    -- (A name nobody has shared under yet, so only the missing function refuses it.)
    Equal(tostring(API().ShareBossCastBars(nil, print)) .. " " .. tostring(API().ShareBossCastBars("Someone", "x")) .. " "
        .. tostring(API().ShareBossCastBars("", print)) .. " " .. tostring(ns.RaidTimers:SharedBy("EraUI")) .. " "
        .. tostring(ns.RaidTimers:SharedBy("Someone")) .. " " .. tostring(ns.RaidTimers:SharedBy("")), "false false false true false false",
        "an addon's name and a function needed")
    -- The first to share under a name keeps it: another callback under EraUI's
    -- name is refused and never heard, so it can't cut EraUI off; EraUI's own
    -- again is fine, and changes nothing.
    local squatter = 0
    local heard = #era.heard
    Equal(tostring(API().ShareBossCastBars("EraUI", function() squatter = squatter + 1 end)) .. " "
        .. tostring(API().ShareBossCastBars("EraUI", era.callback)) .. " " .. #era.heard, "false true " .. heard,
        "EraUI's name taken: another refused, EraUI's own again fine, nothing heard")
    Equal(API().ShareBossCastBars("Another", function() error("its own trouble") end), true, "another addon can share them")
    ns.Set("bossCasts", true)
    ns.RaidTimers:Apply()
    Equal(tostring(API().StylesBossCastBars()) .. " " .. S[bars[1].Border].alpha .. " " .. #printed, "true 0 0",
        "a listener that fails: taken all the same, nothing reported")
    ns.Set("bossCasts", false)
    ns.RaidTimers:Apply()
    Equal(tostring(API().StylesBossCastBars()) .. " " .. S[bars[1].Border].alpha .. " " .. #printed, "false 1 0",
        "and handed back all the same")
    Equal(squatter .. " " .. (#era.heard - heard) .. " " .. tostring(era.heard[#era.heard - 1]):match("^%a+") .. " "
        .. tostring(era.heard[#era.heard]):match("^%a+"), "0 2 true false",
        "EraUI heard both changes of hands, the refused one neither")
    ns.Set("bossCasts", true)
    ns.RaidTimers:Apply()
    Equal(tostring(API().StylesBossCastBars()) .. " " .. S[bars[1].Border].alpha .. " " .. #printed, "true 0 0", "and taken again")

    -- Blizzard's raid warnings loading late are hooked as they load.
    Environment()
    Viewers(0)
    Tracker()
    Bosses()
    Game(nil)
    _G.RaidWarningFrame = nil
    ns = Load({ raidWarnings = true })
    Fire("PLAYER_LOGIN")
    Warnings()
    Fire("ADDON_LOADED", "Blizzard_RaidWarning")
    Say(WARNING)
    Equal(S[lines[1]].face, "Fonts\\FRIZQT__.TTF 20 OUTLINE", "raid warnings loaded late: restyled")
    -- A boss emote added while the part is off, then put in your colour and
    -- back: Blizzard's usual colour for boss emotes, as its own wasn't seen.
    _G.ChatTypeInfo = { RAID_WARNING = { r = .9, g = .3, b = .1 }, RAID_BOSS_EMOTE = { r = .9, g = .8, b = .1 } }
    ns.Set("raidWarnings", false)
    ns.RaidTimers:Apply()
    Say(EMOTE, 2)
    local late = lines[2]
    Equal(S[late].face, nil, "added while off: left as Blizzard's")
    ns.Set("raidWarnings", true)
    ns.RaidTimers:Apply()
    Equal(S[late].face .. " " .. table.concat(S[late].textColour, ","), "Fonts\\FRIZQT__.TTF 20 OUTLINE 1,0.867,0",
        "ticked on: dressed, and still in the colour Blizzard gave it")
    ns.Set("emoteColour", "red")
    ns.RaidTimers:Apply()
    Equal(table.concat(S[late].textColour, ","), "1,0.25,0.2", "ticked on: the boss emote showing in your red")
    ns.Set("emoteColour", "default")
    ns.RaidTimers:Apply()
    Equal(table.concat(S[late].textColour, ","), "0.9,0.8,0.1", "Blizzard's colour again: its usual one for boss emotes")
    _G.ChatTypeInfo = nil
    Equal(#printed, 0, "no errors")
    _G.issecretvalue = nil
    _G.C_AddOns, _G.EraUI = nil, nil
end

-- Nothing was ever left on a sealed frame, even by rawset, which skips the seal.
do
    local count, written = 0, nil
    for frame in pairs(sealed) do
        count = count + 1
        written = written or next(frame)
    end
    Equal(tostring(count > 100) .. " " .. tostring(written), "true nil", "no key left on any of Blizzard's frames")
end

print = _G.print
Equal(SecretMisuse[1], nil, "no secret misused anywhere")
io.write("Forever Enhanced Cooldown Manager checks passed: " .. checks .. " assertions.\n")
