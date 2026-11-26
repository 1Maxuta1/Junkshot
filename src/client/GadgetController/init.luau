--!strict
--[[
	GadgetController: draws what placed gadgets do (server: Behaviors/Gadget decides the state).
	Local only, nothing is sent to the server. Models closer than RANGE get an effect; it is
	removed again when the model is picked up, streamed out or far away.

	Attributes read from the model
	  Gadget        effect name (key of Effects)        GadgetMode  index into the config's Modes
	  GadgetFire    counts up, one burst each           ScreenText / Speech / HoloId  see Gadget

	A running Generator powers every gadget within POWER_RANGE: stronger light, bigger effects,
	higher jumps on the spring launcher.

	Adding an effect: Effects.<Name> = function(ctx) ... return update(time, mode, powered) end
	  ctx.Track(instance) destroys it together with the effect.
]]

local Debris = game:GetService("Debris")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local AudioConfig = require(ReplicatedStorage.Shared.Config.AudioConfig)
local Behaviors = require(ReplicatedStorage.Shared.Config.Behaviors)
local ItemSounds = require(ReplicatedStorage.Shared.Config.ItemSounds)
local JunkFactory = require(ReplicatedStorage.Shared.Util.JunkFactory)
local PlacementRules = require(ReplicatedStorage.Shared.Util.PlacementRules)
local RaceConfig = require(ReplicatedStorage.Shared.Config.RaceConfig)

local AudioController = require(script.Parent.AudioController)

local GadgetController = {}

local RANGE = 140
local LITE_RANGE = 60 -- with Lite graphics
local POWER_RANGE = 25
local DANCE_RANGE = 18
local DANCE_ANIMATION = "rbxassetid://507771019"
local SPARKLE = "rbxasset://textures/particles/sparkles_main.dds"
local SMOKE = "rbxasset://textures/particles/smoke_main.dds"

local localPlayer = Players.LocalPlayer
local rgb = Color3.fromRGB

type Update = (time: number, mode: number, powered: boolean) -> ()
type Context = { Model: Model, Base: BasePart, Folder: Folder, Track: (Instance) -> () }
type Active = { Context: Context, Update: Update, Tracked: { Instance }, Powered: boolean, OnStop: { () -> () } }

local active: { [Model]: Active } = {}
local dancingNear = false -- set by the disco effect every frame

---------------------------------------------------------------------------------------------
-- Helpers
---------------------------------------------------------------------------------------------

local function effectsFolder(): Instance
	local existing = Workspace:FindFirstChild("ClientEffects")
	if existing ~= nil then
		return existing
	end
	local folder = Instance.new("Folder")
	folder.Name = "ClientEffects"
	folder.Parent = Workspace
	return folder
end

local function piece(parent: Instance, shape: Enum.PartType, size: Vector3, color: Color3, transparency: number?): Part
	local part = Instance.new("Part")
	part.Shape = shape
	part.Size = size
	part.Color = color
	part.Material = Enum.Material.Neon
	part.Transparency = transparency or 0
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.CastShadow = false
	part.Parent = parent
	return part
end

local function emitter(parent: Instance, texture: string, props: { [string]: any }): ParticleEmitter
	local e = Instance.new("ParticleEmitter")
	e.Texture = texture
	e.LightEmission = 0.6
	e.Enabled = false
	for key, value in props do
		(e :: any)[key] = value
	end
	e.Parent = parent
	return e
end

local function part(ctx: Context, index: number): BasePart
	local found = ctx.Model:FindFirstChild(`Part{index}`)
	return if found ~= nil and found:IsA("BasePart") then found else ctx.Base
end

local function pointLight(ctx: Context, parent: Instance, color: Color3): PointLight
	local light = Instance.new("PointLight")
	light.Color = color
	light.Enabled = false
	light.Parent = parent
	ctx.Track(light)
	return light
end

local function top(ctx: Context): Vector3
	local cf, size = ctx.Model:GetBoundingBox()
	return cf.Position + Vector3.new(0, size.Y / 2, 0)
end

local function liveRoot(): (BasePart?, Humanoid?)
	local character = localPlayer.Character
	local root = if character ~= nil then character:FindFirstChild("HumanoidRootPart") else nil
	local humanoid = if character ~= nil then character:FindFirstChildOfClass("Humanoid") else nil
	if root ~= nil and root:IsA("BasePart") and humanoid ~= nil and humanoid.Health > 0 then
		return root, humanoid
	end
	return nil, nil
end

local function burst(position: Vector3, colors: { Color3 }, count: number, speed: number)
	local holder = piece(effectsFolder(), Enum.PartType.Ball, Vector3.one, colors[1], 1)
	holder.Position = position
	for _, color in colors do
		local e = emitter(holder, SPARKLE, {
			Color = ColorSequence.new(color),
			Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1.5), NumberSequenceKeypoint.new(1, 0) }),
			Lifetime = NumberRange.new(0.8, 1.7),
			Speed = NumberRange.new(speed * 0.5, speed),
			SpreadAngle = Vector2.new(180, 180),
			Acceleration = Vector3.new(0, -22, 0),
			Rate = 0,
			LightEmission = 1,
		})
		e:Emit(math.ceil(count / #colors))
	end
	Debris:AddItem(holder, 2.5)
end

-- Something flies up from `from`, then bursts.
local function rocket(from: Vector3, height: number, size: Vector3, color: Color3, colors: { Color3 }, count: number, onBurst: ((Vector3) -> ())?)
	local shot = piece(effectsFolder(), Enum.PartType.Block, size, color)
	shot.Position = from
	local target = from + Vector3.new(math.random(-6, 6), height, math.random(-6, 6))
	local rise = TweenService:Create(shot, TweenInfo.new(0.9, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		Position = target,
		Orientation = Vector3.new(math.random(180, 720), math.random(0, 360), 0),
	})
	rise.Completed:Connect(function()
		shot:Destroy()
		burst(target, colors, count, 30)
		if onBurst ~= nil then
			onBurst(target)
		end
	end)
	rise:Play()
	Debris:AddItem(shot, 3)
end

local function ping(parent: Instance, pitch: number, volume: number?)
	local spec = table.clone(AudioConfig.Abilities.StarChime) :: any
	spec.Pitch = pitch
	spec.Volume = volume or spec.Volume
	AudioController.PlayAt(spec, parent, false, 60)
end

local function screenLabel(ctx: Context, screenPart: BasePart): TextLabel
	local gui = Instance.new("SurfaceGui")
	gui.Face = Enum.NormalId.Front
	gui.CanvasSize = Vector2.new(400, math.floor(400 * screenPart.Size.Y / screenPart.Size.X))
	gui.LightInfluence = 0
	gui.ClipsDescendants = true
	local label = Instance.new("TextLabel")
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundColor3 = rgb(16, 20, 36)
	label.BorderSizePixel = 0
	label.Font = Enum.Font.FredokaOne
	label.TextColor3 = rgb(255, 255, 255)
	label.TextScaled = true
	label.Text = ""
	label.Parent = gui
	local padding = Instance.new("UIPadding")
	padding.PaddingLeft = UDim.new(0.06, 0)
	padding.PaddingRight = UDim.new(0.06, 0)
	padding.PaddingTop = UDim.new(0.08, 0)
	padding.PaddingBottom = UDim.new(0.08, 0)
	padding.Parent = label
	gui.Parent = screenPart
	ctx.Track(gui)
	return label
end

-- Runs `fn` for every new burst (not for the ones from before we came close).
local function onFire(ctx: Context, fn: (powered: boolean) -> ())
	local connection = ctx.Model:GetAttributeChangedSignal("GadgetFire"):Connect(function()
		local state = active[ctx.Model]
		fn(state ~= nil and state.Powered)
	end)
	local state = { connection }
	ctx.Model.Destroying:Once(function()
		state[1]:Disconnect()
	end)
	ctx.Folder.Destroying:Once(function()
		state[1]:Disconnect()
	end)
end

local function clock(seconds: number): string
	local left = math.max(0, math.floor(seconds))
	return string.format("%d:%02d", left // 60, left % 60)
end

local function nothing() end

---------------------------------------------------------------------------------------------
-- Effects
---------------------------------------------------------------------------------------------

local Effects: { [string]: (ctx: Context) -> Update } = {}

local PANEL_COLORS = { rgb(150, 220, 230), rgb(60, 130, 255), rgb(240, 70, 80), rgb(255, 205, 60), rgb(80, 220, 120), rgb(40, 44, 60) }

function Effects.Panel(ctx)
	return function(_, mode)
		ctx.Base.Color = PANEL_COLORS[mode] or PANEL_COLORS[1]
	end
end

local CARTOON = { "🦊      🗑️", "  🦊    🗑️", "    🦊  🗑️", "      🦊🗑️", "      💥", "      🦊✨" }

local function newsLine(page: number): string
	if page == 0 then
		return `YARD NEWS\n{#Players:GetPlayers()} scrappers in the yard`
	elseif page == 1 then
		local at = Workspace:GetAttribute("JunkRefillAt")
		local left = if type(at) == "number" then at - Workspace:GetServerTimeNow() else 0
		return `YARD NEWS\nNew scrap in {clock(left)}`
	end
	return "YARD NEWS\nThe fox is watching you"
end

local function raceLine(): string
	local state = Workspace:GetAttribute("RaceState")
	if state == "Countdown" or state == "Racing" then
		return "🏁 LIVE\nThe race is on!"
	end
	local left = RaceConfig.Interval - Workspace:GetServerTimeNow() % RaceConfig.Interval
	return `🏁 NEXT RACE\n{clock(left)}`
end

function Effects.Television(ctx)
	local screenPart = part(ctx, 2)
	local label = screenLabel(ctx, screenPart)
	local light = pointLight(ctx, screenPart, rgb(120, 190, 255))
	return function(t, mode, powered)
		light.Enabled = mode > 1
		light.Range, light.Brightness = if powered then 18 else 11, if powered then 0.8 else 0.5
		label.BackgroundColor3 = if mode == 5 then Color3.fromHSV(t * 0.4 % 1, 0.8, 1) else rgb(16, 20, 36)
		if mode == 2 then
			label.Text = newsLine(math.floor(t / 4) % 3)
		elseif mode == 3 then
			label.Text = raceLine()
		elseif mode == 4 then
			label.Text = CARTOON[math.floor(t * 2) % #CARTOON + 1]
		elseif mode == 5 then
			label.Text = if math.floor(t * 2) % 2 == 0 then "★ PARTY ★" else "☆ PARTY ☆"
			light.Color = label.BackgroundColor3
		else
			label.Text = ""
		end
		if mode ~= 5 then
			light.Color = rgb(120, 190, 255)
		end
	end
end

function Effects.Disco(ctx)
	local ball = part(ctx, 2)
	local home = ball.CFrame
	-- The mirror tiles on the ball turn with it (everything close to the ball's surface).
	local tiles: { { Part: BasePart, Offset: CFrame } } = {}
	local reach = ball.Size.X / 2 * 1.15
	for _, child in ctx.Model:GetChildren() do
		if child:IsA("BasePart") and child ~= ball and child ~= ctx.Base and (child.Position - home.Position).Magnitude <= reach then
			table.insert(tiles, { Part = child, Offset = home:ToObjectSpace(child.CFrame) })
		end
	end
	local light = pointLight(ctx, ball, rgb(255, 255, 255))
	local rays = {}
	for index = 1, 8 do
		local ray = piece(ctx.Folder, Enum.PartType.Cylinder, Vector3.new(16, 0.35, 0.35), rgb(255, 255, 255), 0.75)
		table.insert(rays, { Part = ray, Yaw = index / 8 * math.pi * 2, Pitch = if index % 2 == 0 then 0.35 else -0.2 })
	end
	local sparkle = emitter(ball, SPARKLE, { Rate = 14, Speed = NumberRange.new(4, 8), SpreadAngle = Vector2.new(180, 180), Lifetime = NumberRange.new(0.6, 1.2), Size = NumberSequence.new(0.6, 0) })
	ctx.Track(sparkle)
	return function(t, mode, powered)
		local on = mode == 2
		light.Enabled = on
		sparkle.Enabled = on
		ball.CFrame = home * CFrame.Angles(0, if on then t * 1.5 else 0, 0)
		for _, tile in tiles do
			tile.Part.CFrame = ball.CFrame * tile.Offset
		end
		local scale = if powered then 1.5 else 1
		for index, ray in rays do
			ray.Part.Transparency = if on then 0.72 else 1
			if on then
				ray.Part.Color = Color3.fromHSV((t * 0.25 + index / 8) % 1, 0.75, 1)
				ray.Part.Size = Vector3.new(16 * scale, 0.35, 0.35)
				ray.Part.CFrame = CFrame.new(home.Position) * CFrame.Angles(0, ray.Yaw + t * 0.8, 0)
					* CFrame.Angles(0, 0, ray.Pitch + math.sin(t * 1.3 + index) * 0.25) * CFrame.new(8 * scale, 0, 0)
			end
		end
		if on then
			light.Color = Color3.fromHSV(t * 0.25 % 1, 0.7, 1)
			light.Range, light.Brightness = 20 * scale, 0.7 * scale
			local root = liveRoot()
			if root ~= nil and (root.Position - home.Position).Magnitude < DANCE_RANGE then
				dancingNear = true
			end
		end
	end
end

function Effects.Fountain(ctx)
	local pool = part(ctx, 2)
	local duck = { part(ctx, 3), part(ctx, 4), part(ctx, 5) }
	local homes = {}
	for index, p in duck do
		homes[index] = p.CFrame
	end
	local center = pool.Position
	local radius = math.max(pool.Size.Y, pool.Size.Z) / 2 - duck[1].Size.X * 0.55
	local nozzle = Instance.new("Attachment")
	nozzle.Parent = ctx.Base
	nozzle.WorldCFrame = CFrame.new(center + Vector3.new(0, 0.4, 0))
	ctx.Track(nozzle)
	local water = emitter(nozzle, SPARKLE, {
		Rate = 60, Speed = NumberRange.new(12, 16), SpreadAngle = Vector2.new(12, 12), Acceleration = Vector3.new(0, -32, 0),
		Lifetime = NumberRange.new(0.7, 1), Size = NumberSequence.new(0.5, 0.2), Color = ColorSequence.new(rgb(120, 200, 255)),
	})
	local sound = Instance.new("Sound")
	sound.Name = "Fountain"
	sound.SoundId = "rbxassetid://9120557577" -- "Water Fountain 2", ProSoundEffects
	sound.Looped = true
	sound.Volume = 0.12
	sound.PlaybackSpeed = 1.15 -- smaller fountain
	sound.RollOffMinDistance = 5
	sound.RollOffMaxDistance = 40
	sound.Parent = ctx.Base
	ctx.Track(sound)
	local swum = 0
	local last: number? = nil
	return function(t, mode, powered)
		local on = mode > 1
		water.Enabled = on
		water.Speed = if powered then NumberRange.new(20, 25) else NumberRange.new(12, 16)
		water.Color = ColorSequence.new(if mode == 3 then Color3.fromHSV(t * 0.3 % 1, 0.7, 1) else rgb(120, 200, 255))
		if on ~= sound.Playing then
			sound.Playing = on
		end
		-- The duck swims in circles, bobbing, with its beak forward.
		swum += if on and last ~= nil then math.clamp(t - last, 0, 0.1) else 0
		last = t
		for index, p in duck do
			if on then
				local angle = swum * 0.9
				local swim = CFrame.new(center) * CFrame.Angles(0, angle, 0) * CFrame.new(radius, math.sin(swum * 4) * 0.12, 0)
				p.CFrame = swim * CFrame.new(center):ToObjectSpace(homes[index] - Vector3.new(0, 0.35, 0))
			else
				p.CFrame = homes[index]
			end
		end
	end
end

function Effects.SnowMachine(ctx)
	local cloud = piece(ctx.Folder, Enum.PartType.Block, Vector3.new(22, 1, 22), rgb(255, 255, 255), 1)
	cloud.Position = top(ctx) + Vector3.new(0, 13, 0)
	local snow = emitter(cloud, SPARKLE, {
		Rate = 60, Speed = NumberRange.new(5, 8), EmissionDirection = Enum.NormalId.Bottom, Lifetime = NumberRange.new(2.2, 3),
		Size = NumberSequence.new(0.5), SpreadAngle = Vector2.new(15, 15),
	})
	local puff = emitter(part(ctx, 3), SMOKE, { Rate = 6, Speed = NumberRange.new(10, 14), Lifetime = NumberRange.new(1, 1.4), Size = NumberSequence.new(0.6, 2), Transparency = NumberSequence.new(0.4, 1) })
	ctx.Track(puff)
	return function(_, mode, powered)
		snow.Enabled, puff.Enabled = mode > 1, mode > 1
		snow.Rate = (if mode == 3 then 170 else 60) * (if powered then 1.4 else 1)
		snow.Acceleration = if mode == 3 then Vector3.new(7, 0, 3) else Vector3.zero
	end
end

local LAMP = { rgb(150, 215, 255), rgb(150, 215, 255), rgb(255, 215, 140), rgb(190, 120, 255) }

function Effects.Lamp(ctx)
	local bulb = part(ctx, 2)
	local light = pointLight(ctx, bulb, LAMP[1])
	return function(_, mode, powered)
		light.Enabled = mode > 1
		light.Color = LAMP[mode] or LAMP[1]
		light.Range, light.Brightness = if powered then 40 else 28, if powered then 1 else 0.6
		bulb.Color = light.Color
		bulb.Material = if mode > 1 then Enum.Material.Neon else Enum.Material.SmoothPlastic
	end
end

local SCALE = { 1, 1.125, 1.25, 1.5, 1.667, 2 }

function Effects.Band(ctx)
	local parts = { part(ctx, 2), part(ctx, 3), part(ctx, 4), part(ctx, 5) }
	local homes = {}
	for index, p in parts do
		homes[index] = p.CFrame
	end
	local lastBeat = -1
	return function(t, mode)
		local on = mode == 2
		for index, p in parts do
			local phase = if index <= 2 then 0 else math.pi
			local lift = if on then math.abs(math.sin(t * 5 + phase)) * 0.5 else 0
			local sway = if on then math.sin(t * 5 + phase) * 0.25 else 0
			p.CFrame = homes[index] * CFrame.new(0, lift, 0) * CFrame.Angles(0, sway, 0)
		end
		local beat = math.floor(t * 3)
		if on and beat ~= lastBeat then
			-- the same little tune for everybody (from the beat number, not random)
			local note = SCALE[(beat * 5 + math.floor(beat / 4) * 2) % #SCALE + 1]
			if beat % 4 ~= 3 then
				ping(ctx.Base, note, 0.18)
			end
		end
		lastBeat = beat
	end
end

local BEAM = { rgb(255, 255, 255), rgb(190, 120, 255), rgb(90, 170, 255), rgb(255, 205, 70) }

function Effects.Beacon(ctx)
	local beam = piece(ctx.Folder, Enum.PartType.Cylinder, Vector3.new(200, 1.6, 1.6), BEAM[2], 1)
	beam.CFrame = CFrame.new(top(ctx) + Vector3.new(0, 100, 0)) * CFrame.Angles(0, 0, math.pi / 2)
	local light = pointLight(ctx, part(ctx, 2), BEAM[2])
	return function(t, mode, powered)
		local on = mode > 1
		light.Enabled = on
		beam.Transparency = if on then 0.6 + math.sin(t * 2) * 0.08 else 1
		beam.Color, light.Color = BEAM[mode] or BEAM[1], BEAM[mode] or BEAM[1]
		local width = if powered then 3 else 1.6
		beam.Size = Vector3.new(200, width, width)
		light.Range, light.Brightness = if powered then 26 else 18, 0.6
	end
end

function Effects.Generator(ctx)
	local home = ctx.Base.CFrame
	local smoke = emitter(part(ctx, 2), SMOKE, { Rate = 8, Speed = NumberRange.new(3, 5), Lifetime = NumberRange.new(1, 1.6), Size = NumberSequence.new(0.5, 1.6), Transparency = NumberSequence.new(0.5, 1), Color = ColorSequence.new(rgb(150, 230, 120)) })
	ctx.Track(smoke)
	local light = pointLight(ctx, part(ctx, 3), rgb(80, 255, 140))
	local ring = piece(ctx.Folder, Enum.PartType.Cylinder, Vector3.new(0.08, POWER_RANGE * 2, POWER_RANGE * 2), rgb(80, 255, 140), 1)
	ring.CFrame = CFrame.new(ctx.Model:GetPivot().Position + Vector3.new(0, 0.1, 0)) * CFrame.Angles(0, 0, math.pi / 2)
	local startedAt: number? = nil
	local motor = Instance.new("Sound")
	motor.Name = "Motor"
	motor.SoundId = "rbxassetid://80317022777602"
	motor.Looped = true
	motor.Volume = 0.22
	motor.PlaybackSpeed = 0.6 -- a slow, heavy engine
	motor.RollOffMinDistance = 6
	motor.RollOffMaxDistance = 55
	motor.Parent = ctx.Base
	ctx.Track(motor)
	return function(t, mode)
		local on = mode == 2
		if on ~= motor.Playing then
			motor.Playing = on
		end
		smoke.Enabled, light.Enabled = on, on
		light.Range = 10
		ctx.Base.CFrame = home * CFrame.new(0, if on then math.sin(t * 40) * 0.03 else 0, 0)
		-- shows its reach for two seconds after it was started
		startedAt = if on then startedAt or t else nil
		ring.Transparency = if startedAt ~= nil and t - startedAt < 2 then 0.8 + (t - startedAt) * 0.1 else 1
	end
end

function Effects.Reactor(ctx)
	local base = top(ctx)
	local light = pointLight(ctx, part(ctx, 3), rgb(120, 255, 200))
	local beams = {}
	for index = 1, 4 do
		local a = piece(ctx.Folder, Enum.PartType.Ball, Vector3.one, rgb(255, 255, 255), 1)
		local b = piece(ctx.Folder, Enum.PartType.Ball, Vector3.one, rgb(255, 255, 255), 1)
		a.Position = base + Vector3.new(-60, 55 + index * 4, (index - 2.5) * 16)
		b.Position = base + Vector3.new(60, 55 + index * 4, (index - 2.5) * 16)
		local a0, a1 = Instance.new("Attachment"), Instance.new("Attachment")
		a0.Parent, a1.Parent = a, b
		local beam = Instance.new("Beam")
		beam.Attachment0, beam.Attachment1 = a0, a1
		beam.Width0, beam.Width1 = 14, 14
		beam.Segments = 30
		beam.LightEmission = 1
		beam.FaceCamera = true
		beam.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(0.5, 0.55), NumberSequenceKeypoint.new(1, 1) })
		beam.Parent = a
		table.insert(beams, beam)
	end
	local core = part(ctx, 3)
	-- The aura: a huge bubble you can walk through (inside everything is slow, SlowFieldService),
	-- it grows when the reactor starts; motes drift slowly around in it.
	local field = (Behaviors :: any)["Deploy.Reactor"].Gadget.SlowField
	local center = ctx.Model:GetBoundingBox().Position
	local bubble = piece(ctx.Folder, Enum.PartType.Ball, Vector3.one, rgb(120, 255, 210), 1)
	bubble.Material = Enum.Material.ForceField
	local glow = piece(ctx.Folder, Enum.PartType.Ball, Vector3.one, rgb(150, 220, 255), 1)
	bubble.Position, glow.Position = center, center
	local rim = {}
	for index = 1, 28 do
		rim[index] = piece(ctx.Folder, Enum.PartType.Ball, Vector3.one * (if index <= 20 then 0.9 else 0.6), rgb(150, 255, 220), 1)
	end
	local size, lastT = 0, nil :: number?
	local function drawField(t: number, on: boolean)
		local dt = math.clamp(t - (lastT or t), 0, 0.1)
		lastT = t
		size += ((if on then 1 else 0) - size) * math.min(dt * (if on then 3 else 6), 1)
		local shown = size > 0.02
		local radius = field.Radius * size
		local color = Color3.fromHSV((0.42 + math.sin(t * 0.35) * 0.12) % 1, 0.55, 1)
		bubble.Transparency = if shown then 0.1 else 1
		glow.Transparency = if shown then 0.94 else 1
		if not shown then
			for _, mote in rim do
				mote.Transparency = 1
			end
			return
		end
		local breath = 1 + math.sin(t * 1.4) * 0.008
		bubble.Size = Vector3.one * radius * 2 * breath
		glow.Size = Vector3.one * radius * 1.97
		bubble.Color, glow.Color = color, color
		for index, mote in rim do
			mote.Transparency = 0.15
			mote.Color = Color3.fromHSV((0.4 + index * 0.02 + t * 0.03) % 1, 0.5, 1)
			if index <= 20 then -- ring where the bubble meets the ground
				local a = index / 20 * math.pi * 2 + t * 0.15
				local low = math.min(center.Y - 0.4, radius * 0.95) -- the ground is about y 0.4
				local flat = math.sqrt(math.max(radius * radius - low * low, 0))
				mote.Position = center + Vector3.new(math.cos(a) * flat, -low, math.sin(a) * flat)
			else -- slow wanderers inside
				local a, h = t * 0.12 + index * 1.7, math.sin(t * 0.2 + index * 2.3)
				mote.Position = center + Vector3.new(math.cos(a) * 0.6, 0.25 + h * 0.3, math.sin(a) * 0.6) * radius
			end
		end
	end
	return function(t, mode, powered)
		local on = mode == 2
		drawField(t, on)
		light.Enabled = on
		light.Range, light.Brightness = 22, if powered then 1 else 0.6
		core.Color = if on then Color3.fromHSV(0.4 + math.sin(t) * 0.15, 0.7, 1) else rgb(255, 80, 180)
		for index, beam in beams do
			beam.Enabled = on
			beam.CurveSize0 = math.sin(t * 0.5 + index) * 30
			beam.CurveSize1 = math.cos(t * 0.4 + index) * 30
			beam.Color = ColorSequence.new(Color3.fromHSV((0.36 + index * 0.06 + math.sin(t * 0.2) * 0.1) % 1, 0.75, 1), Color3.fromHSV((0.75 + index * 0.04) % 1, 0.7, 1))
			beam.Width0 = if powered then 20 else 14
			beam.Width1 = beam.Width0
		end
	end
end

function Effects.Gate(ctx)
	local disc = part(ctx, 2)
	local center = disc.CFrame
	local light = pointLight(ctx, disc, rgb(255, 220, 120))
	local stars = {}
	for index = 1, 12 do
		local star = piece(ctx.Folder, Enum.PartType.Ball, Vector3.one * 0.5, rgb(255, 255, 255), 1)
		stars[index] = star
	end
	local swirl = emitter(disc, SPARKLE, { Rate = 25, Speed = NumberRange.new(3, 7), SpreadAngle = Vector2.new(180, 180), Lifetime = NumberRange.new(1, 2), Size = NumberSequence.new(0.8, 0) })
	ctx.Track(swirl)
	return function(t, mode, powered)
		local on = mode > 1
		local color = if mode == 3 then rgb(255, 120, 220) else rgb(255, 215, 110)
		disc.Material = if on then Enum.Material.Neon else Enum.Material.Glass
		disc.Color = if on then color:Lerp(rgb(60, 40, 110), 0.5 + math.sin(t * 2) * 0.3) else rgb(60, 40, 110)
		light.Enabled, swirl.Enabled = on, on
		light.Color, light.Range, light.Brightness = color, 22, 0.7
		swirl.Color = ColorSequence.new(color)
		local radius = if powered then 8 else 5
		for index, star in stars do
			star.Transparency = if on then 0 else 1
			star.Color = color
			local angle = t * 1.2 + index / #stars * math.pi * 2
			star.CFrame = center * CFrame.Angles(math.sin(t * 0.5) * 0.4, 0, 0)
				* CFrame.new(math.sin(t * 2 + index) * 0.8, math.cos(angle) * radius, math.sin(angle) * radius)
		end
	end
end

function Effects.Incubator(ctx)
	local egg = part(ctx, 2)
	local home = egg.Position
	-- A little polar dragon (client-only parts, ~30 of them, only while it flies): body with a
	-- pale belly, a neck, head with snout, horns and glowing eyes, spikes on the back, a
	-- swaying three-part tail with a spade, tucked legs and two-part wings that flap.
	local scales, belly, bone, membrane = rgb(120, 220, 255), rgb(225, 248, 255), rgb(50, 70, 130), rgb(170, 140, 255)
	local all: { BasePart } = {}
	local function make(size: Vector3, color: Color3, shape: Enum.PartType?, material: Enum.Material?, see: number?): BasePart
		local p = piece(ctx.Folder, shape or Enum.PartType.Block, size, color)
		p.Material = material or Enum.Material.SmoothPlastic
		p:SetAttribute("Shown", see or 0)
		table.insert(all, p)
		return p
	end
	local Ball = Enum.PartType.Ball
	-- fixed to the body: { part, offset }
	local fixed: { { any } } = {
		{ make(Vector3.new(1, 0.9, 2), scales), CFrame.identity },
		{ make(Vector3.new(0.8, 0.3, 1.7), belly), CFrame.new(0, -0.4, 0) },
		{ make(Vector3.new(1.1, 1.1, 1.1), scales, Ball), CFrame.new(0, 0.05, -0.8) },
		{ make(Vector3.new(0.55, 0.55, 0.9), scales), CFrame.new(0, 0.45, -1.35) * CFrame.Angles(math.rad(30), 0, 0) },
		{ make(Vector3.new(0.75, 0.6, 0.85), scales), CFrame.new(0, 0.85, -1.85) },
		{ make(Vector3.new(0.5, 0.38, 0.55), belly), CFrame.new(0, 0.75, -2.4) },
		{ make(Vector3.new(0.12, 0.12, 0.6), rgb(250, 250, 255)), CFrame.new(-0.22, 1.2, -1.55) * CFrame.Angles(math.rad(-35), 0, 0) },
		{ make(Vector3.new(0.12, 0.12, 0.6), rgb(250, 250, 255)), CFrame.new(0.22, 1.2, -1.55) * CFrame.Angles(math.rad(-35), 0, 0) },
		{ make(Vector3.new(0.16, 0.16, 0.16), rgb(255, 230, 90), Ball, Enum.Material.Neon), CFrame.new(-0.3, 0.95, -2.1) },
		{ make(Vector3.new(0.16, 0.16, 0.16), rgb(255, 230, 90), Ball, Enum.Material.Neon), CFrame.new(0.3, 0.95, -2.1) },
	}
	for _, z in { -0.5, 0, 0.5 } do
		table.insert(fixed, { make(Vector3.new(0.25, 0.25, 0.25), rgb(240, 250, 255)), CFrame.new(0, 0.5, z) * CFrame.Angles(math.rad(45), 0, 0) })
	end
	for _, x in { -0.42, 0.42 } do
		for _, z in { -0.6, 0.6 } do
			table.insert(fixed, { make(Vector3.new(0.25, 0.5, 0.3), scales), CFrame.new(x, -0.55, z) * CFrame.Angles(math.rad(40), 0, 0) })
		end
	end
	local tail = { make(Vector3.new(0.5, 0.45, 0.9), scales), make(Vector3.new(0.35, 0.32, 0.85), scales), make(Vector3.new(0.22, 0.2, 0.8), scales) }
	local spade = make(Vector3.new(0.5, 0.08, 0.5), membrane, nil, Enum.Material.Neon)
	local wings = {}
	for _, s in { -1, 1 } do
		table.insert(wings, {
			Side = s,
			InnerBone = make(Vector3.new(1.4, 0.14, 0.14), bone),
			Inner = make(Vector3.new(1.4, 0.05, 1.0), membrane, nil, nil, 0.15),
			OuterBone = make(Vector3.new(1.3, 0.12, 0.12), bone),
			Outer = make(Vector3.new(1.3, 0.05, 0.8), membrane, nil, nil, 0.15),
		})
	end
	return function(t, mode, powered)
		local on = mode == 2
		egg.Transparency = if on then 0.8 else 0
		for _, p in all do
			p.Transparency = if on then p:GetAttribute("Shown") :: number else 1
		end
		if not on then
			return
		end
		local radius = if powered then 14 else 9
		local angle = t * 0.9
		local position = home + Vector3.new(math.cos(angle) * radius, 6 + math.sin(t * 1.7) * 2, math.sin(angle) * radius)
		local forward = Vector3.new(-math.sin(angle), 0, math.cos(angle))
		local cf = CFrame.lookAlong(position, forward) * CFrame.Angles(0, 0, 0.3) * CFrame.Angles(math.sin(t * 1.7 + 1) * 0.12, 0, 0)
		for _, entry in fixed do
			entry[1].CFrame = cf * entry[2]
		end
		-- tail: each part turns a little more than the one before it
		local joint = cf * CFrame.new(0, 0.05, 0.95)
		for index, p in tail do
			joint = joint * CFrame.Angles(0, math.sin(t * 5 - index * 0.8) * 0.25, 0)
			local length = p.Size.Z
			p.CFrame = joint * CFrame.new(0, 0, length / 2)
			joint = joint * CFrame.new(0, 0, length)
		end
		spade.CFrame = joint * CFrame.new(0, 0, 0.15) * CFrame.Angles(0, math.rad(45), 0)
		-- wings: the outer half follows the inner one a bit later
		local flap = math.sin(t * 9) * 0.7
		local flapOuter = math.sin(t * 9 - 0.6) * 0.5
		for _, wing in wings do
			local s = wing.Side
			local shoulder = cf * CFrame.new(s * 0.45, 0.35, -0.3) * CFrame.Angles(0, 0, s * flap)
			local innerCF = shoulder * CFrame.new(s * 0.7, 0, 0)
			wing.InnerBone.CFrame = innerCF
			wing.Inner.CFrame = innerCF * CFrame.new(0, 0, 0.5)
			local elbow = shoulder * CFrame.new(s * 1.4, 0, 0) * CFrame.Angles(0, 0, s * flapOuter)
			local outerCF = elbow * CFrame.new(s * 0.65, 0, 0)
			wing.OuterBone.CFrame = outerCF
			wing.Outer.CFrame = outerCF * CFrame.new(0, 0, 0.4) * CFrame.Angles(0, s * 0.25, 0)
		end
	end
end

function Effects.Teleporter(ctx)
	local center = part(ctx, 2).Position
	local rings = {}
	for index = 1, 3 do
		rings[index] = piece(ctx.Folder, Enum.PartType.Cylinder, Vector3.new(0.12, 3, 3), rgb(140, 110, 255), 0.6)
	end
	onFire(ctx, function()
		AudioController.PlayAt(AudioConfig.Abilities.CometWhoosh, ctx.Base, false, 60)
		burst(center + Vector3.new(0, 2.5, 0), { rgb(140, 110, 255), rgb(90, 220, 255) }, 60, 18)
	end)
	return function(t)
		for index, ring in rings do
			local height = (t * 0.6 + index / 3) % 1
			ring.CFrame = CFrame.new(center + Vector3.new(0, 0.3 + height * 4, 0)) * CFrame.Angles(0, 0, math.pi / 2)
			ring.Transparency = 0.6 + height * 0.4
		end
	end
end

local CRYSTAL = { rgb(200, 170, 255), rgb(190, 110, 255), rgb(120, 210, 255), rgb(120, 255, 200) }

function Effects.CrystalSnowman(ctx)
	local balls = { ctx.Base, part(ctx, 2), part(ctx, 3) }
	local light = pointLight(ctx, part(ctx, 2), CRYSTAL[2])
	local sparkle = emitter(part(ctx, 2), SPARKLE, { Rate = 10, Speed = NumberRange.new(2, 5), SpreadAngle = Vector2.new(180, 180), Lifetime = NumberRange.new(0.8, 1.6), Size = NumberSequence.new(0.6, 0) })
	ctx.Track(sparkle)
	return function(t, mode, powered)
		local on = mode > 1
		local color = if mode == 4 then Color3.fromHSV(0.38 + math.sin(t * 0.6) * 0.2, 0.55, 1) else CRYSTAL[mode] or CRYSTAL[1]
		light.Enabled, sparkle.Enabled = on, on
		light.Color, light.Range = color, if powered then 24 else 15
		light.Brightness = 0.5 + math.sin(t * 2) * 0.15
		sparkle.Color = ColorSequence.new(color)
		for index, ball in balls do
			ball.Color = if on then color:Lerp(rgb(255, 255, 255), 0.15 + math.sin(t * 2 + index) * 0.15) else CRYSTAL[1]
		end
	end
end

function Effects.Toast(ctx)
	onFire(ctx, function(powered)
		local pop, popPitch = ItemSounds.ForEvent("ToastLaunch")
		AudioController.PlayItem(pop, popPitch * (0.95 + math.random() * 0.1), ctx.Base, 1, 90)
		for index = 1, if powered then 5 else 2 do
			task.delay(index * 0.12, rocket, top(ctx), 26, Vector3.new(1.3, 1.3, 0.35), rgb(222, 165, 90), { rgb(255, 220, 140), rgb(222, 165, 90) }, 24)
		end
	end)
	return nothing
end

function Effects.Plasma(ctx)
	onFire(ctx, function(powered)
		for index = 1, if powered then 9 else 5 do
			local color = Color3.fromHSV(math.random(), 0.75, 1)
			task.delay(index * 0.3, function()
				-- whistle up, then a bang and crackling sparks where it bursts
				local rise, risePitch = ItemSounds.ForEvent("FireworkRise")
				AudioController.PlayItem(rise, risePitch * (0.9 + math.random() * 0.3), ctx.Base, 1, 160)
				rocket(top(ctx), 45 + math.random(0, 12), Vector3.new(0.5, 1.4, 0.5), color, { color, rgb(255, 255, 255) }, 70, function(position)
					local holder = Instance.new("Attachment")
					holder.WorldPosition = position
					holder.Parent = Workspace.Terrain
					local bang = table.clone(AudioConfig.Abilities.CometImpact) :: any
					bang.Pitch = 1.1 + math.random() * 0.35
					bang.Volume = 0.4
					AudioController.PlayAt(bang, holder, false, 220)
					local crackle, cracklePitch = ItemSounds.ForEvent("FireworkCrackle")
					AudioController.PlayItem(crackle, cracklePitch, holder, 1, 180)
					Debris:AddItem(holder, 4)
				end)
			end)
		end
	end)
	return nothing
end

function Effects.HighFive(ctx)
	local hand = part(ctx, 2)
	local handHome = hand.CFrame
	local hitAt = -10
	onFire(ctx, function()
		hitAt = os.clock()
		burst(handHome.Position, { rgb(255, 205, 50), rgb(236, 74, 70), rgb(70, 160, 255) }, 36, 22)
	end)
	return function()
		local since = os.clock() - hitAt
		local swing = if since < 1 then math.sin(since * 18) * math.exp(-since * 4) * 0.9 else 0
		local turn = CFrame.Angles(swing, 0, 0)
		hand.CFrame = CFrame.new(ctx.Base.Position) * turn * CFrame.new(ctx.Base.Position):ToObjectSpace(handHome)
	end
end

function Effects.Snowman(ctx)
	onFire(ctx, function(powered)
		burst(top(ctx), { rgb(255, 255, 255), rgb(190, 225, 255) }, if powered then 120 else 50, 28)
	end)
	return nothing
end

function Effects.Arcade(ctx)
	local label = screenLabel(ctx, part(ctx, 2))
	local last = ""
	return function(t)
		local text = ctx.Model:GetAttribute("ScreenText")
		local shown = if type(text) == "string" then text else ""
		label.Text = shown
		label.BackgroundColor3 = if shown == "GO!" then rgb(40, 190, 90) elseif shown == "WAIT..." then rgb(180, 50, 60) else rgb(16, 20, 36)
		if shown == "GO!" and last ~= shown then
			ping(ctx.Base, 2, 0.5)
		end
		last = shown
		local _ = t
	end
end

function Effects.Robot(ctx)
	local gui = Instance.new("BillboardGui")
	gui.Size = UDim2.fromOffset(230, 44)
	gui.StudsOffsetWorldSpace = Vector3.new(0, 5, 0)
	gui.AlwaysOnTop = true
	gui.MaxDistance = 60
	gui.LightInfluence = 0
	gui.Adornee = ctx.Base
	local label = Instance.new("TextLabel")
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundColor3 = rgb(248, 251, 255)
	label.Font = Enum.Font.FredokaOne
	label.TextColor3 = rgb(24, 44, 86)
	label.TextScaled = true
	label.Parent = gui
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0.4, 0)
	corner.Parent = label
	gui.Parent = ctx.Folder
	local headParts = { part(ctx, 2), part(ctx, 3), part(ctx, 4) }
	local homes = {}
	for index, p in headParts do
		homes[index] = p.CFrame
	end
	return function(t)
		local speech = ctx.Model:GetAttribute("Speech")
		gui.Enabled = type(speech) == "string"
		label.Text = if type(speech) == "string" then speech else ""
		local pivot = homes[1]
		for index, p in headParts do
			p.CFrame = pivot * CFrame.Angles(0, math.sin(t * 1.2) * 0.5, 0) * pivot:ToObjectSpace(homes[index])
		end
	end
end

function Effects.Hologram(ctx)
	local shown: string? = nil
	local holo: Model? = nil
	local light = pointLight(ctx, part(ctx, 2), rgb(120, 255, 220))
	local center = top(ctx) + Vector3.new(0, 3.2, 0)
	return function(t, _, powered)
		local id = ctx.Model:GetAttribute("HoloId")
		if id ~= shown then
			shown = id
			if holo ~= nil then
				holo:Destroy()
				holo = nil
			end
			local built = if type(id) == "string" then JunkFactory.Build(id, "World", 3.6) else nil
			if built ~= nil then
				for _, p in built:GetDescendants() do
					if p:IsA("BasePart") then
						p.Material = Enum.Material.Neon
						p.Transparency = 0.45
						p.CastShadow = false
						p.Color = p.Color:Lerp(rgb(120, 255, 220), 0.35)
					end
				end
				built.Parent = ctx.Folder
				holo = built
			end
		end
		light.Enabled = holo ~= nil
		light.Range, light.Brightness = if powered then 18 else 12, 0.6
		if holo ~= nil then
			holo:PivotTo(CFrame.new(center + Vector3.new(0, math.sin(t * 1.5) * 0.3, 0)) * CFrame.Angles(0, t, 0))
		end
	end
end

function Effects.Throne(ctx)
	local crown = ctx.Model:FindFirstChild("Crown")
	local seat = ctx.Model:FindFirstChild("ThroneSeat")
	local sparkle = emitter(if crown ~= nil then crown else ctx.Base, SPARKLE, { Rate = 25, Speed = NumberRange.new(3, 6), SpreadAngle = Vector2.new(180, 180), Lifetime = NumberRange.new(0.8, 1.4), Size = NumberSequence.new(0.8, 0), Color = ColorSequence.new(rgb(255, 215, 90)) })
	ctx.Track(sparkle)
	-- Fanfares for the ruler, one after another while somebody sits there (APM Music).
	local tracks = { "rbxassetid://1836473422", "rbxassetid://85130118995016" }
	local music = Instance.new("Sound")
	music.Name = "Fanfare"
	music.Volume = 0.35
	music.RollOffMinDistance = 10
	music.RollOffMaxDistance = 80
	music.Parent = ctx.Base
	ctx.Track(music)
	local nextAt, index = 0, 0
	local crowned: Instance? = nil
	local worn: Model? = nil
	return function()
		local occupant = if seat ~= nil and seat:IsA("Seat") then seat.Occupant else nil
		local seated = occupant ~= nil
		-- A crown for whoever sits there.
		local character = if occupant ~= nil then occupant.Parent else nil
		if character ~= crowned then
			crowned = character
			if worn ~= nil then
				worn:Destroy()
				worn = nil
			end
			local head = if character ~= nil then character:FindFirstChild("Head") else nil
			local built = if head ~= nil and head:IsA("BasePart") then JunkFactory.Build("frozen_crown", "Cosmetic", 1.6) else nil
			if built ~= nil and head ~= nil and head:IsA("BasePart") then
				built:PivotTo(head.CFrame * CFrame.new(0, head.Size.Y / 2 + 0.2, 0))
				built.Parent = ctx.Folder
				local root = JunkFactory.GetRoot(built)
				if root ~= nil then
					local weld = Instance.new("WeldConstraint")
					weld.Part0 = head
					weld.Part1 = root
					weld.Parent = root
				end
				worn = built
			end
		end
		sparkle.Enabled = seated
		if not seated then
			if music.Playing then
				music:Stop()
			end
			nextAt, index = 0, 0
		elseif not music.Playing and os.clock() >= nextAt then
			index = index % #tracks + 1
			music.SoundId = tracks[index]
			music.TimePosition = 0
			music:Play()
			nextAt = os.clock() + 3 -- also the pause after a fanfare
		end
	end
end

local lastLaunch = 0

function Effects.Launcher(ctx)
	local plate = part(ctx, 4)
	local home = plate.CFrame
	local firedAt = -10
	local half = plate.Size.X / 2 + 0.4
	return function(_, _, powered)
		local since = os.clock() - firedAt
		plate.CFrame = home * CFrame.new(0, if since < 0.5 then math.sin(since / 0.5 * math.pi) * 1.4 else 0, 0)
		local root, humanoid = liveRoot()
		if root == nil or humanoid == nil or humanoid.Sit or os.clock() - lastLaunch < 0.6 then
			return
		end
		local offset = home:PointToObjectSpace(root.Position)
		if math.abs(offset.X) < half and math.abs(offset.Z) < half and offset.Y > 0.5 and offset.Y < 4.5 and root.AssemblyLinearVelocity.Y < 20 then
			lastLaunch, firedAt = os.clock(), os.clock()
			humanoid:ChangeState(Enum.HumanoidStateType.Freefall)
			local velocity = root.AssemblyLinearVelocity
			root.AssemblyLinearVelocity = Vector3.new(velocity.X, if powered then 125 else 95, velocity.Z)
			local family, pitch = ItemSounds.ForEvent(`Boing{math.random(1, 4)}`)
			AudioController.PlayItem(family, pitch, ctx.Base, 1, 70)
		end
	end
end

---------------------------------------------------------------------------------------------
-- Dancing near a disco ball (only while standing still; any movement stops it)
---------------------------------------------------------------------------------------------

local danceTrack: AnimationTrack? = nil
local danceAnimator: Animator? = nil

local function updateDance(wanted: boolean)
	local _, humanoid = liveRoot()
	local animator = if humanoid ~= nil then humanoid:FindFirstChildOfClass("Animator") else nil
	local dance = wanted and humanoid ~= nil and humanoid.MoveDirection.Magnitude < 0.05 and not humanoid.Sit
		and humanoid.RigType == Enum.HumanoidRigType.R15 and humanoid.FloorMaterial ~= Enum.Material.Air
	if dance and animator ~= nil then
		if danceTrack == nil or danceAnimator ~= animator then
			local animation = Instance.new("Animation")
			animation.AnimationId = DANCE_ANIMATION
			local track = animator:LoadAnimation(animation)
			track.Looped = true
			track.Priority = Enum.AnimationPriority.Action
			danceTrack, danceAnimator = track, animator
		end
		local track = danceTrack :: AnimationTrack
		if not track.IsPlaying then
			track:Play(0.3)
		end
	elseif danceTrack ~= nil and danceTrack.IsPlaying then
		danceTrack:Stop(0.2)
	end
end

---------------------------------------------------------------------------------------------
-- Lifecycle
---------------------------------------------------------------------------------------------

local function stop(model: Model)
	local state = active[model]
	active[model] = nil
	if state == nil then
		return
	end
	state.Context.Folder:Destroy()
	for _, instance in state.Tracked do
		instance:Destroy()
	end
	for _, fn in state.OnStop do
		fn()
	end
end

local function start(model: Model)
	local name = model:GetAttribute("Gadget")
	local base = model:FindFirstChild("Base")
	local build = if type(name) == "string" then Effects[name] else nil
	if build == nil or base == nil or not base:IsA("BasePart") then
		return -- not a gadget, or its parts are not streamed in yet
	end
	local folder = Instance.new("Folder")
	folder.Name = `Gadget_{name}`
	folder.Parent = effectsFolder()
	local tracked: { Instance } = {}
	-- The effects animate some server parts: put them back when the effect stops.
	local homes: { [BasePart]: { CFrame: CFrame, Color: Color3, Transparency: number, Material: Enum.Material } } = {}
	for _, child in model:GetChildren() do
		if child:IsA("BasePart") then
			homes[child] = { CFrame = child.CFrame, Color = child.Color, Transparency = child.Transparency, Material = child.Material }
		end
	end
	local context: Context = {
		Model = model,
		Base = base,
		Folder = folder,
		Track = function(instance: Instance)
			table.insert(tracked, instance)
		end,
	}
	local ok, update = pcall(build, context)
	if not ok then
		warn(`[GadgetController] {name}: {tostring(update)}`)
		folder:Destroy()
		active[model] = { Context = context, Update = nothing, Tracked = tracked, Powered = false, OnStop = {} }
		return
	end
	active[model] = {
		Context = context,
		Update = update :: Update,
		Tracked = tracked,
		Powered = false,
		OnStop = {
			function()
				for p, home in homes do
					if p:IsDescendantOf(Workspace) then
						p.CFrame, p.Color, p.Transparency, p.Material = home.CFrame, home.Color, home.Transparency, home.Material
					end
				end
			end,
		},
	}
end

local function scan()
	local folder = Workspace:FindFirstChild(PlacementRules.DEPLOYED_FOLDER)
	local camera = Workspace.CurrentCamera
	if folder == nil or camera == nil then
		return
	end
	local eye = camera.CFrame.Position
	local range = if localPlayer:GetAttribute("LiteGraphics") == true then LITE_RANGE else RANGE
	local generators: { Vector3 } = {}
	local near: { [Model]: Vector3 } = {}
	for _, model in folder:GetChildren() do
		local base = model:FindFirstChild("Base")
		if not model:IsA("Model") or model:GetAttribute("Gadget") == nil or base == nil or not base:IsA("BasePart") then
			continue
		end
		if model:GetAttribute("Gadget") == "Generator" and model:GetAttribute("GadgetMode") == 2 then
			table.insert(generators, base.Position)
		end
		if (base.Position - eye).Magnitude <= range then
			near[model] = base.Position
			-- Effects remember their parts: start only when all of them have arrived.
			if active[model] == nil and #model:GetChildren() >= (model:GetAttribute("PartCount") or 1) then
				start(model)
			end
		end
	end
	for model, state in active do
		local position = near[model]
		if position == nil then
			stop(model)
		else
			state.Powered = false
			for _, generator in generators do
				if (generator - position).Magnitude <= POWER_RANGE and model:GetAttribute("Gadget") ~= "Generator" then
					state.Powered = true
				end
			end
		end
	end
end

function GadgetController.Start()
	local elapsed = 1
	RunService.Heartbeat:Connect(function(dt: number)
		elapsed += dt
		if elapsed >= 0.5 then
			elapsed = 0
			scan()
		end
		dancingNear = false
		local time = Workspace:GetServerTimeNow() % 10000
		for model, state in active do
			if model.Parent == nil then
				stop(model)
				continue
			end
			local mode = model:GetAttribute("GadgetMode")
			local ok, err = pcall(state.Update, time, if type(mode) == "number" then mode else 1, state.Powered)
			if not ok then
				warn(`[GadgetController] {model.Name}: {tostring(err)}`)
				state.Update = nothing
			end
		end
		updateDance(dancingNear)
	end)
end

return GadgetController
