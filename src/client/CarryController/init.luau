--!strict
--[[
	CarryController: client view of carried junk.

	1. Visuals: small copies of the junk each player carries, on their back. Purely cosmetic
	   and local to this client. The server only publishes the Player attribute "CarryList"
	   ("uid:id,uid:id"); this module turns it into non-colliding, massless models welded to
	   the HumanoidRootPart (no physics simulation of their own).
	2. Local state: the local player's list plus which slot is selected. Selection is purely a
	   client choice; the server checks ownership again when a throw arrives.

	Nothing here can change what a player really carries.

	API (other client controllers)
	  GetLocalCarried() -> { CarriedJunk }   copy, oldest first (slot 1 = oldest)
	  GetSelectedIndex() -> number            0 when nothing is carried
	  GetSelected() -> CarriedJunk?
	  Select(index), Cycle(direction)
	  IsFull() -> boolean
	  Changed       Signal ()                         list or selection changed
	  ItemsAdded    Signal (entries: { CarriedJunk })  newly carried junk (local player)
	  ItemsRemoved  Signal (entries: { CarriedJunk })  junk that left the local list

	Tuning: VISUAL_MAX_SIZE (studs, largest dimension of one carried item), the slot layout
	in slotOffset(), and BACK_Z (how far behind the torso the stack sits).
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

ReplicatedStorage:WaitForChild("Shared")
local GameConfig = require(ReplicatedStorage.Shared.Config.GameConfig)
local JunkConfig = require(ReplicatedStorage.Shared.Config.JunkConfig)
local Types = require(ReplicatedStorage.Shared.Types)
local JunkFactory = require(ReplicatedStorage.Shared.Util.JunkFactory)
local Signal = require(ReplicatedStorage.Shared.Util.Signal)
local Validate = require(ReplicatedStorage.Shared.Util.Validate)

type CarriedJunk = Types.CarriedJunk

local LIST_ATTRIBUTE = "CarryList"
local FOLDER_NAME = "CarryVisuals"
local ROOT_NAME = "HumanoidRootPart"
local ROOT_WAIT = 10

local VISUAL_MAX_SIZE = 0.95 -- studs
local COLUMN_X = 0.55
local ROW_STEP = 0.95
local BACK_Z = 1.0 -- +Z is behind a character

local localPlayer = Players.LocalPlayer

local CarryController = {}

CarryController.Changed = Signal.new()
CarryController.ItemsAdded = Signal.new()
CarryController.ItemsRemoved = Signal.new()

local visuals: { [Player]: Folder } = {}
local trackers: { [Player]: { RBXScriptConnection } } = {}
local characterWatchers: { [Player]: RBXScriptConnection } = {}

local localList: { CarriedJunk } = {}
local selectedUid: string? = nil
local selectedIndex = 0

---------------------------------------------------------------------------------------------
-- Parsing
---------------------------------------------------------------------------------------------

-- Reads the replicated list; ignores malformed entries and never returns more than MaxJunk.
local function readList(player: Player): { CarriedJunk }
	local entries: { CarriedJunk } = {}
	local value = player:GetAttribute(LIST_ATTRIBUTE)
	if type(value) ~= "string" or value == "" then
		return entries
	end
	for _, pair in string.split(value, ",") do
		local uid, id = string.match(pair, "^([^:]+):(.+)$")
		if uid ~= nil and id ~= nil and Validate.IsUid(uid) and JunkConfig.Exists(id) then
			table.insert(entries, { Uid = uid, Id = id })
			if #entries >= GameConfig.Carry.MaxJunk then
				break
			end
		end
	end
	return entries
end

---------------------------------------------------------------------------------------------
-- Visuals on the back
---------------------------------------------------------------------------------------------

-- Slots fill left/right, then top to bottom.
local function slotOffset(index: number): Vector3
	local zeroBased = index - 1
	local column = zeroBased % 2
	local row = (zeroBased // 2) % 3
	local layer = zeroBased // 6
	local x = if column == 0 then -COLUMN_X else COLUMN_X
	return Vector3.new(x, ROW_STEP - row * ROW_STEP, BACK_Z + layer * ROW_STEP)
end

local function clearVisuals(player: Player)
	local folder: Folder? = visuals[player]
	if folder ~= nil then
		folder:Destroy()
		visuals[player] = nil
	end
end

local function refreshVisuals(player: Player)
	clearVisuals(player)

	local character = player.Character
	if character == nil then
		return
	end
	local root = character:FindFirstChild(ROOT_NAME)
	if root == nil or not root:IsA("BasePart") then
		return
	end

	local entries = readList(player)
	if #entries == 0 then
		return
	end

	local folder = Instance.new("Folder")
	folder.Name = FOLDER_NAME

	local models: { Model } = {}
	for index, entry in entries do
		local model = JunkFactory.Build(entry.Id, "Cosmetic", VISUAL_MAX_SIZE)
		if model ~= nil then
			model:PivotTo(root.CFrame * CFrame.new(slotOffset(index)))
			model.Parent = folder
			table.insert(models, model)
		end
	end

	folder.Parent = character
	visuals[player] = folder

	-- Weld after the models are inside the character so the weld offsets are final.
	for _, model in models do
		local junkRoot = JunkFactory.GetRoot(model)
		if junkRoot ~= nil then
			local weld = Instance.new("WeldConstraint")
			weld.Part0 = root
			weld.Part1 = junkRoot
			weld.Parent = junkRoot
		end
	end
end

---------------------------------------------------------------------------------------------
-- Local state and selection
---------------------------------------------------------------------------------------------

local function indexOfUid(list: { CarriedJunk }, uid: string?): number
	if uid == nil then
		return 0
	end
	for index, entry in list do
		if entry.Uid == uid then
			return index
		end
	end
	return 0
end

local function setSelection(index: number)
	if #localList == 0 then
		selectedIndex = 0
		selectedUid = nil
	else
		selectedIndex = math.clamp(index, 1, #localList)
		selectedUid = localList[selectedIndex].Uid
	end
end

local function updateLocalState()
	local previous = localList
	local nextList = readList(localPlayer)

	local previousUids: { [string]: boolean } = {}
	for _, entry in previous do
		previousUids[entry.Uid] = true
	end
	local nextUids: { [string]: boolean } = {}
	local added: { CarriedJunk } = {}
	for _, entry in nextList do
		nextUids[entry.Uid] = true
		if not previousUids[entry.Uid] then
			table.insert(added, entry)
		end
	end
	local removed: { CarriedJunk } = {}
	for _, entry in previous do
		if not nextUids[entry.Uid] then
			table.insert(removed, entry)
		end
	end

	local oldIndex = selectedIndex
	localList = nextList

	local kept = indexOfUid(localList, selectedUid)
	if kept > 0 then
		setSelection(kept) -- the selected junk is still carried: keep it selected
	elseif oldIndex == 0 then
		setSelection(#localList) -- nothing was selected: select the newest
	else
		setSelection(oldIndex) -- the selected junk left: stay on the same slot (clamped)
	end

	if #removed > 0 then
		CarryController.ItemsRemoved:Fire(removed)
	end
	if #added > 0 then
		CarryController.ItemsAdded:Fire(added)
	end
	CarryController.Changed:Fire()
end

function CarryController.GetLocalCarried(): { CarriedJunk }
	local copy: { CarriedJunk } = {}
	for index, entry in localList do
		copy[index] = { Uid = entry.Uid, Id = entry.Id }
	end
	return copy
end

function CarryController.GetSelectedIndex(): number
	return selectedIndex
end

function CarryController.GetSelected(): CarriedJunk?
	local entry = localList[selectedIndex]
	if entry == nil then
		return nil
	end
	return { Uid = entry.Uid, Id = entry.Id }
end

function CarryController.Select(index: number)
	if index < 1 or index > #localList or index == selectedIndex then
		return
	end
	setSelection(index)
	CarryController.Changed:Fire()
end

-- direction: 1 = next slot, -1 = previous slot (wraps around).
function CarryController.Cycle(direction: number)
	local count = #localList
	if count < 2 then
		return
	end
	local index = ((selectedIndex - 1 + direction) % count) + 1
	CarryController.Select(index)
end

function CarryController.IsFull(): boolean
	return #localList >= GameConfig.Carry.MaxJunk
end

---------------------------------------------------------------------------------------------
-- Player tracking
---------------------------------------------------------------------------------------------

local function onCharacter(player: Player, character: Model)
	-- The root part can arrive after the character itself (and again after streaming).
	if character:WaitForChild(ROOT_NAME, ROOT_WAIT) ~= nil and player.Character == character then
		refreshVisuals(player)
	end
end

local function untrack(player: Player)
	local connections = trackers[player]
	if connections ~= nil then
		for _, connection in connections do
			connection:Disconnect()
		end
		trackers[player] = nil
	end
	local watcher: RBXScriptConnection? = characterWatchers[player]
	if watcher ~= nil then
		watcher:Disconnect()
		characterWatchers[player] = nil
	end
	clearVisuals(player)
end

local function track(player: Player)
	if trackers[player] ~= nil then
		return
	end

	local connections: { RBXScriptConnection } = {}

	local function watchCharacter(character: Model)
		local previous: RBXScriptConnection? = characterWatchers[player]
		if previous ~= nil then
			previous:Disconnect()
		end
		-- With StreamingEnabled a distant character's root can stream out and back in.
		characterWatchers[player] = character.ChildAdded:Connect(function(child: Instance)
			if child.Name == ROOT_NAME and player.Character == character then
				refreshVisuals(player)
			end
		end)
		task.spawn(onCharacter, player, character)
	end

	table.insert(
		connections,
		player:GetAttributeChangedSignal(LIST_ATTRIBUTE):Connect(function()
			refreshVisuals(player)
			if player == localPlayer then
				updateLocalState()
			end
		end)
	)
	table.insert(connections, player.CharacterAdded:Connect(watchCharacter))
	table.insert(
		connections,
		player.CharacterRemoving:Connect(function()
			clearVisuals(player)
		end)
	)
	trackers[player] = connections

	if player.Character ~= nil then
		watchCharacter(player.Character)
	end
	if player == localPlayer then
		updateLocalState()
	end
end

function CarryController.Start()
	Players.PlayerAdded:Connect(track)
	Players.PlayerRemoving:Connect(untrack)
	for _, player in Players:GetPlayers() do
		track(player)
	end
end

return CarryController
