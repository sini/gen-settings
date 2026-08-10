# T8 identity-keying (L14, L18). assembleHost keys every injected module by id_hash pairs (never
# names) on the entity/aspect axes: distinct entities (or cells) with the same aspect yield distinct
# evalModules keys (no dedup collapse); identical (class, entity, aspect) yields an equal key
# (evalModules merges once). Class-name-string / missing-id_hash inputs are definition-time errors.
# E8: duplicate settingsKey within one call is a definition-time error.
#
# The stamp itself is the minted `attaches` binding identity — the labelled tuple of the two relata
# under gen-schema's single minting authority — so the key's identity region is a digest over
# structure, not a join of the two hashes.
{
  lib,
  genSettings,
  genSchema,
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

  # The minting authority itself, called live from the same fixtures the library sees, so an
  # expectation cannot drift from the primitive it is about.
  mintStamp = labels: relata: genSchema.hashIdentity "attaches" labels (k: relata.${k});

  axonFirewall = {
    aspect = fx.aspects.firewall.id_hash;
    entity = fx.entities.axon.id_hash;
  };
  # The same two values under each other's label.
  swappedRelata = {
    aspect = fx.entities.axon.id_hash;
    entity = fx.aspects.firewall.id_hash;
  };

  # The cross-axis separator collision: a `/`-bearing relatum on either axis gives two DISTINCT
  # (entity, aspect) pairs whose flat join is one string. The L14 guard is a presence check, so
  # neither pair is refused on the way in.
  collideLeft = {
    entity = "a/b";
    aspect = "c";
  };
  collideRight = {
    entity = "a";
    aspect = "b/c";
  };
  oldJoin = p: "${p.entity}/${p.aspect}";
  keyOfPair =
    p:
    (assembleHost {
      entity = {
        name = "e";
        id_hash = p.entity;
      };
      class = fx.classes.nixos;
      aspects = [
        {
          aspect = fx.mkAspect "collide" p.aspect;
          classContent = { };
          settings = { };
        }
      ];
    }).collide.key;

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
    # L14 — key format golden: class.name@<minted attaches identity>.
    test-key-format-golden = {
      expr = modAxon.key;
      expected = "nixos@attaches:92fcfa766fc5911824bdf9068aa6dcab633910d4d916f0e9dd9e94a4ba44cdbe";
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
      expected = "nixos@attaches:865c4be3fb4cec5394a781ff7dbacc2d3fb6cfd09d774c0db978cc2d30e45778";
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

    # The stamp IS the minted `attaches` binding identity, and the expectation is computed by
    # calling the authority rather than transcribed from it — so the cell cannot drift from the
    # primitive. A later change of kind tag or label set fails here instead of silently re-keying
    # every module.
    test-stamp-is-minted-attaches = {
      expr = modAxon.key;
      expected = "${fx.classes.nixos.name}@${mintStamp [ "aspect" "entity" ] axonFirewall}";
    };

    # Hashing the structure separates the two pairs a flat join collapsed.
    test-separator-collision-split = {
      expr = keyOfPair collideLeft != keyOfPair collideRight;
      expected = true;
    };
    # …and the retired join really did collapse them, so the claim above has a subject rather than
    # being a refusal about nothing.
    test-control-old-join-collided = {
      expr = oldJoin collideLeft == oldJoin collideRight;
      expected = true;
    };

    # The label list carries no caller obligation: the preimage is an attrset, whose keys render
    # sorted, so the spelling in assembleHost may be chosen for readability.
    test-label-order-free = {
      expr = mintStamp [ "aspect" "entity" ] axonFirewall == mintStamp [ "entity" "aspect" ] axonFirewall;
      expected = true;
    };
    # …while the VALUES under fixed labels are not free. A digest indifferent to its input would
    # pass the claim above and fail here.
    test-control-swapped-values-differ = {
      expr =
        mintStamp [ "aspect" "entity" ] axonFirewall != mintStamp [ "aspect" "entity" ] swappedRelata;
      expected = true;
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
