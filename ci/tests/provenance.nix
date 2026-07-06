# T3 provenance-golden (L5, L6, L9, L15.4). Full per-field provenance chains: default-entry presence
# per strategy, chain ordering, structured entry shape, `via` on a projects-style layer, `refs` hop
# records incl. `at` subpaths, non-strict passthrough (contributor entries only, no default entry),
# and shadowed-ref provenance laziness.
{
  lib,
  genSettings,
  ...
}:
let
  inherit (genSettings)
    mkSchema
    resolveOne
    ref
    ;
  fx = import ./_fixtures/fixtures.nix { inherit lib; };
  theme = fx.aspects.theme;

  resolveRef = { aspect, path }: "R:${lib.concatStringsSep "." path}";
  sentinelRef = { aspect, path }: throw "E4 sentinel: shadowed ref followed";

  # Compact projection of a chain entry (drops the verbose scope record; keeps display + hops).
  proj = e: {
    inherit (e) rendered via refs;
    value = e.value;
  };

  # ── replace + append + recursive chains ──
  schema = mkSchema {
    aspect = fx.aspects.firewall;
    fields = {
      hostname = {
        default = "unset";
      }; # replace
      "allowed-tcp" = {
        default = [ 22 ];
        merge = "append";
      };
    };
  };
  layers = [
    (fx.mkLayer {
      rendered = "env";
      value = {
        hostname = "h1";
        "allowed-tcp" = [ 80 ];
      };
    })
    (fx.mkLayer {
      rendered = "host";
      via = theme; # a projects-style layer carries the projecting aspect
      value = {
        hostname = "h2";
        "allowed-tcp" = [ 443 ];
      };
    })
  ];
  res = resolveOne { inherit schema layers; };

  # ── refs hop records with `at` subpaths ──
  schemaRefs = mkSchema {
    aspect = fx.aspects.terminal;
    fields = {
      cfg = {
        default = { };
        merge = "recursive";
      };
    };
  };
  resRefs = resolveOne {
    schema = schemaRefs;
    layers = [
      (fx.mkLayer {
        rendered = "host";
        value = {
          cfg = {
            k = ref theme [ "font" "mono" ];
          };
        };
      })
    ];
    inherit resolveRef;
  };

  # ── non-strict passthrough ──
  schemaPass = mkSchema {
    aspect = fx.aspects.nginx;
    fields = {
      declared = {
        default = "d";
      };
    };
  };
  resPass = resolveOne {
    schema = schemaPass;
    strict = false;
    layers = [
      (fx.mkLayer {
        rendered = "host";
        value = {
          declared = "x";
          undeclared = "u";
        };
      })
    ];
  };

  # ── shadowed-ref provenance laziness (L15.4) ──
  schemaShadow = mkSchema {
    aspect = fx.aspects.terminal;
    fields = {
      font = {
        default = ref fx.aspects.absent [ "gone" ];
      };
    };
  };
  resShadow = resolveOne {
    schema = schemaShadow;
    layers = [
      (fx.mkLayer {
        rendered = "host";
        value = {
          font = "concrete";
        };
      })
    ];
    resolveRef = sentinelRef;
  };
  shadowChain = resShadow.provenance.font;
in
{
  flake.tests.provenance = {
    # L5 — replace: default entry first, then each contributor, in input order.
    test-replace-chain = {
      expr = map proj res.provenance.hostname;
      expected = [
        {
          rendered = "default";
          via = null;
          refs = [ ];
          value = "unset";
        }
        {
          rendered = "env";
          via = null;
          refs = [ ];
          value = "h1";
        }
        {
          rendered = "host";
          via = theme;
          refs = [ ];
          value = "h2";
        }
      ];
    };
    # L5 — append: default present, contributors show their individual pieces.
    test-append-chain = {
      expr = map (e: e.value) res.provenance."allowed-tcp";
      expected = [
        [ 22 ]
        [ 80 ]
        [ 443 ]
      ];
    };
    # L6 — the default entry's scope is { aspect = schema.aspect } (identity in ≡ out).
    test-default-scope-identity = {
      expr = (lib.head res.provenance.hostname).scope.aspect.id_hash;
      expected = fx.aspects.firewall.id_hash;
    };
    # L6 — a projects-style layer's `via` is the projecting-aspect entry (same id_hash).
    test-via-projecting-aspect = {
      expr = (lib.last res.provenance.hostname).via.id_hash;
      expected = theme.id_hash;
    };
    # L9 — a contribution containing a ref records the hop: { at; aspect; path }.
    test-hop-record = {
      expr = map (r: {
        inherit (r) at path;
        aspect = r.aspect.id_hash;
      }) (lib.last resRefs.provenance.cfg).refs;
      expected = [
        {
          at = [ "k" ];
          path = [
            "font"
            "mono"
          ];
          aspect = theme.id_hash;
        }
      ];
    };
    # L9 — ref-free entries carry refs = [ ].
    test-ref-free-empty-hops = {
      expr = map (e: e.refs) res.provenance.hostname;
      expected = [
        [ ]
        [ ]
        [ ]
      ];
    };
    # L5 — non-strict passthrough: contributor entries only, NO default entry.
    test-passthrough-no-default = {
      expr = map proj resPass.provenance.undeclared;
      expected = [
        {
          rendered = "host";
          via = null;
          refs = [ ];
          value = "u";
        }
      ];
    };
    test-declared-still-has-default = {
      expr = (lib.head resPass.provenance.declared).rendered;
      expected = "default";
    };

    # L15.4 — spine forceable: the two-entry chain length is computable.
    test-shadow-spine-forceable = {
      expr = lib.length shadowChain;
      expected = 2;
    };
    # L15.4 — the surviving (winning) sibling entry's value is forceable.
    test-shadow-sibling-forceable = {
      expr = (lib.last shadowChain).value;
      expected = "concrete";
    };
    # L15.4 — forcing the shadowed entry's OWN value throws (ref followed only then).
    test-shadow-entry-throws-on-force = {
      expr = (builtins.tryEval (builtins.deepSeq (lib.head shadowChain).value true)).success;
      expected = false;
    };
  };
}
