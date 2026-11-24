--!strict
--[[
	PlacementService: the lifecycle of functional items (Config/Behaviors) and the one place
	that moves them between states. Behavior-specific logic lives in Services/Behaviors/<Kind>.

	States of one item (one uid, always in exactly ONE of them)
	  Carried   in the player's hands (CarryService) - can be thrown, recycled, crafted with
	  Deployed  a placed world object owned by the player (this service), saved in
	            profile.Data.Deployed; a vehicle with a driver is "active" but still Deployed
	  (loose)   lying in the world as junk (JunkService) after a drop / throw

	Transitions (each validated and committed without yielding, so a repeated request finds
	the item already moved and fails):
	  Place  Carried -> Deployed   ItemPlace remote: carried? placeable? limits? PlacementRules?
	  Store  Deployed -> Carried   "Store" prompt: owner? behavior allows it (empty, nobody
	                               seated)? free hand slot?
	  Use    Carried (stays)       ItemUse remote: the behavior acts (detector scan)
	While Deployed the uid is reported to JunkService.RegisterUidSource, so CarryService can
	never accept the same uid again (no duplicates even from crafted requests).

	Persistence: the record lives in profile.Data.Deployed from the moment it is placed. When
	the owner leaves, the objects are removed from the world (the records stay); on the next
	join they are placed again on the owner's plot: where they were placed if that was on the
	own plot (Record.Spot, relative to it), otherwise on a free spot (PLOT_SPOTS). A record that cannot be restored returns to the hands.

	Behavior module contract (Services/Behaviors/<Kind>.luau)
	  Init(api)                       receives this service (no circular require)
	  Attach(entry)                   the model is in the world: add prompts, physics, state
	  Detach(entry)                   undo everything (the model is destroyed right after)
	  CanStore(entry) -> (ok, code?)  optional: refuse storing (seated players, contents)
	  HoldsUid(uid) -> boolean        optional: uids the behavior keeps (cart contents)
	  Use(player, carried, behavior) -> (ok, code?)   Mode "Use" items only
	  Start()                         optional, after every module is initialised

	Public API (server only)
	  Place(player, uid, position, yaw) -> (ok, code?)
	  Store(player, uid) -> (ok, code?)
	  Use(player, uid) -> (ok, code?)
	  GetEntry(uid) -> Entry?, GetEntries(player) -> { Entry }
	  AddPrompt(entry, parent, options, handler) -> ProximityPrompt   (for behaviors)
	  Notify(player, text)
	  Load(player) / Unload(player)   (also used by DevTests to simulate a rejoin)
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local GameConfig = require(ReplicatedStorage.Shared.Config.GameConfig)
local ItemConfig = require(ReplicatedStorage.Shared.Config.ItemConfig)
local Remotes = require(ReplicatedStorage.Shared.Remotes)
local Types = require(ReplicatedStorage.Shared.Types)
local DeployModels = require(ReplicatedStorage.Shared.Util.DeployModels)
local ItemCapabilities = require(ReplicatedStorage.Shared.Util.ItemCapabilities)
local PlacementRules = require(ReplicatedStorage.Shared.Util.PlacementRules)
local Signal = require(ReplicatedStorage.Shared.Util.Signal)
local Validate = require(ReplicatedStorage.Shared.Util.Validate)

local CarryService = require(script.Parent.CarryService)
local DataService = require(script.Parent.DataService)
local JunkService = require(script.Parent.JunkService)
local PlotService = require(script.Parent.PlotService)
local RemoteGuard = require(script.Parent.RemoteGuard)

type CarriedJunk = Types.CarriedJunk
type DeployedRecord = Types.DeployedRecord

export type Entry = {
	Uid: string,
	Id: string,
	Owner: Player,
	OwnerId: number,
	Kind: string,
	Behavior: any, -- Config/Behaviors entry
	Model: Model,
	Record: DeployedRecord, -- the live table inside profile.Data.Deployed
	Prompts: { ProximityPrompt },
	Connections: { RBXScriptConnection },
	State: { [string]: any }, -- the behavior's own runtime state
}

export type PromptOptions = {
	Name: string,
	Action: string,
	Object: string?,
	Slot: string, -- key in GameConfig.Input.Interact
	OwnerOnly: boolean?,
	CardOffset: number?, -- studs above the parent for the prompt card
	Row: number?, -- the cards of one object form a grid above it: row 0 = lowest
	Column: number?, -- -0.5 / 0.5 = left / right half of a row, 0 = centered
}

local PlacementService = {}

PlacementService.Errors = table.freeze({
	NotLoaded = "NotLoaded",
	InvalidArguments = "InvalidArguments",
	NotCarried = "NotCarried",
	NotPlaceable = "NotPlaceable",
	NotUsable = "NotUsable",
	NoCharacter = "NoCharacter",
	LimitReached = "LimitReached",
	VehicleLimit = "VehicleLimit",
	NotFound = "NotFound",
	NotOwner = "NotOwner",
	HandsFull = "HandsFull",
})

PlacementService.Placed = Signal.new() -- (entry)
PlacementService.Stored = Signal.new() -- (entry)

local MESSAGES: { [string]: string } = {
	NotCarried = "You are not holding that",
	NotPlaceable = "That cannot be placed",
	NotUsable = "That cannot be used",
	LimitReached = `You can place at most {GameConfig.Placement.MaxDeployed} things`,
	VehicleLimit = `You can place at most {GameConfig.Placement.MaxVehicles} vehicles`,
	NotOwner = "Only its owner can do that",
	HandsFull = "Your hands are full",
	Occupied = "Someone is sitting in it",
	NotEmpty = "Empty it first",
}

-- Spots on a plot where saved objects reappear (relative to the plot's top center; the machine
-- stands at (0, 0, 6)). Tried in order until a free one is found.
local PLOT_SPOTS = {
	-- Stage 4: kept clear of the chest (-15, 14) and the building slots (BaseConfig.Slots).
	Vector3.new(-12, 0, -9),
	Vector3.new(-4, 0, -15),
	Vector3.new(4, 0, -15),
	Vector3.new(0, 0, -6),
	Vector3.new(-11, 0, -17),
	Vector3.new(7, 0, -6),
	Vector3.new(-5, 0, 16),
	Vector3.new(5, 0, 16),
	Vector3.new(-9, 0, 8),
	Vector3.new(9, 0, 8),
	Vector3.new(0, 0, -11),
	Vector3.new(11, 0, -18),
	Vector3.new(-7, 0, -4),
}

local started = false
local folder: Folder? = nil
local entries: { [string]: Entry } = {}
local loaded: { [Player]: boolean } = {}
local modules: { [string]: any } = {}

---------------------------------------------------------------------------------------------
-- Helpers
---------------------------------------------------------------------------------------------

local function getFolder(): Folder
	if folder ~= nil and folder.Parent ~= nil then
		return folder
	end
	local existing = Workspace:FindFirstChild(PlacementRules.DEPLOYED_FOLDER)
	if existing ~= nil and existing:IsA("Folder") then
		folder = existing
		return existing
	end
	local created = Instance.new("Folder")
	created.Name = PlacementRules.DEPLOYED_FOLDER
	created.Parent = Workspace
	folder = created
	return created
end

function PlacementService.Notify(player: Player, message: string)
	CarryService.Notify(player, message)
end

local function report(player: Player, code: string?)
	if code == nil then
		return
	end
	local text = MESSAGES[code] or PlacementRules.Describe(code)
	if text ~= "" then
		PlacementService.Notify(player, text)
	end
end

local function findCarried(player: Player, uid: string): CarriedJunk?
	for _, entry in CarryService.GetCarried(player) do
		if entry.Uid == uid then
			return entry
		end
	end
	return nil
end

function PlacementService.GetEntry(uid: string): Entry?
	return entries[uid]
end

function PlacementService.GetEntries(player: Player): { Entry }
	local list: { Entry } = {}
	for _, entry in entries do
		if entry.Owner == player then
			table.insert(list, entry)
		end
	end
	return list
end

local function moduleHoldsUid(uid: string): boolean
	for _, module in modules do
		if type(module.HoldsUid) == "function" and module.HoldsUid(uid) then
			return true
		end
	end
	return false
end

local function removeRecord(player: Player, uid: string)
	local data = DataService.GetData(player)
	if data == nil or type(data.Deployed) ~= "table" then
		return
	end
	for index, record in data.Deployed do
		if record.Uid == uid then
			table.remove(data.Deployed, index)
			return
		end
	end
end

---------------------------------------------------------------------------------------------
-- Prompts (shared by every behavior)
---------------------------------------------------------------------------------------------

function PlacementService.AddPrompt(
	entry: Entry,
	parent: Instance,
	options: PromptOptions,
	handler: (player: Player) -> ()
): ProximityPrompt
	local keys = (GameConfig.Input.Interact :: any)[options.Slot]
	assert(keys ~= nil, `[PlacementService] unknown prompt slot "{options.Slot}"`)
	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = options.Name
	prompt.ActionText = options.Action
	prompt.ObjectText = options.Object or ItemConfig.GetDisplayName(entry.Id)
	prompt.KeyboardKeyCode = keys.Key
	prompt.GamepadKeyCode = keys.Gamepad
	prompt.HoldDuration = 0
	prompt.RequiresLineOfSight = false
	prompt.MaxActivationDistance = GameConfig.Placement.InteractDistance
	prompt.Style = Enum.ProximityPromptStyle.Custom
	prompt.Exclusivity = Enum.ProximityPromptExclusivity.OnePerButton
	prompt:SetAttribute("PromptKind", "Deployable")
	prompt:SetAttribute("OwnerUserId", entry.OwnerId)
	prompt:SetAttribute("OwnerOnly", options.OwnerOnly == true)
	if options.CardOffset ~= nil then
		prompt:SetAttribute("CardOffset", options.CardOffset)
	end
	prompt:SetAttribute("CardRow", options.Row or 1)
	prompt:SetAttribute("CardColumn", options.Column or 0)
	prompt.Parent = parent
	table.insert(entry.Prompts, prompt)
	table.insert(entry.Connections, prompt.Triggered:Connect(function(player: Player)
		if entries[entry.Uid] ~= entry then
			return -- already stored / removed
		end
		if options.OwnerOnly and player ~= entry.Owner then
			report(player, "NotOwner")
			return
		end
		if CarryService.GetLiveRoot(player) == nil then
			return
		end
		handler(player)
	end))
	return prompt
end

---------------------------------------------------------------------------------------------
-- Spawning / removing world objects
---------------------------------------------------------------------------------------------

-- "Alex's Bicycle" above every placed object.
local function addOwnerTag(model: Model, owner: Player, itemId: string)
	local base = model.PrimaryPart
	if base == nil then
		return
	end
	local top = DeployModels.GetSize(model:GetAttribute("DeployModel") :: string).Y
	local gui = Instance.new("BillboardGui")
	gui.Name = "OwnerTag"
	gui.Size = UDim2.fromOffset(150, 20)
	-- An attachment straight above the object: billboard offsets turn with a rotated Base.
	local anchor = Instance.new("Attachment")
	anchor.Name = "OwnerTagAnchor"
	anchor.Parent = base
	anchor.WorldPosition = model:GetPivot().Position + Vector3.new(0, top + 0.6, 0)
	gui.MaxDistance = 45
	gui.LightInfluence = 0
	gui.Adornee = anchor
	local label = Instance.new("TextLabel")
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundTransparency = 1
	label.Font = Enum.Font.FredokaOne
	label.Text = `{owner.DisplayName}'s {ItemConfig.GetDisplayName(itemId)}`
	label.TextColor3 = Color3.fromRGB(255, 255, 255)
	label.TextStrokeColor3 = Color3.fromRGB(24, 44, 86)
	label.TextStrokeTransparency = 0.1
	label.TextScaled = true
	label.Parent = gui
	gui.Parent = base
end

local function spawnEntry(owner: Player, record: DeployedRecord, pivot: CFrame): Entry?
	local behavior = ItemCapabilities.GetBehavior(record.Id)
	local module = if behavior ~= nil then modules[behavior.Kind] else nil
	if behavior == nil or behavior.Mode ~= "Place" or module == nil then
		return nil
	end
	local model = DeployModels.Build(behavior.Model, true)
	model.Name = record.Id
	model:SetAttribute("DeployUid", record.Uid)
	model:SetAttribute("ItemId", record.Id)
	model:SetAttribute("DeployModel", behavior.Model)
	model:SetAttribute("BehaviorKind", behavior.Kind)
	model:SetAttribute("BehaviorId", ItemConfig.Get(record.Id).BehaviorId)
	model:SetAttribute("OwnerUserId", owner.UserId)
	model:SetAttribute("OwnerName", owner.DisplayName)
	model:PivotTo(pivot)

	local entry: Entry = {
		Uid = record.Uid,
		Id = record.Id,
		Owner = owner,
		OwnerId = owner.UserId,
		Kind = behavior.Kind,
		Behavior = behavior,
		Model = model,
		Record = record,
		Prompts = {},
		Connections = {},
		State = {},
	}
	entries[record.Uid] = entry
	addOwnerTag(model, owner, record.Id)
	model.Parent = getFolder()

	local ok, err = xpcall(module.Attach, debug.traceback, entry)
	if not ok then
		warn(`[PlacementService] {behavior.Kind}.Attach failed: {tostring(err)}`)
	end

	if behavior.Storable then
		local base = model.PrimaryPart or model
		PlacementService.AddPrompt(entry, base, {
			Name = "StorePrompt",
			Action = "Pick up",
			Slot = "Store",
			OwnerOnly = true,
			Row = 0,
		}, function(player: Player)
			local stored, code = PlacementService.Store(player, entry.Uid)
			if not stored then
				report(player, code)
			end
		end)
	end

	PlacementService.Placed:Fire(entry)
	return entry
end

local function despawnEntry(entry: Entry)
	if entries[entry.Uid] ~= entry then
		return
	end
	entries[entry.Uid] = nil
	local module = modules[entry.Kind]
	if module ~= nil and type(module.Detach) == "function" then
		local ok, err = xpcall(module.Detach, debug.traceback, entry)
		if not ok then
			warn(`[PlacementService] {entry.Kind}.Detach failed: {tostring(err)}`)
		end
	end
	for _, connection in entry.Connections do
		connection:Disconnect()
	end
	table.clear(entry.Connections)
	entry.Model:Destroy()
end

---------------------------------------------------------------------------------------------
-- Transitions
---------------------------------------------------------------------------------------------

function PlacementService.Place(player: Player, uid: any, position: any, yaw: any): (boolean, string?)
	if not loaded[player] then
		return false, PlacementService.Errors.NotLoaded
	end
	if not Validate.IsUid(uid) or typeof(position) ~= "Vector3" or not Validate.IsFiniteNumber(yaw) then
		return false, PlacementService.Errors.InvalidArguments
	end
	local vector = position :: Vector3
	if not (Validate.IsFiniteNumber(vector.X) and Validate.IsFiniteNumber(vector.Y) and Validate.IsFiniteNumber(vector.Z)) then
		return false, PlacementService.Errors.InvalidArguments
	end
	local carried = findCarried(player, uid)
	if carried == nil then
		return false, PlacementService.Errors.NotCarried
	end
	local capabilities = ItemCapabilities.Get(carried.Id)
	if capabilities == nil or not capabilities.CanBePlaced then
		return false, PlacementService.Errors.NotPlaceable
	end
	local behavior = capabilities.Behavior
	local owned = PlacementService.GetEntries(player)
	if #owned >= GameConfig.Placement.MaxDeployed then
		return false, PlacementService.Errors.LimitReached
	end
	if behavior.Kind == "Vehicle" then
		local vehicles = 0
		for _, entry in owned do
			if entry.Kind == "Vehicle" then
				vehicles += 1
			end
		end
		if vehicles >= GameConfig.Placement.MaxVehicles then
			return false, PlacementService.Errors.VehicleLimit
		end
	end
	local root = CarryService.GetLiveRoot(player)
	if root == nil then
		return false, PlacementService.Errors.NoCharacter
	end
	local pivot, code = PlacementRules.Check({
		UserId = player.UserId,
		ModelName = behavior.Model,
		Position = vector,
		Yaw = (yaw :: number) % (math.pi * 2),
		RootPosition = root.Position,
		Tolerance = GameConfig.Placement.DistanceTolerance,
	})
	if pivot == nil then
		return false, code
	end
	local data = DataService.GetData(player)
	if data == nil then
		return false, PlacementService.Errors.NotLoaded
	end

	-- Commit: hands -> world, with no yield in between.
	local taken = CarryService.TakeByUid(player, uid)
	if taken == nil then
		return false, PlacementService.Errors.NotCarried
	end
	local record: DeployedRecord = { Uid = taken.Uid, Id = taken.Id }
	if PlotService.OwnerAt(pivot.Position) == player.UserId then
		local plot = PlotService.GetPlot(player)
		if plot ~= nil then
			local offset = PlotService.GetPlotCFrame(plot):ToObjectSpace(pivot)
			local _, spotYaw = offset:ToEulerAnglesYXZ()
			record.Spot = { offset.X, offset.Y, offset.Z, spotYaw }
		end
	end
	table.insert(data.Deployed, record)
	local entry = spawnEntry(player, record, pivot)
	if entry == nil then
		-- Cannot happen with a valid config; never lose the item.
		removeRecord(player, taken.Uid)
		CarryService.AddJunk(player, taken.Id, taken.Uid)
		return false, PlacementService.Errors.NotPlaceable
	end
	return true, nil
end

function PlacementService.Store(player: Player, uid: string): (boolean, string?)
	local entry = entries[uid]
	if entry == nil then
		return false, PlacementService.Errors.NotFound
	end
	if entry.Owner ~= player then
		return false, PlacementService.Errors.NotOwner
	end
	local module = modules[entry.Kind]
	if module ~= nil and type(module.CanStore) == "function" then
		local ok, code = module.CanStore(entry)
		if not ok then
			return false, code
		end
	end
	if CarryService.IsFull(player) then
		return false, PlacementService.Errors.HandsFull
	end

	-- Commit: world -> hands. The entry is removed first so the uid is free for CarryService.
	despawnEntry(entry)
	removeRecord(player, uid)
	local added, code = CarryService.AddJunk(player, entry.Id, entry.Uid)
	if not added then
		warn(`[PlacementService] {player.Name}: storing {entry.Id} failed ({tostring(code)}); kept in the save`)
		local data = DataService.GetData(player)
		if data ~= nil then
			table.insert(data.Deployed, entry.Record)
		end
		return false, code
	end
	PlacementService.Stored:Fire(entry)
	return true, nil
end

function PlacementService.Use(player: Player, uid: any): (boolean, string?)
	if not loaded[player] then
		return false, PlacementService.Errors.NotLoaded
	end
	if not Validate.IsUid(uid) then
		return false, PlacementService.Errors.InvalidArguments
	end
	local carried = findCarried(player, uid)
	if carried == nil then
		return false, PlacementService.Errors.NotCarried
	end
	local capabilities = ItemCapabilities.Get(carried.Id)
	if capabilities == nil or not capabilities.CanBeUsed then
		return false, PlacementService.Errors.NotUsable
	end
	local module = modules[capabilities.Behavior.Kind]
	if module == nil or type(module.Use) ~= "function" then
		return false, PlacementService.Errors.NotUsable
	end
	return module.Use(player, carried, capabilities.Behavior)
end

---------------------------------------------------------------------------------------------
-- Session lifecycle
---------------------------------------------------------------------------------------------

local function findPlotSpot(player: Player, record: DeployedRecord): CFrame?
	local plot = PlotService.GetPlot(player)
	if plot == nil then
		return nil
	end
	local behavior = ItemCapabilities.GetBehavior(record.Id)
	local base = PlotService.GetPlotCFrame(plot)
	local saved = record.Spot
	if type(saved) == "table" and #saved == 4 then
		local valid = true
		for _, value in saved do
			valid = valid and Validate.IsFiniteNumber(value)
		end
		if valid then
			local _, yaw = (base * CFrame.Angles(0, saved[4], 0)):ToEulerAnglesYXZ()
			local pivot = PlacementRules.Check({
				UserId = player.UserId,
				ModelName = behavior.Model,
				Position = (base * CFrame.new(saved[1], saved[2], saved[3])).Position,
				Yaw = yaw,
			})
			if pivot ~= nil then
				return pivot
			end
		end
	end
	for _, spot in PLOT_SPOTS do
		local point = base * CFrame.new(spot)
		local _, yaw = (base * CFrame.Angles(0, math.pi, 0)):ToEulerAnglesYXZ()
		local pivot = PlacementRules.Check({
			UserId = player.UserId,
			ModelName = behavior.Model,
			Position = point.Position,
			Yaw = yaw,
		})
		if pivot ~= nil then
			return pivot
		end
	end
	return nil
end

-- Places the player's saved objects again (on their plot). Invalid or duplicate records are
-- dropped; a record without a free spot goes back to the hands, or waits for the next join.
function PlacementService.Load(player: Player)
	if loaded[player] or player.Parent ~= Players then
		return
	end
	local data = DataService.GetData(player)
	if data == nil then
		return
	end
	CarryService.EnsureRestored(player) -- the uid checks below need the hands restored first
	loaded[player] = true
	if type(data.Deployed) ~= "table" then
		data.Deployed = {}
	end
	local valid: { DeployedRecord } = {}
	local seen: { [string]: boolean } = {}
	for _, record in data.Deployed do
		local uid = if type(record) == "table" then record.Uid else nil
		local id = if type(record) == "table" then record.Id else nil
		local capabilities = if type(id) == "string" then ItemCapabilities.Get(id) else nil
		if Validate.IsUid(uid) and capabilities ~= nil and capabilities.CanBePlaced and not seen[uid]
			and entries[uid] == nil and not CarryService.IsUidCarried(uid) and not JunkService.IsUidActive(uid)
		then
			seen[uid] = true
			if type(record.Contents) == "table" then
				local contents: { CarriedJunk } = {}
				for _, item in record.Contents do
					if type(item) == "table" and Validate.IsUid(item.Uid) and ItemConfig.Exists(item.Id) and not seen[item.Uid]
						and not CarryService.IsUidCarried(item.Uid) and not JunkService.IsUidActive(item.Uid)
					then
						seen[item.Uid] = true
						table.insert(contents, { Uid = item.Uid, Id = item.Id })
					end
				end
				record.Contents = contents
			end
			table.insert(valid, record)
		else
			warn(`[PlacementService] {player.Name}: dropped an invalid saved placed item ({tostring(id)})`)
		end
	end
	data.Deployed = valid

	local remaining: { DeployedRecord } = {}
	for _, record in valid do
		local pivot = findPlotSpot(player, record)
		local entry = if pivot ~= nil then spawnEntry(player, record, pivot) else nil
		if entry ~= nil then
			table.insert(remaining, record)
		elseif (record.Contents == nil or #record.Contents == 0) and not CarryService.IsFull(player)
			and CarryService.AddJunk(player, record.Id, record.Uid)
		then
			continue -- no room on the plot: back into the hands
		else
			table.insert(remaining, record) -- stays saved, placed again next time
		end
	end
	data.Deployed = remaining
end

-- Removes the player's objects from the world. The saved records stay untouched.
function PlacementService.Unload(player: Player)
	for _, entry in PlacementService.GetEntries(player) do
		despawnEntry(entry)
	end
	loaded[player] = nil
end

---------------------------------------------------------------------------------------------
-- Startup
---------------------------------------------------------------------------------------------

function PlacementService.Start()
	assert(not started, "[PlacementService] Start() called twice")
	started = true
	getFolder()

	for _, child in script.Parent.Behaviors:GetChildren() do
		if child:IsA("ModuleScript") then
			local module = require(child) :: any
			modules[child.Name] = module
			if type(module.Init) == "function" then
				module.Init(PlacementService)
			end
		end
	end
	for _, module in modules do
		if type(module.Start) == "function" then
			module.Start()
		end
	end

	JunkService.RegisterUidSource(function(uid: string): boolean
		return entries[uid] ~= nil or moduleHoldsUid(uid)
	end)

	PlotService.PlotAssigned:Connect(function(player: Player)
		-- A moment later than BaseService, so the base (chest, slots) exists and saved objects
		-- are placed around it instead of onto a building slot.
		task.delay(0.2, PlacementService.Load, player)
	end)
	PlotService.PlotReleased:Connect(PlacementService.Unload)
	Players.PlayerRemoving:Connect(PlacementService.Unload)
	for _, player in Players:GetPlayers() do
		if PlotService.GetPlot(player) ~= nil then
			PlacementService.Load(player)
		end
	end

	RemoteGuard.ConnectEvent(Remotes.GetEvent("ItemPlace"), {
		Name = "ItemPlace",
		MaxArgs = 3,
		RateLimit = GameConfig.RateLimits.ItemPlace,
		Validate = function(uid: any, position: any, yaw: any): boolean
			return Validate.IsUid(uid) and typeof(position) == "Vector3" and Validate.IsFiniteNumber(yaw)
		end,
	}, function(player: Player, uid: string, position: Vector3, yaw: number)
		local ok, code = PlacementService.Place(player, uid, position, yaw)
		if not ok then
			report(player, code)
		end
	end)

	RemoteGuard.ConnectEvent(Remotes.GetEvent("ItemUse"), {
		Name = "ItemUse",
		MaxArgs = 1,
		RateLimit = GameConfig.RateLimits.ItemUse,
		Validate = Validate.IsUid,
	}, function(player: Player, uid: string)
		local ok, code = PlacementService.Use(player, uid)
		if not ok then
			report(player, code)
		end
	end)

end

return PlacementService
