-- Run the actual Classic Bars files (Core, Spells, Bars, BarsPanel) against a
-- mock game: spellbook ranks, secret cooldowns in combat, usable and range
-- tints, showing and hiding, dragging, the settings backup, and the panel.
local checks = 0
local function Equal(actual, expected, label)
    checks = checks + 1
    assert(actual == expected, label .. ": expected " .. tostring(expected) .. ", got " .. tostring(actual))
end

-- Mock frames -----------------------------------------------------------------------

local S = setmetatable({}, { __mode = "k" })
local Proto = {}
local frames = {}

local function New(kind, parent)
    local obj = {}
    S[obj] = { kind = kind, parent = parent, shown = true, last = {}, scripts = {}, events = {}, points = {},
        width = 0, height = 0, alpha = 1 }
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
    if watched[self] and InCombatLockdown() and S[self].shown ~= v then S[self].combatToggle = true end
    S[self].shown = v
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

local function Book(ranks)
    -- Two tabs: General (Attack), Balance (Moonfire ranks, Wrath, a passive,
    -- a future spell) and Arms (Overpower).
    book = {
        { name = "General", items = { { name = "Attack", spellID = 6603 } } },
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
        GetSpellName = function(id) return ({ [16870] = "Clearcasting", [16886] = "Nature's Grace" })[id] end,
    }
    _G.UnitClass = function() return "Druid", "DRUID" end
    _G.CustomAuraContainerSlotDefaultOptions = {}
    _G.issecretvalue = function(v) return v == SECRET end
    _G.UnitExists = function() return target end
    _G.UnitAffectingCombat = function() return false end
    _G.InCombatLockdown = function() return lockdown end
    _G.C_CVar = {
        GetCVarBool = function() return true end,
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
        end
        frames[#frames + 1] = f
        if name then _G[name] = f end
        return f
    end
    _G.UIParent = New("Frame")
    S[UIParent].cx, S[UIParent].cy = 500, 400
    _G.GameFontHighlight = { GetFont = function() return "font", 12, "" end }
    _G.SlashCmdList = {}
    _G.Settings = nil
    _G.ClearOverrideBindings = function() end
    _G.SetOverrideBindingClick = function() end
end

local function Load(saved)
    local ns = {}
    _G.ClassicCooldownManagerDB = saved
    for _, file in ipairs({ "Core.lua", "Spells.lua", "Buffs.lua", "Bars.lua", "BarsPanel.lua" }) do
        assert(loadfile(file))("ClassicCooldownManager", ns)
    end
    Fire("ADDON_LOADED", "ClassicCooldownManager")
    Fire("PLAYER_ENTERING_WORLD")
    return ns
end

-- Spellbook: one entry per spell, highest rank -----------------------------------------

Environment()
local ns = Load(nil)
local B = ns.Bars
local list = ns.Spells:List()
Equal(#list, 7, "Attack, Moonfire, Wrath, Thorns, Overpower and two druid procs; passive and future spells left out")
local moonfire = ns.Spells:Find("Moonfire")
Equal(moonfire.spellID, 8924, "Moonfire uses the highest rank")
Equal(moonfire.rankText, "Rank 2", "shows that rank")
Equal(moonfire.line, "Balance", "grouped by spellbook tab")
Equal(ns.Spells:Find("Natural Weapons"), nil, "passives left out")
Equal(table.concat(ns.Spells:Find("Thorns").ids, ","), "467,782", "every known rank recorded for buff matching")
local cc = ns.Spells:Find("Clearcasting")
Equal(cc and cc.proc and cc.line, "Procs", "class procs listed under Procs")
Equal(cc.ids[1], 16870, "with their spell IDs")
Equal(list[#list].name, "Nature's Grace", "procs come last")

-- Off by default ------------------------------------------------------------------------

Equal(B:Enabled(), false, "Classic Bars start off")
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

ns.Set("classicBars", true)
B:Rebuild()
local cd, util = B:Get("cd"), B:Get("util")
Equal(S[cd].shown, true, "a bar with spells shows")
Equal(S[util].shown, false, "an empty bar stays hidden")
Equal(cd.count, 2, "two icons")
Equal(S[cd].width, 2 * 36 + 4, "bar width fits its icons")
local over, moon = cd.icons[1], cd.icons[2]
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
ns.Set("classicBars", false)
B:Rebuild()
Equal(B:IsUnlocked(), false, "turning Classic Bars off locks them")
Equal(S[cd].shown, false, "and hides them")
ns.Set("classicBars", true)
B:Rebuild()

-- A new rank moves the bar onto it ------------------------------------------------------

Book(true)
Fire("SPELLS_CHANGED")
Equal(cd.icons[2].spellID, 8925, "trained rank 3: the bar uses it")
Equal(ns.BarData("cd").spells[2], "Moonfire", "saved setup unchanged")

-- Backup ------------------------------------------------------------------------------

Equal(cvars.ClassicCooldownManagerBackup, "classicBars=1;classicLook=1", "on/off backup")
Equal(cvars.ClassicCooldownManagerBackupBars0, "1", "bars backed up in one chunk")
Environment(true)
ns = Load(nil)
B = ns.Bars
Equal(B:Enabled(), true, "Classic Bars on again after lost settings")
Equal(table.concat(ns.BarData("cd").spells, ","), "Overpower,Moonfire", "bar spells restored")
Equal(ns.BarData("cd").x, 20, "bar position restored")
Equal(ns.BarData("util").x, nil, "unmoved bar keeps its default spot")
Equal(B:Get("cd").count, 2, "and drawn")

Environment(true)
cvars.ClassicCooldownManagerBackupBars1 = "cd.size=9999;cd.spells=A|B;cd.x=nope;evil.size=3;cd.hide=maybe"
ns = Load(nil)
local data = ns.BarData("cd")
Equal(data.size, 64, "bad sizes clamped")
Equal(table.concat(data.spells, ","), "A,B", "names read as plain text")
Equal(data.x, nil, "bad positions dropped")
Equal(data.hideReady, false, "bad flags off")
Equal(ns.BarData("evil"), nil, "unknown bars ignored")

-- Buffs bar -------------------------------------------------------------------------------

Environment()
ns = Load({ classicBars = true })
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

Equal(B:SetBuff("Thorns", true), true, "Thorns ticked")
Equal(slots.b1.enabled, true, "its slot switched on")
Equal(slots.b1.filters.includeSpellIDs[467] and slots.b1.filters.includeSpellIDs[782], true, "any known rank of Thorns")
Equal(slots.b2.enabled, false, "the rest stay off")
Equal(S[buffs].shown, true, "the bar shows")
B:SetBuff("Clearcasting", true)
Equal(slots.b2.filters.includeSpellIDs[16870], true, "a proc in the next slot")
B:Assign("Thorns", "cd")
Equal(B:HasBuff("Thorns"), true, "a spell can be on a cooldown bar and the Buffs bar")
Equal(B:Find("Thorns"), "cd", "and stays on its cooldown bar")
B:Assign("Thorns", nil)

Equal(S[buffs.holders[1].icon].shown, false, "missing buffs hidden by default")
B:SetOption("buff", "showMissing", true)
Equal(S[buffs.holders[1].icon].shown, true, "shown greyed when asked")
Equal(S[buffs.holders[1].icon].desaturated, true, "in grey")

-- Nothing touches the secure slots, or shows or hides the bar, in combat.
Fire("PLAYER_REGEN_DISABLED")
lockdown = true
B:SetBuff("Clearcasting", false)
Equal(containerCallsInCombat, 0, "no slot changes in combat")
Equal(slots.b2.enabled, true, "Clearcasting's slot waits")
B:SetOption("buff", "combatOnly", true)
Equal(S[buffs].alpha, 1, "only in combat: visible in a fight")
ns.Set("classicBars", false)
B:Rebuild()
Equal(S[buffs].combatToggle, nil, "never shown or hidden in combat")
Equal(S[buffs].shown, true, "hiding waits for the fight to end")
lockdown = false
Fire("PLAYER_REGEN_ENABLED")
Equal(S[buffs].shown, false, "hidden after the fight")
Equal(slots.b1.enabled or slots.b2.enabled, false, "and every slot switched off")
ns.Set("classicBars", true)
B:Rebuild()
Equal(slots.b1.enabled, true, "back on with Classic Bars")
Equal(slots.b2.enabled, false, "Clearcasting's change applied")
Equal(S[buffs].alpha, 0, "only in combat: faded out of combat")
Equal(#printed, 0, "no errors")
Equal(cvars.ClassicCooldownManagerBackupBars1:find("buff.missing=1", 1, true) ~= nil, true, "Buffs bar backed up")
Equal(S[buffs.mover.label].text, "Buffs", "mover label is the bar's name")
Equal(S[buffs.mover.label].points[1][1], "CENTER", "inside the highlight")

-- Settings panel ------------------------------------------------------------------------

Environment()
ns = Load({ classicBars = true })
B = ns.Bars
ns.Toggle()
local w = ClassicCooldownManagerFrame
w.tabs.bars:Click()
Equal(S[w.pages.bars].shown, true, "Classic Bars page opens")
Equal(S[w.pages.look].shown, false, "Classic look page hidden")

-- Find the Moonfire row and tick CD.
local function Row(name)
    for _, f in ipairs(frames) do
        if f.spell == name and S[f].shown then return f end
    end
end
local row = Row("Moonfire")
Equal(row ~= nil, true, "Moonfire listed")
row.cd:SetChecked(true)
row.cd:Click()
Equal(ns.BarData("cd").spells[1], "Moonfire", "ticking CD adds it")
row.util:SetChecked(true)
row.util:Click()
Equal(ns.BarData("util").spells[1], "Moonfire", "ticking Util moves it")
Equal(row.cd:GetChecked(), false, "and unticks CD")
Equal(#ns.BarData("cd").spells, 0, "CD bar emptied")
row.buff:SetChecked(true)
row.buff:Click()
Equal(ns.BarData("buff").spells[1], "Moonfire", "ticking Buff adds it to the Buffs bar")
Equal(ns.BarData("util").spells[1], "Moonfire", "without taking it off Utility")
local proc = Row("Clearcasting")
Equal(S[proc.cd].shown or S[proc.util].shown, false, "procs offer only the Buff tick")
Equal(S[proc.buff].shown, true, "Buff tick shown for procs")

print = _G.print
io.write("Classic Bars checks passed: " .. checks .. " assertions.\n")
