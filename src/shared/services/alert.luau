const ReplicatedStorage = game:GetService "ReplicatedStorage"
const RunService = game:GetService "RunService"
const ServerScriptService = game:GetService "ServerScriptService"

const charm = require(ReplicatedStorage.Packages.charm)
const synced_time = require(ReplicatedStorage.Util.numbers["synced-time"])
const HIGHLIGHTS = require(ReplicatedStorage.Shared.settings).alerts.HIGHLIGHTS

-- The toast line: one shared atom the client alert page renders from, plus the
-- two server calls that push into it. Everything else in here is TEXT
-- DRESSING -- see `decorate` -- and it is here rather than in the page because
-- the server, the client and any spec all have to agree on what a line looks
-- like once it is on screen.

export type alert_type = { message: string, timestamp: number }
const alert_atom = charm.atom<<alert_type?>>()

-- The sound a line asks for, by MEANING rather than by asset. A caller says
-- what kind of thing happened; the client audio decides what that sounds like,
-- through `set_voice` below. Passing an asset id here instead would put the
-- game's sound design in whatever server module happened to raise the alert.
--
-- SILENT is "" rather than nil so a caller can say "no sound" explicitly and
-- have it survive the wire: the field is `maybe(str)`, and an omitted field and
-- a deliberately silenced one decode the same. "" is the unset marker
-- everywhere else in this codebase, so a voice that treats it as unset is right
-- either way.
const SOUND = table.freeze {
	WARN = "WARN",
	REFUSE = "REFUSE",
	CONFIRM = "CONFIRM",
	PURCHASE = "PURCHASE",
	SILENT = "",
}

-- UPPERCASE, except inside a rich-text ENTITY. `&#39;` and `&amp;` are
-- case-sensitive to the renderer: upper-casing them yields `&#39;` -> `&#39;`
-- (harmless) but `&amp;` -> `&AMP;`, which Roblox does not recognise and draws
-- literally, so an apostrophe in a line turns into visible markup on screen.
-- The entity is copied through untouched and only the text around it is raised.
function shout(text: string): string
	local out = ""
	local index = 1
	while true do
		const start, stop = string.find(text, "&#?%w+;", index)
		if start == nil or stop == nil then
			out ..= string.upper(string.sub(text, index))
			break
		end
		out ..= string.upper(string.sub(text, index, start - 1)) .. string.sub(text, start, stop)
		index = stop + 1
	end
	return out
end

-- Colour the keywords in `settings.alerts.HIGHLIGHTS`, which are matched
-- against the line AFTER `shout` has raised it -- so the list is written in
-- upper case and this never has to case-fold.
--
-- WORD BOUNDARIES, both sides. Without them "COIN" matches inside "COINCIDE"
-- and the line comes out with three letters coloured mid-word. The test is "the
-- neighbour is not a letter", which leaves punctuation, digits and the ends of
-- the string as boundaries -- so "COINS!" and "5 COINS" both colour and
-- "COINAGE" does not.
--
-- FIRST MATCH WINS, so the list is ordered longest first: a multi-word entry
-- has to be tried before any single word inside it, or the shorter one takes
-- the front of the phrase and the rest is left plain.
function highlight(text: string): string
	local out = ""
	local index = 1
	const size = #text
	while index <= size do
		local skipped = false
		for _, entry in HIGHLIGHTS do
			const stop = index + #entry.text - 1
			if
				string.sub(text, index, stop) == entry.text
				-- `string.sub` past either end returns "", and "" never matches
				-- "%a", so the first and last characters of the line are
				-- boundaries without a special case.
				and not string.match(string.sub(text, index - 1, index - 1), "%a")
				and not string.match(string.sub(text, stop + 1, stop + 1), "%a")
			then
				out ..= `<font color="#{entry.color:ToHex()}"><b>{entry.text}</b></font>`
				index = stop + 1
				skipped = true
				break
			end
		end
		if not skipped then
			out ..= string.sub(text, index, index)
			index += 1
		end
	end
	return out
end

-- The whole dressing pass, and the only one a caller should use: shout the
-- line, colour its keywords, and leave any rich text the caller wrote alone.
--
-- WHY IT WALKS THE TAGS instead of running `shout` and `highlight` over the
-- whole string. Both would eat the markup. `shout` would raise `<font
-- color="#d4af37">` to `<FONT COLOR="#D4AF37">`, which Roblox does not parse,
-- and `highlight` would find its keywords inside attribute values and nest a
-- colour tag inside one. So the message is split into TAGS and TEXT, and only
-- the text is touched.
--
-- `depth` is why the split is not enough on its own: text that the caller
-- already wrapped in its own `<font>` is still shouted, but NOT highlighted.
-- Roblox takes the innermost colour, so highlighting inside a caller's own
-- colour silently overrides the colour they asked for -- and a caller that
-- coloured a span meant that colour.
function decorate(message: string): string
	local out = ""
	local index = 1
	local depth = 0
	const size = #message
	const function plain(text: string)
		const shouted = shout(text)
		out ..= if depth > 0 then shouted else highlight(shouted)
	end
	while index <= size do
		const open = string.find(message, "<", index, true)
		const close = if open then string.find(message, ">", open, true) else nil
		if open == nil or close == nil then
			-- No complete tag left: an unpaired "<" is part of the sentence.
			plain(string.sub(message, index))
			break
		end
		if open > index then
			plain(string.sub(message, index, open - 1))
		end
		const tag = string.sub(message, open, close)
		if string.sub(tag, 1, 5) == "<font" then
			depth += 1
		elseif tag == "</font>" then
			depth -= 1
		end
		out ..= tag
		index = close + 1
	end
	return out
end

-- THE AUDIO SEAM. This module is shared code and knows nothing about the
-- game's sound system; the client audio registers itself here at boot:
--
--   alert.set_voice(function(sound: string?)
--       -- map a SOUND key to a cue, or play a default for nil
--   end)
--
-- A DIRECT REQUIRE of the client audio would make this module client-only --
-- it is required on the server too, for `send_to` -- and would put a client
-- module's whole dependency tree behind every server require of it. Until
-- something registers, alerts are silent and still readable, which is the right
-- failure: a missing sound is a missing sound, not a missing message.
local alert_voice: ((sound: string?) -> ())? = nil

function set_voice(fn: (sound: string?) -> ())
	alert_voice = fn
end

function client(message: string, sound: string?)
	assert(RunService:IsClient(), "CLIENT ALERTS ARE ONLY AVAILABLE ON THE CLIENT!")
	-- An empty message is a SOUND-ONLY alert -- a refusal beep on a button that
	-- has nothing to say. Pushing it into the atom would draw a blank toast and
	-- push a real one off the stack.
	if message ~= "" then
		alert_atom {
			message = decorate(message),
			timestamp = synced_time(),
		}
	end
	const voice = alert_voice
	if voice then
		voice(sound)
	end
end

if RunService:IsServer() then
	-- REQUIRED INSIDE THE CALLS, not at module scope. Requiring the server
	-- network builds the whole wire, and this module is shared: a server module
	-- that only wants `alert.SOUND` or `alert.decorate` would otherwise force
	-- the wire into existence just by naming this file, and its position in the
	-- boot would decide when the remotes appear. Alerts are rare, and a require
	-- of an already-loaded module is a cache lookup.
	function send_to(p: Player, message: string, sound: string?)
		const network = require(ServerScriptService.Server.net["server-network"])
		network.core.send_alert:fire(p, {
			message = message,
			sound = sound,
		})
	end
	function send_to_all(message: string, sound: string?)
		const network = require(ServerScriptService.Server.net["server-network"])
		network.core.send_alert:fire_all {
			message = message,
			sound = sound,
		}
	end
else
	const network = require(ReplicatedStorage.Client.net["client-network"])
	network.core.send_alert:connect(function(a0: {} & { message: string, sound: string? })
		client(a0.message, a0.sound)
	end)
end

return table.freeze {
	SOUND = SOUND,
	client = client,
	set_voice = set_voice,
	-- Exported for the spec, and for a page that wants to dress a line it
	-- renders itself rather than pushing it through the toast stack.
	decorate = decorate,
	send_to = send_to,
	send_to_all = send_to_all,
	alert_atom = alert_atom,
}
