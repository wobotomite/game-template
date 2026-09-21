const RunService = game:GetService "RunService"

-- Studio-only developer commands, and the two ways to reach them: the debug
-- menu (through the `debug` group in `src/shared/network.luau`) and a
-- BindableFunction that external tooling can invoke.
--
-- THE WHOLE FILE IS BEHIND THIS RETURN. Not a flag, not a check inside each
-- handler: a published server never runs a line of it, never parents the
-- bridge, and never connects the remote -- and the remote itself does not exist
-- there either, because that group of the wire is Studio-only too. Three
-- independent gates on the same thing, and that is deliberate. The cost of a
-- forgotten one is a shipped `wipe_data` any client can fire.
if not RunService:IsStudio() then
	return
end

const ReplicatedStorage = game:GetService "ReplicatedStorage"
const ServerScriptService = game:GetService "ServerScriptService"
const Players = game:GetService "Players"

const place_context = require(ReplicatedStorage.Shared["place-context"])
const alert = require(ReplicatedStorage.Shared.services.alert)
const settings = require(ReplicatedStorage.Shared.settings)
const strings = require(ReplicatedStorage.Shared.strings)
const datastore_template = require(ReplicatedStorage.Shared.datastore["datastore-template"])
const observe_players = require(ReplicatedStorage.Util.observers["observe-players"])
const datastore = require(ServerScriptService.Server.data.datastore)
const server_network = require(ServerScriptService.Server.net["server-network"])

const S = strings.debug
const DEBUG = settings.debug

-- Every command that touches the save goes through here, because a debug
-- command that writes to a player's data has three ways to go wrong and all of
-- them are silent: the write can fail (Studio API access off is the usual one),
-- the player can leave mid-write, or the change can land and the client never
-- hear about it.
--
--   * `task.spawn`, so a command never yields the caller -- the remote handler
--     and the bridge both want to return straight away, and the bridge's
--     invoker would otherwise block on a DataStore round trip.
--   * `pcall`, because updateAsync throws on a rejected write and this is a
--     Script: an error here kills the rest of the file, including the bridge.
--   * `player.Parent` checked AFTER the write, because the write yields and the
--     player may be gone by the time it returns. Alerting a departed player is
--     harmless; `after` is where a command re-fires something at their client,
--     and that is not.
--
-- The confirmation toast is the LAST thing, after `after` has run, so what you
-- see on screen is the whole command having finished rather than having
-- started.
function save(player: Player, note: string, mutate: (data: any) -> (), after: (() -> ())?)
	task.spawn(function()
		const ok, err = pcall(function()
			datastore:updateAsync(player, function(data): boolean
				mutate(data)
				-- `true` commits. Returning false would abort the transaction,
				-- which no debug command wants: they are all deliberate writes.
				return true
			end)
		end)
		if not ok then
			warn(`[debug] {note} failed: {err}`)
			if player.Parent then
				alert.send_to(player, S.SAVE_FAILED, alert.SOUND.WARN)
			end
			return
		end
		if player.Parent then
			if after then
				after()
			end
			alert.send_to(player, note, alert.SOUND.CONFIRM)
		end
	end)
end

-- God mode is a SET PLUS A POLL rather than a property write, because there is
-- no single property that means "cannot die": MaxHealth does not stop a script
-- setting Health to 0, and a HealthChanged handler never sees a kill that skips
-- the intermediate values. Topping health up on a short timer catches all of
-- them the same way.
const god: { [Player]: true } = {}

task.spawn(function()
	while true do
		task.wait(DEBUG.GOD_PERIOD)
		for player in god do
			const character = player.Character
			const humanoid = character and character:FindFirstChildOfClass "Humanoid"
			-- `Health > 0` on purpose: god mode keeps a living character alive,
			-- it does not resurrect a corpse. Writing MaxHealth onto a dead
			-- humanoid leaves a ragdoll walking around at full health.
			if humanoid and humanoid.Health > 0 then
				humanoid.Health = humanoid.MaxHealth
			end
		end
	end
end)

observe_players(function(player: Player): () -> ()
	return function()
		-- Player instances are table keys here, so a departed one left in the
		-- set keeps that Player (and its character) alive for the life of the
		-- server.
		god[player] = nil
	end
end)

function humanoid_of(player: Player): Humanoid?
	const character = player.Character
	return character and character:FindFirstChildOfClass "Humanoid"
end

-- A command takes the player who ran it plus the one number and one string the
-- wire carries. Both are optional in practice -- most commands ignore them --
-- and a command that wants neither simply declares one parameter.
type Action = (player: Player, value: number, text: string) -> ()

const commands: { [string]: Action } = {
	god = function(player)
		if god[player] then
			god[player] = nil
			alert.send_to(player, S.GOD_OFF, alert.SOUND.CONFIRM)
		else
			god[player] = true
			alert.send_to(player, S.GOD_ON, alert.SOUND.CONFIRM)
		end
	end,

	heal = function(player)
		const humanoid = humanoid_of(player)
		if humanoid then
			humanoid.Health = humanoid.MaxHealth
		end
	end,

	kill_me = function(player)
		-- God mode off first, or the poll above undoes this within
		-- GOD_PERIOD and the command looks broken rather than blocked.
		god[player] = nil
		const humanoid = humanoid_of(player)
		if humanoid then
			humanoid.Health = 0
		end
	end,

	wipe_data = function(player)
		-- `table.clear` then refill, rather than handing back a fresh table:
		-- `mutate` receives the live data table and the store keeps the
		-- reference, so replacing it would write nothing. Clearing also removes
		-- keys the CURRENT template no longer has, which is the difference
		-- between "wiped" and "wiped except for whatever an old build left".
		save(player, S.DATA_WIPED, function(data)
			table.clear(data)
			for key, value in datastore_template() do
				data[key] = value
			end
		end)
	end,
}

-- PER-PLACE COMMANDS. A multi-place game gives each place its own server code
-- and its own debug commands; this merges them in so there is one menu and one
-- bridge rather than one per place.
--
-- FOUND BY NAME, not required by path. The template ships a single place, so
-- the folders a universe adds do not exist here -- a static `require` of one
-- would stop this whole file loading, in the template and in every place that
-- is not the one named. The module exports `commands` (merged over the table
-- above, so a place can override a generic command) and `describe(player)`
-- (what the bridge reports back when it is asked for state).
const PLACE_FOLDER = `PlaceServer{string.upper(string.sub(place_context.role, 1, 1))}{string.sub(place_context.role, 2)}`
const place_folder = ServerScriptService:FindFirstChild(PLACE_FOLDER)
const place_module = place_folder and place_folder:FindFirstChild "debug-commands"
const place_debug = if place_module then require(place_module) :: any else nil
if place_debug then
	for name, handler in place_debug.commands do
		commands[name] = handler
	end
end

-- Returns an error STRING rather than throwing or asserting. Both callers want
-- to report the failure somewhere specific -- the bridge hands it back to its
-- invoker, the remote handler warns -- and neither wants an exception thrown
-- through it.
function execute(player: Player, name: string, value: number, text: string): string?
	-- Re-checked here even though the file returns early outside Studio: this
	-- is the function both entry points funnel through, and it is the one place
	-- worth being paranoid in.
	if not RunService:IsStudio() or player.Parent ~= Players then
		return "debug commands are Studio-only"
	end
	-- NaN and infinity, before any command sees the number. Every command that
	-- uses `value` does arithmetic with it and most of that arithmetic ends up
	-- in a save -- and NaN written into a player's data poisons it for good,
	-- because it survives the round trip and compares false against every check
	-- that might have caught it later.
	if value ~= value or math.abs(value) == math.huge then
		return "debug command value must be finite"
	end
	const handler = commands[name]
	if not handler then
		return `no such command: {name}`
	end
	const ok, err = pcall(handler, player, value, text)
	return if ok then nil else `command {name} failed: {tostring(err)}`
end

-- THE BRIDGE. A BindableFunction in ReplicatedStorage, so anything running
-- inside the same Studio session -- the command bar, a plugin, an automated
-- test harness -- can run a command as a named player and read the answer,
-- without a remote and without requiring anything from this server tree.
--
-- An empty `name` means "just tell me the state", which is how a caller polls
-- without doing anything.
const bridge = Instance.new "BindableFunction"
bridge.Name = "StudioDebug"
bridge.OnInvoke = function(user_id: number, name: string, value: number?, text: string?): string
	if not RunService:IsStudio() then
		return "debug commands are Studio-only"
	end
	const player = Players:GetPlayerByUserId(user_id)
	if name ~= "" then
		if not player then
			return `no such player: {user_id}`
		end
		const err = execute(player, name, value or 0, text or "")
		if err then
			return err
		end
	end
	if place_debug then
		return place_debug.describe(player)
	end
	return `place={place_context.role} heapKB={gcinfo()} instances={#workspace:GetDescendants()}`
end
bridge.Parent = ReplicatedStorage

-- The group is nil outside Studio, which cannot happen this far down the file,
-- but the nil check is what makes that readable rather than a type cast.
const debug_wire = server_network.debug
if debug_wire then
	debug_wire.command:connect(function(player: Player, data)
		const err = execute(player, data.name, data.value, data.text)
		if err then
			-- Warned, not sent back: the client asked for something that does
			-- not exist or is not allowed, and the person who needs to read
			-- that is the developer with the Output window open.
			warn(`[debug] {err}`)
		end
	end)
end

const names: { string } = {}
for name in commands do
	table.insert(names, name)
end
table.sort(names)
print(`[debug] Studio commands ready: {table.concat(names, ", ")}`)
