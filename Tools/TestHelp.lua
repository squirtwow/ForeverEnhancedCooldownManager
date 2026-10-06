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
            rawset(f, "SetUnit", function(_, unit) S[f].unit = unit end)
            rawset(f, "UpdateAllAuras", function() S[f].refreshes = (S[f].refreshes or 0) + 1 end)
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
            S[f].template = template
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
    _G.EditModeManagerFrame = New("Frame")
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
    _G.PlaySound = function() end
    _G.C_Spell.GetSpellCooldown = function() return { isEnabled = true } end
    _G.GetSpellBaseCooldown = nil
    S[UIParent].width, S[UIParent].height = 1366, 768
end

-- Every file in the order the .toc loads them (Tools/TestRules.mjs checks the .toc).
local FILES = { "Core.lua", "Style.lua", "Skin.lua", "Resource.lua", "CastBar.lua", "RaidTimers.lua", "Ranks.lua", "Spells.lua",
    "Keybinds.lua", "Buffs.lua", "IconAuras.lua", "Bars.lua", "Pulse.lua", "Layout.lua", "Theme.lua", "BarPage.lua",
    "LayoutPage.lua", "CastBarPage.lua", "RaidTimersPage.lua", "PulsePage.lua", "ProfileMenu.lua", "Window.lua", "Tour.lua",
    "MinimapButton.lua", "Notes.lua", "Debug.lua" }
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
function Fit.Problems(root)
    local list, found = Fit.Pieces(root), {}
    local rl, rt, rr, rb = Fit.Rect(root)
    for i, a in ipairs(list) do
        if a[1] < rl or a[3] > rr or a[2] < rt or a[4] > rb then found[#found + 1] = a.name .. " off the page" end
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
        "true THE LOOK 1 of 4 | false false", "? clicked: the Look page's walkthrough, the pulse and note gone, saved")
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
    local function Check(key, label)
        w:Select(key)
        local problems = Fit.Problems(w.pages[key] or w.pages.bar)
        if problems ~= "" then found[#found + 1] = (label or key) .. ": " .. problems end
    end
    for _, key in ipairs({ "cd", "util", "buff", "debuff", "look", "layout", "cast", "general", "pulse" }) do Check(key) end
    local problems = Fit.Problems(w.navFrame) .. Fit.Problems(w.header)
    if problems ~= "" then found[#found + 1] = "list or title bar: " .. problems end
    -- Look, with Blizzard's Cooldown Manager and your display off, a reload
    -- waiting: the warnings take their rows' room.
    cvarOn, prdOn = false, false
    ns.Set("prdSkin", true)
    ns.Set("skin", not ns.Get("skin"))
    Check("look", "look with warnings")
    cvarOn, prdOn = true, true
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
    Equal(table.concat(found, " | "), "", "on every page and in every state, each label clear of the next control, all inside the page")
    Equal(#printed, 0, "no errors")
end)()

Equal(#printed, 0, "no errors")

print = _G.print
io.write("Page help and fit checks passed: " .. checks .. " assertions.\n")
