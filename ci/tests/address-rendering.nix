# address-rendering (L10). `renderAddress` — the renderer every addressed diagnostic composes —
# pinned ARM BY ARM, each cell calling the public renderer directly.
#
# ── WHY THIS FILE EXISTS, WHEN THE E3 GOLDENS ALREADY RENDER ADDRESSES ──
# `static-graph.nix`'s four `renderCycles` goldens pin `renderAddress` only through a composition,
# and therefore only on the arms that composition reaches: a cycle edge is an aspect plus a field,
# so the base and field arms are covered and the PATH arm is covered by nothing at all. The path
# arm is the one E5's target endpoint renders (`resolve.nix` `walkPath` passes `path`, never
# `field`), so the unpinned rendering is the one the least-pinned message is built from. Pinning a
# renderer through a single composition covers whichever arms that composition happens to use and
# leaves the rest silently unpinned — hence one cell per arm here, none of them composed.
#
# Identity law (roadmap §1.10): a rendering is the name plus an 8-char id_hash prefix, DISPLAY ONLY
# and never parsed back. The fixture id_hashes are 16 chars, so every golden below also pins the
# truncation.
{
  lib,
  genSettings,
  ...
}:
let
  inherit (genSettings) renderAddress;
  fx = import ./_fixtures/fixtures.nix { inherit lib; };
  inherit (fx.aspects)
    theme
    terminal
    absent
    ;
in
{
  flake.tests.address-rendering = {
    # base — an aspect alone, no field and no path. The rendering E4 gives its target endpoint.
    test-render-address-base = {
      expr = renderAddress { aspect = absent; };
      expected = "aspect(absent#99998888)";
    };

    # field arm — the source endpoint E4 and E5 both name.
    test-render-address-field = {
      expr = renderAddress {
        aspect = theme;
        field = "f";
      };
      expected = "aspect(theme#a1b2c3d4).f";
    };

    # path arm — the E5 target endpoint. Both renderings belong to this one arm and both are
    # needed to pin it: `concatStringsSep` emits no separator over a one-element path, so the
    # single-component form pins the leading "." and says nothing about the join between
    # components. A cell carrying only the E5 shape would leave half the arm where the path arm
    # was before this file — rendered by shipped code, pinned by nothing.
    test-render-address-path = {
      expr = {
        oneComponent = renderAddress {
          aspect = terminal;
          path = [ "nope" ];
        };
        twoComponents = renderAddress {
          aspect = terminal;
          path = [
            "nope"
            "deeper"
          ];
        };
      };
      expected = {
        oneComponent = "aspect(terminal#e5f6a7b8).nope";
        twoComponents = "aspect(terminal#e5f6a7b8).nope.deeper";
      };
    };
  };
}
