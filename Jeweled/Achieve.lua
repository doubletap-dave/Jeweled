-- Achieve.lua: 18 data-driven achievements (§5.2), gold chat-free unlock toasts,
-- reward unlocks (Deep Mine, Arcane Vault, Polestar gem set), and Achievements window.

local _, ns = ...

local Achieve = {}
ns.Achieve = Achieve

Achieve.LIST = {
	{ id = "first_facet",    name = "First Facet",    desc = "Make your first match",              gem = 1 },
	{ id = "getting_warm",   name = "Getting Warm",   desc = "Trigger a x3 cascade",               gem = 4 },
	{ id = "critical_match", name = "Critical Match", desc = "Trigger a x5 cascade",               gem = 1 },
	{ id = "line_driver",    name = "Line Driver",    desc = "Create your first line-clear gem",   gem = 2 },
	{ id = "blast_radius",   name = "Blast Radius",   desc = "Create your first blast gem",        gem = 5 },
	{ id = "prismatic",      name = "Prismatic",      desc = "Create your first color-clear gem",  gem = 6 },
	{ id = "ten_thousand",   name = "Ten Thousand",   desc = "Score 10,000 in one game",           gem = 3 },
	{ id = "six_figures",    name = "Six Figures",    desc = "Score 100,000 in one game",          gem = 3 },
	{ id = "millionaire",    name = "Millionaire",    desc = "Score 1,000,000 in one game",        gem = 5 },
	{ id = "frequent_flyer", name = "Frequent Flyer", desc = "Play on 10 flights",                 gem = 2 },
	{ id = "sky_captain",    name = "Sky Captain",    desc = "Play on 100 flights",                gem = 4, rewardType = "gemSet",     rewardId = "polestar",    rewardLabel = "Polestar gem set" },
	{ id = "route_runner",   name = "Route Runner",   desc = "Hold a route best on 5 routes",      gem = 2 },
	{ id = "cartographer",   name = "Cartographer",   desc = "Hold a route best on 15 routes",     gem = 6 },
	{ id = "on_a_roll",      name = "On a Roll",      desc = "Reach a 3-flight best streak",       gem = 4 },
	{ id = "untouchable",    name = "Untouchable",    desc = "Reach a 7-flight best streak",       gem = 1 },
	{ id = "guild_champion", name = "Guild Champion", desc = "Reach #1 on your guild leaderboard", gem = 4 },
	{ id = "world_stage",    name = "World Stage",    desc = "Reach the global top 100",           gem = 2 },
	{ id = "crown_jeweled",  name = "Crown Jeweled",  desc = "Reach global #1",                    gem = 6 },
}

local BY_ID = {}
for _, a in ipairs(Achieve.LIST) do
	BY_ID[a.id] = a
end

local toastFrame = nil
local toastQueue = {}
local toastShowing = false
local achieveWin = nil
local achieveRows = {}

local function showNextToast()
	if toastShowing or #toastQueue == 0 then return end
	local item = table.remove(toastQueue, 1)
	toastShowing = true

	if not toastFrame then
		local f = CreateFrame("Frame", "JeweledAchieveToast", UIParent)
		f:SetSize(280, 56)
		f:SetFrameStrata("FULLSCREEN_DIALOG")
		f:Hide()
		ns.Theme.PaintWindow(f, true)
		local ar, ag, ab = ns.Theme.Accent()
		ns.Theme.ApplyBorder(f, ar, ag, ab, 0.95)

		local badge = f:CreateTexture(nil, "ARTWORK")
		badge:SetSize(38, 38)
		badge:SetPoint("LEFT", f, "LEFT", 10, 0)
		badge:SetTexture(ns.Art.FX.badge)
		f.badge = badge

		local gem = f:CreateTexture(nil, "ARTWORK", nil, 1)
		gem:SetSize(22, 22)
		gem:SetPoint("CENTER", badge, "CENTER")
		f.gem = gem

		local hdr = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
		hdr:SetPoint("TOPLEFT", badge, "TOPRIGHT", 10, -4)
		ns.Theme.ApplyFont(hdr, "caption", "accent")
		hdr:SetText("ACHIEVEMENT UNLOCKED")
		f.hdr = hdr

		local nameFS = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
		nameFS:SetPoint("TOPLEFT", hdr, "BOTTOMLEFT", 0, -2)
		ns.Theme.ApplyFont(nameFS, "heading", "text")
		f.nameFS = nameFS

		toastFrame = f
	end

	toastFrame.gem:SetTexture(ns.Art.GetGemTexture("azeroth", item.gem or 1))
	toastFrame.nameFS:SetText(item.rewardLabel and (item.name .. " — " .. item.rewardLabel) or item.name)
	toastFrame:ClearAllPoints()
	local anchor = (ns.UI and ns.UI.IsShown() and _G.JeweledMainFrame) or UIParent
	toastFrame:SetPoint("TOP", anchor, "TOP", 0, 24)
	toastFrame:SetAlpha(0)
	toastFrame:Show()

	if ns.Sound then ns.Sound.Play("achievement") end

	ns.Anim.Tween(0.28, function(t)
		toastFrame:SetAlpha(t)
		toastFrame:ClearAllPoints()
		toastFrame:SetPoint("TOP", anchor, "TOP", 0, 24 - 34 * t)
	end, function()
		ns.Anim.Delay(2.6, function()
			ns.Anim.Tween(0.25, function(t)
				toastFrame:SetAlpha(1 - t)
			end, function()
				toastFrame:Hide()
				toastShowing = false
				showNextToast()
			end, ns.Anim.EaseOutQuad, 0, "toast")
		end, "toast")
	end, ns.Anim.EaseOutQuad, 0, "toast")
end

function Achieve.IsUnlocked(id)
	local db = ns.DB()
	return db and db.achievements and db.achievements[id] ~= nil
end

function Achieve.Unlock(id)
	local def = BY_ID[id]
	local db = ns.DB()
	if not def or not db then return false end
	if db.achievements[id] then return false end

	db.achievements[id] = time and time() or 1
	if def.rewardType == "background" and def.rewardId then
		db.unlocked.backgrounds[def.rewardId] = true
	elseif def.rewardType == "gemSet" and def.rewardId then
		db.unlocked.gemSets[def.rewardId] = true
	end

	toastQueue[#toastQueue + 1] = def
	showNextToast()
	if achieveWin and achieveWin:IsShown() then
		Achieve.RefreshWindow()
	end
	return true
end

function Achieve.OnStep(game, step)
	if not game or not step then return end
	if #(step.cleared or {}) > 0 then Achieve.Unlock("first_facet") end
	if (step.cascade or 0) >= 3 then Achieve.Unlock("getting_warm") end
	if (step.cascade or 0) >= 5 then Achieve.Unlock("critical_match") end

	for _, sp in ipairs(step.createdSpecials or {}) do
		if sp.s == "H" or sp.s == "V" then
			Achieve.Unlock("line_driver")
		elseif sp.s == "B" then
			Achieve.Unlock("blast_radius")
		elseif sp.s == "P" then
			Achieve.Unlock("prismatic")
		end
	end

	local sc = game.score or 0
	if sc >= 10000 then Achieve.Unlock("ten_thousand") end
	if sc >= 100000 then Achieve.Unlock("six_figures") end
	if sc >= 1000000 then Achieve.Unlock("millionaire") end
end

function Achieve.OnFlightLand(db, routeCount)
	if not db then return end
	local flights = db.best and db.best.flights or 0
	local streak = db.best and db.best.bestStreak or 0
	if flights >= 10 then Achieve.Unlock("frequent_flyer") end
	if flights >= 100 then Achieve.Unlock("sky_captain") end
	if (routeCount or 0) >= 5 then Achieve.Unlock("route_runner") end
	if (routeCount or 0) >= 15 then Achieve.Unlock("cartographer") end
	if streak >= 3 then Achieve.Unlock("on_a_roll") end
	if streak >= 7 then Achieve.Unlock("untouchable") end
end

function Achieve.OnRankUpdate(globalRank, guildRank)
	if guildRank and guildRank == 1 then Achieve.Unlock("guild_champion") end
	if globalRank and globalRank <= 100 then Achieve.Unlock("world_stage") end
	if globalRank and globalRank == 1 then Achieve.Unlock("crown_jeweled") end
end

-- Achievements gallery window
function Achieve.RefreshWindow()
	if not achieveWin then return end
	local db = ns.DB()
	local earned = 0
	for i, def in ipairs(Achieve.LIST) do
		local ts = db and db.achievements and db.achievements[def.id]
		if ts then earned = earned + 1 end
		local row = achieveRows[i]
		if row then
			row.gem:SetTexture(ns.Art.GetGemTexture("azeroth", def.gem or 1))
			row.gem:SetAlpha(ts and 1.0 or 0.25)
			row.badge:SetAlpha(ts and 1.0 or 0.25)
			row.nameFS:SetText(def.name)
			ns.Theme.ApplyFont(row.nameFS, "label", ts and "accent" or "textMuted")
			local desc = def.desc
			if def.rewardLabel then
				desc = desc .. "  |cffe6ba66[" .. def.rewardLabel .. "]|r"
			end
			row.descFS:SetText(desc)
			ns.Theme.ApplyFont(row.descFS, "small", ts and "text" or "textMuted")
			row.statusFS:SetText(ts and "|cff6bd999Earned|r" or "Locked")
			ns.Theme.ApplyFont(row.statusFS, "caption", ts and "success" or "textMuted")
		end
	end
	achieveWin.countFS:SetText(string.format("%d / %d Earned", earned, #Achieve.LIST))
end

local function createAchieveWindow()
	local f = CreateFrame("Frame", "JeweledAchieveFrame", UIParent)
	f:SetSize(440, 480)
	f:SetPoint("CENTER")
	f:SetFrameStrata("DIALOG")
	f:SetMovable(true)
	f:EnableMouse(true)
	f:RegisterForDrag("LeftButton")
	f:SetScript("OnDragStart", f.StartMoving)
	f:SetScript("OnDragStop", f.StopMovingOrSizing)
	f:SetClampedToScreen(true)
	f:Hide()
	if UISpecialFrames then
		table.insert(UISpecialFrames, "JeweledAchieveFrame")
	end

	local hdrBg = f:CreateTexture(nil, "BACKGROUND", nil, -4)
	hdrBg:SetHeight(36)
	hdrBg:SetPoint("TOPLEFT", f, "TOPLEFT", 1, -1)
	hdrBg:SetPoint("TOPRIGHT", f, "TOPRIGHT", -1, -1)
	f.hdrBg = hdrBg

	local title = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
	title:SetPoint("TOPLEFT", f, "TOPLEFT", 14, -12)
	title:SetText("Jeweled — Achievements")
	f.title = title

	local countFS = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
	countFS:SetPoint("TOPRIGHT", f, "TOPRIGHT", -44, -14)
	f.countFS = countFS

	local close = ns.Theme.CreateButton(f, "X", 24, 22, function() f:Hide() end, false)
	close:SetPoint("TOPRIGHT", f, "TOPRIGHT", -8, -8)
	f.close = close

	local listWell = CreateFrame("Frame", nil, f)
	listWell:SetPoint("TOPLEFT", f, "TOPLEFT", 10, -40)
	listWell:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -10, 12)
	listWell._bg = listWell:CreateTexture(nil, "BACKGROUND", nil, -3)
	listWell._bg:SetAllPoints(listWell)
	f.listWell = listWell

	local scroll = CreateFrame("ScrollFrame", "JeweledAchieveScroll", listWell, "UIPanelScrollFrameTemplate")
	scroll:SetPoint("TOPLEFT", listWell, "TOPLEFT", 6, -6)
	scroll:SetPoint("BOTTOMRIGHT", listWell, "BOTTOMRIGHT", -26, 6)

	local content = CreateFrame("Frame", nil, scroll)
	content:SetSize(382, #Achieve.LIST * 42)
	scroll:SetScrollChild(content)

	for i, _ in ipairs(Achieve.LIST) do
		local row = CreateFrame("Frame", nil, content)
		row:SetSize(382, 38)
		row:SetPoint("TOPLEFT", content, "TOPLEFT", 0, -(i - 1) * 42)
		row._bg = row:CreateTexture(nil, "BACKGROUND")
		row._bg:SetAllPoints(row)

		local badge = row:CreateTexture(nil, "ARTWORK")
		badge:SetSize(30, 30)
		badge:SetPoint("LEFT", row, "LEFT", 6, 0)
		badge:SetTexture(ns.Art.FX.badge)
		row.badge = badge

		local gem = row:CreateTexture(nil, "ARTWORK", nil, 1)
		gem:SetSize(18, 18)
		gem:SetPoint("CENTER", badge, "CENTER")
		row.gem = gem

		local nameFS = row:CreateFontString(nil, "OVERLAY", "GameFontNormal")
		nameFS:SetPoint("TOPLEFT", badge, "TOPRIGHT", 8, -2)
		row.nameFS = nameFS

		local descFS = row:CreateFontString(nil, "OVERLAY", "GameFontNormal")
		descFS:SetPoint("BOTTOMLEFT", badge, "BOTTOMRIGHT", 8, 2)
		row.descFS = descFS

		local statusFS = row:CreateFontString(nil, "OVERLAY", "GameFontNormal")
		statusFS:SetPoint("RIGHT", row, "RIGHT", -10, 0)
		row.statusFS = statusFS

		achieveRows[i] = row
	end

	local function paint()
		ns.Theme.PaintWindow(f, true)
		local sr, sg, sb = ns.Theme.Color("sky")
		f.hdrBg:SetColorTexture(sr, sg, sb, 0.98)
		local wr, wg, wb = ns.Theme.Color("sidebar")
		f.listWell._bg:SetColorTexture(wr, wg, wb, 0.96)
		local br, bg, bb, ba = ns.Theme.Wash("border")
		ns.Theme.ApplyBorder(f.listWell, br, bg, bb, math.max(ba, 0.16))
		ns.Theme.ApplyFont(f.title, "title", "accent")
		ns.Theme.ApplyFont(f.countFS, "label", "textDim")
		ns.Theme.PaintButton(f.close, false)
		local pr, pg, pb = ns.Theme.Color("panel")
		for _, r in ipairs(achieveRows) do
			r._bg:SetColorTexture(pr, pg, pb, 0.96)
		end
		Achieve.RefreshWindow()
	end

	ns.Theme.RegisterRepaint(paint)
	f:SetScript("OnShow", paint)
	paint()
	achieveWin = f
end

function Achieve.ToggleWindow()
	if not achieveWin then createAchieveWindow() end
	if achieveWin:IsShown() then
		achieveWin:Hide()
	else
		achieveWin:Show()
	end
end
