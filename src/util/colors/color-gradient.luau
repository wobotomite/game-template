return @native function(c1: Color3, c2: Color3?, mix: number?)
	if not c2 then
		return ColorSequence.new(c1)
	end
	-- Strictly inside (0, 1): a keypoint AT 0 duplicates the first one and at 1
	-- the last, and ColorSequence.new throws on two keypoints sharing a time.
	mix = math.clamp(mix or 1, 0.001, 0.999)
	return ColorSequence.new {
		ColorSequenceKeypoint.new(0, c1),
		ColorSequenceKeypoint.new(mix, c1),
		ColorSequenceKeypoint.new(1, c2),
	}
end
