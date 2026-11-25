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
local RunService = game:GetService("RunService")
local SoundService = game:GetService("SoundService")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local AudioConfig = require(ReplicatedStorage.Shared.Config.AudioConfig)
local Signal = require(ReplicatedStorage.Shared.Util.Signal)
local Remotes = require(ReplicatedStorage.Shared.Remotes)

local Theme = require(script.Parent.UI.Theme)
local Window = require(script.Parent.EconomyController.Window)

local AudioController = {}

AudioController.GraphicsChanged = Signal.new() -- ()

local localPlayer = Players.LocalPlayer
local SAVE_DELAY = 1.5
local DUCK_DISTANCE = 60 -- studs to a playing boombox
local DUCK_VOLUME = 0.12 -- share of the music volume left next to it

local duck = 1

local settings = { Music = AudioConfig.Defaults.Music, Sfx = AudioConfig.Defaults.Sfx, Muted = AudioConfig.Defaults.Muted, Graphics = AudioConfig.Defaults.Graphics }
local music: { Sound } = {}
local current = 1
local order: { number } = {}
local orderIndex = 0
local lastCue: { [string]: number } = {}
local cueSounds: { [string]: Sound } = {}
local saveToken = 0
local onSettingsChanged: (() -> ())? = nil

local function musicVolume(): number
	return if settings.Muted then 0 else AudioConfig.Music.Volume * settings.Music * duck
end

-- The one tween that moves the current track's volume. A new one (or a settings change) ends the
-- old one, otherwise a fade that is still running would overwrite the player's mute.
local volumeTween: Tween? = nil

local function fadeMusic(sound: Sound, seconds: number)
	if volumeTween ~= nil then
		volumeTween:Cancel()
	end
	local tween = TweenService:Create(sound, TweenInfo.new(seconds), { Volume = musicVolume() })
	volumeTween = tween
	tween:Play()
end

-- Background music fades down next to a playing boombox (attribute Audible on placed radios).
local function nearPlayingRadio(): boolean
	local deployed = Workspace:FindFirstChild("Deployed")
	local camera = Workspace.CurrentCamera
	if deployed == nil or camera == nil then
		return false
	end
	for _, model in deployed:GetChildren() do
		if model:GetAttribute("Audible") == true and model:IsA("Model")
			and (model:GetPivot().Position - camera.CFrame.Position).Magnitude <= DUCK_DISTANCE
		then
			return true
		end
	end
	return false
end

local function watchRadios()
	while true do
		task.wait(0.5)
		local target = if nearPlayingRadio() then DUCK_VOLUME else 1
		if target ~= duck then
			duck = target
			local sound = music[current]
			if sound ~= nil then
				fadeMusic(sound, 1.2)
			end
		end
	end
end

-- Two groups, so MUTE silences really everything: World = sounds nobody else scales (footsteps,
-- engines, boomboxes ...), Direct = sounds this module already started at the effects volume.
local groups: { [string]: SoundGroup } = {}

local function groupOf(name: string): SoundGroup
	local group = groups[name]
	if group == nil then
		group = Instance.new("SoundGroup")
		group.Name = `Junkshot{name}`
		group.Parent = SoundService
		groups[name] = group
	end
	return group
end

local function applyGroups()
	groupOf("World").Volume = if settings.Muted then 0 else settings.Sfx / AudioConfig.Defaults.Sfx
	groupOf("Direct").Volume = if settings.Muted then 0 else 1
end

local function adopt(instance: Instance)
	if instance:IsA("Sound") and instance.SoundGroup == nil and not instance:IsDescendantOf(SoundService) then
		instance.SoundGroup = groupOf("World")
	elseif instance:IsA("AudioPlayer") then
		instance.Volume = if settings.Muted then 0 else instance.Volume
	end
end

local function applyVolumes()
	applyGroups()
	local sound = music[current]
	if sound ~= nil then
		if volumeTween ~= nil then
			volumeTween:Cancel()
			volumeTween = nil
		end
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
	fadeMusic(sound, fade)
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
	sound.SoundGroup = groupOf("Direct")
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

-- A short item sound (Config/ItemSounds family): quiet, with softened highs. parent = nil plays
-- it for this player only. At most MAX_ITEM_SOUNDS at once, so a pile of throws is no noise.
local MAX_ITEM_SOUNDS = 8
local itemSounds = 0
local softGroup: SoundGroup? = nil

function AudioController.PlayItem(family: any, pitch: number, parent: Instance?, volume: number?, range: number?)
	local level = AudioController.GetSfxVolume()
	if family == nil or level <= 0 or itemSounds >= MAX_ITEM_SOUNDS then
		return
	end
	if softGroup == nil then
		local group = Instance.new("SoundGroup")
		group.Name = "ItemSounds"
		local equalizer = Instance.new("EqualizerSoundEffect")
		equalizer.HighGain = -9
		equalizer.MidGain = -1
		equalizer.LowGain = 0
		equalizer.Parent = group
		group.Parent = groupOf("Direct")
		softGroup = group
	end
	local sound = Instance.new("Sound")
	sound.Name = "ItemSound"
	sound.SoundId = family.SoundId
	sound.Volume = family.Volume * level * (volume or 1)
	sound.PlaybackSpeed = pitch * (0.96 + math.random() * 0.08) -- never exactly the same twice
	sound.PlaybackRegionsEnabled = true
	sound.PlaybackRegion = NumberRange.new(family.Start, family.Start + family.Length)
	sound.RollOffMinDistance = 8
	sound.RollOffMaxDistance = range or 70
	sound.SoundGroup = softGroup
	sound.Parent = parent or SoundService
	itemSounds += 1
	sound:Play()
	if family.Wobble then
		local started = os.clock()
		task.spawn(function()
			while sound.Parent ~= nil and os.clock() - started < family.Length / pitch + 0.5 do
				local t = os.clock() - started
				sound.PlaybackSpeed = pitch * (0.9 + t * 0.9 + math.sin(t * 34) * 0.22 * math.exp(-t * 1.5))
				RunService.Heartbeat:Wait()
			end
		end)
	end
	task.delay(family.Length / pitch + 0.6, function()
		itemSounds -= 1
		sound:Destroy()
	end)
end

function AudioController.GetGraphics(): string
	return settings.Graphics
end

local function scheduleSave()
	saveToken += 1
	local token = saveToken
	task.delay(SAVE_DELAY, function()
		if token == saveToken then
			Remotes.GetEvent("SaveSettings"):FireServer({ Music = settings.Music, Sfx = settings.Sfx, Muted = settings.Muted, Graphics = settings.Graphics })
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
		if type(decoded.Graphics) == "string" then
			settings.Graphics = decoded.Graphics
		end
		AudioController.GraphicsChanged:Fire()
		applyVolumes()
	end
end

local function mountSettings()
	local screenGui = Instance.new("ScreenGui")
	screenGui.Name = "JunkshotAudio"
	screenGui.ResetOnSpawn = false
	screenGui.ScreenInsets = Enum.ScreenInsets.CoreUISafeInsets
	screenGui.DisplayOrder = 8

	local button = Window.HudButton("JunkshotSoundButton", "SOUND", Theme.Colors.Ice, UDim2.new(0, 66, 0, 38),
		UDim2.new(1, -81, 0, 46))
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
		local graphicsRow = Window.Row(list, 4, "Graphics", if settings.Graphics == "Lite" then "Faster, fewer effects" elseif settings.Graphics == "Full" then "Everything on" else "Chooses for your device", nil)
		local choices = { "Auto", "Lite", "Full" }
		local pick = Window.SmallButton(graphicsRow.Right, string.upper(settings.Graphics), Theme.Colors.Ice, UDim2.new(0, 110, 0, 40))
		pick.Activated:Connect(function()
			settings.Graphics = choices[(table.find(choices, settings.Graphics) or 0) % #choices + 1]
			AudioController.GraphicsChanged:Fire()
			applyVolumes()
			scheduleSave()
		end)
		local tracks = Window.Row(list, 5, "Music", "Winter tracks by APM Music (Roblox Creator Store)", nil)
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
	applyGroups()
	for _, instance in Workspace:GetDescendants() do
		adopt(instance)
	end
	Workspace.DescendantAdded:Connect(adopt)
	task.spawn(function()
		mountSettings()
		readSaved()
		startMusic()
		watchRadios()
	end)
end

return AudioController
