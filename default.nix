# Standalone (non-flake) entry. Flake consumers should use the `.lib` output.
#
# gen-settings is a function of `prelude` (gen-prelude), `algebra` (gen-algebra — the fold),
# `bind` (gen-bind — injection), `graph` (gen-graph — cycle detection), `schema`
# (gen-schema — the ref datum and its scan), `types` (gen-types — the structural checkers
# stating what a well-formed schema field is) and `identity` (gen-identity — the one minting
# authority, a dependency-free leaf taken directly rather than through gen-schema).
#
# THREE CHANNELS, ONE PRECEDENCE, AND NONE OF THEM IS A PROBE. A named formal per dependency wins;
# the `inputs` bag is next, tested by attrset membership so a supplied-but-throwing value throws as
# ITSELF rather than falling back; the default is resolved from `./ci/flake.lock`, read as local
# data. There is NO `...`: an argument this root does not declare is a loud error, not a silent drop.
#
# THE PIN SOURCE IS `ci/flake.lock`, NOT THE ROOT `flake.lock`. The root lock stays the flake path's
# lock and is no longer read by Nix code, which is what lets one rule hold across the roster: a root
# lock exists only where the root flake declares inputs, while `ci/flake.lock` exists everywhere —
# including at the libraries that declare no inputs at all and so could hold no shim under the old
# rule. All seven dependencies are root inputs of the ci lock, so every path below is one segment.
#
# `src` AND `dep` ARE FORMALS, NOT `let` BINDINGS, AND THAT IS THE INJECTABLE RESOLVER SEAM — the
# one channel a cell can close. `src` is the only expression here that fetches; everything else
# reads the lock as data. A caller supplying `src = segs: throw "…"` therefore makes fetching
# IMPOSSIBLE for that application rather than merely absent, which is what `ci/tests/entry.nix`
# rests on. A `dep` bound in the `let` below would close over the `let`'s `src`, so the override
# would silently do nothing and the shim would fetch anyway, at rc 0.
#
# THE HAND-WRITTEN THREADING IS GONE, AND WHAT REPLACES IT IS PIN COHERENCE RATHER THAN DATAFLOW.
# This shim used to pass its own `prelude`/`algebra` down into gen-bind, gen-graph, gen-schema and
# gen-types so that one evaluator over one authority served all of them — two instances being two
# content-address formulas for one node. Coherent `ci/flake.lock` pins resolve to one store path and
# `import` memoises, so there is no second instance for a threading to collapse. What makes the count
# one is now the PINS, and the roster-wide coherence check that keeps them coherent is the hub's
# rather than this file's.
#
# The `let` is OUTSIDE the lambda because a formal's default is evaluated in the FORMAL scope, which
# does not see a `let` in the body.
let
  lock = builtins.fromJSON (builtins.readFile ./ci/flake.lock);
  # A direct edge IS the node key; a `follows` value is a PATH resolved segment by segment from this
  # lock's own root. Never by indexing `lock.nodes.<label>` — a last-segment shortcut reads a
  # different node. IT TAKES ITS LOCK AS AN ARGUMENT SO THAT THE ENTRY CELL CAN DRIVE THIS EXACT
  # BINDING ON A FIXTURE WHERE THE TWO RULES DISAGREE BY CONSTRUCTION; a resolver closed over this
  # library's own lock could only ever be compared against a second copy of itself. This is the ONE
  # declaration of the rule in this library — `ci/tests/entry.nix` reads this binding through the
  # record the body hands `wire`, instead of transcribing the fold a second time.
  resolve =
    lock:
    let
      following =
        node: inp:
        let
          v = (lock.nodes.${node}.inputs or { }).${inp};
        in
        if builtins.isString v then v else builtins.foldl' following lock.root v;
    in
    segs: builtins.foldl' following lock.root segs;
  fetch = resolve lock;
in
{
  inputs ? { },
  src ? segs: "${builtins.fetchTree lock.nodes.${fetch segs}.locked}",
  # Arity dispatch, because a dependency's root is a function at a shim'd library and a bare value
  # at a leaf, and neither `import p` nor `import p { }` is total over both.
  dep ?
    segs:
    let
      v = import (src segs);
    in
    if builtins.isFunction v then v { } else v,
  # `wire` IS THE THIRD SEAM, AND IT IS THE ONLY WAY ANYTHING LEAVES THIS FILE. Nix publishes
  # WHETHER a formal has a default and never WHAT it is, and a formal is an INPUT channel that
  # cannot carry a value outward at all — so the only place a formal NAME and its resolved PATH are
  # both in scope is this file's argument TO `wire`, and `resolve` leaves by that same argument
  # rather than by a fourth formal. What `./lib` actually receives is a different question: `wire`
  # RECEIVES `{ deps, resolve }`, and passes on whatever it chooses to — here `deps` and nothing
  # else, but only because the default below reads `{ deps, resolve }: import ./lib deps,`. A cell
  # injecting `dep = segs: segs` alongside `wire = args: args` reads this shim's own formal-to-path
  # map AND its own resolver directly, with nothing fetched, no path restated and no fold
  # transcribed. The record destructures with no `...`, so a drifted body shape is loud at the
  # default; adding `wire` was a widening and breaks no caller for the same reason — there is no
  # `...` here, and no caller passes a name this root does not declare.
  wire ? { deps, resolve }: import ./lib deps,
  prelude ? inputs.gen-prelude or (dep [ "gen-prelude" ]),
  algebra ? inputs.gen-algebra or (dep [ "gen-algebra" ]),
  bind ? inputs.gen-bind or (dep [ "gen-bind" ]),
  graph ? inputs.gen-graph or (dep [ "gen-graph" ]),
  schema ? inputs.gen-schema or (dep [ "gen-schema" ]),
  types ? inputs.gen-types or (dep [ "gen-types" ]),
  # The one minting authority: a dependency-free leaf, so its lib is a bare value and this
  # takes no argument. Derived from THIS shim's lock so the whole construction mints through one
  # encoding — two instances would be two content-address formulas for one node.
  identity ? inputs.gen-identity or (dep [ "gen-identity" ]),
}:
# THE BODY IS EAGER, AND THAT IS WHAT MAKES THE ENTRY CELL TOTAL RATHER THAN PARTIAL. `forced` forces
# every wired dependency to WHNF before `./lib` sees it, so a default that cannot resolve is loud AT
# THE BOUNDARY rather than wherever a consumer first reaches an attribute. Without it a force of this
# root reaches only the dependencies the published surface happens to be derived from — and
# `builtins.deepSeq` cannot make up the difference, because it does not enter a lambda. With the
# eager body a WHNF force of the root reaches all seven, whatever the published surface's shape.
#
# THE FORCE STOPS AT WHNF DELIBERATELY: `builtins.seq` of an attrset does not force its members, so
# this reaches each dependency's root VALUE and never a member of it. A library that deliberately
# refuses to build some member is therefore not an exception to it.
let
  deps = {
    inherit
      prelude
      algebra
      bind
      graph
      schema
      types
      identity
      ;
  };
  forced = builtins.deepSeq (builtins.mapAttrs (_: builtins.typeOf) deps) null;
in
builtins.seq forced (wire {
  inherit deps resolve;
})
