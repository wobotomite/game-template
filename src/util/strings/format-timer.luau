-- MM:SS, with the minutes left to run past 59 -- a 75-minute value reads
-- "75:00". The previous `(value // 60) % 60` wrapped it to "15:00", which is a
-- wrong answer that looks right. Negative input clamps to "00:00": a countdown
-- read one frame after it expired otherwise printed "-1:59".
@native
function format_timer(value: number): string
	const clamped = math.max(value, 0)
	return string.format("%02i:%02i", clamped // 60, clamped % 60)
end

return format_timer
