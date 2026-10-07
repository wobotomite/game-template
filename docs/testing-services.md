# Testing services

```bash
lune run scripts/run-jest               # build the test place and run the tests
lune run scripts/run-jest --build-only  # build it and stop (no Studio)
```

One file, one command. A service test is a `*.test.luau` file in
`tests/services/`, and that command is the whole of running it.

`docs/testing.md` is still the document about testing. This one covers the one
thing it cannot: a **service** — a module under `src/server/` that holds state
and touches Players, DataStores, MarketplaceService or the wire.

## Why a Lune spec cannot do this

A Lune spec loads a module and calls it. That works for anything whose *require*
touches no engine API, which is most of `src/util` and `src/shared` and is worth
designing for — see `docs/testing.md`. A service is the part that cannot be
written that way, because the engine API is the point of it.
`src/server/data/datastore/init.luau` calls `game:GetService "DataStoreService"`,
probes API access and builds a live lyra store *at module scope*, so the require
fails before a single line of the thing you wanted to test has run. The result
was that the server's actual services were the one part of this tree nothing
tested at all.

Jest Roblox runs **inside Roblox**, where those calls are real, and can replace
any module the code under test requires. That is the whole reason it is here.

## Install

Jest Roblox is Roblox's own port of Jest, published to **wally** rather than to
the pesde index, so it comes in through the wally index the UI packages already
use. In `pesde.toml`:

```toml
[dev_dependencies]
jest = { wally = "roblox/jest", version = "3.20.1" }
JestGlobals = { wally = "roblox/jest-globals", version = "^3.20.0" }
```

Both resolved to **3.20.1**. `JestGlobals` is spelled the way Roblox's own docs
spell it, so a test pasted out of the documentation requires
`Packages.JestGlobals` and works here unchanged. The docs spell the other alias
`Jest`; here it is lower-case `jest`, and exactly one file requires it — the
entry point `scripts/run-jest.luau` generates — so a pasted *test* never meets
the difference. A pasted *run script* does: `Packages.Jest` is `Packages.jest`
here.

- the docs, and the install block these two lines are a translation of —
  https://roblox.github.io/jest-roblox/
- the repo — https://github.com/Roblox/jest-roblox
- the wally index pesde reads — https://github.com/UpliftGames/wally-index

`pesde install` links dev dependencies into **the same `roblox_packages/` as
production dependencies** — there is no separate DevPackages directory — so
Jest lands inside the `Packages` mount `default.project.json` already declares
and nothing had to be added to the project file for it. (Rotriever, which
Roblox's own docs mention in passing, does have a `Packages.Dev`. pesde does
not, so ignore that part of the upstream page.)

`pesde.lock` grew by 852 lines and lost none. Six `jsdotlua/jest*` lines in it
are **not** ours and were there before: they are lyra's and greentea's own
declared dev dependencies, recorded as metadata about those packages. pesde
does not install a dependency's dev dependencies, and none of them appear on
disk.

### The production build carries neither Jest nor the tests

That convenience has a cost, and it is the one thing to get right:

```bash
pesde install --prod   # before building the place you publish
```

Measured here, not assumed:

| | `pesde install` | `pesde install --prod` |
|---|---|---|
| link files in `roblox_packages/` | 11 (incl. `jest`, `JestGlobals`) | 9 |
| package directories under `.pesde/` | 61 | 10 |
| `roblox_packages/` on disk | 6.9M | 2.9M |
| place built from `default.project.json` | 1.31 MB, **contains** `Packages.jest` and `Packages.JestGlobals` | 598 KB, **contains neither** |

`pesde.lock` is byte-identical either way (same md5 before and after both
runs), so switching back and forth is free and neither mode dirties the repo.

The **tests** are never in the production place under either mode: nothing in
`default.project.json` mounts `tests/`.

`scripts/run-jest.luau` checks for the Jest link file before it builds anything
and exits 1 with the command to run, because the alternative failure is a
place that looks complete, opens in Studio, and indexes nil.

## Where the tests live, and why there

`tests/services/`, named `*.test.luau`.

Outside `src/`, because every directory under `src/` is mounted by
`default.project.json` and would therefore ship. Under `tests/`, because that is
where tests live. And **`.test`, not `.spec`**, because `.spec.luau` already
belongs to the Lune suite.

The two runners must not see each other's files, and here they do not, twice
over: `tests/run.luau` discovers specs with `fs.readDir "tests"`, which is **not
recursive**, and then matches `%.spec%.luau$`. A service test is one directory
down *and* has the other extension. Going the other way, Jest's `testMatch` is
`**/*.test` against a root that contains only `tests/services`. Note that Jest's
*default* `testMatch` would have taken both `.spec` and `.test`, which is the
other reason `tests/services/jest.config.luau` sets it explicitly.

The source-scanning specs are unaffected: `requires.spec`, `loads.spec` and
`project.spec` all walk `src/` only. `docs.spec` reads comments under `tests/`
as well, so a path named in a service test has to be real — which is the
behaviour you want.

## The test place is derived, never checked in

`scripts/run-jest.luau` reads `default.project.json`, adds what a test run
needs, and writes `test.project.json` at the repository root. Both that file and
`build/` are gitignored.

A second, hand-kept project file would be this tree written down twice, and the
copy goes stale the first time a mount moves — **silently**, because Rojo builds
a project whose `$path` points at nothing without complaining, and the symptom
is a subsystem that is simply absent. The derived file cannot drift.

Three things are added, and only these three:

1. **The tests mount.** `ReplicatedStorage.Tests` → `tests/services`.
2. **The boot scripts are stopped from running.** This takes two mechanisms,
   because Rojo reaches an `init.server.luau` by a different route than the rest.
   `globIgnorePaths` drops every boot script that is an ordinary file inside a
   directory. It does **not** drop `init.server.luau` / `init.client.luau`:
   Rojo probes for those directly when it snapshots a directory and they turn
   the directory itself into the Script, so the glob never sees them. Measured —
   with the globs alone the built place still carried
   `ServerScriptService.Server` and `ReplicatedStorage.Client` as Scripts. Those
   two mounts get `$properties: { Disabled: true }` instead, which the runner
   works out by looking for an init file on disk rather than from a list. Their
   children are still reachable by name, which is all a test wants from them.
3. **A name.** The project is built as `game-template-tests` so a place open in
   Studio says which one it is.

Why it matters that no boot script runs: the boot scripts are what stand the
network, the datastore and every service up. A test place that booted them
would be measuring its own boot rather than the code under test.

The generated entry point, `build/jest/run.lua`, is generated for the same
reason the project file is: every path in it is a fact the runner already owns.
A checked-in copy is a second home for both paths — the mount moves and the
entry keeps naming the old one.

What an empty run does, read from the installed source rather than assumed
(`jest-core/src/runJest.lua`, and `exit` in `roblox-shared/src/nodeUtils.lua`):
with no test found, 3.20.1 logs *No tests found, exiting with code 1* and calls
`exit(1)`, which in Roblox is `error("Exited with code: 1")`. The promise
rejects, the entry point sees `Rejected`, and the run is red. **The one option
that turns that into a green run is `passWithNoTests`. Never set it**: a
`testMatch` that matches nothing must stay a failure.

## How a service test replaces the wire

A service's sends go through `server-network`, and requiring it for real runs
`sendbufs.create_server` and stands a live transport up in the test place. A
case wants a record of what the service sent instead, so the test mocks the
module. The mechanism is `jest.mock`, not a hand-rolled fake:

```luau
jest.resetModules()
jest.mock(ServerScriptService.Server.net["server-network"], function()
    return { core = { send_alert = { fire = function(_self, player, payload) end } } }
end)
```

Two things make that work, and both were read out of the installed 3.20.1
source rather than remembered — `roblox_packages/.pesde/`, package
`roblox_jest-runtime@3.20.1`, `jest-runtime/src/init.lua`:

- **The sandboxed `require`.** Jest builds the environment a module runs in and
  puts its own `require` in it (line 1976): every require made by a module Jest
  loaded goes through `requireModuleOrMock`, not just the requires written in
  the test file. (3.20 also lets that `require` take a string path, which 3.10
  did not; it makes no difference here, since everything in this repo requires
  Instances.)
- **Mocks are keyed on the module instance alone.** `Runtime_private:_shouldMock`
  (line 2245) sets `local moduleID = moduleName` and never consults who is doing
  the requiring, so a mock registered by the test file applies **transitively, at
  any depth**. The docs' line about a module being mocked only for the file that
  calls `jest.mock` is about per-test-file registry isolation, not about depth.

`tests/services/award.test.luau` is the proof of it. It mocks
`server-network` and the player `datastore`, and deliberately leaves
`src/shared/services/alert.luau` **real** — `alert.send_to` requires the wire
*inside the call*, not at module scope, so the interception has to reach a
transitive **and lazily evaluated** require. Its alert case reads the payload
off the mocked wire, which is what proves the interception reached that far.

Note the order in that file: `jest.resetModules()` first, then `jest.mock`, then
`require` the module under test *inside* each case. `resetModules` (line 1490)
clears `_moduleRegistry` and `_mockRegistry` so the next require re-runs the
service against the mocks; it leaves `_explicitShouldMock` alone, which is
cleared only in `teardown`, so registering after it is safe.

### Deviations from JavaScript Jest worth knowing before you write one

From https://roblox.github.io/jest-roblox/deviations

- `jest.fn()` returns **two** values: the mock (a callable table) and a plain
  function that forwards to it. Pass the second where a real function is
  required; assert against the first.
- `.never` replaces `.not`, which is a Lua keyword.
- `toMatch` and `expect.stringMatching` take a **Lua string pattern** or a
  RegExp, not only a regex.
- `toBeFalsy()` is Lua-falsy — only `false` and `nil`, so `0` is truthy.
- `expect.any()` takes a typename string (`"number"`) as well as a class.
- Constructors are `mockFn.new()`, and `each` takes a list of tables rather than
  a tagged template.
- Everything must be required explicitly from `JestGlobals`. There are no
  globals; a name you forgot to require is simply `nil`.

One more that the deviations page does not spell out and that decides how
`testMatch` is written. Jest globs the **instance path**, not a filesystem path:
`jest-core/src/SearchSource.lua` asks `CoreScriptSyncService` for a real file
path, gets nothing in a built place (nothing is synced) and falls back to
walking the instance tree, so the string being matched is `Tests/award.test`.
SearchSource then appends `?(.lua|.luau)` to every pattern, which is why a
pattern with no extension on it is the one that works under either route.

## It cannot run under Lune

Asked and answered, so nobody spends the afternoon again. Jest Roblox's README
says it runs within Roblox, including via Open Cloud Luau Execution for CI. The
blocker is structural rather than missing polyfills: the runtime addresses
modules as **Instances** and turns each one into a function with
`debug.loadmodule`, or with `loadstring` over `ModuleScript.Source` when that
API is off. Lune's `@lune/roblox` instances are data, not code, and neither
route exists there.

So `--build-only` is as far as this repo gets on its own, and it is worth
running on its own: it proves the place builds, that Jest and the tests landed
where the entry point looks for them, and that no boot script survived.

## Running it for real — the prerequisites

Roblox names two ways to run Jest Roblox — **Studio**, and **Open Cloud Luau
Execution** for CI — on https://roblox.github.io/jest-roblox/ , which links
https://create.roblox.com/docs/cloud/reference/features/luau-execution for the
second. It does not mention `run-in-roblox`. Using it is this repo's own choice,
and it is only a way of getting the Studio route without a human in it.

**1. `run-in-roblox`.** In `rokit.toml` at `rojo-rbx/run-in-roblox@0.3.0` — the
only release there has ever been, 2020-07-20. It is not installed by default; it
needs

```bash
rokit trust rojo-rbx/run-in-roblox
rokit install
```

Source: https://github.com/rojo-rbx/run-in-roblox

**2. The `debug.loadmodule` FFlag, probably.** Jest prefers `debug.loadmodule`
to load a test file and falls back to `loadstring` on the module's source when
the API is unavailable — `jest-runtime/src/init.lua` sets `LOADMODULE_ENABLED`
by pcalling it at line 67 and branches on that at 1891. So the flag may not be
strictly required at 3.20.1, and the fallback has a gate of its own
(`ServerScriptService.LoadStringEnabled`). **Neither has been exercised here**;
see *What has not been run*.

The flag's name comes from the one place Roblox's own docs give it, the
`roblox-cli` invocation on https://roblox.github.io/jest-roblox/ :
`--fastFlags.overrides EnableLoadModule=true`. Studio does not take command-line
overrides, so the equivalent there is a `ClientAppSettings.json` in Studio's
`ClientSettings` directory containing

```json
{ "FFlagEnableLoadModule": true }
```

Confirm where your Studio reads that from rather than trusting a path: on this
machine no `ClientSettings` directory exists yet, and nothing in this repo
creates one.

Nothing else is needed for the local route: no Open Cloud, no API key, no place
id.

**`run-in-roblox` takes over Roblox Studio for the duration.** It opens the
place, runs the script and closes. If somebody is playtesting in that Studio,
this will interrupt them — which is the other reason `--build-only` exists.

Inside Studio instead, with no `run-in-roblox` and no command line: open
`build/jest/test-place.rbxl`, paste `build/jest/run.lua` into the command bar,
and read the Output window. `ProcessService` does not exist there, so there is
no exit code to set and the entry point raises the failure instead — a red suite
must not look like a green one.

### What has not been run

The engine step, and only the engine step. The place builds, Jest and the two
test modules land at the DataModel paths the entry point names, both boot
scripts come out `Disabled`, and the example test typechecks against the derived
sourcemap. Nobody has yet watched `award.test` go green inside Roblox, so the
flag question above is open until someone does.
