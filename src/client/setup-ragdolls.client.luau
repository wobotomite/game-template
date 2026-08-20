const ReplicatedStorage = game:GetService "ReplicatedStorage"

const observe_character = require(ReplicatedStorage.Util.observers["observe-character"])
const observe_players = require(ReplicatedStorage.Util.observers["observe-players"])
const ragdolls = require(ReplicatedStorage.Util.ragdolls)

const wl = {
	[Enum.HumanoidStateType.Dead] = true,
	[Enum.HumanoidStateType.Physics] = true,
}

observe_players(function(player: Player): () -> ()
	return observe_character(player, function(character: Model): (() -> ())?
		const root = character:WaitForChild("HumanoidRootPart", 30) :: BasePart
		const hum = character:WaitForChild("Humanoid", 30) :: Humanoid
		ragdolls.init_ragdoll(character)

		hum.StateChanged:Connect(function(old: Enum.HumanoidStateType, new: Enum.HumanoidStateType)
			if wl[new] then
				root:ApplyAngularImpulse(Vector3.new(90, 0, 0))
				ragdolls.set_ragdoll(character, true)
			elseif wl[old] then
				ragdolls.set_ragdoll(character, false)
			end
		end)
	end)
end)
