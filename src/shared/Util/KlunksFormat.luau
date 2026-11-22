--!strict
--[[
	KlunksFormat: the one place that knows how Klunks are displayed.
	KlunksFormat.Format(250)     --> "250 K"
	KlunksFormat.Format(1250000) --> "1,250,000 K"
]]

local GameConfig = require(script.Parent.Parent.Config.GameConfig)

local KlunksFormat = {}

function KlunksFormat.Format(amount: number): string
	local sign = if amount < 0 then "-" else ""
	-- "%.0f" avoids scientific notation that tostring() would produce for large numbers.
	local digits = string.format("%.0f", math.floor(math.abs(amount)))
	local grouped = digits:reverse():gsub("(%d%d%d)", "%1,"):reverse()
	if grouped:sub(1, 1) == "," then
		grouped = grouped:sub(2)
	end
	return `{sign}{grouped} {GameConfig.Klunks.Symbol}`
end

return KlunksFormat
