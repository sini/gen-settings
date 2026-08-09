# Refs — this library's E6 boundary over gen-schema's field-ref datum.
#
# The datum itself lives in gen-schema: the inert record shape, the identity law it enforces, and
# the deep structural scan that makes the cross-aspect dependency graph computable before any
# resolution (Mokhov, Mitchell & Peyton Jones, *Build Systems à la Carte*, ICFP 2018, §3 —
# static/applicative dependencies, not dynamic/monadic ones). It belongs there because it is the
# INHABITANT of gen-schema's reference type: the type declares that a field points at an instance,
# the value names which one, and splitting the two across libraries is how they drift apart.
#
# What stays here is this library's ERROR VOCABULARY. E6 is gen-settings' code, gen-settings' text
# and gen-settings' throw, fired at gen-settings' boundary before the datum is ever constructed —
# the same division that kept the E3 diagnostic here when cycle detection moved to gen-graph. The
# destination supplies the machinery; the caller keeps the blame.
#
# ★ THE SCAN REFUSES FUNCTIONS, AND THAT IS A USER-VISIBLE CONTRACT. A function in a scanned
#   position throws rather than being skipped as a leaf, so a ref buried in a function body is an
#   error instead of an invisible edge. A schema is plain data by its own contract (see schema.nix:
#   only class *content* is parametric, and it *consumes* resolved settings), so on conforming
#   input the refusal fires never; where it would fire, the alternative was worse than a missed
#   diagnostic — the edge could not be derived, the cycle it would have closed went undetected, and
#   the unresolved ref record leaked into output as data.
{ genSchema }:
let
  inherit (builtins)
    isAttrs
    isList
    all
    isString
    ;
in
{
  # The datum's predicate and scan, unchanged: gen-settings adds nothing to them, and wrapping
  # them would put a second implementation of a graph-bearing shape in the consumer.
  isRef = genSchema.isFieldRef;
  refsIn = genSchema.fieldRefsIn;

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
      genSchema.fieldRef aspectEntry path;
}
