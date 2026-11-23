--!strict
--[[
	AudioService: the server side of sound (Config/AudioConfig).

	  Settings  each player's music / effects volume and mute, saved in
	            profile.Data.Settings.Audio = { Music, Sfx, Muted } and published as the Player
	            attribute "AudioSettings" (JSON). The client changes them through SaveSettings;
	            only numbers in [0, 1] and a boolean are accepted.
	  Cues      short sounds for big moments, sent only to the player concerned (AudioCue):
	              Legendary / Mythic   such an item reaches your hands
	              Craft                a crafting or mythic job finished
	              RareReward           recycling gave Rare or better
	              Upgrade              any upgrade / expansion was bought
	              Delivery             a scrap delivery arrived (everyone, quiet)
	The music itself is played by the client (AudioController) from AudioConfig.
]]

local HttpService = game:GetService("HttpService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local AudioConfig = require(ReplicatedStorage.Shared.Config.AudioConfig)
local GameConfig = require(ReplicatedStorage.Shared.Config.GameConfig)
local ItemConfig = require(ReplicatedStorage.Shared.Config.ItemConfig)
local Rarities = require(ReplicatedStorage.Shared.Config.Rarities)
local Remotes = require(ReplicatedStorage.Shared.Remotes)
local Validate = require(ReplicatedStorage.Shared.Util.Validate)

local CarryService = require(script.Parent.CarryService)
local DataService = require(script.Parent.DataService)
local EconomyService = require(script.Parent.EconomyService)
local JunkService = require(script.Parent.JunkService)
local MachineService = require(script.Parent.MachineService)
local RemoteGuard = require(script.Parent.RemoteGuard)

local AudioService = {}

local started = false

local function settingsOf(player: Player): any?
	local data = DataService.GetData(player)
	if data == nil then
		return nil
	end
	if type(data.Settings) ~= "table" then
		data.Settings = {}
	end
	local audio = data.Settings.Audio
	if type(audio) ~= "table" then
		audio = table.clone(AudioConfig.Defaults)
		data.Settings.Audio = audio
	end
	for key, default in AudioConfig.Defaults do
		if typeof(audio[key]) ~= typeof(default) then
			audio[key] = default
		end
	end
	return audio
end

local function publish(player: Player)
	local audio = settingsOf(player)
	if audio ~= nil then
		player:SetAttribute("AudioSettings", HttpService:JSONEncode({ Music = audio.Music, Sfx = audio.Sfx, Muted = audio.Muted }))
	end
end

function AudioService.Cue(player: Player, cue: string)
	if player.Parent == Players and AudioConfig.Cues[cue] ~= nil then
		Remotes.GetEvent("AudioCue"):FireClient(player, cue)
	end
end

function AudioService.SaveSettings(player: Player, settings: any): boolean
	local audio = settingsOf(player)
	if audio == nil or type(settings) ~= "table" then
		return false
	end
	local music, sfx, muted = settings.Music, settings.Sfx, settings.Muted
	if not (Validate.IsFiniteNumber(music) and Validate.IsFiniteNumber(sfx) and type(muted) == "boolean") then
		return false
	end
	audio.Music = math.clamp(math.floor(music * 20 + 0.5) / 20, 0, 1)
	audio.Sfx = math.clamp(math.floor(sfx * 20 + 0.5) / 20, 0, 1)
	audio.Muted = muted
	publish(player)
	return true
end

function AudioService.Start()
	assert(not started, "[AudioService] Start() called twice")
	started = true

	CarryService.ItemAdded:Connect(function(player: Player, itemId: string)
		local rank = Rarities.GetRank(ItemConfig.GetRarity(itemId))
		if rank >= Rarities.GetRank("Mythic") then
			AudioService.Cue(player, "Mythic")
		elseif rank >= Rarities.GetRank("Legendary") then
			AudioService.Cue(player, "Legendary")
		end
	end)
	MachineService.JobFinished:Connect(function(player: Player, result: any, kind: string?)
		if kind == "Craft" or kind == "Mythic" then
			AudioService.Cue(player, "Craft")
		elseif Rarities.GetRank(ItemConfig.GetRarity(result.Id)) >= Rarities.GetRank("Rare") then
			AudioService.Cue(player, "RareReward")
		end
	end)
	EconomyService.Spent:Connect(function(player: Player, _amount: number, reason: string)
		if string.find(reason, "Upgrade", 1, true) or string.find(reason, "Base:", 1, true) then
			AudioService.Cue(player, "Upgrade")
		end
	end)
	JunkService.Delivered:Connect(function(spawned: number)
		if spawned > 0 then
			for _, player in Players:GetPlayers() do
				AudioService.Cue(player, "Delivery")
			end
		end
	end)

	DataService.PlayerLoaded:Connect(publish)
	for _, player in Players:GetPlayers() do
		if DataService.IsLoaded(player) then
			publish(player)
		end
	end

	RemoteGuard.ConnectEvent(Remotes.GetEvent("SaveSettings"), {
		Name = "SaveSettings",
		MaxArgs = 1,
		RateLimit = GameConfig.RateLimits.SaveSettings,
		Validate = function(settings: any): boolean
			return type(settings) == "table"
		end,
	}, function(player: Player, settings: any)
		AudioService.SaveSettings(player, settings)
	end)
end

return AudioService
