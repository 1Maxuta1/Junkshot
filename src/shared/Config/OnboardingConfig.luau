--!strict
--[[
	OnboardingConfig: the first five minutes (server OnboardingService decides, client
	OnboardingController shows). Steps are done in this order.

	Step fields
	  Id, Title, Hint   shown in the objective card
	  Goal              how many times (default 1)
	  Reward            Klunks, paid once per player through EconomyService
	  Target            what the arrow points to: Junk | Machine | Dealer | Base | Raceway
	The rewards together are 150: enough for the first Warm Lantern (100), no more.
]]

export type Step = { Id: string, Title: string, Hint: string, Goal: number, Reward: number, Target: string }

local OnboardingConfig = {
	Steps = {
		{ Id = "Collect", Title = "Pick up 3 pieces of junk", Hint = "Follow the arrow and press the pickup button", Goal = 3, Reward = 15, Target = "Junk" },
		{ Id = "Recycle", Title = "Recycle one item", Hint = "Open your own machine, choose RECYCLE", Goal = 1, Reward = 15, Target = "Machine" },
		{ Id = "Take", Title = "Take your reward", Hint = "Tap SPEED UP, then take it from the tray", Goal = 1, Reward = 20, Target = "Machine" },
		{ Id = "Sell", Title = "Sell something", Hint = "The Scrap Dealer pays Klunks for items in your hands", Goal = 1, Reward = 25, Target = "Dealer" },
		{ Id = "Upgrade", Title = "Make your base better", Hint = "Build a Warm Lantern on your base or buy any upgrade", Goal = 1, Reward = 25, Target = "Base" },
		{ Id = "Explore", Title = "Visit the Raceway", Hint = "Craft a vehicle and race other players every hour", Goal = 1, Reward = 50, Target = "Raceway" },
	} :: { Step },
	RacewaySpot = Vector3.new(73, 4, -264),
	RacewayDistance = 45,
}

for _, step in OnboardingConfig.Steps do
	assert(step.Goal >= 1 and step.Reward >= 0, `[OnboardingConfig] bad step {step.Id}`)
	table.freeze(step)
end
table.freeze(OnboardingConfig.Steps)
return table.freeze(OnboardingConfig)
