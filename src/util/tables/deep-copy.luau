-- `seen` is the memo that makes this safe on a table that reaches itself -- a
-- parent link, a node graph, a record that holds its own registry. Without it
-- the recursion never ends (a stack overflow, not an error you can catch), and
-- a table referenced twice came back as two separate copies, which breaks
-- anything comparing them by identity afterwards. Callers pass one argument;
-- the second is the recursion's own.
@native
function deep_copy<T>(t: T, seen: { [any]: any }?): T
	const memo = seen or {}
	const already = memo[t :: any]
	if already then
		return already
	end

	const copy = table.clone(t :: any)
	memo[t :: any] = copy

	for index: any, value: any in copy :: any do
		if typeof(value) == "table" then
			(copy :: any)[index] = deep_copy(value, memo)
		end
	end

	return copy :: any
end

return deep_copy
