-- The Resource fill on your action bars, with a tick of its own on the
-- Resource fill page (off until it's ticked, and nothing of it runs or is
-- read until then). A spell you can't pay for on an action bar goes dark and
-- fills up from the bottom with the power it needs, exactly as it does on
-- your own bars' icons: every fill is drawn by Fill.lua, so both look the
-- same and there is one lot of drawing code.
--
-- Nothing of your bars is touched. Each button is found by name and only
-- ever looked at: the slot it holds is read from its own action field or its
-- action attribute, and the spell in that slot from the game (GetActionInfo).
-- The fill's layers are made on the button itself, in ARTWORK at its lowest
-- sublevels, which keeps them over the button's own art and under its
-- border, its cooldown swipe and its keybind and count (seen in game, 26 Nov
-- 2026: the swipe is a frame at the button's own level, so a frame of ours
-- draws over it and a texture on the button under it, and the keybind and the
-- count sit far above either way). No attribute is ever set, no method of the
-- bars is ever called, nothing is ever written on a button, and no frame is
-- ever made in a fight: a button that takes a spell mid-fight gets its layers
-- once the fight is over.
--
-- A spell with no cost, an empty slot, an item and a macro that doesn't cast
-- a spell are all left alone. The slots are read again only when the game
-- says they changed (ACTIONBAR_SLOT_CHANGED, ACTIONBAR_PAGE_CHANGED,
-- UPDATE_SHAPESHIFT_FORM, PLAYER_ENTERING_WORLD), never over and over on a
-- timer: a page or a form change reads them once more on the next frame and
-- once more a moment after that, since a bar can turn its own page after the
-- game's word (Again, below). Whether you can pay for what a button holds is
-- the game's own answer (C_Spell.IsSpellUsable, as your own bars' icons go
-- by), and how far up the fill stands is the game's own sum (Fill.lua: your
-- power is a secret this never reads). Every answer the game may keep to
-- itself goes through pcall and Open() first, and one it holds back leaves
-- the fill as it was.
local _, ns = ...

local FB = {}
ns.FillBars = FB

local BUTTONS = 12 -- a bar's buttons
-- Blizzard's own bars, which Forever draws with the shared action bar code:
-- the main bar and the seven side bars, twelve buttons each. A name that
-- isn't there is skipped.
local NAMES = { "ActionButton", "MultiBarBottomLeftButton", "MultiBarBottomRightButton", "MultiBarRightButton",
    "MultiBarLeftButton", "MultiBar5Button", "MultiBar6Button", "MultiBar7Button" }
-- And the buttons the common bar addons make instead: one kind keeps each in
-- a global name of its own, the other in a list of its own. Neither is
-- assumed to be there.
local OWN_BUTTONS = 120
local DROP = -5 -- how far the layers go down inside ARTWORK (Fill.lua's Build)
-- What the game says as your action bars change: a slot, a page, a form, or
-- a loading screen; a bar addon loading later brings its own buttons; and
-- the end of a fight builds what couldn't be built during one.
local EVENTS = { "PLAYER_ENTERING_WORLD", "ACTIONBAR_SLOT_CHANGED", "ACTIONBAR_PAGE_CHANGED", "UPDATE_SHAPESHIFT_FORM",
    "ADDON_LOADED", "PLAYER_REGEN_ENABLED" }
local SETTLE = .25 -- a bar addon's bar can turn its page this long after the event

local list = {} -- every button found, each once, in the order found
local known = {} -- button -> true, so one is never taken twice
local held = {} -- button -> the slot it held when it was last read
local fills = {} -- button -> { parts =, spell = }, only for a spell with a cost
local waiting = false -- a button took a spell in a fight, so its layers wait
local driver, hearing = nil, false
local soon, settling = false, false -- a read already waiting on the next frame, and on the one after SETTLE
local Listen

-- Every answer from the game passes through one of these before it is
-- compared or used (as Keybinds.lua reads your bars).
local function Open(v) return not (issecretvalue and issecretvalue(v)) end
local function Number(v) if Open(v) and type(v) == "number" then return v end end
local function Call(fn, ...)
    if type(fn) ~= "function" then return nil end
    local ok, a, b, c = pcall(fn, ...)
    if ok then return a, b, c end
end

-- Whether the fill is on at all and ticked for your action bars.
function FB:On()
    return ns.Fill ~= nil and ns.Fill:On() and ns.Get("fillBars") == true
end

-- Finding the buttons -----------------------------------------------------------------------

-- A button of your action bars: there, a table, and with the few things a
-- bar button has (all of them read only). Where the game says what it is and
-- it isn't a button, it's left alone.
local function Usable(button)
    if type(button) ~= "table" then return nil end
    if type(button.CreateTexture) ~= "function" or type(button.GetAttribute) ~= "function" then return nil end
    if type(button.GetFrameLevel) ~= "function" or type(button.GetWidth) ~= "function" then return nil end
    local kind = Call(button.GetObjectType, button)
    if Open(kind) and type(kind) == "string" and not kind:find("Button", 1, true) then return nil end
    return button
end

local function Take(button)
    button = Usable(button)
    if not button or known[button] then return end
    known[button] = true
    list[#list + 1] = button
end

-- Every action bar button there is, kept from one look to the next (a button
-- is never unmade): Blizzard's bars first, then a bar addon's own.
local function Find()
    for _, name in ipairs(NAMES) do
        for i = 1, BUTTONS do Take(_G[name .. i]) end
    end
    for i = 1, OWN_BUTTONS do Take(_G["BT4Button" .. i]) end
    local own = _G.Dominos and _G.Dominos.ActionButtons and _G.Dominos.ActionButtons.buttons
    if type(own) == "table" then
        -- Whichever way round that list is kept (a button and its number, or
        -- a number and its button), only a button is ever taken from it.
        for key, value in pairs(own) do
            Take(key)
            Take(value)
        end
    end
end

-- What a button holds -----------------------------------------------------------------------

-- The action slot a button holds now: the one its own code keeps on it, or
-- the attribute its bar set. Only read, never set.
local function Slot(button)
    local slot = Number(button.action)
    if slot then return slot end
    return Number((Call(button.GetAttribute, button, "action")))
end

-- What one slot casts: a spell, or the spell a macro casts. An empty slot,
-- an item and anything else have nothing to fill.
local function SpellOf(slot)
    local kind, id, sub = Call(GetActionInfo, slot)
    if not (Open(kind) and Open(id) and Open(sub)) then return nil end
    if kind == "spell" then return Number(id) end
    if kind ~= "macro" then return nil end
    if sub == "spell" then return Number(id) end -- the spell the macro shows
    local index = Number(id)
    if not index then return nil end
    return Number((Call(GetMacroSpell, index)))
end

-- One button's fill as the game answers for it: shown while the game says
-- you lack the power its spell costs, and gone the moment you can pay for
-- it, which flashes it once (Fill.lua). The answer is the game's own, exactly
-- as Bars.lua's SpellState takes it for your bars' icons, and while the game
-- holds either half of it back, or refuses the question outright, the fill
-- stays as it was. How far up it stands is the game's own sum, so nothing is
-- worked out here.
-- (Each Open() is named again beside the answer it guards instead of being
-- folded into answered, so the rule that every secret answer is read open
-- first can see it on the line that reads it: TestRules.)
local function Show(entry)
    local usable, noMana = Call(C_Spell and C_Spell.IsSpellUsable, entry.spell)
    local answered = Open(usable) and usable ~= nil and Open(noMana)
    local short = Open(usable) and not usable and Open(noMana) and noMana == true
    ns.Fill:Set(entry.parts, entry.spell, short, answered)
end

-- How big a button, or its own picture, is where the game says: a bar addon
-- can set its buttons to any size, and change it later.
local function Size(thing)
    local width = Number((Call(thing.GetWidth, thing)))
    local height = Number((Call(thing.GetHeight, thing)))
    if not (width and height) or width <= 0 or height <= 0 then return nil end
    return width, height
end

-- A button's own picture. The fill is bounded by this rather than by the
-- button, because a button's frame is bigger than its art and filling the
-- frame spills the wash and the wave over the border and into the gap
-- between slots (Squirt saw it, 27 Nov 2026). This client keeps it on
-- button.icon (ActionBarProbe, 26 Nov 2026: "its icon: there, layer
-- BACKGROUND sublevel 0"); the global name is the older shape and is kept as
-- a fallback. Read only: nothing of theirs is ever set. Nil when there is no
-- picture to read, and the fill then bounds itself by the button as it did.
local function Art(button)
    local art = button.icon
    if type(art) ~= "table" then
        local name = Call(button.GetName, button)
        art = Open(name) and type(name) == "string" and _G[name .. "Icon"] or nil
    end
    if type(art) ~= "table" or not Size(art) then return nil end
    return art
end

-- One button's layers, made the first time it holds a spell with a cost and
-- never in a fight: textures on the button itself, under its border, its
-- cooldown swipe, its keybind and its count, with the fill's own frame (which
-- holds nothing a player sees, only the gauges the game measures the level
-- on) at the button's own frame level. A button the game won't give a level
-- or a size for is left alone, and looked at again the next time its bar
-- changes.
local function Layers(button)
    local level = Number((Call(button.GetFrameLevel, button)))
    local art = Art(button)
    local width, height = Size(art or button)
    if not (level and width) then return nil end
    return ns.Fill:Attach(button, level, width, height, DROP, art)
end

-- One button read again: the slot it holds, the spell in that slot, and the
-- fill that follows. A spot with nothing to fill leaves nothing behind.
local function Read(button)
    local entry = fills[button]
    local slot = Slot(button)
    held[button] = slot
    local spell = slot and SpellOf(slot) or nil
    if spell and not ns.Fill:Costed(spell) then spell = nil end
    if not spell then
        if entry then
            entry.spell = nil
            ns.Fill:Drop(entry.parts)
        end
        return
    end
    if not entry then
        -- Nothing is ever made in a fight: it waits for the end of this one.
        if InCombatLockdown() then
            waiting = true
            return
        end
        local parts = Layers(button)
        if not parts then return end
        entry = { parts = parts }
        fills[button] = entry
    else
        -- Its bar may have resized it since. Measured on the picture the
        -- fill is bounded by, the same one Layers used, or the two disagree
        -- and the wave is sized for a box it isn't drawn in.
        local width, height = Size(Art(button) or button)
        if width then ns.Fill:Size(entry.parts, width, height) end
    end
    entry.spell = spell
    Show(entry)
end

-- Working ------------------------------------------------------------------------------------

-- Every button read again (a page turned, your form changed, a loading
-- screen, or a bar addon arrived).
function FB:Reread()
    if not self:On() then return end
    for i = 1, #list do Read(list[i]) end
end

-- One slot changed: only the buttons that were holding it are read again.
-- None given, or the game's nothing-in-particular, reads them all.
function FB:Slot(slot)
    if not self:On() then return end
    if slot == nil or slot == 0 then return self:Reread() end
    for i = 1, #list do
        if held[list[i]] == slot then Read(list[i]) end
    end
end

-- Your power changed, so the game has just been handed it for every fill
-- (Fill.lua's Levels): each button asks again whether you can pay for what it
-- holds, so a fill goes as your power reaches the cost and comes back as you
-- fall short.
function FB:Levels()
    if not self:On() then return end
    for _, entry in pairs(fills) do
        if entry.spell then
            -- A change of form can take a spell's cost away (Fill.lua asks
            -- every cost again then): nothing is left on the button until it
            -- holds something with a cost again.
            if ns.Fill:Costed(entry.spell) then
                Show(entry)
            else
                entry.spell = nil
                ns.Fill:Drop(entry.parts)
            end
        end
    end
end

-- A choice changed on the page (Fill.lua's Apply calls this): with the tick
-- on, the buttons are found and read; with it off, nothing is left on a
-- button and nothing more is heard.
function FB:Apply()
    if not self:On() then
        for _, entry in pairs(fills) do
            entry.spell = nil
            ns.Fill:Drop(entry.parts)
        end
        Listen()
        return
    end
    Find()
    Listen()
    self:Reread()
end

-- Another addon has loaded: any buttons it brought are read, and the ones
-- already found are left alone.
local function Arrived()
    local was = #list
    Find()
    for i = was + 1, #list do Read(list[i]) end
end

-- A page turned or your form changed: a button's own slot can take the game
-- until the next frame to follow, and one of the common bar addons turns its
-- bar a moment after that, so the buttons are read once more then as well
-- (Keybinds.lua reads your keys the same way). Reading costs only a look at
-- what the game already holds, and a fill with nothing new to show is left
-- alone, so a read that changes nothing draws nothing. At most one of each is
-- ever waiting.
local function Again()
    local after = type(C_Timer) == "table" and C_Timer.After or nil
    if type(after) ~= "function" then return end
    if not soon then
        soon = true
        after(0, function()
            soon = false
            FB:Reread()
        end)
    end
    if not settling then
        settling = true
        after(SETTLE, function()
            settling = false
            FB:Reread()
        end)
    end
end

local function OnEvent(_, event, arg)
    if not FB:On() then return end
    if event == "ACTIONBAR_SLOT_CHANGED" then
        FB:Slot(Number(arg))
    elseif event == "PLAYER_REGEN_ENABLED" then
        -- The layers a button needed in the fight are made now.
        if waiting then
            waiting = false
            FB:Reread()
        end
    elseif event == "ADDON_LOADED" then
        Arrived()
    else
        -- A loading screen, a page turned or your form changed.
        if event == "PLAYER_ENTERING_WORLD" then Find() end
        FB:Reread()
        Again()
    end
end

-- Heard only while the tick is on.
Listen = function()
    local want = FB:On() and driver ~= nil
    if want == hearing then return end
    hearing = want
    if want then
        for _, event in ipairs(EVENTS) do pcall(driver.RegisterEvent, driver, event) end
    else
        driver:UnregisterAllEvents()
    end
end

function FB:Start()
    if self.started then return end
    self.started = true
    driver = CreateFrame("Frame")
    driver:SetScript("OnEvent", OnEvent)
    self.driver = driver
    if self:On() then Find() end
    Listen()
    self:Reread()
end

-- For the tests: how many buttons were found, and how many have a fill now.
function FB:Watching()
    local count = 0
    for _ in pairs(fills) do count = count + 1 end
    return #list, count
end

-- For the tests: one button's fill, or nothing where it has none.
function FB:Parts(button)
    local entry = fills[button]
    return entry and entry.parts or nil
end
