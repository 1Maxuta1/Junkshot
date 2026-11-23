--!strict
--[[
	Radio behavior (Boombox Radio): a placed object everybody nearby can enjoy.

	Prompts
	  E  Play / Stop    anyone
	  Z  Next song      anyone
	  T  Pick up        owner only (shared Store prompt; the music stops)

	The Sound lives in the radio's Base on the server, so every player hears the same song
	(positional, fades out at Radio.MaxDistance). Button presses share a short per-radio
	cooldown so nobody can spam it. Tracks: Config/Behaviors["Deploy.Radio"].Radio.Tracks.
]]

local Radio = {}

local api: any = nil

local PLAYING_COLOR = Color3.fromRGB(90, 230, 120)
local IDLE_COLOR = Color3.fromRGB(255, 210, 60)

local function apply(entry: any)
	local state = entry.State
	local config = entry.Behavior.Radio
	local track = config.Tracks[state.Track]
	local sound: Sound = state.Sound
	if sound.SoundId ~= track.SoundId then
		sound.SoundId = track.SoundId
		sound.TimePosition = 0
	end
	sound.Playing = state.Playing
	entry.Model:SetAttribute("Playing", state.Playing)
	entry.Model:SetAttribute("TrackName", track.Name)
	local light = entry.Model:FindFirstChild("Light")
	if light ~= nil and light:IsA("BasePart") then
		light.Color = if state.Playing then PLAYING_COLOR else IDLE_COLOR
	end
	local toggle: ProximityPrompt? = state.TogglePrompt
	if toggle ~= nil then
		toggle.ActionText = if state.Playing then "Stop" else "Play"
		toggle.ObjectText = if state.Playing then `♪ {track.Name}` else "Boombox Radio"
	end
end

local function pressed(entry: any): boolean
	local now = os.clock()
	if now - (entry.State.LastPress or 0) < entry.Behavior.Radio.Cooldown then
		return false
	end
	entry.State.LastPress = now
	return true
end

-- Also called by DevTests.
function Radio.Toggle(entry: any)
	entry.State.Playing = not entry.State.Playing
	apply(entry)
end

function Radio.Next(entry: any)
	local count = #entry.Behavior.Radio.Tracks
	entry.State.Track = entry.State.Track % count + 1
	entry.State.Playing = true
	apply(entry)
end

function Radio.Init(placement: any)
	api = placement
end

function Radio.Attach(entry: any)
	local config = entry.Behavior.Radio
	local base = entry.Model.PrimaryPart
	local sound = Instance.new("Sound")
	sound.Name = "Music"
	sound.Looped = true
	sound.Volume = config.Volume
	sound.RollOffMode = Enum.RollOffMode.InverseTapered
	sound.RollOffMinDistance = 10
	sound.RollOffMaxDistance = config.MaxDistance
	sound.Parent = base

	local state = entry.State
	state.Sound = sound
	state.Track = 1
	state.Playing = false
	state.TogglePrompt = api.AddPrompt(entry, base, {
		Name = "TogglePrompt",
		Action = "Play",
		Slot = "Primary",
		CardOffset = 2.4,
	}, function(_player: Player)
		if pressed(entry) then
			Radio.Toggle(entry)
		end
	end)
	api.AddPrompt(entry, base, {
		Name = "NextPrompt",
		Action = "Next song",
		Slot = "Secondary",
		CardOffset = 0.6,
	}, function(_player: Player)
		if pressed(entry) then
			Radio.Next(entry)
		end
	end)
	apply(entry)
end

function Radio.Detach(entry: any)
	local sound: Sound? = entry.State.Sound
	if sound ~= nil then
		sound:Stop()
	end
end

return Radio
