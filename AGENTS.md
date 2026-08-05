# gen-settings — agent capability sheet

## Scope

Stratified settings resolution: folds a static `{ default; merge }` schema against a caller-supplied ordered layer list into `{ value; provenance; }`, adding refs-as-data (inert cross-aspect references with a static dependency graph) and the injection construct that hands the resolved value to parametric class content.

## Not this library's job

Quoted text is the owner's own `flake.nix` `description` field, verbatim.

| Responsibility | Owner |
|---|---|
| The layered fold itself — merge strategies, accumulation, value byte-identity | `gen-algebra` — "gen-algebra: pure Nix algebra — search monad, records, intensional functions, either". `lib/resolve.nix:33` binds `algebra.record.foldLayersTraced`; the fold is never reimplemented here |
| Module argument binding, `wrap` / `wrapIdentity`, lazy contracts | `gen-bind` — "gen-bind: module binding with external arguments for Nix". Used at `lib/inject.nix:45` (`bind.wrap`) and `lib/inject.nix:106` (`bind.wrapIdentity`) |
| Minting `id_hash`, kinds, registries | `gen-schema` — "gen-schema: typed record registry with extension points for the pure-gen module system". Consumed **interface-only**: not a flake input (`flake.nix:8-12`), and the name occurs in `lib/` only inside a comment (`lib/default.nix:5`). gen-settings only *reads* `id_hash` |
| Deriving the containment chain the layer list is built from | `gen-product` — "gen-product — graph products as first-class operations over accessor-graphs (Cartesian / tensor / strong / lexicographic; cells, slices, fibers, projections, quotients, restriction, containment chains), lazy in and out". `README.md:31` names it as the upstream producer |
| Deriving the D/I scope chain / name-resolution order | `gen-scope` — "gen-scope: demand-driven attribute grammar evaluator over algebraic scope graphs". `README.md:31,133` names it as the upstream producer |
| Graph traversal and query combinators | `gen-graph` — "gen-graph: accessor-based graph query combinators". `lib/graph.nix` carries a private DFS (`cycleFromKey` / `findCycles`, `lib/graph.nix:42-90`) and imports nothing |
| Choosing *which* graph positions a setting applies to | `gen-select` — "gen-select: selector algebra for attributed graph positions" |
| Aspect traits and classification — gen-settings treats an aspect entry as opaque data needing only `name` + `id_hash` | `gen-aspects` — "gen-aspects: aspect-oriented composition types (pure-gen, re-hosted on gen-merge)" |
| Module merge / `evalModules` — the token is CI-forbidden inside `lib/` (`ci/tests/purity.nix:52`) | `gen-merge` — "gen-merge — pure-Nix byte-mode module MERGE engine (evalModuleTree) for the pure-gen module system" |
| Class content itself (partition / contract / apply / gate) | `gen-class` — "gen-class — pure-Nix class-share mechanism (partition / contract / apply / gate) for the pure-gen module system" |
| Structural type checking — `mkSchema` hand-rolls name and shape checks (`lib/schema.nix:24-27,54-68`) | `gen-types` — "gen-types: pure, nixpkgs-lib-free structural type checker for the gen ecosystem" |
| General utilities | `gen-prelude` — "gen-prelude: vendored, nixpkgs-lib-free pure utilities for the gen ecosystem". Used at `lib/ref.nix:18` (`imap0`) and `lib/resolve.nix:62` (`concatMap`) |

## Exports

Two entries, both yielding the same eleven names.

- **Flake**: `inputs.gen-settings.lib` — `flake.nix:22-26` applies `import ./lib` to `gen-prelude.lib`, `gen-algebra.lib`, `gen-bind.lib`.
- **Root `default.nix`** (non-flake): a function whose arguments are all defaulted. It reads its own lockfile — `builtins.fromJSON (builtins.readFile ./flake.lock)` (`default.nix:8`) — resolves `lock.nodes.${lock.nodes.root.inputs.<name>}.locked` and `builtins.fetchTree`s that node (`default.nix:9-16`), then imports `<fetched>/lib` (`default.nix:17-19`). `prelude` and `algebra` are imported bare; `bind` is re-applied to `prelude` (`default.nix:19`) because gen-bind's `lib/` is itself a function.
- `import ./lib` alone is **a function** of `{ prelude, algebra, bind }` (`lib/default.nix:7-11`) — not a bare value.

**Schema** — `lib/schema.nix`

| Export | Signature |
|---|---|
| `mkSchema` | `{ aspect, fields } -> { aspect; fields; strategies; defaults; }` |

`fields` leaves are `{ default; merge ? "replace"; }`; `merge ∈ { replace, append, recursive }` (`lib/schema.nix:18-22`); field names are bare keys.

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
| E1 | schema shape: dotted field name, missing `default`, unknown `merge` | `lib/schema.nix:47,57,63` |
| E2 | strict mode: a layer contributes an undeclared field | `lib/resolve.nix:94` |
| E3 | ref cycle | `lib/graph.nix:185` |
| E4 | unresolved ref (no resolver, or target absent from the batch) | `lib/resolve.nix:130,186` |
| E5 | bad ref path: a component is not present in the resolved value | `lib/resolve.nix:202` |
| E6 | ref target is not an `id_hash`-bearing entry, or the path is malformed | `lib/ref.nix:33,35` |
| E7 | duplicate batch key | `lib/resolve.nix:236` |
| E8 | duplicate `settingsKey` within one `assembleHost` call | `lib/inject.nix:91` |
| L14 | `assembleHost` `class`/`entity` identity violation | `lib/inject.nix:74,79` |

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
| `substDeep`, `refMarker` and `shortHash` are exported by their own modules but dropped by the public surface | `lib/resolve.nix:116`, `lib/ref.nix:25`, `lib/display.nix:13` vs `lib/default.nix:28-35`; `lib ? substDeep` / `? refMarker` / `? shortHash` all ⇒ `false`, control `lib ? isRef` ⇒ `true` |
| A dotted field name is an **eager** E1 — it fires on *any* use of the schema, including `attrNames` of its own `fields` | `lib/schema.nix:44-50,72` (`seq dotCheck`); `.aspect` ⇒ threw, `attrNames .fields` ⇒ threw; control, bare key, `.aspect` ⇒ succeeded |
| A missing `default` or unknown `merge` is **per-field lazy** — the schema, its attribute names, and every sibling field stay usable | `lib/schema.nix:54-68`; with `fields = { good = { default = 1; }; bad = { }; }`: `.aspect` ⇒ ok, `attrNames .defaults` ⇒ ok, `.defaults.good` ⇒ ok, `.defaults.bad` ⇒ threw. Same shape for `merge`: `attrNames .strategies` ⇒ ok, `.strategies.f` ⇒ threw. Tests: `test-e1-dotted-key`, `test-e1-missing-default`, `test-e1-bad-merge` (`ci/tests/resolution-errors.nix`) |
| `merge` accepts exactly three strategies; `"semilattice-set"` is E1 here **even though the underlying fold implements it** | `lib/schema.nix:18-22`; `.strategies.f` with `merge = "semilattice-set"` ⇒ threw. The fold's fourth branch is read from gen-algebra `lib/rec.nix:260-264`, not exercised in this run |
| `ref` validates at **application** time, not at resolution time | `lib/ref.nix:32-36`; `ref "theme" [ "font" ]`, `ref { name = "theme"; } [ "font" ]`, `ref A [ ]` and `ref A [ 1 ]` all threw; control `ref A [ "font" ]` ⇒ record |
| `isRef` is marker-only — a hand-written `{ __genSettingsRef = true; }` is accepted and *counted*, and dies later on a raw missing-attribute error (not an E-code, and **not** `tryEval`-catchable) | `lib/ref.nix:22,57-58`; `isRef` ⇒ `true`, `length (refsIn { x = <marker>; })` ⇒ `1`, forcing that hit's `.path` ⇒ `error: attribute 'path' missing at …/lib/ref.nix:58:36`; control, a real `ref`, `.path` ⇒ `["font"]` |
| `refsIn` is **structurally strict**: a throwing position anywhere in the scanned value throws during the scan | `lib/ref.nix:46-48`; `refsIn { x = throw "boom"; }` ⇒ threw, control `refsIn { x = 1; }` ⇒ `[ ]` |
| A ref inside a function body is invisible — functions are scan leaves | `lib/ref.nix:47-48,65-66`; `refsIn { f = _: ref A [ "font" ]; }` ⇒ `0` hits, control `refsIn { f = ref A [ "font" ]; }` ⇒ `1` |
| `resolveOne`'s default `resolveRef` **throws E4** — a schema whose own `default` is a ref is unusable without one | `lib/resolve.nix:125-133`; `.value` ⇒ threw; with `resolveRef = _: "RESOLVED"` ⇒ `{ font = "RESOLVED"; }` |
| With `strict = false` an undeclared contribution is not dropped — it **passes through into the resolved value** under an implicit `replace` | `lib/resolve.nix:88-98` guards but never filters; the key union is gen-algebra's (`lib/rec.nix:239-242`). Layer `{ font = "x"; nope = 1; }` against a `font`-only schema: default strict ⇒ threw (E2), `strict = false` ⇒ `{ font = "x"; nope = 1; }`, control declared-only ⇒ `{ font = "x"; }` |
| `resolveAll`'s `.graph` is **not** gated by `assertAcyclic` — it hands back a cyclic graph without complaint while `.value` throws | `lib/resolve.nix:233-238,257`; on a 2-cycle batch `deepSeq r.graph` ⇒ ok, `length r.graph.cycles` ⇒ `1`, `r.value` ⇒ threw, `assertAcyclic r.graph` ⇒ threw |
| Two batch members sharing one `aspect.id_hash` under **distinct keys** pass E7 and then silently collapse — both keys resolve to the *first* member's fold | `lib/resolve.nix:153-156,162-173` (E7 checks keys; `raws` is a `listToAttrs` keyed by `id_hash`). Members declaring `default = "FIRST"` and `default = "SECOND"`: keys ⇒ `["theme","theme2"]`, value ⇒ `{"theme":{"font":"FIRST"},"theme2":{"font":"FIRST"}}` |
| `refGraph` is conservative over **pre-fold** values: a ref that a later `replace` layer shadows still contributes an edge, so a fully-shadowed 2-cycle is still E3 | `lib/graph.nix:98-119`; shadowed-cycle batch ⇒ `1` cycle, `.value` ⇒ threw. Tests: `test-conservative-shadowed-cycle`, `test-conservative-shadowed-cycle-throws` (`ci/tests/static-graph.nix`) |
| An edge's target field is only the **head** of the ref path; the rest survives as edge data, not as graph structure | `lib/graph.nix:131`; `ref B [ "sz" "deep" "deeper" ]` ⇒ `to.field = "sz"`, `path = ["sz","deep","deeper"]`, `at = [ ]`, `from.field = "font"` |
| Provenance is **per-entry lazy**: a shadowed entry whose contribution refs an absent aspect leaves the chain spine, its own metadata, its siblings and the resolved value all forceable — only that entry's `value` throws | `lib/resolve.nix:109-113`; chain length ⇒ `3`, shadowed entry's `rendered` ⇒ `"L"`, its `value` ⇒ threw, winner's `value` ⇒ `"WINS"`, `.value` ⇒ `"WINS"`. Tests: `test-shadow-spine-forceable`, `test-shadow-sibling-forceable`, `test-shadow-entry-throws-on-force` (`ci/tests/provenance.nix`) |
| Layer labels are needed **only** when provenance is forced — a bare `{ value = …; }` layer folds a correct value, then dies on a raw missing-attribute error (again not `tryEval`-catchable) | `lib/resolve.nix:50`; `.value` ⇒ `{ font = "x"; }`, forcing `.provenance` ⇒ `error: attribute 'scope' missing at …/lib/resolve.nix:50:33`; control, full layer, `.provenance` ⇒ forced clean |
| `assembleHost` forces its `class`/`entity` identity checks at first force **even when `aspects = [ ]`** | `lib/inject.nix:117-121`; `class = "nixos"` ⇒ threw, `entity = { name = "x"; }` ⇒ threw, valid pair ⇒ `{ }`. Tests: `test-class-string-error`, `test-entity-no-idhash-error` (`ci/tests/identity-keying.nix`) |
| The `assembleHost` result key is the `settingsKey` (default `aspect.name`); identity lives on the module's gen-bind `key` as `class.name@entity.id_hash/aspect.id_hash` | `lib/inject.nix:83,105-110`; `attrNames` ⇒ `["theme"]`, module attrs ⇒ `["_file","imports","key"]`, `key` ⇒ `"nixos@host0axon00000001/a1b2c3d4deadbeef"`. Test: `test-key-format-golden` (`ci/tests/identity-keying.nix`) |
| `injectAspectSettings` always **routes** through `bind.wrap`, but the returned `wrapped` is gen-bind's "did I rebind an argument" flag — it is `false` for content that declares no bound argument | gen-bind `lib/wrap.nix:98-102,263-271`; four contents measured — `{ settings, ... }: { }` ⇒ `true`, `_: { }` ⇒ `false`, `{ foo = 1; }` ⇒ `false`, `{ imports = [ ({ settings, ... }: { }) ]; }` ⇒ `true` |
| `renderAddress` truncates `id_hash` to 8 characters and is display-only | `lib/display.nix:10,19-30`; from a 16-char hash ⇒ `aspect(theme#a1b2c3d4)`, `aspect(theme#a1b2c3d4).font`, `aspect(theme#a1b2c3d4).font.mono.x` |
| A duplicate batch `key` is E7 at first force of `.value` | `lib/resolve.nix:235-236`; two members with `key = "k"` ⇒ threw. Test: `test-e7-duplicate-key` (`ci/tests/resolution-errors.nix`) |
| `mkSchema` with no fields is legal | `lib/schema.nix:33-78`; `fields = { }` ⇒ `{ aspect; defaults = { }; fields = { }; strategies = { }; }` |
| The layer list is never sorted, deduped or filtered — order *is* authority | `git grep -n -E 'sort\|unique\|dedup' -- lib/resolve.nix` returns only the comment at `:149`; positive control `git grep -n -E 'sort' -- lib/graph.nix` ⇒ `:22`, `:73`. The ordering behaviour itself is pinned by `test-permute-flips-winner`, `test-duplicate-appends-twice`, `test-provenance-order-preserved` (`ci/tests/no-reordering.nix`) — read, not exercised in this run |

## Theory

`README.md:127-133` lists its sources flat, with no Implements/Informed-by split; the same claims are restated in code comments.

- **Mokhov, Mitchell & Peyton Jones (2018), *Build Systems à la Carte*, §3** — refs are *applicative* task dependencies, so the cross-aspect graph is computable before any value is produced. The conservative, structurally-strict `refGraph` is that discipline, over-approximated statically. Restated at `lib/schema.nix:5-6`, `lib/ref.nix:5-6`, `lib/graph.nix:7-8`.
- **Positional authority** — config/policy precedence research grounds authority-by-position and the deliberate absence of a per-declaration strength lattice; `lib/resolve.nix:5-7` names CSS Cascading & Inheritance L5 §6 and nixpkgs `mkOverride` as the contrast, not the model.
- **Cardelli (1997), *Program Fragments, Linking, and Modularization*, POPL, §3** — linksets carry identity used to resolve duplicates. **Inherited**, not implemented here: realized by gen-bind `wrapIdentity` (`lib/inject.nix:6-8,106`).
- **Chitil (2012), *Practical Typed Lazy Contracts*, ICFP** — **inherited** via gen-bind; `contracts` is forwarded unchanged at `lib/inject.nix:48` (`README.md:132`).
- **Néron, Tolmach, Visser & Wachsmuth (2015), *A Theory of Name Resolution*, ESOP** — context only. `README.md:133` states the upstream D < I < P chain is realized by gen-scope, **not by this lib**.

**Acceptance gate**: the resolved value is byte-identical to gen-algebra's real `foldLayers` over the same strategies, defaults and layer values — `test-value-equals-foldLayers` (`ci/tests/value-parity.nix`), with `ci/flake.nix:29` exposing the real fold to the suite. Labels are fold-opaque: `test-value-invariant-under-labels`, `test-algebra-value-label-opaque` (`ci/tests/label-opacity.nix`).

**Checked invariants**

- nixpkgs-lib-free — `test-library-source-is-nixpkgs-free` (`ci/tests/purity.nix`) scans `lib/**.nix` plus the root `flake.nix` and `default.nix`, comments stripped, for `nixpkgs`, `lib.types`, `lib.mkOption`, `lib.mkMerge`, `lib.mkForce`, `lib.evalModules`, `evalModules`, `{ lib }`, `{ lib,` (`ci/tests/purity.nix:45-55`). `ci/` is out of scope by design.
- No hashing — `git grep -n -E 'hashString|builtins\.hash|hashFile' -- lib/` returns nothing; positive control `git grep -c -E 'id_hash' -- lib/` hits 7 files. Identity is read, never minted.
- No strength/priority machinery — `git grep -n -E 'mkForce|mkOverride|mkDefault|priority|strength' -- lib/` hits only the comment at `lib/resolve.nix:6`; positive control `git grep -c -E 'merge' -- lib/` hits 3 files.
- The only gen-\* names anywhere in `lib/` are the three injected deps plus a `gen-schema` comment — `git grep -n -o -E 'gen-[a-z]+' -- lib/ | sort -u` yields `gen-settings` (self), `gen-algebra`, `gen-prelude`, `gen-bind`, and `gen-schema` at `lib/default.nix:5` only.

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

**Checks.** Test-runner invocation (from the repo root; CI runs the same command with `working-directory: ci`, `.github/workflows/ci.yml:13,18`):

```sh
nix flake check ./ci
```
