type function union_from_components(input: { type })
	local input_len = #input
	return if input_len == 0 then nil elseif input_len == 1 then input[1] else types.unionof(table.unpack(input))
end

type function MakeIndexableConstTable(input: type): type
	assert(input.tag == "table", "`input` must be table.")

	local indexer = input:indexer()
	local indexer_result = if indexer then { indexer.readresult } else {}

	for key, value in input:properties() do
		local result = value.read or value.write
		if not result then
			continue
		end

		table.insert(indexer_result, result)
	end

	input:setindexer(types.unionof(types.string, types.number), union_from_components(indexer_result) or types.never)

	return input
end

return table.freeze :: <T>(t: T & {}) -> MakeIndexableConstTable<T>
