-- Anim.lua: Shared zero-idle-cost OnUpdate tween driver for Jeweled.
-- Unregisters OnUpdate immediately when no tweens are active, clamps elapsed
-- time at 0.25s (Arcade pattern), and pools tween tables to avoid GC churn.

local _, ns = ...

local Anim = {}
ns.Anim = Anim

local MAX_DT = 0.25
local driver = CreateFrame and CreateFrame("Frame") or nil
local active = {}
local pool = {}
local running = false

-- FPS telemetry (optional dev overlay)
local fpsAccum, fpsFrames, fpsValue = 0, 0, 0

-- Easing functions
function Anim.Linear(t) return t end
function Anim.EaseOutQuad(t) return 1 - (1 - t) * (1 - t) end
function Anim.EaseInOutQuad(t)
	if t < 0.5 then return 2 * t * t end
	return 1 - ((-2 * t + 2) ^ 2) / 2
end
function Anim.EaseOutBack(t)
	local c1 = 1.45
	local c3 = c1 + 1
	local u = t - 1
	return 1 + c3 * u * u * u + c1 * u * u
end

local function releaseTween(tw)
	tw.elapsed = 0
	tw.delay = 0
	tw.duration = 0
	tw.ease = nil
	tw.onUpdate = nil
	tw.onDone = nil
	tw.tag = nil
	tw.cancelled = false
	pool[#pool + 1] = tw
end

local onUpdateFn
local function stopDriver()
	if running and driver then
		driver:SetScript("OnUpdate", nil)
	end
	running = false
end

local function startDriver()
	if not running and driver then
		running = true
		driver:SetScript("OnUpdate", onUpdateFn)
	end
end

onUpdateFn = function(_, rawDt)
	local dt = rawDt
	if dt > MAX_DT then dt = MAX_DT end
	if dt < 0 then dt = 0 end

	fpsAccum = fpsAccum + rawDt
	fpsFrames = fpsFrames + 1
	if fpsAccum >= 0.5 then
		fpsValue = math.floor((fpsFrames / fpsAccum) + 0.5)
		fpsAccum, fpsFrames = 0, 0
	end

	local i = 1
	while i <= #active do
		local tw = active[i]
		if tw.cancelled then
			table.remove(active, i)
			releaseTween(tw)
		else
			if tw.delay > 0 then
				tw.delay = tw.delay - dt
				i = i + 1
			else
				tw.elapsed = tw.elapsed + dt
				local p = tw.duration > 0 and (tw.elapsed / tw.duration) or 1
				if p >= 1 then p = 1 end
				local eased = tw.ease and tw.ease(p) or p
				if tw.onUpdate then
					local ok, err = pcall(tw.onUpdate, eased, p)
					if not ok and geterrorhandler then geterrorhandler()(err) end
				end
				if p >= 1 then
					local done = tw.onDone
					table.remove(active, i)
					releaseTween(tw)
					if done then
						local ok, err = pcall(done)
						if not ok and geterrorhandler then geterrorhandler()(err) end
					end
				else
					i = i + 1
				end
			end
		end
	end

	if #active == 0 then
		stopDriver()
	end
end

function Anim.Tween(duration, onUpdate, onDone, ease, delay, tag)
	local tw = table.remove(pool) or {}
	tw.elapsed = 0
	tw.delay = delay or 0
	tw.duration = math.max(0.001, duration or 0.15)
	tw.ease = ease or Anim.EaseOutQuad
	tw.onUpdate = onUpdate
	tw.onDone = onDone
	tw.tag = tag
	tw.cancelled = false
	active[#active + 1] = tw
	startDriver()
	return tw
end

function Anim.Delay(seconds, onDone, tag)
	return Anim.Tween(math.max(0.001, seconds or 0.01), nil, onDone, Anim.Linear, 0, tag)
end

function Anim.CancelTag(tag)
	for i = 1, #active do
		if active[i].tag == tag then
			active[i].cancelled = true
		end
	end
end

function Anim.CancelAll()
	for i = #active, 1, -1 do
		local tw = table.remove(active, i)
		releaseTween(tw)
	end
	stopDriver()
end

function Anim.ActiveCount()
	return #active
end

function Anim.GetFPS()
	return fpsValue
end
