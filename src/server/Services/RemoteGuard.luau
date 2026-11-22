--!strict
--[[
	RemoteGuard: every client -> server remote goes through here.

	Per request it enforces, in this order:
	  1. rate limit (fixed window, per player, per remote)
	  2. argument count (MaxArgs, required so each remote states its own contract)
	  3. optional Validate(...) callback for argument types/ranges
	Only then does the handler run, inside xpcall so one bad request can never break the
	connection. Failures are logged with warn(); nothing is swallowed silently.

	Rules for handlers (enforced by review, not by code):
	  - The player argument is the only identity you can trust.
	  - Never accept prices, rewards, balances or ownership claims from the client.
	  - Return only data the player may see.

	Example:
	  RemoteGuard.ConnectEvent(remote, {
	      Name = "ThrowRequest",
	      MaxArgs = 2,
	      Validate = function(direction, power) return typeof(direction) == "Vector3" end,
	  }, function(player, direction, power) ... end)
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local GameConfig = require(ReplicatedStorage.Shared.Config.GameConfig)
local Types = require(ReplicatedStorage.Shared.Types)

export type GuardOptions = {
	Name: string,
	MaxArgs: number,
	RateLimit: Types.RateLimitConfig?, -- defaults to GameConfig.RateLimits.Default
	Validate: ((...any) -> boolean)?, -- receives the client arguments only (no player)
}

type Counter = {
	WindowStart: number,
	Count: number,
	Warned: boolean,
}

local RemoteGuard = {}

-- Builds the per-remote gate: returns true when the request may proceed.
local function createGate(options: GuardOptions): (Player, ...any) -> boolean
	local limit = options.RateLimit or GameConfig.RateLimits.Default
	local counters: { [Player]: Counter } = {}

	Players.PlayerRemoving:Connect(function(player: Player)
		counters[player] = nil
	end)

	return function(player: Player, ...: any): boolean
		-- Rate limit first: cheapest check, and it bounds the cost of everything after it.
		local now = os.clock()
		local counter: Counter
		local existing = counters[player]
		if existing == nil or now - existing.WindowStart >= limit.Window then
			counter = { WindowStart = now, Count = 0, Warned = false }
			counters[player] = counter
		else
			counter = existing
		end

		counter.Count += 1
		if counter.Count > limit.MaxRequests then
			if not counter.Warned then
				counter.Warned = true
				warn(`[RemoteGuard] {options.Name}: {player.Name} exceeded {limit.MaxRequests} requests / {limit.Window}s`)
			end
			return false
		end

		if select("#", ...) > options.MaxArgs then
			warn(`[RemoteGuard] {options.Name}: {player.Name} sent {select("#", ...)} args, max is {options.MaxArgs}`)
			return false
		end

		if options.Validate ~= nil then
			local ok, valid = pcall(options.Validate, ...)
			if not ok then
				warn(`[RemoteGuard] {options.Name}: validator errored: {tostring(valid)}`)
				return false
			end
			if valid ~= true then
				warn(`[RemoteGuard] {options.Name}: {player.Name} sent invalid arguments`)
				return false
			end
		end

		return true
	end
end

function RemoteGuard.ConnectEvent(
	remote: RemoteEvent,
	options: GuardOptions,
	handler: (player: Player, ...any) -> ()
): RBXScriptConnection
	local gate = createGate(options)
	return remote.OnServerEvent:Connect(function(player: Player, ...: any)
		if not gate(player, ...) then
			return
		end
		local ok, err = xpcall(handler, debug.traceback, player, ...)
		if not ok then
			warn(`[RemoteGuard] {options.Name} handler error: {tostring(err)}`)
		end
	end)
end

-- RemoteFunction handlers return a single value (nil when the request is rejected).
function RemoteGuard.BindFunction(
	remote: RemoteFunction,
	options: GuardOptions,
	handler: (player: Player, ...any) -> any
)
	local gate = createGate(options)
	remote.OnServerInvoke = function(player: Player, ...: any): any
		if not gate(player, ...) then
			return nil
		end
		local ok, result = xpcall(handler, debug.traceback, player, ...)
		if not ok then
			warn(`[RemoteGuard] {options.Name} handler error: {tostring(result)}`)
			return nil
		end
		return result
	end
end

return RemoteGuard
