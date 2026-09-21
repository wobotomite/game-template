const fatal = require(script.boot.fatal)

-- Boot, under the fatal handler.
--
-- A bare `require` here is worse than it looks: if the datastore fails to
-- start, THIS script dies and every other server script carries on regardless.
-- The game then runs in a state nobody designed -- players in a live session
-- whose progress cannot be saved, with nothing on screen to say so. Wrapping
-- boot means that failure empties the server instead, honestly.
--
-- THIS LIST IS THE SERVER'S ORDER OF OPERATIONS. Every service is a module with
-- a `start()`, so that "what runs on this server, and in what order" is one
-- readable list rather than a guess assembled from whichever files happened to
-- have side effects at require time. Each `start()` is idempotent, so a game
-- that also starts one from somewhere of its own gets one instance, not two.
--
-- THE TWO EXCEPTIONS, both for the same reason -- something else already has to
-- require the module, so listing it here would suggest this list decided
-- something it did not. Each is started by a one-line Script beside its own
-- module, and each says so in its own header:
--
--   * the save's lifecycle, by `src/server/data/data-lifecycle.server.luau`
--   * the leaderboard workers, by `src/server/leaderboards/leaderboards.server.luau`
--
-- ORDER MATTERS ONLY WHERE A COMMENT SAYS IT DOES. Services that need a
-- player's save register with `lifecycle.on_loaded`, which replays for players
-- already loaded, so a late registration cannot miss anyone.
fatal.guard("server-boot", function()
	-- FIRST, always. Every service below either reads a save or writes one, and
	-- this is what fails when the DataStore API is unreachable -- which is a
	-- failure the whole server should die of, here, rather than one discovered
	-- an hour in when nothing has been saving. The save's own lifecycle (load,
	-- unload, shutdown flush) is started by `data-lifecycle.server.luau`.
	require(script.data.datastore)

	-- COMMERCE. Receipts first: it claims `MarketplaceService.ProcessReceipt`,
	-- and Roblox can deliver a pending receipt the moment a player joins.
	require(script.players.receipts).start()
	require(script.players["pass-service"]).start()
	require(script.players["badge-service"]).start()

	require(script.players["voice-service"]).start()
end)
