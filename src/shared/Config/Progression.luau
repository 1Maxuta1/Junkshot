--!strict
--[[
	Progression: player level and experience (ProgressionService awards it, server only).

	XP comes from meaningful, non-repeatable or time-gated actions, so standing still or
	repeating one click earns nothing:
	  Discover   the first time an item id ever reaches your hands or storage (per rarity)
	  Craft      a finished crafting job (per rarity of the result); Mythic crafting finished
	  Recycle    a finished recycling job (30 s each, input is finite yard junk)
	  Sell       1 XP per SellCoinsPerXp coins earned at the dealer (items are consumed)
	Levels unlock shop entries and player upgrades (their RequiredLevel).
]]

local Progression = {
	MaxLevel = 50,
	-- XP needed to go from `level` to `level + 1`.
	XpBase = 60,
	XpExponent = 1.6,

	Discover = { Common = 5, Uncommon = 15, Rare = 40, Epic = 100, Legendary = 250, Mythic = 600 },
	Craft = { Common = 10, Uncommon = 25, Rare = 50, Epic = 120, Legendary = 300, Mythic = 800 },
	MythicCraft = 400,
	Recycle = 4,
	SellCoinsPerXp = 10,
}

function Progression.XpToNext(level: number): number
	return math.floor(Progression.XpBase * level ^ Progression.XpExponent + 0.5)
end

return table.freeze(Progression)
