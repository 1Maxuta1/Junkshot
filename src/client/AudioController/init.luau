--!strict
--[[
	AudioController: background music, short sound cues and the player's sound settings.

	  Music     AudioConfig.Music.Tracks play one after another (shuffled order, cross-fade),
	            non-positional (SoundService), at AudioConfig.Music.Volume x the player's music
	            setting. Two Sound objects only (the current and the next track).
	  Cues      AudioCue events from the server -> one short local sound (per-cue cooldown).
	  Settings  a small SOUND button opens a panel: music volume, effects volume, mute all.
	            Changes apply at once and are saved on the server (SaveSettings, debounced);
	            on join they come back from the Player attribute "AudioSettings".
]]

local HttpService = game:GetService("HttpService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local SoundService = game:GetService("SoundService")
local TweenService = game:GetService("TweenService")

local AudioConfig = require(ReplicatedStorage.Shared.Config.AudioConfig)
local Remotes = require(ReplicatedStorage.Shared.Remotes)

local Theme = require(script.Parent.UI.Theme)
local Window = require(script.Parent.EconomyController.Window)

local AudioController = {}

local localPlayer = Players.LocalPlayer
local SAVE_DELAY = 1.5

local settings = { Music = AudioConfig.Defaults.Music, Sfx = AudioConfig.Defaults.Sfx, Muted = AudioConfig.Defaults.Muted }
local music: { Sound } = {}
local current = 1
local order: { number } = {}
local orderIndex = 0
local lastCue: { [string]: number } = {}
local cueSounds: { [string]: Sound } = {}
local saveToken = 0
local onSettingsChanged: (() -> ())? = nil

local function musicVolume(): number
	return if settings.Muted then 0 else AudioConfig.Music.Volume * settings.Music
end

local function applyVolumes()
	local sound = music[current]
	if sound ~= nil and sound.IsPlaying then
		sound.Volume = musicVolume()
	end
	if onSettingsChanged ~= nil then
		onSettingsChanged()
	end
end

local function shuffle()
	order = {}
	for index = 1, #AudioConfig.Music.Tracks do
		table.insert(order, index)
	end
	for index = #order, 2, -1 do
		local swap = math.random(index)
		order[index], order[swap] = order[swap], order[index]
	end
	orderIndex = 0
end

local function nextTrack(): number
	orderIndex += 1
	if orderIndex > #order then
		shuffle()
		orderIndex = 1
	end
	return order[orderIndex]
end

-- Starts the next track on the free Sound and fades the old one out.
local function playNext()
	local fade = AudioConfig.Music.CrossFade
	local old = music[current]
	current = if current == 1 then 2 else 1
	local sound = music[current]
	local track = AudioConfig.Music.Tracks[nextTrack()]
	sound.SoundId = track.SoundId
	sound.Volume = 0
	sound.TimePosition = 0
	sound:Play()
	TweenService:Create(sound, TweenInfo.new(fade), { Volume = musicVolume() }):Play()
	if old ~= nil and old.IsPlaying then
		local out = TweenService:Create(old, TweenInfo.new(fade), { Volume = 0 })
		out.Completed:Connect(function()
			if music[current] ~= old then
				old:Stop()
			end
		end)
		out:Play()
	end
end

local function startMusic()
	for index = 1, 2 do
		local sound = Instance.new("Sound")
		sound.Name = `Music{index}`
		sound.Looped = false
		sound.Volume = 0
		sound.Parent = SoundService
		sound.Ended:Connect(function()
			if music[current] == sound then
				playNext()
			end
		end)
		music[index] = sound
	end
	shuffle()
	current = 2 -- so the first playNext uses Sound 1
	playNext()
end

local function playCue(name: string)
	local cue = AudioConfig.Cues[name]
	if cue == nil or settings.Muted or settings.Sfx <= 0 then
		return
	end
	local now = os.clock()
	if now - (lastCue[name] or 0) < AudioConfig.CueCooldown then
		return
	end
	lastCue[name] = now
	local sound = cueSounds[name]
	if sound == nil then
		sound = Instance.new("Sound")
		sound.Name = `Cue{name}`
		sound.SoundId = cue.SoundId
		sound.Parent = SoundService
		cueSounds[name] = sound
	end
	local s = sound :: Sound
	s.Volume = cue.Volume * settings.Sfx
	s.PlaybackSpeed = cue.Pitch
	SoundService:PlayLocalSound(s)
end

-- The player's effects volume (0 when muted). Other controllers scale their sounds with it.
function AudioController.GetSfxVolume(): number
	return if settings.Muted then 0 else settings.Sfx
end

-- Plays a configured sound at a world position (or on an instance), scaled by the effects
-- volume. Returns the Sound (already parented; destroyed when it ends unless `keep`).
function AudioController.PlayAt(spec: any, parent: Instance, looped: boolean?, range: number?): Sound?
	local volume = AudioController.GetSfxVolume()
	if spec == nil or (volume <= 0 and not looped) then
		return nil
	end
	local sound = Instance.new("Sound")
	sound.SoundId = spec.SoundId
	sound.Volume = spec.Volume * volume
	sound.PlaybackSpeed = spec.Pitch or 1
	sound.Looped = looped == true
	sound.RollOffMaxDistance = range or 120
	sound.RollOffMinDistance = 8
	sound.Parent = parent
	sound:Play()
	if not looped then
		sound.Ended:Connect(function()
			sound:Destroy()
		end)
	end
	return sound
end

local function scheduleSave()
	saveToken += 1
	local token = saveToken
	task.delay(SAVE_DELAY, function()
		if token == saveToken then
			Remotes.GetEvent("SaveSettings"):FireServer({ Music = settings.Music, Sfx = settings.Sfx, Muted = settings.Muted })
		end
	end)
end

local function readSaved()
	local raw = localPlayer:GetAttribute("AudioSettings")
	if type(raw) ~= "string" then
		return
	end
	local ok, decoded = pcall(HttpService.JSONDecode, HttpService, raw)
	if ok and type(decoded) == "table" then
		if type(decoded.Music) == "number" then
			settings.Music = math.clamp(decoded.Music, 0, 1)
		end
		if type(decoded.Sfx) == "number" then
			settings.Sfx = math.clamp(decoded.Sfx, 0, 1)
		end
		if type(decoded.Muted) == "boolean" then
			settings.Muted = decoded.Muted
		end
		applyVolumes()
	end
end

local function mountSettings()
	local screenGui = Instance.new("ScreenGui")
	screenGui.Name = "JunkshotAudio"
	screenGui.ResetOnSpawn = false
	screenGui.ScreenInsets = Enum.ScreenInsets.CoreUISafeInsets
	screenGui.DisplayOrder = 8

	local button = Window.SmallButton(screenGui, "SOUND", Theme.Colors.Ice, UDim2.new(0, 84, 0, 40),
		UDim2.new(1, -10, 0, 132), Vector2.new(1, 0))
	local window = Window.Mount(screenGui, "SoundWindow", "SOUND", { "SOUND" })
	window.Root.Size = UDim2.fromScale(0.42, 0.55)

	local function render()
		if not window.IsOpen() then
			return
		end
		local list = window.Content("SOUND")
		Window.Clear(list)
		local function volumeRow(order: number, title: string, key: string)
			local value = (settings :: any)[key] :: number
			local row = Window.Row(list, order, title, `{math.floor(value * 100 + 0.5)}%`, nil)
			local minus = Window.SmallButton(row.Right, "-", Theme.Colors.InkSoft, UDim2.new(0, 48, 0, 40))
			local plus = Window.SmallButton(row.Right, "+", Theme.Colors.Success, UDim2.new(0, 48, 0, 40))
			minus.Activated:Connect(function()
				(settings :: any)[key] = math.clamp(value - 0.1, 0, 1)
				applyVolumes()
				scheduleSave()
			end)
			plus.Activated:Connect(function()
				(settings :: any)[key] = math.clamp(value + 0.1, 0, 1)
				applyVolumes()
				scheduleSave()
			end)
		end
		volumeRow(1, "Music", "Music")
		volumeRow(2, "Effects", "Sfx")
		local muteRow = Window.Row(list, 3, "Mute everything", if settings.Muted then "Muted" else "Sound on", nil)
		local toggle = Window.SmallButton(muteRow.Right, if settings.Muted then "UNMUTE" else "MUTE",
			if settings.Muted then Theme.Colors.Success else Theme.Colors.Danger, UDim2.new(0, 110, 0, 40))
		toggle.Activated:Connect(function()
			settings.Muted = not settings.Muted
			applyVolumes()
			scheduleSave()
		end)
		local tracks = Window.Row(list, 4, "Music", "Winter tracks by APM Music (Roblox Creator Store)", nil)
		tracks.Title.TextColor3 = Theme.Colors.InkSoft
	end
	onSettingsChanged = render
	button.Activated:Connect(function()
		if window.IsOpen() then
			window.Close()
		else
			window.Open(nil, false)
			render()
		end
	end)
	screenGui.Parent = localPlayer:WaitForChild("PlayerGui")
end

function AudioController.Start()
	Remotes.GetEvent("AudioCue").OnClientEvent:Connect(function(name: any)
		if type(name) == "string" then
			playCue(name)
		end
	end)
	localPlayer:GetAttributeChangedSignal("AudioSettings"):Connect(readSaved)
	task.spawn(function()
		mountSettings()
		readSaved()
		startMusic()
	end)
end

return AudioController
