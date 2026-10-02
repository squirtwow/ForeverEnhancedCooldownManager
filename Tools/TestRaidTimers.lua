-- Run the actual addon files against a mock game for the Raid Timers page:
-- its place in the /fecm window under More, its switches and choices, its
-- previews (the addon's own frames, never Blizzard's code), EraUI's Classic
-- cast bars owning the boss bars, and settings kept over a reload. The mock
-- game is a copy of Tools/TestBars.lua's: Tools/TestMockSync.mjs checks the
-- two match, and with --write copies it across. Tools/TestSkin.lua holds the
-- rules for Blizzard's own countdown, raid warning and boss cast bar frames.
local checks = 0
local function Equal(actual, expected, label)
    checks = checks + 1
    assert(actual == expected, label .. ": expected " .. tostring(expected) .. ", got " .. tostring(actual))
end

-- Mock frames -----------------------------------------------------------------------

local S = setmetatable({}, { __mode = "k" })
local objects = {} -- everything created, newest last
local Proto = {}
local frames = {}

local function New(kind, parent)
    local obj = {}
    S[obj] = { kind = kind, parent = parent, shown = true, last = {}, scripts = {}, events = {}, points = {},
        width = 0, height = 0, alpha = 1 }
    objects[#objects + 1] = obj
    setmetatable(obj, { __index = function(_, key)
        local method = Proto[key]
        if method then return method end
        if type(key) == "string" and key:match("^[A-Z]") then
            return function(self, ...) S[self].last[key] = table.pack(...) end
        end
    end })
    return obj
end

local function Last(obj, method, i) local call = S[obj].last[method]; return call and call[i or 1] end

local watched = setmetatable({}, { __mode = "k" })
local function Toggled(self, v)
    local s = S[self]
    if watched[self] and InCombatLockdown() and s.shown ~= v then s.combatToggle = true end
    local changed = s.shown ~= v
    s.shown = v
    -- Like the game: showing or hiding runs the frame's OnShow or OnHide.
    if changed then
        local script = s.scripts[v and "OnShow" or "OnHide"]
        if script then script(self) end
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
    if type(v) == "boolean" then s.alpha = v and (ifTrue or 1) or (ifFalse or 0) end
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

local function Fire(event, ...)
    for _, f in ipairs(frames) do
        if S[f].events[event] and S[f].scripts.OnEvent then S[f].scripts.OnEvent(f, event, ...) end
    end
end

-- Game environment ------------------------------------------------------------------

local SECRET = setmetatable({}, { __tostring = function() return "secret" end })
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
    _G.GetInventoryItemCount = function(_, slot) assert(slot == 0); return ammoCount end
    _G.GetInventoryItemTexture = function() return 777 end
    _G.GetInventoryItemCooldown = function(_, slot) assert(slot == 13); return trinketCooldown[1], trinketCooldown[2], trinketCooldown[3] end
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
        GetItemCooldown = function() return itemCooldown[1], itemCooldown[2], itemCooldown[3] end,
        GetItemCount = function(id) return itemCount[id] or 0 end,
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
    local duration = { IsActive = function() return active end }
    _G.C_Spell = {
        GetSpellCooldownDuration = function(id, ignoreGCD)
            assert(ignoreGCD == true, "global cooldown must be ignored")
            cooldownCalls[#cooldownCalls + 1] = id
            return duration
        end,
        IsSpellUsable = function(id) if usable[id] == nil then return true, false end return usable[id], noMana[id] end,
        IsSpellInRange = function(id, unit) assert(unit == "target"); return range[id] end,
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
    _G.issecretvalue = function(v) return v == SECRET end
    _G.UnitExists = function() return target end
    _G.UnitCanAttack = function(a, b) assert(a == "player" and b == "target"); return hostile end
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
        if kind == "AuraContainer" then
            assert(template == "CustomAuraContainerTemplate", "secure custom aura container")
            local slots = {}
            S[f].slots = slots
            containers[#containers + 1] = f
            local function Guard() if lockdown then containerCallsInCombat = containerCallsInCombat + 1 end end
            rawset(f, "AddAuraSlot", function(self, key, filter, options)
                Guard()
                local button = New("Button", self)
                local slot = { filter = filter, button = button, enabled = true, supplied = {} }
                for _, method in ipairs({ "SetIcon", "SetDurationCooldown", "SetApplicationCount" }) do
                    rawset(button, method, function(_, object) slot.supplied[method] = object end)
                end
                options.initializeFrame(button)
                slots[key] = slot
                return button
            end)
            rawset(f, "SetAuraSlotEnabled", function(_, key, enabled)
                Guard(); assert(type(enabled) == "boolean"); slots[key].enabled = enabled
            end)
            rawset(f, "SetAuraSlotCandidateFilters", function(_, key, filters)
                Guard(); slots[key].filters = filters
            end)
            rawset(f, "SetUnit", function(_, unit) S[f].unit = unit end)
            rawset(f, "UpdateAllAuras", function() S[f].refreshes = (S[f].refreshes or 0) + 1 end)
            local groups = {}
            S[f].groups = groups
            rawset(f, "AddAuraGroup", function(self, key, filter, options)
                Guard()
                assert(not groups[key], "group added twice")
                local button = New("Button", self)
                local group = { filter = filter, button = button, enabled = true, supplied = {},
                    filters = options.candidateFilters, layout = options.layout, max = options.maxFrameCount }
                for _, method in ipairs({ "SetIcon", "SetDurationCooldown", "SetApplicationCount" }) do
                    rawset(button, method, function(_, object) group.supplied[method] = object end)
                end
                options.initializeFrame(button)
                groups[key] = group
            end)
            rawset(f, "SetAuraGroupEnabled", function(_, key, enabled)
                Guard(); assert(type(enabled) == "boolean"); groups[key].enabled = enabled
            end)
            rawset(f, "SetAuraGroupCandidateFilters", function(_, key, filters) Guard(); groups[key].filters = filters end)
            rawset(f, "SetAuraGroupLayout", function(_, key, layout) Guard(); groups[key].layout = layout end)
            rawset(f, "SetScale", function(_, scale) Guard(); S[f].scale = scale end)
        end
        frames[#frames + 1] = f
        S[f].name = name
        if name then _G[name] = f end
        return f
    end
    _G.UIParent = New("Frame")
    _G.EditModeManagerFrame = New("Frame")
    S[EditModeManagerFrame].shown = false
    S[UIParent].cx, S[UIParent].cy = 500, 400
    _G.GameFontHighlight = { GetFont = function() return "font", 12, "" end }
    _G.CreateFont = function(name) local font = New("Font"); _G[name] = font; return font end
    _G.SlashCmdList = {}
    _G.StaticPopupDialogs = {}
    _G.Settings = nil
    _G.ClearOverrideBindings = function(owner) assert(not lockdown, "binding change in combat"); bindings[owner] = nil end
    _G.SetOverrideBindingClick = function(owner, _, key, button) assert(not lockdown, "binding change in combat"); bindings[owner] = key .. ":" .. button end
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
    for _, file in ipairs({ "Core.lua", "Style.lua", "Skin.lua", "Resource.lua", "CastBar.lua", "Ranks.lua", "Spells.lua", "Keybinds.lua", "Buffs.lua", "Bars.lua",
        "Layout.lua", "Theme.lua", "BarPage.lua", "LayoutPage.lua", "CastBarPage.lua", "ProfileMenu.lua", "Window.lua", "Tour.lua",
        "MinimapButton.lua", "Notes.lua" }) do
        assert(loadfile(file))("ForeverEnhancedCooldownManager", ns)
    end
    Fire("ADDON_LOADED", "ForeverEnhancedCooldownManager")
    if not beforeLogin then
        Fire("PLAYER_LOGIN")
        Fire("PLAYER_ENTERING_WORLD")
    end
    return ns
end

-- Blizzard's raid timer frames ----------------------------------------------------------
-- Stand-ins for Blizzard's countdown, raid warnings and boss cast bars. The
-- sealed rules for them are in TestSkin.lua; here they only make sure the
-- window and its previews never run Blizzard's own code.

local blizzardCalling = false
-- A global function by its name, or a table's; the hook is the addon's own code.
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
local FLAT = "Interface\\Buttons\\WHITE8X8"
local function BlizzardFrames()
    _G.TimerTracker = New("Frame")
    rawset(TimerTracker, "timerList", {})
    _G.TimerTracker_StartTimerOfType = function() assert(blizzardCalling, "the addon ran Blizzard's countdown") end
    _G.RaidWarningFrame = New("Frame")
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
-- EraUI installed, its Classic cast bars on or off.
local function EraUI(castBars)
    _G.C_AddOns = { IsAddOnLoaded = function(name) return name == "EraUI" end }
    _G.EraUI = { GetSetting = function(_, key)
        if key == "enabled" then return true end
        if key == "castBars" then return castBars end
    end }
end

local function LoadAll(saved, files)
    local ns = {}
    _G.ForeverEnhancedCooldownManagerDB = saved
    for _, file in ipairs(files or { "Core.lua", "Style.lua", "Skin.lua", "Resource.lua", "CastBar.lua", "RaidTimers.lua",
        "Ranks.lua", "Spells.lua", "Keybinds.lua", "Buffs.lua", "Bars.lua", "Layout.lua", "Theme.lua", "BarPage.lua",
        "LayoutPage.lua", "CastBarPage.lua", "RaidTimersPage.lua", "ProfileMenu.lua", "Window.lua", "Tour.lua",
        "MinimapButton.lua", "Notes.lua" }) do
        assert(loadfile(file))("ForeverEnhancedCooldownManager", ns)
    end
    Fire("ADDON_LOADED", "ForeverEnhancedCooldownManager")
    Fire("PLAYER_LOGIN")
    Fire("PLAYER_ENTERING_WORLD")
    return ns
end

local function Colour(obj)
    local r, g, b, a = Last(obj, "SetStatusBarColor", 1), Last(obj, "SetStatusBarColor", 2), Last(obj, "SetStatusBarColor", 3),
        Last(obj, "SetStatusBarColor", 4)
    return string.format("%g,%g,%g,%g", r, g, b, a or 1)
end

-- The window: Raid Timers under More ------------------------------------------------------

Environment()
BlizzardFrames()
local ns = LoadAll(nil)
ns.ShowWindow()
local w = FECMFrame
Equal(w.nav.raid ~= nil and S[w.nav.raid.label].text, "Raid Timers", "Raid Timers in the window's list")
Equal(S[w.moreHeading].text, "MORE", "under a heading of its own, More, like Your bars")
local function Top(item) return -S[item].points[1][3] end
Equal(Top(w.nav.general) .. " " .. Top(w.nav.raid), "328 390", "below General, the rest of the list where it was")
local news = S[w.news].points[1]
Equal(Top(w.nav.raid) + S[w.nav.raid].height <= 489 - news[3] - S[w.news].height, true,
    "clear of the What's new button at the foot of the list")
Equal(type(w.nav.raid.hint) == "string" and w.nav.raid.hint:find("countdown", 1, true) ~= nil, true, "it says what it's for on hover")
w.nav.raid:Click()
local page = w.pages.raid
Equal(tostring(S[page].shown) .. " " .. tostring(S[w.pages.look].shown) .. " " .. tostring(S[w.nav.raid.fill].shown),
    "true false true", "clicked: its page, and it's the one highlighted")

-- Everything off at first, each part saying it needs testing.
Equal(tostring(ns.Get("pullTimer")) .. " " .. tostring(ns.Get("raidWarnings")) .. " " .. tostring(ns.Get("bossCasts")),
    "false false false", "every part off by default")
for _, tick in ipairs({ page.pullTick, page.warningTick, page.bossTick }) do
    Equal(tick.checked == false and S[tick.text].text:find("(Needs testing)", 1, true) ~= nil, true,
        S[tick.text].text .. ": unticked, labelled as needing testing")
end
Equal(S[page.status].text:find("Tick one", 1, true) ~= nil, true, "the title row says how to start")
Equal(S[page.pull].alpha .. " " .. S[page.warnings].alpha .. " " .. S[page.boss].alpha, "0.35 0.35 0.35",
    "the previews dimmed while their parts are off")
Equal(TimerTracker_StartTimerOfType ~= nil and rawget(RaidWarningFrame, "AddMessage") ~= nil, true, "Blizzard's own functions in place")
local plainStart, plainSay = TimerTracker_StartTimerOfType, rawget(RaidWarningFrame, "AddMessage")
local plainFill = rawget(Boss1TargetFrameSpellBar, "UpdateBarFillTexture")

-- The previews: the addon's own frames, dressed like Blizzard's would be.
local pull, warnings, boss = page.pull, page.warnings, page.boss
Equal(pull ~= TimerTracker and pull.bar ~= nil and S[pull].parent == page.tray, true, "the countdown preview is the addon's own frame")
Equal(Last(pull.bar, "SetStatusBarTexture") .. " " .. Colour(pull.bar), FLAT .. " 1,0,0,1",
    "a countdown bar in your texture, in Blizzard's red")
Equal(S[pull.bar.timeText].template .. " " .. Last(pull.bar.timeText, "SetFontObject"), "GameFontHighlight FECMFont12",
    "its time in your font")
Equal(S[pull.digit1].texture .. " " .. tostring(S[pull.digit1].desaturated), "Interface\\Timer\\BigTimerNumbers false",
    "a big number from Blizzard's own sheet, in its gold")
local line1, line2 = warnings.lines[1], warnings.lines[2]
Equal(S[line1].text .. " / " .. S[line2].text, "Raid warning / Boss emote", "a raid warning and a boss emote")
Equal(Last(line1, "SetFont", 1) .. " " .. Last(line1, "SetFont", 2) .. " " .. Last(line1, "SetFont", 3),
    "Fonts\\FRIZQT__.TTF 20 OUTLINE", "in Friz Quadrata, outlined, as big as Blizzard's at rest")
Equal(string.format("%g,%g,%g", S[line1].colour[1], S[line1].colour[2], S[line1].colour[3]), "1,0.282,0",
    "each in Blizzard's colour for it")
Equal(S[boss.bar.Border].alpha .. " " .. S[boss.bar.Background].alpha .. " " .. Colour(boss.bar),
    "0 0 1,0.7,0,1", "a boss cast bar without Blizzard's modern frame, gold")
Equal(Last(boss.bar.Text, "SetFontObject") .. " " .. S[boss.bar.Text].text, "FECMFont10 Frostbolt Volley", "the spell's name in your font")

-- Ticking each part on.
page.pullTick:Click()
Equal(tostring(ns.Get("pullTimer")) .. " " .. S[pull].alpha, "true 1", "the countdown on: saved, its preview in full")
Equal(TimerTracker_StartTimerOfType ~= plainStart, true, "and Blizzard's countdown hooked from now on")
Equal(S[page.status].text, "Your look on 1 of 3. The previews show your choices.", "the title row counts the parts on")
page.warningTick:Click()
page.bossTick:Click()
Equal(tostring(rawget(RaidWarningFrame, "AddMessage") ~= plainSay) .. " " .. tostring(rawget(Boss1TargetFrameSpellBar, "UpdateBarFillTexture") ~= plainFill)
    .. " " .. S[page.warnings].alpha .. " " .. S[page.boss].alpha, "true true 1 1", "raid warnings and boss casts on and hooked")
Equal(S[Boss1TargetFrameSpellBar.Border].alpha .. " " .. Last(Boss5TargetFrameSpellBar.Text, "SetFontObject"), "0 FECMFont10",
    "Blizzard's boss bars restyled at once")
Equal(S[page.status].text, "Your look on 3 of 3. The previews show your choices.", "all three")

-- Colours: click one, click it again for Blizzard's own.
local blue = page.pullColours.swatches[3]
Equal(blue.key, "blue", "the countdown's colours are the bar colours")
blue:Click()
Equal(ns.Get("pullColour") .. " " .. S[page.pullColours.chosen].text .. " " .. Colour(pull.bar), "blue Blue 0.24,0.55,0.88,1",
    "a colour for the countdown bar, on the preview at once")
blue:Click()
Equal(ns.Get("pullColour") .. " " .. S[page.pullColours.chosen].text .. " " .. Colour(pull.bar), "default Blizzard's red 1,0,0,1",
    "clicked again: Blizzard's red")
-- The big numbers.
page.numbers.buttons[3]:Click()
Equal(ns.Get("pullNumbers") .. " " .. tostring(S[pull.digit1].desaturated) .. " " .. table.concat(S[pull.digit1].tint, ","),
    "bar true 1,0,0", "numbers in the bar's colour: made grey, then tinted red")
page.numbers.buttons[2]:Click()
Equal(ns.Get("pullNumbers") .. " " .. table.concat(S[pull.digit1].tint, ","), "white 1,1,1", "white")
Equal(page.numbers.selected, "white", "the choice highlighted")

-- Raid warnings: font, outline, shadow and each kind's colour.
Equal(S[page.font.buttons[4].label].text .. " " .. Last(page.font.buttons[4].label, "SetFontObject"), "Skurri FECMSampleskurri",
    "each font by its name, in its own face")
page.font.buttons[4]:Click()
page.outline.buttons[3]:Click()
page.shadow:Click()
Equal(ns.Get("warningFont") .. " " .. ns.Get("warningOutline") .. " " .. tostring(ns.Get("warningShadow")), "skurri thick false",
    "font, outline and shadow saved")
Equal(Last(line2, "SetFont", 1) .. " " .. Last(line2, "SetFont", 3) .. " " .. Last(line2, "SetShadowOffset", 1),
    "Fonts\\skurri.ttf THICKOUTLINE 0", "and on the preview")
local purple = page.emoteColours.swatches[5]
Equal(purple.key .. " " .. page.emoteColours.swatches[6].key, "purple class", "text colours, your class colour last")
purple:Click()
Equal(string.format("%g,%g,%g", S[line2].colour[1], S[line2].colour[2], S[line2].colour[3]) .. " "
    .. string.format("%g", S[line1].colour[3]) .. " " .. S[page.emoteColours.chosen].text .. " " .. S[page.warningColours.chosen].text,
    "0.72,0.52,1 0 Purple Blizzard's", "boss emotes purple, raid warnings still Blizzard's")
page.warningColours.swatches[1]:Click()
Equal(string.format("%g,%g,%g", S[line1].colour[1], S[line1].colour[2], S[line1].colour[3]), "1,1,1", "raid warnings white")
page.warningColours.swatches[1]:Click()
Equal(string.format("%g,%g,%g", S[line1].colour[1], S[line1].colour[2], S[line1].colour[3]), "1,0.282,0",
    "clicked again: Blizzard's colour back on the preview")

-- Boss cast bars: a colour, and the note on secret casts.
page.bossColours.swatches[4]:Click()
Equal(ns.Get("bossColour") .. " " .. Colour(boss.bar), "green 0.38,0.74,0.3,1", "a colour for boss casts")
Equal(S[page.bossNote].text:find("secret", 1, true) ~= nil, true, "the note says what the game keeps secret")

-- Every control says what it does on hover.
local controls = { page.pullTick, page.warningTick, page.bossTick, page.shadow }
for _, group in ipairs({ page.numbers, page.font, page.outline }) do
    for _, button in ipairs(group.buttons) do controls[#controls + 1] = button end
end
for _, row in ipairs({ page.pullColours, page.bossColours, page.warningColours, page.emoteColours }) do
    for _, swatch in ipairs(row.swatches) do controls[#controls + 1] = swatch end
end
local quiet = 0
for _, control in ipairs(controls) do
    if type(control.hint) ~= "string" or control.hint == "" or control.hint:find("\226\128\148", 1, true) then quiet = quiet + 1 end
end
Equal(#controls .. " " .. quiet, "38 0", "every tick, choice and colour has a note, none with an em dash")
local help = {}
for _, line in ipairs(page.help) do help[#help + 1] = S[line].text end
help = table.concat(help, "\n")
Equal(help:find("/countdown", 1, true) ~= nil and help:find("/rw", 1, true) ~= nil and help:find("Edit Mode", 1, true) ~= nil, true,
    "how to see each part in the game")
Equal(help:find("aren't in WoW Forever yet", 1, true) ~= nil and help:find("\226\128\148", 1, true) == nil, true,
    "and that Blizzard's boss timeline isn't in WoW Forever yet; no em dashes")

-- The previews animate on their own, never through Blizzard's code.
local tick = S[page.tray].scripts.OnUpdate
tick(page.tray, 1.5)
Equal(Last(pull.bar.timeText, "SetFormattedText", 2) .. " " .. string.format("%.3f", Last(pull.bar, "SetValue")), "41 0.875",
    "the countdown preview runs down")
local left, right, top = Last(pull.digit1, "SetTexCoord", 1), Last(pull.digit1, "SetTexCoord", 2), Last(pull.digit1, "SetTexCoord", 3)
Equal(string.format("%.4f %.4f %.4f", left, right, top), "0.0000 0.2500 0.3320", "its number counts down: 4, from Blizzard's sheet")
Equal(string.format("%.1f", Last(boss.bar, "SetValue")), "0.6", "the boss cast fills")
tick(page.tray, 2)
Equal(string.format("%g", Last(pull.digit1, "SetTexCoord", 1)), "0.5", "then 2")

-- In a fight, choices still change: looks only.
lockdown = true
page.outline.buttons[1]:Click()
Equal(ns.Get("warningOutline") .. " " .. Last(line1, "SetFont", 3), "none ", "changed in a fight, as looks only")
lockdown = false
Equal(#printed, 0, "no errors on the page")

-- Kept over a reload; anything invalid reads as the default.
local saved = ForeverEnhancedCooldownManagerDB
Environment(true)
BlizzardFrames()
ns = LoadAll(saved)
Equal(tostring(ns.Get("pullTimer")) .. " " .. ns.Get("pullNumbers") .. " " .. ns.Get("warningFont") .. " " .. ns.Get("emoteColour")
    .. " " .. ns.Get("bossColour"), "true white skurri purple green", "choices kept over a reload")
Equal(S[Boss2TargetFrameSpellBar.Border].alpha, 0, "and Blizzard's boss bars restyled again after it")
saved.pullNumbers, saved.warningOutline, saved.emoteColour, saved.bossColour = "pink", 3, "charcoal", "white"
Equal(ns.Get("pullNumbers") .. " " .. ns.Get("warningOutline") .. " " .. ns.Get("emoteColour") .. " " .. ns.Get("bossColour"),
    "gold outline default default", "anything else is ignored: text colours and bar colours stay apart")

-- EraUI's Classic cast bars on: the boss bars are EraUI's, and the page says so.
Environment()
BlizzardFrames()
EraUI(true)
plainFill = rawget(Boss1TargetFrameSpellBar, "UpdateBarFillTexture")
ns = LoadAll({ bossCasts = true })
ns.ShowWindow()
FECMFrame:Select("raid")
page = FECMFrame.pages.raid
Equal(tostring(page.bossTick.checked) .. " " .. S[page.boss].alpha .. " " .. S[Boss1TargetFrameSpellBar.Border].alpha .. " "
    .. tostring(rawget(Boss1TargetFrameSpellBar, "UpdateBarFillTexture") == plainFill),
    "true 0.35 1 true", "ticked, but EraUI's: Blizzard's boss bars untouched and unhooked, the preview dimmed")
Equal(S[page.bossNote].text:find("EraUI's Cast Bars", 1, true) ~= nil and S[page.bossNote].colour[1], 1,
    "and the note says why, in the warning colour")
Equal(S[page.bossNote].text:find("or for a newer EraUI", 1, true) ~= nil, true, "and that a newer EraUI hands them over")
Equal(S[page.status].text, "Blizzard's countdown, raid warnings and boss casts, in your look. Tick one to start.",
    "none of the three showing your look")
-- Off in EraUI: the addon's.
Environment()
BlizzardFrames()
EraUI(false)
ns = LoadAll({ bossCasts = true })
Equal(S[Boss1TargetFrameSpellBar.Border].alpha, 0, "EraUI's Cast Bars off: the addon restyles them")

-- A current EraUI, its Cast Bars on: it shares the boss bars at its login,
-- so the switch decides, live, and the page says the bars take your look
-- instead of EraUI's.
local function SharingEraUI()
    EraUI(true)
    local heard = {}
    local watch = CreateFrame("Frame")
    watch:RegisterEvent("PLAYER_LOGIN")
    watch:SetScript("OnEvent", function()
        ForeverEnhancedCooldownManagerAPI.ShareBossCastBars("EraUI", function()
            heard[#heard + 1] = ForeverEnhancedCooldownManagerAPI.StylesBossCastBars()
        end)
    end)
    return heard
end
Environment()
BlizzardFrames()
local heard = SharingEraUI()
ns = LoadAll({ bossCasts = false })
ns.ShowWindow()
FECMFrame:Select("raid")
page = FECMFrame.pages.raid
Equal(S[page.bossNote].text, "While this is on, they take your look instead of EraUI's. In a fight the game keeps each cast secret, so the bar keeps one colour.",
    "a sharing EraUI: the note says the boss bars take your look instead of EraUI's")
Equal(S[page.bossNote].colour[1] .. " " .. S[page.boss].alpha .. " " .. S[Boss1TargetFrameSpellBar.Border].alpha .. " " .. #heard,
    string.format("%g", ns.Theme.MUTED[1]) .. " 0.35 1 0", "not a warning; off: the preview dimmed, Blizzard's bars and EraUI left alone")
page.bossTick:Click()
Equal(S[page.boss].alpha .. " " .. S[Boss1TargetFrameSpellBar.Border].alpha .. " " .. Last(Boss3TargetFrameSpellBar.Text, "SetFontObject")
    .. " " .. #heard .. " " .. tostring(heard[1]), "1 0 FECMFont10 1 true",
    "ticked with EraUI's Cast Bars on: the boss bars in your look at once, EraUI told first")
Equal(S[page.status].text, "Your look on 1 of 3. The previews show your choices.", "counted as showing your look")
page.bossTick:Click()
Equal(S[page.boss].alpha .. " " .. S[Boss1TargetFrameSpellBar.Border].alpha .. " " .. #heard .. " " .. tostring(heard[2]),
    "0.35 1 2 false", "unticked: Blizzard's look back and handed to EraUI at once, no reload")
Equal(S[page.bossNote].text:find("\226\128\148", 1, true), nil, "no em dash in the note")
Equal(#printed, 0, "no errors")

-- Before a full restart the new files aren't loaded: no More heading, no page.
Environment()
BlizzardFrames()
ns = LoadAll(nil, { "Core.lua", "Style.lua", "Skin.lua", "Resource.lua", "CastBar.lua", "Ranks.lua", "Spells.lua",
    "Keybinds.lua", "Buffs.lua", "Bars.lua", "Layout.lua", "Theme.lua", "BarPage.lua", "LayoutPage.lua", "CastBarPage.lua",
    "ProfileMenu.lua", "Window.lua", "Tour.lua", "MinimapButton.lua", "Notes.lua" })
ns.ShowWindow()
Equal(tostring(FECMFrame.nav.raid) .. " " .. tostring(FECMFrame.moreHeading) .. " " .. tostring(FECMFrame.pages.raid), "nil nil nil",
    "without the new files: the list as before")
Equal(#printed, 0, "no errors")

print = _G.print
io.write("Raid Timers checks passed: " .. checks .. " assertions.\n")
