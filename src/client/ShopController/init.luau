--!strict
--[[
	ShopController: the Robux shop and the cosmetics locker (one window, "R$ SHOP" button).

	  FEATURED / PACKS   the Starter Pack card: price, every reward marked PERMANENT or COSMETIC,
	                     BUY -> Roblox's own purchase prompt, OWNED once the SERVER confirmed
	                     ownership (Player attribute "Pass_StarterPack"); never before.
	  PASSES             other Game Passes.
	  COSMETICS          every cosmetic: EQUIP / TAKE OFF for owned ones (CosmeticEquip remote; the
	                     server refuses unowned ones), where locked ones come from.
	  BOOSTS             Developer Products (future-ready).
	Products with id 0 show "COMING SOON" and cannot be prompted. Prices come from Roblox
	(GetProductInfo) when an id is set; the config price is only a fallback. Only one purchase
	prompt at a time (the button is locked until Roblox reports the prompt closed).
]]

local MarketplaceService = game:GetService("MarketplaceService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local CosmeticsConfig = require(ReplicatedStorage.Shared.Config.CosmeticsConfig)
local MonetizationConfig = require(ReplicatedStorage.Shared.Config.MonetizationConfig)
local Remotes = require(ReplicatedStorage.Shared.Remotes)

local InputController = require(script.Parent.InputController)
local NotifyController = require(script.Parent.NotifyController)
local Theme = require(script.Parent.UI.Theme)
local Window = require(script.Parent.EconomyController.Window)

local ShopController = {}

local localPlayer = Players.LocalPlayer
local TABS = { "FEATURED", "PACKS", "PASSES", "COSMETICS", "KLUNKS", "BOOSTS" }
local PROMPT_TIMEOUT = 60

local promptOpenUntil = 0
local prices: { [string]: number } = {} -- "pass:<id>" / "product:<id>" -> Robux

local function priceText(kind: string, id: number, fallback: number?): string
	if id == 0 then
		return if fallback ~= nil and fallback > 0 then `R$ {fallback}` else ""
	end
	local key = `{kind}:{id}`
	local known = prices[key]
	if known ~= nil then
		return `R$ {known}`
	end
	task.spawn(function()
		local ok, info = pcall(MarketplaceService.GetProductInfo, MarketplaceService, id,
			if kind == "pass" then Enum.InfoType.GamePass else Enum.InfoType.Product)
		if ok and type(info) == "table" and type(info.PriceInRobux) == "number" then
			prices[key] = info.PriceInRobux
		end
	end)
	return if fallback ~= nil and fallback > 0 then `R$ {fallback}` else "R$ ..."
end

local function promptPass(pass: any)
	if pass.GamePassId == 0 then
		NotifyController.Show("Coming soon!", "Info")
		return
	end
	if os.clock() < promptOpenUntil then
		return -- a prompt is already open
	end
	promptOpenUntil = os.clock() + PROMPT_TIMEOUT
	MarketplaceService:PromptGamePassPurchase(localPlayer, pass.GamePassId)
end

local function promptProduct(product: any)
	if product.ProductId == 0 or product.Handler == nil then
		NotifyController.Show("Coming soon!", "Info")
		return
	end
	if os.clock() < promptOpenUntil then
		return
	end
	promptOpenUntil = os.clock() + PROMPT_TIMEOUT
	MarketplaceService:PromptProductPurchase(localPlayer, product.ProductId)
end

local function mount()
	local screenGui = Instance.new("ScreenGui")
	screenGui.Name = "JunkshotShop"
	screenGui.ResetOnSpawn = false
	screenGui.ScreenInsets = Enum.ScreenInsets.CoreUISafeInsets
	screenGui.DisplayOrder = 8

	local open = Window.HudButton("JunkshotShopButton", "R$ SHOP", Theme.Colors.Success, UDim2.new(0, 66, 0, 38),
		UDim2.new(1, -154, 0, 46))
	local window = Window.Mount(screenGui, "ShopWindow", "SHOP", TABS)

	local function passCard(list: Instance, order: number, key: string): number
		local pass = (MonetizationConfig.GamePasses :: any)[key]
		local owned = localPlayer:GetAttribute(`Pass_{key}`) == true
		local available = pass.GamePassId ~= 0
		local head = Window.Row(list, order, pass.DisplayName, pass.Description, nil)
		head.Frame.BackgroundColor3 = Color3.fromRGB(255, 240, 210)
		local text = if owned then "OWNED" elseif available then `BUY  {priceText("pass", pass.GamePassId, pass.PriceRobux)}` else `SOON  {priceText("pass", 0, pass.PriceRobux)}`
		local buy = Window.SmallButton(head.Right, text, if owned then Theme.Colors.InkSoft elseif available then Theme.Colors.Success else Theme.Colors.InkSoft,
			UDim2.new(0, 170, 0, 42))
		if not owned then
			buy.Activated:Connect(function()
				promptPass(pass)
			end)
		end
		order += 1
		for _, reward in pass.Rewards or {} do
			local row = Window.Row(list, order, `   {reward.Text}`, if reward.Kind == "Permanent" then "Permanent - stays forever" else "Cosmetic - looks only, no advantage", nil)
			row.Frame.Size = UDim2.new(1, -8, 0, 40)
			local tag = Window.SmallButton(row.Right, string.upper(reward.Kind), if reward.Kind == "Permanent" then Theme.Colors.Accent else Theme.Colors.Ice,
				UDim2.new(0, 120, 0, 30))
			tag.AutoButtonColor = false
			order += 1
		end
		return order
	end

	local function render()
		if not window.IsOpen() then
			return
		end
		local tab = window.CurrentTab()
		local list = window.Content(tab)
		Window.Clear(list)
		local order = 1
		if tab == "FEATURED" then
			for key, pass in MonetizationConfig.GamePasses do
				if pass.Featured then
					order = passCard(list, order, key)
				end
			end
		elseif tab == "PACKS" or tab == "PASSES" then
			local category = if tab == "PACKS" then "StarterPacks" else "GamePasses"
			for key, pass in MonetizationConfig.GamePasses do
				if pass.Category == category then
					order = passCard(list, order, key)
				end
			end
		elseif tab == "COSMETICS" then
			local ownedText = localPlayer:GetAttribute("CosmeticsOwned")
			local owned: { [string]: boolean } = {}
			if type(ownedText) == "string" then
				for _, id in string.split(ownedText, ",") do
					owned[id] = true
				end
			end
			for _, category in CosmeticsConfig.Categories do
				Window.Header(list, order, string.upper(category))
				order += 1
				local equipped = localPlayer:GetAttribute(`Equipped_{category}`)
				for _, cosmetic in CosmeticsConfig.List do
					if cosmetic.Category == category then
						local row = Window.Row(list, order, cosmetic.DisplayName, cosmetic.Description, nil)
						order += 1
						if owned[cosmetic.Id] then
							local wearing = equipped == cosmetic.Id
							local button = Window.SmallButton(row.Right, if wearing then "TAKE OFF" else "EQUIP",
								if wearing then Theme.Colors.InkSoft else Theme.Colors.Success, UDim2.new(0, 120, 0, 40))
							button.Activated:Connect(function()
								Remotes.GetEvent("CosmeticEquip"):FireServer(category, if wearing then "" else cosmetic.Id)
							end)
						else
							local lock = Window.SmallButton(row.Right, cosmetic.Exclusive or "LOCKED", Theme.Colors.InkSoft, UDim2.new(0, 140, 0, 40))
							lock.AutoButtonColor = false
						end
					end
				end
			end
		elseif tab == "BOOSTS" or tab == "KLUNKS" then
			local products = {}
			for _, product in MonetizationConfig.Products do
				if product.Category == (if tab == "KLUNKS" then "Currency" else "Boosts") then
					table.insert(products, product)
				end
			end
			table.sort(products, function(a: any, b: any)
				return (a.PriceRobux or 0) < (b.PriceRobux or 0)
			end)
			for _, product in products :: any do
				local available = product.ProductId ~= 0 and product.Handler ~= nil
				local row = Window.Row(list, order, product.DisplayName, product.Description, nil)
				order += 1
				local button = Window.SmallButton(row.Right, if available then `BUY  {priceText("product", product.ProductId, product.PriceRobux)}` elseif product.PriceRobux ~= nil then `SOON  R$ {product.PriceRobux}` else "COMING SOON",
					if available then Theme.Colors.Success else Theme.Colors.InkSoft, UDim2.new(0, 160, 0, 40))
				button.Activated:Connect(function()
					promptProduct(product)
				end)
			end
		end
	end
	window.TabChanged.Event:Connect(render)

	open.Activated:Connect(function()
		if window.IsOpen() then
			window.Close()
		else
			window.Open("FEATURED", InputController.GetInputKind() == "Gamepad")
			render()
		end
	end)

	-- The server decides ownership; redraw when it publishes something new.
	localPlayer.AttributeChanged:Connect(function(name: string)
		if string.sub(name, 1, 5) == "Pass_" or name == "CosmeticsOwned" or string.sub(name, 1, 9) == "Equipped_" then
			render()
			if string.sub(name, 1, 5) == "Pass_" and localPlayer:GetAttribute(name) == true then
				NotifyController.Show("Thank you! Your purchase is ready.", "Success")
			end
		end
	end)
	MarketplaceService.PromptGamePassPurchaseFinished:Connect(function(player: Player)
		if player == localPlayer then
			promptOpenUntil = 0 -- the prompt closed (the server re-checks ownership itself)
		end
	end)
	MarketplaceService.PromptProductPurchaseFinished:Connect(function(userId: number)
		if userId == localPlayer.UserId then
			promptOpenUntil = 0
		end
	end)

	screenGui.Parent = localPlayer:WaitForChild("PlayerGui")
end

function ShopController.Start()
	task.spawn(mount)
end

return ShopController
