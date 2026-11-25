--!strict
--[[
	LeaderboardController: movement on the plaza leaderboards (built by Services/Leaderboard/Board).

	  bulbs run around the frame, rays turn behind the winner, the winner's card pulses, the
	  crown floats and turns, sparks when somebody takes first place, your own place is marked.
	Local only, only close to the camera; with Lite graphics only the mark.
]]

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local LeaderboardController = {}

local RANGE = 110
local BULB_STEP = 0.25 -- seconds between bulb changes
local localPlayer = Players.LocalPlayer
local rgb = Color3.fromRGB
local LIT, DIM = rgb(255, 244, 190), rgb(150, 104, 30)

type View = {
	Model: Model,
	Center: Vector3,
	Bulbs: { BasePart },
	Crown: Model?,
	CrownRest: CFrame,
	Rays: { GuiObject },
	Strokes: { UIStroke },
}
local views: { [Instance]: View } = {}

-- Green border and the word YOU on your own card or row.
local function mark(slot: Instance)
	local mine = slot:GetAttribute("UserId") == localPlayer.UserId
	local old = slot:FindFirstChild("Mine")
	if mine and old == nil then
		local border = Instance.new("UIStroke")
		border.Name = "MineStroke"
		border.Color = rgb(90, 255, 140)
		border.Thickness = 4
		border.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
		local tag = Instance.new("TextLabel")
		tag.Name = "Mine"
		tag.AnchorPoint = Vector2.new(1, 0)
		tag.Position = UDim2.new(1, -4, 0, 4)
		tag.Size = UDim2.fromOffset(54, 24)
		tag.BackgroundColor3 = rgb(50, 200, 100)
		tag.Font = Enum.Font.FredokaOne
		tag.Text = "YOU"
		tag.TextColor3 = Color3.new(1, 1, 1)
		tag.TextScaled = true
		local round = Instance.new("UICorner")
		round.CornerRadius = UDim.new(0, 8)
		round.Parent = tag
		if string.sub(slot.Name, 1, 3) == "Row" then
			tag.AnchorPoint = Vector2.new(0, 0.5)
			tag.Position = UDim2.new(1, -290, 0.5, 0)
		end
		border.Parent = slot
		tag.Parent = slot
	elseif not mine and old ~= nil then
		old:Destroy()
		local border = slot:FindFirstChild("MineStroke")
		if border ~= nil then
			border:Destroy()
		end
	end
end

local function collect(model: Model): View
	local crown = model:FindFirstChild("Crown")
	local view: View = {
		Model = model,
		Center = model:GetPivot().Position,
		Bulbs = {},
		Crown = if crown ~= nil and crown:IsA("Model") then crown else nil,
		CrownRest = if crown ~= nil and crown:IsA("Model") then crown:GetPivot() else CFrame.new(),
		Rays = {},
		Strokes = {},
	}
	for _, d in model:GetDescendants() do
		if d:IsA("BasePart") and d.Name == "Bulb" then
			table.insert(view.Bulbs, d)
		elseif d:IsA("GuiObject") and d.Name == "Rays" then
			table.insert(view.Rays, d)
		elseif d:IsA("GuiObject") and d.Name == "Card1" then
			local s = d:FindFirstChildOfClass("UIStroke")
			if s ~= nil then
				table.insert(view.Strokes, s)
			end
		end
	end
	-- Around the frame, so the light runs.
	table.sort(view.Bulbs, function(a, b)
		local up = view.Center + Vector3.yAxis * 9.2
		local pa, pb = a.Position - up, b.Position - up
		local right = model:GetPivot().RightVector
		return math.atan2(pa.Y, pa:Dot(right)) < math.atan2(pb.Y, pb:Dot(right))
	end)
	return view
end

local function add(model: Instance)
	if not model:IsA("Model") or views[model] ~= nil then
		return
	end
	task.wait(1) -- its parts may still be streaming in
	if not model:IsDescendantOf(Workspace) then
		return
	end
	views[model] = collect(model)
	local function slot(d: Instance)
		if d:IsA("Frame") and (string.match(d.Name, "^Card%d$") ~= nil or string.match(d.Name, "^Row%d+$") ~= nil) then
			d:GetAttributeChangedSignal("UserId"):Connect(function()
				mark(d)
			end)
			mark(d)
		end
	end
	for _, d in model:GetDescendants() do
		slot(d)
	end
	model.DescendantAdded:Connect(function(d: Instance)
		task.defer(slot, d)
		if d.Name == "Bulb" or d.Name == "Crown" or d.Name == "Rays" then -- streamed in later
			views[model] = collect(model)
		end
	end)
	model:GetAttributeChangedSignal("LeaderId"):Connect(function()
		local crown = model:FindFirstChild("Crown")
		local emitter = if crown ~= nil then crown:FindFirstChild("Sparkle", true) else nil
		if emitter ~= nil and emitter:IsA("ParticleEmitter") then
			emitter:Emit(40)
		end
	end)
end

local sinceBulbs, phase = 0, 0
local function step(dt: number)
	local camera = Workspace.CurrentCamera
	if camera == nil or localPlayer:GetAttribute("LiteGraphics") == true then
		return
	end
	local now = os.clock()
	sinceBulbs += dt
	local change = sinceBulbs >= BULB_STEP
	if change then
		sinceBulbs = 0
		phase += 1
	end
	for model, view in views do
		if not model:IsDescendantOf(Workspace) then
			views[model] = nil
			continue
		end
		if (camera.CFrame.Position - view.Center).Magnitude > RANGE then
			continue
		end
		if change then
			for index, bulb in view.Bulbs do
				bulb.Color = if (index + phase) % 6 < 3 then LIT else DIM -- pairs: front and back
			end
		end
		if view.Crown ~= nil then
			view.Crown:PivotTo(CFrame.new(0, math.sin(now * 2) * 0.22, 0) * CFrame.new(view.CrownRest.Position) * CFrame.Angles(0, now * 0.9 % (math.pi * 2), 0) * view.CrownRest.Rotation)
		end
		for _, rays in view.Rays do
			rays.Rotation = now * 12 % 360
		end
		for _, s in view.Strokes do
			s.Thickness = 5 + math.sin(now * 3) * 2
			s.Color = rgb(255, 205, 60):Lerp(rgb(255, 250, 220), 0.5 + 0.5 * math.sin(now * 3))
		end
	end
end

function LeaderboardController.Start()
	for _, model in CollectionService:GetTagged("PlazaBoard") do
		task.spawn(add, model)
	end
	CollectionService:GetInstanceAddedSignal("PlazaBoard"):Connect(add)
	RunService.Heartbeat:Connect(step)
end

return LeaderboardController
