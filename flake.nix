{
  description = "gen-settings — stratified settings resolution as a pure layered fold, with refs-as-data, structured provenance, and the graduated injection construct";

  # Class B (roadmap §5): builtins + gen-prelude, plus gen-algebra (the fold — foldLayersTraced —
  # lives there per Spike 5, never reimplemented here), gen-bind (injection), gen-graph (cycle
  # detection over the ref graph — the algorithm lives there, never reimplemented here) and
  # gen-schema (the ref DATUM and its scan live there, beside the reference TYPE whose inhabitants
  # refs are). gen-schema was once consumed interface-only — values must carry id_hash — and is now
  # an input. The library (./lib) is nixpkgs-lib-free (ci/tests/purity.nix); nixpkgs enters only in
  # ci/ (the harness).
  inputs = {
    gen-prelude.url = "github:sini/gen-prelude";
    gen-algebra.url = "github:sini/gen-algebra";
    gen-bind.url = "github:sini/gen-bind";
    gen-graph.url = "github:sini/gen-graph";
    gen-schema.url = "github:sini/gen-schema";
  };

  outputs =
    {
      gen-prelude,
      gen-algebra,
      gen-bind,
      gen-graph,
      gen-schema,
      ...
    }:
    {
      lib = import ./lib {
        prelude = gen-prelude.lib;
        algebra = gen-algebra.lib;
        bind = gen-bind.lib;
        genGraph = gen-graph.lib;
        genSchema = gen-schema.lib;
      };
    };
}
