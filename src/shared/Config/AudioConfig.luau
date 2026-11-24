--!strict
--[[
	AudioConfig: background music and short sound cues (client AudioController plays them).

	Licensing (checked 2026-11-24 in the Roblox Creator Store from Studio):
	  Music   tracks published by "APMOfficial" (APM Music) in the Creator Store. APM licensed its
	          catalogue to Roblox for use in Roblox experiences; these are original APM
	          compositions (not covers of commercial holiday songs). Each id loaded in Studio.
	  Cues    sounds that ship inside the Roblox client (rbxasset://sounds/...), no upload needed.
	Replace or add tracks here only with assets whose rights are verified the same way.
]]

local AudioConfig = {
	Music = {
		Volume = 0.35, -- master music volume before the player's own setting
		CrossFade = 2.5, -- seconds between two tracks
		Tracks = {
			{ Name = "Dancing Snowflakes", SoundId = "rbxassetid://9046743045" }, -- APM Music
			-- Not 9041771148 "Christmas Party": the file is sleigh bells only (97% of its energy is high).
			{ Name = "Holiday Bliss", SoundId = "rbxassetid://9046748008" }, -- APM Music
			{ Name = "Favorite Time Of Year", SoundId = "rbxassetid://9046745950" }, -- APM Music
			{ Name = "Snowman Song", SoundId = "rbxassetid://9046739139" }, -- APM Music
		},
	},
	Cues = {
		Legendary = { SoundId = "rbxasset://sounds/victory.wav", Volume = 0.6, Pitch = 1 },
		Mythic = { SoundId = "rbxasset://sounds/victory.wav", Volume = 0.7, Pitch = 0.8 },
		Craft = { SoundId = "rbxasset://sounds/electronicpingshort.wav", Volume = 0.5, Pitch = 1.25 },
		Upgrade = { SoundId = "rbxasset://sounds/victory.wav", Volume = 0.4, Pitch = 1.3 },
		RareReward = { SoundId = "rbxasset://sounds/electronicpingshort.wav", Volume = 0.6, Pitch = 0.85 },
		Delivery = { SoundId = "rbxasset://sounds/electronicpingshort.wav", Volume = 0.3, Pitch = 0.7 },
	},
	-- The machine (heard by everyone near it, positional): item goes in, soft ratchet while it
	-- works, a ding when it is done.
	Machine = {
		Start = { SoundId = "rbxasset://sounds/Kerplunk.wav", Volume = 0.45, Pitch = 0.9 },
		Loop = { SoundId = "rbxasset://sounds/clickfast.wav", Volume = 0.07, Pitch = 0.45 },
		Done = { SoundId = "rbxasset://sounds/electronicpingshort.wav", Volume = 0.4, Pitch = 1.3 },
		Range = 40, -- studs at which the machine falls silent
	},
	-- Mythic item abilities (ItemController/Abilities).
	Abilities = {
		CometWhoosh = { SoundId = "rbxasset://sounds/Rocket whoosh 01.wav", Volume = 0.5, Pitch = 1.2 },
		CometImpact = { SoundId = "rbxasset://sounds/impact_explosion_03.mp3", Volume = 0.6, Pitch = 0.85 },
		StarChime = { SoundId = "rbxasset://sounds/electronicpingshort.wav", Volume = 0.25, Pitch = 1.6 },
	},
	-- The Rare Creature world event (client/CreatureController).
	Creature = {
		Appear = { SoundId = "rbxasset://sounds/electronicpingshort.wav", Volume = 0.35, Pitch = 1.25 },
		Catch = { SoundId = "rbxasset://sounds/electronicpingshort.wav", Volume = 0.5, Pitch = 1.9 },
		Range = 120,
	},
	CueCooldown = 0.8, -- seconds: the same cue never plays more often than this
	Defaults = { Music = 0.6, Sfx = 0.8, Muted = false, Graphics = "Auto" }, -- the player's own settings (0..1); Graphics: Auto | Lite | Full (client GraphicsController)
}

local function deepFreeze(value: any)
	if type(value) == "table" and not table.isfrozen(value) then
		for _, child in value do
			deepFreeze(child)
		end
		table.freeze(value)
	end
end
deepFreeze(AudioConfig)

return AudioConfig
