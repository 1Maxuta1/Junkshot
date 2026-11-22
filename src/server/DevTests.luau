--!strict
--[[
	DevTests: automated server-side checks (data, currency, inventory, junk, carry, throw).
	STUDIO ONLY.

	Enabled by GameConfig.Debug.EnableDevTests = true (Main.server also requires
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
		local againOk = MachineService.Recycle(player, reward.Uid)
		check("the reward can be recycled again", againOk)
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

	print(`[DevTests] done: {passed} passed, {failed} failed`)
end

return DevTests
