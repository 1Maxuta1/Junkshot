--!strict
--[[
	Rarities: the rarity ladder and its presentation (color, effect tier).
	Drop CHANCES are not here: they live in Config/DropTables (recycling, world spawning and
	mythic crafting each have their own table).

	  Color    the rarity's UI / world-effect color.
	  Effect   presentation tier used by Util/RarityVisuals and the reward reveal
	           (0 = plain ... 5 = most dramatic).
]]

export type RarityInfo = {
	Id: string,
	DisplayName: string,
	Rank: number, -- 1 = most common
	Color: Color3,
	Effect: number,
}

local Rarities = {}

-- Order matters: it is the ladder from most common to rarest.
local ladder: { RarityInfo } = {
	{ Id = "Common", DisplayName = "Common", Rank = 1, Color = Color3.fromRGB(196, 204, 216), Effect = 0 },
	{ Id = "Uncommon", DisplayName = "Uncommon", Rank = 2, Color = Color3.fromRGB(70, 206, 110), Effect = 1 },
	{ Id = "Rare", DisplayName = "Rare", Rank = 3, Color = Color3.fromRGB(60, 150, 255), Effect = 2 },
	{ Id = "Epic", DisplayName = "Epic", Rank = 4, Color = Color3.fromRGB(170, 90, 255), Effect = 3 },
	{ Id = "Legendary", DisplayName = "Legendary", Rank = 5, Color = Color3.fromRGB(255, 196, 40), Effect = 4 },
	{ Id = "Mythic", DisplayName = "Mythic", Rank = 6, Color = Color3.fromRGB(255, 70, 160), Effect = 5 },
}

local order: { string } = {}
local info: { [string]: RarityInfo } = {}
for rank, entry in ladder do
	assert(entry.Rank == rank, `[Rarities] {entry.Id} has rank {entry.Rank}, expected {rank}`)
	table.insert(order, entry.Id)
	info[entry.Id] = table.freeze(entry)
end

Rarities.Order = table.freeze(order)
Rarities.Info = table.freeze(info)

function Rarities.IsValid(id: any): boolean
	return type(id) == "string" and info[id] ~= nil
end

function Rarities.Get(id: string): RarityInfo?
	return info[id]
end

function Rarities.GetRank(id: string?): number
	local entry = if id ~= nil then info[id] else nil
	return if entry ~= nil then entry.Rank else 1
end

-- Fallback color for unknown ids, so UI code never has to nil-check.
function Rarities.GetColor(id: string?): Color3
	local entry = if id ~= nil then info[id] else nil
	return if entry ~= nil then entry.Color else Color3.fromRGB(196, 204, 216)
end

return table.freeze(Rarities)
