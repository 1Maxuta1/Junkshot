--!strict
--[[
	Main.server: the single server entry point.

	Startup order matters:
	  1. Remotes.Init()          create the remotes the services will bind to
	  2. ReplicationService      bind remotes + listen to data changes
	  3. JunkService             world items (spawning, reservations)
	  4. CarryService            carried items (restored from the profile on PlayerLoaded)
	  5. ThrowService            ThrowRequest remote
	  6. PlotService             gives each loaded player a base plot
	  7. MachineService          personal machines (built when a plot is assigned)
	  8. MonetizationService     optional Robux receipts / passes (placeholders)
	  9. DataService.Start()     LAST: begins loading profiles, which fires PlayerLoaded, and
	                             every listener above must already be connected

	ServerScriptService.Server is a plain Folder, so this is the only Script that runs. The
	guard below still turns an accidental second bootstrap into a visible warning.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local ServerScriptService = game:GetService("ServerScriptService")

if ServerScriptService:GetAttribute("JunkshotBooted") == true then
	warn("[Main] Server bootstrap already ran. Is there a second server entry script?")
	return
end
ServerScriptService:SetAttribute("JunkshotBooted", true)

local GameConfig = require(ReplicatedStorage.Shared.Config.GameConfig)
local Remotes = require(ReplicatedStorage.Shared.Remotes)

local Services = script.Parent.Services
local DataService = require(Services.DataService)
local ReplicationService = require(Services.ReplicationService)
local JunkService = require(Services.JunkService)
local CarryService = require(Services.CarryService)
local ThrowService = require(Services.ThrowService)
local PlotService = require(Services.PlotService)
local MachineService = require(Services.MachineService)
local MonetizationService = require(Services.MonetizationService)

Remotes.Init()
-- Listeners of DataService.PlayerLoaded must exist before the first profile can load, so the
-- services that use it start first; DataService starts loading profiles last.
ReplicationService.Start()
JunkService.Start()
CarryService.Start()
ThrowService.Start()
PlotService.Start()
MachineService.Start()
MonetizationService.Start()
DataService.Start()

if GameConfig.Debug.EnableDevTests and RunService:IsStudio() then
	task.spawn(function()
		require(script.Parent.DevTests).Run()
	end)
end

-- Studio-only bridge for multi-client tests: external test code cannot share these module
-- instances and cannot press keys in secondary client windows, so it asks the live services
-- through this BindableFunction. Server-only (BindableFunctions never cross the network).
if GameConfig.Debug.EnableDevTests and RunService:IsStudio() then
	local bridge = Instance.new("BindableFunction")
	bridge.Name = "JunkshotDebugBridge"
	bridge.OnInvoke = function(action: string, player: Player, arg: any): any
		if action == "Pickup" then
			return CarryService.TryPickup(player, arg)
		elseif action == "Remaining" then
			return MachineService.GetRemaining(player)
		end
		return nil
	end
	bridge.Parent = game:GetService("ServerStorage")
end

print("[Main] JUNKSHOT server started")
