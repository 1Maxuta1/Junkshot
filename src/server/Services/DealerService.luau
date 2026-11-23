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
end

return DealerService
