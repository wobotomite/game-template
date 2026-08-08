local fnv1a_hash
do
	const fnv_prime = 16777619
	function fnv1a_hash(s: string)
		local hash = 2166136261
		for i = 1, #s do
			hash = bit32.bxor(hash, string.byte(s, i))
			hash = bit32.band(hash * fnv_prime, 0xFFFFFFFF)
		end
		return string.format("%X", hash)
	end
end
const attribute_name = "__IGNORE_CACHE_SER_ID__"
function serialize_instance(i: Instance)
	const r = i:GetAttribute(attribute_name)
	if r then
		return r
	end
	const uuid = string.gsub("!xxxxxxxxxxxxxxx", "x", function()
		return string.char(math.random(22, 126))
	end)
	i:SetAttribute(attribute_name, uuid)
	return uuid
end
function flatten_table(t: { any })
	local keys = {}
	local values = {}
	const function recurse(t: { any })
		for i, v in t do
			table.insert(keys, i)
			if typeof(v) == "table" then
				recurse(v)
			else
				table.insert(values, serialize(v))
			end
		end
	end
	recurse(t)
	return table.concat(keys) .. table.concat(values)
end

function serialize(t: any)
	if typeof(t) == "table" then
		return flatten_table(t)
	elseif typeof(t) == "Instance" then
		return serialize_instance(t)
	end
	return tostring(t)
end

function hash_entry(...: any)
	local hash = ""
	for i, v in { ... } do
		hash ..= serialize(v)
	end
	return fnv1a_hash(hash)
end

local function deep_copy<T>(original: {} & T)
	local copy = table.clone(original)
	for key, value in original do
		if type(value) == "table" then
			copy[key] = deep_copy(value)
		end
	end
	return copy
end

-- @ ONLY USE FOR DETERMINISTIC FUNCTIONS
function cached<I..., O...>(fn: (I...) -> O..., memorize_for: number?)
	const caches = {}
	return function(...: I...): O...
		const hashed = hash_entry(...)
		const found = caches[hashed]
		if found and (not memorize_for or (os.clock() - found.ran_at) < memorize_for) then
			return unpack(deep_copy(caches[hashed].result))
		end
		const result = { fn(...) }
		caches[hashed] = {
			ran_at = os.clock(),
			result = result,
		}
		return unpack(deep_copy(result))
	end
end

return cached
