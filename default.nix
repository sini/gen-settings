# Standalone (non-flake) entry. Flake consumers should use the `.lib` output.
#
# gen-settings is a function of `prelude` (gen-prelude), `algebra` (gen-algebra — the fold),
# `bind` (gen-bind — injection), `genGraph` (gen-graph — cycle detection), `genSchema`
# (gen-schema — the ref datum and its scan) and `genTypes` (gen-types — the structural checkers
# stating what a well-formed schema field is). The defaults fetch
# the flake-locked revs (content-addressed via narHash, so the plain-import path stays pure and in
# lockstep with the flake output). Pass any explicitly to override (e.g. a local checkout).
{
  lock ? builtins.fromJSON (builtins.readFile ./flake.lock),
  fetch ?
    name:
    builtins.fetchTree (
      let
        node = lock.nodes.${lock.nodes.root.inputs.${name}}.locked;
      in
      node
    ),
  prelude ? import "${fetch "gen-prelude"}/lib",
  algebra ? import "${fetch "gen-algebra"}/lib",
  # ★ Each dependency is constructed through its OWN standalone entry, never its bare `./lib`. A
  # hand-written argument list here is a second signature that nothing compares against the
  # dependency's own — so a formal gained downstream becomes a silent divergence rather than a
  # refusal. The entry derives its formals from its own lock, so what it needs beyond the shared
  # halves it self-pins: gen-schema's `./lib` also needs gen-merge, which gen-settings has no other
  # use for. `prelude` and `algebra` are still handed down, so the shared halves stay this library's.
  bind ? import "${fetch "gen-bind"}" { inherit prelude; },
  genGraph ? import "${fetch "gen-graph"}" { inherit prelude; },
  genSchema ? import "${fetch "gen-schema"}" { inherit prelude algebra; },
  genTypes ? import "${fetch "gen-types"}" { inherit prelude; },
  # The one minting authority: a dependency-free leaf, so its lib is a bare value and this
  # takes no argument. Derived from THIS shim's lock so the whole construction mints through one
  # encoding — two instances would be two content-address formulas for one node.
  genIdentity ? import "${fetch "gen-identity"}/lib",
}:
import ./lib {
  inherit
    prelude
    algebra
    bind
    genGraph
    genSchema
    genTypes
    genIdentity
    ;
}
