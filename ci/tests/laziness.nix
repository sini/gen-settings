# T9 laziness (L15). Four scoped guarantees. resolveOne (L15.2): a field never read is never
# resolved — its contribution values are never forced and its refs never followed. Injection
# (L15.1): wrap time forces nothing in settings/bindings. resolveAll (L15.3): strict in structure
# but an unread field's FOLD is never computed and resolveRef is never called for it — the deliberate
# contrast with T5's WHNF strictness pin.
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
    injectAspectSettings
    ref
    ;
  fx = import ./_fixtures/fixtures.nix { inherit lib; };
  inherit (fx.aspects) theme terminal;
  member = schema: layers: { inherit schema layers; };

  # ── L15.2: an unread field's throwing contribution is never forced ──
  schema2 = mkSchema {
    aspect = theme;
    fields = {
      a = {
        default = "da";
      };
      b = {
        default = "db";
      };
    };
  };
  res2 = resolveOne {
    schema = schema2;
    layers = [
      (fx.mkLayer {
        value = {
          a = "va";
          b = throw "b forced";
        };
      })
    ];
  };

  # ── L15.2: a provenance-only consumer of `a` doesn't force `b`'s ref substitution ──
  sentinelRef = { aspect, path }: throw "resolveRef called for an unread field";
  schemaRefUnread = mkSchema {
    aspect = theme;
    fields = {
      a = {
        default = "da";
      };
      b = {
        default = ref terminal [ "x" ];
      };
    };
  };
  resRefUnread = resolveOne {
    schema = schemaRefUnread;
    layers = [ ];
    resolveRef = sentinelRef;
  };

  # ── L15.1: injection forces nothing in settings ──
  injLazy = injectAspectSettings {
    aspect = theme;
    classContent = { settings, ... }: { config.x = 1; };
    settings = {
      theme = {
        boom = throw "settings forced at wrap time";
      };
    };
  };

  # ── L15.3: resolveAll — an unread field's FOLD is never computed ──
  # `b` is append-strategy with a WHNF-fine but un-append-able contribution (an int): the graph scan
  # forces it to WHNF (fine), but folding `[] ++ 42` throws only if `b` is read. Reading `a` doesn't.
  batchUnfolded = [
    (member
      (mkSchema {
        aspect = theme;
        fields = {
          a = {
            default = "da";
          };
          b = {
            default = [ ];
            merge = "append";
          };
        };
      })
      [
        (fx.mkLayer {
          value = {
            a = "va";
            b = 42;
          };
        })
      ]
    )
  ];
  resUnfolded = resolveAll { batch = batchUnfolded; };

  # ── L15.3: resolveRef never called for a ref in an unread field ──
  batchRefUnread = [
    (member (mkSchema {
      aspect = theme;
      fields = {
        a = {
          default = "da";
        };
        b = {
          default = ref fx.aspects.absent [ "x" ]; # would be E4 if resolved
        };
      };
    }) [ ])
  ];
  resBatchRefUnread = resolveAll { batch = batchRefUnread; };
in
{
  flake.tests.laziness = {
    # L15.2 — reading `a` succeeds though `b`'s contribution throws.
    test-resolveone-unread-not-forced = {
      expr = res2.value.a;
      expected = "va";
    };
    # L15.2 — a provenance-only consumer of `a` doesn't follow `b`'s ref (sentinel uncalled).
    test-resolveone-prov-a-no-ref-follow = {
      expr = map (e: e.value) resRefUnread.provenance.a;
      expected = [ "da" ];
    };

    # L15.1 — wrap forces nothing in settings; `wrapped` is computable with a throwing settings value.
    test-injection-wrap-lazy = {
      expr = injLazy.wrapped;
      expected = true;
    };

    # L15.3 — reading `a` from resolveAll succeeds though folding `b` would throw (fold not computed).
    test-resolveall-unread-fold-not-computed = {
      expr = resUnfolded.value.theme.a;
      expected = "va";
    };
    # L15.3 — resolveRef never called for a ref in an unread field (would be E4 otherwise).
    test-resolveall-unread-ref-not-followed = {
      expr = resBatchRefUnread.value.theme.a;
      expected = "da";
    };
  };
}
