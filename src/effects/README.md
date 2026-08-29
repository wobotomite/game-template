# effects

Every one-shot visual moment, one file each, spawned by name. Syncs to
`ReplicatedStorage.Effects`.

If you want to change how something looks, how loud its cue is, or how long a
telegraph takes to fill, it is in `list/` and that is the only place you have to
look.

```luau
const effects = require(ReplicatedStorage.Effects)

effects.new("common/ground-telegraph", nil, {
    position = landing, radius = 9, duration = 1.2, color = Color3.new(1, 0.3, 0.2),
})
```

## Layout

```
effects/
  init.luau           the registry: new(name, instances, attributes)
  effect-types.luau   the types, and the generated union of valid names
  shared/             helpers effects share (floor probe + inert decal)
  list/               ONE FILE PER EFFECT -- this is the part you edit
    common/           ground-telegraph (the one example; write yours beside it)
```

An effect's name is its path under `list/`, so
`list/common/ground-telegraph.luau` is `"common/ground-telegraph"`. The registry walks the folder — a file exists, therefore the
effect exists. There is no list to keep in sync.

## Writing one

A `list/` module returns **one function**:

```luau
return function(cleanup, get, attr)
    const position = attr "position" :: Vector3
    const anchor = get "anchor" :: BasePart      -- only if one was bound

    const part = Instance.new "Part"
    -- ... build it, tween it ...

    task.delay(0.5, cleanup)                      -- end when the moment is over
    return function()                             -- teardown, run exactly once
        part:Destroy()
    end
end
```

- `attr "name"` reads what the caller passed. Missing attributes throw with the
  effect's name in the message rather than arriving as `nil` three frames later.
  `attr "start_time"` is always available: it is the effect's start on the
  **synced** clock, which is the clock to measure against because effects are
  spawned from replicated events. Mixing it with `os.clock` fails silently.
- `get "key"` reads a bound instance.
- `cleanup()` ends the effect. Call it when the moment is genuinely over so the
  registry stops considering it running.
- The returned functions are teardowns. Destroy what you made. They run exactly
  once, whichever way the effect ends.

## Lifetime

Three things can end an effect, whichever happens first, and the teardown runs
once:

1. the effect calls `cleanup()` when it finishes naturally
2. the caller calls `handle.cleanup()`
3. **a bound instance is destroyed** — this is the one that earns the framework

```luau
effects.new("common/aura", { target = model }, { color = ... })
```

binds the effect's life to `model`. When the model is removed, the effect stops
and cleans up on its own. Hand-rolling that per effect is exactly where the
leaks were before.

`handle.allow_long_run()` silences the 60-second warning for an effect that is
meant to persist. In Studio, anything still running after a minute warns —
almost always a leak.

## Sound belongs to the effect

Each entry plays its own cue, so one file is the complete moment and look and
sound can be retuned together.

The one rule worth stating: **telegraphs are silent.** A telegraph is the
WARNING half of an attack and the arriving half carries the sound. A cue on the
windup *and* another on the hit reads as two events, and players dodge the first
one.

Keep ids and mix levels in a record, and reach for a named level rather than a
number — see `src/client/audio/sound-groups.luau` for why every cue wants a bus.

## Two failures this folder is shaped around

**A name that does not exist.** `effect-types.luau` generates a union of the real
folder paths, so Studio rejects a typo. But **luau-lsp cannot evaluate
user-defined type functions** — it reports "This syntax is not supported" for
that file and for `util/tables/const-record` — so the union constrains names in
Studio and *not* on the command line, and a union that silently degraded to
`string` would look identical. `init.luau` also asserts at spawn time, and
`tests/effects.spec.luau` checks every `new()` call site against the real
folder. Three checks, because the type is the one that can fail invisibly.

**An effect nobody spawns.** A file in `list/` that nothing calls is dead and
still looks alive, because it sits in the folder with the live ones. The spec
checks that direction too, and **pins the entry count exactly rather than
bounding it** — a `>= 20` style bound was mutation-tested on the original of
that spec and stayed green while three effects were deleted one at a time. A
bound is only a check outside its own slack.

## What is deliberately not here

**Continuous, stateful visuals.** A character renderer, a viewmodel, an
outline pass, an atmosphere controller — anything that owns state for as long as
the session and is driven by the world changing rather than spawned at a moment.
This registry is for things with a beginning and an end.

**Server-authoritative numbers.** If the server resolves damage at a radius the
client draws a telegraph at, that radius is a shared record both sides read — not
a constant inside a client-only effects folder. A telegraph drawn at a different
size than the hit it warns about is a warning that lies.
