--!strict
--[[
	Recipes: the machine's Crafting mode, as data. Adding a recipe = adding one entry here.

	Design of the crafting tree
	  Junk + Materials --> Components (engine, motor, frame, battery pack, control panel)
	                   --> Creations (vehicles, tools, deployables, specials)
	  Higher tiers reuse lower-tier components, so players work their way up: a Bicycle needs
	  only junk, a Scooter needs a crafted Small Engine, a Homemade Car needs an engine AND a
	  frame, a Turbo Kart needs a Homemade Car.

	Fields (Types.Recipe)
	  RecipeId, DisplayName, Description, Category
	  Ingredients        { { Id, Count } }   item ids from ItemConfig; total Count <= carry size
	                                         (ingredients come from the carried items)
	  OutputItemId, OutputAmount
	  Rarity             the output's rarity; decides the duration (MachineConfig.CraftDurations)
	  RequiredLevel      machine level needed (MachineConfig.Upgrades.Level)
	  IsUnlockedByDefault, Special?, DurationOverride?
]]

local GameConfig = require(script.Parent.GameConfig)
local ItemConfig = require(script.Parent.ItemConfig)
local Types = require(script.Parent.Parent.Types)

local Recipes = {}

Recipes.Categories = table.freeze({ "Components", "Vehicles", "Tools", "Deployables", "Special" })

local function ing(id: string, count: number?): Types.RecipeIngredient
	return { Id = id, Count = count or 1 }
end

local function recipe(
	category: string,
	outputItemId: string,
	requiredLevel: number,
	description: string,
	ingredients: { Types.RecipeIngredient },
	extra: { Special: boolean?, DurationOverride: number? }?
): Types.Recipe
	local output = ItemConfig.Get(outputItemId)
	assert(output ~= nil, `[Recipes] unknown output item "{outputItemId}"`)
	return {
		RecipeId = outputItemId,
		DisplayName = output.DisplayName,
		Description = description,
		Category = category,
		Ingredients = ingredients,
		OutputItemId = outputItemId,
		OutputAmount = 1,
		Rarity = output.Rarity,
		RequiredLevel = requiredLevel,
		IsUnlockedByDefault = true,
		Special = if extra ~= nil then extra.Special else nil,
		DurationOverride = if extra ~= nil then extra.DurationOverride else nil,
	}
end

local list: { Types.Recipe } = {
	-- Components
	recipe("Components", "battery_pack", 1, "Wire a car battery into a portable pack.", {
		ing("car_battery"), ing("copper_wire"),
	}),
	recipe("Components", "metal_frame", 1, "Weld pipes and a sheet into a sturdy frame.", {
		ing("pipe_segment", 2), ing("metal_sheet"), ing("bolt_pack"),
	}),
	recipe("Components", "small_engine", 1, "Rebuild an engine from salvaged parts.", {
		ing("engine_part"), ing("gear_wheel"), ing("pipe_segment"), ing("bolt_pack"),
	}),
	recipe("Components", "electric_motor", 1, "Coil copper around a battery-driven gear.", {
		ing("copper_wire", 2), ing("car_battery"), ing("gear_wheel"),
	}),
	recipe("Components", "control_panel", 2, "A screen, a circuit and power: a brain for machines.", {
		ing("circuit_board"), ing("cracked_monitor"), ing("copper_wire"), ing("battery_pack"),
	}),

	-- Vehicles
	recipe("Vehicles", "wooden_sled", 1, "A crate on metal runners.", {
		ing("wooden_crate"), ing("metal_sheet"), ing("bolt_pack"),
	}),
	recipe("Vehicles", "bicycle", 1, "Two wheels and a pipe.", {
		ing("bike_wheel", 2), ing("pipe_segment"),
	}),
	recipe("Vehicles", "metal_cart", 1, "A metal tub on wheels for hauling scrap.", {
		ing("bike_wheel", 2), ing("metal_sheet", 2), ing("bolt_pack"),
	}),
	recipe("Vehicles", "scooter", 1, "Wheels, a pipe and a small engine.", {
		ing("bike_wheel", 2), ing("pipe_segment"), ing("small_engine"),
	}),
	recipe("Vehicles", "homemade_car", 2, "Four tires on a frame, powered by an engine.", {
		ing("old_tire", 4), ing("metal_frame"), ing("small_engine"),
	}),
	recipe("Vehicles", "turbo_kart", 3, "Strap a motor and a fuel barrel to your car.", {
		ing("homemade_car"), ing("electric_motor"), ing("control_panel"), ing("toxic_barrel"),
	}),

	-- Tools
	recipe("Tools", "flashlight", 1, "A lamp, a battery and a bucket reflector.", {
		ing("broken_lamp"), ing("car_battery"), ing("tin_bucket"),
	}),
	recipe("Tools", "metal_detector", 1, "A circuit on a stick that beeps near treasure.", {
		ing("circuit_board"), ing("copper_wire"), ing("pipe_segment"), ing("broken_lamp"),
	}),
	recipe("Tools", "scrap_magnet", 1, "Wrap copper around a fork and power it up.", {
		ing("copper_wire", 2), ing("car_battery"), ing("giant_fork"),
	}),

	-- Deployables
	recipe("Deployables", "storage_box", 1, "Two crates bolted together.", {
		ing("wooden_crate", 2), ing("bolt_pack"),
	}),
	recipe("Deployables", "spring_launcher", 1, "Springs under a plate. Mind your head.", {
		ing("bouncy_spring", 2), ing("metal_sheet"), ing("wooden_crate"),
	}),
	recipe("Deployables", "boombox_radio", 1, "Fix the old radio and give it a battery pack.", {
		ing("old_radio"), ing("copper_wire"), ing("battery_pack"),
	}),
	recipe("Deployables", "generator", 2, "An engine burning toxic fuel to make power.", {
		ing("small_engine"), ing("battery_pack"), ing("toxic_barrel"), ing("metal_sheet"),
	}),

	-- Special
	recipe("Special", "scrap_snowman", 1, "Stack cans and a bucket into a snowman.", {
		ing("tin_bucket"), ing("rusty_can", 2), ing("soda_bottle"),
	}),
	recipe("Special", "junk_robot", 2, "Give a bucket a brain and some gears.", {
		ing("control_panel"), ing("tin_bucket"), ing("gear_wheel"), ing("bouncy_spring"),
	}, { Special = true }),
	recipe("Special", "golden_trophy", 3, "Restore the dented trophy with gold paint and crystal.", {
		ing("dented_trophy"), ing("paint_bucket"), ing("crystal_shard"),
	}, { Special = true }),
	recipe("Special", "aurora_reactor", 3, "Bottle crystal power with a generator.", {
		ing("crystal_shard", 2), ing("control_panel"), ing("generator"),
	}, { Special = true }),
}

local byId: { [string]: Types.Recipe } = {}
local categories: { [string]: boolean } = {}
for _, name in Recipes.Categories do
	categories[name] = true
end

-- Fail loudly at startup on a broken recipe.
for _, entry in list do
	assert(byId[entry.RecipeId] == nil, `[Recipes] duplicate recipe "{entry.RecipeId}"`)
	assert(categories[entry.Category], `[Recipes] "{entry.RecipeId}" has unknown category "{entry.Category}"`)
	local total = 0
	for _, ingredient in entry.Ingredients do
		assert(ItemConfig.Exists(ingredient.Id), `[Recipes] "{entry.RecipeId}" uses unknown item "{ingredient.Id}"`)
		assert(ingredient.Count >= 1 and ingredient.Count % 1 == 0, `[Recipes] "{entry.RecipeId}" has a bad count`)
		total += ingredient.Count
		table.freeze(ingredient)
	end
	assert(total >= 1 and total <= GameConfig.Carry.MaxJunk,
		`[Recipes] "{entry.RecipeId}" needs {total} items; a player can carry only {GameConfig.Carry.MaxJunk}`)
	table.freeze(entry.Ingredients)
	byId[entry.RecipeId] = table.freeze(entry)
end

Recipes.List = table.freeze(list)

function Recipes.Get(recipeId: any): Types.Recipe?
	return if type(recipeId) == "string" then byId[recipeId] else nil
end

function Recipes.TotalIngredients(entry: Types.Recipe): number
	local total = 0
	for _, ingredient in entry.Ingredients do
		total += ingredient.Count
	end
	return total
end

return table.freeze(Recipes)
