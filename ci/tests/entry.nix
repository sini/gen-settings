# THE STANDALONE ROOT ENTRY — the plain-import path, which no other cell in this suite reaches.
#
# ★ WHY THIS FILE EXISTS. Every other suite here builds the library by importing `../lib` directly
# with injected values, so the ROOT `default.nix` — the entry a non-flake consumer actually uses —
# is evaluated by nothing. A shim can therefore name fewer arguments than the library it delegates
# to, promise lockstep with the flake in its own comment, and stay green forever: the flake path and
# the plain-import path are two signatures with nothing comparing them, so the second one rots
# silently the first time `lib/default.nix` grows a formal.
#
# ★★ THE CELL IS PURE, AND THE PURITY IS A CONSEQUENCE OF HOW IT IS CALLED. The shim's defaults
# `builtins.fetchTree` the flake-locked revs; supplying EVERY dependency formal explicitly means
# those defaults are never forced, so this reaches the network not at all. What it tests is the
# shim's SIGNATURE and its delegation — which is precisely where the defect lives.
#
# ★ IT CATCHES BOTH DIRECTIONS OF THE DRIFT, which is why it is an argument-passing cell rather than
# an `attrNames` comparison alone:
#   · a shim naming FEWER formals than `lib` refuses this application by name
#     (`called with unexpected argument 'genIdentity'`);
#   · a shim that forwards fewer than `lib` requires refuses inside it
#     (`called without required argument 'genIdentity'`).
# Both are uncatchable evaluator refusals, so either turns this cell ☢️ rather than ❌ — a crash is
# the loudest reading available and is the right one for an entry point that does not exist.
{
  genSettings,
  prelude,
  genAlgebra,
  genBind,
  genGraph,
  genSchema,
  genTypes,
  genIdentity,
  ...
}:
let
  standalone = import ../.. {
    inherit
      prelude
      genGraph
      genSchema
      genTypes
      genIdentity
      ;
    algebra = genAlgebra;
    bind = genBind;
  };
in
{
  # ★ The assertion is over the APPLIED surfaces, not over the entries themselves: both are
  # functions of their injected substrate, and two Nix lambdas are never equal — so `entry == entry`
  # would read `false` on a correct library and could not distinguish drift from the language. The
  # applied form is also the stronger claim: it is the surface a consumer actually receives.
  flake.tests.entry.test-standalone-entry-matches-lib = {
    expr = builtins.attrNames standalone;
    expected = builtins.attrNames genSettings;
  };

  # The surface is not merely equal but non-trivial, so the cell above cannot pass by both sides
  # being empty.
  flake.tests.entry.test-control-the-compared-surface-is-non-trivial = {
    expr = builtins.length (builtins.attrNames standalone) > 8;
    expected = true;
  };

  # ★ THE COMPARISON IS SHOWN ABLE TO FAIL, in the same run. Without this, an `attrNames` equality
  # between two values that happen to be the same import is a tautology nobody has checked.
  flake.tests.entry.test-control-the-comparison-discriminates = {
    expr = builtins.attrNames standalone == builtins.attrNames (removeAttrs genSettings [ "ref" ]);
    expected = false;
  };

  # And the library reached THROUGH the shim actually works, rather than merely having the right
  # keys — a delegation that forwarded the wrong value would satisfy an `attrNames` check. This one
  # builds a reference and finds it again with the structural scan, so both the injected gen-schema
  # (which owns the ref datum) and the prelude the scan walks with have to be the real ones.
  flake.tests.entry.test-the-shims-library-is-live = {
    expr = builtins.length (standalone.refsIn { x = standalone.ref { id_hash = "h"; } [ "a" ]; });
    expected = 1;
  };
}
