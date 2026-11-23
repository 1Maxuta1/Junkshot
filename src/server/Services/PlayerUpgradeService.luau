--!strict
--[[
	PlayerUpgradeService: permanent player upgrades (Config/PlayerUpgrades), bought with the
	currency at the Scrap Dealer.

	Buy(player, requestId, upgradeId) checks, in this order, without yielding in between:
	  data loaded, known upgrade, request not processed before, not at max level, player level
	  high enough, standing at the dealer, enough money. Then it charges exactly once
	  (EconomyService.Spend with the request id), raises the level, remembers the request id
	  and applies the effect at once.

	Effects
	  CarryCapacity    CarryService capacity bonus (hotbar grows)
	  WalkSpeed        Humanoid.WalkSpeed, re-applied on every spawn
	  PickupRange      CarryService pickup distance (the client also widens its prompts)
	  StorageCapacity  InventoryService capacity
	  Haggler          GetSellBonus(player) -> extra share for SellService
	Levels are saved in profile.Data.PlayerUpgrades and published as Player attributes
	"Upgrade_<Id>" (level) plus "PickupRange" and "StorageMax" for the client.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local GameConfig = require(ReplicatedStorage.Shared.Config.GameConfig)
local PlayerUpgrades = require(ReplicatedStorage.Shared.Config.PlayerUpgrades)
local Remotes = require(ReplicatedStorage.Shared.Remotes)
local Validate = require(ReplicatedStorage.Shared.Util.Validate)

local CarryService = require(script.Parent.CarryService)
local DataService = require(script.Parent.DataService)
local DealerService = require(script.Parent.DealerService)
local EconomyService = require(script.Parent.EconomyService)
local InventoryService = require(script.Parent.InventoryService)
local ProgressionService = require(script.Parent.ProgressionService)
local RemoteGuard = require(script.Parent.RemoteGuard)

local PlayerUpgradeService = {}

PlayerUpgradeService.Errors = table.freeze({
	NotLoaded = "NotLoaded",
	InvalidArguments = "InvalidArguments",
	UnknownUpgrade = "UnknownUpgrade",
	Duplicate = "Duplicate",
	MaxLevel = "MaxLevel",
	LevelTooLow = "LevelTooLow",
	NotAtDealer = "NotAtDealer",
	NotEnough = "NotEnough",
})

local MESSAGES: { [string]: string } = {
	MaxLevel = "Already at the highest level",
	LevelTooLow = "Reach a higher player level first",
	NotAtDealer = "Visit the Scrap Dealer to buy upgrades",
	NotEnough = "Not enough money",
}

local started = false

local function levels(player: Player): { [string]: number }?
	local data = DataService.GetData(player)
	if data == nil then
		return nil
	end
	if type(data.PlayerUpgrades) ~= "table" then
		data.PlayerUpgrades = {}
	end
	return data.PlayerUpgrades
end

function PlayerUpgradeService.GetLevel(player: Player, upgradeId: string): number
	local saved = levels(player)
	local upgrade = PlayerUpgrades.Get(upgradeId)
	if saved == nil or upgrade == nil then
		return 1
	end
	local level = saved[upgradeId]
	if not Validate.IsInteger(level, 1, #upgrade.Levels) then
		return 1
	end
	return level :: number
end

function PlayerUpgradeService.GetValue(player: Player, upgradeId: string): number
	return PlayerUpgrades.ValueAt(upgradeId, PlayerUpgradeService.GetLevel(player, upgradeId))
end

function PlayerUpgradeService.GetSellBonus(player: Player): number
	return PlayerUpgradeService.GetValue(player, "Haggler")
end

local function applyWalkSpeed(player: Player)
	local character = player.Character
	local humanoid = if character ~= nil then character:FindFirstChildOfClass("Humanoid") else nil
	if humanoid ~= nil then
		humanoid.WalkSpeed = PlayerUpgradeService.GetValue(player, "WalkSpeed")
	end
end

local function publish(player: Player)
	if DataService.GetData(player) == nil then
		return
	end
	for _, upgrade in PlayerUpgrades.List do
		player:SetAttribute(`Upgrade_{upgrade.Id}`, PlayerUpgradeService.GetLevel(player, upgrade.Id))
	end
	player:SetAttribute("PickupRange", PlayerUpgradeService.GetValue(player, "PickupRange"))
	player:SetAttribute("StorageMax", InventoryService.GetCapacity(player))
	applyWalkSpeed(player)
	CarryService.Refresh(player) -- republishes CarryMax
end

-- Re-applies and re-publishes every upgrade effect (after data was changed directly).
function PlayerUpgradeService.Refresh(player: Player)
	publish(player)
end

function PlayerUpgradeService.Buy(player: Player, requestId: any, upgradeId: any): (boolean, string?)
	local saved = levels(player)
	if saved == nil then
		return false, PlayerUpgradeService.Errors.NotLoaded
	end
	if not Validate.IsUid(requestId) or type(upgradeId) ~= "string" then
		return false, PlayerUpgradeService.Errors.InvalidArguments
	end
	local upgrade = PlayerUpgrades.Get(upgradeId)
	if upgrade == nil then
		return false, PlayerUpgradeService.Errors.UnknownUpgrade
	end
	if EconomyService.IsProcessed(player, requestId) then
		return false, PlayerUpgradeService.Errors.Duplicate
	end
	local current = PlayerUpgradeService.GetLevel(player, upgradeId)
	local nextLevel = upgrade.Levels[current + 1]
	if nextLevel == nil then
		return false, PlayerUpgradeService.Errors.MaxLevel
	end
	if ProgressionService.GetLevel(player) < (nextLevel.RequiredLevel or 1) then
		return false, PlayerUpgradeService.Errors.LevelTooLow
	end
	if not DealerService.IsNear(player) then
		return false, PlayerUpgradeService.Errors.NotAtDealer
	end
	if nextLevel.Price > 0 then
		local paid = EconomyService.Spend(player, nextLevel.Price, `PlayerUpgrade:{upgradeId}`, requestId)
		if not paid then
			return false, PlayerUpgradeService.Errors.NotEnough
		end
	end
	saved[upgradeId] = current + 1
	EconomyService.MarkProcessed(player, requestId)
	publish(player)
	EconomyService.Message(player, `{upgrade.DisplayName} upgraded to level {current + 1}!`, "Success")
	return true, nil
end

function PlayerUpgradeService.Start()
	assert(not started, "[PlayerUpgradeService] Start() called twice")
	started = true

	CarryService.SetCapacityBonusProvider(function(player: Player): number
		return PlayerUpgradeService.GetValue(player, "CarryCapacity")
	end)
	CarryService.SetPickupRangeProvider(function(player: Player): number
		return PlayerUpgradeService.GetValue(player, "PickupRange")
	end)
	InventoryService.SetCapacityProvider(function(player: Player): number
		return PlayerUpgradeService.GetValue(player, "StorageCapacity")
	end)

	local function hook(player: Player)
		player.CharacterAdded:Connect(function(character: Model)
			local humanoid = character:WaitForChild("Humanoid", 10)
			if humanoid ~= nil and DataService.GetData(player) ~= nil then
				applyWalkSpeed(player)
			end
		end)
	end
	Players.PlayerAdded:Connect(hook)
	for _, player in Players:GetPlayers() do
		hook(player)
	end
	DataService.PlayerLoaded:Connect(publish)
	for _, player in Players:GetPlayers() do
		if DataService.IsLoaded(player) then
			publish(player)
		end
	end

	RemoteGuard.ConnectEvent(Remotes.GetEvent("PlayerUpgradeBuy"), {
		Name = "PlayerUpgradeBuy",
		MaxArgs = 2,
		RateLimit = GameConfig.RateLimits.PlayerUpgradeBuy,
		Validate = function(requestId: any, upgradeId: any): boolean
			return Validate.IsUid(requestId) and Validate.IsString(upgradeId, 1, 40)
		end,
	}, function(player: Player, requestId: string, upgradeId: string)
		local ok, code = PlayerUpgradeService.Buy(player, requestId, upgradeId)
		if not ok and code ~= nil and MESSAGES[code] ~= nil then
			EconomyService.Message(player, MESSAGES[code], "Warning")
		end
	end)
end

return PlayerUpgradeService
