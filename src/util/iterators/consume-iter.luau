return @native function<V, K>(iter: () -> (V, K?))
	local a: { [K]: V } = {}
	for k, v in iter do
		a[k] = v
	end
	return a
end
