# Display helpers — address rendering for error messages and consumer introspection.
#
# Identity law (roadmap §1.10): graph keys and provenance coordinates are id_hash-based
# internally; the rendered string is name + an 8-char id_hash prefix and is DISPLAY ONLY —
# never parsed back into an identity.
{ prelude }:
let
  inherit (builtins) substring concatStringsSep;

  shortHash = h: substring 0 8 h;
in
{
  inherit shortHash;

  # renderAddress { aspect, field ? null, path ? null } -> string
  #   "aspect(theme#a1b2c3d4)"            (aspect only)
  #   "aspect(theme#a1b2c3d4).font"       (aspect + field)
  #   "aspect(theme#a1b2c3d4).font.mono"  (aspect + field-headed path)
  #
  # MIXED class (den-hoag-7gp66 P1): closed over the whole set — transitional, per §v1.2, until P2
  # moves the options off the record.
  renderAddress =
    args:
    let
      checked = prelude.checkOptions "gen-settings.renderAddress" [
        "aspect"
        "field"
        "path"
      ] (prelude.checkRequired "gen-settings.renderAddress" [ "aspect" ] args);
      aspect = checked.aspect;
      field = checked.field or null;
      path = checked.path or null;
      base = "aspect(${aspect.name}#${shortHash aspect.id_hash})";
      fieldPart = if field == null then "" else ".${field}";
      pathPart = if path == null then "" else ".${concatStringsSep "." path}";
    in
    base + fieldPart + pathPart;
}
