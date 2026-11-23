--!strict
--[[
	GameConfig: central tunables shared by server and client.

	Read-only at runtime (deep-frozen at the bottom).
	This module replicates to every client, so never put secrets in here.
	The Debug flags only take effect inside Roblox Studio (checked by the code that reads them).
]]

local GameConfig = {
	Data = {
		StoreName = "PlayerData",
		KeyPrefix = "Player_",
		-- Bump when the profile shape changes and add a migration in DataService.
		ProfileVersion = 6, -- 2: Carry, Machine (2A); 3: Deployed (2B); 4: economy (3); 5: Base (4); 6: cosmetics
	},

	Klunks = {
		Name = "Klunks",
		Symbol = "K", -- display format: "250 K"
		MaxBalance = 1_000_000_000_000,
	},

	Carry = {
		MaxJunk = 6, -- max junk objects one player can carry at once
		PickupCooldown = 0.2, -- seconds between pickup attempts per player (server side)
		-- Extra studs on top of Junk.PickupMaxDistance that the server still accepts,
		-- to absorb lag between the player's client and the server.
		PickupDistanceTolerance = 8,
	},

	Junk = {
		-- Junk objects lying in the world, server-wide. Natural spawning stops at this number;
		-- drops and throws may exceed it briefly but expire (DroppedLifetime). Lower it for
		-- weaker devices.
		MaxActive = 150,
		ContainerName = "JunkContainer", -- Folder in Workspace, created automatically
		SpawnTag = "JunkSpawn", -- optional: tag Parts with this to define spawn areas
		InitialSpawnPerStep = 5, -- objects created per frame during the initial fill
		-- Replenishment (Stage 4): the yard is NOT topped up continuously. Every Interval seconds
		-- a "scrap delivery" spawns what is missing up to the target, so picked areas stay empty
		-- for a while and exploring other zones pays off. Clients show a countdown.
		Replenish = {
			Interval = 300, -- seconds between deliveries
			BaseTarget = 50, -- natural items wanted in the yard with one player...
			PerPlayer = 8, -- ...plus this many per additional player
			MaxTarget = 130, -- never more natural items than this (MaxActive stays the hard cap)
			BatchPerStep = 4, -- items created per frame during a delivery
			MinPlayerDistance = 30, -- studs: nothing pops into existence right next to a player
			CellSize = 24, -- studs: the yard is split into cells ("spawn points")...
			CellCooldown = 240, -- ...and a cell that just got an item waits this long for the next
			NaturalLifetime = 1500, -- seconds an untouched natural item stays (expires only when nobody is near)
		},
		MinSpacing = 5, -- minimum studs between two junk objects (150 junk fit the 4 zones comfortably)
		SpawnAttempts = 12, -- random positions tried before giving up on one spawn
		PickupMaxDistance = 10, -- ProximityPrompt activation distance in studs
		MinGroundNormalY = 0.7, -- ignore surfaces steeper than this (1 = flat)
		DroppedLifetime = 300, -- seconds a dropped/thrown object may lie untouched before it despawns
		CleanupInterval = 5, -- seconds between expiry checks (one loop for all junk)
		PoolSizePerType = 6, -- removed world models kept for reuse, per junk type

		-- Used only when no Part carries the SpawnTag: a square area around the center.
		FallbackCenter = Vector3.new(0, 0, 0),
		FallbackHalfExtent = 180,
		RayStartHeight = 200, -- height the downward ground search starts from (fallback area)
		RayLength = 400, -- length of the downward ground search
	},

	-- Throws are simulated as a ballistic arc (no engine physics). The server derives the
	-- velocity itself from the aim point; the client can only choose where to aim.
	Throw = {
		Cooldown = 0.35, -- seconds between throws per player
		LaunchAngle = 35, -- degrees above horizontal
		Gravity = 90, -- studs/s^2 used for the arc (lower than Workspace.Gravity = floatier)
		MinRange = 8, -- horizontal studs; aiming closer still throws this far
		MaxRange = 60, -- horizontal studs; aiming further is clamped to this
		OriginHeight = 1.5, -- studs above the HumanoidRootPart where the throw starts
		OriginForward = 1.5, -- studs in front of the character
		MaxFlightTime = 3, -- seconds; the arc is cut off after this
		SimulationStep = 1 / 30, -- seconds per raycast segment along the arc
		FxRange = 400, -- only players within this many studs receive the throw visual
	},

	-- Client input bindings. Change keys here; the UI hints read from the same table.
	Input = {
		ThrowKeys = { Enum.KeyCode.F, Enum.KeyCode.ButtonR2 },
		ThrowWithMouseButton = true, -- left mouse button also throws (hold = aim preview)
		SlotKeys = {
			Enum.KeyCode.One,
			Enum.KeyCode.Two,
			Enum.KeyCode.Three,
			Enum.KeyCode.Four,
			Enum.KeyCode.Five,
			Enum.KeyCode.Six,
			Enum.KeyCode.Seven, -- slots 7-9 exist only with the Bigger Backpack upgrade
			Enum.KeyCode.Eight,
			Enum.KeyCode.Nine,
		},
		NextSlotKeys = { Enum.KeyCode.ButtonR1 },
		PrevSlotKeys = { Enum.KeyCode.ButtonL1 },
		PickupKey = Enum.KeyCode.E,
		PickupGamepadKey = Enum.KeyCode.ButtonX,
		-- The machine has its own key, so junk lying next to it never hides its prompt.
		MachineKey = Enum.KeyCode.R,
		MachineGamepadKey = Enum.KeyCode.ButtonY,
		-- The base chest and building slots (own key: the machine prompt reaches far).
		BaseKey = Enum.KeyCode.C,
		BaseGamepadKey = Enum.KeyCode.ButtonL2,
		AimRayLength = 500, -- studs the mouse / screen-center aim ray reaches
		-- Functional items: Use / Place the item selected in the hotbar.
		UseKey = Enum.KeyCode.G,
		-- The bag (carried + base storage).
		BagKey = Enum.KeyCode.B,
		BagGamepadKey = Enum.KeyCode.ButtonSelect,
		UseGamepadKey = Enum.KeyCode.DPadUp,
		-- While placing: confirm with UseKey / left mouse / ButtonR2 / the PLACE button, cancel here.
		CancelKey = Enum.KeyCode.Q,
		CancelGamepadKey = Enum.KeyCode.ButtonB,
		ConfirmGamepadKey = Enum.KeyCode.ButtonR2,
		-- Prompts on placed objects (one key per action, so they never hide each other).
		Interact = {
			Primary = { Key = Enum.KeyCode.E, Gamepad = Enum.KeyCode.ButtonX }, -- drive / ride / tow / play
			Secondary = { Key = Enum.KeyCode.Z, Gamepad = Enum.KeyCode.DPadLeft }, -- load / next track
			Tertiary = { Key = Enum.KeyCode.X, Gamepad = Enum.KeyCode.DPadRight }, -- unload
			Store = { Key = Enum.KeyCode.T, Gamepad = Enum.KeyCode.DPadDown }, -- pick it back up
		},
	},

	-- Placing functional items in the world (PlacementService). The server checks every rule;
	-- the client preview uses the same numbers so green/red matches.
	Placement = {
		MaxDistance = 18, -- studs from the character to the placed object's center
		DistanceTolerance = 6, -- extra studs the server accepts (lag)
		PreviewDistance = 4, -- studs in front of the character to the object's near edge
		MaxDeployed = 5, -- placed objects per player
		MaxVehicles = 2, -- of those, vehicles
		MinGroundNormalY = 0.8, -- flat enough ground only
		MachineClearance = 10, -- studs to keep from any machine
		RayHeight = 8, -- the ground search starts this far above the requested point
		RayLength = 20,
		InteractDistance = 10, -- ProximityPrompt distance on placed objects
		FallResetY = -40, -- an object below this height is returned to its owner's plot
	},

	Inventory = {
		-- Hard cap on stored items per player; protects the DataStore value size.
		MaxItems = 1000,
	},

	RateLimits = {
		Default = { MaxRequests = 10, Window = 1 },
		GetSnapshot = { MaxRequests = 3, Window = 5 },
		ThrowRequest = { MaxRequests = 6, Window = 1 },
		MachineStart = { MaxRequests = 3, Window = 2 }, -- recycle / craft / mythic
		MachineTake = { MaxRequests = 6, Window = 2 },
		MachineUpgrade = { MaxRequests = 3, Window = 2 },
		-- Clicks above this rate are rejected (not counted): an autoclicker gains nothing extra.
		MachineAccelerate = { MaxRequests = 10, Window = 1 },
		ItemPlace = { MaxRequests = 3, Window = 2 },
		ItemUse = { MaxRequests = 4, Window = 1 },
		VehicleInput = { MaxRequests = 30, Window = 1 },
		SellItems = { MaxRequests = 3, Window = 2 },
		ShopBuy = { MaxRequests = 4, Window = 2 },
		PlayerUpgradeBuy = { MaxRequests = 3, Window = 2 },
		StorageMove = { MaxRequests = 8, Window = 1 },
		BaseAction = { MaxRequests = 4, Window = 2 },
		SaveSettings = { MaxRequests = 3, Window = 3 },
	},

	Debug = {
		-- Run server/DevTests.luau on startup (Studio only). Off by default: the tests teleport the
		-- player for about a minute. Set ServerScriptService attribute RunDevTests = true to run once.
		EnableDevTests = false,
		-- true = ProfileStore.Mock in Studio: nothing is saved between Play sessions. Off so Studio
		-- tests keep progress like the live game (needs Game Settings > Security > Enable Studio
		-- Access to API Services). DevTests always use the Mock store (they rewrite the profile).
		UseMockStore = false,
		SimulateLoadFailure = false, -- pretend profile loading failed (Studio only)
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

deepFreeze(GameConfig)

return GameConfig
