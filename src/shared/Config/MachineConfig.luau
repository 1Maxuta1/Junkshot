--!strict
--[[
	MachineConfig: personal Recycling/Crafting machine tunables, shared by server (authority)
	and client (presentation). Rarity chances live in DropTables, recipes in Recipes.

	Durations are seconds BEFORE upgrades/boosts (see MachineService.DurationFor):
	  final = base * Speed upgrade multiplier * permanent pass multiplier * active boost multiplier
	Mythic Crafting is always exactly MythicDuration (only clicks / instant finish shorten it).
]]

local MachineConfig = {
	Tag = "RecyclingMachine", -- machine models carry this tag
	TemplateName = "RecyclingMachine", -- ServerStorage.Assets.<TemplateName>

	RecycleDuration = 30,
	CraftDurations = {
		Common = 60,
		Uncommon = 5 * 60,
		Rare = 10 * 60,
		Epic = 30 * 60,
		Legendary = 60 * 60,
		Mythic = 6 * 60 * 60,
	},
	MythicDuration = 6 * 60 * 60,
	MythicInputs = 3,
	-- Exact ingredient combinations (sorted item ids) with a fixed Mythic Crafting result.
	MythicCombos = {
		{ Inputs = { "crystal_shard", "crystal_shard", "crystal_shard" }, Result = "comet_shard" },
		{ Inputs = { "aurora_orb", "frozen_crown", "golden_wrench" }, Result = "starforged_core" },
	},
	MinDuration = 5, -- no upgrade combination makes a job shorter than this

	SecondsPerClick = 1, -- every valid acceleration click removes exactly this much
	MaxClickShare = 0.5, -- all clicks of one job together remove at most this share of its duration

	UseDistance = 22, -- studs from the machine within which items can be inserted / taken
	PromptDistance = 14, -- the machine ProximityPrompt's activation distance

	-- Upgrades are bought with Klunks. Prices are placeholders until the Economy stage.
	-- Each level's entry: { Price, Value }; level 0 (or the first Level) is the free default.
	Upgrades = {
		Speed = {
			DisplayName = "Processing Speed",
			Description = "Every process takes less time.",
			Levels = {
				{ Price = 0, Value = 1 }, -- duration multiplier
				{ Price = 500, Value = 0.9 },
				{ Price = 1500, Value = 0.8 },
				{ Price = 4000, Value = 0.7 },
				{ Price = 10000, Value = 0.6 },
				{ Price = 25000, Value = 0.5 },
			},
		},
		Storage = {
			DisplayName = "Output Storage",
			Description = "More finished items can wait on the tray.",
			Levels = {
				{ Price = 0, Value = 1 }, -- output slots
				{ Price = 1000, Value = 2 },
				{ Price = 5000, Value = 3 },
			},
		},
		Level = {
			DisplayName = "Machine Level",
			Description = "Unlocks advanced recipes.",
			Levels = {
				{ Price = 0, Value = 1 }, -- machine level
				{ Price = 3000, Value = 2 },
				{ Price = 15000, Value = 3 },
			},
		},
	},
	UpgradeOrder = { "Speed", "Storage", "Level" },
}

local function deepFreeze(value: any)
	if type(value) == "table" and not table.isfrozen(value) then
		for _, child in value do
			deepFreeze(child)
		end
		table.freeze(value)
	end
end

deepFreeze(MachineConfig)

return MachineConfig
