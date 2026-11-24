--!strict
--[[
	MachineController: the client side of the personal machines.

	World presentation (every machine, every client)
	  Driven only by each machine model's attributes (set by the server's MachineService).
	    Idle         green lights, screen "READY"
	    Processing   gears spin, piston pumps, lights flash; the screen shows the remaining time
	    RewardReady  lights in the rarity color of the last result, screen "DONE!"
	  When a job finishes (ResultSeq goes up) everyone nearby sees a burst and an announcement;
	  the owner also gets the reward card (UI/RewardReveal).
	  One 1-second ticker updates the screens and the open panel. Everything else is tweens.

	Panel (own machine only)
	  The machine's prompt (R / Y / tap) opens UI/Machine/Panel. Every button sends a request
	  that acts on the player's own machine; the server validates all of them.
]]

local CollectionService = game:GetService("CollectionService")
local MarketplaceService = game:GetService("MarketplaceService")
local Players = game:GetService("Players")
local ProximityPromptService = game:GetService("ProximityPromptService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

ReplicatedStorage:WaitForChild("Shared")
local ItemConfig = require(ReplicatedStorage.Shared.Config.ItemConfig)
local MachineConfig = require(ReplicatedStorage.Shared.Config.MachineConfig)
local AudioConfig = require(ReplicatedStorage.Shared.Config.AudioConfig)
local MonetizationConfig = require(ReplicatedStorage.Shared.Config.MonetizationConfig)
local Rarities = require(ReplicatedStorage.Shared.Config.Rarities)
local Remotes = require(ReplicatedStorage.Shared.Remotes)
local Types = require(ReplicatedStorage.Shared.Types)
local Validate = require(ReplicatedStorage.Shared.Util.Validate)

local CarryController = require(script.Parent.CarryController)
local DataController = require(script.Parent.DataController)
local InputController = require(script.Parent.InputController)
local AudioController = require(script.Parent.AudioController)
local Panel = require(script.Parent.UI.Machine.Panel)
local Widgets = require(script.Parent.UI.Machine.Widgets)
local RewardReveal = require(script.Parent.UI.RewardReveal)
local Theme = require(script.Parent.UI.Theme)

type Rest = { Part: BasePart, CFrame: CFrame }
type GearRig = { Parts: { Rest }, Axis: Vector3, Direction: number }

type View = {
	Model: Model,
	Door: Rest?,
	Piston: { Rest },
	Gears: { GearRig },
	Lights: { BasePart },
	Glow: BasePart?,
	ScreenLabel: TextLabel?,
	ScreenFill: Frame?,
	Emitter: ParticleEmitter?,
	Announcement: TextLabel?,
	AnnouncementGui: BillboardGui?,
	Tweens: { Tween },
	MotionKey: string?, -- the state the running animation belongs to (restarted only when it changes)
	LoopSound: Sound?, -- the soft working sound while Processing
	SoundsReady: boolean, -- false until the first state is shown (no "start" sound for jobs already running)
	ApplyQueued: boolean,
	SeenSeq: number,
	AnnouncementToken: number,
}

local IDLE_LIGHT = Color3.fromRGB(80, 210, 120)
local BUSY_LIGHT = Color3.fromRGB(255, 150, 30)
local FLASH_LIGHT = Color3.fromRGB(255, 220, 70)
local IDLE_GLOW = Color3.fromRGB(36, 188, 186)
local PISTON_LIFT = 1.4
local ANNOUNCE_TIME = 4
local CLICK_INTERVAL = 1 / 10 -- matches the server's MachineAccelerate rate limit

local localPlayer = Players.LocalPlayer

local MachineController = {}

local views: { [Model]: View } = {}
local remotes: { [string]: RemoteEvent } = {}
local panel: Panel.Panel? = nil
local reveal: RewardReveal.RewardReveal? = nil
local lastClickAt = 0

---------------------------------------------------------------------------------------------
-- Helpers
---------------------------------------------------------------------------------------------

local function attr(view: View, name: string): any
	return view.Model:GetAttribute(name)
end

local function isMine(view: View): boolean
	return attr(view, "OwnerUserId") == localPlayer.UserId
end

local function ownView(): View?
	for _, view in views do
		if isMine(view) then
			return view
		end
	end
	return nil
end

local function fire(name: string, ...: any)
	local remote = remotes[name]
	if remote ~= nil then
		remote:FireServer(...)
	end
end

local function parseList(value: any): { Types.CarriedJunk }
	local list: { Types.CarriedJunk } = {}
	if type(value) ~= "string" or value == "" then
		return list
	end
	for _, pair in string.split(value, ",") do
		local uid, id = string.match(pair, "^([^:]+):(.+)$")
		if uid ~= nil and id ~= nil and Validate.IsUid(uid) and ItemConfig.Exists(id) then
			table.insert(list, { Uid = uid, Id = id })
		end
	end
	return list
end

local function play(view: View, instance: Instance, info: TweenInfo, goal: { [string]: any })
	local tween = TweenService:Create(instance, info, goal)
	table.insert(view.Tweens, tween)
	tween:Play()
end

local function setLights(view: View, color: Color3)
	for _, light in view.Lights do
		light.Color = color
	end
end

local function resetMotion(view: View)
	for _, tween in view.Tweens do
		tween:Cancel()
	end
	table.clear(view.Tweens)
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
end

-- Client-side estimate for labels only (the server decides the real duration).
local function durationFor(base: number): number
	local view = ownView()
	local multiplier = 1
	if view ~= nil then
		local level = attr(view, "UpgradeSpeed")
		local levels = MachineConfig.Upgrades.Speed.Levels
		if type(level) == "number" and levels[level] ~= nil then
			multiplier *= levels[level].Value
		end
		local boostUntil = attr(view, "BoostUntil")
		if type(boostUntil) == "number" and boostUntil > Workspace:GetServerTimeNow() then
			multiplier *= MonetizationConfig.Products.SpeedBoost.Multiplier
		end
	end
	return math.max(MachineConfig.MinDuration, math.floor(base * multiplier + 0.5))
end

---------------------------------------------------------------------------------------------
-- Panel
---------------------------------------------------------------------------------------------

local function buildView(view: View): Widgets.View
	local function number(name: string, default: number): number
		local value = attr(view, name)
		return if type(value) == "number" then value else default
	end
	local function text(name: string): string
		local value = attr(view, name)
		return if type(value) == "string" then value else ""
	end
	return {
		State = text("State"),
		JobKind = text("JobKind"),
		JobLabel = text("JobLabel"),
		StartedAt = number("JobStartedAt", 0),
		CompletesAt = number("JobCompletesAt", 0),
		ClickLeft = number("ClickLeft", 0),
		Duration = number("JobDuration", 0),
		Output = parseList(attr(view, "OutputList")),
		OutputCapacity = number("OutputCapacity", 1),
		Upgrades = {
			Speed = number("UpgradeSpeed", 1),
			Storage = number("UpgradeStorage", 1),
			Level = number("UpgradeLevel", 1),
		},
		MachineLevel = number("MachineLevel", 1),
		Carried = CarryController.GetLocalCarried(),
		Klunks = DataController.GetKlunks(),
		BoostUntil = number("BoostUntil", 0),
		InstantCredits = number("InstantCredits", 0),
	}
end

local function renderPanel()
	local currentPanel = panel
	local view = ownView()
	if currentPanel ~= nil and view ~= nil and currentPanel.IsOpen() then
		currentPanel.Render(buildView(view))
	end
end

local function openPanel()
	local currentPanel = panel
	local view = ownView()
	if currentPanel == nil or view == nil then
		return
	end
	currentPanel.Render(buildView(view))
	currentPanel.Open(InputController.GetInputKind() == "Gamepad")
end

local actions: Widgets.Actions = {
	Recycle = function(uid: string)
		fire("MachineRecycle", uid)
	end,
	Craft = function(recipeId: string)
		fire("MachineCraft", recipeId)
	end,
	Mythic = function(a: string, b: string, c: string)
		fire("MachineMythic", a, b, c)
	end,
	Accelerate = function()
		local now = os.clock()
		if now - lastClickAt >= CLICK_INTERVAL then -- faster clicks would be rejected anyway
			lastClickAt = now
			fire("MachineAccelerate")
		end
	end,
	Take = function(uid: string)
		fire("MachineTake", uid)
	end,
	Upgrade = function(upgradeId: string)
		fire("MachineUpgrade", upgradeId)
	end,
	BuyProduct = function(key: string)
		local product = (MonetizationConfig.Products :: any)[key]
		if product ~= nil and product.ProductId ~= 0 then
			MarketplaceService:PromptProductPurchase(localPlayer, product.ProductId)
		end
	end,
	BuyPass = function(key: string)
		local pass = (MonetizationConfig.GamePasses :: any)[key]
		if pass ~= nil and pass.GamePassId ~= 0 then
			MarketplaceService:PromptGamePassPurchase(localPlayer, pass.GamePassId)
		end
	end,
}

---------------------------------------------------------------------------------------------
-- World presentation
---------------------------------------------------------------------------------------------

local function updateScreen(view: View)
	local label, fill = view.ScreenLabel, view.ScreenFill
	if label == nil or fill == nil then
		return
	end
	local state = attr(view, "State")
	if state == "Processing" then
		local completes = attr(view, "JobCompletesAt")
		local duration = attr(view, "JobDuration")
		local left = if type(completes) == "number" then math.max(0, completes - Workspace:GetServerTimeNow()) else 0
		label.Text = Widgets.FormatTime(left)
		local fraction = if type(duration) == "number" and duration > 0 then 1 - left / duration else 1
		fill.Size = UDim2.fromScale(math.clamp(fraction, 0, 1), 1)
	elseif state == "RewardReady" then
		label.Text = "DONE!"
		fill.Size = UDim2.fromScale(1, 1)
	else
		label.Text = "READY"
		fill.Size = UDim2.fromScale(0, 1)
	end
end

local function announce(view: View)
	local itemId = attr(view, "LastResultId")
	local rarity = attr(view, "LastResultRarity")
	if type(itemId) ~= "string" or not ItemConfig.Exists(itemId) or not Rarities.IsValid(rarity) then
		return
	end
	local info = Rarities.Info[rarity]
	local emitter = view.Emitter
	if emitter ~= nil and info.Effect >= 2 then
		emitter.Color = ColorSequence.new(info.Color, Color3.new(1, 1, 1))
		emitter:Emit(8 * info.Effect) -- one burst; the emitter never runs continuously
	end
	local label, gui = view.Announcement, view.AnnouncementGui
	if label ~= nil and gui ~= nil then
		local ownerName = attr(view, "OwnerName")
		label.Text = string.format("%s got %s %s!", if type(ownerName) == "string" then ownerName else "Someone", info.DisplayName, ItemConfig.GetDisplayName(itemId))
		label.TextColor3 = info.Color
		gui.Enabled = true
		view.AnnouncementToken += 1
		local token = view.AnnouncementToken
		task.delay(ANNOUNCE_TIME, function()
			if view.AnnouncementToken == token then
				gui.Enabled = false
			end
		end)
	end
	if isMine(view) then
		local currentReveal = reveal
		if currentReveal ~= nil then
			currentReveal.Show(itemId, rarity, "It is waiting on your machine's tray", InputController.GetInputKind() == "Gamepad")
		end
	end
end

local function applyState(view: View)
	view.ApplyQueued = false
	local state = attr(view, "State")
	-- Speed-up clicks only move JobCompletesAt: keep the running animation instead of
	-- restarting it from its rest pose on every click.
	local motionKey = `{tostring(state)}:{tostring(attr(view, "LastResultRarity"))}`
	local restart = motionKey ~= view.MotionKey
	view.MotionKey = motionKey
	if restart then
		resetMotion(view)
		-- Sounds follow the state: item in -> soft ratchet while working -> ding when done.
		local found = view.Model:FindFirstChild("PromptAnchor", true)
		local anchor = if found ~= nil and found:IsA("BasePart") then found else nil
		local wasWorking = view.LoopSound ~= nil
		if view.LoopSound ~= nil then
			view.LoopSound:Destroy()
			view.LoopSound = nil
		end
		local sounds = AudioConfig.Machine
		if anchor ~= nil and view.SoundsReady then
			if state == "Processing" then
				AudioController.PlayAt(sounds.Start, anchor, false, sounds.Range)
				view.LoopSound = AudioController.PlayAt(sounds.Loop, anchor, true, sounds.Range)
			elseif state == "RewardReady" and wasWorking then
				AudioController.PlayAt(sounds.Done, anchor, false, sounds.Range)
			end
		elseif anchor ~= nil and state == "Processing" then
			view.LoopSound = AudioController.PlayAt(sounds.Loop, anchor, true, sounds.Range) -- joined mid-job: no "start"
		end
		view.SoundsReady = true
	end
	if not restart then
		-- same state as before: lights, gears and piston keep running as they are
	elseif state == "Processing" then
		setLights(view, BUSY_LIGHT)
		for _, light in view.Lights do
			play(view, light, TweenInfo.new(0.25, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true), { Color = FLASH_LIGHT })
		end
		if view.Glow ~= nil then
			view.Glow.Color = IDLE_GLOW
			play(view, view.Glow, TweenInfo.new(0.5, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true), { Color = BUSY_LIGHT })
		end
		for _, gear in view.Gears do
			for _, rest in gear.Parts do
				local turned = CFrame.new(rest.CFrame.Position)
					* CFrame.fromAxisAngle(gear.Axis, gear.Direction * math.pi / 2)
					* rest.CFrame.Rotation
				-- 4-fold symmetric gear: restarting each quarter turn looks like continuous spinning.
				play(view, rest.Part, TweenInfo.new(0.45, Enum.EasingStyle.Linear, Enum.EasingDirection.InOut, -1), { CFrame = turned })
			end
		end
		for _, rest in view.Piston do
			play(view, rest.Part, TweenInfo.new(0.35, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true), {
				CFrame = rest.CFrame * CFrame.new(0, PISTON_LIFT, 0),
			})
		end
	elseif state == "RewardReady" then
		local color = Rarities.GetColor(attr(view, "LastResultRarity"))
		setLights(view, color)
		if view.Glow ~= nil then
			view.Glow.Color = color
		end
	else
		setLights(view, IDLE_LIGHT)
		if view.Glow ~= nil then
			view.Glow.Color = IDLE_GLOW
		end
	end
	updateScreen(view)

	local seq = attr(view, "ResultSeq")
	if type(seq) == "number" then
		if seq > view.SeenSeq and view.SeenSeq >= 0 then
			announce(view)
		end
		view.SeenSeq = seq
	end
	if isMine(view) then
		renderPanel()
	end
end

-- Many attributes change in the same frame; apply once.
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

local function track(model: Instance)
	if not model:IsA("Model") or views[model] ~= nil or not model:IsDescendantOf(Workspace) then
		return
	end
	local view: View = {
		Model = model,
		Door = nil,
		Piston = {},
		Gears = {},
		Lights = {},
		Glow = findPart(model, "ChamberGlow"),
		Tweens = {},
		MotionKey = nil,
		LoopSound = nil,
		SoundsReady = false,
		ApplyQueued = false,
		SeenSeq = -1,
		AnnouncementToken = 0,
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
	local point = findPart(model, "RewardPoint")
	if point ~= nil then
		local attachment = Instance.new("Attachment")
		attachment.Parent = point
		local emitter = Instance.new("ParticleEmitter")
		emitter.Enabled = false -- bursts only (Emit)
		emitter.Rate = 0
		emitter.Lifetime = NumberRange.new(0.6, 1.1)
		emitter.Speed = NumberRange.new(8, 14)
		emitter.SpreadAngle = Vector2.new(180, 180)
		emitter.Drag = 4
		emitter.LightEmission = 0.8
		emitter.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.5), NumberSequenceKeypoint.new(1, 0) })
		emitter.Parent = attachment
		view.Emitter = emitter
	end
	local anchor = findPart(model, "PromptAnchor")
	if anchor ~= nil then
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

	views[model] = view
	model.AttributeChanged:Connect(function()
		queueApply(view)
	end)
	applyState(view)
	view.SeenSeq = attr(view, "ResultSeq") or 0 -- results that finished earlier are not re-announced
end

local function untrack(model: Instance)
	local view = views[model :: Model]
	if view ~= nil then
		resetMotion(view)
		if view.LoopSound ~= nil then
			view.LoopSound:Destroy()
		end
		views[model :: Model] = nil
	end
end

function MachineController.Start()
	task.spawn(function()
		local gui = Instance.new("ScreenGui")
		gui.Name = "JunkshotMachine"
		gui.ResetOnSpawn = false
		gui.ScreenInsets = Enum.ScreenInsets.CoreUISafeInsets
		gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
		gui.DisplayOrder = 8
		panel = Panel.Mount(gui, actions, durationFor)
		reveal = RewardReveal.Mount(gui)
		gui.Parent = localPlayer:WaitForChild("PlayerGui")

		for _, name in { "MachineRecycle", "MachineCraft", "MachineMythic", "MachineAccelerate", "MachineTake", "MachineUpgrade" } do
			remotes[name] = Remotes.GetEvent(name)
		end

		CollectionService:GetInstanceAddedSignal(MachineConfig.Tag):Connect(track)
		CollectionService:GetInstanceRemovedSignal(MachineConfig.Tag):Connect(untrack)
		for _, model in CollectionService:GetTagged(MachineConfig.Tag) do
			track(model)
		end

		-- One ticker for every machine screen and the open panel (no per-frame work).
		while true do
			task.wait(1)
			for _, view in views do
				if attr(view, "State") == "Processing" then
					updateScreen(view)
				end
			end
			local currentPanel = panel
			if currentPanel ~= nil and currentPanel.IsOpen() then
				currentPanel.Tick()
			end
		end
	end)

	ProximityPromptService.PromptTriggered:Connect(function(prompt: ProximityPrompt, player: Player)
		if player == localPlayer and prompt:GetAttribute("PromptKind") == "Machine"
			and prompt:GetAttribute("OwnerUserId") == localPlayer.UserId
		then
			openPanel()
		end
	end)
	ProximityPromptService.PromptHidden:Connect(function(prompt: ProximityPrompt)
		-- Walking away closes the panel. Roblox also re-shows prompts when the input type
		-- changes, so only an actual distance from the machine counts.
		local currentPanel = panel
		local view = ownView()
		local anchor = prompt.Parent
		if currentPanel == nil or view == nil or not currentPanel.IsOpen() or not prompt:IsDescendantOf(view.Model) then
			return
		end
		local character = localPlayer.Character
		local root = character and character:FindFirstChild("HumanoidRootPart")
		if root == nil or not root:IsA("BasePart") or not anchor:IsA("BasePart")
			or (root.Position - anchor.Position).Magnitude > MachineConfig.PromptDistance + 6
		then
			currentPanel.Close()
		end
	end)
	CarryController.Changed:Connect(renderPanel)
	DataController.Changed:Connect(renderPanel)
end

return MachineController
