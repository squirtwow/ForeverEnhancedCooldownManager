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
    accent = "purple", -- the /ccm window's accent colour (orange until 1.4.4; purple keeps it apart from other addons)
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
    -- Raid Timers: Blizzard's own raid and dungeon timers restyled, each part on its own.
    pullTimer = false, -- the pull and start countdown in your bar design
    pullColour = "default", -- its bar: Blizzard's red, or a bar colour
    pullNumbers = "gold", -- its big numbers: Blizzard's gold, white, or the bar's colour
    raidWarnings = false, -- raid warnings and boss emotes in a font of your choice
    warningFont = "friz",
    warningOutline = "outline", -- none, outline or thick
    warningShadow = true,
    warningColour = "default", -- raid warnings: Blizzard's colour, or a text colour
    emoteColour = "default", -- boss emotes and whispers, the same way
    bossCasts = false, -- the boss frames' cast bars in your bar design
    bossColour = "default", -- their colour: gold (green channelling), or a bar colour
    -- Raid Timers' sizes, in percent of Blizzard's own: each part's, times all of them together.
    pullBarSize = 100, -- the countdown's bar
    pullNumberSize = 100, -- its big numbers
    warningSize = 100, -- raid warning text
    emoteSize = 100, -- boss emote text
    raidSize = 100, -- all four together
    -- Cooldown pulse (More): a big icon in the middle of the screen as a cooldown comes back.
    -- Each cooldown pulses Quick or Long; each style has its own size, time and sound.
    pulse = false, -- on or off
    pulseSize = 272, -- Quick: the icon's size, in the game's units (about a third of the screen's height)
    pulseTime = 10, -- how long each pulse lasts, in tenths of a second
    pulseSound = "none", -- none, chime or bell
    pulseLongSize = 400, -- Long: the same three
    pulseLongTime = 25,
    pulseLongSound = "none",
    pulseMaster = false, -- both styles: the sound at your Master volume, heard with Sound Effects down or off
    pulseSeeThrough = 80, -- both styles: how much of the game shows through it, in percent (see Pulse.lua's Opacity)
    pulseGrow = 135, -- how big it gets by the end, in percent of its size
    pulseBorder = "thin", -- a dark edge round it: none, thin or thick
    pulseShadow = true, -- and a soft shadow
    pulseItems = true, -- your trinkets, and items on your Cooldowns and Utility bars, are listed too
    pulseX = 0, -- where it sits: from the middle of the screen
    pulseY = 0,
    iconBorder = "off", -- a thin border round each icon ("icon") or whole bars ("bar")
    iconShadow = "off", -- and a soft shadow, the same way
    readyGlow = "proc", -- a ready reactive ability on your bars: Blizzard's proc glow, or a plain gold edge ("edge")
    keybinds = false, -- each Cooldowns/Utility icon's key, from your action bars (Look page)
    keybindPosition = "BOTTOM", -- where on the icon: BOTTOM, TOPLEFT, TOP or TOPRIGHT
    keybindSize = 100, -- its size, as a share of the automatic size that follows the icon
    layoutPreview = true, -- the Layout page draws your icons with the Look page's border, shadow and keybinds
    barScale = 100, -- every bar's icons together, as a share of each bar's own size (the Layout page's All bars)
    growArrows = false, -- while your bars are arranged (unlocked or in Edit Mode), an arrow on each for the way it grows
    minimap = true, -- the minimap button
    minimapAngle = 225, -- where it sits round the minimap: degrees anticlockwise from the right
    minimapFree = false, -- free-floating: anywhere on the screen, not on the minimap's edge
    minimapX = 0, -- where it sits while free-floating: from the middle of the screen
    minimapY = 0,
    talentSwitch = false, -- another talent tree taking the lead in points switches to its role's profile (profile menu)
}
ns.DECOR_KEYS = { "off", "icon", "bar" }
ns.DECOR_NAMES = { off = "Off", icon = "Each icon", bar = "Whole bar" }
ns.READY_GLOW_KEYS = { "proc", "edge" }
ns.READY_GLOW_NAMES = { proc = "Proc glow", edge = "Gold edge" }
ns.KEYBIND_POSITIONS = { "BOTTOM", "TOPLEFT", "TOP", "TOPRIGHT" }
ns.KEYBIND_POSITION_NAMES = { BOTTOM = "Bottom", TOPLEFT = "Top left", TOP = "Top", TOPRIGHT = "Top right" }
-- Number settings, each within its limits: min, max, default.
ns.CAST_HEIGHT = { 10, 32, 18 }
ns.MINIMAP_ANGLE = { 0, 359, 225 }
ns.MINIMAP_PLACE = { -4000, 4000, 0 }
ns.KEYBIND_SIZE = { 50, 150, 100 } -- min, max, default (percent)
ns.BAR_SCALE = { 50, 150, 100 } -- min, max, default (percent)
ns.RAID_SIZE = { 50, 200, 100 } -- each Raid Timers size (percent)
ns.RAID_SIZE_ALL = { 50, 150, 100 } -- all of them together, so the biggest is three times Blizzard's
-- Cooldown pulse.
ns.PULSE_SIZE = { 64, 512, 272 }
ns.PULSE_TIME = { 3, 20, 10 } -- tenths of a second: 0.3 to 2 seconds
ns.PULSE_LONG_SIZE = { 64, 512, 400 }
ns.PULSE_LONG_TIME = { 3, 50, 25 } -- 0.3 to 5 seconds
ns.PULSE_SEE_THROUGH = { 0, 90, 80 }
ns.PULSE_GROW = { 100, 160, 135 }
ns.PULSE_PLACE = { -4000, 4000, 0 }
local NUMBERS = { castHeight = ns.CAST_HEIGHT, minimapAngle = ns.MINIMAP_ANGLE, keybindSize = ns.KEYBIND_SIZE,
    barScale = ns.BAR_SCALE, pullBarSize = ns.RAID_SIZE, pullNumberSize = ns.RAID_SIZE, warningSize = ns.RAID_SIZE,
    emoteSize = ns.RAID_SIZE, raidSize = ns.RAID_SIZE_ALL, pulseSize = ns.PULSE_SIZE, pulseTime = ns.PULSE_TIME,
    pulseLongSize = ns.PULSE_LONG_SIZE, pulseLongTime = ns.PULSE_LONG_TIME,
    pulseSeeThrough = ns.PULSE_SEE_THROUGH, pulseGrow = ns.PULSE_GROW,
    pulseX = ns.PULSE_PLACE, pulseY = ns.PULSE_PLACE, minimapX = ns.MINIMAP_PLACE, minimapY = ns.MINIMAP_PLACE }
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
-- Raid Timers: the countdown's big numbers, the raid warnings' outline and their
-- text colours (your class colour last; the colours themselves are in RaidTimers.lua).
ns.NUMBER_KEYS = { "gold", "white", "bar" }
ns.NUMBER_NAMES = { gold = "Gold", white = "White", bar = "Bar colour" }
ns.OUTLINE_KEYS = { "none", "outline", "thick" }
ns.OUTLINE_NAMES = { none = "None", outline = "Outline", thick = "Thick" }
ns.TEXT_COLOUR_KEYS = { "white", "gold", "orange", "red", "purple", "class" }
ns.TEXT_COLOUR_NAMES = { white = "White", gold = "Gold", orange = "Orange", red = "Red", purple = "Purple", class = "Class" }
-- Cooldown pulse: the edge round it, the sound with it, and its two styles.
ns.PULSE_BORDER_KEYS = { "none", "thin", "thick" }
ns.PULSE_BORDER_NAMES = { none = "None", thin = "Thin", thick = "Thick" }
ns.PULSE_SOUND_KEYS = { "none", "chime", "bell", "trill", "shimmerBell", "magicChimes", "shimmer", "zippy", "synth", "pipe", "brass",
    "warhorn", "fanfare", "gold", "jackpot", "anvil" }
ns.PULSE_SOUND_NAMES = { none = "None", chime = "Chime", bell = "Bell", trill = "Bell trill", shimmerBell = "Shimmer bell",
    magicChimes = "Magic chimes", shimmer = "Shimmer", zippy = "Zippy magic", synth = "Synth", pipe = "Pitch pipe", brass = "Brass",
    warhorn = "War horn", fanfare = "Fanfare", gold = "Gold", jackpot = "Jackpot bell", anvil = "Anvil" }
ns.PULSE_STYLE_KEYS = { "quick", "long" }
ns.PULSE_STYLE_NAMES = { quick = "Quick", long = "Long" }
local CHOICES = { accent = {}, barStyle = {}, barColour = {}, prdHealth = { default = true }, prdPower = { default = true },
    prdComboColour = { default = true }, castColour = { default = true }, swingColour = { default = true },
    iconBorder = { off = true, icon = true, bar = true }, iconShadow = { off = true, icon = true, bar = true },
    keybindPosition = {}, font = {}, barTexture = {}, readyGlow = {} }
for _, key in ipairs(ns.READY_GLOW_KEYS) do CHOICES.readyGlow[key] = true end
for _, key in ipairs(ns.ACCENT_KEYS) do CHOICES.accent[key] = true end
for _, key in ipairs(ns.KEYBIND_POSITIONS) do CHOICES.keybindPosition[key] = true end
for _, key in ipairs(ns.BAR_STYLE_KEYS) do CHOICES.barStyle[key] = true end
for _, key in ipairs(ns.FONT_KEYS) do CHOICES.font[key] = true end
for _, key in ipairs(ns.BAR_TEXTURE_KEYS) do CHOICES.barTexture[key] = true end
for _, key in ipairs(ns.BAR_COLOUR_KEYS) do
    CHOICES.barColour[key], CHOICES.prdHealth[key], CHOICES.prdPower[key] = true, true, true
    CHOICES.prdComboColour[key], CHOICES.castColour[key], CHOICES.swingColour[key] = true, true, true
end
-- Raid Timers' choices.
for _, key in ipairs({ "pullColour", "bossColour", "warningColour", "emoteColour" }) do CHOICES[key] = { default = true } end
CHOICES.pullNumbers, CHOICES.warningFont, CHOICES.warningOutline = {}, {}, {}
for _, key in ipairs(ns.BAR_COLOUR_KEYS) do CHOICES.pullColour[key], CHOICES.bossColour[key] = true, true end
for _, key in ipairs(ns.TEXT_COLOUR_KEYS) do CHOICES.warningColour[key], CHOICES.emoteColour[key] = true, true end
for _, key in ipairs(ns.NUMBER_KEYS) do CHOICES.pullNumbers[key] = true end
for _, key in ipairs(ns.FONT_KEYS) do CHOICES.warningFont[key] = true end
for _, key in ipairs(ns.OUTLINE_KEYS) do CHOICES.warningOutline[key] = true end
CHOICES.pulseBorder, CHOICES.pulseSound, CHOICES.pulseLongSound = {}, {}, {}
for _, key in ipairs(ns.PULSE_BORDER_KEYS) do CHOICES.pulseBorder[key] = true end
for _, key in ipairs(ns.PULSE_SOUND_KEYS) do CHOICES.pulseSound[key], CHOICES.pulseLongSound[key] = true, true end

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

-- What a shared profile carries of the look (ProfileShare.lua): how your
-- bars, the restyled bars, your cast bar, Raid Timers and the Cooldown pulse
-- look, and where they sit. Never a tick that switches a part on or off (your
-- bars, the look on Blizzard's bars or display, the cast bar, swing timer,
-- combo points, keybinds, the pulse, each Raid Timers part), nor the window's
-- own (its accent, lists, preview, grow arrows and the minimap button).
ns.SHARE_LOOK = { "barStyle", "barColour", "barTexture", "font", "iconBorder", "iconShadow", "readyGlow",
    "keybindPosition", "keybindSize", "barScale", "prdHideRepeat", "prdHealth", "prdPower", "prdMatch", "prdComboColour",
    "castColour", "castHeight", "castIcon", "castName", "castTime", "swingColour",
    "pullColour", "pullNumbers", "warningFont", "warningOutline", "warningShadow", "warningColour", "emoteColour", "bossColour",
    "pullBarSize", "pullNumberSize", "warningSize", "emoteSize", "raidSize",
    "pulseSize", "pulseTime", "pulseSound", "pulseLongSize", "pulseLongTime", "pulseLongSound", "pulseMaster",
    "pulseSeeThrough", "pulseGrow", "pulseBorder", "pulseShadow", "pulseItems", "pulseX", "pulseY" }

-- Bars: each bar lists spells by name, so the highest known rank is
-- always the one shown.
ns.BAR_KEYS = { "cd", "util", "buff", "debuff" }
ns.BAR_NAMES = { cd = "Cooldowns", util = "Utility", buff = "Buffs", debuff = "Debuffs" }
-- The bars fed by Blizzard's secure aura container, and what each watches.
ns.AURA_BARS = {
    buff = { unit = "player", filter = "HELPFUL", word = "buff" },
    debuff = { unit = "target", filter = "HARMFUL", mine = true, word = "debuff" },
}ns.BAR_LIMITS = { size = { 20, 64, 36 }, spacing = { 0, 20, 4 }, perRow = { 1, 20, 20 } } -- min, max, default
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
ns.BAR_POINTS = POINTS -- for checking a shared profile's (ProfileShare.lua)
-- A bar's settings a shared profile carries (its spells are in the profile).
ns.SHARE_BAR_FIELDS = { "size", "spacing", "perRow", "whenReady", "outOfCombat", "showMissing", "showNames", "showTimer",
    "showAuras", "selfDebuffs", "grow", "wrap", "point", "x", "y" }
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
-- The spell lists live in profiles, the bars' and the Cooldown pulse's
-- ticks; everything else (look, sizes, places, how the pulse looks) is
-- shared. Each character, told apart by its GUID since two can share a name,
-- uses one profile, at first its own "Name (Class) - Realm". Several
-- characters can share one, and profiles never change in combat.
ns.PROFILE_MAX = 48 -- longest profile name
-- Roles: a profile for each role you play, for your class (Roles, below).
ns.ROLE_KEYS = { "tank", "healer", "damage" }
ns.ROLE_NAMES = { tank = "Tank", healer = "Healer", damage = "Damage" }
-- A talent tree's role (Talents, below): one of those, or None, so nothing
-- switches when it takes the lead. None is no role of its own: no profile.
ns.TREE_ROLE_KEYS = { "tank", "healer", "damage", "none" }
ns.TREE_ROLE_NAMES = { tank = "Tank", healer = "Healer", damage = "Damage", none = "None" }

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

-- The Cooldown pulse's two lists in a profile, and the one value each keeps:
-- what's ticked (spell names and item keys -> true), and what's switched
-- to Long (-> "long"; the rest are Quick).
local PULSE_LISTS = { pulsePick = true, pulseStyle = "long" }

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
    for field, keep in pairs(PULSE_LISTS) do
        if type(profile[field]) ~= "table" then profile[field] = {} end
        for key, value in pairs(profile[field]) do
            if type(key) ~= "string" or key == "" or value ~= keep then profile[field][key] = nil end
        end
    end
    -- Positions per profile: its spots and sizes, repaired as they're used.
    if profile.place ~= nil and type(profile.place) ~= "table" then profile.place = nil end
    return profile
end

-- The profile chosen for every character, new ones included, if there is one.
local function Everyone()
    local name = db and db.everyone
    if type(name) == "string" and Profiles()[name] then return name end
end

-- A table of tables saved by a text key (a class, a character's GUID): the
-- rest let go, then each inner table's entries kept only as keep(key, value)
-- says. Nil if there's nothing.
local function Keyed(saved, keep)
    if type(saved) ~= "table" then return nil end
    for outer, inner in pairs(saved) do
        if type(outer) ~= "string" or type(inner) ~= "table" then
            saved[outer] = nil
        else
            for key, value in pairs(inner) do
                if not keep(key, value) then inner[key] = nil end
            end
        end
    end
    return saved
end

-- Role links (class -> role -> profile name; each to a profile that's
-- there, each profile for one role), each class's talent trees set to a role
-- or None (class -> the tree's group ID -> role), and the main tree each character
-- was last seen with (GUID -> the tree's ID; none until one leads), kept
-- only while Switch with my talents is on.
local function RepairRoles(profiles)
    db.roles = Keyed(db.roles, function(role, name)
        return ns.ROLE_NAMES[role] ~= nil and type(name) == "string" and profiles[name] ~= nil
    end)
    for _, links in pairs(db.roles or {}) do
        local taken = {}
        for _, role in ipairs(ns.ROLE_KEYS) do
            if links[role] and taken[links[role]] then links[role] = nil end
            if links[role] then taken[links[role]] = true end
        end
    end
    db.treeRoles = Keyed(db.treeRoles, function(id, role)
        return Finite(id) and id > 0 and ns.TREE_ROLE_NAMES[role] ~= nil
    end)
    local mains = db.mainTrees
    if db.talentSwitch ~= true or type(mains) ~= "table" then
        db.mainTrees = nil
    else
        for guid, id in pairs(mains) do
            if type(guid) ~= "string" or not (Finite(id) and id > 0) then mains[guid] = nil end
        end
    end
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
    RepairRoles(profiles)
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

-- "Name Surname (Class) - Realm", cut to fit a profile name: Forever gives
-- the surname apart, and it tells two characters of one first name apart. On
-- a character's very first login the game may not know its name yet: nil
-- then, unless a name is needed now anyway.
local function OwnName(anyway)
    local name, surname
    if UnitName then name, surname = UnitName("player") end
    if type(name) ~= "string" or name == "" or name == UNKNOWN then
        if not anyway then return nil end
        name = UNKNOWN
    elseif not (issecretvalue and issecretvalue(surname)) and type(surname) == "string" and surname ~= "" then
        name = name .. " " .. surname
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

-- Positions per profile (below): defined after the copy helpers they use.
local SavePlace, LoadPlace, PlaceForCopy, PlaceAtLogin

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
    -- The Cooldown pulse's test builds kept its ticks for every character:
    -- the first profile to load takes them.
    for field, keep in pairs(PULSE_LISTS) do
        if type(db[field]) == "table" then
            for key, value in pairs(db[field]) do
                if type(key) == "string" and key ~= "" and value == keep then profiles[name][field][key] = value end
            end
        end
        db[field] = nil
    end
    active = name
    PlaceAtLogin()
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

-- Every switch clears what the talents last said (Talents, below), so the
-- menu never shows a note about a profile you've since left; a switch the
-- talents make says it again after. With Positions per profile on, the
-- profile you leave keeps where your bars are and how big, and the one you
-- switch to brings its own.
local function Switch(name)
    if db.placePerProfile == true then
        SavePlace()
        if LoadPlace(name) and ns.Layout then ns.Layout.undo, ns.Layout.moved = nil, nil end
    end
    Chars()[PlayerGUID()] = name
    active = name
    ns.talentNote = nil
    if ns.Bars and ns.Bars.started then ns.Bars:Changed() end
    if ns.Pulse and ns.Pulse.started then ns.Pulse:Apply() end
end

-- Role links follow a profile renamed (to its new name) and let go of one
-- deleted (to nil), for every class.
local function Relink(from, to)
    for _, links in pairs(type(db.roles) == "table" and db.roles or {}) do
        for role, name in pairs(links) do
            if name == from then links[role] = to end
        end
    end
end

function ns.UseProfile(name)
    local why = Blocked()
    if why then return false, why end
    if not Profiles()[name] then return false, ('No profile is called "%s".'):format(tostring(name)) end
    if name == active then return true, "You're already using " .. name .. "." end
    Switch(name)
    return true, "Now using " .. name .. "."
end

-- A copy of a profile's lists: its bars', their joins and the Cooldown
-- pulse's ticks, sharing nothing with it.
local function Duplicate(from)
    local profile = { joins = {} }
    for _, key in ipairs(ns.BAR_KEYS) do
        local list = {}
        for i, spell in ipairs(type(from[key]) == "table" and from[key] or {}) do list[i] = spell end
        profile[key] = list
    end
    for key, joins in pairs(type(from.joins) == "table" and from.joins or {}) do
        profile.joins[key] = {}
        for name in pairs(joins) do profile.joins[key][name] = true end
    end
    for field in pairs(PULSE_LISTS) do
        profile[field] = {}
        for key, value in pairs(type(from[field]) == "table" and from[field] or {}) do profile[field][key] = value end
    end
    profile.place = PlaceForCopy(from)
    return profile
end

local function Create(text, copy)
    local why = Blocked()
    if why then return false, why end
    local name, problem = CleanName(text)
    if not name then return false, problem end
    if Profiles()[name] then return false, name .. " already exists." end
    Profiles()[name] = copy and Duplicate(Profiles()[active]) or Lists({})
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
    Relink(active, name)
    if db.placeOwner == active then db.placeOwner = name end
    active = name
    ns.talentNote = nil -- it may name the old name
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
    Relink(name, nil)
    -- The spots on screen are that profile's: they stay, for whichever
    -- profile you're on next (nothing saves them back into the deleted one).
    if db.placeOwner == name then db.placeOwner = nil end
    if name == active then
        local fresh = FreeName(OwnName(true))
        profiles[fresh] = Lists({})
        Switch(fresh)
        return true, "Deleted " .. name .. ". You're now on " .. fresh .. "."
    end
    ns.PruneCustom()
    return true, "Deleted " .. name .. "."
end

-- A copy of a list, or of a table one level deep; empty for anything else.
local function CopyList(list)
    local copy = {}
    for i, value in ipairs(type(list) == "table" and list or {}) do copy[i] = value end
    return copy
end

local function CopyTable(from)
    local copy = {}
    for key, value in pairs(type(from) == "table" and from or {}) do
        copy[key] = type(value) == "table" and CopyList(value) or value
    end
    return copy
end

local function CopySet(from)
    local copy = {}
    for key, value in pairs(type(from) == "table" and from or {}) do
        if type(value) ~= "table" then copy[key] = value end
    end
    return copy
end

-- Positions per profile ---------------------------------------------------------
-- Off unless ticked (Profile menu). Your bars' spots and sizes are every
-- character's (db.bars, db.layout), and all the drawing reads them there.
-- While the tick is on, each profile also keeps a copy (profile.place): a
-- switch saves the one on screen into the profile you leave (db.placeOwner,
-- whose spots are on screen) and puts the next profile's in its place. So
-- a Hunter and a Warlock on their own profiles keep their own bar spots.
-- "Where and how big": each bar's spot, grow and wrap directions, icon size,
-- spacing and icons per row, and the whole Layout page arrangement. The
-- look (colours, border, font, All bars) stays every character's.
local PLACE_FIELDS = { "size", "spacing", "perRow", "grow", "wrap", "point", "x", "y" }
ns.PLACE_FIELDS = PLACE_FIELDS

-- The spots and sizes on screen now, sharing nothing with them.
local function Snapshot()
    local place = { bars = {}, layout = CopyTable(db.layout) }
    place.layout.hidden = CopySet(type(db.layout) == "table" and db.layout.hidden)
    for _, key in ipairs(ns.BAR_KEYS) do
        local bar, saved = type(db.bars) == "table" and db.bars[key], {}
        if type(bar) == "table" then
            for _, field in ipairs(PLACE_FIELDS) do saved[field] = rawget(bar, field) end
        end
        place.bars[key] = saved
    end
    return place
end

-- A profile's saved spots, copied (for a profile made from it).
local function CopyPlace(place)
    if type(place) ~= "table" then return nil end
    local copy = { bars = {}, layout = CopyTable(place.layout) }
    copy.layout.hidden = CopySet(type(place.layout) == "table" and place.layout.hidden)
    for key, bar in pairs(type(place.bars) == "table" and place.bars or {}) do copy.bars[key] = CopySet(bar) end
    return copy
end

-- The profile whose spots are on screen keeps them.
SavePlace = function()
    local owner = db.placeOwner
    local profile = type(owner) == "string" and Profiles()[owner]
    if type(profile) == "table" then profile.place = Snapshot() end
end

-- A profile's spots and sizes on screen, each value repaired as it goes in
-- (ns.BarData, ns.LayoutData). A profile with none yet (made before the
-- tick, or new) takes the ones on screen. True if anything changed.
LoadPlace = function(name)
    db.placeOwner = name
    local profile = Profiles()[name]
    local place = type(profile) == "table" and profile.place
    if type(place) ~= "table" then return false end
    local bars = type(place.bars) == "table" and place.bars or {}
    for _, key in ipairs(ns.BAR_KEYS) do
        local data, from = ns.BarData(key), type(bars[key]) == "table" and bars[key] or {}
        for _, field in ipairs(PLACE_FIELDS) do data[field] = from[field] end
        ns.BarData(key)
    end
    local layout = CopyTable(place.layout)
    layout.hidden = CopySet(type(place.layout) == "table" and place.layout.hidden)
    db.layout = layout
    ns.LayoutData()
    return true
end

function ns.PlacePerProfile()
    return db ~= nil and db.placePerProfile == true
end

-- Ticks Positions per profile on or off. On: every profile starts with the
-- spots on screen, so nothing moves until you move it. Off: the spots on
-- screen are every character's again, and the profiles' copies go.
function ns.SetPlacePerProfile(on)
    if not db then return "" end
    on = on == true
    if on == ns.PlacePerProfile() then return "" end
    if InCombatLockdown() then return "Profiles can't change in combat." end
    db.placePerProfile = on or nil
    local profiles = Profiles()
    if on then
        for _, profile in pairs(profiles) do profile.place = Snapshot() end
        db.placeOwner = active
        return "Each profile keeps its own bar spots and sizes now, starting with the ones you have."
    end
    for _, profile in pairs(profiles) do profile.place = nil end
    db.placeOwner = nil
    return "Your bar spots and sizes are every character's again."
end

-- At login, the profile this character uses brings its spots: another
-- character's may still be on screen. Before the bars are made.
PlaceAtLogin = function()
    if db.placePerProfile ~= true or not active or db.placeOwner == active then return end
    SavePlace()
    if LoadPlace(active) and ns.Bars and ns.Bars.started then ns.Bars:Changed() end
end

-- A copy of the profile you're on, for a new profile made from it: its
-- spots are the ones on screen.
PlaceForCopy = function(from)
    if db.placePerProfile ~= true then return nil end
    if from == Profiles()[active] then return Snapshot() end
    return CopyPlace(from and from.place)
end

-- A shared profile's look, bar sizes and spots, layout and Tracked Bar
-- colours in place of yours, everything it leaves out at its default (it
-- only carries what differs). Each is repaired as it goes in.
local function UseSetup(setup)
    local look = type(setup.look) == "table" and setup.look or {}
    for _, key in ipairs(ns.SHARE_LOOK) do
        local value = look[key]
        if value ~= nil and ns.Valid(key, value) then db[key] = value else db[key] = nil end
    end
    local bars = type(setup.bars) == "table" and setup.bars or {}
    for _, key in ipairs(ns.BAR_KEYS) do
        local data, from = ns.BarData(key), type(bars[key]) == "table" and bars[key] or {}
        for _, field in ipairs(ns.SHARE_BAR_FIELDS) do data[field] = from[field] end
        ns.BarData(key)
    end
    local layout = CopyTable(setup.layout)
    layout.hidden = CopySet(type(setup.layout) == "table" and setup.layout.hidden)
    db.layout = layout
    ns.LayoutData()
    db.barColours = CopySet(setup.colours)
    ns.BarColours()
end

-- Every name on a bar in any profile, in the lists used before the character
-- is known, and in bars saved before profiles (name -> true).
local function NamesInUse()
    local used = {}
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
    return used
end

-- A profile someone shared (read and checked by ProfileShare.lua) as a new
-- profile under the name given, with a number after it if that's taken, and
-- switched to: the profile you were on stays as it is. Spells it added by
-- name or ID come too, but only names none of your profiles has on a bar:
-- spells added by ID are every profile's, so one of yours (added by you, or
-- a name the game doesn't know) never takes on the string's IDs.
-- withLook: its look, bar sizes and spots, and layout too, in place of yours
-- (they're every character's). Never in combat.
function ns.ImportProfile(text, shared, withLook)
    local why = Blocked()
    if why then return false, why end
    if type(shared) ~= "table" or type(shared.lists) ~= "table" then return false, "Paste a profile first." end
    local name, problem = CleanName(text)
    if not name then return false, problem end
    name = FreeName(name)
    local profile = { joins = {}, pulsePick = CopySet(shared.pick), pulseStyle = CopySet(shared.style) }
    for _, key in ipairs(ns.BAR_KEYS) do profile[key] = CopyList(shared.lists[key]) end
    for key in pairs(ns.AURA_BARS) do
        local joins = type(shared.joins) == "table" and shared.joins[key]
        if type(joins) == "table" then profile.joins[key] = CopySet(joins) end
    end
    local custom, yours = ns.CustomSpells(), NamesInUse()
    Profiles()[name] = Lists(profile)
    for spell, ids in pairs(type(shared.added) == "table" and shared.added or {}) do
        if type(spell) == "string" and custom[spell] == nil and not yours[spell] then custom[spell] = CopyList(ids) end
    end
    ns.CustomSpells()
    if withLook and type(shared.setup) == "table" then
        -- Positions per profile: the profile you leave keeps its own spots,
        -- and the imported ones on screen become the new profile's.
        if db.placePerProfile == true then
            SavePlace()
            db.placeOwner = nil
        end
        UseSetup(shared.setup)
    end
    Switch(name)
    return true, "Imported " .. name .. (withLook and " with its look and layout" or "") .. ", and switched to it.", name
end

-- Roles ---------------------------------------------------------------------------
-- Tank, Healer and Damage in the profile menu: a profile for each role you
-- play, linked for your class (db.roles: class -> role -> profile name), so
-- every character of that class finds the same three. Clicking a role
-- switches to its profile; the first time, your lists are saved as it,
-- named for your class and the role ("Druid Healer"). Right-click saves your
-- lists over it. A link follows its profile renamed and goes with it
-- deleted. Links are your own: a shared profile never carries one.

local function Plain(value)
    return not (issecretvalue and issecretvalue(value))
end

-- Your class: its file name ("DRUID", for links and talent trees) and its
-- name as the game shows it ("Druid", in a role profile's name); nil while
-- the game doesn't say.
local function Class()
    if not UnitClass then return nil end
    local name, file = UnitClass("player")
    if not (Plain(name) and Plain(file)) or type(name) ~= "string" or type(file) ~= "string" or name == "" or file == "" then
        return nil
    end
    return file, name
end

local function RoleLinks(class)
    if type(db.roles) ~= "table" then db.roles = {} end
    if type(db.roles[class]) ~= "table" then db.roles[class] = {} end
    return db.roles[class]
end

-- A role's profile for your class, while it's there.
function ns.RoleProfile(role)
    local class = db and Class()
    local links = class and type(db.roles) == "table" and db.roles[class]
    local name = type(links) == "table" and links[role]
    if type(name) == "string" and Profiles()[name] then return name end
    return nil
end

-- The name a role's first profile gets: your class and the role ("Druid
-- Healer"), with a number after it if that's taken.
function ns.RoleName(role)
    local _, className = Class()
    if not (db and className and ns.ROLE_NAMES[role]) then return nil end
    return FreeName(Cut(className .. " " .. ns.ROLE_NAMES[role], ns.PROFILE_MAX))
end

-- Why a role can't be used or saved now, or nil.
local function RoleBlocked(role)
    local why = Blocked()
    if why then return why end
    if not ns.ROLE_NAMES[role] then return "There's no such role." end
    if not Class() then return "Your class isn't known yet." end
end
ns.RoleBlocked = RoleBlocked

-- Your lists as a role's first profile, linked for your class: its name.
local function MakeRole(role)
    local name = ns.RoleName(role)
    Profiles()[name] = Duplicate(Profiles()[active])
    RoleLinks((Class()))[role] = name
    return name
end

-- Switches to a role's profile, making it from your lists the first time.
-- Never in combat.
function ns.UseRole(role)
    local why = RoleBlocked(role)
    if why then return false, why end
    ns.talentNote = nil
    local word, name = ns.ROLE_NAMES[role], ns.RoleProfile(role)
    if name == active then return true, ("You're already on %s, your %s profile."):format(name, word) end
    if name then
        Switch(name)
        return true, ("Now using %s, your %s profile."):format(name, word)
    end
    name = MakeRole(role)
    Switch(name)
    return true, ("Saved your lists as %s, your %s profile, and switched to it."):format(name, word)
end

-- Your lists saved over a role's profile (the menu asks first), or as its
-- first one; you stay on the profile you're on. Never in combat.
function ns.SaveRole(role)
    local why = RoleBlocked(role)
    if why then return false, why end
    ns.talentNote = nil
    local word, name = ns.ROLE_NAMES[role], ns.RoleProfile(role)
    if name == active then return true, ("You're on %s: it saves as you go."):format(name) end
    if not name then return true, ("Saved your lists as %s, your %s profile."):format(MakeRole(role), word) end
    Profiles()[name] = Duplicate(Profiles()[active])
    ns.PruneCustom()
    return true, ("Saved your lists over %s, your %s profile."):format(name, word)
end

-- Talents ---------------------------------------------------------------------------
-- Switch with my talents (off unless ticked): each of your class's talent
-- trees is set to a role, and when another tree takes the lead in points (a
-- respec, or points spent levelling), the addon switches to that role's
-- profile, after the fight if you're in one. Only a change of main tree
-- switches, so a role picked by hand stays until the next one. A tree set
-- to None never switches (you pick a role yourself), but still counts as
-- your main tree. A character with no points spent yet has no main tree:
-- its first point only notes one. Forever's talents are trait trees: your
-- class has one, its talent trees are that tree's groups, and a group's
-- points are what's spent in it, read as the game's own talent frame reads
-- them (C_Traits; seen in game 2026-10-08: "Assassination = 10, Combat = 3",
-- with no answer at all for a tree with none spent).

-- A tree's role unless you set one: by the name the game gives it. A
-- druid's Feral Combat is tank and cat alike, so it's None.
local TREE_ROLES = {
    WARRIOR = { Protection = "tank" },
    PALADIN = { Holy = "healer", Protection = "tank" },
    PRIEST = { Discipline = "healer", Holy = "healer" },
    SHAMAN = { Restoration = "healer" },
    DRUID = { Restoration = "healer", ["Feral Combat"] = "none" },
}
local TALENT_EVENTS = { "PLAYER_ENTERING_WORLD", "PLAYER_TALENT_UPDATE", "TRAIT_CONFIG_UPDATED", "TRAIT_CONFIG_LIST_UPDATED",
    "ACTIVE_TALENT_GROUP_CHANGED" }
local talentWatch -- the frame hearing talent changes, made the first time the tick is on
local talentWaiting -- a check held until the fight ends

-- A plain number from a call, or nil.
local function Number(ok, value)
    if ok and Plain(value) and Finite(value) then return value end
end

-- Your active talents' config: the one your spec group fights with.
local function TalentConfig()
    local talents, spec = C_ClassTalents, C_SpecializationInfo
    if type(talents) == "table" and type(talents.GetActiveConfigID) == "function" then
        local config = Number(pcall(talents.GetActiveConfigID))
        if config then return config end
    end
    if type(spec) == "table" and type(spec.GetActiveSpecGroup) == "function" and type(spec.GetCombatConfigIDForSpecGroup) == "function" then
        local group = Number(pcall(spec.GetActiveSpecGroup))
        return group and Number(pcall(spec.GetCombatConfigIDForSpecGroup, group))
    end
end

-- Your talent trees in the game's order: { id, name, points } each; nil
-- while they can't be read.
function ns.TalentTrees()
    local traits = C_Traits
    local config = type(traits) == "table" and TalentConfig()
    if not config then return nil end
    local ok, info = pcall(traits.GetConfigInfo, config)
    local treeIDs = ok and Plain(info) and type(info) == "table" and info.treeIDs
    local tree = Plain(treeIDs) and type(treeIDs) == "table" and Number(true, treeIDs[1])
    if not tree then return nil end
    local got, groups = pcall(traits.GetGroupDisplayInfoByTreeID, tree)
    if not (got and Plain(groups) and type(groups) == "table") then return nil end
    local trees, ids, byID = {}, {}, {}
    for _, group in ipairs(groups) do
        local id = Plain(group) and type(group) == "table" and Number(true, group.groupID)
        local name = id and group.displayName
        if id and Plain(name) and type(name) == "string" and name ~= "" and not byID[id] then
            byID[id] = { id = id, name = name, points = 0 }
            trees[#trees + 1], ids[#ids + 1] = byID[id], id
        end
    end
    if #trees == 0 then return nil end
    -- A tree with nothing spent may not be answered for: none in it.
    local spent, infos = pcall(traits.GetGroupCurrencyInfo, config, ids)
    for _, entry in ipairs(spent and Plain(infos) and type(infos) == "table" and infos or {}) do
        local id = Plain(entry) and type(entry) == "table" and Number(true, entry.traitNodeGroupID)
        local currencies = id and byID[id] and entry.currencyInfos
        local first = Plain(currencies) and type(currencies) == "table" and currencies[1]
        local points = Plain(first) and type(first) == "table" and Number(true, first.spent)
        if points and points > 0 then byID[id].points = points end
    end
    return trees
end

-- The tree with the most points; nil with none spent, or two level at the top.
local function MainTree(trees)
    local main, level
    for _, tree in ipairs(trees) do
        if tree.points > 0 and (not main or tree.points > main.points) then
            main, level = tree, false
        elseif main and tree.points == main.points then
            level = true
        end
    end
    if not level then return main end
end

-- What the talents last did, for the menu and the footer: switched you, or
-- found the role had no profile. Said once, never in chat: in the footer at
-- once with the window open, else the next time it opens (Say only keeps
-- it for the next refresh, and opening refreshes; a window not made yet
-- says ns.talentNote when it's made, Window.lua).
local function TalentNote(text)
    ns.talentNote = text
    local window = ns.window
    if not window then return end
    window:Say(text)
    if window:IsShown() then window:Refresh() end
end

-- The talents' older note no longer holds (a new main tree with nothing to
-- switch, or a new role for the main tree), so it goes from the menu, and
-- from the footer if it was waiting there for the window to open. Quiet:
-- the caller refreshes the window itself.
local function DropTalentNote(quiet)
    local old, window = ns.talentNote, ns.window
    ns.talentNote = nil
    if not (old and window) then return end
    if window.message == old then window:Say(nil) end
    if not quiet and window:IsShown() then window:Refresh() end
end

-- A tree's role (or "none"): the one you set for it, or the one its name
-- suggests (Damage for any not listed).
function ns.TreeRole(tree)
    local class = db and Class()
    local saved = class and type(db.treeRoles) == "table" and type(db.treeRoles[class]) == "table" and db.treeRoles[class][tree.id]
    if ns.TREE_ROLE_NAMES[saved] then return saved end
    return class and TREE_ROLES[class] and TREE_ROLES[class][tree.name] or "damage"
end

-- A tree set to a role (or None) for your class, by its ID (name, the
-- tree's own, gives its default role). A new role for your main tree drops
-- the talents' note about it (the menu refreshes after), but switches
-- nothing: only a change of main tree does.
function ns.SetTreeRole(id, role, name)
    local class = db and Class()
    if not (class and Finite(id) and id > 0 and ns.TREE_ROLE_NAMES[role]) then return end
    local before = ns.TreeRole({ id = id, name = name })
    if type(db.treeRoles) ~= "table" then db.treeRoles = {} end
    if type(db.treeRoles[class]) ~= "table" then db.treeRoles[class] = {} end
    db.treeRoles[class][id] = role
    local guid = PlayerGUID()
    if role ~= before and guid and type(db.mainTrees) == "table" and db.mainTrees[guid] == id then DropTalentNote(true) end
end

-- Looks at your talents: the main tree changed since it was last seen,
-- its role's profile is switched to (if it has one, and the tree isn't set
-- to None). In a fight it waits for the fight to end. The first look on a
-- character (or after the tick goes on) only notes the main tree; with no
-- points spent (a new character, or talents not sent yet) there's none to
-- note, so the first tree to lead is only noted too.
function ns.CheckTalents()
    if not (db and active and ns.Get("talentSwitch")) then return end
    local guid = PlayerGUID()
    if not guid then return end
    if InCombatLockdown() then
        talentWaiting = true
        if talentWatch then talentWatch:RegisterEvent("PLAYER_REGEN_ENABLED") end
        return
    end
    local trees = ns.TalentTrees()
    if not trees then return end
    local main = MainTree(trees)
    if type(db.mainTrees) ~= "table" then db.mainTrees = {} end
    local last = db.mainTrees[guid]
    if last == nil then
        if main then db.mainTrees[guid] = main.id end
        return
    end
    if not main or main.id == last then return end
    db.mainTrees[guid] = main.id
    local role = ns.TreeRole(main)
    if role == "none" then return DropTalentNote() end -- you pick a role yourself
    local word, name = ns.ROLE_NAMES[role], ns.RoleProfile(role)
    if not name then
        return TalentNote(("Your main talent tree is now %s, but %s has no profile yet: click %s to make one.")
            :format(main.name, word, word))
    end
    if name == active then return DropTalentNote() end -- already there
    Switch(name)
    TalentNote(("Your main talent tree is now %s: switched to %s, your %s profile."):format(main.name, name, word))
end

-- Hears talent changes while the tick is on (and nothing while it's off).
local function ListenTalents()
    local on = ns.Get("talentSwitch")
    if not talentWatch then
        if not on then return end
        talentWatch = CreateFrame("Frame")
        talentWatch:SetScript("OnEvent", function(self, event)
            if event == "PLAYER_REGEN_ENABLED" then
                self:UnregisterEvent(event)
                if not talentWaiting then return end
                talentWaiting = nil
            end
            ns.CheckTalents()
        end)
    end
    for _, event in ipairs(TALENT_EVENTS) do
        if on then talentWatch:RegisterEvent(event) else talentWatch:UnregisterEvent(event) end
    end
end

-- Switch with my talents on or off: either way each character notes its
-- main tree afresh, so only a change of main tree from now on switches.
function ns.SetTalentSwitch(on)
    if not db then return end
    on = on == true
    ns.talentNote, db.mainTrees = nil, nil
    ns.Set("talentSwitch", on)
    ListenTalents()
    ns.CheckTalents()
    return on and "Your profile now follows your main talent tree." or "Your profile no longer follows your talents."
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
    bar.showAuras = bar.showAuras == true -- buff and debuff times on cooldown icons, off unless ticked
    bar.selfDebuffs = bar.selfDebuffs == true -- the Buffs and Debuffs bars: debuffs you put on yourself, off unless ticked
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

-- The layout as saved, read without repairing it, for what's asked often:
-- which bars are taken out, on every target change and fight. It's
-- repaired as the settings load, and every change to it goes through
-- ns.LayoutData first.
function ns.SavedLayout()
    local layout = db and db.layout
    return type(layout) == "table" and layout or nil
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

-- Spell ID -> its spell's name in ns.RANKS (Ranks.lua), made the first time
-- it's needed, and again if the list itself changes.
local rankNames, rankList = {}, nil
local function RankName(id)
    if ns.RANKS ~= rankList then
        rankList, rankNames = ns.RANKS, {}
        for name, ids in pairs(rankList or {}) do
            for _, rank in ipairs(ids) do rankNames[rank] = name end
        end
    end
    return rankNames[id]
end

-- Every rank of the spell with this ID, highest first; none if it has no ranks listed.
local function SameSpell(spellID)
    local name = RankName(spellID)
    local ids, found = name and ns.RANKS[name] or {}, {}
    for i = #ids, 1, -1 do found[#found + 1] = ids[i] end
    return found
end

-- A Tracked Bar's own colour by its spell ID, or nil for the colour for all
-- bars. Since build 70170 Blizzard shows every rank of a spell on one bar,
-- under one of its ranks (usually the first), so a colour saved at any rank
-- counts: the highest rank with one, even over the bar's own ID. Before,
-- learning a rank dropped the colour, so the highest rank's is the latest
-- pick. A spell with no ranks listed has only its own ID.
function ns.BarColourFor(spellID)
    if not (Finite(spellID) and spellID > 0) then return nil end
    local colours = ns.BarColours()
    for _, id in ipairs(SameSpell(spellID)) do
        if colours[id] then return colours[id] end
    end
    return colours[spellID]
end

-- One of the Cooldown pulse's lists in this character's profile (repaired
-- with the rest of it), or a stand-in until the character is known.
local function PulseList(field)
    local store = active and db and Profiles()[active] or scratch
    if type(store[field]) ~= "table" then store[field] = {} end
    return store[field]
end

-- Cooldown pulse: the spells (by name) and items (by key) you ticked ->
-- true. Every spell you know with a cooldown is listed, and your items;
-- none pulses until it's ticked (the user: new ones show as you learn
-- them, and you choose). Kept in the profile, as the bars' lists are.
function ns.PulsePicks()
    return PulseList("pulsePick")
end

function ns.SetPulsePick(key, pick)
    if not db or type(key) ~= "string" or key == "" then return end
    ns.PulsePicks()[key] = pick and true or nil
end

-- Cooldown pulse: the spells and items switched to the Long style, by key
-- -> "long". Everything else is Quick. Kept in the profile too.
function ns.PulseStyles()
    return PulseList("pulseStyle")
end

function ns.SetPulseStyle(key, style)
    if not db or type(key) ~= "string" or key == "" then return end
    ns.PulseStyles()[key] = style == "long" and "long" or nil
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
    local custom, used = ns.CustomSpells(), NamesInUse()
    for name in pairs(custom) do
        if not used[name] then custom[name] = nil end
    end
end

-- Changes ---------------------------------------------------------------------------
-- Everything lives in the saved settings, which the game writes at logout and
-- on a reload; a change only needs the window redrawn. The Cooldown pulse
-- switched on or off is told to Forever Enhanced Cooldown Pulse too (Pulse.lua).

function ns.Set(key, value)
    if not db then return end
    db[key] = value
    if key == "pulse" and ns.Pulse and ns.Pulse.Notify then ns.Pulse:Notify() end
    if ns.window and ns.window:IsShown() then ns.window:Refresh() end
end

-- A Tracked Bar's own colour, or nil to go back to the colour for all bars.
-- Kept under the bar's spell ID; any other rank's colour goes, so it can't
-- come back in its place.
function ns.SetBarColour(spellID, key)
    if not db or not (Finite(spellID) and spellID > 0) then return end
    local colours = ns.BarColours()
    for _, id in ipairs(SameSpell(spellID)) do colours[id] = nil end
    colours[spellID] = key ~= nil and ns.Valid("barColour", key) and key or nil
    if ns.window and ns.window:IsShown() then ns.window:Refresh() end
end

-- What's new: the version whose notes were last shown, or passed over for
-- the welcome on a first install. Marked as they show (Notes.lua), so a
-- reload or logout before then keeps them due.
function ns.NotesSeen()
    return db and type(db.notesSeen) == "string" and db.notesSeen or nil
end

function ns.SetNotesSeen(version)
    if not db then return end
    db.notesSeen = version
end

-- A first install's welcome, until it shows: still due after a reload or
-- logout before it does, when the settings file isn't empty any more.
function ns.WelcomeDue()
    return db ~= nil and db.welcomeDue == true
end

function ns.SetWelcomeDue(due)
    if db then db.welcomeDue = due and true or nil end
end

-- The ? in the window's title bar: clicked at least once, on any character.
-- Until then it pulses and a note points it out (Window.lua).
function ns.HelpSeen()
    return db ~= nil and db.helpSeen == true
end

function ns.SetHelpSeen()
    if not db then return end
    db.helpSeen = true
end

-- One of Blizzard's own settings switched from here (ns.TurnOn, ns.TurnOff):
-- the game reacts to it straight away, inside the addon's click, so a reload
-- finishes it cleanly.
local switched = false

function ns.NeedsReload()
    if switched then return true end
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
-- on afterwards, or false and why not. Switched, a reload is asked for.
function ns.TurnOn(cvar)
    if InCombatLockdown() then return false, "Finish combat first." end
    if not (C_CVar and C_CVar.SetCVar and C_CVar.GetCVarBool) then return false end
    pcall(C_CVar.SetCVar, cvar, "1")
    local on = C_CVar.GetCVarBool(cvar) == true
    if on then switched = true end
    return on
end

-- And off again, when you ask: true when it's off afterwards.
function ns.TurnOff(cvar)
    if InCombatLockdown() then return false, "Finish combat first." end
    if not (C_CVar and C_CVar.SetCVar and C_CVar.GetCVarBool) then return false end
    pcall(C_CVar.SetCVar, cvar, "0")
    local off = C_CVar.GetCVarBool(cvar) == false
    if off then switched = true end
    return off
end

-- Escape closes the /ccm window and What's new through the game's own list
-- of windows Escape closes (UISpecialFrames), never by changing key bindings:
-- a binding changed from addon code has the game rebuild your action bars
-- and state inside the addon's code, which then breaks on your hidden health
-- (thousands of errors, 2026-10-06). The game reads that list inside a
-- securecall, so the entries stay out of the rest of its Escape handling.
-- One Escape closes every listed window that's open; a tour ends as its
-- window closes (Tour.lua). Like the game's own windows on that list, they
-- also close whenever the game closes all windows: the interface coming
-- back after Alt+Z (the game's Escape brings it back first), a loading
-- screen, death, losing control of your character, or a centre or full
-- screen panel of the game's opening (Edit Mode, Help).
local escapeListed = {}
function ns.CloseOnEscape(frame)
    local name = frame and frame:GetName()
    if not name or escapeListed[name] or type(UISpecialFrames) ~= "table" then return end
    escapeListed[name] = true
    table.insert(UISpecialFrames, name)
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
    about:SetText("A cleaner look for Blizzard's Cooldown Manager and Personal Resource Display, plus cooldown, buff and cast bars of your own. Click below or the minimap button for the settings, or type /ccm.")
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
    if db.welcomeDue ~= true then db.welcomeDue = nil end -- the welcome not shown yet: true, or not saved at all
    if ns.firstInstall then db.welcomeDue = true end
    db.probe = nil -- results of a development check the released addon doesn't have
    db.session = nil -- a login count earlier builds kept
    db.pulseMin, db.pulseAdd = nil, nil -- the Cooldown pulse's first test build: a shortest cooldown, and spells added by name
    db.pulseSkip = nil -- and its second: items pulsed unless unticked
    if db.helpSeen ~= true then db.helpSeen = nil end -- the ? clicked once: true, or not saved at all
    -- Everything saved is checked and repaired now, before anything uses it.
    RepairProfiles()
    for _, key in ipairs(ns.BAR_KEYS) do ns.BarData(key) end
    ns.LayoutData()
    ns.CustomSpells()
    ns.BarColours()
    ns.ResolveProfile()
    ListenTalents()
    for key in pairs(ns.RELOAD) do ns.loaded[key] = ns.Get(key) end

    SLASH_FECM1 = "/ccm"
    SLASH_FECM2 = "/fecm"
    SlashCmdList.FECM = function(msg)
        msg = type(msg) == "string" and msg:lower() or ""
        if msg:match("^%s*reset%s*$") and ns.AskReset then
            ns.AskReset()
        elseif msg:match("^%s*new%s*$") and ns.ShowNotes then
            ns.ShowNotes()
        elseif msg:match("^%s*tour%s*$") and ns.Tour then
            ns.Tour:Start()
        elseif msg:match("^%s*discord%s*$") and ns.ShowDiscord then
            ns.ShowDiscord()
        elseif msg:match("^%s*debug%s*$") and ns.ShowDebug then
            ns.ShowDebug()
        elseif ns.Toggle then
            ns.Toggle()
        end
    end
    BuildOptionsEntry()

    if ns.loaded.skin and ns.Skin then ns.Skin:Start() end
    if ns.Keybinds then ns.Keybinds:Start() end
    if ns.Resource then ns.Resource:Start() end
    if ns.CastBar then ns.CastBar:Start() end
    if ns.RaidTimers then ns.RaidTimers:Start() end
    if ns.Bars then ns.Bars:Start() end
    if ns.Pulse then ns.Pulse:Start() end
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
