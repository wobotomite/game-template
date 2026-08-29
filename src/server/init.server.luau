const fatal = require(script.boot.fatal)

-- Boot, under the fatal handler.
--
-- A bare `require` here is worse than it looks: if the datastore fails to
-- start, THIS script dies and every other server script carries on regardless.
-- The game then runs in a state nobody designed -- players in a live session
-- whose progress cannot be saved, with nothing on screen to say so. Wrapping
-- boot means that failure empties the server instead, honestly.
fatal.guard("server-boot", function()
	require(script.data.datastore)
end)

print "Hello world, from server!"
