local ReplicatedStorage = game:GetService "ReplicatedStorage"

local ui_types = require(ReplicatedStorage.Util.ui["ui-types"])
local vide = require(ReplicatedStorage.Packages.vide)

return function(c0: ui_types.UsedAs<Color3>, c1: ui_types.UsedAs<Color3>, v: ui_types.UsedAs<number>)
	return function()
		local clr0 = vide.read(c0)
		local clr1 = vide.read(c1)
		local read_val = vide.read(v)
		return ColorSequence.new {
			ColorSequenceKeypoint.new(0, clr0),
			ColorSequenceKeypoint.new(math.clamp(read_val, 0.001, 0.998), clr0),
			ColorSequenceKeypoint.new(math.clamp(read_val + 0.001, 0.002, 0.999), clr1),
			ColorSequenceKeypoint.new(1, clr1),
		}
	end
end
