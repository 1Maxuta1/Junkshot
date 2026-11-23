--!strict
--[[
	ProgressionService: player level and experience (rules in Config/Progression).

	XP sources (all server-side; the client never reports XP):
	  - Discover: the first time an item id reaches the hands (CarryService.ItemAdded) or base
	    storage (InventoryService.ItemAdded). Each id pays once per player, ever.
	  - Machine jobs that finish (MachineService.JobFinished): recycling, crafting, mythic.
	  - Selling at the dealer (SellService calls AddXP).
	Saved in profile.Data.Progress = { Level, XP, Discovered }. Published as Player attributes
	Level, XP and XPNext so the HUD needs no remote.

	API: GetLevel(player), AddXP(player, amount, reason), Discover(player, itemId),
	     LevelChanged Signal (player, level)
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local ItemConfig = require(ReplicatedStorage.Shared.Config.ItemConfig)
local Progression = require(ReplicatedStorage.Shared.Config.Progression)
local Recipes = require(ReplicatedStorage.Shared.Config.Recipes)
local Signal = require(ReplicatedStorage.Shared.Util.Signal)
local Validate = require(ReplicatedStorage.Shared.Util.Validate)

local CarryService = require(script.Parent.CarryService)
local DataService = require(script.Parent.DataService)
local EconomyService = require(script.Parent.EconomyService)
local InventoryService = require(script.Parent.InventoryService)
local MachineService = require(script.Parent.MachineService)

local ProgressionService = {}

ProgressionService.LevelChanged = Signal.new() -- (player: Player, level: number)

local started = false

local function progressOf(player: Player): any?
	local data = DataService.GetData(player)
	if data == nil then
		return nil
	end
	local progress = data.Progress
	if type(progress) ~= "table" then
		progress = { Level = 1, XP = 0, Discovered = {} }
		data.Progress = progress
	end
	if not Validate.IsInteger(progress.Level, 1, Progression.MaxLevel) then
		progress.Level = 1
	end
	if not Validate.IsInteger(progress.XP, 0) then
		progress.XP = 0
	end
	if type(progress.Discovered) ~= "table" then
		progress.Discovered = {}
	end
	return progress
end

local function publish(player: Player)
	local progress = progressOf(player)
	if progress == nil then
		return
	end
	player:SetAttribute("Level", progress.Level)
	player:SetAttribute("XP", progress.XP)
	player:SetAttribute("XPNext", if progress.Level >= Progression.MaxLevel then 0 else Progression.XpToNext(progress.Level))
end

function ProgressionService.GetLevel(player: Player): number
	local progress = progressOf(player)
	return if progress ~= nil then progress.Level else 1
end

function ProgressionService.AddXP(player: Player, amount: number, reason: string)
	if not Validate.IsInteger(amount, 1) then
		return
	end
	local progress = progressOf(player)
	if progress == nil or progress.Level >= Progression.MaxLevel then
		return
	end
	progress.XP += amount
	local leveled = false
	while progress.Level < Progression.MaxLevel and progress.XP >= Progression.XpToNext(progress.Level) do
		progress.XP -= Progression.XpToNext(progress.Level)
		progress.Level += 1
		leveled = true
	end
	if progress.Level >= Progression.MaxLevel then
		progress.XP = 0
	end
	publish(player)
	if leveled then
		EconomyService.Message(player, `Level up! You are now level {progress.Level}`, "Success")
		ProgressionService.LevelChanged:Fire(player, progress.Level)
	end
	local _ = reason
end

-- First time this player gets an item id: XP by rarity (once per id, ever).
function ProgressionService.Discover(player: Player, itemId: string)
	local progress = progressOf(player)
	if progress == nil or progress.Discovered[itemId] then
		return
	end
	local rarity = ItemConfig.GetRarity(itemId)
	if rarity == nil then
		return
	end
	progress.Discovered[itemId] = true
	local xp = (Progression.Discover :: any)[rarity] or 0
	if xp > 0 then
		EconomyService.Message(player, `New discovery: {ItemConfig.GetDisplayName(itemId)} (+{xp} XP)`, "Success")
		ProgressionService.AddXP(player, xp, "Discover")
	end
end

function ProgressionService.Start()
	assert(not started, "[ProgressionService] Start() called twice")
	started = true

	CarryService.ItemAdded:Connect(function(player: Player, itemId: string)
		ProgressionService.Discover(player, itemId)
	end)
	InventoryService.ItemAdded:Connect(function(player: Player, _uid: string, record: any)
		ProgressionService.Discover(player, record.id)
	end)
	MachineService.JobFinished:Connect(function(player: Player, result: any, kind: string?)
		if kind == "Recycle" then
			ProgressionService.AddXP(player, Progression.Recycle, "Recycle")
		elseif kind == "Mythic" then
			ProgressionService.AddXP(player, Progression.MythicCraft, "Mythic")
		elseif kind == "Craft" and Recipes.Get(result.Id) ~= nil then
			local rarity = ItemConfig.GetRarity(result.Id) or "Common"
			ProgressionService.AddXP(player, (Progression.Craft :: any)[rarity] or 0, "Craft")
		end
	end)

	DataService.PlayerLoaded:Connect(publish)
	for _, player in Players:GetPlayers() do
		if DataService.IsLoaded(player) then
			publish(player)
		end
	end
end

return ProgressionService
