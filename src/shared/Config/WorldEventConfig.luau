--!strict
--[[
	WorldEventConfig: the Rare Creature world event (server/Services/WorldEventService).

	Every Interval seconds (per server, never shared between servers) one creature is picked
	by Weight, spawns at a random valid SpawnPoint and waits Duration seconds. The first
	player the server accepts gets one random item of RewardRarity (the existing recycle reward
	pool, Config/ItemConfig): into their hands, or on the ground at their feet (reserved for
	them) when their hands are full.

	Adding a creature later: a new entry in Creatures (+ a builder in
	server/Services/WorldEvents/CreatureModels). Each one may have its own weight, rarity,
	duration and model.

	SpawnPoints are open spots on paths and on the inner (open) side of the collection zones,
	away from bases, buildings and walls. The server still checks each one before use (ground
	below, nothing solid in the way, not on a base plot) and skips bad ones.
]]

local function polar(radius: number, degrees: number): Vector3
	local angle = math.rad(degrees)
	return Vector3.new(radius * math.cos(angle), 0, radius * math.sin(angle))
end

local spawnPoints: { Vector3 } = {}
-- On the 4 spokes (paths from the plaza to the ring road).
for _, degrees in { 0, 90, 180, 270 } do
	table.insert(spawnPoints, polar(72, degrees))
	table.insert(spawnPoints, polar(118, degrees))
end
-- The open inner side of the 4 collection zones.
for _, degrees in { 45, 135, 225, 315 } do
	table.insert(spawnPoints, polar(74, degrees))
end
-- The ring road between two bases.
for _, degrees in { 22.5, 67.5, 112.5, 157.5, 202.5, 247.5, 292.5, 337.5 } do
	table.insert(spawnPoints, polar(146, degrees))
end

local WorldEventConfig = {
	Interval = 300, -- seconds between two creatures
	Tag = "WorldCreature", -- CollectionService tag on the creature model (clients animate it)
	FolderName = "WorldCreatures", -- Folder in Workspace

	PromptDistance = 10, -- studs: the "Catch" prompt appears
	ClaimDistance = 14, -- studs: the server's limit (prompt distance + lag allowance)
	ClaimCooldown = 0.5, -- seconds between two claim attempts of one player
	FadeTime = 1.2, -- seconds the disappear animation may play before the model is removed

	SpawnClearance = Vector3.new(6, 6, 6), -- this box above the ground must be free of solid parts
	SpawnPoints = spawnPoints,

	Creatures = {
		ScrapFox = {
			DisplayName = "Scrap Fox",
			Model = "ScrapFox",
			Weight = 1,
			Duration = 90,
			RewardRarity = "Rare",
		},
	},
}

local function deepFreeze(value: any)
	if type(value) == "table" and not table.isfrozen(value) then
		for _, child in value do
			deepFreeze(child)
		end
		table.freeze(value)
	end
end
deepFreeze(WorldEventConfig)

return WorldEventConfig
