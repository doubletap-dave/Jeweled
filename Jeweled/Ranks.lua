-- Ranks.lua: Leaderboard data aggregation, 60-day pruning, 14 classic PvP guild
-- rank tiers, and TacoTip-style Polestar-themed Leaderboard Window (§6.7, §7.10).

local _, ns = ...
if type(ns) ~= "table" then ns = {} end

local Ranks = {}
ns.Ranks = Ranks

Ranks.PRUNE_AGE = 60 * 86400 -- 60 days unseen
Ranks.MAX_RECORDS = 10000
Ranks.WEEK_SECONDS = 7 * 86400

Ranks.ALLIANCE_TITLES = {
	"Private", "Corporal", "Sergeant", "Master Sergeant", "Sergeant Major",
	"Knight", "Knight-Lieutenant", "Knight-Captain", "Knight-Champion",
	"Lieutenant Commander", "Commander", "Marshal", "Field Marshal", "Grand Marshal",
}

Ranks.HORDE_TITLES = {
	"Scout", "Grunt", "Sergeant", "Senior Sergeant", "First Sergeant",
	"Stone Guard", "Blood Guard", "Legionnaire", "Centurion",
	"Champion", "Lieutenant General", "General", "Warlord", "High Warlord",
}

-- Map 1-based rank out of `total` guild members to classic PvP rank title (1..14)
function Ranks.GetGuildRankTitle(rankPos, total, faction)
	local titles = (faction == "Horde") and Ranks.HORDE_TITLES or Ranks.ALLIANCE_TITLES
	if not rankPos or not total or total <= 0 then return titles[1] end
	if total == 1 or rankPos == 1 then return titles[14] end
	-- Percentile from bottom (0.0) to top (1.0)
	local pct = (total - rankPos) / math.max(1, total - 1)
	local idx = math.floor(pct * 13 + 0.5) + 1
	idx = math.max(1, math.min(14, idx))
	return titles[idx]
end

local function currentWeekBucket(nowTs)
	return math.floor((nowTs or 0) / Ranks.WEEK_SECONDS)
end

-- Monotonic per-GUID max merge (a lower score never overwrites a higher score)
function Ranks.MergeRecord(rec, nowTs)
	local db = ns.DB and ns.DB()
	if not db or not db.ranks or type(rec) ~= "table" then return false end
	local guid = rec.guid
	if type(guid) ~= "string" or guid == "" then return false end

	nowTs = nowTs or (time and time() or 0)
	local ts = tonumber(rec.ts) or nowTs
	local cur = db.ranks[guid]
	if not cur then
		cur = {
			name = rec.name or "Unknown",
			best = 0,
			bestPPS = 0,
			games = 0,
			weekBest = 0,
			weekBucket = currentWeekBucket(nowTs),
			lastSeen = ts,
			routes = {},
		}
		db.ranks[guid] = cur
	end

	if rec.name and rec.name ~= "" then
		cur.name = rec.name
	end
	if (rec.best or 0) > (cur.best or 0) then
		cur.best = rec.best
	end
	if (rec.bestPPS or 0) > (cur.bestPPS or 0) then
		cur.bestPPS = rec.bestPPS
	end
	if (rec.games or 0) > (cur.games or 0) then
		cur.games = rec.games
	end
	if ts > (cur.lastSeen or 0) then
		cur.lastSeen = ts
	end

	-- Rolling 7-day "This Week" window (no hard wipe of all-time records)
	local curBucket = currentWeekBucket(nowTs)
	if cur.weekBucket ~= curBucket then
		cur.weekBucket = curBucket
		cur.weekBest = 0
	end
	local recAge = nowTs - ts
	if recAge >= -300 and recAge <= Ranks.WEEK_SECONDS then
		local candWeek = rec.weekBest or (rec.isWeekEligible and rec.best) or 0
		if candWeek > (cur.weekBest or 0) then
			cur.weekBest = candWeek
		end
	end

	-- Per-route bests
	if rec.route and rec.route ~= "" then
		if type(cur.routes) ~= "table" then cur.routes = {} end
		local rt = cur.routes[rec.route]
		if not rt then
			rt = { best = 0, pps = 0 }
			cur.routes[rec.route] = rt
		end
		if (rec.routeBest or 0) > rt.best then rt.best = rec.routeBest end
		if (rec.routePPS or 0) > rt.pps then rt.pps = rec.routePPS end
	end

	-- Trigger rank achievements for local player
	if UnitGUID and guid == UnitGUID("player") and ns.Achieve and ns.Achieve.OnRankUpdate then
		local gRank, guildRank = Ranks.GetMyStandings()
		ns.Achieve.OnRankUpdate(gRank, guildRank)
	end

	if Ranks._RefreshIfShown then
		Ranks._RefreshIfShown()
	end
	return true
end

function Ranks.Prune(nowTs, force)
	local db = ns.DB and ns.DB()
	if not db or not db.ranks then return 0 end
	nowTs = nowTs or (time and time() or 0)
	local meta = db.rankMeta or {}
	if not force and meta.lastPrune and (nowTs - meta.lastPrune) < 3600 then
		return 0
	end
	meta.lastPrune = nowTs
	db.rankMeta = meta

	local removed = 0
	local remaining = {}
	for guid, rec in pairs(db.ranks) do
		if (nowTs - (rec.lastSeen or 0)) > Ranks.PRUNE_AGE then
			db.ranks[guid] = nil
			removed = removed + 1
		else
			remaining[#remaining + 1] = { guid = guid, lastSeen = rec.lastSeen or 0 }
		end
	end

	if #remaining > Ranks.MAX_RECORDS then
		table.sort(remaining, function(a, b) return a.lastSeen < b.lastSeen end)
		local excess = #remaining - Ranks.MAX_RECORDS
		for i = 1, excess do
			db.ranks[remaining[i].guid] = nil
			removed = removed + 1
		end
	end
	return removed
end

-- Build guild roster lookup from the receiver's own guild (never trust sender-claimed guild)
local function buildGuildRosterMap()
	local map = {}
	if not (IsInGuild and IsInGuild() and GetNumGuildMembers and GetGuildRosterInfo) then
		return map
	end
	local n = GetNumGuildMembers() or 0
	for i = 1, n do
		local fullName, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, guid = GetGuildRosterInfo(i)
		if guid and guid ~= "" then map[guid] = true end
		if fullName and fullName ~= "" then
			local short = fullName:match("^([^%-]+)") or fullName
			map[short] = true
		end
	end
	return map
end

-- Build sorted rows for any tab: "global" | "pps" | "week" | "guild" | "routes"
function Ranks.BuildView(tab, opts)
	opts = opts or {}
	local db = ns.DB and ns.DB()
	local ranks = db and db.ranks or {}
	local nowTs = opts.nowTs or (time and time() or 0)
	local guildMap = opts.guildRoster or ((tab == "guild") and buildGuildRosterMap() or nil)
	local faction = opts.faction or (UnitFactionGroup and UnitFactionGroup("player")) or "Alliance"
	local routeFilter = opts.route
	local curBucket = currentWeekBucket(nowTs)

	local list = {}
	for guid, rec in pairs(ranks) do
		local include = true
		local val = rec.best or 0

		if tab == "pps" then
			val = rec.bestPPS or 0
			include = val > 0
		elseif tab == "week" then
			val = (rec.weekBucket == curBucket) and (rec.weekBest or 0) or 0
			include = val > 0
		elseif tab == "guild" then
			include = guildMap and (guildMap[guid] or (rec.name and guildMap[rec.name])) or false
			val = rec.best or 0
			include = include and val > 0
		elseif tab == "routes" then
			local rt = routeFilter and rec.routes and rec.routes[routeFilter]
			if rt and (rt.best or 0) > 0 then
				val = rt.pps > 0 and rt.pps or rt.best
			else
				include = false
			end
		else
			include = val > 0
		end

		if include then
			list[#list + 1] = {
				guid = guid,
				name = rec.name or "Unknown",
				score = val,
				best = rec.best or 0,
				bestPPS = rec.bestPPS or 0,
				games = rec.games or 0,
				lastSeen = rec.lastSeen or 0,
			}
		end
	end

	-- Primary true-rank sort descending by metric
	table.sort(list, function(a, b)
		if a.score ~= b.score then return a.score > b.score end
		return a.name < b.name
	end)

	local total = #list
	for i, row in ipairs(list) do
		row.rank = i
		if tab == "guild" then
			row.guildTitle = Ranks.GetGuildRankTitle(i, total, faction)
		end
	end

	-- Optional search filter + secondary column sort (preserves true `#` rank!)
	local search = opts.search and opts.search:lower() or ""
	if search ~= "" then
		local filtered = {}
		for _, row in ipairs(list) do
			if row.name:lower():find(search, 1, true) then
				filtered[#filtered + 1] = row
			end
		end
		list = filtered
	end

	if opts.sortBy == "name" then
		table.sort(list, function(a, b)
			return opts.sortAsc and (a.name < b.name) or (a.name > b.name)
		end)
	elseif opts.sortBy == "games" then
		table.sort(list, function(a, b)
			return opts.sortAsc and (a.games < b.games) or (a.games > b.games)
		end)
	elseif opts.sortBy == "score" and opts.sortAsc then
		table.sort(list, function(a, b) return a.score < b.score end)
	end

	return list, total
end

function Ranks.GetMyStandings()
	local myGuid = UnitGUID and UnitGUID("player")
	if not myGuid then return nil, nil end
	local gList = Ranks.BuildView("global")
	local gRank
	for _, r in ipairs(gList) do
		if r.guid == myGuid then gRank = r.rank; break end
	end
	local guildRank, guildTitle
	if IsInGuild and IsInGuild() then
		local gl = Ranks.BuildView("guild")
		for _, r in ipairs(gl) do
			if r.guid == myGuid then
				guildRank = r.rank
				guildTitle = r.guildTitle
				break
			end
		end
	end
	return gRank, guildRank, guildTitle
end

function Ranks.PrintStandings()
	local gRank, guildRank, guildTitle = Ranks.GetMyStandings()
	local db = ns.DB and ns.DB()
	local best = db and db.best or {}
	local online = ns.Comms and ns.Comms.GetOnlineCount() or 0
	ns.Print(string.format(
		"Your Standings — Global: %s | Guild: %s | Best: %d | Best PPS: %.1f | Online: %d",
		gRank and ("#" .. gRank) or "Unranked",
		guildRank and ("#" .. guildRank .. " (" .. tostring(guildTitle) .. ")") or "N/A",
		best.score or 0,
		best.flightPPS or 0,
		online
	))
end

---------------------------------------------------------------------------
-- Leaderboard Window UI (§6.7) — TacoTip UX in Polestar house anatomy
---------------------------------------------------------------------------
local boardWin = nil
local activeTab = "global"
local activeRoute = nil
local searchText = ""
local sortBy = "score"
local sortAsc = false
local rowWidgets = {}
local tabButtons = {}
local VISIBLE_ROWS = 14
local scrollOffset = 0
local currentRows = {}

local TABS = {
	{ id = "global", label = "Global" },
	{ id = "pps",    label = "Pts/Sec" },
	{ id = "week",   label = "This Week" },
	{ id = "guild",  label = "Guild" },
	{ id = "routes", label = "Routes" },
}

local function formatAge(ts)
	local diff = math.max(0, (time and time() or 0) - (ts or 0))
	if diff < 60 then return "now" end
	if diff < 3600 then return math.floor(diff / 60) .. "m" end
	if diff < 86400 then return math.floor(diff / 3600) .. "h" end
	return math.floor(diff / 86400) .. "d"
end

local function collectAllRoutes()
	local db = ns.DB and ns.DB()
	local seen = {}
	local out = {}
	for _, rec in pairs(db and db.ranks or {}) do
		for rt in pairs(rec.routes or {}) do
			if not seen[rt] then
				seen[rt] = true
				out[#out + 1] = rt
			end
		end
	end
	for rt in pairs(db and db.routes or {}) do
		if not seen[rt] then
			seen[rt] = true
			out[#out + 1] = rt
		end
	end
	table.sort(out)
	return out
end

local function renderRows()
	if not boardWin then return end
	local myGuid = UnitGUID and UnitGUID("player")
	local maxOff = math.max(0, #currentRows - VISIBLE_ROWS)
	if scrollOffset > maxOff then scrollOffset = maxOff end
	if scrollOffset < 0 then scrollOffset = 0 end

	local netOn = ns.Get("network") ~= false
	if #currentRows == 0 then
		boardWin.emptyFS:SetText(
			not netOn
				and "Leaderboard sharing is off — run /jeweled network on to join."
				or "No scores yet — play a game and be the first!"
		)
		boardWin.emptyFS:Show()
	else
		boardWin.emptyFS:Hide()
	end

	for i = 1, VISIBLE_ROWS do
		local w = rowWidgets[i]
		local row = currentRows[scrollOffset + i]
		if row then
			local isMe = (myGuid and row.guid == myGuid)
			local rankColor = "textDim"
			if row.rank == 1 then rankColor = "quest"
			elseif row.rank == 2 then rankColor = "text"
			elseif row.rank == 3 then rankColor = "rare" end

			ns.Theme.ApplyFont(w.rankFS, "number", rankColor)
			w.rankFS:SetText("#" .. tostring(row.rank))

			local label = row.name
			if row.guildTitle then
				label = label .. " |cff9ba2b9(" .. row.guildTitle .. ")|r"
			end
			if isMe then
				label = label .. " |cffe6ba66[YOU]|r"
			end
			ns.Theme.ApplyFont(w.nameFS, "label", isMe and "accent" or "text")
			w.nameFS:SetText(label)

			local metricStr = (activeTab == "pps")
				and string.format("%.1f/s", row.score)
				or tostring(math.floor(row.score))
			ns.Theme.ApplyFont(w.scoreFS, "number", isMe and "accent" or "text")
			w.scoreFS:SetText(metricStr)

			ns.Theme.ApplyFont(w.gamesFS, "small", "textDim")
			w.gamesFS:SetText(tostring(row.games))

			ns.Theme.ApplyFont(w.seenFS, "small", "textMuted")
			w.seenFS:SetText(formatAge(row.lastSeen))

			if isMe then
				local ar, ag, ab = ns.Theme.Accent()
				w._bg:SetColorTexture(ar, ag, ab, 0.24)
			else
				local pr, pg, pb = ns.Theme.Color("panel")
				w._bg:SetColorTexture(pr, pg, pb, (i % 2 == 0) and 0.96 or 0.88)
			end
			w:Show()
		else
			w:Hide()
		end
	end
end

local function refreshBoard(centerOnMe)
	if not boardWin then return end
	if activeTab == "routes" then
		local rts = collectAllRoutes()
		if not activeRoute and rts[1] then activeRoute = rts[1] end
		boardWin.routeBtn:Show()
		boardWin.routeBtn._jwlLabel:SetText("Route: " .. (activeRoute or "None"))
	else
		boardWin.routeBtn:Hide()
	end

	local rows, total = Ranks.BuildView(activeTab, {
		route = activeRoute,
		search = searchText,
		sortBy = sortBy,
		sortAsc = sortAsc,
	})
	currentRows = rows

	local online = ns.Comms and ns.Comms.GetOnlineCount() or 0
	local gRank, guildRank = Ranks.GetMyStandings()
	boardWin.statusFS:SetText(string.format(
		"%d players jeweled right now  ·  %d ranked  ·  You: %s global%s",
		online, total,
		gRank and ("#" .. gRank) or "—",
		guildRank and (" · #" .. guildRank .. " guild") or ""
	))

	for _, tb in ipairs(tabButtons) do
		ns.Theme.PaintButton(tb, tb._tabId == activeTab)
	end

	if centerOnMe then
		local myGuid = UnitGUID and UnitGUID("player")
		for idx, r in ipairs(currentRows) do
			if myGuid and r.guid == myGuid then
				scrollOffset = math.max(0, idx - math.floor(VISIBLE_ROWS / 2))
				break
			end
		end
	end

	renderRows()
end

function Ranks._RefreshIfShown()
	if boardWin and boardWin:IsShown() then
		refreshBoard(false)
	end
end

local function createBoardWindow()
	local f = CreateFrame("Frame", "JeweledLeaderboardFrame", UIParent)
	f:SetSize(560, 490)
	f:SetPoint("CENTER")
	f:SetFrameStrata("DIALOG")
	f:SetMovable(true)
	f:EnableMouse(true)
	f:RegisterForDrag("LeftButton")
	f:SetScript("OnDragStart", f.StartMoving)
	f:SetScript("OnDragStop", f.StopMovingOrSizing)
	f:SetClampedToScreen(true)
	f:EnableMouseWheel(true)
	f:SetScript("OnMouseWheel", function(_, delta)
		scrollOffset = scrollOffset - delta * 3
		renderRows()
	end)
	f:Hide()
	if UISpecialFrames then
		table.insert(UISpecialFrames, "JeweledLeaderboardFrame")
	end

	local title = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
	title:SetPoint("TOPLEFT", 14, -12)
	title:SetText("Jeweled — Leaderboard")
	f.title = title

	local close = ns.Theme.CreateButton(f, "X", 24, 22, function() f:Hide() end, false)
	close:SetPoint("TOPRIGHT", -8, -8)
	f.close = close

	local syncBtn = ns.Theme.CreateButton(f, "Sync now", 76, 22, function()
		if ns.Comms then
			ns.Comms.SendBeacon(true)
			ns.Comms.SendQuery(true)
		end
		refreshBoard(false)
	end, false)
	syncBtn:SetPoint("RIGHT", close, "LEFT", -6, 0)
	f.syncBtn = syncBtn

	local statusFS = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
	statusFS:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -4)
	f.statusFS = statusFS

	-- Tabs
	for i, t in ipairs(TABS) do
		local tb = ns.Theme.CreateButton(f, t.label, 96, 24, function()
			activeTab = t.id
			scrollOffset = 0
			refreshBoard(true)
		end, t.id == activeTab)
		tb._tabId = t.id
		tb:SetPoint("TOPLEFT", f, "TOPLEFT", 14 + (i - 1) * 102, -52)
		tabButtons[i] = tb
	end

	-- Search box + Top / My Rank navigation + Route cycler
	local searchBox = CreateFrame("EditBox", nil, f, "InputBoxTemplate")
	searchBox:SetSize(160, 22)
	searchBox:SetPoint("TOPLEFT", f, "TOPLEFT", 18, -84)
	searchBox:SetAutoFocus(false)
	searchBox:SetScript("OnTextChanged", function(self)
		searchText = self:GetText() or ""
		scrollOffset = 0
		refreshBoard(false)
	end)
	searchBox:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)

	local topBtn = ns.Theme.CreateButton(f, "Top", 54, 22, function()
		scrollOffset = 0
		renderRows()
	end, false)
	topBtn:SetPoint("LEFT", searchBox, "RIGHT", 10, 0)

	local meBtn = ns.Theme.CreateButton(f, "My Rank", 72, 22, function()
		refreshBoard(true)
	end, false)
	meBtn:SetPoint("LEFT", topBtn, "RIGHT", 6, 0)

	local routeBtn = ns.Theme.CreateButton(f, "Route: None", 210, 22, function()
		local rts = collectAllRoutes()
		if #rts == 0 then return end
		local idx = 1
		for i, rt in ipairs(rts) do
			if rt == activeRoute then idx = i; break end
		end
		activeRoute = rts[(idx % #rts) + 1]
		refreshBoard(false)
	end, false)
	routeBtn:SetPoint("LEFT", meBtn, "RIGHT", 8, 0)
	routeBtn:Hide()
	f.routeBtn = routeBtn

	-- Column headers (sortable, true `#` preserved)
	local colY = -114
	local function makeColBtn(text, x, w, key)
		local b = CreateFrame("Button", nil, f)
		b:SetSize(w, 18)
		b:SetPoint("TOPLEFT", f, "TOPLEFT", x, colY)
		local fs = b:CreateFontString(nil, "OVERLAY", "GameFontNormal")
		fs:SetAllPoints(b)
		fs:SetJustifyH(key == "name" and "LEFT" or "RIGHT")
		fs:SetText(text)
		ns.Theme.ApplyFont(fs, "caption", "textMuted")
		if key then
			b:SetScript("OnClick", function()
				if sortBy == key then sortAsc = not sortAsc else sortBy = key; sortAsc = false end
				refreshBoard(false)
			end)
		end
	end
	makeColBtn("#", 14, 38, nil)
	makeColBtn("Player", 60, 250, "name")
	makeColBtn("Score / PPS", 316, 100, "score")
	makeColBtn("Games", 422, 56, "games")
	makeColBtn("Seen", 484, 54, nil)

	-- Pooled visible rows
	for i = 1, VISIBLE_ROWS do
		local row = CreateFrame("Frame", nil, f)
		row:SetSize(532, 22)
		row:SetPoint("TOPLEFT", f, "TOPLEFT", 14, colY - 22 - (i - 1) * 23)
		row._bg = row:CreateTexture(nil, "BACKGROUND")
		row._bg:SetAllPoints(row)

		row.rankFS = row:CreateFontString(nil, "OVERLAY", "GameFontNormal")
		row.rankFS:SetPoint("LEFT", row, "LEFT", 4, 0)
		row.rankFS:SetWidth(38)
		row.rankFS:SetJustifyH("RIGHT")

		row.nameFS = row:CreateFontString(nil, "OVERLAY", "GameFontNormal")
		row.nameFS:SetPoint("LEFT", row, "LEFT", 48, 0)
		row.nameFS:SetWidth(252)
		row.nameFS:SetJustifyH("LEFT")

		row.scoreFS = row:CreateFontString(nil, "OVERLAY", "GameFontNormal")
		row.scoreFS:SetPoint("LEFT", row, "LEFT", 304, 0)
		row.scoreFS:SetWidth(100)
		row.scoreFS:SetJustifyH("RIGHT")

		row.gamesFS = row:CreateFontString(nil, "OVERLAY", "GameFontNormal")
		row.gamesFS:SetPoint("LEFT", row, "LEFT", 410, 0)
		row.gamesFS:SetWidth(56)
		row.gamesFS:SetJustifyH("RIGHT")

		row.seenFS = row:CreateFontString(nil, "OVERLAY", "GameFontNormal")
		row.seenFS:SetPoint("LEFT", row, "LEFT", 472, 0)
		row.seenFS:SetWidth(54)
		row.seenFS:SetJustifyH("RIGHT")

		rowWidgets[i] = row
	end

	local emptyFS = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
	emptyFS:SetPoint("CENTER", f, "CENTER", 0, -20)
	f.emptyFS = emptyFS

	-- Honesty footer (§6.7)
	local footerFS = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
	footerFS:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", 14, 10)
	footerFS:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -14, 10)
	footerFS:SetJustifyH("CENTER")
	footerFS:SetText("Realm-wide, from players your game has heard from. Scores are shared by players, not verified by a server.")
	f.footerFS = footerFS

	local function paint()
		ns.Theme.PaintWindow(f, true)
		ns.Theme.ApplyFont(f.title, "title", "accent")
		ns.Theme.ApplyFont(f.statusFS, "small", "textDim")
		ns.Theme.ApplyFont(f.emptyFS, "body", "textMuted")
		ns.Theme.ApplyFont(f.footerFS, "small", "textMuted")
		ns.Theme.PaintButton(f.close, false)
		ns.Theme.PaintButton(f.syncBtn, false)
		ns.Theme.PaintButton(topBtn, false)
		ns.Theme.PaintButton(meBtn, false)
		ns.Theme.PaintButton(f.routeBtn, false)
		refreshBoard(false)
	end

	ns.Theme.RegisterRepaint(paint)
	f:SetScript("OnShow", function()
		Ranks.Prune(nil, false)
		if ns.Comms then ns.Comms.SendBeacon(false) end
		paint()
		refreshBoard(true)
	end)
	paint()
	boardWin = f
end

function Ranks.Toggle()
	if not boardWin then createBoardWindow() end
	if boardWin:IsShown() then
		boardWin:Hide()
	else
		boardWin:Show()
	end
end

if ns.On then
	ns.On("LOGIN", function()
		Ranks.Prune(nil, true)
	end)
end

return Ranks
