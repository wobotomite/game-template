return @native function(v: number)
	return NumberSequence.new {
		NumberSequenceKeypoint.new(0, 0),
		NumberSequenceKeypoint.new(math.clamp(v, 0.001, 0.998), 0),
		NumberSequenceKeypoint.new(math.clamp(v + 0.001, 0.002, 0.999), 1),
		NumberSequenceKeypoint.new(1, 1),
	}
end
