# gen-settings public API — stratified settings resolution as a pure layered fold, refs-as-data,
# structured provenance, and the graduated injection construct.
#
# Class B (nixpkgs-lib-free): builtins + gen-prelude, plus gen-algebra (the fold lives there),
# gen-bind (injection), gen-graph (cycle detection lives there), and gen-schema consumed
# interface-only (values must carry id_hash; nothing is imported from it). CI purity invariant
# enforces the boundary.
#
# `genGraph` is the gen-graph library; the local `graph` below is this library's own ref-graph
# module. The two names are kept distinct because both are in scope here and `resolve.nix` binds
# the local one.
{
  prelude,
  algebra,
  bind,
  genGraph,
}:
let
  display = import ./display.nix { inherit prelude; };
  schema = import ./schema.nix { inherit prelude; };
  ref = import ./ref.nix { inherit prelude; };
  graph = import ./graph.nix {
    inherit
      prelude
      ref
      display
      genGraph
      ;
  };
  resolve = import ./resolve.nix {
    inherit
      prelude
      algebra
      ref
      graph
      display
      ;
  };
  inject = import ./inject.nix { inherit prelude bind; };
in
{
  inherit (schema) mkSchema;
  inherit (ref) ref isRef refsIn;
  inherit (graph) refGraph assertAcyclic renderCycles;
  inherit (resolve) resolveOne resolveAll;
  inherit (inject) injectAspectSettings assembleHost;
  inherit (display) renderAddress;
}
