-- The player's spellbook, one entry per spell at its highest known rank.
-- Classic Bars store spells by name and look them up here, so training a new
-- rank moves every bar onto it without any change to the saved setup.
local _, ns = ...

local S = {}
ns.Spells = S

local BANK = Enum and Enum.SpellBookSpellBank and Enum.SpellBookSpellBank.Player or 0
local ITEM = Enum and Enum.SpellBookItemType or {}

local list, byName = {}, {}

local function Open(value)
    return not (issecretvalue and issecretvalue(value))
end

-- Rebuilds the list in spellbook order, grouped by spellbook tab. Passive
-- spells, future spells and flyouts are left out.
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
                            entry = { name = name, line = info.name or "" }
                            byName[name] = entry
                            list[#list + 1] = entry
                            entry.rank = -1
                        end
                        if rank >= entry.rank then
                            entry.spellID, entry.icon, entry.rank = spellID, item.iconID, rank
                            entry.rankText = sub
                        end
                    end
                end
            end
        end
    end
    return list
end

function S:List()
    return list
end

function S:Find(name)
    return byName[name]
end
