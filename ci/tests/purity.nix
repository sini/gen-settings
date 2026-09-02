# Purity invariant (roadmap §5, Class B): the gen-settings library (./lib) is nixpkgs-lib-free. All
# machinery is builtins + gen-prelude, plus the injected gen-algebra fold, gen-bind wrap, gen-graph
# cycle detection, gen-schema ref datum and gen-types schema-shape checkers — every one of which is
# itself nixpkgs-lib-free, so importing them introduces none of the forbidden tokens below. A stray
# `lib.`/`evalModules`/`nixpkgs` tether in the library source fails CI. Scope: lib/**.nix + the root
# flake.nix + default.nix. NOT ci/.
{ genPrelude, lib, ... }:
let
  libDir = ../../lib;

  # Drop each line from the `#` that STARTS A COMMENT — one at the start of the line, or preceded
  # by whitespace. A `#` flush against other text is inside a string literal (`lib/display.nix` and
  # `lib/inject.nix` both render an `aspect(name#hash)` label that way), and cutting there hides
  # every character after it — code included — from the scan below. The rule this replaces cut at
  # the FIRST `#` and rested on "no `#` in a string literal", which is false in this corpus and was
  # asserted by nothing.
  #
  # Where the rule cannot tell, it KEEPS the text, and that direction is the whole point: prose
  # that gets scanned is a red CI somebody reads, code that goes unscanned is nothing at all. It
  # still cuts at a whitespace-preceded `#` inside a `''…''` block — measured absent here, and the
  # residue a full Nix lexer would close.
  stripComments =
    text:
    let
      stripLine =
        line:
        let
          parts = lib.splitString "#" line;
          step =
            acc: part:
            if acc.done then
              acc
            else if acc.text == "" || lib.hasSuffix " " acc.text || lib.hasSuffix "\t" acc.text then
              acc // { done = true; }
            else
              acc // { text = acc.text + "#" + part; };
        in
        (lib.foldl' step {
          text = lib.head parts;
          done = false;
        } (lib.tail parts)).text;
    in
    lib.concatStringsSep "\n" (map stripLine (lib.splitString "\n" text));

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

  scan =
    srcs:
    lib.concatMap (
      src:
      map (tok: "${src.name}: '${tok}'") (lib.filter (tok: genPrelude.hasInfix tok src.code) forbidden)
    ) srcs;

  # A synthetic line carrying BOTH halves of the strip's job at once, and NOT written to disk, so
  # the invariant cell stays a statement about the real library. `lib.types.str` sits after a `#`
  # that is inside a string literal: it must SURVIVE and be found. `nixpkgs` sits after a real
  # trailing comment marker: it must be DROPPED and not found.
  probe = {
    name = "<in-string-hash>";
    code = stripComments "edgeName = \"a#b\"; x = lib.types.str; # nixpkgs, in a trailing comment";
  };
in
{
  flake.tests.purity.test-library-source-is-nixpkgs-free = {
    expr = scan sources;
    expected = [ ];
  };

  # THE STRIP IS THE OPERAND OF THE CELL ABOVE, exercised here at an input that cell never reads.
  # The `[ ]` above is a claim about code only if the strip discards comments and nothing else, and
  # a strip that cut at the first `#` would produce that same `[ ]` while hiding the tail of four
  # real lines across the sibling libraries. Both halves are asserted by the one expected value:
  # `lib.types` present says the in-string `#` did not truncate, its absence of `nixpkgs` says the
  # trailing comment still went.
  flake.tests.purity.test-control-strip-cuts-at-comments-not-inside-strings = {
    expr = scan [ probe ];
    expected = [ "<in-string-hash>: 'lib.types'" ];
  };
}
