# THE SECOND TEST OUTPUT — cells whose subject is a REFUSAL'S MESSAGE, and the runner that reads them.
#
# `ref` refuses a target carrying no `id_hash`, and the refusal is this library's E6 text: the
# identity law is stated at the boundary, before the datum is constructed. THAT it refuses is a
# boolean and `builtins.tryEval` can assert it — `ci/tests/resolution-errors.nix` already does.
# WHICH refusal fired is a claim about the message, and `tryEval` yields only `success`, never the
# message, so nix-unit's `expectedError` is the only assertion that can hold it. A guard whose text
# was replaced wholesale still passes the boolean cell and fails the one below.
#
# ★ WHY A SECOND OUTPUT RATHER THAN CELLS IN `flake.tests`. The batch asserter behind
# `checks.default` (gen-harness's `flakeModule.nix`) evaluates `expr == expected` unconditionally
# and quantifies over `flake.tests` and nothing else. An `expr` that ABORTS therefore CRASHES that
# gate rather than failing a cell, and a cell carrying `expectedError` in place of `expected` gives
# it nothing to compare. Hosting these on `flake.testsError` puts them outside that quantifier while
# keeping them live on the nix-unit path — the second output is invisible to `checks.default`
# because it is not the attribute the asserter reads, not because anything here defends it.
#
# ★ AND THE SPLIT IS STRUCTURAL, NOT CONVENTIONAL. This file is not under `./tests`, which is the
# whole of `testModules`, so which cells land in which output rests on no filter predicate and no
# naming habit. It reaches the flake through `mkCi`'s `extraModules`.
#
# `expectedError.msg` IS A REGEX MATCHED BY SEARCH, not a literal and not a whole-string match, so
# pinning the exact bytes takes two things beyond writing them down. Escape the metacharacters the
# message contains — here `(` and `)`; there is no `.`, and `:` `,` `_` `-` are literal. And ANCHOR
# it: measured, an unanchored pattern that is a strict PREFIX of the thrown message passes, so
# without `^` and `$` the cell pins a substring and a message with text appended still satisfies it.
#
# BOTH OUTPUTS NEED RUNNING, so both get a hook. The `ci` hook the shared flake module builds bakes
# `./ci#tests` into its own text and cannot be pointed here; `ci-error` below is its counterpart,
# under a distinct hook id so the two merge rather than collide.
#
#   nix-unit --flake ./ci#tests        # the suites
#   nix-unit --flake ./ci#testsError   # these cells
{
  lib,
  genSettings,
  genInputs,
  ...
}:
let
  inherit (genSettings) ref;
  # The suite's own registry-entry stand-ins, so the control's notion of a well-formed target is the
  # one every other cell in this repository uses. `_`-prefixed, hence not itself a test module.
  fx = import ./tests/_fixtures/fixtures.nix { inherit lib; };
  inherit (fx.aspects) theme;
in
{
  # Same type as `flake.tests`: the same kind of thing, read by the same runner — only the
  # assertion the cells carry differs.
  options.flake.testsError = lib.mkOption {
    type = lib.types.lazyAttrsOf (lib.types.lazyAttrsOf lib.types.raw);
    default = { };
    description = "Test suites whose cells' `expr` CAN ABORT: { suite.test = { expr; expected | expectedError; }; }. Read by `nix-unit --flake ./ci#testsError`; deliberately outside `flake.tests`, which the batch asserter forces every `expr` of and would crash on rather than fail.";
  };

  config = {
    flake.testsError.ref-refusal = {
      # E6 fires at application time, before `genSchema.fieldRef` is reached, so the call itself is
      # the force point and no accessor is needed to reach the throw.
      test-e6-name-string-target-refuses-by-name = {
        expr = ref "theme" [ "x" ];
        expectedError = {
          type = "ThrownError";
          msg = "^gen-settings: ref \\(E6\\): ref target must be an aspect registry entry carrying id_hash, never a name string$";
        };
      };

      # LIVE CONTROL, same run: the same call on a target that DOES carry `id_hash` answers, and the
      # identity it answers with is the one it was handed. Without it the cell above is satisfied by
      # a `ref` that refuses everything, which is the vacuity an assertion about a refusal invites. A
      # control has to run in the same invocation as the thing it controls, so it stays on this
      # output — an `expected` cell among `expectedError` ones on purpose.
      test-e6-control-well-formed-target-answers = {
        expr = (ref theme [ "x" ]).aspect.id_hash;
        expected = theme.id_hash;
      };
    };

    # THE SECOND HOOK. A second output that nothing runs is a second output that rots, and the
    # wrapper the shared flake module builds bakes `./ci#tests` into its own text, so it cannot be
    # pointed at this one.
    perSystem =
      { pkgs, system, ... }:
      {
        pre-commit.settings.hooks.ci-error = {
          enable = true;
          name = "ci-error";
          description = "Run nix-unit error-assertion tests";
          entry = "${
            pkgs.writeShellApplication {
              name = "gen-settings-ci-nix-unit-error";
              runtimeInputs = [ genInputs.nix-unit.packages.${system}.default ];
              text = ''
                exec nix-unit --flake ./ci#testsError "$@"
              '';
            }
          }/bin/gen-settings-ci-nix-unit-error";
          files = "\\.nix$";
          pass_filenames = false;
        };
      };
  };
}
