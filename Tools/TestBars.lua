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

local function Fire(event, ...)
    for _, f in ipairs(frames) do
        if S[f].events[event] and S[f].scripts.OnEvent then S[f].scripts.OnEvent(f, event, ...) end
    end
end

-- Game environment ------------------------------------------------------------------

local SECRET = setmetatable({}, { __tostring = function() return "secret" end })
local book, usable, noMana, range, active, target, cvars, printed
local cooldownCalls, lockdown, containers, containerCallsInCombat
local trinket, trinketCooldown, bagItems, itemCooldown, itemCount
local bindings, cvarOn, reloads, timers

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
    _G.CustomAuraContainerSlotDefaultOptions = {}
    _G.issecretvalue = function(v) return v == SECRET end
    _G.UnitExists = function() return target end
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

local function Load(saved)
    local ns = {}
    _G.ForeverEnhancedCooldownManagerDB = saved
    for _, file in ipairs({ "Core.lua", "Style.lua", "Ranks.lua", "Spells.lua", "Buffs.lua", "Bars.lua", "Theme.lua", "BarsPanel.lua", "Window.lua" }) do
        assert(loadfile(file))("ForeverEnhancedCooldownManager", ns)
    end
    Fire("ADDON_LOADED", "ForeverEnhancedCooldownManager")
    Fire("PLAYER_ENTERING_WORLD")
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
Equal(#containers, 1, "one secure aura container")
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
Equal(cvars.FECMBackupBars1:find("buff.missing=0;buff.names=0;buff.spells=Thorns", 1, true) ~= nil, true, "Buffs bar backed up")
Equal(S[buffs.mover.label].text, "Buffs", "mover label is the bar's name")
Equal(S[buffs.mover.label].points[1][1], "CENTER", "inside the highlight")

-- Settings panel ------------------------------------------------------------------------

Environment()
ns = Load({ useBars = true })
B = ns.Bars
ns.Toggle()
local w = FECMFrame

-- Find the Moonfire row and tick CD.
local function Row(name)
    for _, f in ipairs(frames) do
        if f.spell == name and S[f].shown then return f end
    end
end
local row = Row("Moonfire")
Equal(row ~= nil, true, "Moonfire listed")
row.cd:Click()
Equal(ns.BarData("cd").spells[1], "Moonfire", "ticking CD adds it")
row.util:Click()
Equal(ns.BarData("util").spells[1], "Moonfire", "ticking Util moves it")
Equal(row.cd:GetChecked(), false, "and unticks CD")
Equal(#ns.BarData("cd").spells, 0, "CD bar emptied")
row.buff:Click()
Equal(ns.BarData("buff").spells[1], "Moonfire", "ticking Buff adds it to the Buffs bar")
Equal(ns.BarData("util").spells[1], "Moonfire", "without taking it off Utility")
local proc = Row("Clearcasting")
Equal(S[proc.cd].shown or S[proc.util].shown, false, "procs offer only the Buff tick")
Equal(S[proc.buff].shown, true, "Buff tick shown for procs")

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
Equal(Row("item:118"), nil, "items left out of the list by default")
Equal(Row("Moonfire") ~= nil, true, "spells listed")
local function ShowItemsBox()
    for _, f in ipairs(frames) do
        if f.text and S[f.text].text == "Show items" then return f end
    end
end
local itemsBox = ShowItemsBox()
itemsBox:Click()
Equal(ns.Get("listItems"), true, "Show items remembered")
Equal(Row("item:118") ~= nil, true, "items listed when asked")
Equal(cvars.FECMBackup, "accent=orange;listItems=1;listRanks=0;skin=1;useBars=1", "and backed up")

w.add:SetText("thor")
S[w.add].scripts.OnTextChanged(w.add, true)
Equal(S[w.add.suggest].shown, true, "matches appear while typing")
Equal(w.add.suggest.rows[1].name, "Thorns", "best match first")
local anchor = S[w.add.suggest.rows[1]].points[1]
Equal(anchor[1] == "BOTTOMLEFT" and anchor[3], 4, "best match sits right above the box")
Equal(S[w.add.suggest.rows[2]].points[1][3], 24, "the rest stack upwards")
w.add.suggest.rows[1]:Click()
Equal(w.add:GetText(), "Thorns", "clicking a match fills in its exact name")
Equal(S[w.add.suggest].shown, false, "and closes the list")
w.add:SetText("power word: fort")
S[w.add].scripts.OnTextChanged(w.add, true)
S[w.add].scripts.OnEnterPressed(w.add)
Equal(w.add:GetText(), "Power Word: Fortitude", "Enter takes the first match")
w.add:SetText("zzzz")
S[w.add].scripts.OnTextChanged(w.add, true)
Equal(S[w.add.suggest].shown, false, "no list when nothing matches")
w.add:SetText("nonsense")
w.addButtons.cd:Click()
Equal(S[w.note].text, 'No spell called "nonsense" was found.', "unknown names explained")
w.add:SetText("Minor Healing Potion")
w.addButtons.buff:Click()
Equal(S[w.note].text, "Items can't go on the Buffs bar.", "items kept off the Buffs bar")
w.add:SetText("Power Word: Fortitude")
w.addButtons.buff:Click()
Equal(ns.BarData("buff").spells[1], "Power Word: Fortitude", "added from the box")
Equal(S[w.note].text, "Added Power Word: Fortitude to Buffs.", "and confirmed")
Equal(w.add:GetText(), "", "box cleared")
local pwf = ns.Spells:Find("Power Word: Fortitude")
Equal(pwf and pwf.line, "Added", "added spells listed under Added")
local slotIDs = S[containers[1]].groups.g1.filters.includeSpellIDs
Equal(slotIDs[1243] and slotIDs[10938] and slotIDs[21564], true, "any rank, and Prayer of Fortitude, counts")
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
Equal(Row("Moonfire@1"), nil, "lower ranks hidden by default")
local ranksBox
for _, f in ipairs(frames) do
    if f.text and S[f.text].text == "Show all ranks" then ranksBox = f end
end
ranksBox:Click()
Equal(ns.Get("listRanks"), true, "Show all ranks remembered")
local fixedRow = Row("Moonfire@1")
Equal(fixedRow ~= nil, true, "lower ranks listed when asked")
Equal(S[fixedRow.name].text, "Rank 1", "under the spell as its rank")
Equal(S[fixedRow.cd].shown and S[fixedRow.util].shown, true, "with CD and Util ticks")
Equal(S[fixedRow.buff].shown, false, "but no Buff tick")
Equal(fixedRow.cd:GetChecked(), true, "ticked where it's tracked")
Equal(S[Row("Moonfire").rank].text, "Highest (Rank 3)", "the normal row says it follows the highest")
Row("Moonfire@2").util:Click()
Equal(ns.BarData("util").spells[2], "Moonfire@2", "a lower rank ticked onto a bar")
Environment(true)
ns = Load(nil)
Equal(table.concat(ns.BarData("util").spells, ","), "Moonfire,Moonfire@2", "fixed ranks restored from the backup")

-- The /ccm window ------------------------------------------------------------------------

Environment()
ns = Load(nil)
B = ns.Bars
SlashCmdList.FECM("")
w = FECMFrame
Equal(S[w].shown, true, "/ccm opens the window")
Equal(#w.panels, 3, "Spellbook, Bars and Settings side by side")
Equal(w.look:GetChecked(), true, "charcoal look shown as on")
Equal(w.useBars:GetChecked(), false, "own bars shown as off")
Equal(S[w.off].shown, false, "no Cooldown Manager warning while it is on")
Equal(S[w.reload].shown, false, "no reload needed yet")
Equal(bindings[FECMEscButton], "ESCAPE:FECMEscButton", "Escape closes the window")
Equal(S[w.close.label].text, "X", "a plain X")
Equal(S[w.note].text, "Each spell shows once, at your highest rank.", "footer tip")

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

w.unlock:Click()
Equal(S[w.note].text, "Tick Use my bars first.", "can't unlock while the bars are off")
w.useBars:Click()
Equal(B:Enabled(), true, "Use my bars turns them on")
w.unlock:Click()
Equal(B:IsUnlocked(), true, "unlocked")
Equal(S[w.unlock.label].text, "Lock bars", "button offers to lock")
w.unlock:Click()
Equal(B:IsUnlocked(), false, "locked again")

-- Accent: orange by default, or another set colour.
local function Heading(text)
    for i = #objects, 1, -1 do
        if S[objects[i]] and S[objects[i]].text == text then return objects[i] end
    end
end
local spellbook = Heading("SPELLBOOK")
Equal(spellbook ~= nil, true, "headings in small capitals")
Equal(S[spellbook].colour[1] == .88 and S[spellbook].colour[2], .47, "headings in orange by default")
Equal(#w.swatches, 5, "five set colours")
Equal(w.swatches[1].key, "orange", "orange first")
w.swatches[3]:Click()
Equal(ns.Get("accent"), "teal", "a set colour chosen")
Equal(S[spellbook].colour[1] == .17 and S[spellbook].colour[2], .70, "the whole window repaints")
Equal(S[w.swatches[3]].border[1], 1, "chosen swatch outlined")
local function Segment(label)
    for i = #objects, 1, -1 do
        local o = objects[i]
        if S[o] and S[o].text == label and S[o].shadow ~= nil then return o end
    end
end
local chosenTab, otherTab = Segment("Cooldowns"), Segment("Utility")
Equal(S[chosenTab].colour[1] < .5 and S[chosenTab].shadow, 0, "dark text on a light accent has no smeared shadow")
Equal(S[otherTab].shadow, 1, "light text on dark keeps its shadow")
Equal(S[w.swatches[1]].border[1] < 1, true, "the others not")
w.swatches[1]:Click()
Equal(ns.Get("accent"), "orange", "back to orange")

-- Clearing a bar takes two clicks.
B:Assign("Moonfire", "cd")
B:Assign("Wrath", "cd")
w:Refresh()
Equal(S[w.clear.label].text, "Clear Cooldowns", "clear names the bar")
w.clear:Click()
Equal(#ns.BarData("cd").spells, 2, "one click only asks")
Equal(S[w.clear.label].text, "Click again to clear", "and says so")
w.clear:Click()
Equal(#ns.BarData("cd").spells, 0, "the second click clears")
Equal(S[w.note].text, "Cooldowns cleared.", "and confirms")
B:Assign("Moonfire", "cd")
w.clear:Click()
for _, timer in ipairs(timers) do timer() end
w.clear:Click()
Equal(#ns.BarData("cd").spells, 1, "after a pause, the next click asks again")

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
Equal(S[w].shown, true, "without the development check, /ccm check just toggles")
local probed
ns.Probe = function(msg) probed = msg end
SlashCmdList.FECM(" check Moonfire")
Equal(probed, " check Moonfire", "/ccm check reaches the development check")
Equal(S[w].shown, true, "and leaves the window alone")
ns.Probe = nil
ns.Toggle()
cvarOn = false
ns.Toggle()
Equal(S[w.off].shown, true, "warns when Blizzard's Cooldown Manager is off")
Equal(#printed, 0, "no errors")

print = _G.print
io.write("Bars and window checks passed: " .. checks .. " assertions.\n")
