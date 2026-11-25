--!strict
--[[
	Board: one leaderboard on the plaza.

	  frame      navy screen in a gold frame with bulbs, gears on the corners, coin piles
	  screen     cards with pictures for places 1-3, rows for the rest (both sides)
	  stage      on top: the leader's own avatar dances under a floating crown

	Build(key, title, count, ground) -> Board
	  Set(entries, footer)   entries sorted, best first; redraws only what is given
	LeaderboardController (client) animates it: tag "PlazaBoard" on the model, parts named Bulb /
	Crown, UI named Card1-3 / Row<n> with the attribute UserId, model attribute LeaderId.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local KlunksFormat = require(ReplicatedStorage.Shared.Util.KlunksFormat)

export type Entry = { UserId: number, Name: string, Klunks: number }
export type Board = { Set: (entries: { Entry }, footer: string) -> () }

local Board = {}

local rgb = Color3.fromRGB
local V = Vector3.new
local M = Enum.Material
local NAVY, NIGHT, GOLD, STEEL = rgb(24, 40, 84), rgb(14, 20, 44), rgb(255, 200, 50), rgb(58, 70, 104)
local MEDALS = { rgb(255, 205, 60), rgb(206, 218, 236), rgb(232, 150, 88) }
local CANVAS = Vector2.new(660, 580)
local DANCE = "rbxassetid://507771019" -- Roblox's own dance (R15)
local UPRIGHT = CFrame.Angles(0, 0, math.rad(90))

type Slot = { Root: Frame, Picture: ImageLabel, Name: TextLabel, Amount: TextLabel }

local function corner(parent: Instance, radius: number)
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(0, radius)
	c.Parent = parent
end

local function stroke(parent: Instance, color: Color3, thickness: number)
	local s = Instance.new("UIStroke")
	s.Color = color
	s.Thickness = thickness
	s.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	s.Parent = parent
end

local function shade(parent: Instance, top: Color3, bottom: Color3)
	local g = Instance.new("UIGradient")
	g.Rotation = 90
	g.Color = ColorSequence.new(top, bottom)
	g.Parent = parent
end

local function box(parent: Instance, name: string, x: number, y: number, w: number, h: number, color: Color3): Frame
	local f = Instance.new("Frame")
	f.Name = name
	f.Position = UDim2.fromOffset(x, y)
	f.Size = UDim2.fromOffset(w, h)
	f.BackgroundColor3 = color
	f.BorderSizePixel = 0
	f.Parent = parent
	return f
end

local function text(parent: Instance, name: string, value: string, x: number, y: number, w: number, h: number, color: Color3, align: Enum.TextXAlignment?): TextLabel
	local l = Instance.new("TextLabel")
	l.Name = name
	l.Position = UDim2.fromOffset(x, y)
	l.Size = UDim2.fromOffset(w, h)
	l.BackgroundTransparency = 1
	l.Font = Enum.Font.FredokaOne
	l.Text = value
	l.TextColor3 = color
	l.TextScaled = true
	l.TextXAlignment = align or Enum.TextXAlignment.Center
	local s = Instance.new("UIStroke")
	s.Color = NIGHT
	s.Thickness = 2
	s.Parent = l
	l.Parent = parent
	return l
end

local function picture(parent: Instance, x: number, y: number, size: number, color: Color3): ImageLabel
	local p = Instance.new("ImageLabel")
	p.Name = "Picture"
	p.Position = UDim2.fromOffset(x, y)
	p.Size = UDim2.fromOffset(size, size)
	p.BackgroundColor3 = color:Lerp(NIGHT, 0.55)
	corner(p, size)
	stroke(p, color, math.max(size * 0.05, 2))
	p.Parent = parent
	return p
end

local function card(gui: Instance, place: number): Slot
	local w, h = if place == 1 then 220 else 190, if place == 1 then 250 else 206
	local x = if place == 1 then 220 elseif place == 2 then 18 else 452
	local y = if place == 1 then 84 else 128
	local color = MEDALS[place]
	local root = box(gui, `Card{place}`, x, y, w, h, Color3.new(1, 1, 1))
	corner(root, 18)
	stroke(root, color, if place == 1 then 5 else 4)
	shade(root, color:Lerp(NAVY, 0.45), NIGHT)
	local size = if place == 1 then 124 else 96
	local pic = picture(root, (w - size) / 2, 20, size, color)
	local medal = box(root, "Medal", (w - 46) / 2, size - 4, 46, 46, color)
	corner(medal, 23)
	stroke(medal, NIGHT, 3)
	text(medal, "Place", tostring(place), 5, 4, 36, 38, Color3.new(1, 1, 1))
	local name = text(root, "PlayerName", "", 10, size + 46, w - 20, 30, Color3.new(1, 1, 1))
	local amount = text(root, "Amount", "", 10, h - 34 - (if place == 1 then 6 else 0), w - 20, 28, color:Lerp(Color3.new(1, 1, 1), 0.25))
	return { Root = root, Picture = pic, Name = name, Amount = amount }
end

local function row(gui: Instance, place: number, y: number, height: number): Slot
	local root = box(gui, `Row{place}`, 18, y, CANVAS.X - 36, height - 5, if place % 2 == 0 then rgb(40, 58, 110) else rgb(32, 48, 96))
	corner(root, 10)
	local h = height - 5
	local badge = box(root, "Badge", 5, 4, 46, h - 8, STEEL)
	corner(badge, 8)
	text(badge, "Place", tostring(place), 3, 2, 40, h - 12, rgb(210, 224, 255))
	local pic = picture(root, 60, 3, h - 6, rgb(120, 160, 240))
	local name = text(root, "PlayerName", "", 70 + h, 4, 310, h - 8, Color3.new(1, 1, 1), Enum.TextXAlignment.Left)
	local amount = text(root, "Amount", "", CANVAS.X - 246, 4, 200, h - 8, rgb(255, 222, 120), Enum.TextXAlignment.Right)
	return { Root = root, Picture = pic, Name = name, Amount = amount }
end

local function screen(board: BasePart, face: Enum.NormalId, title: string, count: number): ({ Slot }, TextLabel)
	local gui = Instance.new("SurfaceGui")
	gui.Name = "Screen"
	gui.Face = face
	gui.CanvasSize = CANVAS
	gui.LightInfluence = 0
	gui.ClipsDescendants = true
	gui.MaxDistance = 160
	gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	local back = box(gui, "Back", 0, 0, CANVAS.X, CANVAS.Y, Color3.new(1, 1, 1))
	shade(back, rgb(38, 62, 130), NIGHT)
	-- Rays behind the winner
	local rays = box(back, "Rays", CANVAS.X / 2 - 1, 206, 2, 2, GOLD)
	rays.BackgroundTransparency = 1
	for index = 0, 5 do
		local ray = box(rays, "Ray", 0, 0, 46, 760, GOLD)
		ray.AnchorPoint = Vector2.new(0.5, 0.5)
		ray.Rotation = index * 30
		local fade = Instance.new("UIGradient")
		fade.Rotation = 90
		fade.Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 1),
			NumberSequenceKeypoint.new(0.5, 0.72),
			NumberSequenceKeypoint.new(1, 1),
		})
		fade.Parent = ray
	end
	local head = box(back, "Head", 0, 0, CANVAS.X, 66, Color3.new(1, 1, 1))
	shade(head, rgb(255, 170, 40), rgb(214, 92, 20))
	box(head, "Line", 0, 62, CANVAS.X, 5, GOLD)
	text(head, "Title", title, 60, 6, CANVAS.X - 120, 50, Color3.new(1, 1, 1))

	local slots: { Slot } = {}
	for place = 1, 3 do
		slots[place] = card(back, place)
	end
	local top, bottom = 346, CANVAS.Y - 32
	local height = (bottom - top) / (count - 3)
	for place = 4, count do
		slots[place] = row(back, place, top + (place - 4) * height, height)
	end
	local footer = text(back, "Footer", "", 20, CANVAS.Y - 27, CANVAS.X - 40, 20, rgb(170, 190, 240))
	gui.Parent = board
	return slots, footer
end

function Board.Build(key: string, title: string, count: number, base: CFrame): Board
	local model = Instance.new("Model")
	model.Name = `Leaderboard{key}`
	local function part(name: string, size: Vector3, offset: CFrame, color: Color3, material: Enum.Material?, shape: Enum.PartType?): Part
		local p = Instance.new("Part")
		p.Name = name
		p.Shape = shape or Enum.PartType.Block
		p.Size = size
		p.CFrame = base * offset
		p.Color = color
		p.Material = material or M.SmoothPlastic
		p.Anchored = true
		p.CanTouch = false
		p.TopSurface = Enum.SurfaceType.Smooth
		p.BottomSurface = Enum.SurfaceType.Smooth
		p.Parent = model
		return p
	end
	local function decor(name: string, size: Vector3, offset: CFrame, color: Color3, material: Enum.Material?, shape: Enum.PartType?): Part
		local p = part(name, size, offset, color, material, shape)
		p.CanCollide = false
		p.CanQuery = false
		p.CastShadow = false
		return p
	end
	local at = CFrame.new

	-- Feet and pillars
	for _, x in { -6.1, 6.1 } do
		part("Foot", V(2.2, 0.9, 2.2), at(x, 0.45, 0), NIGHT, M.Metal)
		decor("FootTrim", V(2.3, 0.2, 2.3), at(x, 0.95, 0), GOLD, M.Metal)
		part("Pillar", V(1, 13.6, 1), at(x, 7.4, 0), STEEL, M.Metal)
		for index = 0, 3 do
			decor("Band", V(1.1, 0.35, 1.1), at(x, 2 + index * 0.8, 0), if index % 2 == 0 then GOLD else NIGHT)
		end
		-- a pile of coins at each foot
		for index, spot in { V(0.2, 0.12, -1.5), V(0.35, 0.34, -1.45), V(0.1, 0.56, -1.55), V(1.1, 0.12, -1.7), V(-0.8, 0.12, -1.8), V(1, 0.34, -1.75) } do
			decor("Coin", V(0.22, 1, 1), at(x + spot.X, spot.Y, spot.Z) * CFrame.Angles(0, index, 0) * UPRIGHT, GOLD, M.Metal, Enum.PartType.Cylinder)
		end
	end
	-- Screen and frame
	local board = part("Board", V(10.4, 9.14, 0.5), at(0, 9.2, 0), NAVY)
	part("Frame", V(11, 9.74, 0.4), at(0, 9.2, 0), GOLD, M.Metal)
	part("Rim", V(11.4, 10.1, 0.2), at(0, 9.2, 0), NIGHT, M.Metal)
	for _, z in { -0.32, 0.32 } do
		for index = 0, 10 do
			decor("Bulb", V(0.3, 0.3, 0.3), at(-5.2 + index * 1.04, 13.93, z), rgb(255, 240, 180), M.Neon, Enum.PartType.Ball)
			decor("Bulb", V(0.3, 0.3, 0.3), at(-5.2 + index * 1.04, 4.47, z), rgb(255, 240, 180), M.Neon, Enum.PartType.Ball)
		end
		for index = 1, 8 do
			for _, x in { -5.37, 5.37 } do
				decor("Bulb", V(0.3, 0.3, 0.3), at(x, 4.47 + index * 1.05, z), rgb(255, 240, 180), M.Neon, Enum.PartType.Ball)
			end
		end
	end
	-- Turning gears on the upper corners (PlazaController)
	for _, x in { -6.1, 6.1 } do
		local center = (base * at(x, 13.9, 0)).Position
		local function spin(p: BasePart)
			p:SetAttribute("Speed", if x < 0 then 0.6 else -0.6)
			p:SetAttribute("Center", center)
			p:SetAttribute("Axis", base.LookVector)
			p:AddTag("PlazaSpin")
		end
		for index = 0, 3 do
			spin(decor("Tooth", V(0.55, 2.5, 0.5), at(x, 13.9, 0) * CFrame.Angles(0, 0, math.rad(index * 45)), rgb(255, 140, 40), M.Metal))
		end
		decor("Wheel", V(0.7, 1.9, 1.9), at(x, 13.9, 0) * CFrame.Angles(0, math.rad(90), 0), rgb(255, 160, 50), M.Metal, Enum.PartType.Cylinder)
		decor("Hub", V(0.8, 0.7, 0.7), at(x, 13.9, 0) * CFrame.Angles(0, math.rad(90), 0), NIGHT, M.Metal, Enum.PartType.Cylinder)
	end
	-- Stage for the leader
	part("StageLow", V(6.4, 0.6, 3), at(0, 14.5, 0), NIGHT, M.Metal)
	local stage = part("Stage", V(5.2, 1.2, 3.2), at(0, 15.4, 0), GOLD, M.Metal)
	decor("StageGlow", V(5.4, 0.18, 3.4), at(0, 14.85, 0), rgb(255, 236, 150), M.Neon)
	for _, x in { -2.9, 2.9 } do
		decor("SnowEdge", V(0.9, 0.3, 2.4), at(x, 14.9, 0), rgb(250, 252, 255), M.Snow)
	end
	local crownHolder = Instance.new("Model")
	crownHolder.Name = "Crown"
	for index = 0, 5 do
		local a = math.rad(index * 60)
		local p = decor("Point", V(0.5, 0.9, 0.18), at(0, 22.9, 0) * CFrame.Angles(0, a, 0) * at(0, 0, 0.7), GOLD, M.Metal)
		p.Parent = crownHolder
		local gem = decor("Gem", V(0.24, 0.24, 0.24), at(0, 23.4, 0) * CFrame.Angles(0, a, 0) * at(0, 0, 0.7), if index % 2 == 0 then rgb(255, 70, 90) else rgb(80, 220, 255), M.Neon, Enum.PartType.Ball)
		gem.Parent = crownHolder
	end
	local band = decor("Band", V(0.4, 1.7, 1.7), at(0, 22.4, 0) * UPRIGHT, GOLD, M.Metal, Enum.PartType.Cylinder)
	band.Parent = crownHolder
	crownHolder.PrimaryPart = band
	local sparkle = Instance.new("ParticleEmitter")
	sparkle.Name = "Sparkle"
	sparkle.Texture = "rbxasset://textures/particles/sparkles_main.dds"
	sparkle.Color = ColorSequence.new(rgb(255, 250, 210), GOLD)
	sparkle.LightEmission = 0.8
	sparkle.Size = NumberSequence.new(0.45, 0)
	sparkle.Lifetime = NumberRange.new(0.8, 1.6)
	sparkle.Speed = NumberRange.new(1, 2)
	sparkle.SpreadAngle = Vector2.new(180, 180)
	sparkle.Rate = 5
	sparkle.Parent = band
	crownHolder.Parent = model

	local faces: { { Slots: { Slot }, Footer: TextLabel } } = {}
	for _, face in { Enum.NormalId.Front, Enum.NormalId.Back } do
		local slots, footer = screen(board, face, title, count)
		table.insert(faces, { Slots = slots, Footer = footer })
	end
	local plates: { TextLabel } = {}
	for _, face in { Enum.NormalId.Front, Enum.NormalId.Back } do
		local gui = Instance.new("SurfaceGui")
		gui.Face = face
		gui.CanvasSize = Vector2.new(520, 100)
		gui.LightInfluence = 0
		gui.Parent = stage
		table.insert(plates, text(gui, "Leader", "", 14, 10, 492, 80, Color3.new(1, 1, 1)))
	end
	model.WorldPivot = base
	model:AddTag("PlazaBoard")
	model.Parent = Workspace

	-- The leader's avatar on the stage
	local shown: number? = nil
	local token = 0
	local function showLeader(userId: number?)
		if userId == shown then
			return
		end
		shown = userId
		token += 1
		local mine = token
		model:SetAttribute("LeaderId", userId)
		local old = model:FindFirstChild("Leader")
		if old ~= nil then
			old:Destroy()
		end
		if userId == nil or userId <= 0 then
			return
		end
		task.spawn(function()
			local ok, rig = pcall(function()
				return Players:CreateHumanoidModelFromUserId(userId)
			end)
			if not ok or rig == nil then
				return
			end
			if mine ~= token then
				rig:Destroy()
				return
			end
			rig.Name = "Leader"
			for _, d in rig:GetDescendants() do
				if d:IsA("BaseScript") then
					d:Destroy()
				elseif d:IsA("BasePart") then
					d.CanTouch = false
					d.CanQuery = false
					d.CanCollide = false
				end
			end
			local humanoid = rig:FindFirstChildOfClass("Humanoid")
			local root = rig:FindFirstChild("HumanoidRootPart")
			if humanoid == nil or root == nil or not root:IsA("BasePart") then
				rig:Destroy()
				return
			end
			humanoid.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
			humanoid.HealthDisplayType = Enum.HumanoidHealthDisplayType.AlwaysOff
			humanoid.EvaluateStateMachine = false
			root.Anchored = true
			rig:PivotTo(base * at(0, 20, 0))
			local box, size = rig:GetBoundingBox()
			local feet = box.Position.Y - size.Y / 2
			rig:PivotTo(rig:GetPivot() + V(0, stage.Position.Y + stage.Size.Y / 2 - feet, 0))
			rig.Parent = model
			local animator = humanoid:FindFirstChildOfClass("Animator")
			if animator == nil then
				animator = Instance.new("Animator")
				animator.Parent = humanoid
			end
			local animation = Instance.new("Animation")
			animation.AnimationId = DANCE
			local loaded, track = pcall(function()
				return (animator :: Animator):LoadAnimation(animation)
			end)
			if loaded then
				track.Looped = true
				track:Play()
			end
		end)
	end

	local function fill(slot: Slot, entry: Entry?, place: number)
		slot.Root:SetAttribute("UserId", if entry ~= nil then entry.UserId else nil)
		slot.Name.Text = if entry ~= nil then entry.Name elseif place <= 3 then "This could be you!" else "-"
		slot.Amount.Text = if entry ~= nil then KlunksFormat.Format(entry.Klunks) else ""
		slot.Picture.Image = if entry ~= nil and entry.UserId > 0 then `rbxthumb://type=AvatarHeadShot&id={entry.UserId}&w=150&h=150` else ""
	end

	return {
		Set = function(entries: { Entry }, footer: string)
			for _, face in faces do
				for place, slot in face.Slots do
					fill(slot, entries[place], place)
				end
				face.Footer.Text = footer
			end
			local leader = entries[1]
			for _, plate in plates do
				plate.Text = if leader ~= nil then `#1  {leader.Name}` else "#1  ???"
			end
			showLeader(if leader ~= nil then leader.UserId else nil)
		end,
	}
end

return Board
