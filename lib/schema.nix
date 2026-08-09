# mkSchema — a static, introspectable settings schema of `{ default; merge }` leaves.
#
# Nothing in a schema is a function: only class *content* is parametric and it *consumes*
# resolved settings. The schema stays plain data so the cross-aspect dependency graph is
# statically computable (Mokhov, Mitchell & Peyton Jones, *Build Systems à la Carte*, ICFP
# 2018, §3 — applicative task dependencies are known before any value is produced).
#
# What a well-formed field IS, is stated as gen-types checkers rather than hand-rolled tests: a
# type is a boundary that blames the value on mismatch (Findler & Felleisen, *Contracts for
# Higher-Order Functions*, ICFP 2002), and a refinement is a base checker plus a predicate
# co-located with it (Rondon, Kawaguchi & Jhala, *Liquid Types*, PLDI 2008). What gen-settings
# says when a field is ill-formed is E1 — the checkers supply the predicate, this library keeps
# the diagnostic, and each checker states exactly one obligation so each maps to exactly one E1.
{ prelude, genTypes }:
let
  inherit (builtins)
    attrNames
    mapAttrs
    foldl'
    seq
    ;

  # A bare key is a dot-free string. Bare keys pin the Spike 5 finding that double-nesting under
  # the aspect produces cascade keys that never match. `hasInfix` is prelude's containment test —
  # one `split` on the escaped literal, carrying no `.*` anchor to make the engine recurse on the
  # subject's length; it is the vendored drop-in for nixpkgs' `lib.hasInfix`.
  bareKey = genTypes.refined genTypes.string [
    {
      check = name: !(prelude.hasInfix "." name);
      message = "must be a bare key (no dots)";
    }
  ];

  # `default` is mandatory; its VALUE is unconstrained. Typing it `any` — whose verifier is
  # `_: null` — is what keeps whole-record verification from forcing the default, so an unread
  # field stays unforced for the fold. Typing it as anything else would force it.
  # `merge` is deliberately NOT a member here: it is checked after defaulting, below, so that
  # this checker's failure means "no default" and nothing else.
  fieldRecord = genTypes.struct "field" {
    default = genTypes.any;
  };

  # The EFFECTIVE merge strategy, i.e. the one checked after `merge or "replace"` defaulting.
  mergeStrategy = genTypes.enum "merge" [
    "replace"
    "append"
    "recursive"
  ];
in
{
  # mkSchema { aspect; fields } -> { aspect; fields; strategies; defaults; }
  #   aspect  — registry entry carrying id_hash (the declaring identity)
  #   fields  — { <bare-key> = { default; merge ? "replace"; }; }
  mkSchema =
    {
      aspect,
      fields,
    }:
    let
      names = attrNames fields;

      # Eager, name-level: dotted keys are E1 the moment the schema is used at all — the
      # names are static and cheap, so this does not force any `default` value (laziness of
      # unread defaults is preserved for the fold).
      dotCheck = foldl' (
        acc: n:
        if bareKey.verify n != null then
          throw "gen-settings: schema (E1): field name '${n}' must be a bare key (no dots) — namespacing under the aspect happens at the consumer boundary"
        else
          acc
      ) null names;

      # Per-field normalization. Forcing a field's strategy/default (as the fold does) forces
      # this check; an unread field is never validated beyond its name and never forced.
      normField =
        name: field:
        if fieldRecord.verify field != null then
          throw "gen-settings: schema (E1): field '${name}' has no 'default' — default is mandatory on every leaf"
        else
          let
            merge = field.merge or "replace";
          in
          if mergeStrategy.verify merge != null then
            throw "gen-settings: schema (E1): field '${name}' has unknown merge strategy '${merge}' (expected replace|append|recursive)"
          else
            {
              inherit (field) default;
              inherit merge;
            };

      normalized = mapAttrs normField fields;
    in
    seq dotCheck {
      inherit aspect;
      fields = normalized;
      # The exact shapes foldLayersTraced consumes.
      strategies = mapAttrs (_: f: f.merge) normalized;
      defaults = mapAttrs (_: f: f.default) normalized;
    };
}
