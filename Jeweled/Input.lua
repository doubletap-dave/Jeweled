-- Input.lua: Click-to-swap AND release-on-drop drag-to-swap input controller.
-- While dragging, gems visually follow the cursor toward the target neighbor;
-- the swap only commits when you let go of the mouse button!

local _, ns = ...

local Input = {}
ns.Input = Input

local selected = nil -- { r, c }
local dragState = nil -- { r, c, startX, startY, active, targetR, targetC, ready }
local suppressNextClick = false
local dragTracker = CreateFrame and CreateFrame("Frame") or nil

local function canAct()
	return ns.UI and ns.UI.GetState and ns.UI.GetState() == "PLAYING"
end

function Input.ClearSelection()
	selected = nil
	if ns.Grid then ns.Grid.SetSelected(nil) end
end

local function clearDrag()
	dragState = nil
	if dragTracker then dragTracker:SetScript("OnUpdate", nil) end
	if ns.Grid and ns.Grid.ClearDragPreview then
		ns.Grid.ClearDragPreview()
	end
end

local function tryCommitSwap(r1, c1, r2, c2, startOx, startOy)
	Input.ClearSelection()
	dragState = nil
	if dragTracker then dragTracker:SetScript("OnUpdate", nil) end
	if ns.Grid then ns.Grid.ClearHint() end
	if ns.UI and ns.UI.RequestSwap then
		ns.UI.RequestSwap(r1, c1, r2, c2, startOx, startOy)
	end
end

local function finishDragOnRelease()
	local d = dragState
	if not d then
		clearDrag()
		return
	end
	local wasActive = d.active
	local sr, sc = d.r, d.c
	local tr, tc = d.targetR, d.targetC
	local ready = d.ready
	local ox, oy = d.ox or 0, d.oy or 0
	dragState = nil
	if dragTracker then dragTracker:SetScript("OnUpdate", nil) end

	if wasActive then
		suppressNextClick = true
		if ready and tr and tc and canAct() and ns.Board and ns.Board.AreAdjacent(sr, sc, tr, tc) then
			-- Commit seamlessly from the exact released offset (zero snap-back!)
			tryCommitSwap(sr, sc, tr, tc, ox, oy)
		elseif ns.Grid and ns.Grid.SpringBackDrag then
			ns.Grid.SpringBackDrag(sr, sc, tr, tc, ox, oy)
		elseif ns.Grid and ns.Grid.ClearDragPreview then
			ns.Grid.ClearDragPreview()
		end
	elseif ns.Grid and ns.Grid.ClearDragPreview then
		ns.Grid.ClearDragPreview()
	end
end

local function onDragPoll()
	if not dragState then
		clearDrag()
		return
	end
	if not canAct() then
		clearDrag()
		return
	end

	-- Commit (or cancel) strictly when the player lets go of the left mouse button!
	if not IsMouseButtonDown or not IsMouseButtonDown("LeftButton") then
		finishDragOnRelease()
		return
	end

	local cx, cy = GetCursorPosition()
	local scale = UIParent and UIParent:GetEffectiveScale() or 1
	cx, cy = cx / scale, cy / scale
	local dx = cx - dragState.startX
	local dy = cy - dragState.startY
	local cellSz = (ns.Grid and ns.Grid.GetCellSize()) or 44

	-- Wait for a small deadzone (6px) so regular clicks don't jitter
	if not dragState.active then
		if math.abs(dx) < 6 and math.abs(dy) < 6 then
			return
		end
		dragState.active = true
	end

	local sr, sc = dragState.r, dragState.c
	local tr, tc = sr, sc
	local ox, oy = 0, 0
	local maxOff = cellSz * 0.85

	if math.abs(dx) >= math.abs(dy) then
		local dir = dx >= 0 and 1 or -1
		tc = sc + dir
		if ns.Board and ns.Board.AreAdjacent(sr, sc, tr, tc) then
			ox = math.max(-maxOff, math.min(maxOff, dx))
		else
			tr, tc = nil, nil
			ox = math.max(-cellSz * 0.18, math.min(cellSz * 0.18, dx * 0.25))
		end
	else
		-- Screen Y increases upward, grid rows increase downward
		local dir = dy >= 0 and -1 or 1
		tr = sr + dir
		if ns.Board and ns.Board.AreAdjacent(sr, sc, tr, tc) then
			oy = math.max(-maxOff, math.min(maxOff, dy))
		else
			tr, tc = nil, nil
			oy = math.max(-cellSz * 0.18, math.min(cellSz * 0.18, dy * 0.25))
		end
	end

	local dist = math.max(math.abs(ox), math.abs(oy))
	dragState.targetR = tr
	dragState.targetC = tc
	dragState.ox = ox
	dragState.oy = oy
	dragState.ready = (tr ~= nil and tc ~= nil and dist >= cellSz * 0.30)

	if ns.Grid and ns.Grid.PreviewDrag then
		ns.Grid.PreviewDrag(sr, sc, tr, tc, ox, oy)
	end
end

function Input.BindCell(btn)
	btn:SetScript("OnMouseDown", function(self, mouse)
		if mouse ~= "LeftButton" or not canAct() then return end
		suppressNextClick = false
		local cx, cy = GetCursorPosition()
		local scale = UIParent and UIParent:GetEffectiveScale() or 1
		dragState = {
			r = self.r,
			c = self.c,
			startX = cx / scale,
			startY = cy / scale,
			active = false,
			targetR = nil,
			targetC = nil,
			ready = false,
		}
		if dragTracker then
			dragTracker:SetScript("OnUpdate", onDragPoll)
		end
	end)

	btn:SetScript("OnMouseUp", function(self, mouse)
		if mouse ~= "LeftButton" then return end
		if dragState and dragState.active then
			finishDragOnRelease()
			suppressNextClick = false
			return
		end
		local wasDragged = suppressNextClick
		suppressNextClick = false
		clearDrag()
		if wasDragged or not canAct() then return end

		if not selected then
			selected = { r = self.r, c = self.c }
			ns.Grid.SetSelected(self.r, self.c)
			if ns.Sound then ns.Sound.Play("click") end
			return
		end

		if selected.r == self.r and selected.c == self.c then
			Input.ClearSelection()
			return
		end

		if ns.Board.AreAdjacent(selected.r, selected.c, self.r, self.c) then
			tryCommitSwap(selected.r, selected.c, self.r, self.c)
		else
			selected = { r = self.r, c = self.c }
			ns.Grid.SetSelected(self.r, self.c)
			if ns.Sound then ns.Sound.Play("click") end
		end
	end)
end

function Input.Stop()
	Input.ClearSelection()
	clearDrag()
end
