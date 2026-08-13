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
  inherit (genSettings)
    ref
    mkSchema
    resolveOne
    resolveAll
    ;
  # The suite's own registry-entry stand-ins, so the control's notion of a well-formed target is the
  # one every other cell in this repository uses. `_`-prefixed, hence not itself a test module.
  fx = import ./tests/_fixtures/fixtures.nix { inherit lib; };
  inherit (fx.aspects)
    theme
    terminal
    absent
    ;

  member = schema: layers: { inherit schema layers; };

  # E4 — the ref's target aspect is absent from the batch. This is the batch-level resolver, the one
  # that names BOTH endpoints, so its rendering carries the source field.
  batchE4 = [
    (member (mkSchema {
      aspect = theme;
      fields = {
        f = {
          default = ref absent [ "x" ];
        };
      };
    }) [ ])
  ];

  # E5 — target present in the batch, path component absent from its resolved value. The target
  # endpoint here renders a PATH rather than a field, which is the arm `walkPath` reaches.
  batchE5 = [
    (member (mkSchema {
      aspect = theme;
      fields = {
        f = {
          default = ref terminal [ "nope" ];
        };
      };
    }) [ ])
    (member (mkSchema {
      aspect = terminal;
      fields = {
        g = {
          default = "G";
        };
      };
    }) [ ])
  ];
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

    # THE DIAGNOSTIC BYTES — E1 (schema shape), E4 (target not in batch / no resolver), E5 (bad ref
    # path). Each message is a CONTRACT, and each is pinned here to its exact bytes.
    #
    # ★ WHY NOT `throws … == true`, WHICH `tests/resolution-errors.nix` ALREADY CARRIES FOR EVERY
    # ONE OF THESE. That predicate is a boolean, and a boolean cannot see the thing under test.
    # Measured on this library: dropping `field = sourceField` from BOTH the E4 and E5 renderings,
    # and replacing the E1 dotted-key message wholesale, each leave the entire suite green. A
    # refusal that still fires while saying something else satisfies a `throws` cell and fails every
    # cell below. Adding the boolean here would restate the gap as its own fix.
    #
    # ★ WHERE THE ADDRESSES COME FROM. E4 and E5 compose their endpoints from `renderAddress`, whose
    # three arms are pinned directly — one cell per arm, none composed — in
    # `tests/address-rendering.nix`. The goldens below therefore pin what that file cannot: the fixed
    # text around the addresses, and which endpoint is rendered in which position. E1 carries no
    # address and is pinned only here.
    #
    # ★ THE ACCEPTANCE CONTROLS FOR THESE CONSTRUCTIONS ARE ON `flake.tests`, said here because a
    # cell asserting a refusal is otherwise satisfied by an implementation that refuses everything:
    # `resolution-errors.test-e1-well-formed-field-accepted` accepts a well-formed field, and the
    # `ref-substitution` suite resolves refs that answer (`test-default-ref-resolves` and its
    # neighbours). Both run under the same `nix flake check`; neither can run on this output,
    # because a control belongs with the quantifier it is a control for.
    flake.testsError.diagnostic-bytes = {
      # E1 — a dotted field name. Eager and name-level: `mkSchema` refuses at WHNF, so the call is
      # the force point.
      test-e1-dotted-key-message = {
        expr = mkSchema {
          aspect = theme;
          fields = {
            "a.b" = {
              default = 1;
            };
          };
        };
        expectedError = {
          type = "ThrownError";
          msg = "^gen-settings: schema \\(E1\\): field name 'a\\.b' must be a bare key \\(no dots\\) — namespacing under the aspect happens at the consumer boundary$";
        };
      };

      # E1 — a leaf with no `default`. Per-field and lazy, so reaching the field is the force point:
      # `.strategies.x` is the cheapest read that runs `normField` on `x`.
      test-e1-missing-default-message = {
        expr =
          (mkSchema {
            aspect = theme;
            fields = {
              x = {
                merge = "replace";
              };
            };
          }).strategies.x;
        expectedError = {
          type = "ThrownError";
          msg = "^gen-settings: schema \\(E1\\): field 'x' has no 'default' — default is mandatory on every leaf$";
        };
      };

      # E1 — a merge strategy outside the schema's declared set. The message quotes the offending
      # strategy AND enumerates the admissible ones, so the golden pins the enumeration too: this is
      # the one message whose text a consumer reads as documentation.
      test-e1-bad-merge-message = {
        expr =
          (mkSchema {
            aspect = theme;
            fields = {
              x = {
                default = 1;
                merge = "bogus";
              };
            };
          }).strategies.x;
        expectedError = {
          type = "ThrownError";
          msg = "^gen-settings: schema \\(E1\\): field 'x' has unknown merge strategy 'bogus' \\(expected replace\\|append\\|recursive\\)$";
        };
      };

      # E4 — batch resolution, target absent. BOTH endpoints are named (L10), and the source endpoint
      # is field-indexed: `resolverFor` takes the field precisely so this line can say `.f`. A
      # field-blind resolver still refuses, still names the target, and drops the `.f` — which is the
      # byte this cell exists to hold.
      test-e4-target-absent-message = {
        expr = (resolveAll { batch = batchE4; }).value.theme.f;
        expectedError = {
          type = "ThrownError";
          msg = "^gen-settings: unresolved ref \\(E4\\): aspect\\(theme#a1b2c3d4\\)\\.f references aspect\\(absent#99998888\\) which is not present in the batch$";
        };
      };

      # E4 — the OTHER E4, from `resolveOne`'s default resolver. Standalone resolution has no batch
      # and no source field to name, so this message renders one endpoint where the batch-level E4
      # renders two. Two texts share the code; a golden for either says nothing about the other.
      test-e4-no-resolver-message = {
        expr =
          (resolveOne {
            schema = mkSchema {
              aspect = theme;
              fields = {
                f = {
                  default = ref terminal [ "g" ];
                };
              };
            };
            layers = [ ];
          }).value.f;
        expectedError = {
          type = "ThrownError";
          msg = "^gen-settings: unresolved ref \\(E4\\): no resolveRef supplied to resolveOne for target aspect\\(terminal#e5f6a7b8\\)$";
        };
      };

      # E5 — target present, path component missing. The source endpoint renders a FIELD and the
      # target endpoint renders a PATH, so this one message exercises two different arms of
      # `renderAddress` in two positions, and the golden pins which is which.
      test-e5-bad-path-message = {
        expr = (resolveAll { batch = batchE5; }).value.theme.f;
        expectedError = {
          type = "ThrownError";
          msg = "^gen-settings: bad ref path \\(E5\\): aspect\\(theme#a1b2c3d4\\)\\.f -> aspect\\(terminal#e5f6a7b8\\)\\.nope: component 'nope' not present in the resolved value$";
        };
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
