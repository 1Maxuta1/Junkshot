--!strict
--[[
	Types: shared Luau type definitions (types only, no runtime logic).
	Usage: local Types = require(ReplicatedStorage.Shared.Types)
]]

export type RarityId = string

-- One entry of the item catalog (Config/ItemConfig + Config/Items/*).
export type ItemDefinition = {
	Id: string,
	DisplayName: string,
	Rarity: RarityId,
	Category: string, -- "Junk" | "Material" | "Collectible" | "Component" | "Crafted"
	Description: string?,
	-- How the item looks (built by JunkFactory.Build). Required for every non-debug item.
	Parts: { JunkPartSpec }?,
	NaturalSpawn: boolean?, -- may appear in the yard
	SpawnWeight: number?, -- relative chance within its rarity when the world spawns (default 1)
	RecyclePool: boolean?, -- may be produced by recycling / mythic crafting
	CanBeRecycled: boolean?, -- default true
	ItemType: string?, -- "Component" | "Vehicle" | "Tool" | "Deployable" | "Collectible" ...
	BehaviorId: string?, -- key into Config/Behaviors (e.g. "Vehicle.Bicycle"); see Util/ItemCapabilities
	IsDebug: boolean?,
}

-- One stored item: base storage (InventoryService), saved in the profile under Items[uid].
-- The uid is the same one the item had in the hands / world (it moves, it is not copied).
export type ItemRecord = {
	id: string, -- key into ItemConfig
	acquiredAt: number, -- os.time()
}

-- One physical item. Uid is generated once when the item first exists and stays the same
-- while it lies in the world, is carried, flies after a throw, waits in a machine's output
-- and lands again. Carried items and machine outputs are saved in the profile.
export type CarriedJunk = {
	Uid: string,
	Id: string, -- key into ItemConfig
}

-- The machine's public states (attribute "State" on the machine model).
export type MachineState = "Idle" | "Processing" | "RewardReady"

export type MachineJobKind = "Recycle" | "Craft" | "Mythic"

-- A running machine process. All times are Workspace:GetServerTimeNow() seconds (Unix time),
-- so a job keeps running while its owner is offline and on any server.
export type MachineJob = {
	Kind: MachineJobKind,
	Label: string, -- what the UI shows ("Recycling Rusty Can", recipe name ...)
	StartedAt: number,
	Duration: number, -- seconds, after upgrades
	Accelerated: number, -- seconds removed by clicks / boosts
	Inputs: { CarriedJunk }, -- consumed items (kept for support/audit)
	RecipeId: string?,
	Result: CarriedJunk, -- decided when the job starts (no re-roll by rejoining)
}

export type MachineUpgrades = {
	Speed: number,
	Storage: number,
	Level: number,
}

-- Saved per player in ProfileData.Machine.
export type MachineData = {
	Job: MachineJob?,
	Output: { CarriedJunk }, -- finished items waiting on the output tray
	Upgrades: MachineUpgrades,
	BoostUntil: number, -- server time until which the temporary speed boost applies
	InstantCredits: number, -- unused "instant finish" purchases
	ResultSeq: number, -- increments per finished job (clients reveal each result once)
}

-- A crafted item placed in the world (PlacementService). Saved in ProfileData.Deployed; while
-- it is here the same uid is NOT carried and NOT lying in the world as loose junk.
export type DeployedRecord = {
	Uid: string,
	Id: string, -- key into ItemConfig
	Contents: { CarriedJunk }?, -- items inside it (Metal Cart)
}

-- One currency movement (EconomyService). Kept as a short log in ProfileData.Economy.
export type Transaction = {
	Id: string, -- unique (the client's request id for sales / purchases)
	Type: string, -- "Earn" | "Spend"
	Amount: number,
	Reason: string, -- "Sell" | "Shop" | "PlayerUpgrade" | "MachineUpgrade" | ...
	Balance: number, -- balance right after
	At: number, -- os.time()
}

export type EconomyData = {
	Transactions: { Transaction }, -- most recent last, capped (EconomyConfig.TransactionLog)
	Requests: { string }, -- processed request ids, most recent last (duplicate protection)
}

export type ProgressData = {
	Level: number,
	XP: number, -- progress towards the next level
	Discovered: { [string]: boolean }, -- item ids seen at least once (first-time XP)
}

-- The personal base (BaseService). Chest contents are profile.Items (InventoryService).
export type BuildingState = { Id: string, Level: number }
export type BaseData = {
	Level: number, -- base expansion level (Config/BaseConfig.BaseLevels)
	ChestLevel: number,
	Buildings: { [string]: BuildingState }, -- slot id -> building
}

export type ProfileStats = {
	TotalKlunksEarned: number,
}

-- The saved player profile (Profile.Data).
export type ProfileData = {
	Version: number,
	Klunks: number,
	Items: { [string]: ItemRecord },
	Carry: { CarriedJunk },
	Machine: MachineData,
	Deployed: { DeployedRecord },
	PlayerUpgrades: { [string]: number }, -- upgrade id -> level (Config/PlayerUpgrades)
	Progress: ProgressData,
	Economy: EconomyData,
	Base: BaseData,
	Purchases: { string }, -- processed Robux receipt ids (most recent last)
	Stats: ProfileStats,
	Settings: { [string]: any },
}

-- What a client is allowed to see. Intentionally excludes Version, Stats and Settings.
export type DataSnapshot = {
	Seq: number,
	Klunks: number,
	Items: { [string]: ItemRecord },
}

-- Incremental updates pushed to the owning client. Seq increases per player.
export type DataChange =
	{ Seq: number, Kind: "Klunks", Klunks: number }
	| { Seq: number, Kind: "ItemAdded", Uid: string, Id: string, AcquiredAt: number }
	| { Seq: number, Kind: "ItemRemoved", Uid: string }

export type RateLimitConfig = {
	MaxRequests: number,
	Window: number, -- seconds
}

-- One visual piece of an item model (see Config/Items/Builder and Util/JunkFactory).
export type JunkPartSpec = {
	Shape: Enum.PartType,
	Size: Vector3,
	Color: Color3,
	Material: Enum.Material,
	Offset: Vector3, -- position relative to the item's origin
	Rotation: Vector3, -- degrees (X, Y, Z) relative to the item's origin
}

-- One recipe of the machine's Crafting mode (Config/Recipes).
export type RecipeIngredient = { Id: string, Count: number }

export type Recipe = {
	RecipeId: string,
	DisplayName: string,
	Description: string,
	Category: string,
	Ingredients: { RecipeIngredient },
	OutputItemId: string,
	OutputAmount: number,
	Rarity: RarityId, -- decides the crafting duration (MachineConfig.CraftDurations)
	RequiredLevel: number, -- machine level needed
	IsUnlockedByDefault: boolean,
	Special: boolean?,
	DurationOverride: number?, -- seconds, replaces the rarity duration
}

-- Server -> clients: one validated throw. The world object with this Uid already exists at
-- FinalPivot (sent just before it replicates); clients move THAT object along the arc locally
-- and leave it exactly at FinalPivot. No client-side copy is ever created.
export type ThrowFx = {
	Uid: string,
	JunkId: string,
	ThrowerUserId: number,
	Origin: Vector3,
	Velocity: Vector3,
	Gravity: number,
	FlightTime: number,
	FinalPivot: CFrame,
}

return {}
