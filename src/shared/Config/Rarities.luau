--!strict
--[[
	Rarities: the rarity ladder AND its balancing data. This is the single place for rarity
	chances and colors; no other script may hardcode them.

	  Chance   percent chance that a recycled reward rolls this rarity. The chances must add
	           up to 100 (checked at startup). Change them here to rebalance.
	  Color    the rarity's UI / effect color.
	  Effect   presentation tier used by the reward reveal (0 = plain ... 5 = most dramatic).

	Rolling happens on the server only (RewardService). Clients read this module just to
	color things.
]]

export type RarityInfo = {
	Id: string,
	DisplayName: string,
	Rank: number, -- 1 = most common
	Chance: number, -- percent
	Color: Color3,
	Effect: number,
}

local Rarities = {}

-- Order matters: it is the ladder from most common to rarest.
local ladder: { RarityInfo } = {
	{ Id = "Common", DisplayName = "Common", Rank = 1, Chance = 55, Color = Color3.fromRGB(196, 204, 216), Effect = 0 },
	{ Id = "Uncommon", DisplayName = "Uncommon", Rank = 2, Chance = 25, Color = Color3.fromRGB(70, 206, 110), Effect = 1 },
	{ Id = "Rare", DisplayName = "Rare", Rank = 3, Chance = 12, Color = Color3.fromRGB(60, 150, 255), Effect = 2 },
	{ Id = "Epic", DisplayName = "Epic", Rank = 4, Chance = 6, Color = Color3.fromRGB(170, 90, 255), Effect = 3 },
	{ Id = "Legendary", DisplayName = "Legendary", Rank = 5, Chance = 1.8, Color = Color3.fromRGB(255, 196, 40), Effect = 4 },
	{ Id = "Mythic", DisplayName = "Mythic", Rank = 6, Chance = 0.2, Color = Color3.fromRGB(255, 70, 160), Effect = 5 },
}

local order: { string } = {}
local info: { [string]: RarityInfo } = {}
local total = 0
for rank, entry in ladder do
	assert(entry.Rank == rank, `[Rarities] {entry.Id} has rank {entry.Rank}, expected {rank}`)
	assert(entry.Chance >= 0, `[Rarities] {entry.Id} has a negative chance`)
	total += entry.Chance
	table.insert(order, entry.Id)
	info[entry.Id] = table.freeze(entry)
end
assert(math.abs(total - 100) < 1e-6, `[Rarities] chances add up to {total}, expected 100`)

Rarities.Order = table.freeze(order)
Rarities.Info = table.freeze(info)

function Rarities.IsValid(id: any): boolean
	return type(id) == "string" and info[id] ~= nil
end

function Rarities.Get(id: string): RarityInfo?
	return info[id]
end

-- Fallback color for unknown ids, so UI code never has to nil-check.
function Rarities.GetColor(id: string?): Color3
	local entry = if id ~= nil then info[id] else nil
	return if entry ~= nil then entry.Color else Color3.fromRGB(196, 204, 216)
end

return table.freeze(Rarities)
