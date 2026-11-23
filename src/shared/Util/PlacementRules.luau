--!strict
--[[
	PlacementRules: where a placeable item may stand. Shared on purpose: the server uses it to
	decide (PlacementService), the client uses the SAME function to colour the preview, so the
	preview never promises a spot the server refuses.

	Check(request) -> (CFrame?, errorCode?)
	  request = {
	    UserId        who places (their own plot is allowed, other owned plots are not)
	    ModelName     Util/DeployModels name (gives the footprint)
	    Position      requested point (the ground is searched below / above it)
	    Yaw           radians
	    RootPosition  character position; nil skips the distance rule (server-side respawns)
	    Ignore        extra instances to ignore (the client's own preview model)
	  }
	The returned CFrame is the object's pivot: on the ground, rotated by Yaw.

	Rules (numbers in GameConfig.Placement)
	  TooFar       further than MaxDistance (+ DistanceTolerance on the server) from the character
	  NoGround     no map ground below the point (only the map and terrain count as ground)
	  Steep        ground normal below MinGroundNormalY
	  ForeignPlot  inside another player's base plot
	  NearMachine  closer than MachineClearance to any machine
	  Blocked      the footprint overlaps something solid (map props, other placed objects)
]]

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")

local GameConfig = require(script.Parent.Parent.Config.GameConfig)
local MachineConfig = require(script.Parent.Parent.Config.MachineConfig)
local DeployModels = require(script.Parent.DeployModels)

export type Request = {
	UserId: number,
	ModelName: string,
	Position: Vector3,
	Yaw: number,
	RootPosition: Vector3?,
	Tolerance: number?, -- extra studs added to MaxDistance (server lag allowance)
	Ignore: { Instance }?,
}

local PlacementRules = {}

PlacementRules.DEPLOYED_FOLDER = "Deployed"
PlacementRules.PLOT_TAG = "BasePlot"

local CLEARANCE = 0.35 -- the overlap box starts this far above the ground
local SHRINK = 0.9 -- footprint fraction tested for overlap (forgives touching edges)

local function baseExclusions(extra: { Instance }?): { Instance }
	local list: { Instance } = {}
	for _, player in Players:GetPlayers() do
		if player.Character ~= nil then
			table.insert(list, player.Character)
		end
	end
	local junk = Workspace:FindFirstChild(GameConfig.Junk.ContainerName)
	if junk ~= nil then
		table.insert(list, junk)
	end
	if extra ~= nil then
		for _, instance in extra do
			table.insert(list, instance)
		end
	end
	return list
end

local function isGround(instance: Instance): boolean
	if instance:IsA("Terrain") then
		return true
	end
	local map = Workspace:FindFirstChild("Map")
	return map ~= nil and instance:IsDescendantOf(map)
end

local function onForeignPlot(userId: number, point: Vector3): boolean
	for _, plot in CollectionService:GetTagged(PlacementRules.PLOT_TAG) do
		local owner = plot:GetAttribute("Owner")
		if type(owner) == "number" and owner ~= 0 and owner ~= userId then
			local pad = plot:FindFirstChild("Pad")
			if pad ~= nil and pad:IsA("BasePart") then
				local localPoint = pad.CFrame:PointToObjectSpace(point)
				if math.abs(localPoint.X) <= pad.Size.X / 2 and math.abs(localPoint.Z) <= pad.Size.Z / 2 then
					return true
				end
			end
		end
	end
	return false
end

local function nearMachine(point: Vector3): boolean
	local clearance = GameConfig.Placement.MachineClearance
	for _, machine in CollectionService:GetTagged(MachineConfig.Tag) do
		if machine:IsA("Model") and machine:IsDescendantOf(Workspace) then
			local offset = machine:GetPivot().Position - point
			if Vector3.new(offset.X, 0, offset.Z).Magnitude < clearance then
				return true
			end
		end
	end
	return false
end

function PlacementRules.Check(request: Request): (CFrame?, string?)
	local config = GameConfig.Placement
	local position, yaw = request.Position, request.Yaw

	if request.RootPosition ~= nil then
		local offset = position - request.RootPosition
		local flat = Vector3.new(offset.X, 0, offset.Z).Magnitude
		if flat > config.MaxDistance + (request.Tolerance or 0) or math.abs(offset.Y) > config.RayLength then
			return nil, "TooFar"
		end
	end

	-- Ground below the point. Placed objects are ignored here so nothing stands on a car roof.
	local exclusions = baseExclusions(request.Ignore)
	local deployed = Workspace:FindFirstChild(PlacementRules.DEPLOYED_FOLDER)
	local rayExclusions = table.clone(exclusions)
	if deployed ~= nil then
		table.insert(rayExclusions, deployed)
	end
	local rayParams = RaycastParams.new()
	rayParams.FilterType = Enum.RaycastFilterType.Exclude
	rayParams.FilterDescendantsInstances = rayExclusions
	rayParams.IgnoreWater = true
	local origin = position + Vector3.new(0, config.RayHeight, 0)
	local hit = Workspace:Raycast(origin, Vector3.new(0, -config.RayLength, 0), rayParams)
	if hit == nil or not isGround(hit.Instance) then
		return nil, "NoGround"
	end
	if hit.Normal.Y < config.MinGroundNormalY then
		return nil, "Steep"
	end
	local ground = hit.Position

	if onForeignPlot(request.UserId, ground) then
		return nil, "ForeignPlot"
	end
	if nearMachine(ground) then
		return nil, "NearMachine"
	end

	local pivot = CFrame.new(ground) * CFrame.Angles(0, yaw, 0)
	local size = DeployModels.GetSize(request.ModelName)
	local boxHeight = math.max(size.Y - CLEARANCE, 0.5)
	local boxCFrame = pivot * CFrame.new(0, CLEARANCE + boxHeight / 2, 0)
	local overlapParams = OverlapParams.new()
	overlapParams.FilterType = Enum.RaycastFilterType.Exclude
	overlapParams.FilterDescendantsInstances = exclusions
	local parts = Workspace:GetPartBoundsInBox(boxCFrame, Vector3.new(size.X * SHRINK, boxHeight, size.Z * SHRINK), overlapParams)
	for _, part in parts do
		if part.CanCollide then
			return nil, "Blocked"
		end
	end

	return pivot, nil
end

-- Short player-facing text for an error code (shared by preview and server messages).
local MESSAGES: { [string]: string } = {
	TooFar = "Too far away",
	NoGround = "Needs solid ground",
	Steep = "Too steep here",
	ForeignPlot = "That is someone else's base",
	NearMachine = "Too close to a machine",
	Blocked = "Something is in the way",
}

function PlacementRules.Describe(code: string?): string
	return if code ~= nil then MESSAGES[code] or code else ""
end

return PlacementRules
