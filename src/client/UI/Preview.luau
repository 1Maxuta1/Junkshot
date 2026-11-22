--!strict
--[[
	Preview: fills a ViewportFrame with a small 3D view of a junk type or a reward item.
	Built once per call (static content costs nothing to keep on screen).

	  Preview.Junk(viewport, junkId)
	  Preview.Item(viewport, itemId)
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local JunkFactory = require(ReplicatedStorage.Shared.Util.JunkFactory)

local PREVIEW_SIZE = 2 -- studs, largest dimension inside the preview
local CAMERA_DIRECTION = Vector3.new(1, 0.75, 1).Unit
local CAMERA_DISTANCE = 3.8

local Preview = {}

local function show(viewport: ViewportFrame, model: Model?)
	viewport:ClearAllChildren()
	if model == nil then
		return
	end
	model:PivotTo(CFrame.Angles(0, math.rad(-25), 0))
	model.Parent = viewport

	local center = model:GetBoundingBox().Position
	local camera = Instance.new("Camera")
	camera.FieldOfView = 40
	camera.CFrame = CFrame.lookAt(center + CAMERA_DIRECTION * CAMERA_DISTANCE, center)
	camera.Parent = viewport
	viewport.CurrentCamera = camera
end

function Preview.Junk(viewport: ViewportFrame, junkId: string)
	show(viewport, JunkFactory.Build(junkId, "Cosmetic", PREVIEW_SIZE))
end

function Preview.Item(viewport: ViewportFrame, itemId: string)
	show(viewport, JunkFactory.Build(itemId, "Cosmetic", PREVIEW_SIZE))
end

-- Default lighting for preview frames, so every preview looks the same.
function Preview.StyleViewport(viewport: ViewportFrame)
	viewport.BackgroundTransparency = 1
	viewport.Ambient = Color3.fromRGB(190, 200, 215)
	viewport.LightColor = Color3.fromRGB(255, 250, 240)
	viewport.LightDirection = Vector3.new(-1, -2, -1)
end

return Preview
