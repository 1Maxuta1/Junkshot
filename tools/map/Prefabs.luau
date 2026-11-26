--[[
	Prefabs: reusable map pieces for the JUNKSHOT winter junkyard (run by Lune, see build.luau).

	Every prefab takes (parent, cframe, ...) where cframe is the piece's center ON THE GROUND
	(y = ground height) and its -Z axis is the piece's "front". Pieces are low-part-count on
	purpose: big readable shapes, flat bright colors, no textures.
]]

local roblox = require("@lune/roblox")

local Instance = roblox.Instance
local Vector3 = roblox.Vector3
local CFrame = roblox.CFrame
local Color3 = roblox.Color3
local Enum = roblox.Enum

local Prefabs = {}

local function rgb(r, g, b)
	return Color3.fromRGB(r, g, b)
end

Prefabs.Colors = {
	Snow = rgb(246, 250, 255),
	SnowShade = rgb(222, 234, 250),
	Path = rgb(206, 221, 241),
	PlazaTop = rgb(232, 240, 252),
	Ice = rgb(120, 186, 246),
	Ink = rgb(44, 56, 82),
	Red = rgb(236, 74, 70),
	Orange = rgb(255, 148, 36),
	Yellow = rgb(255, 204, 48),
	Blue = rgb(58, 138, 236),
	Teal = rgb(36, 188, 186),
	Green = rgb(72, 188, 98),
	Purple = rgb(150, 104, 228),
	Pine = rgb(46, 140, 96),
	PineDark = rgb(34, 112, 82),
	Trunk = rgb(124, 82, 52),
	Wood = rgb(176, 124, 74),
	Rubber = rgb(48, 50, 60),
	Metal = rgb(176, 188, 204),
	Warm = rgb(255, 196, 110),
}
local C = Prefabs.Colors

Prefabs.Accents = { C.Red, C.Orange, C.Yellow, C.Blue, C.Teal, C.Green, C.Purple }

local count = 0
function Prefabs.GetPartCount()
	return count
end

-- Plain anchored part with the shared defaults.
function Prefabs.Part(parent, props)
	local part = Instance.new(props.ClassName or "Part")
	part.Anchored = true
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
	part.Material = props.Material or Enum.Material.SmoothPlastic
	part.Color = props.Color or C.Snow
	part.Size = props.Size
	part.CFrame = props.CFrame
	if props.Shape ~= nil then
		part.Shape = props.Shape
	end
	part.Name = props.Name or "Part"
	if props.CanCollide == false then
		part.CanCollide = false
	end
	if props.CanQuery == false then
		part.CanQuery = false
	end
	if props.CastShadow == false then
		part.CastShadow = false
	end
	if props.Transparency ~= nil then
		part.Transparency = props.Transparency
	end
	part.CanTouch = false
	part.Parent = parent
	count += 1
	return part
end

local function model(parent, name)
	local m = Instance.new("Model")
	m.Name = name
	m.Parent = parent
	return m
end

local UPRIGHT = CFrame.Angles(0, 0, math.rad(90)) -- cylinders run along X; this stands them up

-- Tiny deterministic RNG, so the same seed always builds the same map.
local function newRandom(seed)
	local state = (seed * 2654435761) % 4294967296
	local rng = {}
	function rng:NextNumber()
		state = (1103515245 * state + 12345) % 2147483648
		return state / 2147483648
	end
	function rng:NextInteger(min, max)
		return min + math.floor(self:NextNumber() * (max - min + 1))
	end
	return rng
end

---------------------------------------------------------------------------------------------
-- Pieces
---------------------------------------------------------------------------------------------

-- Shipping container, 24 x 9 x 9: body, doors, steel rails, snow cap. The fine details are added
-- near the camera by the client (ContainerController, tag ScrapContainer).
function Prefabs.Container(parent, cf, color, name)
	local m = model(parent, name or "Container")
	local body = Prefabs.Part(m, {
		Name = "Body",
		Size = Vector3.new(24, 9, 9),
		CFrame = cf * CFrame.new(0, 4.5, 0),
		Color = color,
	})
	Prefabs.Part(m, {
		Name = "Doors",
		Size = Vector3.new(0.4, 8.2, 8.2),
		CFrame = cf * CFrame.new(12.1, 4.5, 0),
		Color = color:Lerp(C.Ink, 0.25),
	})
	Prefabs.Part(m, {
		Name = "SnowCap",
		Size = Vector3.new(24.6, 0.7, 9.6),
		CFrame = cf * CFrame.new(0, 9.3, 0),
		Color = C.Snow,
	})
	for _, y in { 0.35, 8.65 } do
		Prefabs.Part(m, {
			Name = "Rail",
			Size = Vector3.new(24.1, 0.7, 9.5),
			CFrame = cf * CFrame.new(0, y, 0),
			Color = color:Lerp(C.Ink, 0.35),
			CanCollide = false,
			CanQuery = false,
			CastShadow = false,
		})
	end
	m:AddTag("ScrapContainer")
	m.PrimaryPart = body
	return m
end

-- The same container with its doors (+X end) open and its load spilled out. Hollow: you can
-- walk in. The invisible Body keeps ContainerController working.
function Prefabs.OpenContainer(parent, cf, color)
	local m = model(parent, "OpenContainer")
	local function p(name, size, offset, partColor, extra)
		local props = extra or {}
		props.Name, props.Size, props.CFrame, props.Color = name, size, cf * offset, partColor
		return Prefabs.Part(m, props)
	end
	local at = CFrame.new
	local inside = color:Lerp(C.Ink, 0.45)
	local body = p("Body", Vector3.new(24, 9, 9), at(0, 4.5, 0), color, { Transparency = 1, CanCollide = false, CanQuery = false, CastShadow = false })
	p("Floor", Vector3.new(24, 0.5, 9), at(0, 0.25, 0), C.Wood, { Material = Enum.Material.WoodPlanks })
	p("Roof", Vector3.new(24, 0.6, 9), at(0, 8.7, 0), color)
	for _, z in { -4.3, 4.3 } do
		p("Wall", Vector3.new(24, 8.6, 0.4), at(0, 4.5, z), color)
		p("Lining", Vector3.new(23, 7.6, 0.1), at(0, 4.5, z * 0.94), inside, { CanCollide = false, CastShadow = false })
	end
	p("End", Vector3.new(0.4, 8.6, 9), at(-11.8, 4.5, 0), inside)
	p("SnowCap", Vector3.new(24.6, 0.7, 9.6), at(0, 9.3, 0), C.Snow)
	for _, y in { 0.35, 8.65 } do
		for _, z in { -4.6, 4.6 } do
			p("Rail", Vector3.new(24.1, 0.7, 0.4), at(0, y, z), color:Lerp(C.Ink, 0.35), { CanCollide = false, CanQuery = false, CastShadow = false })
		end
	end
	-- Doors swung wide open
	for _, side in { -1, 1 } do
		local hinge = at(12, 4.5, side * 4.5) * CFrame.Angles(0, math.rad(side * 125), 0)
		p("Door", Vector3.new(0.35, 8.2, 4.4), hinge * at(0, 0, side * -2.2), color:Lerp(C.Ink, 0.25))
		for _, z in { 1.2, 3.2 } do
			p("Bar", Vector3.new(7.8, 0.24, 0.24), hinge * at(0.3, 0, side * -z) * UPRIGHT, C.Metal, { Shape = Enum.PartType.Cylinder, CanCollide = false, CastShadow = false })
			p("Bar", Vector3.new(7.8, 0.24, 0.24), hinge * at(-0.3, 0, side * -z) * UPRIGHT, C.Metal, { Shape = Enum.PartType.Cylinder, CanCollide = false, CastShadow = false })
		end
	end
	-- A warm lamp inside
	local lamp = p("Lamp", Vector3.new(1.4, 0.3, 0.7), at(4, 8.25, 0), C.Warm, { Material = Enum.Material.Neon, CanCollide = false, CastShadow = false })
	local glow = Instance.new("PointLight")
	glow.Color = C.Warm
	glow.Range = 18
	glow.Brightness = 1.2
	glow.Parent = lamp

	local function crate(x, y, z, size, turn, tilt)
		local base = at(x, y + size / 2, z) * CFrame.Angles(math.rad(tilt or 0), math.rad(turn), 0)
		p("Crate", Vector3.new(size, size, size), base, C.Wood, { Material = Enum.Material.WoodPlanks })
		for _, dy in { -0.42, 0.42 } do
			p("CrateBand", Vector3.new(size + 0.1, size * 0.14, size + 0.1), base * at(0, size * dy, 0), C.Trunk, { CanCollide = false, CastShadow = false })
		end
	end
	local function tire(x, y, z, size, turn, flat)
		local base = at(x, y, z) * CFrame.Angles(0, math.rad(turn), 0) * (if flat then UPRIGHT else CFrame.Angles(math.rad(14), 0, 0))
		p("Tire", Vector3.new(size * 0.35, size, size), base, C.Rubber, { Shape = Enum.PartType.Cylinder, CanCollide = false })
		p("TireHub", Vector3.new(size * 0.37, size * 0.45, size * 0.45), base, C.Yellow, { Shape = Enum.PartType.Cylinder, CanCollide = false, CastShadow = false })
	end
	local function gear(x, y, z, size, turn, gearColor)
		local base = at(x, y, z) * CFrame.Angles(0, math.rad(turn), 0) * UPRIGHT
		for index = 0, 3 do
			p("GearTooth", Vector3.new(0.4, size * 0.24, size), base * CFrame.Angles(math.rad(index * 45), 0, 0), gearColor, { Material = Enum.Material.Metal, CanCollide = false, CastShadow = false })
		end
		p("GearHub", Vector3.new(0.5, size * 0.4, size * 0.4), base, C.Ink, { Shape = Enum.PartType.Cylinder, CanCollide = false, CastShadow = false })
	end
	local function pipe(x, y, z, length, turn, tilt)
		p("Pipe", Vector3.new(length, 0.55, 0.55), at(x, y, z) * CFrame.Angles(0, math.rad(turn), math.rad(tilt or 0)), C.Metal, { Shape = Enum.PartType.Cylinder, Material = Enum.Material.Metal, CanCollide = false })
	end
	-- Still inside
	crate(-9.5, 0.5, -2, 3, 5)
	crate(-9.4, 0.5, 2, 3.2, -8)
	crate(-9.6, 3.6, 0, 2.8, 14)
	crate(-5.5, 0.5, -2.4, 2.6, 22)
	tire(-5.2, 2, 2.6, 3.4, 30, false)
	tire(-2, 1, -2.4, 3, 0, true)
	gear(0.5, 0.8, 2, 2.4, 10, C.Orange)
	crate(3.5, 0.5, -2.2, 2, 40)
	pipe(5, 0.9, 1.6, 6, 8)
	pipe(6, 1.2, 2.4, 5, -6, 4)
	gear(9.5, 0.8, -1.5, 2, 30, C.Yellow)
	-- Tumbling out and lying in the snow
	crate(13, 0, 0.4, 2.2, 28, 24)
	crate(16.5, 0, -2.6, 2, 63)
	crate(18.6, 0, 2.2, 1.6, 12)
	tire(14.6, 0.55, -3.4, 3, 0, true)
	tire(20.5, 1.4, -0.6, 3, 70, false)
	tire(17.4, 0.45, 5, 2.4, 0, true)
	gear(15.6, 0.25, 2.6, 2.6, 15, C.Orange)
	gear(19.4, 0.25, -3.6, 1.8, 50, C.Teal)
	gear(22.4, 0.25, 2.2, 1.5, 5, C.Red)
	pipe(17.2, 0.3, 0, 5, 64)
	pipe(21, 0.3, 4.4, 4, -24)
	p("Barrel", Vector3.new(3.6, 2.6, 2.6), at(14.4, 1.3, 5.6) * CFrame.Angles(0, math.rad(35), 0), C.Blue, { Shape = Enum.PartType.Cylinder })
	p("BarrelBand", Vector3.new(0.4, 2.75, 2.75), at(14.4, 1.3, 5.6) * CFrame.Angles(0, math.rad(35), 0), C.Ink, { Shape = Enum.PartType.Cylinder, CanCollide = false, CastShadow = false })
	for index = 1, 9 do -- bolts everywhere
		p("Bolt", Vector3.new(0.5, 0.28, 0.28), at(13 + index * 1.15, 0.16, math.sin(index * 2.4) * 4.6) * CFrame.Angles(0, index * 1.7, 0), if index % 2 == 0 then C.Yellow else C.Metal, { Shape = Enum.PartType.Cylinder, Material = Enum.Material.Metal, CanCollide = false, CastShadow = false })
	end
	m:AddTag("ScrapContainer")
	m.PrimaryPart = body
	return m
end

-- Stylized pine: trunk + three rotated tiers with snow on top. scale 1 = 20 studs tall.
function Prefabs.Pine(parent, cf, scale)
	scale = scale or 1
	local m = model(parent, "Pine")
	Prefabs.Part(m, {
		Name = "Trunk",
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(4 * scale, 1.8 * scale, 1.8 * scale),
		CFrame = cf * CFrame.new(0, 2 * scale, 0) * UPRIGHT,
		Color = C.Trunk,
	})
	local tiers = {
		{ Width = 11, Height = 5, Y = 6.5, Color = C.PineDark },
		{ Width = 8.2, Height = 4.5, Y = 10.5, Color = C.Pine },
		{ Width = 5.2, Height = 4, Y = 14.2, Color = C.Pine },
	}
	for index, tier in tiers do
		local twist = CFrame.Angles(0, math.rad(if index % 2 == 0 then 45 else 0), 0)
		Prefabs.Part(m, {
			Name = `Tier{index}`,
			Size = Vector3.new(tier.Width, tier.Height, tier.Width) * scale,
			CFrame = cf * CFrame.new(0, tier.Y * scale, 0) * twist,
			Color = tier.Color,
		})
		if index < #tiers then
			Prefabs.Part(m, {
				Name = `Snow{index}`,
				Size = Vector3.new(tier.Width * 0.82, 0.8, tier.Width * 0.82) * scale,
				CFrame = cf * CFrame.new(0, (tier.Y + tier.Height / 2) * scale, 0) * twist,
				Color = C.Snow,
				CastShadow = false,
			})
		end
	end
	Prefabs.Part(m, {
		Name = "Top",
		Size = Vector3.new(2.6, 2.2, 2.6) * scale,
		CFrame = cf * CFrame.new(0, 17.2 * scale, 0) * CFrame.Angles(0, math.rad(45), 0),
		Color = C.Snow,
	})
	return m
end

-- A fuller pine for the forest: eight-pointed tiers (two crossed blocks), snow on the boughs.
function Prefabs.ForestPine(parent, cf, scale, shadow)
	scale = scale or 1
	local m = model(parent, "ForestPine")
	Prefabs.Part(m, {
		Name = "Trunk", Shape = Enum.PartType.Cylinder, Size = Vector3.new(6, 1.7, 1.7) * scale,
		CFrame = cf * CFrame.new(0, 3 * scale, 0) * UPRIGHT, Color = C.Trunk,
	})
	local tiers = { { 9.6, 2.6, 5.4 }, { 8, 2.6, 8 }, { 6.2, 2.6, 10.6 }, { 4.4, 2.6, 13.2 }, { 2.6, 2.4, 15.6 } }
	for index, tier in tiers do
		local color = C.PineDark:Lerp(C.Pine, (index - 1) / 4)
		for turn = 0, 1 do
			Prefabs.Part(m, {
				Name = "Bough", Size = Vector3.new(tier[1], tier[2], tier[1] * 0.72) * scale,
				CFrame = cf * CFrame.new(0, tier[3] * scale, 0) * CFrame.Angles(0, math.rad(index * 27 + turn * 90), 0),
				Color = color, CanCollide = turn == 0 and index <= 2, CanQuery = false, CastShadow = shadow == true and turn == 0,
			})
		end
		if index <= 4 then
			Prefabs.Part(m, {
				Name = "Snow", Size = Vector3.new(tier[1] * 0.74, 0.5, tier[1] * 0.74) * scale,
				CFrame = cf * CFrame.new(0, (tier[3] + 1.45) * scale, 0) * CFrame.Angles(0, math.rad(index * 27 + 45), 0),
				Color = C.Snow, CanCollide = false, CanQuery = false, CastShadow = false,
			})
		end
	end
	return m
end

-- Forest floor pieces: stump, fallen trunk, bush, rock, mushrooms, tent, campfire.
function Prefabs.Stump(parent, cf, size)
	local m = model(parent, "Stump")
	Prefabs.Part(m, { Name = "Wood", Shape = Enum.PartType.Cylinder, Size = Vector3.new(1.6, 2.4, 2.4) * size, CFrame = cf * CFrame.new(0, 0.8 * size, 0) * UPRIGHT, Color = C.Trunk })
	Prefabs.Part(m, { Name = "Cut", Shape = Enum.PartType.Cylinder, Size = Vector3.new(0.1, 2, 2) * size, CFrame = cf * CFrame.new(0, 1.62 * size, 0) * UPRIGHT, Color = C.Wood, CanCollide = false, CastShadow = false })
	Prefabs.Part(m, { Name = "Ring", Shape = Enum.PartType.Cylinder, Size = Vector3.new(0.12, 0.9, 0.9) * size, CFrame = cf * CFrame.new(0, 1.63 * size, 0) * UPRIGHT, Color = C.Trunk, CanCollide = false, CastShadow = false })
end

function Prefabs.FallenTrunk(parent, cf, length)
	local m = model(parent, "FallenTrunk")
	Prefabs.Part(m, { Name = "Log", Shape = Enum.PartType.Cylinder, Size = Vector3.new(length, 2, 2), CFrame = cf * CFrame.new(0, 0.9, 0), Color = C.Trunk })
	Prefabs.Part(m, { Name = "Snow", Size = Vector3.new(length * 0.8, 0.4, 1.3), CFrame = cf * CFrame.new(0, 1.85, 0), Color = C.Snow, CanCollide = false, CastShadow = false })
	for _, x in { -1, 1 } do
		Prefabs.Part(m, { Name = "End", Shape = Enum.PartType.Cylinder, Size = Vector3.new(0.1, 1.7, 1.7), CFrame = cf * CFrame.new(x * length / 2, 0.9, 0), Color = C.Wood, CanCollide = false, CastShadow = false })
	end
	Prefabs.Part(m, { Name = "Branch", Shape = Enum.PartType.Cylinder, Size = Vector3.new(2.6, 0.5, 0.5), CFrame = cf * CFrame.new(length * 0.2, 2, 0.6) * CFrame.Angles(0, 0.4, 1), Color = C.Trunk, CanCollide = false, CastShadow = false })
end

function Prefabs.Bush(parent, cf, size)
	local m = model(parent, "Bush")
	for index, ball in { { 0, 1, 0, 3 }, { 1.6, 0.8, 0.5, 2.4 }, { -1.5, 0.7, -0.3, 2.2 } } do
		Prefabs.Part(m, { Name = "Leaves", Shape = Enum.PartType.Ball, Size = Vector3.one * ball[4] * size, CFrame = cf * CFrame.new(ball[1] * size, ball[2] * size, ball[3] * size), Color = if index == 1 then C.Pine else C.PineDark, CanCollide = false, CanQuery = false, CastShadow = false })
	end
	Prefabs.Part(m, { Name = "Snow", Shape = Enum.PartType.Ball, Size = Vector3.one * 2.2 * size, CFrame = cf * CFrame.new(0.2 * size, 1.6 * size, 0), Color = C.Snow, CanCollide = false, CanQuery = false, CastShadow = false })
end

function Prefabs.Rock(parent, cf, size)
	local m = model(parent, "Rock")
	Prefabs.Part(m, { Name = "Stone", Size = Vector3.new(3, 2, 2.4) * size, CFrame = cf * CFrame.new(0, 0.7 * size, 0) * CFrame.Angles(0.2, 0.6, 0.15), Color = Color3.fromRGB(128, 138, 158) })
	Prefabs.Part(m, { Name = "Stone", Size = Vector3.new(1.7, 1.3, 1.6) * size, CFrame = cf * CFrame.new(1.6 * size, 0.4 * size, 0.6 * size) * CFrame.Angles(-0.2, 1.2, 0.3), Color = Color3.fromRGB(108, 118, 140), CanCollide = false })
	Prefabs.Part(m, { Name = "Snow", Size = Vector3.new(2.2, 0.4, 1.8) * size, CFrame = cf * CFrame.new(0, 1.75 * size, 0) * CFrame.Angles(0.2, 0.6, 0.15), Color = C.Snow, CanCollide = false, CastShadow = false })
end

function Prefabs.Mushrooms(parent, cf)
	local m = model(parent, "Mushrooms")
	for _, spot in { { 0, 0, 1 }, { 0.9, 0.5, 0.7 }, { -0.7, 0.6, 0.55 } } do
		local s = spot[3]
		Prefabs.Part(m, { Name = "Stem", Shape = Enum.PartType.Cylinder, Size = Vector3.new(0.9, 0.35, 0.35) * s, CFrame = cf * CFrame.new(spot[1], 0.45 * s, spot[2]) * UPRIGHT, Color = C.Snow, CanCollide = false, CanQuery = false, CastShadow = false })
		Prefabs.Part(m, { Name = "Cap", Shape = Enum.PartType.Cylinder, Size = Vector3.new(0.4, 1.2, 1.2) * s, CFrame = cf * CFrame.new(spot[1], 1 * s, spot[2]) * UPRIGHT, Color = C.Red, CanCollide = false, CanQuery = false, CastShadow = false })
	end
end

function Prefabs.Campfire(parent, cf)
	local m = model(parent, "Campfire")
	for index = 0, 7 do
		Prefabs.Part(m, { Name = "Stone", Size = Vector3.new(0.9, 0.7, 0.7), CFrame = cf * CFrame.Angles(0, math.rad(index * 45), 0) * CFrame.new(1.7, 0.3, 0), Color = Color3.fromRGB(110, 118, 136), CanCollide = false, CastShadow = false })
	end
	for index = 0, 2 do
		Prefabs.Part(m, { Name = "Log", Shape = Enum.PartType.Cylinder, Size = Vector3.new(2.4, 0.45, 0.45), CFrame = cf * CFrame.Angles(0, math.rad(index * 60), 0) * CFrame.new(0, 0.5, 0) * CFrame.Angles(0, 0, 0.25), Color = C.Trunk, CanCollide = false, CastShadow = false })
	end
	local flame = Prefabs.Part(m, { Name = "Embers", Shape = Enum.PartType.Ball, Size = Vector3.new(1.1, 1.1, 1.1), CFrame = cf * CFrame.new(0, 0.7, 0), Color = C.Orange, Material = Enum.Material.Neon, CanCollide = false, CanQuery = false, CastShadow = false })
	local fire = Instance.new("Fire")
	fire.Size = 4
	fire.Heat = 6
	fire.Parent = flame
	local glow = Instance.new("PointLight")
	glow.Color = C.Warm
	glow.Range = 22
	glow.Brightness = 1.4
	glow.Parent = flame
end

function Prefabs.Tent(parent, cf, color)
	local m = model(parent, "Tent")
	for _, side in { -1, 1 } do
		Prefabs.Part(m, { Name = "Cloth", Size = Vector3.new(0.3, 6.4, 8), CFrame = cf * CFrame.new(side * 1.9, 2.5, 0) * CFrame.Angles(0, 0, math.rad(side * 36)), Color = color })
		Prefabs.Part(m, { Name = "Snow", Size = Vector3.new(0.4, 2.2, 8.2), CFrame = cf * CFrame.new(side * 0.75, 4.3, 0) * CFrame.Angles(0, 0, math.rad(side * 36)), Color = C.Snow, CanCollide = false, CastShadow = false })
		Prefabs.Part(m, { Name = "Peg", Shape = Enum.PartType.Cylinder, Size = Vector3.new(1.2, 0.2, 0.2), CFrame = cf * CFrame.new(side * 4.2, 0.4, 3.4) * UPRIGHT, Color = C.Wood, CanCollide = false, CastShadow = false })
	end
	Prefabs.Part(m, { Name = "Pole", Shape = Enum.PartType.Cylinder, Size = Vector3.new(8.6, 0.3, 0.3), CFrame = cf * CFrame.new(0, 5, 0) * CFrame.Angles(0, math.rad(90), 0), Color = C.Wood, CanCollide = false, CastShadow = false })
	Prefabs.Part(m, { Name = "Mat", Size = Vector3.new(5, 0.2, 7.4), CFrame = cf * CFrame.new(0, 0.15, 0), Color = C.Orange, CanCollide = false, CastShadow = false })
	Prefabs.Part(m, { Name = "Bag", Shape = Enum.PartType.Cylinder, Size = Vector3.new(5, 1.2, 1.2), CFrame = cf * CFrame.new(-0.8, 0.7, 0.3) * CFrame.Angles(0, math.rad(90), 0), Color = C.Blue, CanCollide = false, CastShadow = false })
end

-- Soft snow mound made of spheres sunk into the ground (domes; collision matches the look).
function Prefabs.SnowPile(parent, cf, size)
	size = size or 1
	local m = model(parent, "SnowPile")
	local balls = {
		{ D = 14, X = 0, Z = 0, Sink = 0.62 },
		{ D = 10, X = 5.5, Z = 2, Sink = 0.6 },
		{ D = 8, X = -5, Z = -1.5, Sink = 0.6 },
	}
	for index, ball in balls do
		local d = ball.D * size
		Prefabs.Part(m, {
			Name = `Mound{index}`,
			Shape = Enum.PartType.Ball,
			Size = Vector3.new(d, d, d),
			CFrame = cf * CFrame.new(ball.X * size, d / 2 - d * ball.Sink, ball.Z * size),
			Color = if index == 1 then C.Snow else C.SnowShade,
		})
	end
	return m
end

-- Snowy heap with colorful scrap sticking out of it.
function Prefabs.JunkHeap(parent, cf, size, seed)
	size = size or 1
	local random = newRandom(seed or 1)
	local m = model(parent, "JunkHeap")
	local d = 22 * size
	Prefabs.Part(m, {
		Name = "Mound",
		Shape = Enum.PartType.Ball,
		Size = Vector3.new(d, d, d),
		CFrame = cf * CFrame.new(0, d / 2 - d * 0.6, 0),
		Color = C.Snow,
	})
	for index = 1, 6 do
		local angle = (index / 6) * math.pi * 2 + random:NextNumber() * 0.6
		local radius = (3 + random:NextNumber() * 5) * size
		local height = (2.5 + random:NextNumber() * 3) * size
		local color = Prefabs.Accents[random:NextInteger(1, #Prefabs.Accents)]
		local tilt = CFrame.Angles(random:NextNumber() * 0.9, random:NextNumber() * 3, random:NextNumber() * 0.9)
		local isCylinder = index % 3 == 0
		Prefabs.Part(m, {
			Name = `Scrap{index}`,
			Shape = if isCylinder then Enum.PartType.Cylinder else nil,
			Size = if isCylinder
				then Vector3.new(5, 2.2, 2.2) * size
				else Vector3.new(2 + random:NextNumber() * 3, 1.2 + random:NextNumber() * 2, 2 + random:NextNumber() * 2) * size,
			CFrame = cf * CFrame.new(math.cos(angle) * radius, height, math.sin(angle) * radius) * tilt,
			Color = color,
			Material = if isCylinder then Enum.Material.Metal else Enum.Material.SmoothPlastic,
		})
	end
	return m
end

function Prefabs.TireStack(parent, cf, tires)
	local m = model(parent, "TireStack")
	for index = 1, tires do
		Prefabs.Part(m, {
			Name = `Tire{index}`,
			Shape = Enum.PartType.Cylinder,
			Size = Vector3.new(1.6, 5, 5),
			CFrame = cf * CFrame.new(0, 0.8 + (index - 1) * 1.6, 0) * CFrame.Angles(0, index * 0.5, 0) * UPRIGHT,
			Color = if index == tires then C.Yellow else C.Rubber,
		})
	end
	return m
end

-- Steel drum (4 tall, 3 wide): rolled rims, two rolling hoops, a lid with its bung, paint
-- running down from the top and a little snow on the lid. Small details cast no shadow.
function Prefabs.Barrel(parent, cf, color)
	local m = model(parent, "Barrel")
	local dark = color:Lerp(C.Ink, 0.45)
	local function ring(name, y, diameter, height, ringColor, shadow)
		return Prefabs.Part(m, {
			Name = name,
			Shape = Enum.PartType.Cylinder,
			Size = Vector3.new(height, diameter, diameter),
			CFrame = cf * CFrame.new(0, y, 0) * UPRIGHT,
			Color = ringColor,
			Material = Enum.Material.Metal,
			CanCollide = false,
			CanQuery = false,
			CastShadow = shadow == true,
		})
	end
	local body = ring("Body", 2, 2.9, 3.8, color, true)
	body.CanCollide = true
	body.CanQuery = true
	ring("RimBottom", 0.12, 3, 0.24, dark)
	ring("RimTop", 3.88, 3, 0.24, dark)
	ring("Hoop1", 1.33, 3.04, 0.2, dark)
	ring("Hoop2", 2.67, 3.04, 0.2, dark)
	ring("Lid", 3.93, 2.6, 0.06, color:Lerp(C.Ink, 0.25))
	Prefabs.Part(m, {
		Name = "Bung",
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(0.16, 0.42, 0.42),
		CFrame = cf * CFrame.new(0.75, 4.02, 0.3) * UPRIGHT,
		Color = C.Metal,
		Material = Enum.Material.Metal,
		CanCollide = false,
		CanQuery = false,
		CastShadow = false,
	})
	Prefabs.Part(m, {
		Name = "Drip",
		Size = Vector3.new(0.34, 1.3, 0.12),
		CFrame = cf * CFrame.Angles(0, math.rad(25), 0) * CFrame.new(0, 3.2, -1.43),
		Color = color:Lerp(Color3.new(1, 1, 1), 0.25),
		CanCollide = false,
		CanQuery = false,
		CastShadow = false,
	})
	Prefabs.Part(m, {
		Name = "Snow",
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(0.22, 1.9, 1.9),
		CFrame = cf * CFrame.new(-0.25, 4.03, -0.2) * UPRIGHT,
		Color = C.Snow,
		Material = Enum.Material.Snow,
		CanCollide = false,
		CanQuery = false,
		CastShadow = false,
	})
	return m
end

-- Small industrial shed (14 x 9 x 12) with a snowy roof and a warm glowing window.
function Prefabs.Shed(parent, cf, wallColor, roofColor)
	local m = model(parent, "Shed")
	Prefabs.Part(m, { Name = "Walls", Size = Vector3.new(14, 9, 12), CFrame = cf * CFrame.new(0, 4.5, 0), Color = wallColor })
	Prefabs.Part(m, {
		Name = "Roof",
		Size = Vector3.new(16, 1, 14),
		CFrame = cf * CFrame.new(0, 9.5, 0),
		Color = roofColor,
	})
	Prefabs.Part(m, {
		Name = "RoofSnow",
		Size = Vector3.new(15.4, 0.8, 13.4),
		CFrame = cf * CFrame.new(0, 10.4, 0),
		Color = C.Snow,
	})
	Prefabs.Part(m, {
		Name = "Door",
		Size = Vector3.new(4, 6.5, 0.3),
		CFrame = cf * CFrame.new(-3, 3.25, -6.1),
		Color = wallColor:Lerp(C.Ink, 0.35),
	})
	Prefabs.Part(m, {
		Name = "Window",
		Size = Vector3.new(4, 2.6, 0.3),
		CFrame = cf * CFrame.new(3.5, 5, -6.1),
		Color = C.Warm,
		Material = Enum.Material.Neon,
		CastShadow = false,
	})
	return m
end

-- Detailed winter cottage, footprint 16 x 14, front = -Z: timber frame, gabled roof with snow,
-- framed glowing windows, porch, chimney. About 40 parts, no lights.
function Prefabs.Cottage(parent, cf, wallColor, roofColor)
	local m = model(parent, "Cottage")
	local timber = C.Trunk
	local function p(name, size, offset, color, extra)
		local props = extra or {}
		props.Name = name
		props.Size = size
		props.CFrame = cf * offset
		props.Color = color
		return Prefabs.Part(m, props)
	end
	local at = CFrame.new
	p("Foundation", Vector3.new(14.6, 1, 12.6), at(0, 0.5, 0), rgb(150, 160, 178))
	p("Walls", Vector3.new(14, 7, 12), at(0, 4.5, 0), wallColor)
	-- Timber frame
	for _, x in { -6.9, 6.9 } do
		for _, z in { -5.9, 5.9 } do
			p("Corner", Vector3.new(0.9, 7, 0.9), at(x, 4.5, z), timber, { Material = Enum.Material.Wood })
		end
	end
	for _, z in { -6.05, 6.05 } do
		p("Beam", Vector3.new(14.6, 0.6, 0.4), at(0, 7.8, z), timber, { Material = Enum.Material.Wood, CastShadow = false })
		p("Sill", Vector3.new(14.6, 0.5, 0.4), at(0, 1.25, z), timber, { Material = Enum.Material.Wood, CastShadow = false })
	end
	-- Gable ends and the roof
	for _, x in { -6.7, 6.7 } do
		p("Gable", Vector3.new(0.6, 4.7, 6), at(x, 10.35, -3), wallColor, { ClassName = "WedgePart" })
		p("Gable", Vector3.new(0.6, 4.7, 6), at(x, 10.35, 3) * CFrame.Angles(0, math.pi, 0), wallColor, { ClassName = "WedgePart" })
		p("GableBeam", Vector3.new(0.4, 4.4, 0.5), at(x * 1.06, 10, 0), timber, { Material = Enum.Material.Wood, CastShadow = false })
	end
	local pitch = math.rad(38)
	for _, side in { -1, 1 } do
		local slope = at(0, 10.2, side * 3.55) * CFrame.Angles(side * pitch, 0, 0)
		p("Roof", Vector3.new(16.4, 0.7, 9.4), slope, roofColor)
		p("RoofSnow", Vector3.new(16, 0.55, 6.4), slope * at(0, 0.6, -side * 1.3), C.Snow)
		p("Edge", Vector3.new(16.8, 0.5, 0.4), slope * at(0, -0.1, side * 4.75), timber, { Material = Enum.Material.Wood, CastShadow = false })
	end
	p("Ridge", Vector3.new(16.6, 0.9, 1.6), at(0, 13.2, 0), C.Snow)
	-- Chimney
	p("Chimney", Vector3.new(2, 5, 2), at(4.2, 12.4, 2.2), rgb(170, 88, 72))
	p("ChimneyRim", Vector3.new(2.5, 0.6, 2.5), at(4.2, 14.8, 2.2), rgb(120, 62, 54), { CastShadow = false })
	p("ChimneySnow", Vector3.new(2.2, 0.4, 2.2), at(4.2, 15.2, 2.2), C.Snow, { CastShadow = false })
	-- Door with frame, knob and wreath
	p("DoorFrame", Vector3.new(4.2, 6, 0.3), at(-2.6, 4, -6.15), C.Snow, { CastShadow = false })
	p("Door", Vector3.new(3.4, 5.5, 0.3), at(-2.6, 3.8, -6.3), roofColor, { CastShadow = false })
	p("Knob", Vector3.new(0.4, 0.4, 0.4), at(-1.4, 3.7, -6.5), C.Yellow, { Shape = Enum.PartType.Ball, CastShadow = false })
	p("Wreath", Vector3.new(0.25, 1.5, 1.5), at(-2.6, 5.2, -6.5) * CFrame.Angles(0, math.rad(90), 0), C.Pine, { Shape = Enum.PartType.Cylinder, CastShadow = false })
	p("Bow", Vector3.new(0.5, 0.5, 0.3), at(-2.6, 4.6, -6.65), C.Red, { CastShadow = false })
	-- Front windows, one on each side wall
	local function window(frame)
		p("WindowFrame", Vector3.new(3.4, 3.2, 0.25), frame, C.Snow, { CastShadow = false })
		p("Window", Vector3.new(2.8, 2.6, 0.25), frame * at(0, 0, -0.12), C.Warm, { Material = Enum.Material.Neon, CastShadow = false })
		p("Cross", Vector3.new(0.25, 2.6, 0.2), frame * at(0, 0, -0.22), C.Snow, { CastShadow = false })
		p("WindowSill", Vector3.new(3.8, 0.4, 0.8), frame * at(0, -1.8, -0.2), C.Snow, { CastShadow = false })
	end
	window(at(3.6, 4.8, -6.15))
	window(at(-7.15, 4.8, 0) * CFrame.Angles(0, math.rad(90), 0))
	window(at(7.15, 4.8, 0) * CFrame.Angles(0, math.rad(-90), 0))
	-- Porch
	p("Porch", Vector3.new(6.4, 0.5, 3.4), at(-2.6, 0.55, -8), C.Wood, { Material = Enum.Material.WoodPlanks })
	for _, x in { -5.4, 0.2 } do
		p("PorchPost", Vector3.new(0.5, 6, 0.5), at(x, 3.6, -9.2), timber, { Material = Enum.Material.Wood })
	end
	p("PorchRoof", Vector3.new(7, 0.5, 4.2), at(-2.6, 7, -8) * CFrame.Angles(math.rad(-12), 0, 0), roofColor)
	p("PorchSnow", Vector3.new(6.6, 0.4, 3.6), at(-2.6, 7.42, -8) * CFrame.Angles(math.rad(-12), 0, 0), C.Snow, { CastShadow = false })
	p("Lantern", Vector3.new(0.8, 1, 0.8), at(0.2, 5.8, -9.2), C.Yellow, { Material = Enum.Material.Neon, CastShadow = false })
	-- Firewood by the wall
	for index = 0, 2 do
		p("Log", Vector3.new(3, 1, 1), at(4.6, 0.9 + (index == 2 and 0.9 or 0), -7 - (index % 2) * 1 + (index == 2 and -0.5 or 0)), C.Trunk, { Shape = Enum.PartType.Cylinder, CastShadow = false })
	end
	return m
end

-- Lamp post with a warm bulb. Only some lamps get a real PointLight (lights cost GPU time).
function Prefabs.Lamp(parent, cf, withLight)
	local m = model(parent, "Lamp")
	Prefabs.Part(m, {
		Name = "Pole",
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(11, 0.7, 0.7),
		CFrame = cf * CFrame.new(0, 5.5, 0) * UPRIGHT,
		Color = C.Ink,
	})
	Prefabs.Part(m, {
		Name = "Cap",
		Size = Vector3.new(2.4, 0.5, 2.4),
		CFrame = cf * CFrame.new(0, 12.6, 0),
		Color = C.Ink,
	})
	local bulb = Prefabs.Part(m, {
		Name = "Bulb",
		Shape = Enum.PartType.Ball,
		Size = Vector3.new(1.8, 1.8, 1.8),
		CFrame = cf * CFrame.new(0, 11.6, 0),
		Color = C.Warm,
		Material = Enum.Material.Neon,
		CastShadow = false,
	})
	if withLight then
		local light = Instance.new("PointLight")
		light.Color = rgb(255, 190, 120)
		light.Range = 18
		light.Brightness = 1.3
		light.Shadows = false
		light.Parent = bulb
	end
	return m
end

function Prefabs.Bollard(parent, cf, color)
	local m = model(parent, "Bollard")
	Prefabs.Part(m, {
		Name = "Post",
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(2.4, 1.2, 1.2),
		CFrame = cf * CFrame.new(0, 1.2, 0) * UPRIGHT,
		Color = color,
	})
	Prefabs.Part(m, {
		Name = "Top",
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(0.4, 1.3, 1.3),
		CFrame = cf * CFrame.new(0, 2.5, 0) * UPRIGHT,
		Color = C.Snow,
		CastShadow = false,
	})
	return m
end

function Prefabs.LogPile(parent, cf)
	local m = model(parent, "LogPile")
	local logs = { { 0, 1.1, -1.1 }, { 0, 1.1, 1.1 }, { 0, 2.9, 0 } }
	for index, offset in logs do
		Prefabs.Part(m, {
			Name = `Log{index}`,
			Shape = Enum.PartType.Cylinder,
			Size = Vector3.new(9, 2.2, 2.2),
			CFrame = cf * CFrame.new(offset[1], offset[2], offset[3]),
			Color = C.Wood,
		})
	end
	return m
end

-- Two posts and a colored board with text on its front (-Z) face. The posts end at
-- the board's lower edge, so they never cover the text on either side.
function Prefabs.Sign(parent, cf, text, color)
	local m = model(parent, "Sign")
	for _, x in { -5, 5 } do
		Prefabs.Part(m, {
			Name = "Post",
			Size = Vector3.new(0.6, 4.3, 0.6),
			CFrame = cf * CFrame.new(x, 2.15, 0),
			Color = C.Ink,
		})
	end
	local board = Prefabs.Part(m, {
		Name = "Board",
		Size = Vector3.new(14, 4.6, 0.6),
		CFrame = cf * CFrame.new(0, 6.6, 0),
		Color = color,
	})
	Prefabs.Part(m, {
		Name = "Snow",
		Size = Vector3.new(14.2, 0.5, 1.2),
		CFrame = cf * CFrame.new(0, 9.15, 0),
		Color = C.Snow,
		CastShadow = false,
	})

	local gui = Instance.new("SurfaceGui")
	gui.Face = Enum.NormalId.Front
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = 20
	gui.LightInfluence = 0
	gui.Parent = board
	local label = Instance.new("TextLabel")
	label.BackgroundTransparency = 1
	label.Size = roblox.UDim2.fromScale(0.92, 0.8)
	label.Position = roblox.UDim2.fromScale(0.04, 0.1)
	label.Text = text
	label.TextScaled = true
	label.Font = Enum.Font.FredokaOne
	label.TextColor3 = C.Snow
	label.TextStrokeTransparency = 0.4
	label.TextStrokeColor3 = C.Ink
	label.Parent = gui
	local back = Instance.new("SurfaceGui")
	back.Face = Enum.NormalId.Back
	back.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	back.PixelsPerStud = 20
	back.LightInfluence = 0
	back.Parent = board
	local backLabel = label:Clone()
	backLabel.Parent = back
	return m
end

-- Tall yellow crane: a landmark visible from everywhere in the yard.
function Prefabs.Crane(parent, cf)
	local m = model(parent, "Crane")
	Prefabs.Part(m, { Name = "Base", Size = Vector3.new(10, 2, 10), CFrame = cf * CFrame.new(0, 1, 0), Color = C.Ink })
	Prefabs.Part(m, { Name = "Mast", Size = Vector3.new(3.2, 48, 3.2), CFrame = cf * CFrame.new(0, 26, 0), Color = C.Yellow })
	Prefabs.Part(m, { Name = "Jib", Size = Vector3.new(46, 2.4, 2.4), CFrame = cf * CFrame.new(12, 50, 0), Color = C.Yellow })
	Prefabs.Part(m, { Name = "Cab", Size = Vector3.new(5, 4, 4.5), CFrame = cf * CFrame.new(0, 47, -3.6), Color = C.Red })
	Prefabs.Part(m, {
		Name = "Counterweight",
		Size = Vector3.new(5, 4, 4),
		CFrame = cf * CFrame.new(-9, 47.6, 0),
		Color = C.Ink,
	})
	Prefabs.Part(m, {
		Name = "Cable",
		Size = Vector3.new(0.3, 22, 0.3),
		CFrame = cf * CFrame.new(30, 38, 0),
		Color = C.Ink,
		CastShadow = false,
	})
	Prefabs.Part(m, {
		Name = "Hook",
		Size = Vector3.new(4, 1.4, 4),
		CFrame = cf * CFrame.new(30, 26.5, 0),
		Color = C.Orange,
	})
	return m
end

-- Reserved base plot: flat pad with a colored border and a numbered sign. Empty on purpose.
function Prefabs.BasePlot(parent, cf, index, color, size)
	local m = model(parent, `Plot{index}`)
	local pad = Prefabs.Part(m, {
		Name = "Pad",
		Size = Vector3.new(size, 0.3, size),
		CFrame = cf * CFrame.new(0, 0.15, 0),
		Color = C.SnowShade,
	})
	local half = size / 2
	local border = 1.6
	-- Higher than the pad and 0.3 wider on every side, so no two faces share a plane.
	local out = 0.3
	local strips = {
		{ Vector3.new(size + out * 2, 0.9, border), CFrame.new(0, 0.15, -half - out + border / 2) },
		{ Vector3.new(size + out * 2, 0.9, border), CFrame.new(0, 0.15, half + out - border / 2) },
		{ Vector3.new(border, 0.9, size + (out - border) * 2), CFrame.new(-half - out + border / 2, 0.15, 0) },
		{ Vector3.new(border, 0.9, size + (out - border) * 2), CFrame.new(half + out - border / 2, 0.15, 0) },
	}
	for stripIndex, strip in strips do
		Prefabs.Part(m, {
			Name = `Border{stripIndex}`,
			Size = strip[1],
			CFrame = cf * strip[2],
			Color = color,
			CastShadow = false,
		})
	end
	-- Sign outside the edge nearest to the map's center (the ring road), facing outwards from the
	-- base, text on both sides. Placed in world space: it does not depend on the plot's rotation.
	local center = Vector3.new(cf.Position.X, 0, cf.Position.Z)
	local toCenter = -center.Unit
	local sideways = Vector3.new(-toCenter.Z, 0, toCenter.X)
	local at = center + toCenter * (half + 2.5) + sideways * (half - 8)
	Prefabs.Sign(m, CFrame.new(at) * CFrame.Angles(0, math.atan2(-toCenter.X, -toCenter.Z), 0), `BASE {index}`, color)

	m:SetAttribute("PlotId", index)
	m:SetAttribute("Owner", 0) -- UserId of the owner; 0 = free (used by a later stage)
	m:AddTag("BasePlot")
	m.PrimaryPart = pad
	return m
end

function Prefabs.Spawn(parent, cf, index)
	local spawn = Instance.new("SpawnLocation")
	spawn.Name = `Spawn{index}`
	spawn.Anchored = true
	spawn.Size = Vector3.new(7, 0.4, 7)
	spawn.CFrame = cf * CFrame.new(0, 0.2, 0)
	spawn.Color = C.Ice
	spawn.Material = Enum.Material.SmoothPlastic
	spawn.TopSurface = Enum.SurfaceType.Smooth
	spawn.BottomSurface = Enum.SurfaceType.Smooth
	spawn.Neutral = true
	spawn.Duration = 0 -- no force field
	spawn.CanTouch = true -- SpawnLocations need touch to work
	spawn.Parent = parent
	count += 1
	return spawn
end

-- The Recycling Machine (centerpiece of the plaza). cf = center of its base on the ground,
-- -Z = front (input slot, chamber, output tray). About 40 anchored parts.
-- Parts the client animates are named: InputDoor, Gear1/Gear2 (Models whose parts all share
-- the gear center), PistonHead, Light1..3, ChamberGlow, Screen, OutputPedestal, RewardPoint.
function Prefabs.RecyclingMachine(parent, cf, machineId)
	local m = model(parent, "RecyclingMachine")
	local function p(props)
		props.CFrame = cf * props.CFrame
		return Prefabs.Part(m, props)
	end
	local Metal = rgb(150, 162, 180)
	local Dark = rgb(38, 46, 66)

	-- Base, body, roof
	p({ Name = "Base", Size = Vector3.new(22, 1.2, 16), CFrame = CFrame.new(0, 0.6, 0), Color = C.Blue })
	p({ Name = "Body", Size = Vector3.new(14, 11, 11), CFrame = CFrame.new(0, 6.7, 1), Color = C.Orange })
	p({ Name = "BodyStripe", Size = Vector3.new(14.2, 1, 11.2), CFrame = CFrame.new(0, 2.2, 1), Color = C.Yellow, CastShadow = false })
	p({ Name = "Roof", Size = Vector3.new(15, 1, 12), CFrame = CFrame.new(0, 12.7, 1), Color = Metal, Material = Enum.Material.Metal })
	p({ Name = "RoofSnow", Size = Vector3.new(14.4, 0.7, 11.4), CFrame = CFrame.new(0, 13.5, 1), Color = C.Snow })

	-- Chimney
	p({
		Name = "Chimney",
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(6, 2.4, 2.4),
		CFrame = CFrame.new(4.5, 16, 4) * UPRIGHT,
		Color = Metal,
		Material = Enum.Material.Metal,
	})
	p({
		Name = "ChimneySnow",
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(0.6, 2.8, 2.8),
		CFrame = CFrame.new(4.5, 19.2, 4) * UPRIGHT,
		Color = C.Snow,
	})

	-- Input (front-left): hopper frame, dark slot, door that slides up while accepting
	p({ Name = "Hopper", Size = Vector3.new(6.5, 5, 3.6), CFrame = CFrame.new(-3.5, 6, -6.3), Color = C.Yellow })
	p({
		ClassName = "WedgePart",
		Name = "HopperFunnel",
		Size = Vector3.new(6.5, 2, 3.6),
		CFrame = CFrame.new(-3.5, 9.5, -6.3),
		Color = C.Yellow,
	})
	p({ Name = "InputSlot", Size = Vector3.new(4.6, 2.6, 0.2), CFrame = CFrame.new(-3.5, 6, -8.15), Color = Dark, CastShadow = false })
	p({
		Name = "InputDoor",
		Size = Vector3.new(5, 3, 0.3),
		CFrame = CFrame.new(-3.5, 6, -8.4),
		Color = C.Yellow:Lerp(C.Ink, 0.25),
		CastShadow = false,
	})

	-- Screen above the input (the client draws the progress bar on it)
	p({ Name = "ScreenFrame", Size = Vector3.new(5.6, 2.8, 0.4), CFrame = CFrame.new(-3.5, 10.6, -4.6), Color = Dark })
	p({ Name = "Screen", Size = Vector3.new(5, 2.2, 0.2), CFrame = CFrame.new(-3.5, 10.6, -4.85), Color = rgb(20, 30, 50), CastShadow = false })

	-- Processing chamber (front-right): round window with a glow that follows the state
	p({
		Name = "ChamberRing",
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(0.6, 5.2, 5.2),
		CFrame = CFrame.new(3.5, 8.4, -4.6) * CFrame.Angles(0, math.rad(90), 0),
		Color = Metal,
		Material = Enum.Material.Metal,
	})
	p({
		Name = "ChamberGlow",
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(0.4, 4.2, 4.2),
		CFrame = CFrame.new(3.5, 8.4, -4.85) * CFrame.Angles(0, math.rad(90), 0),
		Color = C.Teal,
		Material = Enum.Material.Neon,
		CastShadow = false,
	})

	-- Output (front-right, low): chute, tray and the pedestal the reward appears on
	p({ Name = "OutputChute", Size = Vector3.new(4, 1.8, 0.3), CFrame = CFrame.new(3.5, 4.2, -4.65), Color = Dark, CastShadow = false })
	p({ Name = "OutputTray", Size = Vector3.new(6, 1.2, 4.4), CFrame = CFrame.new(3.5, 1.8, -6.8), Color = C.Blue })
	p({
		Name = "OutputPedestal",
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(0.5, 3.2, 3.2),
		CFrame = CFrame.new(3.5, 2.65, -6.9) * UPRIGHT,
		Color = Metal,
		Material = Enum.Material.Metal,
	})
	p({
		Name = "RewardPoint",
		Size = Vector3.new(0.2, 0.2, 0.2),
		CFrame = CFrame.new(3.5, 5.2, -6.9),
		Transparency = 1,
		CanCollide = false,
		CanQuery = false,
		CastShadow = false,
	})

	-- Gears on the right side (spin while processing). All parts share the gear's center so a
	-- rotation about the center needs no position change.
	local function gear(name, center, diameter)
		local g = model(m, name)
		local base = cf * CFrame.new(center)
		Prefabs.Part(g, {
			Name = "Disk",
			Shape = Enum.PartType.Cylinder,
			Size = Vector3.new(0.7, diameter, diameter),
			CFrame = base,
			Color = C.Yellow,
			Material = Enum.Material.Metal,
		})
		Prefabs.Part(g, { Name = "ToothA", Size = Vector3.new(0.9, diameter + 1.2, 0.8), CFrame = base, Color = C.Yellow:Lerp(C.Ink, 0.2) })
		Prefabs.Part(g, { Name = "ToothB", Size = Vector3.new(0.9, 0.8, diameter + 1.2), CFrame = base, Color = C.Yellow:Lerp(C.Ink, 0.2) })
		Prefabs.Part(g, {
			Name = "Hub",
			Shape = Enum.PartType.Cylinder,
			Size = Vector3.new(1.1, 1.2, 1.2),
			CFrame = base,
			Color = Dark,
			Material = Enum.Material.Metal,
		})
		return g
	end
	gear("Gear1", Vector3.new(7.45, 8.4, -1.2), 4.4)
	gear("Gear2", Vector3.new(7.45, 4.6, 2.4), 3.2)

	-- Piston on the roof (pumps while processing)
	p({ Name = "PistonBase", Size = Vector3.new(2.6, 1, 2.6), CFrame = CFrame.new(-4, 14.3, 3), Color = Dark })
	p({
		Name = "PistonRod",
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(3, 0.9, 0.9),
		CFrame = CFrame.new(-4, 16.2, 3) * UPRIGHT,
		Color = Metal,
		Material = Enum.Material.Metal,
	})
	p({ Name = "PistonHead", Size = Vector3.new(2.2, 1, 2.2), CFrame = CFrame.new(-4, 17.9, 3), Color = C.Orange })

	-- Status lights along the front roof edge
	for index, x in { -5, 0, 5 } do
		p({
			Name = `Light{index}`,
			Shape = Enum.PartType.Ball,
			Size = Vector3.new(1.2, 1.2, 1.2),
			CFrame = CFrame.new(x, 13.4, -4.9),
			Color = C.Green,
			Material = Enum.Material.Neon,
			CastShadow = false,
		})
	end

	-- Big recycling sign on the roof, readable from both sides of the plaza
	for _, x in { -3.6, 3.6 } do
		p({ Name = "SignPost", Size = Vector3.new(0.5, 3.2, 0.4), CFrame = CFrame.new(x, 15.45, -1.5), Color = Dark })
	end
	local board = p({ Name = "SignBoard", Size = Vector3.new(10, 5, 0.6), CFrame = CFrame.new(0, 19.6, -1.5), Color = C.Green })
	p({ Name = "SignSnow", Size = Vector3.new(10.2, 0.6, 1), CFrame = CFrame.new(0, 22.3, -1.5), Color = C.Snow, CastShadow = false })
	for _, face in { Enum.NormalId.Front, Enum.NormalId.Back } do
		local gui = Instance.new("SurfaceGui")
		gui.Face = face
		gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
		gui.PixelsPerStud = 30
		gui.LightInfluence = 0
		gui.Parent = board
		local symbol = Instance.new("TextLabel")
		symbol.BackgroundTransparency = 1
		symbol.Size = roblox.UDim2.fromScale(0.34, 0.9)
		symbol.Position = roblox.UDim2.fromScale(0.02, 0.05)
		symbol.Text = "♻"
		symbol.TextScaled = true
		symbol.Font = Enum.Font.GothamBold
		symbol.TextColor3 = C.Snow
		symbol.Parent = gui
		local label = Instance.new("TextLabel")
		label.BackgroundTransparency = 1
		label.Size = roblox.UDim2.fromScale(0.6, 0.62)
		label.Position = roblox.UDim2.fromScale(0.37, 0.19)
		label.Text = "RECYCLE"
		label.TextScaled = true
		label.Font = Enum.Font.FredokaOne
		label.TextColor3 = C.Snow
		label.TextStrokeTransparency = 0.5
		label.TextStrokeColor3 = C.Ink
		label.Parent = gui
	end

	-- Snow piles at the base corners
	for _, corner in { Vector3.new(-10, 0, -7), Vector3.new(10, 0, 7) } do
		p({
			Name = "Snow",
			Shape = Enum.PartType.Ball,
			Size = Vector3.new(4, 4, 4),
			CFrame = CFrame.new(corner + Vector3.new(0, 0.2, 0)),
			Color = C.Snow,
		})
	end

	-- Center of the interaction area (MachineService puts the ProximityPrompt here)
	p({
		Name = "PromptAnchor",
		Size = Vector3.new(1, 1, 1),
		CFrame = CFrame.new(0, 5, 0),
		Transparency = 1,
		CanCollide = false,
		CanQuery = false,
		CastShadow = false,
	})

	if machineId ~= nil then
		m:SetAttribute("MachineId", machineId)
	end
	m:AddTag("RecyclingMachine")
	m.WorldPivot = cf -- the base's center on the ground, so PivotTo places it on a plot
	-- A ~40-part landmark every client animates: always fully present, never streamed out.
	m.ModelStreamingMode = Enum.ModelStreamingMode.Persistent
	return m
end

-- Invisible box that marks where junk spawns (read by JunkService through the tag).
function Prefabs.JunkSpawnArea(parent, cf, sizeX, sizeZ, name)
	local part = Prefabs.Part(parent, {
		Name = name or "JunkSpawnArea",
		Size = Vector3.new(sizeX, 2, sizeZ),
		CFrame = cf * CFrame.new(0, 1, 0),
		Transparency = 1,
		CanCollide = false,
		CanQuery = false,
		CastShadow = false,
	})
	part:AddTag("JunkSpawn")
	return part
end

return Prefabs
