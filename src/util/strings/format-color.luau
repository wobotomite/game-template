local floor = math.floor

return function(text: string, color: Color3)
	local r = floor(color.R * 255)
	local g = floor(color.G * 255)
	local b = floor(color.B * 255)
	local color_string = `rgb({r},{g},{b})`
	return `<font color="{color_string}">{text}</font>`
end
