--!strict
--[[
	DealerService: the Scrap Dealer, a trading booth on the plaza (the map's reserved
	"RecyclerSite"). It is the one place where items are sold, the shop is open and player
	upgrades are bought.

	  - The booth is a placeholder model built from Parts at startup (Workspace.ScrapDealer).
	  - Its prompt ("Trade", R / Y / tap) opens the dealer window on the client
	    (PromptKind "Dealer"); nothing is decided by the prompt itself.
	  - IsNear(player): every sale / purchase checks it on the server (EconomyConfig.DealerDistance).
]]

local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local EconomyConfig = require(ReplicatedStorage.Shared.Config.EconomyConfig)
local GameConfig = require(ReplicatedStorage.Shared.Config.GameConfig)

local CarryService = require(script.Parent.CarryService)

local DealerService = {}

local SITE_TAG = "RecyclerSite"
local FALLBACK = CFrame.new(0, 0.4, 0)

local started = false
local anchor: BasePart? = nil

local function part(model: Model, name: string, size: Vector3, cframe: CFrame, color: Color3, material: Enum.Material?): Part
	local p = Instance.new("Part")
	p.Name = name
	p.Size = size
	p.CFrame = cframe
	p.Color = color
	p.Material = material or Enum.Material.SmoothPlastic
	p.Anchored = true
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.Parent = model
	return p
end

local function rgb(r: number, g: number, b: number): Color3
	return Color3.fromRGB(r, g, b)
end

-- Steel drum standing on the ground at `base` (3.4 tall, 2.6 wide): rims, hoops, lid, bung.
local function drum(model: Model, base: CFrame, color: Color3)
	local dark = color:Lerp(rgb(44, 56, 82), 0.45)
	local upright = CFrame.Angles(0, 0, math.rad(90))
	local function ring(name: string, y: number, diameter: number, height: number, ringColor: Color3): Part
		local p = part(model, name, Vector3.new(height, diameter, diameter), base * CFrame.new(0, y, 0) * upright, ringColor, Enum.Material.Metal)
		p.Shape = Enum.PartType.Cylinder
		p.CanCollide = false
		p.CanQuery = false
		p.CastShadow = false
		return p
	end
	local body = ring("Barrel", 1.7, 2.5, 3.2, color)
	body.CanCollide = true
	body.CanQuery = true
	body.CastShadow = true
	ring("BarrelRim", 0.1, 2.6, 0.2, dark)
	ring("BarrelRim", 3.3, 2.6, 0.2, dark)
	ring("BarrelHoop", 1.15, 2.64, 0.18, dark)
	ring("BarrelHoop", 2.25, 2.64, 0.18, dark)
	ring("BarrelLid", 3.33, 2.2, 0.06, color:Lerp(rgb(44, 56, 82), 0.25))
	local bung = ring("BarrelBung", 3.42, 0.36, 0.14, rgb(176, 188, 204))
	bung.CFrame = base * CFrame.new(0.6, 3.42, 0.25) * upright
end

-- Placeholder booth: counter, awning, sign, scale and a pile of coins. Front = -Z (towards +Z
-- of the plaza is fine: players reach it from every side through the prompt distance).
local function buildBooth(ground: CFrame): Model
	local model = Instance.new("Model")
	model.Name = "ScrapDealer"
	local at = function(x: number, y: number, z: number): CFrame
		return ground * CFrame.new(x, y, z)
	end
	part(model, "Floor", Vector3.new(14, 0.4, 10), at(0, 0.2, 0), rgb(70, 160, 230))
	local counter = part(model, "Counter", Vector3.new(12, 3.2, 2.4), at(0, 2, -2.5), rgb(255, 150, 30))
	part(model, "CounterTop", Vector3.new(12.6, 0.4, 3), at(0, 3.8, -2.5), rgb(255, 210, 60))
	part(model, "BackWall", Vector3.new(14, 7, 0.6), at(0, 3.9, 4.6), rgb(236, 74, 70))
	for _, x in { -6.6, 6.6 } do
		part(model, "Post", Vector3.new(0.6, 9, 0.6), at(x, 4.9, -3.6), rgb(40, 44, 64), Enum.Material.Metal)
	end
	for index = 0, 6 do
		local color = if index % 2 == 0 then rgb(255, 255, 255) else rgb(236, 74, 70)
		part(model, `Awning{index}`, Vector3.new(2, 0.3, 9.4), at(-6 + index * 2, 9.4, 0.4) * CFrame.Angles(math.rad(-8), 0, 0), color)
	end
	local sign = part(model, "Sign", Vector3.new(10, 2.2, 0.4), at(0, 11.2, -3.6), rgb(24, 44, 86))
	local gui = Instance.new("SurfaceGui")
	gui.Face = Enum.NormalId.Front
	gui.CanvasSize = Vector2.new(500, 110)
	gui.LightInfluence = 0
	local label = Instance.new("TextLabel")
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundTransparency = 1
	label.Font = Enum.Font.FredokaOne
	label.Text = "SCRAP DEALER"
	label.TextColor3 = rgb(255, 210, 60)
	label.TextScaled = true
	label.Parent = gui
	gui.Parent = sign
	-- A scale and a coin pile on the counter.
	part(model, "Scale", Vector3.new(1.6, 0.3, 1.6), at(-3, 4.15, -2.5), rgb(200, 206, 214), Enum.Material.Metal)
	for index = 1, 6 do
		local coin = part(model, `Coin{index}`, Vector3.new(0.25, 0.9, 0.9), at(2.2 + (index % 3) * 0.7, 4.15 + (index // 3) * 0.26, -2.4 + (index % 2) * 0.4), rgb(255, 205, 50), Enum.Material.Neon)
		coin.Shape = Enum.PartType.Cylinder
		coin.CFrame = coin.CFrame * CFrame.Angles(0, 0, math.rad(90))
	end

	-- Shop dressing: striped counter front, shelves with scrap, barrels, crates, lanterns, roof.
	for index = 0, 5 do
		part(model, "Stripe", Vector3.new(1, 2.4, 0.2), at(-5 + index * 2, 2, -3.78), if index % 2 == 0 then rgb(255, 255, 255) else rgb(236, 74, 70))
	end
	for _, y in { 4.2, 6.2 } do
		part(model, "Shelf", Vector3.new(11.5, 0.25, 1.3), at(0, y, 3.7), rgb(140, 92, 52), Enum.Material.WoodPlanks)
	end
	local goods = { rgb(58, 138, 236), rgb(255, 205, 50), rgb(72, 188, 98), rgb(150, 104, 228), rgb(176, 188, 204), rgb(255, 148, 36) }
	for index = 0, 5 do
		part(model, "Goods", Vector3.new(1.1, 1.1, 0.9), at(-4.8 + index * 1.9, 4.9 + (index % 2) * 2, 3.7) * CFrame.Angles(0, index, 0), goods[index + 1])
	end
	for _, x in { -8.6, 8.6 } do
		drum(model, at(x, 0, -2), if x < 0 then rgb(36, 188, 186) else rgb(236, 74, 70))
		part(model, "Crate", Vector3.new(2.6, 2.6, 2.6), at(x, 1.3, 1.4) * CFrame.Angles(0, 0.2, 0), rgb(176, 124, 74), Enum.Material.WoodPlanks)
		part(model, "CrateTop", Vector3.new(1.8, 1.8, 1.8), at(x, 3.5, 1.4) * CFrame.Angles(0, 0.7, 0), rgb(196, 144, 92), Enum.Material.WoodPlanks)
		local lantern = part(model, "Lantern", Vector3.new(1, 1.2, 1), at(x * 0.77, 8.2, -3.9), rgb(255, 205, 110), Enum.Material.Neon)
		lantern.CastShadow = false
	end
	part(model, "RoofSnow", Vector3.new(14.4, 0.35, 3), at(0, 9.95, 3.4), rgb(246, 250, 255))
	part(model, "SignFrame", Vector3.new(10.8, 2.9, 0.3), at(0, 11.2, -3.45), rgb(255, 205, 50))

	-- Scrappy Sam, the dealer: stands behind the counter, looking at the customers (-Z).
	local npc = Instance.new("Model")
	npc.Name = "ScrappySam"
	local skin, coat, apron = rgb(255, 204, 153), rgb(58, 138, 236), rgb(255, 150, 30)
	for _, x in { -0.5, 0.5 } do
		part(npc, "Leg", Vector3.new(0.9, 2, 0.9), at(x, 1.4, 0.2), rgb(44, 56, 82))
		part(npc, "Eye", Vector3.new(0.2, 0.3, 0.1), at(x * 0.56, 5.15, -0.42), rgb(30, 34, 48))
	end
	part(npc, "Torso", Vector3.new(2, 2, 1), at(0, 3.4, 0.2), coat)
	part(npc, "Apron", Vector3.new(1.5, 1.8, 0.15), at(0, 3.2, -0.35), apron)
	part(npc, "ArmL", Vector3.new(0.8, 0.8, 2), at(-1.4, 3.7, -0.5), coat)
	part(npc, "ArmR", Vector3.new(0.8, 0.8, 2), at(1.4, 3.7, -0.5), coat)
	part(npc, "HandL", Vector3.new(0.75, 0.75, 0.5), at(-1.4, 3.7, -1.7), skin)
	part(npc, "HandR", Vector3.new(0.75, 0.75, 0.5), at(1.4, 3.7, -1.7), skin)
	local head = part(npc, "Head", Vector3.new(1.3, 1.3, 1.2), at(0, 5.05, 0.2), skin)
	part(npc, "Smile", Vector3.new(0.6, 0.14, 0.1), at(0, 4.75, -0.42), rgb(150, 60, 50))
	part(npc, "Beard", Vector3.new(1.35, 0.4, 0.5), at(0, 4.5, -0.1), rgb(240, 244, 250))
	part(npc, "Hat", Vector3.new(1.5, 0.6, 1.4), at(0, 5.9, 0.2), rgb(236, 74, 70))
	part(npc, "HatRim", Vector3.new(1.6, 0.3, 1.5), at(0, 5.55, 0.2), rgb(246, 250, 255))
	local pompom = part(npc, "Pompom", Vector3.new(0.6, 0.6, 0.6), at(0, 6.4, 0.2), rgb(246, 250, 255))
	pompom.Shape = Enum.PartType.Ball
	local tag = Instance.new("BillboardGui")
	tag.Name = "NameTag"
	tag.Size = UDim2.fromScale(4, 0.7) -- in studs: it shrinks with distance
	tag.StudsOffsetWorldSpace = Vector3.new(0, 2.1, 0)
	tag.MaxDistance = 45
	tag.LightInfluence = 0
	local tagLabel = label:Clone()
	tagLabel.Text = "Scrappy Sam"
	tagLabel.TextStrokeTransparency = 0.2
	tagLabel.Parent = tag
	tag.Parent = head
	npc.Parent = model

	local promptAnchor = part(model, "PromptAnchor", Vector3.new(1, 1, 1), at(0, 4.5, -4), rgb(255, 255, 255))
	promptAnchor.Transparency = 1
	promptAnchor.CanCollide = false
	promptAnchor.CanQuery = false
	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = "DealerPrompt"
	prompt.ActionText = "Trade"
	prompt.ObjectText = "Scrap Dealer"
	prompt.KeyboardKeyCode = GameConfig.Input.MachineKey
	prompt.GamepadKeyCode = GameConfig.Input.MachineGamepadKey
	prompt.HoldDuration = 0
	prompt.RequiresLineOfSight = false
	prompt.MaxActivationDistance = 14
	prompt.Exclusivity = Enum.ProximityPromptExclusivity.AlwaysShow
	prompt.Style = Enum.ProximityPromptStyle.Custom
	prompt:SetAttribute("PromptKind", "Dealer")
	prompt.Parent = promptAnchor

	model.PrimaryPart = counter
	model:SetAttribute("Dealer", true)
	model.Parent = Workspace
	anchor = promptAnchor
	return model
end

function DealerService.GetPosition(): Vector3?
	return if anchor ~= nil then anchor.Position else nil
end

-- True when the player stands at the dealer (server check for every trade).
function DealerService.IsNear(player: Player): boolean
	local root = CarryService.GetLiveRoot(player)
	local position = DealerService.GetPosition()
	if root == nil or position == nil then
		return false
	end
	return (root.Position - position).Magnitude <= EconomyConfig.DealerDistance
end

function DealerService.Start()
	assert(not started, "[DealerService] Start() called twice")
	started = true
	local site = CollectionService:GetTagged(SITE_TAG)[1]
	local ground = FALLBACK
	if site ~= nil and site:IsA("BasePart") then
		ground = CFrame.new(site.Position.X, site.Position.Y - site.Size.Y / 2, site.Position.Z)
	end
	buildBooth(ground)
	-- The place file's own default SpawnLocation sits on this counter; players use Map.Spawns.
	for _, child in Workspace:GetChildren() do
		if child:IsA("SpawnLocation") then
			child.Enabled = false
			child.CanCollide = false
			child.CanTouch = false
			child.Transparency = 1
			local decal = child:FindFirstChildWhichIsA("Decal")
			if decal ~= nil then
				decal.Transparency = 1
			end
		end
	end
end

return DealerService
