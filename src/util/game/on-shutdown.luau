const Players = game:GetService "Players"
const RunService = game:GetService "RunService"

-- Run something when this realm is going away.
--
--   const on_shutdown = require(ReplicatedStorage.Util.game["on-shutdown"])
--   on_shutdown(function()
--       save_whatever_has_not_been_saved()
--   end)
--
-- WHAT "GOING AWAY" MEANS IS DIFFERENT PER REALM, and the previous version of
-- this file only implemented one of them. It listened for
-- `Players.PlayerRemoving` and compared against `Players.LocalPlayer` — which
-- is nil on a server, so the comparison was never true and **every callback
-- registered on the server was silently dropped**. A module named
-- `on-shutdown` that never fires on the realm with the shutdown is the wrong
-- way round, and nothing about it would have complained: no error, no warning,
-- just work that never happened.
--
--   client   the local player is leaving (they left, were kicked, or are being
--            teleported).
--   server   `game:BindToClose`, which is the engine's own shutdown hook.
--
-- ON THE SERVER, BindToClose IS A BUDGET, NOT A NOTIFICATION. Roblox waits for
-- the callback, but not indefinitely — roughly 30 seconds, and less in Studio.
-- Callbacks run in parallel here so one slow saver cannot eat the whole budget
-- on behalf of the others, and the whole set is bounded so a callback that
-- hangs cannot hold the server open until the engine kills it mid-write.
const SHUTDOWN_BUDGET = 20 -- seconds; under the engine's own limit, deliberately

const callbacks: { () -> () } = {}

local function run_all()
	for _, callback in callbacks do
		-- Spawned, so one that throws does not take the rest with it, and one
		-- that yields does not delay them.
		task.spawn(function()
			const ok, err = pcall(callback)
			if not ok then
				warn(`[on-shutdown] a callback threw: {err}`)
			end
		end)
	end
end

if RunService:IsServer() then
	game:BindToClose(function()
		const finished = os.clock() + SHUTDOWN_BUDGET
		local remaining = #callbacks
		for _, callback in callbacks do
			task.spawn(function()
				const ok, err = pcall(callback)
				if not ok then
					warn(`[on-shutdown] a callback threw: {err}`)
				end
				remaining -= 1
			end)
		end
		-- Hold the shutdown open until they are done or the budget is spent.
		-- Without the deadline a single hung callback keeps the server alive
		-- until the engine force-closes it, which is exactly when an in-flight
		-- write gets truncated.
		while remaining > 0 and os.clock() < finished do
			task.wait(0.1)
		end
		if remaining > 0 then
			warn(`[on-shutdown] {remaining} callback(s) did not finish within {SHUTDOWN_BUDGET}s`)
		end
	end)
else
	Players.PlayerRemoving:Connect(function(player: Player)
		if player == Players.LocalPlayer then
			run_all()
		end
	end)
end

return function(...: () -> ())
	for _, callback in { ... } do
		table.insert(callbacks, callback)
	end
end
