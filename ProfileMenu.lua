-- The profile menu in the /ccm window's header: the profile this character
-- uses, and a panel under it listing every profile (click one to switch, or
-- its x to delete it after asking) with a box to type a name for New, Copy
-- or Rename. Profiles hold the spell lists only; the rules live in Core.lua.
local _, ns = ...
local T = ns.Theme

local WIDTH, ROW = 300, 22

local function Users(name)
    if ns.OnAll(name) then return "all characters" end
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

    -- Deleting asks first, in the window's own dialog.
    local function Ask(name)
        -- A profile another character uses can't go: say so rather than ask.
        local ok, why = ns.CanDeleteProfile(name)
        if not ok then
            window:Say(why)
            return window:Refresh()
        end
        local mine = name == ns.ProfileName()
        window:Ask(('Delete "%s"?'):format(name), mine
            and "You're using it, so you'll move to a new, empty profile of your own. This can't be undone."
            or "This can't be undone.", "Delete", function()
            local done, message = ns.DeleteProfile(name)
            window:Say(message)
            -- Deleting your own profile moves you, so the menu closes as for any switch.
            if done and mine then panel:Hide() end
            window:Refresh()
        end)
    end

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
    hint:SetPoint("TOPLEFT", 10, -136)
    hint:SetWidth(WIDTH - 20)
    hint:SetText("Click a profile to use it, or x to delete it. Type a name to make, copy or rename one. "
        .. "Any class can share a profile: each character only shows its own spells.")

    -- The profile you're on, for every character and any made later.
    local everyone = T:Button(panel, "Use on all characters", WIDTH - 20, 22)
    everyone:SetPoint("TOPLEFT", 10, -106)
    everyone:SetScript("OnClick", function()
        local name = ns.ProfileName()
        if not name then return end
        if ns.OnAll(name) then
            window:Say("All your characters already use " .. name .. ".")
            return window:Refresh()
        end
        window:Ask(('Use "%s" on all characters?'):format(name),
            "Every character, and any you make later, loads it. Each only shows its own class's spells. Their own profiles stay in this list.",
            "Use on all", function()
                local _, message = ns.UseOnAll()
                window:Say(message)
                panel:Hide()
                window:Refresh()
            end)
    end)
    everyone:HookScript("OnEnter", function()
        window.note:SetText("Loads the profile you're on for every character. Each one only shows its own class's spells.")
    end)
    everyone:HookScript("OnLeave", function() window.note:SetText(window.lastNote or "") end)
    window.profileEveryone = everyone

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
        everyone:ClearAllPoints()
        everyone:SetPoint("TOPLEFT", 10, -(y + 52))
        local onAll = ns.OnAll(current)
        everyone:SetLabel(onAll and "On all characters" or "Use on all characters")
        everyone:SetAlpha(onAll and .5 or 1)
        hint:ClearAllPoints()
        hint:SetPoint("TOPLEFT", 10, -(y + 82))
        panel:SetHeight(y + 92 + math.max(28, math.ceil(hint:GetStringHeight() or 28)))
    end
end
