-- What of Blizzard's own code runs inside the addon's: the secure aura
-- containers' own OnShow and OnHide (the open taint lead of 2026-10-07: the
-- addon showing or hiding the bars that hold them), and the secrets the
-- game keeps in a fight. The mock game is a copy of Tools/TestBars.lua's:
-- Tools/TestMockSync.mjs checks the two match, and with --write copies it
-- across. Tools/TestBars.lua is near the mock game's memory limit, so these
-- run here.
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

-- Aura containers: the game around it --------------------------------------------------------------

local function Fresh()
    Environment()
    _G.hooksecurefunc = function(t, key, hook)
        local original = t[key]
        rawset(t, key, function(...)
            if original then original(...) end
            hook(...)
        end)
    end
    _G.FECMFrame, _G.FECMTour, _G.FECMNotes, _G.FECMDebugFrame = nil, nil, nil, nil
end
-- Blizzard's container code run inside the addon's since the last ask, in
-- order, then forgotten.
local function Runs()
    local text = table.concat(ContainerRuns, " | ")
    for i = #ContainerRuns, 1, -1 do ContainerRuns[i] = nil end
    return text
end


-- The mock game shows and hides as the game does ----------------------------------------------------

do
    Fresh()
    local seen = {}
    local function Watch(frame, name)
        frame:SetScript("OnShow", function() seen[#seen + 1] = name .. " shown" end)
        frame:SetScript("OnHide", function() seen[#seen + 1] = name .. " hidden" end)
    end
    local function Seen()
        local text = table.concat(seen, ", ")
        seen = {}
        return text
    end
    local outer = CreateFrame("Frame", nil, UIParent)
    local inner = CreateFrame("Frame", nil, outer)
    local deep = CreateFrame("Frame", nil, inner)
    Watch(outer, "outer")
    Watch(inner, "inner")
    Watch(deep, "deep")
    outer:Hide()
    Equal(Seen(), "outer hidden, inner hidden, deep hidden", "hiding a frame runs OnHide on it and every shown frame inside it")
    outer:Show()
    Equal(Seen(), "outer shown, inner shown, deep shown", "and showing it runs their OnShow")
    outer:Hide()
    Seen()
    inner:Hide()
    Equal(Seen(), "", "a frame hidden inside a hidden one: nothing runs")
    deep:Hide()
    deep:Show()
    outer:Show()
    Equal(Seen(), "outer shown", "a frame still hidden inside it gets no OnShow, nor anything inside that")
    inner:Show()
    Equal(Seen(), "inner shown, deep shown", "until it shows itself")
    inner:Show()
    Equal(Seen(), "", "showing a shown frame runs nothing")
    -- Moved into a hidden frame, it goes with that one.
    local holder = CreateFrame("Frame", nil, UIParent)
    holder:Hide()
    inner:SetParent(holder)
    holder:Show()
    Equal(Seen() .. " " .. tostring(Last(inner, "SetParent") == holder), "inner shown, deep shown true",
        "a frame moved into another follows that one")
    outer:Hide()
    Equal(Seen(), "outer hidden", "and no longer the one it left")

    -- A container's own OnShow and OnHide are Blizzard's, run inside
    -- whatever code showed or hid it. The tests' own code isn't the addon's.
    local bar = CreateFrame("Frame", nil, UIParent)
    local container = CreateFrame("AuraContainer", nil, bar, "CustomAuraContainerTemplate")
    bar:Hide()
    bar:Show()
    Equal(S[container].intrinsic .. " [" .. Runs() .. "]", "2 []", "its OnHide and OnShow ran, with no addon code on the stack")
    -- Code loaded from an addon file showing it: noted, with the function
    -- that did it and whether it was in a fight.
    local addon = assert(load("local bar = ... local function ShowBars() bar:Hide() bar:Show() end ShowBars()", "@Fake.lua"))
    addon(bar)
    lockdown = true
    addon(bar)
    lockdown = false
    Equal(Runs(), "OnHide Fake.lua ShowBars | OnShow Fake.lua ShowBars | OnHide Fake.lua ShowBars in a fight"
        .. " | OnShow Fake.lua ShowBars in a fight", "inside an addon's code: each run noted, with the function and the fight")
    Equal(#printed, 0, "no errors")
end

-- The mock game's secrets act like the game's ----------------------------------------------------------

do
    Fresh()
    local number, boolean, text = SECRETS.number, SECRETS.boolean, SECRETS.string
    Equal(type(number) .. " " .. type(boolean) .. " " .. type(text) .. " " .. type(SECRET) .. " " .. type(4) .. " " .. type({}),
        "number boolean string table number table", "type() says what a secret stands for, as the game's does")
    Equal(tostring(issecretvalue(number)) .. " " .. tostring(issecretvalue(SECRET)) .. " " .. tostring(issecretvalue(4))
        .. " " .. tostring(issecretvalue({})), "true true false false", "issecretvalue knows them all, and only them")
    trinketCooldown, range[8924] = { SECRET, SECRET, 1 }, SECRET
    local start, length, enable = GetInventoryItemCooldown("player", 13)
    Equal(tostring(rawequal(start, number)) .. " " .. tostring(rawequal(length, number)) .. " " .. enable .. " "
        .. tostring(rawequal(C_Spell.IsSpellInRange(8924, "target"), boolean)), "true true 1 true",
        "the mock game hands back a secret of the kind each API returns")
    -- Every way the addon's code could use one errors, and is noted.
    local uses = {
        "return s > 0", "return 0 <= s", "return s + 1", "return -s", "return s .. ''", "return #s", "return s.x",
        "s.x = 1", "local r = s() return r", "return tostring(s)", "return string.format('%s', s)", "for _ in pairs(s) do end",
        "return s == SECRETS.string",
    }
    local errors = {}
    for _, use in ipairs(uses) do
        local before = #SecretMisuse
        if pcall(assert(load("local s = ... " .. use, "@Fake.lua")), number) then
            errors[#errors + 1] = "no error: " .. use
        elseif #SecretMisuse ~= before + 1 then
            errors[#errors + 1] = "noted " .. (#SecretMisuse - before) .. " times: " .. use
        end
    end
    -- Taken off the list first, or the next check would fail on them.
    local noted, first = #SecretMisuse, SecretMisuse[1]
    for i = #SecretMisuse, 1, -1 do SecretMisuse[i] = nil end
    Equal(table.concat(errors, "; ") .. " " .. noted, " " .. #uses, "comparing, sums, joining, measuring, indexing,"
        .. " writing, calling, text and iterating all error in the addon's code, and each is noted")
    Equal(first, "Fake.lua:1: attempt to compare a secret number value", "noted with the addon's file and line")
    -- What Lua has no hook for: a plain test or == against a plain value.
    local quiet = assert(load("local s = ... return (s and 1 or 2) .. ' ' .. tostring(s == true) .. ' ' .. type(s)", "@Fake.lua"))
    Equal(quiet(boolean) .. " " .. #SecretMisuse, "1 false boolean 0", "`if secret` and `secret == true` can't be caught here")
    -- A misuse the addon's own pcall hides still fails the next check.
    pcall(assert(load("local s = ... return s < 1", "@Fake.lua")), number)
    local ok, err = pcall(Equal, 1, 1, "the next check")
    for i = #SecretMisuse, 1, -1 do SecretMisuse[i] = nil end
    Equal(tostring(ok) .. " " .. tostring(err):match("misused a secret before this check: Fake%.lua:1"), "false misused a secret before"
        .. " this check: Fake.lua:1", "the next check fails")
    for i = #SecretMisuse, 1, -1 do SecretMisuse[i] = nil end
    -- The mock game and the tests are the game's own code: they may look.
    Equal(tostring(number) .. " " .. tostring(number < 1) .. " " .. #text .. " " .. tostring(number.x), "secret false 0 nil",
        "the tests may look at a secret without an error")
    Equal(#SecretMisuse, 0, "and nothing is noted for them")
end

-- Blizzard's container code run inside the addon's: the 2026-10-07 lead ----------------------------------
-- A container's own OnShow and OnHide (OnShow_Intrinsic, OnHide_Intrinsic)
-- sign it up for its events again and mark it for a full update; the update
-- itself runs later, in its own OnUpdate. Up to audit batch 5 the addon
-- showed and hid the bars that hold containers (the Buffs and Debuffs bars'
-- own, and the Cooldowns and Utility bars' buff and debuff times), so those
-- ran inside its B:UpdateShown: on a fight starting, a target gained or lost
-- out of a fight, Use my bars ticked or unticked (in a fight too), a Buffs or
-- Debuffs bar's first or last entry, Hide out of combat, Edit Mode, Unlock
-- bars (batch 2 proved each). Since batch 6 a bar is shown before its first
-- container is made and never shown or hidden after that: it goes right out
-- instead (Bars.lua B:Hold). The checks below go everywhere those did and
-- prove none of it runs inside the addon's code now, and that a bar gone
-- right out is seen, takes the mouse and is laid out as a hidden one was.
-- Whether the game counted the container's later update as the addon's
-- (taint) can't be seen here. With Use my bars off (the default) no container
-- is ever made (audit batch 3).

-- Every container's own code run so far, by anyone: its OnShow and OnHide,
-- and its refreshes (UpdateAllAuras).
local function ContainerWork()
    local runs = 0
    for _, container in ipairs(containers) do
        runs = runs + (S[container].intrinsic or 0) + (S[container].refreshes or 0)
    end
    return runs
end

-- Whether each container made so far hears its auras change (signed up for
-- its events, as the game's would be), in the order they were made.
local function Heard()
    local heard = {}
    for i, container in ipairs(containers) do heard[i] = tostring(S[container].listening) end
    return table.concat(heard, " ")
end

-- The bars a player can see now, then Blizzard's container code run inside
-- the addon's since the last ask.
local function Now(B)
    local seen = {}
    for _, key in ipairs({ "cd", "util", "buff", "debuff" }) do
        local bar = B:Get(key)
        if bar and InSight(bar) then seen[#seen + 1] = key end
    end
    return "seen: " .. table.concat(seen, " ") .. "; runs: " .. Runs()
end

do
    -- Default settings (Use my bars off): never, as there are none.
    Fresh()
    Load(nil)
    Fire("PLAYER_TARGET_CHANGED")
    target = true
    Fire("PLAYER_TARGET_CHANGED")
    Fire("PLAYER_REGEN_DISABLED")
    lockdown = true
    target = false
    Fire("PLAYER_TARGET_CHANGED")
    lockdown = false
    Fire("PLAYER_REGEN_ENABLED")
    Equal(Runs(), "", "bars off (the default): the addon never runs a container's own code, logging in, fighting or targeting")
    -- Everything else a player with the bars off does: spells, gear, bags
    -- and loading screens, Edit Mode, /ccm and every page of it, the Look
    -- page's border and shadow, and the bars set up while off.
    EditModeManagerFrame:Show()
    EditModeManagerFrame:Hide()
    SlashCmdList.FECM("")
    for _, page in ipairs({ "general", "layout", "look", "cd", "buff", "debuff" }) do FECMFrame:Select(page) end
    FECMFrame.iconBorder.buttons[2]:Click()
    FECMFrame.iconShadow.buttons[3]:Click()
    local from = #timers
    for _, event in ipairs({ "SPELLS_CHANGED", "PLAYER_EQUIPMENT_CHANGED", "BAG_UPDATE_DELAYED", "PLAYER_ENTERING_WORLD",
        "SPELL_UPDATE_COOLDOWN", "BAG_UPDATE_COOLDOWN", "PLAYER_LEVEL_UP" }) do
        Fire(event)
    end
    for i = from + 1, #timers do timers[i]() end
    Equal(#containers .. " " .. ContainerWork() .. " [" .. Runs() .. "]", "0 0 []",
        "bars off: no aura container is ever made, so none of Blizzard's container code runs, whatever the player does")
    FECMFrame:Hide()
    Equal(#printed, 0, "no errors")
end

do
    -- Set up while off (entries, buff and debuff times): still none, until
    -- the bars are turned on.
    Fresh()
    local ns = Load({ notesSeen = "dev" })
    local B = ns.Bars
    B:SetAura("buff", "Thorns", true)
    B:SetAura("debuff", "Moonfire", true)
    B:Assign("Moonfire", "cd")
    B:SetOption("cd", "showAuras", true)
    target = true
    Fire("PLAYER_TARGET_CHANGED")
    Equal(#containers .. " " .. ContainerWork() .. " [" .. Runs() .. "]", "0 0 []",
        "bars off with entries and buff and debuff times set up: still no container")
    SlashCmdList.FECM("")
    FECMFrame:Select("general")
    FECMFrame.useBars:Click()
    Equal(#containers .. " " .. Now(B) .. " | " .. Heard(), "4 seen: cd buff debuff; runs:  | true true true true",
        "Use my bars ticked: the containers made then (the Cooldowns bar's two, the Buffs and Debuffs bars'), each in sight"
        .. " and signed up for its auras, with none of their own code run inside the addon's")
    FECMFrame.useBars:Click()
    local held = 0
    for _, key in ipairs(ns.BAR_KEYS) do
        if S[B:Get(key)].shown then held = held + 1 end
    end
    Equal(held .. " " .. Now(B) .. " | " .. Heard(), "3 seen: ; runs:  | true true true true",
        "unticked: the three bars holding containers gone right out, not hidden, none of the containers' own code run")
    -- Off again: the driver rests, so targets and fights reach none of them.
    local work = ContainerWork()
    for _ = 1, 2 do
        target = false
        Fire("PLAYER_TARGET_CHANGED")
        Fire("PLAYER_REGEN_DISABLED")
        lockdown = true
        target = true
        Fire("PLAYER_TARGET_CHANGED")
        lockdown = false
        Fire("PLAYER_REGEN_ENABLED")
    end
    Equal(ContainerWork() - work .. " [" .. Runs() .. "]", "0 []", "turned off again: targets and fights never reach the containers")
    FECMFrame:Hide()
    Equal(#printed, 0, "no errors")
end

do
    -- Use my bars on.
    Fresh()
    local ns = Load({ useBars = true })
    local B = ns.Bars
    Equal(Runs(), "", "logging in with bars on and nothing on them: none")
    -- Each step: the bars seen are as they were before batch 6, and none of
    -- the containers' own code runs inside the addon's (batch 2 found it in
    -- every one of these).
    B:SetAura("buff", "Thorns", true)
    Equal(Now(B), "seen: buff; runs: ", "the Buffs bar's first entry: it comes into sight, none run")
    B:SetAura("buff", "Thorns", false)
    Equal(tostring(S[B:Get("buff")].shown) .. " " .. Now(B), "true seen: ; runs: ",
        "its last taken off: gone right out, still shown, none run")
    B:SetAura("debuff", "Moonfire", true)
    Equal(Now(B), "seen: debuff; runs: ", "the Debuffs bar's first entry: none run")
    B:SetAura("debuff", "Moonfire", false)
    Equal(Now(B), "seen: ; runs: ", "and its last taken off: none run")
    B:SetAura("buff", "Thorns", true)
    B:Assign("Moonfire", "cd")
    B:SetOption("cd", "showAuras", true)
    Equal(Now(B), "seen: cd buff; runs: ", "buff and debuff times ticked on a shown Cooldowns bar: made, none run")
    B:SetOption("cd", "outOfCombat", "hide")
    Equal(tostring(S[B:Get("cd")].shown) .. " " .. Now(B), "true seen: buff; runs: ",
        "Hide out of combat with no target: the Cooldowns bar goes right out, still shown, none run")
    -- A fight starts: PLAYER_REGEN_DISABLED comes just before the lockdown.
    Fire("PLAYER_REGEN_DISABLED")
    Equal(Now(B), "seen: cd buff; runs: ", "a fight starts: back in sight, none run")
    lockdown = true
    target = true
    Fire("PLAYER_TARGET_CHANGED")
    Equal(Now(B), "seen: cd buff; runs: ", "a target in the fight: none run")
    target = false
    Fire("PLAYER_TARGET_CHANGED")
    Equal(Now(B), "seen: cd buff; runs: ", "the target lost in the fight: none run")
    target = true
    Fire("PLAYER_TARGET_CHANGED")
    lockdown = false
    Fire("PLAYER_REGEN_ENABLED")
    Equal(Now(B), "seen: cd buff; runs: ", "the fight ends with an enemy targeted: still up, none run")
    target = false
    Fire("PLAYER_TARGET_CHANGED")
    Equal(Now(B), "seen: buff; runs: ", "no target out of a fight: gone right out, none run")
    target = true
    Fire("PLAYER_TARGET_CHANGED")
    Equal(Now(B), "seen: cd buff; runs: ", "an enemy targeted out of a fight: back, none run")
    -- Out of a fight with no target the Cooldowns bar is gone again; Edit
    -- Mode and Unlock bars bring it back (the addon's own Edit Mode hook).
    target = false
    Fire("PLAYER_TARGET_CHANGED")
    EditModeManagerFrame:Show()
    Equal(Now(B), "seen: cd buff; runs: ", "Edit Mode opening: back, none run")
    EditModeManagerFrame:Hide()
    Equal(Now(B), "seen: buff; runs: ", "and closing: gone, none run")
    B:SetUnlocked(true)
    Equal(Now(B), "seen: cd util buff debuff; runs: ", "Unlock bars: every bar, the empty Debuffs bar too, none run")
    B:SetUnlocked(false)
    Equal(Now(B), "seen: buff; runs: ", "Lock: none run")
    target = true
    Fire("PLAYER_TARGET_CHANGED")
    Runs()
    SlashCmdList.FECM("")
    FECMFrame:Select("general")
    FECMFrame.useBars:Click()
    Equal(Now(B), "seen: ; runs: ", "Use my bars unticked: none run")
    FECMFrame.useBars:Click()
    Equal(Now(B), "seen: cd buff; runs: ", "ticked again: none run")
    FECMFrame:Hide()
    Equal(Now(B) .. " | " .. Heard(), "seen: cd buff; runs:  | true true true true",
        "the window closing: none run, and every container still hears its auras")
    Equal(#printed, 0, "no errors")
end

do
    -- Buff and debuff times first ticked on a Cooldowns bar hidden just then
    -- (Hide out of combat, no target): the bar is shown, gone right out,
    -- before they're made, so they're made in sight and hear their auras
    -- from the start, as they never get an OnShow from the addon after.
    Fresh()
    local ns = Load({ useBars = true, notesSeen = "dev" })
    local B = ns.Bars
    B:Assign("Moonfire", "cd")
    B:SetOption("cd", "outOfCombat", "hide")
    local cd = B:Get("cd")
    Equal(tostring(S[cd].shown) .. " " .. tostring(cd.holds), "false nil", "no containers yet: hidden as before")
    B:SetOption("cd", "showAuras", true)
    local made = cd.auraContainers or { p = UIParent, t = UIParent }
    Equal(tostring(S[cd].shown) .. " " .. Now(B) .. " | " .. S[cd].alpha .. " " .. tostring(S[made.p].listening) .. " "
        .. tostring(S[made.t].listening), "true seen: ; runs:  | 0 true true",
        "ticked: shown but gone right out, its two containers made in sight and hearing their auras, none run")
    target = true
    Fire("PLAYER_TARGET_CHANGED")
    Equal(Now(B), "seen: cd; runs: ", "an enemy targeted: in sight, none run")
    Equal(#printed, 0, "no errors")
end

do
    -- B:Hold on its own leaves the bar right out until the bars are next
    -- shown: here a Utility bar taken out of the layout while unlocked (its
    -- mover and arrows up inside the hidden bar), as when a container would
    -- be made in it with nothing laid out after.
    Fresh()
    local ns = Load({ useBars = true, notesSeen = "dev" })
    local B, L = ns.Bars, ns.Layout
    ns.Set("growArrows", true)
    B:Assign("Wrath", "util")
    L:Apply("pyramid")
    L:TakeOut("util")
    B:SetUnlocked(true)
    local util = B:Get("util")
    Equal(tostring(S[util].shown) .. " " .. tostring(S[util.mover].shown) .. " " .. tostring(S[util.arrows].shown), "false true true",
        "out of the layout while unlocked: hidden, its mover and arrows up inside it")
    B:Hold(util)
    Equal(tostring(S[util].shown) .. " " .. tostring(InSight(util)) .. " " .. tostring(util.gone) .. " " .. S[util].alpha .. " "
        .. tostring(util.mover:IsVisible()) .. " " .. tostring(util.arrows:IsVisible()), "true false true 0 false false",
        "held: shown, but gone right out, see-through, its mover and arrows down")
    -- A bar already shown when it's held is left as it is (no layout or
    -- show may follow, as for B:Relayout).
    local cd = B:Get("cd")
    B:Hold(cd)
    Equal(tostring(InSight(cd)) .. " " .. tostring(cd.gone) .. " " .. S[cd].alpha .. " " .. tostring(cd.mover:IsVisible()) .. " "
        .. tostring(cd.arrows:IsVisible()), "true nil 1 true true", "held while shown: left in sight, its mover and arrows up")
    B:SetUnlocked(false)
    Equal(#printed, 0, "no errors")
end

do
    -- In a fight. Items running out wait for the fight to end, and the Buffs
    -- and Debuffs bars never come or go in one, but the Cooldowns and Utility
    -- bars do, as Use my bars is unticked in a fight: gone right out at once.
    Fresh()
    itemCount[5512] = 1
    local ns = Load({ useBars = true })
    local B = ns.Bars
    B:Assign("Moonfire", "cd")
    B:Assign("family:healthstone", "cd")
    B:SetAura("buff", "Thorns", true)
    B:SetOption("cd", "showAuras", true)
    -- Any show or hide of these two in the lockdown is noted (combatToggle).
    watched[B:Get("cd")], watched[B:Get("buff")] = true, true
    Runs()
    Fire("PLAYER_REGEN_DISABLED")
    lockdown = true
    itemCount[5512] = 0
    Fire("BAG_UPDATE_DELAYED")
    Equal(Runs(), "", "the last Healthstone used in a fight: the bar waits for the fight to end, none")
    SlashCmdList.FECM("")
    FECMFrame:Select("general")
    FECMFrame.useBars:Click()
    Equal(tostring(S[B:Get("cd")].shown) .. " " .. tostring(S[B:Get("cd")].combatToggle) .. " "
        .. tostring(S[B:Get("buff")].combatToggle) .. " " .. Now(B), "true nil nil seen: buff; runs: ", "Use my bars unticked in a"
        .. " fight: the Cooldowns bar goes right out at once, never hidden, none run (the Buffs bar waits)")
    lockdown = false
    Fire("PLAYER_REGEN_ENABLED")
    Equal(tostring(S[B:Get("buff")].shown) .. " " .. Now(B), "true seen: ; runs: ", "and the Buffs bar once it ends, none run")
    FECMFrame:Hide()
    Equal(#printed, 0, "no errors")
end

-- How each bar looks to a player now: seen or not, whether its mover and
-- grow arrows are up (even see-through), how many frames on it take the mouse
-- (shown ones with the mouse on, or a mouse script: a see-through one still
-- catches clicks), and where it's placed and how big.
local function Picture(B)
    local lines = {}
    for _, key in ipairs({ "cd", "util", "buff", "debuff" }) do
        local bar, mice = B:Get(key), 0
        local function Walk(frame)
            local s = S[frame]
            if frame:IsVisible() and (Last(frame, "EnableMouse") == true or s.scripts.OnEnter or s.scripts.OnMouseUp
                or s.scripts.OnDragStart or s.scripts.OnReceiveDrag or s.scripts.OnClick) then
                mice = mice + 1
            end
            for _, kid in ipairs(s.kids or {}) do Walk(kid) end
        end
        Walk(bar)
        local point = S[bar].points[1] or {}
        lines[#lines + 1] = ("%s %s, mover %s, arrows %s, takes the mouse %d, at %s %s,%s, %sx%s"):format(key,
            InSight(bar) and "seen" or "unseen", tostring(bar.mover:IsVisible()), tostring(bar.arrows:IsVisible()), mice,
            tostring(point[1]), tostring(point[4]), tostring(point[5]), tostring(S[bar].width), tostring(S[bar].height))
    end
    return table.concat(lines, "; ")
end

do
    -- A bar gone right out is seen, takes the mouse, and is placed and sized
    -- as a hidden one was, by the layout, its mover and arrows, Unlock bars
    -- and Edit Mode: the same steps with the game's aura containers (bars
    -- holding them go right out) and without any (every bar shown and hidden
    -- as before batch 6), in a layout with grow arrows on. Played twice: with
    -- Cooldowns hiding and Utility fading out of combat, then with the bars
    -- holding containers fading (a bar gone right out must not show at the
    -- Fade opacity) and Utility, with buff and debuff times too, hiding.
    local function Play(withContainers, modes)
        Fresh()
        if not withContainers then _G.CustomAuraContainerSlotDefaultOptions = nil end
        local ns = Load({ useBars = true, notesSeen = "dev" })
        local B, L = ns.Bars, ns.Layout
        ns.Set("growArrows", true)
        B:Assign("Moonfire", "cd")
        B:Assign("Wrath", "util")
        B:SetAura("buff", "Thorns", true)
        B:SetOption("cd", "showAuras", true)
        if modes.utilAuras then B:SetOption("util", "showAuras", true) end
        for _, key in ipairs({ "cd", "util", "buff", "debuff" }) do
            if modes[key] then B:SetOption(key, "outOfCombat", modes[key]) end
        end
        L:Apply("pyramid")
        SlashCmdList.FECM("")
        FECMFrame:Select("general")
        local steps, gone = {}, 0
        local function Step(name)
            for _, key in ipairs(ns.BAR_KEYS) do
                if B:Get(key).gone then gone = gone + 1 end
            end
            steps[#steps + 1] = { name, Picture(B) }
        end
        Step("set up, out of a fight with no target (Cooldowns hides out of combat, Debuffs empty)")
        target = true
        Fire("PLAYER_TARGET_CHANGED")
        Step("an enemy targeted")
        target = false
        Fire("PLAYER_TARGET_CHANGED")
        Step("the target lost")
        Fire("PLAYER_REGEN_DISABLED")
        lockdown = true
        Step("a fight starts")
        target = true
        Fire("PLAYER_TARGET_CHANGED")
        Step("a target in the fight")
        lockdown = false
        Fire("PLAYER_REGEN_ENABLED")
        target = false
        Fire("PLAYER_TARGET_CHANGED")
        Step("the fight over, no target")
        B:SetUnlocked(true)
        Step("Unlock bars")
        B:SetUnlocked(false)
        Step("Lock")
        EditModeManagerFrame:Show()
        Step("Edit Mode open")
        EditModeManagerFrame:Hide()
        Step("Edit Mode closed")
        L:TakeOut("buff")
        Step("Buffs taken out of the layout")
        B:SetUnlocked(true)
        Step("unlocked with Buffs out")
        B:SetUnlocked(false)
        L:PutBack("buff")
        Step("Buffs put back")
        B:SetAura("buff", "Thorns", false)
        Step("the Buffs bar's last entry taken off")
        B:SetAura("debuff", "Moonfire", true)
        Step("the Debuffs bar's first entry")
        FECMFrame.useBars:Click()
        Step("Use my bars unticked")
        FECMFrame.useBars:Click()
        Step("ticked again")
        Fire("PLAYER_REGEN_DISABLED")
        lockdown = true
        FECMFrame.useBars:Click()
        Step("unticked in a fight")
        lockdown = false
        Fire("PLAYER_REGEN_ENABLED")
        Step("that fight over")
        FECMFrame.useBars:Click()
        FECMFrame:Hide()
        Step("ticked again, the window closed")
        return steps, gone, #containers, #printed
    end
    for _, case in ipairs({
        { name = "Cooldowns hiding, Utility fading", made = 4, modes = { cd = "hide", util = "fade" } },
        { name = "Cooldowns, Buffs and Debuffs fading, Utility with buff and debuff times hiding", made = 6,
            modes = { cd = "fade", util = "hide", buff = "fade", debuff = "fade", utilAuras = true } },
    }) do
        local with, gone, made, errors = Play(true, case.modes)
        local without, goneBefore, madeBefore, errorsBefore = Play(false, case.modes)
        Equal(made .. " " .. tostring(gone > 10) .. " " .. madeBefore .. " " .. goneBefore .. " " .. errors .. " " .. errorsBefore,
            case.made .. " true 0 0 0 0", case.name .. ": with the containers, bars holding them go right out at times; without,"
            .. " none is made or goes right out")
        for i, step in ipairs(with) do
            Equal(step[2], without[i][2], case.name .. ", " .. step[1] .. ": a bar gone right out looks, takes the mouse and is placed"
                .. " as a hidden one")
        end
    end
end

do
    -- /ccm debug (hidden, never announced) with entries on the Buffs and
    -- Debuffs bars: those keep them in holders, not icons, so the report
    -- lists each entry's spells there (it stopped on a nil icon before).
    Fresh()
    local ns = Load({ useBars = true, notesSeen = "dev" })
    local B = ns.Bars
    B:Assign("Moonfire", "cd")
    B:SetAura("buff", "Thorns", true)
    B:SetAura("debuff", "Moonfire", true)
    B:SetOption("cd", "showAuras", true)
    local function Report()
        local ok, err = pcall(SlashCmdList.FECM, "debug")
        local report = ok and FECMDebugFrame and S[FECMDebugFrame.edit].text or ("error: " .. tostring(err))
        if FECMDebugFrame then FECMDebugFrame:Hide() end
        return report
    end
    local function Has(report, text) return report:find(text, 1, true) ~= nil end
    local report = Report()
    Equal(tostring(Has(report, "buff bar: shown true (holds aura containers), 1 entries\n  1. Thorns | spells 467,782,1075,8914,9756,9910"))
        .. " " .. tostring(Has(report, "debuff bar: shown true (holds aura containers), 1 entries\n  1. Moonfire | spells 8921,8924,")),
        "true true", "the report lists each Buffs and Debuffs entry with its spells, not as an icon (it stopped on a nil icon before)")
    Equal(tostring(Has(report, "cd bar: shown true (holds aura containers), 1 icons\n  1. Moonfire | spell 8924 | reactive false"))
        .. " " .. tostring(Has(report, "util bar: shown false, 0 icons")), "true true", "and the Cooldowns and Utility icons as before")
    B:SetAura("buff", "Thorns", false)
    Equal(tostring(Has(Report(), "buff bar: shown false (holds aura containers), 0 entries\ndebuff bar:")), "true",
        "a bar gone right out reads as not shown")
    Equal(#printed, 0, "no errors")
end

Equal(SecretMisuse[1], nil, "no secret misused anywhere")
print = _G.print
io.write("Aura container checks passed: " .. checks .. " assertions.\n")
