# gen-settings — stratified settings resolution as a pure layered fold

[![CI](https://github.com/sini/gen-settings/actions/workflows/ci.yml/badge.svg)](https://github.com/sini/gen-settings/actions/workflows/ci.yml) [![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](https://opensource.org/licenses/MIT) [![Sponsor](https://img.shields.io/badge/Sponsor-%E2%9D%A4-pink?logo=github)](https://github.com/sponsors/sini)

gen-settings resolves an aspect's settings — a static, introspectable schema of `{ default; merge }` leaves — against an ordered list of override layers, producing a resolved value plus a full per-field provenance chain. It adds refs-as-data (identity-bearing cross-aspect references with static cycle detection), structured provenance, and the graduated injection construct (`injectAspectSettings` / `assembleHost`).

**Class B (nixpkgs-lib-free).** The library is `builtins` + [gen-prelude](https://github.com/sini/gen-prelude), plus the [gen-algebra](https://github.com/sini/gen-algebra) fold (`foldLayersTraced` — the single fold implementation, never reimplemented here), [gen-bind](https://github.com/sini/gen-bind) injection and [gen-graph](https://github.com/sini/gen-graph) cycle detection (`cyclePaths` — the cycle-finding algorithm is never reimplemented here either; what stays is the E3 diagnostic). [gen-schema](https://github.com/sini/gen-schema) supplies the **ref datum** — the inert record and its structural scan live there, beside the option type whose inhabitants refs are — and the `id_hash` law every ref target must satisfy. A CI purity invariant (`ci/tests/purity.nix`) keeps that boundary honest.

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

`mkSchema { aspect; fields; }` normalizes an aspect's leaves into `{ aspect; fields; strategies; defaults; }` — plain data, always introspectable. Field names are **bare keys** (`allowed-tcp`, never `firewall.allowed-tcp`); `default` is mandatory on every leaf; `merge ∈ { replace, append, recursive }`. Shape violations are the definition-time error E1.

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
# → error: gen-schema: fieldRefsIn: function at scanned position font — this scan's domain is data …
```

Nix exposes no primitive that inspects a function body, so a ref inside a closure is unreachable to any structural scan — and skipping it fails *open*: the edge is never derived, a cycle it would have closed goes undetected, and the unresolved ref record leaks into the resolved value as data. Refusing eliminates the case rather than declaring it unanalysable, so every dependence fact `refGraph` reports is a derived one. A schema is plain data by its own contract, so on conforming input the refusal fires never.

### Structured Provenance

Every field's provenance is an ordered chain of structured entries `{ scope; rendered; via; value; refs; }` — `scope` carries the given registry entries (identity in ≡ out), `rendered` is display-only, `refs` records each hop. **Per-entry lazy ref substitution:** an entry's `value` substitutes only its own refs and only when itself forced; forcing the chain spine or a sibling entry never resolves a given entry's refs. So a shadowed layer whose contribution refs an absent aspect keeps a fully forceable chain — only forcing that shadowed entry throws.

### Injection

`injectAspectSettings` routes class content through gen-bind `wrap` unconditionally (always-wrap, no `isFunction` guard — registered classes are deferredModules that coerce a lone function to `{ imports = [ fn ]; }`). The injected settings binding is namespaced: content reads `settings.<settingsKey>.<field>`. `assembleHost` wraps every module with `wrapIdentity`, keying by **id_hash pairs** (`class.name@entity.id_hash/aspect.id_hash`) so distinct entities/cells are not dedup-collapsed and identical `(class, entity, aspect)` merges once. Duplicate `settingsKey` in one call is E8.

## API Reference

See [REFERENCE.md](./REFERENCE.md) for the full signature-level reference. Public surface: `mkSchema`, `ref` / `isRef` / `refsIn`, `refGraph` / `assertAcyclic` / `renderCycles`, `resolveOne` / `resolveAll`, `injectAspectSettings` / `assembleHost`, `renderAddress`.

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
