--!strict
--[[
	Menus: only one menu at a time. A menu calls Opened(close) when it opens; the one that was
	open before is closed. `close` must do nothing when its menu is already closed.
	Reward cards and upgrade reveals are no menus: they lie on top of whatever is open.
]]

local Menus = {}

local current: (() -> ())? = nil

function Menus.Opened(close: () -> ())
	local before = current
	current = close -- first, so a menu that reacts to the closing cannot loop
	if before ~= nil and before ~= close then
		before()
	end
end

return Menus
