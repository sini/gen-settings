# `nix run ./ci#perf-bench` — drives ci/perf-bench.nix over the current tree.
#
# An app rather than a check derivation, for the reason the hub's own perf-bench states: counter
# collection needs an un-sandboxed evaluator run. Wiring it matters beyond convenience — an
# unwired workload rots silently the next time `lib/default.nix` changes signature, and no gate
# notices that the figure it underwrites has stopped being reproducible.
{ inputs, ... }:
{
  perSystem =
    { pkgs, ... }:
    let
      # Sibling library paths, resolved from the flake inputs. `gen-settings` is supplied by the
      # driver at runtime so the app measures the working tree, not a pinned copy of itself.
      perfSrcs = pkgs.writeText "perf-srcs.nix" ''
        {
          "gen-prelude" = ${inputs.gen-prelude}/lib;
          "gen-algebra" = ${inputs.gen-algebra}/lib;
          "gen-bind" = ${inputs.gen-bind}/lib;
          "gen-graph" = ${inputs.gen-graph}/lib;
        }
      '';
      perfBench = pkgs.writeShellApplication {
        name = "gen-settings-perf-bench";
        runtimeInputs = [
          pkgs.nix
          pkgs.jq
          pkgs.git
        ];
        text = ''
          export PERF_WORKLOADS=${./perf-bench.nix}
          export PERF_SRCS=${perfSrcs}
        ''
        + builtins.readFile ./perf-bench.sh;
      };
    in
    {
      apps.perf-bench = {
        type = "app";
        program = "${perfBench}/bin/gen-settings-perf-bench";
      };
    };
}
