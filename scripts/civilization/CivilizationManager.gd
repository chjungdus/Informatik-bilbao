## CivilizationManager.gd
## Manages all city instances on the planet.
## Handles city spawning, global population stats, and disaster notification routing.
extends Node
class_name CivilizationManager

# ---------------------------------------------------------------------------
# Signals
# ---------------------------------------------------------------------------
signal city_spawned(city: City)
signal city_lost(city: City)
signal total_population_changed(new_total: int)
signal civilization_extinct()

# ---------------------------------------------------------------------------
# Configuration
# ---------------------------------------------------------------------------
@export var initial_city_count:   int   = 8
@export var max_cities:           int   = 60
@export var city_prefab_path:     String = ""   ## unused – cities built procedurally

# ---------------------------------------------------------------------------
# State
# ---------------------------------------------------------------------------
var _cities:      Array  = []    ## Array[City]
var _planet:      Planet
var _city_ai:     CityAI
var _city_scene:  PackedScene

var _total_population: int  = 0
var _stats_timer:      float = 0.0

# City name syllables for procedural naming
const _NAME_PARTS_A: Array = [
	"Al", "Bri", "Cor", "Dor", "El", "Far", "Gor",
	"Hal", "Ir", "Jer", "Kal", "Lor", "Mor", "Nor",
	"Or", "Pel", "Qur", "Ros", "Sol", "Tar", "Ul",
	"Ver", "Wyr", "Xan", "Yor", "Zan"
]
const _NAME_PARTS_B: Array = [
	"ath", "bor", "dan", "eth", "fen", "gor", "hel",
	"ian", "jon", "kin", "lon", "mir", "noth", "oth",
	"por", "quen", "rath", "ston", "than", "ule",
	"ven", "woth", "xia", "yon", "zen"
]

# ---------------------------------------------------------------------------
# Ready
# ---------------------------------------------------------------------------
func _ready() -> void:
	pass  # Initialized by Main.gd via initialize()


func initialize(planet_node: Planet) -> void:
	_planet  = planet_node
	_city_ai = CityAI.new()
	_city_ai.name = "CityAI"
	add_child(_city_ai)
	_city_ai.initialize(self, planet_node)

	_spawn_initial_cities()
	GameManager.disaster_triggered.connect(_on_disaster_triggered)

# ---------------------------------------------------------------------------
# Per-Frame
# ---------------------------------------------------------------------------
func _process(delta: float) -> void:
	_stats_timer += delta * GameManager.game_speed
	if _stats_timer >= 2.0:
		_stats_timer = 0.0
		_recalculate_totals()

# ---------------------------------------------------------------------------
# Initial Spawning
# ---------------------------------------------------------------------------
func _spawn_initial_cities() -> void:
	var candidates: Array = _planet.get_city_spawn_positions()
	candidates.shuffle()

	var count := mini(initial_city_count, candidates.size())
	for i in range(count):
		var region: PlanetRegion = candidates[i]
		var world_pos := _planet.to_global(region.surface_position)
		spawn_city_at(world_pos, region.region_type)

	print("CivilizationManager: Spawned %d initial cities." % _cities.size())

# ---------------------------------------------------------------------------
# City Spawning
# ---------------------------------------------------------------------------

## Spawn a new city at the given world-space position.
func spawn_city_at(world_pos: Vector3, region_type: int,
		founder_name: String = "") -> City:
	if _cities.size() >= max_cities:
		return null

	var city        := City.new()
	city.name        = "City_%d" % _cities.size()
	city.city_name   = _generate_city_name(founder_name)
	city.region_type = region_type
	city.planet_radius = _planet.planet_radius

	# Position on the planet surface, oriented outward
	var surface_pos  := _planet.project_to_surface(world_pos)
	var normal        := (surface_pos - _planet.global_position).normalized()
	city.surface_normal = normal

	# Place inside planet's cities container so it rotates with the planet
	var container: Node3D = _planet.get_node("CitiesContainer")
	container.add_child(city)

	# Local position = slightly above surface
	city.position = _planet.to_local(surface_pos) + normal * 0.05

	# Orient city upright relative to surface normal (local space)
	city.look_at(_planet.to_global(city.position + normal), Vector3.UP)

	# Connect signals
	city.city_destroyed.connect(_on_city_destroyed)
	city.city_rebuilt.connect(_on_city_rebuilt)

	_cities.append(city)
	_recalculate_totals()
	city_spawned.emit(city)

	print("CivilizationManager: Founded '%s' at %s (region: %d)" % [
		city.city_name, surface_pos, region_type])

	return city

# ---------------------------------------------------------------------------
# Public Queries
# ---------------------------------------------------------------------------
func get_all_cities() -> Array:
	return _cities.duplicate()


func get_active_cities() -> Array:
	return _cities.filter(func(c: City) -> bool: return not c.is_collapsed)


func get_total_population() -> int:
	return _total_population


func get_city_count() -> int:
	return _cities.size()


func get_active_city_count() -> int:
	var count := 0
	for c: City in _cities:
		if not c.is_collapsed:
			count += 1
	return count


func get_average_tech_level() -> float:
	if _cities.is_empty():
		return 0.0
	var total := 0.0
	for c: City in _cities:
		total += c.tech_level
	return total / float(_cities.size())


func get_stats_dict() -> Dictionary:
	return {
		"total_cities":   _cities.size(),
		"active_cities":  get_active_city_count(),
		"total_population": _total_population,
		"avg_tech":       get_average_tech_level()
	}

# ---------------------------------------------------------------------------
# Private Helpers
# ---------------------------------------------------------------------------
func _recalculate_totals() -> void:
	var old := _total_population
	_total_population = 0
	for city: City in _cities:
		_total_population += city.population
	if _total_population != old:
		total_population_changed.emit(_total_population)

	# Remove cities that have been freed
	_cities = _cities.filter(func(c: City) -> bool: return is_instance_valid(c))

	if get_active_city_count() == 0 and _cities.size() > 0:
		civilization_extinct.emit()


func _generate_city_name(founder_hint: String) -> String:
	var a    := _NAME_PARTS_A[randi() % _NAME_PARTS_A.size()]
	var b    := _NAME_PARTS_B[randi() % _NAME_PARTS_B.size()]
	var name := a + b
	if not founder_hint.is_empty() and randf() < 0.3:
		name = "New " + founder_hint.split(" ")[-1]
	return name

# ---------------------------------------------------------------------------
# Signal Callbacks
# ---------------------------------------------------------------------------
func _on_city_destroyed(city: City) -> void:
	city_lost.emit(city)
	_recalculate_totals()


func _on_city_rebuilt(city: City) -> void:
	_recalculate_totals()


func _on_disaster_triggered(disaster_type: String, world_pos: Vector3) -> void:
	_city_ai.on_disaster_event(disaster_type, world_pos)
