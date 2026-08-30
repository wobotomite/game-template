return @native function<K, V>(t: { [K]: V }, filter: (V, K) -> boolean)
	local nt = {}
	for i, v in t do
		if filter(v, i) then
			nt[i] = v
		end
	end
	return nt
end
