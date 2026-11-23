--!strict
--[[
	Detector behavior (Metal Detector): a tool used while carried (Mode "Use").

	The player selects it in the hotbar and switches it on (G / D-pad up / USE button). While it
	is on, the client asks for a scan every ScanInterval seconds through ItemUse(uid). The
	server checks that the player really carries this detector (PlacementService.Use), then
	finds the nearest loose item of at least MinRarity within Range of the player (items
	reserved for someone else are ignored) and answers on ItemFx:
	  { Kind = "Detector", Uid, Found, Rarity?, Distance?, Position?, TargetUid? }
	The client beeps faster the closer it is, points to it, and highlights it up close.
	The rarity is revealed, the item itself is not (it is a surprise until picked up).
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local ItemConfig = require(ReplicatedStorage.Shared.Config.ItemConfig)
local Rarities = require(ReplicatedStorage.Shared.Config.Rarities)
local Remotes = require(ReplicatedStorage.Shared.Remotes)

local CarryService = require(script.Parent.Parent.CarryService)
local JunkService = require(script.Parent.Parent.JunkService)

local Detector = {}

export type ScanResult = {
	Kind: string,
	Uid: string,
	Found: boolean,
	Rarity: string?,
	Distance: number?,
	Position: Vector3?,
	TargetUid: string?,
}

-- Runs one scan for the player (also called by DevTests). nil when the player has no character.
function Detector.Scan(player: Player, detectorUid: string, config: any): ScanResult?
	local root = CarryService.GetLiveRoot(player)
	if root == nil then
		return nil
	end
	local minRank = Rarities.GetRank(config.MinRarity)
	local model, uid, itemId, distance = JunkService.FindNearest(root.Position, config.Range, function(id: string): boolean
		return Rarities.GetRank(ItemConfig.GetRarity(id)) >= minRank
	end, player.UserId)
	if model == nil or itemId == nil then
		return { Kind = "Detector", Uid = detectorUid, Found = false }
	end
	return {
		Kind = "Detector",
		Uid = detectorUid,
		Found = true,
		Rarity = ItemConfig.GetRarity(itemId),
		Distance = distance,
		Position = JunkService.GetPosition(model),
		TargetUid = uid,
	}
end

function Detector.Use(player: Player, carried: any, behavior: any): (boolean, string?)
	local result = Detector.Scan(player, carried.Uid, behavior.Detector)
	if result == nil then
		return false, "NoCharacter"
	end
	Remotes.GetEvent("ItemFx"):FireClient(player, result)
	return true, nil
end

return Detector
