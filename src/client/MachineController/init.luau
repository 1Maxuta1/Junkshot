--!strict
--[[
	MachineController: everything the client does for Recycling Machines.

	World presentation (every client, every machine)
	  Driven only by the machine model's attributes (set by the server's MachineService).
	  Each state change cancels the previous phase's tweens and starts the new ones:
	    Idle           green lights, door closed, screen "READY"
	    AcceptingItem  door slides open, the junk flies from its owner into the slot, door closes
	    Processing     gears spin, piston pumps, lights flash, chamber glows, screen progress bar
	    RewardReady    reward model rises on the output pedestal with rarity effects
	                   (particle burst from Rare, light from Legendary) and a public announcement
	  Players joining mid-phase see the right moment (PhaseStartedAt is server time).
	  No Heartbeat/RenderStepped loops; only tweens (and a short Changed hook for model moves).

	Interaction (local player)
	  The machine's ProximityPrompt opens the panel (UI/MachinePanel). RECYCLE sends
	  MachineInsert(machineId, uid); the server validates everything. When the local player's
	  reward is ready, the panel closes and UI/RewardReveal shows it (once per cycle).
]]

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ProximityPromptService = game:GetService("ProximityPromptService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

ReplicatedStorage:WaitForChild("Shared")
local ItemConfig = require(ReplicatedStorage.Shared.Config.ItemConfig)
local JunkConfig = require(ReplicatedStorage.Shared.Config.JunkConfig)
local MachineConfig = require(ReplicatedStorage.Shared.Config.MachineConfig)
local Rarities = require(ReplicatedStorage.Shared.Config.Rarities)
local Remotes = require(ReplicatedStorage.Shared.Remotes)
local JunkFactory = require(ReplicatedStorage.Shared.Util.JunkFactory)

local CarryController = require(script.Parent.CarryController)
local InputController = require(script.Parent.InputController)
local NotifyController = require(script.Parent.NotifyController)
local MachinePanel = require(script.Parent.UI.MachinePanel)
local RewardReveal = require(script.Parent.UI.RewardReveal)
local Theme = require(script.Parent.UI.Theme)

type Rest = { Part: BasePart, CFrame: CFrame }

type GearRig = { Parts: { Rest }, Axis: Vector3, Direction: number }

type View = {
	Id: string,
	Model: Model,
	Prompt: ProximityPrompt?,
	Door: Rest?,
	Piston: { Rest },
	Gears: { GearRig },
	Lights: { BasePart },
	Glow: BasePart?,
	Slot: BasePart?,
	RewardPoint: BasePart?,
	ScreenLabel: TextLabel?,
	ScreenFill: Frame?,
	Emitter: ParticleEmitter?,
	Light: PointLight?,
	Announcement: TextLabel?,
	AnnouncementGui: BillboardGui?,
	Tweens: { Tween },
	Temps: { Instance },
	Connections: { RBXScriptConnection },
	Token: number, -- increments per applied phase; delayed steps check it
	ApplyQueued: boolean,
	RevealedCycle: number,
}

local IDLE_LIGHT = Color3.fromRGB(80, 210, 120)
local BUSY_LIGHT = Color3.fromRGB(255, 150, 30)
local FLASH_LIGHT = Color3.fromRGB(255, 220, 70)
local IDLE_GLOW = Color3.fromRGB(36, 188, 186)
local DOOR_LIFT = 2.8
local PISTON_LIFT = 1.4
local REWARD_SIZE = 2.4
local REWARD_RISE = 1.2
local FLIGHT_TIME = 0.55
local PENDING_TIMEOUT = 2

local localPlayer = Players.LocalPlayer

local MachineController = {}

local views: { [Model]: View } = {}
local insertRemote: RemoteEvent? = nil
local claimRemote: RemoteEvent? = nil

local panel: MachinePanel.Panel? = nil
local reveal: RewardReveal.RewardReveal? = nil
local panelView: View? = nil
local selectedUid: string? = nil
local pendingAt = -math.huge

---------------------------------------------------------------------------------------------
-- Helpers
---------------------------------------------------------------------------------------------

local function attr(view: View, name: string): any
	return view.Model:GetAttribute(name)
end

local function isMine(view: View): boolean
	return attr(view, "OwnerUserId") == localPlayer.UserId
end

local function play(view: View, instance: Instance, info: TweenInfo, goal: { [string]: any })
	local tween = TweenService:Create(instance, info, goal)
	table.insert(view.Tweens, tween)
	tween:Play()
end

-- Moves a whole (anchored) model along a tween: a CFrameValue is tweened and the model follows.
local function tweenModel(view: View, model: Model, from: CFrame, to: CFrame, info: TweenInfo)
	local value = Instance.new("CFrameValue")
	value.Value = from
	table.insert(view.Temps, value)
	table.insert(view.Connections, value.Changed:Connect(function(cframe: CFrame)
		if model.Parent ~= nil then
			model:PivotTo(cframe)
		end
	end))
	model:PivotTo(from)
	play(view, value, info, { Value = to })
end

local function phaseTiming(view: View): (number, number)
	local started = attr(view, "PhaseStartedAt")
	local duration = attr(view, "PhaseDuration")
	local elapsed = if type(started) == "number" then math.max(Workspace:GetServerTimeNow() - started, 0) else 0
	return elapsed, if type(duration) == "number" then duration else 0
end

local function setLights(view: View, color: Color3)
	for _, light in view.Lights do
		light.Color = color
	end
end

-- Cancels the previous phase and puts every moving part back to its rest pose.
local function clearPhase(view: View)
	view.Token += 1
	for _, tween in view.Tweens do
		tween:Cancel()
	end
	table.clear(view.Tweens)
	for _, connection in view.Connections do
		connection:Disconnect()
	end
	table.clear(view.Connections)
	for _, instance in view.Temps do
		instance:Destroy()
	end
	table.clear(view.Temps)

	if view.Door ~= nil then
		view.Door.Part.CFrame = view.Door.CFrame
	end
	for _, rest in view.Piston do
		rest.Part.CFrame = rest.CFrame
	end
	for _, gear in view.Gears do
		for _, rest in gear.Parts do
			rest.Part.CFrame = rest.CFrame
		end
	end
	if view.Light ~= nil then
		view.Light.Enabled = false
	end
	if view.AnnouncementGui ~= nil then
		view.AnnouncementGui.Enabled = false
	end
end

local function setScreen(view: View, text: string, fraction: number, remaining: number)
	local label, fill = view.ScreenLabel, view.ScreenFill
	if label == nil or fill == nil then
		return
	end
	label.Text = text
	fill.Size = UDim2.fromScale(math.clamp(fraction, 0, 1), 1)
	if remaining > 0 then
		play(view, fill, TweenInfo.new(remaining, Enum.EasingStyle.Linear), { Size = UDim2.fromScale(1, 1) })
	end
end

---------------------------------------------------------------------------------------------
-- Phases
---------------------------------------------------------------------------------------------

local function ownerRoot(view: View): BasePart?
	local owner = Players:GetPlayerByUserId(attr(view, "OwnerUserId") or 0)
	local character = owner and owner.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if root ~= nil and root:IsA("BasePart") then
		return root
	end
	return nil
end

local function phaseAccepting(view: View, elapsed: number, duration: number)
	setLights(view, FLASH_LIGHT)
	setScreen(view, "LOADING...", 0, 0)
	local door = view.Door
	if door ~= nil then
		play(view, door.Part, TweenInfo.new(0.2, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
			CFrame = door.CFrame * CFrame.new(0, DOOR_LIFT, 0),
		})
		local token = view.Token
		task.delay(math.max(duration - elapsed - 0.25, 0), function()
			if view.Token == token then
				play(view, door.Part, TweenInfo.new(0.2, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {
					CFrame = door.CFrame,
				})
			end
		end)
	end

	-- The junk flies into the slot (a short local animation of the consumed item).
	local junkId = attr(view, "InputJunkId")
	local slot = view.Slot
	if elapsed < 0.3 and slot ~= nil and type(junkId) == "string" and JunkConfig.Exists(junkId) then
		local model = JunkFactory.Build(junkId, "World", 1.6)
		if model ~= nil then
			table.insert(view.Temps, model)
			local inside = slot.CFrame * CFrame.new(0, 0, 1.5) -- just behind the slot
			local root = ownerRoot(view)
			local from = if root ~= nil and (root.Position - slot.Position).Magnitude < 60
				then CFrame.new(root.Position + Vector3.new(0, 2, 0))
				else slot.CFrame * CFrame.new(0, 1, -6)
			model.Parent = Workspace
			tweenModel(view, model, from, inside, TweenInfo.new(FLIGHT_TIME, Enum.EasingStyle.Quad, Enum.EasingDirection.Out))
		end
	end
end

local function phaseProcessing(view: View, elapsed: number, duration: number)
	setLights(view, BUSY_LIGHT)
	for _, light in view.Lights do
		play(view, light, TweenInfo.new(0.25, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true), {
			Color = FLASH_LIGHT,
		})
	end
	if view.Glow ~= nil then
		view.Glow.Color = IDLE_GLOW
		play(view, view.Glow, TweenInfo.new(0.5, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true), {
			Color = BUSY_LIGHT,
		})
	end
	for _, gear in view.Gears do
		for _, rest in gear.Parts do
			local turned = CFrame.new(rest.CFrame.Position)
				* CFrame.fromAxisAngle(gear.Axis, gear.Direction * math.pi / 2)
				* rest.CFrame.Rotation
			-- 4-fold symmetric gear: restarting each quarter turn looks like continuous spinning.
			play(view, rest.Part, TweenInfo.new(0.45, Enum.EasingStyle.Linear, Enum.EasingDirection.InOut, -1), {
				CFrame = turned,
			})
		end
	end
	for _, rest in view.Piston do
		play(view, rest.Part, TweenInfo.new(0.35, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true), {
			CFrame = rest.CFrame * CFrame.new(0, PISTON_LIFT, 0),
		})
	end
	local fraction = if duration > 0 then elapsed / duration else 1
	setScreen(view, "RECYCLING", fraction, math.max(duration - elapsed, 0))
end

local function showRewardModel(view: View, itemId: string, info: Rarities.RarityInfo)
	local point = view.RewardPoint
	if point == nil then
		return
	end
	local model = JunkFactory.BuildItem(itemId, "World", REWARD_SIZE)
	if model == nil then
		return
	end
	for _, descendant in model:GetDescendants() do
		if descendant:IsA("BasePart") then
			descendant.CastShadow = false
		end
	end
	table.insert(view.Temps, model)
	model.Parent = Workspace

	local base = point.CFrame
	tweenModel(view, model, base * CFrame.new(0, -REWARD_RISE, 0), base, TweenInfo.new(0.5, Enum.EasingStyle.Back, Enum.EasingDirection.Out))

	-- Slow turn while shown (Changed only fires while this tween runs).
	local angle = Instance.new("NumberValue")
	table.insert(view.Temps, angle)
	table.insert(view.Connections, angle.Changed:Connect(function(value: number)
		if model.Parent ~= nil then
			model:PivotTo(base * CFrame.Angles(0, value, 0))
		end
	end))
	local token = view.Token
	task.delay(0.5, function()
		if view.Token == token then
			play(view, angle, TweenInfo.new(5, Enum.EasingStyle.Linear, Enum.EasingDirection.InOut, -1), {
				Value = math.pi * 2,
			})
		end
	end)

	if info.Effect >= 1 then
		local highlight = Instance.new("Highlight")
		highlight.FillColor = info.Color
		highlight.FillTransparency = 0.75
		highlight.OutlineColor = info.Color
		highlight.DepthMode = Enum.HighlightDepthMode.Occluded
		highlight.Parent = model
	end
	local emitter = view.Emitter
	if emitter ~= nil and info.Effect >= 2 then
		emitter.Color = ColorSequence.new(info.Color, Color3.new(1, 1, 1))
		emitter:Emit(8 * info.Effect) -- one burst; the emitter never runs continuously
	end
	local light = view.Light
	if light ~= nil and info.Effect >= 4 then
		light.Color = info.Color
		light.Enabled = true
	end
end

local function phaseReward(view: View)
	local itemId = attr(view, "RewardItemId")
	local rarity = attr(view, "RewardRarity")
	if type(itemId) ~= "string" or not ItemConfig.Exists(itemId) or not Rarities.IsValid(rarity) then
		return
	end
	local info = Rarities.Info[rarity]
	setLights(view, info.Color)
	if view.Glow ~= nil then
		view.Glow.Color = info.Color
	end
	local delivered = attr(view, "RewardDelivered") == true
	setScreen(view, if delivered then string.upper(info.DisplayName) .. "!" else "CLAIM REWARD", 1, 0)
	showRewardModel(view, itemId, info)

	local label, gui = view.Announcement, view.AnnouncementGui
	if label ~= nil and gui ~= nil then
		local definition = ItemConfig.Get(itemId)
		local ownerName = attr(view, "OwnerName")
		label.Text = string.format(
			"%s got %s %s!",
			if type(ownerName) == "string" and ownerName ~= "" then ownerName else "Someone",
			info.DisplayName,
			if definition ~= nil then definition.DisplayName else itemId
		)
		label.TextColor3 = info.Color
		gui.Enabled = true
	end

	-- The owner's reveal card, once per cycle.
	local cycle = attr(view, "Cycle")
	if isMine(view) and type(cycle) == "number" and view.RevealedCycle ~= cycle then
		view.RevealedCycle = cycle
		local currentPanel = panel
		if currentPanel ~= nil and panelView == view then
			currentPanel.Close()
		end
		local currentReveal = reveal
		if currentReveal ~= nil then
			currentReveal.Show(itemId, rarity, delivered, InputController.GetInputKind() == "Gamepad")
		end
	end
end

---------------------------------------------------------------------------------------------
-- Panel
---------------------------------------------------------------------------------------------

local function renderPanel()
	local currentPanel = panel
	local view = panelView
	if currentPanel == nil or view == nil then
		return
	end
	local state = attr(view, "State")
	local items = CarryController.GetLocalCarried()
	local elapsed, duration = phaseTiming(view)

	if state == "Idle" or state == nil then
		-- Keep the selection valid: prefer the current choice, then the hotbar selection.
		local valid = false
		for _, entry in items do
			if entry.Uid == selectedUid then
				valid = true
			end
		end
		if not valid then
			local hotbar = CarryController.GetSelected()
			selectedUid = if hotbar ~= nil then hotbar.Uid elseif items[1] ~= nil then items[1].Uid else nil
		end
		local waiting = os.clock() - pendingAt < PENDING_TIMEOUT
		currentPanel.Render({
			Status = if #items > 0 then "Pick the junk to recycle" else "Your hands are empty",
			Items = items,
			SelectedUid = selectedUid,
			ShowItems = true,
			ActionText = if waiting then "..." else "RECYCLE",
			ActionEnabled = selectedUid ~= nil and not waiting,
			ActionKind = "Recycle",
			Progress = nil,
			Compact = false,
		})
		return
	end

	local mine = isMine(view)
	local ownerName = attr(view, "OwnerName")
	local progress = if state == "Processing" and duration > 0
		then { Fraction = elapsed / duration, Remaining = math.max(duration - elapsed, 0) }
		else nil
	local delivered = attr(view, "RewardDelivered") == true
	local status: string
	if mine then
		status = if state == "AcceptingItem"
			then "Loading your junk..."
			elseif state == "Processing" then "Recycling..."
			else "Reward ready!"
	else
		status = `Busy: {if type(ownerName) == "string" then ownerName else "someone"} is recycling`
	end
	local claim = mine and state == "RewardReady" and not delivered
	currentPanel.Render({
		Status = status,
		Items = items,
		SelectedUid = nil,
		ShowItems = false,
		ActionText = if claim then "CLAIM REWARD" elseif mine then "PLEASE WAIT" else "BUSY",
		ActionEnabled = claim,
		ActionKind = if claim then "Claim" else "Recycle",
		Progress = progress,
		Compact = not claim, -- keep the machine visible while it works
	})
end

local function openPanel(view: View)
	local currentPanel = panel
	if currentPanel == nil then
		return
	end
	panelView = view
	selectedUid = nil
	renderPanel() -- before Open, so gamepad focus can go to the first card
	currentPanel.Open(InputController.GetInputKind() == "Gamepad")
end

local function onPanelAction(kind: string)
	local view = panelView
	if view == nil then
		return
	end
	if kind == "Recycle" then
		local uid = selectedUid
		local remote = insertRemote
		if uid == nil or remote == nil then
			return
		end
		pendingAt = os.clock()
		remote:FireServer(view.Id, uid)
		renderPanel()
	elseif kind == "Claim" then
		local remote = claimRemote
		if remote ~= nil then
			remote:FireServer(view.Id)
		end
	end
end

---------------------------------------------------------------------------------------------
-- Machine setup
---------------------------------------------------------------------------------------------

local function applyState(view: View)
	view.ApplyQueued = false
	clearPhase(view)
	local state = attr(view, "State")
	local elapsed, duration = phaseTiming(view)

	if state == "AcceptingItem" then
		phaseAccepting(view, elapsed, duration)
		if isMine(view) then
			pendingAt = -math.huge
			local junkId = attr(view, "InputJunkId")
			local definition = if type(junkId) == "string" then JunkConfig.Get(junkId) else nil
			NotifyController.Show(`Recycling {if definition ~= nil then definition.DisplayName else "junk"}...`, "Info")
		end
	elseif state == "Processing" then
		phaseProcessing(view, elapsed, duration)
	elseif state == "RewardReady" then
		phaseReward(view)
	else
		setLights(view, IDLE_LIGHT)
		if view.Glow ~= nil then
			view.Glow.Color = IDLE_GLOW
		end
		setScreen(view, "READY", 0, 0)
	end

	local currentReveal = reveal
	if currentReveal ~= nil and isMine(view) and state == "RewardReady" then
		currentReveal.SetDelivered(attr(view, "RewardDelivered") == true)
	end
	if panelView == view then
		renderPanel()
	end
end

-- Several attributes change in the same frame; apply the state once.
local function queueApply(view: View)
	if not view.ApplyQueued then
		view.ApplyQueued = true
		task.defer(applyState, view)
	end
end

local function findPart(model: Model, name: string): BasePart?
	local found = model:FindFirstChild(name, true)
	return if found ~= nil and found:IsA("BasePart") then found else nil
end

local function buildScreen(view: View, screen: BasePart)
	local gui = Instance.new("SurfaceGui")
	gui.Name = "MachineScreen"
	gui.Face = Enum.NormalId.Front
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = 40
	gui.LightInfluence = 0
	local label = Instance.new("TextLabel")
	label.BackgroundTransparency = 1
	label.Size = UDim2.fromScale(1, 0.6)
	label.Font = Theme.Font
	label.TextScaled = true
	label.TextColor3 = Color3.fromRGB(140, 255, 200)
	label.Text = "READY"
	label.Parent = gui
	local barBack = Instance.new("Frame")
	barBack.Position = UDim2.fromScale(0.08, 0.66)
	barBack.Size = UDim2.fromScale(0.84, 0.22)
	barBack.BackgroundColor3 = Color3.fromRGB(40, 60, 90)
	barBack.BorderSizePixel = 0
	barBack.Parent = gui
	local fill = Instance.new("Frame")
	fill.Size = UDim2.fromScale(0, 1)
	fill.BackgroundColor3 = BUSY_LIGHT
	fill.BorderSizePixel = 0
	fill.Parent = barBack
	gui.Parent = screen
	view.ScreenLabel = label
	view.ScreenFill = fill
end

local function buildEffects(view: View, point: BasePart)
	local attachment = Instance.new("Attachment")
	attachment.Name = "RewardFx"
	attachment.Parent = point
	local emitter = Instance.new("ParticleEmitter")
	emitter.Enabled = false -- bursts only (Emit); never runs continuously
	emitter.Rate = 0
	emitter.Lifetime = NumberRange.new(0.6, 1.1)
	emitter.Speed = NumberRange.new(8, 14)
	emitter.SpreadAngle = Vector2.new(180, 180)
	emitter.Drag = 4
	emitter.LightEmission = 0.8
	emitter.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.5), NumberSequenceKeypoint.new(1, 0) })
	emitter.Parent = attachment
	view.Emitter = emitter

	local light = Instance.new("PointLight")
	light.Range = 14
	light.Brightness = 2
	light.Shadows = false
	light.Enabled = false
	light.Parent = point
	view.Light = light
end

local function buildAnnouncement(view: View, anchor: BasePart)
	local gui = Instance.new("BillboardGui")
	gui.Name = "RewardAnnouncement"
	gui.Adornee = anchor
	gui.Size = UDim2.fromOffset(340, 48)
	gui.StudsOffset = Vector3.new(0, 20, 0)
	gui.MaxDistance = 160
	gui.LightInfluence = 0
	gui.Enabled = false
	local label = Instance.new("TextLabel")
	label.BackgroundTransparency = 1
	label.Size = UDim2.fromScale(1, 1)
	label.Font = Theme.Font
	label.TextScaled = true
	label.TextStrokeTransparency = 0.2
	label.TextStrokeColor3 = Theme.Colors.Ink
	label.Parent = gui
	gui.Parent = anchor
	view.Announcement = label
	view.AnnouncementGui = gui
end

local function track(model: Instance)
	if not model:IsA("Model") or views[model] ~= nil then
		return
	end
	local id = model:GetAttribute("MachineId")
	if type(id) ~= "string" then
		return
	end

	local view: View = {
		Id = id,
		Model = model,
		Prompt = nil,
		Door = nil,
		Piston = {},
		Gears = {},
		Lights = {},
		Glow = findPart(model, "ChamberGlow"),
		Slot = findPart(model, "InputSlot"),
		RewardPoint = findPart(model, "RewardPoint"),
		Tweens = {},
		Temps = {},
		Connections = {},
		Token = 0,
		ApplyQueued = false,
		RevealedCycle = -1,
	}
	local door = findPart(model, "InputDoor")
	if door ~= nil then
		view.Door = { Part = door, CFrame = door.CFrame }
	end
	for _, name in { "PistonHead", "PistonRod" } do
		local part = findPart(model, name)
		if part ~= nil then
			table.insert(view.Piston, { Part = part, CFrame = part.CFrame })
		end
	end
	for index, name in { "Gear1", "Gear2" } do
		local gearModel = model:FindFirstChild(name, true)
		if gearModel ~= nil then
			local rig: GearRig = { Parts = {}, Axis = Vector3.xAxis, Direction = if index == 1 then 1 else -1 }
			for _, child in gearModel:GetChildren() do
				if child:IsA("BasePart") then
					table.insert(rig.Parts, { Part = child, CFrame = child.CFrame })
					if child.Name == "Disk" then
						rig.Axis = child.CFrame.RightVector -- cylinders run along X
					end
				end
			end
			table.insert(view.Gears, rig)
		end
	end
	for index = 1, 3 do
		local light = findPart(model, `Light{index}`)
		if light ~= nil then
			table.insert(view.Lights, light)
		end
	end
	local screen = findPart(model, "Screen")
	if screen ~= nil then
		buildScreen(view, screen)
	end
	if view.RewardPoint ~= nil then
		buildEffects(view, view.RewardPoint)
	end
	local anchor = findPart(model, "PromptAnchor")
	if anchor ~= nil then
		buildAnnouncement(view, anchor)
	end

	views[model] = view
	model.AttributeChanged:Connect(function(name: string)
		if name == "State" or name == "PhaseStartedAt" or name == "RewardDelivered" then
			queueApply(view)
		end
	end)
	applyState(view)
end

local function untrack(model: Instance)
	local view = views[model :: Model]
	if view ~= nil then
		clearPhase(view)
		views[model :: Model] = nil
		if panelView == view and panel ~= nil then
			panel.Close()
		end
	end
end

local function viewForPrompt(prompt: ProximityPrompt): View?
	for model, view in views do
		if prompt:IsDescendantOf(model) then
			return view
		end
	end
	return nil
end

function MachineController.Start()
	task.spawn(function()
		local gui = Instance.new("ScreenGui")
		gui.Name = "JunkshotMachine"
		gui.ResetOnSpawn = false
		gui.ScreenInsets = Enum.ScreenInsets.CoreUISafeInsets
		gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
		gui.DisplayOrder = 8

		panel = MachinePanel.Mount(gui, {
			OnSelect = function(uid: string)
				selectedUid = uid
				renderPanel()
			end,
			OnAction = onPanelAction,
			OnClose = function()
				panelView = nil
			end,
		})
		reveal = RewardReveal.Mount(gui, function()
			local view = nil
			for _, candidate in views do
				if isMine(candidate) and attr(candidate, "State") == "RewardReady" then
					view = candidate
				end
			end
			local remote = claimRemote
			if view ~= nil and remote ~= nil then
				remote:FireServer(view.Id)
			end
		end)
		gui.Parent = localPlayer:WaitForChild("PlayerGui")

		insertRemote = Remotes.GetEvent("MachineInsert")
		claimRemote = Remotes.GetEvent("MachineClaim")

		CollectionService:GetInstanceAddedSignal(MachineConfig.Tag):Connect(track)
		CollectionService:GetInstanceRemovedSignal(MachineConfig.Tag):Connect(untrack)
		for _, model in CollectionService:GetTagged(MachineConfig.Tag) do
			track(model)
		end
	end)

	ProximityPromptService.PromptTriggered:Connect(function(prompt: ProximityPrompt, player: Player)
		if player ~= localPlayer or prompt:GetAttribute("PromptKind") ~= "Machine" then
			return
		end
		local view = viewForPrompt(prompt)
		if view ~= nil then
			openPanel(view)
		end
	end)
	ProximityPromptService.PromptHidden:Connect(function(prompt: ProximityPrompt)
		-- Walking away closes the panel, unless the player's own cycle is running.
		-- Roblox also hides and re-shows prompts when the input type changes (touch -> keyboard
		-- -> gamepad), so only an actual distance from the machine counts as walking away.
		local view = panelView
		local anchor = prompt.Parent
		if view == nil or panel == nil or not prompt:IsDescendantOf(view.Model) or not anchor:IsA("BasePart") then
			return
		end
		local character = localPlayer.Character
		local root = character and character:FindFirstChild("HumanoidRootPart")
		local away = root == nil
			or not root:IsA("BasePart")
			or (root.Position - anchor.Position).Magnitude > MachineConfig.PromptDistance + 1
		local state = attr(view, "State")
		if away and not (isMine(view) and state ~= "Idle") then
			panel.Close()
		end
	end)
	CarryController.Changed:Connect(renderPanel)
end

return MachineController
