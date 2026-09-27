-- Everything a Classic Bar can show, one entry each: your spells at their
-- highest known rank, your class's talent procs, your trinkets and usable bag
-- items, and spells added by name or ID. Bars store each entry's key (a spell
-- name, "item:<id>" or "slot:<n>"), so training a new rank or swapping a
-- trinket moves every bar along without any change to the saved setup.
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

local list, byKey = {}, {}

local function Open(value)
    return not (issecretvalue and issecretvalue(value))
end

local function Text(value)
    return type(value) == "string" and Open(value) and value ~= "" and value or nil
end

-- Every spell ID a buff of this name can carry: the ranks you know, all ranks
-- in the game data, and its group version.
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
                            line = info.name or "", known = {}, rank = -1 })
                        entry.known[#entry.known + 1] = spellID
                        if rank >= entry.rank then
                            entry.spellID, entry.icon, entry.rank = spellID, item.iconID, rank
                            entry.rankText = sub
                        end
                    end
                end
            end
        end
    end
    for _, entry in ipairs(list) do entry.ids = BuffIDs(entry.name, entry.known) end
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

-- Food, drink and recipes can be used but never have a cooldown to show.
local RECIPE, CONSUMABLE, FOOD_AND_DRINK = 9, 0, 5
local function NoCooldown(itemID)
    if not (C_Item and C_Item.GetItemInfoInstant) then return false end
    local _, _, _, _, _, classID, subclassID = C_Item.GetItemInfoInstant(itemID)
    return classID == RECIPE or (classID == CONSUMABLE and subclassID == FOOD_AND_DRINK)
end

-- Your two trinket slots, whatever is in them, then usable items in your bags.
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
-- added by name or ID, and items you've run out of.
local function ScanSaved()
    local custom = ns.CustomSpells and ns.CustomSpells() or {}
    for _, key in ipairs(ns.BAR_KEYS) do
        for _, saved in ipairs(ns.BarData(key).spells) do
            if not byKey[saved] then
                local itemID = tonumber(saved:match("^item:(%d+)$"))
                if itemID then
                    AddItem(itemID)
                elseif custom[saved] then
                    local ids = BuffIDs(saved, custom[saved])
                    Add({ key = saved, name = saved, kind = "spell", line = S.LINES.added, ids = ids,
                        spellID = ids[#ids], icon = C_Spell.GetSpellTexture(ids[1]), rankText = "", added = true })
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

-- Names to offer while typing in the add box. Your own spells, procs and items
-- come before other classes' spells from the game data; within each, names
-- that start with the text, then a word that does, then any match, each
-- alphabetically.
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
-- the spell IDs to remember when it isn't in your spellbook, or nil and why.
function S:Resolve(text)
    text = type(text) == "string" and text:match("^%s*(.-)%s*$") or ""
    if text == "" then return nil, "Type a spell name or ID first." end
    local id = tonumber(text)
    if id then
        local name = C_Spell.GetSpellName and Text(C_Spell.GetSpellName(id))
        if not name then return nil, "No spell has ID " .. id .. "." end
        if byKey[name] then return name end
        return name, { id }
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
