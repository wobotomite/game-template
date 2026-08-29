# game-template

A Roblox game skeleton: Rojo + pesde, Luau, charm/vide/lyra/sendbufs, a shared
util toolbox, and a Lune test suite.

## Getting started

```bash
rokit install     # rojo, stylua, lune, pesde, luau-lsp
pesde install     # packages into roblox_packages/
rojo serve        # then connect from Studio
```

```bash
lune run tests/run           # the whole suite
lune run tests/run wire      # only specs matching "wire"
scripts/analyze.sh           # typecheck
scripts/analyze.sh --counts  # per-file diagnostic counts, for diffing
```

## Layout

| Path | What lives there |
| --- | --- |
| `src/shared` | Code both realms need: `services/` (data, sync, appearance, alerts), `world/` (model layout, raycast filters), `records/`, plus the wire and place context. |
| `src/util` | The toolbox. Observers, signals, step dispatch, tweens, UI hooks and templates, colours, tables. **Zero references is not dead code** — this is a library, not application code, and the next game uses a different third of it. |
| `src/server` | Server scripts and modules: the datastore and its lifecycle, the sync handshake, `fatal`, `validate`, `anticheat/`, `party-gate`, `teleport-guard`, `replication-focus`. |
| `src/client` | Mounted at `ReplicatedStorage.Client`. Only `init.client` and `sync.client` run on their own; everything else is a module you call — `preload`, `play-sound` + `sound-groups`, `music-player`, `setup-ragdolls`, `frame-watch`, `mouse-unlock`, `camera-attach`, `strip-character-sounds`. |
| `src/effects` | One-shot visual moments, one file each, spawned by name. Self-cleaning: see its own README. |
| `src/replicated-first` | Anything that must exist before the game loads. |
| `tests` | Lune specs. Not synced to Roblox — see [docs/testing.md](docs/testing.md). |
| `scripts` | `analyze.sh`, which is how you typecheck. |
| `docs` | The reasoning below. |

## Docs

- **[docs/lessons.md](docs/lessons.md)** — start here. The durable half of the
  friction log, organised by when you would need it: writing a check, what fails
  silently in Roblox, what fails silently in this toolchain.
- **[docs/testing.md](docs/testing.md)** — how the specs work, and the rules that
  exist because breaking them produced a *green run over broken code*.
- **[docs/network.md](docs/network.md)** — sendbufs has no queue, and what
  follows from that; hardening remote handlers; the rate-limit boundary.
- **[docs/models.md](docs/models.md)** — Logic/Structure/Deco, tag lookup, and
  why `FindFirstChild "X" :: BasePart` fails a page away from the mistake.
- **[docs/multi-place.md](docs/multi-place.md)** — opt-in. One build, many
  places; the client-bundle relocation and what it costs; teleport recovery.
- **[docs/friction-log.md](docs/friction-log.md)** — the chronological record,
  one entry per pass, with the full evidence behind every claim in lessons.md.
  Read it before assuming a piece of the template is arbitrary.

## The dialect

Two things surprise people reading this code:

**`const` instead of `local`** for bindings that are never reassigned. It is a
Roblox-Luau form; upstream Luau (and therefore Lune) does not accept it, which
is why `tests/roblox-env` rewrites it when loading a module headless.

**Bare `function name()` at module scope**, not `local function`. These are
per-script globals, so a function may be *called above its own definition* and
still resolve. Two consequences worth knowing:

- Globals are per-script. Two modules can both declare `function update()`
  without colliding. The hazard is *within* one file.
- The same is **not** true of `local function`, and mixing them is a real bug
  class: a `local function` called above its own declaration compiles as a
  global read and is nil at runtime. luau-lsp reports both cases identically;
  [docs/testing.md](docs/testing.md#the-stranded-reference-test) has the
  one-line test that tells them apart.

## What runs on its own

Five scripts, and no more on purpose: `init.server`, `init.client`, both halves
of the charm sync handshake, and `data-lifecycle` (which loads and saves).

Everything else is a module with a `start()` or a plain function, because a
template that decides for you has to be undone by every project that wanted
something else. Ragdoll-on-death is the clearest example — a good default for
some games and wrong for others, so you opt in.

## Conventions worth keeping

- **Records over literals.** Tag names, place ids, tuning numbers, sound ids: a
  string literal in two files is a contract nothing checks. A record makes a
  typo a nil index at require time.
- **Derive, do not restate.** A watchdog deadline written as
  `attempts * delay + grace` cannot drift when someone raises `attempts`. The
  same number typed out twice will.
- **Reject silently on remote handlers.** An `assert` there is a
  client-triggerable server error.
- **Fail at the lookup, not at the use.** `require_*` naming the model and the
  tag beats a cast that defers the error to whatever indexes the nil.
- **Say what a check did not cover.** A skip, a cap, a sampled subset — log it.
  Silent truncation reads as full coverage.
