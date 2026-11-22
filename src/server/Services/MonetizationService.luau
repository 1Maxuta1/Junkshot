--!strict
--[[
	MonetizationService: OPTIONAL Robux purchases for the machine (Config/MonetizationConfig).
	Every id there is 0 today, so nothing can be bought until real ids are configured.

	Developer Products (MarketplaceService.ProcessReceipt, the only receipt handler in the game)
	  - The receipt is matched to a configured product; unknown ids are left for a retry.
	  - Idempotent: processed PurchaseIds are stored in the buyer's profile (ProfileData.Purchases,
	    the last MaxStoredReceipts). A repeated receipt is acknowledged without granting again.
	  - Granting goes through MachineService (InstantFinish / AddBoost); the receipt is only
	    acknowledged (PurchaseGranted) after the grant succeeded and was recorded.
	Game Passes
	  - FastMachine ownership is checked when the player's data loads and when they buy it in
	    game; MachineService applies the multiplier to newly started jobs.

	The client only prompts purchases (MarketplaceService:PromptProductPurchase); it never
	decides what was bought.
]]

local MarketplaceService = game:GetService("MarketplaceService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local MonetizationConfig = require(ReplicatedStorage.Shared.Config.MonetizationConfig)
local DataService = require(script.Parent.DataService)
local MachineService = require(script.Parent.MachineService)

local MonetizationService = {}

local started = false

-- ProductId -> grant function. Only configured (non-zero) products are listed.
local handlers: { [number]: (player: Player) -> boolean } = {}

local function registerProducts()
	local products = MonetizationConfig.Products
	if products.InstantFinish.ProductId ~= 0 then
		handlers[products.InstantFinish.ProductId] = function(player: Player): boolean
			return MachineService.InstantFinish(player)
		end
	end
	if products.SpeedBoost.ProductId ~= 0 then
		handlers[products.SpeedBoost.ProductId] = function(player: Player): boolean
			return MachineService.AddBoost(player, products.SpeedBoost.Minutes * 60)
		end
	end
end

local function processReceipt(receipt: any): Enum.ProductPurchaseDecision
	local player = Players:GetPlayerByUserId(receipt.PlayerId)
	if player == nil then
		return Enum.ProductPurchaseDecision.NotProcessedYet -- Roblox retries when they rejoin
	end
	local data = DataService.GetData(player)
	if data == nil then
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end
	if type(data.Purchases) ~= "table" then
		(data :: any).Purchases = {}
	end
	local purchaseId = tostring(receipt.PurchaseId)
	if table.find(data.Purchases, purchaseId) ~= nil then
		return Enum.ProductPurchaseDecision.PurchaseGranted -- already granted earlier
	end
	local grant = handlers[receipt.ProductId]
	if grant == nil then
		warn(`[MonetizationService] receipt for unknown product {tostring(receipt.ProductId)}`)
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end
	local ok, granted = pcall(grant, player)
	if not ok or not granted then
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end
	table.insert(data.Purchases, purchaseId)
	while #data.Purchases > MonetizationConfig.MaxStoredReceipts do
		table.remove(data.Purchases, 1)
	end
	return Enum.ProductPurchaseDecision.PurchaseGranted
end

local function checkPass(player: Player)
	local passId = MonetizationConfig.GamePasses.FastMachine.GamePassId
	if passId == 0 then
		return
	end
	local ok, owns = pcall(function()
		return MarketplaceService:UserOwnsGamePassAsync(player.UserId, passId)
	end)
	if ok and owns then
		MachineService.SetPermanentSpeed(player, true)
	end
end

function MonetizationService.Start()
	assert(not started, "[MonetizationService] Start() called twice")
	started = true

	registerProducts()
	MarketplaceService.ProcessReceipt = processReceipt

	DataService.PlayerLoaded:Connect(checkPass)
	for _, player in Players:GetPlayers() do
		if DataService.IsLoaded(player) then
			task.spawn(checkPass, player)
		end
	end
	MarketplaceService.PromptGamePassPurchaseFinished:Connect(function(player: Player, passId: number, purchased: boolean)
		if purchased and passId == MonetizationConfig.GamePasses.FastMachine.GamePassId and passId ~= 0 then
			MachineService.SetPermanentSpeed(player, true)
		end
	end)
end

-- Exposed for DevTests: run the receipt logic with a fake receipt.
MonetizationService.ProcessReceiptForTest = processReceipt
MonetizationService.RegisterHandlerForTest = function(productId: number, grant: (player: Player) -> boolean)
	handlers[productId] = grant
end

return MonetizationService
