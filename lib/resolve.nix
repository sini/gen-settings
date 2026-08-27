# resolveOne / resolveAll — the stratified fold plus fold-then-substitute ref resolution.
#
# The fold itself lives in gen-algebra (`record.foldLayersTraced`, the single fold implementation
# per Spike 5 — never reimplemented here). Authority is positional: for `replace`, the last
# contributor wins; `append`/`recursive` accumulate in layer order. The deliberate absence of a
# per-declaration strength dimension (the CSS Cascading & Inheritance L5 §6 / nixpkgs mkOverride
# lattice) is the honest realization of authority-by-position (config/policy precedence research).
{
  prelude,
  algebra,
  ref,
  graph,
  display,
}:
let
  inherit (builtins)
    attrNames
    listToAttrs
    elem
    filter
    map
    mapAttrs
    foldl'
    isAttrs
    isList
    isFunction
    typeOf
    head
    seq
    ;
  inherit (ref) isRef refsIn;
  inherit (display) renderAddress;
  inherit (graph) refGraph assertAcyclic;

  # The ground types of Nix's value language: the leaves substitution returns untouched. `set` and
  # `list` are the composites it descends, and a ref is the one leaf it replaces — so naming these
  # six is what lets the dispatch below enumerate its cases instead of ending in a fall-through.
  #
  # A membership SET rather than a list, because this is tested at every leaf of every substituted
  # value. `builtins.elem` over the same six names walks a list per leaf and measured materially
  # more expensive on a substitution-heavy workload; this test measured at +1.1% thunks against the
  # partial dispatch it replaces, with counters BYTE-IDENTICAL to an `else v` control performing no
  # leaf test at all. Totality is free; the list was what was not. The multiple for the rejected
  # form is workload- and build-dependent — hoisting alone moves it — so it is not pinned here.
  leafTypes = {
    int = true;
    float = true;
    bool = true;
    string = true;
    path = true;
    "null" = true;
  };

  # Deep ref substitution. Refs are merge-atomic (§2.2): a ref is replaced wholesale, never
  # merged into — so fold-then-substitute equals folding pre-substituted inputs (L3).
  #
  # ★ THE DISPATCH IS TOTAL, AND IT REFUSES WHAT THE SCAN REFUSES. `refsIn` derives the dependency
  #   graph and its domain is data: a function in a scanned position is refused there, never
  #   skipped as a leaf. This produces the value. Were substitution to admit an input the scan
  #   refuses, a value would be produced from an input no edge was ever derived over — and the
  #   static/applicative discipline `graph.nix` cites (Mokhov, Mitchell & Peyton Jones, ICFP 2018,
  #   §3) is precisely the requirement that the extracted dependencies and the produced value range
  #   over the same inputs. So the residual case throws rather than falling through, and it throws
  #   HERE: this is the single substitution primitive both `resolveOne` and `resolveAll` reach a
  #   resolved value through, so refusing at this point removes the case instead of catching it at
  #   one of them and leaving the other open.
  #
  #   Two arms reach the same refusal, and they are not redundant. `isFunction` is the case that
  #   exists — the one the scan refuses and the one a consumer can write. The membership test after
  #   it is what makes the dispatch total: every value the language does not offer as a leaf is
  #   refused, and `lambda` is merely its only inhabitant today. The message names the type it was
  #   handed rather than saying "function", so the second arm is not a message written for a value
  #   nobody can construct.
  #
  # ★ THE MESSAGE CARRIES NO E-CODE, DELIBERATELY. Whether a refusal about the ref datum — whose
  #   machinery lives in the library that owns that datum — speaks in this library's E-vocabulary
  #   is an open question this text is written not to prejudge. What it does assert is the
  #   POSITION: the field-headed address of the value that carried the offending input. Settling
  #   the vocabulary changes the prefix and nothing else here.
  #
  # ★ THE POSITION IS THE FIELD, AND IS FIXED FOR THE DESCENT. It is not extended with each attr
  #   name and list index walked into, because that subpath is neither free nor missing. Not free:
  #   accumulating one allocates a record at every node of every conforming value, and measured as
  #   the dominant cost of this whole change — paid forever, to sharpen a message that conforming
  #   input never produces. Not missing: the scan refuses the same value and its refusal carries its
  #   own subpath, so on `{ colors = [ "ok" (_: someRef) ]; }` the pair reports `aspect(theme#…).f`
  #   here and `colors.1` there. The field is also the coordinate E2, E4 and E5 already blame.
  refuse =
    at: v:
    throw "gen-settings: cannot substitute into a value of type '${typeOf v}': ${renderAddress at} — substitution ranges over the same data the ref scan derives the dependency graph from, and that scan refuses this position rather than treating it as a leaf, so a value produced here would come from an input no dependency edge was ever derived over";

  substDeep =
    resolve: at: v:
    if isRef v then
      resolve { inherit (v) aspect path; }
    else if isAttrs v then
      mapAttrs (_: e: substDeep resolve at e) v
    else if isList v then
      map (substDeep resolve at) v
    else if isFunction v then
      refuse at v
    else if leafTypes ? ${typeOf v} then
      v
    else
      refuse at v;

  # Structured layer label — fully opaque to foldLayersTraced (it stores labels into provenance
  # and never reads them; the value fold is independent of them, L4).
  layerLabel = l: { inherit (l) scope rendered via; };

  # The refinement this library hands to the traced fold as gen-algebra's `entryTransform`: an
  # entry's structured coordinates, its hop records, and the PER-ENTRY-LAZY substitution of that
  # entry's own refs. `value` resolves only when itself forced (L15.4) — forcing the chain spine,
  # this entry's coordinates, or any sibling computes `refs` (structurally strict over the
  # contribution's shape) but follows no ref. gen-algebra's non-interference law is what carries
  # that through the fold rather than around it, and the ref vocabulary below never crosses over.
  # `resolverFor` is field-indexed because E4/E5 name the SOURCE field as well as the target, and
  # `sourceAspect` is taken for the same reason one hop further: with it, the position a refusal
  # blames is the same field-headed address those diagnostics render. The parameter carries the
  # `source` prefix `resolveAll`'s resolver already uses, since `aspect` is also the name of the
  # TARGET coordinate each hop record below inherits from the scan.
  refineEntry = sourceAspect: resolverFor: field: entry: {
    inherit (entry.layer) scope rendered via;
    refs = map (r: { inherit (r) at aspect path; }) (refsIn entry.value);
    value = substDeep (resolverFor field) {
      aspect = sourceAspect;
      inherit field;
    } entry.value;
  };

  # Raw (ref-inert) value fold + refined provenance + attr-name-level strict scan.
  foldMember =
    {
      schema,
      layers,
      strict,
      resolverFor,
    }:
    let
      schemaFields = attrNames schema.fields;
      # Attr-name-level scan: reads each layer value's attr NAMES, never the values (L15.2).
      violations = prelude.concatMap (
        l:
        map (f: {
          field = f;
          inherit (l) rendered;
          aspect = schema.aspect;
        }) (filter (f: !(elem f schemaFields)) (attrNames l.value))
      ) layers;

      defaultLabel = {
        scope = {
          aspect = schema.aspect;
        };
        rendered = "default";
        via = null;
      };

      folded = algebra.record.foldLayersTraced {
        inherit (schema) strategies defaults;
        layers = map (l: l.value) layers;
        layerNames = map layerLabel layers;
        inherit defaultLabel;
        entryTransform = refineEntry schema.aspect resolverFor;
      };

      # Strict mode: an undeclared contribution is E2, fired when the result spine is first
      # forced (mirrors the L8 timing discipline); contribution values are never forced by it.
      guard =
        x:
        if strict && violations != [ ] then
          let
            v = head violations;
          in
          throw "gen-settings: undeclared field (E2): layer '${v.rendered}' contributes field '${v.field}' not declared by ${
            renderAddress { inherit (v) aspect; }
          }"
        else
          x;
    in
    {
      rawValue = guard folded.value;
      provenance = guard folded.provenance;
      inherit violations;
    };
in
{
  inherit substDeep;

  # resolveOne { schema; layers; resolveRef ?; strict ? true } -> { value; provenance; }
  # Standalone resolver: takes an external address-resolver (default throws E4). Rich batch-level
  # ref addressing (E4/E5) lives in resolveAll, where the batch/graph context exists.
  resolveOne =
    {
      schema,
      layers,
      resolveRef ? (
        {
          aspect,
          path,
        }:
        throw "gen-settings: unresolved ref (E4): no resolveRef supplied to resolveOne for target ${
          renderAddress { inherit aspect; }
        }"
      ),
      strict ? true,
    }:
    let
      # Standalone: one resolver serves every field, so the field index is discarded here. The
      # batch resolver in resolveAll is the one that uses it.
      m = foldMember {
        inherit schema layers strict;
        resolverFor = _field: resolveRef;
      };
    in
    {
      value = mapAttrs (
        field: v:
        substDeep resolveRef {
          inherit (schema) aspect;
          inherit field;
        } v
      ) m.rawValue;
      inherit (m) provenance;
    };

  # resolveAll { batch } -> { value; provenance; graph; }
  #   batch = [ { schema; layers; key ? <aspect name>; strict ? true; } ]
  # Strict in structure, lazy in resolution: first force runs the E7 duplicate-key check and the
  # conservative graph acyclicity check (L8/L17) — forcing every contribution position to WHNF —
  # before any resolved value. Ref routing knot-ties by id_hash; laziness supplies evaluation
  # order, static acyclicity guarantees productivity (no toposort needed or performed).
  resolveAll =
    { batch }:
    let
      keyed = map (m: m // { _key = m.key or m.schema.aspect.name; }) batch;
      keys = map (m: m._key) keyed;
      counts = foldl' (acc: k: acc // { ${k} = (acc.${k} or 0) + 1; }) { } keys;
      dupKeys = filter (k: counts.${k} > 1) (attrNames counts);

      theGraph = refGraph batch;
      checkedGraph = assertAcyclic theGraph;

      # Raw folds keyed by aspect id_hash (ref routing is by identity, never by display key).
      raws = listToAttrs (
        map (m: {
          name = m.schema.aspect.id_hash;
          value = {
            member = m;
            raw = foldMember {
              inherit (m) schema layers;
              strict = m.strict or true;
              # Knot-tied: the resolver reaches back through `raws`, and nothing forces it until
              # an entry's own value is forced — by which point `raws` is the value we came
              # through. The fold's non-interference law is what keeps that from being a cycle.
              resolverFor = resolveRefFrom m.schema.aspect;
            };
          };
        }) keyed
      );

      # Rich resolver carrying the source (aspect, field) so E4/E5 name both endpoints (L10).
      resolveRefFrom =
        sourceAspect: sourceField:
        {
          aspect,
          path,
        }:
        let
          entry = raws.${aspect.id_hash} or null;
        in
        if entry == null then
          throw "gen-settings: unresolved ref (E4): ${
            renderAddress {
              aspect = sourceAspect;
              field = sourceField;
            }
          } references ${renderAddress { inherit aspect; }} which is not present in the batch"
        else
          walkPath sourceAspect sourceField aspect path (resolvedValueOf aspect.id_hash);

      walkPath =
        sourceAspect: sourceField: targetAspect: path: rootVal:
        foldl' (
          acc: comp:
          if isAttrs acc && acc ? ${comp} then
            acc.${comp}
          else
            throw "gen-settings: bad ref path (E5): ${
              renderAddress {
                aspect = sourceAspect;
                field = sourceField;
              }
            } -> ${
              renderAddress {
                aspect = targetAspect;
                inherit path;
              }
            }: component '${comp}' not present in the resolved value"
        ) rootVal path;

      resolvedValueOf =
        h:
        let
          e = raws.${h};
          inherit (e.member.schema) aspect;
        in
        mapAttrs (
          field: v: substDeep (resolveRefFrom aspect field) { inherit aspect field; } v
        ) e.raw.rawValue;

      # The counterpart of resolvedValueOf: the fold already emitted the refined chains, so this
      # is the read, not a second pass over them.
      resolvedProvOf = h: raws.${h}.raw.provenance;

      # Definition-time gate at first force of the result: E7, then acyclicity (which also forces
      # every contribution to WHNF via the graph scan), then the (still-lazy) resolved attrset.
      gate =
        x:
        if dupKeys != [ ] then
          throw "gen-settings: duplicate batch key (E7): '${head dupKeys}'"
        else
          seq checkedGraph x;
    in
    {
      value = gate (
        listToAttrs (
          map (m: {
            name = m._key;
            value = resolvedValueOf m.schema.aspect.id_hash;
          }) keyed
        )
      );
      provenance = gate (
        listToAttrs (
          map (m: {
            name = m._key;
            value = resolvedProvOf m.schema.aspect.id_hash;
          }) keyed
        )
      );
      # checkedGraph, not theGraph: assertAcyclic is check-then-return (identity on an acyclic
      # graph, E3 on a cyclic one — ci/tests/static-graph.nix's test-assertAcyclic-identity), so
      # this is byte-identical to theGraph on every acyclic batch and is the one view of validity
      # `.value` already gates on (:242/:323 above). Returning theGraph here let `.graph` deepSeq
      # clean on a batch whose `.value` throws E3 — two views of one result disagreeing about
      # validity (den-hoag-yk07).
      graph = checkedGraph;
    };
}
