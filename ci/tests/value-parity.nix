# T1 value-parity (L1, L2). The Spike 5 acceptance gate: for ref-free inputs, resolveOne.value is
# byte-identical to gen-algebra's foldLayers over the same strategies/defaults/layer values — a
# COMPUTED comparison against the real fold, not hand-written expecteds. Plus the strategy matrix.
#
# The expected is computed from foldLayers while the library binds foldLayersTraced, and that is
# licensed rather than assumed: gen-algebra's own value-identity guards
# (`test-value-identity-replace` / `-append` / `-recursive` / `-explicit-replace-and-default-only`,
# ci/tests/rec-fold-layers-traced.nix) prove the two agree on exactly the strategies both accept.
# `mergeStrategy` (lib/schema.nix) admits exactly that domain — replace, append, recursive, plus
# the implicit replace its `merge or "replace"` defaulting supplies — so every schema this suite
# can express falls inside it. The siblings are NOT one primitive: foldLayersTraced also resolves
# "semilattice-set", which foldLayers refuses. The licence ends where the shared domain does.
{
  lib,
  genSettings,
  genAlgebra,
  ...
}:
let
  inherit (genSettings) mkSchema resolveOne;
  fx = import ./_fixtures/fixtures.nix { inherit lib; };
  foldLayers = genAlgebra.record.foldLayers;

  schema = mkSchema {
    aspect = fx.aspects.firewall;
    fields = {
      "allowed-tcp" = {
        default = [ 22 ];
        merge = "append";
      };
      hostname = {
        default = "unset";
      }; # replace (implicit)
      opts = {
        default = {
          a = 1;
        };
        merge = "recursive";
      };
      "empty-list" = {
        default = [ ];
        merge = "append";
      };
    };
  };

  layers = [
    (fx.mkLayer {
      rendered = "env";
      value = {
        "allowed-tcp" = [ 80 ];
        hostname = "h1";
        opts = {
          b = 2;
        };
        "empty-list" = [ "x" ];
      };
    })
    (fx.mkLayer {
      rendered = "host";
      value = {
        "allowed-tcp" = [ 443 ];
        hostname = "h2";
        opts = {
          a = 9;
          c = 3;
        };
        "empty-list" = [ "y" ];
      };
    })
  ];

  resolved = resolveOne { inherit schema layers; };
  expectedFold = foldLayers {
    inherit (schema) strategies defaults;
    layers = map (l: l.value) layers;
  };

  # A permuted-layer variant, to observe the last-wins boundary (also used by T10).
  swapped = resolveOne {
    inherit schema;
    layers = lib.reverseList layers;
  };
in
{
  flake.tests.value-parity = {
    # L1 — the gate: computed byte-identity against the real foldLayers.
    test-value-equals-foldLayers = {
      expr = resolved.value;
      expected = expectedFold;
    };

    # L2 — append: default ++ layer₁ ++ … ++ layerₙ in list order.
    test-append-accumulates = {
      expr = resolved.value."allowed-tcp";
      expected = [
        22
        80
        443
      ];
    };
    # L2 — append with empty default.
    test-append-empty-default = {
      expr = resolved.value."empty-list";
      expected = [
        "x"
        "y"
      ];
    };
    # L2 — replace: positional last-wins over [default] ++ layers.
    test-replace-last-wins = {
      expr = resolved.value.hostname;
      expected = "h2";
    };
    # L2 — recursive: shallow // fold, later colliding sub-keys win, earlier-only survive.
    test-recursive-shallow = {
      expr = resolved.value.opts;
      expected = {
        a = 9;
        b = 2;
        c = 3;
      };
    };
    # L2 — a ref-free single-default field (no layers) is just its default.
    test-default-only = {
      expr =
        (resolveOne {
          schema = mkSchema {
            aspect = fx.aspects.theme;
            fields = {
              font = {
                default = "mono";
              };
            };
          };
          layers = [ ];
        }).value;
      expected = {
        font = "mono";
      };
    };
    # Permuted replace layers flip the winner (also L16).
    test-replace-permutation-flips = {
      expr = swapped.value.hostname;
      expected = "h1";
    };
  };
}
