--!strict
--[[
	WorldConfig: the winter atmosphere (WorldService on the server, WeatherController on clients).

	Day cycle   ClockTime runs from DayStart to DayEnd during DayMinutes (a long bright winter
	            day with a golden evening), then through a short starry night back to the
	            morning during NightMinutes. One server loop; ClockTime replicates by itself.
	            Night is kept readable (bluish ambient), never pitch black.
	Sky         stars and soft clouds.
	Snowfall    a light client-side snowfall around the camera (one emitter, cheap).
]]

local WorldConfig = {
	DayCycle = {
		Enabled = true,
		DayStart = 8.5, -- hours
		DayEnd = 18.5,
		DayMinutes = 14, -- real minutes from DayStart to DayEnd
		NightMinutes = 4, -- real minutes from DayEnd round to the next DayStart
		UpdateSeconds = 1,
		DayAmbient = Color3.fromRGB(120, 140, 176),
		NightAmbient = Color3.fromRGB(70, 86, 130),
		DayOutdoor = Color3.fromRGB(140, 163, 204),
		NightOutdoor = Color3.fromRGB(96, 112, 168),
		DayBrightness = 2.6,
		NightBrightness = 1.4,
	},
	Bloom = { Intensity = 0.15, Size = 20, Threshold = 1.9 }, -- the glow of neon and bright parts
	Sky = {
		StarCount = 4000,
		SunAngularSize = 14,
		MoonAngularSize = 9,
		CloudCover = 0.55,
		CloudDensity = 0.6,
		CloudColor = Color3.fromRGB(235, 242, 255),
	},
	Snow = {
		Enabled = true,
		Rate = 35, -- flakes per second around the camera
		Area = 90, -- studs: width of the snowing area above the camera
		Height = 45, -- studs above the camera where flakes start
		Texture = "rbxasset://textures/particles/sparkles_main.dds", -- ships with the client
	},
}

return table.freeze(WorldConfig)
