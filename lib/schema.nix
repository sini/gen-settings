# mkSchema — a static, introspectable settings schema of `{ default; merge }` leaves.
#
# Nothing in a schema is a function: only class *content* is parametric and it *consumes*
# resolved settings. The schema stays plain data so the cross-aspect dependency graph is
# statically computable (Mokhov, Mitchell & Peyton Jones, *Build Systems à la Carte*, ICFP
# 2018, §3 — applicative task dependencies are known before any value is produced).
{ prelude }:
let
  inherit (builtins)
    attrNames
    mapAttrs
    elem
    match
    foldl'
    seq
    ;

  validMerges = [
    "replace"
    "append"
    "recursive"
  ];

  # A bare key contains no dots. Full-string match of "[^.]*" succeeds (→ [ ]) iff dot-free;
  # a dotted key fails the anchored match (→ null). Bare keys pin the Spike 5 finding that
  # double-nesting under the aspect produces cascade keys that never match.
  hasDot = name: match "[^.]*" name == null;
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
        if hasDot n then
          throw "gen-settings: schema (E1): field name '${n}' must be a bare key (no dots) — namespacing under the aspect happens at the consumer boundary"
        else
          acc
      ) null names;

      # Per-field normalization. Forcing a field's strategy/default (as the fold does) forces
      # this check; an unread field is never validated beyond its name and never forced.
      normField =
        name: field:
        if !(field ? default) then
          throw "gen-settings: schema (E1): field '${name}' has no 'default' — default is mandatory on every leaf"
        else
          let
            merge = field.merge or "replace";
          in
          if !(elem merge validMerges) then
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
