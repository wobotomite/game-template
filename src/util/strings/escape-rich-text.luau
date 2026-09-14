-- Escape a string so it can be dropped into a RichText label as TEXT rather
-- than as markup.
--
--   label.Text = `<b>{escape_rich_text(player.DisplayName)}</b> won`
--
-- EVERY player name and every other user-supplied string goes through this
-- before it reaches a label with `RichText = true`. A display name is allowed
-- to contain `<`, and one that does silently breaks the whole label: Roblox
-- parses from the `<` onward looking for a tag, finds garbage, and the label
-- renders empty or drops the rest of the line. It is not an error and nothing
-- is logged -- the text just vanishes, on that one player's row, for everybody
-- else in the server.
--
-- `&` MUST BE FIRST. Escaping it after `<` would turn the `&lt;` this function
-- just produced into `&amp;lt;`, which renders as the literal text "&lt;".
--
-- The outer parentheses are load-bearing: `gsub` returns the count as a second
-- value, and this function is declared to return one string.
return function(text: string): string
	return (text:gsub("&", "&amp;"):gsub("<", "&lt;"):gsub(">", "&gt;"):gsub('"', "&quot;"):gsub("'", "&apos;"))
end
