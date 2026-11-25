--!strict
--[[
	FirstPersonController: your own arms in first person, with the gloves and the held item.
	Roblox hides the whole body there; after its camera step this shows the arms again and
	turns the arm that holds something with the camera, so the item stays in view.
	Local only: nothing is sent and other players see nothing of it.
]]

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local FirstPersonController = {}

local localPlayer = Players.LocalPlayer
local FIRST_PERSON = 1.2 -- studs between camera and its subject
local ARMS = {
	"RightUpperArm", "RightLowerArm", "RightHand", "LeftUpperArm", "LeftLowerArm", "LeftHand", -- R15
	"Right Arm", "Left Arm", -- R6
}
local PITCH_LIMIT = math.rad(60)
local LOWER = math.rad(14) -- the arm stays a little below the view

local showing = false
local holding = false
local lastJoint: Instance? = nil
local lastSet = CFrame.new()

-- The arm with the item follows the camera up and down: on top of the animation, which writes
-- Transform anew every frame (Motor6D or AnimationConstraint, whichever the avatar has).
local function aimArm()
	local camera = Workspace.CurrentCamera
	local character = localPlayer.Character
	local upper = if character ~= nil then character:FindFirstChild("RightUpperArm") else nil
	local joint: any = if upper ~= nil then upper:FindFirstChild("RightShoulder") else nil
	if not showing or not holding or camera == nil or joint == nil or not (joint:IsA("Motor6D") or joint:IsA("AnimationConstraint")) then
		lastJoint = nil
		return
	end
	if joint == lastJoint and joint.Transform == lastSet then
		return -- the animation did not move it: never turn it twice
	end
	local pitch = math.clamp(math.asin(math.clamp(camera.CFrame.LookVector.Y, -1, 1)), -PITCH_LIMIT, PITCH_LIMIT)
	joint.Transform = CFrame.Angles(pitch - LOWER, 0, 0) * joint.Transform
	lastJoint, lastSet = joint, joint.Transform
end

local function step()
	local camera = Workspace.CurrentCamera
	local character = localPlayer.Character
	local humanoid = if character ~= nil then character:FindFirstChildOfClass("Humanoid") else nil
	local first = camera ~= nil and character ~= nil and humanoid ~= nil and humanoid.Health > 0
		and camera.CameraType == Enum.CameraType.Custom
		and (camera.CFrame.Position - camera.Focus.Position).Magnitude < FIRST_PERSON
	if not first then
		showing = false -- the transparency goes back to Roblox's own camera script
		return
	end
	showing = true
	local body = character :: Model
	for _, name in ARMS do
		local part = body:FindFirstChild(name)
		if part ~= nil and part:IsA("BasePart") then
			part.LocalTransparencyModifier = 0
		end
	end
	-- Things welded to a hand: the held item and the gloves (CarryController).
	local right, left = 0, 0
	local visuals = body:FindFirstChild("CarryVisuals")
	if visuals ~= nil then
		for _, model in visuals:GetChildren() do
			local weld = model:FindFirstChildWhichIsA("WeldConstraint", true)
			local root = model:FindFirstChild("Root")
			if root ~= nil then
				weld = nil
				for _, child in root:GetChildren() do
					if child:IsA("WeldConstraint") and child.Part0 ~= nil and child.Part0.Parent == body then
						weld = child
					end
				end
			end
			local to = if weld ~= nil then weld.Part0 else nil
			if to ~= nil and table.find(ARMS, to.Name) ~= nil then
				if string.sub(to.Name, 1, 5) == "Right" then
					right += 1
				else
					left += 1
				end
				for _, part in model:GetDescendants() do
					if part:IsA("BasePart") then
						part.LocalTransparencyModifier = 0
					end
				end
			end
		end
	end
	holding = right > left -- gloves are on both hands, an item only in the right one
end

function FirstPersonController.Start()
	RunService:BindToRenderStep("JunkshotFirstPerson", Enum.RenderPriority.Camera.Value + 5, step)
	RunService.PreSimulation:Connect(aimArm) -- after the animations of this frame
end

return FirstPersonController
