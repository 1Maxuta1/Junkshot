--!strict
--[[
	WorldService: the winter atmosphere on the server (Config/WorldConfig): the day cycle
	(long winter day, golden evening, short starry night) and the sky (stars, clouds).
	Lighting changes replicate to every client by themselves; one loop, once per second.
	Lighting's base look (atmosphere, colour correction, bloom) stays in default.project.json.
]]

local Lighting = game:GetService("Lighting")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local WorldConfig = require(ReplicatedStorage.Shared.Config.WorldConfig)

local WorldService = {}

local started = false

local function setupSky()
	local config = WorldConfig.Sky
	local sky = Lighting:FindFirstChildOfClass("Sky")
	if sky == nil then
		sky = Instance.new("Sky")
		sky.Name = "WinterSky"
		sky.Parent = Lighting
	end
	local s = sky :: Sky
	s.StarCount = config.StarCount
	s.SunAngularSize = config.SunAngularSize
	s.MoonAngularSize = config.MoonAngularSize
	s.CelestialBodiesShown = true

	local terrain = Workspace:FindFirstChildOfClass("Terrain")
	if terrain ~= nil and terrain:FindFirstChildOfClass("Clouds") == nil then
		local clouds = Instance.new("Clouds")
		clouds.Cover = config.CloudCover
		clouds.Density = config.CloudDensity
		clouds.Color = config.CloudColor
		clouds.Parent = terrain
	end
end

-- 0 = full day, 1 = full night (smooth around dusk and dawn).
local function nightAmount(clock: number): number
	local config = WorldConfig.DayCycle
	local function ramp(value: number, from: number, to: number): number
		return math.clamp((value - from) / (to - from), 0, 1)
	end
	if clock >= config.DayEnd - 1 then
		return ramp(clock, config.DayEnd - 1, config.DayEnd + 0.5)
	elseif clock <= config.DayStart then
		return 1 - ramp(clock, config.DayStart - 1, config.DayStart)
	end
	return 0
end

-- The time of day for a moment of the cycle (seconds since the server started).
function WorldService.ClockAt(seconds: number): number
	local config = WorldConfig.DayCycle
	local day = config.DayMinutes * 60
	local night = config.NightMinutes * 60
	local t = seconds % (day + night)
	if t < day then
		return config.DayStart + (config.DayEnd - config.DayStart) * (t / day)
	end
	local nightHours = 24 - (config.DayEnd - config.DayStart)
	return (config.DayEnd + nightHours * ((t - day) / night)) % 24
end

local function apply(clock: number)
	local config = WorldConfig.DayCycle
	local n = nightAmount(clock)
	Lighting.ClockTime = clock
	Lighting.Ambient = config.DayAmbient:Lerp(config.NightAmbient, n)
	Lighting.OutdoorAmbient = config.DayOutdoor:Lerp(config.NightOutdoor, n)
	Lighting.Brightness = config.DayBrightness + (config.NightBrightness - config.DayBrightness) * n
end

function WorldService.Start()
	assert(not started, "[WorldService] Start() called twice")
	started = true
	setupSky()
	if not WorldConfig.DayCycle.Enabled then
		return
	end
	local startedAt = os.clock()
	task.spawn(function()
		while true do
			apply(WorldService.ClockAt(os.clock() - startedAt))
			task.wait(WorldConfig.DayCycle.UpdateSeconds)
		end
	end)
end

return WorldService
