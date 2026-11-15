-- The key that casts each spell or uses each item on your bars, found from the
-- action bar slot holding it, for the key text on the icons. What each action
-- slot holds, and the key each bar button is bound to, are read outside combat
-- only. In a fight the main bar can still change page (forms, stances, paging
-- keys); the keys follow from what was read. Nothing is read while the option
-- is off.
-- Key press glow (a player's idea, Squirt's yes, 15 Nov 2026) reads the same:
-- while it's ticked, the bar buttons whose keys press each spell or item now
-- are kept beside its key, for Bars.lua to read each button's state (pushed
-- or not) and light the icon. A button is only ever looked at: nothing is set
-- on it, hooked or written to it. Nothing is read while both are off.
local _, ns = ...

local K = {}
ns.Keybinds = K

local BUTTONS = 12
local SLOTS = 18 * BUTTONS -- every page: six main pages, form/stance pages, side bars, vehicle bars
K.SLOTS = SLOTS -- for the tests
local DELAY = .3 -- action bar changes come in bursts: one read once they settle
local SETTLE = .25 -- a bar addon's page follows a stance change within this long
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
local blizzard = {} -- binding -> Blizzard's bar button for it, Key press glow only (found by name, never touched)
local own = {} -- a bar addon's buttons that have a key             (read outside combat)
local ownBinding = {} -- bindings those buttons answer instead of Blizzard's
local OWN_BUTTONS = 15 * BUTTONS
local PAGE_BINDING = { [1] = MAIN[1] } -- a bar page's own Blizzard binding, if it has one
for _, bar in ipairs(BARS) do PAGE_BINDING[(bar[3] - 1) / BUTTONS + 1] = bar[1] end
-- The pages a main bar can turn to for a form or stance. A spell waiting on
-- one still shows its key while you're in another stance, below any key that
-- casts it now.
local AWAY_PAGES = { 1, 2, 7, 8, 9, 10 }
-- What the keys press now, by spell ID, item ID and spell name: each key's
-- text, and its tier beside it (lower wins), so working them out again as
-- the main bar changes page makes nothing new. With Key press glow, every
-- bar button whose key presses it now too (buttons, a list each).
local function Map() return { text = {}, tier = {}, buttons = {} } end
local bySpell, byItem, byName = Map(), Map(), Map()
local merged = {} -- a healthstone or potion family's buttons, all its items' together (K:ButtonsForEntry)
local pressing = false -- Key press glow ticked, as the keys were last worked out
local function Clear(map)
    wipe(map.text)
    wipe(map.tier)
    wipe(map.buttons)
end

-- Whether anything wants the keys read: Keybinds on icons, or Key press glow.
local function Wanted()
    return ns.Get("keybinds") == true or ns.Get("keyPressGlow") == true
end

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

-- A bar addon's buttons, with a key on them. Such a bar turns its own pages,
-- by stance say, while Blizzard's page stands still, so the button itself says
-- what its key presses now. Only keys are kept here: the slot is asked for
-- each time, and a button's attributes can be read in a fight.
local function KeyOf(binding)
    local key = Word((Call(GetBindingKey, binding)))
    return key and K:Format(key) or nil
end

local function AddOwn(button, id)
    local name = Word((Call(button.GetName, button)))
    if not name then return end
    local page, index = math.floor((id - 1) / BUTTONS) + 1, (id - 1) % BUTTONS + 1
    local binding = Word((Call(button.GetAttribute, button, "commandName")))
    if not binding and PAGE_BINDING[page] then binding = PAGE_BINDING[page] .. index end
    local text = binding and KeyOf(binding)
    if text then
        ownBinding[binding] = true
    else
        text = KeyOf("CLICK " .. name .. ":Keybind") or KeyOf("CLICK " .. name .. ":HOTKEY")
            or KeyOf("CLICK " .. name .. ":LeftButton")
    end
    if text then own[#own + 1] = { button = button, id = id, index = index, main = page == 1, text = text } end
end

local function ById(a, b) return a.id < b.id end

local function ScanOwn()
    wipe(own)
    wipe(ownBinding)
    for id = 1, OWN_BUTTONS do
        local button = _G["BT4Button" .. id]
        if type(button) == "table" then AddOwn(button, id) end
    end
    local other = _G.Dominos and _G.Dominos.ActionButtons and _G.Dominos.ActionButtons.buttons
    if type(other) == "table" then
        for button, id in pairs(other) do
            id = Number(id)
            if id and type(button) == "table" then AddOwn(button, id) end
        end
    end
    table.sort(own, ById) -- the main bar first, then the lower button
end

-- The action slot a bar addon's button holds right now, or nil.
local function SlotOf(button)
    local state = Call(button.GetAttribute, button, "state")
    if not Open(state) then return nil end
    if state ~= nil then
        state = tostring(state)
        local kind = Call(button.GetAttribute, button, "labtype-" .. state)
        if not Open(kind) then return nil end
        if kind == "action" then return Number((Call(button.GetAttribute, button, "labaction-" .. state))) end
        if kind ~= nil then return nil end -- that page holds something other than an action slot
    end
    return Number((Call(button.GetAttribute, button, "action")))
end

-- Every slot and every bar's keys, hidden side bars included since their
-- keys still work.
local function Scan()
    wipe(actions)
    wipe(bound)
    wipe(blizzard) -- (found again as the keys are worked out, with Key press glow)
    for slot = 1, SLOTS do actions[slot] = Read(slot) end
    for i = 1, BUTTONS do
        bound[MAIN[1] .. i] = Bound(MAIN[1] .. i, MAIN[2] .. i)
        for _, bar in ipairs(BARS) do bound[bar[1] .. i] = Bound(bar[1] .. i, bar[2] .. i) end
    end
    ScanOwn()
end

-- Blizzard's own bar buttons by their binding, for Key press glow: only
-- found by name, never touched.
local function Button(name)
    local button = _G[name]
    return type(button) == "table" and button or nil
end
local function FindButtons()
    for i = 1, BUTTONS do
        blizzard[MAIN[1] .. i] = Button(MAIN[2] .. i)
        for _, bar in ipairs(BARS) do blizzard[bar[1] .. i] = Button(bar[2] .. i) end
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
-- press now, then the side bars in order, then the lower button. With Key
-- press glow every button that presses it now is kept, each once: holding
-- any of their keys lights it. A main bar page its keys don't press now
-- (away) gives no button.
local function Put(map, id, text, tier, button)
    if id == nil then return end
    local was = map.tier[id]
    if not was or tier < was then map.text[id], map.tier[id] = text, tier end
    if not button then return end
    local list = map.buttons[id]
    if not list then
        map.buttons[id] = { button }
        return
    end
    for i = 1, #list do
        if list[i] == button then return end
    end
    list[#list + 1] = button
end
local function Give(action, text, away, button)
    if not (action and text) then return end
    local tier = (action.macro and 2 or 1) + (away and 2 or 0)
    if away or not pressing then button = nil end
    Put(bySpell, action.spell, text, tier, button)
    Put(byItem, action.item, text, tier, button)
    if not action.item then Put(byName, action.name, text, tier, button) end
end
local function Take(slot, binding)
    if ownBinding[binding] then return end -- a bar addon's button answers that key
    Give(actions[slot], bound[binding], nil, blizzard[binding])
end

-- From what was read only, so safe in combat.
local function Resolve()
    Clear(bySpell)
    Clear(byItem)
    Clear(byName)
    wipe(merged)
    pressing = ns.Get("keyPressGlow") == true
    if pressing and next(blizzard) == nil then FindButtons() end
    for i = 1, #own do
        local entry = own[i]
        local slot = SlotOf(entry.button)
        if slot then Give(actions[slot], entry.text, nil, entry.button) end
    end
    for i = 1, #own do
        local entry = own[i]
        if entry.main then
            for p = 1, #AWAY_PAGES do
                Give(actions[(AWAY_PAGES[p] - 1) * BUTTONS + entry.index], entry.text, true)
            end
        end
    end
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
    if not Wanted() then
        wipe(actions)
        wipe(bound)
        wipe(blizzard)
        wipe(own)
        wipe(ownBinding)
        Clear(bySpell)
        Clear(byItem)
        Clear(byName)
        wipe(merged)
        pressing = false
        self.pending = nil
        Push()
        return
    end
    if InCombatLockdown() then
        self.pending = true
        -- Key press glow ticked or unticked in a fight, your bars already
        -- read for the keybinds: its buttons worked out from what was read
        -- (as a page change is in a fight). All read again once it's over.
        if next(actions) ~= nil and pressing ~= (ns.Get("keyPressGlow") == true) then
            Resolve()
            Push()
        end
        return
    end
    self.pending = nil
    Scan()
    Resolve()
    Push()
end

-- The main bar changed page: its keys press other slots now. In a fight too.
function K:Repage()
    if not Wanted() then return end
    Resolve()
    Push()
end

-- A form change, a stance or a paging key brings several page changes at
-- once: the keys are worked out once, on the next frame.
local repaging = false
local settling = false
local function Settled()
    settling = false
    K:Repage()
end
local function Repaged()
    repaging = false
    K:Repage()
    -- A bar addon's bar can turn its page a moment after the event.
    if #own > 0 and not settling then
        settling = true
        C_Timer.After(SETTLE, Settled)
    end
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
    return id ~= nil and map.text[id] or nil
end

-- The key for one of your bar's entries (Spells.lua). A spell uses its
-- highest rank's key, or any rank's; a fixed rank only its own. A
-- healthstone or potion family uses the key for the one it shows, or for any
-- rank, the best first. Procs and ammunition have nothing to press.
function K:ForEntry(entry)
    if not entry then return nil end
    if entry.kind == "spell" then return Lookup(bySpell, entry.spellID) or Lookup(byName, entry.name) end
    if entry.kind == "rank" then return Lookup(bySpell, entry.spellID) end
    if entry.kind == "item" or entry.kind == "slot" then return Lookup(byItem, entry.itemID) end
    if entry.kind == "family" then
        local key = Lookup(byItem, entry.itemID)
        local items = entry.family and entry.family.items or {}
        for i = #items, 1, -1 do key = key or Lookup(byItem, items[i]) end
        return key
    end
    return nil
end

-- Key press glow: the bar buttons whose keys press one of your bar's entries
-- now, found as its key is (K:ForEntry), as a list, or nil with none (or the
-- tick off). A spell counts any rank's buttons, a fixed rank only its own;
-- a healthstone or potion family every one of its items'. Lists are the
-- addon's own, made again each time the keys are worked out: Bars.lua
-- reads each button's state from them and never changes them.
local function Buttons(map, id)
    return id ~= nil and map.buttons[id] or nil
end
local function Join(list, more)
    if not more then return end
    for _, button in ipairs(more) do
        local found = false
        for i = 1, #list do found = found or list[i] == button end
        if not found then list[#list + 1] = button end
    end
end

function K:ButtonsForEntry(entry)
    if not (pressing and entry) then return nil end
    if entry.kind == "spell" then return Buttons(byName, entry.name) or Buttons(bySpell, entry.spellID) end
    if entry.kind == "rank" then return Buttons(bySpell, entry.spellID) end
    if entry.kind == "item" or entry.kind == "slot" then return Buttons(byItem, entry.itemID) end
    if entry.kind == "family" then
        local list = merged[entry]
        if list == nil then
            list = {}
            Join(list, Buttons(byItem, entry.itemID))
            local items = entry.family and entry.family.items or {}
            for i = #items, 1, -1 do Join(list, Buttons(byItem, items[i])) end
            if #list == 0 then list = false end
            merged[entry] = list
        end
        return list or nil
    end
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
        if not Wanted() then return end
        if event == "PLAYER_REGEN_ENABLED" then
            -- Anything that changed in the fight; Blizzard's icons whose spell
            -- was secret then get their key now.
            if K.pending then K:Update() else Push() end
        elseif REPAGE[event] then
            if not repaging then
                repaging = true
                C_Timer.After(0, Repaged)
            end
        elseif InCombatLockdown() then
            K.pending = true
        else
            Later()
        end
    end)
end
