-- makes a ref strong; prevents gcing.

const refs = {}

return function<T>(a: T): T
	refs[a] = true
	return a
end
