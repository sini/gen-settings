# refGraph / assertAcyclic — the static cross-aspect dependency graph.
#
# Field-level granularity: a contribution to address (A, f) containing `ref B [g, …]` yields
# edge (A,f) -> (B,g). The graph is a pure function of schemas + layer values (structure only;
# `resolveRef` is never invoked) and is CONSERVATIVE over pre-fold values — edges are collected
# from every layer contribution and every schema default, before any shadowing (L17). This is
# the honest cost of the static/applicative discipline (Mokhov et al., ICFP 2018 §3): the graph
# is over-approximated statically rather than discovered during resolution.
#
# Neither the EDGE DERIVATION nor the CYCLE DETECTION is this library's. Deriving a graph from
# what a scan finds inside values is gen-graph's `fromScan`; the SCC partition and the ordered
# representative cycle are its `cyclePaths`. Both are general graph results — gen-schema derives
# kind-to-kind edges by the same shape from its declared ref fields — and re-deriving them beside
# each caller is how one concern comes to live in several places.
#
# What stays here is the vocabulary and the diagnostic, which are genuinely this library's: the
# batch shape a contribution is enumerated out of, the FIELD ADDRESS a node key encodes, the scan
# and the projection handed to the derivation, and the E3 rendering. gen-graph sees opaque strings
# throughout, which is exactly what keeps the field granularity available: coarsening a node to its
# aspect would refuse ordinary configurations whose aspects refer to one another mutually.
#
# WHAT DID NOT GO WITH IT, and the reason is the same sentence. The declared-address list and the
# key -> address map stay, because what a node key MEANS is this library's: a node reached only as
# a ref target is named by the reference that reached it, and gen-graph — which is handed a scan
# and a projection and nothing else — has no way to name it. That is a boundary, not a shortfall
# in the constructor.
#
# THE COST OF HANDING IT OVER, PRICED RATHER THAN ASSUMED. The incumbent indexed adjacency with a
# per-node `filter` over the whole edge list; what replaces it is gen-graph's `groupBy` index plus
# a `prelude.unique` per query — and `unique` is quadratic, now sitting on the always-taken path,
# which is exactly the kind of swap that goes unstated. Measured on `ci/perf-bench.nix`'s acyclic
# diamond chain, the workload this library already ships for this question: `nrFunctionCalls`
# FALLS at every size the shipped driver runs — 16.6% at n=8, rising monotonically to 21.0% at
# n=16. Cheaper, and the gap widens with n. Both arms report `cycles = 0` on the acyclic path and
# a non-zero count on the `backedge` control, so they are pricing the same work.
#
# Re-run, and it produces THOSE sizes and no others — `ci/perf-bench.sh`'s `NS` is a hardcoded
# `(8 10 12 14 16)` with no override:
#
#     PERF_BASELINE_LIB=<incumbent lib/> nix run ./ci#perf-bench
#
# `AGENTS.md` carries the same contrast out to n=80 through the by-hand recipe in
# `ci/perf-bench.nix`'s header. Those figures are not comparable cell-for-cell with these because
# they are taken at LARGER n, where the gap is wider — the two instruments are otherwise the same
# shape, each swapping a whole `lib/` directory per arm. The join is smooth: the per-step widening
# decelerates 1.6, 1.2, 0.9, 0.7 points across n=8→16 and then 1.1 points over the four further
# nodes to n=20, one curve rather than two.
#
# ★ THE NAME `refGraph` IS KEPT, DEPARTING FROM THE EXTRACTION SPEC'S §8.5 ("retires as a name").
#   §8.5 grounds that on `assembleHost` receiving the same disposition "for the same reason", but
#   §9.1's reason for `assembleHost` is that the construct DECOMPOSES — "no successor construct,
#   no single home" — so the name goes because nothing is left to name. §8.5 itself says this
#   library KEEPS a thin binding, and a surviving export is not that case; the analogy fails on
#   the spec's own text. What the binding returns is still the batch's ref graph, so the name
#   denotes its value rather than its retired implementation.
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

      # The address a hop names: the ref's aspect, and the HEAD of its path. The rest of the path
      # is edge data, never graph structure — an edge says which field is depended on, not which
      # position inside it.
      targetOf = r: {
        inherit (r) aspect;
        field = head r.path;
      };

      # An address map keyed by node key. `listToAttrs` keeps the FIRST binding for a repeated
      # key, so position inside one call is precedence.
      keyed =
        addrs:
        listToAttrs (
          map (a: {
            name = nodeKey a;
            value = a;
          }) addrs
        );

      # Every declared field address. These are the nodes no edge touches, and nothing else puts
      # them in the graph — gen-graph seeds a node set from the derived edges and from this map,
      # never from the scanned items.
      declaredAddrs = concatMap (
        m:
        map (f: {
          inherit (m.schema) aspect;
          field = f;
        }) (attrNames (m.schema.defaults or { }))
      ) batch;
      declaredMap = keyed declaredAddrs;

      # The derivation, handed to its owner: contributions in, hops out, adjacency and node set
      # built there. What crosses is a scan and a projection — gen-graph never learns what a ref
      # is, and the field address travels as an opaque key.
      scanned = genGraph.fromScan {
        items = map (c: c // { id = nodeKey c; }) allContribs;
        scan = refsIn;
        project = r: nodeKey (targetOf r);
        nodeData = declaredMap;
      };

      # The hops, restated in this library's vocabulary. The reference rides on the derived edge,
      # so naming an address costs no second scan of the contribution.
      edges = map (e: {
        from = {
          inherit (e.item) aspect field;
        };
        to = targetOf e.ref;
        inherit (e.ref) at path;
      }) scanned.derivedEdges;

      # What a node key MEANS is this library's, so the mapping back to an address stays here. A
      # declared address wins its key, then a source, then a target: an address reached only as a
      # ref target is named by the ref that reached it.
      nodeMap = keyed (map (e: e.from) edges ++ map (e: e.to) edges) // declaredMap;

      # Each reported cycle is an ORDERED walk over node keys — every consecutive pair is an
      # edge — which is what licenses assertAcyclic's " -> " join below.
      cycles = map (cyc: map (k: nodeMap.${k}) cyc) (
        genGraph.cyclePaths { inherit (scanned) nodes edges; }
      );
    in
    {
      nodes = map (k: nodeMap.${k}) scanned.nodes;
      inherit edges cycles;
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
