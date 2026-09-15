{
  description = "gen-settings — stratified settings resolution as a pure layered fold, with refs-as-data, structured provenance, and the graduated injection construct";

  # Class B (roadmap §5): builtins + gen-prelude, plus gen-algebra (the fold — foldLayersTraced —
  # lives there per Spike 5, never reimplemented here), gen-bind (injection), gen-graph (cycle
  # detection over the ref graph — the algorithm lives there, never reimplemented here), gen-schema
  # (the ref DATUM and its scan live there, beside the reference TYPE whose inhabitants refs are)
  # and gen-identity (the minting authority; rationale on its own `inputs` line below). gen-schema
  # was once consumed interface-only — values must carry id_hash — and is now an input. The
  # `inputs` block below is this library's input list in full — this comment gives the WHY for
  # each, not the count. gen-types states what a well-formed schema field IS (the structural
  # checkers behind E1, never reimplemented here); the E1 diagnostic itself stays. The library
  # (./lib) is nixpkgs-lib-free (ci/tests/purity.nix); nixpkgs enters only in ci/ (the harness).
  inputs = {
    gen-prelude.url = "github:sini/gen-prelude";
    gen-algebra.url = "github:sini/gen-algebra";
    gen-bind.url = "github:sini/gen-bind";
    gen-graph.url = "github:sini/gen-graph";
    gen-schema.url = "github:sini/gen-schema";
    gen-types.url = "github:sini/gen-types";
    # The one minting authority, now a dependency-free leaf. Taken directly rather than through
    # gen-schema: a mint reached through a second library is a mint whose identity depends on
    # that library's pin.
    gen-identity.url = "github:sini/gen-identity";
    # ★ COLLAPSED ONTO ONE NODE, and done now rather than when it bites. gen-schema carries a
    # gen-identity of its own, so without this the lock resolves TWO — and two instances of the
    # MINT are two encoding formulas for one node, which is silent while the revs agree and
    # silent-and-wrong the moment they diverge. Collapsing while they still agree is free;
    # collapsing after they diverge is a migration.
    gen-schema.inputs.gen-identity.follows = "gen-identity";
  };

  outputs =
    {
      gen-prelude,
      gen-algebra,
      gen-bind,
      gen-graph,
      gen-schema,
      gen-types,
      gen-identity,
      ...
    }:
    {
      # `nix flake check` forces the WHNF of every top-level output and nothing deeper, so this root's
      # green quantified over the `lib` SPINE alone: a member of the published surface could throw and
      # the check still exited 0 (measured — den-hoag-z1ta6). Hanging the force on that spine is what
      # makes the green mean "the surface evaluates", and a library needs no new output name for it.
      # The depth is each member's WHNF and no deeper: a retirement tombstone is a published `throw`
      # by design (gen-scope's `buildNodes`), so a deep force is red on a healthy tree.
      lib =
        let
          surface = import ./lib {
            prelude = gen-prelude.lib;
            algebra = gen-algebra.lib;
            bind = gen-bind.lib;
            graph = gen-graph.lib;
            schema = gen-schema.lib;
            types = gen-types.lib;
            identity = gen-identity.lib;
          };
        in
        builtins.deepSeq (builtins.mapAttrs (_: builtins.typeOf) surface) surface;
    };
}
