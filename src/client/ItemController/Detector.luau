--!strict
--[[
	Detector (client): the Metal Detector while it is selected in the hotbar and switched on.

	  - Every ScanInterval seconds it asks the server for a scan (ItemUse(uid)); the server
	    validates and answers on ItemFx (Services/Behaviors/Detector).
	  - A small panel shows the signal: rarity, distance and an arrow pointing at it.
	  - It beeps; the closer the find, the faster. Up close the find glows in its rarity colour.
	Switching to another hotbar slot turns it off.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local SoundService = game:GetService("SoundService")
local Workspace = game:GetService("Workspace")

local GameConfig = require(ReplicatedStorage.Shared.Config.GameConfig)
local Rarities = require(ReplicatedStorage.Shared.Config.Rarities)
local Remotes = require(ReplicatedStorage.Shared.Remotes)

local Theme = require(script.Parent.Parent.UI.Theme)

local Detector = {}

local BEEP_SOUND = "rbxasset://sounds/electronicpingshort.wav" -- ships with every Roblox client
local MIN_BEEP = 0.15 -- seconds between beeps right on top of it
local MAX_BEEP = 1.4 -- seconds between beeps at the edge of the range

local localPlayer = Players.LocalPlayer

local on = false
local uid: string? = nil
local config: any = nil
local last: any = nil -- last scan result
local scanTimer = 0
local beepTimer = 0
local panel: Frame? = nil
local statusLabel: TextLabel? = nil
local arrow: TextLabel? = nil
local beep: Sound? = nil
local highlight: Highlight? = nil
local onChanged: (() -> ())? = nil

local function clearHighlight()
	if highlight ~= nil then
		highlight:Destroy()
		highlight = nil
	end
end

local function findWorldItem(targetUid: string): Model?
	local container = Workspace:FindFirstChild(GameConfig.Junk.ContainerName)
	if container == nil then
		return nil
	end
	for _, child in container:GetChildren() do
		if child:GetAttribute("JunkUid") == targetUid and child:IsA("Model") then
			return child
		end
	end
	return nil
end

local function render()
	if panel == nil or statusLabel == nil or arrow == nil then
		return
	end
	panel.Visible = on
	if not on then
		return
	end
	if last == nil then
		statusLabel.Text = "Scanning..."
		statusLabel.TextColor3 = Theme.Colors.InkSoft
		arrow.Visible = false
		return
	end
	if not last.Found then
		statusLabel.Text = `Nothing valuable within {config.Range} studs`
		statusLabel.TextColor3 = Theme.Colors.InkSoft
		arrow.Visible = false
		return
	end
	local character = localPlayer.Character
	local root = if character ~= nil then character:FindFirstChild("HumanoidRootPart") else nil
	local distance = last.Distance
	if root ~= nil and root:IsA("BasePart") and last.Position ~= nil then
		distance = (last.Position - root.Position).Magnitude
	end
	statusLabel.Text = string.format("%s signal  ·  %d studs", last.Rarity, math.floor(distance + 0.5))
	statusLabel.TextColor3 = Rarities.GetColor(last.Rarity)
	local camera = Workspace.CurrentCamera
	if camera ~= nil and root ~= nil and root:IsA("BasePart") and last.Position ~= nil then
		local look = camera.CFrame.LookVector
		local toTarget = last.Position - root.Position
		local a = math.atan2(look.X, look.Z)
		local b = math.atan2(toTarget.X, toTarget.Z)
		arrow.Rotation = math.deg(a - b)
		arrow.Visible = true
	end
end

local function onResult(result: any)
	if type(result) ~= "table" or result.Kind ~= "Detector" or not on or result.Uid ~= uid then
		return
	end
	last = result
	clearHighlight()
	if result.Found and type(result.TargetUid) == "string" and type(result.Distance) == "number"
		and result.Distance <= config.HighlightDistance
	then
		local model = findWorldItem(result.TargetUid)
		if model ~= nil then
			local glow = Instance.new("Highlight")
			glow.Name = "DetectorGlow"
			glow.FillColor = Rarities.GetColor(result.Rarity)
			glow.OutlineColor = Rarities.GetColor(result.Rarity)
			glow.FillTransparency = 0.4
			glow.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
			glow.Adornee = model
			glow.Parent = Workspace.CurrentCamera
			highlight = glow
		end
	end
	render()
end

function Detector.IsOn(): boolean
	return on
end

function Detector.SetOn(value: boolean, detectorUid: string?, behavior: any?)
	if value and (detectorUid == nil or behavior == nil) then
		value = false
	end
	if value == on and detectorUid == uid then
		return
	end
	on = value
	uid = if value then detectorUid else nil
	config = if value and behavior ~= nil then behavior.Detector else nil
	last = nil
	scanTimer = math.huge -- scan right away
	beepTimer = 0
	clearHighlight()
	render()
	if onChanged ~= nil then
		onChanged()
	end
end

function Detector.Mount(screenGui: ScreenGui, changed: () -> ())
	onChanged = changed

	local frame = Instance.new("Frame")
	frame.Name = "DetectorPanel"
	frame.AnchorPoint = Vector2.new(0.5, 0)
	frame.Position = UDim2.new(0.5, 0, 0, 8)
	frame.Size = UDim2.new(0, 320, 0, 56)
	frame.BackgroundColor3 = Theme.Colors.Panel
	frame.Visible = false
	Theme.Corner(frame, UDim.new(0, 16))
	Theme.Stroke(frame, Theme.Colors.Ink, 3)
	frame.Parent = screenGui

	local arrowLabel = Theme.Label({
		Name = "Arrow",
		Text = "▲",
		Size = UDim2.new(0, 40, 0, 40),
		Position = UDim2.new(0, 10, 0.5, 0),
		AnchorPoint = Vector2.new(0, 0.5),
		Color = Theme.Colors.Accent,
		MinTextSize = 20,
		MaxTextSize = 34,
		Parent = frame,
	})
	Theme.Label({
		Name = "Title",
		Text = "METAL DETECTOR",
		Size = UDim2.new(1, -70, 0, 18),
		Position = UDim2.new(0, 60, 0, 6),
		Font = Theme.Font,
		MinTextSize = 11,
		MaxTextSize = 15,
		XAlignment = Enum.TextXAlignment.Left,
		Parent = frame,
	})
	statusLabel = Theme.Label({
		Name = "Status",
		Text = "",
		Size = UDim2.new(1, -70, 0, 24),
		Position = UDim2.new(0, 60, 0, 26),
		Font = Theme.FontBody,
		MinTextSize = 11,
		MaxTextSize = 16,
		XAlignment = Enum.TextXAlignment.Left,
		Parent = frame,
	})
	arrow = arrowLabel
	panel = frame

	local sound = Instance.new("Sound")
	sound.Name = "DetectorBeep"
	sound.SoundId = BEEP_SOUND
	sound.Volume = 0.5
	sound.Parent = SoundService
	beep = sound

	Remotes.GetEvent("ItemFx").OnClientEvent:Connect(onResult)

	RunService.Heartbeat:Connect(function(dt: number)
		if not on or uid == nil or config == nil then
			return
		end
		scanTimer += dt
		if scanTimer >= config.ScanInterval then
			scanTimer = 0
			Remotes.GetEvent("ItemUse"):FireServer(uid)
		end
		if last ~= nil and last.Found and type(last.Distance) == "number" then
			beepTimer += dt
			local ratio = math.clamp(last.Distance / config.Range, 0, 1)
			if beepTimer >= MIN_BEEP + (MAX_BEEP - MIN_BEEP) * ratio then
				beepTimer = 0
				if beep ~= nil then
					beep.PlaybackSpeed = 1.6 - ratio * 0.6
					SoundService:PlayLocalSound(beep)
				end
			end
		end
		render()
	end)
end

return Detector
