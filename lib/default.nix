# gen-settings public API — stratified settings resolution as a pure layered fold, refs-as-data,
# structured provenance, and the graduated injection construct.
#
# Class B (nixpkgs-lib-free): builtins + gen-prelude, plus gen-algebra (the fold lives there),
# gen-bind (injection), gen-graph (cycle detection lives there), gen-schema (the ref DATUM
# lives there, beside the reference type whose inhabitants refs are — so gen-schema is now an
# IMPORTED input, not the interface-only dependency it once was; the id_hash law it defines is the
# same law either way), gen-types (structural checking — what a well-formed schema field IS is
# stated there, while the E1 diagnostic stays here), and gen-identity (the one minting authority,
# taken directly rather than through gen-schema so identity never depends on a second library's
# pin — `inject.nix` calls `hashIdentity` for the `attaches` binding stamp). CI purity invariant
# enforces the boundary.
#
# `graph` (the formal) is the gen-graph library; the local `refGraphModule` below is this
# library's own ref-graph module. The two are kept distinct because both are in scope here and
# `resolve.nix` binds the local one under its own formal name `graph`. `schema` (the formal, the
# schema.nix module) and `schemaModule` are kept distinct for the same reason.
{
  prelude,
  algebra,
  bind,
  graph,
  schema,
  types,
  identity,
}:
let
  display = import ./display.nix { inherit prelude; };
  schemaModule = import ./schema.nix { inherit prelude types; };
  ref = import ./ref.nix { inherit schema; };
  refGraphModule = import ./graph.nix {
    inherit
      prelude
      ref
      display
      graph
      ;
  };
  resolve = import ./resolve.nix {
    inherit
      prelude
      algebra
      ref
      display
      ;
    graph = refGraphModule;
  };
  inject = import ./inject.nix {
    inherit
      prelude
      bind
      schema
      identity
      ;
  };
in
{
  inherit (schemaModule) mkSchema;
  inherit (ref) ref isRef refsIn;
  inherit (refGraphModule) refGraph assertAcyclic renderCycles;
  inherit (resolve) resolveOne resolveAll;
  inherit (inject) injectAspectSettings assembleHost;
  inherit (display) renderAddress;
}
