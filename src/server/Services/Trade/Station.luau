--!strict
--[[
	Station: the Trade Station on the plaza. Two glass exchange pods (orange and teal) joined by
	energy pipes to a console with a hologram, under a neon arch.

	Cheap on purpose: everything is anchored, small parts neither collide, query nor cast
	shadows, two small lights without shadows. The rings and the hologram are turned by every
	client alone (tag PlazaSpin, client PlazaController: only close by, not with Lite graphics).

	Build(ground) -> Model, Console   the caller adds the prompt to the console
]]

local Workspace = game:GetService("Workspace")

local Station = {}

local rgb = Color3.fromRGB
local V = Vector3.new
local M = Enum.Material
local C, S, W = Enum.PartType.Cylinder, Enum.PartType.Ball, Enum.PartType.Wedge
local at = CFrame.new
local UPRIGHT = CFrame.Angles(0, 0, math.rad(90)) -- stands a cylinder up (its axis is X)
local INK, NAVY, STEEL, CHROME = rgb(28, 36, 60), rgb(44, 56, 92), rgb(120, 132, 156), rgb(200, 208, 222)
local ORANGE, TEAL, GOLD, SNOW = rgb(255, 150, 40), rgb(50, 220, 220), rgb(255, 205, 60), rgb(248, 251, 255)

local function deg(x: number, y: number, z: number): CFrame
	return CFrame.Angles(math.rad(x), math.rad(y), math.rad(z))
end

function Station.Build(ground: CFrame): (Model, BasePart)
	local model = Instance.new("Model")
	model.Name = "TradeStation"
	-- Something to stand on or bump into.
	local function solid(name: string, size: Vector3, offset: CFrame, color: Color3, material: Enum.Material?, shape: Enum.PartType?): Part
		local p = Instance.new("Part")
		p.Name = name
		p.Shape = shape or Enum.PartType.Block
		p.Size = size
		p.CFrame = ground * offset
		p.Color = color
		p.Material = material or M.SmoothPlastic
		p.Anchored = true
		p.CanTouch = false
		p.TopSurface = Enum.SurfaceType.Smooth
		p.BottomSurface = Enum.SurfaceType.Smooth
		p.Parent = model
		return p
	end
	-- Decoration only.
	local function part(name: string, size: Vector3, offset: CFrame, color: Color3, material: Enum.Material?, shape: Enum.PartType?): Part
		local p = solid(name, size, offset, color, material, shape)
		p.CanCollide = false
		p.CanQuery = false
		p.CastShadow = false
		return p
	end
	local function spin(p: BasePart, center: CFrame, axis: Vector3, speed: number)
		p:SetAttribute("Center", (ground * center).Position)
		p:SetAttribute("Axis", ground:VectorToWorldSpace(axis))
		p:SetAttribute("Speed", speed)
		p:AddTag("PlazaSpin")
	end
	local function light(parent: Instance, color: Color3, range: number)
		local l = Instance.new("PointLight")
		l.Color = color
		l.Range = range
		l.Brightness = 1
		l.Shadows = false
		l.Parent = parent
	end

	-- Platform: two low steps, hazard edge, plates, a neon trench between the pods
	solid("Base", V(22, 0.3, 11), at(0, 0.15, 0), INK)
	solid("Deck", V(20.4, 0.3, 9.4), at(0, 0.4, 0), NAVY, M.Metal)
	for index = 0, 21 do
		part("Hazard", V(0.92, 0.06, 0.7), at(-10 + index * 0.952, 0.31, -5.1), if index % 2 == 0 then GOLD else INK)
	end
	for _, x in { -3.4, 3.4 } do
		for _, z in { -3, 0, 3 } do
			part("Plate", V(2.6, 0.06, 2.5), at(x, 0.57, z), STEEL, M.DiamondPlate)
		end
	end
	for side = -1, 1, 2 do
		local color = if side < 0 then ORANGE else TEAL
		part("Trench", V(3.6, 0.08, 0.3), at(side * 3.2, 0.6, -1.6), color, M.Neon)
		part("Trench", V(3.6, 0.08, 0.3), at(side * 3.2, 0.6, 1.4), color, M.Neon)
		part("Corner", V(0.5, 0.5, 9.5), at(side * 10.4, 0.5, 0), STEEL, M.Metal)
		for _, z in { -4.4, 4.4 } do
			solid("Bollard", V(1.4, 0.8, 0.8), at(side * 10.4, 1, z) * UPRIGHT, INK, M.Metal, C)
			part("BollardLight", V(0.3, 0.86, 0.86), at(side * 10.4, 1.4, z) * UPRIGHT, color, M.Neon, C)
			part("BollardCap", V(0.2, 0.9, 0.9), at(side * 10.4, 1.72, z) * UPRIGHT, SNOW, M.Snow, C)
		end

		-- Exchange pod: pad, rings that turn, glass back, head lamp, coil
		local px = side * 6.8
		solid("Pad", V(0.4, 5.6, 5.6), at(px, 0.72, 0) * UPRIGHT, INK, M.Metal, C)
		part("PadGlow", V(0.44, 5, 5), at(px, 0.74, 0) * UPRIGHT, color, M.Neon, C)
		part("PadTop", V(0.48, 4.6, 4.6), at(px, 0.75, 0) * UPRIGHT, NAVY, M.DiamondPlate, C)
		part("PadMark", V(0.5, 1.6, 1.6), at(px, 0.76, 0) * UPRIGHT, color, M.Neon, C)
		part("PadMarkIn", V(0.52, 1.1, 1.1), at(px, 0.77, 0) * UPRIGHT, NAVY, M.SmoothPlastic, C)
		for index = 0, 7 do
			local ring = part("Ring", V(1.5, 0.22, 0.3), at(px, 7.3, 0) * deg(0, index * 45, 0) * at(0, 0, 2.2), CHROME, M.Metal)
			spin(ring, at(px, 7.3, 0), V(0, 1, 0), side * 0.8)
			if index % 2 == 0 then
				local bulb = part("RingBulb", V(0.4, 0.3, 0.4), at(px, 7.1, 0) * deg(0, index * 45, 0) * at(0, 0, 2.2), color, M.Neon)
				spin(bulb, at(px, 7.3, 0), V(0, 1, 0), side * 0.8)
			end
		end
		solid("Back", V(4.4, 6.4, 0.5), at(px, 3.8, 3.1), INK, M.Metal)
		local glass = part("Glass", V(3.6, 5, 0.2), at(px, 4, 2.8), color, M.Glass)
		glass.Transparency = 0.5
		for _, dx in { -2.1, 2.1 } do
			solid("Pillar", V(0.7, 7.6, 0.9), at(px + dx, 4.3, 2.6), STEEL, M.Metal)
			part("PillarStrip", V(0.16, 6.2, 0.1), at(px + dx, 4.2, 2.12), color, M.Neon)
			part("PillarFoot", V(1.1, 0.7, 1.3), at(px + dx, 0.95, 2.6), INK, M.Metal)
		end
		part("Head", V(5.4, 0.9, 1.6), at(px, 8.2, 2.5), NAVY, M.Metal)
		part("HeadTrim", V(5.6, 0.2, 1.8), at(px, 8.7, 2.5), GOLD, M.Metal)
		part("HeadSnow", V(5.5, 0.35, 1.7), at(px, 8.95, 2.5), SNOW, M.Snow)
		part("Arm", V(0.5, 0.5, 2.6), at(px, 8.1, 1.1), STEEL, M.Metal)
		local lamp = part("Lamp", V(0.4, 1.8, 1.8), at(px, 7.8, 0) * UPRIGHT, color, M.Neon, C)
		light(lamp, color, 11)
		local beam = part("Beam", V(6.6, 3.4, 3.4), at(px, 4.2, 0) * UPRIGHT, color, M.Neon, C)
		beam.Transparency = 0.93
		-- Letter plate on the glass: which side you are
		local plate = part("SideScreen", V(3, 1, 0.12), at(px, 5.6, 2.62), INK)
		local gui = Instance.new("SurfaceGui")
		gui.Face = Enum.NormalId.Front
		gui.CanvasSize = Vector2.new(240, 80)
		gui.LightInfluence = 0
		gui.MaxDistance = 70
		local label = Instance.new("TextLabel")
		label.Size = UDim2.fromScale(1, 1)
		label.BackgroundTransparency = 1
		label.Font = Enum.Font.FredokaOne
		label.Text = "STAND HERE"
		label.TextColor3 = color
		label.TextScaled = true
		label.Parent = gui
		gui.Parent = plate
		-- Coil and tank on the outside
		for index = 0, 3 do
			part("Coil", V(0.3, 1.5, 1.5), at(side * 9.7, 1.6 + index * 0.6, 2.9) * UPRIGHT, if index % 2 == 0 then color else CHROME, M.Metal, C)
		end
		part("Tank", V(3, 1.1, 1.1), at(side * 9.7, 2, 2.9) * UPRIGHT, INK, M.Metal, C)
		part("TankCap", V(1.1, 1.1, 1.1), at(side * 9.7, 3.9, 2.9), color, M.Neon, S)
		-- Energy pipes from the pod to the console
		for _, pipe in { { 1.1, 3.5, 0.5 }, { 2, 3.7, 0.36 }, { 2.8, 3.5, 0.28 } } do
			part("Pipe", V(4.2, pipe[3], pipe[3]), at(side * 3, pipe[1], pipe[2]), if pipe[3] < 0.4 then color else STEEL, if pipe[3] < 0.3 then M.Neon else M.Metal, C)
			part("PipeRing", V(0.3, pipe[3] + 0.24, pipe[3] + 0.24), at(side * 3.6, pipe[1], pipe[2]), GOLD, M.Metal, C)
		end
	end

	-- Console: slanted desk with two screens, buttons and levers
	local console = solid("Console", V(3.6, 2.4, 1.8), at(0, 1.75, 0.6), NAVY, M.Metal)
	part("ConsoleFoot", V(4.2, 0.5, 2.4), at(0, 0.8, 0.6), INK, M.Metal)
	part("ConsoleTrim", V(3.8, 0.18, 2), at(0, 2.9, 0.6), GOLD, M.Metal)
	part("Desk", V(3.6, 0.8, 1.7), at(0, 3.35, 0.65) * deg(0, 180, 0), STEEL, M.Metal, W)
	for side = -1, 1, 2 do
		local color = if side < 0 then ORANGE else TEAL
		part("DeskScreen", V(1.3, 0.06, 0.9), at(side * 0.85, 3.42, 0.6) * deg(-25, 0, 0), color, M.Neon)
		for index = 0, 2 do
			part("Button", V(0.22, 0.16, 0.22), at(side * (0.45 + index * 0.4), 3.08, -0.02), if index == 1 then GOLD else color, M.Neon)
		end
		part("Lever", V(0.12, 0.8, 0.12), at(side * 1.65, 3.6, 0.5) * deg(-20, 0, side * -10), CHROME, M.Metal)
		part("LeverKnob", V(0.32, 0.32, 0.32), at(side * 1.72, 4, 0.36), rgb(236, 74, 70), M.SmoothPlastic, S)
		part("Vent", V(0.1, 1.2, 1.1), at(side * 1.82, 1.7, 0.6), INK)
	end
	part("ConsoleFace", V(2.6, 1.3, 0.1), at(0, 1.85, -0.32), INK)
	for index = 0, 4 do
		part("Meter", V(0.3, 0.3 + (index * 37 % 5) * 0.16, 0.08), at(-0.9 + index * 0.45, 1.75, -0.39), if index < 2 then ORANGE elseif index == 2 then GOLD else TEAL, M.Neon)
	end

	-- Hologram over the console: two arrows chasing each other around a coin
	local center = at(0, 5.6, 0.4)
	part("HoloBase", V(0.3, 1.5, 1.5), at(0, 3.95, 0.9) * UPRIGHT, INK, M.Metal, C)
	part("HoloLens", V(0.34, 1.1, 1.1), at(0, 3.97, 0.9) * UPRIGHT, TEAL, M.Neon, C)
	local coin = part("HoloCoin", V(0.2, 1.1, 1.1), center, GOLD, M.Neon, C)
	coin.Transparency = 0.15
	spin(coin, center, V(0, 1, 0), 1.6)
	for side = 0, 1 do
		local color = if side == 0 then ORANGE else TEAL
		for index = 0, 4 do
			local block = part("HoloArrow", V(0.22, 0.34, 0.62), center * deg(0, side * 180 + index * 27, 0) * at(1.5, 0, 0), color, M.Neon)
			block.Transparency = 0.1
			spin(block, center, V(0, 1, 0), -1.1)
		end
		for _, tilt in { -38, 38 } do
			local tip = part("HoloTip", V(0.22, 0.3, 0.8), center * deg(0, side * 180 - 18, 0) * at(1.5, 0, 0) * deg(tilt, 0, 0) * at(0, 0, -0.28), color, M.Neon)
			spin(tip, center, V(0, 1, 0), -1.1)
		end
	end
	local dust = Instance.new("ParticleEmitter")
	dust.Name = "Dust"
	dust.Texture = "rbxasset://textures/particles/sparkles_main.dds"
	dust.Color = ColorSequence.new(ORANGE, TEAL)
	dust.LightEmission = 1
	dust.Size = NumberSequence.new(0.22, 0)
	dust.Lifetime = NumberRange.new(1, 1.8)
	dust.Speed = NumberRange.new(0.4, 1)
	dust.SpreadAngle = Vector2.new(180, 180)
	dust.Rate = 4
	dust.Parent = coin

	-- Arch with the sign
	for side = -1, 1, 2 do
		solid("ArchLeg", V(0.9, 10.4, 0.9), at(side * 3.4, 5.6, 4), STEEL, M.Metal)
		part("ArchFoot", V(1.6, 1, 1.6), at(side * 3.4, 1, 4), INK, M.Metal)
		part("ArchStrip", V(0.16, 9, 0.1), at(side * 3.4, 5.8, 3.52), if side < 0 then ORANGE else TEAL, M.Neon)
		part("Brace", V(0.4, 3.6, 0.4), at(side * 4.4, 9.2, 4) * deg(0, 0, side * -48), STEEL, M.Metal)
	end
	local sign = solid("Sign", V(13, 2.8, 0.6), at(0, 11.8, 4), INK)
	sign.CanCollide = false
	part("SignFrame", V(13.6, 3.4, 0.4), at(0, 11.8, 4), GOLD, M.Metal)
	part("SignSnow", V(13.4, 0.45, 1), at(0, 13.6, 4), SNOW, M.Snow)
	for index = 0, 11 do
		for _, z in { 3.68, 4.32 } do
			part("SignBulb", V(0.28, 0.28, 0.28), at(-6.2 + index * 1.127, 10.25, z), if index % 2 == 0 then ORANGE else TEAL, M.Neon, S)
		end
	end
	for side = -1, 1, 2 do
		for index = 0, 2 do -- gears on the sign's ends
			local tooth = part("Tooth", V(0.5, 2.2, 0.5), at(side * 7, 11.8, 4) * deg(0, 0, index * 60), rgb(255, 160, 50), M.Metal)
			spin(tooth, at(side * 7, 11.8, 4), V(0, 0, 1), side * 0.7)
		end
		part("Gear", V(0.6, 1.6, 1.6), at(side * 7, 11.8, 4) * deg(0, 90, 0), rgb(255, 160, 50), M.Metal, C)
		part("GearHub", V(0.7, 0.6, 0.6), at(side * 7, 11.8, 4) * deg(0, 90, 0), INK, M.Metal, C)
	end
	for _, face in { Enum.NormalId.Front, Enum.NormalId.Back } do
		local gui = Instance.new("SurfaceGui")
		gui.Face = face
		gui.CanvasSize = Vector2.new(520, 112)
		gui.LightInfluence = 0
		local title = Instance.new("TextLabel")
		title.Position = UDim2.fromScale(0.04, 0.06)
		title.Size = UDim2.fromScale(0.92, 0.6)
		title.BackgroundTransparency = 1
		title.Font = Enum.Font.FredokaOne
		title.Text = "TRADE STATION"
		title.TextColor3 = rgb(255, 214, 80)
		title.TextScaled = true
		title.Parent = gui
		local line = title:Clone()
		line.Position = UDim2.fromScale(0.04, 0.68)
		line.Size = UDim2.fromScale(0.92, 0.24)
		line.Text = "two players  -  fair swap  -  no tricks"
		line.TextColor3 = rgb(150, 235, 240)
		line.Parent = gui
		gui.Parent = sign
	end

	-- Cargo beside the pods: crates, a coin pile
	for _, crate in { { -9.6, -2.6, 1.5, 12 }, { -9.3, -1, 1.2, 40 }, { 9.6, -2.4, 1.6, -15 } } do
		local size = crate[3]
		solid("Crate", V(size, size, size), at(crate[1], 0.55 + size / 2, crate[2]) * deg(0, crate[4], 0), rgb(176, 124, 74), M.WoodPlanks)
		part("CrateBand", V(size + 0.08, size * 0.16, size + 0.08), at(crate[1], 0.55 + size / 2, crate[2]) * deg(0, crate[4], 0), INK, M.Metal)
	end
	for index, spot in { V(9.3, 0.65, -0.7), V(9.8, 0.65, -0.4), V(9.5, 0.65, -0.1), V(9.5, 0.85, -0.5), V(9.6, 0.85, -0.3), V(9.5, 1.05, -0.4) } do
		part("Coin", V(0.2, 0.8, 0.8), at(spot.X, spot.Y, spot.Z) * deg(0, index * 40, 0) * UPRIGHT, GOLD, M.Metal, C)
	end

	model.Parent = Workspace
	return model, console
end

return Station
