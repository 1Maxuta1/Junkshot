--!strict
--[[
	Main.server: the single server entry point.

	Startup order matters:
	  1. Remotes.Init()        create the remotes the services will bind to
	  2. DataService.Start()   begin loading profiles
	  3. ReplicationService    bind remotes + listen to data changes
	  4. JunkService           spawn junk in the world (Workspace.Map is part of the place)
	  5. CarryService          pickup + carry list (listens to JunkService)
	  6. ThrowService          ThrowRequest remote (uses CarryService and JunkService)
	  7. MachineService        Recycling Machines (uses CarryService, RewardService, DataService)

	ServerScriptService.Server is a plain Folder (there is no init.server.luau), so this is the
	only Script that runs. The guard below still turns an accidental second bootstrap into a
	visible warning.
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

local DataService = require(script.Parent.Services.DataService)
local ReplicationService = require(script.Parent.Services.ReplicationService)
local JunkService = require(script.Parent.Services.JunkService)
local CarryService = require(script.Parent.Services.CarryService)
local ThrowService = require(script.Parent.Services.ThrowService)
local MachineService = require(script.Parent.Services.MachineService)

Remotes.Init()
DataService.Start()
ReplicationService.Start()
JunkService.Start()
CarryService.Start() -- after JunkService: it listens to JunkService.PickupRequested
ThrowService.Start() -- after CarryService: it takes junk out of carry lists
MachineService.Start() -- after CarryService and DataService

if GameConfig.Debug.EnableDevTests and RunService:IsStudio() then
	task.spawn(function()
		require(script.Parent.DevTests).Run()
	end)
end

print("[Main] JUNKSHOT server started")
