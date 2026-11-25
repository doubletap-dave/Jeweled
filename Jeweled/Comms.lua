-- Comms.lua: Guild & realm-wide P2P leaderboard sync protocol for Jeweled (§7.10).
-- Implements MasterBait presence + TacoTip stealth channel & token bucket +
-- Guild Vendetta deterministic responder ordering, chunked replies, and anti-cheat.
-- Injectable environment (Comms.New) allows exact production logic to run in
-- offline LuaJIT discrete-event multi-client simulations (tests/test_comms.lua).

local _, ns = ...
if type(ns) ~= "table" then ns = {} end

local Comms = {}
ns.Comms = Comms

Comms.PREFIX = "JEWELED"
Comms.PROTO_VERSION = "1"
Comms.CHANNEL_NAME = "jeweledsync"
Comms.CHANNEL_PASS = "jwl16001"
Comms.MAX_BYTES = 240
Comms.TOKEN_RATE = 1.5        -- 1 message per 1.5s
Comms.TOKEN_BURST = 3         -- burst max 3
Comms.PRESENCE_TTL = 600      -- 10 minutes online window
Comms.QUERY_COOLDOWN = 20     -- max 1 query answer per requester per 20s
Comms.REDRIVE_COOLDOWN = 30   -- max 1 sync round per 30s
Comms.BEACON_BASE = 300       -- 5 min heartbeat (+/- 60s jitter)
Comms.NEWCOMER_AGE = 360      -- online < 6 min waits +4s as late backup
Comms.MIN_TIMESTAMP = 1767225600 -- 2026-01-01 00:00:00 UTC
Comms.RATE_ABUSE_IGNORE = 600 -- 10 min ignore for inhuman score spam
Comms.MIN_SCORE_INTERVAL = 3  -- faster than 3s between score bursts flags abuse

-- Pure Lua 5.1 deterministic hash (no bitwise operators required)
local function stableHash(str)
	local h = 5381
	for i = 1, #str do
		h = (h * 33 + string.byte(str, i)) % 2147483647
	end
	return h
end
Comms.StableHash = stableHash

local function sanitizeField(s)
	if s == nil then return "" end
	return tostring(s):gsub("[;|%c]", "")
end

local function splitFields(str, sep)
	local out = {}
	local start = 1
	local sLen = #str
	while true do
		local pos = str:find(sep, start, true)
		if not pos then
			out[#out + 1] = str:sub(start)
			break
		end
		out[#out + 1] = str:sub(start, pos - 1)
		start = pos + 1
		if start > sLen + 1 then break end
	end
	return out
end

-- Create a Comms instance bound to `env` (real WoW API or offline sim stub)
function Comms.New(addonNs, env)
	local self = {}
	local queue = {}
	local tokens = Comms.TOKEN_BURST
	local lastRefill = env.getTime()
	local drainScheduled = false
	local loginTime = env.getTime()
	local presence = {}          -- guid -> { name, lastHeard }
	local queryLastAnswered = {} -- requesterGuid -> time
	local lastRedrive = -999
	local pendingReply = nil     -- { queryId, requester, sentGuids, timer }
	local scoreAbuse = {}        -- guid -> { count, windowStart, ignoreUntil }
	local devLog = {}            -- ring buffer of last 60 wire messages
	local channelId = nil
	local networkOn = true
	local beaconTimer = nil

	local function logWire(dir, dist, msg)
		devLog[#devLog + 1] = string.format("[%.1f] %s (%s): %s", env.getTime(), dir, tostring(dist), tostring(msg))
		if #devLog > 60 then
			table.remove(devLog, 1)
		end
	end

	function self.GetLog()
		return devLog
	end

	function self.DumpLog()
		if #devLog == 0 then
			if addonNs.Print then addonNs.Print("Comms log is empty.") end
			return
		end
		if addonNs.Print then addonNs.Print("Last " .. #devLog .. " comms messages:") end
		for i = math.max(1, #devLog - 24), #devLog do
			if addonNs.Print then addonNs.Print("  " .. devLog[i]) end
		end
	end

	function self.GetOnlineCount()
		local now = env.getTime()
		local myGuid = env.myGuid()
		local count = 0
		if myGuid and networkOn then
			presence[myGuid] = { name = env.myName(), lastHeard = now }
		end
		for guid, info in pairs(presence) do
			if (now - info.lastHeard) <= Comms.PRESENCE_TTL then
				count = count + 1
			else
				presence[guid] = nil
			end
		end
		return count
	end

	function self.GetKnownPeers()
		local now = env.getTime()
		local list = {}
		for guid, info in pairs(presence) do
			if (now - info.lastHeard) <= Comms.PRESENCE_TTL then
				list[#list + 1] = { guid = guid, name = info.name or guid }
			end
		end
		return list
	end

	local function refillTokens()
		local now = env.getTime()
		local dt = now - lastRefill
		if dt > 0 then
			tokens = math.min(Comms.TOKEN_BURST, tokens + dt / Comms.TOKEN_RATE)
			lastRefill = now
		end
	end

	local drainQueue
	local function scheduleDrain()
		if drainScheduled or #queue == 0 then return end
		drainScheduled = true
		refillTokens()
		local wait = tokens >= 1 and 0.05 or ((1 - tokens) * Comms.TOKEN_RATE)
		env.after(math.max(0.05, wait), function()
			drainScheduled = false
			drainQueue()
		end)
	end

	local function resolveChannelId()
		if not networkOn then return nil end
		local id = env.getChannelId(Comms.CHANNEL_NAME)
		if id and id > 0 then
			channelId = id
			return id
		end
		return nil
	end

	drainQueue = function()
		if not networkOn then
			for i = #queue, 1, -1 do queue[i] = nil end
			return
		end
		refillTokens()
		while #queue > 0 and tokens >= 1 do
			local item = table.remove(queue, 1)
			tokens = tokens - 1
			local dist = item.dist
			local target = item.target
			if dist == "CHANNEL" then
				local cid = resolveChannelId()
				if cid then
					target = cid
					env.sendAddonMessage(Comms.PREFIX, item.msg, "CHANNEL", target)
					logWire("OUT", "CH:" .. tostring(cid), item.msg)
				else
					-- Fallback to group/guild if channel not yet joined
					local fb = env.fallbackDist()
					if fb then
						env.sendAddonMessage(Comms.PREFIX, item.msg, fb, nil)
						logWire("OUT", fb, item.msg)
					end
				end
			else
				env.sendAddonMessage(Comms.PREFIX, item.msg, dist, target)
				logWire("OUT", dist, item.msg)
			end
		end
		if #queue > 0 then
			scheduleDrain()
		end
	end

	function self.Enqueue(msg, dist, target)
		if not networkOn then return false, "network_off" end
		if type(msg) ~= "string" or #msg > Comms.MAX_BYTES then
			return false, "too_large"
		end
		queue[#queue + 1] = { msg = msg, dist = dist or "CHANNEL", target = target }
		drainQueue()
		return true
	end

	function self.QueueDepth()
		return #queue
	end

	local function buildHello()
		local db = addonNs.DB and addonNs.DB()
		local best = db and db.best or {}
		return table.concat({
			Comms.PROTO_VERSION, "H",
			sanitizeField(env.myGuid()),
			sanitizeField(env.myName()),
			tostring(math.floor(best.score or 0)),
			tostring(math.floor((best.flightPPS or 0) * 10 + 0.5) / 10),
			tostring(math.floor(best.games or 0)),
		}, ";")
	end

	function self.SendBeacon(force)
		if not networkOn then return end
		if not force and #queue > 0 then return end
		local msg = buildHello()
		self.Enqueue(msg, "CHANNEL")
		if env.isInGuild() then
			self.Enqueue(msg, "GUILD")
		end
	end

	function self.BroadcastScore(score, pps, mode, route, moves, duration)
		if not networkOn then return end
		local nowTs = env.nowTs()
		local msg = table.concat({
			Comms.PROTO_VERSION, "S",
			sanitizeField(env.myGuid()),
			sanitizeField(env.myName()),
			tostring(math.floor(score or 0)),
			tostring(math.floor((pps or 0) * 10 + 0.5) / 10),
			sanitizeField(mode or "classic"),
			sanitizeField(route or ""),
			tostring(math.floor(moves or 0)),
			tostring(math.floor(duration or 0)),
			tostring(math.floor(nowTs)),
		}, ";")
		if #msg > Comms.MAX_BYTES then
			-- Trim route name if needed to stay under 240-byte door
			local shortRoute = sanitizeField(route or ""):sub(1, 32)
			msg = table.concat({
				Comms.PROTO_VERSION, "S",
				sanitizeField(env.myGuid()),
				sanitizeField(env.myName()),
				tostring(math.floor(score or 0)),
				tostring(math.floor((pps or 0) * 10 + 0.5) / 10),
				sanitizeField(mode or "classic"),
				shortRoute,
				tostring(math.floor(moves or 0)),
				tostring(math.floor(duration or 0)),
				tostring(math.floor(nowTs)),
			}, ";")
		end
		self.Enqueue(msg, "CHANNEL")
		if env.isInGuild() then
			self.Enqueue(msg, "GUILD")
		end
		-- Also record locally immediately
		if addonNs.Ranks and addonNs.Ranks.MergeRecord then
			addonNs.Ranks.MergeRecord({
				guid = env.myGuid(),
				name = env.myName(),
				best = math.floor(score or 0),
				bestPPS = pps and (math.floor(pps * 10 + 0.5) / 10) or 0,
				games = (addonNs.DB and addonNs.DB() and addonNs.DB().best and addonNs.DB().best.games) or 1,
				route = route,
				routeBest = (route and route ~= "") and math.floor(score or 0) or nil,
				routePPS = (route and route ~= "" and pps) and (math.floor(pps * 10 + 0.5) / 10) or nil,
				ts = nowTs,
			})
		end
	end

	function self.SendQuery(force)
		if not networkOn then return false end
		local now = env.getTime()
		if not force and (now - lastRedrive) < Comms.REDRIVE_COOLDOWN then
			return false
		end
		lastRedrive = now
		local qid = tostring(math.floor(now * 10))
		local msg = table.concat({
			Comms.PROTO_VERSION, "Q",
			sanitizeField(env.myGuid()),
			qid,
		}, ";")
		self.Enqueue(msg, "CHANNEL")
		if env.isInGuild() then
			self.Enqueue(msg, "GUILD")
		end
		return true
	end

	function self.SendBye()
		if not networkOn then return end
		local msg = table.concat({ Comms.PROTO_VERSION, "B", sanitizeField(env.myGuid()) }, ";")
		local cid = resolveChannelId()
		if cid then
			env.sendAddonMessage(Comms.PREFIX, msg, "CHANNEL", cid)
			logWire("OUT", "CH:" .. tostring(cid), msg)
		end
	end

	-- Compute Vendetta deterministic responder rank among known peers
	local function computeResponderDelay(requesterGuid, queryId)
		local myGuid = env.myGuid()
		local myName = env.myName() or myGuid
		local myKey = stableHash(myName .. "|" .. tostring(requesterGuid) .. "|" .. tostring(queryId))
		local rank = 0
		local peers = self.GetKnownPeers()
		for _, p in ipairs(peers) do
			if p.guid ~= myGuid and p.guid ~= requesterGuid then
				local pKey = stableHash((p.name or p.guid) .. "|" .. tostring(requesterGuid) .. "|" .. tostring(queryId))
				if pKey < myKey or (pKey == myKey and p.guid < myGuid) then
					rank = rank + 1
				end
			end
		end
		local delay = 0.5 + rank * 2.0
		-- Newcomers (online < 6 min) wait +4s as late backup
		if (env.getTime() - loginTime) < Comms.NEWCOMER_AGE then
			delay = delay + 4.0
		end
		return delay, rank
	end

	local function encodeCompactRecord(guid, rec)
		return table.concat({
			sanitizeField(guid),
			sanitizeField(rec.name or ""),
			tostring(math.floor(rec.best or 0)),
			tostring(math.floor((rec.bestPPS or 0) * 10 + 0.5) / 10),
			tostring(math.floor(rec.games or 0)),
			tostring(math.floor(rec.weekBest or 0)),
			tostring(math.floor(rec.lastSeen or 0)),
		}, ",")
	end

	local function decodeCompactRecord(chunk)
		local p = splitFields(chunk, ",")
		if #p < 7 then return nil end
		local guid = p[1]
		local name = p[2]
		local best = tonumber(p[3])
		local bestPPS = tonumber(p[4])
		local games = tonumber(p[5])
		local weekBest = tonumber(p[6])
		local lastSeen = tonumber(p[7])
		if not guid or guid == "" or not best or not bestPPS or not lastSeen then return nil end
		return {
			guid = guid,
			name = name,
			best = best,
			bestPPS = bestPPS,
			games = games or 0,
			weekBest = weekBest or 0,
			ts = lastSeen,
		}
	end

	local function isTimestampValid(ts)
		local nowTs = env.nowTs()
		if type(ts) ~= "number" then return false end
		if ts < Comms.MIN_TIMESTAMP or ts > (nowTs + 300) then return false end
		return true
	end

	local function checkRateAbuse(guid)
		local now = env.getTime()
		local info = scoreAbuse[guid]
		if not info then
			scoreAbuse[guid] = { count = 1, windowStart = now, ignoreUntil = 0 }
			return false
		end
		if info.ignoreUntil > now then
			return true
		end
		if (now - info.windowStart) > 15 then
			info.count = 1
			info.windowStart = now
			return false
		end
		info.count = info.count + 1
		if info.count > 4 then
			info.ignoreUntil = now + Comms.RATE_ABUSE_IGNORE
			return true
		end
		return false
	end

	local function answerQuery(requesterGuid, queryId, dist)
		local db = addonNs.DB and addonNs.DB()
		local ranks = db and db.ranks
		if not ranks then return end

		-- Collect records not already broadcast by an earlier responder
		local alreadySent = (pendingReply and pendingReply.queryId == queryId) and pendingReply.sentGuids or {}
		local encodedList = {}
		for guid, rec in pairs(ranks) do
			if not alreadySent[guid] and (rec.best or 0) > 0 then
				encodedList[#encodedList + 1] = { guid = guid, best = rec.best or 0, str = encodeCompactRecord(guid, rec) }
			end
		end
		if #encodedList == 0 then return end
		table.sort(encodedList, function(a, b) return a.best > b.best end)

		-- Pack into <= 240-byte chunks
		local chunks = {}
		local cur = {}
		local curLen = 0
		local headerReserve = 20 -- "1;R;99;99;qid;"
		for _, item in ipairs(encodedList) do
			local addLen = #item.str + (curLen > 0 and 1 or 0)
			if curLen + addLen + headerReserve > Comms.MAX_BYTES then
				if #cur > 0 then
					chunks[#chunks + 1] = table.concat(cur, "|")
				end
				cur = { item.str }
				curLen = #item.str
			else
				cur[#cur + 1] = item.str
				curLen = curLen + addLen
			end
		end
		if #cur > 0 then
			chunks[#chunks + 1] = table.concat(cur, "|")
		end

		local total = #chunks
		local outDist = (dist == "GUILD") and "GUILD" or "CHANNEL"
		for part, body in ipairs(chunks) do
			local msg = table.concat({
				Comms.PROTO_VERSION, "R",
				tostring(part), tostring(total),
				sanitizeField(queryId),
				body,
			}, ";")
			if #msg <= Comms.MAX_BYTES then
				self.Enqueue(msg, outDist)
			end
		end
	end

	-- Main inbound packet handler (CHAT_MSG_ADDON)
	function self.OnMessage(prefix, msg, dist, senderName, senderGuid)
		if prefix ~= Comms.PREFIX or not networkOn then return end
		if type(msg) ~= "string" or #msg == 0 or #msg > Comms.MAX_BYTES then return end
		logWire("IN", dist, msg)

		local parts = splitFields(msg, ";")
		if parts[1] ~= Comms.PROTO_VERSION then return end
		local op = parts[2]
		local now = env.getTime()
		local nowTs = env.nowTs()
		local Board = addonNs.Board

		if op == "H" then
			local guid = parts[3]
			local name = parts[4]
			local best = tonumber(parts[5])
			local bestPPS = tonumber(parts[6])
			local games = tonumber(parts[7])
			if not guid or guid == "" or not best or not bestPPS then return end
			-- Sender binding when client provides senderGuid
			if senderGuid and senderGuid ~= "" and senderGuid ~= guid then return end
			if Board and not Board.IsPlausibleScore(best, bestPPS, nil, nil) then return end

			presence[guid] = { name = name, lastHeard = now }
			if addonNs.Ranks and addonNs.Ranks.MergeRecord and best > 0 then
				addonNs.Ranks.MergeRecord({
					guid = guid,
					name = name,
					best = best,
					bestPPS = bestPPS,
					games = games or 0,
					ts = nowTs,
				})
			end

		elseif op == "S" then
			local guid = parts[3]
			local name = parts[4]
			local score = tonumber(parts[5])
			local pps = tonumber(parts[6])
			local mode = parts[7]
			local route = parts[8]
			local moves = tonumber(parts[9])
			local dur = tonumber(parts[10])
			local ts = tonumber(parts[11])
			if not guid or guid == "" or not score then return end
			-- Strict sender binding: nobody may report another player's score
			if senderGuid and senderGuid ~= "" and senderGuid ~= guid then return end
			if checkRateAbuse(guid) then return end
			if not isTimestampValid(ts) then return end
			if Board and not Board.IsPlausibleScore(score, pps, moves, dur) then return end

			presence[guid] = { name = name, lastHeard = now }
			if addonNs.Ranks and addonNs.Ranks.MergeRecord then
				addonNs.Ranks.MergeRecord({
					guid = guid,
					name = name,
					best = score,
					bestPPS = pps or 0,
					route = (route and route ~= "") and route or nil,
					routeBest = (route and route ~= "") and score or nil,
					routePPS = (route and route ~= "" and pps) and pps or nil,
					ts = ts,
					isWeekEligible = true,
				})
			end

		elseif op == "Q" then
			local reqGuid = parts[3]
			local queryId = parts[4] or "0"
			if not reqGuid or reqGuid == "" or reqGuid == env.myGuid() then return end
			local lastAns = queryLastAnswered[reqGuid]
			if lastAns and (now - lastAns) < Comms.QUERY_COOLDOWN then
				return
			end
			queryLastAnswered[reqGuid] = now

			-- Schedule deterministic responder turn
			local delay = computeResponderDelay(reqGuid, queryId)
			local replyState = { queryId = queryId, requester = reqGuid, sentGuids = {} }
			pendingReply = replyState
			env.after(delay, function()
				if pendingReply == replyState then
					answerQuery(reqGuid, queryId, dist)
					pendingReply = nil
				end
			end)

		elseif op == "R" then
			local queryId = parts[5]
			local body = parts[6]
			if not body or body == "" then return end
			local recs = splitFields(body, "|")
			for _, chunk in ipairs(recs) do
				local rec = decodeCompactRecord(chunk)
				if rec and isTimestampValid(rec.ts) then
					if not Board or Board.IsPlausibleScore(rec.best, rec.bestPPS, nil, nil) then
						-- Track overheard records so later responders stay quiet (Vendetta optimization)
						if pendingReply and pendingReply.queryId == queryId then
							pendingReply.sentGuids[rec.guid] = true
						end
						if addonNs.Ranks and addonNs.Ranks.MergeRecord then
							addonNs.Ranks.MergeRecord(rec)
						end
					end
				end
			end

		elseif op == "B" then
			local guid = parts[3]
			if guid and guid ~= "" then
				if senderGuid and senderGuid ~= "" and senderGuid ~= guid then return end
				presence[guid] = nil
			end
		end
	end

	local function scheduleNextBeacon()
		if not networkOn then return end
		local jitter = (env.random() * 120) - 60 -- +/- 60s
		local delay = math.max(60, Comms.BEACON_BASE + jitter)
		env.after(delay, function()
			if not networkOn then return end
			self.SendBeacon(false)
			scheduleNextBeacon()
		end)
	end

	function self.SetNetworkEnabled(enabled)
		networkOn = enabled and true or false
		if networkOn then
			env.joinChannel(Comms.CHANNEL_NAME, Comms.CHANNEL_PASS)
			env.after(1.5, function()
				if networkOn then
					self.SendBeacon(true)
					self.SendQuery(true)
				end
			end)
		else
			for i = #queue, 1, -1 do queue[i] = nil end
			env.leaveChannel(Comms.CHANNEL_NAME)
		end
	end

	function self.Start()
		loginTime = env.getTime()
		env.registerPrefix(Comms.PREFIX)
		networkOn = addonNs.Get and (addonNs.Get("network") ~= false) or true
		if networkOn then
			env.joinChannel(Comms.CHANNEL_NAME, Comms.CHANNEL_PASS)
			-- Vendetta timing: +8s after login send beacon + catch-up query
			env.after(8.0, function()
				if not networkOn then return end
				self.SendBeacon(true)
				self.SendQuery(false)
				scheduleNextBeacon()
			end)
		end
	end

	return self
end

-- Production WoW Forever 1.60.1 binding
local liveInstance = nil

local function makeWoWEnv()
	return {
		getTime = function() return GetTime and GetTime() or 0 end,
		nowTs = function() return time and time() or 0 end,
		random = function() return math.random() end,
		myGuid = function() return UnitGUID and UnitGUID("player") or "Player-0-0" end,
		myName = function() return UnitName and UnitName("player") or "Player" end,
		isInGuild = function() return IsInGuild and IsInGuild() or false end,
		fallbackDist = function()
			if IsInRaid and IsInRaid() then return "RAID" end
			if IsInGroup and IsInGroup() then return "PARTY" end
			if IsInGuild and IsInGuild() then return "GUILD" end
			return nil
		end,
		registerPrefix = function(p)
			if C_ChatInfo and C_ChatInfo.RegisterAddonMessagePrefix then
				pcall(C_ChatInfo.RegisterAddonMessagePrefix, p)
			end
		end,
		sendAddonMessage = function(p, msg, dist, target)
			if C_ChatInfo and C_ChatInfo.SendAddonMessage then
				pcall(C_ChatInfo.SendAddonMessage, p, msg, dist, target)
			end
		end,
		joinChannel = function(name, pass)
			-- Stealth channel join (TacoTip pattern): hide from chat frames
			if JoinChannelByName then
				pcall(JoinChannelByName, name, pass, nil, true)
			end
		end,
		leaveChannel = function(name)
			if LeaveChannelByName then
				pcall(LeaveChannelByName, name)
			end
		end,
		getChannelId = function(name)
			if GetChannelName then
				local id = GetChannelName(name)
				if id and id > 0 then return id end
			end
			return nil
		end,
		after = function(sec, fn)
			if C_Timer and C_Timer.After then
				C_Timer.After(sec, ns.Safe and ns.Safe(fn) or fn)
			end
		end,
	}
end

-- Stealth chat filter: suppress any accidental chat-frame noise from jeweledsync
if ChatFrame_AddMessageEventFilter then
	local function stealthFilter(_, _, _, _, _, _, _, _, _, _, channelBaseName)
		if type(channelBaseName) == "string" and channelBaseName:lower() == Comms.CHANNEL_NAME then
			return true
		end
		return false
	end
	pcall(ChatFrame_AddMessageEventFilter, "CHAT_MSG_CHANNEL", stealthFilter)
	pcall(ChatFrame_AddMessageEventFilter, "CHAT_MSG_CHANNEL_NOTICE", stealthFilter)
	pcall(ChatFrame_AddMessageEventFilter, "CHAT_MSG_CHANNEL_JOIN", stealthFilter)
	pcall(ChatFrame_AddMessageEventFilter, "CHAT_MSG_CHANNEL_LEAVE", stealthFilter)
end

-- Public facade methods delegating to liveInstance
function Comms.BroadcastScore(...) if liveInstance then liveInstance.BroadcastScore(...) end end
function Comms.SendQuery(force) if liveInstance then return liveInstance.SendQuery(force) end end
function Comms.SendBeacon(force) if liveInstance then liveInstance.SendBeacon(force) end end
function Comms.SetNetworkEnabled(on) if liveInstance then liveInstance.SetNetworkEnabled(on) end end
function Comms.GetOnlineCount() return liveInstance and liveInstance.GetOnlineCount() or 0 end
function Comms.DumpLog() if liveInstance then liveInstance.DumpLog() end end

if ns.On and ns.RegisterEvent then
	ns.On("LOGIN", function()
		liveInstance = Comms.New(ns, makeWoWEnv())
		liveInstance.Start()
	end)
	ns.On("LOGOUT", function()
		if liveInstance then liveInstance.SendBye() end
	end)
	ns.RegisterEvent("CHAT_MSG_ADDON", function(_, prefix, msg, dist, sender, _, _, _, _, _, _, _, senderGuid)
		if liveInstance then
			liveInstance.OnMessage(prefix, msg, dist, sender, senderGuid)
		end
	end)
	ns.RegisterEvent("ZONE_CHANGED_NEW_AREA", function()
		if liveInstance then liveInstance.SendQuery(false) end
	end)
end

return Comms
