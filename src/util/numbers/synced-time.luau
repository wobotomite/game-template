-- -math.huge, NOT 0, so the FIRST call always resyncs.
--
-- At 0 the refresh below is gated on `os.clock() - 0 > SYNC_AFTER`, and
-- os.clock is process uptime -- so for the first six seconds of a server's
-- life the sync never runs and this returns `0 + os.clock()`, i.e. uptime
-- instead of server time. Then the first call past six seconds jumps it by
-- the whole server epoch, about 1.7e9:
--
--     os.clock=1.0 -> 1.0             os.clock=6.1 -> 1756400006.1
--
-- Nothing errors. What breaks is any pair of stamps that straddles the jump,
-- and the game has several: punch.shove writes `shoved_at = synced_time()`
-- and every behavior peel-checks it against ctx.now, which is also
-- synced_time -- so a shove stamped before the first sync reads as
-- 1.7 billion seconds OLDER than a windup started after it, and the peel
-- silently stops firing. run-state's `started_at` has the same shape and
-- yields a nonsense run duration in the results card.
--
-- Whether the first call lands inside that window is pure timing, which is
-- what makes it worth fixing rather than watching: it would reproduce
-- intermittently and look like something else.
local last_synced = -math.huge
local server_time = 0
const SYNC_AFTER = 6 -- seconds

return @native function()
	if os.clock() - last_synced > SYNC_AFTER then
		last_synced = os.clock()
		server_time = workspace:GetServerTimeNow()
	end
	return server_time + (os.clock() - last_synced)
end
