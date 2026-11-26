--!strict
--[[
	LocalizationController: every text this player sees, in their language (shared/Localization).

	Watches TextLabels and TextButtons in PlayerGui and in world SurfaceGuis / BillboardGuis.
	Whenever the game writes English into one, the translation replaces it right away (the
	other controllers keep writing English and never know). TextBoxes are left alone: players
	type into them. English players: nothing is watched at all.

	Studio only: ReplicatedStorage attribute ForceLanguage = "es" (or any code) picks the
	language, and PlayerGui.LocalizationDebug:Invoke() lists the texts that had no
	translation, for tools/i18n.
]]

local LocalizationService = game:GetService("LocalizationService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Localization = require(ReplicatedStorage.Shared.Localization)

local LocalizationController = {}

local localPlayer = Players.LocalPlayer
local translator: Localization.Translator? = nil
local written: { [Instance]: string } = setmetatable({}, { __mode = "k" }) :: any

local function languageCode(): string
	if RunService:IsStudio() then
		local forced = ReplicatedStorage:GetAttribute("ForceLanguage")
		if type(forced) == "string" and forced ~= "" then
			return Localization.CodeFor(forced)
		end
	end
	local ok, locale = pcall(function()
		return LocalizationService.RobloxLocaleId
	end)
	if ok and type(locale) == "string" and locale ~= "" then
		return Localization.CodeFor(locale)
	end
	return Localization.CodeFor(localPlayer.LocaleId)
end

-- Labels are sized for English. A longer translation in a scaled label may shrink further
-- instead of breaking a word in the middle ("Транспо рт"). TextWrapped stays as it is:
-- switching it off makes a scaled label pick a much smaller size.
local LONGER = 1.15
local MIN_SIZE = 8

local function fitLonger(label: TextLabel | TextButton, english: string, translated: string)
	if not label.TextScaled or utf8.len(translated) == nil or utf8.len(english) == nil then
		return
	end
	if (utf8.len(translated) :: number) <= (utf8.len(english) :: number) * LONGER then
		return
	end
	local constraint = label:FindFirstChildOfClass("UITextSizeConstraint")
	if constraint ~= nil and constraint.MinTextSize > MIN_SIZE then
		constraint.MinTextSize = MIN_SIZE
	end
end

local function apply(label: TextLabel | TextButton)
	local active = translator
	if active == nil then
		return
	end
	local text = label.Text
	if written[label] == text then
		return -- our own translation coming back through the Changed signal
	end
	local translated = active.Translate(text)
	written[label] = translated
	if translated ~= text then
		label.Text = translated
		fitLonger(label, text, translated)
	end
end

local function watch(instance: Instance)
	if instance:IsA("TextLabel") or instance:IsA("TextButton") then
		local label = instance :: TextLabel
		label.AutoLocalize = false -- Roblox's own automatic translation would fight ours
		apply(label)
		label:GetPropertyChangedSignal("Text"):Connect(function()
			apply(label)
		end)
	end
end

local function watchTree(root: Instance)
	for _, descendant in root:GetDescendants() do
		watch(descendant)
	end
	root.DescendantAdded:Connect(watch)
end

-- World texts live in SurfaceGuis / BillboardGuis anywhere in the Workspace.
local function watchWorld()
	local function onWorld(instance: Instance)
		if instance:IsA("TextLabel") or instance:IsA("TextButton") then
			if instance:FindFirstAncestorWhichIsA("LayerCollector") ~= nil then
				watch(instance)
			end
		end
	end
	for _, descendant in Workspace:GetDescendants() do
		onWorld(descendant)
	end
	Workspace.DescendantAdded:Connect(onWorld)
end

-- For other controllers that build text outside a label (e.g. a prompt's ActionText).
function LocalizationController.Translate(text: string): string
	local active = translator
	return if active ~= nil then active.Translate(text) else text
end

function LocalizationController.GetCode(): string
	local active = translator
	return if active ~= nil then active.Code else "en"
end

function LocalizationController.Start()
	local code = languageCode()
	local entries = Localization.Load(code)
	if entries == nil then
		return -- English
	end
	local active = Localization.NewTranslator(code, entries, RunService:IsStudio())
	translator = active
	if RunService:IsStudio() then
		-- tools/i18n: PlayerGui.LocalizationDebug:Invoke() lists the texts that had no translation.
		local debug = Instance.new("BindableFunction")
		debug.Name = "LocalizationDebug"
		debug.OnInvoke = function(): { string }
			local list = {}
			for text in active.Missing do
				table.insert(list, text)
			end
			table.sort(list)
			return list
		end
		debug.Parent = localPlayer:WaitForChild("PlayerGui")
	end
	task.spawn(function()
		watchTree(localPlayer:WaitForChild("PlayerGui"))
	end)
	task.spawn(watchWorld)
end

return LocalizationController
