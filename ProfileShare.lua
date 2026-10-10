-- Sharing a profile as text. Share, in the profile menu, shows the profile
-- you're on, with your bars' look and layout, as one line to copy (into
-- Discord, say). Import takes one pasted in and makes it a new profile, so
-- the one you're on stays as it is. Its look and layout only replace yours
-- if you tick them, after a question, as they're every character's.
--
-- A share string is "FECM1:" (the format's version), then the profile
-- packed in this file's own plain format and written in Base64, which
-- survives chat and copying. Reading one only takes text apart, a character
-- at a time, within set limits (its length, how deep lists go and how many
-- values it holds): nothing in a string is ever run. Only what this version
-- knows is kept, each value checked; the rest is left out and counted.
local _, ns = ...
local T = ns.Theme

local P = {}
ns.ProfileShare = P

P.PREFIX, P.FORMAT = "FECM", 1
P.MAX_TEXT = 32000 -- the longest string read; a big profile is a few thousand letters
local MAX_DATA = 24000 -- the most a string may unpack to (Base64 is four letters for three)
local MAX_WORD = 64 -- the longest name or key kept
local MAX_DEPTH = 4 -- lists inside lists, the outermost counted
local MAX_ITEMS = 4000 -- values in all, keys counted
local MAX_PICKS = 400 -- Cooldown pulse ticks, and the cooldowns switched to Long
local MAX_IDS = 10 -- spell IDs an added spell keeps
local MAX_COLOURS = 200 -- Tracked Bars coloured one by one
local MAX_ID = 2147483647 -- the biggest spell or item ID
P.IMPORTED = "Shared profile" -- a new profile's name when none is typed (strings carry no name)

P.NOT_OURS = "That string isn't a FECM profile."
P.DAMAGED = "That profile is cut short or damaged. Copy all of it again."
P.TOO_LONG = "That's too long to be a FECM profile."
P.NEWER = "That profile is from a newer version of the addon. Update it, then paste it again."
-- A string that doesn't read, with other words before it (a whole message pasted).
P.PART = "Copy just the profile, from " .. P.PREFIX .. P.FORMAT .. ": to its end, and paste it again."
P.TOO_MUCH = "That's too much to share in one string."

local function Finite(n)
    return type(n) == "number" and n == n and n > -math.huge and n < math.huge
end

local function Integer(n)
    return Finite(n) and n == math.floor(n)
end

-- A whole number from 1 up to the biggest ID, or nil.
local function ID(value)
    return Integer(value) and value >= 1 and value <= MAX_ID and value or nil
end

-- Base64 ---------------------------------------------------------------------------------------
-- Letters, digits, + and /, with = making up the last four; no other
-- character is read.

local ALPHABET = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"
local LETTER, VALUE = {}, {}
for i = 1, #ALPHABET do
    LETTER[i - 1] = ALPHABET:sub(i, i)
    VALUE[ALPHABET:byte(i)] = i - 1
end
local PAD = ("="):byte()

local function Encode64(raw)
    local out = {}
    for i = 1, #raw, 3 do
        local a, b, c = raw:byte(i, i + 2)
        local n = a * 65536 + (b or 0) * 256 + (c or 0)
        out[#out + 1] = LETTER[math.floor(n / 262144)] .. LETTER[math.floor(n / 4096) % 64]
            .. (b and LETTER[math.floor(n / 64) % 64] or "=") .. (c and LETTER[n % 64] or "=")
    end
    return table.concat(out)
end

-- The bytes, or nil for anything but whole Base64.
local function Decode64(text)
    local length = #text
    if length == 0 or length % 4 ~= 0 then return nil end
    local out = {}
    for i = 1, length, 4 do
        local a, b, c, d = text:byte(i, i + 3)
        local w, x, y, z = VALUE[a], VALUE[b], VALUE[c], VALUE[d]
        local last = i + 3 == length
        if not (w and x) then return nil end
        if last and c == PAD and d == PAD then
            out[#out + 1] = string.char(math.floor((w * 262144 + x * 4096) / 65536))
        elseif last and d == PAD then
            if not y then return nil end
            local n = w * 262144 + x * 4096 + y * 64
            out[#out + 1] = string.char(math.floor(n / 65536), math.floor(n / 256) % 256)
        else
            if not (y and z) then return nil end
            local n = w * 262144 + x * 4096 + y * 64 + z
            out[#out + 1] = string.char(math.floor(n / 65536), math.floor(n / 256) % 256, n % 256)
        end
    end
    return table.concat(out)
end

-- Packing --------------------------------------------------------------------------------------
-- T and F for true and false; N, a number and ; ("N-12.5;"); S, the text's
-- length in bytes, : and the text ("S8:Moonfire"); [ values ] for a list;
-- { key value ... } for any other table, its keys in order, so a profile
-- always packs the same way.

local TRUE, FALSE, NUMBER, TEXT, LIST, TABLE = ("TFNS[{"):byte(1, 6)
local END_LIST, END_TABLE = ("]}"):byte(1, 2)

-- Whether a table is a list: 1 to n, nothing else.
local function IsList(t)
    local count = 0
    for _ in pairs(t) do count = count + 1 end
    return count == #t
end

local function KeyOrder(a, b)
    local x, y = type(a), type(b)
    if x ~= y then return x == "number" end
    return a < b
end

local function Pack(value, out)
    local kind = type(value)
    if kind == "boolean" then
        out[#out + 1] = value and "T" or "F"
    elseif kind == "number" then
        out[#out + 1] = (Integer(value) and math.abs(value) < 2147483648) and ("N%d;"):format(value) or ("N%.14g;"):format(value)
    elseif kind == "string" then
        out[#out + 1] = "S" .. #value .. ":" .. value
    elseif kind == "table" then
        if IsList(value) then
            out[#out + 1] = "["
            for _, item in ipairs(value) do Pack(item, out) end
            out[#out + 1] = "]"
        else
            local keys = {}
            for key in pairs(value) do keys[#keys + 1] = key end
            table.sort(keys, KeyOrder)
            out[#out + 1] = "{"
            for _, key in ipairs(keys) do
                Pack(key, out)
                Pack(value[key], out)
            end
            out[#out + 1] = "}"
        end
    end
end

-- Packed text taken apart: true and the value, or false for anything else
-- (cut short, too deep, too many values, a key twice or of the wrong kind,
-- a number that isn't plainly one, a stray character, anything left over).
local function Unpack(raw)
    local at, items = 1, 0
    local function Value(depth)
        items = items + 1
        if items > MAX_ITEMS then return false end
        local tag = raw:byte(at)
        at = at + 1
        if tag == TRUE then return true, true end
        if tag == FALSE then return true, false end
        if tag == NUMBER then
            local text = raw:match("^([%-%+%.%deE]+);", at)
            if not text or #text > 24 then return false end
            if not (text:find("^%-?%d+%.?%d*$") or text:find("^%-?%d+%.?%d*[eE][%-%+]?%d+$")) then return false end
            local n = tonumber(text)
            if not Finite(n) then return false end
            at = at + #text + 1
            return true, n
        end
        if tag == TEXT then
            local digits = raw:match("^(%d%d?%d?):", at)
            if not digits then return false end
            local first = at + #digits + 1
            local last = first + tonumber(digits) - 1
            if last > #raw then return false end
            at = last + 1
            return true, raw:sub(first, last)
        end
        if (tag ~= LIST and tag ~= TABLE) or depth >= MAX_DEPTH then return false end
        local t, n, close = {}, 0, tag == LIST and END_LIST or END_TABLE
        while true do
            local byte = raw:byte(at)
            if not byte then return false end
            if byte == close then
                at = at + 1
                return true, t
            end
            local ok, key = Value(depth + 1)
            if not ok then return false end
            if tag == LIST then
                n = n + 1
                t[n] = key
            else
                if (type(key) ~= "string" and type(key) ~= "number") or t[key] ~= nil then return false end
                local good, value = Value(depth + 1)
                if not good then return false end
                t[key] = value
            end
        end
    end
    local ok, value = Value(0)
    if not ok or at ~= #raw + 1 then return false end
    return true, value
end

-- What a string may hold -------------------------------------------------------------------------

-- A name or key as kept: short plain text, no colour or link codes, no
-- control characters, no spaces round it. Nil otherwise.
local function Word(value)
    if type(value) ~= "string" or value == "" or #value > MAX_WORD then return nil end
    if value:find("[%c|]") or value:find("^%s") or value:find("%s$") then return nil end
    return value
end

local families
-- A bar entry's key as the bars keep them (Spells.lua): a spell's name,
-- "Name@N" for one of its ranks, "Name#ID" for a spell pinned to one ID,
-- "item:<id>", "slot:13" or "slot:14" (the trinkets), "ammo", or a
-- healthstone or potion family. Nil for anything else.
local function Entry(value)
    local key = Word(value)
    if not key then return nil end
    if key:find("#", 1, true) then return ns.Spells:Pinned(key) and key or nil end
    if key:find("^item:") then
        local id = key:match("^item:([1-9]%d?%d?%d?%d?%d?%d?%d?%d?%d?)$")
        return id and ID(tonumber(id)) and key or nil
    end
    if key:find("^slot:") then return (key == "slot:13" or key == "slot:14") and key or nil end
    if key:find("^family:") then
        if not families then
            families = {}
            for _, family in ipairs(ns.Spells and ns.Spells.FAMILIES or {}) do families[family.key] = true end
        end
        return families[key] and key or nil
    end
    if key:find("@", 1, true) and not key:find("^[^@]+@%d%d?$") then return nil end
    return key
end

local function Within(value, limits)
    return Finite(value) and value >= limits[1] and value <= limits[2]
end

local function Bool(value)
    return type(value) == "boolean"
end

local function BarKey(value)
    return type(value) == "string" and ns.BAR_NAMES[value] ~= nil
end

local function Preset(value)
    return type(value) == "string" and ns.Layout ~= nil and ns.Layout:Preset(value) ~= nil
end

local function Place(value)
    return Finite(value) and math.abs(value) < 4000
end

-- Each bar setting a string carries (ns.SHARE_BAR_FIELDS), its check, and
-- its default, which a string leaves out.
local BAR_CHECKS = {
    size = function(v) return Within(v, ns.BAR_LIMITS.size) end,
    spacing = function(v) return Within(v, ns.BAR_LIMITS.spacing) end,
    perRow = function(v) return Within(v, ns.BAR_LIMITS.perRow) end,
    whenReady = function(v) return ns.WHEN_READY_NAMES[v] ~= nil end,
    outOfCombat = function(v) return ns.OUT_OF_COMBAT_NAMES[v] ~= nil end,
    showMissing = Bool, showNames = Bool, showTimer = Bool, showAuras = Bool, selfDebuffs = Bool,
    grow = function(v) return ns.GROW_NAMES[v] ~= nil end,
    wrap = function(v) return ns.WRAP_NAMES[v] ~= nil end,
    point = function(v) return ns.BAR_POINTS[v] == true end,
    x = Place, y = Place,
}
P.BAR_CHECKS = BAR_CHECKS
local BAR_DEFAULTS = { size = ns.BAR_LIMITS.size[3], spacing = ns.BAR_LIMITS.spacing[3], perRow = ns.BAR_LIMITS.perRow[3],
    whenReady = "show", outOfCombat = "show", showMissing = false, showNames = false, showTimer = true, showAuras = false,
    selfDebuffs = false, grow = "centre", wrap = "down" }
-- The layout's own settings; its rows and the bars taken out are lists.
local LAYOUT_CHECKS = {
    on = Bool, preset = Preset, base = Preset, left = BarKey, right = BarKey,
    gap = function(v) return Within(v, ns.ROW_GAP) end,
    spacing = function(v) return Within(v, ns.ICON_GAP) end,
}
local LAYOUT_FIELDS = { "on", "preset", "base", "left", "right", "gap", "spacing" }
local LOOK = {}
for _, key in ipairs(ns.SHARE_LOOK) do LOOK[key] = true end
-- What a string's top table holds: its name (n), the addon's version (a),
-- the bars' lists (l), joins (j), Cooldown pulse ticks (p) and Long ones
-- (q), spells added by name or ID (c), and the look and layout (g).
local KNOWN = { n = true, a = true, l = true, j = true, p = true, q = true, c = true, g = true }

-- Reading ----------------------------------------------------------------------------------------

local function Table(value)
    return type(value) == "table" and value or {}
end

-- A profile's name from a string: plain text, cut to fit, or nil.
local function SharedName(value)
    if type(value) ~= "string" then return nil end
    local name = value:gsub("[%c|]", ""):match("^%s*(.-)%s*$")
    if #name > ns.PROFILE_MAX then
        name = name:sub(1, ns.PROFILE_MAX):gsub("[\192-\255][\128-\191]*$", ""):gsub("%s+$", "")
    end
    return name ~= "" and name or nil
end

-- The look and layout from a string's g: only settings this version shares,
-- each checked.
local function Setup(g, Skip)
    local setup = { look = {}, bars = {}, layout = {}, colours = {} }
    for key, value in pairs(Table(g.s)) do
        if LOOK[key] and ns.Valid(key, value) then setup.look[key] = value else Skip() end
    end
    local bars = Table(g.b)
    for key in pairs(bars) do
        if not BarKey(key) then Skip() end
    end
    for _, key in ipairs(ns.BAR_KEYS) do
        local own = {}
        for field, value in pairs(Table(bars[key])) do
            local check = BAR_CHECKS[field]
            if check and check(value) then own[field] = value else Skip() end
        end
        setup.bars[key] = own
    end
    local layout, saved = setup.layout, Table(g.l)
    for field, value in pairs(saved) do
        local check = LAYOUT_CHECKS[field]
        if check then
            if check(value) then layout[field] = value else Skip() end
        elseif field ~= "above" and field ~= "below" and field ~= "hidden" then
            Skip()
        end
    end
    for _, place in ipairs({ "above", "below" }) do
        local rows = {}
        for _, key in ipairs(Table(saved[place])) do
            if BarKey(key) then rows[#rows + 1] = key else Skip() end
        end
        layout[place] = rows
    end
    layout.hidden = {}
    for key, out in pairs(Table(saved.hidden)) do
        if BarKey(key) and out == true then layout.hidden[key] = true else Skip() end
    end
    local count = 0
    for id, colour in pairs(Table(g.k)) do
        if ID(id) and ns.Valid("barColour", colour) and count < MAX_COLOURS then
            setup.colours[id], count = colour, count + 1
        else
            Skip()
        end
    end
    return setup
end

-- What a string's top table holds, checked: only what this version knows,
-- each value sane; anything else left out and counted (skipped).
local function Clean(data)
    local skipped = 0
    local function Skip() skipped = skipped + 1 end
    for key in pairs(data) do
        if not KNOWN[key] then Skip() end
    end
    local shared = { lists = {}, joins = {}, pick = {}, style = {}, added = {}, count = 0, picks = 0 }
    -- Each bar's entries, each once and at most the bars' limit; a spell
    -- sits on the Cooldowns or the Utility bar, not both.
    local lists, cooldown, listed = Table(data.l), {}, {}
    for key in pairs(lists) do
        if not BarKey(key) then Skip() end
    end
    for _, key in ipairs(ns.BAR_KEYS) do
        local list, seen, spells = {}, {}, not ns.AURA_BARS[key]
        for _, value in ipairs(Table(lists[key])) do
            local entry = Entry(value)
            if entry and not seen[entry] and not (spells and cooldown[entry]) and #list < ns.BAR_MAX_SPELLS then
                list[#list + 1] = entry
                seen[entry], listed[entry] = true, true
                if spells then cooldown[entry] = true end
            else
                Skip()
            end
        end
        shared.lists[key] = list
        shared.count = shared.count + #list
    end
    -- On the Buffs and Debuffs bars, names joined to the entry before them.
    for key, joins in pairs(Table(data.j)) do
        if ns.AURA_BARS[key] and type(joins) == "table" then
            local after, set = {}, {}
            for i, entry in ipairs(shared.lists[key]) do
                if i > 1 then after[entry] = true end
            end
            for name, on in pairs(joins) do
                if on == true and after[name] then set[name] = true else Skip() end
            end
            shared.joins[key] = set
        else
            Skip()
        end
    end
    -- The Cooldown pulse's ticks (true), and its cooldowns switched to Long.
    for _, list in ipairs({ { data.p, shared.pick, true }, { data.q, shared.style, "long" } }) do
        local count = 0
        for key, value in pairs(Table(list[1])) do
            if value == list[3] and Entry(key) and count < MAX_PICKS then
                list[2][key], count = value, count + 1
            else
                Skip()
            end
        end
    end
    for _ in pairs(shared.pick) do shared.picks = shared.picks + 1 end
    -- The spell IDs of entries added by name or ID, for the names on its
    -- bars. A spell pinned to one ID carries it in its key, and takes none.
    for name, ids in pairs(Table(data.c)) do
        local kept = {}
        if type(name) == "string" and listed[name] and not ns.Spells:Pinned(name) then
            for _, id in ipairs(Table(ids)) do
                if ID(id) and #kept < MAX_IDS then kept[#kept + 1] = id end
            end
        end
        if #kept > 0 then shared.added[name] = kept else Skip() end
    end
    if type(data.g) == "table" then
        shared.setup = Setup(data.g, Skip)
    elseif data.g ~= nil then
        Skip()
    end
    shared.name = SharedName(data.n)
    shared.version = type(data.a) == "string" and #data.a <= 32 and data.a:find("^[%w%.%-]+$") and data.a or nil
    shared.skipped = skipped
    return shared
end

-- A pasted string's profile: { name, lists, joins, pick, style, added,
-- setup (or nil), count (entries on its bars), picks, skipped }; or nil
-- and why not (nil only, for an empty box). The string is read from its
-- "FECM1:" wherever that is, so a whole chat message pasted (words or a
-- code block's mark before it) still reads, up to the last letter Base64
-- uses. Spaces and line breaks a chat put in it are passed over.
function P.Read(text)
    if type(text) ~= "string" then return nil end
    if #text > 2 * P.MAX_TEXT then return nil, P.TOO_LONG end
    text = text:gsub("%s+", "")
    if text:gsub("[`'\"]+", "") == "" then return nil end
    local from = text:find(P.PREFIX .. "%d+:")
    if not from then return nil, P.NOT_OURS end
    local format, body = text:match("^" .. P.PREFIX .. "(%d+):([A-Za-z0-9%+/=]*)", from)
    if #P.PREFIX + #format + 1 + #body > P.MAX_TEXT then return nil, P.TOO_LONG end
    -- Other words before it: one that doesn't read was likely cut or run
    -- into them, so the box says to copy only the string.
    local damaged = text:sub(1, from - 1):gsub("[`'\"]+", "") == "" and P.DAMAGED or P.PART
    format = tonumber(format)
    if format < 1 then return nil, P.NOT_OURS end
    if format > P.FORMAT then return nil, P.NEWER end
    local raw = Decode64(body)
    if not raw or #raw > MAX_DATA then return nil, damaged end
    local ok, data = Unpack(raw)
    if not ok then return nil, damaged end
    if type(data) ~= "table" or not (type(data.l) == "table" or type(data.g) == "table") then return nil, P.NOT_OURS end
    return Clean(data)
end

-- What a string holds, in a line: "Holds 12 bar entries and 3 pulse ticks,
-- with its look and layout."
function P.Describe(shared)
    local text = ("Holds %d bar %s"):format(shared.count, shared.count == 1 and "entry" or "entries")
    if shared.picks > 0 then text = text .. (" and %d pulse %s"):format(shared.picks, shared.picks == 1 and "tick" or "ticks") end
    text = text .. (shared.setup and ", with its look and layout." or ".")
    if shared.skipped > 0 then
        text = text .. (" %d left out, as this version doesn't use %s."):format(shared.skipped, shared.skipped == 1 and "it" or "them")
    end
    return text
end

-- Making one -------------------------------------------------------------------------------------

-- A list's names and keys that read back, in order.
local function Entries(list)
    local out = {}
    for _, value in ipairs(list) do
        if Entry(value) then out[#out + 1] = value end
    end
    return out
end

local function IDs(list)
    local out = {}
    for _, id in ipairs(Table(list)) do
        if ID(id) and #out < MAX_IDS then out[#out + 1] = id end
    end
    return out
end

-- A pulse list's keys that read back with the one value each keeps.
local function Picks(list, keep)
    local out = {}
    for key, value in pairs(list) do
        if value == keep and Entry(key) then out[key] = value end
    end
    return out
end

-- What a layout works out for each bar it holds (Layout.lua L:Stack), from
-- wherever the display is, so a string needn't carry it.
local STACKED = { point = true, x = true, y = true, grow = true, wrap = true }

-- The look and layout as they are now: the look and each bar's settings
-- where they differ from the defaults, the layout, and Tracked Bar colours.
local function SetupNow()
    local look, bars, colours = {}, {}, {}
    for _, key in ipairs(ns.SHARE_LOOK) do
        local value = ns.Get(key)
        if value ~= ns.DEFAULTS[key] then look[key] = value end
    end
    local saved, layout = ns.LayoutData(), { hidden = {} }
    for _, key in ipairs(ns.BAR_KEYS) do
        local data, own, stacked = ns.BarData(key), {}, saved.on and not saved.hidden[key]
        for _, field in ipairs(ns.SHARE_BAR_FIELDS) do
            local value = data[field]
            if value ~= nil and value ~= BAR_DEFAULTS[field] and not (stacked and STACKED[field]) then own[field] = value end
        end
        bars[key] = own
    end
    for _, field in ipairs(LAYOUT_FIELDS) do layout[field] = saved[field] end
    layout.above, layout.below = Entries(saved.above), Entries(saved.below)
    for key in pairs(saved.hidden) do layout.hidden[key] = true end
    for id, colour in pairs(ns.BarColours()) do
        if ID(id) then colours[id] = colour end
    end
    return { s = look, b = bars, l = layout, k = colours }
end

-- The profile you're on, with the look and layout, as a share string; or
-- nil and why not. It leaves out the profile's name: by default that is your
-- character's name, and strings get posted in public (the user's call,
-- 2026-10-08). The importer names it, or gets "Imported".
function P.Export()
    if not ns.ProfileName() then return nil, "Your profile hasn't loaded yet." end
    local data = { a = ns.Version(), l = {}, g = SetupNow() }
    local custom, added, joins = ns.CustomSpells(), {}, {}
    for _, key in ipairs(ns.BAR_KEYS) do
        data.l[key] = Entries(ns.ActiveList(key))
        for _, entry in ipairs(data.l[key]) do
            if not ns.Spells:Pinned(entry) and type(custom[entry]) == "table" and #IDs(custom[entry]) > 0 then
                added[entry] = IDs(custom[entry])
            end
        end
    end
    for key in pairs(ns.AURA_BARS) do
        local set = Picks(ns.Joins(key), true)
        if next(set) then joins[key] = set end
    end
    local picks, styles = Picks(ns.PulsePicks(), true), Picks(ns.PulseStyles(), "long")
    if next(joins) then data.j = joins end
    if next(picks) then data.p = picks end
    if next(styles) then data.q = styles end
    if next(added) then data.c = added end
    local out = {}
    Pack(data, out)
    local raw = table.concat(out)
    if #raw > MAX_DATA then return nil, P.TOO_MUCH end
    local text = P.PREFIX .. P.FORMAT .. ":" .. Encode64(raw)
    -- Only a string Import can read: within each limit reading keeps (its
    -- length in letters, and how many values it holds).
    if not P.Read(text) then return nil, P.TOO_MUCH end
    return text
end

-- After a look and layout came in: everything that shows them, as the Look,
-- Layout, Cast bar, Raid Timers and Cooldown pulse pages do on a change.
-- Undo on the Layout page is for a layout you picked, so it goes.
local function Redraw()
    if ns.Layout then ns.Layout.undo, ns.Layout.moved = nil, nil end
    ns.Style:ApplyFont()
    local B = ns.Bars
    if B and B.started then
        B:Rebuild()
        B:ApplyFont()
        B:ApplyDecor()
        B:ApplyGlow()
        B:ApplyKeybinds()
    end
    local skin = ns.Skin
    if skin and skin.started then
        skin:ApplyBarLook()
        skin:ApplyDecor()
        skin:ApplyKeybinds()
    end
    if ns.Resource and ns.Resource.started then ns.Resource:Apply() end
    if ns.CastBar and ns.CastBar.started then ns.CastBar:Apply() end
    if ns.RaidTimers and ns.RaidTimers.started then ns.RaidTimers:Apply() end
    if ns.Pulse and ns.Pulse.started then ns.Pulse:Apply() end
end

-- A string read by P.Read as a new profile (Core.lua's ns.ImportProfile),
-- switched to; with its look and layout too, if asked. True and what
-- happened, or false and why not.
function P.Import(text, shared, withLook)
    local ok, message, name = ns.ImportProfile(text, shared, withLook)
    if not ok then return false, message end
    if withLook then Redraw() end
    if not ns.Get("useBars") then message = message .. " Your bars are off: tick Use my bars on General." end
    return true, message, name
end

-- The box ----------------------------------------------------------------------------------------
-- Over the whole window, as "Are you sure?" is (that one shows over it).
-- Share shows the string to copy; Import takes one pasted in, says what it
-- holds before anything changes, then makes it a new profile.

local BOX_WIDTH, INNER = 480, 452
local IMPORT_HEIGHT, EXPORT_HEIGHT = 252, 136
local EXPORT_DETAIL = "Your profile, with your bars' look and layout, as text. Press Ctrl+C to copy it, then paste it"
    .. " where you like, such as Discord."
local IMPORT_DETAIL = "Paste a profile someone shared. It becomes a new profile, and yours stays as it is."
    .. " Spells your class can't use don't show."
local LOOK_ON = "Your bar sizes, spots, layout and look are replaced by its own, on every character."
local LOOK_OFF = "Unticked, only its bars' spells and pulse ticks come, in your own look and layout."
local LOOK_ASK = "Your bar sizes, spots, layout and look change to the shared ones, on every character."
    .. " To keep a copy of yours, Share it first."
P.LOOK_ON, P.LOOK_OFF = LOOK_ON, LOOK_OFF

-- A text box's text set from here, with its grey placeholder only while empty.
local function SetBoxText(input, text)
    input:SetText(text)
    input.placeholder:SetShown(text == "" and not input:HasFocus())
end

-- Greyed out and unclickable while it can't be used; still says why on hover.
local function Usable(button, usable)
    button.usable = usable
    button:SetEnabled(usable)
    if button.SetMotionScriptsWhileDisabled then button:SetMotionScriptsWhileDisabled(true) end
    button:SetAlpha(usable and 1 or .35)
end

function P.BuildBox(window)
    local shade = CreateFrame("Frame", nil, window)
    shade:SetAllPoints()
    shade:SetFrameLevel(window:GetFrameLevel() + 70)
    shade:EnableMouse(true) -- nothing behind it can be clicked meanwhile
    local dim = shade:CreateTexture(nil, "BACKGROUND")
    dim:SetAllPoints()
    dim:SetColorTexture(0, 0, 0, .45)
    shade:Hide()
    window:Hint(shade, "Close the box first: Close or Cancel.")

    local box = CreateFrame("Frame", nil, shade, "BackdropTemplate")
    box:SetSize(BOX_WIDTH, IMPORT_HEIGHT)
    box:SetPoint("CENTER")
    T:Flat(box, T.PANEL, T.CONTROL_BORDER)
    box:EnableMouse(true)
    window:Hint(box, function()
        return box.mode == "export" and "Press Ctrl+C to copy the text, then Close."
            or "Paste a profile, check what it holds, then make it a new profile."
    end)
    box.shade = shade
    box.title = T:Heading(box, "")
    box.title:SetPoint("TOPLEFT", 14, -14)
    box.detail = T:Text(box, "GameFontHighlightSmall", T.MUTED)
    box.detail:SetPoint("TOPLEFT", 14, -34)
    box.detail:SetWidth(INNER)

    local function Close()
        box.shared, box.mode = nil, nil
        shade:Hide()
    end
    box.Close = Close

    -- The string to copy: it stays as it is, selected. (Share only makes
    -- strings Import reads, so never longer than P.MAX_TEXT: this box never
    -- cuts one.)
    local copy = T:Input(box, "", INNER)
    copy:SetPoint("TOPLEFT", 14, -68)
    copy:SetMaxLetters(P.MAX_TEXT + 1)
    copy:SetScript("OnTextChanged", function(self)
        if box.mode ~= "export" or box.restoring or self:GetText() == box.text then return end
        box.restoring = true -- putting it back changes the text once more
        self:SetText(box.text or "")
        self:HighlightText()
        box.restoring = nil
    end)
    copy:HookScript("OnEditFocusGained", function(self) self:HighlightText() end)
    -- A click in it selects it all again (it already has the focus, and a
    -- click alone would only place the cursor), so Ctrl+C still copies it all.
    copy:SetScript("OnMouseUp", function(self) self:HighlightText() end)
    copy:SetScript("OnEscapePressed", Close)
    copy:SetScript("OnEnterPressed", Close)
    window:Hint(copy, "Your profile as text. Press Ctrl+C to copy it.")
    box.copy = copy

    -- The string pasted in, read as it changes.
    local paste = T:Input(box, "Paste a profile here: Ctrl+V", INNER)
    paste:SetPoint("TOPLEFT", 14, -68)
    paste:SetMaxLetters(P.MAX_TEXT + 1)
    paste:SetScript("OnEscapePressed", Close)
    window:Hint(paste, "Paste a profile here with Ctrl+V. Nothing changes until you make it a new profile.")
    box.paste = paste
    local status = T:Text(box, "GameFontHighlightSmall", T.MUTED)
    status:SetPoint("TOPLEFT", 14, -96)
    status:SetWidth(INNER)
    box.status = status

    -- The new profile's name: the one it came with, or one typed.
    local nameLabel = T:Text(box, "GameFontHighlightSmall")
    nameLabel:SetPoint("TOPLEFT", 14, -134)
    nameLabel:SetText("New profile's name")
    local name = T:Input(box, P.IMPORTED, 300)
    name:SetPoint("TOPLEFT", 140, -130)
    name:SetMaxLetters(ns.PROFILE_MAX)
    name:SetScript("OnEscapePressed", Close)
    window:Hint(name, "The new profile's name. A name already taken gets a number after it.")
    box.name, box.nameLabel = name, nameLabel

    -- Its look and layout as well, only when ticked: off each time.
    local lookNote = T:Text(box, "GameFontHighlightSmall", T.MUTED)
    lookNote:SetPoint("TOPLEFT", 32, -180)
    lookNote:SetWidth(INNER - 18)
    local look = T:Check(box, "Also use its look and layout (Needs testing)", function(self)
        lookNote:SetText(self:GetChecked() and LOOK_ON or LOOK_OFF)
    end)
    look:SetPoint("TOPLEFT", 14, -160)
    window:Hint(look, "Its bar sizes, spots, layout and look in place of yours, on every character. It asks first.")
    box.look, box.lookNote = look, lookNote

    local make = T:Button(box, "Make new profile", 130, 22)
    make:SetPoint("BOTTOMRIGHT", -14, 14)
    window:Hint(make, function()
        if not box.shared then return "Paste a profile first." end
        return "Make it a new profile and switch to it. The profile you're on stays as it is."
    end)
    local no = T:Button(box, "Cancel", 90, 22)
    no:SetScript("OnClick", Close)
    window:Hint(no, function() return box.mode == "export" and "Close the box." or "Close the box. Nothing changes." end)
    box.make, box.no = make, no

    local function Status(text, colour)
        status:SetText(text)
        status:SetTextColor(colour[1], colour[2], colour[3])
    end

    -- Reads what's in the box and says what it holds, or why it can't be read.
    -- The name box takes the string's own name, in place of one an earlier
    -- string put there, never over a name typed.
    function box:Check()
        local text = paste:GetText() or ""
        local read, shared, why = pcall(P.Read, text)
        if not read then shared, why = nil, P.DAMAGED end
        box.shared = shared
        local typed = name:GetText() or ""
        local auto = box.autoName ~= nil and typed == box.autoName
        if shared then
            Status(P.Describe(shared), T.TEXT)
            if not name:HasFocus() and (typed == "" or auto) then
                SetBoxText(name, shared.name or "")
                box.autoName = shared.name
            end
        else
            Status(why or "Paste a profile to see what it holds.", why and T.WARN or T.MUTED)
            if auto and text == "" then
                SetBoxText(name, "")
                box.autoName = nil
            end
        end
        local setup = shared ~= nil and shared.setup ~= nil
        if not setup then look:SetChecked(false) end
        look:SetShown(setup)
        lookNote:SetShown(setup)
        lookNote:SetText(look:GetChecked() and LOOK_ON or LOOK_OFF)
        Usable(make, shared ~= nil)
    end
    paste:SetScript("OnTextChanged", function() box:Check() end)

    make:SetScript("OnClick", function()
        if box.mode ~= "import" or not box.shared then return end
        local shared, withLook = box.shared, look:IsShown() and look:GetChecked()
        local typed = name:GetText() or ""
        if typed:match("^%s*$") then typed = shared.name or P.IMPORTED end
        local function Go()
            local ok, message = P.Import(typed, shared, withLook)
            if not ok then return Status(message, T.WARN) end
            Close()
            if window.profilePanel then window.profilePanel:Hide() end
            window:Say(message)
            window:Refresh()
        end
        if withLook then
            -- A click doesn't take the keyboard from a text box: while the
            -- question is up, keys would still type into the box behind it,
            -- and Escape would close the box but leave the question.
            paste:ClearFocus()
            name:ClearFocus()
            window:Ask("Use its look and layout too?", LOOK_ASK, "Use them", Go)
        else
            Go()
        end
    end)

    -- mode: "export" with the string, or "import".
    function box:Open(mode, text)
        box.mode, box.text, box.shared, box.autoName = mode, text, nil, nil
        if window.profilePanel then window.profilePanel:Hide() end
        local export = mode == "export"
        box.title:SetText(export and "SHARE A PROFILE" or "IMPORT A PROFILE")
        box.detail:SetText(export and EXPORT_DETAIL or IMPORT_DETAIL)
        copy:SetShown(export)
        for _, part in ipairs({ paste, status, nameLabel, name, make }) do part:SetShown(not export) end
        look:SetChecked(false)
        look:SetShown(false)
        lookNote:SetShown(false)
        no:ClearAllPoints()
        if export then no:SetPoint("BOTTOMRIGHT", -14, 14) else no:SetPoint("BOTTOMLEFT", 14, 14) end
        no:SetLabel(export and "Close" or "Cancel")
        box:SetHeight(export and EXPORT_HEIGHT or IMPORT_HEIGHT)
        shade:Show()
        if export then
            copy:SetText(text or "")
            copy:HighlightText()
            copy:SetFocus()
        else
            SetBoxText(paste, "")
            SetBoxText(name, "")
            box:Check()
            paste:SetFocus()
        end
    end
    window:HookScript("OnHide", Close)
    window.shareBox = box
    return box
end
