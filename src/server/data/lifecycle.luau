const ReplicatedStorage = game:GetService "ReplicatedStorage"

const player_data = require(ReplicatedStorage.Shared.services["player-data"])
const observe_players = require(ReplicatedStorage.Util.observers["observe-players"])

const datastore = require(script.Parent.datastore)

-- `player-data` declares a different set of functions per realm, so every one
-- of them is optional as far as the analyzer is concerned. This file only ever
-- runs on the server, where `clear` is always there; the cast says so once
-- rather than leaving a "could be nil" on the call.
const clear_data = player_data.clear :: (Player) -> ()

-- The save's lifecycle: load on join, publish, unload on leave, close on
-- shutdown -- and the one place that says when a player's data is ready.
--
-- WHY A MODULE AND NOT JUST THE SCRIPT. Services need to run something the
-- moment a player's profile is in memory (hand out badges already earned, apply
-- what a game pass unlocked, mount a UI from saved settings). Two shapes were
-- possible: this module requires each of them and calls them in order, or each
-- of them registers a callback here. The registry wins because the list of
-- things a GAME wants to do on load is unknowable from a template, and because
-- the alternative makes this file require half the server -- every one of those
-- requires then runs at boot whether the game uses the service or not.
--
-- `data-lifecycle.server.luau` next door is the script that starts it. It is
-- three lines, and it is separate so that this module can be required by the
-- services that register with it; a Script cannot be required at all.

-- Players whose profile is loaded right now.
const loaded: { [Player]: boolean } = {}
const listeners: { (Player) -> () } = {}

-- Registers `callback(player)` to run once per player, once their save is in
-- memory and published through `player-data`.
--
-- ORDER-FREE ON PURPOSE. Roblox does not promise which server Script runs
-- first, so a service that registers after the lifecycle has already loaded
-- somebody would otherwise miss them -- a bug that appears only on a live
-- server with a fast joiner and never in Studio. Registering late therefore
-- REPLAYS: the callback is called immediately for everyone already loaded.
-- Which is also why a callback must be safe to run for a player mid-session,
-- not only at their join.
function on_loaded(callback: (Player) -> ())
	table.insert(listeners, callback)
	for player in loaded do
		task.spawn(callback, player)
	end
end

function announce(player: Player)
	loaded[player] = true
	-- Spawned one thread each: a listener that yields or errors must not stop
	-- the ones after it, and none of them are allowed to delay the join.
	for _, listener in listeners do
		task.spawn(listener, player)
	end
end

local started = false
function start()
	if started then
		return
	end
	started = true

	observe_players(function(player: Player): () -> ()
		datastore
			:load(player)
			:andThen(function()
				-- `observe_players` cleanup has not run, but the player may still
				-- have left during the load; announcing one who is gone would
				-- leave them in `loaded` forever.
				if player.Parent == nil then
					return
				end
				announce(player)
			end)
			:catch(function(err)
				-- Playing without loaded data means nothing saves -- silent
				-- progress loss, which a player only discovers after an hour.
				-- Log it and kick honestly instead (lyra already retried).
				warn(`[data] load failed for {player.Name}: {tostring(err)}`)
				if player.Parent then
					pcall(player.Kick, player, "Your save data couldn't be loaded. Please rejoin!")
				end
			end)

		return function()
			loaded[player] = nil
			clear_data(player)
			-- May already be unloaded (a save-before-teleport releases the
			-- session), and that rejection is not news.
			datastore:unload(player):catch(function() end)
		end
	end)

	game:BindToClose(function()
		-- The last chance to flush every open profile. Roblox gives a server
		-- about thirty seconds here; `closeAsync` yields until lyra has written
		-- what it holds, and the pcall is because an error thrown inside
		-- BindToClose would abandon the rest of the shutdown.
		const ok, err = pcall(function()
			datastore:closeAsync()
		end)
		if not ok then
			warn(`[data] close failed: {tostring(err)}`)
		end
	end)
end

return table.freeze {
	start = start,
	on_loaded = on_loaded,
}
