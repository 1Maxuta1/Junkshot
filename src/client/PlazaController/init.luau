--!strict
--[[
	PlazaController: turns the plaza gears (parts tagged PlazaSpin, built by tools/map/Plaza).
	Local only, only close to the camera, off with Lite graphics.
]]

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local PlazaController = {}

local RANGE = 130
local localPlayer = Players.LocalPlayer

local function rotate(part: Instance, dt: number, eye: Vector3)
	local speed, center, axis = part:GetAttribute("Speed"), part:GetAttribute("Center"), part:GetAttribute("Axis")
	if not part:IsA("BasePart") or type(speed) ~= "number" or typeof(center) ~= "Vector3" or typeof(axis) ~= "Vector3"
		or (center - eye).Magnitude > RANGE
	then
		return
	end
	part.CFrame = CFrame.new(center) * CFrame.fromAxisAngle(axis, speed * dt) * CFrame.new(-center) * part.CFrame
end

function PlazaController.Start()
	RunService.RenderStepped:Connect(function(dt: number)
		local camera = Workspace.CurrentCamera
		if camera == nil or localPlayer:GetAttribute("LiteGraphics") == true then
			return
		end
		for _, part in CollectionService:GetTagged("PlazaSpin") do
			rotate(part, dt, camera.CFrame.Position)
		end
	end)
end

return PlazaController
