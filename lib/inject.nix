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
  # injectAspectSettings { settingsKey ?; bindings ?; contracts ?; provenance ?; } { aspect; settings; }
  #   classContent -> { module; wrapped; signature; }
  # The injected settings binding is namespaced: settings = { ${settingsKey} = <resolved>; }, so
  # content reads `settings.<key>.<field>`. gen-bind's default `bindWins` shadows stray same-named
  # module args; lib/config/pkgs still flow from the module system (never injected).
  #
  # THREE STEPS (den-hoag-7gp66 P2, rules 2, 4 and the keyed-record ruling v1.3):
  #   · the OPTIONS, one closed set first, a `prelude.door` refused by name and catchably at
  #     `injectAspectSettings opts`'s own WHNF;
  #   · `aspect` and `settings`, two configuration operands with no natural order between them (the
  #     declaring entry and its resolved values, two attrsets a positional order would let a caller
  #     swap silently), as ONE keyed record: open (R5), a missing field refused by name at the
  #     record's application, and an option given on it instead of the options refused by name
  #     (`optionsStep`, G10);
  #   · the class content, the subject the injection wraps, positional and last.
  injectAspectSettings = injectOptions (
    o: injectRecord ({ aspect, settings, ... }: classContent: injectCore o aspect settings classContent)
  );
  injectOptions = prelude.door {
    name = "gen-settings.injectAspectSettings";
    optional = [
      "settingsKey"
      "bindings"
      "contracts"
      "provenance"
    ];
    next = injectRecordSpec;
  };
  injectRecordSpec = {
    name = "gen-settings.injectAspectSettings";
    required = [
      "aspect"
      "settings"
    ];
    open = true;
    optionsStep = injectAspectSettings;
  };
  injectRecord = prelude.door injectRecordSpec;
  # The unchecked core, which `assembleHost` calls once per aspect (spec §p2.3.2: internal callers
  # of a door call its core, and no check sits in a per-element closure).
  injectCore =
    o: aspect: settings: classContent:
    let
      settingsKey = o.settingsKey or aspect.name;
      bindings = o.bindings or { };
      contracts = o.contracts or { };
      provenance = o.provenance or { };
      allBindings = bindings // {
        settings = {
          ${settingsKey} = settings;
        };
      };
      result = bind.wrap {
        bindings = allBindings;
        inherit contracts provenance;
      } classContent;
    in
    {
      inherit (result) module wrapped signature;
    };

  # assembleHost { bindings ?; } { class; aspects; } entity -> { <settingsKey> = <identity-keyed module>; }
  #   entity — consuming entity (a registry entry) OR a minted binding node's identity (ADR-0016
  #            rulings 3–4), e.g. from gen-scope `mintStrata`; either way MUST carry id_hash.
  #   class  — class REGISTRY ENTRY; its `name` is the internal wrapIdentity key token.
  # Keys derive from id_hash pairs, never names, on the entity/aspect axes (identity law): distinct
  # entities (or binding nodes) with the same aspect yield distinct evalModules keys and are not
  # dedup-collapsed; the same (class, entity, aspect) reaching one eval twice carries an equal key
  # and merges once. Duplicate settingsKey within one call is E8 (a module would otherwise be
  # silently dropped by attrset collision — the failure identity keying exists to prevent).
  #
  # THREE STEPS (den-hoag-7gp66 P2; K1, 2026-09-27, names `entity` the subject): the one option,
  # `bindings`, leaves for a closed options set (a `prelude.door`); `class` and `aspects`, two
  # configuration operands with no natural order, are ONE keyed open record (the v1.3 ruling), its
  # missing field refused by name at its application and `bindings` given on it refused by name
  # (`optionsStep`); the entity is positional and last, so `assembleHost { } { class; aspects; }` is an
  # assembler mapped over entities.
  assembleHost = assembleOptions (
    o:
    assembleRecord (
      { class, aspects, ... }: entity: assembleCore (o.bindings or { }) class aspects entity
    )
  );
  assembleOptions = prelude.door {
    name = "gen-settings.assembleHost";
    optional = [ "bindings" ];
    next = assembleRecordSpec;
  };
  assembleRecordSpec = {
    name = "gen-settings.assembleHost";
    required = [
      "class"
      "aspects"
    ];
    open = true;
    optionsStep = assembleHost;
  };
  assembleRecord = prelude.door assembleRecordSpec;
  assembleCore =
    bindings: class: aspects: entity:
    let
      classOk =
        if !(isAttrs class && class ? name) then
          throw "gen-settings: assembleHost (L14): `class` must be a class registry entry (carrying a name), never a class-name string"
        else
          class;
      entityOk =
        if !(isAttrs entity && entity ? id_hash) then
          throw "gen-settings: assembleHost (L14): `entity` must carry id_hash (a registry entry, or a binding node's identity, which the one identity function mints, e.g. from gen-scope `mintStrata`)"
        else
          entity;

      # Each element is a data record (R5: open, its missing field refused by name), checked once
      # here, where the P1 door it was handed to used to check it.
      keyed = map (
        a:
        let
          e = prelude.checkRequired "gen-settings.assembleHost" [
            "aspect"
            "classContent"
            "settings"
          ] a;
        in
        e // { _key = e.settingsKey or e.aspect.name; }
      ) aspects;
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
          inj = injectCore {
            settingsKey = a._key;
            bindings = bindings // (a.bindings or { });
          } a.aspect a.settings a.classContent;
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
          idModule = bind.wrapIdentity { } classOk.name stamp inj.module;
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
