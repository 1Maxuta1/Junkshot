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
			{ Name = "Christmas Party", SoundId = "rbxassetid://9041771148" }, -- APM Music
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
	CueCooldown = 0.8, -- seconds: the same cue never plays more often than this
	Defaults = { Music = 0.6, Sfx = 0.8, Muted = false }, -- the player's own settings (0..1)
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
