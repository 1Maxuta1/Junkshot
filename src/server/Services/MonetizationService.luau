--!strict
--[[
	MonetizationService: every Robux purchase (Config/MonetizationConfig). With all ids at 0
	(today) nothing can be bought or granted; the code paths are ready for real ids.

	GAME PASSES (permanent, e.g. the Starter Pack)
	  - Ownership comes ONLY from MarketplaceService:UserOwnsGamePassAsync, checked when the
	    player's data loads (covers passes bought outside the game) and after an in-game purchase
	    (PromptGamePassPurchaseFinished is only a hint to re-check, never proof).
	  - API errors are retried (OwnershipRetries), then re-checked in the background every
	    OwnershipRecheck seconds while the player stays; nothing is granted unverified.
	  - Granting is idempotent (ApplyPass): it raises the chest to at least the pass level (never
	    lowers it), unlocks cosmetics that are not owned yet and turns on pass effects; running
	    it again produces the same state. The first grant is recorded in
	    profile.Data.Entitlements[passKey] = { GrantedAt } for support. Session ownership is
	    published as the Player attribute "Pass_<Key>" (true) for the shop's OWNED state.
	  - Granted unlocks are permanent unlocks (the pass is a one-time permanent purchase). If a
	    later check says the pass is no longer owned (refund), nothing is granted again.

	DEVELOPER PRODUCTS (repeatable)
	  - The game's ONLY MarketplaceService.ProcessReceipt. The receipt is validated (PlayerId,
	    ProductId, PurchaseId), routed to the product's Handler, and acknowledged
	    (PurchaseGranted) only after the grant succeeded AND a finished profile save contains the
	    PurchaseId (last MaxStoredReceipts), so a server crash can never lose a paid item: the
	    grant and the id are in the same save, or neither is. A repeated PurchaseId is acknowledged without
	    granting again. Anything uncertain returns NotProcessedYet so Roblox retries.

	No remote can grant anything. Clients only open Roblox's own purchase prompts.
]]

local MarketplaceService = game:GetService("MarketplaceService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local MonetizationConfig = require(ReplicatedStorage.Shared.Config.MonetizationConfig)

local BaseService = require(script.Parent.BaseService)
local CosmeticsService = require(script.Parent.CosmeticsService)
local DataService = require(script.Parent.DataService)
local EconomyService = require(script.Parent.EconomyService)
local MachineService = require(script.Parent.MachineService)

local MonetizationService = {}

local started = false

-- ProductId -> grant function. Only configured (non-zero id + implemented handler) products.
local handlers: { [number]: (player: Player) -> boolean } = {}
local PRODUCT_HANDLERS: { [string]: (player: Player, product: any) -> boolean } = {
	SkipTime = function(player: Player, product: any): boolean
		return MachineService.SkipTime(player, product.Hours * 3600)
	end,
	Klunks = function(player: Player, product: any): boolean
		return (EconomyService.Earn(player, product.Amount, `Robux:{product.Key}`))
	end,
	SpeedBoost = function(player: Player, product: any): boolean
		return MachineService.AddBoost(player, product.Minutes * 60)
	end,
}

-- Ownership source; replaced only by DevTests in Studio.
local ownsPass: (userId: number, passId: number) -> boolean = function(userId: number, passId: number): boolean
	return MarketplaceService:UserOwnsGamePassAsync(userId, passId)
end

local function registerProducts()
	for _, product in MonetizationConfig.Products do
		local handler = if product.Handler ~= nil then PRODUCT_HANDLERS[product.Handler] else nil
		if product.ProductId ~= 0 and handler ~= nil then
			handlers[product.ProductId] = function(player: Player): boolean
				return handler(player, product)
			end
		end
	end
end

local SAVE_TIMEOUT = 25
local confirmSave: (player: Player, isSaved: (saved: any) -> boolean, timeout: number) -> boolean = DataService.SaveAndConfirm

local function processReceipt(receipt: any): Enum.ProductPurchaseDecision
	if type(receipt) ~= "table" or type(receipt.PlayerId) ~= "number" or type(receipt.ProductId) ~= "number"
		or receipt.PurchaseId == nil
	then
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end
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
	local function confirm(): Enum.ProductPurchaseDecision
		local onDisk = confirmSave(player, function(saved: any): boolean
			return type(saved.Purchases) == "table" and table.find(saved.Purchases, purchaseId) ~= nil
		end, SAVE_TIMEOUT)
		return if onDisk then Enum.ProductPurchaseDecision.PurchaseGranted else Enum.ProductPurchaseDecision.NotProcessedYet
	end
	if table.find(data.Purchases, purchaseId) ~= nil then
		return confirm() -- granted earlier (never twice); acknowledged once it is on disk
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
	return confirm()
end

---------------------------------------------------------------------------------------------
-- Game passes
---------------------------------------------------------------------------------------------

-- Applies everything a pass gives. Idempotent: safe to run on every confirmed ownership.
function MonetizationService.ApplyPass(player: Player, key: string): boolean
	local pass = (MonetizationConfig.GamePasses :: any)[key]
	local data = DataService.GetData(player)
	if pass == nil or data == nil then
		return false
	end
	local grant = pass.Grant or {}
	local ok = true
	if grant.ChestLevel ~= nil then
		ok = BaseService.EnsureChestLevel(player, grant.ChestLevel) and ok
	end
	if grant.Cosmetics ~= nil then
		for _, cosmeticId in grant.Cosmetics do
			ok = CosmeticsService.Unlock(player, cosmeticId, key) and ok
		end
	end
	if grant.MachineSpeed then
		MachineService.SetPermanentSpeed(player, true)
	end
	if type(data.Entitlements) ~= "table" then
		data.Entitlements = {}
	end
	if data.Entitlements[key] == nil then
		data.Entitlements[key] = { GrantedAt = os.time() }
	end
	player:SetAttribute(`Pass_{key}`, true)
	return ok
end

-- Asks Roblox whether the player owns the pass. nil = the API failed (unknown).
local function checkOwnership(player: Player, passId: number): boolean?
	local ok, owns = pcall(ownsPass, player.UserId, passId)
	if not ok then
		warn(`[MonetizationService] ownership check failed for {player.Name}: {tostring(owns)}`)
		return nil
	end
	return owns == true
end

-- Verifies one pass with retries; grants only when Roblox confirms ownership.
local function verifyPass(player: Player, key: string)
	local pass = (MonetizationConfig.GamePasses :: any)[key]
	if pass == nil or pass.GamePassId == 0 then
		return
	end
	local delays = MonetizationConfig.OwnershipRetries
	for attempt = 0, #delays do
		if player.Parent ~= Players then
			return
		end
		local owns = checkOwnership(player, pass.GamePassId)
		if owns == true then
			MonetizationService.ApplyPass(player, key)
			return
		elseif owns == false then
			return
		end
		if attempt < #delays then
			task.wait(delays[attempt + 1])
		end
	end
	-- Still unknown: keep checking in the background while the player is here.
	task.delay(MonetizationConfig.OwnershipRecheck, function()
		if player.Parent == Players and player:GetAttribute(`Pass_{key}`) ~= true then
			verifyPass(player, key)
		end
	end)
end

local function verifyAllPasses(player: Player)
	for key in MonetizationConfig.GamePasses do
		task.spawn(verifyPass, player, key)
	end
end

function MonetizationService.Start()
	assert(not started, "[MonetizationService] Start() called twice")
	started = true

	registerProducts()
	MarketplaceService.ProcessReceipt = processReceipt -- the only assignment in the experience

	DataService.PlayerLoaded:Connect(verifyAllPasses)
	for _, player in Players:GetPlayers() do
		if DataService.IsLoaded(player) then
			verifyAllPasses(player)
		end
	end
	MarketplaceService.PromptGamePassPurchaseFinished:Connect(function(player: Player, passId: number, purchased: boolean)
		if not purchased or passId == 0 then
			return
		end
		for key, pass in MonetizationConfig.GamePasses do
			if pass.GamePassId == passId then
				task.spawn(verifyPass, player, key) -- the event is a hint; Roblox's answer decides
			end
		end
	end)
end

MonetizationService.ProductHandlers = PRODUCT_HANDLERS
-- DevTests (Studio only): run the receipt logic with a fake receipt, register a test product,
-- replace the ownership source to simulate owning / API failures. Never used in a live game.
MonetizationService.ProcessReceiptForTest = processReceipt
MonetizationService.SetConfirmForTest = function(confirm: ((Player, (any) -> boolean, number) -> boolean)?)
	assert(RunService:IsStudio(), "test hook")
	confirmSave = confirm or DataService.SaveAndConfirm
end
MonetizationService.RegisterHandlerForTest = function(productId: number, grant: (player: Player) -> boolean)
	assert(RunService:IsStudio(), "test hook")
	handlers[productId] = grant
end
MonetizationService.VerifyPassForTest = function(player: Player, key: string, passId: number, source: (number, number) -> boolean)
	assert(RunService:IsStudio(), "test hook")
	local previous = ownsPass
	ownsPass = source
	local pass = (MonetizationConfig.GamePasses :: any)[key]
	local owns = checkOwnership(player, passId)
	if owns == true and pass ~= nil then
		MonetizationService.ApplyPass(player, key)
	end
	ownsPass = previous
	return owns
end

return MonetizationService
