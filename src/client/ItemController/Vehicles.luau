--!strict
--[[
	Vehicles (client): everything the client does for vehicles. The server drives them
	(Services/Behaviors/Vehicle); this only sends input and makes them look alive.

	  - In the driver seat: Roblox's own control scripts write the VehicleSeat's ThrottleFloat
	    / SteerFloat from WASD / arrows, the gamepad stick or the touch thumbstick. This module
	    forwards those two numbers to the server (VehicleInput) when they change, and at least
	    every RESEND seconds while driving so the server knows the driver is still there.
	  - Seated in any vehicle: throwing is blocked and a small HUD shows the speed and an EXIT
	    button (Jump also exits).
	  - Every nearby vehicle: wheels (and bicycle pedals) spin with its speed, and the engine
	    sound's pitch follows the speed. Purely local and cosmetic.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Remotes = require(ReplicatedStorage.Shared.Remotes)
local PlacementRules = require(ReplicatedStorage.Shared.Util.PlacementRules)

local InputController = require(script.Parent.Parent.InputController)
local Theme = require(script.Parent.Parent.UI.Theme)

local Vehicles = {}

local SEND_INTERVAL = 1 / 12 -- seconds between input packets at most
local RESEND = 0.4 -- seconds: resend unchanged input this often while driving
local ANIMATE_DISTANCE = 220 -- studs from the camera within which vehicles are animated

type Spinner = { Weld: Weld, BaseC0: CFrame, Radius: number }
type View = { Model: Model, Spinners: { Spinner }, Angle: number }

local localPlayer = Players.LocalPlayer
local views: { [Model]: View } = {}
local seat: BasePart? = nil
local isDriver = false
local lastSent = { Throttle = 0, Steer = 0, At = 0 }
local hud: Frame? = nil
local speedLabel: TextLabel? = nil
local switchButton: TextButton? = nil
local switchLabel: TextLabel? = nil
local onChanged: (() -> ())? = nil

local function vehicleModelOf(part: Instance?): Model?
	local deployed = Workspace:FindFirstChild(PlacementRules.DEPLOYED_FOLDER)
	if part == nil or deployed == nil then
		return nil
	end
	local current: Instance? = part
	while current ~= nil and current.Parent ~= deployed do
		current = current.Parent
	end
	if current ~= nil and current:IsA("Model") and current:GetAttribute("BehaviorKind") == "Vehicle" then
		return current
	end
	return nil
end

local function viewOf(model: Model): View
	local view = views[model]
	if view ~= nil then
		return view
	end
	local spinners: { Spinner } = {}
	for _, weld in model:GetDescendants() do
		if weld:IsA("Weld") and weld.Name == "SpinWeld" and weld.Part1 ~= nil then
			local radius = weld.Part1:GetAttribute("Spin")
			if type(radius) == "number" and radius > 0 then
				table.insert(spinners, { Weld = weld, BaseC0 = weld.C0, Radius = radius })
			end
		end
	end
	view = { Model = model, Spinners = spinners, Angle = 0 }
	views[model] = view
	model.AncestryChanged:Connect(function()
		if not model:IsDescendantOf(Workspace) then
			views[model] = nil
		end
	end)
	return view
end

local function animate(dt: number)
	local deployed = Workspace:FindFirstChild(PlacementRules.DEPLOYED_FOLDER)
	local camera = Workspace.CurrentCamera
	if deployed == nil or camera == nil then
		return
	end
	local cameraPosition = camera.CFrame.Position
	for _, model in deployed:GetChildren() do
		if model:IsA("Model") and model:GetAttribute("BehaviorKind") == "Vehicle" then
			local base = model.PrimaryPart
			if base ~= nil and (base.Position - cameraPosition).Magnitude <= ANIMATE_DISTANCE then
				local view = viewOf(model)
				if #view.Spinners == 0 and model:FindFirstChild("SpinWeld", true) ~= nil then
					views[model] = nil -- welds replicated after the first look: rebuild
					view = viewOf(model)
				end
				local speed = base.AssemblyLinearVelocity:Dot(base.CFrame.LookVector)
				view.Angle += speed * dt
				for _, spinner in view.Spinners do
					spinner.Weld.C0 = spinner.BaseC0 * CFrame.Angles(-view.Angle / spinner.Radius, 0, 0)
				end
				local engine = base:FindFirstChild("Engine")
				if engine ~= nil and engine:IsA("Sound") then
					local maxSpeed = model:GetAttribute("MaxSpeed")
					local ratio = if type(maxSpeed) == "number" and maxSpeed > 0 then math.abs(speed) / maxSpeed else 0
					local rolling = model:GetAttribute("EngineRolling")
					if type(rolling) == "number" then
						engine.Volume = rolling * math.clamp(ratio * 2.5, 0, 1)
					end
					engine.PlaybackSpeed = (0.75 + ratio * 0.8) * (model:GetAttribute("EnginePitch") or 1)
				end
			end
		end
	end
end

local function sendInput()
	if not isDriver or seat == nil or not seat:IsA("VehicleSeat") then
		return
	end
	local vehicleSeat = seat :: VehicleSeat
	local throttle = math.clamp(vehicleSeat.ThrottleFloat, -1, 1)
	local steer = math.clamp(vehicleSeat.SteerFloat, -1, 1)
	local now = os.clock()
	local changed = math.abs(throttle - lastSent.Throttle) > 0.05 or math.abs(steer - lastSent.Steer) > 0.05
	if now - lastSent.At < SEND_INTERVAL or (not changed and now - lastSent.At < RESEND) then
		return
	end
	lastSent.Throttle, lastSent.Steer, lastSent.At = throttle, steer, now
	Remotes.GetEvent("VehicleInput"):FireServer(throttle, steer)
end

local function updateHud()
	if hud == nil then
		return
	end
	hud.Visible = seat ~= nil
	if seat ~= nil and speedLabel ~= nil then
		local speed = seat.AssemblyLinearVelocity.Magnitude
		speedLabel.Text = string.format("%d", math.floor(speed + 0.5))
		local model = vehicleModelOf(seat)
		local other = if model ~= nil then model:FindFirstChild(if isDriver then "PassengerSeat" else "DriverSeat") else nil
		local free = other ~= nil and (other:IsA("Seat") or other:IsA("VehicleSeat")) and other.Occupant == nil
		local mine = model ~= nil and model:GetAttribute("OwnerUserId") == localPlayer.UserId
		if switchButton ~= nil and switchLabel ~= nil then
			switchButton.Visible = free and (isDriver or mine)
			switchLabel.Text = if isDriver then "PASSENGER SEAT" else "DRIVE"
			hud.Size = UDim2.new(0, if switchButton.Visible then 340 else 210, 0, 64)
		end
	end
end

local function onSeatChanged(humanoid: Humanoid)
	local part = humanoid.SeatPart
	local model = vehicleModelOf(part)
	if model ~= nil and part ~= nil then
		seat = part
		isDriver = part:IsA("VehicleSeat")
		lastSent.At = 0
		InputController.SetThrowBlocked("Vehicle", true)
	else
		if isDriver then
			Remotes.GetEvent("VehicleInput"):FireServer(0, 0)
		end
		seat = nil
		isDriver = false
		InputController.SetThrowBlocked("Vehicle", false)
	end
	updateHud()
	if onChanged ~= nil then
		onChanged()
	end
end

local function hookCharacter(character: Model)
	local humanoid = character:WaitForChild("Humanoid", 10)
	if humanoid == nil or not humanoid:IsA("Humanoid") then
		return
	end
	humanoid:GetPropertyChangedSignal("SeatPart"):Connect(function()
		onSeatChanged(humanoid)
	end)
	onSeatChanged(humanoid)
end

function Vehicles.IsSeated(): boolean
	return seat ~= nil
end

function Vehicles.Exit()
	local character = localPlayer.Character
	local humanoid = if character ~= nil then character:FindFirstChildOfClass("Humanoid") else nil
	if humanoid ~= nil and humanoid.SeatPart ~= nil then
		-- Roblox's control script resets Humanoid.Jump every frame, so leave the seat directly.
		humanoid.Sit = false
		humanoid:ChangeState(Enum.HumanoidStateType.Jumping)
	end
end

function Vehicles.Mount(screenGui: ScreenGui, changed: () -> ())
	onChanged = changed

	local frame = Instance.new("Frame")
	frame.Name = "DriveHud"
	frame.AnchorPoint = Vector2.new(0.5, 0)
	frame.Position = UDim2.new(0.5, 0, 0, 8)
	frame.Size = UDim2.new(0, 300, 0, 64)
	frame.BackgroundColor3 = Theme.Colors.Panel
	frame.Visible = false
	Theme.Corner(frame, UDim.new(0, 16))
	Theme.Stroke(frame, Theme.Colors.Ink, 3)
	frame.Parent = screenGui

	speedLabel = Theme.Label({
		Name = "Speed",
		Text = "0",
		Size = UDim2.new(0, 70, 0, 40),
		Position = UDim2.new(0, 10, 0, 4),
		MinTextSize = 18,
		MaxTextSize = 34,
		Parent = frame,
	})
	Theme.Label({
		Name = "Unit",
		Text = "studs/s",
		Size = UDim2.new(0, 70, 0, 16),
		Position = UDim2.new(0, 10, 0, 44),
		Font = Theme.FontBody,
		Color = Theme.Colors.InkSoft,
		MinTextSize = 10,
		MaxTextSize = 12,
		Parent = frame,
	})
	local exit = Instance.new("TextButton")
	exit.Name = "Exit"
	exit.AnchorPoint = Vector2.new(1, 0.5)
	exit.Position = UDim2.new(1, -10, 0.5, 0)
	exit.Size = UDim2.new(0, 90, 0, 46)
	exit.BackgroundColor3 = Theme.Colors.Danger
	exit.Text = ""
	Theme.Corner(exit, UDim.new(0, 12))
	Theme.Stroke(exit, Theme.Colors.Ink, 2.5)
	local exitLabel = Theme.Label({
		Name = "Label",
		Text = "EXIT",
		Size = UDim2.fromScale(0.85, 0.7),
		Position = UDim2.fromScale(0.5, 0.5),
		AnchorPoint = Vector2.new(0.5, 0.5),
		Color = Theme.Colors.White,
		MinTextSize = 14,
		MaxTextSize = 24,
		Parent = exit,
	})
	Theme.TextStroke(exitLabel, Theme.Colors.Ink, 1.5)
	exit.Parent = frame

	local switch = Instance.new("TextButton")
	switch.Name = "Switch"
	switch.AnchorPoint = Vector2.new(1, 0.5)
	switch.Position = UDim2.new(1, -108, 0.5, 0)
	switch.Size = UDim2.new(0, 132, 0, 46)
	switch.BackgroundColor3 = Theme.Colors.Ice
	switch.Text = ""
	switch.Visible = false
	Theme.Corner(switch, UDim.new(0, 12))
	Theme.Stroke(switch, Theme.Colors.Ink, 2.5)
	switchLabel = Theme.Label({
		Name = "Label",
		Text = "",
		Size = UDim2.fromScale(0.88, 0.7),
		Position = UDim2.fromScale(0.5, 0.5),
		AnchorPoint = Vector2.new(0.5, 0.5),
		Color = Theme.Colors.White,
		MinTextSize = 11,
		MaxTextSize = 18,
		Parent = switch,
	})
	Theme.TextStroke(switchLabel :: TextLabel, Theme.Colors.Ink, 1.5)
	switch.Parent = frame
	switch.Activated:Connect(function()
		Remotes.GetEvent("VehicleSwitch"):FireServer()
	end)
	switchButton = switch
	exit.Activated:Connect(Vehicles.Exit)
	hud = frame

	localPlayer.CharacterAdded:Connect(function(character: Model)
		task.spawn(hookCharacter, character)
	end)
	if localPlayer.Character ~= nil then
		task.spawn(hookCharacter, localPlayer.Character)
	end

	local hudTimer = 0
	RunService.Heartbeat:Connect(function(dt: number)
		sendInput()
		hudTimer += dt
		if seat ~= nil and hudTimer >= 0.1 then
			hudTimer = 0
			updateHud()
		end
	end)
	RunService.RenderStepped:Connect(animate)
end

return Vehicles
