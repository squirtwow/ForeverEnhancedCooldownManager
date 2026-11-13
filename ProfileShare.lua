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
-- "item:<id>", "slot:13" or "slot:14" (the trinkets), "ammo", "shards" (Soul
-- Shards), "hand:main" or "hand:off" (a hand's weapon enchant), "trinket:1"
-- or "trinket:2" (a trinket's buff), or a healthstone or potion family; or
-- the Cooldown pulse's key for a proc, "proc:" and its buff's ID, one any
-- class has (Pulse.lua P.PROCS). Nil for anything else. (A version before
-- the hands or the trinkets keeps those as names it doesn't know: shown for
-- no one.)
local function Entry(value)
    local key = Word(value)
    if not key then return nil end
    if key:find("#", 1, true) then return ns.Spells:Pinned(key) and key or nil end
    if key:find("^hand:") then return ns.Spells.HAND_KEYS and ns.Spells.HAND_KEYS[key] and key or nil end
    if key:find("^trinket:") then return ns.Spells.TRINKET_KEYS and ns.Spells.TRINKET_KEYS[key] and key or nil end
    if key:find("^proc:") then
        local id = tonumber(key:match("^proc:([1-9]%d?%d?%d?%d?%d?%d?%d?%d?%d?)$"))
        for _, list in pairs(ns.Pulse and ns.Pulse.PROCS or {}) do
            for _, ids in ipairs(list) do
                if ids[1] == id then return key end
            end
        end
        return nil
    end
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

-- The same for an entry on a bar's list (key: that bar; nil for a form's
-- list, which is a cooldown bar's): a hand's weapon enchant or a trinket's
-- buff only on a Buffs bar, as Bars.lua's B:Fits keeps them, so an edited
-- string can't put one where it would be a spell icon with no spell, and a
-- proc's pulse key on none. Nil for anything else.
local function BarEntry(value, key)
    local entry = Entry(value)
    if entry and entry:find("^proc:") then return nil end
    if entry and (entry:find("^hand:") or entry:find("^trinket:")) and not (key and ns.BAR_KIND[key] == "buff") then return nil end
    return entry
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
    onCooldown = function(v) return ns.WHEN_READY_NAMES[v] ~= nil end,
    dimUnusable = Bool,
    dimOpacity = function(v) return Within(v, ns.BAR_LIMITS.dimOpacity) end,
    outOfCombat = function(v) return ns.OUT_OF_COMBAT_NAMES[v] ~= nil end,
    showMissing = Bool, onlyMissing = Bool, greyedNoTarget = Bool, showNames = Bool, showTimer = Bool, showAuras = Bool,
    showGCD = Bool, selfDebuffs = Bool,
    grow = function(v) return ns.GROW_NAMES[v] ~= nil end,
    wrap = function(v) return ns.WRAP_NAMES[v] ~= nil end,
    point = function(v) return ns.BAR_POINTS[v] == true end,
    x = Place, y = Place,
    tickAt = function(v) return ns.TICK_AT_NAMES[v] ~= nil end,
    tickSize = function(v) return Within(v, ns.TICK_SIZE) end,
    tickColour = function(v) return ns.COUNT_COLOURS[v] ~= nil or v == ns.CUSTOM end,
    tickFrom = function(v) return v == 0 or v == 1 end,
    tickEdge = Bool,
    -- Custom's own colour beside it: six hex digits as kept, or none.
    tickCustom = function(v) return v == "" or ns.Hex(v) == v end,
}
P.BAR_CHECKS = BAR_CHECKS
local BAR_DEFAULTS = { size = ns.BAR_LIMITS.size[3], spacing = ns.BAR_LIMITS.spacing[3], perRow = ns.BAR_LIMITS.perRow[3],
    whenReady = "show", onCooldown = "show", dimUnusable = false, dimOpacity = ns.BAR_LIMITS.dimOpacity[3],
    outOfCombat = "show", showMissing = false, onlyMissing = false, greyedNoTarget = false, showNames = false, showTimer = true,
    showAuras = false, showGCD = false, selfDebuffs = false, grow = "centre", wrap = "down",
    tickAt = "TOPLEFT", tickSize = ns.TICK_SIZE[3], tickColour = "white", tickFrom = 1, tickEdge = false, tickCustom = "" }
-- The layout's own settings; its rows and the bars taken out are lists.
local LAYOUT_CHECKS = {
    on = Bool, preset = Preset, base = Preset, left = BarKey, right = BarKey,
    gap = function(v) return Within(v, ns.ROW_GAP) end,
    spacing = function(v) return Within(v, ns.ICON_GAP) end,
}
local LAYOUT_FIELDS = { "on", "preset", "base", "left", "right", "gap", "spacing" }
local LOOK = {}
for _, key in ipairs(ns.SHARE_LOOK) do LOOK[key] = true end
-- Icon details' Icons goes in the look as I = "b", not iconStyle =
-- "blizzard", so a full profile drawn like Blizzard's still fits one
-- Discord message (under 2000 letters). Read back either way.
local SHORT_ICONS, LONG_ICONS = { blizzard = "b" }, { b = "blizzard" }
-- The parts a string carries the ones on of (ns.SHARE_PARTS), by their letter.
local PART = {}
for _, part in ipairs(ns.SHARE_PARTS) do PART[part.code] = part end
-- The layout's settings at their default, which a string leaves out
-- (ns.LayoutData puts them back).
local LAYOUT_DEFAULTS = { on = false, gap = ns.ROW_GAP[3], spacing = ns.ICON_GAP[3] }
-- What a string's top table holds: its name (n), the addon's version (a),
-- the bars' lists (l), each form's lists (f: Swap with my form, form ->
-- bar -> list) and the bars swapping with your form (w: bar -> true),
-- joins (j), the buffs shown only while they're missing (m: "buff" -> name
-- -> true, Only when missing), Cooldown pulse ticks (p) and Long ones (q),
-- spells added by name or ID (c), the look and layout (g), each entry's
-- own countdown font and size (i: entry -> { font, size }, settings per spell),
-- the aura bars' warned entries (t: "buff"/"debuff" -> name -> seconds,
-- Warn at N seconds left), the extra bars (x: "debuff2" -> true, Extra bars;
-- their lists in l, their settings in g) and icons' own sizes (z: bar ->
-- name -> percent).
local KNOWN = { n = true, a = true, l = true, f = true, w = true, j = true, m = true, p = true, q = true, c = true, g = true,
    i = true, t = true, x = true, z = true }
local MAX_LOOKS = 200 -- entries with a look of their own

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
-- each checked. A string made by 1.6.0 has Swap with my form with each
-- bar's settings: true or false read (true on the Cooldowns or Utility bar
-- goes into swap, for the profile), anything else left out.
local function Setup(g, Skip, swap)
    local setup = { look = {}, bars = {}, layout = {}, colours = {}, custom = {}, parts = {} }
    for key, value in pairs(Table(g.s)) do
        if key == "I" then key, value = "iconStyle", LONG_ICONS[value] or value end
        if LOOK[key] and ns.Valid(key, value) then setup.look[key] = value else Skip() end
    end
    -- The parts it has on (o): a letter each, those this version knows. A
    -- string made before them has none.
    if type(g.o) == "string" and #g.o <= MAX_WORD then
        for i = 1, #g.o do
            local part = PART[g.o:sub(i, i)]
            if part then setup.parts[part.key] = true else Skip() end
        end
    elseif g.o ~= nil then
        Skip()
    end
    -- Custom only with its own colour beside it.
    for _, key in ipairs(ns.COLOUR_SETTINGS) do
        if setup.look[key] == ns.CUSTOM and not ns.Hex(setup.look[key .. "Custom"]) then
            setup.look[key] = nil
            Skip()
        end
    end
    local bars = Table(g.b)
    for key in pairs(bars) do
        if not BarKey(key) then Skip() end
    end
    -- Every bar there can be: an extra bar's settings only when it has some.
    for _, key in ipairs(ns.ALL_BAR_KEYS) do
        local own = {}
        for field, value in pairs(Table(bars[key])) do
            local check = BAR_CHECKS[field]
            if check and check(value) then
                own[field] = value
            elseif field == "swapForm" and Bool(value) then
                if value and ns.CanSwap(key) then swap[key] = true end
            else
                Skip()
            end
        end
        if own.tickColour == ns.CUSTOM and not ns.Hex(own.tickCustom) then
            own.tickColour = nil
            Skip()
        end
        if ns.EXTRAS_OF[key] or type(bars[key]) == "table" then setup.bars[key] = own end
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
    -- Tracked Bar colours (k), and for each in Custom its own colour (h).
    local count, hexes = 0, Table(g.h)
    for id, colour in pairs(Table(g.k)) do
        local hex = colour == ns.CUSTOM and ns.Hex(hexes[id])
        if ID(id) and ns.Valid("barColour", colour) and (colour ~= ns.CUSTOM or hex) and count < MAX_COLOURS then
            setup.colours[id], count = colour, count + 1
            if hex then setup.custom[id] = hex end
        else
            Skip()
        end
    end
    for id in pairs(hexes) do
        if not setup.custom[id] then Skip() end
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
    local shared = { lists = {}, forms = {}, swap = {}, joins = {}, only = {}, pick = {}, style = {}, added = {}, looks = {}, warns = {},
        extras = {}, sizes = {}, count = 0, picks = 0 }
    -- Its extra bars (Extra bars, Core.lua): the keys this version knows,
    -- true each, four at most (Cooldowns 3 and the like too; a version from
    -- before them counts those as left out).
    if data.x ~= nil and type(data.x) ~= "table" then Skip() end
    local x, extras = Table(data.x), 0
    for key, on in pairs(x) do
        if not (BarKey(key) and not ns.EXTRAS_OF[key] and on == true) then Skip() end
    end
    for _, key in ipairs(ns.EXTRA_BAR_KEYS) do
        if x[key] == true then
            if extras < ns.EXTRA_MAX then shared.extras[key], extras = true, extras + 1 else Skip() end
        end
    end
    -- Each bar's entries, each once and at most the bars' limit; a spell
    -- sits on one cooldown bar (Cooldowns, Utility, or an extra one), not
    -- two. An extra bar's only with it.
    local lists, cooldown, listed = Table(data.l), {}, {}
    for key in pairs(lists) do
        if not BarKey(key) then Skip() end
    end
    -- (The four first: one also on an extra cooldown bar stays on theirs, as
    -- Core.lua's ns.KeepApart keeps it.)
    local order = {}
    for _, key in ipairs(ns.BASE_BAR_KEYS) do order[#order + 1] = key end
    for _, key in ipairs(ns.EXTRA_BAR_KEYS) do order[#order + 1] = key end
    for _, key in ipairs(order) do
        if ns.EXTRAS_OF[key] or shared.extras[key] then
            local list, seen, spells = {}, {}, not ns.AURA_BARS[key]
            for _, value in ipairs(Table(lists[key])) do
                local entry = BarEntry(value, key)
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
        elseif lists[key] ~= nil then
            Skip()
        end
    end
    -- Each form's own lists for the Cooldowns and Utility bars (Swap with my
    -- form), only the ones it has, each checked as a bar's is: an entry on
    -- one of a form's two bars, not both.
    if data.f ~= nil and type(data.f) ~= "table" then Skip() end
    for form, own in pairs(Table(data.f)) do
        if ns.OwnFormList(form) and type(own) == "table" then
            local kept, cooldown = {}, {}
            for key, values in pairs(own) do
                if not (ns.CanSwap(key) and type(values) == "table") then Skip() end
            end
            for _, key in ipairs(ns.BASE_BAR_KEYS) do
                if ns.CanSwap(key) and type(own[key]) == "table" then
                    local list = {}
                    for _, value in ipairs(own[key]) do
                        local entry = BarEntry(value)
                        if entry and not cooldown[entry] and #list < ns.BAR_MAX_SPELLS then
                            list[#list + 1] = entry
                            cooldown[entry], listed[entry] = true, true
                        else
                            Skip()
                        end
                    end
                    -- Not counted with the bars' entries: each starts as a
                    -- copy of a bar's own (P.Describe counts the forms).
                    kept[key] = list
                end
            end
            shared.forms[form] = kept
        else
            Skip()
        end
    end
    -- The bars swapping with your form: the Cooldowns and Utility bars, true each.
    if data.w ~= nil and type(data.w) ~= "table" then Skip() end
    for key, on in pairs(Table(data.w)) do
        if ns.CanSwap(key) and on == true then shared.swap[key] = true else Skip() end
    end
    -- On the Buffs and Debuffs bars (an extra one with it), names joined to
    -- the entry before them.
    for key, joins in pairs(Table(data.j)) do
        if ns.AURA_BARS[key] and shared.lists[key] and type(joins) == "table" then
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
    -- On a Buffs bar (Buffs 2 with it), the buffs shown only while they're
    -- missing (Only when missing): names on its list, true each.
    if data.m ~= nil and type(data.m) ~= "table" then Skip() end
    for key, set in pairs(Table(data.m)) do
        if ns.BAR_KIND[key] == "buff" and shared.lists[key] and type(set) == "table" then
            local listed, kept = {}, {}
            for _, entry in ipairs(shared.lists[key]) do listed[entry] = true end
            for name, on in pairs(set) do
                if on == true and listed[name] then kept[name] = true else Skip() end
            end
            shared.only[key] = kept
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
    -- Each entry's own countdown font and size (settings per spell): only
    -- names on its lists, each field checked. A field this version doesn't
    -- know, or a font or size it can't use, is left out and counted.
    if data.i ~= nil and type(data.i) ~= "table" then Skip() end
    local looks = 0
    for name, look in pairs(Table(data.i)) do
        local kept = type(name) == "string" and listed[name] and looks < MAX_LOOKS and ns.CleanSpellLook(look) or nil
        if kept then
            for field, value in pairs(look) do
                if kept[field] ~= value then Skip() end
            end
            shared.looks[name], looks = kept, looks + 1
        else
            Skip()
        end
    end
    -- The Buffs and Debuffs bars' warned entries (Warn at): names on that
    -- bar's list, each a whole number of seconds up to an hour.
    if data.t ~= nil and type(data.t) ~= "table" then Skip() end
    for key, set in pairs(Table(data.t)) do
        if ns.AURA_BARS[key] and type(set) == "table" then
            local onBar, kept = {}, {}
            for _, entry in ipairs(shared.lists[key] or {}) do onBar[entry] = true end
            for name, seconds in pairs(set) do
                if onBar[name] and ns.WarnValue(seconds) then kept[name] = seconds else Skip() end
            end
            if next(kept) then shared.warns[key] = kept end
        else
            Skip()
        end
    end
    -- Each icon's own size (settings per spell): a bar the string has, names
    -- on its lists (a form's too), each a percent this version keeps.
    if data.z ~= nil and type(data.z) ~= "table" then Skip() end
    for key, set in pairs(Table(data.z)) do
        if shared.lists[key] and type(set) == "table" then
            local onBar, kept = {}, {}
            for _, entry in ipairs(shared.lists[key]) do onBar[entry] = true end
            for _, own in pairs(shared.forms) do
                for _, entry in ipairs(own[key] or {}) do onBar[entry] = true end
            end
            for name, percent in pairs(set) do
                if onBar[name] and ns.SizeValue(percent) then kept[name] = percent else Skip() end
            end
            if next(kept) then shared.sizes[key] = kept end
        else
            Skip()
        end
    end
    if type(data.g) == "table" then
        shared.setup = Setup(data.g, Skip, shared.swap)
    elseif data.g ~= nil then
        Skip()
    end
    shared.name = SharedName(data.n)
    shared.version = type(data.a) == "string" and #data.a <= 32 and data.a:find("^[%w%.%-]+$") and data.a or nil
    shared.skipped = skipped
    return shared
end

-- A pasted string's profile: { name, lists, forms, swap, joins, only, pick,
-- style, added, looks, warns, setup (or nil), count (entries on its bars), picks, skipped }; or nil
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
-- with icons for 2 forms and its look and layout." Bar entries are the
-- bars' own lists; the forms are those with lists of their own (Swap with
-- my form), whose entries would count each spell again.
function P.Describe(shared)
    local text = ("Holds %d bar %s"):format(shared.count, shared.count == 1 and "entry" or "entries")
    if shared.picks > 0 then text = text .. (" and %d pulse %s"):format(shared.picks, shared.picks == 1 and "tick" or "ticks") end
    local forms, with = 0, {}
    for _, lists in pairs(shared.forms or {}) do
        if next(lists) then forms = forms + 1 end
    end
    if forms > 0 then with[#with + 1] = ("icons for %d %s"):format(forms, forms == 1 and "form" or "forms") end
    local looks = 0
    for _ in pairs(shared.looks or {}) do looks = looks + 1 end
    if looks > 0 then with[#with + 1] = ("own countdowns for %d %s"):format(looks, looks == 1 and "spell" or "spells") end
    local warns = 0
    for _, set in pairs(shared.warns or {}) do
        for _ in pairs(set) do warns = warns + 1 end
    end
    if warns > 0 then with[#with + 1] = ("low-time warnings for %d %s"):format(warns, warns == 1 and "aura" or "auras") end
    local extras, sizes = 0, 0
    for _ in pairs(shared.extras or {}) do extras = extras + 1 end
    for _, set in pairs(shared.sizes or {}) do
        for _ in pairs(set) do sizes = sizes + 1 end
    end
    if extras > 0 then with[#with + 1] = extras == 1 and "an extra bar" or ("%d extra bars"):format(extras) end
    if sizes > 0 then with[#with + 1] = ("own sizes for %d %s"):format(sizes, sizes == 1 and "icon" or "icons") end
    if shared.setup then with[#with + 1] = "its look and layout" end
    -- A list of them: commas, then "and" before the last.
    local last = table.remove(with)
    if last then text = text .. ", with " .. (#with > 0 and (table.concat(with, ", ") .. " and ") or "") .. last end
    text = text .. "."
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
-- where they differ from the defaults, the layout, Tracked Bar colours, and
-- the parts you have on.
local function SetupNow()
    local look, bars, colours = {}, {}, {}
    for _, key in ipairs(ns.SHARE_LOOK) do
        local value = ns.Get(key)
        if value ~= ns.DEFAULTS[key] then look[key] = value end
    end
    if look.iconStyle then look.I, look.iconStyle = SHORT_ICONS[look.iconStyle] or look.iconStyle, nil end
    local saved, layout = ns.LayoutData(), { hidden = {} }
    for _, key in ipairs(ns.BAR_KEYS) do
        local data, own, stacked = ns.BarData(key), {}, saved.on and not saved.hidden[key]
        for _, field in ipairs(ns.SHARE_BAR_FIELDS) do
            local value = data[field]
            if value ~= nil and value ~= BAR_DEFAULTS[field] and not (stacked and STACKED[field]) then own[field] = value end
        end
        bars[key] = own
    end
    for _, field in ipairs(LAYOUT_FIELDS) do
        if saved[field] ~= LAYOUT_DEFAULTS[field] then layout[field] = saved[field] end
    end
    layout.above, layout.below = Entries(saved.above), Entries(saved.below)
    for key in pairs(saved.hidden) do layout.hidden[key] = true end
    local picked, custom, hexes = ns.BarColours()
    for id, colour in pairs(picked) do
        if ID(id) then colours[id] = colour end
        -- Custom's own colour, only for a bar in Custom.
        if ID(id) and colour == ns.CUSTOM and custom[id] then
            hexes = hexes or {}
            hexes[id] = custom[id]
        end
    end
    local parts = {}
    for _, part in ipairs(ns.SHARE_PARTS) do
        if ns.GetSaved(part.key) == true then parts[#parts + 1] = part.code end
    end
    return { s = look, b = bars, l = layout, k = colours, h = hexes, o = #parts > 0 and table.concat(parts) or nil }
end

-- The profile you're on, with the look and layout, as a share string; or
-- nil and why not. It leaves out the profile's name: by default that is your
-- character's name, and strings get posted in public (the user's call,
-- 2026-10-08). The importer names it, or gets "Imported".
function P.Export()
    if not ns.ProfileName() then return nil, "Your profile hasn't loaded yet." end
    local data = { a = ns.Version(), l = {}, g = SetupNow() }
    local custom, added, joins, forms = ns.CustomSpells(), {}, {}, {}
    -- A list's entries that read back, and the IDs of those added by name or ID.
    local function Listed(list)
        local out = Entries(list)
        for _, entry in ipairs(out) do
            if not ns.Spells:Pinned(entry) and type(custom[entry]) == "table" and #IDs(custom[entry]) > 0 then
                added[entry] = IDs(custom[entry])
            end
        end
        return out
    end
    -- Each bar's normal list (whatever the form you're in), then each
    -- form's own lists (Swap with my form), as they are.
    -- (Your extra bars' too, and which they are.)
    local store, extras = ns.ProfileLists(), {}
    for _, key in ipairs(ns.BAR_KEYS) do
        data.l[key] = Listed(Table(store[key]))
        if not ns.EXTRAS_OF[key] then extras[key] = true end
    end
    if next(extras) then data.x = extras end
    for form, own in pairs(Table(store.forms)) do
        if ns.OwnFormList(form) and type(own) == "table" then
            local lists = {}
            for _, key in ipairs(ns.BASE_BAR_KEYS) do
                if ns.CanSwap(key) and type(own[key]) == "table" then lists[key] = Listed(own[key]) end
            end
            if next(lists) then forms[form] = lists end
        end
    end
    if next(forms) then data.f = forms end
    local swap = {}
    for _, key in ipairs(ns.BAR_KEYS) do
        if ns.Swaps(key) then swap[key] = true end
    end
    if next(swap) then data.w = swap end
    -- Each aura bar's joins, and on a Buffs bar the buffs shown only while
    -- they're missing, those on its list.
    local only = {}
    for _, key in ipairs(ns.BAR_KEYS) do
        if ns.AURA_BARS[key] then
            local set = Picks(ns.Joins(key), true)
            if next(set) then joins[key] = set end
        end
        if ns.BAR_KIND[key] == "buff" then
            local listed, kept = {}, {}
            for _, entry in ipairs(data.l[key] or {}) do listed[entry] = true end
            for name in pairs(Picks(ns.OnlyWhenMissing(key), true)) do
                if listed[name] then kept[name] = true end
            end
            if next(kept) then only[key] = kept end
        end
    end
    if next(only) then data.m = only end
    -- Each entry's own countdown font and size, for those on its lists.
    local own, onList = {}, {}
    for _, list in pairs(data.l) do
        for _, entry in ipairs(list) do onList[entry] = true end
    end
    for _, lists in pairs(forms) do
        for _, list in pairs(lists) do
            for _, entry in ipairs(list) do onList[entry] = true end
        end
    end
    for name, look in pairs(Table(store.spellLook)) do
        local kept = onList[name] and ns.CleanSpellLook(look)
        if kept then own[name] = kept end
    end
    if next(own) then data.i = own end
    -- The aura bars' warned entries (Warn at), those on that bar's list.
    local warns = {}
    for key in pairs(ns.AURA_BARS) do
        local onBar, set = {}, {}
        for _, entry in ipairs(data.l[key] or {}) do onBar[entry] = true end
        for name, seconds in pairs(ns.WarnAt(key)) do
            if onBar[name] and ns.WarnValue(seconds) then set[name] = seconds end
        end
        if next(set) then warns[key] = set end
    end
    if next(warns) then data.t = warns end
    -- Each icon's own size, for those on its bar's lists (a form's too).
    local sizes = {}
    for key, set in pairs(Table(store.iconSize)) do
        local onBar, kept = {}, {}
        for _, entry in ipairs(data.l[key] or {}) do onBar[entry] = true end
        for _, lists in pairs(forms) do
            for _, entry in ipairs(lists[key] or {}) do onBar[entry] = true end
        end
        for name, percent in pairs(Table(set)) do
            if onBar[name] and ns.SizeValue(percent) then kept[name] = percent end
        end
        if next(kept) then sizes[key] = kept end
    end
    if next(sizes) then data.z = sizes end
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
-- Undo on the Layout page is for a layout you picked, and the presets' Undo
-- for a look you picked (it would switch off what came on), so both go.
local function Redraw()
    if ns.Layout then ns.Layout.undo, ns.Layout.moved = nil, nil end
    P.undo = nil
    P.RedrawLook()
end

-- Everything that shows the look, after it changed: the font, your bars, the
-- restyled Blizzard bars, the display, the cast bar, Raid Timers and pulse.
function P.RedrawLook()
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
    -- Icon details: the swipe, countdown and edge line on every icon.
    ns.Style:ApplyDetails()
    if ns.Resource and ns.Resource.started then ns.Resource:Apply() end
    if ns.CastBar and ns.CastBar.started then ns.CastBar:Apply() end
    if ns.RaidTimers and ns.RaidTimers.started then ns.RaidTimers:Apply() end
    if ns.Pulse and ns.Pulse.started then ns.Pulse:Apply() end
end

-- Presets ---------------------------------------------------------------------------
-- One click for how everything looks (the Look page's Presets): the design,
-- colour, texture and font, borders, shadows and edges, keys on icons, the
-- display's text and the cast bar's look. Not the window's accent, where
-- anything sits, Raid Timers or the pulse; and a preset never turns
-- anything off: text you switched off on a bar stays off. Picked with a
-- preset, the Also turn on choices switch on what the look goes well with.
-- Undo puts back the look and switches off what was turned on, until the
-- next preset or a reload.
P.LOOKS = {
    { key = "clean", name = "Clean", about = "Flat and tidy, thin edges, no shadows.", extras = { "keybinds", "cast" }, values = {
        barStyle = "split", barColour = "blue", barTexture = "flat", font = "friz", iconBorder = "icon", iconShadow = "off",
        barDarkness = 50, thickEdges = false, readyGlow = "edge", keybindPosition = "TOPRIGHT", keybindSize = 90,
        prdHealthAt = "centre", prdHealthCentre = "value", prdPowerAt = "centre", prdPowerCentre = "value", prdTextNumbers = "short",
        prdTextFont = "look", prdHealthSize = 11, prdPowerSize = 10, prdExtraSize = 9, prdEnergySize = 8,
        castColour = "blue", castHeight = 16, castTickColour = "white", castTickStyle = "notches", castTickWidth = 2,
        castTimeFormat = "left", castLatencyColour = "red", swingColour = "charcoal" } },
    { key = "bold", name = "Bold", about = "Glass in your class colour, thick edges, borders and shadows.",
        extras = { "keybinds", "text", "cast", "ticks", "latency" }, values = {
        barStyle = "glass", barColour = "class", barTexture = "raid", font = "skurri", iconBorder = "icon", iconShadow = "bar",
        barDarkness = 75, thickEdges = true, readyGlow = "proc", keybindPosition = "BOTTOM", keybindSize = 115,
        prdHealthAt = "sides", prdHealthLeft = "value", prdHealthRight = "percent", prdPowerAt = "sides", prdPowerLeft = "value",
        prdPowerRight = "percent", prdTextNumbers = "short", prdTextFont = "look", prdHealthSize = 14, prdPowerSize = 12,
        prdExtraSize = 10, prdEnergySize = 9,
        castColour = "class", castHeight = 22, castTickColour = "white", castTickStyle = "lines", castTickWidth = 3,
        castTimeFormat = "total", castLatencyColour = "red", swingColour = "default" } },
    { key = "minimal", name = "Minimal", about = "Outline bars, small and quiet.", extras = {}, values = {
        barStyle = "outline", barColour = "charcoal", barTexture = "flat", font = "arial", iconBorder = "off", iconShadow = "off",
        barDarkness = 0, thickEdges = false, readyGlow = "edge", keybindPosition = "TOPLEFT", keybindSize = 80,
        prdHealthAt = "centre", prdHealthCentre = "percent", prdPowerAt = "centre", prdPowerCentre = "value", prdTextNumbers = "short",
        prdTextFont = "arial", prdHealthSize = 9, prdPowerSize = 9, prdExtraSize = 8, prdEnergySize = 8,
        castColour = "charcoal", castHeight = 12, castTickColour = "white", castTickStyle = "notches", castTickWidth = 1,
        castTimeFormat = "left", castLatencyColour = "white", swingColour = "charcoal" } },
    { key = "classic", name = "Classic", about = "Close to Blizzard's own: the classic bar, gold casts.", extras = { "look", "cast" }, values = {
        barStyle = "glass", barColour = "orange", barTexture = "classic", font = "friz", iconBorder = "icon", iconShadow = "off",
        barDarkness = 0, thickEdges = false, readyGlow = "proc", keybindPosition = "TOPRIGHT", keybindSize = 100,
        prdHealthAt = "centre", prdHealthCentre = "value", prdPowerAt = "centre", prdPowerCentre = "value", prdTextNumbers = "full",
        prdTextFont = "friz", prdHealthSize = 10, prdPowerSize = 10, prdExtraSize = 9, prdEnergySize = 9,
        castColour = "default", castHeight = 18, castTickColour = "white", castTickStyle = "notches", castTickWidth = 2,
        castTimeFormat = "left", castLatencyColour = "red", swingColour = "default" } },
}
local LOOK = {}
for _, look in ipairs(P.LOOKS) do LOOK[look.key] = look end

-- What a preset can switch on as well, each a tick (some for some classes).
P.EXTRAS = {
    { key = "keybinds", label = "Keybinds on icons", settings = { "keybinds" } },
    { key = "text", label = "Health and power text", settings = { "prdText" } },
    { key = "look", label = "The look on Blizzard's bars", settings = { "skin", "prdSkin" },
        about = "Apply this look to Blizzard's Cooldown Manager and resource display. Needs a reload." },
    { key = "cast", label = "Your own cast bar", settings = { "castBar" } },
    { key = "ticks", label = "Cast bar tick marks", settings = { "castTicks" }, about = "Tick marks on channelled spells." },
    { key = "latency", label = "Cast bar latency", settings = { "castLatency" }, about = "Your latency at the end of each cast." },
    { key = "combo", label = "Combo points", settings = { "prdCombo" }, classes = { ROGUE = true, DRUID = true },
        about = "Combo points under your energy bar." },
    { key = "energy", label = "Energy bar in other forms", settings = { "prdEnergy" }, classes = { DRUID = true } },
    { key = "tidy", label = "Tidy extra mana bar", settings = { "prdHideRepeat" }, classes = { DRUID = true } },
}
-- A look made yours in the panel: its font and colour, in place of its own
-- (and Custom's own colour, with the colour Custom).
local OWN = { font = "font", colour = "barColour", colourCustom = "barColourCustom" }

-- The choices to offer you: every extra, or those for your class.
function P.ExtrasFor(class)
    local list = {}
    for _, extra in ipairs(P.EXTRAS) do
        if not extra.classes or extra.classes[class] then list[#list + 1] = extra end
    end
    return list
end

-- An extra is on when all it switches is on already.
function P.ExtraOn(extra)
    for _, key in ipairs(extra.settings) do
        if ns.Get(key) ~= true then return false end
    end
    return true
end

-- What a preset sets for you now ("keep": nothing of its own): its values
-- the addon takes, less text on a bar you switched off (a preset never
-- turns it back on), with own (font, colour) in place of its own. Nil for
-- no such preset.
function P.LookValues(key, own)
    local look = LOOK[key]
    if not look and key ~= "keep" then return nil end
    local values = {}
    for setting, value in pairs(look and look.values or {}) do
        local skip = (setting == "prdHealthAt" or setting == "prdPowerAt") and ns.GetSaved(setting) == "off"
        if not skip and ns.Valid(setting, value) then values[setting] = value end
    end
    -- A game in Chinese, Korean or Russian keeps its own font, which can
    -- write its names and its short numbers' word (like 万), unless you pick
    -- another yourself.
    if ns.GAME_FONT_FIRST then
        if values.font ~= nil then values.font = "game" end
        if values.prdTextFont ~= nil and values.prdTextFont ~= "look" then values.prdTextFont = "game" end
    end
    for which, setting in pairs(OWN) do
        local value = own and own[which]
        if value ~= nil and ns.Valid(setting, value) then values[setting] = value end
    end
    return values
end

-- A look shown on your bars for a moment while you pick (nil for yours),
-- nothing saved.
function P.PreviewLook(key, own)
    local values = key and P.LookValues(key, own)
    ns.PreviewLook(values and next(values) and values or nil)
    P.RedrawLook()
end

-- After keys on icons were switched on or off: Keybinds.lua reads your
-- action bars again first, as the Look page's tick has it do.
local function Rekey(undo)
    if not ns.Keybinds then return end
    for _, setting in ipairs(undo.on) do
        if setting == "keybinds" then return ns.Keybinds:Update() end
    end
end

-- A preset's look (made yours by own), and the extras ticked (by key),
-- switched on: what was there kept for Undo, back to before the first
-- preset since the last Undo. A message to show.
function P.ApplyLook(key, extras, own)
    local values = P.LookValues(key, own)
    if not values then return false, "There's no preset called that." end
    local look = LOOK[key]
    ns.PreviewLook(nil)
    local undo, turned = P.undo or { values = {}, on = {} }, {}
    ns.SetMany(function()
        for setting, value in pairs(values) do
            if undo.values[setting] == nil then undo.values[setting] = ns.Get(setting) end
            ns.Set(setting, value)
        end
        for _, extra in ipairs(P.EXTRAS) do
            if extras and extras[extra.key] and not P.ExtraOn(extra) then
                for _, setting in ipairs(extra.settings) do
                    if ns.Get(setting) ~= true then
                        undo.on[#undo.on + 1] = setting
                        ns.Set(setting, true)
                    end
                end
                turned[#turned + 1] = extra.label
            end
        end
    end)
    P.undo = undo
    Rekey(undo)
    P.RedrawLook()
    local said = look and (look.name .. " look applied") or next(values) and "Your look changed" or "Your look kept"
    if #turned > 0 then said = said .. ", and turned on: " .. table.concat(turned, ", ") end
    if ns.NeedsReload and ns.NeedsReload() then said = said .. ". Reload to finish" end
    return true, said .. "."
end

function P.CanUndoLook()
    return P.undo ~= nil
end

-- The look before the presets, and anything they turned on off again.
function P.UndoLook()
    local undo = P.undo
    if not undo then return false, "Nothing to undo." end
    P.undo = nil
    ns.PreviewLook(nil)
    ns.SetMany(function()
        for setting, value in pairs(undo.values) do ns.Set(setting, value) end
        for _, setting in ipairs(undo.on) do ns.Set(setting, false) end
    end)
    Rekey(undo)
    P.RedrawLook()
    return true, "Your look before the presets is back."
end

-- A part that can't run here now isn't switched on: the pulse and its procs
-- while it runs in Forever Enhanced Cooldown Pulse, and proc pulses while
-- the game can't show them (their ticks are greyed then).
local function CantRun(key)
    local pulse = ns.Pulse
    if not pulse or (key ~= "pulse" and key ~= "pulseProcs") then return false end
    if pulse:Elsewhere() then return true end
    return key == "pulseProcs" and not pulse:CanProcs()
end

-- Your class's file name ("DRUID"), or nil while the game doesn't say.
local function MyClass()
    if not UnitClass then return nil end
    local _, class = UnitClass("player")
    if (issecretvalue and issecretvalue(class)) or type(class) ~= "string" then return nil end
    return class
end

-- What a string read by P.Read switches on for you with its look and
-- layout: each part it has on that's off here and can run now, in order, as
-- { key, name, shown }. The name has "(experimental)" where its tick says
-- so; shown is false for a part your class doesn't use (switched on all the
-- same, as it's every character's, but not named).
function P.WouldTurnOn(shared)
    local setup = type(shared) == "table" and type(shared.setup) == "table" and shared.setup or {}
    local parts = type(setup.parts) == "table" and setup.parts or {}
    local class, list = MyClass(), {}
    for _, part in ipairs(ns.SHARE_PARTS) do
        local key = part.key
        if parts[key] == true and ns.GetSaved(key) ~= true and not CantRun(key) then
            list[#list + 1] = { key = key, name = part.name .. (part.experimental and " (experimental)" or ""),
                shown = not part.classes or (class ~= nil and part.classes[class] == true) }
        end
    end
    return list
end

-- Those switched on, never one turned off: your bars as General's tick
-- turns them on. How many are named, what to tell you about your bars (or
-- nil), and the keys turned on.
local function SwitchOn(shared)
    local list, shown, note, turned = P.WouldTurnOn(shared), 0, nil, {}
    ns.SetMany(function()
        for _, part in ipairs(list) do
            if part.key == "useBars" then note = ns.SetBars(true) else ns.Set(part.key, true) end
            turned[part.key] = true
            if part.shown then shown = shown + 1 end
        end
    end)
    return shown, note, turned
end

-- A string read by P.Read as a new profile (Core.lua's ns.ImportProfile),
-- switched to; with its look and layout too, if asked, and the parts it has
-- on switched on. True and what happened, or false and why not. (The
-- question before it names them; the line after only counts them, to fit.)
function P.Import(text, shared, withLook)
    local ok, message, name = ns.ImportProfile(text, shared, withLook)
    if not ok then return false, message end
    if withLook then
        local shown, note, turned = SwitchOn(shared)
        -- Keys on icons: your action bars read again first, as the Look page's tick has it.
        if turned.keybinds and ns.Keybinds then ns.Keybinds:Update() end
        Redraw()
        if shown > 0 then message = message .. (" Also turned on %d of its settings."):format(shown) end
        -- Your bars on: Blizzard's Cooldown Manager went off, as the question said.
        if note and ns.NeedsReload and ns.NeedsReload() then
            message = message .. " Reload to finish."
        elseif note then
            message = message .. " " .. note
        end
    end
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
local LOOK_ON = "Your bar sizes, spots, layout and look are replaced by its own, on every character. Anything it has switched on"
    .. " comes on too."
local LOOK_OFF = "Unticked, only its bars' spells and pulse ticks come, in your own look and layout."
local LOOK_ASK = "Your bar sizes, spots, layout and look change to the shared ones, on every character."
local KEEP_YOURS = " To keep a copy of yours, Share it first."
P.LOOK_ON, P.LOOK_OFF = LOOK_ON, LOOK_OFF

-- The question before a look and layout come in: what changes, each part it
-- switches on for you by name, and, when your bars come on, that Blizzard's
-- Cooldown Manager goes off.
function P.LookQuestion(shared)
    local names, bars = {}, false
    for _, part in ipairs(P.WouldTurnOn(shared)) do
        if part.key == "useBars" and ns.CooldownManagerOn() then
            bars = true
        elseif part.shown then
            names[#names + 1] = part.name
        end
    end
    local text = LOOK_ASK
    local last = table.remove(names)
    if last then text = text .. " It also turns on " .. (#names > 0 and (table.concat(names, ", ") .. " and ") or "") .. last .. "." end
    if bars then text = text .. " Your own bars come on in place of Blizzard's Cooldown Manager, which turns off (reload after)." end
    return text .. KEEP_YOURS
end

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
    local look = T:Check(box, "Also use its look and layout (experimental)", function(self)
        lookNote:SetText(self:GetChecked() and LOOK_ON or LOOK_OFF)
    end)
    look:SetPoint("TOPLEFT", 14, -160)
    window:Hint(look, "Its bar sizes, spots, layout and look in place of yours, on every character, and anything it has switched on"
        .. " comes on too. It asks first.")
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
            window:Ask("Use its look and layout too?", P.LookQuestion(shared), "Use them", Go)
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
