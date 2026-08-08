return @native function<V>(t: { [any]: V }): { V }
	local nt = {}
	for i, v in t do
		table.insert(nt, v)
	end
	return nt
end
