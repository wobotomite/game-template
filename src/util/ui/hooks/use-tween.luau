const ReplicatedStorage = game:GetService "ReplicatedStorage"

const Ripple = require(ReplicatedStorage.Packages.ripple)
const Vide = require(ReplicatedStorage.Packages.vide)

type Animatable = Ripple.Animatable
type Tween<T> = Ripple.Tween<T>
type TweenOptions<T> = Ripple.TweenOptions<T>

local function use_tween<T>(initialValue: T, initialOptions: (TweenOptions<T> | any)?): (() -> T, Tween<T>)
	local tween = Ripple.createTween(initialValue, initialOptions)
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

return use_tween
