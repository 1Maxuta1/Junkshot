--!strict
--[[
	PlotService: gives every player one of the map's base plots (Models tagged "BasePlot",
	attribute PlotId) while they are in the server. Minimal on purpose: the full base system is
	a later stage. Today a plot holds the player's personal machine.

	  - A plot is assigned when the player's data has loaded (DataService.PlayerLoaded) and
	    released when they leave. Lowest free PlotId first.
	  - The plot's attributes Owner (UserId, 0 = free) and OwnerName are set, and its sign shows
	    the owner's name.
	  - With more players than plots, the extra players simply get no plot (warned).

	Public API (server only)
	  GetPlot(player) -> Model?
	  GetPlotCFrame(plot) -> CFrame   center of the pad's top surface, -Z facing the plaza
	  PlotAssigned  Signal (player, plot)
	  PlotReleased  Signal (player, plot)   fired BEFORE the plot is cleared
]]

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Signal = require(ReplicatedStorage.Shared.Util.Signal)
local DataService = require(script.Parent.DataService)

local PLOT_TAG = "BasePlot"

local PlotService = {}

PlotService.PlotAssigned = Signal.new() -- (player: Player, plot: Model)
PlotService.PlotReleased = Signal.new() -- (player: Player, plot: Model)

local started = false
local plotOf: { [Player]: Model } = {}
local ownerOf: { [Model]: Player } = {}

local function getPlots(): { Model }
	local plots: { Model } = {}
	for _, instance in CollectionService:GetTagged(PLOT_TAG) do
		if instance:IsA("Model") and type(instance:GetAttribute("PlotId")) == "number" then
			table.insert(plots, instance)
		end
	end
	table.sort(plots, function(a, b)
		return (a:GetAttribute("PlotId") :: number) < (b:GetAttribute("PlotId") :: number)
	end)
	return plots
end

local function signLabel(plot: Model): TextLabel?
	local sign = plot:FindFirstChild("Sign")
	local label = if sign ~= nil then sign:FindFirstChildWhichIsA("TextLabel", true) else nil
	return label
end

local function setSign(plot: Model, text: string)
	local label = signLabel(plot)
	if label ~= nil then
		label.Text = text
	end
end

function PlotService.GetPlot(player: Player): Model?
	return plotOf[player]
end

function PlotService.GetPlotCFrame(plot: Model): CFrame
	local pad = plot:FindFirstChild("Pad")
	if pad ~= nil and pad:IsA("BasePart") then
		return pad.CFrame * CFrame.new(0, pad.Size.Y / 2, 0)
	end
	return plot:GetPivot()
end

local function assign(player: Player)
	if plotOf[player] ~= nil or player.Parent ~= Players then
		return
	end
	for _, plot in getPlots() do
		if ownerOf[plot] == nil then
			ownerOf[plot] = player
			plotOf[player] = plot
			plot:SetAttribute("Owner", player.UserId)
			plot:SetAttribute("OwnerName", player.DisplayName)
			setSign(plot, `{string.upper(player.DisplayName)}'S BASE`)
			PlotService.PlotAssigned:Fire(player, plot)
			return
		end
	end
	warn(`[PlotService] no free plot for {player.Name}`)
end

local function release(player: Player)
	local plot = plotOf[player]
	if plot == nil then
		return
	end
	PlotService.PlotReleased:Fire(player, plot)
	plotOf[player] = nil
	ownerOf[plot] = nil
	plot:SetAttribute("Owner", 0)
	plot:SetAttribute("OwnerName", "")
	setSign(plot, `BASE {plot:GetAttribute("PlotId")}`)
end

function PlotService.Start()
	assert(not started, "[PlotService] Start() called twice")
	started = true

	if #getPlots() == 0 then
		warn(`[PlotService] no plots found (Models tagged "{PLOT_TAG}")`)
	end
	DataService.PlayerLoaded:Connect(assign)
	Players.PlayerRemoving:Connect(release)
	for _, player in Players:GetPlayers() do
		if DataService.IsLoaded(player) then
			assign(player)
		end
	end
end

return PlotService
