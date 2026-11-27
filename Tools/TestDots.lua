-- Run the actual addon files against a mock game for the DoTs part: the
-- damage over time spells you have running on your target, with the damage
-- they still have to deal marked on its health bar. This file covers the
-- shell: the settings and their defaults, the row under More in /ccm, the
-- page and every control on it, and the mock game's own additions the rest of
-- the part will be built on.
-- What the probe proved in game on 26 Nov 2026 (build 1.60.1.71139) and this
-- file holds the game to: the combat log is shut to addons, so registering
-- for COMBAT_LOG_EVENT_UNFILTERED is refused outright; your health is secret
-- in a fight and out of one, with a number only the game may look behind, so
-- a status bar of ours takes the sealed max as its range and the plain damage
-- as its value and the game does that division; and each spell's own text
-- (C_Spell.GetSpellDescription) carries the server's numbers, so there is no
-- coefficient table of ours.
-- Nothing is drawn yet: the band, the clock and the list come next, and this
-- file is what proves they are built on a shell that behaves.
-- The mock game is a copy of Tools/TestBars.lua's: Tools/TestMockSync.mjs
-- checks the two match, and with --write copies it across.
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

-- DoTs: the game around it ----------------------------------------------------------
-- Stand-ins for what the window's other pages need (as Tools/TestPulse.lua:
-- Raid Timers' previews run none of Blizzard's code), and your power and what
-- your spells cost for the Resource fill page that sits above this one under
-- More.

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

-- What the Resource fill page needs, as Tools/TestFill.lua sets it up: your
-- power secret with a number behind it, each spell's cost, and the game's own
-- colour for each power.
local function FillGame()
    _G.Enum.PowerType = { Mana = 0, Rage = 1, Focus = 2, Energy = 3 }
    _G.UnitPower = function(unit, kind)
        assert(unit == "player", "your own power")
        assert(type(kind) == "number", "a power type")
        return SecretNumber(40)
    end
    _G.UnitPowerMax = function(unit, kind)
        assert(unit == "player" and type(kind) == "number")
        return 100
    end
    _G.UnitPowerType = function(unit)
        assert(unit == "player")
        return 0, "MANA"
    end
    _G.PowerBarColor = { MANA = { r = 0, g = 0, b = 1 }, RAGE = { r = 1, g = 0, b = 0 },
        ENERGY = { r = 1, g = 1, b = 0 }, FOCUS = { r = 1, g = .5, b = .25 } }
    _G.C_Spell.GetSpellPowerCost = function(id)
        assert(type(id) == "number", "a spell ID")
        return { { type = 0, cost = 100, name = "POWER" } }
    end
    _G.PlaySound = function() end
    S[UIParent].width, S[UIParent].height = 1366, 768
end

-- Every file in the order the .toc loads them (Tools/TestRules.mjs checks the
-- .toc). The Totems bar needs a shaman's game of its own, so it is left out
-- here as it is in Tools/TestPulse.lua.
local FILES = { "Core.lua", "SquirtVersions.lua", "Style.lua", "Skin.lua", "Resource.lua", "CastBar.lua", "RaidTimers.lua", "Ranks.lua",
    "Forms.lua", "Spells.lua", "Keybinds.lua", "Buffs.lua", "IconAuras.lua", "Bars.lua", "Pulse.lua", "Fill.lua", "FillBars.lua",
    "Dots.lua", "DotsBand.lua", "Layout.lua",
    "Theme.lua", "BarPage.lua", "LayoutPage.lua", "CastBarPage.lua", "RaidTimersPage.lua", "PulsePage.lua", "FillPage.lua",
    "DotsPage.lua", "ProfileShare.lua", "ProfileMenu.lua", "Window.lua", "Tour.lua", "MinimapButton.lua", "Notes.lua", "Debug.lua" }

-- A fresh game, logged in, with the DoTs part as it comes out of the box.
local function Fresh(saved)
    Environment()
    BlizzardFrames()
    FillGame()
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
    return ns, ns.Dots, ns.DotsBand
end

-- The window open on the DoTs page.
local function Opened(ns)
    ns.ShowWindow()
    FECMFrame:Select("dots")
    return FECMFrame, FECMFrame.pages.dots
end

-- A control's note on hover, however it is kept.
local function Note(control)
    local hint = control.hint
    if type(hint) == "function" then hint = hint(control) end
    return tostring(hint)
end

-- Every control on the page, in the order it is drawn.
local CONTROLS = { "master", "band", "line", "skull", "list", "numbers", "timer", "procs", "others", "nameplates",
    "amber", "strength", "size", "rowHeight", "spacing", "across", "grow", "wrap", "outOfCombat", "choose" }
-- The ticks, the sliders and the choices, each with the setting it holds.
local TICKS = { band = "dotBand", line = "dotLine", skull = "dotSkull", list = "dotList", numbers = "dotNumbers",
    timer = "dotTimer", procs = "dotProcs", others = "dotOthers", nameplates = "dotNameplates", amber = "dotAmber" }

-- The controls greyed out now, in page order: SetUsable greys a tick, a
-- slider and a choice the same way, so their own opacity is the one measure.
local function Greyed(page)
    local out = {}
    for _, name in ipairs(CONTROLS) do
        if S[page[name]].alpha ~= 1 then out[#out + 1] = name end
    end
    for i, row in ipairs(page.rows) do
        if S[row.choice].alpha ~= 1 then out[#out + 1] = "colour" .. i end
    end
    return table.concat(out, " ")
end

-- The rows under More, top to bottom, from where each one sits in the list.
local function MoreRows(w)
    local rows = {}
    for _, key in ipairs({ "raid", "pulse", "totems", "fill", "dots" }) do
        local item = w.nav[key]
        if item then rows[#rows + 1] = { key = key, y = -(S[item].points[1][3] or 0) } end
    end
    table.sort(rows, function(a, b) return a.y < b.y end)
    local out = {}
    for _, row in ipairs(rows) do out[#out + 1] = row.key end
    return table.concat(out, " ")
end

-- Whether anything at all is listening for an event.
local function Hearing(event)
    for _, obj in ipairs(objects) do
        local events = S[obj].events
        if events and events[event] then return true end
    end
    return false
end

-- Off until it is ticked ------------------------------------------------------------
-- Every setting is off or at its own starting value, nothing is heard, and
-- the band has nothing to draw.

;(function()
    local ns, D, B = Fresh()
    Equal(tostring(ns.Get("dots")) .. " " .. tostring(D:On()) .. " " .. tostring(D.started) .. " " .. tostring(B.started),
        "false false true true", "off by default, and both parts started all the same")
    Equal(tostring(B.wanted), "false", "so the band has nothing to draw")
    Equal(tostring(Hearing("UNIT_SPELLCAST_SUCCEEDED")) .. " " .. tostring(Hearing("COMBAT_LOG_EVENT_UNFILTERED")), "false false",
        "nothing is heard: not your casts, and never the combat log")
    -- Every setting's own starting value, in one line.
    local said = {}
    for _, key in ipairs({ "dots", "dotBand", "dotLine", "dotSkull", "dotList", "dotOthers", "dotNameplates", "dotBandColour",
        "dotBandColourCustom", "dotLineColour", "dotLineColourCustom", "dotBandStrength", "dotSize", "dotSpacing",
        "dotRowHeight", "dotPerRow", "dotGrow", "dotWrap", "dotNumbers", "dotTimer", "dotAmber", "dotProcs",
        "dotOutOfCombat", "dotX", "dotY" }) do
        said[#said + 1] = key .. "=" .. tostring(ns.Get(key))
    end
    Equal(table.concat(said, " "), "dots=false dotBand=true dotLine=true dotSkull=true dotList=true dotOthers=false"
        .. " dotNameplates=false dotBandColour=default dotBandColourCustom= dotLineColour=white dotLineColourCustom="
        .. " dotBandStrength=55 dotSize=28 dotSpacing=4 dotRowHeight=14 dotPerRow=8 dotGrow=centre dotWrap=down"
        .. " dotNumbers=true dotTimer=true dotAmber=true dotProcs=true dotOutOfCombat=show dotX=0 dotY=-210",
        "every DoTs setting at its own starting value: the master off, and the ticks that only change what shows while it is"
        .. " already on ticked, as the Resource fill's are")
    Equal(#printed, 0, "no errors")
end)()

-- Each setting kept, and a value the game would refuse put right -------------------
-- A number outside its limits, a choice that is not one, and a colour that is
-- not six hex digits all read back as the setting's own starting value
-- (ns.Valid), so a DoTs setting can never hold something the page cannot show.

;(function()
    local ns = Fresh()
    local said = {}
    for _, pair in ipairs({ { "dotBandStrength", 100 }, { "dotSize", 64 }, { "dotSpacing", 20 }, { "dotRowHeight", 40 },
        { "dotPerRow", 12 }, { "dotGrow", "left" }, { "dotWrap", "up" }, { "dotOutOfCombat", "hide" },
        { "dotBandColour", "purple" }, { "dotLineColour", "black" }, { "dotX", -4000 }, { "dotY", 4000 },
        { "dots", true }, { "dotBand", false }, { "dotAmber", false } }) do
        ns.Set(pair[1], pair[2])
        said[#said + 1] = tostring(ns.Get(pair[1]))
    end
    Equal(table.concat(said, " "), "100 64 20 40 12 left up hide purple black -4000 4000 true false false",
        "every setting keeps what it is set to, each inside its own limits or choices")
    -- Saved and read again, as a reload does it.
    local saved = _G.ForeverEnhancedCooldownManagerDB
    local again = Fresh(saved)
    Equal(again.Get("dotBandStrength") .. " " .. again.Get("dotGrow") .. " " .. tostring(again.Get("dots")) .. " "
        .. tostring(again.Get("dotBand")), "100 left true false", "and they come back after a reload")
    local wrong = {}
    for _, pair in ipairs({ { "dotBandStrength", 5 }, { "dotBandStrength", 500 }, { "dotPerRow", 0 }, { "dotPerRow", 40 },
        { "dotRowHeight", 2 }, { "dotRowHeight", 400 }, { "dotSize", 1 }, { "dotGrow", "sideways" }, { "dotWrap", "left" },
        { "dotOutOfCombat", "never" }, { "dotBandColour", "turquoise" }, { "dotLineColour", "beige" },
        { "dotBandColourCustom", "nothex" }, { "dots", "yes" }, { "dotAmber", 1 }, { "dotX", -9000 } }) do
        _G.ForeverEnhancedCooldownManagerDB[pair[1]] = pair[2]
        wrong[#wrong + 1] = tostring(again.Get(pair[1]))
    end
    Equal(table.concat(wrong, " "), "55 55 8 8 14 14 28 centre down show default white  false true 0",
        "a value the game would refuse reads back as the setting's own starting value")
    Equal(#printed, 0, "no errors")
end)()

-- Its row under More ----------------------------------------------------------------
-- Last under More, after Resource fill, with its own note in the footer. The
-- row is behind a gate on the files being there, since a new file only loads
-- after a full restart.

;(function()
    local ns = Fresh()
    local w = Opened(ns)
    Equal(MoreRows(w), "raid pulse fill dots", "DoTs is the last row under More, after Resource fill")
    Equal(S[w.nav.dots.label].text .. " | " .. Note(w.nav.dots),
        "DoTs | The damage your spells still have to deal, marked on your target's health bar.",
        "named DoTs, and the footer says what the page is for")
    Equal(tostring(ns.BuildDotsPage ~= nil) .. " " .. tostring(ns.Dots ~= nil) .. " " .. tostring(w.pages.dots ~= nil),
        "true true true", "the page is built because both its files are there")
    Equal(w.barRoom > 0, true, "and the bar list still has room of its own under the rows")
    Equal(#printed, 0, "no errors")
end)()

-- Its page: off -----------------------------------------------------------------------
-- The title, the status line saying it is off, and every control but the
-- first greyed, so nothing on it can be changed until it is on.

;(function()
    local ns = Fresh()
    local _, page = Opened(ns)
    Equal(S[page.title].text .. " | " .. S[page.status].text, "DOTS | Off. Tick the box below to start.",
        "the page is titled and says it is off")
    Equal(Greyed(page), "band line skull list numbers timer procs others nameplates amber strength size rowHeight spacing"
        .. " across grow wrap outOfCombat choose colour1 colour2",
        "off: every control but the first is greyed, the two colours included")
    -- The two things a player has to be told in plain words, not on hover.
    Equal(S[page.saidBand].text, "The figures come from each spell's own description, so they already include your gear. Some"
        .. " spells deal their damage unevenly over their time, and the figure is their total.",
        "where the figures come from, on the page")
    Equal(S[page.saidProcs].text, "Spells a hit sets off are listed and timed, but not counted in the band. The game does not"
        .. " tell addons how big the hit was.", "and what the band leaves out, so it does not read as a bug")
    Equal(#printed, 0, "no errors")
end)()

-- Its page: on ------------------------------------------------------------------------
-- The first tick starts it, the status line says what it is doing, and each
-- control follows the one it depends on: the band's line, skull, strength and
-- nameplates on the band, and the list's icons on the list.

;(function()
    local ns = Fresh()
    -- Blizzard's target frame, as the game always has one: without it the
    -- status line says the band has nothing to sit on instead.
    TargetFrameGame(true)
    local w, page = Opened(ns)
    page.master:Click()
    Equal(tostring(ns.Get("dots")) .. " | " .. S[page.status].text, "true | On. Cast a damage over time spell to see it.",
        "ticked on, and the page says so until a spell is running")
    Equal(Greyed(page), "", "on, with the band and the list ticked: nothing is greyed")
    page.band:Click()
    Equal(tostring(ns.Get("dotBand")) .. " | " .. Greyed(page),
        "false | line skull others nameplates strength colour2",
        "the band unticked: its line, its skull, other players' spells, nameplates, its strength and the line's colour"
        .. " go with it, since every one of them is something the band draws")
    Equal(tostring(Last(page.rows[1].choice, "SetEnabled", 1)), "true",
        "but the band's own colour stays open, since each row's bar in the list is drawn in it as well")
    Equal(tostring(Last(page.rows[2].choice, "SetEnabled", 1)) .. " " .. tostring(Note(page.rows[2].choice) ~= "nil"),
        "false true", "and a greyed colour cannot be clicked open, though it still says what it is for")
    page.band:Click()
    Equal(tostring(Last(page.rows[2].choice, "SetEnabled", 1)), "true",
        "the band ticked again: the line's colour can be opened")
    page.list:Click()
    Equal(tostring(ns.Get("dotList")) .. " | " .. Greyed(page), "false | numbers timer procs amber size rowHeight spacing"
        .. " across grow wrap", "the list unticked: the rows' own choices go with it, the ones a hit sets off among them,"
        .. " since that tick only ever changes the list")
    Equal(tostring(Last(page.choose, "SetEnabled", 1)), "true",
        "but Choose spells stays open to you, since a spell unticked there is left out of the band as well as the rows")
    page.band:Click()
    Equal(Greyed(page):find("colour1 colour2", 1, true) ~= nil, true,
        "the band off and the list off together: nothing is drawn at all, so the band's own colour goes as well")
    page.band:Click()
    page.list:Click()
    page.master:Click()
    Equal(tostring(ns.Get("dots")) .. " | " .. S[page.status].text, "false | Off. Tick the box below to start.",
        "and unticked again it is off, whatever the rest hold")
    Equal(tostring(ns.Get("dotBand")) .. " " .. tostring(ns.Get("dotList")), "true true",
        "the rest keep what they were: off is one tick, not a reset")
    Equal(#printed, 0, "no errors")
end)()

-- Its page: every control -------------------------------------------------------------
-- Each tick, slider and choice changes its own setting and nothing else, and
-- each one says what it does on hover.

;(function()
    local ns = Fresh()
    local w, page = Opened(ns)
    page.master:Click()
    local said = {}
    for name, key in pairs(TICKS) do
        local before = ns.Get(key)
        page[name]:Click()
        local after = ns.Get(key)
        page[name]:Click()
        said[#said + 1] = name .. "=" .. tostring(after ~= before) .. tostring(ns.Get(key) == before)
    end
    table.sort(said)
    Equal(table.concat(said, " "), "amber=truetrue band=truetrue line=truetrue list=truetrue nameplates=truetrue"
        .. " numbers=truetrue others=truetrue procs=truetrue skull=truetrue timer=truetrue",
        "every tick can be ticked and unticked, and puts its own setting back")
    page.strength:Choose(80)
    page.size:Choose(40)
    page.rowHeight:Choose(22)
    page.spacing:Choose(10)
    page.across:Choose(2)
    Equal(ns.Get("dotBandStrength") .. " " .. ns.Get("dotSize") .. " " .. ns.Get("dotRowHeight") .. " "
        .. ns.Get("dotSpacing") .. " " .. ns.Get("dotPerRow") .. " | " .. S[page.strength.value].text .. " "
        .. S[page.size.value].text, "80 40 22 10 2 | 80% 40",
        "every slider sets its own setting, the strength shown in percent")
    page.grow.buttons[2]:Click()
    page.wrap.buttons[2]:Click()
    page.outOfCombat.buttons[3]:Click()
    Equal(ns.Get("dotGrow") .. " " .. ns.Get("dotWrap") .. " " .. ns.Get("dotOutOfCombat") .. " | " .. page.grow.selected
        .. " " .. page.wrap.selected .. " " .. page.outOfCombat.selected, "left up hide | left up hide",
        "every choice sets its own setting and shows the one picked")
    -- Each one says what it does, and none of them is marked.
    local quiet = {}
    for _, name in ipairs(CONTROLS) do
        -- A choice's note is on each of its buttons, as the Resource fill
        -- page's are, since the row itself never takes the mouse.
        local control = page[name]
        local note = Note(control.buttons and control.buttons[1] or control)
        if note == "" or note == "nil" or note:find("experimental", 1, true) or note:find("Needs testing", 1, true) then
            quiet[#quiet + 1] = name
        end
    end
    for _, row in ipairs(page.rows) do
        if Note(row.choice) == "nil" then quiet[#quiet + 1] = row.setting end
    end
    Equal(table.concat(quiet, " "), "", "every control says what it does on hover, and none of them is marked")
    Equal(Note(page.procs):find("the game does not tell addons", 1, true) ~= nil, true,
        "the procs tick says plainly why their damage is never counted")
    -- Out of combat's note says what brings it back, and one of those is an
    -- enemy targeted, which Stay hidden with an enemy targeted (General page)
    -- takes away. So the note changes with that tick rather than saying
    -- something that is no longer true.
    Equal(Note(page.outOfCombat.buttons[1]),
        "Out of combat. It comes back in full in combat, with an enemy targeted, and while this page is open.",
        "Out of combat says a target brings it back")
    ns.Set("oocIgnoreTarget", true)
    Equal(Note(page.outOfCombat.buttons[1]),
        "Out of combat. It comes back in full in combat, and while this page is open.",
        "and with Stay hidden with an enemy targeted ticked it stops saying so, since a target no longer does")
    ns.Set("oocIgnoreTarget", false)
    Equal(#printed, 0, "no errors")
end)()

-- Its page: the two colours -------------------------------------------------------------
-- The band's colour and the line's, each with the colours it may take, Custom
-- and the way back to what it started as.

;(function()
    local ns = Fresh()
    local w, page = Opened(ns)
    page.master:Click()
    Equal(#page.rows .. " " .. page.rows[1].setting .. " " .. page.rows[2].setting, "2 dotBandColour dotLineColour",
        "two colour rows: the band's, then the line's")
    Equal(S[page.rows[1].chosen].text .. " | " .. S[page.rows[2].chosen].text, "Spell's school | White",
        "each says what it is at to start with: the spell's own school for the band, white for the line")
    Equal(#page.rows[1].choice.swatches .. " " .. #page.rows[2].choice.swatches, "7 8",
        "the band takes the spell's school or a bar colour, the line white, black or a bar colour")
    page.rows[1].choice.swatches[2]:Click()
    Equal(ns.Get("dotBandColour") .. " | " .. S[page.rows[1].chosen].text, "orange | Orange", "a colour picked for the band")
    page.rows[1].choice.swatches[2]:Click()
    Equal(ns.Get("dotBandColour") .. " | " .. S[page.rows[1].chosen].text, "default | Spell's school",
        "and clicked again it goes back to the spell's school")
    page.rows[2].choice.swatches[2]:Click()
    Equal(ns.Get("dotLineColour") .. " | " .. S[page.rows[2].chosen].text, "black | Black", "and one for the line")
    -- White and black are not bar colours, and a bar colour lookup answers
    -- orange for a key it does not know, so the line keeps its own two.
    local said = {}
    for _, key in ipairs({ "white", "black", "blue" }) do
        local colour = ns.Dots:Colour("dotLineColour", key)
        said[#said + 1] = ("%s %.2f %.2f %.2f"):format(key, colour[1], colour[2], colour[3])
    end
    Equal(table.concat(said, " | "), "white 1.00 1.00 1.00 | black 0.00 0.00 0.00 | blue 0.24 0.55 0.88",
        "the line's white is white and its black is black, and a bar colour is still that bar colour")
    Equal(("%.2f %.2f %.2f"):format(S[page.rows[2].choice.fill].last.SetColorTexture[1],
        S[page.rows[2].choice.fill].last.SetColorTexture[2], S[page.rows[2].choice.fill].last.SetColorTexture[3]),
        "0.00 0.00 0.00", "and the row's own swatch is painted the colour it stands for")
    -- Custom, kept beside the setting as the look's colours are.
    ns.SetMany(function()
        ns.Set("dotBandColourCustom", "ff8800")
        ns.Set("dotBandColour", ns.CUSTOM)
    end)
    w:Refresh()
    local colour = ns.Dots:Colour("dotBandColour")
    Equal(S[page.rows[1].chosen].text .. " | " .. ns.ColourKey("dotBandColour") .. " | "
        .. ("%.2f %.2f %.2f"):format(colour[1], colour[2], colour[3]),
        "Custom | #ff8800 | 1.00 0.53 0.00", "Custom, its own colour kept beside it and read back as the band's")
    Equal(#printed, 0, "no errors")
end)()

-- The debug report ----------------------------------------------------------------------
-- /ccm debug carries one DoTs line, with what the page cannot show. Never
-- announced to players.

;(function()
    local ns = Fresh()
    ns.Set("dots", true)
    ns.Set("dotBandStrength", 70)
    ns.Dots:Apply() -- as the page's own tick does
    local report = ns.DebugReport()
    local line
    for text in report:gmatch("[^\n]+") do
        if text:sub(1, 6) == "DoTs: " then line = text end
    end
    Equal(line, "DoTs: on true, band true (default, 70%), line true (white), skull true, list true, others false,"
        .. " nameplates false, procs true, page open false, running 0 (no figures yet)",
        "one DoTs line in /ccm debug: what is ticked, each colour, and what is running")
    local second
    for text in report:gmatch("[^\n]+") do
        if text:sub(1, 11) == "DoTs list: " then second = text end
    end
    Equal(second, "DoTs list: made true, container true, slots Moonfire, rows 0, unread false, casts unnamed 0,"
        .. " waiting none | nothing running",
        "and a second line with what the page cannot show: what was made, which spells have a slot of their own, how"
        .. " many casts of yours the game would not name, and each running spell's clock")
    Equal(#printed, 0, "no errors")
end)()

-- The page open and shut ------------------------------------------------------------------
-- The part knows while its page is open, so it can show in full there,
-- whatever the out of combat choice is (Dots.lua PageOpen).

;(function()
    local ns, D = Fresh()
    local w, page = Opened(ns)
    Equal(tostring(D.pageOpen), "true", "the page open: the part knows")
    w:Select("look")
    Equal(tostring(D.pageOpen), "false", "another page taking the window: it knows that too")
    w:Select("dots")
    Equal(tostring(D.pageOpen) .. " " .. tostring(page:IsVisible()), "true true", "and back again")
    w:Hide()
    Equal(tostring(D.pageOpen), "false", "the window shut")
    Equal(#printed, 0, "no errors")
end)()

-- The game the band will be built on ------------------------------------------------------
-- The mock game's own additions, proved here as well as in Tools/TestBars.lua,
-- since this is the file the band, the clock and the list will be written in.

;(function()
    Fresh()
    -- A status bar with the sealed max health as its range and the plain
    -- damage as its value: the game works the share out, as it does for the
    -- real band on the target frame's health bar.
    local band = New("StatusBar")
    band:SetSize(126, 20)
    band:SetStatusBarTexture("flat")
    band:SetReverseFill(true)
    band:SetMinMaxValues(0, UnitHealthMax("target"))
    local fill = band:GetStatusBarTexture()
    band:SetValue(6)
    Equal(("%.2f"):format(S[fill].width), "25.20", "6 damage on a 30 health dummy: a fifth of a 126 wide bar")
    band:SetValue(60)
    Equal(("%.2f"):format(S[fill].width) .. " " .. tostring(Last(band, "SetReverseFill", 1)), "126.00 true",
        "more damage than it has health: the whole bar, filled from its right edge")
    Equal(tostring(IsSecret(UnitHealth("target"))) .. " " .. type(UnitHealth("target")), "true number",
        "health is secret in a fight and out of one, and says it is a number all the same")
    -- Each spell's own text, which is where every figure comes from.
    Equal(C_Spell.GetSpellDescription(172), "Corrupts the target, causing 40 Shadow damage over 12 sec.",
        "Corruption's own text, with the server's number in it")
    Equal(C_Spell.GetSpellDescription(980):find("builds up as the Bane", 1, true) ~= nil, true,
        "Curse of Agony's says in its own words that it ramps")
    -- The combat log, shut: there are no tick, hit, miss or resist events.
    Equal(tostring(C_CombatLog.IsCombatLogRestricted()) .. " " .. tostring(_G.CombatLogGetCurrentEventInfo), "true nil",
        "the combat log is restricted and its reader is gone")
    local driver = New("Frame")
    Equal(pcall(driver.RegisterEvent, driver, "COMBAT_LOG_EVENT_UNFILTERED"), false,
        "registering for it is refused outright, as the game refuses it")
    -- Blizzard's target frame, at the sizes measured in game, and nothing of
    -- ours set on it.
    local frame, health, portrait = TargetFrameGame(true)
    Equal(health:GetWidth() .. " " .. health:GetHeight() .. " " .. portrait:GetWidth(), "126 20 58",
        "its health bar 126 by 20 and its portrait 58 wide")
    Equal(#S[health].points .. " " .. S[health].alpha .. " " .. tostring(S[health].last.SetParent) .. " "
        .. tostring(S[health].last.SetClipsChildren) .. " " .. tostring(S[frame].last.SetFrameLevel),
        "0 1 nil nil nil", "and nothing of ours is set on it: no point, its own alpha, no parent, no clipping, no level")
    TargetFrameGame()
    Equal(_G.TargetFrame, nil, "and it can be taken out of the game again, for the tests the band has to survive")
    Equal(#printed, 0, "no errors")
end)()

-- The list of running spells ---------------------------------------------------------
-- One row per damage over time spell you have running on your target: its
-- icon with the game's own countdown swipe over it, its name, the seconds
-- left and the damage still to come. The icon and its swipe are the secure
-- container's, since that is the only countdown the game allows in a fight;
-- the row's own bar, its seconds and its figure run on the addon's clock,
-- started by UNIT_SPELLCAST_SUCCEEDED for you. The figures themselves are
-- further down this file: the spell these checks use is Moonfire, which the
-- mock game has no text for, so the damage column is empty throughout and the
-- clock is all that is being read here.

-- The part on, as the page's own first tick does it.
local function Start(ns)
    ns.Set("dots", true)
    ns.Dots:Apply()
    return ns.Dots
end

-- Your cast landing: the unit, the cast's GUID, then its spell ID. Hand
-- SECRETS.number as the ID for a cast the game will not name.
local function Cast(id)
    Fire("UNIT_SPELLCAST_SUCCEEDED", "player", nil, id)
end

-- Time passing on the list's own OnUpdate: the game's clock moves, then the
-- frame is drawn again.
local function Tick(D, seconds)
    clock = clock + (seconds or 0)
    local frame = D.ticker
    local run = frame and S[frame].scripts.OnUpdate
    if run then run(frame, seconds or 1 / 30) end
end

-- Whether the DoTs part itself is listening for an event. (Hearing above
-- asks the whole addon, and the Buffs bars' containers hear UNIT_AURA of
-- their own.)
local function Heard(D, event)
    local driver = D.driver
    return driver ~= nil and S[driver].events[event] == true
end

-- What is running, by the addon's own clock: each spell and its seconds left.
local function Clock(D)
    local out = {}
    for _, row in ipairs(D:Rows()) do
        out[#out + 1] = ("%s %s/%s%s"):format(row.name, row.left and ("%.1f"):format(row.left) or "-",
            row.lasts and ("%.0f"):format(row.lasts) or "-", row.guessed and " guessed" or "")
    end
    return #out > 0 and table.concat(out, " | ") or "nothing"
end

-- What a row shows: its name, its seconds, its damage, and its bar's range
-- and value (all plain numbers of ours, never the game's).
local function Row(D, i)
    local row = D.state.rows[i]
    if not row then return "no row" end
    if not row:IsShown() then return "hidden" end
    -- %g, since the clock's seconds are a plain number and 11 and 11.0 are
    -- the same reading.
    local function Num(value)
        return type(value) == "number" and ("%g"):format(value) or tostring(value)
    end
    return ("%s %s [%s] %s-%s/%s"):format(S[row.name].text or "", S[row.time].text or "",
        S[row.damage].text or "", Num(S[row.bar].barMin), Num(S[row.bar].barMax), Num(S[row.bar].barValue))
end

-- An aura of the game's, as the reconcile reads it out of a fight.
local function Aura(id, name, lasts, left, source, stacks)
    return { spellId = id, name = name, duration = lasts, expirationTime = clock + left, applications = stacks,
        sourceUnit = source or "player", points = {} }
end

;(function()
    local ns, D = Fresh()
    Equal(tostring(D.frame) .. " " .. tostring(D.ticker) .. " " .. tostring(#D.state.rows) .. " "
        .. tostring(D.state.container), "nil nil 0 nil",
        "off: no list frame, no clock, no rows and no container of the game's")
    Equal(AuraIndexReads .. " " .. tostring(Heard(D, "UNIT_AURA")), "0 false",
        "and no aura is read and no aura event heard while it is off")
    Start(ns)
    Equal(#D.state.rows .. " " .. tostring(D.frame ~= nil) .. " " .. tostring(D.state.container ~= nil),
        "12 true true", "ticked on: the list frame, its twelve rows and the secure container are made at once")
    Equal(tostring(Heard(D, "UNIT_SPELLCAST_SUCCEEDED")) .. " " .. tostring(Heard(D, "UNIT_AURA")) .. " "
        .. tostring(Hearing("COMBAT_LOG_EVENT_UNFILTERED")), "true true false",
        "your casts and your target's auras are heard, and the combat log never is")
    -- One slot per damage over time spell you know, told which IDs to watch:
    -- the mock character is a druid with Moonfire ranks 1 and 2.
    local slots = S[D.state.container].slots
    local ids = {}
    for id in pairs(slots.d1.filters.includeSpellIDs) do ids[#ids + 1] = id end
    table.sort(ids)
    Equal(D.state.anchors.Moonfire ~= nil and slots.d1.filter .. " " .. tostring(slots.d1.enabled) .. " "
        .. table.concat(ids, ",") .. " " .. tostring(slots.d1.filters.isFromPlayerOrPlayerPet),
        "HARMFUL|PLAYER true 8921,8924,8925,8926,8927,8928,8929,9833,9834,9835 true",
        "one slot for Moonfire, watching every rank of it, yours only (the same IDs the Buffs bars watch for it)")
    Equal(tostring(slots.d1.supplied.SetDurationCooldown ~= nil) .. " " .. tostring(slots.d1.supplied.SetIcon ~= nil) .. " "
        .. tostring(Last(slots.d1.supplied.SetDurationCooldown, "SetHideCountdownNumbers", 1)), "true true true",
        "its icon takes the game's own countdown for the swipe, with the numbers off: the row says the seconds itself")
    Equal(S[D.frame].alpha .. " " .. Row(D, 1), "0 hidden", "and with nothing running the list is right out of sight")
    Equal(#printed, 0, "no errors")
end)()

-- A row is painted by the cast that makes it ----------------------------------------
-- Laying a row out gives it its name and shows it, but its seconds, its bar
-- and its figure all come from the draw, so a row laid out and not drawn is
-- on screen and blank. Squirt read that as the row not appearing at all
-- until he cast something else (27 Nov 2026).

;(function()
    local ns, D = Fresh()
    target, hostile = true, true
    Start(ns)
    Cast(8921) -- Moonfire
    Cast(5570) -- Insect Swarm, while the first is still running
    Equal(Row(D, 2) ~= "hidden" and Row(D, 2) ~= "no row", true,
        "a second cast's own row is showing at once, not waiting for a third")
    Equal(Row(D, 1) .. " / " .. Row(D, 2),
        "Moonfire 12 [] 0-12/12 / Insect Swarm 12 [] 0-12/12",
        "and both rows carry their own spell's name, seconds and bar the moment they are cast")
    Equal(#printed, 0, "no errors")
end)()

-- Your own casts on our own clock -----------------------------------------------------

;(function()
    local ns, D = Fresh()
    target, hostile = true, true
    Start(ns)
    Cast(8921) -- Moonfire rank 1
    Equal(Clock(D), "Moonfire 12.0/12 guessed",
        "a cast of yours starts a row and its clock: Moonfire's own lengths are 9 and 12 over ten ranks, so the longest is"
        .. " taken and marked a guess until its real aura is seen")
    Tick(D, 2)
    Equal(Row(D, 1), "Moonfire 10 [] 0-12/10",
        "two seconds on: the row says ten, its bar has ten of twelve left, and the damage is empty, since the game has"
        .. " no text for Moonfire to read a figure out of")
    Equal(S[D.frame].alpha, 1, "and the list shows, since you are in a fight or have an enemy up")
    Tick(D, 7.5)
    Equal(Row(D, 1), "Moonfire 2.5 [] 0-12/2.5", "under ten seconds it counts in tenths")
    local bar = S[D.state.rows[1].bar].last.SetStatusBarColor
    Equal(("%.2f %.2f %.2f"):format(bar[1], bar[2], bar[3]), "1.00 0.72 0.20",
        "with under three seconds left it goes amber, so you can see it is about to drop off")
    ns.Set("dotAmber", false)
    Tick(D, .1)
    bar = S[D.state.rows[1].bar].last.SetStatusBarColor
    Equal(("%.2f %.2f %.2f"):format(bar[1], bar[2], bar[3]), "0.85 0.80 0.70",
        "unticked, it keeps the band's colour the whole way down")
    -- Cast again before it runs out: the same row starts over.
    Cast(8924)
    Equal(Clock(D), "Moonfire 12.0/12 guessed", "cast again, it starts over in the row it already had")
    Tick(D, 12.1)
    Equal(Clock(D) .. " " .. Row(D, 1) .. " " .. tostring(select(1, D:Drawing())), "nothing hidden false",
        "and once it has run out the row goes and the clock stops with it")
    Equal(AuraIndexReads > 0, true, "the reconcile read the real auras out of the fight (none up: nothing changed)")
    Equal(#printed, 0, "no errors")
end)()

-- A cast the game will not name ----------------------------------------------------------
-- UNIT_SPELLCAST_SUCCEEDED can hand its spell ID back held back (the Buffs
-- bars have had one). Nothing may guess which spell it was and in a fight
-- there is no other way to ask, so that cast is simply not listed, and the
-- debug report counts it so it is never a row that went missing for no
-- reason. Whether the game really does this to a DoT in a fight is not
-- proven: it is handled rather than assumed away.

;(function()
    local ns, D = Fresh()
    target, hostile = true, true
    Start(ns)
    Cast(SECRETS.number)
    Equal(Clock(D) .. " " .. tostring(select(1, D:Drawing())), "nothing false",
        "a cast whose spell ID the game held back is not listed and starts no clock")
    Equal(D.state.sealed, 1, "it is counted instead, for the debug report")
    lockdown = true
    Fire("PLAYER_REGEN_DISABLED")
    Cast(SECRETS.number)
    Cast(8921) -- and a plain one in the same fight
    Equal(Clock(D) .. " " .. D.state.sealed, "Moonfire 12.0/12 guessed 2",
        "in a fight the same: the one it would not name is counted, the one it named is listed")
    lockdown = false
    Equal(#printed, 0, "no errors")
end)()

-- A fight: the game says nothing, and the list runs anyway -----------------------------
-- In a fight every aura index answers nil, on every unit, with any filter, so
-- the whole list is the addon's own clock. Nothing is made, nothing is asked
-- of the container, and nothing is read.

;(function()
    local ns, D = Fresh()
    target, hostile = true, true
    Start(ns)
    local made, calls = S[D.state.container].made, containerCallsInCombat
    lockdown = true
    Fire("PLAYER_REGEN_DISABLED")
    local reads = AuraIndexReads
    Equal(tostring(C_UnitAuras.GetAuraDataByIndex("target", 1, "HARMFUL|PLAYER")), "nil",
        "in a fight the game answers nil for every aura index, as it did in the probe")
    Cast(8921)
    Tick(D, 1)
    Equal(Clock(D) .. " | " .. Row(D, 1), "Moonfire 11.0/12 guessed | Moonfire 11 [] 0-12/11",
        "a DoT cast in a fight is listed and counted down all the same, off your cast alone")
    Equal((AuraIndexReads - reads) .. " " .. (S[D.state.container].made - made) .. " "
        .. (containerCallsInCombat - calls), "1 0 0",
        "and in the fight nothing is made and nothing is asked of the container (the one read is the gate answering nil)")
    Equal(tostring(D.state.pending.slots), "nil", "nothing was waiting for the fight to end")
    lockdown = false
    -- Past the grace a cast gets, since the fight has been going a while by
    -- the time it ends. Inside it the row is left alone on purpose, so that
    -- an aura which answers a moment after the cast does not throw it away.
    Tick(D, 2)
    Fire("PLAYER_REGEN_ENABLED")
    Equal(Clock(D), "nothing",
        "the fight over, the real auras are read and the guess goes: nothing is on the target, so nothing is listed")
    Equal(#printed, 0, "no errors")
end)()

-- Out of a fight: the list put straight against the real auras --------------------------

;(function()
    local ns, D = Fresh()
    target, hostile = true, true
    Start(ns)
    TargetAuras = { Aura(8925, "Moonfire", 12, 7.5, "player"), Aura(5570, "Insect Swarm", 12, 10, "player"),
        Aura(770, "Faerie Fire", 40, 30, "player"), Aura(172, "Corruption", 18, 9, "0xF130") }
    Fire("UNIT_AURA", "target")
    Equal(Clock(D), "Moonfire 7.5/12 | Insect Swarm 10.0/12",
        "out of a fight the real auras are the truth: both DoTs of yours listed with their real lengths, the Faerie Fire"
        .. " that does no damage over time left out and another player's Corruption left out with it")
    Cast(8921)
    Equal(Clock(D), "Moonfire 12.0/12 | Insect Swarm 10.0/12",
        "and a cast after that takes the length the real aura taught it, with no guess left in it")
    -- Past the grace a freshly cast spell gets, so the read below is the
    -- game having had its say rather than answering before the aura landed.
    Tick(D, 2)
    TargetAuras = { Aura(5570, "Insect Swarm", 12, 4, "player") }
    Fire("UNIT_AURA", "target")
    Equal(Clock(D), "Insect Swarm 4.0/12", "a spell the game no longer names has gone, and what is left keeps its clock")
    -- One that stacks: the count is on the aura out of a fight, and it is
    -- kept, since the figure will have to be times the count we last saw.
    TargetAuras = { Aura(5570, "Insect Swarm", 12, 4, "player", 4) }
    Fire("UNIT_AURA", "target")
    Equal(tostring(D:Rows()[1].stacks), "4", "a stack count the game gives out of a fight is kept with the spell")
    -- A read the game refuses leaves the list standing and is tried again a
    -- moment later, a few times at most.
    AuraIndexRefuse = true
    local waiting = #timers
    Fire("UNIT_AURA", "target")
    Equal(Clock(D) .. " " .. tostring(D.state.unread) .. " " .. (#timers - waiting), "Insect Swarm 4.0/12 true 1",
        "a read the game refuses leaves the list as it was and is tried again a moment later, not polled")
    AuraIndexRefuse = false
    -- Fields the game holds back: nothing is listed off them, and nothing
    -- anywhere does sums with one.
    AuraIndexSecret = true
    TargetAuras = { Aura(8925, "Moonfire", 12, 7.5, "player") }
    Fire("UNIT_AURA", "target")
    Equal(Clock(D), "Insect Swarm 4.0/12",
        "fields the game hands back secret are no use to the list, so it stands as it was rather than guessing")
    AuraIndexSecret = false
    Equal(#printed, 0, "no errors")
end)()

-- No target, a new target, and a target that died ---------------------------------------

;(function()
    local ns, D = Fresh()
    target, hostile = true, true
    Start(ns)
    Cast(8921)
    Equal(#D:Rows(), 1, "one spell running on your target")
    TargetAuras = {}
    Fire("PLAYER_TARGET_CHANGED")
    Equal(Clock(D) .. " " .. S[D.frame].alpha, "nothing 0",
        "a new target: what was on the old one is forgotten rather than guessed at, and the list goes")
    Cast(8921)
    target = false
    Fire("PLAYER_TARGET_CHANGED")
    Equal(Clock(D) .. " " .. tostring(Row(D, 1)), "nothing hidden", "and with no target at all there is nothing to list")
    Cast(8921)
    Equal(Clock(D), "nothing", "a cast with no target starts nothing")
    target = true
    Equal(#printed, 0, "no errors")
end)()

-- The rows laid out as chosen ------------------------------------------------------------

;(function()
    local ns, D = Fresh()
    target, hostile = true, true
    Start(ns)
    TargetAuras = { Aura(8925, "Moonfire", 12, 7.5, "player"), Aura(5570, "Insect Swarm", 12, 10, "player") }
    Fire("UNIT_AURA", "target")
    local row, second = D.state.rows[1], D.state.rows[2]
    Equal(S[row].width .. " " .. S[row].height .. " " .. S[row.icon].width .. " " .. S[row.bar].height,
        "172 28 28 14", "a row is its icon, a gap and its bar: 28 icon, 140 bar, 14 high")
    Equal(S[second].points[1][1] .. " " .. S[second].points[1][4] .. " " .. S[second].points[1][5],
        "TOPLEFT 0 -32", "the second row sits under the first, a row and the spacing down")
    ns.Set("dotWrap", "up")
    ns.Set("dotRowHeight", 20)
    ns.Set("dotSize", 36)
    ns.Set("dotSpacing", 6)
    D:Apply()
    Equal(S[row].width .. " " .. S[row].height .. " " .. S[second].points[1][1] .. " " .. S[second].points[1][5],
        "220 36 BOTTOMLEFT 42", "bigger icons and taller rows, and with New rows set to Above the next row sits over it")
    ns.Set("dotPerRow", 1)
    D:Apply()
    Equal(S[second].points[1][4] .. " " .. S[second].points[1][5] .. " " .. S[D.frame].width,
        "226 0 446", "one row per column: the second starts a column beside the first, and the list is two rows wide")
    ns.Set("dotGrow", "left")
    D:Apply()
    Equal(S[D.frame].points[1][1] .. " " .. S[D.frame].points[1][4] .. " " .. S[D.frame].points[1][5], "RIGHT 0 -210",
        "Grow left hangs the list off its right edge, from the spot it was given")
    -- The spell's own icon comes from the container's slot, so its anchor is
    -- what moves to the row.
    local anchor = D.state.anchors.Moonfire
    Equal(S[anchor].points[1][1] .. " " .. tostring(S[anchor].points[1][2] == D.state.rows[1].icon) .. " "
        .. S[anchor].width, "CENTER true 36",
        "the container's own icon for that spell is laid over the row's icon spot, at the size you picked")
    -- End to end: the game puts that spell's aura in the slot, and the slot's
    -- icon comes into sight over the row, with the game's own countdown on it.
    local box = D.state.container
    S[box].Update({ { id = 8925, harmful = true, mine = true } })
    local button = S[box].slots.d1.button
    Equal(tostring(S[button].shown) .. " " .. tostring(Last(button, "SetAllPoints", 1) == anchor) .. " "
        .. tostring(S[box].slots.d1.supplied.SetDurationCooldown ~= nil), "true true true",
        "the game shows that slot's icon over our anchor, and the time on it is the cooldown the game was handed")
    -- A spell with no slot of its own (one a hit set off) shows its own
    -- picture on the row instead, with no swipe.
    Equal(tostring(D.state.anchors["Deep Wound"]), "nil", "a spell that is not in your spellbook has no slot")
    -- Show the damage left and Show countdown numbers each turn off their
    -- own part of a row. The damage sits left of the seconds, and at the
    -- bar's own right edge where the seconds are not shown, since a hidden
    -- font string still takes up its width.
    local at = S[row.damage].points[1]
    Equal(at[1] .. " " .. tostring(at[2] == row.time) .. " " .. at[3] .. " " .. at[4], "RIGHT true LEFT -6",
        "with both on, the damage sits left of the seconds")
    ns.Set("dotTimer", false)
    D:Apply()
    at = S[row.damage].points[1]
    Equal(at[1] .. " " .. tostring(at[2]) .. " " .. tostring(at[3]) .. " " .. tostring(at.n), "RIGHT -3 0 3",
        "the seconds off, the damage takes the bar's own right edge instead of leaving their gap")
    ns.SetMany(function()
        ns.Set("dotTimer", false)
        ns.Set("dotNumbers", false)
    end)
    D:Apply()
    Equal(tostring(S[row.time].shown) .. " " .. tostring(S[row.damage].shown), "false false",
        "both unticked, a row keeps its icon, its name and its bar and says no numbers at all")
    -- List the spells unticked: nothing shows, while the clock behind it
    -- keeps running for the band.
    ns.Set("dotList", false)
    D:Apply()
    Equal(Row(D, 1) .. " " .. S[D.frame].alpha .. " " .. #D:Rows(), "hidden 0 2",
        "List the spells unticked: no row shows and the list is out of sight, and the clock behind it still has both spells")
    Equal(#printed, 0, "no errors")
end)()

-- Out of combat: show, fade or hide ------------------------------------------------------

;(function()
    local ns, D = Fresh()
    target, hostile = true, true
    Start(ns)
    TargetAuras = { Aura(8925, "Moonfire", 12, 7.5, "player") }
    Fire("UNIT_AURA", "target")
    Equal(S[D.frame].alpha, 1, "an enemy targeted: the list shows in full")
    hostile = false
    D:UpdateShown()
    Equal(S[D.frame].alpha, 1, "Show: it stays in full with nothing to attack")
    ns.Set("dotOutOfCombat", "fade")
    D:UpdateShown()
    Equal(S[D.frame].alpha, .3, "Fade: it fades out of combat, as your bars do")
    ns.Set("dotOutOfCombat", "hide")
    D:UpdateShown()
    Equal(S[D.frame].alpha, 0, "Hide: it goes out of sight")
    -- An enemy targeted brings it back, unless Stay hidden with an enemy
    -- targeted is ticked on the General page, which is what the Out of combat
    -- note says on hover (DotsPage.lua) and what Awake reads.
    hostile = true
    D:UpdateShown()
    Equal(S[D.frame].alpha, 1, "Hide, with an enemy targeted: it comes back for the target")
    ns.Set("oocIgnoreTarget", true)
    D:UpdateShown()
    Equal(S[D.frame].alpha, 0, "Stay hidden with an enemy targeted: the target does not bring it back any more")
    ns.Set("oocIgnoreTarget", false)
    hostile = false
    D:UpdateShown()
    D:PageOpen(true)
    Equal(S[D.frame].alpha, 1, "and it comes back in full while its page is open, whatever the choice is")
    D:PageOpen(false)
    lockdown = true
    Fire("PLAYER_REGEN_DISABLED")
    Equal(S[D.frame].alpha, 1, "and in a fight")
    lockdown = false
    Fire("PLAYER_REGEN_ENABLED")
    hostile = true
    Equal(#printed, 0, "no errors")
end)()

-- The ones a hit sets off ---------------------------------------------------------------
-- They are listed and timed, and never counted: their size comes from the hit
-- that caused them, which the game tells addons nothing about. One tick says
-- whether they are listed at all.

;(function()
    local ns, D = Fresh()
    target, hostile = true, true
    Start(ns)
    TargetAuras = { Aura(412609, "Deep Wound", 12, 8, "player") }
    Fire("UNIT_AURA", "target")
    local rows = D:Rows()
    Equal(#rows .. " " .. rows[1].name .. " " .. tostring(rows[1].proc) .. " " .. tostring(rows[1].figure),
        "1 Deep Wound true nil", "one a hit set off is listed and timed, and has no figure of its own to count")
    ns.Set("dotProcs", false)
    D:Apply()
    Fire("UNIT_AURA", "target")
    Equal(Clock(D), "nothing", "unticked, it is not listed at all")
    ns.Set("dotProcs", true)
    D:Apply()
    Equal(Clock(D), "Deep Wound 8.0/12", "and ticked again it is back")
    Equal(#printed, 0, "no errors")
end)()

-- Choose spells: one tick per spell -------------------------------------------------------
-- A spell you never want listed is unticked in its own panel over the window,
-- and what is unticked is kept in your own profile, never in a shared string.

;(function()
    local ns, D = Fresh()
    target, hostile = true, true
    local w, page = Opened(ns)
    page.master:Click()
    Equal(tostring(Last(page.choose, "SetEnabled", 1)) .. " " .. tostring(w.dotsPanel), "true nil",
        "with the list on, Choose spells can be opened, and nothing of its panel is made until it is")
    page.choose:Click()
    local panel = w.dotsPanel
    Equal(tostring(panel ~= nil) .. " " .. tostring(panel:IsShown()), "true true", "it opens over the window")
    Equal(S[panel.rows[1].name].text .. " " .. tostring(panel.rows[1].check:GetChecked()) .. " " .. #panel.rows,
        "Moonfire true 1", "with one row per damage over time spell of yours, every one ticked to start with")
    panel.rows[1].check:Click()
    Equal(tostring(ns.DotListed("Moonfire")) .. " " .. tostring(panel.rows[1].check:GetChecked()), "false false",
        "unticked, Moonfire is left out")
    Cast(8921)
    Equal(Clock(D), "nothing", "so a cast of it starts nothing")
    TargetAuras = { Aura(8925, "Moonfire", 12, 7.5, "player") }
    Fire("UNIT_AURA", "target")
    Equal(Clock(D), "nothing", "and the real aura is not listed either")
    panel.all:Click()
    Equal(tostring(ns.DotListed("Moonfire")) .. " | " .. Clock(D), "true | Moonfire 7.5/12",
        "All of them lists every one again, and the spell that is up comes back at once")
    -- Kept with your character, and in no shared string (Tools/TestShare.lua
    -- holds every DoTs setting out of one).
    D:Pick("Moonfire", false)
    local saved = _G.ForeverEnhancedCooldownManagerDB
    local again, D2 = Fresh(saved)
    Equal(tostring(again.DotListed("Moonfire")) .. " " .. tostring(D2:Pickable()[1].listed), "false false",
        "and it is still unticked after a reload")
    again.SetDotListed("Moonfire", true)
    w:Select("look")
    Equal(tostring(w.dotsPanel:IsShown()), "false", "another page shuts the panel, so nothing of it is left over a page")
    Equal(#printed, 0, "no errors")
end)()

-- The page's status line, once something is running ----------------------------------------

;(function()
    local ns, D = Fresh()
    TargetFrameGame(true)
    target, hostile = true, true
    local w, page = Opened(ns)
    page.master:Click()
    Equal(S[page.status].text, "On. Cast a damage over time spell to see it.", "on, with nothing running")
    Cast(8921)
    w:Refresh()
    Equal(S[page.status].text, "On. 1 spell running.",
        "one spell running, with no damage in the line: the game has no text for Moonfire, so it has no figure")
    TargetAuras = { Aura(8925, "Moonfire", 12, 7.5, "player"), Aura(5570, "Insect Swarm", 12, 10, "player") }
    Fire("UNIT_AURA", "target")
    w:Refresh()
    Equal(S[page.status].text, "On. 2 spells running.", "two of them, and it says spells")
    Equal(#printed, 0, "no errors")
end)()

-- The damage figure: a spell's own text --------------------------------------------------
-- Every number comes out of the spell's own description, which the server has
-- already worked your gear into: Corruption read "40 Shadow damage over 12
-- sec" at 0 spell power and "76" in a +46 spell damage robe on the same
-- character and the same rank. The six strings below are what the game really
-- answered on 26 Nov 2026 (build 1.60.1.71139) and they are the fixtures the
-- parse is held to, Immolate's two part wording and Bane of Agony's ramp
-- wording included. Nothing here is a coefficient of ours, and a text the
-- parse cannot read means no figure at all rather than a number made up.

-- Every pending C_Timer.After callback run, which is how the held re-read
-- after a gear change is made to happen.
local function Settle(from)
    for i = from + 1, #timers do timers[i]() end
    return #timers
end

;(function()
    local _, D = Fresh()
    -- One line per reading: the total, the time it is dealt over, the school
    -- it names and whether its own words say it ramps.
    local function Says(text)
        local reading = D:Parse(text)
        if not reading then return "nothing" end
        return ("%g over %g %s%s"):format(reading.total, reading.lasts, reading.school or "-",
            reading.ramps and " ramps" or "")
    end
    Equal(Says(SpellText[172]), "40 over 12 shadow", "Corruption, as the game wrote it at 0 spell power")
    Equal(Says(SpellText[1400172]), "76 over 12 shadow",
        "the same spell at the same rank in a +46 spell damage robe: the server's own number, never a sum of ours")
    Equal(Says(SpellText[980]), "72 over 24 shadow ramps",
        "Bane of Agony: its own text says the damage is dealt slowly at first and builds up, so it is marked a ramp")
    Equal(Says(SpellText[772]), "15 over 9 -", "Rend, which names no school at all")
    Equal(Says(SpellText[348]), "15 over 15 fire",
        "Immolate: the 15 it deals over 15 sec, not the 11 that lands with the cast and is already dealt, and not the 26")
    Equal(Says(SpellText[1978]), "20 over 15 nature", "Serpent Sting")
    -- Texts with nothing in them to read.
    Equal(Says("Reduces the target's armor by 450 for 30 sec."), "nothing",
        "a debuff that deals no damage over time has no figure")
    Equal(Says("Wounds the target."), "nothing", "and neither has a text with no numbers in it")
    Equal(Says("Deals 200 Shadow damage."), "nothing", "nor one whose damage is not dealt over any time")
    Equal(Says(nil) .. " " .. Says(""), "nothing nothing", "nor nothing at all")
    -- How the game writes numbers and times.
    Equal(Says("causing 1,250 Shadow damage over 20 sec."), "1250 over 20 shadow",
        "a thousands separator is read as one")
    Equal(Says("causing 40,5 damage over 10 sec."), "nothing",
        "a client that writes forty and a half as 40,5 is read as no figure rather than as four hundred and five")
    Equal(Says("causing 12.5 damage over 10 sec."), "12.5 over 10 -", "a decimal point is read")
    Equal(Says("causing 120 Shadow damage over 1 min."), "120 over 60 shadow", "and a time in minutes is read in seconds")
    Equal(Says("causing 30 Frost damage over 12 seconds."), "30 over 12 frost", "as is the word written out")
    -- The other way the game words the same thing, which none of the six
    -- above uses: what one tick deals and how long it keeps ticking.
    Equal(Says("Deals 20 Nature damage every 3 sec for 15 sec."), "100 over 15 nature",
        "the per tick wording is read as its total: five ticks of twenty")
    Equal(Says("Deals 10 damage every 2 sec for 20 sec."), "100 over 20 -", "and the same with no school named")
    -- The school has to be one the band can draw in.
    Equal(Says("causing 40 Chaos damage over 12 sec."), "40 over 12 -",
        "a school the addon has no colour for is read as a figure with no school, not dropped")
    Equal(SpellTextReads, 0, "and none of that asked the game anything: the parse is only ever handed a string")
    Equal(#printed, 0, "no errors")
end)()

-- The figure on our own clock --------------------------------------------------------------
-- The text gives the total and the time, ns.TICK_PERIODS gives how often the
-- spell ticks, and our clock gives how much of its time is left: the figure is
-- the ticks still to come times what each one deals. Corruption's own text
-- says 40 over 12 sec and its period is 3, so four ticks of ten.

;(function()
    local ns, D = Fresh()
    target, hostile = true, true
    Start(ns)
    Cast(172) -- Corruption rank 1, the spell the probe measured
    Equal(Clock(D), "Corruption 12.0/12",
        "its own text says over 12 sec, so the clock takes 12 from the text and nothing is a guess")
    Equal(D:Ticks("Corruption", 12) .. " ticks", "4 ticks", "12 sec at a tick every 3 is four ticks")
    Tick(D, 2)
    Equal(Row(D, 1), "Corruption 10 [40] 0-12/10",
        "two seconds on, with all four ticks still to come: the whole 40 is still to be dealt")
    Tick(D, 2)
    Equal(Row(D, 1), "Corruption 8.0 [30] 0-12/8", "the first tick landed: three of four left, so 30")
    Tick(D, 3)
    Equal(Row(D, 1), "Corruption 5.0 [20] 0-12/5", "then two")
    Tick(D, 3)
    Equal(Row(D, 1), "Corruption 2.0 [10] 0-12/2", "then the last one")
    Equal(select(1, D:Band()) .. " " .. tostring(select(2, D:Band())), "10 shadow",
        "and the band's own figure is the same 10, to be drawn in the school the text named")
    local band = D:Colour("dotBandColour")
    Equal(("%.2f %.2f %.2f"):format(band[1], band[2], band[3]), "0.58 0.35 0.85",
        "which is the shadow colour, since the band's colour is Default")
    Tick(D, 2.1)
    Equal(Clock(D) .. " " .. tostring(select(1, D:Band())), "nothing nil", "run out, there is nothing left to deal")
    Equal(#printed, 0, "no errors")
end)()

-- The same, on the two spells whose text is the awkward shape ------------------------------
-- Immolate's text names two figures, and only the second is dealt over time:
-- the first lands with the cast and is already dealt by the time anything here
-- looks, so counting it would mark damage on the health bar that is never
-- coming. Rend's names no school at all.

;(function()
    local ns, D = Fresh()
    target, hostile = true, true
    Start(ns)
    Cast(348) -- Immolate rank 1: "11 Fire damage and then an additional 15 Fire damage over 15 sec."
    local row = D:Rows()[1]
    Equal(("%s %s over %s %s"):format(row.name, tostring(row.figure), tostring(row.lasts), tostring(row.school)),
        "Immolate 15 over 15 fire", "the 15 it deals over 15 sec, not the 11 that lands with the cast and not the 26")
    Tick(D, 6)
    Equal(D:Rows()[1].figure, 9, "15 at a tick every 3 is five ticks of three, and six seconds on three are left")
    Cast(772) -- Rend rank 1: "15 damage over 9 sec", with no school in it
    local said = {}
    for _, each in ipairs(D:Rows()) do said[#said + 1] = each.name .. " " .. tostring(each.figure) end
    Equal(table.concat(said, " | "), "Immolate 9 | Rend 15", "Rend beside it, costed off a text that names no school")
    Equal(select(1, D:Band()) .. " " .. tostring(select(2, D:Band())), "24 nil",
        "the band counts both, and the school is the one the biggest share is dealt in: Rend's 15, which names none")
    local band = D:Colour("dotBandColour")
    Equal(("%.2f %.2f %.2f"):format(band[1], band[2], band[3]), "0.85 0.80 0.70",
        "so the band draws the plain physical colour, which is what Default has always shown with nothing running")
    D:Pick("Rend", false)
    Equal(select(1, D:Band()) .. " " .. tostring(select(2, D:Band())), "9 fire",
        "and with Rend unticked the band is Immolate's alone, in its own fire")
    Equal(#printed, 0, "no errors")
end)()

-- What the text teaches the clock ----------------------------------------------------------
-- A spell's text says how long that rank lasts, and the game wrote it for the
-- exact rank cast, so it beats anything the addon can work out from a table of
-- lengths. Corruption has three lengths over seven ranks, so without its text
-- the longest would be taken and marked a guess.

;(function()
    local ns, D = Fresh()
    target, hostile = true, true
    SpellText[172] = nil
    Start(ns)
    Cast(172)
    Equal(Clock(D) .. " " .. tostring(D:Rows()[1].figure), "Corruption 18.0/18 guessed nil",
        "with no text for it the clock falls back to the longest length its ranks have, marked a guess, and there is no"
        .. " figure at all: nothing is guessed from its rank or its school")
    Equal(Row(D, 1):find("%[%]") ~= nil, true, "so the row lists and times it with its damage column empty")
    Equal(#printed, 0, "no errors")
end)()

-- A spell that says it ramps ---------------------------------------------------------------
-- Bane of Agony's own text says the damage is dealt slowly at first and builds
-- up. Nothing in the text says how steep that is, so the figure is the total's
-- share of the time left and the page says in plain words that the figure is a
-- total rather than an even spread.

;(function()
    local ns, D = Fresh()
    target, hostile = true, true
    Start(ns)
    Cast(980) -- Curse of Agony, which Forever calls Bane of Agony
    local row = D:Rows()[1]
    Equal(("%s %s %s %s"):format(row.name, tostring(row.figure), tostring(row.ramps), tostring(row.lasts)),
        "Bane of Agony 72 true 24", "listed, timed and costed on its total, and marked a ramp")
    Tick(D, 12)
    Equal(D:Rows()[1].figure, 36, "half its time gone, half its total left: the share of the total, not a curve of ours")
    Equal(#printed, 0, "no errors")
end)()

-- A spell that stacks ----------------------------------------------------------------------
-- Its text is one application's worth, and the count is only on the aura out
-- of a fight, so the figure is times the count we last saw.

;(function()
    local ns, D = Fresh()
    target, hostile = true, true
    -- Shaped like the game's own wording for a stacking poison. The figure is
    -- not a measurement: what is measured here is that the count multiplies
    -- whatever the text says.
    SpellText[2818] = "Coats a weapon with poison, causing 12 Nature damage over 12 sec. Stacks up to 5 times."
    Start(ns)
    TargetAuras = { Aura(2818, "Deadly Poison", 12, 12, "player", 5) }
    Fire("UNIT_AURA", "target")
    local row = D:Rows()[1]
    Equal(("%s %s x%s"):format(row.name, tostring(row.figure), tostring(row.stacks)), "Deadly Poison 60 x5",
        "five stacks of a text that says 12: 60 still to deal")
    TargetAuras = { Aura(2818, "Deadly Poison", 12, 12, "player", 2) }
    Fire("UNIT_AURA", "target")
    Equal(D:Rows()[1].figure, 24, "and the figure follows the count down again")
    Equal(#printed, 0, "no errors")
end)()

-- The ones a hit sets off are never costed -------------------------------------------------
-- Deep Wound and its kin come from a hit, and their size is a share of that
-- hit, which the game tells addons nothing about. They are listed and timed,
-- and never costed, whatever their own text happens to say.

;(function()
    local ns, D = Fresh()
    target, hostile = true, true
    SpellText[12721] = "Wounds the target causing them to bleed for 60 damage over 12 sec."
    Start(ns)
    TargetAuras = { Aura(12721, "Deep Wound", 12, 12, "player"), Aura(172, "Corruption", 12, 12, "player") }
    Fire("UNIT_AURA", "target")
    local said = {}
    for _, row in ipairs(D:Rows()) do said[#said + 1] = row.name .. " " .. tostring(row.figure) end
    Equal(table.concat(said, " | "), "Deep Wound nil | Corruption 40",
        "Deep Wound is listed and timed with no figure even though its text names one, and Corruption beside it is costed")
    Equal(select(1, D:Band()), 40, "so the band counts only the 40: nothing a hit set off is ever in it")
    Equal(#printed, 0, "no errors")
end)()

-- In a fight the text is never asked for ---------------------------------------------------
-- Your own stats are sealed in a fight, so every figure a fight needs has to
-- have been read before it. What was read stands; what was not is listed with
-- no figure until the fight ends.

;(function()
    local ns, D = Fresh()
    target, hostile = true, true
    Start(ns)
    Cast(172)
    Equal(D:Rows()[1].figure, 40, "out of the fight, Corruption's text is read and its figure is 40")
    lockdown = true
    Fire("PLAYER_REGEN_DISABLED")
    local reads = SpellTextReads
    Cast(172)
    Tick(D, 1)
    Equal(D:Rows()[1].figure .. " " .. (SpellTextReads - reads), "40 0",
        "cast again in the fight it is costed off the reading already kept, and the game is not asked once")
    -- One it never read: no figure in the fight, and it says so rather than
    -- guessing from the rank.
    Cast(772) -- Rend, which this character has never had read
    Tick(D, 1)
    local said = {}
    for _, row in ipairs(D:Rows()) do said[#said + 1] = row.name .. " " .. tostring(row.figure) end
    Equal(table.concat(said, " | ") .. " " .. (SpellTextReads - reads), "Corruption 40 | Rend nil 0",
        "a spell whose text was never read has no figure in a fight, and the game is still not asked")
    Equal(tostring(D.state.pending.figures), "true", "it is held over for the fight's end instead")
    TargetAuras = { Aura(772, "Rend", 9, 5, "player") }
    lockdown = false
    Fire("PLAYER_REGEN_ENABLED")
    Equal(D:Rows()[1].name .. " " .. tostring(D:Rows()[1].figure) .. " " .. tostring(D.state.pending.figures),
        "Rend 10 nil", "the fight over, its text is read and the figure lands: 15 over 9 sec is three ticks of five, two left")
    Equal(#printed, 0, "no errors")
end)()

-- Your gear changed, so the figures did ---------------------------------------------------
-- The server works your gear into the text itself, so the only way to follow a
-- +46 spell damage robe is to read every text again. Out of a fight only.

;(function()
    local ns, D = Fresh()
    target, hostile = true, true
    Start(ns)
    Cast(172)
    Equal(D:Rows()[1].figure, 40, "40 at 0 spell power")
    -- The same spell and rank read again in the robe, which is the second
    -- string the probe measured.
    SpellText[172] = SpellText[1400172]
    local waiting = #timers
    Fire("PLAYER_EQUIPMENT_CHANGED")
    Equal(D:Rows()[1].figure .. " " .. (#timers - waiting), "76 1",
        "the robe on, every figure is read again: 76, and the re-read of the rest is held for a moment rather than done"
        .. " once per slot")
    Settle(waiting)
    Equal(D:Rows()[1].figure, 76, "and it stands after the held re-read")
    -- In a fight a change waits: what was read is better than nothing.
    lockdown = true
    Fire("PLAYER_REGEN_DISABLED")
    SpellText[172] = SpellText[1400172] .. " "
    Fire("PLAYER_EQUIPMENT_CHANGED")
    Equal(D:Rows()[1].figure .. " " .. tostring(D.state.pending.stale), "76 true",
        "a weapon swapped in the fight leaves the figures already read standing, and holds the re-read over")
    SpellText[172] = SpellText[172]:gsub("76", "90")
    lockdown = false
    TargetAuras = { Aura(172, "Corruption", 12, 12, "player") }
    Fire("PLAYER_REGEN_ENABLED")
    Equal(D:Rows()[1].figure .. " " .. tostring(D.state.pending.stale), "90 nil",
        "and the fight over it is read again and follows")
    Equal(#printed, 0, "no errors")
end)()

-- A client that will not hand the description over -----------------------------------------
-- C_TooltipInfo.GetSpellByID answers the same text on this client, so it is
-- the fallback: the description held back or refused is not the end of it.
-- Nothing is ever read out of a secret, and the tooltip's lines are walked
-- inside one pcall, since a table the game holds back cannot be looked
-- through at all.

;(function()
    local ns, D = Fresh()
    target, hostile = true, true
    local described = _G.C_Spell.GetSpellDescription
    _G.C_Spell.GetSpellDescription = function() return nil end
    Start(ns)
    Cast(172)
    Equal(D:Rows()[1].figure, 40, "no description at all: the figure comes off the tooltip reader's own lines")
    _G.C_Spell.GetSpellDescription = described
end)()

;(function()
    local ns, D = Fresh()
    target, hostile = true, true
    SpellTextSecret = true
    Start(ns)
    Cast(172)
    Equal(D:Rows()[1].figure .. " " .. tostring(SecretMisuse[1]), "40 nil",
        "a description the client keeps secret is passed over for the tooltip reader, and nothing is read out of the secret")
    SpellTextSecret = false
    Equal(#printed, 0, "no errors")
end)()

-- An ask the game refuses, tried a few times and then left alone ---------------------------
-- Never polled. The same few tries the aura reconcile allows itself.

;(function()
    local ns, D = Fresh()
    target, hostile = true, true
    Start(ns)
    local tip = _G.C_TooltipInfo.GetSpellByID
    SpellTextRefuse = true
    _G.C_TooltipInfo.GetSpellByID = function() error("the game refused") end
    local reads = SpellTextReads
    Cast(772)
    for _ = 1, 10 do D:Rows() end
    Equal((SpellTextReads - reads) .. " " .. tostring(D.state.asks[772]) .. " " .. tostring(D:Rows()[1].figure),
        "3 3 nil", "ten asks for the same figure: the game is asked three times and then left alone, with no figure")
    SpellTextRefuse = false
    _G.C_TooltipInfo.GetSpellByID = tip
    Equal(#printed, 0, "no errors")
end)()

;(function()
    local ns, D = Fresh()
    target, hostile = true, true
    SpellText[772] = "Wounds the target, leaving it bleeding."
    Start(ns)
    local reads = SpellTextReads
    Cast(772)
    for _ = 1, 10 do D:Rows() end
    Equal((SpellTextReads - reads) .. " " .. tostring(D:Rows()[1].figure), "1 nil",
        "a text the game does hand over with no figure in it is read once and never asked for again")
    Equal(#printed, 0, "no errors")
end)()

-- A figure is never raised above what the text paid for -----------------------------------
-- A talent or a combo point can make the aura last longer than the text says,
-- which deals more ticks than the text counted. How much more is not in the
-- text, so the ticks still to come stop at the ticks the text paid for.

;(function()
    local ns, D = Fresh()
    target, hostile = true, true
    Start(ns)
    TargetAuras = { Aura(772, "Rend", 21, 21, "player") }
    Fire("UNIT_AURA", "target")
    local row = D:Rows()[1]
    Equal(("%s %s/%s %s"):format(row.name, ("%g"):format(row.left), ("%g"):format(row.lasts), tostring(row.figure)),
        "Rend 21/21 15", "its aura lasts 21 where its text says 9: the clock follows the aura and the figure stops at 15")
    Equal(#printed, 0, "no errors")
end)()

-- The status line and the debug report ------------------------------------------------------

;(function()
    local ns, D = Fresh()
    target, hostile = true, true
    local w, page = Opened(ns)
    page.master:Click()
    Cast(172)
    w:Refresh()
    Equal(S[page.status].text, "On. 1 spell running, 40 damage to come.", "one spell, and what it still has to deal")
    Cast(772)
    w:Refresh()
    Equal(S[page.status].text, "On. 2 spells running, 55 damage to come.", "two of them, added up")
    -- One with no figure beside one with: the line says what it knows.
    Cast(8921)
    w:Refresh()
    Equal(S[page.status].text, "On. 3 spells running, 55 damage to come.",
        "and a spell with no figure is still running: it is counted in the spells and not in the damage")
    local said = {}
    D:Report(function(line) said[#said + 1] = line end)
    Equal(said[2]:find("asks ", 1, true) ~= nil and said[2]:find("Corruption 40 over 12 in 4 ticks shadow", 1, true) ~= nil
        and said[2]:find("Moonfire no figure", 1, true) ~= nil, true,
        "and /ccm debug says what each spell's own text gave: the total, the time, the ticks and the school, or no figure")
    Equal(#printed, 0, "no errors")
end)()

-- Your own spells read once, and not once per change ---------------------------------------
-- A fight needs every figure already read, so every rank of every damage over
-- time spell of yours is read as the part goes on. The page calls D:Apply on
-- every tick and every step of a slider, so that pass may not happen again
-- until something changes the numbers.

;(function()
    local ns, D = Fresh()
    target, hostile = true, true
    Start(ns)
    local reads = SpellTextReads
    Equal(tostring(reads > 0) .. " " .. tostring(D.state.warmed), "true true",
        "ticked on, every rank of every damage over time spell of yours is read at once, out of the fight")
    for _ = 1, 5 do D:Apply() end
    Equal(SpellTextReads - reads, 0, "and a change on the page does not read the lot again")
    ns.Set("dots", false)
    D:Apply()
    Equal((SpellTextReads - reads) .. " " .. tostring(next(D.state.readings)) .. " " .. tostring(D.state.warmed),
        "0 nil nil", "switching it off reads nothing and throws every reading away, since a gear change while it is off"
        .. " is never heard and the figures would be a session out of date")
    ns.Set("dots", true)
    D:Apply()
    Equal(tostring(SpellTextReads > reads) .. " " .. tostring(D.state.warmed), "true true",
        "and ticking it back on reads them all again")
    reads = SpellTextReads
    -- A spell learned, which comes through the same re-read as a gear change.
    -- Shaped like Immolate's measured two part wording, which is the shape
    -- Moonfire's own text has; the figures in it are not a measurement.
    SpellText[8921] = "Burns the enemy for 9 Arcane damage and then an additional 12 Arcane damage over 9 sec."
    local waiting = #timers
    Fire("SPELLS_CHANGED")
    Equal(tostring(D.state.warmed) .. " " .. tostring(next(D.state.readings)), "nil nil",
        "a spell learned throws every reading away and holds the re-read for a moment")
    Settle(waiting)
    Equal(tostring(D.state.warmed), "true", "then reads them all again")
    Cast(8921)
    Equal(Clock(D) .. " " .. tostring(D:Rows()[1].figure), "Moonfire 9.0/9 12",
        "and Moonfire has a figure and a length of its own now: the 12 it deals over 9 sec, in three ticks of four")
    Equal(#printed, 0, "no errors")
end)()

-- Nothing is read while it is off ------------------------------------------------------------

;(function()
    local ns, D = Fresh()
    target, hostile = true, true
    Equal(SpellTextReads .. " " .. tostring(next(D.state.readings)), "0 nil",
        "off, no spell's text is ever asked for")
    local w = Opened(ns)
    w:Refresh()
    Equal(SpellTextReads, 0, "and opening its page reads none either: the page's preview is its own")
    Equal(#printed, 0, "no errors")
end)()

-- The band on your target's health bar ------------------------------------------------------
-- What the band is: our own clipping frame on Blizzard's health bar with one
-- status bar of ours inside it, as wide as the whole health bar, its right
-- edge on the health's own fill and filling backwards from there. Its range
-- is the target's sealed max health and its value is the plain damage still
-- to come, so the game works out how far it reaches and the addon never
-- learns the number. Nothing of Blizzard's is written to anywhere in it.

-- The band's own OnUpdate, a step at a time: the game's clock moves, then the
-- band is drawn again. (A global: this file's main chunk is at Lua's 200
-- locals.)
function BandTick(B, seconds)
    clock = clock + (seconds or 0)
    local frame = B.ticker
    local run = frame and S[frame].scripts.OnUpdate
    if run then run(frame, seconds or 1 / 30) end
end

-- What the band handed the game and what the game drew from it: whether the
-- range it was given is sealed, the numbers behind it, the plain damage as
-- its value, and how wide the game made the band's own fill texture. The
-- addon reads none of this; the mock game is the game here, and it is the one
-- doing the division.
function BandAt(parts)
    if not parts then return "no band" end
    local s = S[parts.band]
    return ("%s %s-%s/%s fill %.2f of %s"):format(IsSecret(s.barMax) and "sealed" or "open",
        tostring(Behind(s.barMin)), tostring(Behind(s.barMax)), tostring(s.barValue),
        S[parts.mark].width, tostring(s.width))
end

-- Whether the band itself is listening for an event. (Hearing, above, asks
-- the whole mock game, which still holds every frame every earlier check in
-- this file made.)
function BandHears(B, event)
    local driver = B.driver
    return driver ~= nil and S[driver].events[event] == true
end

-- How much of the skull the gate lets through, which is the other sum the
-- game does and the addon never sees: the skull's bar is full when the damage
-- has reached the health your target has left, and its own fill stands two
-- past the portrait's far edge at that point, so what is clear of the
-- portrait is the fill less the room before the portrait starts. (The two is
-- DotsBand.lua's SKULL_OVER.)
function SkullAt(parts, portrait)
    if not parts or not parts.reach then return "no skull" end
    local wide, over = portrait:GetWidth(), 2
    local clear = S[parts.reach:GetStatusBarTexture()].width - (S[parts.reach].width - wide - over)
    if clear < 0 then clear = 0 end
    if clear > wide then clear = wide end
    return ("%.0f of %s shown %s"):format(clear, wide, tostring(S[parts.skull].shown))
end

-- Off: nothing of it is made at all, with Blizzard's target frame sitting
-- right there.
;(function()
    local ns, D, B = Fresh()
    local frame, health = TargetFrameGame(true)
    Equal(tostring(B.started) .. " " .. tostring(B.wanted) .. " " .. tostring(B:Parts()) .. " "
        .. tostring(B:PlateParts()) .. " " .. tostring(B.driver) .. " " .. tostring(B:Drawing()),
        "true false nil nil nil false",
        "off: the band is started and has made nothing, hears nothing and draws nothing")
    Equal(tostring(BandHears(B, "PLAYER_TARGET_CHANGED")) .. " " .. tostring(BandHears(B, "UNIT_HEALTH")) .. " "
        .. tostring(BandHears(B, "NAME_PLATE_UNIT_ADDED")), "false false false",
        "and nothing is heard while it is off: not your target changing, its health, or a nameplate coming up")
    Equal(#S[health].points .. " " .. tostring(S[health].kids) .. " " .. tostring(next(S[frame].last)), "0 nil nil",
        "nothing has been put on Blizzard's health bar and nothing set on its frame")
    Equal(#printed, 0, "no errors")
end)()

-- Ticked on: the layers, and nothing of Blizzard's touched ------------------------------------

;(function()
    local ns, D, B = Fresh()
    local frame, health, portrait = TargetFrameGame(true)
    target, hostile = true, true
    Start(ns)
    local parts = B:Parts()
    -- A bar a player can see is hung off directly, which is the plain way
    -- and the way a nameplate needs: pulling the band out of the plate by
    -- parent and strata stops it drawing at all, however right every number
    -- looks (27 Nov 2026, Plater). The climb to the parent is only for a bar
    -- that is hidden, which is the next check down.
    Equal(tostring(parts ~= nil) .. " " .. tostring(B:Found()) .. " " .. S[parts.clip].kind .. " "
        .. tostring(S[parts.clip].parent == health) .. " " .. tostring(S[parts.clip].parent == frame) .. " "
        .. tostring(Last(parts.clip, "SetClipsChildren", 1)) .. " "
        .. tostring(Last(parts.clip, "SetFrameLevel", 1)), "true true Frame true false true 7",
        "a visible bar: the clipping frame hangs off the bar itself, clipping, six levels up")
    Equal(S[parts.band].kind .. " " .. tostring(S[parts.band].parent == parts.clip) .. " " .. S[parts.band].width
        .. " " .. health:GetWidth() .. " " .. tostring(Last(parts.band, "SetReverseFill", 1)), "StatusBar true 126 126 true",
        "with one status bar of ours in it, as wide as the whole health bar, filling from its right edge back")
    local fill, said = health:GetStatusBarTexture(), {}
    for _, point in ipairs(S[parts.band].points) do
        local to = point[2]
        said[#said + 1] = point[1] .. "=" .. (to == fill and "health fill" or to == parts.clip and "clip" or "?")
    end
    Equal(table.concat(said, " "), "TOP=clip BOTTOM=clip RIGHT=health fill",
        "pinned top and bottom to the clip and by its right edge to the health's own fill, so the band always starts"
        .. " where the health ends and nothing is ever worked out from where that is")
    local marks = {}
    for _, point in ipairs(S[parts.line].points) do
        marks[#marks + 1] = point[1] .. "=" .. (point[2] == parts.mark and "band fill" or "?")
    end
    Equal(table.concat(marks, " ") .. " " .. S[parts.line].width .. " " .. tostring(S[parts.line].shown),
        "TOPLEFT=band fill BOTTOMLEFT=band fill 2 false",
        "and the bright line on the band's own fill texture's left edge, out of sight until there is something to mark")
    -- The skull's group, on our own frame over the portrait.
    Equal(tostring(S[parts.holder].parent == frame) .. " " .. tostring(S[parts.reach].parent == parts.holder) .. " "
        .. tostring(Last(parts.gate, "SetClipsChildren", 1)) .. " " .. S[parts.reach].width .. " "
        .. S[parts.skull].texture:sub(-9), "true true true 2520 Skull.tga",
        "the skull's own group over the portrait: a bar of ours twenty health bars wide for the game to measure on,"
        .. " a clipping frame of ours, and our own skull in it")
    -- Nothing of Blizzard's is set, and no key of ours is written onto it.
    Equal(#S[health].points .. " " .. S[health].alpha .. " " .. tostring(S[health].shown) .. " "
        .. tostring(S[health].last.SetParent) .. " " .. tostring(S[health].last.SetClipsChildren) .. " "
        .. tostring(S[health].last.SetFrameLevel) .. " " .. tostring(S[health].last.SetScale),
        "0 1 true nil nil nil nil",
        "nothing of Blizzard's health bar is set: no point, its own alpha, shown, no parent, no clipping, no level,"
        .. " no scale")
    Equal(#S[frame].points .. " " .. S[frame].alpha .. " " .. tostring(next(S[frame].last)) .. " "
        .. #S[portrait].points .. " " .. tostring(next(S[portrait].last)), "0 1 nil 0 nil",
        "and nothing of the frame itself or its portrait either")
    local keys = {}
    for key in pairs(frame) do keys[#keys + 1] = tostring(key) end
    table.sort(keys)
    Equal(table.concat(keys, " ") .. " | " .. tostring(next(health)), "healthbar portrait | nil",
        "no key of ours was written onto the frame or its health bar: only the game's own two are there")
    Equal(#printed, 0, "no errors")
end)()

-- The number: the game does the division ------------------------------------------------------
-- The band's range is the target's sealed max health and its value is the
-- plain damage still to come, which is the reverse of the Resource fill's
-- gauges. Several spells at once are one band.

;(function()
    local ns, D, B = Fresh()
    local _, health = TargetFrameGame(true)
    target, hostile = true, true
    Health.target, HealthMax.target = 100, 100
    Start(ns)
    local parts = B:Parts()
    Equal(BandAt(parts) .. " | " .. tostring(B:Drawing()), "sealed 0-100/0 fill 0.00 of 126 | false",
        "nothing running: the band has nothing to mark and runs no frame of its own")
    Cast(172) -- Corruption: 40 Shadow over 12 sec, four ticks of ten
    Equal(BandAt(parts) .. " | " .. tostring(B:Drawing()) .. " " .. S[parts.clip].alpha,
        "sealed 0-100/40 fill 50.40 of 126 | true 1",
        "40 damage to come on a 100 health target: the game lays the band two fifths of the way across the bar,"
        .. " and nothing here divided anything")
    Cast(772) -- Rend: 15 damage over 9 sec, three ticks of five
    Equal(BandAt(parts), "sealed 0-100/55 fill 69.30 of 126", "two spells running are one band: 55 of the 100")
    BandTick(B, 3)
    Equal(BandAt(parts), "sealed 0-100/40 fill 50.40 of 126",
        "three seconds on, Corruption has three of its four ticks left and Rend two of three: 30 and 10")
    BandTick(B, 9.1)
    Equal(BandAt(parts) .. " | " .. tostring(B:Drawing()) .. " " .. S[parts.clip].alpha .. " "
        .. tostring(S[parts.line].shown), "sealed 0-100/0 fill 0.00 of 126 | false 0 false",
        "and once they have run out the band goes, its line with it, and its clock stops")
    Equal(#printed, 0, "no errors")
end)()

-- Its colour, and the strength slider ----------------------------------------------------------

;(function()
    local ns, D, B = Fresh()
    TargetFrameGame(true)
    target, hostile = true, true
    Start(ns)
    local parts = B:Parts()
    Cast(172) -- Corruption, which its own text says is Shadow
    local paint = S[parts.band].last.SetStatusBarColor
    Equal(("%.2f %.2f %.2f %.2f"):format(paint[1], paint[2], paint[3], paint[4]), "0.58 0.35 0.85 0.55",
        "the band draws in the school the damage is dealt in, at the strength the slider is at")
    ns.Set("dotBandStrength", 100)
    D:Apply()
    paint = S[parts.band].last.SetStatusBarColor
    Equal(("%.2f"):format(paint[4]), "1.00", "the strength all the way up: the band's colour is solid over the health")
    ns.Set("dotBandStrength", 20)
    D:Apply()
    paint = S[parts.band].last.SetStatusBarColor
    Equal(("%.2f"):format(paint[4]), "0.20", "and all the way down: the health shows through it")
    ns.Set("dotBandColour", "orange")
    D:Apply()
    paint = S[parts.band].last.SetStatusBarColor
    local want = ns.Style:BarColour("orange")
    Equal(("%.2f %.2f %.2f"):format(paint[1], paint[2], paint[3]),
        ("%.2f %.2f %.2f"):format(want[1], want[2], want[3]), "a colour of your own is what the band draws in instead")
    Equal(("%.2f %.2f %.2f"):format(S[parts.line].tint[1], S[parts.line].tint[2], S[parts.line].tint[3]) .. " "
        .. tostring(S[parts.line].shown), "1.00 1.00 1.00 true", "the line is white to start with, and shows with the band")
    ns.Set("dotLineColour", "black")
    D:Apply()
    Equal(("%.2f %.2f %.2f"):format(S[parts.line].tint[1], S[parts.line].tint[2], S[parts.line].tint[3]), "0.00 0.00 0.00",
        "and takes a colour of its own")
    ns.Set("dotLine", false)
    D:Apply()
    Equal(tostring(S[parts.line].shown) .. " " .. S[parts.clip].alpha, "false 1",
        "unticked, the line goes and the band stays")
    Equal(#printed, 0, "no errors")
end)()

-- The skull on the portrait --------------------------------------------------------------------
-- Whether the band covers the rest of the health is a comparison nothing in
-- the addon may make, since the health is a secret. The game makes it: the
-- skull's bar is full the moment the damage reaches the health, and a
-- clipping frame of ours rides that fill's own edge.

;(function()
    local ns, D, B = Fresh()
    local _, _, portrait = TargetFrameGame(true)
    target, hostile = true, true
    Start(ns)
    local parts = B:Parts()
    Equal(SkullAt(parts, portrait), "0 of 58 shown false", "nothing running: no skull at all")
    -- A 30 health dummy with 40 damage coming: more than it has, at full
    -- health, which is the case a share of its max health would have missed.
    Cast(172)
    Equal(SkullAt(parts, portrait) .. " " .. S[parts.holder].alpha, "58 of 58 shown true 1",
        "40 damage coming on a 30 health target at full health: the whole skull, since the band covers everything")
    BandTick(B, 6)
    Equal(SkullAt(parts, portrait) .. " " .. S[parts.holder].alpha, "0 of 58 shown true 1",
        "six seconds on, 20 of the 40 is still coming and the target has 30: the skull is clipped right away again")
    -- The target hurt down to under what is still coming.
    Health.target = 18
    Fire("UNIT_HEALTH", "target")
    Equal(SkullAt(parts, portrait), "58 of 58 shown true",
        "the target down to 18 with 20 still coming: the skull stands clear again, and the addon never compared them")
    Health.target = 21
    Fire("UNIT_HEALTH", "target")
    Equal(SkullAt(parts, portrait), "0 of 58 shown true", "healed back past it, and it goes")
    Health.target = 20.4
    Fire("UNIT_HEALTH", "target")
    Equal(SkullAt(parts, portrait), "11 of 58 shown true",
        "and a hair short of it, part of the skull: it wipes in over the last fortieth rather than appearing at once")
    ns.Set("dotSkull", false)
    D:Apply()
    Equal(tostring(S[parts.skull].shown) .. " " .. S[parts.holder].alpha .. " " .. S[parts.clip].alpha, "false 0 1",
        "unticked, the skull goes and the band stays")
    Equal(#printed, 0, "no errors")
end)()

-- What the skull is made of, and why none of it is ever hidden ----------------------------------
-- The group is built with the band, out of a fight, whether its tick is on or
-- not, so ticking it on in a fight has everything it needs already. And it is
-- put out by alpha rather than hidden: a frame the game is not showing never
-- gets a layout pass at all, so hiding the group would stop its geometry
-- following the health and the reveal would freeze where it was. The reveal
-- itself is three anchors and one range: the bar's right edge two past the
-- portrait's far edge, a clipping frame of ours riding that bar's own fill,
-- and the skull on the portrait's own rect.

;(function()
    local ns, D, B = Fresh()
    local frame, _, portrait = TargetFrameGame(true)
    target, hostile = true, true
    ns.Set("dotSkull", false)
    Start(ns)
    local parts = B:Parts()
    Equal(tostring(parts.holder ~= nil) .. " " .. tostring(S[parts.holder].shown) .. " "
        .. tostring(S[parts.gate].shown) .. " " .. tostring(S[parts.reach].shown) .. " " .. S[parts.holder].alpha
        .. " " .. tostring(S[parts.skull].shown), "true true true true 0 false",
        "unticked: the group is made all the same and nothing of it is hidden, only put out by alpha, so its own"
        .. " geometry keeps following the health")
    local function Pinned(obj)
        local said, fill = {}, parts.reach:GetStatusBarTexture()
        for _, point in ipairs(S[obj].points) do
            local to = point[2]
            said[#said + 1] = ("%s=%s%+d%+d"):format(point[1], to == portrait and "portrait"
                or to == fill and "skull fill" or to == frame and "frame" or to == parts.holder and "holder" or "?",
                point[4] or 0, point[5] or 0)
        end
        return table.concat(said, " ")
    end
    Equal(Pinned(parts.reach), "RIGHT=portrait+2+0",
        "the skull's own bar: its right edge two past the portrait's, so a full fill clears the whole portrait and a"
        .. " fill a portrait's width short of full clears none of it")
    Equal(Pinned(parts.gate) .. " " .. S[parts.gate].width,
        "TOP=portrait+0+0 BOTTOM=portrait+0+0 RIGHT=skull fill+0+0 4000",
        "the clipping frame riding that fill's own right edge, reaching far enough back that the skull stands in full"
        .. " once the damage is well past the health")
    Equal(Pinned(parts.skull), "TOPLEFT=portrait+2-2 BOTTOMRIGHT=portrait-2+2",
        "and the skull itself on the portrait's own rect, so the clip lets it through rather than squashing it")
    Equal(("%.2f %.2f %.2f"):format(S[parts.skull].tint[1], S[parts.skull].tint[2], S[parts.skull].tint[3]),
        "1.00 0.96 0.90", "drawn in bone rather than the band's colour, so it reads on any portrait")
    -- The one sum, and who does it: the range is the health your target has
    -- left, sealed, and the value is the plain damage still to come.
    Cast(172) -- Corruption: 40 Shadow over 12 sec, on the 30 health dummy
    local s = S[parts.reach]
    Equal((IsSecret(s.barMax) and "sealed" or "open") .. " " .. tostring(Behind(s.barMin)) .. "-"
        .. tostring(Behind(s.barMax)) .. "/" .. tostring(s.barValue) .. " "
        .. (IsSecret(s.barValue) and "sealed" or "open"), "sealed 0-30/40 open",
        "the skull's bar is handed the sealed health your target has left as its range and the plain damage as its"
        .. " value, so the game is the one that works out whether the one has reached the other")
    -- Ticked on in the middle of a fight: nothing of it is made then.
    local was = { parts.holder, parts.reach, parts.gate, parts.skull }
    lockdown = true
    Fire("PLAYER_REGEN_DISABLED")
    local made = #objects
    ns.Set("dotSkull", true)
    D:Apply()
    BandTick(B, .1)
    Equal(tostring(was[1] == parts.holder and was[2] == parts.reach and was[3] == parts.gate
        and was[4] == parts.skull) .. " " .. (#objects - made) .. " made " .. SkullAt(parts, portrait),
        "true 0 made 58 of 58 shown true",
        "ticked on in a fight: the frames it was made with out of the fight are the ones that show the skull, and the"
        .. " fight itself made nothing at all")
    lockdown = false
    Fire("PLAYER_REGEN_ENABLED")
    Equal(#printed, 0, "no errors")
end)()

-- A target frame with no portrait ---------------------------------------------------------------
-- The portrait is the skull's only. A frame without one keeps its band and
-- its line, goes without the skull, and says so in /ccm debug: nothing errors
-- and nothing of the list changes.

;(function()
    local ns, D, B = Fresh()
    local frame = TargetFrameGame(true)
    rawset(frame, "portrait", nil)
    target, hostile = true, true
    Start(ns)
    local parts = B:Parts()
    Cast(172)
    Equal(tostring(parts.holder) .. " " .. SkullAt(parts, nil) .. " " .. S[parts.clip].alpha .. " "
        .. tostring(S[parts.line].shown), "nil no skull 1 true",
        "no portrait on the frame: no skull group is made at all, and the band and its line go on as they are")
    local said = {}
    B:Report(function(line) said[#said + 1] = line end)
    Equal(said[1]:find("skull false", 1, true) ~= nil, true, "and /ccm debug says there is no skull on this frame")
    Equal(Clock(D), "Corruption 12.0/12", "the list runs as it always does")
    Equal(#printed, 0, "no errors")
end)()

-- A health the game will not give -----------------------------------------------------------------
-- The band's range is your target's full health and the skull's bar is the
-- health it has left, so a client that answers the one and not the other
-- marks the band and never shows a skull at all: the skull's bar is left as
-- it was made, with nothing in it. Never a skull that is wrong.

;(function()
    local ns, D, B = Fresh()
    local _, _, portrait = TargetFrameGame(true)
    target, hostile = true, true
    local answer = _G.UnitHealth
    _G.UnitHealth = function() return nil end
    Start(ns)
    local parts = B:Parts()
    Cast(172)
    Equal(BandAt(parts) .. " | " .. SkullAt(parts, portrait),
        "sealed 0-30/40 fill 126.00 of 126 | 0 of 58 shown true",
        "no answer to the health it has left: the band still marks the lot against its full health, and the skull"
        .. " stays away rather than being drawn on a health nobody knows")
    local said = {}
    B:Report(function(line) said[#said + 1] = line end)
    Equal(said[1]:find("health max only", 1, true) ~= nil, true,
        "and /ccm debug says the health came back as a max and nothing else")
    _G.UnitHealth = answer
    Equal(#printed, 0, "no errors")
end)()

-- The skull follows the band ------------------------------------------------------------------------
-- It is the band's own mark, so a dead target, no target and the out of
-- combat choice take it exactly as they take the band, by alpha alone.

;(function()
    local ns, D, B = Fresh()
    TargetFrameGame(true)
    target, hostile = true, true
    Start(ns)
    local parts = B:Parts()
    Cast(172)
    Equal(S[parts.holder].alpha .. " " .. tostring(S[parts.skull].shown), "1 true",
        "40 damage coming on a 30 health target: the skull stands over its portrait")
    TargetDead = true
    BandTick(B, .1)
    Equal(S[parts.holder].alpha .. " " .. tostring(S[parts.skull].shown) .. " " .. tostring(S[parts.holder].shown),
        "0 false true", "the target dead: the skull comes off the corpse, and its group is put out rather than hidden")
    TargetDead = false
    BandTick(B, .1)
    Equal(S[parts.holder].alpha .. " " .. tostring(S[parts.skull].shown), "1 true", "a live one again, and it is back")
    hostile = false
    for _, pair in ipairs({ { "show", "1" }, { "fade", "0.3" }, { "hide", "0" } }) do
        ns.Set("dotOutOfCombat", pair[1])
        D:Apply()
        Equal(S[parts.holder].alpha .. " " .. S[parts.clip].alpha, pair[2] .. " " .. pair[2],
            "out of combat with nothing to fight, " .. pair[1] .. ": the skull takes the band's own alpha")
    end
    target = false
    Fire("PLAYER_TARGET_CHANGED")
    Equal(S[parts.holder].alpha .. " " .. tostring(S[parts.skull].shown), "0 false", "no target: no skull")
    target = true
    Equal(#printed, 0, "no errors")
end)()

-- In a fight -----------------------------------------------------------------------------------
-- The game says nothing about auras in a fight, so the band runs on the same
-- clock the list does: our own. Nothing is made and nothing of the game's is
-- asked for.

;(function()
    local ns, D, B = Fresh()
    TargetFrameGame(true)
    target, hostile = true, true
    Start(ns)
    local parts = B:Parts()
    -- Cast once out of the fight, which is where a spell's text is read: in a
    -- fight nothing waits on the game for a figure (Dots.lua).
    Cast(172)
    lockdown = true
    Fire("PLAYER_REGEN_DISABLED")
    local made, reads = #objects, AuraIndexReads
    Cast(172)
    BandTick(B, 3)
    Equal(BandAt(parts) .. " " .. S[parts.clip].alpha, "sealed 0-30/30 fill 126.00 of 126 1",
        "a DoT cast in a fight is marked and counted down all the same, off your cast alone")
    Equal((#objects - made) .. " " .. (AuraIndexReads - reads), "0 0",
        "and in the fight the band made nothing at all and read no aura")
    lockdown = false
    TargetAuras = { Aura(172, "Corruption", 12, 6, "player") }
    Fire("PLAYER_REGEN_ENABLED")
    Equal(tostring(B:Drawing()) .. " " .. tostring(B.state.pending.attach) .. " " .. BandAt(parts),
        "true nil sealed 0-30/20 fill 84.00 of 126",
        "the fight over, the real auras put the clock straight and the band marks what they say is left: two of"
        .. " Corruption's four ticks, 20 of the 30 health")
    TargetAuras = {}
    Fire("UNIT_AURA", "target")
    Equal(tostring(B:Drawing()) .. " " .. S[parts.clip].alpha, "false 0",
        "and where they say nothing is running at all, the band goes and its clock stops with it")
    Equal(#printed, 0, "no errors")
end)()

-- Ticked on in the middle of a fight, which is the one time it has to wait.
;(function()
    local ns, D, B = Fresh()
    TargetFrameGame(true)
    target, hostile = true, true
    lockdown = true
    Start(ns)
    Equal(tostring(B:Parts()) .. " " .. tostring(B.state.pending.attach) .. " " .. tostring(B:Found()), "nil true false",
        "ticked on in a fight: nothing is built on Blizzard's frame, and it says it is waiting")
    local w, page = Opened(ns)
    w:Refresh()
    Equal(S[page.status].text, "On. Cast a damage over time spell to see it.",
        "and the page says what it always says: waiting for a fight to end is not the same as a target frame it could"
        .. " not read, so it does not say that")
    w:Hide()
    Cast(172)
    Equal(tostring(B:Parts()) .. " " .. Clock(D), "nil Corruption 18.0/18 guessed",
        "the list runs all the same, on the longest length it knows and marked a guess: in a fight the spell's own"
        .. " text is never asked for, and this one was cast before it had ever been read")
    lockdown = false
    -- The aura the reconcile finds once the fight is over, so what you cast
    -- in it is still running when the band goes up.
    TargetAuras = { Aura(172, "Corruption", 12, 12, "player") }
    Fire("PLAYER_REGEN_ENABLED")
    Equal(tostring(B:Parts() ~= nil) .. " " .. tostring(B.state.pending.attach) .. " " .. BandAt(B:Parts()),
        "true nil sealed 0-30/40 fill 126.00 of 126", "the fight over, it is built and marks what is left")
    Equal(#printed, 0, "no errors")
end)()

-- A new target, no target, a dead one, and a loading screen ------------------------------------

;(function()
    local ns, D, B = Fresh()
    TargetFrameGame(true)
    target, hostile = true, true
    Start(ns)
    local parts = B:Parts()
    Cast(172)
    Equal(S[parts.clip].alpha .. " " .. tostring(S[parts.line].shown), "1 true", "marking your target")
    Fire("PLAYER_TARGET_CHANGED")
    Equal(BandAt(parts) .. " | " .. S[parts.clip].alpha .. " " .. tostring(S[parts.line].shown) .. " "
        .. S[parts.holder].alpha, "sealed 0-30/0 fill 0.00 of 126 | 0 false 0",
        "a new target: the band, its line and its skull all go, since what you had running was on the last one")
    Cast(172)
    Equal(S[parts.clip].alpha, 1, "and the first spell on the new one brings it back")
    -- The target dies.
    TargetDead = true
    BandTick(B, .1)
    Equal(S[parts.clip].alpha .. " " .. tostring(S[parts.line].shown), "0 false",
        "the target dead: the band comes off the corpse rather than marking damage that will never land")
    TargetDead = false
    BandTick(B, .1)
    Equal(S[parts.clip].alpha, 1, "a live one again, and it is back")
    -- No target at all.
    target = false
    Fire("PLAYER_TARGET_CHANGED")
    Equal(S[parts.clip].alpha .. " " .. tostring(S[parts.line].shown), "0 false", "no target: nothing to mark")
    target = true
    -- A loading screen.
    Cast(172)
    Fire("PLAYER_ENTERING_WORLD")
    Equal(S[parts.clip].alpha .. " " .. tostring(S[parts.line].shown) .. " " .. tostring(B:Found()), "0 false true",
        "a loading screen: nothing of ours is left showing over whatever the game has put up")
    Equal(#printed, 0, "no errors")
end)()

-- Out of combat --------------------------------------------------------------------------------
-- In full in a fight, with an enemy up and while its page is open; otherwise
-- as the choice says. By alpha only: nothing of Blizzard's is shown or hidden.

;(function()
    local ns, D, B = Fresh()
    TargetFrameGame(true)
    target, hostile = true, true
    Start(ns)
    local parts = B:Parts()
    Cast(172)
    Equal(S[parts.clip].alpha, 1, "an enemy targeted: in full")
    hostile = false
    for _, pair in ipairs({ { "show", 1 }, { "fade", .3 }, { "hide", 0 } }) do
        ns.Set("dotOutOfCombat", pair[1])
        D:Apply()
        Equal(S[parts.clip].alpha, pair[2], "out of combat with nothing to fight, " .. pair[1] .. ": its own alpha")
    end
    -- An enemy targeted brings it back, unless Stay hidden with an enemy
    -- targeted is ticked on the General page, which is the same tick the
    -- list's own Awake reads (Dots.lua). Checked here, with Hide still
    -- picked and Corruption still running, since once there is nothing to
    -- mark the band is out whatever the choice is.
    hostile = true
    D:Apply()
    Equal(S[parts.clip].alpha, 1, "Hide, with an enemy targeted: the band comes back for the target")
    ns.Set("oocIgnoreTarget", true)
    D:Apply()
    Equal(S[parts.clip].alpha, 0, "Stay hidden with an enemy targeted: the target does not bring the band back either")
    ns.Set("oocIgnoreTarget", false)
    hostile = false
    lockdown = true
    Fire("PLAYER_REGEN_DISABLED")
    Equal(S[parts.clip].alpha, 1, "and in a fight it comes back in full whatever that choice is")
    lockdown = false
    -- Past the grace a freshly cast spell gets, so the read below is the game
    -- having had its say rather than answering before the aura landed.
    Tick(D, 2)
    Fire("PLAYER_REGEN_ENABLED")
    -- The fight over, the reconcile against the real auras finds nothing on
    -- the target, so the list it was marking has gone: that, not Hide, is why
    -- the band is out here.
    Equal(Clock(D) .. " | " .. S[parts.clip].alpha, "nothing | 0",
        "and the fight over, the real auras say nothing is running at all, so the band goes with the list")
    Equal(#printed, 0, "no errors")
end)()

-- A target frame this client's own addon cannot read -------------------------------------------
-- Not an error: the list still works, the page says so in plain words and
-- /ccm debug says what was looked for.

;(function()
    local ns, D, B = Fresh()
    TargetFrameGame()
    target, hostile = true, true
    local w, page = Opened(ns)
    page.master:Click()
    Cast(172)
    w:Refresh()
    Equal(tostring(B:Parts()) .. " " .. tostring(B:Found()) .. " " .. tostring(B.state.errors.host), "nil false no target frame",
        "no target frame at all: nothing is built and it says why")
    Equal(S[page.status].text,
        "On, but your target frame could not be found, so the band has nothing to sit on. The list still works.",
        "the page says it in plain words, so a band that never shows does not read as a bug")
    Equal(Clock(D), "Corruption 12.0/12", "and the list itself runs as it always does")
    local said = {}
    B:Report(function(line) said[#said + 1] = line end)
    Equal(said[1], "DoTs band: wanted true, on the target frame false (no target frame), skull false, width none,"
        .. " marking 40 damage shadow, drawing false, health read, nameplate off, waiting none",
        "and /ccm debug says what it looked for and what it found")
    -- A target frame it cannot read says nothing about the nameplate's band.
    NamePlateGame(true)
    ns.Set("dotNameplates", true)
    D:Apply()
    local plate = B:PlateParts()
    Equal(tostring(plate ~= nil) .. " " .. tostring(B.state.plateOn) .. " " .. S[plate.clip].alpha .. " "
        .. tostring(B:Found()), "true true 1 false",
        "and with nameplates ticked it still marks the plate: a target frame it cannot read takes only the band that"
        .. " would have sat on it")
    ns.Set("dotNameplates", false)
    NamePlateGame()
    Equal(#printed, 0, "no errors")
end)()

-- The same band on your target's nameplate -----------------------------------------------------
-- Off until it is ticked. A plate belongs to the game and the game hands the
-- same plate to the next unit, so one set of layers of ours is made out of a
-- fight and moved onto whichever plate is your target's.

;(function()
    local ns, D, B = Fresh()
    TargetFrameGame(true)
    local _, plateHealth = NamePlateGame(true)
    target, hostile = true, true
    Start(ns)
    Equal(tostring(B:PlateParts()) .. " " .. tostring(B.state.plateOn), "nil false",
        "off by default: nothing at all is made for a nameplate")
    ns.Set("dotNameplates", true)
    D:Apply()
    local plate = B:PlateParts()
    -- Straight onto the plate's own health bar, since it is one a player can
    -- see: a nameplate is drawn through the game's own path and the band has
    -- to stay in it. The climb to a parent is only ever for a hidden bar.
    Equal(tostring(plate ~= nil) .. " " .. tostring(S[plate.clip].parent == plateHealth) .. " "
        .. tostring(Last(plate.clip, "SetClipsChildren", 1)) .. " " .. S[plate.band].width .. " "
        .. tostring(B.state.plateOn), "true true true 110 true",
        "ticked on, the same band goes on your target's own plate, on that bar, whatever width it is")
    Cast(172)
    Equal(BandAt(plate) .. " " .. S[plate.clip].alpha, "sealed 0-30/40 fill 110.00 of 110 1",
        "and marks the same damage there, against the same sealed health")
    Equal(tostring(plate.holder), "nil", "with no skull: a nameplate has no portrait to put one on")
    HealthMax.target = 60
    Fire("UNIT_MAXHEALTH", "target")
    Equal(BandAt(plate), "sealed 0-60/40 fill 73.33 of 110",
        "and the target's health changing reaches the plate's band as well as the target frame's")
    -- The plate taken away, as the game takes one away.
    NamePlateGame()
    Fire("NAME_PLATE_UNIT_REMOVED", "target")
    Equal(S[plate.clip].alpha .. " " .. tostring(B.state.plateOn) .. " " .. tostring(B.state.errors.plate),
        "0 false your target has no nameplate up",
        "the plate gone, the band comes off it rather than riding a plate the game has given to someone else")
    -- And a plate coming up in the middle of a fight, which is when they do.
    lockdown = true
    Fire("PLAYER_REGEN_DISABLED")
    local _, second = NamePlateGame(true)
    local made = #objects
    Fire("NAME_PLATE_UNIT_ADDED", "target")
    Equal(tostring(S[plate.clip].parent == second) .. " " .. (#objects - made) .. " "
        .. S[plate.band].width .. " " .. S[plate.clip].alpha, "true 0 110 1",
        "a plate up in a fight: the same layers move onto its bar, nothing is made, same damage marked")
    lockdown = false
    Equal(#S[second].points .. " " .. S[second].alpha .. " " .. tostring(S[second].last.SetParent) .. " "
        .. tostring(S[second].last.SetClipsChildren) .. " " .. tostring(next(second)), "0 1 nil nil nil",
        "and nothing of the plate's own health bar is set or written to either")
    local said = {}
    B:Report(function(line) said[#said + 1] = line end)
    Equal(said[1]:find("nameplate true", 1, true) ~= nil, true, "/ccm debug says the plate is marked")
    ns.Set("dotNameplates", false)
    D:Apply()
    Equal(S[plate.clip].alpha .. " " .. tostring(B.state.plateOn), "0 false", "unticked, it goes")
    NamePlateGame()
    Equal(#printed, 0, "no errors")
end)()

-- The band switched off, and the whole part switched off ----------------------------------------

;(function()
    local ns, D, B = Fresh()
    TargetFrameGame(true)
    target, hostile = true, true
    Start(ns)
    local parts = B:Parts()
    Cast(172)
    ns.Set("dotBand", false)
    D:Apply()
    Equal(S[parts.clip].alpha .. " " .. tostring(S[parts.line].shown) .. " " .. S[parts.holder].alpha .. " "
        .. tostring(B:Drawing()) .. " " .. tostring(BandHears(B, "UNIT_HEALTH")),
        "0 false 0 false false", "the band unticked: everything of ours goes out and it stops listening")
    Equal(Clock(D), "Corruption 12.0/12", "and the list keeps running, since that is its own tick")
    ns.Set("dotBand", true)
    D:Apply()
    Equal(S[parts.clip].alpha .. " " .. tostring(B:Drawing()), "1 true", "ticked back on, it marks again")
    ns.Set("dots", false)
    D:Apply()
    Equal(S[parts.clip].alpha .. " " .. tostring(B:Drawing()) .. " " .. tostring(BandHears(B, "PLAYER_TARGET_CHANGED")),
        "0 false false", "and the whole part off takes it away and leaves nothing heard")
    TargetFrameGame()
    Equal(#printed, 0, "no errors")
end)()

-- A nameplate in a shape the band does not know by name -----------------------------------------
-- The game's own plate keeps its health bar under one of the names the band
-- looks for. A plate another addon has restyled may keep the game's unit frame
-- and put its bar somewhere else on it, and one built again from scratch may
-- have no unit frame at all, so where no name answers the band walks the
-- frame's own children and takes the first status bar in it. Every bit of that
-- is a read: nothing of the plate is ever set, whatever shape it is in.

-- A plate in one of those shapes. "skinned" keeps the game's unit frame with
-- its health bar under no name the band looks for, "bare" has no unit frame at
-- all and the bar straight on the plate, and "empty" has no status bar in it
-- anywhere. None of the sizes is a measurement: the band takes whatever width
-- the bar it finds has. (A global: this file's main chunk is at Lua's 200
-- locals.)
function PlateShape(kind)
    NamePlates.target = nil
    if kind == nil then return end
    local plate = New("Frame", UIParent)
    S[plate].width, S[plate].height = 110, 45
    local holder = plate
    if kind ~= "bare" then
        holder = New("Frame", plate)
        rawset(plate, "UnitFrame", holder)
    end
    if kind == "empty" then
        New("Frame", holder) -- something of the plate's own that is not a bar
        NamePlates.target = plate
        return plate
    end
    local health = New("StatusBar", holder)
    S[health].width, S[health].height = 92, 8
    health:GetStatusBarTexture()
    health:SetMinMaxValues(0, UnitHealthMax("target"))
    health:SetValue(UnitHealth("target"))
    NamePlates.target = plate
    return plate, health, holder
end

;(function()
    local ns, D, B = Fresh()
    TargetFrameGame(true)
    target, hostile = true, true
    ns.Set("dotNameplates", true)
    local _, skinned = PlateShape("skinned")
    Start(ns)
    local parts = B:PlateParts()
    Equal(tostring(parts ~= nil) .. " " .. tostring(S[parts.clip].parent == skinned) .. " "
        .. S[parts.band].width .. " " .. tostring(B.state.plateOn), "true true 92 true",
        "a plate whose health bar is under no name the band knows: the first status bar inside the game's own unit"
        .. " frame is found, as wide as that bar happens to be")
    Equal(#S[skinned].points .. " " .. tostring(S[skinned].last.SetParent) .. " "
        .. tostring(S[skinned].last.SetClipsChildren) .. " " .. tostring(next(skinned)), "0 nil nil nil",
        "and nothing of that bar is set or written to, exactly as on the game's own plate")
    local _, bare = PlateShape("bare")
    Fire("NAME_PLATE_UNIT_ADDED", "target")
    Equal(tostring(S[parts.clip].parent == bare) .. " " .. S[parts.band].width .. " "
        .. tostring(B.state.plateOn), "true 92 true",
        "and a plate with no unit frame on it at all: the walk finds the bar in the plate itself")
    -- A nameplate addon that draws its own bar hides the game's by its
    -- opacity, not by hiding it, so the game's bar is still "shown" and still
    -- answers for its texture. Measuring the band against that one puts it on
    -- a bar nobody can see, and it may not even be the same shape as the one
    -- in front of the player. The walk takes the first bar that is actually
    -- visible and only falls back to a hidden one when there is nothing else.
    -- (EraUI did exactly this to the target frame on 27 Nov 2026.)
    local _, gameBar, holder = PlateShape("skinned")
    gameBar:SetAlpha(0)
    local theirs = New("StatusBar", holder)
    S[theirs].width, S[theirs].height = 70, 9
    theirs:GetStatusBarTexture()
    Fire("NAME_PLATE_UNIT_ADDED", "target")
    Equal(tostring(S[parts.clip].parent == theirs) .. " " .. S[parts.band].width,
        "true 70", "a plate whose own bar is hidden by its opacity: the band measures the visible one instead")
    gameBar:SetAlpha(1)
    -- And the other way a nameplate addon does it: the game's whole unit
    -- frame is hidden and its own is drawn beside it. The bar inside still
    -- answers IsShown true at full opacity, because that only asks about its
    -- own flag, so only IsVisible tells the two apart. This is the one that
    -- caught Plater out on 27 Nov 2026.
    local plate, inside, box = PlateShape("skinned")
    box:Hide()
    local drawn = New("StatusBar", plate)
    S[drawn].width, S[drawn].height = 64, 9
    drawn:GetStatusBarTexture()
    Fire("NAME_PLATE_UNIT_ADDED", "target")
    Equal(tostring(inside:IsShown()) .. " " .. tostring(inside:IsVisible()) .. " "
        .. tostring(S[parts.clip].parent == drawn) .. " " .. S[parts.band].width,
        "true false true 64",
        "the game's unit frame hidden whole: its bar still says it is shown, and the band takes the drawn one")
    box:Show()
    PlateShape("empty")
    Fire("NAME_PLATE_UNIT_ADDED", "target")
    Equal(tostring(B.state.plateOn) .. " | " .. tostring(B.state.errors.plate) .. " | " .. S[parts.clip].alpha,
        "false | no health bar this can read on your target's nameplate | 0",
        "a plate with no status bar in it anywhere is not an error: nothing is marked and the debug report says why")
    PlateShape()
    Fire("NAME_PLATE_UNIT_REMOVED", "target")
    Equal(#printed, 0, "no errors")
end)()

-- Other players' spells: the band behind yours --------------------------------------------------
-- Off until it is ticked. What anyone else has running on your target is read
-- from each real aura's own caster, out of a fight only, and marked behind your
-- own band: the band behind takes everyone's damage together, so what shows
-- past your own is their share of what is coming. It is hatched and paler, so
-- the two are never one band with a lighter end. Their figures are each
-- spell's own description, which says nothing about their gear, and nothing of
-- theirs is ever heard as it is cast: only your own casts are.

-- The band behind yours: what it was handed, what the game drew from it, how
-- lit it is and what it is drawn with. (A global: this file's main chunk is at
-- Lua's 200 locals.)
function BackAt(parts)
    if not parts or not parts.back then return "no band behind" end
    local s = S[parts.back]
    local texture = tostring(Last(parts.back, "SetStatusBarTexture", 1))
    return ("%s 0-%s/%s fill %.2f of %s alpha %s %s"):format(IsSecret(s.barMax) and "sealed" or "open",
        tostring(Behind(s.barMax)), tostring(s.barValue), S[s.barTexture].width, tostring(s.width),
        tostring(s.alpha), texture:match("[^\\]+$") or texture)
end

;(function()
    local ns, D, B = Fresh()
    -- A target with room for both bands: 200 health, so your own 40 and
    -- someone else's are each a share of it rather than both clamping full.
    Health.target, HealthMax.target = 200, 200
    local _, health = TargetFrameGame(true)
    target, hostile = true, true
    Start(ns)
    local parts = B:Parts()
    -- One Corruption of yours and one of someone else's. Corruption is 40 over
    -- 12 sec in this character's own spellbook text, which is the only reading
    -- the game ever gives us: theirs is costed on the same text.
    TargetAuras = { Aura(172, "Corruption", 12, 12, "player"), Aura(172, "Corruption", 12, 6, "party2") }
    Fire("UNIT_AURA", "target")
    Equal(Clock(D) .. " | " .. tostring(D:Theirs()) .. " " .. select(2, D:Theirs()), "Corruption 12.0/12 | nil 0",
        "off by default: only your own Corruption is read at all, and nothing of anyone else's is counted")
    Equal(S[parts.back].alpha, 0, "and the band behind yours is not lit")
    ns.Set("dotOthers", true)
    D:Apply()
    Fire("UNIT_AURA", "target")
    Equal(Clock(D) .. " | " .. tostring(D:Theirs()) .. " " .. select(2, D:Theirs()), "Corruption 12.0/12 | 20 1",
        "ticked on: theirs is read from the aura's own caster and costed on the spell's own text, two of its four"
        .. " ticks still to come")
    Equal(BandAt(parts), "sealed 0-200/40 fill 25.20 of 126",
        "your own band marks your own 40 of the 200 health and nothing of theirs")
    Equal(BackAt(parts), "sealed 0-200/20 fill 12.60 of 126 alpha 1 Hatch.tga",
        "and the band behind it marks their 20, hatched, as its own stretch of the bar")
    Equal(tostring(S[parts.back].parent == parts.clip) .. " " .. tostring(Last(parts.back, "SetReverseFill", 1)) .. " "
        .. tostring(Last(parts.back, "SetFrameLevel", 1)) .. " " .. tostring(Last(parts.band, "SetFrameLevel", 1)),
        "true true 1 2", "inside the same clipping frame, filling the same way, with your own band over it")
    local anchored = {}
    for _, point in ipairs(S[parts.back].points) do
        local to = point[2]
        anchored[#anchored + 1] = point[1] .. "=" .. (to == parts.mark and "your band's own fill"
            or to == parts.clip and "clip" or "?") .. "/" .. tostring(point[3])
    end
    Equal(table.concat(anchored, " "), "TOP=clip/TOP BOTTOM=clip/BOTTOM RIGHT=your band's own fill/LEFT",
        "and its right edge is the edge your own band reaches, so the two sit side by side rather than one over the"
        .. " other: each band is its own owner's damage")
    local function Painted(bar)
        local said = {}
        for i = 1, 4 do said[i] = ("%.2f"):format(Last(bar, "SetStatusBarColor", i) or 0) end
        return table.concat(said, " ")
    end
    Equal(Painted(parts.band) .. " | " .. Painted(parts.back), "0.58 0.35 0.85 0.55 | 0.73 0.58 0.90 0.36",
        "theirs in the same colour as yours, paler and at a share of the strength")
    Equal(#S[health].points .. " " .. tostring(S[health].last.SetParent) .. " "
        .. tostring(S[health].last.SetClipsChildren) .. " " .. tostring(S[health].last.SetAlpha) .. " "
        .. tostring(next(health)), "0 nil nil nil nil",
        "and nothing of Blizzard's health bar is set or written to by any of it (its own range is the mock game's own,"
        .. " as the game sets it)")
    -- In a fight: nothing of theirs can be read, so what was read before it
    -- counts down on our clock, exactly as your own spells do.
    lockdown = true
    Fire("PLAYER_REGEN_DISABLED")
    local reads = AuraIndexReads
    BandTick(B, 3)
    Equal(BandAt(parts) .. " | " .. BackAt(parts) .. " | " .. (AuraIndexReads - reads),
        "sealed 0-200/30 fill 18.90 of 126 | sealed 0-200/10 fill 6.30 of 126 alpha 1 Hatch.tga | 0",
        "three seconds into a fight both bands have come down a tick, and no aura was read for either")
    lockdown = false
    TargetAuras = { Aura(172, "Corruption", 12, 12, "player") }
    Fire("PLAYER_REGEN_ENABLED")
    Equal(tostring(D:Theirs()) .. " " .. S[parts.back].alpha .. " | " .. BandAt(parts), "nil 0 | sealed 0-200/40 fill 25.20 of 126",
        "the fight over, the real auras are the truth again: theirs has gone and the band behind it goes out")
    Equal(#printed, 0, "no errors")
end)()

-- Only someone else's, and a caster the game will not name ---------------------------------------

;(function()
    local ns, D, B = Fresh()
    Health.target, HealthMax.target = 200, 200
    TargetFrameGame(true)
    target, hostile = true, true
    ns.Set("dotOthers", true)
    Start(ns)
    local parts = B:Parts()
    TargetAuras = { Aura(172, "Corruption", 12, 12, "party2") }
    Fire("UNIT_AURA", "target")
    Equal(Clock(D) .. " | " .. tostring(D:Theirs()) .. " " .. tostring(B:Drawing()), "nothing | 40 true",
        "a target with nothing of yours on it but someone else's spells is still marked, and the band's own clock runs")
    Equal(BandAt(parts) .. " | " .. BackAt(parts),
        "sealed 0-200/0 fill 0.00 of 126 | sealed 0-200/40 fill 25.20 of 126 alpha 1 Hatch.tga",
        "with nothing in your own band: theirs is the whole of what is coming")
    -- A caster the game holds back. On a spell that is already on our own
    -- clock it counts as yours, so a sealed caster can never make a second
    -- band out of your own spell; on one that is not, it is someone else's.
    Cast(172)
    TargetAuras = { { spellId = 172, name = "Corruption", duration = 12, expirationTime = clock + 12,
        sourceUnit = SECRETS.string, points = {} } }
    Fire("UNIT_AURA", "target")
    Equal(Clock(D) .. " | " .. tostring(D:Theirs()), "Corruption 12.0/12 | nil",
        "a caster the game will not name, on a spell you have running: yours, not a second band")
    TargetAuras = {}
    Fire("UNIT_AURA", "target")
    TargetAuras = { { spellId = 172, name = "Corruption", duration = 12, expirationTime = clock + 12,
        sourceUnit = SECRETS.string, points = {} } }
    Fire("UNIT_AURA", "target")
    Equal(Clock(D) .. " | " .. tostring(D:Theirs()) .. " " .. tostring(D:TheirRows()[1].source),
        "nothing | 40 nil", "and on one you have not cast it is someone else's, with no caster named for it")
    -- A new target takes everyone's with it: what was on the old one says
    -- nothing about the new one.
    TargetAuras = {}
    Fire("PLAYER_TARGET_CHANGED")
    Equal(tostring(D:Theirs()) .. " " .. S[parts.back].alpha .. " " .. tostring(B:Drawing()), "nil 0 false",
        "a new target: theirs goes with yours and the band stops")
    -- The band behind yours is the only place theirs is ever drawn, so the
    -- band's own tick takes theirs with it: nothing of theirs is read,
    -- counted or said on the page while the band is off.
    TargetAuras = { Aura(172, "Corruption", 12, 12, "party2") }
    Fire("UNIT_AURA", "target")
    Equal(tostring(D:Theirs()), "40", "theirs read again with the band on")
    ns.Set("dotBand", false)
    D:Apply()
    Fire("UNIT_AURA", "target")
    Equal(tostring(D:Theirs()) .. " " .. #D:TheirRows(), "nil 0",
        "the band unticked: nothing of theirs is read or counted, since the band is the only thing that draws it")
    ns.Set("dotBand", true)
    D:Apply()
    Fire("UNIT_AURA", "target")
    Equal(tostring(D:Theirs()), "40", "the band ticked again, and theirs is read again")
    ns.Set("dotOthers", false)
    D:Apply()
    Equal(tostring(D:Theirs()) .. " " .. #D:TheirRows(), "nil 0", "and unticked, nothing of theirs is kept at all")
    Equal(#printed, 0, "no errors")
end)()

-- The skull counts everyone's together ----------------------------------------------------------
-- The skull is about whether your target lives, so it does not care who the
-- damage came from. Its own bar takes the health your target has left as its
-- range and everyone's damage as its value, and the game fills it: nothing
-- here ever compares the two.

;(function()
    local ns, D, B = Fresh()
    Health.target, HealthMax.target = 70, 200
    local _, _, portrait = TargetFrameGame(true)
    target, hostile = true, true
    ns.Set("dotOthers", true)
    Start(ns)
    local parts = B:Parts()
    TargetAuras = { Aura(172, "Corruption", 12, 12, "player") }
    Fire("UNIT_AURA", "target")
    Equal(SkullAt(parts, portrait), "0 of 58 shown true",
        "your own 40 against the 70 health it has left: not enough, so no skull")
    TargetAuras = { Aura(172, "Corruption", 12, 12, "player"), Aura(172, "Corruption", 12, 12, "party2") }
    Fire("UNIT_AURA", "target")
    Equal(SkullAt(parts, portrait), "58 of 58 shown true",
        "someone else's 40 as well, and together they are more than it has left: the skull stands")
    ns.Set("dotOthers", false)
    D:Apply()
    Equal(SkullAt(parts, portrait), "0 of 58 shown true",
        "unticked, only your own counts again and the skull goes")
    Equal(#printed, 0, "no errors")
end)()

-- What the page and /ccm debug say about theirs --------------------------------------------------

;(function()
    local ns, D, B = Fresh()
    Health.target, HealthMax.target = 200, 200
    TargetFrameGame(true)
    target, hostile = true, true
    local w, page = Opened(ns)
    page.master:Click()
    Equal(S[page.saidOthers].text, "Other players' spells are read between fights, so one cast during a fight is marked"
        .. " when that fight ends. Their figures are the spell's own description, which says nothing about their gear.",
        "the page says where their figures come from and when they are read, in plain words and not on hover")
    Equal(Note(page.others):find("hatched behind your own band", 1, true) ~= nil, true,
        "and the tick's own note says what it draws")
    page.others:Click()
    TargetAuras = { Aura(172, "Corruption", 12, 12, "player"), Aura(172, "Corruption", 12, 12, "party2") }
    Fire("UNIT_AURA", "target")
    w:Refresh()
    Equal(S[page.status].text, "On. 1 spell running, 40 damage to come. 40 of other players' to come.",
        "the status line keeps theirs on the end, so the two figures are never read as one")
    local said = {}
    D:Report(function(line) said[#said + 1] = line end)
    Equal(said[3], "DoTs others: on, running 1, to come 40 | Corruption from party2 12.0/12.0 40",
        "/ccm debug says what was read of theirs, who the game said cast it and what it was costed at")
    local band = {}
    B:Report(function(line) band[#band + 1] = line end)
    Equal(band[1]:find("marking 40 damage shadow and 40 of theirs", 1, true) ~= nil, true,
        "and the band's own line says both figures")
    Equal(#printed, 0, "no errors")
end)()

-- A text that names several figures, one line per combo point ---------------------------------
-- A finishing move's description writes a line for each number of combo
-- points, and nothing in it says which line the cast you just made was. So
-- none of them is taken as the spell's figure: the lines are kept apart, the
-- longest of their times runs the clock as a guess, and the damage column
-- stays empty until the real aura hands the length over. Taking the last line
-- would cost a one point Rupture as the five point one, five times the damage
-- that is coming. (A global, as the mock's own fixtures are: this file's main
-- chunk is at Lua's 200 locals.)
FinisherText = "Finishing move that causes damage over time, increased by your attack power. Lasts longer per combo"
    .. " point: 1 point: 68 damage over 8 secs 2 points: 114 damage over 10 secs 3 points: 180 damage over 12 secs"
    .. " 4 points: 268 damage over 14 secs 5 points: 378 damage over 16 secs"

;(function()
    local _, D = Fresh()
    local reading = D:Parse(FinisherText)
    Equal(tostring(reading ~= nil) .. " " .. tostring(reading.total) .. " " .. tostring(reading.lasts) .. " "
        .. #reading.pairs, "true nil nil 5",
        "five figures in the one text, so not one of them is the spell's figure and all five are kept apart")
    local said = {}
    for _, pair in ipairs(reading.pairs) do said[#said + 1] = pair.total .. "/" .. pair.lasts end
    Equal(table.concat(said, " "), "68/8 114/10 180/12 268/14 378/16",
        "each line's own damage over its own time, in the order the text wrote them")
    local twice = D:Parse("Deals 40 Shadow damage over 12 sec. 40 Shadow damage over 12 sec.")
    Equal(("%g over %g %s"):format(twice.total, twice.lasts, tostring(twice.pairs)), "40 over 12 nil",
        "and a text that says the same figure twice is read as the one figure it is")
    Equal(#printed, 0, "no errors")
end)()

;(function()
    local ns, D = Fresh()
    target, hostile = true, true
    SpellText[1943] = FinisherText -- Rupture rank 1
    Start(ns)
    Cast(1943)
    Equal(Clock(D), "Rupture 16.0/16 guessed",
        "cast, the longest of the text's own times runs the clock and the row says what it is: a guess")
    Equal(tostring(D:Rows()[1].figure), "nil",
        "and there is no figure at all while that length is a guess, since nothing says which line this cast was")
    Equal(tostring(select(1, D:Band())), "nil", "so the band has nothing of it to mark either")
    TargetAuras = { Aura(1943, "Rupture", 8, 8, "player") }
    Fire("UNIT_AURA", "target")
    Equal(Clock(D) .. " " .. tostring(D:Rows()[1].figure), "Rupture 8.0/8 68",
        "the real aura hands the length over, and the line whose own time is that length is the one costed: a one"
        .. " point Rupture's 68, not the five point 378")
    TargetAuras = { Aura(1943, "Rupture", 16, 16, "player") }
    Fire("UNIT_AURA", "target")
    Equal(Clock(D) .. " " .. tostring(D:Rows()[1].figure), "Rupture 16.0/16 378",
        "and a five point one is costed at its own line")
    local told = {}
    D:Report(function(line) told[#told + 1] = line end)
    Equal(told[2]:find("Rupture 378 over 16 in 8 ticks of 5 in its text", 1, true) ~= nil, true,
        "/ccm debug says which of the text's lines it took and how many there were to pick from")
    Equal(#printed, 0, "no errors")
end)()

-- A container that turns a slot down ------------------------------------------------------------
-- Every word said to the container is inside one pcall, as the Buffs bars'
-- are: a client that refuses a slot says so by erroring, and an error let out
-- of there would stop the rest of the addon starting, since Core.lua starts
-- the band, the layout, the minimap button and the notes after this. The list
-- carries on without the slots: each row shows the spell's own picture and our
-- own clock, with no swipe over it.

;(function()
    local ns, D = Fresh()
    target, hostile = true, true
    Start(ns)
    local box = D.state.container
    rawset(box, "SetAuraSlotEnabled", function() error("this client will not have it") end)
    -- The slots made again from scratch, which is what a spell learned does.
    D.state.slotsFor = nil
    D:Apply()
    Equal(tostring(D.state.errors.slots ~= nil) .. " " .. #printed, "true 0",
        "the refusal is kept for the debug report and nothing is thrown at the player")
    local told = {}
    D:Report(function(line) told[#told + 1] = line end)
    Equal(told[4]:find("(refused: ", 1, true) ~= nil, true, "/ccm debug says the container turned the slots down")
    Cast(8921)
    Tick(D, 0)
    Equal(Clock(D) .. " | " .. Row(D, 1), "Moonfire 12.0/12 guessed | Moonfire 12 [] 0-12/12",
        "and the list still runs on our own clock, with the row showing the spell's own picture")
    Equal(#printed, 0, "no errors")
end)()

-- A target that died, and a loading screen -----------------------------------------------------
-- Death takes every debuff on your target with it, and a loading screen
-- leaves the world the list was running in. The game says nothing about
-- either (your target does not change when it dies), so the clock's own pass
-- is what notices, and what it finds is that there is nothing left to count.

;(function()
    local ns, D = Fresh()
    target, hostile = true, true
    Start(ns)
    Cast(8921)
    Equal(Clock(D) .. " " .. tostring(D:Drawing()), "Moonfire 12.0/12 guessed true",
        "one spell running on your live target, with the clock going")
    TargetDead = true
    Tick(D, .1)
    Equal(Clock(D) .. " " .. tostring(D:Drawing()) .. " " .. S[D.frame].alpha, "nothing false 0",
        "your target died, so the list goes with its debuffs rather than counting down over a corpse")
    TargetDead = false
    -- And a loading screen in the middle of a fight, when no aura can be read
    -- at all, so the reconcile has nothing to put straight.
    lockdown = true
    Fire("PLAYER_REGEN_DISABLED")
    Cast(8921)
    Equal(Clock(D), "Moonfire 12.0/12 guessed", "cast again, in a fight this time")
    Fire("PLAYER_ENTERING_WORLD")
    Equal(Clock(D) .. " " .. S[D.frame].alpha, "nothing 0",
        "a loading screen: nothing of the last world's target is left counting down, in a fight as well as out of one")
    lockdown = false
    Fire("PLAYER_REGEN_ENABLED")
    Equal(#printed, 0, "no errors")
end)()

Equal(SecretMisuse[1], nil, "no secret misused anywhere")
io.write("DoTs checks passed: " .. checks .. " assertions.\n")
