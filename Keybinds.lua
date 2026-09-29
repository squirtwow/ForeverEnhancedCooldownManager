-- The key that casts each spell or uses each item on your bars, found from the
-- action bar slot holding it, for the key text on the icons. What each action
-- slot holds, and the key each bar button is bound to, are read outside combat
-- only. In a fight the main bar can still change page (forms, stances, paging
-- keys); the keys follow from what was read. Nothing is read while the option
-- is off.
local _, ns = ...

local K = {}
ns.Keybinds = K

local BUTTONS = 12
local SLOTS = 18 * BUTTONS -- every page: six main pages, form/stance pages, side bars, vehicle bars
K.SLOTS = SLOTS -- for the tests
local DELAY = .3 -- action bar changes come in bursts: one read once they settle
local MAIN = { "ACTIONBUTTON", "ActionButton" }
local BARS = { -- side bars always hold the same slots: binding, button name, first slot
    { "MULTIACTIONBAR1BUTTON", "MultiBarBottomLeftButton", 61 },
    { "MULTIACTIONBAR2BUTTON", "MultiBarBottomRightButton", 49 },
    { "MULTIACTIONBAR3BUTTON", "MultiBarRightButton", 25 },
    { "MULTIACTIONBAR4BUTTON", "MultiBarLeftButton", 37 },
    { "MULTIACTIONBAR5BUTTON", "MultiBar5Button", 145 },
    { "MULTIACTIONBAR6BUTTON", "MultiBar6Button", 157 },
    { "MULTIACTIONBAR7BUTTON", "MultiBar7Button", 169 },
}
local RESCAN = { "PLAYER_ENTERING_WORLD", "ACTIONBAR_SLOT_CHANGED", "UPDATE_BINDINGS", "UPDATE_MACROS",
    "SPELLS_CHANGED", "PLAYER_EQUIPMENT_CHANGED" }
local REPAGE = { ACTIONBAR_PAGE_CHANGED = true, UPDATE_BONUS_ACTIONBAR = true, UPDATE_SHAPESHIFT_FORM = true,
    UPDATE_VEHICLE_ACTIONBAR = true, UPDATE_OVERRIDE_ACTIONBAR = true }

local actions = {} -- slot -> { spell=, item=, name=, macro= }   (read outside combat)
local bound = {} -- binding -> key text                           (read outside combat)
local bySpell, byItem, byName = {}, {}, {} -- id/name -> { text=, tier= } for what the keys press now

-- Every value from the game passes through one of these before it is
-- compared or used as a key.
local function Open(v) return not (issecretvalue and issecretvalue(v)) end
local function Number(v) if Open(v) and type(v) == "number" then return v end end
local function Word(v) if Open(v) and type(v) == "string" and v ~= "" then return v end end
local function Call(fn, ...)
    if type(fn) ~= "function" then return nil end
    local ok, a, b, c = pcall(fn, ...)
    if ok then return a, b, c end
end

-- Keys ------------------------------------------------------------------------------
-- Shortened from the raw key, as action bars show them (1, S2, M4), so it
-- doesn't depend on the game's language.
local MODIFIERS = { ALT = "A", CTRL = "C", SHIFT = "S", META = "Cm" } -- game joins them ALT, CTRL, SHIFT, META
local SHORT = { MOUSEWHEELUP = "WU", MOUSEWHEELDOWN = "WD", NUMPADPLUS = "N+", NUMPADMINUS = "N-",
    NUMPADMULTIPLY = "N*", NUMPADDIVIDE = "N/", NUMPADDECIMAL = "N.", SPACE = "Sp", ESCAPE = "Esc", TAB = "Tab",
    ENTER = "Ent", BACKSPACE = "Bs", CAPSLOCK = "Caps", INSERT = "Ins", DELETE = "Del", HOME = "Hm", END = "End",
    PAGEUP = "PU", PAGEDOWN = "PD", UP = "Up", DOWN = "Dn", LEFT = "Lt", RIGHT = "Rt", PRINTSCREEN = "PS" }

function K:Format(key)
    key = Word(key)
    if not key then return nil end
    local mods = ""
    while true do
        local mod, rest = key:match("^(%u+)%-(.+)$")
        if not (mod and MODIFIERS[mod]) then break end
        mods, key = mods .. MODIFIERS[mod], rest
    end
    if key:match("^PAD") then return nil end -- gamepad buttons: the gamepad bars aren't read
    local short = SHORT[key]
    if not short then
        short = key:gsub("^BUTTON(%d+)$", "M%1")
        short = short:gsub("^NUMPAD", "N")
    end
    return mods .. short
end

-- Reading, outside combat -------------------------------------------------------------

-- A macro's spell, or the item it uses (/use 13 included).
local function Macro(index)
    if not index then return nil end
    local spell = Number((Call(GetMacroSpell, index)))
    if spell then return { spell = spell, macro = true } end
    local _, link = Call(GetMacroItem, index)
    link = Word(link)
    local item = link and tonumber(link:match("item:(%d+)"))
    if item then return { item = item, macro = true } end
end

-- What one action slot casts or uses. Other kinds (flyouts, companions,
-- equipment sets) have nothing to match.
local function Read(slot)
    local kind, id, sub = Call(GetActionInfo, slot)
    if not (Open(kind) and Open(id) and Open(sub)) then return nil end
    local action
    if kind == "spell" then
        action = { spell = Number(id) }
    elseif kind == "item" then
        action = { item = Number(id) }
    elseif kind == "macro" then
        if sub == "spell" then
            action = { spell = Number(id), macro = true } -- #showtooltip / shown spell
        elseif sub == "item" then
            action = { item = Number(id), macro = true }
        else
            action = Macro(Number(id))
        end
    end
    if not (action and (action.spell or action.item)) then return nil end
    if action.item then
        -- An item's use spell, which is what Blizzard's bag-item icons give.
        -- Items are never recorded by name, so none is taken for a spell.
        local _, spell = Call(C_Item and C_Item.GetItemSpell, action.item)
        action.spell = Number(spell)
    else
        action.name = Word((Call(C_Spell and C_Spell.GetSpellName, action.spell)))
    end
    return action
end

-- The first key bound to a bar button, by its binding or a click on it.
local function Bound(binding, button)
    local key = Word((Call(GetBindingKey, binding)))
    if not key then key = Word((Call(GetBindingKey, "CLICK " .. button .. ":LeftButton"))) end
    return key and K:Format(key) or nil
end

-- Every slot and every bar's keys, hidden side bars included since their
-- keys still work.
local function Scan()
    wipe(actions)
    wipe(bound)
    for slot = 1, SLOTS do actions[slot] = Read(slot) end
    for i = 1, BUTTONS do
        bound[MAIN[1] .. i] = Bound(MAIN[1] .. i, MAIN[2] .. i)
        for _, bar in ipairs(BARS) do bound[bar[1] .. i] = Bound(bar[1] .. i, bar[2] .. i) end
    end
end

-- Which keys press what, now ------------------------------------------------------------

-- The page the main bar's keys press now, in Blizzard's own order, from
-- answers that stay open in combat.
local function Has(name)
    local f = C_ActionBar and C_ActionBar[name]
    local v = Call(f)
    return Open(v) and v == true
end
local function Index(name) return Number((Call(C_ActionBar and C_ActionBar[name]))) end
local function MainPage()
    if Has("HasVehicleActionBar") then return Index("GetVehicleBarIndex") end
    if Has("HasOverrideActionBar") then return Index("GetOverrideBarIndex") end
    if Has("HasTempShapeshiftActionBar") then return Index("GetTempShapeshiftBarIndex") end
    local page = Index("GetActionBarPage") or 1
    if page == 1 and Has("HasBonusActionBar") then return Index("GetBonusBarIndex") or 1 end
    return page
end

-- A spell in several slots shows the key that casts it: one placed directly
-- (tier 1) before a macro (tier 2); then the main bar at the page its keys
-- press now, then the side bars in order, then the lower button.
local function Put(map, id, text, tier)
    if id == nil then return end
    local was = map[id]
    if not was or tier < was.tier then map[id] = { text = text, tier = tier } end
end
local function Take(slot, binding)
    local action, text = actions[slot], bound[binding]
    if not (action and text) then return end
    local tier = action.macro and 2 or 1
    Put(bySpell, action.spell, text, tier)
    Put(byItem, action.item, text, tier)
    if not action.item then Put(byName, action.name, text, tier) end
end

-- From what was read only, so safe in combat.
local function Resolve()
    wipe(bySpell)
    wipe(byItem)
    wipe(byName)
    local page = MainPage()
    if page then
        for i = 1, BUTTONS do Take((page - 1) * BUTTONS + i, MAIN[1] .. i) end
    end
    for _, bar in ipairs(BARS) do
        for i = 1, BUTTONS do Take(bar[3] + i - 1, bar[1] .. i) end
    end
end

-- Public --------------------------------------------------------------------------------

local function Push()
    if ns.Bars then ns.Bars:ShowKeys() end
    if ns.Skin then ns.Skin:ShowKeys() end
    -- And the Layout page's drawing of your bars, while it's open.
    local page = ns.window and ns.window.pages and ns.window.pages.layout
    if page and page.ShowKeys and page:IsVisible() then page:ShowKeys() end
end

-- Reads everything again and shows the keys: now, or once the fight is over.
function K:Update()
    if not ns.Get("keybinds") then
        wipe(actions)
        wipe(bound)
        wipe(bySpell)
        wipe(byItem)
        wipe(byName)
        self.pending = nil
        Push()
        return
    end
    if InCombatLockdown() then
        self.pending = true
        return
    end
    self.pending = nil
    Scan()
    Resolve()
    Push()
end

-- The main bar changed page: its keys press other slots now. In a fight too.
function K:Repage()
    if not ns.Get("keybinds") then return end
    Resolve()
    Push()
end

-- At most one read every DELAY: one-button helpers can change a slot every
-- global cooldown.
local queued
local function Later()
    if queued then return end
    queued = true
    C_Timer.After(DELAY, function()
        queued = false
        K:Update()
    end)
end

local function Lookup(map, id)
    local found = id ~= nil and map[id]
    return found and found.text or nil
end

-- The key for one of your bar's entries (Spells.lua). A spell uses its
-- highest rank's key, or any rank's; a fixed rank only its own. Procs and
-- ammunition have nothing to press.
function K:ForEntry(entry)
    if not entry then return nil end
    if entry.kind == "spell" then return Lookup(bySpell, entry.spellID) or Lookup(byName, entry.name) end
    if entry.kind == "rank" then return Lookup(bySpell, entry.spellID) end
    if entry.kind == "item" or entry.kind == "slot" then return Lookup(byItem, entry.itemID) end
    return nil
end

-- The key for a spell ID, as Blizzard's icons give it (their base spell):
-- that rank, or any rank of the same name.
function K:ForSpell(id)
    id = Number(id)
    if not id then return nil end
    local key = Lookup(bySpell, id)
    if key then return key end
    local name = Word((Call(C_Spell and C_Spell.GetSpellName, id)))
    return name and Lookup(byName, name) or nil
end

-- The key for whatever is equipped in an inventory slot (a trinket).
function K:ForSlot(slot)
    slot = Number(slot)
    if not slot then return nil end
    local item = Number((Call(GetInventoryItemID, "player", slot)))
    return item and Lookup(byItem, item) or nil
end

function K:Start()
    if self.started then return end
    self.started = true
    local frame = CreateFrame("Frame")
    for _, event in ipairs(RESCAN) do frame:RegisterEvent(event) end
    for event in pairs(REPAGE) do frame:RegisterEvent(event) end
    frame:RegisterEvent("PLAYER_REGEN_ENABLED")
    frame:SetScript("OnEvent", function(_, event)
        if not ns.Get("keybinds") then return end
        if event == "PLAYER_REGEN_ENABLED" then
            -- Anything that changed in the fight; Blizzard's icons whose spell
            -- was secret then get their key now.
            if K.pending then K:Update() else Push() end
        elseif REPAGE[event] then
            K:Repage()
        elseif InCombatLockdown() then
            K.pending = true
        else
            Later()
        end
    end)
end
