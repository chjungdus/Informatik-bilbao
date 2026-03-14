## CityAI.gd
## Higher-level AI decision-making for cities.
## Runs periodic strategic logic: expansion, diplomacy, defense upgrades.
## Attached to the CivilizationManager (not individual City nodes).
extends Node
class_name CityAI

# ---------------------------------------------------------------------------
# Configuration
# ---------------------------------------------------------------------------
@export var expansion_check_interval: float = 20.0   ## seconds between expansion checks
@export var max_cities_per_ai_run:    int   = 2       ## how many new cities can spawn per tick

var civilization_manager: Node   ## CivilizationManager reference
var planet:               Planet

var _expansion_timer: float = 0.0

# ---------------------------------------------------------------------------
# Ready
# ---------------------------------------------------------------------------
func _ready() -> void:
	set_process(true)


func initialize(civ_manager: Node, planet_node: Planet) -> void:
	civilization_manager = civ_manager
	planet               = planet_node

# ---------------------------------------------------------------------------
# Per-Frame
# ---------------------------------------------------------------------------
func _process(delta: float) -> void:
	var dt := delta * GameManager.game_speed
	_expansion_timer += dt
	if _expansion_timer >= expansion_check_interval:
		_expansion_timer = 0.0
		_run_expansion_logic()

# ---------------------------------------------------------------------------
# Expansion Logic
# ---------------------------------------------------------------------------

func _run_expansion_logic() -> void:
	if not is_instance_valid(civilization_manager):
		return

	var cities: Array = civilization_manager.get_all_cities()
	var spawned := 0

	for city: City in cities:
		if spawned >= max_cities_per_ai_run:
			break
		if city.is_collapsed:
			continue
		if city.population >= 200_000 and city.tech_level >= 5.0:
			if _try_found_new_city(city):
				spawned += 1


func _try_found_new_city(parent_city: City) -> bool:
	# Pick a nearby random surface position
	var spawn_candidates: Array = planet.get_city_spawn_positions()
	if spawn_candidates.is_empty():
		return false

	# Filter to candidates not too close to existing cities
	var existing: Array   = civilization_manager.get_all_cities()
	var valid:    Array   = []

	for region: PlanetRegion in spawn_candidates:
		var world_pos: Vector3 = planet.to_global(region.surface_position)
		var too_close          := false

		for existing_city: City in existing:
			if existing_city.global_position.distance_to(world_pos) < 2.5:
				too_close = true
				break

		if not too_close:
			valid.append(region)

	if valid.is_empty():
		return false

	# Pick one near the parent city
	valid.sort_custom(func(a: PlanetRegion, b: PlanetRegion) -> bool:
		var pa := planet.to_global(a.surface_position)
		var pb := planet.to_global(b.surface_position)
		return pa.distance_to(parent_city.global_position) < \
		       pb.distance_to(parent_city.global_position)
	)

	# Select from the closest third
	var pool_size := maxi(1, valid.size() / 3)
	var region: PlanetRegion = valid[randi() % pool_size]
	var spawn_pos: Vector3   = planet.to_global(region.surface_position)

	civilization_manager.spawn_city_at(spawn_pos, region.region_type, parent_city.city_name)
	return true

# ---------------------------------------------------------------------------
# Disaster Response Coordinator
# ---------------------------------------------------------------------------

## Called by CivilizationManager when a disaster occurs.
## Coordinates cross-city emergency response.
func on_disaster_event(disaster_type: String, world_pos: Vector3) -> void:
	var cities: Array = civilization_manager.get_all_cities()

	match disaster_type:
		"SOLAR_FLARE":
			# Cities with defense guns try to shoot down future threats
			for city: City in cities:
				if city.has_defense_gun and not city.is_collapsed:
					print("CityAI: %s activates defense systems vs Solar Flare!" % city.city_name)

		"METEOR_STRIKE":
			# Nearby undamaged cities send aid to damaged neighbours
			for city: City in cities:
				if city.is_collapsed:
					_coordinate_aid(city, cities)

		"PLANET_CRACK":
			# All cities panic
			for city: City in cities:
				if not city.is_collapsed and city.tech_level < 30.0:
					city.population = int(float(city.population) * 0.5)
					print("CityAI: %s panics due to Planet Crack!" % city.city_name)


func _coordinate_aid(collapsed_city: City, all_cities: Array) -> void:
	var closest_helper: City = null
	var best_dist             := INF

	for other: City in all_cities:
		if other == collapsed_city or other.is_collapsed:
			continue
		if other.tech_level < 10.0:
			continue
		var d := other.global_position.distance_to(collapsed_city.global_position)
		if d < best_dist:
			best_dist      = d
			closest_helper = other

	if closest_helper and best_dist < 5.0:
		# Helper speeds up rebuild
		collapsed_city.rebuild_time = maxf(10.0, collapsed_city.rebuild_time - 10.0)
		print("CityAI: %s sends aid to %s." % [closest_helper.city_name, collapsed_city.city_name])
