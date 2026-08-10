# gen-settings — API Reference

Signature-level reference for the gen-settings public surface. Every value carrying identity is a
gen-schema registry entry (an attrset with `name` + `id_hash`); `"kind:name"` strings are never
input, only internal keys and rendered display. Error codes (E1–E8) are cross-referenced to the
laws they enforce.

## Contents

- [Schema construction](#schema-construction)
- [Refs](#refs)
- [Static dependency graph](#static-dependency-graph)
- [Resolution](#resolution)
- [Injection](#injection)
- [Display](#display)
- [Data shapes](#data-shapes)
- [Error codes](#error-codes)

______________________________________________________________________

## Schema construction

### `mkSchema`

```nix
mkSchema = { aspect, fields }: { aspect; fields; strategies; defaults; }
```

- `aspect` — aspect registry entry (carries `id_hash`), the declaring identity.
- `fields` — `{ <bare-key> = { default; merge ? "replace"; }; }`.

Normalizes into plain, always-introspectable data. `strategies = mapAttrs (_: f: f.merge)` and
`defaults = mapAttrs (_: f: f.default)` are the exact shapes `foldLayersTraced` consumes.

**Rules (all E1):** field names are bare keys (no dots); `default` is mandatory on every leaf;
`merge ∈ { "replace", "append", "recursive" }`. Dotted keys are checked eagerly (name-level, no
`default` value forced); missing-default / bad-merge fire when the offending field's strategy or
default is forced.

______________________________________________________________________

## Refs

### `ref`

```nix
ref = aspectEntry: path: { __genSchemaFieldRef = true; aspect = aspectEntry; path = path; }
```

Inert, identity-bearing cross-aspect reference. `aspectEntry` MUST carry `id_hash` (E6 otherwise, at
application time — a string or an id-less attrset throws immediately). `path` is a non-empty list of
field-name strings; its head is a field of the target schema. Refs are plain data (no functions, no
thunks) and are **merge-atomic**: no strategy ever merges *into* a ref.

The record and the scan below are gen-schema's `fieldRef` / `isFieldRef` / `fieldRefsIn`, re-exported
here; the datum sits beside the option **type** (`schema.ref`) whose inhabitants these values are.
gen-settings keeps the E6 code and its message, thrown at this boundary before the record is built.

### `isRef`

```nix
isRef = v: bool
```

True iff `v` is a ref record. Forces `v` to WHNF (structural strictness — Nix cannot inspect a thunk
without forcing it).

### `refsIn`

```nix
refsIn = v: [ { at; aspect; path; } ]
```

Deep structural scan of any value. `at` is the subpath within `v` where the ref sits (`[ ]` = `v`
itself; attrset keys and list indices compose it). Refs are inspected as records, never resolved
(L7). Non-collection scalars are leaves.

**A function in a scanned position is REFUSED**, not treated as a leaf: the scan throws, naming the
position. The domain is data. A ref inside a closure is unreachable to any structural scan, so
skipping it fails open — the edge is never derived, the cycle it would have closed goes undetected,
and the unresolved record leaks into the resolved value as data. This is a user-visible refusal
contract: a value that once evaluated with a silently-invisible ref now throws.

The refusal is wider than the hazard on purpose (a ref-free function refuses too, at any depth), and
its error names the reads-visible constructs to route a computed value through. The only sanctioned
escape is a declared schema-level annotation, never a quieter scan — gen-schema's README, *If the
refusal is in your way*, carries that path.

______________________________________________________________________

## Static dependency graph

### `refGraph`

```nix
refGraph = batch: { nodes; edges; cycles; }
```

- `batch` — `[ { schema; layers; … } ]`.
- `nodes` — `[ <address> ]`, address `= { aspect = <entry>; field; }`.
- `edges` — `[ { from = <address>; to = <address>; at; path; } ]`, **field-level**: a contribution
  to `(A, f)` containing `ref B [g, …]` yields edge `(A,f) → (B,g)`.
- `cycles` — `[ [ <address> ] ]`, each an **ordered** address list: consecutive pairs are real
  edges, so the list may be rendered as a traversal. **One representative per cyclic component**,
  rotated to begin at the component's smallest node key — a component holding several distinct
  cycles reports one of them. Edge derivation is gen-graph's `fromScan` — the scan and the
  field-address projection are handed to it — and detection is its `cyclePaths`; the field-level
  node key (`id_hash:field`) is what keeps mutually-referring aspects from refusing, and it
  crosses into gen-graph as an opaque string.

Pure function of schemas + layer values — `resolveRef` is never invoked, no resolved value is
computed. **Conservative over pre-fold values** (edges from every default + every layer contribution,
before shadowing) and **structurally strict** (forces every scanned position to WHNF), L17.

### `assertAcyclic`

```nix
assertAcyclic = graph: graph        # identity when cycles == []; otherwise E3
```

E3 renders every address in each cycle, closing back to the head, e.g.
`aspect(theme#a1b2c3d4).font -> aspect(terminal#e5f6a7b8).font-stack -> aspect(theme#a1b2c3d4).font`.

### `renderCycles`

```nix
renderCycles = cycles: string        # [ [ <address> ] ] -> the E3 body
```

The rendering `assertAcyclic` interpolates into its throw, exposed as a named binding. Each cycle
becomes a traversal closing back on its head (`" -> "`), and cycles are joined by `"; "`. Exposed
because a throw's message is unreachable to `builtins.tryEval`, which yields only `success` — so a
caller or test that cannot call this can only re-implement it, and a re-implementation is not an
oracle for the shipped rendering.

______________________________________________________________________

## Resolution

### `resolveOne`

```nix
resolveOne = {
  schema,
  layers,                # ordered [ <layer> ], least → most specific
  resolveRef ? <throws E4>,   # { aspect, path }: <resolved value>
  strict ? true,         # contributions to undeclared fields throw E2
}: { value; provenance; }
```

Fold-then-substitute: the fold runs over raw (ref-inert) values, then refs in the folded value are
deep-substituted via `resolveRef` (equivalent to folding pre-substituted inputs — refs are
merge-atomic, L3). `value` is one key per schema field (+ passthrough keys when `!strict`);
`provenance.<field>` is the ordered chain (§ Data shapes).

- **Strict mode** — an undeclared contribution is E2, detected at the attr-name level (contribution
  values never forced) and fired when the result spine is first forced.
- **Non-strict mode** — unknown fields pass through under `replace` with contributor-only provenance
  (no default entry).
- **Laziness (L15.2)** — a field never read is never resolved; its contribution values are never
  forced and its refs never followed.

The default `resolveRef` throws E4 generically; rich E4/E5 addressing lives in `resolveAll`.

### `resolveAll`

```nix
resolveAll = {
  batch,   # [ { schema; layers; key ? <aspect name>; strict ? true; } ]
}: { value; provenance; graph; }
```

Builds the batch's `refGraph`, applies `assertAcyclic`, then defines the resolved set lazily and
recursively — `resolveRef` for each member looks up the referenced aspect **by id_hash** in the
in-flight resolved set and walks `path` into its resolved value. Laziness supplies evaluation order;
static acyclicity guarantees productivity (no toposort performed).

- `value = { <key> = <resolved attrset>; }`, `provenance = { <key> = <per-field chain>; }`,
  `graph` = the `refGraph`.
- **Strict in structure, lazy in resolution** (L17/L8): first force runs the E7 duplicate-key check
  and the cycle check — forcing every contribution to WHNF — before any resolved value. An unread
  field's fold is never computed and its refs are never followed (L15.3).
- Ref errors: target not in batch → **E4** (names source + target); bad path → **E5** (names source,
  target, and the failing path component). Duplicate `key` → **E7**.

______________________________________________________________________

## Injection

### `injectAspectSettings`

```nix
injectAspectSettings = {
  aspect,
  classContent,              # fn | { imports = [ … ]; } | plain attrset
  settings,                  # resolved settings value for this (entity, aspect)
  settingsKey ? <aspect name>,
  bindings ? { },            # extra injected args, e.g. host = <entity record>
  contracts ? { },           # forwarded to gen-bind (lazy contracts)
  provenance ? { },          # forwarded to gen-bind blame metadata
}: { module; wrapped; signature; }
```

Always-wrap through gen-bind `wrap` (no `isFunction` guard). The settings binding is namespaced —
`settings = { ${settingsKey} = <resolved>; }` — so content reads `settings.<key>.<field>`. Injected
bindings shadow same-named stray module args (`bindWins`); `lib`/`config`/`pkgs` flow from the module
system (never injected). Wrap forces nothing (L15.1). `wrapped = false` only for the plain-attrset
passthrough (byte-identical).

### `assembleHost`

```nix
assembleHost = {
  entity,                    # host/user registry entry OR a cell record — MUST carry id_hash
  class,                     # class REGISTRY ENTRY (its `name` is the wrapIdentity key token)
  aspects,                   # [ { aspect; classContent; settings; settingsKey ?; bindings ? { }; } ]
  bindings ? { },            # shared bindings merged under each aspect's own
}: { <settingsKey> = <identity-keyed module>; }
```

Wraps every injected module with `wrapIdentity`, keying by id_hash pairs:
`"${class.name}@${entity.id_hash}/${aspect.id_hash}"`. Distinct entities (or cells, keyed by
canonical cell identity) with the same aspect yield distinct keys (no dedup collapse); identical
`(class, entity, aspect)` yields an equal key (evalModules merges once). A class-name string or an
`entity`/cell without `id_hash` is a definition-time error (forced at first force of the result).
Duplicate `settingsKey` in one call is **E8** (names the key and both aspect identities).

______________________________________________________________________

## Display

### `renderAddress`

```nix
renderAddress = { aspect, field ? null, path ? null }: string
```

`"aspect(theme#a1b2c3d4)"` / `"aspect(theme#a1b2c3d4).font"` / `"…​.font.mono"` — name + 8-char
`id_hash` prefix. Used by all error messages; display only, never parsed.

______________________________________________________________________

## Data shapes

### Layer (input, computed upstream)

```nix
{
  scope    = { <dim> = <registry entry>; … } | null;   # { host = …; } / { host; user; } / null
  rendered = "sini@axon-01";                            # display string
  via      = <aspect registry entry> | null;            # projecting aspect (projects facet) or null
  value    = { <field> = <contribution>; };             # bare-key partial; may contain refs
}
```

### Provenance entry

```nix
{
  scope    = <as given on the layer, or { aspect = <schema.aspect>; } for the default entry>;
  rendered = <layer's rendered, or "default">;
  via      = <layer's via, or null>;
  value    = <contribution, refs substituted — PER-ENTRY LAZY (L15.4)>;
  refs     = [ { at; aspect; path; } ];                 # one per ref in the contribution; [ ] if none
}
```

`provenance.<field>` = ordered list of entries, default entry first when the field is declared.
Per-entry lazy substitution: forcing the chain spine or any sibling entry never resolves a given
entry's refs — only forcing that entry's own `value` does. The entry above is what this library
hands `foldLayersTraced` as its `entryTransform`, so the chain is emitted refined by the fold
rather than re-mapped over its output; the laziness is that hook's non-interference law.

### Address / edge / graph

```nix
address = { aspect = <registry entry>; field = "font"; };
edge    = { from = <address>; to = <address>; at = [ <subpath> ]; path = [ … ]; };
graph   = { nodes; edges; cycles; };
```

______________________________________________________________________

## Error codes

| Code | Where | Meaning |
|---|---|---|
| **E1** | `mkSchema` | schema shape violation — dotted key, missing `default`, or unknown `merge` |
| **E2** | `resolveOne` (strict) | a layer contributes a field not declared by the schema |
| **E3** | `assertAcyclic` / `resolveAll` | a ref cycle, naming every address in the cycle |
| **E4** | `resolveAll` | ref target aspect not present in the batch |
| **E5** | `resolveAll` | ref `path` component not present in the target's resolved value |
| **E6** | `ref` | ref target is not an identity-bearing entry (no `id_hash`), or bad `path` |
| **E7** | `resolveAll` | duplicate batch `key` |
| **E8** | `assembleHost` | duplicate `settingsKey` within one call |
