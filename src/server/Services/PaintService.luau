--!strict
--[[
	PaintService: painting your own placed objects with a Paint Bucket (Util/Paint).

	ItemPaint remote (bucketUid, targetUid, hex | ""): the bucket must be carried, the object
	must be yours, placed and close. "" takes the paint off. One bucket is used up
	for one coat; taking the paint off or the same color again costs nothing.

	Saved in profile.Data.Paints = { [item uid] = "rrggbb" }: the color stays when the object is
	picked up and placed again. Uids that the player no longer has are dropped on load; a traded
	or recycled item loses its paint.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local GameConfig = require(ReplicatedStorage.Shared.Config.GameConfig)
local Remotes = require(ReplicatedStorage.Shared.Remotes)
local Paint = require(ReplicatedStorage.Shared.Util.Paint)
local Validate = require(ReplicatedStorage.Shared.Util.Validate)

local CarryService = require(script.Parent.CarryService)
local DataService = require(script.Parent.DataService)
local PlacementService = require(script.Parent.PlacementService)
local RemoteGuard = require(script.Parent.RemoteGuard)

local PaintService = {}

PaintService.Errors = table.freeze({
	NotLoaded = "NotLoaded",
	InvalidArguments = "InvalidArguments",
	NoBucket = "NoBucket",
	NotFound = "NotFound",
	NotOwner = "NotOwner",
	TooFar = "TooFar",
})

local MESSAGES: { [string]: string } = {
	NoBucket = "You need a Paint Bucket",
	NotOwner = "You can only paint your own things",
	TooFar = "Come closer to paint it",
}
local REACH_TOLERANCE = 8 -- studs on top of the client's reach, for lag and driving
local started = false

local function paintsOf(player: Player): { [string]: string }?
	local data = DataService.GetData(player) :: any
	if data == nil then
		return nil
	end
	if type(data.Paints) ~= "table" then
		data.Paints = {}
	end
	return data.Paints
end

local function show(entry: any)
	local paints = paintsOf(entry.Owner)
	local color = if paints ~= nil then Paint.FromHex(paints[entry.Uid]) else nil
	if color ~= nil or entry.Model:GetAttribute("PaintColor") ~= nil then
		Paint.Apply(entry.Model, color)
		entry.Model:SetAttribute("PaintColor", color)
	end
end

function PaintService.Paint(player: Player, bucketUid: any, targetUid: any, hex: any): (boolean, string?)
	local paints = paintsOf(player)
	if paints == nil then
		return false, PaintService.Errors.NotLoaded
	end
	if not Validate.IsUid(bucketUid) or not Validate.IsUid(targetUid) or (hex ~= "" and Paint.FromHex(hex) == nil) then
		return false, PaintService.Errors.InvalidArguments
	end
	local bucket = false
	for _, carried in CarryService.GetCarried(player) do
		if carried.Uid == bucketUid and carried.Id == Paint.ITEM then
			bucket = true
		end
	end
	if not bucket then
		return false, PaintService.Errors.NoBucket
	end
	local entry = PlacementService.GetEntry(targetUid)
	if entry == nil then
		return false, PaintService.Errors.NotFound
	end
	if entry.Owner ~= player then
		return false, PaintService.Errors.NotOwner
	end
	local root = CarryService.GetLiveRoot(player)
	if root == nil or (root.Position - entry.Model:GetPivot().Position).Magnitude > GameConfig.Paint.Reach + REACH_TOLERANCE then
		return false, PaintService.Errors.TooFar
	end
	local wanted = if hex == "" then nil else string.lower(hex)
	if wanted ~= nil and wanted ~= paints[targetUid] and CarryService.TakeByUid(player, bucketUid) == nil then
		return false, PaintService.Errors.NoBucket
	end
	paints[targetUid] = wanted
	show(entry)
	return true, nil
end

-- Every string in a table, however deep: the uids a player still has.
local function strings(value: any, into: { [string]: boolean })
	if type(value) == "string" then
		into[value] = true
	elseif type(value) == "table" then
		for key, child in value do
			strings(key, into)
			strings(child, into)
		end
	end
end

local function prune(player: Player)
	local data = DataService.GetData(player) :: any
	local paints = paintsOf(player)
	if data == nil or paints == nil then
		return
	end
	local owned: { [string]: boolean } = {}
	for _, part in { data.Items, data.Carry, data.Deployed, data.Machine } do
		strings(part, owned)
	end
	for uid in table.clone(paints) do
		if not owned[uid] then
			paints[uid] = nil
		end
	end
end

function PaintService.Start()
	assert(not started, "[PaintService] Start() called twice")
	started = true
	PlacementService.Placed:Connect(show)
	DataService.PlayerLoaded:Connect(prune)
	RemoteGuard.ConnectEvent(Remotes.GetEvent("ItemPaint"), {
		Name = "ItemPaint",
		MaxArgs = 3,
		RateLimit = { MaxRequests = 4, Window = 2 },
		Validate = function(bucketUid: any, targetUid: any, hex: any): boolean
			return Validate.IsUid(bucketUid) and Validate.IsUid(targetUid) and Validate.IsString(hex, 0, 6)
		end,
	}, function(player: Player, bucketUid: string, targetUid: string, hex: string)
		local ok, code = PaintService.Paint(player, bucketUid, targetUid, hex)
		local message = if not ok and code ~= nil then MESSAGES[code] else nil
		if message ~= nil then
			CarryService.Notify(player, message)
		end
	end)
end

return PaintService
