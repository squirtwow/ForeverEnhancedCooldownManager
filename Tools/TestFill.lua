-- Run the actual addon files against a mock game for the Resource fill: a
-- spell you can't pay for going dark and filling up from the bottom with
-- the power it needs, its five looks, the shared OnUpdate that draws the
-- waves (and stops when nothing moves), what your spells cost asked only
-- when the game says it changed, a change of form switching the power and
-- its colour, every answer the game may keep to itself, and its page under
-- More in /ccm.
-- Your power comes back secret here, as it does on this client in a fight
-- and out of one, so the fill is proved the way it works in game: the cost
-- and the power go to a status bar of the fill's own and the game works out
-- how far up it stands, which the mock game does too (it may look behind a
-- secret; the addon may not). Any sum or comparison with your power inside
-- addon code is noted and fails the next check, so a division put back into
-- Fill.lua fails this file at its first assertion. The mock game is a copy of
-- Tools/TestBars.lua's: Tools/TestMockSync.mjs checks the two match, and
-- with --write copies it across.
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

-- Resource fill: the game around it ----------------------------------------------------------
-- Stand-ins for what the window's other pages need (as Tools/TestPulse.lua),
-- your power and what each spell costs (the game can keep both from you),
-- the colours the game holds for each power, and your form.

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

local function BlizzardFrames()
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
end

-- The whole fill game, set up after the mock game's Environment(). Your power
-- comes back secret, as it does on this client in a fight and out of one
-- (seen in game, 26 Nov 2026), with the number behind it for the game's own
-- sums alone (SecretNumber: a status bar's fill). Globals (the main chunk is
-- near Lua's 200 locals): Power[kind] (what you have of each power),
-- PowerOpen (a client that answers plainly instead), PowerRefuse (every ask
-- errors, as a game that won't answer at all), PowerReads (each UnitPower
-- asked), PowerKind (the power your form uses), Costs[spellID] ({ type,
-- cost }, nothing for a free spell), CostReads, CostRefuse (every ask
-- errors), CostSecret (the amount comes back secret) and CostBad (the answer
-- isn't a list).
local function FillGame()
    Power, PowerOpen, PowerRefuse, PowerReads, PowerKind = {}, false, false, 0, 0
    Costs, CostReads, CostRefuse, CostSecret, CostBad = {}, 0, false, false, false
    _G.Enum.PowerType = { Mana = 0, Rage = 1, Focus = 2, Energy = 3 }
    _G.UnitPower = function(unit, kind)
        assert(unit == "player", "your own power")
        assert(type(kind) == "number", "a power type")
        PowerReads = PowerReads + 1
        if PowerRefuse then error("the game refused") end
        local value = Power[kind] or 0
        if PowerOpen then return value end
        return SecretNumber(value)
    end
    _G.UnitPowerMax = function(unit, kind)
        assert(unit == "player" and type(kind) == "number")
        return 100
    end
    _G.UnitPowerType = function(unit)
        assert(unit == "player")
        local tokens = { [0] = "MANA", [1] = "RAGE", [2] = "FOCUS", [3] = "ENERGY" }
        return PowerKind, tokens[PowerKind] or "MANA"
    end
    -- The game's own colours for each power, as Blizzard's bars read them.
    _G.PowerBarColor = { MANA = { r = 0, g = 0, b = 1 }, RAGE = { r = 1, g = 0, b = 0 },
        ENERGY = { r = 1, g = 1, b = 0 }, FOCUS = { r = 1, g = .5, b = .25 } }
    _G.C_Spell.GetSpellPowerCost = function(id)
        assert(type(id) == "number", "a spell ID")
        CostReads = CostReads + 1
        if CostRefuse then error("the game refused") end
        if CostBad then return "not a list" end
        local cost = Costs[id]
        if not cost then return {} end
        return { { type = cost.type, cost = CostSecret and SECRETS.number or cost.cost, name = "POWER" } }
    end
    _G.PlaySound = function() end
    S[UIParent].width, S[UIParent].height = 1366, 768
end

-- Every file in the order the .toc loads them (Tools/TestRules.mjs checks
-- the .toc). The Totems bar needs a shaman's game of its own, so it's left
-- out here as it is in Tools/TestPulse.lua.
local FILES = { "Core.lua", "SquirtVersions.lua", "Style.lua", "Skin.lua", "Resource.lua", "CastBar.lua", "RaidTimers.lua", "Ranks.lua",
    "Forms.lua", "Spells.lua", "Keybinds.lua", "Buffs.lua", "IconAuras.lua", "Bars.lua", "Pulse.lua", "Fill.lua", "FillBars.lua",
    "Layout.lua",
    "Theme.lua", "BarPage.lua", "LayoutPage.lua", "CastBarPage.lua", "RaidTimersPage.lua", "PulsePage.lua", "FillPage.lua",
    "ProfileShare.lua", "ProfileMenu.lua", "Window.lua", "Tour.lua", "MinimapButton.lua", "Notes.lua", "Debug.lua" }

-- Your action bars, as the game makes them: Blizzard's main bar and its
-- first side bar, twelve buttons each, and the slots they hold (the mock
-- game's actionSlots). The main bar's buttons keep their slot in a field of
-- their own, the side bar's in an attribute, as both kinds do. The rest of
-- Blizzard's bars aren't there at all, so a name the game hasn't got is
-- skipped. Called with nothing, it takes the bars back out of the game, so
-- no test finds another's buttons left behind.
-- (Global: this file's main chunk is near Lua's 200 locals.)
function ActionBars(there)
    for i = 1, 120 do
        _G["ActionButton" .. i], _G["MultiBarBottomLeftButton" .. i], _G["BT4Button" .. i] = nil, nil, nil
    end
    _G.Dominos = nil
    if not there then return end
    for i = 1, 12 do
        local main = CreateFrame("Button", "ActionButton" .. i, UIParent)
        main:SetSize(36, 36)
        rawset(main, "action", i)
        local side = CreateFrame("Button", "MultiBarBottomLeftButton" .. i, UIParent)
        side:SetSize(36, 36)
        local slot = 60 + i
        rawset(side, "GetAttribute", function(_, what) if what == "action" then return slot end end)
    end
end

-- A fresh game with your bars on and three spells on the Cooldowns bar:
-- Moonfire (100 mana), Wrath (50 mana) and Attack (free). You have 40 mana,
-- so Moonfire's fill would stand at four tenths. With bars, your action bars
-- are there too, before the addon loads.
local function Fresh(saved, bars)
    Environment()
    BlizzardFrames()
    FillGame()
    ActionBars(bars)
    Costs[8924], Costs[5176] = { type = 0, cost = 100 }, { type = 0, cost = 50 }
    Power[0] = 40
    _G.FECMFrame, _G.FECMTour, _G.FECMNotes = nil, nil, nil
    local ns = {}
    _G.ForeverEnhancedCooldownManagerDB = saved or { notesSeen = "dev", helpSeen = true }
    for _, file in ipairs(FILES) do assert(loadfile(file))("ForeverEnhancedCooldownManager", ns) end
    -- Both pages are held out of the window for the release going out now,
    -- so the checks turn them on the way the addon itself will.
    ns.FILL_PAGE_READY, ns.DOTS_PAGE_READY = true, true
    Fire("ADDON_LOADED", "ForeverEnhancedCooldownManager")
    Fire("PLAYER_LOGIN")
    Fire("PLAYER_ENTERING_WORLD")
    for _, name in ipairs({ "Moonfire", "Wrath", "Attack" }) do ns.Bars:Assign(name, "cd") end
    ns.Set("useBars", true)
    ns.Bars:Rebuild()
    return ns, ns.Bars, ns.Fill
end

-- Whether you can pay for a spell, as the game answers it: nil for yes,
-- true for no, and SECRET for an answer it keeps to itself.
local function Short(id, answer)
    if answer == nil then
        usable[id], noMana[id] = nil, nil
    else
        usable[id], noMana[id] = false, answer
    end
end

-- Time passing on the shared OnUpdate, if it runs.
local function Tick(F, seconds)
    local frame = F.ticker
    local run = frame and S[frame].scripts.OnUpdate
    if run then run(frame, seconds or 1 / 30) end
end

-- How far up the game itself put one fill's gauge, as a share of the room it
-- has: the level the fill shows. The mock game works that out from the range
-- it was given and the value it was handed, looking behind the secret to do
-- it exactly as the game does; nothing of the addon's ever sees this number,
-- and the only reason the tests can is that they are the game here.
local function Level(parts)
    local span = S[parts.gauge].height
    if not span or span <= 0 then return "no room" end
    return ("%.2f"):format(S[parts.mark].height / span)
end

-- A fill in a line: whether anything of it shows, the level the game put it
-- at, and the wash's colour and how much of it shows over the spell's picture.
-- (How much of it shows is the layer's own opacity, since a gradient over the
-- same texture carries an opacity of its own at each end: the fill's colour
-- goes on solid and the strength on the layer, so the gradient can never
-- decide it.)
local function Line(parts)
    local shown = S[parts.wash].shown and "shown" or "hidden"
    local r, g, b = Last(parts.wash, "SetColorTexture", 1), Last(parts.wash, "SetColorTexture", 2),
        Last(parts.wash, "SetColorTexture", 3)
    return ("%s %s %s,%s,%s %s"):format(shown, Level(parts), tostring(r), tostring(g), tostring(b),
        tostring(S[parts.wash].alpha))
end

-- An icon's tint, in a word.
local function Tint(icon)
    local tint = S[icon.texture].tint or {}
    if tint[1] == 1 and tint[2] == 1 then return "white" end
    if tint[1] == .5 then return "blue" end
    if tint[1] == .4 then return "grey" end
    return "red"
end

local function Note(control)
    local hint = control.hint
    if type(hint) == "function" then hint = hint(control) end
    return hint
end

-- Off until it's ticked --------------------------------------------------------------------
-- Nothing of it is on an icon, nothing is heard, nothing runs frame by frame
-- and your power is never read. The icon turns blue as it always did.

;(function()
    local ns, B, F = Fresh()
    local cd = B:Get("cd")
    local moon = cd.icons[1]
    Equal(ns.Get("fill"), false, "off by default")
    Equal(tostring(moon.fill ~= nil) .. " " .. tostring(S[moon.fill.wash].shown) .. " " .. tostring(S[moon.fill.dark].shown),
        "true false false", "its layers and gauges are made with the icon, and nothing of it shows")
    Short(8924, true)
    B:RefreshAll()
    Equal(Tint(moon) .. " " .. tostring(moon.fill.on) .. " " .. PowerReads .. " " .. CostReads, "blue false 0 0",
        "short of mana with the fill off: the icon turns blue as before, no fill, and neither your power nor the cost is read")
    Equal(tostring(F:Running()) .. " " .. tostring(next(S[F.driver].events)), "false nil",
        "nothing runs frame by frame, and nothing is heard")
    Equal(#printed, 0, "no errors")
end)()

-- Ticked on -------------------------------------------------------------------------------
-- A spell you can't pay for fills to what you have over what it costs, in
-- the game's own colour for that power, and keeps its own colours instead of
-- turning blue. One that costs nothing has no fill and turns blue as before.
-- The sum is the game's: what the spell costs is handed over as the range of
-- the fill's own gauge, what you have as its value, secret and all, and how
-- far up it stands is then the game's answer, never the addon's.

;(function()
    local ns, B, F = Fresh()
    local cd = B:Get("cd")
    local moon, wrath, attack = cd.icons[1], cd.icons[2], cd.icons[3]
    Equal(moon.name .. " " .. wrath.name .. " " .. attack.name, "Moonfire Wrath Attack", "the three icons, in order")
    ns.Set("fill", true)
    F:Apply()
    Short(8924, true)
    Short(5176, true)
    Short(6603, true)
    B:RefreshAll()
    Equal(Line(moon.fill), "shown 0.40 0,0,1 0.35",
        "Moonfire: shown at four tenths, in the game's mana blue, washed over the spell at Fill strength")
    Equal(Line(wrath.fill), "shown 0.80 0,0,1 0.35", "Wrath costs half as much, so its fill stands twice as high")
    Equal(Tint(moon) .. " " .. Tint(wrath), "white white", "both keep their own colours: the fill takes the blue tint's place")
    Equal(tostring(attack.fill.on) .. " " .. tostring(S[attack.fill.wash].shown) .. " " .. Tint(attack), "false false blue",
        "Attack costs nothing, so it has no fill and turns blue as before")
    -- What went to the game: the cost as the range, your power as the value,
    -- exactly as it came.
    Equal(Last(moon.fill.gauge, "SetMinMaxValues", 1) .. " " .. Last(moon.fill.gauge, "SetMinMaxValues", 2) .. " "
        .. Last(moon.fill.gauge, "SetOrientation", 1), "0 100 VERTICAL",
        "its gauge measures nothing to what the spell costs, from the bottom up")
    Equal(Last(moon.fill.gauge, "SetValue", 1), SECRET, "and your power goes to it as it came, a secret the addon never reads")
    Equal(tostring(issecretvalue(Last(moon.fill.gauge, "SetValue", 1))), "true", "which is still secret where the game takes it")
    -- Over the top and right down to the bottom: the game holds it to its own
    -- range, since nothing here can compare it.
    Power[0] = 250
    Fire("UNIT_POWER_FREQUENT", "player", "MANA")
    Equal(Level(moon.fill) .. " " .. Level(wrath.fill), "1.00 1.00", "more power than it costs still fills to the top, no further")
    Power[0] = 0
    Fire("UNIT_POWER_FREQUENT", "player", "MANA")
    Equal(Level(moon.fill) .. " " .. tostring(S[moon.fill.wash].shown) .. " " .. tostring(S[moon.fill.darkTop].shown),
        "0.00 true true", "none at all: the game leaves the wash nothing to draw, and the spell stays darkened")
    Power[0] = 40
    Fire("UNIT_POWER_FREQUENT", "player", "MANA")
    Equal(Level(moon.fill), "0.40", "and back to four tenths")
    Equal(tostring(F:Costed(8924)) .. " " .. tostring(F:Costed(6603)), "true false",
        "Moonfire costs something this fills with; Attack costs nothing")
    Equal(#printed, 0, "no errors")
end)()

-- A client that answers plainly -------------------------------------------------------------
-- Where the game hands your power over as a plain number instead of a secret
-- (another client, or a unit it doesn't hide), the same gauge takes it and
-- the fill stands in the same place: one path, either way.

;(function()
    local ns, B, F = Fresh()
    local moon = B:Get("cd").icons[1]
    PowerOpen = true
    ns.Set("fill", true)
    F:Apply()
    Short(8924, true)
    B:RefreshAll()
    Equal(Line(moon.fill) .. " " .. tostring(Last(moon.fill.gauge, "SetValue", 1)), "shown 0.40 0,0,1 0.35 40",
        "a plain 40 of 100 stands exactly where the secret 40 did, and goes to the game the same way")
    Power[0] = 90
    Fire("UNIT_POWER_FREQUENT", "player", "MANA")
    Equal(Level(moon.fill), "0.90", "and follows your power as before")
    Equal(#printed, 0, "no errors")
end)()

-- The looks -------------------------------------------------------------------------------
-- Liquid washes the filled part in the power's colour with the spell still
-- showing through it, darkens only the part above the level, and lays one soft
-- wave with a glowing crest along the surface, bubbles rising under it. The
-- wave is one texture of ours read three times over, a band each, not a row of
-- rectangles. Flat is one block of colour with nothing moving: no wave at all,
-- no bubbles, and the shared OnUpdate stops.

;(function()
    local ns, B, F = Fresh()
    local moon = B:Get("cd").icons[1]
    local parts = moon.fill
    ns.Set("fill", true)
    F:Apply()
    Short(8924, true)
    B:RefreshAll()
    local running, count = F:Running()
    Equal(tostring(running) .. " " .. count, "true 1", "Liquid: the shared OnUpdate runs, for the one fill")
    Equal(tostring(S[parts.above].shown) .. " " .. tostring(S[parts.below].shown) .. " " .. tostring(S[parts.crest].shown)
        .. " " .. tostring(S[parts.flecks[1]].shown), "true true true true",
        "the surface's three bands and its bubbles all show")
    -- The wash takes no depth shade at all for now (27 Nov 2026): Squirt saw
    -- a hard straight line in game where the wash met the wave's filled side,
    -- which made the wave read as a decoration floating over the real level.
    -- Both carry the same colour and opacity and the gradient was the only
    -- thing that differed, so it came off. Both ends white leaves the wash
    -- the flat colour, which is exactly what the band's foot is. A shade
    -- here again is the join coming back, so it is pinned.
    local foot, head = Last(parts.wash, "SetGradient", 2), Last(parts.wash, "SetGradient", 3)
    Equal(tostring(Last(parts.wash, "SetGradient", 1)) .. " " .. ("%s,%s,%s"):format(foot.r, foot.g, foot.b)
        .. " " .. ("%s,%s,%s"):format(head.r, head.g, head.b), "VERTICAL 1,1,1 1,1,1",
        "the wash takes no depth shade, so it meets the wave's filled side in exactly the same colour")
    -- One texture, read at three heights, so the light above the curve, the
    -- colour below it and the glow on it are the same curve exactly.
    Equal(#parts.ribbon .. " " .. tostring(S[parts.above].texture == ns.MEDIA .. "Wave.tga")
        .. " " .. tostring(S[parts.below].texture == S[parts.crest].texture), "3 true true",
        "the surface is drawn from the one wave texture, three bands of it")
    -- Each band's quarter, pulled in by one row of the 256 at each end. A
    -- band read right up to .25 or .5 is filtered against its neighbour and
    -- takes some of it: the colour band sits next to the glow's, whose first
    -- rows fade to nothing on purpose, so reading to the edge faded its own
    -- bottom out and the fill stopped short of the surface in a hard line
    -- (seen in game 27 Nov 2026). The inset is what keeps the colour running
    -- all the way up to the wave, so it is pinned exactly.
    Equal(("%s %s | %s %s | %s %s"):format(Last(parts.above, "SetTexCoord", 3), Last(parts.above, "SetTexCoord", 4),
        Last(parts.below, "SetTexCoord", 3), Last(parts.below, "SetTexCoord", 4),
        Last(parts.crest, "SetTexCoord", 3), Last(parts.crest, "SetTexCoord", 4)),
        "0.00390625 0.24609375 | 0.25390625 0.49609375 | 0.50390625 0.74609375",
        "each band reads its own quarter of it, a row in from each edge so no band can bleed into the next")
    Equal(("%.3f"):format(Last(parts.crest, "SetTexCoord", 2) - Last(parts.crest, "SetTexCoord", 1)), "0.625",
        "and a bit over one of the texture's two waves shows across the icon, which is what reads as liquid")
    local off = Last(parts.above, "SetTexCoord", 1)
    Equal(tostring(Last(parts.below, "SetTexCoord", 1) == off) .. " " .. tostring(Last(parts.crest, "SetTexCoord", 1) == off),
        "true true", "all three sit at the same place in the wave, so they read as one surface")
    -- The wave stands on the level and rises above it, so the gauge the game
    -- measures stops as far short of the top as the band is tall: a crest on a
    -- full fill reaches the icon's top edge and never goes over it.
    local room = S[parts.gauge].height
    Equal(tostring(room < parts.height) .. " " .. tostring(math.abs(room + parts.ribbonH - parts.height) < .001), "true true",
        "the gauge leaves the wave exactly its own room at the top")
    Equal(S[parts.above].height .. " " .. parts.ribbonH, parts.ribbonH .. " " .. parts.ribbonH,
        "and the band is exactly as tall as the room it left")
    -- Every layer is anchored once and only to the level, which is the top
    -- edge of the gauge's own fill texture: nothing is ever worked out from
    -- how far up that edge is.
    local pins = S[parts.above].points
    Equal(#pins .. " " .. pins[1][1] .. " " .. pins[1][3] .. " " .. pins[2][1] .. " " .. pins[2][3]
        .. " " .. tostring(pins[1][2] == parts.mark and pins[2][2] == parts.mark),
        "2 BOTTOMLEFT TOPLEFT BOTTOMRIGHT TOPRIGHT true",
        "the band's own rect stands on that edge, pinned to it and to nothing else")
    local washPins, darkPins = S[parts.wash].points, S[parts.darkTop].points
    Equal(washPins[1][1] .. " " .. washPins[1][3] .. " " .. tostring(washPins[1][2] == parts.mark)
        .. " " .. washPins[3][1] .. " " .. tostring(washPins[3][2] == parts.holder),
        "TOPLEFT TOPLEFT true BOTTOMLEFT true", "the wash runs from the level down to the bottom of the icon")
    Equal(darkPins[1][1] .. " " .. tostring(darkPins[1][2] == parts.holder) .. " " .. darkPins[3][1]
        .. " " .. darkPins[3][3] .. " " .. tostring(darkPins[3][2] == parts.above),
        "TOPLEFT true BOTTOMLEFT TOPLEFT true", "and the darkening from the icon's top down to the top of the band")
    -- Each bubble rides a gauge of its own, so the game puts it at its share
    -- of the fill and it can never rise out of it.
    Equal(#parts.gauges .. " " .. tostring(S[parts.flecks[1]].points[1][2] == parts.fleckMarks[1]), "6 true",
        "one gauge for the fill and one for each of the five bubbles, each bubble standing on its own")
    local highest = 0
    for i = 1, #parts.fleckMarks do highest = math.max(highest, S[parts.fleckMarks[i]].height) end
    Equal(tostring(highest <= S[parts.mark].height) .. " " .. tostring(Last(parts.gauges[2], "SetMinMaxValues", 2)), "true 100",
        "no bubble's gauge stands higher than the fill itself, and every gauge takes the same cost and power")
    -- Mixed sizes, so they read as bubbles instead of a row of dots.
    local sizes = {}
    for i = 1, #parts.flecks do sizes[tostring(S[parts.flecks[i]].width)] = true end
    local kinds = 0
    for _ in pairs(sizes) do kinds = kinds + 1 end
    Equal(tostring(kinds > 1), "true", "and they are not all the same size")
    -- Bubbles unticked.
    ns.Set("fillBubbles", false)
    F:Apply()
    Equal(tostring(S[parts.flecks[1]].shown), "false", "Bubbles unticked: none of them shows")
    ns.Set("fillBubbles", true)
    -- Flat.
    ns.Set("fillStyle", "flat")
    F:Apply()
    running, count = F:Running()
    Equal(tostring(running) .. " " .. count, "false 0", "Flat: nothing moves, so the shared OnUpdate stops")
    Equal(tostring(S[parts.above].shown) .. " " .. tostring(S[parts.below].shown) .. " " .. tostring(S[parts.crest].shown)
        .. " " .. tostring(S[parts.darkTop].shown) .. " " .. tostring(S[parts.flecks[1]].shown)
        .. " " .. tostring(S[parts.wash].shown), "false false false false false true",
        "no wave at all, nothing of its darkening and no bubbles: one block of colour")
    Equal(tostring(S[parts.dark].shown) .. " " .. tostring(Last(parts.dark, "SetColorTexture", 4)), "true 0.45",
        "and the whole icon darkened under it, since Flat has no surface to darken down to")
    Equal(S[parts.gauge].height .. " " .. parts.height, parts.height .. " " .. parts.height,
        "and with no wave to make room for, Flat fills the whole icon")
    local flatFoot = Last(parts.wash, "SetGradient", 2)
    Equal(("%s,%s,%s"):format(flatFoot.r, flatFoot.g, flatFoot.b), "1,1,1",
        "and nothing shades it either: one clean block of the power's own colour, top to bottom")
    -- Each of the other three draws its own way and keeps moving, and the two
    -- quieter ones wear the same wave shorter.
    local tall = {}
    for _, look in ipairs({ "frost", "ember", "arcane" }) do
        ns.Set("fillStyle", look)
        F:Apply()
        running = F:Running()
        Equal(tostring(running) .. " " .. tostring(S[parts.wash].shown) .. " " .. Level(parts), "true true 0.40",
            look .. " moves and fills to four tenths")
        tall[look] = parts.ribbonH
    end
    -- Arcane's slow glow is the whole fill's opacity lifting and falling,
    -- not a shade down its foot (27 Nov 2026, so the join cannot show). The
    -- wash and the wave's filled side are handed the same number, so they
    -- must still match exactly at every point of the breath.
    local deep = parts.wash:GetAlpha()
    for _ = 1, 20 do Tick(F, 1 / 30) end
    local lifted = parts.wash:GetAlpha()
    Equal(tostring(lifted ~= deep) .. " " .. tostring(lifted > 0 and lifted <= 1)
        .. " " .. tostring(lifted == parts.below:GetAlpha()), "true true true",
        "Arcane's glow breathes the whole fill, and the wave's filled side breathes with it exactly")
    ns.Set("fillStyle", "liquid")
    F:Apply()
    Equal(tostring(tall.frost == parts.ribbonH) .. " " .. tostring(tall.ember < parts.ribbonH)
        .. " " .. tostring(tall.ember == tall.arcane), "true true true",
        "Frost's wave stands as tall as Liquid's, and Ember's and Arcane's are the quieter, shorter one")
    Equal(#printed, 0, "no errors")
end)()

-- The surface rolls, and nothing else moves -------------------------------------------------
-- The only thing the shared OnUpdate changes about the surface is how far
-- along the wave texture its three bands are read from: they always stay
-- together, that place in the texture is wrapped so it never grows without
-- bound, the band itself is never moved or resized, Frost's stands still, and
-- Bright line on the surface takes the crest off and leaves the rest.

;(function()
    local ns, B, F = Fresh()
    local parts = B:Get("cd").icons[1].fill
    ns.Set("fill", true)
    F:Apply()
    Short(8924, true)
    B:RefreshAll()
    local function Off() return Last(parts.above, "SetTexCoord", 1) end
    local first, pins, tallness = Off(), #S[parts.above].points, S[parts.above].height
    for _ = 1, 10 do Tick(F, 1 / 30) end
    local later = Off()
    Equal(tostring(later ~= first) .. " " .. tostring(later >= 0 and later < 1), "true true",
        "the wave rolls along the texture as time passes, and its place in it stays inside the texture")
    Equal(tostring(Last(parts.below, "SetTexCoord", 1) == later) .. " " .. tostring(Last(parts.crest, "SetTexCoord", 1) == later),
        "true true", "with all three bands still at the same place in it")
    Equal(#S[parts.above].points .. " " .. S[parts.above].height, pins .. " " .. tallness,
        "and the band is never moved or resized while it rolls: only its texture coordinates change")
    -- An hour of it, so the place in the texture is proved wrapped.
    for _ = 1, 200 do Tick(F, 18) end
    Equal(tostring(Off() >= 0 and Off() < 1), "true", "an hour of rolling leaves it still inside the texture")
    -- Frost holds its place in the wave.
    ns.Set("fillStyle", "frost")
    F:Apply()
    local frozen = Off()
    for _ = 1, 10 do Tick(F, 1 / 30) end
    Equal(tostring(Off() == frozen) .. " " .. tostring(S[parts.crest].shown), "true true",
        "Frost holds its place in the wave, so the ice stands still with its own edge lit")
    -- Bright line on the surface unticked.
    ns.Set("fillStyle", "liquid")
    ns.Set("fillLine", false)
    F:Apply()
    Equal(tostring(S[parts.crest].shown) .. " " .. tostring(S[parts.above].shown) .. " " .. tostring(S[parts.below].shown),
        "false true true", "Bright line on the surface unticked: the crest goes and the surface stays")
    -- The wave texture is set to tile across, which is the only reason a
    -- band's texture coordinates can run on past its right edge as it rolls
    -- instead of smearing the last pixel along.
    local was, wraps = Proto.SetTexture, {}
    Proto.SetTexture = function(self, file, across, down)
        was(self, file)
        if across then wraps[self] = tostring(across) .. " " .. tostring(down) end
    end
    local sample = F:Sample(UIParent, 40)
    Proto.SetTexture = was
    Equal(tostring(wraps[sample.fill.above]) .. " | " .. tostring(wraps[sample.fill.below]) .. " | "
        .. tostring(wraps[sample.fill.crest]) .. " | " .. tostring(wraps[sample.fill.wash]),
        "REPEAT CLAMP | REPEAT CLAMP | REPEAT CLAMP | nil",
        "each band tiles across the icon and keeps to its own quarter down it, and the plain layers tile nothing")
    Equal(#printed, 0, "no errors")
end)()

-- The spell shows through the fill ----------------------------------------------------------
-- The whole point of the wash: the spell's own picture is never painted over,
-- whatever Fill strength is set to, and only the part above the level is
-- darkened. Both sliders still do what their labels say.

;(function()
    local ns, B, F = Fresh()
    local parts = B:Get("cd").icons[1].fill
    ns.Set("fill", true)
    F:Apply()
    Short(8924, true)
    B:RefreshAll()
    local function Wash() return S[parts.wash].alpha end
    Equal(tostring(Wash()), "0.35", "at the Fill strength it starts on, the wash is about a third over the spell's picture")
    -- The strength is the layer's own opacity, which is the last word on what
    -- the game draws, and the fill's colour goes on solid under it: a gradient
    -- is laid over that same texture (Liquid's depth, Arcane's glow) carrying
    -- a colour of its own at each end, and if the game took its opacity from
    -- there instead the wash would go solid at every setting and the spell's
    -- picture would be painted over, which is the one thing this must not do.
    Equal(tostring(Last(parts.wash, "SetColorTexture", 4)) .. " " .. tostring(Last(parts.wash, "SetGradient", 1)),
        "1 VERTICAL", "and it is the layer's own, so the gradient over it can never decide how much shows")
    ns.Set("fillStrength", 100)
    F:Apply()
    Equal(tostring(Wash()), "0.5", "turned right up it is half, and never more: the picture still shows through")
    ns.Set("fillStrength", 20)
    F:Apply()
    Equal(tostring(Wash()), "0.1", "and turned right down it is barely there")
    ns.Set("fillStrength", 70)
    F:Apply()
    -- The wave's own filled side is the same colour and strength as the wash
    -- under it, so the two read as one body of liquid.
    local tint, head = S[parts.below].tint or {}, Last(parts.wash, "SetGradient", 3)
    Equal(tostring(S[parts.below].alpha) .. " " .. tostring(Wash()) .. " " .. ("%s,%s,%s"):format(tint[1], tint[2], tint[3])
        .. " " .. ("%s,%s,%s"):format(Last(parts.wash, "SetColorTexture", 1), Last(parts.wash, "SetColorTexture", 2),
            Last(parts.wash, "SetColorTexture", 3)) .. " " .. ("%s,%s,%s"):format(head.r, head.g, head.b),
        "0.35 0.35 0,0,1 0,0,1 1,1,1",
        "the wave's filled side matches the wash exactly, both the power's own colour with nothing shading either of"
        .. " them at the level they meet, so no join shows")
    -- Darkness, and only above the level.
    ns.Set("fillDarkness", 80)
    F:Apply()
    Equal(tostring(Last(parts.darkTop, "SetColorTexture", 4)) .. " " .. tostring(S[parts.above].alpha)
        .. " " .. tostring(S[parts.dark].shown), "0.8 0.8 false",
        "Darkness turned up darkens the part above the level and the wave's dark side with it, and nothing under it")
    ns.Set("fillDarkness", 0)
    F:Apply()
    Equal(tostring(S[parts.darkTop].shown) .. " " .. tostring(S[parts.above].shown) .. " " .. tostring(S[parts.wash].shown),
        "false false true", "and at nothing the picture is left alone, with the fill alone over it")
    Equal(#printed, 0, "no errors")
end)()

-- Nothing runs while nothing moves ---------------------------------------------------------
-- Flat never runs frame by frame, and neither does a fill on bars you can't
-- see: the shared OnUpdate stops and starts again with them. A fill sitting
-- empty or full keeps rolling, since how far up it stands is the game's own
-- and can't be read here to stop it.

;(function()
    local ns, B, F = Fresh()
    local cd = B:Get("cd")
    local parts = cd.icons[1].fill
    ns.Set("fill", true)
    F:Apply()
    Short(8924, true)
    B:RefreshAll()
    Equal(tostring(F:Running()), "true", "filling and in sight: it runs")
    Power[0] = 0
    Fire("UNIT_POWER_FREQUENT", "player", "MANA")
    Equal(Level(parts) .. " " .. tostring(F:Running()), "0.00 true", "empty: it keeps rolling, since nothing here knows it is empty")
    Power[0] = 40
    Fire("UNIT_POWER_FREQUENT", "player", "MANA")
    Equal(Level(parts) .. " " .. tostring(F:Running()), "0.40 true", "part way up: it runs")
    cd:Hide()
    Equal(tostring(F:Running()), "false", "the bar hidden: it stops")
    cd:Show()
    Equal(tostring(F:Running()), "true", "and shown again: it picks up where it was")
    -- Time passing draws it, and the clock never asks for your power.
    local reads = PowerReads
    for _ = 1, 4 do Tick(F, 1 / 30) end
    Equal(PowerReads .. " " .. tostring(S[parts.below].shown), reads .. " true",
        "the waves are drawn without asking for your power again")
    Equal(#printed, 0, "no errors")
end)()

-- The same answer twice draws nothing -------------------------------------------------------
-- The game says whether you can pay several times a second in a fight: while
-- its answer and the cost are the same as last time, nothing is set again,
-- your power included. It goes to the gauges only as the game says it changed.

;(function()
    local ns, B, F = Fresh()
    local parts = B:Get("cd").icons[1].fill
    ns.Set("fillStyle", "flat") -- nothing moving, so only a change draws
    ns.Set("fill", true)
    F:Apply()
    Short(8924, true)
    B:RefreshAll()
    local draws, handed = 0, 0
    rawset(parts.wash, "SetColorTexture", function(self, ...)
        draws = draws + 1
        S[self].last.SetColorTexture = table.pack(...)
    end)
    for _, gauge in ipairs(parts.gauges) do
        local set = Proto.SetValue
        rawset(gauge, "SetValue", function(self, ...)
            handed = handed + 1
            set(self, ...)
        end)
    end
    B:RefreshAll()
    B:RefreshAll()
    Equal(draws .. " " .. handed, "0 0", "the game saying the same again draws nothing and hands nothing over")
    Power[0] = 70
    Fire("UNIT_POWER_FREQUENT", "player", "MANA")
    Equal(draws .. " " .. handed .. " " .. Level(parts), "0 6 0.70",
        "your power changing hands it to the six gauges and nothing else: the game moves the fill itself")
    Equal(#printed, 0, "no errors")
end)()

-- A spot that shows another spell now -------------------------------------------------------
-- The bar laid out again with a different spell in a spot: that fill goes,
-- and takes the new spell's own cost.

;(function()
    local ns, B, F = Fresh()
    local cd = B:Get("cd")
    local parts = cd.icons[1].fill
    ns.Set("fill", true)
    F:Apply()
    Short(8924, true)
    Short(5176, true)
    B:RefreshAll()
    Equal(tostring(parts.spell) .. " " .. Line(parts), "8924 shown 0.40 0,0,1 0.35", "Moonfire's fill in the first spot")
    B:Remove("cd", 1) -- Moonfire off the bar, so Wrath moves up into that spot
    B:Rebuild()
    Equal(cd.icons[1].name .. " " .. tostring(parts.spell) .. " " .. Line(parts), "Wrath 5176 shown 0.80 0,0,1 0.35",
        "laid out again: the spot fills to Wrath's own cost, not the spell that was there")
    Equal(Last(parts.gauge, "SetMinMaxValues", 2), 50, "its gauge measures against the new cost")
    Equal(#printed, 0, "no errors")
end)()

-- Your form -------------------------------------------------------------------------------
-- A druid's spells cost what the form casting them costs, so a change of form
-- has every cost asked again: the icon fills with the new power, in that
-- power's colour.

;(function()
    local ns, B, F = Fresh()
    local parts = B:Get("cd").icons[1].fill
    ns.Set("fill", true)
    F:Apply()
    Short(8924, true)
    B:RefreshAll()
    Equal(parts.power.key .. " " .. Line(parts), "mana shown 0.40 0,0,1 0.35", "out of form: mana, in the game's mana blue")
    -- Cat form: energy, and Moonfire's cost with it.
    PowerKind = 3
    Power[3] = 25
    Costs[8924] = { type = 3, cost = 50 }
    Fire("UNIT_DISPLAYPOWER", "player")
    B:RefreshAll()
    Equal(parts.power.key .. " " .. Line(parts), "energy shown 0.50 1,1,0 0.35",
        "in form: energy, half way up, in the game's energy yellow")
    -- A colour of your own for one power, and back to the game's.
    ns.Set("fillEnergy", "green")
    F:Apply()
    local green = ns.Style:BarColour("green")
    Equal(("%s,%s,%s"):format(Last(parts.wash, "SetColorTexture", 1), Last(parts.wash, "SetColorTexture", 2),
        Last(parts.wash, "SetColorTexture", 3)), ("%s,%s,%s"):format(green[1], green[2], green[3]),
        "a colour of your own for energy, and the fill takes it")
    Equal(("%s,%s,%s"):format(F:Own(ns.FILL_POWERS[3])[1], F:Own(ns.FILL_POWERS[3])[2], F:Own(ns.FILL_POWERS[3])[3]), "1,1,0",
        "while the game's own energy colour is still what Default stands for")
    ns.Set("fillEnergy", "default")
    F:Apply()
    Equal(Line(parts), "shown 0.50 1,1,0 0.35", "back to the game's own")
    Equal(#printed, 0, "no errors")
end)()

-- Answers the game keeps to itself ----------------------------------------------------------
-- A power the game won't answer for at all, a secret cost, a cost it refuses
-- or answers oddly, and a game without the question: no fill, no error, and
-- nothing compared or counted. One secret answer about whether you can pay
-- leaves the fill as it was. (Your power itself is always a secret here, as
-- it is on this client, and the fill lives on it: every check in this file
-- fails if anything of the addon's ever does a sum with it.)

;(function()
    local ns, B, F = Fresh()
    local cd = B:Get("cd")
    local moon, wrath = cd.icons[1], cd.icons[2]
    ns.Set("fill", true)
    F:Apply()
    Short(8924, true)
    B:RefreshAll()
    Equal(Line(moon.fill), "shown 0.40 0,0,1 0.35", "filling to start with")
    -- The game refusing the question outright: the last answer stands.
    PowerRefuse = true
    Power[0] = 90
    Fire("UNIT_POWER_FREQUENT", "player", "MANA")
    Equal(Line(moon.fill), "shown 0.40 0,0,1 0.35", "your power refused: the fill stays where it was")
    PowerRefuse = false
    Fire("UNIT_POWER_FREQUENT", "player", "MANA")
    Equal(Level(moon.fill), "0.90", "and it follows again as soon as the game answers")
    -- Whether you can pay kept from you: the fill stays as it is.
    Short(8924, SECRET)
    B:RefreshAll()
    Equal(Line(moon.fill) .. " " .. Tint(moon), "shown 0.90 0,0,1 0.35 grey",
        "whether you can pay kept from you: the fill stays as it was")
    Short(8924, true)
    B:RefreshAll()
    -- A secret cost, a refusal, an answer that isn't a list, and no question
    -- at all: no fill either way, and the icon turns blue as before.
    Short(5176, true)
    for _, how in ipairs({ "secret", "refuse", "bad", "missing" }) do
        CostSecret, CostRefuse, CostBad = how == "secret", how == "refuse", how == "bad"
        if how == "missing" then C_Spell.GetSpellPowerCost = nil end
        Fire("UNIT_DISPLAYPOWER", "player") -- every cost asked again
        B:RefreshAll()
        Equal(tostring(wrath.fill.on) .. " " .. tostring(S[wrath.fill.wash].shown) .. " " .. Tint(wrath), "false false blue",
            "a cost the game answers with " .. how .. ": no fill, and the icon turns blue as before")
    end
    Equal(#printed, 0, "no errors")
end)()

-- A refused cost read isn't remembered -------------------------------------------------------
-- A refusal is not an answer, so it isn't kept: the next look at that spell
-- asks again, with no change of form in between (nothing else asks every cost
-- again). Otherwise the game being short of a spell's data for a moment at a
-- loading screen, which is when your action bars are first read, would leave
-- that spell unable to fill for the rest of the session. A spell that really
-- costs nothing this fills with does answer, with a list holding nothing of
-- ours, so that one is still asked once and never again.

;(function()
    local ns, B, F = Fresh()
    local cd = B:Get("cd")
    local moon, attack = cd.icons[1], cd.icons[3]
    ns.Set("fill", true)
    F:Apply()
    Short(8924, true)
    CostRefuse = true
    B:RefreshAll()
    Equal(tostring(moon.fill.on) .. " " .. Tint(moon), "false blue",
        "the game refusing what a spell costs: no fill, and the icon turns blue as before")
    CostRefuse = false
    B:RefreshAll()
    Equal(Line(moon.fill), "shown 0.40 0,0,1 0.35",
        "and the very next look asks again, with no change of form: it fills")
    -- Attack costs nothing: an answer of none, kept like any other.
    Short(6603, true)
    B:RefreshAll()
    local asked = CostReads
    B:RefreshAll()
    B:RefreshAll()
    Equal(tostring(attack.fill.on) .. " " .. (CostReads - asked), "false 0",
        "a spell that costs nothing gets no fill, and is never asked about again")
    Equal(#printed, 0, "no errors")
end)()

-- A power the game never answers at all -----------------------------------------------------
-- Nothing to hand the gauge, so nothing is handed over and no fill shows: the
-- icon turns blue as it always did, and the fill arrives the moment the game
-- does answer.

;(function()
    local ns, B, F = Fresh()
    local moon = B:Get("cd").icons[1]
    PowerRefuse = true
    ns.Set("fill", true)
    F:Apply()
    Short(8924, true)
    B:RefreshAll()
    Equal(tostring(moon.fill.on) .. " " .. tostring(S[moon.fill.wash].shown) .. " " .. Tint(moon)
        .. " " .. tostring(Last(moon.fill.gauge, "SetValue", 1)), "false false blue 0",
        "your power refused from the start: no fill, the icon blue, and nothing but its own nothing on the gauge")
    PowerRefuse = false
    Fire("UNIT_POWER_FREQUENT", "player", "MANA")
    B:RefreshAll()
    Equal(Line(moon.fill), "shown 0.40 0,0,1 0.35", "and it fills as soon as the game answers")
    Equal(#printed, 0, "no errors")
end)()

-- The flash, the darkening and the cost ----------------------------------------------------
-- One flash the moment you can pay, the spell darkened while you can't, and
-- what it costs on the icon when that's ticked.

;(function()
    local ns, B, F = Fresh()
    local parts = B:Get("cd").icons[1].fill
    ns.Set("fill", true)
    F:Apply()
    Short(8924, true)
    B:RefreshAll()
    Equal(tostring(S[parts.darkTop].shown) .. " " .. tostring(Last(parts.darkTop, "SetColorTexture", 4))
        .. " " .. tostring(S[parts.dark].shown), "true 0.45 false",
        "the spell darkens above the level while you can't pay for it, and is left alone under it")
    Equal(tostring(S[parts.cost].shown), "false", "what it costs is off until it's ticked")
    ns.Set("fillCost", true)
    F:Apply()
    Equal(tostring(S[parts.cost].shown) .. " " .. tostring(S[parts.cost].text), "true 100", "ticked: its cost sits on the icon")
    ns.Set("fillDim", false)
    F:Apply()
    Equal(tostring(S[parts.darkTop].shown) .. " " .. tostring(S[parts.above].shown) .. " " .. tostring(S[parts.dark].shown),
        "false false false", "Darken the spell unticked: no part of the picture is darkened")
    -- You can pay for it now.
    Short(8924, nil)
    B:RefreshAll()
    Equal(tostring(S[parts.wash].shown) .. " " .. tostring(S[parts.flash].shown) .. " " .. S[parts.fade].plays, "false true 1",
        "you can pay: the fill goes and the icon flashes once, which the game fades out itself")
    -- And with the flash unticked.
    Short(8924, true)
    B:RefreshAll()
    ns.Set("fillFlash", false)
    S[parts.flash].shown, S[parts.fade].plays = false, 0
    Short(8924, nil)
    B:RefreshAll()
    Equal(tostring(S[parts.wash].shown) .. " " .. tostring(S[parts.flash].shown) .. " " .. S[parts.fade].plays, "false false 0",
        "the flash unticked: the fill just goes")
    Equal(#printed, 0, "no errors")
end)()

-- Out of reach, and short ------------------------------------------------------------------
-- Whether you can pay for a spell is the game's own answer, not the tint the
-- icon ended up with: a target out of reach turns the icon red, and a spell
-- you still can't pay for keeps filling under it instead of going with a
-- flash as though you could pay.

;(function()
    local ns, B, F = Fresh()
    local moon = B:Get("cd").icons[1]
    ns.Set("fill", true)
    F:Apply()
    Short(8924, true)
    B:RefreshAll()
    Equal(Line(moon.fill) .. " " .. Tint(moon), "shown 0.40 0,0,1 0.35 white",
        "short of mana and in reach: filling, with its own colours")
    -- A target it can't reach, with the mana still short.
    target = true
    range[8924] = false
    B:RefreshAll()
    Equal(Line(moon.fill) .. " " .. Tint(moon) .. " " .. tostring(S[moon.fill.flash].shown),
        "shown 0.40 0,0,1 0.35 red false",
        "out of reach and still short: the icon turns red, the fill stays where it was, and nothing flashes")
    -- Back in reach, then paid for.
    range[8924] = nil
    B:RefreshAll()
    Equal(Tint(moon), "white", "in reach again: the fill takes the blue tint's place as before")
    Short(8924, nil)
    B:RefreshAll()
    Equal(tostring(S[moon.fill.wash].shown) .. " " .. tostring(S[moon.fill.flash].shown), "false true",
        "and the one flash is for being able to pay, not for walking into reach")
    Equal(#printed, 0, "no errors")
end)()

-- On your action bars ----------------------------------------------------------------------
-- Fill my action bars too, ticked: every button of your action bars is found
-- by name, the slot it holds is read from its own field or its attribute,
-- and a spell with a cost fills exactly as it does on your bars' icons. A
-- name the game hasn't got is skipped, and an empty slot, an item, a free
-- spell and a macro that casts nothing all leave the button alone. Whether
-- you can pay for what a button holds is the game's own answer here too, as
-- it is on your bars' icons: nothing is worked out from your power.

;(function()
    local ns, _, F = Fresh(nil, true)
    local FB = ns.FillBars
    -- Moonfire on the main bar, Wrath on the side bar, nothing in the rest.
    actionSlots[1], actionSlots[61] = { "spell", 8924 }, { "spell", 5176 }
    Short(8924, true)
    Short(5176, true)
    ns.Set("fill", true)
    F:Apply()
    local reads = actionReads
    local buttons, filled = FB:Watching()
    Equal(buttons .. " " .. filled .. " " .. (actionReads - reads), "0 0 0",
        "the fill on with your action bars unticked: no button is looked for, and nothing of your bars is read")
    -- Ticked.
    ns.Set("fillBars", true)
    F:Apply()
    buttons, filled = FB:Watching()
    Equal(buttons .. " " .. filled, "24 2",
        "ticked: the two bars the game has are found, twenty four buttons, and the two holding a spell with a cost fill")
    local main, side = FB:Parts(_G.ActionButton1), FB:Parts(_G.MultiBarBottomLeftButton1)
    Equal(Line(main), "shown 0.40 0,0,1 0.35", "Moonfire on the main bar: four tenths of the way up, in the game's mana blue")
    Equal(Line(side), "shown 0.80 0,0,1 0.35", "Wrath on the side bar, whose slot comes from its attribute: twice as high")
    Equal(tostring(FB:Parts(_G.ActionButton2)), "nil", "a button with an empty slot has no fill at all")
    -- An item, a free spell, and the two kinds of macro.
    actionSlots[3], actionSlots[4] = { "item", 118 }, { "spell", 6603 }
    actionSlots[5], actionSlots[6] = { "macro", 8924, "spell" }, { "macro", 7, "" }
    for _, slot in ipairs({ 3, 4, 5, 6 }) do Fire("ACTIONBAR_SLOT_CHANGED", slot) end
    Equal(tostring(FB:Parts(_G.ActionButton3)) .. " " .. tostring(FB:Parts(_G.ActionButton4)), "nil nil",
        "an item and a spell that costs nothing both get no fill")
    Equal(tostring(FB:Parts(_G.ActionButton5) ~= nil) .. " " .. tostring(FB:Parts(_G.ActionButton6)), "true nil",
        "a macro that shows a spell fills like the spell; one that casts nothing gets no fill")
    macroSpells[7] = 5176
    Fire("ACTIONBAR_SLOT_CHANGED", 6)
    Equal(tostring(FB:Parts(_G.ActionButton6) ~= nil), "true", "and a macro that casts a spell with a cost does")
    -- Your power: the fill follows it, goes with one flash the moment the game
    -- says you can pay, and comes back as you fall short again. Your power is
    -- asked for once for all of them (Fill.lua's own one ask), and handed
    -- straight to each fill's gauges. Three powers, not four: there is no
    -- Focus row, because a hunter casts from mana on this client and Focus is
    -- a pet's power, which the fill never reads.
    reads = PowerReads
    Power[0] = 100
    Short(8924, nil) -- the game says you can pay for it now
    Fire("UNIT_POWER_FREQUENT", "player", "MANA")
    Equal(tostring(S[main.wash].shown) .. " " .. tostring(S[main.flash].shown) .. " " .. (PowerReads - reads),
        "false true 3", "enough mana for it: the fill goes with one flash, and your three powers are asked for once between them")
    Power[0] = 40
    Short(8924, true)
    Fire("UNIT_POWER_FREQUENT", "player", "MANA")
    Equal(Line(main) .. " " .. Line(side), "shown 0.40 0,0,1 0.35 shown 0.80 0,0,1 0.35", "short again: both fills come back")
    -- The game refusing the question outright, not just keeping the answer
    -- secret: the fill stays as it was, and nothing flashes as though you had
    -- just paid for it.
    local asked = C_Spell.IsSpellUsable
    C_Spell.IsSpellUsable = function() error("the game refused") end
    S[main.flash].shown = false -- (the flash from paying for it above is still up: the mock game plays no fade)
    Power[0] = 70
    Fire("UNIT_POWER_FREQUENT", "player", "MANA")
    C_Spell.IsSpellUsable = asked
    Equal(Line(main) .. " " .. tostring(S[main.flash].shown), "shown 0.70 0,0,1 0.35 false",
        "whether you can pay refused: the fill stays, and still follows your power")
    Power[0] = 40
    Fire("UNIT_POWER_FREQUENT", "player", "MANA")
    -- The main bar turns its page, so its buttons hold other slots.
    rawset(_G.ActionButton1, "action", 85)
    actionSlots[85] = { "spell", 5176 }
    Fire("ACTIONBAR_PAGE_CHANGED")
    Equal(tostring(main.spell) .. " " .. Line(main), "5176 shown 0.80 0,0,1 0.35",
        "the page turned: the button fills to what the spell it holds now costs")
    -- A slot that empties: nothing is left on the button.
    actionSlots[85] = nil
    Fire("ACTIONBAR_SLOT_CHANGED", 85)
    Equal(tostring(S[main.wash].shown) .. " " .. tostring(main.on), "false false",
        "the slot emptied: nothing is left on the button")
    -- Your form changes what a spell costs and which power pays for it, and
    -- the bar turns its own page with it: the fill follows both.
    rawset(_G.ActionButton1, "action", 1)
    actionSlots[1] = { "spell", 8924 }
    PowerKind = 3
    Power[3] = 25
    Costs[8924] = { type = 3, cost = 50 }
    Fire("UPDATE_SHAPESHIFT_FORM")
    Fire("UNIT_DISPLAYPOWER", "player")
    Equal(main.power.key .. " " .. Line(main), "energy shown 0.50 1,1,0 0.35",
        "in form: the button fills with energy, half way up, in the game's energy yellow")
    -- A spell the form casts for nothing: the fill goes.
    Costs[8924] = nil
    Fire("UNIT_DISPLAYPOWER", "player")
    Equal(tostring(S[main.wash].shown) .. " " .. tostring(main.on), "false false",
        "a form that casts it for nothing: the fill goes, since there is nothing to fill")
    Costs[8924], PowerKind = { type = 0, cost = 100 }, 0
    Fire("UNIT_DISPLAYPOWER", "player")
    Fire("UPDATE_SHAPESHIFT_FORM")
    Equal(main.power.key .. " " .. Line(main), "mana shown 0.40 0,0,1 0.35", "and out of form it fills with mana again")
    -- The buttons a bar addon makes instead: one kind by name, the other
    -- from a list of its own. Neither is taken for granted.
    local named = CreateFrame("Button", "BT4Button1", UIParent)
    named:SetSize(30, 30)
    rawset(named, "GetAttribute", function(_, what) if what == "action" then return 61 end end)
    local listed = CreateFrame("Button", nil, UIParent)
    listed:SetSize(30, 30)
    rawset(listed, "action", 1)
    local flipped = CreateFrame("Button", nil, UIParent)
    flipped:SetSize(30, 30)
    rawset(flipped, "action", 62)
    actionSlots[1], actionSlots[62] = { "spell", 8924 }, { "spell", 5176 }
    -- Its list either way round: a button and its number, or a number and
    -- its button.
    _G.Dominos = { ActionButtons = { buttons = { [listed] = 1, [2] = flipped } } }
    Fire("ADDON_LOADED", "SomeBars")
    buttons, filled = FB:Watching()
    Equal(buttons .. " " .. tostring(FB:Parts(named) ~= nil) .. " " .. tostring(FB:Parts(listed) ~= nil)
        .. " " .. tostring(FB:Parts(flipped) ~= nil), "27 true true true",
        "a bar addon's buttons are found as it loads, each filling from the slot it holds")
    Equal(tostring(_G.Dominos.ActionButtons.buttons[listed]), "1", "and its own list is only read, never written to")
    -- A button its bar hasn't sized yet: nothing is made for it until it has
    -- a size, and the next look at your bars gives it one.
    local unsized = CreateFrame("Button", "BT4Button2", UIParent)
    rawset(unsized, "action", 1)
    -- And a watch on that one from the moment it is made, through its layers
    -- being built and every read after: each call the rules forbid on a button
    -- of your bars is counted here, whether or not the mock game keeps the
    -- last call of it (it doesn't for a point, a showing or a hiding, so the
    -- block below can't see those; this can).
    local touched = {}
    for _, name in ipairs({ "SetAttribute", "SetPoint", "SetAllPoints", "ClearAllPoints", "Show", "Hide", "SetShown",
        "SetFrameLevel", "SetFrameStrata", "SetParent", "SetScale", "SetAlpha" }) do
        local was = Proto[name]
        rawset(unsized, name, function(self, ...)
            touched[#touched + 1] = name
            if was then return was(self, ...) end
        end)
    end
    Fire("ADDON_LOADED", "SomeBars")
    Equal(tostring(FB:Parts(unsized)), "nil", "a button with no size yet gets no layers")
    unsized:SetSize(30, 30)
    Fire("PLAYER_ENTERING_WORLD")
    Equal(tostring(FB:Parts(unsized) ~= nil) .. " " .. tostring(FB:Parts(unsized).width), "true 30",
        "and once its bar has sized it, its fill is made to that size")
    FB:Reread()
    Equal(#touched .. " " .. (touched[1] or "nothing"), "0 nothing",
        "and nothing was ever set on the button itself through any of it: no attribute, no point, no showing or hiding,"
        .. " no level, strata or parent, no scale and no opacity")
    -- Nothing is ever set on a button of your bars: no attribute, no point,
    -- no scale, no showing or hiding, and none of its frame level, its strata
    -- or the frame it sits in either. The fill's own frame takes the button's
    -- level; the button's own level is only ever read.
    for _, button in ipairs({ _G.ActionButton1, _G.MultiBarBottomLeftButton1, named, listed }) do
        local s = S[button]
        Equal(tostring(s.last.SetAttribute) .. " " .. tostring(s.last.SetPoint) .. " " .. tostring(s.last.SetScale)
            .. " " .. tostring(s.last.Show) .. " " .. tostring(s.last.Hide) .. " " .. tostring(s.last.SetFrameLevel)
            .. " " .. tostring(s.last.SetFrameStrata) .. " " .. tostring(s.last.SetParent),
            "nil nil nil nil nil nil nil nil",
            "nothing is set, moved, scaled, shown, hidden, levelled, restacked or moved into another frame on a button of your bars")
    end
    Equal(#printed, 0, "no errors")
end)()

-- A bar that turns its page a moment later ---------------------------------------------------
-- A button's own slot can take the game until the next frame to follow a page
-- or a form change, and a bar addon turns its own bar a moment after that, so
-- the buttons are read again on the next frame and once more after that.

;(function()
    local ns, _, F = Fresh(nil, true)
    local FB = ns.FillBars
    actionSlots[1] = { "spell", 8924 }
    Short(8924, true)
    Short(5176, true)
    ns.Set("fill", true)
    ns.Set("fillBars", true)
    F:Apply()
    local main = FB:Parts(_G.ActionButton1)
    Equal(tostring(main.spell) .. " " .. Line(main), "8924 shown 0.40 0,0,1 0.35", "Moonfire on the main bar, filling")
    -- The page turns, and the button is still holding the slot it was.
    local was = #timers
    Fire("ACTIONBAR_PAGE_CHANGED")
    Equal(tostring(main.spell), "8924", "read straight away: the button is still holding what it was")
    -- Its bar turns its page now, and the reads that were waiting run.
    rawset(_G.ActionButton1, "action", 85)
    actionSlots[85] = { "spell", 5176 }
    for i = was + 1, #timers do timers[i]() end
    Equal(tostring(main.spell) .. " " .. Line(main), "5176 shown 0.80 0,0,1 0.35",
        "its bar turned its page after the game's word: the buttons are read again, so the fill follows")
    -- The same for a form change.
    was = #timers
    Fire("UPDATE_SHAPESHIFT_FORM")
    rawset(_G.ActionButton1, "action", 1)
    for i = was + 1, #timers do timers[i]() end
    Equal(tostring(main.spell) .. " " .. Line(main), "8924 shown 0.40 0,0,1 0.35", "and back again out of the form")
    -- With the tick off a read that was waiting leaves the buttons alone.
    was = #timers
    Fire("ACTIONBAR_PAGE_CHANGED")
    ns.Set("fillBars", false)
    F:Apply()
    rawset(_G.ActionButton1, "action", 85)
    for i = was + 1, #timers do timers[i]() end
    Equal(tostring(main.on) .. " " .. tostring(S[main.wash].shown), "false false",
        "unticked while a read waited: it reads nothing, and nothing is left on the button")
    Equal(#printed, 0, "no errors")
end)()

-- Nothing is made in a fight -----------------------------------------------------------------
-- A button that takes a spell mid-fight gets no layers then: it waits for
-- the end of the fight.

;(function()
    local ns, _, F = Fresh(nil, true)
    local FB = ns.FillBars
    actionSlots[1] = { "spell", 8924 }
    Short(8924, true)
    Short(5176, true)
    ns.Set("fill", true)
    ns.Set("fillBars", true)
    F:Apply()
    local _, filled = FB:Watching()
    Equal(filled, 1, "one button filling to start with")
    lockdown = true
    actionSlots[2] = { "spell", 5176 }
    local made = #objects
    Fire("ACTIONBAR_SLOT_CHANGED", 2)
    Equal(tostring(FB:Parts(_G.ActionButton2)) .. " " .. (#objects - made), "nil 0",
        "a spell on another button in a fight: nothing at all is made, so its fill waits")
    -- The ones already made still follow your power in the fight.
    Power[0] = 70
    Fire("UNIT_POWER_FREQUENT", "player", "MANA")
    Equal(Line(FB:Parts(_G.ActionButton1)), "shown 0.70 0,0,1 0.35", "the fills already there keep following your power in it")
    lockdown = false
    Fire("PLAYER_REGEN_ENABLED")
    Equal(tostring(FB:Parts(_G.ActionButton2) ~= nil) .. " " .. (#objects - made > 0 and "made" or "nothing"), "true made",
        "and once the fight is over its layers are made and it fills")
    Equal(#printed, 0, "no errors")
end)()

-- Under the button's own swipe, keybind and count ----------------------------------------------
-- A fill on one of your action bars' buttons is made of textures on the
-- button itself, in ARTWORK at its lowest sublevels: that keeps it over the
-- button's art and under its border, and under its cooldown swipe, which is a
-- frame at the button's own level (a frame of ours there would draw over the
-- swipe, a texture on the button draws under it: seen in game, 26 Nov 2026).
-- The keybind and the count sit far above either. Only the fill's own frame
-- goes inside the button, holding nothing a player sees: the gauges alone,
-- each see-through, so only the game's own measure of them is ever used. On
-- your bars' icons the fill sits on that frame and over the icon as before.

;(function()
    local ns, _, F = Fresh(nil, true)
    local FB = ns.FillBars
    actionSlots[1] = { "spell", 8924 }
    Short(8924, true)
    ns.Set("fill", true)
    ns.Set("fillCost", true)
    -- Each layer's draw layer and sublevel as the game is asked for it.
    local layers, texts = {}, {}
    local made, wrote = Proto.CreateTexture, Proto.CreateFontString
    Proto.CreateTexture = function(self, name, layer, template, sublevel)
        local texture = made(self)
        layers[texture] = tostring(layer) .. " " .. tostring(sublevel)
        return texture
    end
    Proto.CreateFontString = function(self, name, layer, template)
        local text = wrote(self, name, layer, template)
        texts[text] = tostring(layer)
        return text
    end
    ns.Set("fillBars", true)
    F:Apply()
    local sample = F:Sample(UIParent, 40) -- a fill of the page's own kind, for the comparison below
    Proto.CreateTexture, Proto.CreateFontString = made, wrote
    local parts = FB:Parts(_G.ActionButton1)
    local button = _G.ActionButton1
    Equal(layers[parts.dark] .. " | " .. layers[parts.darkTop] .. " | " .. layers[parts.wash] .. " | "
        .. layers[parts.above] .. " | " .. layers[parts.below] .. " | " .. layers[parts.flecks[1]] .. " | "
        .. layers[parts.crest] .. " | " .. layers[parts.flash],
        "ARTWORK -8 | ARTWORK -8 | ARTWORK -7 | ARTWORK -6 | ARTWORK -5 | ARTWORK -4 | ARTWORK -3 | ARTWORK -1",
        "every layer in ARTWORK at its lowest sublevels, the darkening up through the wash to the crest, under the"
        .. " button's border, swipe, keybind and count")
    Equal(texts[parts.cost] .. " " .. tostring(Last(parts.cost, "SetDrawLayer", 2)), "ARTWORK -2",
        "what it costs sits over the fill and under them too")
    local onButton = true
    for _, layer in ipairs(parts.layers) do onButton = onButton and S[layer].parent == button end
    Equal(tostring(onButton) .. " " .. tostring(S[parts.flash].parent == button), "true true",
        "every one of them, the darkening, the cost and the flash included, is the button's own texture")
    Equal(tostring(Last(parts.holder, "SetFrameLevel")) .. " " .. tostring(button:GetFrameLevel()) .. " "
        .. tostring(S[parts.holder].parent == button), "1 1 true",
        "the fill's own frame sits inside the button at its own level")
    local inFrame = 0
    for _, obj in ipairs(objects) do if S[obj].parent == parts.holder then inFrame = inFrame + 1 end end
    Equal(inFrame .. " " .. S[parts.gauge].alpha .. " " .. tostring(S[parts.gauge].parent == parts.holder), "6 0 true",
        "and all it holds is the six gauges, see-through, so nothing of ours draws over the swipe")
    -- On your bars' icons: the layers go on the fill's own frame, over the
    -- icon and its swipe, exactly as they always did.
    Equal(layers[sample.fill.wash] .. " | " .. layers[sample.fill.crest] .. " | "
        .. tostring(S[sample.fill.wash].parent == sample.fill.holder), "ARTWORK -2 | ARTWORK 2 | true",
        "and a fill of your own bars' kind is drawn on its own frame over the icon as it always was")
    Equal(#printed, 0, "no errors")
end)()

-- Unticked again: nothing on your action bars ------------------------------------------------
-- Nothing is left on a button, nothing of your bars is heard or read, and
-- the whole fill switched off takes the action bars' with it.

;(function()
    local ns, _, F = Fresh(nil, true)
    local FB = ns.FillBars
    actionSlots[1] = { "spell", 8924 }
    Short(8924, true)
    Short(5176, true)
    ns.Set("fill", true)
    ns.Set("fillBars", true)
    F:Apply()
    local parts = FB:Parts(_G.ActionButton1)
    Equal(tostring(S[parts.wash].shown), "true", "filling to start with")
    ns.Set("fillBars", false)
    F:Apply()
    Equal(tostring(S[parts.wash].shown) .. " " .. tostring(parts.on) .. " " .. tostring(next(S[FB.driver].events)),
        "false false nil", "unticked: nothing left on the button, and nothing of your bars is heard any more")
    local reads = actionReads
    actionSlots[1] = { "spell", 5176 }
    Fire("ACTIONBAR_SLOT_CHANGED", 1)
    Fire("ACTIONBAR_PAGE_CHANGED")
    Fire("UNIT_POWER_FREQUENT", "player", "MANA")
    Equal((actionReads - reads) .. " " .. tostring(S[parts.wash].shown), "0 false",
        "a slot changing, the page turning and your power changing all leave it alone")
    -- Ticked again, and then the whole fill off.
    ns.Set("fillBars", true)
    F:Apply()
    Equal(tostring(S[parts.wash].shown) .. " " .. tostring(parts.spell), "true 5176", "ticked again: it fills the spell there now")
    ns.Set("fill", false)
    F:Apply()
    Equal(tostring(S[parts.wash].shown) .. " " .. tostring(next(S[FB.driver].events)), "false nil",
        "the whole fill off: the action bars' goes with it")
    Equal(#printed, 0, "no errors")
end)()

-- Its page --------------------------------------------------------------------------------
-- Under More in /ccm: the tick that starts it, the tick for your action
-- bars, the look and the movement, the sliders, every small tick, one colour
-- a power with a way back to the game's own, and a preview that draws itself.

;(function()
    local ns, B, F = Fresh()
    ns.ShowWindow()
    FECMFrame:Select("fill")
    local page = FECMFrame.pages.fill
    Equal(tostring(page ~= nil) .. " " .. tostring(FECMFrame.nav.fill ~= nil), "true true", "the page and its row under More are there")
    Equal(S[page.status].text, "Off. Tick the box below to start.", "off, the page says so")
    local moon = B:Get("cd").icons[1]
    Short(8924, true)
    page.master:Click()
    B:RefreshAll()
    Equal(tostring(ns.Get("fill")) .. " " .. tostring(moon.fill.on), "true true", "the tick starts it, and the icon fills")
    Equal(S[page.status].text, "Liquid, normal, on your bars' icons.", "and the page says what it draws")
    -- The look and the movement.
    page.look.buttons[2]:Click()
    -- Flat has no surface and nothing moving, so the three ticks that only
    -- change those are greyed: a tick a player can turn on and off while it
    -- does nothing at all is worse than one it can't reach.
    Equal(ns.Get("fillStyle") .. " " .. tostring(S[page.move].alpha) .. " " .. tostring(page.bubbles.usable)
        .. " " .. tostring(page.line.usable) .. " " .. S[page.status].text,
        "flat 0.35 false false Flat, on your bars' icons.",
        "Flat picked: Movement, Bubbles and the bright line on the surface are greyed, since Flat has none of them")
    Equal(S[page.says].text, "One clean block of colour. Nothing moves.", "and the preview says what the look does")
    page.look.buttons[1]:Click()
    page.move.buttons[3]:Click()
    Equal(ns.Get("fillStyle") .. " " .. ns.Get("fillMove") .. " " .. tostring(S[page.move].alpha), "liquid lively 1",
        "Liquid and Lively picked, and Movement is usable again")
    -- Fill my action bars too, beside the tick that starts it.
    page.bars:Click()
    Equal(tostring(ns.Get("fillBars")) .. " " .. S[page.status].text, "true Liquid, lively, on your bars' icons and your action bars.",
        "the action bars ticked: the page says it draws on both")
    page.bars:Click()
    Equal(tostring(ns.Get("fillBars")) .. " " .. S[page.status].text, "false Liquid, lively, on your bars' icons.",
        "and unticked, on your bars' icons alone")
    -- The sliders.
    page.strength:Choose(100)
    page.darkness:Choose(0)
    Equal(ns.Get("fillStrength") .. " " .. ns.Get("fillDarkness") .. " " .. S[page.strength.value].text,
        "100 0 100%", "Fill strength and Darkness set, each shown in percent")
    -- Every tick.
    for _, name in ipairs({ "bubbles", "flash", "line", "dim", "cost" }) do
        local before = page[name]:GetChecked()
        page[name]:Click()
        Equal(tostring(page[name]:GetChecked()) .. " " .. tostring(before ~= page[name]:GetChecked()), tostring(not before) .. " true",
            name .. " can be ticked and unticked")
        page[name]:Click()
    end
    Equal(tostring(page.bubbles.usable) .. " " .. tostring(page.line.usable), "true true",
        "Bubbles and the bright line on the surface are usable on Liquid")
    -- One colour a power, and the way back.
    Equal(#page.rows .. " " .. page.rows[1].power.name .. " " .. S[page.rows[1].chosen].text, "3 Mana Game's own",
        "three rows, mana first, each at the game's own colour")
    page.rows[1].choice.swatches[2]:Click()
    Equal(ns.Get("fillMana") .. " " .. S[page.rows[1].chosen].text, "orange Orange", "a colour picked for mana")
    page.reset:Click()
    Equal(ns.Get("fillMana") .. " " .. ns.Get("fillRage") .. " " .. S[page.rows[1].chosen].text, "default default Game's own",
        "Game's colours puts all four back")
    -- It draws on your own bars, so it says so while they're off.
    ns.Set("useBars", false)
    B:Rebuild()
    FECMFrame:Refresh()
    Equal(S[page.status].text, "On, but your bars are off: turn Use my bars on, on the General page.",
        "with your bars off it says where to turn them on")
    -- Unless your action bars are ticked, where it has plenty to draw on.
    page.bars:Click()
    Equal(S[page.status].text, "Liquid, lively, on your action bars.",
        "with your bars off and your action bars ticked it says it draws there")
    page.bars:Click()
    ns.Set("useBars", true)
    B:Rebuild()
    FECMFrame:Refresh()
    -- The preview draws itself from its own clock, the fill on or off. Its
    -- levels are its own plain numbers, measured against one whole, so its
    -- gauges stand where the page asked and the last one fills up over and over.
    local sample = page.samples[1].fill
    S[page.tray].scripts.OnUpdate(page.tray, .1)
    Equal(tostring(Last(sample.wash, "SetColorTexture", 4) ~= nil) .. " " .. tostring(#page.samples) .. " " .. Level(sample),
        "true 4 0.20", "four preview icons, drawn by the page's own clock, the first a fifth of the way up")
    local rising = Level(page.samples[4].fill)
    S[page.tray].scripts.OnUpdate(page.tray, .8)
    Equal(tostring(Level(page.samples[2].fill)) .. " " .. tostring(Level(page.samples[4].fill) ~= rising), "0.45 true",
        "the set levels stay put while the last one fills up as you watch")
    -- Unticked again: nothing is left on an icon, nothing is heard, and
    -- nothing runs frame by frame.
    local reads = PowerReads
    page.master:Click()
    Fire("UNIT_POWER_FREQUENT", "player", "MANA")
    Equal(tostring(moon.fill.on) .. " " .. tostring(S[moon.fill.wash].shown) .. " " .. tostring(F:Running()) .. " "
        .. tostring(next(S[F.driver].events)) .. " " .. PowerReads, "false false false nil " .. reads,
        "unticked: nothing on the icon, nothing heard, nothing drawn, and your power never asked for")
    Equal(Note(page.master):find("fills up from the bottom") ~= nil, true, "its tick says what it does on hover")
    Equal(Note(page.bars):find("Blizzard's bars and the common bar addons") ~= nil, true,
        "and the action bars' tick says which bars it covers, naming no addon")
    Equal(#printed, 0, "no errors")
end)()

-- The mock game's secret has the game's own teeth ---------------------------------------------
-- Your power is a secret on this client, in a fight and out of one, and the
-- game stops any sum or comparison with one from addon code. So does the mock
-- game: both are tried here from a chunk standing in for an addon file (the
-- real game's own code, and the tests, may look, which is the only reason
-- Level() above can). That is what makes every check in this file fail if a
-- division of your power by what a spell costs is ever put back in.

;(function()
    local power = SecretNumber(40)
    local divide = assert(load("return function(v) return v / 100 end", "@Fill.lua"))()
    local compare = assert(load("return function(v) return v < 1 end", "@Fill.lua"))()
    local summed, sum = pcall(divide, power)
    local tested, test = pcall(compare, power)
    -- Both were noted as the addon misusing a secret, which fails the next
    -- check: taken off the list here, since these two were on purpose.
    local noted = #SecretMisuse
    local said = tostring(SecretMisuse[1]) .. " | " .. tostring(SecretMisuse[2])
    for i = noted, 1, -1 do SecretMisuse[i] = nil end
    Equal(tostring(issecretvalue(power)) .. " " .. type(power), "true number",
        "a secret number says it is a number, so a type check alone never gets past one")
    Equal(tostring(summed) .. " " .. tostring(tested), "false false", "it can be neither divided nor compared")
    Equal(tostring(sum):find("arithmetic") ~= nil and tostring(test):find("compare") ~= nil, true,
        "each stops with the game's own words")
    Equal(noted .. " " .. tostring(said:find("Fill.lua") ~= nil), "2 true",
        "and each is noted against the file that did it, so a check after it fails")
    Equal(#printed, 0, "no errors")
end)()

Equal(#printed, 0, "no errors")

Equal(SecretMisuse[1], nil, "no secret misused anywhere")
io.write("Resource fill checks passed: " .. checks .. " assertions.\n")
