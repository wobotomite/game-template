@native
function to_minutes(n: number)
	return (n // 60) % 60
end
@native
function to_hours(n: number)
	return n // 60 // 60
end
@native
function to_seconds(n: number)
	return n % 60
end

return table.freeze {
	to_minutes = to_minutes,
	to_hours = to_hours,
	to_seconds = to_seconds,
}
