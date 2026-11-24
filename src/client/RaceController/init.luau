--!strict
--[[
	RaceController: what a player sees of the hourly race (server: RaceService). Display only.

	  Open       "Race in 1:32 ..." for everyone
	  Countdown  3 - 2 - 1 - GO!, the start lights on the arch turn on one by one
	  Racing     lap, place and time for racers, plus an arrow over the next checkpoint
]]

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")

local Theme = require(script.Parent.UI.Theme)

local RaceController = {}

local localPlayer = Players.LocalPlayer
local LIGHT_OFF = Color3.fromRGB(90, 30, 34)
local LIGHT_RED = Color3.fromRGB(255, 60, 50)
local LIGHT_GREEN = Color3.fromRGB(70, 230, 110)

local function clock(seconds: number): string
	local left = math.max(0, math.ceil(seconds))
	return string.format("%d:%02d", left // 60, left % 60)
end

local function setLights(count: number, color: Color3)
	for _, lamp in CollectionService:GetTagged("RaceStartLight") do
		if lamp:IsA("BasePart") then
			local on = (lamp:GetAttribute("Order") or 0) <= count
			lamp.Color = if on then color else LIGHT_OFF
			lamp.Material = if on then Enum.Material.Neon else Enum.Material.SmoothPlastic
		end
	end
end

local function mount()
	local gui = Instance.new("ScreenGui")
	gui.Name = "JunkshotRace"
	gui.ResetOnSpawn = false
	gui.ScreenInsets = Enum.ScreenInsets.CoreUISafeInsets
	gui.DisplayOrder = 5

	local bar = Instance.new("Frame")
	bar.Name = "Bar"
	bar.AnchorPoint = Vector2.new(0.5, 0)
	bar.Position = UDim2.new(0.5, 0, 0, 78) -- under the drive HUD
	bar.Size = UDim2.new(0.5, 0, 0, 32)
	bar.BackgroundColor3 = Theme.Colors.Ink
	bar.BackgroundTransparency = 0.15
	bar.Visible = false
	Theme.Corner(bar, UDim.new(0, 12))
	local limit = Instance.new("UISizeConstraint")
	limit.MaxSize = Vector2.new(460, 34)
	limit.Parent = bar
	bar.Parent = gui
	local label = Theme.Label({
		Name = "Text",
		Text = "",
		Size = UDim2.new(1, -16, 0.8, 0),
		Position = UDim2.fromScale(0.5, 0.5),
		AnchorPoint = Vector2.new(0.5, 0.5),
		Color = Theme.Colors.White,
		MinTextSize = 10,
		MaxTextSize = 20,
		Parent = bar,
	})
	local big = Theme.Label({
		Name = "Countdown",
		Text = "",
		Size = UDim2.fromScale(0.4, 0.26),
		Position = UDim2.fromScale(0.5, 0.36),
		AnchorPoint = Vector2.new(0.5, 0.5),
		Color = Theme.Colors.Sun,
		MinTextSize = 30,
		MaxTextSize = 120,
		Parent = gui,
	})
	Theme.TextStroke(big, Theme.Colors.Ink, 4)

	local arrow = Instance.new("BillboardGui")
	arrow.Name = "NextCheckpoint"
	arrow.Size = UDim2.fromOffset(60, 60)
	arrow.StudsOffsetWorldSpace = Vector3.new(0, 6, 0)
	arrow.AlwaysOnTop = true
	arrow.LightInfluence = 0
	arrow.Enabled = false
	arrow.ResetOnSpawn = false
	local arrowLabel = Theme.Label({
		Name = "Arrow",
		Text = "▼",
		Size = UDim2.fromScale(1, 1),
		Color = Theme.Colors.Sun,
		MinTextSize = 20,
		MaxTextSize = 60,
		Parent = arrow,
	})
	Theme.TextStroke(arrowLabel, Theme.Colors.Ink, 3)
	local playerGui = localPlayer:WaitForChild("PlayerGui")
	arrow.Parent = playerGui
	gui.Parent = playerGui

	local function showArrow()
		local nextIndex = localPlayer:GetAttribute("RaceNext")
		arrow.Enabled = false
		if type(nextIndex) ~= "number" then
			return
		end
		for _, part in CollectionService:GetTagged("RaceCheckpoint") do
			if part:GetAttribute("Index") == nextIndex then
				arrow.Adornee = part
				arrow.Enabled = true
			end
		end
	end
	localPlayer:GetAttributeChangedSignal("RaceNext"):Connect(showArrow)

	while true do
		local state = Workspace:GetAttribute("RaceState")
		local now = Workspace:GetServerTimeNow()
		local racing = type(localPlayer:GetAttribute("RaceLap")) == "number"
		local goAt = Workspace:GetAttribute("RaceGoAt")
		local startsAt = Workspace:GetAttribute("RaceStartsAt")
		big.Text = ""
		if state == "Open" and type(startsAt) == "number" then
			bar.Visible = true
			local you = if localPlayer:GetAttribute("RaceJoined") == true then "you are in!" else "join at the Raceway"
			label.Text = `🏁 Race in {clock(startsAt - now)}  ·  {Workspace:GetAttribute("RaceRacers") or 0}/8  ·  {you}`
		elseif (state == "Countdown" or state == "Racing") and type(goAt) == "number" then
			local left = goAt - now
			bar.Visible = racing
			if state == "Countdown" and left > 0 then
				setLights(math.clamp(4 - math.ceil(left), 0, 3), LIGHT_RED)
				if racing then
					label.Text = "Get ready!"
					big.Text = if left <= 3 then tostring(math.ceil(left)) else ""
				end
			else
				setLights(3, LIGHT_GREEN)
				if racing then
					big.Text = if left > -1 then "GO!" else ""
					local laps = Workspace:GetAttribute("RaceLaps") or 1
					label.Text = string.format("LAP %d/%d  ·  PLACE %d  ·  %.1f s", localPlayer:GetAttribute("RaceLap") :: number,
						laps, localPlayer:GetAttribute("RacePlace") or 1, math.max(0, -left))
				end
			end
		else
			bar.Visible = state == "Results" and racing
			if bar.Visible then
				label.Text = `🏁 You finished in place {localPlayer:GetAttribute("RacePlace") or "-"}`
			end
			setLights(0, LIGHT_OFF)
		end
		task.wait(0.1)
	end
end

function RaceController.Start()
	task.spawn(mount)
end

return RaceController
