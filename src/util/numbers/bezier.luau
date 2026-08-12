type BezierValue = number | Vector3 | Vector2 | CFrame

@native
function quad<T>(t: number, p0: T & BezierValue, p1: T & BezierValue, p2: T & BezierValue): T
	return (1 - t) ^ 2 * p0 + 2 * (1 - t) * t * p1 + t ^ 2 * p2
end

return table.freeze {
	quad = quad,
}
