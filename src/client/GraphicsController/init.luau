--!strict
--[[
	GraphicsController: "Lite graphics" for weak devices (setting in the SOUND window, saved).

	  Auto  (default) a touch device that runs below AUTO_FPS after joining switches to Lite
	  Lite  no shadows, clouds, sun rays or bloom; less snow; gadget effects only close by
	  Full  everything

	The result is the local attribute LiteGraphics on the player (WeatherController and
	GadgetController read it). Only this client's picture changes.
]]

local Lighting = game:GetService("Lighting")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local AudioController = require(script.Parent.AudioController)
local NotifyController = require(script.Parent.NotifyController)

local GraphicsController = {}

local AUTO_FPS = 40
local SETTLE_SECONDS = 12 -- loading the map is always slow
local MEASURE_SECONDS = 8

local localPlayer = Players.LocalPlayer
local autoLite = false
local originals: { [Instance]: boolean } = {}
local shadows: boolean? = nil

local function setEnabled(instance: Instance?, lite: boolean)
	if instance == nil then
		return
	end
	local target = instance :: any
	if lite then
		if originals[instance] == nil then
			originals[instance] = target.Enabled
		end
		target.Enabled = false
	elseif originals[instance] ~= nil then
		target.Enabled = originals[instance]
		originals[instance] = nil
	end
end

local function apply()
	local choice = AudioController.GetGraphics()
	local lite = choice == "Lite" or (choice == "Auto" and autoLite)
	if localPlayer:GetAttribute("LiteGraphics") == lite then
		return
	end
	localPlayer:SetAttribute("LiteGraphics", lite)
	if shadows == nil then
		shadows = Lighting.GlobalShadows
	end
	Lighting.GlobalShadows = if lite then false else shadows :: boolean
	for _, child in Lighting:GetChildren() do
		if child:IsA("PostEffect") and not child:IsA("ColorCorrectionEffect") then
			setEnabled(child, lite)
		end
	end
	setEnabled(Workspace.Terrain:FindFirstChildOfClass("Clouds"), lite)
end

local function measure()
	task.wait(SETTLE_SECONDS)
	local frames, started = 0, os.clock()
	while os.clock() - started < MEASURE_SECONDS do
		RunService.Heartbeat:Wait()
		frames += 1
	end
	local fps = frames / (os.clock() - started)
	if fps < AUTO_FPS and AudioController.GetGraphics() == "Auto" then
		autoLite = true
		apply()
		NotifyController.Show("Lite graphics switched on (change it in SOUND)", "Info")
	end
end

function GraphicsController.Start()
	AudioController.GraphicsChanged:Connect(apply)
	apply()
	if UserInputService.TouchEnabled then
		task.spawn(measure)
	end
end

return GraphicsController
