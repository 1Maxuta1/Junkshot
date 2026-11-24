--!strict
--[[
	WorldEventService: the Rare Creature event (Config/WorldEventConfig). Runs separately on
	every server; nothing is shared between servers.

	Flow
	  - Every Interval seconds (only while players are on the server and no creature is out):
	    pick a creature by Weight and a random VALID spawn point, build it, tell everyone.
	  - The creature has a "Catch" ProximityPrompt (Custom style, drawn by UI/PickupPrompt).
	    Triggered -> TryClaim.
	  - First accepted claim wins: one random item of the creature's RewardRarity from the
	    existing reward pool (ItemConfig.GetRewardPool) goes into the winner's hands
	    (CarryService), or onto the ground at their feet, reserved for them, when the hands are
	    full (JunkService). No other inventory is involved.
	  - Unclaimed after Duration seconds: the creature leaves.

	Safety
	  - TryClaim never yields between "is it still claimable?" and "it is claimed", so two
	    players in the same frame can never both win (the second sees Claimed = true).
	  - The server checks: data loaded, character alive, distance (ClaimDistance), a per-player
	    cooldown (ClaimCooldown). The client only presses the prompt; it sends no data.
	  - The prompt is destroyed the moment the creature is claimed or leaves, and the
	    creature is no longer the active one, so a late or repeated request finds nothing.

	Presentation (no remote needed)
	  - The model carries attributes for clients (client/CreatureController):
	      CreatureKey, DisplayName, Rarity, ExpiresAt (server time),
	      State = "Active" | "Claimed" | "Gone", ClaimedBy (UserId), RewardId, RewardWhere
	        ("Hands" | "Ground")
	    Clients play the appear / disappear animations and the winner's reward card.
	  - Announcements go to everybody through the existing Notify remote.
]]

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local GameConfig = require(ReplicatedStorage.Shared.Config.GameConfig)
local ItemConfig = require(ReplicatedStorage.Shared.Config.ItemConfig)
local Rarities = require(ReplicatedStorage.Shared.Config.Rarities)
local Remotes = require(ReplicatedStorage.Shared.Remotes)
local WorldEventConfig = require(ReplicatedStorage.Shared.Config.WorldEventConfig)

local CarryService = require(script.Parent.CarryService)
local DataService = require(script.Parent.DataService)
local JunkService = require(script.Parent.JunkService)
local CreatureModels = require(script.Parent.WorldEvents.CreatureModels)

local WorldEventService = {}

WorldEventService.Errors = table.freeze({
	Gone = "Gone", -- no such creature any more (claimed, left, or never existed)
	NotLoaded = "NotLoaded",
	Dead = "Dead",
	TooFar = "TooFar",
	TooFast = "TooFast",
	NoReward = "NoReward",
})

type Event = {
	Key: string,
	Config: any,
	Model: Model,
	Prompt: ProximityPrompt,
	ExpiresAt: number,
	Claimed: boolean,
}

local started = false
local active: Event? = nil
local lastAttempt: { [Player]: number } = {}

local function folder(): Folder
	local existing = Workspace:FindFirstChild(WorldEventConfig.FolderName)
	if existing ~= nil and existing:IsA("Folder") then
		return existing
	end
	local created = Instance.new("Folder")
	created.Name = WorldEventConfig.FolderName
	created.Parent = Workspace
	return created
end

local function announce(text: string, kind: string)
	Remotes.GetEvent("Notify"):FireAllClients(text, kind)
end

---------------------------------------------------------------------------------------------
-- Spawn points
---------------------------------------------------------------------------------------------

local function ignoredInstances(): { Instance }
	local list: { Instance } = { folder() }
	for _, name in { GameConfig.Junk.ContainerName, "Companions" } do
		local found = Workspace:FindFirstChild(name)
		if found ~= nil then
			table.insert(list, found)
		end
	end
	for _, player in Players:GetPlayers() do
		if player.Character ~= nil then
			table.insert(list, player.Character)
		end
	end
	return list
end

local function onBasePlot(position: Vector3): boolean
	for _, plot in CollectionService:GetTagged("BasePlot") do
		if plot:IsA("Model") then
			local cf, size = plot:GetBoundingBox()
			local localPos = cf:PointToObjectSpace(position)
			-- A few studs of margin so the creature never stands on a plot's edge.
			if math.abs(localPos.X) < size.X / 2 + 4 and math.abs(localPos.Z) < size.Z / 2 + 4 then
				return true
			end
		end
	end
	return false
end

-- Returns the ground position for a configured point, or nil if it is not usable right now:
-- no ground below, something solid in the way (a building, wall, prop, placed object), or on
-- a base plot.
function WorldEventService.CheckSpawnPoint(point: Vector3): Vector3?
	if onBasePlot(point) then
		return nil
	end
	local ignore = ignoredInstances()
	local rayParams = RaycastParams.new()
	rayParams.FilterType = Enum.RaycastFilterType.Exclude
	rayParams.FilterDescendantsInstances = ignore
	local hit = Workspace:Raycast(point + Vector3.new(0, 40, 0), Vector3.new(0, -80, 0), rayParams)
	if hit == nil or hit.Normal.Y < 0.8 then
		return nil
	end
	-- Something solid ABOVE the start of the ray means the point is under a roof.
	if hit.Position.Y > point.Y + 3 then
		return nil
	end
	local clearance = WorldEventConfig.SpawnClearance
	local overlap = OverlapParams.new()
	overlap.FilterType = Enum.RaycastFilterType.Exclude
	overlap.FilterDescendantsInstances = ignore
	local center = CFrame.new(hit.Position + Vector3.new(0, clearance.Y / 2 + 0.3, 0))
	for _, part in Workspace:GetPartBoundsInBox(center, clearance, overlap) do
		if part.CanCollide then
			return nil
		end
	end
	return hit.Position
end

local function pickSpawnPoint(): Vector3?
	local points = table.clone(WorldEventConfig.SpawnPoints)
	-- Shuffle, then take the first valid one.
	for i = #points, 2, -1 do
		local j = math.random(i)
		points[i], points[j] = points[j], points[i]
	end
	for _, point in points do
		local ground = WorldEventService.CheckSpawnPoint(point)
		if ground ~= nil then
			return ground
		end
	end
	return nil
end

local function pickCreature(): (string?, any)
	local total = 0
	for _, creature in WorldEventConfig.Creatures do
		if CreatureModels.Has(creature.Model) then
			total += creature.Weight
		end
	end
	if total <= 0 then
		return nil, nil
	end
	local roll = math.random() * total
	for key, creature in WorldEventConfig.Creatures do
		if CreatureModels.Has(creature.Model) then
			roll -= creature.Weight
			if roll <= 0 then
				return key, creature
			end
		end
	end
	return nil, nil
end

---------------------------------------------------------------------------------------------
-- Lifecycle
---------------------------------------------------------------------------------------------

-- Ends the event: the prompt goes at once, the model after the disappear animation.
local function finish(event: Event, state: string)
	if active == event then
		active = nil
	end
	if event.Prompt.Parent ~= nil then
		event.Prompt:Destroy()
	end
	event.Model:SetAttribute("State", state)
	local model = event.Model
	task.delay(WorldEventConfig.FadeTime, function()
		model:Destroy()
	end)
end

function WorldEventService.GetActive(): Model?
	return if active ~= nil then active.Model else nil
end

-- Removes the current creature without a winner (also used by DevTests).
function WorldEventService.Despawn(): boolean
	local event = active
	if event == nil then
		return false
	end
	finish(event, "Gone")
	return true
end

-- Spawns a creature now. `key` / `position` are optional (DevTests); otherwise random.
-- Returns the model, or nil when one is already out or nothing valid was found.
function WorldEventService.SpawnNow(key: string?, position: Vector3?): Model?
	if active ~= nil then
		return nil
	end
	local creatureKey, creature
	if key ~= nil then
		creatureKey, creature = key, (WorldEventConfig.Creatures :: any)[key]
	else
		creatureKey, creature = pickCreature()
	end
	if creatureKey == nil or creature == nil then
		return nil
	end
	local ground = if position ~= nil then position else pickSpawnPoint()
	if ground == nil then
		warn("[WorldEventService] no valid spawn point for a creature right now")
		return nil
	end
	local model = CreatureModels.Build(creature.Model, Rarities.GetColor(creature.RewardRarity))
	if model == nil then
		return nil
	end
	model:PivotTo(CFrame.new(ground) * CFrame.Angles(0, math.random() * math.pi * 2, 0))
	-- One small model: always streamed to everyone (label visible from afar, arrives whole).
	model.ModelStreamingMode = Enum.ModelStreamingMode.Persistent

	local expiresAt = Workspace:GetServerTimeNow() + creature.Duration
	model:SetAttribute("CreatureKey", creatureKey)
	model:SetAttribute("DisplayName", creature.DisplayName)
	model:SetAttribute("Rarity", creature.RewardRarity)
	model:SetAttribute("ExpiresAt", expiresAt)
	model:SetAttribute("State", "Active")

	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = "CatchPrompt"
	prompt.ActionText = "Catch"
	prompt.ObjectText = `{creature.DisplayName} - {creature.RewardRarity} item`
	prompt.KeyboardKeyCode = GameConfig.Input.PickupKey
	prompt.HoldDuration = 0
	prompt.RequiresLineOfSight = false
	prompt.MaxActivationDistance = WorldEventConfig.PromptDistance
	prompt.Style = Enum.ProximityPromptStyle.Custom
	prompt.Exclusivity = Enum.ProximityPromptExclusivity.OnePerButton
	prompt:SetAttribute("PromptKind", "Creature")
	prompt:SetAttribute("CardOffset", 4.5)
	prompt.Parent = model.PrimaryPart

	local event: Event = {
		Key = creatureKey,
		Config = creature,
		Model = model,
		Prompt = prompt,
		ExpiresAt = expiresAt,
		Claimed = false,
	}
	active = event
	prompt.Triggered:Connect(function(player: Player)
		WorldEventService.TryClaim(player, model)
	end)

	CollectionService:AddTag(model, WorldEventConfig.Tag)
	model.Parent = folder()
	announce(`🦊 A {creature.DisplayName} appeared! Catch it for a {creature.RewardRarity} item!`, "Info")

	task.delay(creature.Duration, function()
		if active == event and not event.Claimed then
			finish(event, "Gone")
			announce(`The {creature.DisplayName} ran away...`, "Info")
		end
	end)
	return model
end

-- The only way to win a creature. Returns (true, nil) or (false, errorCode).
function WorldEventService.TryClaim(player: Player, model: any): (boolean, string?)
	local Errors = WorldEventService.Errors
	local event = active
	if event == nil or event.Model ~= model or event.Claimed then
		return false, Errors.Gone
	end
	local now = os.clock()
	local last = lastAttempt[player]
	if last ~= nil and now - last < WorldEventConfig.ClaimCooldown then
		return false, Errors.TooFast
	end
	lastAttempt[player] = now
	if not DataService.IsLoaded(player) then
		return false, Errors.NotLoaded
	end
	local root = CarryService.GetLiveRoot(player)
	if root == nil then
		return false, Errors.Dead
	end
	if (root.Position - event.Model:GetPivot().Position).Magnitude > WorldEventConfig.ClaimDistance then
		return false, Errors.TooFar
	end
	local pool = ItemConfig.GetRewardPool(event.Config.RewardRarity)
	if #pool == 0 then
		return false, Errors.NoReward
	end

	-- From here to the end nothing yields: claiming is atomic.
	event.Claimed = true
	local itemId = pool[math.random(#pool)]
	local where = "Hands"
	if not CarryService.AddJunk(player, itemId) then
		where = "Ground"
		local dropped = JunkService.SpawnAt(itemId, root.Position, {
			ReservedFor = player.UserId,
			Lifetime = GameConfig.Junk.DroppedLifetime,
		} :: any)
		if dropped == nil then
			-- No ground under the player (should not happen): undo so someone can still win it.
			event.Claimed = false
			return false, Errors.NoReward
		end
	end

	event.Model:SetAttribute("ClaimedBy", player.UserId)
	event.Model:SetAttribute("RewardId", itemId)
	event.Model:SetAttribute("RewardWhere", where)
	finish(event, "Claimed")
	announce(`{player.DisplayName} caught the {event.Config.DisplayName} and got {ItemConfig.GetDisplayName(itemId)}!`, "Success")
	return true, nil
end

function WorldEventService.Start()
	assert(not started, "[WorldEventService] Start() called twice")
	started = true
	folder()
	Players.PlayerRemoving:Connect(function(player: Player)
		lastAttempt[player] = nil
	end)
	task.spawn(function()
		while true do
			task.wait(WorldEventConfig.Interval)
			if active == nil and #Players:GetPlayers() > 0 then
				local ok, err = pcall(WorldEventService.SpawnNow)
				if not ok then
					warn(`[WorldEventService] spawn failed: {tostring(err)}`)
				end
			end
		end
	end)
end

return WorldEventService
