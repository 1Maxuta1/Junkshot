--[[
	Locations: the two detailed areas of the yard (run by Lune, see build.luau).

	  TireMountain(parent, at)  the "Tire Mountain" zone: a real mountain of tires behind the
	                            junk field, smaller piles, tire walls, a wreck on blocks, a rim rack
	  CraneYard(parent, cf)     the corner with the tower crane: lattice crane with a load on the
	                            hook, site cabin, containers, pipes, beams, barriers, floodlights.
	                            Junk falls here too (its own JunkSpawn area).

	Budget: big silhouettes from few parts. Small details cast no shadow and take no clicks or
	touches (CanQuery / CanTouch off), so they cost almost nothing per frame; only the large
	shapes cast shadows and collide.
]]

local roblox = require("@lune/roblox")
local Prefabs = require("./Prefabs")

local Vector3 = roblox.Vector3
local CFrame = roblox.CFrame
local Color3 = roblox.Color3
local Enum = roblox.Enum
local Instance = roblox.Instance

local C = Prefabs.Colors
local Locations = {}

local UPRIGHT = CFrame.Angles(0, 0, math.rad(90)) -- cylinders run along X; this lays a tire flat
local RUBBER = { Color3.fromRGB(42, 44, 52), Color3.fromRGB(54, 56, 64), Color3.fromRGB(36, 38, 44), Color3.fromRGB(62, 62, 68) }
local HOLE = Color3.fromRGB(20, 21, 26)
local CONCRETE = Color3.fromRGB(176, 182, 192)
local STEEL = Color3.fromRGB(120, 132, 156)

local function rgb(r, g, b)
	return Color3.fromRGB(r, g, b)
end

local function yaw(degrees)
	return CFrame.Angles(0, math.rad(degrees), 0)
end

local function model(parent, name)
	local m = Instance.new("Model")
	m.Name = name
	m.Parent = parent
	return m
end

-- Detail part: no shadow, no collision, no queries.
local function detail(parent, props)
	props.CastShadow = if props.CastShadow == nil then false else props.CastShadow
	if props.CanCollide == nil then
		props.CanCollide = false
	end
	props.CanQuery = false
	return Prefabs.Part(parent, props)
end

-- Big shape: casts a shadow and collides.
local function solid(parent, props)
	props.CastShadow = if props.CastShadow == nil then true else props.CastShadow
	return Prefabs.Part(parent, props)
end

-- A straight bar from point a to point b.
local function bar(parent, a, b, thickness, color, shadow)
	return (if shadow then solid else detail)(parent, {
		Name = "Bar",
		Size = Vector3.new(thickness, thickness, (b - a).Magnitude),
		CFrame = CFrame.lookAt((a + b) / 2, b),
		Color = color,
		Material = Enum.Material.Metal,
	})
end

local function newRandom(seed)
	local state = (seed * 2654435761) % 4294967296
	return function(min, max)
		state = (1103515245 * state + 12345) % 2147483648
		return min + (max - min) * (state / 2147483648)
	end
end

-- One tire at `cf` (its center, lying flat when cf is level). `hole` adds the dark middle.
local function tire(parent, cf, diameter, color, hole)
	local width = diameter * 0.34
	detail(parent, {
		Name = "Tire",
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(width, diameter, diameter),
		CFrame = cf * UPRIGHT,
		Color = color,
	})
	if hole then
		detail(parent, {
			Name = "TireHole",
			Shape = Enum.PartType.Cylinder,
			Size = Vector3.new(width + 0.04, diameter * 0.5, diameter * 0.5),
			CFrame = cf * UPRIGHT,
			Color = HOLE,
		})
	end
end

-- A heap of tires around `base` (on the ground): rings of tires that get smaller towards the
-- top, every tire a little tilted, over a dark rubber core that fills the inside and is what
-- you actually bump into. A few tires on top carry snow.
local function tirePile(parent, base, radius, height, seed)
	local m = model(parent, "TirePile")
	local random = newRandom(seed)
	solid(m, {
		Name = "Core",
		Shape = Enum.PartType.Ball,
		Size = Vector3.new(radius * 1.85, height * 1.5, radius * 1.85),
		CFrame = base * CFrame.new(0, height * 0.1, 0),
		Color = rgb(30, 31, 37),
	})
	local layers = math.max(2, math.floor(height / 1.55))
	local diameter = 5.2
	for layer = 0, layers - 1 do
		local t = layer / layers
		local ringRadius = radius * (1 - t) ^ 0.85
		local y = 0.9 + layer * 1.5
		local count = math.max(1, math.floor(2 * math.pi * ringRadius / (diameter * 0.98)))
		local offset = random(0, math.pi * 2)
		for index = 0, count - 1 do
			local angle = offset + index / count * math.pi * 2 + random(-0.08, 0.08)
			local r = if count == 1 then 0 else ringRadius * random(0.86, 1)
			local outward = CFrame.Angles(0, -angle, 0)
			-- Lean outwards (the heap's slope) plus a little random wobble.
			local lean = CFrame.Angles(random(-0.22, 0.22), 0, -0.28 + random(-0.25, 0.2))
			local cf = base * CFrame.new(math.cos(angle) * r, y, math.sin(angle) * r) * outward * lean
			local size = diameter * random(0.86, 1.1)
			tire(m, cf, size, RUBBER[1 + (layer + index) % #RUBBER], (index + layer) % 2 == 0)
			if layer >= layers - 2 and index % 2 == 0 then
				detail(m, {
					Name = "Snow",
					Shape = Enum.PartType.Cylinder,
					Size = Vector3.new(0.3, size * 0.9, size * 0.9),
					CFrame = cf * CFrame.new(0, size * 0.18, 0) * UPRIGHT,
					Color = C.Snow,
					Material = Enum.Material.Snow,
				})
			end
		end
	end
	-- The very top: one tire, snowy.
	local top = base * CFrame.new(0, 0.9 + layers * 1.5, 0) * CFrame.Angles(0.15, 0.4, 0.1)
	tire(m, top, diameter, RUBBER[2], true)
	detail(m, {
		Name = "SnowCap",
		Shape = Enum.PartType.Ball,
		Size = Vector3.new(4.2, 1.2, 4.2),
		CFrame = top * CFrame.new(0, 0.9, 0),
		Color = C.Snow,
		Material = Enum.Material.Snow,
	})
	return m
end

-- A column of tires standing in a stack (wall pieces).
local function tireColumn(parent, base, count, seed)
	local random = newRandom(seed)
	for index = 1, count do
		local cf = base * CFrame.new(random(-0.25, 0.25), 0.9 + (index - 1) * 1.72, random(-0.25, 0.25)) * yaw(random(0, 90))
		tire(parent, cf, 5, RUBBER[1 + index % #RUBBER], index == count)
	end
end

-- Oil puddle on the ground (two flat shapes, glossy).
local function puddle(parent, cf, size)
	for index, piece in { { 0, 0, 1 }, { size * 0.45, size * 0.2, 0.6 } } do
		detail(parent, {
			Name = "Oil",
			Shape = Enum.PartType.Cylinder,
			Size = Vector3.new(0.04, size * piece[3], size * piece[3] * 0.8),
			CFrame = cf * CFrame.new(piece[1], 0.14 + index * 0.05, piece[2]) * UPRIGHT,
			Color = rgb(24, 24, 32),
			Material = Enum.Material.Glass,
		})
	end
end

-- Car body without wheels, resting on cinder blocks.
local function wreck(parent, cf, color)
	local m = model(parent, "Wreck")
	for _, x in { -3.2, 3.2 } do
		for _, z in { -1.6, 1.6 } do
			detail(m, { Name = "Block", Size = Vector3.new(1.2, 1, 1.6), CFrame = cf * CFrame.new(x, 0.5, z), Color = CONCRETE, Material = Enum.Material.Concrete })
		end
	end
	solid(m, { Name = "Body", Size = Vector3.new(9, 1.8, 4.2), CFrame = cf * CFrame.new(0, 1.9, 0) * CFrame.Angles(0, 0, 0.04), Color = color, Material = Enum.Material.Metal })
	solid(m, { Name = "Roof", Size = Vector3.new(4.6, 1.6, 3.8), CFrame = cf * CFrame.new(-0.6, 3.5, 0), Color = color, Material = Enum.Material.Metal })
	detail(m, { Name = "Windshield", Size = Vector3.new(0.2, 1.4, 3.6), CFrame = cf * CFrame.new(1.8, 3.4, 0) * CFrame.Angles(0, 0, math.rad(-30)), Color = rgb(150, 190, 220), Material = Enum.Material.Glass })
	detail(m, { Name = "Window", Size = Vector3.new(3.6, 1, 3.85), CFrame = cf * CFrame.new(-0.8, 3.55, 0), Color = rgb(60, 80, 100), Material = Enum.Material.Glass })
	detail(m, { Name = "Rust", Size = Vector3.new(2.4, 1.2, 4.25), CFrame = cf * CFrame.new(-2.6, 1.9, 0), Color = rgb(150, 82, 46), Material = Enum.Material.CorrodedMetal })
	detail(m, { Name = "Bumper", Size = Vector3.new(0.4, 0.5, 4.4), CFrame = cf * CFrame.new(4.6, 1.4, 0), Color = C.Metal, Material = Enum.Material.Metal })
	detail(m, { Name = "Snow", Size = Vector3.new(4.4, 0.25, 3.6), CFrame = cf * CFrame.new(-0.6, 4.4, 0), Color = C.Snow, Material = Enum.Material.Snow })
	for _, z in { -1.4, 1.4 } do
		detail(m, { Name = "Lamp", Size = Vector3.new(0.2, 0.5, 0.9), CFrame = cf * CFrame.new(4.55, 2.1, z), Color = rgb(255, 230, 160), Material = Enum.Material.Glass })
	end
	return m
end

-- Rack with wheel rims hanging on a bar.
local function rimRack(parent, cf)
	local m = model(parent, "RimRack")
	for _, x in { -3.5, 3.5 } do
		solid(m, { Name = "Post", Size = Vector3.new(0.4, 5, 0.4), CFrame = cf * CFrame.new(x, 2.5, 0), Color = STEEL, Material = Enum.Material.Metal })
	end
	detail(m, { Name = "Bar", Shape = Enum.PartType.Cylinder, Size = Vector3.new(7.4, 0.3, 0.3), CFrame = cf * CFrame.new(0, 4.6, 0), Color = STEEL, Material = Enum.Material.Metal })
	for index = 0, 3 do
		local rim = cf * CFrame.new(-2.55 + index * 1.7, 3.5, 0) * yaw(90)
		detail(m, { Name = "Rim", Shape = Enum.PartType.Cylinder, Size = Vector3.new(0.5, 2.2, 2.2), CFrame = rim, Color = if index % 2 == 0 then C.Metal else rgb(220, 186, 70), Material = Enum.Material.Metal })
		detail(m, { Name = "RimHub", Shape = Enum.PartType.Cylinder, Size = Vector3.new(0.6, 0.8, 0.8), CFrame = rim, Color = C.Ink, Material = Enum.Material.Metal })
	end
	return m
end

-- `at(x, y, z, yaw)` is the zone's frame. In this zone local -X points away from the plaza
-- (build.luau's lookAt is mirrored), local Z runs along the zone's edge. The junk field is
-- x in [-23, 23], z in [-21, 31] (SpawnArea in build.luau), so everything here stays outside.
function Locations.TireMountain(parent, at)
	-- Behind the field: the mountain itself and two smaller heaps beside it.
	tirePile(parent, at(-37, 0, 4), 12.5, 14, 11)
	tirePile(parent, at(-30.5, 0, -25), 7, 7, 23)
	tirePile(parent, at(-31, 0, 30.5), 6.5, 6, 37)
	-- A giant tire leaning on the mountain, readable from the plaza.
	local giant = at(-25.5, 0, -10, 70) * CFrame.new(0, 5.6, 0) * CFrame.Angles(math.rad(-14), 0, 0)
	solid(parent, { Name = "GiantTire", Shape = Enum.PartType.Cylinder, Size = Vector3.new(3.6, 11, 11), CFrame = giant * yaw(90), Color = RUBBER[1] })
	detail(parent, { Name = "GiantHub", Shape = Enum.PartType.Cylinder, Size = Vector3.new(3.7, 5.2, 5.2), CFrame = giant * yaw(90), Color = rgb(255, 204, 48), Material = Enum.Material.Metal })
	detail(parent, { Name = "GiantCenter", Shape = Enum.PartType.Cylinder, Size = Vector3.new(3.8, 1.8, 1.8), CFrame = giant * yaw(90), Color = C.Ink, Material = Enum.Material.Metal })
	-- Tire walls along both side edges of the field.
	for index = 0, 6 do
		local x = -19 + index * 6
		tireColumn(parent, at(x, 0, -25.5), 2 + index % 3, index * 7 + 1)
		if x < 6 then
			tireColumn(parent, at(x, 0, 34), 2 + (index + 1) % 3, index * 7 + 2)
		end
	end
	wreck(parent, at(17, 0, -29), rgb(70, 120, 180))
	rimRack(parent, at(14, 0, 33.5))
	puddle(parent, at(-22, 0, -16), 3.2)
	puddle(parent, at(-24, 0, 22), 2.4)
	puddle(parent, at(6, 0, -27), 2.8)
	Prefabs.SnowPile(parent, at(26, 0, 33, 90), 0.4)
	Prefabs.Lamp(parent, at(-26, 0, -30), false)
	Prefabs.Lamp(parent, at(-26, 0, 35), true)
end

---------------------------------------------------------------------------------------------
-- Crane Yard
---------------------------------------------------------------------------------------------

local YELLOW = rgb(255, 196, 40)
local YELLOW_DARK = rgb(214, 150, 24)

-- Square lattice section between two heights (four columns, X braces on every face).
local function lattice(parent, base, width, bottom, top, step)
	local half = width / 2
	for _, x in { -half, half } do
		for _, z in { -half, half } do
			solid(parent, { Name = "Column", Size = Vector3.new(0.5, top - bottom, 0.5), CFrame = base * CFrame.new(x, (top + bottom) / 2, z), Color = YELLOW, Material = Enum.Material.Metal })
		end
	end
	local length = math.sqrt(width * width + step * step)
	local angle = math.atan2(step, width)
	local level = 0
	local y = bottom
	while y + step <= top + 0.01 do
		local mid = y + step / 2
		for face = 0, 3 do
			local faceCf = base * yaw(face * 90) * CFrame.new(0, mid, -half)
			local tilt = if (level + face) % 2 == 0 then angle else -angle
			detail(parent, { Name = "Brace", Size = Vector3.new(length, 0.26, 0.26), CFrame = faceCf * CFrame.Angles(0, 0, tilt), Color = YELLOW_DARK, Material = Enum.Material.Metal })
		end
		y += step
		level += 1
	end
end

-- Triangular lattice boom along +X from `base` (length, height of the triangle, width).
local function boom(parent, base, length, height, width, step)
	local function point(x, y, z)
		return (base * CFrame.new(x, y, z)).Position
	end
	local top, left, right = { 0, height, 0 }, { 0, 0, -width / 2 }, { 0, 0, width / 2 }
	for _, c in { top, left, right } do
		bar(parent, point(0, c[2], c[3]), point(length, c[2], c[3]), 0.45, YELLOW, true)
	end
	local count = math.floor(length / step)
	for index = 0, count - 1 do
		local x0, x1 = index * step, (index + 1) * step
		-- Zig-zag on both side faces, a cross bar on the bottom.
		for _, side in { left, right } do
			if index % 2 == 0 then
				bar(parent, point(x0, side[2], side[3]), point(x1, top[2], top[3]), 0.22, YELLOW_DARK)
			else
				bar(parent, point(x0, top[2], top[3]), point(x1, side[2], side[3]), 0.22, YELLOW_DARK)
			end
		end
		bar(parent, point(x1, 0, -width / 2), point(x1, 0, width / 2), 0.2, YELLOW_DARK)
	end
end

local function warningLight(parent, cf)
	local bulb = detail(parent, { Name = "WarningLight", Shape = Enum.PartType.Ball, Size = Vector3.new(0.9, 0.9, 0.9), CFrame = cf, Color = rgb(255, 60, 50), Material = Enum.Material.Neon })
	local light = Instance.new("PointLight")
	light.Color = rgb(255, 70, 60)
	light.Range = 10
	light.Brightness = 1
	light.Shadows = false
	light.Parent = bulb
end

local function towerCrane(parent, cf)
	local m = model(parent, "TowerCrane")
	-- Footing
	solid(m, { Name = "Footing", Size = Vector3.new(12, 1.6, 12), CFrame = cf * CFrame.new(0, 0.8, 0), Color = CONCRETE, Material = Enum.Material.Concrete })
	for _, x in { -4.6, 4.6 } do
		for _, z in { -4.6, 4.6 } do
			detail(m, { Name = "Anchor", Size = Vector3.new(1.6, 0.6, 1.6), CFrame = cf * CFrame.new(x, 1.9, z), Color = C.Ink, Material = Enum.Material.Metal })
		end
	end
	detail(m, { Name = "FootingSnow", Size = Vector3.new(11.4, 0.2, 3.2), CFrame = cf * CFrame.new(0, 1.7, 4.2), Color = C.Snow, Material = Enum.Material.Snow })
	-- Mast
	local mastTop = 48
	lattice(m, cf, 3.6, 2.2, mastTop, 4.6)
	-- Slewing unit, cab, A-frame
	local head = cf * CFrame.new(0, mastTop, 0)
	solid(m, { Name = "Slew", Shape = Enum.PartType.Cylinder, Size = Vector3.new(1.2, 5, 5), CFrame = head * CFrame.new(0, 0.6, 0) * UPRIGHT, Color = C.Ink, Material = Enum.Material.Metal })
	solid(m, { Name = "Platform", Size = Vector3.new(6, 0.8, 5), CFrame = head * CFrame.new(0, 1.6, 0), Color = YELLOW, Material = Enum.Material.Metal })
	solid(m, { Name = "Cab", Size = Vector3.new(3.6, 3.4, 3.4), CFrame = head * CFrame.new(1.2, 3.6, -3.4), Color = rgb(236, 74, 70), Material = Enum.Material.Metal })
	detail(m, { Name = "CabGlass", Size = Vector3.new(3.4, 2, 0.2), CFrame = head * CFrame.new(1.2, 4, -5.15), Color = rgb(140, 200, 240), Material = Enum.Material.Glass, Transparency = 0.2 })
	detail(m, { Name = "CabGlassSide", Size = Vector3.new(0.2, 2, 3), CFrame = head * CFrame.new(3.05, 4, -3.4), Color = rgb(140, 200, 240), Material = Enum.Material.Glass, Transparency = 0.2 })
	local cabLight = detail(m, { Name = "CabLight", Size = Vector3.new(1, 0.3, 1), CFrame = head * CFrame.new(1.2, 5.2, -3.4), Color = rgb(255, 220, 150), Material = Enum.Material.Neon })
	local glow = Instance.new("PointLight")
	glow.Color = rgb(255, 210, 140)
	glow.Range = 8
	glow.Brightness = 0.8
	glow.Shadows = false
	glow.Parent = cabLight
	for _, z in { -1.2, 1.2 } do
		detail(m, { Name = "AFrame", Size = Vector3.new(0.4, 9, 0.4), CFrame = head * CFrame.new(0, 6.5, z) * CFrame.Angles(math.rad(z > 0 and -8 or 8), 0, 0), Color = YELLOW, Material = Enum.Material.Metal })
	end
	warningLight(m, head * CFrame.new(0, 11.4, 0))
	-- Jib (+X) and counter-jib (-X)
	boom(m, head * CFrame.new(2.4, 1.2, 0), 40, 2.6, 2.2, 3.3)
	boom(m, head * CFrame.new(-14.4, 1.2, 0), 12, 1.6, 2.6, 3)
	for index = 0, 2 do
		solid(m, { Name = "Counterweight", Size = Vector3.new(2, 3.4, 3.2), CFrame = head * CFrame.new(-13.4 + index * 2.1, 0, 0), Color = CONCRETE, Material = Enum.Material.Concrete })
	end
	-- Pendant lines from the A-frame to both booms
	local apex = head * CFrame.new(0, 11, 0)
	for _, target in { head * CFrame.new(30, 3.8, 0), head * CFrame.new(-12, 2.8, 0) } do
		local a, b = apex.Position, target.Position
		detail(m, { Name = "Pendant", Size = Vector3.new(0.14, 0.14, (b - a).Magnitude), CFrame = CFrame.lookAt((a + b) / 2, b), Color = C.Ink })
	end
	warningLight(m, head * CFrame.new(42.6, 2.4, 0))
	-- Trolley, hook block and the load: a bundle of pipes swinging over the yard
	local trolleyX = 27
	detail(m, { Name = "Trolley", Size = Vector3.new(2.4, 0.8, 2.6), CFrame = head * CFrame.new(trolleyX, 0.6, 0), Color = C.Ink, Material = Enum.Material.Metal })
	local hookY = -22
	for _, z in { -0.4, 0.4 } do
		detail(m, { Name = "Rope", Size = Vector3.new(0.12, -hookY, 0.12), CFrame = head * CFrame.new(trolleyX, hookY / 2, z), Color = C.Ink })
	end
	solid(m, { Name = "HookBlock", Size = Vector3.new(1.6, 2, 1.4), CFrame = head * CFrame.new(trolleyX, hookY - 1, 0), Color = rgb(255, 148, 36), Material = Enum.Material.Metal })
	detail(m, { Name = "Hook", Size = Vector3.new(0.5, 1.2, 0.5), CFrame = head * CFrame.new(trolleyX, hookY - 2.6, 0), Color = C.Ink, Material = Enum.Material.Metal })
	local load = head * CFrame.new(trolleyX, hookY - 7, 0)
	for _, z in { -1.2, 1.2 } do
		local a = (head * CFrame.new(trolleyX, hookY - 3, 0)).Position
		local b = (load * CFrame.new(0, 1, z * 2.2)).Position
		detail(m, { Name = "Sling", Size = Vector3.new(0.1, 0.1, (b - a).Magnitude), CFrame = CFrame.lookAt((a + b) / 2, b), Color = C.Ink })
	end
	for row = 0, 1 do
		for index = 0, 2 - row do
			solid(m, {
				Name = "Pipe",
				Shape = Enum.PartType.Cylinder,
				Size = Vector3.new(1.3, 1.25, 10),
				CFrame = load * CFrame.new(0, row * 1.1, (index - (2 - row) / 2) * 1.3) * yaw(90) * CFrame.Angles(0, 0, 0),
				Color = rgb(72, 140, 210),
				Material = Enum.Material.Metal,
				CastShadow = false,
			})
		end
	end
	return m
end

local function cabin(parent, cf)
	local m = model(parent, "SiteCabin")
	solid(m, { Name = "Body", Size = Vector3.new(14, 6, 7), CFrame = cf * CFrame.new(0, 3.6, 0), Color = rgb(236, 236, 240), Material = Enum.Material.Metal })
	for _, x in { -6.6, 6.6 } do
		detail(m, { Name = "Corner", Size = Vector3.new(0.8, 6.2, 7.2), CFrame = cf * CFrame.new(x, 3.6, 0), Color = rgb(58, 138, 236), Material = Enum.Material.Metal })
	end
	detail(m, { Name = "Stripe", Size = Vector3.new(12.4, 0.5, 7.1), CFrame = cf * CFrame.new(0, 1.2, 0), Color = rgb(58, 138, 236), Material = Enum.Material.Metal })
	for index, x in { -3.6, 3.2 } do
		local window = detail(m, { Name = "Window", Size = Vector3.new(3, 1.8, 0.2), CFrame = cf * CFrame.new(x, 4.2, -3.55), Color = rgb(255, 214, 140), Material = Enum.Material.Neon })
		if index == 1 then
			local light = Instance.new("PointLight")
			light.Color = rgb(255, 200, 130)
			light.Range = 12
			light.Brightness = 0.7
			light.Shadows = false
			light.Parent = window
		end
		detail(m, { Name = "Frame", Size = Vector3.new(3.4, 0.25, 0.3), CFrame = cf * CFrame.new(x, 3.25, -3.55), Color = C.Ink })
	end
	detail(m, { Name = "Door", Size = Vector3.new(1.8, 3.8, 0.2), CFrame = cf * CFrame.new(0, 2.9, -3.55), Color = rgb(58, 138, 236), Material = Enum.Material.Metal })
	for step = 0, 2 do
		detail(m, { Name = "Step", Size = Vector3.new(2.4, 0.3, 0.9), CFrame = cf * CFrame.new(0, 0.3 + step * 0.35, -4.4 + step * 0.4), Color = STEEL, Material = Enum.Material.DiamondPlate, CanCollide = true })
	end
	detail(m, { Name = "AC", Size = Vector3.new(1.8, 1.4, 1.2), CFrame = cf * CFrame.new(5, 5.2, 3.9), Color = rgb(200, 206, 214), Material = Enum.Material.Metal })
	detail(m, { Name = "Roof", Size = Vector3.new(14.6, 0.4, 7.6), CFrame = cf * CFrame.new(0, 6.8, 0), Color = C.Ink, Material = Enum.Material.Metal })
	detail(m, { Name = "RoofSnow", Size = Vector3.new(14.2, 0.5, 7.2), CFrame = cf * CFrame.new(0, 7.2, 0), Color = C.Snow, Material = Enum.Material.Snow })
	for _, x in { -5.5, 5.5 } do
		detail(m, { Name = "Block", Size = Vector3.new(1.4, 0.6, 6.6), CFrame = cf * CFrame.new(x, 0.3, 0), Color = CONCRETE, Material = Enum.Material.Concrete })
	end
	return m
end

local function jerseyBarrier(parent, cf, color)
	local m = model(parent, "Barrier")
	solid(m, { Name = "Base", Size = Vector3.new(6, 1, 2), CFrame = cf * CFrame.new(0, 0.5, 0), Color = CONCRETE, Material = Enum.Material.Concrete })
	solid(m, { Name = "Top", Size = Vector3.new(6, 1.4, 0.9), CFrame = cf * CFrame.new(0, 1.7, 0), Color = CONCRETE, Material = Enum.Material.Concrete })
	for index = 0, 2 do
		detail(m, { Name = "Stripe", Size = Vector3.new(1, 0.9, 0.95), CFrame = cf * CFrame.new(-2 + index * 2, 1.8, 0) * CFrame.Angles(0, 0, math.rad(35)), Color = if index % 2 == 0 then color else C.Snow })
	end
	return m
end

local function cone(parent, cf)
	detail(parent, { Name = "ConeBase", Size = Vector3.new(1.4, 0.2, 1.4), CFrame = cf * CFrame.new(0, 0.1, 0), Color = C.Ink })
	detail(parent, { Name = "Cone", Shape = Enum.PartType.Cylinder, Size = Vector3.new(1.6, 0.9, 0.9), CFrame = cf * CFrame.new(0, 1, 0) * UPRIGHT, Color = rgb(255, 120, 30) })
	detail(parent, { Name = "ConeStripe", Shape = Enum.PartType.Cylinder, Size = Vector3.new(0.35, 0.95, 0.95), CFrame = cf * CFrame.new(0, 1.15, 0) * UPRIGHT, Color = C.Snow })
end

local function pallet(parent, cf, withCrates)
	local m = model(parent, "Pallet")
	for index = -1, 1 do
		detail(m, { Name = "Runner", Size = Vector3.new(4, 0.4, 0.5), CFrame = cf * CFrame.new(0, 0.2, index * 1.6), Color = rgb(176, 124, 74), Material = Enum.Material.WoodPlanks })
	end
	solid(m, { Name = "Deck", Size = Vector3.new(4, 0.2, 4), CFrame = cf * CFrame.new(0, 0.5, 0), Color = rgb(196, 144, 92), Material = Enum.Material.WoodPlanks })
	if withCrates then
		solid(m, { Name = "Crate", Size = Vector3.new(3.6, 2.4, 3.6), CFrame = cf * CFrame.new(0, 1.8, 0), Color = rgb(176, 124, 74), Material = Enum.Material.WoodPlanks })
		detail(m, { Name = "Strap", Size = Vector3.new(3.7, 2.45, 0.2), CFrame = cf * CFrame.new(0, 1.8, 0), Color = C.Ink })
		detail(m, { Name = "Snow", Size = Vector3.new(3.4, 0.25, 3.4), CFrame = cf * CFrame.new(0, 3.1, 0), Color = C.Snow, Material = Enum.Material.Snow })
	end
	return m
end

local function pipeStack(parent, cf)
	local m = model(parent, "PipeStack")
	for _, x in { -3, 3 } do
		detail(m, { Name = "Sleeper", Size = Vector3.new(0.8, 0.6, 5), CFrame = cf * CFrame.new(x, 0.3, 0), Color = rgb(124, 82, 52), Material = Enum.Material.Wood })
	end
	for row = 0, 2 do
		for index = 0, 3 - row do
			local z = (index - (3 - row) / 2) * 1.25
			solid(m, { Name = "Pipe", Shape = Enum.PartType.Cylinder, Size = Vector3.new(11, 1.2, 1.2), CFrame = cf * CFrame.new(0, 1.2 + row * 1.05, z), Color = if row == 2 then rgb(236, 74, 70) else rgb(160, 170, 186), Material = Enum.Material.Metal, CastShadow = row == 0 })
		end
	end
	return m
end

local function beamPile(parent, cf)
	local m = model(parent, "Beams")
	for index = 0, 3 do
		local beam = cf * CFrame.new(0, 0.5 + (index // 2) * 1.1, (index % 2 - 0.5) * 1.8) * yaw(index * 4)
		solid(m, { Name = "Web", Size = Vector3.new(12, 0.9, 0.2), CFrame = beam, Color = rgb(150, 82, 46), Material = Enum.Material.CorrodedMetal, CastShadow = index < 2 })
		detail(m, { Name = "Flange", Size = Vector3.new(12, 0.15, 1), CFrame = beam * CFrame.new(0, 0.45, 0), Color = rgb(130, 70, 40), Material = Enum.Material.CorrodedMetal })
		detail(m, { Name = "Flange", Size = Vector3.new(12, 0.15, 1), CFrame = beam * CFrame.new(0, -0.45, 0), Color = rgb(130, 70, 40), Material = Enum.Material.CorrodedMetal })
	end
	return m
end

local function floodlight(parent, cf, facingDegrees)
	local m = model(parent, "Floodlight")
	solid(m, { Name = "Base", Size = Vector3.new(3, 0.8, 3), CFrame = cf * CFrame.new(0, 0.4, 0), Color = rgb(255, 204, 48), Material = Enum.Material.Metal })
	solid(m, { Name = "Mast", Size = Vector3.new(0.5, 14, 0.5), CFrame = cf * CFrame.new(0, 7.8, 0), Color = STEEL, Material = Enum.Material.Metal })
	local head = cf * CFrame.new(0, 14.8, 0) * yaw(facingDegrees) * CFrame.Angles(math.rad(-25), 0, 0)
	detail(m, { Name = "Frame", Size = Vector3.new(4.2, 2.2, 0.6), CFrame = head, Color = C.Ink, Material = Enum.Material.Metal })
	for x = -1, 1 do
		local lamp = detail(m, { Name = "Lamp", Size = Vector3.new(1.1, 1.6, 0.2), CFrame = head * CFrame.new(x * 1.3, 0, -0.35), Color = rgb(255, 248, 225), Material = Enum.Material.Neon })
		if x == 0 then
			local spot = Instance.new("SpotLight")
			spot.Face = Enum.NormalId.Front
			spot.Angle = 70
			spot.Range = 40
			spot.Brightness = 1.6
			spot.Color = rgb(255, 244, 220)
			spot.Shadows = false
			spot.Parent = lamp
		end
	end
	return m
end

local function fence(parent, from, to)
	local m = model(parent, "Fence")
	local length = (to - from).Magnitude
	local count = math.max(1, math.floor(length / 6))
	local dir = (to - from).Unit
	for index = 0, count do
		local p = from + dir * (length * index / count)
		solid(m, { Name = "Post", Size = Vector3.new(0.35, 6, 0.35), CFrame = CFrame.new(p + Vector3.new(0, 3, 0)), Color = STEEL, Material = Enum.Material.Metal, CastShadow = false })
		if index < count then
			local q = from + dir * (length * (index + 0.5) / count)
			local look = CFrame.lookAt(q + Vector3.new(0, 3, 0), q + Vector3.new(0, 3, 0) + dir)
			detail(m, { Name = "Mesh", Size = Vector3.new(0.1, 5.4, length / count), CFrame = look, Color = STEEL, Material = Enum.Material.DiamondPlate, Transparency = 0.55, CanCollide = true })
			detail(m, { Name = "Rail", Size = Vector3.new(0.15, 0.15, length / count), CFrame = look * CFrame.new(0, 2.8, 0), Color = STEEL, Material = Enum.Material.Metal })
		end
	end
	return m
end

-- Center: the corner's CFrame on the ground, -Z towards the yard's center. Returns the
-- JunkSpawn area part.
function Locations.CraneYard(parent, cf)
	local m = model(parent, "CraneYard")
	-- Ground: packed snow and gravel, a darker work area, tire tracks.
	solid(m, { Name = "Ground", Size = Vector3.new(70, 0.1, 66), CFrame = cf * CFrame.new(0, 0.05, -8), Color = rgb(226, 232, 242), Material = Enum.Material.Snow, CastShadow = false })
	solid(m, { Name = "WorkArea", Size = Vector3.new(44, 0.1, 40), CFrame = cf * CFrame.new(0, 0.11, -14), Color = rgb(196, 204, 218), Material = Enum.Material.Pebble, CastShadow = false })
	for _, x in { -9, -5.5, 6, 9.5 } do
		detail(m, { Name = "Track", Size = Vector3.new(1.4, 0.1, 56), CFrame = cf * CFrame.new(x, 0.21, -10) * yaw(x * 0.4), Color = rgb(170, 180, 198), Material = Enum.Material.Pebble })
	end
	towerCrane(m, cf * CFrame.new(0, 0, 16) * yaw(108)) -- jib over the yard (-Z)
	cabin(m, cf * CFrame.new(-24, 0, -30) * yaw(60))
	Prefabs.Container(m, cf * CFrame.new(26, 0, 4) * yaw(-75), C.Purple)
	Prefabs.Container(m, cf * CFrame.new(26, 9, 4) * yaw(-70), C.Orange)
	Prefabs.OpenContainer(m, cf * CFrame.new(27, 0, -24) * yaw(-100), C.Green)
	pipeStack(m, cf * CFrame.new(-26, 0, 2) * yaw(80))
	beamPile(m, cf * CFrame.new(-23, 0, -11) * yaw(95))
	pallet(m, cf * CFrame.new(-17, 0, 18), true)
	pallet(m, cf * CFrame.new(-12.5, 0, 19) * yaw(12), true)
	pallet(m, cf * CFrame.new(-15, 0, 22.8) * yaw(-8), false)
	for index, p in { { -6, 6 }, { 6, 6 }, { -14, -34 }, { 14, -34 }, { 0, -38 } } do
		jerseyBarrier(m, cf * CFrame.new(p[1], 0, p[2]) * yaw(if index <= 2 then 90 else 0), if index % 2 == 0 then rgb(236, 74, 70) else rgb(255, 204, 48))
	end
	for _, p in { { -4, 10 }, { 4, 10 }, { 19, -12 }, { 20, -16 }, { -19, -20 }, { 9, -36 } } do
		cone(m, cf * CFrame.new(p[1], 0, p[2]))
	end
	Prefabs.Barrel(m, cf * CFrame.new(20, 0, 16), C.Red)
	Prefabs.Barrel(m, cf * CFrame.new(22.8, 0, 17.5), C.Blue)
	Prefabs.Barrel(m, cf * CFrame.new(-28, 0, -20), C.Orange)
	floodlight(m, cf * CFrame.new(-25, 0, 12), 200)
	floodlight(m, cf * CFrame.new(24, 0, -34), 30)
	-- Fence along the back corner
	local function local3(x, z)
		return (cf * CFrame.new(x, 0, z)).Position
	end
	fence(m, local3(-32, 10), local3(-12, 30))
	fence(m, local3(12, 30), local3(32, 10))
	Prefabs.SnowPile(m, cf * CFrame.new(0, 0, 32), 0.6)
	Prefabs.SnowPile(m, cf * CFrame.new(-33, 0, -26) * yaw(60), 0.45)
	Prefabs.Sign(m, cf * CFrame.new(-18, 0, -40) * yaw(10), "CRANE YARD", C.Orange)
	-- Junk falls on the work area.
	return Prefabs.JunkSpawnArea(m, cf * CFrame.new(0, 0.1, -16), 36, 32, "JunkSpawnArea")
end

return Locations
