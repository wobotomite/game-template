return function(rate: number)
	-- "Never", so the FIRST call passes. Seeded with `os.clock()` the throttle
	-- swallowed the first event of every burst -- the first footstep, the first
	-- hit sound -- and only let the second one through a period later.
	local clock = -math.huge
	return function(): boolean
		if os.clock() - clock > rate then
			clock = os.clock()
			return true
		end
		return false
	end
end
