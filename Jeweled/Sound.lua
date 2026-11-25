-- Sound.lua: Quiet .ogg sound playback with Polestar_Arcade's 8-channel stop-oldest
-- handle limit and per-event deduplication (never stacks duplicate sounds).

local ADDON, ns = ...

local Sound = {}
ns.Sound = Sound

local PATH = "Interface\\AddOns\\" .. ADDON .. "\\Media\\snd\\"
local MAX_CHANNELS = 8
local CHANNEL = "SFX"

local VALID = {
	swap = true,
	error = true,
	match1 = true,
	match2 = true,
	match3 = true,
	cascade4 = true,
	cascade5 = true,
	special_line = true,
	special_blast = true,
	special_prism = true,
	reshuffle = true,
	click = true,
	record = true,
	achievement = true,
	go = true,
	land = true,
}

local handles = {}
local lastPlayedAt = {}

function Sound.IsEnabled()
	return ns.Get("sound") ~= false
end

function Sound.Play(name)
	if not Sound.IsEnabled() then return end
	if not VALID[name] then return end
	if not PlaySoundFile then return end

	-- Deduplicate identical sounds within 40ms (e.g. multi-gem matches play once)
	local now = GetTime and GetTime() or 0
	if lastPlayedAt[name] and (now - lastPlayedAt[name]) < 0.04 then
		return
	end
	lastPlayedAt[name] = now

	local ok, handle = PlaySoundFile(PATH .. name .. ".ogg", CHANNEL)
	if ok and handle then
		handles[#handles + 1] = handle
		if #handles > MAX_CHANNELS then
			local oldest = table.remove(handles, 1)
			if StopSound then
				pcall(StopSound, oldest)
			end
		end
	end
end

function Sound.PlayCascade(tier)
	if tier <= 1 then
		Sound.Play("match1")
	elseif tier == 2 then
		Sound.Play("match2")
	elseif tier == 3 then
		Sound.Play("match3")
	elseif tier == 4 then
		Sound.Play("cascade4")
	else
		Sound.Play("cascade5")
	end
end

function Sound.PlaySpecial(code)
	if code == "H" or code == "V" then
		Sound.Play("special_line")
	elseif code == "B" then
		Sound.Play("special_blast")
	elseif code == "P" then
		Sound.Play("special_prism")
	end
end

function Sound.StopAll()
	if StopSound then
		for i = #handles, 1, -1 do
			pcall(StopSound, handles[i])
			handles[i] = nil
		end
	else
		for i = #handles, 1, -1 do
			handles[i] = nil
		end
	end
end
