--!strict
--[[
	MonetizationConfig: the registry of every Robux product. EVERY ID IS 0 = NOT CONFIGURED:
	an unconfigured product shows "Coming soon" and can never be bought or granted. Nothing here
	creates or activates anything on Roblox; real ids are added by hand after review.

	To enable a product:
	  1. Create it in Creator Hub (Game Pass or Developer Product), set its price there.
	  2. Paste its numeric id into GamePassId / ProductId below.
	  3. Publish. (Game Passes: do NOT enable a free trial for the Starter Pack.)

	Game Pass fields
	  Key, GamePassId, DisplayName, Description, Icon (image id or ""), PriceRobux (shown only
	  until Roblox returns the real price), Category (shop section), Featured, ShowInMachine,
	  Grant = what owning it gives (MonetizationService applies it, idempotently, every time
	  ownership is confirmed by MarketplaceService):
	    ChestLevel   minimum chest level (never lowers a higher one)
	    Cosmetics    cosmetic ids unlocked (Config/CosmeticsConfig), stored as unlocks
	    MachineSpeed permanent machine duration multiplier (FastMachine)
	Developer Product fields
	  Key, ProductId, DisplayName, Description, Icon, Category, Repeatable, ShowInMachine,
	  Handler = name of the grant handler in MonetizationService (nil = not implemented yet:
	  such a product stays disabled even with an id).
	Shop sections: Featured, StarterPacks, GamePasses, Cosmetics, Boosts.
]]

local MonetizationConfig = {
	GamePasses = {
		StarterPack = {
			Key = "StarterPack",
			GamePassId = 0, -- placeholder: paste the real Game Pass id here
			DisplayName = "JUNKSHOT Starter Pack",
			Description = "A head start and a set of exclusive looks.",
			Icon = "",
			PriceRobux = 149,
			Category = "StarterPacks",
			Featured = true,
			ShowInMachine = false,
			Grant = {
				ChestLevel = 3,
				Cosmetics = { "backpack_frosty", "companion_snowbot", "toolskin_frostbite", "title_early_scrapper" },
			},
			-- Shown on the shop card; Permanent = gameplay convenience, Cosmetic = looks only.
			Rewards = {
				{ Text = "Chest Level 3 (35 slots)", Kind = "Permanent" },
				{ Text = "Frosty Scrapper Backpack", Kind = "Cosmetic" },
				{ Text = "Snowbot robot companion", Kind = "Cosmetic" },
				{ Text = "Frostbite Shovel skin", Kind = "Cosmetic" },
				{ Text = "\"Early Scrapper\" title", Kind = "Cosmetic" },
			},
		},
		FastMachine = {
			Key = "FastMachine",
			GamePassId = 0,
			DisplayName = "Fast Machine",
			Description = "Every job is 20% faster, forever.",
			Icon = "",
			PriceRobux = 0,
			Category = "GamePasses",
			Featured = false,
			ShowInMachine = true,
			Grant = { MachineSpeed = true },
			Multiplier = 0.8,
		},
	},
	Products = {
		InstantFinish = {
			Key = "InstantFinish",
			ProductId = 0,
			DisplayName = "Instant Finish",
			Description = "Finish the current process now.",
			Icon = "",
			Category = "Boosts",
			Repeatable = true,
			ShowInMachine = true,
			Handler = "InstantFinish",
		},
		SpeedBoost = {
			Key = "SpeedBoost",
			ProductId = 0,
			DisplayName = "Speed Boost (30 min)",
			Description = "Jobs started in the next 30 minutes run twice as fast.",
			Icon = "",
			Category = "Boosts",
			Repeatable = true,
			ShowInMachine = true,
			Handler = "SpeedBoost",
			Minutes = 30,
			Multiplier = 0.5,
		},
		CoinBoost = {
			Key = "CoinBoost",
			ProductId = 0,
			DisplayName = "2x Scrap Coins (30 min)",
			Description = "Coming later: double coins from selling for 30 minutes.",
			Icon = "",
			Category = "Boosts",
			Repeatable = true,
			ShowInMachine = false,
			Handler = nil, -- future: not implemented, stays disabled
			Minutes = 30,
		},
	},
	ShopSections = { "Featured", "StarterPacks", "GamePasses", "Cosmetics", "Boosts" },
	MaxStoredReceipts = 50, -- processed receipt ids kept per player (idempotency window)
	OwnershipRetries = { 2, 5, 15 }, -- seconds between UserOwnsGamePassAsync retries on API errors
	OwnershipRecheck = 120, -- seconds: keep retrying in the background after an API failure
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
