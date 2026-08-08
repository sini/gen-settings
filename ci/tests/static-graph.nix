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
    renderAddress
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
      map (
        e: "${e.from.aspect.name}.${e.from.field} -> ${e.to.aspect.name}.${e.to.field}"
      ) g.edges
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

  # E3 rendering, recomputed from the graph's cycle data exactly as assertAcyclic renders it.
  renderCycle =
    cyc:
    let
      addrs = map (a: renderAddress { inherit (a) aspect field; }) cyc;
    in
    lib.concatStringsSep " -> " (addrs ++ [ (lib.head addrs) ]);
  # The whole E3 body, including the "; " join BETWEEN cycles — the only place multiplicity
  # reaches the reader, and the reason a multi-cycle fixture is pinned at the message level.
  renderCycles = g: lib.concatStringsSep "; " (map renderCycle g.cycles);

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
      expr = renderCycle (lib.head graph2.cycles);
      expected = "aspect(theme#a1b2c3d4).f -> aspect(terminal#e5f6a7b8).g -> aspect(theme#a1b2c3d4).f";
    };
    # E3 message golden, DISCRIMINATING — the cycle is reported in traversal order, so every
    # " -> " in the body is a real edge. A cycle finder that reports membership sorted by key
    # renders `theme.f -> terminal.g` here, which is not an edge of this graph.
    test-e3-message-golden-discriminating = {
      expr = renderCycle (lib.head graph3Discriminating.cycles);
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
      expr = renderCycles graphFigureEight;
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
      expr = renderCycles graphDisjointCycles;
      expected = "aspect(nginx#00112233).k -> aspect(firewall#f1f2f3f4).h -> aspect(nginx#00112233).k; aspect(theme#a1b2c3d4).f -> aspect(terminal#e5f6a7b8).g -> aspect(theme#a1b2c3d4).f";
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
  };
}
