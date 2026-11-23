--!strict
--[[
	CompanionController: animates every companion (Workspace.Companions) on this client.
	Each companion trails its owner (behind and to the side), glides smoothly, bobs while idle,
	hops a little while following and turns towards where it is going. Only companions within
	ANIMATE_RANGE of the camera are updated. Local only: nothing is sent to the server.
]]

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local CompanionController = {}

local OFFSET = Vector3.new(2.6, 0, 3.2) -- right / behind the owner
local ANIMATE_RANGE = 160
local SHARPNESS = 6
local GROUND_DROP = 3 -- studs from the owner's root down to their feet

type State = { Position: Vector3, Yaw: number, Phase: number }
local states: { [Model]: State } = {}

local function ownerRoot(model: Model): BasePart?
	local userId = model:GetAttribute("OwnerUserId")
	local owner = if type(userId) == "number" then Players:GetPlayerByUserId(userId) else nil
	local character = if owner ~= nil then owner.Character else nil
	local root = if character ~= nil then character:FindFirstChild("HumanoidRootPart") else nil
	return if root ~= nil and root:IsA("BasePart") then root else nil
end

local function step(dt: number)
	local folder = Workspace:FindFirstChild("Companions")
	local camera = Workspace.CurrentCamera
	if folder == nil or camera == nil then
		return
	end
	local alpha = 1 - math.exp(-SHARPNESS * dt)
	for _, model in folder:GetChildren() do
		if not model:IsA("Model") then
			continue
		end
		local root = ownerRoot(model)
		if root == nil or (root.Position - camera.CFrame.Position).Magnitude > ANIMATE_RANGE then
			continue
		end
		local state = states[model]
		local goal = (root.CFrame * CFrame.new(OFFSET)).Position - Vector3.new(0, GROUND_DROP, 0)
		if state == nil then
			state = { Position = goal, Yaw = 0, Phase = math.random() * 10 }
			states[model] = state
			model.AncestryChanged:Connect(function()
				if not model:IsDescendantOf(Workspace) then
					states[model] = nil
				end
			end)
		end
		local s = state :: State
		local before = s.Position
		if (goal - before).Magnitude > 40 then
			s.Position = goal -- teleported owner: jump straight there
		else
			s.Position = before:Lerp(goal, alpha)
		end
		local moved = s.Position - before
		local speed = moved.Magnitude / math.max(dt, 1e-3)
		if Vector3.new(moved.X, 0, moved.Z).Magnitude > 0.02 then
			s.Yaw = math.atan2(-moved.X, -moved.Z)
		else
			local look = root.CFrame.LookVector
			s.Yaw = math.atan2(-look.X, -look.Z)
		end
		s.Phase += dt * (if speed > 2 then 9 else 2.2)
		local bob = if speed > 2 then math.abs(math.sin(s.Phase)) * 0.45 else math.sin(s.Phase) * 0.12 + 0.12
		local tilt = if speed > 2 then math.sin(s.Phase) * 0.12 else 0
		model:PivotTo(CFrame.new(s.Position + Vector3.new(0, bob, 0)) * CFrame.Angles(0, s.Yaw, tilt))
	end
end

function CompanionController.Start()
	RunService.RenderStepped:Connect(step)
end

return CompanionController
