-- Run the actual addon files against a mock game for the ? in the /ccm
-- window's title bar and how things fit: its tooltip (just under it, in the
-- addon's own look, never the footer), its first-time pulse and note (until
-- it's first clicked, saved for the whole account, never over the welcome,
-- a tour or a walkthrough), and every label on the window's pages clear of
-- the next control (the Layout page's foot most of all). The mock game is a
-- copy of Tools/TestBars.lua's: Tools/TestMockSync.mjs checks the two match,
-- and with --write copies it across. Tools/TestBars.lua is near the mock
-- game's memory limit, so these run here.
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

-- The page help: the game around it ------------------------------------------------------------
-- Stand-ins for what the window's other pages need (Raid Timers' previews
-- run none of Blizzard's code, the Cooldown pulse plays no sound), as in
-- Tools/TestPulse.lua.

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
    _G.PlaySound = function() end
    _G.C_Spell.GetSpellCooldown = function() return { isEnabled = true } end
    _G.GetSpellBaseCooldown = nil
    S[UIParent].width, S[UIParent].height = 1366, 768
end

-- Every file in the order the .toc loads them (Tools/TestRules.mjs checks the .toc).
local FILES = { "Core.lua", "SquirtVersions.lua", "Style.lua", "Skin.lua", "Resource.lua", "CastBar.lua", "RaidTimers.lua", "Ranks.lua", "Forms.lua", "Spells.lua",
    "Keybinds.lua", "Buffs.lua", "IconAuras.lua", "Bars.lua", "Pulse.lua", "Layout.lua", "Theme.lua", "BarPage.lua",
    "LayoutPage.lua", "CastBarPage.lua", "RaidTimersPage.lua", "PulsePage.lua", "ProfileShare.lua", "ProfileMenu.lua", "Window.lua",
    "Tour.lua", "MinimapButton.lua", "Notes.lua", "Debug.lua" }
-- A fresh game, logged in with these saved settings (nil: a first install).
local function Start(saved)
    Environment()
    BlizzardFrames()
    _G.FECMFrame, _G.FECMTour, _G.FECMNotes = nil, nil, nil
    local ns = {}
    _G.ForeverEnhancedCooldownManagerDB = saved
    for _, file in ipairs(FILES) do assert(loadfile(file))("ForeverEnhancedCooldownManager", ns) end
    Fire("ADDON_LOADED", "ForeverEnhancedCooldownManager")
    Fire("PLAYER_LOGIN")
    Fire("PLAYER_ENTERING_WORLD")
    return ns
end
-- A frame of the game going by: the ?'s pulse and note run while the
-- window is on screen and the ? has never been clicked.
local function Step(w, elapsed)
    local driver = w.helpNudge.driver
    if driver:IsVisible() then S[driver].scripts.OnUpdate(driver, elapsed or 0) end
end
-- The note under the ?, and the ?'s glow: each on screen or not.
local function Nudge(w)
    return tostring(w.helpNudge:IsVisible()) .. " " .. tostring(w.help.glow:IsVisible())
end
-- Two places as text, rounded.
local function Num(v) return ("%.2f"):format(v) end

-- How things fit ---------------------------------------------------------------------------------
-- Text in the game runs about seven units a letter in the window's usual
-- font (on a screenshot of the game "Live preview" took about 76 and ran
-- into Row spacing). Counted at 7.5 here, 6.5 in the small font, and more for
-- capitals, as Tools/TestPulse.lua does, to be sure. Places are worked out
-- from each frame's anchors as the game would: left, top, right and bottom,
-- y down from the window's top left.
local Fit = {}
function Fit.Wide(text, font)
    text = tostring(text or ""):gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""):gsub("|T.-|t", "XX")
    local small = type(font) == "string" and font:find("Small") ~= nil
    local capitals = text:find("%a") ~= nil and text == text:upper()
    local each = small and (capitals and 7.5 or 6.5) or (capitals and 9 or 7.5)
    return #text * each
end
-- Text is as wide as Wide says (in its room, where it's justified), and as
-- many lines tall as it wraps to; a tick is its box and label.
function Fit.Rect(obj, depth)
    depth = depth or 0
    assert(depth < 40, "anchors that go round in a circle")
    if obj == FECMFrame then return 0, 0, 820, 560 end
    local s = S[obj]
    if obj == UIParent or not s then return -10000, -10000, 10000, 10000 end
    local width, height, wide = s.width, s.height, nil
    if s.kind == "FontString" then
        wide = Fit.Wide(s.text, Last(obj, "SetFontObject") or s.template)
        if width == 0 then
            width = wide
        elseif wide > width and height == 0 then
            height = math.ceil(wide / width) * 12
        end
        if height == 0 then height = 12 end
    end
    if rawget(obj, "box") and rawget(obj, "text") then width, height = 18 + Fit.Wide(S[obj.text].text, S[obj.text].template), 16 end
    if #s.points == 0 then return Fit.Rect(s.parent, depth + 1) end
    local left, top, right, bottom, cx, cy
    for _, p in ipairs(s.points) do
        local point, relative, relativePoint, x, y = p[1], s.parent, p[1], p[2] or 0, p[3] or 0
        if type(p[2]) == "table" then point, relative, relativePoint, x, y = p[1], p[2], p[3] or p[1], p[4] or 0, p[5] or 0 end
        local rl, rt, rr, rb = Fit.Rect(relative, depth + 1)
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
    if wide and s.width > 0 and wide < right - left then
        local justify = Last(obj, "SetJustifyH") or "LEFT"
        if justify == "RIGHT" then
            left = right - wide
        elseif justify == "CENTER" then
            left, right = (left + right - wide) / 2, (left + right + wide) / 2
        else
            right = left + wide
        end
    end
    return left, top, right, bottom
end
function Fit.Inside(obj, root)
    local at = obj
    while at do
        if at == root then return true end
        at = S[at] and S[at].parent
    end
    return false
end
-- In a list that scrolls: cut off at its edge.
function Fit.Scrolled(obj)
    local at = S[obj].parent
    while at and S[at] do
        if S[at].kind == "ScrollFrame" then return true end
        at = S[at].parent
    end
    return false
end
function Fit.Name(obj)
    local s = S[obj]
    if s.kind == "FontString" then return '"' .. tostring(s.text) .. '"' end
    if rawget(obj, "box") and rawget(obj, "text") then return "tick " .. tostring(S[obj.text].text) end
    if rawget(obj, "buttons") then return "choice " .. tostring(S[obj.buttons[1].label].text) .. "..." end
    if rawget(obj, "popup") then return "colour swatch" end
    if rawget(obj, "label") then return s.kind .. " " .. tostring(S[obj.label].text) end
    return s.kind
end
-- What can run into something else, where each shows: text (not a
-- button's or tick's own), ticks with their labels, buttons, choices, text
-- boxes and slider tracks, the thumb reaching 5 past each end.
function Fit.Pieces(root)
    local list = {}
    for _, obj in ipairs(objects) do
        local s = S[obj]
        local parent = s.parent
        if obj ~= root and Fit.Inside(obj, root) and obj:IsVisible() and not Fit.Scrolled(obj) then
            local piece
            if s.kind == "FontString" then
                local own = parent and S[parent] and ((S[parent].kind == "Button" and rawget(parent, "label") == obj)
                    or (rawget(parent, "box") ~= nil and rawget(parent, "text") == obj))
                local inChoice = parent and S[parent] and S[parent].parent and rawget(S[parent].parent, "buttons") ~= nil
                piece = (s.text or "") ~= "" and not own and not inChoice
            elseif rawget(obj, "box") and rawget(obj, "text") then
                piece = true
            elseif rawget(obj, "buttons") and rawget(obj, "SetSelected") then
                piece = true
            elseif s.kind == "Button" and rawget(obj, "label") then
                piece = not (parent and rawget(parent, "buttons"))
            elseif s.kind == "Button" and rawget(obj, "popup") then
                piece = true -- a colour's swatch, which opens its colours
            elseif s.kind == "EditBox" then
                piece = true
            elseif parent and rawget(parent, "track") == obj then
                piece = "track"
            end
            if piece then
                local l, t, r, b = Fit.Rect(obj)
                if piece == "track" then l, r = l - 5, r + 5 end
                list[#list + 1] = { l, t, r, b, obj = obj, name = Fit.Name(obj) }
            end
        end
    end
    return list
end
function Fit.Below(a, b)
    local at = S[b].parent
    while at do
        if at == a then return true end
        at = S[at] and S[at].parent
    end
    return false
end
-- Every piece on a page inside it and none on another: "" when all fit.
-- With boxes ({ frame, name } each: a panel drawn round some of the
-- pieces), a piece in a box is inside it too, past none of its edges, and
-- each box shown is clear of the pieces outside it, like a piece itself.
function Fit.Problems(root, boxes)
    local list, found, named = Fit.Pieces(root), {}, {}
    for _, box in ipairs(boxes or {}) do
        if box[1]:IsVisible() then
            named[box[1]] = box[2]
            local l, t, r, b = Fit.Rect(box[1])
            list[#list + 1] = { l, t, r, b, obj = box[1], name = box[2] }
        end
    end
    local rl, rt, rr, rb = Fit.Rect(root)
    for i, a in ipairs(list) do
        if a[1] < rl or a[3] > rr or a[2] < rt or a[4] > rb then found[#found + 1] = a.name .. " off the page" end
        -- The nearest box it's in, if any.
        local box = S[a.obj].parent
        while box and box ~= root and S[box] and not named[box] do box = S[box].parent end
        if box and named[box] then
            local l, t, r, b = Fit.Rect(box)
            if a[1] < l or a[3] > r or a[2] < t or a[4] > b then
                found[#found + 1] = ("%s out of %s (%.1f, %.1f to %.1f, %.1f in %.1f, %.1f to %.1f, %.1f)"):format(a.name, named[box],
                    a[1], a[2], a[3], a[4], l, t, r, b)
            end
        end
        for j = i + 1, #list do
            local b = list[j]
            if a[1] < b[3] and b[1] < a[3] and a[2] < b[4] and b[2] < a[4] and not Fit.Below(a.obj, b.obj) and not Fit.Below(b.obj, a.obj) then
                found[#found + 1] = a.name .. " on " .. b.name
            end
        end
    end
    return table.concat(found, "; ")
end
function Fit.Clear(a, b)
    local al, at, ar, ab = Fit.Rect(a)
    local bl, bt, br, bb = Fit.Rect(b)
    return not (al < br and bl < ar and at < bb and bt < ab)
end
-- The Look page's boxes: the preview, the choices under it and the Each bar box.
function Fit.LookBoxes(w)
    return { { S[w.lookOptions].points[1][2], "the preview" }, { w.lookOptions, "the choices" }, { w.eachPanel, "the Each bar box" } }
end
-- The Each bar box's rows, which scroll (so the page's check leaves them
-- out): each shown one across the list and clear of the list's note and
-- its button under them, and its icon, name, colour swatch and colour's
-- name inside it, none on another.
function Fit.Rows(w)
    local found = {}
    for i, row in ipairs(w.eachRows) do
        if row:IsVisible() then
            local scroll = S[S[row].parent].parent
            local sl, _, sr = Fit.Rect(scroll)
            local l, t, r, b = Fit.Rect(row)
            if l < sl or r > sr then found[#found + 1] = ("row %d (%.1f to %.1f) wider than the list (%.1f to %.1f)"):format(i, l, r, sl, sr) end
            for _, under in ipairs({ { w.eachEmpty, "the list's note" }, { w.eachFix, "its button" } }) do
                if under[1]:IsVisible() and not Fit.Clear(row, under[1]) then found[#found + 1] = ("row %d on %s"):format(i, under[2]) end
            end
            local parts = { { row.icon, "icon" }, { row.name, "name " .. tostring(S[row.name].text) },
                { row.chosen, "colour's name " .. tostring(S[row.chosen].text) }, { row.colour, "colour swatch" } }
            for p, part in ipairs(parts) do
                local pl, pt, pr, pb = Fit.Rect(part[1])
                if pl < l or pr > r or pt < t or pb > b then found[#found + 1] = ("row %d: %s out of its row"):format(i, part[2]) end
                for q = p + 1, #parts do
                    if not Fit.Clear(part[1], parts[q][1]) then found[#found + 1] = ("row %d: %s on %s"):format(i, part[2], parts[q][2]) end
                end
            end
        end
    end
    return table.concat(found, "; ")
end
-- The bars' list on the left, which scrolls once they don't all fit (so
-- the list's check leaves it out): each shown bar's row and + Add a bar
-- line across the list's width, none on another; in each row its name,
-- count and the icons showing inside it, none on another (a long name like
-- Cooldowns 2 clear of its count, the icons under the name).
function Fit.BarList(w)
    local found, parts = {}, {}
    local content = w.barList.content
    local sl, _, sr = Fit.Rect(w.barList)
    for key, item in pairs(w.nav) do
        if S[item].parent == content and item:IsVisible() then parts[#parts + 1] = { item, key } end
    end
    for kind, line in pairs(w.navPlus) do
        if line:IsVisible() then parts[#parts + 1] = { line, "+" .. kind } end
    end
    for i, part in ipairs(parts) do
        local l, t, r, b = Fit.Rect(part[1])
        if l < sl or r > sr then found[#found + 1] = ("%s (%.1f to %.1f) wider than the list (%.1f to %.1f)"):format(part[2], l, r, sl, sr) end
        for j = i + 1, #parts do
            if not Fit.Clear(part[1], parts[j][1]) then found[#found + 1] = part[2] .. " on " .. parts[j][2] end
        end
        local bits = { { part[1].label, "name " .. tostring(S[part[1].label].text) } }
        if part[1].count then
            bits[#bits + 1] = { part[1].count, "count " .. tostring(S[part[1].count].text) }
            for n, icon in ipairs(part[1].icons) do
                if icon:IsVisible() then bits[#bits + 1] = { icon, "icon " .. n } end
            end
        end
        for p, bit in ipairs(bits) do
            local pl, pt, pr, pb = Fit.Rect(bit[1])
            if pl < l or pr > r or pt < t or pb > b then found[#found + 1] = ("%s: %s out of it"):format(part[2], bit[2]) end
            for q = p + 1, #bits do
                if not Fit.Clear(bit[1], bits[q][1]) then found[#found + 1] = ("%s: %s on %s"):format(part[2], bit[2], bits[q][2]) end
            end
        end
    end
    return table.concat(found, "; ")
end

-- The ?'s tooltip: just under it, in the addon's own look ------------------------------------------
-- Hovering the ? shows a small tooltip under it, as Show me what's new's
-- does above that button: not the footer. Leaving it, clicking it or
-- closing the window puts it away. Show me what's new's stays above.

;(function()
    local ns = Start({ useBars = true, notesSeen = "dev", helpSeen = true })
    for _, timer in ipairs(timers) do timer() end
    SlashCmdList.FECM("")
    local w, T = FECMFrame, ns.Theme
    local help = w.help
    local resting = S[w.note].text
    S[help].scripts.OnEnter(help)
    local tip = T.tip
    local p = S[tip].points[1]
    Equal(S[tip.title].text .. " | " .. S[tip.text].text .. " | " .. tostring(S[tip].shown) .. " | " .. p[1] .. " " .. tostring(p[2] == help)
        .. " " .. p[3] .. " " .. p[4] .. " " .. p[5] .. " | " .. tostring(Last(tip, "SetClampedToScreen")) .. " " .. Last(tip, "SetFrameStrata"),
        "PAGE HELP | Walks you through this page, a step at a time. | true | TOPRIGHT true BOTTOMRIGHT 0 -6 | true TOOLTIP",
        "hovered: Page help, just under the ?, lined up with its right edge, kept on screen")
    Equal(tostring(help.hint) .. " | " .. tostring(S[w.note].text == resting), "nil | true", "the footer stays as it was: no note there for the ?")
    local l, t, r, b = Fit.Rect(tip)
    local _, _, _, helpBottom = Fit.Rect(help)
    Equal(tostring(l >= 0 and r <= 820 and b <= 560) .. " " .. Num(t - helpBottom) .. " " .. tostring(Fit.Clear(tip, w.close)) .. " "
        .. tostring(Fit.Clear(tip, w.profileButton)), "true 6.00 true true",
        "inside the window, which stays on screen, 6 under the ?, clear of the X and the profile menu's button")
    Equal(S[tip].border[1] .. " " .. S[tip.title].colour[1], "0.69 0.69", "edged and headed in the accent, as Show me what's new's")
    S[help].scripts.OnLeave(help)
    Equal(tostring(S[tip].shown), "false", "gone as the mouse leaves")
    S[help].scripts.OnEnter(help)
    help:Click()
    Equal(tostring(S[tip].shown) .. " " .. tostring(S[FECMTour].shown), "false true", "clicked: gone, and the page's walkthrough starts")
    FECMTour.skip:Click()
    S[help].scripts.OnEnter(help)
    w:Hide()
    Equal(tostring(S[tip].shown), "false", "gone with the window")
    -- Another button's tooltip: the ? never takes it away, and it still
    -- shows above its button.
    w:Show()
    T:ShowTip(w.news, "What's new", "What changed.")
    p = S[tip].points[1]
    T:HideTip(help)
    Equal(tostring(S[tip].shown) .. " " .. p[1] .. " " .. tostring(p[2] == w.news) .. " " .. p[3] .. " " .. p[4] .. " " .. p[5],
        "true BOTTOM true TOP 0 6", "another's tooltip stays above its button, and the ? leaves it be")
    T:HideTip()
    Equal(tostring(S[tip].shown), "false", "and goes when it's put away")
    Equal(#printed, 0, "no errors from the tooltip")
end)()

-- A first install: the ? pulses and a note points it out, after the welcome -------------------------
-- Until the ? is first clicked, it glows softly in the accent, slow, dim to
-- lit and back, and a note under it, its arrow pointing up at it, says
-- what it's for, with an x to put it away. Neither shows while the welcome,
-- the tour or a walkthrough is up, nor over the profile menu or What's new:
-- they come back after, and each time the window opens. The note sits under
-- the title bar, inside the window, over the page, under the profile menu,
-- the tour and Are you sure?, and only on a page with room for it (below).

;(function()
    local ns = Start(nil)
    local db = ForeverEnhancedCooldownManagerDB
    Equal(tostring(ns.firstInstall) .. " " .. tostring(db.helpSeen) .. " " .. tostring(ns.HelpSeen()), "true nil false",
        "a first install: the ? not clicked yet")
    for _, timer in ipairs(timers) do timer() end
    local w, box, T = FECMFrame, FECMTour, ns.Theme
    local nudge, help = w.helpNudge, w.help
    Step(w, .5)
    Equal(S[box.title].text .. " " .. tostring(S[box].shown) .. " | " .. Nudge(w), "WELCOME true | false false",
        "the welcome: no note, no pulse")
    box.skip:Click()
    Step(w, 0)
    Equal(Nudge(w) .. " " .. S[nudge.text].text, "true true New: click ? for help with any page", "skipped: the note and the pulse")
    -- Take the tour instead: hidden for every step, back after.
    ns.Tour:Welcome()
    Step(w, 0)
    Equal(Nudge(w), "false false", "the welcome again: hidden")
    box.next:Click()
    Step(w, 0)
    local steps = 0
    local hidden = true
    repeat
        steps = steps + 1
        Step(w, .3)
        if w.helpNudge:IsVisible() or help.glow:IsVisible() then hidden = false end
        box.next:Click()
    until not S[box].shown or steps > 20
    Step(w, 0)
    Equal(tostring(steps) .. " " .. tostring(hidden) .. " | " .. w.selected .. " " .. Nudge(w), "9 true | cast false true",
        "taken: hidden on all nine steps of the tour; done on Cast bar, the pulse is back, the note waits for a page with room")
    w:Select("cd")
    Step(w, 0)
    Equal(Nudge(w), "true true", "and the note shows on Cooldowns")
    -- A page's walkthrough started any other way: hidden too.
    ns.Tour:StartPage("general")
    Step(w, 0)
    Equal(Nudge(w), "false false", "a walkthrough showing: hidden")
    box.skip:Click()
    Step(w, 0)
    Equal(Nudge(w), "true true", "back after it")
    -- Over the profile menu and What's new: hidden while they're open.
    w.profileButton:Click()
    Step(w, 0)
    local menu = Nudge(w)
    w.profileButton:Click()
    Step(w, 0)
    ns.ShowNotes()
    Step(w, 0)
    local news = Nudge(w)
    ns.notes:Hide()
    Step(w, 0)
    Equal(menu .. " | " .. news .. " | " .. Nudge(w), "false false | false false | true true", "not over the profile menu or What's new")

    -- The pulse: slow and light, dim to lit and back, in the accent.
    w:Hide()
    Equal(tostring(S[nudge].shown) .. " " .. tostring(S[help.glow].shown) .. " " .. tostring(nudge.driver:IsVisible()), "false false false",
        "closed: the note and the glow go with the window")
    w:Show()
    Equal(tostring(S[nudge].shown), "false", "opened again: not before the game's next frame, which knows what else is up")
    Step(w, 0)
    local glow = help.glow
    local accent, edge = T:Accent(), T.CONTROL_BORDER
    local function Pulse() return Num(S[glow].alpha) .. " " .. Num(S[help].border[1]) end
    local dim = Pulse()
    Step(w, .6)
    local quarter = Pulse()
    Step(w, .6)
    local lit = Pulse()
    Step(w, 1.2)
    local back = Pulse()
    Equal(dim .. " | " .. quarter .. " | " .. lit .. " | " .. back,
        Num(0) .. " " .. Num(edge[1]) .. " | " .. Num(.15) .. " " .. Num(edge[1] + (accent[1] - edge[1]) * .4) .. " | " .. Num(.3) .. " "
            .. Num(edge[1] + (accent[1] - edge[1]) * .8) .. " | " .. Num(0) .. " " .. Num(edge[1]),
        "dim as it opens, lit after 1.2 seconds (a third of the accent inside, most of it on the edge), dim again at 2.4")
    Equal(tostring(S[glow].shown) .. " " .. Last(glow, "SetColorTexture") .. " " .. tostring(S[glow].parent == help) .. " "
        .. S[glow].points[1][1] .. " " .. S[glow].points[2][1], "true " .. accent[1] .. " true TOPLEFT BOTTOMRIGHT",
        "the ?'s own glow, in the accent, inside it")
    -- A new accent: the note, its arrow and the glow follow.
    ns.Set("accent", "teal")
    T:Repaint()
    Step(w, 1.2)
    local teal = T.ACCENTS.teal.colour
    Equal(S[nudge].border[1] .. " " .. S[nudge.arrow].tint[1] .. " " .. Last(glow, "SetColorTexture") .. " " .. Num(S[help].border[1]),
        teal[1] .. " " .. teal[1] .. " " .. teal[1] .. " " .. Num(edge[1] + (teal[1] - edge[1]) * .8), "a new accent: all of it follows")
    ns.Set("accent", "purple")
    T:Repaint()

    -- Where the note sits: under the title bar, inside the window, its
    -- arrow pointing up at the ?, clear of the title bar's buttons.
    local l, t, r, b = Fit.Rect(nudge)
    local _, _, _, headerBottom = Fit.Rect(w.header)
    local al, at, ar, ab = Fit.Rect(nudge.arrow)
    local hl, _, hr, hb = Fit.Rect(help)
    Equal(tostring(l >= 0 and r <= 820 and b <= 560) .. " " .. tostring(t >= headerBottom) .. " " .. tostring(Last(w, "SetClampedToScreen"))
        .. " " .. tostring(Last(nudge, "SetClampedToScreen")), "true true true true",
        "inside the window, which stays on screen, and under the title bar")
    Equal(Num((al + ar) / 2 - (hl + hr) / 2) .. " " .. Num(at - hb) .. " " .. Num(ab - t) .. " " .. S[nudge.arrow].texture
        .. " " .. table.concat({ Last(nudge.arrow, "SetTexCoord", 1), Last(nudge.arrow, "SetTexCoord", 3) }, ","),
        "0.00 4.00 0.00 " .. ns.MEDIA .. "TourArrow.tga 0,0", "its arrow on its top edge, under the middle of the ?, pointing up, 4 below it")
    local clear = {}
    for _, part in ipairs({ help, w.close, w.profileButton }) do
        clear[#clear + 1] = tostring(Fit.Clear(nudge, part) and Fit.Clear(nudge.arrow, part))
    end
    Equal(table.concat(clear, " "), "true true true", "clear of the ?, the X and the profile menu's button")
    -- Its text on one line with room to spare, clear of its x.
    local text = S[nudge.text]
    local xl = Fit.Rect(nudge.close)
    local tl, _, tr = Fit.Rect(nudge.text)
    Equal(tostring(Fit.Wide(text.text, text.template) <= text.width) .. " " .. tostring(l + 10 + text.width + 4 <= xl) .. " "
        .. tostring(tl >= l + 10 and tr <= xl - 4) .. " " .. S[nudge].height .. " " .. tostring(r - (xl + 16) >= 4),
        "true true true 28 true", "its words on one line, clear of its x, which sits inside it")
    -- Under the profile menu, the tour and Are you sure?.
    local level = Last(nudge, "SetFrameLevel")
    Equal(tostring(level < Last(w.profilePanel, "SetFrameLevel")) .. " " .. tostring(level < Last(box, "SetFrameLevel")) .. " "
        .. tostring(level < Last(box.outline, "SetFrameLevel")) .. " " .. tostring(level < Last(w.confirm.shade, "SetFrameLevel")),
        "true true true true", "under the profile menu, the tour's outline and box, and Are you sure?")
    Equal(tostring(Last(nudge, "EnableMouse")) .. " | " .. nudge.close.hint,
        "true | Put this note away. The ? stays, for help with any page.",
        "it takes the clicks over it, and its x says what it does")

    -- Its x: gone for good, saved.
    nudge.close:Click()
    Step(w, 1)
    Equal(tostring(db.helpSeen) .. " " .. tostring(ns.HelpSeen()) .. " | " .. Nudge(w) .. " " .. tostring(nudge.driver:IsVisible()) .. " "
        .. Num(S[help].border[1]), "true true | false false false " .. Num(edge[1]), "x clicked: saved, the note and pulse gone, the ?'s edge as it was")
    w:Hide()
    w:Show()
    Step(w, 1)
    Equal(Nudge(w), "false false", "and they stay gone when the window opens again")
    Equal(#printed, 0, "no errors from the note")
end)()

-- The note never over a page's buttons or words ----------------------------------------------------
-- It takes the clicks over it, so it shows only where nothing is under it:
-- the four bar pages and General. Elsewhere (Layout's Undo, Reset and Turn
-- off, the Preview button, Look's Turn on, a long status line) only the ?
-- pulses, so every button there stays clickable. Checked in the states that
-- change what a page's top row shows.

;(function()
    local ns = Start({ useBars = true, notesSeen = "dev" })
    for _, timer in ipairs(timers) do timer() end
    SlashCmdList.FECM("")
    local w = FECMFrame
    local nudge, glow = w.helpNudge, w.help.glow
    local shownOn, problems = {}, {}
    local function Check(key, label)
        label = label or key
        w:Select(key)
        Step(w, 0)
        if not glow:IsVisible() then problems[#problems + 1] = label .. ": no pulse" end
        if not nudge:IsVisible() then return end
        shownOn[#shownOn + 1] = label
        -- Anything on the page that takes the mouse, any words, any slider.
        local root = w.pages[key] or w.pages.bar
        for _, obj in ipairs(objects) do
            local s = S[obj]
            local kind = s.kind
            local counts = Last(obj, "EnableMouse") or kind == "Button" or kind == "EditBox" or kind == "Slider"
                or (kind == "FontString" and (s.text or "") ~= "")
            if counts and obj ~= root and Fit.Inside(obj, root) and obj:IsVisible()
                and not (Fit.Clear(nudge, obj) and Fit.Clear(nudge.arrow, obj)) then
                problems[#problems + 1] = label .. ": " .. Fit.Name(obj)
            end
        end
    end
    for _, key in ipairs({ "cd", "util", "buff", "debuff", "look", "layout", "cast", "general", "raid", "pulse" }) do Check(key) end
    -- Layout with a layout picked: Undo, Reset and Turn off along its top row.
    local layout = w.pages.layout
    layout.cards[1]:Click()
    Check("layout", "layout picked")
    Equal(tostring(S[layout.undo].shown) .. " " .. S[layout.toggle.label].text .. " | " .. Nudge(w), "true Turn off | false true",
        "Layout with Undo, Reset and Turn off showing: only the pulse, nothing over them")
    -- Look with the display off: its Turn on button.
    cvarOn, prdOn = false, false
    ns.Set("prdSkin", true)
    Check("look", "look with warnings")
    cvarOn, prdOn = true, true
    -- General with EraUI there, a bar page with your bars off, one taken out.
    _G.C_AddOns = { IsAddOnLoaded = function(name) return name == "EraUI" end }
    Check("general", "general with EraUI")
    _G.C_AddOns = nil
    ns.Set("useBars", false)
    Check("cd", "cd bars off")
    Check("general", "general bars off")
    ns.Set("useBars", true)
    ns.Layout:TakeOut("util")
    Check("util", "util taken out")
    Equal(table.concat(shownOn, ", "), "cd, util, buff, debuff, general, general with EraUI, cd bars off, general bars off, util taken out",
        "the note shows on the bar pages and General only")
    Equal(table.concat(problems, "; "), "", "where it shows, nothing on the page is under it; the ? pulses on every page")
    -- A bar with spells shows Clear at the right of its top row, an extra
    -- bar's page Remove bar there: only the ? pulses, as on other pages with
    -- buttons there. An empty bar's page still has the note, even with an
    -- extra bar of its kind (added from the list now, no button there).
    ns.Bars:SetAura("debuff", "Moonfire", true)
    w:Select("debuff")
    Step(w, 0)
    local bp = w.pages.bar
    local withSpells = Nudge(w) .. " " .. tostring(bp.clear:IsVisible()) .. " " .. tostring(bp.another:IsVisible())
    ns.Bars:AddBar("buff")
    w:Select("buff2")
    Step(w, 0)
    local extra = Nudge(w) .. " " .. tostring(bp.another:IsVisible())
    Check("buff", "buff empty with Buffs 2 there")
    Equal(withSpells .. " | " .. extra .. " | " .. Nudge(w) .. " " .. tostring(bp.clear:IsVisible()) .. " " .. tostring(bp.another:IsVisible())
        .. " | " .. table.concat(problems, "; "), "false true true false | false true true | true true false false | ",
        "a bar with spells: Clear shows, the note doesn't (the ? still pulses); an extra bar's page: Remove bar, no note; an empty"
        .. " bar's page keeps the note, with an extra bar of its kind too, over nothing")
    ns.Bars:RemoveBar("buff2")
    Equal(#printed, 0, "no errors")
end)()

-- Clicking the ?: its walkthrough, and the pulse and note gone for good ---------------------------
-- An upgrade (saved settings without it) starts as a first install does.
-- Kept over a reload; anything but true saved for it reads as not clicked.

;(function()
    local ns = Start({ useBars = true, notesSeen = "dev" })
    for _, timer in ipairs(timers) do timer() end
    local db = ForeverEnhancedCooldownManagerDB
    SlashCmdList.FECM("")
    local w = FECMFrame
    Step(w, 0)
    Equal(tostring(db.helpSeen) .. " " .. Nudge(w), "nil true true", "an upgrade: the note and the pulse on opening")
    w:Select("look")
    w.help:Click()
    local box = FECMTour
    Step(w, 0)
    Equal(tostring(db.helpSeen) .. " " .. S[box.title].text .. " " .. S[box.count].text .. " | " .. Nudge(w),
        "true THE LOOK 1 of 8 | false false", "? clicked: the Look page's walkthrough, the pulse and note gone, saved")
    box.skip:Click()
    Step(w, 0)
    Equal(Nudge(w) .. " " .. tostring(w.helpNudge.driver:IsVisible()), "false false false", "gone for good after it")

    -- Kept over a reload.
    local saved = ForeverEnhancedCooldownManagerDB
    ns = Start(saved)
    for _, timer in ipairs(timers) do timer() end
    SlashCmdList.FECM("")
    w = FECMFrame
    Step(w, 1)
    Equal(tostring(ns.HelpSeen()) .. " " .. Nudge(w) .. " " .. tostring(S[w.helpNudge.driver].shown), "true false false false",
        "after a reload: still gone, nothing running for it")

    -- Anything else saved: repaired to not clicked, so it shows.
    local repaired = {}
    for _, bad in ipairs({ "yes", 1, false, {} }) do
        ns = Start({ useBars = true, notesSeen = "dev", helpSeen = bad })
        for _, timer in ipairs(timers) do timer() end
        SlashCmdList.FECM("")
        Step(FECMFrame, 0)
        repaired[#repaired + 1] = tostring(ForeverEnhancedCooldownManagerDB.helpSeen) .. " " .. Nudge(FECMFrame)
    end
    Equal(table.concat(repaired, ", "), "nil true true, nil true true, nil true true, nil true true",
        "a bad saved value is cleared on load, and the note shows")
    Equal(#printed, 0, "no errors")
end)()

-- The Layout page's foot: every label with room ----------------------------------------------------
-- On a screenshot of the game Live preview's label ran into Row spacing's. Live
-- preview is now the drawing's own tick, in its box's bottom left corner,
-- level with Unlock bars; under the box, three rows: Show grow arrows and
-- All bars, Show the Personal Resource Display and Row spacing, Match the
-- resource display and Icon spacing. All bars' longer label has room before
-- its track, which lines up with the spacing sliders'. The title row's
-- words stay clear of Undo and Reset, whatever it says.

;(function()
    local ns = Start({ useBars = true, notesSeen = "dev", helpSeen = true })
    for _, timer in ipairs(timers) do timer() end
    SlashCmdList.FECM("")
    local w = FECMFrame
    w:Select("layout")
    local page = w.pages.layout
    local L = ns.Layout
    Equal(Fit.Problems(page), "", "at the start: every label clear of the next control, all inside the page")
    -- Under the box: three rows, each tick level with its slider, clear of it.
    local function Middle(obj)
        local _, t, _, b = Fit.Rect(obj)
        return (t + b) / 2
    end
    Equal(tostring(Middle(page.growArrows) == Middle(page.allBars)) .. " " .. tostring(Middle(page.shown) == Middle(page.spacing)) .. " "
        .. tostring(Middle(page.match) == Middle(page.iconSpacing)), "true true true", "each tick level with its slider")
    local tracks = {}
    local pageLeft = Fit.Rect(page)
    for _, slider in ipairs({ page.allBars, page.spacing, page.iconSpacing }) do tracks[#tracks + 1] = Num(Fit.Rect(slider.track) - pageLeft) end
    local _, _, _, boxBottom = Fit.Rect(page.box)
    local _, allTop = Fit.Rect(page.allBars)
    Equal(table.concat(tracks, " ") .. " " .. Num(allTop - boxBottom), "482.00 482.00 482.00 10.00", "the tracks lined up, All bars 10 under the box")
    -- Each slider's label clear of its track, which its thumb reaches 5
    -- back over at the lowest, and each value clear of the thumb at the
    -- highest, inside its own room.
    local tight = {}
    for _, slider in ipairs({ page.allBars, page.spacing, page.iconSpacing }) do
        local label, track = S[slider.label], S[slider.track].points
        if Fit.Wide(label.text, label.template) + 5 + 3 > track[1][2] then tight[#tight + 1] = label.text end
        for _, value in ipairs({ "0", "20", "50", "150" }) do
            local shown = S[slider.value]
            if Fit.Wide(value, shown.template) + 5 > -track[2][2] or Fit.Wide(value, shown.template) > shown.width then
                tight[#tight + 1] = label.text .. " at " .. value
            end
        end
    end
    Equal(table.concat(tight, ", "), "", "every slider's label clear of its track, every value inside its room")
    -- Live preview: the drawing's own tick, in the box's foot, where the
    -- drawing never goes, clear of Put back and Unlock bars.
    local ll, lt, lr, lb = Fit.Rect(page.live)
    local bl, _, _, bb = Fit.Rect(page.box)
    local _, unlockTop = Fit.Rect(page.unlock)
    Equal(tostring(S[page.live].parent == page.box) .. " " .. Num(ll - bl) .. " " .. Num(bb - lb) .. " " .. tostring(bb - lt <= 28) .. " "
        .. tostring(Middle(page.live) == Middle(page.unlock)) .. " " .. tostring(Fit.Clear(page.live, page.unlock)) .. " " .. Num(unlockTop - lt),
        "true 12.00 10.00 true true true -1.00", "in the box's bottom left corner, within the room its foot keeps clear, level with Unlock bars")
    -- Bars taken out: Put back and its buttons after it, two to a line, none
    -- on Live preview or Unlock bars.
    for _, key in ipairs(ns.BAR_KEYS) do L:TakeOut(key) end
    w:Refresh()
    Equal(Fit.Problems(page), "", "all four taken out: Put back and its buttons clear of Live preview, Unlock bars and each other")
    for _, key in ipairs(ns.BAR_KEYS) do L:PutBack(key) end
    w:Refresh()

    -- The title row, whatever it says, clear of Undo or Reset.
    local said = {}
    local function Check(label)
        said[#said + 1] = S[page.status].text
        local problems = Fit.Problems(page)
        if problems ~= "" then said[#said] = label .. ": " .. problems end
    end
    Check("start")
    page.cards[1]:Click()
    Equal(tostring(S[page.undo].shown), "true", "a layout picked: Undo shows")
    Check("picked")
    prdOn = false
    w:Refresh()
    Check("display off")
    prdOn = true
    ns.Bars:SetUnlocked(true)
    w:Refresh()
    Check("unlocked")
    ns.Bars:SetUnlocked(false)
    L:TurnOff()
    L.moved = true
    w:Refresh()
    Check("moved")
    L.moved = nil
    w:Refresh()
    Check("off")
    ns.Set("useBars", false)
    w:Refresh()
    Check("bars off")
    ns.Set("useBars", true)
    Equal(table.concat(said, " | "), "Pick a layout to stack your bars around the display. | Your bars follow your resource display. | "
        .. "Your rows close up where the display would be. | Unlocked: drag a bar on screen to move it. | "
        .. "You moved a bar, so they're no longer stacked. | Your bars stay where you put them. | Your bars are off.",
        "every state's words, each clear of Undo, Reset and Turn on")
    Equal(#printed, 0, "no errors")
end)()

-- Every page in the window: no label runs into the next control -----------------------------------
-- Each page the window builds, in the states that change what it shows.
-- Raid Timers isn't here: at this estimate a few of its labels reach a few
-- units into the next control or past the page's edge, but measured on
-- screenshots of the game (about 6.2 a letter, 5.25 small) they're clear.

;(function()
    local ns = Start({ useBars = true, notesSeen = "dev", helpSeen = true })
    for _, timer in ipairs(timers) do timer() end
    SlashCmdList.FECM("")
    local w = FECMFrame
    local found = {}
    -- (The Look page's pieces inside its boxes too: more of it below.)
    local function Check(key, label)
        w:Select(key)
        local problems = Fit.Problems(w.pages[key] or w.pages.bar, key == "look" and Fit.LookBoxes(w) or nil)
        if problems ~= "" then found[#found + 1] = (label or key) .. ": " .. problems end
    end
    for _, key in ipairs({ "cd", "util", "buff", "debuff", "look", "layout", "cast", "general", "pulse" }) do Check(key) end
    local problems = Fit.Problems(w.navFrame) .. Fit.BarList(w) .. Fit.Problems(w.header)
    if problems ~= "" then found[#found + 1] = "list or title bar: " .. problems end
    -- Look, with Blizzard's Cooldown Manager and your display off, a reload
    -- waiting: the warnings take their rows' room.
    cvarOn, prdOn = false, false
    ns.Set("prdSkin", true)
    ns.Set("skin", not ns.Get("skin"))
    Check("look", "look with warnings")
    cvarOn, prdOn = true, true
    -- Cast bar, with crafting, tick marks and latency on: both previews in
    -- the tray, tallest, the ticks' colour, style and width under their
    -- tick, and latency's Show ms and colours under those.
    ns.Set("castBatch", true)
    ns.Set("castTicks", true)
    ns.Set("castLatency", true)
    ns.Set("castTimeFormat", "total")
    ns.Set("castHeight", ns.CAST_HEIGHT[2])
    Check("cast", "cast with crafting, tick marks and latency")
    local cast = w.pages.cast
    Equal(tostring(cast.tickSample:IsVisible()) .. " " .. tostring(cast.tickStyle:IsVisible()) .. " "
        .. tostring(cast.tickWidth:IsVisible()) .. " " .. tostring(cast.tickColour:IsVisible()) .. " "
        .. tostring(cast.latencyMs:IsVisible()) .. " " .. tostring(cast.latencyColour:IsVisible()), "true true true true true true",
        "(the tick marks' preview, style, width and colour, and latency's Show ms and colour, checked there)")
    ns.Set("castTicks", false)
    w:Select("cast")
    Check("cast", "cast with latency, tick marks off")
    Equal(tostring(cast.tickSample:IsVisible()) .. " " .. tostring(cast.tickStyle:IsVisible()) .. " "
        .. tostring(S[cast.latency].points[1][3]), "false false -204",
        "with tick marks off, their preview and choices hide, and latency moves up under them")
    ns.Set("castLatency", false)
    w:Select("cast")
    Equal(tostring(cast.latencyMs:IsVisible()) .. " " .. tostring(cast.latencyColour:IsVisible()), "false false",
        "with latency off, Show ms and its colour hide")
    ns.Set("castBatch", false)
    ns.Set("castTimeFormat", "left")
    ns.Set("castHeight", ns.CAST_HEIGHT[3])
    -- General, with EraUI there: Open instead of its links.
    _G.C_AddOns = { IsAddOnLoaded = function(name) return name == "EraUI" end }
    Check("general", "general with EraUI")
    _G.C_AddOns = nil
    -- A bar page with your bars off, and one taken out of the layout.
    ns.Set("useBars", false)
    Check("cd", "bars off")
    ns.Set("useBars", true)
    ns.Layout:TakeOut("util")
    Check("util", "taken out")
    -- Extra bars: with spells on it, Clear, and + Add a bar under Cooldowns
    -- in the list (checked too); Cooldowns 2's page, its title the longest,
    -- with Remove bar, and taken out of the layout too.
    ns.Bars:Assign("Moonfire", "cd")
    Check("cd", "cd with spells")
    local plus = Fit.Problems(w.navFrame) .. Fit.BarList(w)
    if plus ~= "" then found[#found + 1] = "the list with + Add a bar under Cooldowns: " .. plus end
    ns.Bars:AddBar("cd")
    Check("cd", "cd with Cooldowns 2 there")
    Check("cd2", "Cooldowns 2, empty: Remove bar in Clear's place")
    ns.Bars:Assign("Wrath", "cd2")
    Check("cd2", "Cooldowns 2")
    ns.Layout:TakeOut("cd2")
    Check("cd2", "Cooldowns 2 taken out")
    Equal(tostring(w.pages.bar.another:IsVisible()) .. " " .. S[w.pages.bar.another.label].text .. " " .. tostring(w.pages.bar.putBack:IsVisible())
        .. " " .. tostring(w.pages.bar.clear:IsVisible()), "true Remove bar true true", "(Remove bar, Put back and Clear all checked there)")
    -- Four extra bars, third ones too (a player's idea: a third cooldown
    -- bar): Cooldowns 3's page, Cooldowns', the list of eight bars on the
    -- left with every kind's + Add a bar line (the most it ever holds), and
    -- the Layout page with all eight taken out (Put back and its buttons,
    -- four lines of two).
    ns.Layout:PutBack("cd2")
    ns.Bars:AddBar("cd")
    ns.Bars:AddBar("debuff")
    ns.Bars:AddBar("debuff")
    ns.Bars:Assign("Overpower", "cd3")
    ns.Bars:Assign("Thorns", "util")
    ns.Bars:SetAura("buff", "Thorns", true)
    Check("cd3", "Cooldowns 3")
    Check("cd", "cd with Cooldowns 2 and 3 there")
    Check("debuff3", "Debuffs 3, empty")
    local eight = Fit.Problems(w.navFrame) .. Fit.BarList(w)
    if eight ~= "" then found[#found + 1] = "the list with eight bars: " .. eight end
    local lines = {}
    for _, kind in ipairs(ns.BASE_BAR_KEYS) do lines[#lines + 1] = tostring(w.navPlus[kind]:IsVisible()) end
    for _, key in ipairs(ns.BAR_KEYS) do ns.Layout:TakeOut(key) end
    Check("layout", "layout with all eight taken out")
    for _, key in ipairs(ns.BAR_KEYS) do ns.Layout:PutBack(key) end
    Equal(table.concat(ns.BAR_KEYS, " ") .. " | " .. tostring(w.nav.cd3:IsVisible()) .. " " .. tostring(w.nav.debuff3:IsVisible())
        .. " | " .. table.concat(lines, " "), "cd cd2 cd3 util buff debuff debuff2 debuff3 | true true | true true true true",
        "(eight bars, each in the list, and four + Add a bar lines, checked there)")
    for _, key in ipairs({ "cd3", "debuff3", "debuff2" }) do ns.Bars:RemoveBar(key) end
    ns.Bars:Assign("Overpower", nil)
    ns.Bars:Assign("Thorns", nil)
    ns.Bars:SetAura("buff", "Thorns", false)
    ns.Bars:RemoveBar("cd2")
    ns.Bars:Assign("Moonfire", nil)
    -- Buffs with Only show missing: rows, names and missing ones greyed
    -- (greyed out) all there, and its tick under the sliders.
    ns.Bars:SetOption("buff", "onlyMissing", true)
    Check("buff", "buff with only show missing")
    local bp = w.pages.bar
    Equal(tostring(bp.options.onlyMissing:IsVisible()) .. " " .. tostring(bp.across:IsVisible()) .. " "
        .. tostring(bp.options.wrap:IsVisible()) .. " " .. tostring(bp.options.showNames:IsVisible()),
        "true true true true", "(the tick, Icons per row, New rows and Show spell names all checked there)")
    -- Debuffs with missing ones greyed: Keep them greyed with no target
    -- under it, beside Show your debuffs on you.
    ns.Bars:SetOption("debuff", "showMissing", true)
    ns.Bars:SetOption("debuff", "greyedNoTarget", true)
    Check("debuff", "debuff with keep them greyed")
    Equal(tostring(bp.options.keepGreyed:IsVisible()) .. " " .. tostring(bp.options.showSelf:IsVisible()) .. " "
        .. tostring(bp.options.showNames:IsVisible()) .. " " .. tostring(bp.options.keepGreyed.usable),
        "true true true true", "(Keep them greyed with no target, usable, beside Show your debuffs on you, checked there)")
    -- Group one-at-a-time spells: the General page's, beside Use my bars,
    -- ticked by default, saying what it does.
    w:Select("general")
    local families = w.groupFamilies
    local note = type(families.hint) == "function" and families.hint(families) or tostring(families.hint)
    Equal(tostring(families:IsVisible()) .. " " .. tostring(families:GetChecked()) .. " " .. S[families.text].text .. " | " .. note,
        "true true Group one-at-a-time spells | Only one Seal, Aura or Aspect, or Curse, Bane, Sting or Judgement, can be up,"
        .. " so side by side they're one icon on Buffs and Debuffs.", "(on the General page, ticked, with its note)")
    w:Select("debuff")
    -- Count ticks: a ticked debuff that ticks has its own tick at its row's
    -- end on the Debuffs page (not Wrath, which doesn't tick), saying its
    -- pace; ticking it keeps the debuff on. Joined with one that ticks
    -- differently, it says why it can't count, and greys once unticked.
    local B = ns.Bars
    B:SetAura("debuff", "Moonfire", true)
    B:SetAura("debuff", "Wrath", true)
    w:Refresh()
    local function RowOf(name)
        for _, row in ipairs(bp.rows) do
            if row:IsVisible() and row.spell == name then return row end
        end
    end
    local function Note(control) return type(control.hint) == "function" and control.hint(control) or tostring(control.hint) end
    local moonfire = RowOf("Moonfire")
    local opts = bp.options
    Equal(tostring(moonfire.ticks:IsVisible()) .. " " .. S[moonfire.ticks.text].text .. " " .. tostring(RowOf("Wrath").ticks:IsVisible())
        .. " " .. tostring(opts.tickAt:IsVisible()) .. " | " .. Note(moonfire.ticks), "true Count ticks false false | Counts its ticks on"
        .. " its icon, every 3 seconds for Moonfire, starting again when you reapply it.",
        "(Count ticks beside Moonfire, not Wrath, with its pace; the tick count's own options not yet)")
    moonfire.ticks:Click()
    Equal(tostring(B:CountsTicks("debuff", "Moonfire")) .. " " .. tostring(B:HasAura("debuff", "Moonfire")) .. " "
        .. tostring(RowOf("Moonfire").ticks:GetChecked()), "true true true", "(ticked: it counts, and Moonfire stays on the bar)")
    -- Then the tick count's two rows under the options: where, from 1,
    -- its size and colour, each clear of the next.
    Check("debuff", "debuff with the tick count's options")
    Equal(table.concat({ tostring(opts.tickAt:IsVisible()), tostring(opts.tickFrom:IsVisible()), tostring(opts.tickSize:IsVisible()),
        tostring(opts.tickChoice:IsVisible()), tostring(opts.tickFrom:GetChecked()), opts.tickAt.selected, S[opts.tickSize.value].text,
        tostring(opts.tickEdge:IsVisible()), tostring(opts.tickEdge:GetChecked()) }, " "),
        "true true true true true TOPLEFT 100% true false", "(they show: top left, from 1, at 100%, not on the edge)")
    opts.tickEdge:Click()
    Equal(tostring(ns.BarData("debuff").tickEdge) .. " | " .. Note(opts.tickEdge), "true | Centres the count on the icon's edge at its"
        .. " spot, half outside, so it covers less of the icon. Not for the centre.", "(On the edge ticks, saying what it does)")
    opts.tickEdge:Click()
    -- Glow when missing on the Debuffs page too, Count ticks just left of it.
    moonfire = RowOf("Moonfire")
    local tp = S[moonfire.ticks].points[1]
    Equal(tostring(moonfire.glow:IsVisible()) .. " " .. tostring(tp[2] == moonfire.glow) .. " " .. tp[1] .. " " .. tp[3] .. " | "
        .. Note(moonfire.glow), "true true RIGHT LEFT | Its icon glows while it's missing from an enemy you target, like a Judgement"
        .. " that fell off.", "(Glow when missing on the Debuffs page, Count ticks left of it)")
    opts.tickAt.buttons[2]:Click()
    Equal(ns.BarData("debuff").tickAt .. " " .. S[opts.tickAt.buttons[2].label].text, "TOP Top centre", "(top centre, a player's pick)")
    opts.tickAt.buttons[4]:Click()
    opts.tickFrom:Click()
    opts.tickSwatches[2]:Click()
    local debuffs = ns.BarData("debuff")
    Equal(debuffs.tickAt .. " " .. debuffs.tickFrom .. " " .. debuffs.tickColour .. " | " .. Note(opts.tickAt.buttons[4]),
        "CENTER 0 gold | Where the tick count sits on each icon. The centre is the countdown's: untick Show countdown numbers to keep"
        .. " it clear.", "(the centre, from 0, gold: saved, and the centre says it's the countdown's)")
    opts.tickAt.buttons[1]:Click()
    opts.tickFrom:Click()
    opts.tickSwatches[1]:Click()
    local wrathAt
    for i, name in ipairs(ns.BarData("debuff").spells) do if name == "Wrath" then wrathAt = i end end
    B:SetJoined("debuff", wrathAt, true)
    w:Refresh()
    moonfire = RowOf("Moonfire")
    Equal(tostring(moonfire.ticks.usable) .. " | " .. Note(moonfire.ticks), "true | Can't count while it shares an icon with Wrath:"
        .. " the game can't tell the two apart.", "(joined with Wrath: says why it can't count, still untickable)")
    moonfire.ticks:Click()
    w:Refresh()
    Equal(tostring(B:CountsTicks("debuff", "Moonfire")) .. " " .. tostring(RowOf("Moonfire").ticks.usable), "false false",
        "(unticked, it greys while it can't count)")
    B:SetJoined("debuff", wrathAt, false)
    B:SetAura("debuff", "Wrath", false)
    B:SetAura("debuff", "Moonfire", false)
    w:Refresh()
    -- Glow when missing (the user: say what it needs): greyed, saying why,
    -- until Show missing buffs greyed or Only show missing is ticked.
    local buffs = ns.BarData("buff")
    local only, missing = buffs.onlyMissing, buffs.showMissing
    B:SetOption("buff", "onlyMissing", false)
    B:SetOption("buff", "showMissing", false)
    B:SetAura("buff", "Thorns", true)
    w:Select("buff")
    local thorns = RowOf("Thorns")
    Equal(tostring(thorns.glow:IsVisible()) .. " " .. tostring(thorns.glow.usable) .. " | " .. Note(thorns.glow), "true false | Tick Show"
        .. " missing buffs greyed or Only when missing first: the glow shows on a missing buff's greyed spot.", "(greyed, saying what it needs)")
    thorns.glow:Click()
    Equal(tostring(B:GlowsMissing("buff", "Thorns")), "false", "(a click does nothing while greyed)")
    -- Only when missing (a player's ask): on a ticked buff's row, just left
    -- of Glow when missing, off, saying what it does (seen working in game,
    -- so no longer marked experimental). Its
    -- row's name, it and Glow when missing each clear of the next, inside
    -- the row, with room for a long buff name.
    local op = S[thorns.only].points[1]
    Equal(table.concat({ tostring(thorns.only:IsVisible()), S[thorns.only.text].text, tostring(thorns.only:GetChecked()),
        tostring(thorns.only.usable), tostring(op[2] == thorns.glow), op[1], op[3], tostring(op[4]) }, " ") .. " | " .. Note(thorns.only),
        "true Only when missing false true true RIGHT LEFT -14 | Shows this buff only while it's missing from you, so you see to recast it."
        .. " The game hides your buffs from addons in a fight, so changes then show once it ends.",
        "(Only when missing beside Glow when missing, off, saying what it does)")
    local rl, _, rr = Fit.Rect(thorns)
    local nl = Fit.Rect(thorns.name)
    local ol, _, orr = Fit.Rect(thorns.only)
    local gl, _, gr = Fit.Rect(thorns.glow)
    Equal(tostring(Fit.Clear(thorns.name, thorns.only)) .. " " .. tostring(Fit.Clear(thorns.only, thorns.glow)) .. " "
        .. tostring(ol >= rl and gr <= rr and orr < gl) .. " " .. tostring(ol - nl >= 200), "true true true true",
        "(the name, Only when missing and Glow when missing clear of each other in the row, room for a 26-letter name)")
    thorns.only:Click()
    w:Refresh()
    thorns = RowOf("Thorns")
    Equal(tostring(B:OnlyWhenMissing("buff", "Thorns")) .. " " .. tostring(thorns.only:GetChecked()) .. " " .. tostring(B:HasAura("buff", "Thorns"))
        .. " " .. tostring(thorns.glow.usable) .. " | " .. Note(thorns.glow), "true true true true | Its icon glows while it's missing,"
        .. " so you see to recast it, like a Seal that fell off.", "(ticked: kept, Thorns stays on the bar, and its glow can go on its spot)")
    -- Greyed while Only show missing does it for every buff, saying so,
    -- keeping its own choice; a click does nothing then.
    B:SetOption("buff", "onlyMissing", true)
    w:Refresh()
    thorns = RowOf("Thorns")
    thorns.only:Click()
    Equal(tostring(thorns.only.usable) .. " " .. S[thorns.only].alpha .. " " .. tostring(thorns.only:GetChecked()) .. " "
        .. tostring(B:OnlyWhenMissing("buff", "Thorns")) .. " | " .. Note(thorns.only), "false 0.35 true true | Not needed with Only show"
        .. " missing, which already shows every buff only while it's missing.", "(greyed with Only show missing, its choice kept, saying why)")
    B:SetOption("buff", "onlyMissing", false)
    w:Refresh()
    RowOf("Thorns").only:Click()
    Equal(tostring(B:OnlyWhenMissing("buff", "Thorns")) .. " " .. tostring(RowOf("Thorns").glow.usable), "false false",
        "(unticked: off, and Glow when missing greyed again)")
    -- Not on the Debuffs page.
    B:SetAura("debuff", "Moonfire", true)
    w:Select("debuff")
    Equal(tostring(RowOf("Moonfire").only:IsVisible()), "false", "(no Only when missing on the Debuffs page)")
    B:SetAura("debuff", "Moonfire", false)
    w:Select("buff")
    B:SetOption("buff", "showMissing", true)
    w:Refresh()
    thorns = RowOf("Thorns")
    Equal(tostring(thorns.glow.usable) .. " | " .. Note(thorns.glow), "true | Its icon glows while it's missing, so you see to recast it,"
        .. " like a Seal that fell off.", "(with Show missing buffs greyed: usable, saying what it does)")
    thorns.glow:Click()
    Equal(tostring(B:GlowsMissing("buff", "Thorns")), "true", "(ticked)")
    B:SetGlowMissing("buff", "Thorns", false)
    B:SetAura("buff", "Thorns", false)
    B:SetOption("buff", "showMissing", missing)
    B:SetOption("buff", "onlyMissing", only)
    w:Select("debuff")
    -- Cooldowns with Swap with my form ticked (a druid with Bear Form): the
    -- tick, and Editing under it on the longest name it shows.
    table.insert(book[2].items, { name = "Bear Form", spellID = 5487, iconID = 132276 })
    ns.Spells:Stale()
    ns.Bars:SetOption("cd", "swapForm", true)
    w:Select("cd")
    ns.SetEditingForm(18)
    Check("cd", "cd with Swap with my form")
    Equal(tostring(bp.options.swapForm:IsVisible()) .. " " .. tostring(bp.options.editing:IsVisible()) .. " "
        .. S[bp.options.editing.name].text, "true true Defensive Stance", "(the tick and Editing, on its longest name, checked there)")
    ns.SetEditingForm(nil)
    -- A full bar (40 icons): the Cooldowns tray takes three rows, closer
    -- than an aura bar's, so under its taller options the spell list still
    -- shows two rows and more; the Buffs tray four, under its shorter ones.
    local profile = ForeverEnhancedCooldownManagerDB.profiles[ns.ProfileName()]
    local rows = {}
    for _, key in ipairs({ "cd", "buff" }) do
        local full = {}
        for i = 1, ns.BAR_MAX_SPELLS do full[i] = "item:" .. (20000 + i) end
        profile[key] = full
        ns.Bars:Changed()
        w:Select(key)
        Check(key, key .. " full")
        local shown, lowest = 0, 0
        for _, icon in ipairs(bp.icons) do
            if icon:IsVisible() then
                shown = shown + 1
                lowest = math.max(lowest, select(4, Fit.Rect(icon)))
            end
        end
        local _, top, _, bottom = Fit.Rect(bp.list)
        local _, trayTop, _, trayBottom = Fit.Rect(bp.tray)
        rows[#rows + 1] = key .. " " .. shown .. " icons in " .. tostring(lowest <= trayBottom) .. " " .. math.floor((bottom - top) / 22)
            .. " rows"
    end
    Equal(table.concat(rows, ", "), "cd 40 icons in true 2 rows, buff 40 icons in true 2 rows",
        "a full bar: every icon in its tray, and two rows of the spell list showing")
    Equal(table.concat(found, " | "), "", "on every page and in every state, each label clear of the next control, all inside the page")
    Equal(#printed, 0, "no errors")
end)()

-- The Cooldown pulse page with Procs too -----------------------------------------------------------
-- Its tick right under Trinkets and potions too, Master volume moved under
-- it, the options 156 tall: everything clear of the next control. Its hover
-- note quietly experimental, or greyed with why on a game without the
-- containers; the list's Procs header, a proc row's tick and switch, each
-- note within two lines of the footer; the title row's longest with procs.
;(function()
    local ns = Start({ notesSeen = "dev", helpSeen = true, pulse = true, pulseProcs = true })
    for _, timer in ipairs(timers) do timer() end
    SlashCmdList.FECM("")
    local w = FECMFrame
    local page = w.pages.pulse
    local function Note(control) return type(control.hint) == "function" and control.hint(control) or tostring(control.hint) end
    local function Fits(text) return Fit.Wide(text, S[w.note].template) <= 2 * S[w.note].width end
    ns.SetPulsePick("proc:16870", true)
    ns.SetPulsePick("Overpower", true)
    ns.Pulse:Apply()
    w:Select("pulse")
    local problems = Fit.Problems(page)
    local rows, header, clear = {}, nil, nil
    for _, row in ipairs(page.rows) do
        if row:IsVisible() and row.proc then rows[#rows + 1] = row end
        if row:IsVisible() and S[row.header].shown and S[row.header].text == "PROCS" then header = row end
    end
    local first = rows[1]
    Equal(problems .. " | " .. S[page.procs.text].text .. " " .. tostring(page.procs:GetChecked()) .. " " .. tostring(page.procs.usable) .. " | "
        .. S[page.options].height .. " " .. tostring(Fit.Clear(page.items, page.procs)) .. " " .. tostring(Fit.Clear(page.procs, page.volume)) .. " | "
        .. S[page.status].text, " | Procs too true true | 156 true true | 1 cooldown pulses when ready, 1 proc as it lands.",
        "Procs too and Master volume clear of each other and everything else, the title row's longest with procs too")
    Equal(tostring(header ~= nil) .. " " .. #rows .. " " .. S[first.name].text .. " | " .. Note(page.procs) .. " | " .. Note(first.check) .. " | "
        .. Note(rows[2].check) .. " | " .. Note(first.style.buttons[2]),
        "true 2 Clearcasting | Your class's procs, like Clearcasting or Missile Barrage: a pulse the moment one lands, in a fight too. Procs pulse"
        .. " without a sound. (experimental) | Untick to leave Clearcasting out. | Tick to pulse when Nature's Grace lands. (experimental) |"
        .. " Clearcasting pulses Quick. Click for Long. Each style has its own size and time, set under Edit above. Procs pulse without a sound.",
        "a Procs header and the druid's two named procs; the tick, a row's tick and its switch say what they do, quietly experimental")
    clear = Fits(Note(page.procs)) and Fits(Note(rows[2].check)) and Fits(Note(first.style.buttons[2]))
    Equal(tostring(clear), "true", "each note within two lines of the footer")
    -- A game without the containers: greyed, saying why.
    _G.CustomAuraContainerSlotDefaultOptions = nil
    w:Refresh()
    Equal(tostring(page.procs.usable) .. " " .. Note(page.procs) .. " | " .. Fit.Problems(page), "false Your game can't show proc pulses. | ",
        "greyed on a game that can't, saying why, still clear of the rest")
    _G.CustomAuraContainerSlotDefaultOptions = {}
    Equal(#printed, 0, "no errors")
end)()

-- Health and power text: the Look page's tick, and Set up's panel --------------------------------
-- The tick at the foot of the right-hand column, off, with Set up beside
-- it: under the Darkness slider and Thick edges, level with the combo
-- points' tick on the left, both inside the choices, which keep the height
-- they had before it (198), so the Each bar box keeps its room (a taller
-- box left the box's note spilling over its foot, in game, 2026-10-17).
-- The rest of the Look page's fit is checked below. Set up opens a panel
-- over the window: every piece inside it and none on another in each state
-- (the middle or a pair on each bar, a bar's text off, the display
-- switched off, the text off on your bars, both warnings at once), as tall
-- as the rows it shows, under the title bar, and clear of the footer, where
-- each of its controls still says what it does. While the tick is off it
-- says so, and its Turn on ticks it.
-- Each choice is set at once, and its preview is drawn by the display's
-- own text code (Resource.lua).

;(function()
    local ns = Start({ useBars = true, notesSeen = "dev", helpSeen = true })
    for _, timer in ipairs(timers) do timer() end
    -- The game's own number writers, on the preview's plain numbers.
    _G.BreakUpLargeNumbers = function(v) return (("%d"):format(v):reverse():gsub("(%d%d%d)", "%1,"):reverse():gsub("^,", "")) end
    _G.AbbreviateNumbers = function(v) return ("%.1fK"):format(v / 1000) end
    SlashCmdList.FECM("")
    local w = FECMFrame
    w:Select("look")
    local tick, setUp = w.prdText, w.prdTextSetUp
    local function Note(control)
        S[control].scripts.OnEnter(control)
        local text = S[w.note].text
        S[control].scripts.OnLeave(control)
        return text
    end
    Equal(tostring(tick:IsVisible()) .. " " .. tostring(tick:GetChecked()) .. " " .. S[tick.text].text .. " | " .. S[setUp.label].text
        .. " | " .. Note(tick), "true false Health and power text | Set up | Your health and power as numbers on the resource display,"
        .. " in and out of combat.", "the tick, off by default, named like its panel, its note (no longer marked experimental:"
        .. " seen working in game, 1.8.0), with Set up beside it")
    local tickLeft, tickTop, tickRight, tickBottom = Fit.Rect(tick)
    local setLeft, setTop, setRight, setBottom = Fit.Rect(setUp)
    local _, comboTop, comboRight = Fit.Rect(w.combo)
    local _, _, _, darkBottom = Fit.Rect(w.darkness)
    local _, _, _, thickBottom = Fit.Rect(w.thickEdges)
    local _, _, optionsRight, optionsBottom = Fit.Rect(w.lookOptions)
    local keysLeft = Fit.Rect(w.keybinds)
    Equal(table.concat({ tostring(tickLeft == keysLeft and tickLeft > comboRight), tostring(tickTop >= darkBottom and tickTop >= thickBottom),
        tostring(math.abs(tickTop - comboTop) <= 1), tostring(tickRight < setLeft and setRight <= optionsRight),
        tostring(math.max(tickBottom, setBottom) <= optionsBottom), Num(setTop + setBottom - tickTop - tickBottom),
        tostring(S[w.lookOptions].height) }, " "), "true true true true true 0.00 198",
        "in the right-hand column, under Darkness and Thick edges, level with the combo points' tick, Set up beside it and"
        .. " level with it, both inside the choices, which are as tall as before the tick")
    -- A druid's energy in other forms: beside the extra mana bar's tick and
    -- level with it, clear of Thick edges, the choices no taller.
    local energyTick = w.energyTick
    local energyLeft, energyTop, energyRight = Fit.Rect(energyTick)
    local _, manaTop, manaRight = Fit.Rect(w.repeatMana)
    local thickLeft = Fit.Rect(w.thickEdges)
    Equal(tostring(energyTick:IsVisible()) .. " " .. tostring(energyTick:GetChecked()) .. " " .. S[energyTick.text].text
        .. " | " .. Note(energyTick) .. " | " .. S[w.repeatMana.text].text .. " | " .. Note(w.repeatMana) .. " | "
        .. tostring(energyLeft > manaRight and math.abs(energyTop - manaTop) <= 1 and energyRight < thickLeft),
        "true false Show energy bar in other forms | Your energy under the display in caster, bear and your other forms. In cat"
        .. " form it's your main bar as usual. (experimental) | Tidy extra mana bar | The second mana bar some specs get, under"
        .. " your main bar: hidden in caster form, half size in forms. | true",
        "for a druid, the energy tick, off by default, its note quietly experimental, beside the extra mana bar's shorter tick and"
        .. " level with it, clear of Thick edges")

    setUp:Click()
    local panel = w.textPanel
    local dialog, preview = panel.dialog, panel.preview
    local found = {}
    local function Check(label)
        local problems = Fit.Problems(dialog)
        local _, top, _, bottom = Fit.Rect(dialog)
        if top < 42 or bottom > 560 - 28 then problems = problems .. ("the panel at %.1f to %.1f, over the title bar or the footer"):format(top, bottom) end
        if problems ~= "" then found[#found + 1] = label .. ": " .. problems end
    end
    Equal(tostring(dialog:IsVisible()) .. " " .. tostring(S[panel].points[2][3]), "true 28", "Set up opens the panel, its shade clear of the footer")
    Check("at the start")
    -- The tick off, as it starts: the choices show only on the preview, so
    -- the panel says the text is off on your bars, with Turn on.
    Equal(tostring(panel.textOff:IsVisible()) .. " " .. S[panel.textOff].text .. " | " .. tostring(panel.textOn:IsVisible()) .. " "
        .. S[panel.textOn.label].text .. " | " .. Note(panel.textOn), "true The text is off on your bars. | true Turn on | "
        .. "Show this text on your bars, as ticking Health and power text on the Look page does.",
        "the tick off: the panel says the text is off on your bars, with Turn on, which says what it does")
    -- The preview: the display's own text code, on plain numbers, in the
    -- Look page's texture and each bar's colour.
    local hp, mp = preview.health, preview.power
    -- What each spot says now, as the game would write it.
    local said = setmetatable({}, { __mode = "k" })
    for _, bar in pairs(preview) do
        for _, spot in ipairs({ "centre", "left", "right" }) do
            rawset(bar.slots[spot], "SetText", function(self, text) said[self] = text end)
            rawset(bar.slots[spot], "SetFormattedText", function(self, format, ...) said[self] = format:format(...) end)
        end
    end
    w:Refresh()
    local function Spot(slot)
        local text = said[slot]
        return (text == nil or text == "") and '""' or text
    end
    local function Preview(bar) return Spot(bar.slots.centre) .. " | " .. Spot(bar.slots.left) .. " | " .. Spot(bar.slots.right) end
    Equal(Preview(hp) .. " || " .. Preview(mp) .. " | " .. Last(hp.slots.centre, "SetFontObject") .. " " .. Last(hp, "SetStatusBarTexture")
        .. " " .. Last(hp, "SetStatusBarColor", 2) .. " " .. Last(mp, "SetStatusBarColor", 3), '4,321 | "" | "" || 1,876 | "" | "" | '
        .. "FECMFont10 Interface\\Buttons\\WHITE8X8 0.8 1", "the preview: each value in the middle, in the Look page's font at 10, flat, green and blue")

    -- Each choice, at once.
    local function Row(key)
        for _, row in ipairs(panel.rows) do
            if row.key == key then return row.pills end
        end
    end
    local function Pick(key, choice)
        for _, button in ipairs(Row(key).buttons) do
            if button.key == choice then return S[button].scripts.OnClick(button) end
        end
        error("no " .. tostring(choice) .. " for " .. key)
    end
    Pick("prdHealthAt", "sides")
    Equal(ns.Get("prdHealthAt") .. " " .. Preview(hp) .. " " .. tostring(Row("prdHealthLeft"):IsVisible()) .. " "
        .. tostring(Row("prdHealthCentre"):IsVisible()), 'sides "" | 4,321 | 84% true false',
        "Left and right on the health bar: the value at the left, the percent at the right, their rows in place of Centre's")
    Check("health left and right")
    Pick("prdPowerAt", "sides")
    Pick("prdPowerRight", "both")
    Pick("prdTextNumbers", "short")
    Equal(Preview(mp), '"" | 1.9K | 1.9K / 2.4K', "Value / max at the right, numbers shortened")
    Check("both left and right")
    Pick("prdHealthAt", "off")
    Equal(Preview(hp) .. " " .. tostring(Row("prdHealthLeft"):IsVisible()), '"" | "" | "" false', "the health bar's text off: none, and no rows under it")
    Check("health off")
    Pick("prdHealthAt", "sides")
    -- The display switched off: why there's no text, and Turn on, over the rows.
    prdOn = false
    w:Refresh()
    Equal(tostring(panel.turnOn:IsVisible()), "true", "the display off: Turn on in the panel")
    local _, displayTop = Fit.Rect(panel.turnOn)
    local _, textTop = Fit.Rect(panel.textOn)
    Equal(tostring(panel.textOn:IsVisible()) .. " " .. Num(textTop - displayTop), "true 25.00",
        "the text off too: both warnings, the text's a row under the display's")
    -- Its tallest: both warnings over a pair on each bar, still under the title bar.
    Check("display and text off, both left and right")
    panel.turnOn:Click()
    Equal(tostring(prdOn) .. " " .. S[w.note].text, "true Your Personal Resource Display is on. Reload to finish.",
        "and it switches the display on, as the Look page's own Turn on does")
    w:Refresh()
    Equal(tostring(panel.turnOn:IsVisible()), "false", "gone once it's on")
    -- The text's Turn on ticks the Look page's tick: on your bars, the
    -- warning gone, the panel still open; unticked there, it's back.
    panel.textOn:Click()
    Equal(tostring(ns.Get("prdText")) .. " " .. tostring(tick:GetChecked()) .. " " .. tostring(panel.textOff:IsVisible()) .. " "
        .. tostring(panel.textOn:IsVisible()) .. " " .. tostring(dialog:IsVisible()), "true true false false true",
        "Turn on ticks Health and power text: saved, the Look page's tick ticked, the warning gone, the panel still open")
    Check("text on")
    tick:Click()
    Equal(tostring(ns.Get("prdText")) .. " " .. tostring(panel.textOff:IsVisible()) .. " " .. tostring(panel.textOn:IsVisible()),
        "false true true", "unticked on the Look page: the warning back")
    -- The Bar picker: one bar's rows at a time (the preview shows them all).
    local function Picker()
        for _, pills in pairs(panel.pickers) do
            if pills:IsVisible() then return pills end
        end
    end
    local function PickBar(kind)
        for _, button in ipairs(Picker().buttons) do
            if button.key == kind then return S[button].scripts.OnClick(button) end
        end
        error("no bar " .. kind)
    end
    -- Size and font: each bar its own size, under its rows; one font.
    panel.sizes.health:Choose(14)
    PickBar("power")
    panel.sizes.power:Choose(12)
    PickBar("health")
    Pick("prdTextFont", "arial")
    Equal(ns.Get("prdHealthSize") .. " " .. ns.Get("prdPowerSize") .. " " .. Last(hp.slots.left, "SetFontObject") .. " "
        .. Last(mp.slots.right, "SetFontObject"), "14 12 FECMFontarial14 FECMFontarial12", "each bar its own size, in Arial Narrow, just for this text")
    -- (One box: its list of fonts open to read them, then shut.)
    local fonts = panel.fonts
    fonts:Click()
    Equal(S[fonts.buttons[1].label].text .. " " .. Last(fonts.buttons[1].label, "SetFontObject") .. " " .. Last(fonts.buttons[3].label, "SetFontObject")
        .. " | " .. Note(fonts.buttons[1]) .. " | " .. Note(fonts.buttons[3]), "Look page FECMSamplefriz FECMSamplearial | "
        .. "The font picked on the Look page, now Friz Quadrata. | Arial Narrow, plain and narrow, just for this text.",
        "the Look page's font first, then the game's own, each in its own face and saying what it is")
    Equal(S[fonts.label].text .. " " .. Last(fonts.label, "SetFontObject") .. " " .. #fonts.buttons .. " " .. S[fonts.buttons[7].label].text
        .. " " .. Last(fonts.buttons[7].label, "SetFontObject"), "Arial Narrow FECMSamplearial 9 Barlow Semi Condensed FECMSamplebarlow",
        "the box shows the font picked in its face; the list has the fonts shipped with the addon too")
    fonts:Click()
    Check("size 14 in Arial Narrow")
    local healthNote = Note(Row("prdHealthAt").buttons[2])
    PickBar("power")
    Equal(healthNote .. " | " .. Note(Row("prdPowerLeft").buttons[3]) .. " | " .. Note(Row("prdTextNumbers").buttons[2])
        .. " | " .. Note(panel.sizes.power) .. " | " .. Note(Picker().buttons[1]), "A pair at the ends of your health bar. Long text is"
        .. " cut short rather than run into the other. | What you have now and the most you can have, like 4,321 / 5,120. | Numbers"
        .. " shortened by the game, like 4.3K or 12K. | The text's size on your power bar. It can't fit itself to the bar, so text too"
        .. " long for it is cut short. | Which bar's text to set up. The preview shows them all.",
        "each choice says what it does in the footer, clear of the panel")
    -- A druid's extra mana bar, and the energy bar once it's ticked: the
    -- same rows, off to start, and their own preview bars.
    Equal(#Picker().buttons .. " " .. tostring(preview.extra:IsVisible()) .. " " .. tostring(preview.energy:IsVisible()) .. " "
        .. tostring(Row("prdHealthAt"):IsVisible()) .. " " .. tostring(Row("prdPowerAt"):IsVisible()) .. " " .. Preview(preview.extra),
        '3 true false false true "" | "" | ""', "a druid: Health, Power and Extra mana, Power's rows only, the extra mana bar's text off")
    PickBar("extra")
    Pick("prdExtraAt", "centre")
    Pick("prdExtraCentre", "both")
    Equal(tostring(Row("prdPowerAt"):IsVisible()) .. " " .. Preview(preview.extra), 'false 1.2K / 2.4K | "" | ""',
        "Extra mana: its own rows, its value / max in the middle")
    Check("extra mana in the middle")
    ns.Set("prdEnergy", true)
    w:Refresh()
    PickBar("energy")
    Pick("prdEnergyAt", "sides")
    Pick("prdTextNumbers", "full")
    Equal(#Picker().buttons .. " " .. tostring(preview.energy:IsVisible()) .. " " .. Preview(preview.energy), '4 true "" | 80 | 80%',
        "the energy bar ticked: Energy too, a pair at its ends")
    Check("energy left and right")
    -- Percent (no sign), a player's idea: the percent with no % after it
    -- (full shows 100), saying so, quietly experimental, the row's five
    -- choices each sized by its name, the row inside the panel.
    Pick("prdEnergyRight", "bare")
    local bare, widths = nil, {}
    for _, button in ipairs(Row("prdEnergyRight").buttons) do
        if button.key == "bare" then bare = button end
        widths[#widths + 1] = button.key .. " " .. math.floor(S[button].width)
    end
    Equal(ns.Get("prdEnergyRight") .. " " .. Preview(preview.energy) .. " | " .. S[bare.label].text .. " | " .. Note(bare) .. " | "
        .. table.concat(widths, ", "), 'bare "" | 80 | 80 | Percent (no sign) | As a percent with no % sign, like 84. Full shows 100.'
        .. " (experimental) | none 49, value 56, both 99, percent 70, bare 141",
        "Percent (no sign): the number with no % sign, its note quietly experimental, each choice as wide as its name needs")
    Check("percent with no sign")
    Pick("prdEnergyRight", "percent")
    -- Incoming heals and Absorbs, a player's idea: at the health bar's ends
    -- only (the middle always shows something, and the other bars have no
    -- heals), each saying what it shows, quietly experimental, in a row as
    -- wide as the others, each choice as wide as its name needs; the
    -- preview's sample numbers through the game's own calls, which leave
    -- each blank at 0 (whole numbers, no commas).
    do
        local util = _G.C_StringUtil
        _G.C_StringUtil = {
            TruncateWhenZero = function(v) local n = math.floor(v) return n == 0 and "" or tostring(n) end,
            WrapString = function(infix, prefix, suffix) return infix == "" and "" or (prefix or "") .. infix .. (suffix or "") end,
        }
        PickBar("health")
        Pick("prdHealthLeft", "heals")
        Pick("prdHealthRight", "absorbs")
        local left, names, widths, heals, absorbs = Row("prdHealthLeft"), {}, {}, nil, nil
        for _, button in ipairs(left.buttons) do
            if button.key == "heals" then heals = button elseif button.key == "absorbs" then absorbs = button end
            names[#names + 1] = S[button.label].text
            widths[#widths + 1] = math.floor(S[button].width)
        end
        local healsNote, absorbsNote = Note(heals), Note(absorbs)
        Equal(ns.Get("prdHealthLeft") .. " " .. ns.Get("prdHealthRight") .. " " .. left.selected .. " " .. Row("prdHealthRight").selected
            .. " | " .. Preview(hp) .. " | " .. table.concat(names, ", ") .. " | " .. table.concat(widths, " ") .. " | " .. healsNote
            .. " | " .. absorbsNote .. " | " .. tostring(Fit.Wide(healsNote, "GameFontHighlightSmall") <= 2 * S[w.note].width
            and Fit.Wide(absorbsNote, "GameFontHighlightSmall") <= 2 * S[w.note].width) .. " " .. math.floor(S[left].width),
            'heals absorbs heals absorbs | "" | +1200 | (850) | None, Value, Value / max, Percent, Percent (no sign), Incoming heals,'
            .. " Absorbs | 34 38 68 48 97 82 48 | Heals on their way to you, like +1200. Blank while none are coming. (experimental) |"
            .. " Shields on you, like (850) from Power Word: Shield. Blank while you have none. (experimental) | true 420",
            "Incoming heals and Absorbs at the health bar's ends: +1200 and (850) on the preview, each choice sized by its name,"
            .. " each saying what it shows in two lines of the footer at most, quietly experimental")
        Check("heals and absorbs")
        -- Not in the middle, and not on the other bars.
        local function Keys(row)
            local keys = {}
            for _, button in ipairs(row.buttons) do keys[#keys + 1] = button.key end
            return table.concat(keys, " ")
        end
        Pick("prdHealthAt", "centre")
        local centre = Keys(Row("prdHealthCentre"))
        Pick("prdHealthAt", "sides")
        Equal(centre .. " | " .. Keys(Row("prdPowerLeft")) .. " | " .. Keys(Row("prdPowerRight")) .. " | " .. Keys(Row("prdExtraLeft"))
            .. " | " .. Keys(Row("prdEnergyRight")), "value both percent bare | none value both percent bare | none value both percent bare"
            .. " | none value both percent bare | none value both percent bare",
            "only at the health bar's ends: not in its middle, nor on the power, extra mana or energy bars")
        -- A build without the game's blank-at-0 calls: the number as the game writes it.
        _G.C_StringUtil = nil
        w:Refresh()
        Equal(Preview(hp), '"" | +1,200 | (850)', "no blank-at-0 calls: the game's own number writer")
        _G.C_StringUtil = util
        Pick("prdHealthLeft", "value")
        Pick("prdHealthRight", "percent")
    end
    -- /ccm debug: whether the game has the calls and what each says now: a
    -- number, none or secret, and for a secret whether the game's own text
    -- for it comes out blank or not (measured on a hidden line of the
    -- report's own, the secret only handed on); then what each end of the
    -- health bar shows. Nothing misused, nothing changed.
    do
        Pick("prdHealthLeft", "heals")
        local util, width, given = _G.C_StringUtil, Proto.GetStringWidth, {}
        _G.C_StringUtil = {
            TruncateWhenZero = function(v)
                given[#given + 1] = IsSecret(v) and "secret" or tostring(v)
                return SECRETS.string
            end,
            WrapString = function() return "" end,
        }
        _G.UnitGetIncomingHeals = function(unit, healer)
            assert(unit == "player")
            if healer then return nil end
            return SECRETS.number
        end
        _G.UnitGetTotalAbsorbs = function(unit) assert(unit == "player"); return 0 end
        local function Line() return tostring(ns.DebugReport():match("Heals and absorbs: [^\n]*")) end
        local sent = Line()
        -- A line given secret text: measured as nothing there, then kept secret too.
        local answer
        function Proto:GetStringWidth()
            if rawequal(S[self].text, SECRETS.string) then return answer end
            return width(self)
        end
        answer = 0
        local blank = Line():match("incoming [^,]*")
        answer = SECRETS.number
        local hidden = Line():match("incoming [^,]*")
        Proto.GetStringWidth = width
        _G.C_StringUtil, _G.UnitGetIncomingHeals, _G.UnitGetTotalAbsorbs = nil, nil, nil
        local none = Line()
        _G.C_StringUtil = util
        Pick("prdHealthLeft", "value")
        Equal(sent .. " || " .. blank .. " | " .. hidden .. " || " .. none .. " || " .. table.concat(given, " ") .. " " .. ns.Get("prdHealthLeft"),
            "Heals and absorbs: incoming secret (sent), from you none, absorbs 0, blank at 0 true | health text false at sides, left heals,"
            .. " right percent || incoming secret (blank) | incoming secret (can't tell) || Heals and absorbs: incoming no call, from you"
            .. " no call, absorbs no call, blank at 0 false | health text false at sides, left heals, right percent || secret secret secret value",
            "/ccm debug: the calls, what each says now, a secret's text blank or not on a hidden line of its own, and the health bar's ends")
    end
    ns.Set("prdEnergy", false)
    w:Refresh()
    Equal(#Picker().buttons .. " " .. tostring(Row("prdHealthAt"):IsVisible()), "3 true", "unticked: Energy goes, back on Health")
    -- Your own colours on the preview.
    ns.Set("prdHealth", "purple")
    w:Refresh()
    Equal(Last(hp, "SetStatusBarColor", 1), .6, "the preview in your own colour for a bar")
    -- Done closes it; the tick is still the Look page's, and nothing breaks with no display.
    panel.done:Click()
    tick:Click()
    Equal(tostring(dialog:IsVisible()) .. " " .. tostring(ns.Get("prdText")) .. " " .. tostring(w:IsShown()), "false true true",
        "Done closes it; the tick turns the text on")
    setUp:Click()
    w:Hide()
    Equal(tostring(S[panel].shown), "false", "closed with the window")
    Equal(table.concat(found, " | "), "", "in every state: every piece inside the panel and none on another, the panel under the title bar and clear of the footer")
    _G.BreakUpLargeNumbers, _G.AbbreviateNumbers = nil, nil
    Equal(#printed, 0, "no errors")
end)()

-- The Set up panel goes when another page takes the window ----------------------------------------
-- Its shade covers the whole window but the footer, with the mouse on, so a
-- page picked from code while it's open would show dimmed and blocked under
-- it: /ccm tour (its first step points at the menu and picks no page), /ccm
-- reset (the Layout page and its question), What's new's tour (Show me
-- what's new), and the Cooldown pulse's Move box bringing the window back
-- on its page. Each puts the panel away; Set up opens it again after.

;(function()
    local ns = Start({ useBars = true, notesSeen = "dev", helpSeen = true })
    for _, timer in ipairs(timers) do timer() end
    SlashCmdList.FECM("")
    local w = FECMFrame
    local said = {}
    local function After(label, run)
        if FECMTour and FECMTour:IsShown() then FECMTour.skip:Click() end
        w:Select("look")
        w.prdTextSetUp:Click()
        local open = w.textPanel:IsVisible()
        run()
        said[#said + 1] = label .. " " .. tostring(open) .. " " .. tostring(w.textPanel:IsVisible()) .. " " .. tostring(w:IsShown())
            .. " " .. w.selected
    end
    After("/ccm tour", function() SlashCmdList.FECM("tour") end)
    local tourUp = S[FECMTour].shown
    After("What's new's tour", function() ns.Tour:StartNews("1.1.0") end)
    local newsUp = S[FECMTour].shown
    After("a page picked", function() w:Select("pulse") end)
    After("/ccm reset", function() SlashCmdList.FECM("reset") end)
    Equal(table.concat(said, " | ") .. " | " .. tostring(tourUp) .. " " .. tostring(newsUp), "/ccm tour true false true look | "
        .. "What's new's tour true false true cd | a page picked true false true pulse | /ccm reset true false true layout | true true",
        "the panel open, then put away by each, the window still up on the page picked, the tours shown")
    -- Each page's note on hover in two lines of the footer at most, the
    -- Look page's longer now it names the resource display and its text.
    local long = {}
    for key, item in pairs(w.nav) do
        local hint = type(item.hint) == "function" and item.hint(item) or item.hint
        if Fit.Wide(hint, "GameFontHighlightSmall") > 2 * S[w.note].width then long[#long + 1] = key end
    end
    Equal(table.concat(long, " ") .. " | " .. tostring(w.nav.look.hint:find("resource display", 1, true) ~= nil), " | true",
        "each page's hover fits two lines of the footer, the Look page's naming the resource display")
    Equal(#printed, 0, "no errors")
end)()

-- The Look page: every piece inside its box, in every state ---------------------------------------
-- The preview, the choices under it and the Each bar box: each text, tick,
-- button, choice and slider inside the box it's drawn in, past none of its
-- edges, none on another, and each box clear of everything outside it; and
-- each row of the Each bar list across the list, its icon, name, swatches
-- and colour's name inside it and on none of each other. In every state
-- that changes what shows: the list's note and its button (no Tracked Bars
-- yet, the look off, waiting for a reload, Blizzard's Cooldown Manager off)
-- under none, two or three of the display's rows (three for a druid with
-- combo points), your Tracked Bars listed, the warnings on the title's and
-- Each bar's rows, keybinds off and on, the display's text on, and every
-- design, colour, texture, font, accent, ready glow and keybind position.
-- The window is a fixed 820 by 560 (it can't be resized), so that's every
-- size it comes in. A taller choices box left the Each bar box's note
-- spilling over its foot in game (2026-10-17): this catches that.

;(function()
    local ns = Start({ useBars = true, notesSeen = "dev", helpSeen = true })
    for _, timer in ipairs(timers) do timer() end
    local spellName = C_Spell.GetSpellName
    C_Spell.GetSpellName = function(id)
        if id == 25895 then return "Greater Blessing of Salvation" end -- a long name
        return spellName(id)
    end
    SlashCmdList.FECM("")
    local w = FECMFrame
    w:Select("look")
    local page, boxes = w.pages.look, Fit.LookBoxes(w)
    local found = {}
    local function Check(label)
        w:Refresh()
        local problems, rows = Fit.Problems(page, boxes), Fit.Rows(w)
        if rows ~= "" then problems = problems .. (problems ~= "" and "; " or "") .. rows end
        if problems ~= "" then found[#found + 1] = label .. ": " .. problems end
    end
    -- What the list shows: its rows, then its note and its button.
    local function List()
        local shown = 0
        for _, row in ipairs(w.eachRows) do
            if row:IsVisible() then shown = shown + 1 end
        end
        return shown .. " rows | " .. (w.eachEmpty:IsVisible() and S[w.eachEmpty].text or "no note") .. " | "
            .. (w.eachFix:IsVisible() and S[w.eachFix.label].text or "no button")
    end
    -- Blizzard's Tracked Bars, as the Look page reads them (Skin.lua TrackedBars).
    local tracked = {}
    _G.BuffBarCooldownViewer = { itemFramePool = { EnumerateActive = function() return pairs(tracked) end } }
    local function Track(ids)
        tracked = {}
        for i, id in ipairs(ids) do tracked[{ GetBaseSpellID = function() return id end, layoutIndex = i }] = true end
    end
    -- What the list can say, and the look settings behind each.
    local REASONS = {
        { "no Tracked Bars", function() end },
        { "Tracked Bars listed", function() Track({ 16870, 16886, 1243, 25895 }) end },
        { "the look off", function() ns.Set("skin", false); ns.loaded.skin = false end },
        { "waiting for a reload", function() ns.loaded.skin = false end },
        { "Blizzard's Cooldown Manager off", function() cvarOn = false end },
    }
    -- The display's rows over it: none, its two bars, and a druid's combo points.
    local DISPLAY = { { "no display rows", false, false }, { "two display rows", true, false }, { "three display rows", true, true } }
    local said, titles = {}, {}
    for _, reason in ipairs(REASONS) do
        for _, display in ipairs(DISPLAY) do
            Track({})
            ns.Set("skin", true)
            ns.loaded.skin, cvarOn = true, true
            reason[2]()
            _G.PersonalResourceDisplayFrame = display[2] and {} or nil
            ns.Set("prdCombo", display[3])
            Check(reason[1] .. ", " .. display[1])
            said[#said + 1] = List()
            -- The title's row: Reload to apply, or the Cooldown Manager's warning and Turn on.
            if w.reload:IsVisible() then titles[reason[1] .. " reload"] = true end
            if w.off:IsVisible() and w.turnOnManager:IsVisible() then titles[reason[1] .. " warning"] = true end
        end
    end
    Equal(table.concat(said, " || "), "0 rows | Blizzard's Tracked Bars (buffs shown as timer bars) will be listed here to colour once you"
        .. " set some up in Blizzard's Cooldown Settings. Not using them? Nothing to do here. | no button || 2 rows | Blizzard's Tracked"
        .. " Bars (buffs shown as timer bars) will be listed here to colour once you set some up in Blizzard's Cooldown Settings. Not"
        .. " using them? Nothing to do here. | no button || 3 rows | Blizzard's Tracked Bars (buffs shown as timer bars) will be listed"
        .. " here to colour once you set some up in Blizzard's Cooldown Settings. Not using them? Nothing to do here. | no button || "
        .. "4 rows | no note | no button || 6 rows | no note | no button || 7 rows | no note | no button || "
        .. "0 rows | Apply this look to the Cooldown Manager and reload to colour your bars one by one. | Turn on || "
        .. "2 rows | Apply this look to the Cooldown Manager and reload to colour your bars one by one. | Turn on || "
        .. "3 rows | Apply this look to the Cooldown Manager and reload to colour your bars one by one. | Turn on || "
        .. "0 rows | Reload first, then colour your bars one by one here. | Reload || "
        .. "2 rows | Reload first, then colour your bars one by one here. | Reload || "
        .. "3 rows | Reload first, then colour your bars one by one here. | Reload || "
        .. "0 rows | Blizzard's Cooldown Manager is off. | Turn on || 2 rows | Blizzard's Cooldown Manager is off. | Turn on || "
        .. "3 rows | Blizzard's Cooldown Manager is off. | Turn on",
        "(each state's list: its rows, note and button, checked there)")
    local titleList = {}
    for key in pairs(titles) do titleList[#titleList + 1] = key end
    table.sort(titleList)
    Equal(table.concat(titleList, ", "), "Blizzard's Cooldown Manager off warning, waiting for a reload reload",
        "(the title's row checked with Reload to apply while waiting for a reload, and the Cooldown Manager's warning while it's off)")

    -- The display ticked but switched off: the warning and its Turn on on
    -- Each bar's row, over the list's three rows, its note and button.
    cvarOn = true
    ns.Set("skin", false)
    ns.loaded.skin = false
    prdOn = false
    Check("the display off")
    Equal(tostring(w.personalOff:IsVisible()) .. " " .. tostring(w.turnOnPersonal:IsVisible()) .. " | " .. List(),
        "true true | 3 rows | Apply this look to the Cooldown Manager and reload to colour your bars one by one. | Turn on",
        "(the display off: its warning and Turn on, over three rows, the note and its button, checked there)")
    prdOn = true

    -- Each choice, in that fullest list, with keybinds off and on and the display's text on.
    local CHOICES = { { "barStyle", ns.BAR_STYLE_KEYS }, { "barColour", ns.BAR_COLOUR_KEYS }, { "barTexture", ns.BAR_TEXTURE_KEYS },
        { "font", ns.FONT_KEYS }, { "accent", ns.ACCENT_KEYS }, { "readyGlow", ns.READY_GLOW_KEYS },
        { "keybindPosition", ns.KEYBIND_POSITIONS }, { "colourFade", { false, true } } }
    local tried = 0
    for _, keys in ipairs({ false, true }) do
        ns.Set("keybinds", keys)
        ns.Set("prdText", keys)
        for _, choice in ipairs(CHOICES) do
            local was = ns.Get(choice[1])
            for _, key in ipairs(choice[2]) do
                ns.Set(choice[1], key)
                Check(("keybinds %s, %s %s"):format(keys and "on" or "off", choice[1], key))
                tried = tried + 1
            end
            ns.Set(choice[1], was)
        end
    end
    Equal(tostring(w.keyPlace:IsVisible()) .. " " .. tostring(w.prdText:GetChecked()) .. " " .. tried, "true true 70",
        "(keybinds' choices shown, the text ticked, and every choice tried twice: four designs, eight fonts, Colour fade off and on)")
    Equal(table.concat(found, " | "), "", "in every state, each piece on the Look page inside its box (the preview, the choices,"
        .. " the Each bar box), none on another, and each row of the list inside it")
    C_Spell.GetSpellName = spellName
    _G.BuffBarCooldownViewer, _G.PersonalResourceDisplayFrame = nil, nil
    Equal(#printed, 0, "no errors")
end)()

-- The profile menu: every piece inside it, none on another -----------------------------------------
-- Its Roles at the foot: the heading with Switch with my talents at its
-- right, Tank, Healer and Damage under them, and while the tick is on each
-- talent tree (its name and points, then its four choices: Tank, Healer,
-- Damage and None, each word inside its own) and a note under them.
-- The menu stays inside the window, hanging under its button, and ends
-- clear of the footer's line (where every control's hover note shows), the
-- list showing fewer profiles while the trees and note take room.

;(function()
    local names = { "Balance", "Feral Combat", "Restoration" }
    _G.C_ClassTalents = { GetActiveConfigID = function() return 77 end }
    _G.C_Traits = {
        GetConfigInfo = function() return { treeIDs = { 501 } } end,
        GetGroupDisplayInfoByTreeID = function()
            return { { groupID = 101, displayName = names[1] }, { groupID = 102, displayName = names[2] },
                { groupID = 103, displayName = names[3] } }
        end,
        GetGroupCurrencyInfo = function() return { { traitNodeGroupID = 102, currencyInfos = { { spent = 51 } } } } end,
    }
    local ns = Start({ useBars = true, notesSeen = "dev", helpSeen = true })
    for _, timer in ipairs(timers) do timer() end
    SlashCmdList.FECM("")
    local w = FECMFrame
    w.profileButton:Click()
    local found = {}
    -- The footer's line: one line of small text up from its foot.
    local footerTop = select(4, Fit.Rect(w.note)) - 12
    -- A tree's choices, end to end inside it: each word 2 clear of its edges.
    local function Choices(choice)
        local problems = {}
        local left, _, right = Fit.Rect(choice)
        local at = left + 1
        for _, button in ipairs(choice.buttons) do
            local bl, _, br = Fit.Rect(button)
            local ll, _, lr = Fit.Rect(button.label)
            local word = S[button.label].text
            if math.abs(bl - at) > .01 then problems[#problems + 1] = word .. " not against the one before" end
            if ll < bl + 2 or lr > br - 2 then problems[#problems + 1] = ('"%s" (%.1f wide) runs out of its %.1f'):format(word,
                Fit.Wide(word, "GameFontHighlightSmall"), br - bl) end
            at = br
        end
        if math.abs(at - (right - 1)) > .01 then problems[#problems + 1] = ("the choices end at %.1f, not %.1f"):format(at, right - 1) end
        if #choice.buttons ~= 4 then problems[#problems + 1] = #choice.buttons .. " choices, not 4" end
        return table.concat(problems, ", ")
    end
    local function Check(label)
        w:Refresh()
        local problems = Fit.Problems(w.profilePanel)
        local _, top, _, bottom = Fit.Rect(w.profilePanel)
        local _, _, _, under = Fit.Rect(w.profileButton)
        if top < under or bottom > footerTop - 4 then problems = problems .. " the menu reaches " .. top .. " to " .. bottom end
        for _, row in ipairs(w.treeRows) do
            if row.choice:IsVisible() then
                local wrong = Choices(row.choice)
                if wrong ~= "" then problems = problems .. " " .. S[row.name].text .. ": " .. wrong end
            end
        end
        if problems ~= "" then found[#found + 1] = label .. ": " .. problems end
    end
    Check("one profile")
    for _, role in ipairs(ns.ROLE_KEYS) do ns.UseRole(role) end
    Check("three roles")
    w.talentTick:Click()
    Check("talents ticked")
    ns.talentNote = "Your main talent tree is now Feral Combat, but Tank has no profile yet: click Tank to make one."
    Check("with a note")
    for i = 1, 12 do ns.NewProfile(("Profile %02d"):format(i)) end
    Check("a long list")
    -- After the list: every switch (each New here) clears what the talents last said.
    ns.talentNote = "Your main talent tree is now Feral Combat, but Tank has no profile yet: click Tank to make one."
    Check("a long list with a note")
    Equal(tostring(S[w.profilePanel].shown) .. " " .. #w.treeRows .. " " .. tostring(S[w.talentStatus].shown), "true 3 true",
        "(the menu open, three trees and the note showing)")
    -- The longest note there can be: a long tree name and a profile name as long as they come.
    ns.talentNote = "Your main talent tree is now Beast Mastery: switched to " .. ("Profile name as long as they come, made by hand"):sub(1, 48)
        .. ", your Damage profile."
    Check("a long list with the longest note")
    -- The longest tree name there is, at 51 points ("Beast Mastery 51"), clear of its choices.
    names[2] = "Beast Mastery"
    Check("the longest tree name")
    Equal(S[w.treeRows[2].name].text:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "") .. " | " .. #w.treeRows[2].choice.buttons, "Beast Mastery 51 | 4",
        "(the longest tree name showing, with four choices)")
    Equal(table.concat(found, " | "), "", "the profile menu with its roles and talents: each piece clear of the next, all inside it,"
        .. " each tree's four choices' words inside them, and it inside the window under its button, clear of the footer's line")
    Equal(tostring(footerTop) .. " " .. tostring(S[w.profileList].shown), "539 true", "(the footer's line measured where it shows)")
    -- Each choice's hover note for the longest tree name, on one line of the
    -- footer: counted at 5.6 a letter (the small font's widest, as What's
    -- new's foot below), inside the note's width.
    local long = {}
    for _, choice in ipairs(w.treeRows[2].choice.buttons) do
        S[choice].scripts.OnEnter(choice)
        local text = S[w.note].text
        if not text:find("Beast Mastery", 1, true) then long[#long + 1] = choice.key .. ": not shown"
        elseif #text * 5.6 > w.note:GetWidth() then long[#long + 1] = ('"%s" runs %.1f'):format(text, #text * 5.6) end
        S[choice].scripts.OnLeave(choice)
    end
    Equal(w.note:GetWidth() .. " | " .. table.concat(long, " | "), "560 | ",
        "hovered, each tree choice's note for Beast Mastery fits on the footer's one line")
    _G.C_ClassTalents, _G.C_Traits = nil, nil
    Equal(#printed, 0, "no errors")
end)()

-- What's new's foot: its two lines clear of its buttons ----------------------------------------------
-- On the left "Found a bug or have an idea?" and the line on seeing it again;
-- on the right, on the same rows, Got it, Show me what's new (while there's a
-- tour of what's new) and Discord. Fit.Wide's 6.5 a letter is too wide here:
-- the shipped "Found a bug" line sits clear of Discord in the game. Measured
-- on a screenshot of the window's footer, the small font runs 5.1 to 5.6
-- units a letter, so counted at 5.6, the widest, with all three buttons up.

;(function()
    local ns = Start({ useBars = true, notesSeen = "dev", helpSeen = true })
    for _, timer in ipairs(timers) do timer() end
    local News = ns.Tour.News
    ns.Tour.News = function() return { {} } end -- a tour of what's new to offer
    ns.ShowNotes()
    ns.Tour.News = News
    local notes = FECMNotes
    local dl, dt, _, db = Fit.Rect(notes.discord)
    local found = {}
    for _, line in ipairs({ notes.ask, notes.hint }) do
        local l, t, _, b = Fit.Rect(line)
        local right = l + #S[line].text * 5.6
        if not (t < db and dt < b) then found[#found + 1] = S[line].text .. ": not on Discord's rows" end
        if right > dl then found[#found + 1] = ('"%s" ends at %.1f, under Discord from %.1f'):format(S[line].text, right, dl) end
    end
    Equal(tostring(S[notes.tour].shown) .. " " .. tostring(S[notes.discord].shown) .. " | " .. table.concat(found, " | "), "true true | ",
        "with Show me what's new and Discord up, the lines on the left end before Discord")
    notes:Hide()
    Equal(#printed, 0, "no errors")
end)()

-- No What's new pop-up: an update's notes are marked seen at login and never
-- wait to open. Off, they're still due until they've shown.
;(function()
    _G.GetAddOnMetadata = function(addon, field) return addon == "ForeverEnhancedCooldownManager" and field == "Version" and "1.7.0" or nil end
    local on = Start({ useBars = true, notesSeen = "1.6.0", helpSeen = true, noWhatsNew = true })
    Equal(tostring(on.NotesSeen()), "1.7.0", "No What's new pop-up on: this update's notes count as seen at once")
    local off = Start({ useBars = true, notesSeen = "1.6.0", helpSeen = true })
    Equal(tostring(off.NotesSeen()), "1.6.0", "off: still due until they've shown")
    _G.GetAddOnMetadata = nil
end)()

-- Tell me when an update is out (General page, under the minimap button): on
-- from the start, in the shared update notices (SquirtVersions.lua, tested on
-- its own in Tools/TestSquirtVersions.lua) by its code, title and version,
-- and unticked it leaves them nothing to do for this addon. A copy straight
-- from the source ("dev") listens, with no version to share.
;(function()
    _G.SquirtVersions = nil
    _G.GetAddOnMetadata = function(addon, field) return addon == "ForeverEnhancedCooldownManager" and field == "Version" and "1.7.0" or nil end
    local ns = Start({ useBars = true, notesSeen = "dev", helpSeen = true })
    _G.GetAddOnMetadata = nil
    local notices = _G.SquirtVersions
    local entry = notices and notices.addons and notices.addons.CM
    Equal(entry and (entry.title .. " | " .. entry.version .. " | " .. entry.colour .. " | " .. tostring(entry.IsOn())),
        "Forever Enhanced Cooldown Manager | 1.7.0 | ffd100 | true", "in the shared update notices, on from the start")
    Equal(notices:Payload("H"), "H1:CM=1.7.0", "sharing its version")
    SlashCmdList.FECM("")
    local w = FECMFrame
    w:Select("general")
    local tick = w.updateNotice
    local function Note(control)
        S[control].scripts.OnEnter(control)
        local text = S[w.note].text
        S[control].scripts.OnLeave(control)
        return text
    end
    Equal(tostring(tick:IsVisible()) .. " " .. tostring(tick:GetChecked()) .. " " .. S[tick.text].text .. " | " .. Note(tick),
        "true true Tell me when an update is out | A line in chat, once a session, when a newer version is out. It uses a hidden"
        .. " chat channel, which takes one of your chat channel slots.", "the tick, on, its note naming the channel slot")
    tick:Click()
    Equal(tostring(ns.Get("updateNotice")) .. " " .. tostring(ForeverEnhancedCooldownManagerDB.updateNotice) .. " "
        .. tostring(notices:Wanted()) .. " " .. tostring(notices:Payload("H")), "false false false nil",
        "unticked: saved, and the update notices have nothing to do or share for it")
    tick:Click()
    Equal(tostring(ns.Get("updateNotice")) .. " " .. tostring(notices:Wanted()), "true true", "ticked again: back")
    -- No What's new pop-up: beside it, off from the start, and saved.
    Equal(tostring(w.noWhatsNew:IsVisible()) .. " " .. tostring(w.noWhatsNew:GetChecked()) .. " " .. S[w.noWhatsNew.text].text .. " | " .. Note(w.noWhatsNew),
        "true false No What's new pop-up | What's new stops opening by itself after an update. The What's new button and /ccm new still show it. (experimental)",
        "No What's new pop-up: the tick, off, its note")
    w.noWhatsNew:Click()
    Equal(tostring(ns.Get("noWhatsNew")) .. " " .. tostring(ForeverEnhancedCooldownManagerDB.noWhatsNew), "true true", "ticked: saved")
    w.noWhatsNew:Click()
    Equal(tostring(ns.Get("noWhatsNew")), "false", "unticked: off again")
    -- The line itself, through the addon's own chat line.
    printed = {}
    Equal(notices:Test("CM"), 1, "the hidden test")
    Equal(printed[1], "|cffffd100Forever Enhanced Cooldown Manager|r 1.7.1 is out (you have 1.7.0). Update on CurseForge.",
        "says the line in chat")
    printed = {}
    -- A copy straight from the source: no version to share, still listening.
    _G.SquirtVersions = nil
    ns = Start({ useBars = true, notesSeen = "dev", helpSeen = true })
    notices = _G.SquirtVersions
    Equal(notices.addons.CM.version .. " " .. tostring(notices:Payload("H")) .. " " .. tostring(notices:Wanted()), "dev nil true",
        "dev: nothing shared, still listening")
    _G.SquirtVersions = nil
end)()

-- Presets: a look in one click from the Look page, with what to switch on.
;(function()
    local ns = Start({ useBars = true, notesSeen = "dev", helpSeen = true })
    for _, timer in ipairs(timers) do timer() end
    local P = ns.ProfileShare
    -- Every preset's every value is one the addon takes, and none of them
    -- is where things sit, the window's accent, Raid Timers or the pulse.
    local bad = {}
    local LEFT_ALONE = { accent = true, pulseX = true, pulseY = true, barScale = true, prdMatch = true }
    for _, look in ipairs(P.LOOKS) do
        for key, value in pairs(look.values) do
            if not ns.Valid(key, value) or LEFT_ALONE[key] or key:find("^pulse") or key:find("^pull") or key:find("^warning")
                or key:find("^emote") or key:find("^boss") or key:find("^raid") then
                bad[#bad + 1] = look.key .. "." .. key
            end
        end
        for _, extra in ipairs(look.extras) do
            local known = false
            for _, each in ipairs(P.EXTRAS) do known = known or each.key == extra end
            if not known then bad[#bad + 1] = look.key .. " extra " .. extra end
        end
    end
    Equal(#P.LOOKS .. " " .. table.concat(bad, " "), "4 ", "four looks, every value one the addon takes, none of what's left alone")
    SlashCmdList.FECM("")
    local w = FECMFrame
    w:Select("look")
    local function Note(control)
        S[control].scripts.OnEnter(control)
        local text = S[w.note].text
        S[control].scripts.OnLeave(control)
        return text
    end
    Equal(tostring(w.presets:IsVisible()) .. " " .. S[w.presets.label].text, "true Presets", "Presets on the Look page's title row")
    w.presets:Click()
    local panel = w.presetsPanel
    local dialog = panel.dialog
    local found = {}
    local function Check(label)
        local problems = Fit.Problems(dialog)
        local _, top, _, bottom = Fit.Rect(dialog)
        if top < 42 or bottom > 560 - 28 then problems = problems .. ("the panel at %.1f to %.1f, over the title bar or the footer"):format(top, bottom) end
        if problems ~= "" then found[#found + 1] = label .. ": " .. problems end
    end
    local names, labels = {}, {}
    for _, card in ipairs(panel.cards) do names[#names + 1] = S[card.label].text end
    for _, check in ipairs(panel.ticks) do labels[#labels + 1] = S[check.text].text end
    Equal(table.concat(names, ", ") .. " | " .. #labels .. " " .. labels[#labels], "Keep mine, Clean, Bold, Minimal, Classic | 9 Tidy extra mana bar",
        "Keep mine first, then the four looks; a druid gets all nine things to switch on, combo points and the energy bar among them")
    Check("at the start")
    -- Bold: its suggestions ticked; Apply sets its look and switches them on.
    local function Card(key)
        for _, card in ipairs(panel.cards) do if card.key == key then return card end end
    end
    Card("bold"):Click()
    local ticked = {}
    for _, check in ipairs(panel.ticks) do if check:GetChecked() and check.usable ~= false then ticked[#ticked + 1] = check.extra.key end end
    Equal(table.concat(ticked, " "), "keybinds text cast ticks latency", "Bold ticks what it goes well with")
    -- Shown live on your bars, nothing saved yet.
    Equal(ns.Get("barColour") .. " " .. ns.GetSaved("barColour") .. " " .. tostring(ns.Previewing()), "class orange true",
        "picked: Bold shows at once, your own look still what's saved")
    local before = ns.GetSaved("barStyle") .. " " .. ns.GetSaved("barColour") .. " " .. tostring(ns.GetSaved("thickEdges")) .. " "
        .. ns.GetSaved("accent")
    panel.apply:Click()
    Equal(before .. " | " .. ns.Get("barStyle") .. " " .. ns.Get("barColour") .. " " .. tostring(ns.Get("thickEdges")) .. " " .. ns.Get("accent")
        .. " " .. ns.Get("castTickStyle") .. " " .. tostring(ns.Get("keybinds")) .. " " .. tostring(ns.Get("prdText")) .. " "
        .. tostring(ns.Get("castBar")) .. " " .. tostring(ns.Get("castTicks")) .. " " .. tostring(ns.Get("castLatency")),
        "glass orange false purple | glass class true purple lines true true true true true",
        "applied: Bold's look, the accent left alone, and the ticked ones switched on")
    Equal(tostring(Card("bold") ~= nil) .. " " .. S[panel.said].text .. " " .. tostring(ns.Previewing()), "true Bold look applied, and turned"
        .. " on: Keybinds on icons, Health and power text, Your own cast bar, Cast bar tick marks, Cast bar latency. false",
        "saying what it did, the preview now saved")
    -- Already on: ticked and greyed, so a preset can't switch it off.
    local greyed = {}
    for _, check in ipairs(panel.ticks) do if check.usable == false then greyed[#greyed + 1] = check.extra.key end end
    Equal(table.concat(greyed, " "), "keybinds text look cast ticks latency tidy",
        "what's on shows ticked and greyed (the look on Blizzard's bars and Tidy were on already here)")
    Check("after Bold")
    -- Undo: the look before, and what Bold switched on off again.
    panel.undo:Click()
    Equal(ns.Get("barStyle") .. " " .. ns.Get("barColour") .. " " .. tostring(ns.Get("thickEdges")) .. " " .. tostring(ns.Get("keybinds"))
        .. " " .. tostring(ns.Get("prdText")) .. " " .. tostring(ns.Get("castBar")) .. " " .. tostring(ns.Get("prdHideRepeat")) .. " | "
        .. S[panel.said].text .. " " .. tostring(P.CanUndoLook()), "glass orange false false false false true | Your look before the presets"
        .. " is back. false", "Undo: the look before, what it switched on off again, what was on already left on")
    -- Two presets in a row, one Undo: back to before the first. Make it
    -- yours: a font of your own in place of the look's, shown and kept.
    Card("bold"):Click()
    panel.apply:Click()
    Card("minimal"):Click()
    for _, button in ipairs(panel.fonts.buttons) do
        if button.key == "morpheus" then S[button].scripts.OnClick(button) end
    end
    Equal(ns.Get("font") .. " " .. ns.GetSaved("font"), "morpheus skurri", "your font shows at once over Minimal's, Bold's still saved")
    panel.apply:Click()
    Equal(ns.GetSaved("barStyle") .. " " .. ns.GetSaved("font"), "outline morpheus", "Minimal kept, in your font")
    panel.undo:Click()
    Equal(ns.GetSaved("barStyle") .. " " .. ns.GetSaved("barColour") .. " " .. ns.GetSaved("font") .. " " .. tostring(ns.GetSaved("keybinds")),
        "glass orange friz false", "one Undo after two presets: back to before the first")
    -- Picked but not applied: closing puts your look back.
    Card("bold"):Click()
    panel.done:Click()
    Equal(ns.Get("barColour") .. " " .. tostring(ns.Previewing()), "orange false", "Done without Apply: your own look back")
    w.presets:Click()
    -- Text you turned off on a bar stays off.
    ns.Set("prdHealthAt", "off")
    Card("classic"):Click()
    panel.apply:Click()
    Equal(ns.Get("prdHealthAt") .. " " .. ns.Get("prdPowerAt") .. " " .. ns.Get("barTexture"), "off centre classic",
        "a preset never turns text on where you switched it off")
    Equal(Note(panel.apply) .. " | " .. Note(Card("minimal")), "Keep this look, and switch on what's ticked. | Minimal: Outline bars, small"
        .. " and quiet.", "each part says what it does")
    Equal(table.concat(found, " | "), "", "the panel inside the window, under the title bar and clear of the footer, nothing overlapping")
end)()

-- Colour rows: one swatch and its pop-up ---------------------------------------------------------
-- Every colour row but the window's accent is one swatch in the colour in
-- use, which opens a pop-up: Custom first (a rainbow), then the row's named
-- colours. A named one picks as the row always did and closes it; Custom
-- opens the game's colour picker (out of combat), the row following it, its
-- colour kept beside the named ones. The pop-up closes on Escape (alone, the
-- window staying), a click elsewhere, another page, its row going and the
-- window closing; one at a time.

;(function()
    local ns = Start({ useBars = true, notesSeen = "dev", helpSeen = true })
    for _, timer in ipairs(timers) do timer() end
    SlashCmdList.FECM("")
    local w = FECMFrame
    w:Select("look")
    local function Note(control) return type(control.hint) == "function" and control.hint(control) or tostring(control.hint) end
    local function Fill(choice)
        local call = S[choice.fill].last.SetColorTexture
        return ("%.2f,%.2f,%.2f"):format(call[1], call[2], call[3])
    end
    local choice = w.barColour
    local popup = choice.popup
    -- Closed until clicked: Custom first, then the six bar colours, each a
    -- swatch of the same size, in a row, the class colour with its icon.
    local keys, places = { choice.custom.key }, { S[choice.custom].points[1][2] }
    for _, swatch in ipairs(choice.swatches) do
        keys[#keys + 1] = swatch.key
        places[#places + 1] = S[swatch].points[1][2]
    end
    Equal(tostring(popup:IsShown()) .. " | " .. table.concat(keys, " ") .. " | " .. table.concat(places, " ") .. " | " .. Fill(choice)
        .. " " .. tostring(S[choice.icon].shown) .. " " .. tostring(Last(choice.swatches[6].icon, "SetAtlas", 1)) .. " | " .. S[popup].width,
        "false | custom orange charcoal blue green purple class | 6 30 54 78 102 126 150 | 1.00,0.50,0.25 false classicon-druid | 176",
        "one swatch in your colour, its pop-up closed: Custom first, then the bar colours")
    -- Custom is a rainbow of the addon's own: six bands round the colour
    -- wheel and a shade darker at the foot, all gradients.
    local bands, first = 0, nil
    for _, obj in ipairs(objects) do
        if S[obj].parent == choice.custom and S[obj].kind == "Texture" and S[obj].last.SetGradient then
            bands = bands + 1
            first = first or S[obj].last.SetGradient
        end
    end
    Equal(bands .. " " .. first[1] .. " " .. first[2].r .. "," .. first[2].g .. " " .. first[3].r .. "," .. first[3].g .. " | " .. Note(choice.custom),
        "7 HORIZONTAL 1,0 1,1 | Custom: any colour you like, from the game's colour picker. It shows as you pick, and Cancel puts back"
        .. " the one before.", "Custom drawn as a rainbow, its hover no longer marked experimental (seen working in game)")
    -- Open, a named colour picks and closes it.
    choice:Click()
    Equal(tostring(popup:IsShown()) .. " " .. tostring(S[popup].events.GLOBAL_MOUSE_DOWN) .. " " .. tostring(rawequal(_G.FECMFrame, popup))
        .. " | " .. Note(choice), "true true true | The colour for all your Tracked Bars. Click for the colours.",
        "clicked: its pop-up opens, listening for a click elsewhere, Escape's entry its own")
    choice.swatches[3]:Click()
    Equal(ns.Get("barColour") .. " " .. tostring(popup:IsShown()) .. " " .. tostring(rawequal(_G.FECMFrame, w)) .. " "
        .. tostring(S[popup].events.GLOBAL_MOUSE_DOWN) .. " | " .. S[w.barChosen].text .. " " .. Fill(choice) .. " "
        .. S[choice.swatches[3]].border[1], "blue false true nil | Blue 0.24,0.55,0.88 1", "a named colour: picked, shown, the pop-up gone")
    -- Escape closes the pop-up alone; the next Escape the window.
    choice:Click()
    CloseSpecialWindows()
    Equal(tostring(popup:IsShown()) .. " " .. tostring(w:IsShown()) .. " " .. tostring(rawequal(_G.FECMFrame, w)), "false true true",
        "Escape: the pop-up goes, the window stays")
    CloseSpecialWindows()
    Equal(tostring(w:IsShown()), "false", "and the next Escape closes the window")
    SlashCmdList.FECM("")
    -- A click elsewhere closes it; on it, or on its own swatch, it stays.
    choice:Click()
    S[popup].mouseOver = true
    Fire("GLOBAL_MOUSE_DOWN", "LeftButton")
    local stays = popup:IsShown()
    S[popup].mouseOver, S[choice].mouseOver = false, true
    Fire("GLOBAL_MOUSE_DOWN", "LeftButton")
    stays = tostring(stays) .. " " .. tostring(popup:IsShown())
    S[choice].mouseOver = false
    Fire("GLOBAL_MOUSE_DOWN", "LeftButton")
    Equal(stays .. " " .. tostring(popup:IsShown()), "true true false", "a click on it or its swatch keeps it, anywhere else closes it")
    choice:Click()
    choice:Click()
    Equal(tostring(popup:IsShown()), "false", "its swatch clicked again closes it")
    -- The window closing takes it, and it doesn't come back with the window.
    choice:Click()
    w:Hide()
    local gone = tostring(popup:IsShown()) .. " " .. tostring(rawequal(_G.FECMFrame, w))
    w:Show()
    Equal(gone .. " " .. tostring(popup:IsShown()), "false true false", "the window closing closes it, for good")
    -- Another page, and one pop-up at a time.
    choice:Click()
    w:Select("cast")
    local cp = w.pages.cast
    Equal(tostring(popup:IsShown()), "false", "another page closes it")
    cp.colour:Click()
    cp.swingColour:Click()
    Equal(tostring(cp.colour.popup:IsShown()) .. " " .. tostring(cp.swingColour.popup:IsShown()), "false true", "one at a time")
    cp.swingColour:Click()
    -- A row going (latency switched off) takes its pop-up.
    ns.Set("castLatency", true)
    cp.latencyColour:Click()
    ns.Set("castLatency", false)
    Equal(tostring(cp.latencyColour:IsVisible()) .. " " .. tostring(cp.latencyColour.popup:IsShown()) .. " " .. tostring(rawequal(_G.FECMFrame, w)),
        "false false true", "its row hidden: the pop-up goes too")
    -- Click it again for the default, as before: through the pop-up.
    cp.colour:Click()
    cp.colour.swatches[3]:Click()
    cp.colour:Click()
    Equal(ns.Get("castColour") .. " " .. S[cp.chosen].text .. " " .. Note(cp.colour.swatches[3]), "blue Blue A colour for your cast bar."
        .. " Click it again for Blizzard's gold, green while channelling.", "a cast colour, each swatch saying the chosen one again is gold")
    cp.colour.swatches[3]:Click()
    Equal(ns.Get("castColour") .. " " .. S[cp.chosen].text .. " " .. Fill(cp.colour), "default Blizzard's gold 1.00,0.70,0.00",
        "clicked again: Blizzard's gold, the swatch in it")

    -- Custom: the game's colour picker, set up through its own call. In a
    -- fight, or without it, the footer says so and nothing opens.
    w:Select("look")
    lockdown = true
    choice.custom:Click()
    local said = S[w.note].text
    lockdown = false
    _G.ColorPickerFrame = nil
    choice.custom:Click()
    Equal(said .. " | " .. S[w.note].text .. " | " .. ns.Get("barColour"), "Finish combat first, then pick a custom colour. | The game's"
        .. " colour picker isn't there. Pick one of the other colours instead. | blue", "in a fight or without the picker: says so, nothing changes")
    -- The picker as the game's: its setup shows it and sets its colour,
    -- which calls back as any colour picked does.
    local picker = { shown = false, setups = 0 }
    function picker:SetupColorPickerAndShow(info)
        self.info, self.setups, self.shown = info, self.setups + 1, true
        self.r, self.g, self.b = info.r, info.g, info.b
        info.swatchFunc()
    end
    function picker:GetColorRGB() return self.r, self.g, self.b end
    function picker:IsShown() return self.shown end
    _G.ColorPickerFrame = picker
    -- In gamepad mode the picker sets up gamepad buttons (bindings) as it
    -- opens, which mustn't come from an addon's click: Custom says so and
    -- nothing opens. With the mouse and keyboard it opens (below).
    local style, enum, mode = _G.C_InputInterfaceStyle, _G.Enum, 1
    _G.Enum = setmetatable({ InputDeviceInterfaceType = { Mkb = 0, Gamepad = 1 } }, { __index = enum })
    _G.C_InputInterfaceStyle = { GetCurrentStyle = function() return mode end }
    choice.custom:Click()
    Equal(S[w.note].text .. " | " .. picker.setups .. " " .. tostring(picker.shown) .. " " .. ns.Get("barColour") .. " "
        .. tostring(w.colourWatch:IsShown()), "Custom needs the mouse and keyboard, not the gamepad. Pick one of the other colours"
        .. " instead. | 0 false blue false", "in gamepad mode: says so, the picker not opened, nothing changes")
    mode = 0
    local function Pick(r, g, b)
        picker.r, picker.g, picker.b = r, g, b
        picker.info.swatchFunc()
    end
    local function Close()
        picker.shown = false
        S[w.colourWatch].scripts.OnUpdate(w.colourWatch, 0)
    end
    ns.Set("barColour", "orange")
    choice:Click()
    choice.custom:Click()
    local info = picker.info
    Equal(picker.setups .. " " .. ("%.2f,%.2f,%.2f"):format(info.r, info.g, info.b) .. " " .. tostring(info.hasOpacity) .. " "
        .. tostring(popup:IsShown()) .. " " .. Last(w, "SetFrameStrata", 1) .. " " .. tostring(w.colourWatch:IsShown()) .. " | "
        .. ns.Get("barColour") .. " " .. ns.Get("barColourCustom"), "1 1.00,0.50,0.25 false false HIGH true | orange ",
        "Custom: the picker opens in your colour, the pop-up gone, the window a layer under it; nothing changed yet")
    Pick(.2, .4, .6)
    local tint = ns.Style:BarColour(ns.ColourKey("barColour"))
    Equal(ns.Get("barColour") .. " " .. ns.Get("barColourCustom") .. " " .. S[w.barChosen].text .. " " .. Fill(choice) .. " "
        .. ("%.2f,%.2f,%.2f"):format(tint[1], tint[2], tint[3]) .. " " .. ("%.2f"):format(Last(w.preview.Bar, "SetStatusBarColor", 1))
        .. " " .. S[choice.custom].border[1], "custom 336699 Custom 0.20,0.40,0.60 0.20,0.40,0.60 0.20 1",
        "a colour picked: Custom, its colour kept beside it, on the swatch, your bars and the preview")
    Close()
    Equal(Last(w, "SetFrameStrata", 1) .. " " .. tostring(w.colourWatch:IsShown()) .. " " .. ns.Get("barColour"),
        "FULLSCREEN_DIALOG false custom", "OK: the picker closed, the window back on top, the colour kept")
    -- Again: it starts from the custom colour; Cancel puts it back.
    choice.custom:Click()
    info = picker.info
    Pick(.8, .1, .1)
    local moved = ns.Get("barColourCustom")
    info.cancelFunc()
    picker.shown = false
    Equal(("%.2f,%.2f,%.2f"):format(info.r, info.g, info.b) .. " " .. moved .. " | " .. ns.Get("barColour") .. " " .. ns.Get("barColourCustom")
        .. " " .. Last(w, "SetFrameStrata", 1), "0.20,0.40,0.60 cc1a1a | custom 336699 FULLSCREEN_DIALOG",
        "from the custom colour; Cancel: the one before back, the window back on top")
    -- A named colour keeps the custom one beside it, for Custom next time:
    -- the row shows what the picker shows from the start.
    choice.swatches[1]:Click()
    choice.custom:Click()
    local opened = ns.Get("barColour") .. " " .. ns.Get("barColourCustom")
    picker.info.cancelFunc()
    picker.shown = false
    Equal(opened .. " | " .. ns.Get("barColour") .. " " .. ns.Get("barColourCustom"), "custom 336699 | orange 336699",
        "orange picked, the custom colour kept; Custom starts from it, Cancel back to orange")
    -- A stale call from a picker closed or reused for something else changes nothing.
    info.swatchFunc()
    info.cancelFunc()
    Equal(ns.Get("barColour") .. " " .. Last(w, "SetFrameStrata", 1), "orange FULLSCREEN_DIALOG", "a closed session's calls do nothing")

    -- The Each bar list: a Tracked Bar's own Custom, at any rank.
    local function Tracked(id, order)
        return { GetBaseSpellID = function() return id end, layoutIndex = order }
    end
    _G.BuffBarCooldownViewer = { itemFramePool = { EnumerateActive = function() return pairs({ [Tracked(1243, 1)] = true }) end } }
    w:Refresh()
    local row = w.eachRows[1]
    row.colour:Click()
    row.colour.custom:Click()
    Pick(0, 1, 0)
    Close()
    local colours, custom = ns.BarColours()
    Equal(S[row.name].text .. " | " .. tostring(colours[1243]) .. " " .. tostring(custom[1243]) .. " " .. tostring(ns.BarColourFor(1243))
        .. " " .. S[row.chosen].text .. " " .. Fill(row.colour), "Power Word: Fortitude | custom 00ff00 #00ff00 Custom 0.00,1.00,0.00",
        "a Tracked Bar in a custom colour: kept beside, under its own ID")
    row.colour.swatches[4]:Click()
    colours, custom = ns.BarColours()
    local named = tostring(colours[1243]) .. " " .. tostring(custom[1243])
    row.colour.swatches[4]:Click()
    colours, custom = ns.BarColours()
    Equal(named .. " | " .. tostring(colours[1243]) .. " " .. tostring(custom[1243]) .. " " .. S[row.chosen].text, "green 00ff00 | nil nil Default",
        "a named colour keeps it beside; back to the colour for all, both go")
    -- The list turned by the wheel would slide an open pop-up off with its
    -- row: it closes.
    row.colour:Click()
    local before = row.colour.popup:IsShown()
    S[w.eachScroll].scripts.OnMouseWheel(w.eachScroll, -1)
    Equal(tostring(before) .. " " .. tostring(row.colour.popup:IsShown()) .. " " .. tostring(rawequal(_G.FECMFrame, w)), "true false true",
        "the list scrolled: the pop-up closes, Escape's entry the window's again")
    _G.BuffBarCooldownViewer = nil
    w:Refresh()

    -- The Debuffs bar's tick count: Custom kept on the bar (tickCustom).
    local data = ns.BarData("debuff")
    w:Select("debuff")
    local tick = w.pages.bar.options.tickChoice
    tick.custom:Click()
    Pick(1, .5, 0)
    Close()
    Equal(data.tickColour .. " " .. data.tickCustom .. " " .. ns.CountColourKey(data) .. " " .. Fill(tick) .. " | " .. Note(tick),
        "custom ff8000 #ff8000 1.00,0.50,0.00 | The tick count's colour. Click for the colours.", "the tick count in a custom colour")
    tick.swatches[2]:Click()
    Equal(data.tickColour .. " " .. data.tickCustom .. " " .. ns.CountColourKey(data), "gold ff8000 gold", "gold picked, the custom one kept")

    -- The Presets panel's own colour: Custom shown at once, applied, undone.
    w:Select("look")
    w.presets:Click()
    local panel = w.presetsPanel
    panel.colour:Click()
    panel.colour.custom:Click()
    Pick(.5, 0, .5)
    local shown = ns.Get("barColour") .. " " .. ns.Get("barColourCustom") .. " " .. ns.GetSaved("barColour") .. " " .. tostring(ns.Previewing())
    Close()
    panel.apply:Click()
    local applied = ns.GetSaved("barColour") .. " " .. ns.GetSaved("barColourCustom")
    panel.undo:Click()
    Equal(shown .. " | " .. applied .. " | " .. ns.GetSaved("barColour") .. " " .. ns.GetSaved("barColourCustom"),
        "custom 800080 orange true | custom 800080 | orange 336699", "Presets: Custom previewed, applied, and Undo puts both back")
    panel.done:Click()

    -- Kept over a reload; a Custom with no colour kept goes back to its default.
    ns.Set("castColour", ns.CUSTOM)
    ns.Set("castColourCustom", "")
    ns.Set("swingColour", ns.CUSTOM)
    ns.Set("swingColourCustom", "ABCDEF")
    local kept = ForeverEnhancedCooldownManagerDB
    kept.bars.debuff.tickColour, kept.bars.debuff.tickCustom = ns.CUSTOM, "nonsense"
    w:Hide()
    ns = Start(kept)
    Equal(ns.Get("barColour") .. " " .. ns.Get("barColourCustom") .. " | " .. ns.Get("castColour") .. " " .. ns.Get("swingColour") .. " "
        .. ns.Get("swingColourCustom") .. " | " .. ns.BarData("debuff").tickColour .. " " .. ns.BarData("debuff").tickCustom,
        "orange 336699 | default custom abcdef | white ", "kept over a reload, a Custom with no colour of its own back to its default")
    _G.C_InputInterfaceStyle, _G.Enum = style, enum
    Equal(#printed, 0, "no errors from the colour rows")
end)()

-- Icon details: the Look page's button and its panel ------------------------------------------------
-- Beside the preview's icons, Icon details opens a panel over the window:
-- the swipe's colour and see-through, the countdown's size, colour and
-- spot, and the edge line with its colour. Each starts as the icons always
-- looked, changes the panel's own icons and your bars' at once, says what it
-- does (seen working in game, so not marked experimental), fits the panel in every state, goes
-- with another page or the window, and is kept over a reload (anything odd
-- saved goes back to its default). Defaults puts them all back.

;(function()
    local ns = Start({ useBars = true, notesSeen = "dev", helpSeen = true, bars = { cd = { spells = { "Moonfire", "Wrath" } } } })
    for _, timer in ipairs(timers) do timer() end
    SlashCmdList.FECM("")
    local w = FECMFrame
    w:Select("look")
    local function Note(control) return type(control.hint) == "function" and control.hint(control) or tostring(control.hint) end
    local function Num4(call) return ("%g,%g,%g,%g"):format(call[1], call[2], call[3], call[4]) end
    local icon = ns.Bars:Get("cd").icons[1]
    -- What one of the addon's own cooldowns shows: its swipe, edge line,
    -- countdown font and where the numbers sit.
    local function Looks(cooldown)
        local numbers = cooldown:GetCountdownFontString()
        local at = S[numbers].points[1]
        return Num4(S[cooldown].last.SetSwipeColor) .. " " .. tostring(Last(cooldown, "SetDrawEdge")) .. " "
            .. tostring(Last(cooldown, "SetCountdownFont")) .. " " .. (at and (at[1] .. " " .. at[3] .. " " .. at[4] .. " " .. at[5]) or "-")
    end
    local found = {}
    local function Check(dialog, label)
        local problems = Fit.Problems(dialog)
        local _, top, _, bottom = Fit.Rect(dialog)
        if top < 42 or bottom > 560 - 28 then problems = problems .. ("the panel at %.1f to %.1f, over the title bar or the footer"):format(top, bottom) end
        if problems ~= "" then found[#found + 1] = label .. ": " .. problems end
    end
    local button = w.iconDetails
    local _, _, sampleLeft = Fit.Rect(w.preview)
    local left, _, right = Fit.Rect(button)
    local iconsLeft = Fit.Rect(w.sampleIcons)
    Equal(tostring(button:IsVisible()) .. " " .. S[button.label].text .. " " .. tostring(left > sampleLeft and right < iconsLeft) .. " | " .. Note(button)
        .. " | " .. tostring(Fit.Wide(Note(button), "GameFontHighlightSmall") <= 2 * S[w.note].width),
        "true Icon details true | The cooldown swipe's colour and see-through, the countdown's size, colour and spot, and an edge"
        .. " line, on your icons and Blizzard's, and your icons' shape, with a preview. | true",
        "Icon details in the preview, between the sample bar and the sample icons, the shape only your icons', in two lines of the"
        .. " footer, no longer marked experimental")
    Equal(Looks(icon.cooldown), "0,0,0,0.7 false FECMFont18 CENTER CENTER 0 0", "your icons as always: a 70% black swipe, no edge line,"
        .. " white numbers half the icon in its middle")

    button:Click()
    local panel = w.iconPanel
    local dialog, tray = panel.dialog, panel.tray
    local first = tray.icons[1]
    Equal(tostring(dialog:IsVisible()) .. " " .. tostring(S[panel].points[2][3]) .. " " .. #tray.icons .. " " .. Looks(first.cooldown) .. " "
        .. tostring(Last(first.cooldown, "SetCooldown", 2)) .. " " .. tostring(S[first.cooldown].scripts.OnCooldownDone ~= nil),
        "true 28 4 0,0,0,0.7 false FECMFont20 CENTER CENTER 0 0 9 true",
        "opened: its shade clear of the footer, four icons in the preview drawn as your bars', each going round and round")
    Check(dialog, "at the start")
    -- Each choice in the panel says what it does (seen working in game
    -- 2026-10-21, so none is marked experimental any more).
    local notes, marked = {}, {}
    for _, control in ipairs({ panel.swipeColour, panel.swipeColour.custom, panel.swipeColour.swatches[1], panel.seeThrough,
        panel.size, panel.countdownColour, panel.countdownColour.swatches[2], panel.spot.buttons[1], panel.spot.buttons[4],
        panel.edge, panel.edgeColour, panel.edgeColour.swatches[1], panel.defaults }) do
        local note = Note(control)
        notes[#notes + 1] = note
        if note == "" or note == "nil" or note:find("experimental", 1, true) then marked[#marked + 1] = note end
    end
    Equal(table.concat(marked, " | "), "", "every choice has a note, none marked experimental")
    Equal(notes[1] .. " | " .. notes[3] .. " | " .. notes[4] .. " | " .. notes[8] .. " | " .. notes[11] .. " | " .. notes[12],
        "The colour of the swipe going round each icon as it cools down. Click for the colours. | Black for the swipe over"
        .. " each icon as it cools down. | How much of each icon shows through the swipe: 30% as it's always been, 100% no"
        .. " swipe at all. | The countdown at the top left of each icon. It can sit over a keybind or a count in the same"
        .. " spot. | Tick Edge line first. | Game's own for the edge line.",
        "what the swipe, see-through, a spot and the edge line's colour say (greyed until it's ticked)")
    Equal(S[panel.swipeColour.name].text .. " " .. S[panel.seeThrough.value].text .. " " .. S[panel.size.value].text .. " "
        .. S[panel.countdownColour.name].text .. " " .. panel.spot.selected .. " " .. tostring(panel.edge:GetChecked()) .. " "
        .. S[panel.edgeColour.name].text .. " " .. tostring(Last(panel.edgeColour, "SetEnabled")) .. " " .. S[panel.defaults].alpha
        .. " " .. panel.iconStyle.selected,
        "Black 30% 100% White CENTER false Game's own false 0.45 square",
        "the defaults: square icons, black at 30%, 100% white numbers in the middle, no edge line (its colour greyed), Defaults greyed")

    -- Icons (a player's idea: Blizzard's look with Swap with my form): the
    -- first row, Square as always or Blizzard, its own hover quietly
    -- experimental, each fitting two lines of the footer. Blizzard draws
    -- your icons and the preview's like Blizzard's at once; Square puts them
    -- back exactly; the panel fits either way.
    do
        local row = panel.iconStyle
        local square, blizzard = row.buttons[1], row.buttons[2]
        local swipeTop = select(2, Fit.Rect(panel.swipeColour))
        local _, rowTop, _, rowBottom = Fit.Rect(row)
        local fits = Fit.Wide(Note(square), "GameFontHighlightSmall") <= 2 * S[w.note].width
            and Fit.Wide(Note(blizzard), "GameFontHighlightSmall") <= 2 * S[w.note].width
        Equal(S[square.label].text .. "/" .. S[blizzard.label].text .. " " .. tostring(rowBottom <= swipeTop and rowTop > 0) .. " "
            .. tostring(fits) .. " | " .. Note(square) .. " | " .. Note(blizzard),
            "Square/Blizzard true true | Square icons with no frame, as your bars have always looked. | Your bars' icons drawn like"
            .. " Blizzard's Cooldown Manager: rounded, in its frame, with its swipe and range shadow. Its own rows sit 4 closer."
            .. " (experimental)", "the first row, above the swipe: Square, then Blizzard, only its hover experimental and saying"
            .. " Blizzard's rows sit closer (Border and Shadow say they skip them), both two lines at most")
        local quiet, note
        for _, obj in ipairs(objects) do
            if S[obj].parent == dialog and S[obj].kind == "FontString" and tostring(S[obj].text):find("^the icons") then quiet = obj end
            if S[obj].parent == dialog and S[obj].kind == "FontString" and tostring(S[obj].text):find("^On your bars") then note = obj end
        end
        Equal(quiet and S[quiet].text, "the icons, the swipe, the countdown and the edge line",
            "the title's quiet words name the icons (Check: still inside the panel)")
        Equal(note and S[note].text, "On your bars, and on Blizzard's icons while Apply this look to the Cooldown Manager is on"
            .. " (Icons: your bars only). Each change shows at once.", "the panel's note: Icons reach only your bars (Check: it fits)")
        local art = icon.texture
        local function Drawn(texture, cooldown)
            return #(S[texture].masks or {}) .. " " .. tostring(Last(texture, "SetTexCoord")) .. " "
                .. tostring(Last(cooldown, "SetSwipeTexture"))
        end
        S[blizzard].scripts.OnClick(blizzard)
        Equal(ns.Get("iconStyle") .. " " .. row.selected .. " | " .. Drawn(art, icon.cooldown) .. " | " .. Drawn(first.shape.art, first.cooldown)
            .. " | " .. tostring(S[first.shape.frame].shown) .. " " .. S[panel.defaults].alpha,
            "blizzard blizzard | 1 0 Interface\\HUD\\UI-HUD-CoolDownManager-Icon-Swipe | 1 0 Interface\\HUD\\UI-HUD-CoolDownManager-Icon-Swipe"
            .. " | true 1", "Blizzard: your icons and the preview's masked, whole, in its frame and swipe at once; Defaults usable")
        Check(dialog, "Blizzard's icons")
        -- Presets' preview draws your icons the same way, with no border.
        panel:Hide()
        w.presets:Click()
        local preset = w.presetsPanel.tray.icons[1]
        local ringed = preset.decor.border ~= nil and S[preset.decor.border[1]].shown == true
        Equal(#(S[preset.shape.art].masks or {}) .. " " .. tostring(S[preset.shape.frame].shown) .. " " .. tostring(ringed),
            "1 true false", "Presets' preview draws your icons like Blizzard's too")
        w.presetsPanel:Hide()
        -- The Look page's Border and Shadow say they skip your icons drawn
        -- like Blizzard's, each in two lines of the footer.
        local borderNote, shadowNote = Note(w.iconBorder.buttons[1]), Note(w.iconShadow.buttons[2])
        Equal(borderNote .. " | " .. shadowNote .. " | " .. tostring(Fit.Wide(borderNote, "GameFontHighlightSmall") <= 2 * S[w.note].width
            and Fit.Wide(shadowNote, "GameFontHighlightSmall") <= 2 * S[w.note].width),
            "A thin black border round each icon, or each whole bar whose icons stay put. Yours and Blizzard's, but not your icons"
            .. " drawn like Blizzard's (Icon details). | A soft shadow round each icon, or each whole bar whose icons stay put. Your cast"
            .. " bar gets one too. Not on your icons drawn like Blizzard's (Icon details). | true",
            "Border and Shadow say they skip your icons drawn like Blizzard's, each in two lines of the footer")
        button:Click()
        S[square].scripts.OnClick(square)
        Equal(ns.Get("iconStyle") .. " " .. row.selected .. " | " .. Drawn(art, icon.cooldown) .. " | " .. Drawn(first.shape.art, first.cooldown)
            .. " | " .. tostring(S[first.shape.frame].shown) .. " " .. S[panel.defaults].alpha,
            "square square | 0 0.08 Interface\\Buttons\\WHITE8X8 | 0 0.08 Interface\\Buttons\\WHITE8X8 | false 0.45",
            "Square: both back as always, Defaults greyed again")
        Check(dialog, "square icons again")
    end

    -- The swipe: white, half see-through, at once on the preview and your bars.
    panel.swipeColour:Click()
    panel.swipeColour.swatches[2]:Click()
    panel.seeThrough:Choose(50)
    Equal(ns.Get("swipeColour") .. " " .. ns.Get("swipeSeeThrough") .. " " .. S[panel.swipeColour.name].text .. " | " .. Looks(first.cooldown)
        .. " | " .. Looks(icon.cooldown), "white 50 White | 1,1,1,0.5 false FECMFont20 CENTER CENTER 0 0 | 1,1,1,0.5 false FECMFont18"
        .. " CENTER CENTER 0 0", "a white swipe at 50%: on the preview and your icons")
    -- The countdown: half as big again, gold, in the top left.
    panel.size:Choose(150)
    panel.countdownColour:Click()
    panel.countdownColour.swatches[2]:Click()
    S[panel.spot.buttons[1]].scripts.OnClick(panel.spot.buttons[1])
    local font = _G.FECMCountdown27
    Equal(ns.Get("countdownSize") .. " " .. ns.Get("countdownColour") .. " " .. ns.Get("countdownSpot") .. " | " .. Looks(icon.cooldown)
        .. " | " .. Looks(first.cooldown) .. " | " .. ("%.2f,%.2f,%.2f"):format(S[font].colour[1], S[font].colour[2], S[font].colour[3])
        .. " " .. tostring(Last(icon.count, "SetFontObject")), "150 gold TOPLEFT | 1,1,1,0.5 false FECMCountdown27 TOPLEFT TOPLEFT 1 -1"
        .. " | 1,1,1,0.5 false FECMCountdown30 TOPLEFT TOPLEFT 1 -1 | 1.00,0.82,0.00 FECMFont13",
        "the numbers 150% in their own gold font, in the top left corner just in from the edge; item counts keep theirs")
    Check(dialog, "gold numbers in the top left")
    -- The edge line, then its colour: blue.
    panel.edge:Click()
    local edgeOn = tostring(Last(icon.cooldown, "SetDrawEdge")) .. " " .. Num4(S[icon.cooldown].last.SetEdgeColor) .. " "
        .. tostring(Last(panel.edgeColour, "SetEnabled")) .. " " .. Note(panel.edgeColour)
    panel.edgeColour:Click()
    panel.edgeColour.swatches[4]:Click()
    Equal(edgeOn .. " | " .. ns.Get("edgeColour") .. " " .. Num4(S[icon.cooldown].last.SetEdgeColor) .. " "
        .. Num4(S[first.cooldown].last.SetEdgeColor) .. " " .. S[panel.edgeColour.name].text,
        "true 1,1,1,1 true The edge line's colour: the game's own, or tinted. Click for the colours. | blue"
        .. " 0.24,0.55,0.88,1 0.24,0.55,0.88,1 Blue", "the edge line on: the game's own line, then tinted blue, its colour no longer greyed")
    Check(dialog, "the edge line in blue")
    -- A countdown colour of your own, from the game's colour picker.
    local picker = { shown = false }
    function picker:SetupColorPickerAndShow(info)
        self.info, self.shown = info, true
        self.r, self.g, self.b = info.r, info.g, info.b
        info.swatchFunc()
    end
    function picker:GetColorRGB() return self.r, self.g, self.b end
    function picker:IsShown() return self.shown end
    _G.ColorPickerFrame = picker
    panel.countdownColour:Click()
    panel.countdownColour.custom:Click()
    picker.r, picker.g, picker.b = 0, 1, 1
    picker.info.swatchFunc()
    picker.shown = false
    S[w.colourWatch].scripts.OnUpdate(w.colourWatch, 0)
    Equal(ns.Get("countdownColour") .. " " .. ns.Get("countdownColourCustom") .. " " .. S[panel.countdownColour.name].text .. " "
        .. ("%.2f,%.2f,%.2f"):format(S[font].colour[1], S[font].colour[2], S[font].colour[3]),
        "custom 00ffff Custom 0.00,1.00,1.00", "Custom: the numbers in any colour, kept beside the named ones")
    Check(dialog, "custom colours")
    Equal(tostring(Last(panel.defaults, "SetEnabled")) .. " " .. S[panel.defaults].alpha, "true 1", "Defaults usable once anything's changed")

    -- Timer text (a player's idea): the game's own countdown, or whole
    -- minutes then seconds (3m, 2m, 1m, then 59s), at once on the preview
    -- and your icons, through the cooldown's own setters only: the game's
    -- seconds formatter, set up once, and its switch to a count of minutes
    -- at a minute. Nothing is set at the default; picked back, each gets the
    -- game's own again (the switch as read off a cooldown of the addon's own).
    do
        local calls, made, makes = {}, {}, 0
        setmetatable(made, { __index = function(_, method)
            return function(_, value) calls[#calls + 1] = method .. " " .. tostring(value) end
        end })
        local util, enum, read = _G.C_StringUtil, _G.Enum, Proto.GetCountdownAbbrevThreshold
        _G.C_StringUtil = { CreateSecondsFormatter = function() makes = makes + 1; return made end }
        _G.Enum = setmetatable({ SecondsFormatterAbbreviation = { OneLetter = 2 }, SecondsFormatterInterval = { Seconds = 0 },
            SecondsFormatterRounding = { RoundUp = 0 }, SecondsFormatterIntervalWhitespace = { Strip = 1 } }, { __index = enum })
        function Proto:GetCountdownAbbrevThreshold() return 3600 end
        local format = panel.format
        local function Text(cooldown)
            local formatter, switch = S[cooldown].last.SetCountdownFormatter, S[cooldown].last.SetCountdownAbbrevThreshold
            return (formatter == nil and "-" or formatter[1] == made and "minutes" or tostring(formatter[1])) .. " "
                .. (switch == nil and "-" or tostring(switch[1]))
        end
        Equal(format.selected .. " | " .. Note(format.buttons[1]) .. " | " .. Note(format.buttons[2]) .. " | "
            .. S[format.buttons[1].label].text .. " / " .. S[format.buttons[2].label].text .. " | " .. Text(icon.cooldown) .. " " .. makes,
            "game | The countdown as the game writes it, like 2:52, as it's always been. | Whole minutes, then seconds under a minute:"
            .. " 3m, 2m, 1m, then 59s. On your bars and Blizzard's icons. (experimental) | Game (2:52) / Minutes, then seconds (3m, 59s)"
            .. " | - - 0", "Text: the game's own to start with, nothing set on any cooldown; minutes then seconds quietly experimental")
        S[format.buttons[2]].scripts.OnClick(format.buttons[2])
        Equal(ns.Get("countdownFormat") .. " " .. format.selected .. " | " .. Text(icon.cooldown) .. " | " .. Text(first.cooldown) .. " | "
            .. makes .. " " .. table.concat(calls, ", "), "minutes minutes | minutes 60 | minutes 60 | 1 SetDefaultAbbreviation 2,"
            .. " SetStripIntervalWhitespace 1, SetDesiredUnitCount 1, SetMinInterval 0, SetRounding 0, SetCanRoundUpLastUnit true,"
            .. " SetCanRoundUpIntervals true", "minutes then seconds: one formatter made for 3m and 59s, on your icons and the preview,"
            .. " the switch to minutes at a minute")
        Check(dialog, "minutes then seconds")
        Equal(ns.DebugReport():match("Countdown: [^\n]*"), "Countdown: size 150%, spot TOPLEFT, text minutes (formatter made,"
            .. " game's switch 3600)", "/ccm debug says how it went")
        S[format.buttons[1]].scripts.OnClick(format.buttons[1])
        Equal(ns.Get("countdownFormat") .. " | " .. Text(icon.cooldown) .. " | " .. Text(first.cooldown) .. " " .. makes,
            "game | nil 3600 | nil 3600 1", "back to the game's own: the formatter cleared, the switch where the game keeps it")
        _G.C_StringUtil, _G.Enum, Proto.GetCountdownAbbrevThreshold = util, enum, read
    end

    -- Another page, the window closing and the window opened again each put it away.
    local said = {}
    for _, step in ipairs({ { "a page", function() w:Select("general") end }, { "the window closing", function() w:Hide() end },
        { "the window opened", function() ns.ShowWindow() end } }) do
        ns.ShowWindow()
        w:Select("look")
        button:Click()
        local open = dialog:IsVisible()
        step[2]()
        said[#said + 1] = step[1] .. " " .. tostring(open) .. " " .. tostring(S[panel].shown)
    end
    Equal(table.concat(said, " | "), "a page true false | the window closing true false | the window opened true false",
        "another page, the window closing or opened again: the panel goes")

    -- Kept over a reload: your bars' new icons come in the details picked
    -- (Blizzard's icons too).
    S[panel.iconStyle.buttons[2]].scripts.OnClick(panel.iconStyle.buttons[2])
    local kept = ForeverEnhancedCooldownManagerDB
    w:Hide()
    ns = Start(kept)
    icon = ns.Bars:Get("cd").icons[1]
    Equal(Looks(icon.cooldown) .. " " .. Num4(S[icon.cooldown].last.SetEdgeColor) .. " " .. #(S[icon.texture].masks or {}),
        "1,1,1,0.5 true FECMCountdown27 TOPLEFT TOPLEFT 1 -1 0.24,0.55,0.88,1 1", "kept over a reload: your icons made with them,"
        .. " drawn like Blizzard's")
    -- Defaults: all back, the custom colour kept beside for next time.
    SlashCmdList.FECM("")
    w = FECMFrame
    w:Select("look")
    w.iconDetails:Click()
    panel = w.iconPanel
    panel.defaults:Click()
    local back = {}
    for _, key in ipairs(ns.ICON_DETAILS) do back[#back + 1] = tostring(ns.Get(key)) end
    Equal(table.concat(back, " ") .. " " .. ns.Get("countdownColourCustom") .. " | " .. Looks(icon.cooldown) .. " | "
        .. Looks(panel.tray.icons[1].cooldown) .. " " .. S[panel.defaults].alpha .. " " .. #(S[icon.texture].masks or {}),
        "black 30 100 white CENTER game false game square 00ffff |"
        .. " 0,0,0,0.7 false FECMFont18 CENTER CENTER 0 0 | 0,0,0,0.7 false FECMFont20 CENTER CENTER 0 0 0.45 0",
        "Defaults: every detail back, square icons too, on your icons and the preview, the custom colour kept beside")
    -- Anything odd saved goes back to its default.
    kept = ForeverEnhancedCooldownManagerDB
    kept.swipeColour, kept.swipeSeeThrough, kept.countdownSize, kept.countdownColour = "pink", 101, 49.5, ns.CUSTOM
    kept.countdownColourCustom, kept.countdownSpot, kept.swipeEdge, kept.edgeColour = "zzzzzz", "MIDDLE", "yes", "gold"
    kept.countdownFormat, kept.iconStyle = "hours", "round"
    w:Hide()
    ns = Start(kept)
    back = {}
    for _, key in ipairs(ns.ICON_DETAILS) do back[#back + 1] = tostring(ns.Get(key)) end
    Equal(table.concat(back, " ") .. " " .. tostring(ForeverEnhancedCooldownManagerDB.countdownColourCustom),
        "black 30 100 white CENTER game false game square nil", "odd values saved: each back to its default, a Custom with no colour too")
    _G.ColorPickerFrame = nil
    Equal(table.concat(found, " | "), "", "in every state: every piece inside the panel and none on another, under the title bar, clear of the footer")
    Equal(#printed, 0, "no errors from Icon details")
end)()

-- Settings per spell: a tray icon's own panel ---------------------------------------------------------
-- (A player's idea: a font and size per icon.) An icon in a bar page's tray
-- clicked with nothing held opens its own panel over the window: its icon
-- with a countdown going round, at the bar's size, in its look; its
-- countdown's font (the Look page's, then every font, each in its own face)
-- and its own size (a tick, then a percent); and on the Buffs and Debuffs
-- pages its own ticks from the spell list. Nothing changes until picked;
-- each change shows at once on your icons and the preview, is kept by entry
-- in the profile (over a reload too), and every hover of the new choices
-- is quietly experimental. Defaults puts its look back. It fits in every
-- state, and goes with another page, the window or its entry; with a spell
-- held, a click drops it on the bar as before.

;(function()
    local ns = Start({ useBars = true, notesSeen = "dev", helpSeen = true, bars = { cd = { spells = { "Moonfire", "Wrath" } } } })
    for _, timer in ipairs(timers) do timer() end
    local B = ns.Bars
    B:SetAura("buff", "Thorns", true)
    B:SetAura("debuff", "Moonfire", true)
    SlashCmdList.FECM("")
    local w = FECMFrame
    w:Select("cd")
    local bp = w.pages.bar
    local function Note(control) return type(control.hint) == "function" and control.hint(control) or tostring(control.hint) end
    local function Font(cooldown) return tostring(Last(cooldown, "SetCountdownFont")) end
    local found = {}
    local function Check(panel, label)
        local problems = Fit.Problems(panel.dialog)
        local _, top, _, bottom = Fit.Rect(panel.dialog)
        if top < 42 or bottom > 560 - 28 then problems = problems .. ("the panel at %.1f to %.1f, over the title bar or the footer"):format(top, bottom) end
        if problems ~= "" then found[#found + 1] = label .. ": " .. problems end
    end
    local cd = B:Get("cd")
    Equal(Font(cd.icons[1].cooldown) .. " " .. tostring(w.spellPanel), "FECMFont18 nil", "your icons as always, and no panel until one is clicked")

    -- Clicked with nothing held: Moonfire's own panel, nothing changed yet.
    bp.icons[1]:Click()
    local panel = w.spellPanel
    local preview = panel.preview
    Equal(table.concat({ tostring(panel.dialog:IsVisible()), tostring(S[panel].points[2][3]), S[panel.title].text, S[panel.quiet].text,
        panel.font.selected, S[panel.font.label].text, tostring(panel.own:GetChecked()), S[panel.size.value].text, tostring(panel.size.usable),
        tostring(panel.glow:IsVisible()), tostring(panel.only:IsVisible()), tostring(panel.ticks:IsVisible()), tostring(S[panel.defaults].alpha) }, " "),
        "true 28 MOONFIRE on Cooldowns look Look page false 100% false false false false 0.45",
        "opened over the window, clear of the footer: the Look page's font and size, no ticks on Cooldowns, Defaults greyed")
    Equal(tostring(panel.active:IsVisible()) .. " " .. tostring(panel.glowSize:IsVisible()) .. " " .. tostring(panel.glowSizeLabel:IsVisible()),
        "false false false", "no Glow while active on Cooldowns, nor its Glow size")
    Equal(Font(preview.cooldown) .. " " .. S[preview].width .. " " .. tostring(Last(preview.cooldown, "SetCooldown", 2)) .. " "
        .. tostring(S[preview.cooldown].scripts.OnCooldownDone ~= nil) .. " " .. tostring(S[preview.art].texture == ns.Spells:Icon("Moonfire")),
        "FECMFont18 36 75 true true", "the preview: its icon at the bar's size, its countdown going round and round")
    Equal(tostring(panel.warn:IsVisible()) .. " " .. tostring(panel.warnLabel:IsVisible()) .. " " .. tostring(panel.dim:IsVisible()),
        "false false false", "no Warn at on Cooldowns, nor Dim until Warn at: they're for the Buffs and Debuffs bars' auras")
    Check(panel, "Cooldowns, at the start")
    -- Show reagent count: only on a spell that uses a reagent, and it shows
    -- the game's number on that icon alone, gone when unticked.
    Equal(tostring(panel.reagents:IsVisible()), "false", "no reagent tick on a spell that uses none")
    local icon = cd.icons[1]
    _G.C_Spell.IsConsumableSpell = function() return true end
    _G.C_Spell.GetSpellCastCount = function() return 20 end
    panel:Refresh()
    Equal(tostring(panel.reagents:IsVisible()) .. " " .. S[panel.reagents.text].text .. " " .. tostring(panel.reagents:GetChecked()) .. " " .. tostring(S[icon.count].text),
        "true Show reagent count false ", "a spell that uses one: the tick, off, and no number yet")
    Check(panel, "Cooldowns, with the reagent tick")
    panel.reagents:Click()
    Equal(tostring(B:ShowsReagents("Moonfire")) .. " " .. tostring(S[icon.count].text), "true 20", "ticked: the number on its icon")
    local kept = ns.SpellLook("Moonfire")
    Equal(tostring(kept and kept.reagents) .. " " .. tostring(kept and kept.font) .. " " .. tostring(kept and kept.size), "true nil nil", "kept with the spell's own look")
    panel.defaults:Click()
    Equal(tostring(B:ShowsReagents("Moonfire")), "true", "Defaults leaves the tick, as it does the others")
    _G.C_Spell.GetSpellCastCount = function() error("no") end
    B:RefreshAll()
    Equal(tostring(S[icon.count].text), "20", "a failed read keeps the last number")
    _G.C_Spell.GetSpellCastCount = function() return 20 end
    panel.reagents:Click()
    Equal(tostring(B:ShowsReagents("Moonfire")) .. " " .. tostring(ns.SpellLook("Moonfire")) .. " [" .. tostring(S[icon.count].text) .. "]", "false nil []", "unticked: gone, nothing kept")
    _G.C_Spell.IsConsumableSpell, _G.C_Spell.GetSpellCastCount = nil, nil
    panel:Refresh()
    -- Each choice says what it does; the new ones quietly experimental.
    panel.font:Click()
    local notes = { Note(panel.font), Note(panel.font.buttons[1]), Note(panel.font.buttons[7]), Note(panel.own), Note(panel.size),
        Note(panel.defaults), Note(panel.done) }
    local rows = {}
    for i, row in ipairs(panel.font.buttons) do rows[i] = S[row.label].text end
    panel.font:Click()
    Equal(table.concat(notes, " | "), "This spell's countdown font: the Look page's, or one of its own. Click for the fonts. (experimental) | The"
        .. " Look page's font, now Friz Quadrata. | Barlow Semi Condensed, narrow like road signs, just for this spell's countdown. | Gives"
        .. " this spell's countdown a size of its own, in place of Icon details' Size on the Look page. (experimental) | Tick Its own first:"
        .. " until then it's Icon details' Size. | This spell's countdown back in the Look page's font and size, and its icon at the"
        .. " bar's size. Its ticks stay as they are. | Close this panel. Every choice is kept as you make it.",
        "each says what it does; the font and size quietly experimental")
    -- Its icon's own size, in the row under (an icon's own size: a player's
    -- idea): off at first, saying what it does, quietly experimental.
    Equal(table.concat({ tostring(panel.ownIcon:GetChecked()), S[panel.iconSize.value].text, tostring(panel.iconSize.usable),
        tostring(panel.ownIcon.usable), Note(panel.ownIcon), Note(panel.iconSize) }, " | "), "false | 100% | false | true | Gives this"
        .. " icon a size of its own on Cooldowns, in place of the bar's Icon size. (experimental) | Tick Its own first: until then"
        .. " it's the bar's Icon size.", "Icon size: off at first, the bar's size, saying what it does")
    Equal(table.concat(rows, ", "), "Look page, Friz Quadrata, Arial Narrow, Morpheus, Skurri, Game font, Barlow Semi Condensed,"
        .. " Saira Semi Condensed, Fira Sans Condensed", "the Look page's font first, then every font")

    -- A font of its own: Moonfire's icon and the preview at once, Wrath's as it was.
    panel.font.buttons[7]:Click()
    Equal(ns.Style:LookKey(ns.SpellLook("Moonfire")) .. " " .. Font(cd.icons[1].cooldown) .. " " .. Font(cd.icons[2].cooldown) .. " "
        .. Font(preview.cooldown) .. " " .. panel.font.selected .. " " .. S[panel.font.label].text .. " " .. S[panel.defaults].alpha,
        "barlow/ FECMFontbarlow18 FECMFont18 FECMFontbarlow18 barlow Barlow Semi Condensed 1",
        "Barlow for Moonfire: its icon and the preview at once, Wrath's as it was, Defaults usable")
    -- Its own size: ticked, the Look page's to start; then bigger.
    panel.own:Click()
    local ticked = ns.Style:LookKey(ns.SpellLook("Moonfire")) .. " " .. tostring(panel.size.usable) .. " " .. Font(cd.icons[1].cooldown)
    panel.size:Choose(150)
    Equal(ticked .. " | " .. ns.Style:LookKey(ns.SpellLook("Moonfire")) .. " " .. Font(cd.icons[1].cooldown) .. " " .. Font(preview.cooldown)
        .. " " .. S[panel.size.value].text .. " | " .. Note(panel.size), "barlow/100 true FECMFontbarlow18 | barlow/150 FECMFontbarlow27"
        .. " FECMFontbarlow27 150% | How big this spell's countdown is: 100% is about half the icon. In the middle it still moves clear of a"
        .. " keybind. (experimental)", "its own size: the Look page's to start, then 150% on its icon and the preview")
    Check(panel, "Cooldowns, Barlow at 150%")
    Equal(ns.DebugReport():match("Own countdowns: [^\n]*"), "Own countdowns: Moonfire (barlow, 150%)", "/ccm debug lists it")
    -- Unticked: the Look page's size again, its font kept.
    panel.own:Click()
    Equal(ns.Style:LookKey(ns.SpellLook("Moonfire")) .. " " .. Font(cd.icons[1].cooldown) .. " " .. tostring(panel.size.usable) .. " "
        .. S[panel.size.value].text, "barlow/ FECMFontbarlow18 false 100%", "unticked: the Look page's size again, the slider greyed")
    -- Ticked again with another Size in Icon details: it starts at that one.
    ns.Set("countdownSize", 80)
    w:Refresh()
    panel.own:Click()
    local again = ns.Style:LookKey(ns.SpellLook("Moonfire")) .. " " .. S[panel.size.value].text
    ns.Set("countdownSize", 100)
    w:Refresh()
    Equal(again, "barlow/80 80%", "ticked again: it starts at Icon details' Size, 80% there")
    panel.size:Choose(120)

    -- Kept by entry in the profile, over a reload.
    local kept = ForeverEnhancedCooldownManagerDB
    w:Hide()
    ns = Start(kept)
    B = ns.Bars
    cd = B:Get("cd")
    Equal(Font(cd.icons[1].cooldown) .. " " .. Font(cd.icons[2].cooldown), "FECMFontbarlow22 FECMFont18",
        "kept over a reload: Moonfire's icon made in Barlow at 120%")
    SlashCmdList.FECM("")
    w = FECMFrame
    w:Select("cd")
    bp = w.pages.bar
    bp.icons[1]:Click()
    panel, preview = w.spellPanel, w.spellPanel.preview
    Equal(panel.font.selected .. " " .. tostring(panel.own:GetChecked()) .. " " .. S[panel.size.value].text, "barlow true 120%",
        "opened again: as kept")
    -- Defaults: its look back to the Look page's, none kept.
    panel.defaults:Click()
    Equal(Font(cd.icons[1].cooldown) .. " " .. panel.font.selected .. " " .. tostring(panel.own:GetChecked()) .. " " .. S[panel.defaults].alpha
        .. " " .. tostring(ns.ProfileLists().spellLook), "FECMFont18 look false 0.45 nil", "Defaults: back to the Look page's, none kept")

    -- On the Debuffs page: Glow when missing and Count ticks, as on its row.
    w:Select("debuff")
    Equal(tostring(S[panel].shown), "false", "another page: the panel goes")
    bp.icons[1]:Click()
    local function RowOf(name)
        for _, row in ipairs(bp.rows) do
            if row:IsVisible() and row.spell == name then return row end
        end
    end
    Equal(table.concat({ S[panel.title].text, S[panel.quiet].text, tostring(panel.glow:IsVisible()), tostring(panel.glow.usable),
        tostring(panel.only:IsVisible()), tostring(panel.ticks:IsVisible()), tostring(panel.ticks.usable) }, " ") .. " | " .. Note(panel.glow)
        .. " | " .. Note(panel.ticks) .. " | " .. S[panel.note].text, "MOONFIRE on Debuffs true false false true true | Tick Show missing debuffs"
        .. " greyed first: the glow shows on a missing debuff's greyed spot. | Counts its ticks on its icon, every 3 seconds for Moonfire,"
        .. " starting again when you reapply it. | On every bar it's on, and on Blizzard's icon for it while the look is on the Cooldown"
        .. " Manager. The Buffs and Debuffs bars change once you're out of combat.",
        "its own ticks as on its row: Glow when missing greyed until missing debuffs show greyed, Count ticks with its pace")
    Check(panel, "Debuffs, two ticks")
    Equal(tostring(panel.active:IsVisible()) .. " " .. tostring(panel.glowSize:IsVisible()), "false false",
        "no Glow while active on the Debuffs page, nor its Glow size: they're for buffs")
    panel.ticks:Click()
    Equal(tostring(B:CountsTicks("debuff", "Moonfire")) .. " " .. tostring(panel.ticks:GetChecked()) .. " " .. tostring(RowOf("Moonfire").ticks:GetChecked()),
        "true true true", "Count ticks from the panel: on the bar, and on its row in the list")
    RowOf("Moonfire").ticks:Click()
    Equal(tostring(B:CountsTicks("debuff", "Moonfire")) .. " " .. tostring(panel.ticks:GetChecked()), "false false",
        "and from its row: the panel follows")
    -- Warn at (a player's idea: Siphon Life with 3 seconds left): Off, then
    -- each time, in a row under the size; each says what it does, the times
    -- quietly experimental. Packed, only the numbers; with missing debuffs
    -- greyed, the edge too.
    local warnLabels = {}
    for i, button in ipairs(panel.warn.buttons) do warnLabels[i] = S[button.label].text end
    Equal(table.concat(warnLabels, " ") .. " | " .. tostring(panel.warn:IsVisible()) .. " " .. tostring(panel.warn.selected) .. " "
        .. S[panel.warnLabel].text .. " " .. tostring(S[panel.warn].alpha) .. " | " .. Note(panel.warn.buttons[1]) .. " | "
        .. Note(panel.warn.buttons[2]), "Off 3s 5s 10s 30s 1m 5m 10m | true 0 Warn at 1 | No warning: its countdown stays as it is. | Its"
        .. " countdown turns red with 3 seconds left. Tick Show missing debuffs greyed for a red edge round its icon too. (experimental)",
        "Warn at: Off picked, eight choices, each saying what it does; packed: the numbers only, and how to get the edge")
    panel.warn.buttons[2]:Click()
    Equal(tostring(B:WarnAt("debuff", "Moonfire")) .. " " .. tostring(panel.warn.selected) .. " " .. tostring(S[panel].shown),
        "3 3 true", "3s: kept for Moonfire on the Debuffs bar, picked, the panel still open")
    B:SetOption("debuff", "showMissing", true)
    w:Refresh()
    Equal(Note(panel.warn.buttons[7]), "Its countdown turns red with 5 minutes left, with a red edge round its icon. (experimental)",
        "with missing debuffs greyed: the edge too (no glow on the Debuffs bar)")
    Check(panel, "Debuffs, Warn at")
    Equal(ns.DebugReport():match("Warn at: [^|]*"), "Warn at: debuff: Moonfire 3s ", "/ccm debug lists it")
    -- Dim until Warn at (a player's idea: Moonfire not ticking down all 12
    -- seconds), right under Warn at: with a time picked and missing debuffs
    -- greyed, usable, saying what it does in two lines of the footer at most,
    -- not marked experimental (seen working in game); kept as ticked; greyed with why with no time, or
    -- packed, the tick kept. The panel fits.
    local function Fits(text) return Fit.Wide(text, "GameFontHighlightSmall") <= 2 * S[w.note].width end
    local warnY, dimY = S[panel.warn].points[1][3], S[panel.dim].points[1][3]
    Equal(table.concat({ tostring(panel.dim:IsVisible()), S[panel.dim.text].text, tostring(panel.dim:GetChecked()), tostring(panel.dim.usable),
        tostring(warnY - dimY), S[panel.dim].points[1][2], tostring(Fits(Note(panel.dim))) }, " ") .. " | " .. Note(panel.dim),
        "true Dim until Warn at false true 28 16 true | While it's up, its icon stays dark until Warn at's time is left, then lights up"
        .. " with its countdown. Missing, it shows greyed as before.",
        "Dim until Warn at in the row under Warn at, usable, saying what it does in two lines")
    panel.dim:Click()
    Equal(tostring(B:DimsUntilWarn("debuff", "Moonfire")) .. " " .. tostring(panel.dim:GetChecked()) .. " " .. tostring(S[panel].shown) .. " "
        .. tostring(ns.DebugReport():match("dim until Warn at: [^\n]*")), "true true true dim until Warn at: debuff: Moonfire",
        "ticked: kept for Moonfire on the Debuffs bar, the panel still open, /ccm debug lists it")
    Check(panel, "Debuffs, Dim until Warn at")
    panel.warn.buttons[1]:Click()
    local noTime = tostring(panel.dim.usable) .. " " .. tostring(panel.dim:GetChecked()) .. " | " .. Note(panel.dim)
    panel.warn.buttons[2]:Click()
    B:SetOption("debuff", "showMissing", false)
    w:Refresh()
    Equal(noTime .. " | " .. tostring(panel.dim.usable) .. " " .. tostring(panel.dim:GetChecked()) .. " | " .. Note(panel.dim),
        "false true | Pick a Warn at time first: its icon lights up from then. | false true | Tick Show missing debuffs greyed first: the"
        .. " dimmed icon needs a spot of its own.", "greyed with why with Warn at Off, then packed; the tick kept")
    Check(panel, "Debuffs, Dim until Warn at greyed")
    B:SetDimUntilWarn("debuff", "Moonfire", false)
    w:Refresh()
    panel.warn.buttons[1]:Click()
    Equal(tostring(B:WarnAt("debuff", "Moonfire")) .. " " .. tostring(panel.warn.selected) .. " " .. tostring(ns.ProfileLists().warnAt),
        "nil 0 nil", "Off: none kept")
    -- With a spell held, a click drops it on the bar, as before: no panel.
    panel.done:Click()
    local GetCursor = _G.GetCursorInfo
    _G.GetCursorInfo = function() return "spell", nil, nil, 5176 end
    bp.icons[1]:Click()
    local dropped = tostring(w.refused and w.refused.held) .. " " .. tostring(w.refused and w.refused.text)
    _G.GetCursorInfo = GetCursor
    Equal(dropped .. " " .. tostring(S[panel].shown), "spell:5176 " .. tostring(select(2, B:CanAdd("debuff", "5176"))) .. " false",
        "a spell held: dropped on the bar as before (turned away or not, as on the tray), no panel")

    -- On the Buffs page: Only when missing too, then Glow when missing with it.
    w:Select("buff")
    bp.icons[1]:Click()
    local only = tostring(panel.only:IsVisible()) .. " " .. tostring(panel.glow.usable) .. " " .. tostring(panel.ticks:IsVisible())
    panel.only:Click()
    panel.glow:Click()
    Equal(only .. " | " .. tostring(B:OnlyWhenMissing("buff", "Thorns")) .. " " .. tostring(B:GlowsMissing("buff", "Thorns")) .. " "
        .. tostring(panel.glow.usable) .. " | " .. S[panel.note].text:match("The Buffs.*$"), "true false false | true true true | The Buffs and Debuffs bars"
        .. " change once you're out of combat.", "Thorns: Only when missing, then Glow when missing, usable once it's ticked")
    Check(panel, "Buffs, two ticks")
    -- Warn at greyed for a buff shown only while it's missing: no icon while it's up.
    Equal(tostring(S[panel.warn].alpha) .. " " .. tostring(Last(panel.warn.buttons[2], "SetEnabled")) .. " | " .. Note(panel.warn.buttons[2]),
        "0.35 false | Not for a buff shown Only when missing: it has no icon while it's on you, so nothing to warn on.",
        "Only when missing: Warn at greyed, and says why")
    Equal(tostring(panel.dim:IsVisible()) .. " " .. tostring(panel.dim.usable) .. " | " .. Note(panel.dim), "true false | Not for a buff"
        .. " shown Only when missing: it has no icon while it's on you, so nothing to dim.", "and Dim until Warn at greyed, saying why")
    -- Glow while active under them (no row of its own in the list; seen
    -- working in game, so no longer marked experimental): greyed while
    -- Thorns shows only while it's missing, saying why; then usable, saying
    -- what it does, and kept as ticked. With Only show missing greyed again,
    -- the tick kept.
    Equal(table.concat({ tostring(panel.active:IsVisible()), S[panel.active.text].text, tostring(panel.active:GetChecked()),
        tostring(panel.active.usable) }, " ") .. " | " .. Note(panel.active),
        "true Glow while active false false | Not for a buff shown Only when missing: it has no icon while it's on you,"
        .. " so nothing to glow.", "Glow while active on the Buffs page, greyed with Only when missing, saying why, not marked experimental")
    -- Glow size in the row right under it, shown with it: the label at the
    -- left, the slider from the choices' column, at 100% (the usual size),
    -- greyed while the tick is greyed, saying the tick's reason.
    local function Row(region) return S[region].points[1][2] .. "," .. S[region].points[1][3] end
    local tickY = S[panel.active].points[1][3]
    Equal(table.concat({ tostring(panel.glowSize:IsVisible()), tostring(panel.glowSizeLabel:IsVisible()), S[panel.glowSizeLabel].text,
        S[panel.glowSize.value].text, tostring(panel.glowSize.usable), tostring(S[panel.glowSize].alpha), Row(panel.glowSizeLabel),
        Row(panel.glowSize) }, " ") .. " | " .. Note(panel.glowSize), "true true Glow size 100% false 0.35 16," .. (tickY - 2 - 26)
        .. " 96," .. (tickY + 2 - 26) .. " | Not for a buff shown Only when missing: it has no icon while it's on you, so nothing to glow.",
        "Glow size right under Glow while active, at 100%, greyed with the tick, saying why")
    panel.only:Click()
    local usable = tostring(panel.active.usable) .. " " .. Note(panel.active)
    local unticked = tostring(panel.glowSize.usable) .. " | " .. Note(panel.glowSize)
    -- Greyed, a size picked anyway (the slider can't be dragged then) is
    -- never kept, and the slider shows the kept one again.
    panel.glowSize:Choose(70)
    unticked = unticked .. " | " .. ns.GlowActiveSize() .. " " .. S[panel.glowSize.value].text
    panel.active:Click()
    Equal(usable .. " | " .. tostring(B:GlowsActive("buff", "Thorns")) .. " " .. tostring(panel.active:GetChecked()), "true Its icon glows"
        .. " while the buff is on you, like a proc, so you can't miss it. Best for short procs. | true true",
        "Only when missing unticked: usable, saying what it does; ticked, kept for Thorns")
    Equal(unticked .. " | " .. tostring(panel.glowSize.usable) .. " | " .. Note(panel.glowSize), "false | Tick Glow while active first:"
        .. " this sizes its glow. | 100 100% | true | How big the glow is round every buff that glows while it's up, not just this one:"
        .. " 100% is its usual size.", "Glow size: greyed until the tick is ticked (nothing kept meanwhile), then usable,"
        .. " saying it's every glowing buff's (seen in game, no experimental)")
    Check(panel, "Buffs, three ticks")
    -- Picked: kept in the profile for every glowing buff, shown at once; the
    -- panel still fits at either end.
    panel.glowSize:Choose(50)
    local small = ns.GlowActiveSize() .. " " .. tostring(ns.ProfileLists().glowActiveSize) .. " " .. S[panel.glowSize.value].text
    Check(panel, "Buffs, Glow size 50%")
    panel.glowSize:Choose(150)
    Equal(small .. " | " .. ns.GlowActiveSize() .. " " .. S[panel.glowSize.value].text .. " " .. tostring(S[panel].shown), "50 50 50% | 150 150% true",
        "Glow size 50%, then 150%: kept in the profile, the panel still open")
    Check(panel, "Buffs, Glow size 150%")
    B:SetOption("buff", "onlyMissing", true)
    w:Refresh()
    local greyed = tostring(panel.active.usable) .. " " .. tostring(panel.active:GetChecked()) .. " | " .. Note(panel.active)
        .. " | " .. tostring(panel.glowSize.usable) .. " " .. S[panel.glowSize.value].text
    Check(panel, "Buffs, Only show missing")
    B:SetOption("buff", "onlyMissing", false)
    w:Refresh()
    Equal(greyed, "false true | Not with Only show missing: a buff has no icon while it's on you, so nothing to glow. | false 150%",
        "Only show missing: greyed, saying why, the tick kept; Glow size greyed with it, kept")
    panel.active:Click()
    Equal(tostring(B:GlowsActive("buff", "Thorns")) .. " " .. tostring(panel.glowSize.usable) .. " " .. S[panel.glowSize.value].text,
        "false false 150%", "unticked from the panel: Glow size greyed, still the profile's")
    B:SetGlowActiveSize(100)
    Equal(tostring(ns.ProfileLists().glowActiveSize), "nil", "back at 100%: none kept")
    panel.only:Click()
    panel.only:Click()
    B:SetOption("buff", "showMissing", true)
    w:Refresh()
    Equal(tostring(S[panel.warn].alpha) .. " | " .. Note(panel.warn.buttons[8]), "1 | Its countdown turns red with 10 minutes left, with"
        .. " a red edge round its icon. Out of combat its icon glows too. (experimental)", "unticked, with missing buffs greyed: the"
        .. " edge, and out of combat a glow (your own buffs)")
    -- A hand's weapon enchant: its spot is the addon's own, so no red edge.
    B:SetAura("buff", "hand:main", true)
    w:Refresh()
    bp.icons[2]:Click()
    Equal(S[panel.title].text .. " " .. S[panel.quiet].text .. " | " .. Note(panel.warn.buttons[8]), "MAIN HAND ENCHANT on Buffs | Its"
        .. " countdown turns red with 10 minutes left. Out of combat its icon glows too. (experimental)",
        "Main hand enchant: the countdown and the glow, no edge")
    Equal(tostring(panel.active.usable) .. " | " .. Note(panel.active), "false | Not for a weapon enchant: only a buff's icon can glow"
        .. " while it's up.", "Main hand enchant: Glow while active greyed, saying why")
    Equal(tostring(panel.dim.usable) .. " | " .. Note(panel.dim), "false | Not for a weapon enchant: its spot is the addon's own, not the"
        .. " game's.", "Main hand enchant: Dim until Warn at greyed, saying why")
    Check(panel, "Buffs, Main hand enchant")
    bp.icons[1]:Click()
    B:SetAura("buff", "hand:main", false)
    w:Refresh()
    B:SetOption("buff", "showMissing", false)
    -- Buffs 2 has it too.
    B:AddBar("buff")
    B:SetAura("buff2", "Clearcasting", true)
    w:Select("buff2")
    bp.icons[1]:Click()
    local second = S[panel.title].text .. " " .. S[panel.quiet].text .. " " .. tostring(panel.active:IsVisible()) .. " "
        .. tostring(panel.active.usable) .. " " .. tostring(panel.glowSize:IsVisible())
    Check(panel, "Buffs 2")
    panel.done:Click()
    B:RemoveBar("buff2")
    w:Select("buff")
    bp.icons[1]:Click()
    Equal(second, "CLEARCASTING on Buffs 2 true true true", "Glow while active and its Glow size on the Buffs 2 page too")
    panel.only:Click()
    -- Taken off its bar from the tray: the panel goes with it.
    bp.icons[1].remove:Click()
    Equal(tostring(B:HasAura("buff", "Thorns")) .. " " .. tostring(S[panel].shown), "false false", "its entry taken off: the panel goes")
    -- The window closing, and opened again, put it away.
    bp.icons[1]:Click()
    local said = {}
    w:Select("debuff")
    bp.icons[1]:Click()
    said[1] = tostring(S[panel].shown)
    w:Hide()
    said[2] = tostring(S[panel].shown)
    ns.ShowWindow()
    w:Select("debuff")
    bp.icons[1]:Click()
    ns.ShowWindow()
    said[3] = tostring(S[panel].shown)
    Equal(table.concat(said, " "), "true false false", "the window closing or opened again: the panel goes")
    Equal(table.concat(found, " | "), "", "in every state: every piece inside the panel and none on another, under the title bar, clear of the footer")
    Equal(#printed, 0, "no errors from a spell's own panel")
end)()

-- Block and Colour fade on the Look page -------------------------------------------------------------
-- Block, a fourth pill beside Glass, Split and Outline, and Colour fade, a
-- tick level with the colour past its name, clear of the keybinds' choices:
-- off by default (Glass and flat, today's look), each saying what it does
-- on hover (seen working in game 2026-10-21, so no longer marked
-- experimental; the other designs as before). Each shows at once on the
-- preview's Tracked Bar (slimmer for Block, its fill faded) and the Presets
-- panel's bars; a preset leaves the fade as it is; both stay over a reload.
-- (The page's fit with each design and the fade off and on is checked with
-- the Look page's other choices, above.)

;(function()
    local ns = Start({ useBars = true, notesSeen = "dev", helpSeen = true })
    for _, timer in ipairs(timers) do timer() end
    SlashCmdList.FECM("")
    local w = FECMFrame
    w:Select("look")
    local function Note(control)
        S[control].scripts.OnEnter(control)
        local text = S[w.note].text
        S[control].scripts.OnLeave(control)
        return text
    end
    local design, fade, bar = w.barDesign, w.colourFade, w.preview.Bar
    local labels = {}
    for i, button in ipairs(design.buttons) do labels[i] = S[button.label].text end
    Equal(table.concat(labels, " ") .. " | " .. design.selected .. " | " .. tostring(fade:IsVisible()) .. " " .. tostring(fade:GetChecked())
        .. " " .. S[fade.text].text .. " | " .. ns.Get("barStyle") .. " " .. tostring(ns.Get("colourFade")),
        "Glass Split Outline Block | glass | true false Colour fade | glass false", "four designs, Glass picked; Colour fade there, off")
    local DESIGN = "The design for Blizzard's Tracked Bars, your cast bar and, with its look on, your resource display."
    Equal(Note(design.buttons[1]) .. " | " .. Note(design.buttons[3]) .. " | " .. Note(design.buttons[4]), DESIGN .. " | " .. DESIGN .. " | "
        .. DESIGN .. " Block: slimmer Tracked Bars, each bar in a black edge with a thin warm line inside.",
        "the three designs as before; Block says what it is, no longer marked experimental")
    Equal(Note(fade), "Every bar fades from a deeper shade of its colour into a lighter one, in any design: Tracked Bars, the resource"
        .. " display, your cast bar and Raid Timers.", "Colour fade says what it does, no longer marked experimental")
    local fadeLeft, fadeTop, fadeRight, fadeBottom = Fit.Rect(fade)
    local _, swatchTop, _, swatchBottom = Fit.Rect(w.barColour)
    local _, _, chosenRight = Fit.Rect(w.barChosen)
    local keysLeft, keysTop = Fit.Rect(w.keyPlace)
    Equal(tostring(math.abs((fadeTop + fadeBottom) / 2 - (swatchTop + swatchBottom) / 2) <= 2) .. " " .. tostring(fadeLeft > chosenRight + 8)
        .. " " .. tostring(fadeRight < keysLeft - 8) .. " " .. tostring(math.abs(keysTop - swatchTop) <= 1),
        "true true true true", "level with the colour's swatch, past its name, clear of the keybinds' choices on the same row")

    -- Block: picked, saved, and on the preview at once.
    design.buttons[4]:Click()
    Equal(ns.Get("barStyle") .. " " .. design.selected .. " " .. tostring(S[bar].height) .. " " .. Last(bar.Name, "SetFontObject") .. " "
        .. Last(bar.Duration, "SetFontObject") .. " " .. Last(bar.BarBG, "SetColorTexture", 4),
        "block block 18 FECMFont12 FECMFont13 0.92", "Block picked: the preview's bar slimmer, its text a size smaller, on the warmer track")
    -- Your cast bar too, straight away rather than on its next cast.
    local castRow = ns.CastBar.row
    Equal(tostring(castRow ~= nil) .. " " .. tostring(castRow and castRow.bar.line.shown) .. " " .. tostring(castRow and castRow.fit.design),
        "true true block", "Block picked: your cast bar redrawn at once, its warm line showing")
    -- Colour fade: ticked, saved, the preview's fill faded over its colour.
    local fill = bar:CreateTexture()
    rawset(bar, "GetStatusBarTexture", function() return fill end)
    fade:Click()
    local function Fade(texture)
        local how, from, to = Last(texture, "SetGradient", 1), Last(texture, "SetGradient", 2), Last(texture, "SetGradient", 3)
        if not how then return "flat" end
        return ("%s %.2f %.2f %.2f > %.2f %.2f %.2f"):format(how, from.r, from.g, from.b, to.r, to.g, to.b)
    end
    Equal(tostring(ns.Get("colourFade")) .. " " .. tostring(fade:GetChecked()) .. " | " .. Fade(fill) .. " | "
        .. ("%g"):format(Last(bar, "SetStatusBarColor", 1)), "true true | HORIZONTAL 0.94 0.51 0.12 > 1.00 0.75 0.24 | 1",
        "ticked: saved, and the preview's bar in Orange's own fade, over its flat colour")
    -- The Presets panel's bars show both; a preset leaves the fade as it is.
    w.presets:Click()
    local panel = w.presetsPanel
    local tray = panel.tray or panel.preview
    local health = tray and tray.bars and tray.bars[1]
    local healthFill = health and health:CreateTexture()
    if health then
        rawset(health, "GetStatusBarTexture", function() return healthFill end)
        for _, card in ipairs(panel.cards) do if card.key == "keep" then card:Click() end end
    end
    local warm = 0
    for _, obj in ipairs(objects) do
        if health and S[obj].parent == health and Last(obj, "SetColorTexture", 4) == .35 and obj:IsVisible() then warm = warm + 1 end
    end
    Equal(tostring(health ~= nil) .. " " .. warm .. " " .. Fade(healthFill), "true 4 HORIZONTAL 0.00 0.64 0.00 > 0.40 0.88 0.40",
        "the Presets panel's health bar in Block's warm line, its green faded")
    for _, card in ipairs(panel.cards) do if card.key == "bold" then card:Click() end end
    panel.apply:Click()
    Equal(ns.Get("barStyle") .. " " .. tostring(ns.Get("colourFade")), "glass true", "a preset sets its design, and leaves Colour fade as it is")
    panel.undo:Click()
    panel.done:Click()
    Equal(ns.Get("barStyle") .. " " .. tostring(ns.Get("colourFade")), "block true", "Undo: Block back")
    rawset(bar, "GetStatusBarTexture", nil)
    if health then rawset(health, "GetStatusBarTexture", nil) end
    -- Kept over a reload; anything else saved is ignored.
    local kept = ForeverEnhancedCooldownManagerDB
    ns = Start(kept)
    Equal(ns.Get("barStyle") .. " " .. tostring(ns.Get("colourFade")), "block true", "both kept over a reload")
    kept.barStyle, kept.colourFade = "blocky", "yes"
    ns = Start(kept)
    Equal(ns.Get("barStyle") .. " " .. tostring(ns.Get("colourFade")), "glass false", "odd values saved: back to Glass and flat")
    Equal(#printed, 0, "no errors from Block and Colour fade")
end)()

-- Ticked only on a bar page's spell list -----------------------------------------------------------
-- A player's idea: a tick listing only the spells on this page's bar, so
-- their own ticks are quick to reach. Off by default, quietly experimental;
-- after Show items and Show all ranks on the Cooldowns and Utility pages,
-- beside the search on Buffs and Debuffs (which have neither), clear of
-- them all. Other spells from a search don't show (none is on the bar); a
-- bar with nothing says so.

;(function()
    local ns = Start({ useBars = true, notesSeen = "dev", helpSeen = true, bars = { cd = { spells = { "Moonfire", "Wrath" } } } })
    for _, timer in ipairs(timers) do timer() end
    SlashCmdList.FECM("")
    local w, B = FECMFrame, ns.Bars
    w:Select("cd")
    local bp = w.pages.bar
    local tick = bp.ticked
    local function Note(control) return type(control.hint) == "function" and control.hint(control) or tostring(control.hint) end
    local function Listed()
        local names = {}
        for _, row in ipairs(bp.rows) do
            if row:IsVisible() then names[#names + 1] = row.spell or row.other or ("[" .. tostring(S[row.header].text) .. "]") end
        end
        return table.concat(names, ", ")
    end
    local everything = Listed()
    local p = S[tick].points[1]
    Equal(tostring(tick:IsVisible()) .. " " .. tostring(tick:GetChecked()) .. " " .. S[tick.text].text .. " " .. tostring(p[2] == bp.showRanks)
        .. " " .. p[1] .. " " .. p[3] .. " " .. p[4] .. " | " .. Note(tick) .. " | " .. Fit.Problems(bp),
        "true false Ticked only true LEFT RIGHT 14 | Lists only the spells on this bar, with their own ticks. (experimental) | ",
        "off by default, after Show all ranks, saying what it does, quietly experimental; the page's pieces all clear")
    tick:Click()
    Equal(tostring(ns.Get("listTicked")) .. " " .. tostring(tick:GetChecked()) .. " | " .. Listed(), "true true | [BALANCE], Moonfire, Wrath",
        "ticked: only Moonfire and Wrath, the spells on Cooldowns, under their heading")
    -- A search keeps to them, with no Other spells.
    bp.search:SetText("wra")
    S[bp.search].scripts.OnTextChanged(bp.search)
    Equal(Listed(), "Wrath", "a search: only the ticked ones that match, no Other spells")
    bp.search:SetText("")
    S[bp.search].scripts.OnTextChanged(bp.search)
    -- Beside the search on the Debuffs page; with nothing on the bar, it says so.
    w:Select("debuff")
    p = S[tick].points[1]
    Equal(tostring(tick:IsVisible()) .. " " .. tostring(p[2] == bp.search) .. " " .. Listed() .. " | " .. Fit.Problems(bp),
        "true true [NOTHING ON THIS BAR YET] | ", "on the Debuffs page: beside the search, and a bar with nothing says so")
    B:SetAura("debuff", "Moonfire", true)
    w:Refresh()
    Equal(Listed(), "[BALANCE], Moonfire", "a debuff on the bar: just it")
    w:Select("buff")
    Equal(Fit.Problems(bp), "", "the Buffs page: all clear")
    -- Unticked: everything again.
    w:Select("cd")
    tick:Click()
    Equal(tostring(ns.Get("listTicked")) .. " " .. tostring(Listed() == everything), "false true", "unticked: every spell again")
    B:SetAura("debuff", "Moonfire", false)
    Equal(#printed, 0, "no errors from Ticked only")
end)()

-- Moving a bar by numbers on the Layout page -------------------------------------------------------
-- A player's idea: while your bars are unlocked, in place of the box's drag
-- hint, the bar picked (the one last dragged, or click for the next), its
-- place as x and y from the middle of your screen to type in, and an arrow
-- each way moving it a pixel (ten with Shift). Your own bars only, out of a
-- fight; a bar moved this way leaves its layout, as a dragged one does.

;(function()
    local ns = Start({ useBars = true, notesSeen = "dev", helpSeen = true, bars = { cd = { spells = { "Moonfire", "Wrath" } } } })
    for _, timer in ipairs(timers) do timer() end
    SlashCmdList.FECM("")
    local w, B, L = FECMFrame, ns.Bars, ns.Layout
    w:Select("layout")
    local page = w.pages.layout
    local move = page.move
    local function Note(control) return type(control.hint) == "function" and control.hint(control) or tostring(control.hint) end
    local function Where() return ("%g %g"):format(B:BarPlace(B.moving)) end
    local function Boxes() return tostring(S[move.x].text) .. " " .. tostring(S[move.y].text) end
    Equal(tostring(move:IsVisible()) .. " " .. tostring(page.dragHint:IsVisible()), "false true", "locked: the drag hint, no numbers")
    page.cards[1]:Click()
    B:SetUnlocked(true)
    w:Refresh()
    local start = { B:BarPlace("cd") }
    Equal(tostring(move:IsVisible()) .. " " .. tostring(page.dragHint:IsVisible()) .. " " .. tostring(L:Active()) .. " "
        .. S[move.which.label].text .. " " .. tostring(Boxes() == math.floor(start[1] + .5) .. " " .. math.floor(start[2] + .5))
        .. " | " .. Fit.Problems(page), "true false true Cooldowns true | ",
        "unlocked: the numbers in the drag hint's place, for Cooldowns, where it is in its layout; every piece clear")
    Equal(Note(move.which) .. " | " .. Note(move.x) .. " | " .. Note(move.arrows[1]), "The bar the numbers and arrows move: the one you"
        .. " last dragged. Click for the next. (experimental) | How far the bar is right of the middle of your screen, in pixels (left of"
        .. " it is minus). Type a number, then Enter. | Moves the bar 1 pixel left, or 10 with Shift held. Out of combat only.",
        "each says what it does, quietly experimental")
    -- A pixel right: out of its layout, as a drag would.
    move.arrows[2]:Click()
    local x, y = B:BarPlace("cd")
    Equal(Num(x - math.floor(start[1] + .5)) .. " " .. Num(y - math.floor(start[2] + .5)) .. " " .. tostring(L:Active()) .. " "
        .. tostring(L.moved) .. " " .. Boxes(), "1.00 0.00 false true " .. math.floor(x) .. " " .. math.floor(y),
        "a pixel right, to whole pixels: the bar leaves its layout, and the boxes follow")
    -- Ten up with Shift.
    _G.IsShiftKeyDown = function() return true end
    move.arrows[3]:Click()
    _G.IsShiftKeyDown = nil
    local _, up = B:BarPlace("cd")
    Equal(Num(up - y), "10.00", "Shift: ten up")
    -- Typed in: x, then Enter.
    move.x:SetText("250")
    S[move.x].scripts.OnEnterPressed(move.x)
    x = B:BarPlace("cd")
    Equal(Num(x) .. " " .. Boxes(), "250.00 250 " .. math.floor(up + .5), "250 typed for x: there, y as it was")
    move.y:SetText("lots")
    S[move.y].scripts.OnEnterPressed(move.y)
    Equal(S[w.note].text .. " " .. Where(), "Type a number of pixels, like 120 or -40. 250 " .. ("%g"):format(up),
        "not a number: it says so, nothing moves")
    -- Kept on the screen: all of the bar, whichever point it's held by, so
    -- its numbers say where it really is (the game keeps it on screen).
    S[UIParent].width, S[UIParent].height = 1600, 900
    local cd = B:Get("cd")
    local function Edges()
        local px, py = B:BarPlace("cd")
        local point, width, height = cd.data.point, cd:GetWidth(), cd:GetHeight()
        local cx = px - (point:find("LEFT") and -width / 2 or point:find("RIGHT") and width / 2 or 0)
        local cy = py - (point:find("TOP") and height / 2 or point:find("BOTTOM") and -height / 2 or 0)
        return ("%s %.0f %.0f %.0f %.0f"):format(point, cx - width / 2, cx + width / 2, cy - height / 2, cy + height / 2)
    end
    local function Type(input, value)
        input:SetText(value)
        S[input].scripts.OnEnterPressed(input)
    end
    local function Sides(edges, a, b) local t = { edges:match("^(%S+) (%S+) (%S+) (%S+) (%S+)$") } return t[1] .. " " .. t[a] .. " " .. t[b] end
    local sized = tostring(cd:GetWidth() > 0 and cd:GetHeight() > 0)
    Type(move.y, "-2000")
    Type(move.x, "-5000")
    local low = Sides(Edges(), 2, 4)
    Type(move.y, "2000")
    Type(move.x, "5000")
    local high = Sides(Edges(), 3, 5)
    -- Held by a corner now (growing left: its bottom right, as it wraps up).
    B:SetOption("cd", "grow", "left")
    Type(move.x, "-5000")
    Type(move.y, "-2000")
    local corner = Sides(Edges(), 2, 4)
    B:SetOption("cd", "grow", "centre")
    Equal(sized .. " | " .. low .. " | " .. high .. " | " .. corner, "true | BOTTOM -800 -450 | BOTTOM 800 450 | BOTTOMRIGHT -800 -450",
        "far off the screen: all of the bar kept on it, its edge on the screen's, held by an edge's middle or by a corner")
    S[UIParent].width, S[UIParent].height = nil, nil
    -- The next bar.
    move.which:Click()
    Equal(B.moving .. " " .. S[move.which.label].text, "util Utility", "click: the next bar")
    -- In a fight: nothing moves, and it says why.
    local before = Where()
    lockdown = true
    move.arrows[1]:Click()
    lockdown = false
    Equal(S[w.note].text .. " " .. tostring(Where() == before), "Finish combat first, then move your bars. true", "in a fight: nothing moves")
    -- A bar dragged on screen is the one the numbers move.
    local buff = B:Get("buff")
    S[buff.mover].scripts.OnDragStart(buff.mover)
    S[buff.mover].scripts.OnDragStop(buff.mover)
    Equal(B.moving .. " " .. S[move.which.label].text, "buff Buffs", "a bar dragged: the numbers follow it")
    -- Locked again: the drag hint back.
    B:SetUnlocked(false)
    w:Refresh()
    Equal(tostring(move:IsVisible()) .. " " .. tostring(page.dragHint:IsVisible()), "false true", "locked again: the drag hint back")
    Equal(#printed, 0, "no errors from moving bars by numbers")
end)()

-- Glow for more procs on the Cooldowns and Utility pages -------------------------------------------
-- (A player's report: Nightfall never lit Shadow Bolt.) A tick beside Show
-- the global cooldown, off by default, each bar its own; its note says what
-- it does in two lines of the footer at most (not marked experimental: Squirt's
-- call, 13 Nov 2026). Not on the Buffs or Debuffs pages. Clear of everything else on the page.

;(function()
    local ns = Start({ useBars = true, notesSeen = "dev", helpSeen = true, bars = { cd = { spells = { "Moonfire" } } } })
    for _, timer in ipairs(timers) do timer() end
    SlashCmdList.FECM("")
    local w = FECMFrame
    w:Select("cd")
    local bp = w.pages.bar
    local tick = bp.options.glowProcs
    local function Note(control) return type(control.hint) == "function" and control.hint(control) or tostring(control.hint) end
    local p = S[tick].points[1]
    local note = Note(tick)
    Equal(table.concat({ tostring(tick:IsVisible()), S[tick.text].text, tostring(tick:GetChecked()), p[1], p[2], p[3],
        tostring(ns.BarData("cd").glowProcs), Fit.Problems(bp) }, " "), "true Glow for more procs false TOPLEFT 320 -173 false ",
        "on the Cooldowns page beside Show the global cooldown, off by default, clear of everything else")
    Equal(note .. " " .. tostring(Fit.Wide(note, S[w.note].template) <= 2 * S[w.note].width), "Lights a spell while a proc that empowers"
        .. " it is on you, where the game lights nothing: Shadow Bolt with Nightfall's Shadow Trance. true",
        "its note says what it does in two lines of the footer at most")
    tick:Click()
    local cd = tostring(ns.BarData("cd").glowProcs) .. " " .. tostring(tick:GetChecked())
    w:Select("util")
    local util = tostring(tick:IsVisible()) .. " " .. tostring(tick:GetChecked()) .. " " .. tostring(ns.BarData("util").glowProcs)
    w:Select("buff")
    local buff = tostring(tick:IsVisible()) .. " " .. Fit.Problems(bp)
    w:Select("debuff")
    local debuff = tostring(tick:IsVisible())
    w:Select("cd")
    tick:Click()
    Equal(cd .. " | " .. util .. " | " .. buff .. " | " .. debuff .. " | " .. tostring(ns.BarData("cd").glowProcs) .. " " .. tostring(tick:GetChecked()),
        "true true | true false false | false  | false | false false",
        "ticked: Cooldowns' own, Utility's stays off; not on the Buffs or Debuffs pages; unticked again")
    Equal(#printed, 0, "no errors from Glow for more procs")
end)()

Equal(#printed, 0, "no errors")

print = _G.print
Equal(SecretMisuse[1], nil, "no secret misused anywhere")
io.write("Page help and fit checks passed: " .. checks .. " assertions.\n")
