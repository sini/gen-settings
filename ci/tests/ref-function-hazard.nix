# T9 ref-function-hazard. The ref scan's domain is DATA, and a function in a scanned position is
# refused by name rather than treated as a leaf.
#
# ── WHY THIS FILE EXISTS, WHEN EVERY OTHER SUITE IS ALREADY GREEN ──
# A scan that skips functions and a scan that refuses them are indistinguishable on every ordinary
# value, so the rest of the suite passes identically under either and cannot see this contract at
# all. Each pair below therefore runs its DATA arm as a positive control in the same evaluation as
# its FUNCTION arm: the data arm is unchanged by the disposition (it is one hop, or it refuses the
# cycle, under both scans), and the function arm flips. Without the pair a regression back to the
# skipping scan would pass in silence — the shape T5 records for a false-green E3.
#
# The refusal is the by-construction disposition of a failure that was OPEN: a ref inside a closure
# is unreachable to any structural scan (Nix exposes no primitive that inspects a function body), so
# the edge could not be derived, the cycle it would have closed went undetected, and the unresolved
# ref record then leaked into consumer output AS DATA. Refusing eliminates the underivable case
# instead of asserting it unanalysable, which keeps every dependence fact this library reports a
# derived one — the totality Mokhov's static extraction has by typing (ICFP 2018, §3). It costs
# nothing on conforming input: a schema is plain data by its own contract, only class *content*
# being parametric and that content *consuming* resolved settings.
{
  lib,
  genSettings,
  ...
}:
let
  inherit (genSettings)
    mkSchema
    refsIn
    refGraph
    assertAcyclic
    ref
    ;
  fx = import ./_fixtures/fixtures.nix { inherit lib; };
  inherit (fx.aspects) theme terminal;

  throws = e: (builtins.tryEval (builtins.deepSeq e e)).success == false;

  member = schema: layers: { inherit schema layers; };
  onlyDefault =
    aspect: field: value:
    member (mkSchema {
      inherit aspect;
      fields = {
        ${field} = {
          default = value;
        };
      };
    }) [ ];

  # ── pair 1: the same ref value, once as data and once inside a function body ──
  r = ref terminal [ "g" ];
  refInData = {
    k = r;
  };
  refInFunction = {
    k = _: r;
  };

  # ── pair 2: the same 2-cycle theme.f -> terminal.g -> theme.f, with the back edge routed
  #    once wholly through data and once with one hop inside a function body ──
  cyclicData = [
    (onlyDefault theme "f" (ref terminal [ "g" ]))
    (onlyDefault terminal "g" (ref theme [ "f" ]))
  ];
  cyclicViaFn = [
    (onlyDefault theme "f" (ref terminal [ "g" ]))
    (onlyDefault terminal "g" (_: ref theme [ "f" ]))
  ];
  # E3 fires from `cycles`, which is why the force point is the cycle list, not the graph record.
  graphRefuses = batch: throws (assertAcyclic (refGraph batch)).cycles;
in
{
  flake.tests.ref-function-hazard = {
    # ── pair 1 ──
    # CONTROL: a ref in data is one hop. Unchanged by the disposition.
    test-control-ref-in-data-is-one-hop = {
      expr = builtins.length (refsIn refInData);
      expected = 1;
    };
    # THE DISCRIMINATOR: the same ref inside a function body is REFUSED. Under the skipping scan
    # this evaluates to `[ ]` without throwing and the assertion goes red.
    test-ref-in-function-body-is-refused = {
      expr = throws (refsIn refInFunction);
      expected = true;
    };
    # CONTROL: ordinary settings data is untouched, so `throws` is not stuck true.
    test-control-plain-data-is-accepted = {
      expr = throws (refsIn {
        a = 1;
        b = [ "x" ];
        c = {
          d = "e";
        };
      });
      expected = false;
    };

    # ── pair 2: the same contract as seen through the graph, which is where it MATTERS ──
    # CONTROL: a cycle wholly in data refuses (E3). Unchanged by the disposition.
    test-control-cycle-in-data-refuses = {
      expr = graphRefuses cyclicData;
      expected = true;
    };
    # THE DISCRIMINATOR, at the level a consumer feels: with one hop inside a function body the
    # skipping scan derives no back edge, reports NO cycle, and lets the unresolved ref through as
    # data. The refusing scan stops it.
    test-cycle-hidden-in-a-function-body-refuses = {
      expr = graphRefuses cyclicViaFn;
      expected = true;
    };
    # CONTROL: an acyclic batch of the same shape does NOT refuse, so `graphRefuses` can report a
    # true negative and the two rows above are not trivially true.
    test-control-acyclic-batch-does-not-refuse = {
      expr = graphRefuses [
        (onlyDefault theme "f" (ref terminal [ "g" ]))
        (onlyDefault terminal "g" "concrete")
      ];
      expected = false;
    };
  };
}
