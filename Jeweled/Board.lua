-- Board.lua: Pure Lua 5.1 match-3 game logic for Jeweled.
-- ZERO WoW API calls — unit-testable offline under plain Lua 5.1 / LuaJIT.

local _, ns = ...
if type(ns) ~= "table" then ns = {} end

local Board = {}
ns.Board = Board

Board.ROWS = 8
Board.COLS = 8
Board.NUM_TYPES = 6

-- Special gem codes
Board.SPECIAL_NONE  = nil
Board.SPECIAL_LINEH = "H" -- 4-in-a-row horizontal -> clears entire row
Board.SPECIAL_LINEV = "V" -- 4-in-a-row vertical   -> clears entire column
Board.SPECIAL_BLAST = "B" -- L/T intersection      -> clears 3x3 area
Board.SPECIAL_PRISM = "P" -- 5-in-a-row            -> clears all of swapped color

-- Scoring constants (also referenced by Comms.lua anti-cheat plausibility checks)
Board.SCORE = {
	BASE_GEM = 50,
	MATCH4_BONUS = 100,
	BLAST_CREATE_BONUS = 150,
	MATCH5_BONUS = 250,
	SPECIAL_TRIGGER_BONUS = 150,
	MAX_MULTIPLIER = 10,
	-- Anti-cheat plausibility bounds
	MAX_SCORE = 1000000,
	MAX_PPS = 500,
	MAX_POINTS_PER_MOVE = 25000,
}

local ROWS, COLS, NUM_TYPES = Board.ROWS, Board.COLS, Board.NUM_TYPES

local function defaultRng(n)
	return math.random(1, n)
end

local function cellKey(r, c)
	return (r - 1) * COLS + c
end

local function keyToRC(k)
	local r = math.floor((k - 1) / COLS) + 1
	local c = ((k - 1) % COLS) + 1
	return r, c
end

local function makeCell(t, s)
	return { t = t, s = s }
end

function Board.CloneGrid(grid)
	local copy = {}
	for r = 1, ROWS do
		copy[r] = {}
		for c = 1, COLS do
			local cell = grid[r][c]
			if cell then
				copy[r][c] = { t = cell.t, s = cell.s }
			end
		end
	end
	return copy
end

-- Check whether placing gem type `t` at (r, c) creates an immediate 3-match
local function createsImmediateMatch(grid, r, c, t)
	if t == 0 then return false end
	if c >= 3 and grid[r][c - 1] and grid[r][c - 2]
		and grid[r][c - 1].t == t and grid[r][c - 2].t == t then
		return true
	end
	if r >= 3 and grid[r - 1][c] and grid[r - 2][c]
		and grid[r - 1][c].t == t and grid[r - 2][c].t == t then
		return true
	end
	return false
end

-- Scan grid for all 3+ horizontal and vertical runs, merging intersecting same-color runs
function Board.FindMatches(grid)
	local hRuns = {}
	local vRuns = {}

	-- Horizontal runs
	for r = 1, ROWS do
		local c = 1
		while c <= COLS do
			local cell = grid[r][c]
			local t = cell and cell.t or 0
			if t > 0 then
				local c2 = c + 1
				while c2 <= COLS and grid[r][c2] and grid[r][c2].t == t do
					c2 = c2 + 1
				end
				local len = c2 - c
				if len >= 3 then
					local cells = {}
					for cc = c, c2 - 1 do
						cells[#cells + 1] = { r = r, c = cc }
					end
					hRuns[#hRuns + 1] = { dir = "H", t = t, len = len, cells = cells }
				end
				c = c2
			else
				c = c + 1
			end
		end
	end

	-- Vertical runs
	for c = 1, COLS do
		local r = 1
		while r <= ROWS do
			local cell = grid[r][c]
			local t = cell and cell.t or 0
			if t > 0 then
				local r2 = r + 1
				while r2 <= ROWS and grid[r2][c] and grid[r2][c].t == t do
					r2 = r2 + 1
				end
				local len = r2 - r
				if len >= 3 then
					local cells = {}
					for rr = r, r2 - 1 do
						cells[#cells + 1] = { r = rr, c = c }
					end
					vRuns[#vRuns + 1] = { dir = "V", t = t, len = len, cells = cells }
				end
				r = r2
			else
				r = r + 1
			end
		end
	end

	local allRuns = {}
	for i = 1, #hRuns do allRuns[#allRuns + 1] = hRuns[i] end
	for i = 1, #vRuns do allRuns[#allRuns + 1] = vRuns[i] end
	if #allRuns == 0 then return {} end

	-- Build cell -> run indices adjacency to merge intersecting runs of same color
	local cellToRuns = {}
	for idx, run in ipairs(allRuns) do
		for _, pos in ipairs(run.cells) do
			local k = cellKey(pos.r, pos.c)
			local list = cellToRuns[k]
			if not list then
				list = {}
				cellToRuns[k] = list
			end
			list[#list + 1] = idx
		end
	end

	local visited = {}
	local groups = {}

	for idx = 1, #allRuns do
		if not visited[idx] then
			local queue = { idx }
			visited[idx] = true
			local head = 1
			local groupRuns = {}
			local groupColor = allRuns[idx].t
			local cellSet = {}
			local cellList = {}
			local intersections = {}
			local maxH, maxV = 0, 0

			while head <= #queue do
				local cur = queue[head]
				head = head + 1
				local run = allRuns[cur]
				groupRuns[#groupRuns + 1] = run
				if run.dir == "H" and run.len > maxH then maxH = run.len end
				if run.dir == "V" and run.len > maxV then maxV = run.len end

				for _, pos in ipairs(run.cells) do
					local k = cellKey(pos.r, pos.c)
					if not cellSet[k] then
						cellSet[k] = true
						cellList[#cellList + 1] = { r = pos.r, c = pos.c }
					end
					local neighbors = cellToRuns[k]
					if #neighbors > 1 then
						intersections[k] = { r = pos.r, c = pos.c }
					end
					for _, nIdx in ipairs(neighbors) do
						if not visited[nIdx] and allRuns[nIdx].t == groupColor then
							visited[nIdx] = true
							queue[#queue + 1] = nIdx
						end
					end
				end
			end

			local special = nil
			if maxH >= 5 or maxV >= 5 then
				special = Board.SPECIAL_PRISM
			elseif maxH >= 3 and maxV >= 3 then
				special = Board.SPECIAL_BLAST
			elseif maxH == 4 then
				special = Board.SPECIAL_LINEH
			elseif maxV == 4 then
				special = Board.SPECIAL_LINEV
			end

			groups[#groups + 1] = {
				t = groupColor,
				cells = cellList,
				cellSet = cellSet,
				intersections = intersections,
				maxH = maxH,
				maxV = maxV,
				special = special,
			}
		end
	end

	return groups
end

function Board.AreAdjacent(r1, c1, r2, c2)
	if r1 < 1 or r1 > ROWS or c1 < 1 or c1 > COLS then return false end
	if r2 < 1 or r2 > ROWS or c2 < 1 or c2 > COLS then return false end
	return (math.abs(r1 - r2) + math.abs(c1 - c2)) == 1
end

local function isSpecialSwap(a, b)
	if not a or not b then return false end
	if a.s == Board.SPECIAL_PRISM or b.s == Board.SPECIAL_PRISM then return true end
	if a.s ~= nil and b.s ~= nil then return true end
	return false
end

local function swapCellsInPlace(grid, r1, c1, r2, c2)
	local tmp = grid[r1][c1]
	grid[r1][c1] = grid[r2][c2]
	grid[r2][c2] = tmp
end

-- Fast check whether swapping (r1,c1) and (r2,c2) produces a legal move
function Board.IsLegalSwap(grid, r1, c1, r2, c2)
	if not Board.AreAdjacent(r1, c1, r2, c2) then return false end
	local a, b = grid[r1][c1], grid[r2][c2]
	if not a or not b then return false end
	if isSpecialSwap(a, b) then return true end
	if a.t == b.t then return false end

	swapCellsInPlace(grid, r1, c1, r2, c2)
	local matches = Board.FindMatches(grid)
	swapCellsInPlace(grid, r1, c1, r2, c2)
	return #matches > 0
end

function Board.FindLegalMoves(grid)
	local moves = {}
	for r = 1, ROWS do
		for c = 1, COLS do
			if c < COLS and Board.IsLegalSwap(grid, r, c, r, c + 1) then
				moves[#moves + 1] = { r1 = r, c1 = c, r2 = r, c2 = c + 1 }
			end
			if r < ROWS and Board.IsLegalSwap(grid, r, c, r + 1, c) then
				moves[#moves + 1] = { r1 = r, c1 = c, r2 = r + 1, c2 = c }
			end
		end
	end
	return moves
end

function Board.GetHint(grid, rng)
	local moves = Board.FindLegalMoves(grid)
	if #moves == 0 then return nil end
	if rng then
		return moves[rng(#moves)]
	end
	return moves[1]
end

-- Force at least one guaranteed legal swap without creating an immediate 3-match
local function ensureLegalMove(grid)
	if #Board.FindLegalMoves(grid) > 0 then return true end
	-- Pattern at top-left: (1,1)=1, (1,2)=1, (1,3)=2, (2,3)=1 -> swapping (1,3) & (2,3) matches 3 of type 1
	local t1 = 1
	local t2 = 2
	-- Avoid creating accidental match with row 3 or col 4
	local avoid = grid[1][4] and grid[1][4].t or 0
	if avoid == t1 then t1 = 3 end
	if t2 == t1 then t2 = 4 end
	grid[1][1] = makeCell(t1, nil)
	grid[1][2] = makeCell(t1, nil)
	grid[1][3] = makeCell(t2, nil)
	grid[2][3] = makeCell(t1, nil)
	-- Fix any vertical conflict created by row 1/2
	if grid[2][1] and grid[2][1].t == t1 and grid[3][1] and grid[3][1].t == t1 then
		grid[3][1] = makeCell((t1 % NUM_TYPES) + 1, nil)
	end
	if grid[2][2] and grid[2][2].t == t1 and grid[3][2] and grid[3][2].t == t1 then
		grid[3][2] = makeCell((t1 % NUM_TYPES) + 1, nil)
	end
	return #Board.FindLegalMoves(grid) > 0
end

function Board.GenerateGrid(rng)
	rng = rng or defaultRng
	local grid = {}
	for attempt = 1, 40 do
		for r = 1, ROWS do
			grid[r] = {}
			for c = 1, COLS do
				local candidates = {}
				for t = 1, NUM_TYPES do
					if not createsImmediateMatch(grid, r, c, t) then
						candidates[#candidates + 1] = t
					end
				end
				local pick = candidates[rng(#candidates)]
				grid[r][c] = makeCell(pick, nil)
			end
		end
		if #Board.FindLegalMoves(grid) > 0 then
			return grid
		end
	end
	ensureLegalMove(grid)
	return grid
end

function Board.Reshuffle(grid, rng)
	rng = rng or defaultRng
	-- Collect existing cells to preserve specials where possible
	local specials = {}
	for r = 1, ROWS do
		for c = 1, COLS do
			local cell = grid[r][c]
			if cell and cell.s then
				specials[#specials + 1] = { t = cell.t, s = cell.s }
			end
		end
	end

	local fresh = Board.GenerateGrid(rng)
	-- Re-insert preserved specials into random distinct positions without breaking no-match invariant
	local used = {}
	for _, sp in ipairs(specials) do
		local placed = false
		for _ = 1, 64 do
			local r = rng(ROWS)
			local c = rng(COLS)
			local k = cellKey(r, c)
			if not used[k] then
				local old = fresh[r][c]
				-- Keep fresh cell's non-matching color (or 0 for Prismatic) so no match is introduced
				local t = (sp.s == Board.SPECIAL_PRISM) and 0 or old.t
				fresh[r][c] = makeCell(t, sp.s)
				if #Board.FindMatches(fresh) == 0 then
					used[k] = true
					placed = true
					break
				else
					fresh[r][c] = old
				end
			end
		end
		if not placed then
			-- Deterministic scan fallback
			for r = 1, ROWS do
				for c = 1, COLS do
					local k = cellKey(r, c)
					if not used[k] then
						local old = fresh[r][c]
						local t = (sp.s == Board.SPECIAL_PRISM) and 0 or old.t
						fresh[r][c] = makeCell(t, sp.s)
						if #Board.FindMatches(fresh) == 0 then
							used[k] = true
							placed = true
							break
						else
							fresh[r][c] = old
						end
					end
				end
				if placed then break end
			end
		end
	end
	if #Board.FindLegalMoves(fresh) == 0 then
		ensureLegalMove(fresh)
	end

	for r = 1, ROWS do
		for c = 1, COLS do
			grid[r][c] = fresh[r][c]
		end
	end
	return grid
end

function Board.NewState(mode, rng)
	return {
		grid = Board.GenerateGrid(rng),
		score = 0,
		moves = 0,
		cascade = 0,
		mode = mode or "classic",
		lastSwap = nil,
	}
end

-- Find most frequent color on the grid (used when a Prismatic is detonated indirectly)
local function dominantColor(grid)
	local counts = { 0, 0, 0, 0, 0, 0 }
	for r = 1, ROWS do
		for c = 1, COLS do
			local cell = grid[r][c]
			if cell and cell.t >= 1 and cell.t <= NUM_TYPES then
				counts[cell.t] = counts[cell.t] + 1
			end
		end
	end
	local bestT, bestC = 1, -1
	for t = 1, NUM_TYPES do
		if counts[t] > bestC then
			bestT, bestC = t, counts[t]
		end
	end
	return bestT
end

-- Expand clears through triggered specials (BFS chain reaction)
local function expandSpecialClears(grid, clearSet, protectedSet, prismColorHint)
	local triggered = {}
	local queue = {}
	local queued = {}

	for k in pairs(clearSet) do
		if not protectedSet[k] then
			local r, c = keyToRC(k)
			local cell = grid[r][c]
			if cell and cell.s then
				queue[#queue + 1] = k
				queued[k] = true
			end
		end
	end

	local function addCell(r, c)
		if r < 1 or r > ROWS or c < 1 or c > COLS then return end
		local k = cellKey(r, c)
		if not clearSet[k] then
			clearSet[k] = true
			local cell = grid[r][c]
			if cell and cell.s and not queued[k] and not protectedSet[k] then
				queued[k] = true
				queue[#queue + 1] = k
			end
		end
	end

	local head = 1
	while head <= #queue do
		local k = queue[head]
		head = head + 1
		local r, c = keyToRC(k)
		local cell = grid[r][c]
		if cell and cell.s then
			local s = cell.s
			local targets = {}
			if s == Board.SPECIAL_LINEH then
				for cc = 1, COLS do
					addCell(r, cc)
					targets[#targets + 1] = { r = r, c = cc }
				end
			elseif s == Board.SPECIAL_LINEV then
				for rr = 1, ROWS do
					addCell(rr, c)
					targets[#targets + 1] = { r = rr, c = c }
				end
			elseif s == Board.SPECIAL_BLAST then
				for rr = r - 1, r + 1 do
					for cc = c - 1, c + 1 do
						if rr >= 1 and rr <= ROWS and cc >= 1 and cc <= COLS then
							addCell(rr, cc)
							targets[#targets + 1] = { r = rr, c = cc }
						end
					end
				end
			elseif s == Board.SPECIAL_PRISM then
				local targetColor = prismColorHint or dominantColor(grid)
				for rr = 1, ROWS do
					for cc = 1, COLS do
						local other = grid[rr][cc]
						if other and other.t == targetColor then
							addCell(rr, cc)
							targets[#targets + 1] = { r = rr, c = cc }
						end
					end
				end
			end
			triggered[#triggered + 1] = { r = r, c = c, special = s, targets = targets }
		end
	end

	return triggered
end

-- Apply gravity + refill to grid after clears; returns drops and spawns arrays
local function applyGravityAndRefill(grid, rng)
	rng = rng or defaultRng
	local drops = {}
	local spawns = {}

	for c = 1, COLS do
		local writeR = ROWS
		for r = ROWS, 1, -1 do
			local cell = grid[r][c]
			if cell ~= nil then
				if r ~= writeR then
					grid[writeR][c] = cell
					grid[r][c] = nil
					drops[#drops + 1] = {
						fromR = r,
						toR = writeR,
						c = c,
						t = cell.t,
						s = cell.s,
					}
				end
				writeR = writeR - 1
			end
		end
		-- Fill empty top slots
		local spawnCount = writeR
		for r = writeR, 1, -1 do
			local t = rng(NUM_TYPES)
			grid[r][c] = makeCell(t, nil)
			spawns[#spawns + 1] = {
				r = r,
				c = c,
				t = t,
				fromR = r - spawnCount, -- negative/above-board row for drop animation
			}
		end
	end

	return drops, spawns
end

local function pickSpecialSpawnCell(group, lastSwap)
	if lastSwap then
		local k1 = cellKey(lastSwap.r1, lastSwap.c1)
		if group.cellSet[k1] then return lastSwap.r1, lastSwap.c1 end
		local k2 = cellKey(lastSwap.r2, lastSwap.c2)
		if group.cellSet[k2] then return lastSwap.r2, lastSwap.c2 end
	end
	for _, pos in pairs(group.intersections) do
		return pos.r, pos.c
	end
	local mid = group.cells[math.ceil(#group.cells / 2)]
	return mid.r, mid.c
end

-- Resolve a single cascade step from matched groups on `state.grid`.
-- Returns a step result table, or nil if no matches exist.
function Board.ResolveStep(state, rng)
	local grid = state.grid
	local groups = Board.FindMatches(grid)
	if #groups == 0 then
		return nil
	end

	state.cascade = (state.cascade or 0) + 1
	local mult = math.min(state.cascade, Board.SCORE.MAX_MULTIPLIER)

	local clearSet = {}
	local protectedSet = {}
	local createdSpecials = {}
	local bonus = 0

	for _, g in ipairs(groups) do
		for _, pos in ipairs(g.cells) do
			clearSet[cellKey(pos.r, pos.c)] = true
		end
		if g.special then
			local sr, sc = pickSpecialSpawnCell(g, state.lastSwap)
			local sk = cellKey(sr, sc)
			-- Only create if not already creating a special there
			if not protectedSet[sk] then
				protectedSet[sk] = true
				local newT = (g.special == Board.SPECIAL_PRISM) and 0 or g.t
				createdSpecials[#createdSpecials + 1] = {
					r = sr,
					c = sc,
					t = newT,
					s = g.special,
				}
				if g.special == Board.SPECIAL_PRISM then
					bonus = bonus + Board.SCORE.MATCH5_BONUS
				elseif g.special == Board.SPECIAL_BLAST then
					bonus = bonus + Board.SCORE.BLAST_CREATE_BONUS
				else
					bonus = bonus + Board.SCORE.MATCH4_BONUS
				end
			end
		end
	end

	-- Clear swap hint after first step
	state.lastSwap = nil

	-- Expand any specials caught in the cleared cells
	local triggered = expandSpecialClears(grid, clearSet, protectedSet, nil)
	bonus = bonus + (#triggered * Board.SCORE.SPECIAL_TRIGGER_BONUS)

	-- Collect cleared cells for animation/scoring and remove them from grid
	local cleared = {}
	for k in pairs(clearSet) do
		local r, c = keyToRC(k)
		local cell = grid[r][c]
		if cell then
			cleared[#cleared + 1] = { r = r, c = c, t = cell.t, s = cell.s }
			grid[r][c] = nil
		end
	end

	-- Place newly created specials
	for _, sp in ipairs(createdSpecials) do
		grid[sp.r][sp.c] = makeCell(sp.t, sp.s)
	end

	local rawPoints = (#cleared * Board.SCORE.BASE_GEM) + bonus
	local points = rawPoints * mult
	state.score = (state.score or 0) + points

	local drops, spawns = applyGravityAndRefill(grid, rng)

	return {
		cascade = state.cascade,
		multiplier = mult,
		groups = groups,
		cleared = cleared,
		createdSpecials = createdSpecials,
		triggeredSpecials = triggered,
		drops = drops,
		spawns = spawns,
		points = points,
		totalScore = state.score,
	}
end

-- Execute a player swap at (r1,c1) <-> (r2,c2).
-- Returns: valid (bool), firstStep (table|nil)
function Board.TrySwap(state, r1, c1, r2, c2, rng)
	local grid = state.grid
	if not Board.AreAdjacent(r1, c1, r2, c2) then
		return false, nil
	end
	local a, b = grid[r1][c1], grid[r2][c2]
	if not a or not b then
		return false, nil
	end

	-- Handle special-combination swaps directly
	if isSpecialSwap(a, b) then
		swapCellsInPlace(grid, r1, c1, r2, c2)
		state.moves = (state.moves or 0) + 1
		state.cascade = 1
		local clearSet = {}
		local protectedSet = {}
		local triggered = {}
		local prismColorHint = nil

		-- After swap: `b` is at (r1,c1), `a` is at (r2,c2)
		local sa, sb = a.s, b.s
		if sa == Board.SPECIAL_PRISM and sb == Board.SPECIAL_PRISM then
			-- Dual prismatic: clear whole board
			local targets = {}
			for rr = 1, ROWS do
				for cc = 1, COLS do
					clearSet[cellKey(rr, cc)] = true
					targets[#targets + 1] = { r = rr, c = cc }
				end
			end
			triggered[#triggered + 1] = { r = r2, c = c2, special = Board.SPECIAL_PRISM, targets = targets }
		elseif sa == Board.SPECIAL_PRISM or sb == Board.SPECIAL_PRISM then
			-- Prismatic + gem (normal or special)
			local prismR, prismC, otherCell
			if sa == Board.SPECIAL_PRISM then
				prismR, prismC, otherCell = r2, c2, b
			else
				prismR, prismC, otherCell = r1, c1, a
			end
			prismColorHint = otherCell.t
			clearSet[cellKey(r1, c1)] = true
			clearSet[cellKey(r2, c2)] = true
			local targets = {}
			for rr = 1, ROWS do
				for cc = 1, COLS do
					local cCell = grid[rr][cc]
					if cCell and cCell.t == prismColorHint then
						clearSet[cellKey(rr, cc)] = true
						targets[#targets + 1] = { r = rr, c = cc }
					end
				end
			end
			triggered[#triggered + 1] = { r = prismR, c = prismC, special = Board.SPECIAL_PRISM, targets = targets }
		elseif sa == Board.SPECIAL_BLAST and sb == Board.SPECIAL_BLAST then
			-- 5x5 mega blast centered at (r2, c2)
			local targets = {}
			for rr = r2 - 2, r2 + 2 do
				for cc = c2 - 2, c2 + 2 do
					if rr >= 1 and rr <= ROWS and cc >= 1 and cc <= COLS then
						clearSet[cellKey(rr, cc)] = true
						targets[#targets + 1] = { r = rr, c = cc }
					end
				end
			end
			triggered[#triggered + 1] = { r = r2, c = c2, special = Board.SPECIAL_BLAST, targets = targets }
		elseif (sa == Board.SPECIAL_BLAST or sb == Board.SPECIAL_BLAST)
			and (sa == Board.SPECIAL_LINEH or sa == Board.SPECIAL_LINEV or sb == Board.SPECIAL_LINEH or sb == Board.SPECIAL_LINEV) then
			-- Line + Blast: 3 rows + 3 columns cross centered at (r2, c2)
			local targetsH, targetsV = {}, {}
			for dr = -1, 1 do
				local rr = r2 + dr
				if rr >= 1 and rr <= ROWS then
					for cc = 1, COLS do
						clearSet[cellKey(rr, cc)] = true
						targetsH[#targetsH + 1] = { r = rr, c = cc }
					end
				end
			end
			for dc = -1, 1 do
				local cc = c2 + dc
				if cc >= 1 and cc <= COLS then
					for rr = 1, ROWS do
						clearSet[cellKey(rr, cc)] = true
						targetsV[#targetsV + 1] = { r = rr, c = cc }
					end
				end
			end
			triggered[#triggered + 1] = { r = r2, c = c2, special = Board.SPECIAL_LINEH, targets = targetsH }
			triggered[#triggered + 1] = { r = r2, c = c2, special = Board.SPECIAL_LINEV, targets = targetsV }
			triggered[#triggered + 1] = { r = r2, c = c2, special = Board.SPECIAL_BLAST, targets = {} }
		else
			-- Line + Line: full row + full column at (r2, c2)
			local targetsH, targetsV = {}, {}
			for cc = 1, COLS do
				clearSet[cellKey(r2, cc)] = true
				targetsH[#targetsH + 1] = { r = r2, c = cc }
			end
			for rr = 1, ROWS do
				clearSet[cellKey(rr, c2)] = true
				targetsV[#targetsV + 1] = { r = rr, c = c2 }
			end
			triggered[#triggered + 1] = { r = r2, c = c2, special = Board.SPECIAL_LINEH, targets = targetsH }
			triggered[#triggered + 1] = { r = r2, c = c2, special = Board.SPECIAL_LINEV, targets = targetsV }
		end

		-- Chain-react any other specials hit (exclude already-consumed pair)
		protectedSet[cellKey(r1, c1)] = true
		protectedSet[cellKey(r2, c2)] = true
		local chained = expandSpecialClears(grid, clearSet, protectedSet, prismColorHint)
		for i = 1, #chained do
			triggered[#triggered + 1] = chained[i]
		end

		local cleared = {}
		for k in pairs(clearSet) do
			local rr, cc = keyToRC(k)
			local cell = grid[rr][cc]
			if cell then
				cleared[#cleared + 1] = { r = rr, c = cc, t = cell.t, s = cell.s }
				grid[rr][cc] = nil
			end
		end

		local points = (#cleared * Board.SCORE.BASE_GEM) + (#triggered * Board.SCORE.SPECIAL_TRIGGER_BONUS)
		state.score = (state.score or 0) + points
		local drops, spawns = applyGravityAndRefill(grid, rng)

		return true, {
			cascade = 1,
			multiplier = 1,
			groups = {},
			cleared = cleared,
			createdSpecials = {},
			triggeredSpecials = triggered,
			drops = drops,
			spawns = spawns,
			points = points,
			totalScore = state.score,
		}
	end

	-- Normal swap: check if it produces at least one match
	if a.t == b.t then
		return false, nil
	end

	swapCellsInPlace(grid, r1, c1, r2, c2)
	local matches = Board.FindMatches(grid)
	if #matches == 0 then
		swapCellsInPlace(grid, r1, c1, r2, c2)
		return false, nil
	end

	state.moves = (state.moves or 0) + 1
	state.cascade = 0
	state.lastSwap = { r1 = r1, c1 = c1, r2 = r2, c2 = c2 }
	local step = Board.ResolveStep(state, rng)
	return true, step
end

-- Fast-settle any remaining cascades (used on combat/hide/logout or offline tests)
function Board.ResolveAll(state, rng)
	local steps = {}
	local guard = 0
	while guard < 100 do
		guard = guard + 1
		local step = Board.ResolveStep(state, rng)
		if not step then break end
		steps[#steps + 1] = step
	end
	return steps
end

-- Anti-cheat plausibility check driven directly by Board.SCORE constants
function Board.IsPlausibleScore(score, pps, moves, duration)
	if type(score) ~= "number" or score < 0 or score > Board.SCORE.MAX_SCORE then
		return false
	end
	if pps ~= nil and (type(pps) ~= "number" or pps < 0 or pps > Board.SCORE.MAX_PPS) then
		return false
	end
	if moves ~= nil then
		if type(moves) ~= "number" or moves < 0 then return false end
		if moves == 0 and score > 0 then return false end
		if moves > 0 and score > moves * Board.SCORE.MAX_POINTS_PER_MOVE then
			return false
		end
	end
	if duration ~= nil then
		if type(duration) ~= "number" or duration < 0 then return false end
		if duration > 0 and (score / duration) > Board.SCORE.MAX_PPS then
			return false
		end
	end
	return true
end

return Board
