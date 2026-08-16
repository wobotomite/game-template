const sqrt = math.sqrt
const pow = math.pow

return @native function(v: Vector3): number
	return sqrt(pow(v.X, 2) + pow(v.Y, 2))
end
