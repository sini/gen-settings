# Cycle-detection cost workload — the instrument behind the extraction's performance claim.
#
# WHAT IS MEASURED. `refGraph` computes `cycles` over the field-address graph. A correct
# configuration is ACYCLIC, so the cycle check finds nothing — on every evaluation. That makes the
# acyclic case the ALWAYS-TAKEN path, and it is what this workload prices. The `backedge` arm is
# the positive control: it closes the chain so the detector must fire, which is what makes the
# acyclic arm's `cycles = 0` a real absence rather than a dead predicate.
#
# THE WORKLOAD. An acyclic diamond chain over one aspect's fields — a_i -> b_i, a_i -> c_i,
# b_i -> a_{i+1}, c_i -> a_{i+1}, terminating at a_n. It has 2^n simple paths, 3n+1 nodes and zero
# cycles: a cycle finder that walks simple paths pays exponentially here while one that asks only
# "is any node self-reachable" does not.
#
# THE TWO ARMS are two REVISIONS of this library, selected by `srcs.gen-settings`. `lib/default.nix`
# gained a `genGraph` formal in the migrated revision, so the argument set is intersected with the
# imported function's own formals — that is what lets one workload file drive both revisions
# unmodified, and it is load-bearing, not a convenience.
#
# This file only DEFINES the workload. Counters come from NIX_SHOW_STATS; see the re-run recipe
# below. `nrFunctionCalls` is the reported figure because it is deterministic across runs;
# `cpuTime` is noisy at this size and is read only as a sanity check, never quoted alone.
#
#   REPRODUCE, the wired way. It drives this file over the current tree, checks both controls and
#   gates on the growth condition below:
#
#     nix run ./ci#perf-bench
#
#   Point it at a second revision for the two-arm table:
#
#     git worktree add /tmp/gs-base <parent-rev>
#     PERF_BASELINE_LIB=/tmp/gs-base/lib nix run ./ci#perf-bench
#
#   REPRODUCE by hand. `srcs` entries are FILESYSTEM PATHS to each library's `lib/` directory —
#   not `<name>` search-path lookups, which resolve only if you also pass a matching `-I` (bare
#   `nix eval --impure --expr '<gen-prelude>'` fails with "not found in the Nix search path").
#   `gen-schema` is the one exception and points at the REPOSITORY ROOT: its library also needs
#   gen-merge, so it goes through gen-schema's own standalone entry, as `default.nix` does.
#
#     GP=/path/to/gen-prelude/lib; GA=/path/to/gen-algebra/lib
#     GB=/path/to/gen-bind/lib;    GG=/path/to/gen-graph/lib
#     GT=/path/to/gen-types/lib;   GS=/path/to/gen-schema
#     for arm in /tmp/gs-base/lib ./lib; do
#       for n in 8 10 12 14 16; do
#         NIX_SHOW_STATS=1 NIX_SHOW_STATS_PATH=/tmp/stats.json \
#           nix eval --impure --json --expr "import ./ci/perf-bench.nix {
#             srcs = { gen-settings = $arm; gen-prelude = $GP;
#                      gen-algebra = $GA; gen-bind = $GB; gen-graph = $GG;
#                      gen-types = $GT; gen-schema = $GS; };
#             stack = \"acyclic\"; n = $n; }"
#         jq .nrFunctionCalls /tmp/stats.json
#       done
#     done
#
#   Then repeat with stack = "backedge" (the control must report a NON-ZERO cycle count on BOTH
#   arms; a run where either side reports 0 there invalidates the corresponding acyclic zero).
#
#   ACCEPTANCE. The extraction's claim is that the incumbent's cost is exponential on the acyclic
#   path and the successor's is not. It is REFUTED if the migrated arm's `nrFunctionCalls` still
#   multiplies by ~4 for each +2 in `n`. Stating the refutation condition is what makes this a
#   measurement rather than a boast.
{
  srcs, # { gen-settings, gen-prelude, gen-algebra, gen-bind, gen-graph, gen-types } — lib/ paths;
  # plus gen-schema, which is a REPOSITORY ROOT (see the note above)
  stack, # "acyclic" (the always-taken path) | "backedge" (the positive control)
  n,
}:
let
  prelude = import srcs.gen-prelude;
  algebra = import srcs.gen-algebra { inherit prelude; };
  bind = import srcs.gen-bind { inherit prelude; };
  genGraph = import srcs.gen-graph { inherit prelude; };
  genTypes = import srcs.gen-types { inherit prelude; };
  genSchema = import srcs.gen-schema { inherit prelude algebra; };

  libFn = import srcs.gen-settings;
  gs = libFn (
    builtins.intersectAttrs (builtins.functionArgs libFn) {
      inherit
        prelude
        algebra
        bind
        genGraph
        genSchema
        genTypes
        ;
    }
  );
  inherit (gs) mkSchema refGraph ref;

  A = {
    name = "chain";
    id_hash = "a1b2c3d4deadbeef";
  };
  s = toString;
  idx = builtins.genList (i: i) n;

  # The chain's terminal field: inert under "acyclic", a back-edge to a0 under "backedge".
  terminal =
    if stack == "backedge" then
      ref A [ "a0" ]
    else if stack == "acyclic" then
      "leaf"
    else
      throw "perf-bench: stack must be \"acyclic\" or \"backedge\", got ${toString stack}";

  fields =
    builtins.listToAttrs (
      builtins.concatMap (i: [
        {
          name = "a${s i}";
          value.default = [
            (ref A [ "b${s i}" ])
            (ref A [ "c${s i}" ])
          ];
        }
        {
          name = "b${s i}";
          value.default = ref A [ "a${s (i + 1)}" ];
        }
        {
          name = "c${s i}";
          value.default = ref A [ "a${s (i + 1)}" ];
        }
      ]) idx
    )
    // {
      "a${s n}".default = terminal;
    };

  g = refGraph [
    {
      schema = mkSchema {
        aspect = A;
        inherit fields;
      };
      layers = [ ];
    }
  ];
in
{
  nodes = builtins.length g.nodes;
  # deepSeq forces the whole cycle computation — the thing being counted. Under `acyclic` the
  # count is 0 on any correct revision, so two arms disagreeing THERE are not measuring the same
  # work. Under `backedge` they may legitimately differ (a per-start-node contract reports one
  # cycle per start, a per-component contract reports one per component); what the control
  # requires there is only that both are NON-ZERO.
  cycles = builtins.deepSeq g.cycles (builtins.length g.cycles);
}
