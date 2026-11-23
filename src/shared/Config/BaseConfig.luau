--!strict
--[[
	BaseConfig: the personal base (BaseService). Every number the server checks lives here;
	the client only displays it. Positions are relative to the plot's top center, -Z towards
	the ring road (the machine stands at (0, 0, 6)).

	Chest       the base storage (InventoryService) is the chest: deposit / withdraw only
	            standing at it. Capacity grows with the chest level (+ Storage Rack buildings).
	BaseLevels  unlock building slots (base expansion).
	Slots       predefined building places (no free-form editor yet).
	Buildings   what can stand on a slot. Each: DisplayName, Description, Model (BaseModels),
	            RequiredBaseLevel, MaxPerBase, Levels = { { Price, Value, RequiredLevel? } }
	            (Levels[1] = building it; more levels = upgrades). Value means:
	              Conveyor      belt speed in studs/s
	              StorageRack   extra chest slots
	              DisplayStand  -
	              Lantern       -
	RemoveRefund  share of the money spent that comes back when a building is removed.
]]

local BaseConfig = {
	Chest = {
		Position = Vector3.new(-15, 0, 14),
		UseDistance = 12, -- studs from the chest within which items can be moved in / out
		Levels = {
			{ Capacity = 10, Price = 0, Name = "Wooden Crate" },
			{ Capacity = 20, Price = 450, Name = "Reinforced Chest" },
			{ Capacity = 35, Price = 1000, Name = "Metal Container", RequiredLevel = 3 },
			{ Capacity = 55, Price = 3500, Name = "Industrial Container", RequiredLevel = 5 },
			{ Capacity = 80, Price = 9000, Name = "Secure Storage Unit", RequiredLevel = 8 },
		},
	},

	BaseLevels = {
		{ Slots = 1, Price = 0 },
		{ Slots = 3, Price = 1500, RequiredLevel = 3 },
		{ Slots = 4, Price = 6000, RequiredLevel = 6 },
	},

	Slots = {
		{ Id = "S1", Position = Vector3.new(15, 0, 14) },
		{ Id = "S2", Position = Vector3.new(15, 0, 2) },
		{ Id = "S3", Position = Vector3.new(-15, 0, 2) },
		{ Id = "S4", Position = Vector3.new(15, 0, -10) },
	},
	SlotSize = 9, -- studs: square footprint of one slot

	Buildings = {
		Conveyor = {
			DisplayName = "Scrap Conveyor",
			Description = "Throw junk onto the belt: it rolls straight into your chest.",
			Model = "Conveyor",
			RequiredBaseLevel = 1,
			MaxPerBase = 2,
			Levels = {
				{ Price = 600, Value = 4 },
				{ Price = 1500, Value = 7, RequiredLevel = 4 },
			},
		},
		StorageRack = {
			DisplayName = "Storage Rack",
			Description = "Shelves next to your chest: +15 chest slots.",
			Model = "StorageRack",
			RequiredBaseLevel = 2,
			MaxPerBase = 1,
			Levels = {
				{ Price = 2500, Value = 15, RequiredLevel = 4 },
			},
		},
		DisplayStand = {
			DisplayName = "Trophy Stand",
			Description = "Shows off the rarest item in your chest.",
			Model = "DisplayStand",
			RequiredBaseLevel = 1,
			MaxPerBase = 2,
			Levels = {
				{ Price = 250, Value = 0 },
			},
		},
		Lantern = {
			DisplayName = "Warm Lantern",
			Description = "A cosy light for your workshop.",
			Model = "Lantern",
			RequiredBaseLevel = 1,
			MaxPerBase = 4,
			Levels = {
				{ Price = 100, Value = 0 },
			},
		},
	},
	BuildingOrder = { "Conveyor", "StorageRack", "DisplayStand", "Lantern" },
	RemoveRefund = 0.5,

	Conveyor = {
		Length = 8, -- studs of belt; items travel along the slot's +Z into the hopper at the end
		Width = 3.4,
		Step = 0.15, -- seconds between conveyor updates (one loop for all conveyors)
	},
}

for id, building in BaseConfig.Buildings :: { [string]: any } do
	assert(#building.Levels >= 1, `[BaseConfig] building "{id}" needs a level`)
	assert(table.find(BaseConfig.BuildingOrder, id), `[BaseConfig] building "{id}" missing from BuildingOrder`)
end
assert(#BaseConfig.Slots >= BaseConfig.BaseLevels[#BaseConfig.BaseLevels].Slots, "[BaseConfig] not enough slots")

local function deepFreeze(value: any)
	if type(value) == "table" and not table.isfrozen(value) then
		for _, child in value do
			deepFreeze(child)
		end
		table.freeze(value)
	end
end
deepFreeze(BaseConfig)

return BaseConfig
