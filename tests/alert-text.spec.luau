--!nocheck
-- shared/services/alert: `decorate`, the pass that turns a line a server module
-- wrote into the rich text the toast draws.
-- Run with:
--   lune run tests/alert-text.spec.luau
--
-- WHY THIS SPEC EXISTS. Everything `decorate` does is invisible until it is
-- wrong, and every way it is wrong looks the same on screen: markup drawn as
-- text. It emits rich text AND consumes rich text the caller wrote, so the two
-- easy mistakes are upper-casing markup and colouring inside markup -- and
-- neither throws, neither fails a type check, and both only show up in a
-- screenshot somebody has to be looking at.
--
-- It is also the only part of the alert service that can be run outside the
-- engine: the rest of the module is a wire and an atom.
--
-- The keyword list is `settings.alerts.HIGHLIGHTS`, and this spec reads the
-- colour from there rather than writing it in, so retuning the colour does not
-- turn this red.

local h = require "./harness"
local env = require "./roblox-env"

h.title "alert text:"

-- The SERVER realm, because the client branch of the module requires the client
-- wire, which cannot be built outside the engine. `decorate` is the same
-- function either way -- it is declared above the realm split.
local alert = env.load("ReplicatedStorage.Shared.services.alert", { realm = "server" })
local settings = env.load("ReplicatedStorage.Shared.settings", { realm = "server" })

-- The span the service is expected to emit for one listed keyword, built from
-- the list itself. Erroring on a missing entry is deliberate: every case below
-- is written around these two words, and silently substituting nothing would
-- leave a spec that passes while measuring the empty string.
local function span(word: string): string
	for _, entry in settings.alerts.HIGHLIGHTS do
		if entry.text == word then
			return `<font color="#{entry.color:ToHex()}"><b>{entry.text}</b></font>`
		end
	end
	error(`settings.alerts.HIGHLIGHTS has no entry for "{word}"`)
end

local COINS = span "COINS"
local COIN = span "COIN"

do
	-- The whole job in one line: raised to upper case, keyword coloured.
	h.equals("a plain line is shouted and its keyword coloured", alert.decorate "you got 5 coins!", `YOU GOT 5 {COINS}!`)
end

do
	-- WORD BOUNDARIES. "coincide" contains "coin", and without the boundary
	-- test the first four letters of an ordinary word come out gold.
	h.equals("a keyword inside a longer word is left alone", alert.decorate "that coincides", "THAT COINCIDES")
	-- Punctuation and digits are boundaries, so a keyword still colours when it
	-- is not surrounded by spaces.
	h.equals("punctuation still counts as a boundary", alert.decorate "(coins)", `({COINS})`)
	-- The plural entry wins over the singular at the same position: one span
	-- covering the whole word, not a span over "COIN" with a bare "S" after it.
	h.equals("the longer entry takes the whole word", alert.decorate "coins", COINS)
end

do
	-- RICH-TEXT ENTITIES survive the shout. `&amp;` upper-cased is `&AMP;`,
	-- which Roblox does not recognise and draws literally -- so an ampersand in
	-- a line would appear on screen as five characters of markup.
	h.equals("an entity is not upper-cased", alert.decorate "tom &amp; jerry", "TOM &amp; JERRY")
	h.equals("and the text around it still is", alert.decorate "it&#39;s a coin", `IT&#39;S A {COIN}`)
end

do
	-- MARKUP THE CALLER WROTE. The tag is copied through byte for byte: a
	-- shouted `<FONT COLOR="#ABCDEF">` is not a tag Roblox parses, so the line
	-- would draw the markup instead of colouring anything.
	h.equals("a tag is copied through untouched", alert.decorate '<font color="#abcdef">x</font>', '<font color="#abcdef">X</font>')

	-- AND NOT COLOURED INSIDE. Roblox takes the innermost colour, so a keyword
	-- highlight inside the caller's own font span would quietly override the
	-- colour they asked for.
	h.equals(
		"text inside the caller's font is shouted but not highlighted",
		alert.decorate '<font color="#ff0000">10 coins</font> lost',
		'<font color="#ff0000">10 COINS</font> LOST'
	)

	-- Only `<font>` suppresses it. A `<b>` span is not a colour, so its text is
	-- highlighted as usual -- and if `<b>` set the depth, a bolded line would
	-- silently lose every highlight in it.
	h.equals("a non-colour tag does not suppress highlighting", alert.decorate "<b>coin</b>", `<b>{COIN}</b>`)
end

do
	-- A "<" with no ">" after it is arithmetic somebody typed, not a tag.
	-- Treating it as one would swallow the rest of the line.
	h.equals("an unclosed angle bracket is text", alert.decorate "5 < 10 coins", `5 < 10 {COINS}`)
	h.equals("an empty message decorates to nothing", alert.decorate "", "")
end

do
	-- The wire field is `maybe(str)`, so an omitted sound and a deliberately
	-- silent one arrive the same. SILENT is "" -- the unset marker used
	-- everywhere else -- so a voice that treats "" as unset is right by default.
	h.equals("SILENT is the empty string", alert.SOUND.SILENT, "")
	h.check("set_voice is exported for the client audio to register into", type(alert.set_voice) == "function")
end

h.done()
