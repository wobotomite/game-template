@native
function is_within_bounds(point: Vector3, bound_cframe: CFrame, bound_size: Vector3): boolean
	const local_point = bound_cframe:PointToObjectSpace(point)

	local half_x = bound_size.X / 2
	local half_y = bound_size.Y / 2
	local half_z = bound_size.Z / 2

	return math.abs(local_point.X) <= half_x and math.abs(local_point.Y) <= half_y and math.abs(local_point.Z) <= half_z
end

return is_within_bounds
