-- Run the actual addon files against a mock game for the Raid Timers page:
-- its place in the /fecm window under More, its switches and choices, its
-- previews (the addon's own frames, never Blizzard's code), EraUI's Classic
-- cast bars owning the boss bars, and settings kept over a reload. The mock
-- game is a copy of Tools/TestBars.lua's: Tools/TestMockSync.mjs checks the
-- two match, and with --write copies it across. Tools/TestSkin.lua holds the
-- rules for Blizzard's own countdown, raid warning and boss cast bar frames.
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

-- Blizzard's raid timer frames ----------------------------------------------------------
-- Stand-ins for Blizzard's countdown, raid warnings and boss cast bars. The
-- sealed rules for them are in TestSkin.lua; here they only make sure the
-- window and its previews never run Blizzard's own code.

local blizzardCalling = false
-- A global function by its name, or a table's; the hook is the addon's own code.
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
local FLAT = "Interface\\Buttons\\WHITE8X8"
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
    _G.C_AddOns, _G.EraUI = nil, nil
end
-- EraUI installed, its Classic cast bars on or off.
local function EraUI(castBars)
    _G.C_AddOns = { IsAddOnLoaded = function(name) return name == "EraUI" end }
    _G.EraUI = { GetSetting = function(_, key)
        if key == "enabled" then return true end
        if key == "castBars" then return castBars end
    end }
end

local function LoadAll(saved, files)
    local ns = {}
    _G.ForeverEnhancedCooldownManagerDB = saved
    for _, file in ipairs(files or { "Core.lua", "Style.lua", "Skin.lua", "Resource.lua", "CastBar.lua", "RaidTimers.lua",
        "Ranks.lua", "Spells.lua", "Keybinds.lua", "Buffs.lua", "IconAuras.lua", "Bars.lua", "Layout.lua", "Theme.lua", "BarPage.lua",
        "LayoutPage.lua", "CastBarPage.lua", "RaidTimersPage.lua", "ProfileMenu.lua", "Window.lua", "Tour.lua",
        "MinimapButton.lua", "Notes.lua" }) do
        assert(loadfile(file))("ForeverEnhancedCooldownManager", ns)
    end
    Fire("ADDON_LOADED", "ForeverEnhancedCooldownManager")
    Fire("PLAYER_LOGIN")
    Fire("PLAYER_ENTERING_WORLD")
    return ns
end

local function Colour(obj)
    local r, g, b, a = Last(obj, "SetStatusBarColor", 1), Last(obj, "SetStatusBarColor", 2), Last(obj, "SetStatusBarColor", 3),
        Last(obj, "SetStatusBarColor", 4)
    return string.format("%g,%g,%g,%g", r, g, b, a or 1)
end

-- Where things are on a page: every place worked out from the anchors the
-- page set, each frame at its size, text about six units a letter (wider
-- than the game's) and twelve a line, a tick its box and label. Rect gives
-- left, top, width and height from the page's top left, y down.
local function Placer(page)
    local function Size(obj)
        local s = S[obj]
        if s.kind == "FontString" then
            if s.width > 0 then return s.width, obj:GetStringHeight() end
            return #(s.text or "") * 6, 12
        end
        if obj.box and obj.text then return 18 + #(S[obj.text].text or "") * 6, 16 end
        return s.width, s.height
    end
    local function At(point, left, top, width, height)
        local x = point:find("LEFT") and left or point:find("RIGHT") and left + width or left + width / 2
        local y = point:find("TOP") and top or point:find("BOTTOM") and top + height or top + height / 2
        return x, y
    end
    local function Rect(obj)
        local s = S[obj]
        local width, height = Size(obj)
        assert(#s.points == 1, "one anchor each")
        local p = s.points[1]
        local point, relative, relativePoint, x, y = p[1], s.parent, p[1], p[2] or 0, p[3] or 0
        if type(p[2]) == "table" then point, relative, relativePoint, x, y = p[1], p[2], p[3], p[4] or 0, p[5] or 0 end
        local left, top, w, h = 0, 0, 0, 0
        if relative ~= page then left, top, w, h = Rect(relative) end
        local ax, ay = At(relativePoint, left, top, w, h)
        local ox, oy = At(point, 0, 0, width, height)
        return ax + x - ox, ay - y - oy, width, height
    end
    return Rect
end
-- Everything showing that was made in a frame: in it, or in what's in it.
local function Within(frame)
    local found = {}
    for _, obj in ipairs(objects) do
        local parent = S[obj].parent
        while parent and parent ~= frame do parent = S[parent] and S[parent].parent end
        if parent == frame and S[obj].shown then found[#found + 1] = obj end
    end
    return found
end

-- The window: Raid Timers under More ------------------------------------------------------

Environment()
BlizzardFrames()
local ns = LoadAll(nil)
ns.ShowWindow()
local w = FECMFrame
Equal(w.nav.raid ~= nil and S[w.nav.raid.label].text, "Raid Timers", "Raid Timers in the window's list")
Equal(S[w.moreHeading].text, "MORE", "under a heading of its own, More, like Your bars")
local function Top(item) return -S[item].points[1][3] end
Equal(Top(w.nav.general) .. " " .. Top(w.nav.raid), "328 390", "below General, the rest of the list where it was")
local news = S[w.news].points[1]
Equal(Top(w.nav.raid) + S[w.nav.raid].height <= 489 - news[3] - S[w.news].height, true,
    "clear of the What's new button at the foot of the list")
Equal(type(w.nav.raid.hint) == "string" and w.nav.raid.hint:find("countdown", 1, true) ~= nil, true, "it says what it's for on hover")
w.nav.raid:Click()
local page = w.pages.raid
Equal(tostring(S[page].shown) .. " " .. tostring(S[w.pages.look].shown) .. " " .. tostring(S[w.nav.raid.fill].shown),
    "true false true", "clicked: its page, and it's the one highlighted")

-- Everything off at first. The countdown, tested in game, isn't labelled; the
-- other two parts say they need testing.
Equal(tostring(ns.Get("pullTimer")) .. " " .. tostring(ns.Get("raidWarnings")) .. " " .. tostring(ns.Get("bossCasts")),
    "false false false", "every part off by default")
for _, tick in ipairs({ page.pullTick, page.warningTick, page.bossTick }) do
    local untested = tick ~= page.pullTick
    Equal(tick.checked == false and (S[tick.text].text:find("(Needs testing)", 1, true) ~= nil) == untested, true,
        S[tick.text].text .. ": unticked, " .. (untested and "labelled as needing testing" or "not labelled as needing testing"))
end
Equal(S[page.status].text:find("Tick one", 1, true) ~= nil, true, "the title row says how to start")
Equal(S[page.pull].alpha .. " " .. S[page.warnings].alpha .. " " .. S[page.boss].alpha, "0.35 0.35 0.35",
    "the previews dimmed while their parts are off")
-- Sizes: each part's, then all of them, at 100 and greyed while their parts are off.
do
    local labels, values, greyed, notes = {}, {}, 0, {}
    for _, slider in ipairs(page.sizes) do
        labels[#labels + 1] = S[slider.label].text
        values[#values + 1] = tostring(slider.current)
        if slider.usable == false and S[slider].alpha == .35 then greyed = greyed + 1 end
        notes[#notes + 1] = slider.hint()
    end
    Equal(table.concat(labels, ", "), "Bar size, Number size, Warning size, Emote size, All sizes", "a size for each, and all sizes")
    Equal(table.concat(values, " ") .. " " .. greyed, "100 100 100 100 100 5", "each at 100, greyed while its part is off")
    Equal(notes[1] .. " | " .. notes[3] .. " | " .. notes[5], "Tick Pull and start countdown first. | Tick Raid warnings and"
        .. " boss emotes first. | Tick the countdown or the raid warnings first. The boss cast bars keep Blizzard's size.",
        "and each says why on hover")
    Equal(tostring(Last(page.pull.bar, "SetScale")) .. " " .. tostring(Last(page.pull.digit1, "SetScale")), "nil nil",
        "at 100% the preview is never scaled")
end
Equal(TimerTracker_StartTimerOfType ~= nil and rawget(RaidWarningFrame, "AddMessage") ~= nil, true, "Blizzard's own functions in place")
local plainStart, plainSay = TimerTracker_StartTimerOfType, rawget(RaidWarningFrame, "AddMessage")
local plainFill = rawget(Boss1TargetFrameSpellBar, "UpdateBarFillTexture")

-- The previews: the addon's own frames, dressed like Blizzard's would be.
local pull, warnings, boss = page.pull, page.warnings, page.boss
Equal(pull ~= TimerTracker and pull.bar ~= nil and S[pull].parent == page.boxes.pull and S[page.boxes.pull].parent == page.tray,
    true, "the countdown preview is the addon's own frame")
Equal(tostring(Last(page.boxes.pull, "SetClipsChildren")) .. " " .. tostring(Last(page.boxes.warnings, "SetClipsChildren")) .. " "
    .. tostring(Last(page.boxes.boss, "SetClipsChildren")) .. " "
    .. tostring(S[warnings].parent == page.boxes.warnings and S[boss].parent == page.boxes.boss), "true true true true",
    "each preview in a box of its own that cuts a big size at its edge")
Equal(Last(pull.bar, "SetStatusBarTexture") .. " " .. Colour(pull.bar), FLAT .. " 1,0,0,1",
    "a countdown bar in your texture, in Blizzard's red")
Equal(S[pull.bar.timeText].template .. " " .. Last(pull.bar.timeText, "SetFontObject"), "GameFontHighlight FECMFont12",
    "its time in your font")
Equal(S[pull.digit1].texture .. " " .. tostring(S[pull.digit1].desaturated), "Interface\\Timer\\BigTimerNumbers false",
    "a big number from Blizzard's own sheet, in its gold")
-- Centred on a spot of its own, as the game centres its numbers: it grows
-- round its middle, the bar's size never moves it, and it's drawn over the
-- bar. At Number size 200% it still fits its box.
do
    local spot, digit = pull.spot, S[pull.digit1].points
    local at = S[spot].points
    Equal(#digit .. " " .. table.concat({ digit[1][1], tostring(digit[1][2] == spot), digit[1][3], digit[1][4], digit[1][5] }, " ")
        .. " | " .. #at .. " " .. table.concat({ at[1][1], tostring(at[1][2] == pull), at[1][3], at[1][4] }, " ") .. " "
        .. tostring(S[spot].parent == pull) .. " " .. Last(spot, "SetFrameLevel"),
        "1 CENTER true CENTER 0 0 | 1 CENTER true TOP 0 true 2",
        "the preview's number centred on a spot under the bar, never on the bar, and over it")
    local middle, half = -at[1][5] - S[pull].points[1][3], S[pull.digit1].height / 2
    Equal(string.format("%g %g %g %g %g", middle - half, middle + half, middle - 2 * half, middle + 2 * half,
        S[page.boxes.pull].height), "33 65 17 81 88",
        "8 under the bar at 100%, as before; at 200% still inside its 88-high box")
end
local line1, line2 = warnings.lines[1], warnings.lines[2]
Equal(S[line1].text .. " / " .. S[line2].text, "Raid warning / Boss emote", "a raid warning and a boss emote")
Equal(tostring(S[line2].points[1][2] == line1) .. " " .. S[line2].points[1][3], "true BOTTOM",
    "the emote under the warning, as Blizzard stacks them, so each shows its size")
Equal(Last(line1, "SetFont", 1) .. " " .. Last(line1, "SetFont", 2) .. " " .. Last(line1, "SetFont", 3),
    "Fonts\\FRIZQT__.TTF 20 OUTLINE", "in Friz Quadrata, outlined, as big as Blizzard's at rest")
Equal(string.format("%g,%g,%g", S[line1].colour[1], S[line1].colour[2], S[line1].colour[3]), "1,0.282,0",
    "each in Blizzard's colour for it")
Equal(S[boss.bar.Border].alpha .. " " .. S[boss.bar.Background].alpha .. " " .. Colour(boss.bar),
    "0 0 1,0.7,0,1", "a boss cast bar without Blizzard's modern frame, gold")
Equal(Last(boss.bar.Text, "SetFontObject") .. " " .. S[boss.bar.Text].text, "FECMFont10 Frostbolt Volley", "the spell's name in your font")

-- Ticking each part on.
page.pullTick:Click()
Equal(tostring(ns.Get("pullTimer")) .. " " .. S[pull].alpha, "true 1", "the countdown on: saved, its preview in full")
Equal(TimerTracker_StartTimerOfType ~= plainStart, true, "and Blizzard's countdown hooked from now on")
Equal(S[page.status].text, "Your look on 1 of 3. The previews show your choices.", "the title row counts the parts on")
page.warningTick:Click()
page.bossTick:Click()
Equal(tostring(rawget(RaidWarningFrame, "AddMessage") ~= plainSay) .. " " .. tostring(rawget(Boss1TargetFrameSpellBar, "UpdateBarFillTexture") ~= plainFill)
    .. " " .. S[page.warnings].alpha .. " " .. S[page.boss].alpha, "true true 1 1", "raid warnings and boss casts on and hooked")
Equal(S[Boss1TargetFrameSpellBar.Border].alpha .. " " .. Last(Boss5TargetFrameSpellBar.Text, "SetFontObject"), "0 FECMFont10",
    "Blizzard's boss bars restyled at once")
Equal(S[page.status].text, "Your look on 3 of 3. The previews show your choices.", "all three")

-- Colours: click one, click it again for Blizzard's own.
local blue = page.pullColours.swatches[3]
Equal(blue.key, "blue", "the countdown's colours are the bar colours")
blue:Click()
Equal(ns.Get("pullColour") .. " " .. S[page.pullColours.chosen].text .. " " .. Colour(pull.bar), "blue Blue 0.24,0.55,0.88,1",
    "a colour for the countdown bar, on the preview at once")
blue:Click()
Equal(ns.Get("pullColour") .. " " .. S[page.pullColours.chosen].text .. " " .. Colour(pull.bar), "default Blizzard's red 1,0,0,1",
    "clicked again: Blizzard's red")
-- The big numbers.
page.numbers.buttons[3]:Click()
Equal(ns.Get("pullNumbers") .. " " .. tostring(S[pull.digit1].desaturated) .. " " .. table.concat(S[pull.digit1].tint, ","),
    "bar true 1,0,0", "numbers in the bar's colour: made grey, then tinted red")
page.numbers.buttons[2]:Click()
Equal(ns.Get("pullNumbers") .. " " .. table.concat(S[pull.digit1].tint, ","), "white 1,1,1", "white")
Equal(page.numbers.selected, "white", "the choice highlighted")

-- Raid warnings: font, outline, shadow and each kind's colour.
Equal(S[page.font.buttons[4].label].text .. " " .. Last(page.font.buttons[4].label, "SetFontObject"), "Skurri FECMSampleskurri",
    "each font by its name, in its own face")
page.font.buttons[4]:Click()
page.outline.buttons[3]:Click()
page.shadow:Click()
Equal(ns.Get("warningFont") .. " " .. ns.Get("warningOutline") .. " " .. tostring(ns.Get("warningShadow")), "skurri thick false",
    "font, outline and shadow saved")
Equal(Last(line2, "SetFont", 1) .. " " .. Last(line2, "SetFont", 3) .. " " .. Last(line2, "SetShadowOffset", 1),
    "Fonts\\skurri.ttf THICKOUTLINE 0", "and on the preview")
local purple = page.emoteColours.swatches[5]
Equal(purple.key .. " " .. page.emoteColours.swatches[6].key, "purple class", "text colours, your class colour last")
purple:Click()
Equal(string.format("%g,%g,%g", S[line2].colour[1], S[line2].colour[2], S[line2].colour[3]) .. " "
    .. string.format("%g", S[line1].colour[3]) .. " " .. S[page.emoteColours.chosen].text .. " " .. S[page.warningColours.chosen].text,
    "0.72,0.52,1 0 Purple Blizzard's", "boss emotes purple, raid warnings still Blizzard's")
page.warningColours.swatches[1]:Click()
Equal(string.format("%g,%g,%g", S[line1].colour[1], S[line1].colour[2], S[line1].colour[3]), "1,1,1", "raid warnings white")
page.warningColours.swatches[1]:Click()
Equal(string.format("%g,%g,%g", S[line1].colour[1], S[line1].colour[2], S[line1].colour[3]), "1,0.282,0",
    "clicked again: Blizzard's colour back on the preview")

-- Boss cast bars: a colour, and the note on secret casts.
page.bossColours.swatches[4]:Click()
Equal(ns.Get("bossColour") .. " " .. Colour(boss.bar), "green 0.38,0.74,0.3,1", "a colour for boss casts")
Equal(S[page.bossNote].text:find("secret", 1, true) ~= nil, true, "the note says what the game keeps secret")

-- Sizes, the parts on: usable, saved, and on the preview at once.
do
    local function G(value) return value and string.format("%g", value) or "nil" end
    local barSize, numberSize, warningSize, emoteSize, allSizes = table.unpack(page.sizes)
    Equal(tostring(barSize.usable) .. " " .. tostring(warningSize.usable) .. " " .. tostring(allSizes.usable) .. " " .. S[barSize].alpha,
        "true true true 1", "the parts on: their sizes usable")
    Equal(barSize.hint():find("100 is Blizzard's size", 1, true) ~= nil and allSizes.hint():find("Frame Size in Edit Mode", 1, true) ~= nil,
        true, "each says what it does; all sizes points to Edit Mode for the boss frames")
    -- All sizes names the four it multiplies (two sit in the other column);
    -- the bar's says two countdowns overlap when big, the texts' that long
    -- ones wrap past Blizzard's five lines.
    Equal(tostring(allSizes.hint():find("^Bar, Number, Warning and Emote size together") ~= nil) .. " "
        .. tostring(barSize.hint():find("Two countdowns at once overlap above about 180", 1, true) ~= nil) .. " "
        .. tostring(warningSize.hint():find("more lines than Blizzard's usual 5", 1, true) ~= nil) .. " "
        .. tostring(emoteSize.hint():find("more lines than Blizzard's usual 5", 1, true) ~= nil), "true true true true",
        "the notes say what all sizes covers, and what big sizes do")
    local applied, apply = 0, ns.RaidTimers.Apply
    ns.RaidTimers.Apply = function(...) applied = applied + 1; return apply(...) end
    barSize:Choose(150)
    Equal(applied, 1, "a size slider applies to Blizzard's frames at once, not only the preview")
    ns.RaidTimers.Apply = apply
    numberSize:Choose(200)
    Equal(ns.Get("pullBarSize") .. " " .. ns.Get("pullNumberSize") .. " " .. G(Last(pull.bar, "SetScale")) .. " "
        .. G(Last(pull.digit1, "SetScale")), "150 200 1.5 2", "the countdown's sizes saved, the preview's bar and number at them")
    warningSize:Choose(150)
    emoteSize:Choose(50)
    Equal(Last(line1, "SetFont", 2) .. " " .. Last(line2, "SetFont", 2), "30 10",
        "the preview's raid warning at 150%, its boss emote at 50%")
    allSizes:Choose(120)
    Equal(G(Last(pull.bar, "SetScale")) .. " " .. G(Last(pull.digit1, "SetScale")) .. " " .. Last(line1, "SetFont", 2) .. " "
        .. Last(line2, "SetFont", 2), "1.8 2.4 36 12", "all sizes at 120%: each one times 1.2, in proportion")
    Equal(barSize.current .. " " .. allSizes.current, "150 120", "the sliders show what's saved")
    -- Snapped to steps of 5 and kept within the limits.
    allSizes:Choose(500)
    barSize:Choose(12)
    numberSize:Choose(203)
    Equal(ns.Get("raidSize") .. " " .. ns.Get("pullBarSize") .. " " .. ns.Get("pullNumberSize"), "150 50 200",
        "all sizes 50 to 150, each 50 to 200, in steps of 5")
    allSizes:Choose(110)
    barSize:Choose(120)
    -- Untick a part: its sizes grey and say why; the preview dims, keeping them.
    page.pullTick:Click()
    Equal(tostring(barSize.usable) .. " " .. tostring(allSizes.usable) .. " " .. barSize.hint() .. " " .. G(Last(pull.bar, "SetScale")),
        "false true Tick Pull and start countdown first. 1.32", "the countdown off: its sizes greyed, all sizes still for the warnings")
    page.pullTick:Click()
end

-- Every control says what it does on hover.
local controls = { page.pullTick, page.warningTick, page.bossTick, page.shadow, page.editMode }
for _, group in ipairs({ page.numbers, page.font, page.outline }) do
    for _, button in ipairs(group.buttons) do controls[#controls + 1] = button end
end
for _, row in ipairs({ page.pullColours, page.bossColours, page.warningColours, page.emoteColours }) do
    for _, swatch in ipairs(row.swatches) do controls[#controls + 1] = swatch end
end
for _, slider in ipairs(page.sizes) do controls[#controls + 1] = slider end
local quiet = 0
for _, control in ipairs(controls) do
    local hint = type(control.hint) == "function" and control.hint(control) or control.hint
    if type(hint) ~= "string" or hint == "" or hint:find("\226\128\148", 1, true) then quiet = quiet + 1 end
end
Equal(#controls .. " " .. quiet, "44 0", "every tick, choice, colour, size and button has a note, none with an em dash")
-- No "In the game" section: no heading, no how-to lines anywhere on the page.
-- The boss cast bars' how-to stays in the Edit Mode button's own note.
do
    local found = {}
    for _, obj in ipairs(Within(page)) do
        local text = S[obj].kind == "FontString" and tostring(S[obj].text or "") or ""
        for _, phrase in ipairs({ "IN THE GAME", "In the game", "/countdown", "/rw", "boss timeline", "WoW Forever yet" }) do
            if text:find(phrase, 1, true) then found[#found + 1] = text end
        end
    end
    local editNote = page.editMode.hint(page.editMode)
    Equal(tostring(page.help) .. " " .. #found .. " " .. tostring(editNote:find("Tick Boss Frames there to see the boss cast bars", 1, true) ~= nil),
        "nil 0 true", "no In the game section on the page; the Edit Mode button's note still says to tick Boss Frames")
end
-- The page fits above the footer, and nothing on it overlaps (see Placer).
do
    local FOOTER = 489 -- the page's height, down to the window's footer
    local Rect = Placer(page)
    local function Overlap(a, b)
        return a[1] < b[1] + b[3] and b[1] < a[1] + a[3] and a[2] < b[2] + b[4] and b[2] < a[2] + a[4]
    end
    -- Every piece of the options, and the three preview boxes: inside their
    -- frame, and none on another.
    local function Laid(parent, list)
        local left, top, width, height = Rect(parent)
        local rects, outside, overlaps = {}, {}, {}
        for _, obj in ipairs(list) do
            local l, t, w, h = Rect(obj)
            local rect = { l, t, w, h, S[obj].text or (obj.text and S[obj.text].text) or (obj.label and S[obj.label].text) or S[obj].kind }
            if l < left or t < top or l + w > left + width or t + h > top + height then outside[#outside + 1] = rect[5] end
            for _, other in ipairs(rects) do
                if Overlap(rect, other) then overlaps[#overlaps + 1] = rect[5] .. " on " .. other[5] end
            end
            rects[#rects + 1] = rect
        end
        return #rects, table.concat(outside, ", "), table.concat(overlaps, ", ")
    end
    local inside = {}
    for _, obj in ipairs(objects) do
        if S[obj].parent == page.options and S[obj].shown then inside[#inside + 1] = obj end
    end
    local count, outside, overlaps = Laid(page.options, inside)
    Equal(count .. " | " .. outside .. " | " .. overlaps, "49 |  | ",
        "every tick, label, colour, choice, size, the Edit Mode button and the boss note inside the options, none on another")
    count, outside, overlaps = Laid(page.tray, { page.boxes.pull, page.boxes.warnings, page.boxes.boss })
    Equal(count .. " | " .. outside .. " | " .. overlaps, "3 |  | ", "the three preview boxes inside the preview, side by side")
    -- The boss note at its longest, still inside the options.
    local note, top = 0, select(2, Rect(page.bossNote)) - select(2, Rect(page.options))
    for _, text in ipairs({ S[page.bossNote].text,
        "EraUI's Cast Bars style these while they're on (/era, Casting). This waits until they're off, or for a newer EraUI.",
        "While this is on, they take your look instead of EraUI's. In a fight the game keeps each cast secret, so the bar keeps one colour." }) do
        page.bossNote:SetText(text)
        note = math.max(note, page.bossNote:GetStringHeight())
    end
    FECMFrame:Refresh()
    -- The page closes up under the options: nothing of its own below them,
    -- and they end above the footer. (page.top, the tour's two-cornered
    -- outline target, sits on the preview and the tick row.)
    local lowest, below, pieces = 0, {}, 0
    local _, optionsTop, _, optionsHeight = Rect(page.options)
    for _, obj in ipairs(objects) do
        if S[obj].parent == page and S[obj].shown and obj ~= page.top then
            pieces = pieces + 1
            local _, t, _, h = Rect(obj)
            lowest = math.max(lowest, t + h)
            if t + h > optionsTop + optionsHeight then below[#below + 1] = S[obj].text or S[obj].kind end
        end
    end
    Equal(pieces .. " " .. lowest .. " " .. (optionsTop + optionsHeight) .. " | " .. table.concat(below, ", ") .. " | "
        .. tostring(lowest <= FOOTER) .. " " .. tostring(top + note <= optionsHeight), "4 388 388 |  | true true",
        "the title, its status, the preview and the options; nothing below the options, which end above the footer (489);"
            .. " the boss note inside them at its longest")
end

-- The previews animate on their own, never through Blizzard's code.
local tick = S[page.tray].scripts.OnUpdate
tick(page.tray, 1.5)
Equal(Last(pull.bar.timeText, "SetFormattedText", 2) .. " " .. string.format("%.3f", Last(pull.bar, "SetValue")), "41 0.875",
    "the countdown preview runs down")
local left, right, top = Last(pull.digit1, "SetTexCoord", 1), Last(pull.digit1, "SetTexCoord", 2), Last(pull.digit1, "SetTexCoord", 3)
Equal(string.format("%.4f %.4f %.4f", left, right, top), "0.0000 0.2500 0.3320", "its number counts down: 4, from Blizzard's sheet")
Equal(string.format("%.1f", Last(boss.bar, "SetValue")), "0.6", "the boss cast fills")
tick(page.tray, 2)
Equal(string.format("%g", Last(pull.digit1, "SetTexCoord", 1)), "0.5", "then 2")

-- In a fight, choices still change: looks only.
lockdown = true
page.outline.buttons[1]:Click()
Equal(ns.Get("warningOutline") .. " " .. Last(line1, "SetFont", 3), "none ", "changed in a fight, as looks only")
page.sizes[4]:Choose(60)
Equal(ns.Get("emoteSize") .. " " .. Last(line2, "SetFont", 2), "60 13", "and sizes too")
lockdown = false
Equal(#printed, 0, "no errors on the page")

-- Edit Mode: opened only by the game's own /editmode, from a click on a
-- secure button of the game's. It's made the first time the mouse comes over
-- the page's Edit Mode button, out of a fight, and is never part of the
-- window, so the window can always be moved and closed in a fight. Once Edit
-- Mode shows, the window closes, as Edit Mode opens under it.
-- A press goes to whatever takes the mouse on top under it, so this keeps the
-- game's layering too: each frame's strata (its own, or its parent's), its
-- level (its own, never under its parent's), and the window coming to the
-- front of its strata whenever it's pressed or opened (it's toplevel). The
-- secure button's OnClick is the template's, as SecureActionButton_OnClick
-- (Blizzard_FrameXML/SecureTemplates.lua, forever branch) runs it for an
-- addon's button, which never gets isKeyPress or isSecureAction: the action
-- on the press with Action Button Use Key Down on, on the release with it off.
do
    local made, makes, touched, panels = nil, 0, 0, 0
    -- Anything that would hold the window in a fight: none of it in one.
    local PROTECTED = { "SetPoint", "SetAllPoints", "ClearAllPoints", "Show", "Hide", "SetShown", "SetFrameLevel",
        "SetFrameStrata", "RegisterForClicks", "SetParent", "SetScale", "SetScript", "SetSize", "EnableMouse", "Raise" }
    function Proto:SetAllPoints(relative) S[self].points = { { "ALL", relative } } end
    -- A frame's strata, as set (the window's was set as it was made); UIParent's children start at MEDIUM.
    function Proto:SetFrameStrata(strata) S[self].strata = strata end
    function Proto:GetFrameStrata() return S[self].strata or Last(self, "SetFrameStrata") or "MEDIUM" end
    -- Like the game: IsMouseOver is only where the mouse is (mouseOver);
    -- IsMouseMotionFocus is whether the frame is what the mouse is on, with
    -- nothing else over it there (focus).
    function Proto:IsMouseMotionFocus() return S[self].focus == true end

    -- The game's layering.
    local RANK = { BACKGROUND = 1, LOW = 2, MEDIUM = 3, HIGH = 4, DIALOG = 5, FULLSCREEN = 6, FULLSCREEN_DIALOG = 7, TOOLTIP = 8 }
    local REGION = { Texture = true, FontString = true, Font = true }
    local flatLevel = Proto.GetFrameLevel
    local function Strata(f)
        local own = S[f].strata or Last(f, "SetFrameStrata")
        if own then return own end
        local parent = S[f].parent
        return parent and S[parent] and Strata(parent) or "MEDIUM"
    end
    local function Level(f)
        local parent = S[f].parent
        local floor = parent and S[parent] and Level(parent) + 1 or 0
        return math.max(S[f].level or Last(f, "SetFrameLevel") or floor, floor)
    end
    local function InTree(f, root)
        while f do
            if f == root then return true end
            f = S[f] and S[f].parent
        end
        return false
    end
    function Proto:GetFrameLevel() return Level(self) end
    function Proto:SetFrameLevel(level) S[self].level, S[self].last.SetFrameLevel = level, table.pack(level) end
    function Proto:EnableMouse(on) S[self].mouse, S[self].last.EnableMouse = on, table.pack(on) end
    -- To the front of its strata: above every other frame showing in it.
    function Proto:Raise()
        local strata, top = Strata(self), 0
        for _, f in ipairs(objects) do
            if not REGION[S[f].kind] and f:IsVisible() and not InTree(f, self) and Strata(f) == strata then
                top = math.max(top, Level(f))
            end
        end
        S[self].level, S[self].last.Raise = math.max(Level(self), top + 1), table.pack()
    end

    -- The game's own click on the secure button.
    local useKeyDown = "1" -- Action Button Use Key Down, on as the game starts
    local canEnter = true -- EditModeManagerFrame:CanEnterEditMode()
    local opened, ranOn, chat = 0, nil, {}
    local function TemplateClick(self, _, down)
        local onPress = useKeyDown == "1"
        if not ((down and onPress) or (not down and not onPress)) then return end
        local a = S[self].attributes
        if a.type == "macro" and a.macrotext == "/editmode" then
            -- The game's /editmode: Edit Mode, or a line in chat saying it can't.
            ranOn = down and "press" or "release"
            if canEnter then
                opened = opened + 1
                S[EditModeManagerFrame].shown = true
            else
                chat[#chat + 1] = "can't enter Edit Mode"
            end
        end
    end
    -- Clicks it hears: the press, the release, or both.
    local function Registered(f, down)
        local call = S[f].last.RegisterForClicks
        for i = 1, call and call.n or 0 do
            if call[i] == (down and "AnyDown" or "AnyUp") or call[i] == (down and "LeftButtonDown" or "LeftButtonUp") then
                return true
            end
        end
        return false
    end

    local create = _G.CreateFrame
    _G.CreateFrame = function(kind, name, parent, template)
        local f = create(kind, name, parent, template)
        if template == "SecureActionButtonTemplate" then
            assert(not lockdown, "made a secure button in a fight")
            made, makes = f, makes + 1
            S[f].template, S[f].attributes = template, {}
            S[f].scripts.OnClick = TemplateClick
            for _, method in ipairs(PROTECTED) do
                local plain = f[method]
                rawset(f, method, function(self, ...)
                    if lockdown then touched = touched + 1 end
                    return plain(self, ...)
                end)
            end
            rawset(f, "SetAttribute", function(self, key, value)
                if lockdown then touched = touched + 1 end
                S[self].attributes[key] = value
            end)
            rawset(f, "SetParent", function(self, parent)
                if lockdown then touched = touched + 1 end
                S[self].parent = parent
            end)
        end
        return f
    end
    -- Whether the secure button sits anywhere inside the window.
    local function InWindow()
        local parent = S[made].parent
        while parent do
            if parent == FECMFrame then return true end
            parent = S[parent] and S[parent].parent
        end
        return false
    end
    -- No addon code opens Edit Mode or a panel.
    _G.ShowUIPanel = function() panels = panels + 1 end
    rawset(EditModeManagerFrame, "EnterEditMode", function() panels = panels + 1 end)
    -- As the game: hiding a frame runs OnHide on everything showing inside it.
    local function HideTree(frame)
        local inside = {}
        for _, obj in ipairs(objects) do
            -- (A font object isn't on screen: it has no IsVisible.)
            if obj ~= frame and S[obj].kind ~= "Font" and obj:IsVisible() then
                local parent = S[obj].parent
                while parent and parent ~= frame do parent = S[parent] and S[parent].parent end
                if parent == frame then inside[#inside + 1] = obj end
            end
        end
        Proto.Hide(frame)
        for _, obj in ipairs(inside) do
            if S[obj].scripts.OnHide then S[obj].scripts.OnHide(obj) end
        end
    end
    -- The window hidden by the addon's own code, as the game would.
    rawset(FECMFrame, "Hide", HideTree)
    local function Enter(frame) S[frame].scripts.OnEnter(frame) end
    local function Leave(frame) S[frame].scripts.OnLeave(frame) end
    local function Footer() return S[FECMFrame.note].text end
    local IN_A_FIGHT = "Edit Mode can't open in a fight. Try again once it's over."
    local AGAIN = "Click Edit Mode again to open it, or type /editmode."
    local button = page.editMode

    -- Takes the mouse: a plain button as the game makes it; the secure one
    -- only once told to, not left to the template.
    local function Mouse(f)
        local on = S[f].mouse
        if on == nil and f ~= made then on = S[f].kind == "Button" end
        return on == true
    end
    -- What a press on the page's Edit Mode button reaches: of the frames
    -- there that take the mouse, the one on top (strata, then level). The
    -- secure button is there when it's laid over the whole of the page's.
    local function Under()
        local best, height
        for _, f in ipairs({ button, made }) do
            local at = S[f].points
            local there = f == button or (#at == 1 and at[1][1] == "ALL" and at[1][2] == button)
            if there and f:IsVisible() and Mouse(f) then
                local h = RANK[Strata(f)] * 1000000 + Level(f)
                if not best or h > height then best, height = f, h end
            end
        end
        return best
    end
    -- A left click there, as the game delivers it: to the secure button if
    -- it's on top, the press and then the release (only while it still
    -- shows), each followed by its PostClick; otherwise to the page's button,
    -- whose press brings the window to the front (toplevel) and whose
    -- release clicks it.
    local function Press()
        local target = Under()
        if target == made then
            for _, down in ipairs({ true, false }) do
                if made:IsVisible() and Registered(made, down) then
                    S[made].scripts.OnClick(made, "LeftButton", down)
                    local post = S[made].scripts.PostClick
                    if post then post(made, "LeftButton", down) end
                end
            end
            return "secure"
        elseif target == button then
            FECMFrame:Raise()
            button:Click()
            return "page"
        end
        return "nothing"
    end
    -- Where the secure button is: shown, laid over the whole of the page's
    -- button (both corners), and its strata.
    local function Over()
        local points = S[made].points
        return tostring(S[made].shown) .. " " .. #points .. " " .. tostring(points[1] and points[1][1]) .. " "
            .. tostring(points[1] and points[1][2] == button) .. " " .. Strata(made)
    end
    -- What a press there reaches, and whether its strata is above the window's.
    local function OnTop()
        return tostring(Under() == made) .. " " .. tostring(RANK[Strata(made)] > RANK[Strata(FECMFrame)])
    end
    -- A click with Use Key Down on ("1") or off ("0"): what it reached, how
    -- many times Edit Mode opened, on the press or the release, and whether
    -- the window and the secure button still show (and its anchors).
    local function Click(keyDown)
        useKeyDown, ranOn = keyDown, nil
        local was = opened
        local reached = Press()
        return reached .. " " .. (opened - was) .. " " .. tostring(ranOn) .. " " .. tostring(S[FECMFrame].shown) .. " "
            .. tostring(S[made].shown) .. " " .. #S[made].points
    end
    -- Edit Mode shut, the window opened again on the page, the mouse coming
    -- onto the button (the page's hears OnEnter, then the secure one takes it).
    local function Again()
        S[EditModeManagerFrame].shown = false
        ns.ShowWindow()
        FECMFrame:Select("raid")
        Enter(button)
        Leave(button)
        Enter(made)
    end

    Equal(S[button.label].text .. " " .. tostring(S[button].points[1][2] == page.bossTick) .. " " .. S[button].points[1][3] .. " "
        .. tostring(made) .. " " .. tostring(Under() == button), "Edit Mode true RIGHT nil true",
        "an Edit Mode button beside the Boss cast bars tick; nothing secure made yet")

    Enter(button)
    Equal(S[made].template .. " " .. S[made].name .. " " .. tostring(S[made].parent == UIParent) .. " " .. tostring(InWindow()),
        "SecureActionButtonTemplate FECMEditModeButton true false",
        "the mouse over it: a secure button of the game's, UIParent's, never inside the window")
    Equal(S[made].attributes.type .. " " .. S[made].attributes.macrotext .. " " .. tostring(Last(made, "RegisterForClicks", 1)) .. " "
        .. tostring(Last(made, "RegisterForClicks", 2)) .. " " .. tostring(Registered(made, true)) .. " " .. tostring(Registered(made, false))
        .. " " .. tostring(S[made].mouse), "macro /editmode AnyUp AnyDown true true true",
        "a click runs the game's own /editmode, heard on the press and the release (either Use Key Down setting); it takes the mouse")
    Equal(Strata(FECMFrame) .. " | " .. Over() .. " | " .. OnTop(), "FULLSCREEN_DIALOG | true 1 ALL true TOOLTIP | true true",
        "laid over the whole of the page's button a strata above the window: a press there reaches it")
    -- The game moves the mouse onto it, so the page's button hears OnLeave
    -- first: that leaves the secure one where it is, under the mouse.
    Leave(button)
    Equal(Over() .. " | " .. OnTop(), "true 1 ALL true TOOLTIP | true true",
        "the page's button's OnLeave, as the secure one takes the mouse, leaves it there")
    Enter(made)
    Equal(Footer() == button.hint(button) and Footer():find("Tick Boss Frames", 1, true) ~= nil
        and Footer():find("closes this window", 1, true) ~= nil, true,
        "its note in the footer: Edit Mode, closing this window, then Boss Frames")
    -- The window brought to the front of its strata with the mouse resting
    -- there (Options > AddOns' Open settings, which is ns.ShowWindow; a press
    -- anywhere on the window does the same, /fecm only shows or hides it):
    -- the page's button comes up over everything else in the window's
    -- strata, but the secure one is a strata above.
    ns.ShowWindow()
    Equal(OnTop() .. " " .. tostring(Level(button) > Level(made)), "true true true",
        "the window raised in its own strata: the secure one still what a press reaches")
    -- What's new opened from the keyboard (/fecm new) with the mouse still
    -- there: it opens over the window, right over the button, and the secure
    -- one, a strata above it, is taken away first so it can't take What's
    -- new's clicks. Closed again, the game's OnEnter puts it back on top.
    ns.ShowNotes()
    Equal(tostring(S[ns.notes].shown) .. " " .. tostring(S[made].shown) .. " " .. #S[made].points, "true false 0",
        "What's new opened with the mouse on the button: the secure one taken away, not left on top of it")
    ns.notes:Hide()
    Enter(button)
    Leave(button)
    Enter(made)
    Equal(Over() .. " | " .. OnTop(), "true 1 ALL true TOOLTIP | true true",
        "What's new closed, the mouse on the button: the secure one back over it, on top")
    Leave(made)
    Equal(tostring(S[made].shown) .. " " .. #S[made].points .. " " .. tostring(Footer():find("Edit Mode", 1, true)), "false 0 nil",
        "the mouse gone: hidden, anchored to nothing, the footer at rest")
    -- The window closed, or the page switched, with the mouse still there.
    Enter(button)
    HideTree(FECMFrame)
    Equal(tostring(S[made].shown) .. " " .. #S[made].points, "false 0", "the window closed under the mouse: taken away too")
    ns.ShowWindow()
    Enter(button)
    HideTree(page)
    Equal(tostring(S[made].shown) .. " " .. #S[made].points, "false 0", "another page chosen: taken away too")
    FECMFrame:Select("raid")

    -- Back on the page, the mouse resting on the button: the game sends no
    -- new OnEnter, so a press reaches the page's own button. That raises the
    -- window, and out of a fight puts the secure one straight back over it,
    -- on top, with the footer saying to click again; the message stays as
    -- the secure one takes the mouse, and the next click opens Edit Mode.
    Equal(Press() .. " | " .. Footer() .. " | " .. Over() .. " | " .. OnTop() .. " " .. opened,
        "page | " .. AGAIN .. " | true 1 ALL true TOOLTIP | true true 0",
        "a press on the page's own button: the secure one back on top, the footer says to click again")
    Leave(button)
    Enter(made)
    Equal(Footer(), AGAIN, "the message stays as the secure one takes the mouse")
    Equal(Click("1"), "secure 1 press false false 0",
        "the next click: Edit Mode opens, the window closes and the secure button goes with it")
    Again()

    -- A fight: taken away as it starts, before the game locks secure buttons.
    -- The mouse rests on the button from here on, through the whole fight,
    -- with nothing over it.
    S[button].mouseOver, S[button].focus = true, true
    Fire("PLAYER_REGEN_DISABLED")
    lockdown = true
    Equal(tostring(S[made].shown) .. " " .. #S[made].points .. " " .. S[button].alpha .. " " .. tostring(button.usable),
        "false 0 0.35 false", "a fight: the secure button gone before the lock, the page's button greyed")
    Enter(button)
    Equal(tostring(S[made].shown) .. " " .. Footer(), "false " .. IN_A_FIGHT,
        "the mouse over it in a fight: nothing secure moved, the note says why")
    -- Clicked in a fight: the page's own button takes it, with its own message, the hover note gone first.
    Leave(button)
    local resting = Footer()
    Equal(Press() .. " " .. tostring(resting ~= IN_A_FIGHT) .. " " .. Footer(), "page true " .. IN_A_FIGHT,
        "clicked in a fight: the page's button says so itself")
    -- The window moves and closes in a fight, and What's new opens and
    -- closes: nothing secure is in it, holds on to it or is touched.
    FECMFrame:StartMoving()
    FECMFrame:StopMovingOrSizing()
    ns.ShowNotes()
    ns.notes:Hide()
    HideTree(FECMFrame)
    ns.ShowWindow()
    FECMFrame:Select("raid")
    Equal(tostring(S[FECMFrame].shown) .. " " .. #S[made].points .. " " .. touched, "true 0 0",
        "the window moved, closed and opened, and What's new opened, in a fight; the secure button never touched")
    -- The fight over with the mouse still on the button: the game sends no
    -- new OnEnter, so the secure button goes back over it at once.
    lockdown = false
    Fire("PLAYER_REGEN_ENABLED")
    Equal(S[button].alpha .. " " .. tostring(button.usable) .. " | " .. Over() .. " | " .. OnTop(),
        "1 true | true 1 ALL true TOOLTIP | true true",
        "the fight over, the mouse never moved: the button back, the secure one over it again, on top")
    local placedInWindow = InWindow()
    Leave(button)
    Enter(made)
    Equal(Footer() == button.hint(button), true, "and its note, as the game moves the mouse onto it")

    -- Clicked when Edit Mode can't open: the game says so in chat, and the
    -- window and the secure button stay. Clicked when it can: Edit Mode
    -- opens once, on the press with Use Key Down on (as the game starts) or
    -- on the release with it off; then the window closes (Edit Mode opens
    -- under it) and the secure button goes with it, so a release after the
    -- press finds nothing.
    canEnter = false
    Equal(Click("1") .. " " .. #chat, "secure 0 press true true 1 1", "Edit Mode can't open: the game says why; the window stays")
    canEnter = true
    Equal(Click("1"), "secure 1 press false false 0", "Use Key Down on: Edit Mode opens on the press, the window closes")
    Again()
    Equal(Click("0"), "secure 1 release false false 0", "Use Key Down off: on the release, the window closes")
    S[EditModeManagerFrame].shown = false
    -- A fight ending with the window closed, or the mouse elsewhere: nothing placed.
    local function Fight()
        Fire("PLAYER_REGEN_DISABLED")
        lockdown = true
        lockdown = false
        Fire("PLAYER_REGEN_ENABLED")
        return tostring(S[made].shown) .. " " .. #S[made].points
    end
    local closed = Fight()
    ns.ShowWindow()
    FECMFrame:Select("raid")
    S[button].mouseOver, S[button].focus = false, false
    Equal(closed .. " | " .. Fight(), "false 0 | false 0", "a fight ends with the window closed, or the mouse off the button: nothing placed")
    -- The mouse where the button is, but What's new (or the "Are you sure?"
    -- shade) over it as the fight ends: the button isn't what the mouse is
    -- on, so the secure one isn't laid over them.
    S[button].mouseOver = true
    Equal(Fight(), "false 0", "a fight ends with the mouse there but What's new over the button: nothing placed")
    S[button].mouseOver = false
    -- A fight starting or ending refreshes the window only while this page
    -- shows: here its Edit Mode message is no longer true and goes; on
    -- another page, that page's message stays.
    local reached, said = Press(), Footer()
    local fought = Fight()
    Equal(reached .. " " .. tostring(said == AGAIN) .. " " .. fought .. " " .. tostring(Footer() == AGAIN), "page true false 0 false",
        "the page's own button clicked, then a fight: its Click again message gone with the fight")
    FECMFrame:Select("general")
    FECMFrame:Say("Kept.")
    FECMFrame:Refresh()
    said = Footer()
    fought = Fight()
    Equal(said .. " " .. fought .. " " .. Footer(), "Kept. false 0 Kept.", "on another page, a fight leaves its message alone")
    FECMFrame:Select("raid")
    Equal(makes .. " " .. touched .. " " .. panels .. " " .. #printed .. " " .. tostring(placedInWindow) .. " "
        .. tostring(S[made].parent == UIParent) .. " " .. tostring(S[made].scripts.OnClick == TemplateClick) .. " "
        .. tostring(S[made].scripts.PreClick), "1 0 0 0 false true true nil",
        "one secure button, never touched in a fight, still UIParent's after every placing; its OnClick still the"
            .. " template's, no PreClick; no addon code opened Edit Mode or a panel; no errors")
    _G.CreateFrame = create
    Proto.GetFrameLevel, Proto.SetFrameLevel, Proto.EnableMouse, Proto.Raise = flatLevel, nil, nil, nil
    Proto.IsMouseMotionFocus = nil
end

-- Kept over a reload; anything invalid reads as the default.
local saved = ForeverEnhancedCooldownManagerDB
Environment(true)
BlizzardFrames()
ns = LoadAll(saved)
Equal(tostring(ns.Get("pullTimer")) .. " " .. ns.Get("pullNumbers") .. " " .. ns.Get("warningFont") .. " " .. ns.Get("emoteColour")
    .. " " .. ns.Get("bossColour"), "true white skurri purple green", "choices kept over a reload")
Equal(S[Boss2TargetFrameSpellBar.Border].alpha, 0, "and Blizzard's boss bars restyled again after it")
saved.pullNumbers, saved.warningOutline, saved.emoteColour, saved.bossColour = "pink", 3, "charcoal", "white"
Equal(ns.Get("pullNumbers") .. " " .. ns.Get("warningOutline") .. " " .. ns.Get("emoteColour") .. " " .. ns.Get("bossColour"),
    "gold outline default default", "anything else is ignored: text colours and bar colours stay apart")
Equal(ns.Get("pullBarSize") .. " " .. ns.Get("pullNumberSize") .. " " .. ns.Get("warningSize") .. " " .. ns.Get("emoteSize") .. " "
    .. ns.Get("raidSize"), "120 200 150 60 110", "sizes kept over a reload")
saved.pullBarSize, saved.pullNumberSize, saved.warningSize, saved.emoteSize, saved.raidSize = 400, 20, "big", true, 200
Equal(ns.Get("pullBarSize") .. " " .. ns.Get("pullNumberSize") .. " " .. ns.Get("warningSize") .. " " .. ns.Get("emoteSize") .. " "
    .. ns.Get("raidSize"), "100 100 100 100 100", "sizes out of their limits read as 100")

-- EraUI's Classic cast bars on: the boss bars are EraUI's, and the page says so.
Environment()
BlizzardFrames()
EraUI(true)
plainFill = rawget(Boss1TargetFrameSpellBar, "UpdateBarFillTexture")
ns = LoadAll({ bossCasts = true })
ns.ShowWindow()
FECMFrame:Select("raid")
page = FECMFrame.pages.raid
Equal(tostring(page.bossTick.checked) .. " " .. S[page.boss].alpha .. " " .. S[Boss1TargetFrameSpellBar.Border].alpha .. " "
    .. tostring(rawget(Boss1TargetFrameSpellBar, "UpdateBarFillTexture") == plainFill),
    "true 0.35 1 true", "ticked, but EraUI's: Blizzard's boss bars untouched and unhooked, the preview dimmed")
Equal(S[page.bossNote].text:find("EraUI's Cast Bars", 1, true) ~= nil and S[page.bossNote].colour[1], 1,
    "and the note says why, in the warning colour")
Equal(S[page.bossNote].text:find("or for a newer EraUI", 1, true) ~= nil, true, "and that a newer EraUI hands them over")
Equal(S[page.status].text, "Blizzard's countdown, raid warnings and boss casts, in your look. Tick one to start.",
    "none of the three showing your look")
-- Off in EraUI: the addon's.
Environment()
BlizzardFrames()
EraUI(false)
ns = LoadAll({ bossCasts = true })
Equal(S[Boss1TargetFrameSpellBar.Border].alpha, 0, "EraUI's Cast Bars off: the addon restyles them")

-- A current EraUI, its Cast Bars on: it shares the boss bars at its login,
-- so the switch decides, live, and the page says the bars take your look
-- instead of EraUI's.
local function SharingEraUI()
    EraUI(true)
    local heard = {}
    local watch = CreateFrame("Frame")
    watch:RegisterEvent("PLAYER_LOGIN")
    watch:SetScript("OnEvent", function()
        ForeverEnhancedCooldownManagerAPI.ShareBossCastBars("EraUI", function()
            heard[#heard + 1] = ForeverEnhancedCooldownManagerAPI.StylesBossCastBars()
        end)
    end)
    return heard
end
Environment()
BlizzardFrames()
local heard = SharingEraUI()
ns = LoadAll({ bossCasts = false })
ns.ShowWindow()
FECMFrame:Select("raid")
page = FECMFrame.pages.raid
Equal(S[page.bossNote].text, "While this is on, they take your look instead of EraUI's. In a fight the game keeps each cast secret, so the bar keeps one colour.",
    "a sharing EraUI: the note says the boss bars take your look instead of EraUI's")
Equal(S[page.bossNote].colour[1] .. " " .. S[page.boss].alpha .. " " .. S[Boss1TargetFrameSpellBar.Border].alpha .. " " .. #heard,
    string.format("%g", ns.Theme.MUTED[1]) .. " 0.35 1 0", "not a warning; off: the preview dimmed, Blizzard's bars and EraUI left alone")
page.bossTick:Click()
Equal(S[page.boss].alpha .. " " .. S[Boss1TargetFrameSpellBar.Border].alpha .. " " .. Last(Boss3TargetFrameSpellBar.Text, "SetFontObject")
    .. " " .. #heard .. " " .. tostring(heard[1]), "1 0 FECMFont10 1 true",
    "ticked with EraUI's Cast Bars on: the boss bars in your look at once, EraUI told first")
Equal(S[page.status].text, "Your look on 1 of 3. The previews show your choices.", "counted as showing your look")
page.bossTick:Click()
Equal(S[page.boss].alpha .. " " .. S[Boss1TargetFrameSpellBar.Border].alpha .. " " .. #heard .. " " .. tostring(heard[2]),
    "0.35 1 2 false", "unticked: Blizzard's look back and handed to EraUI at once, no reload")
Equal(S[page.bossNote].text:find("\226\128\148", 1, true), nil, "no em dash in the note")
Equal(#printed, 0, "no errors")

-- What's new's tour: three steps for this page, of 1.4.1, the update after
-- 1.4.0. They open the page and point: at the preview and its switches, at
-- All sizes, then at the Edit Mode button. The box never covers what a step
-- asks you to use. Places are from the page's top left, y down. Run as
-- 1.4.1, so steps from later updates (those still waiting for their number
-- too) stay out, as they did in that release.
local function Released(version)
    _G.C_AddOns = { GetAddOnMetadata = function() return version end }
end
do
    Environment()
    BlizzardFrames()
    Released("1.4.1")
    ns = LoadAll({ useBars = true, notesSeen = "1.3.0" })
    local Tour = ns.Tour
    local function Titles(list)
        local titles = {}
        for _, step in ipairs(list) do titles[#titles + 1] = step.title end
        return table.concat(titles, ", ")
    end
    -- One version for all three, newer than 1.4.0: 1.4.1's.
    local function Versions(list)
        local same, newer = true, true
        for _, step in ipairs(list) do
            same = same and step.version == list[1].version
            newer = newer and ns.CompareVersions(step.version, "1.4.0") == 1
        end
        return tostring(same) .. " " .. tostring(newer)
    end
    local RAID = "Raid Timers, Sizes, Edit Mode"
    local menu = Tour:News("0.9.0")[1]
    Equal(menu.title .. ": " .. menu.text(), "The menu: Everything is in this list: your four bars at the top, then Look, Layout,"
        .. " Cast bar and General, and Raid Timers under More.", "the full tour's first step points out Raid Timers under More")
    local added = Tour:News("1.2.0")
    Equal(Titles(added) .. " | " .. Versions(added), RAID .. " | true true",
        "after 1.2.0: three steps for Raid Timers, one version newer than 1.4.0 (Unreleased until the release numbers them)")
    Equal(Titles(Tour:News("1.3.0")) .. " | " .. Titles(Tour:News("1.4.0")) .. " | " .. Titles(Tour:News(nil)),
        RAID .. " | " .. RAID .. " | " .. RAID, "after 1.3.0 or 1.4.0 the same three, and by hand too: the newest there are")
    -- Short and plain: no em dashes, no longer than the basics' steps, and
    -- Edit Mode opened by its button, never typed.
    local basics = 0
    for _, step in ipairs(Tour:News("0.9.0")) do
        local text = type(step.text) == "function" and step.text() or step.text
        if step.version == "1.0.0" then basics = math.max(basics, #text) end
    end
    for _, step in ipairs(added) do
        local all = step.title .. " " .. step.text .. " " .. (step.try or "") .. " " .. (step.alreadyText or "")
        Equal(tostring(all:find("\226\128\148", 1, true)) .. " " .. tostring(basics > 0 and #step.text <= basics) .. " "
            .. tostring(all:lower():find("/editmode", 1, true)), "nil true nil",
            step.title .. ": no em dash, no longer than the basics' steps, no /editmode to type")
    end
    -- How many of the phrases the text has.
    local function Has(text, ...)
        local found = 0
        for _, phrase in ipairs({ ... }) do
            if text:find(phrase, 1, true) then found = found + 1 end
        end
        return found
    end
    Equal(Has(added[1].text, "pull countdown", "raid warnings", "boss emotes", "boss cast bars") .. " "
        .. Has(added[1].text, "in raids and dungeons", "Each part is off until you tick it."),
        "4 2", "the first names all four parts, where they work and that each is off until ticked")
    -- Only the countdown, raid warnings and emotes have sizes (R:Scale): the
    -- boss cast bars keep Blizzard's, and the step says so.
    Equal(Has(added[2].text, "countdown", "raid warnings", "emotes", "All sizes", "Boss cast bars keep Blizzard's size.") .. " "
        .. tostring(added[2].text:lower():find("each part", 1, true)) .. " " .. tostring(added[2].text:find("Edit Mode", 1, true)),
        "5 nil nil", "the second names the three parts with sizes and All sizes, and says the boss cast bars keep Blizzard's size")
    Equal(Has(added[3].text, "Edit Mode button", "Boss Frames", "boss fight") .. " " .. tostring(added[3].try),
        "3 nil", "the third: the Edit Mode button and Boss Frames, no Try it (Edit Mode closes the window)")

    -- After an update from 1.3.0: What's new offers them.
    for _, timer in ipairs(timers) do timer() end
    local notes = FECMNotes
    Equal(tostring(S[notes].shown) .. " " .. tostring(notes.seen) .. " " .. tostring(S[notes.tour].shown), "true 1.3.0 true",
        "What's new after an update from 1.3.0 offers Show me what's new")
    notes.tour:Click()
    local w, box = FECMFrame, FECMTour
    local raid = w.pages.raid
    Equal(tostring(S[notes].shown) .. " " .. S[box.count].text .. " " .. w.selected .. " " .. S[box.title].text .. " "
        .. tostring(S[w.nav.raid.fill].shown), "false 1 of 3 raid RAID TIMERS true",
        "it closes What's new and opens More > Raid Timers on the first step")

    -- Where things are on the page.
    local tray, options = S[raid.tray], S[raid.options]
    local x0, trayTop = tray.points[1][2], -tray.points[1][3]
    local optionsTop = trayTop + tray.height - options.points[1][5]
    local right = x0 + options.width
    local FOOTER = 489 -- the page's height, down to the window's footer
    local OUTLINE = 4 -- how far outside its part the tour's outline sits
    -- left, top, width, height of something on the options, by its one anchor
    local function On(obj)
        local at = S[obj].points[1]
        local width, height = S[obj].width, S[obj].height
        if obj.box and obj.text then width, height = 18 + #S[obj.text].text * 6, 16 end -- a tick: its box and label
        return { x0 + at[2], optionsTop - at[3], width, height }
    end
    local function Overlap(a, b)
        return a[1] < b[1] + b[3] and b[1] < a[1] + a[3] and a[2] < b[2] + b[4] and b[2] < a[2] + a[4]
    end
    local function Inside(a, b)
        return a[1] >= b[1] and a[2] >= b[2] and a[1] + a[3] <= b[1] + b[3] and a[2] + a[4] <= b[2] + b[4]
    end
    local function Grow(rect, by)
        return { rect[1] - by, rect[2] - by, rect[3] + 2 * by, rect[4] + 2 * by }
    end
    -- How many of the rects a rect overlaps.
    local function Covers(rect, list)
        local count = 0
        for _, other in ipairs(list) do
            if Overlap(rect, other) then count = count + 1 end
        end
        return count
    end
    local pullTick, warningTick, bossTick = On(raid.pullTick), On(raid.warningTick), On(raid.bossTick)
    local edit = S[raid.editMode]
    Equal(edit.points[1][1] .. " " .. tostring(edit.points[1][2] == raid.bossTick) .. " " .. edit.points[1][3] .. " " .. edit.points[1][4],
        "LEFT true RIGHT 10", "the Edit Mode button right of the boss cast bars' tick")
    local editRect = { bossTick[1] + bossTick[3] + 10, bossTick[2] + bossTick[4] / 2 - edit.height / 2, edit.width, edit.height }
    local sizes = raid.sizes
    local sizeRects = { On(sizes[1]), On(sizes[2]), On(sizes[3]), On(sizes[4]), On(sizes[5]) }
    local noteRect = On(raid.bossNote)
    noteRect[4] = raid.bossNote:GetStringHeight() -- text: as tall as its lines
    -- The box: its size as the tour fitted it round its text, hanging from its anchor.
    local function Box(anchorRight, anchorBottom)
        local p = S[box].points[1]
        return { anchorRight + p[4] - S[box].width, anchorBottom - p[5], S[box].width, S[box].height }
    end

    -- The first step: the preview and the two ticks along its foot as one part.
    local top, o, p = S[raid.top].points, S[box.outline].points, S[box].points[1]
    Equal(top[1][1] .. " " .. tostring(top[1][2] == raid.tray) .. " " .. top[1][3] .. " | " .. top[2][1] .. " "
        .. tostring(top[2][2] == raid.options) .. " " .. top[2][3] .. " " .. top[2][4] .. " " .. top[2][5] .. " | "
        .. tostring(S[raid.top].parent == raid) .. " " .. tostring(Last(raid.top, "EnableMouse")),
        "TOPLEFT true TOPLEFT | BOTTOMRIGHT true TOPRIGHT 0 -20 | true nil",
        "one part from the preview's top left to the foot of the tick row, the page's own (not the options'), taking no clicks")
    local part = { x0, trayTop, right + top[2][4] - x0, optionsTop - top[2][5] - trayTop }
    Equal(tostring(Inside(pullTick, part)) .. " " .. tostring(Inside(warningTick, part)) .. " " .. tostring(Overlap(bossTick, part)),
        "true true false", "round the countdown's and the raid warnings' ticks; the boss cast bars' tick is further down")
    Equal(tostring(o[1][2] == raid.top and o[2][2] == raid.top) .. " " .. tostring(S[box.outline].shown) .. " " .. p[1] .. " "
        .. tostring(p[2] == raid.top) .. " " .. p[3] .. " " .. S[box.arrow].points[1][3],
        "true true TOPRIGHT true BOTTOMRIGHT TOPRIGHT", "outlining it, the box under its right end, its arrow at that end")
    local first = Box(part[1] + part[3], part[2] + part[4])
    Equal(tostring(first[1] >= x0 + 312) .. " " .. tostring(first[1] + first[3] <= right) .. " "
        .. tostring(first[2] + first[4] <= FOOTER) .. " " .. tostring(p[5] + S[box.arrow].height < o[2][5]),
        "true true true true", "the box in the raid warnings' column, inside the page, its arrow's tip just under the outline")
    Equal(tostring(Overlap(first, pullTick)) .. " " .. tostring(Overlap(first, warningTick)) .. " " .. tostring(Overlap(first, bossTick))
        .. " " .. tostring(Overlap(first, editRect)), "false false false false",
        "clear of all three ticks and the Edit Mode button")
    Equal(S[box.text].text:find("Try it: tick one and watch the preview.", 1, true) ~= nil and not S[box.back].shown, true,
        "asking you to tick one and watch the preview, with no Back on the first step")
    raid.pullTick:Click()
    S[box].scripts.OnUpdate(box, 1)
    Equal(tostring(ns.Get("pullTimer")) .. " " .. S[raid.pull].alpha .. " " .. S[box.title].text, "true 1 RAID TIMERS",
        "ticked: its preview lights up, and the step stays so it can be seen")
    w:Select("look")
    Equal(tostring(S[box].shown) .. " " .. tostring(S[box.outline].shown), "true false", "on another page the outline hides, the box stays")

    -- The second step: All sizes alone, back on the page.
    box.next:Click()
    local allSizes = sizes[#sizes]
    o, p = S[box.outline].points, S[box].points[1]
    Equal(S[box.count].text .. " " .. w.selected .. " " .. S[box.title].text .. " " .. S[box.next.label].text .. " " .. tostring(S[box.back].shown),
        "2 of 3 raid SIZES Next true", "then the sizes")
    Equal(tostring(o[1][2] == allSizes) .. " " .. tostring(o[2][2] == allSizes) .. " " .. p[1] .. " " .. tostring(p[2] == allSizes)
        .. " " .. p[3] .. " " .. S[box.arrow].points[1][3], "true true TOPRIGHT true BOTTOMRIGHT TOPRIGHT",
        "outlining All sizes alone, the box under it at its right end")
    -- The outline round All sizes touches nothing else: not the other sizes,
    -- the Edit Mode button or the boss note's text.
    local ring = Grow(sizeRects[5], OUTLINE)
    Equal(Covers(ring, { sizeRects[1], sizeRects[2], sizeRects[3], sizeRects[4], editRect, bossTick, noteRect }) .. " "
        .. noteRect[4], "0 36", "the outline crosses no other size, no button and no line of the boss note (3 lines here)")
    local second = Box(sizeRects[5][1] + sizeRects[5][3], sizeRects[5][2] + sizeRects[5][4])
    Equal(Covers(second, sizeRects) .. " " .. Covers(second, { editRect, bossTick }), "0 0",
        "the box on none of the five sizes, the Edit Mode button or the boss cast bars' tick")
    Equal(tostring(second[2] >= trayTop + tray.height) .. " " .. tostring(second[1] >= x0 + 312) .. " "
        .. tostring(second[1] + second[3] <= right) .. " " .. (second[2] + second[4]) .. " " .. tostring(second[2] + second[4] <= FOOTER),
        "true true true 486 true", "the preview in sight above, the box in the right column inside the page, ending above the footer")
    -- With no In the game lines under the options, the box sits on nothing
    -- at all: no piece of the options, nothing of the page's own.
    do
        local Rect = Placer(raid)
        local list = {}
        for _, obj in ipairs(objects) do
            local parent = S[obj].parent
            if S[obj].shown and (parent == raid.options or parent == raid)
                and obj ~= raid.options and obj ~= raid.tray and obj ~= raid.top then
                list[#list + 1] = { Rect(obj) }
            end
        end
        Equal(#list .. " " .. Covers(second, list), "51 0", "the sizes box on none of the 49 pieces of the options, the title or its status")
    end
    Equal(tostring(sizes[1].usable) .. " " .. tostring(sizes[3].usable), "true false",
        "the countdown's sizes work now it's ticked; the raid warnings' still wait for theirs")

    -- The third step: the Edit Mode button, the last.
    box.next:Click()
    o, p = S[box.outline].points, S[box].points[1]
    local arrow = S[box.arrow].points[1]
    Equal(S[box.count].text .. " " .. w.selected .. " " .. S[box.title].text .. " " .. S[box.next.label].text .. " " .. tostring(S[box.back].shown)
        .. " " .. tostring(S[box.text].text == added[3].text), "3 of 3 raid EDIT MODE Done true true",
        "then the Edit Mode button, the last step, with no Try it line")
    Equal(tostring(o[1][2] == raid.editMode) .. " " .. tostring(o[2][2] == raid.editMode) .. " " .. p[1] .. " "
        .. tostring(p[2] == raid.editMode) .. " " .. p[3] .. " " .. p[4] .. " " .. p[5] .. " " .. arrow[1] .. " " .. arrow[3],
        "true true TOPLEFT true BOTTOMLEFT 0 -14 BOTTOM TOPLEFT", "outlining the button, the box under it from its left, its arrow up at it")
    ring = Grow(editRect, OUTLINE)
    local third = { editRect[1] + p[4], editRect[2] + editRect[4] - p[5], S[box].width, S[box].height }
    Equal(Covers(ring, { bossTick, sizeRects[1], sizeRects[2], sizeRects[3], sizeRects[4], sizeRects[5], noteRect }) .. " "
        .. Covers(third, { editRect, bossTick }) .. " " .. tostring(third[1] >= x0) .. " " .. tostring(third[1] + third[3] <= right) .. " "
        .. ("%g"):format(third[2] + third[4]) .. " " .. tostring(third[2] + third[4] <= FOOTER),
        "0 0 true true 429 true", "the outline on nothing else, the box clear of the button and the tick, inside the page")
    box.back:Click()
    Equal(S[box.title].text, "SIZES", "Back: the sizes again")
    box.back:Click()
    Equal(S[box.title].text .. " " .. tostring(S[box.text].text:find("Already on: the preview shows your look.", 1, true) ~= nil),
        "RAID TIMERS true", "and the first step, now saying one is on")
    box.next:Click()
    box.next:Click()
    box.next:Click()
    Equal(tostring(S[box].shown) .. " " .. tostring(S[w].shown) .. " " .. S[w.note].text,
        "false true That's what's new. See it again any time from What's new, or with /ccm new.",
        "Done ends it, leaving the window open and saying where it is")
    Equal(tostring(ns.Get("raidWarnings")) .. " " .. tostring(ns.Get("bossCasts")) .. " " .. ns.Get("pullBarSize") .. " "
        .. ns.Get("raidSize"), "false false 100 100", "the tour only changed what you did yourself")

    -- By hand: the same three. The full tour is still the nine basics.
    SlashCmdList.FECM("new")
    notes.tour:Click()
    Equal(S[box.count].text .. " " .. w.selected .. " " .. S[box.title].text, "1 of 3 raid RAID TIMERS", "/fecm new tours them again")
    box.skip:Click()
    SlashCmdList.FECM("tour")
    Equal(S[box.count].text .. " " .. S[box.title].text, "1 of 9 THE MENU", "the full tour is still the nine basics")
    box.skip:Click()
    Equal(#printed, 0, "no errors")
end

-- Before a full restart the new files aren't loaded: no More heading, no page.
-- As 1.4.1 again, the update that brought them.
Environment()
BlizzardFrames()
Released("1.4.1")
ns = LoadAll(nil, { "Core.lua", "Style.lua", "Skin.lua", "Resource.lua", "CastBar.lua", "Ranks.lua", "Spells.lua",
    "Keybinds.lua", "Buffs.lua", "IconAuras.lua", "Bars.lua", "Layout.lua", "Theme.lua", "BarPage.lua", "LayoutPage.lua", "CastBarPage.lua",
    "ProfileMenu.lua", "Window.lua", "Tour.lua", "MinimapButton.lua", "Notes.lua" })
ns.ShowWindow()
Equal(tostring(FECMFrame.nav.raid) .. " " .. tostring(FECMFrame.moreHeading) .. " " .. tostring(FECMFrame.pages.raid), "nil nil nil",
    "without the new files: the list as before")
-- And What's new leaves out the Raid Timers steps: after an update there's
-- nothing new it can show, so no button; by hand, the last steps that can.
do
    local byHand = ns.Tour:News(nil)
    Equal(#ns.Tour:News("1.3.0") .. " " .. #byHand .. " " .. byHand[1].version .. " " .. byHand[#byHand].version, "0 4 1.2.0 1.2.0",
        "without them: nothing after 1.3.0, and by hand 1.2.0's four steps")
    ns.ShowNotes("1.3.0")
    Equal(tostring(S[FECMNotes].shown) .. " " .. tostring(S[FECMNotes.tour].shown), "true false",
        "What's new after an update from 1.3.0, with no Show me what's new")
    FECMNotes:Hide()
    SlashCmdList.FECM("new")
    Equal(tostring(S[FECMNotes.tour].shown), "true", "opened by hand, it offers the last steps that can show")
    FECMNotes.tour:Click()
    Equal(S[FECMTour.count].text .. " " .. FECMFrame.selected .. " " .. S[FECMTour.title].text, "1 of 4 cd HEALTHSTONES AND POTIONS",
        "and never opens a page that isn't there")
    FECMTour.skip:Click()
end
Equal(#printed, 0, "no errors")

print = _G.print
Equal(SecretMisuse[1], nil, "no secret misused anywhere")
io.write("Raid Timers checks passed: " .. checks .. " assertions.\n")
