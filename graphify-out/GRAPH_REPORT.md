# Graph Report - RoBall3D  (2026-10-19)

## Corpus Check
- Corpus is ~13,505 words - fits in a single context window. You may not need a graph.

## Summary
- 96 nodes · 173 edges · 6 communities
- Extraction: 80% EXTRACTED · 20% INFERRED · 0% AMBIGUOUS · INFERRED: 35 edges (avg confidence: 0.84)
- Token cost: 0 input · 0 output

## Community Hubs (Navigation)
- Community 0
- Community 1
- Community 2
- Community 3
- Community 4
- Community 5

## God Nodes (most connected - your core abstractions)
1. `DESIGN.md — RoBall3D design document` - 18 edges
2. `TrackStreamer:buildChunk()` - 10 edges
3. `Config.luau — all tunables` - 10 edges
4. `startRun()` - 6 edges
5. `GenCore.luau — pure seeded generator` - 6 edges
6. `TrackStreamer.luau — spec -> Instances` - 6 edges
7. `Palette.neonAt()` - 5 edges
8. `killRun()` - 5 edges
9. `Ui.new()` - 5 edges
10. `AGENTS.md — agent workflow contract` - 5 edges

## Surprising Connections (you probably didn't know these)
- `DESIGN.md — RoBall3D design document` --references--> `Seeds.luau — seed parse/hash`  [EXTRACTED]
  DESIGN.md → src/ReplicatedStorage/RoBall/Seeds.luau
- `DESIGN.md — RoBall3D design document` --references--> `SaveService.luau — DataStore persistence`  [EXTRACTED]
  DESIGN.md → src/ServerScriptService/RoBallServer/SaveService.luau
- `AGENTS.md — agent workflow contract` --references--> `ChunkDefs.luau — chunk type table + builders`  [INFERRED]
  AGENTS.md → src/ReplicatedStorage/RoBall/ChunkDefs.luau
- `DESIGN.md — RoBall3D design document` --references--> `ChunkDefs.luau — chunk type table + builders`  [EXTRACTED]
  DESIGN.md → src/ReplicatedStorage/RoBall/ChunkDefs.luau
- `DESIGN.md — RoBall3D design document` --references--> `Config.luau — all tunables`  [EXTRACTED]
  DESIGN.md → src/ReplicatedStorage/RoBall/Config.luau

## Import Cycles
- None detected.

## Hyperedges (group relationships)
- **One hue feeds all visuals (track edging, gem glow, sun stripes, mountains)** — src_replicatedstorage_roball_palette_luau, src_serverscriptservice_roballserver_trackstreamer_luau, src_starterplayer_starterplayerscripts_roballclient_backdrop_luau [EXTRACTED 1.00]
- **Seeded chunk generation pipeline (Random seed -> chunk spec -> streamed Instances)** — src_replicatedstorage_roball_gencore_luau, src_replicatedstorage_roball_chunkdefs_luau, src_serverscriptservice_roballserver_trackstreamer_luau, src_replicatedstorage_roball_config_luau [EXTRACTED 1.00]
- **Server-side run lifecycle (boot -> lane + ball + track + score -> death -> restart)** — src_serverscriptservice_roballserver_main_server_luau, src_serverscriptservice_roballserver_runmanager_luau, src_serverscriptservice_roballserver_trackstreamer_luau, src_serverscriptservice_roballserver_balldriver_luau, src_serverscriptservice_roballserver_scoreservice_luau [INFERRED 0.85]

## Communities (6 total, 0 thin omitted)

### Community 0 - "Community 0"
Cohesion: 0.15
Nodes (16): GenCore.new(), hashSeed(), killRun(), onPlayerAdded(), plausible(), randomSeed(), resolveSeed(), spawnBall() (+8 more)

### Community 1 - "Community 1"
Cohesion: 0.14
Nodes (5): ChunkDefs.wrapGrade(), GenCore:nextChunk(), introSection(), Tiers.forDistance(), Tiers.speedAt()

### Community 2 - "Community 2"
Cohesion: 0.28
Nodes (19): AGENTS.md — agent workflow contract, DESIGN.md — RoBall3D design document, README.md — project overview, ChunkDefs.luau — chunk type table + builders, Config.luau — all tunables, GenCore.luau — pure seeded generator, Palette.luau — distance -> vaporwave gradient, Seeds.luau — seed parse/hash (+11 more)

### Community 3 - "Community 3"
Cohesion: 0.28
Nodes (10): Palette.dimAt(), Palette.hueAt(), Palette.neonAt(), Backdrop.init(), Backdrop.update(), bar(), initSun(), layPeak() (+2 more)

### Community 4 - "Community 4"
Cohesion: 0.27
Nodes (8): makeBlock(), makeEdgeStrip(), makeGem(), makeGridStrip(), makeSlicePart(), makeWall(), TrackStreamer:buildChunk(), TrackStreamer:ensureAhead()

### Community 5 - "Community 5"
Cohesion: 0.25
Nodes (5): label(), outlineButton(), Ui.new(), Ui:setLeaderboard(), vlist()

## Suggested Questions
_Questions this graph is uniquely positioned to answer:_

- **Why does `TrackStreamer:buildChunk()` connect `Community 4` to `Community 3`?**
  _High betweenness centrality (0.017) - this node is a cross-community bridge._
- **Are the 2 inferred relationships involving `TrackStreamer:buildChunk()` (e.g. with `Palette.dimAt()` and `Palette.neonAt()`) actually correct?**
  _`TrackStreamer:buildChunk()` has 2 INFERRED edges - model-reasoned connections that need verification._
- **Should `Community 1` be split into smaller, more focused modules?**
  _Cohesion score 0.1368421052631579 - nodes in this community are weakly interconnected._
- **Are the 5 inferred relationships involving `Config.luau — all tunables` (e.g. with `ChunkDefs.luau — chunk type table + builders` and `GenCore.luau — pure seeded generator`) actually correct?**
  _`Config.luau — all tunables` has 5 INFERRED edges - model-reasoned connections that need verification._
- **Are the 4 inferred relationships involving `GenCore.luau — pure seeded generator` (e.g. with `ChunkDefs.luau — chunk type table + builders` and `Config.luau — all tunables`) actually correct?**
  _`GenCore.luau — pure seeded generator` has 4 INFERRED edges - model-reasoned connections that need verification._