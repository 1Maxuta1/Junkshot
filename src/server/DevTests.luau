--!strict
--[[
	DevTests: automated server-side checks (data, currency, inventory, junk, carry, throw).
	STUDIO ONLY.

	Enabled by GameConfig.Debug.EnableDevTests = true or the ServerScriptService attribute
	RunDevTests = true (Main.server also requires
	RunService:IsStudio()). It runs once against the first player who joins, prints
	PASS/FAIL lines and a summary.

	Recommended: also set Debug.UseMockStore = true so the tests never touch the real
	DataStore. Tests undo their own Klunks and inventory changes, except
	Stats.TotalKlunksEarned which only ever increases.

	Step 3 tests also spawn/claim real junk and TELEPORT the test player to a few junk objects
	(restored at the end).

	NOT covered here (manual, see README): profile release on leave, saving across sessions,
	failed profile load, RemoteGuard rate limits, dropping junk on death/leave, the carried
	junk visuals on the character, and the actual ProximityPrompt interaction.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local GameConfig = require(ReplicatedStorage.Shared.Config.GameConfig)
local DataService = require(script.Parent.Services.DataService)
local CurrencyService = require(script.Parent.Services.CurrencyService)
local InventoryService = require(script.Parent.Services.InventoryService)
local DropTables = require(ReplicatedStorage.Shared.Config.DropTables)
local Recipes = require(ReplicatedStorage.Shared.Config.Recipes)
local JunkFactory = require(ReplicatedStorage.Shared.Util.JunkFactory)
local JunkService = require(script.Parent.Services.JunkService)
local CarryService = require(script.Parent.Services.CarryService)
local ThrowService = require(script.Parent.Services.ThrowService)
local Ballistics = require(ReplicatedStorage.Shared.Util.Ballistics)
local Validate = require(ReplicatedStorage.Shared.Util.Validate)
local ItemConfig = require(ReplicatedStorage.Shared.Config.ItemConfig)
local MachineConfig = require(ReplicatedStorage.Shared.Config.MachineConfig)
local Rarities = require(ReplicatedStorage.Shared.Config.Rarities)
local MachineService = require(script.Parent.Services.MachineService)
local RewardService = require(script.Parent.Services.RewardService)
local CraftingService = require(script.Parent.Services.CraftingService)
local PlotService = require(script.Parent.Services.PlotService)
local MonetizationService = require(script.Parent.Services.MonetizationService)
local PlacementService = require(script.Parent.Services.PlacementService)
local VehicleBehavior = require(script.Parent.Services.Behaviors.Vehicle)
local CartBehavior = require(script.Parent.Services.Behaviors.Cart)
local RadioBehavior = require(script.Parent.Services.Behaviors.Radio)
local DetectorBehavior = require(script.Parent.Services.Behaviors.Detector)
local ItemCapabilities = require(ReplicatedStorage.Shared.Util.ItemCapabilities)
local PlacementRules = require(ReplicatedStorage.Shared.Util.PlacementRules)
local CollectionService = game:GetService("CollectionService")
-- Stage 3
local EconomyConfig = require(ReplicatedStorage.Shared.Config.EconomyConfig)
local Progression = require(ReplicatedStorage.Shared.Config.Progression)
local ShopConfig = require(ReplicatedStorage.Shared.Config.ShopConfig)
local ItemValue = require(ReplicatedStorage.Shared.Util.ItemValue)
local EconomyService = require(script.Parent.Services.EconomyService)
local DealerService = require(script.Parent.Services.DealerService)
local SellService = require(script.Parent.Services.SellService)
local ShopService = require(script.Parent.Services.ShopService)
local StorageService = require(script.Parent.Services.StorageService)
local PlayerUpgradeService = require(script.Parent.Services.PlayerUpgradeService)
local ProgressionService = require(script.Parent.Services.ProgressionService)
-- Stage 4
local BaseConfig = require(ReplicatedStorage.Shared.Config.BaseConfig)
local BaseService = require(script.Parent.Services.BaseService)
local ConveyorModule = require(script.Parent.Services.Bases.Conveyor)
local AudioService = require(script.Parent.Services.AudioService)
local CosmeticsService = require(script.Parent.Services.CosmeticsService)
local CompanionService = require(script.Parent.Services.CompanionService)
local WorldServiceModule = require(script.Parent.Services.WorldService)
local WorldEventService = require(script.Parent.Services.WorldEventService)
local WorldEventConfig = require(ReplicatedStorage.Shared.Config.WorldEventConfig)

local DevTests = {}

local passed = 0
local failed = 0

local function check(name: string, condition: boolean, detail: string?)
	if condition then
		passed += 1
		print(`[DevTests] PASS  {name}`)
	else
		failed += 1
		local suffix = ""
		if detail ~= nil then
			suffix = " (" .. detail .. ")"
		end
		warn(`[DevTests] FAIL  {name}{suffix}`)
	end
end

local function waitForPlayer(timeout: number): Player?
	local deadline = os.clock() + timeout
	while os.clock() < deadline do
		local player = Players:GetPlayers()[1]
		if player ~= nil then
			return player
		end
		task.wait(0.5)
	end
	return nil
end

local function runCurrencyTests(player: Player)
	local start = CurrencyService.GetKlunks(player)
	check("Klunks balance is retrievable", type(start) == "number")
	if start == nil then
		return
	end

	local addOk = CurrencyService.AddKlunks(player, 100)
	check("AddKlunks(100) succeeds", addOk)
	check("balance increased by 100", CurrencyService.GetKlunks(player) == start + 100)

	local removeOk = CurrencyService.RemoveKlunks(player, 40)
	check("RemoveKlunks(40) succeeds", removeOk)
	check("balance decreased by 40", CurrencyService.GetKlunks(player) == start + 60)
	check("HasEnough(60) is true", CurrencyService.HasEnough(player, 60))
	check("HasEnough(balance + 1) is false", not CurrencyService.HasEnough(player, start + 61))

	local balance = (CurrencyService.GetKlunks(player) :: number)
	local overOk, overErr = CurrencyService.RemoveKlunks(player, balance + 1)
	check(
		"removing more than the balance is rejected",
		not overOk and overErr == CurrencyService.Errors.InsufficientKlunks,
		tostring(overErr)
	)
	check("balance unchanged after rejected removal", CurrencyService.GetKlunks(player) == balance)

	local invalidAmounts: { any } = { 0, -5, 1.5, 0 / 0, math.huge, -math.huge, "100", true, {} }
	for _, amount in invalidAmounts do
		local a = CurrencyService.AddKlunks(player, amount)
		local r = CurrencyService.RemoveKlunks(player, amount)
		check(`invalid amount {tostring(amount)} rejected by Add and Remove`, not a and not r)
	end
	check("balance unchanged after invalid amounts", CurrencyService.GetKlunks(player) == balance)

	local capOk, capErr = CurrencyService.AddKlunks(player, GameConfig.Klunks.MaxBalance)
	check("exceeding the balance cap is rejected", not capOk and capErr == CurrencyService.Errors.BalanceCap, tostring(capErr))

	-- Undo: net +60 from this test.
	CurrencyService.RemoveKlunks(player, 60)
	check("balance restored to its starting value", CurrencyService.GetKlunks(player) == start)
end

local function runInventoryTests(player: Player)
	local startCount = InventoryService.GetItemCount(player)
	check("item count is retrievable", type(startCount) == "number")
	if startCount == nil then
		return
	end

	local uid, addErr = InventoryService.AddItem(player, "debug_rusty_gear")
	check("AddItem(debug_rusty_gear) succeeds", uid ~= nil, tostring(addErr))
	if uid == nil then
		return
	end

	local record = InventoryService.GetItem(player, uid)
	check("item is found by uid", record ~= nil and record.id == "debug_rusty_gear")
	check("HasItem is true for the new uid", InventoryService.HasItem(player, uid))
	check("item count increased by 1", InventoryService.GetItemCount(player) == startCount + 1)

	-- Read functions return copies: mutating one must not change saved data.
	local copy = InventoryService.GetItem(player, uid)
	if copy ~= nil then
		copy.id = "tampered"
	end
	local reread = InventoryService.GetItem(player, uid)
	check("returned records are copies", reread ~= nil and reread.id == "debug_rusty_gear")

	local unknownUid, unknownErr = InventoryService.AddItem(player, "does_not_exist")
	check("unknown item id is rejected", unknownUid == nil and unknownErr == InventoryService.Errors.UnknownItem, tostring(unknownErr))
	local badIdUid = InventoryService.AddItem(player, 123 :: any)
	check("non-string item id is rejected", badIdUid == nil)

	local badRemoveOk = InventoryService.RemoveItem(player, "not-a-uid")
	check("removing a malformed uid is rejected", not badRemoveOk)
	local missingOk, missingErr = InventoryService.RemoveItem(player, "00000000-0000-0000-0000-000000000000")
	check("removing an unowned uid is rejected", not missingOk and missingErr == InventoryService.Errors.ItemNotFound, tostring(missingErr))

	local removeOk = InventoryService.RemoveItem(player, uid)
	check("RemoveItem(uid) succeeds", removeOk)
	check("item no longer found after removal", not InventoryService.HasItem(player, uid))
	local again = InventoryService.RemoveItem(player, uid)
	check("removing the same uid twice fails the second time", not again)
	check("item count back to the starting value", InventoryService.GetItemCount(player) == startCount)

	-- Uniqueness: every added item must get a different uid.
	local toasterStart = InventoryService.CountByItemId(player, "debug_golden_toaster")
	local uids: { string } = {}
	local seen: { [string]: boolean } = {}
	local duplicates = 0
	-- Stage 4: storage is the chest (10 slots at level 1); give the test a big chest for a moment.
	local inventoryData = DataService.GetData(player) :: any
	local savedChest = if type(inventoryData.Base) == "table" then inventoryData.Base.ChestLevel else nil
	if type(inventoryData.Base) == "table" then
		inventoryData.Base.ChestLevel = #BaseConfig.Chest.Levels
	end
	for _ = 1, 25 do
		local newUid = InventoryService.AddItem(player, "debug_golden_toaster")
		if newUid ~= nil then
			if seen[newUid] then
				duplicates += 1
			end
			seen[newUid] = true
			table.insert(uids, newUid)
		end
	end
	check("25 items added", #uids == 25, tostring(#uids))
	check("no duplicate uids among 25 items", duplicates == 0, tostring(duplicates))
	check(
		"CountByItemId counts the new items",
		toasterStart ~= nil and InventoryService.CountByItemId(player, "debug_golden_toaster") == toasterStart + 25
	)

	for _, id in uids do
		InventoryService.RemoveItem(player, id)
	end
	check("inventory restored after cleanup", InventoryService.GetItemCount(player) == startCount)
	if savedChest ~= nil then
		inventoryData.Base.ChestLevel = savedChest
	end
end

---------------------------------------------------------------------------------------------
-- Step 3: junk spawning and carrying
---------------------------------------------------------------------------------------------

local function waitForLiveRoot(player: Player, timeout: number): BasePart?
	local deadline = os.clock() + timeout
	while os.clock() < deadline do
		local character = player.Character
		if character ~= nil then
			local humanoid = character:FindFirstChildOfClass("Humanoid")
			local root = character:FindFirstChild("HumanoidRootPart")
			if humanoid ~= nil and humanoid.Health > 0 and root ~= nil and root:IsA("BasePart") then
				return root
			end
		end
		task.wait(0.25)
	end
	return nil
end

-- Pickups have a per-player cooldown, so tests wait it out between attempts.
local function waitForCooldown()
	task.wait(GameConfig.Carry.PickupCooldown + 0.05)
end

local function runCatalogTests()
	local count = 0
	local failures: { string } = {}
	for id, definition in ItemConfig.Items do
		if definition.IsDebug ~= true then
			count += 1
			local world = JunkFactory.Build(id, "World")
			local cosmetic = JunkFactory.Build(id, "Cosmetic", 1)
			local good = world ~= nil
				and cosmetic ~= nil
				and JunkFactory.GetRoot(world) ~= nil
				and JunkFactory.GetRoot(cosmetic) ~= nil
			if not good then
				table.insert(failures, id)
			end
			if world ~= nil then
				world:Destroy()
			end
			if cosmetic ~= nil then
				cosmetic:Destroy()
			end
		end
	end
	check("the item catalog has 66 buildable items", count == 66, tostring(count))
	check("every catalog item builds in World and Cosmetic mode", #failures == 0, table.concat(failures, ", "))
	check("there are 15-25 recipes", #Recipes.List >= 15 and #Recipes.List <= 25, tostring(#Recipes.List))
	local badRecipes: { string } = {}
	for _, recipe in Recipes.List do
		if not ItemConfig.Exists(recipe.OutputItemId) or Recipes.TotalIngredients(recipe) > GameConfig.Carry.MaxJunk then
			table.insert(badRecipes, recipe.RecipeId)
		end
	end
	check("every recipe has a real output and fits in the hands", #badRecipes == 0, table.concat(badRecipes, ", "))
end

local function runJunkServiceTests()
	local deadline = os.clock() + 20
	while JunkService.GetActiveCount() == 0 and os.clock() < deadline do
		task.wait(0.25)
	end
	local count = JunkService.GetActiveCount()
	check("junk has spawned in the yard", count > 0, tostring(count))
	check("active junk does not exceed MaxActive", count <= GameConfig.Junk.MaxActive, tostring(count))

	local junk = JunkService.GetActiveJunk()[1]
	if junk == nil then
		return
	end
	local junkId = JunkService.GetJunkId(junk)
	check("active junk has a valid junk id", junkId ~= nil and ItemConfig.Exists(junkId))
	check("active junk has a pickup prompt", junk:FindFirstChildWhichIsA("ProximityPrompt", true) ~= nil)
	check(
		"active junk lives in the junk container",
		junk.Parent ~= nil and junk.Parent.Name == GameConfig.Junk.ContainerName
	)

	local junkUid = JunkService.GetUid(junk)
	check("active junk has a valid uid", junkUid ~= nil and Validate.IsUid(junkUid))
	check("the uid is published as the JunkUid attribute", junk:GetAttribute("JunkUid") == junkUid)
	check("IsUidActive is true for a junk in the world", junkUid ~= nil and JunkService.IsUidActive(junkUid))

	local claimedId, claimedUid = JunkService.Claim(junk)
	check("Claim returns the junk id and uid", claimedId == junkId and claimedUid == junkUid)
	check("a second Claim of the same junk fails", JunkService.Claim(junk) == nil)
	check("IsUidActive is false after Claim", junkUid ~= nil and not JunkService.IsUidActive(junkUid))
	check("claimed junk is no longer active", not JunkService.IsActive(junk))
	check("claimed junk is removed from the world", junk.Parent == nil)

	local stranger = Instance.new("Part")
	check("Claim rejects an instance that is not junk", JunkService.Claim(stranger) == nil)
	stranger:Destroy()
	check("Claim rejects a non-instance value", JunkService.Claim(123 :: any) == nil)
end

local function runCarryTests(player: Player)
	local errors = CarryService.Errors
	local maxJunk = GameConfig.Carry.MaxJunk
	CarryService.Clear(player)

	local allAdded = true
	for _ = 1, maxJunk do
		local ok = CarryService.AddJunk(player, "rusty_can")
		allAdded = allAdded and ok
	end
	check(`{maxJunk} junk can be added`, allAdded and CarryService.GetCount(player) == maxJunk)
	check("IsFull is true at the limit", CarryService.IsFull(player))

	local fullOk, fullErr = CarryService.AddJunk(player, "rusty_can")
	check("adding past the limit is rejected", not fullOk and fullErr == errors.CarryFull, tostring(fullErr))
	check("count is unchanged after a rejected add", CarryService.GetCount(player) == maxJunk)
	local encoded: { string } = {}
	local uniqueUids: { [string]: boolean } = {}
	local uniqueCount = 0
	for _, entry in CarryService.GetCarried(player) do
		table.insert(encoded, `{entry.Uid}:{entry.Id}`)
		if not uniqueUids[entry.Uid] then
			uniqueUids[entry.Uid] = true
			uniqueCount += 1
		end
	end
	check("CarryList attribute mirrors the list", player:GetAttribute("CarryList") == table.concat(encoded, ","))
	check("every carried junk has its own uid", uniqueCount == maxJunk, tostring(uniqueCount))

	local copy = CarryService.GetCarried(player)
	copy[1].Id = "tampered"
	table.clear(copy)
	check(
		"GetCarried returns copies",
		CarryService.GetCount(player) == maxJunk and CarryService.GetCarried(player)[1].Id == "rusty_can"
	)

	CarryService.Clear(player)
	check("Clear empties the list and the attribute", CarryService.GetCount(player) == 0 and player:GetAttribute("CarryList") == nil)

	local unknownOk, unknownErr = CarryService.AddJunk(player, "does_not_exist")
	check("unknown junk id is rejected", not unknownOk and unknownErr == errors.UnknownJunk, tostring(unknownErr))
	local badOk, badErr = CarryService.AddJunk(player, 123 :: any)
	check("non-string junk id is rejected", not badOk and badErr == errors.InvalidJunkId, tostring(badErr))

	CarryService.AddJunk(player, "old_boot")
	CarryService.AddJunk(player, "rubber_duck")
	local top = CarryService.PopTop(player)
	check("PopTop returns the last added junk", top ~= nil and top.Id == "rubber_duck")
	local nextTop = CarryService.PopTop(player)
	check("PopTop returns the previous junk next", nextTop ~= nil and nextTop.Id == "old_boot")
	check("PopTop on an empty list returns nil", CarryService.PopTop(player) == nil)

	-- One uid, one owner.
	local uid = JunkService.NewUid()
	check("AddJunk with an explicit uid succeeds", (CarryService.AddJunk(player, "old_boot", uid)))
	local dupOk, dupErr = CarryService.AddJunk(player, "old_boot", uid)
	check("adding the same uid twice is rejected", not dupOk and dupErr == errors.UidInUse, tostring(dupErr))
	check("HasUid is true for the owner", CarryService.HasUid(player, uid))
	local taken = CarryService.TakeByUid(player, uid)
	check("TakeByUid returns the record", taken ~= nil and taken.Uid == uid and taken.Id == "old_boot")
	check("TakeByUid of a missing uid returns nil", CarryService.TakeByUid(player, uid) == nil)
	local badUidOk, badUidErr = CarryService.AddJunk(player, "old_boot", "not-a-uid")
	check("a malformed uid is rejected", not badUidOk and badUidErr == errors.InvalidUid, tostring(badUidErr))

	local worldJunk = JunkService.GetActiveJunk()[1]
	local worldUid = if worldJunk ~= nil then JunkService.GetUid(worldJunk) else nil
	if worldUid ~= nil then
		local worldOk, worldErr = CarryService.AddJunk(player, "old_boot", worldUid)
		check("a uid that is lying in the world cannot be carried", not worldOk and worldErr == errors.UidInUse, tostring(worldErr))
	end
	CarryService.Clear(player)
end

-- Teleports the test player around, so it runs last. Restores the position at the end.
local function runPickupTests(player: Player)
	local errors = CarryService.Errors
	local maxJunk = GameConfig.Carry.MaxJunk

	local root = waitForLiveRoot(player, 15)
	local character = player.Character
	if root == nil or character == nil then
		warn("[DevTests] no live character: pickup tests skipped")
		return
	end
	local home = character:GetPivot()
	CarryService.Clear(player)

	local function firstJunk(): (Model?, Vector3?)
		local junk = JunkService.GetActiveJunk()[1]
		if junk == nil then
			return nil, nil
		end
		return junk, JunkService.GetPosition(junk)
	end

	local junkA, positionA = firstJunk()
	if junkA == nil or positionA == nil then
		warn("[DevTests] no junk in the yard: pickup tests skipped")
		return
	end
	local idA = JunkService.GetJunkId(junkA)
	local uidA = JunkService.GetUid(junkA)

	waitForCooldown()
	character:PivotTo(CFrame.new(positionA + Vector3.new(60, 4, 0)))
	local farOk, farErr = CarryService.TryPickup(player, junkA)
	check("pickup from far away is rejected", not farOk and farErr == errors.TooFar, tostring(farErr))
	check("junk stays in the yard after a rejected pickup", JunkService.IsActive(junkA))

	waitForCooldown()
	character:PivotTo(CFrame.new(positionA + Vector3.new(2, 4, 0)))
	local nearOk, nearErr = CarryService.TryPickup(player, junkA)
	check("pickup from close by succeeds", nearOk, tostring(nearErr))
	check("picked up junk left the yard", not JunkService.IsActive(junkA))
	local carriedA = CarryService.GetCarried(player)[1]
	check(
		"carry list holds the picked up junk with the same uid",
		CarryService.GetCount(player) == 1 and carriedA ~= nil and carriedA.Id == idA and carriedA.Uid == uidA
	)

	-- No waiting here on purpose: a second pickup right away must hit the cooldown.
	local junkB, positionB = firstJunk()
	if junkB ~= nil and positionB ~= nil then
		character:PivotTo(CFrame.new(positionB + Vector3.new(2, 4, 0)))
		local coolOk, coolErr = CarryService.TryPickup(player, junkB)
		check("a pickup right after another hits the cooldown", not coolOk and coolErr == errors.Cooldown, tostring(coolErr))
		check("junk stays in the yard after a cooldown rejection", JunkService.IsActive(junkB))

		for _ = 1, maxJunk do
			CarryService.AddJunk(player, "rusty_can") -- fills the list; extra adds are rejected
		end
		waitForCooldown()
		character:PivotTo(CFrame.new(positionB + Vector3.new(2, 4, 0)))
		local fullOk, fullErr = CarryService.TryPickup(player, junkB)
		check("pickup with a full carry list is rejected", not fullOk and fullErr == errors.CarryFull, tostring(fullErr))
		check("junk stays in the yard when the list is full", JunkService.IsActive(junkB))
	end

	local before = JunkService.GetActiveCount()
	CarryService.DropAll(player, character:GetPivot().Position)
	check("DropAll empties the carry list", CarryService.GetCount(player) == 0)
	local after = JunkService.GetActiveCount()
	check(`DropAll puts {maxJunk} junk back in the yard`, after >= before + maxJunk, `{before} -> {after}`)

	character:PivotTo(home)
	CarryService.Clear(player)
end

---------------------------------------------------------------------------------------------
-- Stage 1: throwing, expiry
---------------------------------------------------------------------------------------------

-- Horizontal distance a velocity covers before returning to its launch height.
local function flatRange(velocity: Vector3): number
	local flat = Vector3.new(velocity.X, 0, velocity.Z).Magnitude
	return flat * 2 * velocity.Y / Ballistics.GetGravity()
end

local function runBallisticsTests()
	local throw = GameConfig.Throw
	local origin = Vector3.new(0, 50, 0)
	local far = Ballistics.Solve(origin, origin + Vector3.new(10_000, 0, 0), Vector3.new(0, 0, -1))
	check("aiming beyond MaxRange is clamped to MaxRange", math.abs(flatRange(far) - throw.MaxRange) < 0.5, tostring(flatRange(far)))
	local near = Ballistics.Solve(origin, origin + Vector3.new(1, 0, 0), Vector3.new(0, 0, -1))
	check("aiming closer than MinRange throws MinRange", math.abs(flatRange(near) - throw.MinRange) < 0.5, tostring(flatRange(near)))
	local up = Ballistics.Solve(origin, origin + Vector3.new(0, 10_000, 0), Vector3.new(0, 0, -1))
	check("aiming straight up never exceeds the max speed", up.Magnitude <= Ballistics.GetMaxSpeed() + 1e-3)
	local mid = Ballistics.Solve(origin, origin + Vector3.new(0, 0, 30), Vector3.new(0, 0, -1))
	check("a throw goes towards the aim point", mid.Z > 0 and math.abs(mid.X) < 1e-3)
	check("a 30 stud aim lands about 30 studs away", math.abs(flatRange(mid) - 30) < 0.5, tostring(flatRange(mid)))
end

local function runThrowTests(player: Player)
	local errors = ThrowService.Errors
	local root = waitForLiveRoot(player, 15)
	if root == nil then
		warn("[DevTests] no live character: throw tests skipped")
		return
	end
	CarryService.Clear(player)
	local cooldown = GameConfig.Throw.Cooldown + 0.05
	local aim = root.Position + root.CFrame.LookVector * 45 -- a longer flight (~0.9 s) for the mid-flight checks

	local badOk, badErr = ThrowService.TryThrow(player, "not-a-uid", aim)
	check("throw with a malformed uid is rejected", not badOk and badErr == errors.InvalidArguments, tostring(badErr))
	local nanOk, nanErr = ThrowService.TryThrow(player, JunkService.NewUid(), Vector3.new(0 / 0, 0, 0))
	check("throw with a NaN aim point is rejected", not nanOk and nanErr == errors.InvalidArguments, tostring(nanErr))
	local hugeOk = ThrowService.TryThrow(player, JunkService.NewUid(), Vector3.new(math.huge, 0, 0))
	check("throw with an infinite aim point is rejected", not hugeOk)

	task.wait(cooldown)
	local strangerOk, strangerErr = ThrowService.TryThrow(player, JunkService.NewUid(), aim)
	check("throwing junk the player does not carry is rejected", not strangerOk and strangerErr == errors.NotCarried, tostring(strangerErr))

	local uid = JunkService.NewUid()
	CarryService.AddJunk(player, "rubber_duck", uid)
	task.wait(cooldown)
	local ok, err = ThrowService.TryThrow(player, uid, aim)
	check("a valid throw is accepted", ok, tostring(err))
	check("thrown junk leaves the carry list at once", not CarryService.HasUid(player, uid) and CarryService.GetCount(player) == 0)
	check("thrown junk is in flight", ThrowService.IsInFlight(uid))
	local flying = JunkService.GetByUid(uid)
	local copies = 0
	for _, junk in JunkService.GetActiveJunk() do
		if JunkService.GetUid(junk) == uid then
			copies += 1
		end
	end
	check("a flying junk has exactly one world object", flying ~= nil and copies == 1, tostring(copies))
	check("a flying junk cannot be claimed", flying ~= nil and not JunkService.IsClaimable(flying) and JunkService.Claim(flying) == nil)
	local flyingPrompt = if flying ~= nil then flying:FindFirstChildWhichIsA("ProximityPrompt", true) else nil
	check("a flying junk shows no pickup prompt", flyingPrompt ~= nil and not flyingPrompt.Enabled)
	if flying ~= nil then
		local character = player.Character
		local flyingPosition = JunkService.GetPosition(flying)
		if character ~= nil and flyingPosition ~= nil then
			local home = character:GetPivot()
			character:PivotTo(CFrame.new(flyingPosition + Vector3.new(2, 4, 0)))
			local midOk, midErr = CarryService.TryPickup(player, flying)
			check("picking up a flying junk is rejected", not midOk and midErr == CarryService.Errors.NotReady, tostring(midErr))
			character:PivotTo(home)
		end
	end

	local againOk, againErr = ThrowService.TryThrow(player, uid, aim)
	check("throwing the same junk twice is rejected", not againOk)
	check("a throw right after another hits the cooldown", againErr == errors.Cooldown, tostring(againErr))

	task.wait(GameConfig.Throw.MaxFlightTime + 0.3)
	check("thrown junk landed back in the world with the same uid", JunkService.IsUidActive(uid))
	check("thrown junk is no longer in flight", not ThrowService.IsInFlight(uid))

	-- The landed junk is ordinary junk again: it can be picked up by the normal rules.
	local landed: Model? = nil
	for _, junk in JunkService.GetActiveJunk() do
		if JunkService.GetUid(junk) == uid then
			landed = junk
		end
	end
	local landedPosition = if landed ~= nil then JunkService.GetPosition(landed) else nil
	if landed ~= nil and landedPosition ~= nil then
		local character = player.Character
		if character ~= nil then
			local home = character:GetPivot()
			character:PivotTo(CFrame.new(landedPosition + Vector3.new(2, 4, 0)))
			waitForCooldown()
			local pickOk, pickErr = CarryService.TryPickup(player, landed)
			check("landed junk can be picked up again", pickOk, tostring(pickErr))
			check("picked up thrown junk keeps its uid", CarryService.HasUid(player, uid))
			character:PivotTo(home)
		end
	end
	CarryService.Clear(player)

	-- Expiry of dropped junk.
	local expiring = JunkService.SpawnAt("rusty_can", root.Position, { Lifetime = 0 })
	check("SpawnAt with a lifetime creates junk", expiring ~= nil)
	local removed = JunkService.CleanupExpired()
	check("CleanupExpired removes expired junk", removed >= 1 and expiring ~= nil and not JunkService.IsActive(expiring))
end

---------------------------------------------------------------------------------------------
-- Stage 2A: drop tables, crafting rules, personal machines, persistence, receipts
---------------------------------------------------------------------------------------------

local function checkDistribution(name: string, chances: { [string]: number })
	local samples = 200_000
	local counts: { [string]: number } = {}
	for _ = 1, samples do
		local rarity = RewardService.RollRarity(chances)
		counts[rarity] = (counts[rarity] or 0) + 1
	end
	for _, rarityId in Rarities.Order do
		local expected = chances[rarityId] or 0
		local actual = (counts[rarityId] or 0) / samples * 100
		-- About 5 standard deviations, so the test is practically never flaky.
		local tolerance = 5 * math.sqrt(expected * (100 - expected) / samples) + 0.01
		check(
			`{name}: {rarityId} rolls about {expected}%`,
			math.abs(actual - expected) <= tolerance,
			string.format("%.3f%% (allowed %.3f)", actual, tolerance)
		)
	end
end

local function runRewardTests()
	checkDistribution("Recycle", DropTables.Recycle)
	checkDistribution("WorldSpawn", DropTables.WorldSpawn)
	for _, rarityId in Rarities.Order do
		local itemId = RewardService.RollItem(rarityId)
		local definition = ItemConfig.Get(itemId)
		check(
			`a {rarityId} reward is a non-debug {rarityId} reward-pool item`,
			definition ~= nil and definition.Rarity == rarityId and definition.RecyclePool == true and definition.IsDebug ~= true,
			itemId
		)
	end

	-- Mythic crafting odds depend on the inputs.
	local commons = CraftingService.MythicChances({ "rusty_can", "soda_bottle", "old_boot" })
	local legends = CraftingService.MythicChances({ "golden_wrench", "aurora_orb", "frozen_crown" })
	local mixed = CraftingService.MythicChances({ "rusty_can", "circuit_board", "crystal_shard" })
	check("three Commons can never give Legendary or Mythic", commons.Legendary == 0 and commons.Mythic == 0)
	check("three Legendaries never give Common and often give Mythic", legends.Common == 0 and legends.Mythic >= 10)
	check("mixed inputs sit in between", mixed.Mythic > commons.Mythic and mixed.Mythic < legends.Mythic, string.format("%.2f", mixed.Mythic))
	local bad = 0
	for _ = 1, 20_000 do
		local _, rarity = CraftingService.RollMythic({ "rusty_can", "soda_bottle", "old_boot" })
		if rarity == "Legendary" or rarity == "Mythic" then
			bad += 1
		end
	end
	check("20,000 Common mythic rolls never give Legendary/Mythic", bad == 0, tostring(bad))
	check("a special combo gives its fixed result", CraftingService.RollMythic({ "crystal_shard", "crystal_shard", "crystal_shard" }) == "comet_shard")

	-- Recipe planning.
	local carried = {
		{ Uid = JunkService.NewUid(), Id = "bike_wheel" },
		{ Uid = JunkService.NewUid(), Id = "pipe_segment" },
		{ Uid = JunkService.NewUid(), Id = "bike_wheel" },
		{ Uid = JunkService.NewUid(), Id = "rusty_can" },
	}
	local bicycle = Recipes.Get("bicycle") :: any
	local plan = CraftingService.PlanRecipe(bicycle, carried)
	check("a complete recipe plans exactly its ingredients", plan ~= nil and #plan == 3)
	local short, missing = CraftingService.PlanRecipe(bicycle, { carried[1], carried[2] })
	check("a missing ingredient is reported", short == nil and missing.bike_wheel == 1)
end

local function teleportNear(player: Player, cframe: CFrame)
	local character = player.Character
	if character ~= nil then
		character:PivotTo(cframe)
	end
end

local function finishJob(player: Player)
	MachineService.InstantFinish(player)
end

local function trayModelOf(uid: string): Model?
	return JunkService.GetByUid(uid)
end

local function runMachineTests(player: Player)
	local errors = MachineService.Errors
	local root = waitForLiveRoot(player, 15)
	local deadline = os.clock() + 10
	while os.clock() < deadline and MachineService.GetModel(player) == nil do
		task.wait(0.2)
	end
	local model = MachineService.GetModel(player)
	local plot = PlotService.GetPlot(player)
	check("the player got a base plot", plot ~= nil)
	check("the player's personal machine stands on their plot", model ~= nil and plot ~= nil and model:IsDescendantOf(plot))
	if model == nil or root == nil then
		warn("[DevTests] no machine or no character: machine tests skipped")
		return
	end
	check("the machine belongs to the player", model:GetAttribute("OwnerUserId") == player.UserId)
	check("the machine starts Idle", model:GetAttribute("State") == "Idle", tostring(model:GetAttribute("State")))
	local anchor = model:FindFirstChild("PromptAnchor", true) :: BasePart
	local front = anchor.CFrame * CFrame.new(0, 0, -12)
	local character = player.Character :: Model
	local home = character:GetPivot()
	CarryService.Clear(player)

	-- Rejections
	local badOk, badErr = MachineService.Recycle(player, "nope")
	check("recycle with a malformed uid is rejected", not badOk and badErr == errors.InvalidArguments, tostring(badErr))
	teleportNear(player, front)
	local strangerOk, strangerErr = MachineService.Recycle(player, JunkService.NewUid())
	check("recycling an item the player does not carry is rejected", not strangerOk and strangerErr == errors.NotCarried, tostring(strangerErr))
	local uid = JunkService.NewUid()
	CarryService.AddJunk(player, "rusty_can", uid)
	teleportNear(player, anchor.CFrame * CFrame.new(0, 0, -120))
	local farOk, farErr = MachineService.Recycle(player, uid)
	check("recycling from far away is rejected", not farOk and farErr == errors.TooFar, tostring(farErr))
	check("a rejected request keeps the item carried", CarryService.HasUid(player, uid))

	-- Recycling + acceleration
	teleportNear(player, front)
	local ok, err = MachineService.Recycle(player, uid)
	check("a valid recycle is accepted", ok, tostring(err))
	check("the recycled item is consumed exactly once", not CarryService.HasUid(player, uid) and not JunkService.IsUidActive(uid))
	check("the machine is Processing a Recycle job", model:GetAttribute("State") == "Processing" and model:GetAttribute("JobKind") == "Recycle")
	check("recycling takes the configured 30 s", model:GetAttribute("JobDuration") == MachineConfig.RecycleDuration, tostring(model:GetAttribute("JobDuration")))
	local againUid = JunkService.NewUid()
	CarryService.AddJunk(player, "old_boot", againUid)
	local busyOk, busyErr = MachineService.Recycle(player, againUid)
	check("a second job while busy is rejected", not busyOk and busyErr == errors.Busy, tostring(busyErr))
	check("the rejected item stays carried", CarryService.HasUid(player, againUid))

	local before = MachineService.GetRemaining(player) :: number
	MachineService.Accelerate(player)
	local after = MachineService.GetRemaining(player) :: number
	check("one click removes exactly one second", math.abs((before - after) - 1) < 0.15, string.format("%.3f", before - after))
	for _ = 1, 5 do
		MachineService.Accelerate(player)
	end
	local afterFive = MachineService.GetRemaining(player) :: number
	check("five more clicks remove five more seconds", math.abs((after - afterFive) - 5) < 0.2, string.format("%.3f", after - afterFive))
	local clicks = 0
	while MachineService.GetRemaining(player) ~= nil and clicks < 60 do
		MachineService.Accelerate(player)
		clicks += 1
	end
	check("clicking to zero finishes the job", MachineService.GetRemaining(player) == nil and model:GetAttribute("State") == "RewardReady")
	local extraOk, extraErr = MachineService.Accelerate(player)
	check("clicking a finished machine is rejected", not extraOk and extraErr == errors.NoJob, tostring(extraErr))

	-- The reward is a real, reserved world item on the tray
	local data = MachineService.GetData(player) :: any
	check("the result waits in the output", #data.Output == 1)
	local reward = data.Output[1]
	local trayModel = if reward ~= nil then trayModelOf(reward.Uid) else nil
	check("the result lies on the tray as a world item", trayModel ~= nil)
	if reward == nil or trayModel == nil then
		return
	end
	local prompt = trayModel:FindFirstChildWhichIsA("ProximityPrompt", true)
	check("the tray item is reserved for its owner", prompt ~= nil and prompt:GetAttribute("ReservedFor") == player.UserId)
	check("nobody else can claim the reserved tray item", JunkService.Claim(trayModel, nil) == nil and JunkService.IsUidActive(reward.Uid))
	check("the output is full, so a new job cannot start", (select(2, MachineService.Recycle(player, againUid))) == errors.OutputFull)

	-- Full hands keep the reward on the tray
	CarryService.Clear(player)
	for _ = 1, GameConfig.Carry.MaxJunk do
		CarryService.AddJunk(player, "rusty_can")
	end
	local fullOk, fullErr = MachineService.Take(player, reward.Uid)
	check("taking with full hands is rejected", not fullOk and fullErr == errors.CarryFull, tostring(fullErr))
	check("the reward stays on the tray when hands are full", JunkService.IsUidActive(reward.Uid) and #(MachineService.GetData(player) :: any).Output == 1)
	CarryService.Clear(player)

	-- Picking it up like any item (E on the tray)
	local trayPosition = JunkService.GetPosition(trayModel) :: Vector3
	teleportNear(player, CFrame.new(trayPosition + Vector3.new(0, 3, -3)))
	waitForCooldown()
	local pickOk, pickErr = CarryService.TryPickup(player, trayModel)
	check("the owner picks the reward up from the tray", pickOk, tostring(pickErr))
	check("picking it up empties the output in the same step", CarryService.HasUid(player, reward.Uid) and #(MachineService.GetData(player) :: any).Output == 0)
	check("the machine is Idle again", model:GetAttribute("State") == "Idle")

	-- It is an ordinary item now: throw it, pick it up, recycle it again
	waitForCooldown()
	local throwOk = ThrowService.TryThrow(player, reward.Uid, front.Position + Vector3.new(0, 0, -15))
	check("the reward can be thrown", throwOk)
	task.wait(GameConfig.Throw.MaxFlightTime + 0.3)
	local landed = JunkService.GetByUid(reward.Uid)
	check("the thrown reward is a normal, unreserved world item", landed ~= nil and JunkService.CanClaim(landed, player))
	if landed ~= nil then
		teleportNear(player, CFrame.new((JunkService.GetPosition(landed) :: Vector3) + Vector3.new(2, 3, 0)))
		waitForCooldown()
		check("the thrown reward can be picked up again", (CarryService.TryPickup(player, landed)))
		teleportNear(player, front)
		-- Stage 3: only yard junk can be recycled, so a reward cannot be recycled into money forever.
		local againOk, againCode = MachineService.Recycle(player, reward.Uid)
		check("a recycling reward cannot be recycled again (no infinite money)",
			not againOk and againCode == MachineService.Errors.NotRecyclable, tostring(againCode))
		finishJob(player)
		local out = (MachineService.GetData(player) :: any).Output[1]
		if out ~= nil then
			MachineService.Take(player, out.Uid)
		end
	end
	CarryService.Clear(player)

	-- Crafting
	teleportNear(player, front)
	local unknownOk, unknownErr = MachineService.Craft(player, "flying_castle")
	check("an unknown recipe is rejected", not unknownOk and unknownErr == errors.UnknownRecipe, tostring(unknownErr))
	CarryService.AddJunk(player, "bike_wheel")
	CarryService.AddJunk(player, "pipe_segment")
	local missingOk, missingErr = MachineService.Craft(player, "bicycle")
	check("crafting with a missing ingredient is rejected", not missingOk and missingErr == errors.MissingIngredients, tostring(missingErr))
	check("nothing is consumed by a rejected craft", CarryService.GetCount(player) == 2)
	CarryService.AddJunk(player, "bike_wheel")
	CarryService.AddJunk(player, "rusty_can")
	local craftOk, craftErr = MachineService.Craft(player, "bicycle")
	check("a complete recipe starts crafting", craftOk, tostring(craftErr))
	local remainingIds = CarryService.GetCarried(player)
	check("exactly the ingredients were consumed", #remainingIds == 1 and remainingIds[1].Id == "rusty_can")
	check("an Uncommon craft takes 5 minutes", model:GetAttribute("JobDuration") == MachineConfig.CraftDurations.Uncommon)
	finishJob(player)
	local crafted = (MachineService.GetData(player) :: any).Output[1]
	check("crafting produced a Bicycle", crafted ~= nil and crafted.Id == "bicycle")
	if crafted ~= nil then
		check("the crafted item can be taken", (MachineService.Take(player, crafted.Uid)))
	end
	CarryService.Clear(player)
	for _ = 1, 4 do
		CarryService.AddJunk(player, "old_tire")
	end
	CarryService.AddJunk(player, "metal_frame")
	CarryService.AddJunk(player, "small_engine")
	local lockedOk, lockedErr = MachineService.Craft(player, "homemade_car")
	check("a recipe above the machine level is rejected", not lockedOk and lockedErr == errors.Locked, tostring(lockedErr))
	CarryService.Clear(player)

	-- Mythic crafting
	local a, b, c = JunkService.NewUid(), JunkService.NewUid(), JunkService.NewUid()
	CarryService.AddJunk(player, "rusty_can", a)
	CarryService.AddJunk(player, "circuit_board", b)
	CarryService.AddJunk(player, "crystal_shard", c)
	local dupOk, dupErr = MachineService.Mythic(player, a, a, b)
	check("mythic crafting rejects the same item in two slots", not dupOk and dupErr == errors.InvalidArguments, tostring(dupErr))
	local mythicOk, mythicErr = MachineService.Mythic(player, a, b, c)
	check("mythic crafting with three items starts", mythicOk, tostring(mythicErr))
	check("all three inputs are consumed", CarryService.GetCount(player) == 0)
	check("mythic crafting takes exactly six hours", model:GetAttribute("JobDuration") == 6 * 60 * 60, tostring(model:GetAttribute("JobDuration")))

	-- Persistence: leave and rejoin while it runs, then come back after it finished offline
	local completesBefore = model:GetAttribute("JobCompletesAt") :: number
	MachineService.Unload(player)
	check("unloading removes the machine from the world", MachineService.GetModel(player) == nil)
	MachineService.Load(player)
	local reloaded = MachineService.GetModel(player)
	check("after a rejoin the job is still running with the same end time",
		reloaded ~= nil and reloaded:GetAttribute("State") == "Processing"
			and math.abs((reloaded:GetAttribute("JobCompletesAt") :: number) - completesBefore) < 0.01)
	MachineService.Unload(player)
	MachineService.DebugShiftJob(player, 6 * 60 * 60) -- six hours pass while offline
	MachineService.Load(player)
	model = MachineService.GetModel(player) :: Model
	local offlineOut = (MachineService.GetData(player) :: any).Output[1]
	check("a job that finished offline is ready on rejoin", model:GetAttribute("State") == "RewardReady" and offlineOut ~= nil)
	check("the offline result is on the tray", offlineOut ~= nil and JunkService.IsUidActive(offlineOut.Uid))
	anchor = model:FindFirstChild("PromptAnchor", true) :: BasePart
	front = anchor.CFrame * CFrame.new(0, 0, -12)
	teleportNear(player, front)
	if offlineOut ~= nil then
		MachineService.Take(player, offlineOut.Uid)
	end

	-- Carried items survive a rejoin
	CarryService.Clear(player)
	local keepA, keepB = JunkService.NewUid(), JunkService.NewUid()
	CarryService.AddJunk(player, "gear_wheel", keepA)
	CarryService.AddJunk(player, "bicycle", keepB)
	CarryService.ReloadFromSave(player)
	check("carried items are restored after a rejoin", CarryService.HasUid(player, keepA) and CarryService.HasUid(player, keepB) and CarryService.GetCount(player) == 2)
	CarryService.Clear(player)

	-- Upgrades
	local startKlunks = CurrencyService.GetKlunks(player) :: number
	local noMoney = MachineService.BuyUpgrade(player, "Level")
	check("an unaffordable upgrade is rejected", not noMoney or startKlunks >= 3000)
	check("an unknown upgrade is rejected", (select(2, MachineService.BuyUpgrade(player, "Turbo"))) == errors.UnknownUpgrade)
	CurrencyService.AddKlunks(player, 500)
	local buyOk, buyErr = MachineService.BuyUpgrade(player, "Speed")
	check("buying the Speed upgrade works", buyOk, tostring(buyErr))
	check("the upgrade costs its price", CurrencyService.GetKlunks(player) == startKlunks)
	check("the machine shows the new level", model:GetAttribute("UpgradeSpeed") == 2)
	local speedUid = JunkService.NewUid()
	CarryService.AddJunk(player, "rusty_can", speedUid)
	MachineService.Recycle(player, speedUid)
	check("a faster machine takes 10% less time", model:GetAttribute("JobDuration") == 27, tostring(model:GetAttribute("JobDuration")))
	finishJob(player)
	local speedOut = (MachineService.GetData(player) :: any).Output[1]
	if speedOut ~= nil then
		MachineService.Take(player, speedOut.Uid)
	end
	-- Test cleanup: back to the default machine.
	local profile = DataService.GetData(player) :: any
	profile.Machine.Upgrades.Speed = 1
	MachineService.Unload(player)
	MachineService.Load(player)

	-- Robux receipts are idempotent
	local grants = 0
	MonetizationService.RegisterHandlerForTest(424242, function(): boolean
		grants += 1
		return true
	end)
	local receipt = { PlayerId = player.UserId, ProductId = 424242, PurchaseId = "devtest-" .. JunkService.NewUid() }
	local first = MonetizationService.ProcessReceiptForTest(receipt)
	local second = MonetizationService.ProcessReceiptForTest(receipt)
	check("a receipt is granted once", first == Enum.ProductPurchaseDecision.PurchaseGranted and grants == 1)
	check("a repeated receipt is acknowledged without granting again", second == Enum.ProductPurchaseDecision.PurchaseGranted and grants == 1)

	CarryService.Clear(player)
	character:PivotTo(home)
end

---------------------------------------------------------------------------------------------
-- Stage 2B: functional items
---------------------------------------------------------------------------------------------

local function waitUntil(timeout: number, condition: () -> boolean): boolean
	local deadline = os.clock() + timeout
	while os.clock() < deadline do
		if condition() then
			return true
		end
		task.wait(0.05)
	end
	return condition()
end

local function runItemTests(player: Player)
	local errors = PlacementService.Errors
	local root = waitForLiveRoot(player, 15)
	local plot = PlotService.GetPlot(player)
	if root == nil or plot == nil then
		warn("[DevTests] no character or plot: functional item tests skipped")
		return
	end
	local character = player.Character :: Model
	local humanoid = character:FindFirstChildOfClass("Humanoid") :: Humanoid
	local home = character:GetPivot()
	local data = DataService.GetData(player) :: any
	CarryService.Clear(player)

	local plotTop = PlotService.GetPlotCFrame(plot)
	local spotA = (plotTop * CFrame.new(-12, 0, -8)).Position
	local spotB = (plotTop * CFrame.new(1, 0, -14)).Position -- clear of the Stage 4 building slots
	local spotC = (plotTop * CFrame.new(-12, 0, 8)).Position
	local function standNear(spot: Vector3)
		character:PivotTo(CFrame.new(spot + Vector3.new(0, 3, 0) + plotTop.LookVector * -9))
		task.wait(0.1)
	end
	local function give(itemId: string): string
		local uid = JunkService.NewUid()
		CarryService.AddJunk(player, itemId, uid)
		return uid
	end
	local function deployedCount(uid: string): number
		local count = 0
		for _, model in (workspace:FindFirstChild("Deployed") :: Folder):GetChildren() do
			if model:GetAttribute("DeployUid") == uid then
				count += 1
			end
		end
		return count
	end
	local function savedRecord(uid: string): any
		for _, record in data.Deployed do
			if record.Uid == uid then
				return record
			end
		end
		return nil
	end

	-- Capabilities of the first five functional items
	local function caps(id: string): any
		return ItemCapabilities.Get(id)
	end
	check("bicycle, car, cart and radio can be placed",
		caps("bicycle").CanBePlaced and caps("homemade_car").CanBePlaced and caps("metal_cart").CanBePlaced and caps("boombox_radio").CanBePlaced)
	check("the metal detector is used while carried", caps("metal_detector").CanBeUsed and not caps("metal_detector").CanBePlaced)
	check("plain junk has no action", not caps("rusty_can").CanBePlaced and not caps("rusty_can").CanBeUsed)

	-- Placement rules
	local bikeUid = give("bicycle")
	standNear(spotA)
	local farOk, farCode = PlacementService.Place(player, bikeUid, spotA + plotTop.LookVector * 70, 0)
	check("placing far away is rejected", not farOk and farCode == "TooFar", tostring(farCode))
	local ghostOk, ghostCode = PlacementService.Place(player, JunkService.NewUid(), spotA, 0)
	check("placing an item that is not carried is rejected", not ghostOk and ghostCode == errors.NotCarried, tostring(ghostCode))
	local canUid = give("rusty_can")
	local canOk, canCode = PlacementService.Place(player, canUid, spotA, 0)
	check("placing plain junk is rejected", not canOk and canCode == errors.NotPlaceable, tostring(canCode))
	CarryService.TakeByUid(player, canUid)
	local machine = MachineService.GetModel(player)
	if machine ~= nil then
		local _, nearCode = PlacementRules.Check({ UserId = player.UserId, ModelName = "Radio", Position = machine:GetPivot().Position + Vector3.new(3, 0, 0), Yaw = 0 })
		check("placing next to a machine is rejected", nearCode == "NearMachine" or nearCode == "Blocked", tostring(nearCode))
	end
	for _, other in CollectionService:GetTagged("BasePlot") do
		if other ~= plot and other:GetAttribute("Owner") == 0 then
			other:SetAttribute("Owner", 999999) -- pretend someone owns it
			local _, foreignCode = PlacementRules.Check({ UserId = player.UserId, ModelName = "Radio", Position = PlotService.GetPlotCFrame(other).Position, Yaw = 0 })
			other:SetAttribute("Owner", 0)
			check("placing on another player's plot is rejected", foreignCode == "ForeignPlot", tostring(foreignCode))
			break
		end
	end

	-- Place: hands -> world, exactly once
	-- Facing the plot's -X edge, so the ride below has to cross the plot's curb.
	local _, plotYaw = plotTop:ToEulerAnglesYXZ()
	local placeOk, placeCode = PlacementService.Place(player, bikeUid, spotA, plotYaw + math.pi / 2)
	check("a carried bicycle can be placed", placeOk, tostring(placeCode))
	local entry = PlacementService.GetEntry(bikeUid)
	if entry ~= nil then
		task.wait(0.5)
		local lowest = math.huge
		for _, part in entry.Model:GetChildren() do
			if part:IsA("BasePart") and part.Name == "Collider" then
				lowest = math.min(lowest, part.Position.Y - part.Size.Y / 2)
			end
		end
		check("the placed bicycle stands on the ground", math.abs(lowest - plotTop.Position.Y) < 0.3,
			string.format("bottom %.2f, ground %.2f", lowest, plotTop.Position.Y))
	end
	check("the bicycle left the hands", not CarryService.HasUid(player, bikeUid))
	check("exactly one bicycle object exists", deployedCount(bikeUid) == 1, tostring(deployedCount(bikeUid)))
	check("the placed bicycle is saved", savedRecord(bikeUid) ~= nil)
	local againOk, againCode = PlacementService.Place(player, bikeUid, spotB, 0)
	check("placing the same item twice is rejected", not againOk and againCode == errors.NotCarried and deployedCount(bikeUid) == 1, tostring(againCode))
	local dupOk, dupCode = CarryService.AddJunk(player, "bicycle", bikeUid)
	check("a placed uid cannot be added to the hands again", not dupOk and dupCode == "UidInUse", tostring(dupCode))

	-- Riding
	if entry ~= nil then
		local seat = entry.Model:FindFirstChild("DriverSeat") :: VehicleSeat
		local base = entry.Model.PrimaryPart :: BasePart
		character:PivotTo(CFrame.new(seat.Position + Vector3.new(2, 1, 0)))
		task.wait(0.2)
		seat:Sit(humanoid)
		check("the owner can sit on the bicycle", waitUntil(2, function()
			return seat.Occupant == humanoid
		end))
		check("the owner becomes the driver", VehicleBehavior.GetDriven(player) == entry)
		local busyOk, busyCode = PlacementService.Store(player, bikeUid)
		check("an occupied vehicle cannot be picked up", not busyOk and busyCode == "Occupied", tostring(busyCode))
		check("the vehicle stays server-owned while ridden", base:GetNetworkOwner() == nil)

		local start = base.Position
		local topSpeed = 0
		local deadline = os.clock() + 2
		while os.clock() < deadline do
			VehicleBehavior.SetInput(player, 1, 0)
			local velocity = base.AssemblyLinearVelocity
			topSpeed = math.max(topSpeed, Vector3.new(velocity.X, 0, velocity.Z).Magnitude)
			task.wait(0.1)
		end
		local travelled = (base.Position - start).Magnitude
		local maxSpeed = entry.Behavior.Vehicle.MaxSpeed
		check("throttle moves the bicycle forward", travelled > 10, string.format("%.1f studs", travelled))
		local plotHalf = (plot:FindFirstChild("Pad") :: BasePart).Size.X / 2
		local localX = plotTop:PointToObjectSpace(base.Position).X
		check("the bicycle rolls over the plot's curb", localX < -plotHalf, string.format("local x %.1f, edge %.1f", localX, -plotHalf))
		check("the bicycle never exceeds its max speed", topSpeed <= maxSpeed + 2, string.format("%.1f > %d", topSpeed, maxSpeed))
		VehicleBehavior.SetInput(player, 99, -99)
		check("driver input is clamped to [-1, 1]", entry.State.Throttle == 1 and entry.State.Steer == -1)
		local yawBefore = entry.State.Yaw
		local steerDeadline = os.clock() + 1
		while os.clock() < steerDeadline do
			VehicleBehavior.SetInput(player, 1, 1)
			task.wait(0.1)
		end
		check("steering turns the bicycle", math.abs(entry.State.Yaw - yawBefore) > 0.5, string.format("%.2f rad", entry.State.Yaw - yawBefore))
		local brakeDeadline = os.clock() + 2.5
		while os.clock() < brakeDeadline do
			VehicleBehavior.SetInput(player, -1, 0)
			task.wait(0.1)
		end
		check("braking stops it and reverse is slow", entry.State.Speed <= 0 and entry.State.Speed >= -entry.Behavior.Vehicle.ReverseSpeed, tostring(entry.State.Speed))

		humanoid.Sit = false
		local weld = seat:FindFirstChild("SeatWeld")
		if weld ~= nil then
			weld:Destroy()
		end
		check("getting off frees the seat", waitUntil(2, function()
			return seat.Occupant == nil
		end))
		task.wait(0.2)
		check("the rider is no longer the driver", VehicleBehavior.GetDriven(player) == nil and not VehicleBehavior.SetInput(player, 1, 0))
		check("the rider is put down beside it", (root.Position - seat.Position).Magnitude > 1.5)
		check("the rider controls their own character again", root:GetNetworkOwner() == player, tostring(root:GetNetworkOwner()))
		local idleDeadline = os.clock() + 3
		waitUntil(3, function()
			return entry.State.Speed == 0 or os.clock() > idleDeadline
		end)
		check("without a driver the bicycle stops", math.abs(entry.State.Speed) < 0.5, tostring(entry.State.Speed))
	end

	-- Store: world -> hands
	standNear(spotA)
	local storeOk, storeCode = PlacementService.Store(player, bikeUid)
	check("the bicycle can be picked up again", storeOk, tostring(storeCode))
	check("it is back in the hands with the same uid", CarryService.HasUid(player, bikeUid))
	check("its world object and save record are gone", deployedCount(bikeUid) == 0 and savedRecord(bikeUid) == nil and PlacementService.GetEntry(bikeUid) == nil)
	local reStoreOk, reStoreCode = PlacementService.Store(player, bikeUid)
	check("picking it up twice is rejected", not reStoreOk and reStoreCode == errors.NotFound, tostring(reStoreCode))

	-- Vehicle limit
	local carUid = give("homemade_car")
	standNear(spotA)
	local carOk, carCode = PlacementService.Place(player, carUid, spotA, 0)
	check("the homemade car can be placed", carOk, tostring(carCode))
	standNear(spotB)
	local bikeOk, bikeCode = PlacementService.Place(player, bikeUid, spotB, 0)
	check("a second vehicle can be placed", bikeOk, tostring(bikeCode))
	local thirdUid = give("bicycle")
	standNear(spotC)
	local thirdOk, thirdCode = PlacementService.Place(player, thirdUid, spotC, 0)
	check("a third vehicle is over the limit", not thirdOk and thirdCode == errors.VehicleLimit and CarryService.HasUid(player, thirdUid), tostring(thirdCode))
	local carEntry = PlacementService.GetEntry(carUid)
	check("the car has a passenger seat and an engine sound", carEntry ~= nil and carEntry.Model:FindFirstChild("PassengerSeat") ~= nil
		and carEntry.State.Engine ~= nil)
	standNear(spotA)
	PlacementService.Store(player, carUid)
	standNear(spotB)
	PlacementService.Store(player, bikeUid)
	CarryService.Clear(player)

	-- Metal cart
	local cartUid = give("metal_cart")
	standNear(spotA)
	local cartOk, cartCode = PlacementService.Place(player, cartUid, spotA, 0)
	check("the metal cart can be placed", cartOk, tostring(cartCode))
	local cart = PlacementService.GetEntry(cartUid)
	if cart ~= nil then
		local loadA, loadB = give("rusty_can"), give("old_tire")
		local firstLoad = CartBehavior.Load(cart, player)
		local secondLoad = CartBehavior.Load(cart, player)
		check("items can be loaded into the cart", firstLoad and secondLoad and #cart.Record.Contents == 2)
		check("loaded items leave the hands", not CarryService.HasUid(player, loadA) and not CarryService.HasUid(player, loadB))
		check("loaded items are saved with the cart", savedRecord(cartUid) ~= nil and #savedRecord(cartUid).Contents == 2)
		local heldOk = CarryService.AddJunk(player, "rusty_can", loadA)
		check("a loaded uid cannot appear in the hands too", not heldOk)
		local emptyLoad, emptyCode = CartBehavior.Load(cart, player)
		check("loading with empty hands is rejected", not emptyLoad and emptyCode == "NothingToLoad", tostring(emptyCode))
		local fullOk, fullCode = PlacementService.Store(player, cartUid)
		check("a loaded cart cannot be picked up", not fullOk and fullCode == "NotEmpty", tostring(fullCode))
		check("the cart shows its contents", cart.Model:GetAttribute("ContentCount") == 2)

		CartBehavior.ToggleTow(cart)
		check("the cart can be towed", cart.Model:GetAttribute("Towing") == true)
		local away = (plotTop * CFrame.new(-12, 0, 6)).Position
		character:PivotTo(CFrame.new(away + Vector3.new(0, 3, 0)))
		task.wait(1.5)
		local gap = (cart.Model:GetPivot().Position - root.Position) * Vector3.new(1, 0, 1)
		check("a towed cart follows its owner", gap.Magnitude < cart.Behavior.Cart.FollowDistance + 3, string.format("%.1f studs", gap.Magnitude))
		CartBehavior.ToggleTow(cart)
		check("towing can be released", cart.Model:GetAttribute("Towing") == false)

		local unloadOk = CartBehavior.Unload(cart, player)
		-- Load takes the last picked-up item first (old_tire), so the rusty can went in last.
		check("unloading returns the last loaded item to the hands", unloadOk and CarryService.HasUid(player, loadA) and #cart.Record.Contents == 1)
		CartBehavior.Unload(cart, player)
		character:PivotTo(CFrame.new(cart.Model:GetPivot().Position + Vector3.new(0, 3, 5)))
		local cartStoreOk, cartStoreCode = PlacementService.Store(player, cartUid)
		check("an empty cart can be picked up", cartStoreOk, tostring(cartStoreCode))
	end
	CarryService.Clear(player)

	-- Radio
	local radioUid = give("boombox_radio")
	standNear(spotA)
	local radioOk, radioCode = PlacementService.Place(player, radioUid, spotA, 0)
	check("the radio can be placed", radioOk, tostring(radioCode))
	local radio = PlacementService.GetEntry(radioUid)
	if radio ~= nil then
		local sound = radio.State.Sound :: Sound
		RadioBehavior.Toggle(radio)
		check("the radio plays music", sound.Playing and radio.Model:GetAttribute("Playing") == true and sound.SoundId ~= "")
		local firstTrack = radio.Model:GetAttribute("TrackName")
		RadioBehavior.Next(radio)
		check("the radio switches to the next song", radio.Model:GetAttribute("TrackName") ~= firstTrack and sound.Playing)
		RadioBehavior.Toggle(radio)
		check("the radio can be stopped", not sound.Playing and radio.Model:GetAttribute("Playing") == false)
	end

	-- Persistence: leaving and coming back
	local saved = #data.Deployed
	PlacementService.Unload(player)
	check("leaving removes placed objects from the world", PlacementService.GetEntry(radioUid) == nil and deployedCount(radioUid) == 0)
	check("leaving keeps them saved", #data.Deployed == saved and savedRecord(radioUid) ~= nil)
	PlacementService.Load(player)
	check("rejoining places them again with the same uid", PlacementService.GetEntry(radioUid) ~= nil and deployedCount(radioUid) == 1)
	local restored = PlacementService.GetEntry(radioUid)
	if restored ~= nil then
		character:PivotTo(CFrame.new(restored.Model:GetPivot().Position + Vector3.new(0, 3, 5)))
		PlacementService.Store(player, radioUid)
	end
	check("the radio is back in the hands", CarryService.HasUid(player, radioUid))
	CarryService.Clear(player)

	-- Metal detector
	local detectorUid = give("metal_detector")
	character:PivotTo(home)
	task.wait(0.1)
	local findPosition = root.Position + root.CFrame.LookVector * 6
	local find = JunkService.SpawnAt("dented_trophy", findPosition, {})
	local findUid = if find ~= nil then JunkService.GetUid(find) else nil
	local result = DetectorBehavior.Scan(player, detectorUid, ItemCapabilities.GetBehavior("metal_detector").Detector)
	check("the detector finds a rare item nearby", result ~= nil and result.Found and result.TargetUid == findUid,
		if result ~= nil then tostring(result.TargetUid) else "nil")
	check("the detector reports rarity and distance", result ~= nil and result.Rarity == "Rare" and type(result.Distance) == "number")
	local useOk = PlacementService.Use(player, detectorUid)
	check("using a carried detector works", useOk)
	local notCarriedOk, notCarriedCode = PlacementService.Use(player, JunkService.NewUid())
	check("using a detector that is not carried is rejected", not notCarriedOk and notCarriedCode == errors.NotCarried, tostring(notCarriedCode))
	local wrongUid = give("rusty_can")
	local wrongOk, wrongCode = PlacementService.Use(player, wrongUid)
	check("using plain junk is rejected", not wrongOk and wrongCode == errors.NotUsable, tostring(wrongCode))
	if findUid ~= nil then
		JunkService.Despawn(findUid)
	end

	CarryService.Clear(player)
	character:PivotTo(home)
end

---------------------------------------------------------------------------------------------
-- Stage 3: economy and progression
---------------------------------------------------------------------------------------------

local function runEconomyTests(player: Player)
	local root = waitForLiveRoot(player, 15)
	local dealerPosition = DealerService.GetPosition()
	local plot = PlotService.GetPlot(player)
	if root == nil or dealerPosition == nil or plot == nil then
		warn("[DevTests] no character, dealer or plot: economy tests skipped")
		return
	end
	local character = player.Character :: Model
	local humanoid = character:FindFirstChildOfClass("Humanoid") :: Humanoid
	local home = character:GetPivot()
	local data = DataService.GetData(player) :: any
	local savedKlunks = data.Klunks
	local savedProgress = table.clone(data.Progress)
	CarryService.Clear(player)
	local function atDealer()
		character:PivotTo(CFrame.new(dealerPosition + Vector3.new(0, 0, -6)))
		task.wait(0.1)
	end
	local function atBase()
		character:PivotTo(PlotService.GetPlotCFrame(plot) * CFrame.new(BaseConfig.Chest.Position + Vector3.new(4, 3, -5))) -- at the chest (Stage 4)
		task.wait(0.1)
	end
	local function setBalance(value: number)
		local current = CurrencyService.GetKlunks(player) :: number
		if value > current then
			CurrencyService.AddKlunks(player, value - current)
		elseif value < current then
			CurrencyService.RemoveKlunks(player, current - value)
		end
	end
	local function give(itemId: string): string
		local uid = JunkService.NewUid()
		CarryService.AddJunk(player, itemId, uid)
		return uid
	end
	local guid = function(): string
		return JunkService.NewUid()
	end

	-- Valuation
	local ranges = { Common = { 5, 15 }, Uncommon = { 15, 45 }, Rare = { 50, 130 }, Epic = { 130, 320 }, Legendary = { 350, 850 }, Mythic = { 1000, 2600 } }
	local outOfRange: { string } = {}
	for id, definition in ItemConfig.Items do
		if definition.IsDebug ~= true and Recipes.Get(id) == nil and EconomyConfig.ItemOverrides[id] == nil then
			local price = ItemValue.SellPrice(id)
			local range = (ranges :: any)[definition.Rarity]
			if price < range[1] or price > range[2] then
				table.insert(outOfRange, `{id}={price}`)
			end
		end
	end
	check("natural item prices follow their rarity range", #outOfRange == 0, table.concat(outOfRange, ", "))
	local profitable: { string } = {}
	for _, recipe in Recipes.List do
		if ItemValue.CanSell(recipe.OutputItemId) and ItemValue.SellPrice(recipe.OutputItemId) > ItemValue.IngredientValue(recipe) then
			table.insert(profitable, recipe.RecipeId)
		end
	end
	check("no crafted item sells for more than its ingredients", #profitable == 0, table.concat(profitable, ", "))
	local arbitrage: { string } = {}
	for _, entry in ShopConfig.Entries do
		if ItemValue.ShopPrice(entry) <= ItemValue.SellPrice(entry.ItemId) then
			table.insert(arbitrage, entry.Id)
		end
	end
	check("every shop price is above the item's sell price", #arbitrage == 0, table.concat(arbitrage, ", "))
	check("special items cannot be sold", not ItemValue.CanSell("aurora_reactor") and ItemValue.SellPrice("aurora_reactor") == 0)
	check("rewards cannot be recycled, yard junk can", not ItemConfig.CanBeRecycled("snow_globe") and not ItemConfig.CanBeRecycled("metal_sheet")
		and ItemConfig.CanBeRecycled("rusty_can"))

	-- Currency
	setBalance(1000)
	check("earning a non-integer amount is rejected", not EconomyService.Earn(player, 1.5, "Test"))
	check("earning zero is rejected", not EconomyService.Earn(player, 0, "Test"))
	local spendOk, spendCode = EconomyService.Spend(player, 5000, "Test")
	check("spending more than the balance is rejected", not spendOk and spendCode == EconomyService.Errors.NotEnough, tostring(spendCode))
	check("the balance is unchanged after rejected transactions", CurrencyService.GetKlunks(player) == 1000)
	local before = #EconomyService.GetTransactions(player)
	EconomyService.Earn(player, 10, "Test", "devtest-earn")
	local log = EconomyService.GetTransactions(player)
	local last = log[#log]
	check("a transaction is logged with type, amount, reason and id",
		(#log == before + 1 or #log == EconomyConfig.TransactionLog) and last.Type == "Earn" and last.Amount == 10 and last.Reason == "Test" and last.Id == "devtest-earn")

	-- Selling
	local canUid, tireUid = give("rusty_can"), give("old_tire")
	local storedUid = give("metal_sheet")
	atBase()
	local farOk, farCode = SellService.Sell(player, guid(), { canUid })
	check("selling away from the dealer is rejected", not farOk and farCode == SellService.Errors.NotAtDealer, tostring(farCode))
	atDealer()
	local picks, quote = SellService.Quote(player, { canUid, tireUid, storedUid })
	local expected = ItemValue.SellPrice("rusty_can") + ItemValue.SellPrice("old_tire") + ItemValue.SellPrice("metal_sheet")
	check("the quote uses the configured prices", picks ~= nil and quote == expected, `{tostring(quote)} vs {expected}`)
	local balanceBefore = CurrencyService.GetKlunks(player) :: number
	local requestId = guid()
	local sellOk, sellCode, earned = SellService.Sell(player, requestId, { canUid, tireUid, storedUid })
	check("selling carried items works", sellOk and earned == expected, tostring(sellCode))
	check("the money is paid exactly once", CurrencyService.GetKlunks(player) == balanceBefore + expected)
	check("sold items are consumed", not CarryService.HasUid(player, canUid) and not CarryService.HasUid(player, tireUid)
		and not CarryService.HasUid(player, storedUid))
	local chestUid = InventoryService.AddItem(player, "metal_sheet") :: string
	local chestOk, chestCode = SellService.Sell(player, guid(), { chestUid })
	check("an item in the chest cannot be sold", not chestOk and chestCode == SellService.Errors.NotOwned
		and InventoryService.HasItem(player, chestUid), tostring(chestCode))
	InventoryService.RemoveItem(player, chestUid)
	local dupOk, dupCode = SellService.Sell(player, requestId, { canUid })
	check("a repeated sale request is ignored", not dupOk and dupCode == SellService.Errors.Duplicate
		and CurrencyService.GetKlunks(player) == balanceBefore + expected, tostring(dupCode))
	local againOk, againCode = SellService.Sell(player, guid(), { canUid })
	check("a sold item cannot be sold again", not againOk and againCode == SellService.Errors.NotOwned, tostring(againCode))
	local fakeOk, fakeCode = SellService.Sell(player, guid(), { JunkService.NewUid() })
	check("selling an item the player does not own is rejected", not fakeOk and fakeCode == SellService.Errors.NotOwned, tostring(fakeCode))
	local keepUid = give("bolt_pack")
	local twiceOk, twiceCode = SellService.Sell(player, guid(), { keepUid, keepUid })
	check("the same item twice in one sale is rejected", not twiceOk and twiceCode == SellService.Errors.InvalidArguments
		and CarryService.HasUid(player, keepUid), tostring(twiceCode))
	local reactorUid = give("aurora_reactor")
	local mixOk, mixCode = SellService.Sell(player, guid(), { keepUid, reactorUid })
	check("one unsellable item cancels the whole sale", not mixOk and mixCode == SellService.Errors.NotSellable
		and CarryService.HasUid(player, keepUid) and CarryService.HasUid(player, reactorUid), tostring(mixCode))
	local emptyOk = SellService.Sell(player, guid(), {})
	check("an empty sale is rejected", not emptyOk)
	-- An item inside the machine is not the player's to sell.
	CarryService.Clear(player)
	local machine = MachineService.GetModel(player)
	if machine ~= nil then
		local anchor = machine:FindFirstChild("PromptAnchor", true) :: BasePart
		character:PivotTo(anchor.CFrame * CFrame.new(0, 0, -8))
		local busyUid = give("rusty_can")
		local recycled = MachineService.Recycle(player, busyUid)
		atDealer()
		local machineOk, machineCode = SellService.Sell(player, guid(), { busyUid })
		check("an item being recycled cannot be sold", recycled and not machineOk and machineCode == SellService.Errors.NotOwned, tostring(machineCode))
		MachineService.InstantFinish(player)
		local out = (MachineService.GetData(player) :: any).Output[1]
		if out ~= nil then
			character:PivotTo(anchor.CFrame * CFrame.new(0, 0, -8))
			MachineService.Take(player, out.Uid)
		end
	end
	CarryService.Clear(player)

	-- Haggler bonus
	data.PlayerUpgrades.Haggler = 2
	local bonusUid = give("crystal_shard")
	local _, bonusQuote = SellService.Quote(player, { bonusUid })
	check("the Haggler upgrade adds its bonus", bonusQuote == math.floor(ItemValue.SellPrice("crystal_shard") * 1.03),
		`{tostring(bonusQuote)}`)
	data.PlayerUpgrades.Haggler = nil
	CarryService.Clear(player)

	-- Shop (earlier tests earned discovery / machine XP: start these at level 1)
	data.Progress.Level = 1
	data.Progress.XP = 0
	atDealer()
	setBalance(10000)
	local lockedOk, lockedCode = ShopService.Buy(player, guid(), "circuit_board")
	check("a shop entry above the player's level is locked", not lockedOk and lockedCode == ShopService.Errors.LevelTooLow, tostring(lockedCode))
	local sheetPrice = ItemValue.ShopPrice({ ItemId = "metal_sheet" })
	local buyId = guid()
	local buyOk, buyCode, buyWhere = ShopService.Buy(player, buyId, "metal_sheet")
	check("buying a shop item works and goes to the hands", buyOk and buyWhere == "Hands" and CarryService.GetCount(player) == 1, tostring(buyCode))
	check("the shop charges its price once", CurrencyService.GetKlunks(player) == 10000 - sheetPrice)
	local repeatOk, repeatCode = ShopService.Buy(player, buyId, "metal_sheet")
	check("a repeated purchase request is ignored", not repeatOk and repeatCode == ShopService.Errors.Duplicate
		and CarryService.GetCount(player) == 1 and CurrencyService.GetKlunks(player) == 10000 - sheetPrice, tostring(repeatCode))
	while not CarryService.IsFull(player) do
		give("rusty_can")
	end
	local storedBefore = InventoryService.GetItemCount(player) :: number
	local fullOk, _, fullWhere = ShopService.Buy(player, guid(), "metal_sheet")
	check("with full hands the purchase goes to base storage", fullOk and fullWhere == "Storage"
		and InventoryService.GetItemCount(player) == storedBefore + 1)
	setBalance(3)
	local poorOk, poorCode = ShopService.Buy(player, guid(), "metal_sheet")
	check("buying without enough money is rejected", not poorOk and poorCode == ShopService.Errors.NotEnough
		and CurrencyService.GetKlunks(player) == 3, tostring(poorCode))
	CarryService.Clear(player)

	-- Player upgrades
	setBalance(20000)
	local upLockedOk, upLockedCode = PlayerUpgradeService.Buy(player, guid(), "CarryCapacity")
	check("an upgrade above the player's level is locked", not upLockedOk and upLockedCode == PlayerUpgradeService.Errors.LevelTooLow, tostring(upLockedCode))
	local speedId = guid()
	local speedOk = PlayerUpgradeService.Buy(player, speedId, "WalkSpeed")
	check("buying Snow Boots works", speedOk and data.PlayerUpgrades.WalkSpeed == 2)
	check("Snow Boots cost their price", CurrencyService.GetKlunks(player) == 20000 - (require(ReplicatedStorage.Shared.Config.PlayerUpgrades).Get("WalkSpeed") :: any).Levels[2].Price)
	check("Snow Boots raise the walk speed", humanoid.WalkSpeed == 17, tostring(humanoid.WalkSpeed))
	local speedAgainOk = PlayerUpgradeService.Buy(player, speedId, "WalkSpeed")
	check("a repeated upgrade request is ignored", not speedAgainOk and data.PlayerUpgrades.WalkSpeed == 2)
	data.Progress.Level = 2
	local carryOk = PlayerUpgradeService.Buy(player, guid(), "CarryCapacity")
	check("Bigger Backpack adds a hand slot", carryOk and CarryService.GetCapacity(player) == GameConfig.Carry.MaxJunk + 1
		and player:GetAttribute("CarryMax") == GameConfig.Carry.MaxJunk + 1)
	data.PlayerUpgrades.WalkSpeed = 5
	local maxOk, maxCode = PlayerUpgradeService.Buy(player, guid(), "WalkSpeed")
	check("an upgrade at its max level cannot be bought", not maxOk and maxCode == PlayerUpgradeService.Errors.MaxLevel, tostring(maxCode))
	check("upgrade levels are stored in the profile", type(data.PlayerUpgrades) == "table" and data.PlayerUpgrades.CarryCapacity == 2)
	atBase()
	local farUpOk, farUpCode = PlayerUpgradeService.Buy(player, guid(), "PickupRange")
	check("upgrades can only be bought at the dealer", not farUpOk and farUpCode == PlayerUpgradeService.Errors.NotAtDealer, tostring(farUpCode))
	-- Reset the upgrades the tests bought.
	data.PlayerUpgrades = {}
	PlayerUpgradeService.Refresh(player)
	check("resetting the upgrades restores the default effects", humanoid.WalkSpeed == 16
		and CarryService.GetCapacity(player) == GameConfig.Carry.MaxJunk and player:GetAttribute("Upgrade_WalkSpeed") == 1)

	-- Storage (hands <-> base)
	local boxUid = give("wooden_crate")
	atDealer()
	local awayOk, awayCode = StorageService.Move(player, "Store", boxUid)
	check("storing away from the base is rejected", not awayOk and awayCode == StorageService.Errors.NotAtBase, tostring(awayCode))
	atBase()
	local storeOk, storeCode = StorageService.Move(player, "Store", boxUid)
	check("an item moves from the hands into storage", storeOk and not CarryService.HasUid(player, boxUid)
		and InventoryService.HasItem(player, boxUid), tostring(storeCode))
	local dupAdd = CarryService.AddJunk(player, "wooden_crate", boxUid)
	check("a stored uid cannot also be in the hands", not dupAdd)
	local takeOk, takeCode = StorageService.Move(player, "Take", boxUid)
	check("it moves back into the hands with the same uid", takeOk and CarryService.HasUid(player, boxUid)
		and not InventoryService.HasItem(player, boxUid), tostring(takeCode))
	local storedUid2 = InventoryService.AddItem(player, "bolt_pack") :: string
	while not CarryService.IsFull(player) do
		give("rusty_can")
	end
	local handsFullOk, handsFullCode = StorageService.Move(player, "Take", storedUid2)
	check("taking with full hands is rejected", not handsFullOk and handsFullCode == StorageService.Errors.HandsFull
		and InventoryService.HasItem(player, storedUid2), tostring(handsFullCode))
	CarryService.Clear(player)

	-- Progression
	data.Progress.Level = 1
	data.Progress.XP = 0
	data.Progress.Discovered = {}
	give("rusty_can")
	local afterFirst = data.Progress.XP
	give("rusty_can")
	check("discovering an item gives XP once", afterFirst == Progression.Discover.Common and data.Progress.XP == afterFirst,
		`{afterFirst} / {data.Progress.XP}`)
	ProgressionService.AddXP(player, Progression.XpToNext(1) * 3, "Test")
	check("enough XP raises the level", data.Progress.Level >= 2 and player:GetAttribute("Level") == data.Progress.Level)

	-- Cleanup: restore what the tests changed.
	CarryService.Clear(player)
	for uid in InventoryService.GetAllItems(player) or {} do
		InventoryService.RemoveItem(player, uid)
	end
	data.Progress = savedProgress
	setBalance(savedKlunks)
	character:PivotTo(home)
end

---------------------------------------------------------------------------------------------
-- Stage 4: bases, chest, buildings, conveyor, replenishment, audio settings
---------------------------------------------------------------------------------------------

local function runBaseTests(player: Player)
	local root = waitForLiveRoot(player, 15)
	local plot = PlotService.GetPlot(player)
	if root == nil or plot == nil then
		warn("[DevTests] no character or plot: base tests skipped")
		return
	end
	local character = player.Character :: Model
	local home = character:GetPivot()
	local data = DataService.GetData(player) :: any
	local savedBase = data.Base
	local savedKlunks = data.Klunks
	local savedLevel = data.Progress.Level
	data.Base = { Level = 1, ChestLevel = 1, Buildings = {} }
	-- Rebuild the base from the fresh test state (like a rejoin).
	PlotService.PlotReleased:Fire(player, plot)
	PlotService.PlotAssigned:Fire(player, plot)
	task.wait(0.3)
	CarryService.Clear(player)
	for uid in InventoryService.GetAllItems(player) or {} do
		InventoryService.RemoveItem(player, uid)
	end
	local function setBalance(value: number)
		local current = CurrencyService.GetKlunks(player) :: number
		if value > current then
			CurrencyService.AddKlunks(player, value - current)
		elseif value < current then
			CurrencyService.RemoveKlunks(player, current - value)
		end
	end
	local function give(itemId: string): string
		local uid = JunkService.NewUid()
		CarryService.AddJunk(player, itemId, uid)
		return uid
	end
	local guid = function(): string
		return JunkService.NewUid()
	end
	local top = PlotService.GetPlotCFrame(plot)
	local function atChest()
		character:PivotTo(top * CFrame.new(BaseConfig.Chest.Position + Vector3.new(4, 3, -5)))
		task.wait(0.1)
	end
	local function atPlotCenter()
		character:PivotTo(top * CFrame.new(0, 3, -10))
		task.wait(0.1)
	end

	-- The base
	local folder = plot:FindFirstChild("PlayerBase")
	local chest = if folder ~= nil then folder:FindFirstChild("Chest") else nil
	check("the player's base is built on their plot", folder ~= nil and folder:GetAttribute("OwnerUserId") == player.UserId)
	check("the base has a chest owned by the player", chest ~= nil and chest:GetAttribute("OwnerUserId") == player.UserId)
	local pads, unlocked = 0, 0
	for _, child in (folder :: Instance):GetChildren() do
		if child:GetAttribute("SlotId") ~= nil then
			pads += 1
			if child:GetAttribute("Unlocked") then
				unlocked += 1
			end
		end
	end
	check("every slot has a pad and base level 1 unlocks one", pads == #BaseConfig.Slots and unlocked == 1, `{pads} / {unlocked}`)
	check("a level 1 chest holds 10 items", BaseService.GetStorageCapacity(player) == 10 and player:GetAttribute("StorageMax") == 10)

	-- Chest storage
	local farUid = give("rusty_can")
	atPlotCenter()
	character:PivotTo(top * CFrame.new(15, 3, -14))
	task.wait(0.1)
	local farOk, farCode = StorageService.Move(player, "Store", farUid)
	check("storing away from the chest is rejected", not farOk and farCode == StorageService.Errors.NotAtBase, tostring(farCode))
	atChest()
	local storedOk = StorageService.Move(player, "Store", farUid)
	check("storing at the chest works", storedOk and InventoryService.HasItem(player, farUid))
	for _ = 1, 9 do
		InventoryService.AddItem(player, "bolt_pack")
	end
	local overUid = give("old_boot")
	local fullOk, fullCode = StorageService.Move(player, "Store", overUid)
	check("a full chest refuses more items", not fullOk and fullCode == StorageService.Errors.StorageFull
		and CarryService.HasUid(player, overUid), tostring(fullCode))
	for _, rarity in { "Rare", "Epic", "Legendary", "Mythic" } do
		InventoryService.RemoveItem(player, farUid)
		local pool = ItemConfig.GetRewardPool(rarity)
		local rareUid = give(pool[1])
		local ok = StorageService.Move(player, "Store", rareUid)
		check(`a {rarity} item can be stored`, ok and InventoryService.HasItem(player, rareUid))
		farUid = rareUid
	end

	-- Chest upgrade
	setBalance(100)
	local poorOk, poorCode = BaseService.Act(player, guid(), "UpgradeChest")
	check("a chest upgrade without money is rejected", not poorOk and poorCode == BaseService.Errors.NotEnough, tostring(poorCode))
	setBalance(5000)
	local chestId = guid()
	local chestOk = BaseService.Act(player, chestId, "UpgradeChest")
	local newChest = (plot:FindFirstChild("PlayerBase") :: Instance):FindFirstChild("Chest")
	check("the chest can be upgraded", chestOk and data.Base.ChestLevel == 2 and BaseService.GetStorageCapacity(player) == 20)
	check("the chest upgrade costs its price", CurrencyService.GetKlunks(player) == 5000 - BaseConfig.Chest.Levels[2].Price)
	check("the chest model changes with its level", newChest ~= nil and newChest:GetAttribute("ChestLevel") == 2)
	local againOk, againCode = BaseService.Act(player, chestId, "UpgradeChest")
	check("a repeated chest upgrade request is ignored", not againOk and againCode == BaseService.Errors.Duplicate and data.Base.ChestLevel == 2, tostring(againCode))
	local overOk = StorageService.Move(player, "Store", overUid)
	check("the bigger chest takes the waiting item", overOk)

	-- Buildings
	local awayOk, awayCode = (function()
		character:PivotTo(CFrame.new(DealerService.GetPosition() :: Vector3))
		task.wait(0.1)
		return BaseService.Act(player, guid(), "Build", "S1", "Conveyor")
	end)()
	check("building away from the base is rejected", not awayOk and awayCode == BaseService.Errors.NotAtBase, tostring(awayCode))
	atPlotCenter()
	local lockedOk, lockedCode = BaseService.Act(player, guid(), "Build", "S2", "Lantern")
	check("a locked slot cannot be built on", not lockedOk and lockedCode == BaseService.Errors.SlotLocked, tostring(lockedCode))
	local badOk, badCode = BaseService.Act(player, guid(), "Build", "S1", "Castle")
	check("an unknown building is rejected", not badOk and badCode == BaseService.Errors.UnknownBuilding, tostring(badCode))
	local rackOk, rackCode = BaseService.Act(player, guid(), "Build", "S1", "StorageRack")
	check("a building above the base level is rejected", not rackOk and rackCode == BaseService.Errors.BaseLevelTooLow, tostring(rackCode))
	setBalance(5000)
	local buildId = guid()
	local buildOk, buildCode = BaseService.Act(player, buildId, "Build", "S1", "Conveyor")
	check("a conveyor can be built on slot 1", buildOk and data.Base.Buildings.S1 ~= nil and data.Base.Buildings.S1.Id == "Conveyor", tostring(buildCode))
	check("building costs its price", CurrencyService.GetKlunks(player) == 5000 - BaseConfig.Buildings.Conveyor.Levels[1].Price)
	local takenOk, takenCode = BaseService.Act(player, guid(), "Build", "S1", "Lantern")
	check("an occupied slot cannot be built on again", not takenOk and takenCode == BaseService.Errors.SlotTaken, tostring(takenCode))
	local repeatOk = BaseService.Act(player, buildId, "Build", "S1", "Conveyor")
	check("a repeated build request is ignored", not repeatOk)
	local conveyorModel: Model? = nil
	for _, child in (plot:FindFirstChild("PlayerBase") :: Instance):GetChildren() do
		if child:GetAttribute("BuildingId") == "Conveyor" and child:IsA("Model") and child:FindFirstChild("Belt") then
			conveyorModel = child
		end
	end
	check("the conveyor model stands on the slot", conveyorModel ~= nil)
	local _, slotCode = PlacementRules.Check({ UserId = player.UserId, ModelName = "Radio",
		Position = (top * CFrame.new(BaseConfig.Slots[1].Position)).Position, Yaw = 0 })
	check("nothing can be placed onto a building slot", slotCode == "Blocked", tostring(slotCode))

	-- Conveyor: an item on the belt rolls into the chest with the same uid
	if conveyorModel ~= nil then
		local belt = conveyorModel:FindFirstChild("Belt") :: BasePart
		local start = belt.CFrame * CFrame.new(0, 0.2, -2.5)
		local junk = JunkService.SpawnAt("pipe_segment", start.Position + Vector3.new(0, 1, 0), {})
		local junkUid = if junk ~= nil then JunkService.GetUid(junk) else nil
		check("an item can lie on the conveyor", junkUid ~= nil)
		if junkUid ~= nil then
			local startLocal = belt.CFrame:PointToObjectSpace(JunkService.GetPosition(junk :: Model) :: Vector3)
			for _ = 1, 30 do
				ConveyorModule.Step(0.15)
			end
			if not InventoryService.HasItem(player, junkUid) then
				local now = JunkService.GetByUid(junkUid)
				warn(`[DevTests] conveyor: started at {startLocal}, now {if now ~= nil then tostring(belt.CFrame:PointToObjectSpace(JunkService.GetPosition(now) :: Vector3)) else "gone"}`)
			end
			check("the conveyor moves the item into the chest with the same uid",
				InventoryService.HasItem(player, junkUid) and JunkService.GetByUid(junkUid) == nil)
		end
	end

	-- Base expansion and more buildings
	data.Progress.Level = 3
	setBalance(10000)
	local expandOk, expandCode = BaseService.Act(player, guid(), "UpgradeBase")
	local pad2 = (plot:FindFirstChild("PlayerBase") :: Instance):FindFirstChild("SlotS2")
	check("the base can be expanded", expandOk and data.Base.Level == 2 and pad2 ~= nil and pad2:GetAttribute("Unlocked") == true, tostring(expandCode))
	local rackLevelOk, rackLevelCode = BaseService.Act(player, guid(), "Build", "S2", "StorageRack")
	check("a building above the player's level is rejected", not rackLevelOk and rackLevelCode == BaseService.Errors.LevelTooLow, tostring(rackLevelCode))
	data.Progress.Level = 4
	local capacityBefore = BaseService.GetStorageCapacity(player)
	local rack2Ok = BaseService.Act(player, guid(), "Build", "S2", "StorageRack")
	check("a storage rack adds chest slots", rack2Ok and BaseService.GetStorageCapacity(player) == capacityBefore + 15)
	local rack3Ok, rack3Code = BaseService.Act(player, guid(), "Build", "S3", "StorageRack")
	check("building limits are respected", not rack3Ok and rack3Code == BaseService.Errors.LimitReached, tostring(rack3Code))
	local balanceBefore = CurrencyService.GetKlunks(player) :: number
	local removeOk = BaseService.Act(player, guid(), "Remove", "S2")
	check("removing a building refunds half", removeOk and data.Base.Buildings.S2 == nil
		and CurrencyService.GetKlunks(player) == balanceBefore + math.floor(BaseConfig.Buildings.StorageRack.Levels[1].Price * BaseConfig.RemoveRefund))
	check("the base state is saved in the profile", type(data.Base) == "table" and data.Base.Buildings.S1 ~= nil)

	-- Replenishment
	local target = JunkService.GetTarget()
	check("the yard target scales from the base value", target >= GameConfig.Junk.Replenish.BaseTarget and target <= GameConfig.Junk.Replenish.MaxTarget)
	local refillAt = workspace:GetAttribute("JunkRefillAt")
	check("the next scrap delivery time is published", type(refillAt) == "number" and refillAt > workspace:GetServerTimeNow())
	local before: { [Model]: boolean } = {}
	for _, model in JunkService.GetActiveJunk() do
		before[model] = true
	end
	-- Take a few natural items away, then deliver.
	local taken = 0
	for _, model in JunkService.GetActiveJunk() do
		if taken < 5 then
			local id = JunkService.Claim(model, nil)
			if id ~= nil then
				taken += 1
				before[model] = nil
			end
		end
	end
	local survivors = 0
	for model in before do
		if JunkService.IsActive(model) then
			survivors += 1
		end
	end
	local naturalBefore = JunkService.GetNaturalCount()
	local spawned = JunkService.Replenish()
	check("a delivery only fills the gap (the yard is not reset)", JunkService.GetNaturalCount() <= target
		and spawned <= math.max(0, target - naturalBefore))
	local stillThere = 0
	for model in before do
		if JunkService.IsActive(model) then
			stillThere += 1
		end
	end
	check("items already lying in the yard stay after a delivery", stillThere == survivors, `{stillThere}/{survivors}`)
	local tooClose = 0
	for _, model in JunkService.GetActiveJunk() do
		if not before[model] and JunkService.GetPosition(model) ~= nil
			and ((JunkService.GetPosition(model) :: Vector3) - root.Position).Magnitude < GameConfig.Junk.Replenish.MinPlayerDistance
		then
			tooClose += 1
		end
	end
	check("delivered items never appear right next to a player", tooClose == 0, tostring(tooClose))
	check("the world never exceeds MaxActive", JunkService.GetActiveCount() <= GameConfig.Junk.MaxActive)

	-- Audio settings
	local saved = AudioService.SaveSettings(player, { Music = 0.3, Sfx = 2, Muted = true })
	local audio = data.Settings.Audio
	check("audio settings are saved and clamped", saved and audio.Music == 0.3 and audio.Sfx == 1 and audio.Muted == true)
	local badSave = AudioService.SaveSettings(player, { Music = "loud", Sfx = 0.5, Muted = false })
	check("invalid audio settings are rejected", not badSave and audio.Music == 0.3)
	AudioService.SaveSettings(player, { Music = 0.6, Sfx = 0.8, Muted = false })

	-- Cleanup: back to the player's own base and balance.
	CarryService.Clear(player)
	for uid in InventoryService.GetAllItems(player) or {} do
		InventoryService.RemoveItem(player, uid)
	end
	data.Base = savedBase
	data.Progress.Level = savedLevel
	PlotService.PlotReleased:Fire(player, plot)
	PlotService.PlotAssigned:Fire(player, plot)
	setBalance(savedKlunks)
	character:PivotTo(home)
end

---------------------------------------------------------------------------------------------
-- Abilities, Starter Pack / cosmetics, leaderboards, world
---------------------------------------------------------------------------------------------

local function runMonetizationTests(player: Player)
	local root = waitForLiveRoot(player, 15)
	if root == nil then
		warn("[DevTests] no character: monetization tests skipped")
		return
	end
	local data = DataService.GetData(player) :: any
	local saved = {
		ChestLevel = data.Base.ChestLevel,
		Cosmetics = data.Cosmetics,
		Entitlements = data.Entitlements,
		Cooldowns = data.Cooldowns,
	}
	CarryService.Clear(player)

	-- Abilities (Comet Shard / Starforged Core)
	data.Cooldowns = {}
	local cometUid = JunkService.NewUid()
	CarryService.AddJunk(player, "comet_shard", cometUid)
	check("the Comet Shard has a click ability", ItemCapabilities.Get("comet_shard").CanBeUsed
		and ItemCapabilities.Get("comet_shard").Behavior.Kind == "Ability")
	task.wait(0.6) -- the previous test rebuilt the base; PlacementService loads 0.2 s later
	local cometOk, cometCode = PlacementService.Use(player, cometUid)
	local readyAt = player:GetAttribute("Cooldown_Comet")
	check("summoning a comet works", cometOk, tostring(cometCode))
	check("the comet then recharges for 5 minutes", type(readyAt) == "number" and math.abs(readyAt - (os.time() + 300)) <= 2, tostring(readyAt))
	check("a second comet during the cooldown is refused", not PlacementService.Use(player, cometUid))
	check("the cooldown is saved in the profile", type(data.Cooldowns.Comet) == "number")
	check("the comet is not consumed", CarryService.HasUid(player, cometUid))
	local coreUid = JunkService.NewUid()
	CarryService.AddJunk(player, "starforged_core", coreUid)
	check("the Starforged Core starts a starfall", PlacementService.Use(player, coreUid) and type(player:GetAttribute("Cooldown_Starfall")) == "number")
	CarryService.TakeByUid(player, cometUid)
	check("an ability item that is not carried cannot be used", not PlacementService.Use(player, cometUid))
	CarryService.Clear(player)

	-- Starter Pack (Game Pass) - simulated ownership in Studio only
	local carryBefore = CarryService.GetCapacity(player)
	data.Base.ChestLevel = 1
	data.Cosmetics = { Owned = {}, Equipped = {} }
	data.Entitlements = {}
	player:SetAttribute("Pass_StarterPack", nil)
	local notOwned = MonetizationService.VerifyPassForTest(player, "StarterPack", 123, function()
		return false
	end)
	check("no rewards without ownership", notOwned == false and data.Base.ChestLevel == 1 and next(data.Cosmetics.Owned) == nil)
	local failed = MonetizationService.VerifyPassForTest(player, "StarterPack", 123, function(): boolean
		error("HTTP 503 (simulated)")
	end)
	check("no rewards when the ownership API fails", failed == nil and data.Base.ChestLevel == 1 and next(data.Cosmetics.Owned) == nil)
	local owned = MonetizationService.VerifyPassForTest(player, "StarterPack", 123, function()
		return true
	end)
	check("owning the Starter Pack grants it", owned == true and player:GetAttribute("Pass_StarterPack") == true)
	check("the chest becomes level 3 (35 slots)", data.Base.ChestLevel == 3 and BaseService.GetStorageCapacity(player) == 35)
	local count = 0
	for _ in data.Cosmetics.Owned do
		count += 1
	end
	check("all four Starter Pack cosmetics are unlocked", count == 4 and CosmeticsService.IsOwned(player, "companion_snowbot")
		and CosmeticsService.IsOwned(player, "title_early_scrapper"))
	check("the entitlement is recorded", type(data.Entitlements.StarterPack) == "table")
	check("the cosmetic backpack does not change carry capacity", CarryService.GetCapacity(player) == carryBefore and carryBefore == GameConfig.Carry.MaxJunk)
	task.wait(0.3)
	local companion = CompanionService.Get(player)
	check("the robot companion appears", companion ~= nil and companion.Parent ~= nil and companion:GetAttribute("OwnerUserId") == player.UserId)
	local character = player.Character :: Model
	check("the backpack, shovel and title are worn", character:FindFirstChild("JunkshotCosmetics") ~= nil
		and #(character:FindFirstChild("JunkshotCosmetics") :: Instance):GetChildren() >= 3)
	MonetizationService.ApplyPass(player, "StarterPack")
	local again = 0
	for _ in data.Cosmetics.Owned do
		again += 1
	end
	check("granting again changes nothing (idempotent)", again == 4 and data.Base.ChestLevel == 3)
	data.Base.ChestLevel = 5
	MonetizationService.ApplyPass(player, "StarterPack")
	check("a higher chest level is never lowered", data.Base.ChestLevel == 5)

	-- Cosmetics: equip rules
	local badOk, badCode = CosmeticsService.Equip(player, "Companion", "companion_unknown")
	check("equipping an unknown cosmetic is refused", not badOk and badCode == "InvalidCosmetic", tostring(badCode))
	local wrongOk = CosmeticsService.Equip(player, "Title", "companion_snowbot")
	check("a cosmetic only fits its own category", not wrongOk)
	data.Cosmetics.Owned.title_early_scrapper = nil
	local unownedOk, unownedCode = CosmeticsService.Equip(player, "Title", "title_early_scrapper")
	check("equipping an unowned cosmetic is refused", not unownedOk and unownedCode == "NotOwned", tostring(unownedCode))
	local offOk = CosmeticsService.Equip(player, "Companion", "")
	task.wait(0.2)
	check("unequipping the companion removes it", offOk and CompanionService.Get(player) == nil)
	CompanionService.Refresh(player)
	check("without an equipped companion nothing spawns", CompanionService.Get(player) == nil)

	-- Leaderboard and world
	local stats = player:FindFirstChild("leaderstats")
	local klunksValue = if stats ~= nil then stats:FindFirstChild(GameConfig.Klunks.Name) else nil
	check("the player list shows the balance", klunksValue ~= nil and (klunksValue :: IntValue).Value == CurrencyService.GetKlunks(player))
	check("the leaderboards stand on the plaza", workspace:FindFirstChild("LeaderboardServer") ~= nil and workspace:FindFirstChild("LeaderboardGlobal") ~= nil)
	local sky = game:GetService("Lighting"):FindFirstChildOfClass("Sky")
	check("the winter sky has stars", sky ~= nil and sky.StarCount > 0)
	check("the day cycle includes a night", WorldServiceModule.ClockAt(15 * 60) > 18.5 or WorldServiceModule.ClockAt(15 * 60) < 8.5)

	-- Cleanup
	data.Base.ChestLevel = saved.ChestLevel
	data.Cosmetics = saved.Cosmetics
	data.Entitlements = saved.Entitlements
	data.Cooldowns = saved.Cooldowns
	player:SetAttribute("Pass_StarterPack", nil)
	player:SetAttribute("Cooldown_Comet", nil)
	player:SetAttribute("Cooldown_Starfall", nil)
	CosmeticsService.Equip(player, "Backpack", nil)
	CompanionService.Refresh(player)
	PlotService.PlotReleased:Fire(player, PlotService.GetPlot(player))
	PlotService.PlotAssigned:Fire(player, PlotService.GetPlot(player))
end

-- Ownership on bases, trophy stand, new placeables, radio controls.
local function runFixTests(player: Player)
	local plot = PlotService.GetPlot(player)
	local data = DataService.GetData(player) :: any
	if plot == nil or data == nil then
		return
	end
	CarryService.Clear(player)
	-- An item lying on a base belongs to the owner.
	local spot = (PlotService.GetPlotCFrame(plot) * CFrame.new(-2, 0.5, -18)).Position
	check("a point on the base has an owner", PlotService.OwnerAt(spot) == player.UserId)
	check("the plaza has no owner", PlotService.OwnerAt(Vector3.new(0, 1, 30)) == nil)
	local junk = JunkService.SpawnAt("rusty_can", spot)
	check("an item lies on the base", junk ~= nil)
	if junk ~= nil then
		local stranger: any = { UserId = -12345 }
		check("another player cannot take it", not JunkService.CanClaim(junk, stranger) and JunkService.Claim(junk, stranger) == nil)
		check("its owner can", JunkService.CanClaim(junk, player))
		JunkService.Despawn(JunkService.GetUid(junk) :: string)
	end
	-- Trophy stand
	local savedBuildings, savedLevel = data.Base.Buildings, data.Base.Level
	data.Base.Level = math.max(savedLevel, 1)
	data.Base.Buildings = { [BaseConfig.Slots[1].Id] = { Id = "DisplayStand", Level = 1 } }
	PlotService.PlotReleased:Fire(player, plot)
	PlotService.PlotAssigned:Fire(player, plot)
	task.wait(0.8)
	teleportNear(player, PlotService.GetPlotCFrame(plot) * CFrame.new(0, 4, -4))
	task.wait(0.2)
	local trophy = InventoryService.AddItem(player, "snow_globe") :: string
	local setOk, setCode = BaseService.Act(player, JunkService.NewUid(), "SetTrophy", BaseConfig.Slots[1].Id, trophy)
	check("the trophy stand shows the chosen chest item", setOk and data.Base.Buildings[BaseConfig.Slots[1].Id].Shown == trophy, tostring(setCode))
	check("the trophy stays in the chest", InventoryService.HasItem(player, trophy))
	local badOk = BaseService.Act(player, JunkService.NewUid(), "SetTrophy", BaseConfig.Slots[1].Id, JunkService.NewUid())
	check("an item the player does not store cannot be shown", not badOk)
	InventoryService.RemoveItem(player, trophy)
	data.Base.Buildings, data.Base.Level = savedBuildings, savedLevel
	PlotService.PlotReleased:Fire(player, plot)
	PlotService.PlotAssigned:Fire(player, plot)
	task.wait(0.8)
	for _, className in { "BloomEffect", "Atmosphere", "ColorCorrectionEffect" } do
		local effects = 0
		for _, child in game:GetService("Lighting"):GetChildren() do
			effects += if child.ClassName == className then 1 else 0
		end
		check(`exactly one {className}`, effects == 1, tostring(effects))
	end
	-- Sled and scooter
	check("the sled is a 4-item cart", ItemCapabilities.Get("wooden_sled").Behavior.Kind == "Cart" and ItemCapabilities.Get("wooden_sled").Behavior.Cart.Capacity == 4)
	check("the scooter is 1.5 times as fast as the bicycle",
		ItemCapabilities.Get("scooter").Behavior.Vehicle.MaxSpeed == ItemCapabilities.Get("bicycle").Behavior.Vehicle.MaxSpeed * 1.5)
	for _, id in { "wooden_sled", "scooter", "boombox_radio" } do
		local definition = ItemConfig.Get(id)
		if definition == nil then
			continue
		end
		local uid = JunkService.NewUid()
		CarryService.AddJunk(player, id, uid)
		teleportNear(player, CFrame.new(0, 4, -70))
		task.wait(0.3)
		local placed, code = PlacementService.Place(player, uid, Vector3.new(0, 0.2, -60), 0)
		check(`{id} can be placed`, placed, tostring(code))
		local entry = PlacementService.GetEntry(uid)
		if entry ~= nil then
			check(`{id} shows its owner's name`, entry.Model:FindFirstChild("OwnerTag", true) ~= nil)
			if entry.Kind == "Cart" then
				for _ = 1, 5 do
					CarryService.AddJunk(player, "rusty_can")
				end
				local loadedCount = 0
				for _ = 1, 5 do
					if CartBehavior.Load(entry, player) then
						loadedCount += 1
					end
				end
				check("the sled holds exactly 4 items", loadedCount == 4, tostring(loadedCount))
				for _ = 1, 4 do
					CartBehavior.Unload(entry, player)
				end
				CarryService.Clear(player)
			elseif entry.Kind == "Radio" then
				RadioBehavior.Toggle(entry)
				check("the radio prompt says Stop while playing", entry.State.TogglePrompt.ActionText == "Stop")
				RadioBehavior.Pause(entry)
				check("pause keeps the song but silences it", entry.State.Playing and not entry.State.Sound.Playing)
				RadioBehavior.Previous(entry)
				check("previous wraps to the last song", entry.State.Track == #entry.Behavior.Radio.Tracks and entry.State.Sound.Playing)
				RadioBehavior.Toggle(entry)
				check("the radio prompt says Play when stopped", entry.State.TogglePrompt.ActionText == "Play" and not entry.State.PausePrompt.Enabled)
			end
			check(`{id} can be picked up again`, (PlacementService.Store(player, uid)))
		end
		CarryService.Clear(player)
	end
end

local function runCreatureTests(player: Player)
	local root = waitForLiveRoot(player, 15)
	if root == nil then
		warn("[DevTests] no character: creature tests skipped")
		return
	end
	local home = root.CFrame
	local Errors = WorldEventService.Errors
	local pool = ItemConfig.GetRewardPool("Rare")
	local function claim(model: any): (boolean, string?)
		task.wait(WorldEventConfig.ClaimCooldown + 0.1)
		return WorldEventService.TryClaim(player, model)
	end
	WorldEventService.Despawn()
	CarryService.Clear(player)

	local valid = 0
	for index, point in WorldEventConfig.SpawnPoints do
		if WorldEventService.CheckSpawnPoint(point) ~= nil then
			valid += 1
		else
			print(`[DevTests] spawn point {index} ({point}) is not usable right now`)
		end
	end
	check("most creature spawn points are usable", valid >= #WorldEventConfig.SpawnPoints * 0.7, `{valid}/{#WorldEventConfig.SpawnPoints}`)
	local plot = PlotService.GetPlot(player)
	check("a point on a base plot is refused", plot ~= nil and WorldEventService.CheckSpawnPoint(plot:GetPivot().Position) == nil)
	check("a point outside the map is refused", WorldEventService.CheckSpawnPoint(Vector3.new(5000, 0, 5000)) == nil)

	local model = WorldEventService.SpawnNow()
	check("a creature spawns", model ~= nil and WorldEventService.GetActive() == model)
	if model == nil then
		return
	end
	check("only one creature at a time", WorldEventService.SpawnNow() == nil)
	check("it has a prompt", model:FindFirstChild("CatchPrompt", true) ~= nil)
	check("it is a tagged, active creature", model:HasTag(WorldEventConfig.Tag) and model:GetAttribute("State") == "Active")

	local spot = model:GetPivot().Position
	teleportNear(player, CFrame.new(spot + Vector3.new(WorldEventConfig.ClaimDistance + 20, 4, 0)))
	local ok, err = claim(model)
	check("too far away is refused", not ok and err == Errors.TooFar, tostring(err))
	teleportNear(player, CFrame.new(spot + Vector3.new(3, 4, 0)))
	ok, err = WorldEventService.TryClaim(player, model)
	check("repeated requests are rate limited", not ok and err == Errors.TooFast, tostring(err))
	teleportNear(player, CFrame.new(spot + Vector3.new(3, 4, 0)))
	ok, err = claim(model)
	local carriedList = CarryService.GetCarried(player)
	check("a close player catches it", ok, tostring(err))
	check("exactly one Rare item is in the hands", #carriedList == 1 and table.find(pool, carriedList[1].Id) ~= nil)
	check("the model says who won what", model:GetAttribute("ClaimedBy") == player.UserId
		and model:GetAttribute("RewardId") == (carriedList[1] and carriedList[1].Id) and model:GetAttribute("RewardWhere") == "Hands")
	check("the prompt is gone at once", model:FindFirstChild("CatchPrompt", true) == nil)
	ok, err = claim(model)
	check("a second claim gets nothing", not ok and err == Errors.Gone and CarryService.GetCount(player) == 1, tostring(err))
	task.wait(WorldEventConfig.FadeTime + 0.2)
	check("the caught creature is removed", model.Parent == nil)

	-- Full hands: the reward falls on the ground, reserved for the winner.
	while CarryService.GetCount(player) < CarryService.GetCapacity(player) do
		if not CarryService.AddJunk(player, pool[1]) then
			break
		end
	end
	local before = CarryService.GetCount(player)
	local second = WorldEventService.SpawnNow()
	if second ~= nil then
		teleportNear(player, CFrame.new(second:GetPivot().Position + Vector3.new(3, 4, 0)))
		ok, err = claim(second)
		check("full hands still win", ok, tostring(err))
		check("the hands did not change", CarryService.GetCount(player) == before)
		check("the reward is on the ground", second:GetAttribute("RewardWhere") == "Ground")
		local found: Model? = nil
		JunkService.ForEachClaimable(function(junk, _uid, id, position, reservedFor)
			if id == second:GetAttribute("RewardId") and reservedFor == player.UserId
				and (position - second:GetPivot().Position).Magnitude < 25 then
				found = junk
			end
		end)
		check("it is reserved for the winner", found ~= nil)
		if found ~= nil then
			local uid = JunkService.GetUid(found)
			if uid ~= nil then
				JunkService.Despawn(uid)
			end
		end
	else
		check("a second creature spawns", false)
	end

	-- Leaving
	local third = WorldEventService.SpawnNow()
	check("a third creature spawns", third ~= nil)
	if third ~= nil then
		teleportNear(player, CFrame.new(third:GetPivot().Position + Vector3.new(3, 4, 0)))
		WorldEventService.Despawn()
		ok, err = claim(third)
		check("a departed creature cannot be caught", not ok and err == Errors.Gone, tostring(err))
	end
	check("nothing is active afterwards", WorldEventService.GetActive() == nil)
	CarryService.Clear(player)
	teleportNear(player, home)
end

function DevTests.Run()
	print("[DevTests] waiting for a player...")
	local player = waitForPlayer(60)
	if player == nil then
		warn("[DevTests] no player joined within 60s; tests skipped")
		return
	end

	local data = DataService.WaitForData(player, 30)
	if data == nil then
		warn("[DevTests] player data did not load within 30s; tests skipped")
		return
	end
	check("profile is loaded and DataLoaded attribute is set", player:GetAttribute("DataLoaded") == true)

	runCurrencyTests(player)
	runInventoryTests(player)
	runCatalogTests()
	runJunkServiceTests()
	runCarryTests(player)
	runPickupTests(player)
	runBallisticsTests()
	runThrowTests(player)
	runRewardTests()
	runMachineTests(player)
	runItemTests(player)
	runEconomyTests(player)
	runBaseTests(player)
	runMonetizationTests(player)
	runCreatureTests(player)
	runFixTests(player)

	print(`[DevTests] done: {passed} passed, {failed} failed`)
end

return DevTests
