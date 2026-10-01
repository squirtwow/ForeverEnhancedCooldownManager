-- Everything a bar can show, one entry each: your spells at their
-- highest known rank, your class's talent procs, your trinkets and usable bag
-- items, healthstones and potions whatever their rank, and spells added by
-- name or ID. Bars store each entry's key (a spell name, "item:<id>",
-- "slot:<n>" or "family:<name>"), so training a new rank, swapping a trinket
-- or carrying a better potion moves every bar along without any change to
-- the saved setup.
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
local FAMILY_NOTE = "Best you carry (Needs testing)"

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

-- Every spell ID a buff of this name can carry: the ranks you know, all ranks
-- in the game data, and its group version. A passive added by its ID also
-- carries the aura of its own it gives (Plainsrunning's speed buff), which
-- is what lights it on the Buffs or Debuffs bar.
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
    local ranks = ns.RANKS or {}
    Add(ranks[name])
    if GROUP[name] then Add(ranks[GROUP[name]]) end
    for _, id in ipairs(known or {}) do
        Add(ns.PASSIVE_BUFFS and ns.PASSIVE_BUFFS[id])
        Add(ns.PASSIVE_DEBUFFS and ns.PASSIVE_DEBUFFS[id])
    end
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

-- Anything on a bar that isn't in your spellbook or bags right now: spells
-- added by name or ID (each keeping the IDs it was added with, as added),
-- items you've run out of (the bars leave them off until you carry one
-- again), your ammo with none equipped, and Mana Potions kept on a bar by a
-- class without mana (a profile shared with one that has it).
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
                elseif custom[saved] then
                    local ids = BuffIDs(saved, custom[saved])
                    Add({ key = saved, name = saved, kind = "spell", line = S.LINES.added, ids = ids,
                        spellID = ids[#ids], icon = C_Spell.GetSpellTexture(ids[1]), rankText = "", added = custom[saved] })
                end
            end
        end
    end
end

function S:Scan()
    wipe(list)
    wipe(byKey)
    ScanSpellbook()
    ScanProcs()
    ScanItems()
    ScanSaved()
    return list
end

function S:List()
    return list
end

function S:Find(key)
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

-- The spells a bar entry is judged by: the ones it was added with, or for a
-- name with nothing else to go on (another character's spell that isn't in
-- your spellbook), the game data's IDs for that name. None for your own
-- spells, procs and items: the spellbook passes over passives.
local function Judged(key)
    local entry = byKey[key]
    if entry then return entry.added end
    local name = key:gsub("@%d+$", "")
    return ns.RANKS and ns.RANKS[name] or ns.PASSIVES and ns.PASSIVES[name]
end

-- Why an entry can't be tracked on a bar because it's passive (Underwater
-- Breathing anywhere, Plainsrunning but on the Buffs bar), or nil.
function S:PassiveNote(key, bar)
    if type(key) ~= "string" then return nil end
    local entry = byKey[key]
    return Untracked(entry and entry.name or (key:gsub("@%d+$", "")), Judged(key), bar)
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
-- everyone's (the bars leave off any you don't carry).
function S:ForMe(key, bar)
    if type(key) ~= "string" then return false end
    if key == "ammo" then return self:UsesAmmo() end
    local entry = byKey[key]
    if entry and not entry.added then return true end
    if ItemKey(key) then return true end
    if self:PassiveNote(key, bar) then return false end
    local name = key:gsub("@%d+$", "")
    local classes = ns.SPELL_CLASSES and ns.SPELL_CLASSES[name]
    local procs = ProcClasses()[name]
    local races = ns.SPELL_RACES and ns.SPELL_RACES[name]
    local racial = races and not classes and not procs
    if entry and bar == "buff" and not racial then return true end
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
    -- bar it's yours once you or your pet know it (and while the game won't say).
    if not entry then return false end
    if ns.AURA_BARS and ns.AURA_BARS[bar] then return true end
    return Knows(entry.ids) ~= false
end

-- An entry's icon, even for a spell you haven't learned yet (from the game
-- data), so the window only shows a question mark for something unknown.
function S:Icon(key)
    local entry = byKey[key]
    if entry and entry.icon then return entry.icon end
    local ids = type(key) == "string" and ns.RANKS and ns.RANKS[(key:gsub("@%d+$", ""))]
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
-- the spell IDs to remember when it isn't in your spellbook, and the ID given
-- (if one was), or nil and why.
function S:Resolve(text)
    text = type(text) == "string" and text:match("^%s*(.-)%s*$") or ""
    if text == "" then return nil, "Type a spell name or ID first." end
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
    for name in pairs(ns.RANKS or {}) do
        if name:lower() == lower then return name, { ns.RANKS[name][1] } end
    end
    local info = C_Spell.GetSpellInfo and C_Spell.GetSpellInfo(text)
    local name = info and Text(info.name)
    if name and info.spellID then return name, { info.spellID } end
    return nil, "No spell called \"" .. text .. "\" was found."
end
