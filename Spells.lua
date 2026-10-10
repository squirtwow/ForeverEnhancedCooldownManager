-- Everything a bar can show, one entry each: your spells at their
-- highest known rank, your class's talent procs, your trinkets and usable bag
-- items, healthstones and potions whatever their rank, and spells added by
-- name or ID. Bars store each entry's key (a spell name, "item:<id>",
-- "slot:<n>" or "family:<name>"), so training a new rank, swapping a trinket
-- or carrying a better potion moves every bar along without any change to
-- the saved setup. Two more kinds of key carry a number after the name: a
-- fixed rank, "Name@N", and a spell pinned to one ID, "Name#ID" (S:Pin).
local _, ns = ...

local S = {}
ns.Spells = S

local BANK = Enum and Enum.SpellBookSpellBank and Enum.SpellBookSpellBank.Player or 0
local ITEM = Enum and Enum.SpellBookItemType or {}
local TRINKETS = { 13, 14 }
local BAGS = 4

-- Buffs that talents put on you, which have no spellbook entry. The Forever
-- client holds only these IDs (checked against its game data).
local PROCS = {
    DRUID = { 16870, 16886 }, -- Clearcasting, Nature's Grace
    MAGE = { 12536 }, -- Clearcasting
    PRIEST = { 15271 }, -- Spirit Tap
    SHAMAN = { 16246, 16257 }, -- Clearcasting, Flurry
    WARRIOR = { 12966, 12880 }, -- Flurry, Enrage
    WARLOCK = { 17941 }, -- Shadow Trance
    ROGUE = { 14143 }, -- Remorseless
    HUNTER = { 6150 }, -- Quick Shots
    PALADIN = { 20050, 20128 }, -- Vengeance, Redoubt
}
S.PROCS = PROCS

-- A buff's group version counts as the same buff.
local GROUP = {
    ["Mark of the Wild"] = "Gift of the Wild",
    ["Power Word: Fortitude"] = "Prayer of Fortitude",
    ["Arcane Intellect"] = "Arcane Brilliance",
    ["Divine Spirit"] = "Prayer of Spirit",
    ["Shadow Protection"] = "Prayer of Shadow Protection",
    ["Blessing of Might"] = "Greater Blessing of Might",
    ["Blessing of Wisdom"] = "Greater Blessing of Wisdom",
    ["Blessing of Kings"] = "Greater Blessing of Kings",
    ["Blessing of Salvation"] = "Greater Blessing of Salvation",
    ["Blessing of Light"] = "Greater Blessing of Light",
    ["Blessing of Sanctuary"] = "Greater Blessing of Sanctuary",
}

-- Names a later build gave a spell: one saved by its old name still counts
-- as the new one. Build 70291 dropped "Effect" from the trap debuffs' names
-- (and Grounding Totem's buff's), and "Aura" from Frost Trap's.
local RENAMED = {
    ["Immolation Trap Effect"] = "Immolation Trap",
    ["Freezing Trap Effect"] = "Freezing Trap",
    ["Frost Trap Aura"] = "Frost Trap",
    ["Grounding Totem Effect"] = "Grounding Totem",
}

S.LINES = { procs = "Procs", items = "Items", added = "Added" }

-- Healthstones and potions come in ranks, and you carry whichever you have:
-- a family is one entry for every rank of one, showing the best you carry.
-- Item IDs from the Forever client's own item tables (build 1.60.1.70009),
-- weakest first by what each restores. A rank's twins sit beside it:
-- Improved Healthstone's, the conjured Perishable potions (after the plain
-- ones, so they show first: they don't last), and the battleground and other
-- same-named ones. Discolored and Restored potions work differently, so
-- they stay single items.
local FAMILIES = {
    { key = "family:healthstone", name = "Healthstones", items = {
        19004, 5512, 19005, -- Minor
        19006, 5511, 19007, -- Lesser
        19008, 5509, 19009, -- Healthstone
        19010, 5510, 19011, -- Greater
        19012, 9421, 19013, -- Major
    } },
    { key = "family:healing", name = "Healing Potions", items = {
        118, 268881, -- Minor
        858, 268882, -- Lesser
        929, 268883, -- Healing Potion
        1710, 223914, -- Greater
        3928, 18839, -- Superior, Combat Healing Potion
        13446, 223913, -- Major
    } },
    { key = "family:mana", name = "Mana Potions", mana = true, items = {
        2455, 3385, 3827, 6149, -- Minor, Lesser, Mana Potion, Greater
        13443, 18841, -- Superior, Combat Mana Potion
        13444, -- Major
    } },
}
S.FAMILIES = FAMILIES
-- Mana Potions are only offered to classes with mana (or kept on a bar).
local NO_MANA = { WARRIOR = true, ROGUE = true }
-- Only these classes fire bows, guns and crossbows, so only they use ammo.
local AMMO_CLASSES = { HUNTER = true, WARRIOR = true, ROGUE = true }
local FAMILY_NOTE = "Best you carry"

local familyOf, familyByKey = {}, {}
for _, family in ipairs(FAMILIES) do
    familyByKey[family.key] = family
    for _, id in ipairs(family.items) do familyOf[id] = family end
end
-- The item each family showed last, kept over each scan: what it shows while
-- the game hides your bags in a fight, or once you carry none.
local shown = {}

local list, byKey = {}, {}

local function Open(value)
    return not (issecretvalue and issecretvalue(value))
end

local function Text(value)
    return type(value) == "string" and Open(value) and value ~= "" and value or nil
end

-- Spells pinned to one ID. Two spells can share a name (the Skyborne's
-- racial gives two buffs called Energized, 1270842 for 15 seconds and
-- 1259691 for 15 minutes), and an entry kept by name watches every ID it
-- was given. On the Buffs and Debuffs bars, an ID whose name is already in
-- your lists, for another spell, goes on as an entry of its own, kept as
-- "Energized#1270842", which watches that ID alone (and the aura of its own
-- a passive gives). It needs nothing remembered (ns.CustomSpells): the key
-- carries it. Spell names never hold # or @, so no key saved before means
-- anything else now.
local MAX_ID = 2147483647 -- the biggest spell ID
local MAX_KEY = 64 -- the longest key a shared profile keeps (ProfileShare.lua)

-- A pinned key's spell name and ID, or nil for any other key.
local function Pinned(key)
    if type(key) ~= "string" then return nil end
    local name, id = key:match("^([^#@]+)#([1-9]%d*)$")
    id = tonumber(id)
    if not (name and id and id <= MAX_ID) then return nil end
    return name, id
end

function S:Pinned(key)
    return Pinned(key)
end

-- The key a spell's name and ID are pinned under, or nil when they can't be
-- (a name too long to share with the ID after it).
local function PinKey(name, id)
    if type(name) ~= "string" or name == "" or name:find("[#@]") then return nil end
    if type(id) ~= "number" or id < 1 or id > MAX_ID or id ~= math.floor(id) then return nil end
    local key = ("%s#%d"):format(name, id)
    return #key <= MAX_KEY and key or nil
end

-- How a pinned entry is named, in the window and under its icon.
local function PinName(name, id)
    return ("%s (ID %d)"):format(name, id)
end

function S:PinName(name, id)
    return PinName(name, id)
end

-- The spell's own name in an entry's key: without a fixed rank's "@N" or a
-- pinned ID's "#ID".
local function Base(key)
    return (key:gsub("@%d+$", ""):gsub("#%d+$", ""))
end

-- Each ID of an aura that's one buff in several (ns.AURA_FAMILIES: a totem
-- buff's ranks, Well Fed from any food), with all of them. Made the first
-- time it's needed, and again if the list itself changes.
local families, familyList = {}, nil
local function Family(id)
    if ns.AURA_FAMILIES ~= familyList then
        familyList, families = ns.AURA_FAMILIES, {}
        for _, ids in ipairs(familyList or {}) do
            for _, each in ipairs(ids) do families[each] = ids end
        end
    end
    return families[id]
end

-- Every spell ID a buff of this name can carry: the ranks you know, all ranks
-- in the game data, and its group version. A passive added by its ID also
-- carries the aura of its own it gives (Plainsrunning's speed buff), which
-- is what lights it on the Buffs or Debuffs bar. Any of them that leads to
-- an aura with another ID (Bloodrage's rage buff, Vanish's stealth, a
-- poison's debuff on the target, a totem's buff on everyone near it:
-- ns.SPELL_AURAS, and by the aura's name ns.NAME_AURAS) carries that too,
-- and an aura that's one buff in several IDs carries them all (a totem
-- buff's other ranks, Well Fed from another food). With no name, just the
-- IDs known and their auras (a spell pinned to one ID). A name a later
-- build changed counts as the new one too.
local function BuffIDs(name, known)
    local ids, seen = {}, {}
    local function Add(list)
        for _, id in ipairs(list or {}) do
            if not seen[id] then
                seen[id] = true
                ids[#ids + 1] = id
            end
        end
    end
    Add(known)
    local ranks, named = ns.RANKS or {}, ns.NAME_AURAS or {}
    if name then
        local now = RENAMED[name]
        Add(ranks[name])
        if GROUP[name] then Add(ranks[GROUP[name]]) end
        if now then Add(ranks[now]) end
        Add(named[name])
        if now then Add(named[now]) end
    end
    for _, id in ipairs(known or {}) do
        Add(ns.PASSIVE_BUFFS and ns.PASSIVE_BUFFS[id])
        Add(ns.PASSIVE_DEBUFFS and ns.PASSIVE_DEBUFFS[id])
    end
    -- Only the IDs so far: an aura's own auras aren't followed.
    local auras = ns.SPELL_AURAS or {}
    for i = 1, #ids do Add(auras[ids[i]]) end
    for i = 1, #ids do Add(Family(ids[i])) end
    return ids
end

local function Add(entry)
    if byKey[entry.key] then return byKey[entry.key] end
    byKey[entry.key] = entry
    list[#list + 1] = entry
    return entry
end

local function ScanSpellbook()
    if not (C_SpellBook and C_SpellBook.GetNumSpellBookSkillLines) then return end
    for line = 1, C_SpellBook.GetNumSpellBookSkillLines() or 0 do
        local info = C_SpellBook.GetSpellBookSkillLineInfo(line)
        if info and not info.shouldHide and (info.offSpecID or 0) == 0 then
            local first = (info.itemIndexOffset or 0) + 1
            local last = (info.itemIndexOffset or 0) + (info.numSpellBookItems or 0)
            for index = first, last do
                local kind = C_SpellBook.GetSpellBookItemType(index, BANK)
                if kind ~= ITEM.FutureSpell and kind ~= ITEM.Flyout then
                    local item = C_SpellBook.GetSpellBookItemInfo(index, BANK)
                    local name = item and Text(item.name)
                    local spellID = item and (item.spellID or item.actionID)
                    if name and spellID and not item.isPassive then
                        local sub = Text(item.subName) or ""
                        local rank = tonumber(sub:match("%d+")) or 0
                        local entry = byKey[name] or Add({ key = name, name = name, kind = "spell",
                            line = info.name or "", known = {}, byRank = {}, rank = -1 })
                        entry.known[#entry.known + 1] = spellID
                        if rank > 0 then entry.byRank[rank] = { spellID = spellID, icon = item.iconID } end
                        if rank >= entry.rank then
                            entry.spellID, entry.icon, entry.rank = spellID, item.iconID, rank
                            entry.rankText = sub
                        end
                    end
                end
            end
        end
    end
    for _, entry in ipairs(list) do
        entry.ids = BuffIDs(entry.name, entry.known)
        -- Every rank below the highest can also be tracked on its own, as
        -- "Name@N", for players who cast a lower rank on purpose.
        entry.lower = {}
        for rank = 1, entry.rank - 1 do
            local known = entry.byRank[rank]
            if known then
                local fixed = { key = entry.name .. "@" .. rank, name = entry.name .. " (Rank " .. rank .. ")",
                    baseName = entry.name, kind = "rank", line = entry.line, rank = rank, rankText = "Rank " .. rank,
                    spellID = known.spellID, icon = known.icon or entry.icon }
                byKey[fixed.key] = fixed
                entry.lower[#entry.lower + 1] = fixed
            end
        end
    end
end

local function ScanProcs()
    local _, class = UnitClass("player")
    for _, id in ipairs(PROCS[class] or {}) do
        local name = C_Spell.GetSpellName and Text(C_Spell.GetSpellName(id))
        if name and not byKey[name] then
            Add({ key = name, name = name, kind = "proc", line = S.LINES.procs, ids = { id }, spellID = id,
                icon = C_Spell.GetSpellTexture(id), rankText = "" })
        end
    end
end

local function ItemName(itemID, link)
    local name = Text(link) and link:match("%[(.-)%]")
    if not name and C_Item and C_Item.GetItemNameByID then name = Text(C_Item.GetItemNameByID(itemID)) end
    return name or ("Item " .. itemID)
end

local function AddItem(itemID, link, icon)
    return Add({ key = "item:" .. itemID, name = ItemName(itemID, link), kind = "item", line = S.LINES.items,
        itemID = itemID, icon = icon or (C_Item.GetItemIconByID and C_Item.GetItemIconByID(itemID)), rankText = "" })
end

-- Moves a family on to the item it should show now: the best one you carry
-- and can use (a potion above your level can't be), else the best you carry,
-- else the one it showed before. Anything the game hides keeps it as it is.
-- Also notes the name of the one you carry, for its label (none when you're
-- out, or until the game has the name). The bars call this as your bags
-- change; true when anything changed.
function S:Pick(entry)
    local family = entry and entry.family
    if not family then return false end
    local best, carried
    for i = #family.items, 1, -1 do
        local id = family.items[i]
        local count = C_Item.GetItemCount(id, false, true)
        if not Open(count) then return false end
        if type(count) == "number" and count > 0 then
            local usable = C_Item.IsUsableItem(id)
            if not Open(usable) then return false end
            carried = carried or id
            if usable then
                best = id
                break
            end
        end
    end
    local have = carried ~= nil
    best = best or carried or entry.itemID
    local current = have and C_Item.GetItemNameByID and Text(C_Item.GetItemNameByID(best)) or nil
    if best == entry.itemID and have == entry.have and current == entry.current then return false end
    shown[entry.key] = best
    entry.itemID, entry.have, entry.current = best, have, current
    entry.icon = C_Item.GetItemIconByID and C_Item.GetItemIconByID(best) or entry.icon
    return true
end

-- Whether you carry any of a bag item, or any rank of a healthstone or potion
-- family: true or false, or nil while the game won't say (the bars then keep
-- what they knew). An item worn (a cloak with a use, say) counts as carried.
-- Only asked of bag items and families; trinkets and ammo aren't.
function S:Carries(entry)
    local ids
    if entry and entry.kind == "family" then
        ids = entry.family.items
    elseif entry and entry.kind == "item" then
        ids = { entry.itemID }
    else
        return nil
    end
    for _, id in ipairs(ids) do
        local count = C_Item.GetItemCount(id, false, true)
        if not (Open(count) and type(count) == "number") then return nil end
        if count > 0 then return true end
    end
    if entry.kind == "item" and C_Item.IsEquippedItem then
        local worn = C_Item.IsEquippedItem(entry.itemID)
        if not Open(worn) then return nil end
        if worn then return true end
    end
    return false
end

local function AddFamily(family)
    local itemID = shown[family.key] or family.items[1]
    local entry = Add({ key = family.key, name = family.name, kind = "family", line = S.LINES.items, family = family,
        itemID = itemID, icon = C_Item.GetItemIconByID and C_Item.GetItemIconByID(itemID), rankText = FAMILY_NOTE })
    S:Pick(entry)
    return entry
end

-- Food, drink and recipes can be used but never have a cooldown to show.
local RECIPE, CONSUMABLE, FOOD_AND_DRINK = 9, 0, 5
local function NoCooldown(itemID)
    if not (C_Item and C_Item.GetItemInfoInstant) then return false end
    local _, _, _, _, _, classID, subclassID = C_Item.GetItemInfoInstant(itemID)
    return classID == RECIPE or (classID == CONSUMABLE and subclassID == FOOD_AND_DRINK)
end

-- Your two trinket slots, whatever is in them, your ammunition for its
-- count (for a class that uses it), then usable items in your bags.
local AMMO = INVSLOT_AMMO or 0
local AMMO_ICON = "Interface\\Icons\\INV_Ammo_Arrow_01"

local function AddAmmo(itemID)
    Add({ key = "ammo", name = itemID and ("Ammo: " .. ItemName(itemID, GetInventoryItemLink("player", AMMO))) or "Ammo",
        kind = "ammo", line = S.LINES.items, slot = AMMO, itemID = itemID,
        icon = itemID and GetInventoryItemTexture("player", AMMO) or AMMO_ICON, rankText = "" })
end

-- Whether your class uses ammo. Any other class (a warlock on a profile
-- shared with a hunter, say) isn't offered it and passes over it on a bar,
-- where it stays for the characters that use it. Unknown: it does.
function S:UsesAmmo()
    local _, class = UnitClass("player")
    if not (Open(class) and type(class) == "string") then return true end
    return AMMO_CLASSES[class] == true
end

local function ScanItems()
    for index, slot in ipairs(TRINKETS) do
        local itemID = GetInventoryItemID("player", slot)
        if itemID then
            local link = GetInventoryItemLink("player", slot)
            Add({ key = "slot:" .. slot, name = "Trinket " .. index .. ": " .. ItemName(itemID, link), kind = "slot",
                line = S.LINES.items, slot = slot, itemID = itemID,
                icon = GetInventoryItemTexture("player", slot), rankText = "" })
        end
    end
    local ammo = GetInventoryItemID("player", AMMO)
    if ammo and S:UsesAmmo() then AddAmmo(ammo) end
    -- Healthstones and potions, one entry each whatever rank you carry.
    local _, class = UnitClass("player")
    for _, family in ipairs(FAMILIES) do
        if not (family.mana and NO_MANA[class]) then AddFamily(family) end
    end
    if not (C_Container and C_Container.GetContainerNumSlots) then return end
    for bag = 0, BAGS do
        for slot = 1, C_Container.GetContainerNumSlots(bag) or 0 do
            local info = C_Container.GetContainerItemInfo(bag, slot)
            local itemID = info and info.itemID
            if itemID and not byKey["item:" .. itemID] and C_Item.GetItemSpell(itemID) and not NoCooldown(itemID) then
                AddItem(itemID, info.hyperlink, info.iconFileID)
            end
        end
    end
end

-- Whether you or your pet know any of these spells: nil while the game
-- won't say.
local function Knows(ids)
    local book = C_SpellBook
    if not (book and book.IsSpellKnown) then return nil end
    local banks = { BANK }
    local pet = Enum and Enum.SpellBookSpellBank and Enum.SpellBookSpellBank.Pet
    if pet then banks[2] = pet end
    local hidden = false
    for _, id in ipairs(ids or {}) do
        for _, bank in ipairs(banks) do
            local known = book.IsSpellKnown(id, bank)
            if not Open(known) then
                hidden = true
            elseif known then
                return true
            end
        end
    end
    if hidden then return nil end
    return false
end

-- The highest rank of these spells that you or your pet know, or nil: a
-- hunter typing Growl means his pet's, not a druid's.
local function HighestKnown(ids)
    for i = #ids, 1, -1 do
        if Knows({ ids[i] }) == true then return ids[i] end
    end
    return nil
end

-- The highest rank of these spells with a cooldown of its own (the game
-- data's, ns.COOLDOWNS), else the highest: what a spell no one knows yet
-- goes by. Where a druid's or warrior's spell and a pet's share a name
-- (Growl, Charge), the highest ranks are the pet's; a helper listed after
-- the spell itself (Frenzied Regeneration's 22845) has no cooldown to show.
local function Highest(ids)
    local cooldowns = ns.COOLDOWNS or {}
    for i = #ids, 1, -1 do
        if cooldowns[ids[i]] then return ids[i] end
    end
    return ids[#ids]
end

-- The spell an added entry's cooldown, range and tooltip go by: the ID it
-- was added with (the last, when it was given more), so a hunter's pet
-- ability goes by the pet's own spell. While you and your pet don't know
-- that one, the highest rank of its name you do (the pet out now has
-- another rank, or a druid's Growl was saved by name), else the one added.
-- One the game data no longer lists under that name (the teaching spell a
-- pet ability was saved by before) gives way to the data's highest rank.
local function Tracked(name, added)
    local id = added[#added]
    local ranks = ns.RANKS and ns.RANKS[name]
    if not ranks or Knows({ id }) == true then return id end
    local known = HighestKnown(ranks)
    if known then return known end
    for _, rank in ipairs(ranks) do
        if rank == id then return id end
    end
    return Highest(ranks)
end

-- Anything on a bar that isn't in your spellbook or bags right now: spells
-- added by name or ID (each keeping the IDs it was added with, as added),
-- spells pinned to one ID (watching that one), items you've run out of (the
-- bars leave them off until you carry one again), your ammo with none
-- equipped, and Mana Potions kept on a bar by a class without mana (a
-- profile shared with one that has it). An added spell with one of its name
-- pinned beside it shows its own IDs in the list, so the two read apart.
local function ScanSaved()
    local custom = ns.CustomSpells and ns.CustomSpells() or {}
    for _, key in ipairs(ns.BAR_KEYS) do
        for _, saved in ipairs(ns.BarData(key).spells) do
            if not byKey[saved] then
                local itemID = tonumber(saved:match("^item:(%d+)$"))
                if saved == "ammo" then
                    -- None equipped now: shown empty, to a class that uses it.
                    if S:UsesAmmo() then AddAmmo(nil) end
                elseif familyByKey[saved] then
                    AddFamily(familyByKey[saved])
                elseif itemID then
                    AddItem(itemID)
                elseif Pinned(saved) then
                    -- Its own ID only: not its name's other ranks or group version.
                    local name, id = Pinned(saved)
                    Add({ key = saved, name = PinName(name, id), baseName = name, kind = "spell", line = S.LINES.added,
                        ids = BuffIDs(nil, { id }), spellID = id, icon = C_Spell.GetSpellTexture(id), rankText = "",
                        added = { id }, pinned = id })
                elseif custom[saved] then
                    local ids = BuffIDs(saved, custom[saved])
                    Add({ key = saved, name = saved, kind = "spell", line = S.LINES.added, ids = ids,
                        spellID = Tracked(saved, custom[saved]), icon = C_Spell.GetSpellTexture(ids[1]), rankText = "",
                        added = custom[saved] })
                end
            end
        end
    end
    -- An entry kept by name beside a pinned one of that name is shown the
    -- same way, its ID in brackets ("Energized (ID 1259691)"), so the two
    -- read alike; shown is for the window only, the name stays the spell's.
    for _, entry in ipairs(list) do
        local plain = entry.pinned and byKey[entry.baseName]
        if plain and plain.added and not plain.shown then
            plain.shown = ("%s (%s %s)"):format(plain.name, #plain.added > 1 and "IDs" or "ID", table.concat(plain.added, ", "))
        end
    end
end

-- The list is only read when something wants it: after your spellbook, gear,
-- bags or bars change (S:Stale) it waits, and is read again the next time
-- anything looks in it. With your bars off, /ccm closed and the Cooldown
-- pulse off, nothing does, so it's never read at all.
local stale, reads = true, 0

function S:Scan()
    stale, reads = false, reads + 1
    wipe(list)
    wipe(byKey)
    ScanSpellbook()
    ScanProcs()
    ScanItems()
    ScanSaved()
    return list
end

local function Ready()
    if stale then S:Scan() end
end

-- Something the list holds may have changed: it's read again when next wanted.
function S:Stale()
    stale = true
end

-- How many times the list has been read, and whether it may hold something
-- new since the read-th time: read again since, or waiting to be.
function S:Reads()
    return reads
end

function S:Changed(read)
    return stale or reads ~= read
end

-- The list, read again first if anything changed since.
function S:Fresh()
    Ready()
    return list
end

-- The list as last read, even if something has changed since. For the tests.
function S:List()
    return list
end

function S:Find(key)
    Ready()
    return byKey[key]
end

-- The classes whose talents give each proc, by the proc's name.
local procClasses
local function ProcClasses()
    if procClasses then return procClasses end
    procClasses = {}
    for class, ids in pairs(PROCS) do
        for _, id in ipairs(ids) do
            local name = C_Spell.GetSpellName and Text(C_Spell.GetSpellName(id))
            if name then procClasses[name] = (procClasses[name] or "") .. " " .. class end
        end
    end
    return procClasses
end

-- Whether a list of class tokens or race IDs ("DRUID HUNTER", "95 96") holds
-- yours: nil while the game won't say who you are.
local function Holds(list, mine)
    if not (Open(mine) and (type(mine) == "string" or type(mine) == "number")) then return nil end
    return (" " .. list .. " "):find(" " .. mine .. " ", 1, true) ~= nil
end

-- Items on a bar by key: a trinket slot, a bag item, or a healthstone or
-- potion family.
local function ItemKey(key)
    return key:find("^item:%d+$") ~= nil or key:find("^slot:%d+$") ~= nil or key:find("^family:") ~= nil
end

-- Passive spells, by ID, from the game data (ns.PASSIVES, and the passives
-- with an aura of their own, a totem's buff among them), and every ID the
-- data covers: those and every ID in ns.RANKS, which are active unless
-- listed as passive. Gathered the first time it's asked.
local passiveIDs, coveredIDs
local function Gather()
    if passiveIDs then return end
    passiveIDs, coveredIDs = {}, {}
    for _, ids in pairs(ns.PASSIVES or {}) do
        for _, id in ipairs(ids) do passiveIDs[id], coveredIDs[id] = true, true end
    end
    for _, links in ipairs({ ns.PASSIVE_BUFFS or {}, ns.PASSIVE_DEBUFFS or {} }) do
        for id in pairs(links) do passiveIDs[id], coveredIDs[id] = true, true end
    end
    for _, ids in pairs(ns.RANKS or {}) do
        for _, id in ipairs(ids) do coveredIDs[id] = true end
    end
end
-- What the game said of spells the data doesn't cover.
local asked = {}

-- Whether a spell is passive: from the game data, or for a spell it doesn't
-- cover (one from a later build) from the game, never from a hidden answer.
-- Nil while no one can say.
local function IsPassive(id)
    if type(id) ~= "number" then return nil end
    Gather()
    if coveredIDs[id] then return passiveIDs[id] == true end
    if asked[id] ~= nil then return asked[id] end
    local api = C_Spell and C_Spell.IsSpellPassive
    if not api then return nil end
    local ok, passive = pcall(api, id)
    if not (ok and Open(passive) and type(passive) == "boolean") then return nil end
    asked[id] = passive
    return passive
end

-- Why spells can't be tracked on a bar because they're passive: nil when
-- they can. Passive only when every one is (a name shared with an active
-- spell, a troll's Regeneration and a mage's, is told apart by its IDs) and
-- the game data or the game says so. A passive has nothing to track on the
-- Cooldowns or Utility bar, nor on the Buffs or Debuffs bar unless it gives
-- an aura of its own there that comes and goes (Plainsrunning's speed buff,
-- a talent's proc of the same name) or is one (a totem's buff).
local function Untracked(name, ids, bar)
    if type(ids) ~= "table" or #ids == 0 then return nil end
    for _, id in ipairs(ids) do
        if IsPassive(id) ~= true then return nil end
    end
    local buff, debuff = false, false
    for _, id in ipairs(ids) do
        buff = buff or (ns.PASSIVE_BUFFS ~= nil and ns.PASSIVE_BUFFS[id] ~= nil)
        debuff = debuff or (ns.PASSIVE_DEBUFFS ~= nil and ns.PASSIVE_DEBUFFS[id] ~= nil)
    end
    if (bar == "buff" and buff) or (bar == "debuff" and debuff) then return nil end
    if buff then return name .. " is passive. Only its buff can be tracked, on the Buffs bar." end
    if debuff then return name .. " is passive. Only its debuff can be tracked, on the Debuffs bar." end
    return name .. " is passive, so there's nothing to track."
end

-- The spells a bar entry is judged by: the ones it was added with (a pinned
-- one's ID), or for a name with nothing else to go on (another character's
-- spell that isn't in your spellbook), the game data's IDs for that name.
-- None for your own spells, procs and items: the spellbook passes over
-- passives.
local function Judged(key)
    local entry = byKey[key]
    if entry then return entry.added end
    local _, id = Pinned(key)
    if id then return { id } end
    local name = Base(key)
    return ns.RANKS and ns.RANKS[name] or ns.PASSIVES and ns.PASSIVES[name]
end

-- Why an entry can't be tracked on a bar because it's passive (Underwater
-- Breathing anywhere, Plainsrunning but on the Buffs bar), or nil.
function S:PassiveNote(key, bar)
    if type(key) ~= "string" then return nil end
    Ready()
    local entry = byKey[key]
    return Untracked(entry and entry.name or Base(key), Judged(key), bar)
end

-- The same for what "Add by name or spell ID" finds, as it would go on a bar:
-- judged by the ID dragged or typed, else the IDs it would be remembered by,
-- else the entry's. A troll mage dragging the troll's Regeneration is told
-- it's passive, though the mage's Regeneration is in the spellbook.
function S:AddNote(text, bar)
    local found, ids, id = self:Resolve(text)
    if not found then return nil end
    local entry = byKey[found]
    return Untracked(entry and entry.name or found, (id and { id }) or ids or Judged(found), bar)
end

-- Debuffs your own spells put on you. Neither aura bar can show one added by
-- name: the Buffs bar reads your buffs, the Debuffs bar your target's debuffs,
-- and the game hides a debuff on you from a spell ID lookup. "Show your
-- debuffs on you", on either bar, shows them instead (Buffs.lua, F:ApplySelf).
local SELF_DEBUFFS = { [6788] = "Weakened Soul", [11196] = "Recently Bandaged", [25771] = "Forbearance" }

-- One line in the footer (two spilled out of the window in game; 94 letters,
-- Recently Bandaged's, fit on one).
local function SelfNote(name)
    return name .. " can't go on a bar by name. Tick \"Show your debuffs on you\" on Buffs or Debuffs."
end

-- Why typed text (a name or spell ID) or a bar entry's key can't go on a bar
-- because it's one of those debuffs, pointing to the tick that shows it, or nil.
function S:SelfDebuffNote(text)
    if type(text) == "number" then text = tostring(text) end
    if type(text) ~= "string" then return nil end
    local trimmed = Base(text:match("^%s*(.-)%s*$"))
    local id, lower = tonumber(trimmed), trimmed:lower()
    for spellID, name in pairs(SELF_DEBUFFS) do
        if spellID == id or name:lower() == lower then return SelfNote(name) end
    end
    return nil
end

-- The same while typing in the add box: from three letters, any of those
-- debuffs whose name holds the text, or nil.
function S:SelfDebuffMatch(text)
    if type(text) ~= "string" then return nil end
    local lower = text:lower():match("^%s*(.-)%s*$")
    if #lower < 3 then return self:SelfDebuffNote(text) end
    for _, name in pairs(SELF_DEBUFFS) do
        if name:lower():find(lower, 1, true) then return SelfNote(name) end
    end
    return self:SelfDebuffNote(text)
end

-- Whether every one of these IDs is an aura no one learns as a spell
-- (Energized from Read Ley Line, Well Fed from food; ns.AURA_ONLY, from the
-- game data). A pet's ability (a bat's Sonic Blast) or a talent (Holy
-- Shield) isn't, though no class or race in the data names it: someone
-- knows it.
local function OnlyAuras(ids)
    local auras = ns.AURA_ONLY
    if not (auras and ids and ids[1]) then return false end
    for _, id in ipairs(ids) do
        if not auras[id] then return false end
    end
    return true
end

-- Whether an entry on a bar is for you. One profile can serve every class and
-- race: each character passes over what only other characters can have, which
-- stays in the profile for them. Anything in your own spellbook, procs or bags
-- is yours. A passive added to a bar shows for no one where it has nothing to
-- track (S:PassiveNote), and stays in the profile. A buff added by name stays
-- on the Buffs bar whoever casts it (another class's buff can land on you, a
-- gnome priest's Contingency Plan too), unless it's a racial, which no one
-- else can give you. Otherwise a spell is yours when your class and race can
-- have it (ns.SPELL_CLASSES and ns.SPELL_RACES): so not another race's
-- racial (Plainsrunning's buff for anyone but a tauren), nor a race-only
-- class spell. A spell neither names (a profession's, another character's
-- general spell, an all-class one you haven't got) is yours on a cooldown bar
-- only once you know it. Ammo is only for the classes that use it; items are
-- everyone's (the bars leave off any you don't carry). A spell saved by a
-- name a later build changed goes by its new name's classes (a hunter's
-- Immolation Trap Effect). With remember, the IDs B:Add would remember a
-- spell by, it's judged as it would be once added, by those IDs, and for
-- good rather than just now: Bars.lua Vet turns away an add that could
-- never show for you, with nothing left in the window to take it off
-- (another class's or race's spell, or on a cooldown bar a buff's ID no one
-- learns, while the game says you don't know it). One you or your pet don't
-- know yet (a talent not taken, a demon's spell while another demon is
-- out) still goes on, and shows once you do, as it always did.
function S:ForMe(key, bar, remember)
    if type(key) ~= "string" then return false end
    if key == "ammo" then return self:UsesAmmo() end
    Ready()
    local entry = byKey[key]
    if entry and not entry.added then return true end
    if ItemKey(key) then return true end
    local name = Base(key)
    local ids = entry and entry.ids
    if remember then
        if Untracked(name, remember, bar) then return false end
        -- As ScanSaved would watch it: a pinned one by its own ID alone.
        local _, pinned = Pinned(key)
        ids = BuffIDs(not pinned and name or nil, remember)
    elseif self:PassiveNote(key, bar) then
        return false
    end
    local added = entry ~= nil or remember ~= nil
    local classes = ns.SPELL_CLASSES and (ns.SPELL_CLASSES[name] or RENAMED[name] and ns.SPELL_CLASSES[RENAMED[name]])
    local procs = ProcClasses()[name]
    local races = ns.SPELL_RACES and ns.SPELL_RACES[name]
    local racial = races and not classes and not procs
    if added and bar == "buff" and not racial then return true end
    if classes or procs then
        -- While the game won't say your class, it's yours, as it always was.
        local _, class = UnitClass("player")
        if Holds((classes or "") .. " " .. (procs or ""), class) == false then return false end
        if not races then return true end
    end
    if races then
        local race
        if UnitRace then race = select(3, UnitRace("player")) end
        local holds = Holds(races, race)
        if holds ~= nil then return holds end
    end
    -- Anything else not in your spellbook isn't yours, unless added by name
    -- or ID. On the Buffs or Debuffs bar that stays, as it always did: a
    -- talent's or item's effect (Improved Shadow Bolt's Shadow Vulnerability)
    -- is never a spell you know, and only lights while it's up. On a cooldown
    -- bar it's yours once you or your pet know it (and while the game won't
    -- say). About to be added there, only an aura's ID no one ever learns is
    -- judged by that now: anything else goes on, shown once it's known.
    if not added then return false end
    if ns.AURA_BARS and ns.AURA_BARS[bar] then return true end
    if remember and not OnlyAuras(remember) then return true end
    return Knows(ids) ~= false
end

-- Whether an entry on a bar shows there for no one, whichever character
-- uses the profile: on the Cooldowns or Utility bar, a spell no class, race
-- or proc names, remembered only by auras no one learns as a spell (a
-- buff's ID ticked there before such an add was turned away). It's hidden
-- from everyone, with nothing in the window to take it off: Clear takes
-- these too (Bars.lua B:Clear). A pet's ability or a talent another
-- character added stays for them.
function S:Leftover(key, bar)
    if type(key) ~= "string" or (ns.AURA_BARS and ns.AURA_BARS[bar]) then return false end
    Ready()
    local entry = byKey[key]
    local name = Base(key)
    if ns.SPELL_CLASSES and (ns.SPELL_CLASSES[name] or RENAMED[name] and ns.SPELL_CLASSES[RENAMED[name]]) then return false end
    if ProcClasses()[name] or (ns.SPELL_RACES and ns.SPELL_RACES[name]) then return false end
    return OnlyAuras(entry and entry.added)
end

-- The auras one spell ID can carry: its own, and those it leads to (BuffIDs,
-- with no name). For an icon fixed to one rank ("Name@N"), which has no
-- IDs of its own to go by.
function S:AuraIDs(id)
    return BuffIDs(nil, { id })
end

-- An entry's icon, even for a spell you haven't learned yet (from the game
-- data), so the window only shows a question mark for something unknown.
function S:Icon(key)
    Ready()
    local entry = byKey[key]
    if entry and entry.icon then return entry.icon end
    local _, pinned = Pinned(key)
    local ids = pinned and { pinned } or type(key) == "string" and ns.RANKS and ns.RANKS[Base(key)]
    local icon = ids and C_Spell.GetSpellTexture and C_Spell.GetSpellTexture(ids[1])
    return icon or 134400
end

-- Trinkets, bag items, healthstones and potions, and ammunition: nothing
-- that puts an aura on anyone.
function S:IsItem(entry)
    return entry.kind == "item" or entry.kind == "slot" or entry.kind == "ammo" or entry.kind == "family"
end

-- The healthstone or potion family an item is a rank of, if any: dragging
-- any rank in adds the family. Its key and name.
function S:Family(itemID)
    return Open(itemID) and itemID ~= nil and familyOf[itemID] or nil
end

-- Arrows or shot of any kind or level, equipped or not: what goes in the ammo
-- slot, by where it's worn or its item class. Anything unreadable isn't ammo.
function S:IsAmmo(itemID)
    if not (Open(itemID) and type(itemID) == "number" and C_Item and C_Item.GetItemInfoInstant) then return false end
    local _, _, _, worn, _, classID = C_Item.GetItemInfoInstant(itemID)
    if Open(worn) and worn == "INVTYPE_AMMO" then return true end
    local projectile = Enum and Enum.ItemClass and Enum.ItemClass.Projectile or 6
    return Open(classID) and classID == projectile or false
end

-- Names to offer while typing in the add box. Your own spells, procs and items
-- come before other classes' spells from the game data; within each, names
-- that start with the text, then a word that does, then (from three letters
-- on) any match, each alphabetically.
function S:Suggest(text, limit)
    text = type(text) == "string" and text:lower():match("^%s*(.-)%s*$") or ""
    if #text < 2 then return {} end
    Ready()
    local seen, found = {}, {}
    local function Consider(name, icon, spellID, own)
        if seen[name] then return end
        seen[name] = true
        local lower = name:lower()
        local at = lower:find(text, 1, true)
        if not at then return end
        local place = at == 1 and 1 or lower:sub(at - 1, at - 1):match("[%s%p]") and 2 or 3
        if place == 3 and #text < 3 then return end
        found[#found + 1] = { name = name, icon = icon, spellID = spellID, tier = (own and 0 or 3) + place }
    end
    for _, entry in ipairs(list) do Consider(entry.name, entry.icon, entry.spellID, true) end
    for name, ids in pairs(ns.RANKS or {}) do Consider(name, nil, ids[#ids], false) end
    table.sort(found, function(a, b)
        if a.tier ~= b.tier then return a.tier < b.tier end
        return a.name < b.name
    end)
    local out = {}
    for i = 1, math.min(#found, limit or 8) do out[i] = found[i] end
    return out
end

-- Works out what "Add by name or spell ID" means. Returns the key to store,
-- the spell IDs to remember when it isn't in your spellbook (by name, the
-- game data's: the highest rank you or your pet know, else its highest
-- with a cooldown, so a hunter's Growl is his pet's even with the pet away),
-- and the ID given (if one was), or nil and why.
function S:Resolve(text)
    text = type(text) == "string" and text:match("^%s*(.-)%s*$") or ""
    if text == "" then return nil, "Type a spell name or ID first." end
    Ready()
    local id = tonumber(text)
    if id then
        local name = C_Spell.GetSpellName and Text(C_Spell.GetSpellName(id))
        if not name then return nil, "No spell has ID " .. id .. "." end
        if byKey[name] then return name, nil, id end
        return name, { id }, id
    end
    local lower = text:lower()
    for key, entry in pairs(byKey) do
        if entry.name:lower() == lower then return key end
    end
    for name, ids in pairs(ns.RANKS or {}) do
        if name:lower() == lower then return name, { HighestKnown(ids) or Highest(ids) } end
    end
    local info = C_Spell.GetSpellInfo and C_Spell.GetSpellInfo(text)
    local name = info and Text(info.name)
    if name and info.spellID then return name, { info.spellID } end
    return nil, "No spell called \"" .. text .. "\" was found."
end

-- The key a spell ID (typed, searched or dragged) goes on a bar under when
-- it's pinned already in your lists (on any bar, so the Cooldowns bar never
-- hands its ID to the entry of its name too), or on the Buffs or Debuffs bar
-- when it's another spell of a name in your lists: pinned to that ID, when
-- the entry of that name watches none of the auras it would (the second
-- Energized). A name only another profile has (remembered for every
-- profile, ns.CustomSpells) counts too, so adding the other one first here
-- never changes what that profile's entry watches. Nil when it goes by its
-- name, as before: a name not in your lists yet, an ID whose aura its entry
-- watches already (the Flurry talent, whose buff is the Flurry proc's; a
-- mage's Regeneration where a troll's is saved; another rank of an aura,
-- or Well Fed from another food, which an entry watches with the rest:
-- BuffIDs), and any other ID on the Cooldowns and Utility bars. So ranks
-- join one icon, as before 1.5.7, and only two different spells of one name
-- get one each.
function S:Pin(id, bar)
    if type(id) ~= "number" then return nil end
    local name = C_Spell.GetSpellName and Text(C_Spell.GetSpellName(id))
    local key = name and PinKey(name, id)
    if not key then return nil end
    Ready()
    if byKey[key] then return key end
    if not (ns.AURA_BARS and ns.AURA_BARS[bar]) then return nil end
    local entry = byKey[name]
    local remembered = not entry and ns.CustomSpells and ns.CustomSpells()[name]
    if not (entry or remembered) then return nil end
    local watched = {}
    for _, each in ipairs(entry and (entry.ids or {}) or BuffIDs(name, remembered)) do watched[each] = true end
    for _, aura in ipairs(BuffIDs(nil, { id })) do
        if watched[aura] then return nil end
    end
    return key
end
