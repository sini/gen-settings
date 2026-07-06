# refGraph / assertAcyclic — the static cross-aspect dependency graph.
#
# Field-level granularity: a contribution to address (A, f) containing `ref B [g, …]` yields
# edge (A,f) -> (B,g). The graph is a pure function of schemas + layer values (structure only;
# `resolveRef` is never invoked) and is CONSERVATIVE over pre-fold values — edges are collected
# from every layer contribution and every schema default, before any shadowing (L17). This is
# the honest cost of the static/applicative discipline (Mokhov et al., ICFP 2018 §3): the graph
# is over-approximated statically rather than discovered during resolution.
{
  prelude,
  ref,
  display,
}:
let
  inherit (builtins)
    attrNames
    listToAttrs
    elem
    elemAt
    head
    length
    sort
    genList
    concatMap
    filter
    foldl'
    map
    concatStringsSep
    ;
  inherit (ref) refsIn;
  inherit (display) renderAddress;

  # Internal graph key — id_hash + field. Identity law: keys are id_hash-based, names are
  # display only.
  nodeKey = addr: "${addr.aspect.id_hash}:${addr.field}";

  mod = a: b: a - ((a / b) * b);
  firstNonNull = foldl' (acc: x: if acc != null then acc else x) null;

  # Find a cycle through `start` (a path start -> … -> start) as an ordered list of node keys,
  # or null. Standard DFS over the field-address graph.
  cycleFromKey =
    start: adj:
    let
      walk =
        path: node:
        let
          succs = adj.${node} or [ ];
        in
        firstNonNull (
          map (
            s:
            if s == start then
              path # closed: path already holds start..node
            else if elem s path then
              null # a non-start node already on the path — a different cycle, skip
            else
              walk (path ++ [ s ]) s
          ) succs
        );
    in
    walk [ start ] start;

  findCycles =
    nodeKeys: adj: nodeMap:
    let
      raw = filter (c: c != null) (map (k: cycleFromKey k adj) nodeKeys);
      # Canonicalize by rotating each cycle to start at its smallest node key, so rotations of
      # the same cycle dedup to one representative.
      canon =
        cyc:
        let
          minK = head (sort (a: b: a < b) cyc);
          n = length cyc;
          idxOf = foldl' (
            acc: i:
            if acc != null then
              acc
            else if elemAt cyc i == minK then
              i
            else
              null
          ) null (genList (i: i) n);
          rotate = genList (i: elemAt cyc (mod (idxOf + i) n)) n;
        in
        rotate;
      canoned = map canon raw;
      dedup = foldl' (acc: c: if elem c acc then acc else acc ++ [ c ]) [ ] canoned;
    in
    map (cyc: map (k: nodeMap.${k}) cyc) dedup;
in
{
  # refGraph batch -> { nodes; edges; cycles; }
  #   batch = [ { schema; layers; … } ]
  refGraph =
    batch:
    let
      # Every contribution — schema defaults AND every layer value — before any fold.
      contribSources =
        m:
        let
          A = m.schema.aspect;
          defs = m.schema.defaults or { };
          fromDefaults = map (f: {
            field = f;
            value = defs.${f};
          }) (attrNames defs);
          fromLayers = concatMap (
            l:
            map (f: {
              field = f;
              value = l.value.${f};
            }) (attrNames l.value)
          ) m.layers;
        in
        map (c: {
          aspect = A;
          inherit (c) field value;
        }) (fromDefaults ++ fromLayers);

      allContribs = concatMap contribSources batch;

      edgesOf =
        c:
        map (r: {
          from = {
            inherit (c) aspect field;
          };
          to = {
            aspect = r.aspect;
            field = head r.path;
          };
          inherit (r) at path;
        }) (refsIn c.value);

      edges = concatMap edgesOf allContribs;

      # Nodes: every declared field address plus every edge endpoint (dedup by node key).
      declaredAddrs = concatMap (
        m:
        map (f: {
          aspect = m.schema.aspect;
          field = f;
        }) (attrNames (m.schema.defaults or { }))
      ) batch;
      nodeAddrs = declaredAddrs ++ map (e: e.from) edges ++ map (e: e.to) edges;
      nodeMap = listToAttrs (
        map (a: {
          name = nodeKey a;
          value = a;
        }) nodeAddrs
      );
      nodeKeys = attrNames nodeMap;
      nodes = map (k: nodeMap.${k}) nodeKeys;

      adj = listToAttrs (
        map (k: {
          name = k;
          value = map (e: nodeKey e.to) (filter (e: nodeKey e.from == k) edges);
        }) nodeKeys
      );

      cycles = findCycles nodeKeys adj nodeMap;
    in
    {
      inherit nodes edges cycles;
    };

  # assertAcyclic graph -> graph  (identity when cycles == []; otherwise E3).
  # The E3 message renders every address in each cycle, closing back to its head.
  assertAcyclic =
    graph:
    if graph.cycles == [ ] then
      graph
    else
      let
        renderCycle =
          cyc:
          let
            addrs = map (a: renderAddress { inherit (a) aspect field; }) cyc;
          in
          concatStringsSep " -> " (addrs ++ [ (head addrs) ]);
        rendered = concatStringsSep "; " (map renderCycle graph.cycles);
      in
      throw "gen-settings: ref cycle (E3): ${rendered}";
}
