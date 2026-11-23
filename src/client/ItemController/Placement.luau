--!strict
--[[
	Placement: the see-through preview when placing a functional item.

	The preview stands PreviewDistance studs in front of the character, facing where the
	character faces (vehicles point forward), and turns green / red using the SAME rules the
	server checks (Util/PlacementRules), with the reason shown under the buttons.

	  Confirm  G / left mouse / R2 / PLACE button   -> ItemPlace(uid, groundPosition, yaw)
	  Cancel   Q / B / CANCEL button
	It also ends by itself when the item leaves the hands, a menu opens, the character dies
	or sits down. Throwing is blocked while placing.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local GameConfig = require(ReplicatedStorage.Shared.Config.GameConfig)
local ItemConfig = require(ReplicatedStorage.Shared.Config.ItemConfig)
local Remotes = require(ReplicatedStorage.Shared.Remotes)
local DeployModels = require(ReplicatedStorage.Shared.Util.DeployModels)
local PlacementRules = require(ReplicatedStorage.Shared.Util.PlacementRules)

local InputController = require(script.Parent.Parent.InputController)
local NotifyController = require(script.Parent.Parent.NotifyController)
local Theme = require(script.Parent.Parent.UI.Theme)

local Placement = {}

local VALID_COLOR = Color3.fromRGB(70, 230, 120)
local INVALID_COLOR = Color3.fromRGB(240, 70, 70)

local localPlayer = Players.LocalPlayer

local active: {
	Uid: string,
	Id: string,
	ModelName: string,
	Ghost: Model,
	Parts: { BasePart },
	Valid: boolean?,
	FacePlayer: boolean,
	Pivot: CFrame?,
	Yaw: number,
	Code: string?,
}? = nil
local renderConnection: RBXScriptConnection? = nil
local bar: Frame? = nil
local reasonLabel: TextLabel? = nil
local titleLabel: TextLabel? = nil
local onChanged: (() -> ())? = nil

local function liveRoot(): BasePart?
	local character = localPlayer.Character
	local humanoid = if character ~= nil then character:FindFirstChildOfClass("Humanoid") else nil
	local root = if character ~= nil then character:FindFirstChild("HumanoidRootPart") else nil
	if humanoid == nil or humanoid.Health <= 0 or root == nil or not root:IsA("BasePart") then
		return nil
	end
	return root
end

local function makeGhost(modelName: string): (Model, { BasePart })
	local ghost = DeployModels.Build(modelName, false)
	ghost.Name = "PlacementPreview"
	local visible: { BasePart } = {}
	for _, part in ghost:GetDescendants() do
		if part:IsA("BasePart") then
			part.Anchored = true
			part.CanCollide = false
			part.CanQuery = false
			part.CanTouch = false
			part.CastShadow = false
			if part.Transparency < 1 then
				part.Transparency = 0.4
				part.Material = Enum.Material.SmoothPlastic
				table.insert(visible, part)
			end
		end
	end
	ghost.Parent = Workspace.CurrentCamera
	return ghost, visible
end

local function update()
	local state = active
	if state == nil then
		return
	end
	local root = liveRoot()
	if root == nil then
		Placement.Cancel()
		return
	end
	local look = root.CFrame.LookVector
	local flat = Vector3.new(look.X, 0, look.Z)
	flat = if flat.Magnitude > 0.01 then flat.Unit else Vector3.new(0, 0, -1)
	local size = DeployModels.GetSize(state.ModelName)
	local position = root.Position + flat * (GameConfig.Placement.PreviewDistance + size.Z / 2)
	local yaw = math.atan2(-flat.X, -flat.Z) -- the model's front (-Z) faces where the player looks
	if state.FacePlayer then
		yaw += math.pi
	end
	local pivot, code = PlacementRules.Check({
		UserId = localPlayer.UserId,
		ModelName = state.ModelName,
		Position = position,
		Yaw = yaw,
		RootPosition = root.Position,
		Ignore = { state.Ghost },
	})
	state.Pivot, state.Yaw, state.Code = pivot, yaw, code
	if pivot ~= nil then
		state.Ghost:PivotTo(pivot)
	else
		local feet = root.Position.Y - 3
		state.Ghost:PivotTo(CFrame.new(position.X, feet, position.Z) * CFrame.Angles(0, yaw, 0))
	end
	local color = if pivot ~= nil then VALID_COLOR else INVALID_COLOR
	if state.Valid ~= (pivot ~= nil) then
		state.Valid = pivot ~= nil
		for _, part in state.Parts do
			part.Color = color
		end
	end
	if reasonLabel ~= nil then
		reasonLabel.Text = if pivot ~= nil then "Looks good!" else PlacementRules.Describe(code)
		reasonLabel.TextColor3 = if pivot ~= nil then Theme.Colors.Success else Theme.Colors.Danger
	end
end

local function hintText(): string
	local kind = InputController.GetInputKind()
	if kind == "Gamepad" then
		return "R2 / D-pad up: place  ·  B: cancel"
	elseif kind == "Touch" then
		return "Walk to choose a spot"
	end
	return `Click or {GameConfig.Input.UseKey.Name}: place  ·  {GameConfig.Input.CancelKey.Name}: cancel`
end

function Placement.IsActive(): boolean
	return active ~= nil
end

function Placement.GetUid(): string?
	return if active ~= nil then active.Uid else nil
end

function Placement.Start(uid: string, itemId: string, behavior: any)
	Placement.Cancel()
	if liveRoot() == nil then
		return
	end
	local ghost, parts = makeGhost(behavior.Model)
	active = {
		Uid = uid,
		Id = itemId,
		ModelName = behavior.Model,
		Ghost = ghost,
		Parts = parts,
		Valid = nil,
		FacePlayer = behavior.FacePlayer == true,
		Pivot = nil,
		Yaw = 0,
		Code = nil,
	}
	InputController.SetThrowBlocked("Placement", true)
	if bar ~= nil then
		bar.Visible = true
	end
	if titleLabel ~= nil then
		titleLabel.Text = `Place {ItemConfig.GetDisplayName(itemId)}  ·  {hintText()}`
	end
	renderConnection = RunService.RenderStepped:Connect(update)
	update()
	if onChanged ~= nil then
		onChanged()
	end
end

function Placement.Cancel()
	local state = active
	if state == nil then
		return
	end
	active = nil
	if renderConnection ~= nil then
		renderConnection:Disconnect()
		renderConnection = nil
	end
	state.Ghost:Destroy()
	if bar ~= nil then
		bar.Visible = false
	end
	-- Released one frame later, so the click that confirmed does not also start a throw.
	task.defer(function()
		if active == nil then
			InputController.SetThrowBlocked("Placement", false)
		end
	end)
	if onChanged ~= nil then
		onChanged()
	end
end

function Placement.Confirm()
	local state = active
	if state == nil then
		return
	end
	update()
	if state.Pivot == nil then
		NotifyController.Show(PlacementRules.Describe(state.Code), "Warning")
		return
	end
	Remotes.GetEvent("ItemPlace"):FireServer(state.Uid, state.Pivot.Position, state.Yaw)
	Placement.Cancel()
end

local function button(parent: Instance, name: string, text: string, color: Color3, position: UDim2): TextButton
	local b = Instance.new("TextButton")
	b.Name = name
	b.AnchorPoint = Vector2.new(0.5, 0)
	b.Position = position
	b.Size = UDim2.new(0.3, 0, 0, 48)
	b.BackgroundColor3 = color
	b.Text = ""
	b.AutoButtonColor = true
	Theme.Corner(b, UDim.new(0, 12))
	Theme.Stroke(b, Theme.Colors.Ink, 2.5)
	local label = Theme.Label({
		Name = "Label",
		Text = text,
		Size = UDim2.fromScale(0.9, 0.7),
		Position = UDim2.fromScale(0.5, 0.5),
		AnchorPoint = Vector2.new(0.5, 0.5),
		Color = Theme.Colors.White,
		MinTextSize = 14,
		MaxTextSize = 24,
		Parent = b,
	})
	Theme.TextStroke(label, Theme.Colors.Ink, 1.5)
	b.Parent = parent
	return b
end

function Placement.Mount(screenGui: ScreenGui, changed: () -> ())
	onChanged = changed
	local frame = Instance.new("Frame")
	frame.Name = "PlacementBar"
	frame.AnchorPoint = Vector2.new(0.5, 0)
	frame.Position = UDim2.new(0.5, 0, 0, 8)
	frame.Size = UDim2.new(0.5, 0, 0, 120)
	frame.BackgroundColor3 = Theme.Colors.Panel
	frame.Visible = false
	Theme.Corner(frame, UDim.new(0, 16))
	Theme.Stroke(frame, Theme.Colors.Ink, 3)
	local limit = Instance.new("UISizeConstraint")
	limit.MinSize = Vector2.new(300, 120)
	limit.MaxSize = Vector2.new(560, 120)
	limit.Parent = frame
	frame.Parent = screenGui

	titleLabel = Theme.Label({
		Name = "Title",
		Text = "",
		Size = UDim2.new(0.94, 0, 0, 22),
		Position = UDim2.new(0.5, 0, 0, 8),
		AnchorPoint = Vector2.new(0.5, 0),
		Font = Theme.FontBody,
		MinTextSize = 11,
		MaxTextSize = 16,
		Parent = frame,
	})
	local place = button(frame, "Place", "PLACE", Theme.Colors.Success, UDim2.new(0.3, 0, 0, 36))
	local cancel = button(frame, "Cancel", "CANCEL", Theme.Colors.Danger, UDim2.new(0.7, 0, 0, 36))
	reasonLabel = Theme.Label({
		Name = "Reason",
		Text = "",
		Size = UDim2.new(0.94, 0, 0, 20),
		Position = UDim2.new(0.5, 0, 0, 90),
		AnchorPoint = Vector2.new(0.5, 0),
		Font = Theme.FontBody,
		MinTextSize = 11,
		MaxTextSize = 16,
		Parent = frame,
	})
	bar = frame
	place.Activated:Connect(Placement.Confirm)
	cancel.Activated:Connect(Placement.Cancel)

	UserInputService.InputBegan:Connect(function(input: InputObject, gameProcessed: boolean)
		if active == nil or gameProcessed then
			return
		end
		if input.KeyCode == GameConfig.Input.CancelKey or input.KeyCode == GameConfig.Input.CancelGamepadKey then
			Placement.Cancel()
		elseif input.KeyCode == GameConfig.Input.ConfirmGamepadKey or input.UserInputType == Enum.UserInputType.MouseButton1 then
			Placement.Confirm()
		end
	end)
	InputController.MenuChanged:Connect(function(open: boolean)
		if open then
			Placement.Cancel()
		end
	end)
end

return Placement
