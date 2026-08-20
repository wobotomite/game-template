const ReplicatedStorage = game:GetService "ReplicatedStorage"
const RunService = game:GetService "RunService"

const extend_object = require(ReplicatedStorage.Util.tables["extend-object"])
const pseudo_signal = require(script.Parent["pseudo-signal"])

const signals = {}
RunService.RenderStepped:Connect(function(a0: number)
	for signal, data in signals do
		data.counter += a0
		if not data.rate or data.counter >= data.rate then
			const c = data.counter
			data.counter = 0
			signal:fire(c)
		end
	end
end)

return function(rate: number?)
	const ns = pseudo_signal.new<<number>>()
	signals[ns] = { rate = rate, counter = rate or 0 }

	return extend_object(ns, {
		destroy = function(self)
			signals[getmetatable(self).__index] = nil
		end,
	})
end
