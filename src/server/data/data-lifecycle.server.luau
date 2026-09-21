-- Starts the save lifecycle. The work is in `src/server/data/lifecycle.luau`;
-- this is only the thing that runs it.
--
-- WHY THE SPLIT. Services register a post-load callback with that module
-- (`on_loaded`), and a Script cannot be required -- so the body has to live in
-- a ModuleScript and something has to start it. The two names differ because
-- Rojo would otherwise see two children called `data-lifecycle` and the require
-- path would be ambiguous.
require(script.Parent.lifecycle).start()
