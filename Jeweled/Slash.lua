-- Slash.lua: Full slash command interface (/jeweled, /jwl) mirroring all settings
-- plus dev verification helpers (fps, devfx, comms, testart, testsave).

local _, ns = ...

local Slash = {}
ns.Slash = Slash

local testArtFrame = nil

local function toggleTestArt()
	if testArtFrame and testArtFrame:IsShown() then
		testArtFrame:Hide()
		return
	end
	if not testArtFrame then
		local f = CreateFrame("Frame", "JeweledTestArtFrame", UIParent)
		f:SetSize(520, 440)
		f:SetPoint("CENTER")
		f:SetFrameStrata("DIALOG")
		f:SetMovable(true)
		f:EnableMouse(true)
		f:RegisterForDrag("LeftButton")
		f:SetScript("OnDragStart", f.StartMoving)
		f:SetScript("OnDragStop", f.StopMovingOrSizing)
		f:SetClampedToScreen(true)
		if UISpecialFrames then
			table.insert(UISpecialFrames, "JeweledTestArtFrame")
		end
		ns.Theme.PaintWindow(f)

		local title = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
		title:SetPoint("TOPLEFT", 14, -12)
		ns.Theme.ApplyFont(title, "title", "accent")
		title:SetText("Jeweled — Custom Art Verification (26 TGAs)")

		local close = ns.Theme.CreateButton(f, "X", 24, 22, function() f:Hide() end, false)
		close:SetPoint("TOPRIGHT", -8, -8)

		local list = ns.Art.GetAllTextures()
		local cols = 6
		local cellW, cellH = 80, 74
		for i, item in ipairs(list) do
			local col = (i - 1) % cols
			local row = math.floor((i - 1) / cols)
			local x = 18 + col * cellW
			local y = -44 - row * cellH

			local well = f:CreateTexture(nil, "BORDER")
			well:SetSize(52, 52)
			well:SetPoint("TOPLEFT", x + 12, y)
			if item.label == "icon" then
				well:SetColorTexture(0.85, 0.85, 0.88, 1)
			else
				well:SetColorTexture(0.11, 0.14, 0.21, 1)
			end

			local tex = f:CreateTexture(nil, "ARTWORK")
			tex:SetSize(48, 48)
			tex:SetPoint("CENTER", well, "CENTER")
			tex:SetTexture(item.path)

			local lbl = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
			lbl:SetPoint("TOP", well, "BOTTOM", 0, -2)
			lbl:SetWidth(cellW - 4)
			ns.Theme.ApplyFont(lbl, "small", "textDim")
			lbl:SetText(item.label)
		end

		testArtFrame = f
	end
	testArtFrame:Show()
end

local function runTestSave(arg)
	local db = ns.DB()
	if not db then return end
	if arg == "clear" then
		ns.State.ClearGame()
		db.smokeToken = nil
		ns.Print("Persistence test state cleared.")
		return
	end
	local loaded, err = ns.State.LoadGame()
	if loaded and db.smokeToken then
		ns.Print(string.format(
			"PERSISTENCE OK! Restored saved board (score=%d, moves=%d, token=%s, board=%s...)",
			loaded.score, loaded.moves, tostring(db.smokeToken), db.game.board:sub(1, 16)
		))
		return
	elseif err then
		ns.Print("Previous save failed to decode: " .. tostring(err))
	end
	local st = ns.Board.NewState("classic")
	local hint = ns.Board.GetHint(st.grid)
	if hint then
		local ok = ns.Board.TrySwap(st, hint.r1, hint.c1, hint.r2, hint.c2)
		if ok then ns.Board.ResolveAll(st) end
	end
	ns.currentGame = st
	db.smokeToken = "JWL-" .. tostring(time and time() or 12345)
	ns.State.SaveGame(st)
	ns.Print(string.format(
		"Saved smoke-test board (score=%d, moves=%d, token=%s).",
		st.score, st.moves, db.smokeToken
	))
end

local function printHelp()
	ns.Print("v" .. ns.VERSION .. " — Commands (/jeweled or /jwl):")
	ns.Print("  /jeweled — Open or close the game window")
	ns.Print("  /jeweled new — Start a new game")
	ns.Print("  /jeweled auto — Toggle auto-open on flight paths")
	ns.Print("  /jeweled close — Toggle auto-close on landing")
	ns.Print("  /jeweled sound — Toggle sound effects")
	ns.Print("  /jeweled fx — Toggle effects (full / reduced)")
	ns.Print("  /jeweled shake — Toggle screen shake")
	ns.Print("  /jeweled minimap — Show or hide minimap button")
	ns.Print("  /jeweled board — Open the leaderboard window")
	ns.Print("  /jeweled network [on|off] — Toggle leaderboard network sharing")
	ns.Print("  /jeweled ranks — Print your global and guild standings")
	ns.Print("  /jeweled scores — Print your flight route scorebook")
	ns.Print("  /jeweled size <small|medium|large> — Change window size preset")
	ns.Print("  /jeweled reset [all] — Reset window position (or all settings)")
	ns.Print("  /jeweled help — List commands")
end

local function toggleBool(key, label)
	local val = not (ns.Get(key) == true)
	ns.Set(key, val)
	ns.Print(label .. ": " .. (val and "ON" or "OFF"))
end

function Slash.Handle(msg)
	local raw = tostring(msg or ""):match("^%s*(.-)%s*$")
	local cmd, rest = raw:match("^(%S+)%s*(.-)$")
	cmd = (cmd or ""):lower()
	rest = (rest or ""):lower()

	if cmd == "" then
		if ns.UI then ns.UI.Toggle() end
	elseif cmd == "new" then
		if ns.UI then
			ns.UI.Show(false)
			ns.UI.ConfirmNewGame()
		end
	elseif cmd == "auto" then
		toggleBool("autoOpen", "Auto-open on flight paths")
	elseif cmd == "close" then
		toggleBool("autoClose", "Auto-close on landing")
	elseif cmd == "sound" then
		toggleBool("sound", "Sound effects")
	elseif cmd == "fx" then
		local nextMode = ns.Get("fx") == "full" and "reduced" or "full"
		ns.Set("fx", nextMode)
		ns.Print("Visual effects: " .. nextMode)
	elseif cmd == "shake" then
		toggleBool("shake", "Screen shake")
	elseif cmd == "minimap" then
		if ns.Minimap then ns.Minimap.Toggle() end
	elseif cmd == "board" or cmd == "leaderboard" then
		if ns.Ranks then ns.Ranks.Toggle() end
	elseif cmd == "network" then
		local want
		if rest == "on" then want = true
		elseif rest == "off" then want = false
		else want = not (ns.Get("network") ~= false) end
		ns.Set("network", want)
		if ns.Comms and ns.Comms.SetNetworkEnabled then
			ns.Comms.SetNetworkEnabled(want)
		end
		ns.Print("Leaderboard network sharing: " .. (want and "ON (joined jeweledsync)" or "OFF (local data only)"))
	elseif cmd == "ranks" then
		if ns.Ranks and ns.Ranks.PrintStandings then
			ns.Ranks.PrintStandings()
		end
	elseif cmd == "scores" then
		if ns.Taxi and ns.Taxi.PrintRouteScores then
			ns.Taxi.PrintRouteScores()
		end
	elseif cmd == "size" then
		if rest == "small" or rest == "medium" or rest == "large" then
			ns.Set("windowScale", rest)
			ns.Print("Window size set to: " .. rest)
		else
			ns.Print("Usage: /jeweled size small | medium | large")
		end
	elseif cmd == "reset" then
		if rest == "all" then
			if ns.Options and ns.Options.ConfirmResetAll then
				ns.Options.ConfirmResetAll()
			end
		else
			if ns.UI then ns.UI.ResetPosition() end
			ns.Print("Window position reset to center. Use '/jeweled reset all' to reset all settings.")
		end
	elseif cmd == "fps" then
		toggleBool("showFps", "Dev FPS/FX overlay")
	elseif cmd == "comms" then
		if ns.Comms and ns.Comms.DumpLog then ns.Comms.DumpLog() end
	elseif _G.JEWELED_DEV and cmd == "devfx" then
		if ns.UI then ns.UI.RunDevFX() end
	elseif _G.JEWELED_DEV and cmd == "devspecials" then
		if ns.UI then ns.UI.SpawnDevSpecials() end
	elseif _G.JEWELED_DEV and cmd == "autoplay" then
		if ns.UI then ns.UI.ToggleAutoPlay() end
	elseif _G.JEWELED_DEV and cmd == "testart" then
		toggleTestArt()
	elseif _G.JEWELED_DEV and cmd == "testsave" then
		runTestSave(rest)
	elseif cmd == "help" then
		printHelp()
	else
		ns.Print("Unknown command: " .. cmd)
		printHelp()
	end
end

SLASH_JEWELED1 = "/jeweled"
SLASH_JEWELED2 = "/jwl"
if SlashCmdList then
	SlashCmdList["JEWELED"] = function(msg)
		ns.Safe(Slash.Handle)(msg)
	end
end
