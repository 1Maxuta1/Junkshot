--!strict
--[[
	Ability behavior: Mythic items with a show-off ability (Config/Behaviors "Ability.*").
	  Comet Shard       a comet falls from the sky in front of its owner (Effect "Comet")
	  Starforged Core   a starfall streaks high across the sky above its owner ("Starfall")

	Use(player, carried, behavior) (through PlacementService.Use / the ItemUse remote):
	  - the player must carry the item (checked by PlacementService) and be alive
	  - per-player cooldown per effect, saved in profile.Data.Cooldowns[effect] (Unix time it is
	    ready again), so leaving and rejoining does not reset it; published as the Player
	    attribute "Cooldown_<Effect>" for the client's countdown
	  - the effect is broadcast to every client (AbilityFx) with the server-chosen position;
	    clients draw it (ItemController/Abilities). Nothing is spawned on the server and nothing
	    is granted: purely visual.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Remotes = require(ReplicatedStorage.Shared.Remotes)

local CarryService = require(script.Parent.Parent.CarryService)
local DataService = require(script.Parent.Parent.DataService)

local Ability = {}

local api: any = nil

local function cooldowns(player: Player): { [string]: number }?
	local data = DataService.GetData(player)
	if data == nil then
		return nil
	end
	if type(data.Cooldowns) ~= "table" then
		data.Cooldowns = {}
	end
	return data.Cooldowns
end

local function publish(player: Player)
	local list = cooldowns(player)
	if list == nil then
		return
	end
	for effect, readyAt in list do
		if type(readyAt) == "number" then
			player:SetAttribute(`Cooldown_{effect}`, readyAt)
		end
	end
end

local function groundBelow(position: Vector3, exclude: { Instance }): Vector3
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = exclude
	params.RespectCanCollide = true
	local hit = Workspace:Raycast(position + Vector3.new(0, 20, 0), Vector3.new(0, -80, 0), params)
	return if hit ~= nil then hit.Position else position
end

-- Seconds until the effect is ready for this player (0 = ready).
function Ability.TimeLeft(player: Player, effect: string): number
	local list = cooldowns(player)
	local readyAt = if list ~= nil then list[effect] else nil
	return if type(readyAt) == "number" then math.max(0, readyAt - os.time()) else 0
end

function Ability.Use(player: Player, _carried: any, behavior: any): (boolean, string?)
	local config = behavior.Ability
	local list = cooldowns(player)
	local root = CarryService.GetLiveRoot(player)
	if list == nil or root == nil then
		return false, nil -- dead / loading: nothing to say
	end
	local left = Ability.TimeLeft(player, config.Effect)
	if left > 0 then
		api.Notify(player, string.format("%s is recharging: %d:%02d", config.Name, left // 60, left % 60))
		return false, nil
	end
	local look = root.CFrame.LookVector
	local flat = Vector3.new(look.X, 0, look.Z)
	flat = if flat.Magnitude > 0.01 then flat.Unit else Vector3.new(0, 0, -1)
	local exclude: { Instance } = {}
	for _, other in Players:GetPlayers() do
		if other.Character ~= nil then
			table.insert(exclude, other.Character)
		end
	end
	local target = groundBelow(root.Position + flat * config.Distance, exclude)

	list[config.Effect] = os.time() + config.Cooldown
	publish(player)
	Remotes.GetEvent("AbilityFx"):FireAllClients({
		Effect = config.Effect,
		UserId = player.UserId,
		Position = target,
		Direction = flat,
	})
	return true, nil
end

function Ability.Init(placement: any)
	api = placement
end

function Ability.Start()
	DataService.PlayerLoaded:Connect(publish)
	for _, player in Players:GetPlayers() do
		if DataService.IsLoaded(player) then
			publish(player)
		end
	end
end

-- Not placeable: the placement contract hooks are no-ops.
function Ability.Attach(_entry: any) end
function Ability.Detach(_entry: any) end

return Ability
