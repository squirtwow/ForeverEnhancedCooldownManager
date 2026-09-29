-- The /ccm window: your bars listed down the left, each with a preview of
-- its icons, then the Look and General pages; the chosen page fills the rest.
-- A bar's page (BarPage.lua) shows its icons, its options and a spell list to
-- tick from. Drawn in the flat charcoal Theme style.
local _, ns = ...
local T = ns.Theme

local WIDTH, HEIGHT = 820, 560
local HEADER, FOOTER, NAV = 42, 28, 180
local PREVIEW = 9 -- icons previewed under each bar's name
local HINT = "Each spell shows once, at your highest rank."

local function Version()
    local version = ns.Version()
    return version == "dev" and version or "v" .. version
end

-- Pages ----------------------------------------------------------------------------

local function Detail(page, text, x, y, width)
    local detail = T:Text(page, "GameFontHighlightSmall", T.MUTED)
    detail:SetPoint("TOPLEFT", x, y)
    detail:SetWidth(width or 420)
    detail:SetText(text)
    return detail
end

-- Look: Blizzard's Cooldown Manager restyled, laid out like a bar's page: a
-- title row, a panel with a live preview bar, the choices under it, your
-- Tracked Bars to colour one by one, and the window's accent at the foot.
local SWATCH, SWATCH_GAP = 20, 6 -- colour swatches
local ROW, ROW_SWATCH = 24, 16 -- the list of Tracked Bars
-- The preview's icons, for the border and shadow.
local SAMPLE_ICONS = { "Spell_Nature_Lightning", "Ability_Rogue_Sprint", "Spell_Holy_FlashHeal", "Spell_Fire_Fireball" }
local ICON, ICON_GAP = 26, 4

local function Swatch(parent, size, onClick)
    local swatch = CreateFrame("Button", nil, parent, "BackdropTemplate")
    swatch:SetSize(size, size)
    swatch:SetScript("OnClick", onClick)
    return swatch
end

-- Your class icon on the Class swatch, so it isn't taken for a second orange
-- (or whichever colour your class shares).
local function ClassIcon(swatch)
    local _, class = UnitClass("player")
    if not class then return end
    local icon = swatch:CreateTexture(nil, "ARTWORK")
    icon:SetPoint("TOPLEFT", 2, -2)
    icon:SetPoint("BOTTOMRIGHT", -2, 2)
    local atlas, coords = "classicon-" .. class:lower(), CLASS_ICON_TCOORDS and CLASS_ICON_TCOORDS[class]
    if C_Texture and C_Texture.GetAtlasInfo and C_Texture.GetAtlasInfo(atlas) then
        icon:SetAtlas(atlas)
    elseif coords then
        icon:SetTexture("Interface\\GLUES\\CHARACTERCREATE\\UI-CHARACTERCREATE-CLASSES")
        icon:SetTexCoord(coords[1], coords[2], coords[3], coords[4])
    else
        icon:Hide()
        return
    end
    swatch.icon = icon
end

-- A swatch in its colour, outlined in white when it's the one chosen.
local function PaintSwatch(swatch, colour, chosen)
    local border = chosen and { 1, 1, 1, 1 } or T.CONTROL_BORDER
    T:Flat(swatch, { colour[1], colour[2], colour[3], 1 }, border)
end
-- Shared with the Cast bar page.
ns.Swatch, ns.ClassIcon, ns.PaintSwatch = Swatch, ClassIcon, PaintSwatch

local function BuildLook(window, page, width)
    local inner = width - 32
    local function Redraw()
        if ns.Skin then ns.Skin:ApplyBarLook() end
        if ns.Resource then ns.Resource:Apply() end
        window:Refresh()
    end
    -- Borders and shadows reach Blizzard's icons, your bars and your cast bar.
    local function Redecorate()
        if ns.Skin then ns.Skin:ApplyDecor() end
        if ns.Bars then ns.Bars:ApplyDecor() end
        if ns.CastBar then ns.CastBar:Apply() end
        window:Refresh()
    end
    local function Note(text) window.note:SetText(text) end
    local function Unnote() window.note:SetText(window.lastNote or "") end

    -- Title row; a reload is offered at the right once one is needed.
    local title = T:Heading(page, "Look")
    title:SetPoint("TOPLEFT", 16, -16)
    local about = T:Text(page, "GameFontHighlightSmall", T.MUTED)
    about:SetPoint("LEFT", title, "RIGHT", 10, 0)
    about:SetText("Blizzard's Cooldown Manager, restyled")
    local off = T:Text(page, "GameFontHighlightSmall", T.WARN)
    off:SetPoint("LEFT", title, "RIGHT", 10, 0)
    off:SetText("Blizzard's Cooldown Manager is off.")
    window.off = off
    local function TurnOnManager()
        local on, why = ns.TurnOn("cooldownViewerEnabled")
        window:Say(on and "Blizzard's Cooldown Manager is on." or why
            or "It couldn't be switched on here: Options > Gameplay > Advanced Options.")
        window:Refresh()
    end
    local managerOn = T:Button(page, "Turn on", 70, 18)
    managerOn:SetPoint("LEFT", off, "RIGHT", 8, 0)
    managerOn:SetScript("OnClick", TurnOnManager)
    window.turnOnManager = managerOn
    -- Straight from the click, while the window is still shown.
    local function Reload()
        if InCombatLockdown() then
            window:Say("Finish combat first, then reload.")
            window:Refresh()
            return
        end
        ReloadUI()
    end
    local reload = T:Button(page, "Reload to apply", 120, 20)
    reload:SetPoint("TOPRIGHT", -16, -12)
    reload:SetScript("OnClick", Reload)
    window.reload = reload

    -- The preview: a bar like Blizzard's, in the design and colour chosen.
    local tray = CreateFrame("Frame", nil, page, "BackdropTemplate")
    tray:SetPoint("TOPLEFT", 16, -38)
    tray:SetSize(inner, 48)
    T:Flat(tray, T.PANEL, T.BORDER)
    if ns.Skin and ns.Skin.Sample then
        window.preview = ns.Skin:Sample(tray, 300)
        window.preview:SetPoint("LEFT", tray, "LEFT", 12, 0)
    end
    -- And a few icons, for the border and shadow.
    local sample = CreateFrame("Frame", nil, tray)
    sample:SetSize(#SAMPLE_ICONS * (ICON + ICON_GAP) - ICON_GAP, ICON)
    sample:SetPoint("RIGHT", -18, 0)
    sample.decor = ns.Style:Decor(sample, sample)
    sample.icons = {}
    for i, art in ipairs(SAMPLE_ICONS) do
        local icon = CreateFrame("Frame", nil, sample)
        icon:SetSize(ICON, ICON)
        icon:SetPoint("LEFT", (i - 1) * (ICON + ICON_GAP), 0)
        local texture = icon:CreateTexture(nil, "ARTWORK")
        texture:SetAllPoints()
        texture:SetTexture("Interface\\Icons\\" .. art)
        ns.Style:Zoom(texture)
        icon.decor = ns.Style:Decor(icon, icon)
        sample.icons[i] = icon
    end
    window.sampleIcons = sample

    -- The choices: the design and colour, then what the look applies to.
    local options = CreateFrame("Frame", nil, page)
    options:SetPoint("TOPLEFT", tray, "BOTTOMLEFT", 0, -12)
    options:SetSize(inner, 198)
    window.lookOptions = options
    local function Label(text, y)
        local label = T:Text(options, "GameFontHighlight")
        label:SetPoint("TOPLEFT", 0, y)
        label:SetText(text)
    end
    Label("Design", -4)
    local designs = {}
    for _, key in ipairs(ns.BAR_STYLE_KEYS) do designs[#designs + 1] = { key = key, label = ns.BAR_STYLE_NAMES[key] } end
    local design = T:Segmented(options, designs, 210, function(key)
        ns.Set("barStyle", key)
        Redraw()
    end)
    design:SetPoint("TOPLEFT", 100, 0)
    window.barDesign = design
    Label("Colour", -32)
    local barSwatches = {}
    for i, key in ipairs(ns.BAR_COLOUR_KEYS) do
        local swatch = Swatch(options, SWATCH, function()
            ns.Set("barColour", key)
            Redraw()
        end)
        swatch:SetPoint("TOPLEFT", 100 + (i - 1) * (SWATCH + SWATCH_GAP), -28)
        swatch.key = key
        if key == "class" then
            ClassIcon(swatch)
            swatch:SetScript("OnEnter", function() Note("Your class colour.") end)
            swatch:SetScript("OnLeave", Unnote)
        end
        barSwatches[i] = swatch
    end
    window.barSwatches = barSwatches
    local barChosen = T:Text(options, "GameFontHighlightSmall", T.MUTED)
    barChosen:SetPoint("TOPLEFT", 100 + #ns.BAR_COLOUR_KEYS * (SWATCH + SWATCH_GAP) + 2, -32)

    -- A border and a shadow, each round every icon or round whole bars.
    local decorItems = {}
    for _, key in ipairs(ns.DECOR_KEYS) do decorItems[#decorItems + 1] = { key = key, label = ns.DECOR_NAMES[key] } end
    local function Decor(label, setting, y, note)
        Label(label, y - 4)
        local pills = T:Segmented(options, decorItems, 210, function(key)
            ns.Set(setting, key)
            Redecorate()
        end)
        pills:SetPoint("TOPLEFT", 100, y)
        for _, button in ipairs(pills.buttons) do
            button:HookScript("OnEnter", function() Note(note) end)
            button:HookScript("OnLeave", Unnote)
        end
        return pills
    end
    local border = Decor("Border", "iconBorder", -60,
        "A thin black border round each icon, or round each whole bar: your bars and Blizzard's Cooldown Manager.")
    local shadow = Decor("Shadow", "iconShadow", -88,
        "A soft shadow round each icon, or round each whole bar. Your cast bar gets one too.")
    window.iconBorder, window.iconShadow = border, shadow

    -- What the look applies to; the footer explains each.
    local function Choice(label, key, y, note, after)
        local check = T:Check(options, label, function(self)
            ns.Set(key, self:GetChecked())
            if after then after() end
            window:Refresh()
        end)
        check:SetPoint("TOPLEFT", 0, y)
        check:HookScript("OnEnter", function() Note(note) end)
        check:HookScript("OnLeave", Unnote)
        return check
    end
    local look = Choice("Apply this look to the Cooldown Manager", "skin", -116,
        "Square icons, bold numbers and these bars. Needs a reload. Countdown numbers: Edit Mode, click a bar, untick its timer.")
    local personal = Choice("Apply this look to the Personal Resource Display", "prdSkin", -138,
        "Blizzard's health and power bars under you (Options > Combat). Needs a reload.")
    local repeatMana = Choice("Extra mana bar: hide in caster form, half size in forms", "prdHideRepeat", -160,
        "The second mana bar some specs get, under your main bar.",
        function() if ns.Resource then ns.Resource:Apply() end end)
    local combo = Choice("Combo points under your energy bar", "prdCombo", -182,
        "Forever's display has none, so the addon draws them: five segments as wide as the display, for rogues and druids in cat form.",
        function() if ns.Resource then ns.Resource:Apply() end end)
    window.look, window.personal, window.repeatMana, window.combo = look, personal, repeatMana, combo

    -- Each Tracked Bar in a colour of its own.
    local eachTitle = T:Heading(page, "Each bar")
    eachTitle:SetPoint("TOPLEFT", options, "BOTTOMLEFT", 0, -12)
    local eachAbout = T:Text(page, "GameFontHighlightSmall", T.MUTED)
    eachAbout:SetPoint("LEFT", eachTitle, "RIGHT", 10, 0)
    eachAbout:SetText("a colour of its own for any of your bars")
    local personalOn = T:Button(page, "Turn on", 70, 18)
    personalOn:SetPoint("TOPRIGHT", options, "BOTTOMRIGHT", 0, -8)
    personalOn:SetScript("OnClick", function()
        local on, why = ns.TurnOn("nameplateShowSelf")
        window:Say(on and "Your Personal Resource Display is on." or why
            or "It couldn't be switched on here: Options > Combat > Personal Resource Display.")
        window:Refresh()
    end)
    local personalOff = T:Text(page, "GameFontHighlightSmall", T.WARN)
    personalOff:SetPoint("RIGHT", personalOn, "LEFT", -8, 0)
    personalOff:SetJustifyH("RIGHT")
    personalOff:SetText("Your Personal Resource Display is off.")
    window.turnOnPersonal, window.personalOff = personalOn, personalOff
    local listPanel = CreateFrame("Frame", nil, page, "BackdropTemplate")
    listPanel:SetPoint("TOPLEFT", eachTitle, "BOTTOMLEFT", 0, -8)
    listPanel:SetPoint("BOTTOMRIGHT", -16, 44)
    T:Box(listPanel)
    window.eachPanel = listPanel
    local empty = T:Text(listPanel, "GameFontHighlightSmall", T.MUTED)
    empty:SetPoint("TOPLEFT", 12, -12)
    empty:SetWidth(inner - 24)
    window.eachEmpty = empty
    -- Under the reason the list is empty, a button to sort it out.
    local fix = T:Button(listPanel, "Turn on", 90, 20)
    fix:SetPoint("TOPLEFT", empty, "BOTTOMLEFT", 0, -8)
    fix:SetScript("OnClick", function(self) if self.action then self.action() end end)
    window.eachFix = fix
    local listWidth = inner - 30
    -- Pinned by two corners, again once the page shows (see the bar page).
    local scroll = T:Scroll(listPanel, listWidth)
    local function Pin()
        scroll:ClearAllPoints()
        scroll:SetPoint("TOPLEFT", listPanel, "TOPLEFT", 8, -6)
        scroll:SetPoint("BOTTOMRIGHT", listPanel, "BOTTOMRIGHT", -16, 6)
        scroll:ScrollTo(scroll:GetVerticalScroll() or 0)
    end
    Pin()
    page:HookScript("OnShow", function() C_Timer.After(0, Pin) end)
    local rows = {}
    window.eachRows = rows
    local SWATCHES_AT = 260
    local function Row(i)
        if rows[i] then return rows[i] end
        local row = CreateFrame("Frame", nil, scroll.content)
        row:SetSize(listWidth, ROW)
        row:SetPoint("TOPLEFT", 0, -(i - 1) * ROW)
        row.icon = row:CreateTexture(nil, "ARTWORK")
        row.icon:SetSize(18, 18)
        row.icon:SetPoint("LEFT", 4, 0)
        ns.Style:Zoom(row.icon)
        row.name = T:Text(row, "GameFontHighlight")
        row.name:SetPoint("LEFT", row.icon, "RIGHT", 8, 0)
        row.name:SetWidth(SWATCHES_AT - 40)
        row.swatches = {}
        for s, key in ipairs(ns.BAR_COLOUR_KEYS) do
            -- Picking the bar's own colour again goes back: to the colour for
            -- all Tracked Bars, or Blizzard's own for the personal bars.
            local swatch = Swatch(row, ROW_SWATCH, function()
                local entry = row.entry
                if entry.spell then
                    ns.SetBarColour(entry.spell, ns.BarColours()[entry.spell] ~= key and key or nil)
                else
                    ns.Set(entry.setting, ns.Get(entry.setting) ~= key and key or "default")
                end
                Redraw()
            end)
            swatch:SetPoint("LEFT", SWATCHES_AT + (s - 1) * (ROW_SWATCH + 6), 0)
            swatch.key = key
            if key == "class" then ClassIcon(swatch) end
            swatch:SetScript("OnEnter", function()
                local entry = row.entry
                Note(entry and entry.back and ("A colour for this bar. Click it again for " .. entry.back .. ".")
                    or "A colour for this bar. Click it again to use the colour for all bars.")
            end)
            swatch:SetScript("OnLeave", Unnote)
            row.swatches[s] = swatch
        end
        row.chosen = T:Text(row, "GameFontHighlightSmall", T.MUTED)
        row.chosen:SetPoint("LEFT", SWATCHES_AT + #ns.BAR_COLOUR_KEYS * (ROW_SWATCH + 6) + 4, 0)
        rows[i] = row
        return row
    end

    -- The window's own accent, at the foot.
    local accentLabel = T:Text(page, "GameFontHighlight")
    accentLabel:SetPoint("BOTTOMLEFT", 16, 18)
    accentLabel:SetText("Window accent")
    local swatches = {}
    for i, key in ipairs(ns.ACCENT_KEYS) do
        local swatch = Swatch(page, SWATCH, function()
            ns.Set("accent", key)
            T:Repaint()
            window:Refresh()
        end)
        swatch:SetPoint("BOTTOMLEFT", 126 + (i - 1) * (SWATCH + SWATCH_GAP), 14)
        swatch.key = key
        swatches[i] = swatch
    end
    window.swatches = swatches
    local chosen = T:Text(page, "GameFontHighlightSmall", T.MUTED)
    chosen:SetPoint("BOTTOMLEFT", 126 + #ns.ACCENT_KEYS * (SWATCH + SWATCH_GAP) + 2, 18)

    -- Why the list is empty, if it is, and a button's label and action to
    -- fix it where the addon can.
    local function ApplyLook()
        ns.Set("skin", true)
        window:Say("Reload to apply the look, then colour your bars here.")
        window:Refresh()
    end
    local function EmptyText(spells)
        if not ns.loaded.skin then
            if ns.Get("skin") then return "Reload first, then colour your bars one by one here.", "Reload", Reload end
            return "Apply this look to the Cooldown Manager and reload to colour your bars one by one.", "Turn on", ApplyLook
        end
        if not ns.CooldownManagerOn() then return "Blizzard's Cooldown Manager is off.", "Turn on", TurnOnManager end
        if #spells == 0 then
            return "Blizzard's Tracked Bars (buffs shown as timer bars) will be listed here to colour once you set some up in Blizzard's Cooldown Settings. Not using them? Nothing to do here."
        end
    end

    function page:Refresh()
        local on = ns.CooldownManagerOn()
        off:SetShown(not on)
        managerOn:SetShown(not on)
        about:SetShown(on)
        local personalShown = ns.Get("prdSkin") and not ns.PersonalDisplayOn()
        personalOff:SetShown(personalShown)
        personalOn:SetShown(personalShown)
        reload:SetShown(ns.NeedsReload())
        look:SetChecked(ns.Get("skin"))
        personal:SetChecked(ns.Get("prdSkin"))
        repeatMana:SetChecked(ns.Get("prdHideRepeat"))
        combo:SetChecked(ns.Get("prdCombo"))
        design:SetSelected(ns.Get("barStyle"))
        border:SetSelected(ns.Get("iconBorder"))
        shadow:SetSelected(ns.Get("iconShadow"))
        ns.Style:ShowDecor(sample.decor, ns.Style:DecorFor("bar"))
        local iconBorder, iconShadow = ns.Style:DecorFor("icon")
        for _, icon in ipairs(sample.icons) do ns.Style:ShowDecor(icon.decor, iconBorder, iconShadow) end
        local barColour = ns.Get("barColour")
        for _, swatch in ipairs(barSwatches) do
            PaintSwatch(swatch, ns.Style:BarColour(swatch.key), swatch.key == barColour)
        end
        barChosen:SetText(ns.BAR_COLOUR_NAMES[barColour])
        local accent = ns.Get("accent")
        for _, swatch in ipairs(swatches) do
            PaintSwatch(swatch, T.ACCENTS[swatch.key].colour, swatch.key == accent)
        end
        chosen:SetText(T.ACCENTS[accent].name)

        -- The Personal Resource Display's bars first, then your Tracked Bars.
        local entries = {}
        local display = ns.Resource and ns.Resource:Shown()
        if ns.loaded.prdSkin and display then
            entries[1] = { setting = "prdHealth", name = "Personal health", icon = "Interface\\Icons\\INV_Potion_54", back = "Blizzard's own" }
            entries[2] = { setting = "prdPower", name = "Personal power", icon = "Interface\\Icons\\INV_Potion_76", back = "Blizzard's own" }
        end
        local _, class = UnitClass("player")
        if display and ns.Get("prdCombo") and (class == "ROGUE" or class == "DRUID") then
            entries[#entries + 1] = { setting = "prdComboColour", name = "Combo points",
                icon = "Interface\\Icons\\Ability_Rogue_Eviscerate", back = "red" }
        end
        local personalRows = #entries
        local spells = ns.loaded.skin and on and ns.Skin and ns.Skin:TrackedBars() or {}
        local why, fixLabel, fixAction = EmptyText(spells)
        if not why then
            for _, id in ipairs(spells) do entries[#entries + 1] = { spell = id } end
        end
        empty:ClearAllPoints()
        empty:SetPoint("TOPLEFT", 12, -(12 + personalRows * ROW))
        empty:SetText(why or "")
        empty:SetShown(why ~= nil)
        fix:SetLabel(fixLabel or "")
        fix.action = fixAction
        fix:SetShown(fixAction ~= nil)
        local own = ns.BarColours()
        for i, entry in ipairs(entries) do
            local row = Row(i)
            row.entry = entry
            local chosen
            if entry.spell then
                local name = C_Spell and C_Spell.GetSpellName and C_Spell.GetSpellName(entry.spell)
                row.name:SetText(type(name) == "string" and name or ("Spell " .. entry.spell))
                row.icon:SetTexture(C_Spell and C_Spell.GetSpellTexture and C_Spell.GetSpellTexture(entry.spell) or 134400)
                chosen = own[entry.spell]
            else
                row.name:SetText(entry.name)
                row.icon:SetTexture(entry.icon)
                chosen = ns.Get(entry.setting)
                if chosen == "default" then chosen = nil end
            end
            for _, swatch in ipairs(row.swatches) do
                PaintSwatch(swatch, ns.Style:BarColour(swatch.key), swatch.key == chosen)
            end
            row.chosen:SetText(chosen and ns.BAR_COLOUR_NAMES[chosen] or "Default")
            row:Show()
        end
        for i = #entries + 1, #rows do rows[i]:Hide() end
        scroll.content:SetHeight(math.max(1, #entries * ROW))
        scroll:ScrollTo(scroll:GetVerticalScroll() or 0)
    end
end

-- A link to copy, in the window's own look: an addon can't open a web page
-- or the CurseForge app itself. The link stays as it is, selected.
local COPY = "Press Ctrl+C to copy, then paste it into your browser."
local copyBox
local function CopyLink(title, url, note)
    if not copyBox then
        local box = CreateFrame("Frame", "FECMCopyLink", UIParent, "BackdropTemplate")
        box:SetSize(420, 136)
        box:SetPoint("CENTER", 0, 120)
        box:SetFrameStrata("FULLSCREEN_DIALOG")
        box:SetToplevel(true)
        box:EnableMouse(true)
        T:Flat(box, T.BG, T.CONTROL_BORDER)
        T:Paint(function(accent) box:SetBackdropBorderColor(accent[1], accent[2], accent[3], 1) end)
        box.title = T:Heading(box, "")
        box.title:SetPoint("TOPLEFT", 16, -16)
        box.note = T:Text(box, "GameFontHighlightSmall", T.MUTED)
        box.note:SetPoint("TOPLEFT", 16, -36)
        box.note:SetWidth(388)
        box.input = T:Input(box, "", 388)
        box.input:SetPoint("TOPLEFT", 16, -72)
        box.input:SetScript("OnTextChanged", function(self)
            if self:GetText() ~= box.url then
                self:SetText(box.url or "")
                self:HighlightText()
            end
        end)
        box.input:SetScript("OnEscapePressed", function() box:Hide() end)
        box.input:SetScript("OnEnterPressed", function() box:Hide() end)
        local close = T:Button(box, "Close", 90, 22)
        close:SetPoint("BOTTOMRIGHT", -16, 12)
        close:SetScript("OnClick", function() box:Hide() end)
        box.close = close
        copyBox = box
    end
    copyBox.url = url
    copyBox.title:SetText(title:upper())
    copyBox.note:SetText(note or COPY)
    copyBox:Show()
    copyBox:Raise()
    copyBox.input:SetText(url)
    copyBox.input:HighlightText()
    copyBox.input:SetFocus()
end
local ERAUI_LINKS = {
    { label = "CurseForge", url = "https://www.curseforge.com/wow/addons/eraui",
        note = COPY .. " On CurseForge, Install opens the CurseForge app." },
    { label = "GitHub", url = "https://github.com/squirtwow/EraUI" },
}
ns.DISCORD_URL = "https://discord.gg/FVfcDWJncr"

-- The Discord invite, ready to copy: from the General page, What's new and
-- /ccm discord.
function ns.ShowDiscord()
    CopyLink("Join the Discord", ns.DISCORD_URL, "Found a bug or have an idea? " .. COPY)
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
    Detail(page, "Cooldowns, Utility, Buffs and Debuffs bars of your own, set up on the left. Move and arrange them on the Layout page.", 34, -56)

    T:Heading(page, "Minimap button"):SetPoint("TOPLEFT", 16, -96)
    local minimap = T:Check(page, "Show the minimap button", function(self)
        ns.Set("minimap", self:GetChecked())
        if ns.MinimapButton then ns.MinimapButton:Apply() end
    end)
    minimap:SetPoint("TOPLEFT", 16, -116)
    window.minimap = minimap
    Detail(page, "Click it for these settings, right-click for What's new, and drag it round the minimap.", 34, -136)

    -- Help: the tour of the basics, as a first install offers it, and the
    -- Discord for bugs and ideas.
    T:Heading(page, "Help"):SetPoint("TOPLEFT", 16, -176)
    local tour = T:Button(page, "Take the tour", 110, 22)
    tour:SetPoint("TOPLEFT", 16, -194)
    tour:SetScript("OnClick", function() if ns.Tour then ns.Tour:Start() end end)
    window.tour = tour
    local discord = T:Button(page, "Discord", 80, 22)
    discord:SetPoint("TOPLEFT", 134, -194)
    discord:SetScript("OnClick", ns.ShowDiscord)
    window.discord = discord
    local helpAbout = T:Text(page, "GameFontHighlightSmall", T.MUTED)
    helpAbout:SetPoint("LEFT", discord, "RIGHT", 10, 0)
    helpAbout:SetText("A tour of the basics, or the Discord for bugs and ideas.")

    T:Heading(page, "Saved settings"):SetPoint("TOPLEFT", 16, -236)

    -- More from Squirt: the author's other addons, and a way to open them.
    T:Heading(page, "More from Squirt"):SetPoint("TOPLEFT", 16, -322)
    local more = CreateFrame("Frame", nil, page, "BackdropTemplate")
    more:SetPoint("TOPLEFT", 16, -342)
    more:SetSize(WIDTH - NAV - 34, 74)
    T:Flat(more, T.PANEL, T.BORDER)
    local moreIcon = more:CreateTexture(nil, "ARTWORK")
    moreIcon:SetSize(36, 36)
    moreIcon:SetPoint("TOPLEFT", 12, -12)
    moreIcon:SetTexture(ns.MEDIA .. "EraUIIcon.tga") -- its own copy, so it shows without EraUI too
    local moreName = T:Text(more, "GameFontHighlight")
    moreName:SetPoint("TOPLEFT", 60, -12)
    moreName:SetText("EraUI")
    local moreAbout = T:Text(more, "GameFontHighlightSmall", T.MUTED)
    moreAbout:SetPoint("TOPLEFT", 60, -30)
    moreAbout:SetWidth(330) -- clear of the buttons on the right
    moreAbout:SetText("The Classic look for WoW Forever's whole interface, with quality of life options.")
    local moreState = T:Text(more, "GameFontHighlightSmall", T.MUTED)
    moreState:SetPoint("BOTTOMLEFT", 60, 10)
    local moreOpen = T:Button(more, "Open", 80, 22)
    moreOpen:SetPoint("RIGHT", -12, 0)
    moreOpen:SetScript("OnClick", function()
        local run = SlashCmdList and SlashCmdList.ERAUI
        if run then
            window:Hide()
            run("")
        end
    end)
    local moreLinks = {}
    for i, link in ipairs(ERAUI_LINKS) do
        local button = T:Button(more, link.label, 90, 22)
        button:SetPoint("RIGHT", -12 - (#ERAUI_LINKS - i) * 98, 0)
        button:SetScript("OnClick", function() CopyLink("EraUI on " .. link.label, link.url, link.note) end)
        moreLinks[i] = button
    end
    window.moreOpen, window.moreState, window.moreLinks = moreOpen, moreState, moreLinks
    local kept = T:Text(page, "GameFontHighlightSmall", T.MUTED)
    kept:SetPoint("TOPLEFT", 16, -256)
    kept:SetWidth(440)
    window.kept = kept

    function page:Refresh()
        local installed = C_AddOns and C_AddOns.IsAddOnLoaded and C_AddOns.IsAddOnLoaded("EraUI")
        moreOpen:SetShown(installed and true or false)
        for _, button in ipairs(moreLinks) do button:SetShown(not installed) end
        moreState:SetText(installed and "Installed. Type /era, or click Open."
            or "Get it on CurseForge or GitHub: click one for its link.")
        bars:SetChecked(B:Enabled())
        minimap:SetChecked(ns.Get("minimap"))
        -- New files only load after a full restart: until then, no tour.
        tour:SetShown(ns.Tour ~= nil)
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
    item.glow = T:Fade(item, T.FADE.selected)
    item.glow:SetAllPoints()
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

-- "Are you sure?": a small dialog over the whole window, for anything that
-- can't simply be clicked back. window:Ask(title, detail, button, action).
local function BuildConfirm(window)
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
    dialog.detail = T:Text(dialog, "GameFontHighlightSmall", T.MUTED)
    dialog.detail:SetPoint("TOPLEFT", dialog.title, "BOTTOMLEFT", 0, -8)
    dialog.detail:SetWidth(292)
    local yes = T:Button(dialog, "", 90, 22)
    yes:SetPoint("BOTTOMRIGHT", -14, 14)
    yes.label:SetTextColor(T.WARN[1], T.WARN[2], T.WARN[3])
    local no = T:Button(dialog, "Cancel", 90, 22)
    no:SetPoint("RIGHT", yes, "LEFT", -6, 0)
    window.confirm = { shade = shade, dialog = dialog, yes = yes, no = no }
    local pending
    local function Close()
        pending = nil
        shade:Hide()
    end
    no:SetScript("OnClick", Close)
    yes:SetScript("OnClick", function()
        local action = pending
        Close()
        if action then action() end
    end)
    window:HookScript("OnHide", Close)
    function window:Ask(title, detail, label, action)
        pending = action
        dialog.title:SetText(title)
        dialog.detail:SetText(detail)
        yes:SetLabel(label)
        -- A long profile name wraps, and the dialog grows to fit it all.
        local text = (dialog.title:GetStringHeight() or 14) + 8 + (dialog.detail:GetStringHeight() or 14)
        dialog:SetHeight(math.max(112, math.ceil(14 + text + 16 + 22 + 14)))
        shade:Show()
    end
end

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

    -- Header: the addon's icon, and "Enhanced" in the accent.
    local header = T:TitleBar(window, HEADER)
    -- The accent washes in from the right, over the title bar and the pages.
    window.fades = { header = header.fade, page = T:Fade(window, T.FADE.page) }
    window.fades.page:SetPoint("TOPLEFT", NAV + 1, -(HEADER + 1))
    window.fades.page:SetPoint("BOTTOMRIGHT", -1, FOOTER)
    window.close = header.close
    window.header = header
    BuildConfirm(window)
    ns.BuildProfileMenu(window, header, header.close)

    -- The bar list down the left.
    local nav = CreateFrame("Frame", nil, window, "BackdropTemplate")
    nav:SetPoint("TOPLEFT", 1, -(HEADER + 1))
    nav:SetPoint("BOTTOMLEFT", 1, FOOTER)
    nav:SetWidth(NAV)
    window.navFrame = nav
    T:Flat(nav, T.NAV, T.NAV)
    local edge = nav:CreateTexture(nil, "BORDER")
    edge:SetPoint("TOPRIGHT")
    edge:SetPoint("BOTTOMRIGHT")
    edge:SetWidth(1)
    T:Fill(edge, T.BORDER)
    window.nav = {}
    -- The addon's own bars, headed so they aren't taken for Blizzard's
    -- Essential or Utility Cooldowns.
    local yours = T:Text(nav, "GameFontHighlightSmall", T.MUTED)
    yours:SetPoint("TOPLEFT", 14, -12)
    yours:SetText("YOUR BARS")
    window.yourBars = yours
    local y = 28
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
    window.nav.layout = NavItem(window, nav, "layout", "Layout", y + 32)
    -- New files only load after a full restart: until then there's no Cast bar page.
    local castPage = ns.BuildCastBarPage ~= nil
    if castPage then window.nav.cast = NavItem(window, nav, "cast", "Cast bar", y + 64) end
    window.nav.general = NavItem(window, nav, "general", "General", y + (castPage and 96 or 64))
    -- What's new in this version, at the foot of the list.
    local news = T:Button(nav, "What's new", NAV - 24, 22)
    news:SetPoint("BOTTOMLEFT", 12, 12)
    news:SetScript("OnClick", function() if ns.ShowNotes then ns.ShowNotes() end end)
    window.news = news

    -- Pages fill the rest.
    local function Page()
        local page = CreateFrame("Frame", nil, window)
        page:SetPoint("TOPLEFT", NAV + 1, -(HEADER + 1))
        page:SetPoint("BOTTOMRIGHT", -1, FOOTER)
        page:Hide()
        return page
    end
    window.pages = { look = Page(), layout = Page(), general = Page(), bar = Page() }
    BuildLook(window, window.pages.look, WIDTH - NAV - 2)
    ns.BuildLayoutPage(window, window.pages.layout, WIDTH - NAV - 2, HEIGHT - HEADER - FOOTER - 1)
    if castPage then
        window.pages.cast = Page()
        ns.BuildCastBarPage(window, window.pages.cast, WIDTH - NAV - 2)
    end
    BuildGeneral(window, window.pages.general)
    ns.BuildBarPage(window, window.pages.bar, WIDTH - NAV - 2)

    -- Footer: the version, and messages from the window (or a tip).
    local version = T:Text(window, "GameFontHighlightSmall", T.MUTED)
    version:SetPoint("BOTTOMLEFT", 12, 9)
    version:SetText(Version() .. "   /ccm to open")
    window.versionText = version
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
        if ns.Tour then ns.Tour:Sync() end
    end

    function window:Refresh()
        self:RefreshProfiles()
        -- Settings the game didn't keep are pointed out until the next login.
        version:SetText(ns.restored and "Settings restored from backup at login. See General." or (Version() .. "   /ccm to open"))
        local colour = ns.restored and T.WARN or T.MUTED
        version:SetTextColor(colour[1], colour[2], colour[3])
        local selected = self.selected
        local barPage = ns.BAR_NAMES[selected] ~= nil
        for key, item in pairs(self.nav) do
            local chosen = key == selected
            item.fill:SetShown(chosen)
            item.glow:SetShown(chosen)
            item.mark:SetShown(chosen)
            if item.icons then
                -- Yours only: another class's, in a shared profile, stay hidden,
                -- and one you haven't learned yet shows greyed in its own icon.
                local spells = ns.Bars:Mine(key)
                item.count:SetText(#spells)
                for i, preview in ipairs(item.icons) do
                    if spells[i] then
                        preview:SetTexture(ns.Spells:Icon(spells[i]))
                        preview:SetDesaturated(ns.Spells:Find(spells[i]) == nil)
                    end
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
