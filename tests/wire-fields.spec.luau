--!nocheck
-- Every field declared on the wire must actually be read somewhere.
-- Run with:
--   lune run tests/wire-fields.spec.luau
--
-- WHY THIS EXISTS. `shared/network.luau` declares each event's payload as a
-- sendbufs struct. A field nothing reads is not an error, not a warning and not
-- a type failure — it is serialised, sent, and discarded, forever.
--
-- The cost is not theoretical. A per-tick event carrying one entry per entity
-- to every client pays for a dead field on every packet for the life of the
-- server, and the only symptom is a number nobody looks at.
--
-- It is also how a REMOVED feature leaves a tail: the reader goes, the writer
-- and the schema stay, and the wire keeps carrying it.
--
-- THE CORPUS MUST INCLUDE /util. Not a detail. An earlier version of this scan
-- excluded it — the house rule is "do not EDIT /util", which is not the same as
-- never READING it — and it reported all three `analytics.log_funnel` fields as
-- dead, i.e. the entire analytics funnel firing into nothing. Both the sender
-- and the handler live in `util/analytics`. The wire was fine; the scan had
-- removed the consumer from its own corpus.

local h = require "./harness"

h.title "wire fields:"

local NETWORK = "src/shared/network.luau"

-- Normalise the two spellings of the same declaration before parsing. A project
-- may write `sendbufs.event(sendbufs.schema.struct {` or alias
-- `const event, s = sendbufs.event, sendbufs.schema` and write `event(s.struct`.
-- Matching only one of them is a scan that silently checks half the wire.
local network = h.strip(h.read(NETWORK))
network = network:gsub("sendbufs%.schema%.", "s."):gsub("sendbufs%.event", "event")

local function body_at(source: string, open: number): string
	local depth, i = 0, open
	while i <= #source do
		local c = source:sub(i, i)
		if c == "{" then
			depth += 1
		elseif c == "}" then
			depth -= 1
			if depth == 0 then
				return source:sub(open + 1, i - 1)
			end
		end
		i += 1
	end
	return ""
end

type Event = { name: string, fields: { string } }
local events: { Event } = {}
for name, at in network:gmatch "([%w_]+)%s*=%s*event%(s%.struct%s*()" do
	local brace = network:find("{", at, true)
	if brace then
		local fields: { string } = {}
		-- `[\n{,]`, not `[\n{]`: a single-line struct puts its later fields
		-- after a COMMA, and a newline-anchored pattern silently sees only the
		-- first one. Found by mutation — adding a second field to a one-line
		-- struct was not noticed at all.
		for field in body_at(network, brace):gmatch "[\n{,]%s*([%a_][%w_]*)%s*=%s*s%." do
			table.insert(fields, field)
		end
		table.insert(events, { name = name, fields = fields })
	end
end

local total = 0
for _, e in events do
	total += #e.fields
end

-- Blindness guards, BEFORE anything is asserted about the fields themselves. A
-- parser that matched nothing would otherwise report "0 dead fields" forever.
h.saw("struct events in network.luau", #events, 1)
h.saw("payload fields", total, 3)

-- The corpus: every .luau under src except network itself. /util INCLUDED.
local corpus: { string } = {}
for _, entry in h.sources "src" do
	if entry.path ~= NETWORK then
		table.insert(corpus, h.strip(entry.source))
	end
end
local blob = table.concat(corpus, "\n")
h.check(`the corpus includes /util ({#corpus} files)`, blob:find "analytics" ~= nil)

local dead: { string } = {}
for _, e in events do
	for _, field in e.fields do
		-- Read as `something.field`, anywhere outside network.luau. Coarse on
		-- purpose: the question is "does anything consume this at all", and a
		-- precise dataflow answer is not available to a text scan. It errs
		-- toward silence, so a hit here is worth investigating rather than
		-- arguing with.
		if not blob:find(`[%w_%]%)]%.{field}[^%w_]`) then
			table.insert(dead, `{e.name}.{field}`)
		end
	end
end

h.check(
	`every payload field on the wire is read somewhere ({total} fields across {#events} events)`,
	#dead == 0,
	if #dead > 0 then table.concat(dead, ", ") else nil
)

h.done()
