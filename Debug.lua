-- /ccm debug: a report of your bars and their icons, ready to copy, for a
-- player to paste to us when something doesn't look right (first asked for
-- a player's Riposte glow). Never announced (the user): a support tool to
-- ask players for. It only reads: it never changes a setting.
-- Answers the game keeps secret in a fight read "secret".
local _, ns = ...
local T = ns.Theme

local frame

local function Say(value)
    if issecretvalue and issecretvalue(value) then return "secret" end
    return tostring(value)
end

-- A word in each language a font may not write (Chinese, Korean, Russian),
-- measured in each font on a hidden line, English first, for scale. Letters
-- a font lacks don't measure 0 (an English game gave 16 for two Chinese
-- letters in every font), so compare: the font that draws them measures
-- them differently from the rest.
local SAMPLES = { { "en", "Abc" }, { "zh", "中文" }, { "ko", "한글" }, { "ru", "Рус" } }
local measure

local function Width(file, text)
    if not measure then
        measure = UIParent:CreateFontString(nil, "BACKGROUND")
        measure:Hide()
    end
    local ok, done = pcall(measure.SetFont, measure, file, 12, "")
    if not ok or done == false then return "refused" end
    measure:SetText(text)
    return tostring(math.floor((measure:GetStringWidth() or 0) + .5))
end

-- The fonts: your game's language and its own font, each setting's font,
-- the file the addon's text is in now, and each font's sample widths.
local function Fonts(Add)
    local Style = ns.Style
    local inUse = _G[Style:Font(13)]
    Add(("Fonts: game language %s, game font %s, Game font first %s"):format(Say(GetLocale and GetLocale()),
        Say(STANDARD_TEXT_FONT), tostring(ns.GAME_FONT_FIRST)))
    Add(("Font %s, text %s, raid warnings %s; in use %s"):format(tostring(ns.Get("font")), tostring(ns.Get("prdTextFont")),
        tostring(ns.Get("warningFont")), Say(inUse and inUse.GetFont and inUse:GetFont())))
    for _, key in ipairs(ns.FONT_KEYS) do
        local file, widths = Style.FONTS[key], {}
        for _, sample in ipairs(SAMPLES) do widths[#widths + 1] = sample[1] .. " " .. Width(file, sample[2]) end
        Add(("  %s (%s): %s"):format(key, tostring(file), table.concat(widths, ", ")))
    end
    -- Countdown numbers in the font in use: the same widths mean every digit
    -- is as wide as the rest, so a thin 1 leaves room beside it (17 and 13
    -- sit a little right of 29 in Friz Quadrata).
    local file = Style:FontFile()
    Add(("  digits in the font in use: 29 %s, 17 %s, 13 %s, 11 %s"):format(Width(file, "29"), Width(file, "17"), Width(file, "13"),
        Width(file, "11")))
    -- Settings per spell: each entry's own countdown font and size.
    local looks, own = {}, ns.ProfileLists and ns.ProfileLists().spellLook
    for name, look in pairs(type(own) == "table" and own or {}) do
        if type(look) == "table" then
            looks[#looks + 1] = ("%s (%s, %s)"):format(tostring(name), tostring(look.font or "look"),
                look.size and (look.size .. "%") or "look")
        end
    end
    table.sort(looks)
    Add("Own countdowns: " .. (#looks > 0 and table.concat(looks, ", ") or "none"))
end

-- Heals on their way to you and the shields on you (the health bar's
-- Incoming heals and Absorbs text): whether the game has the calls, what
-- each says now (a number, none, or secret) and, for a secret, whether the
-- game's own text for it comes out blank (nothing there) or not (the server
-- sent one), measured on a hidden line of the report's own. Then what each
-- end of the health bar shows.
local probe

local function Shows(value)
    local util = C_StringUtil
    if not (util and util.TruncateWhenZero) then return "" end
    local ok, width = pcall(function()
        if not probe then
            probe = UIParent:CreateFontString(nil, "BACKGROUND")
            probe:Hide()
            probe:SetFont(ns.Style:FontFile(), 12, "")
        end
        probe:SetText(util.TruncateWhenZero(value))
        return probe:GetStringWidth()
    end)
    if not ok then return " (refused)" end
    if type(width) ~= "number" or (issecretvalue and issecretvalue(width)) then return " (can't tell)" end
    return width > 0 and " (sent)" or " (blank)"
end

local function Now(call, ...)
    if type(call) ~= "function" then return "no call" end
    local ok, value = pcall(call, ...)
    if not ok then return "refused" end
    if type(value) == "nil" then return "none" end
    if issecretvalue and issecretvalue(value) then return "secret" .. Shows(value) end
    return tostring(value)
end

local function Heals(Add)
    local util = C_StringUtil
    local blank = util ~= nil and util.TruncateWhenZero ~= nil and util.WrapString ~= nil
    Add(("Heals and absorbs: incoming %s, from you %s, absorbs %s, blank at 0 %s | health text %s at %s, left %s, right %s"):format(
        Now(UnitGetIncomingHeals, "player"), Now(UnitGetIncomingHeals, "player", "player"), Now(UnitGetTotalAbsorbs, "player"),
        tostring(blank), tostring(ns.Get("prdText")), tostring(ns.Get("prdHealthAt")), tostring(ns.Get("prdHealthLeft")),
        tostring(ns.Get("prdHealthRight"))))
end

-- Warn at N seconds left: each aura bar's warned entries, whether the game
-- made the red numbers' rules, and whether each bar has its edge slots; then
-- the entries ticked Dim until Warn at, if any (each entry's line says
-- whether its dimmed icon is on, or the game turned it down).
local function Warns(Add)
    local list, edges, keys, dims = {}, {}, {}, {}
    for _, key in ipairs(ns.BAR_KEYS) do
        if ns.AURA_BARS[key] then keys[#keys + 1] = key end -- (Buffs 2 and Debuffs 2 too, once added)
    end
    for _, key in ipairs(keys) do
        local names, dimmed = {}, {}
        for name, seconds in pairs(ns.WarnAt(key)) do names[#names + 1] = ("%s %ss"):format(tostring(name), tostring(seconds)) end
        table.sort(names)
        if #names > 0 then list[#list + 1] = key .. ": " .. table.concat(names, ", ") end
        for name in pairs(ns.DimUntilWarn and ns.DimUntilWarn(key) or {}) do dimmed[#dimmed + 1] = tostring(name) end
        table.sort(dimmed)
        if #dimmed > 0 then dims[#dims + 1] = key .. ": " .. table.concat(dimmed, ", ") end
        local bar = ns.Bars and ns.Bars.started and ns.Bars:Get(key)
        edges[#edges + 1] = key .. " " .. (not bar and "not made" or bar.marks and "made" or "none")
    end
    local refused = ns.BuffBar and ns.BuffBar.markError
    Add(("Warn at: %s | numbers: %s | edge slots: %s%s%s"):format(#list > 0 and table.concat(list, "; ") or "none",
        ns.Style:WarnReport(), table.concat(edges, ", "), refused and ("; refused: " .. refused) or "",
        #dims > 0 and (" | dim until Warn at: " .. table.concat(dims, "; ")) or ""))
end

function ns.DebugReport()
    local lines = {}
    local function Add(text) lines[#lines + 1] = text end
    local version, build = GetBuildInfo and GetBuildInfo()
    local _, class = UnitClass("player")
    Add(("%s %s | game %s (%s) | %s level %s | in combat %s"):format(ns.TITLE or "FECM", ns.Version(), Say(version), Say(build),
        Say(class), Say(UnitLevel and UnitLevel("player")), tostring(InCombatLockdown())))
    Add(("Look: icon border %s, shadow %s, ready glow %s, icons %s%s"):format(tostring(ns.Get("iconBorder")), tostring(ns.Get("iconShadow")),
        tostring(ns.Get("readyGlow")), tostring(ns.Get("iconStyle")), ns.Style and ns.Style:ShapeReport() or ""))
    -- The design, and whether bars fade (or why not: the game refused a gradient).
    Add(("Bars: design %s, colour fade %s%s"):format(tostring(ns.Get("barStyle")), tostring(ns.Get("colourFade")),
        ns.Style and ns.Style.fadeError and (", refused: " .. ns.Style.fadeError) or ""))
    -- Icon details' countdown, and how its Timer text went.
    Add(("Countdown: size %s%%, spot %s, text %s%s"):format(tostring(ns.Get("countdownSize")), tostring(ns.Get("countdownSpot")),
        tostring(ns.Get("countdownFormat")), ns.Style and ns.Style:TimerReport() or ""))
    if ns.Style then Warns(Add) end
    -- The Cooldown pulse's procs: what the game took, and what it keeps secret.
    if ns.Pulse and ns.Pulse.ProcReport then ns.Pulse:ProcReport(Add) end
    Heals(Add)
    if ns.Style then Fonts(Add) end
    if ns.Bars and ns.Bars.Report then ns.Bars:Report(Add, Say) end
    return table.concat(lines, "\n")
end

local function Build()
    frame = CreateFrame("Frame", "FECMDebugFrame", UIParent, "BackdropTemplate")
    frame:SetSize(620, 380)
    frame:SetPoint("CENTER")
    -- The /ccm window's layer, raised as it shows, so it's never behind it
    -- (as the Discord link box).
    frame:SetFrameStrata("FULLSCREEN_DIALOG")
    frame:SetToplevel(true)
    frame:SetClampedToScreen(true)
    frame:EnableMouse(true)
    frame:SetMovable(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", frame.StartMoving)
    frame:SetScript("OnDragStop", frame.StopMovingOrSizing)
    -- Closed mid-drag (Escape), it never hears the mouse let go: stop moving now.
    frame:SetScript("OnHide", frame.StopMovingOrSizing)
    T:Flat(frame, T.BG, T.BORDER)
    local title = T:Text(frame, "GameFontNormal")
    title:SetPoint("TOPLEFT", 12, -12)
    title:SetText("Debug report: press Ctrl+C to copy it, then paste it to whoever asked.")
    -- Pinned by two corners, so it draws (an unsized scroll frame may not).
    local scroll = CreateFrame("ScrollFrame", nil, frame, "UIPanelScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT", 12, -36)
    scroll:SetPoint("BOTTOMRIGHT", -32, 44)
    local edit = CreateFrame("EditBox", nil, scroll)
    edit:SetMultiLine(true)
    edit:SetAutoFocus(false)
    edit:SetFontObject(ChatFontNormal or GameFontHighlightSmall)
    edit:SetWidth(570)
    edit:SetScript("OnEscapePressed", function() frame:Hide() end)
    -- A click in it selects it all again, so Ctrl+C still copies it all.
    edit:SetScript("OnEditFocusGained", function(self) self:HighlightText() end)
    edit:SetScript("OnMouseUp", function(self) self:HighlightText() end)
    -- Typing in it puts the report back, all selected, ready to copy.
    edit:SetScript("OnTextChanged", function(self, typed)
        if typed then
            self:SetText(frame.report or "")
            self:HighlightText()
        end
    end)
    scroll:SetScrollChild(edit)
    local close = T:Button(frame, "Close", 90, 22)
    close:SetPoint("BOTTOMRIGHT", -12, 12)
    close:SetScript("OnClick", function() frame:Hide() end)
    frame.edit, frame.close = edit, close
    if UISpecialFrames then table.insert(UISpecialFrames, "FECMDebugFrame") end
end

function ns.ShowDebug()
    if not frame then Build() end
    frame.report = ns.DebugReport()
    frame.edit:SetText(frame.report)
    frame:Show()
    frame:Raise()
    frame.edit:SetFocus()
    frame.edit:HighlightText()
end
