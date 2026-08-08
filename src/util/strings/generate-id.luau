return @native function(size: number?)
	size = size or 16
	local str = ""
	for i = 1, size do
		const round = bit32.bor((math.random() * 16), 0)
		str ..= ("%X"):format(round)
	end
	return str
end
