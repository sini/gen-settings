# T5 static-graph (L7, L8, L17). The graph is a pure function of schemas + layer values, computed
# before any resolution and CONSERVATIVE over pre-fold values (Mokhov et al., ICFP 2018 §3). No
# resolution during construction (L7); definition-time acyclicity at first force (L8); structural
# strictness + conservativeness (L17). Cycle detection: 2-cycle, self-loop, 3-cycle, and the
# permissive field-granular non-cycle.
{
  lib,
  genSettings,
  ...
}:
let
  inherit (genSettings)
    mkSchema
    resolveAll
    refGraph
    assertAcyclic
    ref
    renderCycles
    ;
  fx = import ./_fixtures/fixtures.nix { inherit lib; };
  inherit (fx.aspects)
    theme
    terminal
    firewall
    nginx
    ;

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

  # ── 2-cycle: theme.f -> terminal.g -> theme.f ──
  batch2 = [
    (onlyDefault theme "f" (ref terminal [ "g" ]))
    (onlyDefault terminal "g" (ref theme [ "f" ]))
  ];
  graph2 = refGraph batch2;

  # ── self-loop: theme.f -> theme.f ──
  graphSelf = refGraph [ (onlyDefault theme "f" (ref theme [ "f" ])) ];

  # ── 3-cycle: theme.f -> terminal.g -> firewall.h -> theme.f ──
  graph3 = refGraph [
    (onlyDefault theme "f" (ref terminal [ "g" ]))
    (onlyDefault terminal "g" (ref firewall [ "h" ]))
    (onlyDefault firewall "h" (ref theme [ "f" ]))
  ];

  # ── 3-cycle whose TRAVERSAL order and KEY order disagree: theme.f -> firewall.h ->
  # terminal.g -> theme.f, while the node keys sort a1b2…:f < e5f6…:g < f1f2…:h. graph3 above
  # cannot tell a traversal from a key-sorted set — its id_hashes happen to ascend along its
  # traversal direction — so this fixture is what discriminates a cycle PATH from mere cycle
  # MEMBERSHIP. Rendering a membership set with " -> " asserts edges the graph does not contain.
  graph3Discriminating = refGraph [
    (onlyDefault theme "f" (ref firewall [ "h" ]))
    (onlyDefault firewall "h" (ref terminal [ "g" ]))
    (onlyDefault terminal "g" (ref theme [ "f" ]))
  ];

  # ── figure-eight: ONE component holding TWO distinct simple cycles, theme.f -> terminal.g ->
  # theme.f and theme.f -> firewall.h -> theme.f. The reported cycle is one REPRESENTATIVE per
  # component, so the multiplicity here is 1 while the component's cycle count is 2. Its edge set
  # is asserted below so the fixture cannot silently stop being a figure-eight.
  graphFigureEight = refGraph [
    (onlyDefault theme "f" [
      (ref terminal [ "g" ])
      (ref firewall [ "h" ])
    ])
    (onlyDefault terminal "g" (ref theme [ "f" ]))
    (onlyDefault firewall "h" (ref theme [ "f" ]))
  ];
  # Edge set as "A.f -> B.g" strings — the structural premise that this IS a figure-eight.
  edgeStrings =
    g:
    lib.sort lib.lessThan (
      map (e: "${e.from.aspect.name}.${e.from.field} -> ${e.to.aspect.name}.${e.to.field}") g.edges
    );

  # ── two DISJOINT cyclic components: theme.f <-> terminal.g and firewall.h <-> nginx.k. This is
  # the shape that reports more than one cycle, and therefore the only one that exercises
  # assertAcyclic's "; " join between cycles.
  graphDisjointCycles = refGraph [
    (onlyDefault theme "f" (ref terminal [ "g" ]))
    (onlyDefault terminal "g" (ref theme [ "f" ]))
    (onlyDefault firewall "h" (ref nginx [ "k" ]))
    (onlyDefault nginx "k" (ref firewall [ "h" ]))
  ];

  # ── permissive (field-granular, NO cycle): theme.f -> terminal.g, terminal.h -> theme.k ──
  batchPermissive = [
    (member (mkSchema {
      aspect = theme;
      fields = {
        f = {
          default = ref terminal [ "g" ];
        };
        k = {
          default = "K";
        };
      };
    }) [ ])
    (member (mkSchema {
      aspect = terminal;
      fields = {
        g = {
          default = "G";
        };
        h = {
          default = ref theme [ "k" ];
        };
      };
    }) [ ])
  ];
  graphPermissive = refGraph batchPermissive;
  resPermissive = resolveAll { batch = batchPermissive; };

  # ── L17a: cycle whose theme.f ref lives in a DEFAULT shadowed by a replace layer ──
  batchShadowedCycle = [
    (member
      (mkSchema {
        aspect = theme;
        fields = {
          f = {
            default = ref terminal [ "g" ];
          };
        };
      })
      [
        (fx.mkLayer {
          value = {
            f = "concrete";
          };
        })
      ]
    )
    (onlyDefault terminal "g" (ref theme [ "f" ]))
  ];
  graphShadowedCycle = refGraph batchShadowedCycle;

  # ── L17b: a throwing scalar in a shadowed contribution of an unread-under-replace field ──
  batchThrow = [
    (member
      (mkSchema {
        aspect = theme;
        fields = {
          x = {
            default = "d";
          };
        };
      })
      [
        (fx.mkLayer {
          value = {
            x = throw "boom";
          };
        })
        (fx.mkLayer {
          value = {
            x = "win";
          };
        })
      ]
    )
  ];

  # E3 goldens call the SHIPPED renderer (`genSettings.renderCycles`, lib/graph.nix) — the same
  # binding assertAcyclic interpolates into its throw. A local re-implementation would stay green
  # when the shipped rendering changed, which is the one thing these goldens exist to catch.
  # A throw's message is unreachable to builtins.tryEval, which yields only `success`, so calling
  # the renderer is the only way a TEST can observe it. (Out of band a `nix eval` run does print
  # the message to stderr, which is how the equivalence here was checked.)

  # ── node-key precedence: a DECLARED address outranks the same key reached as a ref TARGET ──
  # `themeAlias` carries theme's id_hash under a different display name. Identity is the id_hash
  # and names are display only, so both records claim node key `<theme's id_hash>:f` — one as a
  # declared field address, one as the address a ref target names. This is the only fixture in the
  # file that can observe WHICH wins: every other one keys each node from a single source, so all
  # of them stay green under an inverted precedence.
  themeAlias = fx.mkAspect "theme-alias" theme.id_hash;
  graphAliasedTarget = refGraph [
    (onlyDefault theme "f" "F")
    (onlyDefault terminal "g" (ref themeAlias [ "f" ]))
  ];

  cyclicBatch = batch2;
  forced = builtins.tryEval (builtins.deepSeq (resolveAll { batch = cyclicBatch; }).value true);
in
{
  flake.tests.static-graph = {
    # L7 — the graph is pure structure: edges/cycles computed with NO resolver, no resolved value.
    test-graph-pure-no-resolver = {
      expr = lib.length graph2.edges;
      expected = 2;
    };

    # Cycle detection variants.
    test-2-cycle-detected = {
      expr = lib.length graph2.cycles;
      expected = 1;
    };
    test-self-loop-detected = {
      expr = map (a: a.field) (lib.head graphSelf.cycles);
      expected = [ "f" ];
    };
    test-3-cycle-detected = {
      expr = lib.length (lib.head graph3.cycles);
      expected = 3;
    };
    # Permissive: A.f -> B.g and B.h -> A.k is NOT a cycle at field granularity.
    test-permissive-no-cycle = {
      expr = graphPermissive.cycles;
      expected = [ ];
    };
    # ...and it resolves (the knot ties through the acyclic field-address graph).
    test-permissive-resolves = {
      expr = {
        inherit (resPermissive.value.theme) f;
        h = resPermissive.value.terminal.h;
      };
      expected = {
        f = "G";
        h = "K";
      };
    };

    # E3 message golden — rendered addresses, full cycle closing back to its head.
    test-e3-message-golden = {
      expr = renderCycles [ (lib.head graph2.cycles) ];
      expected = "aspect(theme#a1b2c3d4).f -> aspect(terminal#e5f6a7b8).g -> aspect(theme#a1b2c3d4).f";
    };
    # E3 message golden, DISCRIMINATING — the cycle is reported in traversal order, so every
    # " -> " in the body is a real edge. A cycle finder that reports membership sorted by key
    # renders `theme.f -> terminal.g` here, which is not an edge of this graph.
    test-e3-message-golden-discriminating = {
      expr = renderCycles [ (lib.head graph3Discriminating.cycles) ];
      expected = "aspect(theme#a1b2c3d4).f -> aspect(firewall#f1f2f3f4).h -> aspect(terminal#e5f6a7b8).g -> aspect(theme#a1b2c3d4).f";
    };
    # ...and exactly one cycle is reported for the single component it forms.
    test-e3-discriminating-single-cycle = {
      expr = lib.length graph3Discriminating.cycles;
      expected = 1;
    };

    # ── multiplicity, at the MESSAGE level ──
    # PREMISE, asserted so the fixture cannot silently stop discriminating: these four edges are
    # two distinct simple cycles sharing theme.f. If this goes red, the tests below are pinning
    # something other than a figure-eight and prove nothing about multiplicity.
    test-figure-eight-premise-two-cycles-one-component = {
      expr = edgeStrings graphFigureEight;
      expected = [
        "firewall.h -> theme.f"
        "terminal.g -> theme.f"
        "theme.f -> firewall.h"
        "theme.f -> terminal.g"
      ];
    };
    # ...and the component reports ONE representative, not one per cycle. The contract is
    # per-COMPONENT: the SCC is canonical, the cycle through it is existential.
    test-figure-eight-one-representative = {
      expr = lib.length graphFigureEight.cycles;
      expected = 1;
    };
    # The E3 body for that component names a single traversable loop and carries NO "; ".
    test-figure-eight-message-golden = {
      expr = renderCycles graphFigureEight.cycles;
      expected = "aspect(theme#a1b2c3d4).f -> aspect(terminal#e5f6a7b8).g -> aspect(theme#a1b2c3d4).f";
    };

    # Two DISJOINT components are what produce multiplicity > 1, and this is the only fixture in
    # the suite that renders the "; " join between cycles. Ordering is by component tag, so
    # nginx#00112233 precedes theme#a1b2c3d4.
    test-disjoint-cycles-multiplicity = {
      expr = lib.length graphDisjointCycles.cycles;
      expected = 2;
    };
    test-disjoint-cycles-message-golden = {
      expr = renderCycles graphDisjointCycles.cycles;
      expected = "aspect(nginx#00112233).k -> aspect(firewall#f1f2f3f4).h -> aspect(nginx#00112233).k; aspect(theme#a1b2c3d4).f -> aspect(terminal#e5f6a7b8).g -> aspect(theme#a1b2c3d4).f";
    };

    # ── node-key precedence ──
    # PREMISE, asserted so the fixture cannot silently stop discriminating: the two aspect records
    # are the same identity under different names, so they really do collide on one node key.
    test-aliased-target-premise-one-identity-two-names = {
      expr = {
        sameIdentity = themeAlias.id_hash == theme.id_hash;
        differentName = themeAlias.name != theme.name;
      };
      expected = {
        sameIdentity = true;
        differentName = true;
      };
    };
    # ...and the DECLARED address is the one that names the node. `theme-alias` here would mean a
    # node's identity is described by whoever pointed at it rather than by whoever declared it.
    test-declared-address-wins-a-shared-node-key = {
      expr = lib.sort lib.lessThan (map (n: n.aspect.name) graphAliasedTarget.nodes);
      expected = [
        "terminal"
        "theme"
      ];
    };

    # assertAcyclic throws on a cyclic graph, is identity on an acyclic one.
    test-assertAcyclic-throws = {
      expr = (builtins.tryEval (assertAcyclic graph2)).success;
      expected = false;
    };
    test-assertAcyclic-identity = {
      expr = (assertAcyclic graphPermissive) == graphPermissive;
      expected = true;
    };

    # L17a — a cycle reachable only through a shadowed default ref still counts (pre-fold graph).
    test-conservative-shadowed-cycle = {
      expr = lib.length graphShadowedCycle.cycles;
      expected = 1;
    };
    test-conservative-shadowed-cycle-throws = {
      expr =
        (builtins.tryEval (builtins.deepSeq (resolveAll { batch = batchShadowedCycle; }).value true))
        .success;
      expected = false;
    };

    # L8 — an UNforced resolveAll result never throws, even for a cyclic batch.
    test-unforced-never-throws = {
      expr = (builtins.tryEval (resolveAll { batch = cyclicBatch; } ? value)).value;
      expected = true;
    };
    # L8 — forcing the result triggers the cycle check.
    test-forced-throws = {
      expr = forced.success;
      expected = false;
    };

    # L17b — a throwing scalar in any (shadowed, unread-under-replace) contribution throws at force.
    test-structural-strictness-throw = {
      expr =
        (builtins.tryEval (builtins.deepSeq (resolveAll { batch = batchThrow; }).value true)).success;
      expected = false;
    };

    # den-hoag-yk07 — `.graph` is a SECOND view of the same result `.value` gates on, and both must
    # agree about validity. Before the fix this cell was the bug's own witness: `.value` throws E3
    # on this cyclic batch (test-forced-throws above) while `.graph` deepSeq'd clean, because
    # resolveAll returned the unchecked `theGraph` rather than `checkedGraph` under this accessor.
    test-graph-accessor-throws-on-cycle = {
      expr =
        (builtins.tryEval (builtins.deepSeq (resolveAll { batch = cyclicBatch; }).graph true)).success;
      expected = false;
    };
    # Control: on an ACYCLIC batch, assertAcyclic is identity (test-assertAcyclic-identity above),
    # so `.graph` is byte-identical to the raw `refGraph batch` both before and after routing it
    # through the check — this cell would hold unchanged whichever of the two the accessor returns,
    # which is what proves the fix above changes validity-gating and nothing else.
    test-control-graph-accessor-unchanged-on-acyclic-batch = {
      expr = (resolveAll { batch = batchPermissive; }).graph == graphPermissive;
      expected = true;
    };
  };
}
