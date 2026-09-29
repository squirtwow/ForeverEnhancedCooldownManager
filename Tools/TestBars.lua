-- Run the actual bars files (Core, Style, Spells, Buffs, Bars, the window) against a
-- mock game: spellbook ranks, secret cooldowns in combat, usable and range
-- tints, showing and hiding, dragging, settings kept over a reload, and the panel.
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
    for _, file in ipairs({ "Core.lua", "Style.lua", "Skin.lua", "Resource.lua", "CastBar.lua", "Ranks.lua", "Spells.lua", "Buffs.lua", "Bars.lua",
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

-- Kept over a reload ----------------------------------------------------------------------
-- Everything lives in the saved settings; nothing goes into the game's own.

do
    Equal(next(cvars), nil, "no game settings written")
    local saved = ForeverEnhancedCooldownManagerDB
    Environment(true)
    ns = Load(saved)
    B = ns.Bars
    Equal(B:Enabled(), true, "bars on again after a reload")
    Equal(table.concat(ns.BarData("cd").spells, ","), "Overpower,Moonfire", "bar spells kept")
    Equal(ns.BarData("cd").x, 20, "bar position kept")
    Equal(ns.BarData("util").x, nil, "unmoved bar keeps its default spot")
    Equal(B:Get("cd").count, 2, "and drawn")
    Equal(ns.firstInstall, false, "a kept settings file isn't a first install")

    -- Anything unexpected in the saved settings is put right at load.
    Environment()
    ns = Load({ useBars = true, bars = { cd = { size = 9999, spells = { "A", 7, "", "B" }, x = "nope", y = 3, hideReady = "maybe" },
        evil = { size = 3 } } })
    local data = ns.BarData("cd")
    Equal(data.size, 64, "bad sizes clamped")
    Equal(table.concat(data.spells, ","), "A,B", "only names kept in a list")
    Equal(data.x, nil, "bad positions dropped")
    Equal(data.hideReady, false, "bad flags off")
    Equal(ns.BarData("evil"), nil, "unknown bars ignored")
end

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
local kept = ForeverEnhancedCooldownManagerDB
Equal(tostring(kept.bars.buff.showMissing) .. " " .. tostring(kept.bars.buff.showTimer), "false true", "Buffs bar options saved")
Equal(table.concat(kept.profiles[ns.ProfileName()].buff, ","), "Thorns", "and its list, in your profile")
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
kept = ForeverEnhancedCooldownManagerDB
Environment(true)
ns = Load(kept)
B = ns.Bars
Equal(Shape("buff"), "Thorns, Walk on Air+Nature's Grace+Clearcasting", "joins kept over a reload")
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
-- Icons the Buffs page used and this one doesn't go with their join buttons
-- and lines, which sit on the tray, not the icon.
Equal(#barPage.icons >= 4, true, "the Buffs page drew more icons than Cooldowns has")
for n = 3, #barPage.icons do
    local icon = barPage.icons[n]
    Equal(tostring(S[icon].shown) .. " " .. tostring(S[icon.link].shown) .. " " .. tostring(S[icon.bridge].shown), "false false false",
        "an icon not in use goes with its join button and line")
end
do
    -- Taking the last of a group off with its x leaves no line or button behind.
    win:Select("buff")
    local last = barPage.icons[4]
    Equal(tostring(S[last.link].shown) .. " " .. tostring(S[last.bridge].shown), "true true", "the last Buffs icon is joined")
    last.remove:Click()
    Equal(#ns.BarData("buff").spells .. " " .. tostring(S[last.link].shown) .. " " .. tostring(S[last.bridge].shown), "3 false false",
        "taken off, its join button and line go too")
    -- A full bar: splitting a group or dragging one out of it would need
    -- another icon, so it's refused, saying why.
    ns.BUFF_SLOTS = 2
    barPage.icons[3].link:Click()
    Equal(tostring(B:Joined("buff", 3)) .. " " .. S[win.note].text, "true Buffs is full.", "a split past the bar's slots is refused")
    S[barPage.icons[3]].scripts.OnDragStart(barPage.icons[3])
    S[barPage.icons[1]].mouseOver = true
    S[barPage.icons[3]].scripts.OnDragStop(barPage.icons[3])
    S[barPage.icons[1]].mouseOver = nil
    Equal(Shape("buff") .. " " .. S[win.note].text, "Thorns, Walk on Air+Nature's Grace Buffs is full.",
        "and so is dragging one out of its group")
    ns.BUFF_SLOTS = 16
    -- Closing the window mid-drag: the icon's spot comes back, nothing is
    -- left on the cursor, and a late drop takes nothing off.
    local held = barPage.icons[1]
    S[held].scripts.OnDragStart(held)
    Equal(tostring(S[held].alpha) .. " " .. tostring(S[barPage.ghost].shown), "0 true", "picked up, it follows the cursor")
    barPage:Hide()
    Equal(tostring(S[held].alpha) .. " " .. tostring(S[barPage.ghost].shown), "1 false",
        "closed mid-drag, its spot shows again and nothing is left on the cursor")
    S[held].scripts.OnDragStop(held)
    Equal(#ns.BarData("buff").spells, 3, "a late drop takes nothing off")
    barPage:Show()
end
Equal(#printed, 0, "no errors")

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
Equal(ForeverEnhancedCooldownManagerDB.bars.cd.outOfCombat, "hide", "the choice is saved")

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
Equal(ForeverEnhancedCooldownManagerDB.bars.cd.showTimer, false, "that choice saved")
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
Equal(ForeverEnhancedCooldownManagerDB.listItems, true, "and saved")

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

kept = ForeverEnhancedCooldownManagerDB
Environment(true)
ns = Load(kept)
Equal(ns.CustomSpells()["Power Word: Fortitude"][1], 1243, "added spells kept over a reload")
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
kept = ForeverEnhancedCooldownManagerDB
Environment(true)
ns = Load(kept)
Equal(table.concat(ns.BarData("util").spells, ","), "Moonfire,Moonfire@2", "fixed ranks kept over a reload")

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

-- Sharing: renaming follows every character; a shared one can be deleted
-- too, and says how many others use it (the menu asks first).
ns.UseProfile(mine)
Equal(ns.ProfileUsers(mine), 2, "two characters can share a profile")
ok, message = ns.RenameProfile("Balance")
Equal(ok and saved.chars["Player-1-0001"], "Balance", "renaming updates every character using it")
Equal(saved.profiles[mine], nil, "the old name is gone")
do
    local can, name, others = ns.CanDeleteProfile("Balance")
    Equal(tostring(can) .. " " .. name .. " " .. others, "true Balance 1", "a profile another character uses can be deleted, counting them")
end
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

-- Profiles are kept over a reload; a lost settings file is a first install -----------------

character = { guid = "Player-1-0001", name = "Zriel", realm = "Zephras" }
Environment(true)
ns = Load(saved)
Equal(ns.ProfileName(), "Balance", "each character's profile kept over a reload")
Equal(ns.BarData("buff").spells[1], "Power Word: Fortitude", "with its lists")
Equal(ns.CustomSpells()["Power Word: Fortitude"][1], 1243, "and added spells")
Equal(ForeverEnhancedCooldownManagerDB.chars["Player-1-0002"], mine .. " 2", "who uses what, too")
Equal(tostring(ns.firstInstall) .. " " .. #printed, "false 0", "a normal reload, with nothing to say")

-- Only the saved settings count: game settings an earlier build kept are
-- never read, so a lost file starts afresh.
Environment()
cvars.FECMBackup = "accent=teal;useBars=1"
cvars.FECMBackupBars0, cvars.FECMBackupBars1 = "1", "cd.size=40;cd.spells=Moonfire"
cvars.ClassicCooldownManagerBackup = "accent=blue;classicBars=1"
ns = Load(nil)
Equal(tostring(ns.firstInstall) .. " " .. ns.Get("accent") .. " " .. tostring(ns.Get("useBars")), "true orange false",
    "a lost settings file is a first install; old backups aren't read")
Equal(#ns.BarData("cd").spells .. " " .. ns.BarData("cd").size .. " " .. ns.ProfileName(), "0 36 Zriel (Druid) - Zephras",
    "starting empty, on a profile of your own")
Equal(#printed, 0, "with nothing printed")
ns.Set("accent", "blue")
ns.SetBarColour(123, "blue")
ns.SetNotesSeen("x")
do
    local count = 0
    for _ in pairs(cvars) do count = count + 1 end
    Equal(count .. " " .. cvars.FECMBackup, "4 accent=teal;useBars=1", "and changes are never written there")
end

-- A kept file: an old login count dropped, and everything checked at load.
do
    Environment()
    ns = Load({ session = 63, accent = "pink", castHeight = 99, useBars = true, bars = { cd = { size = 9999, x = "no" } },
        layout = { on = "yes", above = { "cd", "cd", "nope" } }, custom = { [""] = { 1 }, Good = { 5 } },
        barColours = { [5] = "nope", [6] = "blue" } })
    local db = ForeverEnhancedCooldownManagerDB
    Equal(tostring(ns.firstInstall) .. " " .. tostring(db.session), "false nil", "not a first install, and the login count is gone")
    Equal(ns.Get("accent") .. " " .. ns.Get("castHeight") .. " " .. tostring(ns.Get("useBars")), "orange 18 true",
        "bad settings fall back, good ones stay")
    Equal(db.bars.cd.size .. " " .. tostring(db.bars.cd.x), "64 nil", "bar data put right at load")
    Equal(tostring(db.layout.on) .. " " .. table.concat(db.layout.above, ","), "false cd", "the layout too")
    Equal(tostring(db.custom[""]) .. " " .. tostring(db.custom.Good ~= nil), "nil true", "added spells too")
    Equal(tostring(db.barColours[5]) .. " " .. db.barColours[6], "nil blue", "and each bar's colour")
end

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
Equal(S[w.versionText].text, "dev   /ccm to open", "the footer shows the version")
w:Refresh()
Equal(S[w.versionText].text, "dev   /ccm to open", "and keeps it")

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
-- No saved-settings section: More from Squirt sits under the tour and Discord.
Equal(tostring(w.kept) .. " " .. tostring(Heading("SAVED SETTINGS") ~= nil), "nil false", "no saved-settings text or heading")
Equal(S[Heading("MORE FROM SQUIRT")].points[1][3], -236, "More from Squirt closes the gap")
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

-- Alt+Z hides the interface, running the window's OnHide though it's still
-- shown: Escape goes back to the game, which brings the interface back.
do
    ns.ShowWindow()
    Equal(bindings[FECMEscButton], "ESCAPE:FECMEscButton", "open again, Escape is borrowed")
    S[UIParent].shown = false
    S[w].scripts.OnHide(w)
    Equal(bindings[FECMEscButton], nil, "the interface hidden: Escape handed back")
    S[UIParent].shown = true
    S[w].scripts.OnShow(w)
    Equal(bindings[FECMEscButton], "ESCAPE:FECMEscButton", "and borrowed again as it comes back")
    -- Closing a window that's already off screen runs no OnHide: the key is
    -- still handed back.
    local onHide = S[w].scripts.OnHide
    S[w].scripts.OnHide = nil
    S[UIParent].shown = false
    FECMEscButton:Click()
    S[w].scripts.OnHide = onHide
    S[UIParent].shown = true
    Equal(tostring(S[w].shown) .. " " .. tostring(bindings[FECMEscButton]), "false nil", "Escape closes it and doesn't keep the key")

    -- Closed mid-drag, nothing keeps following the cursor: the window, a
    -- slider or a list's scroll thumb.
    ns.ShowWindow()
    S[w].last.StopMovingOrSizing = nil
    w:Hide()
    Equal(S[w].last.StopMovingOrSizing ~= nil, true, "closing the window stops it moving")
    local slider = ns.Theme:Slider(UIParent, "Size", { 1, 10 }, 1, 200, function() end)
    slider:Set(5)
    S[slider.track].scripts.OnMouseDown(slider.track)
    Equal(S[slider.track].scripts.OnUpdate ~= nil, true, "a slider follows the cursor while held")
    slider.track:Hide()
    Equal(S[slider.track].scripts.OnUpdate, nil, "and stops once hidden")
    local thumb = ns.Theme:Scroll(UIParent, 100).thumb
    S[thumb].shown = true
    S[thumb].scripts.OnMouseDown(thumb)
    Equal(thumb.drag ~= nil, true, "a scroll thumb follows it while held")
    thumb:Hide()
    Equal(thumb.drag, nil, "and stops once hidden")
end

SlashCmdList.FECM("check")
Equal(S[w].shown, true, "anything after /ccm but new just opens the window")
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
Equal(S[confirm.dialog.detail].text, "You're using it, so you'll move to a new, empty profile of your own. Another character uses it, "
    .. "and gets a new, empty profile of its own at its next login. This can't be undone.",
    "a profile another character uses is asked about too, saying what happens to that character")
confirm.no:Click()
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
-- Kept over a reload.
Environment(true)
ns = Load(db)
Equal(tostring(ns.EveryoneProfile()) .. " " .. tostring(ForeverEnhancedCooldownManagerDB.chars["Player-1-0042"]), "Shared Shared",
    "kept over a reload")

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

-- A profile other characters use, even ones since deleted, can be deleted:
-- they get a profile of their own at their next login.
do
    local function Lists() return { cd = {}, util = {}, buff = {}, debuff = {}, joins = {} } end
    Environment()
    ns = Load({ useBars = true, profiles = { Mine = Lists(), Dead = Lists(), Shared = Lists() },
        chars = { ["Player-1-0001"] = "Mine", ["Player-1-0099"] = "Dead", ["Player-1-0002"] = "Shared", ["Player-1-0003"] = "Shared" } })
    local db = ForeverEnhancedCooldownManagerDB
    local can, name, others = ns.CanDeleteProfile("Dead")
    Equal(tostring(can) .. " " .. name .. " " .. others, "true Dead 1", "a profile a deleted character used can go")
    Equal(select(3, ns.CanDeleteProfile("Mine")), 0, "your own counts no others")
    SlashCmdList.FECM("")
    w = FECMFrame
    w.profileButton:Click()
    MenuRow("Dead").remove:Click()
    Equal(tostring(S[w.confirm.shade].shown) .. " " .. S[w.confirm.dialog.detail].text,
        "true Another character uses it, and gets a new, empty profile of its own at its next login. This can't be undone.",
        "asked first, saying what happens to that character")
    w.confirm.yes:Click()
    Equal(tostring(db.profiles.Dead) .. " " .. tostring(db.chars["Player-1-0099"]) .. " " .. S[w.note].text, "nil nil Deleted Dead.",
        "deleted, and the character let go")
    MenuRow("Shared").remove:Click()
    Equal(S[w.confirm.dialog.detail].text,
        "2 other characters use it, and each gets a new, empty profile of its own at its next login. This can't be undone.",
        "several characters")
    w.confirm.no:Click()
    db.everyone = "Mine"
    MenuRow("Shared").remove:Click()
    Equal(S[w.confirm.dialog.detail].text, "2 other characters use it, and each loads Mine at its next login. This can't be undone.",
        "with a profile for every character, they load that")
    w.confirm.yes:Click()
    Equal(tostring(db.chars["Player-1-0002"]) .. " " .. tostring(db.chars["Player-1-0003"]), "nil nil", "both let go")
    -- Your own, shared: you move to a new one, and the other is let go.
    db.everyone = nil
    db.profiles.Shared = Lists()
    db.chars["Player-1-0002"] = "Mine"
    w:Refresh()
    MenuRow("Mine").remove:Click()
    Equal(S[w.confirm.dialog.detail].text, "You're using it, so you'll move to a new, empty profile of your own. Another character uses it, "
        .. "and gets a new, empty profile of its own at its next login. This can't be undone.", "your own, shared")
    w.confirm.yes:Click()
    Equal(ns.ProfileName() .. " " .. tostring(db.chars["Player-1-0002"]), "Zriel (Druid) - Zephras nil", "you move, it's let go")
    -- That character logs in and gets a profile as a new one would.
    character = { guid = "Player-1-0002", name = "Kess", realm = "Zephras" }
    Environment(true)
    ns = Load(db)
    Equal(ns.ProfileName() .. " " .. #ns.BarData("cd").spells, "Kess (Druid) - Zephras 0", "a profile of its own at its next login, empty")
    lockdown = true
    Equal(select(2, ns.CanDeleteProfile("Shared")), "Profiles can't change in combat.", "never in combat")
    lockdown = false
    character = { guid = "Player-1-0001", name = "Zriel", realm = "Zephras" }

    -- Names made for you fit the 48 characters a profile name can have, and
    -- are never cut through a letter.
    Environment()
    character = { guid = "Player-1-0001", name = "Abcdefghijkl", realm = "An Extremely Long Realm Name For Testing" }
    ns = Load({ useBars = true })
    local own = ns.ProfileName()
    Equal(own .. " " .. #own, "Abcdefghijkl (Druid) - An Extremely Long Realm N 48", "a long name cut to fit, with no space left at the end")
    local saved = ForeverEnhancedCooldownManagerDB
    character = { guid = "Player-1-0002", name = "Abcdefghijkl", realm = "An Extremely Long Realm Name For Testing" }
    Environment(true)
    ns = Load(saved)
    Equal(ns.ProfileName(), "Abcdefghijkl (Druid) - An Extremely Long Realm 2", "a numbered one fits too")
    Equal((ns.CanDeleteProfile(own)), true, "and it can be deleted")
    Environment()
    character = { guid = "Player-1-0001", name = "Zri\195\169l", realm = "R" .. string.rep("\195\169", 24) }
    ns = Load({ useBars = true })
    own = ns.ProfileName()
    Equal(tostring(#own <= ns.PROFILE_MAX) .. " " .. tostring(utf8.len(own) ~= nil), "true true", "never cut through a letter")
    -- A long name from before names were kept short can still be deleted.
    Environment()
    character = { guid = "Player-1-0001", name = "Zriel", realm = "Zephras" }
    local long = string.rep("x", 60)
    ns = Load({ useBars = true, profiles = { [long] = Lists() }, chars = { ["Player-1-0005"] = long } })
    can, name = ns.CanDeleteProfile(long)
    Equal(tostring(can) .. " " .. tostring(name == long), "true true", "a long old name can be deleted")
    Equal(tostring((ns.DeleteProfile(long))) .. " " .. tostring(ForeverEnhancedCooldownManagerDB.profiles[long]), "true nil", "and is")
    Equal(select(2, ns.CanDeleteProfile("  ")), "Type a profile name first.", "typed names are still checked")

    -- Many profiles: the list scrolls, and the name box and buttons stay
    -- under it, in reach.
    Environment()
    local profiles = {}
    for i = 1, 30 do profiles[("Profile %02d"):format(i)] = Lists() end
    ns = Load({ useBars = true, profiles = profiles, notesSeen = "dev" }) -- no What's new
    SlashCmdList.FECM("")
    w = FECMFrame
    w.profileButton:Click()
    local list = w.profileList
    local shown, inList = 0, 0
    for _, f in ipairs(frames) do
        if f.profile and S[f].shown then
            shown = shown + 1
            if S[f].parent == list.content then inList = inList + 1 end
        end
    end
    Equal(shown .. " " .. inList .. " " .. S[list.content].height, "31 31 682", "every profile listed, in a list that scrolls")
    local bottom = S[list].points[2]
    Equal(bottom[1] .. " " .. bottom[3] .. " " .. bottom[4] .. " " .. bottom[5], "BOTTOMRIGHT TOPLEFT 282 -204",
        "pinned by two corners, eight rows tall")
    Equal(S[w.profileInput].points[1][3], -208, "the name box right under those eight")
    Equal(tostring(S[w.profilePanel].height <= 420) .. " " .. tostring(Last(w.profilePanel, "SetClampedToScreen")), "true true",
        "the menu stays short and on screen")
    for _, timer in ipairs(timers) do timer() end
    Equal(S[list].points[2][5], -204, "pinned again a moment after opening")
    -- A short list is as tall as its profiles.
    Environment()
    ns = Load({ useBars = true })
    SlashCmdList.FECM("")
    w = FECMFrame
    w.profileButton:Click()
    Equal(S[w.profileList].points[2][5] .. " " .. S[w.profileInput].points[1][3], "-50 -54", "one profile: a one-row list, the box right under it")
end

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
-- Racials: yours from your spellbook; another race's (an orc's Blood Fury in a
-- shared profile) stays off your bars; anything the data doesn't know stays.
Equal(tostring(ns.Spells:ForMe("Walk on Air", "cd")) .. " " .. tostring(ns.Spells:ForMe("Blood Fury", "cd"))
    .. " " .. tostring(ns.Spells:ForMe("Will of the Forsaken", "util")) .. " " .. tostring(ns.Spells:ForMe("Blood Fury", "buff"))
    .. " " .. tostring(ns.Spells:ForMe("Major Healing Potion", "cd")), "true false false false true",
    "your racial is yours, another race's isn't, on any bar; unknown names stay")
B:Add("cd", "Blood Fury")
Equal(table.concat(B:Mine("cd"), ","):find("Blood Fury", 1, true), nil, "an orc's racial in the profile doesn't show on your bar")

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
Equal(S[notes.version].text, "Version 1.0.0", "headed with the notes' version")
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
S[notes].last.StopMovingOrSizing = nil
FECMEscButton:Click()
Equal(S[notes].shown, false, "Escape closes What's new")
Equal(S[notes].last.StopMovingOrSizing ~= nil, true, "stopping it moving, if it was dragged")
Equal(bindings[FECMEscButton], nil, "and hands the key back")

-- Once per version.
local saved = ForeverEnhancedCooldownManagerDB
Environment(true)
ns = Load(saved)
for _, timer in ipairs(timers) do timer() end
Equal(FECMNotes == notes and not S[notes].shown, true, "shown once per version")

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

-- Kept over a reload with everything else.
cdData.perRow, cdData.grow, cdData.wrap = 3, "right", "up"
saved = ForeverEnhancedCooldownManagerDB
Environment(true)
ns = Load(saved)
cdData = ns.BarData("cd")
Equal(cdData.perRow .. " " .. cdData.grow .. " " .. cdData.wrap .. " " .. tostring(cdData.point), "3 right up BOTTOMLEFT",
    "rows and grow kept over a reload, the position held by the edge it grows from")

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
-- Edit Mode's Hide Health Bar hides the container, not the health bar in
-- it: the rows then sit flush on the power bar.
do
    local health = New("Frame", prd.HealthBarsContainer)
    S[health].rect = { 400, 205, 200, 15 }
    rawset(prd.HealthBarsContainer, "healthBar", health)
    L:Stack()
    Equal(At(B:Get("cd")) .. " " .. At(B:Get("util")), "BOTTOM 0 -180 TOP 0 -200", "the health bar counts while it shows")
    prd.HealthBarsContainer:Hide()
    L:Stack()
    Equal(At(B:Get("cd")) .. " " .. At(B:Get("util")), "BOTTOM 0 -195 TOP 0 -200", "Hide Health Bar: flush on the power bar")
    prd.HealthBarsContainer:Show()
    rawset(prd.HealthBarsContainer, "healthBar", nil)
    L:Stack()
    Equal(At(B:Get("cd")), "BOTTOM 0 -180", "and on the health bar again once it shows")
end

-- Undo puts back what the preset changed.
ok, message = L:Undo()
Equal(message .. " " .. ns.BarData("cd").perRow .. " " .. tostring(L:Active()), "Put back as it was. 20 false", "Undo")
Equal(S[prd].width, 200, "and the display gets Blizzard's width back")
Equal(L.undo, nil, "once")
Equal(tostring(ns.LayoutData().preset), "nil", "from no layout, no preset is left marked")
-- Undo back to your own layout: no preset marked, and icon sizes you set
-- after picking one stay, since a layout never changes them.
L:Apply("pyramid")
L:SetAcross("cd", 7)
L:Apply("wide")
B:SetOption("cd", "size", 48)
L:Undo()
Equal(tostring(ns.LayoutData().preset) .. " " .. ns.BarData("cd").size .. " " .. ns.BarData("cd").perRow, "nil 48 7",
    "Undo puts your own layout back, keeping the size you set")
B:SetOption("cd", "size", 36)

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

-- Reset positions ends the layout; it's kept over a reload.
L:Apply("funnel")
Equal(table.concat(ns.LayoutData().above, ","), "debuff,buff,util,cd", "everything above the display")
saved = ForeverEnhancedCooldownManagerDB
Environment(true)
Display()
ns = Load(saved)
Equal(tostring(ns.LayoutData().on) .. " " .. ns.LayoutData().preset .. " " .. table.concat(ns.LayoutData().above, ","),
    "true funnel debuff,buff,util,cd", "the layout kept over a reload")
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
-- Escape mid-drag closes the window: the spell stays where it was, and no
-- icon is left on the cursor for next time.
do
    local tile = lp.rows.cd.tiles[1]
    local name = tile.name
    S[tile].scripts.OnDragStart(tile)
    Equal(S[lp.ghost].shown, true, "a picked-up icon follows the cursor")
    w:Hide()
    S[tile].scripts.OnDragStop(tile)
    Equal(tostring(B:Find(name) ~= nil) .. " " .. tostring(S[lp.ghost].shown), "true false", "closed mid-drag, the spell stays on its bar")
    w:Show()
    w:Select("layout")
    S[tile].scripts.OnDragStart(tile)
    lp:Hide()
    Equal(S[lp.ghost].shown, false, "the page closing lets go of what was held")
    lp:Show()
    w:Select("layout")
    -- A drag that never landed can't be dropped by a later one.
    S[tile].scripts.OnDragStart(tile)
    local spare = lp.rows.cd.tiles[6]
    Equal(spare.name, nil, "an empty spot")
    S[spare].scripts.OnDragStart(spare)
    S[spare].scripts.OnDragStop(spare)
    Equal(tostring(B:Find(name) ~= nil) .. " " .. tostring(S[lp.ghost].shown), "true false", "nothing taken off by a drag from an empty spot")
end
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
-- Switched off in Blizzard's Options instead: the rows close up too.
prdOn = false
Fire("CVAR_UPDATE", "nameplateShowSelf", "0")
Equal(At(B:Get("cd")) .. " " .. At(B:Get("util")), "BOTTOM 0 -90 TOP 0 -90", "switched off in Options, the rows close up")
prdOn = true
Fire("CVAR_UPDATE", "nameplateShowSelf", "1")
Equal(At(B:Get("util")), "TOP 0 -100", "and part again when it's back")
prdOn = false
Fire("CVAR_UPDATE", "cooldownViewerEnabled", "1")
Equal(At(B:Get("util")), "TOP 0 -100", "other game settings don't restack")
prd:Hide()
Equal(At(B:Get("util")), "TOP 0 -90", "the display hiding closes them up too")
prdOn = true
prd:Show()
Equal(At(B:Get("util")), "TOP 0 -100", "and showing again parts them")
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
-- Its height is kept over a reload, within its limits.
saved = ForeverEnhancedCooldownManagerDB
Environment(true)
ns = Load(saved)
Equal(ns.Get("castHeight"), 24, "the height kept over a reload")
saved.castHeight = 99
Environment(true)
ns = Load(saved)
Equal(ns.Get("castHeight"), 18, "one out of range is ignored")

-- The swing timer in the cast bar's spot ---------------------------------------------------------

-- In a function of its own: the main chunk is near Lua's limit of 200 locals.
;(function()
    Environment()
    Display()
    _G.PlayerCastingBarFrame = New("Frame")
    local native = PlayerCastingBarFrame
    -- Forever's own swing timers: the addon never touches them.
    local forever = {}
    for _, name in ipairs({ "SwingTimerMainHandFrame", "SwingTimerOffHandFrame", "SwingTimerRangedFrame" }) do
        _G[name] = New("Frame")
        forever[#forever + 1] = _G[name]
    end
    -- A sword in the main hand and a bow in the ranged slot.
    local weapons = { [16] = 135274, [18] = 135490 }
    _G.GetInventoryItemTexture = function(unit, slot) assert(unit == "player"); return weapons[slot] end
    local class = "DRUID"
    _G.UnitClass = function() return class:sub(1, 1) .. class:sub(2):lower(), class end
    ns = Load({ useBars = true, prdSkin = false })
    local B, L, C = ns.Bars, ns.Layout, ns.CastBar
    local sw = C.row
    B:Assign("Moonfire", "cd")
    B:Assign("Attack", "util")
    L:Apply("pyramid")
    local function Gone() return S[sw].alpha .. " " .. tostring(S[sw].scripts.OnUpdate) end
    local function Time() return Last(sw.bar.time, "SetFormattedText", 2) end
    Equal(tostring(ns.Get("swingTimer")) .. " " .. ns.Get("swingColour") .. " " .. tostring(C:Room()) .. " " .. tostring(S[sw].shown),
        "false default nil false", "off by default: no room, nothing shown")
    class = "HUNTER"
    clock = 200
    Fire("PLAYER_SWING", 2.5, 2)
    Equal(Gone(), "0 nil", "off, a swing does nothing")
    ns.Set("swingTimer", true)
    C:Apply()
    Equal(At(sw) .. string.format(" %g ", S[sw].width) .. At(B:Get("util")) .. " " .. Gone(), "TOP 0 -104 200 TOP 0 -122 0 nil",
        "on: the cast bar's spot under the display, Utility under it, and nothing ticking until you swing")
    native:SetAlpha(.5)
    Equal(tostring(C:Room()) .. " " .. S[native].alpha, "18 0.5", "its room kept, and Blizzard's cast bar left alone")
    native:SetAlpha(1)
    -- Auto Shot: the bow's icon, filling from empty, in silver.
    Fire("PLAYER_SWING", 2.5, 2)
    Equal(S[sw].alpha .. " " .. S[sw.bar.name].text .. " " .. S[sw.icon].texture .. " " .. Last(sw.bar, "SetMinMaxValues", 2),
        "1 Auto Shot 135490 2.5", "Auto Shot for a hunter: the ranged weapon's icon, as long as the swing")
    Equal(string.format("%g %g %g", Last(sw.bar, "SetStatusBarColor", 1), Last(sw.bar, "SetStatusBarColor", 3), Last(sw.bar, "SetValue", 1)),
        "0.66 0.72 0", "in silver, starting empty")
    clock = 201
    S[sw].scripts.OnUpdate(sw, 1)
    Equal(string.format("%g %g", Last(sw.bar, "SetValue", 1), Time()), "1 1.5", "filling, with the seconds left")
    -- The off hand, and swings the game keeps secret, are skipped.
    Fire("PLAYER_SWING", 1.8, 1)
    Fire("PLAYER_SWING", SECRET, 2)
    Fire("PLAYER_SWING", 1.2, SECRET)
    Fire("PLAYER_SWING", SECRET, SECRET)
    -- Secret numbers too: the game says so, whatever they'd read as.
    local plain = issecretvalue
    _G.issecretvalue = function(v) return v == 1.7 or plain(v) end
    Fire("PLAYER_SWING", 1.7, 2)
    _G.issecretvalue = function(v) return v == 2 or plain(v) end
    Fire("PLAYER_SWING", 1.9, 2)
    _G.issecretvalue = plain
    for _, odd in ipairs({ 0, -1, 0 / 0, math.huge, "2" }) do Fire("PLAYER_SWING", odd, 0) end
    Fire("PLAYER_SWING", nil, 0)
    Fire("PLAYER_SWING", 2, nil)
    clock = 201.5
    S[sw].scripts.OnUpdate(sw, .5)
    Equal(string.format("%s %g %g", S[sw.bar.name].text, Last(sw.bar, "SetMinMaxValues", 2), Last(sw.bar, "SetValue", 1)),
        "Auto Shot 2.5 1.5", "the off hand, secret swings and odd times are skipped, never guessed at")
    -- Shot after shot: held full as each runs out, so the bar never blinks.
    local lowest = 1
    rawset(sw, "SetAlpha", function(self, alpha)
        lowest = math.min(lowest, alpha)
        S[self].alpha = alpha
    end)
    clock = 202.6 -- ran out at 202.5
    S[sw].scripts.OnUpdate(sw, 1.1)
    Equal(string.format("%g %g %g", Last(sw.bar, "SetValue", 1), Time(), S[sw].alpha), "2.5 0 1", "run out: full, and held")
    clock = 202.8
    S[sw].scripts.OnUpdate(sw, .2)
    Fire("PLAYER_SWING", 2.5, 2)
    Equal(string.format("%g %g", lowest, Last(sw.bar, "SetValue", 1)), "1 0", "the next shot starts it again, with no blink between")
    rawset(sw, "SetAlpha", nil)
    clock = 205.8 -- ran out at 205.3
    S[sw].scripts.OnUpdate(sw, 3)
    Equal(string.format("%.2f", S[sw].alpha), "0.67", "no next shot: it fades like a finished cast")
    clock = 206.1
    S[sw].scripts.OnUpdate(sw, .3)
    Equal(Gone(), "0 nil", "and it's gone, with nothing left ticking")
    -- The main hand, and other classes' ranged swings.
    Fire("PLAYER_SWING", 3.2, 0)
    Equal(S[sw.bar.name].text .. " " .. S[sw.icon].texture .. " " .. Last(sw.bar, "SetMinMaxValues", 2) .. " " .. S[sw].alpha,
        "Main hand 135274 3.2 1", "a melee swing: Main hand, with the main hand weapon's icon")
    class = "DRUID"
    Fire("PLAYER_SWING", 2, 2)
    Equal(S[sw.bar.name].text, "Ranged", "a ranged swing for any other class")
    weapons[16], weapons[18] = nil, SECRET
    Fire("PLAYER_SWING", 3.2, 0)
    local sword = S[sw.icon].texture
    Fire("PLAYER_SWING", 2, 2)
    Equal(sword .. " " .. S[sw.icon].texture, "Interface\\Icons\\INV_Sword_04 Interface\\Icons\\INV_Weapon_Bow_05",
        "no weapon icon to hand, or a secret one: a sword or a bow")
    weapons[16], weapons[18] = 135274, 135490
    class = "HUNTER"
    -- The height and parts are the cast bar's.
    ns.Set("castHeight", 24)
    ns.Set("castIcon", false)
    C:Apply()
    Equal(S[sw].height .. " " .. tostring(S[sw.icon].shown) .. " " .. At(B:Get("util")) .. " " .. Last(sw.bar, "SetStatusBarColor", 1),
        "24 false TOP 0 -128 0.66", "the swing timer follows the height and parts, and keeps its colour")
    ns.Set("castHeight", 18)
    ns.Set("castIcon", true)
    C:Apply()
    -- A new weapon or a loading screen clears it.
    Fire("WEAPON_SLOT_CHANGED")
    Equal(Gone(), "0 nil", "a weapon change clears it")
    Fire("PLAYER_SWING", 2.5, 2)
    Fire("PLAYER_ENTERING_WORLD")
    Equal(Gone(), "0 nil", "and so does a loading screen")
    -- The cast bar off: casts stay on Blizzard's bar, and the swing keeps the spot.
    clock = 207
    Fire("PLAYER_SWING", 2.5, 2)
    local casting = { "Wrath", "Wrath", 136006, 207000, 208500, false, "cast-1" }
    _G.UnitCastingInfo = function() return table.unpack(casting) end
    Fire("UNIT_SPELLCAST_START", "player", "cast-1", 5176)
    Equal(S[sw.bar.name].text .. " " .. S[native].alpha, "Auto Shot 1",
        "with the cast bar off, casts are left to Blizzard's bar and the swing timer keeps the spot")
    -- Both on: one spot, and a cast takes it while it lasts.
    ns.Set("castBar", true)
    C:Apply()
    Equal(tostring(C:Room()) .. " " .. At(B:Get("util")) .. " " .. S[native].alpha .. " " .. S[sw.bar.name].text,
        "18 TOP 0 -122 0 Auto Shot", "both on: one spot, Blizzard's cast bar hidden, the swing still showing")
    clock = 210
    Fire("PLAYER_SWING", 3, 0)
    casting = { "Wrath", "Wrath", 136006, 210500, 212000, false, "cast-2" }
    clock = 210.5
    Fire("UNIT_SPELLCAST_START", "player", "cast-2", 5176)
    Equal(S[sw.bar.name].text .. " " .. Last(sw.bar, "SetStatusBarColor", 1), "Wrath 1", "a cast takes the spot, in gold")
    clock = 211
    Fire("PLAYER_SWING", 3, 0)
    S[sw].scripts.OnUpdate(sw, .5)
    Equal(S[sw.bar.name].text .. " " .. string.format("%g", Last(sw.bar, "SetValue", 1)), "Wrath 0.5", "a swing meanwhile waits its turn")
    clock = 212
    Fire("UNIT_SPELLCAST_STOP", "player", "cast-2", 5176)
    clock = 212.5
    S[sw].scripts.OnUpdate(sw, .5)
    Equal(S[sw.bar.name].text .. string.format(" %.2f", S[sw].alpha), "Wrath 0.67", "the finished cast holds and fades as before")
    clock = 212.8
    S[sw].scripts.OnUpdate(sw, .3)
    Equal(string.format("%s %g %g %.1f", S[sw.bar.name].text, S[sw].alpha, Last(sw.bar, "SetStatusBarColor", 1), Last(sw.bar, "SetValue", 1)),
        "Main hand 1 0.66 1.8", "then the swing timer comes back, in its own colour, where it's got to")
    -- A swing that runs out during a cast doesn't come back just to fade.
    clock = 215
    Fire("PLAYER_SWING", 2.5, 0) -- runs out at 217.5, just before the cast has faded
    casting = { "Wrath", "Wrath", 136006, 215000, 218000, false, "cast-3" }
    Fire("UNIT_SPELLCAST_START", "player", "cast-3", 5176)
    clock = 217
    S[sw].scripts.OnUpdate(sw, 2)
    Fire("UNIT_SPELLCAST_STOP", "player", "cast-3", 5176)
    clock = 217.8
    S[sw].scripts.OnUpdate(sw, .8)
    Equal(Gone(), "0 nil", "a swing that ran out during the cast stays gone")
    -- Broken off: red, then the swing timer again.
    clock = 220
    Fire("PLAYER_SWING", 3, 0)
    casting = { "Wrath", "Wrath", 136006, 220000, 222000, false, "cast-4" }
    Fire("UNIT_SPELLCAST_START", "player", "cast-4", 5176)
    Fire("UNIT_SPELLCAST_INTERRUPTED", "player", "cast-4", 5176)
    Equal(S[sw.bar.name].text .. " " .. Last(sw.bar, "SetStatusBarColor", 1), "Interrupted 0.85", "an interrupted cast shows red as before")
    clock = 220.8
    S[sw].scripts.OnUpdate(sw, .8)
    Equal(S[sw.bar.name].text .. " " .. S[sw].alpha, "Main hand 1", "and the swing timer comes back after")
    -- The Layout page draws the spot while either is on.
    SlashCmdList.FECM("")
    local w = FECMFrame
    w:Select("layout")
    local strip = w.pages.layout.castStrip
    Equal(tostring(S[strip].shown) .. " " .. Last(strip, "SetColorTexture", 1), "true 1", "the Layout page draws the spot, in the cast bar's colour")
    w:Select("cast")
    local cp = w.pages.cast
    Equal(S[cp.status].text, "Cast bar and swing timer under your resource display. Blizzard's cast bar is hidden.", "the page says both are on")
    cp.shown:Click()
    native:SetAlpha(1) -- Blizzard's own bar starting a cast
    w:Select("layout")
    Equal(tostring(S[strip].shown) .. " " .. Last(strip, "SetColorTexture", 1) .. " " .. tostring(C:Room()) .. " " .. S[native].alpha,
        "true 0.66 18 1", "only the swing timer: the spot in its silver, and Blizzard's cast bar back")
    w:Select("cast")
    cp.swing:Click()
    w:Select("layout")
    Equal(tostring(S[strip].shown) .. " " .. tostring(C:Room()) .. " " .. At(B:Get("util")) .. " " .. tostring(S[sw].shown) .. " " .. Gone(),
        "false nil TOP 0 -100 false 0 nil", "both off from the page: no spot, the rows close up, nothing ticking")
    -- The Cast bar page: a tick, a colour and a preview for the swing timer.
    w:Select("cast")
    Equal(S[cp.swing.text].text .. "|" .. S[cp.icon.text].text .. "|" .. S[cp.name.text].text .. "|" .. S[cp.timer.text].text,
        "Swing timer in this spot|Icon|Name|Time left", "the ticks read right for both")
    Equal(tostring(cp.swing:GetChecked()) .. " " .. S[cp.sample].alpha .. " " .. S[cp.swingSample].alpha, "false 0.35 0.35",
        "both off: both preview bars dimmed")
    Equal(S[cp.swingSample.bar.name].text .. " " .. S[cp.swingSample.icon].texture, "Auto Shot Interface\\Icons\\INV_Weapon_Bow_05",
        "a hunter's preview swings Auto Shot, with a bow")
    cp.swing:Click()
    Equal(tostring(ns.Get("swingTimer")) .. " " .. S[cp.swingSample].alpha .. " " .. S[cp.sample].alpha .. " " .. S[cp.status].text,
        "true 1 0.35 Swing timer under your resource display. Casts show on Blizzard's cast bar.", "ticked: its preview lights up")
    Equal(tostring(C:Room()) .. " " .. tostring(S[sw].shown), "18 true", "and the spot is back")
    S[cp.swing].scripts.OnEnter(cp.swing)
    local note = S[w.note].text
    Equal(note:find("Main hand and ranged swings: Auto Shot for hunters, Ranged for other classes.", 1, true) ~= nil
        and note:find("A cast takes the spot", 1, true) ~= nil and note:find("EraUI", 1, true) ~= nil, true,
        "its note: main hand and ranged, as shown above, casts first, and the other swing timers")
    S[cp.swing].scripts.OnLeave(cp.swing)
    -- The Name tick names all three a swing can be called.
    S[cp.name].scripts.OnEnter(cp.name)
    note = S[w.note].text
    Equal(note:find("Main hand, Auto Shot or Ranged for the swing timer", 1, true) ~= nil, true, "the Name tick's note lists Ranged too")
    S[cp.name].scripts.OnLeave(cp.name)
    -- What's new says what it does: the main hand for everyone, hunters too,
    -- and ranged swings, called Auto Shot for hunters.
    local bullet
    for _, section in ipairs(ns.NOTES[1].sections) do
        for _, item in ipairs(section[2]) do
            if item:find("^Swing timer") then bullet = item end
        end
    end
    Equal(bullet:find("your main hand and ranged swings (Auto Shot for hunters)", 1, true) ~= nil
        and bullet:find("everyone else", 1, true) == nil, true, "What's new: main hand and ranged, not Auto Shot only for hunters")
    cp.swingSwatches[3]:Click()
    Equal(ns.Get("swingColour") .. " " .. S[cp.swingChosen].text .. " " .. Last(cp.swingSample.bar, "SetStatusBarColor", 1) .. " " .. ns.Get("castColour"),
        "blue Blue " .. ns.Style:BarColour("blue")[1] .. " default", "a colour of its own, in the preview, leaving the cast bar's")
    Fire("PLAYER_SWING", 2.5, 2)
    Equal(Last(sw.bar, "SetStatusBarColor", 1), ns.Style:BarColour("blue")[1], "and on the real one")
    cp.swingSwatches[3]:Click()
    Equal(ns.Get("swingColour") .. " " .. S[cp.swingChosen].text, "default Silver", "clicking it again goes back to silver")
    S[cp.swingSample].scripts.OnUpdate(cp.swingSample, 1)
    Equal(string.format("%g %.1f", Last(cp.swingSample.bar, "SetValue", 1), Last(cp.swingSample.bar.time, "SetFormattedText", 2)), "1 1.8",
        "the preview swings as you watch")
    S[cp.swingSample].scripts.OnUpdate(cp.swingSample, 2)
    Equal(string.format("%.1f", Last(cp.swingSample.bar, "SetValue", 1)), "0.2", "over and over")
    class = "DRUID"
    w:Refresh()
    Equal(S[cp.swingSample.bar.name].text .. " " .. S[cp.swingSample.icon].texture, "Main hand Interface\\Icons\\INV_Sword_04",
        "anyone else's preview swings the main hand, with a sword")
    class = "HUNTER"
    -- Everything fits the page, top to bottom, none overlapping.
    local tray = S[cp.options].points[1][2]
    local top = -S[tray].points[1][3] + S[tray].height - S[cp.options].points[1][5]
    local rows = { cp.shown, cp.swing, cp.swatches[1], cp.swingSwatches[1], cp.height, cp.icon, cp.name, cp.timer }
    local bottom, clear = 0, true
    for _, row in ipairs(rows) do
        local y = -S[row].points[1][3]
        if y < bottom + 4 then clear = false end
        bottom = y + S[row].height
    end
    local aboutTop = -S[cp.about].points[1][3]
    local last = aboutTop + cp.about:GetStringHeight()
    Equal(tostring(clear and aboutTop >= bottom + 4) .. " " .. tostring(top + last <= 489), "true true", "the page's rows don't overlap and fit the window")
    Equal(S[tray].height / 2 >= 3 + ns.CAST_HEIGHT[2] + 5 and S[cp.sample].points[1][1] .. " " .. S[cp.swingSample].points[1][1],
        "BOTTOMLEFT TOPLEFT", "both preview bars fit the tray at the tallest height, one above the middle and one below")
    -- Forever's own swing timers are never touched.
    local untouched = true
    for _, frame in ipairs(forever) do
        if next(S[frame].last) ~= nil or S[frame].alpha ~= 1 or not S[frame].shown then untouched = false end
    end
    Equal(untouched, true, "Forever's own swing timers untouched")
    Equal(#printed, 0, "no errors from the swing timer")
    -- Kept over a reload; anything else is ignored.
    ns.Set("swingColour", "purple")
    local kept = ForeverEnhancedCooldownManagerDB
    Environment(true)
    ns = Load(kept)
    Equal(tostring(ns.Get("swingTimer")) .. " " .. ns.Get("swingColour"), "true purple", "kept over a reload")
    kept.swingTimer, kept.swingColour = "yes", "pink"
    Environment(true)
    ns = Load(kept)
    Equal(tostring(ns.Get("swingTimer")) .. " " .. ns.Get("swingColour") .. " " .. tostring(ns.Valid("swingColour", "class"))
        .. " " .. tostring(ns.Valid("swingColour", "default")) .. " " .. tostring(ns.Valid("swingColour", 3)),
        "false default true true false", "anything else is ignored: off, and silver")
    Environment()
    ns = Load(nil)
    Equal(tostring(ns.Get("swingTimer")) .. " " .. tostring(S[ns.CastBar.row].shown), "false false", "a new install: off")
    for _, name in ipairs({ "SwingTimerMainHandFrame", "SwingTimerOffHandFrame", "SwingTimerRangedFrame", "PlayerCastingBarFrame" }) do
        _G[name] = nil
    end
end)()

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

-- A whole-bar box only goes round icons that stay put: not packed Buffs or
-- Debuffs, a bar hiding its ready icons, or greyed Debuffs spots with no enemy.
do
    Environment()
    ns = Load({ useBars = true })
    B = ns.Bars
    B:Assign("Moonfire", "cd")
    B:SetAura("buff", "Thorns", true)
    B:SetAura("debuff", "Moonfire", true)
    ns.Set("iconBorder", "bar")
    ns.Set("iconShadow", "bar")
    B:ApplyDecor()
    local cd, buff, debuff = B:Get("cd"), B:Get("buff"), B:Get("debuff")
    Equal(Shown(cd.decor.border) .. " " .. Shown(cd.decor.shadow[1]), "true true", "a cooldown bar gets the whole-bar box")
    Equal(Shown(buff.decor.border) .. " " .. Shown(buff.decor.shadow[1]) .. " " .. Shown(debuff.decor.border), "false false false",
        "packed Buffs and Debuffs don't: their icons come and go")
    B:SetOption("cd", "hideReady", true)
    Equal(Shown(cd.decor.border), "false", "nor a bar that hides its ready icons")
    B:SetUnlocked(true)
    Equal(Shown(cd.decor.border), "true", "unless every icon shows, unlocked")
    B:SetUnlocked(false)
    Equal(Shown(cd.decor.border), "false", "locked again, it goes")
    B:SetOption("cd", "hideReady", false)
    Equal(Shown(cd.decor.border), "true", "and it's back with Hide when ready off")
    B:SetOption("buff", "showMissing", true)
    Equal(Shown(buff.decor.border), "true", "fixed Buffs spots always show, so they get it")
    target, hostile = false, true
    B:SetOption("debuff", "showMissing", true)
    Fire("PLAYER_TARGET_CHANGED")
    Equal(Shown(debuff.decor.border) .. " " .. tostring(debuff.enemy), "false false", "fixed Debuffs spots with no enemy don't")
    target = true
    Fire("PLAYER_TARGET_CHANGED")
    Equal(Shown(debuff.decor.border), "true", "until you target one")
    -- Each icon: a greyed Debuffs spot's rings go with it.
    ns.Set("iconBorder", "icon")
    ns.Set("iconShadow", "icon")
    B:ApplyDecor()
    local spot = debuff.holders[1]
    Equal(Shown(spot.decor.border) .. " " .. Shown(spot.decor.shadow[1]) .. " " .. Shown(debuff.decor.border), "true true false",
        "each icon: the spots ringed while there's an enemy")
    target = false
    Fire("PLAYER_TARGET_CHANGED")
    Equal(Shown(spot.decor.border) .. " " .. tostring(S[spot.icon].alpha), "false 0", "no enemy: the greyed spot goes, rings and all")
    B:ApplyDecor()
    Equal(Shown(spot.decor.border) .. " " .. Shown(buff.holders[1].decor.border), "false true",
        "the Look page doesn't bring them back, and Buffs spots keep theirs")
    hostile, target = SECRET, true
    Fire("PLAYER_TARGET_CHANGED")
    Equal(Shown(spot.decor.border), "true", "a hidden answer counts as an enemy")
    hostile = true
    Equal(#printed, 0, "no errors from whole-bar boxes")

    -- Blizzard's packed icons can't be used while auras are secret, so the
    -- Look page changes theirs once the fight is over; yours change at once.
    Environment()
    ns = Load({ useBars = true })
    B = ns.Bars
    B:Assign("Moonfire", "cd")
    B:SetAura("buff", "Thorns", true)
    local packed = B:Get("buff").groupParts
    Equal(#packed .. " " .. Shown(packed[1].decor.border), "1 false", "a packed icon, no border yet")
    Fire("PLAYER_REGEN_DISABLED")
    lockdown = true
    ns.Set("iconBorder", "icon")
    B:ApplyDecor()
    Equal(Shown(B:Get("cd").icons[1].decor.border) .. " " .. Shown(packed[1].decor.border) .. " " .. tostring(B:Get("buff").pendingDecor),
        "true false true", "in a fight your icons change at once; Blizzard's packed ones wait")
    lockdown = false
    Fire("PLAYER_REGEN_ENABLED")
    Equal(Shown(packed[1].decor.border) .. " " .. tostring(B:Get("buff").pendingDecor), "true nil", "and change once it's over")
    Equal(#printed, 0, "no errors from redrawing in a fight")
end

-- Joined entries take one slot between them ------------------------------------------------

do
    Environment()
    ns = Load({ useBars = true })
    B = ns.Bars
    ns.BUFF_SLOTS = 2
    B:SetAura("buff", "Thorns", true)
    B:SetAura("buff", "Clearcasting", true)
    B:SetJoined("buff", 2, true)
    Equal(B:SlotsUsed("buff"), 1, "a joined pair takes one slot")
    Equal(B:SetAura("buff", "Nature's Grace", true), true, "so a second icon still fits")
    Equal(B:SetAura("buff", "Walk on Air", true), false, "but not a third")
    local ok, why = B:SetJoined("buff", 2, false)
    Equal(tostring(ok) .. " " .. tostring(why) .. " " .. tostring(B:Joined("buff", 2)), "false Buffs is full. true",
        "splitting past the slots is refused")
    ok, why = B:MoveTo("buff", 2, 3)
    Equal(tostring(ok) .. " " .. tostring(why) .. " | " .. Shape("buff"), "false Buffs is full. | Thorns+Clearcasting, Nature's Grace",
        "so is dragging one out of its group, which puts everything back")
    Equal(B:MoveTo("buff", 3, 1), true, "a move that needs no more icons is fine")
    Equal(Shape("buff"), "Nature's Grace, Thorns+Clearcasting", "and happens")
    ns.BUFF_SLOTS = 16
    Equal(B:SetJoined("buff", 3, false), true, "with room, a split goes through")
    Equal(Shape("buff"), "Nature's Grace, Thorns, Clearcasting", "split")
    B:Assign("Moonfire", "cd")
    B:Assign("Wrath", "cd")
    Equal(B:MoveTo("cd", 1, 2), true, "cooldown bars move as before")
    Equal(table.concat(ns.BarData("cd").spells, ","), "Wrath,Moonfire", "moved")
    Equal(#printed, 0, "no errors from slots")
end

-- Only what a bar can show goes on it -------------------------------------------------------

do
    Environment()
    Book(true)
    ns = Load({ useBars = true })
    B = ns.Bars
    B:Assign("Moonfire@1", "cd")
    local ok, why = B:Transfer("cd", "buff", "Moonfire@1")
    Equal(tostring(ok) .. " " .. tostring(why), "false Fixed ranks can't go on the Buffs bar, which counts every rank already.",
        "a fixed rank can't be dragged onto Buffs")
    Equal(table.concat(ns.BarData("cd").spells, ","), "Moonfire@1", "and stays on Cooldowns")
    Equal(B:Transfer("cd", "debuff", "Moonfire@1"), false, "nor onto Debuffs")
    Equal(B:Transfer("cd", "util", "Moonfire@1"), true, "Utility is fine")
    B:SetAura("buff", "Clearcasting", true)
    ok, why = B:Transfer("buff", "cd", "Clearcasting")
    Equal(tostring(ok) .. " " .. tostring(why), "false Procs only go on the Buffs bar.", "a proc can't go onto Cooldowns")
    Equal(tostring(B:Transfer("buff", "debuff", "Clearcasting")) .. " " .. tostring(B:HasAura("buff", "Clearcasting")), "false true",
        "nor Debuffs, and it stays on Buffs")
    ok, why = B:Add("debuff", "Clearcasting")
    Equal(tostring(ok) .. " " .. tostring(why), "false Procs only go on the Buffs bar.", "added by name, it says why")
    Equal((B:Add("buff", "Moonfire (Rank 1)")), false, "a fixed rank added to Buffs by name is refused")
    Equal((B:Add("util", "Moonfire (Rank 2)")), true, "but it's fine on a cooldown bar")
    Equal((B:Add("buff", "Thorns")), true, "a buff on Buffs is fine")
    Equal(B:Transfer("buff", "debuff", "Thorns"), true, "and plain spells move between aura bars as before")
    Equal(#printed, 0, "no errors from what fits")

    -- On the Layout page: refused, the spell stays and the footer says why.
    Environment()
    Book(true)
    Display()
    ns = Load({ useBars = true, prdSkin = false })
    B = ns.Bars
    B:Assign("Moonfire@1", "cd")
    B:SetAura("buff", "Thorns", true)
    SlashCmdList.FECM("")
    w = FECMFrame
    w:Select("layout")
    local lp = w.pages.layout
    local tile = lp.rows.cd.tiles[1]
    S[tile].scripts.OnDragStart(tile)
    S[lp.rows.buff].mouseOver = true
    S[tile].scripts.OnDragStop(tile)
    S[lp.rows.buff].mouseOver = nil
    Equal(table.concat(ns.BarData("cd").spells, ",") .. " " .. S[w.note].text,
        "Moonfire@1 Fixed ranks can't go on the Buffs bar, which counts every rank already.", "dragged onto the Buffs row, it stays")
end

-- A Buffs or Debuffs bar dragged as a fight starts is let go first ---------------------------

do
    Environment()
    ns = Load({ useBars = true })
    B = ns.Bars
    B:SetAura("buff", "Thorns", true)
    B:SetUnlocked(true)
    local bar = B:Get("buff")
    S[bar.mover].scripts.OnDragStart(bar.mover)
    Equal(bar.dragging, true, "dragging")
    S[bar].cx, S[bar].cy = 620, 450
    Fire("PLAYER_REGEN_DISABLED")
    Equal(tostring(bar.dragging) .. " " .. tostring(S[bar].last.StopMovingOrSizing ~= nil), "nil true",
        "let go as the fight starts, before it's locked")
    Equal(ns.BarData("buff").x, 120, "and placed where it was")
    lockdown = true
    local points = #S[bar].points
    S[bar].last.StopMovingOrSizing = nil
    S[bar.mover].scripts.OnDragStop(bar.mover)
    Equal(tostring(S[bar].last.StopMovingOrSizing) .. " " .. #S[bar].points, "nil " .. points, "the late drag stop moves nothing in the fight")
    S[bar.mover].scripts.OnDragStart(bar.mover)
    Equal(bar.dragging, nil, "and no drag starts in one")
    lockdown = false
    Fire("PLAYER_REGEN_ENABLED")
    Equal(#printed, 0, "no errors from dragging into a fight")
end

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
-- Kept over a reload.
saved = ForeverEnhancedCooldownManagerDB
Environment(true)
Display()
ns = Load(saved)
Equal(tostring(ns.Layout:IsHidden("debuff")) .. " " .. ns.LayoutData().base, "true pyramid", "still out after a reload")
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

-- A first install: the window and a welcome ------------------------------------------

-- Nothing new to show: the window opens instead, a moment after login and
-- never in combat, offering the tour.
do
    Environment()
    _G.FECMFrame, _G.FECMTour, _G.FECMNotes = nil, nil, nil
    ns = Load(nil)
    Equal(FECMFrame, nil, "a first install waits a moment to open the window")
    lockdown = true
    for _, timer in ipairs(timers) do timer() end
    Equal(FECMFrame, nil, "not in combat")
    lockdown = false
    Fire("PLAYER_REGEN_ENABLED")
    local tw, box = FECMFrame, FECMTour
    Equal(tw ~= nil and S[tw].shown, true, "then the window opens")
    Equal(S[box].shown and S[box.title].text, "WELCOME", "with a welcome")
    Equal(S[box.next.label].text .. "|" .. S[box.skip.label].text .. "|" .. tostring(S[box.back].shown),
        "Take the tour|Skip|false", "offering the tour, or Skip")
    Equal(FECMNotes == nil or not S[FECMNotes].shown, true, "and no What's new")
    box.skip:Click()
    Equal(S[box].shown, false, "Skip closes the welcome")
    Equal(S[tw].shown and S[tw.note].text, "Take the tour any time from the General page, or with /ccm tour.",
        "leaving the window open, and saying where the tour is")
    -- Once only.
    local saved = ForeverEnhancedCooldownManagerDB
    Environment(true)
    _G.FECMFrame, _G.FECMTour = nil, nil
    ns = Load(saved)
    for _, timer in ipairs(timers) do timer() end
    Equal(FECMFrame == nil and FECMTour == nil, true, "the welcome only comes once")
end

-- The tour --------------------------------------------------------------------------------

-- In a function of its own: the main chunk is near Lua's limit of 200 locals.
;(function()
    Environment()
    _G.FECMFrame, _G.FECMTour = nil, nil
    ns = Load({ useBars = false })
    -- Ticks as wide as their labels while the window is made, so the Cast bar
    -- step's two ticks differ.
    local fixedWidth = Proto.GetStringWidth
    Proto.GetStringWidth = function(self) return #(S[self].text or "") * 6 end
    SlashCmdList.FECM("tour")
    Proto.GetStringWidth = fixedWidth
    local tw, box = FECMFrame, FECMTour
    local function Outlined() return S[box.outline].points[1][2] end
    local function Anchor() local p = S[box].points[1]; return p[1] .. " " .. p[3] end
    Equal(S[tw].shown and S[box].shown, true, "/ccm tour opens the window with the tour")
    Equal(S[box.count].text .. " " .. S[box.title].text, "1 of 9 THE MENU", "nine steps, the menu first")
    Equal(Outlined() == tw.navFrame and S[box.outline].shown, true, "outlining the menu")
    Equal(Anchor(), "TOPLEFT TOPRIGHT", "its box beside it")
    Equal(S[box.back].shown, false, "no Back on the first step")
    box.next:Click()
    Equal(tw.selected .. " " .. S[box.title].text, "general SWITCH YOUR BARS ON", "Next opens the General page")
    Equal(Outlined(), tw.useBars, "outlining Use my bars")
    Equal(S[box.text].text:find("Try it: tick it.", 1, true) ~= nil, true, "asking you to try it")
    S[box].scripts.OnUpdate(box, .3)
    Equal(S[box.title].text, "SWITCH YOUR BARS ON", "waiting until you do")
    tw.useBars:Click()
    S[box].scripts.OnUpdate(box, .1)
    Equal(S[box.title].text, "SWITCH YOUR BARS ON", "looking a few times a second, not every frame")
    S[box].scripts.OnUpdate(box, .2)
    Equal(tw.selected .. " " .. S[box.title].text, "cd ADD SPELLS", "ticking it moves the tour on by itself")
    Equal(Outlined() == tw.pages.bar.listPanel and Anchor() == "BOTTOMLEFT TOPLEFT", true, "the spell list, the box above it")
    ns.Bars:Assign("Moonfire", "cd")
    S[box].scripts.OnUpdate(box, .3)
    Equal(S[box.title].text, "THIS BAR'S OPTIONS", "adding a spell moves it on")
    Equal(Outlined(), tw.pages.bar.optionsArea, "outlining the bar's options")
    box.back:Click()
    Equal(S[box.title].text, "ADD SPELLS", "Back goes back a step")
    S[box].scripts.OnUpdate(box, .3)
    Equal(S[box.title].text, "ADD SPELLS", "a step done before doesn't skip itself")
    box.next:Click()
    tw:Select("look")
    Equal(S[box].shown and not S[box.outline].shown, true, "on another page the outline hides, the box stays")
    tw:Select("util")
    Equal(S[box.outline].shown, true, "any bar's page counts as the bar page")
    box.next:Click()
    Equal(tw.selected .. " " .. S[box.title].text, "layout LAYOUTS", "Layouts next")
    local cards = tw.pages.layout.cards
    Equal(Outlined() == cards[1] and S[box.outline].points[2][2] == cards[#cards], true, "outlining every preset")
    box.next:Click()
    Equal(tw.selected .. " " .. S[box.title].text, "look THE LOOK", "then the Look page")
    Equal(Outlined(), tw.lookOptions, "its choices")
    Equal(S[box.text].text:find("already has the new look", 1, true) ~= nil, true, "the look on: the Cooldown Manager has it")
    -- Only said when it's true: ticked but not reloaded yet, unticked, or
    -- unticked since login, the step says what happens.
    local function Again()
        box.back:Click()
        box.next:Click()
        return S[box.text].text
    end
    ns.loaded.skin = false
    Equal(Again():find("Reload to apply, and Blizzard's Cooldown Manager gets the new look.", 1, true), 1,
        "ticked but not reloaded: reload to apply")
    ns.Set("skin", false)
    Equal(Again():find("Tick Apply this look to the Cooldown Manager, then reload", 1, true), 1, "unticked: tick it, then reload")
    ns.loaded.skin = true
    local text = Again()
    Equal(tostring(text:find("goes back to its own look when you reload", 1, true) ~= nil) .. " " .. tostring(text:find("already has", 1, true)),
        "true nil", "unticked since login: it goes back to its own look at the next reload")
    ns.Set("skin", true)
    Equal(Again():find("already has the new look", 1, true) ~= nil and tw.selected .. " " .. S[box.title].text, "look THE LOOK",
        "ticked again: as before")
    box.next:Click()
    Equal(tw.selected .. " " .. S[box.title].text, "cast CAST BAR", "the Cast bar page")
    -- Both its ticks outlined as one part, with the box and its arrow under
    -- the swing timer's tick, never over it.
    local cp = tw.pages.cast
    local ticks = S[cp.ticks]
    Equal(Outlined() == cp.ticks and S[box.outline].points[2][2] == cp.ticks, true, "outlining both ticks")
    Equal(ticks.points[1][1] .. " " .. tostring(ticks.points[1][2] == cp.shown) .. " " .. ticks.points[2][1] .. " "
        .. tostring(ticks.points[2][2] == cp.swing) .. " " .. ticks.points[2][3] .. " " .. tostring(ticks.shown),
        "TOPLEFT true BOTTOMLEFT true BOTTOMLEFT true", "from the top of the cast bar's tick to the bottom of the swing timer's")
    Equal(S[cp.shown].width ~= S[cp.swing].width and ticks.width == math.max(S[cp.shown].width, S[cp.swing].width), true,
        "as wide as the wider tick")
    local swingBottom = S[cp.swing].points[1][3] - S[cp.swing].height
    local p = S[box].points[1]
    Equal(p[1] .. " " .. tostring(p[2] == cp.ticks) .. " " .. p[3] .. " " .. tostring(swingBottom + p[5] + 9 < swingBottom),
        "TOPLEFT true BOTTOMLEFT true", "the box and its arrow sit under the swing timer's tick")
    Equal(S[box.text].text:find("The second adds a swing timer", 1, true) ~= nil, true, "saying what the second tick is")
    box.next:Click()
    Equal(S[box.title].text .. " " .. Anchor(), "PROFILES TOPRIGHT BOTTOMRIGHT", "Profiles, the box lined up with its right end")
    Equal(Outlined(), tw.profileButton, "outlining the profile menu")
    -- Opened, the menu isn't covered: the box moves to its left, pointing at it.
    tw.profileButton:Click()
    Equal(tostring(S[tw.profilePanel].shown) .. " " .. Anchor() .. " " .. tostring(S[box].points[1][2] == tw.profilePanel)
        .. " " .. tostring(Outlined() == tw.profilePanel), "true TOPRIGHT TOPLEFT true true", "the menu open: the box beside it, outlining it")
    local arrow = S[box.arrow]
    Equal(tostring(arrow.shown) .. " " .. arrow.points[1][1] .. " " .. arrow.points[1][3] .. " "
        .. table.concat({ table.unpack(arrow.last.SetTexCoord, 1, 8) }, ","), "true LEFT TOPRIGHT 1,1,0,1,1,0,0,0",
        "its arrow on the right, facing the menu")
    tw.profileButton:Click()
    Equal(tostring(S[tw.profilePanel].shown) .. " " .. Anchor() .. " " .. tostring(Outlined() == tw.profileButton),
        "false TOPRIGHT BOTTOMRIGHT true", "closed again, the box goes back under the button")
    -- The menu already open as the step starts: beside it from the start.
    box.back:Click()
    tw.profileButton:Click()
    Equal(S[box.title].text .. " " .. Anchor(), "CAST BAR TOPLEFT BOTTOMLEFT", "other steps don't move for the menu")
    box.next:Click()
    Equal(S[box.title].text .. " " .. Anchor(), "PROFILES TOPRIGHT TOPLEFT", "the Profiles step starts beside the open menu")
    tw.profileButton:Click()
    Equal(Anchor(), "TOPRIGHT BOTTOMRIGHT", "and moves back as it closes")
    box.next:Click()
    Equal(S[box.count].text .. " " .. S[box.title].text, "9 of 9 THAT'S THE BASICS", "the last step")
    Equal(Outlined(), FECMMinimapButton, "pointing at the minimap button")
    Equal(S[box.text].text:find("with this button or /ccm", 1, true) ~= nil, true, "which opens these settings")
    Equal(S[box.next.label].text, "Done", "Done instead of Next")
    box.next:Click()
    Equal(S[box].shown, false, "Done ends the tour")
    Equal(S[tw].shown and S[tw.note].text, "That's the tour. Take the tour any time from the General page, or with /ccm tour.",
        "leaving the window open")
    Equal(ns.Get("useBars") and #ns.BarData("cd").spells, 1, "the tour only changed what you did yourself")

    -- Escape ends the tour first, then closes the window.
    tw:Select("general")
    tw.tour:Click()
    Equal(S[box].shown and S[box.title].text, "THE MENU", "Take the tour on the General page starts it again")
    FECMEscButton:Click()
    Equal(S[box].shown == false and S[tw].shown, true, "Escape ends the tour, the window stays")
    FECMEscButton:Click()
    Equal(S[tw].shown, false, "then Escape closes the window")
    -- Closing the window ends it too.
    SlashCmdList.FECM("tour")
    tw.close:Click()
    SlashCmdList.FECM("")
    Equal(S[tw].shown and not S[box].shown, true, "closing the window ends the tour")

    -- With your bars already on, that step says so and waits for Next.
    SlashCmdList.FECM("tour")
    box.next:Click()
    Equal(S[box.text].text:find("They're already on.", 1, true) ~= nil, true, "a step already done says so")
    S[box].scripts.OnUpdate(box, 1)
    Equal(S[box.title].text, "SWITCH YOUR BARS ON", "and waits for Next")
    box.skip:Click()
    Equal(S[box].shown, false, "Skip tour ends it")

    -- Without the minimap button, the last step points at /ccm in the footer.
    tw:Select("general")
    tw.minimap:Click()
    Equal(ns.Get("minimap") == false and S[FECMMinimapButton].shown == false, true, "the General tick hides the minimap button")
    SlashCmdList.FECM("tour")
    for _ = 1, 8 do box.next:Click() end
    Equal(Outlined() == tw.versionText and Anchor() == "BOTTOMLEFT TOPLEFT", true, "without it, the last step points at /ccm")
    Equal(S[box.text].text:find("any time with /ccm.", 1, true) ~= nil, true, "and says so")
    box.next:Click()
    tw.minimap:Click()
    Equal(S[FECMMinimapButton].shown, true, "ticking it brings the button back")
end)()

-- The minimap button --------------------------------------------------------------------

do
    Environment()
    _G.FECMFrame = nil
    ns = Load({ useBars = true })
    local mm = FECMMinimapButton
    local function At() local p = S[mm].points[1]; return string.format("%s %.1f %.1f", p[1], p[4], p[5]) end
    Equal(S[mm].shown and S[mm].parent == Minimap, true, "a minimap button, on by default")
    Equal(At(), "CENTER -52.3 -52.3", "at the minimap's bottom left, just outside its edge")
    S[mm].scripts.OnEnter(mm)
    Equal(S[GameTooltip].text .. "|" .. table.concat(S[GameTooltip].lines, "|"),
        ns.TITLE .. "|Click: settings|Right-click: What's new|Drag: move it round the minimap", "its tooltip says what it does")
    S[mm].scripts.OnClick(mm, "LeftButton")
    Equal(FECMFrame ~= nil and S[FECMFrame].shown, true, "click: the settings")
    S[mm].scripts.OnClick(mm, "LeftButton")
    Equal(S[FECMFrame].shown, false, "and again to close them")
    S[mm].scripts.OnClick(mm, "RightButton")
    Equal(FECMNotes ~= nil and S[FECMNotes].shown, true, "right-click: What's new")
    FECMNotes:Hide()
    -- Dragging: it follows the cursor round the edge, saved where it's let go.
    S[mm].scripts.OnDragStart(mm)
    Equal(mm.isMoving, true, "flagged while it's dragged, so a minimap tidier (EraUI's) doesn't fade it")
    _G.GetCursorPosition = function() return 900, 800 end
    S[mm].scripts.OnUpdate(mm, .01)
    Equal(At() .. " " .. ns.Get("minimapAngle"), "CENTER 0.0 74.0 225", "following the cursor")
    S[mm].scripts.OnDragStop(mm)
    Equal(ns.Get("minimapAngle") .. " " .. At() .. " " .. tostring(mm.isMoving), "90 CENTER 0.0 74.0 nil", "saved where it's let go")
    Equal(ForeverEnhancedCooldownManagerDB.minimapAngle, 90, "in the saved settings")
    S[mm].scripts.OnClick(mm, "LeftButton")
    Equal(S[FECMFrame].shown, false, "letting go isn't a click")
    clock = clock + 1
    S[mm].scripts.OnClick(mm, "LeftButton")
    Equal(S[FECMFrame].shown, true, "a click after that is")
    S[Minimap].width = 200
    S[Minimap].scripts.OnSizeChanged(Minimap)
    Equal(At(), "CENTER 0.0 104.0", "a bigger minimap: still on its edge")
    Equal(ns.Valid("minimapAngle", 360), false, "angles stay within a turn")
    -- Hidden mid-drag, it's let go there and doesn't trail the cursor later.
    S[mm].scripts.OnDragStart(mm)
    _G.GetCursorPosition = function() return 800, 700 end
    S[mm].scripts.OnUpdate(mm, .01)
    mm:Hide()
    Equal(ns.Get("minimapAngle") .. " " .. tostring(S[mm].scripts.OnUpdate) .. " " .. tostring(mm.isMoving), "180 nil nil",
        "hidden mid-drag, it's let go where it was")
    mm:Show()
    S[mm].scripts.OnDragStart(mm)
    _G.GetCursorPosition = function() return 900, 800 end
    S[mm].scripts.OnUpdate(mm, .01)
    S[mm].scripts.OnDragStop(mm)
    local saved = ForeverEnhancedCooldownManagerDB
    Environment(true)
    ns = Load(saved)
    local p = S[FECMMinimapButton].points[1]
    Equal(string.format("%.1f %.1f", p[4], p[5]), "0.0 74.0", "where you left it after a reload")
end

-- The Discord: found a bug or have an idea ---------------------------------------------

do
    Environment()
    _G.FECMFrame, _G.FECMCopyLink = nil, nil
    ns = Load({ useBars = true })
    SlashCmdList.FECM("")
    local tw = FECMFrame
    tw:Select("general")
    tw.discord:Click()
    local box = FECMCopyLink
    Equal(S[box].shown and S[box.title].text .. " " .. S[box.input].text, "JOIN THE DISCORD https://discord.gg/FVfcDWJncr",
        "the General page gives the Discord invite, ready to copy")
    Equal(S[box.note].text:find("Found a bug or have an idea?", 1, true) ~= nil, true, "saying what it is for")
    box.close:Click()
    SlashCmdList.FECM("discord")
    Equal(S[box].shown, true, "/ccm discord does too")
    box.close:Click()
    SlashCmdList.FECM("new")
    local notes = FECMNotes
    Equal(S[notes.ask].text, "Found a bug or have an idea?", "What's new asks")
    Equal(S[notes.discord].points[1][2], notes.done, "with a Discord button beside Got it")
    notes.discord:Click()
    Equal(S[box].shown, true, "which gives the invite")
end

print = _G.print
io.write("Bars and window checks passed: " .. checks .. " assertions.\n")
