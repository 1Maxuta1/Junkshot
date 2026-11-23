--!strict
--[[
	PlayerUpgrades: permanent player improvements bought with the currency
	(PlayerUpgradeService validates and applies them; the client only displays this table).

	Each upgrade: Id, DisplayName, Description, Unit (how Value is shown) and Levels.
	Levels[1] is the free starting level. Levels[n] = { Price, Value, RequiredLevel? }:
	  Price          cost to reach this level from the one before
	  Value          the effect at this level (see Effect)
	  RequiredLevel  player level needed to buy it (Config/Progression)
	The current level of each upgrade is saved in profile.Data.PlayerUpgrades[Id].

	Effects (applied by the server)
	  CarryCapacity    extra hand slots on top of GameConfig.Carry.MaxJunk
	  WalkSpeed        Humanoid.WalkSpeed (Roblox default 16)
	  PickupRange      studs from which loose items can be picked up
	  (StorageCapacity moved to the base chest in Stage 4: Config/BaseConfig)
	  Haggler          extra share paid when selling (0.05 = +5%)
	Balance: each step is noticeable but small; the last levels are long-term goals.
]]

export type Level = { Price: number, Value: number, RequiredLevel: number? }
export type Upgrade = {
	Id: string,
	DisplayName: string,
	Description: string,
	Unit: string,
	Levels: { Level },
}

local list: { Upgrade } = {
	{
		Id = "CarryCapacity",
		DisplayName = "Bigger Backpack",
		Description = "Carry more items at once.",
		Unit = "slots",
		Levels = {
			{ Price = 0, Value = 0 },
			{ Price = 800, Value = 1, RequiredLevel = 2 },
			{ Price = 1500, Value = 2, RequiredLevel = 4 },
			{ Price = 5000, Value = 3, RequiredLevel = 7 },
		},
	},
	{
		Id = "WalkSpeed",
		DisplayName = "Snow Boots",
		Description = "Walk a little faster.",
		Unit = "speed",
		Levels = {
			{ Price = 0, Value = 16 },
			{ Price = 500, Value = 17 },
			{ Price = 800, Value = 18, RequiredLevel = 3 },
			{ Price = 2000, Value = 19, RequiredLevel = 5 },
			{ Price = 5000, Value = 20, RequiredLevel = 8 },
		},
	},
	{
		Id = "PickupRange",
		DisplayName = "Grabber Arm",
		Description = "Pick things up from further away.",
		Unit = "studs",
		Levels = {
			{ Price = 0, Value = 10 },
			{ Price = 600, Value = 12, RequiredLevel = 2 },
			{ Price = 1200, Value = 14, RequiredLevel = 4 },
			{ Price = 3500, Value = 16, RequiredLevel = 6 },
		},
	},
	-- "StorageCapacity" (Stage 3) moved to the base chest (Config/BaseConfig.Chest); saved levels
	-- were converted into chest levels by the 4 -> 5 profile migration.
	{
		Id = "Haggler",
		DisplayName = "Haggler",
		Description = "The Scrap Dealer pays you more.",
		Unit = "%",
		Levels = {
			{ Price = 0, Value = 0 },
			{ Price = 1000, Value = 0.03, RequiredLevel = 3 },
			{ Price = 4000, Value = 0.06, RequiredLevel = 6 },
			{ Price = 12000, Value = 0.1, RequiredLevel = 10 },
		},
	},
}

local byId: { [string]: Upgrade } = {}
for _, upgrade in list do
	assert(byId[upgrade.Id] == nil, `[PlayerUpgrades] duplicate "{upgrade.Id}"`)
	assert(#upgrade.Levels >= 2, `[PlayerUpgrades] "{upgrade.Id}" needs at least 2 levels`)
	for index, level in upgrade.Levels do
		assert(level.Price >= 0 and level.Price % 1 == 0, `[PlayerUpgrades] "{upgrade.Id}" level {index} has a bad price`)
	end
	byId[upgrade.Id] = upgrade
end

local function deepFreeze(value: any)
	if type(value) == "table" and not table.isfrozen(value) then
		for _, child in value do
			deepFreeze(child)
		end
		table.freeze(value)
	end
end
deepFreeze(list)

local PlayerUpgrades = {}

PlayerUpgrades.List = list

function PlayerUpgrades.Get(id: string): Upgrade?
	return byId[id]
end

-- The effect value at a (1-based) level; clamps out-of-range levels.
function PlayerUpgrades.ValueAt(id: string, level: number): number
	local upgrade = byId[id]
	if upgrade == nil then
		return 0
	end
	local index = math.clamp(math.floor(level), 1, #upgrade.Levels)
	return upgrade.Levels[index].Value
end

-- The largest extra carry slot count any upgrade can give (hotbar size).
function PlayerUpgrades.MaxCarryBonus(): number
	local upgrade = byId.CarryCapacity
	return upgrade.Levels[#upgrade.Levels].Value
end

return table.freeze(PlayerUpgrades)
