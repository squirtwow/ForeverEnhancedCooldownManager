-- Run the actual addon files against a mock game for sharing a profile as
-- text (ProfileShare.lua, and Core.lua's ns.ImportProfile): a full profile
-- with its look and layout goes out and comes back the same on another
-- account, Import always makes a new profile under a free name and leaves
-- the one you're on as it is, another class's spells stay in it but off
-- your bars, and broken, cut short, huge, deeply nested, wrong and hostile
-- strings never error, never run anything, and only leave sane values. The
-- mock game is a copy of Tools/TestBars.lua's: Tools/TestMockSync.mjs checks
-- the two match, and with --write copies it across.
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

-- Share: the game around it ----------------------------------------------------------------------
-- Stand-ins for what the window's other pages need, as in Tools/TestWidgets.lua,
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

-- A fresh game for the character set in `character`, logged in with these
-- saved settings.
local function Start(saved)
    Environment()
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

-- The tests' own helpers, in one table: this file's main chunk shares Lua's
-- 200 locals with the mock game.
local H = {}

-- Any value as text, tables with their keys in order, so two can be compared.
function H.Text(v)
    if type(v) == "string" then return ("%q"):format(v) end
    -- As the game's Lua 5.1 has it: 0 and 0.0 are one number.
    if type(v) == "number" then return v == math.floor(v) and ("%d"):format(v) or ("%.14g"):format(v) end
    if type(v) ~= "table" then return tostring(v) end
    local keys = {}
    for k in pairs(v) do keys[#keys + 1] = k end
    table.sort(keys, function(a, b)
        if type(a) ~= type(b) then return type(a) < type(b) end
        return a < b
    end)
    local parts = {}
    for _, k in ipairs(keys) do parts[#parts + 1] = "[" .. H.Text(k) .. "]=" .. H.Text(v[k]) end
    return "{" .. table.concat(parts, ",") .. "}"
end

-- The share format, written here a second time on purpose (not the addon's
-- own code), to make strings of any shape: T, F, N<number>;, S<length>:<text>,
-- [values] for a list and {key value ...} for a table.
function H.Pack(v)
    local kind = type(v)
    if kind == "boolean" then return v and "T" or "F" end
    if kind == "number" then
        if v == math.floor(v) and math.abs(v) < 2147483648 then return ("N%d;"):format(v) end
        return ("N%.14g;"):format(v)
    end
    if kind == "string" then return "S" .. #v .. ":" .. v end
    local count = 0
    for _ in pairs(v) do count = count + 1 end
    local out = {}
    if count == #v then
        for _, item in ipairs(v) do out[#out + 1] = H.Pack(item) end
        return "[" .. table.concat(out) .. "]"
    end
    local keys = {}
    for k in pairs(v) do keys[#keys + 1] = k end
    table.sort(keys, function(a, b)
        if type(a) ~= type(b) then return type(a) == "number" end
        return a < b
    end)
    for _, k in ipairs(keys) do out[#out + 1] = H.Pack(k) .. H.Pack(v[k]) end
    return "{" .. table.concat(out) .. "}"
end

-- Base64, written here a second time too: six bits at a time.
function H.Base64(raw)
    local letters = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"
    local bits = {}
    for i = 1, #raw do
        local byte = raw:byte(i)
        for b = 7, 0, -1 do bits[#bits + 1] = math.floor(byte / 2 ^ b) % 2 end
    end
    while #bits % 6 ~= 0 do bits[#bits + 1] = 0 end
    local out = {}
    for i = 1, #bits, 6 do
        local n = 0
        for b = 0, 5 do n = n * 2 + bits[i + b] end
        out[#out + 1] = letters:sub(n + 1, n + 1)
    end
    while #out % 4 ~= 0 do out[#out + 1] = "=" end
    return table.concat(out)
end

function H.String(data)
    return "FECM1:" .. H.Base64(type(data) == "string" and data or H.Pack(data))
end

-- The same few numbers every run: fuzzing that fails, fails again.
H.seed = 20261008
function H.Random(n)
    H.seed = (H.seed * 1103515245 + 12345) % 2147483648
    return H.seed % n
end

-- Random values for random profiles: names, keys and settings the format
-- knows, and plenty it doesn't, numbers in and out of range, ticks, and
-- lists and tables of them, sometimes deeper than a string may go.
H.WORDS = { "l", "g", "s", "b", "k", "j", "p", "q", "c", "n", "a", "cd", "util", "buff", "debuff", "extra", "size", "spacing",
    "perRow", "grow", "wrap", "point", "x", "y", "on", "preset", "base", "gap", "above", "below", "hidden", "left", "right",
    "barStyle", "font", "accent", "useBars", "castHeight", "pulseX", "showTimer", "Moonfire", "Thorns", "Wrath", "item:118",
    "item:0", "slot:13", "slot:9", "family:mana", "family:x", "ammo", "Moonfire@2", "@", "long", "short", "split", "arial", "wide",
    "evil", "TOP", "CENTER", "centre", "down", "up", "dim", "hide", "fade", "show", "blue", "neon", "|cffff0000x|r", "a\0b", " x",
    ("z"):rep(70), "", 'loadstring("x")()' }
H.NUMBERS = { 0, 1, -1, 2.5, 3, 13, 40, 64, 65, 3999, 4000, -4000, 1e9, 2147483647, 2147483648, 1e300, -0.5, 7 }
function H.RandomValue(depth)
    local roll = H.Random(10)
    if depth >= 5 or roll < 3 then return H.WORDS[H.Random(#H.WORDS) + 1] end
    if roll < 5 then return H.NUMBERS[H.Random(#H.NUMBERS) + 1] end
    if roll < 6 then return H.Random(2) == 0 end
    local t = {}
    if roll < 8 then
        for i = 1, H.Random(6) do t[i] = H.RandomValue(depth + 1) end
    else
        for _ = 1, H.Random(6) do
            local key = H.Random(4) == 0 and H.NUMBERS[H.Random(#H.NUMBERS) + 1] or H.WORDS[H.Random(#H.WORDS) + 1]
            t[key] = H.RandomValue(depth + 1)
        end
    end
    return t
end
function H.RandomProfile()
    local root = {}
    for _, key in ipairs({ "l", "g", "j", "p", "q", "c", "n", "a", "zz" }) do
        if H.Random(3) > 0 then root[key] = H.RandomValue(1) end
    end
    if H.Random(2) == 0 then
        root.l = { cd = H.RandomValue(2), util = H.RandomValue(2), buff = H.RandomValue(2), debuff = H.RandomValue(2) }
    end
    if H.Random(2) == 0 then
        root.g = { s = H.RandomValue(2), b = { cd = H.RandomValue(3), buff = H.RandomValue(3) }, l = H.RandomValue(2), k = H.RandomValue(2) }
    end
    return root
end

-- Runs fn with every way Lua or the game has of running text as code
-- replaced by one that notes the call and stops: whether fn ran without an
-- error, what it returned, and the calls tried.
H.RUNNERS = { "loadstring", "load", "dofile", "loadfile", "require", "setfenv", "getfenv", "RunScript", "RunMacroText",
    "RunMacro", "securecall", "ConsoleExec" }
function H.Trap(fn, ...)
    local saved, tried = {}, {}
    for _, name in ipairs(H.RUNNERS) do
        saved[name] = rawget(_G, name)
        rawset(_G, name, function() tried[#tried + 1] = name; error(name .. " was called") end)
    end
    local result = table.pack(pcall(fn, ...))
    for _, name in ipairs(H.RUNNERS) do rawset(_G, name, saved[name]) end
    return result[1], result[2], result[3], tried, result[4]
end

-- Whether what P.Read gave back is sane, worked out here without the
-- addon's checks: "" when it is, else the first thing wrong.
function H.Sane(ns, shared)
    local function Word(v)
        return type(v) == "string" and #v >= 1 and #v <= 64 and not v:find("[%c|]") and v == v:match("^%s*(.-)%s*$")
    end
    local function ID(v) return type(v) == "number" and v == math.floor(v) and v >= 1 and v <= 2147483647 end
    local known = { lists = true, joins = true, pick = true, style = true, added = true, setup = true, count = true, picks = true,
        skipped = true, name = true, version = true }
    for k in pairs(shared) do
        if not known[k] then return "an unknown key " .. tostring(k) end
    end
    if type(shared.skipped) ~= "number" or shared.skipped < 0 then return "skipped" end
    if shared.name ~= nil and not (type(shared.name) == "string" and #shared.name <= 48 and not shared.name:find("[%c|]")) then return "name" end
    if shared.version ~= nil and not (type(shared.version) == "string" and shared.version:find("^[%w%.%-]+$")) then return "version" end
    local count, on, cooldown = 0, {}, {}
    for k in pairs(shared.lists) do
        if not ns.BAR_NAMES[k] then return "a list for no bar" end
    end
    for _, key in ipairs(ns.BAR_KEYS) do
        local list, seen = shared.lists[key], {}
        if type(list) ~= "table" or #list > 40 then return "the " .. key .. " list" end
        for k, v in pairs(list) do
            if type(k) ~= "number" or not Word(v) or seen[v] then return "an entry on " .. key end
            if (key == "cd" or key == "util") and cooldown[v] then return "on both cooldown bars: " .. v end
            seen[v], on[v] = true, true
            if key == "cd" or key == "util" then cooldown[v] = true end
            if v:find("^item:") and not v:find("^item:[1-9]%d*$") then return "an item key " .. v end
            if v:find("^slot:") and v ~= "slot:13" and v ~= "slot:14" then return "a slot key " .. v end
        end
        count = count + #list
    end
    if shared.count ~= count then return "count" end
    for key, set in pairs(shared.joins) do
        if not ns.AURA_BARS[key] then return "joins on " .. tostring(key) end
        for name, v in pairs(set) do
            if v ~= true or not on[name] or shared.lists[key][1] == name then return "a join " .. tostring(name) end
        end
    end
    local picks = 0
    for name, v in pairs(shared.pick) do
        if v ~= true or not Word(name) then return "a pick" end
        picks = picks + 1
    end
    if picks ~= shared.picks or picks > 400 then return "picks" end
    for name, v in pairs(shared.style) do
        if v ~= "long" or not Word(name) then return "a style" end
    end
    for name, ids in pairs(shared.added) do
        if not on[name] or #ids < 1 or #ids > 10 then return "added " .. tostring(name) end
        for _, id in pairs(ids) do
            if not ID(id) then return "an added ID" end
        end
    end
    local setup = shared.setup
    if setup == nil then return "" end
    local share = {}
    for _, key in ipairs(ns.SHARE_LOOK) do share[key] = true end
    for key, v in pairs(setup.look) do
        if not share[key] or not ns.Valid(key, v) then return "a look setting " .. tostring(key) end
    end
    local fields = {}
    for _, field in ipairs(ns.SHARE_BAR_FIELDS) do fields[field] = true end
    for key, bar in pairs(setup.bars) do
        if not ns.BAR_NAMES[key] then return "a bar " .. tostring(key) end
        for field, v in pairs(bar) do
            if not fields[field] then return "a bar setting " .. tostring(field) end
            if (field == "x" or field == "y") and not (type(v) == "number" and math.abs(v) < 4000) then return "a spot" end
            if field == "size" and not (type(v) == "number" and v >= 20 and v <= 64) then return "a size" end
        end
    end
    local layoutKeys = { on = true, preset = true, base = true, left = true, right = true, gap = true, spacing = true,
        above = true, below = true, hidden = true }
    for field, v in pairs(setup.layout) do
        if not layoutKeys[field] then return "a layout setting " .. tostring(field) end
        if (field == "left" or field == "right") and not ns.BAR_NAMES[v] then return "a side" end
        if (field == "above" or field == "below") then
            for _, key in pairs(v) do
                if not ns.BAR_NAMES[key] then return "a row" end
            end
        end
    end
    for id, colour in pairs(setup.colours) do
        if not ID(id) or not ns.Valid("barColour", colour) then return "a colour" end
    end
    return ""
end

-- Every value a shared profile carries, read from the game as it is now: the
-- look, each bar's settings, the layout and the Tracked Bar colours.
function H.SetupNow(ns)
    local look = {}
    for _, key in ipairs(ns.SHARE_LOOK) do look[key] = ns.Get(key) end
    local bars = {}
    for _, key in ipairs(ns.BAR_KEYS) do
        local data, own = ns.BarData(key), {}
        for _, field in ipairs(ns.SHARE_BAR_FIELDS) do own[field] = data[field] end
        bars[key] = own
    end
    local layout, saved = {}, ns.LayoutData()
    for _, field in ipairs({ "on", "preset", "base", "gap", "spacing", "left", "right", "above", "below", "hidden" }) do
        layout[field] = saved[field]
    end
    local colours = {}
    for id, colour in pairs(ns.BarColours()) do colours[id] = colour end
    return H.Text({ look = look, bars = bars, layout = layout, colours = colours })
end

-- The profile you're on, as its lists.
function H.ProfileNow(ns)
    local lists = {}
    for _, key in ipairs(ns.BAR_KEYS) do lists[key] = ns.ActiveList(key) end
    return H.Text({ lists = lists, buff = ns.Joins("buff"), debuff = ns.Joins("debuff"), pick = ns.PulsePicks(),
        style = ns.PulseStyles() })
end

-- Watches what draws the look again: a function giving the parts drawn
-- since, in order of name, each once.
function H.Spy(ns)
    local called = {}
    for _, spy in ipairs({ { ns.Style, "ApplyFont", "font" }, { ns.Bars, "ApplyDecor", "icon decor" },
        { ns.Bars, "ApplyGlow", "icon glow" }, { ns.Bars, "ApplyKeybinds", "icon keys" }, { ns.Skin, "ApplyBarLook", "restyled bars" },
        { ns.Resource, "Apply", "display" }, { ns.CastBar, "Apply", "cast bar" }, { ns.RaidTimers, "Apply", "raid timers" } }) do
        local module, method, label = spy[1], spy[2], spy[3]
        local original = module[method]
        module[method] = function(...)
            called[label] = true
            return original(...)
        end
    end
    return function()
        local list = {}
        for label in pairs(called) do list[#list + 1] = label end
        table.sort(list)
        return table.concat(list, ", ")
    end
end

-- Settings a shared profile never carries: switching a part on or off, and the window's own.
H.NOT_SHARED = { "skin", "useBars", "listItems", "listRanks", "accent", "prdSkin", "prdCombo", "castBar", "swingTimer",
    "pullTimer", "raidWarnings", "bossCasts", "pulse", "keybinds", "layoutPreview", "growArrows", "minimap", "minimapAngle",
    "minimapFree", "minimapX", "minimapY" }

-- Every setting is either shared or kept out, on purpose -------------------------------------------
-- A setting added later must be put on one side or the other.

do
    character = { guid = "Player-1-0001", name = "Zriel", realm = "Zephras" }
    local ns = Start({ notesSeen = "dev", helpSeen = true })
    local sides, both = {}, {}
    for _, key in ipairs(ns.SHARE_LOOK) do sides[key] = "shared" end
    for _, key in ipairs(H.NOT_SHARED) do
        if sides[key] then both[#both + 1] = key end
        sides[key] = "kept"
    end
    local loose = {}
    for key in pairs(ns.DEFAULTS) do
        if not sides[key] then loose[#loose + 1] = key end
    end
    for key in pairs(sides) do
        if ns.DEFAULTS[key] == nil then loose[#loose + 1] = key .. " (no such setting)" end
    end
    table.sort(loose)
    Equal(table.concat(loose, ", ") .. "|" .. table.concat(both, ", "), "|",
        "every setting is shared or kept out, none both: the look goes, a tick switching a part on or off never does")
    local barChecks, fields = ns.ProfileShare.BAR_CHECKS, {}
    for _, field in ipairs(ns.SHARE_BAR_FIELDS) do fields[#fields + 1] = field .. (barChecks[field] and "" or " unchecked") end
    for field in pairs(barChecks) do
        local found = false
        for _, f in ipairs(ns.SHARE_BAR_FIELDS) do found = found or f == field end
        if not found then fields[#fields + 1] = field .. " not shared" end
    end
    Equal(table.concat(fields, ","), "size,spacing,perRow,whenReady,outOfCombat,showMissing,showNames,showTimer,showAuras,"
        .. "selfDebuffs,grow,wrap,point,x,y", "each bar setting shared has its own check, and only those")
end

-- A full profile, out and back ----------------------------------------------------------------------
-- Every list, join, pulse tick and Long style, a spell added by ID, and a
-- look, bar settings, a layout and Tracked Bar colours unlike the defaults.
-- Read back, it's the same; imported on another account with its look and
-- layout, that account's profile and setup are the same, and it shares the
-- very same string. Settings a string never carries stay the importer's own.

do
    character = { guid = "Player-1-0001", name = "Zriel", realm = "Zephras" }
    local ns = Start({ notesSeen = "dev", helpSeen = true, useBars = true, barStyle = "split", barColour = "blue",
        barTexture = "raid", font = "arial", iconBorder = "icon", iconShadow = "bar", readyGlow = "edge", keybindPosition = "TOP",
        keybindSize = 120, barScale = 110, prdHideRepeat = false, prdHealth = "green", castHeight = 24, castIcon = false,
        swingColour = "purple", pullColour = "class", warningFont = "morpheus", warningShadow = false, raidSize = 120,
        pulseSize = 300, pulseSound = "bell", pulseMaster = true, pulseX = -120, pulseY = 85.5,
        -- Never shared: these stay each account's own.
        accent = "teal", keybinds = true, pulse = true, minimap = false, growArrows = true, listItems = true })
    local P, B, L = ns.ProfileShare, ns.Bars, ns.Layout
    for key, list in pairs({ cd = { "Moonfire", "Wrath", "Mortal Strike", "slot:13", "family:healing", "Moonfire@1" },
        util = { "Overpower", "ammo", "item:118" }, buff = { "Thorns", "Mark of the Wild", "Power Word: Fortitude" },
        debuff = { "Moonfire", "Garrote" } }) do
        for _, entry in ipairs(list) do table.insert(ns.ActiveList(key), entry) end
    end
    ns.AddCustom("Power Word: Fortitude", { 1243 })
    ns.Joins("buff")["Mark of the Wild"] = true
    ns.SetPulsePick("Moonfire", true)
    ns.SetPulsePick("item:118", true)
    ns.SetPulseStyle("Moonfire", "long")
    ns.SetPulseStyle("Wrath", "long")
    B:Changed()
    B:SetOption("cd", "size", 48)
    B:SetOption("cd", "whenReady", "dim")
    B:SetOption("cd", "outOfCombat", "fade")
    B:SetOption("util", "perRow", 6)
    B:SetOption("util", "showNames", true)
    B:SetOption("buff", "showMissing", true)
    B:SetOption("buff", "spacing", 2)
    B:SetOption("debuff", "selfDebuffs", true)
    B:SetOption("debuff", "showTimer", false)
    L:Apply("sides")
    L:SetGap(3)
    L:TakeOut("util")
    ns.SetBarColour(1234, "blue")
    ns.SetBarColour(5678, "class")
    local profile, setup = H.ProfileNow(ns), H.SetupNow(ns)

    local ok, text, _, tried = H.Trap(P.Export)
    Equal(tostring(ok) .. " " .. #tried, "true 0", "Share makes a string, running nothing")
    Equal(text:sub(1, 6) .. " " .. tostring(text:sub(7):find("^[%w%+/]+=*$") ~= nil), "FECM1: true",
        "it starts FECM1: and the rest is plain Base64, which survives chat")
    Equal(#text < 2000, true, "a full profile fits in one Discord message (" .. #text .. " letters)")
    io.write("Share: a full profile with its look and layout is " .. #text .. " letters as a string.\n")
    Equal(P.Export(), text, "the same profile always makes the same string")

    local read, shared, why, readTried = H.Trap(P.Read, text)
    Equal(tostring(read) .. " " .. tostring(why) .. " " .. #readTried .. " " .. H.Sane(ns, shared) .. "|", "true nil 0 |",
        "read back: no error, nothing run, every value sane")
    Equal(tostring(shared.name) .. " | " .. shared.version .. " | " .. shared.skipped, "nil | dev | 0",
        "no name (by default it's your character's, and strings get posted in public), the version that made it, nothing left out")
    Equal(tostring(text:find("Zriel", 1, true)), "nil", "the character's name is nowhere in it")
    Equal(H.Text({ lists = shared.lists, buff = shared.joins.buff, debuff = shared.joins.debuff or {}, pick = shared.pick,
        style = shared.style }), profile, "every list, join, pulse tick and Long style comes back the same")
    Equal(H.Text(shared.added), H.Text({ ["Power Word: Fortitude"] = { 1243 } }), "and the spell added by ID, with its ID")
    local look = {}
    for _, key in ipairs(ns.SHARE_LOOK) do
        if ns.Get(key) ~= ns.DEFAULTS[key] then look[key] = ns.Get(key) end
    end
    Equal(H.Text(shared.setup.look), H.Text(look), "the look: every shared setting unlike the default, and no other")
    Equal(tostring(shared.setup.look.accent) .. " " .. tostring(shared.setup.look.keybinds) .. " " .. tostring(shared.setup.look.castBar)
        .. " " .. tostring(shared.setup.look.pulse), "nil nil nil nil", "never the accent, nor a tick that switches a part on")
    local cd, debuff, util = shared.setup.bars.cd, shared.setup.bars.debuff, shared.setup.bars.util
    Equal(cd.size .. " " .. cd.whenReady .. " " .. cd.outOfCombat .. " " .. tostring(cd.showTimer) .. " " .. tostring(cd.showNames)
        .. " | " .. tostring(debuff.showTimer) .. " " .. tostring(debuff.selfDebuffs), "48 dim fade nil nil | false true",
        "each bar's settings unlike the defaults, and only those")
    Equal(tostring(cd.point) .. " " .. tostring(cd.x) .. " " .. tostring(cd.wrap) .. " " .. tostring(debuff.grow) .. " | "
        .. tostring(util.point == ns.BarData("util").point and util.x == ns.BarData("util").x and util.y == ns.BarData("util").y),
        "nil nil nil nil | true", "no spot or way to grow for a bar the layout places (it works them out again), a bar taken out keeps its spot")
    Equal(H.Text(shared.setup.colours), H.Text({ [1234] = "blue", [5678] = "class" }), "Tracked Bar colours")
    Equal(shared.setup.layout.preset .. " " .. shared.setup.layout.gap .. " " .. tostring(shared.setup.layout.hidden.util)
        .. " " .. shared.setup.layout.left .. " " .. shared.setup.layout.right, "sides 3 true buff debuff", "and the layout")
    Equal(P.Describe(shared), "Holds 14 bar entries and 2 pulse ticks, with its look and layout.", "said in a line")

    -- Another account: its own profile and settings.
    character = { guid = "Player-1-0077", name = "Kess", realm = "Zephras" }
    local ns2 = Start({ notesSeen = "dev", helpSeen = true, useBars = true, accent = "orange", keybinds = false, listItems = false })
    ns2.Bars:Assign("Wrath", "cd")
    local db = ForeverEnhancedCooldownManagerDB
    local own = ns2.ProfileName()
    local ownBefore = H.Text(db.profiles[own])
    local shared2 = ns2.ProfileShare.Read(text)
    local redrawn = H.Spy(ns2)
    -- The box's name when none is typed (the string has none).
    local ran, done, message, importTried, name = H.Trap(ns2.ProfileShare.Import, ns2.ProfileShare.IMPORTED, shared2, true)
    Equal(redrawn(), "cast bar, display, font, icon decor, icon glow, icon keys, raid timers, restyled bars",
        "everything that shows the look is drawn again, as the pages do on a change")
    Equal(tostring(ran and done) .. " " .. #importTried .. " | " .. tostring(name) .. " | " .. tostring(message),
        "true 0 | Shared profile | Imported Shared profile with its look and layout, and switched to it.",
        "imported with its look and layout, running nothing, as \"Shared profile\" when no name is typed")
    Equal(ns2.ProfileName() .. " | " .. tostring(db.chars["Player-1-0077"]), "Shared profile | Shared profile",
        "and this character switched to it")
    Equal(H.ProfileNow(ns2), profile, "every list, join, pulse tick and Long style the same")
    Equal(H.SetupNow(ns2), setup, "the look, every bar's settings and spot, the layout and the colours the same")
    Equal(H.Text(ns2.CustomSpells()["Power Word: Fortitude"]), "{[1]=1243}", "the spell added by ID, added here too")
    Equal(H.Text(db.profiles[own]), ownBefore, "the importer's own profile is as it was")
    Equal(ns2.Get("accent") .. " " .. tostring(ns2.Get("keybinds")) .. " " .. tostring(ns2.Get("castBar")) .. " "
        .. tostring(ns2.Get("pulse")) .. " " .. tostring(ns2.Get("minimap")) .. " " .. tostring(ns2.Get("growArrows")) .. " "
        .. tostring(ns2.Get("listItems")), "orange false false false true false false",
        "nothing the string doesn't carry changes: the accent, and every part still on or off as it was")
    Equal(ns2.ProfileShare.Export(), text, "and it shares the very same string back")
    Equal(table.concat((ns2.Bars:Mine("cd")), ","), "Moonfire,Wrath,slot:13,family:healing,Moonfire@1",
        "the bars show it: a druid's own, the warrior's spell left off")
end

-- Import makes a new profile, and leaves yours as it is ----------------------------------------------

do
    character = { guid = "Player-1-0001", name = "Zriel", realm = "Zephras" }
    local ns = Start({ notesSeen = "dev", helpSeen = true, useBars = true, barStyle = "outline" })
    local P, B = ns.ProfileShare, ns.Bars
    B:Assign("Moonfire", "cd")
    ns.SetPulsePick("Moonfire", true)
    local db = ForeverEnhancedCooldownManagerDB
    db.chars["Player-1-0009"] = "Zriel (Druid) - Zephras" -- another character on it too
    local own = ns.ProfileName()
    local before, setup = H.Text(db.profiles[own]), H.SetupNow(ns)
    -- Someone else's, with the same name as yours, a look and a layout.
    local text = H.String({ n = own, a = "1.5.3", l = { cd = { "Wrath" }, util = {}, buff = {}, debuff = {} },
        g = { s = { barStyle = "glass" }, b = { cd = { size = 60 } }, l = { on = true, preset = "wide", base = "wide" }, k = {} } })
    local shared = P.Read(text)
    local redrawn = H.Spy(ns)
    local ok, message, name = P.Import(shared.name, shared, false)
    Equal(redrawn(), "", "unticked, nothing about the look is drawn again")
    Equal(tostring(ok) .. " | " .. tostring(name) .. " | " .. tostring(message), "true | Zriel (Druid) - Zephras 2 | "
        .. "Imported Zriel (Druid) - Zephras 2, and switched to it.", "a name that's taken gets a number after it")
    Equal(ns.ProfileName() .. " | " .. table.concat(ns.ActiveList("cd"), ","), "Zriel (Druid) - Zephras 2 | Wrath",
        "you're on the new profile, with its spells")
    Equal(H.Text(db.profiles[own]), before, "yours is exactly as it was")
    Equal(H.SetupNow(ns), setup, "unticked, its look and layout don't come: yours stay")
    Equal(db.chars["Player-1-0009"], own, "another character on your old profile stays on it")
    shared.lists.cd[1] = "Starfire"
    Equal(db.profiles[name].cd[1], "Wrath", "the new profile is its own copy, not the string's")
    ok, message, name = P.Import(own, P.Read(text), false)
    Equal(tostring(name), "Zriel (Druid) - Zephras 3", "again: the next number")
    ok, message, name = P.Import("Raid night", P.Read(text), false)
    local second = select(3, P.Import("Raid night", P.Read(text), false))
    Equal(tostring(name) .. " | " .. tostring(second), "Raid night | Raid night 2", "a name typed is used, or numbered if taken")
    local long = ("N"):rep(48)
    P.Import(long, P.Read(text), false)
    name = select(3, P.Import(long, P.Read(text), false))
    Equal(tostring(name) .. " " .. #tostring(name), ("N"):rep(46) .. " 2 48", "a long name taken: cut so its number fits")
    local count = #ns.ProfileNames()
    local refusals = {}
    for _, try in ipairs({ { "Bad|Name", P.Read(text) }, { "   ", P.Read(text) }, { "Fine", nil } }) do
        local good, why = P.Import(try[1], try[2], false)
        refusals[#refusals + 1] = tostring(good) .. " " .. tostring(why)
    end
    lockdown = true
    local good, why = P.Import("In a fight", P.Read(text), true)
    lockdown = false
    refusals[#refusals + 1] = tostring(good) .. " " .. tostring(why)
    Equal(table.concat(refusals, " | ") .. " | " .. (#ns.ProfileNames() - count), "false Profile names can't use the | character. | "
        .. "false Type a profile name first. | false Paste a profile first. | false Profiles can't change in combat. | 0",
        "a bad name, no name, nothing read or a fight: refused, and nothing made")
    Equal(ns.Get("barStyle"), "outline", "a refusal with the look ticked changes no look either")
    -- Core repairs whatever it's handed, even unchecked: a bad look setting
    -- or one that isn't shared, a size out of range, a broken layout.
    ok = ns.ImportProfile("Unchecked", { lists = { cd = { "Wrath", 7, "" } }, pick = { Wrath = "yes" },
        setup = { look = { barStyle = "evil", accent = "teal", useBars = false, font = "skurri" }, bars = { cd = { size = 999, grow = "up" } },
            layout = { on = "yes", above = { "cd", "cd" }, hidden = { cd = "yes" } }, colours = { [0] = "blue", [12] = "neon" } } }, true)
    local layout = ns.LayoutData()
    Equal(tostring(ok) .. " | " .. table.concat(ns.ActiveList("cd"), ",") .. " | " .. H.Text(ns.PulsePicks()) .. " | " .. ns.Get("barStyle")
        .. " " .. ns.Get("accent") .. " " .. tostring(ns.Get("useBars")) .. " " .. ns.Get("font") .. " | " .. ns.BarData("cd").size .. " "
        .. ns.BarData("cd").grow .. " | " .. tostring(layout.on) .. " " .. table.concat(layout.above, ",") .. " " .. H.Text(layout.hidden)
        .. " | " .. H.Text(ns.BarColours()) .. " | " .. tostring(db.barStyle),
        "true | Wrath | {} | glass purple true skurri | 64 centre | false cd {} | {} | nil",
        "Core.lua repairs what comes in: only sane values stay (nothing bad even saved), and nothing it doesn't share changes")
    -- A spell you added by ID yourself keeps your IDs; one new to you comes with the string's.
    ns.ActiveList("buff")[1] = "Power Word: Fortitude"
    ns.AddCustom("Power Word: Fortitude", { 10938 })
    B:Changed()
    P.Import("Added", P.Read(H.String({ l = { buff = { "Power Word: Fortitude", "Spirit Link" } },
        c = { ["Power Word: Fortitude"] = { 1243 }, ["Spirit Link"] = { 9999 } } })), false)
    Equal(H.Text(ns.CustomSpells()["Power Word: Fortitude"]) .. " " .. H.Text(ns.CustomSpells()["Spirit Link"]), "{[1]=10938} {[1]=9999}",
        "spells added by ID: yours keep your IDs, one new to you comes with the string's")
    -- A name on one of your profiles the game doesn't know (so it shows
    -- nothing there): the string's IDs for it don't come, as they'd show on
    -- yours too (added spells are every profile's).
    P.Import("Mine again", P.Read(H.String({ l = { buff = { "Totally Unknown Spell" } } })), false)
    local mineAgain = ns.ProfileName()
    P.Import("Theirs", P.Read(H.String({ l = { buff = { "Totally Unknown Spell", "Brand New Spell" } },
        c = { ["Totally Unknown Spell"] = { 1243 }, ["Brand New Spell"] = { 1244 } } })), false)
    Equal(tostring(ns.CustomSpells()["Totally Unknown Spell"]) .. " " .. H.Text(ns.CustomSpells()["Brand New Spell"]), "nil {[1]=1244}",
        "a name already on one of your profiles takes no IDs from a string; one on none of them does")
    ns.UseProfile(mineAgain)
    ns.Spells:Stale()
    Equal(ns.ProfileName() .. " " .. tostring(ns.Spells:Find("Totally Unknown Spell")), "Mine again nil",
        "back on yours, it still shows nothing")
end

-- Another class's spells stay in it, off your bars ----------------------------------------------------
-- A warrior's profile on a druid: each character only shows its own class's
-- spells, as with a profile shared between characters.

do
    character = { guid = "Player-1-0005", name = "Ayla", realm = "Zephras" }
    local ns = Start({ notesSeen = "dev", helpSeen = true, useBars = true })
    local P, B = ns.ProfileShare, ns.Bars
    local text = H.String({ n = "Grom (Warrior) - Zephras", l = { cd = { "Mortal Strike", "Moonfire", "Execute" },
        util = { "Sinister Strike", "Wrath" }, buff = { "Battle Shout", "Thorns" }, debuff = { "Rend", "Moonfire" } } })
    local shared = P.Read(text)
    Equal(tostring(shared.setup) .. " | " .. P.Describe(shared), "nil | Holds 9 bar entries.", "a string with no look or layout")
    P.Import(shared.name, shared, false)
    local mine = {}
    for _, key in ipairs(ns.BAR_KEYS) do mine[#mine + 1] = key .. ": " .. table.concat((B:Mine(key)), ",") end
    Equal(table.concat(mine, " | "), "cd: Moonfire | util: Wrath | buff: Thorns | debuff: Moonfire",
        "only a druid's spells are yours")
    Equal(table.concat(ns.BarData("cd").spells, ",") .. " | " .. table.concat(ns.BarData("buff").spells, ","),
        "Mortal Strike,Moonfire,Execute | Battle Shout,Thorns", "the warrior's stay in the profile, for a warrior using it")
    Equal(B:Get("cd").count .. " " .. B:Get("util").count, "1 1", "and only yours go on the bars")
    SlashCmdList.FECM("")
    Equal(tostring(S[FECMFrame.nav.cd.count].text), "1", "the window's bar list counts yours only")
end

-- Broken, cut short, huge, nested, wrong and hostile strings ------------------------------------------
-- Each read without an error and without running anything: nothing back and
-- why, or a profile whose every value is sane.

do
    character = { guid = "Player-1-0001", name = "Zriel", realm = "Zephras" }
    local ns = Start({ notesSeen = "dev", helpSeen = true, useBars = true })
    local P = ns.ProfileShare
    ns.Bars:Assign("Moonfire", "cd")
    ns.Bars:SetAura("buff", "Thorns", true)
    ns.SetPulsePick("Moonfire", true)
    local good = P.Export()
    local body = good:sub(7)
    local errors, ran, insane, results = {}, {}, {}, {}
    -- Reads one, noting anything wrong; gives back what it read.
    local function Try(label, text)
        local ok, shared, why, tried = H.Trap(P.Read, text)
        if not ok then errors[#errors + 1] = label .. ": " .. tostring(shared) end
        for _, name in ipairs(tried) do ran[#ran + 1] = label .. ": " .. name end
        if ok and shared ~= nil then
            local problem = type(shared) == "table" and H.Sane(ns, shared) or "not a table"
            if problem ~= "" then insane[#insane + 1] = label .. ": " .. problem end
            if why ~= nil then insane[#insane + 1] = label .. ": a profile and a reason" end
        elseif ok and text:find("%S") and type(why) ~= "string" then
            insane[#insane + 1] = label .. ": no profile and no reason"
        end
        results[label] = ok and (shared ~= nil and "read" or tostring(why)) or "error"
        return shared, why
    end
    local function Found(list) return #list == 0 and "none" or table.concat(list, "; ", 1, math.min(#list, 3)) end

    -- Fixed cases, each with what it must say.
    local cases = {
        { "empty", "", "nil" }, { "spaces", "  \n\t ", "nil" },
        { "prefix only", "FECM1:", P.DAMAGED }, { "padding only", "FECM1:====", P.DAMAGED },
        { "one letter", "FECM1:A", P.DAMAGED }, { "three nothings", "FECM1:AAAA", P.DAMAGED },
        { "a stray =", "FECM1:A===", P.DAMAGED }, { "not Base64", "FECM1:!!!!", P.DAMAGED },
        { "an = inside", "FECM1:AA==" .. body, P.DAMAGED }, { "one more =", good .. "=", P.DAMAGED },
        { "more after it", good .. "AAAA", P.DAMAGED },
        { "lower case", "fecm1:" .. body, P.NOT_OURS }, { "no number", "FECM:" .. body, P.NOT_OURS },
        { "version 0", "FECM0:" .. body, P.NOT_OURS }, { "a newer version", "FECM2:" .. body, P.NEWER },
        { "a huge version", "FECM99999999999999999999:" .. body, P.NEWER },
        { "the cursor's", "FEC1:" .. body, P.NOT_OURS }, { "raid frames'", "FERF1:" .. body, P.NOT_OURS },
        { "a semicolon", "FECM1;" .. body, P.NOT_OURS },
        -- A whole message pasted: read from FECM1: to the last Base64 letter;
        -- one that doesn't read then says to copy only the string.
        { "something before", "XFECM1:" .. body, "read" }, { "colour codes round it", "|cffff0000" .. good .. "|r", "read" },
        { "a message round it", "my profile: " .. good .. " :)", "read" },
        { "a code block with a language", "```txt\n" .. good .. "\n```", "read" },
        { "words before, cut short", "here: " .. good:sub(1, -9), P.PART },
        { "words run into it", "here: " .. good .. "enjoy", P.PART }, { "run into words, nothing before", good .. "enjoy", P.DAMAGED },
        { "code marks before, cut short", "```" .. good:sub(1, -9) .. "```", P.DAMAGED },
        { "a word before the prefix only", "my FECM1:", P.PART },
        { "plain words", "Here is my setup, enjoy", P.NOT_OURS }, { "Lua", "return loadstring('x')()", P.NOT_OURS },
        { "a slash command", "/run RunScript('x')", P.NOT_OURS },
        { "code, packed", H.String("loadstring(\"print(1)\")()"), P.DAMAGED },
        { "not a table", H.String("T"), P.NOT_OURS }, { "a list", H.String({ "a", "b" }), P.NOT_OURS },
        { "a table of nothing known", H.String({ x = 1, y = { 2 } }), P.NOT_OURS },
        { "far too long", ("x"):rep(70000), P.TOO_LONG }, { "just too long", "FECM1:" .. ("A"):rep(P.MAX_TEXT), P.TOO_LONG },
        { "in code marks", "`" .. good .. "`", "read" }, { "in quotes", '"' .. good .. '"', "read" },
        { "with line breaks", good:sub(1, 20) .. "\n" .. good:sub(21, 50) .. " \r\n " .. good:sub(51), "read" },
        { "deep tables", H.String(("{S1:a"):rep(1000) .. "T" .. ("}"):rep(1000)), P.DAMAGED },
        { "deep lists", H.String(("["):rep(5000) .. ("]"):rep(5000)), P.DAMAGED },
        { "five deep", H.String({ g = { b = { cd = { size = { 1 } } } } }), P.DAMAGED },
        { "four deep", H.String({ g = { b = { cd = { size = 40 } } } }), "read" },
        { "too many values", H.String({ l = { cd = (function() local t = {} for i = 1, 5000 do t[i] = "a" end return t end)() } }), P.DAMAGED },
        { "a key twice", H.String("{S1:lS1:xS1:lS1:y}"), P.DAMAGED }, { "a table as a key", H.String("{[]T}"), P.DAMAGED },
        { "a ture as a key", H.String("{TT}"), P.DAMAGED }, { "unclosed", H.String("{S1:l[S1:a"), P.DAMAGED },
        { "text too long for itself", H.String("{S1:lS99:abc}"), P.DAMAGED }, { "text cut short", H.String("{S1:lS2:abc}"), P.DAMAGED },
        { "a length too big", H.String("{S1:lS1000:a}"), P.DAMAGED }, { "no length", H.String("{S1:lS:}"), P.DAMAGED },
        { "a hex number", H.String("{S1:lN0x10;}"), P.DAMAGED }, { "infinity", H.String("{S1:lN1e999;}"), P.DAMAGED },
        { "not a number", H.String("{S1:lNnan;}"), P.DAMAGED }, { "two points", H.String("{S1:lN1.5.5;}"), P.DAMAGED },
        { "two minuses", H.String("{S1:lN--1;}"), P.DAMAGED }, { "a long number", H.String("{S1:lN" .. ("1"):rep(30) .. ";}"), P.DAMAGED },
        { "no semicolon", H.String("{S1:lN12}"), P.DAMAGED }, { "a stray letter", H.String("{S1:lX}"), P.DAMAGED },
        { "a nul byte", H.String("{S1:l\0}"), P.DAMAGED }, { "nothing after a key", H.String("{S1:l}"), P.DAMAGED },
    }
    local wrong = {}
    for _, case in ipairs(cases) do
        Try(case[1], case[2])
        if results[case[1]] ~= case[3] then wrong[#wrong + 1] = case[1] .. " said " .. results[case[1]] end
    end
    Equal(table.concat(wrong, "; "), "", "each broken, wrong or hostile string says why, in plain words (" .. #cases .. " of them)")
    -- Cut short anywhere: never read as a profile.
    local cut = 0
    for i = 0, #good - 1 do
        Try("cut at " .. i, good:sub(1, i))
        if results["cut at " .. i] == "read" then cut = cut + 1 end
    end
    Equal(cut, 0, "the string cut short at every length (" .. #good .. "): never read as a profile")
    -- A letter changed anywhere, three ways.
    local letters = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/="
    for i = 7, #good do
        for _ = 1, 3 do
            local at = H.Random(#letters) + 1
            Try("changed at " .. i, good:sub(1, i - 1) .. letters:sub(at, at) .. good:sub(i + 1))
        end
    end
    -- Random Base64, and random bytes.
    for n = 1, 300 do
        local text = {}
        for _ = 1, 4 * (1 + H.Random(100)) do
            local at = H.Random(64) + 1
            text[#text + 1] = letters:sub(at, at)
        end
        Try("random Base64 " .. n, "FECM1:" .. table.concat(text))
        local bytes = {}
        for _ = 1, 1 + H.Random(300) do bytes[#bytes + 1] = string.char(H.Random(256)) end
        Try("random bytes " .. n, table.concat(bytes))
        Try("random packed bytes " .. n, H.String(table.concat(bytes)))
    end
    -- Random pieces of the format itself, so the reader is walked down every path.
    local pieces = { "{", "}", "[", "]", "T", "F", "N1;", "N-2.5;", "N1e3;", "N40;", "S0:", "S1:l", "S1:g", "S1:s", "S1:b", "S1:n",
        "S1:p", "S1:j", "S2:cd", "S4:util", "S4:buff", "S6:debuff", "S8:Moonfire", "S6:Thorns", "S4:size", "S7:preset", "S4:wide",
        "S8:barStyle", "S5:split", "S3:|cf", "S2:a\0", "S99:x" }
    for n = 1, 1500 do
        local text = {}
        for _ = 1, 1 + H.Random(60) do text[#text + 1] = pieces[H.Random(#pieces) + 1] end
        Try("random pieces " .. n, H.String(table.concat(text)))
        Try("random pieces in a table " .. n, H.String("{S1:l{S2:cd[" .. table.concat(text) .. "]}S1:g{" .. table.concat(text) .. "}}"))
    end
    -- Random profiles: the right shape, with any keys and values in it, so
    -- the checks on what's kept are walked down every path too.
    local read = 0
    for n = 1, 1500 do
        local label = "random profile " .. n
        Try(label, H.String(H.RandomProfile()))
        if results[label] == "read" then read = read + 1 end
    end
    Equal(read > 300, true, "hundreds of random profiles read, so the checks on what's kept are tried (" .. read .. " of 1500)")
    Equal(Found(errors), "none", "no string ever errors")
    Equal(Found(ran), "none", "no string ever runs anything: no loadstring, load, RunScript or the like is called")
    Equal(Found(insane), "none", "every profile read is sane, and every refusal says why")
end

-- A hostile string that reads: only what's known and sane is kept ------------------------------------
-- Code as names, colour codes, links, control characters, wrong types,
-- numbers out of range, unknown bars, keys and settings, settings that would
-- switch parts on: each left out and counted, or kept as plain text that's
-- never run and never shows.

do
    character = { guid = "Player-1-0001", name = "Zriel", realm = "Zephras" }
    local ns = Start({ notesSeen = "dev", helpSeen = true, accent = "purple" })
    local P = ns.ProfileShare
    local code = 'loadstring("print(1)")()'
    local hostile = {
        n = "Evil|cffff0000Red|r\nName" .. ("x"):rep(80), a = "1.5.3; os.exit()",
        l = { cd = { "Moonfire", "Moonfire", code, "RunScript('x')", "|cffff0000Red|r", "|TInterface\\Icons\\X:0|t", "a\0b", "a\nb",
            " Moonfire", "Wrath ", ("W"):rep(65), "item:118", "item:0", "item:-1", "item:99999999999", "item:0118", "slot:13", "slot:99",
            "family:healing", "family:evil", "Moonfire@3", "Moonfire@999", "@3", "ammo", 42, true, { "nested" } },
            util = { "Moonfire", "Overpower" }, buff = "Thorns", debuff = { [1] = "Rend", [3] = "Garrote", x = "y" },
            extra = { "Moonfire" } },
        j = { buff = { Thorns = true }, debuff = { Rend = true }, cd = { Moonfire = true } },
        p = { Moonfire = true, Wrath = "yes", ["|cffEvil"] = true, [7] = true },
        q = { Moonfire = "long", Wrath = "short" },
        c = { [code] = { 1, 1.5, -3, 1e12, "7", 99 }, NotListed = { 5 }, Moonfire = {} },
        g = { s = { barStyle = "evil", accent = "teal", useBars = true, castBar = true, pulse = true, keybinds = true,
                skin = false, castHeight = 999, pulseX = 5000, font = "arial", prdMatch = "yes", iconBorder = "bar" },
            b = { cd = { size = 1e300, spacing = -5, grow = "up", point = "EVIL", x = 3999, y = -4000, showTimer = "no",
                whenReady = "dim", evil = true }, zz = { size = 40 } },
            l = { on = "yes", preset = "evil", base = "wide", gap = 99, spacing = 3, above = { "cd", "zz", 7 }, below = "util",
                hidden = { cd = true, util = "yes", zz = true }, left = "nope", right = "buff", evil = 1 },
            k = { [1234] = "blue", [0] = "blue", [1.5] = "blue", [-3] = "blue", x = "blue", [99] = "neon" } },
        evil = "x", [1] = "y",
    }
    local text = H.String(hostile)
    local ok, shared, why, tried = H.Trap(P.Read, text)
    Equal(tostring(ok) .. " " .. tostring(why) .. " " .. #tried .. " " .. H.Sane(ns, shared) .. "|", "true nil 0 |",
        "a hostile string that reads: no error, nothing run, every value sane")
    Equal(tostring(shared.name:find("[%c|]")) .. " " .. #shared.name .. " " .. tostring(shared.version), "nil 48 nil",
        "its name without codes or line breaks, cut to fit; a version that isn't one left out")
    Equal(table.concat(shared.lists.cd, ","), "Moonfire," .. code .. ",RunScript('x'),item:118,slot:13,family:healing,Moonfire@3,ammo",
        "only plain names and keys the bars know, each once: code kept only as a name, never run")
    Equal(table.concat(shared.lists.util, ",") .. " | " .. table.concat(shared.lists.buff, ",") .. " | "
        .. table.concat(shared.lists.debuff, ","), "Overpower |  | Rend",
        "a spell on one cooldown bar only, no list from text, a list only up to its first gap")
    Equal(H.Text(shared.joins) .. " " .. H.Text(shared.pick) .. " " .. H.Text(shared.style),
        '{["buff"]={},["debuff"]={}} {["Moonfire"]=true} {["Moonfire"]="long"}',
        "joins only to an entry before them on the Buffs or Debuffs bar; ticks and Long only as they're kept")
    Equal(H.Text(shared.added), H.Text({ [code] = { 1, 99 } }), "added spells only for names on its bars, with whole IDs")
    Equal(H.Text(shared.setup.look), H.Text({ font = "arial", iconBorder = "bar" }),
        "only look settings, each valid: nothing that switches a part on, never the accent")
    Equal(H.Text(shared.setup.bars.cd) .. " " .. tostring(shared.setup.bars.zz), H.Text({ whenReady = "dim", x = 3999 }) .. " nil",
        "bar settings only in range and of their kind, only for your four bars")
    Equal(H.Text(shared.setup.layout), H.Text({ base = "wide", spacing = 3, right = "buff", above = { "cd" }, below = {},
        hidden = { cd = true } }), "the layout's known settings, each valid")
    Equal(H.Text(shared.setup.colours), "{[1234]=\"blue\"}", "Tracked Bar colours by whole spell IDs, in a bar colour")
    Equal(shared.skipped, 64, "everything else left out and counted")
    Equal(P.Describe(shared), "Holds 10 bar entries and 1 pulse tick, with its look and layout. 64 left out, as this version"
        .. " doesn't use them.", "and the box says so")
    -- Imported with its look and layout: still nothing run, nothing switched on.
    local ran, done, message, importTried = H.Trap(P.Import, "Hostile", shared, true)
    Equal(tostring(ran and done) .. " " .. #importTried .. " " .. tostring(message), "true 0 Imported Hostile with its look and layout, and"
        .. " switched to it. Your bars are off: tick Use my bars on General.", "imported: nothing run")
    Equal(tostring(ns.Get("useBars")) .. " " .. ns.Get("accent") .. " " .. tostring(ns.Get("castBar")) .. " " .. tostring(ns.Get("pulse"))
        .. " " .. tostring(ns.Get("keybinds")) .. " " .. tostring(ns.Get("skin")), "false purple false false false true",
        "your bars, the accent and every part stay as they were")
    Equal(ns.Get("font") .. " " .. ns.LayoutData().base .. " " .. table.concat(ns.LayoutData().below, ","), "arial wide util,debuff",
        "its sane look and layout came, repaired as they went in (a bar in no row goes under the display)")
    local shown, _, _, shownTried = H.Trap(function()
        ns.Set("useBars", true)
        ns.Bars:Rebuild()
        SlashCmdList.FECM("")
        FECMFrame:Select("cd")
        FECMFrame:Refresh()
    end)
    Equal(tostring(shown) .. " " .. #shownTried .. " " .. tostring(ns.BarData("cd").spells[2] == code), "true 0 true",
        "code as a name is only text: kept in the profile, and the bars and window draw it without running anything")
end

-- Share only hands out strings Import reads ---------------------------------------------------------
-- A profile too big to read back, by its letters or by how many values it
-- holds, is refused with a reason: never a string Import turns away, nor one
-- the copy box would cut.

do
    character = { guid = "Player-1-0001", name = "Zriel", realm = "Zephras" }
    local ns = Start({ notesSeen = "dev", helpSeen = true, useBars = true })
    local P = ns.ProfileShare
    ns.Bars:Assign("Moonfire", "cd")
    -- The bytes a string unpacks to, from its Base64.
    local function Bytes(text)
        local body = text:sub(7)
        return #body / 4 * 3 - #body:match("=*$")
    end
    -- Pulse ticks with 64-letter names (69 bytes each) to just under the
    -- most a string may hold, then one-letter ones (5 bytes each) across it.
    ns.SetPulsePick("a", true) -- the pulse list itself, so each tick after adds only its own bytes
    local start = Bytes(P.Export())
    for i = 1, math.floor((23990 - start) / 69) do ns.SetPulsePick(("%03d"):format(i) .. ("x"):rep(61), true) end
    local size = Bytes(P.Export())
    local letters, wrong, edge = "bcdefghijklmnopqrstuvwxyz", {}, {}
    for i = 1, 20 do
        ns.SetPulsePick(letters:sub(i, i), true)
        size = size + 5
        local ok, text, why, tried = H.Trap(P.Export)
        local got = not ok and "an error" or #tried > 0 and "ran something"
            or text and (text:sub(1, 6) == "FECM1:" and Bytes(text) == size and P.Read(text) ~= nil and #text <= P.MAX_TEXT
                and "reads" or "a string that doesn't read: " .. #text)
            or why == P.TOO_MUCH and "too much" or tostring(why)
        local want = size <= 23994 and "reads" or "too much"
        if got ~= want then wrong[#wrong + 1] = size .. " bytes: " .. got end
        if size >= 23995 and size <= 24000 then edge[#edge + 1] = size end
    end
    Equal(table.concat(wrong, "; "), "", "growing past the limit: every string Share makes reads back, and past it Share says"
        .. " it's too much (from 23,995 bytes, over " .. P.MAX_TEXT .. " letters)")
    Equal(#edge > 0, true, "tried just past the longest string, packed small enough but too long in letters")
    -- Too many values to read (each tick is two), though short enough.
    local ns2 = Start({ notesSeen = "dev", helpSeen = true, useBars = true })
    for i = 1, 2100 do ns2.SetPulsePick(("p%04d"):format(i), true) end
    local text, why = ns2.ProfileShare.Export()
    Equal(tostring(text) .. " " .. tostring(why), "nil " .. P.TOO_MUCH, "2,100 pulse ticks (too many values to read): too much to share")
    SlashCmdList.FECM("")
    local w = FECMFrame
    w.profileButton:Click()
    w.profileShare:Click()
    Equal(tostring(S[w.shareBox.shade].shown) .. " " .. S[w.note].text, "false " .. P.TOO_MUCH,
        "Share says so in the footer, and no box opens")
    w:Hide()
    Equal(#printed, 0, "no errors")
end

-- The profile menu: Share and Import -------------------------------------------------------------------

do
    character = { guid = "Player-1-0001", name = "Zriel", realm = "Zephras" }
    local ns = Start({ notesSeen = "dev", helpSeen = true, useBars = true, barStyle = "outline" })
    local P, B = ns.ProfileShare, ns.Bars
    B:Assign("Moonfire", "cd")
    SlashCmdList.FECM("")
    local w = FECMFrame
    local box = w.shareBox
    w.profileButton:Click()
    local function Points(frame)
        local p = S[frame].points[1]
        return p and (p[1] .. " " .. tostring(p[2] == nil or type(p[2]) == "table" and "frame" or p[2]) .. " "
            .. tostring(p[3]) .. " " .. tostring(p[4])) or "none"
    end
    Equal(S[w.profileShare.label].text .. " " .. S[w.profileImport.label].text .. " | " .. Points(w.profileImport) .. " | "
        .. Points(w.profileShare), "Share Import | TOPRIGHT -10 -6 nil | RIGHT frame LEFT -4",
        "Share and Import at the top right of the profile menu, level with its heading")
    Equal(S[w.profileInput].points[1][3] .. " " .. S[w.profileList].points[2][5], "-54 -50",
        "the list and the name box where they were")
    Equal(tostring(rawget(w.profileShare, "hint")) .. " | " .. tostring(rawget(w.profileImport, "hint")),
        "Your profile, with your bars' look and layout, as text to copy and share. | "
        .. "Paste a shared profile to make it a new profile. Yours stays as it is.", "each says what it does")

    -- Share: the string, selected, to copy; it can't be typed over.
    w.profileShare:Click()
    Equal(tostring(S[box.shade].shown) .. " " .. tostring(S[w.profilePanel].shown) .. " " .. S[box.title].text .. " "
        .. tostring(S[box.copy].shown) .. " " .. tostring(S[box.paste].shown) .. " " .. tostring(S[box.make].shown) .. " "
        .. S[box.no.label].text, "true false SHARE A PROFILE true false false Close",
        "Share opens the box over the window, the menu put away: the string and Close")
    Equal(box.copy:GetText() == P.Export(), true, "the string is the profile you're on")
    Equal(tostring(S[box.copy].last.HighlightText ~= nil) .. " " .. tostring(S[box.copy].last.SetFocus ~= nil), "true true",
        "selected, ready for Ctrl+C")
    box.copy:SetText("typed over")
    S[box.copy].scripts.OnTextChanged(box.copy)
    Equal(box.copy:GetText() == P.Export(), true, "typing over it puts it back")
    -- Putting it back changes the text too, as the game tells it: even in a
    -- box that kept fewer letters than it was given (Share never makes one
    -- that long), it's put back once, never in a loop.
    local puts, set = 0, box.copy.SetText
    rawset(box.copy, "SetText", function(self, t)
        puts = puts + 1
        set(self, t:sub(1, 100))
        S[self].scripts.OnTextChanged(self)
    end)
    local fine = pcall(box.copy.SetText, box.copy, "typed again")
    rawset(box.copy, "SetText", nil)
    Equal(tostring(fine) .. " " .. puts, "true 2", "put back once, never in a loop")
    box.copy:SetText(P.Export())
    S[box.copy].last.HighlightText = nil
    S[box.copy].scripts.OnMouseUp(box.copy)
    Equal(S[box.copy].last.HighlightText ~= nil, true, "a click in it selects it all again, so Ctrl+C still copies it all")
    Equal(Last(box.copy, "SetMaxLetters") >= P.MAX_TEXT, true, "the box holds the longest string Share makes, uncut")
    Equal(S[box.detail].text, "Your profile, with your bars' look and layout, as text. Press Ctrl+C to copy it, then paste it"
        .. " where you like, such as Discord.", "and the box says how")
    box.no:Click()
    Equal(S[box.shade].shown, false, "Close puts it away")
    lockdown = true
    w.profileButton:Click()
    w.profileShare:Click()
    Equal(tostring(S[box.shade].shown) .. " " .. tostring(box.copy:GetText() == P.Export()), "true true", "sharing works in a fight too")
    lockdown = false
    box.no:Click()

    -- Import: nothing changes until the profile is made.
    local function Paste(text)
        box.paste:SetText(text)
        S[box.paste].scripts.OnTextChanged(box.paste)
    end
    local function Colour(text)
        local c = S[text].colour
        return c and (c[1] .. "," .. c[2] .. "," .. c[3]) or "none"
    end
    w.profileButton:Click()
    w.profileImport:Click()
    Equal(tostring(S[box.shade].shown) .. " " .. S[box.title].text .. " " .. tostring(S[box.paste].shown) .. " "
        .. tostring(S[box.copy].shown) .. " " .. tostring(S[box.look].shown) .. " " .. S[box.no.label].text .. " "
        .. tostring(box.make.usable) .. " | " .. S[box.status].text, "true IMPORT A PROFILE true false false Cancel false | "
        .. "Paste a profile to see what it holds.", "Import opens the box: a place to paste, Make greyed until a profile's there")
    Paste("Here is my setup")
    Equal(S[box.status].text .. " " .. Colour(box.status) .. " " .. tostring(box.make.usable), P.NOT_OURS .. " 1,0.45,0.3 false",
        "anything else says so, in the warning colour")
    local mine = P.Export()
    Paste("Here you go: ```txt\n" .. mine .. "\n``` have fun")
    Equal(S[box.status].text .. " " .. tostring(box.make.usable), "Holds 1 bar entry, with its look and layout. true",
        "a whole Discord message pasted, the string in a code block: it reads")
    Paste("Here you go: " .. mine:sub(1, -20))
    Equal(S[box.status].text .. " " .. Colour(box.status) .. " " .. tostring(box.make.usable), P.PART .. " 1,0.45,0.3 false",
        "a message whose string doesn't read: copy only the string")
    Equal(S[box.detail].text, "Paste a profile someone shared. It becomes a new profile, and yours stays as it is."
        .. " Spells your class can't use don't show.", "the box says another class's spells won't show")
    local text = H.String({ n = "Grom (Warrior) - Zephras", l = { cd = { "Wrath" }, util = {}, buff = {}, debuff = {} },
        g = { s = { barStyle = "glass" }, b = {}, l = {}, k = {} }, future = "a key this version doesn't know" })
    Paste(text)
    Equal(S[box.status].text .. " | " .. box.name:GetText() .. " | " .. tostring(S[box.look].shown) .. " "
        .. tostring(box.look:GetChecked()) .. " " .. tostring(box.make.usable) .. " | " .. S[box.lookNote].text,
        "Holds 1 bar entry, with its look and layout. 1 left out, as this version doesn't use it. | Grom (Warrior) - Zephras | "
        .. "true false true | " .. P.LOOK_OFF, "a profile says what it holds, its name goes in the name box, and its look is offered, unticked")
    Paste("")
    Equal(box.name:GetText() .. "|" .. tostring(box.make.usable), "|false", "emptied, the name it put there goes with it")
    box.name:SetText("My pick")
    Paste(text)
    Equal(box.name:GetText(), "My pick", "a name typed stays over the string's own")
    box.name:SetText("")
    Paste(text)

    -- Its look ticked: asked first; Cancel changes nothing.
    Equal(S[box.look.text].text .. " | " .. tostring(rawget(box.look, "hint")), "Also use its look and layout (Needs testing) | Its bar"
        .. " sizes, spots, layout and look in place of yours, on every character. It asks first.", "the tick says it needs testing")
    box.look:Click()
    Equal(S[box.lookNote].text, P.LOOK_ON, "ticked, it says what changes")
    local count = #ns.ProfileNames()
    S[box.paste].last.ClearFocus, S[box.name].last.ClearFocus = nil, nil
    box.make:Click()
    local confirm = w.confirm
    Equal(tostring(S[box.paste].last.ClearFocus ~= nil) .. " " .. tostring(S[box.name].last.ClearFocus ~= nil), "true true",
        "the text boxes let go of the keyboard while it asks: keys don't type behind it, and Escape closes the window")
    Equal(tostring(S[confirm.shade].shown) .. " " .. S[confirm.dialog.title].text .. " | " .. S[confirm.dialog.detail].text,
        "true Use its look and layout too? | Your bar sizes, spots, layout and look change to the shared ones, on every character."
        .. " To keep a copy of yours, Share it first.", "Make asks first, saying what changes and how to keep yours")
    confirm.no:Click()
    Equal(tostring(S[box.shade].shown) .. " " .. (#ns.ProfileNames() - count) .. " " .. ns.Get("barStyle"), "true 0 outline",
        "Cancel: back in the box, nothing made or changed")
    local _, _, _, tried = H.Trap(function()
        box.make:Click()
        confirm.yes:Click()
    end)
    Equal(#tried .. " " .. tostring(S[box.shade].shown) .. " " .. tostring(S[w.profilePanel].shown) .. " | " .. ns.ProfileName() .. " | "
        .. ns.Get("barStyle") .. " | " .. S[w.note].text, "0 false false | Grom (Warrior) - Zephras | glass | Imported Grom (Warrior) -"
        .. " Zephras with its look and layout, and switched to it.", "yes: made, switched to, its look on, the box closed and the footer says so")

    -- Unticked: straight away, no question.
    w.profileButton:Click()
    w.profileImport:Click()
    Paste(mine)
    box.make:Click()
    Equal(tostring(S[confirm.shade].shown) .. " " .. ns.ProfileName() .. " " .. ns.Get("barStyle") .. " | " .. S[w.note].text,
        "false Shared profile glass | Imported Shared profile, and switched to it.",
        "unticked: made at once, as \"Shared profile\" (your own string carries no name), the look left as it is")
    -- Refused in a fight: the box stays and says why.
    w.profileButton:Click()
    w.profileImport:Click()
    Paste(mine)
    lockdown = true
    box.make:Click()
    lockdown = false
    Equal(tostring(S[box.shade].shown) .. " " .. S[box.status].text .. " " .. Colour(box.status),
        "true Profiles can't change in combat. 1,0.45,0.3", "in a fight: refused, the box stays and says why")
    w:Hide()
    Equal(S[box.shade].shown, false, "closing the window puts the box away")

    -- Every part of the box says what it does; the ? over the profile menu and the tour's Profiles step mention them.
    local missing = {}
    for _, part in ipairs({ box.shade, box, box.copy, box.paste, box.name, box.look, box.make, box.no }) do
        if rawget(part, "hint") == nil then missing[#missing + 1] = S[part].kind end
    end
    Equal(table.concat(missing, ","), "", "the box, its text boxes, tick and buttons each have a note in the footer")
    ns.ShowWindow()
    w.profileButton:Click()
    w.help:Click()
    Equal(S[w.note].text, "Profiles: click to use, x to delete, type a name to make one. Share or Import one as text.",
        "the ? over the profile menu mentions Share and Import")
    Equal(#S[w.note].text <= 91, true, "on one line, no longer than before")
    w.profileButton:Click()
    ns.Tour:Start()
    for _ = 1, 20 do
        if S[FECMTour.title].text == "PROFILES" then break end
        FECMTour.next:Click()
    end
    Equal(S[FECMTour.text].text:find("Share and Import trade profiles with other players as text.", 1, true) ~= nil, true,
        "the tour's Profiles step mentions them")
    ns.Tour:Stop()

    -- Words fit: about 7.5 units a letter, 6.5 in the small font (as Tools/TestHelp.lua counts).
    local function Wide(text, small) return #text * (small and 6.5 or 7.5) end
    Equal(tostring(14 + Wide(S[box.nameLabel].text, true) < 140) .. " " .. tostring(18 + Wide(S[box.look.text].text) < 452) .. " "
        .. tostring(Wide(S[box.make.label].text, true) < 130 - 8) .. " " .. tostring(Wide("Import", true) < 56 - 8) .. " "
        .. tostring(Wide(P.NOT_OURS, true) < 452) .. " " .. tostring(Wide(P.DAMAGED, true) < 452), "true true true true true true",
        "the labels fit their room, and a refusal fits on one line")
end

print = _G.print
Equal(SecretMisuse[1], nil, "no secret misused anywhere")
Equal(WidgetMisses[1], nil, "no method Forever lacks looked for anywhere")
io.write("Share checks passed: " .. checks .. " assertions.\n")
