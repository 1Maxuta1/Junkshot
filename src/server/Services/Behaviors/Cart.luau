--!strict
--[[
	Cart behavior (Metal Cart, Wooden Sled): a transport tool for MORE junk than the hands hold.

	Prompts (owner only)
	  E  Tow / Release   the cart follows behind the owner like it is on a rope
	  Z  Load            moves the last picked-up item from the hands into the cart
	  X  Unload          moves the last loaded item from the cart back into the hands
	  T  Pick up         only when the cart is empty (shared Store prompt)

	The cart is anchored and moved by the server (smoothed PivotTo every Heartbeat while towed),
	so there is no client physics to exploit. Its contents are saved in the cart's record
	(profile.Data.Deployed[i].Contents) and their uids are reported as held (HoldsUid), so a
	loaded item exists only in the cart. Towing stops when the owner dies, leaves or ends up
	further than MaxTowDistance away.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")

local GameConfig = require(ReplicatedStorage.Shared.Config.GameConfig)
local ItemConfig = require(ReplicatedStorage.Shared.Config.ItemConfig)
local JunkFactory = require(ReplicatedStorage.Shared.Util.JunkFactory)
local PlacementRules = require(ReplicatedStorage.Shared.Util.PlacementRules)

local CarryService = require(script.Parent.Parent.CarryService)

local Cart = {}

local CONTENT_SIZE = 1.1 -- studs: largest side of an item shown in the cart
local CONTENT_SLOTS = {
	Vector3.new(-0.75, 1.75, 1.5),
	Vector3.new(0.75, 1.75, 1.5),
	Vector3.new(-0.75, 1.75, 0.5),
	Vector3.new(0.75, 1.75, 0.5),
	Vector3.new(-0.75, 1.75, -0.5),
	Vector3.new(0.75, 1.75, -0.5),
	Vector3.new(-0.75, 1.75, -1.5),
	Vector3.new(0.75, 1.75, -1.5),
}
local GROUND_RAY_HEIGHT = 6
local GROUND_RAY_LENGTH = 20

local api: any = nil
local held: { [string]: boolean } = {} -- uids inside any cart on this server
local towed: { [any]: boolean } = {}

local function contentsOf(entry: any): { any }
	local record = entry.Record
	if type(record.Contents) ~= "table" then
		record.Contents = {}
	end
	return record.Contents
end

local function setCollision(entry: any, solid: boolean)
	local base = entry.Model.PrimaryPart
	if base ~= nil then
		base.CanCollide = solid
	end
end

local function render(entry: any)
	local model: Model = entry.Model
	local folder = model:FindFirstChild("Contents")
	if folder ~= nil then
		folder:Destroy()
	end
	local newFolder = Instance.new("Folder")
	newFolder.Name = "Contents"
	local pivot = model:GetPivot()
	for index, item in contentsOf(entry) do
		local slot = (entry.Behavior.Cart.Slots or CONTENT_SLOTS)[index]
		local copy = if slot ~= nil then JunkFactory.Build(item.Id, "Cosmetic", entry.Behavior.Cart.ContentSize or CONTENT_SIZE) else nil
		if copy ~= nil and slot ~= nil then
			for _, part in copy:GetDescendants() do
				if part:IsA("BasePart") then
					part.Anchored = true
					part.CanCollide = false
					part.CanQuery = false
					part.CanTouch = false
				end
			end
			copy:PivotTo(pivot * CFrame.new(slot) * CFrame.Angles(0, index * 1.3, 0))
			copy.Parent = newFolder
		end
	end
	newFolder.Parent = model

	local capacity = entry.Behavior.Cart.Capacity
	local count = #contentsOf(entry)
	model:SetAttribute("ContentCount", count)
	local text = `{ItemConfig.GetDisplayName(entry.Id)} ({count}/{capacity})`
	for _, prompt in entry.Prompts do
		if prompt.Name ~= "StorePrompt" then
			prompt.ObjectText = text
		end
	end
end

local function setTowing(entry: any, on: boolean)
	if on then
		towed[entry] = true
	else
		towed[entry] = nil
	end
	entry.State.Towing = on
	entry.Model:SetAttribute("Towing", on)
	setCollision(entry, not on) -- while towed it must not shove its owner around
	local prompt = entry.State.TowPrompt
	if prompt ~= nil then
		prompt.ActionText = if on then "Release" else "Tow"
	end
end

---------------------------------------------------------------------------------------------
-- Actions (also called by DevTests)
---------------------------------------------------------------------------------------------

function Cart.Load(entry: any, player: Player): (boolean, string?)
	local contents = contentsOf(entry)
	if #contents >= entry.Behavior.Cart.Capacity then
		return false, "CartFull"
	end
	-- Take and hold in the same step (no yield): the uid is never free in between.
	local item = CarryService.PopTop(player)
	if item == nil then
		return false, "NothingToLoad"
	end
	table.insert(contents, { Uid = item.Uid, Id = item.Id })
	held[item.Uid] = true
	render(entry)
	return true, nil
end

function Cart.Unload(entry: any, player: Player): (boolean, string?)
	local contents = contentsOf(entry)
	if #contents == 0 then
		return false, "CartEmpty"
	end
	if CarryService.IsFull(player) then
		return false, "HandsFull"
	end
	local item = table.remove(contents) :: any
	held[item.Uid] = nil
	local ok, code = CarryService.AddJunk(player, item.Id, item.Uid)
	if not ok then
		table.insert(contents, item) -- never lose it
		held[item.Uid] = true
		render(entry)
		return false, code
	end
	render(entry)
	return true, nil
end

function Cart.ToggleTow(entry: any)
	if entry.Behavior.Cart.Fixed then
		return
	end
	setTowing(entry, not entry.State.Towing)
end

---------------------------------------------------------------------------------------------
-- Behavior contract
---------------------------------------------------------------------------------------------

local MESSAGES: { [string]: string } = {
	CartFull = "The cart is full",
	NothingToLoad = "Your hands are empty",
	CartEmpty = "The cart is empty",
	HandsFull = "Your hands are full",
}

function Cart.Init(placement: any)
	api = placement
end

function Cart.Attach(entry: any)
	for _, item in contentsOf(entry) do
		held[item.Uid] = true
	end
	local base = entry.Model.PrimaryPart
	if not entry.Behavior.Cart.Fixed then -- the Storage Box stays where it is
	entry.State.TowPrompt = api.AddPrompt(entry, base, {
		Name = "TowPrompt",
		Action = "Tow",
		Slot = "Primary",
		OwnerOnly = true,
		Row = 2,
	}, function(_player: Player)
		Cart.ToggleTow(entry)
	end)
	end
	api.AddPrompt(entry, base, {
		Name = "LoadPrompt",
		Action = "Load",
		Slot = "Secondary",
		OwnerOnly = true,
		Row = 1,
		Column = -0.5,
	}, function(player: Player)
		local ok, code = Cart.Load(entry, player)
		if not ok and code ~= nil then
			api.Notify(player, MESSAGES[code] or code)
		end
	end)
	api.AddPrompt(entry, base, {
		Name = "UnloadPrompt",
		Action = "Unload",
		Slot = "Tertiary",
		OwnerOnly = true,
		Row = 1,
		Column = 0.5,
	}, function(player: Player)
		local ok, code = Cart.Unload(entry, player)
		if not ok and code ~= nil then
			api.Notify(player, MESSAGES[code] or code)
		end
	end)
	setTowing(entry, false)
	render(entry)
end

function Cart.Detach(entry: any)
	towed[entry] = nil
	for _, item in contentsOf(entry) do
		held[item.Uid] = nil
	end
end

function Cart.CanStore(entry: any): (boolean, string?)
	if #contentsOf(entry) > 0 then
		return false, "NotEmpty"
	end
	return true, nil
end

function Cart.HoldsUid(uid: string): boolean
	return held[uid] == true
end

---------------------------------------------------------------------------------------------
-- Towing
---------------------------------------------------------------------------------------------

local function groundY(position: Vector3, exclude: { Instance }): number?
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = exclude
	local hit = Workspace:Raycast(position + Vector3.new(0, GROUND_RAY_HEIGHT, 0), Vector3.new(0, -GROUND_RAY_LENGTH, 0), params)
	return if hit ~= nil then hit.Position.Y else nil
end

local function stepTow(entry: any, dt: number, exclude: { Instance })
	local owner: Player = entry.Owner
	local root = CarryService.GetLiveRoot(owner)
	local config = entry.Behavior.Cart
	local pivot = entry.Model:GetPivot()
	if root == nil or (root.Position - pivot.Position).Magnitude > config.MaxTowDistance then
		setTowing(entry, false)
		return
	end
	local ownerFlat = Vector3.new(root.Position.X, pivot.Position.Y, root.Position.Z)
	local away = pivot.Position - ownerFlat
	if away.Magnitude < 0.1 then
		away = -root.CFrame.LookVector
	end
	local desired = ownerFlat + away.Unit * config.FollowDistance
	local y = groundY(desired, exclude) or pivot.Position.Y
	local target = CFrame.lookAt(Vector3.new(desired.X, y, desired.Z), Vector3.new(ownerFlat.X, y, ownerFlat.Z))
	local alpha = 1 - math.exp(-config.FollowSharpness * dt)
	entry.Model:PivotTo(pivot:Lerp(target, alpha))
end

function Cart.Start()
	RunService.Heartbeat:Connect(function(dt: number)
		if next(towed) == nil then
			return
		end
		local exclude: { Instance } = {}
		for _, player in Players:GetPlayers() do
			if player.Character ~= nil then
				table.insert(exclude, player.Character)
			end
		end
		local junk = Workspace:FindFirstChild(GameConfig.Junk.ContainerName)
		if junk ~= nil then
			table.insert(exclude, junk)
		end
		local deployed = Workspace:FindFirstChild(PlacementRules.DEPLOYED_FOLDER)
		if deployed ~= nil then
			table.insert(exclude, deployed)
		end
		for entry in towed do
			stepTow(entry, dt, exclude)
		end
	end)
end

return Cart
