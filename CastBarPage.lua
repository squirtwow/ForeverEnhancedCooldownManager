-- The Cast bar page in the /ccm window: your own cast bar under the Personal
-- Resource Display, shown in a live preview in the Look page's design, and
-- its choices: on or off, its colour and height, and whether the spell's
-- icon, name and time left show on it.
local _, ns = ...
local T = ns.Theme

local SWATCH, SWATCH_GAP = 20, 6
local SAMPLE = { name = "Hearthstone", icon = "Interface\\Icons\\INV_Misc_Rune_01", total = 3 }

function ns.BuildCastBarPage(window, page, width)
    local C = ns.CastBar
    local inner = width - 32
    local function Note(text) window.note:SetText(text) end
    local function Unnote() window.note:SetText(window.lastNote or "") end
    local function Changed()
        C:Apply()
        window:Refresh()
    end

    local title = T:Heading(page, "Cast bar")
    title:SetPoint("TOPLEFT", 16, -16)
    local status = T:Text(page, "GameFontHighlightSmall", T.MUTED)
    status:SetPoint("LEFT", title, "RIGHT", 10, 0)
    page.status = status

    -- The preview: a cast bar like yours, filling over and over.
    local tray = CreateFrame("Frame", nil, page, "BackdropTemplate")
    tray:SetPoint("TOPLEFT", 16, -38)
    tray:SetSize(inner, 56)
    T:Flat(tray, T.PANEL, T.BORDER)
    local sample = C:Make(tray)
    sample:SetPoint("LEFT", 12, 0)
    sample:SetWidth(300)
    sample.icon:SetTexture(SAMPLE.icon)
    sample.bar.name:SetText(SAMPLE.name)
    sample.bar:SetMinMaxValues(0, SAMPLE.total)
    local elapsed = 0
    sample:SetScript("OnUpdate", function(_, delta)
        elapsed = (elapsed + delta) % SAMPLE.total
        sample.bar:SetValue(elapsed)
        sample.bar.time:SetFormattedText("%.1f", SAMPLE.total - elapsed)
    end)
    page.sample = sample
    local previewNote = T:Text(tray, "GameFontHighlightSmall", T.MUTED)
    previewNote:SetPoint("RIGHT", -12, 0)
    previewNote:SetJustifyH("RIGHT")
    previewNote:SetText("Preview. Changes show straight away.")

    local options = CreateFrame("Frame", nil, page)
    options:SetPoint("TOPLEFT", tray, "BOTTOMLEFT", 0, -12)
    options:SetSize(inner, 190)
    local function Tick(label, key, y, note)
        local check = T:Check(options, label, function(self)
            ns.Set(key, self:GetChecked())
            Changed()
        end)
        check:SetPoint("TOPLEFT", 0, y)
        check:HookScript("OnEnter", function() Note(note) end)
        check:HookScript("OnLeave", Unnote)
        return check
    end
    local shown = Tick("Show my cast bar under the resource display", "castBar", -4,
        "On, Blizzard's own cast bar is hidden. Off, your rows close up and another addon's cast bar works as before.")

    -- Its colour: click the chosen one again for Blizzard's gold.
    local label = T:Text(options, "GameFontHighlight")
    label:SetPoint("TOPLEFT", 0, -36)
    label:SetText("Colour")
    local swatches = {}
    for i, key in ipairs(ns.BAR_COLOUR_KEYS) do
        local swatch = ns.Swatch(options, SWATCH, function()
            ns.Set("castColour", ns.Get("castColour") ~= key and key or "default")
            Changed()
        end)
        swatch:SetPoint("TOPLEFT", 100 + (i - 1) * (SWATCH + SWATCH_GAP), -32)
        swatch.key = key
        if key == "class" then ns.ClassIcon(swatch) end
        swatch:SetScript("OnEnter", function()
            Note("A colour for your cast bar. Click it again for Blizzard's gold, green while channelling.")
        end)
        swatch:SetScript("OnLeave", Unnote)
        swatches[i] = swatch
    end
    page.swatches = swatches
    local chosen = T:Text(options, "GameFontHighlightSmall", T.MUTED)
    chosen:SetPoint("TOPLEFT", 100 + #ns.BAR_COLOUR_KEYS * (SWATCH + SWATCH_GAP) + 2, -36)
    page.chosen = chosen

    local height = T:Slider(options, "Height", ns.CAST_HEIGHT, 1, 280, function(value)
        ns.Set("castHeight", value)
        Changed()
    end)
    height:SetPoint("TOPLEFT", 0, -64)
    page.height = height

    local icon = Tick("Spell icon", "castIcon", -96, "The spell's icon at the left end.")
    local name = Tick("Spell name", "castName", -118, "The spell's name on the bar.")
    local timer = Tick("Cast time", "castTime", -140, "Seconds left, at the right end.")
    page.shown, page.icon, page.name, page.timer = shown, icon, name, timer

    local about = T:Text(options, "GameFontHighlightSmall", T.MUTED)
    about:SetPoint("TOPLEFT", 0, -170)
    about:SetWidth(inner)
    about:SetText("It sits right under your Personal Resource Display, and in a layout the rows go under it. "
        .. "It keeps its room between casts, since the Buffs and Debuffs bars can't move in a fight.")

    function page:Refresh()
        local on = ns.Get("castBar")
        status:SetText(on and "Under your Personal Resource Display. Blizzard's cast bar is hidden."
            or "Off. Your rows close up, and other cast bar addons work as before.")
        shown:SetChecked(on)
        icon:SetChecked(ns.Get("castIcon"))
        name:SetChecked(ns.Get("castName"))
        timer:SetChecked(ns.Get("castTime"))
        height:Set(ns.Get("castHeight"))
        local colour = ns.Get("castColour")
        for _, swatch in ipairs(swatches) do
            ns.PaintSwatch(swatch, ns.Style:BarColour(swatch.key), swatch.key == colour)
        end
        chosen:SetText(colour == "default" and "Blizzard's gold" or ns.BAR_COLOUR_NAMES[colour])
        C:Look(sample, false)
    end
end
