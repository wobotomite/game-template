const ReplicatedStorage = game:GetService "ReplicatedStorage"

const vide = require(ReplicatedStorage.Packages.vide)
export type UsedAs<T> = T | () -> T
export type function InferProperties(t: type)
	return t:parameters().head[1]
end

export type VideProperties<T> = InferProperties<typeof(vide.create<<T>>(...))>
return nil
