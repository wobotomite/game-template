const Players = game:GetService "Players"
const ReplicatedStorage = game:GetService "ReplicatedStorage"

const voice = require(ReplicatedStorage.Shared.settings).voice

-- One `AudioDeviceInput` per player: the new-audio-API form of voice chat.
--
-- WHY A SERVER SCRIPT AT ALL. With `UseAudioApi = "Enabled"` and
-- `EnableDefaultVoice = false` in `default.project.json`, the engine stops
-- building the voice graph for you, and a player with no `AudioDeviceInput`
-- simply has no microphone. In exchange, the wiring is ordinary instances: the
-- input can be routed through an `AudioFader`, an emitter positioned in the
-- world, a proximity filter -- none of which the default graph allows.
--
-- The input is parented to the PLAYER, not the character, so it survives death
-- and respawn. A game that wants positional voice adds an `AudioEmitter` on the
-- character and wires it with an `AudioDeviceInput.Player` -> emitter
-- `Wire`; the input this file creates is the source end of that.
--
-- IT DOES NOT GRANT VOICE. Whether a player can speak is their account's
-- verified-age setting and the experience's voice permission on the dashboard;
-- with voice off, this input exists and stays silent, which is harmless.

function attach(player: Player)
	-- Idempotent: `observe`-style callers and the join handler can both run for
	-- the same player, and two inputs on one player is a doubled voice.
	if player.Parent ~= Players or player:FindFirstChildOfClass "AudioDeviceInput" then
		return
	end
	const input = Instance.new "AudioDeviceInput"
	input.Name = voice.INPUT_NAME
	input.Player = player
	input.Parent = player
end

local started = false
function start()
	if started then
		return
	end
	started = true

	Players.PlayerAdded:Connect(attach)
	-- The loop after the connect, not before: a player who joins between the two
	-- is caught by one or the other, and `attach` makes the overlap harmless.
	for _, player in Players:GetPlayers() do
		attach(player)
	end
end

return table.freeze {
	start = start,
	attach = attach,
}
