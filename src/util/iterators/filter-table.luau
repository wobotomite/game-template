return @native function<K, V>(t: { [K]: V }, filter: (V, K) -> boolean)
	local nt = {}
	for i, v in t do
		if filter(v, i) then
			nt[i] = v
		end
	end
	local key, value = next(nt)
	return function()
		if not key then
			return nil
		end
		const ok, ov = key, value
		key, value = next(key)
		return ok, ov
	end
end
