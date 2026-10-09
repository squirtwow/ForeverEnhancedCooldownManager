-- Run the actual addon files against a mock game for role profiles (Core.lua's
-- Roles and Talents, the profile menu's Tank, Healer and Damage, and Switch
-- with my talents): the first click on a role saves your lists as its
-- profile and switches to it, later clicks switch, right-click saves your
-- lists over it after asking, the role you're on is lit, nothing changes in a
-- fight, and a role's link follows its profile renamed and goes with it
-- deleted. Talents: a respec that changes your main tree switches to its
-- role's profile (after the fight), a tie, no points or the same main tree
-- do nothing, a role with no profile only says so, a tree set to None (a
-- druid's Feral Combat at first) never switches, and the tree roles are
-- yours to set. Share strings never carry role links. The mock game is a
-- copy of Tools/TestBars.lua's: Tools/TestMockSync.mjs checks the two match,
-- and with --write copies it across.
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
    local LOOKS = { ["Skin.lua GetBaseSpellID"] = true, ["Skin.lua GetEquipSlot"] = true }
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
function Proto:RegisterEvent(e) S[self].events[e] = true end
function Proto:RegisterUnitEvent(e) S[self].events[e] = true end
function Proto:GetAlpha() return S[self].alpha end
function Proto:UnregisterAllEvents() S[self].events = {} end
function Proto:CreateTexture() return New("Texture", self) end
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
function Proto:SetSize(w, h) S[self].width, S[self].height = w, h end
function Proto:GetSize() return S[self].width, S[self].height end
function Proto:SetWidth(w) S[self].width = w end
function Proto:SetHeight(h) S[self].height = h end
function Proto:GetWidth() return S[self].width end
function Proto:GetHeight() return S[self].height end
function Proto:GetName() return S[self].name end
function Proto:GetVerticalScroll() return S[self].scroll or 0 end
function Proto:SetVerticalScroll(v) S[self].scroll = v end
function Proto:GetEffectiveScale() return 1 end
function Proto:SetBackdropBorderColor(r, g, b, a) S[self].border = { r, g, b, a } end
function Proto:SetTextColor(r, g, b) S[self].colour = { r, g, b } end
function Proto:SetShadowColor(r, g, b, a) S[self].shadow = a end
function Proto:SetAlpha(a) S[self].alpha = a end
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
    -- Blizzard's aura container code run inside the addon's (below).
    ContainerRuns = {}
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
            local class = ({ [118] = { 0, 1 }, [117] = { 0, 5 }, [2698] = { 9, 0 }, [2512] = { 6, 2 }, [2516] = { 6, 3 } })[id]
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
    _G.Enum = { SpellBookSpellBank = { Player = 0 }, SpellBookItemType = { Spell = 1, FutureSpell = 2, Flyout = 3 } }
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
        GetSpellTexture = function() return 1 end,
        GetSpellName = function(id) return ({ [16870] = "Clearcasting", [16886] = "Nature's Grace", [1243] = "Power Word: Fortitude" })[id] end,
        GetSpellInfo = function() return nil end,
    }
    _G.UnitClass = function() return "Druid", "DRUID" end
    -- A Skyborne, so Walk on Air (in the spellbook) is your own racial.
    _G.UnitRace = function(unit) assert(unit == "player"); return "Skyborne", "Skyborne", 96 end
    _G.UnitPower = function() return 0 end
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
    _G.UnitAffectingCombat = function() return false end
    _G.InCombatLockdown = function() return lockdown end
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
                S[f].made = S[f].made + 1
                if S[f].updating then S[f].late = S[f].late + 1 end
                if options.initializeFrame then options.initializeFrame(button) end
                return button
            end
            rawset(f, "AddAuraSlot", function(_, key, filter, options)
                Guard()
                local button = Make(options)
                slots[key] = { filter = filter, button = button, enabled = true, supplied = S[button].supplied }
                return button
            end)
            rawset(f, "SetAuraSlotEnabled", function(_, key, enabled)
                Guard(); assert(type(enabled) == "boolean"); slots[key].enabled = enabled
            end)
            rawset(f, "SetAuraSlotCandidateFilters", function(_, key, filters)
                Guard(); slots[key].filters = filters
            end)
            -- Like the game: its unit set, it signs up for that unit's aura
            -- events, but only while it can be seen (UpdateEventRegistrations
            -- asks IsVisible); its own OnShow and OnHide below sign it up
            -- again or off. listening: whether it hears its auras change.
            rawset(f, "SetUnit", function(_, unit)
                if S[f].unit ~= unit then S[f].listening = f:IsVisible() end
                S[f].unit = unit
            end)
            rawset(f, "UpdateAllAuras", function() S[f].refreshes = (S[f].refreshes or 0) + 1 end)
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
            end)
            rawset(f, "GetAuraGroupFrameCount", function(_, key) return groups[key] and #groups[key].frames or 0 end)
            rawset(f, "GetAuraGroupFrame", function(_, key, i) return groups[key] and groups[key].frames[i] end)
            rawset(f, "SetAuraGroupMaxFrameCount", function(_, key, count)
                Guard()
                assert(type(count) == "number" and count >= 0 and count == math.floor(count), "a whole number of icons")
                groups[key].max = count
            end)
            rawset(f, "SetAuraGroupEnabled", function(_, key, enabled)
                Guard(); assert(type(enabled) == "boolean"); groups[key].enabled = enabled
            end)
            rawset(f, "SetAuraGroupCandidateFilters", function(_, key, filters) Guard(); groups[key].filters = filters end)
            rawset(f, "SetAuraGroupLayout", function(_, key, layout) Guard(); groups[key].layout = layout end)
            rawset(f, "SetScale", function(_, scale) Guard(); S[f].scale = scale end)
            -- The container's own update, from its OnUpdate after UNIT_AURA or
            -- a refresh: each switched-on group takes the auras it matches, up
            -- to its most, with icons from its pool, making a batch more when
            -- the pool runs dry (Blizzard_AuraContainerGroups.lua
            -- RefreshAuraGroup). Auras are { id =, harmful =, mine = }. Any
            -- call into the addon's own files while it runs is counted.
            local function Matches(group, aura)
                if (group.filter == "HARMFUL") ~= (aura.harmful == true) then return false end
                local filters = group.filters or {}
                if filters.includeSpellIDs and not filters.includeSpellIDs[aura.id] then return false end
                if filters.isFromPlayerOrPlayerPet ~= nil and filters.isFromPlayerOrPlayerPet ~= (aura.mine == true) then return false end
                return true
            end
            S[f].Update = function(auras)
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
                    end
                end)
                debug.sethook()
                S[f].updating = false
                assert(ok, err)
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

local function Load(saved, beforeLogin)
    local ns = {}
    _G.ForeverEnhancedCooldownManagerDB = saved
    for _, file in ipairs({ "Core.lua", "Style.lua", "Skin.lua", "Resource.lua", "CastBar.lua", "Ranks.lua", "Spells.lua", "Keybinds.lua", "Buffs.lua", "IconAuras.lua", "Bars.lua",
        "Layout.lua", "Theme.lua", "BarPage.lua", "LayoutPage.lua", "CastBarPage.lua", "ProfileMenu.lua", "Window.lua", "Tour.lua",
        "MinimapButton.lua", "Notes.lua", "Debug.lua" }) do
        assert(loadfile(file))("ForeverEnhancedCooldownManager", ns)
    end
    Fire("ADDON_LOADED", "ForeverEnhancedCooldownManager")
    if not beforeLogin then
        Fire("PLAYER_LOGIN")
        Fire("PLAYER_ENTERING_WORLD")
    end
    return ns
end

-- Roles: the game around it ----------------------------------------------------------------------
-- Stand-ins for what the window's other pages need, as in Tools/TestShare.lua,
-- so every file the addon ships loads.

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
local FILES = { "Core.lua", "Style.lua", "Skin.lua", "Resource.lua", "CastBar.lua", "RaidTimers.lua", "Ranks.lua", "Spells.lua",
    "Keybinds.lua", "Buffs.lua", "IconAuras.lua", "Bars.lua", "Pulse.lua", "Layout.lua", "Theme.lua", "BarPage.lua",
    "LayoutPage.lua", "CastBarPage.lua", "RaidTimersPage.lua", "PulsePage.lua", "ProfileShare.lua", "ProfileMenu.lua",
    "Window.lua", "Tour.lua", "MinimapButton.lua", "Notes.lua", "Debug.lua" }

-- The tests' own helpers, in one table: this file's main chunk shares Lua's
-- 200 locals with the mock game.
local R = {}

-- Your class for the next login: its name as the game shows it, and its file name.
R.class = { "Druid", "DRUID" }

-- A fresh game for the character set in `character`, of R.class, logged in
-- with these saved settings.
function R.Start(saved)
    Environment()
    BlizzardFrames()
    local class = R.class
    _G.UnitClass = function() return class[1], class[2] end
    _G.FECMFrame, _G.FECMTour, _G.FECMNotes, _G.FECMDebugFrame = nil, nil, nil, nil
    local ns = {}
    _G.ForeverEnhancedCooldownManagerDB = saved
    for _, file in ipairs(FILES) do assert(loadfile(file))("ForeverEnhancedCooldownManager", ns) end
    Fire("ADDON_LOADED", "ForeverEnhancedCooldownManager")
    Fire("PLAYER_LOGIN")
    Fire("PLAYER_ENTERING_WORLD")
    return ns
end

-- Talents, as Forever gives them (C_Traits, read as the game's own talent
-- frame reads them): your class's one tree (501), its talent trees as that
-- tree's groups, each tree's points as what's spent in its group, and no
-- answer at all for a tree with none spent (seen in game: "Subtlety = ?").
-- Each spec group fights with its own config: 77 for the first, 78 for the
-- second. Kept across logins, as the game keeps them.
R.talents = { groups = {}, points = { [77] = {}, [78] = {} }, group = 1, asked = 0 }
function R.Config() return R.talents.group == 1 and 77 or 78 end
function R.Trees(groups)
    local talents = R.talents
    talents.groups, talents.points, talents.group = groups, { [77] = {}, [78] = {} }, 1
    _G.C_ClassTalents = { GetActiveConfigID = function() return R.Config() end }
    _G.C_SpecializationInfo = { GetActiveSpecGroup = function() return talents.group end,
        GetCombatConfigIDForSpecGroup = function(group) return group == 1 and 77 or 78 end }
    _G.C_Traits = {
        GetConfigInfo = function(config)
            talents.asked = talents.asked + 1
            assert(config == R.Config(), "the config you fight with")
            return { ID = config, type = 1, name = "", treeIDs = { 501 }, usesSharedActionBars = true }
        end,
        GetGroupDisplayInfoByTreeID = function(tree)
            assert(tree == 501, "your class's tree")
            local out = {}
            for i, group in ipairs(talents.groups) do
                out[i] = { groupID = group[1], treeID = 501, skillLineID = 0, orderIndex = i, displayName = group[2], icon = 1 }
            end
            return out
        end,
        GetGroupCurrencyInfo = function(config, ids)
            local out = {}
            for _, id in ipairs(ids) do
                local spent = talents.points[config][id] or 0
                if spent > 0 then
                    out[#out + 1] = { traitNodeGroupID = id, currencyInfos = { { traitCurrencyID = 1, quantity = 0, spent = spent } } }
                end
            end
            return out
        end,
    }
end
R.DRUID = { { 101, "Balance" }, { 102, "Feral Combat" }, { 103, "Restoration" } }
-- Points in each tree, by the tree's ID, for the spec group fighting now; a
-- respec tells the game's talent events.
function R.Points(points, quiet)
    R.talents.points[R.Config()] = points
    if not quiet then
        Fire("TRAIT_CONFIG_UPDATED", R.Config())
        Fire("PLAYER_TALENT_UPDATE")
    end
end

-- A profile's lists as text: its four bars, joins and the pulse's ticks.
function R.Lists(profile)
    if type(profile) ~= "table" then return tostring(profile) end
    local parts = {}
    for _, key in ipairs({ "cd", "util", "buff", "debuff" }) do parts[#parts + 1] = key .. "=" .. table.concat(profile[key] or {}, ",") end
    local joins = {}
    for key, set in pairs(profile.joins or {}) do
        for name in pairs(set) do joins[#joins + 1] = key .. ":" .. name end
    end
    table.sort(joins)
    local picks = {}
    for key, value in pairs(profile.pulsePick or {}) do picks[#picks + 1] = key .. "=" .. tostring(value) end
    for key, value in pairs(profile.pulseStyle or {}) do picks[#picks + 1] = key .. "=" .. tostring(value) end
    table.sort(picks)
    return table.concat(parts, " ") .. " joins=" .. table.concat(joins, ",") .. " pulse=" .. table.concat(picks, ",")
end

-- A profile's row in the open menu.
function R.Row(name)
    for _, f in ipairs(frames) do
        if f.profile == name and S[f].shown then return f end
    end
end

-- A role button's look: lit (edged and lettered in the accent), plain, or
-- greyed (no profile yet).
function R.Look(ns, button)
    local accent, muted, text = ns.Theme:Accent(), ns.Theme.MUTED, ns.Theme.TEXT
    local edge, letters = S[button].border, S[button.label].colour
    if edge[1] == accent[1] and edge[2] == accent[2] and letters[1] == accent[1] then return "lit" end
    if letters[1] == muted[1] and letters[2] == muted[2] then return "greyed" end
    if letters[1] == text[1] and letters[2] == text[2] then return "plain" end
    return "unknown"
end
function R.Looks(ns, w)
    local looks = {}
    for _, role in ipairs(ns.ROLE_KEYS) do looks[#looks + 1] = role .. " " .. R.Look(ns, w.roleButtons[role]) end
    return table.concat(looks, ", ")
end

-- A right-click, as the game sends it.
function R.RightClick(button) S[button].scripts.OnClick(button, "RightButton") end

-- Frames listening for an event.
function R.Listening(event)
    local count = 0
    for _, f in ipairs(frames) do
        if S[f].events[event] then count = count + 1 end
    end
    return count
end

-- Whether the frame hearing talent changes waits for a fight to end.
function R.Waiting()
    for _, f in ipairs(frames) do
        if S[f].events.TRAIT_CONFIG_UPDATED then return S[f].events.PLAYER_REGEN_ENABLED == true end
    end
    return false
end

-- The profile menu open (it opens and closes on its button), drawn afresh.
function R.Open(w)
    if S[w.profilePanel].shown then w:Refresh() else w.profileButton:Click() end
end

-- Spells straight onto the profile you're on.
function R.Put(ns, key, ...)
    for _, name in ipairs({ ... }) do table.insert(ns.ActiveList(key), name) end
end

-- Roles: the first click saves and switches, later clicks switch ----------------------------------

do
    character = { guid = "Player-1-0001", name = "Zriel", realm = "Zephras" }
    R.class = { "Druid", "DRUID" }
    _G.C_Traits, _G.C_ClassTalents, _G.C_SpecializationInfo = nil, nil, nil
    local ns = R.Start({ useBars = true, notesSeen = "dev", helpSeen = true })
    local db = ForeverEnhancedCooldownManagerDB
    local own = "Zriel (Druid) - Zephras"
    R.Put(ns, "cd", "Moonfire")
    R.Put(ns, "buff", "Thorns", "Mark of the Wild")
    ns.Joins("buff")["Mark of the Wild"] = true
    ns.SetPulsePick("Moonfire", true)
    ns.SetPulseStyle("Moonfire", "long")
    local before = R.Lists(db.profiles[own])
    Equal(before, "cd=Moonfire util= buff=Thorns,Mark of the Wild debuff= joins=buff:Mark of the Wild pulse=Moonfire=long,Moonfire=true",
        "your lists to start with")
    Equal(tostring(ns.Get("talentSwitch")) .. " " .. tostring(db.roles) .. " " .. tostring(ns.RoleProfile("healer")),
        "false nil nil", "no roles yet, Switch with my talents off")

    SlashCmdList.FECM("")
    local w = FECMFrame
    w.profileButton:Click()
    local buttons = w.roleButtons
    Equal(S[w.roleHeading].text .. " | " .. S[buttons.tank.label].text .. " " .. S[buttons.healer.label].text .. " "
        .. S[buttons.damage.label].text .. " | " .. tostring(S[buttons.tank].shown and S[w.talentTick].shown) .. " | "
        .. S[w.talentTick.text].text .. " " .. tostring(w.talentTick:GetChecked()), "ROLES | Tank Healer Damage | true | "
        .. "Switch with my talents false", "the menu has Roles: Tank, Healer, Damage, and Switch with my talents, unticked")
    Equal(R.Looks(ns, w), "tank greyed, healer greyed, damage greyed", "no role has a profile yet: all three greyed")
    Equal(tostring(Last(buttons.healer, "RegisterForClicks")) .. " " .. tostring(S[buttons.healer].last.RegisterForClicks[2]),
        "LeftButtonUp RightButtonUp", "they take a right-click too")

    -- The first click: your lists saved as the role's profile, switched to.
    local count = #ns.ProfileNames()
    buttons.healer:Click()
    Equal(ns.ProfileName() .. " | " .. (#ns.ProfileNames() - count) .. " | " .. S[w.note].text .. " | " .. tostring(S[w.profilePanel].shown),
        "Druid Healer | 1 | Saved your lists as Druid Healer, your Healer profile, and switched to it. | false",
        "the first click: your lists saved as Druid Healer (your class and the role), switched to, the menu closed")
    Equal(R.Lists(db.profiles["Druid Healer"]) .. " | " .. R.Lists(db.profiles[own]), before .. " | " .. before,
        "the new profile has your lists and pulse ticks; the one you were on stays as it was")
    Equal(tostring(db.roles.DRUID.healer) .. " " .. tostring(db.chars[character.guid]), "Druid Healer Druid Healer",
        "linked for your class, and your character is on it")
    -- A copy, nothing shared.
    R.Put(ns, "cd", "Wrath")
    ns.Joins("buff")["Mark of the Wild"] = nil
    db.profiles["Druid Healer"].pulsePick.Wrath = true
    Equal(R.Lists(db.profiles[own]), before, "a change on the role's profile (a spell, a join, a pulse tick) leaves the old one alone")
    db.profiles["Druid Healer"].cd[2], db.profiles["Druid Healer"].pulsePick.Wrath = nil, nil
    ns.Joins("buff")["Mark of the Wild"] = true
    -- The role you're on is lit; the others greyed until they have a profile.
    w.profileButton:Click()
    Equal(R.Looks(ns, w) .. " | " .. tostring(buttons.healer.lit), "tank greyed, healer lit, damage greyed | true",
        "the role you're on is lit in the accent")

    -- Later clicks only switch.
    R.Row(own):Click()
    Equal(ns.ProfileName(), own, "back on your own profile by hand")
    w.profileButton:Click()
    Equal(R.Looks(ns, w), "tank greyed, healer plain, damage greyed", "on no role's profile: none lit, Healer plain (it has one)")
    count = #ns.ProfileNames()
    buttons.healer:Click()
    Equal(ns.ProfileName() .. " | " .. (#ns.ProfileNames() - count) .. " | " .. S[w.note].text,
        "Druid Healer | 0 | Now using Druid Healer, your Healer profile.", "a later click switches, nothing made")
    w.profileButton:Click()
    buttons.healer:Click()
    Equal(ns.ProfileName() .. " | " .. S[w.note].text, "Druid Healer | You're already on Druid Healer, your Healer profile.",
        "clicking the role you're on says so")
    -- Damage: the first click copies the lists you're on now (Healer's).
    w.profileButton:Click()
    buttons.damage:Click()
    Equal(ns.ProfileName() .. " | " .. R.Lists(db.profiles["Druid Damage"]), "Druid Damage | " .. before,
        "Damage's first click saves the lists you're on (Healer's) as Druid Damage")
    w.profileButton:Click()
    Equal(R.Looks(ns, w), "tank greyed, healer plain, damage lit", "Damage lit now, Healer plain")

    -- Each says what it does, and that it needs testing.
    local notes = {}
    for _, role in ipairs(ns.ROLE_KEYS) do notes[#notes + 1] = buttons[role].hint(buttons[role]) end
    Equal(table.concat(notes, " | "), "Save your lists as Druid Tank and switch to it. Right-click to save them without"
        .. " switching. (Needs testing) | Switch to Druid Healer, your Healer profile. Right-click to save your lists over it."
        .. " (Needs testing) | You're on Druid Damage, your Damage profile. (Needs testing)",
        "each role's note in the footer: what a click and a right-click do (naming the profile a first click makes), marked Needs testing")
    S[buttons.tank].scripts.OnEnter(buttons.tank)
    Equal(S[w.note].text:find("Save your lists as Druid Tank", 1, true) ~= nil, true, "shown in the footer on hover")
    S[buttons.tank].scripts.OnLeave(buttons.tank)
    w:Hide()
    Equal(#printed, 0, "nothing in chat")
end

-- Right-click: your lists over a role's profile, after asking ----------------------------------------

do
    character = { guid = "Player-1-0001", name = "Zriel", realm = "Zephras" }
    R.class = { "Druid", "DRUID" }
    local ns = R.Start({ useBars = true, notesSeen = "dev", helpSeen = true })
    local db = ForeverEnhancedCooldownManagerDB
    local own = "Zriel (Druid) - Zephras"
    R.Put(ns, "cd", "Moonfire")
    SlashCmdList.FECM("")
    local w = FECMFrame
    local buttons, confirm = w.roleButtons, w.confirm
    -- No profile yet: made from your lists at once, no question, and you stay where you are.
    R.Open(w)
    R.RightClick(buttons.tank)
    Equal(tostring(S[confirm.shade].shown) .. " | " .. ns.ProfileName() .. " | " .. R.Lists(db.profiles["Druid Tank"]) .. " | "
        .. S[w.note].text .. " | " .. tostring(S[w.profilePanel].shown),
        "false | " .. own .. " | cd=Moonfire util= buff= debuff= joins= pulse= | Saved your lists as Druid Tank, your Tank profile. | true",
        "right-click on a role with no profile: your lists saved as it, nothing asked, you stay on yours, the menu stays")
    Equal(R.Looks(ns, w), "tank plain, healer greyed, damage greyed", "Tank has a profile now, not lit (you're not on it)")
    -- One with a profile: asked first, naming it; Cancel changes nothing.
    R.Put(ns, "cd", "Wrath")
    R.RightClick(buttons.tank)
    Equal(tostring(S[confirm.shade].shown) .. " | " .. S[confirm.dialog.title].text .. " | " .. S[confirm.dialog.detail].text .. " | "
        .. S[confirm.yes.label].text, 'true | Save your lists over "Druid Tank"? | Your Tank profile gets the spell lists and pulse'
        .. " ticks of the profile you're on, in place of its own. This can't be undone. | Save", "right-click on one with a profile asks first")
    confirm.no:Click()
    Equal(R.Lists(db.profiles["Druid Tank"]), "cd=Moonfire util= buff= debuff= joins= pulse=", "Cancel: Tank as it was")
    R.RightClick(buttons.tank)
    confirm.yes:Click()
    Equal(R.Lists(db.profiles["Druid Tank"]) .. " | " .. ns.ProfileName() .. " | " .. S[w.note].text,
        "cd=Moonfire,Wrath util= buff= debuff= joins= pulse= | " .. own .. " | Saved your lists over Druid Tank, your Tank profile.",
        "Save: Tank gets your lists, you stay on yours, the footer says so")
    -- Only that role's profile: the others as they were.
    R.Row(own):Click()
    R.Open(w)
    buttons.healer:Click()
    Equal(ns.ProfileName(), "Druid Healer", "Healer made")
    R.Put(ns, "util", "Starfire")
    ns.SetPulsePick("Starfire", true)
    local healer, tank, mine = R.Lists(db.profiles["Druid Healer"]), R.Lists(db.profiles["Druid Tank"]), R.Lists(db.profiles[own])
    R.Open(w)
    R.RightClick(buttons.damage)
    Equal(tostring(S[confirm.shade].shown) .. " " .. tostring(db.roles.DRUID.damage) .. " " .. ns.ProfileName(),
        "false Druid Damage Druid Healer", "Damage made from Healer's lists, you still on Healer")
    db.profiles["Druid Damage"].cd = { "Hurricane" }
    R.RightClick(buttons.damage)
    Equal(S[confirm.shade].shown, true, "asked")
    confirm.yes:Click()
    Equal(R.Lists(db.profiles["Druid Damage"]) .. " | " .. tostring(R.Lists(db.profiles["Druid Tank"]) == tank) .. " "
        .. tostring(R.Lists(db.profiles[own]) == mine) .. " " .. tostring(R.Lists(db.profiles["Druid Healer"]) == healer),
        healer .. " | true true true", "Damage overwritten with the lists you're on; Tank, Healer and your own untouched")
    Equal(healer, "cd=Moonfire,Wrath util=Starfire buff= debuff= joins= pulse=Starfire=true", "(the lists you're on)")
    -- Not shared: a change after the save is the profile you're on alone.
    R.Put(ns, "cd", "Hurricane")
    ns.SetPulsePick("Wrath", true)
    Equal(R.Lists(db.profiles["Druid Damage"]), healer, "a copy: changing yours later leaves Damage alone")
    -- The role you're on: nothing to save over.
    R.Open(w)
    R.RightClick(buttons.healer)
    Equal(tostring(S[confirm.shade].shown) .. " | " .. S[w.note].text, "false | You're on Druid Healer: it saves as you go.",
        "right-click on the role you're on: nothing asked, it says it saves as you go")
    -- Another character on it: the question says so.
    db.chars["Player-1-0009"] = "Druid Tank"
    R.RightClick(buttons.tank)
    Equal(S[confirm.dialog.detail].text, "Your Tank profile gets the spell lists and pulse ticks of the profile you're on, in place of"
        .. " its own. Another character uses it, and gets them too. This can't be undone.", "another character on it: said")
    confirm.no:Click()
    db.chars["Player-1-0010"] = "Druid Tank"
    R.RightClick(buttons.tank)
    Equal(S[confirm.dialog.detail].text:find("2 other characters use it, and get them too.", 1, true) ~= nil, true, "two: said")
    confirm.no:Click()
    -- Spells added by ID only the old lists had are let go once no profile has them.
    ns.AddCustom("Old Trick", { 99001 })
    db.profiles["Druid Tank"].cd = { "Old Trick" }
    R.RightClick(buttons.tank)
    confirm.yes:Click()
    Equal(tostring(ns.CustomSpells()["Old Trick"]), "nil", "an added spell only the overwritten lists had is let go")
    w:Hide()
    Equal(#printed, 0, "nothing in chat")
end

-- In a fight: roles refused, nothing asked ----------------------------------------------------------------

do
    character = { guid = "Player-1-0001", name = "Zriel", realm = "Zephras" }
    R.class = { "Druid", "DRUID" }
    local ns = R.Start({ useBars = true, notesSeen = "dev", helpSeen = true })
    local db = ForeverEnhancedCooldownManagerDB
    local own = "Zriel (Druid) - Zephras"
    SlashCmdList.FECM("")
    local w = FECMFrame
    local buttons, confirm = w.roleButtons, w.confirm
    w.profileButton:Click()
    buttons.tank:Click()
    R.Row(own):Click()
    w.profileButton:Click()
    lockdown = true
    buttons.healer:Click()
    Equal(ns.ProfileName() .. " | " .. tostring(db.profiles["Druid Healer"]) .. " | " .. S[w.note].text, own
        .. " | nil | Profiles can't change in combat.", "a first click in a fight: nothing made, nothing switched, the footer says why")
    Equal(S[w.profilePanel].shown, true, "the menu stays open")
    buttons.tank:Click()
    Equal(ns.ProfileName() .. " | " .. S[w.note].text, own .. " | Profiles can't change in combat.", "a later click: not switched")
    R.Open(w)
    local tank = R.Lists(db.profiles["Druid Tank"])
    R.RightClick(buttons.tank)
    Equal(tostring(S[confirm.shade].shown) .. " | " .. tostring(R.Lists(db.profiles["Druid Tank"]) == tank) .. " | " .. S[w.note].text,
        "false | true | Profiles can't change in combat.", "a right-click: nothing asked or saved")
    R.RightClick(buttons.damage)
    Equal(tostring(db.profiles["Druid Damage"]) .. " " .. tostring(db.roles.DRUID.damage), "nil nil", "nor made")
    Equal(select(2, ns.UseRole("tank")) .. " | " .. select(2, ns.SaveRole("tank")), "Profiles can't change in combat. | "
        .. "Profiles can't change in combat.", "refused in Core too")
    -- Asked out of a fight, answered in one: refused then too.
    lockdown = false
    R.RightClick(buttons.tank)
    lockdown = true
    confirm.yes:Click()
    Equal(tostring(R.Lists(db.profiles["Druid Tank"]) == tank) .. " | " .. S[w.note].text, "true | Profiles can't change in combat.",
        "a question answered in a fight: refused")
    lockdown = false
    w:Hide()
    Equal(#printed, 0, "nothing in chat")
end

-- A role's profile renamed or deleted: the link follows it, or goes -----------------------------------

do
    character = { guid = "Player-1-0001", name = "Zriel", realm = "Zephras" }
    R.class = { "Druid", "DRUID" }
    local ns = R.Start({ useBars = true, notesSeen = "dev", helpSeen = true })
    local db = ForeverEnhancedCooldownManagerDB
    local own = "Zriel (Druid) - Zephras"
    SlashCmdList.FECM("")
    local w = FECMFrame
    local buttons = w.roleButtons
    ns.UseRole("healer")
    Equal(select(2, ns.RenameProfile("Resto")) .. " | " .. tostring(ns.RoleProfile("healer")) .. " | " .. db.roles.DRUID.healer,
        "Renamed to Resto. | Resto | Resto", "renamed: Healer's link follows it")
    w.profileButton:Click()
    Equal(R.Looks(ns, w), "tank greyed, healer lit, damage greyed", "still lit as Healer")
    buttons.healer:Click()
    Equal(S[w.note].text, "You're already on Resto, your Healer profile.", "and a click finds it")
    -- Deleted while you're on another: the link goes, Healer greys.
    ns.UseProfile(own)
    Equal(select(2, ns.DeleteProfile("Resto")) .. " | " .. tostring(db.roles.DRUID.healer) .. " | " .. tostring(ns.RoleProfile("healer")),
        "Deleted Resto. | nil | nil", "deleted: the link goes with it")
    w.profileButton:Click()
    Equal(R.Looks(ns, w), "tank greyed, healer greyed, damage greyed", "Healer greyed again")
    buttons.healer:Click()
    Equal(ns.ProfileName() .. " | " .. tostring(db.roles.DRUID.healer), "Druid Healer | Druid Healer", "clicked: a new Druid Healer")
    -- The role's profile you're on deleted: you move to a fresh one, the link goes.
    Equal(select(2, ns.DeleteProfile("Druid Healer")) .. " | " .. tostring(db.roles.DRUID.healer),
        "Deleted Druid Healer. You're now on " .. own .. " 2. | nil", "your own role profile deleted: link gone, you on a fresh one")
    -- Deleted from the menu, with its x.
    ns.UseRole("tank")
    ns.UseProfile(own)
    w.profileButton:Click()
    R.Row("Druid Tank").remove:Click()
    w.confirm.yes:Click()
    Equal(tostring(db.profiles["Druid Tank"]) .. " " .. tostring(db.roles.DRUID.tank), "nil nil", "deleted from the menu: link gone")
    -- A name already taken by a profile made by hand: the role's gets a number, the other is left alone.
    ns.NewProfile("Druid Tank")
    ns.UseProfile(own)
    R.Put(ns, "cd", "Moonfire")
    Equal(select(2, ns.UseRole("tank")) .. " | " .. #db.profiles["Druid Tank"].cd .. " " .. #db.profiles["Druid Tank 2"].cd,
        "Saved your lists as Druid Tank 2, your Tank profile, and switched to it. | 0 1",
        "a name taken: the role's profile numbered, the one made by hand untouched (and not linked)")
    w:Hide()

    -- Saved links repaired at load: to profiles that are gone, roles that aren't, two roles to one profile, junk.
    local saved = ForeverEnhancedCooldownManagerDB
    saved.roles = { DRUID = { tank = "Druid Tank 2", healer = "Gone", damage = "Druid Tank 2", ranged = own, none = own },
        WARRIOR = "junk", [5] = { tank = own } }
    saved.treeRoles = { DRUID = { [101] = "tank", [102] = "healz", [-3] = "tank", x = "tank", [104] = "none", [105] = "off",
        [106] = "None" }, PALADIN = 7 }
    saved.mainTrees = { [character.guid] = 103 }
    ns = R.Start(saved)
    Equal(tostring(saved.roles.DRUID.tank) .. " " .. tostring(saved.roles.DRUID.healer) .. " " .. tostring(saved.roles.DRUID.damage)
        .. " " .. tostring(saved.roles.DRUID.ranged) .. " " .. tostring(saved.roles.DRUID.none) .. " " .. tostring(saved.roles.WARRIOR)
        .. " " .. tostring(saved.roles[5]), "Druid Tank 2 nil nil nil nil nil nil",
        "a link to a profile that's gone, a second role on one profile, an unknown role (None is no role of its own) and junk: let go")
    Equal(tostring(saved.treeRoles.DRUID[101]) .. " " .. tostring(saved.treeRoles.DRUID[102]) .. " " .. tostring(saved.treeRoles.DRUID[-3])
        .. " " .. tostring(saved.treeRoles.DRUID.x) .. " " .. tostring(saved.treeRoles.DRUID[104]) .. " " .. tostring(saved.treeRoles.DRUID[105])
        .. " " .. tostring(saved.treeRoles.DRUID[106]) .. " " .. tostring(saved.treeRoles.PALADIN) .. " " .. tostring(saved.mainTrees),
        "tank nil nil nil none nil nil nil nil",
        "tree roles: only a tree's ID and a role or None kept; the main trees seen go while the tick is off")
    saved.roles = "junk"
    saved.treeRoles = 4
    ns = R.Start(saved)
    Equal(tostring(saved.roles) .. " " .. tostring(saved.treeRoles) .. " " .. tostring(ns.RoleProfile("tank")), "nil nil nil",
        "not tables at all: let go")
    Equal(#printed, 0, "nothing in chat")
end

-- Another class: its own roles; another of your class: the same ---------------------------------------

do
    character = { guid = "Player-1-0001", name = "Zriel", realm = "Zephras" }
    R.class = { "Druid", "DRUID" }
    local ns = R.Start({ useBars = true, notesSeen = "dev", helpSeen = true })
    R.Put(ns, "cd", "Moonfire")
    ns.UseRole("healer")
    local saved = ForeverEnhancedCooldownManagerDB
    -- A warrior: no Healer of its own, its first Tank click makes Warrior Tank.
    character = { guid = "Player-1-0002", name = "Grom", realm = "Zephras" }
    R.class = { "Warrior", "WARRIOR" }
    ns = R.Start(saved)
    Equal(ns.ProfileName() .. " | " .. tostring(ns.RoleProfile("healer")), "Grom (Warrior) - Zephras | nil",
        "a warrior: on its own profile, the druid's Healer isn't its own")
    SlashCmdList.FECM("")
    local w = FECMFrame
    w.profileButton:Click()
    Equal(R.Looks(ns, w), "tank greyed, healer greyed, damage greyed", "its roles all greyed")
    w.roleButtons.tank:Click()
    Equal(ns.ProfileName() .. " | " .. tostring(saved.roles.WARRIOR.tank) .. " | " .. tostring(saved.roles.DRUID.healer) .. " | "
        .. tostring(saved.roles.DRUID.tank), "Warrior Tank | Warrior Tank | Druid Healer | nil",
        "Warrior Tank made for warriors; the druid's links untouched")
    w:Hide()
    -- Another druid: the same Druid Healer, nothing new made.
    character = { guid = "Player-1-0003", name = "Tarn", realm = "Zephras" }
    R.class = { "Druid", "DRUID" }
    ns = R.Start(saved)
    local count = #ns.ProfileNames()
    Equal(select(2, ns.UseRole("healer")) .. " | " .. (#ns.ProfileNames() - count) .. " | " .. ns.ProfileUsers("Druid Healer"),
        "Now using Druid Healer, your Healer profile. | 0 | 2", "another druid finds the same Druid Healer, now used by both")
    -- A class the game hides (after login: the profile's own name reads it
    -- too): nothing linked, nothing made, no error.
    SlashCmdList.FECM("")
    FECMFrame:Hide()
    _G.UnitClass = function() return SECRETS.string, SECRETS.string end
    count = #ns.ProfileNames()
    Equal(select(2, ns.UseRole("tank")) .. " | " .. select(2, ns.SaveRole("tank")) .. " | " .. (#ns.ProfileNames() - count) .. " | "
        .. tostring(ns.RoleProfile("healer")) .. " " .. tostring(ns.RoleName("healer")), "Your class isn't known yet. | Your class isn't"
        .. " known yet. | 0 | nil nil", "a class the game hides: refused, nothing made, no role found")
    Equal(ns.TreeRole({ id = 103, name = "Restoration" }), "damage", "a tree's role: Damage, not knowing the class")
    R.class = { "Druid", "DRUID" }
    Equal(#printed, 0, "nothing in chat")
end

-- Share strings never carry role links ---------------------------------------------------------------

do
    character = { guid = "Player-1-0001", name = "Zriel", realm = "Zephras" }
    R.class = { "Druid", "DRUID" }
    local ns = R.Start({ useBars = true, notesSeen = "dev", helpSeen = true })
    local P = ns.ProfileShare
    R.Put(ns, "cd", "Moonfire")
    ns.SetPulsePick("Moonfire", true)
    local plain = P.Export()
    ns.UseRole("healer")
    ns.SetTalentSwitch(true)
    ns.SetTreeRole(103, "tank")
    ns.SetTreeRole(101, "none")
    local text = P.Export()
    local shared = P.Read(text)
    Equal(tostring(text == plain) .. " " .. shared.skipped .. " " .. tostring(shared.setup.look.talentSwitch) .. " "
        .. tostring(ForeverEnhancedCooldownManagerDB.treeRoles.DRUID[101]), "true 0 nil none",
        "a role's profile shares the very same string as the lists it came from: no link, no talent setting, no tree's role or None")
    -- Imported (here, by the same account): a new profile, linked to no role.
    local ok, message, name = ns.ImportProfile("From a friend", shared, true)
    Equal(tostring(ok) .. " " .. tostring(name) .. " | " .. tostring(ns.RoleProfile("healer")) .. " | " .. tostring(ns.Get("talentSwitch")),
        "true From a friend | Druid Healer | true", "an import is linked to no role, and leaves yours and the tick as they were")
    Equal(#printed, 0, "nothing in chat")
end

-- Talents: Switch with my talents --------------------------------------------------------------------

do
    character = { guid = "Player-1-0001", name = "Zriel", realm = "Zephras" }
    R.class = { "Druid", "DRUID" }
    R.Trees(R.DRUID)
    R.Points({ [103] = 31, [101] = 5 }, true)
    local ns = R.Start({ useBars = true, notesSeen = "dev", helpSeen = true })
    local db = ForeverEnhancedCooldownManagerDB
    local own = "Zriel (Druid) - Zephras"
    -- Off (the default): nothing listens, nothing is read.
    local asked = R.talents.asked
    Equal(R.Listening("TRAIT_CONFIG_UPDATED") .. " " .. R.Listening("PLAYER_TALENT_UPDATE") .. " " .. (R.talents.asked - asked),
        "0 0 0", "off: nothing listens for talent changes, and the talents aren't read")
    ns.UseRole("healer")
    ns.UseRole("damage")
    ns.UseProfile(own)
    R.Points({ [101] = 31 })
    Equal(ns.ProfileName() .. " " .. (R.talents.asked - asked), own .. " 0", "off: a respec changes nothing")

    -- Ticked in the menu: the trees, each with its points and role; your main tree noted, nothing switched.
    R.Points({ [103] = 31, [101] = 5 }, true)
    SlashCmdList.FECM("")
    local w = FECMFrame
    w.profileButton:Click()
    w.talentTick:Click()
    Equal(tostring(ns.Get("talentSwitch")) .. " | " .. ns.ProfileName() .. " | " .. tostring(db.mainTrees[character.guid]) .. " | "
        .. S[w.note].text, "true | " .. own .. " | 103 | Your profile now follows your main talent tree.",
        "ticked: on, your main tree (Restoration) noted, nothing switched, the footer says what it does")
    local function Trees()
        local out = {}
        for _, row in ipairs(w.treeRows) do
            if S[row.name].shown then
                out[#out + 1] = S[row.name].text:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "") .. " " .. tostring(row.choice.selected)
            end
        end
        return table.concat(out, ", ")
    end
    Equal(Trees(), "Balance 5 damage, Feral Combat 0 none, Restoration 31 healer",
        "each tree with its points and role: Balance Damage, Feral Combat None, Restoration Healer")
    Equal(R.Listening("TRAIT_CONFIG_UPDATED") .. " " .. R.Listening("PLAYER_TALENT_UPDATE") .. " " .. R.Listening("ACTIVE_TALENT_GROUP_CHANGED")
        .. " " .. R.Listening("TRAIT_CONFIG_LIST_UPDATED"), "1 1 1 1", "ticked: listening for talent changes")
    Equal(tostring(rawget(w.talentTick, "hint")), "When another talent tree takes the lead in points, switch to its role's profile,"
        .. " after any fight. (Needs testing)", "the tick's note, marked Needs testing")
    local choice = w.treeRows[3].choice.buttons[1]
    Equal(choice.hint(choice), "When Restoration takes the lead in points, switch to your Tank profile. (Needs testing)", "each choice's note")

    -- A respec that changes the main tree: switched to its role's profile.
    R.Points({ [101] = 31, [103] = 5 })
    Equal(ns.ProfileName() .. " | " .. tostring(db.mainTrees[character.guid]) .. " | " .. tostring(ns.talentNote),
        "Druid Damage | 101 | Your main talent tree is now Balance: switched to Druid Damage, your Damage profile.",
        "Balance now has the most points: switched to Damage's profile")
    Equal(S[w.note].text, ns.talentNote, "with the window open, the footer says so")
    R.Open(w)
    Equal(tostring(S[w.talentStatus].shown) .. " " .. S[w.talentStatus].text .. " | " .. R.Looks(ns, w), "true " .. ns.talentNote
        .. " | tank greyed, healer plain, damage lit", "and the menu, under the trees; Damage lit")
    -- A role picked by hand isn't undone by a respec that keeps the main tree.
    w.roleButtons.healer:Click()
    Equal(ns.ProfileName() .. " " .. tostring(ns.talentNote), "Druid Healer nil", "Healer picked by hand (the talents' note cleared)")
    R.Points({ [101] = 21, [103] = 10 })
    Equal(ns.ProfileName(), "Druid Healer", "a respec that keeps Balance on top: your pick stays")
    Fire("PLAYER_ENTERING_WORLD")
    Fire("TRAIT_CONFIG_LIST_UPDATED")
    Equal(ns.ProfileName(), "Druid Healer", "a loading screen or the talents loading again: your pick stays")
    -- A tie, or no points: nothing.
    R.Points({ [101] = 2, [102] = 15, [103] = 15 })
    Equal(ns.ProfileName() .. " " .. db.mainTrees[character.guid], "Druid Healer 101", "two trees level at the top: nothing, nothing noted")
    R.Points({})
    Equal(ns.ProfileName() .. " " .. db.mainTrees[character.guid], "Druid Healer 101", "no points at all (a wipe): nothing")
    ns.UseProfile(own)
    R.Points({ [103] = 1 })
    Equal(ns.ProfileName() .. " " .. db.mainTrees[character.guid], "Druid Healer 103", "the first point after the wipe, in Restoration: Healer")
    -- In a fight: held until it ends.
    ns.UseProfile(own)
    lockdown = true
    local before = R.talents.asked
    R.Points({ [101] = 31 })
    Equal(ns.ProfileName() .. " " .. db.mainTrees[character.guid] .. " " .. (R.talents.asked - before) .. " " .. tostring(R.Waiting()),
        own .. " 103 0 true", "in a fight: nothing switched or read, waiting for the fight to end")
    lockdown = false
    Fire("PLAYER_REGEN_ENABLED")
    Equal(ns.ProfileName() .. " " .. db.mainTrees[character.guid], "Druid Damage 101", "the fight over: switched")
    -- Another profile picked from the list: the talents' note goes (it named the one you left).
    R.Open(w)
    Equal(tostring(S[w.talentStatus].shown) .. " " .. tostring(ns.talentNote ~= nil), "true true", "(the switch said in the menu)")
    R.Row(own):Click()
    R.Open(w)
    Equal(ns.ProfileName() .. " | " .. tostring(ns.talentNote) .. " | " .. tostring(S[w.talentStatus].shown), own .. " | nil | false",
        "another profile picked from the list: the talents' note goes from the menu")
    Fire("PLAYER_REGEN_ENABLED")
    Equal(ns.ProfileName(), own, "another fight ending with nothing waiting: nothing")

    -- A tree's role set by you: kept, and used.
    R.Open(w)
    w.treeRows[2].choice.buttons[1]:Click()
    Equal(tostring(db.treeRoles.DRUID[102]) .. " " .. Trees(), "tank Balance 31 damage, Feral Combat 0 tank, Restoration 0 healer",
        "Feral Combat set to Tank: saved for druids, by the tree's ID")
    -- A role with no profile: nothing switched, said once in the footer and the menu, never in chat.
    w:Hide()
    R.Points({ [102] = 31 })
    Equal(ns.ProfileName() .. " | " .. db.mainTrees[character.guid] .. " | " .. tostring(ns.talentNote), own .. " | 102 | Your main talent"
        .. " tree is now Feral Combat, but Tank has no profile yet: click Tank to make one.",
        "Feral Combat on top, but Tank has no profile: nothing switched, the note kept for the menu")
    SlashCmdList.FECM("")
    Equal(S[w.note].text, ns.talentNote, "said with the window closed: in the footer as it next opens")
    w.profileButton:Click()
    Equal(tostring(S[w.talentStatus].shown) .. " " .. S[w.talentStatus].text, "true " .. ns.talentNote, "the menu says so when opened")
    w:Refresh()
    local footer = S[w.note].text
    R.Points({ [102] = 30 })
    Fire("PLAYER_TALENT_UPDATE")
    Equal(tostring(S[w.note].text == footer) .. " " .. tostring(S[w.note].text:find("no profile", 1, true)), "true nil",
        "more talent events, the same main tree: not said again")
    Equal(#printed, 0, "never in chat")
    -- Making Tank by hand clears it; Tank only switches on the next change of main tree.
    w.roleButtons.tank:Click()
    Equal(ns.ProfileName() .. " " .. tostring(ns.talentNote), "Druid Tank nil", "Tank made by hand: the note goes")

    -- Kept over a reload: the tick, the tree roles, your main tree. Logging in with the same main tree: your pick stays.
    ns.UseProfile("Druid Healer")
    local saved = ForeverEnhancedCooldownManagerDB
    w:Hide()
    ns = R.Start(saved)
    db = ForeverEnhancedCooldownManagerDB
    Equal(tostring(ns.Get("talentSwitch")) .. " " .. db.treeRoles.DRUID[102] .. " " .. db.mainTrees[character.guid] .. " " .. ns.ProfileName(),
        "true tank 102 Druid Healer", "after a reload: all kept, and the same main tree at login leaves your pick")
    -- Respecced while away (say, on another computer): the next login switches.
    R.Points({ [101] = 40 }, true)
    ns = R.Start(saved)
    Equal(ns.ProfileName() .. " " .. saved.mainTrees[character.guid], "Druid Damage 101", "a different main tree at login: switched")
    SlashCmdList.FECM("")
    Equal(S[FECMFrame.note].text, "Your main talent tree is now Balance: switched to Druid Damage, your Damage profile.",
        "switched before the window was first made: the footer says so as it first opens")
    FECMFrame.profileButton:Click()
    FECMFrame:Refresh()
    Equal(tostring(S[FECMFrame.note].text:find("talent", 1, true)) .. " " .. S[FECMFrame.talentStatus].text, "nil " .. ns.talentNote,
        "said once in the footer (the menu still shows it)")
    FECMFrame:Hide()
    -- A second spec group (dual spec): switching to it changes the config and the main tree.
    R.talents.group = 2
    R.Points({ [103] = 41 }, true)
    Fire("ACTIVE_TALENT_GROUP_CHANGED", 2, 1)
    Equal(ns.ProfileName(), "Druid Healer", "the other spec group, Restoration on top: Healer")

    -- Another character of your class: its first look only notes its main tree.
    character = { guid = "Player-1-0004", name = "Tarn", realm = "Zephras" }
    ns = R.Start(saved)
    Equal(ns.ProfileName() .. " " .. tostring(saved.mainTrees["Player-1-0004"]), "Tarn (Druid) - Zephras 103",
        "a character seen for the first time: its main tree noted, not switched")
    R.talents.group = 1
    character = { guid = "Player-1-0001", name = "Zriel", realm = "Zephras" }

    -- Unticked: nothing switches, and the main trees seen are let go (so a tick later starts afresh).
    ns = R.Start(saved)
    SlashCmdList.FECM("")
    w = FECMFrame
    w.profileButton:Click()
    w.talentTick:Click()
    Equal(tostring(ns.Get("talentSwitch")) .. " " .. tostring(saved.mainTrees) .. " | " .. S[w.note].text .. " | " .. Trees() .. " | "
        .. tostring(S[w.talentStatus].shown), "false nil | Your profile no longer follows your talents. |  | false",
        "unticked: off, the main trees forgotten, the trees and their roles out of the menu")
    local profile = ns.ProfileName()
    R.Points({ [103] = 41 })
    Equal(ns.ProfileName(), profile, "a respec while unticked: nothing")
    w.talentTick:Click()
    R.Points({ [103] = 40 })
    Equal(ns.ProfileName() .. " " .. saved.mainTrees[character.guid], profile .. " 103", "ticked again: noted afresh, not switched")
    w:Hide()
    Equal(#printed, 0, "nothing in chat")
end

-- Talents: no main tree yet (a new character, or talents not sent yet) -----------------------------------
-- With no points spent there's no main tree to note, so the first tree to
-- lead is only noted, never switched to.

do
    character = { guid = "Player-1-0005", name = "Sprout", realm = "Zephras" }
    R.class = { "Druid", "DRUID" }
    R.Trees(R.DRUID)
    R.Points({}, true)
    local ns = R.Start({ useBars = true, notesSeen = "dev", helpSeen = true, talentSwitch = true })
    local db = ForeverEnhancedCooldownManagerDB
    local own = "Sprout (Druid) - Zephras"
    ns.UseRole("healer")
    ns.UseRole("damage")
    ns.UseProfile(own)
    Equal(tostring(db.mainTrees and db.mainTrees[character.guid]), "nil", "a new character, no points spent: no main tree noted")
    -- Its first point (levelling): only noted.
    R.Points({ [102] = 1 })
    Equal(ns.ProfileName() .. " " .. tostring(db.mainTrees[character.guid]) .. " " .. tostring(ns.talentNote), own .. " 102 nil",
        "its first point, in Feral Combat: noted, not switched, nothing said")
    R.Points({ [102] = 5 })
    Equal(ns.ProfileName(), own, "more points in the same tree: nothing")
    -- Levelling on, another tree overtaking it switches once (as a respec would).
    R.Points({ [102] = 5, [103] = 6 })
    Equal(ns.ProfileName() .. " " .. db.mainTrees[character.guid], "Druid Healer 103",
        "levelling, Restoration overtakes Feral Combat: switched to Healer")
    -- A tree whose role has no profile leads, then the one you're on again: the old note goes.
    ns.SetTreeRole(102, "tank")
    R.Points({ [102] = 9, [103] = 6 })
    Equal(ns.ProfileName() .. " | " .. tostring(ns.talentNote ~= nil), "Druid Healer | true", "Feral Combat (Tank, no profile) leads: said")
    R.Points({ [102] = 9, [103] = 10 })
    Equal(ns.ProfileName() .. " | " .. tostring(ns.talentNote), "Druid Healer | nil",
        "Restoration leads again, its Healer profile the one you're on: nothing to switch, the old note goes")

    -- Talents not sent yet at the first look (every tree reads as none
    -- spent): when they come, only noted. A "none" noted by an earlier
    -- build is let go at load, so it can't switch either.
    character = { guid = "Player-1-0006", name = "Fern", realm = "Zephras" }
    local saved = ForeverEnhancedCooldownManagerDB
    saved.mainTrees[character.guid] = 0
    R.Points({ [103] = 31 }, true)
    local answer = C_Traits.GetGroupCurrencyInfo
    C_Traits.GetGroupCurrencyInfo = function() return {} end
    ns = R.Start(saved)
    Equal(ns.ProfileName() .. " | " .. tostring(saved.mainTrees[character.guid]), "Fern (Druid) - Zephras | nil",
        "logged in before the talents came: nothing noted (an old 0 let go)")
    C_Traits.GetGroupCurrencyInfo = answer
    Fire("TRAIT_CONFIG_LIST_UPDATED")
    Equal(ns.ProfileName() .. " | " .. tostring(saved.mainTrees[character.guid]) .. " | " .. tostring(ns.talentNote),
        "Fern (Druid) - Zephras | 103 | nil", "the talents come: Restoration noted, not switched, nothing said")
    R.Points({ [103] = 31 })
    Equal(ns.ProfileName(), "Fern (Druid) - Zephras", "and the same tree after: nothing")
    Equal(#printed, 0, "nothing in chat")
end

-- Talents: a tree set to None (don't switch) ------------------------------------------------------------
-- Tank and cat share Feral Combat, so a druid's Feral Combat starts on None:
-- when it takes the lead nothing switches and nothing is said (you click
-- Tank or Damage yourself), but it's noted as your main tree, so the next
-- tree to take the lead switches as any other. None is no role of its own.

do
    character = { guid = "Player-1-0007", name = "Bramble", realm = "Zephras" }
    R.class = { "Druid", "DRUID" }
    R.Trees(R.DRUID)
    R.Points({ [103] = 31 }, true)
    local ns = R.Start({ useBars = true, notesSeen = "dev", helpSeen = true, talentSwitch = true })
    local db = ForeverEnhancedCooldownManagerDB
    ns.UseRole("healer")
    ns.UseRole("damage")
    ns.UseProfile("Druid Healer")
    SlashCmdList.FECM("")
    local w = FECMFrame
    w.profileButton:Click()
    local function Trees()
        local out = {}
        for _, row in ipairs(w.treeRows) do
            if S[row.name].shown then
                out[#out + 1] = S[row.name].text:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "") .. " " .. tostring(row.choice.selected)
            end
        end
        return table.concat(out, ", ")
    end
    local labels = {}
    for _, choice in ipairs(w.treeRows[2].choice.buttons) do labels[#labels + 1] = S[choice.label].text .. "=" .. choice.key end
    Equal(table.concat(labels, " ") .. " | " .. Trees() .. " | " .. tostring(db.mainTrees[character.guid]),
        "Tank=tank Healer=healer Damage=damage None=none | Balance 0 damage, Feral Combat 0 none, Restoration 31 healer | 103",
        "each tree has four choices, None last; a druid's Feral Combat starts on None (Restoration noted at login)")
    local none = w.treeRows[2].choice.buttons[4]
    Equal(none.hint(none), "When Feral Combat takes the lead in points, don't switch: click a role yourself. (Needs testing)",
        "None's note says what it does, marked Needs testing")

    -- Balance takes the lead: switched to Damage and said, as before.
    R.Points({ [101] = 31 })
    Equal(ns.ProfileName() .. " | " .. tostring(S[w.talentStatus].shown) .. " " .. tostring(S[w.note].text == ns.talentNote),
        "Druid Damage | true true", "Balance leads: switched to Damage, said in the footer and the menu")
    -- Feral Combat (None) takes the lead, with Tank not made yet: nothing
    -- switched, no note to make Tank, the older note gone from the open
    -- menu and the footer; still noted as your main tree.
    R.Points({ [102] = 31 })
    Equal(ns.ProfileName() .. " | " .. tostring(db.mainTrees[character.guid]) .. " | " .. tostring(ns.talentNote) .. " | "
        .. tostring(S[w.talentStatus].shown) .. " " .. tostring(S[w.note].text:find("talent tree", 1, true)) .. " "
        .. tostring(ns.RoleProfile("tank")), "Druid Damage | 102 | nil | false nil nil",
        "Feral Combat (None) leads: nothing switched or said, the older note gone; noted as your main tree")
    Fire("PLAYER_TALENT_UPDATE")
    Fire("PLAYER_ENTERING_WORLD")
    Equal(ns.ProfileName() .. " " .. tostring(ns.talentNote), "Druid Damage nil", "more talent events and a loading screen: still nothing")
    -- Feral Combat set to Tank while it leads: nothing switched. When it
    -- takes the lead again with Tank not made, the menu says to click Tank.
    -- Another tree's role, or Tank clicked again, leaves that note; Feral
    -- Combat set back to None from the menu: it goes at once.
    w.treeRows[2].choice.buttons[1]:Click()
    Equal(ns.ProfileName() .. " " .. tostring(ns.talentNote), "Druid Damage nil", "Feral Combat (leading) set to Tank: nothing switched")
    R.Points({ [101] = 32 })
    R.Points({ [102] = 33 })
    local clickTank = "Your main talent tree is now Feral Combat, but Tank has no profile yet: click Tank to make one."
    Equal(ns.ProfileName() .. " | " .. tostring(S[w.talentStatus].shown) .. " " .. S[w.talentStatus].text, "Druid Damage | true " .. clickTank,
        "Balance leads, then Feral Combat (Tank, not made): the menu says to click Tank")
    w.treeRows[1].choice.buttons[1]:Click()
    w.treeRows[1].choice.buttons[3]:Click()
    w.treeRows[2].choice.buttons[1]:Click()
    Equal(tostring(ns.talentNote) .. " | " .. tostring(S[w.talentStatus].shown), clickTank .. " | true",
        "Balance set to Tank and back to Damage, and Feral Combat's Tank clicked again: no new role for the main tree, the note stays")
    w.treeRows[2].choice.buttons[4]:Click()
    Equal(ns.ProfileName() .. " | " .. tostring(db.treeRoles.DRUID[102]) .. " | " .. tostring(ns.talentNote) .. " | "
        .. tostring(S[w.talentStatus].shown) .. " " .. tostring(S[w.note].text:find("click Tank", 1, true)), "Druid Damage | none | nil | false nil",
        "Feral Combat set back to None from the menu: the note to click Tank goes at once, nothing switched")
    -- You pick Tank by hand; then Restoration takes the lead: switched to Healer, as from any tree.
    w.roleButtons.tank:Click()
    Equal(ns.ProfileName(), "Druid Tank", "(Tank made by hand)")
    R.Points({ [103] = 40 })
    Equal(ns.ProfileName() .. " " .. db.mainTrees[character.guid], "Druid Healer 103", "then Restoration leads: switched to Healer")
    -- Its Healer (its role by default, never set) clicked from the menu: no new role, so the note stays.
    R.Open(w)
    w.treeRows[3].choice.buttons[2]:Click()
    Equal(tostring(db.treeRoles.DRUID[103]) .. " | " .. tostring(ns.talentNote ~= nil) .. " " .. tostring(S[w.talentStatus].shown),
        "healer | true true", "Restoration's Healer (its default) clicked while it leads: the note saying you switched stays")
    R.Points({ [102] = 40 })
    Equal(ns.ProfileName() .. " " .. db.mainTrees[character.guid] .. " " .. tostring(ns.talentNote), "Druid Healer 102 nil",
        "Feral Combat leads again: you stay on Healer, nothing said")
    -- With the window closed: Balance switches (said for the next open), then Feral Combat takes the lead: the older note goes there too.
    w:Hide()
    R.Points({ [101] = 45 })
    Equal(ns.ProfileName() .. " " .. tostring(ns.talentNote ~= nil), "Druid Damage true", "(window closed, Balance leads: switched)")
    R.Points({ [102] = 46 })
    SlashCmdList.FECM("")
    Equal(ns.ProfileName() .. " | " .. tostring(ns.talentNote) .. " " .. tostring(S[w.note].text:find("talent tree", 1, true)),
        "Druid Damage | nil nil", "then Feral Combat (None) leads: nothing switched, and the window opens without the older note")
    ns.UseProfile("Druid Healer")
    R.Points({ [102] = 40 })
    -- Another message waiting for the window to open isn't the talents' to drop.
    w:Hide()
    R.Points({ [101] = 47 })
    w:Say("A message of its own, waiting for the window.")
    R.Points({ [102] = 48 })
    SlashCmdList.FECM("")
    Equal(ns.ProfileName() .. " | " .. tostring(ns.talentNote) .. " | " .. S[w.note].text,
        "Druid Damage | nil | A message of its own, waiting for the window.",
        "another message waiting: Feral Combat (None) leading drops only the talents' note, the window opens with the other")
    ns.UseProfile("Druid Healer")
    R.Points({ [102] = 40 })

    -- None set from the menu, Damage over the default: saved for druids by the tree's ID.
    R.Open(w)
    w.treeRows[3].choice.buttons[4]:Click()
    w.treeRows[2].choice.buttons[3]:Click()
    Equal(tostring(db.treeRoles.DRUID[103]) .. " " .. tostring(db.treeRoles.DRUID[102]) .. " | " .. Trees(),
        "none damage | Balance 0 damage, Feral Combat 40 damage, Restoration 0 none",
        "Restoration set to None and Feral Combat to Damage: saved for druids, by the tree's ID")
    w:Hide()
    -- Kept over a reload; Feral Combat (Damage now) switches, Restoration (None) doesn't.
    local saved = ForeverEnhancedCooldownManagerDB
    ns = R.Start(saved)
    Equal(tostring(saved.treeRoles.DRUID[103]) .. " " .. ns.ProfileName(), "none Druid Healer", "after a reload: None kept")
    R.Points({ [101] = 45 })
    ns.UseProfile("Druid Healer")
    R.Points({ [102] = 50 })
    Equal(ns.ProfileName(), "Druid Damage", "Balance leads, Healer picked by hand, then Feral Combat (now Damage) leads: switched to Damage")
    R.Points({ [103] = 51 })
    Equal(ns.ProfileName() .. " " .. saved.mainTrees[character.guid] .. " " .. tostring(ns.talentNote), "Druid Damage 103 nil",
        "Restoration (None) leads: nothing switched or said, noted as your main tree")
    -- Set by code too; anything else is never saved, and None makes no profile.
    ns.SetTreeRole(101, "none")
    ns.SetTreeRole(102, "off")
    local count = #ns.ProfileNames()
    Equal(tostring(saved.treeRoles.DRUID[101]) .. " " .. saved.treeRoles.DRUID[102] .. " | " .. select(2, ns.UseRole("none")) .. " "
        .. select(2, ns.SaveRole("none")) .. " " .. (#ns.ProfileNames() - count) .. " " .. tostring(saved.roles.DRUID.none),
        "none damage | There's no such role. There's no such role. 0 nil", "None set for a tree; an unknown choice never saved; no profile for None")
    Equal(#printed, 0, "nothing in chat")
end

-- Talents the game can't or won't say -------------------------------------------------------------------

do
    character = { guid = "Player-1-0001", name = "Zriel", realm = "Zephras" }
    R.class = { "Druid", "DRUID" }
    _G.C_Traits, _G.C_ClassTalents, _G.C_SpecializationInfo = nil, nil, nil
    local ns = R.Start({ useBars = true, notesSeen = "dev", helpSeen = true, talentSwitch = true })
    local db = ForeverEnhancedCooldownManagerDB
    SlashCmdList.FECM("")
    local w = FECMFrame
    w.profileButton:Click()
    Equal(tostring(ns.TalentTrees()) .. " " .. tostring(db.mainTrees) .. " | " .. tostring(S[w.talentStatus].shown) .. " "
        .. S[w.talentStatus].text, "nil nil | true Your talent trees can't be read yet.",
        "no talent API: no trees, nothing noted, and the menu says the trees can't be read")
    -- Secret answers: nothing read from them.
    R.Trees(R.DRUID)
    R.Points({ [103] = 31 }, true)
    local traits = C_Traits
    for _, swap in ipairs({
        { "GetActiveConfigID", function() return SECRETS.number end },
        { "GetConfigInfo", function() return SECRET end },
        { "GetGroupDisplayInfoByTreeID", function() return SECRET end },
        { "GetGroupDisplayInfoByTreeID", function() return { { groupID = SECRETS.number, displayName = SECRETS.string } } end },
        { "GetGroupCurrencyInfo", function() return { { traitNodeGroupID = 103, currencyInfos = { { spent = SECRETS.number } } } } end },
        { "GetConfigInfo", function() error("no such config") end },
    }) do
        local owner = swap[1] == "GetActiveConfigID" and C_ClassTalents or traits
        local original = owner[swap[1]]
        owner[swap[1]] = swap[2]
        local trees = ns.TalentTrees()
        local text = trees and (#trees .. " " .. trees[3].points) or "nil"
        owner[swap[1]] = original
        Equal(text, ({ GetActiveConfigID = "3 31", GetConfigInfo = "nil", GetGroupDisplayInfoByTreeID = "nil",
            GetGroupCurrencyInfo = "3 0" })[swap[1]], swap[1] .. " answering a secret or an error: nothing taken from it, no error")
    end
    -- A secret config from the first question: the spec group's config instead.
    Equal(#ns.TalentTrees(), 3, "and with every answer plain, three trees")
    Equal(#printed, 0, "no errors")
end

-- Each class's trees, and a tree the defaults don't know --------------------------------------------------

do
    character = { guid = "Player-1-0001", name = "Zriel", realm = "Zephras" }
    local roles = {}
    for _, case in ipairs({
        { "Warrior", "WARRIOR", { "Arms", "Fury", "Protection" } },
        { "Paladin", "PALADIN", { "Holy", "Protection", "Retribution" } },
        { "Priest", "PRIEST", { "Discipline", "Holy", "Shadow" } },
        { "Shaman", "SHAMAN", { "Elemental", "Enhancement", "Restoration" } },
        { "Druid", "DRUID", { "Balance", "Feral Combat", "Restoration" } },
        { "Hunter", "HUNTER", { "Beast Mastery", "Marksmanship", "Survival" } },
        { "Rogue", "ROGUE", { "Assassination", "Combat", "Subtlety" } },
        { "Mage", "MAGE", { "Arcane", "Fire", "Frost" } },
        { "Warlock", "WARLOCK", { "Affliction", "Demonology", "Destruction" } },
        { "Druid", "DRUID", { "Wildheart" } },
    }) do
        R.class = { case[1], case[2] }
        local groups = {}
        for i, name in ipairs(case[3]) do groups[i] = { 200 + i, name } end
        R.Trees(groups)
        local ns = R.Start({ notesSeen = "dev", helpSeen = true })
        local line = {}
        for _, tree in ipairs(ns.TalentTrees()) do line[#line + 1] = tree.name .. " " .. ns.TreeRole(tree) end
        roles[#roles + 1] = case[1] .. ": " .. table.concat(line, ", ")
    end
    Equal(table.concat(roles, " | "), "Warrior: Arms damage, Fury damage, Protection tank | Paladin: Holy healer, Protection tank,"
        .. " Retribution damage | Priest: Discipline healer, Holy healer, Shadow damage | Shaman: Elemental damage, Enhancement damage,"
        .. " Restoration healer | Druid: Balance damage, Feral Combat none, Restoration healer | Hunter: Beast Mastery damage,"
        .. " Marksmanship damage, Survival damage | Rogue: Assassination damage, Combat damage, Subtlety damage | Mage: Arcane damage,"
        .. " Fire damage, Frost damage | Warlock: Affliction damage, Demonology damage, Destruction damage | Druid: Wildheart damage",
        "each class's trees start on their usual role (a druid's Feral Combat, tank and cat, on None); Damage for any other")
    -- A warrior's Protection to Damage is the warrior's alone; a druid's trees as before.
    R.class = { "Warrior", "WARRIOR" }
    R.Trees({ { 301, "Arms" }, { 302, "Fury" }, { 303, "Protection" } })
    local ns = R.Start({ notesSeen = "dev", helpSeen = true })
    ns.SetTreeRole(303, "damage")
    ns.SetTreeRole(303, "ranged")
    ns.SetTreeRole("x", "tank")
    local saved = ForeverEnhancedCooldownManagerDB
    Equal(tostring(saved.treeRoles.WARRIOR[303]) .. " " .. tostring(saved.treeRoles.WARRIOR.x) .. " " .. tostring(saved.treeRoles.DRUID),
        "damage nil nil", "set for warriors only; an unknown role or tree is never saved")
    R.class = { "Druid", "DRUID" }
    Equal(#printed, 0, "no errors")
end

-- The menu: help, the tour, and room ----------------------------------------------------------------------

do
    character = { guid = "Player-1-0001", name = "Zriel", realm = "Zephras" }
    R.class = { "Druid", "DRUID" }
    R.Trees({ { 101, "Balance" }, { 102, "Feral Combat" }, { 103, "Restoration" } })
    R.Points({ [101] = 31 }, true)
    local profiles = {}
    for i = 1, 30 do profiles[("Profile %02d"):format(i)] = { cd = {}, util = {}, buff = {}, debuff = {}, joins = {} } end
    local ns = R.Start({ useBars = true, notesSeen = "dev", helpSeen = true, profiles = profiles })
    SlashCmdList.FECM("")
    local w = FECMFrame
    w.profileButton:Click()
    Equal(tostring(S[w.profilePanel].height <= 420), "true", "unticked, with a long list: the menu as short as before the roles came")
    -- The tallest it gets: ticked, three trees and a note. Under the title
    -- bar (the menu hangs 38 down from the window's top), it ends clear of
    -- the footer's line (539 down the 560-tall window): the list shows fewer.
    w.talentTick:Click()
    ns.talentNote = "Your main talent tree is now Feral Combat, but Tank has no profile yet: click Tank to make one."
    w:Refresh()
    local height = S[w.profilePanel].height
    Equal(tostring(38 + height <= 535) .. " " .. tostring(S[w.talentStatus].shown), "true true",
        "ticked, three trees and a note under them: clear of the footer (" .. height .. " tall)")
    -- Profiles the list shows at once: the name box sits under it (32 + 22 a row down).
    local function Rows()
        local at = S[w.profileInput].points[1]
        return math.floor((-at[3] - 32) / 22 + .5)
    end
    w.talentTick:Click()
    local unticked = Rows()
    w.talentTick:Click()
    ns.talentNote = "Your main talent tree is now Feral Combat, but Tank has no profile yet: click Tank to make one."
    w:Refresh()
    local ticked = Rows()
    -- 7 since Positions per profile took a row under Use on all characters.
    Equal(unticked .. " " .. tostring(ticked < unticked and ticked >= 4), "7 true",
        "the list shows 7 profiles unticked, a few fewer (" .. ticked .. ") with the trees and note, and still scrolls to the rest")
    -- Every new control in the menu says what it does, and that it needs testing.
    local missing = {}
    for _, role in ipairs(ns.ROLE_KEYS) do
        local hint = w.roleButtons[role].hint
        if type(hint) ~= "function" or not hint(w.roleButtons[role]):find("(Needs testing)", 1, true) then missing[#missing + 1] = role end
    end
    local tickHint = rawget(w.talentTick, "hint")
    if not (tickHint and tickHint:find("(Needs testing)", 1, true)) then missing[#missing + 1] = "tick" end
    for i, row in ipairs(w.treeRows) do
        for _, choice in ipairs(row.choice.buttons) do
            if type(choice.hint) ~= "function" or not choice.hint(choice):find("(Needs testing)", 1, true) then
                missing[#missing + 1] = "tree " .. i .. " " .. choice.key
            end
        end
    end
    Equal(table.concat(missing, ", "), "", "each role, the tick and each tree's choices have a note, marked Needs testing")
    -- Words fit: about 7.5 units a letter, 6.5 in the small font (as Tools/TestHelp.lua counts).
    local function Wide(text, small) return #text:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "") * (small and 6.5 or 7.5) end
    local fits = {}
    -- The tick at the right of the Roles heading, clear of it.
    fits[#fits + 1] = tostring(10 + #S[w.roleHeading].text * 7.5 + 8 <= 290 - (18 + Wide(S[w.talentTick.text].text)))
    -- Each tree's name and points clear of its four choices (the longest
    -- names, at 51 points, too), each choice's word in its own room, and
    -- the four end to end inside the choice's edge.
    local wide = S[w.treeRows[1].choice].width
    for _, row in ipairs(w.treeRows) do
        fits[#fits + 1] = tostring(18 + Wide(S[row.name].text, true) <= 300 - 10 - wide - 6)
        local x, words = 1, true
        for _, choice in ipairs(row.choice.buttons) do
            local at = S[choice].points[1]
            if at[1] ~= "LEFT" or math.abs(at[2] - x) > .01 or Wide(S[choice.label].text, true) + 4 > S[choice].width then words = false end
            x = x + S[choice].width
        end
        fits[#fits + 1] = tostring(words and #row.choice.buttons == 4 and math.abs(x - (wide - 1)) < .01)
    end
    fits[#fits + 1] = tostring(Wide("Beast Mastery 51", true) <= 300 - 10 - wide - 6 - 18
        and Wide("Assassination 51", true) <= 300 - 10 - wide - 6 - 18)
    fits[#fits + 1] = tostring(Wide("Healer", true) <= 90 - 8)
    Equal(table.concat(fits, " "), "true true true true true true true true true",
        "the tick clear of the Roles heading, each tree's name and points clear of its four choices, the choices' words in their room")
    local tickAt, headingAt = S[w.talentTick].points[1], S[w.roleHeading].points[1]
    Equal(tickAt[1] .. " " .. tickAt[2] .. " " .. (tickAt[3] - headingAt[3]), "TOPLEFT 10 -42",
        "the tick on its own row under the role buttons (the heading's row holds the Needs testing tag)")
    local tag = w.roleTesting
    Equal(tostring(tag ~= nil) .. " " .. S[tag].text .. " " .. tostring(S[tag].points[1][2] == w.roleHeading), "true Needs testing true",
        "Needs testing in plain sight beside the Roles heading")
    w:Hide()

    -- The ? over the open menu, and the tour's Profiles step, mention the roles.
    SlashCmdList.FECM("")
    w.profileButton:Click()
    w.help:Click()
    Equal(S[w.note].text .. " " .. #S[w.note].text, "Click a profile or role to use it, right-click a role to save. Share or Import"
        .. " as text. 87", "the ? over the menu: the roles too, still short (it was 90)")
    -- Without Share and Import (ProfileShare.lua is a new file: until a full restart), the line keeps typing a name.
    local share = w.profileShare
    w.profileShare = nil
    w.help:Click()
    Equal(S[w.note].text .. " " .. #S[w.note].text, "Click a profile or role to use it, right-click a role to save. Type a name to make"
        .. " one. 87", "without Share and Import: the roles, and typing a name")
    w.profileShare = share
    w.profileButton:Click()
    ns.Tour:Start()
    for _ = 1, 20 do
        if S[FECMTour.title].text == "PROFILES" then break end
        FECMTour.next:Click()
    end
    Equal(S[FECMTour.text].text, "Each character has its own spell lists. Use one on several characters, even across classes, or on all"
        .. " of them. Tank, Healer and Damage keep a profile for each role, and Switch with my talents can pick one for you. Share and"
        .. " Import trade profiles with other players as text.", "the tour's Profiles step mentions the roles and the talents")
    ns.Tour:Stop()
    w:Hide()
    -- No em dashes in anything new.
    local words = { S[w.talentTick.text].text, rawget(w.talentTick, "hint") }
    for _, role in ipairs(ns.ROLE_KEYS) do words[#words + 1] = w.roleButtons[role].hint(w.roleButtons[role]) end
    for _, choice in ipairs(w.treeRows[1].choice.buttons) do words[#words + 1] = S[choice.label].text .. " " .. choice.hint(choice) end
    Equal(table.concat(words, " "):find("\226\128\148", 1, true), nil, "no em dashes")
    Equal(#printed, 0, "no errors")
end

-- Positions per profile: each profile keeps its own bar spots and sizes ------------------------------

-- A bar's spot and size as text.
function R.Spot(ns, key)
    local d = ns.BarData(key)
    return ("%s %s %s %d"):format(tostring(d.point), tostring(d.x), tostring(d.y), d.size)
end

do
    character = { guid = "Player-1-0001", name = "Zriel", realm = "Zephras" }
    R.class = { "Druid", "DRUID" }
    _G.C_Traits, _G.C_ClassTalents, _G.C_SpecializationInfo = nil, nil, nil
    local ns = R.Start({ useBars = true, notesSeen = "dev", helpSeen = true })
    local db = ForeverEnhancedCooldownManagerDB
    local own = "Zriel (Druid) - Zephras"
    local function CD() return ns.BarData("cd") end
    -- Moves the Cooldowns bar (and sizes it) as dragging would, then redraws:
    -- the bar's spot as saved after (redraws keep it in the bar's own anchor).
    local function Move(x, size)
        local d = CD()
        d.point, d.x, d.y, d.size = d.point or "CENTER", x, d.y or -40, size or d.size
        ns.Bars:Rebuild()
        return R.Spot(ns, "cd")
    end
    local first = Move(100, 40)
    -- Off at first: switching never moves a bar, and no profile keeps spots.
    Equal(tostring(ns.PlacePerProfile()), "false", "off by default")
    ns.CopyProfile("Zriel Two")
    local shared = Move(222)
    ns.UseProfile(own)
    Equal(R.Spot(ns, "cd") .. " " .. tostring(db.profiles[own].place) .. " " .. tostring(db.profiles["Zriel Two"].place),
        shared .. " nil nil", "off: one set of spots for every profile")
    Equal(first ~= shared, true, "the bar did move")

    -- The tick in the menu, under Use on all characters, unticked.
    SlashCmdList.FECM("")
    local w = FECMFrame
    R.Open(w)
    local tick = w.profilePlaces
    Equal(S[tick.text].text .. " " .. tostring(tick:GetChecked()) .. " " .. tostring(S[tick].shown),
        "Positions per profile false true", "the tick, unticked")
    local hint = rawget(tick, "hint")
    Equal(hint:find("(Needs testing)", 1, true) ~= nil and hint:find("\226\128\148", 1, true) == nil, true,
        "its hover says Needs testing, no em dash")
    -- In a fight it can't change.
    lockdown = true
    tick:Click()
    Equal(tostring(ns.PlacePerProfile()) .. " | " .. S[w.note].text, "false | Profiles can't change in combat.", "not in a fight")
    lockdown = false
    R.Open(w)
    tick:Click()
    Equal(tostring(ns.PlacePerProfile()) .. " " .. tostring(tick:GetChecked()) .. " | " .. S[w.note].text,
        "true true | Each profile keeps its own bar spots and sizes now, starting with the ones you have.", "ticked")
    Equal(R.Spot(ns, "cd") .. " | " .. tostring(db.profiles[own].place.bars.cd.x == CD().x and db.profiles["Zriel Two"].place.bars.cd.x == CD().x)
        .. " | " .. tostring(db.placeOwner), shared .. " | true | " .. own,
        "ticking it on: every profile starts with the spots on screen, nothing moves")

    -- Each profile keeps its own: spots, sizes and the layout.
    ns.UseProfile("Zriel Two")
    local two = Move(-300, 52)
    ns.LayoutData().gap = 9
    ns.UseProfile(own)
    Equal(R.Spot(ns, "cd"), shared, "back on yours: your spot and size")
    Equal(ns.LayoutData().gap ~= 9, true, "and your layout")
    ns.UseProfile("Zriel Two")
    Equal(R.Spot(ns, "cd") .. " gap " .. ns.LayoutData().gap, two .. " gap 9", "on the other: its own spot, size and layout")
    -- The look stays every character's.
    ns.Set("barScale", 120)
    ns.UseProfile(own)
    Equal(ns.Get("barScale"), 120, "All bars and the look are shared")

    -- A copy, and a role's first profile, start with the spots on screen.
    local eleven = Move(11)
    ns.CopyProfile("Zriel Copy")
    Equal(R.Spot(ns, "cd") .. " " .. tostring(db.profiles["Zriel Copy"].place.bars.cd.x == CD().x), eleven .. " true",
        "a copy brings your spots")
    ns.UseRole("healer")
    Equal(ns.ProfileName() .. " " .. R.Spot(ns, "cd"), "Druid Healer " .. eleven, "a role starts where you are")
    local healer = Move(77)
    ns.UseProfile("Zriel Two")
    ns.UseRole("healer")
    Equal(R.Spot(ns, "cd"), healer, "and keeps its own after")

    -- Rename follows; a deleted profile's spots stay on screen for the next.
    ns.RenameProfile("Zriel Heals")
    Equal(tostring(db.placeOwner) .. " " .. tostring(db.profiles["Zriel Heals"].place ~= nil), "Zriel Heals true", "rename follows")
    ns.UseProfile("Zriel Copy")
    ns.DeleteProfile("Zriel Copy")
    Equal(tostring(db.profiles["Zriel Copy"]) .. " " .. R.Spot(ns, "cd"), "nil " .. eleven,
        "deleting the one you're on: its spots stay for the new one")
    ns.UseProfile("Zriel Two")
    Equal(R.Spot(ns, "cd"), two, "and the others are untouched")

    -- An import with its look: the profile you leave keeps its spots.
    ns.UseProfile(own)
    local before = R.Spot(ns, "cd")
    ns.ImportProfile("From A Friend", { lists = {}, setup = { bars = { cd = { point = "CENTER", x = 400, y = 20 } }, layout = {} } }, true)
    local friend = R.Spot(ns, "cd")
    Equal(ns.ProfileName() .. " " .. math.floor(CD().x), "From A Friend 400", "imported spots on screen")
    ns.UseProfile(own)
    Equal(R.Spot(ns, "cd"), before, "yours kept its own")
    ns.UseProfile("From A Friend")
    Equal(R.Spot(ns, "cd"), friend, "the import keeps the friend's")
    ns.UseProfile(own)
    Equal(#printed, 0, "no errors")

    -- Another character on another profile logs in: its spots, and yours kept.
    local saved = db
    character = { guid = "Player-1-0009", name = "Grom", realm = "Zephras" }
    R.class = { "Warrior", "WARRIOR" }
    saved.chars["Player-1-0009"] = "Zriel Two"
    local ns2 = R.Start(saved)
    Equal(ns2.ProfileName() .. " " .. R.Spot(ns2, "cd"), "Zriel Two " .. two, "another character: its profile's spots")
    character = { guid = "Player-1-0001", name = "Zriel", realm = "Zephras" }
    R.class = { "Druid", "DRUID" }
    local ns3 = R.Start(saved)
    Equal(ns3.ProfileName() .. " " .. R.Spot(ns3, "cd"), own .. " " .. before, "back on the first: its spots")

    -- Unticked: the spots on screen are everyone's again, the copies go.
    SlashCmdList.FECM("")
    local w3 = FECMFrame
    R.Open(w3)
    w3.profilePlaces:Click()
    local left = 0
    for _, profile in pairs(saved.profiles) do if profile.place then left = left + 1 end end
    Equal(tostring(ns3.PlacePerProfile()) .. " " .. left .. " " .. tostring(saved.placeOwner) .. " " .. R.Spot(ns3, "cd"),
        "false 0 nil " .. before, "unticked: nothing moves, the copies go")
    ns3.UseProfile("Zriel Two")
    Equal(R.Spot(ns3, "cd"), before, "and switching moves nothing again")
    Equal(#printed, 0, "no errors after")
end

print = _G.print
Equal(SecretMisuse[1], nil, "no secret misused anywhere")
Equal(WidgetMisses[1], nil, "no method Forever lacks looked for anywhere")
io.write("Roles checks passed: " .. checks .. " assertions.\n")
