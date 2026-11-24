--!strict
--[[
	TradeService: the TRADE STATION on the plaza - two players swap carried items and Klunks.

	Flow: both stand at the station -> Invite -> Accept -> each side edits its offer -> both
	press READY -> LOCK_SECONDS later everything is swapped in one step.

	Safety
	  - Offers hold only uids in the owner's hands and an amount they can afford; both are checked
	    again in the moment of the swap (execute), which never yields: either all of it happens
	    or nothing.
	  - Every change of an offer takes READY away from BOTH sides and READY is refused for
	    CHANGE_LOCK seconds after it, so an offer cannot be switched at the last moment.
	  - Items keep their uid (CarryService), so nothing can be duplicated. Money goes through
	    EconomyService (logged as "Trade").
	  - The last LOCK_SECONDS are shown to both (LockEndsAt, server time); taking READY back or
	    CANCEL during them stops the swap.
	  - Walking away, dying or leaving cancels. A player is in at most one trade.

	Remotes: TradeAction client -> server (action, a, b); TradeState server -> client (table).
]]

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local GameConfig = require(ReplicatedStorage.Shared.Config.GameConfig)
local Remotes = require(ReplicatedStorage.Shared.Remotes)
local Validate = require(ReplicatedStorage.Shared.Util.Validate)

local CarryService = require(script.Parent.CarryService)
local EconomyService = require(script.Parent.EconomyService)
local RemoteGuard = require(script.Parent.RemoteGuard)

local TradeService = {}

local DISTANCE = 24
local INVITE_SECONDS = 30
local CHANGE_LOCK = 2
local LOCK_SECONDS = 3
local MAX_ITEMS = 9

TradeService.LockSeconds = LOCK_SECONDS
TradeService.ChangeLock = CHANGE_LOCK

type Offer = { Uids: { string }, Klunks: number, Ready: boolean }
type Session = { A: Player, B: Player, Offers: { [Player]: Offer }, ChangedAt: number, Token: number, LockEndsAt: number?, Closed: boolean }

local started = false
local anchor: BasePart? = nil
local sessions: { [Player]: Session } = {}
local invites: { [Player]: { [Player]: number } } = {} -- target -> from -> expires

local function send(player: Player, payload: { [string]: any })
	if player.Parent == Players then
		Remotes.GetEvent("TradeState"):FireClient(player, payload)
	end
end

local function otherOf(session: Session, player: Player): Player
	return if session.A == player then session.B else session.A
end

function TradeService.GetPosition(): Vector3?
	return if anchor ~= nil then anchor.Position else nil
end

function TradeService.IsNear(player: Player): boolean
	local root = CarryService.GetLiveRoot(player)
	return root ~= nil and anchor ~= nil and (root.Position - anchor.Position).Magnitude <= DISTANCE
end

local function idOf(player: Player, uid: string): string?
	for _, entry in CarryService.GetCarried(player) do
		if entry.Uid == uid then
			return entry.Id
		end
	end
	return nil
end

local function describe(player: Player, offer: Offer): any
	local items = {}
	for _, uid in offer.Uids do
		local id = idOf(player, uid)
		if id ~= nil then
			table.insert(items, { Uid = uid, Id = id })
		end
	end
	return { Items = items, Klunks = offer.Klunks, Ready = offer.Ready }
end

local function publish(session: Session)
	for _, player in { session.A, session.B } do
		local other = otherOf(session, player)
		send(player, {
			Kind = "Session",
			Name = other.DisplayName,
			Mine = describe(player, session.Offers[player]),
			Theirs = describe(other, session.Offers[other]),
			LockEndsAt = session.LockEndsAt, -- server time of the swap, nil = not counting down
		})
	end
end

local function close(session: Session, reason: string)
	if session.Closed then
		return
	end
	session.Closed = true
	session.Token += 1
	for _, player in { session.A, session.B } do
		if sessions[player] == session then
			sessions[player] = nil
		end
		send(player, { Kind = "Closed", Reason = reason })
	end
end

function TradeService.GetSession(player: Player): Session?
	return sessions[player]
end

function TradeService.Invite(from: Player, target: Player): (boolean, string?)
	if from == target or target.Parent ~= Players then
		return false, "NoTarget"
	end
	if not TradeService.IsNear(from) or not TradeService.IsNear(target) then
		return false, "TooFar"
	end
	if sessions[from] ~= nil or sessions[target] ~= nil then
		return false, "Busy"
	end
	invites[target] = invites[target] or {}
	invites[target][from] = os.clock() + INVITE_SECONDS
	send(target, { Kind = "Invite", UserId = from.UserId, Name = from.DisplayName, Seconds = INVITE_SECONDS })
	return true, nil
end

function TradeService.Accept(player: Player, from: Player): (boolean, string?)
	local expires = if invites[player] ~= nil then invites[player][from] else nil
	if expires == nil or os.clock() > expires then
		return false, "NoInvite"
	end
	if sessions[player] ~= nil or sessions[from] ~= nil then
		return false, "Busy"
	end
	if not TradeService.IsNear(player) or not TradeService.IsNear(from) then
		return false, "TooFar"
	end
	invites[player] = nil
	local session: Session = {
		A = from,
		B = player,
		Offers = {
			[from] = { Uids = {}, Klunks = 0, Ready = false },
			[player] = { Uids = {}, Klunks = 0, Ready = false },
		},
		ChangedAt = os.clock(),
		Token = 0,
		LockEndsAt = nil,
		Closed = false,
	}
	sessions[from], sessions[player] = session, session
	publish(session)
	return true, nil
end

function TradeService.SetOffer(player: Player, uids: any, klunks: any): (boolean, string?)
	local session = sessions[player]
	if session == nil then
		return false, "NoSession"
	end
	if type(uids) ~= "table" or #uids > MAX_ITEMS or not Validate.IsInteger(klunks, 0, GameConfig.Klunks.MaxBalance) then
		return false, "InvalidArguments"
	end
	local seen: { [string]: boolean } = {}
	local list: { string } = {}
	for index = 1, #uids do
		local uid = uids[index]
		if not Validate.IsUid(uid) or seen[uid] or not CarryService.HasUid(player, uid) then
			return false, "NotCarried"
		end
		seen[uid] = true
		table.insert(list, uid)
	end
	if klunks > 0 and not EconomyService.CanAfford(player, klunks) then
		return false, "NotEnough"
	end
	session.Offers[player].Uids = list
	session.Offers[player].Klunks = klunks
	for _, offer in session.Offers do
		offer.Ready = false
	end
	session.ChangedAt = os.clock()
	session.LockEndsAt = nil
	session.Token += 1
	publish(session)
	return true, nil
end

-- Everything is checked first; then the swap happens without a yield.
local function execute(session: Session): (boolean, string?)
	for player, offer in session.Offers do
		local other = otherOf(session, player)
		if not TradeService.IsNear(player) then
			return false, "TooFar"
		end
		for _, uid in offer.Uids do
			if not CarryService.HasUid(player, uid) then
				return false, "NotCarried"
			end
		end
		if offer.Klunks > 0 and not EconomyService.CanAfford(player, offer.Klunks) then
			return false, "NotEnough"
		end
		local incoming = #session.Offers[other].Uids
		if CarryService.GetCount(player) - #offer.Uids + incoming > CarryService.GetCapacity(player) then
			return false, "HandsFull"
		end
		local balance = EconomyService.GetBalance(player)
		if balance == nil or balance - offer.Klunks + session.Offers[other].Klunks > GameConfig.Klunks.MaxBalance then
			return false, "BalanceCap"
		end
	end
	local moving: { { To: Player, Uid: string, Id: string } } = {}
	for player, offer in session.Offers do
		for _, uid in offer.Uids do
			local item = CarryService.TakeByUid(player, uid)
			if item ~= nil then
				table.insert(moving, { To = otherOf(session, player), Uid = item.Uid, Id = item.Id })
			end
		end
	end
	for _, item in moving do
		CarryService.AddJunk(item.To, item.Id, item.Uid)
	end
	for player, offer in session.Offers do
		if offer.Klunks > 0 then
			EconomyService.Spend(player, offer.Klunks, "Trade")
			EconomyService.Earn(otherOf(session, player), offer.Klunks, "Trade")
		end
	end
	return true, nil
end

local FAIL_TEXT: { [string]: string } = {
	TooFar = "Trade cancelled: someone walked away",
	NotCarried = "Trade cancelled: an item is gone",
	NotEnough = "Trade cancelled: not enough money",
	HandsFull = "Trade cancelled: not enough room in the hands",
	BalanceCap = "Trade cancelled: a wallet is full",
}

function TradeService.SetReady(player: Player, ready: boolean): (boolean, string?)
	local session = sessions[player]
	if session == nil then
		return false, "NoSession"
	end
	if ready and os.clock() - session.ChangedAt < CHANGE_LOCK then
		return false, "JustChanged"
	end
	local other = otherOf(session, player)
	if session.Offers[player].Ready == ready then
		return true, nil -- a repeated press must not restart the countdown
	end
	local wasLocking = session.LockEndsAt ~= nil
	local locking = ready and session.Offers[other].Ready
	session.Offers[player].Ready = ready
	session.LockEndsAt = if locking then Workspace:GetServerTimeNow() + LOCK_SECONDS else nil
	session.Token += 1
	publish(session)
	if wasLocking then
		for _, each in { player, other } do
			EconomyService.Message(each, `{player.DisplayName} stopped the swap`, "Warning")
		end
	end
	if locking then
		local token = session.Token
		task.delay(LOCK_SECONDS, function()
			if session.Closed or session.Token ~= token then
				return
			end
			local ok, code = execute(session)
			close(session, if ok then "Trade complete!" else (FAIL_TEXT[code or ""] or "Trade cancelled"))
		end)
	end
	return true, nil
end

function TradeService.Cancel(player: Player)
	local session = sessions[player]
	if session ~= nil then
		close(session, `Trade cancelled by {player.DisplayName}`)
	end
end

local ACTION_TEXT: { [string]: string } = {
	TooFar = "Both players must stand at the Trade Station",
	Busy = "That player is already trading",
	NoInvite = "The invite has expired",
	NotEnough = "Not enough money",
	JustChanged = "The offer just changed - check it first",
}

local function build()
	local site = CollectionService:GetTagged("RecyclerSite")[1]
	local y = if site ~= nil and site:IsA("BasePart") then site.Position.Y - site.Size.Y / 2 else 0.4
	local ground = CFrame.new(0, y, 29)
	local model = Instance.new("Model")
	model.Name = "TradeStation"
	local function part(name: string, size: Vector3, offset: CFrame, color: Color3, material: Enum.Material?, shape: Enum.PartType?): Part
		local p = Instance.new("Part")
		p.Name = name
		p.Shape = shape or Enum.PartType.Block
		p.Size = size
		p.CFrame = ground * offset
		p.Color = color
		p.Material = material or Enum.Material.SmoothPlastic
		p.Anchored = true
		p.TopSurface = Enum.SurfaceType.Smooth
		p.BottomSurface = Enum.SurfaceType.Smooth
		p.Parent = model
		return p
	end
	local ink, orange, teal, steel = Color3.fromRGB(44, 56, 82), Color3.fromRGB(255, 150, 30), Color3.fromRGB(36, 188, 186), Color3.fromRGB(176, 188, 204)
	part("Base", Vector3.new(18, 0.5, 8), CFrame.new(0, 0.25, 0), ink)
	for _, x in { -6, 6 } do
		local color = if x < 0 then orange else teal
		part("Pad", Vector3.new(0.3, 5, 5), CFrame.new(x, 0.6, 0) * CFrame.Angles(0, 0, math.rad(90)), color, nil, Enum.PartType.Cylinder)
		part("Tube", Vector3.new(0.8, 7, 0.8), CFrame.new(x, 4, 3.2), steel, Enum.Material.Metal)
		part("Lamp", Vector3.new(1.4, 1.4, 1.4), CFrame.new(x, 8, 3.2), color, Enum.Material.Neon, Enum.PartType.Ball)
	end
	local console = part("Console", Vector3.new(4, 3.4, 2), CFrame.new(0, 2.2, 0), steel, Enum.Material.Metal)
	part("Screen", Vector3.new(3.2, 1.6, 0.3), CFrame.new(0, 4.4, 0.2) * CFrame.Angles(math.rad(-20), 0, 0), teal, Enum.Material.Neon)
	part("Beam", Vector3.new(12.8, 0.6, 0.6), CFrame.new(0, 7.2, 3.2), steel, Enum.Material.Metal)
	local sign = part("Sign", Vector3.new(11, 2.4, 0.5), CFrame.new(0, 9, 3.2), ink)
	for _, face in { Enum.NormalId.Front, Enum.NormalId.Back } do
		local gui = Instance.new("SurfaceGui")
		gui.Face = face
		gui.CanvasSize = Vector2.new(440, 96)
		gui.LightInfluence = 0
		local label = Instance.new("TextLabel")
		label.Size = UDim2.fromScale(1, 1)
		label.BackgroundTransparency = 1
		label.Font = Enum.Font.FredokaOne
		label.Text = "TRADE STATION"
		label.TextColor3 = Color3.fromRGB(255, 210, 60)
		label.TextScaled = true
		label.Parent = gui
		gui.Parent = sign
	end
	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = "TradePrompt"
	prompt.ActionText = "Trade with a player"
	prompt.ObjectText = "Trade Station"
	prompt.KeyboardKeyCode = GameConfig.Input.MachineKey
	prompt.GamepadKeyCode = GameConfig.Input.MachineGamepadKey
	prompt.HoldDuration = 0
	prompt.RequiresLineOfSight = false
	prompt.MaxActivationDistance = 12
	prompt.Style = Enum.ProximityPromptStyle.Custom
	prompt:SetAttribute("PromptKind", "Trade")
	prompt.Parent = console
	model.Parent = Workspace
	anchor = console
end

function TradeService.Start()
	assert(not started, "[TradeService] Start() called twice")
	started = true
	build()
	RemoteGuard.ConnectEvent(Remotes.GetEvent("TradeAction"), {
		Name = "TradeAction",
		MaxArgs = 3,
		RateLimit = GameConfig.RateLimits.TradeAction,
		Validate = function(action: any): boolean
			return Validate.IsString(action, 1, 12)
		end,
	}, function(player: Player, action: string, a: any, b: any)
		local ok, code = true, nil :: string?
		if action == "Invite" or action == "Accept" then
			local other = if type(a) == "number" then Players:GetPlayerByUserId(a) else nil
			if other == nil then
				return
			end
			if action == "Invite" then
				ok, code = TradeService.Invite(player, other)
				if ok then
					EconomyService.Message(player, `Invite sent to {other.DisplayName}`, "Info")
				end
			else
				ok, code = TradeService.Accept(player, other)
			end
		elseif action == "Offer" then
			ok, code = TradeService.SetOffer(player, a, b)
		elseif action == "Ready" then
			ok, code = TradeService.SetReady(player, a == true)
		elseif action == "Cancel" then
			TradeService.Cancel(player)
		end
		if not ok and code ~= nil and ACTION_TEXT[code] ~= nil then
			EconomyService.Message(player, ACTION_TEXT[code], "Warning")
		end
	end)
	Players.PlayerRemoving:Connect(function(player: Player)
		TradeService.Cancel(player)
		invites[player] = nil
		for _, from in invites do
			from[player] = nil
		end
	end)
	task.spawn(function()
		while true do
			task.wait(1)
			for player, session in sessions do
				if not TradeService.IsNear(player) then
					close(session, FAIL_TEXT.TooFar)
					break -- the table changed; the rest is checked in a second
				end
			end
		end
	end)
end

return TradeService
