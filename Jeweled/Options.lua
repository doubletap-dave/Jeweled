-- Options.lua: Live side-by-side Jeweled Settings window (never closes the game
-- window so background/gem-set/scale/FX changes preview live!) PLUS the standard
-- Options > AddOns > Jeweled Blizzard Settings entry.

local _, ns = ...

local Options = {}
ns.Options = Options

local category = nil
local blizzCanvas = nil
local optWin = nil
local controls = {}

local function makeCheckbox(parent, label, x, y, maxWidth, getFn, setFn)
	local cb = CreateFrame("CheckButton", nil, parent, "UICheckButtonTemplate")
	cb:SetSize(24, 24)
	cb:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y)
	local fs = cb:CreateFontString(nil, "OVERLAY", "GameFontNormal")
	fs:SetPoint("LEFT", cb, "RIGHT", 6, 0)
	fs:SetWidth(maxWidth or 360)
	fs:SetJustifyH("LEFT")
	if fs.SetWordWrap then fs:SetWordWrap(true) end
	fs:SetText(label)
	ns.Theme.ApplyFont(fs, "body", "text")
	cb._label = fs
	cb._get = getFn
	cb:SetScript("OnClick", function(self)
		local checked = self:GetChecked() and true or false
		if ns.Sound then ns.Sound.Play("click") end
		setFn(checked)
	end)
	controls[#controls + 1] = cb
	return cb
end

local function makeCycleButton(parent, prefix, x, y, width, getLabelFn, onClickFn)
	local btn = ns.Theme.CreateButton(parent, "", width, 24, function(self)
		onClickFn()
		self._jwlLabel:SetText(prefix .. ": " .. getLabelFn())
	end, false)
	btn:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y)
	btn._refresh = function()
		btn._jwlLabel:SetText(prefix .. ": " .. getLabelFn())
	end
	controls[#controls + 1] = btn
	return btn
end

function Options.Refresh()
	for _, c in ipairs(controls) do
		if c._get and c.SetChecked then
			c:SetChecked(c._get() and true or false)
		elseif c._refresh then
			c._refresh()
		end
	end
end

local function cycleScale()
	local order = { "small", "medium", "large" }
	local cur = ns.Get("windowScale") or "medium"
	local idx = 1
	for i, v in ipairs(order) do
		if v == cur then idx = i; break end
	end
	ns.Set("windowScale", order[(idx % #order) + 1])
end

local function cycleGemSet()
	local db = ns.DB()
	local unlocked = db and db.unlocked and db.unlocked.gemSets or { azeroth = true }
	local avail = {}
	for _, id in ipairs(ns.Art.GEM_SET_ORDER) do
		if unlocked[id] then avail[#avail + 1] = id end
	end
	if #avail <= 1 then
		ns.Print("Unlock the Polestar gem pack with the Sky Captain achievement (100 flights)!")
		return
	end
	local cur = ns.Get("gemSet") or "azeroth"
	local idx = 1
	for i, id in ipairs(avail) do
		if id == cur then idx = i; break end
	end
	ns.Set("gemSet", avail[(idx % #avail) + 1])
end

local function cycleBackground()
	local avail = ns.Art.BACKGROUND_ORDER
	local cur = ns.Get("background") or "nightsky"
	local idx = 1
	for i, id in ipairs(avail) do
		if id == cur then idx = i; break end
	end
	ns.Set("background", avail[(idx % #avail) + 1])
end

if StaticPopupDialogs then
	StaticPopupDialogs["JEWELED_RESET_ALL"] = {
		text = "Reset all Jeweled settings to defaults? (Your high scores and achievements will be kept.)",
		button1 = "Reset Settings",
		button2 = "Cancel",
		OnAccept = function()
			for k in pairs(ns.DEFAULTS) do
				ns.Set(k, ns.DEFAULTS[k])
			end
			if ns.UI then ns.UI.ResetPosition() end
			Options.Refresh()
			ns.Print("All settings reset to defaults.")
		end,
		timeout = 0,
		whileDead = true,
		hideOnEscape = true,
	}
end

function Options.ConfirmResetAll()
	if StaticPopup_Show then
		pcall(StaticPopup_Show, "JEWELED_RESET_ALL")
	end
end

local PRIVACY_TEXT =
	"When enabled, Jeweled joins hidden channel 'jeweledsync' and shares only your character GUID, name, best score, " ..
	"best pts/sec, games played, route names, and timestamps. BattleTag, account info, guild name, class, level, and " ..
	"chat are never sent. Channel traffic is unencrypted. Turn off anytime with /jeweled network off."

-- Shared control builder used by both the live side-by-side Options window and Blizzard Settings
local function populateOptions(parent, startY, width)
	local y = startY
	local step = -28
	local labelW = width - 58

	makeCheckbox(parent, "Auto-open on flight paths", 14, y, labelW,
		function() return ns.Get("autoOpen") == true end,
		function(v) ns.Set("autoOpen", v) end); y = y + step

	makeCheckbox(parent, "Auto-close on landing", 14, y, labelW,
		function() return ns.Get("autoClose") ~= false end,
		function(v) ns.Set("autoClose", v) end); y = y + step

	makeCheckbox(parent, "Sound effects", 14, y, labelW,
		function() return ns.Get("sound") ~= false end,
		function(v) ns.Set("sound", v) end); y = y + step

	makeCheckbox(parent, "Full visual effects (uncheck for reduced)", 14, y, labelW,
		function() return ns.Get("fx") ~= "reduced" end,
		function(v) ns.Set("fx", v and "full" or "reduced") end); y = y + step

	makeCheckbox(parent, "Screen shake on big cascades & blasts", 14, y, labelW,
		function() return ns.Get("shake") ~= false end,
		function(v) ns.Set("shake", v) end); y = y + step

	makeCheckbox(parent, "Show minimap button", 14, y, labelW,
		function() return not ns.Get("minimapHidden") end,
		function(v) ns.Set("minimapHidden", not v) end); y = y + step

	makeCheckbox(parent, "Auto-open on death (opt-in)", 14, y, labelW,
		function() return ns.Get("autoOpenOnDeath") == true end,
		function(v) ns.Set("autoOpenOnDeath", v) end); y = y + step

	makeCheckbox(parent, "Share scores on realm & guild leaderboard", 14, y, labelW,
		function() return ns.Get("network") ~= false end,
		function(v)
			ns.Set("network", v)
			if ns.Comms and ns.Comms.SetNetworkEnabled then ns.Comms.SetNetworkEnabled(v) end
		end); y = y + step - 8

	-- Live appearance pickers
	local btnW = math.floor((width - 38) / 2)
	makeCycleButton(parent, "Background", 14, y, btnW,
		function() return ns.Art.GetBackground(ns.Get("background")).name end,
		cycleBackground)

	makeCycleButton(parent, "Gem Pack", 24 + btnW, y, btnW,
		function() return ns.Art.GetGemSet(ns.Get("gemSet")).name end,
		cycleGemSet)
	y = y - 34

	makeCycleButton(parent, "Window Size", 14, y, btnW,
		function() return tostring(ns.Get("windowScale") or "medium") end,
		cycleScale)

	local resetBtn = ns.Theme.CreateButton(parent, "Reset Settings", btnW, 24, function()
		Options.ConfirmResetAll()
	end, false)
	resetBtn:SetPoint("TOPLEFT", parent, "TOPLEFT", 24 + btnW, y)
	y = y - 38

	-- Inset privacy disclosure card
	local privBox = CreateFrame("Frame", nil, parent)
	privBox:SetPoint("TOPLEFT", parent, "TOPLEFT", 14, y)
	privBox:SetSize(width - 28, 108)
	local pbg = privBox:CreateTexture(nil, "BACKGROUND")
	pbg:SetAllPoints(privBox)
	local pr, pg, pb = ns.Theme.Color("panel")
	pbg:SetColorTexture(pr, pg, pb, 0.90)
	local br, bgg, bb, ba = ns.Theme.Wash("border")
	ns.Theme.ApplyBorder(privBox, br, bgg, bb, math.max(ba, 0.16))

	local privHdr = privBox:CreateFontString(nil, "OVERLAY", "GameFontNormal")
	privHdr:SetPoint("TOPLEFT", privBox, "TOPLEFT", 10, -8)
	ns.Theme.ApplyFont(privHdr, "label", "accent")
	privHdr:SetText("Leaderboard Privacy")

	local privBody = privBox:CreateFontString(nil, "OVERLAY", "GameFontNormal")
	privBody:SetPoint("TOPLEFT", privHdr, "BOTTOMLEFT", 0, -4)
	privBody:SetPoint("RIGHT", privBox, "RIGHT", -10, 0)
	privBody:SetJustifyH("LEFT")
	if privBody.SetWordWrap then privBody:SetWordWrap(true) end
	ns.Theme.ApplyFont(privBody, "small", "textDim")
	privBody:SetText(PRIVACY_TEXT)
end

-- Live side-by-side Options window (never closes JeweledMainFrame!)
local function createOptionsWindow()
	local W, H = 450, 496
	local f = CreateFrame("Frame", "JeweledOptionsFrame", UIParent)
	f:SetSize(W, H)
	f:SetPoint("CENTER", 260, 0)
	f:SetFrameStrata("DIALOG")
	f:SetMovable(true)
	f:EnableMouse(true)
	f:RegisterForDrag("LeftButton")
	f:SetScript("OnDragStart", f.StartMoving)
	f:SetScript("OnDragStop", f.StopMovingOrSizing)
	f:SetClampedToScreen(true)
	f:Hide()
	if UISpecialFrames then
		table.insert(UISpecialFrames, "JeweledOptionsFrame")
	end

	local hdrBg = f:CreateTexture(nil, "BACKGROUND", nil, -4)
	hdrBg:SetHeight(34)
	hdrBg:SetPoint("TOPLEFT", f, "TOPLEFT", 1, -1)
	hdrBg:SetPoint("TOPRIGHT", f, "TOPRIGHT", -1, -1)
	f.hdrBg = hdrBg

	local title = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
	title:SetPoint("TOPLEFT", f, "TOPLEFT", 14, -10)
	title:SetText("Jeweled — Settings")
	f.title = title

	local close = ns.Theme.CreateButton(f, "X", 24, 22, function() f:Hide() end, false)
	close:SetPoint("TOPRIGHT", f, "TOPRIGHT", -8, -6)
	f.close = close

	populateOptions(f, -44, W)

	local function paint()
		ns.Theme.PaintWindow(f, true)
		local sr, sg, sb = ns.Theme.Color("sky")
		f.hdrBg:SetColorTexture(sr, sg, sb, 0.98)
		ns.Theme.ApplyFont(f.title, "title", "accent")
		ns.Theme.PaintButton(f.close, false)
		Options.Refresh()
	end

	ns.Theme.RegisterRepaint(paint)
	f:SetScript("OnShow", paint)
	paint()
	optWin = f
end

-- Toggle live side-by-side settings window right next to the game board
function Options.Open()
	if not optWin then createOptionsWindow() end
	if optWin:IsShown() then
		optWin:Hide()
		return
	end
	local main = _G and _G.JeweledMainFrame
	if main and main:IsShown() then
		optWin:ClearAllPoints()
		optWin:SetPoint("TOPLEFT", main, "TOPRIGHT", 10, 0)
	end
	optWin:Show()
end

-- Blizzard Options > AddOns > Jeweled canvas
local function buildBlizzCanvas()
	blizzCanvas = CreateFrame("Frame")
	blizzCanvas:Hide()

	local title = blizzCanvas:CreateFontString(nil, "OVERLAY", "GameFontNormal")
	title:SetPoint("TOPLEFT", 16, -16)
	ns.Theme.ApplyFont(title, "display", "accent")
	title:SetText("Jeweled")

	local sub = blizzCanvas:CreateFontString(nil, "OVERLAY", "GameFontNormal")
	sub:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -4)
	ns.Theme.ApplyFont(sub, "note", "textDim")
	sub:SetText("Tip: Click 'Options' inside the Jeweled game window to tweak backgrounds & settings live beside your board.")

	populateOptions(blizzCanvas, -70, 520)
	blizzCanvas:SetScript("OnShow", Options.Refresh)
	return blizzCanvas
end

if ns.On then
	ns.On("INIT", function()
		if not (Settings and Settings.RegisterCanvasLayoutCategory and Settings.RegisterAddOnCategory) then
			return
		end
		buildBlizzCanvas()
		local ok, cat = pcall(Settings.RegisterCanvasLayoutCategory, blizzCanvas, "Jeweled")
		if ok and cat then
			pcall(Settings.RegisterAddOnCategory, cat)
			category = cat
		end
	end)
	ns.On("SETTING_CHANGED", function()
		if (optWin and optWin:IsShown()) or (blizzCanvas and blizzCanvas:IsShown()) then
			Options.Refresh()
		end
	end)
end
