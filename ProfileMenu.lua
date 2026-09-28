-- The profile menu in the /fecm window's header: the profile this character
-- uses, and a panel under it listing every profile (click one to switch, or
-- its x to delete it after asking) with a box to type a name for New, Copy
-- or Rename. Profiles hold the spell lists only; the rules live in Core.lua.
local _, ns = ...
local T = ns.Theme

local WIDTH, ROW = 300, 22

local function Users(name)
    local count = ns.ProfileUsers(name)
    local mine = name == ns.ProfileName()
    if mine and count > 1 then return "you + " .. (count - 1) end
    if mine then return "you" end
    if count == 0 then return "unused" end
    return count == 1 and "1 character" or (count .. " characters")
end

function ns.BuildProfileMenu(window, header, anchor)
    local button = T:Button(header, "", 280, 24)
    button:SetPoint("RIGHT", anchor, "LEFT", -8, 0)
    button.label:SetWidth(264)
    button.label:SetWordWrap(false)
    window.profileButton = button

    local panel = CreateFrame("Frame", nil, window, "BackdropTemplate")
    panel:SetPoint("TOPRIGHT", button, "BOTTOMRIGHT", 0, -4)
    panel:SetSize(WIDTH, 200) -- sized again on every refresh
    panel:SetFrameLevel(window:GetFrameLevel() + 60)
    T:Flat(panel, T.PANEL, T.CONTROL_BORDER)
    panel:EnableMouse(true)
    panel:Hide()
    window.profilePanel = panel
    T:Heading(panel, "Profiles"):SetPoint("TOPLEFT", 10, -10)

    -- Deleting asks first, in a small dialog over the whole window.
    local shade = CreateFrame("Frame", nil, window)
    shade:SetAllPoints()
    shade:SetFrameLevel(window:GetFrameLevel() + 80)
    shade:EnableMouse(true) -- nothing behind it can be clicked meanwhile
    local dim = shade:CreateTexture(nil, "BACKGROUND")
    dim:SetAllPoints()
    dim:SetColorTexture(0, 0, 0, .45)
    shade:Hide()
    local dialog = CreateFrame("Frame", nil, shade, "BackdropTemplate")
    dialog:SetSize(320, 112)
    dialog:SetPoint("CENTER")
    T:Flat(dialog, T.PANEL, T.CONTROL_BORDER)
    dialog.title = T:Text(dialog, "GameFontHighlight")
    dialog.title:SetPoint("TOPLEFT", 14, -14)
    dialog.title:SetWidth(292)
    dialog.title:SetWordWrap(false)
    dialog.detail = T:Text(dialog, "GameFontHighlightSmall", T.MUTED)
    dialog.detail:SetPoint("TOPLEFT", 14, -36)
    dialog.detail:SetWidth(292)
    local yes = T:Button(dialog, "Delete", 90, 22)
    yes:SetPoint("BOTTOMRIGHT", -14, 14)
    yes.label:SetTextColor(T.WARN[1], T.WARN[2], T.WARN[3])
    local no = T:Button(dialog, "Cancel", 90, 22)
    no:SetPoint("RIGHT", yes, "LEFT", -6, 0)
    window.confirm = { shade = shade, dialog = dialog, yes = yes, no = no }

    local pending
    local function Ask(name)
        -- A profile another character uses can't go: say so rather than ask.
        local ok, why = ns.CanDeleteProfile(name)
        if not ok then
            window:Say(why)
            return window:Refresh()
        end
        pending = name
        dialog.title:SetText(('Delete "%s"?'):format(name))
        dialog.detail:SetText(name == ns.ProfileName()
            and "You're using it, so you'll move to a new, empty profile of your own. This can't be undone."
            or "This can't be undone.")
        shade:Show()
    end
    local function Close()
        pending = nil
        shade:Hide()
    end
    no:SetScript("OnClick", Close)
    yes:SetScript("OnClick", function()
        local name = pending
        local mine = name == ns.ProfileName()
        Close()
        local ok, message = ns.DeleteProfile(name)
        window:Say(message)
        -- Deleting your own profile moves you, so the menu closes as for any switch.
        if ok and mine then panel:Hide() end
        window:Refresh()
    end)
    window:HookScript("OnHide", Close)

    local rows = {}
    local function Row(i)
        if rows[i] then return rows[i] end
        local row = CreateFrame("Button", nil, panel)
        row:SetSize(WIDTH - 20, ROW - 2)
        row:SetPoint("TOPLEFT", 10, -28 - (i - 1) * ROW)
        row.fill = row:CreateTexture(nil, "BACKGROUND")
        row.fill:SetAllPoints()
        T:Fill(row.fill, T.SELECTED)
        row.mark = row:CreateTexture(nil, "ARTWORK")
        row.mark:SetPoint("TOPLEFT")
        row.mark:SetPoint("BOTTOMLEFT")
        row.mark:SetWidth(3)
        T:Paint(function(accent) T:Fill(row.mark, accent) end)
        local hover = row:CreateTexture(nil, "HIGHLIGHT")
        hover:SetAllPoints()
        hover:SetColorTexture(1, 1, 1, .05)
        row.name = T:Text(row, "GameFontHighlight")
        row.name:SetPoint("LEFT", 10, 0)
        row.name:SetWidth(160)
        row.name:SetWordWrap(false)
        row.remove = T:Square(row, "x")
        row.remove:SetSize(16, 16)
        row.remove:SetPoint("RIGHT", -2, 0)
        row.remove:SetScript("OnClick", function() Ask(row.profile) end)
        row.users = T:Text(row, "GameFontHighlightSmall", T.MUTED)
        row.users:SetPoint("RIGHT", row.remove, "LEFT", -8, 0)
        row.users:SetJustifyH("RIGHT")
        row:SetScript("OnClick", function(self)
            local ok, message = ns.UseProfile(self.profile)
            window:Say(message)
            if ok then panel:Hide() end
            window:Refresh()
        end)
        rows[i] = row
        return row
    end

    -- Placed now as for one profile, then moved under the list on refresh, so
    -- nothing is ever laid out without a place.
    local input = T:Input(panel, "Profile name", WIDTH - 20)
    input:SetPoint("TOPLEFT", 10, -54)
    window.profileInput = input
    local hint = T:Text(panel, "GameFontHighlightSmall", T.MUTED)
    hint:SetPoint("TOPLEFT", 10, -110)
    hint:SetWidth(WIDTH - 20)
    hint:SetText("Click a profile to use it, or x to delete it. Type a name to make, copy or rename one.")

    -- Each button acts on the typed name. Every one of them leaves you on a
    -- different profile or name, so the menu closes once it has worked.
    local function Act(action)
        return function()
            local ok, message = action(input:GetText())
            window:Say(message)
            if ok then
                input:SetText("")
                input:ClearFocus()
                input.placeholder:Show()
                panel:Hide()
            end
            window:Refresh()
        end
    end
    local buttons = {}
    local x = 10
    for _, spec in ipairs({ { "New", ns.NewProfile }, { "Copy", ns.CopyProfile }, { "Rename", ns.RenameProfile } }) do
        local action = T:Button(panel, spec[1], 90, 22)
        action:SetPoint("TOPLEFT", x, -80)
        action.x = x
        action:SetScript("OnClick", Act(spec[2]))
        buttons[spec[1]:lower()] = action
        x = x + 94
    end
    window.profileActions = buttons

    button:SetScript("OnClick", function()
        panel:SetShown(not panel:IsShown())
        window:Refresh()
    end)
    window:HookScript("OnHide", function() panel:Hide() end)

    function window:RefreshProfiles()
        local current = ns.ProfileName()
        button:SetLabel("|cff8b8d92Profile|r   " .. (current or "loading..."))
        if not panel:IsShown() then return end
        local names = ns.ProfileNames()
        for i, name in ipairs(names) do
            local row = Row(i)
            row.profile = name
            row.name:SetText(name)
            row.users:SetText(Users(name))
            local chosen = name == current
            row.fill:SetShown(chosen)
            row.mark:SetShown(chosen)
            row:Show()
        end
        for i = #names + 1, #rows do rows[i]:Hide() end
        -- The box, buttons and hint follow the list.
        local y = 32 + #names * ROW
        input:ClearAllPoints()
        input:SetPoint("TOPLEFT", 10, -y)
        for _, action in pairs(buttons) do
            action:ClearAllPoints()
            action:SetPoint("TOPLEFT", action.x, -(y + 26))
        end
        hint:ClearAllPoints()
        hint:SetPoint("TOPLEFT", 10, -(y + 56))
        panel:SetHeight(y + 92)
    end
end
