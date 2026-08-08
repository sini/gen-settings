# Driver for ci/perf-bench.nix. Sourced into a writeShellApplication by ci/perf-bench-app.nix,
# which supplies PERF_WORKLOADS and PERF_SRCS.
#
# Three jobs, in order of what they protect:
#   1. ANTI-ROT — evaluate the workload against the current tree. A `lib/default.nix` signature
#      change breaks this loudly instead of leaving a stranded file nobody runs.
#   2. CONTROLS — acyclic must report 0 cycles, backedge must report a NON-ZERO count. A zero on
#      the backedge arm means the detector is dead and every acyclic zero is worthless.
#   3. THE GROWTH GATE — the extraction's claim is that cost on the always-taken (acyclic) path is
#      no longer exponential. The incumbent multiplied nrFunctionCalls by ~4.00 per +2 in n, so
#      n=12 -> n=16 was ~16x. This fails the run if that ratio returns.
set -uo pipefail

LIB="${PERF_LIB:-$(git rev-parse --show-toplevel)/lib}"
BASELINE="${PERF_BASELINE_LIB:-}"
STATS=$(mktemp -d)/stats.json

# eval ARM_LIB STACK N -> prints "<nrFunctionCalls> <nodes> <cycles>"
run_cell() {
  local arm="$1" stack="$2" n="$3" out
  out=$(NIX_SHOW_STATS=1 NIX_SHOW_STATS_PATH="$STATS" nix eval --impure --json --expr \
    "import $PERF_WORKLOADS { srcs = (import $PERF_SRCS) // { gen-settings = $arm; }; stack = \"$stack\"; n = $n; }") || {
    echo "PERF-BENCH FAIL: workload did not evaluate (arm=$arm stack=$stack n=$n)" >&2
    echo "  Either the workload is out of step with the library it measures, or a gen-* flake" >&2
    echo "  input is older than a surface lib/ now calls. A missing-attribute error naming a" >&2
    echo "  sibling library is the second: bump ci/flake.lock, or pass --override-input." >&2
    return 1
  }
  echo "$(jq -r .nrFunctionCalls "$STATS") $(jq -r .nodes <<<"$out") $(jq -r .cycles <<<"$out")"
}

rc=0
NS=(8 10 12 14 16)

printf '%-10s %-6s %-8s %-14s %-8s\n' arm n nodes nrFunctionCalls cycles
declare -A CALLS
for armspec in "current:$LIB" ${BASELINE:+"baseline:$BASELINE"}; do
  armname="${armspec%%:*}"; armlib="${armspec#*:}"
  for n in "${NS[@]}"; do
    read -r calls nodes cycles < <(run_cell "$armlib" acyclic "$n") || { rc=1; continue; }
    printf '%-10s %-6s %-8s %-14s %-8s\n' "$armname" "$n" "$nodes" "$calls" "$cycles"
    CALLS[$armname:$n]=$calls
    # CONTROL 1 — the always-taken path really is acyclic.
    if [ "$cycles" != "0" ]; then
      echo "PERF-BENCH FAIL: acyclic arm reported $cycles cycles at n=$n (expected 0)" >&2
      rc=1
    fi
  done
  # CONTROL 2 — the detector fires. Without this every zero above is unfalsifiable.
  read -r _ _ bcycles < <(run_cell "$armlib" backedge 6) || { rc=1; continue; }
  if [ "$bcycles" = "0" ]; then
    echo "PERF-BENCH FAIL: backedge control reported 0 cycles on '$armname' — detector is dead," >&2
    echo "  so the acyclic zeros above are not evidence of anything" >&2
    rc=1
  else
    echo "control: backedge n=6 on '$armname' => $bcycles cycles (non-zero, as required)"
  fi

  # THE GROWTH GATE — refutation condition from the spec, made executable.
  a=${CALLS[$armname:12]:-} ; b=${CALLS[$armname:16]:-}
  if [ -n "$a" ] && [ -n "$b" ] && [ "$a" -gt 0 ]; then
    pct=$(( b * 100 / a ))
    echo "growth: '$armname' n=12 -> n=16 is ${pct}% (exponential would be ~1600%)"
    if [ "$armname" = "current" ] && [ "$pct" -ge 800 ]; then
      echo "PERF-BENCH FAIL: current tree grew ${pct}% from n=12 to n=16." >&2
      echo "  The claim that cost on the acyclic path is no longer exponential is REFUTED." >&2
      rc=1
    fi
  fi
done

[ "$rc" -eq 0 ] && echo "perf-bench: OK"
exit "$rc"
