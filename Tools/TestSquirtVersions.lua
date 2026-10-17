-- The shared update notices (SquirtVersions.lua), the same file in every one
-- of Squirt's addons, run in a small mock of the game: reading and comparing
-- versions, the hidden channel (joined quietly once the game's channels have
-- settled, never at the last free number, left with every tick off, its lines
-- kept out of the chat windows), hellos to the guild, a group, the channel and
-- players nearby, answers only from a newer version (after a wait, not once
-- others have, one a minute), who is believed, one line per addon a session,
-- nothing sent in a fight or while chat is held back, the game's refusals and
-- throttles, secrets never compared, the hidden way to try it in game, and a
-- newer copy of the file taking over from an older one. This file is the same
-- in every addon but for its last line, which its test runner reads.
local checks = 0
local function Equal(actual, expected, label)
    checks = checks + 1
    if actual ~= expected then
        error(label .. ": expected " .. tostring(expected) .. ", got " .. tostring(actual), 2)
    end
end

local PATH = loadfile("SquirtVersions.lua") and "SquirtVersions.lua" or "Core/SquirtVersions.lua"

-- The mock game ----------------------------------------------------------------

local now, combat, lockdown, guild, group, resting, inside, loggedIn
local channels, results, sent, sentAt, timers, frames, filters, secrets, joins, leaves, joinWorks, rnd
local me

local function Reset()
    now, combat, lockdown, guild, group, resting, inside, loggedIn = 1000, false, false, true, nil, false, false, false
    channels = { General = 1, Trade = 2 }
    results, sent, sentAt, timers, frames, filters, secrets = {}, {}, {}, {}, {}, {}, {}
    joins, leaves, joinWorks, rnd = 0, 0, true, 0.5
    me = { "Zriel", "Gustbellow" }
end
Reset()

math.random = function() return rnd end
GetTime = function() return now end
C_Timer = { After = function(seconds, fn) timers[#timers + 1] = { at = now + seconds, fn = fn } end }
InCombatLockdown = function() return combat end
IsLoggedIn = function() return loggedIn end
IsInGuild = function() return guild end
LE_PARTY_CATEGORY_INSTANCE = 2
IsInGroup = function(category)
    if category == 2 then return group == "INSTANCE" end
    return group ~= nil
end
IsInRaid = function() return group == "RAID" end
IsResting = function() return resting end
IsInInstance = function() return inside, inside and "party" or "none" end
UnitName = function() return me[1], me[2] end
issecretvalue = function(value) return value ~= nil and secrets[value] == true end
Constants = { ChatFrameConstants = { MaxChatChannels = 20 } }

local function Count()
    local n = 0
    for _ in pairs(channels) do n = n + 1 end
    return n
end
C_ChatInfo = {
    RegisterAddonMessagePrefix = function() return 0 end,
    InChatMessagingLockdown = function() return lockdown end,
    GetNumActiveChannels = function() return Count() end,
    SendAddonMessage = function(prefix, text, chatType, target)
        assert(not combat, "sent in a fight")
        assert(not lockdown, "sent while chat was held back")
        assert(prefix == "SquirtVersions", "its own prefix")
        sent[#sent + 1] = chatType .. (target and ("#" .. target) or "") .. " " .. text
        sentAt[#sentAt + 1] = now
        return results[chatType] or 0
    end,
}
GetChannelName = function(id)
    for name, number in pairs(channels) do
        if number == id or (type(id) == "string" and name:lower() == id:lower()) then return number, name end
    end
    return 0
end
JoinTemporaryChannel = function(name, password, frameID)
    joins = joins + 1
    assert(password == nil and frameID == nil, "joined without a chat window")
    if not joinWorks then return end
    local number = 1
    while GetChannelName(number) ~= 0 do number = number + 1 end
    channels[name] = number
end
LeaveChannelByName = function(name)
    leaves = leaves + 1
    channels[name] = nil
end
ChatFrameUtil = { AddMessageEventFilter = function(event, fn) filters[event] = fn end }
CreateFrame = function()
    local frame = { events = {} }
    function frame:RegisterEvent(event) self.events[event] = true end
    function frame:UnregisterEvent(event) self.events[event] = nil end
    function frame:SetScript(_, fn) self.script = fn end
    frames[#frames + 1] = frame
    return frame
end

local function Fire(event, ...)
    for _, frame in ipairs(frames) do
        if frame.events[event] and frame.script then frame.script(frame, event, ...) end
    end
end

-- Time passes, running each timer as it falls due.
local function Advance(seconds)
    local target = now + seconds
    while true do
        local index, at
        for i, timer in ipairs(timers) do
            if timer.at <= target and (not at or timer.at < at) then index, at = i, timer.at end
        end
        if not index then break end
        local timer = table.remove(timers, index)
        if timer.at > now then now = timer.at end
        timer.fn()
    end
    now = target
end

local function Sent()
    local text = table.concat(sent, ";")
    sent, sentAt = {}, {}
    return text
end

local printed, ticks
local lib

-- A fresh game with this file loaded, and two addons in it plus a
-- development copy.
local function Fresh()
    Reset()
    SquirtVersions = nil
    assert(loadfile(PATH))()
    lib = SquirtVersions
    printed = {}
    ticks = { CM = true, ER = true, CP = true }
    local function Add(code, version, title)
        return lib:Register({ code = code, title = title, colour = "ffd100", version = version,
            IsOn = function() return ticks[code] == true end,
            Print = function(line) printed[#printed + 1] = line end })
    end
    Add("CM", "1.7.0", "Forever Enhanced Cooldown Manager")
    Add("ER", "1.7.2", "EraUI")
    Add("CP", "@project-version@", "Forever Enhanced Cooldown Pulse")
end

-- Logged in and past the first hellos: in the channel (number 3), the guild
-- and channel hellos sent.
local function Settled()
    Fresh()
    Fire("PLAYER_ENTERING_WORLD", true, false)
    Advance(60)
    assert(GetChannelName("LatestVersion") == 3, "in the channel")
    Sent()
end

local LINE = "|cffffd100%s|r %s is out (you have %s). Update on CurseForge."

-- Versions -------------------------------------------------------------------------

Fresh()
local C = lib.Compare
Equal(C("1.2.1", "1.2.0"), 1, "a later patch is newer")
Equal(C("1.10.0", "1.9.9"), 1, "numbers, not text")
Equal(C("1.2", "1.2.0"), 0, "1.2 is 1.2.0")
Equal(C("1.1.0", "1.2.0"), -1, "older")
Equal(C("v1.3.0", "1.2.9"), 1, "a v in front is fine")
Equal(C("dev", "1.0.0"), nil, "dev isn't a version")
Equal(C("@project-version@", "1.0.0"), nil, "nor the packager's placeholder")
Equal(C("0.0.0-dev", "0.0.0"), nil, "nor a dev number")
Equal(C("100.0.0", "1.0.0"), nil, "a made-up far-off version isn't believed")
Equal(C("1.2.1; x", "1.2.0"), nil, "anything but a version is ignored")
secrets["1.9.9"] = true
Equal(C("1.9.9", "1.0.0"), nil, "a secret is never read")
secrets = {}

local read = lib.Read("H1:CM=1.7.0,ER=1.7.2")
Equal(read.kind .. " " .. read.versions.CM .. " " .. read.versions.ER, "H 1.7.0 1.7.2", "a hello read")
read = lib.Read("A2:CM=1.8;more to come")
Equal(read.kind .. " " .. read.versions.CM, "A 1.8.0", "a later protocol's answer: its versions, the rest passed over")
read = lib.Read("H1:cm=1.0.0,LONG=1.0.0,XP=dev,PR=1.0.0,NP=1.0.0-dev,MP=1.0.0x")
local codes = {}
for code in pairs(read.versions) do codes[#codes + 1] = code end
Equal(table.concat(codes, ","), "PR", "only CODE=1.2.3 parts")
Equal(lib.Read("hello"), nil, "not a message")
Equal(lib.Read("H1:" .. ("CM=1.0.0,"):rep(40)), nil, "too long")
secrets["H1:CM=1.0.0"] = true
Equal(lib.Read("H1:CM=1.0.0"), nil, "a secret text is never read")
secrets = {}

-- Registering, and what's shared.
Equal(lib:Payload("H"), "H1:CM=1.7.0,ER=1.7.2", "every ticked addon with a real version, in order; a development copy shares nothing")
ticks.CM = false
Equal(lib:Payload("A"), "A1:ER=1.7.2", "an unticked addon shares nothing")
ticks.ER, ticks.CP = false, false
Equal(lib:Payload("H"), nil, "nothing to share")
Equal(lib:Wanted(), false, "and nothing wanted")
ticks.CP = true
Equal(lib:Wanted(), true, "a development copy's tick still counts")
local good = { code = "XP", title = "T", version = "1.0.0", IsOn = function() return true end, Print = print }
Equal(lib:Register({ code = "xp", title = "T", IsOn = good.IsOn, Print = print }), false, "a code is two or three capitals")
Equal(lib:Register({ code = "XP", title = "T", IsOn = good.IsOn }), false, "a Print is needed")
Equal(lib:Register({ code = "XP", IsOn = good.IsOn, Print = print }), false, "and a title")
Equal(lib:Register(good), true, "a whole entry joins")
Equal(lib:Register({ code = "BAD", title = "T", version = "1.0.0", IsOn = function() error("broken") end, Print = print }), true,
    "an addon whose tick breaks")
Equal(lib:Payload("H"), "H1:XP=1.0.0", "counts as off")

-- Login: the hellos and the channel ---------------------------------------------

Fresh()
group = "PARTY"
Equal(frames[1].events.CHAT_MSG_ADDON, true, "listening while a tick is on")
Fire("PLAYER_ENTERING_WORLD", true, false)
Advance(19)
Equal(Sent(), "", "nothing in the first twenty seconds")
Equal(joins, 0, "and the channel not joined yet")
Advance(1)
Equal(Sent(), "GUILD H1:CM=1.7.0,ER=1.7.2", "then a hello to the guild")
Advance(3)
Equal(Sent(), "PARTY H1:CM=1.7.0,ER=1.7.2", "and the group, a moment apart")
Advance(30)
Equal(joins, 1, "the channel joined once the game's channels settled")
Equal(Sent(), "CHANNEL#3 H1:CM=1.7.0,ER=1.7.2", "and a hello there, to its number")
for _, event in ipairs({ "CHAT_MSG_CHANNEL", "CHAT_MSG_CHANNEL_JOIN", "CHAT_MSG_CHANNEL_LEAVE", "CHAT_MSG_CHANNEL_NOTICE",
    "CHAT_MSG_CHANNEL_NOTICE_USER" }) do
    Equal(type(filters[event]), "function", "the game's filter list keeps its lines out: " .. event)
end
Fire("PLAYER_ENTERING_WORLD", false, false)
Fire("GROUP_ROSTER_UPDATE")
Advance(600)
Equal(Sent(), "", "no second hello to the guild, the group or the channel")
group = nil
Fire("GROUP_ROSTER_UPDATE")
group = "RAID"
Fire("GROUP_ROSTER_UPDATE")
Advance(10)
Equal(Sent(), "RAID H1:CM=1.7.0,ER=1.7.2", "a new group, after five minutes: a hello there")
group = nil
Fire("GROUP_ROSTER_UPDATE")
group = "INSTANCE"
Fire("GROUP_ROSTER_UPDATE")
Advance(10)
Equal(Sent(), "", "but not a third within five minutes")
Equal(lib:Status(), "on, on channel 3, 0 players heard, 4 sent", "the status line")

-- Messages a moment apart, never two at once.
Fresh()
group = "PARTY"
loggedIn = true
Fire("PLAYER_ENTERING_WORLD", true, false)
Advance(120)
Equal(#sentAt, 3, "three hellos")
Equal(sentAt[2] - sentAt[1] >= 2 and sentAt[3] - sentAt[2] >= 2, true, "two seconds apart at least")
Sent()

-- The channel's lines are dropped from the chat windows; others aren't. The
-- name is checked for a secret first.
local filter = filters.CHAT_MSG_CHANNEL_NOTICE
Equal(filter({}, "CHAT_MSG_CHANNEL_NOTICE", "YOU_JOINED", "", "", "3. LatestVersion", "", "", 0, 3, "LatestVersion"), true,
    "the hidden channel's notice is dropped")
Equal(filters.CHAT_MSG_CHANNEL({}, "CHAT_MSG_CHANNEL", "hi", "Coww", "", "3. latestversion", "", "", 0, 3, "latestversion"),
    true, "anything typed in it too, whatever the case")
Equal(filter({}, "CHAT_MSG_CHANNEL_NOTICE", "YOU_JOINED", "", "", "1. General", "", "", 1, 1, "General"), false,
    "General's isn't")
Equal(filter({}, "CHAT_MSG_CHANNEL_NOTICE", "YOU_JOINED", "", "", "4. LatestVersionToo", "", "", 0, 4, "LatestVersionToo"), false,
    "nor a channel with a longer name")
secrets.LatestVersion = true
Equal(filter({}, "CHAT_MSG_CHANNEL_NOTICE", "YOU_JOINED", "", "", "", "", "", 0, 3, "LatestVersion"), false,
    "a secret name is never compared")
secrets = {}

-- At the channel limit (19 of 20) it never joins.
Fresh()
for i = 3, 19 do channels["Other" .. i] = i end
Fire("PLAYER_ENTERING_WORLD", true, false)
Advance(300)
Equal(joins, 0, "never at the last free channel")
Equal(Sent(), "GUILD H1:CM=1.7.0,ER=1.7.2", "the guild still hears")

-- Without General it waits a minute after login, then joins.
Fresh()
channels = { Trade = 2 }
Fire("PLAYER_ENTERING_WORLD", true, false)
Advance(55)
Equal(joins, 0, "waiting for General")
Advance(10)
Equal(joins, 1, "a minute on, joined anyway")

-- While the game's channels are still arriving, it waits for them to settle.
Fresh()
Fire("PLAYER_ENTERING_WORLD", true, false)
Advance(21)
channels.LocalDefense = 3
Advance(2)
channels.World = 4
Advance(3)
Equal(joins, 0, "a channel just arrived: waiting")
Advance(10)
Equal(joins == 1 and GetChannelName("LatestVersion"), 5, "then joined, after the player's own channels")

-- After a reload the channel is still there: no second join, a hello.
Fresh()
channels.LatestVersion = 3
loggedIn = true
Fire("PLAYER_ENTERING_WORLD", false, true)
Advance(30)
Equal(joins, 0, "still in it after a reload")
Equal(Sent():find("CHANNEL#3 H1:", 1, true) ~= nil, true, "a hello there")

-- A refusal stops it for the session; a password box too.
Fresh()
joinWorks = false
Fire("PLAYER_ENTERING_WORLD", true, false)
Advance(30)
Equal(joins, 1, "asked once")
Fire("CHAT_MSG_CHANNEL_NOTICE", "WRONG_PASSWORD", "", "", "LatestVersion", "", "", 0, 0, "LatestVersion")
Advance(300)
Equal(joins, 1, "a refusal: not asked again")
Equal(lib:Status(), "on, the channel refused (WRONG_PASSWORD), 0 players heard, 1 sent", "and the status says why")
Fresh()
joinWorks = false
Fire("PLAYER_ENTERING_WORLD", true, false)
Advance(30)
Fire("CHANNEL_PASSWORD_REQUEST", "LatestVersion")
Advance(300)
Equal(joins, 1, "a password: not asked again")
Fire("CHAT_MSG_CHANNEL_NOTICE", "WRONG_PASSWORD", "", "", "1. General", "", "", 1, 1, "General")
Equal(lib.refused, "password", "another channel's notice changes nothing")
-- A join that never gets a number is tried three times.
Fresh()
joinWorks = false
Fire("PLAYER_ENTERING_WORLD", true, false)
Advance(600)
Equal(joins .. " " .. tostring(lib.refused), "3 no number", "three tries, then left alone")

-- Every tick off: the channel is left and nothing is heard; on again, back.
Settled()
ticks.CM, ticks.ER, ticks.CP = false, false, false
lib:Refresh()
Equal(leaves .. " " .. GetChannelName("LatestVersion"), "1 0", "left with every tick off")
Equal(frames[1].events.CHAT_MSG_ADDON, nil, "and not listening")
Fire("CHAT_MSG_CHANNEL_NOTICE", "YOU_LEFT", "", "", "3. LatestVersion", "", "", 0, 3, "LatestVersion")
Advance(300)
Equal(joins .. " " .. Sent(), "1 ", "nothing joined or sent")
ticks.ER = true
lib:Refresh()
Advance(30)
Equal(joins .. " " .. GetChannelName("LatestVersion"), "2 3", "a tick on: joined again")
Equal(Sent(), "CHANNEL#3 H1:ER=1.7.2", "with a hello")
-- Leaving it yourself is kept to for the session.
Fire("CHAT_MSG_CHANNEL_NOTICE", "YOU_LEFT", "", "", "3. LatestVersion", "", "", 0, 3, "LatestVersion")
channels.LatestVersion = nil
Advance(300)
Equal(joins .. " " .. tostring(lib.refused), "2 left", "you left it: not joined again")
-- Logged in with every tick off and the channel still there (a reload): left.
Fresh()
ticks.CM, ticks.ER, ticks.CP = false, false, false
channels.LatestVersion = 3
Fire("PLAYER_ENTERING_WORLD", false, true)
Equal(leaves, 1, "a reload with every tick off leaves it")
Advance(300)
Equal(joins .. " " .. Sent(), "0 ", "and nothing more")

-- Hearing and answering ------------------------------------------------------------

local function Heard(text, chatType, sender)
    Fire("CHAT_MSG_ADDON", "SquirtVersions", text, chatType, sender)
end

-- An older player on the channel says hello: an answer after a short wait.
Settled()
Heard("H1:CM=1.6.0,ER=1.7.2", "CHANNEL", "Coww Brightmane")
Advance(4)
Equal(Sent(), "", "not at once")
Advance(2)
Equal(Sent(), "CHANNEL#3 A1:CM=1.7.0,ER=1.7.2", "an answer with your versions")
Heard("H1:CM=1.6.0", "CHANNEL", "Bella Stone")
Advance(30)
Equal(Sent(), "", "one answer a minute")
Advance(40)
Heard("H1:CM=1.6.0", "CHANNEL", "Bella Stone")
Advance(10)
Equal(Sent(), "CHANNEL#3 A1:CM=1.7.0,ER=1.7.2", "and another after it")
Equal(#printed, 0, "an older version says nothing to you")

-- Two answers due at once go two seconds apart; a say gets none.
Settled()
rnd = 0
Heard("H1:CM=1.6.0", "GUILD", "Coww Brightmane")
Heard("H1:CM=1.6.0", "CHANNEL", "Bella Stone")
Heard("H1:CM=1.6.0", "SAY", "Rumble Oak")
Advance(1.2)
Equal(Sent(), "GUILD A1:CM=1.7.0,ER=1.7.2", "the first answer")
Fire("CHAT_MSG_CHANNEL_NOTICE", "YOU_CHANGED", "", "", "3. LatestVersion", "", "", 0, 3, "LatestVersion")
Advance(0.9)
Equal(Sent(), "", "the second, due now, waits")
Advance(1)
Equal(Sent(), "CHANNEL#3 A1:CM=1.7.0,ER=1.7.2", "until two seconds after the first")
Advance(60)
Equal(Sent(), "", "never on say")
-- Switched off with an answer waiting: dropped, even once on again.
Settled()
Heard("H1:CM=1.6.0", "GUILD", "Coww Brightmane")
ticks.CM, ticks.ER, ticks.CP = false, false, false
lib:Refresh()
ticks.ER = true
lib:Refresh()
Advance(60)
Equal(Sent():find("GUILD A1", 1, true), nil, "the waiting answer was dropped")

-- Others answered first: on the channel, two are enough; one isn't.
Settled()
Heard("H1:CM=1.6.0", "CHANNEL", "Coww Brightmane")
Heard("A1:CM=1.7.0", "CHANNEL", "Bella Stone")
Advance(10)
Equal(Sent(), "CHANNEL#3 A1:CM=1.7.0,ER=1.7.2", "one other answer isn't enough out there")
Settled()
Heard("H1:CM=1.6.0", "CHANNEL", "Coww Brightmane")
Heard("A1:CM=1.7.0", "CHANNEL", "Bella Stone")
Heard("H1:CM=1.7.0,ER=1.7.2", "CHANNEL", "Rumble Oak")
Advance(10)
Equal(Sent(), "", "two others said it: no answer")
Settled()
Heard("H1:CM=1.6.0", "CHANNEL", "Coww Brightmane")
Heard("A1:CM=1.7.0", "CHANNEL", "Bella Stone")
Heard("A1:CM=1.7.0", "CHANNEL", "Bella Stone")
Advance(10)
Equal(Sent() ~= "", true, "the same player twice is one")
-- In the guild one is enough.
Settled()
Heard("H1:CM=1.6.0", "GUILD", "Coww Brightmane")
Heard("A1:CM=1.8.0", "GUILD", "Bella Stone")
Advance(10)
Equal(Sent(), "", "a guildmate answered: no answer")
Settled()
Heard("H1:CM=1.6.0", "GUILD", "Coww Brightmane")
Advance(10)
Equal(Sent(), "GUILD A1:CM=1.7.0,ER=1.7.2", "else yours")
-- The same version, or a newer one, gets no answer; nor does an answer.
Settled()
Heard("H1:CM=1.7.0,ER=1.7.2", "CHANNEL", "Coww Brightmane")
Heard("A1:CM=1.6.0", "CHANNEL", "Bella Stone")
Heard("H1:XP=0.9.0", "CHANNEL", "Rumble Oak")
Heard("H1:CP=0.9.0", "CHANNEL", "Rumble Oak")
Advance(30)
Equal(Sent(), "", "no answer: same version, an answer, an addon you lack, a development copy")
-- An unticked addon neither answers nor is told.
Settled()
ticks.CM = false
Heard("H1:CM=1.6.0", "GUILD", "Coww Brightmane")
Heard("H1:CM=1.9.0", "GUILD", "Bella Stone")
Advance(30)
Equal(Sent() .. #printed, "0", "an unticked addon: no answer, no line")

-- Who is believed.
Settled()
Heard("H1:CM=1.8.0", "GUILD", "Coww Brightmane")
Equal(printed[1], LINE:format("Forever Enhanced Cooldown Manager", "1.8.0", "1.7.0"), "a guildmate's newer version: the line")
Heard("H1:CM=1.9.0", "PARTY", "Bella Stone")
Equal(#printed, 1, "once a session for that addon")
Heard("A1:ER=1.8.0", "RAID", "Bella Stone")
Equal(printed[2], LINE:format("EraUI", "1.8.0", "1.7.2"), "another addon has its own line")
Equal(#sent, 0, "a newer version gets no answer")
Settled()
Heard("H1:CM=1.8.0", "CHANNEL", "Coww Brightmane")
Heard("A1:CM=1.8.0", "CHANNEL", "Coww Brightmane")
Heard("A1:CM=1.8.0", "YELL", "Coww Brightmane")
Equal(#printed, 0, "one player out there isn't believed")
Heard("A1:CM=1.7.5", "YELL", "Bella Stone")
Equal(printed[1], LINE:format("Forever Enhanced Cooldown Manager", "1.7.5", "1.7.0"),
    "two are: the version both have at least")
Settled()
Heard("A1:CM=1.8.0", "CHANNEL", "Coww Brightmane")
Heard("A1:CM=1.9.0", "GUILD", "Bella Stone")
Equal(printed[1], LINE:format("Forever Enhanced Cooldown Manager", "1.9.0", "1.7.0"), "the guild's, when it's newer")
-- Your own messages, other players' whispers, and secrets.
Settled()
Heard("H1:CM=9.9.9", "CHANNEL", "Zriel Gustbellow")
Heard("H1:CM=9.9.9", "GUILD", "Zriel Gustbellow-Zephras")
Heard("H1:CM=9.9.9", "WHISPER", "Coww Brightmane")
Heard("H1:CM=1.0.0", "WHISPER", "Coww Brightmane")
Heard("H1:CM=9.9.9", "OFFICER", "Coww Brightmane")
Heard("H1:CM=9.9.9", "BN_WHISPER", "Coww Brightmane")
Fire("CHAT_MSG_ADDON", "OtherPrefix", "H1:CM=9.9.9", "GUILD", "Coww Brightmane")
Advance(30)
Equal(#printed .. Sent(), "0", "your own, a whisper, other chat and other prefixes: nothing")
secrets["Hidden Name"] = true
Heard("H1:CM=9.9.9", "GUILD", "Hidden Name")
secrets["H1:CM=9.8.0"] = true
Heard("H1:CM=9.8.0", "GUILD", "Coww Brightmane")
secrets = { SquirtVersions = true }
Heard("H1:CM=9.7.0", "GUILD", "Coww Brightmane")
secrets = { GUILD = true }
Heard("H1:CM=9.6.0", "GUILD", "Coww Brightmane")
secrets = {}
Equal(#printed, 0, "a secret sender, text, prefix or kind of chat is never compared")
Heard("H1:CM=9.9.9", "WHISPER", "Zriel Gustbellow")
Equal(printed[1], LINE:format("Forever Enhanced Cooldown Manager", "9.9.9", "1.7.0"), "a whisper to yourself tests it")
-- With a surname, someone called just your first name isn't you.
Settled()
Heard("H1:CM=1.8.0", "GUILD", "Zriel")
Equal(#printed, 1, "a guildmate called Zriel is heard")
me = { "Zriel" }
Settled()
me = { "Zriel" }
Heard("H1:CM=1.8.0", "GUILD", "Zriel-Zephras")
Equal(#printed, 0, "without a surname, Zriel with a realm is you")
-- Too much from one player in a minute is ignored.
Settled()
for i = 1, 6 do Heard("A1:XP=1.0.0", "CHANNEL", "Coww Brightmane") end
Heard("A1:CM=1.8.0", "GUILD", "Coww Brightmane")
Equal(#printed, 0, "the seventh message in a minute is ignored")
Advance(61)
Heard("A1:CM=1.8.0", "GUILD", "Coww Brightmane")
Equal(#printed, 1, "a minute later, heard again")
Equal(lib:Status(), "on, on channel 3, 1 players heard, 2 sent", "players heard, counted once")

-- In a fight ------------------------------------------------------------------------

Settled()
combat = true
Heard("H1:CM=1.8.0", "GUILD", "Coww Brightmane")
Heard("H1:ER=1.0.0", "GUILD", "Bella Stone")
Advance(60)
Equal(#printed, 0, "no line in a fight")
combat = false
Fire("PLAYER_REGEN_ENABLED")
Equal(printed[1], LINE:format("Forever Enhanced Cooldown Manager", "1.8.0", "1.7.0"), "it comes as the fight ends")
Advance(10)
Equal(Sent(), "GUILD A1:CM=1.7.0,ER=1.7.2", "and the answer is sent then, never in it")
-- A line held in a fight whose tick goes off meanwhile is dropped.
Settled()
combat = true
Heard("H1:CM=1.8.0", "GUILD", "Coww Brightmane")
ticks.CM = false
combat = false
Fire("PLAYER_REGEN_ENABLED")
Equal(#printed, 0, "switched off in the fight: no line")
-- Chat held back by the game: waited out.
Settled()
lockdown = true
Heard("H1:CM=1.6.0", "GUILD", "Coww Brightmane")
Advance(40)
Equal(Sent(), "", "nothing while chat is held back")
lockdown = false
Advance(20)
Equal(Sent(), "GUILD A1:CM=1.7.0,ER=1.7.2", "sent after")

-- The game's answers to a send ---------------------------------------------------

-- Throttled: a hello tries again, a while later each time.
Fresh()
results.GUILD = 3
Fire("PLAYER_ENTERING_WORLD", true, false)
Advance(20)
Equal(Sent(), "GUILD H1:CM=1.7.0,ER=1.7.2", "throttled")
Advance(4)
Equal(Sent(), "", "waits")
results.GUILD = 0
Advance(2)
Equal(Sent(), "GUILD H1:CM=1.7.0,ER=1.7.2", "and tries again")
-- A yell the server doesn't allow is never tried again this session.
Settled()
results.YELL = 4
resting = true
Fire("PLAYER_UPDATE_RESTING")
Advance(10)
Equal(Sent(), "YELL H1:CM=1.7.0,ER=1.7.2", "in a city: a yell for players nearby")
Equal(lib.blocked.YELL, true, "refused: not allowed here")
Heard("H1:CM=1.6.0", "YELL", "Coww Brightmane")
Advance(3600)
Fire("ZONE_CHANGED_NEW_AREA")
Advance(30)
Equal(Sent(), "", "never again this session, nor an answer")
-- Yells: in a city or an inn, every half hour at most, never inside.
Settled()
resting = true
Fire("PLAYER_UPDATE_RESTING")
Advance(10)
Equal(Sent(), "YELL H1:CM=1.7.0,ER=1.7.2", "a yell")
Fire("ZONE_CHANGED_NEW_AREA")
Advance(600)
Equal(Sent(), "", "not again within half an hour")
Advance(1200)
inside = true
Fire("ZONE_CHANGED_NEW_AREA")
Advance(30)
Equal(Sent(), "", "never inside a dungeon")
-- Inside, the channel and yells wait; the guild still hears.
Settled()
inside = true
Heard("H1:CM=1.6.0", "CHANNEL", "Coww Brightmane")
Heard("H1:CM=1.6.0", "GUILD", "Bella Stone")
Advance(20)
Equal(Sent(), "GUILD A1:CM=1.7.0,ER=1.7.2", "inside: the guild's answer only")
inside = false
Advance(40)
Equal(Sent(), "CHANNEL#3 A1:CM=1.7.0,ER=1.7.2", "the channel's once out")
-- The channel lost its number: rejoined, never sent to a wrong number.
Settled()
channels.LatestVersion = nil
Heard("H1:CM=1.6.0", "CHANNEL", "Coww Brightmane")
Advance(10)
Equal(Sent(), "", "no number: nothing sent")
-- Leaving keeps its "left" line out of the chat windows too.
Fresh()
ticks.CM, ticks.ER, ticks.CP = false, false, false
channels.LatestVersion = 3
Fire("PLAYER_ENTERING_WORLD", false, true)
Equal(leaves .. " " .. type(filters.CHAT_MSG_CHANNEL_NOTICE), "1 function", "left, its notice filtered")
-- Addon messages refused on the channel: it's left for the session, its slot freed.
Settled()
results.CHANNEL = 4
Heard("H1:CM=1.6.0", "CHANNEL", "Coww Brightmane")
Advance(10)
Equal(Sent(), "CHANNEL#3 A1:CM=1.7.0,ER=1.7.2", "tried once")
Equal(GetChannelName("LatestVersion") .. " " .. tostring(lib.refused), "0 no addon messages", "refused: the channel left")
Fire("CHAT_MSG_CHANNEL_NOTICE", "YOU_LEFT", "", "", "3. LatestVersion", "", "", 0, 3, "LatestVersion")
lib:Refresh()
Advance(600)
Equal(joins .. " " .. Sent(), "1 ", "not joined again")
-- Its number refused three times in a row: left too.
Settled()
results.CHANNEL = 7
Heard("H1:CM=1.6.0", "CHANNEL", "Coww Brightmane")
Advance(10)
Equal(GetChannelName("LatestVersion"), 3, "once: still in it")
lib:Refresh()
Advance(10)
lib:Refresh()
Advance(10)
Equal(Sent(), "CHANNEL#3 A1:CM=1.7.0,ER=1.7.2;CHANNEL#3 H1:CM=1.7.0,ER=1.7.2;CHANNEL#3 H1:CM=1.7.0,ER=1.7.2",
    "tried three times")
Equal(GetChannelName("LatestVersion") .. " " .. tostring(lib.refused), "0 no addon messages", "then left")
-- A join that lands after every tick went off is left at once.
Fresh()
joinWorks = false
Fire("PLAYER_ENTERING_WORLD", true, false)
Advance(30)
Equal(joins, 1, "asked for the channel")
ticks.CM, ticks.ER, ticks.CP = false, false, false
lib:Refresh()
Equal(leaves, 0, "nothing to leave yet")
channels.LatestVersion = 3
Fire("CHAT_MSG_CHANNEL_NOTICE", "YOU_JOINED", "", "", "3. LatestVersion", "", "", 0, 3, "LatestVersion")
Equal(leaves .. " " .. GetChannelName("LatestVersion"), "1 0", "the late join is left")
-- Every tick off, then one on before the leave lands: no hello into it, the
-- addon's own leave isn't taken for yours, and it's joined afresh.
Settled()
local leaving = LeaveChannelByName
LeaveChannelByName = function() leaves = leaves + 1 end
ticks.CM, ticks.ER, ticks.CP = false, false, false
lib:Refresh()
ticks.ER = true
lib:Refresh()
Advance(3)
Equal(Sent(), "", "no hello while it's being left")
LeaveChannelByName = leaving
channels.LatestVersion = nil
Fire("CHAT_MSG_CHANNEL_NOTICE", "YOU_LEFT", "", "", "3. LatestVersion", "", "", 0, 3, "LatestVersion")
Advance(30)
Equal(tostring(lib.refused) .. " " .. GetChannelName("LatestVersion") .. " " .. joins, "nil 3 2", "joined again")
Equal(Sent(), "CHANNEL#3 H1:ER=1.7.2", "with a hello")
-- In a crowd, answers out there wait longer, so the first few stop the rest;
-- a group's still comes quickly.
Settled()
lib.heardCount = 400
group = "PARTY"
Heard("H1:CM=1.6.0", "CHANNEL", "Coww Brightmane")
Heard("H1:CM=1.6.0", "PARTY", "Bella Stone")
Advance(25)
local early = Sent()
Equal(early:find("PARTY A1:", 1, true) ~= nil and early:find("CHANNEL", 1, true) == nil, true,
    "the group's answer comes; in a crowd the channel's waits")
Advance(10)
Equal(Sent(), "CHANNEL#3 A1:CM=1.7.0,ER=1.7.2", "then comes")
-- A fault inside is caught, never thrown into the game, and kept for the status line.
Settled()
local holding = C_ChatInfo.InChatMessagingLockdown
C_ChatInfo.InChatMessagingLockdown = function() error("broken") end
Heard("H1:CM=1.6.0", "GUILD", "Coww Brightmane")
Advance(10)
C_ChatInfo.InChatMessagingLockdown = holding
Equal(Sent() .. tostring(lib:Status():find(", last error: ", 1, true) ~= nil), "true", "nothing sent, the fault in the status line")

-- Trying it in game (hidden) -------------------------------------------------------------

-- Every ticked addon's line, one patch on, nothing sent; a development copy has "dev".
Settled()
Equal(lib:Test(), 3, "three addons tried")
table.sort(printed)
Equal(table.concat(printed, "|"), LINE:format("EraUI", "1.7.3", "1.7.2") .. "|"
    .. LINE:format("Forever Enhanced Cooldown Manager", "1.7.1", "1.7.0") .. "|"
    .. LINE:format("Forever Enhanced Cooldown Pulse", "9.9.9", "dev"), "each addon's line")
Advance(60)
Equal(Sent(), "", "nothing sent")
-- Again, for one addon and a version of your own: said again.
printed = {}
Equal(lib:Test("CM", "2.0.0"), 1, "one addon")
Equal(printed[1], LINE:format("Forever Enhanced Cooldown Manager", "2.0.0", "1.7.0"), "with that version, said again")
printed = {}
lib:Test("CM", "1.0.0")
Equal(printed[1], LINE:format("Forever Enhanced Cooldown Manager", "1.7.1", "1.7.0"), "an older one: one patch on instead")
-- An unticked addon isn't tried, and says so.
printed = {}
ticks.CM = false
Equal(lib:Test("CM") .. " " .. #printed, "0 1", "nothing tried")
Equal(printed[1], "Nothing to try: no addon CM here has its update tick on.", "and a line saying why")
-- In a fight, the line waits for its end.
Settled()
combat = true
lib:Test("ER")
Equal(#printed, 0, "no line in a fight")
combat = false
Fire("PLAYER_REGEN_ENABLED")
Equal(printed[1], LINE:format("EraUI", "1.7.3", "1.7.2"), "it comes as the fight ends")

-- Copies of this file ------------------------------------------------------------------

-- An older copy's table, loaded first: this copy's functions take over, and
-- what it kept stays.
Reset()
local kept = { code = "OLD", title = "Old", version = "1.0.0", IsOn = function() return true end, Print = print }
SquirtVersions = { version = 0, addons = { OLD = kept }, Register = function() return "old" end }
assert(loadfile(PATH))()
Equal(SquirtVersions.addons.OLD, kept, "an older copy's addons kept")
Equal(SquirtVersions.version, 1, "this copy's functions")
Equal(SquirtVersions:Register({ code = "NEW", title = "New", IsOn = kept.IsOn, Print = print }), true, "its Register")
Equal(#frames, 1, "one event frame")
-- A newer copy's table: this copy changes nothing of it.
Reset()
local setups = 0
local newer = { version = 99, Register = function() return "newer" end, Setup = function() setups = setups + 1 end }
SquirtVersions = newer
assert(loadfile(PATH))()
Equal(SquirtVersions, newer, "the same table")
Equal(SquirtVersions.version .. " " .. SquirtVersions:Register() .. " " .. setups, "99 newer 1",
    "a newer copy's functions kept, its own setup run")
Equal(#frames, 0, "and no frame of this copy's")
-- Two copies loaded: one frame, one prefix, the second copy's addons too.
Fresh()
assert(loadfile(PATH))()
Equal(#frames, 1, "a second copy makes no second frame")
Equal(SquirtVersions.addons.CM ~= nil, true, "and keeps the addons")
-- Loaded after login (an addon loaded later): starts at once.
Reset()
SquirtVersions = nil
loggedIn = true
assert(loadfile(PATH))()
SquirtVersions:Register({ code = "CM", title = "T", version = "1.0.0", IsOn = function() return true end, Print = print })
Advance(25)
Equal(Sent(), "GUILD H1:CM=1.0.0", "loaded after login: the hellos follow")

io.write("SquirtVersions checks passed: " .. checks .. " assertions.\n")
