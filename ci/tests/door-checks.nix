# THE CLOSED-DOOR CHECKS (den-hoag-7gp66 P1) — every published door catches its own violations.
#
# A native closed formal (`{ aspect, fields }:`) aborts UNCATCHABLY on an unknown or a missing
# argument — not even `builtins.tryEval` sees it, which is ADR-0025 item 1's named defect. Each of
# the six doors below now takes a bare positional formal and applies gen-prelude's shared
# `checkOptions`/`checkRequired` (0ac7b66) instead, so the same violations are NAMED and CATCHABLE.
#
# ★ THE DOOR CLASSES SPLIT THE FAMILY IN TWO. `mkSchema` and `resolveAll` are RECORD doors —
# all-required, `checkRequired` only — and R5's stated price is that they are OPEN: an extra field
# is silently admitted, never refused. `renderAddress`, `resolveOne`, `injectAspectSettings` and
# `assembleHost` are MIXED doors — required plus optional, `checkOptions` composed over
# `checkRequired` — and stay CLOSED on both axes until P2 splits the options off the record.
#
# WHICH refusal fired is a claim about the message and `tryEval` yields only `success`; the byte
# goldens naming each door (R6) live in `ci/tests-error.nix`'s `flake.testsError.door-checks`, the
# same split `resolution-errors.nix`'s own header states for the pre-existing E-code diagnostics.
{
  lib,
  genSettings,
  ...
}:
let
  inherit (genSettings)
    mkSchema
    renderAddress
    resolveOne
    resolveAll
    injectAspectSettings
    assembleHost
    ;
  fx = import ./_fixtures/fixtures.nix { inherit lib; };
  inherit (fx.aspects) theme;
  inherit (fx.entities) axon;
  inherit (fx.classes) nixos;

  # `success == false` pins catchability, not the message — the byte goldens are the message's own
  # test. Forced with `deepSeq null` so a lazily-returned attrset's unread check still runs: the
  # check binding is what refuses, and a bare `(mkSchema args).aspect` would never touch it for a
  # door whose violation is on a field this cell does not read.
  refusesCatchably = e: !(builtins.tryEval (builtins.deepSeq e null)).success;
  answers = e: (builtins.tryEval (builtins.deepSeq e null)).success;

  validSchema = mkSchema {
    aspect = theme;
    fields = { };
  };
in
{
  flake.tests.door-checks = {
    # ★ LIVE CONTROL FOR THE WHOLE SUITE, first: `tryEval` catches an ORDINARY throw, and a
    # non-throwing value answers. Without this, every `refusesCatchably` cell below is equally
    # consistent with a broken helper that reads `false` no matter what it is handed.
    test-control-tryeval-catches-an-ordinary-throw = {
      expr = refusesCatchably (throw "control probe, not this suite's subject");
      expected = true;
    };
    test-control-tryeval-answers-a-non-throwing-value = {
      expr = answers 1;
      expected = true;
    };

    # mkSchema — RECORD class (checkRequired only).
    test-mkschema-missing-required-field-refused-catchably = {
      expr = refusesCatchably (mkSchema {
        aspect = theme;
      });
      expected = true;
    };
    # R5's stated price: an extra field on a record door is ADMITTED, not refused.
    test-mkschema-extra-field-on-a-record-is-admitted = {
      expr = answers (mkSchema {
        aspect = theme;
        fields = { };
        zzsettl3xq = 1;
      });
      expected = true;
    };
    test-mkschema-valid-call-is-unchanged = {
      expr = validSchema.aspect.name;
      expected = "theme";
    };

    # renderAddress — MIXED class (checkOptions over checkRequired).
    test-renderaddress-missing-required-field-refused-catchably = {
      expr = refusesCatchably (renderAddress {
        field = "f";
      });
      expected = true;
    };
    test-renderaddress-unknown-option-refused-catchably = {
      expr = refusesCatchably (renderAddress {
        aspect = theme;
        zzsettl3xq = 1;
      });
      expected = true;
    };
    test-renderaddress-valid-call-is-unchanged = {
      expr = renderAddress { aspect = theme; };
      expected = "aspect(theme#a1b2c3d4)";
    };

    # resolveAll — RECORD class (checkRequired only).
    test-resolveall-missing-required-field-refused-catchably = {
      expr = refusesCatchably (resolveAll { });
      expected = true;
    };
    # R5's stated price, on the second record door.
    test-resolveall-extra-field-on-a-record-is-admitted = {
      expr = answers (resolveAll {
        batch = [ ];
        zzsettl3xq = 1;
      });
      expected = true;
    };
    test-resolveall-valid-call-is-unchanged = {
      expr = (resolveAll { batch = [ ]; }).value;
      expected = { };
    };

    # resolveOne — MIXED class.
    test-resolveone-missing-required-field-refused-catchably = {
      expr = refusesCatchably (resolveOne {
        layers = [ ];
      });
      expected = true;
    };
    test-resolveone-unknown-option-refused-catchably = {
      expr = refusesCatchably (resolveOne {
        schema = validSchema;
        layers = [ ];
        zzsettl3xq = 1;
      });
      expected = true;
    };
    test-resolveone-valid-call-is-unchanged = {
      expr =
        (resolveOne {
          schema = validSchema;
          layers = [ ];
        }).value;
      expected = { };
    };

    # injectAspectSettings — MIXED class.
    test-injectaspectsettings-missing-required-field-refused-catchably = {
      expr = refusesCatchably (injectAspectSettings {
        aspect = theme;
        classContent = { };
      });
      expected = true;
    };
    test-injectaspectsettings-unknown-option-refused-catchably = {
      expr = refusesCatchably (injectAspectSettings {
        aspect = theme;
        classContent = { };
        settings = { };
        zzsettl3xq = 1;
      });
      expected = true;
    };
    test-injectaspectsettings-valid-call-is-unchanged = {
      expr = answers (injectAspectSettings {
        aspect = theme;
        classContent = { };
        settings = { };
      });
      expected = true;
    };

    # assembleHost — MIXED class.
    test-assemblehost-missing-required-field-refused-catchably = {
      expr = refusesCatchably (assembleHost {
        entity = axon;
        class = nixos;
      });
      expected = true;
    };
    test-assemblehost-unknown-option-refused-catchably = {
      expr = refusesCatchably (assembleHost {
        entity = axon;
        class = nixos;
        aspects = [ ];
        zzsettl3xq = 1;
      });
      expected = true;
    };
    test-assemblehost-valid-call-is-unchanged = {
      expr = assembleHost {
        entity = axon;
        class = nixos;
        aspects = [ ];
      };
      expected = { };
    };
  };
}
