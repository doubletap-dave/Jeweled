-- tests/test_comms.lua: Offline LuaJIT discrete-event multi-client simulator for
-- Comms.lua and Ranks.lua (Guild Vendetta testing methodology: real simulated timer
-- delays so near-tie responder ordering and flood limits are actually exercised).
-- Run: luajit tests/test_comms.lua

local passed = 0
local function check(name, cond, detail)
	if not cond then
		error("FAIL [" .. name .. "]: " .. tostring(detail or "assertion failed"))
	end
	passed = passed + 1
end

local function loadInto(path, nsTable)
	local chunk, err = loadfile(path)
	assert(chunk, "Failed to load " .. path .. ": " .. tostring(err))
	return chunk("Jeweled", nsTable)
end

-- Discrete-event network bus with real timer queue
local function createSimWorld(baseEpoch)
	local world = {
		simTime = 0.0,
		baseEpoch = baseEpoch or 1795570000,
		timers = {},
		clients = {},
		packets = {}, -- transcript of all wire packets
		maxPacketBytes = 0,
	}

	function world.after(delay, fn)
		local fireAt = world.simTime + math.max(0.001, delay)
		world.timers[#world.timers + 1] = { at = fireAt, fn = fn }
	end

	function world.runUntil(targetTime)
		while true do
			local bestIdx, bestAt = nil, targetTime + 1
			for i = 1, #world.timers do
				if world.timers[i].at <= targetTime and world.timers[i].at < bestAt then
					bestAt = world.timers[i].at
					bestIdx = i
				end
			end
			if not bestIdx then break end
			local ev = table.remove(world.timers, bestIdx)
			world.simTime = ev.at
			ev.fn()
		end
		world.simTime = targetTime
	end

	function world.addClient(id, name, initialScore, opts)
		opts = opts or {}
		local cNs = {}
		local db = {
			network = true,
			best = { score = initialScore or 0, flightPPS = opts.pps or 0, games = opts.games or 5 },
			ranks = {},
			rankMeta = { lastPrune = 0 },
		}
		cNs.DB = function() return db end
		cNs.Get = function(k) return db[k] end
		cNs.Print = function() end

		loadInto("Jeweled/Board.lua", cNs)
		loadInto("Jeweled/Ranks.lua", cNs)
		loadInto("Jeweled/Comms.lua", cNs)

		local joined = false
		local seed = id * 997 + 13
		local client = {
			id = id,
			guid = "Player-16001-" .. string.format("%08X", id),
			name = name,
			ns = cNs,
			db = db,
			inGuild = opts.inGuild or false,
			sentCount = 0,
			sendTimes = {},
		}

		local env = {
			getTime = function() return world.simTime end,
			nowTs = function() return world.baseEpoch + math.floor(world.simTime) end,
			random = function()
				seed = (seed * 1103515245 + 12345) % 2147483648
				return (seed % 10000) / 10000.0
			end,
			myGuid = function() return client.guid end,
			myName = function() return client.name end,
			isInGuild = function() return client.inGuild end,
			fallbackDist = function() return client.inGuild and "GUILD" or nil end,
			registerPrefix = function() end,
			joinChannel = function() joined = true end,
			leaveChannel = function() joined = false end,
			getChannelId = function() return joined and 7 or nil end,
			after = function(delay, fn) world.after(delay, fn) end,
			sendAddonMessage = function(prefix, msg, dist, target)
				client.sentCount = client.sentCount + 1
				client.sendTimes[#client.sendTimes + 1] = world.simTime
				if #msg > world.maxPacketBytes then world.maxPacketBytes = #msg end
				world.packets[#world.packets + 1] = {
					at = world.simTime,
					from = client.guid,
					dist = dist,
					msg = msg,
				}
				-- Deliver with tiny realistic 20ms wire latency to all listening peers
				world.after(0.02, function()
					for _, peer in ipairs(world.clients) do
						if peer ~= client then
							local deliver = false
							if dist == "CHANNEL" and peer.isJoined() then
								deliver = true
							elseif dist == "GUILD" and peer.inGuild and client.inGuild then
								deliver = true
							end
							if deliver then
								peer.comms.OnMessage(prefix, msg, dist, client.name, client.guid)
							end
						end
					end
				end)
			end,
		}

		client.isJoined = function() return joined end
		client.comms = cNs.Comms.New(cNs, env)

		-- Seed own record locally if initialScore > 0
		if initialScore and initialScore > 0 then
			cNs.Ranks.MergeRecord({
				guid = client.guid,
				name = client.name,
				best = initialScore,
				bestPPS = opts.pps or 25.0,
				games = opts.games or 5,
				ts = world.baseEpoch,
				isWeekEligible = true,
			}, world.baseEpoch)
		end

		world.clients[#world.clients + 1] = client
		return client
	end

	return world
end

-- TEST 1: 15-client login storm + newcomer catch-up & deterministic responder ordering
do
	local world = createSimWorld(1795570000)
	for i = 1, 14 do
		local c = world.addClient(i, "Hero " .. i, 1000 * i, { pps = 10 + i, inGuild = (i <= 5) })
		c.comms.Start()
	end
	-- Advance past 6-minute newcomer age so the 14 veterans know all peers
	world.runUntil(400)

	-- Verify veterans heard each other
	check("veterans_online_count", world.clients[1].comms.GetOnlineCount() == 14,
		"got " .. world.clients[1].comms.GetOnlineCount())

	-- Record packet count before newcomer joins
	local packetsBefore = #world.packets

	-- Client 15 joins fresh with empty ranks table
	local newcomer = world.addClient(15, "Fresh Newcomer", 500, { pps = 8, inGuild = true })
	newcomer.comms.Start()
	world.runUntil(435)

	-- Newcomer must converge to all 15 records (14 veterans + self)
	local count = 0
	for _ in pairs(newcomer.db.ranks) do count = count + 1 end
	check("newcomer_converges_union", count == 15, "expected 15 records, got " .. count)

	-- Count how many R (record reply) packets were broadcast for newcomer's query
	local rPackets = 0
	local sentGuids = {}
	local dupGuids = 0
	for i = packetsBefore + 1, #world.packets do
		local pkt = world.packets[i]
		if pkt.dist == "CHANNEL" and pkt.msg:find("^1;R;") then
			rPackets = rPackets + 1
			local body = pkt.msg:match("^1;R;[^;]+;[^;]+;[^;]+;(.+)$")
			if body then
				for rec in body:gmatch("[^|]+") do
					local g = rec:match("^([^,]+)")
					if g then
						if sentGuids[g] then dupGuids = dupGuids + 1 end
						sentGuids[g] = true
					end
				end
			end
		end
	end
	-- With deterministic responder ordering, rank 0 answers at 0.5s and later peers suppress duplicates!
	check("responder_ordering_no_flood", rPackets <= 4, "too many R packets: " .. rPackets)
	check("each_missing_record_sent_once", dupGuids == 0, "duplicate records sent: " .. dupGuids)
	check("max_packet_within_240_door", world.maxPacketBytes <= 240, "max bytes: " .. world.maxPacketBytes)
end

-- TEST 2: Token bucket rate limit holds under burst enqueue
do
	local world = createSimWorld(1795570000)
	local c = world.addClient(1, "Burst Tester", 5000)
	c.comms.Start()
	-- Wait past the +8s login beacon/query and refill bucket completely
	world.runUntil(20)
	local before = c.sentCount
	-- Enqueue 8 messages simultaneously
	for i = 1, 8 do
		c.comms.Enqueue("1;H;" .. c.guid .. ";Burst Tester;" .. (5000 + i) .. ";10;1", "CHANNEL")
	end
	-- Immediately only burst=3 should have gone out
	check("token_bucket_initial_burst_3", (c.sentCount - before) == 3, "got " .. (c.sentCount - before))
	world.runUntil(35)
	check("token_bucket_eventually_drains_all", (c.sentCount - before) == 8 and c.comms.QueueDepth() == 0,
		"got " .. (c.sentCount - before))
	-- Oversize > 240 bytes must be refused cleanly
	local okOver, reason = c.comms.Enqueue(string.rep("A", 241), "CHANNEL")
	check("reject_over_240_bytes", okOver == false and reason == "too_large")
end

-- TEST 3: Anti-cheat validation (forged absurd score, sender-GUID spoofing, rate abuse)
do
	local world = createSimWorld(1795570000)
	local victim = world.addClient(1, "Honest Player", 2000)
	victim.comms.Start()
	world.runUntil(1)

	-- Forged absurd score (9,999,999 > 1,000,000 cap)
	local badGuid = "Player-16001-DEADBEEF"
	victim.comms.OnMessage("JEWELED",
		"1;S;" .. badGuid .. ";Cheater;9999999;900;classic;;5;10;1795570001",
		"CHANNEL", "Cheater", badGuid)
	check("reject_forged_absurd_score", victim.db.ranks[badGuid] == nil)

	-- Sender-GUID binding: Attacker tries to submit score under another player's GUID
	local otherGuid = "Player-16001-00009999"
	victim.comms.OnMessage("JEWELED",
		"1;S;" .. otherGuid .. ";Spoofed;25000;80;classic;;30;320;1795570001",
		"CHANNEL", "Attacker", badGuid)
	check("reject_sender_guid_spoof", victim.db.ranks[otherGuid] == nil)

	-- Future timestamp rejection
	victim.comms.OnMessage("JEWELED",
		"1;S;" .. badGuid .. ";TimeTraveler;12000;40;classic;;20;300;1999999999",
		"CHANNEL", "TimeTraveler", badGuid)
	check("reject_future_timestamp", victim.db.ranks[badGuid] == nil)

	-- Legitimate score accepted
	local legitGuid = "Player-16001-00007777"
	victim.comms.OnMessage("JEWELED",
		"1;S;" .. legitGuid .. ";Legit Flyer;15000;95.5;flight;Stormwind->Ironforge;22;157;1795570001",
		"CHANNEL", "Legit Flyer", legitGuid)
	check("accept_legit_score", victim.db.ranks[legitGuid] ~= nil and victim.db.ranks[legitGuid].best == 15000)

	-- Monotonic max: lower score never overwrites higher score
	victim.comms.OnMessage("JEWELED",
		"1;S;" .. legitGuid .. ";Legit Flyer;4000;20;classic;;10;200;1795570002",
		"CHANNEL", "Legit Flyer", legitGuid)
	check("monotonic_max_preserved", victim.db.ranks[legitGuid].best == 15000)
end

-- TEST 4: 60-day pruning, rolling 7-day This Week view, and 14 classic PvP guild rank titles
do
	local world = createSimWorld(1795570000)
	local c = world.addClient(1, "Rank Keeper", 5000)
	local Ranks = c.ns.Ranks
	local now = 1795570000

	-- Insert an expired 70-day-old record and a fresh record
	Ranks.MergeRecord({ guid = "G-OLD", name = "Ancient", best = 99999, bestPPS = 80, ts = now - 70 * 86400 }, now)
	Ranks.MergeRecord({ guid = "G-NEW", name = "Current", best = 12000, bestPPS = 50, ts = now - 100, isWeekEligible = true }, now)
	local pruned = Ranks.Prune(now, true)
	check("prune_60_day_stale", pruned == 1 and c.db.ranks["G-OLD"] == nil and c.db.ranks["G-NEW"] ~= nil)

	-- Rolling 7-day week view includes fresh record, excludes 10-day-old record while keeping all-time
	Ranks.MergeRecord({ guid = "G-MID", name = "LastMonth", best = 45000, bestPPS = 60, ts = now - 10 * 86400, isWeekEligible = true }, now)
	local globalRows = Ranks.BuildView("global", { nowTs = now })
	local weekRows = Ranks.BuildView("week", { nowTs = now })
	check("global_keeps_alltime", #globalRows == 3)
	check("week_excludes_10d_old", #weekRows == 2, "got " .. #weekRows)

	-- Guild 14 classic PvP rank titles (Alliance & Horde)
	local roster = { ["G-NEW"] = true, ["G-MID"] = true, [c.guid] = true }
	local aGuild = Ranks.BuildView("guild", { nowTs = now, guildRoster = roster, faction = "Alliance" })
	local hGuild = Ranks.BuildView("guild", { nowTs = now, guildRoster = roster, faction = "Horde" })
	check("guild_top_alliance_grand_marshal", aGuild[1].guildTitle == "Grand Marshal", tostring(aGuild[1].guildTitle))
	check("guild_bottom_alliance_private", aGuild[#aGuild].guildTitle == "Private", tostring(aGuild[#aGuild].guildTitle))
	check("guild_top_horde_high_warlord", hGuild[1].guildTitle == "High Warlord", tostring(hGuild[1].guildTitle))
	check("guild_bottom_horde_scout", hGuild[#hGuild].guildTitle == "Scout", tostring(hGuild[#hGuild].guildTitle))
end

print(string.format("ALL %d COMMS & RANKS SIMULATION TESTS PASSED", passed))
