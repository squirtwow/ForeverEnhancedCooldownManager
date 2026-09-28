-- Development check for Classic Bars (step 2). NOT FOR RELEASE: remove this
-- file from the TOC before packaging.
-- /fecm check [spell]: for 20 seconds, prints once a second whether the game
-- hides from addons the values the bars would use in combat, shows a test
-- sweep above the character for that spell's cooldown, and reports any proc
-- glow events.
local _, ns = ...

local TICKS = 20
local DEFAULT_SPELL = {
    DRUID = "Moonfire", WARRIOR = "Overpower", ROGUE = "Sinister Strike", HUNTER = "Raptor Strike",
    MAGE = "Fire Blast", PRIEST = "Smite", SHAMAN = "Earth Shock", WARLOCK = "Shadow Bolt",
    PALADIN = "Judgement",
}
local SELF_BUFF = { DRUID = { name = "thorns", ids = { 467, 782, 1075, 8914, 9756, 9910 } } }

local running, sweep, events, firstError

local function Say(text)
    print("|cffffd100FECM check|r " .. text)
end

local function Hidden(value)
    if not issecretvalue then return "n/a" end
    return issecretvalue(value) and "hidden" or "open"
end

local function Secrets()
    local S = C_Secrets
    if not (S and S.ShouldCooldownsBeSecret and S.ShouldAurasBeSecret) then return "secrets api=missing" end
    return ("secret cooldowns=%s auras=%s"):format(tostring(S.ShouldCooldownsBeSecret()), tostring(S.ShouldAurasBeSecret()))
end

local function Methods(object)
    local meta = object ~= nil and getmetatable(object)
    local index = type(meta) == "table" and meta.__index
    if type(index) ~= "table" then return type(object) end
    local names = {}
    for name in pairs(index) do names[#names + 1] = name end
    table.sort(names)
    return type(object) .. ": " .. table.concat(names, ", ")
end

local function Build()
    sweep = CreateFrame("Frame", nil, UIParent)
    sweep:SetSize(48, 48)
    sweep:SetPoint("CENTER", 0, 140)
    sweep.icon = sweep:CreateTexture(nil, "ARTWORK")
    sweep.icon:SetAllPoints()
    sweep.cd = CreateFrame("Cooldown", nil, sweep, "CooldownFrameTemplate")
    sweep.cd:SetAllPoints()
    events = CreateFrame("Frame")
    events:SetScript("OnEvent", function(_, event, spellID)
        Say(("%s spell=%s (%s)"):format(event, tostring(spellID), Hidden(spellID)))
    end)
end

local function Tick(state)
    state.n = state.n + 1
    local spell = state.spell
    local combat = InCombatLockdown()
    if combat and not state.sawCombat then
        state.sawCombat = true
        Say("in combat: " .. Secrets())
    end
    local usable = C_Spell.IsSpellUsable(spell)
    local cooldown = C_Spell.GetSpellCooldown(spell)
    local sweepResult = "no api"
    if C_Spell.GetSpellCooldownDuration then
        local duration = C_Spell.GetSpellCooldownDuration(spell)
        if duration == nil then
            sweepResult = "nil"
        else
            local ok, err = pcall(sweep.cd.SetCooldownFromDurationObject, sweep.cd, duration)
            sweepResult = ok and "ok" or ("error " .. tostring(err))
        end
    end
    local buff = "-"
    if state.buff then
        buff = "missing"
        for _, id in ipairs(state.buff.ids) do
            if C_UnitAuras.GetPlayerAuraBySpellID(id) then buff = "found" break end
        end
    end
    -- Only changes are printed, so the whole run fits in one chat screenshot.
    local summary = ("combat=%s usable=%s cooldown=%s sweep=%s %s=%s"):format(
        combat and "yes" or "no", Hidden(usable), cooldown and Hidden(cooldown.duration) or "nil",
        sweepResult, state.buff and state.buff.name or "buff", buff)
    if summary ~= state.last then
        state.last = summary
        Say(("%d/%d %s"):format(state.n, TICKS, summary))
    end
end

local function Stop()
    running = nil
    sweep:Hide()
    events:UnregisterAllEvents()
    Say("done. Please screenshot the chat.")
end

-- /fecm check list: what the window's spell list holds, and where the game
-- has placed it. Also kept in the saved settings (probe), read after a reload.
local function Rect(frame)
    if not frame then return "missing" end
    local left, bottom, width, height = frame:GetRect()
    return ("shown=%s visible=%s level=%s strata=%s alpha=%.2f rect=%s,%s %sx%s"):format(
        tostring(frame:IsShown()), tostring(frame:IsVisible()), tostring(frame:GetFrameLevel()),
        tostring(frame:GetFrameStrata()), frame:GetEffectiveAlpha() or -1,
        tostring(left and math.floor(left)), tostring(bottom and math.floor(bottom)),
        tostring(width and math.floor(width)), tostring(height and math.floor(height)))
end

local function ProbeList()
    local window = ns.window
    local page = window and window.pages and window.pages.bar
    if not page then Say("open /fecm first.") return end
    local lines = {}
    local function Add(text)
        lines[#lines + 1] = text
        Say(text)
    end
    local scroll = page.list
    Add(("page=%s entries=%d error=%s search=%q"):format(tostring(window.selected), #ns.Spells:List(),
        tostring(page.listError), tostring(page.search:GetText())))
    Add("window " .. Rect(window))
    Add("page " .. Rect(page))
    Add("panel " .. Rect(page.listPanel))
    Add("scroll " .. Rect(scroll) .. (" offset=%s range=%s clips=%s"):format(tostring(scroll:GetVerticalScroll()),
        tostring(scroll:GetVerticalScrollRange()), tostring(scroll.DoesClipChildren and scroll:DoesClipChildren())))
    Add("content " .. Rect(scroll.content) .. " child=" .. tostring(scroll:GetScrollChild() == scroll.content)
        .. " kids=" .. tostring(scroll.content:GetNumChildren()))
    local shown, listed = 0, 0
    for _, row in ipairs(page.rows) do
        if row:IsShown() then
            shown = shown + 1
            if listed < 3 then
                listed = listed + 1
                local text = row.header:IsShown() and row.header:GetText() or row.name:GetText()
                Add(("row%d %s text=%s"):format(listed, Rect(row), tostring(text)))
                local label = row.header:IsShown() and row.header or row.name
                local left, bottom, width, height = label:GetRect()
                Add(("  label visible=%s rect=%s,%s %sx%s font=%s"):format(tostring(label:IsVisible()),
                    tostring(left and math.floor(left)), tostring(bottom and math.floor(bottom)),
                    tostring(width and math.floor(width)), tostring(height and math.floor(height)),
                    tostring(label:GetFont())))
            end
        end
    end
    Add(("rows made=%d shown=%d"):format(#page.rows, shown))

    local key = window.selected
    local data = ns.BarData(key)
    local timer = page.options and page.options.showTimer
    if data then
        Add(("data %s showTimer=%s ticked=%s hideReady=%s size=%s"):format(key, tostring(data.showTimer),
            tostring(timer and timer.checked), tostring(data.hideReady), tostring(data.size)))
    end
    Add("tray " .. Rect(page.tray) .. " options " .. Rect(page.size and page.size:GetParent()))
    C_Timer.After(.3, function()
        local left, bottom, width, height = scroll:GetRect()
        Add(("later: scroll points=%d rect=%s"):format(scroll:GetNumPoints(),
            left and (math.floor(width) .. "x" .. math.floor(height)) or "nil"))
        if type(ForeverEnhancedCooldownManagerDB) == "table" then
            ForeverEnhancedCooldownManagerDB.probe = lines
            Say("saved. /reload so the results reach the settings file.")
        end
    end)
end

function ns.Probe(msg)
    if msg:match("^%s*check%s+list%s*$") then return ProbeList() end
    if running then Say("already running.") return end
    local _, class = UnitClass("player")
    local spell = msg:match("^%s*check%s+(.-)%s*$")
    if not spell or spell == "" then spell = DEFAULT_SPELL[class] or "Attack" end
    if not C_Spell.GetSpellInfo(spell) then Say("you don't know " .. spell .. ". Try /fecm check <spell name>.") return end
    if not sweep then Build() end
    sweep.icon:SetTexture(C_Spell.GetSpellTexture(spell))
    sweep:Show()
    events:RegisterEvent("SPELL_ACTIVATION_OVERLAY_GLOW_SHOW")
    events:RegisterEvent("SPELL_ACTIVATION_OVERLAY_GLOW_HIDE")
    local state = { n = 0, spell = spell, buff = SELF_BUFF[class] }
    Say(("start: %s for %d seconds. Get into a fight and cast it. %s"):format(spell, TICKS, Secrets()))
    if C_Spell.GetSpellCooldownDuration then
        Say("duration object " .. Methods(C_Spell.GetSpellCooldownDuration(spell)))
    end
    running = C_Timer.NewTicker(1, function(ticker)
        local ok, err = pcall(Tick, state)
        if not ok and not firstError then
            firstError = tostring(err)
            Say("error: " .. firstError)
        end
        if state.n >= TICKS or not ok then
            ticker:Cancel()
            Stop()
        end
    end)
end

-- Old /fecm check list results are cleared at the next login.
local cleaner = CreateFrame("Frame")
cleaner:RegisterEvent("ADDON_LOADED")
cleaner:SetScript("OnEvent", function(self, _, name)
    if name ~= "ForeverEnhancedCooldownManager" then return end
    self:UnregisterAllEvents()
    if type(ForeverEnhancedCooldownManagerDB) == "table" then ForeverEnhancedCooldownManagerDB.probe = nil end
end)
