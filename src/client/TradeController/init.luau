--!strict
--[[
	TradeController: the Trade Station window (server: TradeService). It only shows what the
	server sends (TradeState) and forwards button presses (TradeAction).
]]

local Players = game:GetService("Players")
local ProximityPromptService = game:GetService("ProximityPromptService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local ItemConfig = require(ReplicatedStorage.Shared.Config.ItemConfig)
local KlunksFormat = require(ReplicatedStorage.Shared.Util.KlunksFormat)
local Remotes = require(ReplicatedStorage.Shared.Remotes)

local CarryController = require(script.Parent.CarryController)
local DataController = require(script.Parent.DataController)
local InputController = require(script.Parent.InputController)
local NotifyController = require(script.Parent.NotifyController)
local Theme = require(script.Parent.UI.Theme)
local Window = require(script.Parent.EconomyController.Window)

local TradeController = {}

local localPlayer = Players.LocalPlayer
local MONEY_STEPS = { -100, -10, 10, 100, 1000 }

local function send(action: string, a: any?, b: any?)
	Remotes.GetEvent("TradeAction"):FireServer(action, a, b)
end

local function mount()
	local gui = Instance.new("ScreenGui")
	gui.Name = "JunkshotTrade"
	gui.ResetOnSpawn = false
	gui.ScreenInsets = Enum.ScreenInsets.CoreUISafeInsets
	gui.DisplayOrder = 8
	local window = Window.Mount(gui, "TradeWindow", "TRADE STATION", { "TRADE" })
	local session: any = nil
	local invites: { [number]: { Name: string, Until: number } } = {}

	local ready, readyLabel = Window.SmallButton(window.Footer, "READY", Theme.Colors.Success,
		UDim2.new(0.3, 0, 0, 42), UDim2.new(1, 0, 0.5, 0), Vector2.new(1, 0.5))
	local cancel = Window.SmallButton(window.Footer, "CANCEL", Theme.Colors.Danger,
		UDim2.new(0.24, 0, 0, 42), UDim2.new(0.68, 0, 0.5, 0), Vector2.new(1, 0.5))
	ready.Activated:Connect(function()
		if session ~= nil then
			send("Ready", not session.Mine.Ready)
		end
	end)
	cancel.Activated:Connect(function()
		send("Cancel")
	end)

	local function offerWith(change: (uids: { [string]: boolean }) -> (), klunks: number?)
		local chosen: { [string]: boolean } = {}
		for _, item in session.Mine.Items do
			chosen[item.Uid] = true
		end
		change(chosen)
		local uids = {}
		for uid in chosen do
			table.insert(uids, uid)
		end
		send("Offer", uids, klunks or session.Mine.Klunks)
	end

	local function render()
		if not window.IsOpen() then
			return
		end
		local list = window.Content("TRADE")
		Window.Clear(list)
		local order = 0
		local function add(): number
			order += 1
			return order
		end
		ready.Visible = session ~= nil
		cancel.Visible = session ~= nil
		if session == nil then
			window.SetTitle("TRADE STATION")
			local any = false
			for userId, invite in invites do
				if os.clock() < invite.Until then
					any = true
					local row = Window.Row(list, add(), `{invite.Name} wants to trade`, "Accept to open the trade", nil)
					Window.SmallButton(row.Right, "ACCEPT", Theme.Colors.Success, UDim2.new(0, 120, 0, 40)).Activated:Connect(function()
						send("Accept", userId)
					end)
				end
			end
			Window.Header(list, add(), "INVITE A PLAYER (both must stand here)")
			for _, player in Players:GetPlayers() do
				if player ~= localPlayer then
					any = true
					local row = Window.Row(list, add(), player.DisplayName, `@{player.Name}`, nil)
					Window.SmallButton(row.Right, "INVITE", Theme.Colors.Ice, UDim2.new(0, 120, 0, 40)).Activated:Connect(function()
						send("Invite", player.UserId)
					end)
				end
			end
			if not any then
				Window.Header(list, add(), "Nobody else is on this server.")
			end
			return
		end

		window.SetTitle(`TRADE WITH {string.upper(session.Name)}`)
		readyLabel.Text = if session.Locking then "SWAPPING..." elseif session.Mine.Ready then "NOT READY" else "READY"
		ready.BackgroundColor3 = if session.Mine.Ready then Theme.Colors.InkSoft else Theme.Colors.Success
		Window.Header(list, add(), `THEY GIVE {if session.Theirs.Ready then "(READY)" else ""}`)
		if session.Theirs.Klunks > 0 then
			Window.Row(list, add(), KlunksFormat.Format(session.Theirs.Klunks), "money", nil)
		end
		for _, item in session.Theirs.Items do
			Window.Row(list, add(), ItemConfig.GetDisplayName(item.Id), ItemConfig.GetRarity(item.Id) or "", item.Id)
		end
		if #session.Theirs.Items == 0 and session.Theirs.Klunks == 0 then
			Window.Row(list, add(), "Nothing yet", "", nil)
		end
		Window.Header(list, add(), `YOU GIVE {if session.Mine.Ready then "(READY)" else ""}`)
		local money = Window.Row(list, add(), KlunksFormat.Format(session.Mine.Klunks), `you have {KlunksFormat.Format(DataController.GetKlunks())}`, nil)
		for _, step in MONEY_STEPS do
			Window.SmallButton(money.Right, (if step > 0 then "+" else "") .. step, if step > 0 then Theme.Colors.Success else Theme.Colors.InkSoft,
				UDim2.new(0, 60, 0, 38)).Activated:Connect(function()
				offerWith(function() end, math.clamp(session.Mine.Klunks + step, 0, DataController.GetKlunks()))
			end)
		end
		local chosen: { [string]: boolean } = {}
		for _, item in session.Mine.Items do
			chosen[item.Uid] = true
		end
		for _, entry in CarryController.GetLocalCarried() do
			local row = Window.Row(list, add(), ItemConfig.GetDisplayName(entry.Id), ItemConfig.GetRarity(entry.Id) or "", entry.Id)
			local on = chosen[entry.Uid] == true
			if on then
				row.Frame.BackgroundColor3 = Color3.fromRGB(220, 248, 226)
			end
			Window.SmallButton(row.Right, if on then "TAKE BACK" else "OFFER", if on then Theme.Colors.InkSoft else Theme.Colors.Success,
				UDim2.new(0, 120, 0, 38)).Activated:Connect(function()
				offerWith(function(uids)
					uids[entry.Uid] = if on then nil else true
				end)
			end)
		end
	end

	Remotes.GetEvent("TradeState").OnClientEvent:Connect(function(payload: any)
		if type(payload) ~= "table" then
			return
		end
		if payload.Kind == "Invite" then
			invites[payload.UserId] = { Name = payload.Name, Until = os.clock() + payload.Seconds }
			NotifyController.Show(`{payload.Name} wants to trade - open the Trade Station`, "Info")
		elseif payload.Kind == "Session" then
			session = payload
			if not window.IsOpen() then
				window.Open(nil, InputController.GetInputKind() == "Gamepad")
			end
		elseif payload.Kind == "Closed" then
			session = nil
			table.clear(invites)
			NotifyController.Show(payload.Reason, if payload.Reason == "Trade complete!" then "Success" else "Warning")
			window.Close()
		end
		render()
	end)
	CarryController.Changed:Connect(render)
	Players.PlayerAdded:Connect(render)
	Players.PlayerRemoving:Connect(function()
		task.defer(render)
	end)
	window.Closed.Event:Connect(function()
		if session ~= nil then
			send("Cancel")
		end
	end)
	ProximityPromptService.PromptTriggered:Connect(function(prompt: ProximityPrompt, player: Player)
		if player == localPlayer and prompt:GetAttribute("PromptKind") == "Trade" then
			window.Open(nil, InputController.GetInputKind() == "Gamepad")
			render()
		end
	end)
	ProximityPromptService.PromptHidden:Connect(function(prompt: ProximityPrompt)
		if prompt:GetAttribute("PromptKind") ~= "Trade" or session ~= nil or not window.IsOpen() then
			return
		end
		local character = localPlayer.Character
		local root = if character ~= nil then character:FindFirstChild("HumanoidRootPart") else nil
		local anchor = prompt.Parent
		if root == nil or not root:IsA("BasePart") or anchor == nil or not anchor:IsA("BasePart")
			or (root.Position - anchor.Position).Magnitude > 18
		then
			window.Close()
		end
	end)
	gui.Parent = localPlayer:WaitForChild("PlayerGui")
end

function TradeController.Start()
	task.spawn(mount)
end

return TradeController
