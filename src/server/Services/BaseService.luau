--!strict
--[[
	BaseService: one service for every player's personal base (Config/BaseConfig).

	PlotService still decides WHICH plot a player gets while they are online (one per player,
	released on leave). BaseService builds the base on that plot from the player's SAVED base
	state, so the base is the same on any plot and on any server:
	  profile.Data.Base = { Level, ChestLevel, Buildings = { [slotId] = { Id, Level } } }
	  profile.Data.Items = the chest contents (InventoryService, unchanged format)

	On the plot (folder "PlayerBase" inside the plot model, rebuilt from data):
	  Chest        model per chest level; prompt "Open" (owner only) -> the client's bag window.
	               Items move in / out only within Chest.UseDistance (StorageService checks).
	  Slot pads    predefined building places; locked ones need a higher base level.
	               Prompt "Build" / "Expand" / "Manage" (owner only) -> the client's base window.
	  Buildings    Conveyor (Bases/Conveyor), Storage Rack (+chest slots), Trophy Stand (shows the
	               rarest stored item), Warm Lantern.
	  Flag         one banner per base level.

	Every change comes through ONE remote, BaseAction(requestId, action, slotId?, buildingId?),
	and always acts on the caller's own base: there is no base or plot id to forge. Each action
	checks, without yielding until the change is done: data loaded, request id new (duplicate
	protection), standing at the base, valid slot / building, unlocked, limits, player level,
	money. Money goes through EconomyService (logged with the request id).

	API: GetStorageCapacity(player), IsNearChest(player), IsAtBase(player), GetData(player),
	     Act(player, requestId, action, slotId?, buildingId?) -> (ok, code?)  (also DevTests)
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local BaseConfig = require(ReplicatedStorage.Shared.Config.BaseConfig)
local GameConfig = require(ReplicatedStorage.Shared.Config.GameConfig)
local ItemConfig = require(ReplicatedStorage.Shared.Config.ItemConfig)
local Rarities = require(ReplicatedStorage.Shared.Config.Rarities)
local Remotes = require(ReplicatedStorage.Shared.Remotes)
local JunkFactory = require(ReplicatedStorage.Shared.Util.JunkFactory)
local Paint = require(ReplicatedStorage.Shared.Util.Paint)
local Validate = require(ReplicatedStorage.Shared.Util.Validate)

local CarryService = require(script.Parent.CarryService)
local DataService = require(script.Parent.DataService)
local EconomyService = require(script.Parent.EconomyService)
local InventoryService = require(script.Parent.InventoryService)
local PlotService = require(script.Parent.PlotService)
local ProgressionService = require(script.Parent.ProgressionService)
local RemoteGuard = require(script.Parent.RemoteGuard)
local BaseModels = require(script.Parent.Bases.BaseModels)
local Conveyor = require(script.Parent.Bases.Conveyor)

local BaseService = {}

BaseService.Errors = table.freeze({
	NotLoaded = "NotLoaded",
	InvalidArguments = "InvalidArguments",
	Duplicate = "Duplicate",
	NotAtBase = "NotAtBase",
	UnknownSlot = "UnknownSlot",
	SlotLocked = "SlotLocked",
	SlotTaken = "SlotTaken",
	SlotEmpty = "SlotEmpty",
	UnknownBuilding = "UnknownBuilding",
	BaseLevelTooLow = "BaseLevelTooLow",
	LimitReached = "LimitReached",
	LevelTooLow = "LevelTooLow",
	MaxLevel = "MaxLevel",
	NotEnough = "NotEnough",
	Blocked = "Blocked",
})

local MESSAGES: { [string]: string } = {
	NotAtBase = "Go to your base first",
	SlotLocked = "Expand your base to unlock this slot",
	SlotTaken = "Something is already built there",
	BaseLevelTooLow = "Expand your base first",
	LimitReached = "You have the maximum number of these",
	LevelTooLow = "Reach a higher player level first",
	MaxLevel = "Already at the highest level",
	NotEnough = "Not enough money",
	Blocked = "Move your placed items off the slot first",
}

local SLOT_ZONE_TAG = "BaseSlotZone"
local BASE_MARGIN = 6 -- studs around the plot pad that still count as "at your base"
local FLAG_POSITION = Vector3.new(19, 0, -19)

type SlotView = { Pad: Model, Building: Model?, Prompt: ProximityPrompt }
type Base = {
	Player: Player,
	Plot: Model,
	Folder: Model,
	Chest: Model?,
	Flag: Model?,
	Slots: { [string]: SlotView },
	StandsDirty: boolean,
}

local started = false
local bases: { [Player]: Base } = {}

---------------------------------------------------------------------------------------------
-- Data
---------------------------------------------------------------------------------------------

local function slotById(slotId: string): any?
	for _, slot in BaseConfig.Slots do
		if slot.Id == slotId then
			return slot
		end
	end
	return nil
end

-- The live, validated base data (repairs anything out of range instead of failing).
local function baseData(player: Player): any?
	local data = DataService.GetData(player)
	if data == nil then
		return nil
	end
	local base = data.Base
	if type(base) ~= "table" then
		base = { Level = 1, ChestLevel = 1, Buildings = {} }
		data.Base = base
	end
	if not Validate.IsInteger(base.Level, 1, #BaseConfig.BaseLevels) then
		base.Level = 1
	end
	if not Validate.IsInteger(base.ChestLevel, 1, #BaseConfig.Chest.Levels) then
		base.ChestLevel = 1
	end
	if type(base.Buildings) ~= "table" then
		base.Buildings = {}
	end
	for slotId, building in base.Buildings do
		local definition = if type(building) == "table" then (BaseConfig.Buildings :: any)[building.Id] else nil
		if slotById(slotId) == nil or definition == nil then
			base.Buildings[slotId] = nil
		elseif not Validate.IsInteger(building.Level, 1, #definition.Levels) then
			building.Level = 1
		end
	end
	return base
end

function BaseService.GetData(player: Player): any?
	local base = baseData(player)
	return if base ~= nil then table.clone(base) else nil
end

function BaseService.GetStorageCapacity(player: Player): number
	local base = baseData(player)
	if base == nil then
		return BaseConfig.Chest.Levels[1].Capacity
	end
	local capacity = BaseConfig.Chest.Levels[base.ChestLevel].Capacity
	for _, building in base.Buildings do
		if building.Id == "StorageRack" then
			capacity += BaseConfig.Buildings.StorageRack.Levels[building.Level].Value
		end
	end
	return capacity
end

local function unlockedSlots(base: any): number
	return BaseConfig.BaseLevels[base.Level].Slots
end

local function slotIndex(slotId: string): number
	for index, slot in BaseConfig.Slots do
		if slot.Id == slotId then
			return index
		end
	end
	return math.huge
end

---------------------------------------------------------------------------------------------
-- World
---------------------------------------------------------------------------------------------

local function plotFrame(base: Base): CFrame
	return PlotService.GetPlotCFrame(base.Plot)
end

local function addPrompt(parent: Instance, owner: Player, kind: string, action: string, object: string, slotId: string?): ProximityPrompt
	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = `{kind}Prompt`
	prompt.ActionText = action
	prompt.ObjectText = object
	prompt.KeyboardKeyCode = GameConfig.Input.BaseKey
	prompt.GamepadKeyCode = GameConfig.Input.BaseGamepadKey
	prompt.HoldDuration = 0
	prompt.RequiresLineOfSight = false
	prompt.MaxActivationDistance = if kind == "Chest" then BaseConfig.Chest.UseDistance - 2 else 8
	prompt.Style = Enum.ProximityPromptStyle.Custom
	prompt.Exclusivity = Enum.ProximityPromptExclusivity.OnePerButton
	prompt:SetAttribute("PromptKind", kind)
	prompt:SetAttribute("OwnerUserId", owner.UserId)
	prompt:SetAttribute("OwnerOnly", true)
	prompt:SetAttribute("CardOffset", 3)
	if slotId ~= nil then
		prompt:SetAttribute("SlotId", slotId)
	end
	prompt.Parent = parent
	return prompt
end

-- The rarest item in the chest (highest rarity, then highest id for stability).
local function rarestStored(player: Player): string?
	local best: string? = nil
	local bestRank = -1
	for _, record in InventoryService.GetAllItems(player) or {} do
		local rank = Rarities.GetRank(ItemConfig.GetRarity(record.id))
		if rank > bestRank or (rank == bestRank and best ~= nil and record.id > best) then
			best, bestRank = record.id, rank
		end
	end
	return best
end

local function refreshStands(base: Base)
	base.StandsDirty = false
	local rarest = rarestStored(base.Player)
	local data = baseData(base.Player)
	for slotId, view in base.Slots do
		-- The owner's choice (a chest item); the rarest chest item when none is chosen or it left.
		local state = if data ~= nil then data.Buildings[slotId] else nil
		local chosen = if state ~= nil and type(state.Shown) == "string" then InventoryService.GetItem(base.Player, state.Shown) else nil
		local itemId = if chosen ~= nil then chosen.id else rarest
		view.Pad:SetAttribute("ShownUid", if chosen ~= nil then (state :: any).Shown else nil)
		local building = view.Building
		local plinth = if building ~= nil then building:FindFirstChild("Plinth") else nil
		if building ~= nil and plinth ~= nil and plinth:IsA("BasePart") then
			local old = building:FindFirstChild("Shown")
			if old ~= nil then
				old:Destroy()
			end
			if itemId ~= nil then
				local shown = JunkFactory.Build(itemId, "Cosmetic", 2.4)
				if shown ~= nil then
					shown.Name = "Shown"
					for _, descendant in shown:GetDescendants() do
						if descendant:IsA("BasePart") then
							descendant.Anchored = true
							descendant.CanCollide = false
							descendant.CanQuery = false
						end
					end
					shown:PivotTo(plinth.CFrame * CFrame.new(0, plinth.Size.Y / 2 + 1.6, 0))
					shown.Parent = building
				end
			end
		end
	end
end

local function markStandsDirty(player: Player)
	local base = bases[player]
	if base == nil or base.StandsDirty then
		return
	end
	base.StandsDirty = true
	task.defer(function()
		if bases[player] == base then
			refreshStands(base)
		end
	end)
end

local function buildSlot(base: Base, slot: any, index: number)
	local data = baseData(base.Player)
	if data == nil then
		return
	end
	local old = base.Slots[slot.Id]
	if old ~= nil then
		Conveyor.Unregister(old.Building)
		old.Pad:Destroy()
		if old.Building ~= nil then
			old.Building:Destroy()
		end
	end
	local frame = plotFrame(base) * CFrame.new(slot.Position)
	local unlocked = index <= unlockedSlots(data)
	local pad = BaseModels.SlotPad(BaseConfig.SlotSize, unlocked)
	pad.Name = `Slot{slot.Id}`
	pad:PivotTo(frame)
	-- An invisible zone so nothing can be PLACED onto a slot (PlacementRules refuses it).
	local zone = Instance.new("Part")
	zone.Name = "Zone"
	zone.Size = Vector3.new(BaseConfig.SlotSize, 4, BaseConfig.SlotSize)
	zone.CFrame = frame * CFrame.new(0, 2.2, 0)
	zone.Transparency = 1
	zone.Anchored = true
	zone.CanCollide = false
	zone.CanTouch = false
	zone.CanQuery = false -- rays and overlap checks ignore it; PlacementRules tests it explicitly
	zone:AddTag(SLOT_ZONE_TAG)
	zone.Parent = pad
	pad:SetAttribute("SlotId", slot.Id)
	pad:SetAttribute("Unlocked", unlocked)
	pad.Parent = base.Folder

	local state = data.Buildings[slot.Id]
	local building: Model? = nil
	local marker = pad:FindFirstChild("Marker") :: BasePart
	local prompt: ProximityPrompt
	if state ~= nil then
		local definition = (BaseConfig.Buildings :: any)[state.Id]
		building = BaseModels.Building(definition.Model)
		local model = building :: Model
		model:PivotTo(frame)
		model:SetAttribute("BuildingId", state.Id)
		model:SetAttribute("Level", state.Level)
		model.Parent = base.Folder
		pad:SetAttribute("BuildingId", state.Id)
		pad:SetAttribute("BuildingLevel", state.Level)
		prompt = addPrompt(marker, base.Player, "BaseSlot", "Manage", definition.DisplayName, slot.Id)
		if state.Id == "Conveyor" then
			Conveyor.Register(base.Player, model, definition.Levels[state.Level].Value)
		end
	else
		pad:SetAttribute("BuildingId", nil)
		pad:SetAttribute("BuildingLevel", nil)
		prompt = addPrompt(marker, base.Player, "BaseSlot", if unlocked then "Build" else "Expand base", "Empty slot", slot.Id)
	end
	base.Slots[slot.Id] = { Pad = pad, Building = building, Prompt = prompt }
end

local function buildChest(base: Base)
	local data = baseData(base.Player)
	if data == nil then
		return
	end
	if base.Chest ~= nil then
		base.Chest:Destroy()
	end
	local chest = BaseModels.Chest(data.ChestLevel)
	-- Next to the machine's front right corner, facing the same way as the machine.
	local frame = plotFrame(base) * CFrame.new(BaseConfig.Chest.Position)
	chest:PivotTo(frame)
	chest:SetAttribute("OwnerUserId", base.Player.UserId)
	chest:SetAttribute("ChestLevel", data.ChestLevel)
	chest:AddTag("BaseChest")
	local body = chest:FindFirstChild("Body") :: BasePart
	addPrompt(body, base.Player, "Chest", "Open", BaseConfig.Chest.Levels[data.ChestLevel].Name)
	chest.Parent = base.Folder
	base.Chest = chest
	-- Its paint (PaintService, key "Chest") survives every rebuild, a new chest level too.
	local profile = DataService.GetData(base.Player) :: any
	local color = if profile ~= nil and type(profile.Paints) == "table" then Paint.FromHex(profile.Paints.Chest) else nil
	if color ~= nil then
		Paint.Apply(chest, color)
		chest:SetAttribute("PaintColor", color)
	end
end

-- The player's chest model (nil while the base is not built).
function BaseService.GetChest(player: Player): Model?
	local base = bases[player]
	return if base ~= nil then base.Chest else nil
end

local function buildFlag(base: Base)
	local data = baseData(base.Player)
	if data == nil then
		return
	end
	if base.Flag ~= nil then
		base.Flag:Destroy()
	end
	local flag = BaseModels.Flag(data.Level)
	flag:PivotTo(plotFrame(base) * CFrame.new(FLAG_POSITION))
	flag.Parent = base.Folder
	base.Flag = flag
end

local function publish(player: Player)
	local data = baseData(player)
	if data == nil then
		return
	end
	player:SetAttribute("BaseLevel", data.Level)
	player:SetAttribute("ChestLevel", data.ChestLevel)
	player:SetAttribute("StorageMax", BaseService.GetStorageCapacity(player))
end

local function load(player: Player)
	local plot = PlotService.GetPlot(player)
	if plot == nil or bases[player] ~= nil or baseData(player) == nil then
		return
	end
	local folder = Instance.new("Model")
	folder.Name = "PlayerBase"
	folder:SetAttribute("OwnerUserId", player.UserId)
	folder.Parent = plot
	local base: Base = { Player = player, Plot = plot, Folder = folder, Chest = nil, Flag = nil, Slots = {}, StandsDirty = false }
	bases[player] = base
	buildChest(base)
	buildFlag(base)
	for index, slot in BaseConfig.Slots do
		buildSlot(base, slot, index)
	end
	refreshStands(base)
	publish(player)
end

local function unload(player: Player)
	local base = bases[player]
	if base == nil then
		return
	end
	bases[player] = nil
	for _, view in base.Slots do
		Conveyor.Unregister(view.Building)
	end
	base.Folder:Destroy()
end

---------------------------------------------------------------------------------------------
-- Checks
---------------------------------------------------------------------------------------------

function BaseService.IsAtBase(player: Player): boolean
	local base = bases[player]
	local root = CarryService.GetLiveRoot(player)
	local pad = if base ~= nil then base.Plot:FindFirstChild("Pad") else nil
	if root == nil or pad == nil or not pad:IsA("BasePart") then
		return false
	end
	local p = pad.CFrame:PointToObjectSpace(root.Position)
	return math.abs(p.X) <= pad.Size.X / 2 + BASE_MARGIN and math.abs(p.Z) <= pad.Size.Z / 2 + BASE_MARGIN and p.Y < 40
end

function BaseService.IsNearChest(player: Player): boolean
	local base = bases[player]
	local root = CarryService.GetLiveRoot(player)
	local chest = if base ~= nil then base.Chest else nil
	if root == nil or chest == nil then
		return false
	end
	local offset = chest:GetPivot().Position - root.Position
	return Vector3.new(offset.X, 0, offset.Z).Magnitude <= BaseConfig.Chest.UseDistance and math.abs(offset.Y) < 12
end

-- Nothing placed by a player may stand on a slot that is about to get a building.
local function slotIsClear(base: Base, slotId: string): boolean
	local view = base.Slots[slotId]
	local zone = if view ~= nil then view.Pad:FindFirstChild("Zone") else nil
	if zone == nil or not zone:IsA("BasePart") then
		return false
	end
	local deployed = workspace:FindFirstChild("Deployed")
	if deployed == nil then
		return true
	end
	local params = OverlapParams.new()
	params.FilterType = Enum.RaycastFilterType.Include
	params.FilterDescendantsInstances = { deployed }
	return #workspace:GetPartBoundsInBox(zone.CFrame, zone.Size, params) == 0
end

local function countBuilt(data: any, buildingId: string): number
	local count = 0
	for _, building in data.Buildings do
		if building.Id == buildingId then
			count += 1
		end
	end
	return count
end

local function pay(player: Player, price: number, reason: string, requestId: string): (boolean, string?)
	if price <= 0 then
		return true, nil
	end
	local ok = EconomyService.Spend(player, price, reason, requestId)
	return ok, if ok then nil else BaseService.Errors.NotEnough
end

---------------------------------------------------------------------------------------------
-- Actions
---------------------------------------------------------------------------------------------

function BaseService.Act(player: Player, requestId: any, action: any, slotId: any, buildingId: any): (boolean, string?)
	local errors = BaseService.Errors
	local data = baseData(player)
	local base = bases[player]
	if data == nil or base == nil then
		return false, errors.NotLoaded
	end
	if not Validate.IsUid(requestId) or type(action) ~= "string" then
		return false, errors.InvalidArguments
	end
	if EconomyService.IsProcessed(player, requestId) then
		return false, errors.Duplicate
	end
	if not BaseService.IsAtBase(player) then
		return false, errors.NotAtBase
	end
	local level = ProgressionService.GetLevel(player)

	if action == "UpgradeChest" then
		local nextLevel = BaseConfig.Chest.Levels[data.ChestLevel + 1]
		if nextLevel == nil then
			return false, errors.MaxLevel
		end
		if level < (nextLevel.RequiredLevel or 1) then
			return false, errors.LevelTooLow
		end
		local ok, code = pay(player, nextLevel.Price, "Base:Chest", requestId)
		if not ok then
			return false, code
		end
		data.ChestLevel += 1
		EconomyService.MarkProcessed(player, requestId)
		buildChest(base)
		publish(player)
		EconomyService.Message(player, `Chest upgraded: {nextLevel.Name} ({nextLevel.Capacity} slots)!`, "Success")
		return true, nil
	elseif action == "UpgradeBase" then
		local nextLevel = BaseConfig.BaseLevels[data.Level + 1]
		if nextLevel == nil then
			return false, errors.MaxLevel
		end
		if level < (nextLevel.RequiredLevel or 1) then
			return false, errors.LevelTooLow
		end
		local ok, code = pay(player, nextLevel.Price, "Base:Expand", requestId)
		if not ok then
			return false, code
		end
		data.Level += 1
		EconomyService.MarkProcessed(player, requestId)
		buildFlag(base)
		for index, slot in BaseConfig.Slots do
			buildSlot(base, slot, index)
		end
		refreshStands(base)
		publish(player)
		EconomyService.Message(player, `Base expanded to level {data.Level}!`, "Success")
		return true, nil
	end

	-- Slot actions
	if type(slotId) ~= "string" or slotById(slotId) == nil then
		return false, errors.UnknownSlot
	end
	local index = slotIndex(slotId)
	if index > unlockedSlots(data) then
		return false, errors.SlotLocked
	end
	local current = data.Buildings[slotId]

	if action == "Build" then
		if current ~= nil then
			return false, errors.SlotTaken
		end
		local definition = if type(buildingId) == "string" then (BaseConfig.Buildings :: any)[buildingId] else nil
		if definition == nil then
			return false, errors.UnknownBuilding
		end
		if data.Level < definition.RequiredBaseLevel then
			return false, errors.BaseLevelTooLow
		end
		if countBuilt(data, buildingId) >= definition.MaxPerBase then
			return false, errors.LimitReached
		end
		local first = definition.Levels[1]
		if level < (first.RequiredLevel or 1) then
			return false, errors.LevelTooLow
		end
		if not slotIsClear(base, slotId) then
			return false, errors.Blocked
		end
		local ok, code = pay(player, first.Price, `Base:Build:{buildingId}`, requestId)
		if not ok then
			return false, code
		end
		data.Buildings[slotId] = { Id = buildingId, Level = 1 }
		EconomyService.MarkProcessed(player, requestId)
		buildSlot(base, slotById(slotId), index)
		refreshStands(base)
		publish(player)
		EconomyService.Message(player, `Built: {definition.DisplayName}!`, "Success")
		return true, nil
	end

	if current == nil then
		return false, errors.SlotEmpty
	end
	local definition = (BaseConfig.Buildings :: any)[current.Id]

	if action == "UpgradeBuilding" then
		local nextLevel = definition.Levels[current.Level + 1]
		if nextLevel == nil then
			return false, errors.MaxLevel
		end
		if level < (nextLevel.RequiredLevel or 1) then
			return false, errors.LevelTooLow
		end
		local ok, code = pay(player, nextLevel.Price, `Base:Upgrade:{current.Id}`, requestId)
		if not ok then
			return false, code
		end
		current.Level += 1
		EconomyService.MarkProcessed(player, requestId)
		buildSlot(base, slotById(slotId), index)
		refreshStands(base)
		publish(player)
		EconomyService.Message(player, `{definition.DisplayName} upgraded to level {current.Level}!`, "Success")
		return true, nil
	elseif action == "SetTrophy" then
		-- buildingId carries the uid of the chest item to show; the item itself stays in the chest.
		if current.Id ~= "DisplayStand" then
			return false, errors.InvalidArguments
		end
		if not Validate.IsUid(buildingId) or InventoryService.GetItem(player, buildingId) == nil then
			return false, errors.InvalidArguments
		end
		current.Shown = buildingId
		EconomyService.MarkProcessed(player, requestId)
		refreshStands(base)
		return true, nil
	elseif action == "Remove" then
		local spent = 0
		for step = 1, current.Level do
			spent += definition.Levels[step].Price
		end
		local refund = math.floor(spent * BaseConfig.RemoveRefund)
		data.Buildings[slotId] = nil
		EconomyService.MarkProcessed(player, requestId)
		if refund > 0 then
			EconomyService.Earn(player, refund, `Base:Refund:{current.Id}`, requestId)
		end
		buildSlot(base, slotById(slotId), index)
		publish(player)
		return true, nil
	end
	return false, errors.InvalidArguments
end

-- Server-only (Game Pass grants): raises the chest to at least `level`. Never lowers it, never
-- touches stored items. Idempotent. Returns true when the chest is at least that level now.
function BaseService.EnsureChestLevel(player: Player, level: number): boolean
	local data = baseData(player)
	if data == nil then
		return false
	end
	local target = math.clamp(math.floor(level), 1, #BaseConfig.Chest.Levels)
	if data.ChestLevel < target then
		data.ChestLevel = target
		local base = bases[player]
		if base ~= nil then
			buildChest(base)
		end
		publish(player)
	end
	return data.ChestLevel >= target
end

---------------------------------------------------------------------------------------------
-- Startup
---------------------------------------------------------------------------------------------

function BaseService.Start()
	assert(not started, "[BaseService] Start() called twice")
	started = true

	InventoryService.SetCapacityProvider(BaseService.GetStorageCapacity)
	Conveyor.Start()

	PlotService.PlotAssigned:Connect(load)
	PlotService.PlotReleased:Connect(unload)
	Players.PlayerRemoving:Connect(unload)
	for _, player in Players:GetPlayers() do
		load(player)
	end

	InventoryService.ItemAdded:Connect(function(player: Player)
		markStandsDirty(player)
	end)
	InventoryService.ItemRemoved:Connect(function(player: Player)
		markStandsDirty(player)
	end)

	RemoteGuard.ConnectEvent(Remotes.GetEvent("BaseAction"), {
		Name = "BaseAction",
		MaxArgs = 4,
		RateLimit = GameConfig.RateLimits.BaseAction,
		Validate = function(requestId: any, action: any, slotId: any, buildingId: any): boolean
			return Validate.IsUid(requestId) and Validate.IsString(action, 1, 24)
				and (slotId == nil or Validate.IsString(slotId, 1, 8))
				and (buildingId == nil or Validate.IsString(buildingId, 1, 64))
		end,
	}, function(player: Player, requestId: string, action: string, slotId: string?, buildingId: string?)
		local ok, code = BaseService.Act(player, requestId, action, slotId, buildingId)
		if not ok and code ~= nil and MESSAGES[code] ~= nil then
			EconomyService.Message(player, MESSAGES[code], "Warning")
		end
	end)

end

return BaseService
