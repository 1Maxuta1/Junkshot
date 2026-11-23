--!strict
--[[
	WeatherController: a light snowfall around the local camera (Config/WorldConfig.Snow).
	One invisible anchored part above the camera with one ParticleEmitter, moved once per frame;
	other players never see this client's flakes (no replication, no physics).
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local WorldConfig = require(ReplicatedStorage.Shared.Config.WorldConfig)

local WeatherController = {}

function WeatherController.Start()
	local config = WorldConfig.Snow
	if not config.Enabled then
		return
	end
	local cloud = Instance.new("Part")
	cloud.Name = "SnowCloud"
	cloud.Anchored = true
	cloud.CanCollide = false
	cloud.CanQuery = false
	cloud.CanTouch = false
	cloud.CastShadow = false
	cloud.Transparency = 1
	cloud.Size = Vector3.new(config.Area, 1, config.Area)

	local emitter = Instance.new("ParticleEmitter")
	emitter.Texture = config.Texture
	emitter.Rate = config.Rate
	emitter.Lifetime = NumberRange.new(7, 10)
	emitter.Speed = NumberRange.new(4, 7)
	emitter.EmissionDirection = Enum.NormalId.Bottom
	emitter.SpreadAngle = Vector2.new(15, 15)
	emitter.Acceleration = Vector3.new(1.5, -1, 0.5)
	emitter.Size = NumberSequence.new(0.18, 0.3)
	emitter.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 1),
		NumberSequenceKeypoint.new(0.1, 0.15),
		NumberSequenceKeypoint.new(0.85, 0.2),
		NumberSequenceKeypoint.new(1, 1),
	})
	emitter.Rotation = NumberRange.new(0, 360)
	emitter.RotSpeed = NumberRange.new(-40, 40)
	emitter.LightEmission = 0.4
	emitter.Color = ColorSequence.new(Color3.fromRGB(255, 255, 255))
	emitter.Shape = Enum.ParticleEmitterShape.Box
	emitter.ShapeStyle = Enum.ParticleEmitterShapeStyle.Volume
	emitter.Parent = cloud
	cloud.Parent = Workspace.CurrentCamera

	RunService.RenderStepped:Connect(function()
		local camera = Workspace.CurrentCamera
		if camera ~= nil then
			if cloud.Parent ~= camera then
				cloud.Parent = camera
			end
			cloud.CFrame = CFrame.new(camera.CFrame.Position + Vector3.new(0, config.Height, 0))
		end
	end)
end

return WeatherController
