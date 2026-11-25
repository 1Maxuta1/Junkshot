--!strict
--[[
	Paint: recolors the painted parts of a placed object (Util/DeployModels). Shared: the server
	paints the real object, the client the preview in the paint window.

	  ITEM               the item id that paints (used up by one coat)
	  Apply(model, color?)   nil = the original color
	  ToHex(color) / FromHex(text)

	Painted = the color that covers the most surface of the model, colorful ones first; glass,
	lights, wheels and invisible parts never count. The parts are remembered in the attribute
	PaintOriginal, so painting again or taking the paint off always works on the same parts.
]]

local Paint = {}

Paint.ITEM = "paint_bucket"

local ORIGINAL = "PaintOriginal"
local COLORFUL = 0.3 -- saturation from which a color beats grey and black

local function paintable(part: BasePart): boolean
	return part.Transparency < 0.5
		and part.Material ~= Enum.Material.Neon
		and part.Material ~= Enum.Material.Glass
		and part:GetAttribute("Spin") == nil
		and not part:IsA("Seat")
		and not part:IsA("VehicleSeat")
end

local function collect(model: Model): { BasePart }
	local known: { BasePart } = {}
	local groups: { [string]: { Color: Color3, Area: number, Parts: { BasePart } } } = {}
	for _, d in model:GetDescendants() do
		if not d:IsA("BasePart") then
			continue
		end
		if d:GetAttribute(ORIGINAL) ~= nil then
			table.insert(known, d)
		elseif paintable(d) then
			local key = d.Color:ToHex()
			local group = groups[key]
			if group == nil then
				group = { Color = d.Color, Area = 0, Parts = {} }
				groups[key] = group
			end
			local s = d.Size
			group.Area += s.X * s.Y + s.Y * s.Z + s.X * s.Z
			table.insert(group.Parts, d)
		end
	end
	if #known > 0 then
		return known
	end
	local best, bestScore = nil, -1
	for _, group in groups do
		local _, saturation, value = group.Color:ToHSV()
		local score = group.Area * (if saturation >= COLORFUL and value > 0.25 then 20 else 1)
		if score > bestScore then
			best, bestScore = group, score
		end
	end
	local parts = if best ~= nil then best.Parts else {}
	for _, part in parts do
		part:SetAttribute(ORIGINAL, part.Color)
	end
	return parts
end

function Paint.Apply(model: Model, color: Color3?)
	for _, part in collect(model) do
		local original = part:GetAttribute(ORIGINAL)
		if color ~= nil then
			part.Color = color
		elseif typeof(original) == "Color3" then
			part.Color = original
		end
	end
end

function Paint.ToHex(color: Color3): string
	return color:ToHex()
end

function Paint.FromHex(text: any): Color3?
	if type(text) ~= "string" or string.match(text, "^%x%x%x%x%x%x$") == nil then
		return nil
	end
	return Color3.fromHex(text)
end

return table.freeze(Paint)
