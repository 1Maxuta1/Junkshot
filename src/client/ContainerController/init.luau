--!strict
--[[
	ContainerController: the small details of the shipping containers (tag "ScrapContainer",
	built by tools/map/Prefabs.Container): corrugated sides, corner posts and castings, door bars,
	company plates with numbers, warning stripes, rust, graffiti, icicles and snow drifts.

	The map keeps only a few parts per container (there are about 130); the details are made
	here for the containers near the camera and removed again, so phones never hold them all.
	Containers of the outer wall get them only on the side the camera is on. Lite graphics: none.
]]

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")

local ContainerController = {}

local NEAR, FAR = 105, 125 -- studs: details appear / disappear
local CHECK_SECONDS = 0.4
local PER_FRAME = 1 -- containers detailed per frame
local localPlayer = Players.LocalPlayer
local rgb = Color3.fromRGB
local V = Vector3.new
local M = Enum.Material
local at = CFrame.new
local UPRIGHT = CFrame.Angles(0, 0, math.rad(90))
local INK, STEEL, SNOW = rgb(40, 46, 64), rgb(170, 180, 196), rgb(248, 251, 255)

local BRANDS = {
	{ Name = "SCRAPCO", Sub = "HEAVY HAULING", Color = rgb(255, 204, 48) },
	{ Name = "FROSTLINE", Sub = "COLD CARGO", Color = rgb(120, 220, 255) },
	{ Name = "NORTHGEAR", Sub = "MACHINE PARTS", Color = rgb(255, 148, 36) },
	{ Name = "BOLT & SONS", Sub = "SINCE 1987", Color = rgb(240, 244, 250) },
	{ Name = "KLUNKS EXPRESS", Sub = "WE SHIP JUNK", Color = rgb(130, 240, 150) },
	{ Name = "POLAR FREIGHT", Sub = "HANDLE WITH MITTENS", Color = rgb(250, 130, 130) },
}
local GRAFFITI = { "SCRAP LIFE", "JUNK!", "K K K A - C H I N G", "BOING", "FREE TIRES ->" }

type Detail = { Model: Model, Side: number }
local details: { [Instance]: Detail } = {}
local queue: { { Container: Model, Side: number } } = {}

local function hash(position: Vector3): number
	local mixed = math.floor(position.X + 0.5) * 73856 + math.floor(position.Z + 0.5) * 19349 + math.floor(position.Y + 0.5) * 8349
	return Random.new(mixed):NextInteger(0, 999999) -- neighbours must not look alike
end

local function label(parent: Instance, text: string, position: UDim2, size: UDim2, color: Color3, align: Enum.TextXAlignment?): TextLabel
	local l = Instance.new("TextLabel")
	l.BackgroundTransparency = 1
	l.Position = position
	l.Size = size
	l.Font = Enum.Font.FredokaOne
	l.Text = text
	l.TextColor3 = color
	l.TextScaled = true
	l.TextXAlignment = align or Enum.TextXAlignment.Center
	l.Parent = parent
	return l
end

local function build(container: Model, body: BasePart, side: number): Model
	local seed = hash(body.Position)
	local random = Random.new(seed)
	local color = body.Color
	local dark, bright = color:Lerp(INK, 0.22), color:Lerp(Color3.new(1, 1, 1), 0.12)
	local model = Instance.new("Model")
	model.Name = "ContainerDetail"
	local function part(name: string, size: Vector3, offset: CFrame, c: Color3, material: Enum.Material?, shape: Enum.PartType?): Part
		local p = Instance.new("Part")
		p.Name = name
		p.Shape = shape or Enum.PartType.Block
		p.Size = size
		p.CFrame = body.CFrame * offset
		p.Color = c
		p.Material = material or M.SmoothPlastic
		p.Anchored = true
		p.CanCollide = false
		p.CanQuery = false
		p.CanTouch = false
		p.CastShadow = false
		p.TopSurface = Enum.SurfaceType.Smooth
		p.BottomSurface = Enum.SurfaceType.Smooth
		p.Parent = model
		return p
	end
	local brand = BRANDS[seed % #BRANDS + 1]
	local code = string.format("JNK %04d %d", seed % 10000, seed % 9 + 1)

	-- side 0: both sides and the ends; +1 / -1: one long side only (outer wall)
	local sides = if side == 0 then { -1, 1 } else { side }
	for _, s in sides do
		local turn = if s > 0 then CFrame.Angles(0, math.pi, 0) else CFrame.new() -- front (-Z) looks outwards
		for index = 0, 14 do -- corrugated steel
			part("Rib", V(0.75, 7.4, 0.22), at(-10.85 + index * 1.55, 0, s * 4.58), if index % 2 == 0 then bright else color)
		end
		for _, x in { -11.75, 11.75 } do
			part("Post", V(0.75, 8.4, 0.5), at(x, 0, s * 4.5), dark, M.Metal)
			for _, y in { -4.2, 4.2 } do
				part("Casting", V(0.95, 0.6, 0.7), at(x, y, s * 4.5), INK, M.Metal)
				part("CastingHole", V(0.4, 0.26, 0.1), at(x, y, s * 4.86), rgb(16, 18, 26))
			end
		end
		-- Company plate
		local plate = part("Plate", V(9, 3, 0.16), at(-4.6 + seed % 3, 0.9, s * 4.78) * turn, dark:Lerp(INK, 0.4))
		local gui = Instance.new("SurfaceGui")
		gui.Face = Enum.NormalId.Front
		gui.CanvasSize = Vector2.new(450, 150)
		gui.LightInfluence = 0.8
		gui.MaxDistance = 120
		local stripe = Instance.new("Frame")
		stripe.BorderSizePixel = 0
		stripe.BackgroundColor3 = brand.Color
		stripe.Size = UDim2.new(0, 14, 1, 0)
		stripe.Parent = gui
		label(gui, brand.Name, UDim2.fromOffset(28, 8), UDim2.fromOffset(410, 84), brand.Color)
		label(gui, brand.Sub, UDim2.fromOffset(28, 100), UDim2.fromOffset(410, 38), rgb(235, 240, 250))
		gui.Parent = plate
		-- Number and weight
		local tag = part("Number", V(4.6, 1.5, 0.14), at(8, 2.4, s * 4.76) * turn, color:Lerp(INK, 0.12))
		local tagGui = Instance.new("SurfaceGui")
		tagGui.Face = Enum.NormalId.Front
		tagGui.CanvasSize = Vector2.new(230, 75)
		tagGui.LightInfluence = 0.8
		tagGui.MaxDistance = 90
		label(tagGui, code, UDim2.fromOffset(4, 2), UDim2.fromOffset(222, 42), rgb(255, 255, 255))
		label(tagGui, `MAX {20 + seed % 11}.{seed % 10} T`, UDim2.fromOffset(4, 46), UDim2.fromOffset(222, 26), rgb(225, 232, 245))
		tagGui.Parent = tag
		-- Extras: every container has a few of them
		if seed % 2 == 0 then
			for index = 0, 5 do -- warning stripes at the bottom
				part("Hazard", V(0.9, 0.7, 0.12), at(4.2 + index * 0.92, -3.2, s * 4.76), if index % 2 == 0 then rgb(255, 204, 48) else INK)
			end
		end
		if seed % 3 == 0 then
			for _ = 1, 6 do
				-- streaks running down the ribs
				local length = random:NextNumber(0.8, 2.6)
				local streak = part("Rust", V(random:NextNumber(0.25, 0.6), length, 0.06), at(random:NextInteger(-6, 6) * 1.55 + 0.1, -3.75 + length / 2, s * 4.68), rgb(150, 82, 44), M.CorrodedMetal)
				streak.Transparency = 0.25
			end
		end
		if seed % 4 == 1 then
			local paint = part("Graffiti", V(7, 2, 0.06), at(4.4, -1.7, s * 4.74) * turn * CFrame.Angles(0, 0, math.rad(6)), color)
			paint.Transparency = 1
			local paintGui = Instance.new("SurfaceGui")
			paintGui.Face = Enum.NormalId.Front
			paintGui.CanvasSize = Vector2.new(350, 100)
			paintGui.MaxDistance = 90
			local l = label(paintGui, GRAFFITI[seed % #GRAFFITI + 1], UDim2.new(), UDim2.fromScale(1, 1), Color3.fromHSV(seed % 10 / 10, 0.5, 1))
			l.Font = Enum.Font.PermanentMarker
			paintGui.Parent = paint
		end
		if seed % 5 < 2 then
			for index = 0, 1 do -- air vents
				for slat = 0, 2 do
					part("Vent", V(1.5, 0.14, 0.14), at(8 + index * 1.8 - 0.9, 0.4 + slat * 0.3, s * 4.74), INK, M.Metal)
				end
			end
		end
		for _ = 1, 5 + seed % 4 do -- icicles under the snow
			local length = random:NextNumber(0.5, 1.5)
			local x = random:NextNumber(-11, 11)
			part("Icicle", V(0.22, length, 0.22), at(x, 4.4 - length / 2, s * 4.86), rgb(190, 228, 255), M.Ice)
			part("IcicleTip", V(0.1, 0.35, 0.1), at(x, 4.4 - length - 0.15, s * 4.86), rgb(215, 240, 255), M.Ice)
		end
		for _ = 1, 2 do
			local drift = part("Drift", V(random:NextNumber(5, 10), 1.8, 2.6), at(random:NextNumber(-8, 8), -4.4, s * 4.9), SNOW)
			local round = Instance.new("SpecialMesh")
			round.MeshType = Enum.MeshType.Sphere
			round.Parent = drift
		end
		for _ = 1, 3 do -- a softer snow edge
			part("SnowLump", V(random:NextNumber(2.5, 5), 0.75, 0.9), at(random:NextNumber(-9, 9), 4.65, s * 4.6), SNOW, M.Snow)
		end
	end
	if side == 0 then
		-- Door end (+X): seam, lock bars with handles, hinges
		part("Seam", V(0.12, 8, 0.12), at(12.32, 0, 0), INK)
		for _, z in { -3, -1.1, 1.1, 3 } do
			part("Bar", V(7.8, 0.24, 0.24), at(12.5, 0, z) * UPRIGHT, STEEL, M.Metal, Enum.PartType.Cylinder)
			for _, y in { -3.4, 3.4 } do
				part("BarClamp", V(0.3, 0.4, 0.5), at(12.45, y, z), INK, M.Metal)
			end
		end
		for _, z in { -0.75, 0.75 } do
			part("Handle", V(0.2, 0.22, 1.3), at(12.7, -0.6, z * 1.7), rgb(255, 204, 48), M.Metal)
			part("Lock", V(0.35, 0.6, 0.5), at(12.6, -1.1, z * 0.5), STEEL, M.Metal)
		end
		for _, z in { -4.15, 4.15 } do
			for _, y in { -3, 0, 3 } do
				part("Hinge", V(0.4, 0.8, 0.3), at(12.4, y, z), INK, M.Metal)
			end
		end
		for index = 0, 4 do -- far end ribs
			part("Rib", V(0.22, 7.4, 0.8), at(-12.08, 0, -3.4 + index * 1.7), bright)
		end
	end
	model.Parent = container
	return model
end

local function bodyOf(container: Instance): BasePart?
	local body = container:FindFirstChild("Body")
	return if body ~= nil and body:IsA("BasePart") then body else nil
end

local function check()
	local camera = Workspace.CurrentCamera
	if camera == nil then
		return
	end
	local eye = camera.CFrame.Position
	local lite = localPlayer:GetAttribute("LiteGraphics") == true
	table.clear(queue)
	for _, container in CollectionService:GetTagged("ScrapContainer") do
		local body = bodyOf(container)
		local detail = details[container]
		if body == nil or not container:IsA("Model") or lite then
			if detail ~= nil then
				detail.Model:Destroy()
				details[container] = nil
			end
			continue
		end
		local distance = (body.Position - eye).Magnitude
		local side = if container.Name == "WallContainer" then (if body.CFrame:PointToObjectSpace(eye).Z > 0 then 1 else -1) else 0
		if detail ~= nil and (distance > FAR or (detail.Side ~= side and distance > 20)) then
			detail.Model:Destroy()
			details[container] = nil
			detail = nil
		end
		if detail == nil and distance < NEAR then
			table.insert(queue, { Container = container, Side = side })
		end
	end
	table.sort(queue, function(a, b)
		return (a.Container:GetPivot().Position - eye).Magnitude < (b.Container:GetPivot().Position - eye).Magnitude
	end)
	for container, detail in details do -- streamed out
		if not container:IsDescendantOf(Workspace) then
			detail.Model:Destroy()
			details[container] = nil
		end
	end
end

function ContainerController.Start()
	task.spawn(function()
		while true do
			check()
			local started = os.clock()
			for index, entry in queue do
				local body = bodyOf(entry.Container)
				if body ~= nil and details[entry.Container] == nil and entry.Container:IsDescendantOf(Workspace) then
					details[entry.Container] = { Model = build(entry.Container, body, entry.Side), Side = entry.Side }
				end
				if index % PER_FRAME == 0 then
					task.wait()
				end
				if os.clock() - started > 1 then
					break -- look again who is near
				end
			end
			task.wait(CHECK_SECONDS)
		end
	end)
end

return ContainerController
