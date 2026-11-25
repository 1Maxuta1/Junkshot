--!strict
--[[
	SlowFieldService: inside a running Aurora Reactor's aura everything moves slower.

	  Players   attribute SlowFactor (nil = normal): PlayerUpgradeService scales the walk speed,
	            the player's own client slows jumps and falls (client SlowFieldController)
	  Vehicles  Behaviors/Vehicle asks FactorAt every step; racers are never slowed

	A field = a placed gadget with Gadget.SlowField in Config/Behaviors, switched on (mode 2).
	Fields do not add up: the strongest one counts. Nothing is saved.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local ItemCapabilities = require(ReplicatedStorage.Shared.Util.ItemCapabilities)
local PlacementRules = require(ReplicatedStorage.Shared.Util.PlacementRules)

local SlowFieldService = {}

local STEP = 0.15 -- seconds between two looks
local ON = 2 -- GadgetMode of a running field
local fields: { { Center: Vector3, Radius: number, Factor: number } } = {}
local started = false

local function scan()
	table.clear(fields)
	local folder = Workspace:FindFirstChild(PlacementRules.DEPLOYED_FOLDER)
	if folder == nil then
		return
	end
	for _, model in folder:GetChildren() do
		if not model:IsA("Model") or model:GetAttribute("GadgetMode") ~= ON then
			continue
		end
		local itemId = model:GetAttribute("ItemId")
		local capabilities = if type(itemId) == "string" then ItemCapabilities.Get(itemId) else nil
		local behavior = if capabilities ~= nil then capabilities.Behavior else nil
		local field = if behavior ~= nil and behavior.Gadget ~= nil then behavior.Gadget.SlowField else nil
		if field ~= nil then
			table.insert(fields, { Center = model:GetBoundingBox().Position, Radius = field.Radius, Factor = field.Factor })
		end
	end
end

-- 1 = normal speed.
function SlowFieldService.FactorAt(position: Vector3): number
	local factor = 1
	for _, field in fields do
		if field.Factor < factor and (position - field.Center).Magnitude <= field.Radius then
			factor = field.Factor
		end
	end
	return factor
end

-- One look at all fields and players (also used by DevTests).
function SlowFieldService.Update()
	scan()
	for _, player in Players:GetPlayers() do
		local character = player.Character
		local root = if character ~= nil then character:FindFirstChild("HumanoidRootPart") else nil
		local factor = if root ~= nil and root:IsA("BasePart") then SlowFieldService.FactorAt(root.Position) else 1
		local value = if factor < 1 and player:GetAttribute("RaceJoined") ~= true then factor else nil
		if player:GetAttribute("SlowFactor") ~= value then
			player:SetAttribute("SlowFactor", value)
		end
	end
end

function SlowFieldService.Start()
	assert(not started, "[SlowFieldService] Start() called twice")
	started = true
	task.spawn(function()
		while true do
			SlowFieldService.Update()
			task.wait(STEP)
		end
	end)
end

return SlowFieldService
