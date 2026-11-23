-- The profile menu in the /ccm window's header: the profile this character
-- uses, and a panel under it listing every profile (click one to switch, or
-- its x to delete it after asking) with a box to type a name for New, Copy
-- or Rename, and Share, Import and Find presets at its top (ProfileShare.lua,
-- Window.lua's Presets page). At its foot,
-- Roles: Tank, Healer and Damage, a profile for each, and Switch with my
-- talents with each talent tree's role (or None, or one of your profiles)
-- under it. Profiles hold the spell
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
-- A talent tree's pick, at the right: a box naming what it switches to,
-- whose list holds Tank, Healer, Damage and None, then your profiles, so the
-- tree's name and points keep their room.
local TREE_CHOICE = 156
local PICK_WIDTH = 220 -- the list, wider than its box for profile names
local PICK_ROW, PICK_PAD = 18, 4
local PICK_HEAD = 18 -- "Your profiles", between the roles and the profiles
local PICK_PROFILES = 8 -- profiles the list shows at once; more scroll
local PICK_LIST = PICK_WIDTH - 2 * PICK_PAD - 8 -- the profiles, clear of their scroll thumb
local TICK_ROW = 24 -- the Switch with my talents tick's own row, under the role buttons
local PLACES_ROW = 22 -- the Positions per profile tick's own row, under Use on all characters

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
        .. " profile moves your bars. Off, they're every character's.")
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

    -- Find presets, at the top right, level with the heading: the Presets
    -- page (Window.lua), for a ready-made setup to import, its word in gold
    -- as Presets is in the list.
    local find = T:Button(panel, "Find presets", 84, 18)
    find:SetPoint("TOPRIGHT", -10, -6)
    find.label:SetTextColor(T.GOLD[1], T.GOLD[2], T.GOLD[3])
    find:SetScript("OnClick", function() window:Select("presets") end)
    window:Hint(find, "Ready-made setups to import, on the Presets page.")
    window.profileFind = find

    -- Share and Import, beside it: the profile you're on as text, or one
    -- pasted in as a new profile (ProfileShare.lua: a new file, so only
    -- after a full restart).
    local share = ns.ProfileShare
    if share then
        local box = share.BuildBox(window)
        local import = T:Button(panel, "Import", 56, 18)
        import:SetPoint("RIGHT", find, "LEFT", -4, 0)
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
            return ("You're on %s, your %s profile."):format(name, word)
        elseif name then
            return ("Switch to %s, your %s profile. Right-click to save your lists over it."):format(name, word)
        end
        -- Named as it will be made ("Druid Tank"), while your class is known.
        local made = ns.RoleName(role)
        return (made and ("Save your lists as %s and switch to it."):format(made)
            or ("Save your lists as your %s profile and switch to it."):format(word))
            .. " Right-click to save them without switching."
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
    window.roleHeading, window.roleButtons = roleHeading, roleButtons

    -- Switch with my talents, on its own row under the role buttons, and
    -- while it's ticked each talent tree under it with its points and what
    -- it switches to: a role's profile, None (it never switches) or one of
    -- your profiles (a player's idea: two damage trees, each with its own);
    -- under them what the talents last did.
    local talents = T:Check(panel, "Switch with my talents", function(self)
        window:Say(ns.SetTalentSwitch(self:GetChecked()))
        window:Refresh()
    end)
    talents:SetPoint("TOPLEFT", 10, -236)
    window:Hint(talents, "When another talent tree takes the lead in points, switch to its role's profile, or the one you picked"
        .. " for it, after any fight.")

    -- A row in a tree's list: its word, filled in the accent while chosen.
    local function PickRow(parent, width, onClick)
        local pick = CreateFrame("Button", nil, parent)
        pick:SetSize(width, PICK_ROW)
        pick.fill = pick:CreateTexture(nil, "BACKGROUND")
        pick.fill:SetAllPoints()
        pick.fill:Hide()
        local shine = pick:CreateTexture(nil, "HIGHLIGHT")
        shine:SetAllPoints()
        shine:SetColorTexture(1, 1, 1, .08)
        pick.label = T:Text(pick, "GameFontHighlightSmall")
        pick.label:SetPoint("LEFT", 8, 0)
        pick.label:SetPoint("RIGHT", -8, 0)
        pick.label:SetJustifyH("LEFT")
        pick.label:SetWordWrap(false)
        pick:SetScript("OnClick", onClick)
        return pick
    end
    local function Paint(pick, chosen)
        local accent, on = T:Accent(), T:OnAccent()
        pick.fill:SetShown(chosen)
        T:Fill(pick.fill, accent)
        local c = chosen and on or T.TEXT
        pick.label:SetTextColor(c[1], c[2], c[3])
    end

    -- A tree's pick: a box naming what it switches to, and under it (or over
    -- it, near the window's foot) its list, one at a time with the window's
    -- other pop-ups: the four roles, then your profiles, which scroll past
    -- PICK_PROFILES. A role lets go of the profile; a profile keeps the role
    -- under it, for if that profile is deleted.
    local function TreeChoice(row)
        local box = CreateFrame("Button", nil, panel, "BackdropTemplate")
        box:SetSize(TREE_CHOICE, 20)
        box:SetPoint("TOPRIGHT", -10, -260) -- placed again on refresh
        T:Flat(box, T.FIELD, T.CONTROL_BORDER)
        box.label = T:Text(box, "GameFontHighlightSmall")
        box.label:SetPoint("LEFT", 8, 0)
        box.label:SetPoint("RIGHT", -18, 0)
        box.label:SetJustifyH("LEFT")
        box.label:SetWordWrap(false)
        local arrow = box:CreateTexture(nil, "ARTWORK")
        arrow:SetTexture(ns.MEDIA .. "TourArrow.tga")
        arrow:SetTexCoord(0, 1, 1, 0) -- pointing down
        arrow:SetSize(8, 5)
        arrow:SetPoint("RIGHT", -6, 0)
        arrow:SetVertexColor(T.MUTED[1], T.MUTED[2], T.MUTED[3], 1)
        local hover = box:CreateTexture(nil, "HIGHLIGHT")
        hover:SetAllPoints()
        hover:SetColorTexture(1, 1, 1, .06)
        window:Hint(box, function()
            return ("What %s switches to when it takes the lead in points: a role, or one of your profiles.")
                :format(row.tree and row.tree.name or "this tree")
        end)

        local popup = ns.PagePopup(window, PICK_WIDTH, 2 * PICK_PAD + 4 * PICK_ROW + PICK_HEAD + PICK_ROW)
        -- Placed under the box from the start (each click places it again),
        -- so its list is never laid out under a frame with no spot.
        popup:SetPoint("TOPRIGHT", box, "BOTTOMRIGHT", 0, -4)
        window:Hint(popup, "A role or one of your profiles for this talent tree. Escape or a click elsewhere closes this.")
        box.popup = popup
        local function Picked(act)
            popup:Close()
            if row.tree then act(row.tree) end
            window:Refresh()
        end
        box.buttons = {}
        for i, role in ipairs(ns.TREE_ROLE_KEYS) do
            local pick = PickRow(popup, PICK_WIDTH - 2 * PICK_PAD, function()
                Picked(function(tree) ns.SetTreeRole(tree.id, role, tree.name) end)
            end)
            pick:SetPoint("TOPLEFT", PICK_PAD, -PICK_PAD - (i - 1) * PICK_ROW)
            pick.label:SetText(ns.TREE_ROLE_NAMES[role])
            pick.key = role
            window:Hint(pick, function()
                local tree = row.tree and row.tree.name or "this tree"
                if role == "none" then
                    return ("When %s takes the lead in points, don't switch: click a role yourself."):format(tree)
                end
                return ("When %s takes the lead in points, switch to your %s profile."):format(tree, ns.ROLE_NAMES[role])
            end)
            box.buttons[i] = pick
        end
        local top = PICK_PAD + 4 * PICK_ROW
        local heading = T:Text(popup, "GameFontHighlightSmall", T.MUTED)
        heading:SetPoint("TOPLEFT", PICK_PAD + 8, -(top + 4))
        heading:SetText("Your profiles")
        box.heading = heading
        local list = T:Scroll(popup, PICK_LIST)
        window:Hint(list.thumb, ns.SCROLL_NOTE)
        box.list = list
        local shown = 1 -- profiles the list is tall enough for
        -- Pinned by two corners, again a moment after the list opens (a
        -- scroll area pinned while hidden is never placed; see the bar page).
        local function Pin()
            list:ClearAllPoints()
            list:SetPoint("TOPLEFT", popup, "TOPLEFT", PICK_PAD, -(top + PICK_HEAD))
            list:SetPoint("BOTTOMRIGHT", popup, "TOPLEFT", PICK_PAD + PICK_LIST, -(top + PICK_HEAD + shown * PICK_ROW))
            list:ScrollTo(list:GetVerticalScroll() or 0)
        end
        Pin()
        popup:HookScript("OnShow", function() C_Timer.After(0, Pin) end)
        box.profileRows = {}
        local function ProfileRow(i)
            local pick = box.profileRows[i]
            if pick then return pick end
            pick = PickRow(list.content, PICK_LIST, function(self)
                local name = self.profile
                Picked(function(tree) ns.SetTreeProfile(tree.id, name) end)
            end)
            pick:SetPoint("TOPLEFT", 0, -(i - 1) * PICK_ROW)
            window:Hint(pick, function()
                return ("When %s takes the lead, switch to %s."):format(row.tree and row.tree.name or "this tree",
                    tostring(pick.profile))
            end)
            box.profileRows[i] = pick
            return pick
        end

        -- The list filled in: every profile, and what's chosen lit.
        function box:Fill()
            local names = ns.ProfileNames()
            for i, name in ipairs(names) do
                local pick = ProfileRow(i)
                pick.profile = name
                pick.label:SetText(name)
                Paint(pick, name == self.profile)
                pick:Show()
            end
            for i = #names + 1, #self.profileRows do self.profileRows[i]:Hide() end
            for _, pick in ipairs(self.buttons) do Paint(pick, self.profile == nil and pick.key == self.selected) end
            shown = math.max(1, math.min(#names, PICK_PROFILES))
            list.content:SetHeight(math.max(1, #names * PICK_ROW))
            popup:SetHeight(2 * PICK_PAD + 4 * PICK_ROW + PICK_HEAD + shown * PICK_ROW)
            Pin()
        end
        -- What the tree switches to: a role (or None), or a profile of yours.
        function box:SetSelected(role, profile)
            self.selected = profile and "profile" or role
            self.profile = profile
            self.label:SetText(profile or ns.TREE_ROLE_NAMES[role] or "")
            local c = role == "none" and not profile and T.MUTED or T.TEXT
            self.label:SetTextColor(c[1], c[2], c[3])
            if popup:IsOpen() then self:Fill() end
        end
        box:SetScript("OnClick", function(self)
            if popup:IsOpen() then return popup:Close() end
            self:Fill()
            -- Under the box, or over it where the window's foot is too close.
            popup:ClearAllPoints()
            local bottom, floor = self:GetBottom(), window:GetBottom()
            if type(bottom) == "number" and type(floor) == "number"
                and bottom - popup:GetHeight() - 4 < floor + (ns.WINDOW_FOOTER or 0) then
                popup:SetPoint("BOTTOMRIGHT", self, "TOPRIGHT", 0, 4)
            else
                popup:SetPoint("TOPRIGHT", self, "BOTTOMRIGHT", 0, -4)
            end
            popup:Open(self)
        end)
        box:HookScript("OnHide", function() popup:Close() end)
        T:Paint(function() if popup:IsOpen() then box:Fill() end end)
        return box
    end

    local treeRows = {}
    local function TreeRow(i)
        if treeRows[i] then return treeRows[i] end
        local row = {}
        row.name = T:Text(panel, "GameFontHighlightSmall")
        row.choice = TreeChoice(row)
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
            row.choice:SetSelected(ns.TreeRole(tree), ns.TreeProfile(tree))
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
