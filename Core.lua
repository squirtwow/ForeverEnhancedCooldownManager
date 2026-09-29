-- Forever Enhanced Cooldown Manager: saved settings and their backup, the /ccm command,
-- Escape for the window and the entry in Options > AddOns. Each feature lives
-- in its own file and starts from here once the saved settings are loaded.
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

ns.DEFAULTS = {
    skin = true,
    useBars = false, -- the addon's own bars
    listItems = false, -- show trinkets and bag items in the /ccm spell list
    listRanks = false, -- show every rank you know as its own row
    accent = "orange", -- the /ccm window's accent colour
    barStyle = "glass", -- Blizzard's Tracked Bars: glass, split or outline
    barColour = "orange", -- and their colour
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
    iconBorder = "off", -- a thin border round each icon ("icon") or whole bars ("bar")
    iconShadow = "off", -- and a soft shadow, the same way
    minimap = true, -- the minimap button
    minimapAngle = 225, -- where it sits round the minimap: degrees anticlockwise from the right
}
ns.DECOR_KEYS = { "off", "icon", "bar" }
ns.DECOR_NAMES = { off = "Off", icon = "Each icon", bar = "Whole bar" }
-- Number settings, each within its limits: min, max, default.
ns.CAST_HEIGHT = { 10, 32, 18 }
ns.MINIMAP_ANGLE = { 0, 359, 225 }
local NUMBERS = { castHeight = ns.CAST_HEIGHT, minimapAngle = ns.MINIMAP_ANGLE }
-- Choices a text setting may hold.
ns.ACCENT_KEYS = { "orange", "blue", "teal", "purple", "green" }
ns.BAR_STYLE_KEYS = { "glass", "split", "outline" }
ns.BAR_STYLE_NAMES = { glass = "Glass", split = "Split", outline = "Outline" }
ns.BAR_COLOUR_KEYS = { "orange", "charcoal", "blue", "green", "purple", "class" } -- your class colour last
ns.BAR_COLOUR_NAMES = { orange = "Orange", class = "Class", charcoal = "Charcoal", blue = "Blue", green = "Green", purple = "Purple" }
local CHOICES = { accent = {}, barStyle = {}, barColour = {}, prdHealth = { default = true }, prdPower = { default = true },
    prdComboColour = { default = true }, castColour = { default = true },
    iconBorder = { off = true, icon = true, bar = true }, iconShadow = { off = true, icon = true, bar = true } }
for _, key in ipairs(ns.ACCENT_KEYS) do CHOICES.accent[key] = true end
for _, key in ipairs(ns.BAR_STYLE_KEYS) do CHOICES.barStyle[key] = true end
for _, key in ipairs(ns.BAR_COLOUR_KEYS) do
    CHOICES.barColour[key], CHOICES.prdHealth[key], CHOICES.prdPower[key] = true, true, true
    CHOICES.prdComboColour[key], CHOICES.castColour[key] = true, true
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

-- "Name (Class) - Realm". On a character's very first login the game may not
-- know its name yet: nil then, unless a name is needed now anyway.
local function OwnName(anyway)
    local name = UnitName and UnitName("player")
    if type(name) ~= "string" or name == "" or name == UNKNOWN then
        if not anyway then return nil end
        name = UNKNOWN
    end
    local class = UnitClass and UnitClass("player") or UNKNOWN
    local realm = GetRealmName and GetRealmName() or ""
    if realm == "" then return ("%s (%s)"):format(name, class) end
    return ("%s (%s) - %s"):format(name, class, realm)
end

-- The name itself if it's free, otherwise with a number after it.
local function FreeName(name)
    local profiles, candidate, n = Profiles(), name, 1
    while profiles[candidate] do
        n = n + 1
        candidate = name .. " " .. n
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
    if ns.Bars and ns.Bars.started then ns.Bars:Changed() else ns.SaveBars() end
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
    ns.SaveBars()
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
    ns.SaveBars()
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

-- Whether a profile can be deleted now: true and its name, or false and why.
function ns.CanDeleteProfile(text)
    local why = Blocked()
    if why then return false, why end
    local name, problem = CleanName(text)
    if not name then return false, problem end
    if not Profiles()[name] then return false, ('No profile is called "%s".'):format(name) end
    local me = PlayerGUID()
    for guid, used in pairs(Chars()) do
        if used == name and guid ~= me then
            return false, "Another character uses " .. name .. ", so it can't be deleted."
        end
    end
    return true, name
end

-- Deletes the named profile, unless another character uses it. Deleting your
-- own leaves you on a new, empty profile of your own.
function ns.DeleteProfile(text)
    local ok, name = ns.CanDeleteProfile(text)
    if not ok then return false, name end
    local profiles = Profiles()
    profiles[name] = nil
    if db.everyone == name then db.everyone = nil end
    if name == active then
        local fresh = FreeName(OwnName(true))
        profiles[fresh] = Lists({})
        Switch(fresh)
        return true, "Deleted " .. name .. ". You're now on " .. fresh .. "."
    end
    ns.PruneCustom()
    ns.SaveBars()
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
    bar.hideReady = bar.hideReady == true
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

-- Backup ------------------------------------------------------------------------
-- The Forever client can lose addon saved settings after a restart, so every
-- choice is also kept in game settings registered by the addon, and read back
-- at login for anything missing. Plain settings are stored as "key=1" pairs and
-- the bars as "cd.size=36;cd.spells=Moonfire|Bash" text split into chunks;
-- everything read back is checked, and nothing is ever run as code.
ns.BACKUP = "FECMBackup"
local BARS_BACKUP = ns.BACKUP .. "Bars"
-- The backup this addon kept under its first name, read once to carry a
-- setup over, with the two settings that were renamed.
local LEGACY = "ClassicCooldownManagerBackup"
local LEGACY_KEYS = { classicLook = "skin", classicBars = "useBars" }
local CHUNK, MAX_CHUNKS = 900, 48

local function ReadCVar(name)
    if not (C_CVar and C_CVar.GetCVar) then return nil end
    local ok, value = pcall(C_CVar.GetCVar, name)
    if ok and type(value) == "string" then return value end
end

local function WriteCVar(name, value)
    if not (C_CVar and C_CVar.SetCVar and C_CVar.RegisterCVar) then return end
    if ReadCVar(name) == nil then pcall(C_CVar.RegisterCVar, name, "") end
    pcall(C_CVar.SetCVar, name, value)
end

local function ReadBackup(name)
    local values = {}
    local text = ReadCVar(name or ns.BACKUP)
    if not text then return values end
    for key, value in text:gmatch("(%w+)=(%w+)") do
        key = LEGACY_KEYS[key] or key
        local default = ns.DEFAULTS[key]
        if type(default) == "boolean" and (value == "0" or value == "1") then
            values[key] = value == "1"
        elseif type(default) == "string" and ns.Valid(key, value) then
            values[key] = value
        elseif type(default) == "number" and ns.Valid(key, tonumber(value)) then
            values[key] = tonumber(value)
        end
    end
    return values
end

-- The bars backup: "v2;" then key and value pairs, each written as its length,
-- a colon and the text, so profile and spell names can hold any character.
local V2 = "v2;"
local TOKEN_MAX = 4000

local function Token(text)
    text = tostring(text)
    return #text .. ":" .. text
end

local function SpellText(list)
    local names = {}
    for _, name in ipairs(list) do
        if not name:find("|", 1, true) then names[#names + 1] = name end
    end
    return table.concat(names, "|")
end

local function EncodeBars()
    local out = { V2 }
    local function Put(key, value) out[#out + 1] = Token(key) .. Token(value) end
    Put("session", db.session or 0)
    for _, key in ipairs(ns.BAR_KEYS) do
        local bar = ns.BarData(key)
        Put(key .. ".size", bar.size)
        Put(key .. ".spacing", bar.spacing)
        Put(key .. ".hide", bar.hideReady and 1 or 0)
        Put(key .. ".ooc", bar.outOfCombat)
        Put(key .. ".missing", bar.showMissing and 1 or 0)
        Put(key .. ".names", bar.showNames and 1 or 0)
        Put(key .. ".timer", bar.showTimer and 1 or 0)
        Put(key .. ".row", bar.perRow)
        Put(key .. ".grow", bar.grow)
        Put(key .. ".wrap", bar.wrap)
        if bar.x and bar.y then
            Put(key .. ".x", ("%.1f"):format(bar.x))
            Put(key .. ".y", ("%.1f"):format(bar.y))
            if bar.point then Put(key .. ".point", bar.point) end
        end
        -- Lists saved before profiles, until the character is known.
        local old = rawget(bar, "spells")
        if type(old) == "table" then Put(key .. ".spells", SpellText(old)) end
    end
    local index = {}
    for i, name in ipairs(ns.ProfileNames()) do
        index[name] = i
        Put("p" .. i, name)
        local profile = Profiles()[name]
        for _, key in ipairs(ns.BAR_KEYS) do Put("p" .. i .. "." .. key, SpellText(profile[key])) end
        for key in pairs(ns.AURA_BARS) do
            local joined = {}
            for spell in pairs(profile.joins and profile.joins[key] or {}) do joined[#joined + 1] = spell end
            table.sort(joined)
            if #joined > 0 then Put("p" .. i .. "." .. key .. ".joins", SpellText(joined)) end
        end
    end
    local guids = {}
    for guid, name in pairs(Chars()) do
        if index[name] then guids[#guids + 1] = guid end
    end
    table.sort(guids)
    for _, guid in ipairs(guids) do Put("c." .. guid, index[Chars()[guid]]) end
    if index[Everyone() or ""] then Put("all", index[Everyone()]) end
    local custom = {}
    for name in pairs(ns.CustomSpells()) do custom[#custom + 1] = name end
    table.sort(custom)
    for i, name in ipairs(custom) do
        Put("u" .. i, name)
        Put("u" .. i .. ".ids", table.concat(ns.CustomSpells()[name], ","))
    end
    local coloured = {}
    for id in pairs(ns.BarColours()) do coloured[#coloured + 1] = id end
    table.sort(coloured)
    for _, id in ipairs(coloured) do Put("bc." .. id, ns.BarColours()[id]) end
    if type(db.notesSeen) == "string" then Put("notes", db.notesSeen) end
    local layout = ns.LayoutData()
    Put("lay.on", layout.on and 1 or 0)
    Put("lay.gap", layout.gap)
    Put("lay.spacing", layout.spacing)
    if layout.preset then Put("lay.preset", layout.preset) end
    if layout.base then Put("lay.base", layout.base) end
    local hidden = {}
    for _, key in ipairs(ns.BAR_KEYS) do
        if layout.hidden[key] then hidden[#hidden + 1] = key end
    end
    if #hidden > 0 then Put("lay.hidden", table.concat(hidden, ",")) end
    Put("lay.above", table.concat(layout.above, ","))
    Put("lay.below", table.concat(layout.below, ","))
    if layout.left then Put("lay.left", layout.left) end
    if layout.right then Put("lay.right", layout.right) end
    return table.concat(out)
end

local function SpellNames(text)
    local names = {}
    for name in (text or ""):gmatch("[^|]+") do
        if #name <= 60 and #names < ns.BAR_MAX_SPELLS then names[#names + 1] = name end
    end
    return names
end

local function DecodeV2(text)
    local pos = #V2 + 1
    local function Read()
        local length, start = text:match("^(%d+):()", pos)
        length = tonumber(length)
        if not length or length > TOKEN_MAX then return nil end
        local piece = text:sub(start, start + length - 1)
        if #piece ~= length then return nil end
        pos = start + length
        return piece
    end
    local values = {}
    while pos <= #text do
        local key = Read()
        local value = key and Read()
        if not value then break end
        values[key] = value
    end
    local decoded = { session = tonumber(values.session), bars = {}, profiles = {}, chars = {}, custom = {} }
    for _, key in ipairs(ns.BAR_KEYS) do
        local function Flag(field) return values[key .. "." .. field] == "1" end
        decoded.bars[key] = {
            size = tonumber(values[key .. ".size"]), spacing = tonumber(values[key .. ".spacing"]),
            hideReady = Flag("hide"), showMissing = Flag("missing"),
            outOfCombat = values[key .. ".ooc"] or (Flag("combat") and "hide" or nil),
            showNames = Flag("names"), showTimer = values[key .. ".timer"] ~= "0",
            x = tonumber(values[key .. ".x"]), y = tonumber(values[key .. ".y"]),
            point = values[key .. ".point"], perRow = tonumber(values[key .. ".row"]),
            grow = values[key .. ".grow"], wrap = values[key .. ".wrap"],
            spells = values[key .. ".spells"] and SpellNames(values[key .. ".spells"]) or nil,
        }
    end
    if values["lay.on"] then
        local function Keys(text)
            local keys = {}
            for key in (text or ""):gmatch("[^,]+") do keys[#keys + 1] = key end
            return keys
        end
        local hidden = {}
        for _, key in ipairs(Keys(values["lay.hidden"])) do hidden[key] = true end
        decoded.layout = { on = values["lay.on"] == "1", preset = values["lay.preset"], gap = tonumber(values["lay.gap"]),
            spacing = tonumber(values["lay.spacing"]), base = values["lay.base"], hidden = hidden,
            above = Keys(values["lay.above"]), below = Keys(values["lay.below"]),
            left = values["lay.left"], right = values["lay.right"] }
    end
    local names = {}
    for i = 1, 500 do
        local name = values["p" .. i]
        if not name then break end
        if not CleanName(name) or CleanName(name) ~= name then break end
        names[i] = name
        local profile = { joins = {} }
        for _, key in ipairs(ns.BAR_KEYS) do profile[key] = SpellNames(values["p" .. i .. "." .. key]) end
        for key in pairs(ns.AURA_BARS) do
            local joined = values["p" .. i .. "." .. key .. ".joins"]
            if joined then
                profile.joins[key] = {}
                for _, spell in ipairs(SpellNames(joined)) do profile.joins[key][spell] = true end
            end
        end
        decoded.profiles[name] = profile
    end
    for key, value in pairs(values) do
        local guid = key:match("^c%.(.+)$")
        local name = guid and names[tonumber(value)]
        if name then decoded.chars[guid] = name end
    end
    decoded.everyone = names[tonumber(values.all or "")]
    for i = 1, 500 do
        local name = values["u" .. i]
        if not name then break end
        local ids = {}
        for id in (values["u" .. i .. ".ids"] or ""):gmatch("%d+") do ids[#ids + 1] = tonumber(id) end
        if #name <= 60 and #ids > 0 then decoded.custom[name] = ids end
    end
    for key, value in pairs(values) do
        local id = tonumber(key:match("^bc%.(%d+)$") or "")
        if id and id > 0 and ns.Valid("barColour", value) then
            decoded.barColours = decoded.barColours or {}
            decoded.barColours[id] = value
        end
    end
    if next(decoded.profiles) == nil then decoded.profiles, decoded.chars, decoded.everyone = nil, nil, nil end
    if values.notes and #values.notes <= 40 then decoded.notesSeen = values.notes end
    return decoded
end

-- The backup written before profiles: "cd.size=36;cd.spells=Moonfire|Bash".
local function DecodeBars(text)
    local bars, custom = {}, nil
    for key, field, value in text:gmatch("(%a+)%.(%a+)=([^;]*)") do
        if key == "extra" and field == "custom" then
            custom = {}
            for name, list in value:gmatch("([^|~]+)~([%d,]+)") do
                local ids = {}
                for id in list:gmatch("%d+") do ids[#ids + 1] = tonumber(id) end
                if #name <= 60 and #ids > 0 then custom[name] = ids end
            end
        elseif ns.BAR_NAMES[key] then
            local bar = bars[key] or { spells = {} }
            bars[key] = bar
            if field == "size" or field == "spacing" then
                bar[field] = tonumber(value)
            elseif field == "hide" then
                bar.hideReady = value == "1"
            elseif field == "missing" then
                bar.showMissing = value == "1"
            elseif field == "names" then
                bar.showNames = value == "1"
            elseif field == "timer" then
                bar.showTimer = value == "1"
            elseif field == "combat" then
                bar.outOfCombat = value == "1" and "hide" or "show"
            elseif field == "x" or field == "y" then
                bar[field] = tonumber(value)
            elseif field == "spells" then
                for name in value:gmatch("[^|]+") do
                    if #name <= 60 and #bar.spells < ns.BAR_MAX_SPELLS then bar.spells[#bar.spells + 1] = name end
                end
            end
        end
    end
    return next(bars) and bars or nil, custom
end

local function ReadBarsBackup(prefix)
    prefix = prefix or BARS_BACKUP
    local count = tonumber(ReadCVar(prefix .. "0") or "")
    if not count or count < 1 or count > MAX_CHUNKS then return nil end
    local parts = {}
    for i = 1, count do
        parts[i] = ReadCVar(prefix .. i)
        if not parts[i] then return nil end
    end
    local text = table.concat(parts)
    if text:sub(1, #V2) == V2 then return DecodeV2(text) end
    local bars, custom = DecodeBars(text)
    if bars or custom then return { bars = bars, custom = custom } end
end

local function WriteBackup()
    local flags = {}
    for key, default in pairs(ns.DEFAULTS) do
        if type(default) == "boolean" then
            flags[#flags + 1] = key .. "=" .. (ns.Get(key) and "1" or "0")
        elseif type(default) == "string" then
            flags[#flags + 1] = key .. "=" .. ns.Get(key)
        elseif type(default) == "number" then
            flags[#flags + 1] = key .. "=" .. math.floor(ns.Get(key) + .5)
        end
    end
    table.sort(flags)
    WriteCVar(ns.BACKUP, table.concat(flags, ";"))
    if not db then return end
    local text = EncodeBars()
    local count = math.min(MAX_CHUNKS, math.ceil(#text / CHUNK))
    for i = 1, count do WriteCVar(BARS_BACKUP .. i, text:sub((i - 1) * CHUNK + 1, i * CHUNK)) end
    WriteCVar(BARS_BACKUP .. "0", tostring(count))
end

function ns.Set(key, value)
    if not db then return end
    db[key] = value
    WriteBackup()
    if ns.window and ns.window:IsShown() then ns.window:Refresh() end
end

-- A Tracked Bar's own colour, or nil to go back to the colour for all bars.
function ns.SetBarColour(spellID, key)
    if not db or not (Finite(spellID) and spellID > 0) then return end
    ns.BarColours()[spellID] = key ~= nil and ns.Valid("barColour", key) and key or nil
    WriteBackup()
    if ns.window and ns.window:IsShown() then ns.window:Refresh() end
end

-- Called after any change to a bar's data.
function ns.SaveBars()
    WriteBackup()
end

-- What's new: the version whose notes were last shown, or passed over on a
-- first install.
function ns.NotesSeen()
    return db and type(db.notesSeen) == "string" and db.notesSeen or nil
end

function ns.SetNotesSeen(version)
    if not db then return end
    db.notesSeen = version
    WriteBackup()
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

local function Shown(frame)
    return frame ~= nil and frame:IsShown()
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

ns.RESTORED_TEXT = "The game didn't keep this addon's settings from your last session, so they were restored from its backup."

local function Load()
    ForeverEnhancedCooldownManagerDB = type(ForeverEnhancedCooldownManagerDB) == "table" and ForeverEnhancedCooldownManagerDB or {}
    db = ForeverEnhancedCooldownManagerDB
    -- A first login under the new name picks up the old backup.
    local hadBackup = ReadCVar(ns.BACKUP) ~= nil
    local fresh = next(db) == nil and not hadBackup
    ns.firstInstall = fresh
    local flags = ReadBackup(fresh and LEGACY or nil)
    local backup = ReadBarsBackup(fresh and LEGACY .. "Bars" or nil) or {}
    -- Each login is numbered in both the saved settings and the backup. An
    -- empty settings file next to a backup, or one older than the backup,
    -- means the game didn't keep the last session's settings; the newer
    -- backup is then used for everything. Otherwise saved settings win and
    -- the backup only fills in what's missing.
    local session = tonumber(db.session)
    ns.restored = hadBackup and not fresh and (next(db) == nil or (session ~= nil and (backup.session or 0) > session))
    for key, value in pairs(flags) do
        if ns.restored or db[key] == nil then db[key] = value end
    end
    for _, field in ipairs({ "bars", "profiles", "chars", "everyone", "custom", "barColours", "notesSeen", "layout" }) do
        if backup[field] ~= nil and (ns.restored or db[field] == nil) then db[field] = backup[field] end
    end
    db.session = math.max(session or 0, backup.session or 0) + 1
    db.probe = nil -- results of a development check the released addon doesn't have
    RepairProfiles()
    for _, key in ipairs(ns.BAR_KEYS) do ns.BarData(key) end
    ns.ResolveProfile()
    WriteBackup()
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
        if not active and ns.ResolveProfile(true) then
            WriteBackup()
            if ns.Bars then ns.Bars:Rebuild() end
        end
        if ns.NameUnknownProfile() and ns.window and ns.window:IsShown() then ns.window:Refresh() end
        if ns.restored then print("|cffffd100" .. ns.TITLE .. ":|r " .. ns.RESTORED_TEXT) end
    end
end)
