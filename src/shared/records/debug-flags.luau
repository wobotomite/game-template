const ReplicatedStorage = game:GetService "ReplicatedStorage"

-- Runtime switches for developer tooling. Attributes on ReplicatedStorage, so
-- they can be flipped from the Studio command bar, from a debug menu, or by a
-- server script — without a rebuild and without a restart.
--
--   game:GetService("ReplicatedStorage"):SetAttribute("DebugDraw", true)
--
-- WHY AN ATTRIBUTE AND NOT `RunService:IsStudio()`. A build-time constant is
-- decided once, at require time, and answers the wrong question. `IsStudio` is
-- true for every Studio session including the ones where you are testing
-- something unrelated and do not want the screen covered in wireframes, and
-- false in the live server where you have an actual reproduction in front of
-- you. An attribute is per-session, live-toggleable, and can be turned on for
-- one client without touching anyone else.
--
-- WHY ReplicatedStorage. Attributes there replicate server → client, so setting
-- one on the server turns the tooling on for everybody at once; a client can
-- also set it locally for itself, and that local write simply never leaves that
-- machine. Both are useful and neither needs a remote.
--
-- These default to OFF. Anything reading them must be free when they are off —
-- a debug feature that costs frame time in production is a debug feature that
-- gets deleted.

-- Wireframe debug drawing: util/debug/gizmos consults this on every call.
const DEBUG_DRAW = "DebugDraw"

function is_on(flag: string): boolean
	return ReplicatedStorage:GetAttribute(flag) == true
end

function set(flag: string, on: boolean)
	ReplicatedStorage:SetAttribute(flag, on)
end

-- Fires whenever the flag changes. Returns a disconnect.
function on_changed(flag: string, callback: (boolean) -> ()): () -> ()
	const connection = ReplicatedStorage:GetAttributeChangedSignal(flag):Connect(function()
		callback(is_on(flag))
	end)
	return function()
		connection:Disconnect()
	end
end

return table.freeze {
	DEBUG_DRAW = DEBUG_DRAW,

	is_on = is_on,
	set = set,
	on_changed = on_changed,

	-- Convenience for the common one.
	draw_enabled = function(): boolean
		return is_on(DEBUG_DRAW)
	end,
}
