return @native function<K, V, NV, NK>(t: { [K]: V }, map: (V, K) -> (NV, NK?))
	local nt = {}
	for i, v in t do
		local nv, nk = map(v, i)
		nk = nk or i
		nt[nk] = nv
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
