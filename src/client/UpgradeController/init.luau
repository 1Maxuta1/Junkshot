--!strict
--[[
	UpgradeController: notices your own upgrades (attributes published by the server) and shows
	UI/UpgradeReveal for each. The backpack has its own (BackpackController). Display only.

	  player    Snow Boots, Grabber Arm, Haggler        Player attributes Upgrade_<Id>
	  base      chest, base size                        ChestLevel, BaseLevel
	            buildings built / upgraded              models in your base (BuildingId, Level)
	  machine   speed, output storage, machine level    attributes of your machine

	Only a step of exactly one level counts, so loading a save shows nothing.
]]

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local BaseConfig = require(ReplicatedStorage.Shared.Config.BaseConfig)
local MachineConfig = require(ReplicatedStorage.Shared.Config.MachineConfig)
local PlayerUpgrades = require(ReplicatedStorage.Shared.Config.PlayerUpgrades)

local UpgradeModels = require(script.Parent.UI.UpgradeModels)
local UpgradeReveal = require(script.Parent.UI.UpgradeReveal)

local UpgradeController = {}

local localPlayer = Players.LocalPlayer
local rgb = Color3.fromRGB
-- The higher the level, the hotter the color.
local COLORS = { rgb(255, 255, 255), rgb(110, 230, 140), rgb(90, 180, 255), rgb(200, 120, 255), rgb(255, 190, 60), rgb(255, 110, 90) }

local function colorOf(level: number): Color3
	return COLORS[math.clamp(level, 1, #COLORS)]
end

local function show(model: Model?, head: string, name: string, detail: string, level: number)
	if model ~= nil then
		UpgradeReveal.Sparks(localPlayer, colorOf(level))
		UpgradeReveal.Show({ Model = model, Head = head, Name = name, Detail = detail, Color = colorOf(level) })
	end
end

local function watch(target: Instance, attribute: string, changed: (level: number) -> ())
	local last = target:GetAttribute(attribute)
	target:GetAttributeChangedSignal(attribute):Connect(function()
		local level = target:GetAttribute(attribute)
		local step = type(last) == "number" and type(level) == "number" and level == last + 1
		last = level
		if step then
			changed(level)
		end
	end)
end

local function ownOf(tag: string): Instance?
	for _, instance in CollectionService:GetTagged(tag) do
		if instance:GetAttribute("OwnerUserId") == localPlayer.UserId and instance:IsDescendantOf(Workspace) then
			return instance
		end
	end
	return nil
end

local function watchPlayer()
	for _, id in { "WalkSpeed", "PickupRange", "Haggler" } do
		local upgrade = PlayerUpgrades.Get(id) :: any
		watch(localPlayer, `Upgrade_{id}`, function(level: number)
			local old, new = upgrade.Levels[level - 1], upgrade.Levels[level]
			if old == nil or new == nil then
				return
			end
			local detail = if id == "Haggler"
				then `SELL BONUS  +{math.round(old.Value * 100)}% > +{math.round(new.Value * 100)}%`
				else `{old.Value} > {new.Value} {string.upper(upgrade.Unit)}`
			show(UpgradeModels.Build(id, level), "UPGRADED!", `{string.upper(upgrade.DisplayName)}  LV {level}`, detail, level)
		end)
	end
	watch(localPlayer, "ChestLevel", function(level: number)
		local old, new = BaseConfig.Chest.Levels[level - 1], BaseConfig.Chest.Levels[level]
		if old == nil or new == nil then
			return
		end
		task.wait(0.3) -- the new chest replaces the old one in the world
		local chest = ownOf("BaseChest")
		show(UpgradeModels.Copy(chest), "NEW CHEST!", string.upper(new.Name), `{old.Capacity} > {new.Capacity} SLOTS`, level)
	end)
	watch(localPlayer, "BaseLevel", function(level: number)
		local old, new = BaseConfig.BaseLevels[level - 1], BaseConfig.BaseLevels[level]
		if old ~= nil and new ~= nil then
			show(UpgradeModels.Build("Base", new.Slots), "BASE EXPANDED!", `BASE LV {level}`, `{old.Slots} > {new.Slots} BUILDING SLOTS`, level + 1)
		end
	end)
end

local watchedMachines: { [Instance]: boolean } = {}
local function watchMachine(machine: Instance)
	if watchedMachines[machine] or machine:GetAttribute("OwnerUserId") ~= localPlayer.UserId then
		return
	end
	watchedMachines[machine] = true
	for _, id in MachineConfig.UpgradeOrder do
		local upgrade = (MachineConfig.Upgrades :: any)[id]
		watch(machine, `Upgrade{id}`, function(level: number)
			local index = math.clamp(level, 2, #upgrade.Levels)
			local old, new = upgrade.Levels[index - 1].Value, upgrade.Levels[index].Value
			local detail = if id == "Speed"
				then `{math.round((1 - new) * 100)}% FASTER`
				elseif id == "Storage" then `{old} > {new} OUTPUT SLOTS`
				else "NEW RECIPES UNLOCKED"
			local model = if id == "Level" then UpgradeModels.Copy(machine) else UpgradeModels.Build(id, index)
			show(model, "MACHINE UPGRADED!", `{if id == "Level" then "MACHINE" else string.upper(upgrade.DisplayName)}  LV {index}`, detail, index)
		end)
	end
end

local watchedBases: { [Instance]: boolean } = {}
local function watchBase(chest: Instance)
	local folder = chest.Parent
	if folder == nil or watchedBases[folder] or chest:GetAttribute("OwnerUserId") ~= localPlayer.UserId then
		return
	end
	watchedBases[folder] = true
	local since = os.clock()
	local levels: { [string]: number } = {}
	local function seen(child: Instance, isNew: boolean)
		local id, level = child:GetAttribute("BuildingId"), child:GetAttribute("Level")
		if not child:IsA("Model") or type(id) ~= "string" or type(level) ~= "number" then
			return
		end
		local at = child:GetPivot().Position
		local key = `{id}{math.round(at.X)},{math.round(at.Z)}`
		local before = levels[key] or 0
		levels[key] = level
		local definition = (BaseConfig.Buildings :: any)[id]
		if isNew and level == before + 1 and definition ~= nil and os.clock() - since > 5 then -- 5 s: the base is being set up
			show(UpgradeModels.Copy(child), if level == 1 then "NEW BUILDING!" else "UPGRADED!", string.upper(definition.DisplayName),
				if level == 1 then definition.Description else `LEVEL {level}`, level + 1)
		end
	end
	for _, child in folder:GetChildren() do
		seen(child, false)
	end
	folder.ChildAdded:Connect(function(child: Instance)
		task.wait(0.2) -- its parts arrive after it
		seen(child, true)
	end)
end

function UpgradeController.Start()
	watchPlayer()
	local function tagged(tag: string, added: (Instance) -> ())
		local function later(instance: Instance)
			task.defer(added, instance)
		end
		for _, instance in CollectionService:GetTagged(tag) do
			later(instance)
		end
		CollectionService:GetInstanceAddedSignal(tag):Connect(later)
	end
	tagged(MachineConfig.Tag, watchMachine)
	tagged("BaseChest", watchBase)
end

return UpgradeController
