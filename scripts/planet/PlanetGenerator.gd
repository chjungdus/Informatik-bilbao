## PlanetGenerator.gd
## Procedurally generates terrain regions distributed across the planet sphere.
## Uses FastNoiseLite to determine terrain type at each location.
class_name PlanetGenerator
extends RefCounted

# ---------------------------------------------------------------------------
# Configuration
# ---------------------------------------------------------------------------
var planet_radius:    float = 10.0
var region_count:     int   = 120     ## Total regions to scatter on the sphere
var noise_seed:       int   = 42
var noise_scale:      float = 1.8

var _noise: FastNoiseLite

# ---------------------------------------------------------------------------
# Constructor
# ---------------------------------------------------------------------------
func _init(radius: float = 10.0, seed_val: int = 0) -> void:
	planet_radius = radius
	noise_seed    = seed_val if seed_val != 0 else randi()
	_build_noise()


func _build_noise() -> void:
	_noise             = FastNoiseLite.new()
	_noise.seed        = noise_seed
	_noise.noise_type  = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	_noise.frequency   = 0.35
	_noise.fractal_octaves = 4

# ---------------------------------------------------------------------------
# Generation Entry Point
# ---------------------------------------------------------------------------

## Returns an Array of PlanetRegion objects covering the planet surface.
func generate_regions() -> Array:
	var regions: Array = []
	var used_positions: Array = []

	# Generate points using Fibonacci sphere for even distribution
	var points := _fibonacci_sphere(region_count)

	for i in range(points.size()):
		var point: Vector3 = points[i] * planet_radius
		var type:  int     = _sample_terrain_type(point)
		var reg    := PlanetRegion.new(i, type, point, _region_radius_for_type(type))
		reg.temperature    = _sample_temperature(point)
		reg.fertility      = _sample_fertility(point, type)
		regions.append(reg)

	return regions


## Returns a subset of regions that are valid city spawn locations.
func get_city_spawn_candidates(regions: Array) -> Array:
	var candidates: Array = []
	for reg in regions:
		if GameData.CITY_SPAWNABLE.get(reg.region_type, false):
			candidates.append(reg)
	return candidates

# ---------------------------------------------------------------------------
# Terrain Sampling
# ---------------------------------------------------------------------------

## Determine terrain type from noise and altitude (y component).
func _sample_terrain_type(world_pos: Vector3) -> int:
	var n   := _noise_at(world_pos)       # –1 .. 1  → remapped 0..1 below
	var t   := (n + 1.0) * 0.5            # 0..1
	var lat := world_pos.normalized().y   # –1 (S pole) .. 1 (N pole)
	var abs_lat := absf(lat)

	# Ice caps near poles
	if abs_lat > 0.75:
		return GameData.RegionType.ICE

	# Near equator, warmer terrain
	if abs_lat < 0.15 and t > 0.55:
		return GameData.RegionType.DESERT

	# Standard terrain based on noise height
	if t < 0.38:
		return GameData.RegionType.OCEAN
	elif t < 0.52:
		return GameData.RegionType.LAND
	elif t < 0.64:
		return GameData.RegionType.FOREST
	elif t < 0.76:
		return GameData.RegionType.MOUNTAIN
	elif t < 0.88:
		return GameData.RegionType.TUNDRA
	else:
		# High noise peaks → volcanic hot spots (rare)
		return GameData.RegionType.VOLCANIC


func _sample_temperature(world_pos: Vector3) -> float:
	var lat     := world_pos.normalized().y   # –1..1
	var base_t  := 25.0 - absf(lat) * 55.0   # equator 25°C, poles -30°C
	var noise_t := _noise_at(world_pos * 1.3) * 5.0
	return base_t + noise_t


func _sample_fertility(world_pos: Vector3, region_type: int) -> float:
	match region_type:
		GameData.RegionType.FOREST:  return randf_range(0.7, 1.0)
		GameData.RegionType.LAND:    return randf_range(0.4, 0.8)
		GameData.RegionType.DESERT:  return randf_range(0.1, 0.3)
		GameData.RegionType.TUNDRA:  return randf_range(0.1, 0.25)
		_:                           return 0.0


func _noise_at(pos: Vector3) -> float:
	return _noise.get_noise_3d(
		pos.x * noise_scale,
		pos.y * noise_scale,
		pos.z * noise_scale
	)


func _region_radius_for_type(region_type: int) -> float:
	match region_type:
		GameData.RegionType.OCEAN:   return 2.2
		GameData.RegionType.MOUNTAIN: return 1.1
		_:                            return 1.6

# ---------------------------------------------------------------------------
# Fibonacci Sphere — evenly distributed points on unit sphere
# ---------------------------------------------------------------------------

## Generates `n` approximately uniformly distributed directions on the unit sphere.
static func _fibonacci_sphere(n: int) -> Array:
	var points: Array = []
	var golden_ratio := (1.0 + sqrt(5.0)) * 0.5
	for i in range(n):
		var theta := TAU * float(i) / golden_ratio
		var phi   := acos(1.0 - 2.0 * (float(i) + 0.5) / float(n))
		points.append(Vector3(
			sin(phi) * cos(theta),
			cos(phi),
			sin(phi) * sin(theta)
		))
	return points
