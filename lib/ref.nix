# Refs — inert, identity-bearing cross-aspect references.
#
# A ref is plain data (no functions, no thunk wrappers): a schema or contribution containing
# refs stays fully introspectable, and the cross-aspect dependency graph is computable before
# any resolution (Mokhov et al., *Build Systems à la Carte*, ICFP 2018, §3 — static/applicative
# dependencies, not dynamic/monadic ones).
{ prelude }:
let
  inherit (builtins)
    isAttrs
    isList
    all
    isString
    attrNames
    concatLists
    map
    ;
  inherit (prelude) imap0;

  refMarker = "__genSettingsRef";

  isRef = v: isAttrs v && (v.${refMarker} or false) == true;
in
{
  inherit isRef refMarker;

  # ref aspectEntry path -> ref record
  #   aspectEntry MUST carry id_hash (identity law) — a string or any value without id_hash
  #   throws E6 immediately at application time; strings never cross the boundary.
  ref =
    aspectEntry: path:
    if !(isAttrs aspectEntry && aspectEntry ? id_hash) then
      throw "gen-settings: ref (E6): ref target must be an aspect registry entry carrying id_hash, never a name string"
    else if !(isList path && path != [ ] && all isString path) then
      throw "gen-settings: ref (E6): path must be a non-empty list of field-name strings"
    else
      {
        ${refMarker} = true;
        aspect = aspectEntry;
        inherit path;
      };

  # refsIn v -> [ { at; aspect; path; } ] — deep structural scan.
  #   `at` is the subpath within v where the ref sits ([ ] = v itself); attrset keys and list
  #   indices compose it. Refs are inspected as records, never resolved (L7). The scan is
  #   structurally strict (L17): detecting a ref forces its position to WHNF, since Nix has no
  #   primitive that inspects a thunk without forcing it. Functions and non-collection scalars
  #   are leaves — a ref buried in a function body is invisible and unsupported (refs are data).
  refsIn =
    v:
    let
      go =
        at: val:
        if isRef val then
          [
            {
              inherit at;
              inherit (val) aspect path;
            }
          ]
        else if isAttrs val then
          concatLists (map (k: go (at ++ [ k ]) val.${k}) (attrNames val))
        else if isList val then
          concatLists (imap0 (i: e: go (at ++ [ i ]) e) val)
        else
          [ ];
    in
    go [ ] v;
}
