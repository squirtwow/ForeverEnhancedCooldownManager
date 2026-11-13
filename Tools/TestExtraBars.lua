-- Run the actual addon files against a mock game for extra bars and an
-- icon's own size (a player's idea: "more control on size of icons
-- individually, or possibly allow us to have additional bars? I'd like not
-- to have Curse of the Elements on the same bar as my 3 dots"). Nothing
-- changes until a player adds a bar or sizes an icon; an extra bar is a full
-- copy of its kind, kept in the profile with its list (profiles, copies,
-- shared strings and old profiles alike), made out of a fight, and when
-- it goes, laid out empty and gone right out (frames and the game's aura
-- containers can't be thrown away). The mock game is a copy of
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
    assert(not s.handed, "a region an aura icon's animation animates moved")
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
-- Mask textures, and the masks on each texture, in the order added.
function Proto:CreateMaskTexture() return New("MaskTexture", self) end
function Proto:AddMaskTexture(mask)
    local s = S[self]
    s.masks = s.masks or {}
    table.insert(s.masks, mask)
end
function Proto:RemoveMaskTexture(mask)
    local masks = S[self].masks or {}
    for i = #masks, 1, -1 do if masks[i] == mask then table.remove(masks, i) end end
end
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
-- (Like the game: a region an animation handed to an aura icon animates
-- keeps its alpha the game's.)
function Proto:SetAlpha(a)
    assert(not S[self].handed, "the alpha of a region an aura icon's animation animates")
    S[self].alpha = a
end
-- Animations, as the game makes them: a group on a frame or texture (it's
-- that one's, not a frame inside it, so it isn't shown or hidden with it),
-- and the animations in it, each on the group's own frame or texture unless
-- given a target. Each group counts its plays.
function Proto:CreateAnimationGroup()
    local group = New("AnimationGroup")
    S[group].parent, S[group].anims, S[group].plays = self, {}, 0
    return group
end
function Proto:CreateAnimation(kind)
    assert(not S[self].handed, "an animation added to a group handed to an aura icon")
    local anim = New(kind)
    S[anim].parent = self
    table.insert(S[self].anims, anim)
    return anim
end
function Proto:GetAnimations() return table.unpack(S[self].anims) end
function Proto:SetTarget(target) S[self].target = target end
function Proto:GetTarget() local s = S[self]; return s.target or S[s.parent].parent end
function Proto:Play() local s = S[self]; s.plays, s.playing = (s.plays or 0) + 1, true end
function Proto:Stop() S[self].playing = false end
function Proto:IsPlaying() return S[self].playing == true end
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
    -- Blizzard's aura container code run inside the addon's (below), and
    -- whether its icons take shown animations (all of them, unless a test says).
    ContainerRuns, ShownAnimations = {}, nil
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
        if slot == 18 then return RangedWorn end -- (a global: this file's main chunk is at Lua's 200 locals)
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
            local class = ({ [118] = { 0, 1 }, [117] = { 0, 5 }, [2698] = { 9, 0 }, [2512] = { 6, 2 }, [2516] = { 6, 3 },
                [5240] = { 2, 19 }, [2504] = { 2, 2 } })[id] -- (a wand and a bow)
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
        -- (A mage's procs with icons of their own, for the Cooldown pulse's proc rows.)
        GetSpellTexture = function(id) return ({ [12536] = 136170, [400589] = 236221, [400625] = 236218, [400670] = 236227 })[id] or 1 end,
        GetSpellName = function(id)
            return ({ [16870] = "Clearcasting", [16886] = "Nature's Grace", [1243] = "Power Word: Fortitude", [12536] = "Clearcasting",
                [400589] = "Missile Barrage", [400625] = "Heating Up", [400670] = "Fingers of Frost" })[id]
        end,
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
    -- And whether the game keeps one spell's aura secret (SpellAurasSecret[id]:
    -- true, false or SECRET; not there is false), as /ccm debug asks of procs.
    SpellAurasSecret = {}
    _G.C_Secrets = { ShouldAurasBeSecret = function() return lockdown or Typed("boolean", AurasSecret) end,
        ShouldSpellAuraBeSecret = function(id)
            assert(type(id) == "number", "a spell ID")
            if SpellAurasSecret[id] == nil then return false end
            return Typed("boolean", SpellAurasSecret[id])
        end }
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
                -- Like the game: an animation group handed to the icon plays
                -- as the icon comes into sight and stops as it goes
                -- (ApplyVisibility, Blizzard_CustomAuraButton.lua). The group
                -- and each animation's target must sit inside the icon; after
                -- that the group takes no more animations and its targets'
                -- alpha is the game's (AuraContainerUtil.InitializeInboundAnimationGroup).
                -- ShownAnimations: "refuse", a game turning one down; "none",
                -- a game without them. (Kept apart from what its look supplied.)
                local shown = {}
                S[button].shownAnimations = shown
                if ShownAnimations == "none" then
                    rawset(button, "AddAuraShownAnimation", false)
                else
                    rawset(button, "AddAuraShownAnimation", function(_, group)
                        if ShownAnimations == "refuse" then error("bad object in function call") end
                        local function Inside(region)
                            local at = S[region] and S[region].parent
                            while at do
                                if at == button then return true end
                                at = S[at] and S[at].parent
                            end
                            return false
                        end
                        assert(S[group] and S[group].kind == "AnimationGroup" and Inside(group), "an animation group inside the icon")
                        local anims = { group:GetAnimations() }
                        for _, anim in ipairs(anims) do assert(Inside(anim:GetTarget()), "an animation on a region inside the icon") end
                        S[group].handed = true
                        for _, anim in ipairs(anims) do S[anim:GetTarget()].handed = true end
                        table.insert(shown, group)
                    end)
                end
                S[f].made = S[f].made + 1
                if S[f].updating then S[f].late = S[f].late + 1 end
                if options.initializeFrame then options.initializeFrame(button) end
                -- (Then out of sight until it shows an aura, as the game's
                -- first display update leaves it.)
                button:Hide()
                return button
            end
            -- Like the game: what makes it look at all your buffs afresh on
            -- its next frame (UpdateAllAuras, Blizzard_ManagedAuraContainer.lua
            -- and Blizzard_CustomAuraContainer.lua) is noted in S[f].full,
            -- which S[f].Refresh below plays out: a slot or group added,
            -- switched or told its filters, its unit, UpdateAllAuras, its
            -- own OnShow and OnHide, and what it hears while it can be
            -- seen: a full UNIT_AURA (none given, or isFullUpdate: a loading
            -- screen) and, once a slot or group is told buff IDs, UNIT_FLAGS
            -- and UNIT_FACTION for you (a fight starting or ending, a stun,
            -- your PvP flag: Blizzard_AuraContainerUtil.lua
            -- AppendCandidateFilterUnitEvents).
            local function Full() S[f].full = true end
            local function Named(filters)
                if type(filters) == "table" and (filters.includeSpellIDs or filters.excludeSpellIDs) then S[f].flags = true end
            end
            S[f].events.UNIT_AURA, S[f].events.UNIT_FLAGS, S[f].events.UNIT_FACTION = true, true, true
            S[f].scripts.OnEvent = function(_, event, unit, info)
                if not S[f].listening then return end
                if event == "UNIT_AURA" then
                    if unit == S[f].unit and (type(info) ~= "table" or info.isFullUpdate) then Full() end
                elseif unit == "player" and S[f].flags then
                    Full()
                end
            end
            rawset(f, "AddAuraSlot", function(_, key, filter, options)
                Guard()
                local button = Make(options)
                slots[key] = { filter = filter, button = button, enabled = true, supplied = S[button].supplied }
                Named(options.candidateFilters)
                Full()
                return button
            end)
            rawset(f, "SetAuraSlotEnabled", function(_, key, enabled)
                Guard(); assert(type(enabled) == "boolean"); slots[key].enabled = enabled; Full()
            end)
            rawset(f, "SetAuraSlotCandidateFilters", function(_, key, filters)
                Guard(); slots[key].filters = filters; Named(filters); Full()
            end)
            -- Like the game: its unit set, it signs up for that unit's aura
            -- events, but only while it can be seen (UpdateEventRegistrations
            -- asks IsVisible); its own OnShow and OnHide below sign it up
            -- again or off. listening: whether it hears its auras change.
            rawset(f, "SetUnit", function(_, unit)
                if S[f].unit ~= unit then
                    S[f].listening = f:IsVisible()
                    Full()
                end
                S[f].unit = unit
            end)
            rawset(f, "UpdateAllAuras", function()
                S[f].refreshes = (S[f].refreshes or 0) + 1
                Full()
            end)
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
                    Full()
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
                Named(options.candidateFilters)
                Full()
            end)
            rawset(f, "GetAuraGroupFrameCount", function(_, key) return groups[key] and #groups[key].frames or 0 end)
            rawset(f, "GetAuraGroupFrame", function(_, key, i) return groups[key] and groups[key].frames[i] end)
            rawset(f, "SetAuraGroupMaxFrameCount", function(_, key, count)
                Guard()
                assert(type(count) == "number" and count >= 0 and count == math.floor(count), "a whole number of icons")
                groups[key].max = count
            end)
            rawset(f, "SetAuraGroupEnabled", function(_, key, enabled)
                Guard(); assert(type(enabled) == "boolean"); groups[key].enabled = enabled; Full()
            end)
            rawset(f, "SetAuraGroupCandidateFilters", function(_, key, filters)
                Guard(); groups[key].filters = filters; Named(filters); Full()
            end)
            rawset(f, "SetAuraGroupLayout", function(_, key, layout) Guard(); groups[key].layout = layout end)
            rawset(f, "SetScale", function(_, scale) Guard(); S[f].scale = scale end)
            -- The container's own update, from its OnUpdate after UNIT_AURA or
            -- a refresh: each switched-on group takes the auras it matches, up
            -- to its most, with icons from its pool, making a batch more when
            -- the pool runs dry (Blizzard_AuraContainerGroups.lua
            -- RefreshAuraGroup). Auras are { id =, harmful =, mine =, other = }
            -- (other: another player's). The filter string's PLAYER keeps only
            -- yours; isFromPlayerOrPlayerPet means any player's. Any call into
            -- the addon's own files while it runs is counted.
            local function Matches(group, aura)
                local tokens = {}
                for token in tostring(group.filter):gmatch("[^|]+") do
                    assert(token == "HELPFUL" or token == "HARMFUL" or token == "PLAYER", "a filter the game knows: " .. token)
                    tokens[token] = true
                end
                if (tokens.HARMFUL == true) ~= (aura.harmful == true) then return false end
                if tokens.PLAYER and aura.mine ~= true then return false end
                local filters = group.filters or {}
                if filters.includeSpellIDs and not filters.includeSpellIDs[aura.id] then return false end
                local player = aura.mine == true or aura.other == true
                if filters.isFromPlayerOrPlayerPet ~= nil and filters.isFromPlayerOrPlayerPet ~= player then return false end
                return true
            end
            -- Each icon in use comes into sight and the rest go, as the
            -- game shows and hides them (running OnShow and OnHide inside
            -- them), playing an icon's shown animations as it comes into
            -- sight and stopping them as it goes.
            local function Sight(button, on)
                local was = S[button].shown
                button:SetShown(on)
                for _, group in ipairs(S[button].shownAnimations) do
                    if on and not was then group:Play() elseif not on then group:Stop() end
                end
            end
            -- (Your buffs as it last saw them are kept for Refresh.)
            S[f].Update = function(auras)
                S[f].auras = auras
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
                        local using = {}
                        for _, button in ipairs(group.active) do using[button] = true end
                        for _, button in ipairs(group.frames) do Sight(button, using[button] == true) end
                    end
                    -- A slot's one icon shows the first aura it matches, if any.
                    for _, slot in pairs(slots) do
                        local lit = false
                        for _, aura in ipairs(slot.enabled and auras or {}) do
                            if Matches(slot, aura) then
                                lit = true
                                break
                            end
                        end
                        Sight(slot.button, lit)
                    end
                end)
                debug.sethook()
                S[f].updating = false
                assert(ok, err)
            end
            -- Its next frame after a full refresh was asked for (S[f].full),
            -- while it can be seen: every icon showing goes, its animations
            -- stopped, then each takes its aura again and comes into sight,
            -- playing them again (ResetFrameAssignments, then
            -- RefreshFrameAssignments). auras: your buffs now, else as it
            -- last saw them. True when it ran.
            S[f].Refresh = function(auras)
                if not (S[f].full and f:IsVisible()) then return false end
                S[f].full = false
                local now = auras or S[f].auras or {}
                S[f].Update({})
                S[f].Update(now)
                return true
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

-- Extra bars: the game around it ------------------------------------------------------------------
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
local FILES = { "Core.lua", "SquirtVersions.lua", "Style.lua", "Skin.lua", "Resource.lua", "CastBar.lua", "RaidTimers.lua", "Ranks.lua", "Forms.lua", "Spells.lua",
    "Keybinds.lua", "Buffs.lua", "IconAuras.lua", "Bars.lua", "Pulse.lua", "Layout.lua", "Theme.lua", "BarPage.lua",
    "LayoutPage.lua", "CastBarPage.lua", "RaidTimersPage.lua", "PulsePage.lua", "ProfileShare.lua", "ProfileMenu.lua",
    "Window.lua", "Tour.lua", "MinimapButton.lua", "Notes.lua", "Debug.lua" }

-- A fresh game, logged in with these saved settings.
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
-- own code), as Tools/TestShare.lua has it, to make strings of any shape.
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
    return "FECM1:" .. H.Base64(H.Pack(data))
end

-- The bars you have now.
function H.Keys(ns)
    return table.concat(ns.BAR_KEYS, " ")
end

-- A container's slots for entries (b1..b16): how many there are and how
-- many are on.
function H.Slots(container)
    local made, on = 0, 0
    for key, slot in pairs(S[container].slots) do
        if key:find("^b") then
            made = made + 1
            if slot.enabled then on = on + 1 end
        end
    end
    return made .. " slots, " .. on .. " on"
end

-- A container's packed group for entry i: whether it's on, and its spells.
function H.Group(container, i)
    local group = S[container].groups["g" .. i]
    if not group then return "none" end
    local ids = {}
    for id in pairs(group.filters and group.filters.includeSpellIDs or {}) do ids[#ids + 1] = id end
    table.sort(ids)
    -- (Every rank's: the first said, with how many.)
    return tostring(group.enabled) .. " " .. tostring(ids[1]) .. "+" .. (#ids - 1)
end

-- A frame's first point: where it's held on its bar, x and y.
function H.At(frame)
    local p = S[frame].points[1] or {}
    local function N(v) return type(v) == "number" and ("%g"):format(v) or tostring(v) end
    return tostring(p[1]) .. " " .. N(p[4]) .. " " .. N(p[5])
end

-- A control's note in the footer.
function H.Note(control)
    return type(control.hint) == "function" and control.hint(control) or tostring(control.hint)
end

-- Off by default, then Debuffs 2 (the player's case) ---------------------------------------------
-- No extra bar until one is added: the four bars, nothing kept or made. On
-- the list's "+ Add a bar" under Debuffs, Debuffs 2: a second Debuffs bar with a
-- container of its own watching your target, made with the bar, its own
-- list (Curse of the Elements apart from three damage over time spells),
-- its own options, as the Debuffs bar's. Each Debuffs bar follows a new
-- target.
;(function()
    local ns = Start({ useBars = true, notesSeen = "dev", helpSeen = true })
    local B = ns.Bars
    local profile = ns.ProfileLists()
    local made = #containers
    Equal(table.concat({ H.Keys(ns), tostring(profile.extraBars), tostring(profile.debuff2), tostring(B:Get("debuff2")), made,
        tostring(ns.HasBar("debuff2")), tostring(rawget(ForeverEnhancedCooldownManagerDB.bars, "debuff2")) },
        " | "), "cd util buff debuff | nil | nil | nil | 2 | false | nil",
        "off by default: the four bars, no extra bar kept or made, the two containers as before")
    local can, key = ns.CanAddBar("debuff")
    Equal(tostring(can) .. " " .. tostring(key) .. " | " .. tostring((ns.CanAddBar("nothing"))) .. " " .. select(2, ns.CanAddBar("nothing")),
        "true debuff2 | false There's no such bar.", "a Debuffs bar can be added: Debuffs 2; nothing else by another name")
    local ok, added, said = B:AddBar("debuff")
    local bar = B:Get("debuff2")
    local box = S[bar.container]
    Equal(table.concat({ tostring(ok), added, said, H.Keys(ns), H.Text(profile.extraBars), H.Text(profile.debuff2),
        tostring(#containers - made), box.unit, H.Slots(bar.container), tostring(bar.holds), tostring(InSight(bar)) }, " | "),
        "true | debuff2 | Debuffs 2 added. Tick spells for it in the list below. | cd util buff debuff debuff2 | {[\"debuff2\"]=true}"
        .. " | {} | 1 | target | 16 slots, 0 on | true | false",
        "added: kept in the profile with an empty list, after Debuffs; one more container, watching your target, made with the"
        .. " bar (16 slots, all off), the bar empty so not seen")
    -- The player's case: three on Debuffs, one on Debuffs 2.
    B:SetAura("debuff", "Moonfire", true)
    B:SetAura("debuff2", "Wrath", true)
    local debuff = B:Get("debuff")
    Equal(H.Group(debuff.container, 1) .. " | " .. H.Group(debuff.container, 2) .. " | " .. H.Group(bar.container, 1) .. " | "
        .. H.Group(bar.container, 2) .. " | " .. tostring(S[bar.container].groups.g1.filters.isFromPlayerOrPlayerPet) .. " | "
        .. H.Text(ns.BarData("debuff").spells) .. " " .. H.Text(ns.BarData("debuff2").spells) .. " | " .. tostring(InSight(bar)),
        "true 8921+9 | none | true 5176+7 | none | true | {[1]=\"Moonfire\"} {[1]=\"Wrath\"} | true",
        "each bar its own icons: Moonfire on Debuffs, Wrath on Debuffs 2 alone, your own only, the bar seen now")
    -- Its own options, as a Debuffs bar's: missing ones greyed and kept with no target, ticks counted.
    B:SetOption("debuff2", "showMissing", true)
    B:SetOption("debuff2", "greyedNoTarget", true)
    B:SetOption("debuff2", "tickFrom", 0)
    B:SetAura("debuff2", "Moonfire", true)
    local counted = B:SetCountTicks("debuff2", "Moonfire", true)
    local data, base = ns.BarData("debuff2"), ns.BarData("debuff")
    Equal(table.concat({ tostring(data.showMissing), tostring(data.greyedNoTarget), tostring(data.tickFrom), tostring(counted),
        tostring(B:CountsTicks("debuff2", "Moonfire")), tostring(B:CountsTicks("debuff", "Moonfire")), tostring(base.showMissing),
        H.Slots(bar.container), tostring(ns.BuffBar:KeepGreyed(data)) }, " "),
        "true true 0 true true false false 16 slots, 2 on true",
        "its own options, kept as a Debuffs bar's (missing greyed, kept with no target, from 0), Count ticks its own: Debuffs"
        .. " left as it was; fixed spots, a slot each")
    -- A new target: both Debuffs bars look again at once.
    local before = { S[debuff.container].refreshes or 0, S[bar.container].refreshes or 0 }
    target = true
    Fire("PLAYER_TARGET_CHANGED")
    Equal(((S[debuff.container].refreshes or 0) - before[1]) .. " " .. ((S[bar.container].refreshes or 0) - before[2]), "1 1",
        "a new target: each Debuffs bar looks again")
    -- Its page's Only when missing and Swap with my form: not a Debuffs bar's.
    Equal(tostring(B:SetOnlyWhenMissing("debuff2", "Wrath", true)) .. " " .. tostring(ns.Swaps("debuff2")), "false false",
        "Only when missing stays a Buffs bar's; no Swap with my form")
    -- Two of each kind (a player's idea: a third cooldown bar): Debuffs 3
    -- next, with a container of its own; a fourth Debuffs bar is turned away.
    local again, third = B:AddBar("debuff")
    local fourth, why = B:AddBar("debuff")
    local bar3 = B:Get("debuff3")
    Equal(table.concat({ tostring(again), third, tostring(fourth), why, H.Keys(ns), H.Text(profile.extraBars),
        tostring(#containers - made), tostring(bar3 and S[bar3.container].unit), tostring(bar3 and bar3.container ~= bar.container) }, " | "),
        "true | debuff3 | false | Debuffs 2 and Debuffs 3 are there already: two extra bars of a kind at most. | cd util buff debuff"
        .. " debuff2 debuff3 | {[\"debuff2\"]=true,[\"debuff3\"]=true} | 2 | target | true",
        "two of each kind: Debuffs 3 next, its own container watching your target; a fourth Debuffs bar turned away, saying why")
    Equal(#printed, 0, "no errors")
end)()

-- Buffs 2: Only show missing, Only when missing and your buffs heard ------------------------------
-- A second Buffs bar watches you, with every choice the Buffs bar has: a
-- buff ticked Only when missing there has the driver hear your buffs, as on
-- the Buffs bar, and is read only out of combat.
;(function()
    local ns = Start({ useBars = true, notesSeen = "dev", helpSeen = true })
    local B = ns.Bars
    B:AddBar("buff")
    local bar = B:Get("buff2")
    local heard = tostring(S[B.driver].events.UNIT_AURA == true)
    B:SetAura("buff2", "Thorns", true)
    local only = B:SetOnlyWhenMissing("buff2", "Thorns", true)
    Equal(table.concat({ S[bar.container].unit, heard, tostring(only), tostring(B:OnlyWhenMissing("buff2", "Thorns")),
        tostring(B:OnlyWhenMissing("buff", "Thorns")), tostring(S[B.driver].events.UNIT_AURA == true), tostring(ns.BuffBar:Hides(bar, 1)) }, " "),
        "player false true true false true true",
        "Buffs 2 watches you; Thorns ticked Only when missing there, not on Buffs; your buffs heard now, for that bar")
    B:SetOption("buff2", "onlyMissing", true)
    B:SetOption("buff", "onlyMissing", true)
    Equal(tostring(ns.BarData("buff2").onlyMissing) .. " " .. tostring(ns.BarData("buff").onlyMissing), "true true",
        "Only show missing kept on Buffs 2 as on Buffs (a Debuffs bar never keeps it)")
    B:SetOption("buff2", "onlyMissing", false)
    B:SetOption("buff", "onlyMissing", false)
    B:SetOnlyWhenMissing("buff2", "Thorns", false)
    Equal(tostring(S[B.driver].events.UNIT_AURA == true), "false", "nothing ticked: your buffs no longer heard")
    -- Both Buffs bars showing only missing buffs: one answered in full, the
    -- other's kept secret. The secret one is read again four times at most,
    -- never more because the other one answered (no polling).
    B:SetAura("buff", "Thorns", true)
    B:SetAura("buff2", "Wrath", true)
    B:SetOption("buff", "onlyMissing", true)
    B:SetOption("buff2", "onlyMissing", true)
    PlayerAuras[467], PlayerAuras[5176] = true, SECRET
    local function Round()
        local list = timers
        timers = {}
        for _, fn in ipairs(list) do fn() end
        S[B.driver].scripts.OnUpdate(B.driver, 0)
    end
    Fire("UNIT_AURA", "player")
    for _ = 1, 10 do Round() end
    local reads = AuraReads
    for _ = 1, 10 do Round() end
    Equal(tostring(B:Get("buff").unread) .. " " .. tostring(bar.unread) .. " " .. (AuraReads - reads) .. " " .. #timers, "nil true 0 0",
        "one Buffs bar answered, the other kept secret: read again a few times, then nothing more until the game says")
    PlayerAuras[467], PlayerAuras[5176] = nil, nil
    B:SetOption("buff", "onlyMissing", false)
    B:SetOption("buff2", "onlyMissing", false)
    -- Warn at on Buffs 2, in a spot of its own: its time left read out of a fight, as on Buffs.
    B:SetOption("buff2", "showMissing", true)
    B:SetWarnAt("buff2", "Thorns", 600)
    Equal(tostring(S[B.driver].events.UNIT_AURA == true) .. " " .. tostring(ns.BuffBar:LowWatch(ns.BarData("buff2"), "buff2")) .. " "
        .. tostring(ns.BuffBar:LowWatch(ns.BarData("buff"), "buff")), "true true false", "Thorns warned on Buffs 2: your buffs heard for it, not for Buffs")
    Equal(#printed, 0, "no errors")
end)()

-- Cooldowns 2: a spell on one cooldown bar at a time -------------------------------------------------
-- Ticking a spell on Cooldowns 2 takes it off Cooldowns, and back; its icon
-- is laid out on the bar it's on. No Swap with my form on an extra bar.
;(function()
    local ns = Start({ useBars = true, notesSeen = "dev", helpSeen = true, bars = { cd = { spells = { "Moonfire", "Wrath" } } } })
    local B = ns.Bars
    B:AddBar("cd")
    B:Assign("Moonfire", "cd2")
    local cd, cd2 = B:Get("cd"), B:Get("cd2")
    Equal(table.concat({ H.Keys(ns), H.Text(ns.BarData("cd").spells), H.Text(ns.BarData("cd2").spells), tostring(B:Find("Moonfire")),
        cd.count .. " " .. cd2.count, tostring(cd2.icons[1].name), tostring(InSight(cd2)) }, " | "),
        "cd cd2 util buff debuff | {[1]=\"Wrath\"} | {[1]=\"Moonfire\"} | cd2 | 1 1 | Moonfire | true",
        "Moonfire moved to Cooldowns 2: off Cooldowns, one icon each, Cooldowns 2 seen")
    B:Assign("Moonfire", "util")
    Equal(H.Text(ns.BarData("cd2").spells) .. " " .. H.Text(ns.BarData("util").spells) .. " " .. tostring(B:Find("Moonfire")),
        "{} {[1]=\"Moonfire\"} util", "and on to Utility: off Cooldowns 2")
    B:Assign("Wrath", "cd2")
    -- Swap with my form: Cooldowns and Utility only.
    ns.SetSwaps("cd2", true)
    B:SetOption("cd2", "swapForm", true)
    Equal(tostring(ns.Swaps("cd2")) .. " " .. tostring(ns.ProfileLists().swapForm) .. " " .. tostring(ns.CanSwap("cd2")) .. " "
        .. tostring(ns.CanSwap("cd")), "false nil false true", "no Swap with my form on Cooldowns 2, none kept")
    -- A spell on Cooldowns' list for a form only (Swap with my form), ticked
    -- on Cooldowns 2 in no form: off that form's list too.
    local store = ns.ProfileLists()
    B:Assign("Wrath", "cd")
    store.swapForm, store.forms = { cd = true }, { [5] = { cd = { "Wrath" } } }
    B:Assign("Wrath", nil)
    B:Assign("Wrath", "cd2")
    Equal(tostring(ns.OwnFormList(5)) .. " " .. H.Text(store.forms[5].cd) .. " " .. H.Text(store.cd2) .. " " .. H.Text(store.cd),
        "true {} {[1]=\"Wrath\"} {}", "on Cooldowns 2 now: off Cooldowns' list for Bear Form too")
    store.swapForm, store.forms = nil, nil
    -- A spell on both (a profile made from a string): Cooldowns keeps it, Cooldowns 2 gives way.
    table.insert(store.cd, "Wrath")
    B:Rebuild()
    Equal(H.Text(store.cd) .. " " .. H.Text(store.cd2), "{[1]=\"Wrath\"} {}", "a spell on both: Cooldowns keeps it, Cooldowns 2 lets it go")
    Equal(#printed, 0, "no errors")
end)()

-- Four at most, never in a fight, and taken away again ---------------------------------------------
-- A fifth extra bar is turned away, saying why; in a fight nothing is added
-- or removed. Remove bar takes it out of your profile with its spells and
-- their choices: its frame can't be thrown away, so it's laid out with
-- nothing on it (every slot off) and goes right out, as a bar taken out of
-- your layout does; your buffs are no longer heard for it.
;(function()
    local ns = Start({ useBars = true, notesSeen = "dev", helpSeen = true })
    local B = ns.Bars
    B:AddBar("debuff")
    B:AddBar("buff")
    B:AddBar("cd")
    B:AddBar("util")
    local fifth, why = B:AddBar("cd")
    Equal(tostring(fifth) .. " " .. why .. " | " .. H.Keys(ns) .. " | " .. tostring(B:Get("cd3")),
        "false You have 4 extra bars already: remove one on its page first. | cd cd2 util util2 buff buff2 debuff debuff2 | nil",
        "four at most: a fifth (Cooldowns 3) is turned away, saying why, nothing made")
    lockdown = true
    local removed, inFight = B:RemoveBar("buff2")
    local addedInFight, said = ns.CanAddBar("cd")
    lockdown = false
    Equal(tostring(removed) .. " " .. inFight .. " | " .. tostring(addedInFight) .. " " .. said .. " | " .. H.Keys(ns),
        "false Finish combat first. | false You have 4 extra bars already: remove one on its page first. | cd cd2 util util2 buff buff2"
        .. " debuff debuff2", "in a fight: nothing removed")
    -- Buffs 2 with Thorns, ticked Only when missing, glowing and warned; then removed.
    B:SetAura("buff2", "Thorns", true)
    B:SetOnlyWhenMissing("buff2", "Thorns", true)
    B:SetGlowMissing("buff2", "Thorns", true)
    B:SetWarnAt("buff2", "Thorns", 10)
    B:SetOwnSize("buff2", "Thorns", 120)
    ns.Bars:SetSpellLook("Thorns", "font", "arial")
    B:SetOption("buff2", "selfDebuffs", true)
    local bar = B:Get("buff2")
    local self = tostring(S[bar.container].groups.self and S[bar.container].groups.self.enabled)
    local ok, message = B:RemoveBar("buff2")
    local store = ns.ProfileLists()
    Equal(table.concat({ tostring(ok), message, H.Keys(ns), H.Text(store.extraBars), tostring(store.buff2),
        tostring(store.onlyWhenMissing.buff2), tostring(store.glowMissing.buff2), tostring(store.warnAt), tostring(store.iconSize),
        tostring(store.spellLook) }, " | "),
        "true | Buffs 2 removed, with its spells. | cd cd2 util util2 buff debuff debuff2 | {[\"cd2\"]=true,[\"debuff2\"]=true,"
        .. "[\"util2\"]=true} | nil | nil | nil | nil | nil | nil",
        "removed: out of the profile with its list and its entries' choices, Thorns' look with it (on no other list)")
    Equal(table.concat({ H.Slots(bar.container), tostring(bar.count), tostring(bar.gone), tostring(InSight(bar)),
        tostring(S[B.driver].events.UNIT_AURA == true), tostring(ns.HasBar("buff2")), tostring(B:Get("buff2") == bar),
        self .. "->" .. tostring(S[bar.container].groups.self.enabled) }, " "),
        "16 slots, 0 on 0 true false false false true true->false",
        "its frame emptied, every slot off (your debuffs on you too), gone right out; your buffs no longer heard")
    -- Unlocked or in Edit Mode, a removed bar stays out of sight.
    B:SetUnlocked(true)
    Equal(tostring(InSight(bar)) .. " " .. tostring(bar.mover:IsShown()), "false false", "unlocked: a removed bar stays out of sight")
    B:SetUnlocked(false)
    -- Added again: back, empty, in the same frame and container.
    local container = bar.container
    B:AddBar("buff")
    Equal(H.Keys(ns) .. " | " .. tostring(B:Get("buff2") == bar) .. " " .. tostring(bar.container == container) .. " | "
        .. H.Text(ns.BarData("buff2").spells), "cd cd2 util util2 buff buff2 debuff debuff2 | true true | {}", "added again: the same frame, empty")
    -- A removed Cooldowns 2: its icons hidden, their range no longer watched.
    B:RemoveBar("buff2")
    B:Assign("Moonfire", "cd2")
    local cd2 = B:Get("cd2")
    local icon = cd2.icons[1]
    B:RemoveBar("cd2")
    Equal(tostring(icon:IsShown()) .. " " .. tostring(icon.spellID) .. " " .. tostring(cd2:IsShown()) .. " " .. tostring((B:Find("Moonfire")))
        .. " | " .. H.Text(ns.BarData("cd2").spells), "false nil false nil | {}", "a removed Cooldowns 2: its icon hidden, nothing watched, Moonfire on no bar")
    Equal(#printed, 0, "no errors")
end)()

-- Profiles: switched, copied, made from a string, repaired --------------------------------------------
-- An extra bar is the profile's: switching to one without it takes it away,
-- back to its own brings it back with its list; a copy carries it; an old
-- profile loads unchanged; saved nonsense is repaired.
;(function()
    local ns = Start({ useBars = true, notesSeen = "dev", helpSeen = true })
    local B = ns.Bars
    local mine = ns.ProfileName()
    B:AddBar("debuff")
    B:SetAura("debuff2", "Wrath", true)
    B:SetOwnSize("debuff2", "Wrath", 80)
    local bar = B:Get("debuff2")
    ns.NewProfile("Plain")
    Equal(H.Keys(ns) .. " | " .. tostring(InSight(bar)) .. " " .. H.Slots(bar.container) .. " " .. H.Group(bar.container, 1) .. " | "
        .. tostring(ns.ProfileLists().extraBars), "cd util buff debuff | false 16 slots, 0 on false 5176+7 | nil",
        "a profile without it: the bar gone, its icon off")
    ns.UseProfile(mine)
    Equal(H.Keys(ns) .. " | " .. tostring(InSight(bar)) .. " " .. H.Group(bar.container, 1) .. " | " .. H.Text(ns.BarData("debuff2").spells),
        "cd util buff debuff debuff2 | true true 5176+7 | {[1]=\"Wrath\"}", "back to its own: the bar back with its list")
    -- Positions per profile: Debuffs 2's spot kept with the four bars', none
    -- for a bar never added.
    ns.SetPlacePerProfile(true)
    local place = ns.ProfileLists().place
    Equal(tostring(place.bars.debuff2 ~= nil) .. " " .. tostring(place.bars.cd ~= nil) .. " " .. tostring(place.bars.cd2),
        "true true nil", "positions per profile: Debuffs 2's spot kept with the four's, none for a bar never added")
    ns.SetPlacePerProfile(false)
    -- Copied: the copy has it too, its own tables.
    ns.CopyProfile("Copy")
    local copy, from = ns.ProfileLists(), ForeverEnhancedCooldownManagerDB.profiles[mine]
    Equal(H.Text(copy.extraBars) .. " " .. H.Text(copy.debuff2) .. " " .. H.Text(copy.iconSize) .. " " .. tostring(copy.debuff2 ~= from.debuff2)
        .. " " .. tostring(copy.iconSize.debuff2 ~= from.iconSize.debuff2) .. " | " .. H.Keys(ns),
        "{[\"debuff2\"]=true} {[1]=\"Wrath\"} {[\"debuff2\"]={[\"Wrath\"]=80}} true true | cd util buff debuff debuff2",
        "a copy carries the bar, its list and the icon's size, sharing no table")
    -- Old and broken saved profiles, repaired as they load.
    local saved = { useBars = true, notesSeen = "dev", helpSeen = true, chars = { ["Player-1-0001"] = "Odd" }, profiles = {
        Odd = { cd = { "Moonfire" }, util = {}, buff = {}, debuff = {}, debuff2 = { "Wrath" }, cd2 = { "Wrath" }, util2 = { 5 },
            cd3 = { "Moonfire", "Overpower" }, debuff3 = { "Wrath" },
            extraBars = { debuff2 = true, cd2 = true, util2 = true, cd3 = true, debuff3 = true, cd4 = true, bogus = true },
            glowMissing = { debuff2 = { Wrath = true }, debuff3 = { Wrath = true } },
            iconSize = { cd = { Moonfire = 130, Wrath = 120 }, cd2 = { Wrath = 49 }, debuff3 = { Wrath = 100 }, nobar = { Moonfire = 90 } } },
        Old = { cd = { "Moonfire" }, util = {}, buff = {}, debuff = {}, debuff2 = { "Wrath" } },
        Junk = { cd = {}, util = {}, buff = {}, debuff = {}, extraBars = "yes" } } }
    ns = Start(saved)
    local odd, old, junk = saved.profiles.Odd, saved.profiles.Old, saved.profiles.Junk
    Equal(table.concat({ H.Text(odd.extraBars), tostring(odd.debuff3), H.Text(odd.cd2), H.Text(odd.util2), H.Text(odd.cd3),
        tostring(odd.glowMissing.debuff3) .. " " .. H.Text(odd.glowMissing.debuff2), H.Text(odd.iconSize), H.Keys(ns),
        tostring(ns.Bars:Get("cd2") and ns.Bars:Get("cd2").count), tostring(ns.Bars:Get("cd3") and ns.Bars:Get("cd3").count) }, " | "),
        "{[\"cd2\"]=true,[\"cd3\"]=true,[\"debuff2\"]=true,[\"util2\"]=true} | nil | {[1]=\"Wrath\"} | {} | {[1]=\"Overpower\"}"
        .. " | nil {[\"Wrath\"]=true} | {[\"cd\"]={[\"Moonfire\"]=130}} | cd cd2 cd3 util util2 buff debuff debuff2 | 1 | 1",
        "repaired: the extra bars it knows, four at most in order (Debuffs 3 let go with its list and choices, Cooldowns 4 and the"
        .. " like unknown), each list repaired (Moonfire stays on Cooldowns, off Cooldowns 3), only sizes this version keeps for names"
        .. " on that bar; logged in with it, Cooldowns 2 and 3 made with their icons")
    Equal(tostring(old.extraBars) .. " " .. tostring(old.debuff2) .. " " .. tostring(old.iconSize) .. " | " .. tostring(junk.extraBars),
        "nil nil nil | nil", "an old profile: no extra bar and nothing added (a list for a bar it hasn't goes); nonsense goes")
    Equal(#printed, 0, "no errors")
end)()

-- Sharing and importing --------------------------------------------------------------------------------
-- A string carries the extra bars (x), their lists and settings, and the
-- icons' own sizes (z). Read back the same, said in the description, made
-- into a profile that has them; a list for an extra bar the string doesn't
-- name, more than four, keys no version has, or odd sizes are left out and
-- counted.
;(function()
    local ns = Start({ useBars = true, notesSeen = "dev", helpSeen = true })
    local B, P = ns.Bars, ns.ProfileShare
    B:AddBar("debuff")
    B:SetAura("debuff", "Moonfire", true)
    B:SetAura("debuff2", "Wrath", true)
    B:SetOption("debuff2", "showMissing", true)
    B:SetOption("debuff2", "size", 48)
    B:SetOwnSize("debuff2", "Wrath", 125)
    B:Assign("Moonfire", "cd")
    B:SetOwnSize("cd", "Moonfire", 75)
    local text = P.Export()
    local shared = P.Read(text)
    Equal(table.concat({ H.Text(shared.extras), H.Text(shared.lists.debuff2), H.Text(shared.sizes), tostring(shared.skipped),
        tostring(shared.setup.bars.debuff2.size), P.Describe(shared) }, " | "),
        "{[\"debuff2\"]=true} | {[1]=\"Wrath\"} | {[\"cd\"]={[\"Moonfire\"]=75},[\"debuff2\"]={[\"Wrath\"]=125}} | 0 | 48 | Holds 3 bar"
        .. " entries, with an extra bar, own sizes for 2 icons and its look and layout.",
        "shared: the extra bar, its list and settings, the icons' sizes, said in the description")
    local ok = ns.ImportProfile("Friend", shared, false)
    local friend = ns.ProfileLists()
    Equal(tostring(ok) .. " | " .. ns.ProfileName() .. " | " .. H.Text(friend.extraBars) .. " " .. H.Text(friend.debuff2) .. " "
        .. H.Text(friend.iconSize) .. " | " .. H.Keys(ns) .. " | " .. tostring(P.Export() == text),
        "true | Friend | {[\"debuff2\"]=true} {[1]=\"Wrath\"} {[\"cd\"]={[\"Moonfire\"]=75},[\"debuff2\"]={[\"Wrath\"]=125}} | cd util"
        .. " buff debuff debuff2 | true", "imported: the new profile has the bar, its list and the sizes; it shares the same string back")
    -- Odd strings: a list for an extra bar it doesn't name, a fifth extra
    -- bar, keys no version has (Cooldowns 4), a spell on two cooldown bars,
    -- odd sizes.
    local odd = P.Read(H.String({ l = { cd = { "Moonfire" }, util = {}, buff = {}, debuff = {}, debuff2 = { "Wrath" }, cd2 = { "Wrath" },
        util2 = {}, buff2 = {}, cd3 = { "Moonfire", "Overpower" }, debuff3 = { "Wrath" }, cd4 = { "Wrath" } },
        x = { cd2 = true, util2 = true, buff2 = true, cd3 = true, debuff3 = true, cd4 = true, nope = true },
        z = { cd = { Moonfire = 151, Wrath = 100 }, cd2 = { Wrath = 50 }, debuff2 = { Wrath = 100 }, cd3 = { Overpower = 120 } } }))
    Equal(table.concat({ H.Text(odd.extras), tostring(odd.lists.debuff2), tostring(odd.lists.debuff3), H.Text(odd.lists.cd3),
        H.Text(odd.lists.buff2), H.Text(odd.sizes), tostring(odd.skipped) }, " | "),
        "{[\"buff2\"]=true,[\"cd2\"]=true,[\"cd3\"]=true,[\"util2\"]=true} | nil | nil | {[1]=\"Overpower\"} | {} | {[\"cd2\"]={[\"Wrath\"]=50},"
        .. "[\"cd3\"]={[\"Overpower\"]=120}} | 10", "odd: four extra bars kept (in order, Cooldowns 3 among them), the fifth (Debuffs 3)"
        .. " and unknown ones (Cooldowns 4) left out, lists for bars it doesn't keep left out, Moonfire kept on Cooldowns and off"
        .. " Cooldowns 3, odd sizes left out: each counted")
    -- An older string (no x, no z): nothing new.
    local older = P.Read(H.String({ a = "1.9.1", l = { cd = { "Moonfire" }, util = {}, buff = {}, debuff = {} } }))
    Equal(H.Text(older.extras) .. " " .. H.Text(older.sizes) .. " " .. older.skipped, "{} {} 0", "a string from before: no extra bar, no sizes")
    Equal(#printed, 0, "no errors")
end)()

-- The Layout page and the stack ----------------------------------------------------------------------------
-- A layout puts an extra bar under the display as it's added, in a row of
-- its own; it can be taken out and put back like any bar; once removed, or
-- with a profile without it, its row isn't stacked or drawn.
;(function()
    local ns = Start({ useBars = true, notesSeen = "dev", helpSeen = true })
    local B, L = ns.Bars, ns.Layout
    L:Apply("pyramid")
    B:AddBar("debuff")
    B:SetAura("debuff2", "Wrath", true)
    local layout = ns.LayoutData()
    Equal(H.Text(layout.below) .. " | " .. table.concat(L:Rows(), " "), "{[1]=\"util\",[2]=\"buff\",[3]=\"debuff\",[4]=\"debuff2\"} | cd util"
        .. " buff debuff debuff2", "added with a layout: a row of its own under the display, last")
    -- Another preset: under the display, last, with the layout's icon spacing.
    B:SetOption("debuff2", "spacing", 9)
    L:Apply("funnel")
    layout = ns.LayoutData()
    Equal(H.Text(layout.above) .. " | " .. H.Text(layout.below) .. " | " .. ns.BarData("debuff2").spacing .. " " .. ns.BarData("cd").spacing,
        "{[1]=\"debuff\",[2]=\"buff\",[3]=\"util\",[4]=\"cd\"} | {[1]=\"debuff2\"} | 0 0",
        "another preset: Debuffs 2 under the display, with the layout's icon spacing like the rest")
    L:Apply("pyramid")
    layout = ns.LayoutData()
    SlashCmdList.FECM("")
    local w = FECMFrame
    w:Select("layout")
    local page = w.pages.layout
    Equal(tostring(page.rows.debuff2 and page.rows.debuff2:IsShown()) .. " " .. S[page.rows.debuff2.name].text, "true Debuffs 2",
        "drawn on the Layout page as its own row")
    L:TakeOut("debuff2")
    w:Refresh()
    Equal(tostring(page.outButtons.debuff2:IsShown()) .. " " .. S[page.outButtons.debuff2.label].text .. " " .. tostring(page.rows.debuff2:IsShown())
        .. " " .. table.concat(L:Rows(), " "), "true + Debuffs 2 false cd util buff debuff", "taken out: a Put back button for it, no row")
    page.outButtons.debuff2:Click()
    Equal(table.concat(L:Rows(), " "), "cd util buff debuff debuff2", "put back")
    -- Moving by numbers steps through it too.
    B.moving = "debuff"
    B:SetUnlocked(true)
    w:Refresh()
    page.move.which:Click()
    local stepped = B.moving
    B:SetUnlocked(false)
    Equal(stepped, "debuff2", "moving by numbers: the next bar after Debuffs is Debuffs 2")
    -- Removed while taken out: no row, and no Put back button either.
    L:TakeOut("debuff2")
    B:RemoveBar("debuff2")
    w:Refresh()
    Equal(table.concat(L:Rows(), " ") .. " | " .. tostring(page.rows.debuff2:IsShown()) .. " " .. tostring(page.outButtons.debuff2:IsShown())
        .. " | " .. H.Text(layout.below), "cd util buff debuff | false false | {[1]=\"util\",[2]=\"buff\",[3]=\"debuff\",[4]=\"debuff2\"}",
        "removed (while taken out): no row stacked or drawn, no Put back button, its place kept for when it's back")
    -- Moving Debuffs 2 by numbers, then a profile without it (a review's
    -- case): the numbers move the Debuffs bar instead, never a bar not there.
    B:AddBar("debuff")
    B.moving = "debuff2"
    B:SetUnlocked(true)
    w:Refresh()
    local was = S[page.move.which.label].text
    ns.NewProfile("Plain")
    w:Refresh()
    Equal(was .. " | " .. B.moving .. " " .. S[page.move.which.label].text .. " " .. tostring(page.move:IsShown()), "Debuffs 2 | debuff Debuffs true",
        "another profile, without Debuffs 2: the numbers move the Debuffs bar")
    B:SetUnlocked(false)
    Equal(#printed, 0, "no errors")
end)()

-- The list's + Add a bar, the way there and back, Remove bar ------------------------------------------
-- Under a kind's last bar in the list on the left (Squirt's pick, concept
-- B), once the bar has spells or an extra bar of its kind is there,
-- "+ Add a bar" adds its kind's next extra bar ("2", then "3") from any
-- page and opens its page; once both are there, or four in all, it stays,
-- greyed, saying why. The bar's own page has no button for it any more.
-- Each extra bar has its own row in the list, lit on its page. On the
-- extra bar's page, Remove bar, which asks first; the list is laid out
-- again. A page whose bar is gone shows its kind's. Each says what it does
-- (seen working in game 13 Nov 2026, so not marked experimental).
;(function()
    local ns = Start({ useBars = true, notesSeen = "dev", helpSeen = true })
    local B = ns.Bars
    SlashCmdList.FECM("")
    local w = FECMFrame
    w:Select("debuff")
    local page = w.pages.bar
    local another, plus = page.another, w.navPlus.debuff
    -- Whether the + line sits right under a row (2 below it), set in.
    local function Under(item)
        local p, at = S[plus].points[1], S[item].points[1]
        return tostring(#S[plus].points == 1 and p[1] == "TOPLEFT" and p[2] == 20 and -p[3] == -at[3] + S[item].height + 2)
    end
    Equal(tostring(plus:IsShown()) .. " " .. tostring(another:IsShown()), "false false",
        "an empty bar: no + Add a bar under it in the list yet, and no button on its page (the ?'s note has room)")
    B:SetAura("debuff", "Moonfire", true)
    w:Refresh()
    Equal(table.concat({ tostring(plus:IsShown()), S[plus.label].text, H.Note(plus), tostring(S[plus].alpha), Under(w.nav.debuff),
        tostring(another:IsShown()) }, " | "),
        "true | + Add a bar | Adds Debuffs 2: a second Debuffs bar with its own spells, size, options and Layout row, say to keep"
        .. " one spell apart from the rest. | 1 | true | false",
        "with spells: + Add a bar under Debuffs in the list, set in, saying what it does; no button on the page")
    -- In a fight: greyed, saying why; a click says so too, and adds nothing.
    lockdown = true
    w:Refresh()
    local fight = tostring(S[plus].alpha) .. " | " .. H.Note(plus)
    plus:Click()
    lockdown = false
    Equal(fight .. " | " .. w.selected .. " " .. S[w.note].text .. " | " .. H.Keys(ns), "0.45 | Finish combat first. | debuff Finish"
        .. " combat first. | cd util buff debuff", "in a fight: greyed, saying why; clicked, it says so and adds nothing")
    w:Refresh()
    plus:Click()
    Equal(table.concat({ w.selected, S[w.note].text, S[page.count].text, tostring(w.nav.debuff2 and w.nav.debuff2.fill:IsShown()),
        tostring(w.nav.debuff.fill:IsShown()), Under(w.nav.debuff2), tostring(another:IsShown()), S[another.label].text, H.Note(another) },
        " | "), "debuff2 | Debuffs 2 added. Tick spells for it in the list below. | Empty | true | false | true | true | Remove bar | Remove"
        .. " Debuffs 2 from this profile, with its spells. It asks first. The < before the title goes back to Debuffs.",
        "clicked: Debuffs 2's page, empty, its own row in the list lit, the + under it now, and Remove bar on its page")
    -- A "<" before the title goes back to Debuffs: shown only on a second
    -- bar's page, with the title after it there.
    local back = page.back
    Equal(table.concat({ tostring(back:IsShown()), S[back.label].text, H.Note(back) }, " | "),
        "true | < | Back to Debuffs.", "Debuffs 2's page: a < saying where it goes")
    back:Click()
    Equal(w.selected .. " " .. tostring(back:IsShown()), "debuff false", "the < goes back to Debuffs, and isn't on Debuffs' page")
    w:Select("debuff2")
    Equal(w.selected .. " " .. tostring(back:IsShown()), "debuff2 true", "on Debuffs 2 again: the < again")
    -- Its options are a Debuffs bar's.
    Equal(tostring(page.options.keepGreyed:IsShown()) .. " " .. tostring(page.options.onlyMissing:IsShown()) .. " "
        .. tostring(page.options.swapForm:IsShown()) .. " " .. tostring(page.showItems:IsShown()),
        "true false false false", "its options are a Debuffs bar's: Keep them greyed, no Only show missing, no Swap with my form or items")
    -- A spell ticked in its list goes on Debuffs 2.
    local row
    for _, r in ipairs(page.rows) do
        if r:IsVisible() and r.spell == "Wrath" then row = r end
    end
    row.check:Click()
    Equal(H.Text(ns.BarData("debuff2").spells) .. " " .. H.Text(ns.BarData("debuff").spells), "{[1]=\"Wrath\"} {[1]=\"Moonfire\"}",
        "ticked in its list: on Debuffs 2, Debuffs as it was")
    -- From another page, the + (under Debuffs 2 now) adds Debuffs 3 (a
    -- player's idea: a third cooldown bar); its page, its own row lit.
    w:Select("look")
    local before = H.Note(plus) .. " | " .. tostring(S[plus].alpha)
    plus:Click()
    Equal(table.concat({ before, w.selected, S[w.note].text, tostring(w.nav.debuff3 and w.nav.debuff3.fill:IsShown()),
        tostring(w.nav.debuff2.fill:IsShown()), Under(w.nav.debuff3), tostring(back:IsShown()), H.Note(back) }, " | "),
        "Adds Debuffs 3: a third Debuffs bar with its own spells, size, options and Layout row, say to keep one spell apart from the rest."
        .. " | 1 | debuff3 | Debuffs 3 added. Tick spells for it in the list below. | true | false | true | true"
        .. " | Back to Debuffs.", "from the Look page: + Add a bar adds Debuffs 3 and opens its page, its own row lit, the + under it")
    -- Both there: still there, greyed, saying why; a click says so too.
    w.nav.debuff:Click()
    local full = tostring(plus:IsShown()) .. " | " .. tostring(S[plus].alpha) .. " | " .. S[plus.label].text .. " | " .. H.Note(plus)
    plus:Click()
    Equal(full .. " | " .. w.selected .. " | " .. S[w.note].text .. " | " .. H.Keys(ns), "true | 0.45 | + Add a bar | Debuffs 2 and"
        .. " Debuffs 3 are there already: two extra bars of a kind at most. | debuff | Debuffs 2 and Debuffs 3 are there already: two"
        .. " extra bars of a kind at most. | cd util buff debuff debuff2 debuff3",
        "both there: still shown, greyed, saying why; clicked anyway it says why, and stays")
    -- Remove bar asks first (Debuffs 3's, then Debuffs 2's); the list is
    -- laid out again each time, the + back under the last one, not greyed.
    w.nav.debuff3:Click()
    another:Click()
    w.confirm.yes:Click()
    local gone3 = table.concat({ w.selected, H.Keys(ns), tostring(w.nav.debuff3:IsShown()), Under(w.nav.debuff2), tostring(S[plus].alpha) },
        " ")
    w.nav.debuff2:Click()
    another:Click()
    local confirm = w.confirm
    Equal(tostring(S[confirm.shade].shown) .. " | " .. S[confirm.dialog.title].text .. " | " .. S[confirm.dialog.detail].text .. " | "
        .. H.Keys(ns) .. " | " .. gone3, "true | Remove Debuffs 2? | Its spells and their settings go from this profile. You can add it"
        .. " again with + Add a bar in the list. | cd util buff debuff debuff2 | debuff cd util buff debuff debuff2 false true 1",
        "Remove bar asks first; Debuffs 3 removed: back on Debuffs, its row gone from the list, the + under Debuffs 2, not greyed")
    confirm.yes:Click()
    Equal(w.selected .. " | " .. S[w.note].text .. " | " .. H.Keys(ns) .. " | " .. Under(w.nav.debuff) .. " " .. tostring(S[plus].alpha)
        .. " " .. tostring(another:IsShown()), "debuff | Debuffs 2 removed, with its spells. | cd util buff debuff | true 1 false",
        "removed: back on Debuffs, the + under it again, no button on its page")
    -- Four extra bars already: greyed, saying why; a click says so too.
    B:AddBar("buff")
    B:AddBar("cd")
    B:AddBar("cd")
    B:AddBar("util")
    w:Refresh()
    local empty = {}
    for _, kind in ipairs({ "cd", "util", "buff" }) do empty[#empty + 1] = tostring(#B:Mine(kind) == 0 and w.navPlus[kind]:IsShown()) end
    Equal(tostring(S[plus].alpha) .. " | " .. H.Note(plus) .. " | " .. table.concat(empty, " "), "0.45 | You have 4 extra bars already:"
        .. " remove one on its page first. | true true true", "four extra bars: greyed, saying why; Cooldowns', Utility's and Buffs' +"
        .. " lines show too, their bars empty but each with an extra bar")
    plus:Click()
    Equal(w.selected .. " | " .. S[w.note].text .. " | " .. H.Keys(ns), "debuff | You have 4 extra bars already: remove one on its page"
        .. " first. | cd cd2 cd3 util util2 buff buff2 debuff", "clicked anyway: it says why, and stays")
    -- A page whose bar went (another profile): its kind's.
    w:Select("cd2")
    ns.NewProfile("Plain")
    w:Refresh()
    Equal(w.selected .. " " .. tostring(w.nav.cd.fill:IsShown()), "cd true", "an extra bar's page with the bar gone: its kind's page")
    Equal(#printed, 0, "no errors")
end)()

-- An icon's own size ---------------------------------------------------------------------------------------
-- A player's idea: more control over each icon's size. On your Cooldowns and
-- Utility bars any icon can be its own size, in a fight too (your own
-- frames); its row makes room for it, each icon centred in the row. On a
-- Buffs or Debuffs bar only a fixed spot can: packed icons are the game's,
-- all one size, so it's kept but not used there. Off by default: every
-- icon at its bar's size, laid out exactly as before.
;(function()
    local ns = Start({ useBars = true, notesSeen = "dev", helpSeen = true, bars = { cd = { spells = { "Moonfire", "Wrath", "Overpower" } } } })
    local B = ns.Bars
    local cd = B:Get("cd")
    local function Row()
        local out = {}
        for i = 1, cd.count do out[i] = cd.icons[i].name .. " " .. S[cd.icons[i]].width .. " " .. H.At(cd.icons[i]) end
        return table.concat(out, "; ") .. " | " .. S[cd].width .. "x" .. S[cd].height
    end
    local before = Row()
    Equal(before .. " | " .. tostring(ns.ProfileLists().iconSize) .. " " .. tostring(ns.OwnSize("cd", "Moonfire")),
        "Moonfire 36 TOPLEFT 0 0; Wrath 36 TOPLEFT 40 0; Overpower 36 TOPLEFT 80 0 | 116x36 | nil nil",
        "off by default: every icon at the bar's size, laid out as before")
    local set = B:SetOwnSize("cd", "Wrath", 150)
    Equal(tostring(set) .. " | " .. Row() .. " | " .. tostring(Last(cd.icons[2].cooldown, "SetCountdownFont")) .. " "
        .. tostring(Last(cd.icons[1].cooldown, "SetCountdownFont")), "true | Moonfire 36 TOPLEFT 0 -9; Wrath 54 TOPLEFT 40 0;"
        .. " Overpower 36 TOPLEFT 98 -9 | 134x54 | FECMFont27 FECMFont18",
        "Wrath at 150%: 54 across, its countdown sized for it; the row as tall as Wrath, the others centred in it")
    -- In a fight too: your own frames.
    lockdown = true
    B:SetOwnSize("cd", "Wrath", 50)
    lockdown = false
    Equal(Row(), "Moonfire 36 TOPLEFT 8 0; Wrath 20 TOPLEFT 48 -8; Overpower 36 TOPLEFT 72 0 | 116x36",
        "in a fight too; 50% of 36 is 18, never under the smallest a bar can have (20)")
    -- Growing from the left edge, then two rows.
    B:SetOption("cd", "grow", "left")
    local left = Row()
    B:SetOption("cd", "grow", "centre")
    B:SetOption("cd", "perRow", 2)
    B:SetOwnSize("cd", "Wrath", 150)
    Equal(left .. " || " .. Row(), "Moonfire 36 TOPLEFT 80 0; Wrath 20 TOPLEFT 56 -8; Overpower 36 TOPLEFT 16 0 | 116x36 || Moonfire 36"
        .. " TOPLEFT 0 -9; Wrath 54 TOPLEFT 40 0; Overpower 36 TOPLEFT 29 -58 | 94x94",
        "growing left: from the right edge; two rows: each as tall as its biggest icon, the second under the first")
    B:SetOption("cd", "perRow", 20)
    -- The buff and debuff time over its icon: sized for it too.
    B:SetOption("cd", "showAuras", true)
    local anchors = {}
    for i, anchor in ipairs(cd.auraAnchors or {}) do anchors[i] = tostring(anchor.size) end
    Equal(table.concat(anchors, " "), "36 54 36", "Show buff and debuff time: the time over Wrath sized for its 54")
    B:SetOption("cd", "showAuras", false)
    -- Bigger bar, All bars: sized from the bar's own on screen.
    B:SetOption("cd", "size", 40)
    Equal(tostring(S[cd.icons[2]].width), "60", "a 40 bar: Wrath 60 across")
    B:SetOption("cd", "size", 36)
    -- Taken off its bar: its size goes. Back: the bar's.
    B:Assign("Wrath", nil)
    Equal(tostring(ns.OwnSize("cd", "Wrath")) .. " " .. tostring(ns.ProfileLists().iconSize), "nil nil", "taken off: its size forgotten")
    -- Only on a bar it's on; odd sizes refused.
    Equal(tostring(B:SetOwnSize("cd", "Wrath", 120)) .. " " .. tostring(B:SetOwnSize("cd", "Moonfire", 151)) .. " "
        .. tostring(B:SetOwnSize("cd", "Moonfire", 49)) .. " " .. tostring(B:SetOwnSize("cd", "Moonfire", 100.5)),
        "false false false false", "a spell not on the bar, or a size outside 50..150 or not whole: refused")
    -- Moved to another cooldown bar: its size on the first goes.
    B:SetOwnSize("cd", "Moonfire", 120)
    B:Assign("Moonfire", "util")
    Equal(tostring(ns.OwnSize("cd", "Moonfire")) .. " " .. tostring(ns.OwnSize("util", "Moonfire")), "nil nil",
        "moved to Utility: its size on Cooldowns forgotten, none on Utility")
    -- The Debuffs bar: packed, kept but not used; fixed spots, at their size.
    B:SetAura("debuff", "Moonfire", true)
    B:SetAura("debuff", "Wrath", true)
    local debuff = B:Get("debuff")
    local kept = B:SetOwnSize("debuff", "Wrath", 150)
    local packed = tostring(B:OwnSizeUsable("debuff")) .. " " .. S[debuff.holders[2]].width .. " " .. tostring(debuff.holders[2].ownSize)
    B:SetOption("debuff", "showMissing", true)
    Equal(tostring(kept) .. " " .. packed .. " | " .. tostring(B:OwnSizeUsable("debuff")) .. " " .. S[debuff.holders[1]].width .. " "
        .. S[debuff.holders[2]].width .. " " .. H.At(debuff.holders[1]) .. " " .. H.At(debuff.holders[2]) .. " " .. S[debuff].height
        .. " | " .. tostring(debuff.holders[2].size), "true false 36 nil | true 36 54 TOPLEFT 0 -9 TOPLEFT 40 0 54 | 54",
        "Debuffs: kept but packed, so not used; with fixed spots Wrath's spot 54 across, its numbers sized for it, Moonfire centred")
    -- In a fight the aura bar waits.
    lockdown = true
    Fire("PLAYER_REGEN_DISABLED")
    B:SetOwnSize("debuff", "Wrath", 100)
    local waiting = S[debuff.holders[2]].width
    lockdown = false
    Fire("PLAYER_REGEN_ENABLED")
    Equal(waiting .. " " .. S[debuff.holders[2]].width, "54 36", "in a fight a Debuffs bar's spot waits for it to end")
    -- /ccm debug says which have one.
    B:SetOwnSize("debuff", "Wrath", 140)
    Equal(ns.DebugReport():match("Extra bars: [^\n]*"), "Extra bars: none | icon sizes: debuff: Wrath 140%", "/ccm debug lists them")
    Equal(#printed, 0, "no errors")
end)()

-- The spell panel's Icon size row ----------------------------------------------------------------------------
-- In a tray icon's own panel, under its countdown's size: Its own, then a
-- percent of the bar's Icon size; on a packed Buffs or Debuffs bar both
-- greyed, saying why. Defaults puts it back with the look.
;(function()
    local ns = Start({ useBars = true, notesSeen = "dev", helpSeen = true, bars = { cd = { spells = { "Moonfire", "Wrath" } } } })
    for _, timer in ipairs(timers) do timer() end
    local B = ns.Bars
    SlashCmdList.FECM("")
    local w = FECMFrame
    w:Select("cd")
    local bp = w.pages.bar
    bp.icons[2]:Click()
    local panel = w.spellPanel
    panel.ownIcon:Click()
    local ticked = tostring(ns.OwnSize("cd", "Wrath")) .. " " .. tostring(panel.iconSize.usable) .. " " .. S[B:Get("cd").icons[2]].width
    panel.iconSize:Choose(125)
    Equal(ticked .. " | " .. tostring(ns.OwnSize("cd", "Wrath")) .. " " .. S[panel.iconSize.value].text .. " " .. S[B:Get("cd").icons[2]].width
        .. " " .. S[panel.preview].width .. " | " .. H.Note(panel.iconSize), "100 true 36 | 125 125% 45 45 | How big this icon is: 100% is"
        .. " the bar's Icon size. The rest of the bar makes room for it. (experimental)",
        "ticked: the bar's size to start; 125%: Wrath and the preview 45 across")
    panel.defaults:Click()
    Equal(tostring(ns.OwnSize("cd", "Wrath")) .. " " .. tostring(panel.ownIcon:GetChecked()) .. " " .. S[B:Get("cd").icons[2]].width,
        "nil false 36", "Defaults: back to the bar's size")
    -- On the packed Debuffs bar: greyed, saying why.
    B:SetAura("debuff", "Moonfire", true)
    w:Select("debuff")
    bp.icons[1]:Click()
    Equal(tostring(panel.ownIcon.usable) .. " " .. tostring(panel.iconSize.usable) .. " | " .. H.Note(panel.ownIcon),
        "false false | This bar is packed: the game lays its icons out at one size. Tick Show missing debuffs greyed to give each its"
        .. " own spot, then its own size.", "packed: greyed, saying why")
    B:SetOption("debuff", "showMissing", true)
    w:Refresh()
    Equal(tostring(panel.ownIcon.usable) .. " | " .. H.Note(panel.ownIcon), "true | Gives this icon a size of its own on Debuffs, in"
        .. " place of the bar's Icon size. (experimental)", "fixed spots: usable")
    Equal(#printed, 0, "no errors")
end)()

-- Buffs 2 and Debuffs 2 go by their kind ------------------------------------------------------------
-- (A review's checks: each place that asks a bar's kind, tried on an extra
-- bar beside the bar it's a copy of.) Passives and spells added by name;
-- each page's list; the page walkthrough; a new target and that target
-- dying; tick counts; buffs shown while unlocked; the low-time glow as a
-- fight starts; /ccm debug's Warn at line.
;(function()
    local ns = Start({ useBars = true, notesSeen = "dev", helpSeen = true })
    local B, Sp = ns.Bars, ns.Spells
    -- A passive's buff (Reckoning's) and another class's buff added by name:
    -- on Buffs 2 as on Buffs, a passive not on Cooldowns 2.
    local names = C_Spell.GetSpellName
    C_Spell.GetSpellName = function(id) if id == 20177 then return "Reckoning" end return names(id) end
    Equal(table.concat({ tostring(Sp:AddNote("20177", "buff")), tostring(Sp:AddNote("20177", "buff2")), tostring(Sp:AddNote("20177", "cd2")),
        tostring(Sp:ForMe("Power Word: Fortitude", "buff", { 1243 })), tostring(Sp:ForMe("Power Word: Fortitude", "buff2", { 1243 })) }, " | "),
        "nil | nil | Reckoning is passive. Only its buff can be tracked, on the Buffs bar. | true | true",
        "a passive's buff goes on Buffs 2 as on Buffs, not on Cooldowns 2; another class's buff added by name is yours on both")
    C_Spell.GetSpellName = names
    B:AddBar("buff")
    B:AddBar("debuff")
    SlashCmdList.FECM("")
    local w = FECMFrame
    local function Rows(key)
        w:Select(key)
        local listed = {}
        for _, row in ipairs(w.pages.bar.rows) do
            if row:IsVisible() and row.spell then listed[#listed + 1] = row.spell end
        end
        return table.concat(listed, ",")
    end
    local buffs, debuffs = Rows("buff"), Rows("debuff")
    Equal(tostring(buffs == Rows("buff2")) .. " " .. tostring(debuffs == Rows("debuff2")) .. " " .. tostring(buffs ~= debuffs and buffs ~= ""),
        "true true true", "Buffs 2's page lists what the Buffs page does, Debuffs 2's what the Debuffs page does")
    -- The page walkthrough on Debuffs 2's page: the Debuffs page's steps.
    B:SetAura("debuff", "Moonfire", true)
    B:SetAura("debuff2", "Moonfire", true)
    local function Steps(key)
        w:Select(key)
        ns.Tour:StartPage(key)
        local titles = {}
        for _, step in ipairs(ns.Tour:Page(key)) do titles[#titles + 1] = tostring(step.title) end
        if FECMTour and FECMTour.skip then FECMTour.skip:Click() end
        return table.concat(titles, ", ")
    end
    local steps = Steps("debuff")
    -- (All but Extra bars: an extra bar's own page has Remove bar instead.)
    local spare = (steps:gsub(", Extra bars", ""))
    Equal(tostring(spare ~= steps) .. " " .. tostring(spare == Steps("debuff2")) .. " " .. tostring(steps:find("Missing ones greyed", 1, true) ~= nil), "true true true",
        "Debuffs 2's walkthrough has the Debuffs page's steps but Extra bars, those only for Buffs and Debuffs bars too")
    -- A new target, then that target dying: each Debuffs bar's Glow when
    -- missing lit, then out; each counts Moonfire's ticks.
    for _, key in ipairs({ "debuff", "debuff2" }) do
        B:SetOption(key, "showMissing", true)
        B:SetGlowMissing(key, "Moonfire", true)
        B:SetCountTicks(key, "Moonfire", true)
    end
    target, hostile = true, true
    Fire("PLAYER_TARGET_CHANGED")
    local function Glow(key)
        local host = B:Get(key).holders[1].glowHost
        return tostring(host and S[host].alpha)
    end
    local lit = Glow("debuff") .. " " .. Glow("debuff2")
    local dead = _G.UnitIsDeadOrGhost
    _G.UnitIsDeadOrGhost = function(unit) return unit == "target" end
    Fire("UNIT_FLAGS", "target")
    _G.UnitIsDeadOrGhost = dead
    Equal(lit .. " | " .. Glow("debuff") .. " " .. Glow("debuff2") .. " | " .. tostring(B:Get("debuff").tickPaces[1]) .. " "
        .. tostring(B:Get("debuff2").tickPaces[1]), "1 1 | 0 0 | 3 3",
        "an enemy targeted: both glow; it dies: both go out (heard as it dies); each counts Moonfire's ticks")
    -- /ccm debug's Warn at line names Debuffs 2's.
    B:SetWarnAt("debuff2", "Moonfire", 5)
    local report = ns.DebugReport()
    Equal(tostring(report:find("Warn at: debuff2: Moonfire 5s", 1, true) ~= nil) .. " | "
        .. tostring(report:match("Warn at: [^\n]*edge slots: ([^\n]*)")) .. " | "
        .. report:match("Extra bars: [^\n]*"), "true | buff none, buff2 none, debuff none, debuff2 none | Extra bars: buff2, debuff2 | icon sizes: none",
        "/ccm debug: Debuffs 2's warned debuff and its edge slots, and both extra bars")
    -- Buffs 2 showing only missing buffs: Thorns on you, its spot hidden,
    -- shown while the bars are unlocked, as on Buffs.
    for _, key in ipairs({ "buff", "buff2" }) do
        B:SetAura(key, "Thorns", true)
        B:SetOption(key, "onlyMissing", true)
    end
    PlayerAuras[467] = true
    Fire("UNIT_AURA", "player")
    S[B.driver].scripts.OnUpdate(B.driver, 0)
    local function Spot(key) return tostring(B:Get(key).holders[1]:IsShown()) end
    local up = Spot("buff") .. " " .. Spot("buff2")
    B:SetUnlocked(true)
    local unlocked = Spot("buff") .. " " .. Spot("buff2")
    B:SetUnlocked(false)
    Equal(up .. " | " .. unlocked .. " | " .. Spot("buff") .. " " .. Spot("buff2"), "false false | true true | false false",
        "Thorns on you: hidden on both Buffs bars, shown on both while unlocked, hidden again")
    PlayerAuras[467] = nil
    for _, key in ipairs({ "buff", "buff2" }) do B:SetOption(key, "onlyMissing", false) end
    -- Warned on both, with spots of their own: lit near the end, out on both as a fight starts.
    local get, ends = C_UnitAuras.GetPlayerAuraBySpellID, { [467] = GetTime() + 30 }
    C_UnitAuras.GetPlayerAuraBySpellID = function(id)
        AuraReads = AuraReads + 1
        if lockdown or ends[id] == nil then return nil end
        return { spellId = id, expirationTime = ends[id] }
    end
    for _, key in ipairs({ "buff", "buff2" }) do
        B:SetOption(key, "showMissing", true)
        B:SetWarnAt(key, "Thorns", 60)
    end
    Fire("UNIT_AURA", "player")
    S[B.driver].scripts.OnUpdate(B.driver, 0)
    local function Low(key)
        local host = B:Get(key).holders[1].lowHost
        return tostring(host ~= nil and host.glow ~= nil and host.glow:IsShown())
    end
    lit = Low("buff") .. " " .. Low("buff2")
    Fire("PLAYER_REGEN_DISABLED")
    lockdown = true
    local fight = Low("buff") .. " " .. Low("buff2")
    lockdown = false
    Fire("PLAYER_REGEN_ENABLED")
    Equal(lit .. " | " .. fight .. " | " .. Low("buff") .. " " .. Low("buff2"), "true true | false false | true true",
        "Thorns warned on both: lit on both, out on both as a fight starts, lit again as it ends")
    C_UnitAuras.GetPlayerAuraBySpellID = get
    Equal(#printed, 0, "no errors")
end)()

-- Cooldowns 2 goes by its kind too; nothing added in a fight ---------------------------------------
-- (The same review.) A new target refreshes the buff and debuff times on
-- each cooldown bar's icons; a keybind on an icon of its own size is sized
-- for it as the Look page changes; no bar is added in a fight.
;(function()
    local ns = Start({ useBars = true, notesSeen = "dev", helpSeen = true, bars = { cd = { spells = { "Moonfire", "Wrath" } } } })
    local B = ns.Bars
    lockdown = true
    local can, why = ns.CanAddBar("cd")
    local added = B:AddBar("cd")
    lockdown = false
    Equal(tostring(can) .. " " .. why .. " | " .. tostring(added) .. " " .. H.Keys(ns), "false Finish combat first. | false cd util buff debuff",
        "in a fight: no extra bar added, saying why")
    B:AddBar("cd")
    B:Assign("Wrath", "cd2")
    B:SetOption("cd", "showAuras", true)
    B:SetOption("cd2", "showAuras", true)
    local function Refreshed(key)
        local containers = B:Get(key).auraContainers
        return tostring(containers and containers.t and S[containers.t].refreshes or 0)
    end
    local before = Refreshed("cd") .. " " .. Refreshed("cd2")
    target = true
    Fire("PLAYER_TARGET_CHANGED")
    Equal(before .. " | " .. Refreshed("cd") .. " " .. Refreshed("cd2"), "0 0 | 1 1",
        "a new target: the buff and debuff times on Cooldowns' and Cooldowns 2's icons look again")
    -- Keybinds on: an icon of its own size keeps its key sized for it as the keybinds change.
    B:SetOwnSize("cd2", "Wrath", 150)
    local icon = B:Get("cd2").icons[1]
    local function Key() return tostring(S[icon.key].last.SetFontObject and S[icon.key].last.SetFontObject[1]) end
    local laid = Key()
    ns.Set("keybinds", true)
    B:ApplyKeybinds()
    Equal(laid .. " " .. Key() .. " " .. S[icon].width, "FECMFont16 FECMFont16 54", "a 54 icon's key sized for it, laid out or changed")
    -- A Debuffs spot of its own size: its Glow when missing that size too.
    B:SetAura("debuff", "Moonfire", true)
    B:SetOption("debuff", "showMissing", true)
    B:SetGlowMissing("debuff", "Moonfire", true)
    B:SetOwnSize("debuff", "Moonfire", 150)
    hostile = true
    Fire("PLAYER_TARGET_CHANGED")
    local holder = B:Get("debuff").holders[1]
    Equal(S[holder].width .. " " .. tostring(holder.glowHost and S[holder.glowHost].width), "54 54", "its glow as big as its spot")
    Equal(#printed, 0, "no errors")
end)()

-- Buffs 2's Only when missing kept, shared and made ---------------------------------------------------
-- (The same review.) Kept over a reload; a shared string carries it and an
-- import makes it; a buff warned on a Buffs 2 the profile doesn't have
-- (saved by hand, or left over) loads without a fuss, dropped; and Debuffs
-- 2's own slots get the tick count's look, the Buffs 2 slots none.
;(function()
    local ns = Start({ useBars = true, notesSeen = "dev", helpSeen = true })
    local B, P = ns.Bars, ns.ProfileShare
    B:AddBar("buff")
    B:SetAura("buff2", "Thorns", true)
    B:SetOnlyWhenMissing("buff2", "Thorns", true)
    local saved = ForeverEnhancedCooldownManagerDB
    ns = Start(saved)
    B, P = ns.Bars, ns.ProfileShare
    local kept = tostring(B:OnlyWhenMissing("buff2", "Thorns"))
    local shared = P.Read(P.Export())
    ns.ImportProfile("Friend", shared, false)
    Equal(kept .. " | " .. H.Text(shared.only) .. " | " .. ns.ProfileName() .. " " .. tostring(B:OnlyWhenMissing("buff2", "Thorns")) .. " "
        .. tostring(B:OnlyWhenMissing("buff", "Thorns")), "true | {[\"buff2\"]={[\"Thorns\"]=true}} | Friend true false",
        "Only when missing on Buffs 2: kept over a reload, in the string, and on the profile made from it (not on Buffs)")
    ns = Start({ useBars = true, notesSeen = "dev", helpSeen = true, chars = { ["Player-1-0001"] = "Left" }, profiles = {
        Left = { cd = {}, util = {}, buff = { "Thorns" }, debuff = {}, warnAt = { buff = { Thorns = 10 }, buff2 = { Thorns = 20 } },
            iconSize = { buff2 = { Thorns = 120 } } } } })
    local left = ForeverEnhancedCooldownManagerDB.profiles.Left
    Equal(H.Text(left.warnAt) .. " " .. tostring(left.iconSize) .. " " .. H.Keys(ns) .. " " .. #printed,
        "{[\"buff\"]={[\"Thorns\"]=10}} nil cd util buff debuff 0", "a warning and a size for a Buffs 2 it doesn't have: dropped as it loads")
    -- The game's tick formatters there: Debuffs 2's slots get the tick count's look as they're made, Buffs 2's none.
    local before = { _G.C_StringUtil, _G.C_CurveUtil, _G.Enum.NumericRuleFormatRounding, _G.Enum.DurationTextBindingProperty }
    _G.C_StringUtil = { CreateNumericRuleFormatter = function()
        return { rules = {}, AddBreakpoint = function(self, rule) table.insert(self.rules, rule) end,
            ClearBreakpoints = function(self) self.rules = {} end }
    end }
    _G.C_CurveUtil = { CreateColorCurve = function()
        return { points = {}, AddPoint = function(self, x, c) table.insert(self.points, { x, c }) end,
            ClearPoints = function(self) self.points = {} end }
    end }
    _G.Enum.NumericRuleFormatRounding, _G.Enum.DurationTextBindingProperty = { Up = 1, Down = 2 }, { ElapsedDuration = 2, TotalDuration = 4 }
    ns.Bars:AddBar("debuff")
    ns.Bars:AddBar("buff")
    local debuff2, buff2 = ns.Bars:Get("debuff2").holders[1].slot, ns.Bars:Get("buff2").holders[1].slot
    _G.C_StringUtil, _G.C_CurveUtil, _G.Enum.NumericRuleFormatRounding, _G.Enum.DurationTextBindingProperty =
        before[1], before[2], before[3], before[4]
    Equal(tostring(debuff2 and debuff2.ticks ~= nil) .. " " .. tostring(buff2 and buff2.ticks ~= nil), "true false",
        "Debuffs 2's slots made with the tick count's look; Buffs 2's without")
    Equal(#printed, 0, "no errors")
end)()

-- A third bar of a kind (a player's idea: a third cooldown bar) ------------------------------------
-- Cooldowns 3 after Cooldowns 2: its own bar a spell can be on (one cooldown
-- bar at a time, the four's lists keeping a spell on two), higher up the
-- screen by default, no Swap with my form, its own settings (Glow for more
-- procs too) kept over a reload. Cooldowns 2 removed leaves Cooldowns 3 as
-- it was, and the next one added is Cooldowns 2 again. Utility 3 the same.
;(function()
    local ns = Start({ useBars = true, notesSeen = "dev", helpSeen = true, bars = { cd = { spells = { "Moonfire", "Wrath", "Overpower" } } } })
    local B = ns.Bars
    local _, second = B:AddBar("cd")
    local _, third, said = B:AddBar("cd")
    B:Assign("Wrath", "cd2")
    B:Assign("Moonfire", "cd3")
    local cd3 = B:Get("cd3")
    Equal(table.concat({ second, third, said, H.Keys(ns), H.Text(ns.BarData("cd").spells), H.Text(ns.BarData("cd2").spells),
        H.Text(ns.BarData("cd3").spells), tostring(B:Find("Moonfire")), tostring(cd3.icons[1].name), tostring(InSight(cd3)),
        H.At(B:Get("cd2")) .. ", " .. H.At(cd3), tostring(ns.CanSwap("cd3")), tostring(ns.BarData("cd3").perRow == ns.BarData("cd").perRow) },
        " | "), "cd2 | cd3 | Cooldowns 3 added. Tick spells for it in the list below. | cd cd2 cd3 util buff debuff | {[1]=\"Overpower\"}"
        .. " | {[1]=\"Wrath\"} | {[1]=\"Moonfire\"} | cd3 | Moonfire | true | BOTTOM 0 454, BOTTOM 0 630 | false | true",
        "Cooldowns 2, then Cooldowns 3, each after its kind; Moonfire on Cooldowns 3 alone, laid out there, higher up the screen"
        .. " than Cooldowns 2 by default, no Swap with my form, started with Cooldowns' icons across")
    -- One cooldown bar at a time: onto Cooldowns 2 it comes off Cooldowns 3.
    B:Assign("Moonfire", "cd2")
    Equal(H.Text(ns.BarData("cd2").spells) .. " " .. H.Text(ns.BarData("cd3").spells) .. " " .. tostring(B:Find("Moonfire")),
        "{[1]=\"Wrath\",[2]=\"Moonfire\"} {} cd2", "moved to Cooldowns 2: off Cooldowns 3")
    B:Assign("Moonfire", "cd3")
    -- Its own settings, kept over a reload (Glow for more procs, a size).
    B:SetOption("cd3", "glowProcs", true)
    B:SetOption("cd3", "size", 44)
    ns = Start(ForeverEnhancedCooldownManagerDB)
    B = ns.Bars
    Equal(table.concat({ H.Keys(ns), tostring(ns.BarData("cd3").glowProcs), tostring(ns.BarData("cd3").size),
        tostring(ns.BarData("cd2").glowProcs), H.Text(ns.BarData("cd3").spells) }, " | "),
        "cd cd2 cd3 util buff debuff | true | 44 | false | {[1]=\"Moonfire\"}", "reloaded: Cooldowns 3 back with its list and its own settings")
    -- Cooldowns 2 removed: Cooldowns 3 stays as it was; the next one added is Cooldowns 2 again.
    B:RemoveBar("cd2")
    local gap = H.Keys(ns) .. " | " .. H.Text(ns.BarData("cd3").spells) .. " | " .. tostring(B:Get("cd3").icons[1].name) .. " | "
        .. tostring((ns.CanAddBar("cd"))) .. " " .. tostring(select(2, ns.CanAddBar("cd")))
    local _, again = B:AddBar("cd")
    Equal(gap .. " | " .. again .. " | " .. H.Keys(ns) .. " | " .. H.Text(ns.BarData("cd2").spells), "cd cd3 util buff debuff | {[1]=\"Moonfire\"}"
        .. " | Moonfire | true cd2 | cd2 | cd cd2 cd3 util buff debuff | {}",
        "Cooldowns 2 removed: Cooldowns 3 as it was; the next one added is Cooldowns 2 again, empty")
    -- Utility 3: the same; a spell on Utility and Utility 3 (a profile made
    -- from a string): Utility keeps it.
    B:AddBar("util")
    local _, util3 = B:AddBar("util")
    B:Assign("Overpower", "util3")
    local store = ns.ProfileLists()
    local found = tostring(B:Find("Overpower"))
    table.insert(store.util, "Overpower")
    B:Rebuild()
    Equal(table.concat({ util3, found, H.Keys(ns), H.Text(store.util), H.Text(store.util3), tostring(B:Find("Overpower")) }, " | "),
        "util3 | util3 | cd cd2 cd3 util util2 util3 buff debuff | {[1]=\"Overpower\"} | {} | util",
        "Utility 3 too; a spell on Utility and Utility 3: Utility keeps it, Utility 3 lets it go")
    Equal(#printed, 0, "no errors")
end)()

-- Buffs 3 and Debuffs 3: every choice an entry has there ---------------------------------------------
-- Each its own container (you, your target). An entry's choices on them
-- (Only when missing, Glow when missing, Others only on a hand's enchant, a
-- trinket's buff, Count ticks, Warn at, Dim until Warn at, its own size) are
-- kept over a reload, copied with the profile sharing no table, shared in
-- a string where they always are (Only when missing, Warn at, sizes; the
-- rest never) and made by an import; removing the bar takes them all.
;(function()
    local ns = Start({ useBars = true, notesSeen = "dev", helpSeen = true })
    local B, P = ns.Bars, ns.ProfileShare
    for _, kind in ipairs({ "buff", "buff", "debuff", "debuff" }) do B:AddBar(kind) end
    B:SetAura("buff3", "Thorns", true)
    B:SetAura("buff3", "hand:main", true)
    B:SetAura("buff3", "trinket:1", true)
    local taken = { B:SetOnlyWhenMissing("buff3", "Thorns", true), B:SetGlowMissing("buff3", "Thorns", true),
        B:SetHandOthers("buff3", "hand:main", true) }
    B:SetAura("debuff3", "Moonfire", true)
    B:SetOption("debuff3", "showMissing", true)
    taken[#taken + 1] = B:SetCountTicks("debuff3", "Moonfire", true)
    taken[#taken + 1] = B:SetWarnAt("debuff3", "Moonfire", 3)
    taken[#taken + 1] = B:SetDimUntilWarn("debuff3", "Moonfire", true)
    taken[#taken + 1] = B:SetOwnSize("debuff3", "Moonfire", 120)
    local function Choices(p)
        local out = {}
        for i, field in ipairs({ "onlyWhenMissing", "glowMissing", "handOthers", "countTicks", "warnAt", "dimUntilWarn", "iconSize" }) do
            local sets = type(p[field]) == "table" and p[field] or {}
            out[#out + 1] = field .. "=" .. H.Text(sets[i <= 3 and "buff3" or "debuff3"])
        end
        return table.concat(out, " ") .. " | " .. H.Text(p.buff3) .. " " .. H.Text(p.debuff3)
    end
    local function Taken()
        local out = {}
        for i, v in ipairs(taken) do out[i] = tostring(v) end
        return table.concat(out, " ")
    end
    local want = 'onlyWhenMissing={["Thorns"]=true} glowMissing={["Thorns"]=true} handOthers={["hand:main"]=true}'
        .. ' countTicks={["Moonfire"]=true} warnAt={["Moonfire"]=3} dimUntilWarn={["Moonfire"]=true} iconSize={["Moonfire"]=120}'
        .. ' | {[1]="Thorns",[2]="hand:main",[3]="trinket:1"} {[1]="Moonfire"}'
    Equal(table.concat({ Taken(), H.Keys(ns), S[B:Get("buff3").container].unit, S[B:Get("debuff3").container].unit,
        Choices(ns.ProfileLists()) }, " | "), "true true true true true true true | cd util buff buff2 buff3 debuff debuff2 debuff3"
        .. " | player | target | " .. want, "Buffs 3 watching you and Debuffs 3 your target, each entry's choices there taken and kept")
    -- Over a reload, then copied.
    ns = Start(ForeverEnhancedCooldownManagerDB)
    B, P = ns.Bars, ns.ProfileShare
    local reloaded = Choices(ns.ProfileLists())
    local from = ns.ProfileLists()
    ns.CopyProfile("Copy")
    local copy, shared = ns.ProfileLists(), {}
    for _, field in ipairs({ "onlyWhenMissing", "glowMissing", "handOthers", "countTicks", "warnAt", "dimUntilWarn", "iconSize" }) do
        for _, key in ipairs({ "buff3", "debuff3" }) do
            local a, b = from[field] and from[field][key], copy[field] and copy[field][key]
            if a ~= nil and a == b then shared[#shared + 1] = field .. "." .. key end
        end
    end
    Equal(reloaded .. " || " .. Choices(copy) .. " | " .. table.concat(shared, " ") .. "| " .. H.Keys(ns), want .. " || " .. want
        .. " | | cd util buff buff2 buff3 debuff debuff2 debuff3", "kept over a reload; copied with the profile, sharing no table")
    -- Shared: the bars, their lists and what strings carry; made into a profile, sharing the same string back.
    local text = P.Export()
    local read = P.Read(text)
    ns.ImportProfile("Friend", read, false)
    local friend = ns.ProfileLists()
    Equal(table.concat({ H.Text(read.extras), tostring(read.skipped), H.Text(read.only.buff3), H.Text(read.warns.debuff3),
        H.Text(read.sizes.debuff3), H.Text(friend.buff3), H.Text(friend.onlyWhenMissing.buff3), tostring(next(friend.handOthers.buff3 or {})),
        tostring(next(friend.dimUntilWarn.debuff3 or {})), H.Keys(ns), tostring(P.Export() == text), tostring(#text < 2000) }, " | "),
        "{[\"buff2\"]=true,[\"buff3\"]=true,[\"debuff2\"]=true,[\"debuff3\"]=true} | 0 | {[\"Thorns\"]=true} | {[\"Moonfire\"]=3}"
        .. " | {[\"Moonfire\"]=120} | {[1]=\"Thorns\",[2]=\"hand:main\",[3]=\"trinket:1\"} | {[\"Thorns\"]=true} | nil | nil | cd util buff"
        .. " buff2 buff3 debuff debuff2 debuff3 | true | true", "shared: the four extra bars, Buffs 3's list with its hand and trinket"
        .. " entries, Only when missing, Warn at and sizes (Others only and Dim until Warn at never, as on Buffs); imported, the same"
        .. " string back")
    -- Removed: every choice of theirs goes with them.
    B:RemoveBar("buff3")
    B:RemoveBar("debuff3")
    local store = ns.ProfileLists()
    Equal(table.concat({ H.Keys(ns), tostring(store.buff3), tostring(store.debuff3), tostring(store.onlyWhenMissing.buff3),
        tostring(store.warnAt and store.warnAt.debuff3), tostring(store.iconSize and store.iconSize.debuff3), H.Text(store.extraBars) }, " | "),
        "cd util buff buff2 debuff debuff2 | nil | nil | nil | nil | nil | {[\"buff2\"]=true,[\"debuff2\"]=true}",
        "Buffs 3 and Debuffs 3 removed: their lists and choices gone")
    ns.UseProfile("Copy")
    store = ns.ProfileLists()
    Equal(table.concat({ H.Keys(ns), tostring(store.handOthers.buff3 and store.handOthers.buff3["hand:main"]),
        tostring(store.dimUntilWarn.debuff3 and store.dimUntilWarn.debuff3.Moonfire), tostring(store.countTicks.debuff3 and store.countTicks.debuff3.Moonfire),
        tostring(store.glowMissing.buff3 and store.glowMissing.buff3.Thorns) }, " | "),
        "cd util buff buff2 buff3 debuff debuff2 debuff3 | true | true | true | true", "the copy still has them all")
    -- /ccm debug names the extra bars.
    Equal(ns.DebugReport():match("Extra bars: [^|]*"), "Extra bars: buff2, buff3, debuff2, debuff3 ", "/ccm debug lists the four")
    Equal(#printed, 0, "no errors")
end)()

-- The window's list of your bars, up to eight, with + Add a bar ------------------------------------
-- (Squirt's pick, concept B, 13 Nov 2026.) Every bar you have is a row like
-- the four's (its name, count and a preview of its icons), never set in,
-- each kind's together; under a kind's last bar its + Add a bar line, once
-- the bar has spells or an extra bar of its kind is there. No spells and no
-- extra bar: the four exactly as always. They share the four's room (192,
-- 28 under the list's top): as + lines and bars come, every row a little
-- shorter with smaller icons, down to 32 high with 12 px icons (the four
-- with a + under each); past that the rows stay so and the list scrolls in
-- that room (Squirt's complaint was one-line rows with no previews: never
-- again, any number of bars). The rule, Look and the rest never move and
-- nothing reaches What's new. In a list that scrolls, the lit bar comes
-- into sight (with its kind's + under it), the wheel scrolls it and a
-- refresh leaves it there. An extra bar's row opens its page, lit there;
-- another profile's extras swap in; none again: the four as always.
;(function()
    local ns = Start({ useBars = true, notesSeen = "dev", helpSeen = true })
    local B = ns.Bars
    SlashCmdList.FECM("")
    local w = FECMFrame
    local list = w.barList
    -- The game measures the list as pinned: 192 high (the mock keeps no
    -- sizes from anchors).
    S[list].height = 192
    -- The list from the top: each bar's row (its top as if unscrolled, 28
    -- being the list's top, +height, x, its name's anchor, previews
    -- showing) and each + line (its top, x), in order.
    local function List()
        local out = {}
        for _, key in ipairs(ns.ALL_BAR_KEYS) do
            local item = w.nav[key]
            if item and item:IsShown() then
                local p, label, shown = S[item].points[1], S[item.label].points[1], 0
                for _, icon in ipairs(item.icons or {}) do
                    if icon:IsShown() then shown = shown + 1 end
                end
                out[#out + 1] = { -p[3], ("%s %d+%d %d %s%d,%d %d"):format(key, 28 - p[3], S[item].height, p[2], label[1], label[2], label[3], shown) }
            end
        end
        for kind, line in pairs(w.navPlus) do
            if line:IsShown() then out[#out + 1] = { -S[line].points[1][3], ("+%s %d %d"):format(kind, 28 - S[line].points[1][3], S[line].points[1][2]) } end
        end
        table.sort(out, function(a, b) return a[1] < b[1] end)
        for i, row in ipairs(out) do out[i] = row[2] end
        return table.concat(out, ", ")
    end
    -- The list's view: pinned by two corners to the list on the left (its
    -- top 28 down, its foot as far as the view goes, the thumb's room at the
    -- right while it scrolls); then how high the view and its content are,
    -- the content's width, the thumb, and how far it's scrolled.
    local function View()
        local a, b = S[list].points[1], S[list].points[2]
        if not (a and b) then return #S[list].points .. " corners: not pinned" end
        local content = S[list.content]
        return ("%d %s%d,%d %s%s%d,%d | %d of %d, %d wide, thumb %s, at %d"):format(#S[list].points, a[1], a[4], a[5], b[1], b[3], b[4], b[5],
            -b[5] - 28, content.height, content.width, tostring(S[list.thumb].shown), list:GetVerticalScroll())
            .. (a[2] == w.navFrame and b[2] == w.navFrame and "" or " (pinned to something else)")
    end
    -- Every bar's row with its preview: 32 high at least, its name over its
    -- icons (never one line), the icons 12 px at least, as many showing as
    -- the bar has spells (nine at most). "" when all have.
    local function Previews()
        local wrong = {}
        for _, key in ipairs(ns.BAR_KEYS) do
            local item, shown = w.nav[key], 0
            for _, icon in ipairs(item.icons) do
                if icon:IsShown() then shown = shown + 1 end
            end
            local want = math.min(9, #B:Mine(key))
            if S[item].height < 32 then wrong[#wrong + 1] = key .. " " .. S[item].height .. " high" end
            if S[item.label].points[1][1] ~= "TOPLEFT" then wrong[#wrong + 1] = key .. " on one line" end
            if S[item.icons[1]].width < 12 then wrong[#wrong + 1] = key .. "'s icons " .. S[item.icons[1]].width end
            if shown ~= want then wrong[#wrong + 1] = key .. " " .. shown .. " icons of " .. want end
        end
        return table.concat(wrong, "; ")
    end
    -- Nothing in the list on anything else in it, all of it inside its
    -- content; the view ending above the rule (224), the content all in
    -- sight unless the list scrolls; nothing under it on anything else or
    -- on What's new (its top 455 down the list), and Look where it always was.
    local function Fits()
        local inList, under, wrong = {}, {}, {}
        for key, item in pairs(w.nav) do
            if item:IsShown() then
                local into = S[item].parent == list.content and inList or under
                into[#into + 1] = { item, key }
            end
        end
        for kind, line in pairs(w.navPlus) do
            if line:IsShown() then inList[#inList + 1] = { line, "+" .. kind } end
            if S[line].parent ~= list.content then wrong[#wrong + 1] = "+" .. kind .. " outside the list" end
        end
        local function Clear(parts)
            for i, a in ipairs(parts) do
                local top = -S[a[1]].points[1][3]
                local bottom = top + S[a[1]].height
                for j = i + 1, #parts do
                    local other = -S[parts[j][1]].points[1][3]
                    if top < other + S[parts[j][1]].height and other < bottom then wrong[#wrong + 1] = a[2] .. " on " .. parts[j][2] end
                end
            end
        end
        Clear(inList)
        Clear(under)
        local content, foot = S[list.content], S[list].points[2]
        if not foot then
            wrong[#wrong + 1] = "the list not pinned"
            return table.concat(wrong, "; ")
        end
        for _, a in ipairs(inList) do
            if -S[a[1]].points[1][3] + S[a[1]].height > content.height then wrong[#wrong + 1] = a[2] .. " past the list's end" end
        end
        local view, rule = -foot[5] - 28, -S[w.under[1][1]].points[1][3]
        if 28 + view > rule then wrong[#wrong + 1] = "the list on the rule" end
        if content.height > view and foot[4] ~= -8 then wrong[#wrong + 1] = "the list cut off, not scrolling" end
        local news = 489 - S[w.news].points[1][3] - S[w.news].height
        for _, a in ipairs(under) do
            if -S[a[1]].points[1][3] + S[a[1]].height > news then wrong[#wrong + 1] = a[2] .. " on What's new" end
        end
        if S[w.nav.look].points[1][3] ~= -232 then wrong[#wrong + 1] = "Look moved to " .. -S[w.nav.look].points[1][3] end
        return table.concat(wrong, "; ")
    end
    local function Icon(key, i)
        local s = S[w.nav[key].icons[i]]
        return ("%s%d,%d %d"):format(s.points[1][1], s.points[1][2], s.points[1][3], s.width)
    end
    -- The page walkthrough's Extra bars step on a bar's page: what it
    -- outlines, and whether its box hangs beside that.
    local function ExtraStep(key)
        w:Select(key)
        w.help:Click()
        local box = FECMTour
        for _ = 1, 20 do
            if S[box.title].text == "EXTRA BARS" or S[box.next.label].text == "Done" then break end
            box.next:Click()
        end
        local part = S[box.title].text == "EXTRA BARS" and S[box.outline].points[1][2] or nil
        local beside = S[box].points[1][1] .. " " .. tostring(S[box].points[1][2] == part) .. " " .. S[box].points[1][3]
        box.skip:Click()
        return part, beside
    end
    local four = List()
    local part, beside = ExtraStep("cd")
    -- Pinned again a moment after the window shows (as every list that
    -- scrolls: one pinned while the window was hidden is never placed).
    local built = View()
    list:ClearAllPoints()
    for _, timer in ipairs(timers) do timer() end
    Equal(four .. " | " .. Icon("cd", 2) .. " " .. S[w.nav.cd.count].text .. " " .. tostring(w.nav.cd2) .. " | " .. Fits() .. " | "
        .. tostring(part == w.nav.cd) .. " " .. beside .. " | " .. built .. " | " .. tostring(View() == built),
        "cd 28+46 0 TOPLEFT14,-9 0, util 76+46 0 TOPLEFT14,-9 0, buff 124+46 0 TOPLEFT14,-9 0, debuff 172+46 0 TOPLEFT14,-9 0 |"
        .. " TOPLEFT30,-26 14 0 nil |  | true TOPLEFT true TOPRIGHT | 2 TOPLEFT0,-28 BOTTOMRIGHTTOPRIGHT0,-220 | 192 of 192, 180 wide,"
        .. " thumb false, at 0 | true", "no spells, no extra bar: the four exactly as always, no + line, nothing made for an extra bar,"
        .. " the list the four's 192, the list's full width, no thumb; the tour's Extra bars step points at Cooldowns in the list;"
        .. " the list pinned again as the window shows")
    -- Spells on Cooldowns and Debuffs: a + under each of those only; the
    -- four rows a little shorter (39), icons 12, the + lines in their room.
    B:Assign("Moonfire", "cd")
    B:SetAura("debuff", "Moonfire", true)
    w:Refresh()
    Equal(List() .. " | " .. Icon("cd", 2) .. " " .. Icon("cd", 1) .. " | " .. Fits() .. " | " .. Previews() .. " | " .. View(),
        "cd 28+39 0 TOPLEFT14,-7 1, +cd 69 20, util 83+39 0 TOPLEFT14,-7 0, buff 124+39 0 TOPLEFT14,-7 0, debuff 165+39 0 TOPLEFT14,-7 1,"
        .. " +debuff 206 20 | TOPLEFT28,-22 12 TOPLEFT14,-22 12 |  |  | 2 TOPLEFT0,-28 BOTTOMRIGHTTOPRIGHT0,-220 | 192 of 192, 180 wide,"
        .. " thumb false, at 0", "spells on two bars: + Add a bar under those two only, set in; every row the same, a little shorter,"
        .. " its preview kept; all in sight, no scrolling; Look in place")
    -- Spells on all four and one extra bar (the review's case: one-line rows
    -- with no previews before): Cooldowns 2 a row like the others, its own
    -- preview, at the same x and name's place as Cooldowns; the + under it,
    -- not under Cooldowns. Every row 32 high with its 12 px icons; the list
    -- scrolls (226 in 192), the thumb in its room at the right.
    B:AddBar("cd")
    B:Assign("Wrath", "cd2")
    B:Assign("Overpower", "util")
    B:SetAura("buff", "Thorns", true)
    w:Select("cd2")
    Equal(List() .. " | " .. Icon("cd2", 1) .. " " .. Icon("cd", 1) .. " " .. S[w.nav.cd2.count].text .. " " .. tostring(w.nav.cd2.fill:IsShown())
        .. " " .. tostring(w.nav.cd.fill:IsShown()) .. " " .. H.Note(w.nav.cd2) .. " | " .. Fits() .. " | " .. Previews() .. " | " .. View(),
        "cd 28+32 0 TOPLEFT14,-4 1, cd2 62+32 0 TOPLEFT14,-4 1, +cd 96 20, util 110+32 0 TOPLEFT14,-4 1, +util 144 20, buff 158+32 0"
        .. " TOPLEFT14,-4 1, +buff 192 20, debuff 206+32 0 TOPLEFT14,-4 1, +debuff 240 20 | TOPLEFT14,-18 12 TOPLEFT14,-18 12 1 true false"
        .. " Your Cooldowns 2 bar: its icons, how it shows, and your spells to tick onto it. |  |  | 2 TOPLEFT0,-28 BOTTOMRIGHTTOPRIGHT-8,-220"
        .. " | 192 of 226, 172 wide, thumb true, at 0", "Cooldowns 2: a full row like Cooldowns (same x, no indent, its own count and"
        .. " preview), lit on its page; the + under it now; every row keeps its preview; the list scrolls in the bars' room; Look in place")
    -- Debuffs' page: its row and the + under it scrolled into sight (no
    -- further); a refresh leaves it; Cooldowns' page: back to the top.
    w:Select("debuff")
    local debuff = list:GetVerticalScroll()
    w:Refresh()
    local kept = list:GetVerticalScroll()
    w:Select("cd")
    Equal(debuff .. " " .. kept .. " " .. list:GetVerticalScroll(), "32 32 0",
        "a bar's page scrolls its row and + into sight in the list, a refresh leaves it there, Cooldowns' page back to the top")
    -- The most the list holds: four extra bars and every kind's + line.
    -- Every row alike as the four's with a + under each (no indent, its
    -- own preview), the + lines still there; the list scrolls (328 in 192);
    -- nothing overlaps, nothing on What's new, Look in place.
    B:AddBar("cd")
    B:AddBar("util")
    B:AddBar("debuff")
    w:Refresh()
    local alphas = {}
    for _, kind in ipairs(ns.BASE_BAR_KEYS) do alphas[#alphas + 1] = tostring(S[w.navPlus[kind]].alpha) end
    part, beside = ExtraStep("cd")
    local eight = List()
    Equal(eight .. " | " .. Fits() .. " | " .. Previews() .. " | " .. View() .. " | " .. table.concat(alphas, " ") .. " | "
        .. tostring(part == w.navPlus.cd) .. " " .. beside, "cd 28+32 0 TOPLEFT14,-4 1, cd2 62+32 0 TOPLEFT14,-4 1, cd3 96+32 0"
        .. " TOPLEFT14,-4 0, +cd 130 20, util 144+32 0 TOPLEFT14,-4 1, util2 178+32 0 TOPLEFT14,-4 0, +util 212 20, buff 226+32 0"
        .. " TOPLEFT14,-4 1, +buff 260 20, debuff 274+32 0 TOPLEFT14,-4 1, debuff2 308+32 0 TOPLEFT14,-4 0, +debuff 342 20 |  |  | 2"
        .. " TOPLEFT0,-28 BOTTOMRIGHTTOPRIGHT-8,-220 | 192 of 328, 172 wide, thumb true, at 0 | 0.45 0.45 0.45 0.45 | true TOPLEFT true"
        .. " TOPRIGHT", "eight bars and four + lines: every row alike, 32 high, no indent, its own preview; the + lines (greyed: four"
        .. " in all) still under each kind; the list scrolls in the bars' room, so all fits above What's new; the tour's Extra bars"
        .. " step points at the + under Cooldowns' bars, its box beside it")
    -- Debuffs 2's page: its row and the + under it at the foot of the view;
    -- the wheel scrolls up and a refresh leaves it; Cooldowns 3's row,
    -- half out of sight above, clicked: in sight, at the top. The thumb
    -- inside the list on the left, clear of the rows.
    w:Select("debuff2")
    local foot = list:GetVerticalScroll()
    S[list].scripts.OnMouseWheel(list, 1)
    local wheel = list:GetVerticalScroll()
    w:Refresh()
    local after = list:GetVerticalScroll()
    w.nav.cd3:Click()
    local thumb = S[list.thumb]
    Equal(foot .. " " .. wheel .. " " .. after .. " " .. list:GetVerticalScroll() .. " | " .. w.selected .. " "
        .. tostring(w.nav.cd3.fill:IsShown()) .. " " .. tostring(w.pages.bar:IsShown()) .. " | " .. thumb.points[1][1] .. " "
        .. tostring(thumb.points[1][2] == list) .. " " .. thumb.points[1][3] .. " " .. thumb.points[1][4] .. " " .. thumb.width,
        "134 90 90 68 | cd3 true true | TOPLEFT true TOPRIGHT 4 3", "Debuffs 2's row and its + scrolled into sight; the wheel"
        .. " scrolls the list, a refresh leaves it; Cooldowns 3's row opens its page, lit, scrolled into sight; the thumb 4 right of"
        .. " the list's 172, 3 wide: inside the list on the left (180)")
    -- Another profile, with an extra bar of its own (Buffs 2): its list;
    -- yours back, then that one's again, each laid out afresh.
    local mine = ns.ProfileName()
    ns.NewProfile("Plain")
    w:Refresh()
    local plain = List() .. " | " .. View()
    B:SetAura("buff", "Thorns", true)
    B:AddBar("buff")
    w:Refresh()
    local other = List() .. " | " .. View()
    ns.UseProfile(mine)
    w:Refresh()
    local back = List()
    ns.UseProfile("Plain")
    w:Refresh()
    Equal(plain .. " || " .. other .. " || " .. tostring(back == eight) .. " || " .. tostring(List() .. " | " .. View() == other) .. " "
        .. Fits() .. " | " .. Previews(), "cd 28+46 0 TOPLEFT14,-9 0, util 76+46 0 TOPLEFT14,-9 0, buff 124+46 0 TOPLEFT14,-9 0,"
        .. " debuff 172+46 0 TOPLEFT14,-9 0 | 2 TOPLEFT0,-28 BOTTOMRIGHTTOPRIGHT0,-220 | 192 of 192, 180 wide, thumb false, at 0 || cd"
        .. " 28+33 0 TOPLEFT14,-4 0, util 63+33 0 TOPLEFT14,-4 0, buff 98+33 0 TOPLEFT14,-4 1, buff2 133+33 0 TOPLEFT14,-4 0, +buff 168"
        .. " 20, debuff 182+33 0 TOPLEFT14,-4 0 | 2 TOPLEFT0,-28 BOTTOMRIGHTTOPRIGHT0,-220 | 192 of 189, 180 wide, thumb false, at 0 ||"
        .. " true || true  | ", "a new profile: the four as always, the list back to its full width, no thumb, at the top; Buffs 2"
        .. " added there: its own row, the + under it, all in sight; yours: your eight again; back: Buffs 2's list again, the others'"
        .. " rows gone")
    -- Yours, scrolled down, then every extra removed: four rows with a +
    -- under each (all have spells), all in sight again, back at the top at
    -- the list's full width; then no spells: the four exactly as always.
    ns.UseProfile(mine)
    w:Select("debuff2")
    local scrolled = list:GetVerticalScroll()
    for _, key in ipairs({ "debuff2", "util2", "cd3", "cd2" }) do B:RemoveBar(key) end
    w:Refresh()
    local plus = scrolled .. " | " .. List() .. " | " .. Fits() .. " | " .. Previews() .. " | " .. View()
    B:Assign("Moonfire", nil)
    B:Assign("Overpower", nil)
    B:SetAura("buff", "Thorns", false)
    B:SetAura("debuff", "Moonfire", false)
    w:Refresh()
    Equal(plus .. " || " .. List() .. " | " .. Icon("cd", 2) .. " " .. tostring(w.nav.cd2:IsShown()) .. " | " .. Fits() .. " | " .. View(),
        "134 | cd 28+32 0 TOPLEFT14,-4 1, +cd 62 20, util 76+32 0 TOPLEFT14,-4 1, +util 110 20, buff 124+32 0 TOPLEFT14,-4 1, +buff 158"
        .. " 20, debuff 172+32 0 TOPLEFT14,-4 1, +debuff 206 20 |  |  | 2 TOPLEFT0,-28 BOTTOMRIGHTTOPRIGHT0,-220 | 192 of 192, 180 wide,"
        .. " thumb false, at 0 || cd 28+46 0 TOPLEFT14,-9 0, util 76+46 0 TOPLEFT14,-9 0, buff 124+46 0 TOPLEFT14,-9 0, debuff 172+46 0"
        .. " TOPLEFT14,-9 0 | TOPLEFT30,-26 14 false |  | 2 TOPLEFT0,-28 BOTTOMRIGHTTOPRIGHT0,-220 | 192 of 192, 180 wide, thumb false,"
        .. " at 0", "every extra removed: four rows and four + lines, laid out again, all in sight at the list's full width, back"
        .. " at the top; no spells: the four exactly as always, icons back to 14")
    Equal(#printed, 0, "no errors")
end)()

-- Eight bars in a layout --------------------------------------------------------------------------------
-- Each extra bar added (third ones too) gets a row of its own under the
-- display, last, drawn on the Layout page; moving by numbers steps through
-- all eight; each can be taken out and put back.
;(function()
    local ns = Start({ useBars = true, notesSeen = "dev", helpSeen = true })
    local B, L = ns.Bars, ns.Layout
    L:Apply("pyramid")
    for _, kind in ipairs({ "cd", "cd", "debuff", "debuff" }) do B:AddBar(kind) end
    for _, key in ipairs({ "cd2", "cd3" }) do B:Assign(key == "cd2" and "Wrath" or "Moonfire", key) end
    B:SetAura("debuff2", "Wrath", true)
    B:SetAura("debuff3", "Moonfire", true)
    SlashCmdList.FECM("")
    local w = FECMFrame
    w:Select("layout")
    local page = w.pages.layout
    local drawn = {}
    for _, key in ipairs(ns.BAR_KEYS) do
        if page.rows[key] and page.rows[key]:IsShown() then drawn[#drawn + 1] = S[page.rows[key].name].text end
    end
    local steps = {}
    B.moving = "debuff3"
    B:SetUnlocked(true)
    for _ = 1, 8 do
        w:Refresh()
        page.move.which:Click()
        steps[#steps + 1] = B.moving
    end
    B:SetUnlocked(false)
    L:TakeOut("cd3")
    w:Refresh()
    local out = tostring(page.outButtons.cd3:IsShown()) .. " " .. S[page.outButtons.cd3.label].text .. " " .. table.concat(L:Rows(), " ")
    page.outButtons.cd3:Click()
    Equal(table.concat({ H.Text(ns.LayoutData().below), table.concat(drawn, ","), table.concat(steps, " "), out, table.concat(L:Rows(), " ") },
        " | "), "{[1]=\"util\",[2]=\"buff\",[3]=\"debuff\",[4]=\"cd2\",[5]=\"cd3\",[6]=\"debuff2\",[7]=\"debuff3\"} | Cooldowns,Cooldowns 2,"
        .. "Cooldowns 3,Utility,Buffs,Debuffs,Debuffs 2,Debuffs 3 | cd cd2 cd3 util buff debuff debuff2 debuff3 | true + Cooldowns 3 cd util"
        .. " buff debuff cd2 debuff2 debuff3 | cd util buff debuff cd2 cd3 debuff2 debuff3",
        "each extra a row of its own under the display, drawn on the Layout page; moving by numbers steps through all eight;"
        .. " Cooldowns 3 taken out and put back")
    Equal(#printed, 0, "no errors")
end)()

Equal(SecretMisuse[1], nil, "no secret misused anywhere")
io.write("Extra bar checks passed: " .. checks .. " assertions.\n")
