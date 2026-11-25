-- Art.lua: Central custom art asset manifest for Jeweled.
-- Zero Blizzard icons; every texture path resolves through this table so new
-- gem sets and backgrounds are pure data additions.

local ADDON, ns = ...
local BASE = "Interface\\AddOns\\" .. ADDON .. "\\Media\\"

local Art = {}
ns.Art = Art

Art.BASE = BASE
Art.ICON = BASE .. "icon"

Art.GEM_ORDER = { 1, 2, 3, 4, 5, 6 }

Art.GEM_SETS = {
	azeroth = {
		id = "azeroth",
		name = "Azeroth Gems",
		unlockAchievement = nil,
		gems = {
			[1] = BASE .. "gems\\azeroth\\ruby",
			[2] = BASE .. "gems\\azeroth\\sapphire",
			[3] = BASE .. "gems\\azeroth\\emerald",
			[4] = BASE .. "gems\\azeroth\\topaz",
			[5] = BASE .. "gems\\azeroth\\amethyst",
			[6] = BASE .. "gems\\azeroth\\diamond",
		},
		names = { "Ruby", "Sapphire", "Emerald", "Topaz", "Amethyst", "Diamond" },
		colors = {
			[1] = { 0.96, 0.22, 0.28 }, -- Ruby crimson
			[2] = { 0.26, 0.56, 1.00 }, -- Sapphire blue
			[3] = { 0.18, 0.86, 0.45 }, -- Emerald green
			[4] = { 1.00, 0.78, 0.22 }, -- Topaz amber-gold
			[5] = { 0.76, 0.38, 1.00 }, -- Amethyst violet
			[6] = { 0.86, 0.94, 1.00 }, -- Diamond ice-white
		},
	},
	polestar = {
		id = "polestar",
		name = "Polestar",
		unlockAchievement = "sky_captain",
		gems = {
			[1] = BASE .. "gems\\polestar\\gold",
			[2] = BASE .. "gems\\polestar\\starlight",
			[3] = BASE .. "gems\\polestar\\void",
			[4] = BASE .. "gems\\polestar\\silver",
			[5] = BASE .. "gems\\polestar\\ember",
			[6] = BASE .. "gems\\polestar\\aurora",
		},
		names = { "Polestar Gold", "Starlight", "Void", "Silver", "Ember", "Aurora" },
		colors = {
			[1] = { 0.94, 0.76, 0.36 }, -- Polestar gold
			[2] = { 0.68, 0.84, 1.00 }, -- Starlight blue
			[3] = { 0.38, 0.48, 0.82 }, -- Void indigo
			[4] = { 0.88, 0.92, 0.96 }, -- Silver moonlight
			[5] = { 1.00, 0.48, 0.16 }, -- Ember orange
			[6] = { 0.22, 0.92, 0.82 }, -- Aurora teal
		},
	},
}

Art.GEM_SET_ORDER = { "azeroth", "polestar" }

Art.SPECIALS = {
	H = BASE .. "gems\\special\\line_h",
	V = BASE .. "gems\\special\\line_v",
	B = BASE .. "gems\\special\\blast",
	P = BASE .. "gems\\special\\prismatic",
}

Art.BACKGROUNDS = {
	nightsky = {
		id = "nightsky",
		name = "Night Sky",
		unlockAchievement = nil,
		path = BASE .. "backgrounds\\nightsky",
	},
	deepmine = {
		id = "deepmine",
		name = "Deep Mine",
		unlockAchievement = nil,
		path = BASE .. "backgrounds\\deepmine",
	},
	arcanevault = {
		id = "arcanevault",
		name = "Arcane Vault",
		unlockAchievement = nil,
		path = BASE .. "backgrounds\\arcanevault",
	},
}

Art.BACKGROUND_ORDER = { "nightsky", "deepmine", "arcanevault" }

Art.SPECIAL_ANIM = {
	H = { prefix = BASE .. "fx\\bolt_h_", dirPath = BASE .. "fx\\chev_h", cols = 4, rows = 2, frames = 8, fps = 20, masked = false, glow = { 0.30, 0.82, 1.00 } },
	V = { prefix = BASE .. "fx\\bolt_v_", dirPath = BASE .. "fx\\chev_v", cols = 4, rows = 2, frames = 8, fps = 20, masked = false, glow = { 0.30, 0.82, 1.00 } },
	B = { prefix = BASE .. "fx\\fire_",   dirPath = nil,                   cols = 4, rows = 2, frames = 8, fps = 14, masked = false, glow = { 1.00, 0.44, 0.10 } },
	P = { path   = BASE .. "fx\\sparkle", dirPath = nil, cols = 1, rows = 1, frames = 1, fps = 0, masked = true, glow = { 0.90, 0.88, 1.00 } },
}

Art.FX = {
	sparkle = BASE .. "fx\\sparkle",
	ring    = BASE .. "fx\\ring",
	beam    = BASE .. "fx\\beam",
	bolt    = BASE .. "fx\\bolt",
	star    = BASE .. "fx\\star",
	badge   = BASE .. "fx\\badge",
	glint   = BASE .. "fx\\glint",
	shard   = BASE .. "fx\\shard",
	chev_h  = BASE .. "fx\\chev_h",
	chev_v  = BASE .. "fx\\chev_v",
	anim_prism = BASE .. "fx\\anim_prism",
}

function Art.GetGemSet(id)
	return Art.GEM_SETS[id] or Art.GEM_SETS.azeroth
end

function Art.GetGemColor(setId, gemType)
	local set = Art.GetGemSet(setId)
	local c = set.colors and set.colors[gemType]
	if c then return c[1], c[2], c[3] end
	return 1, 0.88, 0.55
end

function Art.GetSpecialAnim(specialCode, gemType)
	local spec = Art.SPECIAL_ANIM[specialCode]
	if not spec then return nil end
	if spec.prefix then
		local t = tonumber(gemType) or 1
		if t < 1 or t > 6 then t = 1 end
		return {
			path = spec.prefix .. tostring(t),
			dirPath = spec.dirPath,
			cols = spec.cols,
			rows = spec.rows,
			frames = spec.frames,
			fps = spec.fps,
			masked = spec.masked,
			glow = spec.glow,
		}
	end
	return spec
end

function Art.GetGemTexture(setId, gemType)
	local set = Art.GetGemSet(setId)
	return set.gems[gemType] or set.gems[1]
end

function Art.GetSpecialTexture(specialCode)
	return Art.SPECIALS[specialCode]
end

function Art.GetBackground(id)
	return Art.BACKGROUNDS[id] or Art.BACKGROUNDS.nightsky
end

function Art.GetAllTextures()
	local list = {
		{ label = "icon", path = Art.ICON },
	}
	for _, setId in ipairs(Art.GEM_SET_ORDER) do
		local set = Art.GEM_SETS[setId]
		for i = 1, 6 do
			list[#list + 1] = {
				label = setId .. "/" .. (set.names[i] or tostring(i)),
				path = set.gems[i],
			}
		end
	end
	for _, code in ipairs({ "H", "V", "B", "P" }) do
		list[#list + 1] = { label = "special/" .. code, path = Art.SPECIALS[code] }
	end
	for _, bgId in ipairs(Art.BACKGROUND_ORDER) do
		list[#list + 1] = { label = "bg/" .. bgId, path = Art.BACKGROUNDS[bgId].path }
	end
	for _, fxKey in ipairs({ "sparkle", "ring", "beam", "bolt", "star", "badge" }) do
		list[#list + 1] = { label = "fx/" .. fxKey, path = Art.FX[fxKey] }
	end
	return list
end
