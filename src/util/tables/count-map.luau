return @native function(t: { [any]: any })
	local c = 0
	for i, v in t do
		c += 1
	end
	return c
end
