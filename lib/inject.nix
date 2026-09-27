# injectAspectSettings / assembleHost — resolved settings into parametric class content.
#
# gen-bind `wrap` (= wrapCore) does the work; gen-settings adds only the aspect-settings
# conventions. Always-wrap, no `isFunction` guard: registered classes are deferredModules, which
# coerce a lone function to `{ imports = [ fn ]; }`, so `isFunction` cannot distinguish parametric
# from static content — guarding on it is wrong by construction (Spike 5). Identity keying inherits
# gen-bind's Cardelli linkset identity (*Program Fragments, Linking, and Modularization*, POPL 1997
# §3 — linksets carry identity used to resolve duplicates).
#
# The (entity, aspect) attachment is a RELATION, so the identity gen-bind keys on is the labelled
# tuple of its relata, minted by gen-schema's single authority and never composed here. Hashing the
# STRUCTURE under a canonical encoding is what makes a cross-axis collision INEXPRESSIBLE rather
# than detected: a flat `<entity>/<aspect>` join is not injective, because the separator can occur
# inside a relatum, and a repair for that is an invariant someone must maintain.
{
  prelude,
  bind,
  schema,
  identity,
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

  # ★★★ ADR-0023 (b) SITE 1, THE LIVE CONSUMER — the `contracts ? { }` channel
  # below is the one path in the ecosystem that reaches gen-bind SITE 1
  # (`applyContracts`, gen-bind `lib/wrap.nix`) LIVE: it calls `bind.wrap`
  # directly, the retired call-level surface gen-bind's Adapters do not offer a
  # position for, and any caller of `injectAspectSettings` that supplies
  # `contracts` puts a substrate closure into whatever evaluation eventually
  # consumes `classContent` (ADR-0014: the boundary is the eval, not the repo).
  #
  # (i) THIS CHANNEL DOES NOT MEET ADR-0023 (c). `contracts` is forwarded
  # unconditionally to `bind.wrap`; a caller that supplies one crosses site 1.
  # (ii) THE PRICE, IN THE SITE'S OWN TERMS: a substrate closure — a contract's
  # check/transform pair, applied by gen-bind's `applyContracts` — executes
  # inside the target's evaluation, reading the bound value and its provenance
  # and throwing whatever the contract's own predicate throws.
  # (iii) THE ARGUED IMPOSSIBILITY is gen-bind's, at `wrap.nix`'s `applyContracts`
  # declaration (write-list entry 5): there is no Adapter route to close, so a
  # by-construction repair is not available to this unit; this note only records
  # that the retired direct-call surface — and this channel specifically — is the
  # live path into it. This is a declaration comment, not a new consumer of
  # gen-settings' EXPERIMENTAL surface (ADR-0017).
  #
  # injectAspectSettings { aspect; classContent; settings; settingsKey ?; bindings ?; contracts ?;
  #   provenance ? } -> { module; wrapped; signature; }
  # The injected settings binding is namespaced: settings = { ${settingsKey} = <resolved>; }, so
  # content reads `settings.<key>.<field>`. gen-bind's default `bindWins` shadows stray same-named
  # module args; lib/config/pkgs still flow from the module system (never injected).
  #
  # MIXED class (den-hoag-7gp66 P1): closed over the whole set — transitional, per §v1.2, until P2
  # moves the options off the record.
  injectAspectSettings =
    args:
    let
      checked =
        prelude.checkOptions "gen-settings.injectAspectSettings"
          [
            "aspect"
            "classContent"
            "settings"
            "settingsKey"
            "bindings"
            "contracts"
            "provenance"
          ]
          (
            prelude.checkRequired "gen-settings.injectAspectSettings" [
              "aspect"
              "classContent"
              "settings"
            ] args
          );
      aspect = checked.aspect;
      classContent = checked.classContent;
      settings = checked.settings;
      settingsKey = checked.settingsKey or aspect.name;
      bindings = checked.bindings or { };
      contracts = checked.contracts or { };
      provenance = checked.provenance or { };
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
    # `seq checked` (den-hoag-7gp66 P2): the door's return was a bare attrset literal, so its own
    # WHNF forced none of `module`/`wrapped`/`signature` — checkOptions/checkRequired sat unread
    # until a caller touched one of them, admitting a bad record at application. Same idiom
    # `mkSchema`'s `seq dotCheck` and `assembleHost`'s `builtins.seq classOk (…)` already use.
    builtins.seq checked {
      inherit (result) module wrapped signature;
    };

  # assembleHost { entity; class; aspects; bindings ? } -> { <settingsKey> = <identity-keyed module>; }
  #   entity — consuming entity (a registry entry) OR a minted binding node's identity (ADR-0016
  #            rulings 3–4), e.g. from gen-scope `mintStrata`; either way MUST carry id_hash.
  #   class  — class REGISTRY ENTRY; its `name` is the internal wrapIdentity key token.
  # Keys derive from id_hash pairs, never names, on the entity/aspect axes (identity law): distinct
  # entities (or binding nodes) with the same aspect yield distinct evalModules keys and are not
  # dedup-collapsed; the same (class, entity, aspect) reaching one eval twice carries an equal key
  # and merges once. Duplicate settingsKey within one call is E8 (a module would otherwise be
  # silently dropped by attrset collision — the failure identity keying exists to prevent).
  # MIXED class (den-hoag-7gp66 P1): closed over the whole set — transitional, per §v1.2, until P2
  # moves the options off the record.
  assembleHost =
    args:
    let
      checked =
        prelude.checkOptions "gen-settings.assembleHost"
          [
            "entity"
            "class"
            "aspects"
            "bindings"
          ]
          (
            prelude.checkRequired "gen-settings.assembleHost" [
              "entity"
              "class"
              "aspects"
            ] args
          );
      entity = checked.entity;
      class = checked.class;
      aspects = checked.aspects;
      bindings = checked.bindings or { };
      classOk =
        if !(isAttrs class && class ? name) then
          throw "gen-settings: assembleHost (L14): `class` must be a class registry entry (carrying a name), never a class-name string"
        else
          class;
      entityOk =
        if !(isAttrs entity && entity ? id_hash) then
          throw "gen-settings: assembleHost (L14): `entity` must carry id_hash (a registry entry, or a minted binding node's identity (ADR-0016 rulings 3–4), e.g. from gen-scope `mintStrata`)"
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
          # The relation kind is `attaches`; its relata are labelled `aspect` and `entity`. The label
          # list carries no ordering obligation — the preimage is an attrset, whose keys render
          # sorted — so it is spelled in whichever order reads best.
          stamp = identity.hashIdentity "attaches" [ "aspect" "entity" ] (
            k:
            {
              aspect = a.aspect.id_hash;
              entity = entityOk.id_hash;
            }
            .${k}
          );
          idModule = bind.wrapIdentity {
            class = classOk.name;
            module = inj.module;
            identity = stamp;
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
