return @native function(n: { number })
	local c = 0
	for i = 1, #n do
		c += n[i]
	end
	return c
end
