--!strict
--[[
	EconomyController: the client side of the economy (Stage 3). Display only: every number
	comes from the server (DataController mirror, Player attributes, EconomyFx feedback).

	  Hud     balance (count-up), level + XP bar, BAG button        (Hud.luau)
	  Dealer  SELL / SHOP / UPGRADES at the Scrap Dealer booth       (Dealer.luau)
	  Bag     hands + base storage, STORE / TAKE at your base        (Bag.luau)
	Also widens the local pickup prompts to the player's Grabber Arm range (the server checks
	the same range).
]]

local Players = game:GetService("Players")
local ProximityPromptService = game:GetService("ProximityPromptService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local EconomyConfig = require(ReplicatedStorage.Shared.Config.EconomyConfig)
local GameConfig = require(ReplicatedStorage.Shared.Config.GameConfig)
local Remotes = require(ReplicatedStorage.Shared.Remotes)

local CarryController = require(script.Parent.CarryController)
local DataController = require(script.Parent.DataController)
local InputController = require(script.Parent.InputController)
local NotifyController = require(script.Parent.NotifyController)
local Hud = require(script.Hud)
local Dealer = require(script.Dealer)
local Bag = require(script.Bag)

local EconomyController = {}

local localPlayer = Players.LocalPlayer
local DEALER_CLOSE_DISTANCE = EconomyConfig.DealerDistance + 8

local function applyPickupRange(prompt: Instance)
	if not prompt:IsA("ProximityPrompt") or prompt:GetAttribute("PromptKind") ~= nil then
		return
	end
	local range = localPlayer:GetAttribute("PickupRange")
	prompt.MaxActivationDistance = if type(range) == "number" then range else GameConfig.Junk.PickupMaxDistance
end

local function watchPickupRange()
	local container = Workspace:WaitForChild(GameConfig.Junk.ContainerName, 30)
	if container == nil then
		return
	end
	container.DescendantAdded:Connect(applyPickupRange)
	local function all()
		for _, descendant in container:GetDescendants() do
			applyPickupRange(descendant)
		end
	end
	localPlayer:GetAttributeChangedSignal("PickupRange"):Connect(all)
	all()
end

local function mount()
	local screenGui = Instance.new("ScreenGui")
	screenGui.Name = "JunkshotEconomy"
	screenGui.ResetOnSpawn = false
	screenGui.ScreenInsets = Enum.ScreenInsets.CoreUISafeInsets
	screenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	screenGui.DisplayOrder = 7

	local source = {
		Carried = CarryController.GetLocalCarried,
		Stored = DataController.GetItems,
		Balance = DataController.GetKlunks,
	}
	local hud = Hud.Mount(screenGui)
	local dealer = Dealer.Mount(screenGui, source)
	local bag = Bag.Mount(screenGui, source)

	local function gamepad(): boolean
		return InputController.GetInputKind() == "Gamepad"
	end

	local function refreshAll()
		hud.SetBalance(DataController.GetKlunks())
		dealer.Refresh()
		bag.Refresh()
	end
	DataController.Changed:Connect(refreshAll)
	CarryController.Changed:Connect(function()
		dealer.Refresh()
		bag.Refresh()
	end)
	for _, attribute in { "Level", "StorageMax", "CarryMax", "Upgrade_CarryCapacity", "Upgrade_WalkSpeed",
		"Upgrade_PickupRange", "Upgrade_StorageCapacity", "Upgrade_Haggler" } do
		localPlayer:GetAttributeChangedSignal(attribute):Connect(function()
			dealer.Refresh()
			bag.Refresh()
		end)
	end

	Remotes.GetEvent("EconomyFx").OnClientEvent:Connect(function(payload: any)
		if type(payload) ~= "table" then
			return
		end
		if (payload.Kind == "Earn" or payload.Kind == "Spend") and type(payload.Amount) == "number" then
			hud.Float(if payload.Kind == "Earn" then payload.Amount else -payload.Amount)
		elseif payload.Kind == "Message" and type(payload.Text) == "string" then
			NotifyController.Show(payload.Text, payload.Style or "Info")
		end
	end)

	ProximityPromptService.PromptTriggered:Connect(function(prompt: ProximityPrompt, player: Player)
		if player == localPlayer and prompt:GetAttribute("PromptKind") == "Dealer" then
			bag.Close()
			dealer.Open(gamepad())
		end
	end)

	hud.BagClicked.Event:Connect(function()
		dealer.Close()
		bag.Toggle(gamepad())
	end)
	UserInputService.InputBegan:Connect(function(input: InputObject, gameProcessed: boolean)
		if gameProcessed then
			return
		end
		if input.KeyCode == GameConfig.Input.BagKey or input.KeyCode == GameConfig.Input.BagGamepadKey then
			dealer.Close()
			bag.Toggle(gamepad())
		end
	end)

	-- Walking away from the booth closes the dealer window.
	local accumulated = 0
	RunService.Heartbeat:Connect(function(dt: number)
		accumulated += dt
		if accumulated < 0.5 then
			return
		end
		accumulated = 0
		bag.Tick()
		if not dealer.IsOpen() then
			return
		end
		local booth = Workspace:FindFirstChild("ScrapDealer")
		local anchor = if booth ~= nil then booth:FindFirstChild("PromptAnchor") else nil
		local character = localPlayer.Character
		local root = if character ~= nil then character:FindFirstChild("HumanoidRootPart") else nil
		if anchor == nil or root == nil or (anchor.Position - root.Position).Magnitude > DEALER_CLOSE_DISTANCE then
			dealer.Close()
		end
	end)

	screenGui.Parent = localPlayer:WaitForChild("PlayerGui")
	refreshAll()
end

function EconomyController.Start()
	task.spawn(mount)
	task.spawn(watchPickupRange)
end

return EconomyController
