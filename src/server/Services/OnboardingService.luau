--!strict
--[[
	OnboardingService: walks a new player through the core loop (Config/OnboardingConfig).

	Saved in profile.Data.Onboarding = { Step, Progress, Done }. Profiles that existed before the
	tutorial and already played start as Done (DataService migration). A step is completed only
	by what the server sees happen; its reward is paid once, because the step number moves on in
	the same moment. SKIP ends the tutorial without the remaining rewards.

	Player attributes for the client: OnboardStep (nil = finished / not loaded), OnboardProgress.
	Off while DevTests run (they check balances); they call Advance directly.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local ServerScriptService = game:GetService("ServerScriptService")

local GameConfig = require(ReplicatedStorage.Shared.Config.GameConfig)
local OnboardingConfig = require(ReplicatedStorage.Shared.Config.OnboardingConfig)
local Remotes = require(ReplicatedStorage.Shared.Remotes)
local Validate = require(ReplicatedStorage.Shared.Util.Validate)

local CarryService = require(script.Parent.CarryService)
local DataService = require(script.Parent.DataService)
local EconomyService = require(script.Parent.EconomyService)
local MachineService = require(script.Parent.MachineService)
local RemoteGuard = require(script.Parent.RemoteGuard)

local OnboardingService = {}

local started = false
local POLL = 0.5

local function stateOf(player: Player): any?
	local data = DataService.GetData(player) :: any
	if data == nil then
		return nil
	end
	local state = data.Onboarding
	if type(state) ~= "table" then
		state = { Step = 1, Progress = 0, Done = false }
		data.Onboarding = state
	end
	if not Validate.IsInteger(state.Step, 1, #OnboardingConfig.Steps) then
		state.Step = 1
	end
	if not Validate.IsInteger(state.Progress, 0) then
		state.Progress = 0
	end
	return state
end

local function publish(player: Player)
	local state = stateOf(player)
	local active = state ~= nil and state.Done ~= true
	player:SetAttribute("OnboardStep", if active then (state :: any).Step else nil)
	player:SetAttribute("OnboardProgress", if active then (state :: any).Progress else nil)
end

-- The id of the step a player is on, nil when the tutorial is over.
function OnboardingService.GetStep(player: Player): string?
	local state = stateOf(player)
	return if state ~= nil and state.Done ~= true then OnboardingConfig.Steps[state.Step].Id else nil
end

-- Something happened that counts for step `id`; ignored unless the player is on that step.
function OnboardingService.Advance(player: Player, id: string): boolean
	local state = stateOf(player)
	if state == nil or state.Done == true then
		return false
	end
	local step = OnboardingConfig.Steps[state.Step]
	if step.Id ~= id then
		return false
	end
	state.Progress += 1
	if state.Progress >= step.Goal then
		state.Progress = 0
		if state.Step >= #OnboardingConfig.Steps then
			state.Done = true
		else
			state.Step += 1
		end
		if step.Reward > 0 then
			EconomyService.Earn(player, step.Reward, "Onboarding")
		end
		EconomyService.Message(player, if state.Done then "You know the basics now. Have fun!" else `Done: {step.Title}`, "Success")
	end
	publish(player)
	return true
end

function OnboardingService.Skip(player: Player)
	local state = stateOf(player)
	if state ~= nil and state.Done ~= true then
		state.Done = true
		publish(player)
	end
end

local function isTesting(): boolean
	return RunService:IsStudio() and (GameConfig.Debug.EnableDevTests or ServerScriptService:GetAttribute("RunDevTests") == true)
end

-- Steps that are a situation rather than an event.
local function poll(player: Player)
	local id = OnboardingService.GetStep(player)
	if id == "Recycle" or id == "Take" then
		local machine = MachineService.GetData(player) :: any
		if machine == nil then
			return
		end
		if id == "Recycle" and (machine.Job ~= nil or #machine.Output > 0) then
			OnboardingService.Advance(player, "Recycle")
		elseif id == "Take" and machine.Job == nil and #machine.Output == 0 then
			OnboardingService.Advance(player, "Take")
		end
	elseif id == "Explore" then
		local root = CarryService.GetLiveRoot(player)
		if root ~= nil and (root.Position - OnboardingConfig.RacewaySpot).Magnitude <= OnboardingConfig.RacewayDistance then
			OnboardingService.Advance(player, "Explore")
		end
	end
end

function OnboardingService.Start()
	assert(not started, "[OnboardingService] Start() called twice")
	started = true
	RemoteGuard.ConnectEvent(Remotes.GetEvent("OnboardingSkip"), {
		Name = "OnboardingSkip",
		MaxArgs = 0,
		RateLimit = GameConfig.RateLimits.OnboardingSkip,
	}, function(player: Player)
		OnboardingService.Skip(player)
	end)
	if isTesting() then
		return
	end
	local function onLoaded(player: Player)
		publish(player)
		local state = stateOf(player)
		if state ~= nil and state.Done ~= true and state.Step == 1 then
			EconomyService.Message(player, "Welcome to JUNKSHOT! Turn junk into treasure.", "Success")
		end
	end
	DataService.PlayerLoaded:Connect(onLoaded)
	for _, player in Players:GetPlayers() do
		if DataService.IsLoaded(player) then
			onLoaded(player)
		end
	end
	CarryService.ItemAdded:Connect(function(player: Player)
		OnboardingService.Advance(player, "Collect")
	end)
	EconomyService.Earned:Connect(function(player: Player, _amount: number, reason: string)
		if reason == "Sell" then
			OnboardingService.Advance(player, "Sell")
		end
	end)
	EconomyService.Spent:Connect(function(player: Player, _amount: number, reason: string)
		if reason ~= "Trade" and string.sub(reason, 1, 5) ~= "Shop:" then
			OnboardingService.Advance(player, "Upgrade")
		end
	end)
	task.spawn(function()
		while true do
			task.wait(POLL)
			for _, player in Players:GetPlayers() do
				poll(player)
			end
		end
	end)
end

return OnboardingService
