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
    head
    seq
    ;
  inherit (ref) isRef refsIn;
  inherit (display) renderAddress;
  inherit (graph) refGraph assertAcyclic;

  # Deep ref substitution. Refs are merge-atomic (§2.2): a ref is replaced wholesale, never
  # merged into — so fold-then-substitute equals folding pre-substituted inputs (L3).
  substDeep =
    resolve: v:
    if isRef v then
      resolve { inherit (v) aspect path; }
    else if isAttrs v then
      mapAttrs (_: e: substDeep resolve e) v
    else if isList v then
      map (substDeep resolve) v
    else
      v;

  # Structured layer label — fully opaque to foldLayersTraced (it stores labels into provenance
  # and never reads them; the value fold is independent of them, L4).
  layerLabel = l: { inherit (l) scope rendered via; };

  # Raw (ref-inert) fold + structured provenance + attr-name-level strict scan.
  foldMember =
    {
      schema,
      layers,
      strict,
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
      rawProvenance = guard folded.provenance;
      inherit violations;
    };

  # A provenance entry: structured coordinates + hop records + PER-ENTRY-LAZY substituted value.
  # `value` substitutes only this entry's own refs and only when itself forced (L15.4); forcing
  # the chain spine or any sibling entry computes `refs` (structurally strict) but never resolves.
  mkProvEntry = resolve: entry: {
    inherit (entry.layer) scope rendered via;
    refs = map (r: { inherit (r) at aspect path; }) (refsIn entry.value);
    value = substDeep resolve entry.value;
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
      m = foldMember { inherit schema layers strict; };
    in
    {
      value = mapAttrs (_: v: substDeep resolveRef v) m.rawValue;
      provenance = mapAttrs (_: entries: map (mkProvEntry resolveRef) entries) m.rawProvenance;
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
        in
        mapAttrs (field: v: substDeep (resolveRefFrom e.member.schema.aspect field) v) e.raw.rawValue;

      resolvedProvOf =
        h:
        let
          e = raws.${h};
        in
        mapAttrs (
          field: entries: map (mkProvEntry (resolveRefFrom e.member.schema.aspect field)) entries
        ) e.raw.rawProvenance;

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
      graph = theGraph;
    };
}
