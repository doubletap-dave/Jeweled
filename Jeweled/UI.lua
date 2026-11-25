-- UI.lua: Main Polestar-anatomy window, game state controller, score strip,
-- flight countdown/landing card, and live theme repainting for Jeweled.

local _, ns = ...

local UI = {}
ns.UI = UI

local HEADER_H = 34
local SCORE_H = 44
local FOOTER_H = 56
local PAD = 14

local win = nil
local headerBand, titleFS, soundBtn, closeBtn
local scoreStrip, scoreValFS, bestValFS, modeValFS, fpsFS
local gridHolder, landingCard, landingTextFS
local footerBar, newBtn, hintBtn, ranksBtn, achieveBtn, settingsBtn

local state = "IDLE" -- IDLE | PLAYING | ANIMATING | RESHUFFLE | PAUSED | GAME_OVER
local game = nil
local openedByFlight = false
local recordBrokenThisGame = false
local flightTimerTicker = nil
local autoPlaying = false

function UI.IsAutoPlaying()
	return autoPlaying
end

function UI.GetState()
	return state
end

function UI.IsShown()
	return win ~= nil and win:IsShown()
end

function UI.OpenedByFlight()
	return openedByFlight
end

function UI.SetOpenedByFlight(flag)
	openedByFlight = flag and true or false
end

local function formatNum(n)
	local s = tostring(math.floor(n or 0))
	local out = s:reverse():gsub("(%d%d%d)", "%1,"):reverse()
	if out:sub(1, 1) == "," then out = out:sub(2) end
	return out
end

local function formatTime(sec)
	sec = math.max(0, math.floor(sec + 0.5))
	local m = math.floor(sec / 60)
	local s = sec % 60
	return string.format("%d:%02d", m, s)
end

function UI.UpdateScoreStrip()
	if not scoreValFS then return end
	local sc = game and game.score or 0
	local db = ns.DB()
	local best = db and db.best and db.best.score or 0
	if sc > best then best = sc end

	scoreValFS:SetText("Score: " .. formatNum(sc))
	bestValFS:SetText("Best: " .. formatNum(best))

	if autoPlaying then
		modeValFS:SetText("|cffe6ba66[AUTO]|r Moves: " .. tostring(game and game.moves or 0))
	elseif ns.Taxi and ns.Taxi.GetFlightHudText then
		local hud = ns.Taxi.GetFlightHudText()
		if hud then
			modeValFS:SetText(hud)
		else
			local moves = game and game.moves or 0
			modeValFS:SetText("Moves: " .. tostring(moves))
		end
	else
		local moves = game and game.moves or 0
		modeValFS:SetText("Moves: " .. tostring(moves))
	end

	if fpsFS then
		if ns.Get("showFps") then
			fpsFS:SetText(string.format("%dfps  tw:%d  fx:%d",
				ns.Anim.GetFPS(), ns.Anim.ActiveCount(), ns.FX.ActiveCount()))
			fpsFS:Show()
		else
			fpsFS:Hide()
		end
	end
end

local function stopFlightHudTicker()
	if flightTimerTicker then
		flightTimerTicker:Cancel()
		flightTimerTicker = nil
	end
end

function UI.RefreshFlightHudTicker()
	stopFlightHudTicker()
	if not UI.IsShown() then return end
	local needTick = (ns.Taxi and ns.Taxi.IsFlying and ns.Taxi.IsFlying()) or ns.Get("showFps")
	if needTick and C_Timer and C_Timer.NewTicker then
		flightTimerTicker = C_Timer.NewTicker(0.5, function()
			if not UI.IsShown() then
				stopFlightHudTicker()
				return
			end
			UI.UpdateScoreStrip()
		end)
	end
end

local function updateSoundButtonLabel()
	if not soundBtn or not soundBtn._jwlLabel then return end
	soundBtn._jwlLabel:SetText(ns.Get("sound") ~= false and "SFX: On" or "SFX: Off")
end

local function layoutWindow()
	if not win then return end
	local boardPx = ns.Grid.ApplyScale(ns.Get("windowScale"))
	local w = boardPx + PAD * 2
	local h = HEADER_H + SCORE_H + boardPx + FOOTER_H + PAD * 2
	win:SetSize(w, h)
	gridHolder:SetSize(boardPx, boardPx)

	-- Distribute 5 footer buttons proportionally so "Leaderboard" fits cleanly at all scales
	local btns = { newBtn, hintBtn, ranksBtn, achieveBtn, settingsBtn }
	local weights = { 0.14, 0.15, 0.31, 0.18, 0.22 }
	local gap = 5
	local avail = w - PAD * 2 - gap * (#btns - 1)
	local curX = PAD
	for i, b in ipairs(btns) do
		local bw = math.floor(avail * weights[i])
		b:SetSize(bw, 28)
		b:ClearAllPoints()
		b:SetPoint("LEFT", footerBar, "LEFT", curX, 0)
		curX = curX + bw + gap
	end
end

local function repaintTheme()
	if not win then return end
	local T = ns.Theme
	T.PaintWindow(win)

	local sr, sg, sb = T.Color("sky")
	headerBand:SetColorTexture(sr, sg, sb, 0.96)
	local br, bg, bb, ba = T.Wash("divider")
	headerBand._line:SetColorTexture(br, bg, bb, math.max(ba, 0.14))

	local pr, pg, pb = T.Color("panel")
	scoreStrip._bg:SetColorTexture(pr, pg, pb, 0.90)
	scoreStrip._line:SetColorTexture(br, bg, bb, math.max(ba, 0.12))

	local fr, fg, fb = T.Color("footer")
	footerBar._bg:SetColorTexture(fr, fg, fb, 0.96)
	footerBar._line:SetColorTexture(br, bg, bb, math.max(ba, 0.14))

	T.ApplyFont(titleFS, "title", "text")
	T.ApplyFont(scoreValFS, "heading", "accent")
	T.ApplyFont(bestValFS, "label", "textDim")
	T.ApplyFont(modeValFS, "number", "text")
	T.ApplyFont(fpsFS, "small", "textMuted")

	T.PaintButton(soundBtn, false)
	T.PaintButton(closeBtn, false)
	T.PaintButton(newBtn, false)
	T.PaintButton(hintBtn, true)
	T.PaintButton(ranksBtn, false)
	T.PaintButton(achieveBtn, false)
	T.PaintButton(settingsBtn, false)

	if landingCard then
		local lr, lg, lb = T.Color("panel")
		landingCard._bg:SetColorTexture(lr, lg, lb, 0.96)
		local ar, ag, ab = T.Accent()
		T.ApplyBorder(landingCard, ar, ag, ab, 0.9)
		T.ApplyFont(landingTextFS, "body", "text")
	end
	ns.Grid.ApplyBackground()
end

local function saveNow()
	if game then
		ns.currentGame = game
		ns.State.SaveGame(game)
	end
end

local function checkNewRecordAndAchieve(step)
	if not game then return end
	local newAcc = ns.State.RecordBest(game.score, nil)
	if newAcc and not recordBrokenThisGame and game.score >= 1000 then
		recordBrokenThisGame = true
		ns.FX.PlayNewRecord()
	end
	if ns.Achieve and ns.Achieve.OnStep then
		ns.Achieve.OnStep(game, step)
	end
	if newAcc and ns.Comms and ns.Comms.BroadcastScore then
		ns.Comms.BroadcastScore(game.score, nil, game.mode, nil, game.moves, nil)
	end
end

local runCascadeStep
local scheduleNextAutoMove

-- Pick the highest-value legal move so dev auto-play showcases specials & cascades
local function pickSmartAutoMove(grid)
	local moves = ns.Board.FindLegalMoves(grid)
	if #moves == 0 then return nil end
	local bestMove, bestScore = moves[1], -1
	for _, m in ipairs(moves) do
		local a, b = grid[m.r1][m.c1], grid[m.r2][m.c2]
		local weight = 0
		if a and b and (a.s == "P" or b.s == "P") then
			weight = 1000
		elseif a and b and a.s and b.s then
			weight = 800
		else
			-- Simulate move on a lightweight copy to prioritize 4/5-matches and L/T blasts
			local sim = { grid = ns.Board.CloneGrid(grid), score = 0, moves = 0, cascade = 0 }
			local ok, step = ns.Board.TrySwap(sim, m.r1, m.c1, m.r2, m.c2)
			if ok and step then
				weight = (step.points or 0) + (#(step.createdSpecials or {}) * 400) + (#(step.triggeredSpecials or {}) * 300)
			end
		end
		if weight > bestScore then
			bestScore = weight
			bestMove = m
		end
	end
	return bestMove
end

scheduleNextAutoMove = function()
	if not autoPlaying or state ~= "PLAYING" or not game or not UI.IsShown() then return end
	ns.Anim.CancelTag("autoplay")
	ns.Anim.Delay(0.45, function()
		if not autoPlaying or state ~= "PLAYING" or not game or not UI.IsShown() then return end
		local m = pickSmartAutoMove(game.grid)
		if m then
			UI.RequestSwap(m.r1, m.c1, m.r2, m.c2)
		end
	end, "autoplay")
end

function UI.StopAutoPlay()
	if not autoPlaying then return end
	autoPlaying = false
	ns.Anim.CancelTag("autoplay")
	UI.UpdateScoreStrip()
end

function UI.ToggleAutoPlay()
	if autoPlaying then
		UI.StopAutoPlay()
		ns.Print("Dev auto-play: OFF")
		return
	end
	if not UI.IsShown() then UI.Show(false) end
	autoPlaying = true
	UI.UpdateScoreStrip()
	ns.Print("Dev auto-play: ON (run /jeweled autoplay or close window to stop)")
	scheduleNextAutoMove()
end

local function finishTurnAndCheckMoves()
	if not game then state = "IDLE"; return end
	saveNow()
	UI.UpdateScoreStrip()
	if ns.Grid and ns.Grid.ResetIdleHint then ns.Grid.ResetIdleHint() end

	local legal = ns.Board.FindLegalMoves(game.grid)
	if #legal == 0 then
		state = "RESHUFFLE"
		ns.Board.Reshuffle(game.grid)
		saveNow()
		ns.Grid.AnimateReshuffle(game.grid, function()
			state = "PLAYING"
			scheduleNextAutoMove()
		end)
	else
		state = "PLAYING"
		scheduleNextAutoMove()
	end
end

local function fireStepFX(step)
	local cellSz = ns.Grid.GetCellSize()
	local boardPx = ns.Grid.GetBoardPixelSize()
	local gemSet = ns.Get("gemSet")
	local delayMap = {}

	-- Triggered special effects
	for _, tr in ipairs(step.triggeredSpecials or {}) do
		local sx, sy = ns.Grid.CellCenter(tr.r, tr.c)
		ns.Sound.PlaySpecial(tr.special)
		if tr.special == "H" then
			ns.FX.Beam(true, sx, sy, boardPx)
			for _, tgt in ipairs(tr.targets or {}) do
				local k = (tgt.r - 1) * 8 + tgt.c
				local d = math.abs(tgt.c - tr.c) * 0.018
				delayMap[k] = d
				local tx, ty = ns.Grid.CellCenter(tgt.r, tgt.c)
				ns.FX.Sparkle(tx, ty, cellSz * 1.05, d, 0.45, 0.90, 1.0)
			end
		elseif tr.special == "V" then
			ns.FX.Beam(false, sx, sy, boardPx)
			for _, tgt in ipairs(tr.targets or {}) do
				local k = (tgt.r - 1) * 8 + tgt.c
				local d = math.abs(tgt.r - tr.r) * 0.018
				delayMap[k] = d
				local tx, ty = ns.Grid.CellCenter(tgt.r, tgt.c)
				ns.FX.Sparkle(tx, ty, cellSz * 1.05, d, 0.45, 0.90, 1.0)
			end
		elseif tr.special == "B" then
			ns.FX.FireExplosion(sx, sy, cellSz)
		elseif tr.special == "P" then
			ns.FX.BoardFlash(1, 1, 1, 0.26, 0.22)
			local rainbow = {
				{ 1.0, 0.45, 0.55 },
				{ 1.0, 0.85, 0.35 },
				{ 0.45, 0.95, 1.0 },
				{ 0.78, 0.52, 1.0 },
			}
			for idx, tgt in ipairs(tr.targets or {}) do
				if idx <= 16 then
					local tx, ty = ns.Grid.CellCenter(tgt.r, tgt.c)
					local rc = rainbow[((idx - 1) % #rainbow) + 1]
					ns.FX.Bolt(sx, sy, tx, ty, (idx - 1) * 0.014, rc[1], rc[2], rc[3])
				end
			end
		end
	end

	-- Match sparkles + color-matched gem shard bursts + center of mass for floating score
	local sumX, sumY, cnt = 0, 0, 0
	for idx, cl in ipairs(step.cleared or {}) do
		local x, y = ns.Grid.CellCenter(cl.r, cl.c)
		sumX = sumX + x
		sumY = sumY + y
		cnt = cnt + 1
		if idx <= 10 then
			local gr, gg, gb = ns.Art.GetGemColor(gemSet, cl.t)
			ns.FX.GemShatter(x, y, gr, gg, gb, idx <= 6 and 3 or 2)
			ns.FX.Sparkle(x, y, cellSz * (0.9 + math.min(step.cascade, 4) * 0.12), 0, gr, gg, gb)
		end
	end
	if cnt > 0 then
		local cx, cy = sumX / cnt, sumY / cnt
		ns.Sound.PlayCascade(step.cascade)
		ns.FX.PlayCascadeTier(step.cascade, cx, cy, step.points)
	end
	return delayMap
end

runCascadeStep = function(step)
	state = "ANIMATING"
	UI.UpdateScoreStrip()
	checkNewRecordAndAchieve(step)

	local delayMap = fireStepFX(step)
	ns.Grid.AnimatePop(step.cleared, delayMap, function()
		if state ~= "ANIMATING" then return end
		ns.Grid.AnimateDrops(game.grid, step.drops, step.spawns, function()
			if state ~= "ANIMATING" then return end
			local nextStep = ns.Board.ResolveStep(game)
			if nextStep then
				runCascadeStep(nextStep)
			else
				finishTurnAndCheckMoves()
			end
		end)
	end)
end

function UI.RequestSwap(r1, c1, r2, c2, startOx, startOy)
	if state ~= "PLAYING" or not game then return end
	if ns.Grid and ns.Grid.ResetIdleHint then ns.Grid.ResetIdleHint() end
	state = "ANIMATING"
	ns.Sound.Play("swap")

	local valid, firstStep = ns.Board.TrySwap(game, r1, c1, r2, c2)
	if not valid then
		ns.Sound.Play("error")
		ns.Grid.AnimateSwap(r1, c1, r2, c2, false, function()
			state = "PLAYING"
		end, startOx, startOy)
		return
	end

	-- Animate swap slide seamlessly from startOx/startOy, then pop/cascade
	ns.Grid.AnimateSwap(r1, c1, r2, c2, true, function()
		if state ~= "ANIMATING" then return end
		runCascadeStep(firstStep)
	end, startOx, startOy)
end

function UI.StartNewGame(mode, silent)
	if not win then UI.Create() end
	ns.Anim.CancelAll()
	ns.FX.Reset()
	ns.Input.Stop()
	if landingCard then landingCard:Hide() end

	local db = ns.DB()
	if db and db.best then
		db.best.games = (db.best.games or 0) + 1
	end

	game = ns.Board.NewState(mode or "classic")
	recordBrokenThisGame = false
	state = "PLAYING"
	saveNow()
	ns.Grid.Render(game.grid)
	UI.UpdateScoreStrip()
	if not silent then
		ns.FX.Banner("Go!", "accent", 0.65)
	end
end

function UI.EnsureGameLoaded(mode)
	if game then return end
	local loaded = ns.State.LoadGame()
	if loaded then
		game = loaded
		recordBrokenThisGame = false
		if mode then game.mode = mode end
	else
		game = ns.Board.NewState(mode or "classic")
		recordBrokenThisGame = false
		saveNow()
	end
	ns.currentGame = game
end

function UI.GetGame()
	return game
end

function UI.ShowHint()
	if state ~= "PLAYING" or not game then return end
	local hint = ns.Board.GetHint(game.grid)
	if hint then
		ns.Grid.ShowHint(hint.r1, hint.c1, hint.r2, hint.c2)
	else
		ns.Board.Reshuffle(game.grid)
		saveNow()
		ns.Grid.AnimateReshuffle(game.grid)
	end
end

function UI.FastSettleAndPause()
	UI.StopAutoPlay()
	ns.Input.Stop()
	ns.Anim.CancelAll()
	ns.FX.Reset()
	if game and state == "ANIMATING" then
		ns.Board.ResolveAll(game)
	end
	if game then
		saveNow()
		if win and win:IsShown() then
			ns.Grid.Render(game.grid)
		end
	end
	if state == "PLAYING" or state == "ANIMATING" or state == "RESHUFFLE" then
		state = "PAUSED"
	end
end

function UI.ShowLandingCard(text, autoCloseSec)
	if not win or not landingCard then return end
	landingTextFS:SetText(text)
	landingCard:Show()
	ns.Sound.Play("land")
	if autoCloseSec and autoCloseSec > 0 then
		ns.Anim.Delay(autoCloseSec, function()
			if landingCard then landingCard:Hide() end
			if openedByFlight and ns.Get("autoClose") ~= false then
				openedByFlight = false
				UI.Hide()
			end
		end, "landing_card")
	end
end

function UI.Create()
	if win then return win end

	win = CreateFrame("Frame", "JeweledMainFrame", UIParent)
	win:SetPoint("CENTER")
	win:SetFrameStrata("MEDIUM")
	win:SetMovable(true)
	win:EnableMouse(true)
	win:SetClampedToScreen(true)
	win:RegisterForDrag("LeftButton")
	win:SetScript("OnDragStart", win.StartMoving)
	win:SetScript("OnDragStop", function(self)
		self:StopMovingOrSizing()
		local db = ns.DB()
		if db then
			local pt, _, relPt, x, y = self:GetPoint(1)
			db.winPos = { pt, relPt, x, y }
		end
	end)
	win:Hide()
	if UISpecialFrames then
		table.insert(UISpecialFrames, "JeweledMainFrame")
	end

	-- Restore saved position
	local db = ns.DB()
	if db and type(db.winPos) == "table" and db.winPos[1] then
		win:ClearAllPoints()
		win:SetPoint(db.winPos[1], UIParent, db.winPos[2] or "CENTER", db.winPos[3] or 0, db.winPos[4] or 0)
	end

	-- Header band (Polestar sky-band anatomy)
	local header = CreateFrame("Frame", nil, win)
	header:SetHeight(HEADER_H)
	header:SetPoint("TOPLEFT", win, "TOPLEFT", 1, -1)
	header:SetPoint("TOPRIGHT", win, "TOPRIGHT", -1, -1)
	headerBand = header:CreateTexture(nil, "BACKGROUND")
	headerBand:SetAllPoints(header)
	headerBand._line = header:CreateTexture(nil, "ARTWORK")
	headerBand._line:SetHeight(1)
	headerBand._line:SetPoint("BOTTOMLEFT", header, "BOTTOMLEFT")
	headerBand._line:SetPoint("BOTTOMRIGHT", header, "BOTTOMRIGHT")

	local emblem = header:CreateTexture(nil, "ARTWORK")
	emblem:SetSize(20, 20)
	emblem:SetPoint("LEFT", header, "LEFT", 10, 0)
	emblem:SetTexture(ns.Art.ICON)

	titleFS = header:CreateFontString(nil, "OVERLAY", "GameFontNormal")
	titleFS:SetPoint("LEFT", emblem, "RIGHT", 8, 0)
	titleFS:SetText("Jeweled")

	closeBtn = ns.Theme.CreateButton(header, "X", 24, 22, function()
		openedByFlight = false
		UI.Hide()
	end, false)
	closeBtn:SetPoint("RIGHT", header, "RIGHT", -8, 0)

	soundBtn = ns.Theme.CreateButton(header, "SFX: On", 62, 22, function()
		ns.Set("sound", ns.Get("sound") == false)
		updateSoundButtonLabel()
	end, false)
	soundBtn:SetPoint("RIGHT", closeBtn, "LEFT", -6, 0)
	updateSoundButtonLabel()

	-- Score strip
	scoreStrip = CreateFrame("Frame", nil, win)
	scoreStrip:SetHeight(SCORE_H)
	scoreStrip:SetPoint("TOPLEFT", header, "BOTTOMLEFT", 0, 0)
	scoreStrip:SetPoint("TOPRIGHT", header, "BOTTOMRIGHT", 0, 0)
	scoreStrip._bg = scoreStrip:CreateTexture(nil, "BACKGROUND")
	scoreStrip._bg:SetAllPoints(scoreStrip)
	scoreStrip._line = scoreStrip:CreateTexture(nil, "ARTWORK")
	scoreStrip._line:SetHeight(1)
	scoreStrip._line:SetPoint("BOTTOMLEFT", scoreStrip, "BOTTOMLEFT")
	scoreStrip._line:SetPoint("BOTTOMRIGHT", scoreStrip, "BOTTOMRIGHT")

	scoreValFS = scoreStrip:CreateFontString(nil, "OVERLAY", "GameFontNormal")
	scoreValFS:SetPoint("TOPLEFT", scoreStrip, "TOPLEFT", PAD, -6)
	bestValFS = scoreStrip:CreateFontString(nil, "OVERLAY", "GameFontNormal")
	bestValFS:SetPoint("BOTTOMLEFT", scoreStrip, "BOTTOMLEFT", PAD, 6)
	modeValFS = scoreStrip:CreateFontString(nil, "OVERLAY", "GameFontNormal")
	modeValFS:SetPoint("TOPRIGHT", scoreStrip, "TOPRIGHT", -PAD, -6)
	fpsFS = scoreStrip:CreateFontString(nil, "OVERLAY", "GameFontNormal")
	fpsFS:SetPoint("BOTTOMRIGHT", scoreStrip, "BOTTOMRIGHT", -PAD, 6)
	fpsFS:Hide()

	-- Board well
	gridHolder = ns.Grid.Init(win)
	gridHolder:SetPoint("TOP", scoreStrip, "BOTTOM", 0, -PAD)
	ns.FX.Init(win, gridHolder)

	-- Landing score card overlay (Phase 4)
	landingCard = CreateFrame("Frame", nil, gridHolder)
	landingCard:SetSize(290, 128)
	landingCard:SetPoint("CENTER", gridHolder, "CENTER")
	landingCard:SetFrameLevel(gridHolder:GetFrameLevel() + 20)
	landingCard._bg = landingCard:CreateTexture(nil, "BACKGROUND")
	landingCard._bg:SetAllPoints(landingCard)
	landingTextFS = landingCard:CreateFontString(nil, "OVERLAY", "GameFontNormal")
	landingTextFS:SetPoint("TOPLEFT", landingCard, "TOPLEFT", 14, -14)
	landingTextFS:SetPoint("BOTTOMRIGHT", landingCard, "BOTTOMRIGHT", -14, 14)
	landingTextFS:SetJustifyH("CENTER")
	landingTextFS:SetJustifyV("MIDDLE")
	landingCard:Hide()

	-- Footer bar (56px house height)
	footerBar = CreateFrame("Frame", nil, win)
	footerBar:SetHeight(FOOTER_H)
	footerBar:SetPoint("BOTTOMLEFT", win, "BOTTOMLEFT", 1, 1)
	footerBar:SetPoint("BOTTOMRIGHT", win, "BOTTOMRIGHT", -1, 1)
	footerBar._bg = footerBar:CreateTexture(nil, "BACKGROUND")
	footerBar._bg:SetAllPoints(footerBar)
	footerBar._line = footerBar:CreateTexture(nil, "ARTWORK")
	footerBar._line:SetHeight(1)
	footerBar._line:SetPoint("TOPLEFT", footerBar, "TOPLEFT")
	footerBar._line:SetPoint("TOPRIGHT", footerBar, "TOPRIGHT")

	newBtn = ns.Theme.CreateButton(footerBar, "New", 64, 28, function()
		UI.ConfirmNewGame()
	end, false)
	hintBtn = ns.Theme.CreateButton(footerBar, "Hint", 64, 28, function()
		UI.ShowHint()
	end, true)
	ranksBtn = ns.Theme.CreateButton(footerBar, "Leaderboard", 96, 28, function()
		if ns.Ranks and ns.Ranks.Toggle then ns.Ranks.Toggle() end
	end, false)
	achieveBtn = ns.Theme.CreateButton(footerBar, "Feats", 64, 28, function()
		if ns.Achieve and ns.Achieve.ToggleWindow then ns.Achieve.ToggleWindow() end
	end, false)
	settingsBtn = ns.Theme.CreateButton(footerBar, "Options", 64, 28, function()
		if ns.Options and ns.Options.Open then ns.Options.Open() end
	end, false)

	win:SetScript("OnShow", function()
		repaintTheme()
		layoutWindow()
		updateSoundButtonLabel()
		UI.EnsureGameLoaded()
		state = "PLAYING"
		ns.Grid.Render(game.grid)
		ns.Grid.ResetIdleHint()
		ns.Grid.SetLiveActive(true)
		UI.UpdateScoreStrip()
		UI.RefreshFlightHudTicker()
	end)

	win:SetScript("OnHide", function()
		stopFlightHudTicker()
		ns.Grid.SetLiveActive(false)
		UI.FastSettleAndPause()
	end)

	ns.Theme.RegisterRepaint(repaintTheme)
	layoutWindow()
	repaintTheme()
	return win
end

function UI.Show(fromFlight)
	if InCombatLockdown and InCombatLockdown() then
		ns.Print("Cannot open Jeweled during combat.")
		return
	end
	if not win then UI.Create() end
	if fromFlight and not win:IsShown() then
		openedByFlight = true
	end
	win:Show()
end

function UI.Hide()
	if win and win:IsShown() then
		win:Hide()
	end
end

function UI.Toggle()
	if UI.IsShown() then
		openedByFlight = false
		UI.Hide()
	else
		UI.Show(false)
	end
end

function UI.ResetPosition()
	local db = ns.DB()
	if db then db.winPos = nil end
	if win then
		win:ClearAllPoints()
		win:SetPoint("CENTER")
	end
end

-- Confirm dialog before discarding an active scored game
if StaticPopupDialogs then
	StaticPopupDialogs["JEWELED_NEW_GAME"] = {
		text = "Start a new Jeweled game? Your current saved board will be replaced.",
		button1 = "New Game",
		button2 = "Cancel",
		OnAccept = function()
			UI.StartNewGame(ns.Taxi and ns.Taxi.IsFlying() and "flight" or "classic")
		end,
		timeout = 0,
		whileDead = true,
		hideOnEscape = true,
	}
end

function UI.ConfirmNewGame()
	if game and (game.moves or 0) > 0 and StaticPopup_Show then
		pcall(StaticPopup_Show, "JEWELED_NEW_GAME")
	else
		UI.StartNewGame(ns.Taxi and ns.Taxi.IsFlying() and "flight" or "classic")
	end
end

-- Dev helper: spawn shape-matched special gems across distinct cuts (Square, Triangle, Diamond, Prismatic)
function UI.SpawnDevSpecials()
	if not UI.IsShown() then UI.Show(false) end
	UI.EnsureGameLoaded()
	if not game or not game.grid then return end
	game.grid[4][2] = { t = 2, s = "B" } -- Burning Triangle Sapphire bomb
	game.grid[4][3] = { t = 1, s = "H" } -- Row-lightning Square Ruby
	game.grid[4][4] = { t = 4, s = "V" } -- Col-lightning Diamond Topaz
	game.grid[4][5] = { t = 5, s = "B" } -- Burning Pear Amethyst bomb
	game.grid[4][6] = { t = 0, s = "P" } -- Upright Prismatic orb
	ns.Grid.Render(game.grid)
	saveNow()
	ns.Print("Spawned shape-matched specials on row 4: [B] Flame Triangle, [H] Row Square, [V] Col Diamond, [B] Flame Pear, [P] Prismatic.")
end

-- Dev helper to preview every effect & sound in §5.5
function UI.RunDevFX()
	if not UI.IsShown() then UI.Show(false) end
	local sz = ns.Grid.GetBoardPixelSize()
	local cx, cy = sz * 0.5, -sz * 0.5
	ns.FX.PlayCascadeTier(3, cx, cy, 450)
	ns.FX.GemShatter(cx, cy, 0.96, 0.24, 0.30, 5)
	ns.Sound.PlayCascade(3)
	ns.Anim.Delay(0.6, function()
		ns.FX.Beam(true, cx, cy, sz)
		ns.Sound.PlaySpecial("H")
	end, "fx")
	ns.Anim.Delay(1.1, function()
		ns.FX.FireExplosion(cx, cy, ns.Grid.GetCellSize())
		ns.Sound.PlaySpecial("B")
	end, "fx")
	ns.Anim.Delay(1.6, function()
		ns.FX.BoardFlash(1, 1, 1, 0.28, 0.22)
		ns.FX.Bolt(cx, cy, 40, -40, 0, 1.0, 0.45, 0.55)
		ns.FX.Bolt(cx, cy, sz - 40, -40, 0.03, 1.0, 0.85, 0.35)
		ns.FX.Bolt(cx, cy, 40, -sz + 40, 0.06, 0.45, 0.95, 1.0)
		ns.FX.Bolt(cx, cy, sz - 40, -sz + 40, 0.09, 0.78, 0.52, 1.0)
		ns.Sound.PlaySpecial("P")
	end, "fx")
	ns.Anim.Delay(2.3, function()
		ns.FX.PlayNewRecord()
	end, "fx")
end

-- React to live settings changes
if ns.On then
	ns.On("SETTING_CHANGED", function(key)
		if key == "windowScale" then
			layoutWindow()
			if game and UI.IsShown() then ns.Grid.Render(game.grid) end
		elseif key == "gemSet" then
			if game and UI.IsShown() then ns.Grid.Render(game.grid) end
		elseif key == "background" then
			ns.Grid.ApplyBackground()
		elseif key == "sound" then
			updateSoundButtonLabel()
		elseif key == "showFps" then
			UI.UpdateScoreStrip()
			UI.RefreshFlightHudTicker()
		end
	end)
end
