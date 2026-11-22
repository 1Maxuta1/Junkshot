--!strict
--[[
	Signal: minimal event used to decouple modules
	(e.g. CurrencyService.Changed -> ReplicationService).

	Handlers run through task.spawn, so a yielding or erroring handler can neither block nor
	break the code that fired the signal. Errors still print to the Output window.
]]

export type Connection = {
	Connected: boolean,
	Disconnect: (self: Connection) -> (),
}

export type Signal = {
	Connect: (self: Signal, handler: (...any) -> ()) -> Connection,
	Fire: (self: Signal, ...any) -> (),
}

local Signal = {}

function Signal.new(): Signal
	local handlers: { [Connection]: (...any) -> () } = {}

	local signal: Signal = {
		Connect = function(_self: Signal, handler: (...any) -> ()): Connection
			local connection: Connection = {
				Connected = true,
				Disconnect = function(self: Connection)
					self.Connected = false
					handlers[self] = nil
				end,
			}
			handlers[connection] = handler
			return connection
		end,

		Fire = function(_self: Signal, ...: any)
			-- Copy first so handlers may connect/disconnect while we iterate.
			local snapshot = {}
			for _, handler in handlers do
				table.insert(snapshot, handler)
			end
			for _, handler in snapshot do
				task.spawn(handler, ...)
			end
		end,
	}

	return signal
end

return Signal
