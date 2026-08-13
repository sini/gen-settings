{
  inputs = {
    gen-harness.url = "github:sini/gen-harness";
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
      gen-harness,
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
      # The minting authority, exposed directly to the identity-keying suite so its expectation is
      # computed by calling the primitive rather than transcribed from it.
      genSchema = gen-schema.lib;
    in
    gen-harness.lib.mkCi {
      inherit inputs;
      name = "gen-settings";
      # `testModules` is the whole of `flake.tests`, and `flake.tests` is the whole of what the
      # batch asserter behind `checks.default` quantifies over. Cells whose `expr` CAN ABORT cannot
      # live there — the asserter forces every `expr` unconditionally, so such a cell crashes the
      # gate rather than failing it. They are therefore outside this tree by construction, on their
      # own output: `./tests-error.nix`, read by `nix-unit --flake ./ci#testsError`.
      testModules = ./tests;
      extraModules = [
        # `nix run ./ci#perf-bench` — the driver for ci/perf-bench.nix.
        ./perf-bench-app.nix
        # `flake.testsError` + its `ci-error` hook.
        ./tests-error.nix
      ];
      specialArgs = {
        inherit
          genSettings
          genAlgebra
          genBind
          genSchema
          ;
      };
    };
}
