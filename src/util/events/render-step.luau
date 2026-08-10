const RunService = game:GetService "RunService"

const pseudo_signal = require(script.Parent["pseudo-signal"])

const signals = setmetatable({}, { __mode = "k" })
RunService.RenderStepped:Connect(function(a0: number)
	for signal, data in signals do
		data.counter += a0
		if data.counter > data.rate then
			const c = data.counter
			data.counter = 0
			signal:fire(c)
		end
	end
end)

return function(rate: number)
	const ns = pseudo_signal.new<<number>>()
	signals[ns] = { rate = rate, counter = 0 }
	return ns
end
