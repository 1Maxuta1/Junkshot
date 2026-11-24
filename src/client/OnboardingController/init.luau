--!strict
--[[
	OnboardingController: the objective card and the arrow of the tutorial (server:
	OnboardingService). Display only. Nothing is created for players who finished it.
]]

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local GameConfig = require(ReplicatedStorage.Shared.Config.GameConfig)
local MachineConfig = require(ReplicatedStorage.Shared.Config.MachineConfig)
local OnboardingConfig = require(ReplicatedStorage.Shared.Config.OnboardingConfig)
local Remotes = require(ReplicatedStorage.Shared.Remotes)

local InputController = require(script.Parent.InputController)
local Theme = require(script.Parent.UI.Theme)
local Window = require(script.Parent.EconomyController.Window)

local OnboardingController = {}

local localPlayer = Players.LocalPlayer
local SMALL_SCREEN = 500

local function rootPosition(): Vector3?
	local character = localPlayer.Character
	local root = if character ~= nil then character:FindFirstChild("HumanoidRootPart") else nil
	return if root ~= nil and root:IsA("BasePart") then root.Position else nil
end

local function pivotOf(instance: Instance?): Vector3?
	return if instance ~= nil and instance:IsA("PVInstance") then instance:GetPivot().Position else nil
end

-- Where the arrow points for a target name; nil = not streamed in / nothing there.
local function findTarget(name: string, from: Vector3): Vector3?
	if name == "Junk" then
		local container = Workspace:FindFirstChild(GameConfig.Junk.ContainerName)
		local best: Vector3? = nil
		local bestDistance = math.huge
		if container ~= nil then
			for _, junk in container:GetChildren() do
				local prompt = junk:FindFirstChildWhichIsA("ProximityPrompt", true)
				local reserved = if prompt ~= nil then prompt:GetAttribute("ReservedFor") else nil
				local position = pivotOf(junk)
				if prompt ~= nil and position ~= nil and (reserved == nil or reserved == 0 or reserved == localPlayer.UserId) and (position - from).Magnitude < bestDistance then
					best, bestDistance = position, (position - from).Magnitude
				end
			end
		end
		return best
	elseif name == "Machine" then
		for _, machine in CollectionService:GetTagged(MachineConfig.Tag) do
			if machine:GetAttribute("OwnerUserId") == localPlayer.UserId and machine:IsDescendantOf(Workspace) then
				return pivotOf(machine)
			end
		end
	elseif name == "Dealer" then
		return pivotOf(Workspace:FindFirstChild("ScrapDealer"))
	elseif name == "Base" then
		for _, plot in CollectionService:GetTagged("BasePlot") do
			if plot:GetAttribute("Owner") == localPlayer.UserId then
				return pivotOf(plot)
			end
		end
	elseif name == "Raceway" then
		return OnboardingConfig.RacewaySpot
	end
	return nil
end

local function run()
	local playerGui = localPlayer:WaitForChild("PlayerGui")
	local gui = Instance.new("ScreenGui")
	gui.Name = "JunkshotOnboarding"
	gui.ResetOnSpawn = false
	gui.ScreenInsets = Enum.ScreenInsets.CoreUISafeInsets
	gui.DisplayOrder = 3 -- under every window

	local card = Instance.new("Frame")
	card.Name = "Objective"
	card.Position = UDim2.new(0, 8, 0, 8)
	card.BackgroundColor3 = Theme.Colors.Panel
	Theme.Corner(card, UDim.new(0, 14))
	Theme.Stroke(card, Theme.Colors.Ink, 2.5)
	card.Parent = gui
	local step = Theme.Label({ Name = "Step", Text = "", Size = UDim2.new(1, -86, 0, 18), Position = UDim2.new(0, 10, 0, 11),
		Color = Theme.Colors.AccentDark, MinTextSize = 11, MaxTextSize = 14, XAlignment = Enum.TextXAlignment.Left, Parent = card })
	local title = Theme.Label({ Name = "Title", Text = "", Size = UDim2.new(1, -20, 0, 22), Position = UDim2.new(0, 10, 0, 38),
		MinTextSize = 12, MaxTextSize = 20, XAlignment = Enum.TextXAlignment.Left, Parent = card })
	local hint = Theme.Label({ Name = "Hint", Text = "", Size = UDim2.new(1, -20, 0, 28), Position = UDim2.new(0, 10, 0, 61),
		Color = Theme.Colors.InkSoft, Font = Theme.FontBody, MinTextSize = 11, MaxTextSize = 13, XAlignment = Enum.TextXAlignment.Left, Parent = card })
	hint.TextWrapped = true
	local back = Instance.new("Frame")
	back.Name = "Bar"
	back.Position = UDim2.new(0, 10, 1, -16)
	back.Size = UDim2.new(1, -20, 0, 8)
	back.BackgroundColor3 = Theme.Colors.PanelTint
	Theme.Corner(back, UDim.new(1, 0))
	back.Parent = card
	local fill = Instance.new("Frame")
	fill.Name = "Fill"
	fill.Size = UDim2.fromScale(0, 1)
	fill.BackgroundColor3 = Theme.Colors.Success
	Theme.Corner(fill, UDim.new(1, 0))
	fill.Parent = back
	local skip = Window.SmallButton(card, "SKIP", Theme.Colors.InkSoft, UDim2.new(0, 64, 0, 32), UDim2.new(1, -6, 0, 4), Vector2.new(1, 0))
	local skipLabel = skip:FindFirstChild("Label") :: TextLabel
	local armedUntil = 0
	skip.Activated:Connect(function()
		if os.clock() < armedUntil then
			Remotes.GetEvent("OnboardingSkip"):FireServer()
		else
			armedUntil = os.clock() + 3 -- a second tap confirms
		end
	end)

	local anchor = Instance.new("Part")
	anchor.Name = "OnboardingTarget"
	anchor.Size = Vector3.one
	anchor.Transparency = 1
	anchor.Anchored = true
	anchor.CanCollide = false
	anchor.CanQuery = false
	anchor.CanTouch = false
	local arrow = Instance.new("BillboardGui")
	arrow.Name = "OnboardingArrow"
	arrow.Size = UDim2.fromOffset(64, 64)
	arrow.AlwaysOnTop = true
	arrow.LightInfluence = 0
	arrow.ResetOnSpawn = false
	arrow.MaxDistance = 2000
	arrow.Adornee = anchor
	local arrowLabel = Theme.Label({ Name = "Arrow", Text = "▼", Size = UDim2.fromScale(1, 0.7), Color = Theme.Colors.Sun, MinTextSize = 16, MaxTextSize = 48, Parent = arrow })
	Theme.TextStroke(arrowLabel, Theme.Colors.Ink, 3)
	local distanceLabel = Theme.Label({ Name = "Distance", Text = "", Size = UDim2.fromScale(1, 0.3), Position = UDim2.fromScale(0, 0.7), Color = Theme.Colors.White, MinTextSize = 11, MaxTextSize = 18, Parent = arrow })
	Theme.TextStroke(distanceLabel, Theme.Colors.Ink, 2)
	anchor.Parent = Workspace.CurrentCamera
	arrow.Parent = playerGui

	local function fit()
		local small = gui.AbsoluteSize.Y < SMALL_SCREEN
		card.Size = if small then UDim2.new(0, 228, 0, 82) else UDim2.new(0, 290, 0, 114)
		hint.Visible = not small
		card.Position = if small then UDim2.new(0, 8, 0, 8) else UDim2.new(0, 8, 0, 12)
	end
	gui:GetPropertyChangedSignal("AbsoluteSize"):Connect(fit)
	fit()
	gui.Parent = playerGui
	fit()

	local connections: { RBXScriptConnection } = {}
	local function show()
		local index = localPlayer:GetAttribute("OnboardStep")
		local config = if type(index) == "number" then OnboardingConfig.Steps[index] else nil
		if config == nil then
			return
		end
		step.Text = `STEP {index} OF {#OnboardingConfig.Steps}   +{config.Reward} {GameConfig.Klunks.Symbol}`
		local progress = localPlayer:GetAttribute("OnboardProgress") or 0
		title.Text = if config.Goal > 1 then `{config.Title} ({progress}/{config.Goal})` else config.Title
		hint.Text = config.Hint
		local fraction = ((index :: number) - 1 + (progress :: number) / config.Goal) / #OnboardingConfig.Steps
		TweenService:Create(fill, TweenInfo.new(0.3), { Size = UDim2.fromScale(fraction, 1) }):Play()
	end
	table.insert(connections, localPlayer:GetAttributeChangedSignal("OnboardStep"):Connect(show))
	table.insert(connections, localPlayer:GetAttributeChangedSignal("OnboardProgress"):Connect(show))
	show()

	while localPlayer:GetAttribute("OnboardStep") ~= nil do
		local index = localPlayer:GetAttribute("OnboardStep") :: number
		local config = OnboardingConfig.Steps[index]
		skipLabel.Text = if os.clock() < armedUntil then "SURE?" else "SKIP"
		local from = rootPosition()
		local target = if from ~= nil and config ~= nil and not InputController.IsMenuOpen() then findTarget(config.Target, from) else nil
		local distance = if from ~= nil and target ~= nil then (target - from).Magnitude else 0
		arrow.Enabled = target ~= nil and distance > 8
		if target ~= nil then
			anchor.CFrame = CFrame.new(target + Vector3.new(0, if config.Target == "Junk" then 4 else 9, 0))
			distanceLabel.Text = `{math.floor(distance)} m`
		end
		task.wait(0.2)
	end
	for _, connection in connections do
		connection:Disconnect()
	end
	gui:Destroy()
	arrow:Destroy()
	anchor:Destroy()
end

function OnboardingController.Start()
	local running = false
	local function check()
		if localPlayer:GetAttribute("OnboardStep") ~= nil and not running then
			running = true
			task.spawn(function()
				run()
				running = false
			end)
		end
	end
	localPlayer:GetAttributeChangedSignal("OnboardStep"):Connect(check)
	check()
end

return OnboardingController
