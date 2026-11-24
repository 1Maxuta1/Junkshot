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
		-- Machine time by the hour: 10 Robux each started hour (Roblox prices are fixed per product).
		Skip1h = {
			Key = "Skip1h",
			ProductId = 0,
			DisplayName = "Finish Now (up to 1 h)",
			Description = "Removes up to 1 h from the running job.",
			Icon = "",
			PriceRobux = 10,
			Category = "Skip",
			Repeatable = true,
			ShowInMachine = false,
			Handler = "SkipTime",
			Hours = 1,
		},
		Skip2h = {
			Key = "Skip2h",
			ProductId = 0,
			DisplayName = "Finish Now (up to 2 h)",
			Description = "Removes up to 2 h from the running job.",
			Icon = "",
			PriceRobux = 20,
			Category = "Skip",
			Repeatable = true,
			ShowInMachine = false,
			Handler = "SkipTime",
			Hours = 2,
		},
		Skip3h = {
			Key = "Skip3h",
			ProductId = 0,
			DisplayName = "Finish Now (up to 3 h)",
			Description = "Removes up to 3 h from the running job.",
			Icon = "",
			PriceRobux = 30,
			Category = "Skip",
			Repeatable = true,
			ShowInMachine = false,
			Handler = "SkipTime",
			Hours = 3,
		},
		Skip4h = {
			Key = "Skip4h",
			ProductId = 0,
			DisplayName = "Finish Now (up to 4 h)",
			Description = "Removes up to 4 h from the running job.",
			Icon = "",
			PriceRobux = 40,
			Category = "Skip",
			Repeatable = true,
			ShowInMachine = false,
			Handler = "SkipTime",
			Hours = 4,
		},
		Skip5h = {
			Key = "Skip5h",
			ProductId = 0,
			DisplayName = "Finish Now (up to 5 h)",
			Description = "Removes up to 5 h from the running job.",
			Icon = "",
			PriceRobux = 50,
			Category = "Skip",
			Repeatable = true,
			ShowInMachine = false,
			Handler = "SkipTime",
			Hours = 5,
		},
		Skip6h = {
			Key = "Skip6h",
			ProductId = 0,
			DisplayName = "Finish Now (up to 6 h)",
			Description = "Removes up to 6 h from the running job.",
			Icon = "",
			PriceRobux = 60,
			Category = "Skip",
			Repeatable = true,
			ShowInMachine = false,
			Handler = "SkipTime",
			Hours = 6,
		},
		-- Currency packs.
		Klunks5k = {
			Key = "Klunks5k",
			ProductId = 0,
			DisplayName = "Handful of Klunks",
			Description = "5000 Klunks right away.",
			Icon = "",
			PriceRobux = 99,
			Category = "Currency",
			Repeatable = true,
			ShowInMachine = false,
			Handler = "Klunks",
			Amount = 5000,
		},
		Klunks25k = {
			Key = "Klunks25k",
			ProductId = 0,
			DisplayName = "Crate of Klunks",
			Description = "25000 Klunks right away.",
			Icon = "",
			PriceRobux = 299,
			Category = "Currency",
			Repeatable = true,
			ShowInMachine = false,
			Handler = "Klunks",
			Amount = 25000,
		},
		Klunks100k = {
			Key = "Klunks100k",
			ProductId = 0,
			DisplayName = "Vault of Klunks",
			Description = "100000 Klunks right away.",
			Icon = "",
			PriceRobux = 799,
			Category = "Currency",
			Repeatable = true,
			ShowInMachine = false,
			Handler = "Klunks",
			Amount = 100000,
		},
		InstantFinish = {
			Key = "InstantFinish",
			ProductId = 0,
			DisplayName = "Instant Finish",
			Description = "Finish the current process now.",
			Icon = "",
			Category = "Legacy", -- replaced by the hourly Skip products; not sold
			Repeatable = true,
			ShowInMachine = false,
			Handler = nil,
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
	ShopSections = { "Featured", "StarterPacks", "GamePasses", "Cosmetics", "Currency", "Boosts" },
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
