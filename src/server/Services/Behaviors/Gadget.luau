--!strict
--[[
	Gadget behavior: placed objects that DO something when you press E (Config/Behaviors, Kind
	"Gadget"). The server only decides the state; every client draws it (client/GadgetController).

	Gadget.Action
	  "Cycle"     E = next entry of Modes; anyone may press (attribute GadgetMode, saved as Record.Mode)
	  "Fire"      E = one burst for everyone (attribute GadgetFire counts up), Cooldown seconds apart
	  "Arcade"    reaction game: press, wait for GO!, press again (attribute ScreenText; Record.Best)
	  "Robot"     E = it points to the nearest Rare+ item lying in the yard (attribute Speech)
	  "Hologram"  owner: E = copy the look of the item in the hand (attribute HoloId, Record.Holo).
	              Only a picture; the item stays in the hand
	  "Sit"       E = sit down (the model needs a "ThroneSeat")
	  "Teleport"  owner: E = travel to their next teleport pad. Not while seated, trading or racing
	  "None"      no prompt (the spring launcher works by stepping on it)
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local ItemConfig = require(ReplicatedStorage.Shared.Config.ItemConfig)
local Rarities = require(ReplicatedStorage.Shared.Config.Rarities)

local CarryService = require(script.Parent.Parent.CarryService)
local JunkService = require(script.Parent.Parent.JunkService)
local TradeService = require(script.Parent.Parent.TradeService)

local Gadget = {}

local api: any = nil
local PRESS_COOLDOWN = 0.4
local ROBOT_RANGE = 120
local SPEECH_SECONDS = 6
local ARCADE_MAX = 5 -- seconds after GO! until the round is over

local function pressed(entry: any): boolean
	local now = os.clock()
	if now - (entry.State.LastPress or -math.huge) < (entry.Behavior.Gadget.Cooldown or PRESS_COOLDOWN) then
		return false
	end
	entry.State.LastPress = now
	return true
end

---------------------------------------------------------------------------------------------
-- Actions (also called by DevTests)
---------------------------------------------------------------------------------------------

function Gadget.SetMode(entry: any, mode: number)
	local modes = entry.Behavior.Gadget.Modes
	entry.State.Mode = mode
	entry.Record.Mode = mode
	entry.Model:SetAttribute("GadgetMode", mode)
	local prompt = entry.State.Prompt
	if prompt ~= nil then
		prompt.ActionText = modes[mode % #modes + 1]
	end
end

function Gadget.Cycle(entry: any)
	Gadget.SetMode(entry, entry.State.Mode % #entry.Behavior.Gadget.Modes + 1)
end

function Gadget.Fire(entry: any)
	entry.Model:SetAttribute("GadgetFire", (entry.Model:GetAttribute("GadgetFire") or 0) + 1)
end

local function screen(entry: any, text: string)
	entry.Model:SetAttribute("ScreenText", text)
end

local function bestText(entry: any): string
	local best = entry.Record.Best
	return if type(best) == "number" then `BEST {best} ms` else "PRESS START"
end

-- Reaction game. One player at a time; the round ends by itself.
function Gadget.Arcade(entry: any, player: Player)
	local state = entry.State
	local round = state.Round
	local now = os.clock()
	if round == nil then
		local mine = { Player = player, GoAt = now + 1.5 + math.random() * 2.5 }
		state.Round = mine
		screen(entry, "WAIT...")
		task.delay(mine.GoAt - now, function()
			if state.Round == mine then
				screen(entry, "GO!")
			end
		end)
		task.delay(mine.GoAt - now + ARCADE_MAX, function()
			if state.Round == mine then
				state.Round = nil
				screen(entry, "TOO SLOW!")
			end
		end)
		return
	end
	if round.Player ~= player then
		return
	end
	state.Round = nil
	if now < round.GoAt then
		screen(entry, "TOO EARLY!")
		return
	end
	local ms = math.floor((now - round.GoAt) * 1000 + 0.5)
	local best = entry.Record.Best
	if type(best) ~= "number" or ms < best then
		entry.Record.Best = ms
		screen(entry, `{ms} ms\nNEW BEST!\n{player.DisplayName}`)
	else
		screen(entry, `{ms} ms\n{bestText(entry)}`)
	end
end

local COMPASS = { "north", "north-east", "east", "south-east", "south", "south-west", "west", "north-west" }

local function direction(from: Vector3, to: Vector3): string
	local angle = math.atan2(to.X - from.X, -(to.Z - from.Z))
	return COMPASS[math.floor(angle / (math.pi / 4) + 0.5) % 8 + 1]
end

local function rankOf(rarity: string): number
	return table.find(Rarities.Order, rarity) or 0
end

function Gadget.Robot(entry: any, player: Player)
	local position = entry.Model:GetPivot().Position
	local minimum = rankOf("Rare")
	local model, _, id, distance = JunkService.FindNearest(position, ROBOT_RANGE, function(itemId: string): boolean
		return rankOf(ItemConfig.GetRarity(itemId) or "") >= minimum
	end, player.UserId)
	local target = if model ~= nil then JunkService.GetPosition(model) else nil
	local text = "Beep. Nothing shiny around."
	if target ~= nil and id ~= nil and distance ~= nil then
		text = `Beep! {ItemConfig.GetRarity(id)} scrap {math.floor(distance)} studs {direction(position, target)}!`
	end
	entry.State.SpeechToken = (entry.State.SpeechToken or 0) + 1
	local token = entry.State.SpeechToken
	entry.Model:SetAttribute("Speech", text)
	task.delay(SPEECH_SECONDS, function()
		if entry.State.SpeechToken == token then
			entry.Model:SetAttribute("Speech", nil)
		end
	end)
end

function Gadget.SetHologram(entry: any, player: Player): boolean
	local held = player:GetAttribute("HeldUid")
	for _, item in CarryService.GetCarried(player) do
		if item.Uid == held then
			entry.Record.Holo = item.Id
			entry.Model:SetAttribute("HoloId", item.Id)
			return true
		end
	end
	api.Notify(player, "Hold an item to show its hologram")
	return false
end

local lastTeleport: { [Player]: number } = setmetatable({}, { __mode = "k" }) :: any

-- Returns true when the player was moved.
function Gadget.Teleport(entry: any, player: Player): (boolean, string?)
	if player ~= entry.Owner then
		return false, "Only its owner can use this teleport"
	end
	local character = player.Character
	local humanoid = if character ~= nil then character:FindFirstChildOfClass("Humanoid") else nil
	if character == nil or humanoid == nil or CarryService.GetLiveRoot(player) == nil then
		return false, nil
	end
	if humanoid.Sit then
		return false, "Get out of the vehicle first"
	end
	if player:GetAttribute("RaceLap") ~= nil or player:GetAttribute("RaceJoined") == true then
		return false, "Not during a race"
	end
	if TradeService.GetSession(player) ~= nil then
		return false, "Not while trading"
	end
	local pads: { any } = {}
	for _, other in api.GetEntries(player) do
		if other.Behavior.Gadget ~= nil and other.Behavior.Gadget.Effect == "Teleporter" then
			table.insert(pads, other)
		end
	end
	if #pads < 2 then
		return false, "Place a second Teleport Pad to travel between them"
	end
	local now = os.clock()
	local left = (lastTeleport[player] or -math.huge) + entry.Behavior.Gadget.TravelCooldown - now
	if left > 0 then
		return false, `The teleport recharges: {math.ceil(left)} s`
	end
	table.sort(pads, function(a, b)
		return a.Uid < b.Uid
	end)
	local index = table.find(pads, entry) :: number
	local target = pads[index % #pads + 1]
	lastTeleport[player] = now
	local pivot = target.Model:GetPivot()
	character:PivotTo(pivot * CFrame.new(0, 4.5, 0))
	Gadget.Fire(entry)
	Gadget.Fire(target)
	return true, nil
end

local function seatOf(entry: any): Seat?
	local seat = entry.Model:FindFirstChild("ThroneSeat")
	return if seat ~= nil and seat:IsA("Seat") then seat else nil
end

local function sit(entry: any, player: Player)
	local seat = seatOf(entry)
	local character = player.Character
	local humanoid = if character ~= nil then character:FindFirstChildOfClass("Humanoid") else nil
	if seat == nil or humanoid == nil or humanoid.Health <= 0 or humanoid.Sit then
		return
	end
	if seat.Occupant ~= nil then
		api.Notify(player, "Someone is sitting in it")
		return
	end
	seat:Sit(humanoid)
end

---------------------------------------------------------------------------------------------
-- Behavior contract
---------------------------------------------------------------------------------------------

function Gadget.Init(placement: any)
	api = placement
end

function Gadget.Attach(entry: any)
	local config = entry.Behavior.Gadget
	local record = entry.Record
	local model: Model = entry.Model
	model:SetAttribute("PartCount", #model:GetChildren()) -- clients wait for all of them (streaming)
	model:SetAttribute("Gadget", config.Effect)
	if config.Action ~= "None" then
		entry.State.Prompt = api.AddPrompt(entry, model.PrimaryPart, {
			Name = "GadgetPrompt",
			Action = config.Label or "Use",
			Slot = "Primary",
			OwnerOnly = config.Action == "Hologram" or config.Action == "Teleport",
			Row = 1,
		}, function(player: Player)
			if not pressed(entry) then
				return
			end
			if config.Action == "Cycle" then
				Gadget.Cycle(entry)
			elseif config.Action == "Fire" then
				Gadget.Fire(entry)
			elseif config.Action == "Arcade" then
				Gadget.Arcade(entry, player)
			elseif config.Action == "Robot" then
				Gadget.Robot(entry, player)
			elseif config.Action == "Hologram" then
				Gadget.SetHologram(entry, player)
			elseif config.Action == "Teleport" then
				local _, message = Gadget.Teleport(entry, player)
				if message ~= nil then
					api.Notify(player, message)
				end
			elseif config.Action == "Sit" then
				sit(entry, player)
			end
		end)
	end
	if config.Action == "Cycle" then
		local saved = record.Mode
		local valid = type(saved) == "number" and saved % 1 == 0 and saved >= 1 and saved <= #config.Modes
		Gadget.SetMode(entry, if valid then saved else 1)
	elseif config.Action == "Arcade" then
		screen(entry, bestText(entry))
	elseif config.Action == "Hologram" then
		if ItemConfig.Exists(record.Holo) then
			model:SetAttribute("HoloId", record.Holo)
		else
			record.Holo = nil
		end
	end
end

function Gadget.Detach(entry: any)
	entry.State.Round = nil
	local seat = seatOf(entry)
	local occupant = if seat ~= nil then seat.Occupant else nil
	if occupant ~= nil then
		occupant.Sit = false
	end
end

function Gadget.CanStore(entry: any): (boolean, string?)
	local seat = seatOf(entry)
	if seat ~= nil and seat.Occupant ~= nil then
		return false, "Occupied"
	end
	return true, nil
end

return Gadget
