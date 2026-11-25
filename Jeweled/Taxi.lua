-- Taxi.lua: Flight detection, first-run opt-in prompt, auto-open/auto-close,
-- combat-safe pause/hide, self-learned flight times, landing countdown, PPS
-- route scorebook, beat-the-landing streaks, and opt-in auto-open on death.

local _, ns = ...

local Taxi = {}
ns.Taxi = Taxi

local slots = {}          -- taxi slot index -> node name
local currentNode = nil   -- origin node name captured on TAXIMAP_OPENED
local pendingRoute = nil  -- { from, to, routeKey, takenAt }
local activeFlight = nil  -- { routeKey, from, to, startTime, startScore, startMoves, knownDur }
local askedThisLogin = false
local wasOnTaxi = false

local function onTaxi()
	return UnitOnTaxi and UnitOnTaxi("player") and true or false
end

local function shortNodeName(name)
	if type(name) ~= "string" then return nil end
	-- Strip ", Zone" suffix if very long, keeping readable route name
	local short = name:match("^([^,]+)") or name
	return short:match("^%s*(.-)%s*$")
end

local function formatTime(sec)
	sec = math.max(0, math.floor(sec + 0.5))
	local m = math.floor(sec / 60)
	local s = sec % 60
	return string.format("%d:%02d", m, s)
end

function Taxi.IsFlying()
	return activeFlight ~= nil or onTaxi()
end

function Taxi.GetActiveFlight()
	return activeFlight
end

-- Honest HUD string: real countdown if route duration is learned, count-up otherwise
function Taxi.GetFlightHudText()
	if not activeFlight then return nil end
	local elapsed = (GetTime and GetTime() or 0) - activeFlight.startTime
	if activeFlight.knownDur and activeFlight.knownDur > 0 then
		local rem = math.max(0, activeFlight.knownDur - elapsed)
		return "Landing: " .. formatTime(rem)
	end
	return "Flight: " .. formatTime(elapsed)
end

local function countRoutesWithBest(db)
	local n = 0
	for _, r in pairs(db.routes or {}) do
		if type(r) == "table" and (r.best or 0) > 0 then
			n = n + 1
		end
	end
	return n
end

-- First-run opt-in dialog (§6.1): asks once on first taxi takeoff when db.autoOpen == nil
if StaticPopupDialogs then
	StaticPopupDialogs["JEWELED_FLIGHT_OPTIN"] = {
		text = "Play Jeweled on flight paths?\n\nJeweled can open automatically when you take a flight, and close when you land. You can change this anytime in settings or with /jeweled auto.\n\nJeweled also shares your best scores with other players on the leaderboard network — turn that off anytime with /jeweled network off.",
		button1 = "Yes",
		button2 = "No",
		button3 = "Ask me later",
		OnAccept = function()
			ns.Set("autoOpen", true)
			if onTaxi() and ns.UI and not ns.UI.IsShown() then
				ns.UI.Show(true)
				if ns.FX then ns.FX.Banner("Go!", "accent", 0.75) end
				if ns.Sound then ns.Sound.Play("go") end
			end
		end,
		OnCancel = function(_, _, reason)
			-- Clicking "No" stores false; pressing Esc leaves nil (Ask me later)
			if reason == "clicked" then
				ns.Set("autoOpen", false)
			end
		end,
		OnAlt = function()
			-- Ask me later: leave db.autoOpen == nil (do not nag again this login)
		end,
		timeout = 0,
		whileDead = true,
		hideOnEscape = true,
	}
end

local function onTakeoff()
	if activeFlight then return end
	local now = GetTime and GetTime() or 0
	local db = ns.DB()

	local routeKey = pendingRoute and pendingRoute.routeKey or nil
	local fromName = pendingRoute and pendingRoute.from or nil
	local toName = pendingRoute and pendingRoute.to or nil
	pendingRoute = nil

	local knownDur = (routeKey and db and db.flightTimes) and db.flightTimes[routeKey] or nil
	local g = ns.UI and ns.UI.GetGame and ns.UI.GetGame()
	local startScore = g and g.score or 0
	local startMoves = g and g.moves or 0

	activeFlight = {
		routeKey = routeKey,
		from = fromName,
		to = toName,
		startTime = now,
		startScore = startScore,
		startMoves = startMoves,
		knownDur = knownDur,
	}

	if db and db.best then
		db.best.flights = (db.best.flights or 0) + 1
	end

	-- Handle auto-open / first-run opt-in
	if ns.UI and not ns.UI.IsShown() then
		local pref = db and db.autoOpen
		if pref == nil then
			if not askedThisLogin and StaticPopup_Show then
				askedThisLogin = true
				pcall(StaticPopup_Show, "JEWELED_FLIGHT_OPTIN")
			end
		elseif pref == true then
			ns.UI.Show(true)
			if ns.FX then ns.FX.Banner("Go!", "accent", 0.75) end
			if ns.Sound then ns.Sound.Play("go") end
		end
	elseif ns.UI and ns.UI.IsShown() then
		ns.UI.RefreshFlightHudTicker()
		ns.UI.UpdateScoreStrip()
	end
end

local function onLanding()
	local fl = activeFlight
	activeFlight = nil
	if not fl then return end

	local now = GetTime and GetTime() or 0
	local duration = math.max(1, now - fl.startTime)
	local db = ns.DB()

	-- Self-learn flight time (exponential moving average if seen before)
	if fl.routeKey and db and db.flightTimes and duration >= 5 and duration <= 1800 then
		local prev = db.flightTimes[fl.routeKey]
		if prev then
			db.flightTimes[fl.routeKey] = math.floor((prev * 0.7 + duration * 0.3) + 0.5)
		else
			db.flightTimes[fl.routeKey] = math.floor(duration + 0.5)
		end
	end

	-- Compute flight score & points-per-second (PPS)
	local g = ns.UI and ns.UI.GetGame and ns.UI.GetGame()
	local flightScore = 0
	local flightMoves = 0
	if g then
		flightScore = math.max(0, (g.score or 0) - fl.startScore)
		flightMoves = math.max(0, (g.moves or 0) - fl.startMoves)
		ns.State.SaveGame(g)
	end

	local pps = flightScore > 0 and (flightScore / duration) or 0
	local isNewRouteBest = false
	local isNewOverallBest = false

	if flightScore > 0 and db then
		local newAccScore, newAccPPS = ns.State.RecordBest(g and g.score or flightScore, pps)
		isNewOverallBest = newAccScore or newAccPPS

		if fl.routeKey then
			local rt = db.routes[fl.routeKey]
			if not rt then
				rt = { best = 0, bestPPS = 0, flights = 0 }
				db.routes[fl.routeKey] = rt
			end
			rt.flights = (rt.flights or 0) + 1
			if flightScore > (rt.best or 0) then
				rt.best = flightScore
				isNewRouteBest = true
			end
			if pps > (rt.bestPPS or 0) then
				rt.bestPPS = math.floor(pps * 10 + 0.5) / 10
				isNewRouteBest = true
			end
		end

		-- Beat-the-landing streak
		if isNewRouteBest or isNewOverallBest then
			db.best.streak = (db.best.streak or 0) + 1
			if db.best.streak > (db.best.bestStreak or 0) then
				db.best.bestStreak = db.best.streak
			end
		else
			db.best.streak = 0
		end

		-- Broadcast improvement to leaderboard network
		if (isNewRouteBest or isNewOverallBest) and ns.Comms and ns.Comms.BroadcastScore then
			ns.Comms.BroadcastScore(g and g.score or flightScore, pps, "flight", fl.routeKey, flightMoves, duration)
		end
	end

	if ns.Achieve and ns.Achieve.OnFlightLand then
		ns.Achieve.OnFlightLand(db, countRoutesWithBest(db))
	end

	if ns.UI and ns.UI.IsShown() then
		ns.UI.UpdateScoreStrip()
		if flightScore > 0 then
			local lines = {
				"|cffe6ba66Flight Landed!|r",
				fl.routeKey and (fl.routeKey .. " (" .. formatTime(duration) .. ")") or ("Flight time: " .. formatTime(duration)),
				string.format("Flight Score: |cffffffff%d|r   |cffe6ba66%.1f pts/sec|r", flightScore, pps),
			}
			if isNewRouteBest or isNewOverallBest then
				lines[#lines + 1] = string.format("|cff6bd999New Best!|r  Streak: %d", db and db.best and db.best.streak or 1)
			end
			ns.UI.ShowLandingCard(table.concat(lines, "\n"), 5.0)
		elseif ns.UI.OpenedByFlight() and ns.Get("autoClose") ~= false then
			ns.UI.SetOpenedByFlight(false)
			ns.UI.Hide()
		end
	end
end

local function checkTaxiState()
	local flying = onTaxi()
	if flying and not wasOnTaxi then
		wasOnTaxi = true
		onTakeoff()
	elseif not flying and wasOnTaxi then
		wasOnTaxi = false
		onLanding()
	end
end

-- Capture taxi map nodes and TakeTaxiNode destination
ns.RegisterEvent("TAXIMAP_OPENED", function()
	slots = {}
	currentNode = nil
	if NumTaxiNodes and TaxiNodeGetType and TaxiNodeName then
		local count = NumTaxiNodes() or 0
		for i = 1, count do
			local name = shortNodeName(TaxiNodeName(i))
			if name then
				slots[i] = name
				if TaxiNodeGetType(i) == "CURRENT" then
					currentNode = name
				end
			end
		end
	end
end)

if TakeTaxiNode and hooksecurefunc then
	hooksecurefunc("TakeTaxiNode", function(slot)
		local dest = slots[slot] or (TaxiNodeName and shortNodeName(TaxiNodeName(slot)))
		if dest then
			local from = currentNode or (GetSubZoneText and shortNodeName(GetSubZoneText())) or (GetZoneText and shortNodeName(GetZoneText())) or "Origin"
			pendingRoute = {
				from = from,
				to = dest,
				routeKey = from .. "->" .. dest,
				takenAt = GetTime and GetTime() or 0,
			}
		end
	end)
end

ns.RegisterEvent("PLAYER_CONTROL_LOST", function()
	-- Slight defer allows UnitOnTaxi("player") to settle cleanly on takeoff
	if C_Timer and C_Timer.After then
		C_Timer.After(0.15, ns.Safe(checkTaxiState))
	else
		checkTaxiState()
	end
end)

ns.RegisterEvent("PLAYER_CONTROL_GAINED", function()
	if C_Timer and C_Timer.After then
		C_Timer.After(0.15, ns.Safe(checkTaxiState))
	else
		checkTaxiState()
	end
end)

ns.RegisterEvent("PLAYER_ENTERING_WORLD", function()
	wasOnTaxi = onTaxi()
end)

-- Combat safety (non-negotiable): immediately pause & hide on entering combat
ns.RegisterEvent("PLAYER_REGEN_DISABLED", function()
	if ns.UI and ns.UI.IsShown() then
		ns.UI.FastSettleAndPause()
		ns.UI.Hide()
	end
end)

-- Opt-in auto-open on death (Phase 7, strictly OFF by default)
ns.RegisterEvent("PLAYER_DEAD", function()
	if ns.Get("autoOpenOnDeath") == true and ns.UI and not ns.UI.IsShown() then
		if not (InCombatLockdown and InCombatLockdown()) then
			ns.UI.Show(false)
		end
	end
end)

function Taxi.PrintRouteScores()
	local db = ns.DB()
	local routes = db and db.routes
	if not routes or not next(routes) then
		ns.Print("No flight route scores recorded yet — play on a flight path to start your scorebook!")
		return
	end
	local list = {}
	for route, info in pairs(routes) do
		list[#list + 1] = { route = route, best = info.best or 0, pps = info.bestPPS or 0, flights = info.flights or 0 }
	end
	table.sort(list, function(a, b) return a.pps > b.pps end)
	ns.Print("Route Scorebook (top 10 by pts/sec):")
	for i = 1, math.min(10, #list) do
		local r = list[i]
		ns.Print(string.format("  %d. %s — Best: %d  |  %.1f pts/sec  (%d flights)", i, r.route, r.best, r.pps, r.flights))
	end
end
