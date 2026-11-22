--!strict
--[[
	Types: shared Luau type definitions (types only, no runtime logic).
	Usage: local Types = require(ReplicatedStorage.Shared.Types)
]]

export type RarityId = string

export type ItemDefinition = {
	Id: string,
	DisplayName: string,
	Rarity: RarityId,
	IsDebug: boolean?,
	-- How the item looks (same format as junk, built by JunkFactory.BuildItem). Required for
	-- every non-debug item.
	Parts: { JunkPartSpec }?,
}

-- The machine's states, in cycle order. Published as the machine model's "State" attribute.
export type MachineState = "Idle" | "AcceptingItem" | "Processing" | "RewardReady"

-- One owned item. Stored in the profile under Items[uid].
export type ItemRecord = {
	id: string, -- key into ItemConfig
	acquiredAt: number, -- os.time()
}

export type ProfileStats = {
	TotalKlunksEarned: number,
}

-- The saved player profile (Profile.Data).
export type ProfileData = {
	Version: number,
	Klunks: number,
	Items: { [string]: ItemRecord },
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

-- One visual piece of a junk object (see JunkConfig / JunkFactory).
export type JunkPartSpec = {
	Shape: Enum.PartType,
	Size: Vector3,
	Color: Color3,
	Material: Enum.Material,
	Offset: Vector3, -- position relative to the junk's origin
	Rotation: Vector3, -- degrees (X, Y, Z) relative to the junk's origin
}

-- A type of junk lying in the yard. The first part is the "Root" part.
export type JunkDefinition = {
	Id: string,
	DisplayName: string,
	SpawnWeight: number, -- relative chance to be picked when spawning (0 = never)
	Parts: { JunkPartSpec },
}

-- One physical junk object. Uid is generated once when the object first spawns and stays the
-- same while it lies in the world, is carried, flies after a throw and lands again.
-- Runtime only (never saved). Future rarity/value data belongs on this record.
export type CarriedJunk = {
	Uid: string,
	Id: string, -- key into JunkConfig
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
