-- The /ccm window: your bars listed down the left, each with a preview of
-- its icons, then the Look and General pages; the chosen page fills the rest.
-- A bar's page (BarPage.lua) shows its icons, its options and a spell list to
-- tick from. Drawn in the flat charcoal Theme style.
local _, ns = ...
local T = ns.Theme

local WIDTH, HEIGHT = 820, 560
local HEADER, FOOTER, NAV = 42, 28, 180
local PREVIEW = 9 -- icons previewed under each bar's name
local HEART = "Heart.tga" -- white on clear, tinted to the accent in the footer's credit
-- A list's scroll thumb, wherever there's one: the bar pages, Look and the profiles.
ns.SCROLL_NOTE = "Drag to scroll the list, or turn the mouse wheel over it."

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
-- And keys on them, for the keybinds: made up, so the preview isn't tied to your own.
local SAMPLE_KEYS = { "1", "S2", "M4", "C3" }
local ICON, ICON_GAP = 26, 4
-- The font and bar texture choices: a short bar for each texture, and what
-- each one says on hover, then what they're used for.
local FILL_SWATCH = { 36, 20 }
local FONT_NOTES = {
    friz = "Friz Quadrata, the game's own font",
    arial = "Arial Narrow, plain and narrow",
    morpheus = "Morpheus, the game's storybook lettering",
    skurri = "Skurri, heavy like the game's big numbers",
}
local FONT_USE = ", for countdowns, counts, keys and names on icons, and the text on your cast bar and Tracked Bars."
local TEXTURE_NOTES = {
    flat = "Flat colour",
    classic = "The game's classic unit frame bar",
    raid = "The game's raid frame bar",
    skills = "The game's skill bar, from the character sheet",
}
local TEXTURE_USE = " on your cast bar, swing timer and combo points, and the restyled Tracked Bars and resource display."
local UNTESTED = " (Needs testing)" -- on every choice but today's look
-- Ready glow's choices at the foot, and room for its label before them
-- (about seven units a letter in the game: "Ready glow" needs about 70).
local GLOW_PILLS, GLOW_LABEL = 160, 80

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
        window:Say(on and "Blizzard's Cooldown Manager is on. Reload to finish." or why
            or "It couldn't be switched on here: Options > Gameplay > Advanced Options.")
        window:Refresh()
    end
    local managerOn = T:Button(page, "Turn on", 70, 18)
    managerOn:SetPoint("LEFT", off, "RIGHT", 8, 0)
    managerOn:SetScript("OnClick", TurnOnManager)
    window:Hint(managerOn, "Switch Blizzard's Cooldown Manager on (Options > Gameplay > Advanced Options).")
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
    window:Hint(reload, "Reload your interface so the changes here take effect.")
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
        icon.key = ns.Style:KeyText(icon)
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
    for _, button in ipairs(design.buttons) do
        window:Hint(button, "The design for Blizzard's Tracked Bars, your cast bar and, with its look on, your resource display.")
    end
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
        if key == "class" then ClassIcon(swatch) end
        window:Hint(swatch, (key == "class" and "Your class colour" or ns.BAR_COLOUR_NAMES[key])
            .. " for all your Tracked Bars. Each bar can have its own below.")
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
        for _, button in ipairs(pills.buttons) do window:Hint(button, note) end
        return pills
    end
    local border = Decor("Border", "iconBorder", -60,
        "A thin black border round each icon, or each whole bar whose icons stay put. Yours and Blizzard's.")
    local shadow = Decor("Shadow", "iconShadow", -88,
        "A soft shadow round each icon, or each whole bar whose icons stay put. Your cast bar gets one too.")
    window.iconBorder, window.iconShadow = border, shadow

    -- What the look applies to; the footer explains each.
    local function Choice(label, key, y, note, after, x)
        local check = T:Check(options, label, function(self)
            ns.Set(key, self:GetChecked())
            if after then after() end
            window:Refresh()
        end)
        check:SetPoint("TOPLEFT", x or 0, y)
        window:Hint(check, note)
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

    -- Keybinds on the icons, in the right-hand column clear of the rows on
    -- the left: the tick, then where on each icon (level with Colour) and how
    -- big (level with Border). Changes show at once on the preview, your
    -- bars and Blizzard's icons.
    local KEYS_X = 330
    local function KeyLook()
        if ns.Bars then ns.Bars:ApplyKeybinds() end
        if ns.Skin then ns.Skin:ApplyKeybinds() end
    end
    local function Rekey()
        if ns.Keybinds then ns.Keybinds:Update() end
        KeyLook()
    end
    local keybinds = Choice("Keybinds on icons", "keybinds", -2,
        "The key that casts each spell or uses each item, from your action bars, on your Cooldowns and Utility bars. Blizzard's icons get them while Apply this look to the Cooldown Manager is on.",
        Rekey, KEYS_X)
    local placeItems = {}
    for _, key in ipairs(ns.KEYBIND_POSITIONS) do
        placeItems[#placeItems + 1] = { key = key, label = ns.KEYBIND_POSITION_NAMES[key] }
    end
    local keyPlace = T:Segmented(options, placeItems, 258, function(key)
        ns.Set("keybindPosition", key)
        KeyLook()
        window:Refresh()
    end)
    keyPlace:SetPoint("TOPLEFT", KEYS_X + 18, -28)
    -- Greyed out while the tick is off, and each says why on hover.
    local KEYS_OFF = "Tick Keybinds on icons first."
    for _, button in ipairs(keyPlace.buttons) do
        window:Hint(button, function()
            return ns.Get("keybinds") and "Where the key sits on each icon. At the bottom, the count or charges on an icon with a key move to the top right."
                or KEYS_OFF
        end)
    end
    local keySize = T:Slider(options, "Size", ns.KEYBIND_SIZE, 10, 258, function(value)
        ns.Set("keybindSize", value)
        KeyLook()
        window:Refresh()
    end)
    keySize:SetPoint("TOPLEFT", KEYS_X + 18, -60)
    window:Hint(keySize, function()
        return ns.Get("keybinds") and "The key's size: 100 follows each icon's size. It stays clear of the countdown, which moves over a little on small icons."
            or KEYS_OFF
    end)
    window.keybinds, window.keyPlace, window.keySize = keybinds, keyPlace, keySize

    -- The font for the numbers and text, and the texture for the bars, under
    -- the keybinds, level with Shadow and the first tick: each font's name in
    -- its own face, each texture as a short bar in the colour for all bars.
    -- The preview above shows both; everything changes at once.
    local FACES_X = KEYS_X + 52 -- where the choices start, clear of their labels
    local faces = CreateFrame("Frame", nil, options) -- both rows as one, for the tour to outline
    faces:SetPoint("TOPLEFT", KEYS_X, -88)
    faces:SetSize(inner - KEYS_X, 48)
    window.faces = faces
    local function Refont()
        ns.Style:ApplyFont()
        if ns.Bars then ns.Bars:ApplyFont() end
        window:Refresh()
    end
    local function Retexture()
        if ns.CastBar then ns.CastBar:Apply() end
        Redraw()
    end
    local fontLabel = T:Text(options, "GameFontHighlight")
    fontLabel:SetPoint("TOPLEFT", KEYS_X, -92)
    fontLabel:SetText("Font")
    local fontItems = {}
    for _, key in ipairs(ns.FONT_KEYS) do
        fontItems[#fontItems + 1] = { key = key, label = ns.FONT_NAMES[key]:match("^%S+") }
    end
    local font = T:Segmented(options, fontItems, inner - FACES_X, function(key)
        ns.Set("font", key)
        Refont()
    end)
    font:SetPoint("TOPLEFT", FACES_X, -88)
    for _, button in ipairs(font.buttons) do
        button.label:SetFontObject(ns.Style:SampleFont(button.key))
        window:Hint(button, FONT_NOTES[button.key] .. FONT_USE .. (button.key ~= ns.DEFAULTS.font and UNTESTED or ""))
    end
    local textureLabel = T:Text(options, "GameFontHighlight")
    textureLabel:SetPoint("TOPLEFT", KEYS_X, -120)
    textureLabel:SetText("Texture")
    local fills = {}
    for i, key in ipairs(ns.BAR_TEXTURE_KEYS) do
        local swatch = Swatch(options, SWATCH, function()
            ns.Set("barTexture", key)
            Retexture()
        end)
        swatch:SetSize(FILL_SWATCH[1], FILL_SWATCH[2])
        swatch:SetPoint("TOPLEFT", FACES_X + (i - 1) * (FILL_SWATCH[1] + SWATCH_GAP), -116)
        swatch.key = key
        -- The texture itself, inside the swatch's 1px edge.
        swatch.fill = swatch:CreateTexture(nil, "ARTWORK")
        swatch.fill:SetPoint("TOPLEFT", 1, -1)
        swatch.fill:SetPoint("BOTTOMRIGHT", -1, 1)
        swatch.fill:SetTexture(ns.Style.BAR_TEXTURES[key])
        window:Hint(swatch, TEXTURE_NOTES[key] .. TEXTURE_USE .. (key ~= ns.DEFAULTS.barTexture and UNTESTED or ""))
        fills[i] = swatch
    end
    local fillChosen = T:Text(options, "GameFontHighlightSmall", T.MUTED)
    fillChosen:SetPoint("TOPLEFT", FACES_X + #ns.BAR_TEXTURE_KEYS * (FILL_SWATCH[1] + SWATCH_GAP) + 2, -120)
    window.fontChoice, window.fills, window.fillChosen = font, fills, fillChosen

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
        window:Say(on and "Your Personal Resource Display is on. Reload to finish." or why
            or "It couldn't be switched on here: Options > Combat > Personal Resource Display.")
        window:Refresh()
    end)
    window:Hint(personalOn, "Switch your Personal Resource Display on (Options > Combat).")
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
    window:Hint(fix, function() return fix.about end)
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
    window:Hint(scroll.thumb, ns.SCROLL_NOTE)
    local rows = {}
    window.eachRows = rows
    local SWATCHES_AT = 260
    local function Row(i)
        if rows[i] then return rows[i] end
        local row = CreateFrame("Frame", nil, scroll.content)
        row:SetSize(listWidth, ROW)
        row:SetPoint("TOPLEFT", 0, -(i - 1) * ROW)
        -- The row says what it's for round its swatches, which say their own.
        row:EnableMouse(true)
        window:Hint(row, function()
            return (row.name:GetText() or "This bar") .. ": click a colour on the right for this bar alone."
        end)
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
                    ns.SetBarColour(entry.spell, ns.BarColourFor(entry.spell) ~= key and key or nil)
                else
                    ns.Set(entry.setting, ns.Get(entry.setting) ~= key and key or "default")
                end
                Redraw()
            end)
            swatch:SetPoint("LEFT", SWATCHES_AT + (s - 1) * (ROW_SWATCH + 6), 0)
            swatch.key = key
            if key == "class" then ClassIcon(swatch) end
            window:Hint(swatch, function()
                local entry = row.entry
                return entry and entry.back and ("A colour for this bar. Click it again for " .. entry.back .. ".")
                    or "A colour for this bar. Click it again to use the colour for all bars."
            end)
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
        window:Hint(swatch, T.ACCENTS[key].name .. " for this window's headings, ticks, sliders and highlights.")
        swatches[i] = swatch
    end
    window.swatches = swatches
    local chosen = T:Text(page, "GameFontHighlightSmall", T.MUTED)
    chosen:SetPoint("BOTTOMLEFT", 126 + #ns.ACCENT_KEYS * (SWATCH + SWATCH_GAP) + 2, 18)

    -- How a ready reactive ability (Overpower, Riposte, Mongoose Bite and
    -- the rest of ns.REACTIVE) shows on your own bars, at the foot's right,
    -- clear of the accent: Blizzard's proc glow or a plain gold edge. Every
    -- icon changes at once, one glowing now too.
    local glowItems = {}
    for _, key in ipairs(ns.READY_GLOW_KEYS) do glowItems[#glowItems + 1] = { key = key, label = ns.READY_GLOW_NAMES[key] } end
    local readyGlow = T:Segmented(page, glowItems, GLOW_PILLS, function(key)
        ns.Set("readyGlow", key)
        if ns.Bars then ns.Bars:ApplyGlow() end
        window:Refresh()
    end)
    readyGlow:SetPoint("BOTTOMRIGHT", -16, 14)
    local glowLabel = T:Text(page, "GameFontHighlight")
    glowLabel:SetPoint("BOTTOMRIGHT", -16 - GLOW_PILLS - 10, 18)
    glowLabel:SetJustifyH("RIGHT")
    glowLabel:SetText("Ready glow")
    readyGlow.label = glowLabel
    local GLOW_NOTES = {
        proc = "Blizzard's proc glow, as on your action bars, round a ready ability like Overpower, Riposte or Mongoose Bite on your own bars.",
        edge = "A plain gold edge just inside the icon of a ready ability like Overpower, Riposte or Mongoose Bite on your own bars.",
    }
    for _, button in ipairs(readyGlow.buttons) do window:Hint(button, GLOW_NOTES[button.key]) end
    -- The label and its choices as one part, for the tour to outline.
    local glowPart = CreateFrame("Frame", nil, page)
    glowPart:SetPoint("BOTTOMRIGHT", -16, 14)
    glowPart:SetSize(GLOW_PILLS + 10 + GLOW_LABEL, 20)
    readyGlow.part = glowPart
    window.readyGlow = readyGlow

    -- Why the list is empty, if it is, and a button's label, action and note
    -- to fix it where the addon can.
    local function ApplyLook()
        ns.Set("skin", true)
        window:Say("Reload to apply the look, then colour your bars here.")
        window:Refresh()
    end
    local function EmptyText(spells)
        if not ns.loaded.skin then
            if ns.Get("skin") then
                return "Reload first, then colour your bars one by one here.", "Reload", Reload,
                    "Reload your interface so the look takes effect."
            end
            return "Apply this look to the Cooldown Manager and reload to colour your bars one by one.", "Turn on", ApplyLook,
                "Tick Apply this look to the Cooldown Manager above, then reload."
        end
        if not ns.CooldownManagerOn() then
            return "Blizzard's Cooldown Manager is off.", "Turn on", TurnOnManager, "Switch Blizzard's Cooldown Manager on."
        end
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
        -- The warning takes the heading's row, so the heading's note steps aside.
        eachAbout:SetShown(not personalShown)
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
        -- Keybinds: a new file, so only after a full restart.
        local here, keysOn = ns.Keybinds ~= nil, ns.Get("keybinds")
        keybinds:SetShown(here)
        keyPlace:SetShown(here)
        keySize:SetShown(here)
        keybinds:SetChecked(keysOn)
        keyPlace:SetSelected(ns.Get("keybindPosition"))
        keyPlace:SetUsable(keysOn)
        keySize:Set(ns.Get("keybindSize"))
        keySize:SetUsable(keysOn)
        -- The same calls as the bars, so the preview can't drift from them.
        for i, icon in ipairs(sample.icons) do
            ns.Style:KeyLook(icon.key, icon, ICON, ns.Style:CountdownSize(ICON))
            ns.Style:SetKey(icon.key, SAMPLE_KEYS[i])
        end
        local barColour = ns.Get("barColour")
        for _, swatch in ipairs(barSwatches) do
            PaintSwatch(swatch, ns.Style:BarColour(swatch.key), swatch.key == barColour)
        end
        barChosen:SetText(ns.BAR_COLOUR_NAMES[barColour])
        -- The font, and each texture in the colour for all bars.
        font:SetSelected(ns.Get("font"))
        local texture, tint = ns.Get("barTexture"), ns.Style:BarColour(barColour)
        for _, swatch in ipairs(fills) do
            PaintSwatch(swatch, { 0, 0, 0 }, swatch.key == texture)
            swatch.fill:SetVertexColor(tint[1], tint[2], tint[3])
        end
        fillChosen:SetText(ns.BAR_TEXTURE_NAMES[texture])
        local accent = ns.Get("accent")
        for _, swatch in ipairs(swatches) do
            PaintSwatch(swatch, T.ACCENTS[swatch.key].colour, swatch.key == accent)
        end
        chosen:SetText(T.ACCENTS[accent].name)
        readyGlow:SetSelected(ns.Get("readyGlow"))

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
        local why, fixLabel, fixAction, fixNote = EmptyText(spells)
        if not why then
            for _, id in ipairs(spells) do entries[#entries + 1] = { spell = id } end
        end
        empty:ClearAllPoints()
        empty:SetPoint("TOPLEFT", 12, -(12 + personalRows * ROW))
        empty:SetText(why or "")
        empty:SetShown(why ~= nil)
        fix:SetLabel(fixLabel or "")
        fix.action, fix.about = fixAction, fixNote
        fix:SetShown(fixAction ~= nil)
        for i, entry in ipairs(entries) do
            local row = Row(i)
            row.entry = entry
            local chosen
            if entry.spell then
                local name = C_Spell and C_Spell.GetSpellName and C_Spell.GetSpellName(entry.spell)
                row.name:SetText(type(name) == "string" and name or ("Spell " .. entry.spell))
                row.icon:SetTexture(C_Spell and C_Spell.GetSpellTexture and C_Spell.GetSpellTexture(entry.spell) or 134400)
                chosen = ns.BarColourFor(entry.spell) -- saved at any rank of its spell
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
    window:Hint(bars, "Your own Cooldowns, Utility, Buffs and Debuffs bars. Off, none of them show.")
    window.useBars = bars
    Detail(page, "Cooldowns, Utility, Buffs and Debuffs bars of your own, set up on the left. Move and arrange them on the Layout page.", 34, -56)

    T:Heading(page, "Minimap button"):SetPoint("TOPLEFT", 16, -96)
    local minimap = T:Check(page, "Show the minimap button", function(self)
        ns.Set("minimap", self:GetChecked())
        if ns.MinimapButton then ns.MinimapButton:Apply() end
    end)
    minimap:SetPoint("TOPLEFT", 16, -116)
    window:Hint(minimap, "A button on the minimap for these settings. Off, Options > AddOns and /ccm still open them.")
    window.minimap = minimap
    local free = T:Check(page, "Free-floating", function(self)
        if ns.MinimapButton then ns.MinimapButton:SetFree(self:GetChecked()) end
    end)
    free:SetPoint("TOPLEFT", 260, -116)
    window:Hint(free, "Drag the button anywhere on the screen, not just round the minimap. It shows even with the minimap hidden.")
    window.minimapFree = free
    Detail(page, "Click it for these settings, right-click for What's new, and drag it round the minimap, or anywhere while it's free-floating.",
        34, -136)

    -- Help: the tour of the basics, as a first install offers it, and the
    -- Discord for bugs and ideas.
    T:Heading(page, "Help"):SetPoint("TOPLEFT", 16, -176)
    local tour = T:Button(page, "Take the tour", 110, 22)
    tour:SetPoint("TOPLEFT", 16, -194)
    tour:SetScript("OnClick", function() if ns.Tour then ns.Tour:Start() end end)
    window:Hint(tour, "A short tour of this window, a page at a time. /ccm tour starts it too.")
    window.tour = tour
    local discord = T:Button(page, "Discord", 80, 22)
    discord:SetPoint("TOPLEFT", 134, -194)
    discord:SetScript("OnClick", ns.ShowDiscord)
    window:Hint(discord, "The Discord invite, ready to copy: bugs, ideas and help.")
    window.discord = discord
    local helpAbout = T:Text(page, "GameFontHighlightSmall", T.MUTED)
    helpAbout:SetPoint("LEFT", discord, "RIGHT", 10, 0)
    helpAbout:SetText("A tour of the basics, or the Discord for bugs and ideas.")

    -- More from Squirt: the author's other addons, and a way to open them.
    T:Heading(page, "More from Squirt"):SetPoint("TOPLEFT", 16, -236)
    local more = CreateFrame("Frame", nil, page, "BackdropTemplate")
    more:SetPoint("TOPLEFT", 16, -256)
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
    -- Two lines, then the line under them at the foot: clear of each other.
    moreAbout:SetPoint("TOPLEFT", 60, -28)
    moreAbout:SetWidth(330) -- clear of the buttons on the right
    moreAbout:SetText("The Classic look for WoW Forever's whole interface, with quality of life options.")
    local moreState = T:Text(more, "GameFontHighlightSmall", T.MUTED)
    moreState:SetPoint("BOTTOMLEFT", 60, 8)
    local moreOpen = T:Button(more, "Open", 80, 22)
    moreOpen:SetPoint("RIGHT", -12, 0)
    moreOpen:SetScript("OnClick", function()
        local run = SlashCmdList and SlashCmdList.ERAUI
        if run then
            window:Hide()
            run("")
        end
    end)
    window:Hint(moreOpen, "Open EraUI's settings, as /era does.")
    local moreLinks = {}
    for i, link in ipairs(ERAUI_LINKS) do
        local button = T:Button(more, link.label, 90, 22)
        button:SetPoint("RIGHT", -12 - (#ERAUI_LINKS - i) * 98, 0)
        button:SetScript("OnClick", function() CopyLink("EraUI on " .. link.label, link.url, link.note) end)
        window:Hint(button, "EraUI on " .. link.label .. ", as a link to copy.")
        moreLinks[i] = button
    end
    window.moreOpen, window.moreState, window.moreLinks = moreOpen, moreState, moreLinks

    function page:Refresh()
        local installed = C_AddOns and C_AddOns.IsAddOnLoaded and C_AddOns.IsAddOnLoaded("EraUI")
        moreOpen:SetShown(installed and true or false)
        for _, button in ipairs(moreLinks) do button:SetShown(not installed) end
        moreState:SetText(installed and "Installed. Type /era, or click Open."
            or "Get it on CurseForge or GitHub: click one for its link.")
        bars:SetChecked(B:Enabled())
        minimap:SetChecked(ns.Get("minimap"))
        free:SetChecked(ns.Get("minimapFree"))
        -- New files only load after a full restart: until then, no tour.
        tour:SetShown(ns.Tour ~= nil)
    end
end

-- The bar list ---------------------------------------------------------------------

-- What each page is for, in the footer on hover.
local NAV_NOTES = {
    look = "Blizzard's Cooldown Manager restyled: bar designs, borders, shadows, keybinds, font, textures, ready glow and the accent.",
    layout = "One-click layouts that stack your bars around your Personal Resource Display.",
    cast = "Your own cast bar and a swing timer, under your Personal Resource Display.",
    general = "Your bars on or off, the minimap button, the tour, the Discord and EraUI.",
    raid = "Blizzard's pull countdown, raid warnings and boss cast bars, in your look.",
    pulse = "A big icon in the middle of your screen when a cooldown is ready.",
}

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
    window:Hint(item, NAV_NOTES[key] or ("Your " .. label .. " bar: its icons, how it shows, and your spells to tick onto it."))
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

-- The footer: the version on the left; on the right a note for the control
-- under the mouse, or else the last message, or else who made the addon.
-- Built before the pages, which give their controls notes as they're made.

-- "Made with <heart> by Squirt", the heart and name in the accent. The font
-- has no heart, so it's a small white texture inline in the text, tinted by
-- the escape's own colour: the text lays it out, so it sits right however
-- the line is justified, and it repaints with the line.
local function Credit()
    local accent = T:Accent()
    local function Byte(v) return math.floor(math.max(0, math.min(1, v)) * 255 + .5) end
    return ("Made with |T%s:0:0:0:0:32:32:0:32:0:32:%d:%d:%d|t by |cff%sSquirt|r"):format(ns.MEDIA .. HEART,
        Byte(accent[1]), Byte(accent[2]), Byte(accent[3]), T:Hex(accent))
end

local function BuildFooter(window)
    local version = T:Text(window, "GameFontHighlightSmall", T.MUTED)
    version:SetPoint("BOTTOMLEFT", 12, 9)
    version:SetText(Version() .. "   Options > AddOns or /ccm to open")
    window.versionText = version
    local note = T:Text(window, "GameFontHighlightSmall", T.MUTED)
    note:SetPoint("BOTTOMRIGHT", -12, 9)
    note:SetJustifyH("RIGHT")
    note:SetWidth(560)
    window.note = note
    -- Shown at the next refresh, and until the one after.
    function window:Say(text)
        self.message = text
    end

    -- With a spell or item on the game cursor: over a bar's drop target (a
    -- control with .drop, the bar's key or a function giving it), what
    -- dropping it there does, worked out without changing anything;
    -- anywhere else, why it was last turned away, while it's still held.
    -- Nil while the cursor holds nothing.
    function window:Holding(hovered)
        local held = ns.Bars:Holding()
        if not held then
            self.refused = nil
            return nil
        end
        local key = hovered and hovered.drop
        if type(key) == "function" then key = key(hovered) end
        if key then
            local _, text = ns.Bars:CursorNote(key)
            return text
        end
        local refused = self.refused
        if refused and refused.held == held then return refused.text end
        self.refused = nil
    end
    -- A drop turned away: why stays up while what was dropped is still held,
    -- wherever the mouse goes (the row, its icons, its buttons).
    function window:Refused(text)
        self.refused = { held = ns.Bars:Holding(), text = text }
    end

    -- The hovered control's note, worked out afresh (some change as you
    -- click), or what the footer rests on: the last message, or the credit.
    -- A message just said goes in front of the hovered control's note until
    -- the mouse moves onto a control, or the next refresh. What's held on
    -- the cursor goes in front of both.
    function window:ShowNote()
        local hovered = self.hovered
        if hovered and not hovered:IsVisible() then hovered, self.hovered = nil, nil end
        local text = hovered and not self.saying and hovered.hint
        if type(text) == "function" then text = text(hovered) end
        self.lastNote = self.said or Credit()
        note:SetText(self.dragging or self:Holding(hovered) or text or self.lastNote)
    end
    -- While an icon is dragged in the window, what letting go of it does
    -- goes in front of everything; nil once it's let go.
    function window:DragNote(text)
        self.dragging = text
        self:ShowNote()
    end
    function window:Note(control)
        self.hovered, self.saying = control, nil
        self:ShowNote()
    end
    -- Off a control, the footer rests. Notes follow the game's own enter and
    -- leave, which know what's on top (the "Are you sure?" dialog, the
    -- profile menu, the tour's box), not where the mouse is: from a control
    -- onto the next, a row onto its buttons or back, the game sends both in
    -- the same frame, so the resting line in between is never drawn. Only
    -- the control whose note is up can take it down, whichever order the
    -- game sends them.
    function window:Unnote(control)
        if self.hovered ~= control then return end
        self.hovered = nil
        self:ShowNote()
    end
    -- Every control's note, set up the same way. text: its note, or a
    -- function for one that changes. Hooked, so each keeps its own hover
    -- look. A slider has it all over, its label and value too, and on its
    -- track, which takes the mouse over the rest.
    function window:Hint(control, text)
        if control.track then
            control:EnableMouse(true)
            self:Hint(control.track, text)
        end
        control.hint = text
        control:HookScript("OnEnter", function() window:Note(control) end)
        control:HookScript("OnLeave", function() window:Unnote(control) end)
    end
    -- Closed, nothing is under the mouse any more: open, the footer rests.
    window:HookScript("OnHide", function() window.hovered, window.dragging, window.refused = nil, nil, nil end)
    -- Something picked up or put away (or dropped on a bar): the footer
    -- follows at once, while the window is open.
    local cursor = CreateFrame("Frame", nil, window)
    cursor:RegisterEvent("CURSOR_CHANGED")
    cursor:SetScript("OnEvent", function()
        if window:IsShown() then window:ShowNote() end
    end)
    window.cursorWatch = cursor
    -- A new accent recolours the heart and name at once.
    T:Paint(function() window:ShowNote() end)
end

-- The ? beside the X: a walkthrough of the page showing (Tour.lua), or a
-- word in the footer where there's none, as over the profile menu. Hovered,
-- a tooltip just under it says what it does. Until it's first clicked (once
-- for the whole account), it gently pulses in the accent and a note under
-- it points it out, with an x to put the note away, on the pages it leaves
-- room on. Neither shows while the welcome, the tour or a walkthrough is
-- up, nor over the profile menu or What's new: they come back after, and
-- each time the window opens again.
local NUDGE_TEXT = "New: click ? for help with any page"
local NUDGE_PAD = 10
local NUDGE_TEXT_WIDTH = 240 -- one line, with room to spare
local NUDGE_GAP = 4 -- between the ? and the tip of the note's arrow
local NUDGE_ARROW = { 16, 9 }
local NUDGE_PERIOD = 2.4 -- seconds for one slow pulse, dim to lit and back
local NUDGE_FILL, NUDGE_EDGE = .3, .8 -- how much accent at its strongest: inside, and the edge

local function BuildHelp(window, header)
    local help = T:Square(header, "?")
    help:SetSize(22, 22)
    help:SetPoint("RIGHT", header.close, "LEFT", -6, 0)
    window.help = help
    function window:Help()
        if self.profilePanel and self.profilePanel:IsShown() then
            -- With Share and Import there (a new file: after a full restart).
            -- The menu's own hint, always in sight, says x deletes and a typed name makes one.
            self:Say(self.profileShare and "Click a profile or role to use it, right-click a role to save. Share or Import as text."
                or "Click a profile or role to use it, right-click a role to save. Type a name to make one.")
            return self:Refresh()
        end
        if ns.Tour and ns.Tour:StartPage(self.selected) then return end
        self:Say("Nothing to walk through here yet. Hover over anything and this line says what it does.")
        self:Refresh()
    end
    help:HookScript("OnEnter", function(self)
        T:ShowTip(self, "Page help", "Walks you through this page, a step at a time.", "below")
    end)
    help:HookScript("OnLeave", function(self) T:HideTip(self) end)

    -- The pulse: the accent glowing softly inside the ? and on its edge.
    local glow = help:CreateTexture(nil, "ARTWORK")
    glow:SetPoint("TOPLEFT", 1, -1)
    glow:SetPoint("BOTTOMRIGHT", -1, 1)
    glow:SetAlpha(0)
    glow:Hide()
    help.glow = glow
    -- The note: under the ? and the X, inside the window (which stays on
    -- screen), below the title bar, its arrow pointing up at the ?. Under
    -- the profile menu (60), the tour (70, 80) and Are you sure? (80).
    local nudge = CreateFrame("Frame", nil, window, "BackdropTemplate")
    nudge:SetSize(NUDGE_PAD + NUDGE_TEXT_WIDTH + 6 + 16 + 6, 28) -- its height again once the text is in
    nudge:SetFrameLevel(window:GetFrameLevel() + 50)
    nudge:SetClampedToScreen(true)
    nudge:EnableMouse(true) -- what's under it isn't clicked by mistake
    T:Flat(nudge, T.BG, T.CONTROL_BORDER)
    nudge.text = T:Text(nudge, "GameFontHighlightSmall")
    nudge.text:SetWidth(NUDGE_TEXT_WIDTH)
    nudge.text:SetJustifyH("CENTER")
    nudge.text:SetWordWrap(true)
    nudge.text:SetText(NUDGE_TEXT)
    nudge.text:SetPoint("LEFT", NUDGE_PAD, 0)
    local away = T:Square(nudge, "x")
    away:SetSize(16, 16)
    away:SetPoint("RIGHT", -6, 0)
    window:Hint(away, "Put this note away. The ? stays, for help with any page.")
    nudge.close = away
    nudge:SetHeight(2 * 8 + math.max(12, math.ceil(nudge.text:GetStringHeight() or 12)))
    nudge:SetPoint("TOPRIGHT", header.close, "BOTTOMRIGHT", 0, -(NUDGE_GAP + NUDGE_ARROW[2]))
    nudge.arrow = nudge:CreateTexture(nil, "ARTWORK")
    nudge.arrow:SetTexture(ns.MEDIA .. "TourArrow.tga")
    nudge.arrow:SetSize(NUDGE_ARROW[1], NUDGE_ARROW[2])
    nudge.arrow:SetTexCoord(0, 1, 0, 1)
    nudge.arrow:SetPoint("TOP", help, "BOTTOM", 0, -NUDGE_GAP)
    nudge:Hide()
    window.helpNudge = nudge

    -- Runs every frame until the ? is clicked: the note and the pulse, held
    -- back while something else is up.
    local driver = CreateFrame("Frame", nil, window)
    driver:SetSize(1, 1)
    driver:SetPoint("TOPLEFT")
    nudge.driver = driver
    local since, accent = 0, nil
    -- The accent picked, kept here (this runs every frame), and its share of
    -- the edge's colour worked out in place, with nothing made each frame.
    T:Paint(function(colour) accent = colour end)
    local function Edge(share)
        local from = T.CONTROL_BORDER
        help:SetBackdropBorderColor(from[1] + (accent[1] - from[1]) * share, from[2] + (accent[2] - from[2]) * share,
            from[3] + (accent[3] - from[3]) * share, 1)
    end
    local function Held()
        return (ns.Tour ~= nil and ns.Tour:Active()) or (window.profilePanel ~= nil and window.profilePanel:IsShown())
            or (ns.notes ~= nil and ns.notes:IsShown())
    end
    -- The note only where nothing is under it: the bar pages and General.
    -- Elsewhere buttons or words sit at the right of the page's top row, so
    -- there only the ? pulses.
    local function Room()
        local key = window.selected
        return ns.BAR_NAMES[key] ~= nil or key == "general"
    end
    local function Update(_, elapsed)
        since = (since + (elapsed or 0)) % NUDGE_PERIOD
        local held = Held()
        nudge:SetShown(not held and Room())
        glow:SetShown(not held)
        -- Dim to lit and back, smoothly.
        local share = held and 0 or (1 - math.cos(since / NUDGE_PERIOD * 2 * math.pi)) / 2
        glow:SetAlpha(NUDGE_FILL * share)
        Edge(NUDGE_EDGE * share)
    end
    driver:SetScript("OnUpdate", Update)
    -- Clicked once, by the ? or the note's x: gone for good.
    local function Seen()
        ns.SetHelpSeen()
        driver:Hide()
        nudge:Hide()
        glow:Hide()
        Edge(0)
    end
    driver:SetShown(not ns.HelpSeen())
    away:SetScript("OnClick", Seen)
    help:SetScript("OnClick", function(self)
        T:HideTip(self)
        Seen()
        window:Help()
    end)
    -- Each time the window opens the pulse starts dim, the note waiting a
    -- frame to see what else is up; closed, both go with it.
    window:HookScript("OnShow", function() since = 0 end)
    window:HookScript("OnHide", function()
        T:HideTip(help)
        nudge:Hide()
        glow:Hide()
    end)
    -- A new accent: the note and the glow at once, the ?'s edge next frame.
    T:Paint(function(accent)
        nudge:SetBackdropBorderColor(accent[1], accent[2], accent[3], 1)
        nudge.arrow:SetVertexColor(accent[1], accent[2], accent[3], 1)
        glow:SetColorTexture(accent[1], accent[2], accent[3], 1)
    end)
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
    end)
    window:SetScript("OnHide", function(self)
        -- Closed mid-drag, it never hears the mouse let go: stop moving now.
        self:StopMovingOrSizing()
        if ns.Bars then ns.Bars:SetUnlocked(false) end
    end)
    ns.CloseOnEscape(window)

    -- Header: the addon's icon, and "Enhanced" in the accent.
    local header = T:TitleBar(window, HEADER)
    -- The accent washes in from the right, over the title bar and the pages.
    window.fades = { header = header.fade, page = T:Fade(window, T.FADE.page) }
    window.fades.page:SetPoint("TOPLEFT", NAV + 1, -(HEADER + 1))
    window.fades.page:SetPoint("BOTTOMRIGHT", -1, FOOTER)
    window.close = header.close
    window.header = header
    BuildFooter(window)
    window:Hint(header.close, "Close the window. Escape closes it too. The minimap button, Options > AddOns or /ccm opens it again.")
    BuildHelp(window, header)
    BuildConfirm(window)
    ns.BuildProfileMenu(window, header, window.help)

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
    -- More: pages beyond the Cooldown Manager and your bars, headed like
    -- your bars: Raid Timers, then Cooldown pulse. New files, so each only
    -- after a full restart.
    local raidPage = ns.BuildRaidTimersPage ~= nil
    local pulsePage = ns.BuildPulsePage ~= nil
    if raidPage or pulsePage then
        local more = y + (castPage and 128 or 96)
        local moreRule = nav:CreateTexture(nil, "BORDER")
        moreRule:SetPoint("TOPLEFT", 12, -(more + 4))
        moreRule:SetPoint("RIGHT", -12, 0)
        moreRule:SetHeight(1)
        T:Fill(moreRule, T.BORDER)
        local moreHeading = T:Text(nav, "GameFontHighlightSmall", T.MUTED)
        moreHeading:SetPoint("TOPLEFT", 14, -(more + 14))
        moreHeading:SetText("MORE")
        window.moreHeading = moreHeading
        local at = more + 30
        if raidPage then
            window.nav.raid = NavItem(window, nav, "raid", "Raid Timers", at)
            at = at + 32
        end
        if pulsePage then window.nav.pulse = NavItem(window, nav, "pulse", "Cooldown pulse", at) end
    end
    -- What's new in this version, at the foot of the list.
    local news = T:Button(nav, "What's new", NAV - 24, 22)
    news:SetPoint("BOTTOMLEFT", 12, 12)
    news:SetScript("OnClick", function() if ns.ShowNotes then ns.ShowNotes() end end)
    window:Hint(news, "What changed in this version. /ccm new shows it too.")
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
    if raidPage then
        window.pages.raid = Page()
        ns.BuildRaidTimersPage(window, window.pages.raid, WIDTH - NAV - 2)
    end
    if pulsePage then
        window.pages.pulse = Page()
        ns.BuildPulsePage(window, window.pages.pulse, WIDTH - NAV - 2)
    end
    BuildGeneral(window, window.pages.general)
    ns.BuildBarPage(window, window.pages.bar, WIDTH - NAV - 2)

    window.selected = "cd"
    function window:Select(key)
        self.selected = key
        self.profilePanel:Hide()
        self:Refresh()
        if ns.Tour then ns.Tour:Sync() end
    end

    function window:Refresh()
        self:RefreshProfiles()
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
        -- A message takes the footer, even from the control just clicked,
        -- for now: the next refresh without one, or the mouse onto another
        -- control, brings a hovered control's note back, updated.
        self.said, self.message = self.message, nil
        self.saying = self.said ~= nil
        self:ShowNote()
    end

    ns.window = window
    -- What Switch with my talents last did before the window was first made,
    -- in the footer as it first opens (Core.lua TalentNote).
    if ns.talentNote then window:Say(ns.talentNote) end
    return window
end

function ns.ShowWindow()
    local window = ns.window or BuildWindow()
    window:Show()
    window:Raise()
end

-- /fecm reset: opens the Layout page and asks, just as its Reset button does.
function ns.AskReset()
    ns.ShowWindow()
    local window = ns.window
    window:Select("layout")
    local reset = window.pages.layout.reset
    if reset then reset:Click() end
end

function ns.Toggle()
    local window = ns.window or BuildWindow()
    window:SetShown(not window:IsShown())
end
