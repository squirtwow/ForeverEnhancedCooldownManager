-- Run the actual bars files (Core, Style, Spells, Buffs, Bars, the window) against a
-- mock game: spellbook ranks, secret cooldowns in combat, usable and range
-- tints, showing and hiding, dragging, settings kept over a reload, and the panel.
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

-- Spellbook: one entry per spell, highest rank -----------------------------------------

Environment()
local ns = Load(nil)
local B = ns.Bars
-- The next frame (for the loaded bars, or these): the icon refreshes asked
-- for since the last one happen now, once. A global, as this file's main
-- chunk has no room for another local.
function NextFrame(bars)
    local driver = (bars or ns.Bars).driver
    local run = driver and S[driver].scripts.OnUpdate
    if run then run(driver, 0) end
end
-- The next frame for the timers queued after from (the bars redrawn once
-- after a spellbook change, say): each runs now, once.
function Later(from)
    for i = from + 1, #timers do timers[i]() end
end
-- An event, then the next frame for what it queued.
function Settle(event, ...)
    local from = #timers
    Fire(event, ...)
    Later(from)
end
-- Gear changed, as the game says, and the rebuild it waits for: the timers
-- it queued run.
function GearChanged()
    local from = #timers
    Fire("PLAYER_EQUIPMENT_CHANGED")
    for i = from + 1, #timers do timers[i]() end
end
-- How often a window is on the game's list of windows Escape closes.
function EscapeListed(name)
    local count = 0
    for _, listed in ipairs(UISpecialFrames) do
        if listed == name then count = count + 1 end
    end
    return count
end
-- With your bars off (the default) nothing wants your spellbook at login, so
-- it isn't read; it's read the first time something looks in it.
Equal(#ns.Spells:List(), 0, "bars off: your spellbook and bags aren't read at login")
local list = ns.Spells:Fresh()
Equal(#list, 11, "Attack, Walk on Air, Moonfire, Wrath, Thorns, Overpower, two druid procs, then the healthstone and"
    .. " potion families; passive and future spells left out")
local moonfire = ns.Spells:Find("Moonfire")
Equal(moonfire.spellID, 8924, "Moonfire uses the highest rank")
Equal(moonfire.rankText, "Rank 2", "shows that rank")
Equal(moonfire.line, "Balance", "grouped by spellbook tab")
Equal(ns.Spells:Find("Natural Weapons"), nil, "passives left out")
Equal(table.concat(ns.Spells:Find("Thorns").ids, ","), "467,782,1075,8914,9756,9910", "every rank in the game counts for buff matching")
Equal(ns.Spells:Find("Thorns").spellID, 782, "while the icon uses your highest known rank")
Equal(table.concat(ns.Spells:Find("Walk on Air").ids, ","), "1259416,1308663", "a racial's buff matches both of its IDs")
Equal(ns.Spells:Find("Walk on Air").spellID, 1259416, "its cooldown uses the spellbook ID")
Equal(ns.Spells:Resolve("blood fury"), "Blood Fury", "any race's racial can be added by name")
local cc = ns.Spells:Find("Clearcasting")
Equal(cc and cc.kind == "proc" and cc.line, "Procs", "class procs listed under Procs")
Equal(cc.ids[1], 16870, "with their spell IDs")
Equal(list[8].name .. " " .. list[9].line, "Nature's Grace Items", "procs come after your spells, before your items")

-- Off by default ------------------------------------------------------------------------

Equal(B:Enabled(), false, "own bars start off")
Equal(tostring(B:Get("cd")) .. " " .. tostring(B:Get("buff")) .. " " .. tostring(B.driver), "nil nil nil",
    "no bar shown while off: none is even made, nor their driver")

-- Assigning spells ---------------------------------------------------------------------

Equal(B:Assign("Moonfire", "cd"), true, "spell added")
Equal(B:Assign("Overpower", "cd"), true, "second spell added")
Equal(table.concat(ns.BarData("cd").spells, ","), "Moonfire,Overpower", "kept in order")
B:Assign("Moonfire", "util")
Equal(table.concat(ns.BarData("cd").spells, ","), "Overpower", "a spell sits on one bar at a time")
Equal(table.concat(ns.BarData("util").spells, ","), "Moonfire", "moved to Utility")
B:Assign("Moonfire", nil)
Equal(#ns.BarData("util").spells, 0, "unticking takes it off")
B:Assign("Moonfire", "cd")
B:Assign("Wrath", "cd")
B:Move("cd", 3, -1)
Equal(table.concat(ns.BarData("cd").spells, ","), "Overpower,Wrath,Moonfire", "moved up")
B:Move("cd", 1, -1)
Equal(ns.BarData("cd").spells[1], "Overpower", "the top spell can't move up")
B:Remove("cd", 2)
Equal(table.concat(ns.BarData("cd").spells, ","), "Overpower,Moonfire", "removed")
B:SetOption("cd", "size", 100)
Equal(ns.BarData("cd").size, 64, "size kept within limits")
B:SetOption("cd", "size", 36)

-- Showing -----------------------------------------------------------------------------

ns.Set("useBars", true)
B:Rebuild()
local cd, util = B:Get("cd"), B:Get("util")
Equal(S[cd].shown, true, "a bar with spells shows")
Equal(S[util].shown, false, "an empty bar stays hidden")
Equal(cd.count, 2, "two icons")
Equal(S[cd].width, 2 * 36 + 4, "bar width fits its icons")
local over, moon = cd.icons[1], cd.icons[2]
Equal(over.edge, nil, "no frame around the icon")
Equal(S[over.texture].last.SetAllPoints ~= nil, true, "the art fills the whole icon")
Equal(Last(over.texture, "SetTexCoord"), .08, "icon art zoomed past its bevel")
Equal(Last(over.cooldown, "SetCountdownFont"), "FECMFont18", "big countdown, half the icon's height")
Equal(Last(over.count, "SetFontObject"), "FECMFont13", "item counts sized to match")
B:SetOption("cd", "size", 54)
Equal(Last(over.cooldown, "SetCountdownFont"), "FECMFont27", "the numbers grow with the icon")
B:SetOption("cd", "size", 36)
Equal(over.spellID, 7384, "Overpower icon")
Equal(moon.spellID, 8924, "Moonfire icon at its highest rank")
Equal(S[over].last.EnableMouse[1], false, "icons never take the mouse")
Equal(S[over.cooldown].last.SetSwipeTexture[1], "Interface\\Buttons\\WHITE8X8", "square sweep")
local p = S[cd].points[1]
Equal(p[1] == "BOTTOM" and p[4] == 0 and p[5], 190, "starts above the action bar")

-- Icon states --------------------------------------------------------------------------

active = SECRET
B:RefreshAll()
Equal(S[moon.texture].desaturated, SECRET, "the secret cooldown state goes straight to the game")
Equal(Last(moon.cooldown, "SetCooldownFromDurationObject") ~= nil, true, "sweep fed from the duration object")
Equal(S[moon].alpha .. " " .. ns.BarData("cd").whenReady, "1 show", "shown in full while ready unless you choose otherwise")
B:SetOption("cd", "whenReady", "hide")
moon = cd.icons[2]
Equal(tostring(S[moon].alphaFrom) .. " " .. S[moon].alphaIf, "secret nil nil",
    "hide when ready also uses the secret state as it is, with the game's own 0 while ready")
-- While the bars are being arranged, every icon shows.
S[moon].alpha, S[moon].alphaFrom = nil, nil
B:SetUnlocked(true)
Equal(S[moon].alpha == 1 and S[moon].alphaFrom == nil, true, "unlocked: shown even when ready, to see while moving it")
B:SetUnlocked(false)
Equal(S[moon].alphaFrom, SECRET, "locked again: hidden when ready")
S[moon].alpha, S[moon].alphaFrom = nil, nil
EditModeManagerFrame:Show()
Equal(S[moon].alpha == 1 and S[moon].alphaFrom == nil, true, "in Edit Mode too")
EditModeManagerFrame:Hide()
Equal(S[moon].alphaFrom, SECRET, "and hidden when ready once Edit Mode closes")
-- Dim when ready: the same secret state, never read here, so the game picks
-- the alpha: in full while cooling down, 40% while ready.
S[moon].alpha, S[moon].alphaFrom = nil, nil
B:SetOption("cd", "whenReady", "dim")
Equal(tostring(S[moon].alphaFrom) .. " " .. S[moon].alphaIf .. " " .. tostring(S[moon].alpha), "secret 1 0.4 nil",
    "dim when ready: the secret state goes to the game as it is, 1 while cooling down and 0.4 while ready")
Equal(ns.BarData("util").whenReady, "show", "each bar has its own choice")
active = false
B:RefreshAll()
Equal(S[moon].alpha, .4, "a ready spell dims")
active = true
B:RefreshAll()
Equal(S[moon].alpha, 1, "and is in full while it cools down")
active = false
B:SetUnlocked(true)
Equal(S[moon].alpha, 1, "unlocked: in full even when ready, to see while moving it")
B:SetUnlocked(false)
Equal(S[moon].alpha, .4, "locked again: dimmed when ready")
EditModeManagerFrame:Show()
Equal(S[moon].alpha, 1, "in Edit Mode too")
EditModeManagerFrame:Hide()
Equal(S[moon].alpha, .4, "and dimmed once Edit Mode closes")
B:SetOption("cd", "whenReady", "show")
Equal(S[moon].alpha, 1, "Show: in full again")

usable[8924], noMana[8924] = false, true
B:RefreshAll()
Equal(S[moon.texture].tint[3] == 1 and S[moon.texture].tint[1], .5, "blue when low on mana")
usable[8924], noMana[8924] = false, false
B:RefreshAll()
Equal(S[moon.texture].tint[1], .4, "grey when not usable")
usable[8924] = nil
range[8924] = false
B:RefreshAll()
Equal(S[moon.texture].tint[1], 1, "range ignored with no target")
target = true
B:RefreshAll()
Equal(S[moon.texture].tint[1] == .64 and S[moon.texture].tint[2], .15, "red when out of range")
range[8924] = SECRET
B:RefreshAll()
Equal(S[moon.texture].tint[1], 1, "a hidden range answer is never read")
target = false

usable[7384] = true
B:RefreshAll()
do
local glow = over.glow
Equal(tostring(S[glow].shown) .. " " .. tostring(S[glow].template) .. " " .. glow.ProcStartAnim.plays,
    "true ActionButtonSpellAlertTemplate 1", "reactive ability ready: Blizzard's proc glow, its burst played")
Equal(tostring(S[glow].parent == over.top) .. " " .. tostring(S[over.top].parent == over) .. " " .. S[glow].points[1][1] .. " "
    .. tostring(S[glow].points[1][2] == over), "true true CENTER true",
    "over the icon and centred on it, so the icons beside it and borders never cover it (a player saw only its top)")
local width, height = over:GetSize()
Equal(string.format("%g %g %g", width, S[glow].width / width, S[glow].height / height), width .. " 1.4 1.4",
    "spreading past the icon as Blizzard sizes it on its action bars")
B:RefreshAll()
Equal(glow.ProcStartAnim.plays, 1, "still ready: no second burst")
glow:Hide()
glow.ProcLoop:Stop()
glow:Show()
Equal(tostring(glow.ProcLoop.playing), "true", "hidden with its bar and shown again: the loop plays again")
Equal(S[moon.glow].shown, false, "normal spells never glow")
usable[7384] = false
B:RefreshAll()
Equal(tostring(S[glow].shown) .. " " .. tostring(glow.ProcStartAnim.playing) .. " " .. tostring(glow.ProcLoop.playing),
    "false false false", "the glow goes when it isn't usable, burst and loop stopped (Blizzard's OnHide leaves the loop running)")
usable[7384] = true
B:RefreshAll()
Equal(tostring(S[glow].shown) .. " " .. glow.ProcStartAnim.plays .. " " .. tostring(glow.ProcLoop.playing), "true 2 false",
    "usable again: a new burst, no old loop playing over it")
-- /ccm debug: a report to copy, with the reactive icon, the game's answer and its glow.
SlashCmdList.FECM("debug")
local report = S[FECMDebugFrame.edit].text or ""
Equal(tostring(S[FECMDebugFrame].shown) .. " " .. tostring(report:find("Overpower | spell 7384 | reactive true | usable true, no mana", 1, true) ~= nil)
    .. " " .. tostring(report:find("glow true (proc, loop", 1, true) ~= nil), "true true true",
    "/ccm debug: the reactive icon, the game's usable answer and its glow, ready to copy")
Equal(tostring(report:find("ready glow proc", 1, true) ~= nil), "true", "and the ready glow picked on the Look page")
-- On the /ccm window's layer and raised, so it never opens behind it.
local debugFrame, debugEdit = FECMDebugFrame, FECMDebugFrame.edit
Equal(Last(debugFrame, "SetFrameStrata") .. " " .. tostring(Last(debugFrame, "SetToplevel")) .. " " .. tostring(S[debugFrame].last.Raise ~= nil),
    "FULLSCREEN_DIALOG true true", "the debug box on the /ccm window's layer, raised as it shows")
-- A click in the text, or coming back to it, selects it all again.
for _, script in ipairs({ "OnMouseUp", "OnEditFocusGained" }) do
    S[debugEdit].last.HighlightText = nil
    S[debugEdit].scripts[script](debugEdit)
    Equal(script .. " " .. tostring(S[debugEdit].last.HighlightText ~= nil), script .. " true", "the whole report selected again, ready to copy")
end
FECMDebugFrame:Hide()
-- Ready glow (Look page): Gold edge swaps every icon's glow at once, the one
-- lit now too, Blizzard's put out with its burst and loop stopped; Proc glow
-- brings Blizzard's back, lit with a new burst. Each is made once and kept.
Equal(ns.Get("readyGlow"), "proc", "Blizzard's proc glow by default")
ns.Set("readyGlow", "edge")
B:ApplyGlow()
local edge = over.glow
local strips = {}
for _, obj in ipairs(objects) do
    if S[obj].parent == edge and S[obj].kind == "Texture" then strips[#strips + 1] = table.concat(S[obj].last.SetColorTexture, ",") end
end
Equal(tostring(edge ~= glow) .. " " .. tostring(edge.proc) .. " " .. tostring(S[edge].template) .. " " .. tostring(S[edge].parent == over.top)
    .. " " .. tostring(S[edge].shown) .. " " .. table.concat(strips, " "), "true nil nil true true 1,0.82,0,1 1,0.82,0,1 1,0.82,0,1 1,0.82,0,1",
    "Gold edge: the lit icon's glow swapped for a plain gold edge over it, four strips, lit at once")
Equal(tostring(S[glow].shown) .. " " .. tostring(glow.ProcStartAnim.playing) .. " " .. tostring(glow.ProcLoop.playing) .. " "
    .. tostring(glow.looping), "false false false nil", "Blizzard's put out, burst and loop stopped, so it isn't left stuck")
Equal(tostring(S[moon.glow].shown) .. " " .. tostring(moon.glow == moon.glows.edge) .. " " .. tostring(moon.glows.proc ~= nil),
    "false true true", "an unlit icon swaps too, and stays out")
B:RefreshAll()
Equal(tostring(over.glow == edge) .. " " .. tostring(S[edge].shown) .. " " .. glow.ProcStartAnim.plays, "true true 2",
    "refreshed while ready: the edge stays lit, Blizzard's not played again")
usable[7384] = false
B:RefreshAll()
Equal(S[edge].shown, false, "the edge goes once it isn't usable")
usable[7384] = true
B:RefreshAll()
Equal(S[edge].shown, true, "and comes back when it is")
ns.Set("readyGlow", "proc")
B:ApplyGlow()
local size = over:GetWidth()
Equal(tostring(over.glow == glow) .. " " .. tostring(S[glow].shown) .. " " .. glow.ProcStartAnim.plays .. " " .. tostring(glow.looping)
    .. " " .. tostring(S[edge].shown) .. " " .. string.format("%g", S[glow].width / size), "true true 3 true false 1.4",
    "Proc glow again: Blizzard's own back, lit with a new burst and sized round the icon; the edge out")
B:ApplyGlow()
Equal(glow.ProcStartAnim.plays, 3, "picked again: nothing changes")
usable[7384] = false
B:RefreshAll()
end
usable[7384] = SECRET
B:RefreshAll()
Equal(S[over.glow].shown, false, "a hidden usable answer is never read")
usable[7384] = nil
-- Procs: lit whenever the game lights the spell on your action bars, any
-- spell (Moonfire here), as its own action buttons ask.
do
    local lit = {}
    _G.C_SpellActivationOverlay = { IsSpellOverlayed = function(id) return lit[id] end }
    usable[7384] = false
    lit[moon.spellID] = true
    B:RefreshAll()
    Equal(tostring(S[moon.glow].shown) .. " " .. tostring(S[over.glow].shown), "true false",
        "a spell the game lights up on your action bars glows here too, reactive or not")
    lit[moon.spellID] = SECRETS.boolean
    B:RefreshAll()
    Equal(S[moon.glow].shown, false, "a hidden answer is never read")
    lit[moon.spellID] = false
    B:RefreshAll()
    Equal(S[moon.glow].shown, false, "and it goes when the game puts it out")
    local listening = 0
    for _, f in ipairs(frames) do
        if S[f].events.SPELL_ACTIVATION_OVERLAY_GLOW_SHOW and S[f].events.SPELL_ACTIVATION_OVERLAY_GLOW_HIDE then listening = listening + 1 end
    end
    Equal(listening, 1, "told the moment the game lights one or puts it out")
    _G.C_SpellActivationOverlay = nil
    usable[7384] = nil
end
Equal(#printed, 0, "no errors")

-- Combat-only bars and moving -----------------------------------------------------------

B:SetOption("cd", "outOfCombat", "hide")
Equal(S[cd].shown, false, "only in combat: hidden out of combat")
Fire("PLAYER_REGEN_DISABLED")
Equal(S[cd].shown, true, "shown in combat")
Fire("PLAYER_REGEN_ENABLED")
Equal(S[cd].shown, false, "hidden again after")
B:SetUnlocked(true)
Equal(S[cd].shown and S[util].shown, true, "unlocked: every bar shows, even empty ones")
Equal(S[cd.mover].shown, true, "with its mover")
Equal(S[util].width, 3 * 36 + 2 * 4, "an empty bar keeps room to drag")
S[cd].cx, S[cd].cy = 520.04, 300
S[cd.mover].scripts.OnDragStart()
S[cd.mover].scripts.OnDragStop()
Equal(ns.BarData("cd").x, 20, "position saved from the centre")
Equal(ns.BarData("cd").y, -82, "by the top edge, so new rows grow down from it")
p = S[cd].points[1]
Equal(p[1] == "TOP" and p[4] == 20 and p[5], -82, "placed where it was dropped")
B:SetOption("cd", "outOfCombat", "show")
ns.Set("useBars", false)
B:Rebuild()
Equal(B:IsUnlocked(), false, "turning the bars off locks them")
Equal(S[cd].shown, false, "and hides them")
ns.Set("useBars", true)
B:Rebuild()

-- A new rank moves the bar onto it ------------------------------------------------------

Book(true)
do
    -- Several at once (a form shift): the bars laid out once, on the next
    -- frame, your spellbook read once.
    local from, scan, scans = #timers, ns.Spells.Scan, 0
    ns.Spells.Scan = function(...) scans = scans + 1 return scan(...) end
    Fire("SPELLS_CHANGED")
    Fire("SPELLS_CHANGED")
    local before = cd.icons[2].spellID
    Later(from)
    ns.Spells.Scan = scan
    Equal(before .. " " .. cd.icons[2].spellID .. " " .. scans, "8924 8925 1",
        "trained rank 3: the bar uses it on the next frame, laid out and read once for both changes")
end
Equal(ns.BarData("cd").spells[2], "Moonfire", "saved setup unchanged")

-- Kept over a reload ----------------------------------------------------------------------
-- Everything lives in the saved settings; nothing goes into the game's own.

do
    Equal(next(cvars), nil, "no game settings written")
    local saved = ForeverEnhancedCooldownManagerDB
    Environment(true)
    ns = Load(saved)
    B = ns.Bars
    Equal(B:Enabled(), true, "bars on again after a reload")
    Equal(table.concat(ns.BarData("cd").spells, ","), "Overpower,Moonfire", "bar spells kept")
    Equal(ns.BarData("cd").x, 20, "bar position kept")
    Equal(ns.BarData("util").x, nil, "unmoved bar keeps its default spot")
    Equal(B:Get("cd").count, 2, "and drawn")
    Equal(ns.firstInstall, false, "a kept settings file isn't a first install")

    -- Anything unexpected in the saved settings is put right at load.
    Environment()
    ns = Load({ useBars = true, bars = { cd = { size = 9999, spells = { "A", 7, "", "B" }, x = "nope", y = 3, hideReady = "maybe" },
        util = { whenReady = "fade" }, evil = { size = 3 } } })
    local data = ns.BarData("cd")
    Equal(data.size, 64, "bad sizes clamped")
    Equal(table.concat(data.spells, ","), "A,B", "only names kept in a list")
    Equal(data.x, nil, "bad positions dropped")
    Equal(data.whenReady .. " " .. ns.BarData("util").whenReady, "show show", "bad flags and choices off")
    Equal(ns.BarData("evil"), nil, "unknown bars ignored")

    -- Hide when ready was a tick before Dim joined it: a bar that hid its
    -- ready icons still does, and the old setting goes.
    Environment()
    ns = Load({ useBars = true, bars = { cd = { hideReady = true }, util = { hideReady = false }, buff = { whenReady = "dim", hideReady = true } } })
    Equal(ns.BarData("cd").whenReady .. " " .. ns.BarData("util").whenReady .. " " .. ns.BarData("buff").whenReady, "hide show dim",
        "hide when ready kept as Hide, off as Show, and a choice already made kept")
    Equal(rawget(ns.BarData("cd"), "hideReady"), nil, "the old setting is gone")
end

-- Reactive abilities ----------------------------------------------------------------------
-- The gold edge goes on each spell the game data gates on something happening
-- in the fight (ns.REACTIVE, from Ranks.lua): after a dodge, parry or block, a
-- kill or an Enrage, or on a wounded target, and Overpower with the combo
-- point a dodge gives. Only while the game says it's usable: never while it
-- isn't, or while the answer is hidden. A spell gated by a stance (Intercept),
-- a Seal (Judgement), a form (Tiger's Fury) or an aura you put up yourself
-- (Swiftmend, Conflagrate, Rewind Time) never gets it.

do
    local REACTIVE = {
        { "Counterattack", 19306 }, { "Divine Grace", 1277370 }, { "Enraged Regeneration", 402913 }, { "Execute", 20658 },
        { "Hammer of Wrath", 24275 }, { "Mongoose Bite", 1495 }, { "Overpower", 7384 }, { "Raging Blow", 402911 },
        { "Revenge", 6572 }, { "Riposte", 14251 }, { "Victory Rush", 402927 },
    }
    local OTHERS = { { "Intercept", 20252 }, { "Judgement", 20271 }, { "Tiger's Fury", 5217 }, { "Swiftmend", 18562 },
        { "Conflagrate", 17962 }, { "Rewind Time", 401462 } }
    local listed, expected = {}, {}
    for name, value in pairs(ns.REACTIVE) do listed[#listed + 1] = name .. (value == true and "" or "=" .. tostring(value)) end
    table.sort(listed)
    for i, spell in ipairs(REACTIVE) do expected[i] = spell[1] end
    Equal(table.concat(listed, ", "), table.concat(expected, ", "),
        "the reactive abilities from the game data: these eleven, from five classes, and nothing else")

    -- All of them in the spellbook (Execute at rank 2, with rank 1 on the bar
    -- too), with the others, every one on the Cooldowns bar.
    Environment()
    local items = { { name = "Execute", subName = "Rank 1", spellID = 5308, iconID = 1 } }
    for _, spell in ipairs(REACTIVE) do
        items[#items + 1] = { name = spell[1], subName = spell[1] == "Execute" and "Rank 2" or "", spellID = spell[2], iconID = 1 }
    end
    for _, spell in ipairs(OTHERS) do items[#items + 1] = { name = spell[1], subName = "", spellID = spell[2], iconID = 1 } end
    book = { { name = "General", items = items } }
    local rns = Load({ useBars = true })
    local RB = rns.Bars
    local keys = {}
    for _, spell in ipairs(REACTIVE) do keys[#keys + 1] = spell[1] end
    keys[#keys + 1] = "Execute@1"
    for _, spell in ipairs(OTHERS) do keys[#keys + 1] = spell[1] end
    local added = 0
    for _, key in ipairs(keys) do
        if RB:Assign(key, "cd") then added = added + 1 end
    end
    local bar = RB:Get("cd")
    Equal(added .. " " .. bar.count, "18 18", "all eighteen on the bar")
    Equal(bar.icons[12].name .. " " .. bar.icons[12].spellID, "Execute@1 5308", "Execute's rank 1 on its own")
    local function Lit()
        local names = {}
        for i = 1, bar.count do
            if S[bar.icons[i].glow].shown then names[#names + 1] = bar.icons[i].name end
        end
        return table.concat(names, ", ")
    end
    local function Set(value, which)
        for _, spell in ipairs(which) do usable[spell[2]] = value end
    end
    local all = table.concat(expected, ", ") .. ", Execute@1"
    RB:RefreshAll()
    Equal(Lit(), all, "every reactive ability usable: each has the gold edge, a lower rank too; the others never")
    Set(false, REACTIVE)
    Set(false, OTHERS)
    usable[5308] = false
    RB:RefreshAll()
    Equal(Lit(), "", "none usable: no gold edge anywhere")
    Set(SECRET, REACTIVE)
    Set(SECRET, OTHERS)
    usable[5308] = SECRET
    RB:RefreshAll()
    Equal(Lit(), "", "a hidden usable answer is never read, so no gold edge")
    -- Each icon by its own answer: every other one usable.
    local odd = {}
    for i, spell in ipairs(REACTIVE) do
        usable[spell[2]] = i % 2 == 1
        if i % 2 == 1 then odd[#odd + 1] = spell[1] end
    end
    usable[5308] = false
    Set(true, OTHERS)
    RB:RefreshAll()
    Equal(Lit(), table.concat(odd, ", "), "each lit only while it's usable itself; the stance, Seal, form and own-aura spells, usable, never")
    -- In a fight, the same: the edge comes and goes with the game's own
    -- events, as the answer changes.
    Fire("PLAYER_REGEN_DISABLED")
    lockdown = true
    Set(true, REACTIVE)
    usable[5308] = true
    -- A cast's burst of events refreshes the icons once, on the next frame.
    cooldownCalls = {}
    for _, event in ipairs({ "SPELL_UPDATE_COOLDOWN", "SPELL_UPDATE_USABLE", "BAG_UPDATE_COOLDOWN", "SPELL_UPDATE_USABLE" }) do
        Fire(event)
    end
    local waiting = #cooldownCalls
    NextFrame(RB)
    NextFrame(RB)
    Equal(waiting .. " " .. #cooldownCalls .. " " .. Lit(), "0 18 " .. all,
        "in a fight: lit as each becomes usable, four events refreshing the 18 icons once, on the next frame")
    usable[7384] = false
    Fire("SPELL_UPDATE_USABLE")
    NextFrame(RB)
    Equal(Lit():find("Overpower", 1, true), nil, "and Overpower's goes once it's used")
    -- A new target: Execute and Hammer of Wrath follow its health.
    usable[20658], usable[5308], usable[24275] = false, false, false
    target = true
    Fire("PLAYER_TARGET_CHANGED")
    NextFrame(RB)
    Equal(Lit():find("Execute", 1, true) or Lit():find("Hammer", 1, true), nil, "a healthy new target: no edge on Execute or Hammer of Wrath")
    target = false
    lockdown = false
    Fire("PLAYER_REGEN_ENABLED")
    Equal(#printed, 0, "no errors from reactive abilities")
end

-- Buffs bar -------------------------------------------------------------------------------

Environment()
ns = Load({ useBars = true })
B = ns.Bars
local buffs = B:Get("buff")
watched[buffs] = true
Equal(#containers, 2, "one secure aura container for each aura bar")
local box = containers[1]
Equal(S[box].unit, "player", "watching your own buffs")
local slots = S[box].slots
Equal(slots.b16 ~= nil and slots.b17 == nil, true, "sixteen buff slots")
Equal(slots.b1.filter, "HELPFUL", "helpful auras only")
Equal(slots.b1.enabled, false, "slots start switched off")
Equal(tostring(InSight(buffs)) .. " " .. tostring(S[buffs].shown), "false true",
    "an empty Buffs bar stays out of sight: gone right out, never hidden, as it holds a container")
local b1 = slots.b1
Equal(S[b1.button].last.SetAllPoints[1], buffs.holders[1], "each slot follows the addon's own holder")
Equal(S[b1.button].last.EnableMouse[1], false, "slots never take the mouse")
Equal(b1.supplied.SetIcon ~= nil and b1.supplied.SetDurationCooldown ~= nil and b1.supplied.SetApplicationCount ~= nil, true, "icon, sweep and stack count supplied")
Equal(S[b1.supplied.SetDurationCooldown].last.SetSwipeTexture[1], "Interface\\Buttons\\WHITE8X8", "square sweep")
Equal(S[b1.supplied.SetDurationCooldown].last.SetReverse[1], true, "buff sweep runs the buff way")
Equal(S[b1.supplied.SetDurationCooldown].last.SetCountdownFont[1], "FECMFont18", "big buff timers")
Equal(Last(b1.supplied.SetIcon, "SetTexCoord"), .08, "buff icons zoomed like the rest")

local anchor = S[box].points[1]
Equal(#S[box].points == 1 and anchor[1] == "CENTER" and anchor[2] == buffs and anchor[3], "CENTER", "container held by its centre, so packed buffs stay centred")

-- Packed (the default): one group per buff, in order, only active ones shown.
local groups = S[box].groups
Equal(B:SetAura("buff", "Thorns", true), true, "Thorns ticked")
local g1 = groups.g1
Equal(g1 ~= nil and g1.enabled, true, "its group switched on")
Equal(g1.filter, "HELPFUL", "helpful auras only")
Equal(g1.max, 1, "one icon per group")
Equal(g1.filters.includeSpellIDs[467] and g1.filters.includeSpellIDs[9910], true, "any rank of Thorns")
Equal(g1.layout.layoutIndex, 1, "first in line")
Equal(S[g1.button].width == 36 and S[g1.button].height, 36, "group icons drawn at the base size")
Equal(g1.supplied.SetIcon ~= nil and g1.supplied.SetDurationCooldown ~= nil, true, "with icon and sweep")
Equal(slots.b1.enabled, false, "fixed slots stay off")
Equal(InSight(buffs), true, "the bar shows")
B:SetAura("buff", "Clearcasting", true)
Equal(groups.g2.filters.includeSpellIDs[16870] and groups.g2.layout.layoutIndex, 2, "a proc next in line")
Equal(groups.g3, nil, "groups made only as needed")
B:Move("buff", 2, -1)
Equal(groups.g1.filters.includeSpellIDs[16870] and groups.g2.filters.includeSpellIDs[467], true, "reordering reorders the groups")
B:SetOption("buff", "size", 44)
Equal(S[box].scale, 44 / 36, "icon size scales the packed row")
Equal(math.abs(groups.g1.layout.groupSpacing - 4 * 36 / 44) < 1e-9, true, "spacing kept in screen units")
B:SetOption("buff", "size", 36)
local g1Timer = groups.g1.supplied.SetDurationCooldown
Equal(Last(g1Timer, "SetHideCountdownNumbers"), false, "buff countdowns shown by default")
B:SetOption("buff", "showTimer", false)
Equal(Last(g1Timer, "SetHideCountdownNumbers"), true, "and hidden when asked")
B:SetOption("buff", "showTimer", true)
B:Move("buff", 2, -1)
B:Assign("Thorns", "cd")
Equal(B:HasAura("buff", "Thorns"), true, "a spell can be on a cooldown bar and the Buffs bar")
Equal(B:Find("Thorns"), "cd", "and stays on its cooldown bar")
B:Assign("Thorns", nil)
Equal(S[buffs.holders[1]].shown, false, "no placeholders while packed")

-- Fixed, with missing buffs greyed: one slot per buff in its own spot.
B:SetOption("buff", "showMissing", true)
Equal(groups.g1.enabled or groups.g2.enabled, false, "groups switched off")
Equal(slots.b1.enabled and slots.b2.enabled, true, "slots switched on")
Equal(slots.b1.filters.includeSpellIDs[467], true, "Thorns in the first spot")
Equal(S[box].scale, 1, "fixed spots take their size from the holders")
Equal(S[buffs.holders[1]].shown and S[buffs.holders[1].icon].shown, true, "shown greyed when asked")
Equal(S[buffs.holders[1].icon].desaturated, true, "in grey")
B:SetOption("buff", "size", 54)
Equal(S[slots.b1.supplied.SetDurationCooldown].last.SetCountdownFont[1], "FECMFont27", "a fixed spot's numbers follow its size")
B:SetOption("buff", "size", 36)

-- Nothing touches the secure slots, or shows or hides the bar, in combat.
Fire("PLAYER_REGEN_DISABLED")
lockdown = true
B:SetAura("buff", "Clearcasting", false)
Equal(containerCallsInCombat, 0, "no slot or group changes in combat")
Equal(slots.b2.enabled, true, "Clearcasting's slot waits")
B:SetOption("buff", "outOfCombat", "hide")
Equal(S[buffs].alpha, 1, "only in combat: visible in a fight")
ns.Set("useBars", false)
B:Rebuild()
Equal(S[buffs].combatToggle, nil, "never shown or hidden in combat")
Equal(InSight(buffs), true, "going waits for the fight to end")
lockdown = false
Fire("PLAYER_REGEN_ENABLED")
Equal(tostring(InSight(buffs)) .. " " .. tostring(S[buffs].shown), "false true", "gone right out after the fight, never hidden")
Equal(slots.b1.enabled or slots.b2.enabled, false, "and every slot switched off")
ns.Set("useBars", true)
B:Rebuild()
Equal(slots.b1.enabled, true, "back on with the bars")
Equal(slots.b2.enabled, false, "Clearcasting's change applied")
Equal(S[buffs].alpha, 0, "only in combat: faded out of combat")
B:SetOption("buff", "showMissing", false)
Equal(groups.g1.enabled and slots.b1.enabled == false, true, "back to packed")
Equal(groups.g2.enabled, false, "Clearcasting's group off after being unticked")
Equal(#printed, 0, "no errors")
local kept = ForeverEnhancedCooldownManagerDB
Equal(tostring(kept.bars.buff.showMissing) .. " " .. tostring(kept.bars.buff.showTimer), "false true", "Buffs bar options saved")
Equal(table.concat(kept.profiles[ns.ProfileName()].buff, ","), "Thorns", "and its list, in your profile")
Equal(S[buffs.mover.label].text, "Buffs", "mover label is the bar's name")
Equal(S[buffs.mover.label].points[1][1], "CENTER", "inside the highlight")

-- Debuffs bar -------------------------------------------------------------------------------

Environment()
ns = Load({ useBars = true })
B = ns.Bars
local debuffs = B:Get("debuff")
local dbox = containers[2]
Equal(S[dbox].unit, "target", "the Debuffs bar watches your target")
Equal(S[dbox].slots.b1.filter, "HARMFUL", "for harmful auras")
Equal(B:SetAura("debuff", "Moonfire", true), true, "Moonfire ticked onto Debuffs")
local dg1 = S[dbox].groups.g1
Equal(dg1.filter, "HARMFUL", "its icon looks at debuffs")
Equal(dg1.filters.isFromPlayerOrPlayerPet, true, "only the ones you cast")
Equal(dg1.filters.includeSpellIDs[8921] and dg1.filters.includeSpellIDs[8924], true, "any rank of Moonfire")
Equal(S[containers[1]].groups.g1, nil, "the Buffs bar is left alone")
Equal(S[containers[1]].slots.b1.filters, nil, "and its slots too")
Equal(InSight(debuffs), true, "the bar shows")
local before = S[dbox].refreshes or 0
target, hostile = true, true
Fire("PLAYER_TARGET_CHANGED")
Equal(S[dbox].refreshes, before + 1, "a new target is looked at straight away")
B:SetOption("debuff", "showMissing", true)
Equal(S[debuffs.holders[1].icon].alpha, .45, "missing debuffs greyed while you have a target")
Equal(S[dbox].slots.b1.filters.isFromPlayerOrPlayerPet, true, "fixed spots also show only yours")
target = false
Fire("PLAYER_TARGET_CHANGED")
Equal(S[debuffs.holders[1].icon].alpha, 0, "no greyed spots without a target")
target, hostile = true, false
Fire("PLAYER_TARGET_CHANGED")
Equal(S[debuffs.holders[1].icon].alpha, 0, "nor on a friendly one")
hostile = SECRET
Fire("PLAYER_TARGET_CHANGED")
Equal(S[debuffs.holders[1].icon].alpha, .45, "a hidden answer shows them")
hostile = true
Fire("PLAYER_REGEN_DISABLED")
lockdown = true
Fire("PLAYER_TARGET_CHANGED")
Equal(containerCallsInCombat, 0, "a target change in combat sets nothing up")
lockdown = false
Fire("PLAYER_REGEN_ENABLED")
B:SetOption("debuff", "showMissing", false)
Equal(#printed, 0, "no errors")

-- Joined entries ------------------------------------------------------------------------------

local box = containers[1]
local function Shape(key)
    local out = {}
    for _, unit in ipairs(B:Units(key)) do out[#out + 1] = table.concat(unit, "+") end
    return table.concat(out, ", ")
end
for _, name in ipairs({ "Thorns", "Clearcasting", "Nature's Grace" }) do B:SetAura("buff", name, true) end
Equal(B:SetJoined("buff", 1, true), false, "the first entry can't join anything")
Equal(B:SetJoined("buff", 2, true), true, "an entry joins the one before it")
Equal(Shape("buff"), "Thorns+Clearcasting, Nature's Grace", "shown as one icon")
local ids = S[box].groups.g1.filters.includeSpellIDs
Equal(ids[467] and ids[9910] and ids[16870], true, "which lights for either spell")
Equal(S[box].groups.g2.filters.includeSpellIDs[16886], true, "the next entry moves up")
Equal(S[box].groups.g3.enabled, false, "no third icon")
B:SetJoined("buff", 3, true)
Equal(Shape("buff"), "Thorns+Clearcasting+Nature's Grace", "a run of joined entries is one icon")
B:SetOption("buff", "showMissing", true)
local buffs = B:Get("buff")
Equal(S[buffs.holders[1].label].text, "Thorns +2", "a fixed spot names the first and counts the rest")
Equal(buffs.slotIDs[1][16886] and buffs.slotIDs[1][467], true, "and lights for any of them")
Equal(S[buffs.holders[1].icon].alpha, .45, "buff spots don't depend on a target")
B:SetOption("buff", "showMissing", false)

B:Clear("buff")
Equal(next(ns.Joins("buff")), nil, "clearing a bar clears its joins")
for _, name in ipairs({ "Walk on Air", "Thorns", "Clearcasting", "Nature's Grace" }) do B:SetAura("buff", name, true) end
B:SetJoined("buff", 3, true)
B:SetJoined("buff", 4, true)
Equal(Shape("buff"), "Walk on Air, Thorns+Clearcasting+Nature's Grace", "a group of three after another entry")
B:Remove("buff", 2)
Equal(Shape("buff"), "Walk on Air, Clearcasting+Nature's Grace", "removing the first of a group keeps the rest together, apart from the entry above")
B:SetAura("buff", "Thorns", true)
B:SetJoined("buff", 4, true)
B:SetAura("buff", "Nature's Grace", false)
Equal(Shape("buff"), "Walk on Air, Clearcasting+Thorns", "unticking one in the middle keeps the group")
B:MoveTo("buff", 3, 1)
Equal(Shape("buff"), "Thorns, Walk on Air, Clearcasting", "a dragged entry leaves its group")
B:SetJoined("buff", 3, true)
B:SetAura("buff", "Nature's Grace", true)
B:MoveTo("buff", 4, 3)
Equal(Shape("buff"), "Thorns, Walk on Air+Nature's Grace+Clearcasting", "dropped inside a group, it joins it")
B:SetAura("debuff", "Wrath", true)
B:SetJoined("debuff", 2, true)
Equal(Shape("debuff"), "Moonfire+Wrath", "the Debuffs bar joins the same way")
Equal(B:SetJoined("cd", 2, true), false, "cooldown bars don't join")

ns.CopyProfile("Joined copy")
Equal(Shape("buff"), "Thorns, Walk on Air+Nature's Grace+Clearcasting", "a copied profile keeps its joins")
kept = ForeverEnhancedCooldownManagerDB
Environment(true)
ns = Load(kept)
B = ns.Bars
Equal(Shape("buff"), "Thorns, Walk on Air+Nature's Grace+Clearcasting", "joins kept over a reload")
Equal(Shape("debuff"), "Moonfire+Wrath", "on both bars")

-- The window: the Debuffs page and the join buttons.
SlashCmdList.FECM("")
local win = FECMFrame
local barPage = win.pages.bar
local function ListRow(name)
    for _, f in ipairs(frames) do
        if f.spell == name and S[f].shown then return f end
    end
end
Equal(win.nav.debuff ~= nil and S[win.nav.debuff.count].text, 2, "Debuffs listed down the left")
win:Select("debuff")
Equal(S[barPage.options.showMissing.text].text, "Show missing debuffs greyed", "its page speaks of debuffs")
Equal(ListRow("Clearcasting"), nil, "procs aren't offered for debuffs")
Equal(ListRow("Moonfire").check:GetChecked(), true, "spells on the bar are ticked")
win:Select("buff")
Equal(S[barPage.options.showMissing.text].text, "Show missing buffs greyed", "and the Buffs page of buffs")
Equal(S[barPage.icons[1].link].shown, false, "the first icon has no join button")
local link = barPage.icons[2].link
Equal(S[link].shown and S[link.label].text, "+", "the others offer to join")
link:Click()
Equal(B:Joined("buff", 2), true, "clicking joins it to the one before")
Equal(S[link.label].text, "-", "then offers to split")
Equal(S[barPage.icons[2].bridge].shown, true, "a line under the pair shows they're joined")
link:Click()
Equal(B:Joined("buff", 2), false, "clicking again splits them")
Equal(S[barPage.icons[2].bridge].shown, false, "and the line goes")
B:Assign("Moonfire", "cd")
B:Assign("Wrath", "cd")
win:Select("cd")
Equal(S[barPage.icons[2].link].shown, false, "cooldown bars have no join buttons")
-- Icons the Buffs page used and this one doesn't go with their join buttons
-- and lines, which sit on the tray, not the icon.
Equal(#barPage.icons >= 4, true, "the Buffs page drew more icons than Cooldowns has")
for n = 3, #barPage.icons do
    local icon = barPage.icons[n]
    Equal(tostring(S[icon].shown) .. " " .. tostring(S[icon.link].shown) .. " " .. tostring(S[icon.bridge].shown), "false false false",
        "an icon not in use goes with its join button and line")
end
do
    -- Taking the last of a group off with its x leaves no line or button behind.
    win:Select("buff")
    local last = barPage.icons[4]
    Equal(tostring(S[last.link].shown) .. " " .. tostring(S[last.bridge].shown), "true true", "the last Buffs icon is joined")
    last.remove:Click()
    Equal(#ns.BarData("buff").spells .. " " .. tostring(S[last.link].shown) .. " " .. tostring(S[last.bridge].shown), "3 false false",
        "taken off, its join button and line go too")
    -- A full bar: splitting a group or dragging one out of it would need
    -- another icon, so it's refused, saying why.
    ns.BUFF_SLOTS = 2
    barPage.icons[3].link:Click()
    Equal(tostring(B:Joined("buff", 3)) .. " " .. S[win.note].text, "true Buffs is full.", "a split past the bar's slots is refused")
    -- Dropped onto another icon, the two swap places and each spot stays
    -- joined or not, so a full bar needs no more room.
    S[barPage.icons[3]].scripts.OnDragStart(barPage.icons[3])
    S[barPage.icons[1]].mouseOver = true
    S[barPage.icons[3]].scripts.OnDragStop(barPage.icons[3])
    S[barPage.icons[1]].mouseOver = nil
    Equal(Shape("buff") .. " | " .. S[win.note].text, "Nature's Grace, Walk on Air+Thorns | Swapped Nature's Grace and Thorns.",
        "swapped with the icon it's dropped on, each spot keeping its join, even on a full bar")
    -- Put last, one dragged out of its group would need an icon of its own.
    S[barPage.icons[2]].scripts.OnDragStart(barPage.icons[2])
    S[barPage.tray].mouseOver = true
    S[barPage.icons[2]].scripts.OnDragStop(barPage.icons[2])
    S[barPage.tray].mouseOver = nil
    Equal(Shape("buff") .. " " .. S[win.note].text, "Nature's Grace, Walk on Air+Thorns Buffs is full.",
        "and so is dragging one out of its group")
    ns.BUFF_SLOTS = 16
    -- Closing the window mid-drag: the icon's spot comes back, nothing is
    -- left on the cursor, and a late drop takes nothing off.
    local held = barPage.icons[1]
    S[held].scripts.OnDragStart(held)
    Equal(tostring(S[held].alpha) .. " " .. tostring(S[barPage.ghost].shown), "0 true", "picked up, it follows the cursor")
    barPage:Hide()
    Equal(tostring(S[held].alpha) .. " " .. tostring(S[barPage.ghost].shown), "1 false",
        "closed mid-drag, its spot shows again and nothing is left on the cursor")
    S[held].scripts.OnDragStop(held)
    Equal(#ns.BarData("buff").spells, 3, "a late drop takes nothing off")
    barPage:Show()
end
Equal(#printed, 0, "no errors")

-- Out of combat: show, fade or hide -------------------------------------------------------

Environment()
ns = Load({ useBars = true, bars = { cd = { combatOnly = true } } })
B = ns.Bars
Equal(ns.BarData("cd").outOfCombat, "hide", "bars that were only in combat now hide out of combat")
Equal(rawget(ns.BarData("cd"), "combatOnly"), nil, "the old setting is gone")
Equal(ns.BarData("util").outOfCombat, "show", "the rest show")
B:Assign("Moonfire", "cd")
B:Assign("Wrath", "util")
B:SetAura("buff", "Thorns", true)
local cdBar, utilBar, buffBar = B:Get("cd"), B:Get("util"), B:Get("buff")
target, hostile = false, true
B:UpdateShown()
Equal(S[cdBar].shown, false, "hidden out of combat")
Fire("PLAYER_REGEN_DISABLED")
Equal(S[cdBar].shown and S[cdBar].alpha, 1, "back in full in combat")
Fire("PLAYER_REGEN_ENABLED")
Equal(S[cdBar].shown, false, "hidden again after")
target = true
Fire("PLAYER_TARGET_CHANGED")
Equal(S[cdBar].shown, true, "back with an enemy targeted")
hostile = false
Fire("PLAYER_TARGET_CHANGED")
Equal(S[cdBar].shown, false, "but not with a friend")
hostile = SECRET
Fire("PLAYER_TARGET_CHANGED")
Equal(S[cdBar].shown, true, "a hidden answer counts as an enemy")
hostile, target = true, false
Fire("PLAYER_TARGET_CHANGED")
EditModeManagerFrame:Show()
Equal(S[cdBar].shown, true, "back in Edit Mode")
EditModeManagerFrame:Hide()
Equal(S[cdBar].shown, false, "and hidden once it closes")
B:SetOption("util", "outOfCombat", "fade")
Equal(S[utilBar].shown and S[utilBar].alpha, .3, "faded to 30% out of combat")
Fire("PLAYER_REGEN_DISABLED")
Equal(S[utilBar].alpha, 1, "full in combat")
Fire("PLAYER_REGEN_ENABLED")
B:SetOption("buff", "outOfCombat", "fade")
Equal(S[buffBar].shown and S[buffBar].alpha, .3, "aura bars fade too")
B:SetOption("buff", "outOfCombat", "hide")
Equal(S[buffBar].shown and S[buffBar].alpha, 0, "and hide by fading right out, since their slots can't be hidden in a fight")
B:SetUnlocked(true)
Equal(S[cdBar].shown and S[utilBar].alpha == 1 and S[buffBar].alpha, 1, "unlocked, every bar shows in full")
B:SetUnlocked(false)
Equal(ForeverEnhancedCooldownManagerDB.bars.cd.outOfCombat, "hide", "the choice is saved")

-- The window's out-of-combat choice.
Environment()
ns = Load({ useBars = true })
B = ns.Bars
SlashCmdList.FECM("")
local choice = FECMFrame.pages.bar.options.outOfCombat
Equal(choice.selected, "show", "the page shows the bar's choice")
choice.buttons[2]:Click()
Equal(ns.BarData("cd").outOfCombat, "fade", "clicking Fade sets it")
Equal(choice.selected, "fade", "and shows it")
FECMFrame:Select("util")
Equal(choice.selected, "show", "each bar has its own")

-- Ammunition ---------------------------------------------------------------------------------

Environment()
ammo, ammoCount = 2512, 200
_G.UnitClass = function() return "Hunter", "HUNTER" end
ns = Load({ useBars = true })
B = ns.Bars
local arrows = ns.Spells:Find("ammo")
Equal(arrows and arrows.name, "Ammo: Rough Arrow", "equipped ammunition listed")
Equal(arrows.line, "Items", "with the items")
B:Assign("ammo", "util")
local quiver = B:Get("util").icons[1]
Equal(S[quiver.count].text, 200, "its count shown")
Equal(S[quiver.texture].desaturated, false, "in colour while you have some")
ammoCount = 0
B:RefreshAll()
Equal(S[quiver.texture].desaturated, true, "greyed when you run out")
B:SetOption("util", "showNames", true)
Equal(S[B:Get("util").icons[1].label].text, "Rough Arrow", "named by the ammo")
ammo = nil
GearChanged()
Equal(ns.Spells:Find("ammo") and ns.Spells:Find("ammo").name, "Ammo", "kept on the bar with none equipped")
Equal(S[B:Get("util").icons[1].count].text, 0, "showing none")
Equal(ns.Spells:IsItem(ns.Spells:Find("ammo")), true, "never offered for the Buffs or Debuffs bar")
Equal(#printed, 0, "no errors")
-- A gear set swapped: the game says so once for each slot, all in one frame.
-- The bars are rebuilt once for them all, on the next frame.
do
    local scan, scans, from = ns.Spells.Scan, 0, #timers
    ns.Spells.Scan = function(...)
        scans = scans + 1
        return scan(...)
    end
    for _ = 1, 16 do Fire("PLAYER_EQUIPMENT_CHANGED") end
    local waiting = scans
    for i = from + 1, #timers do timers[i]() end
    Equal(waiting .. " " .. scans, "0 1", "16 slots changed at once: one rebuild, on the next frame")
    GearChanged()
    Equal(scans, 2, "and a later change rebuilds again")
    ns.Spells.Scan = scan
end
-- Only hunters, warriors and rogues use ammo. Any other class on a profile
-- shared with a hunter passes over it, like another class's spell: not
-- listed, off its bars and its drawings of them, kept in the profile.
do
    local uses = {}
    for _, class in ipairs({ "HUNTER", "WARRIOR", "ROGUE", "WARLOCK", "MAGE", "PRIEST", "PALADIN", "SHAMAN", "DRUID" }) do
        _G.UnitClass = function() return class, class end
        uses[#uses + 1] = class .. "=" .. tostring(ns.Spells:UsesAmmo()) .. "," .. tostring(ns.Spells:ForMe("ammo", "util"))
    end
    _G.UnitClass = function() return SECRETS.string, SECRETS.string end
    uses[#uses + 1] = "secret=" .. tostring(ns.Spells:ForMe("ammo", "util"))
    Equal(table.concat(uses, " "), "HUNTER=true,true WARRIOR=true,true ROGUE=true,true WARLOCK=false,false MAGE=false,false"
        .. " PRIEST=false,false PALADIN=false,false SHAMAN=false,false DRUID=false,false secret=true",
        "ammo is for hunters, warriors and rogues; a class the game won't say keeps it")
    -- A warlock with arrows in the ammo slot (and on the shared bar).
    ammo, ammoCount = 2512, 0
    _G.UnitClass = function() return "Warlock", "WARLOCK" end
    B:Rebuild()
    local util = B:Get("util")
    Equal(tostring(ns.Spells:Find("ammo")) .. " " .. util.count .. " " .. tostring(S[util].shown) .. " " .. #(B:Mine("util")) .. " "
        .. table.concat(ns.BarData("util").spells, ","), "nil 0 false 0 ammo",
        "a warlock: ammo not listed, not on its bar or the window's drawing of it, still in the profile")
    ns.Toggle()
    FECMFrame:Select("util")
    FECMFrame.pages.bar.showItems:Click()
    Equal(tostring(ListRow("family:healing") ~= nil) .. " " .. tostring(ListRow("ammo") ~= nil) .. " " .. select(2, B:AddItem("util", 2512)),
        "true false Your class doesn't use ammo.", "nor offered in its Items list, or taken when dragged in")
    ns.Toggle()
    ammo = nil
    B:Rebuild()
    Equal(tostring(ns.Spells:Find("ammo")) .. " " .. util.count, "nil 0", "nor shown empty with none equipped")
    -- The hunter again: back, greyed at 0 while out.
    _G.UnitClass = function() return "Hunter", "HUNTER" end
    B:Rebuild()
    Equal(util.count .. " " .. S[util.icons[1].count].text .. " " .. tostring(S[util.icons[1].texture].desaturated), "1 0 true",
        "a hunter out of ammo: still on the bar, greyed at 0")
    Equal(#printed, 0, "no errors")
end

-- Healthstones and potions: one icon for whichever rank you carry ------------------------------

;(function()
    Environment()
    -- The names of the ranks used here, and a picture for each.
    local names = { [5512] = "Minor Healthstone", [9421] = "Major Healthstone", [19013] = "Major Healthstone",
        [118] = "Minor Healing Potion", [1710] = "Greater Healing Potion", [13446] = "Major Healing Potion" }
    _G.C_Item.GetItemNameByID = function(id) return names[id] end
    _G.C_Item.GetItemIconByID = function(id) return 100000 + id end
    -- Potions above your level can't be used; each cooldown asked for is noted.
    local unusable, asked = {}, {}
    _G.C_Item.IsUsableItem = function(id) return not unusable[id], false end
    _G.C_Item.GetItemCooldown = function(id)
        asked[#asked + 1] = id
        return itemCooldown[1], itemCooldown[2], itemCooldown[3]
    end
    bagItems = { { itemID = 118, hyperlink = "|cffffffff|Hitem:118|h[Minor Healing Potion]|h|r", iconFileID = 888 } }
    itemCount[5512], itemCount[9421] = 1, 1
    ns = Load({ useBars = true })
    B = ns.Bars
    local Spells = ns.Spells
    local stones = Spells:Find("family:healthstone")
    Equal(stones.name .. " | " .. stones.line .. " | " .. stones.rankText .. " | " .. tostring(Spells:IsItem(stones)),
        "Healthstones | Items | Best you carry | true", "Healthstones listed with your items, as one entry")
    Equal(stones.itemID .. " " .. stones.current .. " " .. stones.icon, "9421 Major Healthstone 109421",
        "showing the best one you carry: a Major over a Minor")
    Equal(tostring(Spells:Find("family:healing") ~= nil) .. " " .. tostring(Spells:Find("family:mana") ~= nil) .. " "
        .. Spells:Find("item:118").name, "true true Minor Healing Potion", "healing and mana potions too, and each potion still on its own")
    -- Every rank in one family only; Improved Healthstone's and the conjured
    -- potions in theirs, the Discolored ones left as single items.
    local seen, twice = {}, 0
    for _, family in ipairs(Spells.FAMILIES) do
        for _, id in ipairs(family.items) do
            if seen[id] then twice = twice + 1 end
            seen[id] = true
        end
    end
    Equal(twice .. " " .. Spells:Family(19013).key .. " " .. Spells:Family(268883).name .. " " .. Spells:Family(13444).name
        .. " " .. tostring(Spells:Family(247240)) .. " " .. tostring(Spells:Family(SECRETS.number)),
        "0 family:healthstone Healing Potions Mana Potions nil nil", "each rank in one family, and nothing secret looked up")

    -- On a bar: the one it shows, with its count and name.
    B:Assign("family:healthstone", "cd")
    B:SetOption("cd", "showNames", true)
    local icon = B:Get("cd").icons[1]
    Equal(icon.kind .. " " .. icon.itemID .. " " .. S[icon.texture].texture .. " " .. S[icon.count].text .. " " .. S[icon.label].text,
        "family 9421 109421 1 Major Healthstone", "on a bar: the Major Healthstone's picture, count and name")
    -- Used up: with the window shut only the bars refresh, and it moves on.
    itemCount[9421] = 0
    Fire("BAG_UPDATE_DELAYED")
    Equal(icon.itemID .. " " .. S[icon.texture].texture .. " " .. S[icon.count].text .. " " .. S[icon.label].text .. " "
        .. tostring(S[icon.texture].desaturated), "5512 105512 1 Minor Healthstone false",
        "used: the Minor one next, as soon as your bags change")
    itemCooldown = { 100, 120, 1 }
    asked = {}
    B:RefreshAll()
    Equal(asked[1] .. " " .. Last(icon.cooldown, "SetCooldown", 2) .. " " .. tostring(S[icon.texture].desaturated), "5512 120 true",
        "its cooldown, for the one it shows, greyed")
    itemCooldown = { 0, 0, 1 }
    itemCount[5512] = 0
    Fire("BAG_UPDATE_DELAYED")
    local stoneBar = B:Get("cd")
    Equal(stoneBar.count .. " " .. tostring(S[icon].shown) .. " " .. tostring(S[stoneBar].shown) .. " " .. tostring(B:Absent("family:healthstone")),
        "0 false false true", "none left: off the bar, which closes up (empty here, so hidden)")
    Equal(table.concat(ns.BarData("cd").spells, ","), "family:healthstone", "still on the bar's list")
    B:SetUnlocked(true)
    Equal(stoneBar.count .. " " .. tostring(S[icon].shown) .. " " .. icon.itemID .. " " .. S[icon.count].text .. " "
        .. tostring(S[icon.texture].desaturated) .. " " .. S[icon.label].text,
        "1 true 5512 0 true Healthstones", "unlocked: back, the last one greyed at 0 and named for them all, to be placed")
    EditModeManagerFrame:Show()
    B:SetUnlocked(false)
    Equal(stoneBar.count .. " " .. tostring(S[icon].shown), "1 true", "in Edit Mode too")
    EditModeManagerFrame:Hide()
    Equal(stoneBar.count .. " " .. tostring(S[icon].shown) .. " " .. tostring(S[stoneBar].shown), "0 false false", "and off again after")
    itemCount[19013] = 1
    Fire("BAG_UPDATE_DELAYED")
    Equal(icon.itemID .. " " .. S[icon.count].text .. " " .. S[icon.label].text, "19013 1 Major Healthstone",
        "a new one made, with Improved Healthstone: shown at once")
    itemCount[19013], itemCount[19012] = 0, 1
    Fire("BAG_UPDATE_DELAYED")
    local waiting = icon.itemID .. " " .. S[icon.label].text
    names[19012] = "Major Healthstone"
    -- Looked up again once the game says it has the name, not on every
    -- refresh, and not for other items' names.
    B:RefreshAll()
    local refreshed = S[icon.label].text
    Fire("GET_ITEM_INFO_RECEIVED", 2589, true)
    NextFrame()
    refreshed = refreshed .. " " .. S[icon.label].text
    Fire("GET_ITEM_INFO_RECEIVED", 19012, true)
    Equal(S[icon.label].text, "Healthstones", "the name looked up on the next frame")
    NextFrame()
    Equal(waiting .. " | " .. refreshed .. " | " .. S[icon.label].text,
        "19012 Healthstones | Healthstones Healthstones | Major Healthstone",
        "a name the game hasn't loaded yet: the family's until the game says it has it")
    itemCount[19013], itemCount[19012] = 1, 0
    Fire("BAG_UPDATE_DELAYED")

    -- The best you can use: a Major potion above your level waits.
    unusable[13446] = true
    itemCount[13446], itemCount[1710], itemCount[118] = 2, 3, 5
    B:Assign("family:healing", "cd")
    local potion = B:Get("cd").icons[2]
    Equal(potion.itemID .. " " .. S[potion.count].text .. " " .. S[potion.label].text, "1710 3 Greater Healing Potion",
        "the best potion you can use: Greater, while the Major is above your level")
    -- Levelled up, the Major can be used: looked for once the game says you
    -- levelled, not on every refresh.
    unusable[13446] = nil
    B:RefreshAll()
    local before = potion.itemID
    Fire("PLAYER_LEVEL_UP", 60)
    NextFrame()
    Equal(before .. " " .. potion.itemID .. " " .. S[potion.count].text .. " " .. S[potion.label].text,
        "1710 13446 2 Major Healing Potion", "levelled up: on to the Major on the next frame")
    -- Your level can still read the old one as PLAYER_LEVEL_UP fires, and on
    -- the next frame: PLAYER_LEVEL_CHANGED, with the new one, looks again.
    unusable[13446] = true
    Fire("BAG_UPDATE_DELAYED")
    before = potion.itemID
    Fire("PLAYER_LEVEL_UP", 60)
    NextFrame()
    before = before .. " " .. potion.itemID
    unusable[13446] = nil
    B:RefreshAll()
    before = before .. " " .. potion.itemID
    Fire("PLAYER_LEVEL_CHANGED", 59, 60, true)
    NextFrame()
    Equal(before .. " " .. potion.itemID .. " " .. S[potion.label].text, "1710 1710 1710 13446 Major Healing Potion",
        "the level still the old one as the game says you levelled: on to the Major once it says the level changed")
    unusable[13446], unusable[1710], unusable[118] = true, true, true
    Fire("BAG_UPDATE_DELAYED")
    Equal(potion.itemID, 13446, "none you can use: the best you carry")
    unusable[13446], unusable[1710], unusable[118] = nil, nil, nil
    Fire("BAG_UPDATE_DELAYED")
    Equal(potion.itemID .. " " .. S[potion.count].text, "13446 2", "the Major once you can use it")
    -- Bags or use hidden in a fight: each stays as it is, with no errors.
    local count, use = _G.C_Item.GetItemCount, _G.C_Item.IsUsableItem
    _G.C_Item.GetItemCount = function() return SECRETS.number end
    unusable[13446] = true -- a change it can't see yet
    Fire("PLAYER_REGEN_DISABLED")
    lockdown = true
    Fire("BAG_UPDATE_DELAYED")
    _G.C_Item.GetItemCount = count
    _G.C_Item.IsUsableItem = function() return SECRETS.boolean, SECRETS.boolean end
    Fire("BAG_UPDATE_DELAYED")
    Equal(potion.itemID .. " " .. icon.itemID .. " " .. S[potion.count].text .. " " .. #printed, "13446 19013 2 0",
        "counts or use hidden in a fight: nothing moves, no errors")
    _G.C_Item.IsUsableItem = use
    lockdown = false
    Fire("PLAYER_REGEN_ENABLED")
    NextFrame()
    Equal(potion.itemID, 1710, "and after it, the best you can use again")

    -- Any rank dragged in adds its family, never on the Buffs or Debuffs bars.
    B:TakeOff("cd", "family:healing")
    local ok, message = B:AddItem("util", 858) -- a Lesser Healing Potion, none in your bags
    Equal(tostring(ok) .. " " .. message .. " " .. table.concat(ns.BarData("util").spells, ","),
        "true Added Healing Potions to Utility. It shows the best one you carry. family:healing", "any rank dragged in adds its family")
    Equal(select(2, B:AddItem("buff", 5512)) .. " " .. select(2, B:Add("debuff", "Healthstones")) .. " " .. #ns.BarData("buff").spells
        .. " " .. #ns.BarData("debuff").spells, "Items can't go on the Buffs bar. Items can't go on the Debuffs bar. 0 0",
        "never on the Buffs or Debuffs bar, dragged or by name")
    Equal(select(2, B:Transfer("util", "buff", "family:healing")), "Items can't go on the Buffs bar.", "nor moved there")
    B:Assign("item:118", "util")
    local single = B:Get("util").icons[2]
    Equal(single.kind .. " " .. single.itemID .. " " .. S[single.count].text, "item 118 5", "a potion on its own still works beside it")

    -- The list: with your items, where Show items puts them, saying how it
    -- works as you go to tick one.
    ns.Toggle()
    local w = FECMFrame
    local page = w.pages.bar
    page.showItems:Click()
    local row = ListRow("family:healing")
    Equal(tostring(row ~= nil) .. " " .. S[row.name].text .. " | " .. S[row.rank].text .. " | " .. tostring(row.check:GetChecked()),
        "true Healing Potions | Best you carry | false", "listed as one row, labelled as the best you carry")
    S[row.check].scripts.OnEnter(row.check)
    Equal(S[w.note].text, "Move Healing Potions here from Utility. One icon for the best one you carry, switching as your bags change.",
        "its note says how it works")
    S[row.check].scripts.OnLeave(row.check)
    S[page.showItems].scripts.OnEnter(page.showItems)
    Equal(S[w.note].text:find("Healthstones and potions are one icon each", 1, true) ~= nil, true, "as does Show items'")
    S[page.showItems].scripts.OnLeave(page.showItems)
    row.check:Click()
    Equal(table.concat(ns.BarData("cd").spells, ",") .. " | " .. table.concat(ns.BarData("util").spells, ","),
        "family:healthstone,family:healing | item:118", "ticking it moves it here from Utility")
    w:Select("buff")
    Equal(ListRow("family:healthstone") == nil and ListRow("family:healing") == nil, true, "never offered on the Buffs page")
    w:Select("debuff")
    Equal(ListRow("family:healthstone") == nil, true, "nor the Debuffs page")
    ns.Toggle()

    -- A class without mana isn't offered Mana Potions, unless they're on a
    -- bar (a profile shared with one that has mana). Kept over a reload.
    local kept = ForeverEnhancedCooldownManagerDB
    Environment(true)
    _G.UnitClass = function() return "Warrior", "WARRIOR" end
    ns = Load(kept)
    Equal(tostring(ns.Spells:Find("family:mana")) .. " " .. ns.BarData("cd").spells[1] .. " " .. ns.Spells:Find("family:healthstone").itemID,
        "nil family:healthstone 19004", "no Mana Potions for a warrior; Healthstones kept on the bar, none carried")
    ns.Bars:Assign("family:mana", "util")
    Equal(ns.Spells:Find("family:mana") and ns.Spells:Find("family:mana").name, "Mana Potions", "but kept once on a bar")
    Equal(#printed, 0, "no errors")
end)()

-- Ticking spells onto bars from their pages ------------------------------------------------

Environment()
ns = Load({ useBars = true })
B = ns.Bars
ns.Toggle()
local w = FECMFrame
local page = w.pages.bar

-- The shown list row for a spell.
local function Row(name)
    for _, f in ipairs(frames) do
        if f.spell == name and S[f].shown then return f end
    end
end
local function Other(name)
    for _, f in ipairs(frames) do
        if f.other == name and S[f].shown then return f end
    end
end
local function Search(text)
    page.search:SetText(text)
    S[page.search].scripts.OnTextChanged(page.search, true)
end

Equal(w.selected, "cd", "opens on the Cooldowns bar")
Equal(S[page].shown, true, "its page shown")
local row = Row("Moonfire")
Equal(row ~= nil, true, "Moonfire listed")
row.check:Click()
Equal(ns.BarData("cd").spells[1], "Moonfire", "ticking it adds it to Cooldowns")
w:Select("util")
row = Row("Moonfire")
Equal(row.check:GetChecked(), false, "not ticked on Utility")
Equal(S[row.where].text, "on Cooldowns", "which says where it is")
local at = S[row.where].points[1]
Equal(at[1] == "LEFT" and at[2] == row.rank and at[3] == "RIGHT" and at[4], 10, "right after its rank, on its own row")
Equal(S[Row("Attack").where].points[1][2], Row("Attack").name, "or its name, for a spell without ranks")
row.check:Click()
Equal(ns.BarData("util").spells[1], "Moonfire", "ticking it on Utility moves it")
Equal(#ns.BarData("cd").spells, 0, "off Cooldowns")
Equal(S[row.where].text, "", "and the note goes")
w:Select("buff")
Row("Moonfire").check:Click()
Equal(ns.BarData("buff").spells[1], "Moonfire", "ticked on the Buffs bar too")
Equal(ns.BarData("util").spells[1], "Moonfire", "without leaving Utility")
Equal(Row("Clearcasting") ~= nil, true, "procs listed on the Buffs bar")
w:Select("cd")
Equal(Row("Clearcasting"), nil, "but not on cooldown bars")

-- Items, added spells, names and cooldown ends ---------------------------------------------

Environment()
trinket = 11111
bagItems = {
    { itemID = 118, hyperlink = "|cffffffff|Hitem:118|h[Minor Healing Potion]|h|r", iconFileID = 888 },
    { itemID = 2589, hyperlink = "|cffffffff|Hitem:2589|h[Linen Cloth]|h|r" },
    { itemID = 117, hyperlink = "|cffffffff|Hitem:117|h[Tough Jerky]|h|r" },
    { itemID = 2698, hyperlink = "|cffffffff|Hitem:2698|h[Recipe: Cooked Crab Claw]|h|r" },
}
itemCount[118] = 3
ns = Load({ useBars = true })
B = ns.Bars
local charm = ns.Spells:Find("slot:13")
Equal(charm and charm.name, "Trinket 1: Lucky Charm", "equipped trinket listed")
Equal(charm.line, "Items", "under Items")
Equal(ns.Spells:Find("item:118") and ns.Spells:Find("item:118").name, "Minor Healing Potion", "usable bag item listed")
Equal(ns.Spells:Find("item:2589"), nil, "items without a use left out")
Equal(ns.Spells:Find("item:117"), nil, "food and drink left out: no cooldown")
Equal(ns.Spells:Find("item:2698"), nil, "recipes left out")

Equal(ns.Spells:Resolve("thorns"), "Thorns", "names match whatever the case")
local key, ids = ns.Spells:Resolve("Power Word: Fortitude")
Equal(key, "Power Word: Fortitude", "another class's spell found in the game data")
Equal(ids[1], 1243, "remembered by its ID")
Equal(select(2, ns.Spells:Resolve("99999999")), "No spell has ID 99999999.", "unknown IDs explained")
Equal(ns.Spells:Resolve("16870"), "Clearcasting", "IDs of listed spells map to them")
Equal(select(2, ns.Spells:Resolve("   ")), "Type a spell name or ID first.", "empty input explained")

B:Assign("slot:13", "cd")
B:Assign("item:118", "cd")
local cdBar = B:Get("cd")
local charmIcon, potion = cdBar.icons[1], cdBar.icons[2]
Equal(charmIcon.kind, "slot", "trinket icon")
trinketCooldown = { 100, 120, 1 }
B:RefreshAll()
Equal(Last(charmIcon.cooldown, "SetCooldown", 2), 120, "trinket cooldown shown")
Equal(S[charmIcon.texture].desaturated, true, "greyed while cooling down")
trinketCooldown = { 0, 0, 1 }
S[charmIcon.cooldown].scripts.OnCooldownDone()
Equal(S[charmIcon.texture].desaturated, true, "a cooldown ending asks for a refresh on the next frame")
NextFrame()
Equal(S[charmIcon.texture].desaturated, false, "ungreys when the cooldown finishes")
Equal(S[potion.count].text, 3, "potion count shown")
itemCount[118] = 0
B:RefreshAll()
Equal(S[potion.texture].desaturated, true, "greyed when you've run out")
trinketCooldown = { SECRET, SECRET, 1 }
B:RefreshAll()
Equal(S[charmIcon.texture].desaturated, false, "a hidden item cooldown leaves the icon as it was")
trinketCooldown = { 0, 0, 1 }
B:SetOption("cd", "whenReady", "hide")
Equal(S[cdBar.icons[1]].alpha, 0, "ready trinket hidden when asked")
B:SetOption("cd", "whenReady", "dim")
Equal(S[cdBar.icons[1]].alpha, .4, "or dimmed")
trinketCooldown = { 100, 120, 1 }
B:RefreshAll()
Equal(S[cdBar.icons[1]].alpha, 1, "in full while it cools down")
trinketCooldown = { SECRET, SECRET, 1 }
S[cdBar.icons[1]].alpha = nil
B:RefreshAll()
Equal(S[cdBar.icons[1]].alpha, nil, "a hidden item cooldown doesn't dim or undim it")
-- (Back as the game still shows it, in full: an alpha is only set as it changes.)
S[cdBar.icons[1]].alpha = 1
trinketCooldown = { 0, 0, 1 }
B:RefreshAll()
Equal(S[cdBar.icons[1]].alpha, .4, "ready again: dimmed")
B:SetOption("cd", "whenReady", "show")
Equal(S[cdBar.icons[1]].alpha, 1, "Show: in full")

B:Assign("Moonfire", "util")
local moonIcon = B:Get("util").icons[1]
active = true
B:RefreshAll()
Equal(S[moonIcon.texture].desaturated, true, "spell greyed on cooldown")
active = false
S[moonIcon.cooldown].scripts.OnCooldownDone()
NextFrame()
Equal(S[moonIcon.texture].desaturated, false, "and ungreyed right when its cooldown ends")

B:SetOption("cd", "showNames", true)
Equal(S[cdBar.icons[1].label].shown, true, "names shown when asked")
Equal(S[cdBar.icons[1].label].text, "Lucky Charm", "trinkets named by the item")
B:SetOption("cd", "showNames", false)
Equal(S[cdBar.icons[1].label].shown, false, "names off by default")

Equal(Last(cdBar.icons[1].cooldown, "SetHideCountdownNumbers"), false, "countdown numbers on by default")
B:SetOption("cd", "showTimer", false)
Equal(Last(cdBar.icons[1].cooldown, "SetHideCountdownNumbers"), true, "and off when asked")
Equal(ForeverEnhancedCooldownManagerDB.bars.cd.showTimer, false, "that choice saved")
B:SetOption("cd", "showTimer", true)

local found = ns.Spells:Suggest("mo", 50)
local names, firstContains = {}, nil
for i, item in ipairs(found) do
    names[item.name] = i
    if not firstContains and not item.name:lower():find("^mo") then firstContains = i end
end
Equal(names.Moonfire ~= nil and names["Mongoose Bite"] ~= nil, true, "your spells and other classes' spells both suggested")
Equal(names["Minor Healing Potion"] ~= nil, false, "only names containing the text")
local startsFirst = true
for i, item in ipairs(found) do
    if firstContains and i > firstContains and item.name:lower():find("^mo") then startsFirst = false end
end
Equal(startsFirst, true, "names starting with the text come first")
Equal(#ns.Spells:Suggest("m"), 0, "nothing suggested for a single letter")
local twoLetters = true
for _, item in ipairs(ns.Spells:Suggest("ss", 50)) do
    local lower = item.name:lower()
    if not (lower:find("^ss") or lower:find("[%s%p]ss")) then twoLetters = false end
end
Equal(twoLetters, true, "two letters only match the start of a word")
local passives = 0
for name in pairs(ns.RANKS) do if name:lower():find("passive") then passives = passives + 1 end end
Equal(passives, 0, "hidden passive helper spells left out of the game data")
Equal(#ns.Spells:Suggest("a", 8) <= 8 and #ns.Spells:Suggest("ar") <= 8, true, "at most eight")
Equal(ns.Spells:Suggest("tho")[1].name, "Thorns", "your own spell before other classes' spells")
local fire = ns.Spells:Suggest("fire", 20)
local order = {}
for i, item in ipairs(fire) do order[item.name] = i end
Equal(order.Moonfire < order["Fire Blast"], true, "your spells first, even when another class's name starts with the text")
local shield = ns.Spells:Suggest("shield", 30)
local wordStart, midWord
for i, item in ipairs(shield) do
    if item.name == "Power Word: Shield" then wordStart = i end
    if item.name:lower():find("shield", 1, true) and not item.name:lower():find("^shield") and not item.name:lower():find("[%s%p]shield") then midWord = midWord or i end
end
Equal(midWord == nil or wordStart < midWord, true, "a word starting with the text before a match mid-word")
local fort = {}
for _, item in ipairs(ns.Spells:Suggest("fortitude")) do fort[item.name] = true end
Equal(fort["Power Word: Fortitude"] and fort["Prayer of Fortitude"], true, "found by any part of the name")
Equal(ns.Spells:Suggest("minor heal")[1].name, "Minor Healing Potion", "items suggested too")

ns.Toggle()
w = FECMFrame
page = w.pages.bar
Equal(Row("item:118"), nil, "items left out of the list by default")
Equal(Row("Moonfire") ~= nil, true, "spells listed")
page.showItems:Click()
Equal(ns.Get("listItems"), true, "Show items remembered")
Equal(Row("item:118") ~= nil, true, "items listed when asked")
Equal(ForeverEnhancedCooldownManagerDB.listItems, true, "and saved")

-- Searching filters the list and finds spells outside your spellbook.
Equal(#S[page.list].points, 2, "the list is pinned by two corners, so the game can place it")
page.list:SetVerticalScroll(500)
Search("thor")
Equal(Row("Thorns") ~= nil and Row("Moonfire") == nil, true, "search narrows the list")
Equal(page.list:GetVerticalScroll(), 0, "a short result scrolls back to the top, so it can be seen")
Search("16870")
w:Select("buff")
Equal(Row("Clearcasting") ~= nil, true, "your own spells found by ID too")
Search("power word: fort")
local pwfRow = Other("Power Word: Fortitude")
Equal(pwfRow ~= nil, true, "another class's spell offered under Other spells")
Equal(pwfRow.check:GetChecked(), false, "unticked")
pwfRow.check:Click()
Equal(ns.BarData("buff").spells[1], "Power Word: Fortitude", "ticking it adds it")
Equal(S[w.note].text, "Added Power Word: Fortitude to Buffs.", "and confirms")
Equal(Row("Power Word: Fortitude") ~= nil and Row("Power Word: Fortitude").check:GetChecked(), true, "now listed as your own, ticked")
local pwf = ns.Spells:Find("Power Word: Fortitude")
Equal(pwf and pwf.line, "Added", "added spells listed under Added")
local slotIDs = S[containers[1]].groups.g1.filters.includeSpellIDs
Equal(slotIDs[1243] and slotIDs[10938] and slotIDs[21564], true, "any rank, and Prayer of Fortitude, counts")
Search("minor heal")
Equal(Row("item:118") == nil and Other("Minor Healing Potion") == nil, true, "items never offered on the Buffs bar")
Search("zzzz")
Equal(Row("Moonfire") == nil, true, "nothing listed when nothing matches")
-- Typing a debuff on you: the footer points to the tick, letter after letter.
Search("weak")
Equal(S[w.note].text, ns.Spells:SelfDebuffNote("Weakened Soul"), "typing Weakened Soul: the footer points to the tick")
Search("weake")
Equal(S[w.note].text, ns.Spells:SelfDebuffNote("Weakened Soul"), "and still does on the next letter")
S[page.search].scripts.OnEnter(page.search)
Equal(S[w.note].text, ns.Spells:SelfDebuffNote("Weakened Soul"), "hovering the box keeps the tip")
S[page.search].scripts.OnLeave(page.search)
Search("thor")
S[page.search].scripts.OnEnter(page.search)
Equal(S[w.note].text:find("^Find a spell") ~= nil, true, "other text: the box's own note")
S[page.search].scripts.OnLeave(page.search)
Search("")
Equal(Row("Thorns") ~= nil, true, "clearing the search lists everything again")
Equal(#printed, 0, "no errors")

kept = ForeverEnhancedCooldownManagerDB
Environment(true)
ns = Load(kept)
Equal(ns.CustomSpells()["Power Word: Fortitude"][1], 1243, "added spells kept over a reload")
Equal(ns.BarData("buff").spells[1], "Power Word: Fortitude", "with their bar")
Equal(ns.Spells:Find("item:118").name, "Minor Healing Potion", "items on a bar stay listed when your bags run out")
ns.Bars:SetAura("buff", "Power Word: Fortitude", false)
Equal(ns.CustomSpells()["Power Word: Fortitude"], nil, "forgotten once on no bar")

-- Lower ranks on their own ------------------------------------------------------------

Environment()
ns = Load({ useBars = true })
B = ns.Bars
local rank1 = ns.Spells:Find("Moonfire@1")
Equal(rank1 and rank1.spellID, 8921, "rank 1 can be tracked on its own")
Equal(rank1.name, "Moonfire (Rank 1)", "named with its rank")
Equal(ns.Spells:Find("Moonfire@2"), nil, "the highest rank is the normal row")
Equal(#ns.Spells:Find("Moonfire").lower, 1, "one lower rank known")
B:Assign("Moonfire@1", "cd")
B:Assign("Moonfire", "util")
Equal(B:Get("cd").icons[1].spellID, 8921, "the fixed-rank icon uses rank 1")
Equal(B:Get("util").icons[1].spellID, 8924, "the normal one uses the highest")
Book(true)
Settle("SPELLS_CHANGED")
Equal(B:Get("cd").icons[1].spellID, 8921, "training rank 3 leaves the fixed rank alone")
Equal(B:Get("util").icons[1].spellID, 8925, "and moves the normal one up")
Equal(#ns.Spells:Find("Moonfire").lower, 2, "rank 2 now also listed on its own")

SlashCmdList.FECM("")
w = FECMFrame
page = w.pages.bar
Equal(Row("Moonfire@1"), nil, "lower ranks hidden by default")
page.showRanks:Click()
Equal(ns.Get("listRanks"), true, "Show all ranks remembered")
local fixedRow = Row("Moonfire@1")
Equal(fixedRow ~= nil, true, "lower ranks listed when asked")
Equal(S[fixedRow.name].text, "Rank 1", "under the spell as its rank")
Equal(fixedRow.check:GetChecked(), true, "ticked where it's tracked")
Equal(S[Row("Moonfire").rank].text, "Highest (Rank 3)", "the normal row says it follows the highest")
w:Select("util")
Row("Moonfire@2").check:Click()
Equal(ns.BarData("util").spells[2], "Moonfire@2", "a lower rank ticked onto a bar")
w:Select("buff")
Equal(Row("Moonfire@1"), nil, "fixed ranks not offered on the Buffs bar")
Equal(S[page.showRanks].shown, false, "nor the ranks box")
kept = ForeverEnhancedCooldownManagerDB
Environment(true)
ns = Load(kept)
Equal(table.concat(ns.BarData("util").spells, ","), "Moonfire,Moonfire@2", "fixed ranks kept over a reload")

-- Profiles --------------------------------------------------------------------------------

-- Lists saved before profiles become the first character's own profile.
Environment()
character = { guid = "Player-1-0001", name = "Zriel", realm = "Zephras" }
ns = Load({ useBars = true, bars = { cd = { size = 40, spells = { "Moonfire", "Wrath" } } } })
B = ns.Bars
local mine = "Zriel (Druid) - Zephras"
Equal(ns.ProfileName(), mine, "first login makes a profile named Name (Class) - Realm")
Equal(ForeverEnhancedCooldownManagerDB.chars["Player-1-0001"], mine, "kept for this character's GUID")
Equal(table.concat(ns.BarData("cd").spells, ","), "Moonfire,Wrath", "the lists saved before profiles move into it")
Equal(rawget(ForeverEnhancedCooldownManagerDB.bars.cd, "spells"), nil, "and leave the shared bar settings")
Equal(ns.BarData("cd").size, 40, "sizes stay shared")
Equal(B:Get("cd").count, 2, "the bar shows the profile's list")
Equal(#printed, 0, "no warning on a normal first login")

-- A second character gets its own empty profile; a same-named one is told apart.
local saved = ForeverEnhancedCooldownManagerDB
character = { guid = "Player-1-0002", name = "Zriel", realm = "Zephras" }
Environment(true)
ns = Load(saved)
B = ns.Bars
Equal(ns.ProfileName(), mine .. " 2", "a second character with the same name gets its own profile")
Equal(#ns.BarData("cd").spells, 0, "starting empty")
Equal(ns.BarData("cd").size, 40, "with the shared sizes")
Equal(#saved.profiles[mine].cd, 2, "the first character's lists untouched")

-- New, Copy, Rename and Delete.
B:Assign("Thorns", "util")
local ok, message = ns.NewProfile("  Healing  ")
Equal(ok and ns.ProfileName(), "Healing", "New makes a blank profile, trimmed, and switches to it")
Equal(message, "Made Healing, and switched to it.", "and says so")
Equal(#ns.BarData("util").spells, 0, "blank")
Equal(select(2, ns.NewProfile("Healing")), "Healing already exists.", "names are unique")
Equal(select(2, ns.NewProfile("   ")), "Type a profile name first.", "a name is needed")
Equal(select(2, ns.NewProfile("a|b")), "Profile names can't use the | character.", "no escape characters")
Equal(select(2, ns.NewProfile(string.rep("x", 49))), "Profile names can be up to 48 characters.", "names kept short")
ns.UseProfile(mine .. " 2")
Equal(ns.BarData("util").spells[1], "Thorns", "switching brings back that profile's lists")
Equal(B:Get("util").count, 1, "and redraws the bars")
ok = ns.CopyProfile("Thorns copy")
Equal(ok and ns.BarData("util").spells[1], "Thorns", "Copy starts with your lists")
B:Assign("Wrath", "util")
ns.UseProfile(mine .. " 2")
Equal(#ns.BarData("util").spells, 1, "a copy is its own list")
Equal(select(2, ns.UseProfile("Nope")), 'No profile is called "Nope".', "unknown names explained")

-- Sharing: renaming follows every character; a shared one can be deleted
-- too, and says how many others use it (the menu asks first).
ns.UseProfile(mine)
Equal(ns.ProfileUsers(mine), 2, "two characters can share a profile")
ok, message = ns.RenameProfile("Balance")
Equal(ok and saved.chars["Player-1-0001"], "Balance", "renaming updates every character using it")
Equal(saved.profiles[mine], nil, "the old name is gone")
do
    local can, name, others = ns.CanDeleteProfile("Balance")
    Equal(tostring(can) .. " " .. name .. " " .. others, "true Balance 1", "a profile another character uses can be deleted, counting them")
end
ok = ns.DeleteProfile("Healing")
Equal(ok and saved.profiles.Healing, nil, "an unused profile can be deleted by name")
ns.UseProfile("Thorns copy")
ok, message = ns.DeleteProfile("Thorns copy")
Equal(ok and ns.ProfileName(), mine, "deleting your own leaves you on a fresh profile named after you")
Equal(message, "Deleted Thorns copy. You're now on " .. mine .. ".", "and says so")
Equal(#ns.BarData("util").spells, 0, "empty")
lockdown = true
Equal(select(2, ns.NewProfile("War")), "Profiles can't change in combat.", "nothing changes in combat")
Equal(select(2, ns.UseProfile("Balance")), "Profiles can't change in combat.", "not even switching")
lockdown = false

-- Spells added by name stay while any profile uses them.
ns.UseProfile("Balance")
ns.AddCustom("Power Word: Fortitude", { 1243 })
B:SetAura("buff", "Power Word: Fortitude", true)
ns.UseProfile(mine .. " 2")
ns.PruneCustom()
Equal(ns.CustomSpells()["Power Word: Fortitude"] ~= nil, true, "an added spell in another profile is remembered")

-- Profiles are kept over a reload; a lost settings file is a first install -----------------

character = { guid = "Player-1-0001", name = "Zriel", realm = "Zephras" }
Environment(true)
ns = Load(saved)
Equal(ns.ProfileName(), "Balance", "each character's profile kept over a reload")
Equal(ns.BarData("buff").spells[1], "Power Word: Fortitude", "with its lists")
Equal(ns.CustomSpells()["Power Word: Fortitude"][1], 1243, "and added spells")
Equal(ForeverEnhancedCooldownManagerDB.chars["Player-1-0002"], mine .. " 2", "who uses what, too")
Equal(tostring(ns.firstInstall) .. " " .. #printed, "false 0", "a normal reload, with nothing to say")

-- Only the saved settings count: game settings an earlier build kept are
-- never read, so a lost file starts afresh.
Environment()
cvars.FECMBackup = "accent=teal;useBars=1"
cvars.FECMBackupBars0, cvars.FECMBackupBars1 = "1", "cd.size=40;cd.spells=Moonfire"
cvars.ClassicCooldownManagerBackup = "accent=blue;classicBars=1"
ns = Load(nil)
Equal(tostring(ns.firstInstall) .. " " .. ns.Get("accent") .. " " .. tostring(ns.Get("useBars")), "true purple false",
    "a lost settings file is a first install; old backups aren't read")
Equal(#ns.BarData("cd").spells .. " " .. ns.BarData("cd").size .. " " .. ns.ProfileName(), "0 36 Zriel (Druid) - Zephras",
    "starting empty, on a profile of your own")
Equal(#printed, 0, "with nothing printed")
ns.Set("accent", "blue")
ns.SetBarColour(123, "blue")
ns.SetNotesSeen("x")
do
    local count = 0
    for _ in pairs(cvars) do count = count + 1 end
    Equal(count .. " " .. cvars.FECMBackup, "4 accent=teal;useBars=1", "and changes are never written there")
end

-- A kept file: an old login count dropped, and everything checked at load.
do
    Environment()
    ns = Load({ session = 63, accent = "pink", castHeight = 99, useBars = true, bars = { cd = { size = 9999, x = "no" } },
        layout = { on = "yes", above = { "cd", "cd", "nope" } }, custom = { [""] = { 1 }, Good = { 5 } },
        barColours = { [5] = "nope", [6] = "blue" } })
    local db = ForeverEnhancedCooldownManagerDB
    Equal(tostring(ns.firstInstall) .. " " .. tostring(db.session), "false nil", "not a first install, and the login count is gone")
    Equal(ns.Get("accent") .. " " .. ns.Get("castHeight") .. " " .. tostring(ns.Get("useBars")), "purple 18 true",
        "bad settings fall back, good ones stay")
    Equal(db.bars.cd.size .. " " .. tostring(db.bars.cd.x), "64 nil", "bar data put right at load")
    Equal(tostring(db.layout.on) .. " " .. table.concat(db.layout.above, ","), "false cd", "the layout too")
    Equal(tostring(db.custom[""]) .. " " .. tostring(db.custom.Good ~= nil), "nil true", "added spells too")
    Equal(tostring(db.barColours[5]) .. " " .. db.barColours[6], "nil blue", "and each bar's colour")
end

-- A character that logs in before its GUID is known is sorted out at login.
Environment()
local guid = character.guid
character.guid = nil
ns = Load({ useBars = true }, true)
Equal(ns.ProfileName(), nil, "no profile until the character is known")
character.guid = guid
Fire("PLAYER_LOGIN")
Equal(ns.ProfileName(), "Zriel (Druid) - Zephras", "worked out at login")

-- The /ccm window ------------------------------------------------------------------------

Environment()
ns = Load(nil)
B = ns.Bars
SlashCmdList.FECM("")
w = FECMFrame
page = w.pages.bar
Equal(S[w].shown, true, "/ccm opens the window")
Equal(w.nav.cd ~= nil and w.nav.util ~= nil and w.nav.buff ~= nil and w.nav.look ~= nil and w.nav.general ~= nil,
    true, "bars, Look and General listed down the left")
Equal(S[w.yourBars].text, "YOUR BARS", "the bars headed as your own, apart from Blizzard's")
Equal(S[w.nav.cd.fill].shown and not S[w.nav.util.fill].shown, true, "the chosen one highlighted")
Equal(EscapeListed("FECMFrame"), 1, "Escape closes the window: it's on the game's own list, once")
Equal(S[w.close.label].text, "X", "a plain X")
Equal(S[w.note].text, "Made with |TInterface\\AddOns\\ForeverEnhancedCooldownManager\\Media\\Heart.tga:0:0:0:0:32:32:0:32:0:32:176:125:240|t"
    .. " by |cffb07df0Squirt|r", "the footer's credit: the heart and Squirt in the accent")
Equal(S[w.versionText].text, "dev   Options > AddOns or /ccm to open", "the footer shows the version")
w:Refresh()
Equal(S[w.versionText].text, "dev   Options > AddOns or /ccm to open", "and keeps it")

-- Your bars off: each bar page offers to turn them on.
Equal(S[page.turnOn].shown, true, "bar page offers to turn your bars on")
page.turnOn:Click()
Equal(B:Enabled(), true, "and does")
Equal(S[page.turnOn].shown, false, "then the offer goes")

-- The tray: previews, removing, dragging.
B:Assign("Moonfire", "cd")
B:Assign("Wrath", "cd")
B:Assign("Overpower", "cd")
w:Refresh()
Equal(S[w.nav.cd.count].text, 3, "the list shows how many icons each bar has")
Equal(S[w.nav.cd.icons[1]].texture, 136096, "with a preview of them")
Equal(S[w.nav.cd.icons[4]].shown, false, "and no more")
Equal(page.icons[1].name == "Moonfire" and page.icons[3].name == "Overpower", true, "the tray shows the bar in order")
local third = page.icons[3]
S[third].scripts.OnDragStart(third)
Equal(S[third].alpha, 0, "picked up, its spot is empty")
-- Held over another icon: that one is outlined in the accent, and the footer
-- says the two will swap.
S[page.icons[1]].mouseOver = true
S[page.ghost].scripts.OnUpdate(page.ghost)
Equal(tostring(S[page.mark].shown) .. " " .. tostring(S[page.mark].points[1][2] == page.icons[1]) .. " " .. S[w.note].text,
    "true true Let go to swap Overpower and Moonfire.", "held over another icon, it's outlined and the footer says they'll swap")
Equal(S[page.mark].border[1] .. " " .. tostring(S[page.ghost.texture].desaturated), "0.69 false", "outlined in the accent, the held icon in colour")
S[third].scripts.OnDragStop(third)
S[page.icons[1]].mouseOver = nil
Equal(table.concat(ns.BarData("cd").spells, ",") .. " " .. S[w.note].text, "Overpower,Wrath,Moonfire Swapped Overpower and Moonfire.",
    "dropped onto another icon, the two swap places and the one between stays put")
Equal(tostring(S[page.mark].shown) .. " " .. tostring(w.dragging), "false nil", "let go, the outline and the footer's drag note go")
-- The icon next to it: they swap too.
S[page.icons[2]].scripts.OnDragStart(page.icons[2])
S[page.icons[3]].mouseOver = true
S[page.icons[2]].scripts.OnDragStop(page.icons[2])
S[page.icons[3]].mouseOver = nil
Equal(table.concat(ns.BarData("cd").spells, ","), "Overpower,Moonfire,Wrath", "swapped with the icon beside it")
S[page.icons[1]].scripts.OnDragStart(page.icons[1])
S[page.icons[1]].mouseOver = true
S[page.ghost].scripts.OnUpdate(page.ghost)
Equal(tostring(S[page.mark].shown) .. " " .. S[w.note].text, "false Let go to leave Overpower where it is.",
    "over its own spot, nothing is outlined")
S[page.icons[1]].mouseOver = nil
S[page.tray].mouseOver = true
S[page.ghost].scripts.OnUpdate(page.ghost)
Equal(tostring(S[page.mark].shown) .. " " .. S[w.note].text, "false Let go to put Overpower last.", "over the tray's empty space, it goes last")
S[page.icons[1]].scripts.OnDragStop(page.icons[1])
S[page.tray].mouseOver = nil
Equal(table.concat(ns.BarData("cd").spells, ","), "Moonfire,Wrath,Overpower", "dropping on empty tray space moves it to the end")
S[page.icons[1]].scripts.OnDragStart(page.icons[1])
S[page.ghost].scripts.OnUpdate(page.ghost)
Equal(tostring(S[page.ghost.texture].desaturated) .. " " .. S[w.note].text, "true Let go to take Moonfire off Cooldowns.",
    "off the bar, the held icon greys and the footer says it comes off")
S[page.icons[1]].scripts.OnDragStop(page.icons[1])
Equal(table.concat(ns.BarData("cd").spells, ",") .. " " .. S[w.note].text, "Wrath,Overpower Took Moonfire off Cooldowns.",
    "dragged off the tray, it comes off the bar")
B:Assign("Moonfire", "cd")
B:MoveTo("cd", 3, 1)
w:Refresh()
page.icons[2].remove:Click()
Equal(table.concat(ns.BarData("cd").spells, ","), "Moonfire,Overpower", "x takes an icon off")
Equal(S[page.icons[3]].shown, false, "and the tray closes up")

-- Options.
S[page.size].scripts.OnMouseWheel(page.size, 1)
Equal(ns.BarData("cd").size, 38, "the size slider steps by 2")
page.size:Choose(100)
Equal(ns.BarData("cd").size, 64, "and stays within its limits")
Equal(S[page.size.value].text, 64, "showing the value")
page.spacing:Choose(7)
Equal(ns.BarData("cd").spacing, 7, "spacing set")
page.options.showTimer:Click()
Equal(ns.BarData("cd").showTimer, false, "countdown numbers switched off for this bar")
Equal(Last(B:Get("cd").icons[1].cooldown, "SetHideCountdownNumbers"), true, "and hidden on its icons")
do
    local ready = page.options.whenReady
    Equal(tostring(S[ready].shown and S[ready.label].shown and not S[page.options.showMissing].shown) .. " " .. S[ready.label].text
        .. " " .. ready.selected, "true When ready show", "cooldown bars offer When ready, showing the bar's choice")
    -- Show, Dim or Hide, one at a time, in the spot the Hide when ready tick had.
    local labels = {}
    for _, button in ipairs(ready.buttons) do labels[#labels + 1] = S[button.label].text end
    local at = S[ready].points[1]
    Equal(table.concat(labels, " ") .. " | " .. at[1] .. " " .. at[2] .. " " .. at[3], "Show Dim Hide | TOPLEFT 420 0",
        "three choices, beside the options' first tick row")
    -- The label and its choices as one part for the tour, from the label's
    -- start to the buttons' end and level with the buttons, top and bottom
    -- (the label alone ends above them).
    local part, lt = S[ready.part], S[ready.label].points[1]
    local pt = part.points[1]
    Equal(pt[1] .. " " .. pt[2] .. " " .. pt[3] .. " " .. tostring(pt[2] == lt[2] and pt[2] + part.width == at[2] + S[ready].width
        and pt[3] == at[3] and pt[3] - part.height == at[3] - S[ready].height and #part.points == 1),
        "TOPLEFT 320 0 true", "one part round When ready and its choices, for the tour")
    ready.buttons[2]:Click()
    Equal(ns.BarData("cd").whenReady .. " " .. ready.selected .. " " .. S[B:Get("cd").icons[1]].alpha, "dim dim 0.4",
        "clicking Dim sets it, shows it, and a ready icon on the bar dims")
    ready.buttons[3]:Click()
    Equal(ns.BarData("cd").whenReady .. " " .. ready.selected, "hide hide", "Hide instead: one choice at a time")
    -- Each says what it does; Dim that it needs testing.
    local notes = {}
    for _, button in ipairs(ready.buttons) do
        S[button].scripts.OnEnter(button)
        notes[#notes + 1] = S[w.note].text
        S[button].scripts.OnLeave(button)
    end
    Equal(table.concat(notes, " | "), "Every icon shows in full, ready or cooling down. | "
        .. "Each icon dims while it's ready, so the ones cooling down stand out. | "
        .. "Each icon hides while it's ready, so only the ones cooling down show.", "each choice's note")
    ready.buttons[1]:Click()
    w:Select("buff")
    Equal(S[page.options.showMissing].shown and not S[ready].shown and not S[ready.label].shown, true,
        "the Buffs bar offers missing buffs greyed there instead")
end
Equal(page.options.showTimer:GetChecked(), true, "each bar keeps its own countdown choice")
Equal(page.size.current, 36, "and its own size")

-- Clearing a bar takes two clicks.
w:Select("cd")
Equal(S[page.clear.label].text, "Clear Cooldowns", "clear names the bar")
page.clear:Click()
Equal(#ns.BarData("cd").spells, 2, "one click only asks")
Equal(S[page.clear.label].text, "Click again to clear", "and says so")
page.clear:Click()
Equal(#ns.BarData("cd").spells, 0, "the second click clears")
Equal(S[w.note].text, "Cooldowns cleared.", "and confirms")
Equal(S[page.clear].shown, false, "nothing left to clear")
B:Assign("Moonfire", "cd")
w:Refresh()
page.clear:Click()
for _, timer in ipairs(timers) do timer() end
page.clear:Click()
Equal(#ns.BarData("cd").spells, 1, "after a pause, the next click asks again")

-- Look: the restyle, reload and accent.
w:Select("look")
Equal(S[w.pages.look].shown and not S[page].shown, true, "Look page shown")
Equal(w.look:GetChecked(), true, "restyle shown as on")
Equal(S[w.look.text].text .. "|" .. S[w.personal.text].text .. "|" .. S[w.repeatMana.text].text,
    "Apply this look to the Cooldown Manager|Apply this look to the Personal Resource Display|Extra mana bar: hide in caster form, half size in forms",
    "the ticks say what they apply to")
Equal(S[w.off].shown, false, "no Cooldown Manager warning while it is on")
Equal(S[w.reload].shown, false, "no reload needed yet")
w.look:Click()
Equal(ForeverEnhancedCooldownManagerDB.skin, false, "unticking saves the choice")
Equal(S[w.reload].shown, true, "reload offered after a change")
Equal(S[w.reload.label].text, "Reload to apply", "saying why")
lockdown = true
w.reload:Click()
Equal(reloads, 0, "no reload in combat")
Equal(S[w.note].text, "Finish combat first, then reload.", "explains why")
lockdown = false
w.reload:Click()
Equal(reloads, 1, "reloads straight from the click")
w.look:Click()
Equal(S[w.reload].shown, false, "changing back needs no reload")

local function Heading(text)
    for i = #objects, 1, -1 do
        if S[objects[i]] and S[objects[i]].text == text then return objects[i] end
    end
end
local accentHeading = Heading("EACH BAR")
Equal(accentHeading ~= nil, true, "headings in small capitals")
Equal(S[accentHeading].colour[1] == .69 and S[accentHeading].colour[2], .49, "headings in purple by default")
Equal(#w.swatches, 5, "five window accents")
Equal(w.swatches[1].key, "orange", "orange first")
w.swatches[3]:Click()
Equal(ns.Get("accent"), "teal", "a set colour chosen")
Equal(S[accentHeading].colour[1] == .17 and S[accentHeading].colour[2], .70, "the whole window repaints")
Equal(S[w.swatches[3]].border[1], 1, "chosen swatch outlined")
Equal(S[w.swatches[1]].border[1] < 1, true, "the others not")
w.swatches[1]:Click()
Equal(ns.Get("accent"), "orange", "back to orange")

-- A wash of the accent from the right, and a line round the Each bar box.
local function Wash(texture)
    local from, to = Last(texture, "SetGradient", 2), Last(texture, "SetGradient", 3)
    return Last(texture, "SetGradient", 1) == "HORIZONTAL" and from.a == 0 and to.r == .88 and to.a
end
Equal(Wash(w.fades.header), .30, "the title bar fades in from the right, in the accent")
Equal(Wash(w.fades.page), .18, "softer behind the pages")
Equal(Wash(w.nav.look.glow), .36, "stronger on the chosen menu item")
Equal(S[w.nav.look.glow].shown and not S[w.nav.general.glow].shown, true, "only the chosen one")
Equal(S[w.eachPanel].border[1], .88, "the Each bar box outlined in the accent")
Equal(S[page.listPanel].border[1], .88, "and each bar page's spell list")
Equal(S[page.tray].border[1] < .5, true, "the smaller box at the top keeps a plain line")
w.swatches[3]:Click()
Equal(Last(w.fades.header, "SetGradient", 3).r == .17 and S[w.eachPanel].border[1], .17, "all repainted with a new accent")
w.swatches[1]:Click()
-- The Class swatch shows your class icon, so it isn't a second orange.
Equal(Last(w.barSwatches[6].icon, "SetAtlas", 1), "classicon-druid", "class icon on the Class swatch")
Equal(w.barSwatches[1].icon, nil, "the other swatches are plain colour")

-- Tracked Bars: a design and a colour.
Equal(w.barDesign.selected, "glass", "Glass by default")
w.barDesign.buttons[3]:Click()
Equal(ns.Get("barStyle"), "outline", "Outline chosen")
Equal(w.barDesign.selected, "outline", "and shown")
Equal(#w.barSwatches, 6, "six bar colours")
Equal(w.barSwatches[6].key, "class", "your class colour last")
w.barSwatches[3]:Click()
Equal(ns.Get("barColour"), "blue", "a colour chosen")
Equal(S[w.barSwatches[3]].border[1], 1, "its swatch outlined")
Equal(S[w.barSwatches[1]].border[1] < 1, true, "the others not")
Equal(Last(w.preview.Bar, "SetStatusBarColor", 3), .88, "the preview bar shows it")
w.barDesign.buttons[1]:Click()
w.barSwatches[1]:Click()
Equal(Last(w.preview.Bar, "SetStatusBarColor", 1), 1, "and changes back")

-- Each Tracked Bar in a colour of its own, listed from Blizzard's bars.
local function Tracked(id, order)
    return { GetBaseSpellID = function() return id end, layoutIndex = order }
end
local tracked = { [Tracked(1243, 2)] = true, [Tracked(16870, 1)] = true }
_G.BuffBarCooldownViewer = { itemFramePool = { EnumerateActive = function() return pairs(tracked) end } }
w:Refresh()
local rows = w.eachRows
Equal(S[rows[1].name].text .. "," .. S[rows[2].name].text, "Clearcasting,Power Word: Fortitude", "your Tracked Bars, in Blizzard's order")
Equal(Last(rows[1].swatches[6].icon, "SetAtlas", 1), "classicon-druid", "each bar's Class swatch shows the icon too")
Equal(S[rows[1].chosen].text, "Default", "each uses the colour for all at first")
-- Round its swatches, a row says what it's for.
local function Hover(region, script) if S[region].scripts[script] then S[region].scripts[script](region) end end
Hover(rows[1], "OnEnter")
Equal(S[w.note].text .. " | " .. tostring(Last(rows[1], "EnableMouse")), "Clearcasting: click a colour on the right for this bar alone. | true",
    "hovering a bar's row, its note")
Hover(rows[1], "OnLeave")
Equal(S[w.eachEmpty].shown, false, "no note while there are bars")
rows[1].swatches[4]:Click()
Equal(ns.BarColours()[16870], "green", "a colour picked for one bar")
Equal(S[rows[1].chosen].text, "Green", "and named")
Equal(S[rows[1].swatches[4]].border[1], 1, "its swatch outlined")
Equal(S[rows[2].chosen].text, "Default", "the other bar unchanged")
rows[1].swatches[4]:Click()
Equal(ns.BarColours()[16870], nil, "clicking it again goes back to the colour for all")
Equal(S[rows[1].chosen].text, "Default", "and says so")
-- Since build 70170 Blizzard shows every rank of a spell on one bar, under
-- one rank's ID: a colour picked at another rank still shows, and changing
-- it leaves the spell one colour, under the bar's own ID.
ns.BarColours()[1244] = "blue" -- Power Word: Fortitude rank 2, picked before the patch
w:Refresh()
Equal(S[rows[2].chosen].text .. " " .. S[rows[2].swatches[3]].border[1], "Blue 1", "a colour saved at rank 2 shows on the rank 1 bar")
ns.BarColours()[1243] = "green" -- and one at rank 1, the older pick
w:Refresh()
Equal(S[rows[2].chosen].text .. " " .. S[rows[2].swatches[3]].border[1], "Blue 1", "with colours at both ranks, the higher rank's")
rows[2].swatches[3]:Click()
Equal(tostring(ns.BarColours()[1244]) .. " " .. tostring(ns.BarColours()[1243]) .. " " .. S[rows[2].chosen].text,
    "nil nil Default", "clicking it again goes back to the colour for all, at every rank")
ns.BarColours()[1244] = "blue"
rows[2].swatches[5]:Click()
Equal(tostring(ns.BarColours()[1244]) .. " " .. tostring(ns.BarColours()[1243]) .. " " .. S[rows[2].chosen].text,
    "nil purple Purple", "another colour goes under the bar's own ID")
ns.SetBarColour(1243, nil)
tracked = {}
w:Refresh()
Equal(S[rows[1]].shown, false, "rows go with the bars")
Equal(S[w.eachEmpty].text:find("Tracked Bars (buffs shown as timer bars)", 1, true) ~= nil, true, "and the list says what they are and where to add some")
Equal(S[w.eachFix].shown, false, "with no button: that's done in Blizzard's Cooldown Settings")
ns.loaded.skin = false
w:Refresh()
Equal(S[w.eachEmpty].text .. " " .. S[w.eachFix.label].text, "Reload first, then colour your bars one by one here. Reload",
    "just ticked: reload first, with a button for it")
ns.Set("skin", false)
w:Refresh()
Equal(S[w.eachEmpty].text .. " " .. S[w.eachFix.label].text,
    "Apply this look to the Cooldown Manager and reload to colour your bars one by one. Turn on", "with the look off, a button to turn it on")
w.eachFix:Click()
Equal(tostring(ns.Get("skin")) .. " " .. S[w.eachEmpty].text, "true Reload first, then colour your bars one by one here.",
    "which ticks it, then asks for the reload")
ns.Set("skin", true)
ns.loaded.skin = true
_G.BuffBarCooldownViewer = nil
-- The Personal Resource Display's bars, listed first while it's on.
_G.PersonalResourceDisplayFrame = {}
w:Refresh()
Equal(S[rows[1].name].text .. "," .. S[rows[2].name].text, "Personal health,Personal power", "the personal bars listed first")
rows[2].swatches[5]:Click()
Equal(ns.Get("prdPower"), "purple", "a colour for the personal power bar")
Equal(S[rows[2].chosen].text, "Purple", "and named")
rows[2].swatches[5]:Click()
Equal(ns.Get("prdPower"), "default", "clicking it again goes back to Blizzard's")
w.repeatMana:Click()
Equal(ns.Get("prdHideRepeat"), false, "the repeat mana bar can be kept")
w.repeatMana:Click()
w.personal:Click()
Equal(ns.Get("prdSkin") == false and S[w.reload].shown, true, "turning the restyle off asks for a reload")
w.personal:Click()
Equal(S[w.reload].shown, false, "and back on needs none")
_G.PersonalResourceDisplayFrame = nil

-- Joined buttons (for the pill choices): no smeared shadow on a light accent.
local pills = ns.Theme:Segmented(UIParent, { { key = "a", label = "Show" }, { key = "b", label = "Fade" } }, 120, function() end)
pills:SetSelected("a")
Equal(S[pills.buttons[1].label].shadow, 0, "dark text on a light accent has no smeared shadow")
Equal(S[pills.buttons[2].label].shadow, 1, "light text on dark keeps its shadow")

-- General: your bars and moving them.
w:Select("general")
-- No saved-settings section: More from Squirt sits under the tour and Discord.
Equal(tostring(w.kept) .. " " .. tostring(Heading("SAVED SETTINGS") ~= nil), "nil false", "no saved-settings text or heading")
Equal(S[Heading("MORE FROM SQUIRT")].points[1][3], -236, "More from Squirt closes the gap")
-- More from Squirt: EraUI, and a way to open it.
Equal(S[w.moreOpen].shown, false, "EraUI not installed: no Open button")
Equal(S[w.moreLinks[1]].shown and S[w.moreLinks[2]].shown, true, "but CurseForge and GitHub buttons")
w.moreLinks[1]:Click()
local copy = FECMCopyLink
Equal(S[copy].shown and S[copy.title].text, "ERAUI ON CURSEFORGE", "each opens a box in the window's own look")
Equal(copy.input:GetText(), "https://www.curseforge.com/wow/addons/eraui", "with its link to copy")
copy.input:SetText("typed over")
S[copy.input].scripts.OnTextChanged(copy.input)
Equal(copy.input:GetText(), "https://www.curseforge.com/wow/addons/eraui", "which can't be typed over")
Equal(S[copy.note].text:find("On CurseForge, Install opens the CurseForge app.", 1, true) ~= nil, true,
    "CurseForge's box says Install opens the app")
copy.close:Click()
Equal(S[copy].shown, false, "Close closes it")
w.moreLinks[2]:Click()
Equal(S[copy.title].text .. "|" .. copy.input:GetText(), "ERAUI ON GITHUB|https://github.com/squirtwow/EraUI", "GitHub's box")
Equal(S[copy.note].text, "Press Ctrl+C to copy, then paste it into your browser.", "says only how to copy")
copy.close:Click()
_G.C_AddOns = { IsAddOnLoaded = function(name) return name == "EraUI" end }
local eraOpened
SlashCmdList.ERAUI = function() eraOpened = true end
w:Refresh()
Equal(S[w.moreOpen].shown, true, "installed: an Open button")
Equal(S[w.moreLinks[1]].shown, false, "and no links")
w.moreOpen:Click()
Equal(eraOpened and not S[w].shown, true, "which opens EraUI and closes this window")
_G.C_AddOns, SlashCmdList.ERAUI = nil, nil
ns.ShowWindow()
w:Select("general")
Equal(w.useBars:GetChecked(), true, "own bars shown as on")
w.useBars:Click()
Equal(B:Enabled(), false, "Use my bars turns them off")
-- Unlocking lives on the Layout page.
local unlock = w.pages.layout.unlock
w:Select("layout")
unlock:Click()
Equal(S[w.note].text, "Turn your bars on first.", "can't unlock while the bars are off")
w:Select("general")
w.useBars:Click()
w:Select("layout")
unlock:Click()
Equal(B:IsUnlocked(), true, "unlocked")
Equal(S[unlock.label].text .. " | " .. S[w.pages.layout.status].text, "Lock bars | Unlocked: drag a bar on screen to move it.",
    "button offers to lock, and the page says so")
unlock:Click()
Equal(B:IsUnlocked(), false, "locked again")
unlock:Click()
w:Hide()
Equal(B:IsUnlocked(), false, "closing the window locks them")
ns.ShowWindow()

-- Escape: the game hides every window on its list, in a fight too, and the
-- addon never touches a key binding, before, during or after the fight.
Fire("PLAYER_REGEN_DISABLED")
lockdown = true
Equal(tostring(CloseSpecialWindows()) .. " " .. tostring(S[w].shown), "1 false", "Escape in a fight closes it")
lockdown = false
Fire("PLAYER_REGEN_ENABLED")
ns.ShowWindow()
Equal(tostring(CloseSpecialWindows()) .. " " .. tostring(S[w].shown), "1 false", "and out of one")
Equal(tostring(CloseSpecialWindows()), "nil", "nothing of the addon's open: Escape goes on to the game's menu")
Equal(#bindings .. " " .. EscapeListed("FECMFrame"), "0 1", "no key binding changed, the window listed once however often it opens")

-- Alt+Z hides the interface, running the window's OnHide though it's still
-- shown. Bringing it back (Alt+Z again, or Escape, which brings it back
-- first) runs its OnShow, and the game then closes every window on its
-- list, as it does its own (UIParent.lua OnShow, Game.lua
-- UI.TopLevelParentShown, CloseAllWindows). No key binding is touched.
do
    ns.ShowWindow()
    S[UIParent].shown = false
    S[w].scripts.OnHide(w)
    Equal(tostring(S[w].shown) .. " " .. #bindings, "true 0", "the interface hidden: still open, no key binding changed")
    S[UIParent].shown = true
    S[w].scripts.OnShow(w)
    CloseSpecialWindows() -- the game's CloseAllWindows as the interface comes back
    Equal(tostring(S[w].shown) .. " " .. #bindings, "false 0", "the interface back: the game closes it, no key binding changed")
    Equal(CloseSpecialWindows(), nil, "then Escape goes on to the game's menu")

    -- Closed mid-drag, nothing keeps following the cursor: the window, a
    -- slider or a list's scroll thumb.
    ns.ShowWindow()
    S[w].last.StopMovingOrSizing = nil
    w:Hide()
    Equal(S[w].last.StopMovingOrSizing ~= nil, true, "closing the window stops it moving")
    local slider = ns.Theme:Slider(UIParent, "Size", { 1, 10 }, 1, 200, function() end)
    slider:Set(5)
    S[slider.track].scripts.OnMouseDown(slider.track)
    Equal(S[slider.track].scripts.OnUpdate ~= nil, true, "a slider follows the cursor while held")
    slider.track:Hide()
    Equal(S[slider.track].scripts.OnUpdate, nil, "and stops once hidden")
    local thumb = ns.Theme:Scroll(UIParent, 100).thumb
    S[thumb].shown = true
    S[thumb].scripts.OnMouseDown(thumb)
    Equal(thumb.drag ~= nil, true, "a scroll thumb follows it while held")
    thumb:Hide()
    Equal(thumb.drag, nil, "and stops once hidden")
end

SlashCmdList.FECM("check")
Equal(S[w].shown, true, "anything after /ccm but new just opens the window")
cvarOn = false
w:Select("look")
Equal(S[w.off].shown, true, "warns when Blizzard's Cooldown Manager is off")
Equal(S[w.eachEmpty].text .. " " .. S[w.eachFix.label].text .. " " .. tostring(S[w.eachFix].shown),
    "Blizzard's Cooldown Manager is off. Turn on true", "and the list says so, with its own Turn on")
Equal(S[w.turnOnManager].shown, true, "with a way to turn it on")
Equal(S[w.reload].shown, false, "no reload asked for yet")
lockdown = true
w.turnOnManager:Click()
Equal(tostring(cvarOn) .. " " .. tostring(S[w.reload].shown) .. " " .. S[w.note].text, "false false Finish combat first.",
    "never switched in a fight, so no reload asked for")
lockdown = false
w.eachFix:Click()
Equal(cvarOn, true, "the list's button switches it on too")
-- Blizzard's own code runs at once for the setting, inside the click: a
-- reload finishes it cleanly.
Equal(tostring(S[w.reload].shown) .. " " .. S[w.note].text, "true Blizzard's Cooldown Manager is on. Reload to finish.",
    "and asks for a reload to finish, with the Reload button showing")
cvarOn = false
w:Refresh()
w.turnOnManager:Click()
Equal(cvarOn and S[w.note].text, "Blizzard's Cooldown Manager is on. Reload to finish.", "which switches it on")
Equal(S[w.off].shown or S[w.turnOnManager].shown, false, "and the warning goes")
prdOn = false
w:Refresh()
Equal(S[w.personalOff].shown and S[w.turnOnPersonal].shown, true, "a Personal Resource Display that's off is pointed out too")
lockdown = true
w.turnOnPersonal:Click()
Equal(prdOn == false and S[w.note].text, "Finish combat first.", "never switched in combat")
lockdown = false
w.turnOnPersonal:Click()
Equal(prdOn and S[w.personalOff].shown, false, "switched on, and the note goes")
Equal(tostring(S[w.reload].shown) .. " " .. S[w.note].text, "true Your Personal Resource Display is on. Reload to finish.",
    "a reload asked for too")
reloads = 0
w.reload:Click()
Equal(reloads, 1, "Reload to apply reloads")
Equal(#printed, 0, "no errors")

-- The profile menu ---------------------------------------------------------------------

Environment()
character = { guid = "Player-1-0001", name = "Zriel", realm = "Zephras" }
ns = Load({ useBars = true })
B = ns.Bars
SlashCmdList.FECM("")
w = FECMFrame
local profile = w.profileButton
Equal(S[profile.label].text, "|cff8b8d92Profile|r   Zriel (Druid) - Zephras", "the header shows your profile")
Equal(S[w.profilePanel].shown, false, "the menu starts closed")
profile:Click()
Equal(S[w.profilePanel].shown, true, "clicking opens it")
local function MenuRow(name)
    for _, f in ipairs(frames) do
        if f.profile == name and S[f].shown then return f end
    end
end
local own = MenuRow("Zriel (Druid) - Zephras")
Equal(own ~= nil and S[own.users].text, "you", "each profile listed with who uses it")
Equal(S[own.fill].shown, true, "yours highlighted")
local input = w.profileInput
Equal(w.profileActions.delete, nil, "no Delete button to type a name for")
input:SetText("Resto")
w.profileActions.new:Click()
Equal(ns.ProfileName(), "Resto", "New from the menu")
Equal(S[w.note].text, "Made Resto, and switched to it.", "confirmed in the footer")
Equal(S[w.profilePanel].shown, false, "the menu closes once you've switched")
Equal(input:GetText(), "", "the box clears")
profile:Click()
Equal(S[MenuRow("Zriel (Druid) - Zephras").users].text, "unused", "the other profile shows as unused")
MenuRow("Zriel (Druid) - Zephras"):Click()
Equal(ns.ProfileName(), "Zriel (Druid) - Zephras", "clicking a profile switches to it")
Equal(S[w.profilePanel].shown, false, "and closes the menu")

-- Deleting: the x on a row, then a question.
profile:Click()
local confirm = w.confirm
Equal(S[confirm.shade].shown, false, "no question until asked")
MenuRow("Resto").remove:Click()
Equal(S[confirm.shade].shown, true, "x asks first")
Equal(S[confirm.dialog.title].text, 'Delete "Resto"?', "naming the profile")
Equal(S[confirm.dialog.detail].text, "This can't be undone.", "with a warning")
confirm.no:Click()
Equal(S[confirm.shade].shown, false, "Cancel closes the question")
Equal(ns.ProfileNames()[1], "Resto", "and keeps the profile")
MenuRow("Resto").remove:Click()
confirm.yes:Click()
Equal(#ns.ProfileNames(), 1, "Delete removes it")
Equal(S[w.note].text, "Deleted Resto.", "and says so")
Equal(S[w.profilePanel].shown, true, "the menu stays open, showing the shorter list")
ForeverEnhancedCooldownManagerDB.chars["Player-1-0009"] = "Zriel (Druid) - Zephras"
w:Refresh()
MenuRow("Zriel (Druid) - Zephras").remove:Click()
Equal(S[confirm.dialog.detail].text, "You're using it, so you'll move to a new, empty profile of your own. Another character uses it, "
    .. "and gets a new, empty profile of its own at its next login. This can't be undone.",
    "a profile another character uses is asked about too, saying what happens to that character")
confirm.no:Click()
ForeverEnhancedCooldownManagerDB.chars["Player-1-0009"] = nil
w:Refresh()
MenuRow("Zriel (Druid) - Zephras").remove:Click()
Equal(S[confirm.dialog.detail].text:find("new, empty profile", 1, true) ~= nil, true, "deleting your own says where you'll go")
confirm.yes:Click()
Equal(ns.ProfileName(), "Zriel (Druid) - Zephras", "a fresh profile named after you")
Equal(S[w.profilePanel].shown, false, "and the menu closes, as for any switch")
profile:Click()
MenuRow("Zriel (Druid) - Zephras").remove:Click()
w:Hide()
Equal(S[confirm.shade].shown, false, "closing the window drops the question")
ns.ShowWindow()
input:SetText("")
w.profileActions.rename:Click()
Equal(S[w.note].text, "Type a profile name first.", "problems explained in the footer")
w:Select("look")
Equal(S[w.profilePanel].shown, false, "changing page closes the menu")

-- Use on all characters: the profile you're on, for every character and new ones.
local db = ForeverEnhancedCooldownManagerDB
db.profiles["Kess (Rogue) - Zephras"] = { cd = {}, util = {}, buff = {}, debuff = {}, joins = {} }
db.chars["Player-1-0009"] = "Kess (Rogue) - Zephras"
profile:Click()
Equal(S[w.profileEveryone.label].text .. " | " .. S[MenuRow("Kess (Rogue) - Zephras").users].text,
    "Use on all characters | 1 character", "a button to put your profile on every character")
w.profileEveryone:Click()
Equal(S[confirm.dialog.title].text, 'Use "Zriel (Druid) - Zephras" on all characters?', "asked first")
Equal(S[confirm.dialog].height > 112, true, "a long name wraps and the question grows to fit")
confirm.yes:Click()
Equal(db.chars["Player-1-0009"] .. " | " .. S[w.note].text,
    "Zriel (Druid) - Zephras | All your characters use Zriel (Druid) - Zephras now, and new ones will too.", "every character moves to it")
profile:Click()
Equal(S[MenuRow("Zriel (Druid) - Zephras").users].text .. " | " .. S[w.profileEveryone.label].text .. " | "
    .. S[MenuRow("Kess (Rogue) - Zephras").users].text, "all characters | On all characters | unused", "and the menu says so")
w.profileEveryone:Click()
Equal(tostring(S[confirm.shade].shown) .. " " .. S[w.note].text, "false All your characters already use Zriel (Druid) - Zephras.",
    "nothing to ask once it's on them all")
-- A character logging in for the first time starts on it.
character = { guid = "Player-1-0042", name = "Tarn", realm = "Zephras" }
Environment(true)
ns = Load(db)
Equal(ns.ProfileName() .. " | " .. tostring(db.profiles["Tarn (Druid) - Zephras"]), "Zriel (Druid) - Zephras | nil",
    "a new character starts on it, without a profile of its own")
Equal(ns.RenameProfile("Shared") and ns.EveryoneProfile(), "Shared", "renaming it keeps it on everyone")
-- Kept over a reload.
Environment(true)
ns = Load(db)
Equal(tostring(ns.EveryoneProfile()) .. " " .. tostring(ForeverEnhancedCooldownManagerDB.chars["Player-1-0042"]), "Shared Shared",
    "kept over a reload")

-- A character's very first login, before the game knows its name: its own
-- profile waits for the name, and one already made as "Unknown" takes it.
character = { guid = "Player-1-0077", name = "Unknown", realm = "Zephras" }
Environment()
ns = Load({ useBars = true }, true)
Equal(tostring(ns.ProfileName()), "nil", "no profile made before the game knows the name")
character.name = "Dayseeker"
Fire("PLAYER_LOGIN")
Equal(ns.ProfileName(), "Dayseeker (Druid) - Zephras", "made at login, with the name")
local early = ForeverEnhancedCooldownManagerDB
early.profiles["Unknown (Druid) - Zephras"], early.profiles["Dayseeker (Druid) - Zephras"] = early.profiles["Dayseeker (Druid) - Zephras"], nil
early.chars["Player-1-0077"] = "Unknown (Druid) - Zephras"
Environment(true)
ns = Load(early)
Equal(ns.ProfileName() .. " " .. tostring(early.profiles["Unknown (Druid) - Zephras"]), "Dayseeker (Druid) - Zephras nil",
    "one made as Unknown takes the character's name")
-- Still no name at login: a profile anyway. One you named yourself keeps its name.
character = { guid = "Player-1-0078", name = "Unknown", realm = "Zephras" }
Environment()
ns = Load({ useBars = true })
Equal(ns.ProfileName(), "Unknown (Druid) - Zephras", "still no name at login: a profile anyway")
local named = ForeverEnhancedCooldownManagerDB
named.profiles["Resto"], named.profiles["Unknown (Druid) - Zephras"] = named.profiles["Unknown (Druid) - Zephras"], nil
named.chars["Player-1-0078"] = "Resto"
character.name = "Tarn"
Environment(true)
ns = Load(named)
Equal(ns.ProfileName(), "Resto", "a profile you named keeps its name")
-- Forever gives a surname apart from the first name: a new profile's name
-- has it, so two characters of one first name tell apart. Profiles made
-- before keep their names, found by the character's GUID as ever.
do
    local surname = "Gustbellow"
    local function Named() _G.UnitName = function(unit) assert(unit == "player"); return character.name, surname end end
    character = { guid = "Player-1-0005", name = "Zriel", realm = "Zephras" }
    Environment()
    Named()
    ns = Load({ useBars = true })
    local db = ForeverEnhancedCooldownManagerDB
    Equal(ns.ProfileName(), "Zriel Gustbellow (Druid) - Zephras", "a new profile has the surname too")
    surname = "Moonfeather"
    Environment(true)
    Named()
    ns = Load(db)
    Equal(ns.ProfileName(), "Zriel Gustbellow (Druid) - Zephras", "the same character later: its profile by its GUID, its name kept")
    character.guid, surname = "Player-1-0006", SECRETS.string
    Environment(true)
    Named()
    ns = Load(db)
    Equal(ns.ProfileName() .. " " .. #printed, "Zriel (Druid) - Zephras 0", "a surname the game hides: left out, no errors")
end
character = { guid = "Player-1-0001", name = "Zriel", realm = "Zephras" }

-- A profile other characters use, even ones since deleted, can be deleted:
-- they get a profile of their own at their next login.
do
    local function Lists() return { cd = {}, util = {}, buff = {}, debuff = {}, joins = {} } end
    Environment()
    ns = Load({ useBars = true, profiles = { Mine = Lists(), Dead = Lists(), Shared = Lists() },
        chars = { ["Player-1-0001"] = "Mine", ["Player-1-0099"] = "Dead", ["Player-1-0002"] = "Shared", ["Player-1-0003"] = "Shared" } })
    local db = ForeverEnhancedCooldownManagerDB
    local can, name, others = ns.CanDeleteProfile("Dead")
    Equal(tostring(can) .. " " .. name .. " " .. others, "true Dead 1", "a profile a deleted character used can go")
    Equal(select(3, ns.CanDeleteProfile("Mine")), 0, "your own counts no others")
    SlashCmdList.FECM("")
    w = FECMFrame
    w.profileButton:Click()
    MenuRow("Dead").remove:Click()
    Equal(tostring(S[w.confirm.shade].shown) .. " " .. S[w.confirm.dialog.detail].text,
        "true Another character uses it, and gets a new, empty profile of its own at its next login. This can't be undone.",
        "asked first, saying what happens to that character")
    w.confirm.yes:Click()
    Equal(tostring(db.profiles.Dead) .. " " .. tostring(db.chars["Player-1-0099"]) .. " " .. S[w.note].text, "nil nil Deleted Dead.",
        "deleted, and the character let go")
    MenuRow("Shared").remove:Click()
    Equal(S[w.confirm.dialog.detail].text,
        "2 other characters use it, and each gets a new, empty profile of its own at its next login. This can't be undone.",
        "several characters")
    w.confirm.no:Click()
    db.everyone = "Mine"
    MenuRow("Shared").remove:Click()
    Equal(S[w.confirm.dialog.detail].text, "2 other characters use it, and each loads Mine at its next login. This can't be undone.",
        "with a profile for every character, they load that")
    w.confirm.yes:Click()
    Equal(tostring(db.chars["Player-1-0002"]) .. " " .. tostring(db.chars["Player-1-0003"]), "nil nil", "both let go")
    -- Your own, shared: you move to a new one, and the other is let go.
    db.everyone = nil
    db.profiles.Shared = Lists()
    db.chars["Player-1-0002"] = "Mine"
    w:Refresh()
    MenuRow("Mine").remove:Click()
    Equal(S[w.confirm.dialog.detail].text, "You're using it, so you'll move to a new, empty profile of your own. Another character uses it, "
        .. "and gets a new, empty profile of its own at its next login. This can't be undone.", "your own, shared")
    w.confirm.yes:Click()
    Equal(ns.ProfileName() .. " " .. tostring(db.chars["Player-1-0002"]), "Zriel (Druid) - Zephras nil", "you move, it's let go")
    -- That character logs in and gets a profile as a new one would.
    character = { guid = "Player-1-0002", name = "Kess", realm = "Zephras" }
    Environment(true)
    ns = Load(db)
    Equal(ns.ProfileName() .. " " .. #ns.BarData("cd").spells, "Kess (Druid) - Zephras 0", "a profile of its own at its next login, empty")
    lockdown = true
    Equal(select(2, ns.CanDeleteProfile("Shared")), "Profiles can't change in combat.", "never in combat")
    lockdown = false
    character = { guid = "Player-1-0001", name = "Zriel", realm = "Zephras" }

    -- Names made for you fit the 48 characters a profile name can have, and
    -- are never cut through a letter.
    Environment()
    character = { guid = "Player-1-0001", name = "Abcdefghijkl", realm = "An Extremely Long Realm Name For Testing" }
    ns = Load({ useBars = true })
    local own = ns.ProfileName()
    Equal(own .. " " .. #own, "Abcdefghijkl (Druid) - An Extremely Long Realm N 48", "a long name cut to fit, with no space left at the end")
    local saved = ForeverEnhancedCooldownManagerDB
    character = { guid = "Player-1-0002", name = "Abcdefghijkl", realm = "An Extremely Long Realm Name For Testing" }
    Environment(true)
    ns = Load(saved)
    Equal(ns.ProfileName(), "Abcdefghijkl (Druid) - An Extremely Long Realm 2", "a numbered one fits too")
    Equal((ns.CanDeleteProfile(own)), true, "and it can be deleted")
    Environment()
    character = { guid = "Player-1-0001", name = "Zri\195\169l", realm = "R" .. string.rep("\195\169", 24) }
    ns = Load({ useBars = true })
    own = ns.ProfileName()
    Equal(tostring(#own <= ns.PROFILE_MAX) .. " " .. tostring(utf8.len(own) ~= nil), "true true", "never cut through a letter")
    -- A long name from before names were kept short can still be deleted.
    Environment()
    character = { guid = "Player-1-0001", name = "Zriel", realm = "Zephras" }
    local long = string.rep("x", 60)
    ns = Load({ useBars = true, profiles = { [long] = Lists() }, chars = { ["Player-1-0005"] = long } })
    can, name = ns.CanDeleteProfile(long)
    Equal(tostring(can) .. " " .. tostring(name == long), "true true", "a long old name can be deleted")
    Equal(tostring((ns.DeleteProfile(long))) .. " " .. tostring(ForeverEnhancedCooldownManagerDB.profiles[long]), "true nil", "and is")
    Equal(select(2, ns.CanDeleteProfile("  ")), "Type a profile name first.", "typed names are still checked")

    -- Many profiles: the list scrolls, and the name box and buttons stay
    -- under it, in reach.
    Environment()
    local profiles = {}
    for i = 1, 30 do profiles[("Profile %02d"):format(i)] = Lists() end
    ns = Load({ useBars = true, profiles = profiles, notesSeen = "dev" }) -- no What's new
    SlashCmdList.FECM("")
    w = FECMFrame
    w.profileButton:Click()
    local list = w.profileList
    local shown, inList = 0, 0
    for _, f in ipairs(frames) do
        if f.profile and S[f].shown then
            shown = shown + 1
            if S[f].parent == list.content then inList = inList + 1 end
        end
    end
    Equal(shown .. " " .. inList .. " " .. S[list.content].height, "31 31 682", "every profile listed, in a list that scrolls")
    local bottom = S[list].points[2]
    Equal(bottom[1] .. " " .. bottom[3] .. " " .. bottom[4] .. " " .. bottom[5], "BOTTOMRIGHT TOPLEFT 282 -182",
        "pinned by two corners, seven rows tall (since Positions per profile took a row)")
    Equal(S[w.profileInput].points[1][3], -186, "the name box right under those seven")
    Equal(tostring(S[w.profilePanel].height <= 420) .. " " .. tostring(Last(w.profilePanel, "SetClampedToScreen")), "true true",
        "the menu stays short and on screen")
    for _, timer in ipairs(timers) do timer() end
    Equal(S[list].points[2][5], -182, "pinned again a moment after opening")
    -- A short list is as tall as its profiles.
    Environment()
    ns = Load({ useBars = true })
    SlashCmdList.FECM("")
    w = FECMFrame
    w.profileButton:Click()
    Equal(S[w.profileList].points[2][5] .. " " .. S[w.profileInput].points[1][3], "-50 -54", "one profile: a one-row list, the box right under it")
end

-- A profile shared across classes -------------------------------------------------------------
-- Another class's spells stay in the profile but don't show; your own class's
-- spells you haven't learned yet show greyed, in their own icon.
Environment()
ns = Load({ useBars = true })
B = ns.Bars
B:Assign("Moonfire", "cd")
local shared = ns.BarData("cd").spells
table.insert(shared, 1, "Garrote") -- a rogue's, from the same profile
table.insert(shared, "Rake") -- a druid spell not learned yet
B:Changed()
Equal(table.concat((B:Mine("cd")), ",") .. " | " .. B:Get("cd").count, "Moonfire,Rake | 1",
    "only your class's spells are yours, and only learned ones go on the bar on screen")
SlashCmdList.FECM("")
w = FECMFrame
w:Select("cd")
page = w.pages.bar
Equal(page.icons[1].name .. " " .. page.icons[1].index .. " " .. page.icons[2].name .. " " .. page.icons[2].index
    .. " " .. tostring(page.icons[3] == nil or not S[page.icons[3]].shown), "Moonfire 2 Rake 3 true",
    "the tray shows yours, each knowing its place in the list")
Equal(S[page.icons[2].texture].texture .. " " .. tostring(S[page.icons[2].texture].desaturated), "1 true",
    "a spell you haven't learned: its own icon, greyed, not a question mark")
local nav = w.nav.cd
Equal(S[nav.count].text .. " " .. tostring(S[nav.icons[2]].texture) .. " " .. tostring(S[nav.icons[2]].desaturated)
    .. " " .. tostring(S[nav.icons[3]].shown), "2 1 true false", "the bar list on the left shows the same: yours only, no question marks")
Equal(S[page.count].text, "2 icons, drag to reorder", "counted as yours")
S[page.icons[2]].scripts.OnDragStart(page.icons[2])
S[page.icons[1]].mouseOver = true
S[page.icons[2]].scripts.OnDragStop(page.icons[2])
S[page.icons[1]].mouseOver = nil
Equal(table.concat(ns.BarData("cd").spells, ","), "Garrote,Rake,Moonfire", "dragged in the tray, the rogue's spell stays put")
w:Select("layout")
local tiles = w.pages.layout.rows.cd.tiles
Equal(tiles[1].name .. " " .. tostring(S[tiles[1].texture].desaturated) .. " " .. tiles[2].name,
    "Rake true Moonfire", "the Layout page draws yours, the unlearned one greyed")
B:Clear("cd")
Equal(table.concat(ns.BarData("cd").spells, ","), "Garrote", "Clear takes yours off and leaves the rogue's")
-- /fecm reset asks just as the Layout page's Reset button does; Cancel changes nothing.
w:Hide()
w:Select("cd")
SlashCmdList.FECM(" Reset ")
Equal(tostring(S[w].shown) .. " " .. w.selected .. " " .. tostring(S[w.confirm.shade].shown), "true layout true",
    "/fecm reset opens the Layout page and asks first")
Equal(S[w.confirm.dialog.title].text, "Reset your layout?", "the same question as the Reset button")
w.confirm.no:Click()
Equal(S[w.confirm.shade].shown, false, "Cancel closes it, nothing reset")
-- The Buffs bar's slots are for your own buffs.
B:SetAura("buff", "Evasion", true)
B:SetAura("buff", "Sprint", true)
ns.BUFF_SLOTS = 2
Equal(tostring(B:SetAura("buff", "Thorns", true)) .. " " .. tostring(B:SetAura("buff", "Mark of the Wild", true))
    .. " " .. tostring(B:SetAura("buff", "Clearcasting", true)), "true true false", "a rogue's buffs don't use up your slots")
ns.BUFF_SLOTS = 16
-- Added by name, another class's spell stays off your bars too; a buff added by
-- name stays, since it can land on you whoever casts it. A debuff has to be yours.
B:Add("util", "Sinister Strike")
B:Add("buff", "Blessing of Might")
B:Add("debuff", "Garrote")
Equal(#(B:Mine("util")) .. " " .. B:Get("util").count .. " | " .. tostring(ns.Spells:ForMe("Blessing of Might", "buff"))
    .. " " .. tostring(ns.Spells:ForMe("Garrote", "debuff")) .. " " .. B:Get("debuff").count, "0 0 | true false 0",
    "a rogue's spell or debuff added by name isn't yours; a paladin's buff is")
-- Racials: yours from your spellbook; another race's (an orc's Blood Fury in a
-- shared profile) stays off your bars. Items are everyone's; a spell no class
-- or race owns that isn't in your spellbook (another character's profession)
-- isn't yours.
Equal(tostring(ns.Spells:ForMe("Walk on Air", "cd")) .. " " .. tostring(ns.Spells:ForMe("Blood Fury", "cd"))
    .. " " .. tostring(ns.Spells:ForMe("Will of the Forsaken", "util")) .. " " .. tostring(ns.Spells:ForMe("Blood Fury", "buff"))
    .. " " .. tostring(ns.Spells:ForMe("item:118", "cd")) .. " " .. tostring(ns.Spells:ForMe("slot:14", "util"))
    .. " " .. tostring(ns.Spells:ForMe("family:mana", "cd")) .. " " .. tostring(ns.Spells:ForMe("Attack", "cd"))
    .. " " .. tostring(ns.Spells:ForMe("First Aid", "cd")), "true false false false true true true true false",
    "your racial is yours, another race's isn't, on any bar; items and your general spells are; another's profession isn't")
B:Add("cd", "Blood Fury")
Equal(table.concat(B:Mine("cd"), ","):find("Blood Fury", 1, true), nil, "an orc's racial in the profile doesn't show on your bar")

-- A profile shared across races ------------------------------------------------------------
-- The user's tauren hunter shares a profile with an undead warlock, whose
-- Underwater Breathing (a passive racial, so added by its ID), Cannibalize and
-- Will of the Forsaken sit next to the hunter's Serpent Sting. Each shows only
-- on the character whose race has it, and stays in the profile for the other.
do
local function Undead(book) -- the warlock's spellbook: its racials and Shoot
    table.insert(book[1].items, { name = "Cannibalize", subName = "Racial", spellID = 20577, iconID = 2 })
    table.insert(book[1].items, { name = "Will of the Forsaken", subName = "Racial", spellID = 7744, iconID = 3 })
    table.insert(book[1].items, { name = "Underwater Breathing", subName = "Racial Passive", spellID = 5227, isPassive = true })
    table.insert(book[1].items, { name = "Shoot", spellID = 5019, iconID = 4 })
end
-- Spells the game says you and your pet know, by ID; nil: the game can't say.
local known, petKnown
local function KnownSpells(ids, pets)
    known, petKnown = ids, pets or {}
    if not ids then
        C_SpellBook.IsSpellKnown = nil
        return
    end
    Enum.SpellBookSpellBank.Pet = 1
    C_SpellBook.IsSpellKnown = function(id, bank)
        assert(bank == 0 or bank == 1, "the player's or the pet's spells")
        if bank == 1 then return petKnown[id] == true end
        return known[id] == true
    end
end
local function Racials(race, class)
    _G.UnitRace = function() return race == 5 and "Undead" or "Tauren", race == 5 and "Scourge" or "Tauren", race end
    _G.UnitClass = function() return class, class end
end
local shared = { joins = { buff = {}, debuff = {} }, debuff = {}, buff = {},
    cd = { "Hunter's Mark", "Underwater Breathing", "Serpent Sting", "Cannibalize", "Will of the Forsaken", "Shoot" },
    util = { "Revive Pet" } }
local savedRaces = { useBars = true, notesSeen = "dev", profiles = { Shared = shared }, everyone = "Shared",
    custom = { ["Underwater Breathing"] = { 5227 } } }
-- The warlock first: its active racials are its own. Its passive one, added
-- by ID before passives were turned away, has nothing to track, so it shows
-- for no one, the warlock included, and stays in the profile.
Environment()
Racials(5, "WARLOCK")
Undead(book)
KnownSpells({ [5227] = true, [20577] = true, [7744] = true, [5019] = true })
ns = Load(savedRaces)
B = ns.Bars
Equal(table.concat((B:Mine("cd")), ","), "Cannibalize,Will of the Forsaken,Shoot",
    "the undead warlock's own active racials and Shoot; not its passive Underwater Breathing, nor the hunter's spells")
local onScreen = {}
for i = 1, B:Get("cd").count do onScreen[i] = B:Get("cd").icons[i].name end
Equal(table.concat(onScreen, ","), "Cannibalize,Will of the Forsaken,Shoot", "the three on its bar on screen")
Equal(tostring(ForeverEnhancedCooldownManagerDB.custom["Underwater Breathing"][1]) .. " " .. ns.BarData("cd").spells[2],
    "5227 Underwater Breathing", "the passive stays in the profile, in its place")
-- Now the tauren hunter on the same profile.
Environment()
Racials(6, "HUNTER")
KnownSpells({})
ns = Load(savedRaces)
B = ns.Bars
Equal(table.concat((B:Mine("cd")), ","), "Hunter's Mark,Serpent Sting",
    "the hunter's own spells only: no Underwater Breathing next to Serpent Sting, no Cannibalize or Will of the Forsaken")
Equal(B:Get("cd").count .. " " .. #(B:Mine("util")), "0 1", "nothing of the warlock's on the hunter's bar on screen")
Equal(table.concat(ns.BarData("cd").spells, ","), "Hunter's Mark,Underwater Breathing,Serpent Sting,Cannibalize,Will of the Forsaken,Shoot",
    "the warlock's spells stay in the profile, in their places")
Equal(ForeverEnhancedCooldownManagerDB.custom["Underwater Breathing"][1], 5227, "and its added racial stays remembered")
SlashCmdList.FECM("")
w = FECMFrame
w:Select("cd")
page = w.pages.bar
Equal(page.icons[1].name .. " " .. page.icons[2].name .. " " .. tostring(page.icons[3] == nil or not S[page.icons[3]].shown)
    .. " " .. S[w.nav.cd.count].text, "Hunter's Mark Serpent Sting true 2", "the bar's page and the list on the left show the hunter's two")
w:Select("layout")
local rowTiles = w.pages.layout.rows.cd.tiles
Equal(rowTiles[1].name .. " " .. rowTiles[2].name .. " " .. tostring(rowTiles[3].name), "Hunter's Mark Serpent Sting nil",
    "the Layout page's Cooldowns row too")
-- Swapping the hunter's two on the bar's page keeps the warlock's in their places.
Equal((B:Swap("cd", 1, 3)), true, "the hunter swaps Hunter's Mark and Serpent Sting")
Equal(table.concat(ns.BarData("cd").spells, ","), "Serpent Sting,Underwater Breathing,Hunter's Mark,Cannibalize,Will of the Forsaken,Shoot",
    "the warlock's racial keeps its place between them")
-- Moving a hidden racial to another bar isn't offered: it can't show there for the hunter.
local moved, why = B:Transfer("cd", "util", "Cannibalize")
Equal(tostring(moved) .. " " .. tostring(why), "false Cannibalize can't show on the Utility bar for you.", "another race's racial can't be moved for you")
local traded, tradeWhy = B:CanTrade("util", "Revive Pet", "cd", "Underwater Breathing")
Equal(tostring(traded) .. " " .. tostring(tradeWhy), "false Underwater Breathing is passive, so there's nothing to track.",
    "nor is a passive swapped onto another bar, which says why")
-- Another race's racial on the Buffs bar takes none of the hunter's slots.
table.insert(ns.BarData("buff").spells, "Will of the Forsaken")
B:Changed()
Equal(B:SlotsUsed("buff") .. " " .. B:Get("buff").count, "0 0", "another race's racial on the Buffs bar takes none of the hunter's slots")
-- The tauren's own racial is the hunter's, learned or not and at any rank.
Equal(tostring(ns.Spells:ForMe("War Stomp", "cd")) .. " " .. tostring(ns.Spells:ForMe("War Stomp@1", "cd")), "true true",
    "the tauren's own War Stomp is the hunter's")
-- Class spells only some races get: an undead priest's Touch of Weakness is
-- an undead priest's, not a troll priest's (whose Hex of Weakness it is), nor
-- an undead hunter's.
Racials(5, "PRIEST")
Equal(tostring(ns.Spells:ForMe("Touch of Weakness", "debuff")) .. " " .. tostring(ns.Spells:ForMe("Hex of Weakness", "debuff")),
    "true false", "an undead priest has Touch of Weakness, not a troll's Hex of Weakness")
Racials(5, "HUNTER")
Equal(tostring(ns.Spells:ForMe("Touch of Weakness", "debuff")) .. " " .. tostring(ns.Spells:ForMe("Cannibalize", "cd")),
    "false true", "an undead hunter has the undead racial, not the priest spell")
-- While the game won't say your race, another race's racial still stays off.
_G.UnitRace = function() return SECRETS.string, SECRETS.string, SECRETS.number end
Equal(tostring(ns.Spells:ForMe("Cannibalize", "cd")) .. " " .. tostring(ns.Spells:ForMe("Underwater Breathing", "cd")),
    "false false", "a hidden race keeps another race's racials off (the game says the hunter doesn't know them)")
Racials(6, "HUNTER")
-- A spell added by name or ID that no class or race owns (another
-- character's profession): yours once you know it, and while the game can't say.
ForeverEnhancedCooldownManagerDB.custom["Find Herbs"] = { 2383 }
table.insert(ns.BarData("util").spells, "Find Herbs")
B:Changed()
Equal(tostring(ns.Spells:ForMe("Find Herbs", "util")) .. " " .. #(B:Mine("util")) .. " " .. B:Get("util").count,
    "false 1 0", "the herbalist's Find Herbs isn't the hunter's")
known[2383] = true
B:Changed()
Equal(tostring(ns.Spells:ForMe("Find Herbs", "util")) .. " " .. B:Get("util").count, "true 1", "once the hunter learns it, it shows")
KnownSpells(nil)
B:Changed()
Equal(tostring(ns.Spells:ForMe("Find Herbs", "util")), "true", "while the game can't say, it shows, as before")
KnownSpells({})
-- Not in your spellbook and not added: another character's profession isn't yours.
table.insert(ns.BarData("util").spells, "Smelting")
Equal(tostring(ns.Spells:ForMe("Smelting", "util")) .. " " .. table.concat((B:Mine("util")), ","), "false Revive Pet",
    "the miner's Smelting stays in the profile, off the hunter's rows")
-- A pet's spell added by ID counts while your pet knows it.
ForeverEnhancedCooldownManagerDB.custom.Screech = { 24423 }
table.insert(ns.BarData("util").spells, "Screech")
B:Changed()
Equal(tostring(ns.Spells:ForMe("Screech", "util")), "false", "no pet with Screech: not shown")
KnownSpells({}, { [24423] = true })
B:Changed()
Equal(tostring(ns.Spells:ForMe("Screech", "util")), "true", "your pet knows it: it shows")
-- The Cooldowns page's list leaves off what's hidden for the hunter, as the
-- bar does: the warlock's Underwater Breathing isn't listed (ticked, though
-- not on the hunter's bar) or offered when searching. The pet's Screech,
-- added and known, is; Find Herbs, added and not known, isn't.
w:Select("util")
w:Select("cd")
Equal(tostring((Row("Underwater Breathing"))) .. " " .. tostring((Row("Find Herbs"))) .. " " .. tostring(Row("Screech") ~= nil)
    .. " " .. tostring(Row("Moonfire") ~= nil), "nil nil true true",
    "the hunter's Cooldowns list leaves off the warlock's racial and the herbalist's spell, as the bar does")
Search("underwater")
Equal(tostring((Row("Underwater Breathing"))) .. " " .. tostring((Other("Underwater Breathing"))), "nil nil",
    "searching neither lists it nor offers it to add again")
Search("")
-- On the Buffs bar too: the undead's added Underwater Breathing is always on,
-- with no buff of its own, so it takes no slot and leaves no greyed spot. A
-- gnome priest's Contingency Plan added by name stays: a gnome priest can
-- cast it on the hunter.
B:SetOption("buff", "showMissing", true)
ForeverEnhancedCooldownManagerDB.custom["Contingency Plan"] = { 1277462 }
table.insert(ns.BarData("buff").spells, "Underwater Breathing")
table.insert(ns.BarData("buff").spells, "Contingency Plan")
B:Changed()
Equal(tostring(ns.Spells:ForMe("Underwater Breathing", "buff")) .. " " .. tostring(ns.Spells:ForMe("Contingency Plan", "buff"))
    .. " " .. table.concat((B:Mine("buff")), ",") .. " " .. B:SlotsUsed("buff") .. " " .. B:Get("buff").count,
    "false true Contingency Plan 1 1",
    "an added always-on passive stays off the hunter's Buffs bar; a race-only buff another player casts on you stays")
w:Select("buff")
Equal(tostring((Row("Underwater Breathing"))) .. " " .. tostring(Row("Contingency Plan") ~= nil), "nil true",
    "and off the Buffs page's list")
-- On the Debuffs bar, a debuff added by ID that no class or race owns (a
-- talent's or item's effect, like Improved Shadow Bolt's Shadow Vulnerability)
-- stays, as it always did: the game never says you know it. A cooldown bar
-- still asks.
ForeverEnhancedCooldownManagerDB.custom["Shadow Vulnerability"] = { 17794 }
table.insert(ns.BarData("debuff").spells, "Shadow Vulnerability")
B:SetOption("debuff", "showMissing", true)
B:Changed()
Equal(tostring(ns.Spells:ForMe("Shadow Vulnerability", "debuff")) .. " " .. table.concat((B:Mine("debuff")), ",")
    .. " " .. B:Get("debuff").count .. " " .. tostring(ns.Spells:ForMe("Shadow Vulnerability", "cd")),
    "true Shadow Vulnerability 1 false",
    "an effect debuff added by ID shows on the Debuffs bar, though the game never says you know it")
w:Select("debuff")
Equal(Row("Shadow Vulnerability") ~= nil, true, "and is listed on the Debuffs page")
-- Back on the undead warlock: its active racial is on its Buffs bar; its
-- passive one isn't, even there, and isn't listed on its own pages.
Racials(5, "WARLOCK")
B:Changed()
Equal(tostring(ns.Spells:ForMe("Underwater Breathing", "buff")) .. " " .. table.concat((B:Mine("buff")), ","),
    "false Will of the Forsaken,Contingency Plan", "the undead's active racial is on its Buffs bar, its passive one isn't")
w:Select("cd")
Equal(tostring((Row("Underwater Breathing"))) .. " " .. tostring(Row("Moonfire") ~= nil), "nil true",
    "nor is its passive listed on its own Cooldowns page")
Racials(6, "HUNTER")
w:Hide()
end

-- Passives: nothing to track ------------------------------------------------------------------
-- A passive has nothing to track on the Cooldowns or Utility bar, and on the
-- Buffs or Debuffs bar only by an aura of its own that comes and goes
-- (Plainsrunning's speed buff, a talent's proc). Which spells are passive
-- comes from the game data (ns.PASSIVES), else from the game. One is turned
-- away however it comes (dragged from the spellbook onto a bar's page or a
-- Layout row, typed, searched for, swapped or moved), and one already saved
-- shows for no one but stays in the profile.
do
local data = {}
assert(loadfile("Ranks.lua"))("ForeverEnhancedCooldownManager", data)
local function Holds(list, value)
    for _, item in ipairs(list or {}) do if item == value then return true end end
    return false
end
local function IDs(list) return list and table.concat(list, ",") or "none" end
-- From the game data: a name shared with an active spell lists only its
-- passive IDs (the troll's Regeneration, not the mage's); a passive's buff
-- of its own has its name and icon (Plainsrunning's, a talent's proc, not an
-- NPC's Regeneration) and isn't hidden (not Hack and Slash's or Thick
-- Hide's, which share their talent's name and icon). Dual Wield
-- Specialization gives none either.
Equal(IDs(data.PASSIVES.Regeneration) .. " " .. IDs(data.RANKS.Regeneration) .. " " .. IDs(data.PASSIVE_BUFFS[20555])
    .. " " .. IDs(data.PASSIVES.Endurance) .. " " .. IDs(data.PASSIVE_BUFFS[20550]), "20555 401417 none 13742,20550 none",
    "the troll's Regeneration and the tauren's Endurance are passive with no buff; the mage's Regeneration is active")
Equal(IDs(data.PASSIVES.Plainsrunning) .. " " .. IDs(data.PASSIVE_BUFFS[1259918]) .. " " .. IDs(data.PASSIVE_BUFFS[12319])
    .. " " .. IDs(data.PASSIVE_BUFFS[16487]) .. " " .. IDs(data.PASSIVE_BUFFS[13715]) .. " " .. IDs(data.PASSIVE_BUFFS[23584])
    .. " " .. IDs(data.PASSIVE_BUFFS[13960]) .. " " .. IDs(data.PASSIVE_BUFFS[16929]),
    "1259918 1299038 12966,16257,17687 16488,437713 none none none none",
    "Plainsrunning's speed buff, Flurry's and Blood Craze's buffs; hidden auras aren't buffs")
Equal(IDs(data.PASSIVE_DEBUFFS[11180]) .. " " .. IDs(data.PASSIVE_BUFFS[11180]) .. " " .. IDs(data.PASSIVE_DEBUFFS[1259918])
    .. " " .. tostring(data.PASSIVES["Shadow Vulnerability"]), "12579 none none nil",
    "Winter's Chill gives a debuff, Plainsrunning none; Shadow Vulnerability isn't a passive")
-- A passive with a cooldown isn't listed (Reincarnation, an hour, nor the
-- resurrection it gives, 21169, which holds that cooldown): its cooldown is
-- worth tracking (the user's call). A talent's other effects stay
-- active (Master of Elements' mana, Frostbite's freeze). One that's simply
-- always on gives no aura of its own, though an NPC's or a potion's aura has
-- its name and icon (Parry, a pet's Fire Resistance). One whose description
-- names its aura gives it, whatever its icon (Inspiration's armor buff,
-- Spirit of Redemption, Vindication's debuff).
Equal(IDs(data.PASSIVES.Reincarnation) .. " " .. IDs(data.RANKS.Reincarnation) .. " " .. IDs(data.PASSIVE_BUFFS[20608])
    .. " " .. IDs(data.PASSIVE_DEBUFFS[20608]) .. " " .. IDs(data.PASSIVE_BUFFS[21169]) .. " " .. IDs(data.PASSIVE_DEBUFFS[21169])
    .. " " .. IDs(data.PASSIVE_BUFFS[3127]) .. " " .. IDs(data.PASSIVE_BUFFS[18848])
    .. " " .. IDs(data.PASSIVE_BUFFS[23992]) .. " " .. IDs(data.PASSIVE_BUFFS[24488]),
    "none 20608,21169 none none none none none none none none",
    "Reincarnation and its resurrection aren't listed; Parry and a pet's resistances give no buff")
Equal(IDs(data.PASSIVES["Master of Elements"]) .. " " .. IDs(data.PASSIVES.Frostbite) .. " " .. IDs(data.PASSIVES["Eye for an Eye"])
    .. " " .. IDs(data.PASSIVES["Magic Absorption"]), "29074 11071 9799 29441",
    "only a passive's own resurrection goes with it: a talent's other effects stay active")
Equal(IDs(data.PASSIVE_BUFFS[14892]) .. " " .. IDs(data.PASSIVE_BUFFS[20711]) .. " " .. IDs(data.PASSIVE_DEBUFFS[9452]),
    "14893 27827 67,440667", "the auras a passive's description names, whatever their icon")
-- Build 70170 renamed the warlock's Soul Harvesting to Soul Harvest, its
-- buff's name, so the buff its description names is now its own, and added
-- the druid's Shifting Power, a Cat Form spell with a cooldown.
Equal(IDs(data.PASSIVES["Soul Harvest"]) .. " " .. IDs(data.PASSIVE_BUFFS[437032]) .. " " .. tostring(data.RANKS["Soul Harvesting"])
    .. " " .. tostring(data.SPELL_CLASSES["Shifting Power"]) .. " " .. IDs(data.RANKS["Shifting Power"])
    .. " " .. IDs(data.PASSIVES["Shifting Power"]), "437032 1242853 nil DRUID 1322605 none",
    "Soul Harvest gives its mana buff; Shifting Power is a druid's active spell")
-- The game marks a totem's buff passive (and a battle standard's, a
-- campfire's), though it comes and goes on everyone near: each is its own
-- buff. Not a hidden one (Honor Among Thieves' party aura).
Equal(IDs(data.PASSIVE_BUFFS[8076]) .. " " .. IDs(data.PASSIVE_BUFFS[25362]) .. " " .. IDs(data.PASSIVE_BUFFS[5677])
    .. " " .. IDs(data.PASSIVE_BUFFS[8836]) .. " " .. IDs(data.PASSIVE_BUFFS[1283391]) .. " " .. IDs(data.PASSIVE_DEBUFFS[8076])
    .. " " .. IDs(data.PASSIVE_BUFFS[432264]), "8076 25362 5677 8836 1283391 none none",
    "totem buffs, and a campfire's, are their own buffs; a hidden aura isn't")
-- The game's names: every spell in the data and the auras its passives give,
-- the class procs, and spells the data doesn't cover (an effect, two active
-- racials it has no IDs for, and made-up spells from a later build), and
-- the totem buffs.
local named = { [17794] = "Shadow Vulnerability", [1229504] = "Faction Banner", [1260270] = "Rapid Regeneration",
    [16870] = "Clearcasting", [12536] = "Clearcasting", [16246] = "Clearcasting", [17941] = "Shadow Trance",
    [14143] = "Remorseless", [6150] = "Quick Shots", [1400001] = "Moonlit Path", [1400002] = "Starlit Path",
    [1400003] = "Sunlit Path", [1400004] = "Dawnlit Path", [8076] = "Strength of Earth", [25362] = "Strength of Earth",
    [8836] = "Grace of Air", [5677] = "Mana Spring" }
for _, list in ipairs({ data.RANKS, data.PASSIVES }) do
    for name, ids in pairs(list) do
        for _, id in ipairs(ids) do named[id] = named[id] or name end
    end
end
for _, links in ipairs({ data.PASSIVE_BUFFS, data.PASSIVE_DEBUFFS }) do
    for id, auras in pairs(links) do
        for _, aura in ipairs(auras) do named[aura] = named[aura] or named[id] end
    end
end
-- What's on the cursor, what the game is asked about passives and what it
-- says (true, false, a hidden answer, or "error").
local cursor, asks, says
local function Start(race, class, saved, general)
    Environment()
    if general then book[1].items = general end
    _G.UnitRace = function() return "Race", "Race", race end
    _G.UnitClass = function() return class, class end
    _G.C_Spell.GetSpellName = function(id) return named[id] end
    _G.GetCursorInfo = function() if cursor then return cursor[1], cursor[2], cursor[3], cursor[4] end end
    _G.ClearCursor = function() cursor = nil end
    asks, says = {}, {}
    _G.C_Spell.IsSpellPassive = function(id)
        asks[#asks + 1] = id
        if says[id] == "error" then error("no such spell") end
        return says[id]
    end
    ns = Load(saved or { useBars = true, notesSeen = "dev" })
    B = ns.Bars
    SlashCmdList.FECM("")
    w = FECMFrame
    page = w.pages.bar
end
local function Drop(target)
    S[target].scripts.OnReceiveDrag(target)
    return S[w.note].text
end
local function List(key) return table.concat(ns.BarData(key).spells, ",") end
-- Holds a Layout page tile over a row (and an icon in it), then lets go: the
-- footer while held, then after.
local function Held(tile, row, onto)
    local lp = w.pages.layout
    S[tile].scripts.OnDragStart(tile)
    S[row].mouseOver = true
    if onto then S[onto].mouseOver = true end
    S[lp.ghost].scripts.OnUpdate(lp.ghost)
    local seen = S[w.note].text
    S[tile].scripts.OnDragStop(tile)
    S[row].mouseOver = nil
    if onto then S[onto].mouseOver = nil end
    return seen .. " | " .. S[w.note].text
end

-- A tauren hunter: its Endurance is always on, its Plainsrunning gives a speed buff.
Start(6, "HUNTER")
-- Paladin auras, hunter aspects, stances, forms and Shadowmeld aren't
-- passive: kept or added, they stay as they were.
local held = {}
for _, name in ipairs({ "Devotion Aura", "Retribution Aura", "Aspect of the Hawk", "Aspect of the Cheetah", "Battle Stance",
    "Defensive Stance", "Bear Form", "Cat Form", "Travel Form", "Shadowform", "Shadowmeld", "Stealth", "Ghost Wolf" }) do
    if data.PASSIVES[name] or not data.RANKS[name] or ns.Spells:PassiveNote(name, "cd") or ns.Spells:AddNote(name, "buff") then
        held[#held + 1] = name
    end
end
Equal(table.concat(held, ","), "", "auras, aspects, stances, forms and Shadowmeld aren't passive")
w:Select("cd")
Search("20550")
Equal(tostring((Other("20550"))), "nil", "searching Endurance's ID on the Cooldowns page doesn't offer it")
Search("1259918")
Equal(tostring((Other("1259918"))), "nil", "nor Plainsrunning's")
Search("expans")
Equal(tostring((Other("Expansive Mind"))) .. " " .. tostring(Other("Blood Fury") == nil), "nil true",
    "nor a passive found by name (Expansive Mind), while an active racial (Blood Fury) still is")
Search("blood f")
Equal(Other("Blood Fury") ~= nil, true, "Blood Fury offered")
w:Select("buff")
Search("1259918")
Equal(Other("1259918") ~= nil, true, "on the Buffs page Plainsrunning is offered: it has a buff of its own")
Search("20550")
Equal(tostring((Other("20550"))), "nil", "Endurance isn't: it has none")
Search("")
w:Select("cd")
cursor = { "spell", 1, "spell", 20550 }
Equal(Drop(page.tray) .. " " .. List("cd") .. " " .. tostring(cursor ~= nil) .. " " .. tostring(ns.CustomSpells().Endurance),
    "Endurance is passive, so there's nothing to track.  true nil",
    "dragged from the spellbook onto the Cooldowns page: turned away, saying why, still on the cursor, not remembered")
w:Select("layout")
local rows = w.pages.layout.rows
Equal(Drop(rows.util) .. " " .. List("util"), "Endurance is passive, so there's nothing to track. ",
    "onto the Layout page's Utility row too")
Equal(Drop(rows.buff) .. " " .. List("buff"), "Endurance is passive, so there's nothing to track. ",
    "and the Buffs row: always on, it has no buff of its own")
cursor = { "spell", 1, "spell", 1259918 }
Equal(Drop(rows.cd) .. " " .. List("cd"), "Plainsrunning is passive. Only its buff can be tracked, on the Buffs bar. ",
    "Plainsrunning onto the Cooldowns row: turned away, saying where it goes")
Equal(Drop(rows.buff) .. " " .. List("buff") .. " " .. tostring(cursor), "Added Plainsrunning to Buffs. Plainsrunning nil",
    "onto the Buffs row it goes on")
Equal(table.concat(ns.Spells:Find("Plainsrunning").ids, ",") .. " " .. tostring(B:Get("buff").slotIDs[1][1299038])
    .. " " .. B:Get("buff").count, "1259918,1299038 true 1", "lit by its speed buff")
local ok, said = B:Add("util", "Touch of the Grave")
Equal(tostring(ok) .. " " .. said, "false Touch of the Grave is passive, so there's nothing to track.", "typed by name, turned away")
ok, said = B:Add("debuff", "1259918")
Equal(tostring(ok) .. " " .. said, "false Plainsrunning is passive. Only its buff can be tracked, on the Buffs bar.",
    "Plainsrunning has no debuff to track")
-- Swapped or moved off the Buffs row, it would show nowhere: the footer says why.
B:Assign("Moonfire", "cd")
w:Refresh()
Equal(rows.buff.tiles[1].name .. " " .. rows.cd.tiles[1].name, "Plainsrunning Moonfire", "Plainsrunning and Moonfire on the Layout page")
Equal(Held(rows.buff.tiles[1], rows.cd, rows.cd.tiles[1]), "Can't swap: Plainsrunning is passive. Only its buff can be tracked,"
    .. " on the Buffs bar. | Plainsrunning is passive. Only its buff can be tracked, on the Buffs bar.",
    "held over a Cooldowns icon, then let go: refused, saying why")
Equal(Held(rows.buff.tiles[1], rows.util), "Let go to move Plainsrunning to Utility. | Plainsrunning is passive. Only its buff"
    .. " can be tracked, on the Buffs bar.", "moved to the Utility row: refused, saying why")
Equal(List("cd") .. " | " .. List("util") .. " | " .. List("buff"), "Moonfire |  | Plainsrunning", "nothing moved")
-- Plainsrunning is a tauren's: not a troll's, sharing the profile.
_G.UnitRace = function() return "Troll", "Troll", 8 end
B:Changed()
Equal(tostring(ns.Spells:ForMe("Plainsrunning", "buff")) .. " " .. B:Get("buff").count .. " " .. List("buff"), "false 0 Plainsrunning",
    "a troll doesn't see the tauren's Plainsrunning, which stays")
w:Hide()

-- A warrior's procs and talent buffs share their passive talent's name: the
-- talent dragged onto the Buffs page tracks its buff.
Start(1, "WARRIOR")
w:Select("buff")
cursor = { "spell", 1, "spell", 12319 }
Equal(Drop(page.tray) .. " " .. List("buff") .. " " .. tostring(ns.CustomSpells().Flurry),
    "Added Flurry to Buffs. Flurry nil", "the Flurry talent onto the Buffs page puts the warrior's Flurry proc there")
Equal(ns.Spells:Find("Flurry").kind .. " " .. tostring(ns.Spells:ForMe("Flurry", "buff")), "proc true", "shown, as the proc it is")
cursor = { "spell", 1, "spell", 12317 }
Equal(Drop(page.tray) .. " " .. List("buff"), "Added Enrage to Buffs. Flurry,Enrage", "the Enrage talent too")
cursor = { "spell", 1, "spell", 16487 }
Equal(Drop(page.tray) .. " " .. List("buff"), "Added Blood Craze to Buffs. Flurry,Enrage,Blood Craze",
    "a talent's buff that isn't a listed proc (Blood Craze), by the talent's ID")
Equal(table.concat(ns.Spells:Find("Blood Craze").ids, ",") .. " " .. table.concat((B:Mine("buff")), ",") .. " " .. B:Get("buff").count,
    "16487,16488,437713 Flurry,Enrage,Blood Craze 3", "lit by its buff, all three on the Buffs bar")
w:Select("cd")
cursor = { "spell", 1, "spell", 12319 }
Equal(Drop(page.tray), "Procs only go on the Buffs bar.", "the Flurry talent onto the Cooldowns page: a proc")
cursor = { "spell", 1, "spell", 16487 }
Equal(Drop(page.tray) .. " " .. List("cd"), "Blood Craze is passive. Only its buff can be tracked, on the Buffs bar. ",
    "Blood Craze's talent onto the Cooldowns page: turned away")
w:Hide()

-- A debuff of its own: a mage's Winter's Chill talent goes on the Debuffs
-- bar, lit by the debuff. An effect debuff added by ID (Shadow Vulnerability,
-- which the data doesn't cover; the game says it isn't passive) stays.
Start(1, "MAGE")
w:Select("debuff")
cursor = { "spell", 1, "spell", 11180 }
Equal(Drop(page.tray) .. " " .. List("debuff") .. " " .. table.concat(ns.Spells:Find("Winter's Chill").ids, ","),
    "Added Winter's Chill to Debuffs. Winter's Chill 11180,12579", "the Winter's Chill talent onto the Debuffs page, lit by its debuff")
w:Select("buff")
cursor = { "spell", 1, "spell", 11180 }
Equal(Drop(page.tray) .. " " .. List("buff"), "Winter's Chill is passive. Only its debuff can be tracked, on the Debuffs bar. ",
    "not on the Buffs page")
says[17794] = false
ok = B:Add("debuff", "17794")
Equal(tostring(ok) .. " " .. table.concat((B:Mine("debuff")), ",") .. " " .. B:Get("debuff").count .. " " .. table.concat(asks, ","),
    "true Winter's Chill,Shadow Vulnerability 2 17794", "Shadow Vulnerability by ID shows on the Debuffs bar; the game was asked")
w:Hide()

-- Regeneration: a mage's active spell, and a troll's passive racial. A troll
-- warrior added its own (and a tauren's Endurance) before passives were
-- turned away: neither shows, on any bar, and both stay in the profile.
local regen = { joins = { buff = {}, debuff = {} }, cd = { "Regeneration", "Endurance" }, util = {},
    buff = { "Regeneration", "Endurance" }, debuff = {} }
local savedRegen = { useBars = true, notesSeen = "dev", profiles = { Shared = regen }, everyone = "Shared",
    custom = { Regeneration = { 20555 }, Endurance = { 20550 } } }
Start(8, "WARRIOR", savedRegen)
Equal(table.concat((B:Mine("cd")), ",") .. "|" .. table.concat((B:Mine("buff")), ",") .. "|" .. B:Get("cd").count .. "|" .. B:Get("buff").count,
    "||0|0", "the troll's passive Regeneration and the tauren's Endurance show on no bar")
Equal(List("cd") .. " " .. List("buff") .. " " .. ForeverEnhancedCooldownManagerDB.custom.Regeneration[1] .. " "
    .. ForeverEnhancedCooldownManagerDB.custom.Endurance[1], "Regeneration,Endurance Regeneration,Endurance 20555 20550",
    "and stay in the profile")
w:Select("cd")
Equal(tostring((Row("Regeneration"))) .. " " .. tostring((Row("Endurance"))), "nil nil", "nor are they listed")
w:Hide()
-- A human mage on the same profile: Regeneration is its own active spell.
Start(1, "MAGE", savedRegen, { { name = "Regeneration", spellID = 401417, iconID = 5 } })
Equal(table.concat((B:Mine("cd")), ",") .. " " .. B:Get("cd").count .. " " .. B:Get("cd").icons[1].spellID,
    "Regeneration 1 401417", "the mage's own Regeneration shows; the tauren's Endurance doesn't")
-- The troll's passive Regeneration dragged in is turned away, though the
-- mage's Regeneration is in the spellbook; the mage's own goes on.
w:Select("util")
cursor = { "spell", 1, "spell", 20555 }
Equal(Drop(page.tray) .. " " .. List("util"), "Regeneration is passive, so there's nothing to track. ",
    "the troll's Regeneration, turned away by its own ID")
cursor = { "spell", 1, "spell", 401417 }
Equal(Drop(page.tray) .. " " .. List("util"), "Added Regeneration to Utility. Regeneration", "the mage's own Regeneration goes on")
w:Hide()

-- A priest where a troll saved its passive Regeneration: the mage's
-- Regeneration (a heal over time a mage can put on you), by its ID, is
-- judged by that ID. The Buffs page's search offers it and it goes on,
-- remembered with the troll's, so it shows, lit by the mage's, and stays off
-- the priest's Cooldowns bar (a mage's spell). Already on the Buffs bar, it
-- shows at once; a full bar leaves what was remembered as it was.
do
local function SharedRegen(buff, util)
    return { useBars = true, notesSeen = "dev", everyone = "Shared", custom = { Regeneration = { 20555 } },
        profiles = { Shared = { joins = { buff = {}, debuff = {} }, cd = { "Regeneration" }, util = util or {},
            buff = buff or {}, debuff = {} } } }
end
Start(1, "PRIEST", SharedRegen())
w:Select("buff")
Search("20555")
Equal(tostring((Other("20555"))), "nil", "the troll's Regeneration isn't offered by its ID")
Search("401417")
Equal(Other("401417") ~= nil, true, "the mage's is")
Other("401417").check:Click()
Equal(S[w.note].text .. " " .. table.concat(ForeverEnhancedCooldownManagerDB.custom.Regeneration, ",") .. " "
    .. table.concat((B:Mine("buff")), ",") .. " " .. tostring((B:Get("buff").slotIDs[1] or {})[401417]) .. " "
    .. table.concat((B:Mine("cd")), ","), "Added Regeneration to Buffs. 20555,401417 Regeneration true ",
    "added, remembered with the troll's, shown and lit by the mage's; not on the priest's Cooldowns bar")
Search("")
w:Hide()
Start(1, "PRIEST", SharedRegen({ "Regeneration" }))
Equal(table.concat((B:Mine("buff")), ","), "", "the troll's alone on the Buffs bar doesn't show")
-- Held over the bar first, the footer says it goes on (it shows now), not
-- that it's there already.
ok, said = B:CanAdd("buff", "401417")
Equal(tostring(ok) .. " " .. said .. " " .. table.concat(ForeverEnhancedCooldownManagerDB.custom.Regeneration, ","),
    "true Drop to add Regeneration to Buffs. 20555", "held over the Buffs bar: it goes on, and nothing is remembered yet")
ok, said = B:Add("buff", "401417")
Equal(tostring(ok) .. " " .. said .. " " .. table.concat((B:Mine("buff")), ",") .. " " .. B:Get("buff").count,
    "true Added Regeneration to Buffs. Regeneration 1", "given the mage's ID, it shows at once")
w:Hide()
local filler = {}
for i = 1, 40 do filler[i] = "Filler " .. i end
Start(1, "PRIEST", SharedRegen(nil, filler))
ok = B:Add("util", "401417")
Equal(tostring(ok) .. " " .. table.concat(ForeverEnhancedCooldownManagerDB.custom.Regeneration, ","), "false 20555",
    "a full bar: nothing remembered")
w:Hide()
end

-- Totem buffs: the game marks them passive, but they come and go on everyone
-- near the totem. By its ID one goes on the Buffs bar, lit by itself, and
-- the game data decides (the game isn't asked). The Cooldowns bar says where
-- it goes. Saved ones show.
Start(2, "WARRIOR")
says[25362], says[8836], says[5677] = false, false, false
w:Select("buff")
Search("25362")
Equal(Other("25362") ~= nil, true, "the Buffs page's search offers Strength of Earth by its buff's ID")
w:Select("cd")
Search("25362")
Equal(tostring((Other("25362"))), "nil", "the Cooldowns page's doesn't")
Search("")
ok, said = B:Add("buff", "25362")
Equal(tostring(ok) .. " " .. said .. " " .. table.concat(ns.Spells:Find("Strength of Earth").ids, ",") .. " "
    .. tostring((B:Get("buff").slotIDs[1] or {})[25362]) .. " " .. #asks, "true Added Strength of Earth to Buffs. 25362 true 0",
    "on the Buffs bar, lit by itself")
ok, said = B:Add("cd", "8836")
Equal(tostring(ok) .. " " .. said, "false Grace of Air is passive. Only its buff can be tracked, on the Buffs bar.",
    "not on the Cooldowns bar")
w:Hide()
Start(2, "WARRIOR", { useBars = true, notesSeen = "dev", everyone = "Shared",
    custom = { ["Strength of Earth"] = { 25362 }, ["Mana Spring"] = { 5677 } },
    profiles = { Shared = { joins = { buff = {}, debuff = {} }, cd = {}, util = {},
        buff = { "Strength of Earth", "Mana Spring" }, debuff = {} } } })
says[25362], says[5677] = false, false
B:Changed()
Equal(table.concat((B:Mine("buff")), ",") .. " " .. B:Get("buff").count .. " " .. tostring((B:Get("buff").slotIDs[1] or {})[25362])
    .. " " .. tostring((B:Get("buff").slotIDs[2] or {})[5677]) .. " " .. #asks, "Strength of Earth,Mana Spring 2 true true 0",
    "saved totem buffs show")
w:Hide()

-- Reincarnation is passive, but its hour's cooldown shows whether a shaman
-- can come back, so it goes on the cooldown bars like an active spell
-- (the user's call): searched for, typed, by its ID, dragged or saved.
Start(8, "SHAMAN")
w:Select("cd")
Search("reinc")
Equal(tostring((Other("Reincarnation")) ~= nil), "true", "searching by name offers it")
Search("")
ok, said = B:Add("cd", "Reincarnation")
Equal(tostring(ok) .. " " .. tostring(List("cd"):find("Reincarnation", 1, true) ~= nil), "true true", "typed by name: on Cooldowns")
Equal(said:find("is passive", 1, true) == nil, true, "with no passive note")
w:Hide()
Start(8, "SHAMAN")
ok, said = B:Add("util", "20608")
Equal(tostring(ok) .. " " .. tostring(List("util"):find("Reincarnation", 1, true) ~= nil), "true true", "by its ID on Utility")
w:Hide()
Start(8, "SHAMAN")
w:Select("util")
cursor = { "spell", 1, "spell", 20608 }
Drop(page.tray)
Equal(tostring(List("util"):find("Reincarnation", 1, true) ~= nil) .. " " .. tostring(cursor == nil), "true true",
    "dragged from the spellbook: on the bar, off the cursor")
cursor = nil
w:Hide()
Start(8, "SHAMAN", { useBars = true, notesSeen = "dev", everyone = "Shared", custom = { Reincarnation = { 20608 } },
    profiles = { Shared = { joins = { buff = {}, debuff = {} }, cd = { "Reincarnation" }, util = {}, buff = {}, debuff = {} } } })
Equal(table.concat((B:Mine("cd")), ",") .. "|" .. B:Get("cd").count, "Reincarnation|1", "saved, it shows on the shaman's bar")
w:Hide()
Start(8, "SHAMAN", { useBars = true, notesSeen = "dev", everyone = "Shared", custom = { Reincarnation = { 21169 } },
    profiles = { Shared = { joins = { buff = {}, debuff = {} }, cd = {}, util = { "Reincarnation" }, buff = {}, debuff = {} } } })
Equal(table.concat((B:Mine("util")), ",") .. "|" .. B:Get("util").count, "Reincarnation|1", "saved by its resurrection's ID: shows too")
w:Hide()

-- Parry is simply always on: an NPC's Parry buff, with its name and icon,
-- isn't its. Turned away from the Buffs bar; saved, hidden but kept.
Start(1, "WARRIOR")
ok, said = B:Add("buff", "3127")
Equal(tostring(ok) .. " " .. said .. " " .. List("buff"), "false Parry is passive, so there's nothing to track. ",
    "Parry turned away from the Buffs bar")
w:Hide()
Start(1, "WARRIOR", { useBars = true, notesSeen = "dev", everyone = "Shared", custom = { Parry = { 3127 } },
    profiles = { Shared = { joins = { buff = {}, debuff = {} }, cd = {}, util = {}, buff = { "Parry" }, debuff = {} } } })
Equal(table.concat((B:Mine("buff")), ",") .. "|" .. B:Get("buff").count .. "|" .. List("buff"), "|0|Parry",
    "saved, it shows for no one and stays")
w:Hide()

-- Inspiration's talent names its armor buff, which has another icon: on the
-- Buffs bar it's lit by that buff.
Start(1, "PRIEST")
w:Select("buff")
cursor = { "spell", 1, "spell", 14892 }
Equal(Drop(page.tray) .. " " .. List("buff") .. " " .. table.concat(ns.Spells:Find("Inspiration").ids, ","),
    "Added Inspiration to Buffs. Inspiration 14892,14893", "the Inspiration talent onto the Buffs page, lit by its buff")
w:Select("cd")
cursor = { "spell", 1, "spell", 14892 }
Equal(Drop(page.tray) .. " " .. List("cd"), "Inspiration is passive. Only its buff can be tracked, on the Buffs bar. ",
    "not onto the Cooldowns page")
w:Hide()

-- The game data decides for what it covers, whatever the game says, and
-- the game isn't asked. A spell it doesn't cover (one from a later build):
-- the game says, once; a hidden answer, an error or no way to ask leaves
-- it as any other spell.
Start(6, "HUNTER")
says[5227], says[8921] = false, true
ok, said = B:Add("cd", "5227")
Equal(tostring(ok) .. " " .. said .. " " .. #asks, "false Underwater Breathing is passive, so there's nothing to track. 0",
    "Underwater Breathing is passive by the data, though the game says otherwise, and it isn't asked")
ok = B:Add("cd", "8921")
Equal(tostring(ok) .. " " .. List("cd") .. " " .. #asks, "true Moonfire 0", "Moonfire is active by the data, though the game says otherwise")
says[1400001], says[1400002], says[1400003] = true, SECRETS.boolean, "error"
ok, said = B:Add("util", "1400001")
Equal(tostring(ok) .. " " .. said .. " " .. table.concat(asks, ","), "false Moonlit Path is passive, so there's nothing to track. 1400001",
    "a spell the data doesn't cover, passive by the game")
B:Add("util", "1400001")
Equal(table.concat(asks, ","), "1400001", "asked once")
Equal(tostring((B:Add("util", "1400002"))) .. " " .. tostring((B:Add("util", "1400003"))), "true true",
    "a hidden answer or an error: it goes on")
_G.C_Spell.IsSpellPassive = nil
Equal(tostring((B:Add("util", "1400004"))) .. " " .. List("util"), "true Starlit Path,Sunlit Path,Dawnlit Path",
    "no way to ask: it goes on")
-- One the game called passive, saved before passives were turned away, shows for no one.
ForeverEnhancedCooldownManagerDB.custom["Moonlit Path"] = { 1400001 }
table.insert(ns.BarData("util").spells, "Moonlit Path")
B:Changed()
Equal(table.concat((B:Mine("util")), ",") .. " " .. B:Get("util").count, "Starlit Path,Sunlit Path,Dawnlit Path 3",
    "a saved spell the game called passive stays off")
-- A passive saved by its name alone, with no IDs remembered for it, is
-- judged by the game data's IDs for that name: a night elf's Quickness.
_G.UnitRace = function() return "Race", "Race", 4 end
table.insert(ns.BarData("util").spells, "Quickness")
B:Changed()
Equal(tostring(ns.Spells:Find("Quickness")) .. " " .. tostring(ns.Spells:ForMe("Quickness", "util")) .. " "
    .. table.concat((B:Mine("util")), ","), "nil false Starlit Path,Sunlit Path,Dawnlit Path",
    "a night elf's Quickness saved by name alone stays off too")
-- A name the data has active IDs for as well isn't taken for passive: a
-- hunter's Frost Resistance (the pet's teaching spell) saved by name.
table.insert(ns.BarData("util").spells, "Frost Resistance")
B:Changed()
Equal(tostring(ns.Spells:ForMe("Frost Resistance", "util")), "true", "a hunter's Frost Resistance, passive and active IDs, stays")
w:Hide()

-- Every race-limited spell in the game data, for every race and class: an
-- active one shows on the Cooldowns and Utility bars only for its race (and
-- class, where only some classes get it), and on the Debuffs bar the same; a
-- passive never does. On the Buffs bar an active racial shows for its race,
-- and a race-only class spell (one a player of that race can cast on you)
-- for anyone; a passive only with a buff of its own (Plainsrunning, for a
-- tauren). Each added as by name: its first ID in the data, or the game's ID
-- for the two active ones the data has no IDs for.
local unlisted = { ["Faction Banner"] = 1229504, ["Rapid Regeneration"] = 1260270 }
local names, first, custom, missing = {}, {}, {}, {}
for name in pairs(data.SPELL_RACES) do names[#names + 1] = name end
table.sort(names)
for _, name in ipairs(names) do
    local ids = data.RANKS[name] or data.PASSIVES[name]
    if not ids then missing[#missing + 1] = name end
    first[name] = ids and ids[1] or unlisted[name]
    custom[name] = { first[name] }
end
Equal(table.concat(missing, ","), "Faction Banner,Rapid Regeneration", "the only two the data has no IDs for")
local passives, buffed = {}, {}
for _, name in ipairs(names) do
    if Holds(data.PASSIVES[name], first[name]) then
        passives[#passives + 1] = name
        if data.PASSIVE_BUFFS[first[name]] then buffed[#buffed + 1] = name end
    end
end
Equal(table.concat(passives, ","), "Axe Specialization,Beast Slaying,Big Game Hunter,Elemental Insight,"
    .. "Engineering Specialization,Expansive Mind,Galestrider Riding,Gnomish,Hardiness,Horse Riding,Kodo Riding,"
    .. "Mace Specialization,Mechanostrider Piloting,Plainsrunning,Quickness,Quickness Passive,Ram Riding,Raptor Riding,"
    .. "Sword Specialization,The Human Spirit,Tiger Riding,Touch of the Grave,Undead Horsemanship,Underwater Breathing,"
    .. "Wind Blessed,Wisp Spirit,Wolf Riding", "the race-limited passives in the game data")
Equal(table.concat(buffed, ","), "Plainsrunning", "of which only Plainsrunning gives a buff of its own")
-- A bar holds 40, so the first 40 go on Cooldowns and Buffs, the rest on
-- Utility and the last 40 on Debuffs: each is on a bar, so each is an entry.
local profile = { joins = { buff = {}, debuff = {} }, cd = {}, util = {}, buff = {}, debuff = {} }
for i, name in ipairs(names) do
    table.insert(i <= 40 and profile.cd or profile.util, name)
    if i <= 40 then table.insert(profile.buff, name) end
    if i > #names - 40 then table.insert(profile.debuff, name) end
end
Start(6, "HUNTER", { useBars = true, notesSeen = "dev", profiles = { Shared = profile }, everyone = "Shared", custom = custom },
    { { name = "Attack", spellID = 6603 } })
for _, id in pairs(unlisted) do says[id] = false end
local everyone = {}
for _, list in pairs(data.SPELL_RACES) do
    for race in list:gmatch("%d+") do everyone[tonumber(race)] = true end
end
local races = {}
for race in pairs(everyone) do races[#races + 1] = race end
table.sort(races)
Equal(everyone[1] and everyone[2] and everyone[3] and everyone[4] and everyone[5] and everyone[6] and everyone[7]
    and everyone[8] and everyone[95] and everyone[96], true, "every Forever race among them")
local CLASSES = { "WARRIOR", "PALADIN", "HUNTER", "ROGUE", "PRIEST", "SHAMAN", "MAGE", "WARLOCK", "DRUID" }
local function In(list, value) return list ~= nil and (" " .. list .. " "):find(" " .. value .. " ", 1, true) ~= nil end
local function Expected(name, race, class)
    local id, classes = first[name], data.SPELL_CLASSES[name]
    local passive = Holds(data.PASSIVES[name], id)
    local yours = In(data.SPELL_RACES[name], race) and (classes == nil or In(classes, class))
    return {
        cd = not passive and yours,
        util = not passive and yours,
        buff = (not passive or data.PASSIVE_BUFFS[id] ~= nil) and (classes ~= nil or In(data.SPELL_RACES[name], race)),
        debuff = (not passive or data.PASSIVE_DEBUFFS[id] ~= nil) and yours,
    }
end
local BARS = { "cd", "util", "buff", "debuff" }
for _, name in ipairs(names) do
    local wrong = {}
    for _, race in ipairs(races) do
        _G.UnitRace = function() return "Race", "Race", race end
        for _, class in ipairs(CLASSES) do
            _G.UnitClass = function() return class, class end
            local want = Expected(name, race, class)
            for _, bar in ipairs(BARS) do
                local got = ns.Spells:ForMe(name, bar)
                if got ~= want[bar] then wrong[#wrong + 1] = race .. " " .. class .. " " .. bar .. " " .. tostring(got) end
            end
        end
    end
    Equal(table.concat(wrong, "; "), "", name .. ", for every race and class")
end
Equal(#ns.BarData("cd").spells + #ns.BarData("util").spells .. " " .. #ns.BarData("buff").spells .. " "
    .. #ns.BarData("debuff").spells, #names .. " 40 40", "every one on a bar")
-- On screen, for a few: the bars show just what's theirs.
for _, who in ipairs({ { 6, "HUNTER" }, { 5, "WARLOCK" }, { 7, "PRIEST" }, { 8, "MAGE" }, { 96, "DRUID" } }) do
    _G.UnitRace = function() return "Race", "Race", who[1] end
    _G.UnitClass = function() return who[2], who[2] end
    B:Changed()
    for _, bar in ipairs(BARS) do
        local want = {}
        for _, name in ipairs(ns.BarData(bar).spells) do
            if Expected(name, who[1], who[2])[bar] then want[#want + 1] = name end
        end
        Equal(table.concat((B:Mine(bar)), ",") .. " " .. B:Get(bar).count,
            table.concat(want, ",") .. " " .. math.min(#want, ns.AURA_BARS[bar] and ns.BUFF_SLOTS or #want),
            "a race " .. who[1] .. " " .. who[2] .. "'s " .. bar .. " bar")
    end
end
_G.UnitRace = function() return "Race", "Race", 6 end
_G.UnitClass = function() return "HUNTER", "HUNTER" end
Equal(tostring(Holds((B:Mine("buff")), "Plainsrunning")) .. " " .. tostring(Holds((B:Mine("cd")), "Plainsrunning")), "true false",
    "the tauren hunter's Plainsrunning is on its Buffs bar only")
w:Hide()
end

-- What's new -------------------------------------------------------------------------------

-- A first install has nothing new: the welcome shows instead, and the
-- version is noted as it does (Tools/TestLifecycle.lua reloads before then).
Environment()
ns = Load(nil)
Equal(tostring(ns.NotesSeen()), "nil", "a first install notes nothing before the welcome shows")
for _, timer in ipairs(timers) do timer() end
Equal(FECMNotes == nil or not S[FECMNotes].shown, true, "without showing What's new")
Equal(ns.NotesSeen(), "dev", "the version noted as the welcome shows")

-- After an update it shows once, a moment after login, never in combat.
Environment()
ns = Load({ useBars = true })
Equal(tostring(ns.NotesSeen()), "nil", "an update notes the new version only as What's new shows")
Equal(FECMNotes, nil, "and waits a moment to show What's new")
lockdown = true
for _, timer in ipairs(timers) do timer() end
Equal(FECMNotes == nil and tostring(ns.NotesSeen()), "nil", "not in combat, and not noted yet")
lockdown = false
Fire("PLAYER_REGEN_ENABLED")
local notes = FECMNotes
Equal(notes ~= nil and S[notes].shown and ns.NotesSeen(), "dev", "but once the fight is over, noted as it shows")
Equal(EscapeListed("FECMNotes"), 1, "Escape closes it: it's on the game's own list")
Equal(S[notes.version].text, "Version " .. ns.NOTES[1].version, "headed with the newest notes' version")
Equal(S[notes.close.label].text, "X", "under the window's title bar")
-- Every heading and bullet, top to bottom, none overlapping.
local texts, expected = {}, 0
for _, row in ipairs(notes.flow) do
    if row.text then texts[#texts + 1] = row end
end
-- A copy from the source shows the newest release's notes and the two before
-- it (Notes.lua HISTORY = 3), newest first.
for index, entry in ipairs(ns.NOTES) do
    if index > 3 then break end
    if index > 1 then expected = expected + 1 end -- an older release's version line
    for _, section in ipairs(entry.sections) do expected = expected + 1 + #section[2] end
end
Equal(#texts, expected, "every heading and bullet listed")
Equal(S[texts[1].text].text, ns.NOTES[1].sections[1][1]:upper(), "headings in capitals")
local above
for _, row in ipairs(texts) do
    local y = -S[row.text].points[1][3]
    if above then
        Equal(y >= -S[above.text].points[1][3] + above.text:GetStringHeight(), true, "no row overlaps the one above")
    end
    if row.dot then
        local dot = -S[row.dot].points[1][3]
        Equal(dot > y and dot < y + 12, true, "each bullet's square sits beside its first line")
    end
    above = row
end
Equal(S[notes.scroll.content].height > 200, true, "the notes take their full height")
UIParent:SetHeight(800)
Fire("DISPLAY_SIZE_CHANGED")
-- Tall enough for every note, or stopped at its 620 limit (short notes fit below it).
Equal(S[notes].height <= 620 and (S[notes].height == 620 or S[notes].height > S[notes.scroll.content].height), true,
    "the window grows to fit, up to its limit")
UIParent:SetHeight(300)
Fire("UI_SCALE_CHANGED")
Equal(S[notes].height, 260, "and stays on a small screen, the notes scrolling")
S[notes].last.StopMovingOrSizing = nil
CloseSpecialWindows()
Equal(S[notes].shown, false, "Escape closes What's new")
Equal(S[notes].last.StopMovingOrSizing ~= nil, true, "stopping it moving, if it was dragged")
Equal(#bindings, 0, "no key binding changed")

-- Once per version.
local saved = ForeverEnhancedCooldownManagerDB
Environment(true)
ns = Load(saved)
for _, timer in ipairs(timers) do timer() end
Equal(FECMNotes == notes and not S[notes].shown, true, "shown once per version")

-- Any time: /ccm new, or What's new in the window.
SlashCmdList.FECM("new")
notes = FECMNotes
Equal(S[notes].shown, true, "/ccm new shows it again")
notes.done:Click()
Equal(S[notes].shown, false, "Got it closes it")
SlashCmdList.FECM("")
w = FECMFrame
Equal(S[w.news.label].text, "What's new", "What's new at the foot of the window's list")
w.news:Click()
Equal(S[notes].shown and S[w].shown, true, "opens it over the window")
CloseSpecialWindows()
Equal(tostring(S[notes].shown) .. " " .. tostring(S[w].shown), "false false", "Escape closes What's new and the window at once")
Equal(EscapeListed("FECMNotes") .. " " .. EscapeListed("FECMFrame"), "1 1", "each listed once, however often they open")

-- A released version: its own notes, then the ones before it.
_G.C_AddOns = { GetAddOnMetadata = function(_, field) assert(field == "Version"); return "@project-version@" end }
Equal(ns.Version(), "dev", "a copy straight from the source is dev")
_G.C_AddOns.GetAddOnMetadata = function() return "1.1.0" end
Environment()
ns = Load({ useBars = true, notesSeen = "1.0.0" })
Equal(ns.Version(), "1.1.0", "a release has its version from the TOC")
ns.NOTES = {
    { version = "1.2.0", sections = { { "Added", { "Later." } } } },
    { version = "1.1.0", sections = { { "Added", { "This one." } }, { "Fixed", { "A bug." } } } },
    { version = "1.0.0", sections = { { "Added", { "The first." } } } },
}
for _, timer in ipairs(timers) do timer() end
notes = FECMNotes
Equal(S[notes].shown and S[notes.version].text, "Version 1.1.0", "an update to it shows its own notes")
local rows = {}
for _, row in ipairs(notes.flow) do rows[#rows + 1] = row.rule and "--" or S[row.text].text end
Equal(table.concat(rows, "|"), "ADDED|This one.|FIXED|A bug.|--|Version 1.0.0|ADDED|The first.",
    "then the release before, under a line")
Equal(S[notes.hint].text, "See it again in the settings.", "the way back to it: the settings, not a typed command")
SlashCmdList.FECM("")
local footerVersion
for _, f in ipairs(objects) do
    if S[f].text == "v1.1.0   Options > AddOns or /ccm to open" then footerVersion = f end
end
Equal(footerVersion ~= nil, true, "the window's footer shows the version too")
_G.C_AddOns = nil

-- Rows and which way a bar grows ---------------------------------------------------------

local function At(frame)
    local p = S[frame].points[1]
    return string.format("%s %g %g", p[1], p[4], p[5])
end
Environment()
ns = Load({ useBars = true })
B = ns.Bars
local rowBar = B:Get("cd")
for _, name in ipairs({ "Moonfire", "Wrath", "Overpower", "Attack", "Thorns" }) do B:Assign(name, "cd") end
Equal(ns.BarData("cd").perRow .. " " .. At(rowBar.icons[5]), "20 TOPLEFT 160 0", "one row until told otherwise")
B:SetOption("cd", "perRow", 2)
Equal(At(rowBar.icons[1]) .. "|" .. At(rowBar.icons[2]) .. "|" .. At(rowBar.icons[5]),
    "TOPLEFT 0 0|TOPLEFT 40 0|TOPLEFT 20 -80", "two across: rows of two, the last one centred")
Equal(string.format("%gx%g", S[rowBar].width, S[rowBar].height), "76x116", "the bar fits its rows")
B:SetOption("cd", "grow", "left")
Equal(At(rowBar.icons[1]) .. "|" .. At(rowBar.icons[2]) .. "|" .. At(rowBar.icons[5]),
    "TOPLEFT 40 0|TOPLEFT 0 0|TOPLEFT 40 -80", "growing left: the first icon on the right")
B:SetOption("cd", "grow", "right")
Equal(At(rowBar.icons[5]), "TOPLEFT 0 -80", "growing right: rows start on the left")
Equal(At(rowBar), "BOTTOMLEFT -38 190", "above the action bar, it grows right from where it was")
B:SetOption("cd", "wrap", "up")
Equal(At(rowBar.icons[1]) .. "|" .. At(rowBar.icons[3]), "BOTTOMLEFT 0 0|BOTTOMLEFT 0 40", "new rows above")
B:SetOption("cd", "showNames", true)
Equal(At(rowBar.icons[3]), "BOTTOMLEFT 0 54", "with room for names between rows")
B:SetOption("cd", "showNames", false)
-- Positions saved before rows were from the centre: the bar doesn't shift.
local cdData = ns.BarData("cd")
cdData.perRow, cdData.grow, cdData.wrap = 20, "centre", "down"
cdData.x, cdData.y, cdData.point = 10, 20, nil
B:Rebuild()
Equal(At(rowBar) .. " " .. cdData.point, "TOP 10 38 TOP", "an old position kept by the top edge instead")
B:SetOption("cd", "grow", "left")
Equal(At(rowBar), "TOPRIGHT 108 38", "and by the right edge when it grows left, still in the same place")
B:SetOption("cd", "grow", "centre")
Equal(At(rowBar), "TOP 10 38", "and back")

-- The Buffs bar: fixed spots in rows, packed icons from the bar's edge.
for _, name in ipairs({ "Thorns", "Clearcasting", "Nature's Grace" }) do B:SetAura("buff", name, true) end
local buffRows = B:Get("buff")
B:SetOption("buff", "showMissing", true)
B:SetOption("buff", "perRow", 2)
Equal(At(buffRows.holders[3]), "TOPLEFT 20 -40", "fixed buff spots go in rows too")
B:SetOption("buff", "showMissing", false)
B:SetOption("buff", "grow", "left")
Equal(S[buffRows.container].points[1][1], "RIGHT", "packed buffs line up from the edge the bar grows away from")
Equal(S[buffRows.container].groups.g1.layout.layoutIndex, ns.BUFF_SLOTS, "the first one on the right")
Equal(string.format("%gx%g", S[buffRows].width, S[buffRows].height), "116x36", "in one row: the game lays those out")

-- Kept over a reload with everything else.
cdData.perRow, cdData.grow, cdData.wrap = 3, "right", "up"
saved = ForeverEnhancedCooldownManagerDB
Environment(true)
ns = Load(saved)
cdData = ns.BarData("cd")
Equal(cdData.perRow .. " " .. cdData.grow .. " " .. cdData.wrap .. " " .. tostring(cdData.point), "3 right up BOTTOMLEFT",
    "rows and grow kept over a reload, the position held by the edge it grows from")

-- Layouts around the Personal Resource Display --------------------------------------------

function Proto:GetRect()
    local r = S[self].rect
    if r then return r[1], r[2], r[3], r[4] end
end
local prd
local function Display()
    prd = Blizzard(New("Frame"), "PersonalResourceDisplayFrame")
    S[prd].rect = { 400, 300, 200, 20 } -- its middle 90 below the middle of the screen
    rawset(prd, "HealthBarsContainer", New("Frame", prd))
    S[prd.HealthBarsContainer].rect = { 400, 305, 200, 15 }
    rawset(prd, "PowerBar", New("StatusBar", prd))
    S[prd.PowerBar].rect = { 400, 300, 200, 5 }
    rawset(prd, "AlternatePowerBar", false)
    rawset(prd, "ClassFrameContainer", false)
    rawset(prd, "defaultBarWidth", 200)
    rawset(prd, "barWidthPercent", 100)
    -- Blizzard's own Bar Width setting.
    rawset(prd, "UpdateBarWidth", function(self)
        local width = self.defaultBarWidth * self.barWidthPercent / 100
        for _, part in ipairs({ self, self.HealthBarsContainer, self.PowerBar }) do part:SetWidth(width) end
    end)
    -- Blizzard's: the addon only reads its keys, never writes one.
    getmetatable(prd).__newindex = function(_, key) error("wrote key " .. tostring(key) .. " on Blizzard's display", 2) end
    _G.PersonalResourceDisplayFrame = prd
end
Environment()
_G.hooksecurefunc = function(t, key, hook)
    local original = t[key]
    rawset(t, key, function(...)
        if original then original(...) end
        hook(...)
    end)
end
Display()
ns = Load({ useBars = true, prdSkin = false })
B = ns.Bars
local L = ns.Layout
Equal(L:Active(), false, "no layout until one is picked")
for _, name in ipairs({ "Moonfire", "Wrath", "Overpower" }) do B:Assign(name, "cd") end
B:Assign("Attack", "util")
local ok, message = L:Apply("pyramid")
Equal(ok and message, "Pyramid is set up. Tick spells for each bar, then size them to taste.", "a preset in one click")
local cd, util = ns.BarData("cd"), ns.BarData("util")
Equal(cd.perRow .. " " .. cd.size .. " " .. util.perRow .. " " .. util.size .. " " .. cd.spacing, "6 36 5 36 0",
    "each bar's icons across, its own icon size kept, and the icons flush")
Equal(At(B:Get("cd")), "BOTTOM 0 -80", "Cooldowns right on top of the display")
Equal(At(B:Get("util")), "TOP 0 -100", "Utility right under it")
Equal(At(B:Get("buff")) .. " " .. At(B:Get("debuff")), "TOP 0 -136 TOP 0 -136", "empty bars take no room")
Equal(string.format("%g %g", S[prd].width, S[prd.PowerBar].width), "216 216", "the display as wide as the widest row")
-- The rows touch unless you give them room.
L:SetGap(6)
Equal(At(B:Get("cd")) .. " " .. At(B:Get("util")) .. " " .. ns.LayoutData().gap, "BOTTOM 0 -74 TOP 0 -106 6",
    "room between the rows and the display when asked for")
L:SetGap(99)
Equal(ns.LayoutData().gap, 20, "up to 20")
L:SetGap(0)
Equal(At(B:Get("cd")), "BOTTOM 0 -80", "and touching again")
B:SetUnlocked(true)
Equal(At(B:Get("debuff")), "TOP 0 -172", "unlocked, empty bars show, so they get room")
B:SetUnlocked(false)
-- More spells than fit across: the row wraps, and the rows below move down.
B:Assign("Thorns", "util")
B:SetOption("util", "perRow", 1)
Equal(string.format("%g", S[B:Get("util")].height), "72", "Utility wraps onto a second row")
B:SetAura("buff", "Thorns", true)
Equal(At(B:Get("buff")), "TOP 0 -172", "the bar under it moves down")

-- Blizzard setting its own width puts the match back.
prd:UpdateBarWidth()
Equal(S[prd].width, 216, "the match comes back after Blizzard's Bar Width")
-- The display moved in Edit Mode: the bars follow once it closes.
S[prd].rect, S[prd.HealthBarsContainer].rect, S[prd.PowerBar].rect = { 400, 200, 200, 20 }, { 400, 205, 200, 15 }, { 400, 200, 200, 5 }
EditModeManagerFrame:Show()
EditModeManagerFrame:Hide()
Equal(At(B:Get("cd")), "BOTTOM 0 -180", "the bars follow the display")
-- Hidden until combat, the game can't say where it is: where it was last seen.
S[prd].rect, S[prd.HealthBarsContainer].rect, S[prd.PowerBar].rect = nil, nil, nil
L:Stack()
Equal(At(B:Get("cd")), "BOTTOM 0 -180", "a hidden display: where it was last seen")
-- As it shows, the bars are stacked around it again.
S[prd].rect, S[prd.HealthBarsContainer].rect, S[prd.PowerBar].rect = { 400, 250, 200, 20 }, { 400, 255, 200, 15 }, { 400, 250, 200, 5 }
prd:Hide()
prd:Show()
Equal(At(B:Get("cd")), "BOTTOM 0 -130", "stacked again as it shows")
S[prd].rect, S[prd.HealthBarsContainer].rect, S[prd.PowerBar].rect = { 400, 200, 200, 20 }, { 400, 205, 200, 15 }, { 400, 200, 200, 5 }
L:Stack()
-- Edit Mode's Hide Health Bar hides the container, not the health bar in
-- it: the rows then sit flush on the power bar.
do
    local health = New("StatusBar", prd.HealthBarsContainer)
    S[health].rect = { 400, 205, 200, 15 }
    rawset(prd.HealthBarsContainer, "healthBar", health)
    L:Stack()
    Equal(At(B:Get("cd")) .. " " .. At(B:Get("util")), "BOTTOM 0 -180 TOP 0 -200", "the health bar counts while it shows")
    prd.HealthBarsContainer:Hide()
    L:Stack()
    Equal(At(B:Get("cd")) .. " " .. At(B:Get("util")), "BOTTOM 0 -195 TOP 0 -200", "Hide Health Bar: flush on the power bar")
    prd.HealthBarsContainer:Show()
    rawset(prd.HealthBarsContainer, "healthBar", nil)
    L:Stack()
    Equal(At(B:Get("cd")), "BOTTOM 0 -180", "and on the health bar again once it shows")
end

-- Undo puts back what the preset changed.
ok, message = L:Undo()
Equal(message .. " " .. ns.BarData("cd").perRow .. " " .. tostring(L:Active()), "Put back as it was. 20 false", "Undo")
Equal(S[prd].width, 200, "and the display gets Blizzard's width back")
Equal(L.undo, nil, "once")
Equal(tostring(ns.LayoutData().preset), "nil", "from no layout, no preset is left marked")
-- Undo back to your own layout: no preset marked, and icon sizes you set
-- after picking one stay, since a layout never changes them.
L:Apply("pyramid")
L:SetAcross("cd", 7)
L:Apply("wide")
B:SetOption("cd", "size", 48)
L:Undo()
Equal(tostring(ns.LayoutData().preset) .. " " .. ns.BarData("cd").size .. " " .. ns.BarData("cd").perRow, "nil 48 7",
    "Undo puts your own layout back, keeping the size you set")
B:SetOption("cd", "size", 36)

-- Dragging a bar leaves the layout; Line up stacks them again.
L:Apply("pyramid")
B:SetUnlocked(true)
S[B:Get("util")].cx, S[B:Get("util")].cy = 300, 300
S[B:Get("util").mover].scripts.OnDragStart()
S[B:Get("util").mover].scripts.OnDragStop()
Equal(tostring(L:Active()) .. " " .. tostring(L.moved), "false true", "a bar dragged by hand leaves the layout")
Equal(S[prd].width, 200, "the display's own width again")
B:SetUnlocked(false)
ok, message = L:LineUp()
Equal(tostring(L:Active()) .. " " .. message, "true Your bars are stacked again.", "lined up again")
Equal(At(B:Get("util")), "TOP 0 -200", "back under the display")

-- Changing rows: how many fit across, swapping bars, and moving the display.
L:SetAcross("cd", 7)
Equal(ns.BarData("cd").perRow .. " " .. tostring(ns.LayoutData().preset), "7 nil", "one more across, as your own layout")
Equal(S[prd].width, 7 * 36, "the display follows the widest row")
Equal(L:CanSwap("cd", -1), false, "the top row can't go higher")
L:Swap("util", -1)
local layout = ns.LayoutData()
Equal(table.concat(layout.above, ",") .. "|" .. table.concat(layout.below, ","), "util|cd,buff,debuff",
    "Utility swapped into the top row, Cooldowns into its place")
cd, util = ns.BarData("cd"), ns.BarData("util")
Equal(util.perRow .. " " .. util.size .. " " .. cd.perRow .. " " .. cd.size, "7 36 5 36", "the rows keep how many fit across; each bar keeps its size")
Equal(util.wrap .. " " .. At(B:Get("util")), "up BOTTOM 0 -180", "Utility sits on the display, growing up")
L:Swap("util", 1)
Equal(table.concat(layout.above, ",") .. " " .. ns.BarData("cd").perRow, "cd 7", "and back")
Equal(tostring(L:CanMoveDisplay(-1)) .. " " .. tostring(L:CanMoveDisplay(1)), "true true", "the display can move either way")
L:MoveDisplay(1)
Equal(table.concat(layout.above, ",") .. "|" .. table.concat(layout.below, ","), "cd,util|buff,debuff",
    "moving the display down puts the row under it above it")
Equal(At(B:Get("util")) .. " " .. At(B:Get("cd")), "BOTTOM 0 -180 BOTTOM 0 -144", "flush on top of it, the row above making room")
L:MoveDisplay(-1)
Equal(table.concat(layout.below, ","), "util,buff,debuff", "and back up")

-- Beside the display.
L:Apply("sides")
Equal(At(B:Get("buff")) .. " " .. ns.BarData("buff").grow, "TOPRIGHT -100 -172 left", "Buffs left of the display, growing left")
Equal(At(B:Get("debuff")) .. " " .. ns.BarData("debuff").grow, "TOPLEFT 100 -172 right", "Debuffs right of it, growing right")
Equal(table.concat(L:Rows(), ","), "cd,buff,debuff,util", "in order, the ones beside the display in the middle")
L:Swap("buff", -1)
Equal(ns.LayoutData().left .. " " .. ns.LayoutData().above[1] .. " " .. ns.BarData("buff").perRow, "cd buff 8",
    "a bar beside the display swaps with the row above, taking its shape")

-- Match off: Blizzard's width.
ns.Set("prdMatch", false)
L:Stack()
Equal(S[prd].width, 200, "matching off gives Blizzard's width back")
ns.Set("prdMatch", true)
L:Stack()

-- Never in combat.
lockdown = true
ok, message = L:Apply("wide")
Equal(tostring(ok) .. " " .. message, "false Finish combat first.", "presets wait for the fight to end")
Equal(select(2, L:SetAcross("cd", 3)), "Finish combat first.", "so do row changes")
L:Stack()
Equal(B:Get("buff").pendingLayout, true, "the Buffs bar moves after the fight")
lockdown = false
Fire("PLAYER_REGEN_ENABLED")
Equal(L.pending, nil, "and it's stacked again then")

-- Reset positions ends the layout; it's kept over a reload.
L:Apply("funnel")
Equal(table.concat(ns.LayoutData().above, ","), "debuff,buff,util,cd", "everything above the display")
saved = ForeverEnhancedCooldownManagerDB
Environment(true)
Display()
ns = Load(saved)
Equal(tostring(ns.LayoutData().on) .. " " .. ns.LayoutData().preset .. " " .. table.concat(ns.LayoutData().above, ","),
    "true funnel debuff,buff,util,cd", "the layout kept over a reload")
ns.Bars:ResetPositions()
Equal(ns.Layout:Active(), false, "Reset positions ends the layout")

-- The Layout page ----------------------------------------------------------------------------

Environment()
Display()
ns = Load({ useBars = true, prdSkin = false })
B, L = ns.Bars, ns.Layout
for _, name in ipairs({ "Moonfire", "Wrath", "Overpower" }) do B:Assign(name, "cd") end
SlashCmdList.FECM("")
w = FECMFrame
Equal(w.nav.layout ~= nil, true, "Layout in the window's list")
w:Select("layout")
local lp = w.pages.layout
Equal(S[lp].shown and #lp.cards, 7, "seven layouts to pick from")
Equal(S[lp.status].text, "Pick a layout to stack your bars around the display.", "says what it's for")
lp.cards[2]:Click()
Equal(ns.BarData("cd").perRow .. " " .. S[w.note].text, "12 Wide is set up. Tick spells for each bar, then size them to taste.",
    "clicking one sets it up")
Equal(S[lp.cards[2]].border[1], .69, "outlined in the accent while it's in use")
Equal(S[lp.status].text, "Your bars follow your resource display.", "and says the bars follow the display")
local row = lp.rows.cd
local tiles = 0
for _, tile in ipairs(row.tiles) do if S[tile].shown then tiles = tiles + 1 end end
Equal(tiles, 12, "a tile for every icon across")
Equal(S[row.tiles[1].texture].texture ~= nil and S[row.tiles[4].texture].texture == nil, true, "your icons first, then empty spots")
Equal(S[row.across].text, "12 across", "and how many")
Equal(S[row.buttons].shown, false, "buttons out of the way")
S[row].mouseOver = true
S[row].scripts.OnEnter(row)
Equal(S[row.buttons].shown and S[w.note].text:find("the arrows swap rows", 1, true) ~= nil, true, "hovering a row shows its buttons")
row.wider:Click()
Equal(ns.BarData("cd").perRow, 13, "+ fits one more across")
row.fewer:Click()
row.fewer:Click()
Equal(ns.BarData("cd").perRow .. " " .. S[lp.rows.cd.across].text, "11 11 across", "- one fewer")
Equal(S[lp.cards[2]].border[1] == .88, false, "changed, it's your own layout")
S[row].mouseOver = nil
lp.rows.util.up:Click()
Equal(ns.LayoutData().above[#ns.LayoutData().above], "util", "an arrow swaps a row with the one above")
Equal(S[lp.rows.util].points[1][5] > S[lp.display].points[1][5], true, "drawn above it")
-- The display's own arrows move it up or down the stack.
Equal(S[lp.display.buttons].shown, false, "the display's arrows out of the way")
S[lp.display].mouseOver = true
S[lp.display].scripts.OnEnter(lp.display)
Equal(S[lp.display.buttons].shown and S[w.note].text:find("move it up or down the stack", 1, true) ~= nil, true,
    "hovering the display shows its arrows")
S[lp.display].mouseOver = nil
lp.display.down:Click()
Equal(table.concat(ns.LayoutData().above, ",") .. "|" .. table.concat(ns.LayoutData().below, ","), "util,cd|buff,debuff",
    "moved down past a row")
Equal(S[lp.rows.cd].points[1][5] > S[lp.display].points[1][5], true, "drawn that way too")
-- Icons dragged to another row move there; dragged off, they come off.
local first = lp.rows.cd.tiles[1]
local moving = first.name
S[first].scripts.OnDragStart(first)
S[lp.rows.util].mouseOver = true
S[first].scripts.OnDragStop(first)
S[lp.rows.util].mouseOver = nil
Equal(ns.BarData("util").spells[#ns.BarData("util").spells] .. " " .. S[w.note].text, moving .. " Moved " .. moving .. " to Utility.",
    "an icon dragged onto another row moves to that bar")
local last = lp.rows.util.tiles[#ns.BarData("util").spells]
S[last].scripts.OnDragStart(last)
S[last].scripts.OnDragStop(last)
Equal(tostring((B:Find(moving))) .. " " .. S[w.note].text, "nil Took " .. moving .. " off Utility.", "dragged off, it comes off")
lp.undo:Click()
Equal(ns.BarData("cd").perRow, 20, "Undo")
-- Escape mid-drag closes the window: the spell stays where it was, and no
-- icon is left on the cursor for next time.
do
    local tile = lp.rows.cd.tiles[1]
    local name = tile.name
    S[tile].scripts.OnDragStart(tile)
    Equal(S[lp.ghost].shown, true, "a picked-up icon follows the cursor")
    w:Hide()
    S[tile].scripts.OnDragStop(tile)
    Equal(tostring(B:Find(name) ~= nil) .. " " .. tostring(S[lp.ghost].shown), "true false", "closed mid-drag, the spell stays on its bar")
    w:Show()
    w:Select("layout")
    S[tile].scripts.OnDragStart(tile)
    lp:Hide()
    Equal(S[lp.ghost].shown, false, "the page closing lets go of what was held")
    lp:Show()
    w:Select("layout")
    -- A drag that never landed can't be dropped by a later one.
    S[tile].scripts.OnDragStart(tile)
    local spare = lp.rows.cd.tiles[6]
    Equal(spare.name, nil, "an empty spot")
    S[spare].scripts.OnDragStart(spare)
    S[spare].scripts.OnDragStop(spare)
    Equal(tostring(B:Find(name) ~= nil) .. " " .. tostring(S[lp.ghost].shown), "true false", "nothing taken off by a drag from an empty spot")
end
lp.cards[1]:Click()
Equal(S[lp.toggle.label].text, "Turn off", "a way to stop")
lp.toggle:Click()
Equal(tostring(L:Active()) .. " " .. S[lp.status].text, "false Your bars stay where you put them.", "stopped")
lp.toggle:Click()
Equal(L:Active(), true, "and Line up starts again")
-- Reset positions, now on this page: back above the action bar, out of the layout.
lp.home:Click()
Equal(tostring(L:Active()) .. " " .. tostring(ns.BarData("cd").point) .. " " .. S[w.note].text .. " " .. S[lp.toggle.label].text,
    "false nil Bars moved back above your action bar. Line up stacks them again. Line up", "Reset positions")
lp.toggle:Click()
Equal(L:Active(), true, "and Line up stacks them again")
lp.match:Click()
Equal(tostring(ns.Get("prdMatch")) .. string.format(" %g", S[prd].width), "false 200", "the match can be turned off")
lp.match:Click()
Equal(S[prd].width, 6 * 36, "and on")
-- Room between the icons in every row, flush unless you ask.
Equal(S[lp.iconSpacing.value].text, 0, "icons flush to start with")
lp.iconSpacing:Choose(3)
Equal(ns.BarData("cd").spacing .. " " .. ns.BarData("debuff").spacing .. " " .. ns.LayoutData().spacing, "3 3 3",
    "Icon spacing gives every row the same room")
lp.iconSpacing:Choose(0)
-- The row buttons are drawn in the accent, so they stand out.
Equal(S[lp.rows.cd.up.art].tint[1] .. " " .. S[lp.rows.cd.fewer.label].colour[1], "0.69 0.69", "arrows, - and + in the accent")
-- Picked up, an icon's spot shows empty until it lands.
local held = lp.rows.cd.tiles[1]
local before = table.concat(ns.BarData("cd").spells, ",")
S[held].scripts.OnDragStart(held)
Equal(Last(held.texture, "SetColorTexture"), ns.Theme.CONTROL_BORDER[1], "its spot empty while it's held")
S[lp.rows.cd].mouseOver = true
S[held].scripts.OnDragStop(held)
S[lp.rows.cd].mouseOver = nil
Equal(table.concat(ns.BarData("cd").spells, ","), before, "dropped back on its own row, nothing changes")
-- The display switched off and on from here, or your bars off.
Equal(tostring(lp.shown:GetChecked()) .. " " .. tostring(ns.NeedsReload()), "true false", "the display shown, no reload needed yet")
lp.shown:Click()
Equal(tostring(prdOn) .. " " .. S[lp.status].text, "false Your rows close up where the display would be.",
    "unticked, Blizzard's display goes off and the rows close up")
Equal(At(B:Get("cd")) .. " " .. At(B:Get("util")), "BOTTOM 0 -90 TOP 0 -90", "where it was")
Equal(tostring(ns.NeedsReload()) .. " " .. S[w.note].text,
    "true Your Personal Resource Display is off. Reload to finish (Look page, or /reload).",
    "a reload asked for to finish, pointing at the Look page's Reload button")
lp.shown:Click()
Equal(tostring(prdOn) .. " " .. At(B:Get("util")), "true TOP 0 -100", "and back on")
Equal(S[w.note].text, "Your Personal Resource Display is on. Reload to finish (Look page, or /reload).", "a reload asked for again")
-- Switched off in Blizzard's Options instead: the rows close up too.
prdOn = false
Fire("CVAR_UPDATE", "nameplateShowSelf", "0")
Equal(At(B:Get("cd")) .. " " .. At(B:Get("util")), "BOTTOM 0 -90 TOP 0 -90", "switched off in Options, the rows close up")
prdOn = true
Fire("CVAR_UPDATE", "nameplateShowSelf", "1")
Equal(At(B:Get("util")), "TOP 0 -100", "and part again when it's back")
prdOn = false
Fire("CVAR_UPDATE", "cooldownViewerEnabled", "1")
Equal(At(B:Get("util")), "TOP 0 -100", "other game settings don't restack")
prd:Hide()
Equal(At(B:Get("util")), "TOP 0 -90", "the display hiding closes them up too")
prdOn = true
prd:Show()
Equal(At(B:Get("util")), "TOP 0 -100", "and showing again parts them")
-- Edit Mode's Visibility set to Hidden: no room for it either, with the
-- Options switch still on. In Combat and Always keep its space.
do
    Enum.PersonalResourceDisplayVisibleSetting = { Always = 0, InCombat = 1, Hidden = 2 }
    rawset(prd, "visibleSetting", 2)
    prd:Hide()
    w:Refresh()
    local display = L:Display()
    Equal(tostring(display.off) .. " " .. display.height .. " " .. At(B:Get("util")) .. " " .. S[lp.display].alpha .. " "
        .. S[lp.status].text, "true 0 TOP 0 -90 0.3 Your rows close up where the display would be.",
        "Hidden in Edit Mode: it takes no room, the rows close up, and the page says so")
    Equal(rawget(prd, "visibleSetting"), 2, "its Visibility read, never changed")
    rawset(prd, "visibleSetting", 1)
    L:Stack()
    Equal(tostring(L:Display().off) .. " " .. At(B:Get("util")), "nil TOP 0 -100", "In Combat: hidden out of a fight, its space kept")
    Equal(rawget(prd, "visibleSetting"), 1, "In Combat read, never changed")
    -- A setting the game hides: never compared (comparing one errors in the
    -- game, as it does here), its space kept.
    local Secret = { __eq = function() error("compared a secret value") end }
    local hidden, secret = setmetatable({}, Secret), setmetatable({}, Secret)
    _G.issecretvalue = function(value) return rawequal(value, secret) or IsSecret(value) end
    Enum.PersonalResourceDisplayVisibleSetting.Hidden = hidden
    rawset(prd, "visibleSetting", secret)
    L:Stack()
    Equal(At(B:Get("util")) .. " " .. #printed, "TOP 0 -100 0", "a setting the game hides: never compared, its space kept, no errors")
    Equal(rawequal(rawget(prd, "visibleSetting"), secret), true, "a hidden setting left as it was")
    _G.issecretvalue = IsSecret
    Enum.PersonalResourceDisplayVisibleSetting.Hidden = 2
    rawset(prd, "visibleSetting", 0)
    prd:Show()
    w:Refresh()
    Equal(At(B:Get("util")) .. " " .. S[lp.display].alpha .. " " .. S[lp.status].text,
        "TOP 0 -100 1 Your bars follow your resource display.", "Always: as before")
    Equal(rawget(prd, "visibleSetting"), 0, "Always read, never changed")
    rawset(prd, "visibleSetting", nil)
    Enum.PersonalResourceDisplayVisibleSetting = nil
end
lockdown = true
lp.shown:Click()
Equal(tostring(prdOn) .. " " .. S[w.note].text, "true Finish combat first.", "never in combat")
lockdown = false
w:Refresh()
ns.Set("useBars", false)
w:Refresh()
Equal(S[lp.status].text .. " " .. tostring(S[lp.toggle].shown), "Your bars are off. false", "and your bars")
lp.turnOn:Click()
Equal(B:Enabled(), true, "turned on from here")
Equal(lp.drawError, nil, "the page drew without errors")

-- A bar's page: icons per row, and which way it grows.
w:Select("cd")
local bp = w.pages.bar
Equal(bp.across.current, 6, "Icons per row on the bar's page")
bp.across:Choose(4)
Equal(ns.BarData("cd").perRow, 4, "set there too")
bp.options.grow.buttons[2]:Click()
Equal(ns.BarData("cd").grow .. " " .. S[w.note].text, "centre Your layout sets this. Change it on the Layout page.",
    "a layout decides which way its bars grow")
L:TurnOff()
w:Refresh()
bp.options.grow.buttons[2]:Click()
Equal(ns.BarData("cd").grow, "left", "otherwise it's yours to pick")
bp.options.wrap.buttons[2]:Click()
Equal(ns.BarData("cd").wrap, "up", "and where new rows go")
w:Select("buff")
Equal(S[bp.across].shown or S[bp.options.wrap].shown, false, "packed buffs stay on one row")
bp.options.showMissing:Click()
Equal(S[bp.across].shown and S[bp.options.wrap].shown, true, "fixed spots can have rows")
Equal(bp.listError, nil, "the bar page drew without errors")

-- Items you carry none of: off your bars, which close up -----------------------------------

;(function()
    Environment()
    Display()
    local worn = {}
    _G.C_Item.IsEquippedItem = function(id) return worn[id] == true end
    -- A profile shared with a character who had potions: this one carries none.
    ns = Load({ useBars = true, prdSkin = false })
    B, L = ns.Bars, ns.Layout
    for _, name in ipairs({ "Moonfire", "family:healing", "item:118", "Wrath" }) do B:Assign(name, "cd") end
    B:Assign("family:mana", "util")
    B:SetAura("buff", "Thorns", true)
    local cdBar, utilBar = B:Get("cd"), B:Get("util")
    local function Names(bar)
        local out = {}
        for i = 1, bar.count do out[i] = bar.icons[i].name end
        return table.concat(out, ",")
    end
    local data = ns.BarData("cd")
    Equal(Names(cdBar) .. " | " .. utilBar.count .. " " .. tostring(S[utilBar].shown), "Moonfire,Wrath | 0 false",
        "potions you carry none of are left off: Cooldowns closes up, and Utility, with only Mana Potions, hides")
    Equal(S[cdBar].width, 2 * ns.IconSize(data) + data.spacing, "two icons wide")
    Equal(table.concat(data.spells, ",") .. " " .. B:Find("family:healing") .. " " .. B:Find("item:118"),
        "Moonfire,family:healing,item:118,Wrath cd cd", "still on the bar, for the characters that carry them")
    -- Stacked round the display: the empty Utility row takes no room, and the
    -- display keeps the width of your widest row as set up.
    L:Apply("pyramid")
    Equal(At(B:Get("buff")) .. " " .. string.format("%g", S[prd].width), "TOP 0 -100 216",
        "Buffs moves up under the display; its width, and the cast bar's, stay as set up")
    -- The window still shows them, ticked, to be placed.
    ns.Toggle()
    local w = FECMFrame
    w:Select("cd")
    w.pages.bar.showItems:Click()
    Equal(tostring(ListRow("family:healing").check:GetChecked()) .. " " .. tostring(ListRow("item:118").check:GetChecked()),
        "true true", "ticked in the Items list")
    -- Going to put on one you carry none of, the note says why it won't show yet.
    local function Note(name)
        local row = ListRow(name)
        S[row.check].scripts.OnEnter(row.check)
        local text = S[w.note].text
        S[row.check].scripts.OnLeave(row.check)
        return text
    end
    local NONE = " You carry none, so it shows once you do."
    local STONES = "Put Healthstones on Cooldowns. One icon for the best one you carry, switching as your bags change."
    Equal(Note("family:healthstone"), STONES .. NONE, "a family you carry none of: the tick's note says it shows once you carry one")
    local open = _G.C_Item.GetItemCount
    _G.C_Item.GetItemCount = function() return SECRETS.number end
    Equal(Note("family:healthstone") .. " " .. #printed, STONES .. " 0", "counts hidden: no guess, no errors")
    _G.C_Item.GetItemCount = open
    w:Select("util")
    Equal(Note("family:healing") .. " | " .. Note("item:118"), "Move Healing Potions here from Cooldowns. One icon for the best one you carry,"
        .. " switching as your bags change." .. NONE .. " | Move " .. ListRow("item:118").label .. " here from Cooldowns." .. NONE,
        "and moving one, or an item, to another bar")
    w:Select("cd")
    -- Dragged in or added by name: told the same.
    local _, dragged = B:AddItem("util", 5512)
    B:TakeOff("util", "family:healthstone")
    local _, typed = B:Add("util", "Healthstones")
    B:TakeOff("util", "family:healthstone")
    Equal(dragged .. " | " .. typed, "Added Healthstones to Utility. It shows the best one you carry." .. NONE
        .. " | Added Healthstones to Utility." .. NONE, "dragged in or typed, while you carry none: told it shows once you carry one")
    Equal(utilBar.count .. " " .. tostring(ns.BarData("util").spells[2]), "0 nil", "taken off again")
    w:Select("layout")
    local tiles = w.pages.layout.rows.cd.tiles
    Equal(tiles[2].name .. " " .. tiles[3].name, "family:healing item:118", "drawn on the Layout page in their places")
    ns.Toggle()
    -- Unlocked or in Edit Mode, they show (greyed, none carried) to be placed.
    B:SetUnlocked(true)
    Equal(Names(cdBar) .. " " .. S[cdBar.icons[2].count].text .. " " .. tostring(S[cdBar.icons[2].texture].desaturated) .. " "
        .. At(B:Get("buff")), "Moonfire,family:healing,item:118,Wrath 0 true TOP 0 -136",
        "unlocked: back in place, greyed at 0, and the rows make room for them")
    B:SetUnlocked(false)
    Equal(Names(cdBar) .. " " .. At(B:Get("buff")), "Moonfire,Wrath TOP 0 -100", "locked: off again")
    -- Edit Mode opened while locked: shown to be placed, and the rows make room.
    EditModeManagerFrame:Show()
    Equal(Names(cdBar) .. " " .. At(B:Get("buff")), "Moonfire,family:healing,item:118,Wrath TOP 0 -136",
        "Edit Mode: back in place to be arranged, and the rows make room")
    EditModeManagerFrame:Hide()
    Equal(Names(cdBar) .. " " .. At(B:Get("buff")), "Moonfire,Wrath TOP 0 -100", "Edit Mode closed: off again")
    -- Carrying one again: back as your bags change, in its place.
    itemCount[118] = 2
    Fire("BAG_UPDATE_DELAYED")
    Equal(Names(cdBar), "Moonfire,family:healing,item:118,Wrath", "a potion in your bags: both back, in their places")
    Equal(cdBar.icons[2].itemID .. " " .. S[cdBar.icons[2].count].text .. " " .. tostring(S[cdBar.icons[2].texture].desaturated),
        "118 2 false", "the family on the one you carry, in colour, with its count")
    -- A Mana Potion picked up: Utility comes back and the rows below make room.
    local function Util()
        return utilBar.count .. " " .. tostring(S[utilBar].shown) .. " " .. At(B:Get("buff"))
    end
    itemCount[2455] = 1
    Fire("BAG_UPDATE_DELAYED")
    Equal(Util(), "1 true TOP 0 -136", "a Mana Potion picked up: Utility back, and the rows make room for it")
    -- Used up in a fight: Utility stays till it's over, then goes, and the rows close up.
    Fire("PLAYER_REGEN_DISABLED")
    lockdown = true
    itemCount[2455] = 0
    Fire("BAG_UPDATE_DELAYED")
    Equal(Util(), "1 true TOP 0 -136", "used up in a fight: nothing moves")
    lockdown = false
    Fire("PLAYER_REGEN_ENABLED")
    Equal(Util(), "0 false TOP 0 -100", "after the fight: Utility goes, and the rows close up")
    -- Picked up in a fight: on once it's over, with its count, and the rows make room.
    Fire("PLAYER_REGEN_DISABLED")
    lockdown = true
    itemCount[2455] = 3
    Fire("BAG_UPDATE_DELAYED")
    Equal(Util(), "0 false TOP 0 -100", "picked up in a fight: waits for it to end")
    lockdown = false
    Fire("PLAYER_REGEN_ENABLED")
    Equal(Util() .. " " .. S[utilBar.icons[1].count].text .. " " .. tostring(S[utilBar.icons[1].texture].desaturated),
        "1 true TOP 0 -136 3 false", "after the fight: on, in colour with its count, and the rows make room")
    itemCount[2455] = 0
    Fire("BAG_UPDATE_DELAYED")
    Equal(Util(), "0 false TOP 0 -100", "used up out of a fight: off at once")
    -- Counts hidden while you carry them: kept on, not taken off.
    local open = _G.C_Item.GetItemCount
    _G.C_Item.GetItemCount = function() return SECRETS.number end
    Fire("BAG_UPDATE_DELAYED")
    Equal(Names(cdBar) .. " " .. #printed, "Moonfire,family:healing,item:118,Wrath 0", "hidden counts while carried: kept on")
    _G.C_Item.GetItemCount = open
    -- Used up in a fight: nothing jumps about; it stays, greyed at 0, until it's over.
    Fire("PLAYER_REGEN_DISABLED")
    lockdown = true
    itemCount[118] = 0
    Fire("BAG_UPDATE_DELAYED")
    local potion = cdBar.icons[3]
    Equal(Names(cdBar) .. " " .. S[potion.count].text .. " " .. tostring(S[potion.texture].desaturated),
        "Moonfire,family:healing,item:118,Wrath 0 true", "used up in a fight: stays put, greyed at 0")
    lockdown = false
    Fire("PLAYER_REGEN_ENABLED")
    Equal(Names(cdBar), "Moonfire,Wrath", "off once the fight is over")
    Equal(tostring(S[cdBar.icons[2].texture].desaturated), "false",
        "Wrath, moved into the greyed potion's place, is drawn again, not left greyed")
    -- Counts the game won't give keep what was known.
    local count = _G.C_Item.GetItemCount
    _G.C_Item.GetItemCount = function() return SECRETS.number end
    itemCount[118] = 1
    Fire("BAG_UPDATE_DELAYED")
    Equal(Names(cdBar) .. " " .. #printed, "Moonfire,Wrath 0", "hidden counts: kept as they were, no errors")
    _G.C_Item.GetItemCount = count
    itemCount[118] = 0
    -- An item with a use that you wear still counts.
    B:Assign("item:4000", "util")
    Equal(Names(utilBar), "", "an item you carry none of and don't wear: off")
    local _, moved = B:AddItem("cd", 4000)
    B:AddItem("util", 4000)
    Equal(moved .. " " .. B:Find("item:4000"), "Added " .. ns.Spells:Find("item:4000").name .. " to Cooldowns." .. NONE .. " util",
        "dragged to another bar: told it shows once you carry one")
    -- Whether it's worn, hidden by the game: kept off as it was, no errors.
    local isWorn = _G.C_Item.IsEquippedItem
    _G.C_Item.IsEquippedItem = function() return SECRETS.boolean end
    GearChanged()
    Equal(Names(utilBar) .. " " .. #printed, " 0", "whether it's worn hidden: kept off as it was, no errors")
    _G.C_Item.IsEquippedItem = isWorn
    worn[4000] = true
    GearChanged()
    Equal(Names(utilBar), "item:4000", "an item you wear counts as carried")
    -- Ammo on the shared bar: a class that never uses it (this druid, or a
    -- warlock) doesn't show it; a hunter out of ammo sees it greyed at 0.
    B:Assign("ammo", "util")
    Equal(Names(utilBar) .. " " .. B:Find("ammo"), "item:4000 util", "ammo: off a druid's bar, kept in the profile")
    _G.UnitClass = function() return "Hunter", "HUNTER" end
    B:Rebuild()
    Equal(Names(utilBar) .. " " .. S[utilBar.icons[2].count].text .. " " .. tostring(S[utilBar.icons[2].texture].desaturated),
        "item:4000,ammo 0 true", "a hunter's: stays, greyed at 0, when out")
    _G.UnitClass = function() return "Druid", "DRUID" end
    -- Keys only go on the icons you see.
    B:ShowKeys()
    Equal(#printed, 0, "no errors")
end)()

-- Dragging in from any spellbook, an action bar or your bags -------------------------------

Environment()
Display()
trinket = 11111
bagItems = { { itemID = 118, hyperlink = "|cffffffff|Hitem:118|h[Minor Healing Potion]|h|r", iconFileID = 888 } }
itemCount[118] = 1 -- the potion in your bags, dragged out below
local cursor
_G.GetCursorInfo = function()
    if cursor then return cursor[1], cursor[2], cursor[3], cursor[4] end
end
_G.ClearCursor = function() cursor = nil end
local spellNames = { [5176] = "Wrath", [467] = "Thorns", [8921] = "Moonfire", [1243] = "Power Word: Fortitude",
    [16870] = "Clearcasting", [16886] = "Nature's Grace" }
_G.C_Spell.GetSpellName = function(id) return spellNames[id] end
ns = Load({ useBars = true, prdSkin = false })
B, L = ns.Bars, ns.Layout
SlashCmdList.FECM("")
w = FECMFrame
w:Select("layout")
lp = w.pages.layout
Equal(S[lp.dragHint].text, "Drag spells or items onto a row. Hover a row to change it.",
    "the Layout page says spells can be dragged in")
cursor = { "spell", 12, "spell", 5176 }
S[lp.rows.util].scripts.OnReceiveDrag(lp.rows.util)
Equal(table.concat(ns.BarData("util").spells, ",") .. " " .. S[w.note].text, "Wrath Added Wrath to Utility.",
    "a spell dropped on a row joins that bar")
Equal(cursor, nil, "and is let go of")
cursor = { "spell", 3, "spell", 467 }
lp.rows.buff:Click()
Equal(table.concat(ns.BarData("buff").spells, ","), "Thorns", "clicking a row while holding a spell works too")
cursor = { "spell", 1, "spell", 1243 }
S[lp.rows.buff].scripts.OnReceiveDrag(lp.rows.buff)
Equal(table.concat(ns.BarData("buff").spells, ",") .. " " .. tostring(ns.CustomSpells()["Power Word: Fortitude"] ~= nil),
    "Thorns,Power Word: Fortitude true", "a spell from outside your spellbook, like another class's buff")
cursor = { "item", 118 }
S[lp.rows.cd].scripts.OnReceiveDrag(lp.rows.cd)
Equal(ns.BarData("cd").spells[1] .. " " .. S[w.note].text,
    "family:healing Added Healing Potions to Cooldowns. It shows the best one you carry.",
    "a healing potion from your bags: one icon for whichever rank you carry")
cursor = { "item", 11111 }
S[lp.rows.cd].scripts.OnReceiveDrag(lp.rows.cd)
Equal(ns.BarData("cd").spells[2], "slot:13", "an equipped trinket follows its slot")
do
    -- A class that never uses ammo (this druid) is told so, and keeps it on the cursor.
    cursor = { "item", 2516, "|Hitem:2516|h[Light Shot]|h" }
    S[lp.rows.util].scripts.OnReceiveDrag(lp.rows.util)
    Equal(table.concat(ns.BarData("util").spells, ",") .. " " .. tostring(cursor and cursor[2]) .. " " .. S[w.note].text,
        "Wrath 2516 Your class doesn't use ammo.", "ammo dragged in by a class that never uses it: turned away, still on the cursor")
    -- Ammunition of any kind, equipped or not, is a hunter's ammo: the one
    -- entry that counts whatever ammo you have equipped.
    _G.UnitClass = function() return "Hunter", "HUNTER" end
    S[lp.rows.util].scripts.OnReceiveDrag(lp.rows.util)
    Equal(table.concat(ns.BarData("util").spells, ",") .. " " .. tostring(cursor) .. " " .. S[w.note].text,
        "Wrath,ammo nil Added your ammo to Utility. It counts whatever ammo you have equipped.",
        "ammo from your bags with none equipped: your ammo joins the bar, and is let go of")
    local shot = B:Get("util").icons[2]
    Equal(shot.kind .. " " .. shot.slot .. " " .. tostring(S[shot].shown) .. " " .. S[shot.count].text, "ammo 0 true 0",
        "drawn as your ammo, showing none equipped")
    ammo, ammoCount = 2512, 200
    cursor = { "item", 2516 }
    S[lp.rows.cd].scripts.OnReceiveDrag(lp.rows.cd)
    local arrows = B:Get("cd").icons[3]
    Equal(table.concat(ns.BarData("cd").spells, ",") .. " | " .. table.concat(ns.BarData("util").spells, ",") .. " | "
        .. arrows.kind .. " " .. S[arrows.count].text, "family:healing,slot:13,ammo | Wrath | ammo 200",
        "another kind than the Rough Arrows equipped: still your ammo, moved to Cooldowns, counting the arrows")
    cursor = { "item", 2512 }
    S[lp.rows.cd.tiles[1]].scripts.OnReceiveDrag(lp.rows.cd.tiles[1])
    Equal(table.concat(ns.BarData("cd").spells, ",") .. " " .. tostring(cursor), "family:healing,slot:13,ammo nil",
        "the equipped arrows, from your character panel onto an icon: already there, never twice")
    cursor = { "item", 2512 }
    S[lp.rows.buff].scripts.OnReceiveDrag(lp.rows.buff)
    Equal(S[w.note].text .. " " .. tostring(cursor and cursor[2]) .. " " .. #ns.BarData("buff").spells,
        "Items can't go on the Buffs bar. 2512 2", "ammo on the Buffs bar: turned away, and still on the cursor")
    cursor = { "item", 117 }
    S[lp.rows.util].scripts.OnReceiveDrag(lp.rows.util)
    Equal(S[w.note].text .. " " .. tostring(cursor and cursor[2]) .. " " .. table.concat(ns.BarData("util").spells, ","),
        "That item has no cooldown to show. 117 Wrath", "food: turned away, still on the cursor, the bar as it was")
    -- Anything the game won't say is turned away, never guessed at.
    local instant = _G.C_Item.GetItemInfoInstant
    _G.C_Item.GetItemInfoInstant = function(id)
        if id == 3030 then return id, nil, nil, SECRETS.string, nil, 6, 2 end -- Razor Arrow, where it's worn kept secret
        if id == 3033 then return id, nil, nil, "INVTYPE_AMMO", nil, SECRETS.number, SECRETS.number end -- Solid Shot, its class secret
        if id == 3034 then return id, nil, nil, SECRETS.string, nil, SECRETS.number, SECRETS.number end
        return instant(id)
    end
    local Spells = ns.Spells
    Equal(table.concat({ tostring(Spells:IsAmmo(3030)), tostring(Spells:IsAmmo(3033)), tostring(Spells:IsAmmo(3034)),
        tostring(Spells:IsAmmo(SECRETS.number)), tostring(Spells:IsAmmo(118)), tostring(Spells:IsAmmo(nil)) }, " "),
        "true true false false false false", "ammo by its class or where it's worn; nothing secret or unknown counts")
    _G.C_Item.GetItemInfoInstant = instant
    for _, held in ipairs({ { "item", SECRETS.number }, { SECRETS.string, 118 }, { "spell", 1, "spell", SECRETS.number } }) do
        cursor = held
        S[lp.rows.cd].scripts.OnReceiveDrag(lp.rows.cd)
        Equal(S[w.note].text .. " " .. tostring(cursor == held) .. " " .. #ns.BarData("cd").spells,
            "Only spells and items can go on a bar. true 3", "a secret on the cursor: turned away and left there")
    end
    Equal(#printed, 0, "no errors from secrets on the cursor")
    _G.UnitClass = function() return "Druid", "DRUID" end
end
cursor = nil
B:TakeOff("cd", "ammo")
ammo, ammoCount = nil, 0
cursor = { "item", 118 }
S[lp.rows.buff].scripts.OnReceiveDrag(lp.rows.buff)
Equal(S[w.note].text .. " " .. tostring(cursor and cursor[2]), "Items can't go on the Buffs bar. 118",
    "no items on the Buffs bar: it stays on the cursor")
lp.rows.buff:Click()
Equal(tostring(cursor and cursor[2]) .. " " .. #ns.BarData("buff").spells, "118 2", "a click tries it again, with the same answer")
cursor = { "macro", 4 }
S[lp.rows.util].scripts.OnReceiveDrag(lp.rows.util)
Equal(S[w.note].text .. " " .. tostring(cursor and cursor[1]), "Only spells and items can go on a bar. macro",
    "anything else is turned away, left on the cursor")
cursor = nil -- put away
lp.rows.util:Click()
Equal(S[lp.rows.util.buttons].shown, true, "with nothing held, a click just keeps the row's buttons up")
-- A bar's icons, and the bars on screen while unlocked, take drops too.
w:Select("util")
cursor = { "spell", 9, "spell", 8921 }
S[w.pages.bar.tray].scripts.OnReceiveDrag(w.pages.bar.tray)
Equal(ns.BarData("util").spells[2], "Moonfire", "dropped on a bar's icons")
B:SetUnlocked(true)
cursor = { "spell", 12, "spell", 5176 }
S[B:Get("cd").mover].scripts.OnReceiveDrag(B:Get("cd").mover)
Equal(ns.BarData("cd").spells[3] .. " " .. #ns.BarData("util").spells, "Wrath 1", "dropped on a bar on screen, it moves there")
S[B:Get("cd").mover].scripts.OnMouseUp(B:Get("cd").mover)
Equal(#ns.BarData("cd").spells, 3, "a click with nothing held adds nothing")
Equal(lp.drawError, nil, "the Layout page drew without errors")

-- Countdown numbers in the game's own font: a heavy outline on big numbers, no shadow.
Equal(Last(FECMFont18, "SetFont", 1) .. " " .. Last(FECMFont18, "SetFont", 3) .. " " .. Last(FECMFont13, "SetFont", 3),
    "Fonts\\FRIZQT__.TTF THICKOUTLINE OUTLINE", "Friz Quadrata, thick outline from 16 up")
Equal(Last(FECMFont18, "SetShadowOffset", 1), 0, "no drop shadow")

-- Font and bar texture, picked on the Look page -------------------------------------------

-- In a function of its own: the main chunk is near Lua's limit of 200 locals.
;(function()
    -- No resource display: its bars are TestSkin's, and each load would hook
    -- them again. Put back at the end.
    local display = _G.PersonalResourceDisplayFrame
    _G.PersonalResourceDisplayFrame = nil
    local FRIZ, ARIAL, SKURRI = "Fonts\\FRIZQT__.TTF", "Fonts\\ARIALN.TTF", "Fonts\\skurri.ttf"
    local FLAT, CLASSIC = "Interface\\Buttons\\WHITE8X8", "Interface\\TargetingFrame\\UI-StatusBar"
    local RAID = "Interface\\RaidFrame\\Raid-Bar-Hp-Fill"
    local function Fresh(saved)
        Environment(saved ~= nil)
        _G.GameFontHighlightSmall = New("Font") -- the game's small text: "font", 12, "" (Proto:GetFont)
        _G.FECMFrame, _G.FECMTour, _G.FECMNotes = nil, nil, nil
        ns = Load(saved or { useBars = true, notesSeen = "dev" })
        for _, timer in ipairs(timers) do timer() end
    end
    Fresh()
    local B = ns.Bars
    B:Assign("Moonfire", "cd")
    SlashCmdList.FECM("")
    local w = FECMFrame
    w:Select("look")
    local font, fills = w.fontChoice, w.fills
    local cdBar, buffBar, castBar = B:Get("cd"), B:Get("buff"), ns.CastBar.row.bar

    -- Four of the game's own fonts, each name in its own face; Friz Quadrata
    -- and flat, as before, until you pick another.
    local labels = {}
    for i, button in ipairs(font.buttons) do labels[i] = S[button.label].text .. ":" .. Last(button.label, "SetFontObject") end
    Equal(table.concat(labels, " "), "Friz:FECMSamplefriz Arial:FECMSamplearial Morpheus:FECMSamplemorpheus Skurri:FECMSampleskurri",
        "four of the game's fonts, each name in its own face")
    Equal(Last(FECMSamplearial, "SetFont", 1) .. " " .. Last(FECMSamplemorpheus, "SetFont", 1) .. " " .. Last(FECMSampleskurri, "SetFont", 1),
        ARIAL .. " Fonts\\MORPHEUS.ttf " .. SKURRI, "from the game's own files")
    Equal(font.selected .. " " .. ns.Get("font") .. " " .. Last(FECMFont18, "SetFont", 1) .. " " .. S[cdBar.icons[1].label].template .. " "
        .. S[buffBar.holders[1].label].template, "friz friz " .. FRIZ .. " GameFontHighlightSmall GameFontHighlightSmall",
        "Friz Quadrata by default, the names in the game's own small text as before")
    local keys = {}
    for i, swatch in ipairs(fills) do keys[i] = swatch.key .. ":" .. S[swatch.fill].texture end
    Equal(table.concat(keys, " "), "flat:" .. FLAT .. " classic:" .. CLASSIC .. " raid:" .. RAID
        .. " skills:Interface\\PaperDollInfoFrame\\UI-Character-Skills-Bar", "four of the game's bar textures, flat first")
    Equal(S[w.fillChosen].text .. " " .. S[fills[1]].border[1] .. " " .. tostring(S[fills[2]].border[1] < 1), "Flat 1 true",
        "Flat by default, its swatch outlined")
    Equal(table.concat(S[fills[3].fill].tint, ","), "1,0.5,0.25", "each a short bar in the colour for all bars")
    Equal(Last(w.preview.Bar, "SetStatusBarTexture") .. " " .. Last(castBar, "SetStatusBarTexture"), FLAT .. " " .. FLAT,
        "the preview and your cast bar flat, as before")

    -- In the right-hand column under the keybinds, level with Shadow and the
    -- first tick, inside the Look page's choices.
    local function Rect(region) -- left, top, right, bottom within the choices
        local p = S[region].points[1]
        return p[2], p[3], p[2] + S[region].width, p[3] - S[region].height
    end
    local fl, ft, fr, fb = Rect(font)
    local tl, tt = Rect(fills[1])
    local _, _, tr, tb = Rect(fills[#fills])
    local _, _, _, sizeBottom = Rect(w.keySize)
    local options = S[w.lookOptions]
    Equal(table.concat({ fl, ft, fr, fb, tl, tt, tr, tb }, " "), "382 -88 606 -108 382 -116 544 -136", "the font's four choices, then the textures")
    Equal(tostring(ft == S[w.iconShadow].points[1][3] and tt == S[w.look].points[1][3]) .. " "
        .. tostring(ft < sizeBottom and fl > S[w.keybinds].points[1][2] and fr <= options.width and tb >= -options.height)
        .. " " .. tostring(S[w.fillChosen].points[1][2] + 40 <= options.width),
        "true true true", "level with Shadow and the first tick, under the keybinds' Size, inside the choices, the name clear of the edge")
    local fp = S[w.faces].points[1]
    Equal(tostring(fp[2] < fl and fp[3] == ft and fp[2] + S[w.faces].width == fr and fp[3] - S[w.faces].height == tb),
        "true", "one part round both rows and their labels, for the tour")

    -- Each says what it's for on hover; all but today's look need testing.
    Hover(font.buttons[2], "OnEnter")
    Equal(S[w.note].text, "Arial Narrow, plain and narrow, for countdowns, counts, keys and names on icons, and the text on your cast bar"
        .. " and Tracked Bars. (Needs testing)", "each font says what it's for")
    Hover(font.buttons[2], "OnLeave")
    Hover(font.buttons[1], "OnEnter")
    Equal(S[w.note].text:find("Friz Quadrata, the game's own font", 1, true) == 1 and S[w.note].text:find("Needs testing", 1, true), nil,
        "Friz Quadrata, the look as it was, needs no testing")
    Hover(font.buttons[1], "OnLeave")
    Hover(fills[2], "OnEnter")
    Equal(S[w.note].text, "The game's classic unit frame bar on your cast bar, swing timer and combo points, and the restyled Tracked Bars"
        .. " and resource display. (Needs testing)", "each texture says where it goes")
    Hover(fills[2], "OnLeave")

    -- A font picked: every font made so far takes it at once, so the text in
    -- them changes with no reload, and the names under icons follow.
    font.buttons[2]:Click()
    Equal(ns.Get("font") .. " " .. font.selected, "arial arial", "Arial Narrow picked")
    Equal(Last(FECMFont18, "SetFont", 1) .. " " .. Last(FECMFont18, "SetFont", 3) .. " " .. Last(FECMFont13, "SetFont", 1) .. " "
        .. Last(FECMFont13, "SetFont", 3), ARIAL .. " THICKOUTLINE " .. ARIAL .. " OUTLINE",
        "every font made so far takes it at once, its outline as before")
    Equal(Last(FECMFont15, "SetFont", 1) .. " " .. Last(FECMFont10, "SetFont", 1) .. " " .. Last(w.preview.Bar.Duration, "SetFontObject"),
        ARIAL .. " " .. ARIAL .. " FECMFont15", "the preview's Tracked Bar and your cast bar too, keeping their fonts")
    Equal(tostring(Last(cdBar.icons[1].label, "SetFontObject")) .. " " .. tostring(Last(buffBar.holders[1].label, "SetFontObject")),
        "FECMNames FECMNames", "the names under icons, on every bar")
    Equal(tostring(Last(FECMNames, "CopyFontObject") == GameFontHighlightSmall) .. " " .. Last(FECMNames, "SetFont", 1) .. " "
        .. Last(FECMNames, "SetFont", 2), "true " .. ARIAL .. " 12", "a copy of the game's small text, in Arial Narrow at its size")
    B:SetOption("cd", "size", 60)
    Equal(Last(FECMFont30, "SetFont", 1) .. " " .. tostring(Last(cdBar.icons[1].label, "SetFontObject")), ARIAL .. " FECMNames",
        "fonts made later, for a bigger icon, start in it, and the names keep it")
    B:SetOption("cd", "size", 36)

    -- A texture picked: the preview, your cast bar and its page's previews at once.
    fills[2]:Click()
    Equal(ns.Get("barTexture") .. " " .. S[w.fillChosen].text .. " " .. S[fills[2]].border[1] .. " " .. tostring(S[fills[1]].border[1] < 1),
        "classic Classic 1 true", "Classic picked, its swatch outlined")
    Equal(Last(w.preview.Bar, "SetStatusBarTexture") .. " " .. Last(castBar, "SetStatusBarTexture"), CLASSIC .. " " .. CLASSIC,
        "the preview and your cast bar take it at once")
    local set = 0
    rawset(castBar, "SetStatusBarTexture", function(self, texture)
        set = set + 1
        S[self].last.SetStatusBarTexture = table.pack(texture)
    end)
    ns.CastBar:Apply()
    ns.CastBar:Apply()
    Equal(set, 0, "the cast bar, dressed for every cast, only sets it when it changes")
    w:Select("cast")
    local cp = w.pages.cast
    Equal(Last(cp.sample.bar, "SetStatusBarTexture") .. " " .. Last(cp.swingSample.bar, "SetStatusBarTexture"), CLASSIC .. " " .. CLASSIC,
        "and the Cast bar page's previews")
    w:Select("look")
    w.barSwatches[3]:Click()
    Equal(S[fills[1].fill].tint[3], .88, "the textures follow the colour for all bars")
    w.barSwatches[1]:Click()

    -- Back to today's look: Friz Quadrata, the game's own small text for
    -- names, and flat bars.
    font.buttons[1]:Click()
    fills[1]:Click()
    Equal(Last(FECMFont18, "SetFont", 1) .. " " .. tostring(Last(cdBar.icons[1].label, "SetFontObject")) .. " "
        .. Last(w.preview.Bar, "SetStatusBarTexture") .. " " .. Last(castBar, "SetStatusBarTexture") .. " " .. set,
        FRIZ .. " GameFontHighlightSmall " .. FLAT .. " " .. FLAT .. " 1", "back as it was, in one click each")

    -- A font the game won't take: Friz Quadrata stands in, and nothing breaks.
    rawset(FECMFont18, "SetFont", function(self, file, size, flags)
        if file ~= FRIZ then error("not a font the game has") end
        S[self].last.SetFont = table.pack(file, size, flags)
    end)
    font.buttons[3]:Click()
    Equal(Last(FECMFont18, "SetFont", 1) .. " " .. Last(FECMFont13, "SetFont", 1) .. " " .. #printed, FRIZ .. " Fonts\\MORPHEUS.ttf 0",
        "a font the game refuses: Friz Quadrata instead, with no error")

    -- Kept over a reload: the fonts and bars start in them. Anything else
    -- saved is ignored.
    font.buttons[4]:Click()
    fills[3]:Click()
    local saved = ForeverEnhancedCooldownManagerDB
    Fresh(saved)
    Equal(ns.Get("font") .. " " .. ns.Get("barTexture") .. " " .. Last(FECMFont18, "SetFont", 1) .. " "
        .. Last(ns.CastBar.row.bar, "SetStatusBarTexture"), "skurri raid " .. SKURRI .. " " .. RAID,
        "kept over a reload: the fonts made in Skurri and the bars in Raid from the start")
    Equal(S[ns.Bars:Get("cd").icons[1].label].template .. " " .. S[ns.Bars:Get("buff").holders[1].label].template .. " "
        .. Last(FECMNames, "SetFont", 1), "FECMNames FECMNames " .. SKURRI, "the names made in it too")
    saved.font, saved.barTexture = "comic", 7
    Fresh(saved)
    Equal(ns.Get("font") .. " " .. ns.Get("barTexture") .. " " .. Last(FECMFont18, "SetFont", 1), "friz flat " .. FRIZ,
        "anything else saved is ignored")
    Equal(#printed, 0, "no errors from the font or texture")
    _G.PersonalResourceDisplayFrame = display
end)()

-- Flush against the bars you can see ------------------------------------------------------

Environment()
local power = 0 -- the main bar's power: 0 mana (caster form), 1 rage (bear form)
_G.UnitPowerType = function() return power end
Display()
S[prd].rect = { 400, 280, 200, 60 } -- Blizzard's frame keeps a minimum height
local extra = New("StatusBar", prd)
rawset(extra, "powerName", "MANA")
S[extra].rect = { 400, 294, 200, 6 }
rawset(prd, "AlternatePowerBar", extra)
rawset(prd, "UpdatePowerBar", function() end)
ns = Load({ useBars = true, prdSkin = false, prdCombo = true })
B, L = ns.Bars, ns.Layout
B:Assign("Moonfire", "cd")
B:Assign("Attack", "util")
L:Apply("pyramid")
Equal(At(B:Get("cd")) .. " " .. At(B:Get("util")), "BOTTOM 0 -80 TOP 0 -100",
    "flush against the health and mana bars, not the frame around them or the tucked-away extra mana bar")
power = 1
prd:UpdatePowerBar()
Equal(At(B:Get("cd")) .. " " .. At(B:Get("util")), "BOTTOM 0 -80 TOP 0 -106", "in bear form the extra mana bar shows, and Utility sits under it")
Equal(ns.Resource:ComboRow(), nil, "no combo points in bear form")
-- Cat form: the addon's combo points under the extra mana bar, and Utility under them.
power = 3
prd:UpdatePowerBar()
local comboRow = ns.Resource:ComboRow()
Equal(comboRow ~= nil and S[comboRow].shown and S[comboRow].points[1][2] == extra, true, "cat form: combo points under the lowest bar")
S[comboRow].rect = { 400, 280, 200, 8 }
L:Stack()
Equal(At(B:Get("util")), "TOP 0 -120", "and Utility under the combo points while they show")
power = 0
prd:UpdatePowerBar()
Equal(tostring(ns.Resource:ComboRow()) .. " " .. tostring(S[comboRow].shown), "nil false", "gone in caster form")
Equal(At(B:Get("util")), "TOP 0 -100", "back up against the mana bar in caster form")
-- A form change in a fight: the cooldown bars follow at once, the Buffs bar after.
B:SetAura("buff", "Thorns", true)
lockdown = true
power = 1
prd:UpdatePowerBar()
Equal(At(B:Get("util")) .. " " .. tostring(B:Get("buff").pendingLayout), "TOP 0 -106 true",
    "in a fight Utility moves at once; the Buffs bar waits")
lockdown = false
Fire("PLAYER_REGEN_ENABLED")
Equal(At(B:Get("buff")), "TOP 0 -142", "and catches up once it's over")
power = 0
prd:UpdatePowerBar()
-- The display switched off: the rows close up where it was.
prdOn = false
L:Stack()
Equal(At(B:Get("cd")) .. " " .. At(B:Get("util")), "BOTTOM 0 -90 TOP 0 -90", "with the display off, the rows meet where it was")
prdOn = true
L:Stack()
Equal(At(B:Get("util")), "TOP 0 -100", "and part again when it's back")

-- Your cast bar ------------------------------------------------------------------------------

Environment()
Display()
_G.PlayerCastingBarFrame = Blizzard(New("Frame"), "PlayerCastingBarFrame")
local native = PlayerCastingBarFrame
ns = Load({ useBars = true, prdSkin = false })
B, L = ns.Bars, ns.Layout
local C = ns.CastBar
local cb = C.row
B:Assign("Moonfire", "cd")
B:Assign("Attack", "util")
L:Apply("pyramid")
Equal(tostring(C:Room()) .. " " .. tostring(S[cb].shown) .. " " .. S[native].alpha .. " " .. At(B:Get("util")),
    "nil false 1 TOP 0 -100", "off by default: no room, and Blizzard's cast bar left alone")
ns.Set("castBar", true)
C:Apply()
Equal(At(cb) .. string.format(" %g ", S[cb].width) .. At(B:Get("util")), "TOP 0 -104 200 TOP 0 -122",
    "on: under the display, as wide, and Utility moves down to make room")
Equal(S[cb].shown and S[cb].alpha .. " " .. S[native].alpha, "0 0", "nothing showing between casts, and Blizzard's hidden")
native:SetAlpha(1)
Equal(S[native].alpha, 0, "and it stays hidden when Blizzard shows it for a cast")
-- A cast: its name, icon and length, filling with the time left.
clock = 100
local casting = { "Wrath", "Wrath", 136006, 100000, 101500, false, "cast-1" }
_G.UnitCastingInfo = function(unit) assert(unit == "player"); return table.unpack(casting) end
Fire("UNIT_SPELLCAST_START", "player", "cast-1", 5176)
Equal(S[cb].alpha .. " " .. S[cb.bar.name].text .. " " .. S[cb.icon].texture .. " " .. Last(cb.bar, "SetMinMaxValues", 2), "1 Wrath 136006 1.5",
    "a cast shows its name and icon, as long as the cast")
Equal(Last(cb.bar, "SetStatusBarColor", 1) .. " " .. Last(cb.bar, "SetStatusBarColor", 2), "1 0.7", "in Blizzard's gold")
clock = 100.5
S[cb].scripts.OnUpdate(cb, .5)
Equal(string.format("%g %g", Last(cb.bar, "SetValue", 1), Last(cb.bar.time, "SetFormattedText", 2)), "0.5 1", "filling, with the time left")
Fire("UNIT_SPELLCAST_FAILED", "player", "cast-2", 1)
Equal(S[cb.bar.name].text, "Wrath", "another spell failing doesn't touch it")
Fire("UNIT_SPELLCAST_STOP", "player", "cast-1", 5176)
Equal(string.format("%g", Last(cb.bar, "SetValue", 1)), "1.5", "finished: full")
clock = 101
S[cb].scripts.OnUpdate(cb, .5)
Equal(string.format("%.2f", S[cb].alpha), "0.67", "then it fades")
clock = 101.3
S[cb].scripts.OnUpdate(cb, .3)
Equal(tostring(S[cb].alpha) .. " " .. tostring(S[cb].scripts.OnUpdate), "0 nil", "and it's gone")
-- Interrupted: red, saying so.
casting[7] = "cast-3"
Fire("UNIT_SPELLCAST_START", "player", "cast-3", 5176)
Fire("UNIT_SPELLCAST_INTERRUPTED", "player", "cast-3", 5176)
Equal(S[cb.bar.name].text .. " " .. Last(cb.bar, "SetStatusBarColor", 1), "Interrupted 0.85", "interrupted: red, saying so")
-- A channel: green, draining.
_G.UnitChannelInfo = function() return "Tranquility", "Tranquility", 136107, 102000, 110000, false, false, 740 end
clock = 102
Fire("UNIT_SPELLCAST_CHANNEL_START", "player", nil, 740)
clock = 104
S[cb].scripts.OnUpdate(cb, 2)
Equal(Last(cb.bar, "SetStatusBarColor", 2) .. " " .. string.format("%g", Last(cb.bar, "SetValue", 1)), "0.8 6",
    "a channel: green, draining as it goes")
Fire("UNIT_SPELLCAST_CHANNEL_STOP", "player", nil, 740, "Creature-0-1")
Equal(S[cb.bar.name].text, "Interrupted", "a channel cut short says so too")
_G.UnitChannelInfo = function() return nil end
-- Times the game keeps secret: Blizzard's own bar shows that cast.
casting = { "Wrath", "Wrath", 136006, SECRETS.number, SECRETS.number, false, "cast-4" }
Fire("UNIT_SPELLCAST_START", "player", "cast-4", 5176)
native:SetAlpha(1) -- Blizzard's own bar starting the same cast
Equal(S[cb].alpha .. " " .. S[native].alpha, "0 1", "a cast with secret times: Blizzard's bar shows it")
casting = { "Wrath", "Wrath", 136006, 105000, 106500, false, "cast-5" }
Fire("UNIT_SPELLCAST_START", "player", "cast-5", 5176)
Equal(S[cb].alpha .. " " .. S[native].alpha, "1 0", "and yours takes over again at the next")
Fire("UNIT_SPELLCAST_STOP", "player", "cast-9", 1)
clock = 105.5
S[cb].scripts.OnUpdate(cb, .5)
Equal(string.format("%g", Last(cb.bar, "SetValue", 1)), "0.5", "another spell stopping doesn't end it")
-- Choices: icon, height and colour.
ns.Set("castIcon", false)
ns.Set("castHeight", 24)
ns.Set("castColour", "blue")
C:Apply()
Equal(tostring(S[cb.icon].shown) .. " " .. S[cb].height .. " " .. At(B:Get("util")) .. " " .. Last(cb.bar, "SetStatusBarColor", 1),
    "false 24 TOP 0 -128 " .. ns.Style:BarColour("blue")[1], "no icon, taller (the rows move again), in your colour")
-- The display switched off: the bar sits where it was, between the rows.
prdOn = false
L:Stack()
Equal(At(cb) .. " " .. At(B:Get("util")), "TOP 0 -90 TOP 0 -114", "with the display off, it sits where the display was")
prdOn = true
-- Without a layout it still goes under the display.
L:TurnOff()
ns.Bars:ResetPositions()
L:Stack()
Equal(At(cb), "TOP 0 -104", "without a layout, under the display")
-- Off again, even mid-cast: no room, Blizzard's bar back.
casting[7] = "cast-6"
Fire("UNIT_SPELLCAST_START", "player", "cast-6", 5176)
rawset(native, "casting", true) -- Blizzard's own bar has the cast too
ns.Set("castBar", false)
C:Apply()
L:LineUp()
Equal(tostring(S[cb].shown) .. " " .. S[native].alpha .. " " .. At(B:Get("util")) .. " " .. tostring(S[cb].scripts.OnUpdate),
    "false 1 TOP 0 -100 nil", "off: the rows close up, Blizzard's bar is back mid-cast, and yours drops the cast")
rawset(native, "casting", nil)
-- The Cast bar page: a live preview, and the Layout page draws it.
ns.Set("castBar", true)
C:Apply()
SlashCmdList.FECM("")
w = FECMFrame
w:Select("cast")
local cp = w.pages.cast
Equal(S[cp].shown and S[cp.status].text, "Under your Personal Resource Display. Blizzard's cast bar is hidden.", "its own page")
Equal(S[cp.sample.bar.name].text .. " " .. tostring(S[cp.sample.icon].shown) .. " " .. S[cp.sample].height, "Hearthstone false 24",
    "the preview follows your choices")
S[cp.sample].scripts.OnUpdate(cp.sample, 1)
Equal(string.format("%g", Last(cp.sample.bar, "SetValue", 1)), "1", "and fills as you watch")
cp.swatches[3]:Click()
Equal(S[cp.chosen].text, "Blizzard's gold", "clicking your colour again goes back to Blizzard's")
cp.icon:Click()
Equal(tostring(ns.Get("castIcon")) .. " " .. tostring(S[cp.sample.icon].shown), "true true", "the icon comes back, in the preview too")
w:Select("layout")
Equal(S[w.pages.layout.castStrip].shown, true, "the Layout page draws it under the display")
Equal(w.pages.layout.drawError, nil, "the Layout page drew without errors")
cp.shown:Click()
Equal(tostring(ns.Get("castBar")) .. " " .. tostring(S[w.pages.layout.castStrip].shown), "false false", "switched off from its page")
Equal(#printed, 0, "no errors from the cast bar")
-- Its height is kept over a reload, within its limits.
saved = ForeverEnhancedCooldownManagerDB
Environment(true)
ns = Load(saved)
Equal(ns.Get("castHeight"), 24, "the height kept over a reload")
saved.castHeight = 99
Environment(true)
ns = Load(saved)
Equal(ns.Get("castHeight"), 18, "one out of range is ignored")

-- The swing timer in the cast bar's spot ---------------------------------------------------------

-- In a function of its own: the main chunk is near Lua's limit of 200 locals.
;(function()
    Environment()
    Display()
    _G.PlayerCastingBarFrame = Blizzard(New("Frame"), "PlayerCastingBarFrame")
    local native = PlayerCastingBarFrame
    -- Forever's own swing timers: the addon never touches them.
    local forever = {}
    for _, name in ipairs({ "SwingTimerMainHandFrame", "SwingTimerOffHandFrame", "SwingTimerRangedFrame" }) do
        _G[name] = New("Frame")
        forever[#forever + 1] = _G[name]
    end
    -- A sword in the main hand and a bow in the ranged slot.
    local weapons = { [16] = 135274, [18] = 135490 }
    _G.GetInventoryItemTexture = function(unit, slot) assert(unit == "player"); return weapons[slot] end
    local class = "DRUID"
    _G.UnitClass = function() return class:sub(1, 1) .. class:sub(2):lower(), class end
    ns = Load({ useBars = true, prdSkin = false })
    local B, L, C = ns.Bars, ns.Layout, ns.CastBar
    local sw = C.row
    B:Assign("Moonfire", "cd")
    B:Assign("Attack", "util")
    L:Apply("pyramid")
    local function Gone() return S[sw].alpha .. " " .. tostring(S[sw].scripts.OnUpdate) end
    local function Time() return Last(sw.bar.time, "SetFormattedText", 2) end
    Equal(tostring(ns.Get("swingTimer")) .. " " .. ns.Get("swingColour") .. " " .. tostring(C:Room()) .. " " .. tostring(S[sw].shown),
        "false default nil false", "off by default: no room, nothing shown")
    class = "HUNTER"
    clock = 200
    Fire("PLAYER_SWING", 2.5, 2)
    Equal(Gone(), "0 nil", "off, a swing does nothing")
    ns.Set("swingTimer", true)
    C:Apply()
    Equal(At(sw) .. string.format(" %g ", S[sw].width) .. At(B:Get("util")) .. " " .. Gone(), "TOP 0 -104 200 TOP 0 -122 0 nil",
        "on: the cast bar's spot under the display, Utility under it, and nothing ticking until you swing")
    native:SetAlpha(.5)
    Equal(tostring(C:Room()) .. " " .. S[native].alpha, "18 0.5", "its room kept, and Blizzard's cast bar left alone")
    native:SetAlpha(1)
    -- Auto Shot: the bow's icon, filling from empty, in silver.
    Fire("PLAYER_SWING", 2.5, 2)
    Equal(S[sw].alpha .. " " .. S[sw.bar.name].text .. " " .. S[sw.icon].texture .. " " .. Last(sw.bar, "SetMinMaxValues", 2),
        "1 Auto Shot 135490 2.5", "Auto Shot for a hunter: the ranged weapon's icon, as long as the swing")
    Equal(string.format("%g %g %g", Last(sw.bar, "SetStatusBarColor", 1), Last(sw.bar, "SetStatusBarColor", 3), Last(sw.bar, "SetValue", 1)),
        "0.66 0.72 0", "in silver, starting empty")
    clock = 201
    S[sw].scripts.OnUpdate(sw, 1)
    Equal(string.format("%g %g", Last(sw.bar, "SetValue", 1), Time()), "1 1.5", "filling, with the seconds left")
    -- The off hand, and swings the game keeps secret, are skipped.
    Fire("PLAYER_SWING", 1.8, 1)
    Fire("PLAYER_SWING", SECRETS.number, 2)
    Fire("PLAYER_SWING", 1.2, SECRETS.number)
    Fire("PLAYER_SWING", SECRETS.number, SECRETS.number)
    -- Secret numbers too: the game says so, whatever they'd read as.
    local plain = issecretvalue
    _G.issecretvalue = function(v) return v == 1.7 or plain(v) end
    Fire("PLAYER_SWING", 1.7, 2)
    _G.issecretvalue = function(v) return v == 2 or plain(v) end
    Fire("PLAYER_SWING", 1.9, 2)
    _G.issecretvalue = plain
    for _, odd in ipairs({ 0, -1, 0 / 0, math.huge, "2" }) do Fire("PLAYER_SWING", odd, 0) end
    Fire("PLAYER_SWING", nil, 0)
    Fire("PLAYER_SWING", 2, nil)
    clock = 201.5
    S[sw].scripts.OnUpdate(sw, .5)
    Equal(string.format("%s %g %g", S[sw.bar.name].text, Last(sw.bar, "SetMinMaxValues", 2), Last(sw.bar, "SetValue", 1)),
        "Auto Shot 2.5 1.5", "the off hand, secret swings and odd times are skipped, never guessed at")
    -- Shot after shot: held full as each runs out, so the bar never blinks.
    local lowest = 1
    rawset(sw, "SetAlpha", function(self, alpha)
        lowest = math.min(lowest, alpha)
        S[self].alpha = alpha
    end)
    clock = 202.6 -- ran out at 202.5
    S[sw].scripts.OnUpdate(sw, 1.1)
    Equal(string.format("%g %g %g", Last(sw.bar, "SetValue", 1), Time(), S[sw].alpha), "2.5 0 1", "run out: full, and held")
    clock = 202.8
    S[sw].scripts.OnUpdate(sw, .2)
    Fire("PLAYER_SWING", 2.5, 2)
    Equal(string.format("%g %g", lowest, Last(sw.bar, "SetValue", 1)), "1 0", "the next shot starts it again, with no blink between")
    rawset(sw, "SetAlpha", nil)
    clock = 205.8 -- ran out at 205.3
    S[sw].scripts.OnUpdate(sw, 3)
    Equal(string.format("%.2f", S[sw].alpha), "0.67", "no next shot: it fades like a finished cast")
    clock = 206.1
    S[sw].scripts.OnUpdate(sw, .3)
    Equal(Gone(), "0 nil", "and it's gone, with nothing left ticking")
    -- The main hand, and other classes' ranged swings.
    Fire("PLAYER_SWING", 3.2, 0)
    Equal(S[sw.bar.name].text .. " " .. S[sw.icon].texture .. " " .. Last(sw.bar, "SetMinMaxValues", 2) .. " " .. S[sw].alpha,
        "Main hand 135274 3.2 1", "a melee swing: Main hand, with the main hand weapon's icon")
    class = "DRUID"
    Fire("PLAYER_SWING", 2, 2)
    Equal(S[sw.bar.name].text, "Ranged", "a ranged swing for any other class")
    weapons[16], weapons[18] = nil, SECRETS.number
    Fire("PLAYER_SWING", 3.2, 0)
    local sword = S[sw.icon].texture
    Fire("PLAYER_SWING", 2, 2)
    Equal(sword .. " " .. S[sw.icon].texture, "Interface\\Icons\\INV_Sword_04 Interface\\Icons\\INV_Weapon_Bow_05",
        "no weapon icon to hand, or a secret one: a sword or a bow")
    weapons[16], weapons[18] = 135274, 135490
    class = "HUNTER"
    -- The height and parts are the cast bar's.
    ns.Set("castHeight", 24)
    ns.Set("castIcon", false)
    C:Apply()
    Equal(S[sw].height .. " " .. tostring(S[sw.icon].shown) .. " " .. At(B:Get("util")) .. " " .. Last(sw.bar, "SetStatusBarColor", 1),
        "24 false TOP 0 -128 0.66", "the swing timer follows the height and parts, and keeps its colour")
    ns.Set("castHeight", 18)
    ns.Set("castIcon", true)
    C:Apply()
    -- A new weapon or a loading screen clears it.
    Fire("WEAPON_SLOT_CHANGED")
    Equal(Gone(), "0 nil", "a weapon change clears it")
    Fire("PLAYER_SWING", 2.5, 2)
    Fire("PLAYER_ENTERING_WORLD")
    Equal(Gone(), "0 nil", "and so does a loading screen")
    -- The cast bar off: casts stay on Blizzard's bar, and the swing keeps the spot.
    clock = 207
    Fire("PLAYER_SWING", 2.5, 2)
    local casting = { "Wrath", "Wrath", 136006, 207000, 208500, false, "cast-1" }
    _G.UnitCastingInfo = function() return table.unpack(casting) end
    Fire("UNIT_SPELLCAST_START", "player", "cast-1", 5176)
    Equal(S[sw.bar.name].text .. " " .. S[native].alpha, "Auto Shot 1",
        "with the cast bar off, casts are left to Blizzard's bar and the swing timer keeps the spot")
    -- Both on: one spot, and a cast takes it while it lasts.
    ns.Set("castBar", true)
    C:Apply()
    Equal(tostring(C:Room()) .. " " .. At(B:Get("util")) .. " " .. S[native].alpha .. " " .. S[sw.bar.name].text,
        "18 TOP 0 -122 0 Auto Shot", "both on: one spot, Blizzard's cast bar hidden, the swing still showing")
    clock = 210
    Fire("PLAYER_SWING", 3, 0)
    casting = { "Wrath", "Wrath", 136006, 210500, 212000, false, "cast-2" }
    clock = 210.5
    Fire("UNIT_SPELLCAST_START", "player", "cast-2", 5176)
    Equal(S[sw.bar.name].text .. " " .. Last(sw.bar, "SetStatusBarColor", 1), "Wrath 1", "a cast takes the spot, in gold")
    clock = 211
    Fire("PLAYER_SWING", 3, 0)
    S[sw].scripts.OnUpdate(sw, .5)
    Equal(S[sw.bar.name].text .. " " .. string.format("%g", Last(sw.bar, "SetValue", 1)), "Wrath 0.5", "a swing meanwhile waits its turn")
    clock = 212
    Fire("UNIT_SPELLCAST_STOP", "player", "cast-2", 5176)
    clock = 212.5
    S[sw].scripts.OnUpdate(sw, .5)
    Equal(S[sw.bar.name].text .. string.format(" %.2f", S[sw].alpha), "Wrath 0.67", "the finished cast holds and fades as before")
    clock = 212.8
    S[sw].scripts.OnUpdate(sw, .3)
    Equal(string.format("%s %g %g %.1f", S[sw.bar.name].text, S[sw].alpha, Last(sw.bar, "SetStatusBarColor", 1), Last(sw.bar, "SetValue", 1)),
        "Main hand 1 0.66 1.8", "then the swing timer comes back, in its own colour, where it's got to")
    -- A swing that runs out during a cast doesn't come back just to fade.
    clock = 215
    Fire("PLAYER_SWING", 2.5, 0) -- runs out at 217.5, just before the cast has faded
    casting = { "Wrath", "Wrath", 136006, 215000, 218000, false, "cast-3" }
    Fire("UNIT_SPELLCAST_START", "player", "cast-3", 5176)
    clock = 217
    S[sw].scripts.OnUpdate(sw, 2)
    Fire("UNIT_SPELLCAST_STOP", "player", "cast-3", 5176)
    clock = 217.8
    S[sw].scripts.OnUpdate(sw, .8)
    Equal(Gone(), "0 nil", "a swing that ran out during the cast stays gone")
    -- Broken off: red, then the swing timer again.
    clock = 220
    Fire("PLAYER_SWING", 3, 0)
    casting = { "Wrath", "Wrath", 136006, 220000, 222000, false, "cast-4" }
    Fire("UNIT_SPELLCAST_START", "player", "cast-4", 5176)
    Fire("UNIT_SPELLCAST_INTERRUPTED", "player", "cast-4", 5176)
    Equal(S[sw.bar.name].text .. " " .. Last(sw.bar, "SetStatusBarColor", 1), "Interrupted 0.85", "an interrupted cast shows red as before")
    clock = 220.8
    S[sw].scripts.OnUpdate(sw, .8)
    Equal(S[sw.bar.name].text .. " " .. S[sw].alpha, "Main hand 1", "and the swing timer comes back after")
    -- Auto-attack switched off (the target died): the swing stops where it is
    -- and fades instead of filling on. Auto Shot stopping leaves a melee swing
    -- alone, and the other way round.
    clock = 225
    Fire("PLAYER_SWING", 3, 0)
    clock = 226
    S[sw].scripts.OnUpdate(sw, 1)
    Fire("STOP_AUTOREPEAT_SPELL")
    clock = 226.5
    S[sw].scripts.OnUpdate(sw, .5)
    Equal(string.format("%s %g %g", S[sw.bar.name].text, Last(sw.bar, "SetValue", 1), S[sw].alpha), "Main hand 1.5 1",
        "Auto Shot stopping leaves a melee swing filling")
    Fire("PLAYER_LEAVE_COMBAT")
    clock = 227
    S[sw].scripts.OnUpdate(sw, .5)
    Equal(string.format("%g [%s] %.2f", Last(sw.bar, "SetValue", 1), S[sw.bar.time].text, S[sw].alpha), "1.5 [] 0.67",
        "the mob died: it stops where it was, its time cleared, and fades")
    clock = 227.3
    S[sw].scripts.OnUpdate(sw, .3)
    Equal(Gone(), "0 nil", "then it's gone, not filling on")
    clock = 230
    Fire("PLAYER_SWING", 2.5, 2)
    Fire("PLAYER_LEAVE_COMBAT")
    clock = 230.2
    S[sw].scripts.OnUpdate(sw, .2)
    Equal(string.format("%s %.1f %g", S[sw.bar.name].text, Last(sw.bar, "SetValue", 1), S[sw].alpha), "Auto Shot 0.2 1",
        "melee stopping leaves Auto Shot filling")
    Fire("STOP_AUTOREPEAT_SPELL")
    clock = 231
    S[sw].scripts.OnUpdate(sw, .8)
    Equal(Gone(), "0 nil", "Auto Shot switched off: that swing stops and goes too")
    -- Stopped during a cast: it doesn't come back after the cast.
    clock = 232
    Fire("PLAYER_SWING", 3, 0)
    casting = { "Wrath", "Wrath", 136006, 232000, 233000, false, "cast-5" }
    Fire("UNIT_SPELLCAST_START", "player", "cast-5", 5176)
    Fire("PLAYER_LEAVE_COMBAT")
    clock = 233
    Fire("UNIT_SPELLCAST_STOP", "player", "cast-5", 5176)
    clock = 233.8
    S[sw].scripts.OnUpdate(sw, .8)
    Equal(Gone(), "0 nil", "a swing stopped during a cast stays gone after it")
    -- The Layout page draws the spot while either is on.
    SlashCmdList.FECM("")
    local w = FECMFrame
    w:Select("layout")
    local strip = w.pages.layout.castStrip
    Equal(tostring(S[strip].shown) .. " " .. Last(strip, "SetColorTexture", 1), "true 1", "the Layout page draws the spot, in the cast bar's colour")
    w:Select("cast")
    local cp = w.pages.cast
    Equal(S[cp.status].text, "Cast bar and swing timer under your resource display. Blizzard's cast bar is hidden.", "the page says both are on")
    cp.shown:Click()
    native:SetAlpha(1) -- Blizzard's own bar starting a cast
    w:Select("layout")
    Equal(tostring(S[strip].shown) .. " " .. Last(strip, "SetColorTexture", 1) .. " " .. tostring(C:Room()) .. " " .. S[native].alpha,
        "true 0.66 18 1", "only the swing timer: the spot in its silver, and Blizzard's cast bar back")
    w:Select("cast")
    cp.swing:Click()
    w:Select("layout")
    Equal(tostring(S[strip].shown) .. " " .. tostring(C:Room()) .. " " .. At(B:Get("util")) .. " " .. tostring(S[sw].shown) .. " " .. Gone(),
        "false nil TOP 0 -100 false 0 nil", "both off from the page: no spot, the rows close up, nothing ticking")
    -- The Cast bar page: a tick, a colour and a preview for the swing timer.
    w:Select("cast")
    Equal(S[cp.swing.text].text .. "|" .. S[cp.icon.text].text .. "|" .. S[cp.name.text].text .. "|" .. S[cp.timer.text].text,
        "Swing timer in this spot|Icon|Name|Time left", "the ticks read right for both")
    Equal(tostring(cp.swing:GetChecked()) .. " " .. S[cp.sample].alpha .. " " .. S[cp.swingSample].alpha, "false 0.35 0.35",
        "both off: both preview bars dimmed")
    Equal(S[cp.swingSample.bar.name].text .. " " .. S[cp.swingSample.icon].texture, "Auto Shot Interface\\Icons\\INV_Weapon_Bow_05",
        "a hunter's preview swings Auto Shot, with a bow")
    cp.swing:Click()
    Equal(tostring(ns.Get("swingTimer")) .. " " .. S[cp.swingSample].alpha .. " " .. S[cp.sample].alpha .. " " .. S[cp.status].text,
        "true 1 0.35 Swing timer under your resource display. Casts show on Blizzard's cast bar.", "ticked: its preview lights up")
    Equal(tostring(C:Room()) .. " " .. tostring(S[sw].shown), "18 true", "and the spot is back")
    S[cp.swing].scripts.OnEnter(cp.swing)
    local note = S[w.note].text
    Equal(note:find("Main hand and ranged swings: Auto Shot for hunters, Ranged for other classes.", 1, true) ~= nil
        and note:find("A cast takes the spot", 1, true) ~= nil and note:find("EraUI", 1, true) ~= nil, true,
        "its note: main hand and ranged, as shown above, casts first, and the other swing timers")
    S[cp.swing].scripts.OnLeave(cp.swing)
    -- The Name tick names all three a swing can be called.
    S[cp.name].scripts.OnEnter(cp.name)
    note = S[w.note].text
    Equal(note:find("Main hand, Auto Shot or Ranged for the swing timer", 1, true) ~= nil, true, "the Name tick's note lists Ranged too")
    S[cp.name].scripts.OnLeave(cp.name)
    -- What's new for 1.0.0 says what it does: the main hand for everyone, hunters
    -- too, and ranged swings, called Auto Shot for hunters.
    local bullet, first
    for _, entry in ipairs(ns.NOTES) do
        if entry.version == "1.0.0" then first = entry end
    end
    for _, section in ipairs(first.sections) do
        for _, item in ipairs(section[2]) do
            if item:find("^Swing timer") then bullet = item end
        end
    end
    Equal(bullet:find("your main hand and ranged swings (Auto Shot for hunters)", 1, true) ~= nil
        and bullet:find("everyone else", 1, true) == nil, true, "What's new: main hand and ranged, not Auto Shot only for hunters")
    cp.swingSwatches[3]:Click()
    Equal(ns.Get("swingColour") .. " " .. S[cp.swingChosen].text .. " " .. Last(cp.swingSample.bar, "SetStatusBarColor", 1) .. " " .. ns.Get("castColour"),
        "blue Blue " .. ns.Style:BarColour("blue")[1] .. " default", "a colour of its own, in the preview, leaving the cast bar's")
    Fire("PLAYER_SWING", 2.5, 2)
    Equal(Last(sw.bar, "SetStatusBarColor", 1), ns.Style:BarColour("blue")[1], "and on the real one")
    cp.swingSwatches[3]:Click()
    Equal(ns.Get("swingColour") .. " " .. S[cp.swingChosen].text, "default Silver", "clicking it again goes back to silver")
    S[cp.swingSample].scripts.OnUpdate(cp.swingSample, 1)
    Equal(string.format("%g %.1f", Last(cp.swingSample.bar, "SetValue", 1), Last(cp.swingSample.bar.time, "SetFormattedText", 2)), "1 1.8",
        "the preview swings as you watch")
    S[cp.swingSample].scripts.OnUpdate(cp.swingSample, 2)
    Equal(string.format("%.1f", Last(cp.swingSample.bar, "SetValue", 1)), "0.2", "over and over")
    class = "DRUID"
    w:Refresh()
    Equal(S[cp.swingSample.bar.name].text .. " " .. S[cp.swingSample.icon].texture, "Main hand Interface\\Icons\\INV_Sword_04",
        "anyone else's preview swings the main hand, with a sword")
    class = "HUNTER"
    -- Everything fits the page, top to bottom, none overlapping.
    local tray = S[cp.options].points[1][2]
    local top = -S[tray].points[1][3] + S[tray].height - S[cp.options].points[1][5]
    local rows = { cp.shown, cp.swing, cp.swatches[1], cp.swingSwatches[1], cp.height, cp.icon, cp.name, cp.timer }
    local bottom, clear = 0, true
    for _, row in ipairs(rows) do
        local y = -S[row].points[1][3]
        if y < bottom + 4 then clear = false end
        bottom = y + S[row].height
    end
    local aboutTop = -S[cp.about].points[1][3]
    local last = aboutTop + cp.about:GetStringHeight()
    Equal(tostring(clear and aboutTop >= bottom + 4) .. " " .. tostring(top + last <= 489), "true true", "the page's rows don't overlap and fit the window")
    Equal(S[tray].height / 2 >= 3 + ns.CAST_HEIGHT[2] + 5 and S[cp.sample].points[1][1] .. " " .. S[cp.swingSample].points[1][1],
        "BOTTOMLEFT TOPLEFT", "both preview bars fit the tray at the tallest height, one above the middle and one below")
    -- Forever's own swing timers are never touched.
    local untouched = true
    for _, frame in ipairs(forever) do
        if next(S[frame].last) ~= nil or S[frame].alpha ~= 1 or not S[frame].shown then untouched = false end
    end
    Equal(untouched, true, "Forever's own swing timers untouched")
    Equal(#printed, 0, "no errors from the swing timer")
    -- Kept over a reload; anything else is ignored.
    ns.Set("swingColour", "purple")
    local kept = ForeverEnhancedCooldownManagerDB
    Environment(true)
    ns = Load(kept)
    Equal(tostring(ns.Get("swingTimer")) .. " " .. ns.Get("swingColour"), "true purple", "kept over a reload")
    kept.swingTimer, kept.swingColour = "yes", "pink"
    Environment(true)
    ns = Load(kept)
    Equal(tostring(ns.Get("swingTimer")) .. " " .. ns.Get("swingColour") .. " " .. tostring(ns.Valid("swingColour", "class"))
        .. " " .. tostring(ns.Valid("swingColour", "default")) .. " " .. tostring(ns.Valid("swingColour", 3)),
        "false default true true false", "anything else is ignored: off, and silver")
    Environment()
    ns = Load(nil)
    Equal(tostring(ns.Get("swingTimer")) .. " " .. tostring(S[ns.CastBar.row].shown), "false false", "a new install: off")
    for _, name in ipairs({ "SwingTimerMainHandFrame", "SwingTimerOffHandFrame", "SwingTimerRangedFrame", "PlayerCastingBarFrame" }) do
        _G[name] = nil
    end
end)()

-- The cast bar exactly as wide as the display ------------------------------------------------------

;(function()
    -- How big one of a region's own units is on screen: its own size, or what it sits in.
    local function Scale(region)
        while region do
            local own = rawget(region, "GetEffectiveScale")
            if own then return own(region) end
            region = S[region] and S[region].parent
        end
        return 1
    end
    -- Where a region's left and right edges end up across the screen, from its
    -- anchors and width as the game lays them out; Blizzard's bars from their rects.
    local function Across(region)
        if region == UIParent then return S[UIParent].cx, S[UIParent].cx end
        local s = S[region]
        if s.rect and #s.points == 0 then
            local scale = Scale(region)
            return s.rect[1] * scale, (s.rect[1] + s.rect[3]) * scale
        end
        local left, right, middle
        for _, p in ipairs(s.points) do
            local point, relative, relativePoint, x = p[1], p[2], p[3], p[4]
            if type(relative) ~= "table" then relative, relativePoint, x = s.parent, point, relative end
            local l, r = Across(relative)
            local at = relativePoint:find("LEFT") and l or relativePoint:find("RIGHT") and r or (l + r) / 2
            at = at + (x or 0) * Scale(region)
            if point:find("LEFT") then left = at elseif point:find("RIGHT") then right = at else middle = at end
        end
        local width = s.width * Scale(region)
        if middle then left, right = middle - width / 2, middle + width / 2 end
        return left or right - width, right or left + width
    end
    -- The whole cast bar you see: its edge, and its icon's while that shows.
    local function Seen(cb)
        local left, right = Across(cb.bar.edge)
        if S[cb.iconEdge].shown then left = math.min(left, (Across(cb.iconEdge))) end
        return string.format("%.2f %.2f", left, right)
    end
    -- The display you see: the restyle's edge round its power bar.
    local function Restyled()
        local edge
        for _, obj in ipairs(objects) do
            local p = S[obj].parent == prd.PowerBar and S[obj].kind == "Texture" and S[obj].points[1]
            if p and p[1] == "TOPLEFT" and p[4] < 0 then edge = obj end
        end
        return edge and string.format("%.2f %.2f", Across(edge))
    end

    Environment()
    Display()
    prdOn = true
    _G.PlayerCastingBarFrame = Blizzard(New("Frame"), "PlayerCastingBarFrame")
    ns = Load({ useBars = true, castBar = true, castIcon = true })
    local B, L, C = ns.Bars, ns.Layout, ns.CastBar
    local cb = C.row
    B:Assign("Moonfire", "cd")
    B:Assign("Attack", "util")
    L:Apply("pyramid")
    -- The display's bars run from 400 to 600; the restyle's 1px edge goes round them.
    Equal(Restyled() .. string.format(" %g %g", L:Display().width, L:Display().edge), "399.00 601.00 202 1",
        "the restyled display: its bars and 1px edges")
    Equal(Seen(cb) .. " " .. string.format("%.2f %.2f", Across(cb.icon)), "399.00 601.00 400.00 418.00",
        "the cast bar, icon to bar end, edge to edge with the display, the icon on its bars' line")
    ns.Set("castIcon", false)
    C:Apply()
    Equal(Seen(cb) .. " " .. string.format("%.2f", (Across(cb.bar))), "399.00 601.00 400.00",
        "no icon: the bar's own edge takes its place")
    ns.Set("castIcon", true)
    ns.Set("castBar", false)
    ns.Set("swingTimer", true)
    C:Apply()
    Equal(Seen(cb) .. " " .. tostring(S[cb].shown), "399.00 601.00 true", "the swing timer in the same spot, just as wide")
    -- Switched off, it sits where the display was, still no wider.
    prdOn = false
    L:Stack()
    Equal(Seen(cb) .. " " .. At(cb), "399.00 601.00 TOP 0 -90", "with the display switched off, exactly where its edges were")
    prdOn = true
    L:Stack()
    -- A display last seen before the edge was kept: the restyle's 1px.
    local seen = ns.LayoutData().display
    seen.edge = nil
    _G.PersonalResourceDisplayFrame = nil
    L:Stack()
    Equal(Seen(cb) .. " " .. tostring(seen.edge), "399.00 601.00 1", "a display remembered from before still lines up")
    _G.PersonalResourceDisplayFrame = prd
    -- Edit Mode's Size makes the display and its 1px edges bigger or smaller;
    -- the cast bar follows its edges exactly.
    for _, size in ipairs({ 1.5, .7 }) do
        for _, part in ipairs({ prd, prd.HealthBarsContainer, prd.PowerBar }) do
            rawset(part, "GetEffectiveScale", function() return size end)
        end
        L:Stack()
        Equal(Seen(cb), Restyled(), string.format("at %g%% Size, still edge to edge with the display", size * 100))
    end
    for _, part in ipairs({ prd, prd.HealthBarsContainer, prd.PowerBar }) do rawset(part, "GetEffectiveScale", nil) end
    Equal(#printed, 0, "no errors lining it up")

    -- Without the restyle: its icon and bar span the display's bars exactly,
    -- its own edges just outside them, where the restyle's would be.
    Environment()
    Display()
    _G.PlayerCastingBarFrame = Blizzard(New("Frame"), "PlayerCastingBarFrame")
    ns = Load({ useBars = true, prdSkin = false, castBar = true })
    B, L, C = ns.Bars, ns.Layout, ns.CastBar
    cb = C.row
    B:Assign("Moonfire", "cd")
    L:Apply("pyramid")
    Equal(string.format("%.2f %.2f ", (Across(cb.icon)), select(2, Across(cb.bar))) .. Seen(cb), "400.00 600.00 399.00 601.00",
        "without the restyle: icon and bar span the display's bars, its edges where the restyle's go")
    prdOn = false
    L:Stack()
    Equal(Seen(cb), "399.00 601.00", "and the same with the display switched off")
    prdOn = true

    -- Its shadow reaches as far out as your rows' does, whatever borders go under theirs.
    local function Reach(ring) return 1 - S[ring[3]].points[1][4] end -- past the edge it's round
    local function Shown(ring) return tostring(ring ~= nil and S[ring[1]].shown == true) end -- rings not made yet: not shown
    local cd = B:Get("cd")
    local reaches = {}
    for _, pair in ipairs({ { "off", "bar" }, { "bar", "bar" }, { "icon", "bar" }, { "off", "icon" }, { "icon", "icon" }, { "bar", "icon" } }) do
        ns.Set("iconBorder", pair[1])
        ns.Set("iconShadow", pair[2])
        B:ApplyDecor()
        C:Apply()
        local rows = pair[2] == "bar" and cd.decor or cd.icons[1].decor
        reaches[#reaches + 1] = pair[1] .. "/" .. pair[2] .. " " .. Reach(rows.shadow[4]) .. " " .. Reach(cb.decor.shadow[4])
            .. " " .. Shown(cb.decor.shadow[4]) .. " " .. Shown(cb.decor.border)
    end
    Equal(table.concat(reaches, ", "), "off/bar 4 4 true false, bar/bar 5 5 true false, icon/bar 4 4 true false, "
        .. "off/icon 4 4 true false, icon/icon 5 5 true false, bar/icon 4 4 true false",
        "the cast bar's shadow fades out just where the rows' does, and it never gets a second border")
    ns.Set("iconBorder", "off")
    ns.Set("iconShadow", "bar")
    C:Apply()
    Equal(Reach(cb.decor.shadow[1]), 1, "with no border, its shadow's darkest ring sits under its own 1px edge, as a row's sits on its icons")
    Equal(#printed, 0, "no errors from its shadow")
    _G.PlayerCastingBarFrame = nil
    Display()
end)()

-- Borders and shadows on your bars -------------------------------------------------------------

Environment()
ns = Load({ useBars = true })
B = ns.Bars
B:Assign("Moonfire", "cd")
B:SetAura("buff", "Thorns", true)
local cdBar, buffBar = B:Get("cd"), B:Get("buff")
local function Shown(ring) return tostring(ring ~= nil and S[ring[1]].shown == true) end -- rings not made yet: not shown
Equal(tostring(cdBar.icons[1].decor.border) .. " " .. tostring(cdBar.decor.shadow) .. " " .. tostring(buffBar.holders[1].decor.border),
    "nil nil nil", "none to start with: both off, so not even made (20 textures an icon or bar)")
SlashCmdList.FECM("")
w = FECMFrame
w:Select("look")
w.iconBorder.buttons[2]:Click()
w.iconShadow.buttons[3]:Click()
Equal(ns.Get("iconBorder") .. " " .. ns.Get("iconShadow"), "icon bar", "picked on the Look page")
Equal(Shown(cdBar.icons[1].decor.border) .. " " .. Shown((cdBar.decor.shadow or {})[1]) .. " " .. Shown(cdBar.decor.border),
    "true true false", "a border round each icon and a shadow round each bar")
Equal(Shown(buffBar.holders[1].decor.border), "true", "the Buffs bar's icons too")
Equal(Shown(w.sampleIcons.icons[1].decor.border) .. " " .. Shown((w.sampleIcons.decor.shadow or {})[1]), "true true",
    "shown in the Look page's preview")
Equal(Shown((ns.CastBar.row.decor.shadow or {})[1]) .. " " .. Shown(ns.CastBar.row.decor.border), "true false",
    "your cast bar gets the shadow, keeping its own edges")
B:Assign("Wrath", "cd")
Equal(Shown(cdBar.icons[2].decor.border), "true", "new icons get it as they're made")
w.iconBorder.buttons[1]:Click()
w.iconShadow.buttons[1]:Click()
Equal(Shown(cdBar.icons[1].decor.border) .. " " .. Shown((cdBar.decor.shadow or {})[1]) .. " " .. Shown((ns.CastBar.row.decor.shadow or {})[1]),
    "false false false", "and Off takes them away")
Equal(#printed, 0, "no errors from borders and shadows")

-- A whole-bar box only goes round icons that stay put: not packed Buffs or
-- Debuffs, a bar hiding its ready icons, or greyed Debuffs spots with no enemy.
do
    Environment()
    ns = Load({ useBars = true })
    B = ns.Bars
    B:Assign("Moonfire", "cd")
    B:SetAura("buff", "Thorns", true)
    B:SetAura("debuff", "Moonfire", true)
    ns.Set("iconBorder", "bar")
    ns.Set("iconShadow", "bar")
    B:ApplyDecor()
    local cd, buff, debuff = B:Get("cd"), B:Get("buff"), B:Get("debuff")
    Equal(Shown(cd.decor.border) .. " " .. Shown((cd.decor.shadow or {})[1]), "true true", "a cooldown bar gets the whole-bar box")
    Equal(Shown(buff.decor.border) .. " " .. Shown((buff.decor.shadow or {})[1]) .. " " .. Shown(debuff.decor.border), "false false false",
        "packed Buffs and Debuffs don't: their icons come and go")
    B:SetOption("cd", "whenReady", "hide")
    Equal(Shown(cd.decor.border), "false", "nor a bar that hides its ready icons")
    B:SetUnlocked(true)
    Equal(Shown(cd.decor.border), "true", "unless every icon shows, unlocked")
    B:SetUnlocked(false)
    Equal(Shown(cd.decor.border), "false", "locked again, it goes")
    B:SetOption("cd", "whenReady", "dim")
    Equal(Shown(cd.decor.border) .. " " .. Shown((cd.decor.shadow or {})[1]), "true true", "a bar that dims them keeps them in place, and its box")
    B:SetOption("cd", "whenReady", "show")
    Equal(Shown(cd.decor.border), "true", "and it's back with Hide when ready off")
    B:SetOption("buff", "showMissing", true)
    Equal(Shown(buff.decor.border), "true", "fixed Buffs spots always show, so they get it")
    target, hostile = false, true
    B:SetOption("debuff", "showMissing", true)
    Fire("PLAYER_TARGET_CHANGED")
    Equal(Shown(debuff.decor.border) .. " " .. tostring(debuff.enemy), "false false", "fixed Debuffs spots with no enemy don't")
    target = true
    Fire("PLAYER_TARGET_CHANGED")
    Equal(Shown(debuff.decor.border), "true", "until you target one")
    -- Each icon: a greyed Debuffs spot's rings go with it.
    ns.Set("iconBorder", "icon")
    ns.Set("iconShadow", "icon")
    B:ApplyDecor()
    local spot = debuff.holders[1]
    Equal(Shown(spot.decor.border) .. " " .. Shown((spot.decor.shadow or {})[1]) .. " " .. Shown(debuff.decor.border), "true true false",
        "each icon: the spots ringed while there's an enemy")
    target = false
    Fire("PLAYER_TARGET_CHANGED")
    Equal(Shown(spot.decor.border) .. " " .. tostring(S[spot.icon].alpha), "false 0", "no enemy: the greyed spot goes, rings and all")
    B:ApplyDecor()
    Equal(Shown(spot.decor.border) .. " " .. Shown(buff.holders[1].decor.border), "false true",
        "the Look page doesn't bring them back, and Buffs spots keep theirs")
    hostile, target = SECRET, true
    Fire("PLAYER_TARGET_CHANGED")
    Equal(Shown(spot.decor.border), "true", "a hidden answer counts as an enemy")
    hostile = true
    Equal(#printed, 0, "no errors from whole-bar boxes")

    -- A last row short of the rest (the user's Utility: 5 icons, 4 across)
    -- is boxed round its own icons, not left in an empty box the width of the
    -- bar: the full rows get one box, the short row another.
    ;(function()
    Environment()
    ns = Load({ useBars = true })
    B = ns.Bars
    for _, name in ipairs({ "Attack", "Moonfire", "Wrath", "Thorns", "Overpower" }) do B:Assign(name, "util") end
    B:SetOption("util", "perRow", 4)
    ns.Set("iconShadow", "bar")
    B:ApplyDecor()
    local util = B:Get("util")
    local size = ns.IconSize(ns.BarData("util"))
    local function Anchor(region, i)
        local p = S[region].points[i]
        if not p then return "-" end
        local to = p[2] == util and "bar" or "?"
        for n, icon in ipairs(util.icons) do if p[2] == icon then to = "icon" .. n end end
        return p[1] .. ">" .. to .. "." .. p[3] .. "(" .. (p[4] or 0) .. "," .. (p[5] or 0) .. ")"
    end
    local function Box(region) return Anchor(region, 1) .. " " .. Anchor(region, 2) end
    Equal(ns.BarData("util").wrap .. " " .. ns.BarData("util").grow .. " " .. util.count, "down centre 5", "five icons, a row of four and one under it")
    Equal(Box(util.block), "TOPLEFT>bar.TOPLEFT(0,0) BOTTOMRIGHT>bar.TOPRIGHT(0," .. -size .. ")", "the bar's box goes round the full row only")
    Equal(Box(util.tail), "TOPLEFT>icon5.TOPLEFT(0,0) BOTTOMRIGHT>icon5.BOTTOMRIGHT(0,0)", "the short row's box round its one icon")
    Equal(Shown((util.decor.shadow or {})[1]) .. " " .. Shown((util.tailDecor.shadow or {})[1]) .. " " .. Shown(util.tailDecor.border),
        "true true false", "both shadowed, as chosen (no border)")
    Equal(tostring(S[util.decor.shadow[1][1]].points[1][2] == util.block) .. " " .. tostring(S[util.tailDecor.shadow[1][1]].points[1][2] == util.tail),
        "true true", "each ring follows its box")
    -- A full last row: one box round the bar, as before.
    B:Assign("Overpower", nil)
    Equal(#S[util.block].points .. " " .. tostring(Last(util.block, "SetAllPoints") == util) .. " " .. Shown((util.tailDecor.shadow or {})[1])
        .. " " .. Shown((util.decor.shadow or {})[1]), "0 true false true", "four icons, four across: the whole bar, no second box")
    -- Growing up (above the display) and from the right: the short row is on
    -- top, its first icon on the right.
    B:Assign("Overpower", "util")
    B:Assign("Walk on Air", "util")
    ns.BarData("util").wrap, ns.BarData("util").grow = "up", "left"
    B:Relayout("util")
    Equal(Box(util.block) .. " | " .. Box(util.tail), "BOTTOMLEFT>bar.BOTTOMLEFT(0,0) TOPRIGHT>bar.BOTTOMRIGHT(0," .. size .. ") | "
        .. "TOPLEFT>icon6.TOPLEFT(0,0) BOTTOMRIGHT>icon5.BOTTOMRIGHT(0,0)", "the full row at the bottom, the short one above it")
    -- Laid out again on its own (as when a potion runs out, even in a fight),
    -- a row that fills up loses its second box at once.
    local utilSpells = ns.BarData("util").spells
    local held = { table.remove(utilSpells), table.remove(utilSpells) }
    B:Relayout("util")
    Equal(util.count .. " " .. Shown((util.tailDecor.shadow or {})[1]) .. " " .. Shown((util.decor.shadow or {})[1]), "4 false true",
        "four left: one box again")
    utilSpells[#utilSpells + 1], utilSpells[#utilSpells + 2] = held[2], held[1]
    B:Relayout("util")
    Equal(util.count .. " " .. Shown((util.tailDecor.shadow or {})[1]), "6 true", "six again: the short row's box is back")
    -- One short of a full row is short too: five in rows of three.
    B:Assign("Walk on Air", nil)
    B:SetOption("util", "perRow", 3)
    Equal(util.count .. " " .. Shown((util.tailDecor.shadow or {})[1]) .. " " .. Box(util.tail), "5 true "
        .. "TOPLEFT>icon5.TOPLEFT(0,0) BOTTOMRIGHT>icon4.BOTTOMRIGHT(0,0)", "three and two: the two boxed on their own")
    -- Hiding ready icons: no box at all, short row or not.
    B:SetOption("util", "whenReady", "hide")
    Equal(Shown((util.decor.shadow or {})[1]) .. " " .. Shown((util.tailDecor.shadow or {})[1]), "false false", "a bar that hides its ready icons gets neither")
    B:SetOption("util", "whenReady", "show")
    Equal(Shown((util.decor.shadow or {})[1]) .. " " .. Shown((util.tailDecor.shadow or {})[1]), "true true", "both back")
    -- Fixed Buffs spots work the same; packed ones never get a box.
    for _, name in ipairs({ "Thorns", "Moonfire", "Wrath", "Walk on Air", "Clearcasting" }) do B:SetAura("buff", name, true) end
    B:SetOption("buff", "perRow", 4)
    B:SetOption("buff", "showMissing", true)
    local buff = B:Get("buff")
    local tailTo = S[buff.tail].points[1]
    Equal(tostring(tailTo and tailTo[2] == buff.holders[5]) .. " " .. Shown((buff.tailDecor.shadow or {})[1]), "true true",
        "five fixed Buffs spots, four across: the fifth boxed on its own")
    B:SetOption("buff", "showMissing", false)
    Equal(tostring(buff.short) .. " " .. Shown((buff.tailDecor.shadow or {})[1]) .. " " .. Shown((buff.decor.shadow or {})[1]), "false false false",
        "packed: no box, and no short row")
    Equal(#printed, 0, "no errors from short rows")
    end)()

    -- Blizzard's packed icons can't be used while auras are secret, so the
    -- Look page changes theirs once the fight is over; yours change at once.
    Environment()
    ns = Load({ useBars = true })
    B = ns.Bars
    B:Assign("Moonfire", "cd")
    B:SetAura("buff", "Thorns", true)
    local packed = B:Get("buff").groupParts
    -- One packed entry: the ten icons Blizzard makes for its group as it's added.
    Equal(#packed .. " " .. Shown(packed[1].decor.border), "10 false", "a packed entry's icons, no border yet")
    Fire("PLAYER_REGEN_DISABLED")
    lockdown = true
    ns.Set("iconBorder", "icon")
    B:ApplyDecor()
    Equal(Shown(B:Get("cd").icons[1].decor.border) .. " " .. Shown(packed[1].decor.border) .. " " .. tostring(B:Get("buff").pendingDecor),
        "true false true", "in a fight your icons change at once; Blizzard's packed ones wait")
    lockdown = false
    Fire("PLAYER_REGEN_ENABLED")
    Equal(Shown(packed[1].decor.border) .. " " .. tostring(B:Get("buff").pendingDecor), "true nil", "and change once it's over")
    Equal(#printed, 0, "no errors from redrawing in a fight")
end

-- Joined entries take one slot between them ------------------------------------------------

do
    Environment()
    ns = Load({ useBars = true })
    B = ns.Bars
    ns.BUFF_SLOTS = 2
    B:SetAura("buff", "Thorns", true)
    B:SetAura("buff", "Clearcasting", true)
    B:SetJoined("buff", 2, true)
    Equal(B:SlotsUsed("buff"), 1, "a joined pair takes one slot")
    Equal(B:SetAura("buff", "Nature's Grace", true), true, "so a second icon still fits")
    Equal(B:SetAura("buff", "Walk on Air", true), false, "but not a third")
    local ok, why = B:SetJoined("buff", 2, false)
    Equal(tostring(ok) .. " " .. tostring(why) .. " " .. tostring(B:Joined("buff", 2)), "false Buffs is full. true",
        "splitting past the slots is refused")
    ok, why = B:MoveTo("buff", 2, 3)
    Equal(tostring(ok) .. " " .. tostring(why) .. " | " .. Shape("buff"), "false Buffs is full. | Thorns+Clearcasting, Nature's Grace",
        "so is dragging one out of its group, which puts everything back")
    Equal(B:MoveTo("buff", 3, 1), true, "a move that needs no more icons is fine")
    Equal(Shape("buff"), "Nature's Grace, Thorns+Clearcasting", "and happens")
    ns.BUFF_SLOTS = 16
    Equal(B:SetJoined("buff", 3, false), true, "with room, a split goes through")
    Equal(Shape("buff"), "Nature's Grace, Thorns, Clearcasting", "split")
    B:Assign("Moonfire", "cd")
    B:Assign("Wrath", "cd")
    Equal(B:MoveTo("cd", 1, 2), true, "cooldown bars move as before")
    Equal(table.concat(ns.BarData("cd").spells, ","), "Wrath,Moonfire", "moved")
    Equal(#printed, 0, "no errors from slots")
end

-- Only what a bar can show goes on it -------------------------------------------------------

do
    Environment()
    Book(true)
    ns = Load({ useBars = true })
    B = ns.Bars
    B:Assign("Moonfire@1", "cd")
    local ok, why = B:Transfer("cd", "buff", "Moonfire@1")
    Equal(tostring(ok) .. " " .. tostring(why), "false Fixed ranks can't go on the Buffs bar, which counts every rank already.",
        "a fixed rank can't be dragged onto Buffs")
    Equal(table.concat(ns.BarData("cd").spells, ","), "Moonfire@1", "and stays on Cooldowns")
    Equal(B:Transfer("cd", "debuff", "Moonfire@1"), false, "nor onto Debuffs")
    Equal(B:Transfer("cd", "util", "Moonfire@1"), true, "Utility is fine")
    B:SetAura("buff", "Clearcasting", true)
    ok, why = B:Transfer("buff", "cd", "Clearcasting")
    Equal(tostring(ok) .. " " .. tostring(why), "false Procs only go on the Buffs bar.", "a proc can't go onto Cooldowns")
    Equal(tostring(B:Transfer("buff", "debuff", "Clearcasting")) .. " " .. tostring(B:HasAura("buff", "Clearcasting")), "false true",
        "nor Debuffs, and it stays on Buffs")
    ok, why = B:Add("debuff", "Clearcasting")
    Equal(tostring(ok) .. " " .. tostring(why), "false Procs only go on the Buffs bar.", "added by name, it says why")
    Equal((B:Add("buff", "Moonfire (Rank 1)")), false, "a fixed rank added to Buffs by name is refused")
    Equal((B:Add("util", "Moonfire (Rank 2)")), true, "but it's fine on a cooldown bar")
    Equal((B:Add("buff", "Thorns")), true, "a buff on Buffs is fine")
    Equal(B:Transfer("buff", "debuff", "Thorns"), true, "and plain spells move between aura bars as before")
    Equal(#printed, 0, "no errors from what fits")

    -- On the Layout page: refused, the spell stays and the footer says why.
    Environment()
    Book(true)
    Display()
    ns = Load({ useBars = true, prdSkin = false })
    B = ns.Bars
    B:Assign("Moonfire@1", "cd")
    B:SetAura("buff", "Thorns", true)
    SlashCmdList.FECM("")
    w = FECMFrame
    w:Select("layout")
    local lp = w.pages.layout
    local tile = lp.rows.cd.tiles[1]
    S[tile].scripts.OnDragStart(tile)
    S[lp.rows.buff].mouseOver = true
    S[tile].scripts.OnDragStop(tile)
    S[lp.rows.buff].mouseOver = nil
    Equal(table.concat(ns.BarData("cd").spells, ",") .. " " .. S[w.note].text,
        "Moonfire@1 Fixed ranks can't go on the Buffs bar, which counts every rank already.", "dragged onto the Buffs row, it stays")
end

-- Swapping: an icon dropped onto another trades places with it ------------------------------

do
    Environment()
    Book(true)
    Display()
    ns = Load({ useBars = true, prdSkin = false })
    B = ns.Bars
    local function List(key) return table.concat(ns.BarData(key).spells, ",") end
    local function Lists() return List("cd") .. " | " .. List("util") .. " | " .. List("buff") .. " | " .. List("debuff") end
    -- On one bar, by place in its list: just the two move.
    for _, name in ipairs({ "Moonfire", "Wrath", "Overpower" }) do B:Assign(name, "cd") end
    local ok, said = B:Swap("cd", 1, 3)
    Equal(tostring(ok) .. " " .. said .. " " .. List("cd"), "true Swapped Moonfire and Overpower. Overpower,Wrath,Moonfire",
        "two entries on a bar swap places, the one between staying put")
    Equal(tostring(B:Swap("cd", 2, 2)) .. " " .. tostring(B:Swap("cd", 1, 9)) .. " " .. List("cd"), "false false Overpower,Wrath,Moonfire",
        "not with itself or with nothing")

    -- The Layout page: the icons as drawn in each row.
    SlashCmdList.FECM("")
    w = FECMFrame
    w:Select("layout")
    local lp = w.pages.layout
    local rows = lp.rows
    -- Holds a tile over another tile (in its row, as in the game) or just a
    -- row, then lets go. Gives the footer while it was held and what was
    -- outlined: the icon under it, the row, or nothing.
    local function Drag(tile, onto, row)
        S[tile].scripts.OnDragStart(tile)
        if row then S[row].mouseOver = true end
        if onto then S[onto].mouseOver = true end
        S[lp.ghost].scripts.OnUpdate(lp.ghost)
        local mark = S[lp.mark]
        local at = mark.shown and mark.points[1] and mark.points[1][2]
        local where = not mark.shown and "none" or at == onto and "icon" or row and at == row.strip and "row" or "elsewhere"
        local seen = S[w.note].text .. " | " .. where
        S[tile].scripts.OnDragStop(tile)
        if row then S[row].mouseOver = nil end
        if onto then S[onto].mouseOver = nil end
        return seen
    end
    local cd, util, buff = rows.cd, rows.util, rows.buff
    -- The reported case: two icons on the same bar, one dropped on the other.
    Equal(Drag(cd.tiles[3], cd.tiles[1], cd), "Let go to swap Moonfire and Overpower. | icon",
        "held over an icon in its own row: that one outlined, and the footer says they'll swap")
    Equal(S[lp.mark].border[1], .69, "outlined in the accent")
    Equal(tostring(S[lp.ghost.texture].desaturated), "false", "the held icon in full colour")
    Equal(List("cd") .. " | " .. S[w.note].text, "Moonfire,Wrath,Overpower | Swapped Moonfire and Overpower.",
        "dropped on it, the two swap places in the row")
    Equal(cd.tiles[1].name .. " " .. cd.tiles[3].name .. " " .. tostring(S[lp.mark].shown) .. " " .. tostring(w.dragging),
        "Moonfire Overpower false nil", "drawn that way, the outline and the drag note gone")
    -- An empty spot in its own row, or its own spot: nothing changes.
    Equal(cd.tiles[6].name, nil, "an empty spot")
    Equal(Drag(cd.tiles[1], cd.tiles[6], cd), "Let go to leave Moonfire where it is. | none", "over an empty spot in its own row, nothing outlined")
    Equal(Drag(cd.tiles[1], cd.tiles[1], cd), "Let go to leave Moonfire where it is. | none", "nor over its own spot")
    Equal(List("cd"), "Moonfire,Wrath,Overpower", "and letting go there changes nothing")
    -- Another class's spell (a shared profile) isn't drawn, and stays put.
    table.insert(ns.BarData("cd").spells, 2, "Garrote")
    w:Refresh()
    Equal(cd.tiles[2].name, "Wrath", "another class's spell isn't drawn")
    Drag(cd.tiles[1], cd.tiles[2], cd)
    Equal(List("cd"), "Wrath,Garrote,Moonfire,Overpower", "swapped round it, it stays where it was")
    table.remove(ns.BarData("cd").spells, 2)

    -- Between two rows: each takes the other's place on the other's bar.
    B:Assign("Walk on Air", "util")
    B:Assign("Attack", "util")
    w:Refresh()
    Equal(Drag(util.tiles[1], cd.tiles[2], cd), "Let go to swap Walk on Air and Moonfire. | icon",
        "held over an icon in another row: outlined, and the footer says they'll swap")
    Equal(Lists() .. " | " .. S[w.note].text, "Wrath,Walk on Air,Overpower | Moonfire,Attack |  |  | Swapped Walk on Air and Moonfire.",
        "the two swap bars, each in the other's place")
    -- An empty spot in another row still moves it there, at the end.
    Equal(Drag(cd.tiles[1], util.tiles[5], util), "Let go to move Wrath to Utility. | row",
        "held over another row's empty spot: that row outlined, and the footer says it moves there")
    Equal(Lists() .. " | " .. S[w.note].text, "Walk on Air,Overpower | Moonfire,Attack,Wrath |  |  | Moved Wrath to Utility.",
        "and letting go moves it to the end of that bar")
    -- Between a cooldown bar and the Buffs bar.
    B:SetAura("buff", "Thorns", true)
    w:Refresh()
    Equal(Drag(buff.tiles[1], cd.tiles[1], cd), "Let go to swap Thorns and Walk on Air. | icon", "held over Walk on Air")
    Equal(Lists() .. " | " .. S[w.note].text, "Thorns,Overpower | Moonfire,Attack,Wrath | Walk on Air |  | Swapped Thorns and Walk on Air.",
        "Buffs and Cooldowns swap too")
    B:Assign("Thorns", nil)
    B:Assign("Walk on Air", "cd")
    B:SetAura("buff", "Walk on Air", false)
    Equal(Lists(), "Overpower,Walk on Air | Moonfire,Attack,Wrath |  | ", "set up again")

    -- Only what each bar can show, once: otherwise nothing moves and the
    -- footer says why.
    B:SetAura("buff", "Thorns", true)
    B:Assign("Moonfire@1", "cd")
    w:Refresh()
    local before = Lists()
    -- Held over an icon it can't swap with, the footer already says why:
    -- nothing outlined, the held icon greyed.
    Equal(Drag(cd.tiles[3], buff.tiles[1], buff),
        "Can't swap: Fixed ranks can't go on the Buffs bar, which counts every rank already. | none",
        "held over an icon it can't swap with: the footer says why before letting go, nothing outlined")
    Equal(tostring(S[lp.ghost.texture].desaturated), "true", "and the held icon greyed")
    Equal(Lists() .. " | " .. S[w.note].text, before .. " | Fixed ranks can't go on the Buffs bar, which counts every rank already.",
        "a fixed rank can't swap onto Buffs")
    B:SetAura("buff", "Clearcasting", true)
    ok, said = B:Trade("buff", "Clearcasting", "cd", "Overpower")
    Equal(tostring(ok) .. " " .. tostring(said), "false Procs only go on the Buffs bar.", "a proc can't swap onto Cooldowns")
    B:Assign("family:healing", "util")
    ok, said = B:Trade("util", "family:healing", "buff", "Thorns")
    Equal(tostring(ok) .. " " .. tostring(said), "false Items can't go on the Buffs bar.", "nor an item onto Buffs")
    B:Assign("Thorns", "util")
    ok, said = B:Trade("buff", "Thorns", "cd", "Overpower")
    Equal(tostring(ok) .. " " .. tostring(said), "false Thorns is already on Utility.", "nor onto one cooldown bar while it's on the other")
    B:SetAura("debuff", "Moonfire", true)
    B:SetAura("debuff", "Wrath", true)
    ok, said = B:Trade("debuff", "Moonfire", "util", "Attack")
    Equal(tostring(ok) .. " " .. tostring(said), "false Moonfire is already on Utility.", "nor onto a cooldown bar it's already on")
    ok, said = B:Trade("util", "Moonfire", "debuff", "Wrath")
    Equal(tostring(ok) .. " " .. tostring(said), "false Moonfire is already on Debuffs.", "nor onto an aura bar it's already on")
    B:SetAura("buff", "Clearcasting", false)
    Equal(Lists(), "Overpower,Walk on Air,Moonfire@1 | Moonfire,Attack,Wrath,family:healing,Thorns | Thorns | Moonfire,Wrath",
        "nothing moved")
    -- A paladin's buff added by name shows on your Buffs bar only: it doesn't
    -- swap or move onto a cooldown bar, where it would be hidden with no icon
    -- left to drag it back.
    B:Add("buff", "Blessing of Might")
    w:Refresh()
    before = Lists()
    Equal(buff.tiles[2].name, "Blessing of Might", "a paladin's buff on the Buffs row")
    Equal(Drag(buff.tiles[2], cd.tiles[1], cd), "Can't swap: Blessing of Might can't show on the Cooldowns bar for you. | none",
        "held over a Cooldowns icon: the footer says why")
    Equal(Lists() .. " | " .. S[w.note].text, before .. " | Blessing of Might can't show on the Cooldowns bar for you.",
        "and letting go there leaves both where they were")
    ok, said = B:Trade("cd", "Overpower", "buff", "Blessing of Might")
    Equal(tostring(ok) .. " " .. tostring(said), "false Blessing of Might can't show on the Cooldowns bar for you.",
        "nor does a Cooldowns icon swap with it")
    ok, said = B:Transfer("buff", "util", "Blessing of Might")
    Equal(tostring(ok) .. " " .. tostring(said) .. " | " .. Lists(),
        "false Blessing of Might can't show on the Utility bar for you. | " .. before, "nor is it moved to another row")
    B:SetAura("buff", "Blessing of Might", false)

    -- The Buffs row: a joined group moves whole, and stays on its bar.
    B:SetAura("buff", "Nature's Grace", true)
    B:SetJoined("buff", 2, true)
    B:SetAura("buff", "Walk on Air", true)
    w:Refresh()
    Equal(Shape("buff") .. " | " .. buff.tiles[1].name .. " " .. buff.tiles[2].name, "Thorns+Nature's Grace, Walk on Air | Thorns Walk on Air",
        "a joined pair is one icon on the Layout page")
    Equal(Drag(buff.tiles[2], buff.tiles[1], buff), "Let go to swap Walk on Air and Thorns. | icon", "held over the pair")
    Equal(Shape("buff") .. " | " .. S[w.note].text, "Walk on Air, Thorns+Nature's Grace | Swapped Walk on Air and Thorns.",
        "the pair and the icon swap, the pair still joined")
    Equal(B:Trade("buff", "Thorns", "buff", "Nature's Grace"), false, "a group doesn't swap with itself")
    ok, said = B:Trade("buff", "Thorns", "cd", "Overpower")
    Equal(tostring(ok) .. " " .. tostring(said) .. " | " .. Shape("buff") .. " | " .. List("cd"),
        "false Joined icons only swap on their own bar. | Walk on Air, Thorns+Nature's Grace | Overpower,Walk on Air,Moonfire@1",
        "a joined icon doesn't swap onto another bar")
    ok, said = B:Trade("cd", "Overpower", "buff", "Thorns")
    Equal(tostring(ok) .. " " .. tostring(said), "false Joined icons only swap on their own bar.", "nor does another bar's icon swap into one")

    -- In a fight: swapped as moving is, the Buffs bar catching up once it's over.
    lockdown = true
    containerCallsInCombat = 0
    ok = B:Trade("buff", "Walk on Air", "buff", "Thorns")
    Equal(tostring(ok) .. " " .. Shape("buff") .. " " .. tostring(B:Get("buff").pendingLayout) .. " " .. containerCallsInCombat,
        "true Thorns+Nature's Grace, Walk on Air true 0", "saved at once, the Buffs bar untouched till the fight ends")
    lockdown = false
    Fire("PLAYER_REGEN_ENABLED")
    Equal(B:Get("buff").pendingLayout, nil, "and redrawn after it")
    -- A join an old profile kept for the entry arriving doesn't join it to
    -- the icon before its new place.
    B:Assign("Walk on Air", nil)
    ns.Joins("buff").Attack = true
    ok = B:Trade("util", "Attack", "buff", "Walk on Air")
    Equal(tostring(ok) .. " " .. Shape("buff") .. " | " .. List("util"),
        "true Thorns+Nature's Grace, Attack | Moonfire,Walk on Air,Wrath,family:healing,Thorns", "it arrives on its own")
    B:Assign("Walk on Air", "cd")
    B:Swap("cd", 2, 3)
    w:Refresh()
    -- Dragged off still takes it off.
    Equal(Drag(cd.tiles[1]), "Let go to take Overpower off Cooldowns. | none", "held off the rows: the footer says it comes off")
    Equal(tostring(S[lp.ghost.texture].desaturated), "true", "and the held icon greyed")
    Equal(List("cd") .. " | " .. S[w.note].text, "Walk on Air,Moonfire@1 | Took Overpower off Cooldowns.", "and it does")
    -- In a profile shared with a rogue, a Buffs icon joined only to the
    -- rogue's buff (hidden for you) looks like one on its own: the footer
    -- says why it stays on its bar. In its own row it still swaps.
    B:SetAura("buff", "Evasion", true)
    B:SetJoined("buff", 4, true)
    w:Refresh()
    Equal(Shape("buff") .. " | " .. buff.tiles[2].name, "Thorns+Nature's Grace, Attack+Evasion | Attack",
        "Attack joined to the rogue's Evasion, drawn on its own")
    local hidden = "Attack is joined to another character's spell, so it only swaps on Buffs."
    Equal(Drag(buff.tiles[2], cd.tiles[1], cd), "Can't swap: " .. hidden .. " | none", "held over another row's icon: the footer says why")
    ok, said = B:Trade("cd", "Walk on Air", "buff", "Attack")
    Equal(tostring(ok) .. " " .. tostring(said) .. " | " .. List("cd"), "false " .. hidden .. " | Walk on Air,Moonfire@1",
        "nor does another row's icon swap into it")
    Equal(Drag(buff.tiles[2], buff.tiles[1], buff), "Let go to swap Attack and Thorns. | icon", "in its own row it swaps")
    Equal(Shape("buff"), "Attack+Evasion, Thorns+Nature's Grace", "the rogue's buff going with it")
    Equal(#printed, 0, "no errors from swapping")
end

-- A Buffs or Debuffs bar dragged as a fight starts is let go first ---------------------------

do
    Environment()
    ns = Load({ useBars = true })
    B = ns.Bars
    B:SetAura("buff", "Thorns", true)
    B:SetUnlocked(true)
    local bar = B:Get("buff")
    S[bar.mover].scripts.OnDragStart(bar.mover)
    Equal(bar.dragging, true, "dragging")
    S[bar].cx, S[bar].cy = 620, 450
    Fire("PLAYER_REGEN_DISABLED")
    Equal(tostring(bar.dragging) .. " " .. tostring(S[bar].last.StopMovingOrSizing ~= nil), "nil true",
        "let go as the fight starts, before it's locked")
    Equal(ns.BarData("buff").x, 120, "and placed where it was")
    lockdown = true
    local points = #S[bar].points
    S[bar].last.StopMovingOrSizing = nil
    S[bar.mover].scripts.OnDragStop(bar.mover)
    Equal(tostring(S[bar].last.StopMovingOrSizing) .. " " .. #S[bar].points, "nil " .. points, "the late drag stop moves nothing in the fight")
    S[bar.mover].scripts.OnDragStart(bar.mover)
    Equal(bar.dragging, nil, "and no drag starts in one")
    lockdown = false
    Fire("PLAYER_REGEN_ENABLED")
    Equal(#printed, 0, "no errors from dragging into a fight")
end

-- Each class's debuffs, from Blizzard's own spell data -------------------------------------

local function Has(list, name)
    for _, item in ipairs(list) do if item == name then return true end end
    return false
end
local druid = ns.DEBUFFS.DRUID
Equal(tostring(Has(druid, "Moonfire")) .. " " .. tostring(Has(druid, "Faerie Fire")) .. " " .. tostring(Has(druid, "Rake")),
    "true true true", "a druid's debuffs: Moonfire, Faerie Fire, Rake")
Equal(tostring(Has(druid, "Wrath")) .. " " .. tostring(Has(druid, "Thorns")), "false false", "not a plain nuke or a buff")
Equal(tostring(Has(ns.DEBUFFS.ROGUE, "Rupture")) .. " " .. tostring(Has(ns.DEBUFFS.WARRIOR, "Sunder Armor")), "true true",
    "every class has its own")
Equal(ns.RANKS["Jeff Dummy 1"], nil, "no test dummies")
-- Each race's spells, by race ID, from the same data: racials, passive ones
-- too, and class spells only some races get. Spells any race can have
-- aren't listed.
do
local races = ns.SPELL_RACES
Equal(races["Underwater Breathing"] .. " " .. races.Cannibalize .. " " .. races["Will of the Forsaken"] .. " " .. races["War Stomp"]
    .. " " .. races["Blood Fury"] .. " " .. races["Walk on Air"], "5 5 5 6 2 95 96",
    "the undead's racials (the passive one too), the tauren's, the orc's and the Skyborne's")
Equal(races["Touch of Weakness"] .. " " .. races["Hex of Weakness"] .. " " .. tostring(races["Holy Light"]) .. " " .. tostring(races["Serpent Sting"])
    .. " " .. tostring(races["Find Herbs"]), "5 8 nil nil nil", "a race's priest spells; class and profession spells any race can have aren't listed")
end

-- Taking a bar out, putting it back, and Reset ----------------------------------------------

Environment()
Display()
ns = Load({ useBars = true, prdSkin = false })
B, L = ns.Bars, ns.Layout
B:Assign("Moonfire", "cd")
B:Assign("Attack", "util")
B:SetAura("buff", "Thorns", true)
B:SetAura("debuff", "Moonfire", true)
L:Apply("pyramid")
SlashCmdList.FECM("")
w = FECMFrame
w:Select("layout")
lp = w.pages.layout
local confirm = w.confirm
lp.rows.debuff.out:Click()
Equal(S[confirm.shade].shown and S[confirm.dialog.title].text, "Take Debuffs out of your layout?", "the x asks first")
confirm.no:Click()
Equal(L:IsHidden("debuff"), false, "Cancel leaves it in")
lp.rows.debuff.out:Click()
confirm.yes:Click()
Equal(tostring(L:IsHidden("debuff")) .. " " .. tostring(InSight(B:Get("debuff"))), "true false",
    "taken out: it doesn't show, even with a debuff on it")
Equal(tostring(S[lp.rows.debuff].shown) .. " " .. tostring(S[lp.outButtons.debuff].shown), "false true",
    "its row is gone from the drawing, with a button to put it back")
Equal(table.concat(L:Rows(), ","), "cd,util,buff", "and from the rows you can swap")
Equal(table.concat(ns.BarData("debuff").spells, ","), "Moonfire", "its spells stay")
w:Select("debuff")
Equal(S[w.pages.bar.putBack].shown, true, "its own page says it's out, with Put back")
w:Select("layout")
-- Kept over a reload.
saved = ForeverEnhancedCooldownManagerDB
Environment(true)
Display()
ns = Load(saved)
Equal(tostring(ns.Layout:IsHidden("debuff")) .. " " .. ns.LayoutData().base, "true pyramid", "still out after a reload")
B, L = ns.Bars, ns.Layout
SlashCmdList.FECM("")
w = FECMFrame
w:Select("layout")
lp = w.pages.layout
confirm = w.confirm
lp.outButtons.debuff:Click()
Equal(tostring(L:IsHidden("debuff")) .. " " .. tostring(InSight(B:Get("debuff"))), "false true", "put back, it shows again")
-- All four out: after Live preview, two to a line, clear of Unlock bars and Reset positions.
for _, key in ipairs(ns.BAR_KEYS) do L:TakeOut(key) end
w:Refresh()
local wrapped = {}
for _, key in ipairs(ns.BAR_KEYS) do
    local q = S[lp.outButtons[key]].points[1]
    wrapped[#wrapped + 1] = q[4] .. " " .. q[5]
end
Equal(table.concat(wrapped, ", "), "204 9, 294 9, 204 31, 294 31", "the last two wrap to a second line")
for _, key in ipairs(ns.BAR_KEYS) do L:PutBack(key) end
w:Refresh()
-- Reset: the preset as first set up, asked first.
L:SetGap(4)
L:SetSpacing(3)
L:SetAcross("cd", 9)
lp.reset:Click()
Equal(S[confirm.dialog.title].text, "Reset your layout?", "Reset asks first")
confirm.yes:Click()
local reset = ns.LayoutData()
Equal(reset.gap .. " " .. reset.spacing .. " " .. ns.BarData("cd").perRow .. " " .. tostring(reset.preset) .. " " .. S[w.note].text,
    "0 0 6 pyramid Pyramid is back as it was first set up.", "the preset back as it was, rows and icons flush")
L:Undo()
Equal(ns.BarData("cd").perRow .. " " .. ns.LayoutData().gap, "9 4", "and Undo puts your changes back")

-- Finding a debuff and picking its spot ------------------------------------------------------

L:Reset()
w:Refresh()
local search = lp.search
S[search].scripts.OnEditFocusGained(search)
Equal(S[lp.results].shown and lp.found[1].spell, "Moonfire", "your class's debuffs, the ones you know first")
search:SetText("fae")
S[search].scripts.OnTextChanged(search, true)
Equal(lp.found[1].spell .. " " .. tostring(S[lp.found[2]].shown), "Faerie Fire false", "narrowed as you type")
Equal(S[lp.found[1].name].colour[1], ns.Theme.MUTED[1], "greyed while you haven't learned it")
lp.found[1]:Click()
Equal(S[lp.dragHint].text .. " " .. tostring(S[lp.cancel].shown) .. " " .. tostring(S[lp.rows.debuff.target].shown),
    "Click a spot in the Debuffs row for Faerie Fire. true true", "then it asks for a spot in the Debuffs row")
lp.rows.cd.tiles[1]:Click()
Equal(S[w.note].text .. " " .. #ns.BarData("debuff").spells, "Debuffs go in the Debuffs row. 1", "only there")
lp.rows.debuff.tiles[1]:Click()
Equal(table.concat(ns.BarData("debuff").spells, ",") .. " " .. S[w.note].text, "Faerie Fire,Moonfire Added Faerie Fire to Debuffs.",
    "put in the spot you picked")
Equal(S[lp.dragHint].text .. " " .. tostring(S[lp.cancel].shown), "Drag spells or items onto a row. Hover a row to change it. false",
    "and back to normal")
-- Changed your mind: Cancel.
search:SetText("demoral")
S[search].scripts.OnTextChanged(search, true)
lp.found[1]:Click()
Equal(S[lp.dragHint].text, "Click a spot in the Debuffs row for Demoralizing Roar.", "another debuff picked")
lp.cancel:Click()
Equal(tostring(S[lp.cancel].shown) .. " " .. tostring(S[lp.rows.debuff.target].shown), "false false", "Cancel puts things back")
lp.rows.debuff.tiles[1]:Click()
Equal(table.concat(ns.BarData("debuff").spells, ","), "Faerie Fire,Moonfire", "and nothing is added")
Equal(lp.drawError, nil, "the Layout page drew without errors")
-- An undead priest finds the undead priest's Touch of Weakness, not the troll
-- priest's Hex of Weakness, which would never show for it.
_G.UnitClass = function() return "Priest", "PRIEST" end
_G.UnitRace = function() return "Undead", "Scourge", 5 end
search:SetText("weakness")
S[search].scripts.OnTextChanged(search, true)
Equal(lp.found[1].spell .. " " .. tostring(S[lp.found[2]].shown), "Touch of Weakness false", "your race's debuffs only")
search:SetText("")
S[search].scripts.OnEditFocusLost(search)
_G.UnitClass = function() return "Druid", "DRUID" end
_G.UnitRace = function() return "Skyborne", "Skyborne", 96 end

-- A first install: the window and a welcome ------------------------------------------

-- Nothing new to show: the window opens instead, a moment after login and
-- never in combat, offering the tour.
do
    Environment()
    _G.FECMFrame, _G.FECMTour, _G.FECMNotes = nil, nil, nil
    ns = Load(nil)
    Equal(FECMFrame, nil, "a first install waits a moment to open the window")
    lockdown = true
    for _, timer in ipairs(timers) do timer() end
    Equal(FECMFrame, nil, "not in combat")
    lockdown = false
    Fire("PLAYER_REGEN_ENABLED")
    local tw, box = FECMFrame, FECMTour
    Equal(tw ~= nil and S[tw].shown, true, "then the window opens")
    Equal(S[box].shown and S[box.title].text, "WELCOME", "with a welcome")
    Equal(S[box.next.label].text .. "|" .. S[box.skip.label].text .. "|" .. tostring(S[box.back].shown),
        "Take the tour|Skip|false", "offering the tour, or Skip")
    Equal(FECMNotes == nil or not S[FECMNotes].shown, true, "and no What's new")
    box.skip:Click()
    Equal(S[box].shown, false, "Skip closes the welcome")
    Equal(S[tw].shown and S[tw.note].text, "Take the tour any time from the General page, or with /ccm tour.",
        "leaving the window open, and saying where the tour is")
    -- Once only.
    local saved = ForeverEnhancedCooldownManagerDB
    Environment(true)
    _G.FECMFrame, _G.FECMTour = nil, nil
    ns = Load(saved)
    for _, timer in ipairs(timers) do timer() end
    Equal(FECMFrame == nil and FECMTour == nil, true, "the welcome only comes once")
end

-- The tour --------------------------------------------------------------------------------

-- In a function of its own: the main chunk is near Lua's limit of 200 locals.
;(function()
    Environment()
    _G.FECMFrame, _G.FECMTour = nil, nil
    ns = Load({ useBars = false })
    -- Ticks as wide as their labels while the window is made, so the Cast bar
    -- step's two ticks differ.
    local fixedWidth = Proto.GetStringWidth
    Proto.GetStringWidth = function(self) return #(S[self].text or "") * 6 end
    SlashCmdList.FECM("tour")
    Proto.GetStringWidth = fixedWidth
    local tw, box = FECMFrame, FECMTour
    local function Outlined() return S[box.outline].points[1][2] end
    local function Anchor() local p = S[box].points[1]; return p[1] .. " " .. p[3] end
    Equal(S[tw].shown and S[box].shown, true, "/ccm tour opens the window with the tour")
    Equal(S[box.count].text .. " " .. S[box.title].text, "1 of 9 THE MENU", "nine steps, the menu first")
    Equal(Outlined() == tw.navFrame and S[box.outline].shown, true, "outlining the menu")
    Equal(Anchor(), "TOPLEFT TOPRIGHT", "its box beside it")
    Equal(S[box.back].shown, false, "no Back on the first step")
    box.next:Click()
    Equal(tw.selected .. " " .. S[box.title].text, "general SWITCH YOUR BARS ON", "Next opens the General page")
    Equal(Outlined(), tw.useBars, "outlining Use my bars")
    Equal(S[box.text].text:find("Try it: tick it.", 1, true) ~= nil, true, "asking you to try it")
    S[box].scripts.OnUpdate(box, .3)
    Equal(S[box.title].text, "SWITCH YOUR BARS ON", "waiting until you do")
    tw.useBars:Click()
    S[box].scripts.OnUpdate(box, .1)
    Equal(S[box.title].text, "SWITCH YOUR BARS ON", "looking a few times a second, not every frame")
    S[box].scripts.OnUpdate(box, .2)
    Equal(tw.selected .. " " .. S[box.title].text, "cd ADD SPELLS", "ticking it moves the tour on by itself")
    Equal(Outlined() == tw.pages.bar.listPanel and Anchor() == "BOTTOMLEFT TOPLEFT", true, "the spell list, the box above it")
    ns.Bars:Assign("Moonfire", "cd")
    S[box].scripts.OnUpdate(box, .3)
    Equal(S[box.title].text, "THIS BAR'S OPTIONS", "adding a spell moves it on")
    Equal(Outlined(), tw.pages.bar.optionsArea, "outlining the bar's options")
    box.back:Click()
    Equal(S[box.title].text, "ADD SPELLS", "Back goes back a step")
    S[box].scripts.OnUpdate(box, .3)
    Equal(S[box.title].text, "ADD SPELLS", "a step done before doesn't skip itself")
    box.next:Click()
    tw:Select("look")
    Equal(S[box].shown and not S[box.outline].shown, true, "on another page the outline hides, the box stays")
    tw:Select("util")
    Equal(S[box.outline].shown, true, "any bar's page counts as the bar page")
    box.next:Click()
    Equal(tw.selected .. " " .. S[box.title].text, "layout LAYOUTS", "Layouts next")
    local cards = tw.pages.layout.cards
    Equal(Outlined() == cards[1] and S[box.outline].points[2][2] == cards[#cards], true, "outlining every preset")
    box.next:Click()
    Equal(tw.selected .. " " .. S[box.title].text, "look THE LOOK", "then the Look page")
    Equal(Outlined(), tw.lookOptions, "its choices")
    Equal(S[box.text].text:find("already has the new look", 1, true) ~= nil, true, "the look on: the Cooldown Manager has it")
    -- Only said when it's true: ticked but not reloaded yet, unticked, or
    -- unticked since login, the step says what happens.
    local function Again()
        box.back:Click()
        box.next:Click()
        return S[box.text].text
    end
    ns.loaded.skin = false
    Equal(Again():find("Reload to apply, and Blizzard's Cooldown Manager gets the new look.", 1, true), 1,
        "ticked but not reloaded: reload to apply")
    ns.Set("skin", false)
    Equal(Again():find("Tick Apply this look to the Cooldown Manager, then reload", 1, true), 1, "unticked: tick it, then reload")
    ns.loaded.skin = true
    local text = Again()
    Equal(tostring(text:find("goes back to its own look when you reload", 1, true) ~= nil) .. " " .. tostring(text:find("already has", 1, true)),
        "true nil", "unticked since login: it goes back to its own look at the next reload")
    ns.Set("skin", true)
    Equal(Again():find("already has the new look", 1, true) ~= nil and tw.selected .. " " .. S[box.title].text, "look THE LOOK",
        "ticked again: as before")
    box.next:Click()
    Equal(tw.selected .. " " .. S[box.title].text, "cast CAST BAR", "the Cast bar page")
    -- Both its ticks outlined as one part, with the box and its arrow under
    -- the swing timer's tick, never over it.
    local cp = tw.pages.cast
    local ticks = S[cp.ticks]
    Equal(Outlined() == cp.ticks and S[box.outline].points[2][2] == cp.ticks, true, "outlining both ticks")
    Equal(ticks.points[1][1] .. " " .. tostring(ticks.points[1][2] == cp.shown) .. " " .. ticks.points[2][1] .. " "
        .. tostring(ticks.points[2][2] == cp.swing) .. " " .. ticks.points[2][3] .. " " .. tostring(ticks.shown),
        "TOPLEFT true BOTTOMLEFT true BOTTOMLEFT true", "from the top of the cast bar's tick to the bottom of the swing timer's")
    Equal(S[cp.shown].width ~= S[cp.swing].width and ticks.width == math.max(S[cp.shown].width, S[cp.swing].width), true,
        "as wide as the wider tick")
    local swingBottom = S[cp.swing].points[1][3] - S[cp.swing].height
    local p = S[box].points[1]
    Equal(p[1] .. " " .. tostring(p[2] == cp.ticks) .. " " .. p[3] .. " " .. tostring(swingBottom + p[5] + 9 < swingBottom),
        "TOPLEFT true BOTTOMLEFT true", "the box and its arrow sit under the swing timer's tick")
    Equal(S[box.text].text:find("The second adds a swing timer", 1, true) ~= nil, true, "saying what the second tick is")
    box.next:Click()
    Equal(S[box.title].text .. " " .. Anchor(), "PROFILES TOPRIGHT BOTTOMRIGHT", "Profiles, the box lined up with its right end")
    Equal(Outlined(), tw.profileButton, "outlining the profile menu")
    -- Opened, the menu isn't covered: the box moves to its left, pointing at it.
    tw.profileButton:Click()
    Equal(tostring(S[tw.profilePanel].shown) .. " " .. Anchor() .. " " .. tostring(S[box].points[1][2] == tw.profilePanel)
        .. " " .. tostring(Outlined() == tw.profilePanel), "true TOPRIGHT TOPLEFT true true", "the menu open: the box beside it, outlining it")
    local arrow = S[box.arrow]
    Equal(tostring(arrow.shown) .. " " .. arrow.points[1][1] .. " " .. arrow.points[1][3] .. " "
        .. table.concat({ table.unpack(arrow.last.SetTexCoord, 1, 8) }, ","), "true LEFT TOPRIGHT 1,1,0,1,1,0,0,0",
        "its arrow on the right, facing the menu")
    tw.profileButton:Click()
    Equal(tostring(S[tw.profilePanel].shown) .. " " .. Anchor() .. " " .. tostring(Outlined() == tw.profileButton),
        "false TOPRIGHT BOTTOMRIGHT true", "closed again, the box goes back under the button")
    -- The menu already open as the step starts: beside it from the start.
    box.back:Click()
    tw.profileButton:Click()
    Equal(S[box.title].text .. " " .. Anchor(), "CAST BAR TOPLEFT BOTTOMLEFT", "other steps don't move for the menu")
    box.next:Click()
    Equal(S[box.title].text .. " " .. Anchor(), "PROFILES TOPRIGHT TOPLEFT", "the Profiles step starts beside the open menu")
    tw.profileButton:Click()
    Equal(Anchor(), "TOPRIGHT BOTTOMRIGHT", "and moves back as it closes")
    box.next:Click()
    Equal(S[box.count].text .. " " .. S[box.title].text, "9 of 9 THAT'S THE BASICS", "the last step")
    Equal(Outlined(), FECMMinimapButton, "pointing at the minimap button")
    Equal(S[box.text].text:find("with this button or /ccm", 1, true) ~= nil, true, "which opens these settings")
    Equal(S[box.next.label].text, "Done", "Done instead of Next")
    box.next:Click()
    Equal(S[box].shown, false, "Done ends the tour")
    Equal(S[tw].shown and S[tw.note].text, "That's the tour. Take the tour any time from the General page, or with /ccm tour.",
        "leaving the window open")
    Equal(ns.Get("useBars") and #ns.BarData("cd").spells, 1, "the tour only changed what you did yourself")

    -- Escape closes the window, ending the tour with it.
    tw:Select("general")
    tw.tour:Click()
    Equal(S[box].shown and S[box.title].text, "THE MENU", "Take the tour on the General page starts it again")
    CloseSpecialWindows()
    Equal(tostring(S[box].shown) .. " " .. tostring(S[tw].shown) .. " " .. tostring(ns.Tour:Active()), "false false false",
        "Escape closes the window and ends the tour")
    -- Closing the window ends it too.
    SlashCmdList.FECM("tour")
    tw.close:Click()
    SlashCmdList.FECM("")
    Equal(S[tw].shown and not S[box].shown, true, "closing the window ends the tour")

    -- With your bars already on, that step says so and waits for Next.
    SlashCmdList.FECM("tour")
    box.next:Click()
    Equal(S[box.text].text:find("They're already on.", 1, true) ~= nil, true, "a step already done says so")
    S[box].scripts.OnUpdate(box, 1)
    Equal(S[box.title].text, "SWITCH YOUR BARS ON", "and waits for Next")
    box.skip:Click()
    Equal(S[box].shown, false, "Skip tour ends it")

    -- Without the minimap button, the last step points at /ccm in the footer.
    tw:Select("general")
    tw.minimap:Click()
    Equal(ns.Get("minimap") == false and S[FECMMinimapButton].shown == false, true, "the General tick hides the minimap button")
    SlashCmdList.FECM("tour")
    for _ = 1, 8 do box.next:Click() end
    Equal(Outlined() == tw.versionText and Anchor() == "BOTTOMLEFT TOPLEFT", true, "without it, the last step points at the footer: Options > AddOns or /ccm")
    Equal(S[box.text].text:find("any time from Options > AddOns, or with /ccm.", 1, true) ~= nil, true, "and says so")
    box.next:Click()
    tw.minimap:Click()
    Equal(S[FECMMinimapButton].shown, true, "ticking it brings the button back")
end)()

-- What's new's tour: the steps an update added ------------------------------------------

-- In a function of its own: the main chunk is near Lua's limit of 200 locals.
;(function()
    -- No resource display here: each load would hook its bars' colours again,
    -- on top of every earlier load's, slowing every section after this one.
    -- Put back at the end.
    local display = _G.PersonalResourceDisplayFrame
    _G.PersonalResourceDisplayFrame = nil
    -- The version running: a release's from the TOC, or nil for a copy
    -- straight from the source ("dev").
    local function Running(version)
        _G.C_AddOns = version and { GetAddOnMetadata = function() return version end } or nil
    end
    local function Fresh(saved)
        Environment()
        _G.FECMFrame, _G.FECMTour, _G.FECMNotes = nil, nil, nil
        ns = Load(saved)
        for _, timer in ipairs(timers) do timer() end
    end
    local function Titles(list)
        local titles = {}
        for _, step in ipairs(list) do titles[#titles + 1] = step.title end
        return table.concat(titles, ", ")
    end
    local BASICS = "The menu, Switch your bars on, Add spells, This bar's options, Layouts, The look, Cast bar, Profiles, That's the basics"
    local NEW = "Keybinds on icons, Live preview, All bars"

    -- Versions, compared part by part as numbers.
    Running(nil)
    Fresh({ useBars = true, notesSeen = "dev" })
    local U = ns.UNRELEASED
    local function C(a, b) return tostring(ns.CompareVersions(a, b)) end
    Equal(table.concat({ C("1.0.0", "1.0.0"), C("1.1", "1.1.0"), C("1.10.0", "1.9.0"), C("1.0.1", "1.0.0"), C("1.9.9", "2.0"),
        C("v1.2.0", "1.2"), C("1.1.0-beta", "1.1.0"), C("2", "10") }, " "), "0 0 1 1 -1 0 0 -1",
        "versions compare part by part as numbers: 1.10 after 1.9, and a missing part is 0")
    Equal(U .. " " .. C(U, "1.0.0") .. " " .. C(U, "999.99.99") .. " " .. C("2.0.0", U) .. " " .. C(U, U), "Unreleased 1 1 -1 0",
        "the next update's placeholder comes after any release")
    Equal(C("dev", U) .. " " .. C("dev", "999.0") .. " " .. C("dev", "dev") .. " " .. C("1.0.0", "dev"), "1 1 0 -1",
        "and a copy straight from the source after that")
    Equal(table.concat({ C(nil, "1.0.0"), C("1.0.0", nil), C("", "1.0.0"), C("x", "1.0.0"), C(5, "1.0.0"), C({}, "dev"),
        C("Dev", "1.0.0") }, " "), "nil nil nil nil nil nil nil", "anything else isn't a version")

    -- Which steps: newer than the version seen, up to the one running.
    local Tour = ns.Tour
    -- 1.2.0's steps: after 1.1.0's in a copy from the source.
    local nextSteps = Tour:News("1.1.0")
    local NEXT = Titles(nextSteps)
    local TOTAL = 3 + #nextSteps -- from 1.0.0: 1.1.0's three, then the next update's
    Equal(NEXT:find("Healthstones and potions", 1, true) ~= nil and NEXT:find("Dim when ready", 1, true) ~= nil
        and nextSteps[1].version == "1.2.0", true,
        "1.2.0's steps, Healthstones and potions and Dim when ready among them")
    Equal(Titles(Tour:News("1.0.0")), NEW .. ", " .. NEXT, "from 1.0.0 to this copy: the three new steps, then the next update's")
    -- The newest steps there are: 1.5.0's. Here only Ready glow, on the Look page: the Cooldown pulse's
    -- page isn't loaded (Tools/TestPulse.lua tours its steps).
    local latest = {}
    for _, step in ipairs(nextSteps) do
        if step.version == "1.5.0" then latest[#latest + 1] = step end
    end
    local LATEST = Titles(latest)
    Equal(LATEST .. " | " .. tostring(NEXT:sub(-#LATEST) == LATEST), "Ready glow | true", "1.5.0's: Ready glow, the last of them")
    Equal(Titles(Tour:News(nil)) .. "|" .. Titles(Tour:News("nonsense")) .. "|" .. Titles(Tour:News("1.4.4")),
        LATEST .. "|" .. LATEST .. "|" .. LATEST,
        "no version seen, or one that isn't: the latest update's, the newest steps there are, as after 1.4.4")
    Equal(Titles(Tour:News("0.9.0")), BASICS .. ", " .. NEW .. ", " .. NEXT,
        "versions skipped come together: the basics from 1.0.0, then the new ones")
    Equal(Titles(Tour:News("dev")) .. "|" .. Titles(Tour:News(U)), "|", "nothing when nothing is newer than what was seen")
    -- Short and plain: no em dashes, and the new steps no longer than the basics'.
    local plain, basics, longest = true, 0, 0
    for _, step in ipairs(Tour:News("0.9.0")) do
        local text = type(step.text) == "function" and step.text() or step.text
        local already = type(step.alreadyText) == "function" and step.alreadyText() or step.alreadyText
        local all = text .. " " .. step.title .. " " .. (step.try or "") .. " " .. (already or "")
        if all:find("\226\128\148", 1, true) then plain = false end
        if step.version ~= "1.0.0" then longest = math.max(longest, #text) else basics = math.max(basics, #text) end
    end
    Equal(tostring(plain) .. " " .. tostring(longest > 0 and longest <= basics), "true true", "the steps are plain, the new ones short")
    Equal(Tour:News("0.9.0")[1].text(), "Everything is in this list: your four bars at the top, then Look, Layout, Cast bar and General.",
        "the menu step without a Raid Timers page (a full restart after updating) doesn't name it")
    local keybinds = ns.Keybinds
    ns.Keybinds = nil
    Equal(Titles(Tour:News("1.0.0")), "Live preview, All bars, " .. NEXT, "the keybinds step waits for its file (a full restart after updating)")
    ns.Keybinds = keybinds
    Running("1.0.0")
    Equal(Titles(Tour:News("0.9.0")) .. "|" .. Titles(Tour:News(nil)), BASICS .. "|" .. BASICS,
        "a release takes in steps up to itself; by hand, its own (so all nine are 1.0.0's)")
    Running("1.1.0")
    Equal(Titles(Tour:News("1.0.0")) .. "|" .. Titles(Tour:News(nil)), NEW .. "|" .. NEW,
        "1.1.0 numbered its steps: from 1.0.0 they show, and by hand too")
    -- An update after a release that adds no steps still offers the
    -- release's by hand, as the tour's Done and Skip say. The next update's,
    -- still waiting for their number, are in no release.
    Running("1.1.1")
    Equal(Titles(Tour:News(nil)) .. "|" .. Titles(Tour:News("1.0.0")) .. "|" .. Titles(Tour:News("1.1.0")), NEW .. "|" .. NEW .. "|",
        "1.1.1 with steps from 1.1.0: by hand those, from 1.0.0 those, from 1.1.0 nothing new")
    Running("1.1.0")
    local own = Titles(Tour:News(nil))
    Running("1.0.9")
    Equal(own .. "|" .. Titles(Tour:News(nil)), NEW .. "|" .. BASICS, "1.1.0 by hand its own; a release before it never a later one's")
    Running(nil)

    -- After an update: What's new offers the tour beside Got it.
    Fresh({ useBars = true, notesSeen = "1.0.0" })
    local notes = FECMNotes
    Equal(ns.NotesSeen() .. " " .. tostring(S[notes].shown) .. " " .. tostring(notes.seen), "dev true 1.0.0",
        "What's new after an update, knowing the version seen before it")
    Equal(tostring(S[notes.tour].shown) .. " " .. S[notes.tour.label].text, "true Show me what's new", "offering Show me what's new")
    Equal(S[notes.tour].points[1][1] .. " " .. S[notes.tour].points[1][3] .. " " .. S[notes.tour].points[1][4] .. " | "
        .. S[notes.discord].points[1][1] .. " " .. tostring(S[notes.discord].points[1][2] == notes.tour) .. " "
        .. S[notes.discord].points[1][4], "RIGHT LEFT -8 | RIGHT true -8", "beside Got it, the Discord button moving along for it")
    Equal(16 + S[notes.done].width + 8 + S[notes.tour].width + 8 + S[notes.discord].width, 332,
        "the three buttons leave the left 188 of the 520 for the two lines there")
    S[notes.tour].scripts.OnEnter(notes.tour)
    local tip = ns.Theme.tip
    Equal(tip and (S[tip.title].text .. "|" .. S[tip.text].text .. "|" .. tostring(S[tip].shown)),
        "SHOW ME WHAT'S NEW|A quick tour of what's new, a page at a time.|true",
        "its tooltip says what it does, in the window's own look")
    Equal(tostring(S[GameTooltip].shown), "false", "not Blizzard's tooltip")
    S[notes.tour].scripts.OnLeave(notes.tour)
    Equal(S[tip].shown, false, "gone as the mouse leaves")

    -- The tour: What's new closes, and the window opens on the first step.
    notes.tour:Click()
    local tw, box = FECMFrame, FECMTour
    Equal(tostring(S[notes].shown) .. " " .. tostring(S[tw].shown) .. " " .. tostring(S[box].shown), "false true true",
        "it closes What's new and opens the settings with the tour")
    Equal(S[box.count].text .. " " .. tw.selected .. " " .. S[box.title].text, "1 of " .. TOTAL .. " look KEYBINDS ON ICONS",
        "1.1.0's three steps and the next update's, the Look page's keybinds first")
    local outline = S[box.outline].points
    Equal(tostring(outline[1][2] == tw.keybinds) .. " " .. tostring(outline[2][2] == tw.keySize), "true true",
        "outlining from the Keybinds on icons tick down to the Size slider")
    -- The position pills sit inside that, and the box under it at its right end.
    local function Rect(frame)
        local p = S[frame].points[1]
        return p[2], p[3], p[2] + S[frame].width, p[3] - S[frame].height
    end
    local left, top = Rect(tw.keybinds)
    local _, _, right, bottom = Rect(tw.keySize)
    local l, t, r, b = Rect(tw.keyPlace)
    Equal(l >= left and t <= top and r <= right and b >= bottom and S[tw.keyPlace].parent == S[tw.keySize].parent, true,
        "the position pills inside it")
    local p = S[box].points[1]
    Equal(p[1] .. " " .. tostring(p[2] == tw.keySize) .. " " .. p[3] .. " " .. S[box.arrow].points[1][3], "TOPRIGHT true BOTTOMRIGHT TOPRIGHT",
        "the box under the Size slider at its right end, its arrow at that end")
    Equal(S[box.text].text:find("Try it: tick it.", 1, true) ~= nil and not S[box.back].shown, true,
        "asking you to tick it, with no Back on the first step")
    Equal(tostring(tw.keySize.usable) .. " " .. S[tw.keyPlace].alpha, "false 0.35", "the position and size greyed until it's ticked")
    tw.keybinds:Click()
    S[box].scripts.OnUpdate(box, 1)
    Equal(tostring(ns.Get("keybinds")) .. " " .. tw.selected .. " " .. S[box.title].text, "true look KEYBINDS ON ICONS",
        "ticked, the step stays for the position and size it asks you to pick")
    tw.keySize:Choose(120)
    S[box].scripts.OnUpdate(box, 1)
    Equal(tostring(tw.keySize.usable) .. " " .. S[tw.keyPlace].alpha .. " " .. ns.Get("keybindSize") .. " " .. S[box.title].text,
        "true 1 120 KEYBINDS ON ICONS", "which now work, and can be picked while it shows")
    tw.keySize:Choose(100)
    box.next:Click()
    local lp = tw.pages.layout
    Equal(tw.selected .. " " .. S[box.count].text .. " " .. S[box.title].text, "layout 2 of " .. TOTAL .. " LIVE PREVIEW",
        "Next moves on, to the Layout page's Live preview")
    p = S[box].points[1]
    local arrow = S[box.arrow].points[1]
    Equal(tostring(S[box.outline].points[1][2] == lp.live) .. " " .. p[1] .. " " .. tostring(p[2] == lp.live) .. " " .. p[3] .. " "
        .. p[4] .. " " .. p[5] .. " | " .. arrow[1] .. " " .. arrow[3] .. " " .. arrow[4],
        "true BOTTOMLEFT true TOPLEFT 0 14 | TOP BOTTOMLEFT 24",
        "outlining its tick, the box above it, the arrow down at it")
    -- The tick sits in the drawing's box, 12 in from its bottom left corner
    -- (the box starts 16 into the 638 page, 86 up from its foot): the box
    -- (290 across) over the drawing's foot, inside the page, and well above
    -- All bars under the drawing.
    local liveLeft = 16 + S[lp.live].points[1][2]
    local liveTop = 86 + S[lp.live].points[1][3] + S[lp.live].height
    Equal(tostring(S[lp.live].parent == lp.box) .. " " .. tostring(liveLeft + S[box].width <= 638 - 16) .. " "
        .. tostring(liveTop + 14 > 56 + S[lp.allBars].height), "true true true", "the box inside the page, clear above All bars")
    box.back:Click()
    Equal(tw.selected .. " " .. S[box.title].text, "look KEYBINDS ON ICONS", "Back goes back to the Look page")
    Equal(S[box.text].text:find("They're already on.", 1, true) ~= nil, true, "which now says they're on")
    S[box].scripts.OnUpdate(box, 1)
    Equal(S[box.title].text, "KEYBINDS ON ICONS", "and waits for Next")
    box.next:Click()
    box.next:Click()
    p = S[box].points[1]
    Equal(tw.selected .. " " .. S[box.count].text .. " " .. S[box.title].text .. " " .. S[box.next.label].text,
        "layout 3 of " .. TOTAL .. " ALL BARS Next", "then All bars, the last of 1.1.0's")
    Equal(tostring(S[box.outline].points[1][2] == lp.allBars) .. " " .. p[1] .. " " .. tostring(p[2] == lp.allBars) .. " " .. p[3],
        "true BOTTOMLEFT true TOPLEFT", "outlining the slider, the box above it")
    tw:Select("look")
    Equal(S[box].shown and not S[box.outline].shown, true, "on another page the outline hides, the box stays")
    -- Then the next update's steps, to Done. Healthstones and potions: the
    -- Cooldowns page's Show items tick, the box above it, clear of the list.
    local ahead = {}
    for _ = 4, TOTAL do
        box.next:Click()
        ahead[#ahead + 1] = S[box.title].text
        if S[box.title].text == "HEALTHSTONES AND POTIONS" then
            local bp = tw.pages.bar
            p = S[box].points[1]
            Equal(tw.selected .. " " .. tostring(S[box.outline].points[1][2] == bp.showItems) .. " " .. p[1] .. " "
                .. tostring(p[2] == bp.showItems) .. " " .. p[3] .. " " .. tostring(S[box.text].text:find("Try it: tick Show items.", 1, true) ~= nil),
                "cd true BOTTOMLEFT true TOPLEFT true", "Healthstones and potions: outlining Show items, the box above it, asking you to tick it")
            bp.showItems:Click()
            S[box].scripts.OnUpdate(box, 1)
            Equal(tostring(ns.Get("listItems")) .. " " .. S[box.title].text .. " " .. tostring(Row("family:healthstone") ~= nil),
                "true HEALTHSTONES AND POTIONS true", "ticked: Healthstones listed, the step staying so they can be seen")
        end
        -- Dim when ready: the Cooldowns page's When ready and its three
        -- choices as one part, the box under the buttons (not the shorter
        -- label), inside the page's right edge.
        if S[box.title].text == "DIM WHEN READY" then
            local ready = tw.pages.bar.options.whenReady
            local o = S[box.outline].points
            p = S[box].points[1]
            Equal(tw.selected .. " " .. tostring(o[1][2] == ready.part and o[2][2] == ready.part) .. " " .. p[1] .. " "
                .. tostring(p[2] == ready.part) .. " " .. p[3] .. " " .. tostring(S[box.text].text:find("Try it: pick Dim.", 1, true) ~= nil),
                "cd true TOPLEFT true BOTTOMLEFT true", "Dim when ready: outlining When ready and its choices, the box under them, asking you to pick Dim")
            -- The box hangs from the bottom the outline goes round, so its
            -- arrow's tip stops under the outline, as on the other steps.
            Equal(tostring(p[5] + S[box.arrow].height < o[2][5]) .. " " .. p[5] .. " " .. S[box.arrow].height .. " " .. o[2][5],
                "true -14 9 -4", "its arrow stops just under the outline, clear of it and the buttons")
            Equal(16 + S[ready.part].points[1][2] + S[box].width <= 638 - 8, true, "the box inside the page's right edge")
            ready.buttons[2]:Click()
            S[box].scripts.OnUpdate(box, 1)
            Equal(ns.BarData("cd").whenReady .. " " .. S[box.title].text, "dim DIM WHEN READY", "picked: the step stays so the bar can be seen dimming")
            ready.buttons[1]:Click()
        end
        -- Font and bar texture: both rows on the Look page as one part, the
        -- box under them at their right end, inside the page and below the
        -- preview at the top.
        if S[box.title].text == "FONT AND BAR TEXTURE" then
            local faces = tw.faces
            local o = S[box.outline].points
            p = S[box].points[1]
            Equal(tw.selected .. " " .. tostring(o[1][2] == faces and o[2][2] == faces) .. " " .. p[1] .. " " .. tostring(p[2] == faces)
                .. " " .. p[3] .. " " .. S[box.arrow].points[1][3] .. " "
                .. tostring(S[box.text].text:find("Try it: pick a font or a texture.", 1, true) ~= nil),
                "look true TOPRIGHT true BOTTOMRIGHT TOPRIGHT true",
                "Font and bar texture: outlining both rows, the box under them at their right end, asking you to pick one")
            local at = S[faces].points[1]
            Equal(tostring(16 + at[2] + S[faces].width <= 638 - 16 and 16 + at[2] + S[faces].width - S[box].width >= 16), "true",
                "the box inside the page, lined up with the Look page's right edge")
            tw.fontChoice.buttons[4]:Click()
            tw.fills[2]:Click()
            S[box].scripts.OnUpdate(box, 1)
            Equal(ns.Get("font") .. " " .. ns.Get("barTexture") .. " " .. S[box.title].text, "skurri classic FONT AND BAR TEXTURE",
                "picked: the step stays so others can be tried")
            tw.fontChoice.buttons[1]:Click()
            tw.fills[1]:Click()
        end
        -- Grow arrows: the Layout page's tick, the box above it, clear of
        -- Unlock bars, which it asks you to click next.
        if S[box.title].text == "GROW ARROWS" then
            local tick = lp.growArrows
            p = S[box].points[1]
            Equal(tw.selected .. " " .. tostring(S[box.outline].points[1][2] == tick) .. " " .. p[1] .. " " .. tostring(p[2] == tick)
                .. " " .. p[3] .. " " .. tostring(S[box.text].text:find("Try it: tick it, then Unlock bars.", 1, true) ~= nil),
                "layout true BOTTOMLEFT true TOPLEFT true", "Grow arrows: outlining its tick, the box above it, asking you to tick it and unlock")
            local unlockLeft = 638 - 16 - 12 - S[lp.home].width - 6 - S[lp.unlock].width
            Equal(S[tick].points[1][2] + S[box].width <= unlockLeft - 8, true, "the box clear of Unlock bars")
            tick:Click()
            lp.unlock:Click()
            S[box].scripts.OnUpdate(box, 1)
            Equal(tostring(ns.Get("growArrows")) .. " " .. tostring(ns.Bars:Get("cd").arrows:IsVisible()) .. " " .. S[box.title].text,
                "true true GROW ARROWS", "ticked and unlocked: arrows on your bars, the step staying so they can be seen")
            lp.unlock:Click()
            tick:Click()
        end
        -- Ready glow: the Look page's foot, its label and choices as one
        -- part, the box above them at their right end, inside the page.
        if S[box.title].text == "READY GLOW" then
            local glow = tw.readyGlow
            local o = S[box.outline].points
            p = S[box].points[1]
            Equal(tw.selected .. " " .. tostring(o[1][2] == glow.part and o[2][2] == glow.part) .. " " .. p[1] .. " "
                .. tostring(p[2] == glow.part) .. " " .. p[3] .. " " .. S[box.arrow].points[1][3] .. " "
                .. tostring(S[box.text].text:find("Try it: pick Gold edge.", 1, true) ~= nil),
                "look true BOTTOMRIGHT true TOPRIGHT BOTTOMRIGHT true",
                "Ready glow: outlining its label and choices, the box above them at their right end, asking you to pick Gold edge")
            local part = S[glow.part].points[1]
            local right, bottom = 638 + part[2], -part[3]
            Equal(tostring(right - S[box].width >= 16) .. " " .. tostring(right <= 638 - 16) .. " " .. tostring(bottom + S[glow.part].height
                + p[5] + S[box].height <= 489), "true true true", "the box inside the page, above the foot")
            glow.buttons[2]:Click()
            S[box].scripts.OnUpdate(box, 1)
            Equal(ns.Get("readyGlow") .. " " .. S[box.title].text, "edge READY GLOW", "picked: the step stays so it can be seen")
            glow.buttons[1]:Click()
        end
    end
    Equal(table.concat(ahead, ", ") .. " " .. S[box.next.label].text, NEXT:upper() .. " Done", "then the next update's steps, the last one Done")
    box.next:Click()
    Equal(tostring(S[box].shown) .. " " .. tostring(S[tw].shown) .. " " .. S[tw.note].text,
        "false true That's what's new. See it again any time from What's new, or with /ccm new.",
        "Done ends it, leaving the window open and saying where it is")
    Equal(ns.Get("barScale") .. " " .. tostring(ns.Get("layoutPreview")) .. " " .. tostring(ns.Get("keybinds")), "100 true true",
        "the tour only changed what you did yourself")

    -- Opened by hand: the latest update's steps. Escape closes What's new
    -- and the window at once, ending the tour.
    SlashCmdList.FECM("new")
    Equal(tostring(S[notes].shown) .. " " .. tostring(notes.seen) .. " " .. tostring(S[notes.tour].shown), "true nil true",
        "/ccm new offers it too")
    notes.tour:Click()
    Equal(S[box.count].text .. " " .. S[box.title].text, "1 of " .. #latest .. " " .. latest[1].title:upper(),
        "the next update's steps, the newest there are")
    tw.news:Click()
    Equal(tostring(S[notes].shown) .. " " .. tostring(S[box].shown), "true true", "What's new opened over the tour")
    CloseSpecialWindows()
    Equal(tostring(S[notes].shown) .. " " .. tostring(S[box].shown) .. " " .. tostring(S[tw].shown) .. " " .. tostring(ns.Tour:Active()),
        "false false false false", "Escape closes What's new and the window, ending the tour")
    -- Skip tour ends it too, and says where it is.
    tw.news:Click()
    notes.tour:Click()
    if #latest > 1 then box.next:Click() end -- a step past the first, where there is one
    box.skip:Click()
    Equal(tostring(S[box].shown) .. " " .. S[tw.note].text, "false See it again any time from What's new, or with /ccm new.",
        "Skip tour ends it, saying where to see it again")
    -- The full tour is still the basics, and says its own.
    SlashCmdList.FECM("tour")
    Equal(S[box.count].text .. " " .. S[box.title].text, "1 of 9 THE MENU", "the full tour is still the nine basics")
    box.skip:Click()
    Equal(S[tw.note].text, "Take the tour any time from the General page, or with /ccm tour.", "and Skip tour says where it is")
    SlashCmdList.FECM("tour")
    for _ = 1, 9 do box.next:Click() end
    Equal(S[tw.note].text, "That's the tour. Take the tour any time from the General page, or with /ccm tour.", "as Done does")

    -- Versions skipped: every newer step in one tour.
    Fresh({ useBars = true, notesSeen = "0.9.0" })
    FECMNotes.tour:Click()
    box = FECMTour
    local titles = { S[box.title].text }
    for _ = 2, 9 + TOTAL do
        FECMTour.next:Click()
        titles[#titles + 1] = S[box.title].text
    end
    Equal(S[box.count].text .. " " .. table.concat(titles, ", "),
        (9 + TOTAL) .. " of " .. (9 + TOTAL) .. " " .. BASICS:upper() .. ", " .. NEW:upper() .. ", " .. NEXT:upper(),
        "from 0.9.0: the basics, then what's new since, in one tour")

    -- An update with no new steps: no button, Discord back beside Got it,
    -- and nothing to start. Opened by hand, it still offers the last ones.
    Running("1.1.1")
    Fresh({ useBars = true, notesSeen = "1.1.0" })
    notes = FECMNotes
    Equal(tostring(S[notes].shown) .. " " .. tostring(S[notes.tour].shown) .. " " .. tostring(S[notes.discord].points[1][2] == notes.done),
        "true false true", "an update with no new steps: What's new without the button, Discord beside Got it")
    notes:Hide()
    ns.Tour:StartNews("1.1.0")
    Equal(FECMFrame == nil and FECMTour == nil, true, "and no tour starts: the settings don't even open")
    SlashCmdList.FECM("new")
    Equal(tostring(S[notes.tour].shown) .. " " .. tostring(S[notes.discord].points[1][2] == notes.tour), "true true",
        "opened by hand, the last update's steps are still offered, as the tour's Done and Skip say")
    notes.tour:Click()
    Equal(S[FECMTour.count].text .. " " .. S[FECMTour.title].text, "1 of 3 KEYBINDS ON ICONS", "here 1.1.0's, the three new ones")
    FECMTour.skip:Click()
    Running(nil)

    -- A first install still has the welcome and the full tour, and no What's new.
    Fresh(nil)
    box = FECMTour
    Equal(S[box.title].text .. " " .. tostring(FECMNotes == nil), "WELCOME true", "a first install: the welcome, no What's new")
    box.next:Click()
    titles = { S[box.title].text }
    while S[box.next.label].text ~= "Done" and #titles < 20 do
        box.next:Click()
        titles[#titles + 1] = S[box.title].text
    end
    Equal(S[box.count].text .. " " .. table.concat(titles, ", "), "9 of 9 " .. BASICS:upper(), "Take the tour: the nine basics, unchanged")
    Equal(#printed, 0, "no errors")
    _G.PersonalResourceDisplayFrame = display
end)()

-- The minimap button --------------------------------------------------------------------

do
    Environment()
    _G.FECMFrame = nil
    ns = Load({ useBars = true })
    local mm = FECMMinimapButton
    local function At() local p = S[mm].points[1]; return string.format("%s %.1f %.1f", p[1], p[4], p[5]) end
    Equal(S[mm].shown and S[mm].parent == Minimap, true, "a minimap button, on by default")
    Equal(At(), "CENTER -52.3 -52.3", "at the minimap's bottom left, just outside its edge")
    S[GameTooltip].lines = nil
    S[mm].scripts.OnEnter(mm)
    local tip = ns.Theme.tip
    Equal(S[tip.title].text .. "|" .. S[tip.text].text .. "|" .. tostring(S[tip].shown) .. "|" .. S[tip].points[1][1] .. " "
        .. tostring(S[tip].points[1][2] == mm) .. " " .. S[tip].points[1][3],
        ns.TITLE:upper() .. "|Click: settings\nRight-click: What's new\nDrag: move it round the minimap|true|TOPRIGHT true BOTTOMRIGHT",
        "its tooltip says what it does, the addon's own, under the button")
    -- Never the game's tooltip: an addon writing into it taints it, and in
    -- Forever it then breaks on your hidden health every frame (thousands
    -- of errors, 2026-10-06).
    Equal(tostring(S[GameTooltip].lines) .. " " .. tostring(S[GameTooltip].shown), "nil false", "Blizzard's tooltip untouched")
    S[mm].scripts.OnLeave(mm)
    Equal(S[tip].shown, false, "gone as the mouse leaves")
    S[mm].scripts.OnClick(mm, "LeftButton")
    Equal(FECMFrame ~= nil and S[FECMFrame].shown, true, "click: the settings")
    S[mm].scripts.OnClick(mm, "LeftButton")
    Equal(S[FECMFrame].shown, false, "and again to close them")
    S[mm].scripts.OnClick(mm, "RightButton")
    Equal(FECMNotes ~= nil and S[FECMNotes].shown, true, "right-click: What's new")
    FECMNotes:Hide()
    -- Dragging: it follows the cursor round the edge, saved where it's let go.
    S[mm].scripts.OnDragStart(mm)
    Equal(mm.isMoving, true, "flagged while it's dragged, so a minimap tidier (EraUI's) doesn't fade it")
    _G.GetCursorPosition = function() return 900, 800 end
    S[mm].scripts.OnUpdate(mm, .01)
    Equal(At() .. " " .. ns.Get("minimapAngle"), "CENTER 0.0 74.0 225", "following the cursor")
    S[mm].scripts.OnDragStop(mm)
    Equal(ns.Get("minimapAngle") .. " " .. At() .. " " .. tostring(mm.isMoving), "90 CENTER 0.0 74.0 nil", "saved where it's let go")
    Equal(ForeverEnhancedCooldownManagerDB.minimapAngle, 90, "in the saved settings")
    S[mm].scripts.OnClick(mm, "LeftButton")
    Equal(S[FECMFrame].shown, false, "letting go isn't a click")
    clock = clock + 1
    S[mm].scripts.OnClick(mm, "LeftButton")
    Equal(S[FECMFrame].shown, true, "a click after that is")
    S[Minimap].width = 200
    S[Minimap].scripts.OnSizeChanged(Minimap)
    Equal(At(), "CENTER 0.0 104.0", "a bigger minimap: still on its edge")
    Equal(ns.Valid("minimapAngle", 360), false, "angles stay within a turn")
    -- Hidden mid-drag, it's let go there and doesn't trail the cursor later.
    S[mm].scripts.OnDragStart(mm)
    _G.GetCursorPosition = function() return 800, 700 end
    S[mm].scripts.OnUpdate(mm, .01)
    mm:Hide()
    Equal(ns.Get("minimapAngle") .. " " .. tostring(S[mm].scripts.OnUpdate) .. " " .. tostring(mm.isMoving), "180 nil nil",
        "hidden mid-drag, it's let go where it was")
    mm:Show()
    S[mm].scripts.OnDragStart(mm)
    _G.GetCursorPosition = function() return 900, 800 end
    S[mm].scripts.OnUpdate(mm, .01)
    S[mm].scripts.OnDragStop(mm)
    local saved = ForeverEnhancedCooldownManagerDB
    Environment(true)
    ns = Load(saved)
    local p = S[FECMMinimapButton].points[1]
    Equal(string.format("%.1f %.1f", p[4], p[5]), "0.0 74.0", "where you left it after a reload")
end

-- Free-floating (the General page): anywhere on the screen, held by the
-- screen itself so it shows with the minimap hidden, kept where it's dropped.
do
    Environment()
    _G.FECMFrame = nil
    ns = Load({ useBars = true })
    local mm = FECMMinimapButton
    local function At()
        local p = S[mm].points[1]
        local to = p[2] == UIParent and "screen" or p[2] == Minimap and "minimap" or "?"
        return string.format("%s %s %.1f %.1f", p[1], to, p[4], p[5])
    end
    Equal(tostring(ns.Get("minimapFree")) .. " " .. tostring(Last(mm, "SetParent") == Minimap), "false true",
        "on the minimap by default")
    SlashCmdList.FECM("")
    local w = FECMFrame
    w:Select("general")
    Equal(w.minimapFree:GetChecked(), false, "the General tick, off by default")
    S[mm].cx, S[mm].cy = 847.7, 647.7 -- where it is on the minimap now
    w.minimapFree:Click()
    Equal(tostring(ns.Get("minimapFree")) .. " " .. tostring(Last(mm, "SetParent") == UIParent) .. " " .. At(),
        "true true CENTER screen 348.0 248.0", "ticked: held by the screen, just where it was")
    Equal(w.minimapFree:GetChecked(), true, "the tick shows it")
    S[mm].scripts.OnEnter(mm)
    Equal(S[ns.Theme.tip.text].text, "Click: settings\nRight-click: What's new\nDrag: move it anywhere", "its tooltip says so")
    S[mm].scripts.OnLeave(mm)
    S[mm].scripts.OnDragStart(mm)
    _G.GetCursorPosition = function() return 600, 450 end
    S[mm].scripts.OnUpdate(mm, .01)
    Equal(At(), "CENTER screen 100.0 50.0", "dragged anywhere, following the cursor")
    S[mm].scripts.OnDragStop(mm)
    local db = ForeverEnhancedCooldownManagerDB
    Equal(db.minimapX .. " " .. db.minimapY .. " " .. ns.Get("minimapAngle"), "100 50 225",
        "saved where it's dropped, its minimap spot kept")
    S[Minimap].scripts.OnSizeChanged(Minimap)
    Equal(At(), "CENTER screen 100.0 50.0", "a minimap resize leaves it be")
    Equal(tostring(ns.Valid("minimapX", 5000)) .. " " .. tostring(ns.Valid("minimapY", -12)), "false true", "places stay sensible")
    -- Unticked: back on the minimap's edge, where it was before; ticked again,
    -- it stays where it is.
    w.minimapFree:Click()
    Equal(tostring(ns.Get("minimapFree")) .. " " .. tostring(Last(mm, "SetParent") == Minimap) .. " " .. At(),
        "false true CENTER minimap -52.3 -52.3", "unticked: back on the minimap, where it was")
    S[mm].cx, S[mm].cy = 447.7, 347.7
    w.minimapFree:Click()
    Equal(At(), "CENTER screen -52.0 -52.0", "ticked again: from where it sits now")
    -- As it loads with the choice saved: held by the screen, where it was left.
    S[mm].last.SetParent = nil
    ns.MinimapButton:Apply()
    Equal(tostring(Last(mm, "SetParent") == UIParent) .. " " .. At(), "true CENTER screen -52.0 -52.0", "loaded free-floating")
end

-- The Discord: found a bug or have an idea ---------------------------------------------

do
    Environment()
    _G.FECMFrame, _G.FECMCopyLink = nil, nil
    ns = Load({ useBars = true })
    SlashCmdList.FECM("")
    local tw = FECMFrame
    tw:Select("general")
    tw.discord:Click()
    local box = FECMCopyLink
    Equal(S[box].shown and S[box.title].text .. " " .. S[box.input].text, "JOIN THE DISCORD https://discord.gg/FVfcDWJncr",
        "the General page gives the Discord invite, ready to copy")
    Equal(S[box.note].text:find("Found a bug or have an idea?", 1, true) ~= nil, true, "saying what it is for")
    box.close:Click()
    SlashCmdList.FECM("discord")
    Equal(S[box].shown, true, "/ccm discord does too")
    box.close:Click()
    SlashCmdList.FECM("new")
    local notes = FECMNotes
    Equal(S[notes.ask].text, "Found a bug or have an idea?", "What's new asks")
    Equal(tostring(S[notes.discord].points[1][2] == notes.tour) .. " " .. tostring(S[notes.tour].points[1][2] == notes.done),
        "true true", "with a Discord button by Got it, past Show me what's new")
    notes.discord:Click()
    Equal(S[box].shown, true, "which gives the invite")
end

-- Keybinds on your icons ------------------------------------------------------------------

-- In a function of its own: the main chunk is near Lua's limit of 200 locals.
(function()
    -- The spells and items the action bars below hold.
    local function Names()
        local spellName, itemSpell = C_Spell.GetSpellName, C_Item.GetItemSpell
        local extra = { [8921] = "Moonfire", [8924] = "Moonfire", [5176] = "Wrath", [7384] = "Overpower" }
        C_Spell.GetSpellName = function(id) return extra[id] or spellName(id) end
        C_Item.GetItemSpell = function(id)
            if id == 118 then return "Healing Potion", 441 end
            return itemSpell(id)
        end
    end
    -- Runs every timer queued so far, and any they queue.
    local function Flush()
        for _ = 1, 5 do
            local list = timers
            timers = {}
            for _, timer in ipairs(list) do timer() end
            if #timers == 0 then return end
        end
    end
    local function At(region)
        local p = S[region].points[1]
        return p[1] .. " " .. p[3] .. " " .. p[4] .. " " .. p[5]
    end

    Environment()
    local K = ns.Keybinds
    -- The keys as action bars show them, from the raw key.
    local shown = {}
    for _, raw in ipairs({ "1", "SHIFT-2", "CTRL-3", "ALT-4", "BUTTON4", "SHIFT-BUTTON5", "ALT-CTRL-SHIFT-Q",
        "CTRL-MOUSEWHEELDOWN", "NUMPAD5", "NUMPADPLUS", "SPACE", "SHIFT--" }) do
        shown[#shown + 1] = K:Format(raw)
    end
    Equal(table.concat(shown, " "), "1 S2 C3 A4 M4 SM5 ACSQ CWD N5 N+ Sp S-", "keys shortened as action bars show them")
    Equal(tostring(K:Format(nil)) .. " " .. tostring(K:Format("PADLTRIGGER")) .. " " .. tostring(K:Format(SECRETS.string)), "nil nil nil",
        "nothing for no key, a gamepad button or a secret")

    -- Off by default: nothing is read and no timer is queued.
    Names()
    actionSlots[1], keyOf.ACTIONBUTTON1 = { "spell", 8924 }, "1"
    ns = Load({ useBars = true, notesSeen = "dev" })
    B, K = ns.Bars, ns.Keybinds
    B:Assign("Moonfire", "cd")
    Flush()
    Fire("ACTIONBAR_SLOT_CHANGED", 1)
    Fire("UPDATE_BINDINGS")
    local queued = #timers
    Flush()
    Equal(actionReads .. " " .. queued, "0 0", "off by default: no action bar read, no timer queued")
    Equal(S[B:Get("cd").icons[1].key].shown, false, "and no key on the icon")

    -- On: read once the action bars settle after login.
    Environment()
    Names()
    actionSlots[1], keyOf.ACTIONBUTTON1 = { "spell", 8924 }, "1"
    ns = Load({ useBars = true, keybinds = true, notesSeen = "dev" })
    B, K = ns.Bars, ns.Keybinds
    B:Assign("Moonfire", "cd")
    B:Assign("Wrath", "cd")
    B:Assign("Overpower", "cd")
    local moon, wrath, over = B:Get("cd").icons[1], B:Get("cd").icons[2], B:Get("cd").icons[3]
    local key = moon.key
    Equal(tostring(S[key].shown) .. " " .. actionReads, "false 0", "on: nothing read until the action bars settle")
    Flush()
    Equal(actionReads, K.SLOTS, "then every slot read once")
    Equal(S[key].text .. " " .. tostring(S[key].shown), "1 true", "Moonfire shows the key that casts it")
    Equal(At(key) .. " " .. tostring(S[key].points[1][2] == moon), "BOTTOM BOTTOM 0 2 true", "along the bottom of the icon")
    Equal(Last(key, "SetFontObject") .. " " .. S[key].width .. " " .. Last(key, "SetJustifyH") .. " " .. S[key].colour[1],
        "FECMFont11 32 CENTER 0.9", "sized to the icon, one line across its art, near white")
    Equal(S[key].parent == moon.top, true, "above the sweep, with the count")

    -- Ranks: any rank in the slot counts for the spell; a fixed rank only its own.
    actionSlots[1] = { "spell", 8921 }
    K:Update()
    Equal(S[key].text, "1", "rank 1 in the slot still counts for Moonfire")
    ns.Set("listRanks", true)
    B:Assign("Moonfire@1", "util")
    local fixed = B:Get("util").icons[1]
    Equal(S[fixed.key].text .. " " .. tostring(S[fixed.key].shown), "1 true", "a fixed rank shows the key for that rank")
    actionSlots[1] = { "spell", 8924 }
    K:Update()
    Equal(tostring(S[fixed.key].shown) .. " " .. S[key].text, "false 1", "but not the key for another rank")

    -- A spell in several slots: the main bar first, a macro last.
    actionSlots[61], keyOf.MULTIACTIONBAR1BUTTON1 = { "spell", 8924 }, "SHIFT-1"
    K:Update()
    Equal(S[key].text, "1", "in two slots: the main bar's key")
    actionSlots[1] = nil
    K:Update()
    Equal(S[key].text, "S1", "and the side bar's once it's gone from there")
    actionSlots[62], keyOf.MULTIACTIONBAR1BUTTON2 = { "macro", 5176, "spell" }, "SHIFT-2"
    K:Update()
    Equal(S[wrath.key].text, "S2", "a macro showing a spell gives it its key")
    actionSlots[50], keyOf.MULTIACTIONBAR2BUTTON2 = { "spell", 5176 }, "CTRL-2"
    K:Update()
    Equal(S[wrath.key].text, "C2", "but the spell placed directly wins, even on a later bar")

    -- A form change in a fight: the main bar's keys press its form page at once.
    actionSlots[1], actionSlots[61], actionSlots[85] = { "spell", 8924 }, nil, { "spell", 5176 }
    K:Update()
    Equal(S[key].text .. " " .. S[wrath.key].text, "1 C2", "the main bar's first page to start with")
    local reads = actionReads
    lockdown = true
    bonusIndex = 8
    Settle("UPDATE_BONUS_ACTIONBAR")
    Equal(S[wrath.key].text .. " " .. tostring(S[key].shown), "1 false", "in a fight, a form's page: its keys on the next frame")
    Equal(actionReads, reads, "from what was read before the fight")
    bonusIndex = nil
    Settle("UPDATE_BONUS_ACTIONBAR")
    Equal(S[key].text .. " " .. S[wrath.key].text, "1 C2", "and back")

    -- A slot changed in a fight is read once it's over.
    actionSlots[2], keyOf.ACTIONBUTTON2 = { "spell", 7384 }, "2"
    Fire("ACTIONBAR_SLOT_CHANGED", 2)
    Equal(tostring(K.pending) .. " " .. tostring(S[over.key].shown) .. " " .. actionReads, "true false " .. reads,
        "a slot changed in a fight waits")
    lockdown = false
    Fire("PLAYER_REGEN_ENABLED")
    Equal(S[over.key].text .. " " .. tostring(S[over.key].shown) .. " " .. tostring(K.pending), "2 true nil", "and shows once it's over")

    -- A burst of changes is read once.
    queued, reads = #timers, actionReads
    for _ = 1, 5 do Fire("ACTIONBAR_SLOT_CHANGED", 3) end
    Equal(#timers - queued, 1, "five slot changes queue one read")
    Flush()
    Equal(actionReads - reads, K.SLOTS, "which reads every slot once")

    -- Unbound: no key.
    keyOf.ACTIONBUTTON2 = nil
    Fire("UPDATE_BINDINGS")
    Flush()
    Equal(tostring(S[over.key].shown) .. " [" .. S[over.key].text .. "]", "false []", "a key unbound: none shown")

    -- Items: a potion, by itself or in a macro; a trinket by what's equipped.
    local function Icon(name)
        for _, icon in ipairs(B:Get("cd").icons) do
            if icon.name == name and S[icon].shown then return icon end
        end
    end
    bagItems = { { itemID = 118, hyperlink = "|cffffffff|Hitem:118|h[Minor Healing Potion]|h|r", iconFileID = 888 } }
    trinket, ammo, ammoCount = 5079, 2512, 200
    itemCount[118] = 3
    -- Ammo shows for a class that uses it; the druid's proc is kept to ask about.
    local clearcasting = ns.Spells:Find("Clearcasting")
    _G.UnitClass = function() return "Hunter", "HUNTER" end
    B:Rebuild()
    B:Assign("item:118", "cd") -- the potion on its own, ticked in the list
    B:AddItem("cd", 5079)
    B:Assign("ammo", "cd")
    actionSlots[3], keyOf.ACTIONBUTTON3 = { "item", 118 }, "3"
    actionSlots[5], keyOf.ACTIONBUTTON5 = { "item", 5079 }, "5"
    actionSlots[6], keyOf.ACTIONBUTTON6 = { "spell", 16870 }, "6"
    actionSlots[7], keyOf.ACTIONBUTTON7 = { "item", 2512 }, "7"
    K:Update()
    Equal(S[Icon("item:118").key].text, "3", "a bag item shows its slot's key")
    Equal(K:ForSpell(441), "3", "and Blizzard's icon for it finds it by its use spell")
    actionSlots[3], macroItems[7] = { "macro", 7, "" }, 118
    K:Update()
    Equal(S[Icon("item:118").key].text .. " " .. tostring(S[Icon("item:118").key].shown), "3 true", "as does a macro that uses it")
    Equal(S[Icon("slot:13").key].text, "5", "a trinket shows the key for what's equipped")
    Equal(tostring(K:ForEntry(ns.Spells:Find("ammo"))) .. " " .. tostring(clearcasting and clearcasting.kind) .. " "
        .. tostring(K:ForEntry(clearcasting)) .. " " .. tostring(S[Icon("ammo").key].shown), "nil proc nil false",
        "ammunition and procs have nothing to press")
    -- A key along the bottom only moves the count up on an icon that shows one.
    local potion, quiver = Icon("item:118"), Icon("ammo")
    Equal(At(potion.count) .. " | " .. At(quiver.count), "TOPRIGHT TOPRIGHT -1 -1 | BOTTOMRIGHT BOTTOMRIGHT -1 1",
        "the potion's count moves up clear of its key; the ammo's, with no key, stays at the bottom")
    keyOf.ACTIONBUTTON3 = nil
    Fire("UPDATE_BINDINGS")
    Flush()
    Equal(tostring(S[potion.key].shown) .. " " .. At(potion.count), "false BOTTOMRIGHT BOTTOMRIGHT -1 1",
        "its key unbound: the potion's count comes back down at once")
    keyOf.ACTIONBUTTON3 = "3"
    Fire("UPDATE_BINDINGS")
    Flush()
    Equal(S[potion.key].text .. " " .. At(potion.count) .. " | " .. At(quiver.count),
        "3 TOPRIGHT TOPRIGHT -1 -1 | BOTTOMRIGHT BOTTOMRIGHT -1 1", "bound again: up again, and the ammo's stays put")
    _G.UnitClass = function() return "Druid", "DRUID" end
    -- A healthstone family: the key for the one it shows, else for any rank
    -- on your bars, the best first; a new key as soon as it moves on.
    actionSlots[8], keyOf.ACTIONBUTTON8 = { "item", 9421 }, "8"
    actionSlots[10], keyOf.ACTIONBUTTON10 = { "item", 5511 }, "0"
    K:Update()
    itemCount[19004] = 1
    B:Assign("family:healthstone", "cd")
    local stone = Icon("family:healthstone")
    Equal(stone.itemID .. " " .. S[stone.key].text .. " " .. tostring(S[stone.key].shown), "19004 8 true",
        "one with no key of its own: the Major Healthstone's key, the best rank on your bars")
    actionSlots[9], keyOf.ACTIONBUTTON9 = { "item", 5512 }, "9"
    K:Update()
    itemCount[5512] = 1
    Fire("BAG_UPDATE_DELAYED")
    Equal(stone.itemID .. " " .. S[stone.key].text, "5512 9", "a Minor one made: its own key, as soon as your bags change")
    itemCount[5512], itemCount[19004] = 0, 0
    B:TakeOff("cd", "family:healthstone")
    actionSlots[8], actionSlots[9], actionSlots[10] = nil, nil, nil
    K:Update()
    -- The main bar paged in a fight: text and the addon's own anchors only.
    lockdown = true
    bonusIndex = 8
    Settle("UPDATE_BONUS_ACTIONBAR")
    Equal(tostring(S[potion.key].shown) .. " " .. At(potion.count), "false BOTTOMRIGHT BOTTOMRIGHT -1 1",
        "a form's page in a fight takes the potion's key away: its count follows on the next frame")
    bonusIndex = nil
    Settle("UPDATE_BONUS_ACTIONBAR")
    lockdown = false
    Equal(At(potion.count), "TOPRIGHT TOPRIGHT -1 -1", "and back")
    B:SetAura("buff", "Thorns", true)
    Equal(B:Get("buff").holders[1].key, nil, "the Buffs bar's icons show auras, so get no key")

    -- Room for the key on your icon at 36: the count and countdown move clear.
    B:Clear("cd")
    B:Assign("Moonfire", "cd")
    moon = B:Get("cd").icons[1]
    key = moon.key
    local numbers = S[moon.cooldown].numbers
    Equal(At(moon.count) .. " | " .. At(numbers), "TOPRIGHT TOPRIGHT -1 -1 | CENTER CENTER 0 0",
        "a key along the bottom: the count goes top right, the countdown stays")
    Equal(S[moon.count].points[1][2] == moon and S[numbers].points[1][2] == moon.cooldown, true, "on the icon and its sweep")
    ns.Set("keybindPosition", "TOPRIGHT")
    ns.Set("keybindSize", 150)
    B:ApplyKeybinds()
    Equal(Last(key, "SetFontObject") .. " " .. At(key) .. " " .. Last(key, "SetJustifyH"), "FECMFont16 TOPRIGHT TOPRIGHT -2 -2 RIGHT",
        "top right, half as big again")
    Equal(At(moon.count) .. " | " .. At(numbers), "BOTTOMRIGHT BOTTOMRIGHT -1 1 | CENTER CENTER 0 -4",
        "the count back home, the countdown moved down clear of the key")
    ns.Set("keybindPosition", "BOTTOM")
    ns.Set("keybindSize", 100)
    B:SetOption("cd", "size", 20)
    Equal(At(numbers), "CENTER CENTER 0 4", "a small icon: the countdown moves up clear of a key along the bottom")
    ns.Set("keybinds", false)
    B:ApplyKeybinds()
    Equal(At(moon.count) .. " | " .. At(numbers) .. " " .. tostring(S[key].shown), "BOTTOMRIGHT BOTTOMRIGHT -1 1 | CENTER CENTER 0 0 false",
        "off: no key, and the count and countdown back home")
    Equal(#printed, 0, "no errors from keybinds")

    -- Every icon size, position and key size: the key fits the icon and clears
    -- the countdown, which stays inside it.
    local Style, bad, cases = ns.Style, {}, { { 46, 25 }, { 26, 15 }, { 26, 13 } }
    for size = 20, 64 do cases[#cases + 1] = { size, Style:CountdownSize(size) } end
    for _, case in ipairs(cases) do
        local art, c = case[1], case[2]
        for _, position in ipairs(ns.KEYBIND_POSITIONS) do
            for scale = 50, 150, 10 do
                local size, lift = Style:KeyFit(art, c, position, scale)
                local up = math.abs(lift)
                local fits = size >= 8 and 2 + .75 * size <= art and 2 + .75 * size + 1 <= art / 2 - .75 * c / 2 + up
                    and art / 2 + .75 * c / 2 + up <= art and (lift == 0 or (position == "BOTTOM") == (lift > 0))
                if not fits then bad[#bad + 1] = art .. "/" .. c .. "/" .. position .. "/" .. scale .. " " end
            end
        end
    end
    for art = 36, 64 do
        local _, lift = Style:KeyFit(art, Style:CountdownSize(art), "BOTTOM", 100)
        if lift ~= 0 then bad[#bad + 1] = "moved at " .. art .. " " end
    end
    Equal(table.concat(bad), "", "every key fits its icon, clear of the countdown; from 36 up nothing moves")
    local function Fit(...)
        local size, lift = Style:KeyFit(...)
        return size .. "," .. lift
    end
    Equal(table.concat({ Fit(36, 18, "BOTTOM", 100), Fit(36, 18, "TOPRIGHT", 150), Fit(20, 11, "BOTTOM", 100),
        Fit(64, 32, "BOTTOM", 150), Fit(46, 25, "BOTTOM", 100), Fit(26, 15, "BOTTOM", 100) }, " "),
        "11,0 16,-4 8,4 29,5 14,0 8,2", "your icons and Blizzard's Essential and Utility rows")
    Equal((Style:KeyFit(26, 13, "TOP", 100)) .. " " .. (Style:KeyFit(26, 13, "TOPLEFT", 150)), "8 12", "and the Look page's preview")

    -- The Look page: a tick, where on the icon and how big, shown live.
    Environment()
    Names()
    actionSlots[1], keyOf.ACTIONBUTTON1 = { "spell", 8924 }, "1"
    _G.FECMFrame = nil
    ns = Load({ useBars = true, notesSeen = "dev" })
    B, K = ns.Bars, ns.Keybinds
    B:Assign("Moonfire", "cd")
    local icon = B:Get("cd").icons[1]
    SlashCmdList.FECM("")
    local lw = FECMFrame
    lw:Select("look")
    local samples = lw.sampleIcons.icons
    local function Keys()
        local list = {}
        for i, sample in ipairs(samples) do list[i] = S[sample.key].shown and S[sample.key].text or "-" end
        return table.concat(list, " ")
    end
    Equal(S[lw.keybinds.text].text .. " " .. tostring(lw.keybinds:GetChecked()), "Keybinds on icons false",
        "a tick on the Look page, off to start with")
    Equal(S[lw.keyPlace].alpha .. " " .. S[lw.keySize].alpha .. " " .. Keys(), "0.35 0.35 - - - -", "its choices greyed, and no keys on the preview")
    -- Greyed, both still say why on hover, and the slider ignores clicks.
    local keyTrack, pill = lw.keySize.track, lw.keyPlace.buttons[1]
    S[pill].scripts.OnEnter(pill)
    local pillNote = S[lw.note].text
    S[keyTrack].scripts.OnEnter(keyTrack)
    Equal(pillNote .. " | " .. S[lw.note].text .. " | " .. tostring(Last(keyTrack, "EnableMouse")),
        "Tick Keybinds on icons first. | Tick Keybinds on icons first. | true", "the greyed pills and slider both say why on hover")
    S[keyTrack].scripts.OnMouseDown(keyTrack)
    Equal(ns.Get("keybindSize") .. " " .. tostring(S[keyTrack].scripts.OnUpdate) .. " " .. tostring(Last(lw.keySize, "EnableMouseWheel")),
        "100 nil false", "a click on the greyed slider changes nothing, nor does the wheel")
    local rebuilds, rebuild = 0, B.Rebuild
    B.Rebuild = function(...)
        rebuilds = rebuilds + 1
        return rebuild(...)
    end
    lw.keybinds:Click()
    Equal(tostring(ns.Get("keybinds")) .. " " .. S[lw.keyPlace].alpha .. " " .. S[lw.keySize].alpha, "true 1 1", "ticked: on, and its choices usable")
    S[pill].scripts.OnEnter(pill)
    pillNote = S[lw.note].text
    S[keyTrack].scripts.OnEnter(keyTrack)
    Equal(pillNote .. " | " .. S[lw.note].text:sub(1, 17) .. " | " .. tostring(Last(lw.keySize, "EnableMouseWheel")),
        "Where the key sits on each icon. At the bottom, the count or charges on an icon with a key move to the top right. | The key's size: 1 | true",
        "usable: each explains itself, counts and charges alike, and the wheel works")
    Equal(Keys(), "1 S2 M4 C3", "the preview shows keys at once")
    local first = samples[1].key
    Equal(At(first) .. " " .. Last(first, "SetFontObject"), "BOTTOM BOTTOM 0 2 FECMFont8", "along the bottom, sized to the preview's icons")
    Equal(S[icon.key].text .. " " .. tostring(S[icon.key].shown), "1 true", "and your bar shows its real key")
    lw.keyPlace.buttons[4]:Click()
    Equal(ns.Get("keybindPosition") .. " " .. At(first) .. " | " .. At(icon.key) .. " " .. rebuilds,
        "TOPRIGHT TOPRIGHT TOPRIGHT -2 -2 | TOPRIGHT TOPRIGHT -2 -2 0", "Top right: the preview and your bars move there, with no rebuild")
    lw.keySize:Choose(150)
    Equal(ns.Get("keybindSize") .. " " .. Last(first, "SetFontObject") .. " " .. Last(icon.key, "SetFontObject"), "150 FECMFont12 FECMFont16",
        "bigger keys, each sized to its own icon")
    lw.keybinds:Click()
    local anyShown = S[icon.key].shown
    for _, sample in ipairs(samples) do anyShown = anyShown or S[sample.key].shown end
    Equal(tostring(ns.Get("keybinds")) .. " " .. tostring(anyShown), "false false", "unticked: every key hidden")
    -- The same path as the preview: a bar icon its size draws the key the same way.
    lw.keybinds:Click()
    B:SetOption("cd", "size", 26)
    Equal(Last(icon.key, "SetFontObject") .. " " .. At(icon.key) .. " " .. S[icon.key].width .. " " .. Last(icon.key, "SetJustifyH"),
        Last(first, "SetFontObject") .. " " .. At(first) .. " " .. S[first].width .. " " .. Last(first, "SetJustifyH"),
        "a bar icon as big as the preview's draws its key exactly the same way")
    B.Rebuild = rebuild
    Equal(#printed, 0, "no errors from the Look page's keybinds")

    -- Kept over a reload; anything else reads as the defaults.
    local saved = ForeverEnhancedCooldownManagerDB
    Environment(true)
    ns = Load(saved)
    Equal(tostring(ns.Get("keybinds")) .. " " .. ns.Get("keybindPosition") .. " " .. ns.Get("keybindSize"), "true TOPRIGHT 150", "kept over a reload")
    saved.keybinds, saved.keybindPosition, saved.keybindSize = "yes", "MIDDLE", 400
    Equal(tostring(ns.Get("keybinds")) .. " " .. ns.Get("keybindPosition") .. " " .. ns.Get("keybindSize"), "false BOTTOM 100",
        "anything else reads as off, at the bottom, at 100")
    Equal(#printed, 0, "no errors")
end)()

-- The Layout page's drawing: your look and keys ----------------------------------------------

-- In a function of its own: the main chunk is near Lua's limit of 200 locals.
;(function()
    local function Flush()
        for _ = 1, 5 do
            local list = timers
            timers = {}
            for _, timer in ipairs(list) do timer() end
            if #timers == 0 then return end
        end
    end
    local function At(region)
        local p = S[region].points[1]
        return p[1] .. " " .. p[3] .. " " .. p[4] .. " " .. p[5]
    end
    local function On(ring) return ring ~= nil and S[ring[1]].shown == true end -- rings not made yet: off

    Environment()
    Display()
    local spellName = C_Spell.GetSpellName
    local extra = { [8921] = "Moonfire", [8924] = "Moonfire", [5176] = "Wrath", [7384] = "Overpower", [782] = "Thorns" }
    C_Spell.GetSpellName = function(id) return extra[id] or spellName(id) end
    actionSlots[1], keyOf.ACTIONBUTTON1 = { "spell", 8924 }, "1"
    actionSlots[2], keyOf.ACTIONBUTTON2 = { "spell", 5176 }, "SHIFT-2"
    actionSlots[3], keyOf.ACTIONBUTTON3 = { "spell", 782 }, "3"
    _G.FECMFrame = nil
    ns = Load({ useBars = true, prdSkin = false, keybinds = true, notesSeen = "dev" })
    local Bars, Layout = ns.Bars, ns.Layout
    for _, name in ipairs({ "Moonfire", "Wrath", "Overpower" }) do Bars:Assign(name, "cd") end
    Bars:Assign("Thorns", "util")
    Bars:SetAura("buff", "Thorns", true)
    Layout:Apply("pyramid")
    Flush()
    -- Ticks as wide as their labels while the window is made, to check the new
    -- one's room.
    local fixedWidth = Proto.GetStringWidth
    Proto.GetStringWidth = function(self) return #(S[self].text or "") * 6 end
    SlashCmdList.FECM("")
    Proto.GetStringWidth = fixedWidth
    local lw = FECMFrame
    lw:Select("layout")
    local page = lw.pages.layout
    -- What each tile in a row shows: its key or -, then b and s for its own
    -- border and shadow.
    local function Look(tile)
        return (S[tile.key].shown and S[tile.key].text or "-") .. (On(tile.decor.border) and "b" or "")
            .. (On((tile.decor.shadow or {})[1]) and "s" or "")
    end
    local function Row(key)
        local list = {}
        for _, tile in ipairs(page.rows[key].tiles) do
            if S[tile].shown then list[#list + 1] = Look(tile) end
        end
        return table.concat(list, " ")
    end
    local function Boxed(key)
        local decor = page.rows[key].decor
        return (On(decor.border) and "b" or "") .. (On((decor.shadow or {})[1]) and "s" or "")
    end

    -- The tick: on to start with, beside the display's, clear of the sliders.
    Equal(S[page.live.text].text .. " " .. tostring(page.live:GetChecked()) .. " " .. tostring(ns.Get("layoutPreview")),
        "Live preview true true", "a Live preview tick on the Layout page, on to start with")
    local p = S[page.live].points[1]
    Equal(p[1] .. " " .. p[2] .. " " .. p[3] .. " " .. tostring(S[page.live].parent == page.box), "BOTTOMLEFT 12 10 true",
        "in the drawing's bottom left corner, level with Unlock bars (its label ran into Row spacing beside the display's tick)")
    local function Point(region)
        local q = S[region].points[1]
        return table.concat({ table.unpack(q, 1, q.n) }, " ")
    end
    Equal(Point(page.shown) .. " | " .. Point(page.match) .. " | " .. Point(page.spacing) .. " | " .. Point(page.iconSpacing),
        "BOTTOMLEFT 16 36 | BOTTOMLEFT 16 14 | BOTTOMRIGHT -16 34 | BOTTOMRIGHT -16 12",
        "the page's other controls where they were")

    -- Keys on your Cooldowns and Utility icons, as on your bars; none on an
    -- unbound spell, an empty spot or the Buffs row.
    Equal(Row("cd") .. " | " .. Row("util") .. " | " .. Row("buff"), "1 S2 - - - - | 3 - - - - | - - - -",
        "each icon's real key, nothing on an unbound spell, an empty spot or Buffs")
    local moon = page.rows.cd.tiles[1]
    Equal(At(moon.key) .. " " .. tostring(S[moon.key].points[1][2] == moon) .. " " .. Last(moon.key, "SetFontObject") .. " "
        .. S[moon.key].width .. " " .. Last(moon.key, "SetJustifyH") .. " " .. S[moon.key].colour[1],
        "BOTTOM BOTTOM 0 2 true FECMFont8 21 CENTER 0.9", "placed and sized as on an icon the tile's size (25)")
    Equal(tostring(S[moon.key].parent == moon) .. " " .. tostring(moon.decor.border), "true nil",
        "the tile's own text; no rings made while border and shadow are off")

    -- The border and shadow from the Look page, live.
    ns.Set("iconBorder", "icon")
    Equal(Row("cd") .. " | " .. Row("buff") .. " | " .. Boxed("cd"), "1b S2b -b - - - | -b - - - | ",
        "a border round each icon, the Buffs row's too; empty spots stay plain")
    Equal(S[moon.decor.border[1]].parent == moon, true, "the tile's own rings, made as one is chosen")
    ns.Set("iconShadow", "icon")
    Equal(Row("cd"), "1bs S2bs -bs - - -", "and a shadow")
    ns.Set("iconBorder", "bar")
    ns.Set("iconShadow", "bar")
    local cdRow = page.rows.cd
    Equal(Row("cd") .. " | " .. Boxed("cd") .. " " .. Boxed("util") .. " [" .. Boxed("buff") .. "] [" .. Boxed("debuff") .. "]",
        "1 S2 - - - - | bs bs [] []", "round whole bars: not packed Buffs, nor an empty row")
    local span = S[cdRow.span]
    Equal(tostring(span.points[1][2] == cdRow.tiles[1]) .. " " .. span.points[1][1] .. " " .. tostring(span.points[2][2] == cdRow.tiles[3])
        .. " " .. span.points[2][1] .. " " .. tostring(S[cdRow.decor.border[1]].points[1][2] == cdRow.span),
        "true TOPLEFT true BOTTOMRIGHT true", "round your three icons, not the empty spots")
    Bars:SetOption("buff", "showMissing", true)
    Bars:SetOption("cd", "whenReady", "hide")
    lw:Refresh()
    Equal(Boxed("buff") .. " [" .. Boxed("cd") .. "]", "bs []", "as on your bars: fixed Buffs spots get it, a bar hiding ready icons doesn't")
    Bars:SetOption("cd", "whenReady", "dim")
    lw:Refresh()
    Equal(Boxed("cd"), "bs", "one dimming them does")
    Bars:SetOption("cd", "whenReady", "show")
    Layout:SetAcross("cd", 2)
    lw:Refresh()
    Equal(Row("cd") .. " " .. tostring(S[cdRow.span].points[2][2] == cdRow.tiles[2]) .. " " .. S[cdRow.more].text, "1 S2 true +1",
        "fewer across: round the icons that fit")
    Layout:SetAcross("cd", 6)
    -- A row beside the display fills from the display outwards.
    Layout:Apply("sides")
    Bars:SetAura("buff", "Clearcasting", true)
    lw:Refresh()
    local buffRow = page.rows.buff
    Equal(buffRow.place .. " " .. tostring(S[buffRow.span].points[1][2] == buffRow.tiles[2]) .. " "
        .. tostring(S[buffRow.span].points[2][2] == buffRow.tiles[1]) .. " " .. Boxed("buff"), "left true true bs",
        "beside the display on the left, round both its icons")
    Layout:Apply("pyramid")
    ns.Set("iconBorder", "icon")
    ns.Set("iconShadow", "off")

    -- Keybind settings, live.
    ns.Set("keybindPosition", "TOPRIGHT")
    Equal(At(moon.key) .. " " .. Last(moon.key, "SetJustifyH"), "TOPRIGHT TOPRIGHT -2 -2 RIGHT", "Top right")
    ns.Set("keybindSize", 150)
    Equal(Last(moon.key, "SetFontObject"), "FECMFont11", "half as big again, on the tile")
    ns.Set("keybindPosition", "BOTTOM")
    -- The size chosen only resizes the keys: smaller ones stay at the smallest
    -- readable text, as on your bars, and never drop off the drawing.
    local barKey = Bars:Get("cd").icons[1].key
    local sizes = {}
    for _, scale in ipairs({ 50, 90, 100 }) do
        ns.Set("keybindSize", scale)
        sizes[#sizes + 1] = scale .. ":" .. Row("cd") .. ":" .. Last(moon.key, "SetFontObject")
    end
    Equal(table.concat(sizes, " ") .. " | " .. tostring(S[barKey].shown),
        "50:1b S2b -b - - -:FECMFont8 90:1b S2b -b - - -:FECMFont8 100:1b S2b -b - - -:FECMFont8 | true",
        "smaller keys on the default tiles (25): still shown, at the smallest readable size")
    ns.Set("keybindSize", 100)
    -- Only the tile decides: a key on every tile at least as big as the
    -- smallest icon your bars can have (20), at any size chosen; none below.
    local wrongTiles = {}
    for bar = 20, 40 do
        Bars:SetOption("cd", "size", bar)
        for scale = 50, 150, 10 do
            ns.Set("keybindSize", scale)
            local tile = S[moon].width
            if S[moon.key].shown ~= (tile >= ns.BAR_LIMITS.size[1]) then
                wrongTiles[#wrongTiles + 1] = bar .. "@" .. scale .. "=" .. tile .. " "
            end
        end
    end
    ns.Set("keybindSize", 100)
    Equal(table.concat(wrongTiles), "", "a key on each tile from 20 up, whatever size is chosen")
    Bars:SetOption("cd", "size", 20)
    lw:Refresh()
    Equal(Row("cd") .. " | " .. Row("util") .. " | " .. S[moon].width, "-b -b -b - - - | 3b - - - - | 14",
        "a small bar's tiles too small for a key; a bigger one's keep theirs")
    Bars:SetOption("cd", "size", 36)
    lw:Refresh()
    ns.Set("keybinds", false)
    Equal(Row("cd") .. " | " .. Row("util"), "-b -b -b - - - | -b - - - -", "keybinds unticked: none")
    ns.Set("keybinds", true)
    Equal(Row("cd"), "1b S2b -b - - -", "and back")

    -- Your bindings and action bars, live, with nothing redrawn: in a fight too.
    local draws, refresh = 0, page.Refresh
    page.Refresh = function(...)
        draws = draws + 1
        return refresh(...)
    end
    keyOf.ACTIONBUTTON1 = "CTRL-1"
    Fire("UPDATE_BINDINGS")
    Flush()
    actionSlots[4], keyOf.ACTIONBUTTON4 = { "spell", 7384 }, "4"
    Fire("ACTIONBAR_SLOT_CHANGED", 4)
    Flush()
    Equal(Row("cd") .. " " .. draws, "C1b S2b 4b - - - 0", "a key rebound and a spell placed: shown at once, nothing redrawn")
    actionSlots[85] = { "spell", 7384 }
    ns.Keybinds:Update()
    lockdown = true
    bonusIndex = 8
    Settle("UPDATE_BONUS_ACTIONBAR")
    Equal(Row("cd") .. " " .. draws, "-b -b C1b - - - 0", "a form's page in a fight: its keys on the next frame")
    bonusIndex = nil
    Settle("UPDATE_BONUS_ACTIONBAR")
    lockdown = false
    Equal(Row("cd"), "C1b S2b 4b - - -", "and back")
    page.Refresh = refresh

    -- Dragged to another row or off: the look and key go with the spell.
    S[moon].scripts.OnDragStart(moon)
    Equal(Look(moon), "-", "picked up, its spot is plain")
    keyOf.ACTIONBUTTON2 = "SHIFT-3"
    Fire("UPDATE_BINDINGS")
    Flush()
    Equal(Look(moon) .. " " .. Look(cdRow.tiles[2]), "- S3b", "a key change meanwhile leaves it plain")
    S[page.rows.util].mouseOver = true
    S[moon].scripts.OnDragStop(moon)
    S[page.rows.util].mouseOver = nil
    Equal(Row("cd") .. " | " .. Row("util"), "S3b 4b - - - - | 3b C1b - - -", "moved to Utility: its key and border there, the tiles behind it following")
    local off = page.rows.util.tiles[2]
    S[off].scripts.OnDragStart(off)
    S[off].scripts.OnDragStop(off)
    Equal(tostring(off.name) .. " " .. Row("util"), "nil 3b - - - -", "dragged off: its spot plain again")

    -- Nothing takes the mouse: only textures and text on the tiles and rows.
    local wrong, strips, tiles = {}, {}, {}
    for _, row in pairs(page.rows) do
        strips[row.strip] = true
        local parts = { { row.span, "Texture", row.strip } }
        for _, ring in ipairs({ row.decor.border or {}, table.unpack(row.decor.shadow or {}) }) do -- rings not made yet: none
            for _, strip in ipairs(ring) do parts[#parts + 1] = { strip, "Texture", row.strip } end
        end
        for _, tile in ipairs(row.tiles) do
            tiles[tile] = true
            parts[#parts + 1] = { tile.key, "FontString", tile }
            for _, ring in ipairs({ tile.decor.border or {}, table.unpack(tile.decor.shadow or {}) }) do
                for _, strip in ipairs(ring) do parts[#parts + 1] = { strip, "Texture", tile } end
            end
        end
        for _, part in ipairs(parts) do
            if S[part[1]].kind ~= part[2] or S[part[1]].parent ~= part[3] then wrong[#wrong + 1] = row.key end
        end
    end
    -- And nothing else sits on a row's strip (its tiles aside) or on a tile.
    for _, obj in ipairs(objects) do
        local s = S[obj]
        if s and strips[s.parent] and s.kind ~= "Texture" and s.kind ~= "Button" then wrong[#wrong + 1] = s.kind end
        if s and tiles[s.parent] and s.kind ~= "Texture" and s.kind ~= "FontString" then wrong[#wrong + 1] = s.kind end
    end
    Equal(table.concat(wrong, " "), "", "the border, shadow and key are textures and text on the tile or row, which take no mouse")

    -- Off: drawn as before, plain icons and grey spots.
    ns.Set("iconShadow", "bar")
    page.live:Click()
    local empty = cdRow.tiles[3]
    Equal(tostring(ns.Get("layoutPreview")) .. " " .. Row("cd") .. " | " .. Row("util") .. " [" .. Boxed("cd") .. "]",
        "false - - - - - - | - - - - - []", "unticked: no border, shadow or keys")
    Equal(tostring(S[cdRow.tiles[1].texture].texture ~= nil) .. " " .. Last(empty.texture, "SetColorTexture"), "true " .. ns.Theme.CONTROL_BORDER[1],
        "your icons, then grey spots, as before")
    -- The Look page's preview keeps its own.
    lw:Select("look")
    local samples = lw.sampleIcons.icons
    Equal(tostring(S[samples[1].key].shown) .. " " .. S[samples[1].key].text .. " " .. tostring(On(samples[1].decor.border)), "true 1 true",
        "the Look page's preview isn't affected")
    lw:Select("layout")
    page.live:Click()
    Equal(tostring(ns.Get("layoutPreview")) .. " " .. Row("cd") .. " [" .. Boxed("cd") .. "]", "true S3b 4b - - - - [s]", "ticked again: back at once")

    -- Kept over a reload; anything else reads as on.
    ns.Set("layoutPreview", false)
    Equal(#printed .. " " .. tostring(page.drawError), "0 nil", "no errors from the Layout page's drawing")
    local saved = ForeverEnhancedCooldownManagerDB
    Environment(true)
    ns = Load(saved)
    Equal(ns.Get("layoutPreview"), false, "kept over a reload")
    saved.layoutPreview = "yes"
    Equal(ns.Get("layoutPreview"), true, "anything else reads as on")
end)()

-- All bars: every bar's size together -------------------------------------------------------

-- In a function of its own: the main chunk is near Lua's limit of 200 locals.
;(function()
    local function Spot(frame)
        local p = S[frame].points[1]
        return string.format("%s %g %g", p[1], p[4], p[5])
    end
    local function Point(region, i)
        local q = S[region].points[i or 1]
        return table.concat({ table.unpack(q, 1, q.n) }, " ")
    end
    local function Width(frame) return string.format("%g", S[frame].width) end

    Environment()
    Display()
    _G.FECMFrame = nil
    ns = Load({ useBars = true, prdSkin = false, keybinds = true, notesSeen = "dev" })
    local Bars, Layout = ns.Bars, ns.Layout
    for _, name in ipairs({ "Moonfire", "Wrath", "Overpower" }) do Bars:Assign(name, "cd") end
    Bars:Assign("Attack", "util")
    Bars:SetAura("buff", "Thorns", true)
    Layout:Apply("pyramid")
    Bars:SetOption("cd", "size", 48) -- Cooldowns bigger than the rest
    local cd, util, buff = Bars:Get("cd"), Bars:Get("util"), Bars:Get("buff")
    local buffBox = buff.container
    -- The bars as drawn: Cooldowns' and Utility's icons, the packed Buffs
    -- row's scale, each bar's width (and Cooldowns' height), where the three
    -- bars are, and how wide the display is.
    local function Shape()
        return table.concat({ Width(cd.icons[1]), Width(util.icons[1]), string.format("%g", S[buffBox].scale), Width(cd),
            string.format("%g", S[cd].height), Width(buff), Spot(cd), Spot(util), Spot(buff), Width(prd) }, " ")
    end

    -- 100 to start with: every bar exactly its own size.
    Equal(ns.Get("barScale"), 100, "All bars starts at 100")
    local own = {}
    for size = ns.BAR_LIMITS.size[1], ns.BAR_LIMITS.size[2] do
        if ns.IconSize({ size = size }) ~= size then own[#own + 1] = size end
    end
    Equal(table.concat(own, " "), "", "at 100 every bar is its own size")
    local before = Shape()
    Equal(before, "48 36 1 144 48 36 BOTTOM 0 -80 TOP 0 -100 TOP 0 -136 288",
        "Cooldowns at 48, the rest at 36, stacked round the display as wide as the widest row")

    -- Bigger together: each keeps its size next to the others.
    Bars:SetScale(150)
    Equal(Shape(), "72 54 1.5 216 72 54 BOTTOM 0 -80 TOP 0 -100 TOP 0 -154 432",
        "at 150 every bar is half as big again, the rows below move down and the display widens")
    Equal(S[cd.icons[1]].width * 36 == S[util.icons[1]].width * 48, true, "Cooldowns still bigger than Utility, by as much")
    Equal(Last(cd.icons[1].cooldown, "SetCountdownFont") .. " " .. Last(util.icons[1].cooldown, "SetCountdownFont"),
        "FECMFont36 FECMFont27", "the numbers grow with the icons")
    Equal(ns.BarData("cd").size .. " " .. ns.BarData("util").size, "48 36", "each bar's own size stays as you set it")
    Bars:SetScale(100)
    Equal(Shape(), before, "back at 100, exactly as before")

    -- Fixed Buffs spots follow it too.
    Bars:SetScale(125)
    Bars:SetOption("buff", "showMissing", true)
    Equal(Width(buff.holders[1]) .. " " .. Width(buff) .. " " .. S[S[buffBox].slots.b1.supplied.SetDurationCooldown].last.SetCountdownFont[1],
        "45 45 FECMFont23", "fixed Buffs spots at 125: 45, their numbers to match")
    Bars:SetOption("buff", "showMissing", false)

    -- Each bar's own Icon size still fine-tunes it.
    Bars:SetScale(150)
    SlashCmdList.FECM("")
    local lw = FECMFrame
    lw:Select("cd")
    local bp = lw.pages.bar
    Equal(bp.size.current, 48, "a bar's own Icon size slider shows its own size")
    -- Its note says the size on screen, while All bars isn't 100.
    local function SizeNote()
        S[bp.size.track].scripts.OnEnter(bp.size.track)
        local text = S[lw.note].text
        S[bp.size.track].scripts.OnLeave(bp.size.track)
        return text
    end
    Equal(SizeNote(), "This bar's own size. All bars on the Layout page is at 150, so its icons show at 72.",
        "hovering Icon size says All bars makes Cooldowns' 48 show at 72")
    Equal(S[lw.note].text, lw.lastNote, "the note going back after")
    bp.size:Choose(40)
    Equal(ns.BarData("cd").size .. " " .. Width(cd.icons[1]) .. " " .. Width(util.icons[1]), "40 60 54",
        "and still fine-tunes that bar: 40 at 150 is 60, the others untouched")
    bp.size:Choose(48)

    -- Keybinds sized to the icon on screen, when the Look page changes them too.
    ns.Set("keybindPosition", "TOP")
    Bars:ApplyKeybinds()
    Equal(Last(cd.icons[1].key, "SetFontObject") .. " " .. Width(cd.icons[1].key), "FECMFont22 68",
        "keybinds follow the icon on screen (72), not the bar's own 48")
    ns.Set("keybindPosition", "BOTTOM")
    -- Icons can be up to 96 now: a key still fits, clear of the countdown.
    local Style, bad = ns.Style, {}
    for art = ns.BAR_LIMITS.size[2] + 1, ns.BAR_LIMITS.size[2] * ns.BAR_SCALE[2] / 100 do
        local c = Style:CountdownSize(art)
        for _, position in ipairs(ns.KEYBIND_POSITIONS) do
            for scale = 50, 150, 10 do
                local size, lift = Style:KeyFit(art, c, position, scale)
                local up = math.abs(lift)
                local fits = size >= 8 and 2 + .75 * size <= art and 2 + .75 * size + 1 <= art / 2 - .75 * c / 2 + up
                    and art / 2 + .75 * c / 2 + up <= art
                if not fits then bad[#bad + 1] = art .. "/" .. position .. "/" .. scale .. " " end
            end
        end
    end
    Equal(table.concat(bad), "", "a key fits every icon up to 96, clear of the countdown")

    -- Kept within 50 to 150, and an icon never under 20.
    Bars:SetScale(400)
    local high = ns.Get("barScale")
    Bars:SetScale(10)
    Equal(high .. " " .. ns.Get("barScale"), "150 50", "All bars goes from 50 to 150")
    Equal(Width(cd.icons[1]) .. " " .. Width(util.icons[1]), "24 20", "at 50: 48 is 24, and 36 stops at 20, the smallest a bar can have")
    lw:Select("util")
    local small = SizeNote()
    lw:Select("cd")
    Equal(small .. "|" .. SizeNote(), "This bar's own size. All bars on the Layout page is at 50, so its icons show at 20, the smallest they go."
        .. "|This bar's own size. All bars on the Layout page is at 50, so its icons show at 24.", "the note says when a bar stops at 20")
    local wrong = {}
    for percent = ns.BAR_SCALE[1], ns.BAR_SCALE[2], 5 do
        ns.Set("barScale", percent)
        local last = 0
        for size = ns.BAR_LIMITS.size[1], ns.BAR_LIMITS.size[2] do
            local got, exact = ns.IconSize({ size = size }), size * percent / 100
            -- Never under 20 or over 96; a bigger bar never smaller; to the
            -- nearest whole size unless that's under 20.
            if got < 20 or got > 96 or got < last or (exact >= 20 and math.abs(got - exact) > .5) then
                wrong[#wrong + 1] = size .. "@" .. percent .. "=" .. got .. " "
            end
            last = got
        end
    end
    Equal(table.concat(wrong), "", "every size at every step: from 20 to 96, in order, rounded")
    ns.Set("barScale", 999)
    local odd = ns.Get("barScale")
    ns.Set("barScale", "big")
    Equal(odd .. " " .. ns.Get("barScale"), "100 100", "a saved value out of range, or not a number, reads as 100")
    Bars:SetScale(100)
    Equal(SizeNote(), "This bar's icon size. All bars on the Layout page sizes every bar together.", "at 100 it just says what it is")

    -- Beside the display, a bar sits level with its middle at its size on screen.
    Layout:Apply("sides")
    Bars:SetScale(150)
    Equal(Spot(buff) .. " " .. Spot(Bars:Get("debuff")), "TOPRIGHT -100 -63 TOPLEFT 100 -63",
        "Buffs and Debuffs beside the display, level with its middle at 54")
    Bars:SetScale(100)
    Layout:Apply("pyramid")

    -- The Layout page: the slider, above the spacing sliders.
    Bars:SetScale(150)
    lw:Select("layout")
    local page = lw.pages.layout
    local all = page.allBars
    Equal(S[all.label].text .. " " .. all.current, "All bars 150", "an All bars slider on the Layout page, showing where it is")
    Equal(Point(all) .. " " .. Width(all) .. " | " .. Point(all.track) .. " | " .. Point(page.spacing.track),
        "BOTTOMRIGHT -16 56 330 | LEFT 190 0 | LEFT 100 0", "above Row spacing, with room for its longer label")
    -- The page is 638 across.
    Equal(638 - 16 - S[all].width + S[all.track].points[1][2], 638 - 16 - S[page.spacing].width + S[page.spacing.track].points[1][2],
        "its track lined up with the spacing sliders'")
    Equal(tostring(#S[all.label].text * 6 <= S[all.track].points[1][2] - 8), "true", "its label clear of its track (six units a letter)")
    Equal(Point(page.box, 2) .. " | " .. (86 - 56 - S[all].height) .. " " .. (56 - 34 - S[page.spacing].height) .. " "
        .. (34 - 12 - S[page.iconSpacing].height), "BOTTOMRIGHT -16 86 | 10 2 2",
        "the box ends 22 higher for it: 10 under the box, 2 over Row spacing, as between the others")
    Equal(Point(page.shown) .. " " .. tostring(56 > S[page.shown].points[1][3] + S[page.shown].height), "BOTTOMLEFT 16 36 true",
        "above the ticks on the left, clear of them")
    -- Its note, on hover.
    S[all.track].scripts.OnEnter(all.track)
    local note = S[lw.note].text
    S[all.track].scripts.OnLeave(all.track)
    Equal(note, "Sizes all your bars together, keeping each one's size next to the others. 100 is each bar's own Icon size,"
        .. " which still fine-tunes it. Icons never go under 20.", "hovering it explains it in the note line")
    Equal(S[lw.note].text, lw.lastNote, "and the note goes back after")
    -- Dragged: the bars and the drawing change at once.
    Equal(Width(page.rows.cd.tiles[1]), "50", "the drawing at 150: Cooldowns' 72 at .7")
    all:Choose(125)
    Equal(ns.Get("barScale") .. " " .. Width(cd.icons[1]) .. " " .. Width(page.rows.cd.tiles[1]), "125 60 42",
        "dragged to 125: your bars at once, and the drawing with them")
    S[all].scripts.OnMouseWheel(all, 1)
    Equal(ns.Get("barScale") .. " " .. all.current, "130 130", "the wheel steps by 5")
    Bars:SetScale(100)
    Equal(all.current, 100, "and it shows a change made anywhere else")

    -- Big icons: the drawing fits down the box as well as across, clear of
    -- its hint and buttons.
    for _, key in ipairs(ns.BAR_KEYS) do
        Bars:SetOption(key, "size", 64)
        Layout:SetAcross(key, 2)
    end
    Bars:SetScale(150)
    lw:Refresh()
    local lowest, highest = 0, math.huge
    for _, row in pairs(page.rows) do
        if S[row].shown then
            lowest = math.max(lowest, -S[row].points[1][5] + S[row].height)
            highest = math.min(highest, -S[row].points[1][5])
        end
    end
    -- The box is 287 tall: the page's 489 less 116 above it and 86 under it.
    Equal(tostring(highest >= 28) .. " " .. tostring(lowest <= 287 - 28) .. " " .. Width(page.rows.cd.tiles[1]), "true true 54",
        "every row of 96 inside the box, drawn at 54")
    for _, key in ipairs(ns.BAR_KEYS) do Bars:SetOption(key, "size", 36) end
    Bars:SetOption("cd", "size", 48)
    Layout:Apply("pyramid")
    Bars:SetScale(100)
    Equal(Shape(), before, "back as it was")

    -- In a fight: your Cooldowns and Utility bars at once, the rest after.
    Fire("PLAYER_REGEN_DISABLED")
    lockdown = true
    local calls = containerCallsInCombat
    all:Choose(125)
    Equal(Width(cd.icons[1]) .. " " .. Width(util.icons[1]), "60 45", "in a fight, your Cooldowns and Utility bars resize at once")
    Equal(tostring(buff.pendingLayout) .. string.format(" %g ", S[buffBox].scale) .. Width(buff) .. " " .. (containerCallsInCombat - calls),
        "true 1 36 0", "the Buffs bar waits, its secure icons untouched")
    Equal(tostring(Layout.pending) .. " " .. tostring(ns.Resource.pendingMatch) .. " " .. Width(prd), "true true 288",
        "and the stack and the display's width wait too")
    lockdown = false
    Fire("PLAYER_REGEN_ENABLED")
    Equal(string.format("%g ", S[buffBox].scale) .. Width(buff) .. " " .. Spot(buff) .. " " .. Width(prd) .. " " .. tostring(Layout.pending),
        "1.25 45 TOP 0 -145 360 nil", "once it's over the Buffs bar catches up under Utility, and the display widens")

    -- Shared by every profile, like the bars' own sizes; Reset keeps it too.
    local mine = ns.ProfileName()
    ns.NewProfile("Raid")
    local there = ns.Get("barScale")
    ns.UseProfile(mine)
    Equal(there .. " " .. ns.Get("barScale"), "125 125", "the same in every profile")
    Layout:Reset()
    Equal(ns.Get("barScale") .. " " .. Width(cd.icons[1]), "125 60", "Reset keeps it, as it keeps your icon sizes")
    Equal(#printed .. " " .. tostring(page.drawError) .. " " .. tostring(bp.listError), "0 nil nil", "no errors")

    -- Kept over a reload, the bars drawn at it from the start.
    local saved = ForeverEnhancedCooldownManagerDB
    Environment(true)
    Display()
    ns = Load(saved)
    Equal(ns.Get("barScale") .. " " .. Width(ns.Bars:Get("cd").icons[1]), "125 60", "kept over a reload")

    -- Bars in no layout and never moved sit in their own spots above the
    -- action bar, each growing up from there: All bars spreads the spots out
    -- with the bars (or closes them up), so they never overlap.
    Bars = ns.Bars
    Bars:SetOption("cd", "size", 36)
    Bars:ResetPositions()
    local order = { "util", "cd", "buff", "debuff" }
    local function Spots()
        local spots = {}
        for _, key in ipairs(order) do
            local p = S[Bars:Get(key)].points[1]
            spots[#spots + 1] = p[1] .. " " .. p[5] .. "-" .. (p[5] + S[Bars:Get(key)].height)
        end
        return table.concat(spots, " ")
    end
    Bars:SetScale(100)
    Equal(Spots(), "BOTTOM 146-182 BOTTOM 190-226 BOTTOM 234-270 BOTTOM 278-314", "at 100 where they always were")
    Bars:SetScale(150)
    Equal(Spots(), "BOTTOM 146-200 BOTTOM 212-266 BOTTOM 278-332 BOTTOM 344-398", "at 150 spread out with the bars, the same 8 apart at 100 now 12")
    local overlaps = {}
    for percent = ns.BAR_SCALE[1], ns.BAR_SCALE[2], 5 do
        Bars:SetScale(percent)
        local below
        for _, key in ipairs(order) do
            local bottom = S[Bars:Get(key)].points[1][5]
            if below and bottom < below then overlaps[#overlaps + 1] = key .. "@" .. percent .. " " end
            below = bottom + S[Bars:Get(key)].height
        end
    end
    Equal(table.concat(overlaps), "", "at every step each bar clears the one under it")
    Bars:SetScale(100)
    Equal(#printed, 0, "no errors")
end)()

-- Grow arrows while you arrange your bars -------------------------------------------------

-- In a function of its own: the main chunk is near Lua's limit of 200 locals.
;(function()
    Environment()
    local ns = Load({ useBars = true })
    local B, L, T = ns.Bars, ns.Layout, ns.Theme
    for _, name in ipairs({ "Moonfire", "Wrath", "Overpower" }) do B:Assign(name, "cd") end
    local cd, buff, debuff = B:Get("cd"), B:Get("buff"), B:Get("debuff")
    local arrows = cd.arrows
    -- Which way the art faces, from how it's turned.
    local function Way(texture)
        local c = S[texture].last.SetTexCoord
        if c.n == 8 then return c[1] == 1 and c[2] == 0 and "left" or "right" end
        return c[3] == 0 and "up" or "down"
    end
    -- The arrows that can be seen on a bar, each by the way it points (the
    -- row's with the edge it sits on), or "none". Each black edge must go
    -- with its arrow.
    local function Seen(bar)
        local a = bar.arrows
        if not a:IsVisible() then return "none" end
        local list = {}
        for _, arrow in ipairs({ a.left, a.right, a.row }) do
            if S[arrow].shown ~= S[arrow.edge].shown or Way(arrow) ~= Way(arrow.edge) then list[#list + 1] = "(edge?)" end
            if S[arrow].shown then list[#list + 1] = Way(arrow) .. (arrow == a.row and ("@" .. S[arrow].points[1][1]) or "") end
        end
        return table.concat(list, " ")
    end

    -- Off to start with: unlocked, just the movers.
    B:SetUnlocked(true)
    Equal(tostring(ns.Get("growArrows")) .. " " .. tostring(S[cd.mover].shown) .. " " .. Seen(cd), "false true none",
        "grow arrows start off: unlocked, a bar has its mover and no arrows")
    -- Never in the way: on the bar, above its mover, taking no mouse.
    Equal(tostring(Last(arrows, "EnableMouse")) .. " " .. tostring(S[arrows].parent == cd) .. " "
        .. tostring(Last(arrows, "SetFrameLevel") > Last(cd.mover, "SetFrameLevel")), "false true true",
        "the arrows never take the mouse, and sit on the bar above its mover")

    -- Ticked: from the centre, out both ways, and new rows below.
    ns.Set("growArrows", true)
    B:ApplyArrows()
    Equal(Seen(cd), "left right down@BOTTOM", "ticked: growing from the centre, an arrow out each side, and one down for new rows")
    local function At(region)
        local p = S[region].points[1]
        return table.concat({ p[1], tostring(p[2] == cd), p[3], p[4], p[5], S[region].width .. "x" .. S[region].height }, " ")
    end
    Equal(At(arrows.left) .. " | " .. At(arrows.right) .. " | " .. At(arrows.row),
        "LEFT true LEFT -3 0 7x12 | RIGHT true RIGHT 3 0 7x12 | BOTTOM true BOTTOM 0 -3 12x7",
        "small, on the bar's edges, their tips just outside, inside the mover's margin")
    local edge = arrows.left.edge
    Equal(S[edge].width .. "x" .. S[edge].height .. " " .. table.concat(S[edge].tint, " ") .. " " .. tostring(S[edge].points[1][2] == arrows.left),
        "9x14 0 0 0 true", "each over a black copy a little bigger, so it reads over any icon")
    Equal(table.concat(S[arrows.left].tint, " ") .. " " .. S[arrows.left].texture,
        table.concat(T:Accent(), " ") .. " " .. ns.MEDIA .. "TourArrow.tga", "the tour's arrow, in the accent")
    ForeverEnhancedCooldownManagerDB.accent = "blue"
    T:Repaint()
    Equal(table.concat(S[arrows.row].tint, " "), table.concat(T.ACCENTS.blue.colour, " "), "a new accent repaints them")
    ForeverEnhancedCooldownManagerDB.accent = "orange"
    T:Repaint()

    -- Growing from an edge: one arrow, away from it. New rows above: the
    -- row's arrow up, at the top.
    B:SetOption("cd", "grow", "left")
    local left = Seen(cd)
    B:SetOption("cd", "grow", "right")
    local right = Seen(cd)
    B:SetOption("cd", "wrap", "up")
    Equal(left .. " | " .. right .. " | " .. Seen(cd) .. " " .. S[arrows.row].points[1][5],
        "left down@BOTTOM | right down@BOTTOM | right up@TOP 3",
        "growing left or right, the one arrow that way; new rows above, the row's arrow up at the top")
    B:SetOption("cd", "grow", "centre")
    B:SetOption("cd", "wrap", "down")

    -- Only while the bars are being arranged.
    B:SetUnlocked(false)
    Equal(tostring(S[arrows].shown) .. " " .. Seen(cd), "false none", "locked: gone")
    EditModeManagerFrame:Show()
    Equal(Seen(cd) .. " " .. tostring(S[cd.mover].shown), "left right down@BOTTOM false", "in Edit Mode on your bars, with no mover")
    EditModeManagerFrame:Hide()
    Equal(Seen(cd), "none", "and gone once it closes")
    B:SetUnlocked(true)
    ns.Set("growArrows", false)
    B:ApplyArrows()
    Equal(Seen(cd), "none", "unticked while unlocked: gone at once")
    ns.Set("growArrows", true)
    B:ApplyArrows()

    -- Packed Buffs and Debuffs are one row: only which way they grow. Fixed
    -- spots go in rows like icons.
    B:SetAura("buff", "Thorns", true)
    Equal(Seen(buff) .. " | " .. Seen(debuff), "left right | left right", "packed Buffs, and an empty Debuffs shown while unlocked: no new rows")
    B:SetOption("buff", "showMissing", true)
    Equal(Seen(buff), "left right down@BOTTOM", "fixed spots: new rows too")
    -- In a fight the Buffs bar keeps its shape, and its arrows, until it's over.
    Fire("PLAYER_REGEN_DISABLED")
    lockdown = true
    B:SetOption("buff", "grow", "right")
    local during = Seen(buff)
    lockdown = false
    Fire("PLAYER_REGEN_ENABLED")
    Equal(during .. " | " .. Seen(buff), "left right down@BOTTOM | right down@BOTTOM",
        "a fight holds the Buffs bar's arrows with its shape; they follow it after")
    B:SetOption("buff", "showMissing", false)
    B:SetOption("buff", "grow", "centre")

    -- A layout sets which way its bars grow; the arrows follow.
    L:Apply("sides")
    Equal(Seen(cd) .. " | " .. Seen(buff) .. " | " .. Seen(debuff) .. " | " .. Seen(B:Get("util")),
        "left right up@TOP | left | right | left right down@BOTTOM",
        "Sides: Cooldowns above growing up, Buffs growing left, Debuffs right, Utility below growing down")
    L:TurnOff()
    B:SetUnlocked(false)

    -- The Layout page's tick, level with All bars on its left.
    ns.Set("growArrows", false)
    B:ApplyArrows()
    SlashCmdList.FECM("")
    local w = FECMFrame
    w:Select("layout")
    local lp = w.pages.layout
    local tick = lp.growArrows
    local p, all = S[tick].points[1], S[lp.allBars].points[1]
    Equal(S[tick.text].text .. " " .. tostring(tick:GetChecked()) .. " " .. p[1] .. " " .. p[2] .. " " .. p[3],
        "Show grow arrows false BOTTOMLEFT 16 58", "a Show grow arrows tick on the Layout page, off, bottom left")
    Equal(tostring(p[3] + S[tick].height / 2 == all[3] + S[lp.allBars].height / 2) .. " "
        .. tostring(16 + 18 + #S[tick.text].text * 6 <= 638 - 16 - S[lp.allBars].width - 8) .. " "
        .. tostring(p[3] + S[tick].height <= S[lp.box].points[2][3] - 8), "true true true",
        "level with All bars and clear of it (six units a letter), under the drawing's box")
    Equal(tick.hint, "While your bars are unlocked, or in Edit Mode, an arrow on each shows which way it grows as icons come and go,"
        .. " and where a new row goes.", "its note says when they show and what they mean")
    tick:Click()
    lp.unlock:Click()
    Equal(tostring(ns.Get("growArrows")) .. " " .. tostring(tick:GetChecked()) .. " " .. Seen(cd), "true true left right up@TOP",
        "ticked and unlocked: the arrows on your bars")
    w:Hide()
    Equal(tostring(B:IsUnlocked()) .. " " .. Seen(cd), "false none", "closing the window locks the bars, and the arrows go")
    Equal(#printed, 0, "no errors")

    -- Kept over a reload; anything else reads as off.
    local saved = ForeverEnhancedCooldownManagerDB
    Environment(true)
    ns = Load(saved)
    Equal(ns.Get("growArrows"), true, "kept over a reload")
    saved.growArrows = "yes"
    Equal(ns.Get("growArrows"), false, "anything else reads as off")
end)()

-- The footer: who made the addon, and every control's note -------------------------------

;(function()
    Environment()
    Display()
    local ns = Load({ useBars = true, prdSkin = false })
    local B, L, T = ns.Bars, ns.Layout, ns.Theme
    for _, name in ipairs({ "Moonfire", "Wrath", "Overpower" }) do B:Assign(name, "cd") end
    L:Apply("pyramid")
    SlashCmdList.FECM("")
    local w = FECMFrame
    local note = w.note
    local function Text() return S[note].text end
    local CREDIT = "Made with |TInterface\\AddOns\\ForeverEnhancedCooldownManager\\Media\\Heart.tga:0:0:0:0:32:32:0:32:0:32:%d:%d:%d|t"
        .. " by |cff%sSquirt|r"
    local ORANGE = CREDIT:format(224, 120, 41, "e07829")
    local function Enter(control) S[control].scripts.OnEnter(control) end
    local function Leave(control) S[control].scripts.OnLeave(control) end
    -- The mouse over these, or (nil) off them.
    local function Over(on, ...)
        for _, region in ipairs({ ... }) do S[region].mouseOver = on end
    end
    -- A control's note as the mouse passes over it; areas are what it sits
    -- in, which the mouse is over too.
    local function NoteOf(control, ...)
        Over(true, control, ...)
        Enter(control)
        local text = Text()
        Over(nil, control, ...)
        Leave(control)
        return text
    end
    -- Every text the footer shows from here on, in order.
    local shown = {}
    rawset(note, "SetText", function(self, text)
        shown[#shown + 1] = text
        S[self].text = text
    end)
    local function Seen()
        local list = shown
        shown = {}
        return list
    end
    local function Rested(list)
        for _, text in ipairs(list) do
            if type(text) == "string" and text:find("^Made with") then return true end
        end
        return false
    end
    local function Point(region, i)
        local p = S[region].points[i or 1]
        return p[1] .. " " .. p[p.n - 1] .. " " .. p[p.n]
    end
    -- Whether a region sits somewhere inside root.
    local function Under(region, root)
        local parent = S[region] and S[region].parent
        while parent do
            if parent == root then return true end
            parent = S[parent] and S[parent].parent
        end
        return false
    end

    -- Made with a heart by Squirt, the heart and name in the accent.
    Equal(Text(), CREDIT:format(176, 125, 240, "b07df0"), "at rest the footer says who made the addon, the heart and Squirt in purple, the default accent")
    Equal(table.concat(S[note].colour, " "), table.concat(T.MUTED, " "), "the rest of the line in the footer's muted grey")
    Equal(Text():find("highest rank", 1, true), nil, "the rank line is no longer the footer's")
    w:Select("look")
    w.swatches[3]:Click()
    Equal(Text(), CREDIT:format(43, 179, 163, "2bb3a3"), "a new accent: the heart and name in teal at once")
    -- The repaint alone does it: the setting changed without a refresh.
    ForeverEnhancedCooldownManagerDB.accent = "purple"
    T:Repaint()
    Equal(Text(), CREDIT:format(176, 125, 240, "b07df0"), "repainted with the window, before any refresh: purple")
    Over(true, w.swatches[2])
    Enter(w.swatches[2])
    T:Repaint()
    Equal(Text(), "Blue for this window's headings, ticks, sliders and highlights.", "a repaint leaves a hovered control's note up")
    Over(nil, w.swatches[2])
    Leave(w.swatches[2])
    Equal(Text(), CREDIT:format(176, 125, 240, "b07df0"), "and the credit comes back in the accent")
    w.swatches[1]:Click()
    Equal(Text(), ORANGE, "back to orange")

    -- A note takes the credit's place while the mouse is over its control.
    Equal(NoteOf(w.news), "What changed in this version. /ccm new shows it too.", "hovering What's new, its note")
    Equal(Text(), ORANGE, "and the credit back as the mouse leaves")
    w:Say("Done that.")
    w:Refresh()
    local over = NoteOf(w.news)
    Equal(over .. " | " .. Text() .. " | " .. w.lastNote, "What changed in this version. /ccm new shows it too. | Done that. | Done that.",
        "over a message, a note, then the message back")
    w:Refresh()
    Equal(Text(), ORANGE, "the next refresh rests on the credit again")
    -- Straight from one control to the next, whichever the game tells first,
    -- the next one's note: only the control whose note is up can take it down.
    local look, layout = w.nav.look, w.nav.layout
    Over(true, look)
    Enter(look)
    Over(nil, look)
    Over(true, layout)
    Enter(layout)
    Leave(look)
    local next = Text()
    Over(nil, layout)
    Over(true, look)
    Enter(look)
    Leave(layout)
    Equal(next .. " | " .. Text(), "One-click layouts that stack your bars around your Personal Resource Display. | "
        .. "Blizzard's Cooldown Manager restyled: bar designs, borders, shadows, keybinds, font, textures, ready glow and the accent.",
        "entered before the last one is left, each keeps its note")
    Over(nil, look)
    Leave(look)
    Equal(Text(), ORANGE, "and off both, the credit")

    -- Clicking a control keeps its note up, as it now reads; a message from
    -- the click takes the footer instead, and stays as the mouse leaves.
    w:Select("cd")
    local bp = w.pages.bar
    Over(true, bp.clear)
    Enter(bp.clear)
    Equal(Text(), "Take every icon off Cooldowns. It asks for a second click.", "Clear says what it does")
    bp.clear:Click()
    Equal(Text(), "Click again to take every icon off Cooldowns.", "clicked once, its note stays up and says what the next click does")
    bp.clear:Click()
    Equal(Text(), "Cooldowns cleared.", "the message takes the footer from the control clicked")
    Over(nil, bp.clear)
    Leave(bp.clear)
    Equal(Text(), "Cooldowns cleared.", "and stays as the mouse leaves")
    for _, name in ipairs({ "Moonfire", "Wrath", "Overpower" }) do B:Assign(name, "cd") end
    w:Refresh()
    -- Dragged, a slider's note stays up, not the credit, with each step.
    Over(true, bp.size.track)
    Enter(bp.size.track)
    bp.size:Choose(40)
    Equal(Text(), "This bar's icon size. All bars on the Layout page sizes every bar together.", "a slider's note stays up as it's dragged")
    Over(nil, bp.size.track)
    Leave(bp.size.track)
    bp.size:Choose(36)
    -- A button its own click hides leaves the credit behind, not its note.
    ns.Set("useBars", false)
    B:Rebuild()
    w:Refresh()
    Over(true, bp.turnOn)
    Enter(bp.turnOn)
    Equal(Text(), "Turn your bars on.", "Turn on says what it does")
    bp.turnOn:Click()
    Equal(tostring(S[bp.turnOn].shown) .. " " .. Text(), "false " .. ORANGE, "clicked, it goes, and so does its note")
    Over(nil, bp.turnOn)
    Leave(bp.turnOn)
    -- Closed from a control (its X, or Escape), opened again: the credit.
    Enter(w.close)
    w.close:Click()
    ns.ShowWindow()
    Equal(Text(), ORANGE, "the window opened again rests on the credit, not the X's note")

    -- The rank line: on the bar pages, under the search, clear of the list.
    local ranks = bp.ranks
    Equal(S[ranks].text .. " | " .. tostring(S[ranks].shown) .. " | " .. table.concat(S[ranks].colour, " "),
        "Each spell shows once, at your highest rank. | true | " .. table.concat(T.MUTED, " "), "the rank line on the bar page, muted")
    Equal(Point(ranks) .. " | " .. Point(bp.search) .. " " .. S[bp.search].height .. " | " .. Point(bp.list),
        "TOPLEFT 10 -34 | TOPLEFT 8 -8 20 | TOPLEFT 8 -50", "under the search box, and the list under it")
    Equal(tostring(#S[ranks].text * 6 <= S[ranks].width) .. " " .. tostring(-34 - ranks:GetStringHeight() >= -50), "true true",
        "on one line (six units a letter), clear of the list")
    bp.showRanks:Click()
    Equal(S[ranks].text, "Each spell at your highest rank, with the lower ranks you know under it.", "Show all ranks: the line says so")
    bp.showRanks:Click()
    w:Select("buff")
    Equal(S[ranks].text, "Each spell shows once, and counts every rank.", "an aura bar counts every rank")
    w:Select("cd")

    -- The Layout page: each of a row's buttons says what it does.
    w:Select("layout")
    local lp = w.pages.layout
    local rows, display = lp.rows, lp.display
    local cd, util = rows.cd, rows.util
    local function RowNote(row, button) return NoteOf(button, row, row.buttons) end
    Equal(RowNote(cd, cd.fewer) .. " | " .. RowNote(cd, cd.wider), "One fewer icon across (6 now). | One more icon across (6 now).",
        "- and +, and how many across now")
    Equal(RowNote(cd, cd.up), "Cooldowns is already at the top.", "greyed, the top row's up arrow says why")
    Equal(tostring(cd.up.usable) .. " " .. tostring(Last(cd.up, "SetMotionScriptsWhileDisabled")), "false true",
        "greyed buttons still hear the mouse")
    -- Rows keep their width (a preset's shape), so each note says how many
    -- would then fit across each bar.
    Equal(RowNote(cd, cd.down), "Move Cooldowns down the stack, past the display, swapping places with Utility."
        .. " Rows keep their width, so Cooldowns would be 5 across and Utility 6.", "down, past the display")
    Equal(RowNote(util, util.up), "Move Utility up the stack, past the display, swapping places with Cooldowns."
        .. " Rows keep their width, so Utility would be 6 across and Cooldowns 5.", "up, past the display")
    Equal(RowNote(util, util.down), "Move Utility down the stack, swapping places with Buffs."
        .. " Rows keep their width, so Utility would be 4 across and Buffs 5.", "down, the same side")
    Equal(RowNote(rows.debuff, rows.debuff.down), "Debuffs is already at the bottom.", "the bottom row's down arrow says why")
    Equal(RowNote(util, util.out), "Take Utility out of your layout. It asks first, and its spells stay.", "x")
    Equal(NoteOf(display.up, display.buttons) .. " | " .. NoteOf(display.down, display.buttons),
        "Move your resource display up the stack, past Cooldowns. | Move your resource display down the stack, past Utility.",
        "the display's arrows name the row they move it past")
    -- Greyed, lit on hover no more; usable, lit.
    local lit = Last(cd.up, "SetBackdropColor")
    Enter(cd.up)
    Equal(Last(cd.up, "SetBackdropColor") == lit, true, "a greyed button isn't lit on hover")
    Leave(cd.up)
    Over(true, cd, cd.buttons, cd.wider)
    Enter(cd.wider)
    Equal(Last(cd.wider, "SetBackdropColor"), T.HOVER[1], "a usable one is")
    cd.wider:Click()
    Equal(Text(), "One more icon across (7 now).", "clicked, + still says what it does, now at 7")
    -- A click's message takes the footer for that click only: the next
    -- click, the mouse still on +, has its note back.
    lockdown = true
    cd.wider:Click()
    local said = Text()
    lockdown = false
    cd.wider:Click()
    Equal(said .. " | " .. Text(), "Finish combat first. | One more icon across (8 now).",
        "in combat the message, then after it the next click without moving: + says what it does again")
    Over(nil, cd, cd.buttons, cd.wider)
    Leave(cd.wider)
    Equal(tostring(S[cd.buttons].shown) .. " " .. Text(), "true " .. ORANGE,
        "off the row the credit comes back (clicked, its buttons stay up)")
    L:SetAcross("cd", 1)
    lp:Refresh()
    Equal(RowNote(cd, cd.fewer) .. " " .. tostring(cd.fewer.usable), "Cooldowns is down to 1 across, the fewest. false", "at 1, - says so")
    L:SetAcross("cd", 20)
    lp:Refresh()
    Equal(RowNote(cd, cd.wider), "Cooldowns is at the most across, 20.", "at 20, + says so")
    -- Beside the display.
    L:Apply("sides")
    lp:Refresh()
    Equal(RowNote(cd, cd.down), "Move Cooldowns down, to the left of the display, swapping places with Buffs."
        .. " Rows keep their width, so Cooldowns would be 4 across and Buffs 8.", "down beside the display")
    Equal(RowNote(rows.buff, rows.buff.up), "Move Buffs up, above the display, swapping places with Cooldowns."
        .. " Rows keep their width, so Buffs would be 8 across and Cooldowns 4.", "up above it")
    Equal(RowNote(rows.buff, rows.buff.down), "Move Buffs down, to the right of the display, swapping places with Debuffs.",
        "across it (both 4 across, so nothing to say about widths)")
    Equal(RowNote(rows.debuff, rows.debuff.down), "Move Debuffs down, below the display, swapping places with Utility."
        .. " Rows keep their width, so Debuffs would be 6 across and Utility 4.", "down below it")
    -- Clicked, the footer says what changed, widths and all.
    rows.debuff.down:Click()
    Equal(Text() .. " " .. ns.BarData("debuff").perRow .. " " .. ns.BarData("util").perRow,
        "Debuffs and Utility swapped rows. Rows keep their width, so Debuffs is now 6 across and Utility 4. 6 4",
        "swapped: the footer says each bar's new width")
    Leave(rows.debuff.down)
    w:Refresh() -- the next refresh puts the footer back to resting on the credit
    -- The display skips rows taken out, and says when it can't move.
    L:Apply("pyramid")
    L:TakeOut("cd")
    lp:Refresh()
    Equal(NoteOf(display.up, display.buttons), "Your resource display is already at the top.", "nothing above it in the layout")
    L:PutBack("cd")
    L:Apply("funnel")
    lp:Refresh()
    Equal(NoteOf(display.down, display.buttons), "Your resource display is already at the bottom.", "nothing below it")
    L:Apply("pyramid")
    lp:Refresh()

    -- The game moves the mouse off one control and onto the next in one
    -- frame: it leaves the first and enters the next, in either order, and
    -- only then draws. So what's seen is the footer after both; a resting
    -- line set in between is never drawn. Entered first, it isn't even set.
    local function Move(from, to, enterFirst)
        Seen()
        if enterFirst then Enter(to); Leave(from) else Leave(from); Enter(to) end
        return Text(), Rested(Seen())
    end
    -- From a row onto each of its buttons and back, the footer never drops
    -- to the credit: the row's note, the button's, the row's again.
    local function Path(row, button, enterFirst)
        Over(true, row)
        Enter(row)
        Over(true, row.buttons, button)
        local on, restedOn = Move(row, button, enterFirst)
        local buttons = S[row.buttons].shown
        Over(nil, row.buttons, button)
        local back, restedBack = Move(button, row, enterFirst)
        Over(nil, row)
        Leave(row)
        return on, back, enterFirst and (restedOn or restedBack), buttons
    end
    local HINT = "- and + change how many fit across; the arrows swap rows. Drag an icon onto another to swap them, to another row, or off to remove it."
    local flashes = {}
    for _, key in ipairs({ "cd", "util" }) do
        local row = rows[key]
        for _, part in ipairs({ "fewer", "wider", "up", "down", "out" }) do
            local button = row[part]
            local want = type(button.hint) == "function" and button.hint(button) or button.hint
            for _, enterFirst in ipairs({ false, true }) do
                local on, back, rested, buttons = Path(row, button, enterFirst)
                if rested or not buttons or back ~= HINT or on ~= want or not want:find("%a") then
                    flashes[#flashes + 1] = key .. "." .. part .. (enterFirst and " (enter first)" or "") .. ": " .. tostring(on) .. " "
                end
            end
        end
    end
    Equal(table.concat(flashes), "", "row to each button and back: the button's note, then the row's, and the credit never seen")
    Equal(Text(), ORANGE, "off the row altogether, the credit")
    -- A row's icons too.
    local tile = cd.tiles[1]
    Over(true, cd)
    Enter(cd)
    Over(true, tile)
    local onTile = Move(cd, tile)
    Over(nil, tile)
    local tileBack = Move(tile, cd)
    Equal(onTile .. " | " .. tileBack, "Moonfire. Drag it onto another icon to swap them, to another row, or off to remove it. | " .. HINT,
        "row to an icon and back: the icon's note, then the row's")
    Over(nil, cd)
    Leave(cd)

    -- Clicked, a row's x asks first, and the "Are you sure?" dialog's shade
    -- takes the mouse: the game leaves the x, though it and its row are still
    -- under the mouse, covered. The footer rests, not on the covered row's
    -- note, and stays so after Cancel with the mouse on nothing with a note.
    local confirm = w.confirm
    Over(true, cd, cd.buttons, cd.out)
    Enter(cd)
    Move(cd, cd.out)
    cd.out:Click()
    Leave(cd.out)
    local covered = Text()
    confirm.no:Click()
    Equal(tostring(S[confirm.shade].shown) .. " | " .. covered .. " | " .. Text(), "false | " .. ORANGE .. " | " .. ORANGE,
        "the x's dialog up, then Cancel: the credit, never the covered row's note")
    Over(nil, cd, cd.buttons, cd.out)
    Leave(cd)
    Equal(Text(), ORANGE, "and the row, left after, changes nothing")

    -- While a found debuff waits for its spot, a row's and an icon's notes
    -- say what a click does with it.
    B:SetAura("debuff", "Moonfire", true)
    S[lp.search].scripts.OnEditFocusGained(lp.search)
    lp.search:SetText("fae")
    S[lp.search].scripts.OnTextChanged(lp.search, true)
    lp.found[1]:Click()
    local debuffs = rows.debuff
    Equal(table.concat({ NoteOf(debuffs.tiles[1], debuffs), NoteOf(debuffs.tiles[2], debuffs), NoteOf(debuffs) }, " | "),
        "Click to put Faerie Fire here, before Moonfire. | Click to put Faerie Fire here. | "
        .. "Click to put Faerie Fire at the end, or click an icon to put it in that spot.",
        "placing: the Debuffs row's icons take its spot, anywhere else there the end")
    Equal(NoteOf(cd.tiles[1], cd) .. " | " .. NoteOf(cd), "Debuffs go in the Debuffs row. | Debuffs go in the Debuffs row.",
        "and another row's icons and the row itself say it can't go there")
    lp.cancel:Click()
    Equal(NoteOf(cd.tiles[1], cd) .. " | " .. NoteOf(cd), "Moonfire. Drag it onto another icon to swap them, to another row, or off to remove it. | " .. HINT,
        "cancelled, their usual notes")
    B:SetAura("debuff", "Moonfire", false)
    lp:Refresh()
    -- The display's arrows sit 8 to its right: the strip under them spans
    -- the gap, so crossing it keeps them up and a note in the footer.
    Equal(Point(display.buttons) .. " " .. S[display.buttons].width .. " | " .. Point(display.up) .. " | " .. Point(display.down),
        "LEFT 0 0 48 | LEFT 8 0 | LEFT 30 0", "the arrows where they were, the strip reaching back to the display")
    Equal(tostring(Last(display.buttons, "EnableMouse")) .. " " .. tostring(Last(cd.buttons, "EnableMouse")), "true nil",
        "that strip takes the mouse; a row's, inside the row, doesn't need to")
    local DISPLAY = "Your Personal Resource Display. The arrows move it up or down the stack; move it on screen in Edit Mode."
    Over(true, display)
    Enter(display)
    Over(nil, display)
    Over(true, display.buttons)
    local gap = Move(display, display.buttons)
    local kept = S[display.buttons].shown
    Over(true, display.up)
    local onArrow = Move(display.buttons, display.up)
    Over(nil, display.up)
    local gapBack = Move(display.up, display.buttons)
    Over(nil, display.buttons)
    Over(true, display)
    local displayBack = Move(display.buttons, display)
    Equal(table.concat({ gap, tostring(kept), onArrow, gapBack, displayBack }, " | "),
        table.concat({ DISPLAY, "true", "Move your resource display up the stack, past Cooldowns.", DISPLAY, DISPLAY }, " | "),
        "display to its arrow and back: its arrows stay up across the gap, and a note all the way")
    Over(nil, display)
    Leave(display)

    -- A bar page's icons: the tray, an icon, its x, and back.
    w:Select("cd")
    local icon = bp.icons[1]
    local TRAY = "Drop a spell or item here from your spellbook, bags or action bars. Drag an icon onto another to swap them."
    Over(true, bp.tray)
    Enter(bp.tray)
    local onTray = Text()
    Over(true, icon)
    local onIcon = Move(bp.tray, icon)
    Over(true, icon.remove)
    local onRemove = Move(icon, icon.remove)
    Over(nil, icon.remove)
    local iconBack = Move(icon.remove, icon)
    Over(nil, icon)
    local trayBack = Move(icon, bp.tray)
    Equal(table.concat({ onTray, onIcon, onRemove, iconBack, trayBack }, " | "), table.concat({ TRAY,
        "Moonfire. Drag it onto another icon to swap them, or off the bar to take it off.", "Take Moonfire off Cooldowns.",
        "Moonfire. Drag it onto another icon to swap them, or off the bar to take it off.", TRAY }, " | "),
        "tray, icon, its x, the icon, the tray: each its own note")
    -- Off the x past the icon's edge, straight onto the tray: the tray's note.
    Over(true, icon, icon.remove)
    Enter(icon.remove)
    Over(nil, icon, icon.remove)
    Equal(Move(icon.remove, bp.tray), TRAY, "off an icon's x onto the tray: the tray's note")
    Over(nil, bp.tray)
    Leave(bp.tray)
    Equal(Text(), ORANGE, "off the tray, the credit")
    -- The profile menu over the tray: off an icon or the tray onto the menu,
    -- the game leaves them, though they're still under the mouse, covered.
    -- The footer rests, not on the tray's note under the menu.
    w.profileButton:Click()
    Over(true, bp.tray, icon)
    Enter(icon)
    Leave(icon)
    local offIcon = Text()
    Over(nil, icon)
    Enter(bp.tray)
    Over(true, icon) -- an icon under the menu, where the mouse now is
    Leave(bp.tray)
    Equal(offIcon .. " | " .. Text(), ORANGE .. " | " .. ORANGE, "onto the profile menu off an icon, or off the tray over an icon: the credit")
    Over(nil, bp.tray, icon)
    w.profileButton:Click()

    -- The spell list's ticks say what ticking does.
    local function ListRow(name)
        for _, f in ipairs(frames) do
            if f.spell == name and S[f].shown then return f end
        end
    end
    Equal(NoteOf(ListRow("Moonfire").check), "Take Moonfire off Cooldowns.", "a ticked spell: untick to take it off")
    -- The tick's click area is its whole row: the spell's icon, name and
    -- rank say what ticking does too, and click it.
    local listRow = ListRow("Moonfire")
    local check, inset = listRow.check, function(i) return Last(listRow.check, "SetHitRectInsets", i) or 0 end
    local left = S[check].points[1][2]
    Equal(left + inset(1) == 0 and left + S[check].width - inset(2) == S[listRow].width
        and S[check].height - inset(3) - inset(4) == S[listRow].height and inset(3) == inset(4), true,
        "a spell's tick reaches across its whole row, and all the way down")
    -- A slider's note is on all of it, its label and value too.
    Equal(NoteOf(bp.spacing) .. " | " .. tostring(Last(bp.spacing, "EnableMouse")), "The room between this bar's icons. | true",
        "hovering a slider's label or value, its note")
    Equal(NoteOf(ListRow("Thorns").check), "Put Thorns on Cooldowns.", "an unticked one: tick to put it on")
    B:Assign("Thorns", "util")
    w:Refresh()
    Equal(NoteOf(ListRow("Thorns").check), "Move Thorns here from Utility.", "one on the other bar: ticking moves it")
    B:Assign("Thorns", nil)

    -- The profile menu: a row, its x, and back.
    w.profileButton:Click()
    local profileRow
    for _, f in ipairs(objects) do
        if rawget(f, "profile") and rawget(f, "remove") and Under(f, w) and f:IsVisible() then profileRow = f end
    end
    Over(true, profileRow)
    Enter(profileRow)
    local onRow = Text()
    Over(true, profileRow.remove)
    local onX = Move(profileRow, profileRow.remove)
    Over(nil, profileRow.remove)
    local rowBack = Move(profileRow.remove, profileRow)
    Equal(onRow .. " | " .. onX .. " | " .. rowBack, "The profile you're on. | Delete " .. profileRow.profile .. ". It asks first. | The profile you're on.",
        "a profile, its x, and back")
    -- Its x asks first: under the dialog's shade the footer rests, not on
    -- the covered profile's note, and stays so after Cancel.
    Over(true, profileRow.remove)
    Move(profileRow, profileRow.remove)
    profileRow.remove:Click()
    Leave(profileRow.remove)
    local asked = Text()
    w.confirm.no:Click()
    Equal(asked .. " | " .. Text(), ORANGE .. " | " .. ORANGE, "a profile's x, then Cancel: the credit, never the covered profile's note")
    Over(nil, profileRow, profileRow.remove)
    Leave(profileRow)

    -- The Look page's Turn on under an empty list says what it does too.
    w:Select("look")
    ns.loaded.skin = false
    w:Refresh()
    Equal(NoteOf(w.eachFix), "Reload your interface so the look takes effect.", "the list's Reload says what it does")
    ns.Set("skin", false)
    w:Refresh()
    Equal(NoteOf(w.eachFix), "Tick Apply this look to the Cooldown Manager above, then reload.", "and its Turn on")
    ns.Set("skin", true)
    ns.loaded.skin = true
    w:Refresh()

    -- Every button, text box, slider and anything else that takes the mouse
    -- in the window has a note (the "Are you sure?" dialog and the tour's box
    -- say everything themselves; the window, the profile menu and the
    -- dialog's shade are only the ground under the rest, as is the ?'s
    -- first-time note under its x; the ? has a tooltip of its own instead,
    -- Tools/TestHelp.lua), and on every page each one showing shows its note
    -- on hover and gives the footer back after.
    S[lp.search].scripts.OnEditFocusGained(lp.search) -- its results, made as they show
    S[lp.search].scripts.OnEditFocusLost(lp.search)
    local ground = { [w.profilePanel] = true, [w.confirm.shade] = true, [w.help] = true, [w.helpNudge] = true }
    if _G.FECMTour then ground[FECMTour] = true end
    local function Control(region)
        local s = S[region]
        if not s or ground[region] then return false end
        return s.kind == "Button" or s.kind == "EditBox" or rawget(region, "track") ~= nil
            or (s.parent and rawget(s.parent, "track") == region) or Last(region, "EnableMouse") == true
    end
    local controls, missing = {}, {}
    for _, region in ipairs(objects) do
        if Under(region, w) and Control(region) and not Under(region, w.confirm.shade)
            and not (_G.FECMTour and Under(region, FECMTour)) then
            controls[#controls + 1] = region
            if rawget(region, "hint") == nil then
                missing[#missing + 1] = S[region].kind .. ":" .. tostring(S[region].text or (region.label and S[region.label].text)) .. " "
            end
        end
    end
    Equal(table.concat(missing), "", "every button, text box, slider, list thumb and anything else taking the mouse in the window has a note")
    Equal(#controls > 150, true, "all of them checked (" .. #controls .. ")")
    local quiet, tried = {}, {}
    for _, key in ipairs({ "cd", "util", "buff", "debuff", "look", "layout", "cast", "general" }) do
        w:Select(key)
        w.profileButton:Click() -- the profile menu over each page, as it can be
        for _, control in ipairs(controls) do
            local areas, parent = {}, S[control].parent
            while parent and parent ~= w do
                areas[#areas + 1] = parent
                parent = S[parent].parent
            end
            Over(true, table.unpack(areas))
            Over(true, control)
            Enter(control)
            if control:IsVisible() then
                tried[control] = true
                local text = Text()
                if type(text) ~= "string" or text == "" or text:find("^Made with") then
                    quiet[#quiet + 1] = key .. ":" .. S[control].kind .. ":" .. tostring(text) .. " "
                end
            end
            Over(nil, control)
            Over(nil, table.unpack(areas))
            Leave(control)
            if Text() ~= ORANGE then quiet[#quiet + 1] = key .. " left on: " .. tostring(Text()) .. " " end
        end
        w.profileButton:Click()
    end
    local count = 0
    for _ in pairs(tried) do count = count + 1 end
    Equal(table.concat(quiet), "", "on every page, each control showing has its note on hover and gives the footer back")
    Equal(count > 120, true, "most of them showing on one page or another (" .. count .. ")")
    Equal(#printed, 0, "no errors")
end)()

-- Held over a bar from the spellbook or your bags -----------------------------------------
-- A spell or item on the game cursor, over a bar's drop target (a Layout row
-- or its icons, a bar page's tray or icons, a bar on screen while unlocked):
-- the footer says what dropping it there does, worked out without changing
-- anything, in the drop's own words. A drop turned away keeps saying why
-- while it's still held, wherever the mouse goes (a passive, Dodge, dragged
-- onto the Cooldowns row: the row's own note took the footer straight
-- back). Putting it away, picking up something else or closing the window
-- gives the footer back.
;(function()
    Environment()
    Display()
    local cursor, clears = nil, 0
    _G.GetCursorInfo = function() if cursor then return cursor[1], cursor[2], cursor[3], cursor[4] end end
    _G.ClearCursor = function() cursor, clears = nil, clears + 1 end
    bagItems = { { itemID = 118, hyperlink = "|cffffffff|Hitem:118|h[Minor Healing Potion]|h|r", iconFileID = 888 } }
    itemCount[118] = 1
    local ns = Load({ useBars = true, notesSeen = "dev", prdSkin = false })
    local names = { [81] = "Dodge", [5176] = "Wrath", [8921] = "Moonfire", [467] = "Thorns", [16870] = "Clearcasting",
        [1243] = "Power Word: Fortitude" }
    _G.C_Spell.GetSpellName = function(id) return names[id] end
    local B = ns.Bars
    B:Assign("Moonfire", "cd")
    SlashCmdList.FECM("")
    local w = FECMFrame
    w:Select("layout")
    local lp = w.pages.layout
    local rows = lp.rows
    local function Footer() return S[w.note].text end
    local function Enter(control) S[control].scripts.OnEnter(control) end
    local function Leave(control) S[control].scripts.OnLeave(control) end
    local function Own(control)
        local hint = rawget(control, "hint")
        if type(hint) == "function" then hint = hint(control) end
        return hint
    end
    -- Every bar's list and what's remembered, to show nothing changed.
    local function State()
        local parts = {}
        for _, key in ipairs(ns.BAR_KEYS) do parts[#parts + 1] = key .. "=" .. table.concat(ns.BarData(key).spells, ",") end
        local custom = {}
        for name, ids in pairs(ns.CustomSpells()) do custom[#custom + 1] = name .. ":" .. table.concat(ids, ",") end
        table.sort(custom)
        return table.concat(parts, " ") .. " | " .. table.concat(custom, " ")
    end
    -- Held over a control: what the footer says. Nothing changes, and it
    -- stays on the cursor.
    local function Over(control, held)
        cursor = held
        local before, cleared = State(), clears
        S[control].mouseOver = true
        Enter(control)
        local text = Footer()
        S[control].mouseOver = nil
        Leave(control)
        Equal(State() .. " " .. clears .. " " .. tostring(cursor == held), before .. " " .. cleared .. " true",
            "held over it, nothing changes and it stays on the cursor (" .. tostring(text) .. ")")
        return text
    end
    local DODGE, WRATH, MOONFIRE, THORNS = { "spell", 1, "spell", 81 }, { "spell", 2, "spell", 5176 },
        { "spell", 3, "spell", 8921 }, { "spell", 4, "spell", 467 }
    local PASSIVE = "Dodge is passive, so there's nothing to track."
    local HINT = Own(rows.cd)

    -- The Layout page's rows and their icons.
    Equal(rows.cd:IsVisible() and rows.cd.tiles[1]:IsVisible() and rows.util:IsVisible() and rows.buff:IsVisible(), true,
        "the Layout page's rows showing")
    Equal(Over(rows.cd, DODGE), PASSIVE, "a passive held over the Cooldowns row: the footer says why it can't go there")
    Equal(Over(rows.cd.tiles[1], DODGE), PASSIVE, "over an icon in the row too")
    Equal(Over(rows.buff, { "item", 118 }), "Items can't go on the Buffs bar.", "an item held over the Buffs row")
    Equal(Over(rows.util, WRATH), "Drop to add Wrath to Utility.", "a spell held over the Utility row: what dropping does")
    Equal(Over(rows.cd.tiles[1], WRATH), "Drop to add Wrath to Cooldowns.", "over a Cooldowns icon: added to that bar")
    Equal(Over(rows.cd, MOONFIRE), "Moonfire is already on Cooldowns.", "one already on that bar")
    Equal(Over(rows.util, MOONFIRE), "Drop to move Moonfire from Cooldowns to Utility.", "one on the other cooldown bar moves")
    Equal(Over(rows.buff, THORNS), "Drop to add Thorns to Buffs.", "a buff over the Buffs row")
    Equal(Over(rows.cd, { "item", 118 }), "Drop to add Healing Potions to Cooldowns.", "a potion from your bags")
    Equal(Over(rows.cd, { "macro", 4 }), "Only spells and items can go on a bar.", "anything else")
    Equal(Over(rows.cd, { "spell", 1, "spell", SECRETS.number }) .. " " .. Over(rows.cd, { SECRETS.string, 118 }),
        "Only spells and items can go on a bar. Only spells and items can go on a bar.", "what the game won't say")
    Equal(Over(rows.cd, nil) .. " | " .. Over(rows.cd.tiles[1], nil), HINT .. " | " .. Own(rows.cd.tiles[1]),
        "with nothing held, the row's and the icon's own notes")
    -- Full: the Utility bar's list, then the Buffs bar's slots for your own icons.
    local util = ns.BarData("util").spells
    for i = 1, ns.BAR_MAX_SPELLS do util[i] = "Filler " .. i end
    B:Changed()
    w:Refresh()
    Equal(Over(rows.util, WRATH), "Utility is full.", "a full bar says so")
    cursor = WRATH
    S[rows.util].scripts.OnReceiveDrag(rows.util)
    Equal(Footer() .. " " .. tostring(cursor == WRATH), "Utility is full. true", "and so does the drop, leaving it on the cursor")
    for i = #util, 1, -1 do util[i] = nil end
    local buff, custom = ns.BarData("buff").spells, ns.CustomSpells()
    for i = 1, ns.BUFF_SLOTS do
        buff[i] = "Filler " .. i
        custom["Filler " .. i] = { 900000 + i }
    end
    B:Changed()
    w:Refresh()
    Equal(B:SlotsUsed("buff") .. " " .. #buff, ns.BUFF_SLOTS .. " " .. ns.BUFF_SLOTS, "every Buffs slot taken, the list has room")
    Equal(Over(rows.buff, THORNS), "Buffs is full.", "a Buffs bar with every slot taken says so")
    cursor = THORNS
    S[rows.buff].scripts.OnReceiveDrag(rows.buff)
    Equal(Footer() .. " " .. tostring(cursor == THORNS) .. " " .. #buff, "Buffs is full. true " .. ns.BUFF_SLOTS, "and so does the drop")
    for i = #buff, 1, -1 do buff[i] = nil end
    B:Changed()
    w:Refresh()
    cursor = nil

    -- Dropped and turned away, it stays on the cursor, and so does why, as
    -- the mouse moves between the row, its icons and its buttons, and
    -- anywhere else in the window; a click there tries again.
    cursor = DODGE
    S[rows.cd].mouseOver = true
    Enter(rows.cd)
    S[rows.cd].scripts.OnReceiveDrag(rows.cd)
    Equal(Footer() .. " " .. tostring(cursor == DODGE) .. " " .. clears, PASSIVE .. " true 0",
        "dropped on the Cooldowns row: turned away, saying why, still on the cursor")
    local trail = {}
    for _, control in ipairs({ rows.cd.tiles[1], rows.cd, rows.cd.wider, rows.cd.up, rows.cd.out, rows.cd.tiles[1], lp.unlock }) do
        Enter(control)
        trail[#trail + 1] = Footer()
        Leave(control)
        trail[#trail + 1] = Footer()
    end
    local kept = true
    for _, text in ipairs(trail) do kept = kept and text == PASSIVE end
    Equal(kept, true, "why stays in the footer over its icons, the row, its buttons and elsewhere (" .. table.concat(trail, " / ") .. ")")
    Equal(rows.cd.wider:IsVisible(), true, "the row's buttons were up")
    rows.cd:Click()
    Equal(Footer() .. " " .. tostring(cursor == DODGE), PASSIVE .. " true", "clicked to drop it in: the same answer")
    Enter(rows.cd.tiles[1])
    Equal(Footer(), PASSIVE, "and over the icon after")
    Leave(rows.cd.tiles[1])
    -- Put away: the footer goes back at once, wherever the mouse is.
    Enter(rows.cd.wider)
    Equal(Footer(), PASSIVE, "held over the + button: why it was turned away")
    cursor = nil
    Fire("CURSOR_CHANGED", true, 0, 4, 0)
    Equal(Footer(), Own(rows.cd.wider), "put away: the + button's own note, at once")
    Leave(rows.cd.wider)
    Enter(rows.cd)
    Equal(Footer(), HINT, "and the row's over the row")
    -- Picked up again, nothing has been turned away yet: the button's note.
    Enter(rows.cd.wider)
    cursor = DODGE
    Fire("CURSOR_CHANGED", false, 4, 0, 0)
    Equal(Footer(), Own(rows.cd.wider), "Dodge picked up again: the + button keeps its own note")
    Leave(rows.cd.wider)
    -- Turned away, then something else picked up: that's held now.
    Enter(rows.cd)
    S[rows.cd].scripts.OnReceiveDrag(rows.cd)
    Equal(Footer(), PASSIVE, "turned away again")
    cursor = WRATH
    Fire("CURSOR_CHANGED", false, 4, 4, 0)
    Equal(Footer(), "Drop to add Wrath to Cooldowns.", "Wrath picked up instead, over the row: what dropping it does")
    Enter(rows.cd.wider)
    Equal(Footer(), Own(rows.cd.wider), "and the + button's own note: Dodge's answer is gone with it")
    Leave(rows.cd.wider)
    -- Closing the window lets go of why, though Dodge is still held.
    cursor = DODGE
    Enter(rows.cd)
    S[rows.cd].scripts.OnReceiveDrag(rows.cd)
    Leave(rows.cd)
    Equal(Footer(), PASSIVE, "turned away, off the row")
    w:Hide()
    w:Show()
    w:Select("layout")
    Enter(rows.cd.wider)
    Equal(Footer(), Own(rows.cd.wider), "the window closed and opened again: the + button's own note")
    Leave(rows.cd.wider)
    S[rows.cd].mouseOver = nil
    Leave(rows.cd)
    Equal(S[w.cursorWatch].events.CURSOR_CHANGED, true, "the footer hears the cursor change")
    -- Already on that bar: put away as before, saying so.
    cursor = MOONFIRE
    S[rows.cd].scripts.OnReceiveDrag(rows.cd)
    Equal(Footer() .. " " .. tostring(cursor) .. " " .. table.concat(ns.BarData("cd").spells, ","),
        "Moonfire is already on Cooldowns. nil Moonfire", "Moonfire dropped on Cooldowns again: already there, and let go of")
    Equal(select(2, B:Add("cd", "Moonfire")), "Moonfire is already on Cooldowns.", "typed too")
    -- Put away with the mouse never moving onto anything new (still on the
    -- row it was dropped on, or out over empty space): why goes with it,
    -- rather than staying on as the last message.
    cursor = DODGE
    S[rows.cd].mouseOver = true
    Enter(rows.cd)
    S[rows.cd].scripts.OnReceiveDrag(rows.cd)
    Equal(Footer(), PASSIVE, "Dodge dropped on the row and turned away")
    cursor = nil
    Fire("CURSOR_CHANGED", true, 0, 4, 0)
    Equal(Footer(), HINT, "put away, the mouse still on the row: the row's own note, not why")
    S[rows.cd].mouseOver = nil
    Leave(rows.cd)
    Equal(Footer():find("^Made with") ~= nil, true, "then off the row: the footer rests, why gone with it (" .. tostring(Footer()) .. ")")
    cursor = DODGE
    S[rows.cd].mouseOver = true
    Enter(rows.cd)
    rows.cd:Click()
    Equal(Footer(), PASSIVE, "clicked in: turned away again")
    S[rows.cd].mouseOver = nil
    Leave(rows.cd)
    Equal(Footer(), PASSIVE, "off the row onto empty space, still held: why")
    cursor = nil
    Fire("CURSOR_CHANGED", true, 0, 4, 0)
    Equal(Footer():find("^Made with") ~= nil and Footer() == w.lastNote, true,
        "put away there: the footer rests on the credit, why gone with it (" .. tostring(Footer()) .. ")")
    -- The game says the cursor changed as a drop lets go of it, before the
    -- drop says what it did: that's what the footer shows.
    local clear = _G.ClearCursor
    _G.ClearCursor = function()
        clear()
        Fire("CURSOR_CHANGED", true, 0, 4, 0)
    end
    cursor = WRATH
    S[rows.util].mouseOver = true
    Enter(rows.util)
    S[rows.util].scripts.OnReceiveDrag(rows.util)
    Equal(Footer() .. " " .. tostring(cursor), "Added Wrath to Utility. nil", "Wrath dropped on Utility: added, and said")
    S[rows.util].mouseOver = nil
    Leave(rows.util)
    Equal(Footer(), "Added Wrath to Utility.", "and still said off the row")
    _G.ClearCursor = clear
    B:Assign("Wrath", nil)
    w:Refresh()

    -- A bar's page: its tray and icons.
    w:Select("cd")
    local page = w.pages.bar
    Equal(Over(page.tray, DODGE), PASSIVE, "the Cooldowns page's tray")
    Equal(Over(page.tray, WRATH), "Drop to add Wrath to Cooldowns.", "a spell held over it")
    Equal(page.icons[1]:IsVisible(), true, "Moonfire's icon showing")
    Equal(Over(page.icons[1], WRATH), "Drop to add Wrath to Cooldowns.", "and over its icons")
    cursor = DODGE
    S[page.tray].scripts.OnReceiveDrag(page.tray)
    Enter(page.icons[1])
    Equal(Footer(), PASSIVE, "dropped on the tray and turned away, why stays over its icons")
    Leave(page.icons[1])
    Enter(page.icons[1].remove)
    Equal(Footer(), PASSIVE, "and over an icon's x")
    Leave(page.icons[1].remove)
    -- Clicked onto an icon, as onto the tray round it: dropped there.
    page.icons[1]:Click()
    Equal(Footer() .. " " .. tostring(cursor == DODGE) .. " " .. table.concat(ns.BarData("cd").spells, ","),
        PASSIVE .. " true Moonfire", "Dodge clicked onto an icon: turned away, still held")
    cursor = WRATH
    page.icons[1]:Click()
    Equal(Footer() .. " " .. tostring(cursor) .. " " .. table.concat(ns.BarData("cd").spells, ","),
        "Added Wrath to Cooldowns. nil Moonfire,Wrath", "Wrath clicked onto an icon: added, and let go of")
    B:Assign("Wrath", nil)
    w:Refresh()
    page.icons[1]:Click()
    Equal(table.concat(ns.BarData("cd").spells, ",") .. " " .. tostring(cursor), "Moonfire nil",
        "an icon clicked with nothing held: nothing changes")
    cursor = nil
    Fire("CURSOR_CHANGED", true, 0, 4, 0)
    w:Select("buff")
    Equal(Over(page.tray, { "item", 118 }), "Items can't go on the Buffs bar.", "the Buffs page: no items")
    Equal(Over(page.tray, nil), Own(page.tray), "nothing held: the tray's own note")
    -- A bar on screen while unlocked.
    w:Select("layout")
    lp.unlock:Click()
    local mover = B:Get("cd").mover
    Equal(mover:IsVisible(), true, "the Cooldowns bar unlocked")
    Equal(Over(mover, WRATH), "Drop to add Wrath to Cooldowns.", "a spell held over a bar on screen")
    Equal(Over(mover, DODGE), PASSIVE, "a passive")
    lp.unlock:Click()
    -- In a fight: the same answers, and nothing touched.
    lockdown = true
    local calls = containerCallsInCombat
    Equal(Over(rows.buff, THORNS) .. " " .. Over(rows.cd, DODGE), "Drop to add Thorns to Buffs. " .. PASSIVE, "in a fight too")
    Equal(containerCallsInCombat, calls, "nothing on the Buffs bar touched in the fight")
    lockdown = false
    cursor = nil

    -- An item already on that bar says so too, held and dropped.
    B:Assign("family:healing", "cd")
    Equal(Over(rows.cd, { "item", 118 }), "Healing Potions is already on Cooldowns.", "a potion already on that bar")
    cursor = { "item", 118 }
    S[rows.cd].scripts.OnReceiveDrag(rows.cd)
    Equal(Footer() .. " " .. tostring(cursor) .. " " .. table.concat(ns.BarData("cd").spells, ","),
        "Healing Potions is already on Cooldowns. nil Moonfire,family:healing", "dropped: already there, and let go of")
    -- A name kept without IDs (another character's), given one: it goes on
    -- with that ID, not "already there".
    local util = ns.BarData("util").spells
    util[1] = "Power Word: Fortitude"
    B:Changed()
    Equal(Over(rows.util, { "spell", 6, "spell", 1243 }), "Drop to add Power Word: Fortitude to Utility.",
        "a name on the bar with nothing to show it by, given its ID: added")
    util[1] = nil
    B:Changed()

    -- What the footer says before a drop is what the drop does, for every bar
    -- and anything held: turned away with the same words, or put on (or
    -- already there) as said.
    local function Save()
        local saved = { custom = {} }
        for _, key in ipairs(ns.BAR_KEYS) do saved[key] = { table.unpack(ns.BarData(key).spells) } end
        for name, ids in pairs(ns.CustomSpells()) do saved.custom[name] = { table.unpack(ids) } end
        return saved
    end
    local function Restore(saved)
        for _, key in ipairs(ns.BAR_KEYS) do
            local spells = ns.BarData(key).spells
            for i = #spells, 1, -1 do spells[i] = nil end
            for i, name in ipairs(saved[key]) do spells[i] = name end
        end
        local now = ns.CustomSpells()
        for name in pairs(now) do now[name] = nil end
        for name, ids in pairs(saved.custom) do now[name] = { table.unpack(ids) } end
        B:Changed()
    end
    -- The drop's own words for what was said before it.
    local function Done(said)
        local name, bar = said:match("^Drop to add (.+) to (%a+)%.$")
        if not name then name, bar = said:match("^Drop to move (.+) from %a+ to (%a+)%.$") end
        return name and ("Added " .. name .. " to " .. bar .. ".") or said
    end
    local held = { DODGE, WRATH, MOONFIRE, THORNS, { "spell", 5, "spell", 16870 }, { "spell", 6, "spell", 1243 },
        { "spell", 7, "spell", 99999 }, { "item", 118 }, { "item", 117 }, { "item", 2516 }, { "item", 11111 },
        { "macro", 4 }, { "spell", 1, "spell", SECRETS.number }, { SECRETS.string, 118 } }
    local base = Save()
    local before = State()
    local differ, kinds = {}, {}
    for _, key in ipairs(ns.BAR_KEYS) do
        for _, thing in ipairs(held) do
            cursor = thing
            local can, said = B:CursorNote(key)
            local unchanged = State() == before and cursor == thing
            local ok, message = B:AddFromCursor(key)
            local expected = can and Done(said) or said
            local agree = can == ok and type(message) == "string" and message:sub(1, #expected) == expected
                and (ok or message == said) and unchanged and (ok == (cursor == nil))
            if not agree then
                differ[#differ + 1] = key .. " " .. tostring(thing[4] or thing[2]) .. ": " .. tostring(said) .. " / " .. tostring(message)
            end
            kinds[(can and (said:find("^Drop to") and "drop" or "already")) or "refused"] = true
            Restore(base)
        end
    end
    Equal(table.concat(differ, "; "), "", "on every bar, what's said before a drop is what the drop does")
    Equal(tostring(kinds.drop) .. " " .. tostring(kinds.already) .. " " .. tostring(kinds.refused), "true true true",
        "added, already there and turned away all tried")
    cursor = nil
    Equal(B:CursorNote("cd"), nil, "nothing held: nothing to say")
    Equal(#printed, 0, "no errors")
end)()

-- Buff and debuff times on the cooldown icons, as Blizzard's Cooldown Manager
-- shows them (a player: "not able to track Shadow Word: Pain duration like in
-- the baseline cooldown manager"), and debuffs on you on the Buffs bar ("not
-- able to track the Weakened Soul Debuff"). ---------------------------------------
;(function()
    Environment()
    ns = Load({ useBars = true })
    B = ns.Bars
    B:Assign("Moonfire", "cd")
    B:AddItem("cd", 5512)
    local cd = B:Get("cd")
    Equal(tostring(cd.auraContainers) .. " " .. tostring(ns.BarData("cd").showAuras), "nil false", "off at first: nothing made")
    B:SetOption("cd", "showAuras", true)
    local made = cd.auraContainers
    Equal(made and (S[made.p].unit .. " " .. S[made.t].unit), "player target", "ticked: one container for you, one for your target")
    local p1, t1 = S[made.p].slots.p1, S[made.t].slots.t1
    Equal(p1.filter .. " " .. t1.filter, "HELPFUL HARMFUL", "a buff on you, a debuff on your target")
    Equal(tostring(t1.enabled) .. " " .. tostring(t1.filters.includeSpellIDs[8921] and t1.filters.includeSpellIDs[8924])
        .. " " .. tostring(t1.filters.isFromPlayerOrPlayerPet), "true true true", "every rank of Moonfire, only yours")
    Equal(t1.supplied.SetIcon ~= nil and t1.supplied.SetDurationCooldown ~= nil and t1.supplied.SetApplicationCount ~= nil, true,
        "with its icon, time and stacks")
    Equal(Last(cd.auraAnchors[1], "SetAllPoints") == cd.icons[1], true, "laid over Moonfire's icon")
    local item = S[made.t].slots.t2
    Equal(item == nil or item.enabled == false, true, "an item puts no aura on anyone: no time over it")
    Equal(containerCallsInCombat, 0, "nothing set up in a fight")
    -- An icon moving in a fight takes its time with it, by name.
    B:SetOption("cd", "showAuras", false)
    Equal(tostring(S[made.p].slots.p1.enabled) .. " " .. tostring(S[made.t].slots.t1.enabled), "false false",
        "unticked: both switched off")
    lockdown = true
    B:SetOption("cd", "showAuras", true)
    Equal(tostring(containerCallsInCombat) .. " " .. tostring(cd.auraPending), "0 true", "ticked in a fight: waits for it to end")
    lockdown = false
    Fire("PLAYER_REGEN_ENABLED")
    Equal(tostring(S[made.t].slots.t1.enabled) .. " " .. tostring(cd.auraPending), "true nil", "and switches on once it's over")
    -- First ticked in a fight on a bar with none made yet: made as it ends.
    B:Assign("Wrath", "util")
    local util = B:Get("util")
    lockdown = true
    B:SetOption("util", "showAuras", true)
    Equal(tostring(util.auraContainers) .. " " .. tostring(util.auraPending), "nil true", "nothing made in a fight")
    lockdown = false
    Fire("PLAYER_REGEN_ENABLED")
    Equal(util.auraContainers ~= nil and S[util.auraContainers.t].slots.t1.enabled, true, "made once it's over")
    -- A new target: the debuff side looks again at once.
    local refreshes = S[made.t].refreshes or 0
    Fire("PLAYER_TARGET_CHANGED")
    Equal((S[made.t].refreshes or 0) - refreshes, 1, "a new target is looked at again")
    Equal(#printed, 0, "no errors from buff and debuff times")

    -- Debuffs you put on yourself on the Buffs bar: the game won't let an
    -- addon pick out a debuff on you by spell ID, only by who cast it, so it's
    -- one group for all of yours, after your buffs.
    B:SetAura("buff", "Thorns", true)
    local buff = B:Get("buff")
    local groups = S[buff.container].groups
    Equal(tostring(groups.self) .. " " .. tostring(ns.BarData("buff").selfDebuffs), "nil false", "off at first: no group")
    B:SetOption("buff", "selfDebuffs", true)
    local own = groups.self
    Equal(own and (own.filter .. " " .. tostring(own.enabled) .. " " .. tostring(own.filters.isFromPlayerOrPlayerPet)
        .. " " .. tostring(own.filters.includeSpellIDs)), "HARMFUL true true nil", "ticked: your debuffs on you, by who cast them, no spell IDs")
    Equal(own.layout.layoutIndex > groups.g1.layout.layoutIndex, true, "after your buffs")
    B:SetOption("buff", "grow", "left")
    Equal(groups.self.layout.layoutIndex < groups.g1.layout.layoutIndex, true, "growing left: before them, at the far end")
    B:SetOption("buff", "grow", "centre")
    B:SetOption("buff", "showMissing", true)
    Equal(groups.self.enabled, false, "fixed spots: off, they belong to entries")
    B:SetOption("buff", "showMissing", false)
    Equal(groups.self.enabled, true, "packed again: back on")
    -- With nothing else on the Buffs bar, it still shows for them.
    B:SetAura("buff", "Thorns", false)
    Equal(tostring(InSight(buff)) .. " " .. tostring(groups.self.enabled), "true true", "an empty Buffs bar still shows your debuffs")
    lockdown = true
    B:SetOption("buff", "selfDebuffs", false)
    Equal(tostring(containerCallsInCombat) .. " " .. tostring(groups.self.enabled), "0 true", "unticked in a fight: waits")
    lockdown = false
    Fire("PLAYER_REGEN_ENABLED")
    Equal(groups.self.enabled, false, "and goes once it's over")
    -- Added by name or ID (a player added Weakened Soul and it never showed):
    -- turned away, pointing to the tick.
    local note = ns.Spells:SelfDebuffNote("Weakened Soul")
    Equal(note ~= nil and note:find("Show your debuffs on you", 1, true) ~= nil, true, "Weakened Soul points to the tick")
    Equal(ns.Spells:SelfDebuffNote(" weakened soul ") == note and ns.Spells:SelfDebuffNote("6788") == note
        and ns.Spells:SelfDebuffNote(6788) == note, true, "by any case, by ID, as a number")
    Equal(ns.Spells:SelfDebuffNote("Recently Bandaged") ~= nil and ns.Spells:SelfDebuffNote("25771") ~= nil, true,
        "Recently Bandaged and Forbearance too")
    Equal(ns.Spells:SelfDebuffNote("Power Word: Shield") == nil and ns.Spells:SelfDebuffNote("Thorns") == nil, true,
        "a buff is no debuff on you")
    for _, bar in ipairs({ "buff", "debuff", "cd" }) do
        local ok, said = B:Add(bar, "Weakened Soul")
        Equal(tostring(ok) .. " " .. tostring(said == note), "false true", "not added to " .. bar .. ": told where it shows")
    end
    Equal(B:CanAdd("buff", "6788"), false, "held over a bar: the same")
    Equal(ns.Spells:SelfDebuffMatch("weak") == note and ns.Spells:SelfDebuffMatch("we") == nil
        and ns.Spells:SelfDebuffMatch("moon") == nil, true, "typing: from three letters")
    Equal(#printed, 0, "no errors from debuffs on you")
end)()

-- Blizzard's aura containers never run the addon's code while they update
-- (thousands of errors, 2026-10-06; a look run in the middle of an update was
-- suspected). The only addon code a container runs is a look
-- (initializeFrame), on each icon it makes: here they're all made as their
-- slot or group is added, a group never shows more than were made then, and a
-- look called at any other time does nothing. ----------------------------------
;(function()
    local function Count(field)
        local total = 0
        for _, container in ipairs(containers) do total = total + S[container][field] end
        return total
    end
    -- The mock game makes icons mid-update like the game: a group shown more
    -- auras than its ten makes ten more then, running its look, here a
    -- guarded one of the addon's. Called outside an add, it does nothing.
    Environment()
    ns = Load({ useBars = true })
    local box = CreateFrame("AuraContainer", nil, UIParent, "CustomAuraContainerTemplate")
    local looks = 0
    box:AddAuraGroup("x", "HELPFUL", { maxFrameCount = 12, initializeFrame = ns.BuffBar.Guard(function() looks = looks + 1 end) })
    local twelve = {}
    for i = 1, 12 do twelve[i] = { id = i } end
    S[box].Update(twelve)
    Equal(S[box].late .. " " .. tostring(S[box].addonCalls > 0) .. " " .. looks, "10 true 0",
        "a group past its ten makes more mid-update, and the addon's code runs then; a guarded look does nothing")

    -- Every aura feature on: the Buffs bar packed, with your debuffs on you,
    -- the Debuffs bar, and buff and debuff times on the Cooldowns bar.
    Environment()
    ns = Load({ useBars = true })
    B = ns.Bars
    B:SetAura("buff", "Thorns", true)
    B:SetAura("buff", "Clearcasting", true)
    B:SetOption("buff", "selfDebuffs", true)
    B:SetAura("debuff", "Moonfire", true)
    B:Assign("Moonfire", "cd")
    B:SetOption("cd", "showAuras", true)
    local buff = B:Get("buff")
    local groups = S[buff.container].groups
    Equal(groups.g1.max .. " " .. groups.g2.max .. " " .. groups.self.max .. " " .. #groups.self.frames, "1 1 4 10",
        "each group shows at most what was made as it was added")
    local bare = 0
    for _, container in ipairs(containers) do
        for _, slot in pairs(S[container].slots) do if not slot.supplied.SetIcon then bare = bare + 1 end end
        for _, group in pairs(S[container].groups) do
            for _, button in ipairs(group.frames) do if not S[button].supplied.SetIcon then bare = bare + 1 end end
        end
    end
    Equal(Count("made") > 40 and bare, 0, "every icon made has its look, given as its slot or group was added")
    -- Lots of auras, changing each time, in and out of a fight and across
    -- target changes: your buffs, Moonfire on the target, and twenty debuffs
    -- of yours on you.
    local made = Count("made")
    local auras = { { id = 467 }, { id = 16870 }, { id = 8921, harmful = true, mine = true } }
    for i = 1, 20 do auras[#auras + 1] = { id = 90000 + i, harmful = true, mine = true } end
    for round = 1, 6 do
        if round == 3 then Fire("PLAYER_REGEN_DISABLED"); lockdown = true end
        if round == 5 then lockdown = false; Fire("PLAYER_REGEN_ENABLED") end
        target, hostile = round % 2 == 0, true
        Fire("PLAYER_TARGET_CHANGED")
        for _, container in ipairs(containers) do S[container].Update(auras) end
        table.remove(auras)
    end
    Equal(#groups.self.active .. " " .. #groups.g1.active .. " " .. #S[B:Get("debuff").container].groups.g1.active, "4 1 1",
        "the groups show what they match")
    Equal(Count("late") .. " " .. Count("addonCalls") .. " " .. (Count("made") - made), "0 0 0",
        "no icon made, and none of the addon's code run, while the containers update")

    -- A game making fewer icons up front: a group is held to the ones made.
    Environment()
    ns = Load({ useBars = true })
    B = ns.Bars
    buff = B:Get("buff")
    local container = buff.container
    S[container].batch = 2
    B:SetAura("buff", "Thorns", true)
    B:SetOption("buff", "selfDebuffs", true)
    local own = S[container].groups.self
    Equal(own.max .. " " .. #own.frames .. " " .. S[container].groups.g1.max .. " " .. #buff.groupParts, "2 2 1 4",
        "held to the two made, each with its look")
    local mine = {}
    for i = 1, 6 do mine[i] = { id = 90000 + i, harmful = true, mine = true } end
    S[container].Update(mine)
    Equal(S[container].late .. " " .. S[container].addonCalls .. " " .. #own.active, "0 0 2", "nothing made or run mid-update")
    -- Unheld, the game would make more mid-update and call the look then: it
    -- does nothing, so those icons go without it.
    local parts = #buff.groupParts
    container:SetAuraGroupMaxFrameCount("self", 4)
    S[container].Update(mine)
    Equal(S[container].late .. " " .. tostring(S[container].addonCalls > 0) .. " " .. (#buff.groupParts - parts) .. " "
        .. tostring(next(S[own.frames[#own.frames]].supplied)), "2 true 0 nil", "a look called mid-update does nothing")
    -- An add that fails still shuts the looks off after it.
    local ok = pcall(ns.BuffBar.Add, container, "AddAuraGroup", "self", "HARMFUL", { maxFrameCount = 1 })
    local ran = false
    ns.BuffBar.Guard(function() ran = true end)(UIParent)
    Equal(tostring(ok) .. " " .. tostring(ran), "false false", "a failed add leaves looks shut off")
    Equal(#printed, 0, "no errors from the aura containers")
end)()

print = _G.print
Equal(SecretMisuse[1], nil, "no secret misused anywhere")
io.write("Bars and window checks passed: " .. checks .. " assertions.\n")
