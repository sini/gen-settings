# THE DOOR CHECKS (den-hoag-7gp66 P2 — `prelude.door`, R7 argument structure / R5 field closure) —
# every published step of gen-settings that takes a RECORD catches its own violations, at its own
# application, catchably.
#
# After P2 a door step is one of two kinds (spec §p2.3.1):
#   · an OPTIONS step — one closed set, first in the call: `renderAddress { field?; path?; } aspect`,
#     `resolveOne { resolveRef?; strict?; } schema layers`, `injectAspectSettings { settingsKey?;
#     bindings?; contracts?; provenance?; } …` and `assembleHost { bindings?; } …`;
#   · a RECORD step — open, all fields required (R5), behind its options step and guarded by it
#     (`optionsStep`, G10): `{ aspect; settings; }` before the class content, and `{ class; aspects; }`
#     before the entity (the keyed-record ruling: two configuration operands with no natural order).
# `mkSchema aspect fields` and `resolveAll batch` are positional (rule 4): their arity is structural
# and they carry no row.
#
# WHICH refusal fired is a claim about the message and `tryEval` yields only `success`; the byte
# goldens naming each door (R6) live in `ci/tests-error.nix`'s `flake.testsError.door-checks`.
{
  lib,
  genSettings,
  prelude,
  ...
}:
let
  gs = genSettings;
  fx = import ./_fixtures/fixtures.nix { inherit lib; };
  inherit (fx.aspects) theme;
  inherit (fx.entities) axon blade;
  inherit (fx.classes) nixos;

  # `firesAtApplication` forces the step's application to WHNF only — never `deepSeq` — so a check
  # that ran only behind a later field read reads `false` (spec §p2.5, premise 5).
  firesAtApplication = e: !(builtins.tryEval (builtins.seq e null)).success;
  answers = e: (builtins.tryEval (builtins.deepSeq e null)).success;

  schema = gs.mkSchema theme {
    font.default = "mono";
  };
  layer = fx.mkLayer {
    rendered = "host";
    value.font = "sans";
  };
  # Class content that reports what the injection handed it: the settings keys it sees, and the
  # caller binding `extra` when one is bound.
  part = {
    aspect = theme;
    classContent =
      {
        settings,
        extra,
        ...
      }:
      {
        options.seen = lib.mkOption {
          default = {
            keys = builtins.attrNames settings;
            inherit extra;
          };
        };
      };
    settings.font = "sans";
  };
  # `extra` defaults to `null` as a module argument, which a caller binding shadows (`bindWins`).
  seenIn =
    module:
    (lib.evalModules {
      modules = [
        module
        { _module.args.extra = null; }
      ];
    }).config.seen;

  # The options rows: the door, its options, `apply` supplying the operands after the options step,
  # and one non-default option whose value the door's own result carries (G3), read by `observe`.
  optionsRows = {
    renderAddress = {
      optional = [
        "field"
        "path"
      ];
      apply = f: f theme;
      observe = r: r;
      opt.field = "font";
    };
    resolveOne = {
      optional = [
        "resolveRef"
        "strict"
      ];
      apply =
        f:
        f schema [
          (layer // { value.stray = 1; })
        ];
      # `strict = false` admits the undeclared field the layer carries, which the default refuses.
      observe = r: answers r.value;
      opt.strict = false;
    };
    injectAspectSettings = {
      optional = [
        "settingsKey"
        "bindings"
        "contracts"
        "provenance"
      ];
      apply = f: f { inherit (part) aspect settings; } part.classContent;
      observe = r: seenIn r.module;
      opt.settingsKey = "renamed";
    };
    assembleHost = {
      optional = [ "bindings" ];
      apply =
        f:
        f {
          class = nixos;
          aspects = [ part ];
        } axon;
      observe = r: seenIn r.theme;
      opt.bindings.extra = 1;
    };
  };

  # The record steps behind each chained options step: the step `{ }` forms, its required fields, and
  # one complete record it answers on.
  recordRows = {
    injectAspectSettings = {
      step = gs.injectAspectSettings { };
      required = [
        "aspect"
        "settings"
      ];
      good = {
        inherit (part) aspect settings;
      };
      operand = part.classContent;
    };
    assembleHost = {
      step = gs.assembleHost { };
      required = [
        "class"
        "aspects"
      ];
      good = {
        class = nixos;
        aspects = [ part ];
      };
      operand = axon;
    };
  };

  # A field name no door declares, generated per evaluation from the door names themselves, so it is
  # never a name any contract below lists.
  stranger = "not-a-field-of-" + builtins.concatStringsSep "-" (builtins.attrNames optionsRows);

  perOptions = f: builtins.mapAttrs f optionsRows;
  perRecord = f: builtins.mapAttrs f recordRows;

  surfaceDoors = builtins.attrNames (
    prelude.filterAttrs (
      _: v:
      let
        t = builtins.tryEval (builtins.isAttrs v && v ? __functor && v ? __contract);
      in
      t.success && t.value
    ) gs
  );
in
{
  flake.tests.door-checks = {
    # ── LIVE CONTROLS, first: the predicates are not dead ──
    test-control-firesAtApplication-is-true-for-an-ordinary-throw = {
      expr = firesAtApplication (throw "control probe, not this suite's subject");
      expected = true;
    };
    test-control-firesAtApplication-is-false-for-a-throw-behind-an-unread-field = {
      expr = firesAtApplication { culprit = throw "control probe, not this suite's subject"; };
      expected = false;
    };

    # ── THE TABLE IS THE SURFACE ──
    # Every published door has a row and every row is a published door, so a door added without a
    # row — or a row whose door reverted to a lambda — reds here.
    test-the-door-table-equals-the-surface-doors = {
      expr = surfaceDoors;
      expected = builtins.sort (a: b: a < b) (builtins.attrNames optionsRows);
    };
    test-the-positional-entries-are-plain-lambdas = {
      expr = map (n: builtins.isFunction gs.${n}) [
        "mkSchema"
        "resolveAll"
      ];
      expected = [
        true
        true
      ];
    };
    test-control-the-positional-entries-answer = {
      expr = {
        schema = schema.defaults;
        all =
          (gs.resolveAll [
            {
              inherit schema;
              layers = [ layer ];
            }
          ]).value;
      };
      expected = {
        schema.font = "mono";
        all.theme.font = "sans";
      };
    };

    # ── OPTIONS STEPS ──
    # G1/G4: an unknown option is refused at `f opts`'s WHNF, before any operand.
    test-an-unknown-option-is-refused-at-the-options-application = {
      expr = perOptions (n: _: firesAtApplication (gs.${n} { ${stranger} = 1; }));
      expected = perOptions (_: _: true);
    };
    test-a-non-set-options-argument-is-refused-at-the-application = {
      expr = perOptions (n: _: firesAtApplication (gs.${n} 1));
      expected = perOptions (_: _: true);
    };
    # The old one-record shape is refused by name at its first application: its fields are not
    # options of the door.
    test-the-old-one-record-shape-is-refused-at-the-application = {
      expr = {
        renderAddress = firesAtApplication (gs.renderAddress { aspect = theme; });
        resolveOne = firesAtApplication (
          gs.resolveOne {
            inherit schema;
            layers = [ ];
          }
        );
        injectAspectSettings = firesAtApplication (gs.injectAspectSettings part);
        assembleHost = firesAtApplication (
          gs.assembleHost {
            entity = axon;
            class = nixos;
            aspects = [ ];
          }
        );
      };
      expected = perOptions (_: _: true);
    };
    # The live control: `{ }` forms the door and the operands answer.
    test-control-the-empty-options-answer = {
      expr = perOptions (n: r: answers (r.observe (r.apply (gs.${n} { }))));
      expected = perOptions (_: _: true);
    };
    # Every option of each door is admitted, together.
    test-every-option-is-admitted = {
      expr = perOptions (n: r: !firesAtApplication (gs.${n} (prelude.genAttrs r.optional (_: null))));
      expected = perOptions (_: _: true);
    };
    # D3: the published contract and the functor-aware reader agree with the row.
    test-each-options-door-publishes-its-contract = {
      expr = perOptions (
        n: _: {
          inherit (gs.${n}.__contract) optional open required;
          args = prelude.functionArgs gs.${n};
        }
      );
      expected = perOptions (
        _: r: {
          inherit (r) optional;
          open = false;
          required = [ ];
          args = builtins.listToAttrs (map (f: prelude.nameValuePair f true) r.optional);
        }
      );
    };
    # G3: a non-default option reaches the result (`differ`, against `{ }`), and the partially
    # applied door agrees with the full call (`agree`), each read from its own evaluation.
    test-a-non-default-option-reaches-the-result = {
      expr = perOptions (
        n: r:
        let
          f1 = gs.${n} r.opt;
          run = f: r.observe (r.apply f);
        in
        {
          agree = run f1 == run (gs.${n} r.opt);
          differ = run f1 != run (gs.${n} { });
        }
      );
      expected = perOptions (
        _: _: {
          agree = true;
          differ = true;
        }
      );
    };
    # Composition: `assembleHost opts record` is a value mapped over entities.
    test-a-partially-applied-door-maps-over-entities = {
      expr =
        let
          assemble = gs.assembleHost { } {
            class = nixos;
            aspects = [ part ];
          };
        in
        map (e: builtins.attrNames (assemble e)) [
          axon
          blade
        ];
      expected = [
        [ "theme" ]
        [ "theme" ]
      ];
    };

    # ── RECORD STEPS (R5: open, all fields required) ──
    # D2: a missing required field is refused at the record's application, before any field read.
    test-each-missing-required-field-is-refused-at-the-application = {
      expr = perRecord (
        _: r: map (f: firesAtApplication (r.step (builtins.removeAttrs r.good [ f ]))) r.required
      );
      expected = perRecord (_: r: map (_: true) r.required);
    };
    # G2: an extra field is admitted, answer unchanged (R5's stated price).
    test-an-extra-field-is-admitted-and-the-answer-is-unchanged = {
      expr = perRecord (
        _: r:
        builtins.attrNames (r.step (r.good // { ${stranger} = 1; }) r.operand)
        == builtins.attrNames (r.step r.good r.operand)
      );
      expected = perRecord (_: _: true);
    };
    # G10: an option of the step's own options door, given on the record instead, is refused by name
    # at the record's application rather than silently ignored.
    test-an-option-given-on-the-record-is-refused-at-the-record-application = {
      expr = perRecord (
        n: r: map (o: firesAtApplication (r.step (r.good // { ${o} = null; }))) optionsRows.${n}.optional
      );
      expected = perRecord (n: _: map (_: true) optionsRows.${n}.optional);
    };
    # D3: the record step's contract is published, and the options step names it as its next.
    test-each-record-step-publishes-its-contract = {
      expr = perRecord (
        n: r: {
          inherit (r.step.__contract) required open;
          next = gs.${n}.__contract.next == r.step.__contract;
        }
      );
      expected = perRecord (
        _: r: {
          inherit (r) required;
          open = true;
          next = true;
        }
      );
    };
  };
}
