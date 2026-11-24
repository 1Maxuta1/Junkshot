--!strict
--[[
	Behaviors: what functional crafted items DO. An item opts in through its BehaviorId
	(Config/Items/Crafted); this table holds the behavior's tunables. Items whose BehaviorId is
	not listed here are ordinary carryable items (nothing breaks, they just have no action yet).

	Fields
	  Kind     server module in ServerScriptService.Server.Services.Behaviors/<Kind> and the
	           client feature that drives it: "Vehicle" | "Cart" | "Radio" | "Detector" | "Ability" | "Gadget"
	  Mode     "Place" = selected in the hotbar, placed in the world (preview -> server checks)
	           "Use"   = used while carried (no world object)
	           "Activate" = an ability used while carried (left click too), with a cooldown
	  Model    Util/DeployModels builder name (Place only)
	  Storable the owner can pick the placed object back up into their hands (Place only)
	  FacePlayer  placed facing the player (otherwise facing where the player looks, like a
	           vehicle ready to drive off)

	Adding a new functional item: give its item a BehaviorId, add an entry here and, for a new
	Kind, one server module + (if it needs input) one client module. The item lifecycle,
	placement validation, persistence and prompts are shared and need no change.
]]

local Behaviors = {
	["Vehicle.Bicycle"] = {
		Kind = "Vehicle",
		Mode = "Place",
		Model = "Bicycle",
		Storable = true,
		Vehicle = {
			MaxSpeed = 34, -- studs/s (walking is 16)
			Acceleration = 22, -- studs/s^2
			Braking = 60, -- studs/s^2 when holding the opposite direction
			Coast = 14, -- studs/s^2 of slowdown without input
			ReverseSpeed = 8,
			TurnRate = 2.4, -- radians/s at speed
			PassengerCapacity = 0,
			EngineSoundId = nil,
			WheelRadius = 1.3,
		},
	},
	-- 1.5 times the bicycle's top speed.
	["Vehicle.Scooter"] = {
		Kind = "Vehicle",
		Mode = "Place",
		Model = "Scooter",
		Storable = true,
		Vehicle = {
			MaxSpeed = 51,
			Acceleration = 28,
			Braking = 65,
			Coast = 13,
			ReverseSpeed = 10,
			TurnRate = 2.2,
			PassengerCapacity = 0,
			EngineSoundId = nil,
			WheelRadius = 0.75,
		},
	},
	["Vehicle.Car"] = {
		Kind = "Vehicle",
		Mode = "Place",
		Model = "HomemadeCar",
		Storable = true,
		Vehicle = {
			MaxSpeed = 56,
			Acceleration = 20,
			Braking = 70,
			Coast = 12,
			ReverseSpeed = 18,
			TurnRate = 1.7,
			PassengerCapacity = 1,
			EngineSoundId = "rbxassetid://80317022777602", -- "Car-Engine-Loop", Roblox Resources
			WheelRadius = 1.1,
		},
	},
	["Tool.Cart"] = {
		Kind = "Cart",
		Mode = "Place",
		Model = "MetalCart",
		Storable = true, -- only when empty
		FacePlayer = true, -- placed with its handle towards the player
		Cart = {
			Capacity = 8, -- items it holds (hands hold 6)
			FollowDistance = 6.5, -- studs behind the owner while towed
			FollowSharpness = 8, -- higher = snappier following
			MaxTowDistance = 40, -- towing stops when the owner is further away (teleport, death)
		},
	},
	-- Wooden Sled: a small cart on runners.
	["Vehicle.Sled"] = {
		Kind = "Cart",
		Mode = "Place",
		Model = "WoodenSled",
		Storable = true,
		FacePlayer = true,
		Cart = {
			Capacity = 4,
			FollowDistance = 5.5,
			FollowSharpness = 9,
			MaxTowDistance = 40,
			ContentSize = 0.95,
			Slots = { Vector3.new(-0.5, 1.25, 0.8), Vector3.new(0.5, 1.25, 0.8), Vector3.new(-0.5, 1.25, -0.5), Vector3.new(0.5, 1.25, -0.5) },
		},
	},
	["Deploy.Radio"] = {
		Kind = "Radio",
		Mode = "Place",
		Model = "Radio",
		Storable = true,
		FacePlayer = true, -- speakers towards the player
		Radio = {
			Volume = 0.5,
			MaxDistance = 90, -- studs at which it becomes silent
			Cooldown = 0.4, -- seconds between button presses (per radio)
			-- Free tracks from the Roblox Creator Store (APM Music, usable in any experience).
			Tracks = {
				{ Name = "Into a Groove", SoundId = "rbxassetid://1841070181" },
				{ Name = "Sunshine People", SoundId = "rbxassetid://1841067510" },
				{ Name = "Daring Disco", SoundId = "rbxassetid://1841069706" },
			},
		},
	},
	-- Mythic abilities (Mode "Activate"): select the item, then left click / G / D-pad up / the
	-- action chip. A big effect everyone nearby sees, then a cooldown (saved, survives a rejoin).
	-- Purely a show-off: no items, money or advantage.
	["Ability.Comet"] = {
		Kind = "Ability",
		Mode = "Activate",
		Ability = {
			Effect = "Comet",
			Name = "Summon Comet",
			Cooldown = 300, -- seconds
			Distance = 22, -- studs in front of the player where it lands
		},
	},
	["Ability.Starfall"] = {
		Kind = "Ability",
		Mode = "Activate",
		Ability = {
			Effect = "Starfall",
			Name = "Starfall",
			Cooldown = 180,
			Distance = 0,
		},
	},
	["Vehicle.Kart"] = {
		Kind = "Vehicle",
		Mode = "Place",
		Model = "TurboKart",
		Storable = true,
		Vehicle = {
			MaxSpeed = 70,
			Acceleration = 30,
			Braking = 80,
			Coast = 14,
			ReverseSpeed = 18,
			TurnRate = 1.9,
			PassengerCapacity = 0,
			EngineSoundId = "rbxassetid://80317022777602",
			WheelRadius = 0.9,
		},
	},
	["Vehicle.JetBoard"] = {
		Kind = "Vehicle",
		Mode = "Place",
		Model = "JetBoard",
		Storable = true,
		Vehicle = {
			MaxSpeed = 62,
			Acceleration = 26,
			Braking = 55,
			Coast = 9,
			ReverseSpeed = 10,
			TurnRate = 2.3,
			PassengerCapacity = 0,
			EngineSoundId = nil,
			WheelRadius = 0.8,
		},
	},
	-- Storage Box: a cart that is never towed.
	["Deploy.Storage"] = {
		Kind = "Cart",
		Mode = "Place",
		Model = "Item:storage_box:1.8",
		Storable = true,
		FacePlayer = true,
		Cart = {
			Fixed = true,
			Capacity = 6,
			FollowDistance = 0,
			FollowSharpness = 0,
			MaxTowDistance = 0,
			ContentSize = 1,
			Slots = {
				Vector3.new(-1.2, 3.6, -0.6), Vector3.new(0, 3.6, -0.6), Vector3.new(1.2, 3.6, -0.6),
				Vector3.new(-1.2, 3.6, 0.6), Vector3.new(0, 3.6, 0.6), Vector3.new(1.2, 3.6, 0.6),
			},
		},
	},
	["Ability.RocketBoots"] = {
		Kind = "Ability",
		Mode = "Activate",
		Ability = { Effect = "RocketJump", Name = "Rocket Jump", Cooldown = 8, Distance = 0 },
	},
	["Tool.Magnet"] = {
		Kind = "Ability",
		Mode = "Activate",
		Ability = { Effect = "Magnet", Name = "Pull Scrap", Cooldown = 25, Distance = 0, Range = 28, Amount = 5 },
	},

	-- Gadgets: placed, press E (server Behaviors/Gadget, client GadgetController).
	-- Cycle: the prompt always offers the next entry of Modes; Modes[1] = the idle state.
	["Deploy.Throne"] = { Kind = "Gadget", Mode = "Place", Model = "GoldenThrone", Storable = true, FacePlayer = true,
		Gadget = { Effect = "Throne", Action = "Sit", Label = "Sit" } },
	["Deploy.Teleport"] = { Kind = "Gadget", Mode = "Place", Model = "Item:teleport_pad:2", Storable = true, FacePlayer = true,
		Gadget = { Effect = "Teleporter", Action = "Teleport", Label = "Teleport", TravelCooldown = 5 } },
	["Deploy.Panel"] = { Kind = "Gadget", Mode = "Place", Model = "Item:glass_panel:2.4", Storable = true, FacePlayer = true,
		Gadget = { Effect = "Panel", Action = "Cycle", Modes = { "Clear", "Blue", "Red", "Gold", "Green", "Dark" } } },
	["Deploy.Television"] = { Kind = "Gadget", Mode = "Place", Model = "Item:neon_tv:2", Storable = true, FacePlayer = true,
		Gadget = { Effect = "Television", Action = "Cycle", Modes = { "Switch off", "Yard news", "Race channel", "Cartoon", "Party colors" } } },
	["Deploy.Disco"] = { Kind = "Gadget", Mode = "Place", Model = "Item:disco_ball:2", Storable = true, FacePlayer = true,
		Gadget = { Effect = "Disco", Action = "Cycle", Modes = { "Stop party", "Start party" } } },
	["Deploy.Fountain"] = { Kind = "Gadget", Mode = "Place", Model = "Item:duck_fountain:2.4", Storable = true, FacePlayer = true,
		Gadget = { Effect = "Fountain", Action = "Cycle", Modes = { "Turn off", "Water on", "Rainbow water" } } },
	["Deploy.SnowMachine"] = { Kind = "Gadget", Mode = "Place", Model = "Item:snow_machine:2", Storable = true, FacePlayer = true,
		Gadget = { Effect = "SnowMachine", Action = "Cycle", Modes = { "Turn off", "Make snow", "Blizzard" } } },
	["Deploy.FrostLamp"] = { Kind = "Gadget", Mode = "Place", Model = "Item:frost_lamp:2", Storable = true, FacePlayer = true,
		Gadget = { Effect = "Lamp", Action = "Cycle", Modes = { "Light off", "Ice light", "Warm light", "Violet light" } } },
	["Deploy.Band"] = { Kind = "Gadget", Mode = "Place", Model = "Item:robot_band:1.8", Storable = true, FacePlayer = true,
		Gadget = { Effect = "Band", Action = "Cycle", Modes = { "Stop", "Play" } } },
	["Deploy.Beacon"] = { Kind = "Gadget", Mode = "Place", Model = "Item:crystal_beacon:2", Storable = true, FacePlayer = true,
		Gadget = { Effect = "Beacon", Action = "Cycle", Modes = { "Turn off", "Violet beam", "Blue beam", "Gold beam" } } },
	["Deploy.Reactor"] = { Kind = "Gadget", Mode = "Place", Model = "Item:aurora_reactor:1.8", Storable = true, FacePlayer = true,
		Gadget = { Effect = "Reactor", Action = "Cycle", Modes = { "Shut down", "Start aurora" } } },
	["Deploy.Generator"] = { Kind = "Gadget", Mode = "Place", Model = "Item:generator:1.8", Storable = true, FacePlayer = true,
		Gadget = { Effect = "Generator", Action = "Cycle", Modes = { "Shut down", "Start" } } },
	["Deploy.CosmicGate"] = { Kind = "Gadget", Mode = "Place", Model = "Item:cosmic_gate:2.4", Storable = true, FacePlayer = true,
		Gadget = { Effect = "Gate", Action = "Cycle", Modes = { "Close gate", "Golden gate", "Pink gate" } } },
	["Deploy.Incubator"] = { Kind = "Gadget", Mode = "Place", Model = "Item:dragon_incubator:2", Storable = true, FacePlayer = true,
		Gadget = { Effect = "Incubator", Action = "Cycle", Modes = { "Call it back", "Let it fly" } } },
	["Deploy.ToastCannon"] = { Kind = "Gadget", Mode = "Place", Model = "Item:toast_cannon:2", Storable = true, FacePlayer = true,
		Gadget = { Effect = "Toast", Action = "Fire", Label = "Launch toast", Cooldown = 3 } },
	["Deploy.PlasmaCannon"] = { Kind = "Gadget", Mode = "Place", Model = "Item:plasma_cannon:2", Storable = true, FacePlayer = true,
		Gadget = { Effect = "Plasma", Action = "Fire", Label = "Fireworks", Cooldown = 5 } },
	["Deploy.HighFive"] = { Kind = "Gadget", Mode = "Place", Model = "Item:high_five_machine:2.2", Storable = true, FacePlayer = true,
		Gadget = { Effect = "HighFive", Action = "Fire", Label = "High five!", Cooldown = 1.5 } },
	["Deploy.Snowman"] = { Kind = "Gadget", Mode = "Place", Model = "Item:scrap_snowman:2", Storable = true, FacePlayer = true,
		Gadget = { Effect = "Snowman", Action = "Fire", Label = "Snowball burst", Cooldown = 2 } },
	["Deploy.Arcade"] = { Kind = "Gadget", Mode = "Place", Model = "Item:arcade_machine:2.2", Storable = true, FacePlayer = true,
		Gadget = { Effect = "Arcade", Action = "Arcade", Label = "Play / React" } },
	["Deploy.Hologram"] = { Kind = "Gadget", Mode = "Place", Model = "Item:hologram_projector:2", Storable = true, FacePlayer = true,
		Gadget = { Effect = "Hologram", Action = "Hologram", Label = "Show held item" } },
	["Companion.Robot"] = { Kind = "Gadget", Mode = "Place", Model = "Item:junk_robot:1.8", Storable = true, FacePlayer = true,
		Gadget = { Effect = "Robot", Action = "Robot", Label = "Find treasure", Cooldown = 2 } },
	["Deploy.Launcher"] = { Kind = "Gadget", Mode = "Place", Model = "Item:spring_launcher:2.2", Storable = true, FacePlayer = true,
		Gadget = { Effect = "Launcher", Action = "None" } },
	["Tool.Detector"] = {
		Kind = "Detector",
		Mode = "Use",
		Detector = {
			Range = 90, -- studs searched around the player
			MinRarity = "Rare", -- weaker items are ignored
			ScanInterval = 1, -- seconds between scans while it is switched on
			HighlightDistance = 16, -- the target glows when the player is this close
		},
	},
}

local VALID_KINDS = { Vehicle = true, Cart = true, Radio = true, Detector = true, Ability = true, Gadget = true }

for id, behavior in Behaviors :: { [string]: any } do
	assert(VALID_KINDS[behavior.Kind], `[Behaviors] "{id}" has unknown Kind "{tostring(behavior.Kind)}"`)
	assert(behavior.Mode == "Place" or behavior.Mode == "Use" or behavior.Mode == "Activate", `[Behaviors] "{id}" has unknown Mode`)
	if behavior.Mode == "Place" then
		assert(type(behavior.Model) == "string", `[Behaviors] "{id}" needs a Model`)
	end
end

local function deepFreeze(value: any)
	if type(value) == "table" and not table.isfrozen(value) then
		for _, child in value do
			deepFreeze(child)
		end
		table.freeze(value)
	end
end

deepFreeze(Behaviors)

return Behaviors
