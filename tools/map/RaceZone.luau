--[[
	RaceZone: the JUNKSHOT RACEWAY, an annex north (-Z) of the yard's container wall (built by
	build.luau). Walk through the gate in the wall (entrance arch), past the spectator stand to
	the track.

	Race logic finds its pieces by CollectionService tag (never by name or position):
	  RaceCheckpoint  Part, attribute Index (0 = start/finish line, then in driving order),
	                  -Z = driving direction, Size.X = track width
	  RaceGrid        Part, attribute Slot (1 = pole), -Z = driving direction
	  RaceLobby       Part: the pad where players join
	  RaceBoard       Part with SurfaceGui "Board" (records)
]]

local roblox = require("@lune/roblox")
local Prefabs = require("./Prefabs")

local Instance = roblox.Instance
local Vector3 = roblox.Vector3
local CFrame = roblox.CFrame
local Color3 = roblox.Color3
local UDim2 = roblox.UDim2
local Enum = roblox.Enum
local C = Prefabs.Colors
local Part = Prefabs.Part

local RaceZone = {}

-- The gate in the north wall (build.luau leaves this gap).
RaceZone.GateX = 73.2 -- center of one wall container
RaceZone.GateHalf = 12

local WALL_Z = -232 -- outer face of the yard's north wall
local HALF_X = 198
local FAR_Z = -488
local ROAD_WIDTH = 26
local BARRIER_OFFSET = 14
local SEGMENTS = 72
local START_X = 20 -- the start/finish line on the main straight
local STRAIGHT_Z = -312
local CHECKPOINTS = 8
local ASPHALT = Color3.fromRGB(74, 84, 112)
local WHITE, BLACK = Color3.fromRGB(250, 252, 255), Color3.fromRGB(30, 34, 48)

-- Driving order. The main straight runs east (+X) along STRAIGHT_Z.
local CONTROL = {
	{ -70, -312 }, { 0, -312 }, { 70, -312 }, { 130, -322 }, { 158, -360 }, { 140, -405 },
	{ 95, -425 }, { 50, -400 }, { 5, -375 }, { -45, -395 }, { -80, -435 }, { -130, -440 },
	{ -160, -400 }, { -145, -345 }, { -115, -318 },
}

local function yawTo(direction) -- CFrame whose -Z axis points along `direction`
	return CFrame.Angles(0, math.atan2(-direction.X, -direction.Z), 0)
end

local function child(parent, className, name)
	local instance = Instance.new(className)
	instance.Name = name
	instance.Parent = parent
	return instance
end

-- Text (and an optional smaller line under it) on one face of a part.
local function text(part, face, title, color, subtitle)
	local gui = child(part, "SurfaceGui", "Gui")
	gui.Face = face
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = 14 -- TextScaled stops at 100 px, so few pixels = big text
	gui.LightInfluence = 0
	local function line(name, value, y, height, textColor)
		local label = child(gui, "TextLabel", name)
		label.BackgroundTransparency = 1
		label.Size = UDim2.fromScale(0.92, height)
		label.Position = UDim2.fromScale(0.04, y)
		label.Text = value
		label.TextScaled = true
		label.Font = Enum.Font.FredokaOne
		label.TextColor3 = textColor
		label.TextStrokeColor3 = C.Ink
		label.TextStrokeTransparency = 0.3
		return label
	end
	if subtitle ~= nil then
		line("Title", title, 0.06, 0.58, color)
		line("Subtitle", subtitle, 0.66, 0.26, WHITE)
	else
		line("Title", title, 0.1, 0.8, color)
	end
	return gui
end

-- Row(s) of black/white squares along the X axis of `cf`.
local function checker(parent, cf, width, square, rows, depth, flat)
	local count = math.floor(width / square + 0.5)
	for row = 0, rows - 1 do
		for i = 0, count - 1 do
			local x = (i - (count - 1) / 2) * square
			local across = (row - (rows - 1) / 2) * square
			Part(parent, {
				Name = "Checker",
				Size = if flat then Vector3.new(square, depth, square) else Vector3.new(square, square, depth),
				CFrame = cf * (if flat then CFrame.new(x, 0, across) else CFrame.new(x, across, 0)),
				Color = if (i + row) % 2 == 0 then WHITE else BLACK,
				CanCollide = false,
				CanQuery = false,
				CastShadow = false,
			})
		end
	end
end

-- Closed Catmull-Rom curve sampled at equal distances: { position }, total length.
local function sampleTrack()
	local raw = {}
	local n = #CONTROL
	local function point(i)
		local c = CONTROL[(i - 1) % n + 1]
		return Vector3.new(c[1], 0, c[2])
	end
	for i = 1, n do
		local p0, p1, p2, p3 = point(i - 1), point(i), point(i + 1), point(i + 2)
		for step = 0, 19 do
			local t = step / 20
			table.insert(raw, (p1 * 2 + (p2 - p0) * t + (p0 * 2 - p1 * 5 + p2 * 4 - p3) * (t * t)
				+ (p1 * 3 - p0 - p2 * 3 + p3) * (t * t * t)) * 0.5)
		end
	end
	table.insert(raw, raw[1])
	local total = 0
	for i = 2, #raw do
		total += (raw[i] - raw[i - 1]).Magnitude
	end
	local function at(distance)
		local left = distance % total
		for i = 2, #raw do
			local length = (raw[i] - raw[i - 1]).Magnitude
			if left <= length then
				return raw[i - 1]:Lerp(raw[i], left / math.max(length, 1e-6))
			end
			left -= length
		end
		return raw[1]
	end
	return at, total
end

-- A straight piece between two ground points: -Z along the piece.
local function span(parent, a, b, props)
	local delta = b - a
	props.CFrame = CFrame.new((a + b) / 2 + Vector3.new(0, props.Y, 0)) * yawTo(delta)
	props.Size = Vector3.new(props.Width, props.Height, delta.Magnitude + (props.Overlap or 0))
	return Part(parent, props)
end

local function buildTrack(zone)
	local track = child(zone, "Folder", "Track")
	local at, total = sampleTrack()

	local nodes = {}
	for i = 0, SEGMENTS - 1 do
		local d = i / SEGMENTS * total
		local position = at(d)
		local tangent = (at(d + 1) - at(d - 1)).Unit
		nodes[i] = { Position = position, Tangent = tangent, Side = Vector3.new(-tangent.Z, 0, tangent.X) }
	end
	local road = child(track, "Folder", "Road")
	local barriers = child(track, "Folder", "Barriers")
	for i = 0, SEGMENTS - 1 do
		local a, b = nodes[i], nodes[(i + 1) % SEGMENTS]
		local roadPart = span(road, a.Position, b.Position, {
			-- One even color without texture and all at the same height: the overlaps cannot be
			-- seen. Not collidable: vehicles roll on the flat RaceGround under it, without steps.
			Name = "Road", Width = ROAD_WIDTH, Height = 0.2, Y = -0.04,
			Overlap = 6, Color = ASPHALT, Material = Enum.Material.SmoothPlastic, CanCollide = false, CastShadow = false,
		})
		roadPart:AddTag("NoPlace")
		if i % 2 == 0 then
			local middle = (b.Position - a.Position) * 0.25
			span(road, a.Position + middle, b.Position - middle, {
				Name = "Dash", Width = 0.6, Height = 0.06, Y = 0.06, Color = WHITE,
				CanCollide = false, CanQuery = false, CastShadow = false,
			})
		end
		for _, side in { -1, 1 } do
			span(barriers, a.Position + a.Side * (BARRIER_OFFSET * side), b.Position + b.Side * (BARRIER_OFFSET * side), {
				Name = "Barrier", Width = if i % 2 == 0 then 1.6 else 1.3, Height = if i % 2 == 0 then 2.7 else 2.4,
				Y = if i % 2 == 0 then 1.35 else 1.2, Overlap = if i % 2 == 0 then 0.8 else 0,
				Color = if i % 2 == 0 then C.Red else WHITE, CastShadow = false,
			})
		end
	end

	-- Distance of the start line along the curve.
	local startDistance, best = 0, math.huge
	for d = 0, total, 0.25 do
		local gap = (at(d) - Vector3.new(START_X, 0, STRAIGHT_Z)).Magnitude
		if gap < best then
			startDistance, best = d, gap
		end
	end
	local function frameAt(distance)
		local tangent = (at(distance + 0.5) - at(distance - 0.5)).Unit
		return CFrame.new(at(distance)) * yawTo(tangent)
	end

	local checkpoints = child(track, "Folder", "Checkpoints")
	for index = 0, CHECKPOINTS - 1 do
		local part = Part(checkpoints, {
			Name = `Checkpoint{index}`, Size = Vector3.new(ROAD_WIDTH + 2, 14, 2),
			CFrame = frameAt(startDistance + index / CHECKPOINTS * total) * CFrame.new(0, 7, 0),
			Transparency = 1, CanCollide = false, CanQuery = false, CastShadow = false,
		})
		part:SetAttribute("Index", index)
		part:AddTag("RaceCheckpoint")
	end

	local grid = child(track, "Folder", "Grid")
	for slot = 1, 8 do
		local row = math.floor((slot - 1) / 2)
		local x = if slot % 2 == 1 then -5.5 else 5.5
		local cf = frameAt(startDistance - 10 - row * 14 - (if slot % 2 == 0 then 4 else 0))
		local pad = Part(grid, {
			Name = `Slot{slot}`, Size = Vector3.new(6, 0.1, 9), CFrame = cf * CFrame.new(x, 0.05, 0),
			Color = if slot == 1 then C.Yellow else C.Ice, CanCollide = false, CanQuery = false, CastShadow = false,
		})
		pad:SetAttribute("Slot", slot)
		pad:AddTag("RaceGrid")
	end

	-- Start / finish: checkered line and the arch above it.
	local finish = child(track, "Model", "FinishArch")
	local line = frameAt(startDistance)
	checker(finish, line * CFrame.new(0, 0.07, 0), ROAD_WIDTH, 2, 2, 0.1, true)
	for _, side in { -1, 1 } do
		local x = side * 17
		Part(finish, { Name = "Pillar", Size = Vector3.new(2.6, 19, 2.6), CFrame = line * CFrame.new(x, 9.5, 0), Color = C.Ink })
		Part(finish, { Name = "Foot", Size = Vector3.new(4.4, 1.6, 4.4), CFrame = line * CFrame.new(x, 0.8, 0), Color = C.Red })
		Part(finish, { Name = "Cap", Size = Vector3.new(3.4, 0.8, 3.4), CFrame = line * CFrame.new(x, 22.9, 0), Color = C.Snow, CastShadow = false })
		Part(finish, { Name = "Lamp", Shape = Enum.PartType.Ball, Size = Vector3.new(2, 2, 2), CFrame = line * CFrame.new(x, 24, 0), Color = C.Warm, Material = Enum.Material.Neon, CastShadow = false })
	end
	local banner = Part(finish, { Name = "Banner", Size = Vector3.new(37, 6, 1.6), CFrame = line * CFrame.new(0, 17.5, 0), Color = C.Red })
	text(banner, Enum.NormalId.Back, "START", WHITE)
	text(banner, Enum.NormalId.Front, "START", WHITE)
	checker(finish, line * CFrame.new(0, 21.5, 0), 36, 2, 1, 1.4, false)
	checker(finish, line * CFrame.new(0, 13.5, 0), 36, 2, 1, 1.4, false)
	Part(finish, { Name = "Snow", Size = Vector3.new(37.4, 0.7, 2.4), CFrame = line * CFrame.new(0, 22.85, 0), Color = C.Snow, CastShadow = false })
	local lights = child(finish, "Folder", "StartLights")
	for i = 1, 3 do
		local lamp = Part(lights, {
			Name = `Light{i}`, Shape = Enum.PartType.Ball, Size = Vector3.new(2.2, 2.2, 2.2),
			CFrame = line * CFrame.new((i - 2) * 3.4, 11.2, 0.4), Color = Color3.fromRGB(90, 30, 34), CastShadow = false,
		})
		lamp:SetAttribute("Order", i)
		lamp:AddTag("RaceStartLight")
	end
end

local function buildEntrance(zone)
	local gate = child(zone, "Model", "Entrance")
	local cf = CFrame.new(RaceZone.GateX, 0, -219) -- yard side of the wall; +Z = towards the yard
	for _, side in { -1, 1 } do
		local x = side * 22
		Part(gate, { Name = "Foot", Size = Vector3.new(5, 2, 5), CFrame = cf * CFrame.new(x, 1, 0), Color = C.Red })
		Part(gate, { Name = "Pillar", Size = Vector3.new(3, 22, 3), CFrame = cf * CFrame.new(x, 11, 0), Color = C.Ink })
		for stripe = 0, 3 do
			Part(gate, { Name = "Stripe", Size = Vector3.new(3.1, 1.4, 3.1), CFrame = cf * CFrame.new(x, 4 + stripe * 3.2, 0), Color = if stripe % 2 == 0 then C.Yellow else WHITE, CastShadow = false })
		end
		Part(gate, { Name = "Lamp", Shape = Enum.PartType.Ball, Size = Vector3.new(2.6, 2.6, 2.6), CFrame = cf * CFrame.new(x, 25.4, 0), Color = C.Warm, Material = Enum.Material.Neon, CastShadow = false })
		Prefabs.TireStack(gate, cf * CFrame.new(side * 27, 0, 1), 4)
	end
	local board = Part(gate, { Name = "Board", Size = Vector3.new(40, 8, 1.6), CFrame = cf * CFrame.new(0, 19, 0), Color = C.Blue })
	text(board, Enum.NormalId.Back, "JUNKSHOT RACEWAY", C.Yellow, "Grab a kart - race for Klunks!") -- +Z, seen from the yard
	text(board, Enum.NormalId.Front, "BACK TO THE YARD", WHITE)
	checker(gate, cf * CFrame.new(0, 24, 0), 40, 2, 1, 1.4, false)
	checker(gate, cf * CFrame.new(0, 14, 0), 40, 2, 1, 1.4, false)
	Part(gate, { Name = "Snow", Size = Vector3.new(40.6, 0.8, 2.6), CFrame = cf * CFrame.new(0, 25.4, 0), Color = C.Snow, CastShadow = false })
	-- A row of bulbs under the board.
	for i = 0, 10 do
		Part(gate, {
			Name = "Bulb", Shape = Enum.PartType.Ball, Size = Vector3.new(0.9, 0.9, 0.9), CFrame = cf * CFrame.new((i - 5) * 3.4, 12.4, 0),
			Color = Prefabs.Accents[i % #Prefabs.Accents + 1], Material = Enum.Material.Neon, CanCollide = false, CastShadow = false,
		})
	end
	-- Path: ring road -> gate -> race plaza.
	local paths = child(zone, "Folder", "Paths")
	span(paths, Vector3.new(57, 0, -139), Vector3.new(RaceZone.GateX, 0, -216), { Name = "Path", Width = 12, Height = 0.2, Y = -0.04, Color = C.Path, CastShadow = false })
	span(paths, Vector3.new(RaceZone.GateX, 0, -214), Vector3.new(RaceZone.GateX, 0, -256), { Name = "Path", Width = 18, Height = 0.2, Y = -0.05, Color = C.Path, CastShadow = false })
	Part(paths, { Name = "RacePlaza", Size = Vector3.new(84, 0.2, 38), CFrame = CFrame.new(RaceZone.GateX, -0.03, -274), Color = C.PlazaTop, CastShadow = false })
end

local function buildLobby(zone)
	local lobby = child(zone, "Folder", "Lobby")
	local pad = Part(lobby, { Name = "JoinPad", Size = Vector3.new(16, 0.5, 16), CFrame = CFrame.new(RaceZone.GateX, 0.4, -278), Color = C.Yellow, CastShadow = false })
	pad:AddTag("RaceLobby")
	Part(lobby, { Name = "JoinPadTop", Size = Vector3.new(13, 0.1, 13), CFrame = CFrame.new(RaceZone.GateX, 0.7, -278), Color = C.Ink, CastShadow = false })
	checker(lobby, CFrame.new(RaceZone.GateX, 0.78, -278), 8, 2, 4, 0.06, true)

	-- Spectator stand: 5 snow-dusted steps facing the main straight.
	local stand = child(zone, "Model", "SpectatorStand")
	for step = 0, 4 do
		local height = 1.6 + step * 1.6
		Part(stand, {
			Name = "Step", Size = Vector3.new(70, height, 4), CFrame = CFrame.new(-30, height / 2, -292 + step * 4),
			Color = Prefabs.Accents[step % #Prefabs.Accents + 1],
		})
	end
	for _, x in { -66, 6 } do
		Part(stand, { Name = "RoofPost", Size = Vector3.new(1.4, 18, 1.4), CFrame = CFrame.new(x, 9, -274), Color = C.Ink })
		Part(stand, { Name = "RoofPost", Size = Vector3.new(1.4, 18, 1.4), CFrame = CFrame.new(x, 9, -294), Color = C.Ink })
	end
	Part(stand, { Name = "Roof", Size = Vector3.new(76, 0.9, 25), CFrame = CFrame.new(-30, 18.4, -284), Color = C.Blue })
	Part(stand, { Name = "RoofSnow", Size = Vector3.new(76.6, 0.7, 25.6), CFrame = CFrame.new(-30, 19.2, -284), Color = C.Snow, CastShadow = false })

	-- Record board beside the plaza, facing the gate (+Z).
	local board = child(zone, "Model", "RecordBoard")
	local cf = CFrame.new(RaceZone.GateX + 33, 0, -288)
	for _, x in { -7, 7 } do
		Part(board, { Name = "Post", Size = Vector3.new(1, 15, 1), CFrame = cf * CFrame.new(x, 7.5, -0.9), Color = C.Ink })
	end
	Part(board, { Name = "Frame", Size = Vector3.new(19, 13, 0.8), CFrame = cf * CFrame.new(0, 9, -0.1), Color = C.Yellow })
	local face = Part(board, { Name = "Face", Size = Vector3.new(17.6, 11.6, 0.8), CFrame = cf * CFrame.new(0, 9, 0.2), Color = C.Ink })
	face:AddTag("RaceBoard")
	text(face, Enum.NormalId.Back, "BEST TIMES", C.Yellow, "No records yet").Name = "Board"
	Part(board, { Name = "Snow", Size = Vector3.new(19.6, 0.7, 2), CFrame = cf * CFrame.new(0, 15.8, 0), Color = C.Snow, CastShadow = false })
end

local function buildSurroundings(zone)
	local ground = Part(zone, {
		Name = "RaceGround", Size = Vector3.new(512, 20, 260), CFrame = CFrame.new(0, -10, -386), Color = Color3.new(0.96471, 0.98039, 1),
	})
	ground.Locked = true

	local edge = child(zone, "Folder", "Edge")
	local colors = { C.Teal, C.Orange, C.Purple, C.Blue, C.Red, C.Green, C.Yellow }
	local index = 0
	local function wall(x, z, degrees)
		index += 1
		Prefabs.Container(edge, CFrame.new(x, 0, z) * CFrame.Angles(0, math.rad(degrees), 0), colors[index % #colors + 1], "WallContainer")
	end
	for i = 0, 16 do
		wall(-195.2 + i * 24.4, FAR_Z + 2, 0)
	end
	for _, side in { -1, 1 } do
		for i = 0, 9 do
			wall(side * (HALF_X + 5), -245 - i * 24.4, 90)
		end
		Part(edge, { Name = "Limit", Size = Vector3.new(2, 120, 262), CFrame = CFrame.new(side * HALF_X, 60, -360), Transparency = 1, CastShadow = false })
	end
	Part(edge, { Name = "Limit", Size = Vector3.new(HALF_X * 2 + 4, 120, 2), CFrame = CFrame.new(0, 60, FAR_Z + 7), Transparency = 1, CastShadow = false })

	local decor = child(zone, "Folder", "Decor")
	local turn = 0
	for _, spot in { { 100, -370 }, { 60, -350 }, { -90, -365 }, { -120, -385 }, { -20, -440 }, { 175, -300 }, { 178, -440 }, { -178, -300 }, { -175, -460 }, { 30, -460 }, { -60, -345 } } do
		turn += 1
		Prefabs.Pine(decor, CFrame.new(spot[1], 0, spot[2]) * CFrame.Angles(0, turn, 0), 0.8 + turn % 3 * 0.15)
	end
	Prefabs.SnowPile(decor, CFrame.new(20, 0, -345), 0.7)
	Prefabs.SnowPile(decor, CFrame.new(-95, 0, -400), 0.6)
	Prefabs.SnowPile(decor, CFrame.new(110, 0, -455), 0.7)
	Prefabs.JunkHeap(decor, CFrame.new(95, 0, -385), 0.8, 17)
	Prefabs.TireStack(decor, CFrame.new(125, 0, -355), 4)
	Prefabs.TireStack(decor, CFrame.new(-115, 0, -360), 3)
	for _, spot in { { 40, -262 }, { 108, -262 }, { -75, -286 }, { 150, -286 }, { -150, -290 }, { 0, -345 }, { 100, -445 }, { -100, -462 } } do
		Prefabs.Lamp(decor, CFrame.new(spot[1], 0, spot[2]), true)
	end
end

function RaceZone.Build(map)
	local zone = child(map, "Folder", "RaceZone")
	buildSurroundings(zone)
	buildEntrance(zone)
	buildLobby(zone)
	buildTrack(zone)
end

return RaceZone
