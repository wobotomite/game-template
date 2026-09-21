const ReplicatedStorage = game:GetService "ReplicatedStorage"

const sendbufs = require(ReplicatedStorage.Packages.sendbufs)
const network = require(ReplicatedStorage.Shared.network)

-- The three instances sendbufs parents into ReplicatedStorage for its own
-- transport. They are created by `create_server` below, and they are the whole
-- of the wire: the client binds to them BY NAME with `WaitForChild`, which
-- returns the FIRST match.
const STRAY_REMOTE_NAMES = { "_SB_RELIABLE", "_SB_UNRELIABLE", "_SB_FUNCTION" }

-- Destroy any that are already here before making ours.
--
-- `create_server` parents its three with NO dedupe, so a set left behind by an
-- earlier session is not replaced -- it is joined. Studio is where this
-- happens: anything that runs `create_server` in Edit mode (a plugin, the
-- command bar, a scratch script) leaves a set in the place file, which is then
-- SAVED, and every later Play session starts with two. The client's
-- WaitForChild picks the stale one, the server sends down the new one, and the
-- symptom is the whole game loading with no data and no error -- no snapshot
-- ever arrives, panels never mount, and nothing in the log says why.
--
-- Rojo does not own these instances, so it will never clean them up for you.
-- This runs on every boot as the backstop; it is not a licence to create them
-- outside this file.
for _, child in ReplicatedStorage:GetChildren() do
	if table.find(STRAY_REMOTE_NAMES, child.Name) then
		warn(`[server-network] destroying stray {child.ClassName} "{child.Name}" in ReplicatedStorage`)
		child:Destroy()
	end
end

return sendbufs.create_server(network, 4096)
