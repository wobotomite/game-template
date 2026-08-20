local ReplicatedStorage = game:GetService "ReplicatedStorage"
local RunService = game:GetService "RunService"
local ServerScriptService = game:GetService "ServerScriptService"
local SoundService = game:GetService "SoundService"
local Debris = game:GetService "Debris"

local charm = require(ReplicatedStorage.Packages.charm)
local synced_time = require(ReplicatedStorage.Util.numbers["synced-time"])

export type alert_type = { message: string, timestamp: number }
local alert_atom = charm.atom<<alert_type?>>()

local function play_sound(sound_id: string)
	local s = Instance.new "Sound"
	s.SoundId = sound_id
	s.RollOffMode = Enum.RollOffMode.InverseTapered
	SoundService:PlayLocalSound(s)
	Debris:AddItem(s, 10)
end

function client(message: string, sound_id: string?)
	assert(RunService:IsClient(), "CLIENT ALERTS ARE ONLY AVAILABLE ON THE CLIENT!")
	alert_atom {
		message = message,
		timestamp = synced_time(),
	}
	if sound_id then
		play_sound(sound_id)
	end
end

if RunService:IsServer() then
	local network = require(ServerScriptService.Server["server-network"])
	function send_to(p: Player, message: string, sound_id: string?)
		network.core.send_alert:fire(p, {
			message = message,
			sound = sound_id,
		})
	end
	function send_to_all(message: string, sound_id: string?)
		network.core.send_alert:fire_all {
			message = message,
			sound = sound_id,
		}
	end
else
	local network = require(ReplicatedStorage.Client["client-network"])
	network.core.send_alert:connect(function(a0: {} & { message: string, sound: string? })
		client(a0.message, a0.sound)
	end)
end

return table.freeze {
	client = client,
	send_to = send_to,
	send_to_all = send_to_all,
	alert_atom = alert_atom,
}
