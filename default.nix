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
  bind ? import "${fetch "gen-bind"}/lib" { inherit prelude; },
  genGraph ? import "${fetch "gen-graph"}/lib" { inherit prelude; },
  # gen-schema's ./lib also needs gen-merge, which gen-settings has no other use for — so this one
  # goes through gen-schema's own standalone entry, which self-pins that half from its own lock.
  # `prelude` and `algebra` are still handed down, so the shared halves stay this library's.
  genSchema ? import "${fetch "gen-schema"}" { inherit prelude algebra; },
  genTypes ? import "${fetch "gen-types"}/lib" { inherit prelude; },
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
