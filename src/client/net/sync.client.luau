const ReplicatedStorage = game:GetService "ReplicatedStorage"

const charm_sync = require(ReplicatedStorage.Packages["charm-sync"])
const sync_registry = require(ReplicatedStorage.Shared.services["sync-registry"])
const client_network = require(script.Parent["client-network"])

-- Retry cadence for the snapshot request. The first gap is deliberately longer
-- than sync.server's REQUEST_COOLDOWN (1s) so a retry is never debounced away
-- by the very attach it is chasing.
const RETRY_MIN = 1.5
const RETRY_MAX = 8
const WARN_AFTER = 15

-- True once the server has sent us anything at all: proof it heard the
-- request. Until then the handshake is not done, whatever we think we sent.
local acked = false

client_network.charm.sync:connect(function(payload)
	acked = true
	charm_sync.client.patch(payload)
end)

-- Ask the server for a full snapshot once local listeners have registered.
-- Debounced: if a feature module registers an atom later, we re-request so its
-- initial state is never missed.
local request_queued = false
local function queue_request()
	if request_queued then
		return
	end
	request_queued = true
	task.defer(function()
		request_queued = false
		client_network.charm.request_sync:fire(nil)
	end)
end

sync_registry.set_late_register_hook(queue_request)
queue_request()

-- The request is one shot with no delivery guarantee: sendbufs drops an event
-- that lands before its server-side handler exists (its reader skips ids with
-- no listeners — there is no queue), and server boot order is not fixed.
-- A place script that creates the remotes and then yields — the run
-- orchestrator requires server-network and then builds rooms, the datastore
-- module probes the API — can leave sync.server unconnected for exactly the
-- frames the client needs to ask. Losing that one event used to strand the
-- client forever: no data atom, so wait-for-loaded never returns and nothing
-- ever errors. Keep asking until a payload proves otherwise.
task.spawn(function()
	local wait_for = RETRY_MIN
	local waited = 0
	local warned = false
	local fire_warned = false
	while not acked do
		task.wait(wait_for)
		if acked then
			break
		end
		waited += wait_for
		if waited >= WARN_AFTER and not warned then
			warned = true
			-- Silence here is the worst outcome — say something before the
			-- player has spent a quarter minute staring at a loading screen.
			warn "[sync] no snapshot from the server yet — still asking"
		end
		-- pcall, because THIS LOOP IS THE RECOVERY PATH described above. If the
		-- fire itself throws -- a stale remote, a mid-boot race -- an unguarded
		-- throw kills this thread and re-creates the exact strand the loop
		-- exists to prevent: no data atom, wait_for_loaded never returns, and
		-- nothing errors again after the first one. Guarded so a bad attempt
		-- costs one interval instead of the session.
		const sent, err = pcall(function()
			client_network.charm.request_sync:fire(nil)
		end)
		if not sent and not fire_warned then
			fire_warned = true
			warn(`[sync] request_sync failed to send: {err}`)
		end
		wait_for = math.min(wait_for * 2, RETRY_MAX)
	end
end)
