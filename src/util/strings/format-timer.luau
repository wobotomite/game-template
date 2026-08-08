@native
function format_timer(value: number): string
	return string.format("%02i:%02i", (value // 60) % 60, value % 60)
end

return format_timer
