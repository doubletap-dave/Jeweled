-- Minimap.lua: Hand-rolled draggable minimap button + right-click context menu.
-- Uses ONLY custom Jeweled icon art (zero Blizzard icon textures), following
-- Polestar_Arcade's angle & GetMinimapShape() positioning pattern.

local _, ns = ...

local MinimapBtn = {}
ns.Minimap = MinimapBtn

local button = nil
local menu = nil
local ROW_H, MENU_W = 20, 185

local function updatePosition()
	if not button or not Minimap then return end
	local angle = math.rad(ns.Get("minimapPos") or 220)
	local x, y = math.cos(angle), math.sin(angle)
	local shape = GetMinimapShape and GetMinimapShape() or "ROUND"
	if shape == "SQUARE" then
		x = math.max(-1, math.min(1, x * 1.42))
		y = math.max(-1, math.min(1, y * 1.42))
	end
	local w = Minimap:GetWidth() / 2 + 6
	local h = Minimap:GetHeight() / 2 + 6
	button:ClearAllPoints()
	button:SetPoint("CENTER", Minimap, "CENTER", x * w, y * h)
end

local function onDragUpdate()
	local mx, my = Minimap:GetCenter()
	local px, py = GetCursorPosition()
	local scale = Minimap:GetEffectiveScale()
	px, py = px / scale, py / scale
	local atan2 = math.atan2 or math.atan
	ns.Set("minimapPos", math.deg(atan2(py - my, px - mx)) % 360)
	updatePosition()
end

local function paintButtonTheme()
	if not button then return end
	local T = ns.Theme
	local pr, pg, pb = T.Color("panel")
	button._bg:SetColorTexture(pr, pg, pb, 0.96)
	local ar, ag, ab = T.Accent()
	T.ApplyBorder(button, ar, ag, ab, 0.85)
	if menu then
		T.PaintWindow(menu, true)
	end
end

local function showTooltip(self)
	if not GameTooltip then return end
	GameTooltip:SetOwner(self, "ANCHOR_LEFT")
	GameTooltip:AddLine("|cffe6ba66Jeweled|r")
	GameTooltip:AddLine("|cffffffffLeft-click|r to open or close", 0.8, 0.8, 0.8)
	GameTooltip:AddLine("|cffffffffRight-click|r for menu", 0.8, 0.8, 0.8)
	GameTooltip:AddLine("|cffffffffDrag|r to move this button", 0.8, 0.8, 0.8)
	GameTooltip:AddLine("/jeweled minimap hides it", 0.6, 0.6, 0.6)
	GameTooltip:Show()
end

local function buildMenuRows()
	local open = ns.UI and ns.UI.IsShown()
	return {
		{ kind = "title", text = "Jeweled" },
		{ kind = "item", text = open and "Close game" or "Open game", onClick = function() ns.UI.Toggle() end },
		{ kind = "item", text = "New game", onClick = function() ns.UI.Show(false); ns.UI.ConfirmNewGame() end },
		{ kind = "item", text = "Leaderboard", onClick = function() if ns.Ranks then ns.Ranks.Toggle() end end },
		{ kind = "item", text = "Achievements", onClick = function() if ns.Achieve then ns.Achieve.ToggleWindow() end end },
		{ kind = "item", text = "Settings", onClick = function() if ns.Options then ns.Options.Open() end end },
		{ kind = "item", text = "Hide minimap button", onClick = function() MinimapBtn.Toggle() end },
	}
end

local function createMenu()
	menu = CreateFrame("Frame", "JeweledMinimapMenu", UIParent)
	menu:SetFrameStrata("FULLSCREEN_DIALOG")
	menu:SetClampedToScreen(true)
	menu:EnableMouse(true)
	menu:Hide()
	ns.Theme.PaintWindow(menu, true)
	menu.rows = {}

	if UISpecialFrames then
		table.insert(UISpecialFrames, "JeweledMinimapMenu")
	end
	pcall(menu.RegisterEvent, menu, "GLOBAL_MOUSE_DOWN")
	menu:SetScript("OnEvent", function(self)
		if self:IsShown() and not self:IsMouseOver() and not (button and button:IsMouseOver()) then
			self:Hide()
		end
	end)
end

local function rowWidget(i)
	local r = menu.rows[i]
	if r then return r end
	r = CreateFrame("Button", nil, menu)
	r:SetHeight(ROW_H)
	r:SetPoint("TOPLEFT", menu, "TOPLEFT", 6, -6 - (i - 1) * ROW_H)
	r:SetPoint("RIGHT", menu, "RIGHT", -6, 0)
	local hl = r:CreateTexture(nil, "HIGHLIGHT")
	hl:SetAllPoints(r)
	local hr, hg, hb, ha = ns.Theme.Wash("hover")
	hl:SetColorTexture(hr, hg, hb, math.max(ha, 0.14))
	r.text = r:CreateFontString(nil, "OVERLAY", "GameFontNormal")
	r.text:SetPoint("LEFT", r, "LEFT", 6, 0)
	r.text:SetJustifyH("LEFT")
	r:SetScript("OnClick", function(self)
		if self.row and self.row.onClick then
			menu:Hide()
			if ns.Sound then ns.Sound.Play("click") end
			ns.Safe(self.row.onClick)()
		end
	end)
	menu.rows[i] = r
	return r
end

function MinimapBtn.ShowMenu()
	if not menu then createMenu() end
	ns.Theme.PaintWindow(menu, true)
	local rows = buildMenuRows()
	for i, row in ipairs(rows) do
		local w = rowWidget(i)
		w.row = row
		if row.kind == "title" then
			ns.Theme.ApplyFont(w.text, "heading", "accent")
			w.text:SetText(row.text)
			w:EnableMouse(false)
		else
			ns.Theme.ApplyFont(w.text, "label", "text")
			w.text:SetText(row.text)
			w:EnableMouse(true)
		end
		w:Show()
	end
	for i = #rows + 1, #menu.rows do
		menu.rows[i]:Hide()
	end
	menu:SetSize(MENU_W, #rows * ROW_H + 12)
	menu:ClearAllPoints()
	menu:SetPoint("TOPRIGHT", button, "BOTTOMLEFT", 8, 8)
	menu:Show()
end

function MinimapBtn.ToggleMenu()
	if menu and menu:IsShown() then menu:Hide() else MinimapBtn.ShowMenu() end
end

local function createButton()
	button = CreateFrame("Button", "JeweledMinimapButton", Minimap)
	button:SetSize(30, 30)
	button:SetFrameStrata("MEDIUM")
	button:SetFrameLevel(8)
	button:RegisterForClicks("LeftButtonUp", "RightButtonUp")
	button:RegisterForDrag("LeftButton")

	button._bg = button:CreateTexture(nil, "BACKGROUND")
	button._bg:SetAllPoints(button)

	local hl = button:CreateTexture(nil, "HIGHLIGHT")
	hl:SetAllPoints(button)
	hl:SetColorTexture(1, 0.9, 0.6, 0.18)

	local icon = button:CreateTexture(nil, "ARTWORK")
	icon:SetSize(22, 22)
	icon:SetPoint("CENTER", button, "CENTER", 0, 0)
	icon:SetTexture(ns.Art.ICON)
	button.icon = icon

	button:SetScript("OnClick", function(_, mouse)
		if mouse == "RightButton" then
			if GameTooltip then GameTooltip:Hide() end
			MinimapBtn.ToggleMenu()
		else
			if menu then menu:Hide() end
			if ns.Sound then ns.Sound.Play("click") end
			if ns.UI then ns.UI.Toggle() end
		end
	end)
	button:SetScript("OnDragStart", function(self)
		self:LockHighlight()
		self:SetScript("OnUpdate", onDragUpdate)
		if GameTooltip then GameTooltip:Hide() end
	end)
	button:SetScript("OnDragStop", function(self)
		self:SetScript("OnUpdate", nil)
		self:UnlockHighlight()
	end)
	button:SetScript("OnEnter", showTooltip)
	button:SetScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)
	button:SetScript("OnMouseDown", function() icon:SetSize(20, 20) end)
	button:SetScript("OnMouseUp", function() icon:SetSize(22, 22) end)

	ns.Theme.RegisterRepaint(paintButtonTheme)
	paintButtonTheme()
	updatePosition()
end

function MinimapBtn.Refresh()
	if not Minimap then return end
	if ns.Get("minimapHidden") then
		if button then button:Hide() end
		return
	end
	if not button then createButton() end
	updatePosition()
	button:Show()
end

function MinimapBtn.Toggle()
	local hide = not ns.Get("minimapHidden")
	ns.Set("minimapHidden", hide)
	MinimapBtn.Refresh()
	ns.Print("Minimap button " .. (hide and "hidden." or "shown."))
end

if ns.On then
	ns.On("LOGIN", function()
		MinimapBtn.Refresh()
	end)
	ns.On("SETTING_CHANGED", function(key)
		if key == "minimapHidden" or key == "minimapPos" then
			MinimapBtn.Refresh()
		end
	end)
end
