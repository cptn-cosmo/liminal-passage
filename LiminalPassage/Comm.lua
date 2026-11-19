-- Liminal Passage: channel management, message transport and searching.
local _, ns = ...

local SEP = "~"
local SEARCH_WINDOW = 4 -- seconds to collect replies

local function pack(...)
    local t = {}
    for i = 1, select("#", ...) do
        local v = select(i, ...)
        t[i] = ns.Clean(v == nil and "" or tostring(v))
    end
    return table.concat(t, SEP)
end

local function split(msg)
    local t = {}
    for field in (msg .. SEP):gmatch("(.-)" .. SEP) do t[#t + 1] = field end
    return t
end

function ns:Whisper(target, ...)
    C_ChatInfo.SendAddonMessage(ns.PREFIX, pack(...), "WHISPER", target)
end

function ns:Broadcast(...)
    local id = GetChannelName(ns.CHANNEL)
    if id and id > 0 then
        C_ChatInfo.SendAddonMessage(ns.PREFIX, pack(...), "CHANNEL", id)
        return true
    end
    return false
end

---------------------------------------------------------------------------
-- Hidden channel
---------------------------------------------------------------------------
local joinWaiters, joinTicker = {}, nil

function ns:HideChannel()
    for i = 1, (NUM_CHAT_WINDOWS or 10) do
        local cf = _G["ChatFrame" .. i]
        if cf then
            if ChatFrame_RemoveChannel then
                pcall(ChatFrame_RemoveChannel, cf, ns.CHANNEL)
            elseif cf.RemoveChannel then
                pcall(cf.RemoveChannel, cf, ns.CHANNEL)
            end
        end
    end
end

function ns:JoinChannel(cb)
    local id = GetChannelName(ns.CHANNEL)
    if id and id > 0 then
        if cb then cb(id) end
        return
    end
    if cb then joinWaiters[#joinWaiters + 1] = cb end
    if joinTicker then return end

    JoinTemporaryChannel(ns.CHANNEL)
    local tries = 0
    joinTicker = C_Timer.NewTicker(0.25, function(ticker)
        tries = tries + 1
        local cid = GetChannelName(ns.CHANNEL)
        if tries == 12 and not (cid and cid > 0) then
            JoinTemporaryChannel(ns.CHANNEL) -- retry once
        end
        if (cid and cid > 0) or tries >= 40 then
            ticker:Cancel()
            joinTicker = nil
            local waiters = joinWaiters
            joinWaiters = {}
            if cid and cid > 0 then
                ns:HideChannel()
                for _, w in ipairs(waiters) do w(cid) end
            else
                ns:Print("Could not join the Liminal Passage channel. Try again in a moment.")
            end
        end
    end)
end

function ns:LeaveChannel()
    local id = GetChannelName(ns.CHANNEL)
    if id and id > 0 then LeaveChannelByName(ns.CHANNEL) end
end

---------------------------------------------------------------------------
-- Searching (traveler side)
---------------------------------------------------------------------------
-- opts: { mapID = uiMapID, text = "subzone", point = { mapID, x, y }, label = "..." }
function ns:Search(opts)
    opts = opts or {}
    local text = ns.Clean(opts.text or ""):sub(1, 60)
    local mapID = opts.mapID or 0
    local label = opts.label
    if not label then
        if mapID > 0 then
            local info = C_Map.GetMapInfo(mapID)
            label = info and info.name or ("map " .. mapID)
        elseif text ~= "" then
            label = '"' .. text .. '"'
        else
            label = "anywhere"
        end
        if opts.point then label = "near a spot in " .. label end
    end

    local search = {
        id = ns.Token(), mapID = mapID, text = text, point = opts.point,
        label = label, started = GetTime(),
    }
    self.search = search
    wipe(self.results)
    self:Notify()

    self:JoinChannel(function()
        ns:Broadcast("Q", search.id, mapID, text)
    end)

    C_Timer.After(SEARCH_WINDOW, function()
        if self.search ~= search then return end
        search.done = true
        if self.db.status == "offline" and not self.travel then
            self:LeaveChannel() -- only joined to search; stay invisible
        end
        self:Notify()
    end)
end

function ns:SortedResults()
    local list = {}
    for _, r in pairs(self.results) do list[#list + 1] = r end
    table.sort(list, function(a, b)
        if a.dist and b.dist then return a.dist < b.dist end
        if a.dist or b.dist then return a.dist ~= nil end
        if a.status ~= b.status then return a.status == "online" end
        return a.name < b.name
    end)
    return list
end

---------------------------------------------------------------------------
-- Message handlers
---------------------------------------------------------------------------
ns.msg = ns.msg or {}

-- Query from a traveler (received on the channel).
ns.msg.Q = function(self, sender, f)
    if self.db.status == "offline" then return end
    if InCombatLockdown() or not IsResting() then return end
    local qid, qMapID, qText = f[2], tonumber(f[3]) or 0, f[4] or ""
    if not self:MatchesQuery(qMapID, qText) then return end

    C_Timer.After(math.random() * 1.5, function()
        if self.db.status == "offline" or not IsResting() then return end
        local mapID, x, y, zone, sub = self:GetLocation()
        local _, class = UnitClass("player")
        self:Whisper(sender, "P", qid, self.db.status, mapID or 0,
            x and ("%.4f"):format(x) or "", y and ("%.4f"):format(y) or "",
            class, UnitLevel("player"), zone, sub)
    end)
end

-- Presence reply from a host.
ns.msg.P = function(self, sender, f)
    local s = self.search
    if not s or s.id ~= f[2] then return end
    local status = f[3]
    if status ~= "online" and status ~= "busy" then return end
    local r = {
        name = sender, status = status,
        mapID = tonumber(f[4]), x = tonumber(f[5]), y = tonumber(f[6]),
        class = f[7], level = tonumber(f[8]), zone = f[9] or "", sub = f[10] or "",
    }
    if r.mapID == 0 then r.mapID = nil end
    if s.point then
        r.dist = self:Distance(s.point.mapID, s.point.x, s.point.y, r.mapID, r.x, r.y)
    end
    self.results[sender] = r
    self:Notify()
end

ns:On("CHAT_MSG_ADDON", function(prefix, msg, _, sender)
    if ns.IsSecret(prefix) or ns.IsSecret(msg) or ns.IsSecret(sender) then return end
    if prefix ~= ns.PREFIX then return end
    sender = ns.FullName(sender)
    if not sender or sender == ns:Me() then return end
    local f = split(msg)
    local handler = ns.msg[f[1]]
    if handler then handler(ns, sender, f) end
end)
