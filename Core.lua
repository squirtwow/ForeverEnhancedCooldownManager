-- Forever Enhanced Cooldown Manager: saved settings, the /ccm command, Escape
-- for the window and the entry in Options > AddOns. Each feature lives in its
-- own file and starts from here once the saved settings are loaded.
local ADDON, ns = ...

ns.TITLE = "Forever Enhanced Cooldown Manager"
ns.MEDIA = "Interface\\AddOns\\" .. ADDON .. "\\Media\\"

-- The addon's version, filled in when it's packaged for release; "dev" for a
-- copy straight from the source.
function ns.Version()
    local get = C_AddOns and C_AddOns.GetAddOnMetadata or GetAddOnMetadata
    local version = get and get(ADDON, "Version")
    if type(version) ~= "string" or version == "" or version:find("@", 1, true) then return "dev" end
    return version
end

-- The version of whatever waits for the next update's number: its notes
-- (Notes.lua) and the tour steps it adds (Tour.lua). The release gives them
-- that number in place of this.
ns.UNRELEASED = "Unreleased"

-- A version as numbers to compare part by part ("1.10.2" is 1, 10, 2), or nil
-- if it isn't one. What's unreleased comes after every release, and a copy
-- straight from the source ("dev") after that.
local function VersionParts(version)
    if version == ns.UNRELEASED then return { math.huge } end
    if version == "dev" then return { math.huge, math.huge } end
    local digits = type(version) == "string" and version:match("^v?(%d+[%d%.]*)")
    if not digits then return nil end
    local parts = {}
    for part in digits:gmatch("%d+") do parts[#parts + 1] = tonumber(part) end
    return parts
end

-- -1, 0 or 1 as version a is older than, the same as or newer than b ("1.1"
-- is "1.1.0"); nil if either isn't a version.
function ns.CompareVersions(a, b)
    a, b = VersionParts(a), VersionParts(b)
    if not (a and b) then return nil end
    for i = 1, math.max(#a, #b) do
        local x, y = a[i] or 0, b[i] or 0
        if x ~= y then return x < y and -1 or 1 end
    end
    return 0
end

ns.DEFAULTS = {
    skin = true,
    useBars = false, -- the addon's own bars
    listItems = false, -- show trinkets and bag items in the /ccm spell list
    listRanks = false, -- show every rank you know as its own row
    accent = "orange", -- the /ccm window's accent colour
    barStyle = "glass", -- Blizzard's Tracked Bars: glass, split or outline
    barColour = "orange", -- and their colour
    barTexture = "flat", -- the fill of the addon's bars and the restyled ones: flat, or one of the game's (Look page)
    font = "friz", -- the numbers and text on icons and bars: Friz Quadrata, or another of the game's fonts
    prdSkin = true, -- Blizzard's Personal Resource Display in the same design
    prdHideRepeat = true, -- its second mana bar hidden while the main one is mana
    prdHealth = "default", -- its bars' colours: Blizzard's, or a bar colour
    prdPower = "default",
    prdMatch = true, -- while a layout holds your bars, the display is as wide as your widest row
    prdCombo = false, -- the addon's own combo points under the display
    prdComboColour = "default", -- their colour: the addon's red, or a bar colour
    castBar = false, -- the addon's own cast bar under the display
    castColour = "default", -- its colour: Blizzard's gold (green channelling), or a bar colour
    castHeight = 18,
    castIcon = true, -- the spell's icon, name and time left on it
    castName = true,
    castTime = true,
    swingTimer = false, -- a swing timer in the cast bar's spot: Auto Shot for hunters, the main hand for everyone
    swingColour = "default", -- its colour: silver, or a bar colour
    iconBorder = "off", -- a thin border round each icon ("icon") or whole bars ("bar")
    iconShadow = "off", -- and a soft shadow, the same way
    keybinds = false, -- each Cooldowns/Utility icon's key, from your action bars (Look page)
    keybindPosition = "BOTTOM", -- where on the icon: BOTTOM, TOPLEFT, TOP or TOPRIGHT
    keybindSize = 100, -- its size, as a share of the automatic size that follows the icon
    layoutPreview = true, -- the Layout page draws your icons with the Look page's border, shadow and keybinds
    barScale = 100, -- every bar's icons together, as a share of each bar's own size (the Layout page's All bars)
    growArrows = false, -- while your bars are arranged (unlocked or in Edit Mode), an arrow on each for the way it grows
    minimap = true, -- the minimap button
    minimapAngle = 225, -- where it sits round the minimap: degrees anticlockwise from the right
}
ns.DECOR_KEYS = { "off", "icon", "bar" }
ns.DECOR_NAMES = { off = "Off", icon = "Each icon", bar = "Whole bar" }
ns.KEYBIND_POSITIONS = { "BOTTOM", "TOPLEFT", "TOP", "TOPRIGHT" }
ns.KEYBIND_POSITION_NAMES = { BOTTOM = "Bottom", TOPLEFT = "Top left", TOP = "Top", TOPRIGHT = "Top right" }
-- Number settings, each within its limits: min, max, default.
ns.CAST_HEIGHT = { 10, 32, 18 }
ns.MINIMAP_ANGLE = { 0, 359, 225 }
ns.KEYBIND_SIZE = { 50, 150, 100 } -- min, max, default (percent)
ns.BAR_SCALE = { 50, 150, 100 } -- min, max, default (percent)
local NUMBERS = { castHeight = ns.CAST_HEIGHT, minimapAngle = ns.MINIMAP_ANGLE, keybindSize = ns.KEYBIND_SIZE,
    barScale = ns.BAR_SCALE }
-- Choices a text setting may hold.
ns.ACCENT_KEYS = { "orange", "blue", "teal", "purple", "green" }
ns.BAR_STYLE_KEYS = { "glass", "split", "outline" }
ns.BAR_STYLE_NAMES = { glass = "Glass", split = "Split", outline = "Outline" }
ns.BAR_COLOUR_KEYS = { "orange", "charcoal", "blue", "green", "purple", "class" } -- your class colour last
ns.BAR_COLOUR_NAMES = { orange = "Orange", class = "Class", charcoal = "Charcoal", blue = "Blue", green = "Green", purple = "Purple" }
-- The game's own fonts and bar textures, so every player has them (their
-- files are in Style.lua).
ns.FONT_KEYS = { "friz", "arial", "morpheus", "skurri" }
ns.FONT_NAMES = { friz = "Friz Quadrata", arial = "Arial Narrow", morpheus = "Morpheus", skurri = "Skurri" }
ns.BAR_TEXTURE_KEYS = { "flat", "classic", "raid", "skills" }
ns.BAR_TEXTURE_NAMES = { flat = "Flat", classic = "Classic", raid = "Raid", skills = "Skills" }
local CHOICES = { accent = {}, barStyle = {}, barColour = {}, prdHealth = { default = true }, prdPower = { default = true },
    prdComboColour = { default = true }, castColour = { default = true }, swingColour = { default = true },
    iconBorder = { off = true, icon = true, bar = true }, iconShadow = { off = true, icon = true, bar = true },
    keybindPosition = {}, font = {}, barTexture = {} }
for _, key in ipairs(ns.ACCENT_KEYS) do CHOICES.accent[key] = true end
for _, key in ipairs(ns.KEYBIND_POSITIONS) do CHOICES.keybindPosition[key] = true end
for _, key in ipairs(ns.BAR_STYLE_KEYS) do CHOICES.barStyle[key] = true end
for _, key in ipairs(ns.FONT_KEYS) do CHOICES.font[key] = true end
for _, key in ipairs(ns.BAR_TEXTURE_KEYS) do CHOICES.barTexture[key] = true end
for _, key in ipairs(ns.BAR_COLOUR_KEYS) do
    CHOICES.barColour[key], CHOICES.prdHealth[key], CHOICES.prdPower[key] = true, true, true
    CHOICES.prdComboColour[key], CHOICES.castColour[key], CHOICES.swingColour[key] = true, true, true
end

function ns.Valid(key, value)
    local default = ns.DEFAULTS[key]
    if type(default) == "boolean" then return type(value) == "boolean" end
    if CHOICES[key] then return CHOICES[key][value] == true end
    local limits = NUMBERS[key]
    if limits then return type(value) == "number" and value >= limits[1] and value <= limits[2] end
    return type(value) == type(default)
end
-- Settings that only take effect after a reload.
ns.RELOAD = {
    skin = true,
    prdSkin = true,
}

-- Bars: each bar lists spells by name, so the highest known rank is
-- always the one shown.
ns.BAR_KEYS = { "cd", "util", "buff", "debuff" }
ns.BAR_NAMES = { cd = "Cooldowns", util = "Utility", buff = "Buffs", debuff = "Debuffs" }
-- The bars fed by Blizzard's secure aura container, and what each watches.
ns.AURA_BARS = {
    buff = { unit = "player", filter = "HELPFUL", word = "buff" },
    debuff = { unit = "target", filter = "HARMFUL", mine = true, word = "debuff" },
}
ns.BAR_LIMITS = { size = { 20, 64, 36 }, spacing = { 0, 20, 4 }, perRow = { 1, 20, 20 } } -- min, max, default
ns.ROW_GAP = { 0, 20, 0 } -- a layout's space between rows: touching unless you want room
ns.ICON_GAP = { 0, 20, 0 } -- and between the icons in its rows
ns.BAR_MAX_SPELLS = 40
-- Which way a row grows as icons come and go, and where a new row goes when
-- there are more icons than fit across.
ns.GROW = { "centre", "left", "right" }
ns.GROW_NAMES = { centre = "Centre", left = "Left", right = "Right" }
ns.WRAP = { "down", "up" }
ns.WRAP_NAMES = { down = "Below", up = "Above" }
-- The points a saved position can be for; positions saved before rows were
-- from the centre.
local POINTS = { CENTER = true, TOP = true, BOTTOM = true, TOPLEFT = true, TOPRIGHT = true,
    BOTTOMLEFT = true, BOTTOMRIGHT = true }
-- Out of combat a bar shows, fades or hides; it comes back in full in combat,
-- with an enemy targeted, while unlocked, or in Edit Mode.
ns.OUT_OF_COMBAT = { "show", "fade", "hide" }
ns.OUT_OF_COMBAT_NAMES = { show = "Show", fade = "Fade", hide = "Hide" }
-- While its spell is ready an icon shows in full, dims or hides, so the ones
-- cooling down stand out.
ns.WHEN_READY = { "show", "dim", "hide" }
ns.WHEN_READY_NAMES = { show = "Show", dim = "Dim", hide = "Hide" }
ns.BUFF_SLOTS = 16 -- the Buffs bar has one secure slot per buff

local db
ns.loaded = {}

function ns.Get(key)
    local value = db and db[key]
    if value == nil or not ns.Valid(key, value) then value = ns.DEFAULTS[key] end
    return value
end

local function Finite(n)
    return type(n) == "number" and n == n and n > -math.huge and n < math.huge
end

local function Limit(value, limits)
    if not Finite(value) then return limits[3] end
    return math.max(limits[1], math.min(limits[2], math.floor(value + .5)))
end

-- Profiles ---------------------------------------------------------------------
-- The spell lists live in profiles; everything else (look, sizes, places) is
-- shared. Each character, told apart by its GUID since two can share a name,
-- uses one profile, at first its own "Name (Class) - Realm". Several
-- characters can share one, and profiles never change in combat.
ns.PROFILE_MAX = 48 -- longest profile name

local active -- this character's profile, once the character is known
local scratch = {} -- lists used before then; never saved

local function Profiles()
    if type(db.profiles) ~= "table" then db.profiles = {} end
    return db.profiles
end

local function Chars()
    if type(db.chars) ~= "table" then db.chars = {} end
    return db.chars
end

local function Repair(spells)
    for i = #spells, 1, -1 do
        if type(spells[i]) ~= "string" or spells[i] == "" then table.remove(spells, i) end
    end
    for i = #spells, ns.BAR_MAX_SPELLS + 1, -1 do spells[i] = nil end
    return spells
end

-- A profile's lists, repaired in place, with their joins: on the Buffs and
-- Debuffs bars, the names joined to the entry just before them.
local function Lists(profile)
    for _, key in ipairs(ns.BAR_KEYS) do
        if type(profile[key]) ~= "table" then profile[key] = {} end
        Repair(profile[key])
    end
    if type(profile.joins) ~= "table" then profile.joins = {} end
    for key, joins in pairs(profile.joins) do
        if not ns.AURA_BARS[key] or type(joins) ~= "table" then
            profile.joins[key] = nil
        else
            local listed = {}
            for i, name in ipairs(profile[key]) do
                if i > 1 then listed[name] = true end
            end
            for name, on in pairs(joins) do
                if on ~= true or not listed[name] then joins[name] = nil end
            end
        end
    end
    return profile
end

-- The profile chosen for every character, new ones included, if there is one.
local function Everyone()
    local name = db and db.everyone
    if type(name) == "string" and Profiles()[name] then return name end
end

local function RepairProfiles()
    local profiles = Profiles()
    for name, profile in pairs(profiles) do
        if type(name) ~= "string" or type(profile) ~= "table" then profiles[name] = nil else Lists(profile) end
    end
    local chars = Chars()
    for guid, name in pairs(chars) do
        if type(guid) ~= "string" or type(name) ~= "string" then chars[guid] = nil end
    end
    db.everyone = Everyone()
end

-- The list a bar shows: this character's profile, or a stand-in until the
-- character is known.
function ns.ActiveList(key)
    local profile = active and db and Profiles()[active]
    if profile then
        if type(profile[key]) ~= "table" then profile[key] = {} end
        return profile[key]
    end
    scratch[key] = scratch[key] or {}
    return scratch[key]
end

-- This character's joins for an aura bar.
function ns.Joins(key)
    local profile = active and db and Profiles()[active]
    local store = profile or scratch
    if type(store.joins) ~= "table" then store.joins = {} end
    if type(store.joins[key]) ~= "table" then store.joins[key] = {} end
    return store.joins[key]
end

local function PlayerGUID()
    local guid = UnitGUID and UnitGUID("player")
    return type(guid) == "string" and guid ~= "" and guid or nil
end

local UNKNOWN = UNKNOWNOBJECT or "Unknown"

-- Text cut to at most max bytes, never through the middle of a letter, and
-- without a space left at the end.
local function Cut(text, max)
    if #text <= max then return text end
    local cut = max
    -- A byte from 128 to 191 carries on the letter before it.
    while cut > 0 and (text:byte(cut + 1) or 0) >= 128 and (text:byte(cut + 1) or 0) < 192 do cut = cut - 1 end
    return (text:sub(1, cut):gsub("%s+$", ""))
end

-- "Name (Class) - Realm", cut to fit a profile name. On a character's very
-- first login the game may not know its name yet: nil then, unless a name is
-- needed now anyway.
local function OwnName(anyway)
    local name = UnitName and UnitName("player")
    if type(name) ~= "string" or name == "" or name == UNKNOWN then
        if not anyway then return nil end
        name = UNKNOWN
    end
    local class = UnitClass and UnitClass("player") or UNKNOWN
    local realm = GetRealmName and GetRealmName() or ""
    if realm == "" then return Cut(("%s (%s)"):format(name, class), ns.PROFILE_MAX) end
    return Cut(("%s (%s) - %s"):format(name, class, realm), ns.PROFILE_MAX)
end

-- The name itself if it's free, otherwise with a number after it, cut
-- shorter where needed so it still fits.
local function FreeName(name)
    local profiles, candidate, n = Profiles(), name, 1
    while profiles[candidate] do
        n = n + 1
        local suffix = " " .. n
        candidate = Cut(name, ns.PROFILE_MAX - #suffix) .. suffix
    end
    return candidate
end

-- Works out this character's profile, making its own on its first login
-- (or using the one chosen for every character). The first character to log
-- in after profiles arrived keeps the lists that were saved before them. A
-- new profile waits until the game knows the character's name, at login at
-- the latest ("final").
function ns.ResolveProfile(final)
    if active then return true end
    local guid = db and PlayerGUID()
    if not guid then return false end
    local profiles, chars = Profiles(), Chars()
    local name = chars[guid]
    if not profiles[name] and Everyone() then
        name = Everyone()
        chars[guid] = name
    elseif not profiles[name] then
        local own = OwnName(final)
        if not own then return false end
        local legacy = next(profiles) == nil
        name = FreeName(own)
        local profile = {}
        for _, key in ipairs(ns.BAR_KEYS) do
            local bar = type(db.bars) == "table" and db.bars[key]
            local old = legacy and type(bar) == "table" and rawget(bar, "spells")
            profile[key] = type(old) == "table" and old or {}
        end
        profiles[name] = profile
        chars[guid] = name
    end
    if type(db.bars) == "table" then
        for _, bar in pairs(db.bars) do
            if type(bar) == "table" then rawset(bar, "spells", nil) end
        end
    end
    Lists(profiles[name])
    active = name
    return true
end

function ns.ProfileName()
    return active
end

function ns.ProfileNames()
    local names = {}
    if not db then return names end
    for name in pairs(Profiles()) do names[#names + 1] = name end
    table.sort(names, function(a, b)
        if a:lower() ~= b:lower() then return a:lower() < b:lower() end
        return a < b
    end)
    return names
end

-- How many characters use a profile.
function ns.ProfileUsers(name)
    local count = 0
    for _, used in pairs(db and Chars() or {}) do
        if used == name then count = count + 1 end
    end
    return count
end

local function Blocked()
    if InCombatLockdown() then return "Profiles can't change in combat." end
    if not active then return "Your profile hasn't loaded yet." end
end

local function CleanName(text)
    local name = type(text) == "string" and text:match("^%s*(.-)%s*$") or ""
    if name == "" then return nil, "Type a profile name first." end
    if #name > ns.PROFILE_MAX then return nil, "Profile names can be up to " .. ns.PROFILE_MAX .. " characters." end
    if name:find("[%c|]") then return nil, "Profile names can't use the | character." end
    return name
end

local function Switch(name)
    Chars()[PlayerGUID()] = name
    active = name
    if ns.Bars and ns.Bars.started then ns.Bars:Changed() end
end

function ns.UseProfile(name)
    local why = Blocked()
    if why then return false, why end
    if not Profiles()[name] then return false, ('No profile is called "%s".'):format(tostring(name)) end
    if name == active then return true, "You're already using " .. name .. "." end
    Switch(name)
    return true, "Now using " .. name .. "."
end

local function Create(text, copy)
    local why = Blocked()
    if why then return false, why end
    local name, problem = CleanName(text)
    if not name then return false, problem end
    if Profiles()[name] then return false, name .. " already exists." end
    local from, profile = Profiles()[active], { joins = {} }
    for _, key in ipairs(ns.BAR_KEYS) do
        local list = {}
        if copy then
            for i, spell in ipairs(from[key]) do list[i] = spell end
        end
        profile[key] = list
    end
    if copy then
        for key, joins in pairs(from.joins or {}) do
            profile.joins[key] = {}
            for name in pairs(joins) do profile.joins[key][name] = true end
        end
    end
    Profiles()[name] = profile
    Switch(name)
    return true, (copy and "Copied your lists to " or "Made ") .. name .. ", and switched to it."
end

-- A new, empty profile.
function ns.NewProfile(text)
    return Create(text, false)
end

-- A new profile starting with this character's lists.
function ns.CopyProfile(text)
    return Create(text, true)
end

-- The profile chosen for every character, if any.
function ns.EveryoneProfile()
    return db and Everyone()
end

-- This character's profile for every character, and for any made later.
-- Each one only shows its own class's spells from it.
function ns.UseOnAll()
    local why = Blocked()
    if why then return false, why end
    local chars = Chars()
    for guid in pairs(chars) do chars[guid] = active end
    db.everyone = active
    return true, "All your characters use " .. active .. " now, and new ones will too."
end

-- Whether every character known uses this profile, as chosen for them all.
function ns.OnAll(name)
    if name == nil or name ~= ns.EveryoneProfile() then return false end
    for _, used in pairs(Chars()) do
        if used ~= name then return false end
    end
    return true
end

-- Gives this character's profile a new name, for every character using it.
local function Rename(name)
    local profiles, chars = Profiles(), Chars()
    profiles[name], profiles[active] = profiles[active], nil
    for guid, used in pairs(chars) do
        if used == active then chars[guid] = name end
    end
    if db.everyone == active then db.everyone = name end
    active = name
end

function ns.RenameProfile(text)
    local why = Blocked()
    if why then return false, why end
    local name, problem = CleanName(text)
    if not name then return false, problem end
    if name == active then return true, "That's already its name." end
    if Profiles()[name] then return false, name .. " already exists." end
    Rename(name)
    return true, "Renamed to " .. name .. "."
end

-- A profile made before the game knew the character's name ("Unknown
-- (Paladin)") takes the name, while it's still that character's alone.
function ns.NameUnknownProfile()
    local own = OwnName()
    if not (active and own) or active == own or Profiles()[own] then return false end
    local prefix = UNKNOWN .. " ("
    if active:sub(1, #prefix) ~= prefix or ns.ProfileUsers(active) ~= 1 then return false end
    Rename(own)
    return true
end

-- Whether a profile can be deleted now: true, its name and how many other
-- characters use it, or false and why. The exact name is looked up first, so
-- a profile named before names were kept short can still go.
function ns.CanDeleteProfile(text)
    local why = Blocked()
    if why then return false, why end
    local name = type(text) == "string" and Profiles()[text] and text
    if not name then
        local problem
        name, problem = CleanName(text)
        if not name then return false, problem end
        if not Profiles()[name] then return false, ('No profile is called "%s".'):format(name) end
    end
    local me, others = PlayerGUID(), 0
    for guid, used in pairs(Chars()) do
        if used == name and guid ~= me then others = others + 1 end
    end
    return true, name, others
end

-- Deletes the named profile. Other characters that used it, even ones since
-- deleted, are let go of: at their next login they get a profile as a new
-- character would. Deleting your own leaves you on a new, empty profile of
-- your own.
function ns.DeleteProfile(text)
    local ok, name = ns.CanDeleteProfile(text)
    if not ok then return false, name end
    local profiles, chars = Profiles(), Chars()
    profiles[name] = nil
    for guid, used in pairs(chars) do
        if used == name then chars[guid] = nil end
    end
    if db.everyone == name then db.everyone = nil end
    if name == active then
        local fresh = FreeName(OwnName(true))
        profiles[fresh] = Lists({})
        Switch(fresh)
        return true, "Deleted " .. name .. ". You're now on " .. fresh .. "."
    end
    ns.PruneCustom()
    return true, "Deleted " .. name .. "."
end

-- Bars ---------------------------------------------------------------------------

-- A bar's spells aren't stored with it: reading them gives this character's list.
local SPELLS = {}
for _, key in ipairs(ns.BAR_KEYS) do
    SPELLS[key] = { __index = function(_, field)
        if field == "spells" then return ns.ActiveList(key) end
    end }
end

-- A bar's settings, repaired in place if anything is missing or invalid. Its
-- spells come from this character's profile.
function ns.BarData(key)
    if not db or not ns.BAR_NAMES[key] then return nil end
    if type(db.bars) ~= "table" then db.bars = {} end
    local bar = db.bars[key]
    if type(bar) ~= "table" then
        bar = {}
        db.bars[key] = bar
    end
    if getmetatable(bar) ~= SPELLS[key] then setmetatable(bar, SPELLS[key]) end
    -- Lists saved before profiles, kept until the character is known.
    local old = rawget(bar, "spells")
    if old ~= nil then
        if type(old) == "table" then Repair(old) else rawset(bar, "spells", nil) end
    end
    bar.size = Limit(bar.size, ns.BAR_LIMITS.size)
    bar.spacing = Limit(bar.spacing, ns.BAR_LIMITS.spacing)
    -- Bars set to hide when ready before Dim joined it still hide.
    if not ns.WHEN_READY_NAMES[bar.whenReady] then
        bar.whenReady = bar.hideReady == true and "hide" or "show"
    end
    bar.hideReady = nil
    -- Bars set to "only in combat" before this choice existed hide.
    if not ns.OUT_OF_COMBAT_NAMES[bar.outOfCombat] then
        bar.outOfCombat = bar.combatOnly == true and "hide" or "show"
    end
    bar.combatOnly = nil
    bar.showMissing = bar.showMissing == true
    bar.showNames = bar.showNames == true
    bar.showTimer = bar.showTimer ~= false -- countdown numbers, on unless turned off
    bar.perRow = Limit(bar.perRow, ns.BAR_LIMITS.perRow)
    if not ns.GROW_NAMES[bar.grow] then bar.grow = "centre" end
    if not ns.WRAP_NAMES[bar.wrap] then bar.wrap = "down" end
    if not POINTS[bar.point] then bar.point = nil end
    if not (Finite(bar.x) and Finite(bar.y) and math.abs(bar.x) < 4000 and math.abs(bar.y) < 4000) then
        bar.x, bar.y, bar.point = nil, nil, nil
    end
    return bar
end

-- A bar's icon size on screen: its own size (data, from ns.BarData) times the
-- size for all bars, so a bigger bar stays bigger. Never under the smallest
-- size a bar can have, where the countdown and keybind still fit; at most 96
-- (a 64 bar at 150). At 100 it's the bar's own size.
function ns.IconSize(data)
    local size = math.floor(data.size * ns.Get("barScale") / 100 + .5)
    return math.max(ns.BAR_LIMITS.size[1], size)
end

-- Layouts: your bars stacked around Blizzard's Personal Resource Display.
-- Which bars sit above it and below it (each top to bottom) and beside it,
-- each bar once, and whether the layout holds them now. Repaired in place.
function ns.LayoutData()
    if not db then return nil end
    if type(db.layout) ~= "table" then db.layout = {} end
    local layout = db.layout
    layout.on = layout.on == true
    if type(layout.preset) ~= "string" then layout.preset = nil end
    -- The preset last picked, which Reset goes back to.
    if type(layout.base) ~= "string" then layout.base = nil end
    layout.gap = Limit(layout.gap, ns.ROW_GAP)
    layout.spacing = Limit(layout.spacing, ns.ICON_GAP)
    -- Bars taken out: they keep their row and spells, but don't show.
    if type(layout.hidden) ~= "table" then layout.hidden = {} end
    for key, out in pairs(layout.hidden) do
        if not ns.BAR_NAMES[key] or out ~= true then layout.hidden[key] = nil end
    end
    local seen = {}
    local function Take(key)
        if ns.BAR_NAMES[key] and not seen[key] then
            seen[key] = true
            return key
        end
    end
    for _, place in ipairs({ "above", "below" }) do
        local list = {}
        for _, key in ipairs(type(layout[place]) == "table" and layout[place] or {}) do
            list[#list + 1] = Take(key)
        end
        layout[place] = list
    end
    layout.left, layout.right = Take(layout.left), Take(layout.right)
    -- A bar missing from every place goes under the display.
    for _, key in ipairs(ns.BAR_KEYS) do
        if not seen[key] then layout.below[#layout.below + 1] = Take(key) end
    end
    return layout
end

-- Blizzard's Tracked Bars coloured one by one: the bar's spell ID -> a bar
-- colour. Bars not listed use the colour for all bars.
function ns.BarColours()
    if not db then return {} end
    if type(db.barColours) ~= "table" then db.barColours = {} end
    for id, key in pairs(db.barColours) do
        if not (Finite(id) and id > 0 and ns.Valid("barColour", key)) then db.barColours[id] = nil end
    end
    return db.barColours
end

-- Spells added by name or ID that aren't in your spellbook: name -> spell IDs.
function ns.CustomSpells()
    if not db then return {} end
    if type(db.custom) ~= "table" then db.custom = {} end
    for name, ids in pairs(db.custom) do
        local valid = type(name) == "string" and name ~= "" and type(ids) == "table" and #ids > 0
        for _, id in ipairs(valid and ids or {}) do
            if not Finite(id) then valid = false end
        end
        if not valid then db.custom[name] = nil end
    end
    return db.custom
end

function ns.AddCustom(name, ids)
    ns.CustomSpells()[name] = ids
end

-- Forgets added spells once they're on no bar in any profile.
function ns.PruneCustom()
    if not db then return end
    local custom, used = ns.CustomSpells(), {}
    local function Mark(lists)
        for _, key in ipairs(ns.BAR_KEYS) do
            for _, spell in ipairs(type(lists[key]) == "table" and lists[key] or {}) do used[spell] = true end
        end
    end
    for _, profile in pairs(Profiles()) do
        if type(profile) == "table" then Mark(profile) end
    end
    Mark(scratch)
    for _, key in ipairs(ns.BAR_KEYS) do
        local bar = type(db.bars) == "table" and db.bars[key]
        local old = type(bar) == "table" and rawget(bar, "spells")
        if type(old) == "table" then Mark({ [key] = old }) end
    end
    for name in pairs(custom) do
        if not used[name] then custom[name] = nil end
    end
end

-- Changes ---------------------------------------------------------------------------
-- Everything lives in the saved settings, which the game writes at logout and
-- on a reload; a change only needs the window redrawn.

function ns.Set(key, value)
    if not db then return end
    db[key] = value
    if ns.window and ns.window:IsShown() then ns.window:Refresh() end
end

-- A Tracked Bar's own colour, or nil to go back to the colour for all bars.
function ns.SetBarColour(spellID, key)
    if not db or not (Finite(spellID) and spellID > 0) then return end
    ns.BarColours()[spellID] = key ~= nil and ns.Valid("barColour", key) and key or nil
    if ns.window and ns.window:IsShown() then ns.window:Refresh() end
end

-- What's new: the version whose notes were last shown, or passed over on a
-- first install.
function ns.NotesSeen()
    return db and type(db.notesSeen) == "string" and db.notesSeen or nil
end

function ns.SetNotesSeen(version)
    if not db then return end
    db.notesSeen = version
end

function ns.NeedsReload()
    for key in pairs(ns.RELOAD) do
        if ns.Get(key) ~= ns.loaded[key] then return true end
    end
    return false
end

function ns.CooldownManagerOn()
    if not (C_CVar and C_CVar.GetCVarBool) then return true end
    return C_CVar.GetCVarBool("cooldownViewerEnabled") ~= false
end

-- Blizzard's Personal Resource Display, Options > Combat.
function ns.PersonalDisplayOn()
    if not (C_CVar and C_CVar.GetCVarBool) then return true end
    return C_CVar.GetCVarBool("nameplateShowSelf") ~= false
end

-- Switches one of Blizzard's own settings on, outside combat: true when it's
-- on afterwards, or false and why not.
function ns.TurnOn(cvar)
    if InCombatLockdown() then return false, "Finish combat first." end
    if not (C_CVar and C_CVar.SetCVar and C_CVar.GetCVarBool) then return false end
    pcall(C_CVar.SetCVar, cvar, "1")
    return C_CVar.GetCVarBool(cvar) == true
end

-- And off again, when you ask: true when it's off afterwards.
function ns.TurnOff(cvar)
    if InCombatLockdown() then return false, "Finish combat first." end
    if not (C_CVar and C_CVar.SetCVar and C_CVar.GetCVarBool) then return false end
    pcall(C_CVar.SetCVar, cvar, "0")
    return C_CVar.GetCVarBool(cvar) == false
end

-- Escape closes the /ccm window and What's new. The key is borrowed only while
-- one is up and handed back as a fight begins, since bindings cannot change in
-- combat; this keeps the addon out of the game's own Escape handling.
local escButton

-- On screen: a window left open while the interface is hidden (Alt+Z)
-- doesn't count, so Escape goes back to the game and brings the interface
-- back. The window takes the key again as it reappears.
local function Shown(frame)
    return frame ~= nil and frame:IsVisible()
end

function ns.EscUpdate()
    if not escButton or InCombatLockdown() then return end
    ClearOverrideBindings(escButton)
    if Shown(ns.window) or Shown(ns.notes) then
        SetOverrideBindingClick(escButton, true, "ESCAPE", escButton:GetName())
    end
end

local function BuildEscape()
    escButton = CreateFrame("Button", "FECMEscButton", UIParent)
    -- What's new sits over the window, so it closes first; then the tour ends,
    -- leaving the window open.
    escButton:SetScript("OnClick", function()
        if Shown(ns.notes) then
            ns.notes:Hide()
        elseif ns.Tour and ns.Tour:Active() then
            ns.Tour:Stop()
        elseif ns.window then
            ns.window:Hide()
        end
        -- Checked again here too: hiding a frame that's already off screen
        -- runs no OnHide, so the key would otherwise stay borrowed.
        ns.EscUpdate()
    end)
    escButton:RegisterEvent("PLAYER_REGEN_DISABLED")
    escButton:RegisterEvent("PLAYER_REGEN_ENABLED")
    escButton:SetScript("OnEvent", function(self, event)
        if event == "PLAYER_REGEN_DISABLED" then
            ClearOverrideBindings(self)
        else
            ns.EscUpdate()
        end
    end)
end

-- Options > AddOns ------------------------------------------------------------------

local function BuildOptionsEntry()
    if not (Settings and Settings.RegisterCanvasLayoutCategory and Settings.RegisterAddOnCategory) then return end
    local canvas = CreateFrame("Frame")
    local title = canvas:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    title:SetPoint("TOPLEFT", 16, -16)
    title:SetText(ns.TITLE)
    local about = canvas:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    about:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -10)
    about:SetWidth(560)
    about:SetJustifyH("LEFT")
    about:SetText("A cleaner look for Blizzard's Cooldown Manager and Personal Resource Display, plus cooldown, buff and cast bars of your own. Type /ccm, click the minimap button, or click below, for the settings.")
    local open = CreateFrame("Button", nil, canvas, "UIPanelButtonTemplate")
    open:SetSize(160, 24)
    open:SetPoint("TOPLEFT", about, "BOTTOMLEFT", 0, -14)
    open:SetText("Open settings")
    open:SetScript("OnClick", function() if ns.ShowWindow then ns.ShowWindow() end end)
    local category = Settings.RegisterCanvasLayoutCategory(canvas, ns.TITLE)
    Settings.RegisterAddOnCategory(category)
end

-- Startup -------------------------------------------------------------------------

local loader = CreateFrame("Frame")
loader:RegisterEvent("ADDON_LOADED")
loader:RegisterEvent("PLAYER_LOGIN")

local function Load()
    ForeverEnhancedCooldownManagerDB = type(ForeverEnhancedCooldownManagerDB) == "table" and ForeverEnhancedCooldownManagerDB or {}
    db = ForeverEnhancedCooldownManagerDB
    -- An empty settings file: the addon's first login on this account.
    ns.firstInstall = next(db) == nil
    db.probe = nil -- results of a development check the released addon doesn't have
    db.session = nil -- a login count earlier builds kept
    -- Everything saved is checked and repaired now, before anything uses it.
    RepairProfiles()
    for _, key in ipairs(ns.BAR_KEYS) do ns.BarData(key) end
    ns.LayoutData()
    ns.CustomSpells()
    ns.BarColours()
    ns.ResolveProfile()
    for key in pairs(ns.RELOAD) do ns.loaded[key] = ns.Get(key) end

    SLASH_FECM1 = "/ccm"
    SLASH_FECM2 = "/fecm"
    SlashCmdList.FECM = function(msg)
        msg = type(msg) == "string" and msg or ""
        if msg:match("^%s*new%s*$") and ns.ShowNotes then
            ns.ShowNotes()
        elseif msg:match("^%s*tour%s*$") and ns.Tour then
            ns.Tour:Start()
        elseif msg:match("^%s*discord%s*$") and ns.ShowDiscord then
            ns.ShowDiscord()
        elseif ns.Toggle then
            ns.Toggle()
        end
    end
    BuildEscape()
    BuildOptionsEntry()

    if ns.loaded.skin and ns.Skin then ns.Skin:Start() end
    if ns.Keybinds then ns.Keybinds:Start() end
    if ns.Resource then ns.Resource:Start() end
    if ns.CastBar then ns.CastBar:Start() end
    if ns.Bars then ns.Bars:Start() end
    if ns.Layout then ns.Layout:Start() end
    if ns.MinimapButton then ns.MinimapButton:Start() end
    if ns.Notes then ns.Notes:Start() end
end

loader:SetScript("OnEvent", function(self, event, name)
    if event == "ADDON_LOADED" then
        if name ~= ADDON then return end
        self:UnregisterEvent("ADDON_LOADED")
        Load()
    elseif event == "PLAYER_LOGIN" and db then
        self:UnregisterEvent("PLAYER_LOGIN")
        -- In case the character, or its name, wasn't known yet when the
        -- settings loaded.
        if not active and ns.ResolveProfile(true) and ns.Bars then ns.Bars:Rebuild() end
        if ns.NameUnknownProfile() and ns.window and ns.window:IsShown() then ns.window:Refresh() end
    end
end)
