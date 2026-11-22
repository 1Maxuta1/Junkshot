--!strict
--[[
	MachineConfig: Recycling Machine tunables, shared by server (authority) and client
	(presentation). Rarity chances live in Rarities, not here.

	Cycle (server-controlled; clients only animate what the machine model's attributes say):
	  Idle --insert--> AcceptingItem --InsertDuration--> Processing --ProcessDuration-->
	  RewardReady --RevealDuration (reward delivered) / claim (delivery failed)--> Idle
]]

local MachineConfig = {
	Tag = "RecyclingMachine", -- machine models carry this tag and a "MachineId" attribute

	InsertDuration = 1, -- seconds: input slot opens, junk goes in, slot closes
	ProcessDuration = 4.5, -- seconds of processing (the "4-5 s" from the design)
	RevealDuration = 4, -- seconds the reward is shown before the machine is free again

	PromptDistance = 14, -- studs: machine ProximityPrompt activation distance
	-- Extra studs the server accepts beyond PromptDistance (lag between client and server).
	DistanceTolerance = 8,
}

local function deepFreeze(value: any)
	if type(value) == "table" and not table.isfrozen(value) then
		for _, child in value do
			deepFreeze(child)
		end
		table.freeze(value)
	end
end

deepFreeze(MachineConfig)

return MachineConfig
