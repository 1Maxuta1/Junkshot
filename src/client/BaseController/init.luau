--!strict
--[[
	BaseController: the base window, opened from a building slot's prompt (C / L2 / tap) on
	YOUR base. Display only; every action is BaseAction on the server (BaseService), which
	checks everything again.

	  Base level line   current level / slots and EXPAND BASE (next price, player level)
	  Empty slot        every building (Config/BaseConfig.Buildings) with BUILD price, or why
	                    it is not possible yet (base level, player level, limit)
	  Built slot        the building with UPGRADE (if it has more levels) and REMOVE (refund)
	  Locked slot       how to unlock it (EXPAND BASE)
	The window closes when you walk away from the slot.
]]

local CollectionService = game:GetService("CollectionService")
local HttpService = game:GetService("HttpService")
local Players = game:GetService("Players")
local ProximityPromptService = game:GetService("ProximityPromptService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local BaseConfig = require(ReplicatedStorage.Shared.Config.BaseConfig)
local Remotes = require(ReplicatedStorage.Shared.Remotes)
local KlunksFormat = require(ReplicatedStorage.Shared.Util.KlunksFormat)

local ItemConfig = require(ReplicatedStorage.Shared.Config.ItemConfig)
local Rarities = require(ReplicatedStorage.Shared.Config.Rarities)
local DataController = require(script.Parent.DataController)
local InputController = require(script.Parent.InputController)
local Theme = require(script.Parent.UI.Theme)
local UpgradeModels = require(script.Parent.UI.UpgradeModels)
local Window = require(script.Parent.EconomyController.Window)

local BaseController = {}

local localPlayer = Players.LocalPlayer
local CLOSE_DISTANCE = 20

local function newRequestId(): string
	return HttpService:GenerateGUID(false)
end

local function send(action: string, slotId: string?, buildingId: string?)
	Remotes.GetEvent("BaseAction"):FireServer(newRequestId(), action, slotId, buildingId)
end

local function attribute(name: string, default: number): number
	local value = localPlayer:GetAttribute(name)
	return if type(value) == "number" then value else default
end

-- My base folder (PlayerBase inside my plot).
local function myBase(): Instance?
	for _, plot in CollectionService:GetTagged("BasePlot") do
		if plot:GetAttribute("Owner") == localPlayer.UserId then
			return plot:FindFirstChild("PlayerBase")
		end
	end
	return nil
end

local function slotPad(slotId: string): Instance?
	local base = myBase()
	return if base ~= nil then base:FindFirstChild(`Slot{slotId}`) else nil
end

local function countBuilt(buildingId: string): number
	local base = myBase()
	local count = 0
	if base ~= nil then
		for _, child in base:GetChildren() do
			if child:GetAttribute("SlotId") ~= nil and child:GetAttribute("BuildingId") == buildingId then
				count += 1
			end
		end
	end
	return count
end

local function mount()
	local screenGui = Instance.new("ScreenGui")
	screenGui.Name = "JunkshotBase"
	screenGui.ResetOnSpawn = false
	screenGui.ScreenInsets = Enum.ScreenInsets.CoreUISafeInsets
	screenGui.DisplayOrder = 7
	local window = Window.Mount(screenGui, "BaseWindow", "MY BASE", { "BASE" })
	local currentSlot: string? = nil
	local baseWatch: RBXScriptConnection? = nil
	local shownWatch: RBXScriptConnection? = nil
	local pending = false

	local hint = Theme.Label({
		Name = "Hint",
		Text = "",
		Size = UDim2.new(1, 0, 1, 0),
		Font = Theme.FontBody,
		Color = Theme.Colors.InkSoft,
		MinTextSize = 11,
		MaxTextSize = 15,
		XAlignment = Enum.TextXAlignment.Left,
		Parent = window.Footer,
	})

	local function render()
		if not window.IsOpen() or currentSlot == nil then
			return
		end
		local slotId = currentSlot :: string
		local list = window.Content("BASE")
		Window.Clear(list)
		local order = 0
		local function add(): number
			order += 1
			return order
		end
		local baseLevel = attribute("BaseLevel", 1)
		local playerLevel = attribute("Level", 1)
		local slots = BaseConfig.BaseLevels[baseLevel].Slots

		-- Base level / expansion
		local nextBase = BaseConfig.BaseLevels[baseLevel + 1]
		local baseRow = Window.Row(list, add(), `BASE LEVEL {baseLevel}/{#BaseConfig.BaseLevels}  ·  {slots} building slot{if slots == 1 then "" else "s"}`,
			if nextBase ~= nil then `Expand to unlock {nextBase.Slots - slots} more slot(s)` else "Fully expanded", nil)
		Window.RowIcon(baseRow, UpgradeModels.Build("Base", if nextBase ~= nil then nextBase.Slots else slots))
		if nextBase ~= nil then
			local locked = playerLevel < (nextBase.RequiredLevel or 1)
			local button = Window.SmallButton(baseRow.Right, if locked then `LV {nextBase.RequiredLevel}` else `EXPAND {KlunksFormat.Format(nextBase.Price)}`,
				if locked then Theme.Colors.InkSoft else Theme.Colors.Accent, UDim2.new(0, 170, 0, 40))
			if not locked then
				button.Activated:Connect(function()
					send("UpgradeBase")
				end)
			end
		end

		local pad = slotPad(slotId)
		local unlocked = pad ~= nil and pad:GetAttribute("Unlocked") == true
		local builtId = if pad ~= nil then pad:GetAttribute("BuildingId") else nil
		window.SetTitle(`SLOT {slotId}`)

		if not unlocked then
			Window.Header(list, add(), "This slot is locked - expand your base above to use it.")
			hint.Text = "Expanding the base unlocks more building slots."
			return
		end

		if type(builtId) == "string" then
			local definition = (BaseConfig.Buildings :: any)[builtId]
			local level = pad and pad:GetAttribute("BuildingLevel") or 1
			local row = Window.Row(list, add(), `{definition.DisplayName}  ·  Lv {level}/{#definition.Levels}`, definition.Description, nil)
			local nearest: Model? = nil -- the building on this slot, as its picture
			for _, child in (pad :: Instance).Parent:GetChildren() do
				if child:IsA("Model") and child ~= pad and child:GetAttribute("BuildingId") == builtId
					and (child:GetPivot().Position - (pad :: Model):GetPivot().Position).Magnitude < 3
				then
					nearest = child
				end
			end
			Window.RowIcon(row, UpgradeModels.Copy(nearest))
			local nextLevel = definition.Levels[level + 1]
			if nextLevel ~= nil then
				local locked = playerLevel < (nextLevel.RequiredLevel or 1)
				local upgrade = Window.SmallButton(row.Right, if locked then `LV {nextLevel.RequiredLevel}` else `UPGRADE {KlunksFormat.Format(nextLevel.Price)}`,
					if locked then Theme.Colors.InkSoft else Theme.Colors.Success, UDim2.new(0, 160, 0, 40))
				if not locked then
					upgrade.Activated:Connect(function()
						send("UpgradeBuilding", slotId)
					end)
				end
			end
			local spent = 0
			for step = 1, level do
				spent += definition.Levels[step].Price
			end
			local remove = Window.SmallButton(row.Right, `REMOVE +{KlunksFormat.Format(math.floor(spent * BaseConfig.RemoveRefund))}`,
				Theme.Colors.Danger, UDim2.new(0, 150, 0, 40))
			remove.Activated:Connect(function()
				send("Remove", slotId)
			end)
			hint.Text = "Removing gives back half of what it cost."
			if builtId == "DisplayStand" then
				Window.Header(list, add(), "CHOOSE THE TROPHY (from your chest)")
				local shownUid = pad and pad:GetAttribute("ShownUid")
				local stored = {}
				for uid, record in DataController.GetItems() do
					table.insert(stored, { Uid = uid, Id = record.id, Rank = Rarities.GetRank(ItemConfig.GetRarity(record.id)) })
				end
				table.sort(stored, function(a, b)
					if a.Rank ~= b.Rank then
						return a.Rank > b.Rank
					end
					return a.Uid < b.Uid
				end)
				if #stored == 0 then
					Window.Header(list, add(), "Your chest is empty - store an item first.")
				end
				for _, item in stored do
					local itemRow = Window.Row(list, add(), ItemConfig.GetDisplayName(item.Id), ItemConfig.GetRarity(item.Id) or "", item.Id)
					local shown = item.Uid == shownUid
					local choose = Window.SmallButton(itemRow.Right, if shown then "SHOWN" else "SHOW",
						if shown then Theme.Colors.InkSoft else Theme.Colors.Success, UDim2.new(0, 110, 0, 40))
					choose.Activated:Connect(function()
						send("SetTrophy", slotId, item.Uid)
					end)
				end
			end
			return
		end

		Window.Header(list, add(), "BUILD HERE")
		for _, buildingId in BaseConfig.BuildingOrder do
			local definition = (BaseConfig.Buildings :: any)[buildingId]
			local first = definition.Levels[1]
			local row = Window.Row(list, add(), definition.DisplayName, definition.Description, nil)
			local reason: string? = nil
			if baseLevel < definition.RequiredBaseLevel then
				reason = `BASE LV {definition.RequiredBaseLevel}`
			elseif playerLevel < (first.RequiredLevel or 1) then
				reason = `LV {first.RequiredLevel}`
			elseif countBuilt(buildingId) >= definition.MaxPerBase then
				reason = `MAX {definition.MaxPerBase}`
			end
			local button = Window.SmallButton(row.Right, reason or `BUILD {KlunksFormat.Format(first.Price)}`,
				if reason ~= nil then Theme.Colors.InkSoft else Theme.Colors.Success, UDim2.new(0, 160, 0, 40))
			if reason == nil then
				button.Activated:Connect(function()
					send("Build", slotId, buildingId)
				end)
			end
		end
		hint.Text = "Buildings are saved with your base."
	end

	ProximityPromptService.PromptTriggered:Connect(function(prompt: ProximityPrompt, player: Player)
		if player ~= localPlayer or prompt:GetAttribute("PromptKind") ~= "BaseSlot"
			or prompt:GetAttribute("OwnerUserId") ~= localPlayer.UserId
		then
			return
		end
		local slotId = prompt:GetAttribute("SlotId")
		if type(slotId) ~= "string" then
			return
		end
		currentSlot = slotId
		window.Open(nil, InputController.GetInputKind() == "Gamepad")
		if baseWatch ~= nil then
			baseWatch:Disconnect()
		end
		local base = myBase()
		if base ~= nil then
			-- The server rebuilds a slot after every change: redraw once it arrived.
			baseWatch = base.ChildAdded:Connect(function()
				if not pending then
					pending = true
					task.defer(function()
						pending = false
						render()
					end)
				end
			end)
		end
		local pad = slotPad(slotId)
		if shownWatch ~= nil then
			shownWatch:Disconnect()
		end
		shownWatch = if pad ~= nil then pad:GetAttributeChangedSignal("ShownUid"):Connect(render) else nil
		render()
	end)
	window.Closed.Event:Connect(function()
		if baseWatch ~= nil then
			baseWatch:Disconnect()
			baseWatch = nil
		end
	end)

	-- Re-render when the base changes (pads are rebuilt) or the player's level / money changes.
	for _, name in { "BaseLevel", "Level", "StorageMax" } do
		localPlayer:GetAttributeChangedSignal(name):Connect(render)
	end
	local accumulated = 0
	RunService.Heartbeat:Connect(function(dt: number)
		accumulated += dt
		if accumulated < 0.5 or not window.IsOpen() then
			return
		end
		accumulated = 0
		local pad = if currentSlot ~= nil then slotPad(currentSlot :: string) else nil
		local character = localPlayer.Character
		local root = if character ~= nil then character:FindFirstChild("HumanoidRootPart") else nil
		if pad == nil or root == nil or not pad:IsA("Model") or (pad:GetPivot().Position - root.Position).Magnitude > CLOSE_DISTANCE then
			window.Close()
		end
	end)

	screenGui.Parent = localPlayer:WaitForChild("PlayerGui")
end

function BaseController.Start()
	task.spawn(mount)
end

return BaseController
