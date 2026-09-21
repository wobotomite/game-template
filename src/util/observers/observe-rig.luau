const __create_observer = require(script.Parent["__create-observer"])
const observe_character = require(script.Parent["observe-character"])

-- A resolver that publishes a player's rig -- character, root, head, humanoid
-- -- and re-publishes it as those parts appear.
--
--   const rig = observe_rig(player)
--   rig.changed(function(r) ... end)
--   const root = rig.get().root
--
-- WHY THIS EXISTS, AND WHY `observe-character` IS NOT ENOUGH. On the client,
-- `CharacterAdded` can fire with an EMPTY model. The character is parented
-- first and its parts stream in afterwards, so anything that reads
-- `HumanoidRootPart` at CharacterAdded time reads NIL -- not always, but
-- reliably under load, on a slow join, or with instance streaming on, which is
-- exactly when nobody is watching. The usual patch is a `WaitForChild` inside
-- the callback, which yields the observer's own thread and then holds a
-- reference to a character the player may already have left.
--
-- So this listens to ChildAdded/ChildRemoved on the character and resolves
-- again each time. A consumer gets a rig with `root = nil` first and a complete
-- one a moment later, and is expected to handle both -- which is the honest
-- shape, because that is what the client actually sees.
--
-- Publishes are DE-DUPED on the four fields: a character with a dozen parts
-- fires ChildAdded a dozen times and only the ones that change the rig reach a
-- listener. The rig tables are frozen so a consumer can hold one across frames
-- and compare it by identity.

export type Rig = {
	character: Model?,
	root: BasePart?,
	head: BasePart?,
	humanoid: Humanoid?,
}

export type Resolver = {
	get: () -> Rig,
	changed: (listener: (Rig) -> ()) -> __create_observer.Cleanup,
	destroy: __create_observer.Cleanup,
}

-- One shared empty rig, so "no character" compares equal to itself and the
-- de-dupe above suppresses a repeated teardown publish.
const EMPTY: Rig = table.freeze {}

@native
function observe_rig(player: Player): Resolver
	local rig: Rig = EMPTY
	local listeners: { (Rig) -> () } = {}

	const function publish(next_rig: Rig)
		if
			next_rig.character == rig.character
			and next_rig.root == rig.root
			and next_rig.head == rig.head
			and next_rig.humanoid == rig.humanoid
		then
			return
		end
		rig = next_rig
		-- Cloned: a listener is allowed to unsubscribe itself from inside the
		-- callback, and removing from the array being walked would skip its
		-- neighbour.
		for i, listener in table.clone(listeners) do
			listener(next_rig)
		end
	end

	const stop = observe_character(player, function(character: Model): __create_observer.Cleanup
		const function resolve()
			const root = character:FindFirstChild "HumanoidRootPart"
			const head = character:FindFirstChild "Head"
			publish(table.freeze {
				character = character,
				-- `IsA` rather than a cast: a Model can carry a non-part child
				-- named HumanoidRootPart, and asserting the type away would
				-- move the failure to whoever reads `.Position`.
				root = if root and root:IsA "BasePart" then root else nil,
				head = if head and head:IsA "BasePart" then head else nil,
				humanoid = character:FindFirstChildOfClass "Humanoid",
			})
		end

		const added = character.ChildAdded:Connect(resolve)
		const removed = character.ChildRemoved:Connect(resolve)
		resolve()

		return function()
			added:Disconnect()
			removed:Disconnect()
			publish(EMPTY)
		end
	end)

	const function get(): Rig
		return rig
	end

	const function changed(listener: (Rig) -> ()): __create_observer.Cleanup
		table.insert(listeners, listener)
		return function()
			const at = table.find(listeners, listener)
			if at then
				table.remove(listeners, at)
			end
		end
	end

	const function destroy()
		-- Listeners first. `stop()` runs the character cleanup above, which
		-- publishes EMPTY -- and with the listeners still attached, destroying an
		-- observer fired every one of them a last time, into consumers that were
		-- mid-teardown themselves.
		table.clear(listeners)
		stop()
	end

	return table.freeze {
		get = get,
		changed = changed,
		destroy = destroy,
	}
end

return observe_rig
