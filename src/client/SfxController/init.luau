--!strict
--[[
	SfxController: decides WHEN item sounds play (Config/ItemSounds says what, AudioController.
	PlayItem plays them). Local and quiet; nothing is sent to the server.

	  pickup    the item's own sound (one per PICKUP_GAP, not when the save is restored)
	  throw     a swish at the thrower, the item's sound where it lands
	  placing   the item's sound at the new object; gadgets also when their mode changes
	  sale      coins; buttons a soft click; chest / windows opening
	  race      beeps in the countdown, a fanfare for your own finish
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local ItemSounds = require(ReplicatedStorage.Shared.Config.ItemSounds)
local PlacementRules = require(ReplicatedStorage.Shared.Util.PlacementRules)
local Remotes = require(ReplicatedStorage.Shared.Remotes)

local AudioController = require(script.Parent.AudioController)
local CarryController = require(script.Parent.CarryController)

local SfxController = {}

local localPlayer = Players.LocalPlayer
local QUIET_START = 4 -- seconds after the start without sounds (restoring the save)
local PICKUP_GAP = 0.12
local HEAR = 70

local startedAt = 0
local lastPickup = 0

local function playItem(itemId: any, parent: Instance?, volume: number?)
	if type(itemId) == "string" and os.clock() - startedAt > QUIET_START then
		local family, pitch = ItemSounds.ForItem(itemId)
		AudioController.PlayItem(family, pitch, parent, volume, HEAR)
	end
end

local function playEvent(name: string, parent: Instance?, volume: number?)
	if os.clock() - startedAt > QUIET_START then
		local family, pitch = ItemSounds.ForEvent(name)
		AudioController.PlayItem(family, pitch, parent, volume, HEAR)
	end
end

-- A sound at a fixed place.
local function at(position: Vector3, play: (Instance) -> ())
	local holder = Instance.new("Attachment")
	holder.WorldPosition = position
	holder.Parent = Workspace.Terrain
	play(holder)
	task.delay(2, holder.Destroy, holder)
end

local function watchDeployed()
	local folder = Workspace:WaitForChild(PlacementRules.DEPLOYED_FOLDER, 60)
	if folder == nil then
		return
	end
	local function add(model: Instance, isNew: boolean)
		if not model:IsA("Model") then
			return
		end
		local base = model:FindFirstChild("Base")
		if isNew and base ~= nil then
			playItem(model:GetAttribute("ItemId"), base)
		end
		local function changed()
			playItem(model:GetAttribute("ItemId"), model:FindFirstChild("Base"), 0.8)
		end
		for _, name in { "GadgetMode", "GadgetFire", "Speech", "HoloId" } do
			model:GetAttributeChangedSignal(name):Connect(changed)
		end
	end
	for _, model in folder:GetChildren() do
		add(model, false)
	end
	folder.ChildAdded:Connect(function(model: Instance)
		task.defer(add, model, true)
	end)
end

local function watchButtons()
	local gui = localPlayer:WaitForChild("PlayerGui")
	local function hook(instance: Instance)
		if instance:IsA("GuiButton") then
			instance.Activated:Connect(function()
				playEvent("Button", nil, 1)
			end)
		elseif instance:IsA("Frame") and instance:HasTag("JunkshotMenu") and instance.Name ~= "RewardReveal" then
			instance:GetPropertyChangedSignal("Visible"):Connect(function()
				if instance.Visible then
					playEvent(if instance.Name == "BagWindow" then "ChestOpen" else "Window", nil, 0.7)
				end
			end)
		end
	end
	for _, instance in gui:GetDescendants() do
		hook(instance)
	end
	gui.DescendantAdded:Connect(function(instance: Instance)
		task.defer(hook, instance) -- tags are set right after parenting
	end)
end

local function watchRace()
	local lastBeep = -1
	while true do
		task.wait(0.1)
		local goAt = Workspace:GetAttribute("RaceGoAt")
		if Workspace:GetAttribute("RaceState") == "Countdown" and type(goAt) == "number" and localPlayer:GetAttribute("RaceLap") ~= nil then
			local left = math.ceil(goAt - Workspace:GetServerTimeNow())
			if left ~= lastBeep and left >= 0 and left <= 3 then
				lastBeep = left
				local family = ItemSounds.Families.Beep
				AudioController.PlayItem(family, if left == 0 then 1.5 else 1, nil, 1, HEAR)
			end
		else
			lastBeep = -1
		end
	end
end

function SfxController.Start()
	startedAt = os.clock()
	CarryController.ItemsAdded:Connect(function(added: any)
		if os.clock() - lastPickup >= PICKUP_GAP and added[1] ~= nil then
			lastPickup = os.clock()
			playItem(added[1].Id, nil)
		end
	end)
	Remotes.GetEvent("ThrowFx").OnClientEvent:Connect(function(fx: any)
		if type(fx) ~= "table" or typeof(fx.Origin) ~= "Vector3" or typeof(fx.FinalPivot) ~= "CFrame" or type(fx.FlightTime) ~= "number" then
			return
		end
		at(fx.Origin, function(holder)
			playEvent("Throw", holder, 0.8)
		end)
		task.delay(fx.FlightTime, at, fx.FinalPivot.Position, function(holder)
			playItem(fx.JunkId, holder)
		end)
	end)
	Remotes.GetEvent("EconomyFx").OnClientEvent:Connect(function(payload: any)
		if type(payload) == "table" and payload.Kind == "Earn" and payload.Reason ~= "Onboarding" then
			playEvent("Sell", nil, 1)
		end
	end)
	task.spawn(watchDeployed)
	task.spawn(watchButtons)
	task.spawn(watchRace)
end

return SfxController
