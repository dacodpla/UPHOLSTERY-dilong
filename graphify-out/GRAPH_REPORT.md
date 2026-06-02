# Graph Report - .  (2026-06-02)

## Corpus Check
- Corpus is ~29,607 words - fits in a single context window. You may not need a graph.

## Summary
- 235 nodes · 298 edges · 37 communities (34 shown, 3 thin omitted)
- Extraction: 92% EXTRACTED · 8% INFERRED · 0% AMBIGUOUS · INFERRED: 24 edges (avg confidence: 0.85)
- Token cost: 0 input · 0 output

## Community Hubs (Navigation)
- [[_COMMUNITY_Project Config|Project Config]]
- [[_COMMUNITY_Core Client Scripts|Core Client Scripts]]
- [[_COMMUNITY_Minigame Modules|Minigame Modules]]
- [[_COMMUNITY_Job Pool & Talkogram|Job Pool & Talkogram]]
- [[_COMMUNITY_MinigameRunner Logic|MinigameRunner Logic]]
- [[_COMMUNITY_Seam Stitching Logic|Seam Stitching Logic]]
- [[_COMMUNITY_Job Generator & Economy|Job Generator & Economy]]
- [[_COMMUNITY_Staple Gunning Logic|Staple Gunning Logic]]
- [[_COMMUNITY_Location Manager|Location Manager]]
- [[_COMMUNITY_Foam Padding Logic|Foam Padding Logic]]
- [[_COMMUNITY_Tack Removal Logic|Tack Removal Logic]]
- [[_COMMUNITY_Gameplay Client HUD|Gameplay Client HUD]]
- [[_COMMUNITY_Job Board UI|Job Board UI]]
- [[_COMMUNITY_Admin Panel UI|Admin Panel UI]]
- [[_COMMUNITY_Claude Hook Settings|Claude Hook Settings]]
- [[_COMMUNITY_Claude Permissions|Claude Permissions]]
- [[_COMMUNITY_Laptop Prompt Config|Laptop Prompt Config]]

## God Nodes (most connected - your core abstractions)
1. `Minigames System` - 13 edges
2. `RadiantJobGenerator.Generate()` - 10 edges
3. `tree` - 9 edges
4. `MinigameRunner.Run()` - 8 edges
5. `MinigameRunner.RunChain()` - 8 edges
6. `MinigameRunner Module` - 8 edges
7. `$properties` - 6 edges
8. `LocationManager.Assign()` - 6 edges
9. `Reputation System` - 6 edges
10. `LaptopBrowser Script` - 6 edges

## Surprising Connections (you probably didn't know these)
- `Economy System` --conceptually_related_to--> `PlayerData Server Script`  [INFERRED]
  UPHOLSTERY_GDD_v8.txt → explain.md
- `Core Gameplay Loop` --conceptually_related_to--> `GameplayClient Script`  [INFERRED]
  UPHOLSTERY_GDD_v8.txt → explain.md
- `Job System` --conceptually_related_to--> `LocationManager Script`  [INFERRED]
  UPHOLSTERY_GDD_v8.txt → explain.md
- `Shared Job Board` --conceptually_related_to--> `LaptopBrowser Script`  [INFERRED]
  UPHOLSTERY_GDD_v8.txt → explain.md
- `Minigames System` --conceptually_related_to--> `MinigameRunner Module`  [INFERRED]
  UPHOLSTERY_GDD_v8.txt → explain.md

## Import Cycles
- None detected.

## Hyperedges (group relationships)
- **Core Gameplay Loop — Accept, Play, Earn, Spend** — gdd_shared_job_board, gdd_minigames, gdd_reputation_system, gdd_economy, gdd_toolbox_perk_system [EXTRACTED 0.95]
- **Multi-Axis Progression — Money, Followers, Reputation** — gdd_economy, gdd_followers, gdd_reputation_system, gdd_player_house, gdd_direct_offers [EXTRACTED 0.95]
- **Client-Server Minigame Execution Pipeline** — explain_gameplay_client, explain_minigame_runner, explain_laptop_data, explain_location_manager [EXTRACTED 0.95]

## Communities (37 total, 3 thin omitted)

### Community 0 - "Project Config"
Cohesion: 0.07
Nodes (28): $path, $path, $properties, name, Ambient, Brightness, FilteringEnabled, GlobalShadows (+20 more)

### Community 1 - "Core Client Scripts"
Cohesion: 0.11
Nodes (28): GameConfig Shared Module, GameplayClient Script, LaptopBrowser Script, LaptopData Server Script, LaptopInteraction Script, LocationManager Script, PlayerData Server Script, Bolt vs Bespoke Perk Tiers (+20 more)

### Community 2 - "Minigame Modules"
Cohesion: 0.15
Nodes (18): FoamPadding Luau Module, MinigameRunner Module, SeamStitching Luau Module, StapleGunning Luau Module, TackRemoval Luau Module, Button Tufting Minigame (Post-Launch), Corner Fold Minigame (Post-Launch), Foam Padding Minigame (+10 more)

### Community 3 - "Job Pool & Talkogram"
Cohesion: 0.15
Nodes (9): init(), init(), loadGlobalFeed(), savePost(), LocationManager.Release(), assignHouse(), getHouseCFrame(), onPlayerAdded() (+1 more)

### Community 4 - "MinigameRunner Logic"
Cohesion: 0.32
Nodes (13): onDoorTriggered(), addBlur(), buildGui(), buildParams(), MinigameRunner.Cancel(), MinigameRunner.CollapseChainResult(), MinigameRunner.IsRunning(), MinigameRunner.Run() (+5 more)

### Community 5 - "Seam Stitching Logic"
Cohesion: 0.23
Nodes (10): addTrailDot(), buildDeviationMeter(), buildUI(), closestPointOnSegment(), disconnect(), generatePath(), makeLabel(), makePill() (+2 more)

### Community 6 - "Job Generator & Economy"
Cohesion: 0.33
Nodes (11): buildFurniturePool(), buildJobName(), calcFollowers(), calcPay(), getFurniturePool(), pickForCategory(), pickRandom(), RadiantJobGenerator.Generate() (+3 more)

### Community 7 - "Staple Gunning Logic"
Cohesion: 0.31
Nodes (8): buildUI(), disconnect(), generateZones(), makeLabel(), makePill(), showFeedback(), StapleGunning.Cleanup(), StapleGunning.Start()

### Community 8 - "Location Manager"
Cohesion: 0.27
Nodes (5): colorizeClone(), colorizeSlot(), getDamagedVariants(), LocationManager.Assign(), pickRandom()

### Community 9 - "Foam Padding Logic"
Cohesion: 0.38
Nodes (7): cellBounds(), copyCells(), disconnect(), FoamPadding.Cleanup(), FoamPadding.Start(), generateMold(), rotateCW()

### Community 10 - "Tack Removal Logic"
Cohesion: 0.33
Nodes (6): disconnect(), makeLabel(), makePill(), showHitText(), TackRemoval.Cleanup(), TackRemoval.Start()

### Community 11 - "Gameplay Client HUD"
Cohesion: 0.32
Nodes (3): irisClose(), irisFullSize(), irisOpen()

### Community 12 - "Job Board UI"
Cohesion: 0.70
Nodes (4): clearCards(), populateBoard(), refreshBoard(), splitCamelCase()

### Community 14 - "Admin Panel UI"
Cohesion: 1.00
Nodes (3): corner(), make(), makeDropdown()

## Knowledge Gaps
- **25 isolated node(s):** `PreToolUse`, `allow`, `name`, `$className`, `$path` (+20 more)
  These have ≤1 connection - possible missing edges or undocumented components.
- **3 thin communities (<3 nodes) omitted from report** — run `graphify query` to explore isolated nodes.

## Suggested Questions
_Questions this graph is uniquely positioned to answer:_

- **Why does `Minigames System` connect `Minigame Modules` to `Core Client Scripts`?**
  _High betweenness centrality (0.016) - this node is a cross-community bridge._
- **Why does `Core Gameplay Loop` connect `Core Client Scripts` to `Minigame Modules`?**
  _High betweenness centrality (0.012) - this node is a cross-community bridge._
- **What connects `PreToolUse`, `allow`, `name` to the rest of the system?**
  _28 weakly-connected nodes found - possible documentation gaps or missing edges._
- **Should `Project Config` be split into smaller, more focused modules?**
  _Cohesion score 0.06896551724137931 - nodes in this community are weakly interconnected._
- **Should `Core Client Scripts` be split into smaller, more focused modules?**
  _Cohesion score 0.1111111111111111 - nodes in this community are weakly interconnected._
- **Should `Job Pool & Talkogram` be split into smaller, more focused modules?**
  _Cohesion score 0.14705882352941177 - nodes in this community are weakly interconnected._