# Purity invariant (roadmap §5, Class B): the gen-settings library (./lib) is nixpkgs-lib-free. All
# machinery is builtins + gen-prelude, plus the injected gen-algebra fold and gen-bind wrap; gen-schema
# is consumed interface-only (the id_hash field), never imported. A stray `lib.`/`evalModules`/`nixpkgs`
# tether in the library source fails CI. Scope: lib/**.nix + the root flake.nix + default.nix. NOT ci/.
{ lib, ... }:
let
  libDir = ../../lib;

  stripComments =
    text:
    lib.concatStringsSep "\n" (
      map (line: lib.head (lib.splitString "#" line)) (lib.splitString "\n" text)
    );

  walk =
    dir:
    lib.concatLists (
      lib.mapAttrsToList (
        name: type:
        if type == "directory" then
          walk (dir + "/${name}")
        else if lib.hasSuffix ".nix" name then
          [ (dir + "/${name}") ]
        else
          [ ]
      ) (builtins.readDir dir)
    );

  sources =
    map (p: {
      name = toString p;
      code = stripComments (builtins.readFile p);
    }) (walk libDir)
    ++
      map
        (rel: {
          name = rel;
          code = stripComments (builtins.readFile (../.. + "/${rel}"));
        })
        [
          "flake.nix"
          "default.nix"
        ];

  forbidden = [
    "nixpkgs"
    "lib.types"
    "lib.mkOption"
    "lib.mkMerge"
    "lib.mkForce"
    "lib.evalModules"
    "evalModules"
    "{ lib }"
    "{ lib,"
  ];

  violations = lib.concatMap (
    src: map (tok: "${src.name}: '${tok}'") (lib.filter (tok: lib.hasInfix tok src.code) forbidden)
  ) sources;
in
{
  flake.tests.purity.test-library-source-is-nixpkgs-free = {
    expr = violations;
    expected = [ ];
  };
}
