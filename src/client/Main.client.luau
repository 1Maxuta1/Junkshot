--!strict
--[[
	Main.client: the single client entry point.

	Loads every controller listed in CONTROLLER_NAMES (siblings of this script inside
	StarterPlayerScripts.Client) and calls controller.Start() on each.

	Controller contract:
	  - a ModuleScript returning a table with a Start() function
	  - Start() must NOT yield; do waiting work inside task.spawn
	  - a controller that fails to load or start is reported, and the others still start

	Order matters only for Start(): a controller may use another controller's API inside
	Start() only if that one is listed earlier.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

-- Make sure shared code has replicated before any controller requires it.
ReplicatedStorage:WaitForChild("Shared")

local CONTROLLER_NAMES = {
	"DataController",
	"NotifyController",
	"CarryController",
	"InputController",
	"ThrowController",
	"UI",
	"MachineController",
	"ItemController",
	"EconomyController",
	"BaseController",
	"AudioController",
	"WeatherController",
	"CompanionController",
	"ShopController",
	"CreatureController",
	"RaceController",
	"TradeController",
	"GadgetController",
	"OnboardingController",
	"DailyController",
	"SfxController",
	"GraphicsController",
}

for _, name in CONTROLLER_NAMES do
	local moduleScript = script.Parent:WaitForChild(name, 10)
	if moduleScript == nil or not moduleScript:IsA("ModuleScript") then
		warn(`[Main.client] controller "{name}" not found or not a ModuleScript`)
		continue
	end

	local requireOk, controller = xpcall(require, debug.traceback, moduleScript)
	if not requireOk then
		warn(`[Main.client] failed to load {name}: {tostring(controller)}`)
		continue
	end

	if type(controller) ~= "table" or type(controller.Start) ~= "function" then
		warn(`[Main.client] {name} has no Start() function`)
		continue
	end

	local startOk, startErr = xpcall(controller.Start, debug.traceback)
	if not startOk then
		warn(`[Main.client] {name}.Start() failed: {tostring(startErr)}`)
	end
end

print("[Main.client] JUNKSHOT client started")
