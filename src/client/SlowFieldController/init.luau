--!strict
--[[
	SlowFieldController: being inside a running Aurora Reactor (player attribute SlowFactor, set by
	the server). Your jumps and falls go in slow motion: the jump starts slower and gravity is
	weaker by the square, so you jump just as high but it takes longer. The picture gets a soft
	aurora tint. The walk speed itself is the server's.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local ItemSounds = require(ReplicatedStorage.Shared.Config.ItemSounds)

local AudioController = require(script.Parent.AudioController)

local SlowFieldController = {}

local localPlayer = Players.LocalPlayer
local tint: ColorCorrectionEffect? = nil
local force: VectorForce? = nil

local function factor(): number
	local value = localPlayer:GetAttribute("SlowFactor")
	return if type(value) == "number" then value else 1
end

local function showTint(on: boolean)
	local camera = Workspace.CurrentCamera
	if tint == nil or tint.Parent == nil then
		local effect = Instance.new("ColorCorrectionEffect")
		effect.Name = "SlowFieldTint"
		effect.Parent = camera
		tint = effect
	end
	TweenService:Create(tint :: ColorCorrectionEffect, TweenInfo.new(0.5), {
		TintColor = if on then Color3.fromRGB(190, 245, 235) else Color3.new(1, 1, 1),
		Saturation = if on then -0.12 else 0,
		Contrast = if on then 0.06 else 0,
	}):Play()
end

local function step()
	local slow = factor()
	local character = localPlayer.Character
	local root = if character ~= nil then character:FindFirstChild("HumanoidRootPart") else nil
	local humanoid = if character ~= nil then character:FindFirstChildOfClass("Humanoid") else nil
	local airborne = slow < 1 and root ~= nil and root:IsA("BasePart") and humanoid ~= nil
		and humanoid.SeatPart == nil
		and (humanoid:GetState() == Enum.HumanoidStateType.Jumping or humanoid:GetState() == Enum.HumanoidStateType.Freefall)
	if not airborne then
		if force ~= nil then
			force.Enabled = false
		end
		return
	end
	local body = root :: BasePart
	local attachment = body:FindFirstChild("RootAttachment") or body:FindFirstChildOfClass("Attachment")
	if attachment == nil or not attachment:IsA("Attachment") then
		return
	end
	if force == nil or force.Parent ~= body then
		local f = Instance.new("VectorForce")
		f.Name = "SlowFall"
		f.ApplyAtCenterOfMass = true
		f.RelativeTo = Enum.ActuatorRelativeTo.World
		f.Parent = body
		force = f
	end
	local f = force :: VectorForce
	f.Attachment0 = attachment
	f.Force = Vector3.new(0, body.AssemblyMass * Workspace.Gravity * (1 - slow * slow), 0)
	f.Enabled = true
end

local function hook(character: Model)
	local humanoid = character:WaitForChild("Humanoid", 10)
	if humanoid == nil or not humanoid:IsA("Humanoid") then
		return
	end
	humanoid.StateChanged:Connect(function(_, state: Enum.HumanoidStateType)
		local slow = factor()
		if state == Enum.HumanoidStateType.Jumping and slow < 1 then
			RunService.PreSimulation:Wait() -- the jump has given its speed
			local root = character:FindFirstChild("HumanoidRootPart")
			if root ~= nil and root:IsA("BasePart") then
				local v = root.AssemblyLinearVelocity
				root.AssemblyLinearVelocity = Vector3.new(v.X, math.min(v.Y, math.max(v.Y, 0) * slow), v.Z)
			end
		end
	end)
end

function SlowFieldController.Start()
	localPlayer.CharacterAdded:Connect(function(character: Model)
		task.spawn(hook, character)
	end)
	if localPlayer.Character ~= nil then
		task.spawn(hook, localPlayer.Character)
	end
	localPlayer:GetAttributeChangedSignal("SlowFactor"):Connect(function()
		local inside = factor() < 1
		showTint(inside)
		if inside then
			local family, pitch = ItemSounds.ForEvent("SlowField")
			AudioController.PlayItem(family, pitch, nil, 0.7)
		end
	end)
	RunService.PreSimulation:Connect(step)
end

return SlowFieldController
