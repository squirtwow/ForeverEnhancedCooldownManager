-- Run the actual addon files against a mock game for the Totems bar (a
-- player's idea): only for shamans, off by default, its settings, its four
-- spots (greyed until a totem is down, then its icon and time), the game's
-- secret totem answers handed on in a fight and never read, Red when out of
-- range through the game's aura containers (never shown or hidden after),
-- its layout, order, out of combat choice, moving it, share strings and
-- profiles leaving it alone, the look, the debug report and the
-- development check. The mock game is a copy of Tools/TestBars.lua's:
-- Tools/TestMockSync.mjs checks the two match, and with --write copies it across.
local checks = 0
local SECRET -- the tests' own secret, made with the mock game's below
-- Also fails on a secret the addon misused since the last check (below), even
-- one its own pcall kept quiet, and on a widget method Forever lacks that the
-- addon looked for. Secrets match secrets: SECRET stands for any.
local function Equal(actual, expected, label)
    checks = checks + 1
    if SecretMisuse[1] then error(label .. ": the addon misused a secret before this check: " .. SecretMisuse[1], 2) end
    if WidgetMisses[1] then error(label .. ": the addon looked for a method Forever lacks before this check: " .. WidgetMisses[1], 2) end
    if IsSecret(actual) or IsSecret(expected) then
        assert(IsSecret(actual) and IsSecret(expected) and (rawequal(actual, expected) or rawequal(expected, SECRET)
            or rawequal(actual, SECRET)), label .. ": expected " .. tostring(expected) .. ", got " .. tostring(actual))
        return
    end
    assert(actual == expected, label .. ": expected " .. tostring(expected) .. ", got " .. tostring(actual))
end

-- Mock frames -----------------------------------------------------------------------

local S = setmetatable({}, { __mode = "k" })
local objects = {} -- everything created, newest last
local Proto = {}
local frames = {}

-- Like the game: each kind of widget has only the methods Forever gives it,
-- and its template's (Tools/WidgetMethods.lua, made from Forever's widget
-- API docs and the templates' Lua mixins). Any other capitalised name is nil,
-- as in the game, and one an addon file looks for is noted in WidgetMisses
-- (its file and line), so a call to a method Forever lacks (a retail-only one,
-- or a typo) fails the next check, even inside the addon's own pcall or an
-- `if x.Method then`. Blizzard's frames the tests stand in for get their Lua
-- methods by name in S[frame].mixin. (Globals: this file's main chunk is at
-- Lua's 200 locals.)
do
    local list = dofile("Tools/WidgetMethods.lua")
    local function Into(set, names) for name in names:gmatch("%S+") do set[name] = true end return set end
    local kinds, templates = {}, {}
    for kind, apis in pairs(list.kinds) do
        kinds[kind] = {}
        for api in apis:gmatch("%S+") do Into(kinds[kind], assert(list.apis[api], api)) end
    end
    for name, names in pairs(list.templates) do templates[name] = Into({}, names) end
    local blizzard = {}
    for name, names in pairs(list.blizzard) do blizzard[name] = Into({}, names) end
    -- One of Blizzard's own frames a test stands in for: its Lua methods too.
    function Blizzard(frame, name)
        S[frame].mixin = assert(blizzard[name], "the mock game has no " .. name .. ": add it to Tools/GenerateWidgetMethods.mjs")
        return frame
    end
    WidgetMisses = {}
    -- Methods an addon file looks for on purpose and does without where a
    -- frame lacks them: Skin.lua's Read finds these getters of Blizzard's
    -- cooldown items on them, and none on the window's sample Tracked Bar.
    -- DotsBand.lua's are mostly keys rather than methods: the shapes
    -- Blizzard's target frame and its nameplates have had
    -- (HealthBarsContainer.healthBar, Portrait, UnitFrame), not all of which
    -- this client's own frames have. Its search tries each shape and takes
    -- whichever one the frame really has, so a frame without one answers
    -- nothing rather than being noted a miss. GetStatusBarTexture is in the
    -- list for the same reason: finding a health bar on a nameplate another
    -- addon has restyled means asking each of the plate's own children whether
    -- it is a status bar at all, and most of them are not.
    local LOOKS = { ["Skin.lua GetBaseSpellID"] = true, ["Skin.lua GetEquipSlot"] = true,
        ["DotsBand.lua HealthBarsContainer"] = true, ["DotsBand.lua Portrait"] = true,
        ["DotsBand.lua UnitFrame"] = true, ["DotsBand.lua GetStatusBarTexture"] = true }
    -- The first Lua code up the stack past WidgetHas and the widget's
    -- __index, if it's an addon file's: its file and line.
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
    function WidgetKind(kind)
        assert(kinds[kind], "the mock game has no " .. tostring(kind) .. " widgets: add them to Tools/GenerateWidgetMethods.mjs")
    end
    function WidgetTemplate(template)
        for name in tostring(template):gmatch("[^,%s]+") do
            assert(templates[name], "the mock game has no " .. name .. ": add it to Tools/GenerateWidgetMethods.mjs")
        end
    end
    -- Whether a widget has the method: its kind's, its template's or, for
    -- Blizzard's frames, their own Lua ones. A miss by an addon file is noted.
    function WidgetHas(s, key)
        if kinds[s.kind][key] or (s.mixin and s.mixin[key]) then return true end
        for name in (s.frameTemplate or ""):gmatch("[^,%s]+") do
            if templates[name][key] then return true end
        end
        local at = Addon(key)
        if at then WidgetMisses[#WidgetMisses + 1] = at .. ": Forever has no " .. s.kind .. ":" .. key end
        return false
    end
end

local function New(kind, parent)
    WidgetKind(kind)
    local obj = {}
    S[obj] = { kind = kind, parent = parent, shown = true, last = {}, scripts = {}, events = {}, points = {},
        width = 0, height = 0, alpha = 1 }
    objects[#objects + 1] = obj
    -- Each frame knows the frames inside it (not its textures and text,
    -- which have no OnShow or OnHide), so showing or hiding it reaches them.
    if parent and S[parent] and kind ~= "Texture" and kind ~= "FontString" then
        local kids = S[parent].kids
        if not kids then
            kids = {}
            S[parent].kids = kids
        end
        kids[#kids + 1] = obj
    end
    -- A method the mock doesn't model keeps its last call's arguments.
    setmetatable(obj, { __index = function(_, key)
        if type(key) ~= "string" or not key:match("^[A-Z]") or not WidgetHas(S[obj], key) then return nil end
        local method = Proto[key]
        if method then return method end
        return function(self, ...) S[self].last[key] = table.pack(...) end
    end })
    return obj
end

local function Last(obj, method, i) local call = S[obj].last[method]; return call and call[i or 1] end

local watched = setmetatable({}, { __mode = "k" })
-- Like the game: OnShow and OnHide run as a frame comes into sight or goes
-- out of it, for the frame and then every shown frame inside it, all inside
-- the code that showed or hid it. A frame shown or hidden inside a hidden
-- one changes quietly; its OnShow waits for that one to show.
local Toggled
do
    -- (The frame shown or hidden comes first; the rest stay shown
    -- themselves. One its own script just changed is left there.)
    local function Seen(self, v, first)
        local s = S[self]
        local script = s.scripts[v and "OnShow" or "OnHide"]
        if script then script(self) end
        local kids, still = s.kids, s.shown
        if first then still = s.shown == v end
        if not (kids and still) then return end
        for i = 1, #kids do
            local kid = kids[i]
            local k = S[kid]
            if k.shown and k.parent == self then Seen(kid, v) end
        end
    end
    function Toggled(self, v)
        local s = S[self]
        if watched[self] and InCombatLockdown() and s.shown ~= v then s.combatToggle = true end
        if s.shown == v then return end
        local parent = s.parent
        local inSight = parent == nil or S[parent] == nil or parent:IsVisible()
        s.shown = v
        if inSight then Seen(self, v, true) end
    end
end
-- Moved into another frame: it follows that one's showing and hiding now.
function Proto:SetParent(parent)
    local s = S[self]
    assert(not s.handed, "a region an aura icon's animation animates moved")
    s.last.SetParent = table.pack(parent)
    local old = s.parent and S[s.parent]
    if old and old.kids then
        for i = #old.kids, 1, -1 do
            if old.kids[i] == self then table.remove(old.kids, i) end
        end
    end
    s.parent = parent
    if parent and S[parent] then
        S[parent].kids = S[parent].kids or {}
        table.insert(S[parent].kids, self)
    end
end

-- The game has this and the mock did not, so anything that hangs itself off
-- a frame's parent fell back to the frame instead and the suite passed a
-- path it had never run (27 Nov 2026: the DoTs band moved off the health bar
-- because a unit frame addon sets that bar to no opacity, and the test for
-- it could not tell the difference).
function Proto:GetParent() return S[self].parent end
function Proto:Show() Toggled(self, true) end
function Proto:Hide() Toggled(self, false) end
function Proto:SetShown(v) Toggled(self, v and true or false) end
function Proto:IsShown() return S[self].shown end
function Proto:SetScript(k, fn) S[self].scripts[k] = fn end
function Proto:GetScript(k) return S[self].scripts[k] end
-- Like the game: a hook runs after the script; setting a script drops hooks.
function Proto:HookScript(k, fn)
    local old = S[self].scripts[k]
    S[self].scripts[k] = function(...)
        if old then old(...) end
        fn(...)
    end
end
-- Like the game: the combat log is shut to addons on this client (seen in
-- game, 26 Nov 2026, build 1.60.1.71139), and registering for it is itself a
-- blocked action that puts a warning box on the player's screen. So the mock
-- game refuses it outright, and any attempt to register for it fails the
-- suite there and then rather than quietly working here and warning in game.
-- (A global: this file's main chunk is at Lua's 200 locals.)
function NoCombatLog(event)
    assert(event ~= "COMBAT_LOG_EVENT_UNFILTERED",
        "the combat log is shut on this client: registering for COMBAT_LOG_EVENT_UNFILTERED is a blocked action")
end
function Proto:RegisterEvent(e) NoCombatLog(e); S[self].events[e] = true end
function Proto:RegisterUnitEvent(e) NoCombatLog(e); S[self].events[e] = true end
function Proto:GetAlpha() return S[self].alpha end
function Proto:UnregisterAllEvents() S[self].events = {} end
function Proto:UnregisterEvent(e) S[self].events[e] = nil end
function Proto:CreateTexture() return New("Texture", self) end
-- Mask textures, and the masks on each texture, in the order added.
function Proto:CreateMaskTexture() return New("MaskTexture", self) end
function Proto:AddMaskTexture(mask)
    local s = S[self]
    s.masks = s.masks or {}
    table.insert(s.masks, mask)
end
function Proto:RemoveMaskTexture(mask)
    local masks = S[self].masks or {}
    for i = #masks, 1, -1 do if masks[i] == mask then table.remove(masks, i) end end
end
-- The font it starts in, as the game does: the template's.
function Proto:CreateFontString(_, _, template)
    local text = New("FontString", self)
    S[text].template = template
    return text
end
function Proto:SetText(t) S[self].text = t end
function Proto:GetText() return S[self].text end
function Proto:SetChecked(v) S[self].checked = v and true or false end
function Proto:GetChecked() return S[self].checked end
function Proto:SetPoint(...) table.insert(S[self].points, table.pack(...)) end
function Proto:ClearAllPoints() S[self].points = {} end
-- A status bar's fill texture, sized as the game sizes it: the share of the
-- way from its least to its most that its value stands at, across it or, with
-- a vertical orientation, up it. The value may be a secret, since the game
-- works that share out itself and an addon can't; the mock game, which is the
-- game here, looks behind one (Behind, with the secrets below). So may the
-- range: the DoTs band hands over your target's sealed max health as its most
-- and the plain damage still to come as its value, the other way round from
-- the Resource fill, and the game does that division too. A bar with no
-- texture of its own yet (a slider, say) has nothing to size.
-- (A global: this file's main chunk is at Lua's 200 locals.)
function BarFill(bar)
    local s = S[bar]
    local texture = s.barTexture
    if not texture then return end
    -- Unset is 0 to 1; a secret the mock game can look behind is the number
    -- behind it; a secret with none (a test's bare SECRET) leaves the fill
    -- empty, as it did before the range could be secret at all.
    local least = s.barMin == nil and 0 or Behind(s.barMin)
    local most = s.barMax == nil and 1 or Behind(s.barMax)
    local value = Behind(s.barValue)
    local share = 0
    if type(value) == "number" and type(most) == "number" and type(least) == "number" and most > least then
        share = math.max(0, math.min(1, (value - least) / (most - least)))
    end
    local fill = S[texture]
    if s.vertical then
        fill.width, fill.height = s.width or 0, (s.height or 0) * share
    else
        fill.width, fill.height = (s.width or 0) * share, s.height or 0
    end
end
function Proto:SetSize(w, h) S[self].width, S[self].height = w, h; BarFill(self) end
function Proto:GetSize() return S[self].width, S[self].height end
function Proto:SetWidth(w) S[self].width = w; BarFill(self) end
function Proto:SetHeight(h) S[self].height = h; BarFill(self) end
-- A status bar's range, value, orientation and fill texture: each kept as the
-- last call's arguments too, as every other method is.
function Proto:SetMinMaxValues(least, most)
    local s = S[self]
    s.last.SetMinMaxValues, s.barMin, s.barMax = table.pack(least, most), least, most
    BarFill(self)
end
function Proto:SetValue(value)
    local s = S[self]
    s.last.SetValue, s.barValue = table.pack(value), value
    BarFill(self)
end
function Proto:SetOrientation(way)
    local s = S[self]
    s.last.SetOrientation, s.vertical = table.pack(way), way == "VERTICAL"
    BarFill(self)
end
function Proto:SetStatusBarTexture(texture)
    local s = S[self]
    s.last.SetStatusBarTexture = table.pack(texture)
    s.barTexture = s.barTexture or New("Texture", self)
    BarFill(self)
end
-- Like the game: the bar's own fill texture, which it sizes itself, made the
-- first time it's asked for.
function Proto:GetStatusBarTexture()
    local s = S[self]
    s.barTexture = s.barTexture or New("Texture", self)
    return s.barTexture
end
function Proto:GetWidth() return S[self].width end
function Proto:GetHeight() return S[self].height end
function Proto:GetName() return S[self].name end
-- The frames inside it, as the game gives them: its textures and its text are
-- not children (they have no OnShow of their own either, which is why the mock
-- keeps them apart), and one moved into another frame goes with it.
function Proto:GetChildren()
    local kids = S[self].kids
    if not kids then return end
    return table.unpack(kids)
end
function Proto:GetVerticalScroll() return S[self].scroll or 0 end
function Proto:SetVerticalScroll(v) S[self].scroll = v end
function Proto:GetEffectiveScale() return 1 end
function Proto:SetBackdropBorderColor(r, g, b, a) S[self].border = { r, g, b, a } end
function Proto:SetTextColor(r, g, b) S[self].colour = { r, g, b } end
function Proto:SetShadowColor(r, g, b, a) S[self].shadow = a end
-- (Like the game: a region an animation handed to an aura icon animates
-- keeps its alpha the game's.)
function Proto:SetAlpha(a)
    assert(not S[self].handed, "the alpha of a region an aura icon's animation animates")
    S[self].alpha = a
end
-- Animations, as the game makes them: a group on a frame or texture (it's
-- that one's, not a frame inside it, so it isn't shown or hidden with it),
-- and the animations in it, each on the group's own frame or texture unless
-- given a target. Each group counts its plays.
function Proto:CreateAnimationGroup()
    local group = New("AnimationGroup")
    S[group].parent, S[group].anims, S[group].plays = self, {}, 0
    return group
end
function Proto:CreateAnimation(kind)
    assert(not S[self].handed, "an animation added to a group handed to an aura icon")
    local anim = New(kind)
    S[anim].parent = self
    table.insert(S[self].anims, anim)
    return anim
end
function Proto:GetAnimations() return table.unpack(S[self].anims) end
function Proto:SetTarget(target) S[self].target = target end
function Proto:GetTarget() local s = S[self]; return s.target or S[s.parent].parent end
function Proto:Play() local s = S[self]; s.plays, s.playing = (s.plays or 0) + 1, true end
function Proto:Stop() S[self].playing = false end
function Proto:IsPlaying() return S[self].playing == true end
function Proto:GetCenter() return S[self].cx, S[self].cy end
function Proto:GetFrameLevel() return 1 end
function Proto:GetStringWidth() return 40 end
-- Wrapped text: about six units a letter, twelve a line.
function Proto:GetStringHeight()
    local s = S[self]
    return math.max(1, math.ceil(#(s.text or "") * 6 / math.max(1, s.width))) * 12
end
function Proto:GetFont() return "font", 12, "" end
function Proto:Click() S[self].scripts.OnClick(self) end
function Proto:SetTexture(t) S[self].texture = t end
function Proto:SetVertexColor(r, g, b) S[self].tint = { r, g, b } end
function Proto:SetDesaturated(v) S[self].desaturated = v end
-- Like the game: the alpha for true, then for false (1 and 0 unless given).
-- A secret answer is kept as it is; a plain one sets the alpha it picks.
function Proto:SetAlphaFromBoolean(v, ifTrue, ifFalse)
    local s = S[self]
    s.alphaFrom, s.alphaIf = v, tostring(ifTrue) .. " " .. tostring(ifFalse)
    if type(v) == "boolean" and not IsSecret(v) then s.alpha = v and (ifTrue or 1) or (ifFalse or 0) end
end
-- A cooldown's countdown numbers, made the first time they're asked for.
function Proto:GetCountdownFontString() local s = S[self]; s.numbers = s.numbers or New("FontString", self); return s.numbers end
function Proto:IsMouseOver() return S[self].mouseOver == true end
-- Like the game: shown, and so is everything it sits in.
function Proto:IsVisible()
    local s = S[self]
    if not s.shown then return false end
    local parent = s.parent
    return parent == nil or S[parent] == nil or parent:IsVisible()
end
-- What a player sees (for the tests): shown, in shown frames, and not
-- see-through (its opacity times theirs). A bar gone right out is shown but
-- not in sight. (Global: TestBars' main chunk is at Lua's 200 locals.)
function InSight(frame)
    local alpha = 1
    while frame and S[frame] do
        local s = S[frame]
        if not s.shown then return false end
        alpha = alpha * (s.alpha or 1)
        frame = s.parent
    end
    return alpha > 0
end

local function Fire(event, ...)
    for _, f in ipairs(frames) do
        if S[f].events[event] and S[f].scripts.OnEvent then S[f].scripts.OnEvent(f, event, ...) end
    end
end

-- Game environment ------------------------------------------------------------------

-- Secrets, as the game keeps them in a fight. Like the game's: when the
-- addon's own code compares one, does sums with it, indexes, calls, measures
-- or iterates it, joins it into text or turns it into text, it errors
-- ("attempt to compare a secret number value"), and type() says what it
-- stands for, so a type check alone never gets past one. Each such use is
-- also noted (SecretMisuse, with the addon's file and line), so one inside
-- the addon's own pcall still fails the next check. The mock game and the
-- tests are the game's own code here, so they may look. Lua has no hook for
-- `if secret then` or `secret == plain`, so those two can't be caught.
-- SECRET is the tests' own: the mock game hands back its typed twin
-- (SECRETS.number, .boolean or .string) for what each API returns (Typed).
do
    local rawtype, kinds = type, setmetatable({}, { __mode = "k" })
    -- The first Lua code up the stack, past the game's own C functions ("J" in fengari)
    -- (tostring, string.format): the addon's (its file and line) or not.
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
    local function Kind(a, b) return kinds[a] or kinds[b] end
    local function Boom(verb, plain)
        return function(a, b)
            local at = Addon()
            if not at then return plain(a, b) end
            local message = "attempt to " .. verb .. " a secret " .. Kind(a, b) .. " value"
            SecretMisuse[#SecretMisuse + 1] = at .. ": " .. message
            error(message, 2)
        end
    end
    local function Same(a) return a end
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
    local function Make(kind)
        local secret = setmetatable({}, META)
        kinds[secret] = kind
        return secret
    end
    SECRET = Make("table")
    SECRETS = { number = Make("number"), boolean = Make("boolean"), string = Make("string") }
    SecretMisuse = {}
    function IsSecret(v) return rawtype(v) == "table" and kinds[v] ~= nil end
    -- A secret number with a number behind it, for the sums the game does
    -- itself: your power, which the game keeps from an addon in and out of a
    -- fight but still measures a status bar's fill against (BarFill, above).
    -- The addon can no more read one of these than any other secret.
    local behind = setmetatable({}, { __mode = "k" })
    function SecretNumber(value)
        local secret = Make("number")
        behind[secret] = value
        return secret
    end
    -- The number behind a secret for the mock game's own sums, nothing for a
    -- secret with none, and a plain value as it is.
    function Behind(v)
        if rawtype(v) == "table" and kinds[v] then return behind[v] end
        return v
    end
    -- What an API hands back for a value the test set: SECRET as the kind it returns.
    function Typed(kind, v)
        if rawequal(v, SECRET) then return SECRETS[kind] end
        return v
    end
    _G.type = function(v)
        if rawtype(v) == "table" and kinds[v] then return kinds[v] end
        return rawtype(v)
    end
end
local book, usable, noMana, range, active, target, cvars, printed
local hostile = true -- whether the target can be attacked
local cooldownCalls, lockdown, containers, containerCallsInCombat
local trinket, trinketCooldown, bagItems, itemCooldown, itemCount
local ammo, ammoCount -- the equipped ammunition and how many you carry
local bindings, cvarOn, reloads, timers
-- Your action bars: what each slot holds, the key on each binding, macros,
-- how many slots have been read, and the main bar's page and bonus bar.
local actionSlots, keyOf, macroSpells, macroItems, actionReads, actionPage, bonusIndex
local prdOn = true -- Blizzard's Personal Resource Display switched on
local clock = 100 -- the game's time in seconds, for the cast bar
-- Who is logged in: a GUID tells characters apart, even with the same name.
local character = { guid = "Player-1-0001", name = "Zriel", realm = "Zephras" }

local function Book(ranks)
    -- Two tabs: General (Attack), Balance (Moonfire ranks, Wrath, a passive,
    -- a future spell) and Arms (Overpower).
    book = {
        { name = "General", items = { { name = "Attack", spellID = 6603 },
            { name = "Walk on Air", subName = "Racial", spellID = 1259416, iconID = 1 } } },
        { name = "Balance", items = {
            { name = "Moonfire", subName = "Rank 1", spellID = 8921, iconID = 136096 },
            { name = "Moonfire", subName = "Rank 2", spellID = 8924, iconID = 136096 },
            { name = "Wrath", subName = "Rank 1", spellID = 5176, iconID = 136006 },
            { name = "Thorns", subName = "Rank 1", spellID = 467, iconID = 136104 },
            { name = "Thorns", subName = "Rank 2", spellID = 782, iconID = 136104 },
            { name = "Natural Weapons", spellID = 16902, isPassive = true },
            { name = "Starfire", spellID = 2912, future = true },
        } },
        { name = "Arms", items = { { name = "Overpower", subName = "Rank 1", spellID = 7384, iconID = 132223 } } },
    }
    if ranks then table.insert(book[2].items, 3, { name = "Moonfire", subName = "Rank 3", spellID = 8925, iconID = 136096 }) end
end

local function Environment(keepCVars)
    frames, printed, cooldownCalls = {}, {}, {}
    usable, noMana, range, active, target = {}, {}, {}, false, false
    lockdown, containers, containerCallsInCombat = false, {}, 0
    -- Blizzard's aura container code run inside the addon's (below), and
    -- whether its icons take shown animations (all of them, unless a test says).
    ContainerRuns, ShownAnimations = {}, nil
    bindings, cvarOn, reloads, timers = {}, true, 0, {}
    _G.C_Timer = { After = function(_, fn) timers[#timers + 1] = fn end }
    actionSlots, keyOf, macroSpells, macroItems, actionReads, actionPage, bonusIndex = {}, {}, {}, {}, 0, 1, nil
    _G.GetActionInfo = function(slot)
        actionReads = actionReads + 1
        local a = actionSlots[slot]
        if a then return a[1], a[2], a[3] end
    end
    _G.GetBindingKey = function(binding) return keyOf[binding] end
    _G.GetMacroSpell = function(i) return macroSpells[i] end
    _G.GetMacroItem = function(i) local id = macroItems[i]; if id then return "Item", "|Hitem:" .. id .. "::|h[Item]|h" end end
    _G.C_ActionBar = { GetActionBarPage = function() return actionPage end, HasBonusActionBar = function() return bonusIndex ~= nil end,
        GetBonusBarIndex = function() return bonusIndex end, HasVehicleActionBar = function() return false end,
        HasOverrideActionBar = function() return false end, HasTempShapeshiftActionBar = function() return false end }
    _G.GetCursorPosition = function() return 0, 0 end
    _G.GetCursorInfo = function() end -- nothing picked up
    _G.ClearCursor = function() end
    _G.ReloadUI = function()
        assert(not lockdown, "blocked ReloadUI in combat")
        assert(S[FECMFrame].shown, "window hidden before reload")
        reloads = reloads + 1
    end
    _G.RAID_CLASS_COLORS = { DRUID = { r = 1, g = .49, b = .04 } }
    _G.CreateColor = function(r, g, b, a) return { r = r, g = g, b = b, a = a } end
    _G.C_Texture = { GetAtlasInfo = function(atlas) if atlas == "classicon-druid" then return {} end end }
    trinket, trinketCooldown, bagItems, itemCooldown, itemCount = nil, { 0, 0, 1 }, {}, { 0, 0, 1 }, {}
    ammo, ammoCount = nil, 0
    _G.INVSLOT_AMMO = 0
    _G.GetInventoryItemID = function(_, slot)
        if slot == 0 then return ammo end
        if slot == 18 then return RangedWorn end -- (a global: this file's main chunk is at Lua's 200 locals)
        return slot == 13 and trinket or nil
    end
    _G.GetInventoryItemLink = function(_, slot)
        if slot == 0 then return "|cffffffff|Hitem:" .. tostring(ammo) .. "|h[Rough Arrow]|h|r" end
        return "|cff1eff00|Hitem:" .. tostring(trinket) .. "|h[Lucky Charm]|h|r"
    end
    _G.GetInventoryItemCount = function(_, slot) assert(slot == 0); return Typed("number", ammoCount) end
    _G.GetInventoryItemTexture = function() return 777 end
    _G.GetInventoryItemCooldown = function(_, slot)
        assert(slot == 13)
        return Typed("number", trinketCooldown[1]), Typed("number", trinketCooldown[2]), Typed("number", trinketCooldown[3])
    end
    _G.C_Container = {
        GetContainerNumSlots = function(bag) return bag == 0 and #bagItems or 0 end,
        GetContainerItemInfo = function(bag, slot) return bagItems[slot] end,
    }
    _G.C_Item = {
        GetItemSpell = function(id) return ({ [118] = "Healing Potion", [117] = "Food", [2698] = "Learning" })[id] end,
        -- Rough Arrow and Light Shot: projectiles (6), worn in the ammo slot.
        GetItemInfoInstant = function(id)
            local class = ({ [118] = { 0, 1 }, [117] = { 0, 5 }, [2698] = { 9, 0 }, [2512] = { 6, 2 }, [2516] = { 6, 3 },
                [5240] = { 2, 19 }, [2504] = { 2, 2 } })[id] -- (a wand and a bow)
                or { 15, 0 }
            return id, nil, nil, class[1] == 6 and "INVTYPE_AMMO" or "", nil, class[1], class[2]
        end,
        GetItemCooldown = function()
            return Typed("number", itemCooldown[1]), Typed("number", itemCooldown[2]), Typed("number", itemCooldown[3])
        end,
        GetItemCount = function(id) return Typed("number", itemCount[id] or 0) end,
        IsUsableItem = function() return true, false end,
        GetItemIconByID = function() return 888 end,
        GetItemNameByID = function(id) return id == 118 and "Minor Healing Potion" or nil end,
    }
    if not keepCVars then cvars = {} end
    Book(false)
    _G.Enum = { SpellBookSpellBank = { Player = 0 }, SpellBookItemType = { Spell = 1, FutureSpell = 2, Flyout = 3 },
        UnitAuraSoundTrigger = { Added = 0, ApplicationsIncreased = 1, Removed = 2 } }
    _G.C_SpellBook = {
        GetNumSpellBookSkillLines = function() return #book end,
        GetSpellBookSkillLineInfo = function(line)
            local offset = 0
            for i = 1, line - 1 do offset = offset + #book[i].items end
            return { name = book[line].name, itemIndexOffset = offset, numSpellBookItems = #book[line].items }
        end,
        GetSpellBookItemType = function(index) local item = FindItem(index); return item.future and 2 or 1 end,
        GetSpellBookItemInfo = function(index) return FindItem(index) end,
    }
    function FindItem(index)
        for _, line in ipairs(book) do
            if index <= #line.items then return line.items[index] end
            index = index - #line.items
        end
    end
    local duration = { IsActive = function() return Typed("boolean", active) end }
    -- Spells the game watches for range (EnableSpellRangeCheck, which sends
    -- SPELL_RANGE_CHECK_UPDATE as one goes in or out of range): each ask
    -- counted and each let-go taken off. And spells with no range (NoRange).
    RangeChecks, NoRange = {}, {}
    -- Each spell's own text (C_Spell.GetSpellDescription below), as the game
    -- really answered it: Corruption and Curse of Agony on a warlock, Rend on
    -- a warrior, Immolate's two parts, and Serpent Sting. Corruption's twin
    -- at 1400172 is the same spell read again wearing a +46 spell damage
    -- robe, which is how it was proved the server scales these numbers.
    SpellText = {
        [172] = "Corrupts the target, causing 40 Shadow damage over 12 sec.",
        [1400172] = "Corrupts the target, causing 76 Shadow damage over 12 sec.",
        [980] = "Curses the target with agony, causing 72 Shadow damage over 24 sec. This damage is dealt slowly at first,"
            .. " and builds up as the Bane reaches its full duration.",
        [772] = "Wounds the target causing them to bleed for 15 damage over 9 sec.",
        [348] = "Burns the enemy for 11 Fire damage and then an additional 15 Fire damage over 15 sec.",
        [1978] = "Stings the target, causing 20 Nature damage over 15 sec.",
    }
    SpellNames = { [172] = "Corruption", [1400172] = "Corruption", [980] = "Curse of Agony", [772] = "Rend",
        [348] = "Immolate", [1978] = "Serpent Sting" }
    SpellTextReads, SpellTextRefuse, SpellTextSecret = 0, false, false
    _G.C_Spell = {
        EnableSpellRangeCheck = function(id, enable)
            assert(type(id) == "number" and type(enable) == "boolean", "a spell ID, and on or off")
            RangeChecks[id] = (RangeChecks[id] or 0) + (enable and 1 or -1)
            assert(RangeChecks[id] >= 0, "a range check let go that was never asked for")
        end,
        SpellHasRange = function(id) return NoRange[id] ~= true end,
        GetSpellCooldownDuration = function(id, ignoreGCD)
            assert(ignoreGCD == true, "global cooldown must be ignored")
            cooldownCalls[#cooldownCalls + 1] = id
            return duration
        end,
        IsSpellUsable = function(id)
            if usable[id] == nil then return true, false end
            return Typed("boolean", usable[id]), Typed("boolean", noMana[id])
        end,
        IsSpellInRange = function(id, unit) assert(unit == "target"); return Typed("boolean", range[id]) end,
        -- (A mage's procs with icons of their own, for the Cooldown pulse's proc rows.)
        GetSpellTexture = function(id) return ({ [12536] = 136170, [400589] = 236221, [400625] = 236218, [400670] = 236227 })[id] or 1 end,
        GetSpellName = function(id)
            return ({ [16870] = "Clearcasting", [16886] = "Nature's Grace", [1243] = "Power Word: Fortitude", [12536] = "Clearcasting",
                [400589] = "Missile Barrage", [400625] = "Heating Up", [400670] = "Fingers of Frost" })[id]
        end,
        GetSpellInfo = function() return nil end,
        -- A spell's own text, with the server's numbers already in it, which
        -- is where the DoTs part gets each spell's damage and time from
        -- (Dots.lua). The five here are what the game really answered on 26
        -- Nov 2026 (build 1.60.1.71139) on one warlock and one warrior, so
        -- the parse is tested against real game text; SpellText[id] sets
        -- another, SpellTextRefuse makes every ask error and
        -- SpellTextSecret hands the text back secret. Each ask counted
        -- (SpellTextReads).
        GetSpellDescription = function(id)
            assert(type(id) == "number", "a spell ID")
            SpellTextReads = SpellTextReads + 1
            if SpellTextRefuse then error("the game refused") end
            local text = SpellText[id]
            if text == nil then return nil end
            if SpellTextSecret then return SECRETS.string end
            return text
        end,
    }
    -- The same text through the tooltip reader, which also works on this
    -- client: name, mana cost, cast time, then the description (four lines,
    -- as measured). Nothing is ever written into the game's own tooltip.
    _G.C_TooltipInfo = {
        GetSpellByID = function(id)
            assert(type(id) == "number", "a spell ID")
            local text = SpellText[id]
            if text == nil then return nil end
            return { lines = { { leftText = SpellNames[id] or "A spell" }, { leftText = "25 Mana" },
                { leftText = "Instant" }, { leftText = text } } }
        end,
    }
    -- The combat log, shut to addons on this client: there are no tick, hit,
    -- miss or resist events, ever, so nothing may be built on one.
    _G.C_CombatLog = { IsCombatLogRestricted = function() return true end }
    _G.CombatLogGetCurrentEventInfo = nil
    _G.UnitClass = function() return "Druid", "DRUID" end
    -- Your form (Form: its ID, nil for none, or SECRET) and whether you're
    -- stealthed, as the game says; each ask counted (FormReads).
    Form, Stealthed, FormReads = nil, false, 0
    _G.GetShapeshiftFormID = function() FormReads = FormReads + 1; return Typed("number", Form) end
    _G.IsStealthed = function() return Typed("boolean", Stealthed) end
    -- A Skyborne, so Walk on Air (in the spellbook) is your own racial.
    _G.UnitRace = function(unit) assert(unit == "player"); return "Skyborne", "Skyborne", 96 end
    _G.UnitPower = function() return 0 end
    -- Health, secret on this client in a fight and out of one, with a real
    -- number behind it for the sums the game does itself (BarFill): the DoTs
    -- band hands your target's sealed max health to a status bar of ours and
    -- lets the game work the share out. A 30 health dummy, as the band was
    -- proved on in game.
    Health, HealthMax = { player = 100, target = 30 }, { player = 100, target = 30 }
    _G.UnitHealth = function(unit) return SecretNumber(Health[unit] or 0) end
    _G.UnitHealthMax = function(unit) return SecretNumber(HealthMax[unit] or 1) end
    _G.UnitCastingInfo = function() return nil end
    _G.UnitChannelInfo = function() return nil end
    _G.GetTime = function() return clock end
    _G.UnitGUID = function(unit) assert(unit == "player"); return character.guid end
    _G.UnitName = function(unit) assert(unit == "player"); return character.name end
    _G.GetRealmName = function() return character.realm end
    _G.CustomAuraContainerSlotDefaultOptions = {}
    _G.issecretvalue = IsSecret
    _G.UnitExists = function() return target end
    _G.UnitCanAttack = function(a, b) assert(a == "player" and b == "target"); return Typed("boolean", hostile) end
    -- Whether your target is dead (TargetDead: true, false or SECRET), which
    -- the DoTs band asks so it comes off a corpse rather than marking damage
    -- that will never land.
    TargetDead = false
    _G.UnitIsDeadOrGhost = function(unit)
        assert(type(unit) == "string" and unit ~= "", "a unit")
        return Typed("boolean", TargetDead)
    end
    -- Nameplates (NamePlates[unit] = the plate frame, as NamePlateGame makes
    -- one): the band marks your target's plate as well as the target frame
    -- when that is ticked.
    NamePlates = {}
    _G.C_NamePlate = { GetNamePlateForUnit = function(unit)
        assert(type(unit) == "string" and unit ~= "", "a unit")
        return NamePlates[unit]
    end }
    _G.UnitAffectingCombat = function() return false end
    _G.InCombatLockdown = function() return lockdown end
    -- Your buffs (PlayerAuras[id] = true, or SECRET for an answer the game
    -- keeps secret), as GetPlayerAuraBySpellID finds them, each ask counted
    -- (AuraReads). As on Forever: in a fight it finds none, even with them
    -- up, and C_Secrets says auras are secret then (AurasSecret: out of one).
    PlayerAuras, AuraReads, AurasSecret = {}, 0, false
    -- The game's own aura sounds (Play a sound, Sound on procs): each call
    -- kept as a line (AuraSoundCalls: "add <unit> <spellID> <file> <channel>
    -- <throttle>", "remove <id>", " fight" after either made in one), each
    -- add given the next ID; with AuraSoundRefuse (text) every add errors,
    -- kept as "refused <unit> <spellID>" so an add asked again shows.
    AuraSoundCalls, AuraSoundRefuse, NextAuraSound = {}, nil, 0
    -- Your target's debuffs, which the DoTs part reads out of a fight to put
    -- its own list straight (Dots.lua): TargetAuras in the order the game
    -- hands them over, each a table of the fields the probe proved open on 26
    -- Nov 2026 (spellId, name, duration, expirationTime, applications,
    -- sourceUnit; points is there and empty, so nothing may lean on it). A
    -- filter holding PLAYER leaves out anyone else's, as the game does. In a
    -- fight every index answers nil, on every unit, with any filter, exactly
    -- as it did in the probe. AuraIndexRefuse makes every ask error and
    -- AuraIndexSecret hands the fields back secret; each ask counted
    -- (AuraIndexReads).
    TargetAuras, AuraIndexReads, AuraIndexRefuse, AuraIndexSecret = {}, 0, false, false
    _G.C_UnitAuras = {
        GetPlayerAuraBySpellID = function(id)
            assert(type(id) == "number", "a spell ID")
            AuraReads = AuraReads + 1
            local aura = PlayerAuras[id]
            if lockdown or not aura then return nil end
            if rawequal(aura, SECRET) then return SECRET end
            return { spellId = id }
        end,
        GetAuraDataByIndex = function(unit, index, filter)
            assert(type(unit) == "string" and unit ~= "", "a unit")
            assert(type(index) == "number" and index > 0, "an index from one")
            assert(filter == nil or type(filter) == "string", "a filter, or none")
            AuraIndexReads = AuraIndexReads + 1
            if AuraIndexRefuse then error("the game refused") end
            if lockdown then return nil end
            local mine = type(filter) == "string" and filter:find("PLAYER", 1, true) ~= nil
            local kept = {}
            for _, aura in ipairs(unit == "target" and TargetAuras or {}) do
                if not mine or aura.sourceUnit == "player" then kept[#kept + 1] = aura end
            end
            local aura = kept[index]
            if not aura then return nil end
            if AuraIndexSecret then
                return { spellId = SECRETS.number, name = SECRETS.string, duration = SECRETS.number,
                    expirationTime = SECRETS.number, applications = SECRETS.number, sourceUnit = SECRETS.string,
                    points = {} }
            end
            return aura
        end,
        AddAuraSound = function(trigger, info)
            assert(trigger == 0, "the Added trigger")
            assert(type(info) == "table" and type(info.unitToken) == "string" and type(info.spellID) == "number", "a unit and a spell ID")
            local throttle = info.throttleSeconds
            assert(throttle == nil or (type(throttle) == "number" and throttle >= 0 and throttle <= 5), "a throttle of 0 to 5 seconds")
            if AuraSoundRefuse then
                AuraSoundCalls[#AuraSoundCalls + 1] = ("refused %s %d%s"):format(info.unitToken, info.spellID, lockdown and " fight" or "")
                error(AuraSoundRefuse)
            end
            AuraSoundCalls[#AuraSoundCalls + 1] = ("add %s %d %s %s %s%s"):format(info.unitToken, info.spellID,
                tostring(info.soundFileID or info.soundFileName), tostring(info.outputChannel), tostring(throttle), lockdown and " fight" or "")
            NextAuraSound = NextAuraSound + 1
            return NextAuraSound
        end,
        RemoveAuraSound = function(id)
            AuraSoundCalls[#AuraSoundCalls + 1] = "remove " .. tostring(id) .. (lockdown and " fight" or "")
        end,
    }
    -- And whether the game keeps one spell's aura secret (SpellAurasSecret[id]:
    -- true, false or SECRET; not there is false), as /ccm debug asks of procs.
    SpellAurasSecret = {}
    _G.C_Secrets = { ShouldAurasBeSecret = function() return lockdown or Typed("boolean", AurasSecret) end,
        ShouldSpellAuraBeSecret = function(id)
            assert(type(id) == "number", "a spell ID")
            if SpellAurasSecret[id] == nil then return false end
            return Typed("boolean", SpellAurasSecret[id])
        end }
    _G.C_CVar = {
        GetCVarBool = function(name) if name == "nameplateShowSelf" then return prdOn end return cvarOn end,
        GetCVar = function(name) return cvars[name] end,
        RegisterCVar = function(name, default) if cvars[name] == nil then cvars[name] = default end end,
        SetCVar = function(name, value)
            cvars[name] = value
            if name == "cooldownViewerEnabled" then cvarOn = value == "1" end
            if name == "nameplateShowSelf" then prdOn = value == "1" end
        end,
    }
    _G.wipe = function(t) for k in pairs(t) do t[k] = nil end return t end
    _G.print = function(msg) printed[#printed + 1] = msg end
    _G.CreateFrame = function(kind, name, parent, template)
        local f = New(kind, parent)
        if template then
            WidgetTemplate(template)
            S[f].template, S[f].frameTemplate = template, template
        end
        if kind == "AuraContainer" then
            assert(template == "CustomAuraContainerTemplate", "secure custom aura container")
            local slots = {}
            S[f].slots = slots
            containers[#containers + 1] = f
            -- How many icons a group makes at once (the game's ten), icons
            -- made, icons made mid-update, and calls into the addon's own
            -- files while the container updates (S[f].Update below).
            S[f].batch, S[f].made, S[f].late, S[f].addonCalls = 10, 0, 0, 0
            local function Guard() if lockdown then containerCallsInCombat = containerCallsInCombat + 1 end end
            -- Like the game: every icon made runs the slot's or group's look
            -- (initializeFrame) on it, the only addon code the container
            -- ever runs. One as a slot is added, a batch as a group is added,
            -- and another batch in the middle of an update when a group shows
            -- more auras than it has icons (Blizzard_AuraContainerFrameProviders.lua
            -- AcquireFrame). Each icon keeps what its look supplied.
            local function Make(options)
                for name, value in pairs(options) do
                    assert(name == "initializeFrame" or type(value) ~= "function", "addon code handed to the container: " .. name)
                end
                local button = New("Button", f)
                S[button].frameTemplate = "CustomAuraButtonTemplate"
                local supplied = {}
                S[button].supplied = supplied
                for _, method in ipairs({ "SetIcon", "SetDurationCooldown", "SetApplicationCount" }) do
                    rawset(button, method, function(_, object) supplied[method] = object end)
                end
                rawset(button, "SetDurationText", function(_, object, options)
                    supplied.SetDurationText, supplied.durationTextOptions = object, options
                end)
                -- Like the game: an animation group handed to the icon plays
                -- as the icon comes into sight and stops as it goes
                -- (ApplyVisibility, Blizzard_CustomAuraButton.lua). The group
                -- and each animation's target must sit inside the icon; after
                -- that the group takes no more animations and its targets'
                -- alpha is the game's (AuraContainerUtil.InitializeInboundAnimationGroup).
                -- ShownAnimations: "refuse", a game turning one down; "none",
                -- a game without them. (Kept apart from what its look supplied.)
                local shown = {}
                S[button].shownAnimations = shown
                if ShownAnimations == "none" then
                    rawset(button, "AddAuraShownAnimation", false)
                else
                    rawset(button, "AddAuraShownAnimation", function(_, group)
                        if ShownAnimations == "refuse" then error("bad object in function call") end
                        local function Inside(region)
                            local at = S[region] and S[region].parent
                            while at do
                                if at == button then return true end
                                at = S[at] and S[at].parent
                            end
                            return false
                        end
                        assert(S[group] and S[group].kind == "AnimationGroup" and Inside(group), "an animation group inside the icon")
                        local anims = { group:GetAnimations() }
                        for _, anim in ipairs(anims) do assert(Inside(anim:GetTarget()), "an animation on a region inside the icon") end
                        S[group].handed = true
                        for _, anim in ipairs(anims) do S[anim:GetTarget()].handed = true end
                        table.insert(shown, group)
                    end)
                end
                S[f].made = S[f].made + 1
                if S[f].updating then S[f].late = S[f].late + 1 end
                if options.initializeFrame then options.initializeFrame(button) end
                -- (Then out of sight until it shows an aura, as the game's
                -- first display update leaves it.)
                button:Hide()
                return button
            end
            -- Like the game: what makes it look at all your buffs afresh on
            -- its next frame (UpdateAllAuras, Blizzard_ManagedAuraContainer.lua
            -- and Blizzard_CustomAuraContainer.lua) is noted in S[f].full,
            -- which S[f].Refresh below plays out: a slot or group added,
            -- switched or told its filters, its unit, UpdateAllAuras, its
            -- own OnShow and OnHide, and what it hears while it can be
            -- seen: a full UNIT_AURA (none given, or isFullUpdate: a loading
            -- screen) and, once a slot or group is told buff IDs, UNIT_FLAGS
            -- and UNIT_FACTION for you (a fight starting or ending, a stun,
            -- your PvP flag: Blizzard_AuraContainerUtil.lua
            -- AppendCandidateFilterUnitEvents).
            local function Full() S[f].full = true end
            local function Named(filters)
                if type(filters) == "table" and (filters.includeSpellIDs or filters.excludeSpellIDs) then S[f].flags = true end
            end
            S[f].events.UNIT_AURA, S[f].events.UNIT_FLAGS, S[f].events.UNIT_FACTION = true, true, true
            S[f].scripts.OnEvent = function(_, event, unit, info)
                if not S[f].listening then return end
                if event == "UNIT_AURA" then
                    if unit == S[f].unit and (type(info) ~= "table" or info.isFullUpdate) then Full() end
                elseif unit == "player" and S[f].flags then
                    Full()
                end
            end
            rawset(f, "AddAuraSlot", function(_, key, filter, options)
                Guard()
                local button = Make(options)
                slots[key] = { filter = filter, button = button, enabled = true, supplied = S[button].supplied }
                Named(options.candidateFilters)
                Full()
                return button
            end)
            rawset(f, "SetAuraSlotEnabled", function(_, key, enabled)
                Guard(); assert(type(enabled) == "boolean"); slots[key].enabled = enabled; Full()
            end)
            rawset(f, "SetAuraSlotCandidateFilters", function(_, key, filters)
                Guard(); slots[key].filters = filters; Named(filters); Full()
            end)
            -- Like the game: its unit set, it signs up for that unit's aura
            -- events, but only while it can be seen (UpdateEventRegistrations
            -- asks IsVisible); its own OnShow and OnHide below sign it up
            -- again or off. listening: whether it hears its auras change.
            rawset(f, "SetUnit", function(_, unit)
                if S[f].unit ~= unit then
                    S[f].listening = f:IsVisible()
                    Full()
                end
                S[f].unit = unit
            end)
            rawset(f, "UpdateAllAuras", function()
                S[f].refreshes = (S[f].refreshes or 0) + 1
                Full()
            end)
            -- Like the game: the container's own OnShow and OnHide
            -- (AuraContainerPrivateMixin OnShow_Intrinsic and
            -- OnHide_Intrinsic, Blizzard_AuraContainer.lua) sign it up for
            -- its events again and mark it for a full update. They are
            -- Blizzard's code, but run inside whatever code showed or hid it
            -- or a frame it sits in (not through the secure doors its
            -- methods above go through). Each run is counted, and each one
            -- with the addon's own code on the stack is noted in
            -- ContainerRuns: "OnShow Bars.lua UpdateShown", the innermost
            -- addon function, with "in a fight" when it was.
            for _, which in ipairs({ "OnShow", "OnHide" }) do
                S[f].scripts[which] = function()
                    S[f].intrinsic = (S[f].intrinsic or 0) + 1
                    S[f].listening = f:IsVisible()
                    Full()
                    for level = 2, 60 do
                        local info = debug.getinfo(level, "Sn")
                        if not info then break end
                        local source = info.source or ""
                        if info.what ~= "C" and source:sub(1, 1) == "@" and not source:find("Tools", 1, true) then
                            ContainerRuns[#ContainerRuns + 1] = which .. " " .. source:sub(2) .. " " .. tostring(info.name)
                                .. (lockdown and " in a fight" or "")
                            break
                        end
                    end
                end
            end
            local groups = {}
            S[f].groups = groups
            rawset(f, "AddAuraGroup", function(_, key, filter, options)
                Guard()
                assert(not groups[key], "group added twice")
                local group = { filter = filter, enabled = true, frames = {}, pool = {}, active = {},
                    filters = options.candidateFilters, layout = options.layout, max = options.maxFrameCount or math.huge }
                function group.Batch()
                    for _ = 1, S[f].batch do
                        local button = Make(options)
                        group.frames[#group.frames + 1] = button
                        group.pool[#group.pool + 1] = button
                    end
                end
                group.Batch()
                group.button, group.supplied = group.frames[1], S[group.frames[1]].supplied
                groups[key] = group
                Named(options.candidateFilters)
                Full()
            end)
            rawset(f, "GetAuraGroupFrameCount", function(_, key) return groups[key] and #groups[key].frames or 0 end)
            rawset(f, "GetAuraGroupFrame", function(_, key, i) return groups[key] and groups[key].frames[i] end)
            rawset(f, "SetAuraGroupMaxFrameCount", function(_, key, count)
                Guard()
                assert(type(count) == "number" and count >= 0 and count == math.floor(count), "a whole number of icons")
                groups[key].max = count
            end)
            rawset(f, "SetAuraGroupEnabled", function(_, key, enabled)
                Guard(); assert(type(enabled) == "boolean"); groups[key].enabled = enabled; Full()
            end)
            rawset(f, "SetAuraGroupCandidateFilters", function(_, key, filters)
                Guard(); groups[key].filters = filters; Named(filters); Full()
            end)
            rawset(f, "SetAuraGroupLayout", function(_, key, layout) Guard(); groups[key].layout = layout end)
            rawset(f, "SetScale", function(_, scale) Guard(); S[f].scale = scale end)
            -- The container's own update, from its OnUpdate after UNIT_AURA or
            -- a refresh: each switched-on group takes the auras it matches, up
            -- to its most, with icons from its pool, making a batch more when
            -- the pool runs dry (Blizzard_AuraContainerGroups.lua
            -- RefreshAuraGroup). Auras are { id =, harmful =, mine =, other = }
            -- (other: another player's). The filter string's PLAYER keeps only
            -- yours; isFromPlayerOrPlayerPet means any player's. Any call into
            -- the addon's own files while it runs is counted.
            local function Matches(group, aura)
                local tokens = {}
                for token in tostring(group.filter):gmatch("[^|]+") do
                    assert(token == "HELPFUL" or token == "HARMFUL" or token == "PLAYER", "a filter the game knows: " .. token)
                    tokens[token] = true
                end
                if (tokens.HARMFUL == true) ~= (aura.harmful == true) then return false end
                if tokens.PLAYER and aura.mine ~= true then return false end
                local filters = group.filters or {}
                if filters.includeSpellIDs and not filters.includeSpellIDs[aura.id] then return false end
                local player = aura.mine == true or aura.other == true
                if filters.isFromPlayerOrPlayerPet ~= nil and filters.isFromPlayerOrPlayerPet ~= player then return false end
                return true
            end
            -- Each icon in use comes into sight and the rest go, as the
            -- game shows and hides them (running OnShow and OnHide inside
            -- them), playing an icon's shown animations as it comes into
            -- sight and stopping them as it goes.
            local function Sight(button, on)
                local was = S[button].shown
                button:SetShown(on)
                for _, group in ipairs(S[button].shownAnimations) do
                    if on and not was then group:Play() elseif not on then group:Stop() end
                end
            end
            -- (Your buffs as it last saw them are kept for Refresh.)
            S[f].Update = function(auras)
                S[f].auras = auras
                S[f].updating = true
                debug.sethook(function()
                    local info = debug.getinfo(2, "S")
                    local source = info and info.source or ""
                    if source:sub(1, 1) == "@" and not source:find("Tools", 1, true) then S[f].addonCalls = S[f].addonCalls + 1 end
                end, "c")
                local ok, err = pcall(function()
                    for _, group in pairs(groups) do
                        for _, button in ipairs(group.active) do group.pool[#group.pool + 1] = button end
                        group.active = {}
                        for _, aura in ipairs(group.enabled and auras or {}) do
                            if #group.active >= group.max then break end
                            if Matches(group, aura) then
                                if #group.pool == 0 then group.Batch() end
                                group.active[#group.active + 1] = table.remove(group.pool)
                            end
                        end
                        local using = {}
                        for _, button in ipairs(group.active) do using[button] = true end
                        for _, button in ipairs(group.frames) do Sight(button, using[button] == true) end
                    end
                    -- A slot's one icon shows the first aura it matches, if any.
                    for _, slot in pairs(slots) do
                        local lit = false
                        for _, aura in ipairs(slot.enabled and auras or {}) do
                            if Matches(slot, aura) then
                                lit = true
                                break
                            end
                        end
                        Sight(slot.button, lit)
                    end
                end)
                debug.sethook()
                S[f].updating = false
                assert(ok, err)
            end
            -- Its next frame after a full refresh was asked for (S[f].full),
            -- while it can be seen: every icon showing goes, its animations
            -- stopped, then each takes its aura again and comes into sight,
            -- playing them again (ResetFrameAssignments, then
            -- RefreshFrameAssignments). auras: your buffs now, else as it
            -- last saw them. True when it ran.
            S[f].Refresh = function(auras)
                if not (S[f].full and f:IsVisible()) then return false end
                S[f].full = false
                local now = auras or S[f].auras or {}
                S[f].Update({})
                S[f].Update(now)
                return true
            end
        end
        if template == "ActionButtonSpellAlertTemplate" then
            -- Blizzard's proc glow: its burst, then its loop (the burst's
            -- end starts it), each counting its plays. Hiding never stops the
            -- loop: Forever's template lists OnHide twice, and the second
            -- runs its OnShow method, which looks for a key nothing sets
            -- (ActionButtonSpellAlerts.xml and .lua).
            for _, key in ipairs({ "ProcStartAnim", "ProcLoop" }) do
                local anim = { plays = 0, playing = false }
                function anim:Play() self.plays = self.plays + 1; self.playing = true end
                function anim:Stop() self.playing = false end
                function anim:IsPlaying() return self.playing end
                rawset(f, key, anim)
            end
            S[f].scripts.OnHide = function(self)
                if self.animationPlaying then self.ProcLoop:Play() end
            end
        end
        frames[#frames + 1] = f
        S[f].name = name
        if name then _G[name] = f end
        return f
    end
    _G.UIParent = New("Frame")
    _G.EditModeManagerFrame = Blizzard(New("Frame"), "EditModeManagerFrame")
    S[EditModeManagerFrame].shown = false
    S[UIParent].cx, S[UIParent].cy = 500, 400
    _G.GameFontHighlight = { GetFont = function() return "font", 12, "" end }
    _G.CreateFont = function(name) local font = New("Font"); _G[name] = font; return font end
    _G.SlashCmdList = {}
    _G.StaticPopupDialogs = {}
    _G.Settings = nil
    -- Key bindings are never changed from addon code: the game then rebuilds
    -- your action bars and state inside the addon's code, which breaks on
    -- your hidden health (thousands of errors, 2026-10-06). A call is kept
    -- and stops the test.
    for _, name in ipairs({ "SetBinding", "SetBindingClick", "SetBindingItem", "SetBindingMacro", "SetBindingSpell",
        "SetOverrideBinding", "SetOverrideBindingClick", "SetOverrideBindingItem", "SetOverrideBindingMacro",
        "SetOverrideBindingSpell", "ClearOverrideBinding", "ClearOverrideBindings", "SaveBindings", "LoadBindings" }) do
        _G[name] = function() bindings[#bindings + 1] = name; error(name .. " called from addon code") end
    end
    -- The windows Escape closes: the game's own list, and its Escape hiding
    -- every one on it that's shown (UIParentPanelManager.lua CloseSpecialWindows).
    _G.UISpecialFrames = {}
    _G.CloseSpecialWindows = function()
        local found
        for _, name in pairs(UISpecialFrames) do
            local frame = _G[name]
            if frame and frame:IsShown() then
                frame:Hide()
                found = 1
            end
        end
        return found
    end
    -- The minimap: 140 across, its centre at 900, 700.
    _G.Minimap = New("Frame")
    S[Minimap].width, S[Minimap].height, S[Minimap].cx, S[Minimap].cy = 140, 140, 900, 700
    -- The tooltip keeps its lines.
    _G.GameTooltip = New("Frame")
    S[GameTooltip].shown = false
    rawset(GameTooltip, "SetOwner", function(self) S[self].lines = {} end)
    rawset(GameTooltip, "AddLine", function(self, text) table.insert(S[self].lines, text) end)
end

-- Blizzard's target frame, as measured in game on 26 Nov 2026 (build
-- 1.60.1.71139): the frame at level 500 strata LOW, its health bar at 502 and
-- 126 x 20, its portrait 58 wide. Plain widgets, not Blizzard(...), because
-- TargetFrame is not in Tools/WidgetMethods.lua's blizzard list and adding it
-- needs the generator and a wow-ui-source checkout; plain ones mean a call to
-- a method only its own Lua mixin has is noted as a miss, which is right,
-- since nothing of ours may touch it anyway. Called with nothing it takes the
-- frame back out of the game, for the tests that prove the band does nothing
-- without one. (A global: this file's main chunk is at Lua's 200 locals.)
function TargetFrameGame(there)
    _G.TargetFrame = nil
    if not there then return end
    local frame = New("Frame", UIParent)
    S[frame].width, S[frame].height = 232, 100
    local health = New("StatusBar", frame)
    S[health].width, S[health].height = 126, 20
    health:GetStatusBarTexture()
    -- Its health as the game has it: secret, with the number behind it for
    -- the game's own sums alone, so the fill texture's width is the share the
    -- game worked out and nothing of ours ever knows the number.
    health:SetMinMaxValues(0, UnitHealthMax("target"))
    health:SetValue(UnitHealth("target"))
    local portrait = New("Texture", frame)
    S[portrait].width, S[portrait].height = 58, 58
    -- The health bar's key as this client has it (the other shape the game
    -- has used is HealthBarsContainer.healthBar, which the band's own search
    -- tries first). Its level and strata are not set here: the mock game
    -- answers every GetFrameLevel with 1, and what matters is the level the
    -- band sets on its own clipping frame.
    rawset(frame, "healthbar", health)
    rawset(frame, "portrait", portrait)
    _G.TargetFrame = frame
    return frame, health, portrait
end

-- A nameplate of your target's, in the shape Blizzard's nameplates have: the
-- plate frame with a UnitFrame on it and a health bar in that. Its sizes are
-- not a measurement, unlike the target frame's above: nothing of the DoTs
-- band works a number out from them, since the band takes the health bar's
-- own width whatever it is. Plain widgets again, for the same reason. Called
-- with nothing it takes the plate away, which is what the game does as a
-- plate goes out of sight and is kept for the next unit.
-- (A global: this file's main chunk is at Lua's 200 locals.)
function NamePlateGame(there)
    NamePlates.target = nil
    if not there then return end
    local plate = New("Frame", UIParent)
    S[plate].width, S[plate].height = 110, 45
    local unitFrame = New("Frame", plate)
    local health = New("StatusBar", unitFrame)
    S[health].width, S[health].height = 110, 10
    health:GetStatusBarTexture()
    health:SetMinMaxValues(0, UnitHealthMax("target"))
    health:SetValue(UnitHealth("target"))
    rawset(unitFrame, "healthBar", health)
    rawset(plate, "UnitFrame", unitFrame)
    NamePlates.target = plate
    return plate, health, unitFrame
end

local function Load(saved, beforeLogin)
    local ns = {}
    _G.ForeverEnhancedCooldownManagerDB = saved
    for _, file in ipairs({ "Core.lua", "Style.lua", "Skin.lua", "Resource.lua", "CastBar.lua", "Ranks.lua", "Forms.lua", "Spells.lua", "Keybinds.lua", "Buffs.lua", "IconAuras.lua", "Bars.lua",
        "Layout.lua", "Theme.lua", "BarPage.lua", "LayoutPage.lua", "CastBarPage.lua", "ComboSetUp.lua", "ProfileMenu.lua", "Window.lua", "Tour.lua",
        "MinimapButton.lua", "Notes.lua", "Debug.lua" }) do
        assert(loadfile(file))("ForeverEnhancedCooldownManager", ns)
    end
    -- Both pages are held out of the window for the release going out now,
    -- so the checks turn them on the way the addon itself will.
    ns.FILL_PAGE_READY, ns.DOTS_PAGE_READY = true, true
    Fire("ADDON_LOADED", "ForeverEnhancedCooldownManager")
    if not beforeLogin then
        Fire("PLAYER_LOGIN")
        Fire("PLAYER_ENTERING_WORLD")
    end
    return ns
end

-- Totems: the game around it -------------------------------------------------------------
-- Stand-ins for what the window's other pages need (as Tools/TestPulse.lua),
-- the game's totem slots (secret in a fight), your class, the clock and its
-- timers, and Cooldown frames that may answer a Clear with their done script.

local blizzardCalling = false
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

-- Like the game: clearing a cooldown is counted, as well as noted, and the
-- game may answer it with the done script. A duration object handed over is
-- noted.
function Proto:Clear()
    local s = S[self]
    s.clears = (s.clears or 0) + 1
    s.last.Clear = table.pack()
    if s.scripts.OnCooldownDone then s.scripts.OnCooldownDone(self) end
end
function Proto:SetCooldownFromDurationObject(duration)
    S[self].last.SetCooldownFromDurationObject = table.pack(duration)
end

-- The whole Totems game, set up after the mock game's Environment(). Globals
-- (the main chunk is near Lua's 200 locals): Class (your class file name, or
-- SECRET), TOTEM[slot] ({ name, id, icon, active }) for each totem down,
-- TotemsSecret (every totem answer secret, as in a fight), TotemReads (each
-- GetTotemInfo asked), TotemRefuse (GetTotemDuration errors), Queue (the
-- timers, each with the time it's due).
local function TotemGame()
    Class, TOTEM, TotemsSecret, TotemReads, TotemRefuse, Queue = "SHAMAN", {}, false, 0, false, {}
    -- (A secret class goes to Totems.lua alone: the rest of the addon reads it at other times.)
    local function Asker()
        for level = 2, 12 do
            local info = debug.getinfo(level, "S")
            if not info then return "" end
            if (info.source or ""):sub(1, 1) == "@" and not info.source:find("Tools", 1, true) then return info.source end
        end
        return ""
    end
    _G.UnitClass = function(unit)
        assert(unit == "player")
        if rawequal(Class, SECRET) then
            if Asker():find("Totems.lua", 1, true) then return SECRETS.string, SECRETS.string, SECRETS.number end
            return "Shaman", "SHAMAN", 7
        end
        return Class:sub(1, 1) .. Class:sub(2):lower(), Class, 7
    end
    _G.GetTotemInfo = function(slot)
        assert(type(slot) == "number" and slot >= 1 and slot <= 4, "a plain slot, 1 to 4")
        TotemReads = TotemReads + 1
        if TotemsSecret then
            local b, s, n = SECRETS.boolean, SECRETS.string, SECRETS.number
            return b, s, n, n, n, n, n
        end
        local t = TOTEM[slot]
        if not t then return false, "", 0, 0, nil, 1, 0 end
        return true, t.name, 90, 120, t.icon, 1, t.id
    end
    _G.GetTotemDuration = function(slot)
        assert(type(slot) == "number" and slot >= 1 and slot <= 4, "a plain slot, 1 to 4")
        if TotemRefuse then error("refused") end
        local t = TOTEM[slot]
        local active = t ~= nil and t.active ~= false
        return { slot = slot,
            IsActive = function() if TotemsSecret then return SECRETS.boolean end return active end,
            HasSecretValues = function() return TotemsSecret end }
    end
    C_Secrets.ShouldTotemSlotBeSecret = function(slot) assert(type(slot) == "number"); return TotemsSecret end
    -- Where you are (UnitPosition: north, west, height, map): Where = { x, y, map }, SECRET (kept from
    -- you), or nil (a dungeon). WhereAsks counts the asks.
    Where, WhereAsks = nil, 0
    _G.UnitPosition = function(unit)
        assert(unit == "player")
        WhereAsks = WhereAsks + 1
        if rawequal(Where, SECRET) then
            local n = SECRETS.number
            return n, n, n, n
        end
        if not Where then return nil end
        return Where.y, Where.x, 0, Where.map
    end
    -- Each spell's art: its ID and seven million (Searing's 7003599).
    C_Spell.GetSpellTexture = function(id) return 7000000 + id end
    C_Spell.GetSpellCooldown = function() return { isEnabled = true, isOnGCD = false, startTime = 0, duration = 0, modRate = 1 } end
    _G.PlaySound = function() end
    _G.TimerTracker = Blizzard(New("Frame"), "TimerTracker")
    rawset(TimerTracker, "timerList", {})
    _G.TimerTracker_StartTimerOfType = function() assert(blizzardCalling, "the addon ran Blizzard's countdown") end
    _G.RaidWarningFrame = Blizzard(New("Frame"), "RaidWarningFrame")
    rawset(RaidWarningFrame, "fontStringPool", { EnumerateActive = function() return pairs({}) end })
    rawset(RaidWarningFrame, "AddMessage", function() assert(blizzardCalling, "the addon added a raid warning") end)
    for i = 1, 5 do
        local bar = New("StatusBar")
        for _, key in ipairs({ "TextBorder", "Background", "Border", "Spark", "Icon", "Flash", "BorderShield" }) do
            rawset(bar, key, New("Texture", bar))
        end
        rawset(bar, "Text", New("FontString", bar))
        rawset(bar, "UpdateBarFillTexture", function() assert(blizzardCalling, "the addon ran a boss bar's fill") end)
        _G["Boss" .. i .. "TargetFrameSpellBar"] = bar
    end
    _G.C_AddOns, _G.EraUI, _G.ForeverPulseLink = nil, nil, nil
    S[UIParent].width, S[UIParent].height = 1366, 768
    _G.C_Timer = { After = function(delay, fn) Queue[#Queue + 1] = { at = clock + delay, fn = fn } end }
end

-- Every file in the order the .toc loads them (Tools/TestRules.mjs checks the .toc).
local FILES = { "Core.lua", "SquirtVersions.lua", "Style.lua", "Skin.lua", "Resource.lua", "CastBar.lua", "RaidTimers.lua", "Ranks.lua",
    "Forms.lua", "Spells.lua", "Keybinds.lua", "Buffs.lua", "IconAuras.lua", "Bars.lua", "Pulse.lua", "Totems.lua", "Layout.lua",
    "Theme.lua", "BarPage.lua", "LayoutPage.lua", "CastBarPage.lua", "RaidTimersPage.lua", "PulsePage.lua", "TotemsPage.lua",
    "ProfileShare.lua", "ProfileMenu.lua", "Window.lua", "Tour.lua", "MinimapButton.lua", "Notes.lua", "Debug.lua" }

-- A fresh game and the addon started in it: saved (the settings file, or
-- nil for a first login) and class (SHAMAN unless given).
local function Fresh(saved, class, setup)
    Environment()
    TotemGame()
    if class then Class = class end
    if setup then setup() end
    local ns = {}
    _G.ForeverEnhancedCooldownManagerDB = saved
    for _, file in ipairs(FILES) do assert(loadfile(file))("ForeverEnhancedCooldownManager", ns) end
    Fire("ADDON_LOADED", "ForeverEnhancedCooldownManager")
    Fire("PLAYER_LOGIN")
    Fire("PLAYER_ENTERING_WORLD")
    return ns, ns.Totems
end

-- Time passing: each timer due runs at its time, in order, then the clock
-- stands seconds on.
local function Pass(seconds)
    local stop = clock + (seconds or 0)
    while true do
        local first
        for i, t in ipairs(Queue) do
            if t.at <= stop and (not first or t.at < Queue[first].at) then first = i end
        end
        if not first then break end
        local t = table.remove(Queue, first)
        if t.at > clock then clock = t.at end
        t.fn()
    end
    clock = stop
end

-- A totem down (or gone, name nil) in a slot, as the game tells it: its
-- slot changed, then the next frame.
local function Drop(slot, name, id, icon)
    TOTEM[slot] = name and { name = name, id = id, icon = icon or (7000000 + id) } or nil
    Fire("PLAYER_TOTEM_UPDATE", slot)
    Pass(0)
end

-- Your cast of a spell, as the game tells it.
local function Cast(id)
    Fire("UNIT_SPELLCAST_SUCCEEDED", "player", "Cast-3-0000", id)
end

-- A number as text, whole ones without a point (the layout's sums can be 40.0).
local function N(v)
    if type(v) == "number" and v == math.floor(v) then return string.format("%d", v) end
    return tostring(v)
end

-- Each element's spot, by its letter, from the spots on the bar.
local function Spots(M)
    local found = {}
    for _, kid in ipairs(S[M.bar].kids or {}) do
        if rawget(kid, "letter") then found[kid.letter] = kid end
    end
    return found
end

-- Where a frame is: its first point's x and y.
local function At(frame)
    local p = S[frame].points[1]
    return p and (p[1] .. " " .. N(p[4]) .. " " .. N(p[5])) or "none"
end

-- The spots in order across, by their x on the bar (first row first).
local function Across(M)
    local list = {}
    for letter, spot in pairs(Spots(M)) do list[#list + 1] = { letter = letter, x = S[spot].points[1][4], y = S[spot].points[1][5] } end
    table.sort(list, function(a, b) if a.y ~= b.y then return a.y > b.y end return a.x < b.x end)
    local letters = {}
    for _, item in ipairs(list) do letters[#letters + 1] = item.letter end
    return table.concat(letters)
end

-- Each layer's alpha: placed / empty / red, by letter, in Blizzard's order.
local function Layers(M)
    local out = {}
    for _, letter in ipairs({ "e", "f", "w", "a" }) do
        local spot = Spots(M)[letter]
        out[#out + 1] = letter .. " " .. tostring(S[spot.placed].alpha) .. "/" .. tostring(S[spot.empty].alpha) .. "/"
            .. tostring(S[spot.warn].alpha)
    end
    return table.concat(out, ", ")
end

-- The Totems bar's aura containers: each one's spot's letter, by letter.
local function Holders(M)
    local found = {}
    for letter, spot in pairs(Spots(M)) do
        for _, c in ipairs(containers) do
            if S[c].parent == spot.warn then found[letter] = c end
        end
    end
    return found
end

local function Sorted(set)
    local list = {}
    for id in pairs(set or {}) do list[#list + 1] = id end
    table.sort(list)
    return table.concat(list, ",")
end

local function Has(texts, wanted)
    for _, text in ipairs(texts or {}) do
        if tostring(text):find(wanted, 1, true) then return true end
    end
    return false
end

-- How things fit (a copy of Tools/TestHelp.lua's own Fit, which isn't in
-- the shared mock game). Text in the game runs about seven units a letter in
-- the window's usual font: counted at 7.5 here, 6.5 in the small font, and
-- more for capitals, to be sure. Places are worked out from each frame's
-- anchors as the game would: left, top, right and bottom, y down from the
-- window's top left. (A global: the main chunk is near Lua's 200 locals.)
Fit = {}
function Fit.Wide(text, font)
    text = tostring(text or ""):gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""):gsub("|T.-|t", "XX")
    local small = type(font) == "string" and font:find("Small") ~= nil
    local capitals = text:find("%a") ~= nil and text == text:upper()
    local each = small and (capitals and 7.5 or 6.5) or (capitals and 9 or 7.5)
    return #text * each
end
function Fit.Rect(obj, depth)
    depth = depth or 0
    assert(depth < 40, "anchors that go round in a circle")
    if obj == FECMFrame then return 0, 0, 820, 560 end
    local s = S[obj]
    if obj == UIParent or not s then return -10000, -10000, 10000, 10000 end
    local width, height, wide = s.width, s.height, nil
    if s.kind == "FontString" then
        wide = Fit.Wide(s.text, Last(obj, "SetFontObject") or s.template)
        if width == 0 then
            width = wide
        elseif wide > width and height == 0 then
            height = math.ceil(wide / width) * 12
        end
        if height == 0 then height = 12 end
    end
    if rawget(obj, "box") and rawget(obj, "text") then width, height = 18 + Fit.Wide(S[obj.text].text, S[obj.text].template), 16 end
    if #s.points == 0 then return Fit.Rect(s.parent, depth + 1) end
    local left, top, right, bottom, cx, cy
    for _, p in ipairs(s.points) do
        local point, relative, relativePoint, x, y = p[1], s.parent, p[1], p[2] or 0, p[3] or 0
        if type(p[2]) == "table" then point, relative, relativePoint, x, y = p[1], p[2], p[3] or p[1], p[4] or 0, p[5] or 0 end
        local rl, rt, rr, rb = Fit.Rect(relative, depth + 1)
        local ax = relativePoint:find("LEFT") and rl or relativePoint:find("RIGHT") and rr or (rl + rr) / 2
        local ay = relativePoint:find("TOP") and rt or relativePoint:find("BOTTOM") and rb or (rt + rb) / 2
        ax, ay = ax + x, ay - y
        if point:find("LEFT") then left = ax elseif point:find("RIGHT") then right = ax else cx = ax end
        if point:find("TOP") then top = ay elseif point:find("BOTTOM") then bottom = ay else cy = ay end
    end
    if not left and not right then left = cx - width / 2 end
    left = left or right - width
    right = right or left + width
    if not top and not bottom then top = cy - height / 2 end
    top = top or bottom - height
    bottom = bottom or top + height
    if wide and s.width > 0 and wide < right - left then
        local justify = Last(obj, "SetJustifyH") or "LEFT"
        if justify == "RIGHT" then
            left = right - wide
        elseif justify == "CENTER" then
            left, right = (left + right - wide) / 2, (left + right + wide) / 2
        else
            right = left + wide
        end
    end
    return left, top, right, bottom
end
function Fit.Inside(obj, root)
    local at = obj
    while at do
        if at == root then return true end
        at = S[at] and S[at].parent
    end
    return false
end
function Fit.Name(obj)
    local s = S[obj]
    if s.kind == "FontString" then return '"' .. tostring(s.text) .. '"' end
    if rawget(obj, "box") and rawget(obj, "text") then return "tick " .. tostring(S[obj.text].text) end
    if rawget(obj, "buttons") then return "choice " .. tostring(S[obj.buttons[1].label].text) .. "..." end
    if rawget(obj, "label") then return s.kind .. " " .. tostring(S[obj.label].text) end
    return s.kind
end
-- What can run into something else, where each shows: text (not a
-- button's or tick's own), ticks with their labels, buttons, choices and
-- slider tracks, the thumb reaching 5 past each end. The preview's own
-- spots are drawn smaller (scaled) and take no mouse: left out.
function Fit.Pieces(root, skip)
    local list = {}
    for _, obj in ipairs(objects) do
        local s = S[obj]
        local parent = s.parent
        if obj ~= root and Fit.Inside(obj, root) and not (skip and Fit.Inside(obj, skip)) and obj:IsVisible() then
            local piece
            if s.kind == "FontString" then
                local own = parent and S[parent] and ((S[parent].kind == "Button" and rawget(parent, "label") == obj)
                    or (rawget(parent, "box") ~= nil and rawget(parent, "text") == obj))
                local inChoice = parent and S[parent] and S[parent].parent and rawget(S[parent].parent, "buttons") ~= nil
                piece = (s.text or "") ~= "" and not own and not inChoice
            elseif rawget(obj, "box") and rawget(obj, "text") then
                piece = true
            elseif rawget(obj, "buttons") and rawget(obj, "SetSelected") then
                piece = true
            elseif s.kind == "Button" and rawget(obj, "label") then
                piece = not (parent and rawget(parent, "buttons"))
            elseif parent and rawget(parent, "track") == obj then
                piece = "track"
            end
            if piece then
                local l, t, r, b = Fit.Rect(obj)
                if piece == "track" then l, r = l - 5, r + 5 end
                list[#list + 1] = { l, t, r, b, obj = obj, name = Fit.Name(obj) }
            end
        end
    end
    return list
end
function Fit.Below(a, b)
    local at = S[b].parent
    while at do
        if at == a then return true end
        at = S[at] and S[at].parent
    end
    return false
end
-- Every piece on a page inside it and none on another: "" when all fit.
-- With boxes ({ frame, name } each), a piece in a box is inside it too.
function Fit.Problems(root, boxes, skip)
    local list, found, named = Fit.Pieces(root, skip), {}, {}
    for _, box in ipairs(boxes or {}) do
        if box[1]:IsVisible() then
            named[box[1]] = box[2]
            local l, t, r, b = Fit.Rect(box[1])
            list[#list + 1] = { l, t, r, b, obj = box[1], name = box[2] }
        end
    end
    local rl, rt, rr, rb = Fit.Rect(root)
    for i, a in ipairs(list) do
        if a[1] < rl or a[3] > rr or a[2] < rt or a[4] > rb then found[#found + 1] = a.name .. " off the page" end
        local box = S[a.obj].parent
        while box and box ~= root and S[box] and not named[box] do box = S[box].parent end
        if box and named[box] then
            local l, t, r, b = Fit.Rect(box)
            if a[1] < l or a[3] > r or a[2] < t or a[4] > b then
                found[#found + 1] = ("%s out of %s (%.1f, %.1f to %.1f, %.1f in %.1f, %.1f to %.1f, %.1f)"):format(a.name, named[box],
                    a[1], a[2], a[3], a[4], l, t, r, b)
            end
        end
        for j = i + 1, #list do
            local b = list[j]
            if a[1] < b[3] and b[1] < a[3] and a[2] < b[4] and b[2] < a[4] and not Fit.Below(a.obj, b.obj) and not Fit.Below(b.obj, a.obj) then
                found[#found + 1] = a.name .. " on " .. b.name
            end
        end
    end
    return table.concat(found, "; ")
end
-- A control's note, as the footer shows it.
function Fit.Note(control)
    local hint = control.hint
    if type(hint) == "function" then hint = hint(control) end
    return hint
end

(function()
    local T = {} -- (the module of each game, as it's started)

    -- 1. Not a shaman: nothing made or heard, whatever is saved --------------------------
    do
        local ns, M = Fresh({ totemBar = true }, "DRUID")
        Equal(tostring(M:ForMe()) .. " " .. tostring(M.bar) .. " " .. tostring(M.driver), "false nil nil",
            "a druid: not for you, no bar and no frame made")
        M:Apply()
        M:UpdateShown()
        M:ShowMover()
        M:Restyle()
        Equal(tostring(M.bar), "nil", "turned on (saved from a shaman): still nothing")
        ns.ShowWindow()
        Equal(tostring(FECMFrame.pages.totems) .. " " .. tostring(FECMFrame.nav.totems), "nil nil", "no Totems page or item")
        Equal(ns.DebugReport():find("Totems: shaman false", 1, true) ~= nil, true, "the debug report says it isn't for you")

        local _, M2 = Fresh({ totemBar = true }, SECRET)
        Equal(tostring(M2:ForMe()) .. " " .. tostring(M2.bar) .. " " .. tostring(next(S[M2.driver].events)), "false nil nil",
            "a class the game keeps secret, none kept: not for you, nothing made, nothing heard after login")

        -- Secret as the addon starts, a shaman by login: it starts then.
        -- (A frame made before the addon's hears login first: your class plain from then.)
        local _, M3 = Fresh({ totemBar = true }, SECRET, function()
            local first = CreateFrame("Frame")
            first:RegisterEvent("PLAYER_LOGIN")
            first:SetScript("OnEvent", function() Class = "SHAMAN" end)
        end)
        Equal(tostring(M3:ForMe()) .. " " .. tostring(M3.bar ~= nil) .. " " .. tostring(S[M3.driver].events.PLAYER_LOGIN),
            "true true nil", "your class read again at login: it starts then")
    end

    -- 2. Settings -----------------------------------------------------------------------------
    do
        local ns, M = Fresh(nil)
        T.M, T.ns = M, ns
        local keys = { "totemBar", "totemSize", "totemHeight", "totemSpacing", "totemPerRow", "totemGrow", "totemWrap",
            "totemOutOfCombat", "totemTimer", "totemNames", "totemRange", "totemOrder", "totemX", "totemY" }
        local values = {}
        for _, key in ipairs(keys) do values[#values + 1] = key .. "=" .. tostring(ns.Get(key)) end
        Equal(table.concat(values, " "), "totemBar=false totemSize=36 totemHeight=100 totemSpacing=4 totemPerRow=4 totemGrow=centre"
            .. " totemWrap=down totemOutOfCombat=show totemTimer=true totemNames=false totemRange=false totemOrder=efwa"
            .. " totemX=-300 totemY=-175", "every default: off, a bar's size, one row, Earth Fire Water Air, left of your bars")
        local refused = {}
        for _, case in ipairs({ { "totemSize", 18 }, { "totemSize", 66 }, { "totemPerRow", 0 }, { "totemPerRow", 5 },
            { "totemHeight", 45 }, { "totemHeight", 155 }, { "totemOrder", "eewa" }, { "totemOrder", "efw" },
            { "totemGrow", "up" }, { "totemWrap", "left" }, { "totemOutOfCombat", "dim" }, { "totemX", 4001 }, { "totemBar", "yes" } }) do
            if not ns.Valid(case[1], case[2]) then refused[#refused + 1] = case[1] .. " " .. tostring(case[2]) end
        end
        Equal(#refused, 13, "out of range, broken orders and unknown choices refused: " .. table.concat(refused, ", "))
        local orders = 0
        local letters = { "e", "f", "w", "a" }
        for _, a in ipairs(letters) do for _, b in ipairs(letters) do for _, c in ipairs(letters) do for _, d in ipairs(letters) do
            local order = a .. b .. c .. d
            local distinct = a ~= b and a ~= c and a ~= d and b ~= c and b ~= d and c ~= d
            Equal(ns.Valid("totemOrder", order), distinct, "order " .. order)
            if distinct then orders = orders + 1 end
        end end end end
        Equal(orders, 24, "all 24 orders taken")
        Equal(ns.Valid("totemSize", 64) and ns.Valid("totemPerRow", 2) and ns.Valid("totemHeight", 150) and ns.Valid("totemX", -4000),
            true, "the limits themselves taken")

        -- 3. A shaman, off: nothing made or heard.
        Equal(tostring(M:ForMe()) .. " " .. tostring(M.bar) .. " " .. tostring(M.driver and next(S[M.driver].events)), "true nil nil",
            "a shaman with it off: no bar, nothing heard")
    end

    -- 4. On, every element empty, out of a fight -------------------------------------------
    local ns, M = T.ns, T.M
    do
        ns.Set("totemBar", true)
        M:Apply()
        local bar = M.bar
        Equal(At(bar), "CENTER -300 -175", "made with its middle 300 left and 175 down from the screen's")
        Equal(Last(bar, "SetFrameStrata") .. " " .. tostring(Last(bar, "EnableMouse")) .. " " .. tostring(Last(bar, "SetClampedToScreen")),
            "MEDIUM false true", "strata MEDIUM, no mouse, kept on the screen")
        Equal(N(S[bar].width) .. "x" .. N(S[bar].height) .. " " .. Across(M), "156x36 efwa", "four spots in one row: Earth, Fire, Water, Air")
        local spots, sizes, mice, arts = Spots(M), {}, {}, {}
        for _, letter in ipairs({ "e", "f", "w", "a" }) do
            local spot = spots[letter]
            sizes[#sizes + 1] = N(S[spot].width) .. "x" .. S[spot].height
            for _, frame in ipairs({ spot, spot.placed, spot.empty, spot.warn, spot.time }) do
                if Last(frame, "EnableMouse") ~= false then mice[#mice + 1] = letter end
            end
            arts[#arts + 1] = tostring(S[spot.emptyArt].texture) .. " " .. tostring(S[spot.emptyArt].desaturated) .. " "
                .. tostring(S[spot.emptyArt].alpha)
        end
        Equal(table.concat(sizes, " "), "36x36 36x36 36x36 36x36", "each 36 across")
        Equal(#mice, 0, "no spot or layer takes the mouse")
        Equal(table.concat(arts, ", "), "7008071 true 0.45, 7003599 true 0.45, 7005675 true 0.45, 7008512 true 0.45",
            "each element's own totem art, greyed: Stoneskin, Searing, Mana Spring, Windfury")
        Equal(Layers(M), "e 0/1/0, f 0/1/0, w 0/1/0, a 0/1/0", "every element empty: greyed, nothing placed, no red")
        Equal(tostring(S[bar].shown) .. " " .. tostring(S[bar].alpha), "true 1", "shown, in full (Show out of combat)")
        Equal(M:Down(), 0, "none down")
        local events = {}
        for event in pairs(S[M.driver].events) do events[#events + 1] = event end
        table.sort(events)
        Equal(table.concat(events, " "), "PLAYER_ENTERING_WORLD PLAYER_REGEN_DISABLED PLAYER_REGEN_ENABLED PLAYER_TARGET_CHANGED"
            .. " PLAYER_TOTEM_UPDATE UNIT_SPELLCAST_SUCCEEDED", "its events heard while it's on")
    end

    -- 5. A totem down, out of a fight ------------------------------------------------------
    local spots = Spots(M)
    do
        ns.Set("totemNames", true)
        M:Apply()
        Drop(2, "Strength of Earth Totem V", 25361, 136023)
        local earth = spots.e
        Equal(Layers(M), "e 1/0/0, f 0/1/0, w 0/1/0, a 0/1/0", "Earth placed over its greyed art")
        Equal(S[earth.art].texture, 136023, "the totem's own icon, from the game")
        Equal(type(Last(earth.cooldown, "SetCooldownFromDurationObject")), "table", "its time: the game's duration object, handed on")
        Equal(S[earth.label].text .. " | " .. tostring(S[earth.label].shown) .. " | " .. S[spots.f.emptyLabel].text,
            "Strength of Earth | true | Fire", "names on: the totem's short name, the element's where none is down")
        Equal(M:Down(), 1, "one down")
    end

    -- 6. Its time runs out --------------------------------------------------------------------
    do
        TOTEM[2].active = false
        Pass(30)
        local reads = TotemReads
        S[spots.e.cooldown].scripts.OnCooldownDone(spots.e.cooldown)
        Pass(0)
        Equal(Layers(M), "e 0/1/0, f 0/1/0, w 0/1/0, a 0/1/0", "done: read again, greyed again (no event comes)")
        Equal(TotemReads - reads, 1, "read once")
        -- The game answering a read with its done script: never a loop.
        TOTEM[2] = nil
        TotemRefuse = true
        reads = TotemReads
        Pass(30)
        S[spots.e.cooldown].scripts.OnCooldownDone(spots.e.cooldown)
        Pass(0)
        Pass(0)
        Equal(tostring(S[spots.e.cooldown].clears) .. " " .. tostring(TotemReads - reads) .. " " .. #Queue, "1 1 0",
            "its time cleared once, and the done that answers the clear reads nothing more")
        S[spots.e.cooldown].scripts.OnCooldownDone(spots.e.cooldown)
        Pass(0)
        Equal(TotemReads - reads, 1, "a done straight after a read is that read's answer: nothing more")
        TotemRefuse = false
    end

    -- 7. A totem replaced -----------------------------------------------------------------------
    do
        Drop(2, "Stoneskin Totem", 8071)
        Cast(8155)
        Drop(2, "Stoneskin Totem III", 8155, 136098)
        Equal(S[spots.e.art].texture .. " " .. S[spots.e.label].text, "136098 Stoneskin", "Stoneskin's art and name")
        Drop(2, "Strength of Earth Totem", 8075)
        Equal(S[spots.e.art].texture .. " " .. S[spots.e.label].text, "7008075 Strength of Earth", "replaced: its art and name")
        Drop(2, nil)
        Equal(Layers(M), "e 0/1/0, f 0/1/0, w 0/1/0, a 0/1/0", "taken down: greyed")
    end

    -- 8. In a fight, every totem answer secret ----------------------------------------------------
    do
        lockdown, TotemsSecret = true, true
        Fire("PLAYER_REGEN_DISABLED")
        Cast(10614)
        TOTEM[4] = { name = "Windfury Totem III", id = 10614, icon = 136114 }
        Fire("PLAYER_TOTEM_UPDATE", 4)
        Pass(0)
        local air = spots.a
        Equal(S[air.placed].alphaFrom, SECRET, "placed: the game's secret answer, handed on")
        Equal(S[air.placed].alphaIf .. " | " .. S[air.empty].alphaIf, "1 0 | 0 1", "placed over empty, by the game")
        Equal(S[air.art].texture, SECRET, "its icon: the game's secret one, handed straight to the art")
        Equal(S[air.label].text, "Windfury", "its name from your cast")
        Equal(M:Down(), nil, "how many are down: the game won't say in a fight")
        local report = ns.DebugReport()
        Equal(report:match("Totems: [^\n]*now secret") ~= nil, true, "the debug report says secret")
        Equal(S[M.bar].alpha, 1, "in full in a fight")
        lockdown, TotemsSecret = false, false
        Fire("PLAYER_REGEN_ENABLED")
        Equal(S[air.label].text .. " " .. S[air.placed].alpha, "Windfury 1", "after the fight: read again, seen now")
        Drop(4, nil)
    end

    -- 10. Buff lost and regained: the range warning -------------------------------------------
    local holders
    do
        Equal(M:CanRange(), true, "the game can show it")
        Equal(#containers, 0, "no aura container until Red when out of range is ticked")
        ns.Set("totemRange", true)
        M:Apply()
        holders = Holders(M)
        local count, told = 0, {}
        for _, letter in ipairs({ "e", "f", "w", "a" }) do
            local c = holders[letter]
            if c then
                count = count + 1
                local slot = S[c].slots.lit
                local ids = {}
                for name, entry in pairs(M.TOTEMS) do
                    if entry[1] == letter then for _, id in ipairs(entry[2] or {}) do ids[id] = true end end
                end
                told[#told + 1] = letter .. " " .. tostring(slot.filter) .. " " .. tostring(slot.enabled) .. " "
                    .. tostring(slot.filters.isFromPlayerOrPlayerPet) .. " " .. tostring(Sorted(slot.filters.includeSpellIDs) == Sorted(ids))
                    .. " " .. tostring(S[c].unit)
            end
        end
        Equal(count, 4, "one container per element, on its spot's red")
        Equal(table.concat(told, ", "), "e HELPFUL true nil true player, f HELPFUL true nil true player, w HELPFUL true nil true player,"
            .. " a HELPFUL true nil true player", "each told its element's totem buffs, every rank, from anyone, on you")
        Equal(Sorted(S[holders.e].slots.lit.filters.includeSpellIDs), "8072,8076,8156,8157,8162,8163,10403,10404,10405,10441,25362",
            "Earth: Strength of Earth's and Stoneskin's buffs")
        local button = S[holders.e].slots.lit.button
        Equal(tostring(Last(button, "SetAllPoints") == spots.e.warn) .. " " .. tostring(Last(button, "EnableMouse")),
            "true false", "the game's icon lies exactly over the red and takes no mouse")
        Drop(2, "Strength of Earth Totem V", 25361)
        S[holders.e].Update({ { id = 8076 } })
        Equal(S[spots.e.warn].alpha, 0, "no red just after it went down")
        Pass(M.GRACE + .1)
        Equal(tostring(S[spots.e.warn].alpha) .. " " .. tostring(S[button].shown), "1 true", "the buff on you: the game's icon over the red")
        S[holders.e].Update({})
        Equal(tostring(S[button].shown) .. " " .. table.concat(S[spots.e.red].tint, ","), "false 0.64,0.15,0.15",
            "out of range: its icon gone, the red showing through")
        S[holders.e].Update({ { id = 25362 } })
        Equal(S[button].shown, true, "back in range: normal")
    end

    -- 11. Never red: totems that put no buff on you, and one unknown ---------------------------
    do
        Drop(1, "Searing Totem", 3599)
        Drop(4, "Sentry Totem", 6495)
        Drop(3, "Mystery Totem", 99999)
        Pass(3)
        Equal(Layers(M), "e 1/0/1, f 1/0/0, w 1/0/0, a 1/0/0", "Searing, Sentry and an unknown totem: never red")
        Equal(S[spots.w.label].text, "Water", "an unknown totem: its element's name")
        Drop(1, nil)
        Drop(3, nil)
        Drop(4, nil)
    end

    -- 12. GRACE ------------------------------------------------------------------------------------
    do
        Drop(2, "Stoneskin Totem", 8071)
        Equal(S[spots.e.warn].alpha, 0, "just down: not red yet")
        Pass(1)
        Drop(2, "Strength of Earth Totem", 8075)
        Pass(1.6)
        Equal(S[spots.e.warn].alpha, 0, "the replaced totem's timer doesn't end the new one's")
        Pass(1)
        Equal(S[spots.e.warn].alpha, 1, "red after its own")
    end

    -- 14. Containers rule (and 17: out of combat) -------------------------------------------------
    do
        local function Alpha() return S[M.bar].alpha end
        ns.Set("totemOutOfCombat", "fade")
        M:UpdateShown()
        local fade = Alpha()
        ns.Set("totemOutOfCombat", "hide")
        M:UpdateShown()
        local hide = Alpha()
        Equal(fade .. " " .. hide, "0.3 0", "Fade and Hide out of combat")
        lockdown = true
        Fire("PLAYER_REGEN_DISABLED")
        Equal(Alpha(), 1, "in full in a fight")
        lockdown = false
        Fire("PLAYER_REGEN_ENABLED")
        Equal(Alpha(), 0, "hidden again after it")
        target, hostile = true, true
        Fire("PLAYER_TARGET_CHANGED")
        Equal(Alpha(), 1, "an enemy targeted")
        hostile = SECRET
        Fire("PLAYER_TARGET_CHANGED")
        Equal(Alpha(), 1, "a target the game keeps secret counts as an enemy")
        ns.Set("oocIgnoreTarget", true)
        Fire("PLAYER_TARGET_CHANGED")
        Equal(Alpha(), 0, "Stay hidden with an enemy targeted: stays hidden")
        ns.Set("oocIgnoreTarget", false)
        target, hostile = false, true
        Fire("PLAYER_TARGET_CHANGED")
        M:PageOpen(true)
        Equal(Alpha(), 1, "its page open")
        M:PageOpen(false)
        Equal(Alpha(), 0, "its page closed")
        EditModeManagerFrame:Show()
        Equal(Alpha(), 1, "Edit Mode open")
        EditModeManagerFrame:Hide()
        Equal(Alpha(), 0, "Edit Mode closed")
        ns.Set("totemBar", false)
        M:Apply()
        Equal(tostring(S[M.bar].shown) .. " " .. Alpha() .. " " .. tostring(next(S[M.driver].events)), "true 0 nil",
            "turned off: gone right out, never hidden, nothing heard")
        Equal(S[holders.e].slots.lit.enabled, false, "and the game's slots switched off")
        ns.Set("totemBar", true)
        ns.Set("totemOutOfCombat", "show")
        M:Apply()
        Equal(tostring(Alpha()) .. " " .. tostring(S[holders.e].slots.lit.enabled), "1 true", "back on")
        local ok = M:StartMove()
        M:StopMove(false)
        lockdown = true
        Fire("PLAYER_REGEN_DISABLED")
        lockdown = false
        Fire("PLAYER_REGEN_ENABLED")
        Equal(tostring(ok) .. " " .. #ContainerRuns .. " " .. table.concat(ContainerRuns, "; "), "true 0 ",
            "nothing it sits in was ever shown or hidden by the addon: off and on, Fade, Hide, Edit Mode, moving, fights")
    end

    -- 13. Range ticked in a fight, unticked out of one ------------------------------------------
    do
        local ns2, M2 = Fresh({ totemBar = true }, nil, nil)
        lockdown = true
        Fire("PLAYER_REGEN_DISABLED")
        ns2.Set("totemRange", true)
        M2:Apply()
        Equal(#containers, 0, "ticked in a fight: nothing made yet")
        lockdown = false
        Fire("PLAYER_REGEN_ENABLED")
        local made = Holders(M2)
        Equal(tostring(made.e ~= nil) .. " " .. #containers, "true 4", "made as the fight ends")
        ns2.Set("totemRange", false)
        M2:Apply()
        local spots2 = Spots(M2)
        Equal(tostring(S[made.e].slots.lit.enabled) .. " " .. tostring(S[spots2.e.warn].alpha), "false 0",
            "unticked: the slots switched off, no red")
        -- 9. A reload in a fight: no cast seen, every answer secret.
        local saved = ForeverEnhancedCooldownManagerDB
        saved.totemRange = true
        local ns3, M3 = Fresh(saved, nil, function() lockdown, TotemsSecret = true, true end)
        Pass(M3.GRACE + 1)
        local spots3 = Spots(M3)
        Equal(tostring(S[spots3.a.warn].alpha) .. " " .. S[spots3.a.label].text .. " " .. #containers, "0 Air 0",
            "after a reload in a fight: never red, the element's name, no container until it's over")
        lockdown, TotemsSecret = false, false
        Fire("PLAYER_REGEN_ENABLED")
        Equal(#containers, 4, "made once it's over")
        T.ns3 = ns3
    end

    -- 15. Layout -------------------------------------------------------------------------------------
    do
        local ns4, M4 = Fresh({ totemBar = true })
        local bar = M4.bar
        local s4 = Spots(M4)
        local function Lay(key, value)
            ns4.Set(key, value)
            M4:Apply()
            return N(S[bar].width) .. "x" .. N(S[bar].height) .. " " .. Across(M4)
        end
        Equal(Lay("totemPerRow", 2) .. " | " .. At(s4.e) .. " " .. At(s4.f) .. " " .. At(s4.w) .. " " .. At(s4.a),
            "76x76 efwa | TOPLEFT 0 0 TOPLEFT 40 0 TOPLEFT 0 -40 TOPLEFT 40 -40", "2 per row: a square")
        Equal(Lay("totemPerRow", 1) .. " " .. At(s4.a), "36x156 efwa TOPLEFT 0 -120", "1 per row: a column")
        ns4.Set("totemPerRow", 4)
        Equal(Lay("totemGrow", "left") .. " " .. At(s4.e), "156x36 awfe TOPLEFT 120 0", "Grow Left: the first on the right")
        ns4.Set("totemGrow", "centre")
        ns4.Set("totemPerRow", 2)
        Equal(Lay("totemWrap", "up") .. " " .. At(s4.e) .. " " .. At(s4.w), "76x76 waef BOTTOMLEFT 0 0 BOTTOMLEFT 0 40",
            "New rows Above: the next row over the first")
        ns4.Set("totemWrap", "down")
        ns4.Set("totemPerRow", 4)
        Equal(Lay("totemSpacing", 10), "174x36 efwa", "spacing 10")
        ns4.Set("totemSpacing", 4)
        Equal(Lay("totemHeight", 50) .. " " .. N(S[s4.e].width) .. "x" .. S[s4.e].height, "156x18 efwa 36x18", "Icon height 50%")
        ns4.Set("totemHeight", 100)
        ns4.Bars:SetScale(150)
        Equal(N(S[s4.e].width) .. "x" .. N(S[s4.e].height) .. " " .. N(S[bar].width), "54x54 228", "All bars at 150 sizes the totems too")
        ns4.Bars:SetScale(100)
        ns4.Set("totemPerRow", 2)
        Equal(Lay("totemNames", true) .. " " .. At(s4.w), "76x90 efwa TOPLEFT 0 -54", "names: room under the first row")
        T.ns4, T.M4 = ns4, M4
    end

    -- 16. Order -----------------------------------------------------------------------------------
    do
        local ns4, M4 = T.ns4, T.M4
        ns4.Set("totemNames", false)
        ns4.Set("totemPerRow", 4)
        M4:SetOrderAt(1, "a")
        Equal(ns4.Get("totemOrder") .. " " .. table.concat(M4:Order()) .. " " .. Across(M4), "afwe afwe afwe",
            "Air put first: it swaps with Earth")
        local preview = M4:NewPreview(UIParent)
        M4:DrawPreview(preview)
        local first
        for _, kid in ipairs(S[preview].kids) do
            if rawget(kid, "letter") and S[kid].points[1][4] == 0 then first = kid.letter end
        end
        Equal(first, "a", "the preview follows")
        ForeverEnhancedCooldownManagerDB.totemOrder = "eewa"
        M4:Apply()
        Equal(table.concat(M4:Order()) .. " " .. Across(M4), "efwa efwa", "a broken saved order: Earth, Fire, Water, Air")
        -- The preview's samples.
        local samples = {}
        for _, kid in ipairs(S[preview].kids) do
            if rawget(kid, "letter") then
                samples[kid.letter] = tostring(S[kid.placed].alpha) .. " " .. tostring(S[kid.warn].alpha) .. " "
                    .. tostring(S[kid.label].text)
            end
        end
        Equal(samples.e .. ", " .. samples.f .. ", " .. samples.w .. ", " .. samples.a,
            "1 0 Strength of Earth, 1 0 Searing, 1 0 Mana Spring, 0 0 Air", "the preview: three samples and an element with none")
        ns4.Set("totemRange", true)
        M4:DrawPreview(preview)
        for _, kid in ipairs(S[preview].kids) do
            if rawget(kid, "letter") == "w" then Equal(S[kid.warn].alpha, 1, "Mana Spring red with the range warning ticked") end
        end
        local made = 0
        for _, c in ipairs(containers) do
            local at = S[c].parent
            while at and at ~= preview do at = S[at] and S[at].parent end
            if at == preview then made = made + 1 end
        end
        Equal(made, 0, "a preview never holds a container")
    end

    -- 18. Moving it --------------------------------------------------------------------------------
    do
        local ns4, M4 = T.ns4, T.M4
        ns4.ShowWindow()
        lockdown = true
        local ok, why = M4:StartMove()
        Equal(tostring(ok) .. " " .. tostring(why), "false Finish the fight first, then move it.", "refused in a fight")
        lockdown = false
        ok = M4:StartMove()
        local mover = M4.mover
        Equal(tostring(ok) .. " " .. tostring(S[FECMFrame].shown) .. " " .. tostring(S[mover].shown) .. " "
            .. tostring(S[mover.done].shown) .. " " .. S[mover.label].text .. " | " .. S[mover.note].text,
            "true false true true Totems | Drag the bar, then click Done or right-click it.", "the window out of the way, the box with Done")
        S[mover].scripts.OnDragStart(mover)
        S[M4.bar].cx, S[M4.bar].cy = 300, 350
        S[mover].scripts.OnDragStop(mover)
        Equal(ns4.Get("totemX") .. " " .. ns4.Get("totemY") .. " " .. At(M4.bar), "-200 -50 CENTER -200 -50", "dropped: its middle kept")
        S[mover].scripts.OnDragStart(mover)
        S[M4.bar].cx = 99999
        S[mover].scripts.OnDragStop(mover)
        Equal(ns4.Get("totemX"), 4000, "kept within its limits")
        mover.done:Click()
        Equal(tostring(S[mover].shown) .. " " .. tostring(S[FECMFrame].shown), "false true", "Done: the box gone, the window back")
        if FECMFrame.pages.totems then Equal(FECMFrame.selected, "totems", "on the Totems page") end
        M4:StartMove()
        lockdown = true
        Fire("PLAYER_REGEN_DISABLED")
        Equal(tostring(S[mover].shown) .. " " .. tostring(S[FECMFrame].shown), "false false", "a fight ends the move, no window")
        lockdown = false
        Fire("PLAYER_REGEN_ENABLED")
        M4:ResetPlace()
        Equal(ns4.Get("totemX") .. " " .. ns4.Get("totemY") .. " " .. At(M4.bar), "-300 -175 CENTER -300 -175", "Reset: back where it started")
        ns4.Set("useBars", true)
        ns4.Bars:SetUnlocked(true)
        Equal(tostring(S[mover].shown) .. " " .. tostring(S[mover.done].shown), "true false", "your bars unlocked: the box, no Done")
        ns4.Bars:SetUnlocked(false)
        Equal(S[mover].shown, false, "locked: gone")
    end

    -- 3 and 24. The page: under More for a shaman, its controls, its words, and all of it fitting ------
    do
        local ns8, M8 = Fresh(nil)
        ns8.ShowWindow()
        local w = FECMFrame
        local page = w.pages.totems
        Equal(tostring(page ~= nil) .. " " .. tostring(w.nav.totems ~= nil), "true true", "a shaman: the Totems page and its item")
        local function Y(item)
            local _, top = Fit.Rect(item)
            return top
        end
        Equal(tostring(Y(w.nav.raid) < Y(w.nav.pulse) and Y(w.nav.pulse) < Y(w.nav.totems)) .. " " .. S[w.nav.totems.label].text,
            "true Totems", "under More: Raid Timers, Cooldown pulse, then Totems")
        Equal(Fit.Note(w.nav.totems), "Your totems on a bar of their own: each one's time left, and red when you're out of its range.",
            "its note in the footer")
        w:Select("totems")
        Equal(tostring(S[page].shown) .. " " .. S[page.title].text .. " | " .. S[page.status].text .. " | " .. tostring(M8.bar),
            "true TOTEMS | Off. Tick the box below to start. | nil", "shaman, off: the page says so, no bar made")
        Equal(tostring(page.master:GetChecked()) .. " " .. tostring(page.range:GetChecked()) .. " " .. tostring(page.names:GetChecked())
            .. " " .. tostring(page.timer:GetChecked()), "false false false true", "every tick as its default")
        Equal(S[page.where].text, "Left of your bars, where it starts.", "where it shows, at the start")

        -- The controls drive the settings and the bar.
        page.master:Click()
        Equal(tostring(ns8.Get("totemBar")) .. " " .. tostring(M8.bar ~= nil) .. " " .. tostring(S[M8.bar].alpha) .. " | "
            .. S[page.status].text, "true true 1 | On. Drop a totem to see its time.", "ticked: the bar made, in full while the page is open")
        ns8.Set("totemOutOfCombat", "hide")
        M8:UpdateShown()
        Equal(S[M8.bar].alpha, 1, "Hide out of combat, but its page is open: in full")
        w:Select("general")
        Equal(S[M8.bar].alpha, 0, "another page: hidden as chosen")
        w:Select("totems")
        page.outOfCombat.buttons[1]:Click()
        page.grow.buttons[2]:Click()
        page.wrap.buttons[2]:Click()
        Equal(ns8.Get("totemOutOfCombat") .. " " .. ns8.Get("totemGrow") .. " " .. ns8.Get("totemWrap") .. " " .. page.outOfCombat.selected
            .. " " .. page.grow.selected .. " " .. page.wrap.selected, "show left up show left up", "the choices saved and shown")
        page.grow.buttons[1]:Click()
        page.wrap.buttons[1]:Click()
        page.size:Choose(44)
        page.across:Choose(2)
        page.spacing:Choose(6)
        page.height:Choose(50)
        Equal(ns8.Get("totemSize") .. " " .. ns8.Get("totemPerRow") .. " " .. ns8.Get("totemSpacing") .. " " .. ns8.Get("totemHeight") .. " "
            .. N(S[Spots(M8).e].width) .. "x" .. N(S[Spots(M8).e].height) .. " " .. S[page.height.value].text,
            "44 2 6 50 44x22 50%", "the sliders saved, the bar sized, Icon height shown as a share")
        page.height:Choose(100)
        page.across:Choose(4)
        page.names:Click()
        page.timer:Click()
        Equal(tostring(ns8.Get("totemNames")) .. " " .. tostring(ns8.Get("totemTimer")) .. " " .. tostring(S[Spots(M8).e.label].shown) .. " "
            .. tostring(Last(Spots(M8).e.cooldown, "SetHideCountdownNumbers")), "true false true true", "names on, numbers off")
        page.names:Click()
        page.timer:Click()
        page.range:Click()
        Equal(tostring(ns8.Get("totemRange")) .. " " .. #containers, "true 4", "Red when out of range ticked: the game's slots made")

        -- The order: an arrow steps that spot's element on, swapping the two.
        local function Names()
            local out = {}
            for _, picker in ipairs(page.order) do out[#out + 1] = S[picker.name].text end
            return table.concat(out, " ")
        end
        Equal(Names(), "Earth Fire Water Air", "the order: Earth, Fire, Water, Air")
        page.order[1].next:Click()
        Equal(ns8.Get("totemOrder") .. " " .. Names() .. " " .. Across(M8), "fewa Fire Earth Water Air fewa",
            "first spot's > : Fire first, Earth swapped into its spot, the bar follows")
        page.order[4].back:Click()
        Equal(ns8.Get("totemOrder") .. " " .. Names(), "feaw Fire Earth Air Water", "last spot's < : Water to Air, swapped")
        page.order[4].next:Click()
        page.order[1].back:Click()
        Equal(ns8.Get("totemOrder"), "efwa", "and back")

        -- Status: totems down, and in a fight.
        Drop(2, "Strength of Earth Totem", 10442, 136023)
        w:Refresh()
        Equal(S[page.status].text, "On. 1 totem down.", "one down")
        Drop(1, "Searing Totem", 3599, 135825)
        w:Refresh()
        Equal(S[page.status].text, "On. 2 totems down.", "two down")
        lockdown = true
        Fire("PLAYER_REGEN_DISABLED")
        w:Refresh()
        Equal(S[page.status].text, "On.", "in a fight: on, no count")
        page.move:Click()
        Equal(tostring(S[w].shown) .. " " .. tostring(S[w.note].text), "true Finish the fight first, then move it.",
            "Move in a fight: refused, and why")
        lockdown = false
        Fire("PLAYER_REGEN_ENABLED")

        -- Move and Reset.
        page.move:Click()
        Equal(tostring(S[w].shown) .. " " .. tostring(S[M8.mover].shown) .. " " .. tostring(S[M8.mover.done].shown), "false true true",
            "Move: the window away, the box with Done")
        S[M8.mover].scripts.OnDragStart(M8.mover)
        S[M8.bar].cx, S[M8.bar].cy = 500, 300
        S[M8.mover].scripts.OnDragStop(M8.mover)
        M8.mover.done:Click()
        Equal(tostring(S[w].shown) .. " " .. w.selected .. " | " .. S[page.where].text, "true totems | Where you dragged it.",
            "Done: back on the Totems page, where you dragged it")
        page.reset:Click()
        Equal(ns8.Get("totemX") .. " " .. ns8.Get("totemY") .. " | " .. S[w.note].text .. " | " .. S[page.where].text,
            "-300 -175 | The Totems bar is back where it started. | Left of your bars, where it starts.", "Reset: back where it started")

        -- The preview: fitted to its box, its note following the range tick.
        local preview = page.preview
        Equal(tostring(Last(preview, "SetScale") <= 1) .. " " .. Fit.Note(page.previewBox), "true A preview with your choices: two totems"
            .. " down, one out of range, and an element with none.", "the preview: no bigger than it is, its note with the range warning")
        page.size:Choose(64)
        page.height:Choose(150)
        page.across:Choose(1)
        page.names:Click()
        local scale = Last(preview, "SetScale")
        Equal(tostring(S[preview].width * scale <= 380.01 and S[preview].height * scale <= 72.01), "true",
            "a big column drawn smaller to fit its box")
        page.names:Click()
        page.size:Choose(36)
        page.height:Choose(100)
        page.across:Choose(4)
        page.range:Click()
        Equal(Fit.Note(page.previewBox), "A preview with your choices: three totems down and an element with none.",
            "its note without the range warning")

        -- Notes that follow the game: All bars, Stay hidden, a range warning the game can't show.
        Equal(Fit.Note(page.size), "How big the totems are. All bars on the Layout page sizes them too.", "Icon size, All bars at 100")
        ns8.Set("barScale", 150)
        Equal(Fit.Note(page.size), "Their own size. All bars on the Layout page is at 150, so they show at 54.", "All bars at 150")
        ns8.Set("barScale", 50)
        page.size:Choose(20)
        Equal(Fit.Note(page.size), "Their own size. All bars on the Layout page is at 50, so they show at 20, the smallest they go.",
            "the smallest")
        ns8.Set("barScale", 100)
        page.size:Choose(36)
        ns8.Set("oocIgnoreTarget", true)
        Equal(Fit.Note(page.outOfCombat.buttons[1]), "Out of combat. The bar comes back in full in combat, while this page is open,"
            .. " while you move it, and in Edit Mode.", "Out of combat with Stay hidden ticked")
        ns8.Set("oocIgnoreTarget", false)
        Equal(Fit.Note(page.outOfCombat.buttons[1]), "Out of combat. The bar comes back in full in combat, with an enemy targeted,"
            .. " while this page is open, while you move it, and in Edit Mode.", "and without")

        -- Everything inside the page and its boxes, none on another; every
        -- note in two lines of the footer.
        w:Refresh()
        Equal(Fit.Problems(page, { { page.tray, "the tray" }, { page.options, "the options" } }, page.preview), "",
            "every control inside the page and its boxes, none on another")
        Equal(tostring(#Fit.Pieces(page, page.preview) >= 25), "true", "and every control was looked at")
        local _, top, _, bottom = Fit.Rect(page.options)
        local _, pageTop = Fit.Rect(page)
        Equal(tostring(bottom - pageTop <= 489), "true", "the page's height: " .. (bottom - pageTop) .. " of 489")
        local long, notes = {}, 0
        local room = 2 * S[w.note].width
        local function Check(control)
            local note = Fit.Note(control)
            if note then
                notes = notes + 1
                if Fit.Wide(note, S[w.note].template) > room then long[#long + 1] = note end
                if note:find("\226\128\148", 1, true) or note:find("!", 1, true) then long[#long + 1] = "a dash or ! in: " .. note end
            end
        end
        for _, obj in ipairs(objects) do
            if Fit.Inside(obj, page) and rawget(obj, "hint") then Check(obj) end
        end
        ns8.Set("totemRange", true)
        for _, obj in ipairs({ page.previewBox, page.range }) do Check(obj) end
        ns8.Set("totemRange", false)
        Check(w.nav.totems)
        Equal(tostring(notes >= 20) .. " " .. table.concat(long, " | "), "true ", "every note fits two lines of the footer, no dashes")
        Equal(tostring(top ~= nil), "true", "the options measured")

        -- The range warning the game can't show: greyed, and says so.
        local saved = _G.CustomAuraContainerSlotDefaultOptions
        _G.CustomAuraContainerSlotDefaultOptions = nil
        w:Refresh()
        Equal(tostring(page.range.usable) .. " " .. Fit.Note(page.range), "false Your game can't show the range warning.",
            "the range tick greyed where the game can't show it")
        _G.CustomAuraContainerSlotDefaultOptions = saved
        w:Refresh()

        -- The page's help: three steps, each pointing at its part.
        local Tour = ns8.Tour
        w:Select("totems")
        Equal(tostring(Tour:StartPage("totems")), "true", "the ? starts it")
        Tour:Stop()
        local titles = {}
        for _, step in ipairs(Tour:Page("totems")) do titles[#titles + 1] = step.title end
        Equal(table.concat(titles, ", "), "Turn it on, Red when out of range, Put it anywhere", "the page's help: three steps")
        Equal(S[M8.bar].shown, true, "the bar never hidden")
    end

    -- 19 and 20. Share strings carry it with the look (27, below); profiles leave it alone ---------
    do
        local ns4, M4 = T.ns4, T.M4
        local share = ns4.ProfileShare
        local before = share.Export()
        ns4.Set("totemSize", 50)
        ns4.Set("totemOrder", "awfe")
        ns4.Set("totemRange", true)
        ns4.Set("totemX", 123)
        M4:Apply()
        local look = share.Read(share.Export()).setup.look
        Equal(tostring(share.Export() ~= before) .. " " .. tostring(look.totemSize) .. " " .. tostring(look.totemOrder) .. " "
            .. tostring(look.totemRange) .. " " .. tostring(look.totemX), "true 50 awfe true 123", "its settings go in a share string, with the look")
        local function Totems()
            local out = {}
            for _, key in ipairs({ "totemBar", "totemSize", "totemOrder", "totemRange", "totemX", "totemY" }) do out[#out + 1] = tostring(ns4.Get(key)) end
            return table.concat(out, " ")
        end
        local kept = Totems()
        share.Import("Shared", share.Read(before), false)
        Equal(Totems(), kept, "an import without its look leaves every totem setting as it was")
        ns4.NewProfile("Second")
        Equal(Totems(), kept, "a new profile too")
        ns4.UseProfile(ns4.ProfileName())
        if ns4.Layout and ns4.Layout.Reset then ns4.Layout:Reset() end
        Equal(Totems() .. " " .. At(M4.bar), kept .. " CENTER 123 -175", "and Layout's Reset, and the bar stays put")
    end

    -- 21. Look ---------------------------------------------------------------------------------------
    do
        local ns5, M5 = Fresh({ totemBar = true, totemRange = true, iconBorder = "icon" })
        T.ns5 = ns5
        local s5 = Spots(M5)
        Equal(tostring(s5.e.decor.borderShown) .. " " .. tostring(M5.bar.decor.borderShown), "true nil", "border round each icon")
        ns5.Set("iconBorder", "bar")
        ns5.Bars:ApplyDecor()
        Equal(tostring(s5.e.decor.borderShown) .. " " .. tostring(M5.bar.decor.borderShown), "false true", "round the whole bar")
        lockdown = true
        Fire("PLAYER_REGEN_DISABLED")
        ns5.Set("iconStyle", "blizzard")
        ns5.Style:ApplyDetails()
        Equal(tostring(s5.e.kit.rounded) .. " " .. tostring(s5.e.litKit.rounded), "false false", "in a fight: waits")
        lockdown = false
        Fire("PLAYER_REGEN_ENABLED")
        Equal(tostring(s5.e.emptyKit.rounded) .. " " .. tostring(s5.e.kit.rounded) .. " " .. tostring(s5.e.redKit.rounded) .. " "
            .. tostring(s5.e.litKit.rounded) .. " " .. tostring(Last(s5.e.cooldown, "SetReverse")), "true true true true false",
            "Blizzard's look after it: greyed, placed, red and the game's icon rounded, its time not reversed")
        ns5.Set("font", next(ns5.Style.FONTS))
        ns5.Bars:ApplyFont()
        Equal(Last(s5.e.label, "SetFontObject"), ns5.Style:NameFont(), "a new font reaches the names")
        ns5.Set("countdownSize", 150)
        ns5.Style:ApplyDetails()
        Equal(Last(s5.e.cooldown, "SetCountdownFont"), ns5.Style:Countdown(36), "Icon details' countdown size fitted again")
        ns5.Set("totemTimer", false)
        M5:Apply()
        Equal(Last(s5.e.cooldown, "SetHideCountdownNumbers"), true, "countdown numbers off")
    end

    -- 22 and 23. The debug report, and kept over a reload ------------------------------------------
    do
        local saved = ForeverEnhancedCooldownManagerDB
        local line = T.ns5.DebugReport():match("Totems: [^\n]*")
        Equal(line ~= nil and line:find("shaman true, on true", 1, true) ~= nil, true, "a Totems line in the debug report")
        saved.totemSize, saved.totemX, saved.totemY = 44, 10, 20
        saved.devTotemProbe = { "0.0 old line" }
        local ns6, M6 = Fresh(saved)
        Equal(ns6.Get("totemSize") .. " " .. At(M6.bar) .. " " .. S[Spots(M6).e].width, "44 CENTER 10 20 44", "kept over a reload")
        Equal(ForeverEnhancedCooldownManagerDB.devTotemProbe, nil, "an old development check's lines are cleared")
    end

    -- 25. The buffs are the game data's --------------------------------------------------------------
    do
        -- A shaman knowing every totem's first rank: each one's buffs as the
        -- Buffs bar would watch them (ns.Spells:Find(name).ids).
        local ranks, totems = T.ns.RANKS, T.M.TOTEMS
        local ns7 = Fresh(nil, nil, function()
            for name in pairs(totems) do
                if ranks[name] then table.insert(book[2].items, { name = name, subName = "Rank 1", spellID = ranks[name][1], iconID = 1 }) end
            end
        end)
        local missing = {}
        for name, entry in pairs(totems) do
            Equal(type(ns7.RANKS[name]), "table", name .. " in the game data")
            local found = {}
            local known = ns7.Spells:Find(name)
            for _, aura in ipairs(known and known.ids or {}) do found[aura] = true end
            for _, id in ipairs(entry[2] or {}) do
                if not found[id] then missing[#missing + 1] = name .. " " .. id end
            end
        end
        table.sort(missing)
        Equal(table.concat(missing, ", "), "", "every buff ID is one the game data gives its totem")
    end
end)()

-- 26. Stack it with my bars: the Totems bar as a row in your layout (Squirt's yes, 19 Nov 2026) ---------
-- No display here, so the stack goes round the middle 150 down; Utility has
-- an icon (36 tall), the other bars none (they take no room).
;(function()
    local ns, M = Fresh({ totemBar = true, useBars = true })
    local L, B = ns.Layout, ns.Bars
    local function Rows() return table.concat(ns.LayoutData().above, ",") .. "|" .. table.concat(ns.LayoutData().below, ",") end
    Equal(tostring(L:TotemsStacked()) .. " " .. tostring(L:HoldsTotems()) .. " " .. At(M.bar), "false false CENTER -300 -175",
        "off by default: no row in your layout, the bar in its own spot")
    B:Assign("Attack", "util")
    L:Apply("pyramid")
    Equal(Rows(), "cd|util,buff,debuff", "a preset: no Totems row added")

    -- Ticked: the bottom row, placed as a bar's: its top under the row above, its middle on the display's.
    local ok, message = L:StackTotems(true)
    Equal(tostring(ok) .. " " .. message .. " | " .. Rows(), "true The Totems bar is the bottom row of your layout. Order it on the"
        .. " Layout page. | cd|util,buff,debuff,totems", "ticked: its row at the bottom of your layout")
    Equal(At(B:Get("util")) .. " | " .. At(M.bar) .. " " .. N(S[M.bar].width) .. "x" .. N(S[M.bar].height) .. " " .. tostring(L:HoldsTotems()),
        "TOP 0 -150 | TOP 0 -186 156x36 true", "placed centred under Utility (36 down), held by the layout")

    -- The Layout page: its row in its place, its own icons, the arrows only.
    ns.ShowWindow()
    local w = FECMFrame
    w:Select("layout")
    local page = w.pages.layout
    local row = page.totemRow
    local arts = {}
    for i, tile in ipairs(row.tiles) do arts[i] = tostring(S[tile].texture) end
    Equal(tostring(S[row].shown) .. " " .. S[row.name].text .. " | " .. S[row.across].text .. " | " .. table.concat(arts, ","),
        "true Totems | 4 across | 7008071,7003599,7005675,7008512", "drawn as Totems: Earth, Fire, Water and Air, 4 across")
    Equal(tostring(rawget(row, "fewer")) .. " " .. tostring(rawget(row, "wider")) .. " " .. tostring(rawget(row, "out")) .. " "
        .. tostring(page.rows.totems), "nil nil nil nil", "no - or +, no take out, and not one of your bars' rows (nothing dropped goes on it)")
    local _, rowTop = Fit.Rect(row)
    local _, debuffTop = Fit.Rect(page.rows.debuff)
    Equal(tostring(rowTop > debuffTop) .. " | " .. Fit.Note(row.up) .. " | " .. Fit.Note(row.down), "true | Move Totems up the stack,"
        .. " swapping places with Debuffs. | Totems is already at the bottom.", "under Debuffs, its arrows saying what they do")
    ns.Set("totemPerRow", 2)
    M:Apply()
    w:Refresh()
    local tile = S[row.tiles[1]]
    Equal(S[row.across].text .. " " .. tostring(S[row.strip].height == 2 * tile.height + 2) .. " " .. At(row.tiles[3]),
        "2 across true TOPLEFT 0 " .. N(-(tile.height + 2)), "2 across: two lines of two")
    ns.Set("totemPerRow", 4)
    M:Apply()
    row.up:Click()
    Equal(Rows() .. " | " .. S[w.note].text, "cd|util,buff,totems,debuff | Totems and Debuffs swapped rows.",
        "its up arrow: swapped with Debuffs, order only")
    -- An icon held over it and let go: it takes no spells, so the icon stays on its bar.
    local held = page.rows.util.tiles[1]
    S[held].scripts.OnDragStart(held)
    S[row].mouseOver = true
    S[page.ghost].scripts.OnUpdate(page.ghost)
    local footer = S[w.note].text .. " " .. tostring(S[page.ghost.texture].desaturated) .. " " .. tostring(S[page.mark].shown == true)
    S[held].scripts.OnDragStop(held)
    S[row].mouseOver = nil
    Equal(footer .. " | " .. table.concat(ns.BarData("util").spells, ","), "The Totems bar takes no spells. Let go to leave Attack"
        .. " where it is. true false | Attack", "an icon let go over it: greyed, nothing outlined, and it stays on Utility")

    -- The Totems page: its tick, and Move while it's in your layout.
    w:Select("totems")
    local tp = w.pages.totems
    Equal(tostring(tp.stack:GetChecked()) .. " | " .. S[tp.where].text .. " | " .. Fit.Note(tp.stack) .. " | " .. Fit.Note(tp.move),
        "true | In your layout. Order it on the Layout page. | It takes a row in your layout, under your other rows. Put it in order"
        .. " on the Layout page. | It's in your layout: order it on the Layout page.", "the tick on, where it shows, its notes")
    Equal(Fit.Note(tp.reset), "Puts its own spot back where it started, for when it leaves your layout.",
        "Reset's note while it's in your layout")
    tp.move:Click()
    Equal(tostring(S[w].shown) .. " " .. S[w.note].text, "true It's in your layout: order it on the Layout page.",
        "Move: refused while it's in your layout, and why")
    tp.stack:Click()
    Equal(tostring(tp.stack:GetChecked()) .. " " .. Rows() .. " " .. At(M.bar) .. " | " .. S[w.note].text, "false cd|util,buff,debuff"
        .. " CENTER -300 -175 | The Totems bar is out of your layout, back in its own spot.", "unticked: out of your layout, back in its own spot")
    tp.stack:Click()
    Equal(tostring(tp.stack:GetChecked()) .. " " .. Rows(), "true cd|util,buff,debuff,totems", "ticked again: at the bottom")
    w:Hide()

    -- Names on: a row under it goes down by its height and its names' room (36 and 14).
    ns.Set("totemNames", true)
    M:Apply()
    L:Swap("totems", -1)
    L:Swap("totems", -1)
    Equal(Rows() .. " | " .. At(M.bar) .. " | " .. At(B:Get("buff")), "cd|util,totems,buff,debuff | TOP 0 -186 | TOP 0 -236",
        "up two, under Utility: Buffs under it by its height and names")
    local util = ns.BarData("util").perRow
    ok, message = L:Swap("totems", -1)
    Equal(Rows() .. " | " .. message .. " | " .. util .. " " .. ns.BarData("util").perRow .. " " .. ns.Get("totemPerRow"),
        "cd|totems,util,buff,debuff | Totems and Utility swapped rows. | 5 5 4", "swapped with Utility: order only, each keeps its icons across")
    Equal(At(M.bar) .. " | " .. At(B:Get("util")), "TOP 0 -150 | TOP 0 -200", "Totems right under the display, Utility under its names")
    L:Swap("totems", -1)
    Equal(Rows() .. " | " .. At(M.bar) .. " | " .. At(B:Get("cd")), "totems|cd,util,buff,debuff | BOTTOM 0 -136 | TOP 0 -150",
        "past Cooldowns, above the display: it sits on its names, growing up")

    -- Its width counts for your widest row (Match the resource display to my rows).
    local before = L:WidestRow()
    ns.Set("totemSize", 64)
    M:Apply()
    Equal(N(before) .. " " .. N(L:WidestRow()), "180 268", "Utility's 5 of 36 the widest, then the Totems bar's 4 of 64 with 4 between")
    ns.Set("totemSize", 36)
    ns.Set("totemNames", false)
    M:Apply()
    L:Swap("totems", 1)
    Equal(Rows() .. " | " .. At(M.bar) .. " | " .. At(B:Get("util")), "cd|totems,util,buff,debuff | TOP 0 -150 | TOP 0 -186",
        "back under the display, names off")

    -- In a fight once it holds the game's slots: never moved, its room kept
    -- for the rows under it; placed as the fight ends.
    ns.Set("totemRange", true)
    M:Apply()
    local slots = 0
    for _ in pairs(Holders(M)) do slots = slots + 1 end
    Equal(slots, 4, "Red when out of range: the game's slots made")
    lockdown = true
    Fire("PLAYER_REGEN_DISABLED")
    ns.LayoutData().gap = 4
    L:Stack()
    Equal(At(M.bar) .. " | " .. At(B:Get("util")) .. " | " .. tostring(L.pending), "TOP 0 -150 | TOP 0 -194 | true",
        "in a fight: the Totems bar stays put, Utility still leaves its room")
    lockdown = false
    Fire("PLAYER_REGEN_ENABLED")
    Equal(At(M.bar) .. " " .. tostring(L.pending), "TOP 0 -154 nil", "placed as the fight ends")
    L:SetGap(0)

    -- The bar off: its row stays saved but takes no room, and can't be swapped.
    L:Swap("totems", 1)
    ns.Set("totemBar", false)
    M:Apply()
    Equal(Rows() .. " | " .. table.concat(L:Rows(), ",") .. " | " .. tostring(L:CanSwap("totems", -1)) .. " " .. tostring(L:CanSwap("util", 1))
        .. " " .. tostring(L:HoldsTotems()) .. " " .. At(B:Get("buff")), "cd|util,totems,buff,debuff | cd,util,buff,debuff | false true false"
        .. " TOP 0 -186", "off: kept in your layout, but no row: Buffs right under Utility")
    ns.Set("totemBar", true)
    M:Apply()
    Equal(At(M.bar) .. " | " .. At(B:Get("buff")), "TOP 0 -186 | TOP 0 -222", "on again: back in its row")
    -- Ticked while the bar's off: saved at the bottom, and it says what's missing.
    ns.Set("totemBar", false)
    M:Apply()
    ok, message = L:StackTotems(true)
    Equal(message .. " | " .. Rows(), "The Totems bar joins your layout once you tick Show the Totems bar. | cd|util,buff,debuff,totems",
        "ticked with the bar off: its row saved, and the footer says to show the bar")
    ns.Set("totemBar", true)
    M:Apply()

    -- A preset, Reset and Undo: it stays, at the bottom.
    L:Apply("wide")
    Equal(Rows(), "cd|util,buff,debuff,totems", "another preset: still stacked, at the bottom")
    L:Reset()
    Equal(Rows(), "cd|util,buff,debuff,totems", "Reset: the same")
    L:Apply("sides")
    Equal(Rows() .. " " .. ns.LayoutData().left .. " " .. ns.LayoutData().right, "cd|util,totems buff debuff", "Sides: under Utility")
    L:Swap("totems", -1)
    ok, message = L:Swap("totems", -1)
    Equal(Rows() .. " " .. ns.LayoutData().left .. " " .. ns.LayoutData().right .. " | " .. message, "cd,totems|util buff debuff | Totems"
        .. " moved up past the display.", "next to a row beside the display: past the display instead, those staying")
    ok, message = L:Swap("buff", -1)
    Equal(Rows() .. " | " .. message .. " | " .. table.concat(L:Rows(), ","), "cd|totems,util | Totems moved down past the display."
        .. " | cd,buff,debuff,totems,util", "and back down past it, from the row beside it")
    L:Undo()
    Equal(Rows(), "cd|util,buff,debuff,totems", "Undo: as it was before Sides")

    -- Dragged while your bars are unlocked: the layout stops, as for a bar,
    -- and where it was let go is its own spot.
    B:SetUnlocked(true)
    local mover = M.mover
    Equal(S[mover].shown, true, "unlocked: the box over it")
    S[mover].scripts.OnDragStart(mover)
    S[M.bar].cx, S[M.bar].cy = 400, 300
    S[mover].scripts.OnDragStop(mover)
    Equal(tostring(L:Active()) .. " " .. tostring(L.moved) .. " " .. ns.Get("totemX") .. " " .. ns.Get("totemY") .. " " .. At(M.bar),
        "false true -100 -100 CENTER -100 -100", "dragged out of your layout: it stops, the bar where it was let go")
    B:SetUnlocked(false)
    L:LineUp()
    Equal(tostring(L:HoldsTotems()) .. " " .. At(M.bar), "true TOP 0 -186", "lined up again: back in its row")
    -- Turned off: it stays where it is, as your bars do.
    S[M.bar].cx, S[M.bar].cy = 500, 214
    L:TurnOff()
    L:Stack()
    Equal(ns.Get("totemX") .. " " .. ns.Get("totemY") .. " " .. At(M.bar), "0 -186 CENTER 0 -186", "the layout off: it stays put, that spot its own")
    L:LineUp()
    -- Reset positions (Layout page): the layout stops and it goes back to its own spot, kept as it was.
    ns.Set("totemX", -250)
    ns.Set("totemY", -100)
    Equal(At(M.bar), "TOP 0 -186", "its own spot changed while in your layout: it stays in its row")
    B:ResetPositions()
    Equal(tostring(L:Active()) .. " " .. ns.Get("totemX") .. " " .. ns.Get("totemY") .. " " .. At(M.bar), "false -250 -100 CENTER -250 -100",
        "Reset positions: the layout off, the Totems bar back in its own spot")
    L:LineUp()

    -- Kept once, above or below only; never added.
    local layout = ns.LayoutData()
    layout.above, layout.below, layout.left, layout.right = { "totems", "cd", "totems" }, { "totems", "util", "nope" }, "totems", nil
    layout = ns.LayoutData()
    Equal(Rows() .. " " .. tostring(layout.left) .. " " .. tostring(layout.hidden.totems), "totems,cd|util,buff,debuff nil nil",
        "repaired: once, never beside the display, never taken out; bars missing go under, it never does")

    -- In a share string: its row (its settings go with the look: 27, below).
    L:Apply("pyramid")
    local P = ns.ProfileShare
    local text = P.Export()
    local shared = P.Read(text)
    Equal(table.concat(shared.setup.layout.below, ",") .. " " .. shared.skipped .. " " .. tostring(shared.setup.look.totemSize),
        "util,buff,debuff,totems 0 nil", "a share string carries its row")
    local ns2 = Fresh({ totemBar = true, useBars = true })
    local done = ns2.ProfileShare.Import("Shared", ns2.ProfileShare.Read(text), true)
    Equal(tostring(done) .. " " .. tostring(ns2.Layout:HoldsTotems()) .. " " .. table.concat(ns2.LayoutData().below, ",") .. " "
        .. At(ns2.Totems.bar), "true true util,buff,debuff,totems TOP 0 -186",
        "imported with its look by a shaman: stacked there too, under Utility (its Attack came with the profile)")

    -- Not a shaman: its row kept, but skipped everywhere.
    local ns3 = Fresh({ totemBar = true, useBars = true, layout = { on = true, base = "pyramid", above = { "cd" },
        below = { "util", "totems", "buff", "debuff" } } }, "DRUID")
    local L3 = ns3.Layout
    L3:Stack()
    Equal(table.concat(ns3.LayoutData().below, ",") .. " | " .. table.concat(L3:Rows(), ",") .. " | " .. tostring(L3:CanSwap("totems", 1))
        .. " " .. tostring(L3:CanSwap("util", 1)) .. " " .. tostring(L3:HoldsTotems()) .. " " .. tostring(ns3.Totems.bar) .. " "
        .. tostring(L3:WidestRow()), "util,totems,buff,debuff | cd,util,buff,debuff | false true false nil nil",
        "a druid: the row kept, but no room, no swap, no bar")
    ns3.ShowWindow()
    FECMFrame:Select("layout")
    Equal(tostring(FECMFrame.pages.layout.totemRow), "nil", "and no Totems row drawn")
    local done3 = ns3.ProfileShare.Import("Shared", ns3.ProfileShare.Read(text), true)
    Equal(tostring(done3) .. " " .. table.concat(ns3.LayoutData().below, ",") .. " | " .. table.concat(L3:Rows(), ","),
        "true util,buff,debuff,totems | cd,util,buff,debuff", "a shaman's string imported by a druid: harmless")
end)()

-- 27. A share string brings the Totems bar (Squirt's yes, 19 Nov 2026) ----------------------------------------
-- Made on a shaman with the bar on and set up: imported with its look by a
-- shaman with it off, the bar comes on and is drawn at once as shared, in
-- its own spot, and the question names it. Without its look nothing of it
-- changes. A druid gets the settings saved and the tick on (unnamed), and
-- nothing made, heard or shown. (Tools/TestShare.lua checks the string
-- itself: what goes in, odd values, older strings.)
;(function()
    local ns = Fresh({ useBars = true, totemBar = true, totemSize = 44, totemPerRow = 2, totemOrder = "awfe", totemX = -320,
        totemY = -120, totemOutOfCombat = "fade", totemNames = true })
    local text = ns.ProfileShare.Export()
    local shared = ns.ProfileShare.Read(text)
    Equal(tostring(shared.setup.parts.totemBar) .. " " .. shared.skipped .. " " .. tostring(shared.setup.look.totemSize) .. " "
        .. tostring(shared.setup.look.totemSpacing), "true 0 44 nil", "the string: the bar on and its settings, those at their default left out")
    -- A shaman with the bar off: nothing made yet.
    local ns2, M2 = Fresh({ useBars = true })
    local function Bar(n)
        return table.concat({ tostring(n.Get("totemBar")), n.Get("totemSize"), n.Get("totemPerRow"), n.Get("totemOrder"), n.Get("totemX"),
            n.Get("totemY"), n.Get("totemOutOfCombat"), tostring(n.Get("totemNames")) }, " ")
    end
    -- Without its look: nothing of it changes, nothing made.
    local ok = ns2.ProfileShare.Import("Lists", ns2.ProfileShare.Read(text), false)
    Equal(tostring(ok) .. " " .. Bar(ns2) .. " " .. tostring(M2.bar), "true false 36 4 efwa -300 -175 show false nil",
        "imported without its look: the Totems bar as it was, nothing made")
    Equal(ns2.ProfileShare.LookQuestion(ns2.ProfileShare.Read(text)), "Your bar sizes, spots, layout and look change to the shared ones,"
        .. " on every character. It also turns on Totems bar. To keep a copy of yours, Share it first.", "the question names it")
    local message
    ok, message = ns2.ProfileShare.Import("Shared", ns2.ProfileShare.Read(text), true)
    Equal(tostring(ok) .. " " .. message, "true Imported Shared with its look and layout, and switched to it. Also turned on 1 of its settings.",
        "imported with its look: switched on, and counted")
    Equal(Bar(ns2) .. " | " .. N(S[M2.bar].width) .. "x" .. N(S[M2.bar].height) .. " " .. Across(M2) .. " " .. At(M2.bar) .. " "
        .. tostring(S[M2.bar].alpha), "true 44 2 awfe -320 -120 fade true | 92x106 awfe CENTER -320 -120 0.3",
        "every setting as shared, the bar made and drawn at once: 2 across of 44, names under, in its own spot, faded out of a fight")
    Equal(tostring(ns2.ProfileShare.Export() == text), "true", "and shares the same string back")
    -- Never turned off: a string with it off leaves yours on.
    local off = Fresh({ useBars = true })
    local plain = off.ProfileShare.Export()
    ns2.ProfileShare.Import("Plain", ns2.ProfileShare.Read(plain), true)
    Equal(Bar(ns2) .. " " .. tostring(S[M2.bar].alpha > 0), "true 36 4 efwa -300 -175 show false true",
        "a string with it off: yours stays on, its settings back to the string's (the defaults)")
    -- A druid: saved, unnamed, nothing made or heard.
    local ns3, M3 = Fresh({ useBars = true }, "DRUID")
    local question = ns3.ProfileShare.LookQuestion(ns3.ProfileShare.Read(text))
    ok, message = ns3.ProfileShare.Import("Shared", ns3.ProfileShare.Read(text), true)
    Equal(tostring(ok) .. " " .. message .. " | " .. tostring(question:find("Totems", 1, true)), "true Imported Shared with its look and"
        .. " layout, and switched to it. | nil", "a druid: not named, not counted")
    Equal(Bar(ns3) .. " | " .. tostring(M3.bar) .. " " .. tostring(M3.driver), "true 44 2 awfe -320 -120 fade true | nil nil",
        "its settings and tick saved (they're every character's), nothing made or heard")
    Equal(#printed, 0, "no errors")
end)()

-- 28. Searing and Magma: red once you're further than they reach (a player's idea, Squirt's yes, 20 Nov 2026) --
-- Their spot is yours as you cast them (UnitPosition); where you are is looked
-- at every LOOK_EVERY seconds while one stands, then no more. Never red while
-- the game won't say where you are (a dungeon, a secret), on another map,
-- with Red when out of range unticked, or for one seen but not cast by you
-- since the addon started (after a reload).
;(function()
    local ns, M = Fresh({ useBars = true, totemBar = true, totemRange = true })
    local spots = Spots(M)
    local function Far(letter) return tostring(S[spots[letter or "f"].far].alpha) end
    Where = { x = 100, y = 200, map = 1 }
    Cast(3599)
    Drop(1, "Searing Totem", 3599)
    Equal(Far() .. " " .. M.REACH["Searing Totem"] .. " " .. M.REACH["Magma Totem"], "0 20 8", "Searing down at your feet: not red")
    Where.x = 119
    Pass(M.LOOK_EVERY)
    Equal(Far(), "0", "19 yards away: still in reach")
    Where.x, Where.y = 115, 215
    Pass(M.LOOK_EVERY)
    Equal(Far() .. " " .. tostring(S[spots.f.warn].alpha), "1 0", "21 yards away, on a slant: red (its own red, not the buff one)")
    Where.x, Where.y = 105, 205
    Pass(M.LOOK_EVERY)
    Equal(Far(), "0", "back in reach: the red goes")
    Equal(tostring(ns.DebugReport():find("Fire Searing Totem (seen), now true, red 0, far 0 (Searing Totem, 20 yd)", 1, true) ~= nil),
        "true", "/ccm debug says so")
    -- A fight: every totem answer secret, your cast still says it's Searing, put down where you are now.
    lockdown, TotemsSecret = true, true
    Fire("PLAYER_REGEN_DISABLED")
    Cast(3599)
    Drop(1, "Searing Totem", 3599)
    Where.x = 130
    Pass(M.LOOK_EVERY)
    Equal(Far(), "1", "in a fight, 25 yards from the new one: red")
    Where = SECRET
    Pass(M.LOOK_EVERY)
    Equal(Far(), "0", "where you are kept secret: no red, rather than a wrong one")
    Where = { x = 130, y = 205, map = 1 }
    Pass(M.LOOK_EVERY)
    Equal(Far(), "1", "said again: red again")
    Where.map = 2
    Pass(M.LOOK_EVERY)
    Equal(Far(), "0", "another map: no red")
    Where.map = 1
    lockdown, TotemsSecret = false, false
    Fire("PLAYER_REGEN_ENABLED")
    Pass(M.LOOK_EVERY)
    Equal(Far(), "1", "the fight over: read again, still red")
    -- Unticked: no red, and no more looking.
    ns.Set("totemRange", false)
    M:Apply()
    local asks = WhereAsks
    Pass(1)
    Equal(Far() .. " " .. (WhereAsks - asks), "0 0", "Red when out of range unticked: no red, where you are no longer looked at")
    ns.Set("totemRange", true)
    M:Apply()
    Pass(M.LOOK_EVERY)
    Equal(Far(), "1", "ticked again: red again at once")
    -- Another fire totem in its place: never red that way, and the looking stops.
    Cast(8227)
    Drop(1, "Flametongue Totem", 8227)
    Pass(M.LOOK_EVERY)
    asks = WhereAsks
    Pass(1)
    Equal(Far() .. " " .. (WhereAsks - asks), "0 0", "Flametongue in Searing's place: no far red, nothing looked at")
    -- Magma reaches 8 yards.
    Cast(8190)
    Drop(1, "Magma Totem", 8190)
    Where.x = 137
    Pass(M.LOOK_EVERY)
    Equal(Far(), "0", "7 yards from Magma: in reach")
    Where.x = 139
    Pass(M.LOOK_EVERY)
    Equal(Far(), "1", "9 yards from Magma: red")
    -- Gone (its time up, out of a fight): no red, no looking.
    Drop(1, nil)
    asks = WhereAsks
    Pass(1)
    Equal(Far() .. " " .. (WhereAsks - asks), "0 0", "Magma gone: no red, nothing looked at")
    -- Cast where the game won't say where you are (a dungeon): never red.
    Where = nil
    Cast(3599)
    Drop(1, "Searing Totem", 3599)
    Where = { x = 500, y = 500, map = 1 }
    Pass(1)
    Equal(Far(), "0", "put down in a dungeon: never red, even once where you are is known")
    -- A reload with Searing already down: its spot never seen, never red.
    local ns2, M2 = Fresh({ useBars = true, totemBar = true, totemRange = true }, nil, function()
        TOTEM[1] = { name = "Searing Totem", id = 3599, icon = 7003599 }
    end)
    Where = { x = 0, y = 0, map = 1 }
    Pass(1)
    Where.x = 300
    Pass(1)
    Equal(tostring(S[Spots(M2).f.far].alpha) .. " " .. S[Spots(M2).f.label].text, "0 Searing", "after a reload: Searing shown, never red")
    -- Buffing totems still go by their buff, never by distance.
    Equal(tostring(M2.REACH["Strength of Earth Totem"]), "nil", "Strength of Earth has no reach of its own")
    Equal(#printed, 0, "no errors")
end)()

Equal(#printed, 0, "no errors")

print = _G.print
Equal(SecretMisuse[1], nil, "no secret misused anywhere")
io.write("Totems checks passed: " .. checks .. " assertions.\n")
