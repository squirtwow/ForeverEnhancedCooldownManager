-- Run the actual addon files against a mock game for Swap with my form
-- (Core.lua, Bars.lua and the bar's page, with Forms.lua's data from the
-- game): a Cooldowns or Utility bar ticked keeps a list of its own for each
-- form, made the first time from the normal one without what that form
-- can't cast, each its own after that, and shows the one for the form you're
-- in the moment you change, in a fight too. A druid's caster, bear, dire
-- bear (bear's list), cat (prowling too), travel and moonkin forms, a
-- warrior's stances, a rogue in and out of stealth; the list it shows kept
-- when the game won't say, Normal in a form no list is for; Editing on the
-- page; hidden for a character with no form; repaired, copied and found as
-- it's saved; off, exactly as before. The mock game is a copy of
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

-- Forms: the game around it ------------------------------------------------------------------------
-- In the game a secret can't be a table's key either, but Lua has no hook on
-- the key, so the forms tables the addon looks your form up in get one here:
-- a secret looked up in one is noted (SecretMisuse) and errors, like the
-- mock game's other secrets.
local function NoSecretKeys(t, name)
    setmetatable(t, { __index = function(_, key)
        if IsSecret(key) then
            local message = "attempt to use a secret " .. type(key) .. " value as a table key"
            SecretMisuse[#SecretMisuse + 1] = "Forms.lua's " .. name .. ": " .. message
            error(message, 2)
        end
    end })
end

-- The next frame: the bars' driver runs once.
local function NextFrame(ns)
    local driver = ns.Bars.driver
    local run = driver and S[driver].scripts.OnUpdate
    if run then run(driver, 0) end
end

-- You change form (its ID, nil for none) or go in or out of stealth, as
-- the game says, and the next frame comes.
local function Shift(ns, form, stealthed, event)
    Form, Stealthed = form, stealthed or false
    Fire(event or "UPDATE_SHAPESHIFT_FORM")
    NextFrame(ns)
end

-- A character of this class with these spells in its spellbook ({ name, ID,
-- rank }), and these too (known: forms it can take, say), and a trinket
-- worn, logged in with these settings (your bars on) in no form. Each of the
-- spells then goes on the Cooldowns bar in that order, the trinket last,
-- and it takes the form given.
local function Character(class, spells, saved, form, stealthed, known)
    Environment()
    _G.UnitClass = function() return class:sub(1, 1) .. class:sub(2):lower(), class end
    local items = {}
    for _, list in ipairs({ spells, known or {} }) do
        for _, spell in ipairs(list) do
            items[#items + 1] = { name = spell[1], subName = spell[3], spellID = spell[2], iconID = 101 + #items }
        end
    end
    book = { { name = "General", items = { { name = "Attack", spellID = 6603 } } }, { name = "Class", items = items } }
    trinket = 11111
    local ns = Load(saved or { useBars = true }, true)
    NoSecretKeys(ns.FORMS, "ns.FORMS")
    NoSecretKeys(ns.FORM_LISTS, "ns.FORM_LISTS")
    Fire("PLAYER_LOGIN")
    Fire("PLAYER_ENTERING_WORLD")
    for _, spell in ipairs(spells) do ns.Bars:Assign(spell[1], "cd") end
    ns.Bars:Assign("slot:13", "cd")
    if form ~= nil or stealthed then Shift(ns, form, stealthed) end
    return ns, ns.Bars, ns.Bars:Get("cd")
end

-- Saved settings (your bars on, unless others are given) with Swap with my
-- form ticked on these bars in the profile a character of this class logs
-- in to: its own, named as a new character's is. As the bar's page saves
-- it: the tick is the profile's.
local function Ticked(class, keys, saved)
    saved = saved or { useBars = true }
    local name = ("%s (%s) - %s"):format(character.name, class:sub(1, 1) .. class:sub(2):lower(), character.realm)
    local ticks = {}
    for _, key in ipairs(keys) do ticks[key] = true end
    saved.profiles, saved.chars = { [name] = { swapForm = ticks } }, { [character.guid] = name }
    return saved
end

-- A profile's saved ticks as text: the bars ticked, in order ("cd,util"),
-- or "nil" for none saved.
local function Ticks(profile)
    local ticks = profile and profile.swapForm
    if ticks == nil then return "nil" end
    local out = {}
    for key, on in pairs(ticks) do out[#out + 1] = key .. (on == true and "" or "=" .. tostring(on)) end
    table.sort(out)
    return table.concat(out, ",")
end

-- The icons showing on a bar, in order, each with where it sits from the
-- bar's corner ("Maul 60" in the first row, "Maul 40,-40" below it). The
-- trinket is "Trinket".
local function Showing(bar)
    local out = {}
    for i = 1, bar.count do
        local icon = bar.icons[i]
        if S[icon].shown then
            local p = S[icon].points[1]
            local name = icon.name == "slot:13" and "Trinket" or icon.name
            out[#out + 1] = name .. " " .. ("%g"):format(p[4]) .. (p[5] ~= 0 and ("," .. ("%g"):format(p[5])) or "")
        end
    end
    return table.concat(out, " | ")
end

-- A bar's list in this character's profile, its entries in order ("empty",
-- or "none" for a list not made yet): its normal one, or a form's.
local function List(ns, key, form)
    local profile = ForeverEnhancedCooldownManagerDB.profiles[ns.ProfileName()]
    local list = profile[key]
    if form then list = type(profile.forms) == "table" and type(profile.forms[form]) == "table" and profile.forms[form][key] end
    if type(list) ~= "table" then return "none" end
    return #list == 0 and "empty" or table.concat(list, ",")
end

-- A druid's spells: Moonfire (no form or Moonkin), Claw (cat), Maul (bear),
-- Pounce (cat, prowling), Barkskin (any form) and Bear Form (changes form);
-- the normal list they make, and what the bar shows of it, and of bear
-- form's and cat form's lists made from it.
local DRUID = { { "Moonfire", 8924, "Rank 2" }, { "Claw", 1082, "Rank 1" }, { "Maul", 6807, "Rank 1" },
    { "Pounce", 9005, "Rank 1" }, { "Barkskin", 22812 }, { "Bear Form", 5487 } }
local NORMAL = "Moonfire,Claw,Maul,Pounce,Barkskin,Bear Form,slot:13"
local SHOWN = { all = "Moonfire 0 | Claw 40 | Maul 80 | Pounce 120 | Barkskin 160 | Bear Form 200 | Trinket 240",
    bear = "Maul 0 | Barkskin 40 | Bear Form 80 | Trinket 120", cat = "Claw 0 | Pounce 40 | Barkskin 80 | Bear Form 120 | Trinket 160" }

-- The data, from the game's own tables (Tools/TestForms.mjs checks the file is the build's) ------------

do
    Environment()
    local ns = Load({})
    Equal(ns.FORMS[1] .. ", " .. ns.FORMS[5] .. ", " .. ns.FORMS[8] .. ", " .. ns.FORMS[17] .. ", " .. ns.FORMS[30] .. ", "
        .. ns.FORMS[31] .. ", " .. tostring(ns.FORMS[0]), "Cat Form, Bear Form, Dire Bear Form, Battle Stance, Stealth, Moonkin Form, nil",
        "the forms a character can take, by the game's IDs; none isn't one")
    Equal(ns.FORM_LISTS[1] .. " " .. ns.FORM_LISTS[5] .. " " .. ns.FORM_LISTS[8] .. " " .. ns.FORM_LISTS[17] .. " " .. ns.FORM_LISTS[30]
        .. " " .. tostring(ns.FORM_LISTS[0]), "1 5 5 17 30 nil",
        "each form's list its own, but Dire Bear Form's: Bear Form's, as its spell replaces Bear Form's")
    Equal(table.concat(ns.FORM_GIVERS[5], ",") .. " | " .. table.concat(ns.FORM_GIVERS[8], ",") .. " | "
        .. table.concat(ns.FORM_GIVERS[30], ","), "5487 | 9634 | 1784,1785,1786,1787",
        "the spells that put you in each: Bear Form, Dire Bear Form, every rank of Stealth")
    local function Rule(id)
        local rule = ns.FORM_RULES[ns.FORM_SPELLS[id]]
        if not rule then return "any" end
        return table.concat(rule, ",") .. (rule.stealth and " stealthed" or "")
    end
    Equal(Rule(8924) .. " | " .. Rule(1082) .. " | " .. Rule(6807) .. " | " .. Rule(9005) .. " | " .. Rule(22812) .. " | " .. Rule(5487),
        "0,31 | 1 | 5,8 | 1 stealthed | any | any",
        "Moonfire with no form or in Moonkin, Claw in cat, Maul in bear, Pounce prowling in cat, Barkskin and Bear Form in any")
end

-- Off by default: exactly as before ---------------------------------------------------------------

do
    local ns, B, bar = Character("DRUID", DRUID, nil, 5)
    Equal(tostring(ns.Swaps("cd")) .. " " .. tostring(ns.Swaps("util")) .. " "
        .. tostring(ForeverEnhancedCooldownManagerDB.profiles[ns.ProfileName()].swapForm), "false false nil",
        "off on both cooldown bars, nothing saved for it in your profile")
    Equal(Showing(bar) .. " | " .. FormReads .. " " .. tostring(S[B.driver].events.UPDATE_SHAPESHIFT_FORM) .. " | " .. List(ns, "cd", 5),
        SHOWN.all .. " | 0 nil | none", "in bear form, the one list as always: your form never asked, its changes not heard, no form's list")
    Shift(ns, 1)
    Equal(Showing(bar) .. " | " .. FormReads, SHOWN.all .. " | 0", "nor does a change of form change anything")
    -- Ticked in bear form: its own list at once, made from the normal one.
    Shift(ns, 5)
    B:SetOption("cd", "swapForm", true)
    Equal(Showing(bar) .. " | " .. List(ns, "cd", 5) .. " | " .. List(ns, "cd"), SHOWN.bear .. " | Maul,Barkskin,Bear Form,slot:13 | " .. NORMAL,
        "ticked in bear form: bear form's own list, made from the normal one, which stays as it was")
    local db = ForeverEnhancedCooldownManagerDB
    Equal(Ticks(db.profiles[ns.ProfileName()]) .. " " .. tostring(rawget(db.bars.cd, "swapForm")), "cd nil",
        "the tick saved in your profile, beside its lists, not with the bar's settings every character shares")
    -- Unticked: the normal list, your form no longer asked or heard, and
    -- bear form's list kept for next time.
    B:SetOption("cd", "swapForm", false)
    local reads = FormReads
    Shift(ns, 1)
    Equal(Showing(bar) .. " | " .. tostring(FormReads - reads) .. " " .. tostring(S[B.driver].events.UPDATE_SHAPESHIFT_FORM) .. " | "
        .. List(ns, "cd", 5), SHOWN.all .. " | 0 nil | Maul,Barkskin,Bear Form,slot:13",
        "unticked: the normal list, your form no longer asked or heard, bear form's list kept")
    Equal(Ticks(db.profiles[ns.ProfileName()]), "nil", "and nothing left saved for the tick")
    Shift(ns, 5)
    B:SetOption("cd", "swapForm", true)
    Equal(Showing(bar), SHOWN.bear, "and ticked again: bear form's list once more")
    Equal(#printed, 0, "no errors")
end

-- A druid: each form its own list ------------------------------------------------------------------

do
    local ns, B, bar = Character("DRUID", DRUID, Ticked("DRUID", { "cd" }), nil, nil,
        { { "Cat Form", 768 }, { "Travel Form", 783 }, { "Moonkin Form", 24858 } })
    local profile = ForeverEnhancedCooldownManagerDB.profiles[ns.ProfileName()]
    Equal(Showing(bar) .. " | " .. List(ns, "cd") .. " | " .. tostring(profile.forms), SHOWN.all .. " | " .. NORMAL .. " | nil",
        "no form: the normal list, and no form's made yet")
    Equal(tostring(S[B.driver].events.UPDATE_SHAPESHIFT_FORM) .. " " .. tostring(S[B.driver].events.UPDATE_SHAPESHIFT_FORMS)
        .. " " .. tostring(S[B.driver].events.UPDATE_STEALTH), "true true true", "ticked: your form changing is heard")
    Shift(ns, 5)
    Equal(Showing(bar) .. " | " .. S[bar].width .. "x" .. S[bar].height .. " | " .. List(ns, "cd", 5) .. " | " .. List(ns, "cd"),
        SHOWN.bear .. " | 156x36 | Maul,Barkskin,Bear Form,slot:13 | " .. NORMAL,
        "bear form, at once: its own list, made the first time from the normal one without what a bear can't cast"
            .. " (Moonfire, Claw, Pounce); the normal list as it was")
    Shift(ns, 8)
    Equal(Showing(bar) .. " | " .. List(ns, "cd", 8), SHOWN.bear .. " | none", "dire bear form: bear form's list, none of its own")
    Shift(ns, 1)
    Equal(Showing(bar) .. " | " .. List(ns, "cd", 1), SHOWN.cat .. " | Claw,Pounce,Barkskin,Bear Form,slot:13",
        "cat form: its own, Pounce in it (a list is a form's, prowling or not)")
    Shift(ns, 1, true, "UPDATE_STEALTH")
    Equal(Showing(bar), SHOWN.cat, "prowling: still cat form's")
    Shift(ns, 3)
    Equal(Showing(bar) .. " | " .. List(ns, "cd", 3), "Barkskin 0 | Bear Form 40 | Trinket 80 | Barkskin,Bear Form,slot:13",
        "travel form: only what any form can use")
    Shift(ns, 31)
    Equal(Showing(bar), "Moonfire 0 | Barkskin 40 | Bear Form 80 | Trinket 120", "moonkin form: Moonfire, and not Maul or Claw")
    Shift(ns, nil)
    Equal(Showing(bar) .. " | " .. List(ns, "cd"), SHOWN.all .. " | " .. NORMAL, "out of form: the normal list, all of it")
    -- Several changes in one frame: read once, on the next frame.
    local reads = FormReads
    Form = 5
    Fire("UPDATE_SHAPESHIFT_FORM")
    Fire("UPDATE_SHAPESHIFT_FORMS")
    Fire("UPDATE_SHAPESHIFT_FORM")
    Equal(Showing(bar) .. " | " .. tostring(FormReads - reads), SHOWN.all .. " | 0", "nothing read as the events come")
    NextFrame(ns)
    Equal(Showing(bar) .. " | " .. tostring(FormReads - reads), SHOWN.bear .. " | 1", "then once, on the next frame")
    NextFrame(ns)
    Equal(FormReads - reads, 1, "and not again while nothing changes")
    -- Laid out again only when the list changes: bear to dire bear, the
    -- same list, no icon moved; then to cat, laid out again.
    do
        local set = 0
        local SetPoint = Proto.SetPoint
        Proto.SetPoint = function(self, ...) if rawget(self, "cooldown") then set = set + 1 end return SetPoint(self, ...) end
        Shift(ns, 8)
        local same = set
        Shift(ns, 1)
        Proto.SetPoint = SetPoint
        Equal(same .. " " .. tostring(set > 0), "0 true", "bear to dire bear: nothing moved; to cat: laid out again")
    end
    -- And only a bar whose list changed: Utility, which doesn't swap, stays
    -- put. Barkskin, moved there in cat form, left every Cooldowns list:
    -- Utility shows it in every form.
    B:Assign("Barkskin", "util")
    do
        local moved, util = 0, B:Get("util")
        local SetPoint = Proto.SetPoint
        Proto.SetPoint = function(self, ...)
            if rawget(self, "cooldown") and S[self].parent == util then moved = moved + 1 end
            return SetPoint(self, ...)
        end
        Shift(ns, 5)
        Proto.SetPoint = SetPoint
        Equal(moved .. " | " .. Showing(util) .. " | " .. Showing(bar), "0 | Barkskin 0 | Maul 0 | Bear Form 40 | Trinket 80",
            "a change of form lays out only the bars swapping with it: Utility stays put, Barkskin on it alone")
    end
    Equal(#printed, 0, "no errors")
end

-- Each list its own --------------------------------------------------------------------------------

do
    local ns, B, bar = Character("DRUID", DRUID, Ticked("DRUID", { "cd", "util" }))
    Shift(ns, 1)
    Shift(ns, 5)
    local cat = "Claw,Pounce,Barkskin,Bear Form,slot:13"
    B:Assign("Moonfire", "cd")
    Equal(List(ns, "cd", 5) .. " | " .. List(ns, "cd") .. " | " .. List(ns, "cd", 1), "Maul,Barkskin,Bear Form,slot:13,Moonfire | "
        .. NORMAL .. " | " .. cat, "a spell put on in bear form goes on bear form's list only")
    B:Remove("cd", 2)
    Equal(List(ns, "cd", 5) .. " | " .. List(ns, "cd") .. " | " .. List(ns, "cd", 1), "Maul,Bear Form,slot:13,Moonfire | " .. NORMAL
        .. " | " .. cat, "one taken off, off bear form's only")
    -- Moved to Utility in bear form: off Cooldowns' bear list, on Utility's.
    B:Assign("Maul", "util")
    Equal(List(ns, "cd", 5) .. " | " .. List(ns, "util", 5) .. " | " .. List(ns, "util") .. " | " .. List(ns, "cd") .. " | "
        .. Showing(B:Get("util")), "Bear Form,slot:13,Moonfire | Maul | empty | " .. NORMAL .. " | Maul 0",
        "moved to Utility in bear form: from Cooldowns' bear list to Utility's, the normal lists as they were")
    Shift(ns, nil)
    Equal(Showing(bar) .. " | " .. List(ns, "util") .. " | " .. tostring(B:Get("util").count), SHOWN.all .. " | empty | 0",
        "out of form: the normal lists, all of Cooldowns', nothing on Utility")
    B:Assign("Claw", nil)
    Equal(List(ns, "cd") .. " | " .. List(ns, "cd", 1), "Moonfire,Maul,Pounce,Barkskin,Bear Form,slot:13 | " .. cat,
        "taken off the normal list: cat form's keeps it")
    -- Another class's spell (a shared profile's) and one the game doesn't
    -- know, then a new form's list made from it: the warrior's Charge left
    -- out by its ranks' rule (Battle Stance only), the unknown one kept.
    table.insert(ns.ActiveList("cd"), "Charge")
    table.insert(ns.ActiveList("cd"), "Mystery Spell")
    Shift(ns, 31)
    Equal(List(ns, "cd", 31), "Moonfire,Barkskin,Bear Form,slot:13,Mystery Spell",
        "moonkin form's list: Moonfire and what any form casts, not a warrior's Charge; a spell the game doesn't know kept")
    -- A potion you carry none of, only on bear form's list: left off it,
    -- known as you read your bags in no form, so it never shows on a shift.
    Shift(ns, 5)
    table.insert(ns.ActiveList("cd"), "item:118")
    Shift(ns, nil)
    B:Changed()
    Equal(tostring(B:Absent("item:118")) .. " | " .. List(ns, "cd", 5), "true | Bear Form,slot:13,Moonfire,item:118",
        "a potion you carry none of on bear form's list only: known to be left off, from no form")
    lockdown = true
    Fire("PLAYER_REGEN_DISABLED")
    Shift(ns, 5)
    Equal(Showing(bar), "Bear Form 0 | Trinket 40 | Moonfire 80", "and shifting in a fight leaves it off")
    lockdown = false
    Fire("PLAYER_REGEN_ENABLED")
    Equal(#printed, 0, "no errors")
end

-- A spell on one of the two cooldown bars, in every form ----------------------------------------------
-- With one bar swapping and the other not, or form lists made at different
-- times, a spell moved between the bars leaves every list of the other bar
-- that shows beside its new one, and is never put on a list twice.

do
    -- Only Cooldowns swaps: Utility's list shows in every form.
    local ns, B, bar = Character("DRUID", DRUID, Ticked("DRUID", { "cd" }))
    local util = B:Get("util")
    Shift(ns, 5)
    Shift(ns, nil)
    B:Assign("Barkskin", "util")
    Equal(List(ns, "util") .. " | " .. List(ns, "cd") .. " | " .. List(ns, "cd", 5), "Barkskin | Moonfire,Claw,Maul,Pounce,Bear Form,slot:13"
        .. " | Maul,Bear Form,slot:13", "moved to Utility (which doesn't swap) in no form: off Cooldowns' normal list and bear form's")
    Shift(ns, 5)
    Equal(Showing(util) .. " | " .. Showing(bar) .. " | " .. tostring(B:Find("Barkskin")), "Barkskin 0 | Maul 0 | Bear Form 40 | Trinket 80"
        .. " | util", "in bear form: on Utility alone")
    B:Assign("Barkskin", "util")
    B:Add("util", "Barkskin")
    Equal(List(ns, "util"), "Barkskin", "ticked or added on Utility again: still once")
    -- Moved to Utility in bear form: off Cooldowns' normal list too, which
    -- shows beside Utility's out of form.
    B:Assign("Maul", "util")
    Equal(List(ns, "util") .. " | " .. List(ns, "cd", 5) .. " | " .. List(ns, "cd"), "Barkskin,Maul | Bear Form,slot:13"
        .. " | Moonfire,Claw,Pounce,Bear Form,slot:13", "Maul moved to Utility in bear form: off every Cooldowns list")
    Shift(ns, nil)
    Equal(Showing(util) .. " | " .. Showing(bar), "Barkskin 0 | Maul 40 | Moonfire 0 | Claw 40 | Pounce 80 | Bear Form 120 | Trinket 160",
        "out of form: Maul on Utility only")
    -- Two icons traded between the bars in bear form: each leaves the
    -- other bar's lists that show beside its new place.
    Shift(ns, 5)
    B:Trade("cd", "Bear Form", "util", "Maul")
    Equal(List(ns, "cd", 5) .. " | " .. List(ns, "util") .. " | " .. List(ns, "cd"), "Maul,slot:13 | Barkskin,Bear Form"
        .. " | Moonfire,Claw,Pounce,slot:13", "traded in bear form: Bear Form off every Cooldowns list, Maul on bear form's")
    Equal(#printed, 0, "no errors")
end

do
    -- The other way: a trade from Utility (which doesn't swap) in bear form
    -- puts Maul on it, so Maul leaves Cooldowns' normal list too.
    local ns, B = Character("DRUID", DRUID, Ticked("DRUID", { "cd" }))
    B:Assign("Barkskin", "util")
    Shift(ns, 5)
    B:Trade("util", "Barkskin", "cd", "Maul")
    Equal(List(ns, "util") .. " | " .. List(ns, "cd", 5) .. " | " .. List(ns, "cd"), "Maul | Barkskin,Bear Form,slot:13"
        .. " | Moonfire,Claw,Pounce,Bear Form,slot:13", "traded from Utility in bear form: Maul on Utility, off every Cooldowns list")
    Equal(#printed, 0, "no errors")
end

do
    -- Only Utility swaps: Cooldowns' list shows in every form. A trade in
    -- bear form puts Barkskin on it: off Utility's normal list too.
    local ns, B, bar = Character("DRUID", DRUID, Ticked("DRUID", { "util" }))
    local util = B:Get("util")
    B:Assign("Barkskin", "util")
    Shift(ns, 5)
    Equal(List(ns, "util", 5) .. " | " .. List(ns, "util"), "Barkskin | Barkskin", "Utility's bear form list, made from its normal one")
    B:Trade("cd", "Maul", "util", "Barkskin")
    Equal(List(ns, "util", 5) .. " | " .. List(ns, "util") .. " | " .. List(ns, "cd"),
        "Maul | empty | Moonfire,Claw,Barkskin,Pounce,Bear Form,slot:13", "traded in bear form: Barkskin on Cooldowns, off both Utility lists")
    Shift(ns, nil)
    Equal(Showing(util), "", "out of form: Barkskin on Cooldowns only")
    -- A spell on both bars' lists before the bars were laid out again
    -- (lists from elsewhere): moved to Utility, never put on it twice, even
    -- with Utility full.
    local profile = ForeverEnhancedCooldownManagerDB.profiles[ns.ProfileName()]
    profile.util = { "Barkskin" }
    for i = 2, ns.BAR_MAX_SPELLS do profile.util[i] = "Spell " .. i end
    Equal(tostring(B:Assign("Barkskin", "util")) .. " | " .. profile.util[1] .. " " .. #profile.util .. " | " .. List(ns, "cd"),
        "true | Barkskin 40 | Moonfire,Claw,Pounce,Bear Form,slot:13", "moved to a full Utility it's already on: once, off Cooldowns")
    Equal(select(2, table.concat(profile.util, ","):gsub("Barkskin", "")), 1, "(Barkskin on it once)")
    Equal(#printed, 0, "no errors")
end

do
    -- Both swap, Utility ticked after Cooldowns' bear form list was made.
    local ns, B, bar = Character("DRUID", DRUID, Ticked("DRUID", { "cd" }))
    local util = B:Get("util")
    Shift(ns, 5)
    Shift(ns, nil)
    B:Assign("Barkskin", "util")
    B:SetOption("util", "swapForm", true)
    Shift(ns, 5)
    Equal(List(ns, "util", 5) .. " | " .. List(ns, "cd", 5) .. " | " .. Showing(util) .. " | " .. Showing(bar),
        "Barkskin | Maul,Bear Form,slot:13 | Barkskin 0 | Maul 0 | Bear Form 40 | Trinket 80",
        "Utility ticked later: in bear form, Barkskin on Utility only")
    -- Both swapping: a move in bear form changes the two bear form lists only.
    B:Assign("Maul", "util")
    Equal(List(ns, "util", 5) .. " | " .. List(ns, "cd", 5) .. " | " .. List(ns, "cd") .. " | " .. List(ns, "util"),
        "Barkskin,Maul | Bear Form,slot:13 | Moonfire,Claw,Maul,Pounce,Bear Form,slot:13 | Barkskin",
        "both swapping, moved in bear form: the bear form lists only; out of form Maul stays on Cooldowns")
    -- A form's list made after the other bar's for that form leaves out
    -- what's on that one (cat form's for Utility, made by hand here).
    local profile = ForeverEnhancedCooldownManagerDB.profiles[ns.ProfileName()]
    profile.forms[1] = { util = { "Claw" } }
    Shift(ns, 1)
    Equal(List(ns, "cd", 1) .. " | " .. Showing(util), "Pounce,Bear Form,slot:13 | Claw 0",
        "Cooldowns' cat form list, made after Utility's: without Claw")
    Equal(#printed, 0, "no errors")
end

do
    -- A tick turned on or off, and lists from elsewhere: a spell on both
    -- bars in a form stays on one.
    local ns, B, bar = Character("DRUID", DRUID, Ticked("DRUID", { "cd", "util" }))
    local util = B:Get("util")
    local profile = ForeverEnhancedCooldownManagerDB.profiles[ns.ProfileName()]
    Shift(ns, 5)
    B:Assign("Barkskin", "util")
    Equal(List(ns, "util", 5) .. " | " .. List(ns, "cd"), "Barkskin | " .. NORMAL, "in bear form, Barkskin moved to Utility's bear form list")
    -- Cooldowns unticked: its normal list shows in every form now, and keeps
    -- what's on it; Utility's bear form list gives way.
    B:SetOption("cd", "swapForm", false)
    Equal(List(ns, "util", 5) .. " | " .. Showing(util) .. " | " .. Showing(bar), "empty |  | " .. SHOWN.all,
        "Cooldowns unticked: its whole list in bear form, Barkskin off Utility's bear form list")
    -- Utility's bear form list, kept while it was unticked, has a spell
    -- Cooldowns shows now: ticked again, it gives way.
    B:SetOption("util", "swapForm", false)
    profile.forms[5].util = { "Maul", "Moonfire" }
    B:SetOption("util", "swapForm", true)
    Equal(List(ns, "util", 5) .. " | " .. List(ns, "cd") .. " | " .. Showing(util), "empty | " .. NORMAL .. " | ",
        "Utility ticked again: its kept bear form list gives way to Cooldowns' list")
    -- A list from elsewhere (a profile switched to, one made from a string)
    -- with a spell on both bars in a form: it stays on Cooldowns.
    profile.forms[5].util = { "Maul", "Wrath" }
    B:Changed()
    Equal(List(ns, "util", 5) .. " | " .. Showing(util), "Wrath | ", "laid out again: Maul stays on Cooldowns, off Utility's list")
    Equal(#printed, 0, "no errors")
end

do
    -- Your form kept secret in a fight: read again as it ends.
    local ns, B, bar = Character("DRUID", DRUID, Ticked("DRUID", { "cd" }))
    lockdown = true
    Fire("PLAYER_REGEN_DISABLED")
    Shift(ns, SECRET)
    Equal(Showing(bar) .. " | " .. ns.FormNow(), SHOWN.all .. " | 0", "shifted in a fight, the form secret: the normal list stays")
    Form = 5
    lockdown = false
    Fire("PLAYER_REGEN_ENABLED")
    NextFrame(ns)
    Equal(Showing(bar) .. " | " .. ns.FormNow(), SHOWN.bear .. " | 5", "the fight over, still in bear form: bear form's list")
    Equal(#printed, 0, "no errors")
end

-- The game won't say, or names no list -------------------------------------------------------------

do
    local ns, B, bar = Character("DRUID", DRUID, Ticked("DRUID", { "cd" }), 5)
    Equal(Showing(bar), SHOWN.bear, "bear form")
    Shift(ns, SECRET)
    Equal(Showing(bar) .. " | " .. ns.FormNow(), SHOWN.bear .. " | 5", "your form kept secret: the list it shows stays")
    Shift(ns, nil, SECRET, "UPDATE_STEALTH")
    Equal(Showing(bar), SHOWN.bear, "no form, but whether you're stealthed kept secret: it stays too")
    Shift(ns, 14)
    Equal(Showing(bar) .. " | " .. ns.FormNow(), SHOWN.all .. " | 0", "a form no list is for (a quest's disguise): the normal list")
    Shift(ns, 5)
    local read = _G.GetShapeshiftFormID
    _G.GetShapeshiftFormID = nil
    Shift(ns, 1)
    Equal(Showing(bar), SHOWN.bear, "a game with no way to ask: the list it shows stays")
    _G.GetShapeshiftFormID = read
    Shift(ns, 1)
    Equal(Showing(bar), SHOWN.cat, "and cat form's once it can say")
    -- Stealthed in no form (a night elf's Shadowmeld): Normal, as a druid
    -- has no Stealth.
    Shift(ns, nil, true, "UPDATE_STEALTH")
    Equal(Showing(bar), SHOWN.all, "stealthed in no form, with no Stealth of its own: the normal list")
    Equal(#printed, 0, "no errors")
end

-- A warrior's stances ---------------------------------------------------------------------------

do
    local ns, B, bar = Character("WARRIOR", { { "Charge", 100, "Rank 1" }, { "Overpower", 7384, "Rank 1" }, { "Shield Wall", 871 },
        { "Intercept", 20252, "Rank 1" }, { "Execute", 5308, "Rank 1" }, { "Heroic Strike", 78, "Rank 1" }, { "Battle Stance", 2457 } },
        Ticked("WARRIOR", { "cd" }, { useBars = true, bars = { cd = { grow = "right" } } }), 17)
    Equal(Showing(bar), "Charge 0 | Overpower 40 | Execute 80 | Heroic Strike 120 | Battle Stance 160 | Trinket 200",
        "Battle Stance: its own list, without what only the other stances can use")
    Shift(ns, 18)
    Equal(Showing(bar), "Shield Wall 0 | Heroic Strike 40 | Battle Stance 80 | Trinket 120", "Defensive Stance: Shield Wall")
    Shift(ns, 19)
    Equal(Showing(bar), "Intercept 0 | Execute 40 | Heroic Strike 80 | Battle Stance 120 | Trinket 160",
        "Berserker Stance: Intercept and Execute")
    B:Assign("Heroic Strike", nil)
    Shift(ns, 17)
    Equal(Showing(bar) .. " | " .. List(ns, "cd", 19), "Charge 0 | Overpower 40 | Execute 80 | Heroic Strike 120 | Battle Stance 160"
        .. " | Trinket 200 | Intercept,Execute,Battle Stance,slot:13", "Heroic Strike off Berserker Stance's list only")
    Equal(#printed, 0, "no errors")
end

-- A rogue's stealth -----------------------------------------------------------------------------

do
    local ns, B, bar = Character("ROGUE", { { "Sinister Strike", 1752, "Rank 1" }, { "Ambush", 8676, "Rank 1" }, { "Sap", 6770, "Rank 1" },
        { "Stealth", 1784, "Rank 1" } }, Ticked("ROGUE", { "cd" }, { useBars = true, bars = { cd = { grow = "right" } } }))
    local all = "Sinister Strike 0 | Ambush 40 | Sap 80 | Stealth 120 | Trinket 160"
    Equal(Showing(bar), all, "out of stealth: the normal list")
    Shift(ns, 30, true)
    Equal(List(ns, "cd", 30), "Sinister Strike,Ambush,Sap,Stealth,slot:13", "stealthed: Stealth's own list, made from the normal one")
    B:Assign("Sinister Strike", nil)
    Equal(Showing(bar), "Ambush 0 | Sap 40 | Stealth 80 | Trinket 120", "Sinister Strike taken off it")
    Shift(ns, nil, false, "UPDATE_STEALTH")
    Equal(Showing(bar), all, "out of stealth: the normal list, Sinister Strike and all")
    Shift(ns, nil, true, "UPDATE_STEALTH")
    Equal(Showing(bar), "Ambush 0 | Sap 40 | Stealth 80 | Trinket 120",
        "stealthed with no form (should the game not call Stealth one): Stealth's list, as you know Stealth")
    Equal(#printed, 0, "no errors")
end

-- Your bars off and on again: your form still heard -----------------------------------------------

do
    local ns, B, bar = Character("DRUID", DRUID, Ticked("DRUID", { "cd" }), 5)
    local function Heard()
        local events = S[B.driver].events
        return tostring(events.UPDATE_SHAPESHIFT_FORM) .. " " .. tostring(events.UPDATE_SHAPESHIFT_FORMS) .. " "
            .. tostring(events.UPDATE_STEALTH)
    end
    Equal(Heard(), "true true true", "ticked, your bars on: your form changing is heard")
    -- As General's Use my bars tick does it.
    ns.Set("useBars", false)
    B:Rebuild()
    Equal(Heard(), "nil nil nil", "your bars off: not heard")
    Form = 1
    ns.Set("useBars", true)
    B:Rebuild()
    Equal(Heard() .. " | " .. Showing(bar), "true true true | " .. SHOWN.cat,
        "on again, still ticked: heard again, and the form you took meanwhile read")
    Shift(ns, 5)
    Equal(Showing(bar), SHOWN.bear, "and a change of form swaps the list as before")
    -- Off, the bar's page still reads your form as it shows.
    ns.Set("useBars", false)
    B:Rebuild()
    Form = 31
    SlashCmdList.FECM("")
    FECMFrame:Select("cd")
    Equal(S[FECMFrame.pages.bar.options.editing.name].text .. " | " .. table.concat((B:Mine("cd")), ","),
        "Moonkin Form | Moonfire,Barkskin,Bear Form,slot:13", "your bars off: the page reads the form you're in, for its tray")
    Equal(#printed, 0, "no errors")
end

-- In a fight: the addon's own icons only ----------------------------------------------------------

do
    local ns, B, bar = Character("DRUID", DRUID, Ticked("DRUID", { "cd" }, { useBars = true, bars = { cd = { showAuras = true } } }))
    lockdown = true
    Fire("PLAYER_REGEN_DISABLED")
    local calls, runs = containerCallsInCombat, #ContainerRuns
    Shift(ns, 5)
    Equal(Showing(bar), SHOWN.bear, "bear form in a fight: its list at once, made now")
    Shift(ns, 1, true)
    Equal(Showing(bar), SHOWN.cat, "cat form, prowling: its list")
    Equal(tostring(containerCallsInCombat - calls) .. " " .. tostring(#ContainerRuns - runs), "0 0",
        "nothing told to the game's aura containers, and none of their code run inside the addon's")
    -- Laid out again in a fight (a spell learned): the same.
    B:Relayout("cd")
    Equal(Showing(bar) .. " | " .. tostring(containerCallsInCombat - calls), SHOWN.cat .. " | 0",
        "laid out again in the fight: the same, nothing told to the containers")
    lockdown = false
    Fire("PLAYER_REGEN_ENABLED")
    Equal(Showing(bar), SHOWN.cat, "the fight over: as it was")
    Equal(#printed, 0, "no errors")
end

-- /ccm debug says what it read --------------------------------------------------------------------

do
    local ns = Character("DRUID", DRUID, Ticked("DRUID", { "cd" }), 5)
    local report = ns.DebugReport()
    Equal(report:match("\n  swap with my form: [^\n]*"), "\n  swap with my form: form 5, stealthed false, showing Bear Form",
        "the form and stealth the game gave, and whose list the bar shows")
    Equal(report:find("showing Bear Form\n  when ready show", 1, true) ~= nil, true, "just before how they show when ready")
    Equal(select(2, report:gsub("swap with my form:", "")), 1, "and only under the bar it's ticked on")
    ns.SetEditingForm(0)
    ns.Bars:FormChanged()
    Equal(ns.DebugReport():match("\n  swap with my form: [^\n]*"), "\n  swap with my form: form 5, stealthed false, showing Normal"
        .. " (picked on its page)", "the list picked on the bar's page")
    ns.SetEditingForm(nil)
    ns.Bars:FormChanged()
    Shift(ns, SECRET)
    Equal(ns.DebugReport():match("\n  swap with my form: [^\n]*"), "\n  swap with my form: form secret, stealthed false, showing Bear Form",
        "a secret form: the list it showed")
    Equal(#printed, 0, "no errors")
end

-- On the bar's page: the tick, and Editing ---------------------------------------------------------

do
    local ns, B, bar = Character("DRUID", DRUID, nil, 5)
    SlashCmdList.FECM("")
    local w = FECMFrame
    w:Select("cd")
    local page = w.pages.bar
    local tick, editing = page.options.swapForm, page.options.editing
    local at = S[tick].points[1]
    Equal(tostring(S[tick].shown) .. " " .. S[tick.text].text .. " " .. tostring(tick:GetChecked()) .. " " .. tostring(S[editing].shown)
        .. " | " .. at[1] .. " " .. at[2] .. " " .. at[3], "true Swap with my form false false | TOPLEFT 320 -129",
        "the Cooldowns page: the tick, off, under Show buff and debuff time, beside Dim when you can't cast it; no Editing")
    S[tick].scripts.OnEnter(tick)
    Equal(S[w.note].text, "Each form gets its own icons on this bar, swapped as you change.",
        "its note (no longer marked experimental: seen working in game, 1.6.0)")
    Equal(#S[w.note].text * 5.6 <= 560, true, "on one line of the footer")
    S[tick].scripts.OnLeave(tick)
    tick:Click()
    local pick, label = S[editing].points[1], S[editing.label].points[1]
    Equal(tostring(ns.Swaps("cd")) .. " " .. tostring(tick:GetChecked()) .. " | " .. tostring(S[editing].shown) .. " "
        .. S[editing.label].text .. " " .. pick[2] .. " " .. pick[3] .. " " .. label[2] .. " " .. label[3] .. " " .. S[editing.name].text
        .. " | " .. Showing(bar), "true true | true Editing 420 -151 320 -155 Bear Form | " .. SHOWN.bear,
        "clicked: on, Editing under it on your form, and the bar shows bear form's list at once")
    w:Select("util")
    Equal(tostring(tick:GetChecked()) .. " " .. tostring(S[tick].shown) .. " " .. tostring(S[editing].shown), "false true false",
        "Utility's page shows Utility's own, off")
    for _, key in ipairs({ "buff", "debuff" }) do
        w:Select(key)
        Equal(tostring(S[tick].shown) .. " " .. tostring(S[editing].shown), "false false",
            "not on the " .. key .. " page: auras don't change with your form")
    end
    Equal(#printed, 0, "no errors")
end

do
    local ns, B, bar = Character("DRUID", DRUID, Ticked("DRUID", { "cd" }), nil, nil,
        { { "Cat Form", 768 }, { "Dire Bear Form", 9634 } })
    SlashCmdList.FECM("")
    local w = FECMFrame
    w:Select("cd")
    local page = w.pages.bar
    local editing = page.options.editing
    Equal(tostring(S[editing].shown) .. " " .. S[editing.name].text, "true Normal", "in no form: Editing on Normal")
    S[editing.next].scripts.OnEnter(editing.next)
    Equal(S[w.note].text, "Pick a form to set up its icons here without changing form. Normal is for no form.", "its note")
    Equal(#S[w.note].text * 5.6 <= 560, true, "on one line of the footer")
    S[editing.next].scripts.OnLeave(editing.next)
    -- Normal, Cat Form, then bear form's list, named for Dire Bear Form,
    -- the later one you know.
    local names = {}
    for _ = 1, 3 do
        editing.next:Click()
        names[#names + 1] = S[editing.name].text
    end
    Equal(table.concat(names, ", "), "Cat Form, Dire Bear Form, Normal", "the arrows step through the forms you know, then Normal")
    editing.back:Click()
    Equal(S[editing.name].text .. " | " .. Showing(bar) .. " | " .. table.concat((B:Mine("cd")), ",") .. " | " .. ns.FormNow(),
        "Dire Bear Form | " .. SHOWN.bear .. " | Maul,Barkskin,Bear Form,slot:13 | 0",
        "Dire Bear Form picked in no form: the bar and the tray show bear form's list, made now; you're still in no form")
    -- A spell ticked in the list goes on the list showing.
    local row
    for _, each in ipairs(page.rows) do
        if S[each].shown and each.spell == "Moonfire" then row = each end
    end
    row.check:Click()
    Equal(List(ns, "cd", 5) .. " | " .. List(ns, "cd"), "Maul,Barkskin,Bear Form,slot:13,Moonfire | " .. NORMAL,
        "Moonfire ticked in the list: on bear form's list only")
    -- A fight: your form's list again, Editing still; even before the bars
    -- hear it start, a list asked for is your form's. Its arrows aren't
    -- greyed (nothing would ungrey them as it ends): clicked, they say why
    -- they do nothing.
    lockdown = true
    Equal(tostring(ns.EditingForm()) .. " | " .. table.concat(ns.ActiveList("cd"), ","), "5 | " .. NORMAL,
        "in a fight before it's heard: your form's list, whatever's picked")
    Fire("PLAYER_REGEN_DISABLED")
    Equal(tostring(ns.EditingForm()) .. " | " .. S[editing.name].text .. " | " .. Showing(bar) .. " | " .. tostring(editing.next.usable)
        .. " " .. tostring(editing.back.usable), "nil | Normal | " .. SHOWN.all .. " | nil nil",
        "a fight: the bars follow your form again, Editing on it, its arrows never greyed")
    editing.next:Click()
    Equal(tostring(ns.EditingForm()) .. " " .. S[editing.name].text .. " | " .. S[w.note].text,
        "nil Normal | Not in a fight: your bars follow your form until it ends.", "its arrows do nothing, and the footer says why")
    S[editing.next].scripts.OnEnter(editing.next)
    Equal(S[w.note].text, "Not in a fight: your bars follow your form until it ends.", "and so does their note")
    S[editing.next].scripts.OnLeave(editing.next)
    lockdown = false
    Fire("PLAYER_REGEN_ENABLED")
    NextFrame(ns)
    -- The fight over, with no other refresh: the arrows work again.
    editing.next:Click()
    Equal(tostring(ns.EditingForm()) .. " " .. S[editing.name].text, "1 Cat Form", "the fight over: the arrows step again at once")
    editing.back:Click()
    Equal(tostring(ns.EditingForm()) .. " " .. S[editing.name].text, "0 Normal", "and back")
    ns.SetEditingForm(nil)
    w:Refresh()
    -- You change form with the page open: it follows.
    Shift(ns, 1)
    Equal(S[editing.name].text .. " | " .. table.concat((B:Mine("cd")), ","), "Cat Form | Claw,Pounce,Barkskin,Bear Form,slot:13",
        "you change form with the page open: Editing and the tray follow")
    Shift(ns, nil)
    -- Cat Form picked, then you change form: the one picked still shows.
    editing.next:Click()
    Shift(ns, 5)
    local bear = SHOWN.bear .. " | Moonfire 160"
    Equal(Showing(bar) .. " | " .. S[editing.name].text .. " | " .. ns.FormNow(), SHOWN.cat .. " | Cat Form | 5",
        "you change form meanwhile: the one picked still shows")
    w:Select("util")
    Equal(tostring(ns.EditingForm()) .. " | " .. Showing(bar), "nil | " .. bear, "another bar's page: back to your form's (bear)")
    w:Select("cd")
    Equal(S[editing.name].text, "Dire Bear Form", "back on Cooldowns: Editing on your form's")
    editing.next:Click()
    Equal(Showing(bar), SHOWN.all, "Normal picked in bear form: the normal list")
    w:Hide()
    Equal(tostring(ns.EditingForm()) .. " | " .. Showing(bar), "nil | " .. bear, "the window closed: your form's again")
    Equal(#printed, 0, "no errors")
end

-- No form, no tick ----------------------------------------------------------------------------------

-- The tick's words follow the class (the user, on a rogue: "it should not say form") ---------------------
-- So does its step in What's new (1.6.0's, numbered before the release):
-- after 1.5.9, What's new tours Dim on cooldown, then Swap your icons in
-- the class's words (step).

for _, case in ipairs({
    { "ROGUE", { { "Sinister Strike", 1752, "Rank 1" }, { "Stealth", 1784, "Rank 1" } }, "Swap when in Stealth",
        "Stealth gets its own icons on this bar, swapped as you go in and out of it.",
        "Pick Stealth to set up its icons here without using it. Normal is for the rest of the time.",
        "Not in a fight: your bars follow Stealth until it ends.",
        step = "Ticked, Stealth gets its own icons on this bar, swapped as you go in and out of it, in a fight too."
            .. " Editing then shows under the tick, to set them up without using Stealth." },
    { "WARRIOR", { { "Heroic Strike", 78, "Rank 1" }, { "Battle Stance", 2457 }, { "Defensive Stance", 71 } },
        "Swap with my stance", "Each stance gets its own icons on this bar, swapped as you change.",
        "Pick a stance to set up its icons here without changing stance. Normal is for no stance.",
        "Not in a fight: your bars follow your stance until it ends.",
        step = "Ticked, each stance gets its own icons on this bar, swapped as you change, in a fight too."
            .. " Editing then shows under the tick, to set up another stance's without changing stance." },
    { "DRUID", DRUID, "Swap with my form", "Each form gets its own icons on this bar, swapped as you change.",
        "Pick a form to set up its icons here without changing form. Normal is for no form.",
        "Not in a fight: your bars follow your form until it ends.",
        step = "Ticked, each form gets its own icons on this bar, swapped as you change, in a fight too."
            .. " Editing then shows under the tick, to set up another form's without changing form." },
    { "PRIEST", { { "Mind Blast", 8092, "Rank 1" }, { "Shadowform", 15473 } }, "Swap when in Shadowform",
        "Shadowform gets its own icons on this bar, swapped as you go in and out of it.",
        step = "Ticked, Shadowform gets its own icons on this bar, swapped as you go in and out of it, in a fight too."
            .. " Editing then shows under the tick, to set them up without using Shadowform." },
    { "SHAMAN", { { "Lightning Bolt", 403, "Rank 1" }, { "Ghost Wolf", 2645 } }, "Swap when in Ghost Wolf",
        "Ghost Wolf gets its own icons on this bar, swapped as you go in and out of it.",
        step = "Ticked, Ghost Wolf gets its own icons on this bar, swapped as you go in and out of it, in a fight too."
            .. " Editing then shows under the tick, to set them up without using Ghost Wolf." },
}) do
    local class, spells, label, hover, note, fight = case[1], case[2], case[3], case[4], case[5], case[6]
    local ns = Character(class, spells, Ticked(class, { "cd" }, { useBars = true, notesSeen = "dev", helpSeen = true }))
    SlashCmdList.FECM("")
    local w = FECMFrame
    w:Select("cd")
    local tick = w.pages.bar.options.swapForm
    Equal(tostring(S[tick].shown) .. " " .. S[tick.text].text, "true " .. label, class .. ": the tick's words")
    Equal(tick:GetWidth(), 18 + tick.text:GetStringWidth(), class .. ": its click area takes the label's width")
    S[tick].scripts.OnEnter(tick)
    Equal(S[w.note].text, hover, class .. ": its hover note")
    if note then
        local editing = w.pages.bar.options.editing
        S[editing.next].scripts.OnEnter(editing.next)
        Equal(S[w.note].text, note, class .. ": the Editing note")
        Equal(#S[w.note].text * 5.6 <= 560, true, class .. ": on one line of the footer")
        S[editing.next].scripts.OnLeave(editing.next)
        lockdown = true
        S[editing.next].scripts.OnEnter(editing.next)
        Equal(S[w.note].text, fight, class .. ": in a fight")
        S[editing.next].scripts.OnLeave(editing.next)
        lockdown = false
    end
    Equal(ns.SwapWords().label, label, class .. ": SwapWords")
    local news = ns.Tour:News("1.5.9")
    Equal(#news .. " " .. news[1].title .. ", " .. news[2].title .. " " .. news[1].version .. " " .. news[2].version, "2 Dim on cooldown, Swap your icons 1.6.0 1.6.0",
        class .. ": after 1.5.9, What's new has exactly 1.6.0's two steps")
    ns.ShowNotes("1.5.9")
    FECMNotes.tour:Click()
    local box = FECMTour
    local first = S[box.count].text .. " " .. w.selected .. " " .. S[box.title].text
    box.next:Click()
    Equal(first .. " | " .. S[box.count].text .. " " .. w.selected .. " " .. S[box.title].text .. " | " .. S[box.text].text .. " | "
        .. S[box.next.label].text, "1 of 2 cd DIM ON COOLDOWN | 2 of 2 cd SWAP YOUR ICONS | " .. case.step .. " | Done",
        class .. ": Show me what's new tours them, Swap your icons in the class's words")
    box.skip:Click()
    w:Hide()
    Equal(#printed, 0, class .. ": no errors")
end

do
    local ns, B, bar = Character("MAGE", { { "Fireball", 133, "Rank 1" } },
        Ticked("MAGE", { "cd" }, { useBars = true, notesSeen = "dev", helpSeen = true }))
    SlashCmdList.FECM("")
    local w = FECMFrame
    w:Select("cd")
    local page = w.pages.bar
    Equal(tostring(S[page.options.swapForm].shown) .. " " .. tostring(S[page.options.editing].shown) .. " | " .. Showing(bar),
        "false false | Fireball 0 | Trinket 40", "a mage: no Swap with my form, nor Editing, though it's ticked; its bar as ever")
    w.help:Click()
    local titles = {}
    repeat
        titles[#titles + 1] = S[FECMTour.title].text
        local done = S[FECMTour.next.label].text == "Done"
        FECMTour.next:Click()
    until done or #titles > 20
    Equal(tostring(table.concat(titles, ", "):find("SWAP YOUR ICONS", 1, true)) .. " " .. titles[#titles], "nil DIM ON COOLDOWN",
        "and the page's walkthrough leaves its step out")
    local news = ns.Tour:News("1.5.9")
    Equal(#news .. " " .. news[1].title .. " " .. news[1].version .. " | " .. #ns.Tour:News(nil), "1 Dim on cooldown 1.6.0 | 1",
        "and What's new after 1.5.9 too: only Dim on cooldown, by hand the same")
    Equal(#printed, 0, "no errors")
end

-- Each profile its own tick ---------------------------------------------------------------------------
-- The tick is saved in the profile, beside the lists it swaps between, so a
-- druid ticking it never changes a warrior's bars on the same account (in
-- 1.6.0 it was every character's: a warrior always in a stance then only
-- ever saw Battle Stance's list). A profile switched to brings its own; a
-- profile shared by several characters (Use on all characters) has one tick
-- for them all.

-- A bar's icons showing, by name only ("Maul | Barkskin").
local function Names(bar)
    return (Showing(bar):gsub(" [%d,%.%-]+", ""))
end
local WARRIOR = { { "Charge", 100, "Rank 1" }, { "Overpower", 7384, "Rank 1" }, { "Shield Wall", 871 },
    { "Intercept", 20252, "Rank 1" }, { "Execute", 5308, "Rank 1" }, { "Heroic Strike", 78, "Rank 1" }, { "Battle Stance", 2457 } }
local WARRIOR_ALL = "Charge | Overpower | Shield Wall | Intercept | Execute | Heroic Strike | Battle Stance | Trinket"

do
    -- A druid ticks it, then a warrior logs in on the same account.
    character = { guid = "Player-1-0001", name = "Zriel", realm = "Zephras" }
    local ns, B, bar = Character("DRUID", DRUID, nil, 5)
    local saved = ForeverEnhancedCooldownManagerDB
    local druid = ns.ProfileName()
    B:SetOption("cd", "swapForm", true)
    Equal(Showing(bar) .. " | " .. Ticks(saved.profiles[druid]), SHOWN.bear .. " | cd", "the druid ticks it: bear form's list")
    character = { guid = "Player-1-0002", name = "Grom", realm = "Zephras" }
    local ns2, B2, bar2 = Character("WARRIOR", WARRIOR, saved, 17)
    local warrior = ns2.ProfileName()
    Equal(warrior .. " | " .. tostring(ns2.Swaps("cd")) .. " " .. Ticks(saved.profiles[warrior]) .. " | " .. Names(bar2) .. " | "
        .. List(ns2, "cd", 17) .. " " .. tostring(S[B2.driver].events.UPDATE_SHAPESHIFT_FORM),
        "Grom (Warrior) - Zephras | false nil | " .. WARRIOR_ALL .. " | none nil",
        "a warrior on its own profile: not ticked, its whole list in Battle Stance, no stance list made, its stance not heard")
    SlashCmdList.FECM("")
    FECMFrame:Select("cd")
    local tick = FECMFrame.pages.bar.options.swapForm
    Equal(S[tick.text].text .. " " .. tostring(tick:GetChecked()) .. " " .. tostring(S[FECMFrame.pages.bar.options.editing].shown),
        "Swap with my stance false false", "and its page shows the tick unticked")
    -- The warrior ticks and unticks its own: the druid's stays ticked.
    tick:Click()
    Equal(Names(bar2) .. " | " .. Ticks(saved.profiles[warrior]) .. " " .. Ticks(saved.profiles[druid]),
        "Charge | Overpower | Execute | Heroic Strike | Battle Stance | Trinket | cd cd",
        "the warrior ticks it: Battle Stance's own list, and the druid's tick as it was")
    tick:Click()
    Equal(Names(bar2) .. " | " .. Ticks(saved.profiles[warrior]) .. " " .. Ticks(saved.profiles[druid]), WARRIOR_ALL .. " | nil cd",
        "unticked on the warrior: its whole list again, the druid's still ticked")
    FECMFrame:Hide()
    Equal(#printed, 0, "no errors")
    -- Back on the druid: ticked, in bear form, bear form's list.
    character = { guid = "Player-1-0001", name = "Zriel", realm = "Zephras" }
    local ns3, B3, bar3 = Character("DRUID", {}, saved, 5, nil, DRUID)
    Equal(ns3.ProfileName() .. " | " .. tostring(ns3.Swaps("cd")) .. " | " .. Names(bar3), druid .. " | true | Maul | Barkskin | Bear Form"
        .. " | Trinket", "the druid logs in again: still ticked, bear form's list")
    -- Another profile switched to has its own (none); back again, ticked.
    ns3.NewProfile("Fresh")
    Equal(tostring(ns3.Swaps("cd")) .. " " .. tostring(S[B3.driver].events.UPDATE_SHAPESHIFT_FORM), "false nil",
        "a new profile: not ticked, your form not heard")
    ns3.UseProfile(druid)
    Equal(tostring(ns3.Swaps("cd")) .. " " .. tostring(S[B3.driver].events.UPDATE_SHAPESHIFT_FORM) .. " | " .. Names(bar3),
        "true true | Maul | Barkskin | Bear Form | Trinket", "back on the druid's: ticked, heard, bear form's list at once")
    Equal(#printed, 0, "no errors")
end

do
    -- Saved by 1.6.0, the tick every character's: a druid's profile with
    -- bear form's list, a warrior's that logged in meanwhile (so it has a
    -- Battle Stance list), and a mage's and another warrior's that never
    -- swapped. The tick goes into the two that swapped, once.
    local druid, grom, mage, thrall = "Zriel (Druid) - Zephras", "Grom (Warrior) - Zephras", "Jaina (Mage) - Zephras",
        "Thrall (Warrior) - Zephras"
    local saved = { useBars = true, bars = { cd = { swapForm = true, size = 40 } },
        chars = { ["Player-1-0001"] = druid, ["Player-1-0002"] = grom, ["Player-1-0003"] = mage, ["Player-1-0004"] = thrall },
        profiles = {
            [druid] = { cd = { "Moonfire", "Maul", "Barkskin", "Bear Form" }, forms = { [5] = { cd = { "Maul", "Barkskin", "Bear Form" } } } },
            [grom] = { cd = { "Charge", "Shield Wall", "Battle Stance" }, forms = { [17] = { cd = { "Charge", "Battle Stance" } } } },
            [mage] = { cd = { "Fireball" } }, [thrall] = { cd = { "Charge" }, util = { "Shield Wall" } } } }
    -- Each logs in with its spells known (none newly put on a bar: only the
    -- trinket, on the normal list).
    character = { guid = "Player-1-0001", name = "Zriel", realm = "Zephras" }
    local ns, B, bar = Character("DRUID", {}, saved, 5, nil, DRUID)
    Equal(Ticks(saved.profiles[druid]) .. " " .. Ticks(saved.profiles[grom]) .. " " .. Ticks(saved.profiles[mage]) .. " "
        .. Ticks(saved.profiles[thrall]) .. " | " .. tostring(rawget(saved.bars.cd, "swapForm")) .. " " .. saved.bars.cd.size,
        "cd cd nil nil | nil 40", "moved into each profile with a form's list for that bar; gone from the bar's settings, the rest kept")
    Equal(Names(bar), "Maul | Barkskin | Bear Form", "the druid: as before, bear form's list")
    -- The warrior, whose bar swapped meanwhile, keeps it; unticked there
    -- now, the druid's stays (and it isn't moved again).
    character = { guid = "Player-1-0002", name = "Grom", realm = "Zephras" }
    local ns2, B2, bar2 = Character("WARRIOR", {}, saved, 17, nil, WARRIOR)
    Equal(tostring(ns2.Swaps("cd")) .. " | " .. Names(bar2), "true | Charge | Battle Stance",
        "the warrior that swapped meanwhile: as before, Battle Stance's list")
    B2:SetOption("cd", "swapForm", false)
    Equal(Names(bar2) .. " | " .. Ticks(saved.profiles[grom]) .. " " .. Ticks(saved.profiles[druid]),
        "Charge | Shield Wall | Battle Stance | Trinket | nil cd", "unticked on the warrior alone: its whole list, the druid's still ticked")
    -- The other warrior never swapped: its whole list, always.
    character = { guid = "Player-1-0004", name = "Thrall", realm = "Zephras" }
    local ns4, B4, bar4 = Character("WARRIOR", {}, saved, 17, nil, WARRIOR)
    Equal(tostring(ns4.Swaps("cd")) .. " | " .. Names(bar4) .. " | " .. tostring(saved.profiles[thrall].forms),
        "false | Charge | Trinket | nil", "a warrior that never swapped: not ticked, its whole list, no stance list made")
    character = { guid = "Player-1-0001", name = "Zriel", realm = "Zephras" }
    local ns3, B3, bar3 = Character("DRUID", {}, saved, 5, nil, DRUID)
    Equal(tostring(ns3.Swaps("cd")) .. " " .. Ticks(saved.profiles[grom]) .. " | " .. Names(bar3), "true nil | Maul | Barkskin | Bear Form",
        "the druid again: still ticked, and the warrior's not ticked again")
    Equal(#printed, 0, "no errors")
end

do
    -- Use on all characters: one profile, one tick for every character on it.
    character = { guid = "Player-1-0001", name = "Zriel", realm = "Zephras" }
    local ns, B, bar = Character("DRUID", DRUID, nil, 5)
    local saved = ForeverEnhancedCooldownManagerDB
    local everyone = ns.ProfileName()
    ns.UseOnAll()
    B:SetOption("cd", "swapForm", true)
    character = { guid = "Player-1-0002", name = "Grom", realm = "Zephras" }
    local ns2, B2, bar2 = Character("WARRIOR", WARRIOR, saved, 17)
    Equal(ns2.ProfileName() .. " | " .. tostring(ns2.Swaps("cd")) .. " | " .. Names(bar2), everyone .. " | true | Trinket | Charge"
        .. " | Overpower | Execute | Heroic Strike | Battle Stance", "a warrior on the profile used on all characters: ticked, as it's"
        .. " the same profile, Battle Stance's own list (without Shield Wall and Intercept)")
    B2:SetOption("cd", "swapForm", false)
    Equal(Ticks(saved.profiles[everyone]), "nil", "unticked by the warrior: off for every character on that profile")
    character = { guid = "Player-1-0001", name = "Zriel", realm = "Zephras" }
    local ns3, B3, bar3 = Character("DRUID", {}, saved, 5, nil, DRUID)
    Equal(tostring(ns3.Swaps("cd")) .. " | " .. tostring(Names(bar3):find("Moonfire", 1, true) ~= nil), "false | true",
        "the druid on it: unticked too, its whole list in bear form")
    Equal(#printed, 0, "no errors")
end

-- Saved, repaired, copied and kept ------------------------------------------------------------------

do
    Environment()
    local many = {}
    for i = 1, 45 do many[i] = "Spell " .. i end
    -- Saved by 1.6.0, when the tick was with each bar's settings (every
    -- character's): moved into each profile with a form's list for that bar.
    local ns = Load({ useBars = true, chars = { ["Player-1-0001"] = "Mine" },
        bars = { cd = { swapForm = "yes", onlyForm = true }, util = { swapForm = true }, buff = { swapForm = true }, debuff = { swapForm = 1 } },
        profiles = { Mine = { cd = { "Maul" }, forms = {
            [5] = { cd = { "Maul", 7, "", "Swipe" }, util = "x", buff = { "Thorns" }, nope = {} },
            [8] = { cd = { "Maul" } }, [99] = { cd = {} }, ["5"] = { cd = {} }, [1] = "cat", [31] = { util = many } } },
            Junk = { swapForm = { cd = true, util = "yes", buff = true, [3] = true, nope = true } }, Odd = { swapForm = "cd" } } })
    local db = ForeverEnhancedCooldownManagerDB
    Equal(tostring(ns.Swaps("cd")) .. " " .. tostring(ns.Swaps("util")) .. " " .. tostring(ns.Swaps("buff"))
        .. " " .. tostring(ns.Swaps("debuff")) .. " | " .. Ticks(db.profiles.Mine), "false true false false | util",
        "kept over a reload: only true is on, never on the Buffs or Debuffs bar, and Utility's tick moved into the profile"
            .. " with a Utility list for a form")
    local left = {}
    for _, key in ipairs(ns.BAR_KEYS) do left[#left + 1] = tostring(rawget(db.bars[key], "swapForm")) end
    Equal(table.concat(left, " ") .. " " .. tostring(db.bars.cd.onlyForm), "nil nil nil nil nil",
        "none left with the bars' settings; Only show what your form can use (never released) gone")
    Equal(Ticks(db.profiles.Junk) .. " | " .. Ticks(db.profiles.Odd), "cd | nil",
        "a profile's own ticks repaired: only true, the Cooldowns and Utility bars only; anything else none")
    local forms, keys, five = db.profiles.Mine.forms, {}, {}
    for form in pairs(forms) do keys[#keys + 1] = tostring(form) end
    table.sort(keys)
    for key, list in pairs(forms[5]) do five[#five + 1] = key .. "=" .. table.concat(list, ",") end
    Equal(table.concat(keys, ",") .. " | " .. table.concat(five, " ") .. " | " .. #forms[31].util .. " " .. forms[31].util[40],
        "31,5 | cd=Maul,Swipe | 40 Spell 40",
        "each form's lists repaired: only forms with a list of their own, the Cooldowns and Utility bars, entries as on a bar, 40 at most")
    -- Copied: each form's lists too, a copy of its own.
    local ok = ns.CopyProfile("Copy")
    local copy = db.profiles.Copy.forms
    copy[5].cd[1] = "Bash"
    Equal(tostring(ok) .. " | " .. table.concat(copy[5].cd, ",") .. " | " .. table.concat(forms[5].cd, ",") .. " | " .. #copy[31].util,
        "true | Bash,Swipe | Maul,Swipe | 40", "a profile copied takes each form's lists, a copy of its own")
    ns.Bars:SetOption("cd", "swapForm", true)
    Equal(Ticks(db.profiles.Copy) .. " | " .. Ticks(db.profiles.Mine), "cd,util | util",
        "and the ticks, a copy of their own: ticking Cooldowns on the copy leaves the first as it was")
    -- A spell added by ID that's only on a form's list stays, and is found for the bars.
    ns.AddCustom("Spell 7", { 1243 })
    ns.Bars:Changed()
    ns.Spells:Stale()
    Equal(tostring(ns.CustomSpells()["Spell 7"] and ns.CustomSpells()["Spell 7"][1]) .. " " .. tostring(ns.Spells:Find("Spell 7") ~= nil),
        "1243 true", "a spell added by ID only on a form's list: kept, and known for the bars")
    copy[31].util[7] = "Gone"
    forms[31].util[7] = "Gone"
    ns.Bars:Changed()
    Equal(tostring(ns.CustomSpells()["Spell 7"]), "nil", "and let go once it's on no list")
    Equal(#printed, 0, "no errors")
end

Equal(SecretMisuse[1], nil, "no secret misused anywhere")
io.write("Swap with my form checks passed: " .. checks .. " assertions.\n")
