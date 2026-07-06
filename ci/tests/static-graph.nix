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
  inherit (fx.aspects) theme terminal firewall;

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
