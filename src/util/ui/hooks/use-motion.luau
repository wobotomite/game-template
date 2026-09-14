const ReplicatedStorage = game:GetService "ReplicatedStorage"

const Ripple = require(ReplicatedStorage.Packages.ripple)
const Vide = require(ReplicatedStorage.Packages.vide)

local function use_motion<T>(
	initialValue: T,
	initialOptions: (Ripple.MotionOptions<T> | any)?
): (() -> T, Ripple.Motion<T>)
	local tween = Ripple.createMotion(initialValue, initialOptions)
	local value = Vide.source(initialValue)

	if not (initialOptions and initialOptions.start == false) then
		tween:start()
	end

	local disconnect = tween:onChange(value :: never)

	Vide.cleanup(function()
		disconnect()
		tween:stop()
	end)

	return value, tween
end

return use_motion
