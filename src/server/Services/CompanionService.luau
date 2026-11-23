--!strict
--[[
	CompanionService: spawns the equipped companion (CosmeticsConfig category "Companion") for
	each player and removes it when it is unequipped or the player leaves.

	Performance: the companion is an anchored, non-colliding, non-queryable model in
	Workspace.Companions. The server places it once; every CLIENT animates all companions locally
	(client CompanionController: follow + bob), so nothing is replicated per frame and there is
	no physics. It never touches items, prompts or vehicles: purely visual.
	Ownership is CosmeticsService's job (only owned companions can be equipped).
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local CosmeticsConfig = require(ReplicatedStorage.Shared.Config.CosmeticsConfig)

local CosmeticsService = require(script.Parent.CosmeticsService)
local DataService = require(script.Parent.DataService)
local CosmeticModels = require(script.Parent.Cosmetics.CosmeticModels)

local CompanionService = {}

local FOLDER_NAME = "Companions"
local started = false
local companions: { [Player]: Model } = {}

local function folder(): Folder
	local existing = Workspace:FindFirstChild(FOLDER_NAME)
	if existing ~= nil and existing:IsA("Folder") then
		return existing
	end
	local created = Instance.new("Folder")
	created.Name = FOLDER_NAME
	created.Parent = Workspace
	return created
end

function CompanionService.Despawn(player: Player)
	local model = companions[player]
	companions[player] = nil
	if model ~= nil then
		model:Destroy()
	end
end

function CompanionService.Get(player: Player): Model?
	return companions[player]
end

function CompanionService.Refresh(player: Player)
	CompanionService.Despawn(player)
	local id = CosmeticsService.GetEquipped(player, "Companion")
	local cosmetic = if id ~= nil then CosmeticsConfig.Get(id) else nil
	if cosmetic == nil or cosmetic.Model == nil or player.Parent ~= Players then
		return
	end
	local model = CosmeticModels.Build(cosmetic.Model, true)
	if model == nil then
		return
	end
	model.Name = `{player.Name}_{cosmetic.Id}`
	model:SetAttribute("OwnerUserId", player.UserId)
	model:SetAttribute("CosmeticId", cosmetic.Id)
	local character = player.Character
	local root = if character ~= nil then character:FindFirstChild("HumanoidRootPart") else nil
	if root ~= nil and root:IsA("BasePart") then
		model:PivotTo(root.CFrame * CFrame.new(2.5, -3, 3))
	end
	model.Parent = folder()
	companions[player] = model
end

function CompanionService.Start()
	assert(not started, "[CompanionService] Start() called twice")
	started = true
	folder()
	CosmeticsService.EquippedChanged:Connect(function(player: Player, category: string)
		if category == "Companion" then
			CompanionService.Refresh(player)
		end
	end)
	DataService.PlayerLoaded:Connect(function(player: Player)
		CompanionService.Refresh(player)
	end)
	for _, player in Players:GetPlayers() do
		if DataService.IsLoaded(player) then
			CompanionService.Refresh(player)
		end
	end
	Players.PlayerRemoving:Connect(CompanionService.Despawn)
end

return CompanionService
