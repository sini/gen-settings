# T8 identity-keying (L14, L18). assembleHost keys every injected module by id_hash pairs (never
# names) on the entity/aspect axes: distinct entities (or cells) with the same aspect yield distinct
# evalModules keys (no dedup collapse); identical (class, entity, aspect) yields an equal key
# (evalModules merges once). Class-name-string / missing-id_hash inputs are definition-time errors.
# E8: duplicate settingsKey within one call is a definition-time error.
{
  lib,
  genSettings,
  ...
}:
let
  inherit (genSettings)
    mkSchema
    resolveOne
    assembleHost
    ;
  fx = import ./_fixtures/fixtures.nix { inherit lib; };
  throws = e: (builtins.tryEval (builtins.deepSeq e e)).success == false;

  fwSettings =
    (resolveOne {
      schema = mkSchema {
        aspect = fx.aspects.firewall;
        fields = {
          "allowed-tcp" = {
            default = [ 22 ];
          };
        };
      };
      layers = [ ];
    }).value;

  markContent =
    { settings, host, ... }:
    {
      config.markers = [ host.name ];
    };
  markOpts = {
    options.markers = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ ];
    };
  };

  assembleFor =
    entity:
    (assembleHost {
      inherit entity;
      class = fx.classes.nixos;
      aspects = [
        {
          aspect = fx.aspects.firewall;
          classContent = markContent;
          settings = fwSettings;
          bindings = {
            host = entity;
          };
        }
      ];
    }).firewall;

  modAxon = assembleFor fx.entities.axon;
  modBlade = assembleFor fx.entities.blade;
  modCell = assembleFor fx.entities.siniAtAxon;

  markersOf =
    modules:
    lib.sort lib.lessThan (lib.evalModules { modules = [ markOpts ] ++ modules; }).config.markers;

  # E8 — two aspects colliding on one settingsKey.
  e8Call = assembleHost {
    entity = fx.entities.axon;
    class = fx.classes.nixos;
    aspects = [
      {
        aspect = fx.aspects.firewall;
        classContent = { };
        settings = { };
        settingsKey = "shared";
      }
      {
        aspect = fx.aspects.nginx;
        classContent = { };
        settings = { };
        settingsKey = "shared";
      }
    ];
  };
in
{
  flake.tests.identity-keying = {
    # L14 — key format golden: class.name@entity.id_hash/aspect.id_hash.
    test-key-format-golden = {
      expr = modAxon.key;
      expected = "nixos@host0axon00000001/f1f2f3f4f5f6f7f8";
    };
    # L14 — distinct entities, same aspect → distinct keys.
    test-distinct-entities-distinct-keys = {
      expr = modAxon.key != modBlade.key;
      expected = true;
    };
    # L14 — a cell keys distinctly from its host entity (canonical cell identity).
    test-cell-distinct-key = {
      expr = modCell.key != modAxon.key;
      expected = true;
    };
    test-cell-key-format = {
      expr = modCell.key;
      expected = "nixos@cell0siniaxon0004/f1f2f3f4f5f6f7f8";
    };
    # L14 — distinct keys are NOT dedup-collapsed: both configs survive evalModules.
    test-distinct-both-present = {
      expr = markersOf [
        modAxon
        modBlade
      ];
      expected = [
        "axon-01"
        "blade"
      ];
    };
    # L14 — identical (class, entity, aspect) → equal key → evalModules merges once.
    test-same-key-merges-once = {
      expr = markersOf [
        modAxon
        modAxon
      ];
      expected = [ "axon-01" ];
    };

    # L14 — a class-name string (not a registry entry) is a definition-time error.
    test-class-string-error = {
      expr = throws (assembleHost {
        entity = fx.entities.axon;
        class = "nixos";
        aspects = [ ];
      });
      expected = true;
    };
    # L14 — an entity without id_hash is a definition-time error.
    test-entity-no-idhash-error = {
      expr = throws (assembleHost {
        entity = {
          name = "x";
        };
        class = fx.classes.nixos;
        aspects = [ ];
      });
      expected = true;
    };

    # L18 — duplicate settingsKey in one call is a definition-time error, at first spine force.
    test-e8-duplicate-settingskey = {
      expr = throws e8Call;
      expected = true;
    };
  };
}
