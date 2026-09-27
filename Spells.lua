-- The player's spellbook, one entry per spell at its highest known rank, plus
-- the buffs their class's talents can proc. Classic Bars store spells by name
-- and look them up here, so training a new rank moves every bar onto it
-- without any change to the saved setup.
local _, ns = ...

local S = {}
ns.Spells = S

local BANK = Enum and Enum.SpellBookSpellBank and Enum.SpellBookSpellBank.Player or 0
local ITEM = Enum and Enum.SpellBookItemType or {}

-- Buffs that talents put on you, which have no spellbook entry; every rank's
-- spell ID is listed. Names and icons come from the game.
local PROCS = {
    DRUID = { { 16870 }, { 16886 } }, -- Clearcasting, Nature's Grace
    MAGE = { { 12536 } }, -- Clearcasting
    PRIEST = { { 15271 } }, -- Spirit Tap
    SHAMAN = { { 16246 }, { 16257, 16277, 16278, 16279, 16280 } }, -- Clearcasting, Flurry
    WARRIOR = { { 12966, 12967, 12968, 12969, 12970 }, { 12880, 14201, 14202, 14203, 14204 } }, -- Flurry, Enrage
    WARLOCK = { { 17941 } }, -- Shadow Trance
    ROGUE = { { 14143, 14149 } }, -- Remorseless Attacks
    HUNTER = { { 6150 } }, -- Quick Shots
    PALADIN = { { 20050, 20052, 20053, 20054, 20055 }, { 20128, 20131, 20132, 20133, 20134 } }, -- Vengeance, Redoubt
}
S.PROCS = PROCS
S.PROC_LINE = "Procs"

local list, byName = {}, {}

local function Open(value)
    return not (issecretvalue and issecretvalue(value))
end

local function AddProcs()
    local _, class = UnitClass("player")
    for _, ids in ipairs(PROCS[class] or {}) do
        local name = C_Spell.GetSpellName and C_Spell.GetSpellName(ids[1])
        if type(name) == "string" and Open(name) and name ~= "" and not byName[name] then
            local entry = { name = name, line = S.PROC_LINE, proc = true, ids = ids, spellID = ids[1],
                icon = C_Spell.GetSpellTexture(ids[1]), rank = 0, rankText = "" }
            byName[name] = entry
            list[#list + 1] = entry
        end
    end
end

-- Rebuilds the list in spellbook order, grouped by spellbook tab, with the
-- class procs last. Passive spells, future spells and flyouts are left out.
function S:Scan()
    wipe(list)
    wipe(byName)
    if not (C_SpellBook and C_SpellBook.GetNumSpellBookSkillLines) then return list end
    for line = 1, C_SpellBook.GetNumSpellBookSkillLines() or 0 do
        local info = C_SpellBook.GetSpellBookSkillLineInfo(line)
        if info and not info.shouldHide and (info.offSpecID or 0) == 0 then
            local first = (info.itemIndexOffset or 0) + 1
            local last = (info.itemIndexOffset or 0) + (info.numSpellBookItems or 0)
            for index = first, last do
                local kind = C_SpellBook.GetSpellBookItemType(index, BANK)
                if kind ~= ITEM.FutureSpell and kind ~= ITEM.Flyout then
                    local item = C_SpellBook.GetSpellBookItemInfo(index, BANK)
                    local name = item and item.name
                    local spellID = item and (item.spellID or item.actionID)
                    if name and spellID and not item.isPassive and Open(name) and type(name) == "string" then
                        local sub = Open(item.subName) and type(item.subName) == "string" and item.subName or ""
                        local rank = tonumber(sub:match("%d+")) or 0
                        local entry = byName[name]
                        if not entry then
                            entry = { name = name, line = info.name or "", ids = {}, rank = -1 }
                            byName[name] = entry
                            list[#list + 1] = entry
                        end
                        entry.ids[#entry.ids + 1] = spellID
                        if rank >= entry.rank then
                            entry.spellID, entry.icon, entry.rank = spellID, item.iconID, rank
                            entry.rankText = sub
                        end
                    end
                end
            end
        end
    end
    AddProcs()
    return list
end

function S:List()
    return list
end

function S:Find(name)
    return byName[name]
end
