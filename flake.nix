{
  description = "gen-settings — stratified settings resolution as a pure layered fold, with refs-as-data, structured provenance, and the graduated injection construct";

  # Class B (roadmap §5): builtins + gen-prelude, plus gen-algebra (the fold — foldLayersTraced —
  # lives there per Spike 5, never reimplemented here), gen-bind (injection) and gen-graph (cycle
  # detection over the ref graph — the algorithm lives there, never reimplemented here). gen-schema
  # is consumed INTERFACE-ONLY — values must carry id_hash — so it is not a flake input. The library
  # (./lib) is nixpkgs-lib-free (ci/tests/purity.nix); nixpkgs enters only in ci/ (the harness).
  inputs = {
    gen-prelude.url = "github:sini/gen-prelude";
    gen-algebra.url = "github:sini/gen-algebra";
    gen-bind.url = "github:sini/gen-bind";
    gen-graph.url = "github:sini/gen-graph";
  };

  outputs =
    {
      gen-prelude,
      gen-algebra,
      gen-bind,
      gen-graph,
      ...
    }:
    {
      lib = import ./lib {
        prelude = gen-prelude.lib;
        algebra = gen-algebra.lib;
        bind = gen-bind.lib;
        genGraph = gen-graph.lib;
      };
    };
}
