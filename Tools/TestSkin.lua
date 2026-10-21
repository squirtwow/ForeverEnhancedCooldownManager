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
-- sized at 100%, and the boss frames and their cast bars never are. Icon
-- details: a cooldown icon's or buff icon's own cooldown allows its swipe's
-- colour and its edge line (on, off and colour), the cosmetic setters only,
-- never whether it draws its swipe. Colour fade: a bar's fill allows its
-- gradient, a cosmetic setter too, and nothing else of Blizzard's does.
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
    SetValue = true, SetMinMaxValues = true, SetText = true, SetFormattedText = true, ClearText = true, SetTextHeight = true,
    SetMaxLines = true, GetNumLines = true, GetStringWidth = true, GetStringHeight = true,
    -- Every other way to size one, besides SetScale, SetSize, SetWidth and SetHeight.
    SetTextScale = true, SetFontHeight = true, SetIgnoreParentScale = true,
    -- Its scripts, events, mouse, strata and secure attributes: Blizzard's own.
    SetScript = true, EnableMouse = true, SetFrameStrata = true, RegisterEvent = true, RegisterUnitEvent = true,
    UnregisterEvent = true, UnregisterAllEvents = true, SetAttribute = true,
    -- A cooldown's edge line: only where a part allows it (Icon details).
    SetDrawEdge = true, SetEdgeColor = true,
    -- A gradient: only on a bar's fill, where it allows it (Colour fade).
    SetGradient = true,
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
-- Like the game, a bar's colour wipes a gradient on its fill (Colour fade).
function Proto:SetStatusBarColor(r, g, b, a)
    S[self].barColour = { r, g, b, a }
    local fill = S[self].fill
    if fill and S[fill] then S[fill].gradient = nil end
end
-- A fill's gradient (Colour fade), and how many times one was put on.
function Proto:SetGradient(orientation, from, to)
    local s = S[self]
    s.gradient, s.gradients = { orientation, from, to }, (s.gradients or 0) + 1
end
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
-- A cooldown's swipe colour and edge line (Icon details), Blizzard's or the
-- addon's: each call the addon makes is counted.
local function Counted(self) if not blizzardCalling then S[self].addonCalls = (S[self].addonCalls or 0) + 1 end end
function Proto:SetSwipeColor(r, g, b, a) Counted(self); S[self].swipeColour = { r, g, b, a } end
function Proto:SetDrawEdge(v) Counted(self); S[self].edge = v end
function Proto:SetEdgeColor(r, g, b, a) Counted(self); S[self].edgeColour = { r, g, b, a } end
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
function Proto:SetText(t) S[self].text, S[self].format, S[self].args = t, nil, nil end
function Proto:GetText() return S[self].text end
-- Text from a format, as the game's own code would take it: what it was
-- handed is kept as it was, a secret too, and never looked at here.
-- Like the game, the addon's own text needs its font first.
function Proto:SetFormattedText(format, ...)
    local s = S[self]
    if not s.blizzard and s.kind == "FontString" and s.font == nil then error("FontString:SetFormattedText(): Font not set", 2) end
    s.text, s.format, s.args = nil, format, table.pack(...)
    s.writes = (s.writes or 0) + 1
end
-- Like the game: shown, and so is everything it sits in.
function Proto:IsVisible()
    local at = self
    while at and S[at] do
        if not S[at].shown then return false end
        at = S[at].parent
    end
    return true
end
function Proto:SetChecked(v) S[self].checked = v end
function Proto:GetChecked() return S[self].checked end
function Proto:GetFont() return "font", 12, "" end
-- The spell Blizzard's settings give a Tracked Bar.
function Proto:GetBaseSpellID() return S[self].baseSpell end
-- Raid Timers: what the restyle sets on Blizzard's countdown, raid warnings
-- and boss cast bars, where each part allows it.
function Proto:GetDrawLayer() return S[self].layer end
function Proto:GetStatusBarTexture() return S[self].fill end
function Proto:SetVertexColor(r, g, b, a) S[self].tint, S[self].tintAlpha = { r, g, b }, a end
-- A texture's file, where a part allows it to be set.
function Proto:SetTexture(file) S[self].file = file end
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
    S[item.Cooldown].allow = { SetSwipeColor = true, SetDrawEdge = true, SetEdgeColor = true } -- Icon details
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
    S[item.Cooldown].allow = { SetSwipeColor = true, SetDrawEdge = true, SetEdgeColor = true } -- Icon details
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

-- Darkness and thick edges (Look page): the empty part from today's track to
-- solid black, Glass's shine kept to the fill, and a second pixel inside
-- each edge. Both off by default, so the bar is as it was: the addon's own
-- textures, and only cosmetic setters on Blizzard's.
do
    local function All(owner, layer, sublevel)
        local found = {}
        for _, r in ipairs(S[owner].regions) do
            if S[r].layer == layer and S[r].sublevel == sublevel then found[#found + 1] = r end
        end
        return found
    end
    local function Points(region)
        local out = {}
        for i, p in ipairs(S[region].points) do
            local rel = p[2] == bar.Bar and "bar" or p[2] == S[bar.Bar].fill and "fill" or tostring(p[2])
            out[i] = p[1] .. " " .. rel .. " " .. p[3] .. " " .. p[4] .. " " .. p[5]
        end
        return table.concat(out, ", ")
    end
    local function Colour(region)
        local c = S[region].color
        return string.format("%g %g %g %g", c[1], c[2], c[3], c[4])
    end
    local function Shown(ring)
        local list = {}
        for i, strip in ipairs(ring) do list[i] = tostring(S[strip].shown) end
        return table.concat(list, " ")
    end
    local over = sheen
    local function Made() return #All(bar.Bar, "OVERLAY", -8) .. " " .. #All(bar.Bar, "OVERLAY", -5) .. " " .. #All(bar.Icon, "OVERLAY", -5) end
    Equal(ns.Get("barDarkness") .. " " .. tostring(ns.Get("thickEdges")) .. " | " .. Colour(bar.Bar.BarBG) .. " | " .. Made(),
        "0 false | 0.08 0.08 0.09 0.85 | 1 0 0", "off by default: today's track and one shine, nothing more made")
    Equal(Points(over) .. " | " .. S[over].height .. " " .. tostring(S[over].shown), "TOPLEFT bar TOPLEFT 0 0, TOPRIGHT bar TOPRIGHT 0 0 | 11 true",
        "and today's shine across the whole top, nothing else over the empty part")
    -- Blizzard's fill, as the game hands it back: nothing is ever called on it.
    local fill = New("Texture", bar.Bar)
    Seal(fill)
    S[bar.Bar].fill = fill
    ns.Skin:ApplyBarLook()
    Equal(Points(over) .. " | " .. Made(), "TOPLEFT bar TOPLEFT 0 0, TOPRIGHT bar TOPRIGHT 0 0 | 1 0 0",
        "with darkness at 0 the fill is never asked about: the shine stays whole")
    ns.Set("barDarkness", 100)
    ns.Skin:ApplyBarLook()
    local rest = All(bar.Bar, "OVERLAY", -8)[2]
    Equal(Colour(bar.Bar.BarBG) .. " | " .. Made(), "0 0 0 1 | 2 0 0", "darkness 100: Blizzard's backing solid black, and the empty part's shine made")
    Equal(Points(over) .. " | " .. Points(rest), "TOPLEFT bar TOPLEFT 0 0, TOPRIGHT fill TOPRIGHT 0 0 | TOPLEFT fill TOPRIGHT 0 0, TOPRIGHT bar TOPRIGHT 0 0",
        "the shine split where the fill ends")
    Equal(string.format("%g %g %s %g", S[over].color[4], S[rest].color[4], tostring(S[rest].shown), S[rest].height), "0.16 0 true 11",
        "the fill keeps its shine, the empty part's is gone, the same strip along the top")
    ns.Set("barDarkness", 50)
    ns.Skin:ApplyBarLook()
    Equal(string.format("%g %g %g | %g %g", S[bar.Bar.BarBG].color[1], S[bar.Bar.BarBG].color[3], S[bar.Bar.BarBG].color[4],
        S[over].color[4], S[rest].color[4]), "0.04 0.045 0.925 | 0.16 0.08", "halfway: halfway to black, half the empty part's shine")
    -- As Blizzard gives the bar a spell after a relayout: nothing set or
    -- asked again; a Look page redraw with nothing new doesn't move the shine.
    local watched = { [over] = true, [rest] = true }
    local set, asked, SetPoint, SetColor, GetFill = 0, 0, Proto.SetPoint, Proto.SetColorTexture, Proto.GetStatusBarTexture
    function Proto:SetPoint(...) if watched[self] then set = set + 1 end SetPoint(self, ...) end
    function Proto:SetColorTexture(...) if watched[self] then set = set + 1 end SetColor(self, ...) end
    function Proto:GetStatusBarTexture() asked = asked + 1; return GetFill(self) end
    Blizzard(bar, "OnCooldownIDSet")
    local relayout = set .. " " .. asked
    ns.Skin:ApplyBarLook()
    Equal(relayout .. " | " .. set, "0 0 | 0", "a relayout sets and asks nothing; a redraw leaves the shine and edges as they are")
    Proto.SetPoint, Proto.SetColorTexture, Proto.GetStatusBarTexture = SetPoint, SetColor, GetFill
    -- A new fill (a texture picked can bring one): the shine follows it.
    local newFill = New("Texture", bar.Bar)
    Seal(newFill)
    S[bar.Bar].fill = newFill
    ns.Skin:ApplyBarLook()
    Equal(S[over].points[2][2] == newFill and S[rest].points[1][2] == newFill, true, "a new fill: the shine split at it")
    S[bar.Bar].fill = fill
    ns.Skin:ApplyBarLook()
    -- Split and Outline have no shine at all.
    ns.Set("barStyle", "split")
    ns.Skin:ApplyBarLook()
    Equal(tostring(S[over].shown) .. " " .. tostring(S[rest].shown), "false false", "Split: no shine, either part")
    ns.Set("barStyle", "glass")
    -- Thick edges: a 1px ring just inside the bar's edge and the icon's, over
    -- the fill, under the text; nothing resized. Made as it's first shown.
    ns.Set("thickEdges", true)
    ns.Skin:ApplyBarLook()
    local ring, iconRing = All(bar.Bar, "OVERLAY", -5), All(bar.Icon, "OVERLAY", -5)
    Equal(Shown(ring) .. " | " .. Shown(iconRing), "true true true true | true true true true", "thick edges: the bar and its icon")
    Equal(Colour(ring[1]) .. " | " .. Colour(iconRing[1]), "0 0 0 1 | 0 0 0 1", "black, like their edges")
    local top, left = S[ring[1]].points, S[ring[3]].points
    Equal(table.concat({ top[1][1], tostring(top[1][2] == bar.Bar), top[1][3], top[1][4], top[1][5], S[ring[1]].height,
        left[1][1], left[1][3], left[1][4], left[1][5], S[ring[3]].width }, " "), "BOTTOMLEFT true TOPLEFT 0 -1 1 TOPRIGHT TOPLEFT 1 -1 1",
        "the second pixel inside the bar, not outside it")
    Equal(S[iconRing[1]].points[1][2] == bar.Icon.Icon and InsetBy(iconEdge, bar.Icon.Icon, -1) and InsetBy(barEdge, bar.Bar, -1)
        and S[bar.Bar].height, 26, "round the icon's art; the 1px edges and the bar's height as they were")
    ns.Set("barStyle", "outline")
    ns.Set("barColour", "blue")
    ns.Skin:ApplyBarLook()
    Equal(S[ring[1]].color[3] .. " " .. S[iconRing[1]].color[3], "0.88 0.88", "Outline: in the bar's colour, like its edges")
    -- And off again: today's look.
    ns.Set("barStyle", "glass")
    ns.Set("barColour", "orange")
    ns.Set("barDarkness", 0)
    ns.Set("thickEdges", false)
    ns.Skin:ApplyBarLook()
    Equal(Colour(bar.Bar.BarBG) .. " | " .. Points(over) .. " " .. tostring(S[over].shown) .. " " .. tostring(S[rest].shown) .. " | "
        .. Shown(ring) .. " | " .. Shown(iconRing),
        "0.08 0.08 0.09 0.85 | TOPLEFT bar TOPLEFT 0 0, TOPRIGHT bar TOPRIGHT 0 0 true false | false false false false | false false false false",
        "both off: the track, the whole shine and the 1px edges as before")
    Equal(#printed, 0, "no errors from the darkness or edges")
end

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
    -- Custom (the colour pop-up): its own colour kept beside it, found from
    -- any rank as the colour is, and drawn; a named colour keeps it beside
    -- (moved with it), Custom again takes it, and the colour for all lets
    -- both go.
    colours.barColours = {}
    ns.SetBarColour(782, ns.CUSTOM, "336699")
    ns.Skin:ApplyBarLook()
    local saved, custom = ns.BarColours()
    Equal(tostring(saved[782]) .. " " .. tostring(custom[782]) .. " " .. ns.BarColourFor(467) .. " " .. S[bar.Bar].barColour[3],
        "custom 336699 #336699 0.6", "Custom: kept beside, found from any rank, drawn")
    ns.SetBarColour(9910, "green")
    saved, custom = ns.BarColours()
    Equal(tostring(saved[782]) .. " " .. tostring(saved[9910]) .. " " .. tostring(custom[9910]) .. " " .. ns.BarColourFor(467),
        "nil green 336699 green", "a named colour at another rank: under that ID, the custom one moved beside it")
    ns.SetBarColour(467, ns.CUSTOM)
    Equal(ns.BarColourFor(467), "#336699", "Custom again: the one kept")
    ns.SetBarColour(467, nil)
    saved, custom = ns.BarColours()
    Equal(tostring(next(saved)) .. " " .. tostring(next(custom)), "nil nil", "the colour for all: both go")
    -- Repaired as read: Custom with none kept goes; one kept beside a named
    -- colour stays, in lower case; one for no bar goes.
    colours.barColours = { [467] = "custom", [782] = "custom", [1126] = "blue" }
    colours.barCustom = { [782] = "ABCDEF", [1126] = "00ff00", [5] = "zz" }
    saved, custom = ns.BarColours()
    local list = {}
    for id, key in pairs(saved) do list[#list + 1] = id .. "=" .. key .. "/" .. tostring(custom[id]) end
    for id in pairs(custom) do if not saved[id] then list[#list + 1] = id .. " kept for no bar" end end
    table.sort(list)
    Equal(table.concat(list, " "), "1126=blue/00ff00 782=custom/abcdef", "Custom needs its own colour; a kept one in lower case")
    colours.barColours, colours.barCustom = {}, {}
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
-- The darkness and thick edges too, its shine split where its fill ends.
do
    S[sample.Bar].fill = New("Texture", sample.Bar)
    ns.Set("barDarkness", 100)
    ns.Set("thickEdges", true)
    ns.Skin:ApplyBarLook()
    local shine, ring = {}, {}
    for _, r in ipairs(S[sample.Bar].regions) do
        if S[r].layer == "OVERLAY" and S[r].sublevel == -8 then shine[#shine + 1] = r end
        if S[r].layer == "OVERLAY" and S[r].sublevel == -5 then ring[#ring + 1] = r end
    end
    Equal(string.format("%g %s %s %s", S[sample.Bar.BarBG].color[4], tostring(S[shine[2]].shown),
        tostring(S[shine[2]].points[1][2] == S[sample.Bar].fill), tostring(S[ring[1]].shown)), "1 true true true",
        "the preview shows the darkness, the shine split at its fill, and thick edges")
    ns.Set("barDarkness", 0)
    ns.Set("thickEdges", false)
    ns.Skin:ApplyBarLook()
    Equal(string.format("%g %s %s", S[sample.Bar.BarBG].color[4], tostring(S[shine[2]].shown), tostring(S[ring[1]].shown)),
        "0.85 false false", "and today's look again")
end

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
local UI_STATUSBAR, BAR_FILL = "Interface\\TargetingFrame\\UI-StatusBar", "Interface/TargetingFrame/UI-TargetingFrame-BarFill"
-- The pieces Blizzard draws beside the bars' fills (bare: a display without
-- them), and its own text on each bar (Edit Mode's Show Bar Text).
local function PRDPieces(frame, container, health)
    local power = frame.PowerBar
    -- What a cast will cost, at the end of the mana bar: Blizzard's file, in its prediction blue.
    local cost = New("Texture", power)
    S[cost].file, S[cost].tint, S[cost].layer = UI_STATUSBAR, { 0, .447, 1 }, "ARTWORK"
    power.ManaCostPredictionBar = cost
    -- The flash of power just spent, on a frame of its own over the bar.
    local feedback = New("Frame", power)
    feedback.BarTexture = New("Texture", feedback)
    S[feedback.BarTexture].file = UI_STATUSBAR
    power.FeedbackFrame = feedback
    -- Heals on the way, and the shield's stripes and glow, which keep Blizzard's own art.
    for _, key in ipairs({ "myHealPrediction", "otherHealPrediction", "totalAbsorb", "totalAbsorbOverlay", "overAbsorbGlow" }) do
        health[key] = New("Texture", health)
        S[health[key]].layer = "BORDER"
    end
    S[health.myHealPrediction].file, S[health.otherHealPrediction].file = BAR_FILL, BAR_FILL
    -- The health bar's lost max health, a bar of its own at level 100.
    container.TempMaxHealthLoss = New("StatusBar", container)
    S[container.TempMaxHealthLoss].level = 100
    -- The power bar's full-power pulse: a frame a level above the bar, its
    -- spike and glow frames a level above that.
    local pulse = New("Frame", power)
    S[pulse].level = 2
    for _, key in ipairs({ "SpikeFrame", "PulseFrame" }) do
        pulse[key] = New("Frame", pulse)
        S[pulse[key]].level = 3
    end
    power.FullPowerFrame = pulse
end
local function PRDText(...)
    for _, bar in ipairs({ ... }) do
        for _, key in ipairs({ "TextString", "LeftText", "RightText" }) do bar[key] = New("FontString", bar) end
    end
end
-- Once sealed: the pieces the restyle may set, and the shield's art, which it may not.
local function PRDAllow(frame, health)
    local power = frame.PowerBar
    if not rawget(power, "ManaCostPredictionBar") then return end
    S[power.ManaCostPredictionBar].allow = { SetTexture = true, SetVertexColor = true }
    S[power.FeedbackFrame.BarTexture].allow = { SetTexture = true, SetVertexColor = true }
    S[health.myHealPrediction].allow, S[health.otherHealPrediction].allow = { SetTexture = true }, { SetTexture = true }
    for _, key in ipairs({ "totalAbsorb", "totalAbsorbOverlay", "overAbsorbGlow" }) do
        S[health[key]].deny = { SetTexture = true, SetAlpha = true, SetVertexColor = true, SetAtlas = true, SetColorTexture = true,
            SetBlendMode = true }
    end
end
-- Blizzard's colours for what a cast will cost, which the game loads from its
-- own data: mana's (the display's own default), and one for energy here.
local function PredictionColour(r, g, b) return { r = r, g = g, b = b, a = 1, GetRGBA = function(c) return c.r, c.g, c.b, c.a end } end
_G.POWERBAR_PREDICTION_COLOR_MANA = PredictionColour(0, .447, 1)
_G.PowerBarColor = { MANA = { r = 0, g = 0, b = 1, predictionColor = _G.POWERBAR_PREDICTION_COLOR_MANA },
    ENERGY = { r = 1, g = 1, b = 0, predictionColor = PredictionColour(1, .85, .4) } }
_G.PowerBarColor[0], _G.PowerBarColor[3] = _G.PowerBarColor.MANA, _G.PowerBarColor.ENERGY
-- Like the game, a secret can't look anything up: one used as a key here is a misuse.
setmetatable(_G.PowerBarColor, { __index = function(_, key)
    for _, secret in pairs(SECRETS) do
        if rawequal(key, secret) then SecretMisuse[#SecretMisuse + 1] = "PowerBarColor looked up with a secret" end
    end
end })
local function PRD(bare)
    local frame = New("Frame")
    local container = New("Frame", frame)
    frame.HealthBarsContainer = container
    local health, healthArt = PRDBar({ 0, 1, 0, 1 })
    container.healthBar = health
    frame.PowerBar = PRDBar({ 0, 0, 1, 1 })
    frame.AlternatePowerBar = PRDBar({ 0, 0, 1, 1 })
    frame.AlternatePowerBar.powerName = "MANA"
    if not bare then
        PRDPieces(frame, container, health)
        PRDText(health, frame.PowerBar, frame.AlternatePowerBar)
    end
    -- Blizzard sets the power bar up: its spent flash tinted like the bar
    -- again (BuilderSpenderFrame's Initialize), in its mana blue here, and,
    -- as your power type changes, what a cast will cost in its colour for
    -- that power (or mana's).
    local token0
    frame.UpdatePowerBar = function(self)
        local feedback = rawget(self.PowerBar, "FeedbackFrame")
        if not feedback then return end
        local was = blizzardCalling
        blizzardCalling = true
        feedback.BarTexture:SetVertexColor(0, 0, 1)
        local _, token = UnitPowerType("player")
        if token ~= token0 then
            token0 = token
            local info = PowerBarColor[token]
            self.PowerBar.ManaCostPredictionBar:SetVertexColor((info and info.predictionColor or POWERBAR_PREDICTION_COLOR_MANA):GetRGBA())
        end
        blizzardCalling = was
    end
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
    PRDAllow(frame, health)
    return frame, healthArt
end
local power = 0 -- the main bar's power: 0 mana, 3 energy
Environment()
Viewers(0)
_G.UnitPowerType = function() return power, power == 3 and "ENERGY" or "MANA" end
local prd, healthArt = PRD()
_G.PersonalResourceDisplayFrame = prd
ns = Load(nil)
local health = prd.HealthBarsContainer.healthBar
Equal(S[health].barTexture, "Interface\\Buttons\\WHITE8X8", "personal health bar made flat")
Equal(S[healthArt].color[1] == .08 and S[healthArt].color[4], .85, "its art swapped for the near-black track")
Equal(InsetBy(healthArt, health, 0), true, "fitted to the bar")
Equal(S[Piece(health, "BACKGROUND", -8)].color[1] == 0 and S[Piece(health, "OVERLAY", -8)].shown, true, "Glass: a black edge and a shine")
Equal(S[health].barColour[2] == 1 and S[health].barColour[1], 0, "Blizzard's green kept by default")
-- Blizzard's pieces beside the fills take the texture too: what a cast will
-- cost, heals on the way and the flash of power just spent. Only their
-- texture, alpha and the flash's tint (and the cost's, on a colour of yours:
-- below); the shield's art is left alone.
do
    local cost, flash = prd.PowerBar.ManaCostPredictionBar, prd.PowerBar.FeedbackFrame.BarTexture
    Equal(S[cost].file .. " " .. S[health.myHealPrediction].file .. " " .. S[health.otherHealPrediction].file .. " " .. S[flash].file,
        FLAT .. " " .. FLAT .. " " .. FLAT .. " " .. FLAT, "what a cast will cost, heals on the way and the spent flash: flat like the bars")
    Equal(table.concat(S[cost].tint, ",") .. " " .. S[cost].alpha .. " " .. S[health.myHealPrediction].alpha, "0,0.447,1 1 1",
        "the cost still in Blizzard's own blue, and nothing see-through")
    local untouched = true
    for _, key in ipairs({ "totalAbsorb", "totalAbsorbOverlay", "overAbsorbGlow" }) do
        local s = S[health[key]]
        if s.file or s.alpha ~= 1 or s.tint or next(s.calls) then untouched = false end
    end
    Equal(untouched, true, "the shield's stripes and glow keep Blizzard's own art")
    Equal(table.concat(S[flash].tint, ",") .. " " .. tostring(S[flash].tintAlpha), "0,0,1 1", "the flash in the bar's own blue")
end
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
-- Blizzard sets the bar up again, tinting the spent flash in its own blue:
-- tinted again after, in the colour it gave the bar.
prd:UpdatePowerBar()
Equal(table.concat(S[prd.PowerBar.FeedbackFrame.BarTexture].tint, ","), "1,1,0", "the spent flash follows Blizzard's colour for the bar")
ns.Set("prdPower", "purple")
ns.Resource:Apply()
Equal(S[prd.PowerBar].barColour[1] == .6 and S[prd.AlternatePowerBar].barColour[1], .6, "your own colour instead, on both power bars")
prd.PowerBar:SetStatusBarColor(0, 0, 1)
Equal(S[prd.PowerBar].barColour[1], .6, "and it stays when Blizzard recolours")
prd:UpdatePowerBar()
Equal(string.format("%g %g", S[prd.PowerBar.FeedbackFrame.BarTexture].tint[1], S[prd.PowerBar.FeedbackFrame.BarTexture].tintAlpha), "0.6 1",
    "the spent flash in your colour too, tinted again after Blizzard sets the bar up")
ns.Set("barStyle", "outline")
ns.Resource:Apply()
Equal(S[prd.PowerBar].barColour[4], .45, "Outline: a see-through fill")
Equal(S[Piece(prd.PowerBar, "BACKGROUND", -8)].color[1], .6, "inside an edge in its colour")
do
    local cost, flash = prd.PowerBar.ManaCostPredictionBar, prd.PowerBar.FeedbackFrame.BarTexture
    local function Alphas()
        return string.format("%g %g %g %g", S[cost].alpha, S[health.myHealPrediction].alpha, S[health.otherHealPrediction].alpha,
            S[flash].tintAlpha)
    end
    Equal(Alphas() .. " " .. string.format("%.3f,%.3f,%.3f %g", S[cost].tint[1], S[cost].tint[2], S[cost].tint[3], S[cost].tintAlpha),
        "0.45 0.45 0.45 0.45 0.690,0.558,0.930 1",
        "Outline: what a cast will cost, heals on the way and the spent flash as see-through as the fill (the cost in a lighter purple, see-through by its alpha alone)")
    prd:UpdatePowerBar()
    Equal(string.format("%g", S[flash].tintAlpha), "0.45", "the flash still see-through after Blizzard sets the bar up")
    ns.Set("barStyle", "glass")
    ns.Resource:Apply()
    Equal(Alphas(), "1 1 1 1", "Glass: solid again")
    ns.Set("barStyle", "outline")
    ns.Resource:Apply()
end
-- What a cast will cost, on a colour you picked for the bar: a lighter shade
-- of it, as Blizzard's own cost colour is of its bar; set again each time
-- Blizzard sets its own (as your power type changes); and on Blizzard's
-- colours, Blizzard's own again, for the power you have. Only a cosmetic
-- setter on Blizzard's piece, and the maths only on the addon's own colours.
do
    local cost = prd.PowerBar.ManaCostPredictionBar
    local function Tint()
        local s = S[cost]
        return string.format("%.3f,%.3f,%.3f %g", s.tint[1], s.tint[2], s.tint[3], s.tintAlpha or 1)
    end
    -- Who set its colour, in order: Blizzard's own code or the addon.
    local who, SetTint = {}, Proto.SetVertexColor
    function Proto:SetVertexColor(...)
        if self == cost then who[#who + 1] = blizzardCalling and "Blizzard" or "addon" end
        return SetTint(self, ...)
    end
    local function Who()
        local list = table.concat(who, " ")
        who = {}
        return list
    end
    local PURPLE = "0.690,0.558,0.930 1"
    local bar = S[prd.PowerBar].barColour
    Equal(Tint() .. " " .. tostring(S[cost].tint[1] > bar[1] and S[cost].tint[2] > bar[2] and S[cost].tint[3] > bar[3]), PURPLE .. " true",
        "your purple: the cost lighter than the bar in every channel")
    -- Your power type changes: Blizzard sets its own colour for it, and yours goes back on after.
    power = 3
    prd:UpdatePowerBar()
    Equal(Tint() .. " | " .. Who(), PURPLE .. " | Blizzard addon", "Blizzard sets its energy colour, then the lighter purple goes back on")
    prd.PowerBar:SetStatusBarColor(1, 1, 0)
    prd:UpdatePowerBar()
    Equal(Tint(), PURPLE, "and stays as Blizzard recolours the bar and sets it up with no change of power")
    power = 0
    prd:UpdatePowerBar()
    Equal(Tint() .. " | " .. Who(), PURPLE .. " | addon addon Blizzard addon", "back to mana: the same")
    -- Glass: still solid; your class colour: its own lighter shade.
    ns.Set("barStyle", "glass")
    ns.Set("prdPower", "class")
    ns.Resource:Apply()
    Equal(Tint() .. " " .. S[cost].alpha, "1.000,0.605,0.256 1 1", "Glass and your druid orange: a lighter orange, solid")
    -- The shade is Blizzard's own: its mana bar on this display (0.1, 0.25, 1)
    -- taken the same way comes out as light to the eye as its cost blue (0, 0.447, 1).
    do
        local blue = ns.Style.BAR_COLOURS.blue
        ns.Style.BAR_COLOURS.blue = { .1, .25, 1 }
        ns.Set("prdPower", "blue")
        ns.Resource:Apply()
        ns.Style.BAR_COLOURS.blue = blue
        local function Linear(c) return c <= .04045 and c / 12.92 or ((c + .055) / 1.055) ^ 2.4 end
        local function Light(r, g, b) return .2126 * Linear(r) + .7152 * Linear(g) + .0722 * Linear(b) end
        local t = S[cost].tint
        local shade, blizzard = Light(t[1], t[2], t[3]), Light(0, .447, 1)
        Equal(math.abs(shade - blizzard) < .001 and shade > Light(.1, .25, 1), true,
            "Blizzard's mana bar in the same shade: lighter, and as light as Blizzard's own cost colour")
    end
    -- On white (a priest's class colour, which has no lighter shade) or a
    -- colour nearly as light, the lighter shade wouldn't show: the cost goes
    -- the same step darker (each channel x .775) instead. Every other colour
    -- keeps the lighter one. The edge: the lighter shade standing out from the
    -- bar by a contrast of 1.1 (a grey of .829).
    do
        local function Linear(c) return c <= .04045 and c / 12.92 or ((c + .055) / 1.055) ^ 2.4 end
        local function Light(r, g, b) return .2126 * Linear(r) + .7152 * Linear(g) + .0722 * Linear(b) end
        -- Which way the cost went from the bar's colour, and whether it stands out (a contrast of 1.1 or more).
        local function Way(colour)
            local t, up, down = S[cost].tint, 0, 0
            for i = 1, 3 do
                if t[i] > colour[i] + 1e-9 then up = up + 1 elseif t[i] < colour[i] - 1e-9 then down = down + 1 end
            end
            local a, b = Light(t[1], t[2], t[3]), Light(colour[1], colour[2], colour[3])
            local standout = (math.max(a, b) + .05) / (math.min(a, b) + .05) >= 1.1
            return (up > 0 and down == 0 and "lighter" or down > 0 and up == 0 and "darker" or "mixed")
                .. (standout and "" or " (doesn't stand out)")
        end
        local blue = ns.Style.BAR_COLOURS.blue
        -- A colour of yours on the palette's Blue spot; returns which way the cost went.
        local function On(colour)
            ns.Style.BAR_COLOURS.blue = colour
            ns.Set("prdPower", "blue")
            ns.Resource:Apply()
            ns.Style.BAR_COLOURS.blue = blue
            return Way(colour)
        end
        -- A priest on the Class colour: white.
        local UnitClass0, priest = _G.UnitClass, { 1, 1, 1 }
        _G.UnitClass = function() return "Priest", "PRIEST" end
        _G.RAID_CLASS_COLORS.PRIEST = { r = 1, g = 1, b = 1 }
        ns.Set("prdPower", "class")
        ns.Resource:Apply()
        Equal(Tint() .. " " .. Way(priest), "0.775,0.775,0.775 1 darker", "a priest on the Class colour: the cost a darker white (grey), solid")
        -- Kept through a change of power, as the lighter shade is.
        Who()
        power = 3
        prd:UpdatePowerBar()
        Equal(Tint() .. " | " .. Who(), "0.775,0.775,0.775 1 | Blizzard addon", "Blizzard sets its energy colour, then the darker white goes back on")
        power = 0
        prd:UpdatePowerBar()
        Equal(Tint(), "0.775,0.775,0.775 1", "back to mana: still the darker white")
        -- Outline: the region's alpha as for the lighter shade, the tint still solid.
        ns.Set("barStyle", "outline")
        ns.Resource:Apply()
        Equal(Tint() .. " " .. S[cost].alpha, "0.775,0.775,0.775 1 0.45", "Outline on white: the darker white, see-through by its alpha alone like the fill")
        ns.Set("barStyle", "glass")
        ns.Resource:Apply()
        Equal(Tint() .. " " .. S[cost].alpha, "0.775,0.775,0.775 1 1", "Glass on white: solid again")
        -- A rogue's pale yellow on the Class colour: its lighter shade barely shows, so darker too.
        _G.UnitClass = function() return "Rogue", "ROGUE" end
        _G.RAID_CLASS_COLORS.ROGUE = { r = 1, g = .96, b = .41 }
        ns.Resource:Apply()
        Equal(Tint() .. " " .. Way({ 1, .96, .41 }), "0.775,0.744,0.318 1 darker", "a rogue's pale yellow: the cost darker")
        -- The lightest class colour that still keeps the lighter shade: hunter green.
        _G.UnitClass = function() return "Hunter", "HUNTER" end
        _G.RAID_CLASS_COLORS.HUNTER = { r = .67, g = .83, b = .45 }
        ns.Resource:Apply()
        Equal(Tint() .. " " .. Way({ .67, .83, .45 }), "0.744,0.868,0.574 1 lighter", "hunter green: the lighter shade, as before")
        -- Every class colour Forever has (its class table, build 70425): only
        -- the rogue's and the priest's go darker, and each stands out 1.1 or
        -- more (the mage's 1.16 and the hunter's 1.13 the least).
        do
            local colours0, classes = _G.RAID_CLASS_COLORS, {}
            _G.RAID_CLASS_COLORS = {}
            for _, class in ipairs({ { "WARRIOR", .776, .608, .427 }, { "PALADIN", .957, .549, .729 },
                { "HUNTER", .667, .827, .447 }, { "ROGUE", 1, .957, .408 }, { "PRIEST", 1, 1, 1 }, { "SHAMAN", 0, .439, .867 },
                { "MAGE", .247, .780, .922 }, { "WARLOCK", .529, .533, .933 }, { "DRUID", 1, .486, .039 } }) do
                local token = class[1]
                _G.RAID_CLASS_COLORS[token] = { r = class[2], g = class[3], b = class[4] }
                _G.UnitClass = function() return token, token end
                ns.Resource:Apply()
                classes[#classes + 1] = token:lower() .. " " .. Way({ class[2], class[3], class[4] })
            end
            _G.RAID_CLASS_COLORS = colours0
            Equal(table.concat(classes, ", "), "warrior lighter, paladin lighter, hunter lighter, rogue darker, priest darker, "
                .. "shaman lighter, mage lighter, warlock lighter, druid lighter", "every class colour: only the rogue's and the priest's go darker, each standing out")
        end
        _G.UnitClass, _G.RAID_CLASS_COLORS.PRIEST, _G.RAID_CLASS_COLORS.ROGUE, _G.RAID_CLASS_COLORS.HUNTER = UnitClass0, nil, nil, nil
        ns.Resource:Apply()
        Equal(Tint(), "1.000,0.605,0.256 1", "back to the druid: its lighter orange")
        -- Near-white colours of yours: darker.
        local near = {}
        for _, colour in ipairs({ { 1, 1, 1 }, { .95, .95, .95 }, { .9, .9, .92 }, { 1, 1, .8 }, { .9, 1, 1 } }) do
            near[#near + 1] = On(colour)
        end
        Equal(table.concat(near, ", "), "darker, darker, darker, darker, darker", "white and near-white colours: the cost darker")
        Equal((On({ .95, .95, .95 }) and Tint()), "0.736,0.736,0.736 1", "a near-white .95 grey: .95 x .775")
        -- Every palette colour, and Blizzard's own blue, keep the lighter shade.
        local normal = {}
        for _, key in ipairs({ "orange", "charcoal", "blue", "green", "purple" }) do
            normal[#normal + 1] = key .. " " .. On(ns.Style.BAR_COLOURS[key])
        end
        normal[#normal + 1] = "Blizzard's " .. On({ .1, .25, 1 })
        Equal(table.concat(normal, ", "),
            "orange lighter, charcoal lighter, blue lighter, green lighter, purple lighter, Blizzard's lighter",
            "every palette colour, and Blizzard's own bar blue: the lighter shade, as before")
        -- The edge: a grey of .82 (its lighter shade stands out 1.106) keeps
        -- it; .83 (1.099) goes darker, to .83 x .775.
        Equal(On({ .82, .82, .82 }) .. " | " .. On({ .83, .83, .83 }) .. " " .. Tint(), "lighter | darker 0.643,0.643,0.643 1",
            "the edge: a .82 grey keeps the lighter shade, a .83 grey goes darker")
        -- Saturated ones whose lighter shade only lifts a weak channel (magenta): darker, and standing out.
        Equal(On({ 1, 0, 1 }), "darker", "magenta, whose lighter shade barely shows: darker, and it stands out")
        -- Blizzard's own colours are never shaded: a white bar of Blizzard's keeps its own cost colour.
        ns.Set("prdPower", "default")
        ns.Resource:Apply()
        Who()
        prd.PowerBar:SetStatusBarColor(1, 1, 1)
        ns.Resource:Apply()
        prd:UpdatePowerBar()
        Equal(Tint() .. " | " .. Who(), "0.000,0.447,1.000 1 | ", "a white bar on Blizzard's colours: its own cost blue, nothing set by the addon")
        prd.PowerBar:SetStatusBarColor(1, 1, 0)
    end
    -- Back on Blizzard's colours: its own cost colour for the power you have
    -- now (energy's), then left to Blizzard.
    ns.Set("prdPower", "purple")
    ns.Resource:Apply()
    power = 3
    prd:UpdatePowerBar()
    Who()
    ns.Set("prdPower", "default")
    ns.Resource:Apply()
    Equal(Tint() .. " | " .. Who(), "1.000,0.850,0.400 1 | addon", "Blizzard's colours again: its own energy colour put back, once")
    prd.PowerBar:SetStatusBarColor(1, 1, 0)
    prd:UpdatePowerBar()
    ns.Resource:Apply()
    power = 0
    prd:UpdatePowerBar()
    Equal(Tint() .. " | " .. Who(), "0.000,0.447,1.000 1 | Blizzard", "then left to Blizzard, which sets its mana blue as you change power")
    -- A power with no cost colour of its own, or a secret one: mana's, as Blizzard does.
    ns.Set("prdPower", "purple")
    ns.Resource:Apply()
    _G.UnitPowerType = function() return 1, "RAGE" end
    ns.Set("prdPower", "default")
    ns.Resource:Apply()
    Equal(Tint(), "0.000,0.447,1.000 1", "rage, with no cost colour of its own: mana's put back")
    -- A power Blizzard finds by its number, not its name: that one's; one the
    -- game gives its own bar colour: mana's (Blizzard's colour for it has no
    -- cost colour); one with no name: mana's (Blizzard looks nothing up).
    local found = {}
    for _, answer in ipairs({ { 3, "UNLISTED" }, { 3, "UNLISTED", .5, .5, .5 }, { 3 } }) do
        ns.Set("prdPower", "purple")
        ns.Resource:Apply()
        _G.UnitPowerType = function() return table.unpack(answer) end
        ns.Set("prdPower", "default")
        ns.Resource:Apply()
        found[#found + 1] = Tint()
    end
    Equal(table.concat(found, " | "), "1.000,0.850,0.400 1 | 0.000,0.447,1.000 1 | 0.000,0.447,1.000 1",
        "a power found by its number: its own cost colour; one with the game's own bar colour or no name: mana's")
    ns.Set("prdPower", "purple")
    ns.Resource:Apply()
    _G.issecretvalue = function(v) return rawequal(v, SECRETS.number) or rawequal(v, SECRETS.string) end
    _G.UnitPowerType = function() return SECRETS.number, SECRETS.string end
    ns.Set("prdPower", "default")
    ns.Resource:Apply()
    Equal(Tint(), "0.000,0.447,1.000 1", "a secret power type: mana's put back, and nothing done with the secret")
    _G.issecretvalue = nil
    _G.UnitPowerType = function() return power, power == 3 and "ENERGY" or "MANA" end
    Proto.SetVertexColor = SetTint
    ns.Set("prdPower", "purple")
    ns.Set("barStyle", "outline")
    ns.Resource:Apply()
    Equal(Tint() .. " " .. S[cost].alpha, PURPLE .. " 0.45", "purple and Outline again")
end
-- The bar texture picked on the Look page, and still only set when it changes
-- as Blizzard recolours the bars.
ns.Set("barTexture", "skills")
ns.Resource:Apply()
local SKILLS = "Interface\\PaperDollInfoFrame\\UI-Character-Skills-Bar"
Equal(S[health].barTexture .. " " .. S[prd.PowerBar].barTexture .. " " .. S[prd.AlternatePowerBar].barTexture,
    SKILLS .. " " .. SKILLS .. " " .. SKILLS, "the texture picked, on the display's bars")
Equal(S[prd.PowerBar.ManaCostPredictionBar].file .. " " .. S[health.myHealPrediction].file .. " " .. S[health.otherHealPrediction].file
    .. " " .. S[prd.PowerBar.FeedbackFrame.BarTexture].file, SKILLS .. " " .. SKILLS .. " " .. SKILLS .. " " .. SKILLS,
    "and on Blizzard's pieces beside them")
local fills = 0
-- (Both setters, the bars' fills' and the pieces', counted together.)
local SetFill = { Proto.SetStatusBarTexture, Proto.SetTexture }
function Proto:SetStatusBarTexture(t)
    fills = fills + 1
    SetFill[1](self, t)
end
function Proto:SetTexture(t)
    fills = fills + 1
    SetFill[2](self, t)
end
prd.PowerBar:SetStatusBarColor(0, 0, 1)
prd:UpdatePowerBar()
ns.Resource:Apply()
Equal(fills .. " " .. S[prd.PowerBar].barTexture, "0 " .. SKILLS, "not set again while it stays the same, nor Blizzard's pieces beside it")
Proto.SetStatusBarTexture, Proto.SetTexture = SetFill[1], SetFill[2]
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
-- Darkness and thick edges on the display's bars: Blizzard's art behind each
-- is the track, the shine splits where the fill ends, and a second pixel
-- goes inside the edge. Only cosmetic setters on Blizzard's bars, and
-- nothing over the empty part but the fading shine, so heal prediction shows.
do
    ns.Set("barStyle", "glass")
    ns.Resource:Apply()
    local shine, ring
    local function Find()
        shine, ring = {}, {}
        for _, r in ipairs(S[health].regions) do
            if S[r].layer == "OVERLAY" and S[r].sublevel == -8 then shine[#shine + 1] = r end
            if S[r].layer == "OVERLAY" and S[r].sublevel == -5 then ring[#ring + 1] = r end
        end
    end
    Find()
    local over = shine[1]
    local function At(region, i)
        local p = S[region].points[i]
        local rel = p[2] == health and "bar" or p[2] == S[health].fill and "fill" or "?"
        return p[1] .. " " .. rel .. " " .. p[3]
    end
    Equal(#shine .. " " .. #ring .. " | " .. string.format("%g %g", S[healthArt].color[1], S[healthArt].color[4]) .. " | "
        .. At(over, 1) .. ", " .. At(over, 2) .. " " .. tostring(S[over].shown), "1 0 | 0.08 0.85 | TOPLEFT bar TOPLEFT, BOTTOMRIGHT bar RIGHT true",
        "off by default: today's track and the shine over the whole top half, nothing more made")
    local fill = New("Texture", health)
    Seal(fill)
    S[health].fill = fill
    ns.Set("barDarkness", 100)
    ns.Set("thickEdges", true)
    ns.Resource:Apply()
    Find()
    local rest = shine[2]
    Equal(string.format("%g %g %g", S[healthArt].color[1], S[healthArt].color[4], S[rest].color[4]) .. " | " .. At(over, 2) .. " | "
        .. At(rest, 1) .. ", " .. At(rest, 2) .. " " .. tostring(S[rest].shown),
        "0 1 0 | BOTTOMRIGHT fill RIGHT | TOPLEFT fill TOPRIGHT, BOTTOMRIGHT bar RIGHT true",
        "darkness 100: the art solid black, the shine kept to the fill")
    Equal(string.format("%s %s %g %g", tostring(S[ring[1]].shown), tostring(S[ring[4]].shown), S[ring[1]].color[1], S[ring[1]].color[4])
        .. " " .. tostring(InsetBy(Piece(health, "BACKGROUND", -8), health, -1)), "true true 0 1 true",
        "thick edges: a black pixel inside the 1px edge, which stays where it was")
    -- Blizzard recolouring the bar redraws it, but sets the track only when the darkness changes.
    local set, SetColor = 0, Proto.SetColorTexture
    function Proto:SetColorTexture(...) if self == healthArt or self == rest then set = set + 1 end SetColor(self, ...) end
    health:SetStatusBarColor(0, .9, 0)
    Proto.SetColorTexture = SetColor
    Equal(set, 0, "Blizzard recolouring the bar: the track and shine left as they are")
    ns.Set("barStyle", "outline")
    ns.Resource:Apply()
    Equal(string.format("%g %g %s %s", S[ring[1]].color[1], S[ring[1]].color[2], tostring(S[over].shown), tostring(S[rest].shown)),
        "0 0.9 false false", "Outline: the second pixel in the bar's colour, and no shine")
    ns.Set("barStyle", "glass")
    ns.Set("barDarkness", 0)
    ns.Set("thickEdges", false)
    ns.Resource:Apply()
    Equal(string.format("%g %g", S[healthArt].color[1], S[healthArt].color[4]) .. " | " .. At(over, 2) .. " " .. tostring(S[over].shown)
        .. " " .. tostring(S[rest].shown) .. " " .. tostring(S[ring[1]].shown), "0.08 0.85 | BOTTOMRIGHT bar RIGHT true false false",
        "both off: today's look again")
end
Equal(#printed, 0, "no errors")

-- Restyle off: Blizzard's bars untouched, but the repeat mana bar still hides.
Environment()
Viewers(0)
_G.UnitPowerType = function() return power, power == 3 and "ENERGY" or "MANA" end
prd = PRD()
_G.PersonalResourceDisplayFrame = prd
ns = Load({ prdSkin = false, prdPower = "purple" })
Equal(S[prd.PowerBar].barTexture, nil, "restyle off: Blizzard's own bars")
prd:UpdatePowerBar()
Equal(S[prd.PowerBar.ManaCostPredictionBar].file .. " " .. S[prd.PowerBar.FeedbackFrame.BarTexture].file .. " "
    .. table.concat(S[prd.PowerBar.FeedbackFrame.BarTexture].tint, ","), UI_STATUSBAR .. " " .. UI_STATUSBAR .. " 0,0,1",
    "and Blizzard's own pieces beside them: its texture, and the flash as Blizzard tints it")
Equal(ns.Get("prdPower") .. " " .. table.concat(S[prd.PowerBar.ManaCostPredictionBar].tint, ","), "purple 0,0.447,1",
    "what a cast will cost in Blizzard's own blue, with a colour of yours saved")
Equal(S[prd.AlternatePowerBar].alpha, 0, "the repeat bar still hides")

-- Blizzard loads the display once it's switched on.
Environment()
Viewers(0)
_G.UnitPowerType = function() return power, power == 3 and "ENERGY" or "MANA" end
ns = Load({ prdPower = "purple" })
prd = PRD()
_G.PersonalResourceDisplayFrame = prd
Fire("ADDON_LOADED", "Blizzard_PersonalResourceDisplay")
Equal(S[prd.PowerBar].barTexture, "Interface\\Buttons\\WHITE8X8", "restyled once Blizzard loads it")
-- With your colour saved: what a cast will cost in its lighter shade at once,
-- and again after Blizzard first sets the bar up in its own.
do
    local cost = prd.PowerBar.ManaCostPredictionBar
    local function Tint() return string.format("%.3f,%.3f,%.3f", S[cost].tint[1], S[cost].tint[2], S[cost].tint[3]) end
    local first = Tint()
    prd:UpdatePowerBar()
    Equal(first .. " " .. Tint(), "0.690,0.558,0.930 0.690,0.558,0.930", "your lighter purple as it loads, and after Blizzard sets the bar up")
end
Equal(#printed, 0, "no errors from the display")

-- A display without the pieces beside the fills (a build that drops them):
-- restyled all the same, with nothing looked for that isn't there.
do
    Environment()
    Viewers(0)
    _G.UnitPowerType = function() return power, power == 3 and "ENERGY" or "MANA" end
    local bare = PRD(true)
    _G.PersonalResourceDisplayFrame = bare
    ns = Load(nil)
    bare:UpdatePowerBar()
    ns.Set("barStyle", "outline")
    ns.Set("barTexture", "raid")
    ns.Set("prdPower", "purple")
    ns.Resource:Apply()
    bare:UpdatePowerBar()
    ns.Set("prdPower", "default")
    ns.Resource:Apply()
    Equal(S[bare.PowerBar].barTexture .. " " .. S[bare.HealthBarsContainer.healthBar].barTexture .. " " .. #printed,
        RAID .. " " .. RAID .. " 0", "a display without those pieces: restyled all the same, with no error")
end

-- Something going wrong in the addon's hooks on the display, which run
-- inside Blizzard's own calls: you're told once, and it's never handed back,
-- so Blizzard's work carries on. Its UpdatePowerBar (70425) sets the bar's
-- colour first, then notes your power type and sets up the rest; Edit Mode's
-- setters and its Bar Width carry on after the addon's hooks too.
do
    Environment()
    Viewers(0)
    power = 0
    _G.UnitPowerType = function() return power, power == 3 and "ENERGY" or "MANA" end
    local display = PRD()
    _G.PersonalResourceDisplayFrame = display
    local setUp, noted, maxed = display.UpdatePowerBar, nil, 0
    rawset(display, "UpdatePowerBar", function(self)
        local was = blizzardCalling
        blizzardCalling = true
        self.PowerBar:SetStatusBarColor(0, 0, 1)
        local _, token = UnitPowerType("player")
        noted, maxed = token, maxed + 1
        blizzardCalling = was
        setUp(self)
    end)
    ns = Load(nil)
    local R = ns.Resource
    -- One of Blizzard's own calls, as its events or Edit Mode make it: "true" when all of it ran.
    local function Call(method, ...)
        local done = false
        local ok = pcall(function(...)
            display[method](display, ...)
            done = true
        end, ...)
        return tostring(ok and done)
    end
    local function Told(n, what)
        return tostring(printed[n]):match("couldn't restyle the Personal Resource Display%. Please report this: .*" .. what) ~= nil
    end
    -- A fault in the look, as Blizzard colours the bar: the rest of UpdatePowerBar
    -- still runs, and you're told once, not on each call.
    local ShowSheen = ns.Style.ShowSheen
    ns.Style.ShowSheen = function() error("a fault in the look") end
    local first = Call("UpdatePowerBar") .. " " .. tostring(noted) .. " " .. maxed
    local again = Call("UpdatePowerBar") .. " " .. maxed
    ns.Style.ShowSheen = ShowSheen
    Equal(first .. " | " .. again .. " | " .. #printed .. " " .. tostring(Told(1, "a fault in the look")), "true MANA 1 | true 2 | 1 true",
        "a fault in the look as Blizzard colours the bar: its UpdatePowerBar still notes your power and carries on; told once")
    -- A fault in Layout:Stack, as your power changes (the extra mana bar
    -- comes back, so the rows make room) and as Blizzard sets the width.
    R.lastError = nil
    local layout = ns.Layout
    ns.Layout = { Stack = function() error("a fault in the layout") end, Active = function() error("a fault in the layout") end,
        MatchWidth = function() end }
    power = 3
    local shifted = Call("UpdatePowerBar") .. " " .. tostring(noted) .. " " .. tostring(R:ExtraHidden()) .. " " .. S[display.AlternatePowerBar].alpha
    S[display].width = nil
    local width = Call("UpdateBarWidth") .. " " .. string.format("%g", S[display].width or 0)
    ns.Layout = layout
    Equal(shifted .. " | " .. width .. " | " .. #printed .. " " .. tostring(Told(2, "a fault in the layout")),
        "true ENERGY false 1 | true 200 | 2 true", "a fault in the layout after UpdatePowerBar and Bar Width: both carry on; told once")
    -- A fault in the cost's tint as Edit Mode sets the bars' height.
    R.lastError = nil
    ns.Set("prdPower", "purple")
    local BarColour = ns.Style.BarColour
    ns.Style.BarColour = function() error("a fault in the tint") end
    local height = Call("SetPowerBarHeight", 20) .. " " .. S[display.PowerBar].height
    ns.Style.BarColour = BarColour
    Equal(height .. " | " .. #printed .. " " .. tostring(Told(3, "a fault in the tint")), "true 20 | 3 true",
        "a fault in the cost's tint after Edit Mode's bar height: it carries on; told once")
    -- All well again: Blizzard's colour followed (the spent flash tinted in
    -- it by the look), and nothing more said.
    ns.Set("prdPower", "default")
    ns.Resource:Apply()
    display.PowerBar:SetStatusBarColor(1, 1, 0)
    Equal(table.concat(S[display.PowerBar.FeedbackFrame.BarTexture].tint, ",") .. " " .. Call("UpdatePowerBar") .. " " .. #printed,
        "1,1,0 true 3", "after it: Blizzard's colour followed again, and nothing more said")
    power = 0
end

-- Your health and power as text on the display's bars ----------------------------------------
-- Off by default, with nothing made and nothing listening. Ticked, the
-- addon's own text, on frames of its own over Blizzard's bars that take no
-- mouse, above everything Blizzard draws there. Your health and power are
-- secret on Forever, in and out of combat, so here they're the mock game's
-- secrets, which fail on any compare, sum, join or turn into text: the
-- addon only hands them on, to the game's own calls (which keep them
-- secret) and on to the text. Blizzard's own text on a bar goes see-through
-- while ours shows there, and comes back after.
;(function()
    local SECRET, WORDS = SECRETS.number, SECRETS.string
    local curve = {} -- the game's 0 to 100 curve
    local asked = {}
    -- A game function: what it was asked, secrets named, and its answer.
    local function Game(name, answer)
        return function(...)
            local args, words = table.pack(...), {}
            for i = 1, args.n do
                local v = args[i]
                words[i] = rawequal(v, SECRET) and "secret" or rawequal(v, WORDS) and "secret text" or rawequal(v, curve) and "curve"
                    or tostring(v)
            end
            asked[#asked + 1] = name .. "(" .. table.concat(words, ", ") .. ")"
            if type(answer) == "function" then return answer(...) end
            return answer
        end
    end
    local function Asked()
        local list = table.concat(asked, " ")
        asked = {}
        return list
    end
    local function IsSecretTest(v) return rawequal(v, SECRET) end
    local function Game0()
        _G.UnitHealth, _G.UnitHealthMax = Game("UnitHealth", SECRET), Game("UnitHealthMax", SECRET)
        _G.UnitHealthPercent = Game("UnitHealthPercent", SECRET)
        _G.UnitPower, _G.UnitPowerMax = Game("UnitPower", SECRET), Game("UnitPowerMax", SECRET)
        _G.UnitPowerPercent = Game("UnitPowerPercent", SECRET)
        -- The game's own number writers take a secret and give secret text;
        -- a plain number, plain text.
        _G.BreakUpLargeNumbers = Game("BreakUpLargeNumbers", function(v)
            if IsSecretTest(v) then return WORDS end
            return tostring(math.floor(v)):reverse():gsub("(%d%d%d)", "%1,"):reverse():gsub("^,", "")
        end)
        _G.AbbreviateNumbers = Game("AbbreviateNumbers", function(v)
            if IsSecretTest(v) then return WORDS end
            return string.format("%.1fK", v / 1000)
        end)
        _G.CurveConstants = { ScaleTo100 = curve }
        _G.UnitPowerType = function() return 0, "MANA" end
    end
    local function Fresh(saved)
        Environment()
        Viewers(0)
        Game0()
        local display = PRD()
        _G.PersonalResourceDisplayFrame = display
        ns = Load(saved)
        asked = {}
        return display, display.HealthBarsContainer.healthBar, display.PowerBar
    end
    -- A spot's text as handed over: its format and what went in it, secrets named.
    local function Said(text)
        local s = S[text]
        if s.format == nil then return '"' .. tostring(s.text) .. '"' end
        local words = {}
        for i = 1, s.args.n do
            local v = s.args[i]
            words[i] = rawequal(v, SECRET) and "secret" or rawequal(v, WORDS) and "secret text" or tostring(v)
        end
        return s.format .. " [" .. table.concat(words, ", ") .. "]"
    end
    local function Spots(holder)
        local slots = holder.slots
        return Said(slots.centre) .. " | " .. Said(slots.left) .. " | " .. Said(slots.right)
    end
    local function Listening(holder)
        local list = {}
        for event, unit in pairs(S[holder].events) do list[#list + 1] = event .. ":" .. tostring(unit) end
        table.sort(list)
        return table.concat(list, " ")
    end
    local function BlizzardText(bar)
        return S[bar.TextString].alpha .. S[bar.LeftText].alpha .. S[bar.RightText].alpha
    end

    -- Off by default: nothing made, nothing listening, Blizzard's text as it was.
    local display, health, powerBar = Fresh(nil)
    local made = 0
    for _, frame in ipairs(frames) do
        if S[frame].parent == health or S[frame].parent == powerBar then made = made + 1 end
        if S[frame].events.UNIT_HEALTH or S[frame].events.UNIT_MAXHEALTH then made = made + 100 end
    end
    Equal(tostring(ns.Get("prdText")) .. " " .. tostring(next(ns.Resource.textHolders)) .. " " .. made .. " " .. BlizzardText(health)
        .. " " .. Asked(), "false nil 0 111 ", "off by default: nothing made or listening, nothing asked, Blizzard's text left be")
    Equal(table.concat({ ns.Get("prdHealthAt"), ns.Get("prdHealthCentre"), ns.Get("prdHealthLeft"), ns.Get("prdHealthRight"),
        ns.Get("prdPowerAt"), ns.Get("prdPowerCentre"), ns.Get("prdPowerLeft"), ns.Get("prdPowerRight"), ns.Get("prdTextNumbers"),
        ns.Get("prdTextSize"), ns.Get("prdTextFont") }, " "), "centre value value percent centre value value percent full 10 look",
        "its choices start at the middle of each bar, the value now, numbers in full, size 10, the Look page's font")

    -- Ticked: the text on both bars, in the middle.
    ns.Set("prdText", true)
    ns.Resource:Apply()
    local text = ns.Resource.textHolders
    local hp, mp = text.health, text.power
    Equal(tostring(S[hp].parent == health) .. " " .. tostring(S[mp].parent == powerBar) .. " " .. tostring(S[hp].points[1][2] == health)
        .. " " .. S[hp].points[1][1] .. " " .. S[hp].level .. " " .. S[mp].level .. " " .. tostring(S[hp].mouse) .. " " .. tostring(S[mp].mouse),
        "true true true ALL 101 4 false false",
        "on frames of its own over each bar, taking no mouse: over the lost max health (100), and the power bar's full pulse"
        .. " (+1) and its spike and glow (+2)")
    Equal(Spots(hp) .. " || " .. Spots(mp), '%s [secret text] | "nil" | "nil" || %s [secret text] | "nil" | "nil"',
        "your health and power now in the middle, as the game wrote them")
    Equal(Asked(), "UnitHealth(player) BreakUpLargeNumbers(secret) UnitPower(player, 0) BreakUpLargeNumbers(secret)",
        "each handed straight from the game's answer to its own number writer")
    Equal(S[hp.slots.centre].font .. " " .. S[hp.slots.left].font .. " " .. tostring(S[hp.slots.centre].wordWrap) .. " "
        .. S[hp.slots.centre].justify .. " " .. S[hp.slots.left].justify .. " " .. S[hp.slots.right].justify,
        "FECMFont10 FECMFont10 false CENTER LEFT RIGHT", "in the Look page's font at 10, each spot on one line")
    local function At(slot, i)
        local p = S[slot].points[i]
        return p[1] .. " " .. p[3] .. " " .. p[4]
    end
    Equal(At(hp.slots.left, 1) .. ", " .. At(hp.slots.left, 2) .. " | " .. At(hp.slots.right, 1) .. ", " .. At(hp.slots.right, 2),
        "LEFT LEFT 4, RIGHT CENTER -2 | LEFT CENTER 2, RIGHT RIGHT -4", "a left and right pair each have half the bar, so they can't overlap")
    Equal(Listening(hp) .. " | " .. Listening(mp), "PLAYER_ENTERING_WORLD:true UNIT_HEALTH:player UNIT_MAXHEALTH:player | "
        .. "PLAYER_ENTERING_WORLD:true UNIT_DISPLAYPOWER:player UNIT_MAXPOWER:player UNIT_POWER_FREQUENT:player",
        "listening to your own health and power only, and for loading screens as Blizzard's display does")
    Equal(BlizzardText(health) .. " " .. BlizzardText(powerBar) .. " " .. BlizzardText(display.AlternatePowerBar), "000 000 111",
        "Blizzard's own text see-through on both bars, the extra mana bar's left be")

    -- In a fight: an event writes only that bar's spots in use, with nothing else set.
    local before = (S[hp.slots.centre].writes or 0) .. " " .. (S[mp.slots.centre].writes or 0)
    local fonts, alphas, places = 0, 0, 0
    local SetFont, SetAlpha, SetPoint = Proto.SetFontObject, Proto.SetAlpha, Proto.SetPoint
    function Proto:SetFontObject(o) fonts = fonts + 1; SetFont(self, o) end
    function Proto:SetAlpha(a) alphas = alphas + 1; SetAlpha(self, a) end
    function Proto:SetPoint(...) places = places + 1; SetPoint(self, ...) end
    Fire("UNIT_HEALTH", "player")
    Fire("UNIT_POWER_FREQUENT", "player", "MANA")
    Fire("UNIT_POWER_FREQUENT", "player", "MANA")
    Proto.SetFontObject, Proto.SetAlpha, Proto.SetPoint = SetFont, SetAlpha, SetPoint
    Equal(before .. " | " .. S[hp.slots.centre].writes .. " " .. S[mp.slots.centre].writes .. " " .. fonts .. alphas .. places .. " " .. Asked(),
        "1 1 | 2 3 000 UnitHealth(player) BreakUpLargeNumbers(secret) UnitPower(player, 0) BreakUpLargeNumbers(secret) "
        .. "UnitPower(player, 0) BreakUpLargeNumbers(secret)", "each event: its own bar's text written once, nothing else set")
    -- A bar out of sight isn't written; it's brought up to date as it shows.
    S[health].shown = false
    Fire("UNIT_HEALTH", "player")
    local hidden = S[hp.slots.centre].writes .. " " .. Asked()
    S[health].shown = true
    S[hp].scripts.OnShow(hp)
    Equal(hidden .. " | " .. S[hp.slots.centre].writes .. " " .. Asked(), "2  | 3 UnitHealth(player) BreakUpLargeNumbers(secret)",
        "out of sight: left until it shows again, then brought up to date")
    -- After a loading screen: both bars written again, the game's numbers handed straight on.
    Fire("PLAYER_ENTERING_WORLD", false, true)
    Equal(S[hp.slots.centre].writes .. " " .. Asked(), "4 UnitHealth(player) BreakUpLargeNumbers(secret) UnitPower(player, 0) "
        .. "BreakUpLargeNumbers(secret)", "a loading screen: both bars brought up to date")
    -- Another power's change (a druid's mana ticking in cat form, say): the
    -- power text is left alone, as Blizzard's own display does. Your own
    -- power's, one with no name, one whose name the game keeps secret (never
    -- compared) and your power type changing still write.
    do
        local writes = S[mp.slots.centre].writes
        local function Wrote()
            local now = S[mp.slots.centre].writes
            local n = now - writes
            writes = now
            return n
        end
        Fire("UNIT_POWER_FREQUENT", "player", "ENERGY")
        Fire("UNIT_MAXPOWER", "player", "ENERGY")
        local other = Wrote() .. " " .. Asked()
        Fire("UNIT_POWER_FREQUENT", "player", "MANA")
        Fire("UNIT_MAXPOWER", "player", "MANA")
        local own = Wrote()
        Fire("UNIT_POWER_FREQUENT", "player")
        _G.issecretvalue = function(v) return rawequal(v, SECRET) or rawequal(v, WORDS) end
        Fire("UNIT_POWER_FREQUENT", "player", WORDS)
        -- Your power's own name kept secret: never compared either.
        local PowerType0 = _G.UnitPowerType
        _G.UnitPowerType = function() return 0, WORDS end
        Fire("UNIT_POWER_FREQUENT", "player", "ENERGY")
        _G.UnitPowerType, _G.issecretvalue = PowerType0, nil
        Fire("UNIT_DISPLAYPOWER", "player")
        local rest = Wrote()
        asked = {}
        Equal(other .. "| " .. own .. " " .. rest .. " " .. #printed, "0 | 2 4 0",
            "another power's change: nothing written or asked; your own, no name, a secret name either side and a new power type: written")
    end

    -- Each format, through the game's own calls only.
    local function Pick(key, value)
        ns.Set(key, value)
        ns.Resource:Apply()
    end
    Pick("prdHealthCentre", "both")
    Equal(Said(hp.slots.centre) .. " " .. Asked(), "%s / %s [secret text, secret text] UnitHealth(player) BreakUpLargeNumbers(secret) "
        .. "UnitHealthMax(player) BreakUpLargeNumbers(secret) UnitPower(player, 0) BreakUpLargeNumbers(secret)",
        "Value / max: both written by the game")
    Pick("prdHealthCentre", "percent")
    Pick("prdPowerCentre", "percent")
    Equal(Said(hp.slots.centre) .. " | " .. Said(mp.slots.centre) .. " | " .. Asked(), "%.0f%% [secret] | %.0f%% [secret] | "
        .. "UnitHealthPercent(player, false, curve) UnitPower(player, 0) BreakUpLargeNumbers(secret) "
        .. "UnitHealthPercent(player, false, curve) UnitPowerPercent(player, 0, false, curve)",
        "Percent: the game's percent through its 0 to 100 curve, handed to the text as it is")
    Pick("prdTextNumbers", "short")
    Pick("prdHealthCentre", "value")
    Equal(Said(hp.slots.centre) .. " " .. Asked():match("UnitHealth%(player%) %S+"), "%s [secret text] UnitHealth(player) AbbreviateNumbers(secret)",
        "4.3K: shortened by the game")
    Pick("prdTextNumbers", "full")
    Pick("prdPowerCentre", "value")

    -- A left and right pair: the middle emptied, each end as chosen.
    Pick("prdHealthAt", "sides")
    Equal(Spots(hp), '"" | %s [secret text] | %.0f%% [secret]', "Left and right: the value at the left, the percent at the right")
    Pick("prdHealthLeft", "none")
    Equal(Spots(hp), '"" | "" | %.0f%% [secret]', "None at the left: just the right")
    Pick("prdHealthRight", "both")
    Equal(Spots(hp), '"" | "" | %s / %s [secret text, secret text]', "and Value / max there")
    asked = {}
    Fire("UNIT_HEALTH", "player")
    Equal(Asked(), "UnitHealth(player) BreakUpLargeNumbers(secret) UnitHealthMax(player) BreakUpLargeNumbers(secret)",
        "an event writes the one spot in use")
    Pick("prdHealthLeft", "value")
    Pick("prdHealthRight", "percent")

    -- Size and font: the Look page's font at the size chosen, or one of the game's own.
    Pick("prdTextSize", 14)
    Equal(S[hp.slots.centre].font .. " " .. S[hp.slots.right].font .. " " .. S[mp.slots.left].font, "FECMFont14 FECMFont14 FECMFont14",
        "a bigger size, on every spot")
    Pick("prdTextFont", "arial")
    Equal(S[hp.slots.left].font .. " " .. S[_G.FECMFontarial14].face, "FECMFontarial14 Fonts\\ARIALN.TTF 14 OUTLINE",
        "Arial Narrow just for this text, outlined like the rest")
    ns.Set("font", "skurri")
    ns.Style:ApplyFont()
    Equal(S[_G.FECMFontarial14].face .. " " .. S[_G.FECMFont14].face, "Fonts\\ARIALN.TTF 14 OUTLINE Fonts\\skurri.ttf 14 OUTLINE",
        "a new Look page font leaves it be")
    Pick("prdTextFont", "look")
    Equal(S[hp.slots.left].font .. " " .. #printed, "FECMFont14 0", "back to the Look page's font, now Skurri")
    ns.Set("font", "friz")
    ns.Style:ApplyFont()
    Pick("prdTextSize", 10)

    -- A bar's text off: gone from that bar, its listening and Blizzard's text back.
    Pick("prdHealthAt", "off")
    Equal(tostring(S[hp].shown) .. " " .. Listening(hp) .. "| " .. BlizzardText(health) .. " " .. tostring(S[mp].shown) .. " "
        .. BlizzardText(powerBar), "false | 111 true 000", "the health bar's text off: hidden and quiet, Blizzard's text back there")
    Pick("prdHealthAt", "centre")
    Equal(tostring(S[hp].shown) .. " " .. BlizzardText(health) .. " " .. Said(hp.slots.centre), "true 000 %s [secret text]", "and back")
    -- Unticked: all of it gone, nothing listening, Blizzard's text back.
    Pick("prdText", false)
    Equal(tostring(S[hp].shown) .. " " .. tostring(S[mp].shown) .. " " .. Listening(hp) .. "|" .. Listening(mp) .. "| "
        .. BlizzardText(health) .. BlizzardText(powerBar), "false false || 111111", "unticked: hidden, quiet, and Blizzard's text back")
    asked = {}
    Fire("UNIT_HEALTH", "player")
    ns.Resource:Apply()
    Equal(Asked(), "", "and nothing asked of the game")
    Equal(#printed, 0, "no errors")

    -- Kept over a reload; anything else saved is ignored.
    local saved = ForeverEnhancedCooldownManagerDB
    saved.prdText, saved.prdHealthAt, saved.prdPowerRight, saved.prdTextSize = true, "sides", "both", 12
    display, health = Fresh(saved)
    hp = ns.Resource.textHolders.health
    Equal(tostring(S[hp].shown) .. " " .. Spots(hp) .. " " .. S[hp.slots.left].font, 'true "nil" | %s [secret text] | %.0f%% [secret] FECMFont12',
        "kept over a reload: shown from the start as chosen")
    saved.prdHealthCentre, saved.prdHealthLeft, saved.prdTextSize, saved.prdTextFont, saved.prdTextNumbers = "none", "middle", 30, "comic", 4
    Fresh(saved)
    Equal(table.concat({ ns.Get("prdHealthCentre"), ns.Get("prdHealthLeft"), ns.Get("prdTextSize"), ns.Get("prdTextFont"),
        ns.Get("prdTextNumbers") }, " "), "value value 10 look full", "anything else is ignored (the middle always shows something)")

    -- A power type the game keeps secret: the game picks your current one.
    _G.issecretvalue = function(v) return rawequal(v, SECRET) end
    display = Fresh({ prdText = true })
    _G.UnitPowerType = function() return SECRET, "MANA" end
    Fire("UNIT_POWER_FREQUENT", "player", "MANA")
    Equal(Asked(), "UnitPower(player, nil) BreakUpLargeNumbers(secret)", "a secret power type isn't handed on: the game picks")
    _G.issecretvalue = nil

    -- A build without the percent call or its curve: percent spots stay blank.
    Environment()
    Viewers(0)
    Game0()
    _G.UnitHealthPercent, _G.CurveConstants = nil, nil
    _G.PersonalResourceDisplayFrame = PRD()
    ns = Load({ prdText = true, prdHealthCentre = "percent", prdPowerCentre = "percent" })
    hp = ns.Resource.textHolders.health
    Equal(Said(hp.slots.centre) .. " " .. Said(ns.Resource.textHolders.power.slots.centre) .. " " .. #printed, '"" "" 0',
        "no percent call or curve: blank, with no error")
    _G.CurveConstants = { ScaleTo100 = curve }

    -- A druid's extra mana bar (off until picked): your mana, whatever your
    -- power, Blizzard's text there see-through while ours shows; another
    -- power ticking doesn't write it. Then the energy bar's, on that bar.
    do
        display = Fresh({ prdText = true, prdExtraAt = "centre" })
        local alternate = display.AlternatePowerBar
        local xp = ns.Resource.textHolders.extra
        Equal(tostring(S[xp].parent == alternate) .. " " .. Spots(xp) .. " " .. BlizzardText(alternate),
            'true %s [secret text] | "nil" | "nil" 000', "the extra mana bar: your mana in the middle, Blizzard's text there see-through")
        Asked()
        Fire("UNIT_POWER_FREQUENT", "player", "RAGE")
        Equal(Asked(), "", "rage ticking writes neither your mana bar's text nor the extra mana bar's")
        ns.Set("prdEnergy", true)
        ns.Set("prdEnergyAt", "sides")
        ns.Resource:Apply()
        local ep = ns.Resource.textHolders.energy
        Equal(tostring(ep ~= nil and S[ep].parent == ns.Resource:ComboRow()) .. " " .. Spots(ep), 'true "nil" | %s [secret text] | %.0f%% [secret]',
            "the energy bar in other forms: your energy as a pair at its ends, on that bar")
        ns.Set("prdExtraAt", "off")
        ns.Resource:Apply()
        Equal(BlizzardText(alternate), "111", "off again: Blizzard's text on the extra mana bar comes back")
    end

    -- The game refusing a number: that bar's text goes blank, quiet and away,
    -- Blizzard's own text there comes back, and you're told once.
    display = Fresh({ prdText = true })
    hp = ns.Resource.textHolders.health
    local was = BlizzardText(display.HealthBarsContainer.healthBar)
    _G.BreakUpLargeNumbers = function() error("bad argument #1 to 'BreakUpLargeNumbers'") end
    Fire("UNIT_HEALTH", "player")
    Fire("UNIT_HEALTH", "player")
    local now = tostring(S[hp].shown) .. " " .. BlizzardText(display.HealthBarsContainer.healthBar)
    ns.Resource:Apply()
    Equal(Said(hp.slots.centre) .. " " .. Listening(hp) .. "| " .. #printed .. " " .. tostring(printed[1]):match("couldn't show text") ,
        '"" | 1 couldn\'t show text', "refused: blank and quiet, one message to report")
    Equal(was .. " " .. now .. " " .. tostring(S[hp].shown) .. " " .. BlizzardText(display.HealthBarsContainer.healthBar), "000 false 111 false 111",
        "and put away at once, Blizzard's text back, staying that way")

    for _, name in ipairs({ "UnitHealth", "UnitHealthMax", "UnitHealthPercent", "UnitPower", "UnitPowerMax", "UnitPowerPercent",
        "BreakUpLargeNumbers", "AbbreviateNumbers", "CurveConstants" }) do
        _G[name] = nil
    end
end)()

-- A layout can make the display as wide as your widest row: only the widths
-- its own Bar Width setting changes, never in combat, and Blizzard's back after.
function Proto:GetEffectiveScale() return 1 end
Environment()
Viewers(0)
_G.UnitPowerType = function() return power, power == 3 and "ENERGY" or "MANA" end
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
_G.UnitPowerType = function() return power, power == 3 and "ENERGY" or "MANA" end
local points = 2
_G.UnitPower = function(unit, kind) assert(unit == "player" and kind == 4, "your combo points"); return points end
prd = PRD()
_G.PersonalResourceDisplayFrame = prd
ns = Load(nil)
Equal(ns.Resource:ComboRow(), nil, "off unless you tick it")
-- What the combo points' listener hears (the display file's own frame with
-- no parent): nothing while they're off; while they're on, what can show or
-- hide them; while they show, your points and target too.
local function ComboHears()
    local list = {}
    for _, frame in ipairs(frames) do
        local script = S[frame].scripts.OnEvent
        if script and S[frame].parent == nil and debug.getinfo(script, "S").source == "@Resource.lua" then
            for event, unit in pairs(S[frame].events) do list[#list + 1] = event .. ":" .. tostring(unit) end
        end
    end
    table.sort(list)
    return table.concat(list, " ")
end
local COMBO_ON = "PLAYER_ENTERING_WORLD:true UNIT_DISPLAYPOWER:player UNIT_MAXPOWER:player UPDATE_SHAPESHIFT_FORM:true"
local COMBO_SHOWN = "PLAYER_ENTERING_WORLD:true PLAYER_TARGET_CHANGED:true UNIT_DISPLAYPOWER:player UNIT_MAXPOWER:player"
    .. " UNIT_POWER_FREQUENT:player UPDATE_SHAPESHIFT_FORM:true"
Equal(ComboHears(), "", "off: a druid's combo listener hears nothing, not even your energy")
ns.Set("prdCombo", true)
ns.Resource:Apply()
local row = ns.Resource:ComboRow()
Equal(row ~= nil and S[row].shown, true, "ticked, a druid in cat form gets them")
Equal(ComboHears(), COMBO_SHOWN, "and its listener hears your power, target, form and loading screens")
-- Forever 70291 draws the game's own combo points too: see-through while ours show.
Equal(S[prd.ClassFrameContainer].alpha .. " " .. tostring(S[prd.ClassFrameContainer].shown),
    "0 " .. tostring(S[prd.ClassFrameContainer].shown), "the game's own combo points go see-through, nothing else changed")
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
Equal(S[prd.ClassFrameContainer].alpha, 1, "ours gone: the game's back in full")
Equal(ComboHears(), COMBO_ON, "out of cat form: not your power or target, only what brings them back")
power = 3
Fire("UPDATE_SHAPESHIFT_FORM")
Equal(tostring(S[row].shown) .. " " .. ComboHears(), "true " .. COMBO_SHOWN, "back in cat form, hearing your power and target again")
-- A rogue has no extra mana bar: straight under the energy bar.
S[prd.AlternatePowerBar].shown = false
prd:UpdatePowerBar()
Equal(S[row].points[1][2] == prd.PowerBar, true, "under the energy bar when it's the lowest")
-- Darkness and thick edges on each segment: its own track, the shine split
-- where its fill ends, and a second pixel inside its edge, so the segments
-- and the gaps between them stay as they are.
do
    ns.Set("barStyle", "glass")
    ns.Resource:Apply()
    local seg = segments[2]
    local track, edge = Piece(seg, "BACKGROUND", nil), Piece(seg, "BACKGROUND", -8)
    local shine, ring
    local function Find()
        shine, ring = {}, {}
        for _, r in ipairs(S[seg].regions) do
            if S[r].layer == "OVERLAY" and S[r].sublevel == -8 then shine[#shine + 1] = r end
            if S[r].layer == "OVERLAY" and S[r].sublevel == -5 then ring[#ring + 1] = r end
        end
    end
    Find()
    local over = shine[1]
    Equal(string.format("%g %g %g", S[track].color[1], S[track].color[4], #S[over].points) .. " " .. tostring(S[over].points[2][2] == seg)
        .. " " .. #shine .. " " .. #ring, "0.08 0.85 2 true 1 0", "off by default: today's track and shine, nothing more made")
    for _, bar in ipairs(segments) do S[bar].fill = New("Texture", bar) end
    ns.Set("barDarkness", 100)
    ns.Set("thickEdges", true)
    ns.Resource:Apply()
    Find()
    local rest = shine[2]
    Equal(string.format("%g %g %g", S[track].color[1], S[track].color[4], S[rest].color[4]) .. " "
        .. tostring(S[over].points[2][2] == S[seg].fill and S[rest].points[1][2] == S[seg].fill and S[rest].shown) .. " "
        .. tostring(S[ring[1]].shown) .. " " .. tostring(InsetBy(edge, seg, -1)) .. " " .. S[row].height,
        "0 1 0 true true true 12", "darkness 100 and thick edges: black track, the shine kept to the fill, a pixel inside the edge, the row as tall")
    ns.Set("barStyle", "outline")
    ns.Resource:Apply()
    Equal(S[ring[1]].color[1] == ns.Style:BarColour("blue")[1] and S[ring[3]].shown, true, "Outline: in their colour")
    ns.Set("barDarkness", 0)
    ns.Set("thickEdges", false)
    ns.Resource:Apply()
    Equal(string.format("%g %g", S[track].color[1], S[track].color[4]) .. " " .. tostring(S[over].points[2][2] == seg) .. " "
        .. tostring(S[rest].shown) .. " " .. tostring(S[ring[1]].shown), "0.08 0.85 true false false", "both off: as before")
end
-- Unticked: gone, and the listener hears nothing again.
ns.Set("prdCombo", false)
ns.Resource:Apply()
Equal(tostring(ns.Resource:ComboRow()) .. " " .. tostring(S[row].shown) .. " [" .. ComboHears() .. "]", "nil false []",
    "unticked: gone, and nothing heard")
Equal(#printed, 0, "no errors from the combo points")
-- A rogue: nothing heard until they're ticked; ticked, your energy and
-- target too, and the points follow.
do
    Environment()
    Viewers(0)
    local UnitClass0 = _G.UnitClass
    _G.UnitClass = function() return "Rogue", "ROGUE" end
    prd = PRD()
    _G.PersonalResourceDisplayFrame = prd
    ns = Load(nil)
    local off = ComboHears()
    ns.Set("prdCombo", true)
    ns.Resource:Apply()
    points = 3
    Fire("UNIT_POWER_FREQUENT", "player", "ENERGY")
    local rogueRow = ns.Resource:ComboRow()
    Equal("[" .. off .. "] " .. ComboHears() .. " " .. tostring(rogueRow and S[S[rogueRow].children[3]].value), "[] " .. COMBO_SHOWN .. " 3",
        "a rogue: nothing heard while off; ticked, your energy and target too, and the points follow")
    _G.UnitClass = UnitClass0
    Equal(#printed, 0, "no errors from a rogue's combo points")
end

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
-- Something going wrong in a hook on Blizzard's cast bar: told once, and
-- never handed back to Blizzard's call.
do
    ns.Set("castBar", true)
    ns.CastBar:Apply()
    rawset(hold, "Stop", function() error("a fault stopping the fade") end)
    local fine = 0
    for _ = 1, 2 do
        if pcall(castingBar.PlayInterruptAnims, castingBar) then fine = fine + 1 end
    end
    rawset(hold, "Stop", nil)
    Equal(fine .. " " .. #printed .. " " .. tostring(tostring(printed[1]):match(
        "couldn't hide Blizzard's cast bar%. Please report this: .*a fault stopping the fade") ~= nil), "2 1 true",
        "a fault in a hook on Blizzard's cast bar: its call carries on; told once")
end
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

-- Icon details on Blizzard's icons -----------------------------------------------------------
-- The swipe's colour and see-through, the countdown's size, colour and spot,
-- and the edge line, on Blizzard's Essential, Utility and buff icons through
-- their own cooldowns' setters only. At the defaults nothing is hooked or set:
-- the icons stay exactly as Blizzard draws them. Changed, each icon's refresh
-- is post-hooked to set the swipe again after Blizzard's own, leaving
-- Blizzard's gold swipe over a buff that's up as it is; back at the defaults,
-- Blizzard's own swipe and edge line are put back, once. A failure is
-- reported once and never thrown into Blizzard's refresh.

do
    Environment()
    local v = Viewers(1)
    local GOLD, DARK = { r = 1, g = .95, b = .57, a = .7 }, { r = 0, g = 0, b = 0, a = .7 }
    _G.CooldownViewerConstants = { ITEM_AURA_COLOR = GOLD, ITEM_COOLDOWN_COLOR = DARK }
    local ns = Load(nil)
    local item, buff = First(v.essentialActive), First(v.buffsActive)
    -- Blizzard's own refreshes (CooldownViewer.lua): the swipe in the colour
    -- it picked, and its edge line only for charges.
    rawset(item, "RefreshSpellCooldownInfo", function(self)
        local colour = rawget(self, "cooldownSwipeColor") or DARK
        self.Cooldown:SetSwipeColor(colour.r, colour.g, colour.b, colour.a)
        self.Cooldown:SetDrawEdge(rawget(self, "cooldownShowDrawEdge") == true)
    end)
    local refresh = rawget(item, "RefreshSpellCooldownInfo")
    rawset(buff, "RefreshCooldownInfo", function(self)
        self.Cooldown:SetSwipeColor(DARK.r, DARK.g, DARK.b, DARK.a)
        self.Cooldown:SetDrawEdge(false)
    end)
    local function Refresh()
        Blizzard(item, "RefreshSpellCooldownInfo")
        Blizzard(buff, "RefreshCooldownInfo")
    end
    local function Swipe(frame)
        local c = S[frame.Cooldown].swipeColour
        return ("%g,%g,%g,%g"):format(c[1], c[2], c[3], c[4])
    end
    local function Edge(frame)
        local c = S[frame.Cooldown].edgeColour
        return tostring(S[frame.Cooldown].edge) .. (c and (" " .. ("%g,%g,%g,%g"):format(c[1], c[2], c[3], c[4])) or "")
    end
    local function Numbers(frame)
        local at = S[frame.Cooldown:GetCountdownFontString()].points[1]
        return at and (at[1] .. " " .. tostring(at[2] == frame.Cooldown) .. " " .. at[3] .. " " .. at[4] .. " " .. at[5]) or "Blizzard's"
    end
    local function Calls() return (S[item.Cooldown].addonCalls or 0) + (S[buff.Cooldown].addonCalls or 0) end
    Refresh()
    ns.Skin:ApplyIconDetails()
    Equal(Swipe(item) .. " " .. Edge(item) .. " " .. Swipe(buff) .. " | " .. Calls() .. " " .. tostring(rawget(item, "RefreshSpellCooldownInfo") == refresh)
        .. " | " .. S[item.Cooldown].countdownFont .. " " .. S[buff.Cooldown].countdownFont .. " " .. Numbers(item) .. " " .. Numbers(buff),
        "0,0,0,0.7 false 0,0,0,0.7 | 0 true | FECMFont25 FECMFont20 Blizzard's Blizzard's",
        "at the defaults: Blizzard's own swipe and numbers, nothing set by the addon, no refresh hooked")

    -- A purple swipe, 40% see-through: at once, and again after each of Blizzard's refreshes.
    ns.Set("swipeColour", "purple")
    ns.Set("swipeSeeThrough", 40)
    ns.Skin:ApplyIconDetails()
    local now = Swipe(item) .. " " .. Swipe(buff)
    Refresh()
    Equal(now .. " | " .. Swipe(item) .. " " .. Swipe(buff) .. " " .. tostring(rawget(item, "RefreshSpellCooldownInfo") ~= refresh) .. " "
        .. Edge(item), "0.6,0.43,0.91,0.6 0.6,0.43,0.91,0.6 | 0.6,0.43,0.91,0.6 0.6,0.43,0.91,0.6 true false",
        "a purple swipe at 40%: at once, and after Blizzard's refreshes (hooked), its edge line left as Blizzard's")
    -- Blizzard's gold swipe over a buff of the spell that's up stays gold.
    rawset(item, "cooldownSwipeColor", GOLD)
    Refresh()
    Equal(Swipe(item) .. " " .. Swipe(buff), "1,0.95,0.57,0.7 0.6,0.43,0.91,0.6", "Blizzard's gold over a buff that's up stays as it is")
    rawset(item, "cooldownSwipeColor", DARK)
    -- The edge line on every icon, then tinted green; after Blizzard's refresh too.
    ns.Set("swipeEdge", true)
    ns.Skin:ApplyIconDetails()
    now = Edge(item) .. " " .. Edge(buff)
    ns.Set("edgeColour", "green")
    ns.Skin:ApplyIconDetails()
    Refresh()
    Equal(now .. " | " .. Edge(item) .. " " .. Edge(buff), "true 1,1,1,1 true 1,1,1,1 | true 0.38,0.74,0.3,1 true 0.38,0.74,0.3,1",
        "the edge line: the game's own on every icon, then green, kept after Blizzard's refreshes")
    -- The countdown: 120%, red, along the bottom; the buff icon's too, and the charge count stays put.
    ns.Set("countdownSize", 120)
    ns.Set("countdownColour", "red")
    ns.Set("countdownSpot", "BOTTOM")
    ns.Skin:ApplyIconDetails()
    local font = _G.FECMCountdown30
    Equal(S[item.Cooldown].countdownFont .. " " .. S[buff.Cooldown].countdownFont .. " " .. table.concat(S[font].textColour, ",") .. " | "
        .. Numbers(item) .. " | " .. Numbers(buff) .. " | " .. S[item.ChargeCount.Current].points[1][1],
        "FECMCountdown30 FECMCountdown24 1,0.25,0.2 | BOTTOM true BOTTOM 0 1 | BOTTOM true BOTTOM 0 1 | BOTTOMRIGHT",
        "the numbers 120% in red, along the bottom of each icon, the charge count where Blizzard keeps it")
    -- A failure is reported once, never thrown into Blizzard's refresh.
    local swipe = ns.Style.Swipe
    ns.Style.Swipe = function() error("a broken swipe") end
    local ok = pcall(Refresh)
    ns.Style.Swipe = swipe
    Equal(tostring(ok) .. " " .. #printed .. " " .. tostring(printed[1] and printed[1]:find("couldn't colour a cooldown icon's swipe", 1, true) ~= nil),
        "true 1 true", "a failure in the hook: reported once, Blizzard's refresh carries on")
    table.remove(printed, 1)
    ns.Skin.lastError = nil
    -- Edge line off while the swipe stays purple: Blizzard never colours its
    -- own line, so the green goes at once (and the line with it), and after
    -- Blizzard's refreshes only the swipe is set again.
    ns.Set("swipeEdge", false)
    ns.Skin:ApplyIconDetails()
    local off = Edge(item) .. " " .. Edge(buff)
    local before = Calls()
    Refresh()
    Equal(off .. " | " .. Edge(item) .. " " .. Edge(buff) .. " " .. Swipe(item) .. " " .. (Calls() - before),
        "false 1,1,1,1 false 1,1,1,1 | false 1,1,1,1 false 1,1,1,1 0.6,0.43,0.91,0.6 2",
        "edge line off with the swipe still changed: Blizzard's own line back untinted at once, then only the swipe set")

    -- Back to the defaults: Blizzard's own swipe and its edge line for a
    -- spell's charges, once; then nothing set again, nor after its refreshes.
    rawset(item, "cooldownShowDrawEdge", true)
    for _, key in ipairs(ns.ICON_DETAILS) do ns.Set(key, ns.DEFAULTS[key]) end
    ns.Skin:ApplyIconDetails()
    Equal(Swipe(item) .. " " .. Edge(item) .. " " .. Swipe(buff) .. " " .. Edge(buff) .. " | " .. S[item.Cooldown].countdownFont .. " "
        .. S[buff.Cooldown].countdownFont .. " " .. Numbers(item) .. " | " .. Numbers(buff),
        "0,0,0,0.7 true 1,1,1,1 0,0,0,0.7 false 1,1,1,1 | FECMFont25 FECMFont20 CENTER true CENTER 0 0 | CENTER true CENTER 0 0",
        "defaults again: Blizzard's dark swipe, its own edge line for charges untinted, white numbers in the middle")
    local calls = Calls()
    ns.Skin:ApplyIconDetails()
    Refresh()
    Equal(Calls() - calls, 0, "and nothing set again by the addon, after Blizzard's refreshes either")
    -- A new icon, with the details changed: made in them, hooked as it's made.
    ns.Set("swipeColour", "white")
    local fresh = CooldownItem()
    rawset(fresh, "RefreshSpellCooldownInfo", refresh)
    Blizzard(v.utility, "OnAcquireItemFrame", fresh)
    Blizzard(fresh, "RefreshSpellCooldownInfo")
    Equal(Swipe(fresh) .. " " .. tostring(rawget(fresh, "RefreshSpellCooldownInfo") ~= refresh), "1,1,1,0.7 true",
        "a new icon with the details changed: in them as it's made, its refresh hooked")
    ns.Set("swipeColour", "black")
    ns.Skin:ApplyIconDetails()
    _G.CooldownViewerConstants = nil
    Equal(#printed, 0, "no errors")
end

-- Block and Colour fade (Look page) ----------------------------------------------------------
-- Block, the fourth Design: the Tracked Bars slimmer (their own status
-- bar's height, the one size allowed, and back) with their text a size
-- smaller, each bar and icon in its black edge with a thin warm line just
-- inside it (a pixel further in with Thick edges), on a warmer track, with
-- no shine, time box or spark; the display's bars and the combo points the
-- same at their own heights. Colour fade: each fill a gradient from a deeper
-- shade of its colour into a lighter one, a cosmetic setter on Blizzard's
-- fills only, put on again each time a bar is coloured (a colour wipes it,
-- here as in the game). Both off by default: nothing made, nothing faded.
do
    Environment()
    local v = Viewers(1)
    power = 3
    _G.UnitPowerType = function() return power, power == 3 and "ENERGY" or "MANA" end
    _G.UnitPower = function() return 2 end
    local prd, art = PRD()
    _G.PersonalResourceDisplayFrame = prd
    local made = 0
    _G.CreateColor = function(r, g, b, a) made = made + 1; return { r = r, g = g, b = b, a = a } end
    local ns = Load({ prdCombo = true })
    local bar, health = First(v.barsActive), prd.HealthBarsContainer.healthBar
    local row = assert(ns.Resource:ComboRow(), "a druid in cat form with combo points ticked")
    local segments = S[row].children
    -- Blizzard's fills, as the game hands them back: each allows its gradient alone.
    local fills = {}
    for _, owner in ipairs({ bar.Bar, health, prd.PowerBar }) do
        local fill = New("Texture", owner)
        Seal(fill)
        S[fill].allow = { SetGradient = true }
        S[owner].fill = fill
        fills[#fills + 1] = fill
    end
    for _, seg in ipairs(segments) do S[seg].fill = New("Texture", seg) end
    local function Apply()
        ns.Skin:ApplyBarLook()
        ns.Resource:Apply()
    end
    -- Block's warm line on owner: its strips (the soft cream ones), how many
    -- show, their colour, and where the top one sits on region.
    local function Warm(owner, region)
        local strips, shown = {}, 0
        for _, r in ipairs(S[owner].regions) do
            local c = S[r].color
            if S[r].layer == "OVERLAY" and S[r].sublevel == -6 and c and c[4] == .35 then
                strips[#strips + 1] = r
                if S[r].shown then shown = shown + 1 end
            end
        end
        if #strips == 0 then return "none" end
        local c, top = S[strips[1]].color, S[strips[1]].points[1]
        return string.format("%d %d %g %g %g | %s %s %s %g %g", #strips, shown, c[1], c[2], c[3], top[1],
            tostring(top[2] == (region or owner)), top[3], top[4], top[5])
    end
    local function Colour(region)
        local c = S[region].color
        return string.format("%g %g %g %g", c[1], c[2], c[3], c[4])
    end
    local function Fade(fill)
        local g = S[fill].gradient
        if not g then return "flat" end
        local a, b = g[2], g[3]
        return string.format("%s %.2f %.2f %.2f %g > %.2f %.2f %.2f %g", g[1], a.r, a.g, a.b, a.a, b.r, b.g, b.b, b.a)
    end
    local segTrack = Piece(segments[1], "BACKGROUND", nil)
    Equal(ns.Get("barStyle") .. " " .. tostring(ns.Get("colourFade")) .. " | " .. Warm(bar.Bar) .. " " .. Warm(bar.Icon) .. " "
        .. Warm(health) .. " " .. Warm(segments[1]) .. " | " .. Fade(fills[1]) .. " " .. Fade(fills[2]) .. " " .. made,
        "glass false | none none none none | flat flat 0", "both off by default: no warm line made, nothing faded, no colour made")

    -- Block.
    ns.Set("barStyle", "block")
    Apply()
    local sheen, box = Piece(bar.Bar, "OVERLAY", -8), Piece(bar.Bar, "OVERLAY", -7)
    Equal(S[bar.Bar].height .. " " .. S[bar.Bar.Name].font .. " " .. S[bar.Bar.Duration].font .. " " .. tostring(S[bar].height),
        "18 FECMFont12 FECMFont13 nil", "Block: the Tracked Bar slimmer, its text a size smaller, the item frame never resized")
    Equal(Warm(bar.Bar) .. " | " .. Warm(bar.Icon, bar.Icon.Icon), "4 4 1 0.84 0.59 | BOTTOMLEFT true TOPLEFT 0 -1 | 4 4 1 0.84 0.59 |"
        .. " BOTTOMLEFT true TOPLEFT 0 -1", "a thin warm line just inside the bar's edge, and inside its icon's art")
    Equal(Colour(bar.Bar.BarBG) .. " | " .. tostring(S[sheen].shown) .. " " .. tostring(S[box].shown) .. " " .. S[bar.Bar.Pip].alpha
        .. " | " .. table.concat(S[bar.Bar].barColour, ",") .. " " .. Colour(Piece(bar.Bar, "BACKGROUND", -8)) .. " | "
        .. S[bar.Bar.Duration].points[1][1], "0.11 0.085 0.075 0.92 | false false 0 | 1,0.5,0.25,1 0 0 0 1 | RIGHT",
        "on a warmer track, no shine, time box or spark, the fill solid in a black edge, the time on the right")
    Equal(Warm(health) .. " | " .. Warm(prd.PowerBar) .. " | " .. Colour(art) .. " " .. tostring(S[Piece(health, "OVERLAY", -8)].shown)
        .. " " .. tostring(S[health].height), "4 4 1 0.84 0.59 | BOTTOMLEFT true TOPLEFT 0 -1 | 4 4 1 0.84 0.59 | BOTTOMLEFT true"
        .. " TOPLEFT 0 -1 | 0.11 0.085 0.075 0.92 false nil", "the display's bars too, at their own height, on Blizzard's art made the warmer track")
    Equal(Warm(segments[1]) .. " | " .. Colour(segTrack), "4 4 1 0.84 0.59 | BOTTOMLEFT true TOPLEFT 0 -1 | 0.11 0.085 0.075 0.92",
        "and each combo point")
    ns.Set("thickEdges", true)
    Apply()
    Equal(Warm(bar.Bar) .. " | " .. Warm(health) .. " | " .. Warm(segments[1]), "4 4 1 0.84 0.59 | BOTTOMLEFT true TOPLEFT 1 -2 | 4 4 1"
        .. " 0.84 0.59 | BOTTOMLEFT true TOPLEFT 1 -2 | 4 4 1 0.84 0.59 | BOTTOMLEFT true TOPLEFT 1 -2",
        "Thick edges: the warm line a pixel further in, inside the second black one")
    ns.Set("thickEdges", false)
    ns.Set("barStyle", "glass")
    Apply()
    Equal(S[bar.Bar].height .. " " .. S[bar.Bar.Name].font .. " " .. S[bar.Bar.Duration].font .. " | " .. Warm(bar.Bar):sub(1, 3) .. " "
        .. Warm(bar.Icon):sub(1, 3) .. " " .. Warm(health):sub(1, 3) .. " " .. Warm(segments[1]):sub(1, 3) .. " | " .. Colour(bar.Bar.BarBG)
        .. " " .. Colour(art) .. " " .. tostring(S[sheen].shown) .. " " .. S[bar.Bar.Pip].alpha,
        "26 FECMFont13 FECMFont15 | 4 0 4 0 4 0 4 0 | 0.08 0.08 0.09 0.85 0.08 0.08 0.09 0.85 true 1",
        "back to Glass: today's bar, text, track, shine and spark, every warm line hidden")

    -- Colour fade.
    ns.Set("colourFade", true)
    Apply()
    Equal(Fade(fills[1]) .. " | " .. table.concat(S[bar.Bar].barColour, ","), "HORIZONTAL 0.94 0.51 0.12 1 > 1.00 0.75 0.24 1 | 1,0.5,0.25,1",
        "Colour fade: Orange's own fade, deeper to lighter, over its flat colour")
    Equal(Fade(fills[2]) .. " | " .. Fade(fills[3]) .. " | " .. Fade(S[segments[1]].fill),
        "HORIZONTAL 0.00 0.80 0.00 1 > 0.40 1.00 0.40 1 | HORIZONTAL 0.00 0.00 0.80 1 > 0.40 0.40 1.00 1 | HORIZONTAL 0.70 0.16 0.10 1 >"
        .. " 0.92 0.52 0.48 1", "Blizzard's green and blue on the display, and the combo points' red: a step deeper and a step lighter")
    local gradients = S[fills[1]].gradients
    Blizzard(bar, "OnCooldownIDSet")
    Equal(S[fills[1]].gradients - gradients, 0, "given the same spell again: nothing put on again")
    -- Blizzard recolouring a bar wipes the fade; it's put on again in that colour.
    health:SetStatusBarColor(0, .9, 0)
    Equal(Fade(fills[2]), "HORIZONTAL 0.00 0.72 0.00 1 > 0.40 0.94 0.40 1", "Blizzard recolours the health bar: faded again in its new colour")
    -- A colour the game keeps secret: flat, never worked on.
    _G.issecretvalue = function(value) return rawequal(value, SECRETS.number) end
    health:SetStatusBarColor(SECRETS.number, SECRETS.number, SECRETS.number)
    Equal(Fade(fills[2]), "flat", "a secret colour stays flat")
    _G.issecretvalue = nil
    health:SetStatusBarColor(0, 1, 0)
    ns.Set("barStyle", "outline")
    ns.Set("barColour", "class")
    Apply()
    Equal(Fade(fills[1]) .. " | " .. Fade(fills[2]), "HORIZONTAL 0.80 0.39 0.03 0.45 > 1.00 0.69 0.42 0.45 | HORIZONTAL 0.00 0.80 0.00 0.45 >"
        .. " 0.40 1.00 0.40 0.45", "Outline: as see-through as its fill; your class colour a step deeper and lighter")
    ns.Set("barStyle", "block")
    ns.Set("barColour", "purple")
    Apply()
    Equal(Fade(fills[1]) .. " " .. Warm(bar.Bar):sub(1, 3), "HORIZONTAL 0.42 0.42 0.97 1 > 0.77 0.43 0.97 1 4 4",
        "with any design: Block in Purple's own fade")
    -- Your cast bar: the warm line on the bar and its icon, each cast's
    -- colour faded as it's given (gold, then red once broken off).
    local cast = ns.CastBar:Make(nil)
    S[cast.bar].fill = New("Texture", cast.bar)
    ns.CastBar:Look(cast, false)
    Equal(Warm(cast.bar):sub(1, 3) .. " " .. Warm(cast, cast.icon) .. " | " .. Colour(cast.bar.background) .. " | " .. Fade(S[cast.bar].fill),
        "4 4 4 4 1 0.84 0.59 | BOTTOMLEFT true TOPLEFT 0 -1 | 0.11 0.085 0.075 0.92 | HORIZONTAL 0.80 0.56 0.00 1 > 1.00 0.82 0.40 1",
        "your cast bar: the warm line on it and inside its icon, the warmer track, a cast's gold faded")
    ns.CastBar:Look(cast, false, true)
    Equal(Fade(S[cast.bar].fill), "HORIZONTAL 0.68 0.12 0.08 1 > 0.91 0.49 0.46 1", "broken off: its red faded, as it's given")
    ns.Set("barStyle", "glass")
    ns.Set("barColour", "orange")
    ns.Set("colourFade", false)
    Apply()
    Equal(Fade(fills[1]) .. " " .. Fade(fills[2]) .. " " .. Fade(fills[3]) .. " " .. Fade(S[segments[1]].fill), "flat flat flat flat",
        "unticked: every bar flat again")
    -- A game with no colours to make a gradient from: flat, quietly.
    _G.CreateColor = nil
    ns.Set("colourFade", true)
    Apply()
    Equal(Fade(fills[1]) .. " " .. Fade(fills[2]) .. " " .. #printed, "flat flat 0", "no CreateColor: flat, nothing said")
    -- The game refusing a gradient: that bar flat, kept quietly for /ccm
    -- debug, and every bar flat for the session.
    _G.CreateColor = function(r, g, b, a) return { r = r, g = g, b = b, a = a } end
    local SetGradient = Proto.SetGradient
    function Proto:SetGradient() error("no gradients here") end
    ns.Skin:ApplyBarLook()
    Proto.SetGradient = SetGradient
    ns.Resource:Apply()
    Equal(Fade(fills[1]) .. " " .. table.concat(S[bar.Bar].barColour, ",") .. " " .. Fade(fills[2]) .. " " .. tostring(ns.Style:Fades()) .. " "
        .. tostring(ns.Style.fadeError ~= nil) .. " " .. #printed, "flat 1,0.5,0.25,1 flat false true 0",
        "refused: flat in its colour, every bar after it flat too, nothing said")
    _G.CreateColor = nil
    Equal(#printed, 0, "no errors")
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
