-- Core.lua: Addon namespace, SavedVariables init/migration, nil-culling defaults,
-- Safe() call wrapper, and event dispatch bus for Jeweled (WoW Forever 1.60.1).

local ADDON, ns = ...
ns.ADDON = ADDON
ns.VERSION = "1.0.0"
ns.SCHEMA_VERSION = 1

local DEFAULTS = {
	autoOpen = nil,           -- nil = never asked; true/false = stored answer
	autoClose = true,
	sound = true,
	fx = "full",              -- "full" | "reduced"
	shake = true,
	minimapHidden = false,
	minimapPos = 220,
	network = true,
	autoOpenOnDeath = false,
	windowScale = "medium",   -- "small" | "medium" | "large"
	gemSet = "azeroth",
	background = "nightsky",
	showFps = false,
}
ns.DEFAULTS = DEFAULTS

local function getErrorHandler()
	return geterrorhandler and geterrorhandler() or nil
end

function ns.Safe(fn)
	if type(fn) ~= "function" then return fn end
	return function(...)
		local ok, err = pcall(fn, ...)
		if not ok then
			local eh = getErrorHandler()
			if eh then eh(err) end
		end
	end
end

function ns.Print(msg)
	if DEFAULT_CHAT_FRAME and DEFAULT_CHAT_FRAME.AddMessage then
		DEFAULT_CHAT_FRAME:AddMessage("|cffe6ba66Jeweled:|r " .. tostring(msg))
	elseif print then
		print("Jeweled: " .. tostring(msg))
	end
end

-- Simple internal pub/sub bus
local listeners = {}

function ns.On(event, fn)
	if type(fn) ~= "function" then return end
	local list = listeners[event]
	if not list then
		list = {}
		listeners[event] = list
	end
	list[#list + 1] = fn
end

function ns.Fire(event, ...)
	local list = listeners[event]
	if not list then return end
	for i = 1, #list do
		local ok, err = pcall(list[i], ...)
		if not ok then
			local eh = getErrorHandler()
			if eh then eh(err) end
		end
	end
end

-- SavedVariables access with Polestar-style nil-culling for default values
function ns.DB()
	return JeweledDB
end

function ns.CharDB()
	return JeweledCharDB
end

function ns.Get(key)
	local db = JeweledDB
	if db and db[key] ~= nil then
		return db[key]
	end
	return DEFAULTS[key]
end

function ns.Set(key, val)
	local db = JeweledDB
	if not db then return end
	if val == DEFAULTS[key] then
		db[key] = nil
	else
		db[key] = val
	end
	ns.Fire("SETTING_CHANGED", key, ns.Get(key))
end

local function ensureTable(parent, key)
	if type(parent[key]) ~= "table" then
		parent[key] = {}
	end
	return parent[key]
end

local function initDB()
	if type(JeweledDB) ~= "table" then
		JeweledDB = {}
	end
	local db = JeweledDB
	if type(db.version) ~= "number" then
		db.version = ns.SCHEMA_VERSION
	end
	local unlocked = ensureTable(db, "unlocked")
	local uSets = ensureTable(unlocked, "gemSets")
	uSets.azeroth = true
	local uBgs = ensureTable(unlocked, "backgrounds")
	uBgs.nightsky = true
	uBgs.deepmine = true
	uBgs.arcanevault = true

	ensureTable(db, "achievements")
	local best = ensureTable(db, "best")
	best.score = tonumber(best.score) or 0
	best.flightPPS = tonumber(best.flightPPS) or 0
	best.streak = tonumber(best.streak) or 0
	best.bestStreak = tonumber(best.bestStreak) or 0
	best.flights = tonumber(best.flights) or 0
	best.games = tonumber(best.games) or 0

	ensureTable(db, "routes")
	ensureTable(db, "flightTimes")
	ensureTable(db, "ranks")
	local meta = ensureTable(db, "rankMeta")
	meta.lastPrune = tonumber(meta.lastPrune) or 0

	if type(JeweledCharDB) ~= "table" then
		JeweledCharDB = {}
	end
	local cBest = ensureTable(JeweledCharDB, "best")
	cBest.score = tonumber(cBest.score) or 0
	cBest.flightPPS = tonumber(cBest.flightPPS) or 0
end

-- WoW event frame
local eventHandlers = {}
local eventFrame = CreateFrame and CreateFrame("Frame") or nil

function ns.RegisterEvent(event, fn)
	local list = eventHandlers[event]
	if not list then
		list = {}
		eventHandlers[event] = list
		if eventFrame then
			pcall(eventFrame.RegisterEvent, eventFrame, event)
		end
	end
	list[#list + 1] = fn
end

function ns.UnregisterEvent(event, fn)
	local list = eventHandlers[event]
	if not list then return end
	for i = #list, 1, -1 do
		if list[i] == fn then
			table.remove(list, i)
		end
	end
	if #list == 0 and eventFrame then
		eventHandlers[event] = nil
		pcall(eventFrame.UnregisterEvent, eventFrame, event)
	end
end

if eventFrame then
	eventFrame:SetScript("OnEvent", function(_, event, ...)
		local list = eventHandlers[event]
		if not list then return end
		for i = 1, #list do
			local ok, err = pcall(list[i], event, ...)
			if not ok then
				local eh = getErrorHandler()
				if eh then eh(err) end
			end
		end
	end)
end

ns.RegisterEvent("ADDON_LOADED", function(_, loadedName)
	if loadedName ~= ADDON then return end
	initDB()
	ns.Fire("INIT", JeweledDB, JeweledCharDB)
end)

ns.RegisterEvent("PLAYER_LOGIN", function()
	ns.Fire("LOGIN", JeweledDB, JeweledCharDB)
end)

ns.RegisterEvent("PLAYER_LOGOUT", function()
	ns.Fire("LOGOUT", JeweledDB, JeweledCharDB)
end)

-- Global addon compartment hook (TOC ## AddonCompartmentFunc)
function Jeweled_OnAddonCompartmentClick()
	if ns.UI and ns.UI.Toggle then
		ns.UI.Toggle()
	elseif ns.Slash and ns.Slash.Handle then
		ns.Slash.Handle("")
	end
end
