# THE DOOR CHECKS FIRE AT APPLICATION, NOT ONLY BEHIND A LATER FIELD READ (den-hoag-7gp66 P2).
#
# `door-checks.nix` proves the six doors' checkOptions/checkRequired violations are CATCHABLE, but
# does so with `deepSeq` — and its own comment already names the gap that leaves open: "a bare
# `(mkSchema args).aspect` would never touch it for a door whose violation is on a field this cell
# does not read." This file closes that gap with a narrower, harder predicate: `seq` alone, to
# WHNF of the door's OWN return, reading NO field at all — the shape of a defensive
# `builtins.seq (door args) rest` a caller writes to gate on validity before touching any output.
#
# MEASURED (den-hoag-7gp66 P2, gen-memo eed0685's defect class — a check that sits behind a later
# read is a check a caller who does not make that read never runs): three of the six doors —
# `resolveOne`, `resolveAll`, `injectAspectSettings` — returned a bare attrset literal, whose own
# WHNF forces none of its fields, so a bad record sailed through the door's own application and
# was admitted until a caller happened to force one of `.value`/`.provenance`/`.graph`/`.module`/
# `.wrapped`/`.signature`. Fixed by threading `seq checked` (`builtins.seq checked` in `inject.nix`,
# which does not otherwise import `seq`) through the return — the same idiom `mkSchema`'s
# `seq dotCheck` and `assembleHost`'s `builtins.seq classOk (builtins.seq entityOk …)` already use,
# which is also why those two, plus `renderAddress` (a string built by `+`, forced whole), were
# already strict here and need no fix; their cells below are the pin.
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

  # `seq`, not `deepSeq`: WHNF of the door's own return, no field read — the strictly narrower
  # predicate `door-checks.nix`'s `deepSeq`-based `refusesCatchably` cannot discriminate, since
  # `deepSeq` forces straight through to the same guard whichever field it hangs off.
  refusesAtApplication = e: !(builtins.tryEval (builtins.seq e null)).success;
  answersAtApplication = e: (builtins.tryEval (builtins.seq e null)).success;

  validSchema = mkSchema {
    aspect = theme;
    fields = { };
  };
in
{
  flake.tests.door-application-strictness = {
    # ★ LIVE CONTROL FOR THE WHOLE SUITE, first: `tryEval`+`seq` catches an ordinary throw, and a
    # non-throwing value answers. Without this, every `refusesAtApplication` cell below is equally
    # consistent with a predicate that reads `false` no matter what it is handed.
    test-control-tryeval-seq-catches-an-ordinary-throw = {
      expr = refusesAtApplication (throw "control probe, not this suite's subject");
      expected = true;
    };
    test-control-tryeval-seq-answers-a-non-throwing-value = {
      expr = answersAtApplication 1;
      expected = true;
    };

    # mkSchema — already strict (`seq dotCheck` forces `checked` via `checked.fields` before the
    # return is built). Pinned, not fixed.
    test-mkschema-missing-required-field-refused-at-application = {
      expr = refusesAtApplication (mkSchema {
        aspect = theme;
      });
      expected = true;
    };

    # renderAddress — already strict (the return is a string built by `+`, which forces both
    # operands whole, so `aspect.name` — hence `checked` — is forced regardless of which optional
    # argument is supplied). Pinned, not fixed.
    test-renderaddress-missing-required-field-refused-at-application = {
      expr = refusesAtApplication (renderAddress {
        field = "f";
      });
      expected = true;
    };
    test-renderaddress-unknown-option-refused-at-application = {
      expr = refusesAtApplication (renderAddress {
        aspect = theme;
        zzsettl3xq = 1;
      });
      expected = true;
    };

    # resolveAll — FIXED (P2): was a bare attrset literal; now `seq checked { … }`.
    test-resolveall-missing-required-field-refused-at-application = {
      expr = refusesAtApplication (resolveAll { });
      expected = true;
    };
    # R5's stated price is unchanged: an extra field on a record door is still admitted, and is
    # admitted at application too — `checkRequired` never looks at it either way.
    test-resolveall-extra-field-on-a-record-is-admitted-at-application = {
      expr = answersAtApplication (resolveAll {
        batch = [ ];
        zzsettl3xq = 1;
      });
      expected = true;
    };

    # resolveOne — FIXED (P2): was a bare attrset literal; now `seq checked { … }`.
    test-resolveone-missing-required-field-refused-at-application = {
      expr = refusesAtApplication (resolveOne {
        layers = [ ];
      });
      expected = true;
    };
    test-resolveone-unknown-option-refused-at-application = {
      expr = refusesAtApplication (resolveOne {
        schema = validSchema;
        layers = [ ];
        zzsettl3xq = 1;
      });
      expected = true;
    };

    # injectAspectSettings — FIXED (P2): was a bare attrset literal; now
    # `builtins.seq checked { … }`.
    test-injectaspectsettings-missing-required-field-refused-at-application = {
      expr = refusesAtApplication (injectAspectSettings {
        aspect = theme;
        classContent = { };
      });
      expected = true;
    };
    test-injectaspectsettings-unknown-option-refused-at-application = {
      expr = refusesAtApplication (injectAspectSettings {
        aspect = theme;
        classContent = { };
        settings = { };
        zzsettl3xq = 1;
      });
      expected = true;
    };

    # assembleHost — already strict (`builtins.seq classOk (builtins.seq entityOk …)` forces
    # `checked` via `classOk`/`entityOk` before the return is built). Pinned, not fixed.
    test-assemblehost-missing-required-field-refused-at-application = {
      expr = refusesAtApplication (assembleHost {
        entity = axon;
        class = nixos;
      });
      expected = true;
    };
    test-assemblehost-unknown-option-refused-at-application = {
      expr = refusesAtApplication (assembleHost {
        entity = axon;
        class = nixos;
        aspects = [ ];
        zzsettl3xq = 1;
      });
      expected = true;
    };
  };
}
