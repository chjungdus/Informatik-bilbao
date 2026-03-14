# PLANET DESTROYER: GOD OF CATASTROPHES

> *You are a cosmic entity. The planet is yours to nurture — or annihilate.*

A procedurally-generated, emergent sandbox simulation built in **Godot 4**.
Civilizations rise and fall as you unleash cosmic powers upon a living, breathing world.

---

## GAME DESIGN OVERVIEW

### Core Fantasy
The player exists outside time and space — an omnipotent god observing a planet
evolve from primordial rock into a flourishing civilization. At any moment, you can
intervene: seed life, trigger cataclysm, or simply watch entropy do its work.

### Emergent Gameplay Loop
```
Planet generates → Biosphere stabilizes → Cities spawn → Tech advances
       ↓                                                        ↓
  Player observes ←←←←←←←←← Disasters reshape world ←←←←←← Cities respond
```

---

## TECHNICAL ARCHITECTURE

### System Map

```
Main.gd (Node3D — root orchestrator)
│
├── GameManager.gd         [Autoload] Central state: energy, abilities, cooldowns
├── GameData.gd            [Autoload] Shared constants, enums, utility functions
│
├── WorldEnvironment       Godot environment node (glow, tone-mapping, ambient)
├── DirectionalLight3D     Sun lighting
│
├── Planet (Node3D)        [Planet.gd]
│   ├── PlanetMesh         Procedural SphereMesh + surface shader
│   ├── AtmosphereMesh     Rim-lit transparent shell
│   └── CitiesContainer    Parent for all City nodes (rotates with planet)
│       └── City_N (Node3D) [City.gd] × 8–60 instances
│
├── CivilizationManager    [CivilizationManager.gd]
│   └── CityAI             [CityAI.gd] Strategic AI coordinator
│
├── DisasterManager        [DisasterManager.gd]
│   └── (spawns temporary Meteor, BlackHole, etc. nodes at runtime)
│
├── EffectsManager         [EffectsManager.gd]
│   └── (spawns MeshInstance3D / OmniLight3D effect nodes at runtime)
│
├── OrbitCamera (Camera3D) [OrbitCamera.gd]
│   └── (manages orbit, zoom, click detection, screen shake)
│
└── GameUI (CanvasLayer)   [GameUI.gd]
    ├── StatsPanel         Planet health/atmosphere/biosphere bars
    ├── AbilityPanel       8 ability buttons with cooldown indicators
    ├── NotificationPanel  Real-time event feed
    └── SpeedControls      Game speed (0.5×, 1×, 2×, 4×) + pause
```

### Data Flow

```
Player clicks ability button
    → GameManager.select_ability()       [state = TARGETING]
    → OrbitCamera detects left-click
    → GameManager.trigger_at_position()  [fires disaster_triggered signal]
    → DisasterManager._on_disaster_triggered()
        ├── Spawns visual effect (meteor node, black hole, etc.)
        ├── _apply_zone_damage() → City.on_disaster_hit() × N cities
        ├── Planet.apply_health_damage() etc.
        └── EffectsManager creates particle-like mesh effects
    → GameUI receives planet/city signals → updates HUD
```

---

## PROJECT FOLDER STRUCTURE

```
project.godot                   Godot project entry point
icon.svg                        Game icon (SVG)
README.md                       This file
data/
  game_config.json              Tunable gameplay parameters
effects/
  shaders/
    planet_surface.gdshader     Procedural terrain (noise-based biomes + damage)
    atmosphere.gdshader         Rim-glow translucent atmosphere
    lava_glow.gdshader          Animated lava pool effect
    city_pulse.gdshader         City heartbeat glow
scenes/
  Main.tscn                     Root scene (bootstraps everything via Main.gd)
scripts/
  Main.gd                       Scene orchestrator and system wiring
  managers/
    GameManager.gd              [Autoload] Ability selection, energy, cooldowns
  data/
    GameData.gd                 [Autoload] Constants, enums, utility functions
  planet/
    Planet.gd                   Planet attributes, visuals, disaster zones
    PlanetGenerator.gd          Procedural region generation (Fibonacci sphere)
    PlanetRegion.gd             Individual terrain region data class
  civilization/
    CivilizationManager.gd      City lifecycle management
    City.gd                     Per-city simulation (growth, disasters, tech)
    CityAI.gd                   Strategic AI (expansion, aid, defense)
  disasters/
    DisasterManager.gd          Routes triggers → damage application
  camera/
    OrbitCamera.gd              3D orbit camera with raycast targeting
  effects/
    EffectsManager.gd           Runtime visual effects (explosions, lava, etc.)
  ui/
    GameUI.gd                   Full HUD built programmatically
ui/
  styles/                       (reserved for future UI theme files)
```

---

## SCENE SETUP

The entire scene hierarchy is **built programmatically** in `Main.gd._ready()`.
This means `Main.tscn` contains only a single root node — all systems are
instantiated at runtime in the correct dependency order:

1. `WorldEnvironment` + lights (environment baseline)
2. `Planet` (generates terrain regions, builds mesh + shader)
3. `EffectsManager` (must exist before DisasterManager connects to it)
4. `DisasterManager` (connects to GameManager signals)
5. `CivilizationManager` (spawns initial cities on valid planet regions)
6. `OrbitCamera` (targets the Planet node)
7. `GameUI` (connects to Planet + CivManager for live stats)
8. Cross-system connections (camera shake, notifications, etc.)

---

## FULL SCRIPT IMPLEMENTATIONS

| Script | Lines | Responsibility |
|--------|-------|----------------|
| `GameManager.gd` | ~160 | Autoload: game state, energy, ability dispatch |
| `GameData.gd` | ~120 | Autoload: enums, constants, utility statics |
| `Main.gd` | ~140 | Root: boot, wire all systems |
| `Planet.gd` | ~280 | Planet simulation + procedural visuals |
| `PlanetGenerator.gd` | ~130 | Fibonacci sphere + noise-based biome assignment |
| `PlanetRegion.gd` | ~100 | Terrain region data, effect state |
| `CivilizationManager.gd` | ~175 | City spawning, stats aggregation |
| `City.gd` | ~270 | Per-city simulation, disaster response, tech milestones |
| `CityAI.gd` | ~120 | Strategic AI: expansion, aid coordination |
| `DisasterManager.gd` | ~220 | Ability routing, zone damage, effects |
| `OrbitCamera.gd` | ~200 | Orbit, zoom, drag, ray-sphere intersection |
| `EffectsManager.gd` | ~260 | Runtime mesh/light effects |
| `GameUI.gd` | ~360 | Full HUD construction + stat updates |

---

## EXAMPLE DATA STRUCTURES

### Planet Attributes
```gdscript
planet.planet_health     # float 0–100
planet.atmosphere_level  # float 0–100
planet.temperature       # float °C (-100 to 100)
planet.tectonic_activity # float 0–100
planet.biosphere_level   # float 0–100
```

### City State
```gdscript
city.population      # int 0–100,000,000
city.tech_level      # float 1–100
city.defense_level   # float 1–100
city.culture_level   # float 1–100
city.is_collapsed    # bool
city.has_shield      # bool (unlocked at tech >= 35)
city.has_satellite   # bool (unlocked at tech >= 20)
city.has_defense_gun # bool (unlocked at tech >= 50)
```

### PlanetRegion
```gdscript
region.region_id         # int
region.region_type       # GameData.RegionType enum
region.surface_position  # Vector3 (local to planet)
region.radius            # float (influence radius)
region.temperature       # float °C
region.fertility         # float 0–1
region.is_on_fire        # bool
region.is_frozen         # bool
region.has_lava          # bool
region.radiation_level   # float 0–100
```

### Ability Definition
```gdscript
GameManager.ABILITIES["METEOR_STRIKE"] = {
    "name":         "Meteor Strike",
    "description":  "Hurl a massive meteor at the planet surface.",
    "cooldown":     5.0,
    "energy_cost":  20.0,
    "color":        Color(1.0, 0.4, 0.1),
    "icon":         "☄"
}
```

---

## HOW TO RUN IN GODOT 4

### Prerequisites
- Godot Engine 4.2 or later (download from https://godotengine.org)
- No additional plugins required

### Steps

1. **Open Godot** → Click **"Import"**
2. Navigate to the project folder and select **`project.godot`**
3. Click **"Import & Edit"** — Godot will import all resources automatically
4. If shader UIDs warn about mismatches, click **"Fix"** (safe to ignore)
5. Press **F5** (or the ▶ Play button) to run the game

### First Launch Notes
- The planet generates a random seed on each run (different terrain each time)
- 8 cities spawn automatically on valid land regions
- Give the simulation ~10–15 in-game seconds to stabilise before striking

---

## CONTROLS

| Input | Action |
|-------|--------|
| Right-drag mouse | Rotate camera around planet |
| Scroll wheel | Zoom in / out |
| Left-click (ability selected) | Trigger ability at clicked point |
| ESC | Cancel targeting |
| Keys 1–8 | Quick-select abilities |
| SPACE | Toggle pause |
| +/- | Speed up / slow down time |

---

## ABILITY REFERENCE

| # | Ability | Energy | Cooldown | Effect |
|---|---------|--------|----------|--------|
| 1 | Meteor Strike | 20 | 5s | Impact crater, kills nearby cities |
| 2 | Volcanic Eruption | 30 | 8s | Lava spread, CO₂ release, temp +3° |
| 3 | Earthquake | 25 | 6s | Tectonic stress, wide city damage |
| 4 | Climate Shift | 35 | 12s | Temperature swing ±10°C |
| 5 | Ice Age | 60 | 25s | Global freeze, biosphere collapse |
| 6 | Solar Flare | 45 | 15s | Destroys satellites, kills tech |
| 7 | Black Hole | 80 | 30s | Sustained gravitational destruction |
| 8 | Planet Crack | 200 | 120s | **ULTIMATE** — Tears the planet apart |

---

## EXPANSION IDEAS

### Simulation Depth
- **Plate tectonics**: Full plate movement simulation driving mountain building
- **Water cycle**: Rainfall, rivers, and drought mechanics affecting biosphere
- **Species evolution**: Procedural creature types that mutate and migrate
- **Religion system**: Cities develop belief systems influencing culture and cooperation
- **Trade routes**: Cities form economic links that boost tech/culture exchange
- **Space age**: Advanced civs build rockets, colony ships, and off-planet outposts

### Catastrophe Expansion
- **Asteroid belt**: Random meteor showers independent of player action
- **Gamma Ray Burst**: Directional radiation kills half the planet
- **Rogue Planet Collision**: Complete planetary destruction cinema
- **Alien Invasion**: Extraterrestrial fleet attacks the civilization
- **Divine Plague**: Biological catastrophe spreading between cities
- **Magnetic Pole Reversal**: Disrupts all electronic-age tech globally

### Visual & World Quality
- **Procedural cloud layer**: Dynamic cloud shell animated by wind currents
- **Night side glow**: City lights visible on the dark hemisphere
- **Dynamic seasons**: Axial tilt drives real seasonal biome shifts
- **Ocean currents**: Heat distribution model affecting regional climates
- **Volcanic archipelagos**: Islands rise from ocean eruptions over time

---

## MULTIPLAYER — MULTIPLE GODS

### Cooperative Mode
- 2–4 gods share the same planet
- Each god has a separate energy pool and personal cooldowns
- Gods vote on planet fate via UI
- Shared leaderboard: who caused the most devastation

### Competitive Mode
- Each god secretly assigned an objective (Destroyer / Nurturer / Corruptor)
- Gods can target each other's city favorites
- First to achieve objective wins the epoch
- Match lasts until planet health < 10% or one god's civilization goes extinct

### Asynchronous God Mode
- Steam: leave a "curse" on the planet; friend joins and inherits the state
- Persistent world, 24-hour ticks, mobile push notifications

---

## STEAM RELEASE IDEAS

### Core Steam Features
- **Achievement system**: "First Mass Extinction", "Nurturing God", "Planet Cracker"
- **Steam Workshop**: Share procedural planet seeds; others can play your exact world
- **Trading cards**: Each cosmic power as a collectible card with lore text
- **Leaderboards**: Most population killed in one meteor strike; highest civilization reached
- **Cloud saves**: Planet state saved online, continue on any PC

### DLC Concepts
- **Alien Worlds Pack**: Different planet types (gas giant rings, binary star orbit)
- **History Mode**: Preset scenarios based on Earth's mass extinction events
- **Creator Mode**: Place terrain, set city locations, build custom disaster chains
- **God Skins**: Visual re-skins (Lovecraftian Elder God, Greek Pantheon, Robot AI)

### Monetization (ethical)
- Base game: full sandbox with all 8 abilities
- DLC: additional planet types, disaster packs, visual themes
- NO pay-to-win, NO energy microtransactions

---

## PROCEDURAL PLANET GENERATION IDEAS

### Tectonic Simulation
- Generate N tectonic plates as Voronoi cells on the sphere
- Plates drift at random velocities
- Collision zones → mountain ranges; divergent zones → rift valleys + volcanism
- Run simulation for N steps before game start = emergent terrain

### Multi-Layer Noise Pipeline
```
Layer 1: Continental mask (low-freq simplex) → land/ocean split
Layer 2: Mountain noise (high-freq, masked to land) → peaks
Layer 3: Humidity noise → desert vs forest within land
Layer 4: Temperature gradient (latitude-based) → ice caps + tropics
Layer 5: Volcanic hotspot mask (rare high peaks) → volcanoes
Layer 6: Erosion pass (blur + slope cutoff) → realistic coastlines
```

### Biome Matrix (temperature × humidity)
```
              Cold    Temperate    Hot
  Arid:       Tundra   Steppe      Desert
  Moderate:   Taiga    Grassland   Savanna
  Humid:      Boreal   Forest      Rainforest
```

### Special Planet Types
- **Ocean World**: 90% ocean, scattered volcanic island chains
- **Desert World**: Scarce water, massive dune seas, dust storms
- **Ice Planet**: Thick ice sheets, liquid subsurface oceans (hidden life?)
- **Volcanic World**: Young planet, constant eruption, no stable biosphere yet
- **Twin Planets**: Two worlds in close orbit, civilizations can eventually communicate

---

*Built with Godot 4 · GDScript · Forward+ Renderer*
*Architecture: Modular Manager Pattern · Emergent AI · Procedural Generation*
