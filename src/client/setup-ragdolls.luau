const ReplicatedStorage = game:GetService "ReplicatedStorage"

const observe_character = require(ReplicatedStorage.Util.observers["observe-character"])
const observe_players = require(ReplicatedStorage.Util.observers["observe-players"])
const ragdolls = require(ReplicatedStorage.Util.ragdolls)
observe_players(function(player: Player): () -> ()
	return observe_character(player, function(character: Model): (() -> ())?
		character:WaitForChild("HumanoidRootPart", 30)
		ragdolls.init_ragdoll(character)
	end)
end)
