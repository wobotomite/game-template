local last_synced = 0
local server_time = 0
const SYNC_AFTER = 6 -- seconds

return @native function()
	if os.clock() - last_synced > SYNC_AFTER then
		last_synced = os.clock()
		server_time = workspace:GetServerTimeNow()
	end
	return server_time + (os.clock() - last_synced)
end
