--!strict
--[[
	CosmeticsConfig: every cosmetic (CosmeticsService). Cosmetics are UNLOCKS saved in
	profile.Data.Cosmetics.Owned[id] = source; they are never items in the inventory and never
	change any gameplay number (carry capacity, speed, luck, money ...).

	Categories (one equipped per category)
	  Backpack    a backpack model on the character's back
	  Companion   a small follower (CompanionService; animated on clients)
	  ToolSkin    the look of the shovel. JUNKSHOT has no shovel TOOL yet, so the skin is shown
	              as a shovel strapped to the back; when a shovel tool arrives it reuses this id.
	  Title       a short title shown above the character's name

	Add a cosmetic: one entry here (+ a model builder in Services/Cosmetics/CosmeticModels for
	Backpack / Companion / ToolSkin). Grant it from a Game Pass (MonetizationConfig.Grant) or
	any other server system with CosmeticsService.Unlock.
]]

export type Cosmetic = {
	Id: string,
	Category: string,
	DisplayName: string,
	Description: string,
	Model: string?, -- builder name in CosmeticModels
	TitleColor: Color3?,
	Exclusive: string?, -- where it comes from (shown in the locker)
}

local list: { Cosmetic } = {
	{
		Id = "backpack_frosty",
		Category = "Backpack",
		DisplayName = "Frosty Scrapper Backpack",
		Description = "A snow-dusted orange backpack. Looks only: carry capacity is unchanged.",
		Model = "FrostyBackpack",
		Exclusive = "Starter Pack",
	},
	{
		Id = "companion_snowbot",
		Category = "Companion",
		DisplayName = "Snowbot",
		Description = "A cheerful little robot with a snow hat that follows you around.",
		Model = "Snowbot",
		Exclusive = "Starter Pack",
	},
	{
		Id = "toolskin_frostbite",
		Category = "ToolSkin",
		DisplayName = "Frostbite Shovel",
		Description = "An icy blue shovel with a frosted blade.",
		Model = "FrostbiteShovel",
		Exclusive = "Starter Pack",
	},
	{
		Id = "title_early_scrapper",
		Category = "Title",
		DisplayName = "Early Scrapper",
		Description = "For the players who were here from the start.",
		TitleColor = Color3.fromRGB(140, 220, 255),
		Exclusive = "Starter Pack",
	},
}

local Categories = { "Backpack", "Companion", "ToolSkin", "Title" }

local byId: { [string]: Cosmetic } = {}
for _, cosmetic in list do
	assert(byId[cosmetic.Id] == nil, `[CosmeticsConfig] duplicate "{cosmetic.Id}"`)
	assert(table.find(Categories, cosmetic.Category), `[CosmeticsConfig] "{cosmetic.Id}" has unknown category`)
	byId[cosmetic.Id] = table.freeze(cosmetic)
end

local CosmeticsConfig = {}

CosmeticsConfig.List = table.freeze(list)
CosmeticsConfig.Categories = table.freeze(Categories)

function CosmeticsConfig.Get(id: string): Cosmetic?
	return byId[id]
end

return table.freeze(CosmeticsConfig)
