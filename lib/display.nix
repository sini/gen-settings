# Display helpers — address rendering for error messages and consumer introspection.
#
# Identity law (roadmap §1.10): graph keys and provenance coordinates are id_hash-based
# internally; the rendered string is name + an 8-char id_hash prefix and is DISPLAY ONLY —
# never parsed back into an identity.
{ prelude }:
let
  inherit (builtins) substring concatStringsSep;

  shortHash = h: substring 0 8 h;

  # The unchecked core every internal diagnostic calls (spec §p2.3.2: internal callers of a door call
  # its core). Its argument is an ADDRESS, the `{ aspect; field?; path?; }` coordinate the
  # diagnostics already carry, not a door record.
  renderAt =
    {
      aspect,
      field ? null,
      path ? null,
    }:
    let
      base = "aspect(${aspect.name}#${shortHash aspect.id_hash})";
      fieldPart = if field == null then "" else ".${field}";
      pathPart = if path == null then "" else ".${concatStringsSep "." path}";
    in
    base + fieldPart + pathPart;
in
{
  inherit shortHash renderAt;

  # renderAddress { field ? null; path ? null; } aspect -> string
  #   "aspect(theme#a1b2c3d4)"            (aspect only)
  #   "aspect(theme#a1b2c3d4).font"       (aspect + field)
  #   "aspect(theme#a1b2c3d4).font.mono"  (aspect + field-headed path)
  #
  # OPTIONS FIRST, THEN THE ASPECT (den-hoag-7gp66 P2, rules 2 and 4): the two optional fields leave
  # for one closed options set, a `prelude.door` refused by name and catchably at `renderAddress
  # opts`'s own WHNF; the aspect is the subject, positional and last, so `renderAddress { field; }`
  # is a renderer mapped over aspects.
  renderAddress =
    prelude.door
      {
        name = "gen-settings.renderAddress";
        optional = [
          "field"
          "path"
        ];
      }
      (
        o: aspect:
        renderAt {
          inherit aspect;
          field = o.field or null;
          path = o.path or null;
        }
      );

}
