# T6 resolution-errors (L10, L11). Error addressing names both endpoints (no bare name without its
# identity rendering); identity in ≡ identity out. Error codes E1 (schema shape), E2 (strict unknown
# field), E4 (target not in batch), E5 (bad path), E6 (non-identity ref target), E7 (duplicate key).
#
# Pure Nix cannot capture a throw's *message* (builtins.tryEval yields only success:bool), so message
# goldens are pinned via renderAddress (T5 for E3) and the render components below; the error CODES
# are pinned by asserting the throw fires (success == false) at the specified force point.
{
  lib,
  genSettings,
  ...
}:
let
  inherit (genSettings)
    mkSchema
    resolveOne
    resolveAll
    refGraph
    ref
    refsIn
    ;
  fx = import ./_fixtures/fixtures.nix { inherit lib; };
  inherit (fx.aspects) theme terminal;

  throws = e: (builtins.tryEval (builtins.deepSeq e e)).success == false;
  member = schema: layers: { inherit schema layers; };

  # E4 — target aspect absent from the batch.
  batchE4 = [
    (member (mkSchema {
      aspect = theme;
      fields = {
        f = {
          default = ref fx.aspects.absent [ "x" ];
        };
      };
    }) [ ])
  ];

  # E5 — target present, path component absent in its resolved value.
  batchE5 = [
    (member (mkSchema {
      aspect = theme;
      fields = {
        f = {
          default = ref terminal [ "nope" ];
        };
      };
    }) [ ])
    (member (mkSchema {
      aspect = terminal;
      fields = {
        g = {
          default = "G";
        };
      };
    }) [ ])
  ];

  # E7 — duplicate batch key.
  batchE7 = [
    (
      member (mkSchema {
        aspect = theme;
        fields = {
          f = {
            default = 1;
          };
        };
      }) [ ]
      // {
        key = "dup";
      }
    )
    (
      member (mkSchema {
        aspect = terminal;
        fields = {
          g = {
            default = 2;
          };
        };
      }) [ ]
      // {
        key = "dup";
      }
    )
  ];

  # E2 — strict-mode undeclared contribution (non-throwing value: attr-name-level detection).
  resE2 = resolveOne {
    schema = mkSchema {
      aspect = theme;
      fields = {
        f = {
          default = "d";
        };
      };
    };
    strict = true;
    layers = [
      (fx.mkLayer {
        value = {
          extra = "u";
        };
      })
    ];
  };
in
{
  flake.tests.resolution-errors = {
    # E1 — schema shape violations.
    test-e1-dotted-key = {
      expr = throws (mkSchema {
        aspect = theme;
        fields = {
          "a.b" = {
            default = 1;
          };
        };
      });
      expected = true;
    };
    test-e1-missing-default = {
      expr = throws (mkSchema {
        aspect = theme;
        fields = {
          x = {
            merge = "replace";
          };
        };
      });
      expected = true;
    };
    test-e1-bad-merge = {
      expr = throws (mkSchema {
        aspect = theme;
        fields = {
          x = {
            default = 1;
            merge = "bogus";
          };
        };
      });
      expected = true;
    };

    # E2 — strict unknown field, at first force of the result.
    test-e2-strict-unknown = {
      expr = throws resE2.value;
      expected = true;
    };

    # E4 / E5 — resolution addressing (both endpoints; fires when the field is forced).
    test-e4-target-absent = {
      expr = throws (resolveAll { batch = batchE4; }).value;
      expected = true;
    };
    test-e5-bad-path = {
      expr = throws (resolveAll { batch = batchE5; }).value;
      expected = true;
    };

    # E6 — ref rejects non-identity targets at application time.
    test-e6-string-target = {
      expr = throws (ref "theme" [ "x" ]);
      expected = true;
    };
    test-e6-no-idhash = {
      expr = throws (ref { name = "x"; } [ "f" ]);
      expected = true;
    };

    # E7 — duplicate batch key.
    test-e7-duplicate-key = {
      expr = throws (resolveAll { batch = batchE7; }).value;
      expected = true;
    };

    # L11 — identity in ≡ out: a ref carries the given entry (same id_hash), never a string.
    test-l11-ref-identity = {
      expr = (lib.head (refsIn (ref theme [ "x" ]))).aspect.id_hash;
      expected = theme.id_hash;
    };
    # L11 — graph node aspects are the identical input entries (id_hash-equal).
    test-l11-graph-node-identity = {
      expr = lib.any (n: n.aspect.id_hash == theme.id_hash) (refGraph batchE5).nodes;
      expected = true;
    };
  };
}
