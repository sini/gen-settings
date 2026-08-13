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
    resolveOne
    resolveAll
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

  # ── pair 3: the same contract at the SUBSTITUTION rather than the scan ──
  # One `resolveOne` application per construction, so the two halves asserted below come from ONE
  # call. The constructions differ in exactly one thing: whether the ref sits in the field's value
  # or inside a function body in it.
  substSubject =
    value:
    resolveOne {
      schema = mkSchema {
        aspect = theme;
        fields = {
          f = {
            default = value;
          };
        };
      };
      layers = [ ];
      resolveRef = _: "RESOLVED";
    };
  oneFn = substSubject (_: r);
  oneData = substSubject r;
  bothHalves = one: [
    (throws one.value)
    (throws one.provenance)
  ];
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

    # ── pair 3: the SUBSTITUTION's half of the same domain ──
    # The scan derives the graph; substitution produces the value. If substitution admitted an
    # input the scan refuses, a value would be produced from an input no edge was ever derived
    # over — so the two must accept the same inputs, and the pairs above see only one of them.
    #
    # THE DISCRIMINATOR, and it is `resolveOne`: its VALUE half reaches the substitution without
    # passing the scan, so this pair is where the two could disagree and did. Asserted as a list of
    # both halves of one call rather than a conjunction, so a failure names which half — under the
    # skipping dispatch this cell read `[ false true ]`, the value arm handing back the lambda
    # while the provenance arm of the very same call refused it.
    test-one-call-refuses-the-function-on-both-halves = {
      expr = bothHalves oneFn;
      expected = [
        true
        true
      ];
    };
    # CONTROL: the same construction with the ref in DATA answers on both halves, so the row above
    # is not satisfied by a resolver that refuses everything.
    test-control-one-call-resolves-the-ref-in-data-on-both-halves = {
      expr = bothHalves oneData;
      expected = [
        false
        false
      ];
    };
    # CONTROL: and it SUBSTITUTES rather than merely not throwing — the ref does not survive.
    test-control-substitution-replaces-the-ref-in-data = {
      expr = oneData.value.f;
      expected = "RESOLVED";
    };

    # REGRESSION, NOT A DISCRIMINATOR, and the distinction is the point. `resolveAll` gates on the
    # graph before any value, so the scan refuses the function before substitution is ever reached
    # and this pair reads the same on both sides of the dispatch change. It is here because the
    # value-level behaviour of the other public resolver is worth holding, not because it can see
    # what pair 3 sees.
    test-resolveAll-refuses-the-function-before-any-value = {
      expr =
        throws
          (resolveAll {
            batch = [
              (onlyDefault theme "f" (_: r))
              (onlyDefault terminal "g" "G")
            ];
          }).value;
      expected = true;
    };
    test-control-resolveAll-resolves-the-ref-in-data = {
      expr =
        (resolveAll {
          batch = [
            (onlyDefault theme "f" r)
            (onlyDefault terminal "g" "G")
          ];
        }).value.theme.f;
      expected = "G";
    };
  };
}
