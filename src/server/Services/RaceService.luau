--!strict
--[[
	RaceService: the hourly race at the JUNKSHOT RACEWAY (map: tools/map/RaceZone, found by tags).

	  Idle       nothing; Workspace attribute RaceStartsAt = the next full hour
	  Open       OpenBefore seconds before it: players join at the pad (they need a placed vehicle)
	  Countdown  their vehicles are put on the grid with them in the seat, frozen; 3-2-1-GO
	  Racing     checkpoints in order, Laps rounds; the server measures everything
	  Results    prizes, records; vehicles go back to where they were placed

	The client sends nothing here: joining is a ProximityPrompt and driving is the existing
	VehicleInput. Progress is decided from the vehicle's position on the server (which also
	simulates it), so times, laps and places cannot be faked.
	A racer is out (DNF) when they leave, stay out of the seat for ExitGrace seconds or their
	vehicle is gone. Saved: profile.Data.Racing = { BestMs, Races, Wins } and, on a new personal
	best only, the OrderedDataStore of the all-time board.

	Attributes for clients: Workspace RaceState, RaceStartsAt, RaceGoAt, RaceRacers, RaceLaps;
	player RaceJoined, RaceLap, RaceNext (checkpoint index), RacePlace.
]]

local CollectionService = game:GetService("CollectionService")
local DataStoreService = game:GetService("DataStoreService")
local HttpService = game:GetService("HttpService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local GameConfig = require(ReplicatedStorage.Shared.Config.GameConfig)
local Signal = require(ReplicatedStorage.Shared.Util.Signal)
local RaceConfig = require(ReplicatedStorage.Shared.Config.RaceConfig)
local Remotes = require(ReplicatedStorage.Shared.Remotes)

local CarryService = require(script.Parent.CarryService)
local DataService = require(script.Parent.DataService)
local EconomyService = require(script.Parent.EconomyService)
local PlacementService = require(script.Parent.PlacementService)
local Vehicle = require(script.Parent.Behaviors.Vehicle)

local RaceService = {}

export type Racer = {
	Player: Player,
	Entry: any,
	Home: CFrame,
	Lap: number,
	Next: number, -- index of the checkpoint to reach
	Passed: number, -- checkpoints reached in total (for the places)
	TimeMs: number?, -- finished
	Out: boolean,
	SeatlessSince: number?,
}

RaceService.Finished = Signal.new() -- (player) crossed the finish line

local started = false
local state = "Idle"
local joined: { Player } = {}
local racers: { Racer } = {}
local store: OrderedDataStore? = nil
local names: { [number]: string } = {}

local function announce(text: string, kind: string)
	Remotes.GetEvent("Notify"):FireAllClients(text, kind)
end

local function setState(value: string)
	state = value
	Workspace:SetAttribute("RaceState", value)
end

local function checkpoints(): { [number]: BasePart }
	local list: { [number]: BasePart } = {}
	for _, part in CollectionService:GetTagged("RaceCheckpoint") do
		local index = part:GetAttribute("Index")
		if part:IsA("BasePart") and type(index) == "number" then
			list[index] = part
		end
	end
	return list
end

local function gridSlot(slot: number): CFrame?
	for _, part in CollectionService:GetTagged("RaceGrid") do
		if part:IsA("BasePart") and part:GetAttribute("Slot") == slot then
			return part.CFrame
		end
	end
	return nil
end

function RaceService.GetState(): string
	return state
end

function RaceService.GetRacers(): { Racer }
	return racers
end

-- The vehicle a player would race with: the one they drive, else any placed one.
function RaceService.FindVehicle(player: Player): any?
	local driven = Vehicle.GetDriven(player)
	if driven ~= nil and driven.Owner == player then
		return driven
	end
	for _, entry in PlacementService.GetEntries(player) do
		if entry.Kind == "Vehicle" then
			return entry
		end
	end
	return nil
end

function RaceService.SpeedFor(maxSpeed: number): number
	return RaceConfig.BaseSpeed + (maxSpeed - RaceConfig.BaseSpeed) * RaceConfig.SpeedShare
end

---------------------------------------------------------------------------------------------
-- Joining
---------------------------------------------------------------------------------------------

local function publishJoined()
	Workspace:SetAttribute("RaceRacers", #joined)
end

function RaceService.Join(player: Player): (boolean, string?)
	if state ~= "Open" then
		return false, "Closed"
	end
	if table.find(joined, player) ~= nil then
		return false, "AlreadyJoined"
	end
	if #joined >= RaceConfig.MaxRacers then
		return false, "Full"
	end
	if CarryService.GetLiveRoot(player) == nil then
		return false, "NoCharacter"
	end
	if RaceService.FindVehicle(player) == nil then
		return false, "NoVehicle"
	end
	table.insert(joined, player)
	player:SetAttribute("RaceJoined", true)
	publishJoined()
	return true, nil
end

function RaceService.Leave(player: Player)
	local index = table.find(joined, player)
	if index ~= nil then
		table.remove(joined, index)
		publishJoined()
	end
	player:SetAttribute("RaceJoined", nil)
end

local MESSAGES: { [string]: string } = {
	Closed = "The race is not open - it starts every full hour",
	Full = "The race is full",
	NoVehicle = "You need a placed vehicle (a bicycle is enough!)",
}

local function onJoinPrompt(player: Player, pad: BasePart)
	local root = CarryService.GetLiveRoot(player)
	if root == nil or (root.Position - pad.Position).Magnitude > RaceConfig.JoinDistance then
		return
	end
	if table.find(joined, player) ~= nil and state == "Open" then
		RaceService.Leave(player)
		EconomyService.Message(player, "You left the race", "Info")
		return
	end
	local ok, code = RaceService.Join(player)
	if ok then
		EconomyService.Message(player, "You are in the race! Your vehicle will be put on the grid.", "Success")
	elseif code ~= nil and MESSAGES[code] ~= nil then
		EconomyService.Message(player, MESSAGES[code], "Warning")
	end
end

---------------------------------------------------------------------------------------------
-- Progress
---------------------------------------------------------------------------------------------

-- Advances one racer from a position. Returns true when they just finished.
-- Only the NEXT checkpoint counts, so skipping or driving backwards gives nothing.
function RaceService.Advance(racer: Racer, position: Vector3, points: { [number]: BasePart }, elapsedMs: number): boolean
	if racer.Out or racer.TimeMs ~= nil then
		return false
	end
	local point = points[racer.Next]
	if point == nil then
		return false
	end
	local p = point.CFrame:PointToObjectSpace(position)
	if math.abs(p.X) > point.Size.X / 2 + RaceConfig.CheckpointMargin or math.abs(p.Z) > RaceConfig.CheckpointDepth
		or math.abs(p.Y) > point.Size.Y
	then
		return false
	end
	racer.Passed += 1
	local crossedLine = racer.Next == 0
	racer.Next = if points[racer.Next + 1] ~= nil then racer.Next + 1 else 0
	if crossedLine then
		if racer.Lap >= RaceConfig.Laps then
			racer.TimeMs = math.floor(elapsedMs)
			return true
		end
		racer.Lap += 1
	end
	return false
end

local function progressKey(racer: Racer, points: { [number]: BasePart }): number
	local point = points[racer.Next]
	local base = racer.Entry.Model.PrimaryPart
	local distance = if point ~= nil and base ~= nil then (point.Position - base.Position).Magnitude else 0
	return racer.Passed * 10000 - distance
end

-- Finished (by time) first, then by progress, then those who are out.
function RaceService.Order(list: { Racer }, points: { [number]: BasePart }): { Racer }
	local sorted = table.clone(list)
	table.sort(sorted, function(a, b)
		if (a.TimeMs ~= nil) ~= (b.TimeMs ~= nil) then
			return a.TimeMs ~= nil
		end
		if a.TimeMs ~= nil and b.TimeMs ~= nil then
			return a.TimeMs < b.TimeMs
		end
		if a.Out ~= b.Out then
			return b.Out
		end
		return progressKey(a, points) > progressKey(b, points)
	end)
	return sorted
end

function RaceService.PrizeFor(place: number, startCount: number): number
	if startCount < RaceConfig.MinForPrizes then
		return RaceConfig.SoloReward
	end
	return RaceConfig.Prizes[place] or RaceConfig.FinisherReward
end

---------------------------------------------------------------------------------------------
-- Records
---------------------------------------------------------------------------------------------

local function formatMs(ms: number): string
	local seconds = ms / 1000
	return string.format("%d:%05.2f", seconds // 60, seconds % 60)
end

local function nameOf(userId: number): string
	local cached = names[userId]
	if cached ~= nil then
		return cached
	end
	local ok, name = pcall(Players.GetNameFromUserIdAsync, Players, userId)
	names[userId] = if ok and type(name) == "string" then name else `Player {userId}`
	return names[userId]
end

local function refreshBoard()
	local face = CollectionService:GetTagged("RaceBoard")[1]
	local subtitle = if face ~= nil then face:FindFirstChild("Subtitle", true) else nil
	local title = if face ~= nil then face:FindFirstChild("Title", true) else nil
	if subtitle == nil or title == nil or not subtitle:IsA("TextLabel") or not title:IsA("TextLabel") then
		return
	end
	title.Size = UDim2.fromScale(0.92, 0.22)
	subtitle.Position = UDim2.fromScale(0.04, 0.3)
	subtitle.Size = UDim2.fromScale(0.92, 0.64)
	local lines: { string } = {}
	local current = store
	if current ~= nil then
		local ok, pages = pcall(function()
			return current:GetSortedAsync(true, RaceConfig.BoardSize)
		end)
		if ok and pages ~= nil then
			for rank, record in (pages :: any):GetCurrentPage() do
				local userId = tonumber(record.key)
				if userId ~= nil then
					table.insert(lines, `{rank}. {nameOf(userId)}  {formatMs(record.value)}`)
				end
			end
		end
	end
	subtitle.Text = if #lines > 0 then table.concat(lines, "\n") else "No records yet"
end

-- Saves a validated finish. Returns true when it is a new personal best.
function RaceService.SaveResult(player: Player, timeMs: number, won: boolean): boolean
	local data = DataService.GetData(player) :: any
	if data == nil then
		return false
	end
	if type(data.Racing) ~= "table" then
		data.Racing = { BestMs = 0, Races = 0, Wins = 0 }
	end
	local racing = data.Racing
	racing.Races += 1
	racing.Wins += if won then 1 else 0
	local best = racing.BestMs <= 0 or timeMs < racing.BestMs
	if best then
		racing.BestMs = timeMs
		player:SetAttribute("RaceBestMs", timeMs)
		local current = store
		if current ~= nil then
			task.spawn(function()
				pcall(function()
					current:SetAsync(tostring(player.UserId), timeMs)
				end)
				refreshBoard()
			end)
		end
	end
	return best
end

---------------------------------------------------------------------------------------------
-- The race
---------------------------------------------------------------------------------------------

local function release(racer: Racer)
	local player, entry = racer.Player, racer.Entry
	player:SetAttribute("RaceLap", nil)
	player:SetAttribute("RaceNext", nil)
	player:SetAttribute("RacePlace", nil)
	player:SetAttribute("RaceJoined", nil)
	if PlacementService.GetEntry(entry.Uid) ~= entry then
		return -- already gone
	end
	Vehicle.SetRace(entry, nil)
	Vehicle.Eject(entry)
	task.wait(0.3)
	if PlacementService.GetEntry(entry.Uid) == entry then
		Vehicle.MoveTo(entry, racer.Home)
	end
	local character = player.Character
	if player.Parent == Players and character ~= nil and CarryService.GetLiveRoot(player) ~= nil then
		character:PivotTo(CFrame.new(RaceConfig.ExitSpot + Vector3.new(math.random(-8, 8), 0, math.random(-4, 4))))
	end
end

local function leaveRace(racer: Racer, text: string)
	racer.Out = true
	if racer.Player.Parent == Players then
		EconomyService.Message(racer.Player, text, "Warning")
	end
	task.spawn(release, racer)
end

local function lineUp()
	racers = {}
	for _, player in joined do
		local entry = if player.Parent == Players and CarryService.GetLiveRoot(player) ~= nil then RaceService.FindVehicle(player) else nil
		local slot = if entry ~= nil then gridSlot(#racers + 1) else nil
		if entry == nil or slot == nil then
			player:SetAttribute("RaceJoined", nil)
			continue
		end
		local racer: Racer = {
			Player = player,
			Entry = entry,
			Home = entry.Model:GetPivot(),
			Lap = 1,
			Next = 1,
			Passed = 0,
			TimeMs = nil,
			Out = false,
			SeatlessSince = nil,
		}
		table.insert(racers, racer)
		Vehicle.SetRace(entry, { MaxSpeed = RaceService.SpeedFor(entry.Behavior.Vehicle.MaxSpeed), Frozen = true })
		Vehicle.MoveTo(entry, CFrame.new(slot.Position + Vector3.new(0, 0.3, 0)) * slot.Rotation)
		task.spawn(Vehicle.Seat, entry)
		player:SetAttribute("RaceLap", 1)
		player:SetAttribute("RaceNext", 1)
	end
	joined = {}
	publishJoined()
end

local function finishRewards(points: { [number]: BasePart }, startCount: number)
	local place = 0
	for _, racer in RaceService.Order(racers, points) do
		local player = racer.Player
		if racer.TimeMs == nil or player.Parent ~= Players then
			continue
		end
		place += 1
		local prize = RaceService.PrizeFor(place, startCount)
		RaceService.Finished:Fire(player)
		local best = RaceService.SaveResult(player, racer.TimeMs, place == 1 and startCount >= RaceConfig.MinForPrizes)
		if best then
			prize += RaceConfig.RecordBonus
		end
		EconomyService.Earn(player, prize, "Race", HttpService:GenerateGUID(false))
		EconomyService.Message(player, `Place {place}: {formatMs(racer.TimeMs)} - you won {prize}!`
			.. (if best then " New personal best!" else ""), "Success")
		if place == 1 then
			announce(`🏁 {player.DisplayName} won the race in {formatMs(racer.TimeMs)}!`, "Success")
		end
	end
	if place == 0 then
		announce("🏁 Nobody finished the race", "Info")
	end
end

-- Runs one race with the players who joined. Yields until it is over.
function RaceService.Run()
	setState("Countdown")
	lineUp()
	local points = checkpoints()
	if #racers == 0 or points[0] == nil then
		setState("Idle")
		return
	end
	local startCount = #racers
	local goAt = Workspace:GetServerTimeNow() + RaceConfig.Countdown
	Workspace:SetAttribute("RaceGoAt", goAt)
	while Workspace:GetServerTimeNow() < goAt do
		task.wait(0.05)
	end
	for _, racer in racers do
		if PlacementService.GetEntry(racer.Entry.Uid) == racer.Entry then
			Vehicle.SetRace(racer.Entry, { MaxSpeed = RaceService.SpeedFor(racer.Entry.Behavior.Vehicle.MaxSpeed), Frozen = false })
		end
	end
	setState("Racing")

	local endsAt = goAt + RaceConfig.TimeLimit
	while true do
		task.wait(RaceConfig.Step)
		local now = Workspace:GetServerTimeNow()
		local active = 0
		for _, racer in racers do
			if racer.Out or racer.TimeMs ~= nil then
				continue
			end
			local base = racer.Entry.Model.PrimaryPart
			if racer.Player.Parent ~= Players or base == nil or PlacementService.GetEntry(racer.Entry.Uid) ~= racer.Entry then
				leaveRace(racer, "Your vehicle is gone - you are out of the race")
				continue
			end
			if Vehicle.GetDriven(racer.Player) ~= racer.Entry then
				racer.SeatlessSince = racer.SeatlessSince or now
				if now - racer.SeatlessSince > RaceConfig.ExitGrace then
					leaveRace(racer, "You left your vehicle - you are out of the race")
					continue
				end
			else
				racer.SeatlessSince = nil
				if RaceService.Advance(racer, base.Position, points, (now - goAt) * 1000) then
					Vehicle.SetRace(racer.Entry, { MaxSpeed = 20, Frozen = true })
					EconomyService.Message(racer.Player, "Finished! Waiting for the others...", "Success")
					endsAt = math.min(endsAt, now + RaceConfig.AfterFirst)
				end
				racer.Player:SetAttribute("RaceLap", math.min(racer.Lap, RaceConfig.Laps))
				racer.Player:SetAttribute("RaceNext", if racer.TimeMs == nil then racer.Next else nil)
			end
			if racer.TimeMs == nil then
				active += 1
			end
		end
		for place, racer in RaceService.Order(racers, points) do
			if racer.Player.Parent == Players and not racer.Out then
				racer.Player:SetAttribute("RacePlace", place)
			end
		end
		if active == 0 or now >= endsAt then
			break
		end
	end

	setState("Results")
	finishRewards(points, startCount)
	task.wait(RaceConfig.ResultSeconds)
	for _, racer in racers do
		if not racer.Out then
			task.spawn(release, racer)
		end
	end
	racers = {}
	setState("Idle")
end

-- Opens joining now and starts after `seconds` (also used by the Studio debug bridge).
function RaceService.Open(seconds: number)
	if state ~= "Idle" then
		return
	end
	joined = {}
	publishJoined()
	Workspace:SetAttribute("RaceStartsAt", Workspace:GetServerTimeNow() + seconds)
	setState("Open")
	announce(`🏁 Race in {math.ceil(seconds / 60)} min! Join at the JUNKSHOT RACEWAY with your vehicle`, "Info")
	task.wait(seconds)
	local ok, err = pcall(RaceService.Run)
	if not ok then
		warn(`[RaceService] race failed: {tostring(err)}`)
		for _, racer in racers do
			task.spawn(release, racer)
		end
		racers = {}
		setState("Idle")
	end
end

-- Big board over the plaza (tag RaceTimerBoard). Clients write it (countdown every second) and
-- turn its pages on a click (client RaceController).
local function buildTimerBoard()
	local site = CollectionService:GetTagged("RecyclerSite")[1]
	local y = if site ~= nil and site:IsA("BasePart") then site.Position.Y - site.Size.Y / 2 else 0.4
	local model = Instance.new("Model")
	model.Name = "RaceTimer"
	local function part(name: string, size: Vector3, position: Vector3, color: Color3): Part
		local p = Instance.new("Part")
		p.Name = name
		p.Size = size
		p.Position = Vector3.new(0, y, 16) + position
		p.Color = color
		p.Material = Enum.Material.SmoothPlastic
		p.Anchored = true
		p.CastShadow = false
		p.TopSurface = Enum.SurfaceType.Smooth
		p.BottomSurface = Enum.SurfaceType.Smooth
		p.Parent = model
		return p
	end
	local ink, red, white = Color3.fromRGB(28, 36, 60), Color3.fromRGB(236, 74, 70), Color3.fromRGB(245, 248, 255)
	for _, x in { -14, 14 } do
		part("Post", Vector3.new(1.2, 26, 1.2), Vector3.new(x, 13, 0), Color3.fromRGB(150, 160, 180))
		part("PostFoot", Vector3.new(3, 1, 3), Vector3.new(x, 0.5, 0), ink)
	end
	local board = part("Board", Vector3.new(28, 10, 0.8), Vector3.new(0, 21, 0), ink)
	for index = 0, 13 do
		part("Check", Vector3.new(2, 1, 0.9), Vector3.new(-13 + index * 2, 26.5, 0), if index % 2 == 0 then white else red)
	end
	local click = Instance.new("ClickDetector")
	click.MaxActivationDistance = 120
	click.Parent = board
	for _, face in { Enum.NormalId.Front, Enum.NormalId.Back } do
		local gui = Instance.new("SurfaceGui")
		gui.Name = face.Name
		gui.Face = face
		gui.CanvasSize = Vector2.new(840, 300)
		gui.LightInfluence = 0
		local function label(name: string, position: UDim2, size: UDim2, color: Color3)
			local text = Instance.new("TextLabel")
			text.Name = name
			text.Position = position
			text.Size = size
			text.BackgroundTransparency = 1
			text.Font = Enum.Font.FredokaOne
			text.TextColor3 = color
			text.TextScaled = true
			text.Text = ""
			text.Parent = gui
		end
		label("Title", UDim2.fromScale(0.04, 0.04), UDim2.fromScale(0.92, 0.22), Color3.fromRGB(255, 210, 60))
		label("Main", UDim2.fromScale(0.04, 0.27), UDim2.fromScale(0.92, 0.46), white)
		label("Note", UDim2.fromScale(0.04, 0.77), UDim2.fromScale(0.92, 0.18), Color3.fromRGB(150, 200, 255))
		gui.Parent = board
	end
	board:AddTag("RaceTimerBoard")
	model.Parent = Workspace
end

function RaceService.Start()
	assert(not started, "[RaceService] Start() called twice")
	started = true
	setState("Idle")
	publishJoined()
	buildTimerBoard()
	local function publishBest(player: Player)
		local data = DataService.GetData(player) :: any
		local best = if data ~= nil and type(data.Racing) == "table" then data.Racing.BestMs else 0
		if type(best) == "number" and best > 0 then
			player:SetAttribute("RaceBestMs", best)
		end
	end
	DataService.PlayerLoaded:Connect(publishBest)
	Workspace:SetAttribute("RaceLaps", RaceConfig.Laps)

	-- DevTests never write real records.
	local tests = RunService:IsStudio() and (GameConfig.Debug.UseMockStore
		or game:GetService("ServerScriptService"):GetAttribute("TestStore") == true
		or game:GetService("ServerScriptService"):GetAttribute("RunDevTests") == true)
	if not tests then
		local ok, result = pcall(DataStoreService.GetOrderedDataStore, DataStoreService, "RaceBest_v1")
		if ok then
			store = result
		end
	end

	for _, pad in CollectionService:GetTagged("RaceLobby") do
		if pad:IsA("BasePart") then
			local prompt = Instance.new("ProximityPrompt")
			prompt.Name = "RacePrompt"
			prompt.ActionText = "Join / leave"
			prompt.ObjectText = "Hourly race"
			prompt.KeyboardKeyCode = GameConfig.Input.MachineKey
			prompt.GamepadKeyCode = GameConfig.Input.MachineGamepadKey
			prompt.HoldDuration = 0
			prompt.RequiresLineOfSight = false
			prompt.MaxActivationDistance = 12
			prompt.Style = Enum.ProximityPromptStyle.Custom
			prompt:SetAttribute("PromptKind", "Race")
			prompt.Parent = pad
			prompt.Triggered:Connect(function(player: Player)
				onJoinPrompt(player, pad)
			end)
		end
	end
	Players.PlayerRemoving:Connect(function(player: Player)
		RaceService.Leave(player)
	end)

	task.spawn(refreshBoard)
	task.spawn(function()
		while true do
			local now = Workspace:GetServerTimeNow()
			local startsAt = (math.floor(now / RaceConfig.Interval) + 1) * RaceConfig.Interval
			if startsAt - now < 30 then
				startsAt += RaceConfig.Interval -- a server that just started skips this one
			end
			if state == "Idle" then
				Workspace:SetAttribute("RaceStartsAt", startsAt)
			end
			task.wait(math.max(1, startsAt - RaceConfig.OpenBefore - now))
			RaceService.Open(math.max(1, startsAt - Workspace:GetServerTimeNow()))
			task.wait(5)
		end
	end)
end

return RaceService
