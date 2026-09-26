# Shared fixtures — aspect registry-entry stand-ins (identity-bearing) and layer/entity helpers.
# An "entry" is any value carrying `name` + `id_hash` — gen-settings never asks for more, and the
# ref datum's identity law is stated over exactly that. These plain records model the contract
# structurally, so the suite exercises the law rather than a particular registry that satisfies it.
{ ... }:
let
  mkAspect = name: id_hash: { inherit name id_hash; };
in
rec {
  inherit mkAspect;

  # Aspects with fixed, human-legible id_hashes so golden renderings are stable.
  aspects = {
    theme = mkAspect "theme" "a1b2c3d4deadbeef";
    terminal = mkAspect "terminal" "e5f6a7b8cafef00d";
    firewall = mkAspect "firewall" "f1f2f3f4f5f6f7f8";
    nginx = mkAspect "nginx" "0011223344556677";
    absent = mkAspect "absent" "9999888877776666";
  };

  # Entities — anything carrying id_hash. A minted binding node fills the same slot; the
  # identity-keying suite mints one through gen-scope rather than transcribing a token here.
  entities = {
    axon = {
      name = "axon-01";
      id_hash = "host0axon00000001";
    };
    blade = {
      name = "blade";
      id_hash = "host0blade0000002";
    };
    sini = {
      name = "sini";
      id_hash = "user0sini00000003";
    };
  };

  classes = {
    nixos = {
      name = "nixos";
      id_hash = "class0nixos000005";
    };
  };

  # A layer with an explicit scope/rendered/via and a bare-key contribution value.
  mkLayer =
    {
      scope ? null,
      rendered ? "layer",
      via ? null,
      value,
    }:
    {
      inherit
        scope
        rendered
        via
        value
        ;
    };
}
