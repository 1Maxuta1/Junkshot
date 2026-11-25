--!strict
--[[
	Abilities (client): draws the Mythic item abilities the server broadcasts (AbilityFx).
	Every client draws them locally (no server parts, no physics, nothing replicated back).

	  Comet     a glowing comet with a long trail falls from the sky onto the given spot,
	            whooshing; on impact a flash, an expanding shock ring, a burst of sparkles, a
	            short camera shake for players close by and a glowing mark that fades.
	  Starfall  shooting stars streak high across the sky above the owner for a few seconds,
	            with soft chimes.
	Sounds use the player's effects volume (AudioController).
]]

local Debris = game:GetService("Debris")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local AudioConfig = require(ReplicatedStorage.Shared.Config.AudioConfig)
local ItemSounds = require(ReplicatedStorage.Shared.Config.ItemSounds)
local Remotes = require(ReplicatedStorage.Shared.Remotes)

local AudioController = require(script.Parent.Parent.AudioController)

local Abilities = {}

local watchToasted: () -> ()

local SPARKLE = "rbxasset://textures/particles/sparkles_main.dds"
local SHAKE_RANGE = 90
local VIEW_RANGE = 500

local function effectsFolder(): Folder
	local existing = Workspace:FindFirstChild("ClientEffects")
	if existing ~= nil and existing:IsA("Folder") then
		return existing
	end
	local folder = Instance.new("Folder")
	folder.Name = "ClientEffects"
	folder.Parent = Workspace
	return folder
end

local function glowPart(size: Vector3, color: Color3, shape: Enum.PartType?): Part
	local p = Instance.new("Part")
	p.Shape = shape or Enum.PartType.Ball
	p.Size = size
	p.Color = color
	p.Material = Enum.Material.Neon
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.CastShadow = false
	return p
end

local function addTrail(part: BasePart, from: Color3, to: Color3, width: number, lifetime: number)
	local a0 = Instance.new("Attachment")
	a0.Position = Vector3.new(0, width / 2, 0)
	a0.Parent = part
	local a1 = Instance.new("Attachment")
	a1.Position = Vector3.new(0, -width / 2, 0)
	a1.Parent = part
	local trail = Instance.new("Trail")
	trail.Attachment0 = a0
	trail.Attachment1 = a1
	trail.Lifetime = lifetime
	trail.LightEmission = 1
	trail.FaceCamera = true
	trail.Color = ColorSequence.new(from, to)
	trail.Transparency = NumberSequence.new(0, 1)
	trail.WidthScale = NumberSequence.new(1, 0)
	trail.Parent = part
end

local function sparkleBurst(position: Vector3, color: Color3, count: number)
	local holder = glowPart(Vector3.one, color)
	holder.Transparency = 1
	holder.Position = position
	local emitter = Instance.new("ParticleEmitter")
	emitter.Texture = SPARKLE
	emitter.Color = ColorSequence.new(color, Color3.new(1, 1, 1))
	emitter.LightEmission = 1
	emitter.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1.4), NumberSequenceKeypoint.new(1, 0) })
	emitter.Lifetime = NumberRange.new(0.8, 1.6)
	emitter.Speed = NumberRange.new(18, 40)
	emitter.SpreadAngle = Vector2.new(180, 180)
	emitter.Acceleration = Vector3.new(0, -25, 0)
	emitter.Rate = 0
	emitter.Parent = holder
	holder.Parent = effectsFolder()
	emitter:Emit(count)
	Debris:AddItem(holder, 2.5)
end

local function shakeCamera(strength: number, duration: number)
	local name = "JunkshotCometShake"
	local started = os.clock()
	RunService:BindToRenderStep(name, Enum.RenderPriority.Camera.Value + 1, function()
		local t = os.clock() - started
		if t >= duration then
			RunService:UnbindFromRenderStep(name)
			return
		end
		local fade = 1 - t / duration
		local camera = Workspace.CurrentCamera
		if camera ~= nil then
			local x = (math.noise(t * 25, 0.3) * 2) * strength * fade
			local y = (math.noise(0.7, t * 25) * 2) * strength * fade
			camera.CFrame = camera.CFrame * CFrame.Angles(math.rad(y), math.rad(x), 0)
		end
	end)
end

local function nearLocalPlayer(position: Vector3, range: number): boolean
	local character = Players.LocalPlayer.Character
	local root = if character ~= nil then character:FindFirstChild("HumanoidRootPart") else nil
	return root ~= nil and root:IsA("BasePart") and (root.Position - position).Magnitude <= range
end

local function comet(target: Vector3, direction: Vector3)
	local folder = effectsFolder()
	local start = target - direction * 70 + Vector3.new(25, 170, 0)
	local head = glowPart(Vector3.one * 4, Color3.fromRGB(190, 230, 255))
	head.Position = start
	addTrail(head, Color3.fromRGB(255, 255, 255), Color3.fromRGB(255, 120, 220), 4, 0.9)
	local light = Instance.new("PointLight")
	light.Color = Color3.fromRGB(170, 210, 255)
	light.Range = 40
	light.Brightness = 3
	light.Parent = head
	local sparks = Instance.new("ParticleEmitter")
	sparks.Texture = SPARKLE
	sparks.Color = ColorSequence.new(Color3.fromRGB(255, 200, 250), Color3.fromRGB(140, 220, 255))
	sparks.LightEmission = 1
	sparks.Size = NumberSequence.new(0.8, 0)
	sparks.Lifetime = NumberRange.new(0.5, 0.9)
	sparks.Speed = NumberRange.new(2, 6)
	sparks.Rate = 60
	sparks.SpreadAngle = Vector2.new(180, 180)
	sparks.Parent = head
	head.Parent = folder
	AudioController.PlayAt(AudioConfig.Abilities.CometWhoosh, head, false, 300)

	local fall = TweenService:Create(head, TweenInfo.new(1.8, Enum.EasingStyle.Quad, Enum.EasingDirection.In), { Position = target })
	fall.Completed:Connect(function()
		sparks.Enabled = false
		head.Transparency = 1
		light.Enabled = false
		Debris:AddItem(head, 1)

		-- Flash
		local flash = glowPart(Vector3.one * 4, Color3.fromRGB(255, 255, 255))
		flash.Position = target
		flash.Parent = folder
		TweenService:Create(flash, TweenInfo.new(0.45), { Size = Vector3.one * 26, Transparency = 1 }):Play()
		Debris:AddItem(flash, 0.6)
		-- Shock ring
		local ring = glowPart(Vector3.new(0.3, 4, 4), Color3.fromRGB(150, 220, 255), Enum.PartType.Cylinder)
		ring.CFrame = CFrame.new(target + Vector3.new(0, 0.3, 0)) * CFrame.Angles(0, 0, math.rad(90))
		ring.Parent = folder
		TweenService:Create(ring, TweenInfo.new(0.9, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
			Size = Vector3.new(0.3, 60, 60),
			Transparency = 1,
		}):Play()
		Debris:AddItem(ring, 1)
		-- Glowing mark that slowly fades
		local mark = glowPart(Vector3.new(0.2, 9, 9), Color3.fromRGB(255, 140, 230), Enum.PartType.Cylinder)
		mark.CFrame = CFrame.new(target + Vector3.new(0, 0.12, 0)) * CFrame.Angles(0, 0, math.rad(90))
		mark.Transparency = 0.2
		mark.Parent = folder
		TweenService:Create(mark, TweenInfo.new(5, Enum.EasingStyle.Sine), { Transparency = 1 }):Play()
		Debris:AddItem(mark, 5.2)

		sparkleBurst(target + Vector3.new(0, 1, 0), Color3.fromRGB(200, 230, 255), 90)
		local soundHolder = glowPart(Vector3.one, Color3.new())
		soundHolder.Transparency = 1
		soundHolder.Position = target
		soundHolder.Parent = folder
		AudioController.PlayAt(AudioConfig.Abilities.CometImpact, soundHolder, false, 300)
		Debris:AddItem(soundHolder, 4)
		if nearLocalPlayer(target, SHAKE_RANGE) then
			shakeCamera(1.6, 0.6)
		end
	end)
	fall:Play()
end

local function starfall(center: Vector3)
	local family, pitch = ItemSounds.ForEvent("Starfall")
	for index = 0, 1 do -- falling shimmer, twice while the stars fall
		task.delay(index * 2.2, AudioController.PlayItem, family, pitch * (1 - index * 0.12), nil, 1)
	end
	local folder = effectsFolder()
	local random = Random.new()
	local skyHeight = center.Y + 190
	for index = 1, 26 do
		task.delay(index * 0.16 + random:NextNumber() * 0.2, function()
			local angle = random:NextNumber() * math.pi * 2
			local radius = random:NextNumber() * 160
			local from = Vector3.new(center.X + math.cos(angle) * radius, skyHeight + random:NextNumber() * 40, center.Z + math.sin(angle) * radius)
			local travel = Vector3.new(random:NextNumber(-1, 1), -0.35, random:NextNumber(-1, 1)).Unit * random:NextNumber(90, 140)
			local colors = { Color3.fromRGB(255, 240, 170), Color3.fromRGB(170, 220, 255), Color3.fromRGB(255, 170, 230) }
			local color = colors[random:NextInteger(1, #colors)]
			local star = glowPart(Vector3.one * 1.6, color)
			star.Position = from
			addTrail(star, Color3.new(1, 1, 1), color, 1.6, 0.7)
			star.Parent = folder
			local fly = TweenService:Create(star, TweenInfo.new(1.1 + random:NextNumber() * 0.5, Enum.EasingStyle.Linear), {
				Position = from + travel,
				Size = Vector3.one * 0.2,
			})
			fly:Play()
			Debris:AddItem(star, 2.4)
		end)
	end
end

local function rootOf(userId: any): BasePart?
	local player = if type(userId) == "number" then Players:GetPlayerByUserId(userId) else nil
	local character = if player ~= nil then player.Character else nil
	local root = if character ~= nil then character:FindFirstChild("HumanoidRootPart") else nil
	return if root ~= nil and root:IsA("BasePart") then root else nil
end

local function rocketJump(userId: any, direction: Vector3)
	local root = rootOf(userId)
	if root == nil then
		return
	end
	sparkleBurst(root.Position - Vector3.new(0, 2.5, 0), Color3.fromRGB(255, 150, 40), 40)
	AudioController.PlayAt(AudioConfig.Abilities.CometWhoosh, root, false, 90)
	if userId == Players.LocalPlayer.UserId then
		local humanoid = (root.Parent :: Instance):FindFirstChildOfClass("Humanoid")
		if humanoid ~= nil and not humanoid.Sit then
			humanoid:ChangeState(Enum.HumanoidStateType.Freefall)
			root.AssemblyLinearVelocity = direction * 45 + Vector3.new(0, 85, 0)
		end
	end
end

local PLASMA = { Color3.fromRGB(255, 120, 230), Color3.fromRGB(140, 110, 255), Color3.fromRGB(255, 220, 140) }

local function plasmaToast(userId: any, spots: { any })
	local root = rootOf(userId)
	local from = if root ~= nil then root.Position + Vector3.new(0, 1, 0) else nil
	if from == nil then
		return
	end
	sparkleBurst(from, PLASMA[1], 24)
	local family, pitch = ItemSounds.ForItem("plasma_toaster")
	AudioController.PlayItem(family, pitch, root, 1, 90)
	for index, spot in spots do
		if typeof(spot) ~= "Vector3" then
			continue
		end
		task.delay((index - 1) * 0.1, function()
			local pop, popPitch = ItemSounds.ForEvent("Toast")
			AudioController.PlayItem(pop, popPitch, root, 0.6, 90)
			local toast = glowPart(Vector3.new(1.5, 1.5, 0.4), PLASMA[1], Enum.PartType.Block)
			toast.Position = from
			addTrail(toast, PLASMA[1], PLASMA[2], 1.2, 0.5)
			toast.Parent = effectsFolder()
			local started = os.clock()
			local flight = 0.9 - (index - 1) * 0.1
			local connection: RBXScriptConnection
			connection = RunService.Heartbeat:Connect(function()
				local t = math.min((os.clock() - started) / flight, 1)
				local position = from:Lerp(spot + Vector3.new(0, 1.4, 0), t) + Vector3.new(0, math.sin(t * math.pi) * 8, 0)
				toast.CFrame = CFrame.new(position) * CFrame.Angles(t * 12, t * 7, 0)
				if t >= 1 then
					connection:Disconnect()
					sparkleBurst(position, PLASMA[2], 18)
					toast:Destroy()
				end
			end)
		end)
	end
end

-- Glow and sparkles on everybody who ate a plasma toast (Player attribute ToastedUntil).
function watchToasted()
	local effects: { [Player]: { Instance } } = {}
	local function update(player: Player)
		for _, instance in effects[player] or {} do
			instance:Destroy()
		end
		effects[player] = nil
		local root = rootOf(player.UserId)
		if type(player:GetAttribute("ToastedUntil")) ~= "number" or root == nil then
			return
		end
		local light = Instance.new("PointLight")
		light.Color = PLASMA[1]
		light.Range = 12
		light.Brightness = 0.8
		light.Parent = root
		local emitter = Instance.new("ParticleEmitter")
		emitter.Texture = SPARKLE
		emitter.Color = ColorSequence.new(PLASMA[1], PLASMA[2])
		emitter.LightEmission = 1
		emitter.Size = NumberSequence.new(0.7, 0)
		emitter.Lifetime = NumberRange.new(0.5, 0.9)
		emitter.Speed = NumberRange.new(2, 5)
		emitter.SpreadAngle = Vector2.new(180, 180)
		emitter.Rate = 22
		emitter.Parent = root
		effects[player] = { light, emitter }
		local bite, pitch = ItemSounds.ForEvent("Eat")
		AudioController.PlayItem(bite, pitch, root, 1, 60)
	end
	local function watch(player: Player)
		player:GetAttributeChangedSignal("ToastedUntil"):Connect(function()
			update(player)
		end)
		update(player)
	end
	Players.PlayerAdded:Connect(watch)
	Players.PlayerRemoving:Connect(function(player: Player)
		effects[player] = nil
	end)
	for _, player in Players:GetPlayers() do
		watch(player)
	end
end

local DRAGON_SECONDS = 20

-- A baby ice dragon circles its owner and leaves frost behind (drawn by every client).
local function dragonCall(userId: any)
	local first = rootOf(userId)
	if first == nil then
		return
	end
	local folder = Instance.new("Folder")
	folder.Name = "Dragon"
	folder.Parent = effectsFolder()
	local function limb(size: Vector3, color: Color3): Part
		local p = glowPart(size, color, Enum.PartType.Block)
		p.Material = Enum.Material.SmoothPlastic
		p.Parent = folder
		return p
	end
	local ice, light, wing = Color3.fromRGB(110, 210, 255), Color3.fromRGB(170, 238, 255), Color3.fromRGB(255, 110, 190)
	local body, head, snout = limb(Vector3.new(1, 0.9, 2), ice), limb(Vector3.new(0.9, 0.8, 0.9), light), limb(Vector3.new(0.5, 0.4, 0.5), light)
	local tail, left, right = limb(Vector3.new(0.35, 0.35, 1.6), ice), limb(Vector3.new(2, 0.1, 1.1), wing), limb(Vector3.new(2, 0.1, 1.1), wing)
	addTrail(body, light, ice, 0.8, 1)
	sparkleBurst(first.Position, light, 40)
	local family, pitch = ItemSounds.ForEvent("Dragon")
	AudioController.PlayItem(family, pitch, first, 1, 80)
	local started = os.clock()
	local connection: RBXScriptConnection
	connection = RunService.Heartbeat:Connect(function()
		local t = os.clock() - started
		local root = rootOf(userId)
		if root == nil or t >= DRAGON_SECONDS then
			connection:Disconnect()
			if root ~= nil then
				sparkleBurst(body.Position, light, 30)
			end
			folder:Destroy()
			return
		end
		local angle = t * 2
		local grow = math.min(t, 1) * math.min(DRAGON_SECONDS - t, 1)
		local offset = Vector3.new(math.cos(angle) * 6 * grow, 3 + math.sin(t * 1.7) * 1.2, math.sin(angle) * 6 * grow)
		local cf = CFrame.lookAlong(root.Position + offset, Vector3.new(-math.sin(angle), math.cos(t * 1.7) * 0.2, math.cos(angle))) * CFrame.Angles(0, 0, 0.3)
		local flap = math.sin(t * 11) * 0.7
		body.CFrame = cf
		head.CFrame = cf * CFrame.new(0, 0.45, -1.3)
		snout.CFrame = cf * CFrame.new(0, 0.3, -1.95)
		tail.CFrame = cf * CFrame.new(0, 0.1, 1.7) * CFrame.Angles(0, math.sin(t * 6) * 0.35, 0)
		left.CFrame = cf * CFrame.new(-0.45, 0.35, 0) * CFrame.Angles(0, 0, -flap) * CFrame.new(-1, 0, 0)
		right.CFrame = cf * CFrame.new(0.45, 0.35, 0) * CFrame.Angles(0, 0, flap) * CFrame.new(1, 0, 0)
	end)
end

local function magnetPulse(userId: any)
	local root = rootOf(userId)
	if root == nil then
		return
	end
	AudioController.PlayAt(AudioConfig.Abilities.StarChime, root, false, 60)
	local ring = glowPart(Vector3.new(0.3, 56, 56), Color3.fromRGB(255, 90, 80), Enum.PartType.Cylinder)
	ring.Transparency = 0.7
	ring.CFrame = CFrame.new(root.Position - Vector3.new(0, 2.5, 0)) * CFrame.Angles(0, 0, math.rad(90))
	ring.Parent = effectsFolder()
	TweenService:Create(ring, TweenInfo.new(0.5), { Size = Vector3.new(0.3, 4, 4), Transparency = 1 }):Play()
	Debris:AddItem(ring, 0.7)
end

function Abilities.Start()
	watchToasted()
	Remotes.GetEvent("AbilityFx").OnClientEvent:Connect(function(payload: any)
		if type(payload) ~= "table" or typeof(payload.Position) ~= "Vector3" then
			return
		end
		if not nearLocalPlayer(payload.Position, VIEW_RANGE) then
			return -- too far to see it
		end
		local direction = if typeof(payload.Direction) == "Vector3" then payload.Direction else Vector3.new(0, 0, -1)
		if payload.Effect == "Comet" then
			comet(payload.Position, direction)
		elseif payload.Effect == "Starfall" then
			starfall(payload.Position)
		elseif payload.Effect == "RocketJump" then
			rocketJump(payload.UserId, direction)
		elseif payload.Effect == "DragonCall" then
			dragonCall(payload.UserId)
		elseif payload.Effect == "Magnet" then
			magnetPulse(payload.UserId)
		elseif payload.Effect == "PlasmaToast" and type(payload.Spots) == "table" then
			plasmaToast(payload.UserId, payload.Spots)
		end
	end)
end

return Abilities
