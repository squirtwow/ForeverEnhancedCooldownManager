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
local FILES = { "Core.lua", "Style.lua", "Skin.lua", "Resource.lua", "CastBar.lua", "RaidTimers.lua", "Ranks.lua", "Spells.lua",
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
    B:SetOption("cd", "whenReady", "show")
    active, usable[8924], range[8924] = false, nil, nil
    lockdown = false
    Fire("PLAYER_REGEN_ENABLED")
    NextFrame(ns)
    _G.C_SpellActivationOverlay = nil
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

Equal(SecretMisuse[1], nil, "no secret misused anywhere")
print = _G.print
io.write("Hot path checks passed: " .. checks .. " assertions.\n")
