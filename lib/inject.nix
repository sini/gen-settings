# injectAspectSettings / assembleHost — resolved settings into parametric class content.
#
# gen-bind `wrap` (= wrapCore) does the work; gen-settings adds only the aspect-settings
# conventions. Always-wrap, no `isFunction` guard: registered classes are deferredModules, which
# coerce a lone function to `{ imports = [ fn ]; }`, so `isFunction` cannot distinguish parametric
# from static content — guarding on it is wrong by construction (Spike 5). Identity keying inherits
# gen-bind's Cardelli linkset identity (*Program Fragments, Linking, and Modularization*, POPL 1997
# §3 — linksets carry identity used to resolve duplicates).
{
  prelude,
  bind,
}:
let
  inherit (builtins)
    map
    listToAttrs
    filter
    attrNames
    foldl'
    isAttrs
    head
    ;

  # injectAspectSettings { aspect; classContent; settings; settingsKey ?; bindings ?; contracts ?;
  #   provenance ? } -> { module; wrapped; signature; }
  # The injected settings binding is namespaced: settings = { ${settingsKey} = <resolved>; }, so
  # content reads `settings.<key>.<field>`. gen-bind's default `bindWins` shadows stray same-named
  # module args; lib/config/pkgs still flow from the module system (never injected).
  injectAspectSettings =
    {
      aspect,
      classContent,
      settings,
      settingsKey ? aspect.name,
      bindings ? { },
      contracts ? { },
      provenance ? { },
    }:
    let
      allBindings = bindings // {
        settings = {
          ${settingsKey} = settings;
        };
      };
      result = bind.wrap {
        module = classContent;
        bindings = allBindings;
        inherit contracts provenance;
      };
    in
    {
      inherit (result) module wrapped signature;
    };

  # assembleHost { entity; class; aspects; bindings ? } -> { <settingsKey> = <identity-keyed module>; }
  #   entity — consuming entity (host/user registry entry) OR a cell record; either way MUST carry
  #            id_hash (a plain entity's content-addressed hash, or a cell's canonical cell identity).
  #   class  — class REGISTRY ENTRY; its `name` is the internal wrapIdentity key token.
  # Keys derive from id_hash pairs, never names, on the entity/aspect axes (identity law): distinct
  # entities (or cells) with the same aspect yield distinct evalModules keys and are not
  # dedup-collapsed; the same (class, entity, aspect) reaching one eval twice carries an equal key
  # and merges once. Duplicate settingsKey within one call is E8 (a module would otherwise be
  # silently dropped by attrset collision — the failure identity keying exists to prevent).
  assembleHost =
    {
      entity,
      class,
      aspects,
      bindings ? { },
    }:
    let
      classOk =
        if !(isAttrs class && class ? name) then
          throw "gen-settings: assembleHost (L14): `class` must be a class registry entry (carrying a name), never a class-name string"
        else
          class;
      entityOk =
        if !(isAttrs entity && entity ? id_hash) then
          throw "gen-settings: assembleHost (L14): `entity` must carry id_hash (a registry entry, or a cell record with a canonical cell identity)"
        else
          entity;

      keyed = map (a: a // { _key = a.settingsKey or a.aspect.name; }) aspects;
      counts = foldl' (acc: a: acc // { ${a._key} = (acc.${a._key} or 0) + 1; }) { } keyed;
      dupKeys = filter (k: counts.${k} > 1) (attrNames counts);
      e8 =
        let
          dup = head dupKeys;
          culprits = map (a: a.aspect) (filter (a: a._key == dup) keyed);
        in
        throw "gen-settings: duplicate settingsKey (E8): '${dup}' shared by ${
          builtins.concatStringsSep " and " (
            map (asp: "aspect(${asp.name}#${builtins.substring 0 8 asp.id_hash})") culprits
          )
        }";

      mkOne =
        a:
        let
          inj = injectAspectSettings {
            inherit (a) aspect classContent settings;
            settingsKey = a._key;
            bindings = bindings // (a.bindings or { });
          };
          identity = "${entityOk.id_hash}/${a.aspect.id_hash}";
          idModule = bind.wrapIdentity {
            class = classOk.name;
            module = inj.module;
            inherit identity;
          };
        in
        {
          name = a._key;
          value = idModule;
        };
    in
    # class/entity identity are definition-time errors: force them at first force of the result,
    # independent of whether `aspects` is empty.
    builtins.seq classOk (
      builtins.seq entityOk (if dupKeys != [ ] then e8 else listToAttrs (map mkOne keyed))
    );
in
{
  inherit injectAspectSettings assembleHost;
}
