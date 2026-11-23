--!strict
--[[
	Behaviors: what functional crafted items DO. An item opts in through its BehaviorId
	(Config/Items/Crafted); this table holds the behavior's tunables. Items whose BehaviorId is
	not listed here are ordinary carryable items (nothing breaks, they just have no action yet).

	Fields
	  Kind     server module in ServerScriptService.Server.Services.Behaviors/<Kind> and the
	           client feature that drives it: "Vehicle" | "Cart" | "Radio" | "Detector"
	  Mode     "Place" = selected in the hotbar, placed in the world (preview -> server checks)
	           "Use"   = used while carried (no world object)
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

local VALID_KINDS = { Vehicle = true, Cart = true, Radio = true, Detector = true }

for id, behavior in Behaviors :: { [string]: any } do
	assert(VALID_KINDS[behavior.Kind], `[Behaviors] "{id}" has unknown Kind "{tostring(behavior.Kind)}"`)
	assert(behavior.Mode == "Place" or behavior.Mode == "Use", `[Behaviors] "{id}" has unknown Mode`)
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
