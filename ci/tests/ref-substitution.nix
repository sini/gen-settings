# T2 ref-substitution (L3). Fold-then-substitute equals folding pre-substituted inputs, because
# refs are merge-atomic (§2.2). Refs in defaults, in layer values, deep inside values, as list
# elements under `append`, at sub-keys under `recursive` (shadowed and surviving). Merge-atomicity:
# a ref shadowed by a later `replace` layer is never *followed* (sentinel resolveRef, never called).
{
  lib,
  genSettings,
  genAlgebra,
  ...
}:
let
  inherit (genSettings)
    mkSchema
    resolveOne
    ref
    ;
  fx = import ./_fixtures/fixtures.nix { inherit lib; };
  foldLayers = genAlgebra.record.foldLayers;

  theme = fx.aspects.theme;
  # A concrete resolver mapping any ref to a marker of its path (so equivalence is checkable).
  resolveRef = { aspect, path }: "R:${lib.concatStringsSep "." path}";

  # A resolver that MUST NOT be called (proves a shadowed/absent ref is never followed).
  sentinelRef = { aspect, path }: throw "resolveRef called — should not happen";

  # ── ref in a default, no overriding layer ──
  schemaDefaultRef = mkSchema {
    aspect = fx.aspects.terminal;
    fields = {
      font = {
        default = ref theme [
          "font"
          "mono"
        ];
      };
    };
  };
  resDefaultRef = resolveOne {
    schema = schemaDefaultRef;
    layers = [ ];
    inherit resolveRef;
  };

  # ── ref in a layer value, deep + list element under append ──
  schemaDeep = mkSchema {
    aspect = fx.aspects.terminal;
    fields = {
      cfg = {
        default = {
          k = "base";
        };
      };
      ports = {
        default = [ ];
        merge = "append";
      };
    };
  };
  resDeep = resolveOne {
    schema = schemaDeep;
    layers = [
      (fx.mkLayer {
        value = {
          cfg = {
            k = ref theme [ "font" ];
          }; # deep inside an attrset value
          ports = [
            (ref theme [ "p1" ])
            7
          ]; # ref as a list element
        };
      })
    ];
    inherit resolveRef;
  };
  # The same fold with refs pre-substituted — L3 equivalence target.
  resDeepPre = foldLayers {
    inherit (schemaDeep) strategies defaults;
    layers = [
      {
        cfg = {
          k = "R:font";
        };
        ports = [
          "R:p1"
          7
        ];
      }
    ];
  };

  # ── shadowed ref under replace: the default ref is beaten by a concrete layer ──
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
    resolveRef = sentinelRef; # never called: the winning value carries no ref
  };

  # ── surviving ref under recursive at a sub-key ──
  schemaRec = mkSchema {
    aspect = fx.aspects.terminal;
    fields = {
      opts = {
        default = {
          a = 1;
        };
        merge = "recursive";
      };
    };
  };
  resRec = resolveOne {
    schema = schemaRec;
    layers = [
      (fx.mkLayer {
        value = {
          opts = {
            b = ref theme [ "x" ];
          };
        };
      })
    ];
    inherit resolveRef;
  };
in
{
  flake.tests.ref-substitution = {
    # ref in a default resolves during the fold.
    test-default-ref-resolves = {
      expr = resDefaultRef.value.font;
      expected = "R:font.mono";
    };
    # deep + list-element refs resolve, and equal the pre-substituted fold (L3).
    test-deep-and-list-equiv = {
      expr = resDeep.value;
      expected = resDeepPre;
    };
    test-list-ref-element = {
      expr = resDeep.value.ports;
      expected = [
        "R:p1"
        7
      ];
    };
    # merge-atomicity: a shadowed ref is never followed — sentinel resolver stays uncalled.
    test-shadowed-ref-not-followed = {
      expr = resShadow.value.font;
      expected = "concrete";
    };
    # a ref surviving under recursive at a sub-key is resolved as a unit.
    test-recursive-subkey-ref = {
      expr = resRec.value.opts;
      expected = {
        a = 1;
        b = "R:x";
      };
    };
  };
}
