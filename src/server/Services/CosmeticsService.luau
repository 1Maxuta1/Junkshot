--!strict
--[[
	CosmeticsService: cosmetic unlocks and what each player wears (Config/CosmeticsConfig).

	Saved in profile.Data.Cosmetics = { Owned = { [id] = source }, Equipped = { [category] = id } }.
	  Unlock(player, id, source)   server-only (Game Pass grants, future rewards); idempotent
	  Equip(player, category, id?) the CosmeticEquip remote: only OWNED cosmetics of that
	                               category; nil / "" takes it off
	  IsOwned(player, id)
	Visuals (server-built, replicate to everyone):
	  Backpack, ToolSkin   welded to the character's torso on every spawn; without a Backpack
	                     cosmetic the pack of the Bigger Backpack upgrade is worn
	                     (Util/BackpackModels)
	  Title                a small BillboardGui above the head
	  Companion            CompanionService
	Published for the UI as Player attributes "CosmeticsOwned" (comma list) and
	"Equipped_<Category>". Nothing here changes any gameplay value.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local CosmeticsConfig = require(ReplicatedStorage.Shared.Config.CosmeticsConfig)
local BackpackModels = require(ReplicatedStorage.Shared.Util.BackpackModels)
local Remotes = require(ReplicatedStorage.Shared.Remotes)
local Signal = require(ReplicatedStorage.Shared.Util.Signal)
local Validate = require(ReplicatedStorage.Shared.Util.Validate)

local DataService = require(script.Parent.DataService)
local RemoteGuard = require(script.Parent.RemoteGuard)
local CosmeticModels = require(script.Parent.Cosmetics.CosmeticModels)

local CosmeticsService = {}

CosmeticsService.EquippedChanged = Signal.new() -- (player, category, id?)

local VISUAL_FOLDER = "JunkshotCosmetics"
local started = false

local function cosmeticsOf(player: Player): any?
	local data = DataService.GetData(player)
	if data == nil then
		return nil
	end
	if type(data.Cosmetics) ~= "table" then
		data.Cosmetics = { Owned = {}, Equipped = {} }
	end
	local c = data.Cosmetics
	if type(c.Owned) ~= "table" then
		c.Owned = {}
	end
	if type(c.Equipped) ~= "table" then
		c.Equipped = {}
	end
	return c
end

function CosmeticsService.IsOwned(player: Player, id: string): boolean
	local c = cosmeticsOf(player)
	return c ~= nil and c.Owned[id] ~= nil and CosmeticsConfig.Get(id) ~= nil
end

function CosmeticsService.GetEquipped(player: Player, category: string): string?
	local c = cosmeticsOf(player)
	local id = if c ~= nil then c.Equipped[category] else nil
	if type(id) == "string" and CosmeticsService.IsOwned(player, id) then
		return id
	end
	return nil
end

local function publish(player: Player)
	local c = cosmeticsOf(player)
	if c == nil then
		return
	end
	local owned = {}
	for id in c.Owned do
		if CosmeticsConfig.Get(id) ~= nil then
			table.insert(owned, id)
		end
	end
	table.sort(owned)
	player:SetAttribute("CosmeticsOwned", table.concat(owned, ","))
	for _, category in CosmeticsConfig.Categories do
		player:SetAttribute(`Equipped_{category}`, CosmeticsService.GetEquipped(player, category))
	end
end

-- Builds the worn cosmetics (backpack, shovel, title) on the current character.
local function dress(player: Player)
	local character = player.Character
	if character == nil then
		return
	end
	local old = character:FindFirstChild(VISUAL_FOLDER)
	if old ~= nil then
		old:Destroy()
	end
	local torso = character:FindFirstChild("UpperTorso") or character:FindFirstChild("Torso")
	local head = character:FindFirstChild("Head")
	if torso == nil or not torso:IsA("BasePart") then
		return
	end
	local folder = Instance.new("Folder")
	folder.Name = VISUAL_FOLDER
	for _, category in { "Backpack", "ToolSkin" } do
		local id = CosmeticsService.GetEquipped(player, category)
		local cosmetic = if id ~= nil then CosmeticsConfig.Get(id) else nil
		local model = if cosmetic ~= nil and cosmetic.Model ~= nil then CosmeticModels.Build(cosmetic.Model, false) else nil
		if model ~= nil then
			model:PivotTo(torso.CFrame)
			for _, descendant in model:GetDescendants() do
				if descendant:IsA("BasePart") then
					local weld = Instance.new("WeldConstraint")
					weld.Part0 = torso
					weld.Part1 = descendant
					weld.Parent = descendant
				end
			end
			model.Parent = folder
		end
	end
	local packLevel = player:GetAttribute("Upgrade_CarryCapacity")
	local pack = if CosmeticsService.GetEquipped(player, "Backpack") == nil and type(packLevel) == "number"
		then BackpackModels.Build(packLevel)
		else nil
	if pack ~= nil and pack.PrimaryPart ~= nil then
		local body = pack.PrimaryPart
		local origin = CFrame.new(0, 0, torso.Size.Z / 2 - 0.5) -- thinner and thicker avatars
		pack:PivotTo(torso.CFrame * origin)
		local weld = Instance.new("Weld") -- swayed by BackpackController
		weld.Name = "PackWeld"
		weld.Part0 = torso
		weld.Part1 = body
		weld.C0 = torso.CFrame:ToObjectSpace(body.CFrame)
		weld.Parent = body
		pack.Parent = folder
	end
	player:SetAttribute("PackWorn", pack ~= nil)
	local titleId = CosmeticsService.GetEquipped(player, "Title")
	local title = if titleId ~= nil then CosmeticsConfig.Get(titleId) else nil
	if title ~= nil and head ~= nil and head:IsA("BasePart") then
		local gui = Instance.new("BillboardGui")
		gui.Name = "Title"
		gui.Adornee = head
		gui.Size = UDim2.fromOffset(200, 26)
		gui.StudsOffset = Vector3.new(0, 3.4, 0)
		gui.MaxDistance = 90
		gui.LightInfluence = 0
		local label = Instance.new("TextLabel")
		label.Size = UDim2.fromScale(1, 1)
		label.BackgroundTransparency = 1
		label.Font = Enum.Font.FredokaOne
		label.Text = `★ {title.DisplayName} ★`
		label.TextColor3 = title.TitleColor or Color3.new(1, 1, 1)
		label.TextScaled = true
		label.TextStrokeTransparency = 0.3
		label.TextStrokeColor3 = Color3.fromRGB(24, 44, 86)
		label.Parent = gui
		gui.Parent = folder
	end
	folder.Parent = character
end

-- Server-only: gives a cosmetic (idempotent; a second call changes nothing).
function CosmeticsService.Unlock(player: Player, id: string, source: string): boolean
	local c = cosmeticsOf(player)
	local cosmetic = CosmeticsConfig.Get(id)
	if c == nil or cosmetic == nil then
		return false
	end
	if c.Owned[id] == nil then
		c.Owned[id] = source
		-- Newly unlocked and nothing worn in that slot: wear it right away.
		if c.Equipped[cosmetic.Category] == nil then
			c.Equipped[cosmetic.Category] = id
			CosmeticsService.EquippedChanged:Fire(player, cosmetic.Category, id)
			dress(player)
		end
		publish(player)
	end
	return true
end

function CosmeticsService.Equip(player: Player, category: any, id: any): (boolean, string?)
	local c = cosmeticsOf(player)
	if c == nil then
		return false, "NotLoaded"
	end
	if type(category) ~= "string" or not table.find(CosmeticsConfig.Categories, category) then
		return false, "InvalidCategory"
	end
	if id == nil or id == "" then
		c.Equipped[category] = nil
	else
		local cosmetic = if type(id) == "string" then CosmeticsConfig.Get(id) else nil
		if cosmetic == nil or cosmetic.Category ~= category then
			return false, "InvalidCosmetic"
		end
		if c.Owned[id] == nil then
			return false, "NotOwned"
		end
		c.Equipped[category] = id
	end
	publish(player)
	dress(player)
	CosmeticsService.EquippedChanged:Fire(player, category, c.Equipped[category])
	return true, nil
end

function CosmeticsService.Start()
	assert(not started, "[CosmeticsService] Start() called twice")
	started = true

	local function hook(player: Player)
		player:GetAttributeChangedSignal("Upgrade_CarryCapacity"):Connect(function()
			dress(player)
		end)
		player.CharacterAdded:Connect(function(character: Model)
			character:WaitForChild("Head", 10)
			if DataService.GetData(player) ~= nil then
				dress(player)
			end
		end)
	end
	Players.PlayerAdded:Connect(hook)
	for _, player in Players:GetPlayers() do
		hook(player)
	end
	DataService.PlayerLoaded:Connect(function(player: Player)
		publish(player)
		dress(player)
	end)
	for _, player in Players:GetPlayers() do
		if DataService.IsLoaded(player) then
			publish(player)
			dress(player)
		end
	end

	RemoteGuard.ConnectEvent(Remotes.GetEvent("CosmeticEquip"), {
		Name = "CosmeticEquip",
		MaxArgs = 2,
		RateLimit = { MaxRequests = 4, Window = 2 },
		Validate = function(category: any, id: any): boolean
			return Validate.IsString(category, 1, 24) and (id == nil or Validate.IsString(id, 0, 64))
		end,
	}, function(player: Player, category: string, id: string?)
		CosmeticsService.Equip(player, category, id)
	end)
end

return CosmeticsService
