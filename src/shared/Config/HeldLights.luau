--!strict
--[[
	HeldLights: items that glow while they are the selected item in somebody's hand
	(client/CarryController). Spot = a flashlight cone instead of a glow all around.
]]

local function rgb(r: number, g: number, b: number): Color3
	return Color3.fromRGB(r, g, b)
end

export type HeldLight = { Color: Color3, Range: number, Brightness: number, Spot: boolean? }

local HeldLights: { [string]: HeldLight } = {
	broken_lamp = { Color = rgb(255, 220, 150), Range = 12, Brightness = 0.8 },
	frost_lantern = { Color = rgb(150, 215, 255), Range = 18, Brightness = 1.2 },
	plasma_toaster = { Color = rgb(255, 120, 220), Range = 14, Brightness = 1 },
	neon_gear = { Color = rgb(80, 255, 200), Range = 10, Brightness = 0.7 },
	crystal_shard = { Color = rgb(180, 130, 255), Range = 10, Brightness = 0.7 },
	aurora_orb = { Color = rgb(120, 255, 200), Range = 18, Brightness = 1.2 },
	starforged_core = { Color = rgb(255, 220, 120), Range = 18, Brightness = 1.2 },
	comet_shard = { Color = rgb(150, 200, 255), Range = 16, Brightness = 1.1 },
	toxic_barrel = { Color = rgb(140, 255, 90), Range = 8, Brightness = 0.5 },
	flashlight = { Color = rgb(255, 245, 210), Range = 45, Brightness = 3, Spot = true },
}

return table.freeze(HeldLights)
