{
  inputs = {
    gen.url = "github:sini/gen";
    gen-prelude.url = "github:sini/gen-prelude";
    gen-algebra.url = "github:sini/gen-algebra";
    gen-bind.url = "github:sini/gen-bind";
    gen-graph.url = "github:sini/gen-graph";
    gen-schema.url = "github:sini/gen-schema";
    gen-types.url = "github:sini/gen-types";
    # nixpkgs is the CI runner's dependency (nix-unit harness, treefmt) and supplies the `lib` the
    # test modules use. It enters ONLY here (a VALUE in ci/), never a `lib/` dep — the library
    # (../lib) is nixpkgs-lib-free (ci/tests/purity.nix enforces this).
    nixpkgs.url = "https://channels.nixos.org/nixos-unstable/nixexprs.tar.xz";
  };

  outputs =
    inputs@{
      gen,
      gen-prelude,
      gen-algebra,
      gen-bind,
      gen-graph,
      gen-schema,
      gen-types,
      ...
    }:
    let
      genSettings = import ../lib {
        prelude = gen-prelude.lib;
        algebra = gen-algebra.lib;
        bind = gen-bind.lib;
        genGraph = gen-graph.lib;
        genSchema = gen-schema.lib;
        genTypes = gen-types.lib;
      };
      # gen-algebra's fold, exposed directly to the value-parity + label-opacity suites (the real
      # fold, byte-identity is the Spike 5 acceptance gate).
      genAlgebra = gen-algebra.lib;
      genBind = gen-bind.lib;
    in
    gen.lib.mkCi {
      inherit inputs;
      name = "gen-settings";
      testModules = ./tests;
      # `nix run ./ci#perf-bench` — the driver for ci/perf-bench.nix.
      extraModules = [ ./perf-bench-app.nix ];
      specialArgs = {
        inherit genSettings genAlgebra genBind;
      };
    };
}
