--!strict
--[[
	DataService: owns player profiles (load, session lock, save, release).
	Built on ProfileStore (loleris / MAD STUDIO). API verified against
	https://madstudioroblox.github.io/ProfileStore/api

	Responsibilities
	  - Start a session-locked profile when a player joins; release it when they leave.
	  - Fail closed: if the profile cannot be loaded (or is from a newer game version) the
	    player is kicked and no service will hand out data for them.
	  - Mark a player as ready with the Player attribute "DataLoaded" = true.
	  - Expose the profile data to OTHER SERVER SERVICES via GetData(). Never expose this
	    to clients, and never mutate Klunks or Items from outside CurrencyService /
	    InventoryService.

	Saving: ProfileStore auto-saves periodically and saves on EndSession. On server shutdown
	it ends all sessions itself (see "Shutdown Handling" in its API docs), so no manual
	BindToClose is needed here.

	ProfileStore must be installed at src/server/Packages/ProfileStore.luau
	(becomes ServerScriptService.Server.Packages.ProfileStore).
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local GameConfig = require(ReplicatedStorage.Shared.Config.GameConfig)
local Types = require(ReplicatedStorage.Shared.Types)
local Signal = require(ReplicatedStorage.Shared.Util.Signal)

-- The library is third-party and not shipped with this project, so check before requiring.
-- Use a direct path so static type checkers can resolve this ModuleScript.
local packagesFolder = script.Parent.Parent:FindFirstChild("Packages")
if packagesFolder == nil then
	error(
		"[DataService] ProfileStore ModuleScript not found. "
			.. "Place it at src/server/Packages/ProfileStore.luau "
			.. "(ServerScriptService.Server.Packages.ProfileStore). See README."
	)
end
local profileStoreModule = packagesFolder:FindFirstChild("ProfileStore")
if profileStoreModule == nil or not profileStoreModule:IsA("ModuleScript") then
	error(
		"[DataService] ProfileStore ModuleScript not found. "
			.. "Place it at src/server/Packages/ProfileStore.luau "
			.. "(ServerScriptService.Server.Packages.ProfileStore). See README."
	)
end
local ProfileStore: any = require(script.Parent.Parent.Packages.ProfileStore)

local KICK_LOAD_FAILED = "Your data could not be loaded. Please rejoin."
local KICK_DATA_INVALID = "Your data could not be verified. Please rejoin."
local KICK_SESSION_ENDED = "Your data session ended. Please rejoin."

-- Profile.Data for brand-new players; Reconcile() fills missing keys of existing profiles.
-- Keep it minimal: only fields that a shipped system actually uses.
local TEMPLATE: Types.ProfileData = {
	Version = GameConfig.Data.ProfileVersion,
	Klunks = 0,
	Items = {},
	-- Carried items survive leaving the game (CarryService).
	Carry = {},
	-- The personal machine (MachineService). Upgrade values are level indexes (1 = default).
	Machine = {
		Output = {},
		Upgrades = { Speed = 1, Storage = 1, Level = 1 },
		BoostUntil = 0,
		InstantCredits = 0,
		ResultSeq = 0,
	},
	-- Processed Robux receipt ids (MonetizationService idempotency).
	Purchases = {},
	Stats = {
		TotalKlunksEarned = 0,
	},
	Settings = {},
}

-- MIGRATIONS[n] upgrades data from version n to n + 1 (mutating it in place).
-- Reconcile() fills new template keys afterwards, so additive changes need no code here.
local MIGRATIONS: { [number]: (data: any) -> () } = {
	[1] = function(_data: any)
		-- 1 -> 2: Carry, Machine and Purchases were added; Reconcile() creates them.
	end,
}

local DataService = {}

-- Fires (player) once the player's data is loaded and validated.
DataService.PlayerLoaded = Signal.new()

local store: any = nil
local started = false

local Profiles: { [Player]: any } = {} -- every started session (so it can always be ended)
local Ready: { [Player]: boolean } = {} -- validated and safe for other services to use
local Loading: { [Player]: boolean } = {}

-- Returns false when the data must not be used.
local function prepareData(player: Player, profile: any): boolean
	local data = profile.Data
	local version = data.Version

	if type(version) ~= "number" then
		warn(`[DataService] {player.Name}: profile has no valid Version`)
		return false
	end
	if version > GameConfig.Data.ProfileVersion then
		-- Saved by a newer server build: touching it could destroy data we do not understand.
		warn(`[DataService] {player.Name}: profile version {version} is newer than {GameConfig.Data.ProfileVersion}`)
		return false
	end
	while version < GameConfig.Data.ProfileVersion do
		local migrate = MIGRATIONS[version]
		if migrate == nil then
			warn(`[DataService] {player.Name}: no migration from version {version}`)
			return false
		end
		migrate(data)
		version += 1
		data.Version = version
	end

	profile:Reconcile()
	return true
end

local function loadProfile(player: Player)
	local key = GameConfig.Data.KeyPrefix .. tostring(player.UserId)

	local profile: any = nil
	if GameConfig.Debug.SimulateLoadFailure and RunService:IsStudio() then
		warn("[DataService] SimulateLoadFailure is on: skipping StartSessionAsync")
	else
		profile = store:StartSessionAsync(key, {
			-- Stop retrying as soon as the player has left.
			Cancel = function()
				return player.Parent ~= Players
			end,
		})
	end

	if profile == nil then
		-- nil = load failed or was cancelled. Only kick if the player is still here.
		if player.Parent == Players then
			player:Kick(KICK_LOAD_FAILED)
		end
		return
	end

	profile:AddUserId(player.UserId) -- lets Roblox erasure requests find this key (GDPR)

	if player.Parent ~= Players then
		-- Left while loading: release immediately so the lock is not held for nothing.
		profile:EndSession()
		return
	end

	profile.OnSessionEnd:Connect(function()
		-- Fires on EndSession, on a session steal by another server, and on shutdown.
		if Profiles[player] == profile then
			Profiles[player] = nil
			Ready[player] = nil
		end
		if player.Parent == Players then
			player:Kick(KICK_SESSION_ENDED)
		end
	end)
	Profiles[player] = profile

	if not prepareData(player, profile) then
		player:Kick(KICK_DATA_INVALID)
		profile:EndSession()
		return
	end

	Ready[player] = true
	DataService.PlayerLoaded:Fire(player) -- services restore carried items, machine, plot
	player:SetAttribute("DataLoaded", true)
end

local function onPlayerAdded(player: Player)
	if Loading[player] or Profiles[player] ~= nil then
		return
	end
	if ProfileStore.IsClosing then
		player:Kick(KICK_LOAD_FAILED)
		return
	end

	Loading[player] = true
	local ok, err = xpcall(loadProfile, debug.traceback, player)
	Loading[player] = nil

	if not ok then
		warn(`[DataService] unexpected error while loading {player.Name}: {tostring(err)}`)
		-- Fail closed: never leave a player in the game without verified data.
		local profile = Profiles[player]
		Profiles[player] = nil
		Ready[player] = nil
		if profile ~= nil then
			profile:EndSession()
		end
		if player.Parent == Players then
			player:Kick(KICK_LOAD_FAILED)
		end
	end
end

local beforeRelease: { (player: Player) -> () } = {}

local function onPlayerRemoving(player: Player)
	-- Let other services write last changes (e.g. a reward still in the machine) while the data
	-- is still loaded. Runs synchronously, so it always happens before EndSession below.
	if Ready[player] then
		for _, callback in beforeRelease do
			local ok, err = xpcall(callback, debug.traceback, player)
			if not ok then
				warn(`[DataService] before-release callback failed for {player.Name}: {tostring(err)}`)
			end
		end
	end

	local profile = Profiles[player]
	Profiles[player] = nil
	Ready[player] = nil
	Loading[player] = nil
	if profile ~= nil then
		profile:EndSession() -- final save + releases the session lock
	end
end

-- Studio helper: tells you immediately whether DataStores are reachable.
local function reportDataStoreState()
	local deadline = os.clock() + 10
	while ProfileStore.DataStoreState == "NotReady" and os.clock() < deadline do
		task.wait(0.25)
	end
	print(`[DataService] DataStoreState = {tostring(ProfileStore.DataStoreState)}`)
	if ProfileStore.DataStoreState ~= "Access" then
		warn(
			"[DataService] DataStores are not writable here. In Studio, publish the place and enable "
				.. "Game Settings > Security > Enable Studio Access to API Services, or use Debug.UseMockStore."
		)
	end
end

function DataService.Start()
	assert(not started, "[DataService] Start() called twice")
	started = true

	local baseStore = ProfileStore.New(GameConfig.Data.StoreName, TEMPLATE)
	if GameConfig.Debug.UseMockStore and RunService:IsStudio() then
		warn("[DataService] Debug.UseMockStore is on: data is NOT saved to the DataStore")
		store = baseStore.Mock
	else
		store = baseStore
	end

	ProfileStore.OnError:Connect(function(message: string, storeName: string, profileKey: string)
		warn(`[DataService] ProfileStore error ({storeName}/{profileKey}): {message}`)
	end)
	ProfileStore.OnCriticalToggle:Connect(function(isCritical: boolean)
		if isCritical then
			warn("[DataService] DataStore is in a critical state: saves are failing repeatedly")
		else
			print("[DataService] DataStore recovered from critical state")
		end
	end)

	Players.PlayerAdded:Connect(onPlayerAdded)
	Players.PlayerRemoving:Connect(onPlayerRemoving)
	-- Players that joined before this script ran.
	for _, player in Players:GetPlayers() do
		task.spawn(onPlayerAdded, player)
	end

	task.spawn(reportDataStoreState)
end

-- Registers a callback that runs when a loaded player leaves, BEFORE their profile is saved
-- and released. The callback must not yield. Use it for last-moment data writes.
function DataService.OnBeforeRelease(callback: (player: Player) -> ())
	table.insert(beforeRelease, callback)
end

function DataService.IsLoaded(player: Player): boolean
	local profile = Profiles[player]
	return Ready[player] == true and profile ~= nil and profile:IsActive()
end

-- For OTHER SERVER SERVICES only. Returns nil unless the data is loaded and active.
function DataService.GetData(player: Player): Types.ProfileData?
	if not DataService.IsLoaded(player) then
		return nil
	end
	local profile = Profiles[player]
	return profile.Data :: any
end

-- Polls until the player's data is ready, the player leaves, or the timeout passes.
function DataService.WaitForData(player: Player, timeout: number): Types.ProfileData?
	local deadline = os.clock() + timeout
	while player.Parent == Players and os.clock() < deadline do
		local data = DataService.GetData(player)
		if data ~= nil then
			return data
		end
		task.wait(0.1)
	end
	return DataService.GetData(player)
end

return DataService
