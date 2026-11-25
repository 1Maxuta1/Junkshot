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
	  8b. PlacementService       functional items: place / store / use (+ Services/Behaviors/*)
	  8c. Economy (Stage 3)      Progression, Dealer (booth), PlayerUpgrades, Sell, Shop, Storage;
	                             EconomyService has no Start (it is a library over CurrencyService)
	  8d. Bases & audio (4)      BaseService (chest, slots, buildings, Bases/Conveyor), AudioService
	  8e. World & looks          WorldService (day cycle, sky), LeaderboardService, Cosmetics, Companions
	  8f. World events         WorldEventService (Rare Creature every 5 min), RaceService (hourly), TradeService
	  8g. OnboardingService     the tutorial of new players; DailyService daily reward and quests
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
local CurrencyService = require(Services.CurrencyService)
local ThrowService = require(Services.ThrowService)
local PlotService = require(Services.PlotService)
local MachineService = require(Services.MachineService)
local MonetizationService = require(Services.MonetizationService)
local PlacementService = require(Services.PlacementService)
local PaintService = require(Services.PaintService)
local ProgressionService = require(Services.ProgressionService)
local DealerService = require(Services.DealerService)
local PlayerUpgradeService = require(Services.PlayerUpgradeService)
local SellService = require(Services.SellService)
local ShopService = require(Services.ShopService)
local StorageService = require(Services.StorageService)
local BaseService = require(Services.BaseService)
local AudioService = require(Services.AudioService)
local WorldService = require(Services.WorldService)
local LeaderboardService = require(Services.LeaderboardService)
local CosmeticsService = require(Services.CosmeticsService)
local CompanionService = require(Services.CompanionService)
local WorldEventService = require(Services.WorldEventService)
local RaceService = require(Services.RaceService)
local TradeService = require(Services.TradeService)
local OnboardingService = require(Services.OnboardingService)
local DailyService = require(Services.DailyService)

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
PaintService.Start() -- before PlacementService: it paints what is placed
PlacementService.Start()
ProgressionService.Start()
DealerService.Start()
PlayerUpgradeService.Start()
SellService.Start()
ShopService.Start()
StorageService.Start()
BaseService.Start()
AudioService.Start()
WorldService.Start()
LeaderboardService.Start()
CosmeticsService.Start()
CompanionService.Start()
WorldEventService.Start()
RaceService.Start()
TradeService.Start()
OnboardingService.Start()
DailyService.Start()
DataService.Start()

-- DevTests move the test player around (machine, plot, junk) for about a minute, so they only
-- run when asked: GameConfig.Debug.EnableDevTests, or the attribute RunDevTests = true on
-- ServerScriptService (set it in Studio's Properties window / command bar before pressing Play).
local runDevTests = RunService:IsStudio()
	and (GameConfig.Debug.EnableDevTests or ServerScriptService:GetAttribute("RunDevTests") == true)
if runDevTests then
	task.spawn(function()
		require(script.Parent.DevTests).Run()
	end)
end

-- Studio-only bridge for multi-client tests: external test code cannot share these module
-- instances and cannot press keys in secondary client windows, so it asks the live services
-- through this BindableFunction. Server-only (BindableFunctions never cross the network).
-- Also available without the tests via the ServerScriptService attribute DebugBridge = true.
if runDevTests or (RunService:IsStudio() and ServerScriptService:GetAttribute("DebugBridge") == true) then
	local bridge = Instance.new("BindableFunction")
	bridge.Name = "JunkshotDebugBridge"
	bridge.OnInvoke = function(action: string, player: Player, arg: any): any
		if action == "Pickup" then
			return CarryService.TryPickup(player, arg)
		elseif action == "GrantPass" then
			return MonetizationService.ApplyPass(player, arg) -- visual checks only; real ownership is never faked
		elseif action == "Klunks" then
			return CurrencyService.AddKlunks(player, arg)
		elseif action == "Give" then
			return CarryService.AddJunk(player, arg)
		elseif action == "Remaining" then
			return MachineService.GetRemaining(player)
		elseif action == "SpawnCreature" then
			return WorldEventService.SpawnNow(nil, arg) -- arg: optional ground position
		elseif action == "ClaimCreature" then
			return WorldEventService.TryClaim(player, WorldEventService.GetActive())
		elseif action == "OpenRace" then
			task.spawn(RaceService.Open, arg)
			return true
		elseif action == "SpawnItem" then
			return JunkService.SpawnAt(arg.Id, arg.Position, { Yaw = 0 })
		elseif action == "TestProfile" then -- only for a TestStore session: fresh profile, endless money
			if ServerScriptService:GetAttribute("TestStore") ~= true then
				return false
			end
			local data = DataService.GetData(player) :: any
			data.Progress.Level = 1
			data.Progress.XP = 0
			data.PlayerUpgrades = {}
			data.Machine.Upgrades = { Speed = 1, Storage = 1, Level = 1 }
			OnboardingService.Skip(player)
			CurrencyService.AddKlunks(player, arg or 100000)
			MachineService.Unload(player)
			MachineService.Load(player)
			return true
		elseif action == "ResetOnboarding" then
			local data = DataService.GetData(player) :: any
			data.Onboarding = { Step = 1, Progress = 0, Done = false }
			return true
		elseif action == "JoinRace" then
			return RaceService.Join(player)
		elseif action == "Trade" then
			return (TradeService :: any)[arg.Fn](player, table.unpack(arg.Args))
		elseif action == "DespawnCreature" then
			return WorldEventService.Despawn()
		end
		return nil
	end
	bridge.Parent = game:GetService("ServerStorage")
end

print("[Main] JUNKSHOT server started")
