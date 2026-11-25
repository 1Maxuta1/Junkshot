--!strict
--[[
	BackpackController: life in the upgrade backpacks (Util/BackpackModels, worn by the server)
	and the moment you get a new one. Display only.

	  every pack near you   hangs back a little when its owner runs or falls, the core pulses,
	                        the ring turns, the thrusters flare in the air
	  your own upgrade      a short full-screen reveal (rays, turning pack, name, slots), tap to
	                        close; other players see the sparks
	Weak devices (LiteGraphics): the packs stand still.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local GameConfig = require(ReplicatedStorage.Shared.Config.GameConfig)
local ItemSounds = require(ReplicatedStorage.Shared.Config.ItemSounds)
local PlayerUpgrades = require(ReplicatedStorage.Shared.Config.PlayerUpgrades)
local BackpackModels = require(ReplicatedStorage.Shared.Util.BackpackModels)

local AudioController = require(script.Parent.AudioController)
local Preview = require(script.Parent.UI.Preview)
local Theme = require(script.Parent.UI.Theme)

local BackpackController = {}

local localPlayer = Players.LocalPlayer
local rgb = Color3.fromRGB
local RANGE = 80
local ATTRIBUTE = "Upgrade_CarryCapacity"
local NIGHT = rgb(16, 20, 38)

type Pack = {
	Model: Model,
	Root: BasePart,
	Humanoid: Humanoid?,
	Weld: Weld,
	Rest: CFrame,
	Lean: number,
	Spins: { { Weld: Weld, Center: CFrame, Offset: CFrame } },
	Pulses: { { Part: BasePart, Color: Color3, Light: PointLight?, Brightness: number } },
	Flames: { ParticleEmitter },
}
local packs: { [Player]: Pack } = {}

local function adopt(player: Player, model: Model)
	local character = player.Character
	local body = model.PrimaryPart
	local root = if character ~= nil then character:FindFirstChild("HumanoidRootPart") else nil
	local weld = if body ~= nil then body:FindFirstChild("PackWeld") else nil
	if character == nil or body == nil or weld == nil or not weld:IsA("Weld") or root == nil or not root:IsA("BasePart") then
		return
	end
	local pack: Pack = {
		Model = model,
		Root = root,
		Humanoid = character:FindFirstChildOfClass("Humanoid"),
		Weld = weld,
		Rest = weld.C0,
		Lean = 0,
		Spins = {},
		Pulses = {},
		Flames = {},
	}
	local core = model:FindFirstChild("Core")
	for _, d in model:GetDescendants() do
		if d:IsA("BasePart") then
			local spin = d:FindFirstChildOfClass("Weld")
			if d:GetAttribute("Spin") ~= nil and spin ~= nil and core ~= nil and core:IsA("BasePart") then
				local center = body.CFrame:ToObjectSpace(core.CFrame)
				table.insert(pack.Spins, { Weld = spin, Center = center, Offset = center:ToObjectSpace(spin.C0) })
			end
			if d:GetAttribute("Pulse") == true then
				local l = d:FindFirstChildOfClass("PointLight")
				table.insert(pack.Pulses, { Part = d, Color = d.Color, Light = l, Brightness = if l ~= nil then l.Brightness else 0 })
			end
		elseif d:IsA("ParticleEmitter") then
			table.insert(pack.Flames, d)
		end
	end
	packs[player] = pack
end

local function step(dt: number)
	if localPlayer:GetAttribute("LiteGraphics") == true then
		return
	end
	local camera = Workspace.CurrentCamera
	local now = os.clock()
	for player, pack in packs do
		if not pack.Model:IsDescendantOf(Workspace) or not pack.Root:IsDescendantOf(Workspace) then
			packs[player] = nil
			continue
		end
		if camera == nil or (camera.CFrame.Position - pack.Root.Position).Magnitude > RANGE then
			continue
		end
		local velocity = pack.Root.AssemblyLinearVelocity
		local speed = Vector3.new(velocity.X, 0, velocity.Z).Magnitude
		local wanted = math.clamp(speed * 0.35, 0, 8) - math.clamp(velocity.Y * 0.15, -8, 5)
		pack.Lean += (wanted - pack.Lean) * math.min(dt * 7, 1)
		local bounce = if speed > 2 then math.sin(now * 11) * math.min(speed, 20) * 0.0022 else math.sin(now * 2) * 0.008
		pack.Weld.C0 = pack.Rest * CFrame.new(0, bounce + 0.8, 0) * CFrame.Angles(-math.rad(math.max(pack.Lean, 0)), 0, 0) * CFrame.new(0, -0.8, 0) -- hangs from its top
		for _, spin in pack.Spins do
			spin.Weld.C0 = spin.Center * CFrame.Angles(0, 0, now * 1.3 % (math.pi * 2)) * spin.Offset
		end
		local wave = 0.5 + 0.5 * math.sin(now * 2.6)
		for _, pulse in pack.Pulses do
			pulse.Part.Color = pulse.Color:Lerp(Color3.new(1, 1, 1), wave * 0.45)
			if pulse.Light ~= nil then
				pulse.Light.Brightness = pulse.Brightness * (0.65 + wave * 0.6)
			end
		end
		local humanoid = pack.Humanoid
		local rate = if humanoid ~= nil and humanoid.FloorMaterial == Enum.Material.Air then 45 elseif speed > 6 then 16 else 7
		for _, flame in pack.Flames do
			flame.Rate = rate
		end
	end
end

-- Sparks around someone who just got a better pack.
local function sparks(player: Player, color: Color3)
	local character = player.Character
	local root = if character ~= nil then character:FindFirstChild("HumanoidRootPart") else nil
	if root == nil or not root:IsA("BasePart") then
		return
	end
	local holder = Instance.new("Attachment")
	holder.Position = Vector3.new(0, 0.5, 1)
	holder.Parent = root
	local emitter = Instance.new("ParticleEmitter")
	emitter.Texture = "rbxasset://textures/particles/sparkles_main.dds"
	emitter.Color = ColorSequence.new(Color3.new(1, 1, 1), color)
	emitter.LightEmission = 1
	emitter.Size = NumberSequence.new(0.7, 0)
	emitter.Lifetime = NumberRange.new(0.6, 1.1)
	emitter.Speed = NumberRange.new(8, 14)
	emitter.SpreadAngle = Vector2.new(180, 180)
	emitter.Drag = 3
	emitter.Rate = 0
	emitter.Parent = holder
	emitter:Emit(45)
	task.delay(1.5, holder.Destroy, holder)
end

local revealToken = 0
local function reveal(level: number)
	revealToken += 1
	local token = revealToken
	local color = BackpackModels.Colors[level] or rgb(255, 255, 255)
	local model = BackpackModels.Build(level)
	if model == nil then
		return
	end
	local playerGui = localPlayer:WaitForChild("PlayerGui")
	local before = playerGui:FindFirstChild("JunkshotBackpackReveal")
	if before ~= nil then
		before:Destroy()
	end
	local gui = Instance.new("ScreenGui")
	gui.Name = "JunkshotBackpackReveal"
	gui.IgnoreGuiInset = true
	gui.ResetOnSpawn = false
	gui.DisplayOrder = 30
	gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling

	local shade = Instance.new("TextButton")
	shade.Name = "BackpackReveal"
	shade.Text = ""
	shade.AutoButtonColor = false
	shade.Size = UDim2.fromScale(1, 1)
	shade.BackgroundColor3 = NIGHT
	shade.BackgroundTransparency = 1
	shade.BorderSizePixel = 0
	shade:SetAttribute("Dressed", true) -- no button look
	shade:AddTag("JunkshotMenu")
	shade.Parent = gui

	local stage = Instance.new("Frame")
	stage.AnchorPoint = Vector2.new(0.5, 0.5)
	stage.Position = UDim2.fromScale(0.5, 0.44)
	stage.Size = UDim2.fromScale(0.62, 0.62)
	stage.BackgroundTransparency = 1
	stage.Parent = shade
	local square = Instance.new("UIAspectRatioConstraint")
	square.Parent = stage
	local stageScale = Instance.new("UIScale")
	stageScale.Scale = 0.2
	stageScale.Parent = stage

	local rays = Instance.new("Frame")
	rays.AnchorPoint = Vector2.new(0.5, 0.5)
	rays.Position = UDim2.fromScale(0.5, 0.5)
	rays.Size = UDim2.fromScale(1.5, 1.5)
	rays.BackgroundTransparency = 1
	rays.Parent = stage
	for index = 0, 5 do
		local ray = Instance.new("Frame")
		ray.AnchorPoint = Vector2.new(0.5, 0.5)
		ray.Position = UDim2.fromScale(0.5, 0.5)
		ray.Size = UDim2.fromScale(0.06, 1)
		ray.Rotation = index * 30
		ray.BackgroundColor3 = color
		ray.BorderSizePixel = 0
		local fade = Instance.new("UIGradient")
		fade.Rotation = 90
		fade.Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 1),
			NumberSequenceKeypoint.new(0.5, 0.45),
			NumberSequenceKeypoint.new(1, 1),
		})
		fade.Parent = ray
		ray.Parent = rays
	end
	local disc = Instance.new("Frame")
	disc.AnchorPoint = Vector2.new(0.5, 0.5)
	disc.Position = UDim2.fromScale(0.5, 0.5)
	disc.Size = UDim2.fromScale(0.8, 0.8)
	disc.BackgroundColor3 = color:Lerp(NIGHT, 0.6)
	disc.BackgroundTransparency = 0.25
	Theme.Corner(disc, UDim.new(1, 0))
	Theme.Stroke(disc, color, 4)
	disc.Parent = stage

	local viewport = Instance.new("ViewportFrame")
	viewport.AnchorPoint = Vector2.new(0.5, 0.5)
	viewport.Position = UDim2.fromScale(0.5, 0.5)
	viewport.Size = UDim2.fromScale(0.9, 0.9)
	Preview.StyleViewport(viewport)
	viewport.Parent = stage
	model.Parent = viewport
	local center = model:GetBoundingBox().Position
	local camera = Instance.new("Camera")
	camera.FieldOfView = 40
	camera.Parent = viewport
	viewport.CurrentCamera = camera

	local function label(name: string, text: string, y: number, height: number, textColor: Color3, max: number)
		local l = Theme.Label({
			Name = name,
			Text = text,
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, y),
			Size = UDim2.fromScale(0.8, height),
			Color = textColor,
			MinTextSize = 12,
			MaxTextSize = max,
			Parent = shade,
		})
		Theme.TextStroke(l, NIGHT, 3)
	end
	local upgrade = PlayerUpgrades.Get("CarryCapacity") :: any
	local old, new = upgrade.Levels[level - 1].Value, upgrade.Levels[level].Value
	label("Head", "NEW BACKPACK!", 0.1, 0.09, rgb(255, 214, 90), 44)
	label("PackName", BackpackModels.Names[level] or "BACKPACK", 0.8, 0.1, color:Lerp(Color3.new(1, 1, 1), 0.4), 48)
	label("Slots", `{GameConfig.Carry.MaxJunk + old} > {GameConfig.Carry.MaxJunk + new} SLOTS`, 0.885, 0.07, rgb(255, 255, 255), 30)
	label("Tap", "tap to continue", 0.95, 0.04, rgb(180, 190, 220), 16)
	gui.Parent = playerGui

	TweenService:Create(shade, TweenInfo.new(0.25), { BackgroundTransparency = 0.15 }):Play()
	TweenService:Create(stageScale, TweenInfo.new(0.5, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 }):Play()
	local family, pitch = ItemSounds.ForEvent("PackUpgrade")
	AudioController.PlayItem(family, pitch, nil, 1)
	local started = os.clock()
	local connection = RunService.RenderStepped:Connect(function()
		local t = os.clock() - started
		rays.Rotation = t * 25
		local angle = t * 0.9 - 6 * math.exp(-t * 2.5) -- a fast turn that settles
		camera.CFrame = CFrame.lookAt(center + Vector3.new(math.sin(angle), 0.3, math.cos(angle)) * 6, center)
	end)
	gui.Destroying:Connect(function()
		connection:Disconnect()
	end)
	local closed = false
	local function close()
		if closed then
			return
		end
		closed = true
		for _, d in shade:GetChildren() do
			if d:IsA("TextLabel") then
				d.Visible = false
			end
		end
		TweenService:Create(shade, TweenInfo.new(0.2), { BackgroundTransparency = 1 }):Play()
		TweenService:Create(stageScale, TweenInfo.new(0.2, Enum.EasingStyle.Quad, Enum.EasingDirection.In), { Scale = 0 }):Play()
		task.delay(0.22, gui.Destroy, gui)
	end
	shade.Activated:Connect(function()
		if os.clock() - started > 0.5 then
			close()
		end
	end)
	task.delay(6, function()
		if token == revealToken then
			close()
		end
	end)
end

local function watch(player: Player)
	local function onCharacter(character: Model)
		local function look(folder: Instance)
			if folder.Name == "JunkshotCosmetics" then
				local model = folder:WaitForChild("UpgradeBackpack", 2)
				if model ~= nil and model:IsA("Model") then
					adopt(player, model)
				end
			end
		end
		character.ChildAdded:Connect(look)
		local now = character:FindFirstChild("JunkshotCosmetics")
		if now ~= nil then
			task.spawn(look, now)
		end
	end
	player.CharacterAdded:Connect(onCharacter)
	if player.Character ~= nil then
		onCharacter(player.Character)
	end
	local last = player:GetAttribute(ATTRIBUTE)
	player:GetAttributeChangedSignal(ATTRIBUTE):Connect(function()
		local level = player:GetAttribute(ATTRIBUTE)
		if type(last) == "number" and type(level) == "number" and level == last + 1 then -- bought, not loaded
			sparks(player, BackpackModels.Colors[level] or rgb(255, 255, 255))
			if player == localPlayer then
				reveal(level)
			end
		end
		last = level
	end)
end

function BackpackController.Start()
	for _, player in Players:GetPlayers() do
		watch(player)
	end
	Players.PlayerAdded:Connect(watch)
	Players.PlayerRemoving:Connect(function(player: Player)
		packs[player] = nil
	end)
	RunService.Heartbeat:Connect(step)
end

return BackpackController
