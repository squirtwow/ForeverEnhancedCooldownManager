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

function ns.DebugReport()
    local lines = {}
    local function Add(text) lines[#lines + 1] = text end
    local version, build = GetBuildInfo and GetBuildInfo()
    local _, class = UnitClass("player")
    Add(("%s %s | game %s (%s) | %s level %s | in combat %s"):format(ns.TITLE or "FECM", ns.Version(), Say(version), Say(build),
        Say(class), Say(UnitLevel and UnitLevel("player")), tostring(InCombatLockdown())))
    Add(("Look: icon border %s, shadow %s, ready glow %s"):format(tostring(ns.Get("iconBorder")), tostring(ns.Get("iconShadow")),
        tostring(ns.Get("readyGlow"))))
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
