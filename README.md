# gen-settings — stratified settings resolution as a pure layered fold

[![CI](https://github.com/sini/gen-settings/actions/workflows/ci.yml/badge.svg)](https://github.com/sini/gen-settings/actions/workflows/ci.yml) [![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](https://opensource.org/licenses/MIT) [![Sponsor](https://img.shields.io/badge/Sponsor-%E2%9D%A4-pink?logo=github)](https://github.com/sponsors/sini)

gen-settings resolves an aspect's settings — a static, introspectable schema of `{ default; merge }` leaves — against an ordered list of override layers, producing a resolved value plus a full per-field provenance chain. It adds refs-as-data (identity-bearing cross-aspect references with static cycle detection), structured provenance, and the graduated injection construct (`injectAspectSettings` / `assembleHost`).

**Class B (nixpkgs-lib-free).** The library is `builtins` + [gen-prelude](https://github.com/sini/gen-prelude), plus the [gen-algebra](https://github.com/sini/gen-algebra) fold (`foldLayersTraced` — the single fold implementation, never reimplemented here), [gen-bind](https://github.com/sini/gen-bind) injection and the [gen-graph](https://github.com/sini/gen-graph) ref graph (`fromScan` derives the edges and builds the node set from the scan and the field-address projection this library hands it; `cyclePaths` finds the cycles — neither is reimplemented here, and what stays is the batch shape, the node key and the E3 diagnostic). [gen-schema](https://github.com/sini/gen-schema) supplies the **ref datum** — the inert record and its structural scan live there, beside the option type whose inhabitants refs are — and the `id_hash` law every ref target must satisfy. [gen-types](https://github.com/sini/gen-types) supplies the **schema-shape predicates**: what a well-formed field is, is a structural checker there, never a hand-rolled test here; the E1 diagnostic is what stays. A CI purity invariant (`ci/tests/purity.nix`) keeps that boundary honest.

## Table of Contents

- [Overview](#overview)
- [Gen Ecosystem](#gen-ecosystem)
- [Quick Start](#quick-start)
- [Core Concepts](#core-concepts)
  - [Schemas](#schemas)
  - [Layers and the Fold](#layers-and-the-fold)
  - [Refs as Data](#refs-as-data)
  - [Structured Provenance](#structured-provenance)
  - [Injection](#injection)
- [API Reference](#api-reference)
- [Design Constraints](#design-constraints)
- [Testing](#testing)
- [Theoretical Foundations](#theoretical-foundations)

## Overview

An aspect declares its settings as a **static schema** — bare-key leaves `{ default; merge ? "replace" | "append" | "recursive"; }`, always introspectable, never buried behind functions. Only class *content* is parametric, and it *consumes* resolved settings.

Resolution is a **pure layered fold** over an ordered layer list (least → most specific): positional last-wins for `replace`, accumulation for `append`/`recursive`. Authority is **by position** — there is deliberately no per-declaration strength dimension (`mkForce`/`!important`). The resolved value is byte-identical to gen-algebra's `foldLayers` over the same strategies, defaults, and layer values; this equality is the Spike 5 acceptance gate, tested against the real fold.

The lib is **lattice-blind by design**: the layer chain arrives as an ordered list computed upstream (by den-hoag as a gen-product containment chain × gen-scope D/I chain). gen-settings takes that list as given and never reorders, dedups, or filters it.

## Gen Ecosystem

```
gen-prelude ─┐
gen-algebra ─┤
gen-bind    ─┼─→ gen-settings ─→ den-hoag (four-concern assembly)
gen-graph   ─┤
gen-schema  ─┘  (the ref datum + id_hash)
```

gen-settings is an L2 contract library on the gen substrate. den-hoag composes it: per cell, a containment chain × D/I chain becomes the ordered layer list, gen-settings folds it, and the parametric aspect content consumes the resolved settings through the injection construct.

## Quick Start

```nix
let
  genSettings = (import ./lib) {
    prelude = gen-prelude.lib;
    algebra = gen-algebra.lib;
    bind = gen-bind.lib;
    genGraph = gen-graph.lib;
  };
  inherit (genSettings) mkSchema resolveOne;

  schema = mkSchema {
    aspect = config.aspects.firewall;      # a registry entry (carries id_hash)
    fields = {
      "allowed-tcp" = { default = [ 22 ]; merge = "append"; };
      hostname = { default = "unset"; };   # replace (implicit)
    };
  };

  resolved = resolveOne {
    inherit schema;
    layers = [
      { scope = { env = config.envs.prod; };  rendered = "prod"; via = null; value = { "allowed-tcp" = [ 80 ]; }; }
      { scope = { host = den.hosts.axon-01; }; rendered = "axon-01"; via = null; value = { "allowed-tcp" = [ 443 ]; hostname = "axon-01"; }; }
    ];
  };
in
resolved.value    # => { "allowed-tcp" = [ 22 80 443 ]; hostname = "axon-01"; }
```

## Core Concepts

### Schemas

`mkSchema { aspect; fields; }` normalizes an aspect's leaves into `{ aspect; fields; strategies; defaults; }` — plain data, always introspectable. Field names are **bare keys** (`allowed-tcp`, never `firewall.allowed-tcp`); `default` is mandatory on every leaf; `merge ∈ { replace, append, recursive }`. Those three obligations are stated as gen-types checkers and the value of `default` is typed `any`, so verifying a field never forces what it holds. Shape violations are the definition-time error E1, which is gen-settings' own diagnostic over gen-types' predicate.

### Layers and the Fold

A layer is `{ scope; rendered; via; value; }`. `scope` is an attrset of registry entries (`{ host = den.hosts.axon-01; }`), `rendered` is a display string, `via` is the projecting aspect (for `projects`-facet layers) or `null`, and `value` is a bare-key partial contribution. The ordered list is least → most specific; a `user@host` cell override is nothing special — it enters as most-specific and wins by position.

The fold is gen-algebra's `foldLayersTraced`. Labels are fully opaque to it: replacing every label with any other value changes no resolved value (label opacity, pinned in both this lib's and gen-algebra's CI).

### Refs as Data

A schema default or any layer contribution may reference another aspect's resolved setting:

```nix
settings.font = { default = ref config.aspects.theme [ "font" "mono" ]; };
```

`ref` takes the aspect **registry entry** (never a string — a value without `id_hash` throws E6 at application time) and a field path list. The record and its scan are gen-schema's `fieldRef` family; what this library adds is the E6 diagnostic, the field-address graph over them, and resolution. Refs are **inert data** — no functions, no thunks — so schemas stay introspectable and the cross-aspect dependency graph is computable statically (`refGraph`). Cycles are a definition-time error (E3) naming every address in the cycle. Refs resolve during the fold (fold-then-substitute; refs are merge-atomic, so this equals folding pre-substituted inputs).

The static graph is **conservative over pre-fold values** and **structurally strict**: it forces every scanned contribution to WHNF and counts edges from refs a later `replace` layer would shadow. This is the honest cost of the static/applicative discipline (see [Theoretical Foundations](#theoretical-foundations)).

**The scan refuses functions.** A function found in a scanned position throws, naming the position, rather than being passed over as a leaf:

```nix
settings.font = { default = _: ref config.aspects.theme [ "font" ]; };
# → error: gen-schema: fieldRefsIn: function at scanned position font — this scan's domain is data.
#   A function is refused rather than skipped … If this position is a computed value, express it
#   where its reads stay visible — `fieldRef <instance> <path>` for a cross-instance read, or the
#   kind's `computed` hook for a value derived from collections and defs; otherwise, make the
#   position data, or keep the function outside the scanned structure.
```

Nix exposes no primitive that inspects a function body, so a ref inside a closure is unreachable to any structural scan — and skipping it fails *open*: the edge is never derived, a cycle it would have closed goes undetected, and the unresolved ref record leaks into the resolved value as data. Refusing eliminates the case rather than declaring it unanalysable, so every dependence fact `refGraph` reports is a derived one. A schema is plain data by its own contract, so on conforming input the refusal fires never.

The refusal is deliberately wider than the hazard — a ref-free function refuses too, at any depth — and if it is ever genuinely in the way, the sanctioned escape is a **declared** schema-level annotation, not a quieter scan. gen-schema's README carries that path under *If the refusal is in your way*; it is where the contract is owned.

**And so does the substitution.** The scan derives the graph, `substDeep` produces the value, and its dispatch is total over that same domain — so `resolveOne` refuses a function-valued field during resolution too, on **both** halves of its result, naming the field: `gen-settings: cannot substitute into a value of type 'lambda': aspect(theme#a1b2c3d4).font — …`. Admitting an input the scan refuses would produce a value from an input no dependency edge was ever derived over, which is the same static/applicative requirement read from the other end.

### Structured Provenance

Every field's provenance is an ordered chain of structured entries `{ scope; rendered; via; value; refs; }` — `scope` carries the given registry entries (identity in ≡ out), `rendered` is display-only, `refs` records each hop. **Per-entry lazy ref substitution:** an entry's `value` substitutes only its own refs and only when itself forced; forcing the chain spine or a sibling entry never resolves a given entry's refs. So a shadowed layer whose contribution refs an absent aspect keeps a fully forceable chain — only forcing that shadowed entry throws. The substitution is handed to the fold as gen-algebra's `entryTransform` and emitted by it, not mapped over its output afterwards; the laziness is that hook's non-interference law, and what this library supplies is the ref-specific refinement it applies.

### Injection

`injectAspectSettings` routes class content through gen-bind `wrap` unconditionally (always-wrap, no `isFunction` guard — registered classes are deferredModules that coerce a lone function to `{ imports = [ fn ]; }`). The injected settings binding is namespaced: content reads `settings.<settingsKey>.<field>`. `assembleHost` wraps every module with `wrapIdentity`, keying by the **minted `attaches` binding identity** over the entity and aspect `id_hash`es — `class.name@attaches:<sha256>`, where gen-schema's `hashIdentity` is the sole minting authority and the class scopes the key from outside the identity rather than entering it — so distinct entities/cells are not dedup-collapsed and identical `(class, entity, aspect)` merges once. Hashing the structure rather than joining the two hashes is what makes a cross-axis separator collision inexpressible. Duplicate `settingsKey` in one call is E8.

## API Reference

See `gen-specs/gen-settings/REFERENCE.md` in the den-architecture papers repository for the full
signature-level reference — reference specs live there, not in the library repo. Public surface: `mkSchema`, `ref` / `isRef` / `refsIn`, `refGraph` / `assertAcyclic` / `renderCycles`, `resolveOne` / `resolveAll`, `injectAspectSettings` / `assembleHost`, `renderAddress`.

## Design Constraints

- **No slice-lattice awareness inside the lib.** Layer derivation is upstream; gen-settings is a pure fold.
- **No per-declaration strength.** Authority is positional; a strength dimension must ship as a `foldLayers` extension in gen-algebra, not here.
- **Identity law.** Public APIs take/return registry entries carrying `id_hash`; `"kind:name"` strings are internal keys + display only.
- **nixpkgs-lib-free.** `builtins` + gen-prelude, plus the declared gen deps.

## Testing

Law-based suites, one named group per spec law (`ci/tests/`), run with [nix-unit](https://github.com/nix-community/nix-unit):

```bash
cd ci && nix-unit --flake .#tests
```

Highlights: T1 computes value byte-identity against the **real** `foldLayers` (the Spike 5 gate); T5 pins static-graph strictness, conservativeness, and cycle detection (2-cycle, self-loop, 3-cycle, permissive field-granular non-cycle); T3 pins per-entry provenance laziness for shadowed refs; T7 runs the firewall full loop through `evalModules`; T8 pins id_hash-pair identity keying.

## Theoretical Foundations

- **Static dependencies of refs** — Mokhov, Mitchell & Peyton Jones, *Build Systems à la Carte* (ICFP 2018), §3: refs are *applicative* task dependencies — the graph is computable before any value is produced. The conservative, structurally-strict `refGraph` is exactly this discipline (over-approximated statically, not discovered during resolution).
- **Positional authority** — the config/policy precedence research grounds authority-by-position and the deliberate absence of a strength lattice (contrast: CSS Cascading & Inheritance L5 §6, nixpkgs `mkOverride`). This lib realizes the positional fold, not the priority lattice.
- **Module identity keying** — Cardelli, *Program Fragments, Linking, and Modularization* (POPL 1997), §3: linksets carry identity used to resolve duplicates. Realized via gen-bind `wrapIdentity` (inherited).
- **Lazy contracts at the injection boundary** — Chitil, *Practical Typed Lazy Contracts* (ICFP 2012), via gen-bind (inherited; forwarded, zero cost until forced).
- **Layer-order provenance (context)** — the upstream D < I < P chain follows Néron, Tolmach, Visser & Wachsmuth, *A Theory of Name Resolution* (ESOP 2015), realized by gen-scope, not by this lib.
