-- State.lua: Compact SavedVariables serialization & persistence for Jeweled.
-- Encodes an 8x8 board into two 64-character strings (types + specials).

local _, ns = ...
if type(ns) ~= "table" then ns = {} end

local State = {}
ns.State = State

local ROWS = 8
local COLS = 8
local VALID_SPECIAL = { H = true, V = true, B = true, P = true }

function State.EncodeGrid(grid)
	local tChars = {}
	local sChars = {}
	local idx = 1
	for r = 1, ROWS do
		local row = grid[r]
		for c = 1, COLS do
			local cell = row and row[c]
			local t = cell and tonumber(cell.t) or 1
			if t < 0 or t > 6 then t = 1 end
			local s = cell and cell.s
			if s == "P" then t = 0 end
			tChars[idx] = tostring(t)
			sChars[idx] = (s and VALID_SPECIAL[s]) and s or "."
			idx = idx + 1
		end
	end
	return table.concat(tChars), table.concat(sChars)
end

function State.DecodeGrid(boardStr, specialStr)
	if type(boardStr) ~= "string" or #boardStr ~= ROWS * COLS then
		return nil, "invalid board length"
	end
	if specialStr ~= nil and (type(specialStr) ~= "string" or #specialStr ~= ROWS * COLS) then
		return nil, "invalid specials length"
	end

	local grid = {}
	local idx = 1
	for r = 1, ROWS do
		grid[r] = {}
		for c = 1, COLS do
			local ch = boardStr:sub(idx, idx)
			local t = tonumber(ch)
			if not t or t < 0 or t > 6 then
				return nil, "invalid gem code at " .. idx
			end
			local s = nil
			if specialStr then
				local sch = specialStr:sub(idx, idx)
				if VALID_SPECIAL[sch] then
					s = sch
				elseif sch ~= "." then
					return nil, "invalid special code at " .. idx
				end
			end
			if t == 0 and s ~= "P" then
				return nil, "colorless non-prismatic cell at " .. idx
			end
			grid[r][c] = { t = t, s = s }
			idx = idx + 1
		end
	end
	return grid, nil
end

function State.SaveGame(gameState, nowFn)
	local db = ns.DB and ns.DB()
	if not db then return false end
	if not gameState or not gameState.grid then
		db.game = nil
		return true
	end
	local boardStr, specialStr = State.EncodeGrid(gameState.grid)
	local now = nowFn and nowFn() or (time and time() or 0)
	db.game = {
		board = boardStr,
		specials = specialStr,
		score = tonumber(gameState.score) or 0,
		moves = tonumber(gameState.moves) or 0,
		mode = gameState.mode or "classic",
		savedAt = now,
	}
	return true
end

function State.LoadGame()
	local db = ns.DB and ns.DB()
	local saved = db and db.game
	if type(saved) ~= "table" then return nil end
	local grid, err = State.DecodeGrid(saved.board, saved.specials)
	if not grid then
		return nil, err
	end
	return {
		grid = grid,
		score = tonumber(saved.score) or 0,
		moves = tonumber(saved.moves) or 0,
		cascade = 0,
		mode = saved.mode or "classic",
		savedAt = tonumber(saved.savedAt) or 0,
	}
end

function State.ClearGame()
	local db = ns.DB and ns.DB()
	if db then db.game = nil end
end

function State.RecordBest(score, pps)
	local db = ns.DB and ns.DB()
	local cdb = ns.CharDB and ns.CharDB()
	local newAccScore, newAccPPS = false, false

	if db and db.best then
		if score and score > (db.best.score or 0) then
			db.best.score = score
			newAccScore = true
		end
		if pps and pps > (db.best.flightPPS or 0) then
			db.best.flightPPS = pps
			newAccPPS = true
		end
	end
	if cdb and cdb.best then
		if score and score > (cdb.best.score or 0) then
			cdb.best.score = score
		end
		if pps and pps > (cdb.best.flightPPS or 0) then
			cdb.best.flightPPS = pps
		end
	end
	return newAccScore, newAccPPS
end

if ns.On then
	ns.On("LOGOUT", function()
		if ns.currentGame then
			State.SaveGame(ns.currentGame)
		end
	end)
end

return State
