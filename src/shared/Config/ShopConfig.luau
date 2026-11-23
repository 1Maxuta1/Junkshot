--!strict
--[[
	ShopConfig: what the Scrap Dealer sells (ShopService validates and delivers).

	Entry fields
	  Id             stable key (sent by the client; never rename a shipped one)
	  Category       one of Categories (UI tab section)
	  ItemId         the item delivered (into the hands, or base storage when hands are full)
	  Price          explicit price; when nil: ItemValue.SellPrice(ItemId) x BuyMultiplier,
	                 rounded up to 5 (always far above what the item sells for: no arbitrage)
	  RequiredLevel  player level needed (Config/Progression), default 1

	Player upgrades are shown in the dealer's UPGRADES tab (Config/PlayerUpgrades); machine
	upgrades stay in the machine. To add a shop item: add one line below.
]]

export type Entry = {
	Id: string,
	Category: string,
	ItemId: string,
	Price: number?,
	RequiredLevel: number?,
}

local ShopConfig = {
	BuyMultiplier = 4,
	Categories = { "Materials", "Parts", "Utility" },
	Entries = {
		{ Id = "metal_sheet", Category = "Materials", ItemId = "metal_sheet" },
		{ Id = "bolt_pack", Category = "Materials", ItemId = "bolt_pack" },
		{ Id = "pipe_segment", Category = "Materials", ItemId = "pipe_segment" },
		{ Id = "bike_wheel", Category = "Materials", ItemId = "bike_wheel" },
		{ Id = "copper_wire", Category = "Parts", ItemId = "copper_wire", RequiredLevel = 2 },
		{ Id = "car_battery", Category = "Parts", ItemId = "car_battery", RequiredLevel = 2 },
		{ Id = "gear_wheel", Category = "Parts", ItemId = "gear_wheel", RequiredLevel = 3 },
		{ Id = "engine_part", Category = "Parts", ItemId = "engine_part", RequiredLevel = 3 },
		{ Id = "circuit_board", Category = "Parts", ItemId = "circuit_board", RequiredLevel = 5 },
		{ Id = "bicycle", Category = "Utility", ItemId = "bicycle", Price = 1200, RequiredLevel = 3 },
		{ Id = "metal_detector", Category = "Utility", ItemId = "metal_detector", Price = 2500, RequiredLevel = 4 },
		{ Id = "boombox_radio", Category = "Utility", ItemId = "boombox_radio", Price = 1800, RequiredLevel = 4 },
	} :: { Entry },
}

local function deepFreeze(value: any)
	if type(value) == "table" and not table.isfrozen(value) then
		for _, child in value do
			deepFreeze(child)
		end
		table.freeze(value)
	end
end
deepFreeze(ShopConfig)

return ShopConfig
