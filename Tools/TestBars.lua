-- Run the actual bars files (Core, Style, Spells, Buffs, Bars, the window) against a
-- mock game: spellbook ranks, secret cooldowns in combat, usable and range
-- tints, showing and hiding, dragging, the settings backup, and the panel.
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
function Proto:UnregisterAllEvents() S[self].events = {} end
function Proto:CreateTexture() return New("Texture", self) end
function Proto:CreateFontString() return New("FontString", self) end
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
function Proto:GetFont() return "font", 12, "" end
function Proto:Click() S[self].scripts.OnClick(self) end
function Proto:SetTexture(t) S[self].texture = t end
function Proto:SetVertexColor(r, g, b) S[self].tint = { r, g, b } end
function Proto:SetDesaturated(v) S[self].desaturated = v end
function Proto:SetAlphaFromBoolean(v) S[self].alphaFrom = v end
function Proto:IsMouseOver() return S[self].mouseOver == true end

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
local bindings, cvarOn, reloads, timers
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
    _G.GetCursorPosition = function() return 0, 0 end
    _G.ReloadUI = function()
        assert(not lockdown, "blocked ReloadUI in combat")
        assert(S[FECMFrame].shown, "window hidden before reload")
        reloads = reloads + 1
    end
    _G.RAID_CLASS_COLORS = { DRUID = { r = 1, g = .49, b = .04 } }
    trinket, trinketCooldown, bagItems, itemCooldown, itemCount = nil, { 0, 0, 1 }, {}, { 0, 0, 1 }, {}
    _G.GetInventoryItemID = function(_, slot) return slot == 13 and trinket or nil end
    _G.GetInventoryItemLink = function() return "|cff1eff00|Hitem:" .. tostring(trinket) .. "|h[Lucky Charm]|h|r" end
    _G.GetInventoryItemTexture = function() return 777 end
    _G.GetInventoryItemCooldown = function(_, slot) assert(slot == 13); return trinketCooldown[1], trinketCooldown[2], trinketCooldown[3] end
    _G.C_Container = {
        GetContainerNumSlots = function(bag) return bag == 0 and #bagItems or 0 end,
        GetContainerItemInfo = function(bag, slot) return bagItems[slot] end,
    }
    _G.C_Item = {
        GetItemSpell = function(id) return ({ [118] = "Healing Potion", [117] = "Food", [2698] = "Learning" })[id] end,
        GetItemInfoInstant = function(id)
            local class = ({ [118] = { 0, 1 }, [117] = { 0, 5 }, [2698] = { 9, 0 } })[id] or { 15, 0 }
            return id, nil, nil, nil, nil, class[1], class[2]
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
        GetCVarBool = function() return cvarOn end,
        GetCVar = function(name) return cvars[name] end,
        RegisterCVar = function(name, default) if cvars[name] == nil then cvars[name] = default end end,
        SetCVar = function(name, value) cvars[name] = value end,
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
    S[UIParent].cx, S[UIParent].cy = 500, 400
    _G.GameFontHighlight = { GetFont = function() return "font", 12, "" end }
    _G.CreateFont = function(name) local font = New("Font"); _G[name] = font; return font end
    _G.SlashCmdList = {}
    _G.Settings = nil
    _G.ClearOverrideBindings = function(owner) assert(not lockdown, "binding change in combat"); bindings[owner] = nil end
    _G.SetOverrideBindingClick = function(owner, _, key, button) assert(not lockdown, "binding change in combat"); bindings[owner] = key .. ":" .. button end
end

local function Load(saved, beforeLogin)
    local ns = {}
    _G.ForeverEnhancedCooldownManagerDB = saved
    for _, file in ipairs({ "Core.lua", "Style.lua", "Ranks.lua", "Spells.lua", "Buffs.lua", "Bars.lua", "Theme.lua", "BarPage.lua", "ProfileMenu.lua", "Window.lua" }) do
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
local list = ns.Spells:List()
Equal(#list, 8, "Attack, Walk on Air, Moonfire, Wrath, Thorns, Overpower and two druid procs; passive and future spells left out")
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
Equal(list[#list].name, "Nature's Grace", "procs come last")

-- Off by default ------------------------------------------------------------------------

Equal(B:Enabled(), false, "own bars start off")
Equal(B:Get("cd") and S[B:Get("cd")].shown, false, "no bar shown while off")

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
Equal(S[moon].alpha, 1, "shown while not hiding ready icons")
B:SetOption("cd", "hideReady", true)
moon = cd.icons[2]
Equal(S[moon].alphaFrom, SECRET, "hide when ready also uses the secret state as it is")
B:SetOption("cd", "hideReady", false)
active = false

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
Equal(S[over.glow].shown, true, "reactive ability ready: gold edge")
Equal(S[moon.glow].shown, false, "normal spells never get the gold edge")
usable[7384] = false
B:RefreshAll()
Equal(S[over.glow].shown, false, "gold edge goes when it isn't usable")
usable[7384] = SECRET
B:RefreshAll()
Equal(S[over.glow].shown, false, "a hidden usable answer is never read")
usable[7384] = nil
Equal(#printed, 0, "no errors")

-- Combat-only bars and moving -----------------------------------------------------------

B:SetOption("cd", "combatOnly", true)
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
Equal(ns.BarData("cd").y, -100, "position saved")
p = S[cd].points[1]
Equal(p[1] == "CENTER" and p[4] == 20 and p[5], -100, "placed where it was dropped")
B:SetOption("cd", "combatOnly", false)
ns.Set("useBars", false)
B:Rebuild()
Equal(B:IsUnlocked(), false, "turning the bars off locks them")
Equal(S[cd].shown, false, "and hides them")
ns.Set("useBars", true)
B:Rebuild()

-- A new rank moves the bar onto it ------------------------------------------------------

Book(true)
Fire("SPELLS_CHANGED")
Equal(cd.icons[2].spellID, 8925, "trained rank 3: the bar uses it")
Equal(ns.BarData("cd").spells[2], "Moonfire", "saved setup unchanged")

-- Backup ------------------------------------------------------------------------------

Equal(cvars.FECMBackup, "accent=orange;listItems=0;listRanks=0;skin=1;useBars=1", "on/off backup")
Equal(cvars.FECMBackupBars0, "1", "bars backed up in one chunk")
Environment(true)
ns = Load(nil)
B = ns.Bars
Equal(B:Enabled(), true, "bars on again after lost settings")
Equal(table.concat(ns.BarData("cd").spells, ","), "Overpower,Moonfire", "bar spells restored")
Equal(ns.BarData("cd").x, 20, "bar position restored")
Equal(ns.BarData("util").x, nil, "unmoved bar keeps its default spot")
Equal(B:Get("cd").count, 2, "and drawn")

Environment(true)
cvars.FECMBackupBars1 = "cd.size=9999;cd.spells=A|B;cd.x=nope;evil.size=3;cd.hide=maybe"
ns = Load(nil)
local data = ns.BarData("cd")
Equal(data.size, 64, "bad sizes clamped")
Equal(table.concat(data.spells, ","), "A,B", "names read as plain text")
Equal(data.x, nil, "bad positions dropped")
Equal(data.hideReady, false, "bad flags off")
Equal(ns.BarData("evil"), nil, "unknown bars ignored")

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
Equal(S[buffs].shown, false, "an empty Buffs bar stays hidden")
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
Equal(B:SetBuff("Thorns", true), true, "Thorns ticked")
local g1 = groups.g1
Equal(g1 ~= nil and g1.enabled, true, "its group switched on")
Equal(g1.filter, "HELPFUL", "helpful auras only")
Equal(g1.max, 1, "one icon per group")
Equal(g1.filters.includeSpellIDs[467] and g1.filters.includeSpellIDs[9910], true, "any rank of Thorns")
Equal(g1.layout.layoutIndex, 1, "first in line")
Equal(S[g1.button].width == 36 and S[g1.button].height, 36, "group icons drawn at the base size")
Equal(g1.supplied.SetIcon ~= nil and g1.supplied.SetDurationCooldown ~= nil, true, "with icon and sweep")
Equal(slots.b1.enabled, false, "fixed slots stay off")
Equal(S[buffs].shown, true, "the bar shows")
B:SetBuff("Clearcasting", true)
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
Equal(B:HasBuff("Thorns"), true, "a spell can be on a cooldown bar and the Buffs bar")
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
B:SetBuff("Clearcasting", false)
Equal(containerCallsInCombat, 0, "no slot or group changes in combat")
Equal(slots.b2.enabled, true, "Clearcasting's slot waits")
B:SetOption("buff", "combatOnly", true)
Equal(S[buffs].alpha, 1, "only in combat: visible in a fight")
ns.Set("useBars", false)
B:Rebuild()
Equal(S[buffs].combatToggle, nil, "never shown or hidden in combat")
Equal(S[buffs].shown, true, "hiding waits for the fight to end")
lockdown = false
Fire("PLAYER_REGEN_ENABLED")
Equal(S[buffs].shown, false, "hidden after the fight")
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
local text = cvars.FECMBackupBars1
Equal(text:find("12:buff.missing1:0", 1, true) ~= nil and text:find("10:buff.timer1:1", 1, true) ~= nil, true, "Buffs bar options backed up")
Equal(text:find("7:p1.buff6:Thorns", 1, true) ~= nil, true, "and its list, in your profile")
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
Equal(S[debuffs].shown, true, "the bar shows")
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
Environment(true)
ns = Load(nil)
B = ns.Bars
Equal(Shape("buff"), "Thorns, Walk on Air+Nature's Grace+Clearcasting", "joins come back from the backup")
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
Equal(#printed, 1, "only the restored-settings notice was printed")

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
Equal(S[charmIcon.texture].desaturated, false, "ungreys when the cooldown finishes")
Equal(S[potion.count].text, 3, "potion count shown")
itemCount[118] = 0
B:RefreshAll()
Equal(S[potion.texture].desaturated, true, "greyed when you've run out")
trinketCooldown = { SECRET, SECRET, 1 }
B:RefreshAll()
Equal(S[charmIcon.texture].desaturated, false, "a hidden item cooldown leaves the icon as it was")
trinketCooldown = { 0, 0, 1 }
B:SetOption("cd", "hideReady", true)
Equal(S[cdBar.icons[1]].alpha, 0, "ready trinket hidden when asked")
B:SetOption("cd", "hideReady", false)

B:Assign("Moonfire", "util")
local moonIcon = B:Get("util").icons[1]
active = true
B:RefreshAll()
Equal(S[moonIcon.texture].desaturated, true, "spell greyed on cooldown")
active = false
S[moonIcon.cooldown].scripts.OnCooldownDone()
Equal(S[moonIcon.texture].desaturated, false, "and ungreyed right when its cooldown ends")

B:SetOption("cd", "showNames", true)
Equal(S[cdBar.icons[1].label].shown, true, "names shown when asked")
Equal(S[cdBar.icons[1].label].text, "Lucky Charm", "trinkets named by the item")
B:SetOption("cd", "showNames", false)
Equal(S[cdBar.icons[1].label].shown, false, "names off by default")

Equal(Last(cdBar.icons[1].cooldown, "SetHideCountdownNumbers"), false, "countdown numbers on by default")
B:SetOption("cd", "showTimer", false)
Equal(Last(cdBar.icons[1].cooldown, "SetHideCountdownNumbers"), true, "and off when asked")
Equal(cvars.FECMBackupBars1:find("8:cd.timer1:0", 1, true) ~= nil, true, "that choice backed up")
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
Equal(cvars.FECMBackup, "accent=orange;listItems=1;listRanks=0;skin=1;useBars=1", "and backed up")

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
Search("")
Equal(Row("Thorns") ~= nil, true, "clearing the search lists everything again")
Equal(#printed, 0, "no errors")

Environment(true)
ns = Load(nil)
Equal(ns.CustomSpells()["Power Word: Fortitude"][1], 1243, "added spells restored from the backup")
Equal(ns.BarData("buff").spells[1], "Power Word: Fortitude", "with their bar")
Equal(ns.Spells:Find("item:118").name, "Minor Healing Potion", "items on a bar stay listed when your bags run out")
ns.Bars:SetBuff("Power Word: Fortitude", false)
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
Fire("SPELLS_CHANGED")
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
Environment(true)
ns = Load(nil)
Equal(table.concat(ns.BarData("util").spells, ","), "Moonfire,Moonfire@2", "fixed ranks restored from the backup")

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

-- Sharing: renaming follows every character; deleting a shared one is refused.
ns.UseProfile(mine)
Equal(ns.ProfileUsers(mine), 2, "two characters can share a profile")
ok, message = ns.RenameProfile("Balance")
Equal(ok and saved.chars["Player-1-0001"], "Balance", "renaming updates every character using it")
Equal(saved.profiles[mine], nil, "the old name is gone")
Equal(select(2, ns.DeleteProfile("Balance")), "Another character uses Balance, so it can't be deleted.", "a profile another character uses can't be deleted")
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
B:SetBuff("Power Word: Fortitude", true)
ns.UseProfile(mine .. " 2")
ns.PruneCustom()
Equal(ns.CustomSpells()["Power Word: Fortitude"] ~= nil, true, "an added spell in another profile is remembered")

-- The backup keeps profiles, and a lost settings file is noticed ------------------------

character = { guid = "Player-1-0001", name = "Zriel", realm = "Zephras" }
Environment(true)
ns = Load(nil) -- the game lost the settings file
Equal(ns.ProfileName(), "Balance", "profile restored for this character")
Equal(ns.BarData("buff").spells[1], "Power Word: Fortitude", "with its lists")
Equal(ns.CustomSpells()["Power Word: Fortitude"][1], 1243, "and added spells")
Equal(ForeverEnhancedCooldownManagerDB.chars["Player-1-0002"], mine .. " 2", "who uses what, too")
Equal(ns.restored, true, "the loss is noticed")
Equal(printed[#printed], "|cffffd100Forever Enhanced Cooldown Manager:|r " .. ns.RESTORED_TEXT, "and you're told at login")

-- A settings file older than the backup means the last session wasn't kept.
saved = ForeverEnhancedCooldownManagerDB
local stale = {}
for key, value in pairs(saved) do stale[key] = value end
stale.session = saved.session - 1
stale.accent = "green"
Environment(true)
ns = Load(stale)
Equal(ns.restored, true, "an older settings file is noticed")
Equal(ns.Get("accent"), "orange", "and the newer backup is used")

-- A normal reload keeps the file and says nothing.
saved = ForeverEnhancedCooldownManagerDB
local before = saved.session
Environment(true)
ns = Load(saved)
Equal(ns.restored, false, "a kept settings file is trusted")
Equal(#printed, 0, "with no warning")
Equal(saved.session, before + 1, "each login is numbered")

-- A character that logs in before its GUID is known is sorted out at login.
Environment()
local guid = character.guid
character.guid = nil
ns = Load({ useBars = true }, true)
Equal(ns.ProfileName(), nil, "no profile until the character is known")
character.guid = guid
Fire("PLAYER_LOGIN")
Equal(ns.ProfileName(), "Zriel (Druid) - Zephras", "worked out at login")

-- The /fecm window ------------------------------------------------------------------------

Environment()
ns = Load(nil)
B = ns.Bars
SlashCmdList.FECM("")
w = FECMFrame
page = w.pages.bar
Equal(S[w].shown, true, "/fecm opens the window")
Equal(w.nav.cd ~= nil and w.nav.util ~= nil and w.nav.buff ~= nil and w.nav.look ~= nil and w.nav.general ~= nil,
    true, "bars, Look and General listed down the left")
Equal(S[w.nav.cd.fill].shown and not S[w.nav.util.fill].shown, true, "the chosen one highlighted")
Equal(bindings[FECMEscButton], "ESCAPE:FECMEscButton", "Escape closes the window")
Equal(S[w.close.label].text, "X", "a plain X")
Equal(S[w.note].text, "Each spell shows once, at your highest rank.", "footer tip")

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
S[page.icons[1]].mouseOver = true
S[third].scripts.OnDragStop(third)
S[page.icons[1]].mouseOver = nil
Equal(table.concat(ns.BarData("cd").spells, ","), "Overpower,Moonfire,Wrath", "dragging onto an icon takes its place")
S[page.icons[1]].scripts.OnDragStart(page.icons[1])
S[page.tray].mouseOver = true
S[page.icons[1]].scripts.OnDragStop(page.icons[1])
S[page.tray].mouseOver = nil
Equal(table.concat(ns.BarData("cd").spells, ","), "Moonfire,Wrath,Overpower", "dropping on empty tray space moves it to the end")
S[page.icons[1]].scripts.OnDragStart(page.icons[1])
S[page.icons[1]].scripts.OnDragStop(page.icons[1])
Equal(table.concat(ns.BarData("cd").spells, ","), "Moonfire,Wrath,Overpower", "dropping outside the tray changes nothing")
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
Equal(S[page.options.hideReady].shown and not S[page.options.showMissing].shown, true, "cooldown bars offer Hide when ready")
w:Select("buff")
Equal(S[page.options.showMissing].shown and not S[page.options.hideReady].shown, true, "the Buffs bar offers missing buffs greyed")
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

-- Look: the charcoal look, reload and accent.
w:Select("look")
Equal(S[w.pages.look].shown and not S[page].shown, true, "Look page shown")
Equal(w.look:GetChecked(), true, "charcoal look shown as on")
Equal(S[w.off].shown, false, "no Cooldown Manager warning while it is on")
Equal(S[w.reload].shown, false, "no reload needed yet")
w.look:Click()
Equal(ForeverEnhancedCooldownManagerDB.skin, false, "unticking saves the choice")
Equal(S[w.reload].shown, true, "reload offered after a change")
Equal(w.hint:GetText(), "Reload UI to apply your change.", "explains the reload")
lockdown = true
w.reload:Click()
Equal(reloads, 0, "no reload in combat")
Equal(w.hint:GetText(), "Finish combat first, then reload.", "explains why")
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
local accentHeading = Heading("ACCENT")
Equal(accentHeading ~= nil, true, "headings in small capitals")
Equal(S[accentHeading].colour[1] == .88 and S[accentHeading].colour[2], .47, "headings in orange by default")
Equal(#w.swatches, 5, "five set colours")
Equal(w.swatches[1].key, "orange", "orange first")
w.swatches[3]:Click()
Equal(ns.Get("accent"), "teal", "a set colour chosen")
Equal(S[accentHeading].colour[1] == .17 and S[accentHeading].colour[2], .70, "the whole window repaints")
Equal(S[w.swatches[3]].border[1], 1, "chosen swatch outlined")
Equal(S[w.swatches[1]].border[1] < 1, true, "the others not")
w.swatches[1]:Click()
Equal(ns.Get("accent"), "orange", "back to orange")

-- Joined buttons (for the pill choices): no smeared shadow on a light accent.
local pills = ns.Theme:Segmented(UIParent, { { key = "a", label = "Show" }, { key = "b", label = "Fade" } }, 120, function() end)
pills:SetSelected("a")
Equal(S[pills.buttons[1].label].shadow, 0, "dark text on a light accent has no smeared shadow")
Equal(S[pills.buttons[2].label].shadow, 1, "light text on dark keeps its shadow")

-- General: your bars and moving them.
w:Select("general")
Equal(w.useBars:GetChecked(), true, "own bars shown as on")
w.useBars:Click()
Equal(B:Enabled(), false, "Use my bars turns them off")
w.unlock:Click()
Equal(S[w.note].text, "Tick Use my bars first.", "can't unlock while the bars are off")
w.useBars:Click()
w.unlock:Click()
Equal(B:IsUnlocked(), true, "unlocked")
Equal(S[w.unlock.label].text, "Lock bars", "button offers to lock")
w.unlock:Click()
Equal(B:IsUnlocked(), false, "locked again")

Fire("PLAYER_REGEN_DISABLED")
Equal(bindings[FECMEscButton], nil, "Escape handed back as combat starts")
lockdown = true
Fire("PLAYER_REGEN_ENABLED")
lockdown = false
Fire("PLAYER_REGEN_ENABLED")
Equal(bindings[FECMEscButton] ~= nil, true, "and taken again after combat while the window is open")
FECMEscButton:Click()
Equal(S[w].shown, false, "Escape closes it")
Equal(bindings[FECMEscButton], nil, "and releases the key")

SlashCmdList.FECM("check")
Equal(S[w].shown, true, "without the development check, /fecm check just toggles")
local probed
ns.Probe = function(msg) probed = msg end
SlashCmdList.FECM(" check Moonfire")
Equal(probed, " check Moonfire", "/fecm check reaches the development check")
Equal(S[w].shown, true, "and leaves the window alone")
ns.Probe = nil
cvarOn = false
w:Select("look")
Equal(S[w.off].shown, true, "warns when Blizzard's Cooldown Manager is off")
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
Equal(S[confirm.shade].shown, false, "a profile another character uses isn't asked about")
Equal(S[w.note].text, "Another character uses Zriel (Druid) - Zephras, so it can't be deleted.", "the reason is given instead")
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

-- Settings the game didn't keep are pointed out in the window too.
Environment(true)
ns = Load(nil)
SlashCmdList.FECM("")
w = FECMFrame
local footer
for _, f in ipairs(objects) do
    if S[f].text == "Settings restored from backup at login. See General." then footer = f end
end
Equal(footer ~= nil and S[footer].colour[1], 1, "the footer warns, in orange")
w:Select("general")
Equal(S[w.kept].text:find(ns.RESTORED_TEXT, 1, true) ~= nil, true, "and General explains")

print = _G.print
io.write("Bars and window checks passed: " .. checks .. " assertions.\n")
