--!strict
--[[
	RarityVisuals: the one place that decides how rarity looks on 3D items.

	World items (JunkService adds these once per model; pooled models keep them)
	  Common     nothing
	  Uncommon+  a flat neon ring under the item in the rarity color
	  Epic+      + a thin translucent light beam (visible from far away)
	  Legendary+ + a few slow sparkles (ParticleEmitter, Rate 2-4)
	  Mythic     + a second ring in the secondary color
	Carried items have no effect (a box around them looked like a hitbox).

	Lightweight on purpose: no lights, no scripts, no per-frame work. The extra parts are
	anchored, non-colliding and non-queryable, so they never touch physics or raycasts.
	UI code uses Rarities.GetColor directly.
]]

local Rarities = require(script.Parent.Parent.Config.Rarities)
local ItemConfig = require(script.Parent.Parent.Config.ItemConfig)
local JunkFactory = require(script.Parent.JunkFactory)

local RarityVisuals = {}

local MARK = "RarityVisual"
local MYTHIC_SECOND = Color3.fromRGB(110, 230, 255)

local function effectPart(model: Model, name: string, shape: Enum.PartType, size: Vector3, cframe: CFrame, color: Color3, transparency: number): Part
	local part = Instance.new("Part")
	part.Name = name
	part.Shape = shape
	part.Size = size
	part.CFrame = cframe
	part.Color = color
	part.Material = Enum.Material.Neon
	part.Transparency = transparency
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.CastShadow = false
	part.Massless = true
	part.Parent = model
	return part
end

-- Adds the world effects to a freshly built "World" model (pivot at the item origin).
function RarityVisuals.ApplyWorld(model: Model, itemId: string)
	if model:GetAttribute(MARK) == true then
		return
	end
	model:SetAttribute(MARK, true)
	local info = Rarities.Get(ItemConfig.GetRarity(itemId) or "Common")
	local bounds = JunkFactory.GetBounds(itemId)
	if info == nil or bounds == nil or info.Effect < 1 then
		return
	end

	local pivot = model:GetPivot()
	local diameter = math.max(bounds.Size.X, bounds.Size.Z) + 1.2
	local ground = pivot * CFrame.new(0, bounds.Min.Y + 0.08, 0) * CFrame.Angles(0, 0, math.rad(90))
	local ring = effectPart(model, "RarityRing", Enum.PartType.Cylinder, Vector3.new(0.1, diameter, diameter), ground, info.Color, 0.6)

	if info.Effect >= 5 then
		local inner = diameter * 0.65
		effectPart(model, "RarityRing2", Enum.PartType.Cylinder, Vector3.new(0.12, inner, inner), ground, MYTHIC_SECOND, 0.55)
	end
	if info.Effect >= 3 then
		local height = 7
		effectPart(
			model,
			"RarityBeam",
			Enum.PartType.Cylinder,
			Vector3.new(height, 0.3, 0.3),
			pivot * CFrame.new(0, bounds.Min.Y + height / 2, 0) * CFrame.Angles(0, 0, math.rad(90)),
			info.Color,
			0.85
		)
	end
	if info.Effect >= 4 then
		local attachment = Instance.new("Attachment")
		attachment.Name = "RaritySparkles"
		attachment.Parent = ring
		local emitter = Instance.new("ParticleEmitter")
		emitter.Rate = if info.Effect >= 5 then 4 else 2
		emitter.Lifetime = NumberRange.new(1, 1.6)
		emitter.Speed = NumberRange.new(1.5, 3)
		emitter.SpreadAngle = Vector2.new(25, 25)
		emitter.EmissionDirection = Enum.NormalId.Right -- the ring's X axis points up
		emitter.LightEmission = 0.4
		emitter.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.35), NumberSequenceKeypoint.new(1, 0) })
		emitter.Color = if info.Effect >= 5 then ColorSequence.new(info.Color, MYTHIC_SECOND) else ColorSequence.new(info.Color)
		emitter.Parent = attachment
	end
end


return RarityVisuals
