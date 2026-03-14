## GameData.gd
## Autoload Singleton — Shared constants, enums, and data structures
## used throughout the entire game. Acts as a typed data registry.
extends Node

# ---------------------------------------------------------------------------
# Region Types — determines terrain color and disaster interaction
# ---------------------------------------------------------------------------
enum RegionType {
	OCEAN,
	LAND,
	MOUNTAIN,
	VOLCANIC,
	ICE,
	DESERT,
	FOREST,
	TUNDRA
}

# Visual colors per region type (used by terrain shader)
const REGION_COLORS: Dictionary = {
	RegionType.OCEAN:    Color(0.08, 0.25, 0.65, 1.0),
	RegionType.LAND:     Color(0.22, 0.55, 0.18, 1.0),
	RegionType.MOUNTAIN: Color(0.50, 0.45, 0.38, 1.0),
	RegionType.VOLCANIC: Color(0.55, 0.10, 0.02, 1.0),
	RegionType.ICE:      Color(0.80, 0.92, 1.00, 1.0),
	RegionType.DESERT:   Color(0.85, 0.73, 0.38, 1.0),
	RegionType.FOREST:   Color(0.08, 0.38, 0.10, 1.0),
	RegionType.TUNDRA:   Color(0.60, 0.70, 0.65, 1.0)
}

# Whether cities can spawn on a given region type
const CITY_SPAWNABLE: Dictionary = {
	RegionType.OCEAN:    false,
	RegionType.LAND:     true,
	RegionType.MOUNTAIN: false,
	RegionType.VOLCANIC: false,
	RegionType.ICE:      false,
	RegionType.DESERT:   true,
	RegionType.FOREST:   true,
	RegionType.TUNDRA:   false
}

# ---------------------------------------------------------------------------
# City data template — spawned city starts with these values
# ---------------------------------------------------------------------------
const CITY_DEFAULT: Dictionary = {
	"population":       1000,
	"tech_level":       1.0,
	"defense_level":    1.0,
	"culture_level":    1.0,
	"growth_rate":      0.02,    # population multiplier per game-second
	"tech_growth":      0.001,
	"defense_growth":   0.0005,
	"culture_growth":   0.0008,
	"is_collapsed":     false,
	"rebuild_timer":    0.0,
	"rebuild_time":     30.0,    # seconds to rebuild after collapse
	"has_shield":       false,
	"has_satellite":    false,
	"has_defense_gun":  false
}

# ---------------------------------------------------------------------------
# Planet attribute defaults
# ---------------------------------------------------------------------------
const PLANET_DEFAULT: Dictionary = {
	"planet_health":     100.0,
	"atmosphere_level":  100.0,
	"temperature":       15.0,   # Celsius baseline
	"tectonic_activity": 20.0,   # 0–100
	"biosphere_level":   75.0,
	"max_health":        100.0
}

# ---------------------------------------------------------------------------
# Disaster effect radii and damage values
# ---------------------------------------------------------------------------
const DISASTER_PARAMS: Dictionary = {
	"METEOR_STRIKE": {
		"impact_radius":    2.0,   # world units
		"city_damage":      0.6,   # fraction of population killed in radius
		"health_damage":    8.0,
		"atmosphere_loss":  2.0,
		"tectonic_boost":   5.0,
		"crater_duration":  60.0
	},
	"VOLCANIC_ERUPTION": {
		"impact_radius":    3.0,
		"city_damage":      0.5,
		"health_damage":    6.0,
		"atmosphere_loss":  5.0,
		"temp_increase":    3.0,
		"lava_duration":    45.0
	},
	"EARTHQUAKE": {
		"impact_radius":    4.0,
		"city_damage":      0.4,
		"health_damage":    5.0,
		"tectonic_boost":   15.0,
		"shake_duration":   3.0
	},
	"CLIMATE_SHIFT": {
		"temp_delta":        10.0,  # can be + or –
		"biosphere_loss":    5.0,
		"health_damage":     3.0,
		"duration":          20.0
	},
	"ICE_AGE": {
		"temp_delta":        -30.0,
		"biosphere_loss":    30.0,
		"health_damage":     15.0,
		"duration":          60.0,
		"city_damage":       0.3
	},
	"SOLAR_FLARE": {
		"atmosphere_loss":   10.0,
		"city_tech_loss":    0.5,   # fraction of tech level lost
		"biosphere_loss":    8.0,
		"health_damage":     5.0,
		"duration":          15.0
	},
	"BLACK_HOLE": {
		"impact_radius":    5.0,
		"city_damage":      0.8,
		"health_damage":    20.0,
		"atmosphere_loss":  15.0,
		"duration":         10.0
	},
	"PLANET_CRACK": {
		"impact_radius":    20.0,
		"city_damage":      1.0,
		"health_damage":    60.0,
		"atmosphere_loss":  40.0,
		"tectonic_boost":   50.0,
		"duration":         30.0
	}
}

# ---------------------------------------------------------------------------
# Effect colors for visual feedback
# ---------------------------------------------------------------------------
const EFFECT_COLORS: Dictionary = {
	"explosion":  Color(1.0, 0.5, 0.1),
	"lava":       Color(1.0, 0.2, 0.0),
	"ice":        Color(0.7, 0.9, 1.0),
	"radiation":  Color(0.4, 1.0, 0.2),
	"gravity":    Color(0.6, 0.0, 1.0),
	"crack":      Color(0.3, 0.0, 0.0),
	"shield":     Color(0.3, 0.7, 1.0)
}

# ---------------------------------------------------------------------------
# Utility helpers
# ---------------------------------------------------------------------------

## Convert a 3D point on a unit sphere to (latitude, longitude) in radians.
static func world_to_latlon(surface_pos: Vector3, planet_radius: float) -> Vector2:
	var normalized := surface_pos.normalized()
	var lat := asin(normalized.y)                       # –π/2 .. π/2
	var lon := atan2(normalized.z, normalized.x)        # –π   .. π
	return Vector2(lat, lon)


## Convert (latitude, longitude) in radians to a 3D point on the sphere.
static func latlon_to_world(lat: float, lon: float, radius: float) -> Vector3:
	return Vector3(
		cos(lat) * cos(lon) * radius,
		sin(lat)             * radius,
		cos(lat) * sin(lon)  * radius
	)


## Clamp and normalize a 0..100 health value to a Color gradient (green→red).
static func health_to_color(health: float) -> Color:
	var t := clampf(health / 100.0, 0.0, 1.0)
	return Color(1.0 - t, t, 0.0)


## Returns a random point on the surface of a unit sphere.
static func random_sphere_point(radius: float) -> Vector3:
	var theta := randf() * TAU
	var phi   := acos(2.0 * randf() - 1.0)
	return Vector3(
		sin(phi) * cos(theta) * radius,
		cos(phi)              * radius,
		sin(phi) * sin(theta) * radius
	)
