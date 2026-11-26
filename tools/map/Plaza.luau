--[[
	Plaza: the decoration of the start area (run by Lune, see build.luau). Pure looks:
	no scripts, no lights (glow comes from Neon), big simple shapes, nothing in the walking lanes
	(spawns at z = -27, spokes along the axes).

	Parts tagged "PlazaSpin" turn around their own X axis on every client (attribute Speed, in
	radians per second; client/PlazaController).
]]

local roblox = require("@lune/roblox")
local Prefabs = require("./Prefabs")

local Instance = roblox.Instance
local Vector3 = roblox.Vector3
local CFrame = roblox.CFrame
local Color3 = roblox.Color3
local Enum = roblox.Enum
local C = Prefabs.Colors

local Plaza = {}

local FLOOR = 0.4 -- top of the plaza floor
local UPRIGHT = CFrame.Angles(0, 0, math.rad(90))
local STONE = Color3.fromRGB(196, 210, 232)
local STONE_DARK = Color3.fromRGB(168, 186, 214)
local GOLD = Color3.fromRGB(255, 205, 50)
local BULBS = { C.Red, C.Yellow, C.Green, C.Blue, C.Purple }

local function Part(parent, props)
	props.CastShadow = if props.CastShadow == nil then false else props.CastShadow
	return Prefabs.Part(parent, props)
end

local function model(parent, name)
	local m = Instance.new("Model")
	m.Name = name
	m.Parent = parent
	return m
end

local function yaw(degrees)
	return CFrame.Angles(0, math.rad(degrees), 0)
end

local function polar(radius, degrees)
	local a = math.rad(degrees)
	return Vector3.new(radius * math.cos(a), 0, radius * math.sin(a))
end

-- A thin disc on the floor. Every layer is 0.06 higher than the one below: smaller steps
-- flicker (z-fighting) when the floor is seen from far away.
local function disc(parent, name, radius, layer, color)
	Part(parent, {
		Name = name,
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(0.1, radius * 2, radius * 2),
		CFrame = CFrame.new(0, FLOOR - 0.05 + layer * 0.06, 0) * UPRIGHT, -- top = FLOOR + layer * 0.06
		Color = color,
		CanCollide = false,
		CanQuery = false,
	})
end

local function floor(parent)
	disc(parent, "Ring1", 38.5, 1, STONE_DARK)
	disc(parent, "Ring2", 36.5, 2, STONE)
	disc(parent, "Ring3", 24, 3, STONE_DARK)
	disc(parent, "Ring4", 23, 4, Color3.fromRGB(214, 225, 242))
	-- Compass star: eight blades, orange and teal.
	for index = 0, 7 do
		Part(parent, {
			Name = "Blade",
			Size = Vector3.new(if index % 2 == 0 then 1.6 else 0.9, 0.1, 10.5),
			CFrame = yaw(index * 45) * CFrame.new(0, FLOOR + 0.15, -30.2), -- top 0.06 above Ring2
			Color = if index % 2 == 0 then C.Orange else C.Teal,
			CanCollide = false,
			CanQuery = false,
		})
	end
	-- Bolts around the outer ring.
	for index = 0, 15 do
		Part(parent, {
			Name = "Bolt",
			Shape = Enum.PartType.Cylinder,
			Size = Vector3.new(0.16, 1, 1),
			CFrame = CFrame.new(polar(37.5, 11.25 + index * 22.5) + Vector3.new(0, FLOOR + 0.13, 0)) * UPRIGHT,
			Color = C.Metal,
			CanCollide = false,
			CanQuery = false,
		})
	end
end

-- Gate behind the spawns: JUNKSHOT sign between two container towers, with a string of bulbs.
local function gate(parent)
	local m = model(parent, "StartGate")
	local cf = CFrame.new(0, FLOOR, -37)
	for side = -1, 1, 2 do
		Part(m, { Name = "Tower", Size = Vector3.new(4.5, 13, 4.5), CFrame = cf * CFrame.new(side * 27, 6.5, 0), Color = if side < 0 then C.Orange else C.Teal, CastShadow = true })
		for level = 0, 2 do
			Part(m, { Name = "Rib", Size = Vector3.new(4.9, 0.6, 4.9), CFrame = cf * CFrame.new(side * 27, 1.2 + level * 5.3, 0), Color = C.Ink })
		end
		Part(m, { Name = "Cap", Size = Vector3.new(5.6, 0.8, 5.6), CFrame = cf * CFrame.new(side * 27, 13.4, 0), Color = C.Snow })
		Part(m, { Name = "Beacon", Shape = Enum.PartType.Ball, Size = Vector3.new(2.4, 2.4, 2.4), CFrame = cf * CFrame.new(side * 27, 14.8, 0), Color = GOLD, Material = Enum.Material.Neon })
	end
	Part(m, { Name = "Beam", Size = Vector3.new(50, 1.2, 1.2), CFrame = cf * CFrame.new(0, 12, 0), Color = C.Ink })
	local board = Part(m, { Name = "Sign", Size = Vector3.new(26, 6.4, 1), CFrame = cf * CFrame.new(0, 15.4, 0), Color = C.Ink, CastShadow = true })
	Part(m, { Name = "SignTop", Size = Vector3.new(27, 0.7, 1.6), CFrame = cf * CFrame.new(0, 18.9, 0), Color = C.Snow })
	for _, x in { -13.2, 13.2 } do
		Part(m, { Name = "SignSide", Size = Vector3.new(0.6, 6.4, 1.2), CFrame = cf * CFrame.new(x, 15.4, 0), Color = GOLD })
	end
	for _, face in { Enum.NormalId.Front, Enum.NormalId.Back } do
		local gui = Instance.new("SurfaceGui")
		gui.Face = face
		gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
		gui.PixelsPerStud = 20
		gui.LightInfluence = 0
		gui.Parent = board
		local label = Instance.new("TextLabel")
		label.BackgroundTransparency = 1
		label.Size = roblox.UDim2.fromScale(0.92, 0.86)
		label.Position = roblox.UDim2.fromScale(0.04, 0.07)
		label.Text = "JUNKSHOT"
		label.TextScaled = true
		label.Font = Enum.Font.FredokaOne
		label.TextColor3 = GOLD
		label.Parent = gui
	end
	-- Hanging bulbs, lowest in the middle.
	for index = 0, 14 do
		local x = -23.8 + index * 3.4
		local sag = 1.6 * (1 - (x / 24) ^ 2)
		Part(m, {
			Name = "Bulb",
			Shape = Enum.PartType.Ball,
			Size = Vector3.new(0.9, 0.9, 0.9),
			CFrame = cf * CFrame.new(x, 11 - sag, 0),
			Color = BULBS[index % #BULBS + 1],
			Material = Enum.Material.Neon,
			CanCollide = false,
			CanQuery = false,
		})
	end
end

-- One gear: a wheel with teeth, all in one spinning model-less group around its center.
local function gear(parent, center, radius, color, speed)
	local function spin(part)
		part:AddTag("PlazaSpin")
		part:SetAttribute("Speed", speed)
		part:SetAttribute("Center", center.Position)
		part:SetAttribute("Axis", center.RightVector)
	end
	spin(Part(parent, { Name = "Wheel", Shape = Enum.PartType.Cylinder, Size = Vector3.new(0.9, radius * 2, radius * 2), CFrame = center, Color = color, Material = Enum.Material.Metal }))
	Part(parent, { Name = "Hub", Shape = Enum.PartType.Cylinder, Size = Vector3.new(1.3, radius * 0.6, radius * 0.6), CFrame = center, Color = C.Ink })
	-- Four bars through the center make eight teeth.
	for index = 0, 3 do
		spin(Part(parent, {
			Name = "Teeth",
			Size = Vector3.new(0.8, radius * 2 + 1.3, radius * 0.34),
			CFrame = center * CFrame.Angles(math.rad(index * 45), 0, 0),
			Color = color,
			Material = Enum.Material.Metal,
			CanCollide = false,
		}))
	end
end

-- Scrap engine: pipes, turning gears and a glowing core, left and right of the dealer.
local function engine(parent, cf, mirrored)
	local m = model(parent, "ScrapEngine")
	local s = if mirrored then -1 else 1
	Part(m, { Name = "Base", Size = Vector3.new(8, 1.2, 8), CFrame = cf * CFrame.new(0, 0.6, 0), Color = C.Ink, CastShadow = true })
	Part(m, { Name = "Tank", Shape = Enum.PartType.Cylinder, Size = Vector3.new(9, 5, 5), CFrame = cf * CFrame.new(0, 5.6, 0) * UPRIGHT, Color = if mirrored then C.Teal else C.Orange, Material = Enum.Material.Metal, CastShadow = true })
	for _, y in { 2.4, 5.6, 8.8 } do
		Part(m, { Name = "Band", Shape = Enum.PartType.Cylinder, Size = Vector3.new(0.5, 5.4, 5.4), CFrame = cf * CFrame.new(0, y, 0) * UPRIGHT, Color = C.Ink, Material = Enum.Material.Metal })
	end
	Part(m, { Name = "Core", Shape = Enum.PartType.Ball, Size = Vector3.new(4.4, 4.4, 4.4), CFrame = cf * CFrame.new(0, 11, 0), Color = if mirrored then Color3.fromRGB(90, 230, 240) else Color3.fromRGB(255, 190, 70), Material = Enum.Material.Neon })
	Part(m, { Name = "Chimney", Shape = Enum.PartType.Cylinder, Size = Vector3.new(8, 1.4, 1.4), CFrame = cf * CFrame.new(-s * 2.9, 9, 1.6) * UPRIGHT, Color = C.Metal, Material = Enum.Material.Metal })
	Part(m, { Name = "Pipe", Shape = Enum.PartType.Cylinder, Size = Vector3.new(6, 1, 1), CFrame = cf * CFrame.new(s * 3.2, 1.8, -1.4), Color = C.Metal, Material = Enum.Material.Metal })
	local front = cf * yaw(90)
	gear(m, front * CFrame.new(3.2, 5.2, s * 1.4), 2.6, GOLD, 0.7 * s)
	gear(m, front * CFrame.new(3.2, 8.9, -s * 1.5), 1.7, C.Red, -1.07 * s)
end

local function wreathTree(parent, position, seed)
	local pine = Prefabs.Pine(parent, CFrame.new(position) * yaw(seed * 37), 0.8)
	for index = 0, 6 do
		local height = 4.2 + index * 1.35
		local radius = 4.4 - index * 0.48
		local angle = index * 140 + seed * 50
		Part(pine, {
			Name = "Bauble",
			Shape = Enum.PartType.Ball,
			Size = Vector3.new(0.9, 0.9, 0.9),
			CFrame = CFrame.new(position + polar(radius, angle) + Vector3.new(0, height, 0)),
			Color = BULBS[(index + seed) % #BULBS + 1],
			Material = Enum.Material.Neon,
			CanCollide = false,
			CanQuery = false,
		})
	end
	Part(pine, { Name = "Star", Shape = Enum.PartType.Ball, Size = Vector3.new(1.6, 1.6, 1.6), CFrame = CFrame.new(position + Vector3.new(0, 15.2, 0)), Color = GOLD, Material = Enum.Material.Neon, CanCollide = false })
end

-- A post with one arrow plank pointing along `direction`.
-- (Yaw by hand: Lune's CFrame.lookAt mirrors Z, which made arrows point the wrong way.)
local function arrow(parent, position, direction, text, color)
	local m = model(parent, "Pointer")
	local flat = CFrame.new(position)
	Part(m, { Name = "Post", Size = Vector3.new(0.7, 5.5, 0.7), CFrame = flat * CFrame.new(0, 2.75, 0), Color = C.Trunk, CastShadow = true })
	local board = Part(m, { Name = "Plank", Size = Vector3.new(0.5, 2.2, 8), CFrame = CFrame.new(position + Vector3.new(0, 6.6, 0)) * CFrame.Angles(0, math.atan2(-direction.X, -direction.Z), 0) * CFrame.new(0, 0, -2.2), Color = color })
	Part(m, { Name = "Tip", Size = Vector3.new(0.5, 1.55, 1.55), CFrame = board.CFrame * CFrame.new(0, 0, -4) * CFrame.Angles(math.rad(45), 0, 0), Color = color, CanCollide = false })
	Part(m, { Name = "Snow", Size = Vector3.new(0.9, 0.35, 8), CFrame = board.CFrame * CFrame.new(0, 1.25, 0), Color = C.Snow, CanCollide = false })
	for _, face in { Enum.NormalId.Left, Enum.NormalId.Right } do
		local gui = Instance.new("SurfaceGui")
		gui.Face = face
		gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
		gui.PixelsPerStud = 24
		gui.LightInfluence = 0
		gui.Parent = board
		local label = Instance.new("TextLabel")
		label.BackgroundTransparency = 1
		label.Size = roblox.UDim2.fromScale(0.9, 0.84)
		label.Position = roblox.UDim2.fromScale(0.05, 0.08)
		label.Text = text
		label.TextScaled = true
		label.Font = Enum.Font.FredokaOne
		label.TextColor3 = C.Snow
		label.Parent = gui
	end
end

function Plaza.Build(map)
	local folder = Instance.new("Folder")
	folder.Name = "PlazaDecor"
	folder.Parent = map

	floor(folder)
	gate(folder)
	engine(folder, CFrame.new(-28, FLOOR, 10), false)
	engine(folder, CFrame.new(28, FLOOR, 10), true)
	for index = 0, 7 do
		-- Between the spokes, just outside the rim; the gate takes the back.
		local degrees = 22.5 + index * 45
		local position = polar(47, degrees)
		if position.Z > -36 then
			wreathTree(folder, position, index)
		end
	end
	for _, degrees in { 33, 57, 123, 147, 213, 327 } do
		Prefabs.SnowPile(folder, CFrame.new(polar(44.5, degrees)), 0.42)
	end
	arrow(folder, Vector3.new(33, FLOOR, -9), Vector3.new(1, 0, 0), "BASES", C.Red)
	arrow(folder, Vector3.new(-33, FLOOR, -9), Vector3.new(-1, 0, 0), "BASES", C.Blue)
	arrow(folder, Vector3.new(31, FLOOR, -22), Vector3.new(0.5, 0, -1).Unit, "RACEWAY", C.Orange)
end

return Plaza
