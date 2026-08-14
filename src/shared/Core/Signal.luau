--!strict
--[[
	Signal.luau

	Minimal typed event emitter for in-process communication between services.
	Deliberately not a BindableEvent: BindableEvents serialise their arguments,
	which loses table identity and Instance references we care about.

	Handlers run in their own coroutine so one throwing handler cannot stop the
	others from firing.
]]

local Signal = {}
Signal.__index = Signal

export type Connection = {
	connected: boolean,
	disconnect: (Connection) -> (),
}

type Handler = (...any) -> ()

export type Signal = typeof(setmetatable(
	{} :: {
		_handlers: { { fn: Handler, conn: Connection } },
	},
	Signal
))

function Signal.new(): Signal
	return setmetatable({ _handlers = {} }, Signal)
end

function Signal.connect(self: Signal, fn: Handler): Connection
	local conn: Connection
	conn = {
		connected = true,
		disconnect = function(c: Connection)
			if not c.connected then
				return
			end
			c.connected = false
			for i, entry in self._handlers do
				if entry.conn == c then
					table.remove(self._handlers, i)
					break
				end
			end
		end,
	}
	table.insert(self._handlers, { fn = fn, conn = conn })
	return conn
end

--- Fires once, then disconnects itself.
function Signal.once(self: Signal, fn: Handler): Connection
	local conn
	conn = self:connect(function(...)
		conn:disconnect()
		fn(...)
	end)
	return conn
end

function Signal.fire(self: Signal, ...: any)
	-- Iterate a copy: handlers are allowed to disconnect during dispatch.
	local snapshot = table.clone(self._handlers)
	for _, entry in snapshot do
		if entry.conn.connected then
			task.spawn(entry.fn, ...)
		end
	end
end

function Signal.destroy(self: Signal)
	for _, entry in self._handlers do
		entry.conn.connected = false
	end
	table.clear(self._handlers)
end

return Signal
