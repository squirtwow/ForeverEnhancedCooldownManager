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
function Proto:RegisterUnitEvent(e) S[self].events[e] = true end
function Proto:GetAlpha() return S[self].alpha end
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
local ammo, ammoCount -- the equipped ammunition and how many you carry
local bindings, cvarOn, reloads, timers
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
end

local function Load(saved, beforeLogin)
    local ns = {}
    _G.ForeverEnhancedCooldownManagerDB = saved
    for _, file in ipairs({ "Core.lua", "Style.lua", "Skin.lua", "Resource.lua", "CastBar.lua", "Ranks.lua", "Spells.lua", "Buffs.lua", "Bars.lua",
        "Layout.lua", "Theme.lua", "BarPage.lua", "LayoutPage.lua", "CastBarPage.lua", "ProfileMenu.lua", "Window.lua", "Notes.lua" }) do
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
-- While the bars are being arranged, every icon shows.
S[moon].alpha, S[moon].alphaFrom = nil, nil
B:SetUnlocked(true)
Equal(S[moon].alpha == 1 and S[moon].alphaFrom == nil, true, "unlocked: shown even when ready, to see while moving it")
B:SetUnlocked(false)
Equal(S[moon].alphaFrom, SECRET, "locked again: hidden when ready")
S[moon].alpha, S[moon].alphaFrom = nil, nil
EditModeManagerFrame:Show()
Equal(S[moon].alpha == 1 and S[moon].alphaFrom == nil, true, "in Edit Mode too")
EditModeManagerFrame:Hide()
Equal(S[moon].alphaFrom, SECRET, "and hidden when ready once Edit Mode closes")
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

B:SetOption("cd", "outOfCombat", "hide")
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
Equal(ns.BarData("cd").y, -82, "by the top edge, so new rows grow down from it")
p = S[cd].points[1]
Equal(p[1] == "TOP" and p[4] == 20 and p[5], -82, "placed where it was dropped")
B:SetOption("cd", "outOfCombat", "show")
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

Equal(cvars.FECMBackup, "accent=orange;barColour=orange;barStyle=glass;castBar=0;castColour=default;castHeight=18;castIcon=1;castName=1;castTime=1;iconBorder=off;iconShadow=off;listItems=0;listRanks=0;prdCombo=0;prdComboColour=default;prdHealth=default;prdHideRepeat=1;prdMatch=1;prdPower=default;prdSkin=1;skin=1;useBars=1", "on/off backup")
Equal(cvars.FECMBackupBars0 .. " " .. #cvars.FECMBackupBars1, "2 900", "bars backed up in chunks of 900 characters")
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
B:SetOption("buff", "outOfCombat", "hide")
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

-- Out of combat: show, fade or hide -------------------------------------------------------

Environment()
ns = Load({ useBars = true, bars = { cd = { combatOnly = true } } })
B = ns.Bars
Equal(ns.BarData("cd").outOfCombat, "hide", "bars that were only in combat now hide out of combat")
Equal(rawget(ns.BarData("cd"), "combatOnly"), nil, "the old setting is gone")
Equal(ns.BarData("util").outOfCombat, "show", "the rest show")
B:Assign("Moonfire", "cd")
B:Assign("Wrath", "util")
B:SetAura("buff", "Thorns", true)
local cdBar, utilBar, buffBar = B:Get("cd"), B:Get("util"), B:Get("buff")
target, hostile = false, true
B:UpdateShown()
Equal(S[cdBar].shown, false, "hidden out of combat")
Fire("PLAYER_REGEN_DISABLED")
Equal(S[cdBar].shown and S[cdBar].alpha, 1, "back in full in combat")
Fire("PLAYER_REGEN_ENABLED")
Equal(S[cdBar].shown, false, "hidden again after")
target = true
Fire("PLAYER_TARGET_CHANGED")
Equal(S[cdBar].shown, true, "back with an enemy targeted")
hostile = false
Fire("PLAYER_TARGET_CHANGED")
Equal(S[cdBar].shown, false, "but not with a friend")
hostile = SECRET
Fire("PLAYER_TARGET_CHANGED")
Equal(S[cdBar].shown, true, "a hidden answer counts as an enemy")
hostile, target = true, false
Fire("PLAYER_TARGET_CHANGED")
EditModeManagerFrame:Show()
Equal(S[cdBar].shown, true, "back in Edit Mode")
EditModeManagerFrame:Hide()
Equal(S[cdBar].shown, false, "and hidden once it closes")
B:SetOption("util", "outOfCombat", "fade")
Equal(S[utilBar].shown and S[utilBar].alpha, .3, "faded to 30% out of combat")
Fire("PLAYER_REGEN_DISABLED")
Equal(S[utilBar].alpha, 1, "full in combat")
Fire("PLAYER_REGEN_ENABLED")
B:SetOption("buff", "outOfCombat", "fade")
Equal(S[buffBar].shown and S[buffBar].alpha, .3, "aura bars fade too")
B:SetOption("buff", "outOfCombat", "hide")
Equal(S[buffBar].shown and S[buffBar].alpha, 0, "and hide by fading right out, since their slots can't be hidden in a fight")
B:SetUnlocked(true)
Equal(S[cdBar].shown and S[utilBar].alpha == 1 and S[buffBar].alpha, 1, "unlocked, every bar shows in full")
B:SetUnlocked(false)
Equal(cvars.FECMBackupBars1:find("6:cd.ooc4:hide", 1, true) ~= nil, true, "the choice is backed up")
Environment(true)
cvars.FECMBackupBars0, cvars.FECMBackupBars1 = "1", "cd.combat=1;cd.spells=Moonfire"
ns = Load(nil)
Equal(ns.BarData("cd").outOfCombat, "hide", "backups from before the choice carry it over")
Environment(true)
cvars.FECMBackupBars1 = "v2;9:cd.combat1:1"
ns = Load(nil)
Equal(ns.BarData("cd").outOfCombat, "hide", "including this week's backups")

-- The window's out-of-combat choice.
Environment()
ns = Load({ useBars = true })
B = ns.Bars
SlashCmdList.FECM("")
local choice = FECMFrame.pages.bar.options.outOfCombat
Equal(choice.selected, "show", "the page shows the bar's choice")
choice.buttons[2]:Click()
Equal(ns.BarData("cd").outOfCombat, "fade", "clicking Fade sets it")
Equal(choice.selected, "fade", "and shows it")
FECMFrame:Select("util")
Equal(choice.selected, "show", "each bar has its own")

-- Ammunition ---------------------------------------------------------------------------------

Environment()
ammo, ammoCount = 2512, 200
ns = Load({ useBars = true })
B = ns.Bars
local arrows = ns.Spells:Find("ammo")
Equal(arrows and arrows.name, "Ammo: Rough Arrow", "equipped ammunition listed")
Equal(arrows.line, "Items", "with the items")
B:Assign("ammo", "util")
local quiver = B:Get("util").icons[1]
Equal(S[quiver.count].text, 200, "its count shown")
Equal(S[quiver.texture].desaturated, false, "in colour while you have some")
ammoCount = 0
B:RefreshAll()
Equal(S[quiver.texture].desaturated, true, "greyed when you run out")
B:SetOption("util", "showNames", true)
Equal(S[B:Get("util").icons[1].label].text, "Rough Arrow", "named by the ammo")
ammo = nil
Fire("PLAYER_EQUIPMENT_CHANGED")
Equal(ns.Spells:Find("ammo") and ns.Spells:Find("ammo").name, "Ammo", "kept on the bar with none equipped")
Equal(S[B:Get("util").icons[1].count].text, 0, "showing none")
Equal(ns.Spells:IsItem(ns.Spells:Find("ammo")), true, "never offered for the Buffs or Debuffs bar")
Equal(#printed, 0, "no errors")

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
local at = S[row.where].points[1]
Equal(at[1] == "LEFT" and at[2] == row.rank and at[3] == "RIGHT" and at[4], 10, "right after its rank, on its own row")
Equal(S[Row("Attack").where].points[1][2], Row("Attack").name, "or its name, for a spell without ranks")
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
Equal(cvars.FECMBackup, "accent=orange;barColour=orange;barStyle=glass;castBar=0;castColour=default;castHeight=18;castIcon=1;castName=1;castTime=1;iconBorder=off;iconShadow=off;listItems=1;listRanks=0;prdCombo=0;prdComboColour=default;prdHealth=default;prdHideRepeat=1;prdMatch=1;prdPower=default;prdSkin=1;skin=1;useBars=1", "and backed up")

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

-- The /ccm window ------------------------------------------------------------------------

Environment()
ns = Load(nil)
B = ns.Bars
SlashCmdList.FECM("")
w = FECMFrame
page = w.pages.bar
Equal(S[w].shown, true, "/ccm opens the window")
Equal(w.nav.cd ~= nil and w.nav.util ~= nil and w.nav.buff ~= nil and w.nav.look ~= nil and w.nav.general ~= nil,
    true, "bars, Look and General listed down the left")
Equal(S[w.yourBars].text, "YOUR BARS", "the bars headed as your own, apart from Blizzard's")
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
Equal(S[third].alpha, 0, "picked up, its spot is empty")
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
Equal(table.concat(ns.BarData("cd").spells, ",") .. " " .. S[w.note].text, "Wrath,Overpower Took Moonfire off Cooldowns.",
    "dragged off the tray, it comes off the bar")
B:Assign("Moonfire", "cd")
B:MoveTo("cd", 3, 1)
w:Refresh()
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

-- Look: the restyle, reload and accent.
w:Select("look")
Equal(S[w.pages.look].shown and not S[page].shown, true, "Look page shown")
Equal(w.look:GetChecked(), true, "restyle shown as on")
Equal(S[w.look.text].text .. "|" .. S[w.personal.text].text .. "|" .. S[w.repeatMana.text].text,
    "Apply this look to the Cooldown Manager|Apply this look to the Personal Resource Display|Extra mana bar: hide in caster form, half size in forms",
    "the ticks say what they apply to")
Equal(S[w.off].shown, false, "no Cooldown Manager warning while it is on")
Equal(S[w.reload].shown, false, "no reload needed yet")
w.look:Click()
Equal(ForeverEnhancedCooldownManagerDB.skin, false, "unticking saves the choice")
Equal(S[w.reload].shown, true, "reload offered after a change")
Equal(S[w.reload.label].text, "Reload to apply", "saying why")
lockdown = true
w.reload:Click()
Equal(reloads, 0, "no reload in combat")
Equal(S[w.note].text, "Finish combat first, then reload.", "explains why")
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
local accentHeading = Heading("EACH BAR")
Equal(accentHeading ~= nil, true, "headings in small capitals")
Equal(S[accentHeading].colour[1] == .88 and S[accentHeading].colour[2], .47, "headings in orange by default")
Equal(#w.swatches, 5, "five window accents")
Equal(w.swatches[1].key, "orange", "orange first")
w.swatches[3]:Click()
Equal(ns.Get("accent"), "teal", "a set colour chosen")
Equal(S[accentHeading].colour[1] == .17 and S[accentHeading].colour[2], .70, "the whole window repaints")
Equal(S[w.swatches[3]].border[1], 1, "chosen swatch outlined")
Equal(S[w.swatches[1]].border[1] < 1, true, "the others not")
w.swatches[1]:Click()
Equal(ns.Get("accent"), "orange", "back to orange")

-- A wash of the accent from the right, and a line round the Each bar box.
local function Wash(texture)
    local from, to = Last(texture, "SetGradient", 2), Last(texture, "SetGradient", 3)
    return Last(texture, "SetGradient", 1) == "HORIZONTAL" and from.a == 0 and to.r == .88 and to.a
end
Equal(Wash(w.fades.header), .30, "the title bar fades in from the right, in the accent")
Equal(Wash(w.fades.page), .18, "softer behind the pages")
Equal(Wash(w.nav.look.glow), .36, "stronger on the chosen menu item")
Equal(S[w.nav.look.glow].shown and not S[w.nav.general.glow].shown, true, "only the chosen one")
Equal(S[w.eachPanel].border[1], .88, "the Each bar box outlined in the accent")
Equal(S[page.listPanel].border[1], .88, "and each bar page's spell list")
Equal(S[page.tray].border[1] < .5, true, "the smaller box at the top keeps a plain line")
w.swatches[3]:Click()
Equal(Last(w.fades.header, "SetGradient", 3).r == .17 and S[w.eachPanel].border[1], .17, "all repainted with a new accent")
w.swatches[1]:Click()
-- The Class swatch shows your class icon, so it isn't a second orange.
Equal(Last(w.barSwatches[6].icon, "SetAtlas", 1), "classicon-druid", "class icon on the Class swatch")
Equal(w.barSwatches[1].icon, nil, "the other swatches are plain colour")

-- Tracked Bars: a design and a colour.
Equal(w.barDesign.selected, "glass", "Glass by default")
w.barDesign.buttons[3]:Click()
Equal(ns.Get("barStyle"), "outline", "Outline chosen")
Equal(w.barDesign.selected, "outline", "and shown")
Equal(#w.barSwatches, 6, "six bar colours")
Equal(w.barSwatches[6].key, "class", "your class colour last")
w.barSwatches[3]:Click()
Equal(ns.Get("barColour"), "blue", "a colour chosen")
Equal(S[w.barSwatches[3]].border[1], 1, "its swatch outlined")
Equal(S[w.barSwatches[1]].border[1] < 1, true, "the others not")
Equal(Last(w.preview.Bar, "SetStatusBarColor", 3), .88, "the preview bar shows it")
w.barDesign.buttons[1]:Click()
w.barSwatches[1]:Click()
Equal(Last(w.preview.Bar, "SetStatusBarColor", 1), 1, "and changes back")

-- Each Tracked Bar in a colour of its own, listed from Blizzard's bars.
local function Tracked(id, order)
    return { GetBaseSpellID = function() return id end, layoutIndex = order }
end
local tracked = { [Tracked(1243, 2)] = true, [Tracked(16870, 1)] = true }
_G.BuffBarCooldownViewer = { itemFramePool = { EnumerateActive = function() return pairs(tracked) end } }
w:Refresh()
local rows = w.eachRows
Equal(S[rows[1].name].text .. "," .. S[rows[2].name].text, "Clearcasting,Power Word: Fortitude", "your Tracked Bars, in Blizzard's order")
Equal(Last(rows[1].swatches[6].icon, "SetAtlas", 1), "classicon-druid", "each bar's Class swatch shows the icon too")
Equal(S[rows[1].chosen].text, "Default", "each uses the colour for all at first")
Equal(S[w.eachEmpty].shown, false, "no note while there are bars")
rows[1].swatches[4]:Click()
Equal(ns.BarColours()[16870], "green", "a colour picked for one bar")
Equal(S[rows[1].chosen].text, "Green", "and named")
Equal(S[rows[1].swatches[4]].border[1], 1, "its swatch outlined")
Equal(S[rows[2].chosen].text, "Default", "the other bar unchanged")
rows[1].swatches[4]:Click()
Equal(ns.BarColours()[16870], nil, "clicking it again goes back to the colour for all")
Equal(S[rows[1].chosen].text, "Default", "and says so")
tracked = {}
w:Refresh()
Equal(S[rows[1]].shown, false, "rows go with the bars")
Equal(S[w.eachEmpty].text:find("Tracked Bars (buffs shown as timer bars)", 1, true) ~= nil, true, "and the list says what they are and where to add some")
Equal(S[w.eachFix].shown, false, "with no button: that's done in Blizzard's Cooldown Settings")
ns.loaded.skin = false
w:Refresh()
Equal(S[w.eachEmpty].text .. " " .. S[w.eachFix.label].text, "Reload first, then colour your bars one by one here. Reload",
    "just ticked: reload first, with a button for it")
ns.Set("skin", false)
w:Refresh()
Equal(S[w.eachEmpty].text .. " " .. S[w.eachFix.label].text,
    "Apply this look to the Cooldown Manager and reload to colour your bars one by one. Turn on", "with the look off, a button to turn it on")
w.eachFix:Click()
Equal(tostring(ns.Get("skin")) .. " " .. S[w.eachEmpty].text, "true Reload first, then colour your bars one by one here.",
    "which ticks it, then asks for the reload")
ns.Set("skin", true)
ns.loaded.skin = true
_G.BuffBarCooldownViewer = nil
-- The Personal Resource Display's bars, listed first while it's on.
_G.PersonalResourceDisplayFrame = {}
w:Refresh()
Equal(S[rows[1].name].text .. "," .. S[rows[2].name].text, "Personal health,Personal power", "the personal bars listed first")
rows[2].swatches[5]:Click()
Equal(ns.Get("prdPower"), "purple", "a colour for the personal power bar")
Equal(S[rows[2].chosen].text, "Purple", "and named")
rows[2].swatches[5]:Click()
Equal(ns.Get("prdPower"), "default", "clicking it again goes back to Blizzard's")
w.repeatMana:Click()
Equal(ns.Get("prdHideRepeat"), false, "the repeat mana bar can be kept")
w.repeatMana:Click()
w.personal:Click()
Equal(ns.Get("prdSkin") == false and S[w.reload].shown, true, "turning the restyle off asks for a reload")
w.personal:Click()
Equal(S[w.reload].shown, false, "and back on needs none")
_G.PersonalResourceDisplayFrame = nil

-- Joined buttons (for the pill choices): no smeared shadow on a light accent.
local pills = ns.Theme:Segmented(UIParent, { { key = "a", label = "Show" }, { key = "b", label = "Fade" } }, 120, function() end)
pills:SetSelected("a")
Equal(S[pills.buttons[1].label].shadow, 0, "dark text on a light accent has no smeared shadow")
Equal(S[pills.buttons[2].label].shadow, 1, "light text on dark keeps its shadow")

-- General: your bars and moving them.
w:Select("general")
-- More from Squirt: EraUI, and a way to open it.
Equal(S[w.moreOpen].shown, false, "EraUI not installed: no Open button")
Equal(S[w.moreLinks[1]].shown and S[w.moreLinks[2]].shown, true, "but CurseForge and GitHub buttons")
w.moreLinks[1]:Click()
local copy = FECMCopyLink
Equal(S[copy].shown and S[copy.title].text, "ERAUI ON CURSEFORGE", "each opens a box in the window's own look")
Equal(copy.input:GetText(), "https://www.curseforge.com/wow/addons/eraui", "with its link to copy")
copy.input:SetText("typed over")
S[copy.input].scripts.OnTextChanged(copy.input)
Equal(copy.input:GetText(), "https://www.curseforge.com/wow/addons/eraui", "which can't be typed over")
Equal(S[copy.note].text:find("On CurseForge, Install opens the CurseForge app.", 1, true) ~= nil, true,
    "CurseForge's box says Install opens the app")
copy.close:Click()
Equal(S[copy].shown, false, "Close closes it")
w.moreLinks[2]:Click()
Equal(S[copy.title].text .. "|" .. copy.input:GetText(), "ERAUI ON GITHUB|https://github.com/squirtwow/EraUI", "GitHub's box")
Equal(S[copy.note].text, "Press Ctrl+C to copy, then paste it into your browser.", "says only how to copy")
copy.close:Click()
_G.C_AddOns = { IsAddOnLoaded = function(name) return name == "EraUI" end }
local eraOpened
SlashCmdList.ERAUI = function() eraOpened = true end
w:Refresh()
Equal(S[w.moreOpen].shown, true, "installed: an Open button")
Equal(S[w.moreLinks[1]].shown, false, "and no links")
w.moreOpen:Click()
Equal(eraOpened and not S[w].shown, true, "which opens EraUI and closes this window")
_G.C_AddOns, SlashCmdList.ERAUI = nil, nil
ns.ShowWindow()
w:Select("general")
Equal(w.useBars:GetChecked(), true, "own bars shown as on")
w.useBars:Click()
Equal(B:Enabled(), false, "Use my bars turns them off")
-- Unlocking lives on the Layout page.
local unlock = w.pages.layout.unlock
w:Select("layout")
unlock:Click()
Equal(S[w.note].text, "Turn your bars on first.", "can't unlock while the bars are off")
w:Select("general")
w.useBars:Click()
w:Select("layout")
unlock:Click()
Equal(B:IsUnlocked(), true, "unlocked")
Equal(S[unlock.label].text .. " | " .. S[w.pages.layout.status].text, "Lock bars | Unlocked: drag a bar on screen to move it.",
    "button offers to lock, and the page says so")
unlock:Click()
Equal(B:IsUnlocked(), false, "locked again")
unlock:Click()
w:Hide()
Equal(B:IsUnlocked(), false, "closing the window locks them")
ns.ShowWindow()

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
cvarOn = false
w:Select("look")
Equal(S[w.off].shown, true, "warns when Blizzard's Cooldown Manager is off")
Equal(S[w.eachEmpty].text .. " " .. S[w.eachFix.label].text .. " " .. tostring(S[w.eachFix].shown),
    "Blizzard's Cooldown Manager is off. Turn on true", "and the list says so, with its own Turn on")
Equal(S[w.turnOnManager].shown, true, "with a way to turn it on")
w.eachFix:Click()
Equal(cvarOn, true, "the list's button switches it on too")
cvarOn = false
w:Refresh()
w.turnOnManager:Click()
Equal(cvarOn and S[w.note].text, "Blizzard's Cooldown Manager is on.", "which switches it on")
Equal(S[w.off].shown or S[w.turnOnManager].shown, false, "and the warning goes")
prdOn = false
w:Refresh()
Equal(S[w.personalOff].shown and S[w.turnOnPersonal].shown, true, "a Personal Resource Display that's off is pointed out too")
lockdown = true
w.turnOnPersonal:Click()
Equal(prdOn == false and S[w.note].text, "Finish combat first.", "never switched in combat")
lockdown = false
w.turnOnPersonal:Click()
Equal(prdOn and S[w.personalOff].shown, false, "switched on, and the note goes")
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

-- Use on all characters: the profile you're on, for every character and new ones.
local db = ForeverEnhancedCooldownManagerDB
db.profiles["Kess (Rogue) - Zephras"] = { cd = {}, util = {}, buff = {}, debuff = {}, joins = {} }
db.chars["Player-1-0009"] = "Kess (Rogue) - Zephras"
profile:Click()
Equal(S[w.profileEveryone.label].text .. " | " .. S[MenuRow("Kess (Rogue) - Zephras").users].text,
    "Use on all characters | 1 character", "a button to put your profile on every character")
w.profileEveryone:Click()
Equal(S[confirm.dialog.title].text, 'Use "Zriel (Druid) - Zephras" on all characters?', "asked first")
Equal(S[confirm.dialog].height > 112, true, "a long name wraps and the question grows to fit")
confirm.yes:Click()
Equal(db.chars["Player-1-0009"] .. " | " .. S[w.note].text,
    "Zriel (Druid) - Zephras | All your characters use Zriel (Druid) - Zephras now, and new ones will too.", "every character moves to it")
profile:Click()
Equal(S[MenuRow("Zriel (Druid) - Zephras").users].text .. " | " .. S[w.profileEveryone.label].text .. " | "
    .. S[MenuRow("Kess (Rogue) - Zephras").users].text, "all characters | On all characters | unused", "and the menu says so")
w.profileEveryone:Click()
Equal(tostring(S[confirm.shade].shown) .. " " .. S[w.note].text, "false All your characters already use Zriel (Druid) - Zephras.",
    "nothing to ask once it's on them all")
-- A character logging in for the first time starts on it.
character = { guid = "Player-1-0042", name = "Tarn", realm = "Zephras" }
Environment(true)
ns = Load(db)
Equal(ns.ProfileName() .. " | " .. tostring(db.profiles["Tarn (Druid) - Zephras"]), "Zriel (Druid) - Zephras | nil",
    "a new character starts on it, without a profile of its own")
Equal(ns.RenameProfile("Shared") and ns.EveryoneProfile(), "Shared", "renaming it keeps it on everyone")
-- Kept in the backup.
Environment(true)
ns = Load(nil)
Equal(tostring(ns.EveryoneProfile()) .. " " .. tostring(ForeverEnhancedCooldownManagerDB.chars["Player-1-0042"]), "Shared Shared",
    "the backup keeps it")

-- A character's very first login, before the game knows its name: its own
-- profile waits for the name, and one already made as "Unknown" takes it.
character = { guid = "Player-1-0077", name = "Unknown", realm = "Zephras" }
Environment()
ns = Load({ useBars = true }, true)
Equal(tostring(ns.ProfileName()), "nil", "no profile made before the game knows the name")
character.name = "Dayseeker"
Fire("PLAYER_LOGIN")
Equal(ns.ProfileName(), "Dayseeker (Druid) - Zephras", "made at login, with the name")
local early = ForeverEnhancedCooldownManagerDB
early.profiles["Unknown (Druid) - Zephras"], early.profiles["Dayseeker (Druid) - Zephras"] = early.profiles["Dayseeker (Druid) - Zephras"], nil
early.chars["Player-1-0077"] = "Unknown (Druid) - Zephras"
Environment(true)
ns = Load(early)
Equal(ns.ProfileName() .. " " .. tostring(early.profiles["Unknown (Druid) - Zephras"]), "Dayseeker (Druid) - Zephras nil",
    "one made as Unknown takes the character's name")
-- Still no name at login: a profile anyway. One you named yourself keeps its name.
character = { guid = "Player-1-0078", name = "Unknown", realm = "Zephras" }
Environment()
ns = Load({ useBars = true })
Equal(ns.ProfileName(), "Unknown (Druid) - Zephras", "still no name at login: a profile anyway")
local named = ForeverEnhancedCooldownManagerDB
named.profiles["Resto"], named.profiles["Unknown (Druid) - Zephras"] = named.profiles["Unknown (Druid) - Zephras"], nil
named.chars["Player-1-0078"] = "Resto"
character.name = "Tarn"
Environment(true)
ns = Load(named)
Equal(ns.ProfileName(), "Resto", "a profile you named keeps its name")
character = { guid = "Player-1-0001", name = "Zriel", realm = "Zephras" }

-- A profile shared across classes -------------------------------------------------------------
-- Another class's spells stay in the profile but don't show; your own class's
-- spells you haven't learned yet show greyed, in their own icon.
Environment()
ns = Load({ useBars = true })
B = ns.Bars
B:Assign("Moonfire", "cd")
local shared = ns.BarData("cd").spells
table.insert(shared, 1, "Garrote") -- a rogue's, from the same profile
table.insert(shared, "Rake") -- a druid spell not learned yet
B:Changed()
Equal(table.concat((B:Mine("cd")), ",") .. " | " .. B:Get("cd").count, "Moonfire,Rake | 1",
    "only your class's spells are yours, and only learned ones go on the bar on screen")
SlashCmdList.FECM("")
w = FECMFrame
w:Select("cd")
page = w.pages.bar
Equal(page.icons[1].name .. " " .. page.icons[1].index .. " " .. page.icons[2].name .. " " .. page.icons[2].index
    .. " " .. tostring(page.icons[3] == nil or not S[page.icons[3]].shown), "Moonfire 2 Rake 3 true",
    "the tray shows yours, each knowing its place in the list")
Equal(S[page.icons[2].texture].texture .. " " .. tostring(S[page.icons[2].texture].desaturated), "1 true",
    "a spell you haven't learned: its own icon, greyed, not a question mark")
local nav = w.nav.cd
Equal(S[nav.count].text .. " " .. tostring(S[nav.icons[2]].texture) .. " " .. tostring(S[nav.icons[2]].desaturated)
    .. " " .. tostring(S[nav.icons[3]].shown), "2 1 true false", "the bar list on the left shows the same: yours only, no question marks")
Equal(S[page.count].text, "2 icons, drag to reorder", "counted as yours")
S[page.icons[2]].scripts.OnDragStart(page.icons[2])
S[page.icons[1]].mouseOver = true
S[page.icons[2]].scripts.OnDragStop(page.icons[2])
S[page.icons[1]].mouseOver = nil
Equal(table.concat(ns.BarData("cd").spells, ","), "Garrote,Rake,Moonfire", "dragged in the tray, the rogue's spell stays put")
w:Select("layout")
local tiles = w.pages.layout.rows.cd.tiles
Equal(tiles[1].name .. " " .. tostring(S[tiles[1].texture].desaturated) .. " " .. tiles[2].name,
    "Rake true Moonfire", "the Layout page draws yours, the unlearned one greyed")
B:Clear("cd")
Equal(table.concat(ns.BarData("cd").spells, ","), "Garrote", "Clear takes yours off and leaves the rogue's")
-- The Buffs bar's slots are for your own buffs.
B:SetAura("buff", "Evasion", true)
B:SetAura("buff", "Sprint", true)
ns.BUFF_SLOTS = 2
Equal(tostring(B:SetAura("buff", "Thorns", true)) .. " " .. tostring(B:SetAura("buff", "Mark of the Wild", true))
    .. " " .. tostring(B:SetAura("buff", "Clearcasting", true)), "true true false", "a rogue's buffs don't use up your slots")
ns.BUFF_SLOTS = 16
-- Added by name, another class's spell stays off your bars too; a buff added by
-- name stays, since it can land on you whoever casts it. A debuff has to be yours.
B:Add("util", "Sinister Strike")
B:Add("buff", "Blessing of Might")
B:Add("debuff", "Garrote")
Equal(#(B:Mine("util")) .. " " .. B:Get("util").count .. " | " .. tostring(ns.Spells:ForMe("Blessing of Might", "buff"))
    .. " " .. tostring(ns.Spells:ForMe("Garrote", "debuff")) .. " " .. B:Get("debuff").count, "0 0 | true false 0",
    "a rogue's spell or debuff added by name isn't yours; a paladin's buff is")

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

-- What's new -------------------------------------------------------------------------------

-- A first install has nothing new: the version is noted and nothing shows.
Environment()
ns = Load(nil)
Equal(ns.NotesSeen(), "dev", "a first install notes the version")
for _, timer in ipairs(timers) do timer() end
Equal(FECMNotes == nil or not S[FECMNotes].shown, true, "without showing What's new")

-- After an update it shows once, a moment after login, never in combat.
Environment()
ns = Load({ useBars = true })
Equal(ns.NotesSeen(), "dev", "an update notes the new version at once")
Equal(FECMNotes, nil, "and waits a moment to show What's new")
lockdown = true
for _, timer in ipairs(timers) do timer() end
Equal(FECMNotes, nil, "not in combat")
lockdown = false
Fire("PLAYER_REGEN_ENABLED")
local notes = FECMNotes
Equal(notes ~= nil and S[notes].shown, true, "but once the fight is over")
Equal(bindings[FECMEscButton], "ESCAPE:FECMEscButton", "Escape is taken while it's open")
Equal(S[notes.version].text, "Unreleased", "headed with the notes' version")
Equal(S[notes.close.label].text, "X", "under the window's title bar")
-- Every heading and bullet, top to bottom, none overlapping.
local texts, expected = {}, 0
for _, row in ipairs(notes.flow) do
    if row.text then texts[#texts + 1] = row end
end
for _, section in ipairs(ns.NOTES[1].sections) do expected = expected + 1 + #section[2] end
Equal(#texts, expected, "every heading and bullet listed")
Equal(S[texts[1].text].text, "BLIZZARD'S COOLDOWN MANAGER", "headings in capitals")
local above
for _, row in ipairs(texts) do
    local y = -S[row.text].points[1][3]
    if above then
        Equal(y >= -S[above.text].points[1][3] + above.text:GetStringHeight(), true, "no row overlaps the one above")
    end
    if row.dot then
        local dot = -S[row.dot].points[1][3]
        Equal(dot > y and dot < y + 12, true, "each bullet's square sits beside its first line")
    end
    above = row
end
Equal(S[notes.scroll.content].height > 200, true, "the notes take their full height")
UIParent:SetHeight(800)
Fire("DISPLAY_SIZE_CHANGED")
Equal(S[notes].height, 620, "the window grows to fit, up to its limit")
UIParent:SetHeight(300)
Fire("UI_SCALE_CHANGED")
Equal(S[notes].height, 260, "and stays on a small screen, the notes scrolling")
FECMEscButton:Click()
Equal(S[notes].shown, false, "Escape closes What's new")
Equal(bindings[FECMEscButton], nil, "and hands the key back")

-- Once per version, even if the settings file is lost.
local saved = ForeverEnhancedCooldownManagerDB
Environment(true)
ns = Load(saved)
for _, timer in ipairs(timers) do timer() end
Equal(FECMNotes == notes and not S[notes].shown, true, "shown once per version")
Environment(true)
ns = Load(nil)
Equal(ns.restored and ns.NotesSeen(), "dev", "a lost settings file gets the version seen back from the backup")
for _, timer in ipairs(timers) do timer() end
Equal(FECMNotes == notes, true, "so What's new doesn't show again")

-- Any time: /ccm new, or What's new in the window.
SlashCmdList.FECM("new")
notes = FECMNotes
Equal(S[notes].shown, true, "/ccm new shows it again")
notes.done:Click()
Equal(S[notes].shown, false, "Got it closes it")
SlashCmdList.FECM("")
w = FECMFrame
Equal(S[w.news.label].text, "What's new", "What's new at the foot of the window's list")
w.news:Click()
Equal(S[notes].shown and S[w].shown, true, "opens it over the window")
FECMEscButton:Click()
Equal(not S[notes].shown and S[w].shown, true, "Escape closes What's new first")
Equal(bindings[FECMEscButton], "ESCAPE:FECMEscButton", "keeping the key for the window")
FECMEscButton:Click()
Equal(S[w].shown, false, "then the window")

-- A released version: its own notes, then the ones before it.
_G.C_AddOns = { GetAddOnMetadata = function(_, field) assert(field == "Version"); return "@project-version@" end }
Equal(ns.Version(), "dev", "a copy straight from the source is dev")
_G.C_AddOns.GetAddOnMetadata = function() return "1.1.0" end
Environment()
ns = Load({ useBars = true, notesSeen = "1.0.0" })
Equal(ns.Version(), "1.1.0", "a release has its version from the TOC")
ns.NOTES = {
    { version = "1.2.0", sections = { { "Added", { "Later." } } } },
    { version = "1.1.0", sections = { { "Added", { "This one." } }, { "Fixed", { "A bug." } } } },
    { version = "1.0.0", sections = { { "Added", { "The first." } } } },
}
for _, timer in ipairs(timers) do timer() end
notes = FECMNotes
Equal(S[notes].shown and S[notes.version].text, "Version 1.1.0", "an update to it shows its own notes")
local rows = {}
for _, row in ipairs(notes.flow) do rows[#rows + 1] = row.rule and "--" or S[row.text].text end
Equal(table.concat(rows, "|"), "ADDED|This one.|FIXED|A bug.|--|Version 1.0.0|ADDED|The first.",
    "then the release before, under a line")
SlashCmdList.FECM("")
local footerVersion
for _, f in ipairs(objects) do
    if S[f].text == "v1.1.0   /ccm to open" then footerVersion = f end
end
Equal(footerVersion ~= nil, true, "the window's footer shows the version too")
_G.C_AddOns = nil

-- Rows and which way a bar grows ---------------------------------------------------------

local function At(frame)
    local p = S[frame].points[1]
    return string.format("%s %g %g", p[1], p[4], p[5])
end
Environment()
ns = Load({ useBars = true })
B = ns.Bars
local rowBar = B:Get("cd")
for _, name in ipairs({ "Moonfire", "Wrath", "Overpower", "Attack", "Thorns" }) do B:Assign(name, "cd") end
Equal(ns.BarData("cd").perRow .. " " .. At(rowBar.icons[5]), "20 TOPLEFT 160 0", "one row until told otherwise")
B:SetOption("cd", "perRow", 2)
Equal(At(rowBar.icons[1]) .. "|" .. At(rowBar.icons[2]) .. "|" .. At(rowBar.icons[5]),
    "TOPLEFT 0 0|TOPLEFT 40 0|TOPLEFT 20 -80", "two across: rows of two, the last one centred")
Equal(string.format("%gx%g", S[rowBar].width, S[rowBar].height), "76x116", "the bar fits its rows")
B:SetOption("cd", "grow", "left")
Equal(At(rowBar.icons[1]) .. "|" .. At(rowBar.icons[2]) .. "|" .. At(rowBar.icons[5]),
    "TOPLEFT 40 0|TOPLEFT 0 0|TOPLEFT 40 -80", "growing left: the first icon on the right")
B:SetOption("cd", "grow", "right")
Equal(At(rowBar.icons[5]), "TOPLEFT 0 -80", "growing right: rows start on the left")
Equal(At(rowBar), "BOTTOMLEFT -38 190", "above the action bar, it grows right from where it was")
B:SetOption("cd", "wrap", "up")
Equal(At(rowBar.icons[1]) .. "|" .. At(rowBar.icons[3]), "BOTTOMLEFT 0 0|BOTTOMLEFT 0 40", "new rows above")
B:SetOption("cd", "showNames", true)
Equal(At(rowBar.icons[3]), "BOTTOMLEFT 0 54", "with room for names between rows")
B:SetOption("cd", "showNames", false)
-- Positions saved before rows were from the centre: the bar doesn't shift.
local cdData = ns.BarData("cd")
cdData.perRow, cdData.grow, cdData.wrap = 20, "centre", "down"
cdData.x, cdData.y, cdData.point = 10, 20, nil
B:Rebuild()
Equal(At(rowBar) .. " " .. cdData.point, "TOP 10 38 TOP", "an old position kept by the top edge instead")
B:SetOption("cd", "grow", "left")
Equal(At(rowBar), "TOPRIGHT 108 38", "and by the right edge when it grows left, still in the same place")
B:SetOption("cd", "grow", "centre")
Equal(At(rowBar), "TOP 10 38", "and back")

-- The Buffs bar: fixed spots in rows, packed icons from the bar's edge.
for _, name in ipairs({ "Thorns", "Clearcasting", "Nature's Grace" }) do B:SetAura("buff", name, true) end
local buffRows = B:Get("buff")
B:SetOption("buff", "showMissing", true)
B:SetOption("buff", "perRow", 2)
Equal(At(buffRows.holders[3]), "TOPLEFT 20 -40", "fixed buff spots go in rows too")
B:SetOption("buff", "showMissing", false)
B:SetOption("buff", "grow", "left")
Equal(S[buffRows.container].points[1][1], "RIGHT", "packed buffs line up from the edge the bar grows away from")
Equal(S[buffRows.container].groups.g1.layout.layoutIndex, ns.BUFF_SLOTS, "the first one on the right")
Equal(string.format("%gx%g", S[buffRows].width, S[buffRows].height), "116x36", "in one row: the game lays those out")

-- Kept in the backup with everything else.
cdData.perRow, cdData.grow, cdData.wrap = 3, "right", "up"
ns.SaveBars()
Environment(true)
ns = Load(nil)
cdData = ns.BarData("cd")
Equal(cdData.perRow .. " " .. cdData.grow .. " " .. cdData.wrap .. " " .. tostring(cdData.point), "3 right up BOTTOMLEFT",
    "rows and grow come back from the backup, the position held by the edge it grows from")

-- Layouts around the Personal Resource Display --------------------------------------------

function Proto:GetRect()
    local r = S[self].rect
    if r then return r[1], r[2], r[3], r[4] end
end
local prd
local function Display()
    prd = New("Frame")
    S[prd].rect = { 400, 300, 200, 20 } -- its middle 90 below the middle of the screen
    rawset(prd, "HealthBarsContainer", New("Frame", prd))
    S[prd.HealthBarsContainer].rect = { 400, 305, 200, 15 }
    rawset(prd, "PowerBar", New("Frame", prd))
    S[prd.PowerBar].rect = { 400, 300, 200, 5 }
    rawset(prd, "AlternatePowerBar", false)
    rawset(prd, "ClassFrameContainer", false)
    rawset(prd, "defaultBarWidth", 200)
    rawset(prd, "barWidthPercent", 100)
    -- Blizzard's own Bar Width setting.
    rawset(prd, "UpdateBarWidth", function(self)
        local width = self.defaultBarWidth * self.barWidthPercent / 100
        for _, part in ipairs({ self, self.HealthBarsContainer, self.PowerBar }) do part:SetWidth(width) end
    end)
    _G.PersonalResourceDisplayFrame = prd
end
Environment()
_G.hooksecurefunc = function(t, key, hook)
    local original = t[key]
    rawset(t, key, function(...)
        if original then original(...) end
        hook(...)
    end)
end
Display()
ns = Load({ useBars = true, prdSkin = false })
B = ns.Bars
local L = ns.Layout
Equal(L:Active(), false, "no layout until one is picked")
for _, name in ipairs({ "Moonfire", "Wrath", "Overpower" }) do B:Assign(name, "cd") end
B:Assign("Attack", "util")
local ok, message = L:Apply("pyramid")
Equal(ok and message, "Pyramid is set up. Tick spells for each bar, then size them to taste.", "a preset in one click")
local cd, util = ns.BarData("cd"), ns.BarData("util")
Equal(cd.perRow .. " " .. cd.size .. " " .. util.perRow .. " " .. util.size .. " " .. cd.spacing, "6 36 5 36 0",
    "each bar's icons across, its own icon size kept, and the icons flush")
Equal(At(B:Get("cd")), "BOTTOM 0 -80", "Cooldowns right on top of the display")
Equal(At(B:Get("util")), "TOP 0 -100", "Utility right under it")
Equal(At(B:Get("buff")) .. " " .. At(B:Get("debuff")), "TOP 0 -136 TOP 0 -136", "empty bars take no room")
Equal(string.format("%g %g", S[prd].width, S[prd.PowerBar].width), "216 216", "the display as wide as the widest row")
-- The rows touch unless you give them room.
L:SetGap(6)
Equal(At(B:Get("cd")) .. " " .. At(B:Get("util")) .. " " .. ns.LayoutData().gap, "BOTTOM 0 -74 TOP 0 -106 6",
    "room between the rows and the display when asked for")
L:SetGap(99)
Equal(ns.LayoutData().gap, 20, "up to 20")
L:SetGap(0)
Equal(At(B:Get("cd")), "BOTTOM 0 -80", "and touching again")
B:SetUnlocked(true)
Equal(At(B:Get("debuff")), "TOP 0 -172", "unlocked, empty bars show, so they get room")
B:SetUnlocked(false)
-- More spells than fit across: the row wraps, and the rows below move down.
B:Assign("Thorns", "util")
B:SetOption("util", "perRow", 1)
Equal(string.format("%g", S[B:Get("util")].height), "72", "Utility wraps onto a second row")
B:SetAura("buff", "Thorns", true)
Equal(At(B:Get("buff")), "TOP 0 -172", "the bar under it moves down")

-- Blizzard setting its own width puts the match back.
prd:UpdateBarWidth()
Equal(S[prd].width, 216, "the match comes back after Blizzard's Bar Width")
-- The display moved in Edit Mode: the bars follow once it closes.
S[prd].rect, S[prd.HealthBarsContainer].rect, S[prd.PowerBar].rect = { 400, 200, 200, 20 }, { 400, 205, 200, 15 }, { 400, 200, 200, 5 }
EditModeManagerFrame:Show()
EditModeManagerFrame:Hide()
Equal(At(B:Get("cd")), "BOTTOM 0 -180", "the bars follow the display")
-- Hidden until combat, the game can't say where it is: where it was last seen.
S[prd].rect, S[prd.HealthBarsContainer].rect, S[prd.PowerBar].rect = nil, nil, nil
L:Stack()
Equal(At(B:Get("cd")), "BOTTOM 0 -180", "a hidden display: where it was last seen")
-- As it shows, the bars are stacked around it again.
S[prd].rect, S[prd.HealthBarsContainer].rect, S[prd.PowerBar].rect = { 400, 250, 200, 20 }, { 400, 255, 200, 15 }, { 400, 250, 200, 5 }
prd:Hide()
prd:Show()
Equal(At(B:Get("cd")), "BOTTOM 0 -130", "stacked again as it shows")
S[prd].rect, S[prd.HealthBarsContainer].rect, S[prd.PowerBar].rect = { 400, 200, 200, 20 }, { 400, 205, 200, 15 }, { 400, 200, 200, 5 }
L:Stack()

-- Undo puts back what the preset changed.
ok, message = L:Undo()
Equal(message .. " " .. ns.BarData("cd").perRow .. " " .. tostring(L:Active()), "Put back as it was. 20 false", "Undo")
Equal(S[prd].width, 200, "and the display gets Blizzard's width back")
Equal(L.undo, nil, "once")

-- Dragging a bar leaves the layout; Line up stacks them again.
L:Apply("pyramid")
B:SetUnlocked(true)
S[B:Get("util")].cx, S[B:Get("util")].cy = 300, 300
S[B:Get("util").mover].scripts.OnDragStart()
S[B:Get("util").mover].scripts.OnDragStop()
Equal(tostring(L:Active()) .. " " .. tostring(L.moved), "false true", "a bar dragged by hand leaves the layout")
Equal(S[prd].width, 200, "the display's own width again")
B:SetUnlocked(false)
ok, message = L:LineUp()
Equal(tostring(L:Active()) .. " " .. message, "true Your bars are stacked again.", "lined up again")
Equal(At(B:Get("util")), "TOP 0 -200", "back under the display")

-- Changing rows: how many fit across, swapping bars, and moving the display.
L:SetAcross("cd", 7)
Equal(ns.BarData("cd").perRow .. " " .. tostring(ns.LayoutData().preset), "7 nil", "one more across, as your own layout")
Equal(S[prd].width, 7 * 36, "the display follows the widest row")
Equal(L:CanSwap("cd", -1), false, "the top row can't go higher")
L:Swap("util", -1)
local layout = ns.LayoutData()
Equal(table.concat(layout.above, ",") .. "|" .. table.concat(layout.below, ","), "util|cd,buff,debuff",
    "Utility swapped into the top row, Cooldowns into its place")
cd, util = ns.BarData("cd"), ns.BarData("util")
Equal(util.perRow .. " " .. util.size .. " " .. cd.perRow .. " " .. cd.size, "7 36 5 36", "the rows keep how many fit across; each bar keeps its size")
Equal(util.wrap .. " " .. At(B:Get("util")), "up BOTTOM 0 -180", "Utility sits on the display, growing up")
L:Swap("util", 1)
Equal(table.concat(layout.above, ",") .. " " .. ns.BarData("cd").perRow, "cd 7", "and back")
Equal(tostring(L:CanMoveDisplay(-1)) .. " " .. tostring(L:CanMoveDisplay(1)), "true true", "the display can move either way")
L:MoveDisplay(1)
Equal(table.concat(layout.above, ",") .. "|" .. table.concat(layout.below, ","), "cd,util|buff,debuff",
    "moving the display down puts the row under it above it")
Equal(At(B:Get("util")) .. " " .. At(B:Get("cd")), "BOTTOM 0 -180 BOTTOM 0 -144", "flush on top of it, the row above making room")
L:MoveDisplay(-1)
Equal(table.concat(layout.below, ","), "util,buff,debuff", "and back up")

-- Beside the display.
L:Apply("sides")
Equal(At(B:Get("buff")) .. " " .. ns.BarData("buff").grow, "TOPRIGHT -100 -172 left", "Buffs left of the display, growing left")
Equal(At(B:Get("debuff")) .. " " .. ns.BarData("debuff").grow, "TOPLEFT 100 -172 right", "Debuffs right of it, growing right")
Equal(table.concat(L:Rows(), ","), "cd,buff,debuff,util", "in order, the ones beside the display in the middle")
L:Swap("buff", -1)
Equal(ns.LayoutData().left .. " " .. ns.LayoutData().above[1] .. " " .. ns.BarData("buff").perRow, "cd buff 8",
    "a bar beside the display swaps with the row above, taking its shape")

-- Match off: Blizzard's width.
ns.Set("prdMatch", false)
L:Stack()
Equal(S[prd].width, 200, "matching off gives Blizzard's width back")
ns.Set("prdMatch", true)
L:Stack()

-- Never in combat.
lockdown = true
ok, message = L:Apply("wide")
Equal(tostring(ok) .. " " .. message, "false Finish combat first.", "presets wait for the fight to end")
Equal(select(2, L:SetAcross("cd", 3)), "Finish combat first.", "so do row changes")
L:Stack()
Equal(B:Get("buff").pendingLayout, true, "the Buffs bar moves after the fight")
lockdown = false
Fire("PLAYER_REGEN_ENABLED")
Equal(L.pending, nil, "and it's stacked again then")

-- Reset positions ends the layout; the backup keeps it.
L:Apply("funnel")
local kept = ns.LayoutData()
Equal(table.concat(kept.above, ","), "debuff,buff,util,cd", "everything above the display")
Environment(true)
Display()
ns = Load(nil)
Equal(tostring(ns.LayoutData().on) .. " " .. ns.LayoutData().preset .. " " .. table.concat(ns.LayoutData().above, ","),
    "true funnel debuff,buff,util,cd", "the layout comes back from the backup")
ns.Bars:ResetPositions()
Equal(ns.Layout:Active(), false, "Reset positions ends the layout")

-- The Layout page ----------------------------------------------------------------------------

Environment()
Display()
ns = Load({ useBars = true, prdSkin = false })
B, L = ns.Bars, ns.Layout
for _, name in ipairs({ "Moonfire", "Wrath", "Overpower" }) do B:Assign(name, "cd") end
SlashCmdList.FECM("")
w = FECMFrame
Equal(w.nav.layout ~= nil, true, "Layout in the window's list")
w:Select("layout")
local lp = w.pages.layout
Equal(S[lp].shown and #lp.cards, 7, "seven layouts to pick from")
Equal(S[lp.status].text, "Pick a layout to stack your bars around your resource display.", "says what it's for")
lp.cards[2]:Click()
Equal(ns.BarData("cd").perRow .. " " .. S[w.note].text, "12 Wide is set up. Tick spells for each bar, then size them to taste.",
    "clicking one sets it up")
Equal(S[lp.cards[2]].border[1], .88, "outlined in the accent while it's in use")
Equal(S[lp.status].text, "Your bars follow your Personal Resource Display.", "and says the bars follow the display")
local row = lp.rows.cd
local tiles = 0
for _, tile in ipairs(row.tiles) do if S[tile].shown then tiles = tiles + 1 end end
Equal(tiles, 12, "a tile for every icon across")
Equal(S[row.tiles[1].texture].texture ~= nil and S[row.tiles[4].texture].texture == nil, true, "your icons first, then empty spots")
Equal(S[row.across].text, "12 across", "and how many")
Equal(S[row.buttons].shown, false, "buttons out of the way")
S[row].mouseOver = true
S[row].scripts.OnEnter(row)
Equal(S[row.buttons].shown and S[w.note].text:find("the arrows swap rows", 1, true) ~= nil, true, "hovering a row shows its buttons")
row.wider:Click()
Equal(ns.BarData("cd").perRow, 13, "+ fits one more across")
row.fewer:Click()
row.fewer:Click()
Equal(ns.BarData("cd").perRow .. " " .. S[lp.rows.cd.across].text, "11 11 across", "- one fewer")
Equal(S[lp.cards[2]].border[1] == .88, false, "changed, it's your own layout")
S[row].mouseOver = nil
lp.rows.util.up:Click()
Equal(ns.LayoutData().above[#ns.LayoutData().above], "util", "an arrow swaps a row with the one above")
Equal(S[lp.rows.util].points[1][5] > S[lp.display].points[1][5], true, "drawn above it")
-- The display's own arrows move it up or down the stack.
Equal(S[lp.display.buttons].shown, false, "the display's arrows out of the way")
S[lp.display].mouseOver = true
S[lp.display].scripts.OnEnter(lp.display)
Equal(S[lp.display.buttons].shown and S[w.note].text:find("move it up or down the stack", 1, true) ~= nil, true,
    "hovering the display shows its arrows")
S[lp.display].mouseOver = nil
lp.display.down:Click()
Equal(table.concat(ns.LayoutData().above, ",") .. "|" .. table.concat(ns.LayoutData().below, ","), "util,cd|buff,debuff",
    "moved down past a row")
Equal(S[lp.rows.cd].points[1][5] > S[lp.display].points[1][5], true, "drawn that way too")
-- Icons dragged to another row move there; dragged off, they come off.
local first = lp.rows.cd.tiles[1]
local moving = first.name
S[first].scripts.OnDragStart(first)
S[lp.rows.util].mouseOver = true
S[first].scripts.OnDragStop(first)
S[lp.rows.util].mouseOver = nil
Equal(ns.BarData("util").spells[#ns.BarData("util").spells] .. " " .. S[w.note].text, moving .. " Moved " .. moving .. " to Utility.",
    "an icon dragged onto another row moves to that bar")
local last = lp.rows.util.tiles[#ns.BarData("util").spells]
S[last].scripts.OnDragStart(last)
S[last].scripts.OnDragStop(last)
Equal(tostring((B:Find(moving))) .. " " .. S[w.note].text, "nil Took " .. moving .. " off Utility.", "dragged off, it comes off")
lp.undo:Click()
Equal(ns.BarData("cd").perRow, 20, "Undo")
lp.cards[1]:Click()
Equal(S[lp.toggle.label].text, "Turn off", "a way to stop")
lp.toggle:Click()
Equal(tostring(L:Active()) .. " " .. S[lp.status].text, "false Your bars stay where you put them.", "stopped")
lp.toggle:Click()
Equal(L:Active(), true, "and Line up starts again")
-- Reset positions, now on this page: back above the action bar, out of the layout.
lp.home:Click()
Equal(tostring(L:Active()) .. " " .. tostring(ns.BarData("cd").point) .. " " .. S[w.note].text .. " " .. S[lp.toggle.label].text,
    "false nil Bars moved back above your action bar. Line up stacks them again. Line up", "Reset positions")
lp.toggle:Click()
Equal(L:Active(), true, "and Line up stacks them again")
lp.match:Click()
Equal(tostring(ns.Get("prdMatch")) .. string.format(" %g", S[prd].width), "false 200", "the match can be turned off")
lp.match:Click()
Equal(S[prd].width, 6 * 36, "and on")
-- Room between the icons in every row, flush unless you ask.
Equal(S[lp.iconSpacing.value].text, 0, "icons flush to start with")
lp.iconSpacing:Choose(3)
Equal(ns.BarData("cd").spacing .. " " .. ns.BarData("debuff").spacing .. " " .. ns.LayoutData().spacing, "3 3 3",
    "Icon spacing gives every row the same room")
lp.iconSpacing:Choose(0)
-- The row buttons are drawn in the accent, so they stand out.
Equal(S[lp.rows.cd.up.art].tint[1] .. " " .. S[lp.rows.cd.fewer.label].colour[1], "0.88 0.88", "arrows, - and + in the accent")
-- Picked up, an icon's spot shows empty until it lands.
local held = lp.rows.cd.tiles[1]
local before = table.concat(ns.BarData("cd").spells, ",")
S[held].scripts.OnDragStart(held)
Equal(Last(held.texture, "SetColorTexture"), ns.Theme.CONTROL_BORDER[1], "its spot empty while it's held")
S[lp.rows.cd].mouseOver = true
S[held].scripts.OnDragStop(held)
S[lp.rows.cd].mouseOver = nil
Equal(table.concat(ns.BarData("cd").spells, ","), before, "dropped back on its own row, nothing changes")
-- The display switched off and on from here, or your bars off.
Equal(lp.shown:GetChecked(), true, "the display shown")
lp.shown:Click()
Equal(tostring(prdOn) .. " " .. S[lp.status].text, "false Your rows sit together where your resource display would be.",
    "unticked, Blizzard's display goes off and the rows close up")
Equal(At(B:Get("cd")) .. " " .. At(B:Get("util")), "BOTTOM 0 -90 TOP 0 -90", "where it was")
lp.shown:Click()
Equal(tostring(prdOn) .. " " .. At(B:Get("util")), "true TOP 0 -100", "and back on")
lockdown = true
lp.shown:Click()
Equal(tostring(prdOn) .. " " .. S[w.note].text, "true Finish combat first.", "never in combat")
lockdown = false
w:Refresh()
ns.Set("useBars", false)
w:Refresh()
Equal(S[lp.status].text .. " " .. tostring(S[lp.toggle].shown), "Your bars are off. false", "and your bars")
lp.turnOn:Click()
Equal(B:Enabled(), true, "turned on from here")
Equal(lp.drawError, nil, "the page drew without errors")

-- A bar's page: icons per row, and which way it grows.
w:Select("cd")
local bp = w.pages.bar
Equal(bp.across.current, 6, "Icons per row on the bar's page")
bp.across:Choose(4)
Equal(ns.BarData("cd").perRow, 4, "set there too")
bp.options.grow.buttons[2]:Click()
Equal(ns.BarData("cd").grow .. " " .. S[w.note].text, "centre Your layout sets this. Change it on the Layout page.",
    "a layout decides which way its bars grow")
L:TurnOff()
w:Refresh()
bp.options.grow.buttons[2]:Click()
Equal(ns.BarData("cd").grow, "left", "otherwise it's yours to pick")
bp.options.wrap.buttons[2]:Click()
Equal(ns.BarData("cd").wrap, "up", "and where new rows go")
w:Select("buff")
Equal(S[bp.across].shown or S[bp.options.wrap].shown, false, "packed buffs stay on one row")
bp.options.showMissing:Click()
Equal(S[bp.across].shown and S[bp.options.wrap].shown, true, "fixed spots can have rows")
Equal(bp.listError, nil, "the bar page drew without errors")

-- Dragging in from any spellbook, an action bar or your bags -------------------------------

Environment()
Display()
trinket = 11111
bagItems = { { itemID = 118, hyperlink = "|cffffffff|Hitem:118|h[Minor Healing Potion]|h|r", iconFileID = 888 } }
local cursor
_G.GetCursorInfo = function()
    if cursor then return cursor[1], cursor[2], cursor[3], cursor[4] end
end
_G.ClearCursor = function() cursor = nil end
local spellNames = { [5176] = "Wrath", [467] = "Thorns", [8921] = "Moonfire", [1243] = "Power Word: Fortitude",
    [16870] = "Clearcasting", [16886] = "Nature's Grace" }
_G.C_Spell.GetSpellName = function(id) return spellNames[id] end
ns = Load({ useBars = true, prdSkin = false })
B, L = ns.Bars, ns.Layout
SlashCmdList.FECM("")
w = FECMFrame
w:Select("layout")
lp = w.pages.layout
Equal(S[lp.dragHint].text, "Drag spells from your spellbook onto a row. Hover a row to change it.",
    "the Layout page says spells can be dragged in")
cursor = { "spell", 12, "spell", 5176 }
S[lp.rows.util].scripts.OnReceiveDrag(lp.rows.util)
Equal(table.concat(ns.BarData("util").spells, ",") .. " " .. S[w.note].text, "Wrath Added Wrath to Utility.",
    "a spell dropped on a row joins that bar")
Equal(cursor, nil, "and is let go of")
cursor = { "spell", 3, "spell", 467 }
lp.rows.buff:Click()
Equal(table.concat(ns.BarData("buff").spells, ","), "Thorns", "clicking a row while holding a spell works too")
cursor = { "spell", 1, "spell", 1243 }
S[lp.rows.buff].scripts.OnReceiveDrag(lp.rows.buff)
Equal(table.concat(ns.BarData("buff").spells, ",") .. " " .. tostring(ns.CustomSpells()["Power Word: Fortitude"] ~= nil),
    "Thorns,Power Word: Fortitude true", "a spell from outside your spellbook, like another class's buff")
cursor = { "item", 118 }
S[lp.rows.cd].scripts.OnReceiveDrag(lp.rows.cd)
Equal(ns.BarData("cd").spells[1], "item:118", "an item with a cooldown, from your bags")
cursor = { "item", 11111 }
S[lp.rows.cd].scripts.OnReceiveDrag(lp.rows.cd)
Equal(ns.BarData("cd").spells[2], "slot:13", "an equipped trinket follows its slot")
cursor = { "item", 118 }
S[lp.rows.buff].scripts.OnReceiveDrag(lp.rows.buff)
Equal(S[w.note].text .. " " .. tostring(cursor), "Items can't go on the Buffs bar. nil", "no items on the Buffs bar")
cursor = { "macro", 4 }
S[lp.rows.util].scripts.OnReceiveDrag(lp.rows.util)
Equal(S[w.note].text, "Only spells and items can go on a bar.", "anything else is turned away")
lp.rows.util:Click()
Equal(S[lp.rows.util.buttons].shown, true, "with nothing held, a click just keeps the row's buttons up")
-- A bar's icons, and the bars on screen while unlocked, take drops too.
w:Select("util")
cursor = { "spell", 9, "spell", 8921 }
S[w.pages.bar.tray].scripts.OnReceiveDrag(w.pages.bar.tray)
Equal(ns.BarData("util").spells[2], "Moonfire", "dropped on a bar's icons")
B:SetUnlocked(true)
cursor = { "spell", 12, "spell", 5176 }
S[B:Get("cd").mover].scripts.OnReceiveDrag(B:Get("cd").mover)
Equal(ns.BarData("cd").spells[3] .. " " .. #ns.BarData("util").spells, "Wrath 1", "dropped on a bar on screen, it moves there")
S[B:Get("cd").mover].scripts.OnMouseUp(B:Get("cd").mover)
Equal(#ns.BarData("cd").spells, 3, "a click with nothing held adds nothing")
Equal(lp.drawError, nil, "the Layout page drew without errors")

-- Countdown numbers in the game's own font: a heavy outline on big numbers, no shadow.
Equal(Last(FECMFont18, "SetFont", 1) .. " " .. Last(FECMFont18, "SetFont", 3) .. " " .. Last(FECMFont13, "SetFont", 3),
    "Fonts\\FRIZQT__.TTF THICKOUTLINE OUTLINE", "Friz Quadrata, thick outline from 16 up")
Equal(Last(FECMFont18, "SetShadowOffset", 1), 0, "no drop shadow")

-- Flush against the bars you can see ------------------------------------------------------

Environment()
local power = 0 -- the main bar's power: 0 mana (caster form), 1 rage (bear form)
_G.UnitPowerType = function() return power end
Display()
S[prd].rect = { 400, 280, 200, 60 } -- Blizzard's frame keeps a minimum height
local extra = New("Frame", prd)
rawset(extra, "powerName", "MANA")
S[extra].rect = { 400, 294, 200, 6 }
rawset(prd, "AlternatePowerBar", extra)
rawset(prd, "UpdatePowerBar", function() end)
ns = Load({ useBars = true, prdSkin = false, prdCombo = true })
B, L = ns.Bars, ns.Layout
B:Assign("Moonfire", "cd")
B:Assign("Attack", "util")
L:Apply("pyramid")
Equal(At(B:Get("cd")) .. " " .. At(B:Get("util")), "BOTTOM 0 -80 TOP 0 -100",
    "flush against the health and mana bars, not the frame around them or the tucked-away extra mana bar")
power = 1
prd:UpdatePowerBar()
Equal(At(B:Get("cd")) .. " " .. At(B:Get("util")), "BOTTOM 0 -80 TOP 0 -106", "in bear form the extra mana bar shows, and Utility sits under it")
Equal(ns.Resource:ComboRow(), nil, "no combo points in bear form")
-- Cat form: the addon's combo points under the extra mana bar, and Utility under them.
power = 3
prd:UpdatePowerBar()
local comboRow = ns.Resource:ComboRow()
Equal(comboRow ~= nil and S[comboRow].shown and S[comboRow].points[1][2] == extra, true, "cat form: combo points under the lowest bar")
S[comboRow].rect = { 400, 280, 200, 8 }
L:Stack()
Equal(At(B:Get("util")), "TOP 0 -120", "and Utility under the combo points while they show")
power = 0
prd:UpdatePowerBar()
Equal(tostring(ns.Resource:ComboRow()) .. " " .. tostring(S[comboRow].shown), "nil false", "gone in caster form")
Equal(At(B:Get("util")), "TOP 0 -100", "back up against the mana bar in caster form")
-- A form change in a fight: the cooldown bars follow at once, the Buffs bar after.
B:SetAura("buff", "Thorns", true)
lockdown = true
power = 1
prd:UpdatePowerBar()
Equal(At(B:Get("util")) .. " " .. tostring(B:Get("buff").pendingLayout), "TOP 0 -106 true",
    "in a fight Utility moves at once; the Buffs bar waits")
lockdown = false
Fire("PLAYER_REGEN_ENABLED")
Equal(At(B:Get("buff")), "TOP 0 -142", "and catches up once it's over")
power = 0
prd:UpdatePowerBar()
-- The display switched off: the rows close up where it was.
prdOn = false
L:Stack()
Equal(At(B:Get("cd")) .. " " .. At(B:Get("util")), "BOTTOM 0 -90 TOP 0 -90", "with the display off, the rows meet where it was")
prdOn = true
L:Stack()
Equal(At(B:Get("util")), "TOP 0 -100", "and part again when it's back")

-- Your cast bar ------------------------------------------------------------------------------

Environment()
Display()
_G.PlayerCastingBarFrame = New("Frame")
local native = PlayerCastingBarFrame
ns = Load({ useBars = true, prdSkin = false })
B, L = ns.Bars, ns.Layout
local C = ns.CastBar
local cb = C.row
B:Assign("Moonfire", "cd")
B:Assign("Attack", "util")
L:Apply("pyramid")
Equal(tostring(C:Room()) .. " " .. tostring(S[cb].shown) .. " " .. S[native].alpha .. " " .. At(B:Get("util")),
    "nil false 1 TOP 0 -100", "off by default: no room, and Blizzard's cast bar left alone")
ns.Set("castBar", true)
C:Apply()
Equal(At(cb) .. string.format(" %g ", S[cb].width) .. At(B:Get("util")), "TOP 0 -104 200 TOP 0 -122",
    "on: under the display, as wide, and Utility moves down to make room")
Equal(S[cb].shown and S[cb].alpha .. " " .. S[native].alpha, "0 0", "nothing showing between casts, and Blizzard's hidden")
native:SetAlpha(1)
Equal(S[native].alpha, 0, "and it stays hidden when Blizzard shows it for a cast")
-- A cast: its name, icon and length, filling with the time left.
clock = 100
local casting = { "Wrath", "Wrath", 136006, 100000, 101500, false, "cast-1" }
_G.UnitCastingInfo = function(unit) assert(unit == "player"); return table.unpack(casting) end
Fire("UNIT_SPELLCAST_START", "player", "cast-1", 5176)
Equal(S[cb].alpha .. " " .. S[cb.bar.name].text .. " " .. S[cb.icon].texture .. " " .. Last(cb.bar, "SetMinMaxValues", 2), "1 Wrath 136006 1.5",
    "a cast shows its name and icon, as long as the cast")
Equal(Last(cb.bar, "SetStatusBarColor", 1) .. " " .. Last(cb.bar, "SetStatusBarColor", 2), "1 0.7", "in Blizzard's gold")
clock = 100.5
S[cb].scripts.OnUpdate(cb, .5)
Equal(string.format("%g %g", Last(cb.bar, "SetValue", 1), Last(cb.bar.time, "SetFormattedText", 2)), "0.5 1", "filling, with the time left")
Fire("UNIT_SPELLCAST_FAILED", "player", "cast-2", 1)
Equal(S[cb.bar.name].text, "Wrath", "another spell failing doesn't touch it")
Fire("UNIT_SPELLCAST_STOP", "player", "cast-1", 5176)
Equal(string.format("%g", Last(cb.bar, "SetValue", 1)), "1.5", "finished: full")
clock = 101
S[cb].scripts.OnUpdate(cb, .5)
Equal(string.format("%.2f", S[cb].alpha), "0.67", "then it fades")
clock = 101.3
S[cb].scripts.OnUpdate(cb, .3)
Equal(tostring(S[cb].alpha) .. " " .. tostring(S[cb].scripts.OnUpdate), "0 nil", "and it's gone")
-- Interrupted: red, saying so.
casting[7] = "cast-3"
Fire("UNIT_SPELLCAST_START", "player", "cast-3", 5176)
Fire("UNIT_SPELLCAST_INTERRUPTED", "player", "cast-3", 5176)
Equal(S[cb.bar.name].text .. " " .. Last(cb.bar, "SetStatusBarColor", 1), "Interrupted 0.85", "interrupted: red, saying so")
-- A channel: green, draining.
_G.UnitChannelInfo = function() return "Tranquility", "Tranquility", 136107, 102000, 110000, false, false, 740 end
clock = 102
Fire("UNIT_SPELLCAST_CHANNEL_START", "player", nil, 740)
clock = 104
S[cb].scripts.OnUpdate(cb, 2)
Equal(Last(cb.bar, "SetStatusBarColor", 2) .. " " .. string.format("%g", Last(cb.bar, "SetValue", 1)), "0.8 6",
    "a channel: green, draining as it goes")
Fire("UNIT_SPELLCAST_CHANNEL_STOP", "player", nil, 740, "Creature-0-1")
Equal(S[cb.bar.name].text, "Interrupted", "a channel cut short says so too")
_G.UnitChannelInfo = function() return nil end
-- Times the game keeps secret: Blizzard's own bar shows that cast.
casting = { "Wrath", "Wrath", 136006, SECRET, SECRET, false, "cast-4" }
Fire("UNIT_SPELLCAST_START", "player", "cast-4", 5176)
native:SetAlpha(1) -- Blizzard's own bar starting the same cast
Equal(S[cb].alpha .. " " .. S[native].alpha, "0 1", "a cast with secret times: Blizzard's bar shows it")
casting = { "Wrath", "Wrath", 136006, 105000, 106500, false, "cast-5" }
Fire("UNIT_SPELLCAST_START", "player", "cast-5", 5176)
Equal(S[cb].alpha .. " " .. S[native].alpha, "1 0", "and yours takes over again at the next")
Fire("UNIT_SPELLCAST_STOP", "player", "cast-9", 1)
clock = 105.5
S[cb].scripts.OnUpdate(cb, .5)
Equal(string.format("%g", Last(cb.bar, "SetValue", 1)), "0.5", "another spell stopping doesn't end it")
-- Choices: icon, height and colour.
ns.Set("castIcon", false)
ns.Set("castHeight", 24)
ns.Set("castColour", "blue")
C:Apply()
Equal(tostring(S[cb.icon].shown) .. " " .. S[cb].height .. " " .. At(B:Get("util")) .. " " .. Last(cb.bar, "SetStatusBarColor", 1),
    "false 24 TOP 0 -128 " .. ns.Style:BarColour("blue")[1], "no icon, taller (the rows move again), in your colour")
-- The display switched off: the bar sits where it was, between the rows.
prdOn = false
L:Stack()
Equal(At(cb) .. " " .. At(B:Get("util")), "TOP 0 -90 TOP 0 -114", "with the display off, it sits where the display was")
prdOn = true
-- Without a layout it still goes under the display.
L:TurnOff()
ns.Bars:ResetPositions()
L:Stack()
Equal(At(cb), "TOP 0 -104", "without a layout, under the display")
-- Off again, even mid-cast: no room, Blizzard's bar back.
casting[7] = "cast-6"
Fire("UNIT_SPELLCAST_START", "player", "cast-6", 5176)
rawset(native, "casting", true) -- Blizzard's own bar has the cast too
ns.Set("castBar", false)
C:Apply()
L:LineUp()
Equal(tostring(S[cb].shown) .. " " .. S[native].alpha .. " " .. At(B:Get("util")) .. " " .. tostring(S[cb].scripts.OnUpdate),
    "false 1 TOP 0 -100 nil", "off: the rows close up, Blizzard's bar is back mid-cast, and yours drops the cast")
rawset(native, "casting", nil)
-- The Cast bar page: a live preview, and the Layout page draws it.
ns.Set("castBar", true)
C:Apply()
SlashCmdList.FECM("")
w = FECMFrame
w:Select("cast")
local cp = w.pages.cast
Equal(S[cp].shown and S[cp.status].text, "Under your Personal Resource Display. Blizzard's cast bar is hidden.", "its own page")
Equal(S[cp.sample.bar.name].text .. " " .. tostring(S[cp.sample.icon].shown) .. " " .. S[cp.sample].height, "Hearthstone false 24",
    "the preview follows your choices")
S[cp.sample].scripts.OnUpdate(cp.sample, 1)
Equal(string.format("%g", Last(cp.sample.bar, "SetValue", 1)), "1", "and fills as you watch")
cp.swatches[3]:Click()
Equal(S[cp.chosen].text, "Blizzard's gold", "clicking your colour again goes back to Blizzard's")
cp.icon:Click()
Equal(tostring(ns.Get("castIcon")) .. " " .. tostring(S[cp.sample.icon].shown), "true true", "the icon comes back, in the preview too")
w:Select("layout")
Equal(S[w.pages.layout.castStrip].shown, true, "the Layout page draws it under the display")
Equal(w.pages.layout.drawError, nil, "the Layout page drew without errors")
cp.shown:Click()
Equal(tostring(ns.Get("castBar")) .. " " .. tostring(S[w.pages.layout.castStrip].shown), "false false", "switched off from its page")
Equal(#printed, 0, "no errors from the cast bar")
-- Its height is in the backup too, within its limits.
Environment(true)
ns = Load(nil)
Equal(ns.Get("castHeight"), 24, "the height comes back from the backup")
cvars.FECMBackup = cvars.FECMBackup:gsub("castHeight=24", "castHeight=99")
Environment(true)
ns = Load(nil)
Equal(ns.Get("castHeight"), 18, "one out of range is ignored")

-- Borders and shadows on your bars -------------------------------------------------------------

Environment()
ns = Load({ useBars = true })
B = ns.Bars
B:Assign("Moonfire", "cd")
B:SetAura("buff", "Thorns", true)
local cdBar, buffBar = B:Get("cd"), B:Get("buff")
local function Shown(ring) return tostring(S[ring[1]].shown) end
Equal(Shown(cdBar.icons[1].decor.border) .. " " .. Shown(cdBar.decor.shadow[1]), "false false", "none to start with")
SlashCmdList.FECM("")
w = FECMFrame
w:Select("look")
w.iconBorder.buttons[2]:Click()
w.iconShadow.buttons[3]:Click()
Equal(ns.Get("iconBorder") .. " " .. ns.Get("iconShadow"), "icon bar", "picked on the Look page")
Equal(Shown(cdBar.icons[1].decor.border) .. " " .. Shown(cdBar.decor.shadow[1]) .. " " .. Shown(cdBar.decor.border),
    "true true false", "a border round each icon and a shadow round each bar")
Equal(Shown(buffBar.holders[1].decor.border), "true", "the Buffs bar's icons too")
Equal(Shown(w.sampleIcons.icons[1].decor.border) .. " " .. Shown(w.sampleIcons.decor.shadow[1]), "true true",
    "shown in the Look page's preview")
Equal(Shown(ns.CastBar.row.decor.shadow[1]) .. " " .. Shown(ns.CastBar.row.decor.border), "true false",
    "your cast bar gets the shadow, keeping its own edges")
B:Assign("Wrath", "cd")
Equal(Shown(cdBar.icons[2].decor.border), "true", "new icons get it as they're made")
w.iconBorder.buttons[1]:Click()
w.iconShadow.buttons[1]:Click()
Equal(Shown(cdBar.icons[1].decor.border) .. " " .. Shown(cdBar.decor.shadow[1]) .. " " .. Shown(ns.CastBar.row.decor.shadow[1]),
    "false false false", "and Off takes them away")
Equal(#printed, 0, "no errors from borders and shadows")

-- Each class's debuffs, from Blizzard's own spell data -------------------------------------

local function Has(list, name)
    for _, item in ipairs(list) do if item == name then return true end end
    return false
end
local druid = ns.DEBUFFS.DRUID
Equal(tostring(Has(druid, "Moonfire")) .. " " .. tostring(Has(druid, "Faerie Fire")) .. " " .. tostring(Has(druid, "Rake")),
    "true true true", "a druid's debuffs: Moonfire, Faerie Fire, Rake")
Equal(tostring(Has(druid, "Wrath")) .. " " .. tostring(Has(druid, "Thorns")), "false false", "not a plain nuke or a buff")
Equal(tostring(Has(ns.DEBUFFS.ROGUE, "Rupture")) .. " " .. tostring(Has(ns.DEBUFFS.WARRIOR, "Sunder Armor")), "true true",
    "every class has its own")
Equal(ns.RANKS["Jeff Dummy 1"], nil, "no test dummies")

-- Taking a bar out, putting it back, and Reset ----------------------------------------------

Environment()
Display()
ns = Load({ useBars = true, prdSkin = false })
B, L = ns.Bars, ns.Layout
B:Assign("Moonfire", "cd")
B:Assign("Attack", "util")
B:SetAura("buff", "Thorns", true)
B:SetAura("debuff", "Moonfire", true)
L:Apply("pyramid")
SlashCmdList.FECM("")
w = FECMFrame
w:Select("layout")
lp = w.pages.layout
local confirm = w.confirm
lp.rows.debuff.out:Click()
Equal(S[confirm.shade].shown and S[confirm.dialog.title].text, "Take Debuffs out of your layout?", "the x asks first")
confirm.no:Click()
Equal(L:IsHidden("debuff"), false, "Cancel leaves it in")
lp.rows.debuff.out:Click()
confirm.yes:Click()
Equal(tostring(L:IsHidden("debuff")) .. " " .. tostring(S[B:Get("debuff")].shown), "true false",
    "taken out: it doesn't show, even with a debuff on it")
Equal(tostring(S[lp.rows.debuff].shown) .. " " .. tostring(S[lp.outButtons.debuff].shown), "false true",
    "its row is gone from the drawing, with a button to put it back")
Equal(table.concat(L:Rows(), ","), "cd,util,buff", "and from the rows you can swap")
Equal(table.concat(ns.BarData("debuff").spells, ","), "Moonfire", "its spells stay")
w:Select("debuff")
Equal(S[w.pages.bar.putBack].shown, true, "its own page says it's out, with Put back")
w:Select("layout")
-- Kept in the backup.
Environment(true)
Display()
ns = Load(nil)
Equal(tostring(ns.Layout:IsHidden("debuff")) .. " " .. ns.LayoutData().base, "true pyramid", "the backup keeps it out")
B, L = ns.Bars, ns.Layout
SlashCmdList.FECM("")
w = FECMFrame
w:Select("layout")
lp = w.pages.layout
confirm = w.confirm
lp.outButtons.debuff:Click()
Equal(tostring(L:IsHidden("debuff")) .. " " .. tostring(S[B:Get("debuff")].shown), "false true", "put back, it shows again")
-- All four out: the last button wraps clear of Unlock bars and Reset positions.
for _, key in ipairs(ns.BAR_KEYS) do L:TakeOut(key) end
w:Refresh()
local wrapped = S[lp.outButtons.debuff].points[1]
Equal(wrapped[4] .. " " .. wrapped[5] .. " " .. S[lp.outButtons.buff].points[1][5], "80 31 9", "the last one wraps to a second line")
for _, key in ipairs(ns.BAR_KEYS) do L:PutBack(key) end
w:Refresh()
-- Reset: the preset as first set up, asked first.
L:SetGap(4)
L:SetSpacing(3)
L:SetAcross("cd", 9)
lp.reset:Click()
Equal(S[confirm.dialog.title].text, "Reset your layout?", "Reset asks first")
confirm.yes:Click()
local reset = ns.LayoutData()
Equal(reset.gap .. " " .. reset.spacing .. " " .. ns.BarData("cd").perRow .. " " .. tostring(reset.preset) .. " " .. S[w.note].text,
    "0 0 6 pyramid Pyramid is back as it was first set up.", "the preset back as it was, rows and icons flush")
L:Undo()
Equal(ns.BarData("cd").perRow .. " " .. ns.LayoutData().gap, "9 4", "and Undo puts your changes back")

-- Finding a debuff and picking its spot ------------------------------------------------------

L:Reset()
w:Refresh()
local search = lp.search
S[search].scripts.OnEditFocusGained(search)
Equal(S[lp.results].shown and lp.found[1].spell, "Moonfire", "your class's debuffs, the ones you know first")
search:SetText("fae")
S[search].scripts.OnTextChanged(search, true)
Equal(lp.found[1].spell .. " " .. tostring(S[lp.found[2]].shown), "Faerie Fire false", "narrowed as you type")
Equal(S[lp.found[1].name].colour[1], ns.Theme.MUTED[1], "greyed while you haven't learned it")
lp.found[1]:Click()
Equal(S[lp.dragHint].text .. " " .. tostring(S[lp.cancel].shown) .. " " .. tostring(S[lp.rows.debuff.target].shown),
    "Click a spot in the Debuffs row for Faerie Fire. true true", "then it asks for a spot in the Debuffs row")
lp.rows.cd.tiles[1]:Click()
Equal(S[w.note].text .. " " .. #ns.BarData("debuff").spells, "Debuffs go in the Debuffs row. 1", "only there")
lp.rows.debuff.tiles[1]:Click()
Equal(table.concat(ns.BarData("debuff").spells, ",") .. " " .. S[w.note].text, "Faerie Fire,Moonfire Added Faerie Fire to Debuffs.",
    "put in the spot you picked")
Equal(S[lp.dragHint].text .. " " .. tostring(S[lp.cancel].shown), "Drag spells from your spellbook onto a row. Hover a row to change it. false",
    "and back to normal")
-- Changed your mind: Cancel.
search:SetText("demoral")
S[search].scripts.OnTextChanged(search, true)
lp.found[1]:Click()
Equal(S[lp.dragHint].text, "Click a spot in the Debuffs row for Demoralizing Roar.", "another debuff picked")
lp.cancel:Click()
Equal(tostring(S[lp.cancel].shown) .. " " .. tostring(S[lp.rows.debuff.target].shown), "false false", "Cancel puts things back")
lp.rows.debuff.tiles[1]:Click()
Equal(table.concat(ns.BarData("debuff").spells, ","), "Faerie Fire,Moonfire", "and nothing is added")
Equal(lp.drawError, nil, "the Layout page drew without errors")

print = _G.print
io.write("Bars and window checks passed: " .. checks .. " assertions.\n")
