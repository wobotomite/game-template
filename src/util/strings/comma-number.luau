@native
function format_number(value: number): string
	local formatted = tostring(value)
	while true do
		local k
		formatted, k = string.gsub(formatted, "^(-?%d+)(%d%d%d)", "%1,%2")
		if k == 0 then
			break
		end
	end
	return formatted
end

return format_number
