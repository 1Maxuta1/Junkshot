--!strict
--[[
	MonetizationConfig: OPTIONAL Robux products for the machine. All ids are 0 = not configured;
	unconfigured products are hidden as "coming soon" and can never be bought.

	To enable one: create the Developer Product / Game Pass on the Creator Dashboard, put its id
	here, and publish. Nothing is created or activated automatically.

	Developer Products (consumable, handled by MonetizationService.ProcessReceipt)
	  InstantFinish   finishes the running process now (or is stored as a credit if idle)
	  SpeedBoost      jobs started during the next Minutes use Multiplier
	Game Passes (permanent)
	  FastMachine     every job uses Multiplier
]]

local MonetizationConfig = {
	Products = {
		InstantFinish = { ProductId = 0, DisplayName = "Instant Finish", Description = "Finish the current process now." },
		SpeedBoost = {
			ProductId = 0,
			DisplayName = "Speed Boost (30 min)",
			Description = "Jobs started in the next 30 minutes run twice as fast.",
			Minutes = 30,
			Multiplier = 0.5,
		},
	},
	GamePasses = {
		FastMachine = { GamePassId = 0, DisplayName = "Fast Machine", Description = "Every job is 20% faster, forever.", Multiplier = 0.8 },
	},
	MaxStoredReceipts = 50, -- processed receipt ids kept per player (idempotency window)
}

local function deepFreeze(value: any)
	if type(value) == "table" and not table.isfrozen(value) then
		for _, child in value do
			deepFreeze(child)
		end
		table.freeze(value)
	end
end

deepFreeze(MonetizationConfig)

return MonetizationConfig
