-- Grid.lua: Pooled 8x8 board renderer with Bejeweled-style gem rotation, specular
-- glints, ambient board twinkles, squash-and-stretch drops, and live 8-frame
-- elemental flipbook overlays (crackling H/V lightning, burning flames, rainbow vortex).

local _, ns = ...

local Grid = {}
ns.Grid = Grid

local ROWS, COLS = 8, 8
local CELL_SIZES = {
	small = 36,
	medium = 44,
	large = 52,
}
Grid.CELL_SIZES = CELL_SIZES

local container = nil
local bgTex = nil
local bgScrim = nil
local selectFrame = nil
local hintFrames = {}
local cells = {} -- cells[r][c] = Button
local cellSize = 44

local selectedRC = nil -- { r, c }
local hoveredBtn = nil
local liveDriver = CreateFrame and CreateFrame("Frame") or nil
local liveActive = false
local liveClock = 0
local nextTwinkleAt = 0.8
local lastActionAt = 0
local IDLE_HINT_SECONDS = 6.0

function Grid.ResetIdleHint()
	lastActionAt = liveClock
end

local function fullFX()
	if ns.Get("fx") == "reduced" then return false end
	if ns.Theme and ns.Theme.ReduceMotion() then return false end
	return true
end

local function safeRotate(tex, rad)
	if tex and tex.SetRotation then
		pcall(tex.SetRotation, tex, rad)
	end
end

function Grid.GetCellSize()
	return cellSize
end

function Grid.GetBoardPixelSize()
	return cellSize * COLS
end

function Grid.CellCenter(r, c)
	local x = (c - 0.5) * cellSize
	local y = -(r - 0.5) * cellSize
	return x, y
end

function Grid.CellTopLeft(r, c)
	return (c - 1) * cellSize, -(r - 1) * cellSize
end

local function setFlipbookFrame(tex, frameIdx, cols, rows)
	local idx = frameIdx % (cols * rows)
	local col = idx % cols
	local row = math.floor(idx / cols)
	local u1 = col / cols
	local u2 = (col + 1) / cols
	local v1 = row / rows
	local v2 = (row + 1) / rows
	tex:SetTexCoord(u1, u2, v1, v2)
end

-- Compact inner-crown specular sheen sweep strictly inside the gem silhouette
function Grid.PlayGlint(btn, duration)
	if not btn or not btn.sheen or not fullFX() then return end
	local sh = btn.sheen
	local gemSz = cellSize - 6
	local span = gemSz * 0.16
	sh:SetSize(gemSz * 0.64, gemSz * 0.64)
	sh:Show()
	ns.Anim.Tween(duration or 0.30, function(t)
		local off = -span + (span * 2) * t
		sh:ClearAllPoints()
		sh:SetPoint("CENTER", btn.gem, "CENTER", off, -off * 0.45)
		sh:SetAlpha(math.sin(t * math.pi) * 0.62)
	end, function()
		sh:Hide()
		sh:SetAlpha(0)
	end, ns.Anim.EaseInOutQuad, 0, "glint")
end

-- Tight facet twinkle sitting strictly inside the gem's upper-left facet
function Grid.PlayFacetTwinkle(btn)
	if not btn or not btn.twinkle or not fullFX() then return end
	local tw = btn.twinkle
	local gemSz = cellSize - 6
	local off = gemSz * 0.14
	local s0 = gemSz * 0.12
	local s1 = gemSz * 0.30
	tw:ClearAllPoints()
	tw:SetPoint("CENTER", btn.gem, "CENTER", -off, off)
	tw:Show()
	ns.Anim.Tween(0.30, function(t)
		local sz = s0 + (s1 - s0) * math.sin(t * math.pi)
		tw:SetSize(math.max(4, sz), math.max(4, sz))
		tw:SetAlpha(math.sin(t * math.pi) * 0.90)
		safeRotate(tw, t * 1.4)
	end, function()
		tw:Hide()
		tw:SetAlpha(0)
	end, ns.Anim.EaseOutQuad, 0, "glint")
end

local function triggerHoverFlourish(btn)
	if not btn or not fullFX() then return end
	if not (ns.UI and ns.UI.GetState and ns.UI.GetState() == "PLAYING") then return end
	if selectedRC and selectedRC.r == btn.r and selectedRC.c == btn.c then return end

	local baseSz = cellSize - 6
	local tag = "hover_" .. btn.r .. "_" .. btn.c
	ns.Anim.CancelTag(tag)
	Grid.PlayGlint(btn, 0.30)

	-- Crisp Bejeweled spin-wobble + scale lift on mouseover
	ns.Anim.Tween(0.32, function(t)
		local lift = math.sin(t * math.pi * 0.5)
		local sz = baseSz * (1 + 0.12 * lift)
		btn.gem:SetSize(sz, sz)
		if btn.specialCode ~= "P" then
			-- Quick jewel twist that eases cleanly back to upright
			local spin = math.sin(t * math.pi * 2) * 0.24 * (1 - t)
			safeRotate(btn.gem, spin)
		end
	end, function()
		if hoveredBtn == btn and not (selectedRC and selectedRC.r == btn.r and selectedRC.c == btn.c) then
			btn.gem:SetSize(baseSz * 1.10, baseSz * 1.10)
			if btn.specialCode ~= "P" then safeRotate(btn.gem, 0) end
		end
	end, ns.Anim.EaseOutQuad, 0, tag)
end

local function settleHoverOff(btn)
	if not btn then return end
	if selectedRC and selectedRC.r == btn.r and selectedRC.c == btn.c then return end
	local baseSz = cellSize - 6
	local tag = "hover_" .. btn.r .. "_" .. btn.c
	ns.Anim.CancelTag(tag)
	btn.gem:SetSize(baseSz, baseSz)
	if btn.specialCode ~= "P" then
		safeRotate(btn.gem, 0)
	end
end

-- HSV -> RGB helper for smooth prismatic aura cycling
local function hsvToRgb(h, s, v)
	local i = math.floor(h * 6)
	local f = h * 6 - i
	local p = v * (1 - s)
	local q = v * (1 - f * s)
	local t = v * (1 - (1 - f) * s)
	local m = i % 6
	if m == 0 then return v, t, p
	elseif m == 1 then return q, v, p
	elseif m == 2 then return p, v, t
	elseif m == 3 then return p, q, v
	elseif m == 4 then return t, p, v
	else return v, p, q end
end

local function onLiveBoardUpdate(_, rawDt)
	if not container or not container:IsVisible() then
		Grid.SetLiveActive(false)
		return
	end
	local dt = rawDt > 0.1 and 0.1 or rawDt
	liveClock = liveClock + dt

	local fxFull = fullFX()
	local isPlaying = ns.UI and ns.UI.GetState and ns.UI.GetState() == "PLAYING"
	local baseSz = cellSize - 6

	-- 1. Update gem-masked special flipbooks & unmasked H/V directional chevrons
	for r = 1, ROWS do
		local row = cells[r]
		if row then
			for c = 1, COLS do
				local btn = row[c]
				local sc = btn.specialCode
				if sc then
					local anim = ns.Art.GetSpecialAnim(sc, btn.gemType)
					if anim then
						if sc == "P" then
							-- Prismatic super gem: BOTH round-contour outer flames + outer crackling lightning
							-- smoothly rainbow-tinted at 60 FPS, plus breathing halo & gliding inner sheen!
							if fxFull then
								local t = liveClock + btn.animPhase
								local breath = 0.5 + 0.5 * math.sin(t * 2.6)
								local hr1, hg1, hb1 = hsvToRgb((t * 0.22) % 1, 0.85, 1.0)
								local hr2, hg2, hb2 = hsvToRgb((t * 0.22 + 0.48) % 1, 0.72, 1.0)

								-- Layer 1: Round-contour prismatic flames flowing outside the orb
								local fFire = math.floor((liveClock * 14) + btn.animPhase) % 8
								setFlipbookFrame(btn.spec, fFire, 4, 2)
								btn.spec:SetVertexColor(hr1, hg1, hb1, 0.95)

								-- Layer 2: Round-contour prismatic crackling lightning arcing outside the orb
								local fBolt = math.floor((liveClock * 20) + btn.animPhase + 3) % 8
								setFlipbookFrame(btn.specDir, fBolt, 4, 2)
								btn.specDir:SetVertexColor(hr2, hg2, hb2, 0.95)

								-- Layer 3: Breathing outer ring halo + gliding inner crystal sheen
								local haloSz = cellSize * (0.98 + 0.16 * breath)
								btn.specGlow:SetSize(haloSz, haloSz)
								btn.specGlow:SetVertexColor(hr1, hg1, hb1, 0.35 + 0.40 * breath)

								local sweep = math.sin(t * 1.9) * ((cellSize - 6) * 0.24)
								btn.specInner:ClearAllPoints()
								btn.specInner:SetPoint("CENTER", btn.gem, "CENTER", sweep, -sweep * 0.5)
								btn.specInner:SetVertexColor(1, 0.98, 1, 0.35 + 0.35 * (1 - breath))
							else
								setFlipbookFrame(btn.spec, 0, 4, 2)
								btn.spec:SetVertexColor(0.95, 0.72, 1.0, 0.85)
								setFlipbookFrame(btn.specDir, 0, 4, 2)
								btn.specDir:SetVertexColor(0.55, 0.92, 1.0, 0.85)
								btn.specGlow:SetSize(cellSize * 1.06, cellSize * 1.06)
								btn.specGlow:SetVertexColor(0.85, 0.75, 1.0, 0.50)
							end
						else
							if fxFull then
								local fIdx = math.floor((liveClock * anim.fps) + btn.animPhase) % anim.frames
								setFlipbookFrame(btn.spec, fIdx, anim.cols, anim.rows)
								if btn.specDir and anim.dirPath then
									local p = 0.68 + 0.32 * (0.5 + 0.5 * math.sin(liveClock * 6.5 + btn.animPhase))
									btn.specDir:SetAlpha(p)
								end
							else
								setFlipbookFrame(btn.spec, 0, anim.cols, anim.rows)
								if btn.specDir and anim.dirPath then
									btn.specDir:SetAlpha(0.92)
								end
							end
						end
					end
				end
			end
		end
	end

	-- 2. Selected gem gentle rock & breath (Prismatic stays upright and regal)
	if fxFull and isPlaying and selectedRC then
		local sBtn = cells[selectedRC.r] and cells[selectedRC.r][selectedRC.c]
		if sBtn then
			local breath = 1.06 + 0.04 * math.sin(liveClock * 5.5)
			sBtn.gem:SetSize(baseSz * breath, baseSz * breath)
			if sBtn.specialCode ~= "P" then
				safeRotate(sBtn.gem, math.sin(liveClock * 4.2) * 0.18)
			end
		end
	end

	-- 3. Ambient Bejeweled board twinkles (glint & facet sparkle masked strictly to the gem)
	if fxFull and isPlaying and liveClock >= nextTwinkleAt then
		nextTwinkleAt = liveClock + 0.65 + math.random() * 0.85
		local rr = math.random(1, ROWS)
		local cc = math.random(1, COLS)
		local tBtn = cells[rr] and cells[rr][cc]
		if tBtn and tBtn.gem:IsShown() then
			Grid.PlayGlint(tBtn, 0.36)
			Grid.PlayFacetTwinkle(tBtn)
		end
	end

	-- 4. Auto-hint when the player hasn't moved a gem in IDLE_HINT_SECONDS
	local autoPlaying = ns.UI and ns.UI.IsAutoPlaying and ns.UI.IsAutoPlaying()
	if isPlaying and not autoPlaying and (liveClock - lastActionAt) >= IDLE_HINT_SECONDS then
		lastActionAt = liveClock
		if ns.UI and ns.UI.ShowHint then
			ns.UI.ShowHint()
		end
	end
end

function Grid.SetLiveActive(on)
	if on then
		if not liveActive and liveDriver then
			liveActive = true
			liveDriver:SetScript("OnUpdate", onLiveBoardUpdate)
		end
	else
		if liveActive and liveDriver then
			liveDriver:SetScript("OnUpdate", nil)
		end
		liveActive = false
	end
end

local function makeHighlightFrame(parent, r, g, b, a)
	local f = CreateFrame("Frame", nil, parent)
	f:SetFrameLevel(parent:GetFrameLevel() + 6)
	ns.Theme.ApplyBorder(f, r, g, b, a)
	local fill = f:CreateTexture(nil, "BACKGROUND")
	fill:SetAllPoints(f)
	fill:SetColorTexture(r, g, b, 0.16)
	f:Hide()
	return f
end

function Grid.Init(parent)
	if container then return container end

	cellSize = CELL_SIZES[ns.Get("windowScale")] or 44
	local pxSize = cellSize * COLS

	container = CreateFrame("Frame", nil, parent)
	container:SetSize(pxSize, pxSize)

	bgTex = container:CreateTexture(nil, "BACKGROUND", nil, -4)
	bgTex:SetAllPoints(container)
	bgScrim = container:CreateTexture(nil, "BACKGROUND", nil, -3)
	bgScrim:SetAllPoints(container)
	bgScrim:SetColorTexture(0.02, 0.03, 0.06, 0.34)

	for r = 1, ROWS do
		cells[r] = {}
		for c = 1, COLS do
			local btn = CreateFrame("Button", nil, container)
			btn.r = r
			btn.c = c
			btn.animPhase = ((r * 3 + c * 5) % 8) + (math.random() * 0.5)
			btn.specialCode = nil
			btn.gemType = 1
			btn:SetSize(cellSize, cellSize)
			btn:SetPoint("TOPLEFT", container, "TOPLEFT", (c - 1) * cellSize, -(r - 1) * cellSize)
			btn:RegisterForClicks("LeftButtonUp")

			local tile = btn:CreateTexture(nil, "BACKGROUND", nil, -2)
			tile:SetAllPoints(btn)
			local isAlt = ((r + c) % 2) == 0
			tile:SetColorTexture(1, 1, 1, isAlt and 0.045 or 0.015)
			btn.tile = tile

			local hover = btn:CreateTexture(nil, "HIGHLIGHT")
			hover:SetAllPoints(btn)
			hover:SetColorTexture(1, 0.94, 0.78, 0.09)

			-- Soft pulsing elemental aura behind special gems
			local specGlow = btn:CreateTexture(nil, "ARTWORK", nil, 0)
			specGlow:SetPoint("CENTER", btn, "CENTER", 0, 0)
			specGlow:SetSize(cellSize + 8, cellSize + 8)
			specGlow:SetTexture(ns.Art.FX.sparkle)
			specGlow:SetBlendMode("ADD")
			specGlow:Hide()
			pcall(specGlow.SetSnapToPixelGrid, specGlow, false)
			btn.specGlow = specGlow

			-- Base gemstone texture
			local gem = btn:CreateTexture(nil, "ARTWORK", nil, 1)
			gem:SetPoint("CENTER", btn, "CENTER", 0, 0)
			gem:SetSize(cellSize - 6, cellSize - 6)
			pcall(gem.SetSnapToPixelGrid, gem, false)
			pcall(gem.SetTexelSnappingBias, gem, 0)
			btn.gem = gem

			-- Pixel-perfect silhouette mask matching the exact gem shape (clips sheen & twinkle strictly to gem!)
			if btn.CreateMaskTexture then
				local mask = btn:CreateMaskTexture()
				mask:SetAllPoints(gem)
				btn.gemMask = mask
			end

			-- Specular diagonal glint sweep texture (masked strictly to gem silhouette)
			local sheen = btn:CreateTexture(nil, "ARTWORK", nil, 2)
			sheen:SetPoint("CENTER", gem, "CENTER", 0, 0)
			sheen:SetSize(cellSize - 6, cellSize - 6)
			sheen:SetTexture(ns.Art.FX.glint)
			sheen:SetBlendMode("ADD")
			sheen:SetAlpha(0)
			sheen:Hide()
			pcall(sheen.SetSnapToPixelGrid, sheen, false)
			if btn.gemMask and sheen.AddMaskTexture then
				sheen:AddMaskTexture(btn.gemMask)
			end
			btn.sheen = sheen

			-- Facet twinkle star (also masked strictly to gem silhouette)
			local twinkle = btn:CreateTexture(nil, "ARTWORK", nil, 2)
			twinkle:SetPoint("CENTER", gem, "CENTER", 0, 0)
			twinkle:SetSize(14, 14)
			twinkle:SetTexture(ns.Art.FX.sparkle)
			twinkle:SetBlendMode("ADD")
			twinkle:SetVertexColor(1, 0.97, 0.84, 1)
			twinkle:SetAlpha(0)
			twinkle:Hide()
			pcall(twinkle.SetSnapToPixelGrid, twinkle, false)
			if btn.gemMask and twinkle.AddMaskTexture then
				twinkle:AddMaskTexture(btn.gemMask)
			end
			btn.twinkle = twinkle

			-- Unmasked shape-matched outer flipbook overlay (flames & lightning flowing OUTSIDE the exact gem contour!)
			local spec = btn:CreateTexture(nil, "ARTWORK", nil, 3)
			spec:SetPoint("CENTER", gem, "CENTER", 0, 0)
			spec:SetSize(cellSize + 10, cellSize + 10)
			spec:SetBlendMode("ADD")
			spec:Hide()
			pcall(spec.SetSnapToPixelGrid, spec, false)
			pcall(spec.SetTexelSnappingBias, spec, 0)
			btn.spec = spec

			-- Masked inner prismatic sheen (strictly inside the upright Prismatic orb)
			local specInner = btn:CreateTexture(nil, "ARTWORK", nil, 3)
			specInner:SetPoint("CENTER", gem, "CENTER", 0, 0)
			specInner:SetSize(cellSize - 4, cellSize - 4)
			specInner:SetBlendMode("ADD")
			specInner:Hide()
			pcall(specInner.SetSnapToPixelGrid, specInner, false)
			if btn.gemMask and specInner.AddMaskTexture then
				specInner:AddMaskTexture(btn.gemMask)
			end
			btn.specInner = specInner

			-- Unmasked crisp directional arrowheads ONLY for Row (H) and Column (V) line clears
			local specDir = btn:CreateTexture(nil, "ARTWORK", nil, 4)
			specDir:SetPoint("CENTER", gem, "CENTER", 0, 0)
			specDir:SetSize(cellSize + 8, cellSize + 8)
			specDir:SetBlendMode("ADD")
			specDir:Hide()
			pcall(specDir.SetSnapToPixelGrid, specDir, false)
			btn.specDir = specDir

			btn:SetScript("OnEnter", function(self)
				hoveredBtn = self
				triggerHoverFlourish(self)
			end)
			btn:SetScript("OnLeave", function(self)
				if hoveredBtn == self then hoveredBtn = nil end
				settleHoverOff(self)
			end)

			if ns.Input and ns.Input.BindCell then
				ns.Input.BindCell(btn)
			end
			cells[r][c] = btn
		end
	end

	local ar, ag, ab = ns.Theme.Accent()
	selectFrame = makeHighlightFrame(container, ar, ag, ab, 0.95)
	hintFrames[1] = makeHighlightFrame(container, 1, 0.86, 0.42, 0.95)
	hintFrames[2] = makeHighlightFrame(container, 1, 0.86, 0.42, 0.95)

	Grid.ApplyBackground()
	return container
end

function Grid.GetContainer()
	return container
end

function Grid.GetCell(r, c)
	return cells[r] and cells[r][c]
end

function Grid.ApplyBackground()
	if not bgTex then return end
	local bg = ns.Art.GetBackground(ns.Get("background"))
	bgTex:SetTexture(bg.path)
	if container then
		local br, bgg, bb, ba = ns.Theme.Wash("border")
		ns.Theme.ApplyBorder(container, br, bgg, bb, math.max(ba, 0.18))
	end
	if selectFrame then
		local ar, ag, ab = ns.Theme.Accent()
		ns.Theme.ApplyBorder(selectFrame, ar, ag, ab, 0.95)
	end
end

function Grid.ApplyScale(scaleKey)
	cellSize = CELL_SIZES[scaleKey or ns.Get("windowScale")] or 44
	if not container then return cellSize * COLS end
	local pxSize = cellSize * COLS
	container:SetSize(pxSize, pxSize)
	for r = 1, ROWS do
		for c = 1, COLS do
			local btn = cells[r][c]
			btn:SetSize(cellSize, cellSize)
			btn:ClearAllPoints()
			btn:SetPoint("TOPLEFT", container, "TOPLEFT", (c - 1) * cellSize, -(r - 1) * cellSize)
			btn.gem:SetSize(cellSize - 6, cellSize - 6)
			btn.sheen:SetSize((cellSize - 6) * 0.64, (cellSize - 6) * 0.64)
			btn.spec:SetSize(cellSize + 10, cellSize + 10)
			btn.specDir:SetSize(cellSize + 8, cellSize + 8)
			btn.specGlow:SetSize(cellSize + 4, cellSize + 4)
		end
	end
	if selectFrame then selectFrame:SetSize(cellSize - 2, cellSize - 2) end
	for i = 1, 2 do
		if hintFrames[i] then hintFrames[i]:SetSize(cellSize - 2, cellSize - 2) end
	end
	return pxSize
end

local function paintCellTexture(btn, cell)
	if not cell then
		btn.specialCode = nil
		btn.gemType = 0
		btn.gem:Hide()
		btn.spec:Hide()
		btn.specInner:Hide()
		btn.specDir:Hide()
		btn.specGlow:Hide()
		btn.sheen:Hide()
		return
	end

	local gemSet = ns.Get("gemSet")
	local gemSz = cellSize - 6
	btn.specialCode = cell.s
	btn.gemType = cell.t or 1

	btn.gem:ClearAllPoints()
	btn.gem:SetPoint("CENTER", btn, "CENTER", 0, 0)
	btn.gem:SetSize(gemSz, gemSz)
	btn.gem:SetAlpha(1)
	safeRotate(btn.gem, 0)

	btn.spec:ClearAllPoints()
	btn.spec:SetPoint("CENTER", btn.gem, "CENTER", 0, 0)
	btn.spec:SetSize(cellSize + 10, cellSize + 10)
	btn.spec:SetAlpha(1)

	btn.specInner:ClearAllPoints()
	btn.specInner:SetPoint("CENTER", btn.gem, "CENTER", 0, 0)
	btn.specInner:SetSize(cellSize - 4, cellSize - 4)
	btn.specInner:SetAlpha(1)

	btn.specDir:ClearAllPoints()
	btn.specDir:SetPoint("CENTER", btn.gem, "CENTER", 0, 0)
	btn.specDir:SetSize(cellSize + 8, cellSize + 8)
	btn.specDir:SetAlpha(0.92)

	btn.specGlow:ClearAllPoints()
	btn.specGlow:SetPoint("CENTER", btn.gem, "CENTER", 0, 0)
	btn.specGlow:Hide()

	local gemTexPath
	if cell.s == "P" then
		gemTexPath = ns.Art.GetSpecialTexture("P")
	else
		gemTexPath = ns.Art.GetGemTexture(gemSet, cell.t)
	end
	btn.gem:SetTexture(gemTexPath)
	btn.gem:Show()
	if btn.gemMask then
		btn.gemMask:SetTexture(gemTexPath, "CLAMPTOBLACKADDITIONAL", "CLAMPTOBLACKADDITIONAL")
	end

	local anim = cell.s and ns.Art.GetSpecialAnim(cell.s, cell.t) or nil
	if anim then
		if cell.s == "P" then
			-- Combine round-contour outer flames (fire_6) + outer crackling lightning (bolt_h_6) + halo + inner sheen!
			btn.spec:SetTexture(ns.Art.BASE .. "fx\\fire_6")
			btn.spec:SetSize(cellSize + 10, cellSize + 10)
			btn.spec:SetVertexColor(1, 0.75, 1, 0.95)
			setFlipbookFrame(btn.spec, math.floor(btn.animPhase) % 8, 4, 2)
			btn.spec:Show()

			btn.specDir:SetTexture(ns.Art.BASE .. "fx\\bolt_h_6")
			btn.specDir:SetSize(cellSize + 10, cellSize + 10)
			btn.specDir:SetVertexColor(0.60, 0.95, 1.0, 0.95)
			setFlipbookFrame(btn.specDir, math.floor(btn.animPhase + 3) % 8, 4, 2)
			btn.specDir:Show()

			btn.specGlow:SetTexture(ns.Art.FX.ring)
			btn.specGlow:SetSize(cellSize * 1.04, cellSize * 1.04)
			btn.specGlow:SetVertexColor(0.85, 0.78, 1.0, 0.55)
			btn.specGlow:Show()

			btn.specInner:SetTexture(ns.Art.FX.glint)
			btn.specInner:SetTexCoord(0, 1, 0, 1)
			btn.specInner:SetVertexColor(1, 0.98, 1, 0.55)
			btn.specInner:Show()
		else
			btn.specInner:Hide()
			btn.specGlow:Hide()
			btn.spec:SetVertexColor(1, 1, 1, 1)
			btn.spec:SetSize(cellSize + 10, cellSize + 10)
			btn.spec:SetTexture(anim.path)
			setFlipbookFrame(btn.spec, math.floor(btn.animPhase) % anim.frames, anim.cols, anim.rows)
			btn.spec:Show()
			if anim.dirPath then
				btn.specDir:SetTexCoord(0, 1, 0, 1)
				btn.specDir:SetVertexColor(1, 1, 1, 0.92)
				btn.specDir:SetSize(cellSize + 8, cellSize + 8)
				btn.specDir:SetTexture(anim.dirPath)
				btn.specDir:Show()
			else
				btn.specDir:SetTexCoord(0, 1, 0, 1)
				btn.specDir:Hide()
			end
		end
	else
		btn.spec:SetTexCoord(0, 1, 0, 1)
		btn.spec:SetVertexColor(1, 1, 1, 1)
		btn.spec:Hide()
		btn.specInner:Hide()
		btn.specDir:SetTexCoord(0, 1, 0, 1)
		btn.specDir:SetVertexColor(1, 1, 1, 1)
		btn.specDir:Hide()
		btn.specGlow:Hide()
	end
end

function Grid.Render(grid)
	if not container or not grid then return end
	for r = 1, ROWS do
		for c = 1, COLS do
			paintCellTexture(cells[r][c], grid[r][c])
		end
	end
end

function Grid.SetSelected(r, c)
	-- Reset previously selected gem's spin & scale cleanly
	if selectedRC then
		local prev = cells[selectedRC.r] and cells[selectedRC.r][selectedRC.c]
		if prev then
			prev.gem:SetSize(cellSize - 6, cellSize - 6)
			if prev.specialCode ~= "P" then safeRotate(prev.gem, 0) end
		end
	end

	if not selectFrame then return end
	if not r or not c then
		selectedRC = nil
		selectFrame:Hide()
		return
	end
	local btn = cells[r] and cells[r][c]
	if not btn then
		selectedRC = nil
		selectFrame:Hide()
		return
	end
	selectedRC = { r = r, c = c }
	selectFrame:SetSize(cellSize - 2, cellSize - 2)
	selectFrame:ClearAllPoints()
	selectFrame:SetPoint("CENTER", btn, "CENTER")
	selectFrame:Show()
	Grid.PlayGlint(btn, 0.30)
end

function Grid.ClearHint()
	ns.Anim.CancelTag("hint")
	for i = 1, 2 do
		if hintFrames[i] then hintFrames[i]:Hide() end
	end
end

function Grid.ShowHint(r1, c1, r2, c2)
	Grid.ClearHint()
	local b1 = cells[r1] and cells[r1][c1]
	local b2 = cells[r2] and cells[r2][c2]
	if not b1 or not b2 then return end
	local pair = { b1, b2 }
	for i = 1, 2 do
		local hf = hintFrames[i]
		hf:SetSize(cellSize - 2, cellSize - 2)
		hf:ClearAllPoints()
		hf:SetPoint("CENTER", pair[i], "CENTER")
		hf:SetAlpha(1)
		hf:Show()
	end
	local nudgeX = (c2 - c1) * 4
	local nudgeY = -(r2 - r1) * 4
	Grid.PlayGlint(b1, 0.40)
	Grid.PlayGlint(b2, 0.40)
	-- Pulse gold twice and gently rock the pair toward each other (quiet)
	ns.Anim.Tween(1.1, function(t)
		local a = 0.25 + 0.75 * math.abs(math.sin(t * math.pi * 2))
		hintFrames[1]:SetAlpha(a)
		hintFrames[2]:SetAlpha(a)
		if fullFX() then
			local w = math.sin(t * math.pi * 4) * 0.5 + 0.5
			b1.gem:ClearAllPoints(); b1.gem:SetPoint("CENTER", b1, "CENTER", nudgeX * w, nudgeY * w)
			b2.gem:ClearAllPoints(); b2.gem:SetPoint("CENTER", b2, "CENTER", -nudgeX * w, -nudgeY * w)
		end
	end, function()
		hintFrames[1]:Hide()
		hintFrames[2]:Hide()
		b1.gem:ClearAllPoints(); b1.gem:SetPoint("CENTER", b1, "CENTER", 0, 0)
		b2.gem:ClearAllPoints(); b2.gem:SetPoint("CENTER", b2, "CENTER", 0, 0)
	end, ns.Anim.Linear, 0, "hint")
end

-- Live drag preview: slide dragged gem toward neighbor while mouse button is held;
-- swap does NOT commit until release!
local dragPreviewCells = nil

local function setCellOffset(btn, ox, oy)
	if not btn then return end
	btn.gem:ClearAllPoints()
	btn.gem:SetPoint("CENTER", btn, "CENTER", ox, oy)
end

function Grid.ClearDragPreview()
	if not dragPreviewCells then return end
	setCellOffset(dragPreviewCells[1], 0, 0)
	setCellOffset(dragPreviewCells[2], 0, 0)
	dragPreviewCells = nil
end

function Grid.PreviewDrag(sr, sc, tr, tc, ox, oy)
	local b1 = cells[sr] and cells[sr][sc]
	local b2 = (tr and tc and cells[tr]) and cells[tr][tc] or nil
	if dragPreviewCells then
		if dragPreviewCells[1] ~= b1 then setCellOffset(dragPreviewCells[1], 0, 0) end
		if dragPreviewCells[2] ~= b2 then setCellOffset(dragPreviewCells[2], 0, 0) end
	end
	setCellOffset(b1, ox, oy)
	if b2 then
		setCellOffset(b2, -ox, -oy)
	end
	dragPreviewCells = { b1, b2 }
end

-- Smoothly spring back a cancelled drag without snapping abruptly
function Grid.SpringBackDrag(sr, sc, tr, tc, startOx, startOy)
	local b1 = cells[sr] and cells[sr][sc]
	local b2 = (tr and tc and cells[tr]) and cells[tr][tc] or nil
	dragPreviewCells = nil
	if not b1 then return end
	ns.Anim.Tween(0.10, function(t)
		local rem = 1 - t
		setCellOffset(b1, startOx * rem, startOy * rem)
		if b2 then setCellOffset(b2, -startOx * rem, -startOy * rem) end
	end, function()
		setCellOffset(b1, 0, 0)
		if b2 then setCellOffset(b2, 0, 0) end
	end, ns.Anim.EaseOutQuad, 0, "board")
end

-- Swap slide tween: supports continuing seamlessly from drag-release offsets (startOx, startOy)
function Grid.AnimateSwap(r1, c1, r2, c2, valid, onDone, startOx, startOy)
	dragPreviewCells = nil
	local b1, b2 = cells[r1][c1], cells[r2][c2]
	local dx = (c2 - c1) * cellSize
	local dy = -(r2 - r1) * cellSize
	local sx = startOx or 0
	local sy = startOy or 0
	local fromDrag = (sx ~= 0 or sy ~= 0)

	if valid then
		local dur = fromDrag and 0.07 or 0.12
		ns.Anim.Tween(dur, function(t)
			local ox = sx + (dx - sx) * t
			local oy = sy + (dy - sy) * t
			setCellOffset(b1, ox, oy)
			setCellOffset(b2, -ox, -oy)
		end, onDone, ns.Anim.EaseOutQuad, 0, "board")
	elseif fromDrag then
		-- Invalid drag swap: bounce smoothly back directly from where the player let go!
		ns.Anim.Tween(0.16, function(t)
			local rem = 1 - t
			setCellOffset(b1, sx * rem, sy * rem)
			setCellOffset(b2, -sx * rem, -sy * rem)
		end, function()
			setCellOffset(b1, 0, 0)
			setCellOffset(b2, 0, 0)
			if onDone then onDone() end
		end, ns.Anim.EaseOutQuad, 0, "board")
	else
		-- Invalid click swap: slide out halfway and bounce back
		ns.Anim.Tween(0.22, function(t)
			local u = t < 0.5 and (t * 2) or ((1 - t) * 2)
			local off = 0.55 * u
			setCellOffset(b1, dx * off, dy * off)
			setCellOffset(b2, -dx * off, -dy * off)
		end, function()
			setCellOffset(b1, 0, 0)
			setCellOffset(b2, 0, 0)
			if onDone then onDone() end
		end, ns.Anim.EaseInOutQuad, 0, "board")
	end
end

-- Spin-pop cleared cells (scale 1 -> 1.28 -> 0 with spin over ~160ms)
function Grid.AnimatePop(cleared, delayMap, onDone)
	local baseSz = cellSize - 6
	local fxFull = fullFX()
	local maxDelay = 0
	for _, item in ipairs(cleared) do
		local btn = cells[item.r][item.c]
		local key = (item.r - 1) * COLS + item.c
		local d = (delayMap and delayMap[key]) or 0
		if d > maxDelay then maxDelay = d end
		local dir = ((item.r + item.c) % 2 == 0) and 1 or -1
		ns.Anim.Tween(0.16, function(t)
			local scale = t < 0.32 and (1 + 0.28 * (t / 0.32)) or (1.28 * (1 - (t - 0.32) / 0.68))
			local sz = math.max(2, baseSz * scale)
			btn.gem:SetSize(sz, sz)
			btn.gem:SetAlpha(1 - t)
			if fxFull then safeRotate(btn.gem, dir * t * 1.4) end
			btn.spec:SetAlpha(1 - t)
			btn.specInner:SetAlpha(1 - t)
			btn.specDir:SetAlpha(1 - t)
		end, function()
			btn.gem:SetAlpha(0)
			safeRotate(btn.gem, 0)
			btn.spec:SetAlpha(0)
			btn.specInner:SetAlpha(0)
			btn.specDir:SetAlpha(0)
		end, ns.Anim.EaseOutQuad, d, "board")
	end
	ns.Anim.Delay(0.17 + maxDelay, onDone, "board")
end

-- Gravity fall + spawn drop with tactile squash-and-stretch landing bounce
function Grid.AnimateDrops(grid, drops, spawns, onDone)
	Grid.Render(grid)
	local baseSz = cellSize - 6
	local fxFull = fullFX()
	local any = false

	local function animateFall(btn, startY, isSpawn, duration)
		btn.gem:ClearAllPoints()
		btn.gem:SetPoint("CENTER", btn, "CENTER", 0, startY)
		if isSpawn then btn.gem:SetAlpha(0) end

		ns.Anim.Tween(duration, function(t, raw)
			local y = startY * (1 - t)
			btn.gem:ClearAllPoints(); btn.gem:SetPoint("CENTER", btn, "CENTER", 0, y)
			if isSpawn then btn.gem:SetAlpha(math.min(1, raw * 2.5)) end
			if fxFull then
				-- Slight vertical stretch while falling, quick horizontal squash on landing
				local sx, sy = 1, 1
				if raw < 0.72 then
					sx, sy = 0.95, 1.06
				else
					local imp = math.sin(((raw - 0.72) / 0.28) * math.pi)
					sx = 1 + 0.11 * imp
					sy = 1 - 0.09 * imp
				end
				btn.gem:SetSize(baseSz * sx, baseSz * sy)
			end
		end, function()
			btn.gem:SetSize(baseSz, baseSz)
			btn.gem:SetAlpha(1)
		end, ns.Anim.EaseOutBack, 0, "board")
	end

	for _, d in ipairs(drops) do
		any = true
		local btn = cells[d.toR][d.c]
		animateFall(btn, (d.toR - d.fromR) * cellSize, false, 0.20)
	end

	for _, sp in ipairs(spawns) do
		any = true
		local btn = cells[sp.r][sp.c]
		animateFall(btn, (sp.r - sp.fromR) * cellSize, true, 0.22)
	end

	if any then
		ns.Anim.Delay(0.23, function()
			Grid.Render(grid)
			if onDone then onDone() end
		end, "board")
	else
		if onDone then onDone() end
	end
end

-- Quick alpha shimmer wave across cells during reshuffle
function Grid.AnimateReshuffle(grid, onDone)
	if ns.Sound then ns.Sound.Play("reshuffle") end
	ns.Anim.Tween(0.28, function(t)
		local a = t < 0.5 and (1 - t * 1.6) or (0.2 + (t - 0.5) * 1.6)
		for r = 1, ROWS do
			for c = 1, COLS do
				cells[r][c].gem:SetAlpha(math.max(0.15, math.min(1, a)))
			end
		end
	end, function()
		Grid.Render(grid)
		if onDone then onDone() end
	end, ns.Anim.Linear, 0, "board")
end
