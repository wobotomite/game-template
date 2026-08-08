return @native function(c1: Color3, c2: Color3?, mix: number?)
	if not c2 then
		return ColorSequence.new(c1)
	end
	mix = math.clamp(mix or 1, 0, 0.999)
	return ColorSequence.new {
		ColorSequenceKeypoint.new(0, c1),
		ColorSequenceKeypoint.new(mix, c1),
		ColorSequenceKeypoint.new(1, c2),
	}
end
