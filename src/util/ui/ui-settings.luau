local FONTS = {
	DEFAULT = Font.fromEnum(Enum.Font.BuilderSansMedium),
	BOLD = Font.fromEnum(Enum.Font.BuilderSansBold),
	BLACK = Font.fromEnum(Enum.Font.BuilderSansExtraBold),
}

local COLORS = {
	WHITE = Color3.new(1, 1, 1),
	BLACK = Color3.new(0, 0, 0),
}

local NUMBERS = {
	PADDING = 8,
	FONT_LARGE = 24,
	FONT_MEDIUM = 18,
	FONT_SMALL = 14,
}

return table.freeze {
	FONTS = table.freeze(FONTS),
	COLORS = table.freeze(COLORS),
	NUMBERS = table.freeze(NUMBERS),
}
