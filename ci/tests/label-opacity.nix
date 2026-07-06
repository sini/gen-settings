# T4 label-opacity (L4). `.value` is independent of layer labels: replacing every structured label
# with any other value changes no resolved value. Plus the gen-algebra pinning test (§5, T4) —
# foldLayersTraced accepts non-string labels and never inspects them.
{
  lib,
  genSettings,
  genAlgebra,
  ...
}:
let
  inherit (genSettings) mkSchema resolveOne;
  fx = import ./_fixtures/fixtures.nix { inherit lib; };
  foldLayersTraced = genAlgebra.record.foldLayersTraced;

  schema = mkSchema {
    aspect = fx.aspects.firewall;
    fields = {
      "allowed-tcp" = {
        default = [ 22 ];
        merge = "append";
      };
      hostname = {
        default = "unset";
      };
    };
  };

  # Two layer sets differing ONLY in scope/rendered/via labels; the contribution values match.
  labelledLayers = [
    (fx.mkLayer {
      scope = {
        host = fx.entities.axon;
      };
      rendered = "axon-01";
      via = fx.aspects.theme;
      value = {
        "allowed-tcp" = [ 80 ];
        hostname = "h";
      };
    })
  ];
  relabelledLayers = [
    (fx.mkLayer {
      scope = null;
      rendered = "TOTALLY-DIFFERENT";
      via = null;
      value = {
        "allowed-tcp" = [ 80 ];
        hostname = "h";
      };
    })
  ];

  a = resolveOne {
    inherit schema;
    layers = labelledLayers;
  };
  b = resolveOne {
    inherit schema;
    layers = relabelledLayers;
  };

  # gen-algebra pinning: same values, labels are ints / attrsets / null → value byte-identical.
  strategies = {
    x = "replace";
  };
  defaults = {
    x = 0;
  };
  layers = [
    { x = 1; }
    { x = 2; }
  ];
  foldA = foldLayersTraced {
    inherit strategies defaults layers;
    layerNames = [
      "s-one"
      "s-two"
    ];
    defaultLabel = "default";
  };
  foldB = foldLayersTraced {
    inherit strategies defaults layers;
    layerNames = [
      7
      { k = "attr"; }
    ];
    defaultLabel = null;
  };
in
{
  flake.tests.label-opacity = {
    # L4 — resolved value invariant under label replacement.
    test-value-invariant-under-labels = {
      expr = a.value == b.value;
      expected = true;
    };
    # §5 pinning — foldLayersTraced value is byte-identical under non-string labels.
    test-algebra-value-label-opaque = {
      expr = foldA.value == foldB.value;
      expected = true;
    };
    # ...and the traced labels are stored verbatim (opacity, never inspected/coerced).
    test-algebra-labels-stored-verbatim = {
      expr = map (e: e.layer) foldB.provenance.x;
      expected = [
        null
        7
        { k = "attr"; }
      ];
    };
  };
}
