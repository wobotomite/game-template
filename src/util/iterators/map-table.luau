return @native function<K, V, NV, NK>(t: { [K]: V }, map: (V, K) -> (NV, NK?))
	local nt = {}
	for k, v in t do
		local nv, nk = map(v, k)
		nk = nk or k
		nt[nk] = nv
	end
	return nt
end
