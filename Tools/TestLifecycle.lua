-- Run the actual addon files against a mock game for what happens around
-- the player's clicks: Use my bars unticked while a layout matched the
-- Personal Resource Display to your rows, a bar or the /ccm debug box still
-- being dragged as the game closes its windows (Escape, a loading screen,
-- death), a bar held through a bag or spell change, a rebuild or a fight
-- ending, and What's new or the first-install welcome after a reload or
-- logout before they showed. The mock game is a copy of
-- Tools/TestBars.lua's: Tools/TestMockSync.mjs checks the two match, and
-- with --write copies it across. Tools/TestBars.lua is near the mock game's
-- memory limit, so these run here.
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

-- Lifecycle: the game around it ------------------------------------------------------------------
-- Blizzard's Personal Resource Display, as in Tools/TestBars.lua: where its
-- parts are, its width from Blizzard's own Bar Width setting, and keys the
-- addon only ever reads.

function Proto:GetRect()
    local r = S[self].rect
    if r then return r[1], r[2], r[3], r[4] end
end
local function Display()
    local prd = Blizzard(New("Frame"), "PersonalResourceDisplayFrame")
    S[prd].rect = { 400, 300, 200, 20 }
    rawset(prd, "HealthBarsContainer", New("Frame", prd))
    S[prd.HealthBarsContainer].rect = { 400, 305, 200, 15 }
    rawset(prd, "PowerBar", New("StatusBar", prd))
    S[prd.PowerBar].rect = { 400, 300, 200, 5 }
    rawset(prd, "AlternatePowerBar", false)
    rawset(prd, "ClassFrameContainer", false)
    rawset(prd, "defaultBarWidth", 200)
    rawset(prd, "barWidthPercent", 100)
    getmetatable(prd).__newindex = function(_, key) error("wrote key " .. tostring(key) .. " on Blizzard's display", 2) end
    _G.PersonalResourceDisplayFrame = prd
    return prd
end
-- A fresh game with nothing of the addon's left on screen from the last.
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
-- The same settings, after a reload or the next login.
local function Reload()
    local saved = ForeverEnhancedCooldownManagerDB
    Environment(true)
    _G.FECMFrame, _G.FECMTour, _G.FECMNotes, _G.FECMDebugFrame = nil, nil, nil, nil
    return Load(saved)
end
local function RunTimers()
    for _, timer in ipairs(timers) do timer() end
end

-- Use my bars unticked: the display gets Blizzard's width back ---------------------------------------

do
    Fresh()
    local prd = Display()
    local ns = Load({ useBars = true, prdSkin = false })
    local B, L = ns.Bars, ns.Layout
    for _, name in ipairs({ "Moonfire", "Wrath", "Overpower" }) do B:Assign(name, "cd") end
    L:Apply("wide")
    local function Widths()
        return string.format("%g %g %g", S[prd].width, S[prd.HealthBarsContainer].width, S[prd.PowerBar].width)
    end
    local wide = string.format("%g", L:MatchWidth() or 0)
    Equal(tostring(L:Active()) .. " " .. tostring(tonumber(wide) > 200) .. " " .. Widths(), "true true " .. wide .. " " .. wide .. " " .. wide,
        "Wide: the display as wide as the widest row")
    SlashCmdList.FECM("")
    local w = FECMFrame
    w:Select("general")
    w.useBars:Click()
    Equal(tostring(B:Enabled()) .. " " .. tostring(L:Active()) .. " " .. Widths(), "false false 200 200 200",
        "Use my bars unticked on the General page: the display gets Blizzard's width back at once")
    w.useBars:Click()
    Equal(tostring(L:Active()) .. " " .. Widths(), "true " .. wide .. " " .. wide .. " " .. wide, "ticked again: matched to the rows again")
    -- In a fight the display's width waits for it to end, as always.
    lockdown = true
    w.useBars:Click()
    Equal(Widths(), wide .. " " .. wide .. " " .. wide, "unticked in a fight: the width waits")
    lockdown = false
    Fire("PLAYER_REGEN_ENABLED")
    Equal(Widths(), "200 200 200", "and is Blizzard's once the fight is over")
    -- No layout, so nothing matched: turning the bars on and off never
    -- touches the display's width.
    w.useBars:Click()
    L:TurnOff()
    S[prd].width = 150
    w.useBars:Click()
    w.useBars:Click()
    Equal(tostring(L:Active()) .. string.format(" %g", S[prd].width), "false 150", "bars turned off and on with no layout: untouched")
    w:Hide()
    Equal(#printed, 0, "no errors")
end

-- A bar or the debug box let go when the game closes its windows mid-drag -------------------------

do
    Fresh()
    local ns = Load({ useBars = true })
    local B, L = ns.Bars, ns.Layout
    for _, name in ipairs({ "Moonfire", "Wrath" }) do B:Assign(name, "cd") end
    -- The hidden debug box is let go as Escape closes it.
    SlashCmdList.FECM("debug")
    local box = FECMDebugFrame
    S[box].last.StopMovingOrSizing = nil
    S[box].scripts.OnDragStart(box)
    CloseSpecialWindows()
    Equal(tostring(S[box].shown) .. " " .. tostring(S[box].last.StopMovingOrSizing ~= nil), "false true",
        "the debug box closed mid-drag stops moving")
    B:SetAura("buff", "Thorns", true)
    -- Picks a bar up off its mover, as the mouse does, then moves it here.
    -- While the game is moving it, the addon anchoring it anywhere else
    -- could be the spot the game leaves it at as it's let go: noted.
    local function PickUp(key, x, y)
        local bar = B:Get(key)
        local s = S[bar]
        s.last.StartMoving, s.last.StopMovingOrSizing, s.placedWhileMoving = nil, nil, nil
        rawset(bar, "StartMoving", function(self) S[self].moving, S[self].last.StartMoving = true, {} end)
        rawset(bar, "StopMovingOrSizing", function(self) S[self].moving, S[self].last.StopMovingOrSizing = nil, {} end)
        rawset(bar, "ClearAllPoints", function(self)
            if S[self].moving then S[self].placedWhileMoving = true end
            S[self].points = {}
        end)
        S[bar.mover].scripts.OnDragStart(bar.mover)
        s.cx, s.cy = x, y
        return bar
    end
    SlashCmdList.FECM("")
    local w = FECMFrame
    B:SetUnlocked(true)
    local bar = PickUp("cd", 450, 350)
    Equal(tostring(bar.dragging) .. " " .. tostring(S[bar].last.StartMoving ~= nil) .. " " .. tostring(ns.BarData("cd").x),
        "true true nil", "unlocked: a bar picked up follows the cursor, from its first spot")
    -- Escape (or a loading screen, or death) closes the window, which locks the bars.
    CloseSpecialWindows()
    Equal(tostring(S[w].shown) .. " " .. tostring(B:IsUnlocked()) .. " " .. tostring(S[bar.mover].shown), "false false false",
        "Escape mid-drag: the window closes and the bars lock")
    Equal(tostring(bar.dragging) .. " " .. tostring(S[bar].last.StopMovingOrSizing ~= nil), "nil true",
        "the bar being dragged is let go, not left on the cursor")
    Equal(S[bar].placedWhileMoving, nil, "let go before the bars are laid out again as they lock, so it stays where the mouse left it")
    Equal(ns.BarData("cd").x ~= nil and ns.BarData("cd").y ~= nil, true, "and kept where it was let go")
    -- The game's own let go, should it still come: nothing more happens.
    S[bar].last.StopMovingOrSizing = nil
    S[bar.mover].scripts.OnDragStop(bar.mover)
    Equal(S[bar].last.StopMovingOrSizing, nil, "a late let go does nothing more")
    -- Locked from the Layout page mid-drag: the Buffs bar too.
    w:Show()
    B:SetUnlocked(true)
    local buffs = PickUp("buff", 520, 300)
    Equal(buffs.dragging, true, "the Buffs bar picked up")
    B:SetUnlocked(false)
    Equal(tostring(buffs.dragging) .. " " .. tostring(S[buffs].last.StopMovingOrSizing ~= nil) .. " " .. tostring(ns.BarData("buff").x ~= nil),
        "nil true true", "locked mid-drag: let go and kept")
    -- Its mover hidden any other way mid-drag (the interface hidden, say):
    -- let go all the same.
    B:SetUnlocked(true)
    bar = PickUp("cd", 430, 360)
    bar.mover:Hide()
    Equal(tostring(bar.dragging) .. " " .. tostring(S[bar].last.StopMovingOrSizing ~= nil), "nil true",
        "its mover hidden any other way mid-drag: let go too")
    B:SetUnlocked(false)
    -- Nothing held: locking changes nothing, and a layout stays.
    L:Apply("pyramid")
    B:SetUnlocked(true)
    S[bar].last.StopMovingOrSizing = nil
    B:SetUnlocked(false)
    Equal(tostring(L:Active()) .. " " .. tostring(S[bar].last.StopMovingOrSizing), "true nil", "locking with nothing held leaves the bars and layout be")
    Equal(#printed, 0, "no errors")
end

-- A bar held through a bag or spell change stays on the cursor ----------------------------------

do
    Fresh()
    bagItems = { { itemID = 118, hyperlink = "|cffffffff|Hitem:118|h[Minor Healing Potion]|h|r", iconFileID = 888 } }
    itemCount[118] = 3
    local ns = Load({ useBars = true, notesSeen = "dev" })
    local B, L = ns.Bars, ns.Layout
    B:Assign("Moonfire", "cd")
    B:Assign("item:118", "cd")
    SlashCmdList.FECM("")
    B:SetUnlocked(true)
    local bar, data = B:Get("cd"), ns.BarData("cd")
    local s = S[bar]
    -- The game carrying a bar: from where it sits, under the cursor till the
    -- mouse lets go. Anchored anywhere while it's carried, it goes back to
    -- that spot and stays there, off the cursor (snapped).
    rawset(bar, "StartMoving", function() s.moving, s.snapped, s.home = true, false, { s.cx, s.cy } end)
    rawset(bar, "StopMovingOrSizing", function() s.moving = nil end)
    rawset(bar, "ClearAllPoints", function()
        if s.moving then s.snapped, s.cx, s.cy = true, s.home[1], s.home[2] end
        s.points = {}
    end)
    local function Cursor(x, y)
        if s.moving and not s.snapped then s.cx, s.cy = x, y end
    end
    local function PickUp() S[bar.mover].scripts.OnDragStart(bar.mover) end
    local function LetGo() S[bar.mover].scripts.OnDragStop(bar.mover) end
    -- An event, then the next frame for the timers it queued: each runs now, once.
    local function Settle(event)
        local from = #timers
        Fire(event)
        for i = from + 1, #timers do timers[i]() end
    end
    local function Spot() return string.format("%s %s %s", tostring(data.x), tostring(data.y), tostring(data.point)) end
    local function Held() return tostring(bar.dragging) .. " " .. tostring(s.moving) .. " " .. tostring(s.snapped) end
    s.cx, s.cy = 500, 160 -- where it sits, above the action bar
    -- A plain drag, nothing else happening: where it lands.
    PickUp()
    Cursor(450, 350)
    LetGo()
    local dropped = Spot()
    Equal(Held() .. " " .. tostring(data.x ~= nil), "nil nil false true", "a plain drag: let go and kept where the mouse left it")
    PickUp()
    Cursor(560, 300)
    LetGo()
    Equal(Spot() ~= dropped, true, "dragged somewhere else")
    -- The same drag again, with the game busy while it's held.
    PickUp()
    Cursor(520, 320)
    itemCount[118] = 5
    Settle("BAG_UPDATE_DELAYED")
    Equal(Held(), "true true false", "a bag change while a bar is held: still on the cursor")
    Equal(S[bar.icons[2].count].text, 5, "its icons still change: the potion's new count")
    Cursor(480, 340)
    Book(true)
    Settle("SPELLS_CHANGED")
    Equal(Held(), "true true false", "a rank learned while it's held: still on the cursor")
    Equal(bar.icons[1].spellID, 8925, "its icons still change: Moonfire's new rank")
    B:Rebuild()
    Equal(Held(), "true true false", "the bars rebuilt (a change of yours) while it's held: still on the cursor")
    -- Held through a fight that used the last potion: the bars make room
    -- again as it ends.
    lockdown = true
    Fire("PLAYER_REGEN_DISABLED")
    itemCount[118] = 0
    lockdown = false
    Settle("PLAYER_REGEN_ENABLED")
    Equal(Held(), "true true false", "a fight ending while it's held: still on the cursor")
    Cursor(450, 350)
    LetGo()
    Equal(Held() .. " " .. Spot(), "nil nil false " .. dropped, "let go: it lands where the mouse left it, as a plain drag does")
    -- In a layout: a plain drag takes it out of the layout, where the mouse
    -- left it; held through a rebuild (which stacks the layout again), the same.
    L:Apply("pyramid")
    s.cx, s.cy = 300, 200 -- where the layout put it
    PickUp()
    Cursor(450, 350)
    LetGo()
    dropped = Spot()
    Equal(tostring(L:Active()) .. " " .. tostring(data.x ~= nil), "false true", "a plain drag out of a layout: kept where the mouse left it")
    L:Apply("pyramid")
    s.cx, s.cy = 300, 200 -- where the layout put it
    PickUp()
    Settle("SPELLS_CHANGED")
    B:Rebuild()
    Equal(Held(), "true true false", "held in a layout through a spell change and a rebuild: still on the cursor")
    Cursor(450, 350)
    LetGo()
    Equal(tostring(L:Active()) .. " " .. Spot(), "false " .. dropped, "let go: out of the layout, where the mouse left it, as a plain drag does")
    Equal(#printed, 0, "no errors")
end

-- What's new and the welcome stay due until they show ------------------------------------------------

do
    -- An update: What's new is due a moment after login, never in a fight.
    Fresh()
    local ns = Load({ useBars = true, notesSeen = "0.9.0" })
    Equal(ns.Version() .. " " .. ns.NotesSeen() .. " " .. tostring(FECMNotes), "dev 0.9.0 nil", "an update: What's new due, not noted yet")
    -- A reload or logout before it shows: still due.
    ns = Reload()
    Equal(ns.NotesSeen(), "0.9.0", "a reload before it shows keeps it due")
    -- Still in a fight when it would show, then a logout: still due.
    lockdown = true
    RunTimers()
    Equal(FECMNotes == nil and ns.NotesSeen(), "0.9.0", "waiting for the fight to end: still due")
    lockdown = false
    ns = Reload()
    RunTimers()
    local notes = FECMNotes
    Equal(tostring(notes ~= nil and S[notes].shown) .. " " .. ns.NotesSeen() .. " " .. tostring(notes and notes.seen),
        "true dev 0.9.0", "then it shows, noted as it does, its tour taking in everything since the version seen before")
    ns = Reload()
    RunTimers()
    Equal(FECMNotes, nil, "once per version")

    -- A first install: the welcome, kept over a reload before it shows, when
    -- the settings file isn't empty any more.
    Fresh()
    ns = Load(nil)
    local db = ForeverEnhancedCooldownManagerDB
    Equal(tostring(ns.firstInstall) .. " " .. tostring(ns.NotesSeen()) .. " " .. tostring(db.welcomeDue), "true nil true",
        "a first install: the welcome due, nothing noted yet")
    ns = Reload()
    Equal(tostring(ns.firstInstall) .. " " .. tostring(ns.WelcomeDue()), "false true", "reloaded before it showed: still due")
    RunTimers()
    local box = FECMTour
    Equal(tostring(box ~= nil and S[box].shown and S[box.title].text) .. " " .. tostring(FECMNotes == nil), "WELCOME true",
        "then the welcome shows, not What's new")
    Equal(ns.NotesSeen() .. " " .. tostring(db.welcomeDue), "dev nil", "noted as it shows")
    box.skip:Click()
    ns = Reload()
    RunTimers()
    Equal(FECMFrame == nil and FECMTour == nil and FECMNotes == nil, true, "the welcome only comes once")
    -- Anything but true saved for it: no welcome is due, and it's cleared.
    Fresh()
    ns = Load({ useBars = true, notesSeen = "dev", welcomeDue = "yes" })
    RunTimers()
    Equal(tostring(ForeverEnhancedCooldownManagerDB.welcomeDue) .. " " .. tostring(FECMTour == nil), "nil true",
        "a bad saved value: cleared, no welcome")
    Equal(#printed, 0, "no errors")
end

print = _G.print
Equal(SecretMisuse[1], nil, "no secret misused anywhere")
io.write("Lifecycle checks passed: " .. checks .. " assertions.\n")
