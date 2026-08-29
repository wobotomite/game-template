--!strict
-- Runs every spec in this directory.
--
--   lune run tests/run           all specs
--   lune run tests/run vacuum    only specs whose name contains "vacuum"
--
-- Each spec runs in its OWN `lune` process, on purpose. Specs load real source
-- text and compile chunks out of it; one that throws, hangs on a bad pattern,
-- or leaves a global behind must not be able to take the rest of the suite
-- with it or change what the next spec sees. The cost is a process per spec,
-- which at this scale is nothing.
--
-- Exits non-zero if any spec fails, so it works as a pre-commit hook or a CI
-- step unchanged.
--
-- ON A SPEC THAT HANGS. Lune's `process.exec` blocks with no timeout, so an
-- accidental infinite loop -- or a broken deadline in the module under test --
-- stops the suite with nothing on screen to say where. It is still locatable
-- without a progress line: specs run in SORTED order and each prints when it
-- finishes, so the culprit is the one alphabetically after the last `PASS`.
--
-- That inference is why there is no "now running…" line here. It would print a
-- second row per spec, and piped output does not honour a carriage return, so
-- the cost is real and the information was already there.
--
-- When mutation-testing a module that contains a deadline, run its single spec
-- under an external timeout rather than the whole suite.

local fs = require "@lune/fs"
local process = require "@lune/process"

local filter = process.args[1]

local specs: { string } = {}
for _, name in fs.readDir "tests" do
	if name:match "%.spec%.luau$" then
		if not filter or name:find(filter, 1, true) then
			table.insert(specs, name)
		end
	end
end
table.sort(specs)

if #specs == 0 then
	print(if filter then `no spec matches "{filter}"` else "no specs found in tests/")
	process.exit(1)
end

-- Wall-clock per spec, so a scan that has quietly become quadratic is visible
-- before it becomes the reason nobody runs the suite.
local started = os.clock()
local failed: { string } = {}
local outputs: { [string]: string } = {}

for _, name in specs do
	local at = os.clock()
	local result = process.exec("lune", { "run", `tests/{name}` }, { stdio = "default" })
	local elapsed = math.floor((os.clock() - at) * 1000)
	if result.ok then
		print(`PASS  {name}  ({elapsed}ms)`)
	else
		print(`FAIL  {name}  ({elapsed}ms)`)
		table.insert(failed, name)
		-- Kept so the failures can be reprinted together at the end. A failure
		-- twenty specs up the scrollback is a failure nobody reads.
		outputs[name] = result.stdout .. result.stderr
	end
end

print ""
print(`{#specs - #failed}/{#specs} specs passed in {math.floor((os.clock() - started) * 1000)}ms`)

if #failed > 0 then
	print ""
	print "================================ failures ================================"
	for _, name in failed do
		print ""
		print(`---- {name} ----`)
		-- Only the failing lines: a spec prints one line per assertion and the
		-- passing ones are noise once the summary above has counted them.
		for line in (outputs[name] .. "\n"):gmatch "(.-)\n" do
			-- `0 failed` in a summary line is not a failure. Matching the bare
			-- word reprinted the summary of specs that had passed every case,
			-- which reads as a contradiction rather than as an explanation.
			local is_summary_zero = line:match "0 failed"
			if not is_summary_zero and (line:match "FAIL" or line:match "failed" or line:match "error") then
				print(line)
			end
		end
	end
	process.exit(1)
end
