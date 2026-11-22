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
local JunkConfig = require(ReplicatedStorage.Shared.Config.JunkConfig)
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

local function runJunkConfigTests()
	local count = 0
	local failures: { string } = {}
	for id in JunkConfig.Items do
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
	check("JunkConfig defines exactly 20 junk types", count == 20, tostring(count))
	check("every junk type builds in World and Cosmetic mode", #failures == 0, table.concat(failures, ", "))
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
	check("active junk has a valid junk id", junkId ~= nil and JunkConfig.Exists(junkId))
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
-- Stage 2: rarity rolls and the Recycling Machine
---------------------------------------------------------------------------------------------

local function runRewardTests()
	local samples = 200_000
	local counts: { [string]: number } = {}
	for _ = 1, samples do
		local rarity = RewardService.RollRarity()
		counts[rarity] = (counts[rarity] or 0) + 1
	end
	for _, rarityId in Rarities.Order do
		local expected = Rarities.Info[rarityId].Chance
		local actual = (counts[rarityId] or 0) / samples * 100
		-- About 5 standard deviations, so the test is practically never flaky.
		local tolerance = 5 * math.sqrt(expected * (100 - expected) / samples) + 0.01
		check(
			`{rarityId} rolls about {expected}%`,
			math.abs(actual - expected) <= tolerance,
			string.format("%.3f%% (allowed %.3f)", actual, tolerance)
		)
	end
	for _, rarityId in Rarities.Order do
		local itemId = RewardService.RollItem(rarityId)
		local definition = ItemConfig.Get(itemId)
		check(
			`a {rarityId} roll gives a non-debug {rarityId} item`,
			definition ~= nil and definition.Rarity == rarityId and definition.IsDebug ~= true,
			itemId
		)
	end
end

local function findMachineModel(): Model?
	for _, instance in game:GetService("CollectionService"):GetTagged(MachineConfig.Tag) do
		if instance:IsA("Model") and instance:GetAttribute("MachineId") == "Main" then
			return instance
		end
	end
	return nil
end

local function runMachineTests(player: Player)
	local errors = MachineService.Errors
	local model = findMachineModel()
	check("the Recycling Machine exists in the world", model ~= nil)
	if model == nil then
		return
	end
	check("the machine starts Idle", MachineService.GetState("Main") == "Idle" and model:GetAttribute("State") == "Idle")
	local anchor = model:FindFirstChild("PromptAnchor", true) :: BasePart?
	local character = player.Character
	local root = waitForLiveRoot(player, 15)
	if anchor == nil or character == nil or root == nil then
		warn("[DevTests] no machine anchor or live character: machine tests skipped")
		return
	end
	local home = character:GetPivot()
	CarryService.Clear(player)

	local badOk, badErr = MachineService.TryInsert(player, "Main", "not-a-uid")
	check("insert with a malformed uid is rejected", not badOk and badErr == errors.InvalidArguments, tostring(badErr))
	local unknownOk, unknownErr = MachineService.TryInsert(player, "NoSuchMachine", JunkService.NewUid())
	check("insert into an unknown machine is rejected", not unknownOk and unknownErr == errors.UnknownMachine, tostring(unknownErr))

	character:PivotTo(anchor.CFrame * CFrame.new(0, 0, -10))
	local strangerOk, strangerErr = MachineService.TryInsert(player, "Main", JunkService.NewUid())
	check("inserting junk the player does not carry is rejected", not strangerOk and strangerErr == errors.NotCarried, tostring(strangerErr))

	local uid = JunkService.NewUid()
	CarryService.AddJunk(player, "rusty_can", uid)
	character:PivotTo(anchor.CFrame * CFrame.new(0, 0, -120))
	local farOk, farErr = MachineService.TryInsert(player, "Main", uid)
	check("inserting from far away is rejected", not farOk and farErr == errors.TooFar, tostring(farErr))
	check("a rejected insert keeps the junk carried", CarryService.HasUid(player, uid))

	character:PivotTo(anchor.CFrame * CFrame.new(0, 0, -10))
	local itemsBefore = InventoryService.GetAllItems(player) or {}
	local ok, err = MachineService.TryInsert(player, "Main", uid)
	check("a valid insert is accepted", ok, tostring(err))
	check("the inserted junk is consumed", not CarryService.HasUid(player, uid))
	check("the machine is AcceptingItem with the player as owner",
		model:GetAttribute("State") == "AcceptingItem" and model:GetAttribute("OwnerUserId") == player.UserId)
	check("the reward is not revealed while processing", model:GetAttribute("RewardItemId") == "")

	local againOk, againErr = MachineService.TryInsert(player, "Main", uid)
	check("inserting the same junk again is rejected", not againOk and againErr == errors.Busy, tostring(againErr))
	local otherUid = JunkService.NewUid()
	CarryService.AddJunk(player, "old_boot", otherUid)
	local busyOk, busyErr = MachineService.TryInsert(player, "Main", otherUid)
	check("a second insert while busy is rejected", not busyOk and busyErr == errors.Busy, tostring(busyErr))
	check("junk rejected as busy stays carried", CarryService.HasUid(player, otherUid))
	local claimOk, claimErr = MachineService.TryClaim(player, "Main")
	check("claiming while processing is rejected", not claimOk and claimErr == errors.NothingToClaim, tostring(claimErr))

	task.wait(MachineConfig.InsertDuration + 0.2)
	check("the machine moves on to Processing", model:GetAttribute("State") == "Processing")
	task.wait(MachineConfig.ProcessDuration)
	check("the machine reaches RewardReady", model:GetAttribute("State") == "RewardReady")

	local rewardId = model:GetAttribute("RewardItemId")
	local rewardRarity = model:GetAttribute("RewardRarity")
	local definition = if type(rewardId) == "string" then ItemConfig.Get(rewardId) else nil
	check("the revealed reward is a real item of the revealed rarity",
		definition ~= nil and definition.Rarity == rewardRarity, `{tostring(rewardId)} / {tostring(rewardRarity)}`)
	check("the reward is marked delivered", model:GetAttribute("RewardDelivered") == true)

	local itemsAfter = InventoryService.GetAllItems(player) or {}
	local newUids: { string } = {}
	for itemUid, record in itemsAfter do
		if itemsBefore[itemUid] == nil then
			table.insert(newUids, itemUid)
			check("the new inventory item is the revealed reward", record.id == rewardId, record.id)
		end
	end
	check("exactly one reward item was added to the inventory", #newUids == 1, tostring(#newUids))
	local lateClaim = MachineService.TryClaim(player, "Main")
	check("a delivered reward cannot be claimed again", not lateClaim)

	task.wait(MachineConfig.RevealDuration + 0.3)
	check("the machine returns to Idle", model:GetAttribute("State") == "Idle")
	check("still exactly one reward item after the cycle", #newUids == 1 and InventoryService.HasItem(player, newUids[1]))

	-- Clean up: tests must not leave items behind.
	for _, itemUid in newUids do
		InventoryService.RemoveItem(player, itemUid)
	end
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
	runJunkConfigTests()
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
