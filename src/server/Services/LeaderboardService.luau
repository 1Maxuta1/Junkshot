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
local Board = require(script.Parent.Leaderboard.Board)

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
local boards: { [string]: Board.Board } = {}
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
	boards[key] = Board.Build(key, title, rowCount, ground * BOARD_POSITIONS[key], ground.Position)
end

local function setRows(key: string, entries: { Board.Entry }, footer: string)
	local board = boards[key]
	if board ~= nil then
		board.Set(entries, footer)
	end
end

local function refreshServer()
	serverDirty = false
	local list = {}
	for _, player in Players:GetPlayers() do
		local klunks = CurrencyService.GetKlunks(player)
		if klunks ~= nil then
			table.insert(list, { UserId = player.UserId, Name = player.DisplayName, Klunks = klunks })
		end
	end
	table.sort(list, function(a, b)
		return a.Klunks > b.Klunks
	end)
	setRows("Server", list, "This server - live")
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
	local list = {}
	for _, entry in (pages :: any):GetCurrentPage() do
		local userId = tonumber(entry.key)
		if userId ~= nil then
			table.insert(list, { UserId = userId, Name = nameOf(userId), Klunks = entry.value })
		end
	end
	setRows("Global", list, "All servers - every 2 minutes")
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
