@native
function deep_copy<T>(t: T): T
	t = table.clone(t :: any) :: any

	for index: any, value: any in t :: any do
		if typeof(value) == "table" then
			(t :: any)[index] = deep_copy(value)
		end
	end

	return t
end

return deep_copy
