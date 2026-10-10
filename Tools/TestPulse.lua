-- Run the actual addon files against a mock game for the Cooldown pulse:
-- its page in the /ccm window under More, after Raid Timers, its choices
-- and live preview, its two styles (Quick and Long, each with its own size,
-- time and sound, picked on each row), which cooldowns it lists (every
-- spell you know with a cooldown of its own, from the game data, to tick;
-- your items, to untick), how it hands the game's duration objects to
-- Cooldown frames of its own without ever reading them, the pulse itself
-- (its fade, growth, queue and sound), moving it, that everything on its
-- page fits, and its settings over a reload. The mock game is a copy of
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

-- Cooldown pulse: the game around it ---------------------------------------------------------
-- Stand-ins for what the window's other pages need (Raid Timers' previews
-- run none of Blizzard's code), the game's sounds, a screen, and cooldowns
-- the addon may hand on but never read.

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
    _G.C_AddOns, _G.EraUI = nil, nil
end

-- A cooldown's duration object, as the game hands it over: secret in a
-- fight, so the addon may pass it on but never look inside.
local sealed = setmetatable({}, {
    __index = function() error("the pulse read a cooldown's duration", 2) end,
    __newindex = function() error("the pulse wrote on a cooldown's duration", 2) end,
})
-- Sounds played, the spells whose cooldowns were asked for, and spells
-- whose cooldown is on hold (it starts once their effect is used up).
local sounds, asked, held = {}, {}, {}
-- Like the game: clearing a cooldown is counted, as well as noted, and
-- the game may answer it with the done script.
function Proto:Clear()
    local s = S[self]
    s.clears = (s.clears or 0) + 1
    s.last.Clear = table.pack()
    if s.scripts.OnCooldownDone then s.scripts.OnCooldownDone(self) end
end

local function PulseGame()
    sounds, asked, held = {}, {}, {}
    _G.PlaySound = function(kit, channel) sounds[#sounds + 1] = kit .. " " .. tostring(channel) end
    _G.C_Spell.GetSpellCooldownDuration = function(id, ignoreGCD)
        assert(ignoreGCD == true, "global cooldown must be ignored")
        asked[#asked + 1] = id
        return sealed
    end
    -- Like the game: the times secret in a fight, whether it's on hold never.
    _G.C_Spell.GetSpellCooldown = function(id)
        return { isEnabled = not held[id], startTime = SECRET, duration = SECRET, modRate = SECRET }
    end
    _G.GetSpellBaseCooldown = nil
    -- A trinket with a use: Lucky Charm.
    local itemSpell = C_Item.GetItemSpell
    C_Item.GetItemSpell = function(id) if id == 9999 then return "Lucky", 1 end return itemSpell(id) end
    -- A druid with a few long cooldowns: Barkskin and Bash (a minute each),
    -- and Walk on Air, a racial (two minutes).
    table.insert(book[2].items, { name = "Barkskin", spellID = 22812, iconID = 136097 })
    table.insert(book[2].items, { name = "Bash", subName = "Rank 1", spellID = 5211, iconID = 132114 })
    S[UIParent].width, S[UIParent].height = 1366, 768
    -- Each frame's template, noted.
    local create = _G.CreateFrame
    _G.CreateFrame = function(kind, name, parent, template)
        local made = create(kind, name, parent, template)
        S[made].template = template
        return made
    end
end

-- Every file in the order the .toc loads them (Tools/TestRules.mjs checks the .toc).
local FILES = { "Core.lua", "Style.lua", "Skin.lua", "Resource.lua", "CastBar.lua", "RaidTimers.lua", "Ranks.lua", "Spells.lua",
    "Keybinds.lua", "Buffs.lua", "IconAuras.lua", "Bars.lua", "Pulse.lua", "Layout.lua", "Theme.lua", "BarPage.lua",
    "LayoutPage.lua", "CastBarPage.lua", "RaidTimersPage.lua", "PulsePage.lua", "ProfileShare.lua", "ProfileMenu.lua", "Window.lua",
    "Tour.lua", "MinimapButton.lua", "Notes.lua", "Debug.lua" }
local function LoadAll(saved)
    local ns = {}
    _G.ForeverEnhancedCooldownManagerDB = saved
    for _, file in ipairs(FILES) do assert(loadfile(file))("ForeverEnhancedCooldownManager", ns) end
    Fire("ADDON_LOADED", "ForeverEnhancedCooldownManager")
    Fire("PLAYER_LOGIN")
    Fire("PLAYER_ENTERING_WORLD")
    return ns
end

-- The next frame: what the pulse's events asked for is done now, once.
local function Tick(P)
    local driver = P.driver
    local work = S[driver].scripts.OnUpdate
    if work then work(driver, 0) end
end
-- The next frame for the timers queued after from (the bars and the window
-- redrawn once after a spellbook change): each runs now, once.
local function Later(from)
    for i = from + 1, #timers do timers[i]() end
end
-- Time passing on the pulse while it shows.
local function Run(P, seconds)
    local frame = P.frame
    if S[frame].shown then S[frame].scripts.OnUpdate(frame, seconds) end
end
-- Every pulse showing and waiting played out.
local function Finish(P)
    local frame = P.frame
    while frame and S[frame].shown do S[frame].scripts.OnUpdate(frame, 5) end
end
-- The game says a cooldown frame is done.
local function Done(cooldown)
    S[cooldown].scripts.OnCooldownDone(cooldown)
end
-- The page's list as text: headers, then each row ticked or not, its name,
-- its cooldown and its style.
local function Rows(page)
    local out = {}
    for _, row in ipairs(page.rows) do
        if S[row].shown then
            if S[row.header].shown then
                out[#out + 1] = S[row.header].text
            else
                out[#out + 1] = (row.check.checked and "[x] " or "[ ] ") .. S[row.name].text .. " " .. S[row.long].text .. " "
                    .. (row.style.selected == "long" and "Long" or "Quick")
            end
        end
    end
    return table.concat(out, " | ")
end
-- A cooldown's row on the page, by its key.
local function RowFor(page, key)
    for _, row in ipairs(page.rows) do
        if row.key == key and S[row].shown then return row end
    end
end
-- Clicks a row's Quick or Long.
local function Switch(row, style)
    row.style.buttons[style == "long" and 2 or 1]:Click()
end
-- The sliders showing, each with its value.
local function Sliders(page)
    local out = {}
    for _, slider in ipairs(page.sliders) do
        if S[slider].shown then out[#out + 1] = S[slider.label].text .. " " .. S[slider.value].text end
    end
    return table.concat(out, ", ")
end
-- A control's note, as the footer shows it.
local function Note(control)
    local hint = control.hint
    if type(hint) == "function" then hint = hint(control) end
    return hint
end
-- One of the pulse's saved lists: its keys, in order.
-- One of the pulse's lists in this character's profile, as saved.
local function Profile(list)
    local db = ForeverEnhancedCooldownManagerDB
    local profile = type(db.profiles) == "table" and type(db.chars) == "table" and db.profiles[db.chars[UnitGUID("player")]]
    return profile and profile[list]
end
local function Saved(list)
    local keys = {}
    for key in pairs(Profile(list) or {}) do keys[#keys + 1] = tostring(key) end
    table.sort(keys)
    return table.concat(keys, ",")
end
-- What's showing now, and in which style.
local function Now(P)
    local key, _, style = P:Showing()
    return tostring(key) .. " " .. tostring(style)
end

-- The window: Cooldown pulse under More, after Raid Timers ----------------------------------

Environment()
BlizzardFrames()
PulseGame()
-- Every name the addon puts in the game's global space as it first loads
-- and its window opens, for the check beside Forever Enhanced Cooldown
-- Pulse near the end. A global: the main chunk is near Lua's limit of 200 locals.
ADDED_GLOBALS = {}
setmetatable(_G, { __newindex = function(globals, name, value)
    if value ~= nil then ADDED_GLOBALS[#ADDED_GLOBALS + 1] = tostring(name) end
    rawset(globals, name, value)
end })
local ns = LoadAll(nil)
local P = ns.Pulse
Tick(P)
ns.ShowWindow()
setmetatable(_G, nil)
local w = FECMFrame
local page = w.pages.pulse
do
    local function Top(item) return -S[item].points[1][3] end
    Equal(S[w.nav.pulse.label].text, "Cooldown pulse", "Cooldown pulse in the window's list")
    Equal(Top(w.nav.raid) .. " " .. Top(w.nav.pulse), "390 422", "under More, right after Raid Timers")
    local news = S[w.news].points[1]
    Equal(Top(w.nav.pulse) + S[w.nav.pulse].height <= 489 - news[3] - S[w.news].height, true,
        "clear of the What's new button at the foot of the list")
    Equal(w.nav.pulse.hint, "A big icon in the middle of your screen when a cooldown is ready.", "it says what it's for on hover")
    w.nav.pulse:Click()
    Equal(tostring(S[page].shown) .. " " .. tostring(S[w.pages.raid].shown) .. " " .. tostring(S[w.nav.pulse.fill].shown),
        "true false true", "clicked: its page, and it's the one highlighted")
end

-- Off by default, with the approved defaults (seen working in game, so no Needs testing) -------

do
    Equal(tostring(ns.Get("pulse")) .. " " .. tostring(page.master.checked), "false false", "off by default")
    Equal(S[page.master.text].text, "Pulse an icon when a cooldown is ready", "no Needs testing: the user tested it in game")
    local widths = {}
    for _, slider in ipairs(page.sliders) do widths[#widths + 1] = S[slider.value].width end
    Equal(table.concat(widths, " "), "28 28 36 36 36 36", "room for 160% and 2.5s beside each track")
    Equal(page.edit.selected .. " | " .. Sliders(page), "quick | Size 272, Shows for 1.0s, See-through 80%, Grows to 135%",
        "Edit starts on Quick, at the approved defaults: Quick's size and time, then the look both styles share")
    Equal(tostring(S[page.slider.pulseLongSize].shown) .. " " .. tostring(S[page.slider.pulseLongTime].shown), "false false",
        "Long's own hidden meanwhile")
    Equal(ns.Get("pulseLongSize") .. " " .. ns.Get("pulseLongTime") .. " " .. ns.Get("pulseLongSound") .. " | "
        .. table.concat(ns.PULSE_LONG_TIME, " ") .. " | " .. table.concat(ns.PULSE_TIME, " "), "400 25 none | 3 50 25 | 3 20 10",
        "Long: bigger, 2.5 s and silent to start, up to 5 s (Quick up to 2 s)")
    Equal(page.border.selected .. " " .. page.sound.selected .. " " .. S[page.sound.name].text .. " " .. tostring(page.shadow.checked) .. " "
        .. tostring(page.items.checked) .. " " .. tostring(page.volume.checked), "thin none None true true false",
        "a thin border and a shadow, no sound, trinkets and potions too, at the Sound Effects volume")
    Equal(S[page.previewButton.label].text, "Preview Quick", "Preview says which style it plays")
    Equal(ns.Get("pulseX") .. " " .. ns.Get("pulseY") .. " | " .. S[page.where].text, "0 0 | In the middle of your screen.",
        "in the middle of the screen")
    Equal(S[page.status].text, "Off. Tick the box below to start.", "the title row says how to start")
    Equal(select(1, P:Watchers()) .. " " .. tostring(P.holder) .. " " .. #asked, "0 nil 0", "off: nothing watched, nothing asked of the game")
    Equal(Rows(page), "SPELLS | [ ] Barkskin 1 min Quick | [ ] Bash 1 min Quick | [ ] Overpower 5s Quick | [ ] Walk on Air 2 min Quick",
        "every spell you know with a cooldown of its own, by name, each unticked and Quick, with its cooldown; Moonfire and Attack (none) left out")
    Equal(tostring(page.add) .. " " .. tostring(page.slider.pulseMin) .. " " .. tostring(ns.Get("pulseMin")) .. " " .. tostring(P.Add),
        "nil nil nil nil", "no Cooldowns from slider, and no box to add a spell by name")
    Equal(S[page.about].text, "tick the ones you want to pulse, then pick Quick or Long for each", "the list says what to do")
    local controls = { page.master, page.previewButton, page.move, page.reset, page.shadow, page.items, page.volume }
    for _, pills in ipairs({ page.edit, page.sound, page.border }) do
        for _, button in ipairs(pills.buttons) do controls[#controls + 1] = button end
    end
    for _, slider in ipairs(page.sliders) do controls[#controls + 1] = slider end
    local plain = 0
    for _, control in ipairs(controls) do
        local hint = Note(control)
        if type(hint) == "string" and #hint > 10 and hint:find("\226\128\148") == nil then plain = plain + 1 end
    end
    Equal(plain .. "/" .. #controls, "21/21", "every control says what it does on hover, no dashes")
    -- See-through: 80% leaves a tenth (the user's pick, once the far end),
    -- and past it, fainter still.
    local shown = {}
    for _, see in ipairs({ 0, 40, 80, 85, 90 }) do
        ns.Set("pulseSeeThrough", see)
        shown[#shown + 1] = string.format("%.3f", P:Opacity())
    end
    Equal(table.concat(shown, " "), "1.000 0.550 0.100 0.070 0.040", "see-through: 80% leaves a tenth, then fainter to 90%")
    -- The checks below were measured at the first build's look.
    for key, value in pairs({ pulseSize = 320, pulseTime = 7, pulseSeeThrough = 30, pulseGrow = 120 }) do ns.Set(key, value) end
end

-- On, then ticked: a Cooldown frame of its own for each, handed the game's duration ---------

page.master:Click()
do
    Equal(tostring(ns.Get("pulse")) .. " " .. select(1, P:Watchers()) .. " " .. #asked .. " | " .. S[page.status].text,
        "true 0 0 | Nothing to pulse yet: tick some below.", "on with nothing ticked: nothing watched or asked, and the title row says what to do")
    Equal(Note(RowFor(page, "Barkskin").check), "Tick to pulse when Barkskin is ready.", "a row says what ticking does")
    for _, key in ipairs({ "Barkskin", "Bash", "Walk on Air" }) do RowFor(page, key).check:Click() end
    Equal(Saved("pulsePick") .. " | " .. S[page.status].text, "Barkskin,Bash,Walk on Air | 3 cooldowns pulse when they're ready.",
        "three ticked: saved by name, and counted")
    Equal(Rows(page), "SPELLS | [x] Barkskin 1 min Quick | [x] Bash 1 min Quick | [ ] Overpower 5s Quick | [x] Walk on Air 2 min Quick",
        "ticked on the page")
    Equal(S[RowFor(page, "Overpower").style].alpha .. " " .. S[RowFor(page, "Bash").style].alpha, "1 1",
        "every row's switch at full strength, ticked or not: it can be set first")
    Equal(Note(RowFor(page, "Overpower").style.buttons[1]), "Once ticked, Overpower pulses Quick. Each style has its own size, time"
        .. " and sound, set under Edit above.", "an unticked row's switch says it pulses once ticked")
    Equal(Note(RowFor(page, "Overpower").style.buttons[2]), "Once ticked, Overpower pulses Quick. Click for Long. Each style has its"
        .. " own size, time and sound, set under Edit above.", "and Long says what clicking it does")
end
local count, watchers = P:Watchers()
do
    Equal(count, 3, "ticked: three cooldowns watched")
    local holder = P.holder
    Equal(tostring(S[holder].parent) .. " " .. S[holder].width .. "x" .. S[holder].height .. " "
        .. tostring(Last(holder, "EnableMouse")) .. " " .. tostring(holder:IsVisible()), "nil 1x1 false true",
        "the watchers sit on a shown frame of their own (not hidden with the interface), one unit square, with no mouse")
    local keys = {}
    for key, watch in pairs(watchers) do
        keys[#keys + 1] = key
        local cd = watch.cooldown
        Equal(S[cd].kind .. " " .. S[cd].template .. " " .. tostring(S[cd].parent == holder) .. " " .. tostring(Last(cd, "SetDrawSwipe"))
            .. tostring(Last(cd, "SetDrawEdge")) .. tostring(Last(cd, "SetDrawBling")) .. " "
            .. tostring(Last(cd, "SetHideCountdownNumbers")) .. " " .. tostring(Last(cd, "EnableMouse")),
            "Cooldown CooldownFrameTemplate true falsefalsefalse true false",
            key .. ": Blizzard's Cooldown frame, as on your bars, that draws nothing and takes no mouse")
        Equal(Last(cd, "SetCooldownFromDurationObject") == sealed, true, key .. ": handed the game's duration as it is")
    end
    table.sort(keys)
    local seen, ids = {}, {}
    for _, id in ipairs(asked) do
        if not seen[id] then seen[id], ids[#ids + 1] = true, id end
    end
    table.sort(ids)
    Equal(table.concat(keys, ",") .. " | " .. table.concat(ids, ","), "Barkskin,Bash,Walk on Air | 5211,22812,1259416",
        "each ticked one asked for, without the global cooldown; Overpower, unticked, never")
    -- Cooldowns change: each is asked again, once, on the next frame.
    asked = {}
    Fire("SPELL_UPDATE_COOLDOWN")
    Fire("SPELL_UPDATE_COOLDOWN")
    Equal(#asked, 0, "nothing asked until the next frame")
    Tick(P)
    Equal(#asked, 3, "then each watched spell once, however many events")
    -- In a fight the same, the duration never read.
    lockdown = true
    Fire("SPELL_UPDATE_COOLDOWN")
    Tick(P)
    Equal(#asked, 6, "in a fight too")
    -- On hold (like Presence of Mind still up): it hasn't started, so it's
    -- cleared, its duration not even asked for, until it starts.
    local bark = watchers.Barkskin.cooldown
    local clears = S[bark].clears or 0
    S[bark].last.SetCooldownFromDurationObject = nil
    held[22812], asked = true, {}
    Fire("SPELL_UPDATE_COOLDOWN")
    Tick(P)
    table.sort(asked)
    Equal(table.concat(asked, ",") .. " " .. ((S[bark].clears or 0) - clears) .. " "
        .. tostring(Last(bark, "SetCooldownFromDurationObject")) .. " " .. tostring(P:Showing()), "5211,1259416 1 nil nil",
        "Barkskin's cooldown on hold, in a fight: cleared, never counted from the cast, and no pulse for the clear")
    held[22812] = nil
    Fire("SPELL_UPDATE_COOLDOWN")
    Tick(P)
    Equal(Last(bark, "SetCooldownFromDurationObject") == sealed, true, "once it starts: handed on")
    lockdown = false
end

-- A cooldown done: its icon pulses ---------------------------------------------------------------

local frame
do
    clock = clock + 5 -- past the quiet after logging in
    local barkskin = watchers.Barkskin.cooldown
    Done(barkskin)
    frame = P.frame
    Equal(Now(P), "Barkskin quick", "Barkskin is ready: it pulses, Quick")
    Equal(tostring(S[frame].shown) .. " " .. tostring(S[frame].parent == UIParent) .. " " .. Last(frame, "SetFrameStrata")
        .. " " .. tostring(Last(frame, "EnableMouse")) .. " " .. tostring(Last(frame.art, "EnableMouse")), "true true HIGH false false",
        "a plain frame of the addon's own, high up, that never takes the mouse")
    local at = S[frame].points[1]
    Equal(S[frame].width .. " " .. table.concat({ at[1], tostring(at[2] == UIParent), at[3], at[4], at[5] }, " "),
        "320 CENTER true CENTER 0 0", "320 big, in the middle of the screen")
    Equal(S[frame.art.texture].texture .. " " .. tostring(S[frame].alpha == 0), "136097 true", "Barkskin's icon, starting unseen")
    local function Look() return string.format("%.3f %.1f", S[frame].alpha, S[frame.art].width) end
    Run(P, .0525)
    Equal(Look(), "0.331 329.2", "fading in fast: half way in after 0.05 s, already growing")
    Run(P, .1575)
    Equal(Look(), "0.663 352.6", "held at full, 30% see-through")
    Run(P, .28)
    Equal(Look(), "0.361 378.2", "fading out, still growing")
    Run(P, .25)
    Equal(tostring(S[frame].shown) .. " " .. tostring(P:Showing()), "false nil", "gone after 0.7 s")
    -- Told twice: once only.
    Done(barkskin)
    Equal(tostring(P:Showing()), "nil", "Barkskin done again within 3 seconds is the same one: no second pulse")
    clock = clock + 3
    Done(barkskin)
    Equal(P:Showing(), "Barkskin", "three seconds on, it can pulse again")
    Finish(P)
    -- Just after a loading screen, a login or a reload: no pulses for two seconds.
    Fire("PLAYER_ENTERING_WORLD")
    Tick(P)
    local bash = watchers.Bash.cooldown
    clock = clock + 1.5
    Done(bash)
    Equal(tostring(P:Showing()), "nil", "just after a loading screen: no pulse")
    clock = clock + 1
    Done(bash)
    Equal(P:Showing(), "Bash", "two seconds on, it pulses")
    Finish(P)
    -- With the interface hidden (Alt+Z), none.
    clock = clock + 5
    S[UIParent].shown = false
    Done(watchers["Walk on Air"].cooldown)
    S[UIParent].shown = true
    Equal(tostring(P:Showing()), "nil", "the interface hidden: no pulse")
    Equal(#sounds, 0, "no sound chosen, none played")
    -- Hidden mid-pulse with the interface (Alt+Z, a cinematic), as the game
    -- hides it: what showed and waited is let go, not played late.
    for _, key in ipairs({ "h1", "h2", "h3" }) do P:Queue(1, key) end
    S[frame].scripts.OnHide(frame)
    local key, waiting = P:Showing()
    Equal(tostring(key) .. " " .. waiting .. " " .. tostring(S[frame].shown), "nil 0 false",
        "the interface hidden mid-pulse: nothing left showing or waiting")
    Equal(tostring(P:Queue(1, "after")) .. " " .. P:Showing(), "true after", "and the next pulse shows as usual")
    Finish(P)
end

-- Several at once: one after another, never a flood --------------------------------------------

do
    local took = {}
    for _, key in ipairs({ "a", "b", "c", "d", "e", "b" }) do took[#took + 1] = tostring(P:Queue(1, key)) end
    Equal(table.concat(took, " "), "true true true true false false",
        "one shows and three wait; any more are let go, and one already waiting isn't added again")
    local order = {}
    for _ = 1, 5 do
        order[#order + 1] = tostring(P:Showing())
        Run(P, 1)
    end
    Equal(table.concat(order, " "), "a b c d nil", "one after another, each in full, never stacked")
    Equal(tostring(P:Queue(1, "a")), "true", "and once played out, room again")
    Finish(P)
end

-- Sound, border and shadow ------------------------------------------------------------------------

do
    page.sound.buttons[3]:Click()
    Equal(ns.Get("pulseSound") .. " " .. S[page.sound.name].text .. " " .. table.concat(sounds, ","), "chime Chime 316447 SFX",
        "the next arrow: Chime, and it plays")
    P:Queue(1, "x")
    Equal(#sounds .. " " .. sounds[#sounds], "2 316447 SFX", "and each pulse plays it")
    Finish(P)
    page.sound.buttons[3]:Click()
    Equal(sounds[#sounds], "316493 SFX", "Bell")
    local count = #sounds
    page.sound.buttons[2]:Click()
    Equal((#sounds - count) .. " " .. sounds[#sounds] .. " " .. ns.Get("pulseSound"), "1 316493 SFX bell", "its name plays it again, still Bell")
    -- Play at Master volume: the same sound, on the game's Master channel.
    page.volume:Click()
    page.sound.buttons[2]:Click()
    Equal(tostring(ns.Get("pulseMaster")) .. " " .. sounds[#sounds], "true 316493 Master", "Play at Master volume: played on Master")
    page.volume:Click()
    page.sound.buttons[2]:Click()
    Equal(tostring(ns.Get("pulseMaster")) .. " " .. sounds[#sounds], "false 316493 SFX", "unticked: Sound Effects again")
    -- Round the list both ways.
    page.sound.buttons[1]:Click()
    page.sound.buttons[1]:Click()
    Equal(ns.Get("pulseSound"), "none", "the back arrow: Chime, then None")
    count = #sounds
    page.sound.buttons[2]:Click()
    Equal(#sounds - count, 0, "None plays nothing")
    page.sound.buttons[1]:Click()
    Equal(ns.Get("pulseSound") .. " " .. S[page.sound.name].text, "anvil Anvil", "back from None: round to the last")
    page.sound.buttons[3]:Click()
    Equal(ns.Get("pulseSound"), "none", "and on from the last: None")
    local missing, kits = {}, {}
    for _, key in ipairs(ns.PULSE_SOUND_KEYS) do
        local kit = P.SOUNDS[key]
        if key ~= "none" and not (kit and ns.PULSE_SOUND_NAMES[key] and not kits[kit]) then missing[#missing + 1] = key end
        if kit then kits[kit] = true end
    end
    Equal(#ns.PULSE_SOUND_KEYS .. " [" .. table.concat(missing, ",") .. "]", "16 []", "None and 15 sounds, each its own, with a name")
    local heard = #sounds
    P:Queue(1, "y")
    Finish(P)
    Equal(#sounds .. " " .. ns.Get("pulseLongSound"), heard .. " none", "None: silent; and all of it Quick's, Long's sound untouched")

    local art = frame.art
    local function Ring(ring) return tostring(S[ring[1]].shown) .. " " .. S[ring[1]].height end
    P:Queue(1, "look")
    Equal(Ring(art.border) .. " " .. Last(art.border[1], "SetColorTexture", 4) .. " | " .. Ring(art.shadow[1]) .. " "
        .. Ring(art.shadow[4]) .. " " .. S[art.shadow[4][1]].points[1][5] .. " " .. Last(art.shadow[1][1], "SetColorTexture", 4),
        "true 2 1 | true 5 true 5 17 0.55", "at 320: a thin dark border 2 thick, then a soft shadow of four rings 5 thick, fading out")
    Finish(P)
    page.border.buttons[3]:Click()
    page.shadow:Click()
    P:Queue(1, "look 2")
    Equal(Ring(art.border) .. " | " .. tostring(S[art.shadow[1][1]].shown), "true 5 | false", "Thick, and Shadow unticked")
    Finish(P)
    page.border.buttons[1]:Click()
    P:Queue(1, "look 3")
    Equal(tostring(S[art.border[1]].shown), "false", "None: no border")
    Finish(P)
    page.border.buttons[2]:Click()
    page.shadow:Click()
    Equal(ns.Get("pulseBorder") .. " " .. tostring(ns.Get("pulseShadow")), "thin true", "back to thin with a shadow")
end

-- Two styles: Quick or Long, picked on each row ------------------------------------------------

do
    local bark = RowFor(page, "Barkskin")
    Equal(S[bark.style.buttons[1].label].text .. " " .. S[bark.style.buttons[2].label].text .. " " .. bark.style.selected .. " "
        .. S[bark.style].width .. " " .. table.concat(S[bark.style].points[1], " "), "Quick Long quick 96 RIGHT -4 0",
        "each row has a small Quick | Long switch on its right, on Quick to start")
    Equal(Note(bark.style.buttons[1]) .. " | " .. Note(bark.style.buttons[2]), "Barkskin pulses Quick. Each style has its own size,"
        .. " time and sound, set under Edit above. | Barkskin pulses Quick. Click for Long. Each style has its own size, time and"
        .. " sound, set under Edit above.", "it says what it is on hover, and what Long does")
    Switch(bark, "long")
    Equal(Note(bark.style.buttons[1]):sub(1, 39), "Barkskin pulses Long. Click for Quick. ", "switched: says Long, and Quick goes back")
    Equal(Saved("pulseStyle") .. " " .. Profile("pulseStyle").Barkskin .. " | " .. Rows(page),
        "Barkskin long | SPELLS | [x] Barkskin 1 min Long | [x] Bash 1 min Quick | [ ] Overpower 5s Quick | [x] Walk on Air 2 min Quick",
        "switched to Long: saved, the rest stay Quick")
    Equal(select(1, P:Watchers()), 3, "the same three watched")
    -- Its pulse: Long's own size, time and sound.
    clock = clock + 5
    local heard = #sounds
    Done(watchers.Barkskin.cooldown)
    Equal(Now(P) .. " " .. S[frame].width .. " " .. (#sounds - heard), "Barkskin long 400 0",
        "Barkskin pulses Long: 400 big, with Long's sound (none yet)")
    Run(P, .1875)
    Equal(string.format("%.3f %.0f", S[frame].alpha, S[frame.art].width), "0.331 412",
        "fading in over Long's time: half way in after 0.19 s, growing as Quick's do")
    Run(P, 2.2)
    Equal(tostring(S[frame].shown), "true", "still there at 2.4 s")
    Run(P, .2)
    Equal(Now(P), "nil nil", "gone after 2.5 s")
    -- Quick as it was.
    Done(watchers.Bash.cooldown)
    Equal(Now(P) .. " " .. S[frame].width, "Bash quick 320", "Bash still pulses Quick, 320 big")
    Run(P, .65)
    Equal(tostring(S[frame].shown), "true", "for Quick's time")
    Run(P, .1)
    Equal(Now(P), "nil nil", "gone after 0.7 s, as before")

    -- Edit: Long. The page shows and sets Long's own.
    page.edit.buttons[2]:Click()
    Equal(P.editing .. " " .. page.edit.selected .. " | " .. Sliders(page) .. " | " .. page.sound.selected .. " | "
        .. S[page.previewButton.label].text, "long long | Size 400, Shows for 2.5s, See-through 30%, Grows to 120% | none | Preview Long",
        "Edit: Long. Long's own size, time and sound, then the shared look")
    page.slider.pulseLongSize:Choose(448)
    page.slider.pulseLongTime:Choose(40)
    page.sound.buttons[3]:Click()
    page.sound.buttons[3]:Click()
    Equal(ns.Get("pulseLongSize") .. " " .. ns.Get("pulseLongTime") .. " " .. ns.Get("pulseLongSound") .. " " .. sounds[#sounds] .. " | "
        .. ns.Get("pulseSize") .. " " .. ns.Get("pulseTime") .. " " .. ns.Get("pulseSound"), "448 40 bell 316493 SFX | 320 7 none",
        "Long's size, time and sound set (Bell played as picked); Quick's unchanged")
    Equal(Note(page.sound.buttons[1]), "A sound with each Long pulse. The arrows step through them and play each one; click its name to"
        .. " hear it again.",
        "the sound says which style it's for")
    -- Preview plays Long.
    heard = #sounds
    page.previewButton:Click()
    Equal(Now(P) .. " " .. S[frame].width .. " " .. (#sounds - heard) .. " " .. sounds[#sounds], "preview long 448 1 316493 SFX",
        "Preview: a Long pulse, its size and bell")
    Run(P, 3.9)
    Equal(tostring(S[frame].shown), "true", "for Long's 4 s")
    Finish(P)
    -- And in play.
    clock = clock + 5
    Done(watchers.Barkskin.cooldown)
    Equal(Now(P) .. " " .. S[frame].width .. " " .. sounds[#sounds], "Barkskin long 448 316493 SFX", "Barkskin: Long's new size and sound")
    Finish(P)
    -- Edit: Quick again, and Preview plays Quick.
    page.edit.buttons[1]:Click()
    heard = #sounds
    page.previewButton:Click()
    Equal(P.editing .. " " .. Sliders(page) .. " | " .. page.sound.selected .. " | " .. Now(P) .. " " .. S[frame].width .. " "
        .. (#sounds - heard), "quick Size 320, Shows for 0.7s, See-through 30%, Grows to 120% | none | preview quick 320 0",
        "Edit: Quick. Its own again, and Preview plays Quick, silent")
    -- Edit switched while a preview shows: the new Preview takes its place at once.
    page.edit.buttons[2]:Click()
    heard = #sounds
    page.previewButton:Click()
    Equal(Now(P) .. " " .. S[frame].width .. " " .. select(2, P:Showing()) .. " " .. (#sounds - heard), "preview long 448 0 1",
        "Preview Quick showing, Edit: Long, Preview: Long at once, with its bell, nothing left waiting")
    page.edit.buttons[1]:Click()
    page.previewButton:Click()
    Equal(Now(P) .. " " .. S[frame].width .. " " .. select(2, P:Showing()), "preview quick 320 0", "and the other way round")
    Equal(tostring(P:Preview()) .. " " .. Now(P), "false preview quick", "the same style again: the one showing carries on")
    -- One waiting behind a pulse plays the style being edited when its turn comes.
    Finish(P)
    clock = clock + 5
    Done(watchers.Bash.cooldown)
    page.previewButton:Click()
    page.edit.buttons[2]:Click()
    page.previewButton:Click()
    Equal(Now(P) .. " " .. select(2, P:Showing()), "Bash quick 1", "behind Bash's pulse: one preview waits")
    Run(P, .75)
    Equal(Now(P) .. " " .. S[frame].width, "preview long 448", "and plays Long, as Edit now shows")
    page.edit.buttons[1]:Click()
    Finish(P)
    Switch(RowFor(page, "Barkskin"), "quick")
    Equal(tostring(Profile("pulseStyle").Barkskin) .. " " .. RowFor(page, "Barkskin").style.selected, "nil quick",
        "back to Quick: nothing saved")
end

-- Trinkets and potions -------------------------------------------------------------------------------

do
    trinket = 9999
    Fire("PLAYER_EQUIPMENT_CHANGED")
    Tick(P)
    ns.Bars:Assign("family:healing", "cd")
    P:Apply()
    w:Refresh()
    Equal(tostring(watchers["slot:13"]) .. " " .. tostring(watchers["family:healing"]) .. " | " .. Rows(page),
        "nil nil | SPELLS | [x] Barkskin 1 min Quick | [x] Bash 1 min Quick | [ ] Overpower 5s Quick | [x] Walk on Air 2 min Quick"
        .. " | ITEMS | [ ] Trinket 1: Lucky Charm trinket Quick | [ ] Healing Potions on your bars Quick",
        "a trinket with a use put on, and a potion on your Cooldowns bar: listed under Items, unticked to start, so not watched")
    RowFor(page, "slot:13").check:Click()
    RowFor(page, "family:healing").check:Click()
    Equal(tostring(watchers["slot:13"] ~= nil) .. " " .. tostring(watchers["family:healing"] ~= nil) .. " " .. Saved("pulsePick"),
        "true true Barkskin,Bash,Walk on Air,family:healing,slot:13", "ticked: watched, saved with the spells")
    Equal(S[page.status].text, "5 cooldowns pulse when they're ready.", "counted")
    -- Plain numbers: a cooldown running is handed on; one only as long as
    -- the global cooldown is cleared, never counted.
    trinketCooldown, itemCooldown = { 50, 120, 1 }, { 100, 1.5, 1 }
    Fire("BAG_UPDATE_COOLDOWN")
    Tick(P)
    local trinketCd, potionCd = watchers["slot:13"].cooldown, watchers["family:healing"].cooldown
    Equal(tostring(Last(trinketCd, "SetCooldown", 1)) .. " " .. tostring(Last(trinketCd, "SetCooldown", 2)), "50 120",
        "the trinket's cooldown handed on")
    Equal(tostring(Last(potionCd, "SetCooldown")) .. " " .. tostring((S[potionCd].clears or 0) > 0) .. " " .. tostring(P:Showing()),
        "nil true nil", "the global cooldown alone: cleared, and no pulse for it")
    -- Hidden in a fight: the watcher keeps what it had.
    lockdown = true
    trinketCooldown = { SECRET, SECRET, 1 }
    S[trinketCd].last.SetCooldown = nil
    local clears = S[trinketCd].clears or 0
    Fire("BAG_UPDATE_COOLDOWN")
    Tick(P)
    Equal(tostring(Last(trinketCd, "SetCooldown")) .. " " .. ((S[trinketCd].clears or 0) - clears), "nil 0",
        "secret numbers: left as they were")
    lockdown = false
    trinketCooldown = { 0, 0, 1 }
    clock = clock + 5
    itemCount[118] = 2
    Done(potionCd)
    Equal(P:Showing() .. " " .. S[frame.art.texture].texture, "family:healing 888", "a potion ready pulses its own icon")
    Finish(P)
    -- An item can be Long too.
    Switch(RowFor(page, "family:healing"), "long")
    clock = clock + 5
    Done(potionCd)
    Equal(Now(P) .. " " .. Profile("pulseStyle")["family:healing"], "family:healing long long",
        "Healing Potions switched to Long: pulse Long")
    Finish(P)
    -- On hold (not enabled: 0, or false as C_Item says it), as Blizzard's
    -- own read it: not started, so not counted.
    for _, enable in ipairs({ 0, false }) do
        itemCooldown = { 100, 120, enable }
        S[potionCd].last.SetCooldown = nil
        Fire("BAG_UPDATE_COOLDOWN")
        Tick(P)
        Equal(tostring(Last(potionCd, "SetCooldown")), "nil", "a cooldown on hold (" .. tostring(enable) .. "): not counted")
    end
    itemCooldown = { 100, 120, true }
    Fire("BAG_UPDATE_COOLDOWN")
    Tick(P)
    Equal(tostring(Last(potionCd, "SetCooldown", 2)), "120", "enabled (true from C_Item): counted")
    -- Your last one drunk: none left to drink, so no pulse (as your bars hide it).
    itemCount[118] = 0
    clock = clock + 5
    Done(potionCd)
    Equal(tostring(P:Showing()), "nil", "a potion you carry none of now: no pulse")
    -- Healing and Mana Potions share one cooldown: one pulse, not two, in
    -- the style of the one that tells first.
    itemCount[118], itemCount[2455] = 1, 1
    ns.Bars:Assign("family:mana", "cd")
    ns.SetPulsePick("family:mana", true)
    P:Apply()
    itemCooldown = { 200, 120, true }
    Fire("BAG_UPDATE_COOLDOWN")
    Tick(P)
    clock = clock + 5
    Done(potionCd)
    Done(watchers["family:mana"].cooldown)
    local key, waiting, style = P:Showing()
    Equal(key .. " " .. waiting .. " " .. style, "cd:200:120 0 long", "potions sharing a cooldown: one pulse, the second let go")
    Finish(P)
    Switch(RowFor(page, "family:healing"), "quick")
    ns.Bars:Assign("family:mana", nil)
    ns.SetPulsePick("family:mana", false)
    P:Apply()
    Equal(tostring(watchers["family:mana"]) .. " " .. Saved("pulseStyle"), "nil ", "Mana Potions off the bar: not watched; nothing Long")
    -- Straight from your bags, no bar needed (the user: some want a potion
    -- only as a pulse): Mana Potions, still carried, and a bag item with a use.
    bagItems[1] = { itemID = 6948, hyperlink = "|cffffffff|Hitem:6948::|h[Hearthstone]|h|r", iconFileID = 134414 }
    itemCount[6948] = 1
    local bagSpell = C_Item.GetItemSpell
    C_Item.GetItemSpell = function(id) if id == 6948 then return "Hearthstone", 8690 end return bagSpell(id) end
    ns.Spells:Scan()
    w:Refresh()
    Equal(Rows(page):match("ITEMS.*"), "ITEMS | [x] Trinket 1: Lucky Charm trinket Quick | [x] Healing Potions on your bars Quick"
        .. " | [ ] Mana Potions in your bags Quick | [ ] Hearthstone in your bags Quick",
        "potions you carry and bag items with a use, listed from your bags, unticked")
    -- Items listed from your bags aren't seen pulsing in game yet: their
    -- ticks say so. Trinkets and items on your bars have been.
    do
        local trinketRow, barRow = RowFor(page, "slot:13"), RowFor(page, "family:healing")
        trinketRow.check:SetChecked(false)
        barRow.check:SetChecked(false)
        Equal(Note(RowFor(page, "item:6948").check) .. " | " .. Note(RowFor(page, "family:mana").check) .. " | "
            .. Note(trinketRow.check) .. " | " .. Note(barRow.check),
            "Tick to pulse when Hearthstone is ready. (Needs testing) | Tick to pulse when Mana Potions is ready. (Needs testing)"
            .. " | Tick to pulse when Trinket 1: Lucky Charm is ready. | Tick to pulse when Healing Potions is ready.",
            "items from your bags say Needs testing on their ticks, trinkets and items on your bars don't")
        trinketRow.check:SetChecked(true)
        barRow.check:SetChecked(true)
    end
    RowFor(page, "item:6948").check:Click()
    Equal(tostring(watchers["item:6948"] ~= nil) .. " " .. tostring(Profile("pulsePick")["item:6948"]), "true true", "ticked: watched")
    -- Run out of it: gone. Carrying it again, with /ccm shut: read again, watched again.
    bagItems[1], itemCount[6948] = nil, 0
    ns.Spells:Scan()
    P:Apply()
    Equal(tostring(watchers["item:6948"]), "nil", "none left: not watched")
    w:Hide()
    -- A count the game keeps secret is never compared: not read again yet.
    itemCount[6948] = SECRET
    Fire("BAG_UPDATE_DELAYED")
    Tick(P)
    Equal(tostring(watchers["item:6948"]), "nil", "a count the game keeps secret: never compared, not read again")
    bagItems[1], itemCount[6948] = { itemID = 6948, hyperlink = "|cffffffff|Hitem:6948::|h[Hearthstone]|h|r", iconFileID = 134414 }, 1
    Fire("BAG_UPDATE_DELAYED")
    Tick(P)
    Equal(tostring(watchers["item:6948"] ~= nil), "true", "back in your bags: watched again, the window shut")
    -- Run out of again with /ccm shut: kept (only your bags changed), and no
    -- pulse for it. Then the list read again without it (your bars laid out
    -- again, by a change to one): no longer listed, it's asked about by its
    -- own ID, and still says nothing. As in Forever Enhanced Cooldown Pulse.
    do
        bagItems[1], itemCount[6948] = nil, 0
        Fire("BAG_UPDATE_DELAYED")
        Tick(P)
        local kept = watchers["item:6948"]
        clock = clock + 5
        Done(kept.cooldown)
        local before = tostring(P:Showing())
        ns.Bars:Rebuild()
        clock = clock + 5
        Done(kept.cooldown)
        Equal(before .. " | " .. tostring(kept == watchers["item:6948"]) .. " " .. tostring(ns.Spells:Find("item:6948")) .. " "
            .. tostring(P:Showing()), "nil | true nil nil",
            "run out of, /ccm shut: no pulse; the list read again without it: still watched, no longer listed, and still no pulse")
        bagItems[1], itemCount[6948] = { itemID = 6948, hyperlink = "|cffffffff|Hitem:6948::|h[Hearthstone]|h|r", iconFileID = 134414 }, 1
        Fire("BAG_UPDATE_DELAYED")
        Tick(P)
    end
    w:Show()
    RowFor(page, "item:6948").check:Click()
    bagItems[1], itemCount[6948] = nil, 0
    C_Item.GetItemSpell = bagSpell
    ns.Spells:Scan()
    P:Apply()
    w:Refresh()
    page.items:Click()
    Equal(tostring(watchers["slot:13"]) .. " " .. tostring(watchers["family:healing"]) .. " | " .. Rows(page),
        "nil nil | SPELLS | [x] Barkskin 1 min Quick | [x] Bash 1 min Quick | [ ] Overpower 5s Quick | [x] Walk on Air 2 min Quick",
        "Trinkets and potions too unticked: spells only")
    page.items:Click()
end

-- Ticking and unticking ------------------------------------------------------------------------------

do
    local bashRow = RowFor(page, "Bash")
    local reach = Last(bashRow.check, "SetHitRectInsets", 2)
    Equal(reach .. " " .. tostring(4 + 16 - reach < S[bashRow].width - 4 - S[bashRow.style].width), "-448 true",
        "the whole row clicks its tick, up to its switch")
    Equal(Note(bashRow.check), "Untick to leave Bash out.", "and says what unticking does")
    local old = watchers.Bash.cooldown
    bashRow.check:Click()
    Equal(tostring(Profile("pulsePick").Bash) .. " " .. tostring(watchers.Bash) .. " "
        .. tostring(old.watch) .. " " .. tostring(bashRow.check.checked) .. " " .. S[bashRow.style].alpha, "nil nil nil false 1",
        "unticked: forgotten, its watcher let go, its switch still full strength")
    Equal(S[page.status].text, "4 cooldowns pulse when they're ready.", "one fewer")
    Equal(Note(bashRow.check), "Tick to pulse when Bash is ready.", "ticking says it puts it back")
    clock = clock + 5
    Done(old)
    Equal(tostring(P:Showing()), "nil", "a watcher let go says nothing")
    bashRow.check:Click()
    Equal(tostring(Profile("pulsePick").Bash) .. " " .. tostring(watchers.Bash ~= nil), "true true", "ticked again: back")
    -- An item unticked: left out until it's ticked again.
    local potionRow = RowFor(page, "family:healing")
    potionRow.check:Click()
    Equal(Saved("pulsePick") .. " " .. tostring(watchers["family:healing"]), "Barkskin,Bash,Walk on Air,slot:13 nil",
        "an item unticked: left out, as a spell is")
    potionRow.check:Click()
    Equal(Saved("pulsePick") .. " " .. tostring(watchers["family:healing"] ~= nil), "Barkskin,Bash,Walk on Air,family:healing,slot:13 true",
        "ticked again: back")
    -- Nothing ticked: the title row says what to do.
    page.items:Click()
    for _, key in ipairs({ "Barkskin", "Bash", "Walk on Air" }) do RowFor(page, key).check:Click() end
    Equal(select(1, P:Watchers()) .. " " .. S[page.status].text .. " " .. tostring(S[page.empty].shown), "0 Nothing to pulse yet: tick some below. false",
        "nothing ticked: nothing watched, and the title row says so")
    for _, key in ipairs({ "Barkskin", "Bash", "Walk on Air" }) do RowFor(page, key).check:Click() end
    page.items:Click()
    Equal(select(1, P:Watchers()), 5, "all back")
end

-- Moving it ---------------------------------------------------------------------------------------------

do
    page.move:Click()
    local mover = P.mover
    Equal(tostring(P:Moving()) .. " " .. tostring(S[w].shown), "true false", "Move: the box shows and the window steps aside")
    Equal(S[mover].width .. " " .. Last(mover, "SetFrameStrata") .. " " .. tostring(Last(mover, "EnableMouse")) .. " "
        .. tostring(Last(mover, "SetClampedToScreen")) .. " " .. tostring(Last(mover, "RegisterForDrag")),
        "320 DIALOG true true LeftButton", "Quick's size, draggable, kept on the screen")
    Equal(S[mover.icon].texture .. " " .. S[mover.title].text .. " " .. S[mover.done.label].text, "136097 COOLDOWN PULSE Done",
        "your first cooldown's icon in it, named, with Done")
    -- Dragged so its middle is 100 right of the screen's and 50 down (the screen's middle is at 500, 400).
    S[mover].cx, S[mover].cy = 600, 350
    S[mover].scripts.OnDragStart(mover)
    S[mover].scripts.OnDragStop(mover)
    local at = S[mover].points[1]
    Equal(ns.Get("pulseX") .. " " .. ns.Get("pulseY") .. " | " .. table.concat({ at[1], tostring(at[2] == UIParent), at[3], at[4], at[5] }, " "),
        "100 -50 | CENTER true CENTER 100 -50", "let go: saved from the middle of the screen")
    Equal(tostring(Last(mover, "SetUserPlaced")) .. " " .. tostring(mover.dragging), "false nil",
        "kept out of the game's own layout, as your bars are")
    clock = clock + 5
    P:Queue(1, "moved")
    Equal(S[frame].points[1][4] .. " " .. S[frame].points[1][5], "100 -50", "the pulse shows there")
    Finish(P)
    P:Queue(1, "moved long", nil, "long")
    Equal(S[frame].width .. " " .. S[frame].points[1][4] .. " " .. S[frame].points[1][5], "448 100 -50", "a Long pulse too")
    Finish(P)
    mover.done:Click()
    Equal(tostring(P:Moving()) .. " " .. tostring(S[w].shown) .. " " .. w.selected, "false true pulse",
        "Done: the box goes, and the window comes back on this page")
    -- With Long picked under Edit, the box is Long's size.
    page.edit.buttons[2]:Click()
    page.move:Click()
    Equal(S[mover].width, 448, "with Long picked under Edit: a box Long's size")
    mover.done:Click()
    page.edit.buttons[1]:Click()
    page.move:Click()
    S[mover].scripts.OnMouseUp(mover, "LeftButton")
    Equal(tostring(P:Moving()), "true", "a left click is only a drag")
    S[mover].scripts.OnMouseUp(mover, "RightButton")
    Equal(tostring(P:Moving()) .. " " .. tostring(S[w].shown) .. " " .. tostring(ns.Get("pulseX")), "false true 100",
        "a right-click finishes too, where it was put")
    Equal(S[page.where].text, "Moved 100 right and 50 down from the middle.", "the page says where, in plain words")
    local spot = S[page.spotBox].points[1]
    Equal(string.format("%.1f %.1f %.1f", S[page.spotBox].width, spot[4], spot[5]), "27.5 8.6 -4.3",
        "the small screen shows it there, to scale")
    page.reset:Click()
    Equal(ns.Get("pulseX") .. " " .. ns.Get("pulseY") .. " | " .. S[page.where].text .. " | " .. S[w.note].text,
        "0 0 | In the middle of your screen. | The pulse is back in the middle of your screen.", "Reset: the middle again")
    -- Not in a fight, and a fight ends a move.
    lockdown = true
    page.move:Click()
    Equal(tostring(P:Moving()) .. " " .. S[w.note].text, "false Finish the fight first, then move it.", "in a fight: not now, and why")
    lockdown = false
    page.move:Click()
    Fire("PLAYER_REGEN_DISABLED")
    Equal(tostring(P:Moving()) .. " " .. ns.Get("pulseX"), "false 0", "a fight starting puts the box away")
    Fire("PLAYER_REGEN_ENABLED")
    -- Mid-drag: the box can't hear the mouse let go once hidden, so where it
    -- is now is kept (50 left of the middle and 100 up).
    page.move:Click()
    S[mover].cx, S[mover].cy = 450, 500
    S[mover].scripts.OnDragStart(mover)
    S[mover].last.SetUserPlaced = nil
    Fire("PLAYER_REGEN_DISABLED")
    Equal(tostring(P:Moving()) .. " " .. ns.Get("pulseX") .. " " .. ns.Get("pulseY") .. " " .. tostring(Last(mover, "SetUserPlaced"))
        .. " " .. tostring(mover.dragging), "false -50 100 false nil", "a fight starting mid-drag: the box goes, where it was put kept")
    Fire("PLAYER_REGEN_ENABLED")
    ns.ShowWindow()
    w:Select("pulse")
    Equal(S[page.where].text, "Moved 50 left and 100 up from the middle.", "the page says so")
    page.reset:Click()
    -- Only one way: just that.
    ns.Set("pulseY", -40)
    w:Refresh()
    Equal(S[page.where].text, "Moved 40 down from the middle.", "one way only")
    page.reset:Click()
end

-- The live preview, and Preview ---------------------------------------------------------------------

do
    Equal(S[page.screen].width .. "x" .. S[page.screen].height .. " " .. S[page.spotBox].width, "117x66 27.5",
        "a small screen the shape of yours, the pulse on it to scale")
    -- A very wide screen (32:9): only as wide as its room, clear of UP CLOSE.
    S[UIParent].width = 2732
    w:Refresh()
    Equal(S[page.screen].width .. "x" .. S[page.screen].height .. " " .. string.format("%.1f", S[page.spotBox].width), "172x48 20.1",
        "a very wide screen: no wider than its room, the pulse still to scale")
    S[UIParent].width = 1366
    w:Refresh()
    Equal(S[page.sample.texture].texture .. " " .. S[page.spot.texture].texture, "136097 136097", "your first cooldown's icon")
    local tray = page.tray
    S[tray].scripts.OnUpdate(tray, .0525)
    Equal(string.format("%.3f %.1f %.2f", S[page.sample].alpha, S[page.sample].width, S[page.spot].width), "0.331 41.2 28.29",
        "both pulse as the real one does")
    S[tray].scripts.OnUpdate(tray, 1)
    Equal(S[page.sample].alpha, 0, "then rest a moment before the next")
    Equal(S[page.sample.border[1]].height .. " " .. tostring(S[page.sample.shadow[1][1]].shown), "1 true",
        "with your border and shadow, made small")
    page.slider.pulseSeeThrough:Choose(60)
    S[tray].scripts.OnUpdate(tray, .3) -- 1.3 s a round: half way in again
    Equal(string.format("%.3f", S[page.sample].alpha), "0.163", "more see-through at once")
    page.slider.pulseSeeThrough:Choose(30)
    -- With Long picked under Edit: Long's size on the small screen, and its
    -- time (4 s and a rest a round: 4.9 s in is half way in again).
    page.edit.buttons[2]:Click()
    S[tray].scripts.OnUpdate(tray, 3.5475)
    Equal(string.format("%.1f %.3f %.1f", S[page.spotBox].width, S[page.sample].alpha, S[page.sample].width), "38.5 0.331 41.2",
        "with Long picked: Long's size on the small screen, and its time")
    page.edit.buttons[1]:Click()
    S[tray].scripts.OnUpdate(tray, 0)
    Equal(string.format("%.1f %.3f", S[page.spotBox].width, S[page.sample].alpha), "27.5 0.000", "Quick's again: resting at 4.9 s")

    page.master:Click()
    Equal(select(1, P:Watchers()) .. " " .. tostring(watchers.Barkskin), "0 nil", "off: nothing watched")
    page.previewButton:Click()
    Equal(P:Showing() .. " " .. Last(frame, "SetFrameStrata") .. " " .. S[frame.art.texture].texture, "preview TOOLTIP 136097",
        "Preview: a pulse now, over the window, with your first cooldown's icon, even while it's off")
    Finish(P)
    page.master:Click()
end

-- Everything fits: each label clear of its control, nothing on anything else ------------------------
-- Text in the game runs about seven units a letter in the window's usual
-- font (measured on a screenshot of the first build: "Cooldowns fro" took
-- about 90, so its label ran into a track 100 along). Counted at 7.5 here,
-- 6.5 in the small font, and more for capitals, to be sure.

local function Wide(text, font)
    text = tostring(text or "")
    local small = type(font) == "string" and font:find("Small") ~= nil
    local capitals = text:find("%a") ~= nil and text == text:upper()
    local each = small and (capitals and 7.5 or 6.5) or (capitals and 9 or 7.5)
    return #text * each
end
do
    -- Where things are on the page: every place worked out from the anchors
    -- it set, each frame at its size, text as wide as Wide says, a tick its
    -- box and label. Rect gives left, top, width and height from the page's
    -- top left, y down.
    local function Size(obj)
        local s = S[obj]
        if s.kind == "FontString" then
            if s.width > 0 then return s.width, 12 end
            return Wide(s.text, s.template), 12
        end
        if obj.box and obj.text then return 18 + Wide(S[obj.text].text, S[obj.text].template), 16 end
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
        local p = s.points[1]
        local point, relative, relativePoint, x, y = p[1], s.parent, p[1], p[2] or 0, p[3] or 0
        if type(p[2]) == "table" then point, relative, relativePoint, x, y = p[1], p[2], p[3], p[4] or 0, p[5] or 0 end
        local left, top, w, h = 0, 0, 0, 0
        if relative ~= page then left, top, w, h = Rect(relative) end
        local ax, ay = At(relativePoint, left, top, w, h)
        local ox, oy = At(point, 0, 0, width, height)
        return ax + x - ox, ay - y - oy, width, height
    end
    local function Overlap(a, b)
        return a[1] < b[1] + b[3] and b[1] < a[1] + a[3] and a[2] < b[2] + b[4] and b[2] < a[2] + a[4]
    end
    -- Every piece of the options showing: inside them, and none on another.
    local function Laid()
        local left, top, width, height = Rect(page.options)
        local rects, outside, overlaps = {}, {}, {}
        for _, obj in ipairs(objects) do
            if S[obj].parent == page.options and S[obj].shown then
                assert(#S[obj].points == 1, "one anchor each")
                local l, t, wide, high = Rect(obj)
                local rect = { l, t, wide, high, S[obj].text or (obj.text and S[obj.text].text) or (obj.label and S[obj.label].text) or S[obj].kind }
                if l < left or t < top or l + wide > left + width or t + high > top + height then outside[#outside + 1] = rect[5] end
                for _, other in ipairs(rects) do
                    if Overlap(rect, other) then overlaps[#overlaps + 1] = rect[5] .. " on " .. other[5] end
                end
                rects[#rects + 1] = rect
            end
        end
        return #rects .. " | " .. table.concat(outside, ", ") .. " | " .. table.concat(overlaps, ", ")
    end
    for i, style in ipairs({ "Quick", "Long" }) do
        page.edit.buttons[i]:Click()
        Equal(Laid(), "14 |  | ", style .. " under Edit: every tick, label, choice and slider inside the options, none on another")
    end
    page.edit.buttons[1]:Click()

    -- Each slider's label clear of its track, whose thumb reaches 5 back
    -- over the track's start at the lowest value (the overlap the user saw),
    -- and each value clear of the thumb at the highest.
    local limits = { pulseSize = ns.PULSE_SIZE, pulseLongSize = ns.PULSE_LONG_SIZE, pulseTime = ns.PULSE_TIME,
        pulseLongTime = ns.PULSE_LONG_TIME, pulseSeeThrough = ns.PULSE_SEE_THROUGH, pulseGrow = ns.PULSE_GROW }
    local tight = {}
    for _, slider in ipairs(page.sliders) do
        local track = S[slider.track].points
        local label = S[slider.label]
        if Wide(label.text, label.template) + 5 + 3 > track[1][2] then tight[#tight + 1] = label.text end
        for _, value in ipairs({ limits[slider.key][1], limits[slider.key][2] }) do
            slider:Set(value)
            local shown = S[slider.value]
            if Wide(shown.text, shown.template) + 5 > -track[2][2] or Wide(shown.text, shown.template) > shown.width then
                tight[#tight + 1] = slider.key .. " at " .. shown.text
            end
        end
        slider:Set(ns.Get(slider.key))
    end
    -- Each choice's label clear of its buttons, and each button's name inside it.
    local function Fits(pills)
        local label = S[pills.label]
        if Wide(label.text, label.template) + 6 > S[pills].points[1][2] - label.points[1][2] then tight[#tight + 1] = label.text end
        for _, button in ipairs(pills.buttons) do
            local name = S[button.label]
            if Wide(name.text, name.template) + 4 > S[button].width then tight[#tight + 1] = name.text end
        end
    end
    for _, pills in ipairs({ page.edit, page.sound, page.border }) do Fits(pills) end
    -- A row's switch, and its cooldown in its room before it.
    local row = RowFor(page, "family:healing")
    for _, button in ipairs(row.style.buttons) do
        local name = S[button.label]
        if Wide(name.text, name.template) + 4 > S[button].width then tight[#tight + 1] = name.text end
    end
    for _, text in ipairs({ "on your bars", "in your bags", "trinket", "1.5 min", "2 hours" }) do
        if Wide(text, S[row.long].template) > S[row.long].width then tight[#tight + 1] = text end
    end
    local room = S[page.sound.play].width
    for _, key in ipairs(ns.PULSE_SOUND_KEYS) do
        local name = ns.PULSE_SOUND_NAMES[key]
        if Wide(name, S[page.sound.name].template) + 4 > room then tight[#tight + 1] = name end
    end
    Equal(table.concat(tight, ", "), "", "every label beside its control with room to spare, every value and name inside its own")

    -- The title row: the longest it says, clear of Preview; and the list's
    -- heading and its note inside the page.
    local title = S[page.title]
    local from = 16 + Wide(title.text, title.template) + 10
    local longest = 0
    for _, said in ipairs({ "Off. Tick the box below to start.", "Nothing to pulse yet: tick some below.",
        "12 cooldowns pulse when they're ready.", "Running in Forever Enhanced Cooldown Pulse instead." }) do
        longest = math.max(longest, Wide(said, S[page.status].template))
    end
    local previewLeft = 638 - 16 - S[page.previewButton].width
    local heading = 16 + Wide(S[page.heading].text, S[page.heading].template) + 10 + Wide(S[page.about].text, S[page.about].template)
    Equal(tostring(from + longest + 8 <= previewLeft) .. " " .. tostring(heading <= 16 + 606), "true true",
        "the title row clear of Preview, the list's heading and note inside the page")
    Equal(tostring(Wide("Preview Quick", "GameFontHighlightSmall") + 8 <= S[page.previewButton].width), "true", "Preview's name inside it")
    -- A row switch's note, for every name listed, in two lines of the footer at most.
    local widest, named = 0, 0
    for _, row in ipairs(page.rows) do
        if S[row].shown and row.key then
            named = named + 1
            for _, button in ipairs(row.style.buttons) do widest = math.max(widest, Wide(Note(button), S[w.note].template)) end
        end
    end
    Equal(tostring(named > 0) .. " " .. tostring(widest <= 2 * S[w.note].width), "true true", "a row switch's note fits two lines of the footer")

    -- Our own words: none of an older addon's names for these choices, and no long dashes.
    local words, found = { "Fade", "Opacity", "Alpha", "Hold", "Scal", "Ignore", "Remaining", "Cooldowns from", "Add a spell" }, {}
    for _, obj in ipairs(objects) do
        local text = S[obj].kind == "FontString" and S[obj].text
        local parent = S[obj].parent
        while parent and parent ~= page do parent = S[parent] and S[parent].parent end
        if type(text) == "string" and parent == page then
            for _, word in ipairs(words) do
                if text:find(word, 1, true) then found[#found + 1] = text end
            end
            if text:find("\226\128\148") then found[#found + 1] = text end
        end
    end
    Equal(table.concat(found, ", "), "", "our own plain words on the page")
end

-- The game data: each spell's base cooldown --------------------------------------------------------------

do
    Equal(P:BaseCooldown(22812) .. " " .. P:BaseCooldown(871) .. " " .. P:BaseCooldown(1856) .. " " .. P:BaseCooldown(8921) .. " "
        .. P:BaseCooldown(6603) .. " " .. P:BaseCooldown(17), "60 900 300 0 0 4",
        "from the game data: Barkskin, Shield Wall, Vanish, Power Word: Shield; Moonfire and Attack have none")
    Equal(P:BaseCooldown(999999), 0, "a spell the data doesn't cover, with no way to ask: none")
    _G.GetSpellBaseCooldown = function(id)
        if id == 999999 then return 45000, 1500 end
        if id == 999998 then return SECRETS.number end
        return 99000
    end
    Equal(string.format("%g %g %g", P:BaseCooldown(999999), P:BaseCooldown(999998), P:BaseCooldown(8921)), "45 0 0",
        "asked of the game only for a spell the data doesn't cover, and only a plain answer counts")
    _G.GetSpellBaseCooldown = nil
end

-- Plain words: seconds read the same everywhere, and the tour's first step
-- names both pages under More.

do
    Equal(ns.PulseLong(4) .. ", " .. ns.PulseLong(45) .. ", " .. ns.PulseLong(90) .. ", " .. ns.PulseLong(180) .. ", "
        .. ns.PulseLong(3600), "4s, 45s, 1.5 min, 3 min, 1 hour", "a cooldown in plain words, seconds as the sliders say them")
    Equal(ns.Tour:News("0.9.0")[1].text(), "Everything is in this list: your four bars at the top, then Look, Layout, Cast bar and General,"
        .. " and Raid Timers and Cooldown pulse under More.", "the tour's first step points out both pages under More")
end

-- Ticks follow the profile, as the bars' lists do -----------------------------------------------------

do
    local own = ns.ProfileName()
    Equal(tostring(ForeverEnhancedCooldownManagerDB.pulsePick) .. " " .. Saved("pulsePick"),
        "nil Barkskin,Bash,Walk on Air,family:healing,slot:13", "ticks are saved in this character's profile")
    ns.SetPulseStyle("Bash", "long")
    local made = ns.NewProfile("Empty")
    w:Refresh()
    Equal(tostring(made) .. " " .. select(1, P:Watchers()) .. " [" .. Saved("pulsePick") .. "] " .. Rows(page),
        "true 0 [] SPELLS | [ ] Barkskin 1 min Quick | [ ] Bash 1 min Quick | [ ] Overpower 5s Quick | [ ] Walk on Air 2 min Quick"
        .. " | ITEMS | [ ] Trinket 1: Lucky Charm trinket Quick | [ ] Healing Potions in your bags Quick | [ ] Mana Potions in your bags Quick",
        "a new, empty profile: nothing ticked, all Quick, nothing watched; its bars are empty, so the potions show from your bags")
    ns.UseProfile(own)
    w:Refresh()
    Equal(select(1, P:Watchers()) .. " " .. RowFor(page, "Bash").style.selected, "5 long", "back on your own: your ticks and Long again")
    ns.CopyProfile("Copied")
    Equal(ns.ProfileName() .. " " .. select(1, P:Watchers()) .. " " .. Saved("pulsePick") .. " " .. Saved("pulseStyle"),
        "Copied 5 Barkskin,Bash,Walk on Air,family:healing,slot:13 Bash", "a copy takes your ticks and Long")
    ns.SetPulsePick("Barkskin", false)
    ns.UseProfile(own)
    Equal(tostring(Profile("pulsePick").Barkskin) .. " " .. select(1, P:Watchers()), "true 5", "unticking in the copy leaves your own alone")
    ns.DeleteProfile("Copied")
    ns.DeleteProfile("Empty")
    ns.SetPulseStyle("Bash", nil)
    w:Refresh()
end

-- Kept over a reload; anything wrong falls back ---------------------------------------------------------

do
    page.sound.buttons[3]:Click()
    page.sound.buttons[3]:Click()
    page.slider.pulseSize:Choose(400)
    ns.SetPulsePick("Bash", false)
    ns.SetPulseStyle("Barkskin", "long")
    local saved = ForeverEnhancedCooldownManagerDB
    Environment()
    BlizzardFrames()
    PulseGame()
    local again = LoadAll(saved)
    Tick(again.Pulse)
    local n, kept = again.Pulse:Watchers()
    Equal(tostring(again.Get("pulse")) .. " " .. again.Get("pulseSize") .. " " .. again.Get("pulseSound") .. " | "
        .. again.Get("pulseLongSize") .. " " .. again.Get("pulseLongTime") .. " " .. again.Get("pulseLongSound") .. " | " .. n .. " "
        .. tostring(kept.Bash) .. " " .. again.Pulse.editing, "true 400 bell | 448 40 bell | 3 nil quick",
        "on, both styles' choices and what's ticked, all kept; Edit back on Quick")
    Equal(table.concat(asked, ","):find("5211", 1, true), nil, "Bash, unticked, isn't even asked about")
    -- Just logged in: quiet, then it works, in its style.
    Done(kept.Barkskin.cooldown)
    Equal(tostring(again.Pulse:Showing()), "nil", "no pulse as you log in")
    clock = clock + 5
    Done(kept.Barkskin.cooldown)
    Equal(Now(again.Pulse) .. " " .. S[again.Pulse.frame].width, "Barkskin long 448", "after that, it pulses, still Long")

    Environment()
    BlizzardFrames()
    PulseGame()
    local bad = LoadAll({ pulse = "yes", pulseSize = 9999, pulseTime = 1, pulseSeeThrough = -5, pulseGrow = 300, pulseBorder = "pink",
        pulseSound = 3, pulseLongSize = 30, pulseLongTime = 51, pulseLongSound = "horn", pulseX = 1e9, pulseShadow = "no",
        pulseItems = 1, pulseMin = 0, pulseAdd = { Growl = true },
        pulseSkip = { ["family:healing"] = true },
        pulsePick = { Barkskin = true, Bash = "yes", [3] = true, [""] = true, ["slot:13"] = true, ["family:mana"] = "yes" },
        pulseStyle = { Barkskin = "long", Bash = "LONG", Thorns = "quick", [5] = "long", ["slot:13"] = "long", Moonfire = true } })
    Equal(tostring(bad.Get("pulse")) .. " " .. bad.Get("pulseSize") .. " " .. bad.Get("pulseTime") .. " " .. bad.Get("pulseSeeThrough")
        .. " " .. bad.Get("pulseGrow") .. " " .. bad.Get("pulseBorder") .. " " .. bad.Get("pulseSound") .. " | " .. bad.Get("pulseLongSize")
        .. " " .. bad.Get("pulseLongTime") .. " " .. bad.Get("pulseLongSound") .. " | " .. bad.Get("pulseX") .. " "
        .. tostring(bad.Get("pulseShadow")) .. " " .. tostring(bad.Get("pulseItems")),
        "false 272 10 80 135 thin none | 400 25 none | 0 true true", "anything wrong in the saved settings reads as the default")
    Equal(tostring(ForeverEnhancedCooldownManagerDB.pulseSkip) .. " " .. tostring(ForeverEnhancedCooldownManagerDB.pulsePick) .. " "
        .. tostring(ForeverEnhancedCooldownManagerDB.pulseStyle) .. " | " .. Saved("pulsePick") .. " | " .. Saved("pulseStyle"),
        "nil nil nil | Barkskin,slot:13 | Barkskin,slot:13",
        "the test builds' ticks for every character move into the profile, only proper entries: spells by name, items by key,"
        .. " Long by either; the left-out items, forgotten")
    Equal(tostring(ForeverEnhancedCooldownManagerDB.pulseMin) .. " " .. tostring(ForeverEnhancedCooldownManagerDB.pulseAdd), "nil nil",
        "the first test build's Cooldowns from and spells added by name, forgotten")
    Equal(bad.Pulse:StyleOf("Barkskin") .. " " .. bad.Pulse:StyleOf("Bash") .. " " .. bad.Pulse:StyleOf("Moonfire"), "long quick quick",
        "read as Long only when saved as Long")

    Environment()
    BlizzardFrames()
    PulseGame()
    local lists = LoadAll({ pulsePick = "x", pulseStyle = true, pulseLongTime = 2 })
    local db = ForeverEnhancedCooldownManagerDB
    Equal(tostring(db.pulsePick) .. " " .. tostring(db.pulseStyle) .. " " .. type(Profile("pulsePick")) .. " " .. type(Profile("pulseStyle"))
        .. " " .. lists.Get("pulseLongTime"), "nil nil table table 25",
        "lists that aren't lists start empty; a time under the shortest reads as the default")
    local profile = db.profiles[db.chars[UnitGUID("player")]]
    profile.pulsePick, profile.pulseStyle = 5, { Bash = "long", Thorns = "quick", [""] = "long" }
    Environment()
    BlizzardFrames()
    PulseGame()
    LoadAll(db)
    Equal(type(Profile("pulsePick")) .. " " .. Saved("pulseStyle"), "table Bash", "and in a profile too")
end

-- A new spell learned: listed at once, unticked -----------------------------------------------------

do
    Environment()
    BlizzardFrames()
    PulseGame()
    -- A character with no cooldowns yet: Attack and Smite.
    book = { { name = "General", items = { { name = "Attack", spellID = 6603 } } },
        { name = "Holy", items = { { name = "Smite", subName = "Rank 1", spellID = 585, iconID = 135924 } } } }
    local learner = LoadAll({ pulse = true })
    local P = learner.Pulse
    Tick(P)
    learner.ShowWindow()
    FECMFrame:Select("pulse")
    local page = FECMFrame.pages.pulse
    Equal(Rows(page) .. " | " .. tostring(S[page.empty].shown) .. " " .. S[page.empty].text .. " | " .. S[page.status].text,
        " | true None of your spells has a cooldown of its own yet. New ones show here as you learn them."
        .. " | Nothing to pulse yet: tick some below.", "no cooldowns yet: the list says new ones show as you learn them")
    -- Power Word: Shield learned (the user's own example: 4 s).
    table.insert(book[2].items, { name = "Power Word: Shield", subName = "Rank 1", spellID = 17, iconID = 135940 })
    local from, scan, scans, refresh, redraws = #timers, learner.Spells.Scan, 0, FECMFrame.Refresh, 0
    learner.Spells.Scan = function(...) scans = scans + 1 return scan(...) end
    FECMFrame.Refresh = function(...) redraws = redraws + 1 return refresh(...) end
    Fire("SPELLS_CHANGED")
    Fire("SPELLS_CHANGED")
    Equal(Rows(page):find("Power Word", 1, true), nil, "learned: not listed until the next frame")
    Later(from)
    Tick(P)
    learner.Spells.Scan, FECMFrame.Refresh = scan, refresh
    Equal(scans .. " " .. redraws, "1 1", "two spellbook changes at once: one redraw, your spells read once, not again by the pulse")
    Equal(Rows(page) .. " | " .. tostring(S[page.empty].shown), "SPELLS | [ ] Power Word: Shield 4s Quick | false",
        "learned: listed on the next frame, unticked, Quick, its 4 s cooldown")
    Tick(P)
    Equal(select(1, P:Watchers()), 0, "and not watched until it's ticked")
    RowFor(page, "Power Word: Shield").check:Click()
    local n, watched = P:Watchers()
    Equal(n .. " " .. S[page.status].text, "1 1 cooldown pulses when it's ready.", "ticked: watched")
    clock = clock + 5
    Done(watched["Power Word: Shield"].cooldown)
    Equal(Now(P), "Power Word: Shield quick", "and it pulses when it's ready")
    Finish(P)
    -- A new level: the list is read again on the next frame.
    table.insert(book[2].items, { name = "Psychic Scream", subName = "Rank 1", spellID = 8122, iconID = 136184 })
    Fire("PLAYER_LEVEL_UP")
    Equal(Rows(page):find("Psychic Scream", 1, true), nil, "not until the next frame")
    Tick(P)
    Equal(Rows(page), "SPELLS | [x] Power Word: Shield 4s Quick | [ ] Psychic Scream 30s Quick",
        "a new level: the new spell listed, unticked; the ticked one kept")
    Equal(select(1, P:Watchers()), 1, "still only the ticked one watched")
    -- Unlearned (talents reset): its row and its watcher go on the next
    -- frame, and its old cooldown ending says nothing.
    local old = watched["Power Word: Shield"].cooldown
    table.remove(book[2].items, 2)
    from = #timers
    Fire("SPELLS_CHANGED")
    Later(from)
    Equal(Rows(page) .. " | " .. S[page.status].text, "SPELLS | [ ] Psychic Scream 30s Quick | Nothing to pulse yet: tick some below.",
        "unlearned: its row gone on the next frame, nothing counted")
    Tick(P)
    clock = clock + 5
    Done(old)
    Equal(select(1, P:Watchers()) .. " " .. tostring(old.watch) .. " " .. tostring(P:Showing()) .. " " .. #printed, "0 nil nil 0",
        "its watcher let go on the next frame; its old cooldown ending: no pulse, no error")
    Equal(tostring(Profile("pulsePick")["Power Word: Shield"]), "true", "still ticked should it be learned again")
end


-- Two trinkets at once, or a trinket and a potion: a pulse each ---------------------------------
-- Items sharing a cooldown pulse once (every potion), but two trinkets used
-- in the same moment, or a trinket and a potion with the same start and
-- length, run their own cooldowns: each pulses, the second taking its turn.
-- A potion or healthstone in your bags is its family's row, listed once.

;(function()
    Environment()
    BlizzardFrames()
    PulseGame()
    -- Lucky Charm in the first slot and a Second Charm in the other, both with a use.
    local worn, cooldowns = { [13] = 9999, [14] = 9998 }, { [13] = { 0, 0, 1 }, [14] = { 0, 0, 1 } }
    local itemSpell = C_Item.GetItemSpell
    C_Item.GetItemSpell = function(id)
        if id == 9998 then return "Charm", 2 end
        if id == 2455 then return "Mana Potion", 3 end
        return itemSpell(id)
    end
    _G.GetInventoryItemID = function(_, slot) return worn[slot] end
    _G.GetInventoryItemLink = function(_, slot)
        return "|cff1eff00|Hitem:" .. tostring(worn[slot]) .. "|h[" .. (slot == 13 and "Lucky Charm" or "Second Charm") .. "]|h|r"
    end
    _G.GetInventoryItemCooldown = function(_, slot)
        local c = cooldowns[slot]
        return c[1], c[2], c[3]
    end
    local tns = LoadAll({ pulse = true })
    local TP = tns.Pulse
    Tick(TP)
    itemCount[118] = 1
    tns.SetPulsePick("slot:13", true)
    tns.SetPulsePick("slot:14", true)
    tns.SetPulsePick("family:healing", true)
    TP:Apply()
    local _, watching = TP:Watchers()
    Equal(tostring(watching["slot:13"] ~= nil) .. " " .. tostring(watching["slot:14"] ~= nil) .. " " .. tostring(watching["family:healing"] ~= nil),
        "true true true", "both trinkets and Healing Potions ticked: each watched")
    -- Both trinkets used in the same moment: the same start and length.
    cooldowns[13], cooldowns[14] = { 200, 120, 1 }, { 200, 120, 1 }
    Fire("BAG_UPDATE_COOLDOWN")
    Tick(TP)
    clock = clock + 5
    Done(watching["slot:13"].cooldown)
    Done(watching["slot:14"].cooldown)
    local key, waiting = TP:Showing()
    Equal(key .. " " .. waiting .. " " .. tostring(watching["slot:13"].shared) .. " " .. tostring(watching["slot:14"].shared),
        "slot:13 1 nil nil", "two trinkets used together: each pulses, the second waiting its turn, neither sharing")
    TP:Next()
    Equal(tostring((TP:Showing())), "slot:14", "then the second trinket's own pulse")
    Finish(TP)
    -- A trinket and a potion with the same start and length: a pulse each too.
    cooldowns[13], itemCooldown = { 400, 120, 1 }, { 400, 120, true }
    Fire("BAG_UPDATE_COOLDOWN")
    Tick(TP)
    clock = clock + 5
    Done(watching["slot:13"].cooldown)
    Done(watching["family:healing"].cooldown)
    key, waiting = TP:Showing()
    Equal(key .. " " .. waiting, "slot:13 1", "a trinket and a potion with the same cooldown: the trinket now, the potion next")
    TP:Next()
    Equal(tostring((TP:Showing())), "cd:400:120", "the potion's own pulse, keyed by the cooldown potions share")
    Finish(TP)

    -- Carrying a Minor Healing Potion: Healing Potions lists it, the bag
    -- item isn't listed again (each pulse is the family's).
    local function Keys()
        local keys = {}
        for _, entry in ipairs(TP:Items()) do keys[#keys + 1] = entry.key end
        return table.concat(keys, ",")
    end
    bagItems[1] = { itemID = 118, hyperlink = "|cffffffff|Hitem:118::|h[Minor Healing Potion]|h|r", iconFileID = 888 }
    tns.Spells:Scan()
    Equal(Keys(), "slot:13,slot:14,family:healing", "a potion in your bags: once, as Healing Potions, not twice")
    Equal(tostring(tns.Spells:Find("item:118") ~= nil), "true", "though your bars can still list it from your bags")
    -- Wanted on its own, it shows: ticked (an older list), or on a bar by itself.
    tns.SetPulsePick("item:118", true)
    Equal(Keys(), "slot:13,slot:14,family:healing,item:118", "ticked on its own: listed, so it can be unticked")
    tns.SetPulsePick("item:118", false)
    tns.Bars:Assign("item:118", "cd")
    Equal(Keys(), "slot:13,slot:14,family:healing,item:118", "on a bar by itself: listed")
    tns.Bars:Assign("item:118", nil)
    Equal(Keys(), "slot:13,slot:14,family:healing", "off the bar: once again")
    -- A class without mana has no Mana Potions row: one carried shows on its own.
    _G.UnitClass = function() return "Warrior", "WARRIOR" end
    bagItems[1] = { itemID = 2455, hyperlink = "|cffffffff|Hitem:2455::|h[Minor Mana Potion]|h|r", iconFileID = 888 }
    itemCount[2455] = 1
    tns.Spells:Scan()
    Equal(Keys(), "slot:13,slot:14,family:healing,item:2455", "a warrior's mana potion: no Mana Potions row, so its own")
    -- A profile shared with a class with mana keeps Mana Potions on the bar:
    -- the warrior's list adds it last. The potion is still its row, once.
    local cdSpells = tns.BarData("cd").spells
    cdSpells[#cdSpells + 1] = "family:mana"
    tns.Spells:Scan()
    Equal(Keys(), "slot:13,slot:14,family:healing,family:mana",
        "Mana Potions on the bar from a shared profile: a warrior's mana potion listed once, as that row")
    cdSpells[#cdSpells] = nil
    tns.Spells:Scan()
    _G.UnitClass = function() return "Druid", "DRUID" end

    -- Lucky Charm put on the Cooldowns bar from your bags before you wore
    -- it stays that item on the bar, listed beside Trinket 1. Both ticked,
    -- its cooldown pulses once, as the slot; with the slot unticked, the
    -- bar's one pulses for it.
    C_Item.IsEquippedItem = function(id) return id == worn[13] or id == worn[14] end
    cdSpells[#cdSpells + 1] = "item:9999"
    tns.Spells:Scan()
    tns.SetPulsePick("item:9999", true)
    TP:Apply()
    Equal(tostring(watching["slot:13"] ~= nil) .. " " .. tostring(watching["item:9999"] ~= nil), "true true",
        "the worn trinket ticked twice over: as Trinket 1, and as the item on your bars")
    cooldowns[13], itemCooldown = { 600, 120, 1 }, { 600, 120, true }
    Fire("BAG_UPDATE_COOLDOWN")
    Tick(TP)
    clock = clock + 5
    Done(watching["slot:13"].cooldown)
    Done(watching["item:9999"].cooldown)
    key, waiting = TP:Showing()
    Equal(key .. " " .. waiting, "slot:13 0", "one trinket, ticked twice: one pulse, the slot's")
    Finish(TP)
    tns.SetPulsePick("slot:13", false)
    TP:Apply()
    cooldowns[13], itemCooldown = { 800, 120, 1 }, { 800, 120, true }
    Fire("BAG_UPDATE_COOLDOWN")
    Tick(TP)
    clock = clock + 5
    Done(watching["item:9999"].cooldown)
    key, waiting = TP:Showing()
    Equal(tostring(key) .. " " .. waiting, "cd:800:120 0", "its slot unticked: the item on your bars pulses for it")
    Finish(TP)
    Equal(#printed, 0, "no errors from trinkets and potions")
end)()

-- Trinkets and potions too: only those with a cooldown pulse ---------------------------------------

do
    local items = FECMFrame.pages.pulse.items
    Equal(items.hint, "Your trinkets, potions, healthstones and other items with a use in your bags. Only ones with a cooldown pulse.",
        "its note says only items with a cooldown pulse")
    Equal(tostring(Wide(items.hint, "GameFontHighlightSmall") <= 2 * S[FECMFrame.note].width), "true", "in two lines of the footer at most")
end

-- Where a frame is in the window: left, top, right, bottom, y down from its
-- top left, worked out from its anchors as the game would. Text is as wide
-- as Wide says, a tick its box and label. A global: the main chunk is near
-- Lua's limit of 200 locals.
function Placed(obj, depth)
    depth = depth or 0
    assert(depth < 40, "anchors that go round in a circle")
    if obj == FECMFrame then return 0, 0, 820, 560 end
    local s = S[obj]
    local width, height = s.width, s.height
    if s.kind == "FontString" then
        if width == 0 then width = Wide(s.text, s.template) end
        height = height > 0 and height or 12
    end
    if rawget(obj, "box") and rawget(obj, "text") then width, height = 18 + Wide(S[obj.text].text, S[obj.text].template), 16 end
    if #s.points == 0 then return Placed(s.parent, depth + 1) end
    local left, top, right, bottom, cx, cy
    for _, p in ipairs(s.points) do
        local point, relative, relativePoint, x, y = p[1], s.parent, p[1], p[2] or 0, p[3] or 0
        if type(p[2]) == "table" then point, relative, relativePoint, x, y = p[1], p[2], p[3] or p[1], p[4] or 0, p[5] or 0 end
        local rl, rt, rr, rb = Placed(relative, depth + 1)
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
    return left, top, right, bottom
end

-- The tour box showing, against the part it outlines and the page it's on:
-- nothing when it fits, or what's wrong. The box inside the page, the part
-- outlined there, and the box clear of the outline round it.
function BoxFits(page)
    local box = FECMTour
    local o = S[box.outline].points
    local l, t = Placed(o[1][2])
    local _, _, r, b = Placed(o[2][2])
    l, t, r, b = l - 4, t - 4, r + 4, b + 4
    local bl, bt, br, bb = Placed(box)
    local pl, pt, pr, pb = Placed(page)
    local wrong = {}
    if bl < pl or bt < pt or br > pr or bb > pb then
        wrong[#wrong + 1] = ("box off the page (%g %g %g %g)"):format(bl - pl, bt - pt, br - pl, bb - pt)
    end
    if l + 4 < pl or t + 4 < pt or r - 4 > pr or b - 4 > pb then wrong[#wrong + 1] = "part off the page" end
    if bl < r and l < br and bt < b and t < bb then wrong[#wrong + 1] = "box on its part" end
    return table.concat(wrong, ", ")
end

-- What's new for the Cooldown pulse, and the ? on every page ------------------------------------
-- What's new tours the next update's steps: the Cooldown pulse page's four
-- (turn it on, pick your cooldowns, Quick and Long, where it shows) and the
-- Look page's Ready glow, never the page help's. The ? walks through the
-- page showing: every step about it, on it, each box on the page and clear
-- of what it points at, and changes nothing.

;(function()
    Environment()
    BlizzardFrames()
    PulseGame()
    _G.FECMFrame, _G.FECMTour, _G.FECMNotes = nil, nil, nil
    local tns = LoadAll({ useBars = true, notesSeen = "1.4.4" })
    local Tour = tns.Tour
    local function Titles(list)
        local titles = {}
        for _, step in ipairs(list) do titles[#titles + 1] = step.title end
        return table.concat(titles, ", ")
    end
    local NEW = "Turn it on, Pick your cooldowns, Quick and Long, Where it shows, Ready glow"
    local waiting = true
    for _, step in ipairs(Tour:News("1.4.4")) do waiting = waiting and step.version == "1.5.0" end
    Equal(Titles(Tour:News("1.4.4")) .. " | " .. tostring(waiting) .. " | " .. Titles(Tour:News(nil)), NEW .. " | true | " .. NEW,
        "after 1.4.4: the Cooldown pulse's four steps, then Ready glow, all 1.5.0's; by hand the same")
    -- Plain and short: no em dash, none longer than the basics' steps.
    local basics, long = 0, {}
    for _, step in ipairs(Tour:News("0.9.0")) do
        local text = type(step.text) == "function" and step.text() or step.text
        if step.version == "1.0.0" then basics = math.max(basics, #text) end
    end
    for _, step in ipairs(Tour:News("1.4.4")) do
        local text = type(step.text) == "function" and step.text() or step.text
        local already = type(step.alreadyText) == "function" and step.alreadyText() or step.alreadyText
        local all = text .. " " .. step.title .. " " .. (step.try or "") .. " " .. (already or "")
        if #text > basics or all:find("\226\128\148", 1, true) or all:find("/fecm", 1, true) then long[#long + 1] = step.title end
    end
    Equal(table.concat(long, ", "), "", "each plain, no longer than the basics' steps, and never /fecm")
    -- The page help's steps are in no What's new, nor the full tour.
    local all = Titles(Tour:News("0.9.0"))
    local leaked = {}
    for _, title in ipairs({ "Missing ones greyed", "Join two into one", "Your debuffs on you", "Colours", "Height and parts",
        "Minimap button", "Help" }) do
        if all:find(title, 1, true) then leaked[#leaked + 1] = title end
    end
    Equal(table.concat(leaked, ", "), "", "no page help step in What's new, from any version")

    -- After an update from 1.4.4: Show me what's new tours them.
    for _, timer in ipairs(timers) do timer() end
    local notes = FECMNotes
    Equal(tostring(S[notes].shown) .. " " .. tostring(S[notes.tour].shown), "true true", "What's new after 1.4.4 offers its tour")
    notes.tour:Click()
    local w, box = FECMFrame, FECMTour
    local pulse = w.pages.pulse
    local seen = {}
    local function Step()
        return S[box.count].text .. " " .. w.selected .. " " .. S[box.title].text
    end
    Equal(Step() .. " | " .. tostring(S[box.outline].points[1][2] == pulse.master) .. " " .. BoxFits(pulse) .. "|"
        .. tostring(S[box.text].text:find("Try it: tick it.", 1, true) ~= nil), "1 of 5 pulse TURN IT ON | true |true",
        "the first: the Cooldown pulse page's on tick, the box under it on the page, asking you to tick it")
    pulse.master:Click()
    S[box].scripts.OnUpdate(box, 1)
    Equal(Step() .. " | " .. tostring(S[box.outline].points[1][2] == pulse.panel) .. " " .. BoxFits(pulse) .. "|"
        .. tostring(S[box.text].text:find("Try it: tick one.", 1, true) ~= nil), "2 of 5 pulse PICK YOUR COOLDOWNS | true |true",
        "ticked: on to the list of cooldowns, the box above it")
    box.next:Click()
    Equal(Step() .. " | " .. tostring(S[box.outline].points[1][2] == pulse.styles) .. " " .. BoxFits(pulse) .. "|"
        .. tostring(S[box.text].text:find("Try it: pick Long, then Preview.", 1, true) ~= nil), "3 of 5 pulse QUICK AND LONG | true |true",
        "then Edit and what follows it, the box beside them")
    -- The box sits over the look both styles share, clear of Edit, Size, Shows for and Sound.
    local edge = select(3, Placed(pulse.styles))
    for _, part in ipairs({ pulse.edit, pulse.slider.pulseSize, pulse.slider.pulseTime, pulse.sound }) do
        seen[#seen + 1] = tostring(select(3, Placed(part)) <= edge)
    end
    Equal(table.concat(seen, " ") .. " " .. tostring(select(1, Placed(box)) >= edge + 14), "true true true true true",
        "Edit, Size, Shows for and Sound inside the part outlined, the box past it")
    pulse.edit.buttons[2]:Click()
    pulse.previewButton:Click()
    S[box].scripts.OnUpdate(box, 1)
    Equal(Step(), "3 of 5 pulse QUICK AND LONG", "Long picked and previewed: the step stays")
    Finish(tns.Pulse)
    pulse.edit.buttons[1]:Click()
    box.next:Click()
    local o = S[box.outline].points
    Equal(Step() .. " | " .. tostring(o[1][2] == pulse.move and o[2][2] == pulse.reset) .. " " .. BoxFits(pulse) .. "|"
        .. tostring(S[box.text].text:find("Try it", 1, true)), "4 of 5 pulse WHERE IT SHOWS | true |nil",
        "then Move and Reset, the box under them, no Try it (Move puts the window away)")
    box.next:Click()
    Equal(Step() .. " | " .. tostring(S[box.outline].points[1][2] == w.readyGlow.part) .. " " .. BoxFits(w.pages.look) .. "| "
        .. S[box.next.label].text, "5 of 5 look READY GLOW | true | Done", "and Ready glow on the Look page, the last")
    box.next:Click()
    Equal(tostring(S[box].shown) .. " " .. S[w.note].text, "false That's what's new. See it again any time from What's new, or with /ccm new.",
        "Done ends it")
    Equal(tostring(tns.Get("pulse")) .. " " .. tns.Get("readyGlow"), "true proc", "the tour only changed what you did yourself")
    tns.Set("pulse", false)
    tns.Pulse:Apply()

    -- The ? on every page: that page's steps only, on it, each box fitting.
    local help = w.help
    local problems = {}
    local function Walk(key)
        w:Select(key)
        help:Click()
        local page = w.pages[key] or w.pages.bar
        local titles, shown, outlined, count = {}, {}, true, S[box.count].text
        local done
        repeat
            titles[#titles + 1] = S[box.title].text
            shown[w.selected] = true
            if not (S[box.outline].shown and S[box.arrow].shown) then outlined = false end
            local wrong = BoxFits(page)
            if wrong ~= "" then problems[#problems + 1] = key .. " " .. S[box.title].text .. ": " .. wrong end
            done = S[box.next.label].text == "Done"
            box.next:Click()
        until done or #titles > 20
        local pages = {}
        for name in pairs(shown) do pages[#pages + 1] = name end
        table.sort(pages)
        return table.concat(titles, ", ") .. " | " .. count:match("of (%d+)") .. " | " .. table.concat(pages, ",") .. " " .. tostring(outlined)
    end
    local before = {}
    for key in pairs(tns.DEFAULTS) do before[#before + 1] = key .. "=" .. tostring(tns.Get(key)) end
    table.sort(before)
    local BAR = "ADD SPELLS, THIS BAR'S OPTIONS"
    local SPELL = BAR .. ", HEALTHSTONES AND POTIONS, DIM WHEN READY | 4"
    local expected = {
        cd = SPELL .. " | cd true",
        util = SPELL .. " | util true",
        buff = BAR .. ", MISSING ONES GREYED, JOIN TWO INTO ONE, YOUR DEBUFFS ON YOU | 5 | buff true",
        debuff = BAR .. ", MISSING ONES GREYED, JOIN TWO INTO ONE, YOUR DEBUFFS ON YOU | 5 | debuff true",
        look = "THE LOOK, KEYBINDS ON ICONS, FONT AND BAR TEXTURE, READY GLOW | 4 | look true",
        layout = "LAYOUTS, LIVE PREVIEW, ALL BARS, GROW ARROWS | 4 | layout true",
        cast = "CAST BAR, COLOURS, HEIGHT AND PARTS | 3 | cast true",
        general = "SWITCH YOUR BARS ON, MINIMAP BUTTON, HELP | 3 | general true",
        raid = "RAID TIMERS, SIZES, EDIT MODE | 3 | raid true",
        pulse = "TURN IT ON, PICK YOUR COOLDOWNS, QUICK AND LONG, WHERE IT SHOWS | 4 | pulse true",
    }
    local pages, wrong = {}, {}
    for key in pairs(w.nav) do pages[#pages + 1] = key end
    table.sort(pages)
    for _, key in ipairs(pages) do
        local got = Walk(key)
        if got ~= expected[key] then wrong[#wrong + 1] = key .. ": " .. got end
    end
    Equal(table.concat(pages, ",") .. " | " .. table.concat(wrong, "; "), "buff,cast,cd,debuff,general,layout,look,pulse,raid,util | ",
        "every page in the list has a walkthrough of two steps or more, its own steps only, staying on it, each part outlined:"
        .. " the four bars share their page's steps, but Buffs and Debuffs skip the spell bars' Show items and When ready")
    Equal(table.concat(problems, "; "), "", "on every page, each box inside the page and clear of the part it points at")
    local after = {}
    for key in pairs(tns.DEFAULTS) do after[#after + 1] = key .. "=" .. tostring(tns.Get(key)) end
    table.sort(after)
    Equal(table.concat(after, " "), table.concat(before, " "), "walking every page changed no setting")
    Equal(tostring(S[box].shown) .. " " .. S[w.note].text, "false That's this page. Click ? any time to see it again.",
        "Done ends each, saying where to find it again")
    -- The Cooldown pulse page's first step moves on once the pulse is ticked on.
    w:Select("pulse")
    help:Click()
    pulse.master:Click()
    S[box].scripts.OnUpdate(box, 1)
    Equal(Step(), "2 of 4 pulse PICK YOUR COOLDOWNS", "ticked on: the walkthrough moves on by itself")
    box.skip:Click()
    Equal(S[w.note].text, "Click ? any time to see it again.", "Skip tour ends it")
    pulse.master:Click()
    Equal(tostring(tns.Get("pulse")), "false", "off again")
    Equal(#printed, 0, "no errors from What's new or the walkthroughs")
end)()

-- The ? in the title bar: its place, and the bar pages sharing one page -----------------------------
-- (TestBars.lua's window is near the mock game's memory limit, so these run here.)

;(function()
    Environment()
    BlizzardFrames()
    PulseGame()
    _G.FECMFrame, _G.FECMTour, _G.FECMNotes = nil, nil, nil
    local hns = LoadAll({ useBars = true, notesSeen = "dev" })
    for _, timer in ipairs(timers) do timer() end
    SlashCmdList.FECM("")
    local w = FECMFrame
    local help = w.help
    -- Beside the X, in the window's own square style; the profile menu
    -- moves along for it.
    local hp, pp = S[help].points[1], S[w.profileButton].points[1]
    Equal(S[help.label].text .. " " .. S[help].width .. "x" .. S[help].height .. " " .. hp[1] .. " " .. tostring(hp[2] == w.close) .. " "
        .. hp[3] .. " " .. hp[4] .. " | " .. pp[1] .. " " .. tostring(pp[2] == help) .. " " .. pp[3] .. " " .. pp[4] .. " | "
        .. tostring(S[help].parent == w.header) .. " " .. tostring(help.hint),
        "? 22x22 RIGHT true LEFT -6 | RIGHT true LEFT -8 | true nil",
        "a ? square beside the X, the profile menu left of it; on hover a tooltip under it says what it does,"
            .. " not the footer (Tools/TestHelp.lua)")
    -- The title (large text, ten units a letter to be sure) clear of the
    -- profile menu, which starts 28 further left than before the ?.
    local profileLeft = Placed(w.profileButton)
    Equal(tostring(1 + 12 + 26 + 8 + #"Forever Enhanced Cooldown Manager" * 10 + 20 <= profileLeft) .. " " .. profileLeft,
        "true 471", "the title clear of the profile menu, which starts at 471")
    local Tour = hns.Tour
    local box
    -- The bar showing is what a bar step talks about.
    local bp = w.pages.bar
    hns.Bars:SetOption("util", "whenReady", "dim")
    w:Select("util")
    help:Click()
    box = FECMTour
    for _ = 1, 3 do box.next:Click() end
    Equal(S[box.title].text .. " " .. tostring(S[box.text].text:find("Utility already dims its ready icons.", 1, true) ~= nil) .. " "
        .. tostring(S[box.outline].points[1][2] == bp.options.whenReady.part), "DIM WHEN READY true true",
        "on Utility, Dim when ready says Utility already dims, outlining its When ready")
    hns.Bars:SetOption("util", "whenReady", "show")
    -- Another page picked meanwhile: the outline hides; Next goes back to the
    -- walkthrough's own page, not Cooldowns.
    box.back:Click()
    w:Select("cd")
    Equal(tostring(S[box].shown) .. " " .. tostring(S[box.outline].shown) .. " " .. tostring(S[box.arrow].shown), "true false false",
        "on another bar's page, even one sharing its page, the outline and arrow hide")
    box.next:Click()
    Equal(w.selected .. " " .. S[box.title].text .. " " .. tostring(S[box.outline].shown), "util DIM WHEN READY true",
        "Next brings it back to Utility")
    box.skip:Click()
    Equal(tostring(S[box].shown) .. " " .. S[w.note].text, "false Click ? any time to see it again.", "Skip tour ends it, saying the same")
    -- Buffs: each of its own steps points at its own part, the box hung from it.
    w:Select("buff")
    help:Click()
    local parts = { bp.listPanel, bp.optionsArea, bp.options.showMissing, bp.tray, bp.options.showSelf }
    local right = 0
    for i, part in ipairs(parts) do
        local o, p = S[box.outline].points, S[box].points[1]
        if o[1][2] == part and o[2][2] == part and p[2] == part and S[part].shown then right = right + 1 end
        if i == 3 then
            Equal(S[box.text].text, "Ticked, each buff keeps its spot, greyed while it's missing from you. Unticked, only the ones up show, in one row.",
                "the Buffs bar's missing ones: from you")
        end
        box.next:Click()
    end
    Equal(right, 5, "every Buffs step outlines its own part, there to see, the box hung from it")
    w:Select("debuff")
    help:Click()
    for _ = 1, 2 do box.next:Click() end
    Equal(S[box.text].text, "Ticked, each debuff keeps its spot, greyed while it's missing from your target."
        .. " Unticked, only the ones up show, in one row.", "the Debuffs bar's: from your target")
    -- Its own Your debuffs on you, at the end of the bar.
    for _ = 1, 2 do box.next:Click() end
    local o = S[box.outline].points
    Equal(S[box.title].text .. " | " .. S[box.text].text .. " | " .. tostring(o[1][2] == bp.options.showSelf and S[bp.options.showSelf].shown),
        "YOUR DEBUFFS ON YOU | Shows debuffs you put on yourself, like Weakened Soul or Recently Bandaged, at the end of this bar."
        .. " Not with missing debuffs greyed. | true", "the Debuffs bar's debuffs on you: at the end of the bar, outlining its tick")
    box.skip:Click()
    -- Cast bar's Colours: the box under both rows, clear of the chosen
    -- colours' names (Blizzard's gold, Silver) that the step talks about.
    w:Select("cast")
    help:Click()
    box.next:Click()
    local cp = w.pages.cast
    local function Clear(a, b)
        local al, at, ar, ab = Placed(a)
        local bl, bt, br, bb = Placed(b)
        return not (al < br and bl < ar and at < bb and bt < ab)
    end
    Equal(S[box.title].text .. " " .. S[cp.chosen].text .. ", " .. S[cp.swingChosen].text .. " " .. tostring(Clear(box, cp.chosen)) .. " "
        .. tostring(Clear(box, cp.swingChosen)) .. " " .. S[box].points[1][1] .. " " .. S[box].points[1][3] .. " " .. BoxFits(cp) .. "|",
        "COLOURS Blizzard's gold, Silver true true TOPLEFT BOTTOMLEFT |", "Colours: the box under the rows, clear of the chosen colours' names")
    box.skip:Click()

    -- Over the profile menu: a word on it in the footer, no walkthrough.
    w:Select("look")
    w.profileButton:Click()
    help:Click()
    Equal(tostring(S[box].shown) .. " " .. tostring(S[w.profilePanel].shown) .. " " .. S[w.note].text,
        "false true Click a profile or role to use it, right-click a role to save. Share or Import as text.",
        "with the profile menu open, the footer explains it (Share and Import too) and the menu stays")
    w.profileButton:Click()
    -- A page with nothing to walk through: the footer says so.
    local start = Tour.StartPage
    Tour.StartPage = function() return false end
    help:Click()
    Equal(tostring(S[box].shown) .. " " .. S[w.note].text,
        "false Nothing to walk through here yet. Hover over anything and this line says what it does.", "nothing to show: a word in the footer")
    Tour.StartPage = start
    Equal(#Tour:Page("nowhere") .. " " .. tostring(Tour:StartPage("nowhere")) .. " " .. tostring(S[box].shown), "0 false false",
        "a page with no steps starts nothing")
    -- The full tour is still the nine basics.
    SlashCmdList.FECM("tour")
    Equal(S[box.count].text .. " " .. S[box.title].text, "1 of 9 THE MENU", "the full tour is still the nine basics")
    box.skip:Click()
    Equal(#printed, 0, "no errors from the walkthroughs")
end)()

-- Ready glow: how a ready reactive ability shows on your own bars ---------------------------------
-- Picked at the foot of the Look page, right of the window's accent:
-- Blizzard's proc glow (the default) or a plain gold edge. A look, so no
-- Needs testing. Every icon changes at once, and it's kept over a reload.
-- Without Blizzard's template, both are the edge. Your bars read the game's
-- cooldowns here, so the pulse's sealed ones (PulseGame) stay out.

;(function()
    Environment()
    BlizzardFrames()
    _G.FECMFrame, _G.FECMTour, _G.FECMNotes = nil, nil, nil
    local gns = LoadAll({ useBars = true, notesSeen = "dev" })
    for _, timer in ipairs(timers) do timer() end
    local B = gns.Bars
    B:Assign("Overpower", "cd")
    usable[7384] = true
    B:RefreshAll()
    SlashCmdList.FECM("")
    local w = FECMFrame
    w:Select("look")
    local glow, icon = w.readyGlow, B:Get("cd").icons[1]
    local labels = {}
    for _, button in ipairs(glow.buttons) do labels[#labels + 1] = S[button.label].text end
    Equal(S[glow.label].text .. " | " .. table.concat(labels, ", ") .. " | " .. glow.selected .. " " .. tostring(S[glow].shown),
        "Ready glow | Proc glow, Gold edge | proc true", "Ready glow: Proc glow and Gold edge, Proc glow picked")
    -- At the foot, level with the accent and right of it, inside the page;
    -- its label clear of the choices and of the accent's name, each name
    -- inside its button.
    local gp, lp, pp = S[glow].points[1], S[glow.label].points[1], S[glow.part].points[1]
    local accent = S[w.swatches[#w.swatches]].points[1]
    Equal(gp[1] .. " " .. gp[2] .. " " .. gp[3] .. " | " .. lp[1] .. " " .. lp[3] .. " | " .. pp[1] .. " " .. pp[2] .. " " .. pp[3] .. " "
        .. S[glow.part].width .. " | " .. accent[1] .. " " .. accent[3], "BOTTOMRIGHT -16 14 | BOTTOMRIGHT 18 | BOTTOMRIGHT -16 14 250 | BOTTOMLEFT 14",
        "at the foot's right, level with the accent's swatches and label; one part round label and choices for the tour")
    local page = w.pages.look
    local l = Placed(page)
    local labelLeft, _, labelRight = Placed(glow.label)
    local pillsLeft, _, pillsRight = Placed(glow)
    local partLeft = Placed(glow.part)
    local chosenRight = l + 126 + #gns.ACCENT_KEYS * 26 + 2 + Wide("Orange", "GameFontHighlightSmall")
    Equal(tostring(labelRight + 10 <= pillsLeft) .. " " .. tostring(labelLeft >= chosenRight + 20) .. " " .. tostring(partLeft <= labelLeft) .. " "
        .. tostring(pillsRight <= l + 638 - 16) .. " " .. tostring(Wide("Proc glow", "GameFontHighlightSmall") + 4 <= S[glow.buttons[1]].width),
        "true true true true true", "the label before the choices and clear of the accent's name, inside the part and the page; each name inside its button")
    local notes = {}
    for _, button in ipairs(glow.buttons) do notes[#notes + 1] = button.hint end
    Equal(table.concat(notes, " | "), "Blizzard's proc glow, as on your action bars, round a ready ability like Overpower, Riposte or Mongoose Bite"
        .. " on your own bars. | A plain gold edge just inside the icon of a ready ability like Overpower, Riposte or Mongoose Bite on your own bars.",
        "each choice says what it is, with no Needs testing (a look, not a gameplay feature), naming abilities as examples only")
    -- Each in two lines of the footer at most.
    local fits = true
    for _, note in ipairs(notes) do fits = fits and Wide(note, "GameFontHighlightSmall") <= 2 * S[w.note].width end
    Equal(tostring(fits), "true", "each choice's note fits two lines of the footer")
    -- Picked: saved, every icon at once, the lit one staying lit.
    local proc = icon.glow
    glow.buttons[2]:Click()
    Equal(gns.Get("readyGlow") .. " " .. glow.selected .. " " .. tostring(icon.glow ~= proc and icon.glow.proc == nil) .. " "
        .. tostring(S[icon.glow].shown) .. " " .. tostring(S[proc].shown), "edge edge true true false",
        "Gold edge picked: the ready Overpower shows the edge at once, Blizzard's glow put out")
    -- Kept over a reload; anything else saved reads as Proc glow.
    local saved = ForeverEnhancedCooldownManagerDB
    Environment(true)
    BlizzardFrames()
    gns = LoadAll(saved)
    usable[7384] = true
    gns.Bars:RefreshAll()
    local again = gns.Bars:Get("cd").icons[1]
    Equal(gns.Get("readyGlow") .. " " .. tostring(again.glow.proc) .. " " .. tostring(S[again.glow].shown) .. " " .. tostring(again.glows.proc),
        "edge nil true nil", "kept over a reload: the edge from the start, Blizzard's never even made")
    saved.readyGlow = "sparkles"
    Environment(true)
    BlizzardFrames()
    gns = LoadAll(saved)
    usable[7384] = true
    gns.Bars:RefreshAll()
    Equal(gns.Get("readyGlow") .. " " .. tostring(gns.Bars:Get("cd").icons[1].glow.proc), "proc true", "anything else saved: Proc glow")

    -- Without Blizzard's template, both choices use the edge, made once.
    Environment()
    BlizzardFrames()
    local create = _G.CreateFrame
    local tried = 0
    _G.CreateFrame = function(kind, name, parent, template)
        if template == "ActionButtonSpellAlertTemplate" then
            tried = tried + 1
            error("no such template")
        end
        return create(kind, name, parent, template)
    end
    gns = LoadAll({ useBars = true })
    gns.Bars:Assign("Overpower", "cd")
    usable[7384] = true
    gns.Bars:RefreshAll()
    local bare = gns.Bars:Get("cd").icons[1]
    local fallback = bare.glow
    Equal(tostring(fallback.proc) .. " " .. tostring(S[fallback].shown) .. " " .. tostring(bare.glows.proc == fallback) .. " " .. tried,
        "nil true true 1", "no template: the plain edge, lit, standing in for Proc glow")
    gns.Set("readyGlow", "edge")
    gns.Bars:ApplyGlow()
    gns.Set("readyGlow", "proc")
    gns.Bars:ApplyGlow()
    Equal(tostring(bare.glow == fallback) .. " " .. tostring(S[fallback].shown) .. " " .. tried, "true true 1",
        "either choice: the same edge, still lit, the template not tried again")
    usable[7384] = nil
    Equal(#printed, 0, "no errors from the ready glow")
end)()

-- Forever Enhanced Cooldown Pulse beside it: one pulse at a time --------------------------------------
-- That addon is this pulse on its own. With both installed only one pulses:
-- whichever is on keeps it, the other's tick greyed out with a note saying
-- where it runs and how to swap; with both saved as on, this one wins. Both
-- join one shared table, ForeverPulseLink, and tell each other when their
-- ticks change, so nothing needs a reload. That addon is stood in for here
-- (on the link at rank 1, its tick settable), and run as its own Link.lua
-- when it's beside this one.

;(function()
    local MANAGER, PULSE = "ForeverEnhancedCooldownManager", "ForeverEnhancedCooldownPulse"
    local NOTE = "Cooldown pulse is on in Forever Enhanced Cooldown Pulse. Turn it off there to use this one."
    local RUNNING = "Running in Forever Enhanced Cooldown Pulse instead."
    local ABOUT = "A big icon in the middle of your screen the moment a cooldown is ready, in a fight too. It never takes the mouse."
    local OFF = "Off. Tick the box below to start."
    local ON = "2 cooldowns pulse when they're ready."
    -- Forever Enhanced Cooldown Pulse, stood in for: its tick, and how often it's told something changed.
    local function Other(on)
        local other = { on = on, told = 0 }
        other.owner = { name = "Forever Enhanced Cooldown Pulse", rank = 1,
            IsOn = function() return other.on end,
            Refresh = function() other.told = other.told + 1 end }
        return other
    end
    local function Join(other) ForeverPulseLink:Register(PULSE, other.owner) end
    -- Its tick clicked: saved, then the others told.
    local function Flip(other, on)
        other.on = on
        ForeverPulseLink:Notify(PULSE)
    end
    -- A login with these settings and the link as left (nil: none yet),
    -- Barkskin and Bash ticked, the window open on the page.
    local function Start(saved, link)
        Environment()
        BlizzardFrames()
        PulseGame()
        _G.FECMFrame, _G.FECMTour, _G.FECMNotes = nil, nil, nil
        _G.ForeverPulseLink = link
        local lns = LoadAll(saved)
        Tick(lns.Pulse)
        lns.SetPulsePick("Barkskin", true)
        lns.SetPulsePick("Bash", true)
        lns.Pulse:Apply()
        lns.ShowWindow()
        FECMFrame:Select("pulse")
        return lns, FECMFrame.pages.pulse
    end
    -- The tick (ticked, usable, alpha), the title row, and how many cooldowns are watched.
    local function State(lns, page)
        return tostring(page.master.checked) .. " " .. tostring(page.master.usable) .. " " .. S[page.master].alpha .. " | "
            .. S[page.status].text .. " | " .. (lns.Pulse:Watchers())
    end
    local function Runner() return tostring((ForeverPulseLink:Runner())) end
    -- A watched cooldown done, past the quiet after logging in: what pulses.
    local function Ready(lns, key)
        clock = clock + 5
        local _, list = lns.Pulse:Watchers()
        if list[key] then Done(list[key].cooldown) end
        local showing = tostring((lns.Pulse:Showing()))
        Finish(lns.Pulse)
        return showing
    end

    -- Absent: the pulse runs here, as ever.
    local lns, page = Start({ pulse = true }, nil)
    local link = ForeverPulseLink
    local entry, joined = link.owners[MANAGER], 0
    for _ in pairs(link.owners) do joined = joined + 1 end
    Equal(State(lns, page), "true true 1 | " .. ON .. " | 2", "no Forever Enhanced Cooldown Pulse: the pulse runs here, its tick free")
    Equal(link.version .. " " .. joined .. " " .. entry.name .. " " .. entry.rank .. " " .. tostring(entry.IsOn()) .. " " .. Runner(),
        "1 1 Forever Enhanced Cooldown Manager 2 true " .. MANAGER, "on the link by its folder name, with its title, rank 2 and its tick")
    Equal(tostring(lns.Pulse:Elsewhere()) .. " " .. tostring(lns.Pulse:Note()) .. " | " .. Note(page.master), "nil nil | " .. ABOUT,
        "its tick says what it does")
    Equal(Ready(lns, "Barkskin"), "Barkskin", "a cooldown done pulses")
    local added = {}
    for _, name in ipairs(ADDED_GLOBALS) do
        -- Its saved settings, and its API for other addons (ForeverEnhancedCooldownManagerAPI, RaidTimers.lua).
        if not (name:match("^FECM") or name:match("^SLASH_FECM%d$") or name:match("^ForeverEnhancedCooldownManager%u%u")) then
            added[#added + 1] = name
        end
    end
    Equal(#ADDED_GLOBALS > 5 and table.concat(added, ","), "ForeverPulseLink",
        "in the game's global space, only the addon's own names and the link: none to clash with Forever Enhanced Cooldown Pulse's")

    -- Present and on, this one off: it joins while the window is open, and this tick greys out at once.
    lns, page = Start({ pulse = false }, nil)
    Equal(State(lns, page), "false true 1 | " .. OFF .. " | 0", "off on its own: its tick free")
    local other = Other(true)
    Join(other)
    Equal(State(lns, page) .. " | " .. Runner(), "false false 0.35 | " .. RUNNING .. " | 0 | " .. PULSE,
        "Forever Enhanced Cooldown Pulse joins with its pulse on: it runs there, this tick greys out at once, the title row says so")
    Equal(Note(page.master) .. " | " .. tostring(Last(page.master, "SetEnabled")) .. " " .. tostring(Last(page.master, "SetMotionScriptsWhileDisabled")),
        NOTE .. " | false true", "unclickable, its hover note saying where the pulse runs and how to swap")
    local told = other.told
    page.master:Click()
    Equal(tostring(lns.Get("pulse")) .. " " .. tostring(page.master.checked) .. " " .. (other.told - told) .. " " .. (lns.Pulse:Watchers()),
        "false false 0 0", "clicked anyway: nothing changes, nothing is told, nothing watched")
    local footer = S[FECMFrame.note]
    Equal(tostring(Wide(NOTE, footer.template) <= 2 * footer.width), "true", "the note fits two lines of the footer")
    -- The ? walks the page: its first step says where the pulse runs, and that there's nothing to do here.
    local basics = 0
    for _, step in ipairs(lns.Tour:News("0.9.0")) do
        local text = type(step.text) == "function" and step.text() or step.text
        if step.version == "1.0.0" then basics = math.max(basics, #text) end
    end
    FECMFrame.help:Click()
    local box = FECMTour
    local said = S[box.text].text
    local step = "Cooldown pulse is on in Forever Enhanced Cooldown Pulse, so it runs there and this tick waits."
        .. " Turn it off there to use this one."
    Equal(S[box.title].text .. " | " .. tostring(said:find(step, 1, true) == 1) .. " "
        .. tostring(said:find("Nothing to do here while it runs there.", 1, true) ~= nil) .. " " .. tostring(#step <= basics) .. " "
        .. tostring(step:find("\226\128\148", 1, true)) .. " | " .. BoxFits(page), "TURN IT ON | true true true nil | ",
        "the ? on the page: Turn it on says it runs there, nothing to do here, plain and short, its box on the page")
    box.skip:Click()

    -- Toggled there, live: greyed and freed at once, no reload.
    Flip(other, false)
    Equal(State(lns, page) .. " | " .. Runner(), "false true 1 | " .. OFF .. " | 0 | nil", "turned off there: this tick free again at once")
    Flip(other, true)
    Equal(State(lns, page), "false false 0.35 | " .. RUNNING .. " | 0", "and on again: greyed again at once")
    Flip(other, false)

    -- Present and off: this tick is free, and clicking it tells that addon at once.
    told = other.told
    page.master:Click()
    Equal((other.told - told) .. " | " .. State(lns, page) .. " | " .. Runner(), "1 | true true 1 | " .. ON .. " | 2 | " .. MANAGER,
        "ticked on here: Forever Enhanced Cooldown Pulse is told at once, and the pulse runs here")
    Equal(Ready(lns, "Bash"), "Bash", "and pulses here")
    -- On here, then on there too: this one keeps it.
    Flip(other, true)
    Equal(State(lns, page) .. " | " .. Runner(), "true true 1 | " .. ON .. " | 2 | " .. MANAGER,
        "turned on there while this one is on: this one keeps it, its tick free")
    Equal(Ready(lns, "Barkskin"), "Barkskin", "and still pulses here")
    page.master:Click()
    Equal(State(lns, page) .. " | " .. Runner() .. " " .. tostring(lns.Get("pulse")), "false false 0.35 | " .. RUNNING .. " | 0 | " .. PULSE .. " false",
        "turned off here: it runs there, and this tick greys out")
    Equal(Ready(lns, "Barkskin"), "nil", "a cooldown done now pulses only there, never here too")

    -- Both saved as on (a player with both, or one updating from 1.5.0): this one wins, whichever loads first.
    other = Other(true)
    lns, page = Start({ pulse = true }, { owners = { [PULSE] = other.owner } })
    Equal(other.told .. " | " .. State(lns, page) .. " | " .. Runner(), "1 | true true 1 | " .. ON .. " | 2 | " .. MANAGER,
        "that addon's link made first: this one joins it and is heard; both on, this one wins, its tick free")
    Equal(Ready(lns, "Barkskin"), "Barkskin", "and it pulses here")
    other = Other(true)
    lns, page = Start({ pulse = true }, nil)
    Join(other)
    Equal(State(lns, page) .. " | " .. Runner(), "true true 1 | " .. ON .. " | 2 | " .. MANAGER, "that one joining after: this one still wins")
    told = other.told
    page.master:Click()
    Equal((other.told - told) .. " | " .. State(lns, page) .. " | " .. Runner(), "1 | false false 0.35 | " .. RUNNING .. " | 0 | " .. PULSE,
        "turned off here: that one is told and takes over, and this tick greys out")
    Flip(other, false)
    Equal(State(lns, page) .. " | " .. tostring(lns.Get("pulse")), "false true 1 | " .. OFF .. " | 0 | false",
        "turned off there too: this tick free again, still off")

    -- One whose calls fail breaks nothing here; a link a newer version left keeps its own code.
    lns, page = Start({ pulse = false }, nil)
    ForeverPulseLink:Register(PULSE, { name = "Broken", rank = 5, IsOn = function() error("broken") end,
        Refresh = function() error("broken") end })
    Equal(State(lns, page), "false true 1 | " .. OFF .. " | 0", "an addon whose calls fail counts as off: this tick free")
    page.master:Click()
    Equal(State(lns, page) .. " | " .. #printed, "true true 1 | " .. ON .. " | 2 | 0", "ticked: the pulse runs here, the failing call passed over")
    local calls = {}
    local newer = { version = 2, owners = {} }
    function newer:Register(key, owner)
        calls[#calls + 1] = "Register " .. key
        self.owners[key] = owner
    end
    function newer:Notify(from) calls[#calls + 1] = "Notify " .. from end
    function newer:Runner() return nil end
    local functions = { newer.Register, newer.Notify, newer.Runner }
    lns, page = Start({ pulse = false }, newer)
    page.master:Click()
    Equal(tostring(ForeverPulseLink == newer) .. " " .. newer.version .. " "
        .. tostring(newer.Register == functions[1] and newer.Notify == functions[2] and newer.Runner == functions[3]) .. " | "
        .. table.concat(calls, ", "), "true 2 true | Register " .. MANAGER .. ", Notify " .. MANAGER,
        "a link from a newer version: kept, its own code used to join and to tell")
    Equal(State(lns, page), "true true 1 | " .. ON .. " | 2", "its Runner naming none: ticked on, the pulse runs here")
    lns, page = Start({ pulse = true }, "left over")
    Equal(type(ForeverPulseLink) .. " " .. tostring(ForeverPulseLink.owners[MANAGER] ~= nil) .. " | " .. State(lns, page),
        "table true | true true 1 | " .. ON .. " | 2", "something else under its name: a link made in its place")

    -- The real thing, when it's beside this addon: its Link.lua, run as its own.
    local chunk = loadfile("../ForeverEnhancedCooldownPulse/Link.lua")
    if chunk then
        lns, page = Start({ pulse = true }, nil)
        local theirs = { TITLE = "Forever Enhanced Cooldown Pulse", on = true }
        function theirs.Get(key) if key == "pulse" then return theirs.on end end
        chunk(PULSE, theirs)
        theirs.Link:Start()
        local L = theirs.Link
        local function Theirs() return tostring(L:Runs()) .. " " .. tostring(L:Note()) .. " " .. tostring(S[L.watcher].shown) end
        Equal(State(lns, page) .. " | " .. Theirs(), "true true 1 | " .. ON .. " | 2 | false Cooldown pulse is on in Forever Enhanced"
            .. " Cooldown Manager. Turn it off there to use this one. false",
            "its own Link.lua, both on: this one runs; there, it waits with the note, never reading this one's settings")
        page.master:Click()
        Equal(State(lns, page) .. " | " .. Theirs(), "false false 0.35 | " .. RUNNING .. " | 0 | true nil false",
            "turned off here: it runs there at once, this tick greyed")
        theirs.on = false
        L:Changed()
        Equal(State(lns, page) .. " | " .. Theirs(), "false true 1 | " .. OFF .. " | 0 | false nil false", "turned off there: this tick free")
        page.master:Click()
        theirs.on = true
        L:Changed()
        Equal(State(lns, page) .. " | " .. Theirs(), "true true 1 | " .. ON .. " | 2 | false Cooldown pulse is on in Forever Enhanced"
            .. " Cooldown Manager. Turn it off there to use this one. false", "both on again: this one keeps it")
        Equal(Ready(lns, "Bash"), "Bash", "and pulses here")
    else
        io.write("Forever Enhanced Cooldown Pulse isn't beside this addon: its own Link.lua not run.\n")
    end
    _G.ForeverPulseLink = nil
    Equal(#printed, 0, "no errors beside Forever Enhanced Cooldown Pulse")
end)()

Equal(#printed, 0, "no errors")

print = _G.print
Equal(SecretMisuse[1], nil, "no secret misused anywhere")
io.write("Cooldown pulse checks passed: " .. checks .. " assertions.\n")
