-- Run the actual addon files against a mock game for what the addon does
-- while you fight: on each event, only what the game says changed is done
-- again, and nothing is set that is already so. Your bars refresh only the
-- cooldowns or only the colours and glows as told, and range comes from the
-- game's own range event (never asked 4 times a second); borders and shadows,
-- your cast bar and swing timer, the keys after a form change, the Cooldown
-- pulse after a bag change and the ? help's pulse each skip what's unchanged.
-- Every call the addon's files make into the mock game is counted, and the
-- counts per event are printed. The mock game is a copy of
-- Tools/TestBars.lua's: Tools/TestMockSync.mjs checks the two match, and with
-- --write copies it across. Tools/TestBars.lua is near the mock game's memory
-- limit, so these run here.
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

-- Hot path: the game around it ---------------------------------------------------------------------
-- Stand-ins for what the window's other pages need (Raid Timers' previews
-- run none of Blizzard's code, the Cooldown pulse plays no sound), as in
-- Tools/TestCost.lua, so every file the addon ships loads.

_G.hooksecurefunc = function(t, key, hook)
    if type(t) == "string" then t, key, hook = _G, t, key end
    local original = t[key]
    rawset(t, key, function(...)
        if original then original(...) end
        hook(...)
    end)
end
local function BlizzardFrames()
    _G.TimerTracker = Blizzard(New("Frame"), "TimerTracker")
    rawset(TimerTracker, "timerList", {})
    _G.TimerTracker_StartTimerOfType = function() end
    _G.RaidWarningFrame = Blizzard(New("Frame"), "RaidWarningFrame")
    rawset(RaidWarningFrame, "fontStringPool", { EnumerateActive = function() return pairs({}) end })
    rawset(RaidWarningFrame, "AddMessage", function() end)
    _G.C_AddOns, _G.EraUI = nil, nil
    _G.PlaySound = function() end
    _G.C_Spell.GetSpellCooldown = function() return { isEnabled = true } end
    _G.GetSpellBaseCooldown = nil
    S[UIParent].width, S[UIParent].height = 1366, 768
end

-- Every file in the order the .toc loads them (Tools/TestRules.mjs checks the .toc).
local FILES = { "Core.lua", "SquirtVersions.lua", "Style.lua", "Skin.lua", "Resource.lua", "CastBar.lua", "RaidTimers.lua", "Ranks.lua", "Forms.lua", "Spells.lua",
    "Keybinds.lua", "Buffs.lua", "IconAuras.lua", "Bars.lua", "Pulse.lua", "Layout.lua", "Theme.lua", "BarPage.lua",
    "LayoutPage.lua", "CastBarPage.lua", "RaidTimersPage.lua", "PulsePage.lua", "ProfileShare.lua", "ProfileMenu.lua", "Window.lua",
    "Tour.lua", "MinimapButton.lua", "Notes.lua", "Debug.lua" }

-- The timers run so far, each once (C_Timer.After: the next frame).
local ran = 0
-- A fresh game, logged in with these saved settings.
local function Start(saved)
    Environment()
    ran = 0
    BlizzardFrames()
    _G.FECMFrame, _G.FECMTour, _G.FECMNotes, _G.FECMDebugFrame = nil, nil, nil, nil
    local ns = {}
    _G.ForeverEnhancedCooldownManagerDB = saved
    for _, file in ipairs(FILES) do assert(loadfile(file))("ForeverEnhancedCooldownManager", ns) end
    Fire("ADDON_LOADED", "ForeverEnhancedCooldownManager")
    Fire("PLAYER_LOGIN")
    Fire("PLAYER_ENTERING_WORLD")
    return ns
end
-- Frames going by, each this long: the frames that update every frame (the
-- bars' driver, the pulse's) run once a frame.
local function Frames(ns, count, elapsed)
    for _ = 1, count do
        for _, driver in ipairs({ ns.Bars.driver or false, ns.Pulse.driver or false }) do
            local run = driver and S[driver].scripts.OnUpdate
            if run then run(driver, elapsed) end
        end
    end
end
-- The timers queued since the last ones ran, each run once.
local function Later()
    while ran < #timers do
        ran = ran + 1
        timers[ran]()
    end
end
-- The next frame: the timers queued since, then the frames that update
-- every frame, each once.
local function NextFrame(ns)
    Later()
    Frames(ns, 1, 0)
end

-- What the addon's own files ask while fn runs: every call from one of them
-- straight into the mock game (a frame's or texture's method, C_Spell's, a
-- function of the game's) by name, with game.all for all of them; the
-- addon's own functions run, by name; and how many different ones ran (a
-- function made anew each time shows up as another one).
local SELF = debug.getinfo(1, "S").source
local function AddonFile(source)
    return source ~= nil and source ~= SELF and source:sub(1, 1) == "@" and not source:find("Tools", 1, true)
end
local function Measure(fn)
    local game, addon, seen, made = { all = 0 }, {}, {}, 0
    debug.sethook(function()
        local callee = debug.getinfo(2, "Snf")
        if not callee then return end
        -- Who called it: the first Lua function up the stack, past the
        -- game's own (pcall, say).
        local from
        for level = 3, 12 do
            local info = debug.getinfo(level, "S")
            if not info then break end
            if info.what ~= "C" and info.what ~= "J" then
                from = info.source
                break
            end
        end
        if not AddonFile(from) then return end
        local name = callee.name or "?"
        if callee.source == SELF then
            -- (The mock's own type(), which in the game is Lua's, isn't the game.)
            if name:sub(1, 2) ~= "__" and name ~= "type" then
                game[name] = (game[name] or 0) + 1
                game.all = game.all + 1
            end
        elseif AddonFile(callee.source) then
            addon[name] = (addon[name] or 0) + 1
            if not seen[callee.func] then
                seen[callee.func] = true
                made = made + 1
            end
        end
    end, "c")
    local ok, err = pcall(fn)
    debug.sethook()
    if not ok then error(err, 2) end
    return game, addon, made
end
-- Counts by name, as text: "3 0 1".
local function Counts(counted, ...)
    local out = {}
    for i, name in ipairs({ ... }) do out[i] = tostring(counted[name] or 0) end
    return table.concat(out, " ")
end
-- One line of the printed costs.
local function Note(label, game)
    io.write(("  %-62s %4d calls into the game\n"):format(label, game.all))
end
-- An icon's colour, as text.
local function Tint(icon)
    local tint = S[icon.texture].tint or { 1, 1, 1 }
    return tint[1] .. " " .. tint[2] .. " " .. tint[3]
end

-- Your bars in a fight: only what the game says changed is done again -----------------------------

do
    local ns = Start({ notesSeen = "dev", useBars = true })
    local B = ns.Bars
    local lit = {}
    _G.C_SpellActivationOverlay = { IsSpellOverlayed = function(id) return lit[id] end }
    for _, name in ipairs({ "Moonfire", "Wrath", "Overpower" }) do B:Assign(name, "cd") end
    local bar = B:Get("cd")
    local moon, over = bar.icons[1], bar.icons[3]
    Equal(bar.count .. " " .. moon.name .. " " .. over.name, "3 Moonfire Overpower", "three spells on the Cooldowns bar")
    target = true
    Fire("PLAYER_TARGET_CHANGED")
    NextFrame(ns)
    io.write("Your bars (3 spells, an enemy targeted), each event and the frame after it:\n")

    -- Standing there with an enemy targeted: nothing changes, nothing is asked.
    local game = Measure(function() Frames(ns, 60, 1 / 60) end)
    Note("a second of frames, nothing changing", game)
    Equal(game.all, 0, "a second with an enemy targeted and nothing changing: nothing asked or set (was 4 full refreshes)")

    -- A cooldown starts (every cast, for the global cooldown): only cooldowns.
    game = Measure(function()
        Fire("SPELL_UPDATE_COOLDOWN")
        NextFrame(ns)
    end)
    Note("SPELL_UPDATE_COOLDOWN (every cast)", game)
    Equal(Counts(game, "GetSpellCooldownDuration", "SetCooldownFromDurationObject", "SetDesaturated", "SetAlpha", "IsSpellUsable",
        "IsSpellInRange", "IsSpellOverlayed", "SetVertexColor", "Stop", "Hide"), "3 3 3 0 0 0 0 0 0 0",
        "a cooldown started: each spell's cooldown fed again, greyed or not; its alpha (in full) not set again; colour, range and glow left alone")
    game = Measure(function()
        Fire("BAG_UPDATE_COOLDOWN")
        NextFrame(ns)
    end)
    Note("BAG_UPDATE_COOLDOWN", game)
    Equal(Counts(game, "GetSpellCooldownDuration", "IsSpellUsable"), "3 0", "a bag cooldown: the same")
    -- Dim when ready: the game's own answer each time; back to Show, in full once.
    B:SetOption("cd", "whenReady", "dim")
    game = Measure(function()
        Fire("SPELL_UPDATE_COOLDOWN")
        NextFrame(ns)
    end)
    Equal(Counts(game, "SetAlphaFromBoolean", "SetAlpha"), "3 0", "dim when ready: the secret answer handed on each time")
    B:SetOption("cd", "whenReady", "show")
    Equal(S[moon].alpha, 1, "back to Show: in full")
    game = Measure(function()
        Fire("SPELL_UPDATE_COOLDOWN")
        NextFrame(ns)
    end)
    Equal(Counts(game, "SetAlphaFromBoolean", "SetAlpha"), "0 0", "and not set again")

    -- Usable, a glow, a new target: colours and glows, set only if changed.
    game = Measure(function()
        Fire("SPELL_UPDATE_USABLE")
        NextFrame(ns)
    end)
    Note("SPELL_UPDATE_USABLE, nothing changed", game)
    Equal(Counts(game, "GetSpellCooldownDuration", "IsSpellUsable", "IsSpellInRange", "IsSpellOverlayed", "SetVertexColor", "Stop", "Hide"),
        "0 3 3 3 0 0 0", "usable again: each spell asked if usable, in range and lit; nothing set while nothing changed; no cooldown read")
    usable[8924], noMana[8924] = false, true
    game = Measure(function()
        Fire("SPELL_UPDATE_USABLE")
        NextFrame(ns)
    end)
    Equal(Tint(moon) .. " | " .. Counts(game, "SetVertexColor"), "0.5 0.5 1 | 1", "out of mana: blue, one colour set")
    usable[8924], noMana[8924] = nil, nil
    Fire("SPELL_UPDATE_USABLE")
    NextFrame(ns)
    Equal(Tint(moon), "1 1 1", "and white again")
    lit[5176] = true
    Fire("SPELL_ACTIVATION_OVERLAY_GLOW_SHOW", 5176)
    NextFrame(ns)
    Equal(tostring(S[bar.icons[2].glow].shown), "true", "a proc lit by the game: Wrath glows on the next frame")
    lit[5176] = nil
    Fire("SPELL_ACTIVATION_OVERLAY_GLOW_HIDE", 5176)
    NextFrame(ns)
    Equal(tostring(S[bar.icons[2].glow].shown), "false", "and goes out with it")

    -- A reactive glow put out once, not again and again.
    usable[7384] = false
    Fire("SPELL_UPDATE_USABLE")
    game = Measure(function() NextFrame(ns) end)
    Equal(tostring(S[over.glow].shown) .. " " .. Counts(game, "Stop", "Hide"), "false 2 1",
        "Overpower used: its glow goes, burst and loop stopped")
    Fire("SPELL_UPDATE_USABLE")
    game = Measure(function() NextFrame(ns) end)
    Equal(Counts(game, "Stop", "Hide"), "0 0", "and nothing stopped or hidden again while it stays out (was every refresh)")
    usable[7384] = nil
    Fire("SPELL_UPDATE_USABLE")
    NextFrame(ns)
    Equal(tostring(S[over.glow].shown), "true", "usable again: lit again")

    -- Range: the game says when a spell goes in or out of range.
    range[8924] = false
    game = Measure(function()
        Fire("SPELL_RANGE_CHECK_UPDATE", 8924, false, true)
        NextFrame(ns)
    end)
    Note("SPELL_RANGE_CHECK_UPDATE (Moonfire out of range)", game)
    Equal(Tint(moon) .. " | " .. Counts(game, "SetVertexColor", "GetSpellCooldownDuration"), "0.64 0.15 0.15 | 1 0",
        "out of range: red as the game says so, one colour set, no cooldown read")
    range[8924] = nil
    Fire("SPELL_RANGE_CHECK_UPDATE", 8924, true, true)
    NextFrame(ns)
    Equal(Tint(moon), "1 1 1", "back in range: white again")
    range[8924] = false
    Frames(ns, 60, 1 / 60)
    Equal(Tint(moon), "1 1 1", "moving with no word from the game: nothing asked, so nothing changes")
    Fire("SPELL_RANGE_CHECK_UPDATE", 8924, false, true)
    NextFrame(ns)
    Equal(Tint(moon), "0.64 0.15 0.15", "until it says")
    range[8924] = SECRET
    Fire("SPELL_RANGE_CHECK_UPDATE", SECRETS.number, SECRETS.boolean, SECRETS.boolean)
    NextFrame(ns)
    Equal(Tint(moon), "1 1 1", "a hidden range answer, and an event with hidden values, never read")
    range[8924] = nil

    -- Dim when you can't cast it: only a change in whether you can feeds a
    -- spell's cooldown again (its opacity takes both), that spell's alone;
    -- nothing while nothing changes, and nothing at all unticked.
    B:SetOption("cd", "dimUnusable", true)
    game = Measure(function()
        Fire("SPELL_UPDATE_USABLE")
        NextFrame(ns)
    end)
    Equal(Counts(game, "GetSpellCooldownDuration", "SetAlpha", "SetAlphaFromBoolean"), "0 0 0",
        "ticked, nothing changed: no cooldown read, no opacity set")
    usable[8924], noMana[8924] = false, true
    game = Measure(function()
        Fire("SPELL_UPDATE_USABLE")
        NextFrame(ns)
    end)
    Equal(S[moon].alpha .. " | " .. Counts(game, "GetSpellCooldownDuration", "SetAlpha"), "0.4 | 1 1",
        "out of mana: Moonfire alone fed again, and dimmed")
    game = Measure(function()
        Fire("SPELL_UPDATE_USABLE")
        NextFrame(ns)
    end)
    Equal(Counts(game, "GetSpellCooldownDuration", "SetAlpha"), "0 0", "still out of mana: nothing again")
    range[8924] = false
    game = Measure(function()
        Fire("SPELL_RANGE_CHECK_UPDATE", 8924, false, true)
        NextFrame(ns)
    end)
    Equal(Tint(moon) .. " " .. S[moon].alpha .. " | " .. Counts(game, "GetSpellCooldownDuration", "SetAlpha"), "0.64 0.15 0.15 0.4 | 0 0",
        "out of range as well: red now, still can't cast it, so its opacity is left as it is")
    usable[8924], noMana[8924], range[8924] = nil, nil, nil
    game = Measure(function()
        Fire("SPELL_RANGE_CHECK_UPDATE", 8924, true, true)
        NextFrame(ns)
    end)
    Equal(S[moon].alpha .. " | " .. Counts(game, "GetSpellCooldownDuration", "SetAlpha"), "1 | 1 1", "castable again: in full, fed once")
    B:SetOption("cd", "dimUnusable", false)
    usable[8924], noMana[8924] = false, true
    game = Measure(function()
        Fire("SPELL_UPDATE_USABLE")
        NextFrame(ns)
    end)
    Equal(S[moon].alpha .. " | " .. Counts(game, "GetSpellCooldownDuration", "SetAlpha"), "1 | 0 0",
        "unticked: out of mana reads no cooldown, and it stays in full")
    usable[8924], noMana[8924] = nil, nil
    Fire("SPELL_UPDATE_USABLE")
    NextFrame(ns)

    -- A new target: colours and glows (range, Execute's usable), no cooldowns.
    game = Measure(function()
        target = false
        Fire("PLAYER_TARGET_CHANGED")
        NextFrame(ns)
    end)
    Note("PLAYER_TARGET_CHANGED (target lost)", game)
    Equal(Counts(game, "GetSpellCooldownDuration", "IsSpellUsable", "IsSpellInRange"), "0 3 0",
        "a target lost: usable asked again, range not (no target), no cooldown read")
    range[8924] = false
    game = Measure(function()
        target = true
        Fire("PLAYER_TARGET_CHANGED")
        NextFrame(ns)
    end)
    Equal(Tint(moon) .. " | " .. Counts(game, "GetSpellCooldownDuration", "IsSpellInRange"), "0.64 0.15 0.15 | 0 3",
        "a new target out of range: red at once")
    range[8924] = nil
    Fire("SPELL_RANGE_CHECK_UPDATE", 8924, true, true)
    NextFrame(ns)

    -- A cooldown ending: cooldowns.
    game = Measure(function()
        S[moon.cooldown].scripts.OnCooldownDone(moon.cooldown)
        NextFrame(ns)
    end)
    Note("a cooldown ending (OnCooldownDone)", game)
    Equal(Counts(game, "GetSpellCooldownDuration", "IsSpellUsable"), "3 0", "a cooldown ending: cooldowns fed again, nothing else asked")

    -- A cast's burst of events: every icon once, in full.
    game = Measure(function()
        for _, event in ipairs({ "SPELL_UPDATE_COOLDOWN", "SPELL_UPDATE_USABLE", "BAG_UPDATE_COOLDOWN", "SPELL_UPDATE_USABLE" }) do
            Fire(event)
        end
        NextFrame(ns)
        NextFrame(ns)
    end)
    Note("a cast's burst: 4 events in one frame", game)
    Equal(Counts(game, "GetSpellCooldownDuration", "IsSpellUsable"), "3 3", "a cast's burst: every icon once, in full, on the next frame")

    -- In a fight, with secrets: the same parts, nothing read.
    B:SetOption("cd", "whenReady", "dim")
    lockdown = true
    Fire("PLAYER_REGEN_DISABLED")
    active, usable[8924], range[8924] = SECRET, SECRET, SECRET
    Fire("SPELL_UPDATE_COOLDOWN")
    Fire("SPELL_UPDATE_USABLE")
    NextFrame(ns)
    Equal(tostring(S[moon].alphaFrom) .. " " .. Tint(moon), "secret 1 1 1", "in a fight: secrets handed on to the game or left unread")
    -- On cooldown and Dim when you can't cast it too: the cooldown handed
    -- on, a hidden usable answer taken as castable.
    B:SetOption("cd", "onCooldown", "hide")
    B:SetOption("cd", "dimUnusable", true)
    Fire("SPELL_UPDATE_USABLE")
    NextFrame(ns)
    Equal(tostring(S[moon].alphaFrom) .. " " .. S[moon].alphaIf .. " " .. Tint(moon), "secret 0 0.4 1 1 1",
        "in a fight: hidden while cooling down, dimmed while ready, by the game; nothing dimmed for a hidden answer")
    B:SetOption("cd", "onCooldown", "show")
    B:SetOption("cd", "dimUnusable", false)
    B:SetOption("cd", "whenReady", "show")
    active, usable[8924], range[8924] = false, nil, nil
    lockdown = false
    Fire("PLAYER_REGEN_ENABLED")
    NextFrame(ns)
    _G.C_SpellActivationOverlay = nil
    Equal(#printed, 0, "no errors")
end

-- Show the global cooldown: a sweep of its own, fed only as cooldowns change ------------------------
-- Off (the default) nothing more is made or asked. Ticked on a bar, each of
-- its spell icons gets a second sweep, made once, with no numbers and no
-- flash, in the icon's own swipe. It's fed the spell's cooldown with the
-- global cooldown counted as the cooldowns are fed (a cast, a cooldown
-- ending), never as colours or range change, and is see-through while the
-- spell's own cooldown runs: by the game's own answer, handed on unread in
-- a fight. Each bar its own; unticked, each sweep is cleared once and never
-- fed again; a spot that turns into an item loses its sweep.

do
    local ns = Start({ notesSeen = "dev", useBars = true })
    local B = ns.Bars
    -- The game's cooldown with the global one counted, which only the sweep
    -- asks for (the mock game's own, which the bars always ask for, is
    -- without it), and the spells it was asked for.
    local counted = { IsActive = function() return Typed("boolean", true) end }
    local without, asked = C_Spell.GetSpellCooldownDuration, {}
    C_Spell.GetSpellCooldownDuration = function(id, ignoreGCD)
        if ignoreGCD == false then
            asked[#asked + 1] = id
            return counted
        end
        return without(id, ignoreGCD)
    end
    for _, name in ipairs({ "Moonfire", "Wrath", "Overpower" }) do B:Assign(name, "cd") end
    B:Assign("Thorns", "util")
    local bar, util = B:Get("cd"), B:Get("util")
    local moon = bar.icons[1]
    Equal(tostring(ns.BarData("cd").showGCD) .. " " .. tostring(ns.BarData("util").showGCD) .. " " .. tostring(rawget(moon, "gcd"))
        .. " " .. #asked, "false false nil 0", "off at first, on each bar: no sweep made, nothing asked with the global cooldown")
    local game = Measure(function()
        Fire("SPELL_UPDATE_COOLDOWN")
        NextFrame(ns)
    end)
    Equal(Counts(game, "GetSpellCooldownDuration", "SetCooldownFromDurationObject", "SetAlphaFromBoolean", "CreateFrame") .. " " .. #asked,
        "4 4 0 0 0", "off, a cast: each spell's own cooldown fed, as before, and nothing more")

    -- Ticked on Cooldowns: a sweep of its own on each spell icon there, fed at once.
    game = Measure(function() B:SetOption("cd", "showGCD", true) end)
    local gcd = rawget(moon, "gcd")
    local s = S[gcd]
    Equal(tostring(gcd ~= nil) .. " " .. s.kind .. " " .. s.template .. " " .. tostring(s.parent == moon) .. " "
        .. tostring(Last(gcd, "SetAllPoints") == moon.texture) .. " " .. tostring(Last(gcd, "SetHideCountdownNumbers")) .. " "
        .. tostring(Last(gcd, "SetDrawBling")) .. " " .. tostring(Last(gcd, "SetSwipeTexture") == Last(moon.cooldown, "SetSwipeTexture"))
        .. " " .. Counts(game, "CreateFrame"),
        "true Cooldown CooldownFrameTemplate true true true false true 3",
        "ticked: a sweep of its own on each of the three spell icons, over the icon's art, no numbers, no flash, the icon's swipe")
    Equal(tostring(Last(gcd, "SetCooldownFromDurationObject") == counted) .. " " .. s.alphaIf .. " " .. s.alpha .. " | "
        .. table.concat(asked, " ") .. " | " .. tostring(rawget(util.icons[1], "gcd")),
        "true 0 1 1 | 8924 5176 7384 | nil",
        "fed the cooldown with the global one counted, shown while the spell's own isn't running; Utility's, unticked, has none")

    -- A cast: the sweeps fed with the cooldowns, made no more.
    asked = {}
    game = Measure(function()
        Fire("SPELL_UPDATE_COOLDOWN")
        NextFrame(ns)
    end)
    Note("SPELL_UPDATE_COOLDOWN, Show the global cooldown ticked", game)
    Equal(Counts(game, "GetSpellCooldownDuration", "SetCooldownFromDurationObject", "SetAlphaFromBoolean", "CreateFrame") .. " " .. #asked,
        "7 7 3 0 3", "ticked, a cast: each spell's own cooldown and, on Cooldowns, its sweep fed; nothing made")
    asked = {}
    game = Measure(function()
        Fire("SPELL_UPDATE_USABLE")
        NextFrame(ns)
    end)
    Equal(Counts(game, "GetSpellCooldownDuration", "SetCooldownFromDurationObject", "SetAlphaFromBoolean") .. " " .. #asked, "0 0 0 0",
        "usable, range or a glow: the sweeps aren't fed")

    -- The spell's own cooldown running: see-through, so it keeps showing as
    -- before; done (in the global cooldown, say), the sweep shows again.
    active = true
    Fire("SPELL_UPDATE_COOLDOWN")
    NextFrame(ns)
    Equal(s.alpha .. " " .. tostring(S[moon.texture].desaturated) .. " " .. tostring(Last(moon.cooldown, "SetHideCountdownNumbers")),
        "0 true false", "its own cooldown running: the sweep see-through; the icon greyed and counting down as ever")
    active = false
    S[moon.cooldown].scripts.OnCooldownDone(moon.cooldown)
    NextFrame(ns)
    Equal(s.alpha .. " " .. tostring(S[moon.texture].desaturated), "1 false", "its own cooldown done: the sweep shows again")

    -- In a fight: the game's answers handed on unread.
    lockdown = true
    Fire("PLAYER_REGEN_DISABLED")
    active = SECRET
    Fire("SPELL_UPDATE_COOLDOWN")
    NextFrame(ns)
    Equal(tostring(s.alphaFrom) .. " " .. s.alphaIf .. " " .. tostring(Last(gcd, "SetCooldownFromDurationObject") == counted),
        "secret 0 1 true", "in a fight: whether its own cooldown runs handed to the game as it is, the sweep fed as ever")
    active = false
    lockdown = false
    Fire("PLAYER_REGEN_ENABLED")
    NextFrame(ns)

    -- Icon details: the sweeps in the swipe picked, with the icons'.
    ns.Set("swipeColour", "white")
    ns.Style:ApplyDetails()
    local mine, its = S[gcd].last.SetSwipeColor, S[moon.cooldown].last.SetSwipeColor
    Equal(table.concat({ mine[1], mine[2], mine[3], mine[4] }, " ") .. " | " .. its[1] .. " " .. its[2] .. " " .. its[3],
        table.concat({ its[1], its[2], its[3], its[4] }, " ") .. " | 1 1 1", "Icon details changed: each sweep in the same swipe as its icon")
    ns.Set("swipeColour", "black")
    ns.Style:ApplyDetails()

    -- /ccm debug says so, for the bar ticked.
    local report = ns.DebugReport()
    Equal(select(2, report:gsub("dimmed icons 40%%, global cooldown shown, show only when I can't afford it false\n", "")), 1, "the debug report says so, for Cooldowns only")

    -- A spot that turns into an item: its sweep cleared, and not fed.
    itemCount[118] = 1
    B:TakeOff("cd", "Overpower")
    B:Assign("family:healing", "cd")
    local spot = bar.icons[3]
    asked = {}
    Fire("SPELL_UPDATE_COOLDOWN")
    NextFrame(ns)
    Equal(spot.kind .. " " .. tostring(spot.gcdShown) .. " " .. tostring(S[spot.gcd].last.Clear ~= nil) .. " " .. table.concat(asked, " "),
        "family nil true 8924 5176", "a spot that turns into a potion: its sweep cleared, and only the spells' fed")
    B:TakeOff("cd", "family:healing")
    B:Assign("Overpower", "cd")

    -- Unticked: each sweep cleared once, then never fed or cleared again.
    s.last.Clear = nil
    B:SetOption("cd", "showGCD", false)
    Equal(tostring(moon.gcdShown) .. " " .. tostring(s.last.Clear ~= nil), "nil true", "unticked: each sweep cleared")
    s.last.Clear, asked = nil, {}
    game = Measure(function()
        Fire("SPELL_UPDATE_COOLDOWN")
        NextFrame(ns)
    end)
    Equal(Counts(game, "GetSpellCooldownDuration", "SetAlphaFromBoolean") .. " " .. #asked .. " " .. tostring(s.last.Clear),
        "4 0 0 nil", "and after: only the spells' own cooldowns fed, as before it was ticked")
    C_Spell.GetSpellCooldownDuration = without
    Equal(#printed, 0, "no errors")
end

-- Range watched as Blizzard's own Cooldown Manager watches it ----------------------------------------
-- Each spell icon asks the game to watch its spell (EnableSpellRangeCheck)
-- while your bars are on, and lets it go as it changes spell or the bars go
-- off: one ask and one let-go each, so the game's own watch of the same
-- spell (Blizzard's Cooldown Manager) is never undone.

do
    local ns = Start({ notesSeen = "dev", useBars = true })
    local B = ns.Bars
    for _, name in ipairs({ "Moonfire", "Wrath", "Overpower" }) do B:Assign(name, "cd") end
    local function Watched()
        return tostring(RangeChecks[8924] or 0) .. " " .. tostring(RangeChecks[5176] or 0) .. " " .. tostring(RangeChecks[7384] or 0)
    end
    Equal(Watched(), "1 1 1", "each spell on your bars watched for range, once")
    Equal(tostring(S[B.driver].events.SPELL_RANGE_CHECK_UPDATE), "true", "and the game's word on it heard")
    B:Rebuild()
    Equal(Watched(), "1 1 1", "laid out again: still once each")
    C_Spell.EnableSpellRangeCheck(8924, true) -- Blizzard's own, for its Moonfire
    B:TakeOff("cd", "Wrath")
    Equal(Watched(), "2 0 1", "taken off the bar: let go of")
    NoRange[5176] = true
    B:Assign("Wrath", "cd")
    Equal(Watched(), "2 0 1", "a spell with no range (one on yourself) has nothing to watch")
    NoRange[5176] = nil
    ns.Set("useBars", false)
    B:Rebuild()
    Equal(Watched(), "1 0 0", "bars off: every watch of theirs let go, Blizzard's own kept")
    ns.Set("useBars", true)
    B:Rebuild()
    Equal(Watched(), "2 1 1", "on again: watched again")
    -- Items have no range: a potion and a trinket on the bar aren't watched.
    local before = 0
    for _ in pairs(RangeChecks) do before = before + 1 end
    itemCount[118] = 1
    B:Assign("family:healing", "cd")
    local after = 0
    for _ in pairs(RangeChecks) do after = after + 1 end
    Equal(after - before, 0, "a potion on the bar: nothing watched for it")
    C_Spell.EnableSpellRangeCheck(8924, false)
    -- A client without the range watch: the bars still work.
    local enable = C_Spell.EnableSpellRangeCheck
    C_Spell.EnableSpellRangeCheck = nil
    B:TakeOff("cd", "Moonfire")
    B:Assign("Moonfire", "cd")
    C_Spell.EnableSpellRangeCheck = enable
    Equal(#printed, 0, "no errors")
end

-- Borders and shadows: set only when something changed ---------------------------------------------

do
    local ns = Start({ notesSeen = "dev" })
    local Style = ns.Style
    local owner, other = CreateFrame("Frame"), CreateFrame("Frame")
    local decor = Style:Decor(owner, owner, 2)
    local game = Measure(function() Style:ShowDecor(decor, false, false) end)
    Equal(tostring(decor.border) .. " " .. game.all, "nil 0", "both off: nothing made, nothing set")
    Style:ShowDecor(decor, true, true)
    local top, glow = decor.border[1], decor.shadow[1][1]
    local function At(strip)
        local p = S[strip].points[1]
        return p[1] .. " " .. tostring(p[2] == owner and "owner" or p[2] == other and "other") .. " " .. p[4] .. " " .. p[5]
    end
    Equal(At(top) .. " | " .. At(glow) .. " | " .. tostring(S[top].shown) .. " " .. tostring(S[glow].shown),
        "BOTTOMLEFT owner 1 -2 | BOTTOMLEFT owner 0 -1 | true true", "a border on the art's edge, the shadow just outside it")
    game = Measure(function() Style:ShowDecor(decor, true, true) end)
    io.write("Borders and shadows:\n")
    Note("asked again, nothing changed (Blizzard's rows: each relayout)", game)
    Equal(game.all, 0, "asked again with nothing changed: nothing set (was 20 strips placed and shown again)")
    decor.region = other
    Style:ShowDecor(decor, true, true)
    Equal(At(top), "BOTTOMLEFT other 1 -2", "round something else: placed there")
    Style:ShowDecor(decor, false, true)
    Equal(tostring(S[top].shown) .. " " .. At(glow), "false BOTTOMLEFT other 1 -2", "border off: the shadow moves in to the edge")
    game = Measure(function() Style:ShowDecor(decor, false, false) end)
    Equal(Counts(game, "ClearAllPoints", "SetPoint") .. " " .. tostring(S[glow].shown), "0 0 false", "both off: hidden, not placed")
    decor.region, decor.inset = owner, 0
    game = Measure(function() Style:ShowDecor(decor, false, false) end)
    Equal(game.all, 0, "moved while off: nothing set")
    Style:ShowDecor(decor, true, false)
    Equal(At(top) .. " " .. tostring(S[top].shown) .. " " .. tostring(S[glow].shown), "BOTTOMLEFT owner -1 0 true false",
        "shown again: placed where it is now")
    Equal(#printed, 0, "no errors")
end

-- Icons drawn like Blizzard's: nothing more in a fight, nothing again on a relayout ----------------
-- (Icon details' Icons.) Each icon is drawn as it's laid out at a new size
-- or in a new style, never again while neither changes: a relayout sets
-- nothing on its art, mask, frame or sweeps. In a fight the icons cost what
-- square ones do; Blizzard's range shadow is set only as an icon goes in or
-- out of range, with its tint.

do
    local ns = Start({ notesSeen = "dev", useBars = true, iconStyle = "blizzard" })
    local B = ns.Bars
    for _, name in ipairs({ "Moonfire", "Wrath", "Overpower" }) do B:Assign(name, "cd") end
    local moon = B:Get("cd").icons[1]
    target = true
    Fire("PLAYER_TARGET_CHANGED")
    NextFrame(ns)
    Equal(moon.name .. " " .. #(S[moon.texture].masks or {}) .. " " .. tostring(S[moon.shape.frame].shown), "Moonfire 1 true",
        "your icons drawn like Blizzard's")
    io.write("Icons drawn like Blizzard's (3 spells, an enemy targeted):\n")
    local game = Measure(function() Frames(ns, 60, 1 / 60) end)
    Note("a second of frames, nothing changing", game)
    Equal(game.all, 0, "a second with nothing changing: nothing asked or set")
    game = Measure(function()
        Fire("SPELL_UPDATE_COOLDOWN")
        NextFrame(ns)
    end)
    Note("SPELL_UPDATE_COOLDOWN (every cast)", game)
    Equal(Counts(game, "GetSpellCooldownDuration", "SetCooldownFromDurationObject", "SetDesaturated", "SetShown", "SetSwipeTexture",
        "SetPoint", "SetTexCoord"), "3 3 3 0 0 0 0", "a cooldown started: the same as square icons, nothing of Blizzard's look set again")
    range[8924] = false
    game = Measure(function()
        Fire("SPELL_RANGE_CHECK_UPDATE", 8924, false, true)
        NextFrame(ns)
    end)
    Note("SPELL_RANGE_CHECK_UPDATE (Moonfire out of range)", game)
    local far = Tint(moon) .. " " .. tostring(S[moon.shape.range].shown) .. " | " .. Counts(game, "SetVertexColor", "SetShown")
    range[8924] = nil
    game = Measure(function()
        Fire("SPELL_RANGE_CHECK_UPDATE", 8924, true, true)
        NextFrame(ns)
    end)
    Equal(far .. " || " .. Tint(moon) .. " " .. tostring(S[moon.shape.range].shown) .. " | " .. Counts(game, "SetVertexColor", "SetShown"),
        "0.64 0.15 0.15 true | 1 1 || 1 1 1 false | 1 1", "out of range: red and Blizzard's shadow, one of each set; back in range the same")
    game = Measure(function() B:Rebuild() end)
    Note("laid out again, nothing changed", game)
    Equal(Counts(game, "SetTexCoord", "AddMaskTexture", "RemoveMaskTexture", "SetAtlas", "SetSwipeTexture", "CreateMaskTexture"),
        "0 0 0 0 0 0", "laid out again with nothing changed: nothing of Blizzard's look set again or made")
    Equal(#printed, 0, "no errors")
end

-- Your cast bar and swing timer: sized once, coloured as the colour changes ------------------------

do
    local ns = Start({ notesSeen = "dev", castBar = true, iconShadow = "bar" })
    local C = ns.CastBar
    local cb = C.row
    local casting = { "Wrath", "Wrath", 136006, 100000, 101500, false, "cast-1" }
    _G.UnitCastingInfo = function(unit)
        assert(unit == "player")
        return table.unpack(casting)
    end
    clock = 100
    Fire("UNIT_SPELLCAST_START", "player", "cast-1", 5176)
    Equal(Last(cb.bar, "SetStatusBarColor", 1) .. " " .. Last(cb.bar, "SetStatusBarColor", 2) .. " " .. S[cb].height .. " "
        .. tostring(cb.decor.shadow and S[cb.decor.shadow[1][1]].shown), "1 0.7 18 true", "a cast: Blizzard's gold, 18 tall, its shadow on")
    Fire("UNIT_SPELLCAST_STOP", "player", "cast-1", 5176)
    casting[7] = "cast-2"
    local LOOK = { "SetHeight", "SetSize", "ClearAllPoints", "SetPoint", "SetFontObject", "SetShown", "SetStatusBarTexture",
        "SetStatusBarColor", "SetColorTexture" }
    local game = Measure(function() Fire("UNIT_SPELLCAST_START", "player", "cast-2", 5176) end)
    io.write("Your cast bar (shadow on):\n")
    Note("a cast starting", game)
    Equal(Counts(game, table.unpack(LOOK)), "0 0 0 0 0 0 0 0 0",
        "the next cast in the same colour: nothing about its look set again, its shadow's 20 strips neither")
    Equal(S[cb.bar.name].text .. " " .. Last(cb.bar, "SetMinMaxValues", 2), "Wrath 1.5", "its name and length still set")
    game = Measure(function() Fire("UNIT_SPELLCAST_INTERRUPTED", "player", "cast-2", 5176) end)
    Equal(Last(cb.bar, "SetStatusBarColor", 1) .. " " .. Counts(game, "SetStatusBarColor", "SetColorTexture", "SetHeight"), "0.85 1 1 0",
        "broken off: red, its colour set once, nothing resized")
    _G.UnitChannelInfo = function() return "Tranquility", "Tranquility", 136107, 102000, 110000, false, false, 740 end
    clock = 102
    Fire("UNIT_SPELLCAST_CHANNEL_START", "player", nil, 740)
    Equal(Last(cb.bar, "SetStatusBarColor", 2), .8, "a channel: green")
    Fire("UNIT_SPELLCAST_CHANNEL_STOP", "player", nil, 740)
    _G.UnitChannelInfo = function() return nil end
    -- A choice changed: sized again at once, or with the next cast.
    ns.Set("castHeight", 24)
    C:Apply()
    Equal(S[cb].height .. " " .. S[cb.icon].width, "24 24", "a new height: sized again at once")
    -- Every other choice it's sized by, each on its own: at once too.
    ns.Set("castName", false)
    C:Apply()
    Equal(tostring(S[cb.bar.name].shown) .. " " .. tostring(S[cb.bar.time].shown), "false true", "the name unticked: hidden at once")
    ns.Set("castTime", false)
    C:Apply()
    Equal(tostring(S[cb.bar.name].shown) .. " " .. tostring(S[cb.bar.time].shown), "false false", "the time unticked: hidden at once")
    ns.Set("castName", true)
    ns.Set("castTime", true)
    C:Apply()
    local function Reach() return S[cb.decor.shadow[1][3]].points[1][4] end
    local before = Reach()
    ns.Set("iconBorder", "bar")
    C:Apply()
    Equal(before .. " " .. Reach(), "0 -1", "a border picked round your rows: the cast bar's shadow moves out with theirs at once")
    ns.Set("iconBorder", "off")
    C:Apply()
    ns.Set("barStyle", "outline")
    casting[7] = "cast-3"
    Fire("UNIT_SPELLCAST_START", "player", "cast-3", 5176)
    Equal(Last(cb.bar, "SetStatusBarColor", 4) .. " " .. table.concat(Last(cb.bar.edge, "SetColorTexture") and { Last(cb.bar.edge, "SetColorTexture", 1),
        Last(cb.bar.edge, "SetColorTexture", 2) } or {}, " "), "0.45 1 0.7", "Outline picked: the next cast see-through, inside a gold edge")
    -- A colour with the same red as the last one (orange after Blizzard's gold): still set.
    ns.Set("castColour", "orange")
    C:Apply()
    Equal(Last(cb.bar, "SetStatusBarColor", 1) .. " " .. Last(cb.bar, "SetStatusBarColor", 2), "1 0.5", "orange after gold: set at once")
    ns.Set("castColour", "default")
    C:Apply()
    ns.Set("barStyle", "glass")
    ns.Set("barTexture", "raid")
    casting[7] = "cast-4"
    Fire("UNIT_SPELLCAST_START", "player", "cast-4", 5176)
    Equal(Last(cb.bar, "SetStatusBarTexture") .. " " .. Last(cb.bar, "SetStatusBarColor", 4) .. " " .. Last(cb.bar.edge, "SetColorTexture", 1),
        "Interface\\RaidFrame\\Raid-Bar-Hp-Fill 1 0", "a new texture: set, the colour after it, the edge black again")
    ns.Set("iconShadow", "off")
    C:Apply()
    Equal(tostring(S[cb.decor.shadow[1][1]].shown), "false", "shadow off: gone at once")
    -- Darkness and thick edges (Look page): set with the next fit, then
    -- nothing again per cast, not even where the fill ends.
    local fill = cb.bar:CreateTexture()
    rawset(cb.bar, "GetStatusBarTexture", function() return fill end)
    ns.Set("barDarkness", 60)
    ns.Set("thickEdges", true)
    C:Apply()
    Equal(tostring(S[cb.bar.sheen.rest].shown) .. " " .. tostring(S[cb.bar.inner[1]].shown) .. " "
        .. tostring(S[cb.iconInner[1]].shown), "true true true", "darkened and thick: the empty part's shine apart, a second pixel inside the edges")
    casting[7] = "cast-5"
    game = Measure(function() Fire("UNIT_SPELLCAST_START", "player", "cast-5", 5176) end)
    Note("a cast starting (darkness and thick edges on)", game)
    Equal(Counts(game, table.unpack(LOOK)) .. " " .. Counts(game, "GetStatusBarTexture"), "0 0 0 0 0 0 0 0 0 0",
        "the next cast, darkened and thick: nothing about its look set again, the fill not asked for")
    ns.Set("barDarkness", 0)
    ns.Set("thickEdges", false)
    C:Apply()
    Equal(#printed, 0, "no errors")

    -- The swing timer alone.
    ns = Start({ notesSeen = "dev", swingTimer = true, iconShadow = "bar" })
    cb = ns.CastBar.row
    Fire("PLAYER_SWING", 2.5, 0)
    Equal(Last(cb.bar, "SetStatusBarColor", 1) .. " " .. S[cb.bar.name].text, "0.66 Main hand", "a swing: silver")
    game = Measure(function() Fire("PLAYER_SWING", 2.5, 0) end)
    Note("a swing (swing timer on)", game)
    Equal(Counts(game, table.unpack(LOOK)), "0 0 0 0 0 0 0 0 0", "the next swing: nothing about its look set again")
    Equal(#printed, 0, "no errors")
end

-- Keys after a form change: worked out once, set only where they change -------------------------------

do
    local ns = Start({ notesSeen = "dev", useBars = true, keybinds = true })
    local B, K = ns.Bars, ns.Keybinds
    B:Assign("Moonfire", "cd")
    B:Assign("Wrath", "cd")
    local bar = B:Get("cd")
    local moon, wrath = bar.icons[1], bar.icons[2]
    actionSlots[1], keyOf.ACTIONBUTTON1 = { "spell", 8924 }, "1"
    actionSlots[2], keyOf.ACTIONBUTTON2 = { "spell", 5176 }, "2"
    actionSlots[85] = { "spell", 5176 } -- the form's page: Wrath under the first key
    K:Update()
    NextFrame(ns)
    Equal(S[moon.key].text .. " " .. S[wrath.key].text, "1 2", "keys from your action bars")
    lockdown = true
    bonusIndex = 8
    local game, addon = Measure(function()
        Fire("UPDATE_SHAPESHIFT_FORM")
        Fire("UPDATE_BONUS_ACTIONBAR")
        Fire("ACTIONBAR_PAGE_CHANGED")
    end)
    Equal(S[moon.key].text .. " " .. Counts(addon, "Resolve"), "1 0", "a form change's three events: nothing worked out yet")
    game, addon = Measure(Later)
    io.write("Keys (keybinds on, 2 icons):\n")
    Note("a form change: 3 events, then the next frame", game)
    Equal(tostring(S[moon.key].shown) .. " " .. S[wrath.key].text .. " " .. Counts(addon, "Resolve"), "false 1 1",
        "worked out once on the next frame: the form's page, in a fight")
    Fire("UPDATE_BONUS_ACTIONBAR")
    game = Measure(Later)
    Note("the same page again", game)
    Equal(Counts(game, "SetText", "SetShown", "SetPoint", "ClearAllPoints"), "0 0 0 0", "the same page again: no key set again")
    bonusIndex = nil
    Fire("UPDATE_BONUS_ACTIONBAR")
    Later()
    Equal(S[moon.key].text .. " " .. S[wrath.key].text, "1 2", "out of the form: the main page's keys back")
    lockdown = false
    -- Keybinds off: nothing looked up as the bars are laid out.
    ns.Set("keybinds", false)
    K:Update()
    game, addon = Measure(function() B:Rebuild() end)
    Equal(Counts(addon, "KeyFor", "ForEntry") .. " " .. tostring(S[moon.key].shown), "0 0 false",
        "keybinds off: no key looked up as the bars are laid out, none shown")
    Equal(#printed, 0, "no errors")
end

-- Key press glow: each frame only asks the buttons watched, and sets nothing until one changes -------
-- (Squirt's yes, 15 Nov 2026.) Off (the default), no button is looked up as
-- the keys are worked out and nothing runs every frame for it. Ticked, the
-- addon's own frame asks each watched button its state once a frame, in a
-- fight too, and the border is made and shown only as a key goes down,
-- hidden only as it comes up.

do
    local ns = Start({ notesSeen = "dev", useBars = true, keybinds = true })
    local B, K = ns.Bars, ns.Keybinds
    B:Assign("Moonfire", "cd")
    B:Assign("Wrath", "cd")
    local moon = B:Get("cd").icons[1]
    actionSlots[1], keyOf.ACTIONBUTTON1 = { "spell", 8924 }, "1"
    actionSlots[2], keyOf.ACTIONBUTTON2 = { "spell", 5176 }, "2"
    local states, asked = {}, 0
    local function Button()
        local button = setmetatable({}, { __index = function(_, key)
            if key == "GetButtonState" then
                return function(self)
                    asked = asked + 1
                    return states[self]
                end
            end
        end, __newindex = function(_, key) error("the addon wrote " .. tostring(key) .. " on a bar button") end })
        states[button] = "NORMAL"
        return button
    end
    _G.ActionButton1, _G.ActionButton2 = Button(), Button()
    K:Update()
    NextFrame(ns)
    -- Off: the keys worked out with no button looked up; nothing every frame.
    local _, addon = Measure(function() K:Update() end)
    Equal(Counts(addon, "ButtonsForEntry", "FindButtons", "Watch") .. " " .. tostring(B.pressDriver) .. " " .. asked, "0 0 0 nil 0",
        "off (the default): no button looked up as the keys are read, no frame made for it, none asked")
    ns.Set("keyPressGlow", true)
    K:Update()
    B:ApplyKeyPress()
    local driver = B.pressDriver
    local run = S[driver].scripts.OnUpdate
    local function Second() for _ = 1, 60 do run(driver, 1 / 60) end end
    lockdown = true
    local game
    game, addon = Measure(Second)
    io.write("Key press glow (2 icons watched):\n")
    Note("a second of frames, nothing held", game)
    local SETS = { "CreateTexture", "SetColorTexture", "SetShown", "Show", "Hide", "SetPoint", "ClearAllPoints", "SetHeight", "SetWidth" }
    Equal(asked .. " " .. Counts(game, table.unpack(SETS)) .. " " .. Counts(addon, "Held", "Light"), "120 0 0 0 0 0 0 0 0 0 120 120",
        "a second, nothing held, in a fight: each button asked once a frame (each icon's once), nothing made or set")
    states[ActionButton1] = "PUSHED"
    asked = 0
    game = Measure(Second)
    Note("a second of frames, a key held down", game)
    Equal(asked .. " " .. Counts(game, table.unpack(SETS)), "120 4 4 4 0 4 8 4 2 2",
        "held: the border made once (four sides, each placed), shown once, nothing set again while it stays held")
    game = Measure(Second)
    Equal(Counts(game, table.unpack(SETS)), "0 0 0 0 0 0 0 0 0", "still held: nothing set")
    states[ActionButton1] = "NORMAL"
    game = Measure(Second)
    Note("a second of frames, the key let go", game)
    Equal(Counts(game, table.unpack(SETS)) .. " " .. tostring(moon.pressLit), "0 0 4 0 0 0 0 0 0 false", "let go: hidden once, nothing else")
    lockdown = false
    -- Unticked: no OnUpdate at all, nothing asked.
    ns.Set("keyPressGlow", false)
    K:Update()
    B:ApplyKeyPress()
    asked = 0
    Equal(tostring(S[driver].scripts.OnUpdate) .. " " .. asked, "nil 0", "unticked: the OnUpdate taken off")
    _G.ActionButton1, _G.ActionButton2 = nil, nil
    Equal(#printed, 0, "no errors")
end

-- Only show missing: your buffs read as they change, once a frame, never in a fight -------------------

do
    local ns = Start({ notesSeen = "dev", useBars = true })
    local B = ns.Bars
    for _, name in ipairs({ "Thorns", "Clearcasting", "Nature's Grace" }) do B:SetAura("buff", name, true) end
    local bar = B:Get("buff")
    local function Burst()
        for _ = 1, 5 do Fire("UNIT_AURA", "player") end
        NextFrame(ns)
        Frames(ns, 60, 1 / 60)
    end
    local game, addon = Measure(Burst)
    Equal(Counts(game, "GetPlayerAuraBySpellID") .. " " .. Counts(addon, "OnEvent", "Missing") .. " "
        .. tostring(S[B.driver].events.UNIT_AURA), "0 0 0 nil", "off (the default): your buffs changing not heard, nothing read")
    B:SetOption("buff", "onlyMissing", true)
    local ids = 0
    for i = 1, bar.count do
        for _ in pairs(bar.slotIDs[i]) do ids = ids + 1 end
    end
    io.write("Only show missing (3 buffs on the Buffs bar, " .. ids .. " spell IDs):\n")
    game = Measure(function() Frames(ns, 60, 1 / 60) end)
    Note("a second of frames, nothing changing", game)
    Equal(game.all, 0, "on: a second with nothing changing, nothing asked or set (never polled)")
    -- (Each read goes through pcall, so it's counted by AuraReads, the mock's own count.)
    local reads = AuraReads
    game = Measure(Burst)
    Note("UNIT_AURA x5 and a second, nothing changed", game)
    Equal((AuraReads - reads) .. " " .. Counts(game, "SetAuraSlotEnabled", "SetShown", "SetPoint") .. " " .. tostring(game.all <= 3 * ids),
        ids .. " 0 0 0 true", "five changes in a frame: every ID read once (none up), nothing set while nothing changed")
    PlayerAuras[16870] = true
    reads = AuraReads
    game = Measure(Burst)
    Note("UNIT_AURA x5 and a second, Clearcasting cast", game)
    Equal(Counts(game, "SetAuraSlotEnabled", "SetPoint") .. " " .. tostring(AuraReads - reads <= ids),
        "1 2 true", "Clearcasting cast: read once, its slot switched off, the other two placed again")
    -- A fight: not heard, nothing read; read once as it ends.
    Fire("PLAYER_REGEN_DISABLED")
    lockdown = true
    PlayerAuras[16870] = nil
    reads = AuraReads
    game, addon = Measure(Burst)
    Note("UNIT_AURA x5 and a second in a fight", game)
    Equal(game.all .. " " .. (AuraReads - reads) .. " " .. Counts(addon, "OnEvent", "Missing", "Check"), "0 0 0 0 0",
        "in a fight: not heard, nothing asked or run")
    lockdown = false
    reads = AuraReads
    game = Measure(function() Fire("PLAYER_REGEN_ENABLED") end)
    Equal((AuraReads - reads) .. " " .. Counts(game, "SetAuraSlotEnabled"), ids .. " 1", "as it ends: read once, Clearcasting's slot back on")
    Equal(#printed, 0, "no errors")
end

-- The Cooldown pulse after a bag change: only the items looked at again ----------------------------

do
    local ns = Start({ notesSeen = "dev", useBars = true, pulse = true, pulseItems = true })
    local P, B = ns.Pulse, ns.Bars
    itemCount[118] = 2
    B:Assign("family:healing", "cd")
    ns.SetPulsePick("family:healing", true)
    P:Apply()
    NextFrame(ns)
    local count, watchers = P:Watchers()
    Equal(count .. " " .. tostring(watchers["family:healing"] and watchers["family:healing"].itemID), "1 118",
        "Healing Potions watched, by the Minor one you carry")
    local game, addon = Measure(function()
        Fire("BAG_UPDATE_DELAYED")
        NextFrame(ns)
    end)
    io.write("The Cooldown pulse (on, a potion ticked):\n")
    Note("a bag change (looting, a potion)", game)
    Equal(Counts(addon, "Watched", "Spells", "Items", "Restock", "Feed"), "0 0 0 1 1",
        "a bag change: the items looked at again and every watcher fed; your spells and items not listed again")
    -- Your last Minor drunk, a Lesser carried: the family moves on, the pulse with it.
    itemCount[118], itemCount[858] = 0, 1
    Fire("BAG_UPDATE_DELAYED")
    NextFrame(ns)
    Equal(tostring(watchers["family:healing"].itemID), "858", "the family moves on to the potion you carry, and its pulse with it")
    -- On no bar (or with your bars off) nothing there moves it on: the pulse
    -- does, its icon too, still only looking at the items again. As in
    -- Forever Enhanced Cooldown Pulse.
    do
        B:Assign("family:healing", nil)
        Fire("BAG_UPDATE_DELAYED")
        NextFrame(ns)
        local icon = C_Item.GetItemIconByID
        C_Item.GetItemIconByID = function(id) if id == 118 then return 135929 end return icon(id) end
        itemCount[118], itemCount[858] = 1, 0
        game, addon = Measure(function()
            Fire("BAG_UPDATE_DELAYED")
            NextFrame(ns)
        end)
        local potion = watchers["family:healing"]
        Equal(potion.itemID .. " " .. potion.icon .. " | " .. Counts(addon, "Watched", "Restock"), "118 135929 | 0 1",
            "on no bar, the Lesser drunk and a Minor carried: the pulse moves the family on, icon and all, without working it out again")
        C_Item.GetItemIconByID = icon
    end
    -- A spell learned: worked out again.
    game, addon = Measure(function()
        Fire("SPELLS_CHANGED")
        NextFrame(ns)
    end)
    Equal(Counts(addon, "Watched"), "1", "your spellbook changed: what's watched is worked out again")
    -- With /ccm open your bags are read again for its list: worked out again.
    SlashCmdList.FECM("")
    game, addon = Measure(function()
        Fire("BAG_UPDATE_DELAYED")
        NextFrame(ns)
    end)
    Equal(Counts(addon, "Watched"), "1", "with /ccm open, a bag change reads your bags again: what's watched is worked out again")
    FECMFrame:Hide()
    -- A ticked bag item run out of, and the list marked to be read again only
    -- after the pulse heard the bag change (/ccm's bag listing hearing it
    -- second): still worked out again from the new read, so it's let go.
    bagItems[1] = { itemID = 6948, hyperlink = "|cffffffff|Hitem:6948::|h[Hearthstone]|h|r", iconFileID = 134414 }
    itemCount[6948] = 1
    local bagSpell = C_Item.GetItemSpell
    C_Item.GetItemSpell = function(id) if id == 6948 then return "Hearthstone", 8690 end return bagSpell(id) end
    ns.Spells:Stale()
    ns.SetPulsePick("item:6948", true)
    P:Apply()
    NextFrame(ns)
    Equal(tostring(watchers["item:6948"] ~= nil), "true", "a Hearthstone in your bags, ticked: watched")
    bagItems[1], itemCount[6948] = nil, 0
    Fire("BAG_UPDATE_DELAYED")
    ns.Spells:Stale()
    NextFrame(ns)
    Equal(tostring(watchers["item:6948"]), "nil", "run out of, the list waiting to be read again: let go, as a full rebuild does")
    ns.SetPulsePick("item:6948", false)
    C_Item.GetItemSpell = bagSpell
    P:Apply()
    -- Off: nothing watched, nothing to feed.
    ns.Set("pulse", false)
    P:Apply()
    game, addon = Measure(function()
        Fire("BAG_UPDATE_DELAYED")
        NextFrame(ns)
    end)
    Equal((P:Watchers()) .. " " .. Counts(addon, "Watched", "Spells", "Items"), "0 0 0 0", "the pulse off: nothing watched, nothing listed")
    Equal(#printed, 0, "no errors")
end

-- The ? help's pulse: the same work each frame, nothing made anew ---------------------------------

do
    local ns = Start({ notesSeen = "dev" })
    SlashCmdList.FECM("")
    local w = FECMFrame
    local driver = w.helpNudge.driver
    local run = S[driver].scripts.OnUpdate
    Equal(tostring(run ~= nil) .. " " .. tostring(driver:IsVisible()), "true true", "the ? pulses until it's first clicked")
    local function Run(frames)
        for _ = 1, frames do run(driver, .1) end
    end
    local game, _, ten = Measure(function() Run(10) end)
    local _, _, thirty = Measure(function() Run(30) end)
    io.write("The ? help's pulse (/ccm open):\n")
    Note("10 frames", game)
    Equal(thirty - ten, 0, "30 frames run no more different functions than 10: nothing made anew each frame (was one a frame)")
    -- 4 seconds in: its edge a share of the way to the accent, every channel.
    local share = .8 * (1 - math.cos(4 % 2.4 / 2.4 * 2 * math.pi)) / 2
    local accent, from = ns.Theme:Accent(), ns.Theme.CONTROL_BORDER
    local want, got = {}, {}
    for i = 1, 3 do
        want[i] = ("%.3f"):format(from[i] + (accent[i] - from[i]) * share)
        got[i] = ("%.3f"):format(S[w.help].border[i])
    end
    Equal(table.concat(got, " "), table.concat(want, " "), "its edge between the plain edge and the accent, all three colours")
    ns.Set("accent", "teal")
    ns.Theme:Repaint()
    Run(1)
    local teal = ns.Theme:Accent()
    share = .8 * (1 - math.cos(4.1 % 2.4 / 2.4 * 2 * math.pi)) / 2
    Equal(("%.3f"):format(S[w.help].border[3]), ("%.3f"):format(from[3] + (teal[3] - from[3]) * share), "a new accent: followed at once")
    w:Hide()
    Equal(#printed, 0, "no errors")
end

-- Show the trap I last laid: your casts heard only while it's ticked ---------------------------------
-- (Squirt, 15 Nov 2026.) With no trap icon ticked your casts aren't heard
-- at all. Ticked, a cast of anything but a trap only asks whether its spell
-- ID is secret, and sets nothing; so does a secret ID or the trap laid last
-- again. A new trap laid sets the ticked icon's picture and name once each,
-- at once, and nothing else.

do
    local ns = Start({ notesSeen = "dev", useBars = true })
    local B = ns.Bars
    table.insert(book[1].items, { name = "Freezing Trap", subName = "Rank 1", spellID = 1499, iconID = 135834 })
    table.insert(book[1].items, { name = "Frost Trap", subName = "Rank 1", spellID = 13809, iconID = 135840 })
    ns.Spells:Stale()
    for _, name in ipairs({ "Moonfire", "Freezing Trap", "Frost Trap" }) do B:Assign(name, "cd") end
    NextFrame(ns)
    local function Lay(id) Fire("UNIT_SPELLCAST_SUCCEEDED", "player", "Cast-3-0-0-0-0-0", id) end
    io.write("Show the trap I last laid (Moonfire and two traps on Cooldowns, one ticked):\n")
    Equal(tostring(S[B.driver].events.UNIT_SPELLCAST_SUCCEEDED), "nil", "none ticked: your casts not heard")
    B:SetLastTrap("cd", "Freezing Trap", true)
    NextFrame(ns)
    local trap = B:Get("cd").icons[2]
    local game = Measure(function()
        Lay(5176)
        NextFrame(ns)
    end)
    Note("a cast of Wrath, and the next frame", game)
    Equal(tostring(S[B.driver].events.UNIT_SPELLCAST_SUCCEEDED) .. " " .. Counts(game, "issecretvalue") .. " " .. game.all, "true 1 1",
        "ticked: casts heard; one that isn't a trap only asks whether its ID is secret, and sets nothing")
    game = Measure(function() Lay(SECRET) end)
    Equal(Counts(game, "issecretvalue") .. " " .. game.all, "1 1", "a secret spell ID: asked, nothing else")
    game = Measure(function() Lay(13809) end)
    Note("Frost Trap laid", game)
    Equal(Counts(game, "SetTexture", "SetText") .. " " .. game.all .. " " .. S[trap.texture].texture .. " " .. S[trap.label].text,
        "1 1 3 135840 Frost Trap", "a new trap laid: the ticked icon's picture and name set once each, nothing else")
    game = Measure(function() Lay(13809) end)
    Equal(game.all, 1, "the same trap laid again: nothing set")
    Equal(#printed, 0, "no errors")
end

-- Count ticks on a cooldown icon: nothing per frame, nothing heard -----------------------------------
-- (Squirt, 14 Nov 2026.) The game draws the count in a slot of the bar's
-- own debuff container, so ticked or not, frames going by ask the game
-- nothing more, in a fight or out, and no event is heard for it. With none
-- ticked no count slot is made. In a fight a relayout only moves the
-- count's anchor (the addon's own frame), never the game's icon.

do
    local ns = Start({ notesSeen = "dev", useBars = true })
    local B = ns.Bars
    B:Assign("Moonfire", "cd")
    B:Assign("Wrath", "cd")
    B:SetOption("cd", "showAuras", true)
    NextFrame(ns)
    local cd = B:Get("cd")
    local function Events()
        local list = {}
        for event in pairs(S[B.driver].events) do list[#list + 1] = event end
        table.sort(list)
        return table.concat(list, ",")
    end
    local function Relayout()
        lockdown = true
        local game = Measure(function() ns.IconAuras:Layout(cd, ns.BarData("cd")) end)
        lockdown = false
        return game
    end
    io.write("Count ticks (Moonfire and Wrath on Cooldowns, buff and debuff times shown):\n")
    local heard, idle, fight = Events(), Measure(function() Frames(ns, 10, .1) end), Relayout()
    Note("ten frames, none counting", idle)
    Equal(tostring(cd.tickSlots), "nil", "none ticked: no count slot made")
    B:SetCountTicks("cd", "Moonfire", true)
    NextFrame(ns)
    local counting = Measure(function() Frames(ns, 10, .1) end)
    Note("ten frames, Moonfire counting", counting)
    lockdown = true
    Fire("PLAYER_REGEN_DISABLED")
    local inFight = Measure(function() Frames(ns, 10, .1) end)
    lockdown = false
    Fire("PLAYER_REGEN_ENABLED")
    local moved = Relayout()
    Note("a relayout in a fight, Moonfire counting", moved)
    local asked = { "InCombatLockdown", "IsShown", "ClearAllPoints", "SetAllPoints", "SetFontObject", "SetTextColor", "SetShown" }
    Equal(table.concat({ tostring(#cd.tickSlots), tostring(Events() == heard), tostring(counting.all == idle.all),
        tostring(inFight.all <= idle.all), tostring(moved.all - fight.all), Counts(moved, table.unpack(asked)) .. " / "
        .. Counts(fight, table.unpack(asked)) }, " "), "1 true true true 4 5 3 3 3 0 0 0 / 4 2 2 2 0 0 0",
        "one count slot; nothing more heard; frames ask nothing more, in a fight or out; a relayout in a fight asks only one"
        .. " more of each: whether it's one, Moonfire's icon shown, the count's anchor moved there; the game's icon never touched")
    Equal(#printed, 0, "no errors")
end

Equal(SecretMisuse[1], nil, "no secret misused anywhere")
print = _G.print
io.write("Hot path checks passed: " .. checks .. " assertions.\n")
