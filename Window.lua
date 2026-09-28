-- The /fecm window: your bars listed down the left, each with a preview of
-- its icons, then the Look and General pages; the chosen page fills the rest.
-- A bar's page (BarPage.lua) shows its icons, its options and a spell list to
-- tick from. Drawn in the flat charcoal Theme style.
local ADDON, ns = ...
local T = ns.Theme

local WIDTH, HEIGHT = 820, 560
local HEADER, FOOTER, NAV = 42, 28, 180
local PREVIEW = 9 -- icons previewed under each bar's name
local HINT = "Each spell shows once, at your highest rank."

local function Version()
    local get = C_AddOns and C_AddOns.GetAddOnMetadata or GetAddOnMetadata
    local version = get and get(ADDON, "Version")
    if not version or version:find("@", 1, true) then return "dev" end
    return "v" .. version
end

-- Pages ----------------------------------------------------------------------------

local function Detail(page, text, x, y, width)
    local detail = T:Text(page, "GameFontHighlightSmall", T.MUTED)
    detail:SetPoint("TOPLEFT", x, y)
    detail:SetWidth(width or 420)
    detail:SetText(text)
    return detail
end

local function BuildLook(window, page)
    T:Heading(page, "Blizzard's Cooldown Manager"):SetPoint("TOPLEFT", 16, -16)
    local look = T:Check(page, "Charcoal look", function(self)
        ns.Set("skin", self:GetChecked())
        window:Refresh()
    end)
    look:SetPoint("TOPLEFT", 16, -36)
    window.look = look
    Detail(page, "Square frameless icons, big bold countdown numbers and charcoal bars on Blizzard's own "
        .. "Cooldown Manager. Needs a reload.", 34, -56)

    -- Shown when Blizzard's Cooldown Manager is switched off.
    local off = T:Text(page, "GameFontHighlightSmall", T.WARN)
    off:SetPoint("TOPLEFT", 16, -92)
    off:SetWidth(440)
    off:SetText("Blizzard's Cooldown Manager is off: Options > Gameplay > Advanced Options.")
    window.off = off
    Detail(page, "To hide Blizzard's countdown numbers, open Edit Mode, click one of its bars and untick "
        .. "its timer option.", 16, -112, 440)

    T:Heading(page, "Accent"):SetPoint("TOPLEFT", 16, -156)
    local swatches = {}
    local chosen = T:Text(page, "GameFontHighlightSmall", T.MUTED)
    chosen:SetPoint("TOPLEFT", 16 + #ns.ACCENT_KEYS * 28 + 6, -180)
    for i, key in ipairs(ns.ACCENT_KEYS) do
        local swatch = CreateFrame("Button", nil, page, "BackdropTemplate")
        swatch:SetSize(20, 20)
        swatch:SetPoint("TOPLEFT", 16 + (i - 1) * 28, -176)
        local colour = T.ACCENTS[key].colour
        T:Flat(swatch, { colour[1], colour[2], colour[3], 1 }, T.CONTROL_BORDER)
        swatch.key = key
        swatch:SetScript("OnClick", function()
            ns.Set("accent", key)
            T:Repaint()
            window:Refresh()
        end)
        swatches[i] = swatch
    end
    window.swatches = swatches

    -- The reload a changed charcoal look needs, at the foot of the page.
    local hint = T:Text(page, "GameFontHighlightSmall", T.MUTED)
    hint:SetPoint("BOTTOMLEFT", 16, 44)
    hint:SetWidth(300)
    window.hint = hint
    local reload = T:Button(page, "Reload UI", 140)
    reload:SetPoint("BOTTOMLEFT", 16, 16)
    -- Straight from the click, while the window is still shown.
    reload:SetScript("OnClick", function()
        if InCombatLockdown() then
            hint:SetText("Finish combat first, then reload.")
            return
        end
        ReloadUI()
    end)
    window.reload = reload

    function page:Refresh()
        look:SetChecked(ns.Get("skin"))
        off:SetShown(not ns.CooldownManagerOn())
        local needsReload = ns.NeedsReload()
        reload:SetShown(needsReload)
        hint:SetText(needsReload and "Reload UI to apply your change." or "")
        local current = ns.Get("accent")
        for _, swatch in ipairs(swatches) do
            local border = swatch.key == current and { 1, 1, 1, 1 } or T.CONTROL_BORDER
            swatch:SetBackdropBorderColor(border[1], border[2], border[3], 1)
        end
        chosen:SetText(T.ACCENTS[current].name)
    end
end

local function BuildGeneral(window, page)
    local B = ns.Bars
    T:Heading(page, "Your bars"):SetPoint("TOPLEFT", 16, -16)
    local bars = T:Check(page, "Use my bars", function(self)
        ns.Set("useBars", self:GetChecked())
        B:Rebuild()
        window:Refresh()
    end)
    bars:SetPoint("TOPLEFT", 16, -36)
    window.useBars = bars
    Detail(page, "Cooldowns, Utility and Buffs bars of your own, set up on the left.", 34, -56)

    local unlock = T:Button(page, "Unlock bars to move", 160)
    unlock:SetPoint("TOPLEFT", 16, -84)
    unlock:SetScript("OnClick", function()
        if not B:Enabled() then
            window:Say("Tick Use my bars first.")
        else
            B:SetUnlocked(not B:IsUnlocked())
        end
        window:Refresh()
    end)
    window.unlock = unlock
    local reset = T:Button(page, "Reset positions", 160)
    reset:SetPoint("LEFT", unlock, "RIGHT", 8, 0)
    reset:SetScript("OnClick", function()
        B:ResetPositions()
        window:Say("Bars moved back above your action bar.")
        window:Refresh()
    end)
    Detail(page, "Unlocked bars show a box you can drag. Closing this window locks them again.", 16, -114)

    T:Heading(page, "Saved settings"):SetPoint("TOPLEFT", 16, -150)
    local kept = T:Text(page, "GameFontHighlightSmall", T.MUTED)
    kept:SetPoint("TOPLEFT", 16, -170)
    kept:SetWidth(440)
    window.kept = kept

    function page:Refresh()
        bars:SetChecked(B:Enabled())
        unlock:SetLabel(B:IsUnlocked() and "Lock bars" or "Unlock bars to move")
        if ns.restored then
            kept:SetText(ns.RESTORED_TEXT .. " This happens when the game closes without saving, for example after a crash.")
            kept:SetTextColor(T.WARN[1], T.WARN[2], T.WARN[3])
        else
            kept:SetText("Saved normally. The addon also keeps a backup in the game's own settings, in case the game loses them.")
            kept:SetTextColor(T.MUTED[1], T.MUTED[2], T.MUTED[3])
        end
    end
end

-- The bar list ---------------------------------------------------------------------

local function NavItem(window, nav, key, label, y, previews)
    local item = CreateFrame("Button", nil, nav)
    item:SetPoint("TOPLEFT", 0, -y)
    item:SetPoint("RIGHT")
    item:SetHeight(previews and 46 or 30)
    item.fill = item:CreateTexture(nil, "BACKGROUND")
    item.fill:SetAllPoints()
    T:Fill(item.fill, T.SELECTED)
    item.mark = item:CreateTexture(nil, "ARTWORK")
    item.mark:SetPoint("TOPLEFT")
    item.mark:SetPoint("BOTTOMLEFT")
    item.mark:SetWidth(3)
    T:Paint(function(accent) T:Fill(item.mark, accent) end)
    local hover = item:CreateTexture(nil, "HIGHLIGHT")
    hover:SetAllPoints()
    hover:SetColorTexture(1, 1, 1, .04)
    item.label = T:Text(item, "GameFontHighlight")
    item.label:SetPoint("TOPLEFT", 14, -9)
    item.label:SetText(label)
    item.count = T:Text(item, "GameFontHighlightSmall", T.MUTED)
    item.count:SetPoint("TOPRIGHT", -12, -10)
    item.count:SetJustifyH("RIGHT")
    if previews then
        item.icons = {}
        for i = 1, PREVIEW do
            local icon = item:CreateTexture(nil, "ARTWORK")
            icon:SetSize(14, 14)
            icon:SetPoint("TOPLEFT", 14 + (i - 1) * 16, -26)
            ns.Style:Zoom(icon)
            item.icons[i] = icon
        end
    end
    item.key = key
    item:SetScript("OnClick", function() window:Select(key) end)
    return item
end

-- Setup ------------------------------------------------------------------------------

local function BuildWindow()
    local window = CreateFrame("Frame", "FECMFrame", UIParent, "BackdropTemplate")
    window:SetSize(WIDTH, HEIGHT)
    window:SetPoint("CENTER", 0, 40)
    window:SetFrameStrata("FULLSCREEN_DIALOG")
    window:SetToplevel(true)
    window:SetClampedToScreen(true)
    window:EnableMouse(true)
    window:SetMovable(true)
    window:RegisterForDrag("LeftButton")
    window:SetScript("OnDragStart", window.StartMoving)
    window:SetScript("OnDragStop", window.StopMovingOrSizing)
    T:Flat(window, T.BG, T.CONTROL_BORDER)
    window:Hide()
    -- Set before anything hooks these: setting a script later would drop the
    -- hooks the pages and the profile menu add.
    window:SetScript("OnShow", function(self)
        self:Refresh()
        ns.EscUpdate()
    end)
    window:SetScript("OnHide", function()
        ns.EscUpdate()
        if ns.Bars then ns.Bars:SetUnlocked(false) end
    end)

    -- Header: the icon on an accent square, and "Enhanced" in the accent.
    local header = CreateFrame("Frame", nil, window, "BackdropTemplate")
    header:SetPoint("TOPLEFT", 1, -1)
    header:SetPoint("TOPRIGHT", -1, -1)
    header:SetHeight(HEADER)
    T:Flat(header, T.HEADER, T.HEADER)
    local logo = CreateFrame("Frame", nil, header, "BackdropTemplate")
    logo:SetSize(24, 24)
    logo:SetPoint("LEFT", 12, 0)
    local icon = logo:CreateTexture(nil, "ARTWORK")
    icon:SetPoint("TOPLEFT", 2, -2)
    icon:SetPoint("BOTTOMRIGHT", -2, 2)
    icon:SetTexture("Interface\\Icons\\INV_Misc_PocketWatch_01")
    local title = T:Text(header, "GameFontNormalLarge")
    title:SetPoint("LEFT", logo, "RIGHT", 8, 0)
    T:Paint(function(accent)
        T:Flat(logo, { accent[1], accent[2], accent[3], 1 }, { accent[1], accent[2], accent[3], 1 })
        title:SetText("Forever |cff" .. T:Hex(accent) .. "Enhanced|r Cooldown Manager")
    end)
    local close = T:Square(header, "X")
    close:SetSize(22, 22)
    close:SetPoint("RIGHT", -10, 0)
    close:SetScript("OnClick", function() window:Hide() end)
    window.close = close
    window.header = header
    ns.BuildProfileMenu(window, header, close)

    -- The bar list down the left.
    local nav = CreateFrame("Frame", nil, window, "BackdropTemplate")
    nav:SetPoint("TOPLEFT", 1, -(HEADER + 1))
    nav:SetPoint("BOTTOMLEFT", 1, FOOTER)
    nav:SetWidth(NAV)
    T:Flat(nav, T.NAV, T.NAV)
    local edge = nav:CreateTexture(nil, "BORDER")
    edge:SetPoint("TOPRIGHT")
    edge:SetPoint("BOTTOMRIGHT")
    edge:SetWidth(1)
    T:Fill(edge, T.BORDER)
    window.nav = {}
    local y = 8
    for _, key in ipairs(ns.BAR_KEYS) do
        window.nav[key] = NavItem(window, nav, key, ns.BAR_NAMES[key], y, true)
        y = y + 48
    end
    local rule = nav:CreateTexture(nil, "BORDER")
    rule:SetPoint("TOPLEFT", 12, -(y + 4))
    rule:SetPoint("RIGHT", -12, 0)
    rule:SetHeight(1)
    T:Fill(rule, T.BORDER)
    y = y + 12
    window.nav.look = NavItem(window, nav, "look", "Look", y)
    window.nav.general = NavItem(window, nav, "general", "General", y + 32)

    -- Pages fill the rest.
    local function Page()
        local page = CreateFrame("Frame", nil, window)
        page:SetPoint("TOPLEFT", NAV + 1, -(HEADER + 1))
        page:SetPoint("BOTTOMRIGHT", -1, FOOTER)
        page:Hide()
        return page
    end
    window.pages = { look = Page(), general = Page(), bar = Page() }
    BuildLook(window, window.pages.look)
    BuildGeneral(window, window.pages.general)
    ns.BuildBarPage(window, window.pages.bar, WIDTH - NAV - 2)

    -- Footer: the version, and messages from the window (or a tip).
    local version = T:Text(window, "GameFontHighlightSmall", T.MUTED)
    version:SetPoint("BOTTOMLEFT", 12, 9)
    version:SetText(Version() .. "   /fecm to open")
    local note = T:Text(window, "GameFontHighlightSmall", T.MUTED)
    note:SetPoint("BOTTOMRIGHT", -12, 9)
    note:SetJustifyH("RIGHT")
    note:SetWidth(560)
    window.note = note
    function window:Say(text)
        self.message = text
    end

    window.selected = "cd"
    function window:Select(key)
        self.selected = key
        self.profilePanel:Hide()
        self:Refresh()
    end

    function window:Refresh()
        self:RefreshProfiles()
        -- Settings the game didn't keep are pointed out until the next login.
        version:SetText(ns.restored and "Settings restored from backup at login. See General." or (Version() .. "   /fecm to open"))
        local colour = ns.restored and T.WARN or T.MUTED
        version:SetTextColor(colour[1], colour[2], colour[3])
        local selected = self.selected
        local barPage = ns.BAR_NAMES[selected] ~= nil
        for key, item in pairs(self.nav) do
            local chosen = key == selected
            item.fill:SetShown(chosen)
            item.mark:SetShown(chosen)
            if item.icons then
                local spells = ns.BarData(key).spells
                item.count:SetText(#spells)
                for i, preview in ipairs(item.icons) do
                    local entry = spells[i] and ns.Spells:Find(spells[i])
                    preview:SetTexture(entry and entry.icon or 134400) -- question mark until learned
                    preview:SetShown(spells[i] ~= nil)
                end
            end
        end
        for key, page in pairs(self.pages) do
            page:SetShown(key == (barPage and "bar" or selected))
        end
        if barPage then self.pages.bar:Refresh(selected) else self.pages[selected]:Refresh() end
        self.lastNote = self.message or HINT
        self.note:SetText(self.lastNote)
        self.message = nil
    end

    ns.window = window
    return window
end

function ns.ShowWindow()
    local window = ns.window or BuildWindow()
    window:Show()
    window:Raise()
end

function ns.Toggle()
    local window = ns.window or BuildWindow()
    window:SetShown(not window:IsShown())
end
