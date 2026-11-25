--!strict
--[[
	RaceConfig: the JUNKSHOT RACEWAY race every 30 minutes (server/Services/RaceService).

	Everybody races in their OWN placed vehicle. To keep it fair every vehicle's top speed is
	pulled towards BaseSpeed during the race (SpeedShare = how much of the difference stays), so
	a better vehicle helps a little but a bicycle can still win by driving well.

	Prizes are real but not game breaking (a chest upgrade costs 450 - 9000). The full prizes need
	MinForPrizes racers at the start, so nobody farms an empty server alone.
]]

local RaceConfig = {
	Interval = 1800, -- seconds; races start at :00 and :30 on every server
	OpenBefore = 180, -- seconds before the start when joining opens
	MaxRacers = 8, -- grid slots on the map
	Laps = 3,
	Countdown = 5,
	TimeLimit = 300, -- seconds after GO
	AfterFirst = 60, -- seconds the others get after the winner finished
	ExitGrace = 8, -- seconds out of the vehicle before a racer is out
	ResultSeconds = 8,

	BaseSpeed = 42,
	SpeedShare = 0.35,

	MinForPrizes = 2,
	Prizes = { 1500, 700, 350 },
	FinisherReward = 100, -- everyone else who finishes
	SoloReward = 150, -- finishing with fewer than MinForPrizes racers
	RecordBonus = 100, -- beating your own best time

	CheckpointMargin = 3, -- extra studs left / right of a checkpoint
	CheckpointDepth = 7, -- studs before / after its line
	Step = 0.1, -- seconds between two progress checks
	JoinDistance = 18, -- studs from the join pad
	ExitSpot = Vector3.new(73, 4, -264), -- racers stand here afterwards
	BoardSize = 5,
}

for _, child in RaceConfig :: any do
	if type(child) == "table" then
		table.freeze(child)
	end
end
return table.freeze(RaceConfig)
