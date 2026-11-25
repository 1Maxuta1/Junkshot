--!strict
--[[
	BackpackController: life in the upgrade backpacks (Util/BackpackModels, worn by the server)
	and the moment you get a new one. Display only.

	  every pack near you   hangs back a little when its owner runs or falls, the core pulses,
	                        the ring turns, the thrusters flare in the air
	  your own upgrade      the full-screen reveal (UI/UpgradeReveal); other players see sparks
	Weak devices (LiteGraphics): the packs stand still.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local GameConfig = require(ReplicatedStorage.Shared.Config.GameConfig)
local PlayerUpgrades = require(ReplicatedStorage.Shared.Config.PlayerUpgrades)
local BackpackModels = require(ReplicatedStorage.Shared.Util.BackpackModels)

local UpgradeReveal = require(script.Parent.UI.UpgradeReveal)

local BackpackController = {}

local localPlayer = Players.LocalPlayer
local rgb = Color3.fromRGB
local RANGE = 80
local ATTRIBUTE = "Upgrade_CarryCapacity"

type Pack = {
	Model: Model,
	Root: BasePart,
	Humanoid: Humanoid?,
	Weld: Weld,
	Rest: CFrame,
	Lean: number,
	Spins: { { Weld: Weld, Center: CFrame, Offset: CFrame } },
	Pulses: { { Part: BasePart, Color: Color3, Light: PointLight?, Brightness: number } },
	Flames: { ParticleEmitter },
}
local packs: { [Player]: Pack } = {}

local function adopt(player: Player, model: Model)
	local character = player.Character
	local body = model.PrimaryPart
	local root = if character ~= nil then character:FindFirstChild("HumanoidRootPart") else nil
	local weld = if body ~= nil then body:FindFirstChild("PackWeld") else nil
	if character == nil or body == nil or weld == nil or not weld:IsA("Weld") or root == nil or not root:IsA("BasePart") then
		return
	end
	local pack: Pack = {
		Model = model,
		Root = root,
		Humanoid = character:FindFirstChildOfClass("Humanoid"),
		Weld = weld,
		Rest = weld.C0,
		Lean = 0,
		Spins = {},
		Pulses = {},
		Flames = {},
	}
	local core = model:FindFirstChild("Core")
	for _, d in model:GetDescendants() do
		if d:IsA("BasePart") then
			local spin = d:FindFirstChildOfClass("Weld")
			if d:GetAttribute("Spin") ~= nil and spin ~= nil and core ~= nil and core:IsA("BasePart") then
				local center = body.CFrame:ToObjectSpace(core.CFrame)
				table.insert(pack.Spins, { Weld = spin, Center = center, Offset = center:ToObjectSpace(spin.C0) })
			end
			if d:GetAttribute("Pulse") == true then
				local l = d:FindFirstChildOfClass("PointLight")
				table.insert(pack.Pulses, { Part = d, Color = d.Color, Light = l, Brightness = if l ~= nil then l.Brightness else 0 })
			end
		elseif d:IsA("ParticleEmitter") then
			table.insert(pack.Flames, d)
		end
	end
	packs[player] = pack
end

local function step(dt: number)
	if localPlayer:GetAttribute("LiteGraphics") == true then
		return
	end
	local camera = Workspace.CurrentCamera
	local now = os.clock()
	for player, pack in packs do
		if not pack.Model:IsDescendantOf(Workspace) or not pack.Root:IsDescendantOf(Workspace) then
			packs[player] = nil
			continue
		end
		if camera == nil or (camera.CFrame.Position - pack.Root.Position).Magnitude > RANGE then
			continue
		end
		local velocity = pack.Root.AssemblyLinearVelocity
		local speed = Vector3.new(velocity.X, 0, velocity.Z).Magnitude
		local wanted = math.clamp(speed * 0.35, 0, 8) - math.clamp(velocity.Y * 0.15, -8, 5)
		pack.Lean += (wanted - pack.Lean) * math.min(dt * 7, 1)
		local bounce = if speed > 2 then math.sin(now * 11) * math.min(speed, 20) * 0.0022 else math.sin(now * 2) * 0.008
		pack.Weld.C0 = pack.Rest * CFrame.new(0, bounce + 0.8, 0) * CFrame.Angles(-math.rad(math.max(pack.Lean, 0)), 0, 0) * CFrame.new(0, -0.8, 0) -- hangs from its top
		for _, spin in pack.Spins do
			spin.Weld.C0 = spin.Center * CFrame.Angles(0, 0, now * 1.3 % (math.pi * 2)) * spin.Offset
		end
		local wave = 0.5 + 0.5 * math.sin(now * 2.6)
		for _, pulse in pack.Pulses do
			pulse.Part.Color = pulse.Color:Lerp(Color3.new(1, 1, 1), wave * 0.45)
			if pulse.Light ~= nil then
				pulse.Light.Brightness = pulse.Brightness * (0.65 + wave * 0.6)
			end
		end
		local humanoid = pack.Humanoid
		local rate = if humanoid ~= nil and humanoid.FloorMaterial == Enum.Material.Air then 45 elseif speed > 6 then 16 else 7
		for _, flame in pack.Flames do
			flame.Rate = rate
		end
	end
end

local function reveal(level: number)
	local model = BackpackModels.Build(level)
	if model == nil then
		return
	end
	local upgrade = PlayerUpgrades.Get("CarryCapacity") :: any
	local old, new = upgrade.Levels[level - 1].Value, upgrade.Levels[level].Value
	UpgradeReveal.Show({
		Model = model,
		Head = "NEW BACKPACK!",
		Name = BackpackModels.Names[level] or "BACKPACK",
		Detail = `{GameConfig.Carry.MaxJunk + old} > {GameConfig.Carry.MaxJunk + new} SLOTS`,
		Color = BackpackModels.Colors[level] or rgb(255, 255, 255),
		Seconds = 6,
	})
end

local function watch(player: Player)
	local function onCharacter(character: Model)
		local function look(folder: Instance)
			if folder.Name == "JunkshotCosmetics" then
				local model = folder:WaitForChild("UpgradeBackpack", 2)
				if model ~= nil and model:IsA("Model") then
					adopt(player, model)
				end
			end
		end
		character.ChildAdded:Connect(look)
		local now = character:FindFirstChild("JunkshotCosmetics")
		if now ~= nil then
			task.spawn(look, now)
		end
	end
	player.CharacterAdded:Connect(onCharacter)
	if player.Character ~= nil then
		onCharacter(player.Character)
	end
	local last = player:GetAttribute(ATTRIBUTE)
	player:GetAttributeChangedSignal(ATTRIBUTE):Connect(function()
		local level = player:GetAttribute(ATTRIBUTE)
		if type(last) == "number" and type(level) == "number" and level == last + 1 then -- bought, not loaded
			UpgradeReveal.Sparks(player, BackpackModels.Colors[level] or rgb(255, 255, 255))
			if player == localPlayer then
				reveal(level)
			end
		end
		last = level
	end)
end

function BackpackController.Start()
	for _, player in Players:GetPlayers() do
		watch(player)
	end
	Players.PlayerAdded:Connect(watch)
	Players.PlayerRemoving:Connect(function(player: Player)
		packs[player] = nil
	end)
	RunService.Heartbeat:Connect(step)
end

return BackpackController
