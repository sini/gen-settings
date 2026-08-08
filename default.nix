# Standalone (non-flake) entry. Flake consumers should use the `.lib` output.
#
# gen-settings is a function of `prelude` (gen-prelude), `algebra` (gen-algebra — the fold),
# `bind` (gen-bind — injection) and `genGraph` (gen-graph — cycle detection). The defaults fetch
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
}:
import ./lib {
  inherit
    prelude
    algebra
    bind
    genGraph
    ;
}
