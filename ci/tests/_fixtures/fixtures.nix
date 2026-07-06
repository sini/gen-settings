# Shared fixtures — aspect registry-entry stand-ins (identity-bearing) and layer/entity helpers.
# gen-settings consumes gen-schema INTERFACE-ONLY: an "entry" is any value carrying `name` +
# `id_hash`. These plain records model that contract without importing gen-schema.
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

  # Entities (hosts/users) and a cell — anything carrying id_hash.
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
    # A cell (user@host) carrying a CANONICAL cell identity, not a plain-entity hash.
    siniAtAxon = {
      name = "sini@axon-01";
      id_hash = "cell0siniaxon0004";
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
    { inherit scope rendered via value; };
}
