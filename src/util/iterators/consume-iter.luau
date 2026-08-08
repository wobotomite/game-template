return @native function<T>(iter: () -> T?)
	local a: { T } = {}
	for v in iter do
		table.insert(a, v)
	end
	return a
end
