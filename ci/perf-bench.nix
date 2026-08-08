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
#   REPRODUCE (from a checkout of this repo; ARMS are two lib/ trees):
#
#     git worktree add /tmp/gs-incumbent <parent-rev>
#     for arm in /tmp/gs-incumbent/lib ./lib; do
#       for n in 8 10 12 14 16; do
#         NIX_SHOW_STATS=1 NIX_SHOW_STATS_PATH=/tmp/stats.json \
#           nix eval --impure --json --expr "import ./ci/perf-bench.nix {
#             srcs = { gen-settings = $arm; gen-prelude = <gen-prelude>/lib;
#                      gen-algebra = <gen-algebra>/lib; gen-bind = <gen-bind>/lib;
#                      gen-graph = <gen-graph>/lib; };
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
  srcs, # { gen-settings, gen-prelude, gen-algebra, gen-bind, gen-graph } — lib/ paths
  stack, # "acyclic" (the always-taken path) | "backedge" (the positive control)
  n,
}:
let
  prelude = import srcs.gen-prelude;
  algebra = import srcs.gen-algebra { inherit prelude; };
  bind = import srcs.gen-bind { inherit prelude; };
  genGraph = import srcs.gen-graph { inherit prelude; };

  libFn = import srcs.gen-settings;
  gs = libFn (
    builtins.intersectAttrs (builtins.functionArgs libFn) {
      inherit
        prelude
        algebra
        bind
        genGraph
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
  # deepSeq forces the whole cycle computation — the thing being counted. Returning the count also
  # makes the two arms comparable: a run in which the revisions disagree here is not a fair
  # measurement of the same work.
  cycles = builtins.deepSeq g.cycles (builtins.length g.cycles);
}
