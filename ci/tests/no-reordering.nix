# T10 no-reordering (L16). The lib performs no reorder, dedup, or filter of the given layer list —
# the lattice-blindness constraint made observable. Permuting two `replace` layers flips the winner;
# a duplicate layer contributes twice under `append`; provenance order equals input order.
{
  lib,
  genSettings,
  ...
}:
let
  inherit (genSettings) mkSchema resolveOne;
  fx = import ./_fixtures/fixtures.nix { inherit lib; };

  schema = mkSchema {
    aspect = fx.aspects.firewall;
    fields = {
      h = {
        default = "d";
      }; # replace
      p = {
        default = [ ];
        merge = "append";
      };
    };
  };

  la = fx.mkLayer {
    rendered = "a";
    value = {
      h = "A";
      p = [ 1 ];
    };
  };
  lb = fx.mkLayer {
    rendered = "b";
    value = {
      h = "B";
      p = [ 2 ];
    };
  };

  fwd = resolveOne {
    inherit schema;
    layers = [
      la
      lb
    ];
  };
  rev = resolveOne {
    inherit schema;
    layers = [
      lb
      la
    ];
  };
  dup = resolveOne {
    inherit schema;
    layers = [
      la
      la
    ];
  };
in
{
  flake.tests.no-reordering = {
    # L16 — permuting replace layers flips the winner.
    test-permute-flips-winner = {
      expr = [
        fwd.value.h
        rev.value.h
      ];
      expected = [
        "B"
        "A"
      ];
    };
    # L16 — a duplicate layer contributes twice under append (no dedup).
    test-duplicate-appends-twice = {
      expr = dup.value.p;
      expected = [
        1
        1
      ];
    };
    # L16 — provenance order equals input order (default first, then layers as given).
    test-provenance-order-preserved = {
      expr = map (e: e.rendered) fwd.provenance.h;
      expected = [
        "default"
        "a"
        "b"
      ];
    };
  };
}
