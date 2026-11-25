-- Theme.lua: Live Polestar.Theme API v2 reader with bundled Night-scheme fallback.
-- Reads colors, washes, fonts, pixel scale, and motion preference from Polestar
-- when loaded, and repaints all registered Jeweled frames on Polestar theme changes.

local _, ns = ...

local Theme = {}
ns.Theme = Theme

-- Bundled Night-scheme house tokens (fallback when Polestar is not loaded)
local FALLBACK_COLORS = {
	bg        = { 0.039, 0.051, 0.086, 0.97 },
	panel     = { 0.051, 0.066, 0.110, 0.98 },
	panelAlt  = { 0.075, 0.094, 0.149, 1.00 },
	sidebar   = { 0.027, 0.035, 0.063, 1.00 },
	footer    = { 0.031, 0.040, 0.071, 1.00 },
	sky       = { 0.075, 0.106, 0.200, 1.00 },
	text      = { 0.960, 0.970, 0.990, 1.00 },
	textDim   = { 0.690, 0.720, 0.800, 1.00 },
	textMuted = { 0.500, 0.540, 0.630, 1.00 },
	ink       = { 1.000, 1.000, 1.000, 1.00 },
	shade     = { 0.000, 0.000, 0.020, 1.00 },
	scrim     = { 0.020, 0.030, 0.060, 1.00 },
	onAccent  = { 0.040, 0.050, 0.080, 1.00 },
	shadow    = { 0.000, 0.000, 0.020, 0.60 },
	success   = { 0.420, 0.850, 0.600, 1.00 },
	warning   = { 0.980, 0.750, 0.300, 1.00 },
	danger    = { 0.960, 0.450, 0.450, 1.00 },
	quest     = { 1.000, 0.840, 0.450, 1.00 },
	rare      = { 1.000, 0.500, 0.320, 1.00 },
}

local FALLBACK_ACCENT = { 0.90, 0.73, 0.40 }

local FALLBACK_WASHES = {
	border   = 0.12,
	divider  = 0.10,
	hover    = 0.08,
	selected = 0.14,
	track    = 0.12,
	progress = 0.08,
	chip     = 0.08,
}

local FALLBACK_ROLES = {
	hero    = 24,
	display = 18,
	title   = 15,
	heading = 13,
	body    = 13,
	label   = 12,
	note    = 12,
	small   = 11,
	number  = 12,
	caption = 11,
}

local function polestarTheme()
	local P = _G and _G.Polestar
	local PT = P and P.Theme
	if PT and (PT.API_VERSION or 0) >= 2 then
		return PT
	end
	return nil
end

function Theme.HasPolestar()
	return polestarTheme() ~= nil
end

function Theme.Color(token)
	local PT = polestarTheme()
	if PT and PT.Color then
		local ok, r, g, b, a = pcall(PT.Color, token)
		if ok and r then
			return r, g, b, a or 1
		end
	end
	local c = FALLBACK_COLORS[token] or FALLBACK_COLORS.text
	return c[1], c[2], c[3], c[4] or 1
end

function Theme.Accent()
	local PT = polestarTheme()
	if PT and PT.Accent then
		local ok, r, g, b = pcall(PT.Accent)
		if ok and r then
			return r, g, b, 1
		end
	end
	return FALLBACK_ACCENT[1], FALLBACK_ACCENT[2], FALLBACK_ACCENT[3], 1
end

function Theme.Wash(name)
	local PT = polestarTheme()
	if PT and PT.Wash then
		local ok, r, g, b, a = pcall(PT.Wash, name)
		if ok and r then
			return r, g, b, a or 0.12
		end
	end
	local ir, ig, ib = Theme.Color("ink")
	return ir, ig, ib, FALLBACK_WASHES[name] or 0.12
end

function Theme.GroundAlpha()
	local PT = polestarTheme()
	if PT and PT.GroundAlpha then
		local ok, a = pcall(PT.GroundAlpha)
		if ok and type(a) == "number" then
			return a
		end
	end
	return 0.96
end

function Theme.Pixel(region)
	local PT = polestarTheme()
	if PT and PT.Pixel then
		local ok, px = pcall(PT.Pixel, region)
		if ok and type(px) == "number" and px > 0 then
			return px
		end
	end
	return 1
end

function Theme.ReduceMotion()
	local PT = polestarTheme()
	if PT and PT.ReduceMotion then
		local ok, rm = pcall(PT.ReduceMotion)
		if ok and rm then return true end
	end
	return false
end

function Theme.FontSpec(role, scale)
	scale = scale or 1
	local PT = polestarTheme()
	if PT and PT.FontSpec then
		local ok, face, size, flags = pcall(PT.FontSpec, role, scale)
		if ok and face and size then
			return face, size, flags or ""
		end
	end
	local face = STANDARD_TEXT_FONT or "Fonts\\FRIZQT__.TTF"
	local baseSize = FALLBACK_ROLES[role] or 12
	return face, math.max(9, math.floor(baseSize * scale + 0.5)), ""
end

function Theme.ApplyFont(fs, role, colorToken, scale)
	if not fs then return end
	local face, size, flags = Theme.FontSpec(role or "body", scale)
	local ok, applied = pcall(fs.SetFont, fs, face, size, flags or "")
	if not ok or applied == false then
		local fallback = STANDARD_TEXT_FONT or "Fonts\\FRIZQT__.TTF"
		pcall(fs.SetFont, fs, fallback, size or 12, flags or "")
	end
	if colorToken == "accent" then
		local r, g, b = Theme.Accent()
		fs:SetTextColor(r, g, b, 1)
	elseif colorToken then
		local r, g, b, a = Theme.Color(colorToken)
		fs:SetTextColor(r, g, b, a or 1)
	end
end

-- Create or update a 4-edge 1px hairline border on a frame
function Theme.ApplyBorder(frame, r, g, b, a)
	local px = Theme.Pixel(frame)
	local bdr = frame._jwlBorder
	if not bdr then
		bdr = {}
		for i = 1, 4 do
			bdr[i] = frame:CreateTexture(nil, "OVERLAY", nil, 6)
		end
		bdr[1]:SetPoint("TOPLEFT", frame, "TOPLEFT", 0, 0)
		bdr[1]:SetPoint("TOPRIGHT", frame, "TOPRIGHT", 0, 0)
		bdr[2]:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 0, 0)
		bdr[2]:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", 0, 0)
		bdr[3]:SetPoint("TOPLEFT", frame, "TOPLEFT", 0, 0)
		bdr[3]:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 0, 0)
		bdr[4]:SetPoint("TOPRIGHT", frame, "TOPRIGHT", 0, 0)
		bdr[4]:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", 0, 0)
		frame._jwlBorder = bdr
	end
	bdr[1]:SetHeight(px)
	bdr[2]:SetHeight(px)
	bdr[3]:SetWidth(px)
	bdr[4]:SetWidth(px)
	for i = 1, 4 do
		bdr[i]:SetColorTexture(r, g, b, a)
	end
end

function Theme.PaintWindow(frame, isModal)
	-- Deep dark backing scrim + drop shadow so menus/modals stay crisp and readable
	-- even when Polestar's guide window is configured with low GroundAlpha().
	if not frame._jwlShadow then
		local sh = frame:CreateTexture(nil, "BACKGROUND", nil, -8)
		sh:SetPoint("TOPLEFT", frame, "TOPLEFT", -6, 6)
		sh:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", 6, -8)
		frame._jwlShadow = sh
	end
	frame._jwlShadow:SetColorTexture(0.01, 0.015, 0.03, isModal and 0.68 or 0.52)

	if not frame._jwlScrim then
		local sc = frame:CreateTexture(nil, "BACKGROUND", nil, -7)
		sc:SetAllPoints(frame)
		frame._jwlScrim = sc
	end
	local sr, sg, sb = Theme.Color("scrim")
	frame._jwlScrim:SetColorTexture(sr, sg, sb, isModal and 0.96 or 0.90)

	if not frame._jwlBg then
		frame._jwlBg = frame:CreateTexture(nil, "BACKGROUND", nil, -6)
		frame._jwlBg:SetAllPoints(frame)
	end
	local r, g, b = Theme.Color("bg")
	local minAlpha = isModal and 0.96 or 0.93
	local alpha = math.max(minAlpha, Theme.GroundAlpha())
	frame._jwlBg:SetColorTexture(r, g, b, alpha)

	local br, bg, bb, ba = Theme.Wash("border")
	Theme.ApplyBorder(frame, br, bg, bb, math.max(ba, isModal and 0.24 or 0.18))
end

function Theme.PaintButton(btn, isPrimary)
	if not btn._jwlBg then
		btn._jwlBg = btn:CreateTexture(nil, "BACKGROUND")
		btn._jwlBg:SetAllPoints(btn)
		btn._jwlHl = btn:CreateTexture(nil, "HIGHLIGHT")
		btn._jwlHl:SetAllPoints(btn)
	end
	if isPrimary then
		local ar, ag, ab = Theme.Accent()
		btn._jwlBg:SetColorTexture(ar, ag, ab, 0.92)
		btn._jwlHl:SetColorTexture(1, 1, 1, 0.16)
		Theme.ApplyBorder(btn, ar, ag, ab, 0.85)
		if btn._jwlLabel then
			Theme.ApplyFont(btn._jwlLabel, "label", "onAccent")
		end
	else
		local pr, pg, pb = Theme.Color("panelAlt")
		btn._jwlBg:SetColorTexture(pr, pg, pb, 0.95)
		local hr, hg, hb, ha = Theme.Wash("hover")
		btn._jwlHl:SetColorTexture(hr, hg, hb, math.max(ha, 0.10))
		local br, bg, bb, ba = Theme.Wash("border")
		Theme.ApplyBorder(btn, br, bg, bb, math.max(ba, 0.14))
		if btn._jwlLabel then
			Theme.ApplyFont(btn._jwlLabel, "label", "text")
		end
	end
end

function Theme.CreateButton(parent, label, width, height, onClick, isPrimary)
	local btn = CreateFrame("Button", nil, parent)
	btn:SetSize(width or 84, height or 26)
	local fs = btn:CreateFontString(nil, "OVERLAY", "GameFontNormal")
	fs:SetPoint("CENTER")
	btn._jwlLabel = fs
	btn._jwlPrimary = isPrimary and true or false
	Theme.PaintButton(btn, btn._jwlPrimary)
	fs:SetText(label or "")
	btn:SetScript("OnClick", function(self)
		if ns.Sound and ns.Sound.Play then ns.Sound.Play("click") end
		if onClick then ns.Safe(onClick)(self) end
	end)
	return btn
end

-- Live repaint subscription
local painters = {}
local hookedPolestar = false

function Theme.RegisterRepaint(fn)
	if type(fn) ~= "function" then return end
	painters[#painters + 1] = fn
end

function Theme.RepaintAll()
	for i = 1, #painters do
		ns.Safe(painters[i])()
	end
end

local function hookPolestar()
	if hookedPolestar then return end
	local PT = polestarTheme()
	if PT and PT.OnChanged then
		hookedPolestar = true
		pcall(PT.OnChanged, function()
			Theme.RepaintAll()
		end)
	end
end

if ns.On then
	ns.On("LOGIN", hookPolestar)
	ns.On("INIT", hookPolestar)
end
