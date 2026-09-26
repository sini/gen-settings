# T8 identity-keying (L14, L18). assembleHost keys every injected module by id_hash pairs (never
# names) on the entity/aspect axes: distinct entities (or binding nodes) with the same aspect yield distinct
# evalModules keys (no dedup collapse); identical (class, entity, aspect) yields an equal key
# (evalModules merges once). Class-name-string / missing-id_hash inputs are definition-time errors.
# E8: duplicate settingsKey within one call is a definition-time error.
#
# The stamp itself is the minted `attaches` binding identity — the labelled tuple of the two relata
# under gen-schema's single minting authority — so the key's identity region is a digest over
# structure, not a join of the two hashes.
#
# The binding cells hand the slot a node minted by gen-scope's `mintStrata` (ADR-0016 rulings 3–4):
# the filler is a function of its labelled relata, so the key moves when a relatum or a label moves
# and holds when the emitters are presented in another order.
{
  lib,
  genSettings,
  schema,
  identity,
  scope,
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

  markersOf =
    modules:
    lib.sort lib.lessThan (lib.evalModules { modules = [ markOpts ] ++ modules; }).config.markers;

  # The minting authority itself, called live from the same fixtures the library sees, so an
  # expectation cannot drift from the primitive it is about.
  mintStamp = labels: relata: identity.hashIdentity "attaches" labels (k: relata.${k});

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

  # A binding node minted through the one authority: two relatum-free nodes at pass 0, the binding
  # relating them at pass 1. Kind and labels are invented test data (ADR-0035). The identifier is
  # held fixed, so the controls below move a relatum or a label and nothing else.
  nodeAt0 = identifier: kind: {
    pass = 0;
    inherit identifier kind;
    relata = { };
    content = { };
    site = "t:${identifier}";
  };
  bindingId = "inscribes";
  inscribes = relata: {
    pass = 1;
    identifier = bindingId;
    kind = "inscribes";
    inherit relata;
    content = { };
    site = "t:${bindingId}";
  };
  withRelata =
    relata:
    [
      (nodeAt0 "ferrule" "quill")
      (nodeAt0 "sable" "quill")
      (nodeAt0 "vellum" "sheet")
    ]
    ++ [ (inscribes relata) ];
  emitters = withRelata {
    stylus = "ferrule";
    leaf = "vellum";
  };
  mintAll =
    es:
    scope.mintStrata {
      kinds = { };
      emitters = es;
    };
  minted = mintAll emitters;
  # The caller adapts the node record to the slot; assembleHost reads `id_hash` and nothing else.
  bindingFill = es: {
    name = bindingId;
    id_hash = (mintAll es).nodes.${bindingId}.identity;
  };
  fill = bindingFill;
  bindingKey = es: (assembleFor (fill es)).key;

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
    # ★ THE GOLDEN DIGESTS MOVED WITH THE PREIMAGE, and that is a priced consequence rather
    # than a regression. These pinned values were computed under the mint's SCALAR-ONLY
    # encoding; the encoder now emits an explicit type-tagged structure, so every digest it
    # produces differs. ADR-0016 ruling 5 is what makes that admissible — id_hash is internal
    # addressing and nothing durable may depend on it across evaluations — and the same
    # migration already ran on the mint's own suite. What these cells pin is the FORMAT
    # (`class.name@<kind>:<64 hex>`) and the STABILITY of the derivation, neither of which moved.
    test-key-format-golden = {
      expr = modAxon.key;
      expected = "nixos@attaches:a7b6185ed4c1efd965fece181c89d1fcc6ddb2473fbf8557b92519cea010afcf";
    };
    # L14 — distinct entities, same aspect → distinct keys.
    test-distinct-entities-distinct-keys = {
      expr = modAxon.key != modBlade.key;
      expected = true;
    };
    # L14 — a minted binding node keys distinctly from a plain entity.
    test-binding-distinct-key = {
      expr = bindingKey emitters != modAxon.key;
      expected = true;
    };
    # The slot takes the minted node: the key is the `attaches` stamp over the node's identity,
    # computed by calling both authorities rather than transcribed.
    test-binding-fills-slot = {
      expr =
        bindingKey emitters == "${fx.classes.nixos.name}@${
          mintStamp [ "aspect" "entity" ] {
            aspect = fx.aspects.firewall.id_hash;
            entity = minted.nodes.${bindingId}.identity;
          }
        }";
      expected = true;
    };
    # The filler is a minted node: mint-shaped, with out-edges under exactly its two labels.
    test-binding-is-minted-node = {
      expr =
        builtins.match "[a-z][a-z0-9-]*:[0-9a-f]{64}" (fill emitters).id_hash != null
        &&
          lib.sort lib.lessThan (map (e: e.label) (builtins.filter (e: e.from == bindingId) minted.edges))
          == [
            "leaf"
            "stylus"
          ];
      expected = true;
    };
    # One relation, one key, whatever order its emitters arrive in. The discrimination lives in
    # gen-scope's mint (the labelled relata render as an attrset); the two controls below show the
    # same key predicate reading false when a relatum or a label moves.
    test-binding-key-permutation-invariant = {
      expr = bindingKey emitters == bindingKey (lib.reverseList emitters);
      expected = true;
    };
    test-control-relatum-moves-key = {
      expr =
        bindingKey emitters != bindingKey (withRelata {
          stylus = "sable";
          leaf = "vellum";
        });
      expected = true;
    };
    test-control-label-swap-moves-key = {
      expr =
        bindingKey emitters != bindingKey (withRelata {
          stylus = "vellum";
          leaf = "ferrule";
        });
      expected = true;
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
