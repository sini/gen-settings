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

  # E5 — target present in the batch, and the path component decides whether it resolves. The target
  # endpoint renders a PATH rather than a field, which is the arm `walkPath` reaches.
  #
  # Parameterised by that component so the refusal and its control differ in exactly one string, and
  # differ in nothing else BY CONSTRUCTION: `terminalPathBatch "nope"` walks off the end of the
  # resolved value, `terminalPathBatch "g"` lands on the field the terminal schema declares. A
  # control assembled as its own literal could drift from the construction it is a control for; this
  # one cannot, because there is only one construction.
  terminalPathBatch = comp: [
    (member (mkSchema {
      aspect = theme;
      fields = {
        f = {
          default = ref terminal [ comp ];
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

  batchE5 = terminalPathBatch "nope";

  # E7 (identity arm) — two members share ONE id_hash under DISTINCT display keys. `theme-alias`
  # carries theme's id_hash under a different name, the same construction `ci/tests/static-graph.nix`'s
  # `themeAlias` fixture uses to observe the identity/display split from the graph side.
  themeAlias = fx.mkAspect "theme-alias" theme.id_hash;
  dupIdentityBatch = [
    (
      member (mkSchema {
        aspect = theme;
        fields = {
          font = {
            default = "FIRST";
          };
        };
      }) [ ]
      // {
        key = "theme";
      }
    )
    (
      member (mkSchema {
        aspect = themeAlias;
        fields = {
          font = {
            default = "SECOND";
          };
        };
      }) [ ]
      // {
        key = "theme2";
      }
    )
  ];

  # LIVE CONTROL for the cell above: the SAME two display keys, but DISTINCT identities. Without
  # it, the identity refusal is satisfied by a `resolveAll` that refuses every two-member batch —
  # the cell's answer would be about the display keys colliding, not about identity.
  distinctIdentitySameKeysBatch = [
    (
      member (mkSchema {
        aspect = theme;
        fields = {
          font = {
            default = "FIRST";
          };
        };
      }) [ ]
      // {
        key = "theme";
      }
    )
    (
      member (mkSchema {
        aspect = terminal;
        fields = {
          font = {
            default = "SECOND";
          };
        };
      }) [ ]
      // {
        key = "theme2";
      }
    )
  ];

  # THE SUBSTITUTION'S DOMAIN. `resolveOne` applied ONCE per construction, so the two arms asserted
  # below are halves of one result rather than two similar calls — which is what lets them witness
  # a result disagreeing with itself rather than two exports disagreeing with each other.
  #
  # The two constructions differ in exactly one thing, and nothing else, BY CONSTRUCTION: the same
  # `ref` value sits in the field's value, or inside a function body in it. A control assembled as
  # its own literal could drift from the construction it controls; this one cannot.
  substSubject =
    value:
    resolveOne {
      schema = mkSchema {
        aspect = theme;
        fields = {
          f = {
            default = value;
          };
        };
      };
      layers = [ ];
      resolveRef = _: "RESOLVED";
    };
  refToTerminal = ref terminal [ "g" ];
  oneFn = substSubject (_: refToTerminal);
  oneData = substSubject refToTerminal;

  refuses = e: !(builtins.tryEval (builtins.deepSeq e e)).success;
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
    # ★ THE LIVE CONTROL FOR THESE CELLS IS THE LAST ONE IN THIS SUITE, on this output and in this
    # invocation, for the reason the E6 control above already states: a cell asserting a refusal is
    # otherwise satisfied by a library that refuses everything it is handed, and a control rules that
    # out only if it runs when the cells it controls run. `flake.tests` carries further acceptance
    # coverage of the same constructions — `resolution-errors.test-e1-well-formed-field-accepted`,
    # and the `ref-substitution` suite's resolving cells. That coverage is ADDITIONAL, not a
    # substitute: it runs under `nix flake check` and not under `nix-unit --flake ./ci#testsError`,
    # so a run of this output alone would carry none of it.
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

      # LIVE CONTROL, same run, for every cell above — the E5 construction with its path component
      # corrected, and nothing else about it changed. It runs the whole path the goldens only ever
      # see fail: `mkSchema` accepts both schemas, the batch resolves, and `walkPath` walks the one
      # component it is handed and finds it.
      #
      # ★ WITHOUT IT THIS OUTPUT REPORTS SUCCESS ON A LIBRARY THAT NO LONGER RESOLVES ANYTHING.
      # Measured: breaking `walkPath`'s success branch leaves all six goldens green, because each one
      # asks only that a refusal arrive with the right bytes, and a library that has stopped resolving
      # produces refusals more readily, not less. That is the failure mode a refusal suite invites,
      # and the only cell that can see it is one that requires an answer.
      test-control-e5-construction-with-corrected-path-resolves = {
        expr = (resolveAll { batch = terminalPathBatch "g"; }).value.theme.f;
        expected = "G";
      };
    };

    # E7's IDENTITY ARM — den-hoag-dz8j. `resolveAll` indexed the batch twice, under two
    # different keys (display key for the output, `id_hash` for the fold), and assumed the two
    # indexings were bijective without deriving or enforcing it. Two members sharing one
    # `id_hash` under distinct display keys passed the display-key E7 check and collided in the
    # identity-keyed fold: both display keys silently resolved to the FIRST member's value, the
    # second member's declarations gone with no diagnostic. ADR-0016 leaves how two members at
    # one identity should COMPOSE unsettled (premise-document OPEN 2.C); refusing by name decides
    # nothing about that and is the arm it names as available, so this closes as a second E7 arm
    # rather than a silent first-wins fold or an invented precedence rule.
    #
    # ★ A cell that only checks "it refuses" would pass a refusal firing for the wrong reason —
    # `ci/tests/resolution-errors.nix`'s boolean `test-e7-duplicate-key` cannot discriminate this
    # arm from the pre-existing display-key one. The byte goldens below are what can.
    flake.testsError.identity-collapse = {
      test-e7-duplicate-identity-message = {
        expr = (resolveAll { batch = dupIdentityBatch; }).value;
        expectedError = {
          type = "ThrownError";
          msg = "^gen-settings: duplicate batch identity \\(E7\\): 'a1b2c3d4' shared by 'theme' \\(aspect\\(theme#a1b2c3d4\\)\\) and 'theme2' \\(aspect\\(theme-alias#a1b2c3d4\\)\\)$";
        };
      };

      # LIVE CONTROL, same run: the identical two display keys, DISTINCT identities, resolve
      # cleanly — the plumbing works, and the cell above's refusal is about identity, not keys.
      test-control-distinct-identities-same-display-keys-resolve = {
        expr = (resolveAll { batch = distinctIdentitySameKeysBatch; }).value;
        expected = {
          theme = {
            font = "FIRST";
          };
          theme2 = {
            font = "SECOND";
          };
        };
      };

      # BOTH gated accessors, not just the one the fixture above happens to read — same
      # colliding construction, `.provenance` forced instead of `.value`.
      test-e7-duplicate-identity-provenance-also-refuses = {
        expr = (resolveAll { batch = dupIdentityBatch; }).provenance;
        expectedError = {
          type = "ThrownError";
          msg = "^gen-settings: duplicate batch identity \\(E7\\): 'a1b2c3d4' shared by 'theme' \\(aspect\\(theme#a1b2c3d4\\)\\) and 'theme2' \\(aspect\\(theme-alias#a1b2c3d4\\)\\)$";
        };
      };
    };

    # THE SUBSTITUTION REFUSES WHAT THE SCAN REFUSES — and says so at the position it refuses.
    #
    # `refsIn` derives the dependency graph and its domain is data; `substDeep` produces the value.
    # `resolveOne` is the surface where the difference is observable: its VALUE half reaches
    # `substDeep` without passing the scan, so while the dispatch ended in a bare `else v` a
    # function-valued field came back AS THE LAMBDA on that half while the PROVENANCE half of the
    # SAME call refused it. One call, two answers.
    #
    # ★ WHY THE POSITION IS THE ASSERTED THING. `builtins.tryEval` yields only `success`, so a
    # boolean cell cannot tell a refusal that names the offending field from one that says nothing
    # useful, and both satisfy it. The golden below is what holds the field-headed address; the
    # boolean pair beneath it is what holds the AGREEMENT, which no single message can show.
    #
    # ★ THE PREFIX IS THE ONE THING NOT PINNED ON PURPOSE. Whether a refusal of this kind speaks in
    # this library's E-vocabulary is unruled, and the rule under test is the position-naming, not
    # the vocabulary. Settling it rewrites this one string and nothing else in this suite.
    flake.testsError.substitution-domain = {
      test-value-arm-refuses-a-function-and-names-its-field = {
        expr = oneFn.value.f;
        expectedError = {
          type = "ThrownError";
          msg = "^gen-settings: cannot substitute into a value of type 'lambda': aspect\\(theme#a1b2c3d4\\)\\.f — substitution ranges over the same data the ref scan derives the dependency graph from, and that scan refuses this position rather than treating it as a leaf, so a value produced here would come from an input no dependency edge was ever derived over$";
        };
      };

      # THE DISCRIMINATOR: both halves of ONE call. The list is the cell rather than a conjunction
      # so a failure names WHICH half disagreed — before the dispatch was total this read
      # `[ false true ]`, and a `&&` would have reported only `false`.
      #
      # The provenance half is a boolean HERE and bytes in the cell below, and the split is not
      # arbitrary. A chain entry carries BOTH vocabularies: its `refs` come from the scan, so a
      # refusal reached through them is gen-schema's text, while its `value` is this library's own
      # substitution and refuses in this library's own. Which of the two a deepSeq of the whole
      # chain surfaces is decided by attr force order and is not a contract — measured, it is not
      # even stable across shapes of the offending value. So the honest claim for a cell that forces
      # the whole half is that it refuses, which is exactly a boolean; the bytes belong on a named
      # force point, and that is the next cell.
      test-one-call-both-arms-refuse-the-function = {
        expr = [
          (refuses oneFn.value)
          (refuses oneFn.provenance)
        ];
        expected = [
          true
          true
        ];
      };

      # THE PROVENANCE HALF'S OWN BYTES, at the entry's `value` — a NAMED force point, not a deepSeq
      # of the chain, so which of the entry's two vocabularies answers is decided here rather than by
      # attr order.
      #
      # ★ THIS CELL COVERS A CALL SITE THE GOLDEN ABOVE CANNOT REACH. The two halves of `resolveOne`
      # arrive at `substDeep` through DIFFERENT positions: the value half through `resolveOne`'s own
      # `mapAttrs`, the provenance half through `refineEntry`, each supplying the address the refusal
      # renders. Measured: with `refineEntry`'s address corrupted to name the wrong field, a user
      # reading this message is told the wrong position and BOTH SUITES STAY GREEN — the golden above
      # never runs that code. Identical expected bytes to that golden is the assertion, not a
      # duplication of it: the two halves must blame the same place, and the corruption that reddens
      # this cell leaves that one green.
      test-provenance-arm-refuses-a-function-and-names-the-same-field = {
        expr = (builtins.head oneFn.provenance.f).value;
        expectedError = {
          type = "ThrownError";
          msg = "^gen-settings: cannot substitute into a value of type 'lambda': aspect\\(theme#a1b2c3d4\\)\\.f — substitution ranges over the same data the ref scan derives the dependency graph from, and that scan refuses this position rather than treating it as a leaf, so a value produced here would come from an input no dependency edge was ever derived over$";
        };
      };

      # LIVE CONTROL, same run, same construction with the ref in DATA: both halves answer. Without
      # it the two cells above are satisfied by a `resolveOne` that refuses everything it is handed
      # — and a library that has stopped resolving produces refusals more readily, not less.
      test-control-one-call-both-arms-resolve-the-ref-in-data = {
        expr = [
          (refuses oneData.value)
          (refuses oneData.provenance)
        ];
        expected = [
          false
          false
        ];
      };

      # LIVE CONTROL, and the stronger one: substitution is not merely quiet on the data arm, it
      # SUBSTITUTES. The resolver returns "RESOLVED", so the ref must not survive into the value.
      test-control-data-arm-substitutes-the-ref = {
        expr = oneData.value;
        expected = {
          f = "RESOLVED";
        };
      };

      # LIVE CONTROL for the provenance golden, at the SAME NAMED FORCE POINT it reads. The entry's
      # `value` on the data construction is the SUBSTITUTED one, so the point that golden inspects is
      # demonstrably a point that resolves rather than one that refuses whatever it is handed — the
      # vacuity every cell asserting a refusal invites, checked here where the refusal is asserted.
      test-control-provenance-arm-substitutes-at-the-same-force-point = {
        expr = (builtins.head oneData.provenance.f).value;
        expected = "RESOLVED";
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
