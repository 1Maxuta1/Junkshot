--!strict
--[[
	LeaderboardService: who is the richest.

	  leaderstats   every player gets "Klunks" and "Level" in Roblox's player list (this server,
	                live, sorted by Roblox).
	  Server board  a board on the plaza: the richest players on THIS server (up to 8), updated
	                a moment after any balance changes.
	  Global board  the richest players of the whole game, from an OrderedDataStore
	                ("RichestPlayers"). Balances are written every GlobalWriteSeconds and when a
	                player leaves; the top list is read every GlobalReadSeconds. All DataStore
	                calls are pcall-ed; failures only delay the board. Where DataStores are not
	                available (Studio without API access) the board says so.
	Ranked by the current balance (Klunks). Names are cached per user id.
]]

local DataStoreService = game:GetService("DataStoreService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local GameConfig = require(ReplicatedStorage.Shared.Config.GameConfig)
local KlunksFormat = require(ReplicatedStorage.Shared.Util.KlunksFormat)

local CurrencyService = require(script.Parent.CurrencyService)
local DataService = require(script.Parent.DataService)

local LeaderboardService = {}

local STORE_NAME = "RichestPlayers_v1"
local GLOBAL_WRITE_SECONDS = 120
local GLOBAL_READ_SECONDS = 120
local GLOBAL_SIZE = 10
local SERVER_SIZE = 8
local BOARD_POSITIONS = {
	Server = CFrame.new(-17, 0, 6) * CFrame.Angles(0, math.rad(200), 0),
	Global = CFrame.new(17, 0, 6) * CFrame.Angles(0, math.rad(160), 0),
}

local started = false
local store: OrderedDataStore? = nil
local names: { [number]: string } = {}
local rowsOf: { [string]: { TextLabel } } = {}
local footerOf: { [string]: TextLabel } = {}
local serverDirty = false

local function nameOf(userId: number): string
	local cached = names[userId]
	if cached ~= nil then
		return cached
	end
	local player = Players:GetPlayerByUserId(userId)
	if player ~= nil then
		names[userId] = player.DisplayName
		return player.DisplayName
	end
	local ok, name = pcall(Players.GetNameFromUserIdAsync, Players, userId)
	local result = if ok and type(name) == "string" then name else `Player {userId}`
	names[userId] = result
	return result
end

local function buildBoard(key: string, title: string, rowCount: number)
	-- Next to the Scrap Dealer on the plaza (the map's "RecyclerSite" marker).
	local site = game:GetService("CollectionService"):GetTagged("RecyclerSite")[1]
	local ground = if site ~= nil and site:IsA("BasePart")
		then CFrame.new(site.Position.X, site.Position.Y - site.Size.Y / 2, site.Position.Z)
		else CFrame.new(0, 0.4, 0)
	local model = Instance.new("Model")
	model.Name = `Leaderboard{key}`
	local function part(name: string, size: Vector3, cframe: CFrame, color: Color3, material: Enum.Material?): Part
		local p = Instance.new("Part")
		p.Name = name
		p.Size = size
		p.CFrame = cframe
		p.Color = color
		p.Material = material or Enum.Material.SmoothPlastic
		p.Anchored = true
		p.Parent = model
		return p
	end
	local base = ground * BOARD_POSITIONS[key]
	for _, x in { -4.2, 4.2 } do
		part("Leg", Vector3.new(0.6, 6, 0.6), base * CFrame.new(x, 3, 0), Color3.fromRGB(40, 44, 64), Enum.Material.Metal)
	end
	local board = part("Board", Vector3.new(9.4, 8.6, 0.5), base * CFrame.new(0, 9.6, 0), Color3.fromRGB(24, 44, 86))
	part("Frame", Vector3.new(10, 9.2, 0.35), base * CFrame.new(0, 9.6, 0), Color3.fromRGB(255, 205, 50))
	for _, x in { -4.2, 4.2 } do
		part("Foot", Vector3.new(1.8, 0.8, 1.8), base * CFrame.new(x, 0.4, 0), Color3.fromRGB(28, 36, 60))
	end
	part("Snow", Vector3.new(9.8, 0.4, 0.9), base * CFrame.new(0, 14.1, 0), Color3.fromRGB(250, 252, 255), Enum.Material.Snow)
	local rows: { TextLabel } = {}
	for _, face in { Enum.NormalId.Front, Enum.NormalId.Back } do
		local gui = Instance.new("SurfaceGui")
		gui.Face = face
		gui.CanvasSize = Vector2.new(470, 430)
		gui.LightInfluence = 0
		gui.Parent = board
		local header = Instance.new("TextLabel")
		header.Size = UDim2.new(1, 0, 0, 60)
		header.BackgroundTransparency = 1
		header.Font = Enum.Font.FredokaOne
		header.Text = title
		header.TextColor3 = Color3.fromRGB(255, 205, 50)
		header.TextScaled = true
		header.Parent = gui
		for index = 1, rowCount do
			local row = Instance.new("TextLabel")
			row.Name = `Row{index}`
			row.Position = UDim2.new(0, 16, 0, 64 + (index - 1) * 34)
			row.Size = UDim2.new(1, -32, 0, 30)
			row.BackgroundTransparency = 1
			row.Font = Enum.Font.GothamBold
			row.Text = ""
			row.TextColor3 = if index <= 3 then Color3.fromRGB(255, 236, 170) else Color3.fromRGB(230, 238, 255)
			row.TextScaled = true
			row.TextXAlignment = Enum.TextXAlignment.Left
			row.Parent = gui
			table.insert(rows, row)
		end
		local footer = Instance.new("TextLabel")
		footer.Name = "Footer"
		footer.Position = UDim2.new(0, 0, 1, -26)
		footer.Size = UDim2.new(1, 0, 0, 22)
		footer.BackgroundTransparency = 1
		footer.Font = Enum.Font.Gotham
		footer.Text = ""
		footer.TextColor3 = Color3.fromRGB(160, 178, 220)
		footer.TextScaled = true
		footer.Parent = gui
		footerOf[key .. tostring(face)] = footer
	end
	model.Parent = Workspace
	rowsOf[key] = rows
end

local function setRows(key: string, lines: { string }, footer: string?)
	local rows = rowsOf[key]
	if rows == nil then
		return
	end
	local perFace = #rows // 2
	for index, row in rows do
		local line = lines[((index - 1) % perFace) + 1]
		row.Text = line or ""
	end
	for name, label in footerOf do
		if string.sub(name, 1, #key) == key then
			label.Text = footer or ""
		end
	end
end

local function line(rank: number, name: string, amount: number): string
	return `{rank}. {name}  ·  {KlunksFormat.Format(amount)}`
end

local function refreshServer()
	serverDirty = false
	local list = {}
	for _, player in Players:GetPlayers() do
		local klunks = CurrencyService.GetKlunks(player)
		if klunks ~= nil then
			table.insert(list, { Name = player.DisplayName, Klunks = klunks })
		end
	end
	table.sort(list, function(a, b)
		return a.Klunks > b.Klunks
	end)
	local lines = {}
	for index = 1, math.min(SERVER_SIZE, #list) do
		table.insert(lines, line(index, list[index].Name, list[index].Klunks))
	end
	setRows("Server", lines, "This server - live")
end

local function markServerDirty()
	if serverDirty then
		return
	end
	serverDirty = true
	task.delay(2, refreshServer)
end

local function writeBalance(player: Player)
	local current = store
	local klunks = CurrencyService.GetKlunks(player)
	if current == nil or klunks == nil then
		return
	end
	pcall(function()
		current:SetAsync(tostring(player.UserId), math.floor(klunks))
	end)
end

local function readGlobal()
	local current = store
	if current == nil then
		setRows("Global", {}, "Appears in the published game")
		return
	end
	local ok, pages = pcall(function()
		return current:GetSortedAsync(false, GLOBAL_SIZE)
	end)
	if not ok or pages == nil then
		setRows("Global", {}, "Updating soon...")
		return
	end
	local lines = {}
	for index, entry in (pages :: any):GetCurrentPage() do
		local userId = tonumber(entry.key)
		if userId ~= nil then
			table.insert(lines, line(index, nameOf(userId), entry.value))
		end
	end
	setRows("Global", lines, "All servers - every 2 minutes")
end

local function setupLeaderstats(player: Player)
	if player:FindFirstChild("leaderstats") ~= nil then
		return
	end
	local stats = Instance.new("Folder")
	stats.Name = "leaderstats"
	local klunks = Instance.new("IntValue")
	klunks.Name = GameConfig.Klunks.Name
	klunks.Value = CurrencyService.GetKlunks(player) or 0
	klunks.Parent = stats
	local level = Instance.new("IntValue")
	level.Name = "Level"
	level.Value = player:GetAttribute("Level") or 1
	level.Parent = stats
	player:GetAttributeChangedSignal("Level"):Connect(function()
		level.Value = player:GetAttribute("Level") or 1
	end)
	stats.Parent = player
	markServerDirty()
end

function LeaderboardService.Start()
	assert(not started, "[LeaderboardService] Start() called twice")
	started = true

	local ok, result = pcall(DataStoreService.GetOrderedDataStore, DataStoreService, STORE_NAME)
	local tests = game:GetService("RunService"):IsStudio() and (GameConfig.Debug.UseMockStore
		or game:GetService("ServerScriptService"):GetAttribute("TestStore") == true
		or game:GetService("ServerScriptService"):GetAttribute("RunDevTests") == true) -- never write test balances
	if ok and not tests then
		store = result
	end

	buildBoard("Server", "RICHEST HERE", SERVER_SIZE)
	buildBoard("Global", "RICHEST EVER", GLOBAL_SIZE)

	CurrencyService.Changed:Connect(function(player: Player, balance: number)
		local stats = player:FindFirstChild("leaderstats")
		local value = if stats ~= nil then stats:FindFirstChild(GameConfig.Klunks.Name) else nil
		if value ~= nil and value:IsA("IntValue") then
			value.Value = math.floor(balance)
		end
		markServerDirty()
	end)
	DataService.PlayerLoaded:Connect(setupLeaderstats)
	for _, player in Players:GetPlayers() do
		if DataService.IsLoaded(player) then
			setupLeaderstats(player)
		end
	end
	Players.PlayerRemoving:Connect(function(player: Player)
		task.spawn(writeBalance, player)
		markServerDirty()
	end)

	task.spawn(function()
		refreshServer()
		readGlobal()
		local sinceWrite, sinceRead = 0, 0
		while true do
			task.wait(10)
			sinceWrite += 10
			sinceRead += 10
			if sinceWrite >= GLOBAL_WRITE_SECONDS then
				sinceWrite = 0
				for _, player in Players:GetPlayers() do
					writeBalance(player)
				end
			end
			if sinceRead >= GLOBAL_READ_SECONDS then
				sinceRead = 0
				readGlobal()
			end
		end
	end)
end

return LeaderboardService
