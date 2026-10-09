-- The profile menu in the /ccm window's header: the profile this character
-- uses, and a panel under it listing every profile (click one to switch, or
-- its x to delete it after asking) with a box to type a name for New, Copy
-- or Rename, and Share and Import at its top (ProfileShare.lua). At its foot,
-- Roles: Tank, Healer and Damage, a profile for each, and Switch with my
-- talents with each talent tree's role (or None) under it. Profiles hold the spell
-- lists only (the bars', and the Cooldown pulse's ticks); the rules live in
-- Core.lua.
local _, ns = ...
local T = ns.Theme

local WIDTH, ROW = 300, 22
local LIST_ROWS = 7 -- profiles listed at once; more scroll (7 since Positions per profile took a row)
-- The menu's tallest: it hangs 38 down the 560-tall window and stays clear
-- of the footer's line (539 down), so a hover note there is never under it
-- (Tools/TestHelp.lua measures it).
local MENU_MAX = 496
local LIST_WIDTH = WIDTH - 28 -- the list, clear of its scroll thumb
-- A talent tree's Tank, Healer, Damage and None, at the right: each as wide
-- as its word needs (together the choice less its 2 edges), so the tree's
-- name and points keep their room.
local TREE_CHOICE = 156
local TREE_WIDTHS = { tank = 32, healer = 45, damage = 45, none = 32 }
local TICK_ROW = 24 -- the Switch with my talents tick's own row, under the role buttons
local PLACES_ROW = 22 -- the Positions per profile tick's own row, under Use on all characters
local UNTESTED = " (Needs testing)" -- the roles and talents, until they're seen in game

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
    window:Hint(button, "The profile this character uses: its spell lists and Cooldown pulse ticks. Click for every profile, to switch or make one.")
    window.profileButton = button

    local panel = CreateFrame("Frame", nil, window, "BackdropTemplate")
    panel:SetPoint("TOPRIGHT", button, "BOTTOMRIGHT", 0, -4)
    panel:SetSize(WIDTH, 200) -- sized again on every refresh
    panel:SetFrameLevel(window:GetFrameLevel() + 60)
    panel:SetClampedToScreen(true)
    T:Flat(panel, T.PANEL, T.CONTROL_BORDER)
    panel:EnableMouse(true)
    panel:Hide()
    window.profilePanel = panel
    T:Heading(panel, "Profiles"):SetPoint("TOPLEFT", 10, -10)

    -- The profiles scroll in a list of up to LIST_ROWS, so however many there
    -- are, the name box and buttons under it stay in reach. Pinned by two
    -- corners, again a moment after the menu opens (see the bar page).
    local list = T:Scroll(panel, LIST_WIDTH)
    local tall = 1 -- rows the list is tall enough for
    local function Pin()
        list:ClearAllPoints()
        list:SetPoint("TOPLEFT", panel, "TOPLEFT", 10, -28)
        list:SetPoint("BOTTOMRIGHT", panel, "TOPLEFT", 10 + LIST_WIDTH, -(28 + tall * ROW))
        list:ScrollTo(list:GetVerticalScroll() or 0)
    end
    Pin()
    panel:HookScript("OnShow", function() C_Timer.After(0, Pin) end)
    window:Hint(list.thumb, ns.SCROLL_NOTE)
    window.profileList = list

    -- Deleting asks first, in the window's own dialog, saying what happens to
    -- any other character using it: at its next login it gets a profile as a
    -- new character would, even one since deleted that only left its name.
    local function Ask(name)
        local ok, why, others = ns.CanDeleteProfile(name)
        if not ok then
            window:Say(why)
            return window:Refresh()
        end
        local mine = name == ns.ProfileName()
        local detail = mine and "You're using it, so you'll move to a new, empty profile of your own. " or ""
        if others > 0 then
            local everyone = ns.EveryoneProfile()
            local fate = everyone and everyone ~= name and ("loads " .. everyone)
                or "gets a new, empty profile of its own"
            detail = detail .. (others == 1 and "Another character uses it, and " or (others .. " other characters use it, and each "))
                .. fate .. " at its next login. "
        end
        window:Ask(('Delete "%s"?'):format(name), detail .. "This can't be undone.", "Delete", function()
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
        local row = CreateFrame("Button", nil, list.content)
        row:SetSize(LIST_WIDTH, ROW - 2)
        row:SetPoint("TOPLEFT", 0, -(i - 1) * ROW)
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
        window:Hint(row, function()
            return row.profile == ns.ProfileName() and "The profile you're on." or ("Switch to " .. row.profile .. ".")
        end)
        window:Hint(row.remove, function() return "Delete " .. row.profile .. ". It asks first." end)
        rows[i] = row
        return row
    end

    -- Placed now as for one profile, then moved under the list on refresh, so
    -- nothing is ever laid out without a place.
    local input = T:Input(panel, "Profile name", WIDTH - 20)
    input:SetPoint("TOPLEFT", 10, -54)
    window:Hint(input, "A name for New, Copy or Rename.")
    window.profileInput = input
    local hint = T:Text(panel, "GameFontHighlightSmall", T.MUTED)
    hint:SetPoint("TOPLEFT", 10, -136)
    hint:SetWidth(WIDTH - 20)
    hint:SetText("Click a profile to use it, or x to delete it. Type a name to make, copy or rename one. "
        .. "Any class can use a profile: each character only shows its own spells.")

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
            "Every character, and any you make later, loads it. Each only shows its own class's spells and racials. Their own profiles stay in this list.",
            "Use on all", function()
                local _, message = ns.UseOnAll()
                window:Say(message)
                panel:Hide()
                window:Refresh()
            end)
    end)
    window:Hint(everyone, function()
        return ns.OnAll(ns.ProfileName()) and "All your characters use this profile, and new ones will too."
            or "Loads the profile you're on for every character. Each one only shows its own class's spells and racials."
    end)
    window.profileEveryone = everyone

    -- Positions per profile: its own row under Use on all characters.
    local places = T:Check(panel, "Positions per profile", function(self)
        window:Say(ns.SetPlacePerProfile(self:GetChecked()))
        self:SetChecked(ns.PlacePerProfile())
        window:Refresh()
    end)
    places:SetPoint("TOPLEFT", 10, -132)
    window:Hint(places, "Each profile keeps its own bar spots and sizes, and the Layout page arrangement, so switching"
        .. " profile moves your bars. Off, they're every character's." .. UNTESTED)
    window.profilePlaces = places

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
    for _, spec in ipairs({ { "New", ns.NewProfile, "Make a new, empty profile with the name typed above, and switch to it." },
        { "Copy", ns.CopyProfile, "Copy your lists into a new profile with the name typed above, and switch to it." },
        { "Rename", ns.RenameProfile, "Give the profile you're on the name typed above, for every character using it." } }) do
        local action = T:Button(panel, spec[1], 90, 22)
        action:SetPoint("TOPLEFT", x, -80)
        action.x = x
        action:SetScript("OnClick", Act(spec[2]))
        window:Hint(action, spec[3])
        buttons[spec[1]:lower()] = action
        x = x + 94
    end
    window.profileActions = buttons

    button:SetScript("OnClick", function()
        panel:SetShown(not panel:IsShown())
        window:Refresh()
    end)
    window:HookScript("OnHide", function() panel:Hide() end)

    -- Share and Import, at the top right, level with the heading: the
    -- profile you're on as text, or one pasted in as a new profile
    -- (ProfileShare.lua: a new file, so only after a full restart).
    local share = ns.ProfileShare
    if share then
        local box = share.BuildBox(window)
        local import = T:Button(panel, "Import", 56, 18)
        import:SetPoint("TOPRIGHT", -10, -6)
        import:SetScript("OnClick", function() box:Open("import") end)
        window:Hint(import, "Paste a shared profile to make it a new profile. Yours stays as it is.")
        local send = T:Button(panel, "Share", 56, 18)
        send:SetPoint("RIGHT", import, "LEFT", -4, 0)
        send:SetScript("OnClick", function()
            local text, why = share.Export()
            if not text then
                window:Say(why)
                return window:Refresh()
            end
            box:Open("export", text)
        end)
        window:Hint(send, "Your profile, with your bars' look and layout, as text to copy and share.")
        window.profileShare, window.profileImport = send, import
    end

    -- Roles: a profile for each role you play, for your class (Core.lua).
    -- Click one to switch to it; the first time it saves your lists as it
    -- ("Druid Healer"). Right-click saves your lists over it, asking first,
    -- and you stay where you are. The one you're on is edged in the accent;
    -- one not made yet is greyed.
    -- Placed now as for one profile, then moved on refresh (as the box above).
    local roleHeading = T:Heading(panel, "Roles")
    roleHeading:SetPoint("TOPLEFT", 10, -194)
    -- In plain sight beside the heading until the roles and talents are seen
    -- working in game (the user's call, 2026-10-08), not only on hover.
    local roleTesting = T:Text(panel, "GameFontHighlightSmall", T.MUTED)
    roleTesting:SetText("Needs testing")
    roleTesting:SetPoint("LEFT", roleHeading, "RIGHT", 8, 0)
    local function UseRole(role)
        local ok, message = ns.UseRole(role)
        window:Say(message)
        if ok then panel:Hide() end
        window:Refresh()
    end
    local function SaveRole(role)
        local name = ns.RoleProfile(role)
        local function Save()
            local _, message = ns.SaveRole(role)
            window:Say(message)
            window:Refresh()
        end
        if ns.RoleBlocked(role) or not name or name == ns.ProfileName() then return Save() end
        local others = ns.ProfileUsers(name)
        window:Ask(('Save your lists over "%s"?'):format(name),
            ("Your %s profile gets the spell lists and pulse ticks of the profile you're on, in place of its own. "):format(ns.ROLE_NAMES[role])
                .. (others == 1 and "Another character uses it, and gets them too. " or others > 1
                    and (others .. " other characters use it, and get them too. ") or "") .. "This can't be undone.",
            "Save", Save)
    end
    local function RoleNote(role)
        local word, name = ns.ROLE_NAMES[role], ns.RoleProfile(role)
        if name and name == ns.ProfileName() then
            return ("You're on %s, your %s profile."):format(name, word) .. UNTESTED
        elseif name then
            return ("Switch to %s, your %s profile. Right-click to save your lists over it."):format(name, word) .. UNTESTED
        end
        -- Named as it will be made ("Druid Tank"), while your class is known.
        local made = ns.RoleName(role)
        return (made and ("Save your lists as %s and switch to it."):format(made)
            or ("Save your lists as your %s profile and switch to it."):format(word))
            .. " Right-click to save them without switching." .. UNTESTED
    end
    local roleButtons = {}
    for i, role in ipairs(ns.ROLE_KEYS) do
        local roleButton = T:Button(panel, ns.ROLE_NAMES[role], 90, 22)
        roleButton.role, roleButton.x = role, 10 + (i - 1) * 94
        roleButton:SetPoint("TOPLEFT", roleButton.x, -210)
        roleButton:RegisterForClicks("LeftButtonUp", "RightButtonUp")
        roleButton:SetScript("OnClick", function(_, mouse)
            if mouse == "RightButton" then SaveRole(role) else UseRole(role) end
        end)
        window:Hint(roleButton, function() return RoleNote(role) end)
        roleButtons[role] = roleButton
    end
    window.roleHeading, window.roleButtons, window.roleTesting = roleHeading, roleButtons, roleTesting

    -- Switch with my talents, on its own row under the role buttons (the
    -- heading's row holds the Needs testing tag), and while it's ticked each
    -- talent tree under it with its points and its role, or None (it never
    -- switches); under them what the talents last did.
    local talents = T:Check(panel, "Switch with my talents", function(self)
        window:Say(ns.SetTalentSwitch(self:GetChecked()))
        window:Refresh()
    end)
    talents:SetPoint("TOPLEFT", 10, -236)
    window:Hint(talents, "When another talent tree takes the lead in points, switch to its role's profile, after any fight."
        .. UNTESTED)
    local roleItems = {}
    for _, role in ipairs(ns.TREE_ROLE_KEYS) do
        roleItems[#roleItems + 1] = { key = role, label = ns.TREE_ROLE_NAMES[role], width = TREE_WIDTHS[role] }
    end
    local treeRows = {}
    local function TreeRow(i)
        if treeRows[i] then return treeRows[i] end
        local row = {}
        row.name = T:Text(panel, "GameFontHighlightSmall")
        row.choice = T:Segmented(panel, roleItems, TREE_CHOICE, function(role)
            if row.tree then ns.SetTreeRole(row.tree.id, role, row.tree.name) end
            window:Refresh()
        end)
        for _, choice in ipairs(row.choice.buttons) do
            window:Hint(choice, function()
                local tree = row.tree and row.tree.name or "this tree"
                if choice.key == "none" then
                    return ("When %s takes the lead in points, don't switch: click a role yourself."):format(tree) .. UNTESTED
                end
                return ("When %s takes the lead in points, switch to your %s profile."):format(tree, ns.ROLE_NAMES[choice.key]) .. UNTESTED
            end)
        end
        treeRows[i] = row
        return row
    end
    local talentStatus = T:Text(panel, "GameFontHighlightSmall", T.MUTED)
    talentStatus:SetPoint("TOPLEFT", 10, -238)
    talentStatus:SetWidth(WIDTH - 20)
    talentStatus:Hide()
    window.talentTick, window.treeRows, window.talentStatus = talents, treeRows, talentStatus

    -- The talent trees as they are now (read once a refresh), none while
    -- unticked; the note under them, what the talents last did or why there
    -- are no trees to show; and how tall the roles and talents stand.
    local function RolesNow()
        local on = ns.Get("talentSwitch")
        local trees = on and ns.TalentTrees() or {}
        local status = on and (ns.talentNote or (#trees == 0 and "Your talent trees can't be read yet.")) or nil
        talentStatus:SetText(status or "")
        talentStatus:SetShown(status ~= nil) -- shown before it's measured
        local tall = (#trees > 0 and 40 + #trees * 24 or 38) + TICK_ROW
        if status then tall = tall + 6 + math.ceil(talentStatus:GetStringHeight() or 12) end
        return trees, status, tall
    end

    -- Roles and talents under the hint, from y down; the bottom they reach.
    local function PlaceRoles(y, trees, status)
        local current, accent = ns.ProfileName(), T:Accent()
        roleHeading:ClearAllPoints()
        roleHeading:SetPoint("TOPLEFT", 10, -y)
        for _, role in ipairs(ns.ROLE_KEYS) do
            local roleButton, name = roleButtons[role], ns.RoleProfile(role)
            roleButton:ClearAllPoints()
            roleButton:SetPoint("TOPLEFT", roleButton.x, -(y + 16))
            local lit = name ~= nil and name == current
            local edge = lit and accent or T.CONTROL_BORDER
            roleButton:SetBackdropBorderColor(edge[1], edge[2], edge[3], 1)
            local text = lit and accent or name and T.TEXT or T.MUTED
            roleButton.label:SetTextColor(text[1], text[2], text[3])
            roleButton.lit = lit
        end
        talents:ClearAllPoints()
        talents:SetPoint("TOPLEFT", 10, -(y + 42))
        talents:SetChecked(ns.Get("talentSwitch"))
        local bottom = y + 38 + TICK_ROW
        for i, tree in ipairs(trees) do
            local row = TreeRow(i)
            row.tree = tree
            local top = y + 44 + TICK_ROW + (i - 1) * 24
            row.name:ClearAllPoints()
            row.name:SetPoint("TOPLEFT", 18, -(top + 4))
            row.name:SetText(("%s |cff%s%d|r"):format(tree.name, T:Hex(T.MUTED), tree.points))
            row.choice:ClearAllPoints()
            row.choice:SetPoint("TOPRIGHT", -10, -top)
            row.choice:SetSelected(ns.TreeRole(tree))
            row.name:Show()
            row.choice:Show()
            bottom = top + 20
        end
        for i = #trees + 1, #treeRows do
            treeRows[i].tree = nil
            treeRows[i].name:Hide()
            treeRows[i].choice:Hide()
        end
        if not status then return bottom end
        talentStatus:ClearAllPoints()
        talentStatus:SetPoint("TOPLEFT", 10, -(bottom + 6))
        return bottom + 6 + math.ceil(talentStatus:GetStringHeight() or 12)
    end

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
        -- The list is as tall as its profiles, up to LIST_ROWS, and fewer
        -- while the talent trees and their note take room, so the menu
        -- never reaches the window's footer (MENU_MAX); the box, buttons,
        -- hint, roles and talents follow it.
        local trees, status, rolesTall = RolesNow()
        local hintTall = math.max(28, math.ceil(hint:GetStringHeight() or 28))
        local room = math.floor((MENU_MAX - 10 - 32 - 92 - PLACES_ROW - hintTall - rolesTall) / ROW)
        tall = math.max(1, math.min(#names, LIST_ROWS, room))
        list.content:SetHeight(math.max(1, #names * ROW))
        Pin()
        local y = 32 + tall * ROW
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
        places:ClearAllPoints()
        places:SetPoint("TOPLEFT", 10, -(y + 77))
        places:SetChecked(ns.PlacePerProfile())
        hint:ClearAllPoints()
        hint:SetPoint("TOPLEFT", 10, -(y + 82 + PLACES_ROW))
        panel:SetHeight(PlaceRoles(y + 92 + PLACES_ROW + hintTall, trees, status) + 10)
    end
end
