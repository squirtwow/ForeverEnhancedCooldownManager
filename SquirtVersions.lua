-- Update notices, shared by Squirt's addons: every addon that carries this
-- file has the same copy. Each one registers a short code, its title, its
-- version (from its .toc) and its "Tell me when an update is out" tick. When
-- someone with a newer version is heard, that addon says so in chat, once a
-- session: "<Title> 1.7.1 is out (you have 1.7.0). Update on CurseForge."
--
-- An addon can't look at CurseForge, so versions are swapped with other
-- players who have these addons, in addon messages (never shown in chat): on
-- a hidden chat channel, joined quietly a little after login once the game's
-- own channels have their numbers (it takes one channel number, never the
-- last free one); with your guild and your group; and with players nearby, by
-- a yell now and then in a city or an inn. A message is one short line:
-- "H1:CM=1.7.0,ER=1.7.2" says hello with the versions you have, "A1:..."
-- answers one. Only a player with a newer version answers, after a short
-- random wait (longer the more players are heard), and not once others have
-- (two elsewhere, one in your guild or group); one answer a minute for each
-- kind of chat at most.
--
-- Nothing is sent in a fight or while the game holds chat back, and nothing
-- on the channel or by a yell inside a dungeon or raid; a refusal or a
-- throttle from the game is waited out. A newer version is believed from your
-- guild or group at once, elsewhere once two different players have it. Your
-- own messages and other players' whispers are ignored (a whisper to
-- yourself counts, for testing). A line in a fight waits for its end. The
-- channel's own lines (joining, leaving, anything typed in it) are kept out
-- of every chat window through the game's chat filter list: no chat window is
-- touched. With every tick off, the channel is left and nothing is shared or
-- heard. A development copy (no number in its .toc) shares nothing and is
-- never told.
--
-- To see the line in game without a newer version anywhere (nothing is
-- sent): /run SquirtVersions:Test() for every addon with its tick on, or
-- /run SquirtVersions:Test("CM", "9.9.9") for one. /run
-- print(SquirtVersions:Status()) says whether the channel is joined.
--
-- One table in the game's global space, SquirtVersions, made by whichever
-- addon loads first. Its functions come from the newest copy of this file
-- loaded (VERSION), so an older copy in another addon never holds a newer one
-- back; everything it keeps lives in the table, so a newer copy carries on
-- with it.
local lib = _G.SquirtVersions
if type(lib) ~= "table" then
    lib = {}
    _G.SquirtVersions = lib
end
local VERSION = 1

if type(lib.version) ~= "number" or lib.version < VERSION then
    lib.version = VERSION
    lib.PREFIX = "SquirtVersions" -- the addon messages' name
    lib.CHANNEL = "LatestVersion" -- the hidden channel (the user's name for it; the prefix keeps our messages our own)
    lib.HELLO_AFTER = 20 -- seconds after login before the first hello, and the channel
    lib.SETTLED = 5 -- the game's channels unchanged this long before joining
    lib.GROUP_GAP = 300 -- a hello to a new group at most every five minutes
    lib.YELL_GAP = 1800 -- a yell at most every half hour
    lib.ANSWER_GAP = 60 -- one answer a minute for each kind of chat
    lib.SEND_GAP = 2 -- seconds between any two messages
    lib.PER_MINUTE = 6 -- more than this from one player in a minute is ignored
    lib.LINE = "|cff%s%s|r %s is out (you have %s). Update on CurseForge."

    local max, min, random = math.max, math.min, math.random
    -- Your guild and group are believed at once; a channel, a yell or a say
    -- needs two different players.
    local TRUSTED = { GUILD = true, PARTY = true, RAID = true, INSTANCE_CHAT = true }
    local PUBLIC = { CHANNEL = true, YELL = true, SAY = true }
    local ANSWERS = { GUILD = true, PARTY = true, RAID = true, INSTANCE_CHAT = true, CHANNEL = true, YELL = true }
    local GROUP = { GROUP = true, PARTY = true, RAID = true, INSTANCE_CHAT = true }
    -- The channel's own lines, kept out of the chat windows.
    local CHANNEL_EVENTS = { "CHAT_MSG_CHANNEL", "CHAT_MSG_CHANNEL_JOIN", "CHAT_MSG_CHANNEL_LEAVE",
        "CHAT_MSG_CHANNEL_NOTICE", "CHAT_MSG_CHANNEL_NOTICE_USER" }
    -- The game's notices that the channel won't have you: not tried again this session.
    local REFUSED = { WRONG_PASSWORD = true, BANNED = true, INVALID_NAME = true, NOT_IN_AREA = true, TRIAL_RESTRICTED = true }
    local EVENTS = { "PLAYER_ENTERING_WORLD", "GROUP_ROSTER_UPDATE", "PLAYER_REGEN_ENABLED", "PLAYER_UPDATE_RESTING",
        "ZONE_CHANGED_NEW_AREA", "CHAT_MSG_CHANNEL_NOTICE", "CHANNEL_PASSWORD_REQUEST" }

    -- Whether the game keeps a value secret: never compared, measured or matched.
    local function Secret(value)
        return issecretvalue ~= nil and issecretvalue(value) == true
    end

    -- A version as three numbers ("1.7" is 1.7.0, a "v" in front is fine), or
    -- nil for anything else: "dev", the packager's placeholder, "0.0.0-dev".
    -- Each part stays under 100, so a made-up message can't claim a far-off one.
    local function Parse(text)
        if type(text) ~= "string" or Secret(text) or #text > 12 then return nil end
        local a, b, c = text:match("^v?(%d+)%.(%d+)%.?(%d*)$")
        a, b, c = tonumber(a), tonumber(b), tonumber(c) or 0
        if not (a and b) or a > 99 or b > 99 or c > 99 then return nil end
        return { a, b, c }
    end

    -- A version written the one way ("1.7.0"), or nil.
    local function Normal(version)
        local parts = Parse(version)
        return parts and (parts[1] .. "." .. parts[2] .. "." .. parts[3]) or nil
    end

    -- One patch on from a version ("1.7.0" gives "1.7.1"); "9.9.9" for none.
    local function Next(version)
        local parts = Parse(version)
        if not parts then return "9.9.9" end
        if parts[3] < 99 then return parts[1] .. "." .. parts[2] .. "." .. (parts[3] + 1) end
        if parts[2] < 99 then return parts[1] .. "." .. (parts[2] + 1) .. ".0" end
        return nil
    end

    -- -1, 0 or 1 as version a is older than, the same as or newer than b; nil
    -- if either isn't a version.
    function lib.Compare(a, b)
        a, b = Parse(a), Parse(b)
        if not (a and b) then return nil end
        for i = 1, 3 do
            if a[i] ~= b[i] then return a[i] < b[i] and -1 or 1 end
        end
        return 0
    end
    local Compare = lib.Compare

    -- A message read: its kind (H hello, A answer) and the versions in it by
    -- code, or nil. A later protocol's number and anything after a ";" are
    -- passed over, and so is any part that isn't "CODE=1.2.3".
    function lib.Read(text)
        if type(text) ~= "string" or Secret(text) or #text > 250 then return nil end
        local kind, list = text:match("^([HA])%d+:([^;]*)")
        if not kind then return nil end
        local versions, parts = {}, 0
        for part in list:gmatch("[^,]+") do
            parts = parts + 1
            if parts > 24 then break end
            local code, version = part:match("^(%u%u%u?)=(%d+%.%d+%.?%d*)$")
            local normal = code and Normal(version)
            if normal then versions[code] = normal end
        end
        return { kind = kind, versions = versions }
    end

    -- An addon's tick, asked safely.
    local function On(entry)
        local ok, on = pcall(entry.IsOn)
        return ok and on == true
    end

    -- Whether any addon's tick is on.
    function lib:Wanted()
        for _, entry in pairs(self.addons) do
            if On(entry) then return true end
        end
        return false
    end

    -- "H1:CM=1.7.0,ER=1.7.2": every addon with its tick on and a real version;
    -- nil when there's none.
    function lib:Payload(kind)
        local parts = {}
        for code, entry in pairs(self.addons) do
            local version = Normal(entry.version)
            if version and On(entry) then parts[#parts + 1] = code .. "=" .. version end
        end
        if #parts == 0 then return nil end
        table.sort(parts)
        return kind .. "1:" .. table.concat(parts, ",")
    end

    -- Your name: "First Surname" on Forever (the game gives the surname as
    -- UnitName's second answer), else the first name alone.
    local function Me()
        if not UnitName then return nil end
        local first, surname = UnitName("player")
        if Secret(first) or Secret(surname) or type(first) ~= "string" or first == "" then return nil end
        if type(surname) == "string" and surname ~= "" then return first .. " " .. surname, first end
        return first, first
    end

    -- Whether a message's sender is you, with or without a realm after a dash.
    -- With a surname, a player called just your first name isn't you.
    function lib:IsMe(sender)
        local full, first = Me()
        if not full or type(sender) ~= "string" or Secret(sender) then return false end
        local base = sender:match("^(.-)%-") or sender
        return base == full or (full == first and base == first)
    end

    -- The channel's number, 0 while you aren't in it.
    local function ChannelNumber()
        if not GetChannelName then return 0 end
        local ok, id = pcall(GetChannelName, lib.CHANNEL)
        if not ok or Secret(id) or type(id) ~= "number" then return 0 end
        return id
    end

    -- Whether a channel name is the hidden channel's ("5. LatestVersion" too).
    -- It runs for every channel line, so the cheap checks come first.
    local function Ours(name)
        if Secret(name) or type(name) ~= "string" or #name < #lib.CHANNEL then return false end
        if name:find("^%d") then name = name:gsub("^%d+%.%s*", "") end
        return #name == #lib.CHANNEL and name:lower() == lib.CHANNEL:lower()
    end

    -- How many channels you're in, and how many the game allows.
    local function ChannelCount()
        local api = C_ChatInfo
        if api and api.GetNumActiveChannels then
            local ok, count = pcall(api.GetNumActiveChannels)
            if ok and not Secret(count) and type(count) == "number" then return count end
        end
        if not GetChannelList then return 0 end
        return math.floor(select("#", GetChannelList()) / 3)
    end

    local function MostChannels()
        local most = Constants and Constants.ChatFrameConstants and Constants.ChatFrameConstants.MaxChatChannels
        if Secret(most) or type(most) ~= "number" then return 10 end
        return most
    end

    -- Whether General (the game's first channel) is in.
    local function GeneralIn()
        if not GetChannelName then return false end
        local ok, id = pcall(GetChannelName, 1)
        return ok and not Secret(id) and type(id) == "number" and id > 0
    end

    -- Your group's kind of chat now, or nil.
    local function GroupType()
        if IsInGroup and LE_PARTY_CATEGORY_INSTANCE and IsInGroup(LE_PARTY_CATEGORY_INSTANCE) then return "INSTANCE_CHAT" end
        if IsInRaid and IsInRaid() then return "RAID" end
        if IsInGroup and IsInGroup() then return "PARTY" end
        return nil
    end

    local function InGuild()
        return IsInGuild ~= nil and IsInGuild() == true
    end

    local function Fighting()
        return InCombatLockdown ~= nil and InCombatLockdown() == true
    end

    -- While the game holds chat back (a boss fight, for one).
    local function Lockdown()
        local api = C_ChatInfo
        return api ~= nil and api.InChatMessagingLockdown ~= nil and api.InChatMessagingLockdown() == true
    end

    local function Inside()
        return IsInInstance ~= nil and IsInInstance() == true
    end

    -- An addon joins: { code = two or three capitals, title, colour (six hex
    -- digits), version (from its .toc), IsOn, Print }. Print gets the whole
    -- line, title and all. False if something is missing.
    function lib:Register(entry)
        if type(entry) ~= "table" or type(entry.code) ~= "string" or not entry.code:match("^%u%u%u?$")
            or type(entry.title) ~= "string" or type(entry.IsOn) ~= "function" or type(entry.Print) ~= "function" then
            return false
        end
        self.addons[entry.code] = entry
        self:Refresh()
        return true
    end

    -- A tick changed (or an addon joined): listen or stop, and join or leave
    -- the channel.
    function lib:Refresh()
        local wanted = self:Wanted()
        if self.frame and wanted ~= self.listening then
            if wanted then self.frame:RegisterEvent("CHAT_MSG_ADDON") else self.frame:UnregisterEvent("CHAT_MSG_ADDON") end
            self.listening = wanted
        end
        if not self.loginAt then return end
        if wanted then
            self:Wake(1)
        else
            self:Leave()
            self.queue, self.answers = {}, {}
        end
    end

    -- One line for an addon's status command, and for the tests in game: the
    -- channel, the players heard, the messages the game took, and the last
    -- fault caught inside, if any.
    function lib:Status()
        if not self:Wanted() then return "off" end
        local number = ChannelNumber()
        local where = number > 0 and ("on channel " .. number)
            or (self.refused and ("the channel refused (" .. tostring(self.refused) .. ")")) or "the channel not joined yet"
        local line = ("on, %s, %d players heard, %d sent"):format(where, self.heardCount or 0, self.sent or 0)
        if self.lastError then line = line .. ", last error: " .. self.lastError end
        return line
    end

    -- Timing --------------------------------------------------------------------

    -- Runs Wakeup in a while; a sooner wake already due stands.
    function lib:Wake(seconds)
        if not (C_Timer and C_Timer.After) then return end
        seconds = max(0.2, tonumber(seconds) or 1)
        local at = GetTime() + seconds
        if self.wakeAt and self.wakeAt <= at + 0.01 then return end
        self.wakeAt = at
        C_Timer.After(seconds, function()
            if lib.wakeAt and GetTime() + 0.05 < lib.wakeAt then return end -- a later one took over
            lib:Safely(lib.Wakeup)
        end)
    end

    -- A call that can't break the game: an error is kept for the status line.
    function lib:Safely(fn, ...)
        local ok, problem = pcall(fn, self, ...)
        if not ok then self.lastError = tostring(problem) end
    end

    function lib:Wakeup()
        self.wakeAt = nil
        if not self.loginAt or not self:Wanted() then return end
        local since = GetTime() - self.loginAt
        if since < self.HELLO_AFTER then return self:Wake(self.HELLO_AFTER - since) end
        self:Greet()
        local join, pump = self:Join(), self:Pump()
        local soonest = (join and pump and min(join, pump)) or join or pump
        if soonest then self:Wake(soonest) end
    end

    function lib:Login()
        self.loginAt = GetTime()
        self:Refresh()
    end

    -- Hellos ----------------------------------------------------------------------

    -- A hello queued on a kind of chat, unless one is waiting there already.
    function lib:Hello(chatType, delay)
        if self.blocked[chatType] then return end
        for _, item in ipairs(self.queue) do
            if item.chatType == chatType and item.kind == "H" then return end
        end
        self.queue[#self.queue + 1] = { chatType = chatType, kind = "H", due = GetTime() + (delay or 0) }
        self:Wake(delay)
    end

    -- Your guild once a session, a group as you join it (at most every five
    -- minutes), and players nearby in a city or an inn.
    function lib:Greet()
        if not self.loginAt or GetTime() - self.loginAt < self.HELLO_AFTER or not self:Wanted() then return end
        if InGuild() and not self.greeted.GUILD then
            self.greeted.GUILD = true
            self:Hello("GUILD", 0)
        end
        local group = GroupType()
        if group and not self.grouped then
            self.grouped = true
            local now = GetTime()
            if now - (self.greeted.GROUP or -math.huge) >= self.GROUP_GAP then
                self.greeted.GROUP = now
                self:Hello("GROUP", 1 + random() * 3)
            end
        elseif not group then
            self.grouped = false
        end
        self:Nearby()
    end

    function lib:Nearby()
        if not self.loginAt or GetTime() - self.loginAt < self.HELLO_AFTER or not self:Wanted() or self.blocked.YELL then return end
        if not (IsResting and IsResting() == true) or Inside() then return end
        local now = GetTime()
        if now - (self.greeted.YELL or -math.huge) < self.YELL_GAP then return end
        self.greeted.YELL = now
        self:Hello("YELL", 3 + random() * 5)
    end

    -- The hidden channel ----------------------------------------------------------

    -- Joins once the game's channels are in and settled, never at the last
    -- free number. Seconds until it should look again, or nil.
    function lib:Join()
        if self.refused or not JoinTemporaryChannel then return nil end
        if ChannelNumber() > 0 then
            if not self.joined then
                -- Just left (every tick off, then one on again): the leave
                -- lands first, then it's joined afresh.
                if self.leftAt and GetTime() - self.leftAt < 10 then return 2 end
                self:Joined()
            end
            return nil
        end
        if self.joined then
            -- Gone without the addon leaving it: you left it, or were put out.
            self.joined, self.refused = false, "left"
            return nil
        end
        local now = GetTime()
        if self.asked then
            if now - self.asked < 30 then return 3 end -- waiting for its number
            self.asked = nil
            self.tries = (self.tries or 0) + 1
            if self.tries >= 3 then
                self.refused = "no number"
                return nil
            end
        end
        local count = ChannelCount()
        if count ~= self.channels then self.channels, self.channelsAt = count, now end
        if now - self.channelsAt < self.SETTLED or (not GeneralIn() and now - self.loginAt < 60) then return 2 end
        if count >= MostChannels() - 1 then return 30 end
        self.asked = now
        self:Quieten()
        pcall(JoinTemporaryChannel, self.CHANNEL)
        return 2
    end

    function lib:Joined()
        self.joined, self.asked, self.tries = true, nil, nil
        self:Quieten()
        self:Hello("CHANNEL", 1 + random() * 4)
    end

    function lib:Leave()
        local was = self.joined
        self.joined, self.asked = false, nil
        if (was or ChannelNumber() > 0) and LeaveChannelByName then
            self.leftAt = GetTime()
            self:Quieten() -- its "left" line kept out too
            pcall(LeaveChannelByName, self.CHANNEL)
        end
    end

    -- The channel's lines are kept out of every chat window by the game's own
    -- chat filter list (made for addons), never by touching a chat window.
    function lib:Quieten()
        if self.quiet then return end
        local util = ChatFrameUtil
        local add = type(util) == "table" and util.AddMessageEventFilter or ChatFrame_AddMessageEventFilter
        if type(add) ~= "function" then return end
        self.quiet = true
        if type(self.filter) ~= "function" then
            self.filter = function(...) return lib:Filter(...) end
        end
        for _, event in ipairs(CHANNEL_EVENTS) do pcall(add, event, self.filter) end
    end

    -- True drops the line: one of the hidden channel's. The name (the event's
    -- ninth value) is checked for a secret before it's compared.
    function lib:Filter(_, _, ...)
        return Ours((select(9, ...)))
    end

    -- The game's notices about the channel: its number came, or it won't have
    -- you. A join that lands after every tick went off is left at once; a
    -- leave that isn't the addon's own (it leaves only with every tick off)
    -- is you leaving it, kept to for the session.
    function lib:Notice(kind, ...)
        if not Ours((select(8, ...))) or Secret(kind) or type(kind) ~= "string" then return end
        if kind == "YOU_JOINED" or kind == "YOU_CHANGED" then
            if self:Wanted() then self:Wake(0.5) else self:Leave() end
        elseif kind == "YOU_LEFT" then
            local own = self.leftAt and GetTime() - self.leftAt < 10
            if self.joined and self:Wanted() and not own then self.refused = "left" end
            self.joined, self.leftAt = false, nil
            if self:Wanted() and not self.refused then self:Wake(2) end
        elseif REFUSED[kind] then
            self.refused = kind
        end
    end

    -- Sending ---------------------------------------------------------------------

    -- The game's answer to a send: 0 sent, else its refusal (3 or 8 throttled,
    -- 11 chat held back, 4 or 7 not allowed).
    local function Send(chatType, text, target)
        local api = C_ChatInfo
        if not (api and api.SendAddonMessage) then return 9 end
        local ok, result = pcall(api.SendAddonMessage, lib.PREFIX, text, chatType, target)
        if not ok or result == false then return 9 end
        if result == nil or result == true then return 0 end
        if Secret(result) then return 9 end
        return tonumber(result) or 9
    end

    -- Whether an answer still has something to say: an addon the asker is
    -- behind on that too few others have covered.
    local function Needed(pending, chatType)
        local enough = PUBLIC[chatType] and 2 or 1
        for code in pairs(pending.need) do
            local others = 0
            for _ in pairs(pending.covered[code] or {}) do others = others + 1 end
            if others < enough then return true end
        end
        return false
    end

    -- Sends the first message due. Seconds until it should look again, or nil
    -- (nothing waiting, or a fight: its end wakes it).
    function lib:Pump()
        local queue = self.queue
        if #queue == 0 or Fighting() then return nil end
        if Lockdown() then return 15 end
        local now = GetTime()
        local gap = self.SEND_GAP - (now - (self.lastSend or -math.huge))
        if gap > 0 then return gap end
        local inside = Inside()
        local pick, soonest
        for i, item in ipairs(queue) do
            local ready = max(item.due, self.waits[item.chatType] or 0)
            if inside and (item.chatType == "CHANNEL" or item.chatType == "YELL") then ready = max(ready, now + 30) end
            if not pick and ready <= now then
                pick = i
            elseif not soonest or ready < soonest then
                soonest = ready
            end
        end
        if not pick then return soonest and max(0.2, soonest - now) end
        self:SendItem(table.remove(queue, pick))
        return #queue > 0 and self.SEND_GAP or nil
    end

    function lib:SendItem(item)
        local chatType, target = item.chatType, nil
        if GROUP[chatType] then
            chatType = GroupType()
        elseif chatType == "GUILD" then
            chatType = InGuild() and chatType or nil
        elseif chatType == "CHANNEL" then
            target = ChannelNumber()
            if target <= 0 then
                self.joined = false
                chatType = nil
            end
        end
        if not chatType or self.blocked[chatType] then return end
        if item.kind == "A" then
            local pending = self.answers[item.chatType]
            self.answers[item.chatType] = nil
            if not pending or not Needed(pending, item.chatType) then return end
            self.answered[item.chatType] = GetTime()
        end
        local text = self:Payload(item.kind)
        if not text then return end
        local result = Send(chatType, text, target)
        local now = GetTime()
        self.lastSend = now
        if result == 0 then
            self.backoff[item.chatType] = nil
            self.sent = (self.sent or 0) + 1
            if chatType == "CHANNEL" then self.channelFails = nil end
        elseif result == 3 or result == 8 then
            -- Throttled: a hello tries again, waiting longer each time.
            local wait = min(300, (self.backoff[item.chatType] or 2.5) * 2)
            self.backoff[item.chatType] = wait
            self.waits[item.chatType] = now + wait
            if item.kind == "H" then
                item.due = now + wait
                self.queue[#self.queue + 1] = item
            end
        elseif result == 11 then
            if item.kind == "H" then
                item.due = now + 15
                self.queue[#self.queue + 1] = item
            end
        elseif chatType == "CHANNEL" and (result == 4 or result == 7) then
            -- Its number went (joined again later). Refused outright, or three
            -- times in a row, the channel is no use: left for the session, so
            -- it holds no channel slot.
            self.joined = false
            self.channelFails = (self.channelFails or 0) + 1
            if result == 4 or self.channelFails >= 3 then
                self.refused = "no addon messages"
                self:Leave()
            end
        elseif result == 4 or result == 7 then
            self.blocked[chatType] = true -- not allowed on this server: never again this session
        end
    end

    -- Hearing ---------------------------------------------------------------------

    -- Whether a player has sent too much in the last minute (their message is
    -- then ignored).
    function lib:Flooding(sender)
        local now = GetTime()
        local times = self.recent[sender]
        if not times then
            self.recentCount = (self.recentCount or 0) + 1
            if self.recentCount > 400 then
                local kept = 0
                for name, list in pairs(self.recent) do
                    if now - (list[#list] or 0) > 60 then self.recent[name] = nil else kept = kept + 1 end
                end
                self.recentCount = kept + 1
            end
            times = {}
            self.recent[sender] = times
            if not self.heard[sender] and (self.heardCount or 0) < 1000 then
                self.heard[sender] = true
                self.heardCount = (self.heardCount or 0) + 1
            end
        end
        local kept = 0
        for i = 1, #times do
            if now - times[i] < 60 then
                kept = kept + 1
                times[kept] = times[i]
            end
        end
        for i = #times, kept + 1, -1 do times[i] = nil end
        if kept >= self.PER_MINUTE then return true end
        times[kept + 1] = now
        return false
    end

    -- An addon message under the prefix. Everything the game gives is checked
    -- for a secret before it's compared.
    function lib:Receive(prefix, text, chatType, sender)
        if Secret(prefix) or Secret(text) or Secret(chatType) or Secret(sender) then return end
        if prefix ~= self.PREFIX or type(chatType) ~= "string" or type(sender) ~= "string" or sender == "" then return end
        if not self:Wanted() then return end
        local mine = self:IsMe(sender)
        local trusted
        if chatType == "WHISPER" then
            if not mine then return end
            trusted = true -- a whisper to yourself, for testing
        elseif mine then
            return -- your own, back to you
        elseif TRUSTED[chatType] then
            trusted = true
        elseif PUBLIC[chatType] then
            trusted = false
        else
            return
        end
        if self:Flooding(sender) then return end
        local message = lib.Read(text)
        if not message then return end
        local behind
        for code, theirs in pairs(message.versions) do
            local entry = self.addons[code]
            local ours = entry and On(entry) and Normal(entry.version)
            if ours then
                local order = Compare(theirs, ours)
                if order == 1 then self:Claim(code, theirs, sender, trusted) end
                if order == -1 then
                    if message.kind == "H" then
                        behind = behind or {}
                        behind[code] = true
                    end
                else
                    self:Covered(chatType, code, sender)
                end
            end
        end
        if behind and ANSWERS[chatType] then self:Answer(chatType, behind) end
    end

    -- An answer to a hello, after a short random wait (one waiting answer per
    -- kind of chat, one sent a minute).
    function lib:Answer(chatType, behind)
        if self.blocked[chatType] or Secret(chatType) then return end
        local pending = self.answers[chatType]
        if not pending then
            local now = GetTime()
            if now - (self.answered[chatType] or -math.huge) < self.ANSWER_GAP then return end
            -- A group's answer comes in a few seconds. Elsewhere the wait
            -- grows with the players heard this session, up to a minute, so
            -- a crowd's answers spread out and the first few stop the rest.
            local crowd = GROUP[chatType] and 0 or min(54, (self.heardCount or 0) / 4)
            local wait = PUBLIC[chatType] and (2 + random() * (6 + crowd)) or (1 + random() * (4 + crowd))
            pending = { need = {}, covered = {} }
            self.answers[chatType] = pending
            self.queue[#self.queue + 1] = { chatType = chatType, kind = "A", due = now + wait }
            self:Wake(wait)
        end
        for code in pairs(behind) do pending.need[code] = true end
    end

    -- Someone else said the same version or newer where an answer waits.
    function lib:Covered(chatType, code, sender)
        local pending = self.answers[chatType]
        if not pending then return end
        pending.covered[code] = pending.covered[code] or {}
        pending.covered[code][sender] = true
    end

    -- Someone has a newer version. Believed from your guild or group (or a
    -- whisper to yourself) at once, elsewhere once two different players have
    -- it: the second highest of their versions.
    function lib:Claim(code, version, sender, trusted)
        local entry = self.addons[code]
        local ours = entry and Normal(entry.version)
        version = Normal(version)
        if not ours or not version or type(sender) ~= "string" or Secret(sender) or not On(entry)
            or Compare(version, ours) ~= 1 then
            return
        end
        local claims = self.claims[code]
        if not claims then
            claims = { count = 0, by = {} }
            self.claims[code] = claims
        end
        local was = claims.by[sender]
        if not was then
            if claims.count >= 40 then return end
            claims.count = claims.count + 1
            claims.by[sender] = { version = version, trusted = trusted == true }
        else
            if Compare(version, was.version) == 1 then was.version = version end
            was.trusted = was.trusted or trusted == true
        end
        local best, top, second
        for _, claim in pairs(claims.by) do
            if claim.trusted and (not best or Compare(claim.version, best) == 1) then best = claim.version end
            if not top or Compare(claim.version, top) == 1 then
                top, second = claim.version, top
            elseif not second or Compare(claim.version, second) == 1 then
                second = claim.version
            end
        end
        if second and (not best or Compare(second, best) == 1) then best = second end
        if best then self:Tell(entry, best) end
    end

    -- The one line a session for an addon; in a fight it waits for the end.
    -- ours: what it says you have, for a development copy tried with Test.
    function lib:Tell(entry, version, ours)
        ours = ours or Normal(entry.version)
        if self.told[entry.code] or not ours then return end
        self.told[entry.code] = true
        local colour = type(entry.colour) == "string" and entry.colour:match("^%x%x%x%x%x%x$") or "ffd100"
        local line = self.LINE:format(colour, entry.title, version, ours)
        if Fighting() then
            self.later[#self.later + 1] = { entry = entry, line = line }
        else
            pcall(entry.Print, line)
        end
    end

    -- Hidden, for the tests in game: as if your guild had a newer version, for
    -- every addon with its tick on, or the one with this code. With no
    -- version given (or one not newer), one patch on from yours. Its line is
    -- said again (its once-a-session mark cleared), a development copy is
    -- told it has "dev", and nothing is sent. Gives how many were tried.
    function lib:Test(code, version)
        local tried, mine = 0, Me()
        for key, entry in pairs(self.addons) do
            local ours = Normal(entry.version)
            local newer = Normal(version)
            if not newer or (ours and Compare(newer, ours) ~= 1) then newer = Next(ours) end
            if (code == nil or key == code) and On(entry) and newer then
                tried = tried + 1
                self.told[key], self.claims[key] = nil, nil
                if ours then
                    self:Claim(key, newer, mine or "you", true)
                else
                    self:Tell(entry, newer, "dev")
                end
            end
        end
        if tried == 0 then
            local _, any = next(self.addons)
            local which = type(code) == "string" and not Secret(code) and (" " .. code) or ""
            if any then pcall(any.Print, "Nothing to try: no addon" .. which .. " here has its update tick on.") end
        end
        return tried
    end

    -- A fight ended: the lines it held, for addons still ticked.
    function lib:Flush()
        local later = self.later
        self.later = {}
        for _, held in ipairs(later) do
            if On(held.entry) then pcall(held.entry.Print, held.line) end
        end
    end

    function lib:OnEvent(event, ...)
        if event == "CHAT_MSG_ADDON" then
            self:Receive(...)
        elseif event == "PLAYER_ENTERING_WORLD" then
            if not self.loginAt then self:Login() else self:Greet() end
        elseif event == "GROUP_ROSTER_UPDATE" then
            self:Greet()
        elseif event == "PLAYER_REGEN_ENABLED" then
            self:Flush()
            if #self.queue > 0 then self:Wake(1) end
        elseif event == "PLAYER_UPDATE_RESTING" or event == "ZONE_CHANGED_NEW_AREA" then
            self:Nearby()
        elseif event == "CHAT_MSG_CHANNEL_NOTICE" then
            self:Notice(...)
        elseif event == "CHANNEL_PASSWORD_REQUEST" then
            if Ours((...)) then self.refused = "password" end
        end
    end

    -- What it keeps, and its one event frame: made when missing, so a newer
    -- copy carries on with an older one's.
    function lib:Setup()
        for _, key in ipairs({ "addons", "told", "claims", "recent", "heard", "queue", "answers", "answered", "waits",
            "backoff", "blocked", "greeted", "later" }) do
            if type(self[key]) ~= "table" then self[key] = {} end
        end
        if not self.frame and CreateFrame then
            local frame = CreateFrame("Frame")
            frame:SetScript("OnEvent", function(_, event, ...) lib:Safely(lib.OnEvent, event, ...) end)
            self.frame = frame
        end
        if self.frame then
            for _, event in ipairs(EVENTS) do self.frame:RegisterEvent(event) end
        end
        if not self.prefixed and C_ChatInfo and C_ChatInfo.RegisterAddonMessagePrefix then
            self.prefixed = true
            pcall(C_ChatInfo.RegisterAddonMessagePrefix, self.PREFIX)
        end
        -- Loaded after login (an addon loaded later): starts now.
        if not self.loginAt and IsLoggedIn and IsLoggedIn() then self:Login() end
    end
end

lib:Setup()
