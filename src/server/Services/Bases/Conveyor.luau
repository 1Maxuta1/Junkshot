--!strict
--[[
	Conveyor: the first automation building. Loose world items lying on a conveyor's belt
	(thrown or dropped onto it) roll towards its hopper; at the hopper they go into the owner's
	chest (base storage) with the SAME uid.

	Rules
	  - Only registered world items (JunkService) move; carried, flying (thrown), machine and
	    placed items are not world items, so they are never touched. Items reserved for
	    someone (a machine tray) are skipped.
	  - Into the chest: JunkService.Claim (removes it from the world, atomically) then
	    InventoryService.AddItem(owner, id, uid). If that fails the item is put back where it
	    was. With a full chest the item waits at the hopper (the owner is told once a minute).
	  - One loop for every conveyor on the server (BaseConfig.Conveyor.Step); no per-belt
	    threads, no physics (items are anchored and moved with PivotTo).
	Conveyors exist only while their owner is online (their base is built).
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local BaseConfig = require(ReplicatedStorage.Shared.Config.BaseConfig)
local ItemConfig = require(ReplicatedStorage.Shared.Config.ItemConfig)

local CarryService = require(script.Parent.Parent.CarryService)
local InventoryService = require(script.Parent.Parent.InventoryService)
local JunkService = require(script.Parent.Parent.JunkService)

local Conveyor = {}

type Belt = { Owner: Player, Model: Model, Belt: BasePart, Speed: number, LastFullNotice: number }

local HEIGHT_ABOVE = 4 -- studs above the belt surface that still count as "on the belt"
local HOPPER_MARGIN = 0.4

local belts: { [Model]: Belt } = {}
local started = false

function Conveyor.Register(owner: Player, model: Model, speed: number)
	local belt = model:FindFirstChild("Belt")
	if belt == nil or not belt:IsA("BasePart") then
		return
	end
	belts[model] = { Owner = owner, Model = model, Belt = belt, Speed = speed, LastFullNotice = -math.huge }
end

function Conveyor.Unregister(model: Model?)
	if model ~= nil then
		belts[model] = nil
	end
end

-- Puts one item from the hopper into the owner's chest. Returns true when it was stored.
local function deposit(belt: Belt, junk: Model, uid: string, itemId: string, position: Vector3): boolean
	local owner = belt.Owner
	if (InventoryService.GetItemCount(owner) or math.huge) >= InventoryService.GetCapacity(owner) then
		local now = os.clock()
		if now - belt.LastFullNotice > 60 then
			belt.LastFullNotice = now
			CarryService.Notify(owner, "Your chest is full - the conveyor is waiting")
		end
		return false
	end
	local claimedId, claimedUid = JunkService.Claim(junk, owner)
	if claimedId == nil or claimedUid == nil then
		return false
	end
	local stored = InventoryService.AddItem(owner, claimedId, claimedUid)
	if stored == nil then
		JunkService.SpawnAt(claimedId, position, { Uid = claimedUid }) -- never lose it
		return false
	end
	CarryService.Notify(owner, `Conveyor stored {ItemConfig.GetDisplayName(itemId)}`)
	local _ = uid
	return true
end

-- One update of every conveyor (also called by DevTests with a custom dt).
function Conveyor.Step(dt: number)
	if next(belts) == nil then
		return
	end
	-- One pass over the world items for all belts together.
	local candidates: { { Model: Model, Uid: string, Id: string, Position: Vector3 } } = {}
	JunkService.ForEachClaimable(function(model: Model, uid: string, itemId: string, position: Vector3, reservedFor: number?)
		if reservedFor == nil then
			table.insert(candidates, { Model = model, Uid = uid, Id = itemId, Position = position })
		end
	end)
	if #candidates == 0 then
		return
	end
	local length = BaseConfig.Conveyor.Length
	local halfWidth = BaseConfig.Conveyor.Width / 2
	for model, belt in belts do
		if belt.Owner.Parent ~= Players or model.Parent == nil then
			belts[model] = nil
			continue
		end
		local frame = belt.Belt.CFrame
		local forward = frame.ZVector -- the hopper is on the belt's +Z end
		for _, item in candidates do
			local localPos = frame:PointToObjectSpace(item.Position)
			if math.abs(localPos.X) <= halfWidth and math.abs(localPos.Z) <= length / 2 + HOPPER_MARGIN
				and localPos.Y > -1 and localPos.Y < HEIGHT_ABOVE
			then
				local nextZ = localPos.Z + belt.Speed * dt
				if nextZ >= length / 2 - HOPPER_MARGIN then
					deposit(belt, item.Model, item.Uid, item.Id, item.Position)
				else
					JunkService.MoveTo(item.Model, item.Position + forward * belt.Speed * dt)
				end
			end
		end
	end
end

function Conveyor.Start()
	assert(not started, "[Conveyor] Start() called twice")
	started = true
	local step = BaseConfig.Conveyor.Step
	task.spawn(function()
		while true do
			task.wait(step)
			local ok, err = pcall(Conveyor.Step, step)
			if not ok then
				warn(`[Conveyor] {tostring(err)}`)
			end
		end
	end)
end

return Conveyor
