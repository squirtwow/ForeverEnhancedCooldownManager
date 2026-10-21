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
function Proto:UnregisterEvent(e) S[self].events[e] = nil end
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
    -- Your form (Form: its ID, nil for none, or SECRET) and whether you're
    -- stealthed, as the game says; each ask counted (FormReads).
    Form, Stealthed, FormReads = nil, false, 0
    _G.GetShapeshiftFormID = function() FormReads = FormReads + 1; return Typed("number", Form) end
    _G.IsStealthed = function() return Typed("boolean", Stealthed) end
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
    -- Your buffs (PlayerAuras[id] = true, or SECRET for an answer the game
    -- keeps secret), as GetPlayerAuraBySpellID finds them, each ask counted
    -- (AuraReads). As on Forever: in a fight it finds none, even with them
    -- up, and C_Secrets says auras are secret then (AurasSecret: out of one).
    PlayerAuras, AuraReads, AurasSecret = {}, 0, false
    _G.C_UnitAuras = {
        GetPlayerAuraBySpellID = function(id)
            assert(type(id) == "number", "a spell ID")
            AuraReads = AuraReads + 1
            local aura = PlayerAuras[id]
            if lockdown or not aura then return nil end
            if rawequal(aura, SECRET) then return SECRET end
            return { spellId = id }
        end,
    }
    _G.C_Secrets = { ShouldAurasBeSecret = function() return lockdown or Typed("boolean", AurasSecret) end }
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
    for _, file in ipairs({ "Core.lua", "Style.lua", "Skin.lua", "Resource.lua", "CastBar.lua", "Ranks.lua", "Forms.lua", "Spells.lua", "Keybinds.lua", "Buffs.lua", "IconAuras.lua", "Bars.lua",
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

-- Your debuffs on you on the Debuffs bar too -------------------------------------------------------
-- A player looked for Weakened Soul on the Debuffs bar first. That bar's
-- container watches your target, and a container watches one unit, so your
-- debuffs on you get a second container of the bar's own, watching you. It's
-- made and driven as the Buffs bar's group for them is: the first time
-- they're ticked with your bars on, never in a fight (a tick then waits for it
-- to end), on a bar already holding a container (so never shown or hidden
-- after, B:Hold), in sight, each icon's look given as its group is added and
-- never after. The game sizes a container itself and nothing may hang off
-- one, so it's anchored to the bar: just past the bar's end the way it grows,
-- or in the bar's own spot while the bar has no entries.

-- A number as text, to four figures (1 and 1.0 alike).
local function Figure(v)
    return type(v) == "number" and ("%.4g"):format(v) or tostring(v)
end

-- Where the Debuffs bar's container for you sits: how many points, the
-- first one's point, whether it's on the bar, its point on the bar, the
-- offset, and the container's scale.
local function SelfSpot(bar)
    local own = bar.selfContainer
    if not own then return "none" end
    local points = S[own].points
    local p = points[1] or {}
    return #points .. " " .. tostring(p[1]) .. " " .. tostring(p[2] == bar) .. " " .. tostring(p[3]) .. " " .. Figure(p[4]) .. " "
        .. Figure(p[5]) .. " " .. Figure(S[own].scale)
end

-- The Debuffs bar's group for your debuffs on you, or an empty table.
local function SelfGroup(bar)
    local own = bar.selfContainer
    return own and S[own].groups.self or {}
end

do
    Fresh()
    local ns = Load({ useBars = true, notesSeen = "dev" })
    local B = ns.Bars
    B:SetAura("debuff", "Moonfire", true)
    local debuff = B:Get("debuff")
    Runs()
    local before = #containers
    Equal(tostring(ns.BarData("debuff").selfDebuffs) .. " " .. tostring(debuff.selfContainer) .. " " .. before, "false nil 2",
        "off at first: nothing more made than the Buffs and Debuffs bars' own containers")
    B:SetOption("debuff", "selfDebuffs", true)
    local own = debuff.selfContainer
    local s = own and S[own] or {}
    Equal(tostring(#containers - before) .. " " .. tostring(s.unit) .. " " .. tostring(s.parent == debuff) .. " " .. tostring(s.listening)
        .. " [" .. Runs() .. "] " .. containerCallsInCombat, "1 player true true [] 0",
        "ticked: one more container, on the bar, watching you, made in sight and hearing your auras, none of its own code run"
        .. " inside the addon's")
    local group = SelfGroup(debuff)
    local filters = group.filters or {}
    Equal(tostring(group.filter) .. " " .. tostring(group.enabled) .. " " .. tostring(filters.isFromPlayerOrPlayerPet) .. " "
        .. tostring(filters.includeSpellIDs) .. " " .. tostring(group.max) .. " " .. #(group.frames or {}),
        "HARMFUL true true nil 4 10", "one group for your debuffs on you, by who cast them, no spell IDs, up to four: as the Buffs bar's")
    local mine = S[debuff.container]
    Equal(mine.unit .. " " .. tostring(mine.groups.self) .. " " .. tostring(mine.groups.g1.enabled), "target nil true",
        "the bar's own container still watches your target, with nothing of yours on you in it")
    Equal(Figure(S[debuff.container].scale) .. " " .. tostring(S[debuff].shown) .. " " .. tostring(debuff.holds), "1 true true",
        "the bar was holding a container already: it's never shown or hidden for this one")
    -- Where it sits: past the bar's end, the bar's spacing from it, as big as
    -- the bar's own icons.
    Equal(SelfSpot(debuff), "1 LEFT true RIGHT 4 0 1", "just past the bar's right end (it grows from its centre), the bar's spacing from it")
    B:SetOption("debuff", "grow", "left")
    Equal(SelfSpot(debuff), "1 RIGHT true LEFT -4 0 1", "growing left: past its left end, away from where it's held")
    B:SetOption("debuff", "grow", "right")
    Equal(SelfSpot(debuff), "1 LEFT true RIGHT 4 0 1", "growing right: past its right end")
    B:SetOption("debuff", "size", 54)
    Equal(SelfSpot(debuff) .. " " .. Figure(S[debuff.container].scale), "1 LEFT true RIGHT 2.667 0 1.5 1.5",
        "bigger icons: scaled with the bar's own, the same room from it")
    B:SetOption("debuff", "size", 36)
    B:SetOption("debuff", "grow", "centre")
    -- No entries: in the bar's own spot, the bar showing for them alone.
    B:SetAura("debuff", "Moonfire", false)
    Equal(SelfSpot(debuff) .. " " .. tostring(InSight(debuff)) .. " " .. tostring(group.enabled), "1 CENTER true CENTER 0 0 1 true true",
        "no entries: in the bar's own spot, the bar still showing for your debuffs on you")
    B:SetOption("debuff", "grow", "right")
    Equal(SelfSpot(debuff), "1 LEFT true LEFT 0 0 1", "growing right with no entries: from the edge it grows from")
    B:SetOption("debuff", "grow", "centre")
    B:SetAura("debuff", "Moonfire", true)
    Equal(SelfSpot(debuff), "1 LEFT true RIGHT 4 0 1", "an entry back: past the end again")
    -- They show whatever you target: the debuffs on you, not another's
    -- debuff or a buff, and a target change never touches their container.
    target = false
    local refreshes = s.refreshes or 0
    Fire("PLAYER_TARGET_CHANGED")
    s.Update({ { id = 6788, harmful = true, mine = true }, { id = 11196, harmful = true, mine = true }, { id = 99, harmful = true },
        { id = 467 } })
    Equal(#group.active .. " " .. tostring(InSight(own)) .. " " .. ((s.refreshes or 0) - refreshes), "2 true 0",
        "no target: your two debuffs on you show, another's debuff and a buff don't, and the target change didn't touch them")
    target = true
    Fire("PLAYER_TARGET_CHANGED")
    Equal(#group.active .. " " .. ((s.refreshes or 0) - refreshes) .. " [" .. Runs() .. "]", "2 0 []",
        "an enemy targeted: still yours, still untouched, none of their code run inside the addon's")
    -- More than four of yours: four show, and the container makes no icon and
    -- runs none of the addon's code as it updates.
    local many = {}
    for i = 1, 7 do many[i] = { id = 90000 + i, harmful = true, mine = true } end
    s.Update(many)
    local bare = 0
    for _, button in ipairs(group.frames) do if not S[button].supplied.SetIcon then bare = bare + 1 end end
    Equal(#group.active .. " " .. s.late .. " " .. s.addonCalls .. " " .. bare, "4 0 0 0",
        "seven of yours: four show; no icon made and none of the addon's code run mid-update; every icon had its look as it was added")
    -- Missing debuffs greyed (fixed spots): off, as on the Buffs bar.
    B:SetOption("debuff", "showMissing", true)
    Equal(tostring(group.enabled), "false", "missing debuffs greyed: off, the spots belong to entries")
    B:SetOption("debuff", "showMissing", false)
    Equal(tostring(group.enabled), "true", "packed again: back on")
    -- Use my bars off: off with them; on: back.
    ns.Set("useBars", false)
    B:Rebuild()
    Equal(tostring(group.enabled) .. " " .. tostring(InSight(debuff)), "false false", "Use my bars off: off, the bar gone")
    ns.Set("useBars", true)
    B:Rebuild()
    Equal(tostring(group.enabled) .. " " .. tostring(InSight(debuff)), "true true", "on again: back")
    -- Both bars ticked: each shows them, each in its own container.
    B:SetOption("buff", "selfDebuffs", true)
    local buffGroup = S[B:Get("buff").container].groups.self
    Equal(tostring(buffGroup and buffGroup.enabled) .. " " .. tostring(group.enabled) .. " " .. #containers, "true true 3",
        "ticked on both bars: both show them, the Buffs bar in its own container, nothing more made")
    B:SetOption("buff", "selfDebuffs", false)
    -- Unticked: switched off, the container kept (as a group is); an empty
    -- bar goes right out again.
    B:SetOption("debuff", "selfDebuffs", false)
    Equal(tostring(group.enabled) .. " " .. tostring(debuff.selfContainer == own) .. " " .. #containers, "false true 3",
        "unticked: switched off, the container kept")
    B:SetAura("debuff", "Moonfire", false)
    Equal(tostring(InSight(debuff)) .. " " .. tostring(S[debuff].shown) .. " [" .. Runs() .. "]", "false true []",
        "unticked with no entries: the bar gone right out, still shown, none of the containers' code run")
    B:SetOption("debuff", "selfDebuffs", true)
    Equal(tostring(group.enabled) .. " " .. tostring(InSight(debuff)) .. " " .. #containers .. " " .. SelfSpot(debuff),
        "true true 3 1 CENTER true CENTER 0 0 1", "ticked again: the same container, back on, the empty bar back")
    Equal(#printed, 0, "no errors")
end

do
    -- Ticked in a fight: nothing is made or set up until it ends, as for the
    -- Buffs bar; unticked in one, it waits too.
    Fresh()
    local ns = Load({ useBars = true, notesSeen = "dev" })
    local B = ns.Bars
    B:SetAura("debuff", "Moonfire", true)
    local debuff = B:Get("debuff")
    local before = #containers
    Fire("PLAYER_REGEN_DISABLED")
    lockdown = true
    B:SetOption("debuff", "selfDebuffs", true)
    Equal(tostring(debuff.selfContainer) .. " " .. (#containers - before) .. " " .. containerCallsInCombat, "nil 0 0",
        "ticked in a fight: nothing made or set up")
    lockdown = false
    Fire("PLAYER_REGEN_ENABLED")
    local own = debuff.selfContainer
    Equal(tostring(own ~= nil) .. " " .. tostring(own and S[own].listening) .. " " .. tostring(SelfGroup(debuff).enabled) .. " ["
        .. Runs() .. "]", "true true true []", "made as it ends, in sight and hearing your auras, switched on")
    Fire("PLAYER_REGEN_DISABLED")
    lockdown = true
    B:SetOption("debuff", "selfDebuffs", false)
    Equal(tostring(SelfGroup(debuff).enabled) .. " " .. containerCallsInCombat, "true 0", "unticked in a fight: waits")
    lockdown = false
    Fire("PLAYER_REGEN_ENABLED")
    Equal(tostring(SelfGroup(debuff).enabled), "false", "and goes once it's over")
    Equal(#printed, 0, "no errors")
end

do
    -- Saved ticked: made at login with the bars, and the empty bar shows for
    -- them. With your bars off, nothing is made, as ever.
    Fresh()
    Load({ notesSeen = "dev", bars = { debuff = { selfDebuffs = true } } })
    Equal(#containers .. " [" .. Runs() .. "]", "0 []", "saved ticked with your bars off: still no container")
    Fresh()
    local ns = Load({ useBars = true, notesSeen = "dev", bars = { debuff = { selfDebuffs = true } } })
    local debuff = ns.Bars:Get("debuff")
    local own = debuff.selfContainer
    Equal(#containers .. " " .. tostring(own and S[own].unit) .. " " .. tostring(own and S[own].listening) .. " "
        .. tostring(SelfGroup(debuff).enabled) .. " " .. tostring(InSight(debuff)) .. " [" .. Runs() .. "]",
        "3 player true true true []", "saved ticked with your bars on: made at login, watching you, the empty Debuffs bar showing")
    Equal(#printed, 0, "no errors")
end

do
    -- The tick: on the Buffs and Debuffs pages, each bar its own. The
    -- Debuffs one, seen working in game 2026-10-08, has no label of its own
    -- now: both read alike. Typing Weakened Soul in either page's add box
    -- points to both ticks, still on one line, and one left on a bar points
    -- to the tick on its page, or to the Buffs one.
    Fresh()
    local ns = Load({ useBars = true, notesSeen = "dev", helpSeen = true })
    SlashCmdList.FECM("")
    local w = FECMFrame
    local tick = w.pages.bar.options.showSelf
    local function Note()
        local hint = tick.hint
        if type(hint) == "function" then hint = hint(tick) end
        return hint
    end
    local seen = {}
    for _, key in ipairs({ "cd", "util", "buff", "debuff" }) do
        w:Select(key)
        if tick:IsVisible() then seen[#seen + 1] = key end
    end
    Equal(table.concat(seen, " "), "buff debuff", "on the Buffs and Debuffs pages only")
    -- A bar's icon for one of those debuffs, left on it from before the add
    -- box turned them away: what its note says on each page.
    ns.Bars:Assign("Moonfire", "cd")
    w:Select("cd")
    local iconNote = w.pages.bar.icons[1].hint
    local function IconNote(key)
        w:Select(key)
        return iconNote({ name = "Recently Bandaged" })
    end
    local icons = {}
    for _, key in ipairs({ "buff", "debuff", "cd" }) do icons[#icons + 1] = IconNote(key) end
    local longestIcon = 0
    for _, note in ipairs(icons) do longestIcon = math.max(longestIcon, #note) end
    Equal(table.concat(icons, " | ") .. " " .. tostring(longestIcon <= 94), "Recently Bandaged can't show here. Tick \"Show your debuffs"
        .. " on you\" and drag it off the bar. | Recently Bandaged can't show here. Tick \"Show your debuffs on you\" and drag it off the"
        .. " bar. | Recently Bandaged can't show here. Drag it off, and tick \"Show your debuffs on you\" on Buffs. true",
        "one left on a bar: its note names this page's tick, or the Buffs one, on one line")
    w:Select("buff")
    local buffLabel, buffNote = S[tick.text].text, Note()
    w:Select("debuff")
    Equal(buffLabel .. " | " .. S[tick.text].text, "Show your debuffs on you | Show your debuffs on you",
        "both read alike, the Debuffs one no longer marked (seen working in game)")
    S[tick].width = 0
    w:Select("buff")
    w:Select("debuff")
    Equal(S[tick].width > 18, true, "its click area is sized to the words again")
    w:Select("buff")
    Equal(S[tick.text].text, "Show your debuffs on you", "back on Buffs: its own words")
    w:Select("debuff")
    Equal(buffNote, "Debuffs you put on yourself, like Weakened Soul from your shield or Recently Bandaged, after your buffs."
        .. " Not with missing buffs greyed or Only show missing.", "the Buffs one's note: not with either")
    Equal(Note(), "Debuffs you put on yourself, like Weakened Soul from your shield or Recently Bandaged, at the end of this bar."
        .. " Not with missing debuffs greyed.", "the Debuffs one's: where they go")
    Equal(tostring(tick:GetChecked()), "false", "unticked at first")
    tick:Click()
    w:Select("buff")
    local buffTicked = tick:GetChecked()
    w:Select("debuff")
    Equal(tostring(ns.BarData("debuff").selfDebuffs) .. " " .. tostring(ns.BarData("buff").selfDebuffs) .. " " .. tostring(buffTicked)
        .. " " .. tostring(tick:GetChecked()) .. " " .. tostring(SelfGroup(ns.Bars:Get("debuff")).enabled), "true false false true true",
        "ticked on the Debuffs page: that bar's alone, and it shows them")
    local note = ns.Spells:SelfDebuffNote("Weakened Soul")
    local longest = ns.Spells:SelfDebuffNote("Recently Bandaged")
    Equal(tostring(note:find("Tick \"Show your debuffs on you\" on Buffs or Debuffs.", 1, true) ~= nil) .. " " .. tostring(#longest <= 100),
        "true true", "Weakened Soul typed: pointed to the tick on either bar, the longest still one line (94 letters fit in game)")
    w:Hide()
    Equal(#printed, 0, "no errors")
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

-- Two spells of one name: GitHub issue 1 ------------------------------------------------------------
-- The Skyborne's Read Leyline gives two buffs both called Energized: 1270842
-- (15 seconds) and 1259691 (15 minutes). With 1259691 on the Buffs bar, the
-- page's search found no 1270842 ("No matches"), and adding it by ID only
-- gave the first entry a second ID: one icon lit by either. Now it goes on
-- pinned to its own ID ("Energized#1270842", Spells.lua S:Pin): an entry of
-- its own, with its own icon, place, joins and removal, each container group
-- or slot watching only its own entry's IDs, told out of combat only. The
-- Cooldowns and Utility bars go by name, as before. (In a function of its
-- own: this file's main chunk has little room for more locals.)

;(function()
    Fresh()
    local ns = Load({ useBars = true, notesSeen = "dev", helpSeen = true })
    local B, Sp = ns.Bars, ns.Spells
    local NAMES = { [1259691] = "Energized", [1270842] = "Energized", [1259705] = "Read Leyline" }
    local function Named()
        local game = C_Spell.GetSpellName
        C_Spell.GetSpellName = function(id) return NAMES[id] or game(id) end
    end
    Named()
    SlashCmdList.FECM("")
    local w = FECMFrame
    local page = w.pages.bar
    local db = ForeverEnhancedCooldownManagerDB
    local function Search(text)
        page.search:SetText(text)
        S[page.search].scripts.OnTextChanged(page.search, true)
    end
    -- The list's Energized rows, each with its muted text, and ticked,
    -- unticked or offered under Other spells; or the first heading when
    -- there are none.
    local function Rows()
        local out, heading = {}, nil
        for _, row in ipairs(page.rows) do
            if S[row].shown and S[row.check].shown and (S[row.name].text or ""):find("Energized", 1, true) then
                local muted = S[row.rank].text or ""
                out[#out + 1] = S[row.name].text .. (muted ~= "" and (" [" .. muted .. "]") or "") .. " "
                    .. (row.other and "offered" or row.check:GetChecked() and "ticked" or "unticked")
            elseif S[row].shown and not S[row.check].shown then
                heading = heading or S[row.header].text
            end
        end
        return #out > 0 and table.concat(out, " | ") or tostring(heading)
    end
    local function Other(lookup)
        for _, row in ipairs(page.rows) do
            if S[row].shown and row.other == lookup then return row end
        end
    end
    local function Note(frame)
        local hint = frame.hint
        if type(hint) == "function" then hint = hint(frame) end
        return hint
    end
    local function List(key) return table.concat(ns.BarData(key).spells, ",") end
    -- Spells remembered by name (db.custom): "Name=ids", in order.
    local function Custom()
        local out = {}
        for name, ids in pairs(db.custom or {}) do out[#out + 1] = name .. "=" .. table.concat(ids, ",") end
        table.sort(out)
        return table.concat(out, " ")
    end
    local function IDs(set)
        local list = {}
        for id in pairs(set or {}) do list[#list + 1] = id end
        table.sort(list)
        return table.concat(list, ",")
    end
    -- What each of a bar's container groups (packed) and slots (missing ones
    -- greyed) that's switched on watches, in order.
    local function Watched(key)
        local bar = B:Get(key)
        local s, out = S[bar.container], {}
        for i = 1, bar.groups do
            local group = s.groups["g" .. i]
            if group.enabled then out[#out + 1] = "g" .. i .. " " .. IDs(group.filters and group.filters.includeSpellIDs) end
        end
        for i = 1, ns.BUFF_SLOTS do
            local slot = s.slots["b" .. i]
            if slot.enabled then out[#out + 1] = "b" .. i .. " " .. IDs(slot.filters and slot.filters.includeSpellIDs) end
        end
        return table.concat(out, " | ")
    end
    -- The groups that light for these auras.
    local function Lit(key, auras)
        local bar = B:Get(key)
        local s, out = S[bar.container], {}
        s.Update(auras)
        for i = 1, bar.groups do
            if #s.groups["g" .. i].active > 0 then out[#out + 1] = "g" .. i end
        end
        return table.concat(out, " ")
    end
    local ENERGIZED, LONG = { id = 1259691 }, { id = 1270842 }

    -- The key: a spell's name and its ID, and nothing else reads as one.
    local name, id = Sp:Pinned("Energized#1270842")
    local refused = {}
    for _, key in ipairs({ "Energized", "Moonfire@2", "Energized#0", "Energized#01", "Energized#2147483648", "Energized#12a",
        "#1270842", "Ener@gized#1270842", "Ener#gized#1270842", "item:118", "family:healing" }) do
        if Sp:Pinned(key) then refused[#refused + 1] = key end
    end
    Equal(tostring(name) .. " " .. tostring(id) .. " | " .. table.concat(refused, " "), "Energized 1270842 | ",
        "a pinned key is a spell's name, # and its ID; a plain name, a fixed rank, an item or a bad ID isn't one")

    w:Select("buff")
    Search("1259691")
    local first = Rows()
    Search("1270842")
    Equal(first .. " | " .. Rows(), "Energized (ID 1259691) offered | Energized (ID 1270842) offered",
        "neither tracked: the Buffs page's search finds each by its ID")
    Search("1259691")
    Other("1259691").check:Click()
    Equal(S[w.note].text .. " " .. List("buff") .. " " .. Custom(), "Added Energized to Buffs. Energized Energized=1259691",
        "1259691 added: kept by name, remembered by its ID, as before")
    Search("1270842")
    local row = Other("1270842")
    Equal(Rows() .. " | " .. tostring(row and Note(row.check)), "Energized (ID 1270842) offered | Add Energized (ID 1270842) to Buffs"
        .. " as its own icon, for this spell ID only.", "then 1270842 is still found (it said No matches), and says what ticking it does")
    row.check:Click()
    Equal(S[w.note].text .. " " .. List("buff") .. " " .. Custom(),
        "Added Energized (ID 1270842) to Buffs. Energized,Energized#1270842 Energized=1259691",
        "added as an entry of its own, pinned to its ID; the first keeps its own ID, and nothing more is remembered")
    Equal(Rows(), "Energized (ID 1270842) ticked", "searched again: listed and ticked, not offered again")
    Search("1259691")
    Equal(Rows(), "Energized (ID 1259691) ticked", "the first, by its ID: ticked, its ID in brackets like the second's")
    Search("")
    Equal(Rows(), "Energized (ID 1259691) ticked | Energized (ID 1270842) ticked", "the whole list: both, each ticked, told apart alike")
    local bar = B:Get("buff")
    Equal(bar.count .. " | " .. Watched("buff"), "2 | g1 1259691 | g2 1270842", "two icons on the bar, each group watching its own ID")
    Equal(Lit("buff", { ENERGIZED }) .. " | " .. Lit("buff", { LONG }) .. " | " .. Lit("buff", { ENERGIZED, LONG }) .. " | "
        .. Lit("buff", { { id = 1259705 } }), "g1 | g2 | g1 g2 | ", "each lights for its own buff only, both for both, neither for the racial")
    Equal(page.icons[1].name .. " | " .. page.icons[2].name .. " | " .. Note(page.icons[2]), "Energized (ID 1259691) | Energized (ID 1270842) | Energized"
        .. " (ID 1270842). Drag it onto another icon to swap them, or off the bar to take it off.", "the page's tray names them apart, alike")
    -- Typed or dropped again, each is there already, as before.
    local said = {}
    for _, text in ipairs({ "1270842", "1259691" }) do
        local ok, message = B:Add("buff", text)
        said[#said + 1] = tostring(ok) .. " " .. message
    end
    local _, held = B:CanAdd("buff", "1270842")
    Equal(table.concat(said, " | ") .. " | " .. held .. " | " .. List("buff"), "true Energized (ID 1270842) is already on Buffs. | true"
        .. " Energized is already on Buffs. | Energized (ID 1270842) is already on Buffs. | Energized,Energized#1270842",
        "added again, each says it's on the bar already, and nothing changes")
    -- The Cooldowns bar goes by name, as before: an ID not pinned yet is
    -- taken in by the name's own entry there, and nothing new is pinned.
    NAMES[1300004] = "Energized"
    local _, cooldowns = B:CanAdd("cd", "1300004")
    Equal(cooldowns .. " " .. tostring(Sp:Pin(1300004, "cd")) .. " " .. tostring(Sp:Pin(1300004, "util")),
        "Drop to add Energized to Cooldowns. nil nil", "on the Cooldowns and Utility bars nothing new is pinned")
    -- But an ID pinned already goes there as that entry: given to the
    -- name's entry instead, it would light the first icon on Buffs for the
    -- second buff too.
    local _, pinnedThere = B:CanAdd("cd", "1270842")
    local added, addedNote = B:Add("cd", "1270842")
    Equal(pinnedThere .. " | " .. tostring(added) .. " " .. addedNote .. " | " .. List("cd") .. " | " .. Custom() .. " | "
        .. Watched("buff"), "Drop to add Energized (ID 1270842) to Cooldowns. | true Added Energized (ID 1270842) to Cooldowns."
        .. " | Energized#1270842 | Energized=1259691 | g1 1259691 | g2 1270842",
        "an ID pinned on Buffs, typed on Cooldowns: its pinned entry goes there, the first still watching its own ID only")
    B:Assign("Energized#1270842", nil)
    -- A name too long to share with an ID after it (a shared key is 64
    -- letters at most) goes by name, as before.
    local long = ("Long Spell Name "):rep(4):sub(1, 60)
    NAMES[1300001], NAMES[1300002] = long, long
    ns.AddCustom(long, { 1300001 })
    B:SetAura("buff", long, true)
    local _, longNote = B:CanAdd("buff", "1300002")
    Equal(tostring(Sp:Pin(1300002, "buff")) .. " " .. longNote, "nil Drop to add " .. long .. " to Buffs.",
        "a 60-letter name: not pinned, it joins its name's entry")
    B:SetAura("buff", long, false)
    -- Another spell of a spellbook spell's name: pinned, watching its own ID
    -- only, not the ranks the spellbook's entry watches.
    NAMES[1300003] = "Thorns"
    B:SetAura("buff", "Thorns", true)
    B:Add("buff", "1300003")
    Equal(List("buff") .. " | " .. Watched("buff"), "Energized,Energized#1270842,Thorns,Thorns#1300003 | g1 1259691 | g2 1270842"
        .. " | g3 467,782,1075,8914,9756,9910 | g4 1300003", "beside a spellbook spell: its own ID only, not the spell's ranks")
    B:SetAura("buff", "Thorns#1300003", false)
    B:SetAura("buff", "Thorns", false)
    -- Judged by its spell's own name, as any entry: a racial's buff pinned
    -- by its ID (the tauren's Plainsrunning) shows for that race only.
    B:SetAura("buff", "Plainsrunning#1299038", true)
    local skyborne = tostring(Sp:ForMe("Plainsrunning#1299038", "buff"))
    local race = _G.UnitRace
    _G.UnitRace = function() return "Tauren", "Tauren", 6 end
    B:Changed()
    Equal(skyborne .. " " .. tostring(Sp:ForMe("Plainsrunning#1299038", "buff")) .. " " .. table.concat((B:Mine("buff")), ","),
        "false true Energized,Energized#1270842,Plainsrunning#1299038", "a racial's buff pinned by ID: a tauren's, not a Skyborne's")
    _G.UnitRace = race
    B:SetAura("buff", "Plainsrunning#1299038", false)

    -- Each its own place, joins and look.
    B:MoveTo("buff", 2, 1)
    Equal(List("buff") .. " | " .. Watched("buff"), "Energized#1270842,Energized | g1 1270842 | g2 1259691", "moved: the groups follow")
    B:MoveTo("buff", 2, 1)
    B:SetJoined("buff", 2, true)
    Equal(bar.count .. " | " .. Watched("buff") .. " | " .. Lit("buff", { LONG }), "1 | g1 1259691,1270842 | g1",
        "joined: one icon, lit by either")
    B:SetJoined("buff", 2, false)
    B:SetOption("buff", "showMissing", true)
    B:SetOption("buff", "showNames", true)
    Equal(Watched("buff") .. " | " .. S[bar.holders[1].label].text .. " | " .. S[bar.holders[2].label].text,
        "b1 1259691 | b2 1270842 | Energized | Energized (ID 1270842)", "missing ones greyed: a slot each, each named")
    B:SetOption("buff", "showNames", false)
    B:SetOption("buff", "showMissing", false)
    Equal(Watched("buff"), "g1 1259691 | g2 1270842", "packed again")

    -- Taken off in a fight: the containers are told once it's over, the
    -- other entry still there, still remembered.
    Runs()
    Fire("PLAYER_REGEN_DISABLED")
    lockdown = true
    local ok, message = B:TakeOff("buff", "Energized#1270842")
    Equal(tostring(ok) .. " " .. message .. " " .. List("buff") .. " | " .. Watched("buff") .. " | " .. containerCallsInCombat,
        "true Took Energized (ID 1270842) off Buffs. Energized | g1 1259691 | g2 1270842 | 0",
        "taken off in a fight: off the list, nothing told to the containers yet")
    lockdown = false
    Fire("PLAYER_REGEN_ENABLED")
    Equal(Watched("buff") .. " | " .. Custom() .. " | " .. Lit("buff", { LONG }) .. " | [" .. Runs() .. "]",
        "g1 1259691 | Energized=1259691 |  | []", "after it: the other watches its own ID still, and nothing lights for the long one")
    B:Add("buff", "1270842")
    B:Remove("buff", 1)
    Equal(List("buff") .. " | " .. Custom() .. " | " .. Watched("buff") .. " | " .. Lit("buff", { ENERGIZED }) .. " | "
        .. Lit("buff", { LONG }), "Energized#1270842 |  | g1 1270842 |  | g1",
        "the first taken off: the pinned one stays, watching its own ID; the first's ID let go")
    Search("1270842")
    first = Rows()
    Search("1259691")
    Equal(first .. " | " .. Rows(), "Energized (ID 1270842) ticked | Energized (ID 1259691) offered",
        "the pinned one ticked by its ID; the other offered again")
    Other("1259691").check:Click()
    Equal(List("buff") .. " | " .. Custom() .. " | " .. Watched("buff"), "Energized#1270842,Energized | Energized=1259691 | g1 1270842"
        .. " | g2 1259691", "and goes back on by name, as the first did")

    Equal(#printed .. " " .. containerCallsInCombat, "0 0", "no errors, no container told anything in a fight")

    -- Kept over a reload, and on the Debuffs bar the same way.
    local saved = db
    Fresh()
    ns = Load(saved)
    B, Sp, db = ns.Bars, ns.Spells, ForeverEnhancedCooldownManagerDB
    Named()
    Equal(List("buff") .. " | " .. B:Get("buff").count .. " | " .. Watched("buff"), "Energized#1270842,Energized | 2 | g1 1270842"
        .. " | g2 1259691", "after a reload: both, each watching its own ID")
    ok, message = B:Add("debuff", "1270842")
    local group = S[B:Get("debuff").container].groups.g1
    Equal(tostring(ok) .. " " .. message .. " " .. List("debuff") .. " | " .. Watched("debuff") .. " | "
        .. tostring(group.filters.isFromPlayerOrPlayerPet), "true Added Energized (ID 1270842) to Debuffs. Energized#1270842 | g1 1270842"
        .. " | true", "on the Debuffs bar: the pinned one goes on as itself, only yours")
    B:Add("debuff", "1259691")
    Equal(List("debuff") .. " | " .. Watched("debuff") .. " | " .. Custom(), "Energized#1270842,Energized | g1 1270842 | g2 1259691"
        .. " | Energized=1259691", "and the first beside it, by name")
    Equal(#printed .. " " .. containerCallsInCombat, "0 0", "no errors, no container told anything in a fight")

    -- Saved by 1.5.6: an entry kept by name watches the IDs it was given,
    -- as it did. One given both IDs keeps one icon for both.
    Fresh()
    ns = Load({ useBars = true, notesSeen = "dev", everyone = "Old", custom = { Energized = { 1259691 }, Thorns = { 467 } },
        profiles = { Old = { cd = {}, util = {}, buff = { "Energized", "Thorns" }, debuff = {}, joins = { buff = { Thorns = true } } } } })
    B, Sp, db = ns.Bars, ns.Spells, ForeverEnhancedCooldownManagerDB
    Named()
    Equal(List("buff") .. " | " .. Watched("buff"), "Energized,Thorns | g1 467,782,1075,8914,9756,9910,1259691",
        "1.5.6's saved Energized: by name, watching its ID, joined as it was")
    ok, message = B:Add("buff", "1270842")
    Equal(message .. " " .. List("buff") .. " | " .. Custom(), "Added Energized (ID 1270842) to Buffs. Energized,Thorns,Energized#1270842"
        .. " | Energized=1259691 Thorns=467", "the second goes on pinned, beside it")
    Fresh()
    ns = Load({ useBars = true, notesSeen = "dev", everyone = "Old", custom = { Energized = { 1259691, 1270842 } },
        profiles = { Old = { cd = {}, util = {}, buff = { "Energized" }, debuff = {}, joins = {} } } })
    B, Sp, db = ns.Bars, ns.Spells, ForeverEnhancedCooldownManagerDB
    Named()
    ok, message = B:Add("buff", "1270842")
    Equal(Watched("buff") .. " | " .. message .. " " .. List("buff"), "g1 1259691,1270842 | Energized is already on Buffs. Energized",
        "one given both IDs before: one icon for both, as it was, and 1270842 is on the bar already")

    -- Spells added by ID are remembered for every profile. With both on the
    -- first profile's Buffs bar, another profile (another character) adding
    -- the 15-second one first gets it pinned too: by name it would have
    -- made the first profile's Energized watch the 15-second buff instead,
    -- two icons for one buff and none for the other.
    Fresh()
    ns = Load({ useBars = true, notesSeen = "dev", helpSeen = true })
    B, Sp, db = ns.Bars, ns.Spells, ForeverEnhancedCooldownManagerDB
    Named()
    B:Add("buff", "1259691")
    B:Add("buff", "1270842")
    local firstProfile = ns.ProfileName()
    ns.NewProfile("Second")
    SlashCmdList.FECM("")
    w = FECMFrame
    page = w.pages.bar
    w:Select("buff")
    Search("1270842")
    row = Other("1270842")
    Equal(Rows() .. " | " .. tostring(row and Note(row.check)), "Energized (ID 1270842) offered | Add Energized (ID 1270842) to Buffs"
        .. " as its own icon, for this spell ID only.", "another profile: the 15-second one offered pinned, the first's Energized remembered")
    row.check:Click()
    Equal(List("buff") .. " | " .. Custom() .. " | " .. Watched("buff"), "Energized#1270842 | Energized=1259691 | g1 1270842",
        "added there pinned; what the first's Energized watches is kept")
    ok, message = B:Add("buff", "1259691")
    Equal(message .. " " .. List("buff") .. " | " .. Custom() .. " | " .. Watched("buff"), "Added Energized to Buffs."
        .. " Energized#1270842,Energized | Energized=1259691 | g1 1270842 | g2 1259691", "then the 15-minute one there by name, as the first has it")
    ns.UseProfile(firstProfile)
    Equal(List("buff") .. " | " .. Watched("buff"), "Energized,Energized#1270842 | g1 1259691 | g2 1270842",
        "back on the first profile: each icon still watching its own ID")
    Equal(#printed, 0, "no errors")
end)()

-- Spells whose aura has another ID -----------------------------------------------------------------
-- Some spells put no aura on anyone themselves, or not the one a bar would
-- show: a rogue's poison is made by one spell and put on the target by
-- another of its name (Deadly Poison 2835 makes it, 2818 is the debuff),
-- Bloodrage's rage buff is 29131, a totem's buff on everyone near it is
-- its own spell, and the Skyborne's Read Leyline and Skysight set off
-- Energized and Elemental Blessing. The game data links each spell to those
-- auras (Ranks.lua ns.SPELL_AURAS, and by the aura's name ns.NAME_AURAS),
-- so its entry lights for them on the Buffs and Debuffs bars and in the
-- Cooldowns bar's buff and debuff times. The ranks of one aura are one
-- icon (ns.AURA_FAMILIES: a totem's buff, a talent's aura, Well Fed from
-- any food), as in 1.5.6, while two spells of one name (the two Energized)
-- still go on one each. A hunter's pet abilities are the pet's own spells,
-- and the trap debuffs build 70291 renamed keep every rank. (In a function
-- of its own: this file's main chunk has little room for more locals.)
;(function()
    local data = {}
    assert(loadfile("Ranks.lua"))("ForeverEnhancedCooldownManager", data)
    local function Has(list, ...)
        local set = {}
        for _, id in ipairs(list or {}) do set[id] = true end
        for _, id in ipairs({ ... }) do
            if not set[id] then return false end
        end
        return true
    end
    local function Joined(list) return list and table.concat(list, ",") or "none" end
    local function FamilyOf(id)
        for _, ids in ipairs(data.AURA_FAMILIES) do
            if Has(ids, id) then return ids end
        end
        return nil
    end
    -- From the game data (build 70425).
    local links = data.SPELL_AURAS
    Equal(Joined(links[2835]) .. " | " .. Joined(links[13220]) .. " | " .. Joined(links[3421]) .. " | " .. Joined(links[2687]) .. " | "
        .. Joined(links[1856]) .. " | " .. Joined(links[1238122]) .. " | " .. Joined(links[5246]) .. " | " .. Joined(links[11129]),
        "2818,434312 | 13218,13222,13223,13224 | 3409,11201,25809 | 29131 | 11327,11329 | 19675 | 20511 | 28682",
        "a poison's maker leads to its debuff (every rank's, for a name the later ranks share), Bloodrage to its rage buff,"
        .. " Vanish to its stealth, Feral Charge to its root, Intimidating Shout to its stun, Combustion to its stacks")
    Equal(Joined(links[1259705]) .. " | " .. Joined(links[1259686]) .. " | " .. Joined(links[8512]) .. " | " .. Joined(links[8227])
        .. " | " .. Joined(links[400574]) .. " | " .. Joined(links[1240827]) .. " | " .. Joined(links[1499]) .. " | " .. Joined(links[13809]),
        "1259691,1270842 | 1259688,1270893 | 8515,10609,10612 | 8230,8250,10521,15036 | 400573 | 401877,1240848,1240849"
        .. " | 3355,14308,14309 | 13810", "Read Leyline to both Energized, Skysight to both Elemental Blessing, a totem to its"
        .. " buff (not Windfury's moment's extra attack, 8516), Arcane Blast to its stacks, Prayer of Mending to every rank's buff,"
        .. " the traps to theirs")
    Equal(Joined(FamilyOf(8076)) .. " | " .. Joined(FamilyOf(24118)) .. " | " .. tostring(Has(FamilyOf(1248406), 1248420, 19709))
        .. " | " .. tostring(FamilyOf(1259691)) .. " " .. tostring(FamilyOf(1270842)) .. " " .. tostring(FamilyOf(1259688)),
        "8076,8162,8163,10441,25362 | 24118,24119,24120,1299332 | true | nil nil nil",
        "one aura in several IDs: a totem buff's ranks, a bleed no class lists, Well Fed from any food; never the two Energized"
        .. " or the two Elemental Blessing")
    -- A talent ability's ranks are its own name's in ns.RANKS now (2026-10-20),
    -- every rank its buff had as a family before.
    Equal(tostring(FamilyOf(19506)) .. " " .. Joined(data.RANKS["Trueshot Aura"]) .. " | " .. tostring(FamilyOf(1310687)) .. " "
        .. Joined(data.RANKS["Sniper Shot"]) .. " | " .. tostring(FamilyOf(20925)) .. " " .. Joined(data.RANKS["Holy Shield"]),
        "nil 1299346,1299348,19506,20905,20906 | nil 1310687,1310785,1310786 | nil 20925,20927,20928",
        "a talent aura's ranks all in ns.RANKS (Trueshot Aura, Sniper Shot's three, Holy Shield), no family needed")
    Equal(Joined(FamilyOf(8182)) .. " | " .. Joined(FamilyOf(8185)) .. " | " .. Joined(FamilyOf(10596)),
        "8182,10476,10477 | 8185,10534,10535 | 10596,10598,10599",
        "a totem's Frost, Fire and Nature Resistance too, though a hunter's pet's passives hold those names")
    local only = data.AURA_ONLY
    Equal(tostring(only[1259691] and only[1270842] and only[1248406] and only[18118]) .. " | " .. tostring(only[1264482]) .. " "
        .. tostring(only[20925]) .. " " .. tostring(only[17767]) .. " " .. tostring(only[1310786]), "true | nil nil nil nil",
        "auras no one learns: Energized, Well Fed, Aftermath's debuff; not a bat's Sonic Blast, nor the talents Holy Shield and"
        .. " Sniper Shot, nor a voidwalker's Consume Shadows")
    Equal(Joined(data.RANKS.Bite) .. " | " .. Joined(data.RANKS["Furious Howl"]) .. " | " .. tostring(data.SPELL_CLASSES.Bite) .. " "
        .. tostring(data.SPELL_CLASSES.Dash) .. " | " .. tostring(data.COOLDOWNS[17261]) .. " " .. tostring(data.COOLDOWNS[17268]),
        "17253,17255,17256,17257,17258,17259,17260,17261 | 24604,24605,24603,24597 | HUNTER DRUID HUNTER | 10 nil",
        "a pet ability's ranks are the pet's own spells (not the hunter's Beast Training ones), still a hunter's, with their cooldown")
    Equal(tostring(data.RANKS["Immolation Trap Effect"]) .. " | " .. Joined(data.RANKS["Immolation Trap"]),
        "nil | 13795,13797,14298,14302,14299,14303,14300,14304,14301,14305",
        "build 70291 renamed Immolation Trap Effect: its burns are Immolation Trap's now")

    local NAMES = { [2818] = "Deadly Poison", [13218] = "Wound Poison", [13224] = "Wound Poison", [29131] = "Bloodrage",
        [1259691] = "Energized", [1270842] = "Energized", [1259688] = "Elemental Blessing", [1270893] = "Elemental Blessing",
        [8076] = "Strength of Earth", [8162] = "Strength of Earth", [25362] = "Strength of Earth", [19506] = "Trueshot Aura",
        [20906] = "Trueshot Aura", [1248406] = "Well Fed", [1248420] = "Well Fed", [19709] = "Well Fed",
        [401877] = "Prayer of Mending", [1240849] = "Prayer of Mending", [3355] = "Freezing Trap", [14309] = "Freezing Trap",
        [8182] = "Frost Resistance", [10477] = "Frost Resistance" }
    for name, ids in pairs(data.RANKS) do
        for _, id in ipairs(ids) do NAMES[id] = NAMES[id] or name end
    end
    local ns, B, Sp, db
    local petKnows = {}
    local function Start(class, saved, racials)
        Fresh()
        for _, item in ipairs(racials or {}) do table.insert(book[1].items, item) end
        local game = C_Spell.GetSpellName
        C_Spell.GetSpellName = function(id) return NAMES[id] or game(id) end
        _G.UnitClass = function() return class, class end
        -- What your pet knows, in the pet's spellbook.
        _G.Enum.SpellBookSpellBank.Pet = 1
        C_SpellBook.IsSpellKnown = function(id, bank) return bank == 1 and petKnows[id] == true end
        ns = Load(saved or { useBars = true, notesSeen = "dev", helpSeen = true })
        B, Sp, db = ns.Bars, ns.Spells, ForeverEnhancedCooldownManagerDB
    end
    local function List(key) return table.concat(ns.BarData(key).spells, ",") end
    local function Custom(name) return Joined(db.custom and db.custom[name]) end
    local function IDs(set)
        local list = {}
        for id in pairs(set or {}) do list[#list + 1] = id end
        table.sort(list)
        return table.concat(list, ",")
    end
    -- What each of a bar's container groups that's switched on watches.
    local function Watched(key)
        local bar = B:Get(key)
        local s, out = S[bar.container], {}
        for i = 1, bar.groups do
            local group = s.groups["g" .. i]
            if group.enabled then out[#out + 1] = "g" .. i .. " " .. IDs(group.filters and group.filters.includeSpellIDs) end
        end
        return table.concat(out, " | ")
    end
    -- The groups that light for these auras, by ID: buffs on you, or your
    -- debuffs on the target.
    local function Lit(key, ...)
        local bar = B:Get(key)
        local s, auras, out = S[bar.container], {}, {}
        for _, id in ipairs({ ... }) do auras[#auras + 1] = { id = id, harmful = key == "debuff", mine = key == "debuff" } end
        s.Update(auras)
        for i = 1, bar.groups do
            if #s.groups["g" .. i].active > 0 then out[#out + 1] = "g" .. i end
        end
        return table.concat(out, " ")
    end
    local function Said(key, text)
        local ok, message = B:Add(key, text)
        return tostring(ok) .. " " .. message
    end

    -- A rogue's poisons, added by name on the Debuffs bar (the page's search
    -- offers them): each lights for its debuff on the target. Wound Poison's
    -- later ranks are spells of other names (Wound Poison II...), but their
    -- debuffs are all called Wound Poison: by name, it lights for every one.
    Start("ROGUE", nil, { { name = "Vanish", subName = "Rank 1", spellID = 1856, iconID = 1 },
        { name = "Vanish", subName = "Rank 2", spellID = 1857, iconID = 1 } })
    Equal(Said("debuff", "Deadly Poison") .. " | " .. Custom("Deadly Poison") .. " | " .. Watched("debuff"),
        "true Added Deadly Poison to Debuffs. | 2835 | g1 2818,2835,434312", "Deadly Poison by name: it watches its debuff too")
    Equal(Lit("debuff", 2818) .. " | " .. tostring(Sp:Pin(2818, "debuff")) .. " " .. Said("debuff", "2818") .. " | " .. List("debuff")
        .. " | " .. Watched("debuff"), "g1 | nil true Added Deadly Poison to Debuffs. | Deadly Poison | g1 2818,2835,434312",
        "your Deadly Poison on the target lights it; its ID typed after goes in with it, not on an icon of its own")
    Said("debuff", "Wound Poison")
    Equal(Custom("Wound Poison") .. " | " .. Watched("debuff") .. " | " .. Lit("debuff", 13224) .. " | " .. Lit("debuff", 13218),
        "13220 | g1 2818,2835,434312 | g2 13218,13220,13222,13223,13224 | g2 | g2", "Wound Poison by name lights for rank 4's debuff, and rank 1's")
    -- Vanish's stealth is its own spell too: its buff time on the Cooldowns
    -- bar watches it, for Vanish and for Vanish fixed at rank 1.
    B:Assign("Vanish", "cd")
    B:Assign("Vanish@1", "cd")
    B:SetOption("cd", "showAuras", true)
    local slots = S[B:Get("cd").auraContainers.p].slots
    Equal(IDs(slots.p1.filters.includeSpellIDs) .. " | " .. IDs(slots.p2.filters.includeSpellIDs), "1856,1857,11327,11329 | 1856,11327,11329",
        "Vanish's buff time watches its stealth, at either rank")
    Equal(#printed, 0, "no errors")

    -- A warrior's Bloodrage on the Buffs bar, and its buff time over its icon
    -- on the Cooldowns bar.
    Start("WARRIOR")
    Said("buff", "Bloodrage")
    Equal(Watched("buff") .. " | " .. Lit("buff", 29131) .. " | " .. tostring(Sp:Pin(29131, "buff")) .. " " .. List("buff"),
        "g1 2687,29131 | g1 | nil Bloodrage", "Bloodrage lights for its rage buff, and that buff's ID isn't pinned beside it")
    B:Assign("Bloodrage", "cd")
    B:SetOption("cd", "showAuras", true)
    local made = B:Get("cd").auraContainers
    local p1 = made and S[made.p].slots.p1
    Equal(tostring(p1 and p1.enabled) .. " " .. IDs(p1 and p1.filters.includeSpellIDs), "true 2687,29131",
        "on the Cooldowns bar its buff time watches the rage buff too")
    Equal(#printed, 0, "no errors")

    -- Ranks of one aura join one icon, as in 1.5.6: a totem's buff and a
    -- talent's aura added by one rank's ID light for every rank, and the
    -- next rank's ID goes in with it. Well Fed from any food the same. The
    -- two Energized are two spells: the second still goes on as its own.
    Start("WARRIOR")
    Equal(Said("buff", "8076") .. " | " .. Custom("Strength of Earth") .. " | " .. Watched("buff") .. " | "
        .. Lit("buff", 25362), "true Added Strength of Earth to Buffs. | 8076 | g1 8076,8162,8163,10441,25362 | g1",
        "Strength of Earth by its first rank: lit by every rank")
    Equal(tostring(Sp:Pin(25362, "buff")) .. " | " .. Said("buff", "25362") .. " | " .. List("buff") .. " | " .. Custom("Strength of Earth")
        .. " | " .. B:Get("buff").count, "nil | true Added Strength of Earth to Buffs. | Strength of Earth | 8076,25362 | 1",
        "rank 5 by its ID: not pinned, it joins the one icon")
    Said("buff", "19506")
    Equal(tostring(Sp:Pin(20906, "buff")) .. " | " .. Said("buff", "20906") .. " | " .. List("buff") .. " | " .. Lit("buff", 1299346),
        "nil | true Added Trueshot Aura to Buffs. | Strength of Earth,Trueshot Aura | g2", "Trueshot Aura's ranks the same")
    Said("buff", "1248406")
    Equal(tostring(Sp:Pin(1248420, "buff")) .. " | " .. Said("buff", "1248420") .. " | " .. List("buff") .. " | "
        .. Lit("buff", 19709), "nil | true Added Well Fed to Buffs. | Strength of Earth,Trueshot Aura,Well Fed | g3",
        "Well Fed from another food joins the one icon, lit by any food's")
    Said("buff", "1259691")
    Equal(Said("buff", "1270842") .. " | " .. List("buff") .. " | " .. Sp:Find("Energized#1270842").name,
        "true Added Energized (ID 1270842) to Buffs. | Strength of Earth,Trueshot Aura,Well Fed,Energized,Energized#1270842"
        .. " | Energized (ID 1270842)", "the second Energized still goes on as its own icon, named by its ID")
    Equal(#printed, 0, "no errors")

    -- The totem's Frost Resistance shares its name with a hunter's pet's
    -- passive, which is what the data's ranks hold under it: its own ranks
    -- still join one icon.
    Start("WARRIOR")
    Equal(Said("buff", "8182") .. " | " .. tostring(Sp:Pin(10477, "buff")) .. " | " .. Said("buff", "10477") .. " | " .. List("buff")
        .. " | " .. Custom("Frost Resistance") .. " | " .. Lit("buff", 10477) .. " | " .. B:Get("buff").count,
        "true Added Frost Resistance to Buffs. | nil | true Added Frost Resistance to Buffs. | Frost Resistance | 8182,10477 | g1 | 1",
        "Frost Resistance by rank 1's ID, then rank 3's: one icon, lit by either")
    Equal(#printed, 0, "no errors")

    -- Prayer of Mending by name, whoever casts it on you: its casts put no
    -- aura on anyone, and later ranks name only the first rank's buff.
    Start("WARRIOR")
    Said("buff", "Prayer of Mending")
    Equal(Lit("buff", 401877) .. " | " .. Lit("buff", 1240849), "g1 | g1", "lit by the first rank's buff, and the third's")

    -- The Skyborne's racials in the spellbook, on the Buffs bar: each lights
    -- for both buffs it gives, and the two Energized still go on one each.
    Start("DRUID", nil, { { name = "Read Leyline", subName = "Racial", spellID = 1259705, iconID = 1 },
        { name = "Skysight", subName = "Racial", spellID = 1259686, iconID = 1 } })
    B:SetAura("buff", "Read Leyline", true)
    B:SetAura("buff", "Skysight", true)
    Equal(Watched("buff") .. " | " .. Lit("buff", 1270842) .. " | " .. Lit("buff", 1259691) .. " | " .. Lit("buff", 1259688) .. " | "
        .. Lit("buff", 1270893), "g1 1259691,1259705,1270842 | g2 1259686,1259688,1270893 | g1 | g1 | g2 | g2",
        "Read Leyline lights for either Energized, Skysight for either Elemental Blessing")
    Said("buff", "1259691")
    Equal(Said("buff", "1270842") .. " | " .. List("buff") .. " | " .. Custom("Energized"),
        "true Added Energized (ID 1270842) to Buffs. | Read Leyline,Skysight,Energized,Energized#1270842 | 1259691",
        "beside them, the two Energized still go on one each")
    Equal(#printed, 0, "no errors")

    -- A hunter's pet abilities: on the Cooldowns bar each goes by the pet's
    -- own spell, the one with the cooldown. Added by its ID, that ID; by
    -- name, the highest rank your pet knows; saved by a Beast Training
    -- spell before (Bite's 17254), the pet's highest rank.
    petKnows = { [17261] = true, [14921] = true }
    Start("HUNTER")
    Said("cd", "17261")
    Equal(Custom("Bite") .. " " .. Sp:Find("Bite").spellID .. " | " .. Said("util", "Growl") .. " | " .. Custom("Growl") .. " "
        .. Sp:Find("Growl").spellID, "17261 17261 | true Added Growl to Utility. | 14921 14921",
        "pet Bite by its ID goes by that ID; Growl by name, by your pet's (not a druid's 6795)")
    local calls = {}
    for _, id in ipairs(cooldownCalls) do calls[id] = true end
    Equal(tostring(calls[17261]) .. " " .. tostring(calls[14921]) .. " " .. tostring(calls[17268]), "true true nil",
        "their cooldowns asked of the pet's spells, not a Beast Training one")
    Said("buff", "Furious Howl")
    Said("debuff", "Scorpid Poison")
    Equal(Lit("buff", 24604) .. " | " .. Lit("debuff", 24587) .. " | " .. Custom("Scorpid Poison"),
        "g1 | g1 | 24587", "by name, Furious Howl lights for its buff and Scorpid Poison for its debuff, every rank")
    petKnows = {}
    Start("HUNTER", { useBars = true, notesSeen = "dev", everyone = "Old", custom = { Bite = { 17254 } },
        profiles = { Old = { cd = { "Bite" }, util = {}, buff = {}, debuff = {}, joins = {} } } })
    Equal(Sp:Find("Bite").spellID .. " " .. tostring(Sp:ForMe("Bite", "cd")), "17261 true",
        "Bite saved by its Beast Training spell: the pet's highest rank")
    -- With no pet out, Growl by name is still the pet's: the data's highest
    -- rank with a cooldown, not a druid's first.
    Equal(Said("util", "Growl") .. " | " .. Custom("Growl") .. " " .. Sp:Find("Growl").spellID,
        "true Added Growl to Utility. | 14921 14921", "Growl by name with the pet away: the pet's top rank")
    -- Saved by name before (1.5.7 remembered the data's first rank: a
    -- druid's Growl and Dash, a warrior's Charge), or at a rank the pet out
    -- now has passed (Bite at rank 4): each goes by the rank the pet knows.
    petKnows = { [14921] = true, [27685] = true, [23110] = true, [17261] = true }
    Start("HUNTER", { useBars = true, notesSeen = "dev", everyone = "Old",
        custom = { Growl = { 6795 }, Charge = { 100 }, Dash = { 1850 }, Bite = { 17257 } },
        profiles = { Old = { cd = { "Bite" }, util = { "Growl", "Charge", "Dash" }, buff = {}, debuff = {}, joins = {} } } })
    B:RefreshAll()
    calls = {}
    for _, id in ipairs(cooldownCalls) do calls[id] = true end
    Equal(Sp:Find("Growl").spellID .. " " .. Sp:Find("Charge").spellID .. " " .. Sp:Find("Dash").spellID .. " " .. Sp:Find("Bite").spellID
        .. " | " .. tostring(calls[14921] and calls[27685] and calls[23110] and calls[17261]) .. " "
        .. tostring(calls[6795] or calls[100] or calls[1850] or calls[17257]), "14921 27685 23110 17261 | true nil",
        "saved by a druid's or warrior's rank, or the pet's old one: the pet's own spells, and their cooldowns asked of them")
    Equal(#printed, 0, "no errors")

    -- Saved by the trap debuffs' old names (build 70291 dropped "Effect"):
    -- each still watches every rank, and is still a hunter's only.
    local old = { useBars = true, notesSeen = "dev", everyone = "Old",
        custom = { ["Immolation Trap Effect"] = { 13797 }, ["Freezing Trap Effect"] = { 3355 } },
        profiles = { Old = { cd = {}, util = {}, buff = {}, debuff = { "Immolation Trap Effect", "Freezing Trap Effect" }, joins = {} } } }
    Start("HUNTER", old)
    local burns, freezes = Sp:Find("Immolation Trap Effect").ids, Sp:Find("Freezing Trap Effect").ids
    Equal(tostring(Has(burns, 13797, 14298, 14299, 14300, 14301)) .. " " .. tostring(Has(freezes, 3355, 14308, 14309)) .. " | "
        .. Lit("debuff", 14301) .. " | " .. Lit("debuff", 14309), "true true | g1 | g2",
        "each lights for its top rank, as for its first")
    Start("DRUID", old)
    Equal(tostring(Sp:ForMe("Immolation Trap Effect", "debuff")) .. " " .. B:Get("debuff").count, "false 0",
        "a druid sharing the profile doesn't see them")
    Equal(#printed, 0, "no errors")

    -- Build 70425 renamed the Skyborne's Read Ley Line (Read Leyline) and
    -- the paladin's Blessing of Salvation and Greater Blessing of Salvation
    -- (Salvation and Mass Salvation), keeping their IDs; and brought Frost
    -- Blast, Revoke, a fourth Mana Tide Totem (its buff one of the Mana Tide
    -- family) and Reckoning's buff.
    Equal(tostring(data.RANKS["Read Ley Line"]) .. " " .. Joined(data.RANKS["Read Leyline"]) .. " " .. tostring(data.SPELL_RACES["Read Leyline"])
        .. " | " .. tostring(data.RANKS["Blessing of Salvation"]) .. " " .. tostring(data.RANKS["Greater Blessing of Salvation"]) .. " "
        .. Joined(data.RANKS.Salvation) .. " " .. Joined(data.RANKS["Mass Salvation"]) .. " " .. tostring(data.SPELL_CLASSES["Mass Salvation"]),
        "nil 1259705 95 | nil nil 1038 25895 PALADIN", "the new names, the same IDs")
    Equal(Joined(data.RANKS["Frost Blast"]) .. " " .. tostring(Has(data.DEBUFFS.MAGE, "Frost Blast")) .. " | " .. Joined(data.RANKS.Revoke)
        .. " " .. tostring(data.SPELL_CLASSES.Revoke) .. " | " .. Joined(data.RANKS["Mana Tide Totem"]) .. " " .. Joined(FamilyOf(1325257))
        .. " | " .. Joined(data.PASSIVE_BUFFS[20177]), "1326053,1326054,1326055 true | 1325499 PALADIN | 16190,17354,17359,1325256"
        .. " 16191,17355,17360,1325257 | 1326084", "Frost Blast (a mage's debuff), Revoke, Mana Tide's fourth rank, Reckoning's buff")
    NAMES[16191], NAMES[1325257], NAMES[20177] = "Mana Tide", "Mana Tide", "Reckoning"
    Start("SHAMAN")
    Equal(Said("buff", "16191") .. " | " .. Lit("buff", 1325257) .. " | " .. tostring(Sp:AddNote("20177", "buff")) .. " | "
        .. tostring(Sp:AddNote("20177", "cd")), "true Added Mana Tide to Buffs. | g1 | nil | Reckoning is passive. Only its buff"
        .. " can be tracked, on the Buffs bar.", "Mana Tide lights for the fourth totem's; Reckoning goes on the Buffs bar now")

    -- Saved by the old names: every profile's keys move over as it loads
    -- (each bar's list and each form's, joins, the pulse's ticks and Long, a
    -- pinned one's name), and so do spells added by those names (merged with
    -- the new name's, each ID once). A list holding both keeps the first,
    -- with its join. A paladin's Salvation lights for Mass Salvation too.
    local function Renamed()
        return { useBars = true, notesSeen = "dev", helpSeen = true, everyone = "Old",
            custom = { ["Blessing of Salvation"] = { 25895, 1038 }, Salvation = { 1038 }, ["Read Ley Line"] = { 1259705 } },
            profiles = {
                Old = { cd = { "Read Ley Line" }, util = {}, buff = { "Blessing of Salvation" }, debuff = {}, joins = {},
                    forms = { [5] = { cd = { "Read Ley Line" } } },
                    pulsePick = { ["Read Ley Line"] = true, Barkskin = true }, pulseStyle = { ["Read Ley Line"] = "long" } },
                Other = { cd = {}, util = { "Read Ley Line#1259705" }, debuff = {},
                    buff = { "Arcane Intellect", "Blessing of Salvation", "Salvation", "Greater Blessing of Salvation" },
                    joins = { buff = { ["Blessing of Salvation"] = true, ["Greater Blessing of Salvation"] = true } } } } }
    end
    local function Keys(set)
        local keys = {}
        for key, value in pairs(set or {}) do keys[#keys + 1] = key .. "=" .. (type(value) == "table" and Joined(value) or tostring(value)) end
        table.sort(keys)
        return table.concat(keys, " ")
    end
    NAMES[1038], NAMES[25895], NAMES[1259705] = "Salvation", "Mass Salvation", "Read Leyline"
    Start("PALADIN", Renamed(), { { name = "Salvation", spellID = 1038, iconID = 1 } })
    local mine, other = db.profiles.Old, db.profiles.Other
    Equal(table.concat(mine.cd, ",") .. " " .. table.concat(mine.forms[5].cd, ",") .. " " .. table.concat(mine.buff, ",") .. " | "
        .. Keys(mine.pulsePick) .. " | " .. Keys(mine.pulseStyle), "Read Leyline Read Leyline Salvation | Barkskin=true Read Leyline=true"
        .. " | Read Leyline=long", "your profile: each list, each form's, the pulse's ticks and Long")
    Equal(table.concat(other.buff, ",") .. " | " .. Keys(other.joins.buff) .. " | " .. table.concat(other.util, ","),
        "Arcane Intellect,Salvation,Mass Salvation | Mass Salvation=true Salvation=true | Read Leyline#1259705",
        "another profile too: the second Salvation gone, the joins kept, a pinned one under its new name")
    Equal(Keys(db.custom), "Read Leyline=1259705 Salvation=1038,25895", "spells added by those names, merged with the new name's")
    Equal(Lit("buff", 1038) .. " | " .. Lit("buff", 25895), "g1 | g1", "a paladin's Salvation lights for Salvation and Mass Salvation")
    Start("PALADIN", db)
    Equal(table.concat(db.profiles.Old.cd, ",") .. " | " .. Keys(db.custom), "Read Leyline | Read Leyline=1259705 Salvation=1038,25895",
        "loaded again: nothing left to move")

    -- Should an old name turn up after all (nothing saves one now), it still
    -- counts as the new one: Blessing of Salvation lights for Mass Salvation
    -- too, and Read Ley Line is still a Skyborne's racial, for them and kept
    -- by Clear.
    db.profiles.Old.buff[2], db.profiles.Old.cd[2] = "Blessing of Salvation", "Read Ley Line"
    db.custom["Blessing of Salvation"], db.custom["Read Ley Line"], db.custom.Energized = { 1038 }, { 1259691 }, { 1259691 }
    db.profiles.Old.cd[3] = "Energized"
    Sp:Stale()
    local race = _G.UnitRace
    _G.UnitRace = function() return "Skyborne", "Skyborne", 95 end
    local skyborne = tostring(Sp:ForMe("Read Ley Line", "cd"))
    _G.UnitRace = function() return "Human", "Human", 1 end
    Equal(tostring(Has(Sp:Find("Blessing of Salvation").ids, 25895)) .. " | " .. skyborne .. " " .. tostring(Sp:ForMe("Read Ley Line", "cd"))
        .. " | " .. tostring(Sp:Leftover("Read Ley Line", "cd")) .. " " .. tostring(Sp:Leftover("Energized", "cd")),
        "true | true false | false true", "an old name goes by the new one's group version, races and Clear")
    _G.UnitRace = race
    -- A profile shared from before the new names comes in under them, and so
    -- do the spells it added by name.
    Start("WARRIOR")
    local ok = ns.ImportProfile("Shared", { lists = { cd = { "Read Ley Line" }, util = {}, buff = { "Greater Blessing of Salvation" },
        debuff = {} }, joins = {}, pick = { ["Read Ley Line"] = true }, style = {},
        added = { ["Greater Blessing of Salvation"] = { 25895 } } }, false)
    local shared = db.profiles.Shared
    Equal(tostring(ok) .. " " .. table.concat(shared.cd, ",") .. " " .. table.concat(shared.buff, ",") .. " | " .. Keys(shared.pulsePick)
        .. " | " .. Keys(db.custom) .. " | " .. Lit("buff", 25895), "true Read Leyline Mass Salvation | Read Leyline=true"
        .. " | Mass Salvation=25895 | g1", "a profile shared under the old names comes in under the new ones")
    Equal(#printed, 0, "no errors")
end)()

-- Added where it can't show ------------------------------------------------------------------------
-- On the Cooldowns and Utility pages a buff's ID (Energized, 1259691) was
-- offered under Other spells, and ticking it said "Added Energized to
-- Cooldowns." Then it was gone: the game never says you know a buff, so it
-- showed for no one, with no row, no icon and no Clear left to take it off,
-- kept in the profile for good. Another class's spell searched by name (a
-- druid's Sprint) did the same. Neither is offered now, adding either is
-- turned away in a drag's words, and Clear takes what was stuck before
-- (but not another class's spell, which shows for the characters that have
-- it). Where the game can't say what you know, it goes on as before. (In a
-- function of its own: this file's main chunk has little room for more locals.)
;(function()
    local NAMES = { [1259691] = "Energized", [1270842] = "Energized", [1259705] = "Read Leyline", [11305] = "Sprint",
        [19244] = "Spell Lock", [12975] = "Last Stand", [1264482] = "Sonic Blast", [20925] = "Holy Shield", [18118] = "Aftermath" }
    local ns, B, w, page, db
    -- A Skyborne druid; with knows, the game says you know your spellbook's
    -- spells (and nothing else), as it does, and your pet the spells in pet.
    local function Start(saved, knows, class, pet)
        Fresh()
        local game = C_Spell.GetSpellName
        C_Spell.GetSpellName = function(id) return NAMES[id] or game(id) end
        if class then _G.UnitClass = function() return class, class end end
        if knows then
            local known = {}
            for _, tab in ipairs(book) do
                for _, item in ipairs(tab.items) do
                    if not item.future then known[item.spellID] = true end
                end
            end
            _G.Enum.SpellBookSpellBank.Pet = 1
            C_SpellBook.IsSpellKnown = function(id, bank)
                if bank == 1 then return (pet or {})[id] == true end
                return bank == 0 and known[id] == true
            end
        end
        ns = Load(saved or { useBars = true, notesSeen = "dev", helpSeen = true })
        B, db = ns.Bars, ForeverEnhancedCooldownManagerDB
        SlashCmdList.FECM("")
        w = FECMFrame
        page = w.pages.bar
    end
    local function Search(text)
        page.search:SetText(text)
        S[page.search].scripts.OnTextChanged(page.search, true)
    end
    -- The list's rows holding the text, ticked, unticked or offered under
    -- Other spells; or the first heading when there are none.
    local function Rows(match)
        local out, heading = {}, nil
        for _, row in ipairs(page.rows) do
            if S[row].shown and S[row.check].shown and (S[row.name].text or ""):lower():find(match, 1, true) then
                out[#out + 1] = S[row.name].text .. " " .. (row.other and "offered" or row.check:GetChecked() and "ticked" or "unticked")
            elseif S[row].shown and not S[row.check].shown then
                heading = heading or S[row.header].text
            end
        end
        return #out > 0 and table.concat(out, " | ") or tostring(heading)
    end
    local function Note(frame)
        local hint = frame.hint
        if type(hint) == "function" then hint = hint(frame) end
        return hint
    end
    local function Said(key, text)
        local ok, message = B:Add(key, text)
        return tostring(ok) .. " " .. message
    end
    local function List(key) return table.concat(ns.BarData(key).spells, ",") end
    local function Custom()
        local out = {}
        for name, ids in pairs(db.custom or {}) do out[#out + 1] = name .. "=" .. table.concat(ids, ",") end
        table.sort(out)
        return table.concat(out, " ")
    end

    -- Neither offered on the Cooldowns or Utility page, and turned away
    -- however it's added: by ID, by name, or held over the bar.
    Start(nil, true)
    w:Select("cd")
    Search("1259691")
    local energized = Rows("energized")
    Search("sprint")
    Equal(energized .. " | " .. Rows("sprint"), "NO MATCHES | NO MATCHES",
        "the Cooldowns page offers neither a buff's ID nor a rogue's spell")
    Equal(table.concat({ Said("cd", "1259691"), Said("util", "1259691"), Said("cd", "Sprint"), select(2, B:CanAdd("util", "1259691")) }, " | "),
        "false Energized can't show on the Cooldowns bar for you. | false Energized can't show on the Utility bar for you."
        .. " | false Sprint can't show on the Cooldowns bar for you. | Energized can't show on the Utility bar for you.",
        "added anyway: turned away in a drag's words, and held over the bar it says the same")
    Equal(List("cd") .. "|" .. List("util") .. "|" .. Custom(), "||", "nothing put on, nothing remembered")
    -- Your own spells still go on, learned or not; the buff still goes on
    -- the Buffs bar, where it shows.
    Search("hurric")
    Equal(Rows("hurricane") .. " | " .. Said("cd", "Hurricane") .. " | " .. table.concat((B:Mine("cd")), ","),
        "Hurricane offered | true Added Hurricane to Cooldowns. | Hurricane",
        "a druid spell not learned yet is still offered, and goes on (greyed)")
    w:Select("buff")
    Search("1259691")
    Equal(Rows("energized") .. " | " .. Said("buff", "1259691"), "Energized (ID 1259691) offered | true Added Energized to Buffs.",
        "on the Buffs page the buff is offered and goes on, as before")
    Equal(select(2, B:Transfer("buff", "cd", "Energized")), "Energized can't show on the Cooldowns bar for you.",
        "dragged from there onto the Cooldowns bar: turned away, as it always was")
    Equal(#printed, 0, "no errors")

    -- Stuck before: Energized by name and pinned on cooldown bars, beside a
    -- rogue's Sprint in the shared profile. Clear takes the buffs, which
    -- show for no one, and leaves Sprint for the rogue.
    local stuck = { useBars = true, notesSeen = "dev", helpSeen = true, everyone = "Old",
        custom = { Energized = { 1259691 }, Sprint = { 11305 } },
        profiles = { Old = { cd = { "Energized", "Sprint", "Moonfire" }, util = { "Energized#1270842" }, buff = { "Energized" },
            debuff = {}, joins = {} } } }
    Start(stuck, true)
    Equal(table.concat((B:Mine("cd")), ",") .. " | " .. table.concat(B:Leftovers("cd"), ",") .. " | " .. table.concat(B:Leftovers("util"), ",")
        .. " | " .. table.concat(B:Leftovers("buff"), ","), "Moonfire | Energized | Energized#1270842 | ",
        "Moonfire is yours; the two Energized on cooldown bars show for no one; on the Buffs bar it shows")
    w:Select("util")
    Equal(S[page.count].text .. " | " .. tostring(S[page.clear].shown) .. " | " .. Note(page.clear),
        "Empty | true | Take every icon off Utility, and buffs or debuffs added to it that can't show there. It asks for a second"
        .. " click. (experimental)", "nothing of yours on Utility, but Clear shows, and says what it takes")
    page.clear:Click()
    page.clear:Click()
    Equal(List("util") .. " | " .. S[w.note].text .. " | " .. tostring(S[page.clear].shown), " | Utility cleared. | false",
        "cleared: the pinned Energized gone, and the button with it")
    w:Select("cd")
    Equal(Note(page.clear), "Take every icon off Cooldowns, and buffs or debuffs added to it that can't show there. It asks for a"
        .. " second click. (experimental)", "the Cooldowns page's Clear says so too")
    page.clear:Click()
    page.clear:Click()
    Equal(List("cd") .. " | " .. List("buff") .. " | " .. Custom(), "Sprint | Energized | Energized=1259691 Sprint=11305",
        "Moonfire and Energized cleared; the rogue's Sprint stays, and so does Energized on the Buffs bar")
    Equal(tostring(S[page.clear].shown) .. " " .. Note(page.clear), "false Take every icon off Cooldowns. It asks for a second click.",
        "nothing left to take: no Clear, and its note as it was")
    Start(stuck, true, "ROGUE")
    Equal(table.concat((B:Mine("cd")), ",") .. " " .. tostring(ns.Spells:ForMe("Sprint", "cd")), "Sprint true", "the rogue still sees Sprint")
    Equal(#printed, 0, "no errors")

    -- Shared with a hunter and a paladin: the bat's Sonic Blast and the
    -- talent Holy Shield, kept by ID, are spells someone knows, though the
    -- data names no class for them, so a druid's Clear leaves them; a debuff
    -- no one learns (Aftermath's), ticked on Utility before, goes.
    local shared = { useBars = true, notesSeen = "dev", helpSeen = true, everyone = "Old",
        custom = { ["Sonic Blast"] = { 1264482 }, ["Holy Shield"] = { 20925 }, Aftermath = { 18118 } },
        profiles = { Old = { cd = { "Sonic Blast" }, util = { "Holy Shield", "Aftermath" }, buff = {}, debuff = {}, joins = {} } } }
    Start(shared, true)
    Equal("[" .. table.concat((B:Mine("cd")), ",") .. "] [" .. table.concat(B:Leftovers("cd"), ",") .. "] ["
        .. table.concat(B:Leftovers("util"), ",") .. "]", "[] [] [Aftermath]", "none of it the druid's; only Aftermath's debuff a leftover")
    w:Select("util")
    Equal(Note(page.clear), "Take every icon off Utility, and buffs or debuffs added to it that can't show there. It asks for a second"
        .. " click. (experimental)", "Clear says it takes debuffs too")
    page.clear:Click()
    page.clear:Click()
    B:Clear("cd")
    Equal(List("cd") .. " | " .. List("util") .. " | " .. Custom(), "Sonic Blast | Holy Shield | Holy Shield=20925 Sonic Blast=1264482",
        "cleared: Aftermath's debuff gone; the hunter's Sonic Blast and the paladin's Holy Shield stay")
    Start(shared, true, "HUNTER", { [1264482] = true })
    Equal(table.concat((B:Mine("cd")), ",") .. " " .. tostring(ns.Spells:Leftover("Sonic Blast", "cd")), "Sonic Blast false",
        "the hunter, his bat out, still has it")

    -- What you or your pet don't know yet still goes on the Cooldowns bar,
    -- shown once known, as before: the felhunter's Spell Lock while a
    -- warlock's imp is out, Last Stand before a warrior takes the talent.
    -- The page offers each by its ID.
    Start(nil, true, "WARLOCK")
    w:Select("cd")
    Search("19244")
    Equal(Rows("spell lock") .. " | " .. Said("cd", "19244") .. " | " .. tostring(ns.Spells:ForMe("Spell Lock", "cd")),
        "Spell Lock (ID 19244) offered | true Added Spell Lock to Cooldowns. | false",
        "the felhunter's Spell Lock with the imp out: offered and added, hidden until the felhunter's out")
    Equal(Said("util", "Spell Lock") .. " | " .. List("cd") .. " | " .. List("util"), "true Added Spell Lock to Utility. |  | Spell Lock",
        "added again by name on Utility, still hidden: it moves there")
    Start(db, true, "WARLOCK", { [19244] = true })
    Equal(table.concat((B:Mine("util")), ","), "Spell Lock", "the felhunter out: it shows")
    Start(nil, true, "WARRIOR")
    w:Select("cd")
    Search("12975")
    Equal(Rows("last stand") .. " | " .. Said("cd", "12975"), "Last Stand (ID 12975) offered | true Added Last Stand to Cooldowns.",
        "Last Stand before the talent's taken: offered and added")
    Equal(#printed, 0, "no errors")

    -- Where the game can't say what you know, a buff's ID goes on the
    -- Cooldowns bar as before, and shows (ticked, so it can be taken off).
    Start(nil, false)
    w:Select("cd")
    Search("1259691")
    Equal(Rows("energized") .. " | " .. Said("cd", "1259691") .. " | " .. table.concat((B:Mine("cd")), ","),
        "Energized (ID 1259691) offered | true Added Energized to Cooldowns. | Energized", "the game can't say: offered and added, and shown")
    Equal(#printed, 0, "no errors")
end)()

-- Only show missing: buffs only while they're not on you ---------------------------------------------
-- A CurseForge comment asked for the Buffs bar to show a buff only while
-- it's missing (Fortitude, Inner Fire, Mark of the Wild: any of them). Out of
-- a fight the addon reads which entries are on you (GetPlayerAuraBySpellID,
-- each ID the entry's slot is given) and shows only the missing ones, greyed
-- in their fixed spots, side by side in the bar's room for them all; one on
-- you has no spot and its slot is off. In a fight the game keeps your buffs
-- secret, so nothing is read, shown, hidden, moved or told to the container:
-- a buff cast then lights in its slot over its greyed spot as usual, and the
-- bar catches up as the fight ends. Unlocked or in Edit Mode every entry
-- shows, to place the bar. (In a function of its own: this file's main chunk
-- has little room for more locals.)

;(function()
    Fresh()
    local ns = Load({ useBars = true, notesSeen = "dev", helpSeen = true })
    local B = ns.Bars
    for _, name in ipairs({ "Thorns", "Clearcasting", "Nature's Grace", "Walk on Air" }) do B:SetAura("buff", name, true) end
    local bar = B:Get("buff")
    local box = S[bar.container]
    -- The next frame: the driver's refresh, once.
    local function NextFrame()
        local run = S[B.driver].scripts.OnUpdate
        if run then run(B.driver, 0) end
    end
    -- Your buffs changed, as the game says (UNIT_AURA), then the next frame.
    local function Changed()
        Fire("UNIT_AURA", "player")
        NextFrame()
    end
    -- The entries showing on the bar, in order, each at its place from the
    -- bar's left edge. With rows, its place across and up or down too, after
    -- the corner of the bar they're placed from.
    local function Showing(rows)
        local out, corner = {}, nil
        for i = 1, bar.count do
            local holder = bar.holders[i]
            if S[holder].shown then
                local p = S[holder].points[1]
                local at = p and (rows and ("%g,%g"):format(p[4], p[5]) or ("%g"):format(p[4])) or "nowhere"
                corner = corner or p and p[1]
                out[#out + 1] = S[holder.label].text .. "@" .. at
            end
        end
        return (rows and (tostring(corner) .. ": ") or "") .. table.concat(out, ", ")
    end
    -- The container's slots and groups switched on.
    local function On()
        local out = {}
        for i = 1, ns.BUFF_SLOTS do
            if box.slots["b" .. i].enabled then out[#out + 1] = "b" .. i end
        end
        for i = 1, bar.groups do
            if box.groups["g" .. i].enabled then out[#out + 1] = "g" .. i end
        end
        return table.concat(out, " ")
    end
    local function Heard() return tostring(S[B.driver].events.UNIT_AURA == true) end
    -- How many spell IDs the bar's entries watch in all.
    local function IDs()
        local n = 0
        for i = 1, bar.count do
            for _ in pairs(bar.slotIDs[i]) do n = n + 1 end
        end
        return n
    end
    local function Size() return S[bar].width .. "x" .. S[bar].height end
    -- Thorns on you at a rank you don't know (another druid's), and Nature's Grace up.
    PlayerAuras[9910], PlayerAuras[16886] = true, true

    -- Off (the default): as before, packed or with missing ones greyed, and
    -- nothing read or heard.
    Equal(tostring(ns.BarData("buff").onlyMissing) .. " | " .. On() .. " | " .. Showing() .. " | " .. AuraReads .. " " .. Heard(),
        "false | g1 g2 g3 g4 |  | 0 false", "off at first: packed as before, nothing read, your buffs changing not heard")
    B:SetOption("buff", "showMissing", true)
    Equal(On() .. " | " .. Showing() .. " | " .. Size() .. " | " .. AuraReads .. " " .. Heard(),
        "b1 b2 b3 b4 | Thorns@0, Clearcasting@40, Nature's Grace@80, Walk on Air@120 | 156x36 | 0 false",
        "with missing ones greyed: every entry in its spot, as before, and still nothing read")
    B:SetOption("buff", "showMissing", false)

    -- On: only the buffs not on you, side by side in your order, in the
    -- bar's room for all four.
    B:SetOption("buff", "onlyMissing", true)
    Equal(On() .. " | " .. Showing() .. " | " .. Size() .. " | " .. Heard(),
        "b2 b4 | Clearcasting@40, Walk on Air@80 | 156x36 | true",
        "on: Clearcasting and Walk on Air only, side by side and centred, the bar its size for all four, your buffs heard")
    local held = bar.holders[2]
    Equal(tostring(box.slots.b2.filters.includeSpellIDs[16870]) .. " " .. tostring(box.slots.b4.filters.includeSpellIDs[1308663])
        .. " " .. tostring(S[held.icon].desaturated) .. " " .. S[held.icon].alpha .. " " .. tostring(S[bar.holders[1]].shown)
        .. " " .. tostring(S[bar.holders[3]].shown), "true true true 0.45 false false",
        "each missing one watched in its slot and greyed in its spot; Thorns (any rank) and Nature's Grace, on you, have neither")
    B:SetOption("buff", "grow", "left")
    local left = Showing()
    B:SetOption("buff", "grow", "right")
    Equal(left .. " | " .. Showing(), "Clearcasting@120, Walk on Air@80 | Clearcasting@0, Walk on Air@40",
        "growing left: from the right edge, the first on the right; growing right: from the left edge")
    B:SetOption("buff", "grow", "centre")

    -- In rows (two to a row): the bar keeps two rows for all four, and the
    -- spots showing fill the first row, then the next; a short last row lines
    -- up as the bar grows, and no box goes round it (the whole bar's, not
    -- one round the icons in it).
    B:SetOption("buff", "perRow", 2)
    local two = Showing(true) .. " | " .. Size()
    PlayerAuras[16886] = nil
    Changed()
    Equal(two .. " || " .. Showing(true) .. " | " .. Size() .. " " .. tostring(bar.short),
        "TOPLEFT: Clearcasting@0,0, Walk on Air@40,0 | 76x76 || TOPLEFT: Clearcasting@0,0, Nature's Grace@40,0, Walk on Air@20,-40"
        .. " | 76x76 false", "two missing: both in the first row, the bar two rows high for all four; three: the third centred in the second")
    B:SetOption("buff", "grow", "left")
    left = Showing(true)
    B:SetOption("buff", "grow", "right")
    Equal(left .. " | " .. Showing(true), "TOPLEFT: Clearcasting@40,0, Nature's Grace@0,0, Walk on Air@40,-40 | TOPLEFT: Clearcasting@0,0,"
        .. " Nature's Grace@40,0, Walk on Air@0,-40", "growing left or right: the lone one in the second row at that edge")
    B:SetOption("buff", "grow", "centre")
    B:SetOption("buff", "wrap", "up")
    Equal(Showing(true) .. " | " .. Size(), "BOTTOMLEFT: Clearcasting@0,0, Nature's Grace@40,0, Walk on Air@20,40 | 76x76",
        "new rows above: the first row at the bottom, the second over it")
    B:SetOption("buff", "wrap", "down")
    B:SetOption("buff", "showNames", true)
    Equal(Showing(true) .. " | " .. Size() .. " " .. tostring(S[bar.holders[4].label].shown),
        "TOPLEFT: Clearcasting@0,0, Nature's Grace@40,0, Walk on Air@20,-54 | 76x90 true",
        "with spell names: room for them under each row, and the bar taller to match")
    B:SetOption("buff", "showNames", false)
    B:SetOption("buff", "perRow", 20)
    PlayerAuras[16886] = true
    Changed()
    Equal(Showing() .. " | " .. Size(), "Clearcasting@40, Walk on Air@80 | 156x36", "back in one row")

    -- Your buffs changing: read on the next frame, once however many came
    -- at once (every ID of every entry, with none on you).
    PlayerAuras[9910], PlayerAuras[16886] = nil, nil
    local reads = AuraReads
    for _ = 1, 3 do Fire("UNIT_AURA", "player") end
    local waiting = Showing()
    NextFrame()
    Equal(waiting .. " | " .. Showing() .. " | " .. On() .. " | " .. tostring(AuraReads - reads == IDs()),
        "Clearcasting@40, Walk on Air@80 | Thorns@0, Clearcasting@40, Nature's Grace@80, Walk on Air@120 | b1 b2 b3 b4 | true",
        "Thorns and Nature's Grace gone: three changes, one read on the next frame, and both show in their places")
    reads = AuraReads
    for _ = 1, 20 do NextFrame() end
    Equal(AuraReads - reads, 0, "never polled: with nothing heard, frames go by without a read")
    PlayerAuras[467] = true
    Changed()
    Equal(Showing() .. " | " .. On(), "Clearcasting@20, Nature's Grace@60, Walk on Air@100 | b2 b3 b4",
        "Thorns cast again, at your own rank: it goes and the rest close up")

    -- Joined: one icon for either, so it's on you while either is.
    B:SetJoined("buff", 2, true)
    local joined = Showing() .. " | " .. Size()
    PlayerAuras[467], PlayerAuras[16870] = nil, true
    Changed()
    local either = Showing()
    PlayerAuras[16870] = nil
    Changed()
    Equal(joined .. " | " .. either .. " | " .. Showing(), "Nature's Grace@20, Walk on Air@60 | 116x36 | Nature's Grace@20, Walk on Air@60"
        .. " | Thorns +1@0, Nature's Grace@40, Walk on Air@80", "Clearcasting joined to Thorns: one entry, up while either is, shown once neither is")
    B:SetJoined("buff", 2, false)

    -- An answer the game keeps secret, or one that can't be read, keeps
    -- what that entry was: Thorns, on you, stays hidden though it's gone;
    -- Nature's Grace, missing, stays shown though it's back.
    PlayerAuras[467] = true
    Changed()
    local before = Showing()
    local get = C_UnitAuras.GetPlayerAuraBySpellID
    C_UnitAuras.GetPlayerAuraBySpellID = function(id)
        if id == 782 then error("can't be read") end
        return get(id)
    end
    PlayerAuras[467], PlayerAuras[16886] = nil, SECRET
    Changed()
    Equal(before .. " | " .. Showing(), "Clearcasting@20, Nature's Grace@60, Walk on Air@100 | Clearcasting@20, Nature's Grace@60,"
        .. " Walk on Air@100", "Thorns unreadable and Nature's Grace secret: each stays as it was")
    C_UnitAuras.GetPlayerAuraBySpellID = get
    PlayerAuras[16886] = nil
    -- While the game says auras are secret out of a fight (a raid encounter),
    -- nothing is read, and nothing changes.
    AurasSecret = true
    reads = AuraReads
    PlayerAuras[16870] = true
    Changed()
    local secret = Showing() .. " | " .. (AuraReads - reads)
    -- One added then, never read, counts as missing, so it shows.
    local added = B:Add("buff", "Mark of the Wild")
    local withMark = Showing()
    B:SetAura("buff", "Mark of the Wild", false)
    AurasSecret, PlayerAuras[16870] = false, nil
    Changed()
    Equal(secret .. " | " .. tostring(added) .. " " .. withMark .. " | " .. Showing(), "Clearcasting@20, Nature's Grace@60, Walk on Air@100"
        .. " | 0 | true Clearcasting@20, Nature's Grace@60, Walk on Air@100, Mark of the Wild@140 | Thorns@0, Clearcasting@40,"
        .. " Nature's Grace@80, Walk on Air@120",
        "auras kept secret: nothing read or changed, and Mark of the Wild added then shows; all read again once they aren't")

    -- A fight: nothing read, shown, hidden, moved or told to the container.
    PlayerAuras[467], PlayerAuras[16870], PlayerAuras[16886] = nil, nil, true
    Changed()
    watched[bar] = true
    for _, holder in ipairs(bar.holders) do watched[holder] = true end
    Fire("PLAYER_REGEN_DISABLED")
    lockdown = true
    local calls, spots = containerCallsInCombat, Showing()
    reads = AuraReads
    local slot = box.slots.b2
    Equal(spots .. " | " .. Heard() .. " | " .. On() .. " | " .. tostring(S[bar.holders[2]].shown) .. " "
        .. tostring(Last(slot.button, "SetAllPoints") == bar.holders[2]) .. " " .. tostring(slot.filters.includeSpellIDs[16870]),
        "Thorns@20, Clearcasting@60, Walk on Air@100 | false | b1 b2 b4 | true true true",
        "in a fight your buffs aren't heard; a missing one's slot stays on, its icon over the greyed spot, so Clearcasting cast now lights there")
    PlayerAuras[16870], PlayerAuras[16886] = true, nil
    Fire("UNIT_AURA", "player")
    for _ = 1, 5 do NextFrame() end
    B:SetUnlocked(true)
    B:SetUnlocked(false)
    EditModeManagerFrame:Show()
    EditModeManagerFrame:Hide()
    local toggled = S[bar].combatToggle == true
    for _, holder in ipairs(bar.holders) do toggled = toggled or S[holder].combatToggle == true end
    Equal(Showing() .. " | " .. On() .. " | " .. (containerCallsInCombat - calls) .. " " .. (AuraReads - reads) .. " " .. tostring(toggled),
        spots .. " | b1 b2 b4 | 0 0 false",
        "Clearcasting cast and Nature's Grace gone, unlocked, locked and Edit Mode: nothing read, shown, hidden, moved or switched")
    lockdown = false
    Fire("PLAYER_REGEN_ENABLED")
    Equal(Showing() .. " | " .. On() .. " | " .. Heard(), "Thorns@20, Nature's Grace@60, Walk on Air@100 | b1 b3 b4 | true",
        "as it ends: Clearcasting, cast in the fight, goes; Nature's Grace, gone in it, shows; heard again")
    watched[bar] = nil
    for _, holder in ipairs(bar.holders) do watched[holder] = nil end
    -- A fight with nothing else waiting for its end: the buffs that came
    -- and went in it are read as it ends all the same.
    Fire("PLAYER_REGEN_DISABLED")
    lockdown = true
    PlayerAuras[16870], PlayerAuras[16886] = nil, true
    Fire("UNIT_AURA", "player")
    NextFrame()
    local fought = Showing() .. " " .. tostring(bar.pendingLayout)
    lockdown = false
    Fire("PLAYER_REGEN_ENABLED")
    Equal(fought .. " | " .. Showing() .. " | " .. On(), "Thorns@20, Nature's Grace@60, Walk on Air@100 nil | Thorns@20, Clearcasting@60,"
        .. " Walk on Air@100 | b1 b2 b4", "nothing else waiting: Clearcasting, gone in the fight, and Nature's Grace, cast in it, read as it ends")
    PlayerAuras[16870], PlayerAuras[16886] = true, nil
    Changed()

    -- Your buffs still secret as a fight ends (the game slow to say they
    -- aren't, or an encounter going on after it): nothing changes then, and
    -- they're read again half a second later, so a buff gone in the fight
    -- shows without your buffs changing again. Four times at most, so never
    -- polled, and again once the game's restrictions change.
    local ran = 0
    -- Time going by: the timers queued so far, each run once.
    local function Wait()
        while ran < #timers do
            ran = ran + 1
            timers[ran]()
        end
    end
    Wait()
    local asks, ask = 0, C_Secrets.ShouldAurasBeSecret
    C_Secrets.ShouldAurasBeSecret = function()
        asks = asks + 1
        return ask()
    end
    Fire("PLAYER_REGEN_DISABLED")
    lockdown = true
    PlayerAuras[16870] = nil
    lockdown, AurasSecret = false, true
    Fire("PLAYER_REGEN_ENABLED")
    local ended = Showing() .. " " .. asks .. " " .. tostring(bar.unread)
    AurasSecret = false
    Wait()
    NextFrame()
    Equal(ended .. " | " .. Showing() .. " | " .. On() .. " " .. tostring(bar.unread), "Thorns@20, Nature's Grace@60, Walk on Air@100 1"
        .. " true | Thorns@0, Clearcasting@40, Nature's Grace@80, Walk on Air@120 | b1 b2 b3 b4 nil",
        "Clearcasting gone in the fight, still secret as it ends: kept as it was, then shown once read again, with no change to your buffs heard")
    -- Kept secret on: a read again still to come as another fight starts
    -- does nothing in it; as that one ends, read and four times again, then
    -- not till the game says its restrictions changed (heard out of a fight
    -- only), and on the next frame then, not as it says so.
    Fire("PLAYER_REGEN_DISABLED")
    lockdown = true
    PlayerAuras[16870] = true
    local fighting = tostring(S[B.driver].events.ADDON_RESTRICTION_STATE_CHANGED) .. " " .. tostring(S[B.driver].events.ENCOUNTER_END)
    lockdown, AurasSecret, asks = false, true, 0
    Fire("PLAYER_REGEN_ENABLED")
    Fire("PLAYER_REGEN_DISABLED")
    lockdown = true
    Wait()
    NextFrame()
    local waited = asks .. " " .. tostring(bar.pendingLayout)
    lockdown = false
    Fire("PLAYER_REGEN_ENABLED")
    for _ = 1, 10 do
        Wait()
        NextFrame()
    end
    local tried = asks
    for _ = 1, 20 do NextFrame() end
    Wait()
    local kept = Showing() .. " | " .. waited .. " " .. tried .. " " .. asks .. " | " .. fighting .. " "
        .. tostring(S[B.driver].events.ADDON_RESTRICTION_STATE_CHANGED) .. " " .. tostring(S[B.driver].events.ENCOUNTER_END)
    AurasSecret = false
    Fire("ADDON_RESTRICTION_STATE_CHANGED", 1, 0)
    local told = Showing()
    NextFrame()
    Equal(kept .. " | " .. told .. " | " .. Showing(), "Thorns@0, Clearcasting@40, Nature's Grace@80, Walk on Air@120 | 1 nil 6 6 |"
        .. " nil nil true true | Thorns@0, Clearcasting@40, Nature's Grace@80, Walk on Air@120 | Thorns@20, Nature's Grace@60, Walk on Air@100",
        "Clearcasting cast in a fight, kept secret after it: lit over its spot; nothing in the next fight; read as it ends and four times"
        .. " again, then only once the game's restrictions change, on the next frame")
    reads = AuraReads
    Fire("ENCOUNTER_END")
    Fire("ADDON_RESTRICTION_STATE_CHANGED", 1, 0)
    NextFrame()
    Wait()
    Equal(AuraReads - reads, 0, "with every buff answered, an encounter ending or the game's restrictions changing reads nothing")
    C_Secrets.ShouldAurasBeSecret = ask

    -- Arranging the bars: every entry, to place and size the bar by, the
    -- ones on you lit in their slots.
    B:SetUnlocked(true)
    local unlocked = Showing() .. " | " .. On()
    B:SetUnlocked(false)
    local locked = Showing() .. " | " .. On()
    EditModeManagerFrame:Show()
    local editing = Showing()
    EditModeManagerFrame:Hide()
    Equal(unlocked .. " || " .. locked .. " || " .. editing .. " || " .. Showing(),
        "Thorns@0, Clearcasting@40, Nature's Grace@80, Walk on Air@120 | b1 b2 b3 b4 || Thorns@20, Nature's Grace@60, Walk on Air@100"
        .. " | b1 b3 b4 || Thorns@0, Clearcasting@40, Nature's Grace@80, Walk on Air@120 || Thorns@20, Nature's Grace@60, Walk on Air@100",
        "unlocked or in Edit Mode, all four; locked or out of it, the missing ones")
    -- The Layout page draws every entry too.
    SlashCmdList.FECM("")
    local w = FECMFrame
    w:Select("layout")
    local names = {}
    for _, tile in ipairs(w.pages.layout.rows.buff.tiles) do
        if S[tile].shown and tile.name then names[#names + 1] = tile.name end
    end
    Equal(table.concat(names, ","), "Thorns,Clearcasting,Nature's Grace,Walk on Air", "the Layout page's drawing shows every entry")
    -- /ccm debug says which it last read as on you.
    SlashCmdList.FECM("debug")
    local report = S[FECMDebugFrame.edit].text
    FECMDebugFrame:Hide()
    Equal(tostring(report:find("1. Thorns | spells [%d,]+ | on you false\n  2. Clearcasting | spells 16870 | on you true") ~= nil),
        "true", "the debug report says which it last read as on you")
    -- Your debuffs on you go with packed buffs only.
    B:SetOption("buff", "selfDebuffs", true)
    Equal(tostring(ns.BuffBar:SelfOn(bar)), "false", "not with Only show missing")
    B:SetOption("buff", "selfDebuffs", false)

    -- The page: the tick on Buffs only, under the sliders; while it's on,
    -- missing buffs greyed is greyed out, keeping its own choice.
    local page = w.pages.bar
    local tick, greyed = page.options.onlyMissing, page.options.showMissing
    local function Note(frame)
        local hint = frame.hint
        if type(hint) == "function" then hint = hint(frame) end
        return hint
    end
    local seen = {}
    for _, key in ipairs({ "cd", "util", "buff", "debuff" }) do
        w:Select(key)
        if tick:IsVisible() then seen[#seen + 1] = key end
    end
    w:Select("buff")
    local at = S[tick].points[1]
    Equal(table.concat(seen, " ") .. " | " .. S[tick.text].text .. " | " .. at[1] .. " " .. at[2] .. " " .. at[3] .. " | " .. Note(tick),
        "buff | Only show missing | TOPLEFT 0 -107 | Shows a buff only while it's not on you. The game hides your buffs from addons"
        .. " in a fight, so changes then show once it ends.",
        "on the Buffs page only, under the sliders, saying what it does and its limit in a fight (seen working in game 2026-10-11)")
    Equal(tostring(tick:GetChecked()) .. " " .. tostring(greyed.usable) .. " " .. S[greyed].alpha .. " " .. tostring(greyed:GetChecked())
        .. " | " .. Note(greyed) .. " | " .. tostring(page.across:IsVisible() and page.options.wrap:IsVisible()
        and page.options.showNames:IsVisible()), "true false 0.35 false | Not with Only show missing, which shows only the buffs"
        .. " you're missing. | true", "ticked: missing buffs greyed greyed out, saying why; icons per row, new rows and names offered")
    tick:Click()
    greyed:Click()
    tick:Click()
    Equal(tostring(ns.BarData("buff").onlyMissing) .. " " .. tostring(ns.BarData("buff").showMissing) .. " " .. tostring(greyed.usable)
        .. " " .. tostring(greyed:GetChecked()) .. " " .. S[greyed].alpha, "true true false true 0.35",
        "unticked, missing buffs greyed ticked, ticked again: greyed out with its own choice kept")
    greyed:Click()
    Equal(tostring(ns.BarData("buff").showMissing) .. " " .. tostring(greyed:GetChecked()), "true true", "a click on it while greyed changes nothing")
    tick:Click()
    Equal(tostring(ns.BarData("buff").onlyMissing) .. " " .. tostring(greyed.usable) .. " " .. S[greyed].alpha .. " | " .. On() .. " | "
        .. Showing() .. " | " .. Heard(), "false true 1 | b1 b2 b3 b4 | Thorns@0, Clearcasting@40, Nature's Grace@80, Walk on Air@120 | false",
        "unticked: missing buffs greyed back, as it was, every entry in its spot, your buffs no longer heard")
    w:Select("debuff")
    B:SetOption("debuff", "onlyMissing", true)
    Equal(tostring(ns.BarData("debuff").onlyMissing) .. " " .. tostring(greyed.usable), "false true",
        "not on the Debuffs bar, where missing debuffs greyed stays its own")
    B:SetOption("buff", "showMissing", false)
    w:Select("buff")
    tick:Click()
    w:Hide()
    Equal(tostring(ns.BarData("buff").onlyMissing) .. " " .. On() .. " | " .. Showing(), "true b1 b3 b4 | Thorns@20, Nature's Grace@60,"
        .. " Walk on Air@100", "ticked again on the page: only the missing ones")

    -- A border round whole bars (Look page): none round this one while its
    -- spots come and go; with missing ones greyed, as before.
    ns.Set("iconBorder", "bar")
    local ring = tostring((B:BarDecorFor("buff")))
    B:SetOption("buff", "showMissing", true)
    ring = ring .. " " .. tostring((B:BarDecorFor("buff")))
    B:SetOption("buff", "onlyMissing", false)
    ring = ring .. " " .. tostring((B:BarDecorFor("buff")))
    B:SetOption("buff", "showMissing", false)
    B:SetOption("buff", "onlyMissing", true)
    Equal(ring, "false false true", "no border round the whole bar while its spots come and go; with missing ones greyed, as before")

    -- Kept over a reload, read again as you log in; with your bars off,
    -- nothing read or heard.
    local saved = ForeverEnhancedCooldownManagerDB
    Equal(tostring(saved.bars.buff.onlyMissing), "true", "saved with the Buffs bar's settings")
    Fresh()
    PlayerAuras[782] = true
    ns = Load(saved)
    B = ns.Bars
    bar = B:Get("buff")
    box = S[bar.container]
    Equal(tostring(ns.BarData("buff").onlyMissing) .. " | " .. Showing() .. " | " .. Heard() .. " " .. tostring(AuraReads > 0),
        "true | Clearcasting@20, Nature's Grace@60, Walk on Air@100 | true true", "after a reload: on, read at login, heard")
    ns.Set("useBars", false)
    B:Rebuild()
    reads = AuraReads
    PlayerAuras[782] = nil
    Fire("UNIT_AURA", "player")
    NextFrame()
    B:SetOption("buff", "onlyMissing", true)
    Equal(Heard() .. " " .. (AuraReads - reads), "false 0", "your bars off: nothing heard or read")
    -- Saved before it, or on the Debuffs bar: off.
    Fresh()
    ns = Load({ useBars = true, notesSeen = "dev", bars = { buff = { showMissing = true }, debuff = { onlyMissing = true } } })
    Equal(tostring(ns.BarData("buff").onlyMissing) .. " " .. tostring(ns.BarData("buff").showMissing) .. " "
        .. tostring(ns.BarData("debuff").onlyMissing) .. " " .. tostring(S[ns.Bars.driver].events.UNIT_AURA),
        "false true false nil", "saved before it: off, missing buffs greyed as it was; on the Debuffs bar: off")
    Equal(#printed, 0, "no errors")
end)()

-- Only when missing: single buffs only while they're not on you -----------------------------------
-- A player asked for Only show missing buff by buff (Discord). A buff
-- ticked Only when missing on the Buffs page shows only while it's missing
-- from you, greyed in a fixed slot and spot of its own, as Only show missing
-- does for every buff; the rest stay exactly as they are: the game's packed
-- icons (only while up), or greyed in their spots with missing ones greyed.
-- On a packed bar the spots lead the row (centred as if alone, or from the
-- edge it grows from) and the packed icons follow just past them. Which are
-- on you is read whenever any buff is ticked, out of a fight only, and only
-- for the ticked ones; in a fight nothing is read, shown, hidden, moved or
-- told to the container. Kept per profile, with the repair, a copy of the
-- profile and a buff taken off. (In a function of its own: this file's main
-- chunk has little room for more locals.)

;(function()
    Fresh()
    local ns = Load({ useBars = true, notesSeen = "dev", helpSeen = true })
    local B = ns.Bars
    for _, name in ipairs({ "Thorns", "Clearcasting", "Nature's Grace", "Walk on Air" }) do B:SetAura("buff", name, true) end
    local bar = B:Get("buff")
    local box = S[bar.container]
    local function NextFrame()
        local run = S[B.driver].scripts.OnUpdate
        if run then run(B.driver, 0) end
    end
    local function Changed()
        Fire("UNIT_AURA", "player")
        NextFrame()
    end
    -- The spots showing, in order, each at its place from the bar's left edge.
    local function Showing()
        local out = {}
        for i = 1, bar.count do
            local holder = bar.holders[i]
            if S[holder].shown then
                local p = S[holder].points[1]
                out[#out + 1] = S[holder.label].text .. "@" .. (p and ("%g"):format(p[4]) or "nowhere")
            end
        end
        return table.concat(out, ", ")
    end
    -- The container's slots and groups switched on.
    local function On()
        local out = {}
        for i = 1, ns.BUFF_SLOTS do
            if box.slots["b" .. i].enabled then out[#out + 1] = "b" .. i end
        end
        for i = 1, bar.groups do
            if box.groups["g" .. i].enabled then out[#out + 1] = "g" .. i end
        end
        return table.concat(out, " ")
    end
    -- Where the game's packed icons line up from: the container's point on
    -- the bar's, and how far along (in the container's own scaled size).
    local function Packed()
        local p = S[bar.container].points[1]
        return p[1] .. " " .. tostring(p[3]) .. " " .. (p[4] and ("%g"):format(p[4]) or "0")
    end
    local function Heard() return tostring(S[B.driver].events.UNIT_AURA == true) end
    -- Thorns on you at another druid's rank, and Nature's Grace up.
    PlayerAuras[9910], PlayerAuras[16886] = true, true

    -- Off (the default): packed as before, nothing read or heard.
    local reads = AuraReads
    Equal(On() .. " | " .. Showing() .. " | " .. Packed() .. " | " .. (AuraReads - reads) .. " " .. Heard() .. " "
        .. tostring(B:OnlyWhenMissing("buff", "Thorns")), "g1 g2 g3 g4 |  | CENTER CENTER 0 | 0 false false",
        "off at first: packed as before, nothing read, your buffs not heard")
    Equal(tostring(B:SetOnlyWhenMissing("debuff", "Thorns", true)) .. " " .. tostring(B:SetOnlyWhenMissing("buff", "Wrath", true)),
        "false false", "not on the Debuffs bar, nor for a spell not on the Buffs bar")

    -- Thorns ticked, on you: it has no spot and its packed icon goes; the
    -- rest packed as before. Only Thorns is read; your buffs are heard.
    local asked, get = {}, C_UnitAuras.GetPlayerAuraBySpellID
    C_UnitAuras.GetPlayerAuraBySpellID = function(id)
        asked[id] = true
        return get(id)
    end
    Equal(tostring(B:SetOnlyWhenMissing("buff", "Thorns", true)) .. " " .. tostring(B:OnlyWhenMissing("buff", "Thorns")) .. " "
        .. tostring(ns.OnlyWhenMissing("buff").Thorns), "true true true", "ticked for Thorns, kept in the profile")
    C_UnitAuras.GetPlayerAuraBySpellID = get
    local others = asked[16870] or asked[16886] or asked[1308663]
    Equal(On() .. " | " .. Showing() .. " | " .. Packed() .. " | " .. Heard() .. " " .. tostring(asked[9910] == true) .. " "
        .. tostring(others == true), "g2 g3 g4 |  | CENTER CENTER 0 | true true false",
        "Thorns on you: no spot, its packed icon off, the rest packed as before; only Thorns read, your buffs heard")
    Equal(box.groups.g2.layout.layoutIndex .. " " .. tostring(box.groups.g2.filters.includeSpellIDs[16870]) .. " "
        .. box.groups.g4.layout.layoutIndex, "2 true 4", "the others' packed icons as they were, in your order")

    -- Thorns gone: greyed in its spot, centred as if alone, its slot on to
    -- light if cast in a fight; the packed icons just past it.
    PlayerAuras[9910] = nil
    Changed()
    local held = bar.holders[1]
    Equal(On() .. " | " .. Showing() .. " | " .. Packed() .. " | " .. tostring(S[held.icon].desaturated) .. " " .. S[held.icon].alpha
        .. " " .. tostring(box.slots.b1.filters.includeSpellIDs[467]) .. " " .. tostring(Last(box.slots.b1.button, "SetAllPoints") == held),
        "b1 g2 g3 g4 | Thorns@60 | LEFT LEFT 100 | true 0.45 true true",
        "Thorns gone: greyed in its spot in the middle, its slot on over it, the packed icons from just past it")
    B:SetOption("buff", "grow", "right")
    local right = Showing() .. " " .. Packed()
    B:SetOption("buff", "grow", "left")
    Equal(right .. " | " .. Showing() .. " " .. Packed(), "Thorns@0 LEFT LEFT 40 | Thorns@120 RIGHT RIGHT -40",
        "growing right: from the left edge, the packed icons after it; growing left: from the right edge, the packed icons before it")
    B:SetOption("buff", "grow", "centre")

    -- Two ticked and missing: side by side in your order, the packed icons
    -- past both.
    B:SetOnlyWhenMissing("buff", "Walk on Air", true)
    local two = On() .. " | " .. Showing() .. " | " .. Packed()
    B:SetOption("buff", "grow", "left")
    Equal(two .. " || " .. Showing() .. " " .. Packed(), "b1 b4 g2 g3 | Thorns@40, Walk on Air@80 | LEFT LEFT 120 || Thorns@120,"
        .. " Walk on Air@80 RIGHT RIGHT -80", "two missing: side by side, the packed icons past them; growing left, the first on the right")
    B:SetOption("buff", "grow", "centre")

    -- Bigger icons: the packed icons' container is scaled to their size, so
    -- its offset is in its own size, and a spot's numbers (its icon is in
    -- that container) are sized as the packed icons' are.
    local size = ns.BarData("buff").size
    B:SetOption("buff", "size", 45)
    Equal(Showing() .. " | " .. Packed() .. " | " .. box.scale .. " " .. held.size .. " "
        .. tostring(Last(held.slot.cooldown, "SetCountdownFont") == ns.Style:Countdown(36)) .. " " .. S[held].width,
        "Thorns@49, Walk on Air@98 | LEFT LEFT 117.6 | 1.25 36 true 45",
        "icons at 45: the spots at 45, the packed icons from past them in the container's size, the spot's numbers as theirs")
    B:SetOption("buff", "showMissing", true)
    Equal(box.scale .. " " .. held.size .. " " .. tostring(Last(held.slot.cooldown, "SetCountdownFont") == ns.Style:Countdown(45)),
        "1 45 true", "with missing ones greyed (no packed icons): the container at its own size, the numbers at 45")
    B:SetOption("buff", "showMissing", false)
    B:SetOption("buff", "size", size)
    Equal(tostring(B:MissingSpot("buff", "Thorns")) .. " " .. tostring(B:MissingSpot("buff", "Clearcasting")), "true false",
        "Glow when missing can go on Thorns's spot; Clearcasting, packed, has none")

    -- With missing ones greyed: every other buff in its spot as before, a
    -- ticked one only while it's missing, the spots showing closed up.
    B:SetOption("buff", "showMissing", true)
    local greyed = On() .. " | " .. Showing()
    PlayerAuras[467] = true
    Changed()
    Equal(greyed .. " || " .. On() .. " | " .. Showing(), "b1 b2 b3 b4 | Thorns@0, Clearcasting@40, Nature's Grace@80, Walk on Air@120"
        .. " || b2 b3 b4 | Clearcasting@20, Nature's Grace@60, Walk on Air@100",
        "missing ones greyed: every buff in its spot, Thorns too while missing; cast, it goes and the rest close up")
    -- A border round whole bars: none while a buff is ticked, as its spot
    -- comes and goes.
    local border = ns.Get("iconBorder")
    ns.Set("iconBorder", "bar")
    local ring = tostring((B:BarDecorFor("buff")))
    B:SetOnlyWhenMissing("buff", "Thorns", false)
    B:SetOnlyWhenMissing("buff", "Walk on Air", false)
    ring = ring .. " " .. tostring((B:BarDecorFor("buff"))) .. " " .. Heard()
    B:SetOnlyWhenMissing("buff", "Thorns", true)
    B:SetOnlyWhenMissing("buff", "Walk on Air", true)
    Equal(ring, "false true false", "no border round the whole bar while a buff is ticked; none ticked: as before, nothing heard")
    -- Another character's buff ticked in a shared profile (a paladin's Seal
    -- of Light, joined to Walk on Air) has no icon here, so nothing comes and
    -- goes: the border stays round the whole bar, and packed, Walk on Air's
    -- Glow when missing still has no spot to go on.
    B:SetOnlyWhenMissing("buff", "Thorns", false)
    B:SetOnlyWhenMissing("buff", "Walk on Air", false)
    local spells = ns.BarData("buff").spells
    spells[#spells + 1] = "Seal of Light"
    ns.Joins("buff")["Seal of Light"] = true
    ns.OnlyWhenMissing("buff")["Seal of Light"] = true
    B:Changed()
    local seal = tostring(ns.Spells:ForMe("Seal of Light", "buff")) .. " " .. bar.count .. " " .. tostring(next(bar.only)) .. " "
        .. tostring((B:BarDecorFor("buff"))) .. " " .. tostring(bar.decorState)
    B:SetOption("buff", "showMissing", false)
    seal = seal .. " " .. tostring(B:MissingSpot("buff", "Walk on Air"))
    B:SetOption("buff", "showMissing", true)
    B:SetAura("buff", "Seal of Light", false)
    Equal(seal .. " | " .. table.concat(spells, ",") .. " " .. tostring(ns.OnlyWhenMissing("buff")["Seal of Light"]),
        "false 4 nil true b false | Thorns,Clearcasting,Nature's Grace,Walk on Air nil",
        "another character's buff ticked: no icon here, the border kept, no glow spot for the buff joined to it; taken off, its tick goes")
    B:SetOnlyWhenMissing("buff", "Thorns", true)
    B:SetOnlyWhenMissing("buff", "Walk on Air", true)
    ns.Set("iconBorder", border)
    B:SetOption("buff", "showMissing", false)

    -- A fight: nothing read, shown, hidden, moved or told to the container.
    -- Walk on Air, missing as it starts, lights in its slot if cast; Thorns,
    -- on you, stays hidden though it drops. Both caught up as it ends.
    Equal(On() .. " | " .. Showing() .. " | " .. Packed(), "b4 g2 g3 | Walk on Air@60 | LEFT LEFT 100", "before the fight: Walk on Air missing")
    watched[bar] = true
    for _, holder in ipairs(bar.holders) do watched[holder] = true end
    Fire("PLAYER_REGEN_DISABLED")
    lockdown = true
    local calls = containerCallsInCombat
    reads = AuraReads
    PlayerAuras[467], PlayerAuras[1308663] = nil, true
    Fire("UNIT_AURA", "player")
    for _ = 1, 5 do NextFrame() end
    B:SetUnlocked(true)
    B:SetUnlocked(false)
    local toggled = S[bar].combatToggle == true
    for _, holder in ipairs(bar.holders) do toggled = toggled or S[holder].combatToggle == true end
    Equal(Heard() .. " | " .. On() .. " | " .. Showing() .. " | " .. Packed() .. " | " .. (containerCallsInCombat - calls) .. " "
        .. (AuraReads - reads) .. " " .. tostring(toggled), "false | b4 g2 g3 | Walk on Air@60 | LEFT LEFT 100 | 0 0 false",
        "in a fight: not heard, nothing read, shown, hidden, moved or switched; Walk on Air's slot stays on over its spot")
    lockdown = false
    Fire("PLAYER_REGEN_ENABLED")
    Equal(On() .. " | " .. Showing() .. " | " .. Packed() .. " | " .. Heard(), "b1 g2 g3 | Thorns@60 | LEFT LEFT 100 | true",
        "as it ends: Thorns, gone in the fight, shows; Walk on Air, cast in it, goes; heard again")
    watched[bar] = nil
    for _, holder in ipairs(bar.holders) do watched[holder] = nil end

    -- Arranging the bars: every ticked one, to place the bar by.
    B:SetUnlocked(true)
    local unlocked = On() .. " | " .. Showing() .. " | " .. Packed()
    B:SetUnlocked(false)
    Equal(unlocked .. " || " .. On() .. " | " .. Showing(), "b1 b4 g2 g3 | Thorns@40, Walk on Air@80 | LEFT LEFT 120 || b1 g2 g3 | Thorns@60",
        "unlocked: both ticked ones, the packed icons past them; locked: only the missing one")

    -- /ccm debug says which are ticked and what each was last read as.
    SlashCmdList.FECM("debug")
    local report = S[FECMDebugFrame.edit].text
    FECMDebugFrame:Hide()
    Equal(tostring(report:find("1. Thorns | spells [%d,]+ | only when missing | on you false\n  2. Clearcasting | spells 16870\n") ~= nil),
        "true", "the debug report says which are ticked, and what each was last read as")

    -- With Only show missing (every buff), the ticks have nothing to add.
    B:SetOption("buff", "onlyMissing", true)
    Equal(tostring(ns.BuffBar:Flagged("buff", ns.BarData("buff"))) .. " " .. tostring(next(bar.only)) .. " | " .. On() .. " | " .. Showing(),
        "false nil | b1 b2 | Thorns@40, Clearcasting@80", "with Only show missing: every buff only while missing, the ticks aside")
    B:SetOption("buff", "onlyMissing", false)

    -- Kept in a copy of the profile, on its own there; a buff taken off the
    -- bar loses its tick; a reload repairs what's kept.
    local own = ns.ProfileName()
    ns.CopyProfile("Raid")
    local copied = tostring(B:OnlyWhenMissing("buff", "Walk on Air"))
    B:SetOnlyWhenMissing("buff", "Walk on Air", false)
    local db = ForeverEnhancedCooldownManagerDB
    Equal(copied .. " " .. tostring(db.profiles[own].onlyWhenMissing.buff["Walk on Air"]) .. " "
        .. tostring(db.profiles.Raid.onlyWhenMissing.buff["Walk on Air"]), "true true nil",
        "a copy keeps the ticks, each profile its own after")
    ns.UseProfile(own)
    B:SetAura("buff", "Thorns", false)
    B:SetAura("buff", "Thorns", true)
    Equal(tostring(B:OnlyWhenMissing("buff", "Thorns")) .. " " .. tostring(B:OnlyWhenMissing("buff", "Walk on Air")), "false true",
        "Thorns taken off and put back: no longer ticked; Walk on Air still is")
    local store = db.profiles[own].onlyWhenMissing
    store.buff.Wrath, store.buff.Clearcasting, store.debuff, store.cd = true, "yes", { Moonfire = true }, { Thorns = true }
    Fresh()
    ns = Load(db)
    B = ns.Bars
    store = db.profiles[own].onlyWhenMissing
    Equal(tostring(B:OnlyWhenMissing("buff", "Walk on Air")) .. " " .. tostring(store.buff.Wrath) .. " " .. tostring(store.buff.Clearcasting)
        .. " " .. tostring(store.debuff) .. " " .. tostring(store.cd) .. " " .. tostring(S[B.driver].events.UNIT_AURA == true),
        "true nil nil nil nil true",
        "after a reload: Walk on Air still ticked; a name not on the bar, anything but true and other bars dropped; heard")
    Equal(#printed, 0, "no errors")
end)()

-- One icon per Curse, Bane or Sting (1.8.1, a player's idea): only one of
-- each family can be yours on a target, so on the Debuffs bar ones side by
-- side are one icon, and one added goes beside its family, on by default;
-- nothing in the lists changes, so it can be unticked any time. A
-- right-click on the bar's page picks the one shown, faded, while none is up.
;(function()
    -- A warlock who knows these curses and banes, and Corruption.
    local WARLOCK = { { "Curse of Weakness", 702 }, { "Curse of Tongues", 1714 }, { "Curse of Recklessness", 704 },
        { "Bane of Agony", 980 }, { "Bane of Doom", 603 }, { "Corruption", 172 } }
    local function Warlock()
        Fresh()
        for _, spell in ipairs(WARLOCK) do
            table.insert(book[2].items, { name = spell[1], subName = "Rank 1", spellID = spell[2], iconID = spell[2] })
        end
        _G.UnitClass = function() return "Warlock", "WARLOCK" end
    end
    local class = _G.UnitClass
    Warlock()
    local ns = Load({ useBars = true, notesSeen = "dev", helpSeen = true })
    local B, db = ns.Bars, ForeverEnhancedCooldownManagerDB
    local function List() return table.concat(ns.BarData("debuff").spells, ",") end
    local function Joins()
        local out = {}
        for i, name in ipairs(ns.BarData("debuff").spells) do
            if B:Joined("debuff", i) then out[#out + 1] = name end
        end
        return table.concat(out, ",")
    end
    Equal(tostring(ns.Get("groupFamilies")), "true", "on by default")
    for _, name in ipairs({ "Curse of Weakness", "Corruption", "Bane of Agony", "Curse of Tongues", "Bane of Doom" }) do
        B:SetAura("debuff", name, true)
    end
    Equal(List() .. " | " .. Joins() .. " | " .. B:Get("debuff").count .. " | " .. tostring(next(ns.Joins("debuff"))),
        "Curse of Weakness,Curse of Tongues,Corruption,Bane of Agony,Bane of Doom | Curse of Tongues,Bane of Doom | 3 | nil",
        "each added beside its family, one icon with it: the Curses one, the Banes one, Corruption its own; no join saved")
    local exhaustion, weakness, pinned = B:Family("Curse of Exhaustion"), B:Family("Curse of Weakness@2"), B:Family("Curse of Weakness#702")
    Equal(tostring(exhaustion and exhaustion.key) .. " " .. tostring(weakness and weakness.key) .. " " .. tostring(pinned and pinned.key)
        .. " " .. tostring(B:Family("Corruption")), "curses curses curses nil",
        "by the spell's name at a rank or ID too; Curse of Exhaustion one of them")
    -- The join button can't split a family while ticked, and says why.
    local split, why = B:SetJoined("debuff", 2, false)
    Equal(tostring(split) .. " " .. tostring(why) .. " | " .. Joins(), "false " .. B.FAMILY_TIED .. " | Curse of Tongues,Bane of Doom",
        "the join button: no split, and why")

    -- A Judgement is one family too; a Seal is the Buffs bar's, not this one's.
    local judgement, seal, aspect = B:Family("Judgement of Light"), B:Family("Seal of Command"), B:Family("Aspect of the Hawk")
    Equal(tostring(judgement and judgement.bar) .. " " .. tostring(seal and seal.bar) .. " " .. tostring(aspect and aspect.key) .. " "
        .. tostring(B:Kindred("debuff", "Seal of Light", "Seal of Wisdom")) .. " " .. tostring(B:Kindred("buff", "Seal of Light",
        "Seal of Wisdom")) .. " " .. tostring(B:Kindred("buff", "Curse of Weakness", "Curse of Tongues")),
        "debuff buff aspects false true false", "Judgements on Debuffs; Seals, Auras and Aspects on Buffs, one icon there only")
    for _, name in ipairs({ "Seal of Light", "Blessing of Might", "Seal of Wisdom" }) do B:SetAura("buff", name, true) end
    Equal(table.concat(ns.BarData("buff").spells, ",") .. " | " .. tostring(B:Joined("buff", 2)) .. " " .. tostring(B:Joined("buff", 3)),
        "Seal of Light,Seal of Wisdom,Blessing of Might | true false", "on Buffs: a Seal added goes beside the other, one icon")
    for _, name in ipairs({ "Seal of Light", "Blessing of Might", "Seal of Wisdom" }) do B:SetAura("buff", name, false) end

    -- Unticked: each its own icon where it is, and a new one at the end.
    B:SetFamilies(false)
    B:SetAura("debuff", "Curse of Recklessness", true)
    Equal(List() .. " | " .. Joins() .. " | " .. B:Get("debuff").count, "Curse of Weakness,Curse of Tongues,Corruption,Bane of Agony,"
        .. "Bane of Doom,Curse of Recklessness |  | 6", "unticked: each its own icon, in place, a new one at the end")
    -- Ticked again: side by side ones are one icon; one apart stays apart
    -- until moved beside them.
    B:SetFamilies(true)
    Equal(List() .. " | " .. Joins(), "Curse of Weakness,Curse of Tongues,Corruption,Bane of Agony,Bane of Doom,Curse of Recklessness"
        .. " | Curse of Tongues,Bane of Doom", "ticked again: the ones side by side one icon, Curse of Recklessness apart")
    B:MoveTo("debuff", 6, 3)
    Equal(List() .. " | " .. Joins() .. " | " .. B:Get("debuff").count, "Curse of Weakness,Curse of Tongues,Curse of Recklessness,"
        .. "Corruption,Bane of Agony,Bane of Doom | Curse of Tongues,Curse of Recklessness,Bane of Doom | 3", "moved beside them: joined")

    -- A full bar: one more of a family still fits (it shares the icon), any
    -- other spell doesn't, and unticking (more icons than fit) is refused.
    local slots = ns.BUFF_SLOTS
    ns.BUFF_SLOTS = 3
    local idiocy, corruption = B:SetAura("debuff", "Curse of Idiocy", true), B:SetAura("debuff", "Immolate", true)
    local untick, room = B:SetFamilies(false)
    Equal(tostring(idiocy) .. " " .. tostring(corruption) .. " | " .. List() .. " | " .. tostring(untick) .. " " .. tostring(room)
        .. " " .. tostring(ns.Get("groupFamilies")), "true false | Curse of Weakness,Curse of Tongues,Curse of Recklessness,"
        .. "Curse of Idiocy,Corruption,Bane of Agony,Bane of Doom | false Debuffs has no room to split them: take a spell or two off"
        .. " it first. true", "full: a curse fits beside its family, Immolate doesn't, and unticking says why")
    ns.BUFF_SLOTS = slots
    B:SetAura("debuff", "Curse of Idiocy", false)

    -- The faded icon: the first of the group, or the one picked.
    B:SetOption("debuff", "showNames", true)
    local bar = B:Get("debuff")
    Equal(S[bar.holders[1].label].text, "Curse of Weakness +2", "the first's icon and name while none is up")
    Equal(tostring(B:PickMissing("debuff", 3)) .. " " .. tostring(B:Picked("debuff", 3)) .. " " .. S[bar.holders[1].label].text,
        "true true Curse of Recklessness +2", "Curse of Recklessness picked: its icon and name instead")
    B:PickMissing("debuff", 2)
    Equal(tostring(B:Picked("debuff", 3)) .. " " .. tostring(B:Picked("debuff", 2)) .. " " .. S[bar.holders[1].label].text,
        "false true Curse of Tongues +2", "another picked: only one at a time")
    B:PickMissing("debuff", 2)
    Equal(tostring(B:Picked("debuff", 2)) .. " " .. S[bar.holders[1].label].text .. " " .. tostring(B:PickMissing("debuff", 4)),
        "false Curse of Weakness +2 false", "picked again: unpicked, the first again; an icon on its own has nothing to pick")
    -- Two picked in one icon (after a move): the first counts, one dot.
    B:PickMissing("debuff", 3)
    ns.MissingPicks("debuff")["Curse of Tongues"] = true
    B:Changed()
    Equal(tostring(B:Picked("debuff", 2)) .. " " .. tostring(B:Picked("debuff", 3)) .. " " .. S[bar.holders[1].label].text,
        "true false Curse of Tongues +2", "two picked in one icon: the first is the one")
    ns.MissingPicks("debuff")["Curse of Tongues"] = nil
    B:Changed()

    -- Kept over a reload, and in a copy of the profile; a new profile's
    -- curses side by side are one icon too (the option is everyone's).
    local saved = db
    Warlock()
    ns = Load(saved)
    B = ns.Bars
    Equal(Joins() .. " | " .. tostring(B:Picked("debuff", 3)), "Curse of Tongues,Curse of Recklessness,Bane of Doom | true",
        "after a reload: one icon each, the pick kept")
    ns.CopyProfile("Raid")
    Equal(tostring(ns.ProfileName()) .. " " .. tostring(B:Picked("debuff", 3)) .. " | " .. Joins(),
        "Raid true | Curse of Tongues,Curse of Recklessness,Bane of Doom", "a copy keeps the pick")
    ns.NewProfile("Fresh")
    B:SetAura("debuff", "Curse of Tongues", true)
    B:SetAura("debuff", "Immolate", true)
    B:SetAura("debuff", "Curse of Weakness", true)
    Equal(List() .. " | " .. Joins(), "Curse of Tongues,Curse of Weakness,Immolate | Curse of Weakness",
        "a new profile: a curse added goes beside the other, one icon")
    Equal(#printed, 0, "no errors")
    _G.UnitClass = class
end)()

-- Glow when missing (1.8.1, a player's idea: a Seal that fell off): a buff
-- on the Buffs bar ticked to glow shows the Look page's glow on its greyed
-- spot, kept inside it (clipped) and under the game's icon, which covers it
-- while the buff is on you; the addon never reads whether it is.
;(function()
    Fresh()
    local ns = Load({ useBars = true, notesSeen = "dev", helpSeen = true })
    local B = ns.Bars
    B:SetAura("buff", "Thorns", true)
    B:SetOption("buff", "showMissing", true)
    local bar = B:Get("buff")
    local holder = bar.holders[1]
    Equal(tostring(holder.glowHost) .. " " .. tostring(B:GlowsMissing("buff", "Thorns")), "nil false", "off at first: no glow made")
    Equal(tostring(B:SetGlowMissing("buff", "Thorns", true)) .. " " .. tostring(B:SetGlowMissing("debuff", "Thorns", true)) .. " "
        .. tostring(B:SetGlowMissing("buff", "Wrath", true)), "true false false",
        "ticked for a buff on the Buffs bar; not the Debuffs bar, nor a spell not on the bar")
    local host = holder.glowHost
    Equal(tostring(host ~= nil and S[host.glow].shown) .. " " .. tostring(Last(host, "SetClipsChildren")) .. " "
        .. tostring(S[host].parent == holder) .. " " .. tostring(Last(host, "SetFrameLevel")) .. " "
        .. tostring(bar.container and Last(bar.container, "SetFrameLevel")),
        "true true true nil 6", "its spot glows, the glow clipped to the spot, at the spot's own level: under the game's icons"
        .. " (their container 5 above the bar)")
    B:SetGlowMissing("buff", "Thorns", false)
    Equal(tostring(S[host.glow].shown), "false", "unticked: no glow")
    B:SetGlowMissing("buff", "Thorns", true)
    -- Kept over a reload; a name taken off the bar goes from the list too.
    local saved = ForeverEnhancedCooldownManagerDB
    Fresh()
    ns = Load(saved)
    B = ns.Bars
    Equal(tostring(B:GlowsMissing("buff", "Thorns")) .. " " .. tostring(B:Get("buff").holders[1].glowHost ~= nil),
        "true true", "after a reload: still glows")
    B:SetAura("buff", "Thorns", false)
    Fresh()
    ns = Load(saved)
    Equal(tostring(ns.GlowMissing("buff").Thorns), "nil", "taken off the bar: no longer kept")
    Equal(#printed, 0, "no errors")
end)()

-- Count ticks (1.8.1, a player's idea: Bane of Agony's ticks): each Debuffs
-- bar icon asks the game to draw its aura's time so far over its debuff's
-- pace, rounded down, at its top left, as the addon can't read it in a
-- fight. Hidden until ticked for its debuff; the pace is set out of combat.
;(function()
    local util, enum = _G.C_StringUtil, { _G.Enum.NumericRuleFormatRounding, _G.Enum.DurationTextBindingProperty }
    local function Game()
        _G.C_StringUtil = { CreateNumericRuleFormatter = function()
            return { rules = {}, AddBreakpoint = function(self, rule) table.insert(self.rules, rule) end,
                ClearBreakpoints = function(self) self.rules = {} end }
        end }
        _G.Enum.NumericRuleFormatRounding, _G.Enum.DurationTextBindingProperty = { Up = 1, Down = 2 }, { ElapsedDuration = 2 }
    end
    -- What slot i's icon (fixed) and group i's (packed) show: "hidden", or
    -- "every N" seconds.
    local function Shows(bar, i)
        local out = {}
        local ticks = { bar.holders[i].slot and bar.holders[i].slot.ticks, (bar.groupTicks[i] or {})[1] }
        for n = 1, 2 do
            local t = ticks[n]
            local rules = t and t.formatter.rules
            out[n] = not t and "none" or not S[t.frame].shown and "hidden" or ("every " .. tostring(rules[#rules].components[1].div)
                .. (#rules == 1 and "" or " (" .. #rules .. " rules)"))
        end
        return table.concat(out, " / ")
    end
    -- Without the game's number rules (an older build): nothing asked, no errors.
    Fresh()
    local ns = Load({ useBars = true, notesSeen = "dev", helpSeen = true })
    local B = ns.Bars
    B:SetAura("debuff", "Moonfire", true)
    Equal(tostring(S[B:Get("debuff").container].slots.b1.supplied.SetDurationText) .. " " .. tostring(B:Get("debuff").holders[1].slot.ticks),
        "nil nil", "no number rules in the game: no count asked for")
    Fresh()
    Game()
    ns = Load({ useBars = true, notesSeen = "dev", helpSeen = true })
    B = ns.Bars
    local bar = B:Get("debuff")
    local slot = S[bar.container].slots.b1
    local options = slot.supplied.durationTextOptions
    local component = options and options.textFormat.components[1]
    Equal(table.concat({ tostring(slot.supplied.SetDurationText ~= nil), tostring(S[B:Get("buff").container].slots.b1.supplied.SetDurationText),
        tostring(options and options.textFormat.formatString), tostring(component and component.property),
        tostring((S[slot.supplied.SetDurationText].points[1] or {})[1]), tostring(S[bar.holders[1].slot.ticks.frame].shown) }, " "),
        "true nil {} 2 TOPLEFT false", "each Debuffs bar icon asks for its time so far (not the Buffs bar's), at its top left, hidden")
    -- Ticked for a debuff on the bar that ticks; not for the Buffs bar, a
    -- spell not on the bar, nor one that doesn't tick.
    B:SetAura("debuff", "Moonfire", true)
    B:SetAura("debuff", "Wrath", true)
    Equal(Shows(bar, 1), "hidden / hidden", "packed (the default): the group's icon made, still hidden")
    B:SetAura("buff", "Moonfire", true)
    Equal(table.concat({ tostring(B:SetCountTicks("debuff", "Moonfire", true)), tostring(B:SetCountTicks("buff", "Moonfire", true)),
        tostring(B:SetCountTicks("debuff", "Corruption", true)), tostring(B:SetCountTicks("debuff", "Wrath", true)) }, " "),
        "true false false false", "ticked for Moonfire on the Debuffs bar only; not on the Buffs bar (it's on there too), nor"
        .. " Corruption (it ticks, but isn't on the bar), nor Wrath (no ticks)")
    B:SetAura("buff", "Moonfire", false)
    -- Paces from the game's data: one that ticks once, as it ends, isn't
    -- offered (its count would read 0 throughout); a trap kept under its old
    -- name still is.
    Equal(tostring(B:TickPace("Bane of Agony")) .. " " .. tostring(B:TickPace("Bane of Doom")) .. " "
        .. tostring(B:TickPace("Immolation Trap Effect")) .. " " .. tostring(B:TickPace("Rupture@3")), "2 nil 3 2",
        "Agony every 2 s; not Bane of Doom; the trap by its old name; a fixed rank by its spell's")
    Equal(Shows(bar, 1) .. " | " .. Shows(bar, 2), "every 3 / every 3 | hidden / hidden",
        "Moonfire's icon counts every 3 seconds, its pace in the game's data, fixed and packed; Wrath's doesn't")
    -- Fixed spots (Show missing ... greyed): the same.
    B:SetOption("debuff", "showMissing", true)
    Equal(Shows(bar, 1), "every 3 / every 3", "fixed spots count too, one rule each (the old one cleared)")
    -- Taken off and put back: it starts afresh, unticked, as after a reload;
    -- ticked again, the count follows it to its new place, after Wrath.
    B:SetAura("debuff", "Moonfire", false)
    B:SetAura("debuff", "Moonfire", true)
    Equal(tostring(B:CountsTicks("debuff", "Moonfire")) .. " | " .. Shows(bar, 1) .. " | " .. Shows(bar, 2),
        "false | hidden / hidden | hidden / hidden", "taken off and put back: unticked, as after a reload")
    B:SetCountTicks("debuff", "Moonfire", true)
    Equal(Shows(bar, 1) .. " | " .. Shows(bar, 2), "hidden / hidden | every 3 / every 3", "ticked again: counting in its new place")
    -- In a fight, the change waits for it to end (the icons are the game's).
    lockdown = true
    B:SetCountTicks("debuff", "Moonfire", false)
    Equal(Shows(bar, 2), "every 3 / every 3", "unticked in a fight: still counting until it ends")
    lockdown = false
    Fire("PLAYER_REGEN_ENABLED")
    Equal(Shows(bar, 2), "hidden / hidden", "the fight over: hidden")
    B:SetCountTicks("debuff", "Moonfire", true)
    -- Joined into one icon with Wrath, which doesn't tick: the game shows
    -- whichever is up and the addon can't tell which in a fight, so that
    -- icon can't count; the Debuffs page says why (B:TickClash).
    B:SetJoined("debuff", 2, true)
    Equal(Shows(bar, 1) .. " | " .. tostring(B:TickClash("debuff", "Moonfire")) .. " " .. tostring(B:TickClash("debuff", "Wrath")),
        "hidden / hidden | Wrath nil", "joined with Wrath (no ticks; this game has no colour curves to tell them apart): hidden,"
        .. " and Moonfire's row names Wrath (Wrath's has no Count ticks)")
    B:SetJoined("debuff", 2, false)
    Equal(Shows(bar, 2) .. " | " .. tostring(B:TickClash("debuff", "Moonfire")), "every 3 / every 3 | nil", "apart again: counting")
    -- Its count is smaller than the stack count, tucked in the corner, clear
    -- of the countdown.
    Equal(tostring(Last(bar.holders[2].slot.ticks.text, "SetFontObject")) .. " " .. tostring(Last(bar.holders[2].slot.count, "SetFontObject")),
        ns.Style:Ticks(bar.holders[2].size) .. " " .. ns.Style:Count(bar.holders[2].size), "the tick count's own smaller font")
    Equal(ns.Style:Ticks(36) .. " " .. ns.Style:Ticks(20), "FECMFont10 FECMFont8", "10 at 36, 8 at the smallest icons")
    -- From 1 by default, like stacks (a player's ask: Bane of Agony): rounded
    -- up, the time taken as at least a moment so it never reads 0 as it
    -- lands; from 0, rounded down, the old rule cleared each time.
    local ticks = bar.holders[2].slot.ticks
    local function Rule()
        local rules = ticks.formatter.rules
        local rule = rules[#rules]
        return rule.components[1].rounding .. " " .. tostring(rule.min) .. " " .. #rules
    end
    Equal(Rule(), "1 0.01 1", "from 1: rounded up, never 0 as it lands")
    B:SetOption("debuff", "tickFrom", 0)
    Equal(Rule(), "2 nil 1", "from 0: rounded down")
    B:SetOption("debuff", "tickFrom", 1)
    -- Where it sits, its size and colour: the Debuffs page's, on fixed spots
    -- and packed icons alike (the packed one at its drawn size, then scaled).
    B:SetOption("debuff", "tickAt", "BOTTOMRIGHT")
    B:SetOption("debuff", "tickColour", "gold")
    B:SetOption("debuff", "tickSize", 200)
    local function Look(t, size)
        local point = S[t.text].points[1] or {}
        return table.concat({ tostring(point[1]), tostring(point[2]), tostring(point[3]), tostring(Last(t.text, "SetJustifyH")),
            tostring((S[t.text].colour or {})[1]), tostring((S[t.text].colour or {})[2]),
            tostring(Last(t.text, "SetFontObject") == ns.Style:Ticks(size, 200)) }, " ")
    end
    Equal(Look(ticks, bar.holders[2].size) .. " | " .. Look(bar.groupTicks[2][1], 36),
        "BOTTOMRIGHT -1 1 RIGHT 1 0.82 true | BOTTOMRIGHT -1 1 RIGHT 1 0.82 true",
        "bottom right, gold, twice the size: on the fixed spot and the packed icon")
    B:SetOption("debuff", "tickAt", "CENTER")
    Equal(tostring((S[ticks.text].points[1] or {})[1]) .. " " .. tostring(#S[ticks.text].points) .. " " .. tostring(Last(ticks.text, "SetJustifyH")),
        "CENTER 1 CENTER", "the centre: one point, moved, not added")
    B:SetOption("debuff", "tickAt", "TOP")
    local top = S[ticks.text].points[1] or {}
    Equal(tostring(top[1]) .. " " .. tostring(top[2]) .. " " .. tostring(top[3]) .. " " .. tostring(Last(ticks.text, "SetJustifyH")),
        "TOP 0 -1 CENTER", "top centre (a player's pick): tucked a pixel in from the top")
    -- On the edge (the same player): centred on the border at its spot,
    -- half outside; the centre stays the centre.
    B:SetOption("debuff", "tickEdge", true)
    top = S[ticks.text].points[1] or {}
    Equal(tostring(top[1]) .. " " .. tostring(top[2] == ticks.frame) .. " " .. tostring(top[3]) .. " " .. tostring(top[4]) .. " "
        .. tostring(top[5]) .. " " .. tostring(#S[ticks.text].points), "CENTER true TOP 0 0 1", "on the edge: centred on the top border")
    B:SetOption("debuff", "tickAt", "TOPRIGHT")
    top = S[ticks.text].points[1] or {}
    Equal(tostring(top[1]) .. " " .. tostring(top[3]), "CENTER TOPRIGHT", "a corner: centred on the corner")
    B:SetOption("debuff", "tickAt", "CENTER")
    top = S[ticks.text].points[1] or {}
    Equal(tostring(top[1]) .. " " .. tostring(top[2]) .. " " .. tostring(top[3]), "CENTER 0 0", "the centre: as before")
    -- Custom (the colour pop-up): its own colour, kept beside it; a new one
    -- drawn at once, as a named one is.
    ns.BarData("debuff").tickCustom = "336699"
    B:SetOption("debuff", "tickColour", ns.CUSTOM)
    local custom = ("%.1f,%.1f,%.1f"):format(S[ticks.text].colour[1], S[ticks.text].colour[2], S[ticks.text].colour[3])
    ns.BarData("debuff").tickCustom = "ff0000"
    B:SetOption("debuff", "tickColour", ns.CUSTOM)
    Equal(custom .. " " .. ("%.1f,%.1f,%.1f"):format(S[ticks.text].colour[1], S[ticks.text].colour[2], S[ticks.text].colour[3])
        .. " " .. ("%.1f"):format(S[bar.groupTicks[2][1].text].colour[1]), "0.2,0.4,0.6 1.0,0.0,0.0 1.0",
        "a custom colour on the count, a new one at once, on packed icons too")
    for field, value in pairs({ tickAt = "TOPLEFT", tickColour = "white", tickSize = 100, tickEdge = false, tickCustom = "" }) do
        B:SetOption("debuff", field, value)
    end
    -- Kept over a reload; a name taken off the bar goes from the list too.
    local saved = ForeverEnhancedCooldownManagerDB
    Fresh()
    Game()
    ns = Load(saved)
    B = ns.Bars
    Equal(tostring(B:CountsTicks("debuff", "Moonfire")) .. " " .. Shows(B:Get("debuff"), 2), "true every 3 / none",
        "after a reload: still counting (fixed spots, so no packed groups made)")
    local own = ns.ProfileName()
    ns.CopyProfile("Raid")
    Equal(tostring(ns.ProfileName()) .. " " .. tostring(B:CountsTicks("debuff", "Moonfire")), "Raid true", "a copy of the profile counts too")
    ns.UseProfile(own)
    B:SetAura("debuff", "Moonfire", false)
    Fresh()
    Game()
    ns = Load(saved)
    Equal(tostring(ns.CountTicks("debuff").Moonfire), "nil", "taken off the bar: no longer kept")
    -- The old test's settings (/ccm ticks) go, and the command with them.
    saved.devTickTest, saved.devTickProbe, saved.devTickPace = true, {}, {}
    Fresh()
    Game()
    ns = Load(saved)
    Equal(tostring(saved.devTickTest) .. " " .. tostring(saved.devTickProbe) .. " " .. tostring(saved.devTickPace) .. " "
        .. tostring(ns.ToggleTickTest), "nil nil nil nil", "the old test's settings cleared")
    _G.C_StringUtil, _G.Enum.NumericRuleFormatRounding, _G.Enum.DurationTextBindingProperty = util, enum[1], enum[2]
    Equal(#printed, 0, "no errors")
end)()

-- Count ticks in a joined icon (a player's case: Bane of Doom beside Agony):
-- with the game's colour curves, the count runs at the counted debuff's pace
-- and goes see-through for the others, told apart by how long each lasts;
-- two as long, or a length not known, can't be told apart. And Glow when
-- missing on the Debuffs bar (the same player as the Buffs bar's), only
-- with an enemy targeted.
;(function()
    local before = { _G.C_StringUtil, _G.C_CurveUtil, _G.Enum.NumericRuleFormatRounding, _G.Enum.DurationTextBindingProperty }
    Fresh()
    _G.C_StringUtil = { CreateNumericRuleFormatter = function()
        return { rules = {}, AddBreakpoint = function(self, rule) table.insert(self.rules, rule) end,
            ClearBreakpoints = function(self) self.rules = {} end }
    end }
    _G.C_CurveUtil = { CreateColorCurve = function()
        return { points = {}, AddPoint = function(self, x, c) table.insert(self.points, { x, c }) end,
            ClearPoints = function(self) self.points = {} end }
    end }
    _G.Enum.NumericRuleFormatRounding, _G.Enum.DurationTextBindingProperty = { Up = 1, Down = 2 }, { ElapsedDuration = 2, TotalDuration = 4 }
    local ns = Load({ useBars = true, notesSeen = "dev", helpSeen = true })
    local B = ns.Bars
    local bar = B:Get("debuff")
    local options = S[bar.container].slots.b1.supplied.durationTextOptions
    local color = options and options.textColor
    Equal(tostring(color and color.property) .. " " .. tostring(color ~= nil and color.curve == bar.holders[1].slot.ticks.curve), "4 true",
        "each count coloured by a curve on how long its aura lasts")
    B:SetAura("debuff", "Moonfire", true)
    B:SetAura("debuff", "Wrath", true)
    B:SetOption("debuff", "showMissing", true)
    B:SetCountTicks("debuff", "Moonfire", true)
    B:SetJoined("debuff", 2, true)
    ns.DEBUFF_LASTS.Wrath = { 30 } -- Wrath as a debuff lasting 30 s
    B:Changed()
    local ticks = bar.holders[1].slot.ticks
    local function Curve()
        local out = {}
        for _, point in ipairs(ticks.curve.points) do out[#out + 1] = point[1] .. "=" .. point[2].a end
        return table.concat(out, " ")
    end
    Equal(tostring(S[ticks.frame].shown) .. " | " .. Curve() .. " | " .. tostring(B:TickClash("debuff", "Moonfire")),
        "true | 0=1 20.99=1 21.01=0 100000=0 | nil",
        "joined with Wrath (30 s): counting, see-through from half way between Moonfire's 12 s and Wrath's 30")
    ns.DEBUFF_LASTS.Wrath = { 12 }
    B:Changed()
    Equal(tostring(S[ticks.frame].shown) .. " " .. tostring(B:TickClash("debuff", "Moonfire")), "false Wrath",
        "as long as Moonfire's: can't be told apart, hidden, and the row says why")
    ns.DEBUFF_LASTS.Wrath = nil
    B:Changed()
    Equal(tostring(S[ticks.frame].shown) .. " " .. tostring(B:TickClash("debuff", "Moonfire")), "false Wrath", "a length not known: the same")
    -- Two ticked at different paces (a review's case: Serpent then Viper
    -- Sting): the later one's row names the earlier, whichever is asked.
    ns.TICK_PERIODS.Wrath, ns.DEBUFF_LASTS.Wrath = 2, { 30 }
    Equal(tostring(B:TickClash("debuff", "Wrath")) .. " " .. tostring(B:TickClash("debuff", "Moonfire")), "Moonfire nil",
        "Moonfire counted: Wrath's row (second, another pace) names Moonfire; Moonfire's own row is fine")
    ns.TICK_PERIODS.Wrath = nil
    -- The one in the way is the one as long as a counted one, not just the
    -- first other (a review's case: Curses of Tongues, Weakness, Idiocy).
    ns.DEBUFF_LASTS.Thorns = { 12 }
    Equal(select(3, B:IconTicks({ "Wrath", "Thorns", "Moonfire" }, { Moonfire = true })), "Thorns",
        "as long as Moonfire: Thorns is named, not Wrath")
    ns.DEBUFF_LASTS.Thorns, ns.DEBUFF_LASTS.Wrath = nil, nil
    -- Rupture's lengths with each combo point (a review's case).
    Equal(table.concat(ns.DEBUFF_LASTS.Rupture, ","), "6,8,10,12,14,16", "Rupture lasts 6 to 16 s with combo points")
    B:SetJoined("debuff", 2, false)
    Equal(tostring(S[ticks.frame].shown) .. " " .. Curve(), "true 0=1 100000=1", "apart again: counting, its colour throughout")
    -- Glow when missing on the Debuffs bar: only with an enemy targeted.
    Equal(tostring(B:SetGlowMissing("debuff", "Moonfire", true)) .. " " .. tostring(B:GlowsMissing("debuff", "Moonfire")), "true true",
        "ticked for a debuff on the Debuffs bar")
    local host = bar.holders[1].glowHost
    target, hostile = false, false
    Fire("PLAYER_TARGET_CHANGED")
    local none = host and S[host].alpha
    target, hostile = true, true
    Fire("PLAYER_TARGET_CHANGED")
    Equal(tostring(host ~= nil) .. " " .. tostring(none) .. " " .. tostring(host and S[host].alpha) .. " "
        .. tostring(host and S[host.glow].shown), "true 0 1 true", "its spot glows only with an enemy targeted")
    B:SetOption("debuff", "greyedNoTarget", true)
    target, hostile = false, false
    Fire("PLAYER_TARGET_CHANGED")
    Equal(tostring(S[host].alpha) .. " " .. tostring(S[bar.holders[1].icon].alpha), "0 0.45",
        "kept greyed with no target: the spot stays greyed, but no glow with nothing to put it on")
    -- Not on a corpse (a review's case): your target dying puts it out.
    target, hostile = true, true
    Fire("PLAYER_TARGET_CHANGED")
    local dead = _G.UnitIsDeadOrGhost
    _G.UnitIsDeadOrGhost = function(unit) return unit == "target" end
    Fire("UNIT_FLAGS", "target")
    local corpse = S[host].alpha
    _G.UnitIsDeadOrGhost = dead
    Equal(tostring(corpse) .. " " .. tostring(S[B.driver].events.UNIT_FLAGS), "0 true", "your target dead: no glow (heard as it dies)")
    _G.C_StringUtil, _G.C_CurveUtil, _G.Enum.NumericRuleFormatRounding, _G.Enum.DurationTextBindingProperty =
        before[1], before[2], before[3], before[4]
    Equal(#printed, 0, "no errors")
end)()

-- Icon details on the aura containers' icons -------------------------------------------------------
-- The swipe, the edge line and the countdown's size, colour and spot reach
-- the Buffs and Debuffs bars' icons (packed and fixed) and the buff and
-- debuff times over the cooldown icons: as each is made, and after a change,
-- out of a fight only, as their borders are (a change made in one waits for
-- it to end). At the defaults their numbers stay where the game puts them.

;(function()
    Fresh()
    local ns = Load({ useBars = true, notesSeen = "dev", helpSeen = true })
    local B = ns.Bars
    B:SetAura("buff", "Thorns", true)
    B:SetAura("debuff", "Moonfire", true)
    B:Assign("Wrath", "cd")
    B:SetOption("cd", "showAuras", true)
    B:SetOption("debuff", "showMissing", true)
    B:Changed()
    local packed = B:Get("buff").groupParts[1]
    local fixed = B:Get("debuff").holders[1].slot
    local over = B:Get("cd").auraAnchors[1].parts[1]
    local own = B:Get("cd").icons[1].cooldown
    local function Looks(cooldown)
        local swipe, numbers = S[cooldown].last.SetSwipeColor, S[cooldown].numbers
        local at = numbers and S[numbers].points[1]
        return ("%g,%g,%g,%g"):format(swipe[1], swipe[2], swipe[3], swipe[4]) .. " " .. tostring(Last(cooldown, "SetDrawEdge")) .. " "
            .. tostring(Last(cooldown, "SetCountdownFont")) .. " " .. (at and (at[1] .. " " .. at[4] .. " " .. at[5]) or "game's")
    end
    local function All() return Looks(packed.cooldown) .. " | " .. Looks(fixed.cooldown) .. " | " .. Looks(over.cooldown) end
    Equal(All() .. " | " .. tostring(Last(packed.cooldown, "SetReverse")), "0,0,0,0.7 false FECMFont18 game's | 0,0,0,0.7 false FECMFont18"
        .. " game's | 0,0,0,0.7 false FECMFont18 game's | true", "at the defaults: each as it always was, its numbers where the game puts them")
    -- Changed in a fight: your own icons at once, the containers' as it ends.
    Fire("PLAYER_REGEN_DISABLED")
    lockdown = true
    for key, value in pairs({ swipeColour = "blue", swipeSeeThrough = 20, countdownSize = 50, countdownColour = "green",
        countdownSpot = "BOTTOMLEFT", swipeEdge = true, edgeColour = "orange" }) do ns.Set(key, value) end
    ns.Style:ApplyDetails()
    local fight = All() .. " || " .. Looks(own)
    lockdown = false
    Fire("PLAYER_REGEN_ENABLED")
    Equal(fight, "0,0,0,0.7 false FECMFont18 game's | 0,0,0,0.7 false FECMFont18 game's | 0,0,0,0.7 false FECMFont18 game's || 0.24,0.55,0.88,0.8"
        .. " true FECMCountdown9 BOTTOMLEFT 1 1", "in a fight: your own icons at once, the containers' icons left alone")
    Equal(All() .. " | " .. ("%g,%g,%g"):format(S[packed.cooldown].last.SetEdgeColor[1], S[packed.cooldown].last.SetEdgeColor[2],
        S[packed.cooldown].last.SetEdgeColor[3]), "0.24,0.55,0.88,0.8 true FECMCountdown9 BOTTOMLEFT 1 1 | 0.24,0.55,0.88,0.8 true"
        .. " FECMCountdown9 BOTTOMLEFT 1 1 | 0.24,0.55,0.88,0.8 true FECMCountdown9 BOTTOMLEFT 1 1 | 1,0.5,0.25",
        "as it ends: a blue swipe at 80%, the orange edge line, small green numbers in the bottom left, on each")
    -- New icons come in them too, as they're made.
    B:SetAura("debuff", "Wrath", true)
    B:Changed()
    local second = B:Get("debuff").holders[2].slot
    Equal(Looks(second.cooldown), "0.24,0.55,0.88,0.8 true FECMCountdown9 BOTTOMLEFT 1 1", "a new icon made in the details picked")
    -- Back to the defaults: each as it always was, its numbers back in the middle.
    for _, key in ipairs(ns.ICON_DETAILS) do ns.Set(key, ns.DEFAULTS[key]) end
    ns.Style:ApplyDetails()
    Equal(All(), "0,0,0,0.7 false FECMFont18 CENTER 0 0 | 0,0,0,0.7 false FECMFont18 CENTER 0 0 | 0,0,0,0.7 false FECMFont18 CENTER 0 0",
        "the defaults again: as they always were, the numbers in the middle")
    Equal(#printed, 0, "no errors")
end)()

Equal(SecretMisuse[1], nil, "no secret misused anywhere")
print = _G.print
io.write("Aura container checks passed: " .. checks .. " assertions.\n")
