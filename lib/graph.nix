# refGraph / assertAcyclic — the static cross-aspect dependency graph.
#
# Field-level granularity: a contribution to address (A, f) containing `ref B [g, …]` yields
# edge (A,f) -> (B,g). The graph is a pure function of schemas + layer values (structure only;
# `resolveRef` is never invoked) and is CONSERVATIVE over pre-fold values — edges are collected
# from every layer contribution and every schema default, before any shadowing (L17). This is
# the honest cost of the static/applicative discipline (Mokhov et al., ICFP 2018 §3): the graph
# is over-approximated statically rather than discovered during resolution.
#
# Cycle DETECTION is gen-graph's (`cyclePaths`), not this library's: the SCC partition and the
# ordered representative cycle are general graph results, and re-deriving them here cost a full
# simple-path enumeration on the acyclic — i.e. the always-taken — path. What stays here is the
# E3 DIAGNOSTIC, which is genuinely this library's: the field-address vocabulary and its rendering.
{
  prelude,
  ref,
  display,
  genGraph,
}:
let
  inherit (builtins)
    attrNames
    listToAttrs
    head
    concatMap
    filter
    map
    concatStringsSep
    ;
  inherit (ref) refsIn;
  inherit (display) renderAddress;

  # Internal graph key — id_hash + field. Identity law: keys are id_hash-based, names are
  # display only. The field component is what keeps mutually-referring aspects from refusing:
  # granularity is a property of this key, and gen-graph treats it as an opaque string.
  nodeKey = addr: "${addr.aspect.id_hash}:${addr.field}";

  # E3's body. Each cycle renders as a traversal closing back on its head — every " -> " is a real
  # edge, which is what the ordered cycle contract buys — and cycles are joined by "; ". This is a
  # NAMED binding rather than a local of assertAcyclic because a throw's message is unreachable to
  # `builtins.tryEval` (it yields only `success`), so a golden that cannot call the renderer can
  # only re-implement it, and a re-implementation is not an oracle for the shipped one.
  renderCycles =
    cycles:
    let
      renderCycle =
        cyc:
        let
          addrs = map (a: renderAddress { inherit (a) aspect field; }) cyc;
        in
        concatStringsSep " -> " (addrs ++ [ (head addrs) ]);
    in
    concatStringsSep "; " (map renderCycle cycles);
in
{
  inherit renderCycles;

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

      # Each reported cycle is an ORDERED walk over node keys — every consecutive pair is an
      # edge — which is what licenses assertAcyclic's " -> " join below.
      cycles = map (cyc: map (k: nodeMap.${k}) cyc) (
        genGraph.cyclePaths {
          nodes = nodeKeys;
          edges = k: adj.${k} or [ ];
        }
      );
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
      throw "gen-settings: ref cycle (E3): ${renderCycles graph.cycles}";
}
