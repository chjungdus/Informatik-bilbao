## PlanetRegion.gd
## Data class representing a discrete terrain region on the planet surface.
## Regions are stored as data objects (not scene nodes) for performance.
## Each region occupies a zone centred on `surface_position`.
class_name PlanetRegion
extends RefCounted

# ---------------------------------------------------------------------------
# Properties
# ---------------------------------------------------------------------------
var region_id:        int                   ## Unique identifier
var region_type:      int                   ## GameData.RegionType
var surface_position: Vector3              ## World-space point on planet surface
var radius:           float  = 1.5        ## Influence radius in world units
var temperature:      float  = 15.0
var fertility:        float  = 1.0        ## 0..1 — affects city growth
var is_on_fire:       bool   = false
var is_frozen:        bool   = false
var has_lava:         bool   = false
var radiation_level:  float  = 0.0       ## 0..100
var active_effects:   Array  = []         ## list of effect name strings

# ---------------------------------------------------------------------------
# Constructor
# ---------------------------------------------------------------------------
func _init(id: int, type: int, pos: Vector3, rad: float = 1.5) -> void:
	region_id        = id
	region_type      = type
	surface_position = pos
	radius           = rad

# ---------------------------------------------------------------------------
# State Queries
# ---------------------------------------------------------------------------

## Returns true if the given world position overlaps this region.
func contains_point(point: Vector3) -> bool:
	return surface_position.distance_to(point) <= radius


## Returns the base Color for this region type (unaffected by disasters).
func get_base_color() -> Color:
	return GameData.REGION_COLORS.get(region_type, Color.GRAY)


## Damage modifier: disasters deal extra damage to already-stressed regions.
func get_damage_multiplier() -> float:
	var mult := 1.0
	if is_on_fire:    mult += 0.3
	if has_lava:      mult += 0.5
	if is_frozen:     mult += 0.2
	if radiation_level > 50.0: mult += 0.4
	return mult

# ---------------------------------------------------------------------------
# Status Mutations
# ---------------------------------------------------------------------------

func apply_fire() -> void:
	is_on_fire  = true
	has_lava    = false   # lava supersedes fire
	if "fire" not in active_effects:
		active_effects.append("fire")


func apply_lava() -> void:
	has_lava    = true
	is_on_fire  = false
	if "lava" not in active_effects:
		active_effects.append("lava")
	active_effects.erase("fire")


func apply_freeze() -> void:
	is_frozen   = true
	is_on_fire  = false
	has_lava    = false
	active_effects.erase("fire")
	active_effects.erase("lava")
	if "freeze" not in active_effects:
		active_effects.append("freeze")


func apply_radiation(amount: float) -> void:
	radiation_level = minf(radiation_level + amount, 100.0)
	if "radiation" not in active_effects:
		active_effects.append("radiation")


func clear_effects() -> void:
	is_on_fire     = false
	is_frozen      = false
	has_lava       = false
	radiation_level = 0.0
	active_effects.clear()


## Natural recovery tick — called by Planet every N seconds.
func tick_recovery(dt: float) -> void:
	if radiation_level > 0.0:
		radiation_level = maxf(0.0, radiation_level - dt * 2.0)
		if radiation_level <= 0.0:
			active_effects.erase("radiation")

	# Lava and fire have their own durations managed by EffectsManager;
	# region just reflects state set by the manager.


## Returns a serializable dictionary for debugging or save systems.
func to_dict() -> Dictionary:
	return {
		"region_id":       region_id,
		"region_type":     region_type,
		"surface_position": {"x": surface_position.x, "y": surface_position.y, "z": surface_position.z},
		"radius":          radius,
		"temperature":     temperature,
		"fertility":       fertility,
		"is_on_fire":      is_on_fire,
		"is_frozen":       is_frozen,
		"has_lava":        has_lava,
		"radiation_level": radiation_level
	}
