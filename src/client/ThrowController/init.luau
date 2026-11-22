--!strict
--[[
	ThrowController: aiming, the aim preview and the throw request (local player), plus the
	flight visual of every throw the server reports (all players).

	Aiming
	  KeyboardMouse  the point under the mouse cursor.
	  Touch/Gamepad  the point at the center of the screen (turn the camera to aim).
	  While the throw input is held, a preview arc (one Beam) and a landing ring show where the
	  junk will land. They use the same Ballistics code as the server, so they match.
	  The per-frame update exists only while aiming.

	Request
	  ThrowRequest(uid, aimPoint). The server decides everything else (origin, speed, range,
	  cooldown, ownership); a rejected request simply changes nothing.

	Flights (one object per item, never a copy)
	  The server creates the thrown junk at its final pivot and sends ThrowFx just BEFORE the
	  object replicates. This module moves that same world object (found by its JunkUid) along
	  the arc locally and leaves it exactly at the server's FinalPivot. If the object arrives
	  later (streaming), the flight continues from the current time; if it never arrives,
	  nothing is drawn. One Heartbeat connection drives all flights and exists only while
	  something is flying. Client-side CFrame changes never replicate, and the server's
	  pivot is already final, so nothing has to be "corrected" afterwards.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

ReplicatedStorage:WaitForChild("Shared")
local GameConfig = require(ReplicatedStorage.Shared.Config.GameConfig)
local JunkConfig = require(ReplicatedStorage.Shared.Config.JunkConfig)
local Remotes = require(ReplicatedStorage.Shared.Remotes)
local Types = require(ReplicatedStorage.Shared.Types)
local Ballistics = require(ReplicatedStorage.Shared.Util.Ballistics)
local Validate = require(ReplicatedStorage.Shared.Util.Validate)

-- `script` is this folder's init module, so sibling controllers are children of script.Parent.
local CarryController = require(script.Parent.CarryController)
local InputController = require(script.Parent.InputController)
local NotifyController = require(script.Parent.NotifyController)

-- A throw the client knows about. Model is nil until the world object has replicated.
type Flight = {
	Fx: Types.ThrowFx,
	Model: Model?,
	Correction: Vector3, -- FinalPivot minus the arc's end point, blended in over the flight
	SpinAxis: Vector3,
	SpinTotal: number, -- radians, a whole number of turns so the flight ends unrotated
	StartedAt: number,
}

local VISUALS_FOLDER_NAME = "ThrowVisuals"
local PREVIEW_COLOR = Color3.fromRGB(255, 170, 40)
local PREVIEW_WIDTH = 0.35
local LANDING_RING_SIZE = 3.2
local SPIN_SPEED = 9 -- radians per second while flying
local PENDING_TIMEOUT = 1 -- seconds before an unanswered request no longer blocks the next one

local localPlayer = Players.LocalPlayer

local ThrowController = {}

local throwRemote: RemoteEvent? = nil
local visualsFolder: Folder? = nil
local junkContainer: Instance? = nil

local lastThrowAt = -math.huge
local pendingUid: string? = nil
local pendingAt = 0

-- Preview instances (created once, shown only while aiming).
local previewBeam: Beam? = nil
local previewAttachment0: Attachment? = nil
local previewAttachment1: Attachment? = nil
local previewRing: Part? = nil
local aimConnection: RBXScriptConnection? = nil

local flights: { [string]: Flight } = {}
local flightCount = 0
local flightConnection: RBXScriptConnection? = nil

---------------------------------------------------------------------------------------------
-- Shared helpers
---------------------------------------------------------------------------------------------

local function getLiveRoot(): BasePart?
	local character = localPlayer.Character
	if character == nil then
		return nil
	end
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if humanoid == nil or humanoid.Health <= 0 then
		return nil
	end
	local root = character:FindFirstChild("HumanoidRootPart")
	if root ~= nil and root:IsA("BasePart") then
		return root
	end
	return nil
end

-- Same filter as the server: the arc ignores characters and junk.
local function buildParams(): RaycastParams
	local excluded: { Instance } = {}
	if junkContainer ~= nil then
		table.insert(excluded, junkContainer)
	end
	if visualsFolder ~= nil then
		table.insert(excluded, visualsFolder)
	end
	for _, player in Players:GetPlayers() do
		if player.Character ~= nil then
			table.insert(excluded, player.Character)
		end
	end
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = excluded
	params.IgnoreWater = true
	params.RespectCanCollide = true
	return params
end

-- Mirrors ThrowService.getOrigin.
local function getOrigin(root: BasePart, params: RaycastParams): Vector3
	local throw = GameConfig.Throw
	local look = root.CFrame.LookVector
	local flatLook = Vector3.new(look.X, 0, look.Z)
	flatLook = if flatLook.Magnitude > 1e-3 then flatLook.Unit else Vector3.zero
	local raised = root.Position + Vector3.new(0, throw.OriginHeight, 0)
	local desired = raised + flatLook * throw.OriginForward
	if Workspace:Raycast(raised, desired - raised, params) ~= nil then
		return raised
	end
	return desired
end

local function getAimPoint(params: RaycastParams): Vector3?
	local camera = Workspace.CurrentCamera
	if camera == nil then
		return nil
	end
	local screenPoint: Vector2
	if InputController.GetInputKind() == "KeyboardMouse" then
		screenPoint = UserInputService:GetMouseLocation()
	else
		screenPoint = camera.ViewportSize / 2
	end
	local ray = camera:ViewportPointToRay(screenPoint.X, screenPoint.Y)
	local length = GameConfig.Input.AimRayLength
	local result = Workspace:Raycast(ray.Origin, ray.Direction * length, params)
	if result ~= nil then
		return result.Position
	end
	return ray.Origin + ray.Direction * length
end

---------------------------------------------------------------------------------------------
-- Aim preview
---------------------------------------------------------------------------------------------

-- Beam control points that trace a projectile exactly (cubic Bezier through the parabola).
local function beamForArc(gravity: Vector3, velocity: Vector3, origin: Vector3, t1: number): (number, number, CFrame, CFrame)
	local c = 0.125
	local p3 = 0.5 * gravity * t1 * t1 + velocity * t1 + origin
	local p2 = p3 - (gravity * t1 * t1 + velocity * t1) / 3
	local p1 = (c * gravity * t1 * t1 + 0.5 * velocity * t1 + origin - c * (origin + p3)) / (3 * c) - p2

	local curve0 = (p1 - origin).Magnitude
	local curve1 = (p2 - p3).Magnitude

	local b = (origin - p3).Unit
	local r1 = (p1 - origin).Unit
	local u1 = r1:Cross(b).Unit
	local r2 = (p2 - p3).Unit
	local u2 = r2:Cross(b).Unit
	b = u1:Cross(r1).Unit

	local cf1 = CFrame.fromMatrix(origin, r1, u1, b)
	local cf2 = CFrame.fromMatrix(p3, r2, u2, b)
	return curve0, -curve1, cf1, cf2
end

local function ensurePreview()
	if previewBeam ~= nil then
		return
	end
	local terrain = Workspace.Terrain
	local attachment0 = Instance.new("Attachment")
	attachment0.Name = "ThrowPreview0"
	attachment0.Parent = terrain
	local attachment1 = Instance.new("Attachment")
	attachment1.Name = "ThrowPreview1"
	attachment1.Parent = terrain

	local beam = Instance.new("Beam")
	beam.Name = "ThrowPreview"
	beam.Attachment0 = attachment0
	beam.Attachment1 = attachment1
	beam.Color = ColorSequence.new(PREVIEW_COLOR)
	beam.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.6),
		NumberSequenceKeypoint.new(0.3, 0.15),
		NumberSequenceKeypoint.new(1, 0.15),
	})
	beam.Width0 = PREVIEW_WIDTH
	beam.Width1 = PREVIEW_WIDTH
	beam.Segments = 24
	beam.FaceCamera = true
	beam.LightEmission = 0.6
	beam.Enabled = false
	beam.Parent = terrain

	local ring = Instance.new("Part")
	ring.Name = "ThrowLanding"
	ring.Shape = Enum.PartType.Cylinder
	ring.Size = Vector3.new(0.15, LANDING_RING_SIZE, LANDING_RING_SIZE)
	ring.Color = PREVIEW_COLOR
	ring.Material = Enum.Material.Neon
	ring.Transparency = 0.35
	ring.Anchored = true
	ring.CanCollide = false
	ring.CanQuery = false
	ring.CanTouch = false
	ring.CastShadow = false

	previewAttachment0 = attachment0
	previewAttachment1 = attachment1
	previewBeam = beam
	previewRing = ring
end

local function hidePreview()
	if previewBeam ~= nil then
		previewBeam.Enabled = false
	end
	if previewRing ~= nil then
		previewRing.Parent = nil
	end
end

local function updatePreview()
	local root = getLiveRoot()
	if root == nil or CarryController.GetSelected() == nil then
		hidePreview()
		return
	end
	local params = buildParams()
	local aim = getAimPoint(params)
	if aim == nil then
		hidePreview()
		return
	end

	local origin = getOrigin(root, params)
	local velocity = Ballistics.Solve(origin, aim, root.CFrame.LookVector)
	local hit = Ballistics.Simulate(origin, velocity, params)
	if hit.Time <= 0.02 then
		hidePreview()
		return
	end

	ensurePreview()
	local beam = previewBeam :: Beam
	local attachment0 = previewAttachment0 :: Attachment
	local attachment1 = previewAttachment1 :: Attachment
	local ring = previewRing :: Part

	local gravity = Vector3.new(0, -Ballistics.GetGravity(), 0)
	local curve0, curve1, cf1, cf2 = beamForArc(gravity, velocity, origin, hit.Time)
	beam.CurveSize0 = curve0
	beam.CurveSize1 = curve1
	attachment0.WorldCFrame = cf1
	attachment1.WorldCFrame = cf2
	beam.Enabled = true

	local normal = hit.Normal or Vector3.new(0, 1, 0)
	-- Cylinders extend along X: point X along the surface normal so the ring lies flat on it.
	ring.CFrame = CFrame.lookAt(hit.Position, hit.Position + normal) * CFrame.Angles(0, math.rad(90), 0)
		+ normal * 0.08
	ring.Parent = visualsFolder
end

local function stopAiming()
	if aimConnection ~= nil then
		aimConnection:Disconnect()
		aimConnection = nil
	end
	hidePreview()
end

local function startAiming()
	if aimConnection ~= nil then
		return
	end
	if CarryController.GetSelected() == nil then
		return -- nothing to throw: the release shows a message
	end
	aimConnection = RunService.RenderStepped:Connect(updatePreview)
	updatePreview()
end

---------------------------------------------------------------------------------------------
-- Request
---------------------------------------------------------------------------------------------

local function requestThrow()
	stopAiming()

	local selected = CarryController.GetSelected()
	if selected == nil then
		NotifyController.Show("Nothing to throw - pick up some junk!", "Info")
		return
	end
	local root = getLiveRoot()
	local remote = throwRemote
	if root == nil or remote == nil then
		return
	end

	local now = os.clock()
	if now - lastThrowAt < GameConfig.Throw.Cooldown then
		return
	end
	if pendingUid ~= nil and now - pendingAt < PENDING_TIMEOUT then
		return -- previous throw not answered yet
	end

	local params = buildParams()
	local aim = getAimPoint(params)
	if aim == nil then
		return
	end

	-- Face the throw so the server's origin (in front of the character) matches the preview.
	local flat = Vector3.new(aim.X - root.Position.X, 0, aim.Z - root.Position.Z)
	if flat.Magnitude > 0.5 then
		root.CFrame = CFrame.lookAt(root.Position, root.Position + flat)
	end

	lastThrowAt = now
	pendingUid = selected.Uid
	pendingAt = now
	remote:FireServer(selected.Uid, aim)
end

---------------------------------------------------------------------------------------------
-- Flights: animate the ONE world object of each thrown junk
---------------------------------------------------------------------------------------------

local function findJunk(uid: string): Model?
	local container = junkContainer
	if container == nil then
		return nil
	end
	for _, child in container:GetChildren() do
		if child:IsA("Model") and child:GetAttribute("JunkUid") == uid then
			return child
		end
	end
	return nil
end

local function endFlight(uid: string)
	local flight = flights[uid]
	if flight == nil then
		return
	end
	flights[uid] = nil
	flightCount -= 1
	local model = flight.Model
	-- Leave the object exactly where the server put it (only if it is still that junk).
	if model ~= nil and model.Parent ~= nil and model:GetAttribute("JunkUid") == uid then
		model:PivotTo(flight.Fx.FinalPivot)
	end
	if flightCount <= 0 and flightConnection ~= nil then
		flightConnection:Disconnect()
		flightConnection = nil
	end
end

local function placeAlongArc(flight: Flight, t: number)
	local model = flight.Model
	if model == nil then
		return
	end
	local fx = flight.Fx
	local alpha = t / fx.FlightTime
	local position = Ballistics.PositionAt(fx.Origin, fx.Velocity, fx.Gravity, t) + flight.Correction * alpha
	local spin = CFrame.fromAxisAngle(flight.SpinAxis, flight.SpinTotal * alpha)
	model:PivotTo(CFrame.new(position) * spin * fx.FinalPivot.Rotation)
end

local function stepFlights()
	local now = os.clock()
	local finished: { string } = {}
	for uid, flight in flights do
		local t = now - flight.StartedAt
		local model = flight.Model
		if t >= flight.Fx.FlightTime then
			table.insert(finished, uid)
		elseif model ~= nil then
			if model.Parent == nil or model:GetAttribute("JunkUid") ~= uid then
				table.insert(finished, uid) -- streamed out or reused: stop touching it
			else
				placeAlongArc(flight, t)
			end
		end
	end
	for _, uid in finished do
		endFlight(uid)
	end
end

local function attachModel(flight: Flight, model: Model)
	flight.Model = model
	-- Move it onto the arc right away, before this frame is drawn at the final pivot.
	placeAlongArc(flight, math.min(os.clock() - flight.StartedAt, flight.Fx.FlightTime))
end

local function isValidFx(fx: any): boolean
	if type(fx) ~= "table" then
		return false
	end
	return Validate.IsUid(fx.Uid)
		and JunkConfig.Exists(fx.JunkId)
		and typeof(fx.Origin) == "Vector3"
		and typeof(fx.Velocity) == "Vector3"
		and typeof(fx.FinalPivot) == "CFrame"
		and Validate.IsFiniteNumber(fx.Gravity)
		and Validate.IsFiniteNumber(fx.FlightTime)
		and fx.FlightTime > 0
		and fx.FlightTime <= GameConfig.Throw.MaxFlightTime + 0.1
end

local function onThrowFx(fx: Types.ThrowFx)
	if not isValidFx(fx) then
		return
	end

	if fx.ThrowerUserId == localPlayer.UserId then
		if pendingUid == fx.Uid then
			pendingUid = nil
		end
		local definition = JunkConfig.Get(fx.JunkId)
		NotifyController.Show(`Threw {if definition ~= nil then definition.DisplayName else "junk"}!`, "Success")
	end

	if flights[fx.Uid] ~= nil then
		return
	end

	local arcEnd = Ballistics.PositionAt(fx.Origin, fx.Velocity, fx.Gravity, fx.FlightTime)
	local flat = Vector3.new(fx.Velocity.X, 0, fx.Velocity.Z)
	local turns = math.max(1, math.floor(fx.FlightTime * SPIN_SPEED / (2 * math.pi) + 0.5))
	local flight: Flight = {
		Fx = fx,
		Model = nil,
		Correction = fx.FinalPivot.Position - arcEnd,
		SpinAxis = if flat.Magnitude > 1e-3 then flat.Unit:Cross(Vector3.new(0, 1, 0)) else Vector3.new(1, 0, 0),
		SpinTotal = turns * 2 * math.pi,
		StartedAt = os.clock(),
	}
	flights[fx.Uid] = flight
	flightCount += 1
	if flightConnection == nil then
		flightConnection = RunService.Heartbeat:Connect(stepFlights)
	end

	-- Normally the object replicates right after this event (see onJunkAdded); it can also be
	-- here already, e.g. when this client was far away and it streamed in early.
	local model = findJunk(fx.Uid)
	if model ~= nil then
		attachModel(flight, model)
	end
end

-- A junk object replicated (or streamed in). If it belongs to a flight, it starts flying now.
local function onJunkAdded(child: Instance)
	if not child:IsA("Model") then
		return
	end
	local uid = child:GetAttribute("JunkUid")
	if type(uid) ~= "string" then
		return
	end
	local flight = flights[uid]
	if flight ~= nil and flight.Model == nil then
		attachModel(flight, child)
	end
end

---------------------------------------------------------------------------------------------
-- Start
---------------------------------------------------------------------------------------------

function ThrowController.Start()
	local folder = Instance.new("Folder")
	folder.Name = VISUALS_FOLDER_NAME
	folder.Parent = Workspace
	visualsFolder = folder

	InputController.ThrowBegan:Connect(startAiming)
	InputController.ThrowReleased:Connect(requestThrow)
	InputController.ThrowCancelled:Connect(stopAiming)

	-- The selected junk left (e.g. dropped on death) while aiming: the preview follows the new state.
	CarryController.ItemsRemoved:Connect(function(entries: { Types.CarriedJunk })
		for _, entry in entries do
			if entry.Uid == pendingUid then
				pendingUid = nil
			end
		end
	end)

	localPlayer.CharacterRemoving:Connect(InputController.CancelThrow)

	-- Must not yield (see Main.client): waiting for remotes happens in a spawned task.
	task.spawn(function()
		throwRemote = Remotes.GetEvent("ThrowRequest")
		Remotes.GetEvent("ThrowFx").OnClientEvent:Connect(onThrowFx)

		local container = Workspace:WaitForChild(GameConfig.Junk.ContainerName, 30)
		if container ~= nil then
			junkContainer = container
			container.ChildAdded:Connect(onJunkAdded)
		end
	end)
end

return ThrowController
