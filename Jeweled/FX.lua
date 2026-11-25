-- FX.lua: Pooled visual effects engine for Jeweled (§5.5 + Animation Polish).
-- Hard budgets: max 64 pooled effect textures, max 12 pooled floating score texts,
-- screen shake capped at <= 3px with >= 300ms cooldown. Zero runtime allocations.

local _, ns = ...

local FX = {}
ns.FX = FX

local MAX_FX_TEX = 64
local MAX_FLOATS = 12
local SHAKE_COOLDOWN = 0.30

local layerFrame = nil
local boardFrame = nil
local windowFrame = nil
local fxPool = {}
local floatPool = {}
local flashTex = nil
local bannerFS = nil
local lastShakeAt = 0
local activeFxCount = 0

local COMBO_CALLS = {
	[2] = "Combo!",
	[3] = "Critical Match!",
	[4] = "Multistrike!",
	[5] = "Legendary!",
}

local function fullFX()
	if ns.Get("fx") == "reduced" then return false end
	if ns.Theme and ns.Theme.ReduceMotion() then return false end
	return true
end

local function shakeEnabled()
	if not fullFX() then return false end
	return ns.Get("shake") ~= false
end

function FX.Init(winFrame, bFrame)
	if layerFrame then return end
	windowFrame = winFrame
	boardFrame = bFrame

	layerFrame = CreateFrame("Frame", nil, bFrame)
	layerFrame:SetAllPoints(bFrame)
	layerFrame:SetFrameLevel(bFrame:GetFrameLevel() + 12)

	flashTex = layerFrame:CreateTexture(nil, "OVERLAY", nil, 5)
	flashTex:SetAllPoints(layerFrame)
	flashTex:SetColorTexture(1, 0.85, 0.45, 0)
	flashTex:Hide()

	for i = 1, MAX_FX_TEX do
		local tex = layerFrame:CreateTexture(nil, "ARTWORK", nil, 4)
		tex:Hide()
		pcall(tex.SetSnapToPixelGrid, tex, false)
		pcall(tex.SetTexelSnappingBias, tex, 0)
		fxPool[i] = { tex = tex, busy = false }
	end

	for i = 1, MAX_FLOATS do
		local fs = layerFrame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
		fs:Hide()
		if ns.Theme then ns.Theme.ApplyFont(fs, "heading", "accent") end
		floatPool[i] = { fs = fs, busy = false }
	end

	bannerFS = layerFrame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
	bannerFS:SetPoint("CENTER", layerFrame, "CENTER", 0, 24)
	bannerFS:Hide()
	if ns.Theme then ns.Theme.ApplyFont(bannerFS, "hero", "accent") end
end

local function acquireFX()
	for i = 1, MAX_FX_TEX do
		if not fxPool[i].busy then
			fxPool[i].busy = true
			activeFxCount = activeFxCount + 1
			local tex = fxPool[i].tex
			tex:ClearAllPoints()
			tex:SetTexCoord(0, 1, 0, 1)
			tex:SetVertexColor(1, 1, 1, 1)
			tex:SetAlpha(1)
			if tex.SetRotation then pcall(tex.SetRotation, tex, 0) end
			tex:SetBlendMode("ADD")
			tex:Show()
			return fxPool[i]
		end
	end
	return nil
end

local function releaseFX(slot)
	if not slot or not slot.busy then return end
	slot.busy = false
	activeFxCount = math.max(0, activeFxCount - 1)
	slot.tex:Hide()
end

local function acquireFloat()
	for i = 1, MAX_FLOATS do
		if not floatPool[i].busy then
			floatPool[i].busy = true
			local fs = floatPool[i].fs
			fs:ClearAllPoints()
			fs:SetAlpha(1)
			fs:Show()
			return floatPool[i]
		end
	end
	return nil
end

local function releaseFloat(slot)
	if not slot or not slot.busy then return end
	slot.busy = false
	slot.fs:Hide()
end

function FX.ActiveCount()
	return activeFxCount
end

function FX.Reset()
	if not layerFrame then return end
	ns.Anim.CancelTag("fx")
	for i = 1, MAX_FX_TEX do
		fxPool[i].busy = false
		fxPool[i].tex:Hide()
	end
	activeFxCount = 0
	for i = 1, MAX_FLOATS do
		floatPool[i].busy = false
		floatPool[i].fs:Hide()
	end
	if flashTex then flashTex:Hide() end
	if bannerFS then bannerFS:Hide() end
end

-- Screen shake on the board well (capped <= 3px, >= 300ms cooldown)
function FX.Shake(px, duration)
	if not boardFrame or not shakeEnabled() then return end
	local now = GetTime and GetTime() or 0
	if (now - lastShakeAt) < SHAKE_COOLDOWN then return end
	lastShakeAt = now

	local mag = math.min(3, math.max(1, px or 2))
	local basePoint, baseRel, baseRelPt, baseX, baseY = boardFrame:GetPoint(1)
	if not basePoint then return end

	ns.Anim.Tween(duration or 0.16, function(t)
		local decay = 1 - t
		local ox = math.sin(t * 38) * mag * decay
		local oy = math.cos(t * 47) * mag * decay
		boardFrame:ClearAllPoints()
		boardFrame:SetPoint(basePoint, baseRel, baseRelPt, (baseX or 0) + ox, (baseY or 0) + oy)
	end, function()
		boardFrame:ClearAllPoints()
		boardFrame:SetPoint(basePoint, baseRel, baseRelPt, baseX or 0, baseY or 0)
	end, ns.Anim.Linear, 0, "fx")
end

function FX.BoardFlash(r, g, b, maxAlpha, duration)
	if not flashTex or not fullFX() then return end
	flashTex:SetColorTexture(r, g, b, maxAlpha or 0.28)
	flashTex:SetAlpha(1)
	flashTex:Show()
	ns.Anim.Tween(duration or 0.22, function(t)
		flashTex:SetAlpha(1 - t)
	end, function()
		flashTex:Hide()
	end, ns.Anim.EaseOutQuad, 0, "fx")
end

-- Sparkle burst at board-local (x, y)
function FX.Sparkle(x, y, size, delay, r, g, b)
	if not layerFrame or not fullFX() then return end
	local slot = acquireFX()
	if not slot then return end
	local tex = slot.tex
	tex:SetTexture(ns.Art.FX.sparkle)
	tex:SetVertexColor(r or 1, g or 0.92, b or 0.65, 1)
	local s0 = (size or 42) * 0.45
	local s1 = (size or 42) * 1.35
	tex:SetSize(s0, s0)
	tex:SetPoint("CENTER", layerFrame, "TOPLEFT", x, y)
	ns.Anim.Tween(0.24, function(t)
		local sz = s0 + (s1 - s0) * t
		tex:SetSize(sz, sz)
		tex:SetAlpha(1 - t)
		if tex.SetRotation then pcall(tex.SetRotation, tex, t * 1.2) end
	end, function()
		releaseFX(slot)
	end, ns.Anim.EaseOutQuad, delay or 0, "fx")
end

-- Color-matched spinning crystal shard burst on gem pop
function FX.GemShatter(x, y, r, g, b, count)
	if not layerFrame or not fullFX() then return end
	local n = math.min(count or 3, 5)
	for i = 1, n do
		local slot = acquireFX()
		if not slot then break end
		local tex = slot.tex
		tex:SetTexture(ns.Art.FX.shard)
		tex:SetBlendMode("BLEND")
		tex:SetVertexColor(r or 1, g or 0.9, b or 0.6, 1)
		local ang = (math.pi * 2 * i / n) + (math.random() * 0.8 - 0.4)
		local speed = 26 + math.random(0, 26)
		local vx = math.cos(ang) * speed
		local vy = math.sin(ang) * speed + 16
		local spinDir = (math.random() < 0.5) and 1 or -1
		local sz = 10 + math.random(0, 6)
		tex:SetSize(sz, sz)
		tex:SetPoint("CENTER", layerFrame, "TOPLEFT", x, y)
		ns.Anim.Tween(0.36, function(t)
			-- Arcing gravity trajectory (downward is -Y in WoW)
			local px = x + vx * t
			local py = y + vy * t - 48 * t * t
			tex:ClearAllPoints()
			tex:SetPoint("CENTER", layerFrame, "TOPLEFT", px, py)
			tex:SetAlpha(1 - t * t)
			if tex.SetRotation then pcall(tex.SetRotation, tex, spinDir * t * 5.2) end
		end, function()
			releaseFX(slot)
		end, ns.Anim.Linear, 0, "fx")
	end
end

-- Ambient rising ember (Blast flame gem) or electric spark (H/V lightning gem)
function FX.AmbientSpark(x, y, specialCode, cellSize)
	if not layerFrame or not fullFX() then return end
	local slot = acquireFX()
	if not slot then return end
	local tex = slot.tex
	tex:SetTexture(ns.Art.FX.star)
	local spread = (cellSize or 44) * 0.36
	local sx = x + (math.random() * 2 - 1) * spread
	local sy = y + (math.random() * 2 - 1) * spread * 0.6
	local dx, dy, dur
	if specialCode == "B" then
		-- Rising hot orange-gold ember
		tex:SetVertexColor(1.0, 0.55 + math.random() * 0.35, 0.14, 1)
		dx = (math.random() * 2 - 1) * 14
		dy = 22 + math.random(0, 18)
		dur = 0.55
	elseif specialCode == "H" or specialCode == "V" then
		-- Quick snapping cyan-white electric spark
		tex:SetVertexColor(0.45, 0.88, 1.0, 1)
		dx = (specialCode == "H" and ((math.random() < 0.5 and -1 or 1) * (16 + math.random(0, 12))) or (math.random() * 14 - 7))
		dy = (specialCode == "V" and ((math.random() < 0.5 and -1 or 1) * (16 + math.random(0, 12))) or (math.random() * 14 - 7))
		dur = 0.26
	else
		-- Swirling rainbow starlight glint for Prismatic
		tex:SetVertexColor(0.85, 0.72 + math.random() * 0.25, 1.0, 1)
		local ang = math.random() * math.pi * 2
		dx = math.cos(ang) * 18
		dy = math.sin(ang) * 18
		dur = 0.42
	end
	local sz = 10 + math.random(0, 6)
	tex:SetSize(sz, sz)
	tex:SetPoint("CENTER", layerFrame, "TOPLEFT", sx, sy)
	ns.Anim.Tween(dur, function(t)
		tex:ClearAllPoints()
		tex:SetPoint("CENTER", layerFrame, "TOPLEFT", sx + dx * t, sy + dy * t)
		tex:SetAlpha(math.sin(t * math.pi))
	end, function()
		releaseFX(slot)
	end, ns.Anim.EaseOutQuad, 0, "fx")
end

-- Expanding shockwave ring at (x, y)
function FX.Ring(x, y, maxSize, r, g, b)
	if not layerFrame or not fullFX() then return end
	local slot = acquireFX()
	if not slot then return end
	local tex = slot.tex
	tex:SetTexture(ns.Art.FX.ring)
	tex:SetVertexColor(r or 0.95, g or 0.78, b or 0.42, 1)
	local s0 = 20
	local s1 = maxSize or 150
	tex:SetSize(s0, s0)
	tex:SetPoint("CENTER", layerFrame, "TOPLEFT", x, y)
	ns.Anim.Tween(0.28, function(t)
		local sz = s0 + (s1 - s0) * t
		tex:SetSize(sz, sz)
		tex:SetAlpha(1 - t)
	end, function()
		releaseFX(slot)
	end, ns.Anim.EaseOutQuad, 0, "fx")
end

-- Fiery 3x3 bomb detonation for Blast (B) gems
function FX.FireExplosion(x, y, cellSize)
	if not layerFrame or not fullFX() then return end
	local sz = cellSize or 44
	FX.Ring(x, y, sz * 3.6, 1.0, 0.48, 0.12)
	FX.Ring(x, y, sz * 2.4, 1.0, 0.85, 0.35)
	FX.BoardFlash(1.0, 0.45, 0.12, 0.22, 0.22)
	FX.Shake(3, 0.18)

	-- Burst of spinning orange-gold flames & hot embers across the 3x3 area
	for i = 1, 8 do
		local slot = acquireFX()
		if not slot then break end
		local tex = slot.tex
		tex:SetTexture(i <= 4 and ns.Art.FX.sparkle or ns.Art.FX.star)
		tex:SetVertexColor(1.0, i <= 4 and 0.52 or 0.86, i <= 4 and 0.12 or 0.28, 1)
		local ang = (math.pi * 2 * i / 8) + (math.random() * 0.35)
		local dist = sz * (0.8 + math.random() * 0.85)
		local dx = math.cos(ang) * dist
		local dy = math.sin(ang) * dist + 14
		local pSz = (i <= 4) and (sz * 0.95) or 18
		tex:SetSize(pSz, pSz)
		tex:SetPoint("CENTER", layerFrame, "TOPLEFT", x, y)
		ns.Anim.Tween(0.38, function(t)
			tex:ClearAllPoints()
			tex:SetPoint("CENTER", layerFrame, "TOPLEFT", x + dx * t, y + dy * t)
			tex:SetAlpha(1 - t * t)
			if tex.SetRotation then pcall(tex.SetRotation, tex, t * 2.5) end
		end, function()
			releaseFX(slot)
		end, ns.Anim.EaseOutQuad, 0, "fx")
	end
end

-- Drifting star particles for cascade x3+ and New Record
function FX.StarBurst(x, y, count)
	if not layerFrame or not fullFX() then return end
	local n = math.min(count or 4, 8)
	for i = 1, n do
		local slot = acquireFX()
		if not slot then break end
		local tex = slot.tex
		tex:SetTexture(ns.Art.FX.star)
		tex:SetVertexColor(1, 0.88, 0.48, 1)
		local ang = (math.pi * 2 * i / n) + (math.random() * 0.4 - 0.2)
		local dist = 28 + math.random(0, 34)
		local dx = math.cos(ang) * dist
		local dy = math.sin(ang) * dist + 18
		local sz = 14 + math.random(0, 8)
		tex:SetSize(sz, sz)
		tex:SetPoint("CENTER", layerFrame, "TOPLEFT", x, y)
		ns.Anim.Tween(0.45, function(t)
			tex:ClearAllPoints()
			tex:SetPoint("CENTER", layerFrame, "TOPLEFT", x + dx * t, y + dy * t)
			tex:SetAlpha(1 - t * t)
		end, function()
			releaseFX(slot)
		end, ns.Anim.EaseOutQuad, (i - 1) * 0.02, "fx")
	end
end

-- Layered crackling electric lightning beam across full row or column (H / V)
function FX.Beam(isHorizontal, x, y, boardSize)
	if not layerFrame or not fullFX() then return end

	-- Outer electric cyan energy beam
	local outer = acquireFX()
	if outer then
		local tex = outer.tex
		tex:SetTexture(ns.Art.FX.beam)
		tex:SetVertexColor(0.32, 0.86, 1.0, 1)
		local thickness = 46
		tex:SetSize(boardSize, thickness)
		if isHorizontal then
			tex:SetPoint("CENTER", layerFrame, "TOPLEFT", boardSize * 0.5, y)
			if tex.SetRotation then pcall(tex.SetRotation, tex, 0) end
		else
			tex:SetPoint("CENTER", layerFrame, "TOPLEFT", x, -boardSize * 0.5)
			if tex.SetRotation then pcall(tex.SetRotation, tex, math.pi * 0.5) end
		end
		ns.Anim.Tween(0.24, function(t)
			tex:SetHeight(math.max(6, thickness * (1 - t * 0.65)))
			tex:SetAlpha(1 - t)
		end, function()
			releaseFX(outer)
		end, ns.Anim.EaseOutQuad, 0, "fx")
	end

	-- Jagged crackling white-blue lightning bolt core jittering along the axis
	local core = acquireFX()
	if core then
		local tex = core.tex
		tex:SetTexture(ns.Art.FX.bolt)
		tex:SetVertexColor(0.88, 0.98, 1.0, 1)
		tex:SetSize(44, boardSize)
		local baseX = isHorizontal and (boardSize * 0.5) or x
		local baseY = isHorizontal and y or (-boardSize * 0.5)
		local rot = isHorizontal and (math.pi * 0.5) or 0
		if tex.SetRotation then pcall(tex.SetRotation, tex, rot) end
		tex:SetPoint("CENTER", layerFrame, "TOPLEFT", baseX, baseY)
		ns.Anim.Tween(0.22, function(t)
			local jitter = math.sin(t * 75) * 4
			tex:ClearAllPoints()
			tex:SetPoint("CENTER", layerFrame, "TOPLEFT",
				baseX + (isHorizontal and 0 or jitter),
				baseY + (isHorizontal and jitter or 0))
			tex:SetAlpha(1 - t * t)
		end, function()
			releaseFX(core)
		end, ns.Anim.Linear, 0, "fx")
	end
end

-- Lightning bolt arc from (x1, y1) to (x2, y2) for Prismatic color-clear
function FX.Bolt(x1, y1, x2, y2, delay, r, g, b)
	if not layerFrame or not fullFX() then return end
	local slot = acquireFX()
	if not slot then return end
	local tex = slot.tex
	tex:SetTexture(ns.Art.FX.bolt)
	tex:SetVertexColor(r or 0.75, g or 0.93, b or 1, 1)
	local dx = x2 - x1
	local dy = y2 - y1
	local len = math.max(24, math.sqrt(dx * dx + dy * dy))
	local mx = (x1 + x2) * 0.5
	local my = (y1 + y2) * 0.5
	tex:SetSize(34, len)
	tex:SetPoint("CENTER", layerFrame, "TOPLEFT", mx, my)
	local atan2 = math.atan2 or math.atan
	local angle = atan2(dy, dx) - math.pi * 0.5
	if tex.SetRotation then pcall(tex.SetRotation, tex, angle) end
	ns.Anim.Tween(0.24, function(t)
		tex:SetAlpha(1 - t * t)
	end, function()
		releaseFX(slot)
	end, ns.Anim.Linear, delay or 0, "fx")
end

-- Floating +N score text
function FX.FloatScore(x, y, points, cascade)
	if not layerFrame then return end
	local slot = acquireFloat()
	if not slot then return end
	local fs = slot.fs
	local role = (cascade and cascade >= 3) and "display" or "heading"
	local color = (cascade and cascade >= 2) and "accent" or "text"
	if ns.Theme then ns.Theme.ApplyFont(fs, role, color) end
	local suffix = (cascade and cascade >= 2) and (" x" .. tostring(cascade)) or ""
	fs:SetText("+" .. tostring(points) .. suffix)
	fs:SetPoint("CENTER", layerFrame, "TOPLEFT", x, y)
	ns.Anim.Tween(0.65, function(t)
		fs:ClearAllPoints()
		fs:SetPoint("CENTER", layerFrame, "TOPLEFT", x, y + 36 * t)
		fs:SetAlpha(t < 0.6 and 1 or (1 - (t - 0.6) / 0.4))
	end, function()
		releaseFloat(slot)
	end, ns.Anim.EaseOutQuad, 0, "fx")
end

-- Center banner flash (Combo calls, "New Record!", "Go!")
function FX.Banner(text, colorToken, duration)
	if not bannerFS then return end
	if ns.Theme then ns.Theme.ApplyFont(bannerFS, "hero", colorToken or "accent") end
	bannerFS:SetText(text or "")
	bannerFS:SetAlpha(1)
	bannerFS:ClearAllPoints()
	bannerFS:SetPoint("CENTER", layerFrame, "CENTER", 0, 12)
	bannerFS:Show()
	ns.Anim.CancelTag("fx_banner")
	ns.Anim.Tween(duration or 0.85, function(t)
		bannerFS:ClearAllPoints()
		bannerFS:SetPoint("CENTER", layerFrame, "CENTER", 0, 12 + 22 * t)
		bannerFS:SetAlpha(t < 0.55 and 1 or (1 - (t - 0.55) / 0.45))
	end, function()
		bannerFS:Hide()
	end, ns.Anim.EaseOutQuad, 0, "fx_banner")
end

-- High-level cascade tier dispatcher matching §5.5 spec
function FX.PlayCascadeTier(tier, cx, cy, points)
	FX.FloatScore(cx, cy, points, tier)
	if tier >= 2 then
		FX.Ring(cx, cy, 110 + tier * 18)
	end
	if tier >= 3 then
		FX.StarBurst(cx, cy, math.min(6, tier + 1))
	end
	if tier == 4 then
		FX.Shake(2, 0.15)
	elseif tier >= 5 then
		FX.Shake(3, 0.20)
		FX.BoardFlash(0.95, 0.78, 0.35, 0.24, 0.25)
	end
	local call = COMBO_CALLS[math.min(tier, 5)]
	if call and tier >= 2 then
		FX.Banner(call, tier >= 5 and "quest" or "accent", 0.75)
	end
end

function FX.PlayNewRecord()
	if not layerFrame then return end
	local w = layerFrame:GetWidth() or 352
	FX.StarBurst(w * 0.5, -w * 0.35, 8)
	FX.Banner("New Record!", "quest", 1.1)
	if ns.Sound then ns.Sound.Play("record") end
end
