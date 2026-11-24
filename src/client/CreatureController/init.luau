--!strict
--[[
	CreatureController: presentation of the Rare Creature world event (server:
	WorldEventService). Local only; nothing is sent to the server (catching goes through the
	creature's ProximityPrompt, drawn by UI/PickupPrompt).

	  appear     the creature pops out of a snow puff (scale 0 -> 1) with a chime
	  idle       bobs and looks around (only within ANIMATE_RANGE of the camera)
	  label      "RARE" badge, its name and the time left, visible from far away
	  disappear  spins and shrinks into a puff when caught or when it runs away
	  winner     the reward card (UI/RewardReveal) shows which item it was and where it went
]]

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local AudioConfig = require(ReplicatedStorage.Shared.Config.AudioConfig)
local ItemConfig = require(ReplicatedStorage.Shared.Config.ItemConfig)
local Rarities = require(ReplicatedStorage.Shared.Config.Rarities)
local WorldEventConfig = require(ReplicatedStorage.Shared.Config.WorldEventConfig)

local AudioController = require(script.Parent.AudioController)
local InputController = require(script.Parent.InputController)
local RewardReveal = require(script.Parent.UI.RewardReveal)
local Theme = require(script.Parent.UI.Theme)

local CreatureController = {}

local localPlayer = Players.LocalPlayer
local ANIMATE_RANGE = 220
local APPEAR_TIME = 0.6
local VANISH_TIME = 0.5

type View = {
	Model: Model,
	Home: CFrame, -- the server's pivot
	Scale: NumberValue, -- 0..1, drives Model:ScaleTo
	Phase: number,
	Label: BillboardGui,
	TimeLabel: TextLabel,
	Leaving: boolean,
}

local views: { [Model]: View } = {}
local reveal: RewardReveal.RewardReveal? = nil

local function puff(at: Vector3, color: Color3)
	local holder = Instance.new("Part")
	holder.Anchored = true
	holder.CanCollide = false
	holder.CanQuery = false
	holder.CanTouch = false
	holder.Transparency = 1
	holder.Size = Vector3.one
	holder.Position = at
	local emitter = Instance.new("ParticleEmitter")
	emitter.Texture = "rbxasset://textures/particles/smoke_main.dds"
	emitter.Color = ColorSequence.new(Color3.new(1, 1, 1), color)
	emitter.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1.5), NumberSequenceKeypoint.new(1, 4) })
	emitter.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.2), NumberSequenceKeypoint.new(1, 1) })
	emitter.Lifetime = NumberRange.new(0.6, 1)
	emitter.Speed = NumberRange.new(6, 12)
	emitter.SpreadAngle = Vector2.new(180, 180)
	emitter.Rate = 0
	emitter.Parent = holder
	holder.Parent = Workspace
	emitter:Emit(18)
	task.delay(1.5, function()
		holder:Destroy()
	end)
end

local function setScale(view: View, value: number)
	local model = view.Model
	if model.Parent == nil then
		return
	end
	pcall(function()
		model:ScaleTo(math.max(value, 0.02))
	end)
end

local function buildLabel(model: Model, rarity: string): (BillboardGui, TextLabel)
	local color = Rarities.GetColor(rarity)
	local gui = Instance.new("BillboardGui")
	gui.Name = "CreatureLabel"
	gui.Size = UDim2.fromOffset(200, 74)
	gui.StudsOffsetWorldSpace = Vector3.new(0, 7.5, 0)
	gui.AlwaysOnTop = true
	gui.LightInfluence = 0
	gui.MaxDistance = 400
	gui.Adornee = model.PrimaryPart

	local badge = Theme.Label({
		Name = "Rarity",
		Text = `★ {string.upper(rarity)} ★`,
		Size = UDim2.new(1, 0, 0, 26),
		Color = color,
		MinTextSize = 14,
		MaxTextSize = 24,
		Parent = gui,
	})
	badge.TextStrokeTransparency = 0.2
	local name = Theme.Label({
		Name = "Name",
		Text = tostring(model:GetAttribute("DisplayName") or model.Name),
		Size = UDim2.new(1, 0, 0, 24),
		Position = UDim2.fromOffset(0, 26),
		Color = Color3.new(1, 1, 1),
		MinTextSize = 12,
		MaxTextSize = 22,
		Parent = gui,
	})
	name.TextStrokeTransparency = 0.2
	local timeLabel = Theme.Label({
		Name = "Time",
		Text = "",
		Size = UDim2.new(1, 0, 0, 20),
		Position = UDim2.fromOffset(0, 50),
		Color = Color3.fromRGB(220, 236, 255),
		MinTextSize = 10,
		MaxTextSize = 18,
		Parent = gui,
	})
	timeLabel.TextStrokeTransparency = 0.3
	gui.Parent = model
	return gui, timeLabel
end

local function showReward(model: Model)
	if model:GetAttribute("ClaimedBy") ~= localPlayer.UserId then
		return
	end
	local itemId = model:GetAttribute("RewardId")
	if type(itemId) ~= "string" or ItemConfig.Get(itemId) == nil then
		return
	end
	local note = if model:GetAttribute("RewardWhere") == "Ground"
		then "Your hands were full - it is on the ground next to you"
		else "It is in your hands"
	local currentReveal = reveal
	if currentReveal ~= nil then
		currentReveal.Show(itemId, ItemConfig.GetRarity(itemId) or "Rare", note, InputController.GetInputKind() == "Gamepad")
	end
end

local function leave(view: View)
	if view.Leaving then
		return
	end
	view.Leaving = true
	local model = view.Model
	local claimed = model:GetAttribute("State") == "Claimed"
	view.Label.Enabled = false
	local rarity = model:GetAttribute("Rarity")
	local color = Rarities.GetColor(if type(rarity) == "string" then rarity else "Rare")
	if claimed and model.PrimaryPart ~= nil then
		AudioController.PlayAt(AudioConfig.Creature.Catch, model.PrimaryPart, false, AudioConfig.Creature.Range)
	end
	TweenService:Create(view.Scale, TweenInfo.new(VANISH_TIME, Enum.EasingStyle.Back, Enum.EasingDirection.In), { Value = 0 }):Play()
	task.delay(VANISH_TIME * 0.8, function()
		puff(view.Home.Position + Vector3.new(0, 2, 0), color)
	end)
	if claimed then
		showReward(model)
	end
end

local function track(instance: Instance)
	if not instance:IsA("Model") or views[instance] ~= nil or instance.PrimaryPart == nil then
		return
	end
	local model = instance :: Model
	local rarity = model:GetAttribute("Rarity")
	local label, timeLabel = buildLabel(model, if type(rarity) == "string" then rarity else "Rare")
	local scale = Instance.new("NumberValue")
	scale.Value = 0
	local view: View = {
		Model = model,
		Home = model:GetPivot(),
		Scale = scale,
		Phase = math.random() * 10,
		Label = label,
		TimeLabel = timeLabel,
		Leaving = false,
	}
	views[model] = view
	scale.Changed:Connect(function(value: number)
		setScale(view, value)
	end)

	if model:GetAttribute("State") == "Active" then
		setScale(view, 0.02)
		puff(view.Home.Position + Vector3.new(0, 1.5, 0), Rarities.GetColor(if type(rarity) == "string" then rarity else "Rare"))
		AudioController.PlayAt(AudioConfig.Creature.Appear, model.PrimaryPart :: BasePart, false, AudioConfig.Creature.Range)
		TweenService:Create(scale, TweenInfo.new(APPEAR_TIME, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Value = 1 }):Play()
	else
		leave(view)
	end
	model:GetAttributeChangedSignal("State"):Connect(function()
		if model:GetAttribute("State") ~= "Active" then
			leave(view)
		end
	end)
end

local function untrack(instance: Instance)
	local view = views[instance :: Model]
	if view ~= nil then
		view.Scale:Destroy()
		views[instance :: Model] = nil
	end
end

local function step()
	local camera = Workspace.CurrentCamera
	if camera == nil then
		return
	end
	local t = os.clock()
	for model, view in views do
		if view.Leaving or model.Parent == nil then
			continue
		end
		if (view.Home.Position - camera.CFrame.Position).Magnitude > ANIMATE_RANGE then
			continue
		end
		-- Bob, and turn the head side to side now and then.
		local bob = math.abs(math.sin(t * 2.2 + view.Phase)) * 0.35
		local look = math.sin(t * 0.7 + view.Phase) * 0.6
		model:PivotTo(view.Home * CFrame.new(0, bob, 0) * CFrame.Angles(0, look, 0))
	end
end

local function tickLabels()
	local now = Workspace:GetServerTimeNow()
	for model, view in views do
		local expiresAt = model:GetAttribute("ExpiresAt")
		if type(expiresAt) == "number" then
			local left = math.max(0, math.floor(expiresAt - now))
			view.TimeLabel.Text = string.format("leaves in %d:%02d", left // 60, left % 60)
		end
	end
end

function CreatureController.Start()
	task.spawn(function()
		local gui = Instance.new("ScreenGui")
		gui.Name = "JunkshotCreatureReward"
		gui.ResetOnSpawn = false
		gui.ScreenInsets = Enum.ScreenInsets.CoreUISafeInsets
		gui.DisplayOrder = 9
		reveal = RewardReveal.Mount(gui)
		gui.Parent = localPlayer:WaitForChild("PlayerGui")

		CollectionService:GetInstanceAddedSignal(WorldEventConfig.Tag):Connect(track)
		CollectionService:GetInstanceRemovedSignal(WorldEventConfig.Tag):Connect(untrack)
		for _, model in CollectionService:GetTagged(WorldEventConfig.Tag) do
			track(model)
		end
		RunService.RenderStepped:Connect(step)
		while true do
			tickLabels()
			task.wait(0.5)
		end
	end)
end

return CreatureController
