# gen-settings — agent capability sheet

> **Status (owner ruling, 2026-08-05): EXPERIMENTAL, subject to replacement.** Built by the original
> den-hoag agent; likely to go through redesign. Do not build new long-lived dependencies on this
> surface without checking the den-hoag tracker first.

## Scope

Stratified settings resolution: folds a static `{ default; merge }` schema against a caller-supplied ordered layer list into `{ value; provenance; }`, adding refs-as-data (inert cross-aspect references with a static dependency graph) and the injection construct that hands the resolved value to parametric class content.

## Not this library's job

Quoted text is the owner's own `flake.nix` `description` field, verbatim.

| Responsibility | Owner |
|---|---|
| The layered fold itself — merge strategies, accumulation, value byte-identity | `gen-algebra` — "gen-algebra: pure Nix algebra — search monad, records, intensional functions, either". `lib/resolve.nix:foldLayersTraced` binds `algebra.record.foldLayersTraced`; the fold is never reimplemented here |
| Module argument binding, `wrap` / `wrapIdentity`, lazy contracts | `gen-bind` — "gen-bind: module binding with external arguments for Nix". Used at `lib/inject.nix:injectAspectSettings` (`bind.wrap`) and `lib/inject.nix:assembleHost` (`bind.wrapIdentity`) |
| Minting `id_hash`, kinds, registries | `gen-schema` — "gen-schema: typed record registry with extension points for the pure-gen module system". Consumed **interface-only**: not a flake input (`flake.nix:inputs`), and the name occurs in `lib/` only inside a comment (`lib/default.nix`, file header). gen-settings only *reads* `id_hash` |
| Deriving the containment chain the layer list is built from | `gen-product` — "gen-product — graph products as first-class operations over accessor-graphs (Cartesian / tensor / strong / lexicographic; cells, slices, fibers, projections, quotients, restriction, containment chains), lazy in and out". `README.md` § *Overview* (the "lattice-blind by design" paragraph) names it as the upstream producer |
| Deriving the D/I scope chain / name-resolution order | `gen-scope` — "gen-scope: demand-driven attribute grammar evaluator over algebraic scope graphs". `README.md` § *Overview* and § *Theoretical Foundations* ("Layer-order provenance (context)") name it as the upstream producer |
| Graph traversal and query combinators, **including ref-cycle detection** | `gen-graph` — "gen-graph: accessor-based graph query combinators". `lib/graph.nix` builds the field-address accessor and calls `genGraph.cyclePaths`; the cycle-finding algorithm is not reimplemented here. What stays is the E3 diagnostic — the address vocabulary and its rendering (`lib/graph.nix`, `assertAcyclic`) |
| Choosing *which* graph positions a setting applies to | `gen-select` — "gen-select: selector algebra for attributed graph positions" |
| Aspect traits and classification — gen-settings treats an aspect entry as opaque data needing only `name` + `id_hash` | `gen-aspects` — "gen-aspects: aspect-oriented composition types (pure-gen, re-hosted on gen-merge)" |
| Module merge / `evalModules` — the token is CI-forbidden inside `lib/` (`ci/tests/purity.nix:forbidden`) | `gen-merge` — "gen-merge — pure-Nix byte-mode module MERGE engine (evalModuleTree) for the pure-gen module system" |
| Class content itself (partition / contract / apply / gate) | `gen-class` — "gen-class — pure-Nix class-share mechanism (partition / contract / apply / gate) for the pure-gen module system" |
| Structural type checking — `mkSchema` hand-rolls name and shape checks (`lib/schema.nix:hasDot`, `lib/schema.nix:mkSchema` — `normField`) | `gen-types` — "gen-types: pure, nixpkgs-lib-free structural type checker for the gen ecosystem" |
| General utilities | `gen-prelude` — "gen-prelude: vendored, nixpkgs-lib-free pure utilities for the gen ecosystem". Used at `lib/ref.nix:imap0` and `lib/resolve.nix:foldMember` (`prelude.concatMap`) |

## Exports

Two entries, both yielding the same twelve names.

- **Flake**: `inputs.gen-settings.lib` — `flake.nix` applies `import ./lib` to `gen-prelude.lib`, `gen-algebra.lib`, `gen-bind.lib` and `gen-graph.lib` (as `genGraph`).
- **Root `default.nix`** (non-flake): a function whose arguments are all defaulted. It reads its own lockfile — `builtins.fromJSON (builtins.readFile ./flake.lock)` (`default.nix:lock`) — resolves `lock.nodes.${lock.nodes.root.inputs.<name>}.locked` and `builtins.fetchTree`s that node (`default.nix:fetch`), then imports `<fetched>/lib` (`default.nix`, the `prelude` / `algebra` / `bind` / `genGraph` argument defaults). `prelude` and `algebra` are imported bare; `bind` and `genGraph` are re-applied to `prelude` because gen-bind's and gen-graph's `lib/` are themselves functions.
- `import ./lib` alone is **a function** of `{ prelude, algebra, bind, genGraph }` — not a bare value. `genGraph` is the gen-graph library; the local name `graph` inside `lib/default.nix` is this library's own ref-graph module, which is why the injected one is not called `graph`.

**Schema** — `lib/schema.nix`

| Export | Signature |
|---|---|
| `mkSchema` | `{ aspect, fields } -> { aspect; fields; strategies; defaults; }` |

`fields` leaves are `{ default; merge ? "replace"; }`; `merge ∈ { replace, append, recursive }` (`lib/schema.nix:validMerges`); field names are bare keys.

**Refs** — `lib/ref.nix`

| Export | Signature |
|---|---|
| `ref` | `aspectEntry -> [string] -> { __genSettingsRef = true; aspect; path; }` |
| `isRef` | `any -> bool` |
| `refsIn` | `any -> [ { at; aspect; path; } ]` (deep structural scan; `at` is the subpath within the scanned value) |

**Static dependency graph** — `lib/graph.nix`

| Export | Signature |
|---|---|
| `refGraph` | `batch -> { nodes; edges; cycles; }` |
| `assertAcyclic` | `graph -> graph` (identity when `cycles == [ ]`, else E3) |
| `renderCycles` | `[ [ <address> ] ] -> string` (the E3 body; the binding `assertAcyclic` throws) |

**Resolution** — `lib/resolve.nix`

| Export | Signature |
|---|---|
| `resolveOne` | `{ schema, layers, resolveRef ? <throws E4>, strict ? true } -> { value; provenance; }` |
| `resolveAll` | `{ batch } -> { value; provenance; graph; }` |

**Injection** — `lib/inject.nix`

| Export | Signature |
|---|---|
| `injectAspectSettings` | `{ aspect, classContent, settings, settingsKey ? aspect.name, bindings ? { }, contracts ? { }, provenance ? { } } -> { module; wrapped; signature; }` |
| `assembleHost` | `{ entity, class, aspects, bindings ? { } } -> { <settingsKey> = <identity-keyed module>; }` |

**Display** — `lib/display.nix`

| Export | Signature |
|---|---|
| `renderAddress` | `{ aspect, field ? null, path ? null } -> string` |

**Consumed shapes** (not exported)

| Shape | Fields |
|---|---|
| Layer | `{ scope; rendered; via; value; }` — `value` is a bare-key partial contribution; the list is least → most specific |
| Batch member | `{ schema; layers; key ? schema.aspect.name; strict ? true; }` |
| Aspect / entity / class entry | any attrset carrying `name` + `id_hash` (the gen-schema interface) |
| `assembleHost` aspect record | `{ aspect; classContent; settings; settingsKey ? aspect.name; bindings ? { }; }` |
| Provenance entry | `{ scope; rendered; via; refs; value; }` |
| Edge | `{ from = { aspect; field; }; to = { aspect; field; }; at; path; }` |

**Error codes** and their throwing sites

| Code | Meaning | Site |
|---|---|---|
| E1 | schema shape: dotted field name, missing `default`, unknown `merge` | `lib/schema.nix:mkSchema` (`dotCheck`, then `normField`'s two throws) |
| E2 | strict mode: a layer contributes an undeclared field | `lib/resolve.nix:foldMember` (`guard`) |
| E3 | ref cycle | `lib/graph.nix:assertAcyclic` |
| E4 | unresolved ref (no resolver, or target absent from the batch) | `lib/resolve.nix:resolveOne` (the default `resolveRef`), `lib/resolve.nix:resolveAll` (`resolveRefFrom`) |
| E5 | bad ref path: a component is not present in the resolved value | `lib/resolve.nix:resolveAll` (`walkPath`) |
| E6 | ref target is not an `id_hash`-bearing entry, or the path is malformed | `lib/ref.nix:ref` |
| E7 | duplicate batch key | `lib/resolve.nix:resolveAll` (`gate`) |
| E8 | duplicate `settingsKey` within one `assembleHost` call | `lib/inject.nix:assembleHost` (`e8`) |
| L14 | `assembleHost` `class`/`entity` identity violation | `lib/inject.nix:assembleHost` (`classOk`, `entityOk`) |

## Entry points by task

| Task | Reach for |
|---|---|
| Declare an aspect's settings surface | `mkSchema { aspect; fields; }` |
| Resolve one aspect against a layer chain | `resolveOne { schema; layers; }` — supply `resolveRef` if any ref is reachable |
| Resolve a batch with cross-aspect refs | `resolveAll { batch; }` — ref routing is internal, keyed by `id_hash` |
| Point one setting at another aspect's setting | `ref <aspect-registry-entry> [ "field" … ]` inside a `default` or a layer `value` |
| Ask what a value depends on without resolving | `refsIn v` (per-position hits) / `refGraph batch` (field-address edges) |
| Fail fast on a ref cycle | `assertAcyclic (refGraph batch)`, or force `(resolveAll { batch; }).value` |
| Ask where a resolved field came from | `.provenance.<key>.<field>` — ordered chain, default entry first |
| Hand resolved settings to parametric class content | `injectAspectSettings { aspect; classContent; settings; }` → `.module` |
| Build an entity's whole per-aspect module set | `assembleHost { entity; class; aspects; }` |
| Render an address for an error message | `renderAddress { aspect; field ? ; path ? ; }` — display only, never parsed back |
| Accept undeclared contributions | `strict = false` — the field then passes through into the value |

## Measured traps

Verified at `24a78e9` by evaluating against the flake's `lib` (`nix eval --impure .#lib --apply …`). Shared fixtures: `A = { name = "theme"; id_hash = "a1b2c3d4deadbeef"; }`, `B = { name = "terminal"; id_hash = "e5f6a7b8cafef00d"; }`, `C` an aspect absent from every batch; `L = value: { scope = null; rendered = "L"; via = null; inherit value; }`; `ok = e: (builtins.tryEval (builtins.deepSeq e e)).success`.

| Trap | Evidence |
|---|---|
| `substDeep`, `refMarker` and `shortHash` are exported by their own modules but dropped by the public surface | `lib/resolve.nix:substDeep`, `lib/ref.nix:refMarker`, `lib/display.nix:shortHash` vs `lib/default.nix`'s export attrset; `lib ? substDeep` / `? refMarker` / `? shortHash` all ⇒ `false`, control `lib ? isRef` ⇒ `true` |
| A dotted field name is an **eager** E1 — it fires on *any* use of the schema, including `attrNames` of its own `fields` | `lib/schema.nix:mkSchema` (`dotCheck`, forced by the body's `seq dotCheck`); `.aspect` ⇒ threw, `attrNames .fields` ⇒ threw; control, bare key, `.aspect` ⇒ succeeded |
| A missing `default` or unknown `merge` is **per-field lazy** — the schema, its attribute names, and every sibling field stay usable | `lib/schema.nix:mkSchema` (`normField`); with `fields = { good = { default = 1; }; bad = { }; }`: `.aspect` ⇒ ok, `attrNames .defaults` ⇒ ok, `.defaults.good` ⇒ ok, `.defaults.bad` ⇒ threw. Same shape for `merge`: `attrNames .strategies` ⇒ ok, `.strategies.f` ⇒ threw. Tests: `test-e1-dotted-key`, `test-e1-missing-default`, `test-e1-bad-merge` (`ci/tests/resolution-errors.nix`) |
| `merge` accepts exactly three strategies; `"semilattice-set"` is E1 here **even though the underlying fold implements it** | `lib/schema.nix:validMerges`; `.strategies.f` with `merge = "semilattice-set"` ⇒ threw. The fold's fourth branch is read from gen-algebra `lib/rec.nix:foldLayersTraced` (the `semilattice-set` arm of its `resolve`), not exercised in this run |
| `ref` validates at **application** time, not at resolution time | `lib/ref.nix:ref`; `ref "theme" [ "font" ]`, `ref { name = "theme"; } [ "font" ]`, `ref A [ ]` and `ref A [ 1 ]` all threw; control `ref A [ "font" ]` ⇒ record |
| `isRef` is marker-only — a hand-written `{ __genSettingsRef = true; }` is accepted and *counted*, and dies later on a raw missing-attribute error (not an E-code, and **not** `tryEval`-catchable) | `lib/ref.nix:isRef`, `lib/ref.nix:refsIn` (`go`'s ref branch); `isRef` ⇒ `true`, `length (refsIn { x = <marker>; })` ⇒ `1`, forcing that hit's `.path` ⇒ `error: attribute 'path' missing at …/lib/ref.nix:58:36`; control, a real `ref`, `.path` ⇒ `["font"]` |
| `refsIn` is **structurally strict**: a throwing position anywhere in the scanned value throws during the scan | `lib/ref.nix:refsIn` (its structural-strictness note); `refsIn { x = throw "boom"; }` ⇒ threw, control `refsIn { x = 1; }` ⇒ `[ ]` |
| A ref inside a function body is invisible — functions are scan leaves | `lib/ref.nix:refsIn` (its leaves note, and `go`'s final `[ ]` branch); `refsIn { f = _: ref A [ "font" ]; }` ⇒ `0` hits, control `refsIn { f = ref A [ "font" ]; }` ⇒ `1` |
| `resolveOne`'s default `resolveRef` **throws E4** — a schema whose own `default` is a ref is unusable without one | `lib/resolve.nix:resolveOne` (the default `resolveRef`); `.value` ⇒ threw; with `resolveRef = _: "RESOLVED"` ⇒ `{ font = "RESOLVED"; }` |
| With `strict = false` an undeclared contribution is not dropped — it **passes through into the resolved value** under an implicit `replace` | `lib/resolve.nix:foldMember` (`guard`) guards but never filters; the key union is gen-algebra's (`lib/rec.nix:foldLayersTraced` — `allKeySet`). Layer `{ font = "x"; nope = 1; }` against a `font`-only schema: default strict ⇒ threw (E2), `strict = false` ⇒ `{ font = "x"; nope = 1; }`, control declared-only ⇒ `{ font = "x"; }` |
| `resolveAll`'s `.graph` is **not** gated by `assertAcyclic` — it hands back a cyclic graph without complaint while `.value` throws | `lib/resolve.nix:resolveAll` (`gate` vs the ungated `graph = theGraph`); on a 2-cycle batch `deepSeq r.graph` ⇒ ok, `length r.graph.cycles` ⇒ `1`, `r.value` ⇒ threw, `assertAcyclic r.graph` ⇒ threw |
| Two batch members sharing one `aspect.id_hash` under **distinct keys** pass E7 and then silently collapse — both keys resolve to the *first* member's fold | `lib/resolve.nix:resolveAll` (`dupKeys` — the E7 check — vs `raws`, a `listToAttrs` keyed by `id_hash`). Members declaring `default = "FIRST"` and `default = "SECOND"`: keys ⇒ `["theme","theme2"]`, value ⇒ `{"theme":{"font":"FIRST"},"theme2":{"font":"FIRST"}}` |
| `refGraph` is conservative over **pre-fold** values: a ref that a later `replace` layer shadows still contributes an edge, so a fully-shadowed 2-cycle is still E3 | `lib/graph.nix:refGraph` (`contribSources` — defaults AND every layer, before any fold); shadowed-cycle batch ⇒ `1` cycle, `.value` ⇒ threw. Tests: `test-conservative-shadowed-cycle`, `test-conservative-shadowed-cycle-throws` (`ci/tests/static-graph.nix`) |
| An edge's target field is only the **head** of the ref path; the rest survives as edge data, not as graph structure | `lib/graph.nix:refGraph` (`edgesOf` — `field = head r.path`); `ref B [ "sz" "deep" "deeper" ]` ⇒ `to.field = "sz"`, `path = ["sz","deep","deeper"]`, `at = [ ]`, `from.field = "font"` |
| Provenance is **per-entry lazy**: a shadowed entry whose contribution refs an absent aspect leaves the chain spine, its own metadata, its siblings and the resolved value all forceable — only that entry's `value` throws | `lib/resolve.nix:mkProvEntry`; chain length ⇒ `3`, shadowed entry's `rendered` ⇒ `"L"`, its `value` ⇒ threw, winner's `value` ⇒ `"WINS"`, `.value` ⇒ `"WINS"`. Tests: `test-shadow-spine-forceable`, `test-shadow-sibling-forceable`, `test-shadow-entry-throws-on-force` (`ci/tests/provenance.nix`) |
| Layer labels are needed **only** when provenance is forced — a bare `{ value = …; }` layer folds a correct value, then dies on a raw missing-attribute error (again not `tryEval`-catchable) | `lib/resolve.nix:layerLabel`; `.value` ⇒ `{ font = "x"; }`, forcing `.provenance` ⇒ `error: attribute 'scope' missing at …/lib/resolve.nix:50:33`; control, full layer, `.provenance` ⇒ forced clean |
| `assembleHost` forces its `class`/`entity` identity checks at first force **even when `aspects = [ ]`** | `lib/inject.nix:assembleHost` (the body's `builtins.seq classOk (builtins.seq entityOk …)`); `class = "nixos"` ⇒ threw, `entity = { name = "x"; }` ⇒ threw, valid pair ⇒ `{ }`. Tests: `test-class-string-error`, `test-entity-no-idhash-error` (`ci/tests/identity-keying.nix`) |
| The `assembleHost` result key is the `settingsKey` (default `aspect.name`); identity lives on the module's gen-bind `key` as `class.name@entity.id_hash/aspect.id_hash` | `lib/inject.nix:assembleHost` (`keyed`'s `_key`, and `mkOne`'s `identity` / `bind.wrapIdentity`); `attrNames` ⇒ `["theme"]`, module attrs ⇒ `["_file","imports","key"]`, `key` ⇒ `"nixos@host0axon00000001/a1b2c3d4deadbeef"`. Test: `test-key-format-golden` (`ci/tests/identity-keying.nix`) |
| `injectAspectSettings` always **routes** through `bind.wrap`, but the returned `wrapped` is gen-bind's "did I rebind an argument" flag — it is `false` for content that declares no bound argument | gen-bind `lib/wrap.nix:wrapFunctionModule` (the `boundArgNames == [ ]` passthrough) and `lib/wrap.nix:wrapCore` (the plain-attrset passthrough); four contents measured — `{ settings, ... }: { }` ⇒ `true`, `_: { }` ⇒ `false`, `{ foo = 1; }` ⇒ `false`, `{ imports = [ ({ settings, ... }: { }) ]; }` ⇒ `true` |
| `renderAddress` truncates `id_hash` to 8 characters and is display-only | `lib/display.nix:shortHash`, `lib/display.nix:renderAddress`; from a 16-char hash ⇒ `aspect(theme#a1b2c3d4)`, `aspect(theme#a1b2c3d4).font`, `aspect(theme#a1b2c3d4).font.mono.x` |
| A duplicate batch `key` is E7 at first force of `.value` | `lib/resolve.nix:resolveAll` (`gate`); two members with `key = "k"` ⇒ threw. Test: `test-e7-duplicate-key` (`ci/tests/resolution-errors.nix`) |
| `mkSchema` with no fields is legal | `lib/schema.nix:mkSchema`; `fields = { }` ⇒ `{ aspect; defaults = { }; fields = { }; strategies = { }; }` |
| The layer list is never sorted, deduped or filtered — order *is* authority | `git grep -n -E 'sort\|unique\|dedup' -- lib/resolve.nix` returns only the comment at `:149`; positive control `git grep -n -E 'sort' -- lib/graph.nix` ⇒ `:22`, `:73`. The ordering behaviour itself is pinned by `test-permute-flips-winner`, `test-duplicate-appends-twice`, `test-provenance-order-preserved` (`ci/tests/no-reordering.nix`) — read, not exercised in this run |

## Theory

`README.md` § *Theoretical Foundations* lists its sources flat, with no Implements/Informed-by split; the same claims are restated in code comments.

- **Mokhov, Mitchell & Peyton Jones (2018), *Build Systems à la Carte*, §3** — refs are *applicative* task dependencies, so the cross-aspect graph is computable before any value is produced. The conservative, structurally-strict `refGraph` is that discipline, over-approximated statically. Restated in the file headers of `lib/schema.nix`, `lib/ref.nix` and `lib/graph.nix`.
- **Positional authority** — config/policy precedence research grounds authority-by-position and the deliberate absence of a per-declaration strength lattice; `lib/resolve.nix`'s file header names CSS Cascading & Inheritance L5 §6 and nixpkgs `mkOverride` as the contrast, not the model.
- **Cardelli (1997), *Program Fragments, Linking, and Modularization*, POPL, §3** — linksets carry identity used to resolve duplicates. **Inherited**, not implemented here: realized by gen-bind `wrapIdentity` (`lib/inject.nix` file header; `lib/inject.nix:assembleHost` — `bind.wrapIdentity`).
- **Chitil (2012), *Practical Typed Lazy Contracts*, ICFP** — **inherited** via gen-bind; `contracts` is forwarded unchanged at `lib/inject.nix:injectAspectSettings` (`inherit contracts provenance` into `bind.wrap`) — `README.md` § *Theoretical Foundations*, "Lazy contracts at the injection boundary".
- **Néron, Tolmach, Visser & Wachsmuth (2015), *A Theory of Name Resolution*, ESOP** — context only. `README.md` § *Theoretical Foundations* ("Layer-order provenance (context)") states the upstream D < I < P chain is realized by gen-scope, **not by this lib**.

**Acceptance gate**: the resolved value is byte-identical to gen-algebra's real `foldLayers` over the same strategies, defaults and layer values — `test-value-equals-foldLayers` (`ci/tests/value-parity.nix`), with `ci/flake.nix:genAlgebra` exposing the real fold to the suite. Labels are fold-opaque: `test-value-invariant-under-labels`, `test-algebra-value-label-opaque` (`ci/tests/label-opacity.nix`).

**Checked invariants**

- nixpkgs-lib-free — `test-library-source-is-nixpkgs-free` (`ci/tests/purity.nix`) scans `lib/**.nix` plus the root `flake.nix` and `default.nix`, comments stripped, for `nixpkgs`, `lib.types`, `lib.mkOption`, `lib.mkMerge`, `lib.mkForce`, `lib.evalModules`, `evalModules`, `{ lib }`, `{ lib,` (`ci/tests/purity.nix:forbidden`). `ci/` is out of scope by design.
- No hashing — `git grep -n -E 'hashString|builtins\.hash|hashFile' -- lib/` returns nothing; positive control `git grep -c -E 'id_hash' -- lib/` hits 7 files. Identity is read, never minted.
- No strength/priority machinery — `git grep -n -E 'mkForce|mkOverride|mkDefault|priority|strength' -- lib/` hits only `lib/resolve.nix`'s file-header comment; positive control `git grep -c -E 'merge' -- lib/` hits 3 files.
- The only gen-\* names anywhere in `lib/` are the four injected deps plus a `gen-schema` comment — `git grep -n -o -E 'gen-[a-z]+' -- lib/ | sort -u` yields `gen-settings` (self), `gen-algebra`, `gen-prelude`, `gen-bind`, `gen-graph`, and `gen-schema` in `lib/default.nix`'s file header only.

## Drift check

```sh
nix eval --json .#lib --apply 'builtins.attrNames'
```

Current output (verbatim):

```json
["assembleHost","assertAcyclic","injectAspectSettings","isRef","mkSchema","ref","refGraph","refsIn","renderAddress","resolveAll","resolveOne"]
```

The export surface is flat — there is no nested namespace. The non-flake entry must agree; it produces the same list:

```sh
nix eval --impure --json --expr 'builtins.attrNames (import ./default.nix { })'
```

**Checks.** Test-runner invocation (from the repo root; CI runs the same command with `working-directory: ci` — `.github/workflows/ci.yml`, the `check` job's `defaults.run.working-directory` and its `run: nix flake check` step):

```sh
nix flake check ./ci
```
