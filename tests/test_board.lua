-- tests/test_board.lua: Offline LuaJIT (Lua 5.1) unit tests for Board.lua and State.lua.
-- Run: luajit tests/test_board.lua

local ns = {}

local function loadModule(path)
	local chunk, err = loadfile(path)
	assert(chunk, "Failed to load " .. path .. ": " .. tostring(err))
	return chunk("Jeweled", ns)
end

loadModule("Jeweled/Board.lua")
loadModule("Jeweled/State.lua")

local Board = ns.Board
local State = ns.State

local passed = 0
local function check(name, cond, detail)
	if not cond then
		error("FAIL [" .. name .. "]: " .. tostring(detail or "assertion failed"))
	end
	passed = passed + 1
end

-- Deterministic LCG RNG for reproducible tests
local function makeRng(seed)
	local s = seed or 42
	return function(n)
		s = (s * 1103515245 + 12345) % 2147483648
		return (s % n) + 1
	end
end

-- Helper to construct a grid from 8 strings of 8 digits ('1'..'6', '0' for prism)
local function gridFromStrings(rows, specials)
	local g = {}
	for r = 1, 8 do
		g[r] = {}
		for c = 1, 8 do
			local t = tonumber(rows[r]:sub(c, c))
			local s = nil
			if specials then
				local sch = specials[r]:sub(c, c)
				if sch ~= "." then s = sch end
			end
			g[r][c] = { t = t, s = s }
		end
	end
	return g
end

-- 1. Generation invariants: 20 boards with 0 initial matches and >=1 legal move
do
	local rng = makeRng(1337)
	for i = 1, 20 do
		local g = Board.GenerateGrid(rng)
		local matches = Board.FindMatches(g)
		check("gen_no_initial_matches_" .. i, #matches == 0, "found " .. #matches)
		local moves = Board.FindLegalMoves(g)
		check("gen_has_legal_move_" .. i, #moves > 0, "no legal moves on board " .. i)
	end
end

-- 2. Simple 3-match swap + invalid swap rejection
do
	local g = gridFromStrings({
		"11213456",
		"34156123",
		"56321456",
		"23456123",
		"45612345",
		"61234561",
		"23456123",
		"45612345",
	})
	local st = { grid = g, score = 0, moves = 0, cascade = 0, mode = "classic" }
	-- Invalid swap: (1,5) & (1,6) -> no match
	local okBad = Board.TrySwap(st, 1, 5, 1, 6, makeRng(1))
	check("invalid_swap_rejected", okBad == false)
	check("invalid_swap_no_move_count", st.moves == 0)

	-- Valid swap: (1,3) & (2,3) puts '1' at (1,3), matching (1,1)(1,2)(1,3)(1,4) -> 4-match H!
	local ok, step = Board.TrySwap(st, 1, 3, 2, 3, makeRng(2))
	check("valid_swap_accepted", ok == true and step ~= nil)
	check("moves_incremented", st.moves == 1)
	check("line_h_created", #step.createdSpecials == 1 and step.createdSpecials[1].s == "H",
		"expected H special")
	check("score_positive", st.score > 0)
end

-- 3. 5-match creates Prismatic (P)
do
	local g = gridFromStrings({
		"11211345",
		"34156123",
		"56324156",
		"23456234",
		"45612345",
		"61234561",
		"23456123",
		"45612345",
	})
	local st = { grid = g, score = 0, moves = 0, cascade = 0, mode = "classic" }
	local ok, step = Board.TrySwap(st, 1, 3, 2, 3, makeRng(3))
	check("match5_valid", ok == true)
	check("match5_creates_prism", #step.createdSpecials == 1 and step.createdSpecials[1].s == "P" and step.createdSpecials[1].t == 0)
end

-- 4. L/T intersection creates Blast (B)
do
	local g = gridFromStrings({
		"23145623",
		"45162345",
		"11211345",
		"34526123",
		"56234561",
		"23456123",
		"45612345",
		"61234561",
	})
	-- Swap (3,3)='2' with (4,3)='5'? Wait: put '1' at (3,3) by swapping (3,3) with (4,3) if (4,3)='1'
	g[3][3].t = 2
	g[4][3].t = 1
	g[3][4].t = 6
	g[3][5].t = 3
	-- Now (1,3)=1, (2,3)=1, (3,1)=1, (3,2)=1, (4,3)=1 -> swapping (3,3) & (4,3) makes L-shape of 5 '1's!
	local st = { grid = g, score = 0, moves = 0, cascade = 0, mode = "classic" }
	local ok, step = Board.TrySwap(st, 3, 3, 4, 3, makeRng(4))
	check("l_shape_valid", ok == true)
	check("l_shape_creates_blast", #step.createdSpecials == 1 and step.createdSpecials[1].s == "B")
end

-- 5. Special activations: Prismatic + color clears all of that color
do
	local g = gridFromStrings({
		"01234561",
		"23456123",
		"45612345",
		"61234561",
		"23456123",
		"45612345",
		"61234561",
		"23456123",
	}, {
		"P.......",
		"........",
		"........",
		"........",
		"........",
		"........",
		"........",
		"........",
	})
	-- Count type 1 gems before swap
	local ones = 0
	for r = 1, 8 do
		for c = 1, 8 do
			if g[r][c].t == 1 then ones = ones + 1 end
		end
	end
	local st = { grid = g, score = 0, moves = 0, cascade = 0, mode = "classic" }
	local ok, step = Board.TrySwap(st, 1, 1, 1, 2, makeRng(5))
	check("prism_swap_valid", ok == true)
	check("prism_clears_all_of_color", #step.cleared == ones + 1, "expected " .. (ones + 1) .. ", got " .. #step.cleared)
	check("prism_trigger_recorded", #step.triggeredSpecials >= 1 and step.triggeredSpecials[1].special == "P")
end

-- 6. Dual Prismatic clears entire 64-cell board
do
	local g = Board.GenerateGrid(makeRng(6))
	g[4][4] = { t = 0, s = "P" }
	g[4][5] = { t = 0, s = "P" }
	local st = { grid = g, score = 0, moves = 0, cascade = 0, mode = "classic" }
	local ok, step = Board.TrySwap(st, 4, 4, 4, 5, makeRng(7))
	check("dual_prism_valid", ok == true)
	check("dual_prism_clears_64", #step.cleared == 64, "got " .. #step.cleared)
end

-- 7. Line + Line combo clears full row + full column (15 cells)
do
	local g = Board.GenerateGrid(makeRng(8))
	g[4][4] = { t = 1, s = "H" }
	g[4][5] = { t = 2, s = "V" }
	local st = { grid = g, score = 0, moves = 0, cascade = 0, mode = "classic" }
	local ok, step = Board.TrySwap(st, 4, 4, 4, 5, makeRng(9))
	check("line_line_valid", ok == true)
	check("line_line_clears_15", #step.cleared == 15, "got " .. #step.cleared)
end

-- 8. Chain reaction: H-beam triggers a B-blast in the same row
do
	local g = gridFromStrings({
		"12345612",
		"34561234",
		"56123456",
		"11213456",
		"23156123",
		"45612345",
		"61234561",
		"23456123",
	}, {
		"........",
		"........",
		"........",
		"H.....B.",
		"........",
		"........",
		"........",
		"........",
	})
	local st = { grid = g, score = 0, moves = 0, cascade = 0, mode = "classic" }
	-- Swap (4,3) & (5,3) -> matches row 4 cols 1..4 including H at (4,1), which hits B at (4,7)!
	local ok, step = Board.TrySwap(st, 4, 3, 5, 3, makeRng(10))
	check("chain_valid", ok == true)
	check("chain_triggered_both", #step.triggeredSpecials == 2, "got " .. #step.triggeredSpecials)
	check("chain_cleared_row_plus_blast", #step.cleared >= 14, "got " .. #step.cleared)
end

-- 9. Reshuffle on dead board produces 0 matches and >=1 legal move while preserving specials
do
	local g = Board.GenerateGrid(makeRng(11))
	g[2][2] = { t = 3, s = "B" }
	g[6][6] = { t = 0, s = "P" }
	Board.Reshuffle(g, makeRng(12))
	check("reshuffle_no_matches", #Board.FindMatches(g) == 0)
	check("reshuffle_has_legal", #Board.FindLegalMoves(g) > 0)
	local foundB, foundP = false, false
	for r = 1, 8 do
		for c = 1, 8 do
			if g[r][c].s == "B" then foundB = true end
			if g[r][c].s == "P" then foundP = true end
		end
	end
	check("reshuffle_preserves_specials", foundB and foundP)
end

-- 10. State.lua 64-char round-trip serialization + corruption handling
do
	local g = Board.GenerateGrid(makeRng(13))
	g[1][1] = { t = 0, s = "P" }
	g[3][4] = { t = 2, s = "H" }
	g[5][6] = { t = 4, s = "V" }
	g[8][8] = { t = 5, s = "B" }
	local bStr, sStr = State.EncodeGrid(g)
	check("encode_lengths", #bStr == 64 and #sStr == 64)
	local decoded, err = State.DecodeGrid(bStr, sStr)
	check("decode_ok", decoded ~= nil and err == nil, err)
	for r = 1, 8 do
		for c = 1, 8 do
			check("roundtrip_" .. r .. "_" .. c,
				decoded[r][c].t == g[r][c].t and decoded[r][c].s == g[r][c].s)
		end
	end
	local bad, badErr = State.DecodeGrid("short", sStr)
	check("decode_rejects_truncated", bad == nil and badErr ~= nil)
	local bad2, badErr2 = State.DecodeGrid("0" .. bStr:sub(2), "." .. sStr:sub(2))
	check("decode_rejects_colorless_non_prism", bad2 == nil and badErr2 ~= nil)
end

-- 11. Plausibility anti-cheat bounds
do
	check("plausible_normal", Board.IsPlausibleScore(12500, 120, 15, 104) == true)
	check("reject_over_max_score", Board.IsPlausibleScore(5000000, 100, 500, 50000) == false)
	check("reject_over_max_pps", Board.IsPlausibleScore(50000, 999, 50, 50) == false)
	check("reject_zero_moves_nonzero_score", Board.IsPlausibleScore(500, 10, 0, 50) == false)
	check("reject_impossible_points_per_move", Board.IsPlausibleScore(100000, 100, 1, 1000) == false)
end

print(string.format("ALL %d BOARD & STATE TESTS PASSED", passed))
