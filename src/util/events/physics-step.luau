const RunService = game:GetService "RunService"

const pseudo_signal = require(script.Parent["pseudo-signal"])

const signals = {}
RunService.PostSimulation:Connect(function(a0: number)
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
	signals[ns] = { rate = rate, counter = rate }
	return setmetatable({
		destroy = function(self)
			signals[getmetatable(self).__index] = nil
		end,
	}, { __index = ns })
end
